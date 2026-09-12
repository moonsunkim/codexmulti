import AppKit
import Foundation
import XCTest
@testable import CodexMulti









final class LifecycleIntegrationTests: XCTestCase {

    static let executable = Bundle(for: LifecycleIntegrationTests.self).bundleURL
        .deletingLastPathComponent()
        .appending(path: "CodexMulti")


    static let silentLaunchFlags = ["--no-status-item", "--no-activate"]
    static let headlessEnvironment = [LaunchOptions.headlessEnvironmentKey: "1"]

    private var process: Process?

    override func tearDown() {
        if let process, process.isRunning {
            kill(process.processIdentifier, SIGKILL)
            process.waitUntilExit()
        }
        process = nil
    }

    func testSIGTERMDrainsAndExitsWellBeforeTheWatchdog() throws {
        let lifecycle = temporaryLifecycleLog()
        defer { try? FileManager.default.removeItem(at: lifecycle) }
        let process = try launch(fixture: Fixtures.emptyAttached, environment: [LifecycleLog.environmentKey: lifecycle.path])
        XCTAssertTrue(process.isRunning, "the shell must be running before SIGTERM")
        let started = ContinuousClock.now
        kill(process.processIdentifier, SIGTERM)
        waitForExit(process, timeout: .seconds(12))
        let elapsed = ContinuousClock.now - started
        XCTAssertFalse(process.isRunning, "SIGTERM must end the process (hung: the quit path never replied)")
        if !process.isRunning {
            XCTAssertEqual(process.terminationReason, .exit)
            XCTAssertEqual(process.terminationStatus, 0)
        }
        XCTAssertLessThan(elapsed, .seconds(8), "the drained reply, not the 10 s watchdog, must end the process")


        let lines = try lifecycleLines(lifecycle)
        XCTAssertEqual(lines.count, 3, "\(lines)")
        XCTAssertTrue(lines.first?.hasSuffix(" pid=\(process.processIdentifier) build=dev launch") == true, lines.first ?? "")
        XCTAssertTrue(lines.contains { $0.hasSuffix(" reply reason=\"core drained\"") }, "\(lines)")
        XCTAssertTrue(lines.last?.hasSuffix(" will-terminate reason=SIGTERM") == true, lines.last ?? "")
    }

    func testQuitEffectExitsTheProcess() throws {
        var object = try Fixtures.emptyAttachedObject()
        object["effects"] = [["kind": "quit"]]
        let fixture = FileManager.default.temporaryDirectory
            .appending(path: "CodexMulti-quit-effect-\(UUID().uuidString).json")
        try Fixtures.data(from: object).write(to: fixture)
        defer { try? FileManager.default.removeItem(at: fixture) }
        let lifecycle = temporaryLifecycleLog()
        defer { try? FileManager.default.removeItem(at: lifecycle) }
        let process = try launch(fixture: fixture, settle: false, environment: [LifecycleLog.environmentKey: lifecycle.path])
        waitForExit(process, timeout: .seconds(12))
        XCTAssertFalse(process.isRunning, "the quit effect must end the process (hung: terminate called from a dispatch drain)")
        if !process.isRunning {
            XCTAssertEqual(process.terminationReason, .exit)
            XCTAssertEqual(process.terminationStatus, 0)
        }
        let lines = try lifecycleLines(lifecycle)
        XCTAssertTrue(lines.last?.hasSuffix(" will-terminate reason=\"quit effect\"") == true, "\(lines)")
    }



    func testSilentLaunchFlagsAreUnderstoodByTheShell() {
        let flagged = LaunchOptions(arguments: ["CodexMulti"] + Self.silentLaunchFlags, environment: [:])
        XCTAssertTrue(flagged.noStatusItem)
        XCTAssertTrue(flagged.noActivate)
        XCTAssertTrue(flagged.headless)
        XCTAssertFalse(flagged.showWindow)
        let byEnvironment = LaunchOptions(arguments: ["CodexMulti"], environment: Self.headlessEnvironment)
        XCTAssertTrue(byEnvironment.headless)
        XCTAssertFalse(LaunchOptions(arguments: ["CodexMulti", "--no-status-item"], environment: [:]).headless)
        XCTAssertFalse(LaunchOptions(arguments: ["CodexMulti"], environment: [:]).headless)
    }


