import Foundation

public struct RuntimeOperations: Sendable {
    public var ownedPlistDigest: @Sendable (String, UpdateJournal) throws -> String? = { _, _ in nil }
    public var plannedPlistDigest: @Sendable (String, UpdateJournal) throws -> String? = { _, _ in nil }
    public var recordHealth: @Sendable (String, UpdateJournal) throws -> Void = { _, _ in }
    public var removeServiceArtifacts: @Sendable (UpdateJournal) throws -> Void = { _ in }
    public var setRoutingOn: @Sendable (UpdateJournal) throws -> Void = { _ in }
    public var snapshot: @Sendable (String) throws -> ServiceSnapshot?
    public var bootout: @Sendable (ServiceSnapshot) throws -> Void
    public var removed: @Sendable (ServiceSnapshot) throws -> Bool
    public var process: @Sendable (Int32) throws -> ProcessIdentity?
    public var writerAvailable: @Sendable () throws -> Bool
    public var bootstrap: @Sendable (String, UpdateJournal) throws -> String
    public var plistDigest: @Sendable (String) throws -> String?
    public var client: @Sendable (String) throws -> ProxyClient
    public var setRoutingOff: @Sendable (UpdateJournal) throws -> Void

    public init(store: RuntimeStore, launch: LaunchService = LaunchService()) {
        self.ownedPlistDigest = { runtimeID, journal in
            let path = try launch.plistURL(journal.serviceLabel)
            guard Disk.exists(path) else { return nil }
            let bytes = try Disk.read(path)
            guard bytes == (try ManagedArtifacts.plist(store: store, runtimeID: runtimeID, configPath: journal.configPath, serviceLabel: journal.serviceLabel)) else {
                throw UpdateFailure.serviceOwnershipUnknown
            }
            return Disk.digest(bytes)
        }
        self.plannedPlistDigest = { runtimeID, journal in
            Disk.digest(try ManagedArtifacts.plist(store: store, runtimeID: runtimeID, configPath: journal.configPath, serviceLabel: journal.serviceLabel))
        }
        self.recordHealth = { try ManagedArtifacts.recordHealth(store: store, runtimeID: $0, journal: $1) }
        self.setRoutingOn = { journal in
            let app = try store.bundle(journal.rollbackAttempted ? journal.oldRuntimeID : journal.targetRuntimeID)
            guard try Commands.run(app.appendingPathComponent("Contents/Helpers/codexmulti-maintenance").path, ["routing-on"]).status == 0 else {
                throw UpdateFailure.recoveryRequired
            }
        }
        self.removeServiceArtifacts = { journal in
            let path = try launch.plistURL(journal.serviceLabel)
            guard try launch.snapshot(journal.serviceLabel) == nil else { throw UpdateFailure.processStillRunning }
            if Disk.exists(path) {
                let digest = try Disk.fileDigest(path)
                guard digest == journal.oldPlistSHA256 || digest == journal.candidatePlistSHA256 else { throw UpdateFailure.serviceOwnershipUnknown }
                try Disk.removePrivateFile(path)
            }
        }
        self.snapshot = launch.snapshot
        self.bootout = launch.bootout
        self.removed = launch.removed
        self.process = launch.inspectProcess
        self.writerAvailable = {
            do { let lock = try FileLock(store.writerLockURL); _ = lock.descriptor; return true }
            catch UpdateFailure.updateBusy { return false }
        }
        self.bootstrap = { runtimeID, journal in
            let app = try store.bundle(runtimeID)
            _ = try store.verifyPayload(in: app)
            let plistURL = try launch.plistURL(journal.serviceLabel)
            let currentDigest = Disk.exists(plistURL) ? try Disk.fileDigest(plistURL) : nil
            guard currentDigest == nil || currentDigest == journal.oldPlistSHA256 || currentDigest == journal.candidatePlistSHA256 else {
                throw UpdateFailure.serviceOwnershipUnknown
            }
            let data = try ManagedArtifacts.plist(store: store, runtimeID: runtimeID, configPath: journal.configPath, serviceLabel: journal.serviceLabel)
            guard Disk.digest(data) == journal.candidatePlistSHA256 else { throw UpdateFailure.identityMismatch }
            return try launch.bootstrap(label: journal.serviceLabel, data: data, expectedPlistDigest: currentDigest)
        }
        self.plistDigest = { label in
            let file = try launch.plistURL(label)
            return Disk.exists(file) ? try Disk.fileDigest(file) : nil
        }
        self.client = { try ProxyClient(configPath: URL(fileURLWithPath: $0)) }
        self.setRoutingOff = { journal in
            let app = try store.bundle(journal.oldRuntimeID)
            let helper = app.appendingPathComponent("Contents/Helpers/codexmulti-maintenance")
            guard try Commands.run(helper.path, ["routing-off"]).status == 0 else { throw UpdateFailure.recoveryRequired }
        }
    }

    public init(snapshot: @escaping @Sendable (String) throws -> ServiceSnapshot?,
                bootout: @escaping @Sendable (ServiceSnapshot) throws -> Void,
                removed: @escaping @Sendable (ServiceSnapshot) throws -> Bool,
                process: @escaping @Sendable (Int32) throws -> ProcessIdentity?,
                writerAvailable: @escaping @Sendable () throws -> Bool,
                bootstrap: @escaping @Sendable (String, UpdateJournal) throws -> String,
                plistDigest: @escaping @Sendable (String) throws -> String?,
                client: @escaping @Sendable (String) throws -> ProxyClient,
                setRoutingOff: @escaping @Sendable (UpdateJournal) throws -> Void = { _ in }) {
        self.snapshot = snapshot; self.bootout = bootout; self.removed = removed; self.process = process
        self.writerAvailable = writerAvailable; self.bootstrap = bootstrap; self.plistDigest = plistDigest
        self.client = client; self.setRoutingOff = setRoutingOff
    }

    public static func arguments(app: URL, configPath: String) -> [String] {
        [app.appendingPathComponent("Contents/Helpers/codexmulti-runtime-launcher").path, "--config", configPath, "--managed"]
    }
}
