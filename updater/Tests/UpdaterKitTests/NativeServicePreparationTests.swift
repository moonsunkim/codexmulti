import Foundation
import XCTest
@testable import UpdaterKit

final class NativeServicePreparationTests: XCTestCase {
    func testCancelledInstalledRuntimeDoesNotApplyItselfAgainAfterGUIRestart() throws {
        guard let oldPath = ProcessInfo.processInfo.environment["CODEXMULTI_UPDATER_TEST_OLD_APP"],
              let newPath = ProcessInfo.processInfo.environment["CODEXMULTI_UPDATER_TEST_NEW_APP"] else {
            throw XCTSkip("Two signed application fixtures are required")
        }
        let home = FileManager.default.temporaryDirectory.appendingPathComponent("codexmulti-cancelled-runtime-\(UUID().uuidString)")
        defer { try? FileManager.default.removeItem(at: home) }
        let store = try RuntimeStore(root: home)
        let old = try store.stage(app: URL(fileURLWithPath: oldPath))
        let app = URL(fileURLWithPath: newPath)
        let new = try store.verifyPayload(in: app)
        try store.select(ActiveRuntime(runtimeID: old.runtimeID, generation: 1))
        let config = store.root.appendingPathComponent("proxy.json").path
        let cancelled = UpdateJournal(phase: .cancelled, appPath: app.path,
            previousAppBuild: old.appBuild, targetAppBuild: new.appBuild,
            oldRuntimeID: old.runtimeID, targetRuntimeID: new.runtimeID,
            configPath: config, configRevision: "", desiredEnabled: true, previousGeneration: 1)
        try store.save(cancelled)
        XCTAssertThrowsError(try UpdatePreparation.externalApp(store: store, app: app, configPath: config, desiredEnabled: true))
        XCTAssertEqual(try store.current()?.transactionID, cancelled.transactionID)
        XCTAssertEqual(try store.active()?.runtimeID, old.runtimeID)
        let service = UpdateJournal(phase: .complete, appPath: app.path,
            previousAppBuild: old.appBuild, targetAppBuild: old.appBuild,
            oldRuntimeID: old.runtimeID, targetRuntimeID: old.runtimeID,
            configPath: config, configRevision: "", desiredEnabled: false, previousGeneration: 1, kind: "service")
        try store.save(service)
        XCTAssertThrowsError(try UpdatePreparation.externalApp(store: store, app: app, configPath: config, desiredEnabled: true)) {
            XCTAssertEqual($0 as? UpdateFailure, .runtimeDeferred)
        }
        let retry = try UpdatePreparation.externalApp(store: store, app: app, configPath: config,
                                                       desiredEnabled: true, automatically: false)
        XCTAssertEqual(retry.phase, .preparingApp)
        XCTAssertNotEqual(retry.transactionID, cancelled.transactionID)
        XCTAssertEqual(try store.active()?.runtimeID, old.runtimeID)
    }

    func testFirstManagedStartCreatesCapabilityAndRejectsForeignInactivePlist() throws {
        guard let appPath = ProcessInfo.processInfo.environment["CODEXMULTI_UPDATER_TEST_OLD_APP"] else {
            throw XCTSkip("A signed application fixture is required")
        }
        let home = FileManager.default.temporaryDirectory.appendingPathComponent("codexmulti-service-preparation-\(UUID().uuidString)")
        defer { try? FileManager.default.removeItem(at: home) }
        let store = try RuntimeStore(root: home.appendingPathComponent("Library/Application Support/CodexMulti"))
        let app = try Disk.canonicalURL(URL(fileURLWithPath: appPath))
        let manifest = try store.stage(app: app)
        try store.select(ActiveRuntime(runtimeID: manifest.runtimeID, generation: 1))
        let launch = LaunchService(home: home, run: { command, arguments in
            XCTAssertEqual(command, "/bin/launchctl")
            XCTAssertEqual(arguments.first, "print")
            return CommandResult(status: 113, output: "", errorOutput: "Could not find service")
        })
        let config = store.root.appendingPathComponent("proxy.json")
        let journal = try ServicePreparation.begin(store: store, app: app, configPath: config.path, enabled: true, launch: launch)
        XCTAssertEqual(journal.phase, .waitingIdle)
        let token = URL(fileURLWithPath: config.path + ".control-token")
        XCTAssertEqual(try Disk.read(token).count, 64)
        XCTAssertEqual(try Disk.checked(token, privateFile: true).st_mode & 0o777, 0o600)
        var completed = journal
        completed.phase = .complete
        try store.save(completed)
        let plist = try launch.plistURL(journal.serviceLabel)
        try Disk.ownedDirectory(plist.deletingLastPathComponent())
        let foreign: [String: Any] = ["Label": journal.serviceLabel, "ProgramArguments": ["/foreign/program"]]
        let bytes = try PropertyListSerialization.data(fromPropertyList: foreign, format: .xml, options: 0)
        try Disk.atomicWrite(bytes, at: plist)
        XCTAssertThrowsError(try ServicePreparation.begin(store: store, app: app, configPath: config.path, enabled: true, launch: launch)) {
            XCTAssertEqual($0 as? UpdateFailure, .serviceOwnershipUnknown)
        }
        XCTAssertEqual(try Disk.read(plist), bytes)
        XCTAssertEqual(try store.current()?.transactionID, journal.transactionID)
        let owned = try ManagedArtifacts.plist(store: store, runtimeID: manifest.runtimeID, configPath: config.path)
        let object = try XCTUnwrap(PropertyListSerialization.propertyList(from: owned, format: nil) as? [String: Any])
        XCTAssertEqual(object["ProgramArguments"] as? [String], try RuntimeOperations.arguments(app: store.bundle(manifest.runtimeID), configPath: config.path))
    }
}
