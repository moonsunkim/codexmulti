import Foundation
import XCTest
@testable import UpdaterKit

private final class FakeRuntime: @unchecked Sendable {
    let lock = NSRecursiveLock()
    let store: RuntimeStore
    let label: String
    let config: String
    var current: ServiceSnapshot?
    var healthValue: ProxyHealth?
    var bootouts = 0
    var bootstraps = 0
    var offWrites = 0
    var activations: [String] = []
    var failRuntime: String?
    var failAll = false
    var loseActivationReply = false
    var unreachable = false
    var nextPID: Int32 = 700
    var plistSHA = String(repeating: "c", count: 64)

    init(store: RuntimeStore, runtimeID: String, config: String, label: String) throws {
        self.store = store; self.config = config; self.label = label
        try install(runtimeID, gate: "serving")
    }

    func synchronized<T>(_ body: () throws -> T) rethrows -> T {
        lock.lock(); defer { lock.unlock() }; return try body()
    }

    func install(_ runtimeID: String, gate: String) throws {
        let app = try store.bundle(runtimeID)
        nextPID += 1
        current = ServiceSnapshot(label: label, arguments: RuntimeOperations.arguments(app: app, configPath: config),
            process: ProcessIdentity(pid: nextPID, start: "start-\(nextPID)",
                                     executable: app.appendingPathComponent("Contents/Helpers/node").path))
        healthValue = ProxyHealth(updateProtocol: 1, managed: true, runtimeID: runtimeID,
            bootID: UUID().uuidString.lowercased(), generation: try store.active()?.generation ?? 1,
            gate: gate, configRevision: String(repeating: "d", count: 64), configPath: config,
            work: ["http": 0, "websocket": 0, "renewal": 0, "control": 0], workTotal: 0, payloadVerified: true)
    }

    func busy(_ kind: String, _ count: Int) {
        synchronized {
            healthValue?.work[kind] = count
            let total = healthValue?.work.values.reduce(0, +) ?? 0
            healthValue?.workTotal = total
        }
    }

    func reply(_ action: String, _ command: ProxyCommand?) throws -> ProxyReply {
        try synchronized {
            guard !unreachable, var health = healthValue else { throw URLError(.cannotConnectToHost) }
            switch action {
            case "health": return ProxyReply(status: 200, health: health)
            case "prepare-if-idle":
                guard health.workTotal == 0 else { return ProxyReply(status: 409, health: health, error: "proxy_busy") }
                health.gate = "quiescent"
                health.lease = String(repeating: "e", count: 64)
            case "commit-stop": health.gate = "stopped"
            case "abort-prepare": health.gate = "serving"
            case "activate":
                XCTAssertEqual(try store.active()?.generation, command?.generation)
                XCTAssertEqual(try store.active()?.runtimeID, health.runtimeID)
                activations.append(health.runtimeID!)
                health.gate = "serving"
                health.generation = command!.generation!
                healthValue = health
                if loseActivationReply { loseActivationReply = false; throw URLError(.timedOut) }
            default: return ProxyReply(status: 404)
            }
            healthValue = health
            return ProxyReply(status: 200, health: health)
        }
    }

    var operations: RuntimeOperations {
        RuntimeOperations(
            snapshot: { _ in self.synchronized { self.current } },
            bootout: { expected in try self.synchronized {
                guard self.current == expected else { throw UpdateFailure.serviceOwnershipUnknown }
                XCTAssertEqual(self.healthValue?.workTotal ?? 0, 0)
                XCTAssertNotEqual(self.healthValue?.gate, "serving")
                self.bootouts += 1; self.current = nil; self.healthValue = nil
            } },
            removed: { _ in self.synchronized { self.current == nil } },
            process: { pid in self.synchronized { self.current?.process?.pid == pid ? self.current?.process : nil } },
            writerAvailable: { self.synchronized { self.current == nil } },
            bootstrap: { runtimeID, _ in try self.synchronized {
                self.bootstraps += 1
                if self.failAll || self.failRuntime == runtimeID { throw UpdateFailure.candidateFailed }
                try self.install(runtimeID, gate: "gated")
                return self.plistSHA
            } },
            plistDigest: { _ in self.synchronized { self.plistSHA } },
            client: { _ in ProxyClient(exchange: { action, command in try self.reply(action, command) }) },
            setRoutingOff: { _ in self.synchronized { self.offWrites += 1 } }
        )
    }
}

final class UpdateEngineTests: XCTestCase, @unchecked Sendable {
    private let oldID = String(repeating: "a", count: 64)
    private let newID = String(repeating: "b", count: 64)

