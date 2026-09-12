import Darwin
import Foundation
import XCTest
@testable import UpdaterKit

final class DiskTests: XCTestCase {
    private func temporaryRoot() throws -> URL {
        let root = FileManager.default.temporaryDirectory.resolvingSymlinksInPath()
            .appendingPathComponent("codexmulti-updater-test-\(UUID().uuidString)", isDirectory: true)
        try Disk.privateDirectory(root)
        addTeardownBlock { try FileManager.default.removeItem(at: root) }
        return root
    }

    func testRuntimeRootKeepsPOSIXCanonicalPathAcrossFoundationNormalization() throws {
        let input = FileManager.default.temporaryDirectory.appendingPathComponent("codexmulti-canonical-\(UUID().uuidString)")
        let store = try RuntimeStore(root: input, verifyBundle: { _ in })
        defer { try? FileManager.default.removeItem(at: input) }
        let pointer = try XCTUnwrap(realpath(input.path, nil))
        defer { free(pointer) }
        XCTAssertEqual(store.root.path, String(cString: pointer))
    }

    func testDurableJournalAndActiveSelectionRoundTrip() throws {
        let store = try RuntimeStore(root: temporaryRoot(), verifyBundle: { _ in })
        let oldID = String(repeating: "a", count: 64)
        let newID = String(repeating: "b", count: 64)
        let journal = UpdateJournal(phase: .waitingIdle, appPath: "/Applications/CodexMulti.app",
            previousAppBuild: "1", targetAppBuild: "2", oldRuntimeID: oldID, targetRuntimeID: newID,
            configPath: "/fixture/proxy.json", configRevision: String(repeating: "c", count: 64),
            desiredEnabled: true, previousGeneration: 7)
        try store.save(journal)
        try store.select(ActiveRuntime(runtimeID: oldID, generation: 7))
        XCTAssertEqual(try store.current()?.transactionID, journal.transactionID)
        XCTAssertEqual(try store.current()?.phase, .waitingIdle)
        XCTAssertEqual(try store.active()?.generation, 7)
        try store.select(ActiveRuntime(runtimeID: newID, generation: 8, transactionID: journal.transactionID))
        XCTAssertEqual(try store.active()?.runtimeID, newID)
        XCTAssertEqual(try store.current()?.phase, .waitingIdle)
        XCTAssertEqual(try Disk.checked(store.activeURL, privateFile: true).st_mode & 0o777, 0o600)
    }

    func testAtomicWriteRejectsSymlinkWithoutTouchingTarget() throws {
        let root = try temporaryRoot()
        let target = root.appendingPathComponent("target")
        try Disk.atomicWrite(Data("keep".utf8), at: target)
        let link = root.appendingPathComponent("link")
        try FileManager.default.createSymbolicLink(at: link, withDestinationURL: target)
        XCTAssertThrowsError(try Disk.atomicWrite(Data("replace".utf8), at: link))
        XCTAssertEqual(try Disk.read(target), Data("keep".utf8))
    }

    func testLockCannotBeStolenAndIsReleasedByDescriptorLifetime() throws {
        let root = try temporaryRoot()
        let file = root.appendingPathComponent("update.lock")
        var lock: FileLock? = try FileLock(file)
        XCTAssertNotNil(lock)
        XCTAssertThrowsError(try FileLock(file)) { XCTAssertEqual($0 as? UpdateFailure, .updateBusy) }
        lock = nil
        let next = try FileLock(file)
        XCTAssertGreaterThanOrEqual(next.descriptor, 0)
    }

    func testInvalidPointerCannotEscapeTransactionDirectory() throws {
        let store = try RuntimeStore(root: temporaryRoot(), verifyBundle: { _ in })
        try Disk.write(UpdatePointer(transactionID: "../../outside"), at: store.pointerURL)
        XCTAssertThrowsError(try store.current()) { XCTAssertEqual($0 as? UpdateFailure, .invalidTransaction) }
    }

    func testPrivateReadRejectsGroupReadableJournal() throws {
        let root = try temporaryRoot()
        let file = root.appendingPathComponent("journal.json")
        try Disk.atomicWrite(Data("{}".utf8), at: file)
        XCTAssertEqual(chmod(file.path, 0o640), 0)
        XCTAssertThrowsError(try Disk.read(file)) { XCTAssertEqual($0 as? UpdateFailure, .unsafePermissions) }
    }
}
