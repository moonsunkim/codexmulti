import Foundation

public actor UpdateEngine {
    public let store: RuntimeStore
    public let operations: RuntimeOperations
    public let transactionID: String
    private let now: @Sendable () -> Date

    public init(store: RuntimeStore, transactionID: String, operations: RuntimeOperations? = nil,
                now: @escaping @Sendable () -> Date = Date.init) {
        self.store = store; self.transactionID = transactionID
        self.operations = operations ?? RuntimeOperations(store: store); self.now = now
    }

    public func state() throws -> UpdateJournal { try store.journal(transactionID) }

    public func requestCancellation() throws {
        var journal = try state()
        guard !journal.phase.terminal else { return }
        journal.cancellationRequested = true
        try store.save(journal)
    }

    public func requestOff() throws {
        var journal = try state()
        journal.desiredEnabled = false
        try store.save(journal)
        try persistOffIntent()
    }

    private func persistOffIntent() throws {
        let path = store.root.appendingPathComponent("proxy-settings.json")
        if Disk.exists(path) {
            guard var object = try JSONSerialization.jsonObject(with: Disk.read(path)) as? [String: Any] else {
                throw UpdateFailure.invalidTransaction
            }
            if object["enabled"] as? Bool == false { return }
            object["enabled"] = false
            try Disk.atomicWrite(try JSONSerialization.data(withJSONObject: object, options: [.sortedKeys]), at: path)
        }
    }

    public func armInstallation() throws {
        var journal = try state()
        guard !journal.cancellationRequested else { throw UpdateFailure.invalidTransaction }
        if journal.phase == .installingApp, journal.installArmed { return }
        guard journal.phase == .appPrepared, !journal.installArmed else { throw UpdateFailure.invalidTransaction }
        journal.installArmed = true
        journal.phase = .installingApp
        try store.save(journal)
    }

    public func disarmAfterInstallerAbort() throws {
        var journal = try state()
        guard [.preparingApp, .appPrepared, .installingApp].contains(journal.phase),
              try appBuild(at: URL(fileURLWithPath: journal.appPath)) == journal.previousAppBuild else {
            throw UpdateFailure.installStillArmed
        }
        journal.installArmed = false
        journal.phase = .cancelled
        try store.save(journal)
    }

    public func installerFailed() throws {
        var journal = try state()
        guard [.installingApp, .awaitingGUI].contains(journal.phase) else { throw UpdateFailure.invalidTransaction }
        journal.phase = .appRecoveryRequired
        journal.failure = .appRecoveryRequired
        try store.save(journal)
    }

    public func markGUIReady(appPath: String) throws {
        var journal = try state()
        guard appPath == journal.appPath else {
            throw UpdateFailure.invalidTransaction
        }
        let app = URL(fileURLWithPath: appPath)
        let manifest = try store.verifyPayload(in: app)
        guard manifest.appBuild == journal.targetAppBuild, manifest.runtimeID == journal.targetRuntimeID else {
            throw UpdateFailure.identityMismatch
        }
        if journal.guiReady {
            guard !journal.installArmed else { throw UpdateFailure.invalidTransaction }
            return
        }
        guard [.appPrepared, .installingApp, .awaitingGUI].contains(journal.phase) else {
            throw UpdateFailure.invalidTransaction
        }
        _ = try store.stage(app: app)
        journal.guiReady = true
        journal.installArmed = false
        journal.phase = .waitingIdle
        try store.save(journal)
    }

    public func advance() async throws -> UpdateJournal {
        var journal = try state()
        if journal.phase.terminal { return journal }
        do {
            if !journal.desiredEnabled { try persistOffIntent() }
            switch journal.phase {
            case .preparingApp, .appPrepared:
                if journal.cancellationRequested && !journal.installArmed {
                    journal.phase = .cancelled
                    try store.save(journal)
                }
            case .installingApp:
                let app = URL(fileURLWithPath: journal.appPath)
                if (try? appBuild(at: app)) == journal.targetAppBuild {
                    let manifest = try store.verifyPayload(in: app)
                    guard manifest.runtimeID == journal.targetRuntimeID else { throw UpdateFailure.identityMismatch }
                    journal.phase = .awaitingGUI
                    try store.save(journal)
                }
            case .awaitingGUI:
                if now().timeIntervalSince(journal.updatedAt) >= 30 {
                    journal.phase = .appRecoveryRequired
                    journal.failure = .appRecoveryRequired
                    try store.save(journal)
                }
            case .waitingIdle:
                try await waitForIdle(&journal)
            case .quiescent:
                try await commitStop(&journal)
            case .stopCommitted:
                try await stopAndStartCandidate(&journal)
            case .candidateGated:
                try await confirmCandidate(&journal)
            case .activationCommitted:
                try await activate(&journal)
            case .verifying:
                try await verify(&journal)
            case .rollingBack:
                try await rollbackBeforeAdmission(&journal)
            case .complete, .cancelled, .rolledBack, .recoveryRequired, .appRecoveryRequired:
                break
            }
        } catch {
            let failure = error as? UpdateFailure ?? .recoveryRequired
            if failure == .proxyBusy { return try state() }
            if failure == .processStillRunning, [.stopCommitted, .rollingBack].contains(journal.phase),
               now().timeIntervalSince(journal.updatedAt) < 10 { return try state() }
            journal = try state()
            if [.activationCommitted, .verifying].contains(journal.phase), !journal.rollbackAttempted,
               let active = try store.active(), active.runtimeID == journal.targetRuntimeID,
               active.generation == journal.activationGeneration,
               try operations.snapshot(journal.serviceLabel)?.process == nil, try operations.writerAvailable() {
                journal.failure = failure
                journal.rollbackAttempted = true
                journal.phase = .waitingIdle
            } else if (journal.phase == .candidateGated || (journal.phase == .stopCommitted && failure == .candidateFailed))
                && !journal.rollbackAttempted {
                journal.failure = failure
                journal.phase = .rollingBack
            } else if [.installingApp, .awaitingGUI].contains(journal.phase) {
                journal.failure = failure
                journal.phase = .appRecoveryRequired
            } else {
                journal.failure = failure
                journal.phase = .recoveryRequired
            }
            try store.save(journal)
        }
        return try state()
    }

    private func selectedTarget(_ journal: UpdateJournal) -> String {
        journal.rollbackAttempted || (journal.cancellationRequested && !journal.desiredEnabled)
            ? journal.oldRuntimeID : journal.targetRuntimeID
    }

    private func refreshIntent(_ journal: inout UpdateJournal) throws {
        let current = try state()
        journal.desiredEnabled = current.desiredEnabled
        journal.cancellationRequested = current.cancellationRequested
    }

    private func owned(_ snapshot: ServiceSnapshot, runtimeID: String, journal: UpdateJournal, allowLauncher: Bool = false) throws {
        let app = try store.bundle(runtimeID)
        guard snapshot.label == journal.serviceLabel,
              snapshot.arguments == RuntimeOperations.arguments(app: app, configPath: journal.configPath) else {
            throw UpdateFailure.serviceOwnershipUnknown
        }
        if let process = snapshot.process {
            guard process.executable == app.appendingPathComponent("Contents/Helpers/node").path
                || (allowLauncher && process.executable == app.appendingPathComponent("Contents/Helpers/codexmulti-runtime-launcher").path) else {
                throw UpdateFailure.serviceOwnershipUnknown
            }
        }
    }

    private func valid(_ health: ProxyHealth, runtimeID: String, journal: UpdateJournal) throws {
        guard health.runtimeID == runtimeID, health.configPath == nil || health.configPath == journal.configPath,
              let revision = health.configRevision, Disk.isDigest(revision) else { throw UpdateFailure.identityMismatch }
    }

    private func leaseURL() throws -> URL {
        try store.transactionDirectory(transactionID).appendingPathComponent("lease.json")
    }

    private func rememberProcess(_ snapshot: ServiceSnapshot, journal: inout UpdateJournal) throws {
        journal.oldPID = snapshot.process?.pid
        journal.oldProcessStart = snapshot.process?.start
        journal.oldPlistSHA256 = try operations.plistDigest(snapshot.label)
    }

    private func waitForIdle(_ journal: inout UpdateJournal) async throws {
        guard journal.kind != "app" || journal.guiReady else { throw UpdateFailure.appRecoveryRequired }
        guard let active = try store.active() else { throw UpdateFailure.invalidManifest }
        let target = selectedTarget(journal)
        if journal.cancellationRequested && journal.desiredEnabled && !journal.rollbackAttempted {
            journal.phase = .cancelled
            try store.save(journal)
            return
        }
        let snapshot = try operations.snapshot(journal.serviceLabel)
        if snapshot == nil {
            if let pid = journal.oldPID, let process = try operations.process(pid), process.start == journal.oldProcessStart {
                throw UpdateFailure.processStillRunning
            }
            guard try operations.writerAvailable() else { throw UpdateFailure.processStillRunning }
            if let digest = try operations.ownedPlistDigest(active.runtimeID, journal) { journal.oldPlistSHA256 = digest }
            journal.previousGeneration = active.generation
            journal.activationGeneration = active.generation + 1
            journal.phase = .stopCommitted
            try store.save(journal)
            return
        }
        let snapshotValue = snapshot!
        try owned(snapshotValue, runtimeID: active.runtimeID, journal: journal)
        let client = try operations.client(journal.configPath)
        let health: ProxyHealth
        do { health = try await client.health() }
        catch {
            guard snapshotValue.process == nil, try operations.writerAvailable() else { throw UpdateFailure.proxyUnreachable }
            try rememberProcess(snapshotValue, journal: &journal)
            journal.phase = .stopCommitted
            try store.save(journal)
            return
        }
        try valid(health, runtimeID: active.runtimeID, journal: journal)
        try refreshIntent(&journal)
        if journal.cancellationRequested && journal.desiredEnabled && !journal.rollbackAttempted {
            journal.phase = .cancelled
            try store.save(journal)
            return
        }
        if active.runtimeID == target && journal.desiredEnabled && health.gate == "serving" && health.generation == active.generation {
            if ["service", "migration"].contains(journal.kind) { try operations.setRoutingOn(journal) }
            try operations.recordHealth(target, journal)
            journal.phase = journal.rollbackAttempted ? .rolledBack : .complete
            try store.save(journal)
            return
        }
        if health.workTotal > 0 { return }
        journal.expectedBootID = health.bootID
        journal.configRevision = health.configRevision!
        journal.previousGeneration = active.generation
        journal.activationGeneration = active.generation + 1
        try rememberProcess(snapshotValue, journal: &journal)
        try store.save(journal)
        if health.gate == "gated" {
            journal.phase = .stopCommitted
            try store.save(journal)
            return
        }
        let reply = try await client.exchange("prepare-if-idle", ProxyCommand(journal: journal, health: health))
        if reply.status == 409 && reply.error == "proxy_busy" { return }
        guard reply.status == 200, let prepared = reply.health, let lease = prepared.lease,
              Disk.isDigest(lease), prepared.workTotal == 0, prepared.gate == "quiescent", prepared.bootID == health.bootID else {
            throw UpdateFailure.identityMismatch
        }
        try valid(prepared, runtimeID: active.runtimeID, journal: journal)
        try Disk.write(try ProxyCommand(journal: journal, health: prepared, lease: lease), at: leaseURL())
        journal.phase = .quiescent
        try store.save(journal)
    }

    private func commitStop(_ journal: inout UpdateJournal) async throws {
        guard let active = try store.active(), let snapshot = try operations.snapshot(journal.serviceLabel) else {
            journal.phase = .stopCommitted
            try store.save(journal)
            return
        }
        try owned(snapshot, runtimeID: active.runtimeID, journal: journal)
        let client = try operations.client(journal.configPath)
        let health = try await client.health()
        try valid(health, runtimeID: active.runtimeID, journal: journal)
        if health.gate == "gated" && health.workTotal == 0 {
            journal.expectedBootID = health.bootID
            try rememberProcess(snapshot, journal: &journal)
            journal.phase = .stopCommitted
            try store.save(journal)
            return
        }
        guard health.bootID == journal.expectedBootID else { throw UpdateFailure.identityMismatch }
        if health.gate == "serving" {
            journal.phase = .waitingIdle
            try store.save(journal)
            return
        }
        let lease = try Disk.decode(ProxyCommand.self, at: leaseURL())
        try refreshIntent(&journal)
        if (journal.cancellationRequested && journal.desiredEnabled) || health.configRevision != journal.configRevision {
            let reply = try await client.exchange("abort-prepare", lease)
            guard reply.status == 200 else { throw UpdateFailure.activationUnconfirmed }
            journal.phase = journal.cancellationRequested && journal.desiredEnabled ? .cancelled : .waitingIdle
            try store.save(journal)
            return
        }
        guard health.gate == "quiescent", health.workTotal == 0 else { throw UpdateFailure.proxyBusy }
        journal.phase = .stopCommitted
        try store.save(journal)
    }

    private func stopAndStartCandidate(_ journal: inout UpdateJournal) async throws {
        guard let active = try store.active() else { throw UpdateFailure.invalidManifest }
        var target = selectedTarget(journal)
        if let snapshot = try operations.snapshot(journal.serviceLabel) {
            let candidateArguments = RuntimeOperations.arguments(app: try store.bundle(target), configPath: journal.configPath)
            let isOriginalProcess = snapshot.process?.pid == journal.oldPID && snapshot.process?.start == journal.oldProcessStart
            if snapshot.arguments == candidateArguments && (target != active.runtimeID || !isOriginalProcess) {
                try owned(snapshot, runtimeID: target, journal: journal, allowLauncher: true)
                journal.candidatePlistSHA256 = try operations.plistDigest(journal.serviceLabel)
                journal.phase = .candidateGated
                try store.save(journal)
                return
            }
            try owned(snapshot, runtimeID: active.runtimeID, journal: journal)
            if snapshot.process != nil {
                let client = try operations.client(journal.configPath)
                let health = try await client.health()
                try valid(health, runtimeID: active.runtimeID, journal: journal)
                guard health.workTotal == 0 else { throw UpdateFailure.proxyBusy }
                if health.gate == "quiescent" || health.gate == "stopped" {
                    let lease = try Disk.decode(ProxyCommand.self, at: leaseURL())
                    guard lease.bootID == health.bootID, journal.expectedBootID == health.bootID,
                          (try await client.exchange("commit-stop", lease)).status == 200 else {
                        throw UpdateFailure.activationUnconfirmed
                    }
                } else if health.gate != "gated" {
                    throw UpdateFailure.activationUnconfirmed
                }
            }
            try rememberProcess(snapshot, journal: &journal)
            try store.save(journal)
            try operations.bootout(snapshot)
            guard try operations.removed(snapshot) else { throw UpdateFailure.processStillRunning }
        }
        if let pid = journal.oldPID, let process = try operations.process(pid), process.start == journal.oldProcessStart {
            throw UpdateFailure.processStillRunning
        }
        guard try operations.writerAvailable() else { throw UpdateFailure.processStillRunning }
        try refreshIntent(&journal)
        target = selectedTarget(journal)
        if !journal.desiredEnabled {
            try operations.setRoutingOff(journal)
            try operations.removeServiceArtifacts(journal)
            try store.select(ActiveRuntime(runtimeID: target, generation: journal.activationGeneration,
                                          transactionID: journal.transactionID, epoch: journal.epoch))
            journal.phase = journal.rollbackAttempted ? .rolledBack : journal.cancellationRequested ? .cancelled : .complete
            try store.save(journal)
            return
        }
        if let digest = try operations.plannedPlistDigest(target, journal) {
            journal.candidatePlistSHA256 = digest
            try store.save(journal)
        }
        journal.candidatePlistSHA256 = try operations.bootstrap(target, journal)
        journal.phase = .candidateGated
        try store.save(journal)
    }

    private func confirmCandidate(_ journal: inout UpdateJournal) async throws {
        let target = selectedTarget(journal)
        guard let snapshot = try operations.snapshot(journal.serviceLabel) else {
            if now().timeIntervalSince(journal.updatedAt) < 15 { return }
            throw UpdateFailure.candidateFailed
        }
        try owned(snapshot, runtimeID: target, journal: journal, allowLauncher: true)
        let health: ProxyHealth
        do { health = try await operations.client(journal.configPath).health() }
        catch {
            if now().timeIntervalSince(journal.updatedAt) < 15 { return }
            throw UpdateFailure.candidateFailed
        }
        try valid(health, runtimeID: target, journal: journal)
        guard health.gate == "gated", health.workTotal == 0 else { throw UpdateFailure.identityMismatch }
        journal.candidateBootID = health.bootID
        journal.phase = .activationCommitted
        try store.save(journal)
        try store.select(ActiveRuntime(runtimeID: target, generation: journal.activationGeneration,
                                      transactionID: journal.transactionID, epoch: journal.epoch))
    }

    private func activate(_ journal: inout UpdateJournal) async throws {
        let target = selectedTarget(journal)
        let client = try operations.client(journal.configPath)
        let health = try await client.health()
        try valid(health, runtimeID: target, journal: journal)
        guard health.bootID == journal.candidateBootID else { throw UpdateFailure.identityMismatch }
        guard let active = try store.active() else { throw UpdateFailure.invalidManifest }
        if active.generation == journal.previousGeneration && health.gate == "gated" {
            try store.select(ActiveRuntime(runtimeID: target, generation: journal.activationGeneration,
                                          transactionID: journal.transactionID, epoch: journal.epoch))
        } else if active.runtimeID != target || active.generation != journal.activationGeneration
                    || active.transactionID != journal.transactionID || active.epoch != journal.epoch {
            throw UpdateFailure.identityMismatch
        }
        if health.gate != "serving" || health.generation != journal.activationGeneration {
            guard health.gate == "gated", health.workTotal == 0 else { throw UpdateFailure.identityMismatch }
            do {
                let command = try ProxyCommand(journal: journal, health: health, generation: journal.activationGeneration)
                let reply = try await client.exchange("activate", command)
                guard reply.status == 200 else { throw UpdateFailure.activationUnconfirmed }
            } catch {
                if now().timeIntervalSince(journal.updatedAt) < 15 { return }
                throw UpdateFailure.activationUnconfirmed
            }
        }
        journal.phase = .verifying
        try store.save(journal)
    }

    private func verify(_ journal: inout UpdateJournal) async throws {
        let target = selectedTarget(journal)
        let health = try await operations.client(journal.configPath).health()
        try refreshIntent(&journal)
        try valid(health, runtimeID: target, journal: journal)
        guard health.bootID == journal.candidateBootID, health.generation == journal.activationGeneration,
              health.gate == "serving", let snapshot = try operations.snapshot(journal.serviceLabel) else {
            throw UpdateFailure.activationUnconfirmed
        }
        try owned(snapshot, runtimeID: target, journal: journal)
        if !journal.desiredEnabled {
            journal.phase = .waitingIdle
            try store.save(journal)
            return
        }
        if ["service", "migration"].contains(journal.kind) { try operations.setRoutingOn(journal) }
        try operations.recordHealth(target, journal)
        journal.phase = journal.rollbackAttempted ? .rolledBack : .complete
        try store.save(journal)
    }

    private func rollbackBeforeAdmission(_ journal: inout UpdateJournal) async throws {
        guard !journal.rollbackAttempted, let active = try store.active(),
              active.runtimeID == journal.oldRuntimeID,
              active.generation == journal.previousGeneration else { throw UpdateFailure.activationUnconfirmed }
        if let snapshot = try operations.snapshot(journal.serviceLabel) {
            try owned(snapshot, runtimeID: journal.targetRuntimeID, journal: journal, allowLauncher: true)
            try operations.bootout(snapshot)
            guard try operations.removed(snapshot) else { throw UpdateFailure.processStillRunning }
        }
        guard try operations.writerAvailable() else { throw UpdateFailure.processStillRunning }
        journal.rollbackAttempted = true
        journal.expectedBootID = nil
        journal.candidateBootID = nil
        journal.oldPID = nil
        journal.oldProcessStart = nil
        journal.oldPlistSHA256 = try operations.plistDigest(journal.serviceLabel)
        journal.phase = .stopCommitted
        journal.activationGeneration = active.generation + 1
        try store.save(journal)
    }

    private func appBuild(at app: URL) throws -> String {
        let bytes = try Disk.read(app.appendingPathComponent("Contents/Info.plist"), privateFile: false)
        guard let plist = try PropertyListSerialization.propertyList(from: bytes, format: nil) as? [String: Any],
              let build = plist["CFBundleVersion"] as? String else { throw UpdateFailure.invalidManifest }
        return build
    }
}