    private func fixture(sameRuntime: Bool = false) throws -> (RuntimeStore, UpdateJournal, FakeRuntime) {
        let root = FileManager.default.temporaryDirectory.resolvingSymlinksInPath()
            .appendingPathComponent("codexmulti-update-engine-\(UUID().uuidString)", isDirectory: true)
        let store = try RuntimeStore(root: root, verifyBundle: { _ in })
        addTeardownBlock { try FileManager.default.removeItem(at: root) }
        try store.select(ActiveRuntime(runtimeID: oldID, generation: 4))
        let config = root.appendingPathComponent("proxy.json").path
        let journal = UpdateJournal(phase: .waitingIdle, appPath: "/Applications/CodexMulti.app",
            previousAppBuild: "1", targetAppBuild: "2", oldRuntimeID: oldID,
            targetRuntimeID: sameRuntime ? oldID : newID, configPath: config,
            configRevision: String(repeating: "d", count: 64), desiredEnabled: true,
            previousGeneration: 4, serviceLabel: "dev.codexmulti.tests.engine", kind: "runtime")
        try store.save(journal)
        return (store, journal, try FakeRuntime(store: store, runtimeID: oldID, config: config, label: journal.serviceLabel))
    }

    private func finish(store: RuntimeStore, id: String, runtime: FakeRuntime) async throws -> UpdateJournal {
        for _ in 0..<25 {
            let engine = UpdateEngine(store: store, transactionID: id, operations: runtime.operations)
            let journal = try await engine.advance()
            if journal.phase.terminal { return journal }
        }
        throw UpdateFailure.recoveryRequired
    }

    func testUIOnlyUpdateKeepsPIDAndBusyConnection() async throws {
        let (store, journal, runtime) = try fixture(sameRuntime: true)
        runtime.busy("websocket", 1)
        let original = runtime.current
        let completed = try await finish(store: store, id: journal.transactionID, runtime: runtime)
        XCTAssertEqual(completed.phase, .complete)
        XCTAssertEqual(runtime.current, original)
        XCTAssertEqual(runtime.bootouts, 0)
        XCTAssertEqual(runtime.bootstraps, 0)
        XCTAssertEqual(runtime.healthValue?.workTotal, 1)
    }

    func testBusyRequestsDeferThenSwapAndSurviveCoordinatorRecreationAtEveryPhase() async throws {
        let (store, journal, runtime) = try fixture()
        runtime.busy("http", 2)
        for _ in 0..<4 {
            let engine = UpdateEngine(store: store, transactionID: journal.transactionID, operations: runtime.operations)
            let state = try await engine.advance()
            XCTAssertEqual(state.phase, .waitingIdle)
        }
        XCTAssertEqual(runtime.bootouts, 0)
        runtime.busy("http", 0)
        let completed = try await finish(store: store, id: journal.transactionID, runtime: runtime)
        XCTAssertEqual(completed.phase, .complete)
        XCTAssertEqual(try store.active()?.runtimeID, newID)
        XCTAssertEqual(try store.active()?.generation, 5)
        XCTAssertEqual(runtime.bootouts, 1)
        XCTAssertEqual(runtime.bootstraps, 1)
        XCTAssertEqual(runtime.activations, [newID])
    }

    func testFailedCandidateReturnsToPreviousRuntimeWithANewGeneration() async throws {
        let (store, journal, runtime) = try fixture()
        runtime.failRuntime = newID
        let completed = try await finish(store: store, id: journal.transactionID, runtime: runtime)
        XCTAssertEqual(completed.phase, .rolledBack)
        XCTAssertTrue(completed.rollbackAttempted)
        XCTAssertEqual(try store.active()?.runtimeID, oldID)
        XCTAssertEqual(try store.active()?.generation, 5)
        XCTAssertEqual(runtime.activations, [oldID])
        XCTAssertEqual(runtime.offWrites, 0)
    }

    func testCandidateCrashAfterAdmissionRestoresOldRuntimeWithoutReplayingRequests() async throws {
        let (store, journal, runtime) = try fixture()
        let engine = UpdateEngine(store: store, transactionID: journal.transactionID, operations: runtime.operations)
        while try await engine.state().phase != .verifying { _ = try await engine.advance() }
        runtime.synchronized { runtime.current = nil; runtime.healthValue = nil }
        let completed = try await finish(store: store, id: journal.transactionID, runtime: runtime)
        XCTAssertEqual(completed.phase, .rolledBack)
        XCTAssertEqual(try store.active()?.runtimeID, oldID)
        XCTAssertEqual(try store.active()?.generation, 6)
        XCTAssertEqual(runtime.activations, [newID, oldID])
    }

