import Foundation

public struct RemovalReceipt: Codable, Sendable {
    public var schema = 1
    public var transactionID: String
    public var runtimeID: String
    public var generation: Int
    public var appPath: String
    enum CodingKeys: String, CodingKey {
        case schema, generation
        case transactionID = "transaction_id", runtimeID = "runtime_id", appPath = "app_path"
    }
}

public enum RemovalPreparation {
    public static func begin(store: RuntimeStore, app: URL, configPath: String) throws -> UpdateJournal {
        var journal = try ServicePreparation.begin(store: store, app: app, configPath: configPath, enabled: false)
        let lock = try FileLock(store.lockURL)
        defer { withExtendedLifetime(lock) {} }
        journal.kind = "removal"
        try store.save(journal)
        return journal
    }

    public static func recordReady(store: RuntimeStore, transactionID: String, launch: LaunchService = LaunchService()) throws {
        let lock = try FileLock(store.lockURL)
        defer { withExtendedLifetime(lock) {} }
        let journal = try store.journal(transactionID)
        guard journal.kind == "removal", journal.phase == .complete, !journal.desiredEnabled,
              let active = try store.active(), active.transactionID == transactionID,
              try launch.snapshot(journal.serviceLabel) == nil,
              !Disk.exists(try launch.plistURL(journal.serviceLabel)) else { throw UpdateFailure.removalNotPrepared }
        let writer = try FileLock(store.writerLockURL)
        try Disk.write(RemovalReceipt(transactionID: transactionID, runtimeID: active.runtimeID,
            generation: active.generation, appPath: journal.appPath), at: store.root.appendingPathComponent("removal-ready.json"))
        withExtendedLifetime(writer) {}
    }

    public static func checkReady(store: RuntimeStore, app: URL, launch: LaunchService = LaunchService()) throws {
        let lock = try FileLock(store.lockURL)
        defer { withExtendedLifetime(lock) {} }
        let receipt = try Disk.decode(RemovalReceipt.self, at: store.root.appendingPathComponent("removal-ready.json"))
        guard receipt.schema == 1, receipt.appPath == app.path,
              let journal = try store.current(), journal.transactionID == receipt.transactionID,
              journal.kind == "removal", journal.phase == .complete, !journal.desiredEnabled, !journal.installArmed,
              let active = try store.active(), active.runtimeID == receipt.runtimeID, active.generation == receipt.generation,
              try launch.snapshot(journal.serviceLabel) == nil,
              !Disk.exists(try launch.plistURL(journal.serviceLabel)) else { throw UpdateFailure.removalNotPrepared }
        let writer = try FileLock(store.writerLockURL)
        withExtendedLifetime(writer) {}
    }
}
