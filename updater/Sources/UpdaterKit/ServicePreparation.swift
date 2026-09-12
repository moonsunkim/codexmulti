import CryptoKit
import Foundation

public enum ServicePreparation {
    public static func begin(store: RuntimeStore, app: URL, configPath: String, enabled: Bool,
                             clientsClosed: Bool = false, launch: LaunchService = LaunchService()) throws -> UpdateJournal {
        let lock = try FileLock(store.lockURL)
        defer { withExtendedLifetime(lock) {} }
        guard configPath.hasPrefix("/"), !configPath.contains("\n") else { throw UpdateFailure.invalidPath }
        if let current = try store.current(), ![.complete, .cancelled, .rolledBack].contains(current.phase) {
            throw UpdateFailure.updateBusy
        }
        let manifest = try store.verifyPayload(in: app)
        var active = try store.active()
        var legacySnapshot: ServiceSnapshot?
        let label = "dev.codexmulti.app.proxy"
        if active == nil {
            guard clientsClosed else { throw UpdateFailure.migrationRequired }
            legacySnapshot = try launch.snapshot(label)
            if let snapshot = legacySnapshot {
                guard snapshot.arguments == [app.appendingPathComponent("Contents/Helpers/node").path,
                    app.appendingPathComponent("Contents/Resources/proxy/src/server.mjs").path, "--config", configPath],
                      snapshot.process == nil || snapshot.process?.executable == app.appendingPathComponent("Contents/Helpers/node").path else {
                    throw UpdateFailure.serviceOwnershipUnknown
                }
            }
            let legacy = try launch.run("/bin/launchctl", ["print", "gui/\(launch.uid)/com.codexmulti.proxy"])
            guard legacy.status != 0,
                  (legacy.output + legacy.errorOutput).contains("Could not find service") else {
                throw UpdateFailure.serviceOwnershipUnknown
            }
            _ = try store.stage(app: app)
            active = ActiveRuntime(runtimeID: manifest.runtimeID, generation: 1)
        }
        guard let active else { throw UpdateFailure.invalidManifest }
        var journal = UpdateJournal(phase: .waitingIdle, appPath: app.path,
            previousAppBuild: manifest.appBuild, targetAppBuild: manifest.appBuild,
            oldRuntimeID: active.runtimeID, targetRuntimeID: active.runtimeID,
            configPath: configPath, configRevision: "", desiredEnabled: enabled,
            previousGeneration: active.generation, kind: "service")
        journal.guiReady = true
        journal.helperSHA256 = try Disk.fileDigest(UpdatePreparation.helperURL(store: store, journal: journal))
        let plist = try launch.plistURL(label)
        if Disk.exists(plist) {
            let object = try PropertyListSerialization.propertyList(from: Disk.read(plist), format: nil) as? [String: Any]
            let expected = try store.active() == nil
                ? [app.appendingPathComponent("Contents/Helpers/node").path, app.appendingPathComponent("Contents/Resources/proxy/src/server.mjs").path, "--config", configPath]
                : RuntimeOperations.arguments(app: try store.bundle(active.runtimeID), configPath: configPath)
            guard object?["Label"] as? String == label, object?["ProgramArguments"] as? [String] == expected else {
                throw UpdateFailure.serviceOwnershipUnknown
            }
        }
        if enabled {
            let token = URL(fileURLWithPath: configPath + ".control-token")
            if !Disk.exists(token) {
                guard try launch.snapshot(label) == nil else { throw UpdateFailure.identityMismatch }
                let bytes = SymmetricKey(size: .bits256).withUnsafeBytes { Array($0) }
                let text = bytes.map { String(format: "%02x", $0) }.joined()
                try Disk.atomicWrite(Data(text.utf8), at: token)
            }
        }
        journal.oldPlistSHA256 = Disk.exists(plist) ? try Disk.fileDigest(plist) : nil
        if clientsClosed, try store.active() == nil {
            journal.kind = "migration"
            journal.phase = .stopCommitted
            journal.oldPID = legacySnapshot?.process?.pid
            journal.oldProcessStart = legacySnapshot?.process?.start
            try store.save(journal)
            if let snapshot = legacySnapshot {
                try launch.bootout(snapshot)
                guard try launch.removed(snapshot) else { throw UpdateFailure.processStillRunning }
            }
            let writer = try FileLock(store.writerLockURL)
            try store.select(active)
            withExtendedLifetime(writer) {}
        } else {
            try store.save(journal)
        }
        return journal
    }
}