    func testLostActivateAcknowledgementDoesNotRestartTheServingCandidate() async throws {
        let (store, journal, runtime) = try fixture()
        runtime.loseActivationReply = true
        let engine = UpdateEngine(store: store, transactionID: journal.transactionID, operations: runtime.operations)
        while try await engine.state().phase != .activationCommitted { _ = try await engine.advance() }
        _ = try await engine.advance()
        runtime.busy("http", 3)
        let completed = try await finish(store: store, id: journal.transactionID, runtime: runtime)
        XCTAssertEqual(completed.phase, .complete)
        XCTAssertEqual(runtime.bootouts, 1)
        XCTAssertEqual(runtime.activations, [newID])
        XCTAssertEqual(runtime.healthValue?.workTotal, 3)
    }

    func testOffDuringIdleWaitStopsSafelyWithoutStartingAnotherEngine() async throws {
        let (store, journal, runtime) = try fixture()
        runtime.busy("renewal", 1)
        let engine = UpdateEngine(store: store, transactionID: journal.transactionID, operations: runtime.operations)
        try await engine.requestOff()
        let pending = try await engine.advance()
        XCTAssertEqual(pending.phase, .waitingIdle)
        XCTAssertFalse(pending.desiredEnabled)
        XCTAssertEqual(runtime.offWrites, 0)
        runtime.busy("renewal", 0)
        let completed = try await finish(store: store, id: journal.transactionID, runtime: runtime)
        XCTAssertEqual(completed.phase, .complete)
        XCTAssertFalse(completed.desiredEnabled)
        XCTAssertEqual(runtime.bootouts, 1)
        XCTAssertEqual(runtime.bootstraps, 0)
        XCTAssertEqual(runtime.offWrites, 1)
    }

    func testUnreachableLiveProcessIsNeverStopped() async throws {
        let (store, journal, runtime) = try fixture()
        runtime.unreachable = true
        let completed = try await finish(store: store, id: journal.transactionID, runtime: runtime)
        XCTAssertEqual(completed.phase, .recoveryRequired)
        XCTAssertEqual(runtime.bootouts, 0)
        XCTAssertEqual(runtime.bootstraps, 0)
        XCTAssertNotNil(runtime.current)
    }

    func testRollbackFailureIsVisibleAndDoesNotTurnRoutingOff() async throws {
        let (store, journal, runtime) = try fixture()
        runtime.failAll = true
        let completed = try await finish(store: store, id: journal.transactionID, runtime: runtime)
        XCTAssertEqual(completed.phase, .recoveryRequired)
        XCTAssertTrue(completed.rollbackAttempted)
        XCTAssertEqual(runtime.bootstraps, 2)
        XCTAssertEqual(runtime.offWrites, 0)
    }

    func testProgressWriteCannotOverwriteNewerOffOrCancellationIntent() throws {
        let (store, stale, _) = try fixture()
        var newer = stale
        newer.desiredEnabled = false
        newer.cancellationRequested = true
        try store.save(newer)
        var progress = stale
        progress.phase = .quiescent
        try store.save(progress)
        XCTAssertFalse(try store.current()!.desiredEnabled)
        XCTAssertTrue(try store.current()!.cancellationRequested)
    }

    func testOffArrivingWithHealthReplyPreventsCompletionUntilProcessStops() async throws {
        for sameRuntime in [true, false] {
            let (store, journal, runtime) = try fixture(sameRuntime: sameRuntime)
            let first = UpdateEngine(store: store, transactionID: journal.transactionID, operations: runtime.operations)
            if !sameRuntime {
                while try await first.state().phase != .verifying { _ = try await first.advance() }
            }
            var operations = runtime.operations
            operations.client = { _ in ProxyClient(exchange: { action, command in
                if action == "health" {
                    var intent = try store.journal(journal.transactionID)
                    intent.desiredEnabled = false
                    try store.save(intent)
                }
                return try runtime.reply(action, command)
            }) }
            let resumed = UpdateEngine(store: store, transactionID: journal.transactionID, operations: operations)
            let pending = try await resumed.advance()
            XCTAssertNotEqual(pending.phase, .complete)
            let completed = try await finish(store: store, id: journal.transactionID, runtime: runtime)
            XCTAssertEqual(completed.phase, .complete)
            XCTAssertFalse(completed.desiredEnabled)
            XCTAssertNil(runtime.current)
            XCTAssertEqual(runtime.offWrites, 1)
        }
    }

    func testCancellingPendingUpdateDoesNotDiscardAnOffRequest() async throws {
        let (store, journal, runtime) = try fixture()
        let engine = UpdateEngine(store: store, transactionID: journal.transactionID, operations: runtime.operations)
        try await engine.requestOff()
        try await engine.requestCancellation()
        let result = try await finish(store: store, id: journal.transactionID, runtime: runtime)
        XCTAssertEqual(result.phase, .cancelled)
        XCTAssertFalse(result.desiredEnabled)
        XCTAssertNil(runtime.current)
        XCTAssertEqual(runtime.offWrites, 1)
        XCTAssertEqual(try store.active()?.runtimeID, oldID)
        XCTAssertEqual(runtime.bootstraps, 0)
    }
}
