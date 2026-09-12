import Foundation

public enum UpdatePreparation {
    public static func begin(store: RuntimeStore, app: URL, targetBuild: String, targetRuntimeID: String,
                             configPath: String, desiredEnabled: Bool,
                             serviceLabel: String = "dev.codexmulti.app.proxy") throws -> UpdateJournal {
        let lock = try FileLock(store.lockURL)
        defer { withExtendedLifetime(lock) {} }
        if let current = try store.current(), ![.complete, .cancelled, .rolledBack].contains(current.phase) {
            throw UpdateFailure.updateBusy
        }
        guard Disk.isDigest(targetRuntimeID), !targetBuild.isEmpty, targetBuild.count < 80,
              let active = try store.active() else { throw UpdateFailure.migrationRequired }
        let manifest = try store.verifyPayload(in: app)
        let oldApp = try store.bundle(active.runtimeID)
        let oldManifest = try store.verifyPayload(in: oldApp)
        guard oldManifest.minimumGUIProtocol <= 1, oldManifest.maximumGUIProtocol >= 1 else {
            throw UpdateFailure.incompatibleVersion
        }
        _ = try store.stage(app: app)
        let capacity = try store.root.resourceValues(forKeys: [.volumeAvailableCapacityForImportantUsageKey])
        guard let available = capacity.volumeAvailableCapacityForImportantUsage, available >= 512 * 1024 * 1024 else {
            throw UpdateFailure.insufficientSpace
        }
        let journal = UpdateJournal(phase: .preparingApp, appPath: app.path,
            previousAppBuild: manifest.appBuild, targetAppBuild: targetBuild,
            oldRuntimeID: active.runtimeID, targetRuntimeID: targetRuntimeID,
            configPath: configPath, configRevision: "", desiredEnabled: desiredEnabled,
            previousGeneration: active.generation, serviceLabel: serviceLabel)
        try store.save(journal)
        return journal
    }

    public static func externalApp(store: RuntimeStore, app: URL, configPath: String, desiredEnabled: Bool,
                                   automatically: Bool = true, serviceLabel: String = "dev.codexmulti.app.proxy") throws -> UpdateJournal {
        let lock = try FileLock(store.lockURL)
        defer { withExtendedLifetime(lock) {} }
        let current = try store.current()
        if let current, ![.complete, .cancelled, .rolledBack].contains(current.phase) { throw UpdateFailure.updateBusy }
        guard let active = try store.active() else { throw UpdateFailure.migrationRequired }
        let manifest = try store.verifyPayload(in: app)
        if automatically, let deferred = try store.deferred(),
           deferred.appBuild == manifest.appBuild, deferred.runtimeID == manifest.runtimeID {
            throw UpdateFailure.runtimeDeferred
        }
        if automatically, let current, [.cancelled, .rolledBack].contains(current.phase),
           current.targetAppBuild == manifest.appBuild, current.targetRuntimeID == manifest.runtimeID {
            throw UpdateFailure.runtimeDeferred
        }
        _ = try store.stage(app: app)
        let previous = try store.verifyPayload(in: store.bundle(active.runtimeID))
        let journal = UpdateJournal(phase: .preparingApp, appPath: app.path,
            previousAppBuild: previous.appBuild, targetAppBuild: manifest.appBuild,
            oldRuntimeID: active.runtimeID, targetRuntimeID: manifest.runtimeID,
            configPath: configPath, configRevision: "", desiredEnabled: desiredEnabled,
            previousGeneration: active.generation, serviceLabel: serviceLabel, kind: "external")
        try store.save(journal)
        return journal
    }

