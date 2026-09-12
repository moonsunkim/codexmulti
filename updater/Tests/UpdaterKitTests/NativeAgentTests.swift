import Darwin
import Foundation
import XCTest
@testable import UpdaterKit

final class NativeAgentTests: XCTestCase, @unchecked Sendable {
    func testSignedGUIReadyCanBeRetriedAfterTheCoordinatorAdvances() async throws {
        guard let oldPath = ProcessInfo.processInfo.environment["CODEXMULTI_UPDATER_TEST_OLD_APP"],
              let guiPath = ProcessInfo.processInfo.environment["CODEXMULTI_UPDATER_TEST_GUI_APP"] else {
            throw XCTSkip("Signed agent and GUI client fixtures are required")
        }
        let home = FileManager.default.temporaryDirectory.appendingPathComponent("codexmulti-gui-ready-\(UUID().uuidString)")
        defer { try? FileManager.default.removeItem(at: home) }
        let store = try RuntimeStore(root: home)
        let manifest = try store.stage(app: URL(fileURLWithPath: oldPath))
        let gui = try Disk.canonicalURL(URL(fileURLWithPath: guiPath))
        try store.select(ActiveRuntime(runtimeID: manifest.runtimeID, generation: 1))
        var journal = UpdateJournal(phase: .installingApp, appPath: gui.path,
            previousAppBuild: manifest.appBuild, targetAppBuild: manifest.appBuild,
            oldRuntimeID: manifest.runtimeID, targetRuntimeID: manifest.runtimeID,
            configPath: store.root.appendingPathComponent("unused-proxy.json").path,
            configRevision: "", desiredEnabled: true, previousGeneration: 1)
        journal.installArmed = true
        try store.save(journal)
        let first = UpdateEngine(store: store, transactionID: journal.transactionID)
        try await first.markGUIReady(appPath: gui.path)
        for phase: UpdatePhase in [.waitingIdle, .candidateGated, .activationCommitted, .verifying, .complete] {
            var advanced = try store.journal(journal.transactionID)
            advanced.phase = phase
            try store.save(advanced)
            let persisted = try Disk.read(store.journalURL(journal.transactionID))
            let resumed = UpdateEngine(store: store, transactionID: journal.transactionID)
            try await resumed.markGUIReady(appPath: gui.path)
            XCTAssertEqual(try Disk.read(store.journalURL(journal.transactionID)), persisted)
            do {
                try await resumed.markGUIReady(appPath: oldPath)
                XCTFail("A different app path must not acknowledge GUI readiness")
            } catch { XCTAssertEqual(error as? UpdateFailure, .invalidTransaction) }
        }
    }

    func testSignedAgentRejectsUntrustedPeerAndResumesArmedStateAfterProcessDeath() async throws {
        guard let oldPath = ProcessInfo.processInfo.environment["CODEXMULTI_UPDATER_TEST_OLD_APP"],
              let guiPath = ProcessInfo.processInfo.environment["CODEXMULTI_UPDATER_TEST_GUI_APP"] else {
            throw XCTSkip("Signed agent and GUI client fixtures are required")
        }
        let home = FileManager.default.temporaryDirectory.appendingPathComponent("codexmulti-native-agent-\(UUID().uuidString)")
        let store = try RuntimeStore(root: home.appendingPathComponent("Library/Application Support/CodexMulti"))
        let launch = LaunchService(home: try Disk.canonicalURL(home))
        let manifest = try store.stage(app: URL(fileURLWithPath: oldPath))
        let gui = try Disk.canonicalURL(URL(fileURLWithPath: guiPath))
        try store.verifyBundle(gui)
        try store.select(ActiveRuntime(runtimeID: manifest.runtimeID, generation: 1))
        var journal = UpdateJournal(phase: .appPrepared, appPath: gui.path,
            previousAppBuild: manifest.appBuild, targetAppBuild: "999999999999",
            oldRuntimeID: manifest.runtimeID, targetRuntimeID: manifest.runtimeID,
            configPath: store.root.appendingPathComponent("unused-proxy.json").path,
            configRevision: "", desiredEnabled: true, previousGeneration: 1)
        journal.helperSHA256 = try Disk.fileDigest(UpdatePreparation.helperURL(store: store, journal: journal))
        try store.save(journal)
        let label = "dev.codexmulti.app.update." + journal.transactionID
        let id = journal.transactionID
        let helper = try UpdatePreparation.helperURL(store: store, journal: journal)
        addTeardownBlock {
            if let snapshot = try launch.snapshot(label) {
                guard snapshot.arguments == [helper.path, "serve", "--root", store.root.path, "--transaction", id] else {
                    throw UpdateFailure.serviceOwnershipUnknown
                }
                try launch.bootout(snapshot)
                for _ in 0..<50 {
                    if try launch.removed(snapshot) { break }
                    usleep(100_000)
                }
                guard try launch.removed(snapshot) else { throw UpdateFailure.processStillRunning }
            }
            let socket = try AgentConnection.socketURL(root: store.root)
            if Disk.exists(socket) { XCTAssertEqual(unlink(socket.path), 0) }
            try FileManager.default.removeItem(at: home)
        }
        try UpdatePreparation.startAgent(store: store, journal: journal, launch: launch)
        let socket = try AgentConnection.socketURL(root: store.root)
        for _ in 0..<100 {
            if Disk.exists(socket) { break }
            try await Task.sleep(for: .milliseconds(100))
        }
        var info = stat()
        XCTAssertEqual(lstat(socket.path, &info), 0)
        XCTAssertEqual(info.st_mode & 0o777, 0o600)
        XCTAssertThrowsError(try AgentConnection.send(AgentRequest("state", transactionID: id), store: store)) {
            XCTAssertEqual($0 as? UpdateFailure, .invalidSignature)
        }
        let client = gui.appendingPathComponent("Contents/MacOS/CodexMulti").path
        let state = try Commands.run(client, [store.root.path, id, "state"])
        XCTAssertEqual(state.status, 0, state.errorOutput)
        XCTAssertEqual(state.output.trimmingCharacters(in: .whitespacesAndNewlines), UpdatePhase.appPrepared.rawValue)
        let armed = try Commands.run(client, [store.root.path, id, "arm"])
        XCTAssertEqual(armed.status, 0, armed.errorOutput)
        XCTAssertTrue(try store.journal(id).installArmed)
        let first = try XCTUnwrap(launch.snapshot(label)?.process)
        XCTAssertEqual(kill(first.pid, SIGKILL), 0)
        var restarted: ProcessIdentity?
        for _ in 0..<150 {
            if let current = try launch.snapshot(label)?.process, current != first,
               (try? Commands.run(client, [store.root.path, id, "state"]).status) == 0 {
                restarted = current; break
            }
            try await Task.sleep(for: .milliseconds(100))
        }
        XCTAssertNotNil(restarted)
        XCTAssertTrue(try store.journal(id).installArmed)
        let aborted = try Commands.run(client, [store.root.path, id, "download-aborted"])
        XCTAssertEqual(aborted.status, 0, aborted.errorOutput)
        XCTAssertEqual(try store.journal(id).phase, .cancelled)
        XCTAssertFalse(try store.journal(id).installArmed)
        for _ in 0..<50 {
            if try launch.snapshot(label)?.process == nil { break }
            try await Task.sleep(for: .milliseconds(100))
        }
        XCTAssertNil(try launch.snapshot(label)?.process)
        XCTAssertNil(try launch.snapshot(label))
        XCTAssertFalse(Disk.exists(try launch.plistURL(label)))
    }
}