    @MainActor
    func testHeadlessPresenterRecordsShowSettingsInsteadOfOpening() {
        let presenter = WindowPresenter()
        presenter.headless = true
        var opened = 0
        presenter.open = { opened += 1 }
        presenter.showSettings()
        presenter.showSettings()
        XCTAssertEqual(presenter.suppressedShowRequests, 2)
        XCTAssertEqual(opened, 0)
    }



    func testSilentLaunchCreatesNoStatusBarWindow() throws {
        let process = try launch(fixture: Fixtures.emptyAttached)
        let pid = process.processIdentifier
        let statusLevel = Int(CGWindowLevelForKey(.statusWindow))
        let windows = (CGWindowListCopyWindowInfo([.optionAll], kCGNullWindowID) as? [[String: Any]]) ?? []
        let owned = windows.filter { ($0[kCGWindowOwnerPID as String] as? Int) == Int(pid) }
        let statusWindows = owned.filter { ($0[kCGWindowLayer as String] as? Int) == statusLevel }
        XCTAssertEqual(statusWindows.count, 0, "a status item window exists: \(statusWindows)")
    }



    func testHeadlessStartupFailureExitsWithStatusThree() throws {
        let fixture = FileManager.default.temporaryDirectory
            .appending(path: "CodexMulti-bad-fixture-\(UUID().uuidString).json")
        try Data("{\"schema\":\"not-cm.bridge\"}".utf8).write(to: fixture)
        defer { try? FileManager.default.removeItem(at: fixture) }
        let process = try launch(fixture: fixture, settle: false)
        waitForExit(process, timeout: .seconds(12))
        XCTAssertFalse(process.isRunning, "a failed start must end the process")
        if !process.isRunning {
            XCTAssertEqual(process.terminationReason, .exit)
            XCTAssertEqual(process.terminationStatus, AppDelegate.headlessStartupFailureStatus)
        }
    }







    func testUnsignedLiveCoreFailsWithoutShowingAnEmptyAccountList() throws {
        let home = FileManager.default.temporaryDirectory
            .appending(path: "CodexMulti-home-\(UUID().uuidString)", directoryHint: .isDirectory)
        try FileManager.default.createDirectory(at: home, withIntermediateDirectories: true)
        defer { try? FileManager.default.removeItem(at: home) }
        let process = try launch(fixture: nil, settle: false, environment: ["HOME": home.path])
        waitForExit(process, timeout: .seconds(12))
        XCTAssertFalse(process.isRunning, "an untrusted build must report failed startup")
        let windows = (CGWindowListCopyWindowInfo([.optionAll], kCGNullWindowID) as? [[String: Any]]) ?? []
        let owned = windows.filter { ($0[kCGWindowOwnerPID as String] as? Int) == Int(process.processIdentifier) }
        XCTAssertEqual(owned.count, 0, "the live core launch owns windows: \(owned)")

        if !process.isRunning {
            XCTAssertEqual(process.terminationReason, .exit)
            XCTAssertEqual(process.terminationStatus, AppDelegate.headlessStartupFailureStatus)
        }
    }



    private func temporaryLifecycleLog() -> URL {
        FileManager.default.temporaryDirectory.appending(path: "CodexMulti-lifecycle-\(UUID().uuidString).log")
    }

    private func lifecycleLines(_ url: URL) throws -> [String] {
        try String(contentsOf: url, encoding: .utf8).split(separator: "\n").map(String.init)
    }



    private func launch(fixture: URL?, settle: Bool = true, environment: [String: String] = [:]) throws -> Process {
        XCTAssertTrue(FileManager.default.isExecutableFile(atPath: Self.executable.path), "missing \(Self.executable.path)")
        let process = Process()
        process.executableURL = Self.executable
        process.arguments = (fixture.map { ["--fixture", $0.path] } ?? []) + Self.silentLaunchFlags


        process.environment = ProcessInfo.processInfo.environment
            .merging(Self.headlessEnvironment) { $1 }
            .merging([LifecycleLog.environmentKey: temporaryLifecycleLog().path]) { $1 }
            .merging(environment) { $1 }
        process.standardOutput = FileHandle.nullDevice
        process.standardError = FileHandle.nullDevice
        try process.run()
        self.process = process
        if settle {
            Thread.sleep(forTimeInterval: 2)
        }
        return process
    }

    private func waitForExit(_ process: Process, timeout: Duration) {
        let deadline = ContinuousClock.now + timeout
        while process.isRunning && ContinuousClock.now < deadline {
            Thread.sleep(forTimeInterval: 0.05)
        }
    }
}