    public static func prepared(store: RuntimeStore, transactionID: String) throws -> UpdateJournal {
        let lock = try FileLock(store.lockURL)
        defer { withExtendedLifetime(lock) {} }
        var journal = try store.journal(transactionID)
        guard journal.phase == .preparingApp, !journal.cancellationRequested else { throw UpdateFailure.invalidTransaction }
        let app = journal.kind == "external" ? try store.bundle(journal.oldRuntimeID) : URL(fileURLWithPath: journal.appPath)
        let manifest = try store.verifyPayload(in: app)
        guard manifest.appBuild == journal.previousAppBuild else { throw UpdateFailure.identityMismatch }
        let previousDirectory = try store.transactionDirectory(transactionID).appendingPathComponent("previous-app")
        try Disk.privateDirectory(previousDirectory)
        let previous = previousDirectory.appendingPathComponent("CodexMulti.app")
        if !Disk.exists(previous) { try FileManager.default.copyItem(at: app, to: previous) }
        guard try store.verifyPayload(in: previous) == manifest else { throw UpdateFailure.payloadMismatch }
        let helper = try helperURL(store: store, journal: journal)
        journal.helperSHA256 = try Disk.fileDigest(helper)
        journal.phase = journal.kind == "external" ? .waitingIdle : .appPrepared
        journal.guiReady = journal.kind == "external"
        try store.save(journal)
        return journal
    }

    public static func cancelUnarmed(store: RuntimeStore, transactionID: String) throws {
        let lock = try FileLock(store.lockURL)
        defer { withExtendedLifetime(lock) {} }
        var journal = try store.journal(transactionID)
        guard [.preparingApp, .appPrepared].contains(journal.phase), !journal.installArmed else {
            throw UpdateFailure.installStillArmed
        }
        journal.cancellationRequested = true
        journal.phase = .cancelled
        try store.save(journal)
    }

    public static func helperURL(store: RuntimeStore, journal: UpdateJournal) throws -> URL {
        let app = try store.bundle(journal.oldRuntimeID)
        _ = try store.verifyPayload(in: app)
        return app.appendingPathComponent("Contents/Helpers/codexmulti-update-agent")
    }

    public static func startAgent(store: RuntimeStore, journal: UpdateJournal, launch: LaunchService = LaunchService()) throws {
        let helper = try helperURL(store: store, journal: journal)
        if let digest = journal.helperSHA256, try Disk.fileDigest(helper) != digest { throw UpdateFailure.payloadMismatch }
        let label = "dev.codexmulti.app.update." + journal.transactionID
        let arguments = [helper.path, "serve", "--root", store.root.path, "--transaction", journal.transactionID]
        if let snapshot = try launch.snapshot(label) {
            guard snapshot.arguments == arguments else { throw UpdateFailure.serviceOwnershipUnknown }
            return
        }
        let plist = try launch.plistURL(label)
        let values: [String: Any] = [
            "Label": label, "ProgramArguments": arguments,
            "RunAtLoad": true, "KeepAlive": ["SuccessfulExit": false], "ThrottleInterval": 5, "Umask": 63,
            "EnvironmentVariables": ["HOME": launch.home.path],
        ]
        let data = try PropertyListSerialization.data(fromPropertyList: values, format: .xml, options: 0)
        try Disk.ownedDirectory(plist.deletingLastPathComponent())
        if Disk.exists(plist), try Disk.read(plist) != data { throw UpdateFailure.serviceOwnershipUnknown }
        try Disk.atomicWrite(data, at: plist)
        guard try launch.run("/bin/launchctl", ["bootstrap", "gui/\(launch.uid)", plist.path]).status == 0 else {
            throw UpdateFailure.candidateFailed
        }
    }

    public static func removeAgentPlist(store: RuntimeStore, journal: UpdateJournal, launch: LaunchService = LaunchService()) throws {
        let label = "dev.codexmulti.app.update." + journal.transactionID
        guard journal.phase.terminal, let snapshot = try launch.snapshot(label),
              snapshot.arguments == [try helperURL(store: store, journal: journal).path, "serve", "--root", store.root.path,
                                      "--transaction", journal.transactionID] else { throw UpdateFailure.serviceOwnershipUnknown }
        let plist = try launch.plistURL(label)
        let values = try PropertyListSerialization.propertyList(from: Disk.read(plist), format: nil) as? [String: Any]
        guard values?["ProgramArguments"] as? [String] == snapshot.arguments else { throw UpdateFailure.serviceOwnershipUnknown }
        try Disk.removePrivateFile(plist)
        try launch.bootout(snapshot)
    }
}
