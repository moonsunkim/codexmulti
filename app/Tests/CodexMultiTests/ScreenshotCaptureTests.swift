import AppKit
import Foundation
import XCTest
@testable import CodexMulti



final class ScreenshotCaptureTests: XCTestCase {
    static let executable = Bundle(for: ScreenshotCaptureTests.self).bundleURL
        .deletingLastPathComponent()
        .appending(path: "CodexMulti")

    private var process: Process?

    override func tearDown() {
        if let process, process.isRunning {
            kill(process.processIdentifier, SIGKILL)
            process.waitUntilExit()
        }
        process = nil
        super.tearDown()
    }

    func testCaptureAndSettingsTabLaunchOptionsParseJoinedAndSplitForms() {
        let split = LaunchOptions(arguments: [
            "CodexMulti", "--capture", "/tmp/readme.png", "--tab", "settings",
        ], environment: [:])
        XCTAssertEqual(split.capturePath, "/tmp/readme.png")
        XCTAssertEqual(split.tab, .failover, "the retained bridge spelling selects the shell's Settings tab")
        XCTAssertTrue(split.headless, "capture mode must suppress every on-screen app surface")
        XCTAssertTrue(split.noActivate)
        XCTAssertTrue(split.noStatusItem)

        let joined = LaunchOptions(arguments: [
            "CodexMulti", "--capture=/tmp/readme.png", "--tab=settings",
        ], environment: [:])
        XCTAssertEqual(joined, split)

        let bare = LaunchOptions(arguments: ["CodexMulti"], environment: [:])
        XCTAssertNil(bare.capturePath)
        XCTAssertFalse(bare.headless)

        let versioned = LaunchOptions(
            arguments: ["CodexMulti", "--capture=/tmp/readme.png"],
            environment: [LaunchOptions.captureVersionEnvironmentKey: "0.2.0 (7)"])
        XCTAssertEqual(versioned.captureVersionText, "0.2.0 (7)")
    }

    @MainActor
    func testCaptureSizeDefaultsToOneThousandBySevenHundredAndUsesOnlyFrameSize() {
        XCTAssertEqual(
            ScreenshotCapture.logicalSize(for: LaunchOptions(
                arguments: ["CodexMulti", "--capture=/tmp/default.png"], environment: [:])),
            CGSize(width: 1_000, height: 700))
        XCTAssertEqual(
            ScreenshotCapture.logicalSize(for: LaunchOptions(arguments: [
                "CodexMulti", "--capture=/tmp/framed.png", "--frame=-3008,44,1200,760",
            ], environment: [:])),
            CGSize(width: 1_200, height: 760))

        let contradictory = LaunchOptions(arguments: [
            "CodexMulti", "--capture=/tmp/silent.png", "--show-window",
        ], environment: [:])
        XCTAssertFalse(contradictory.showWindow, "capture must win over an on-screen presentation flag")
    }

    func testCaptureLaunchWritesRetinaPNGAtRequestedFrameSizeAndExits() throws {
        let directory = FileManager.default.temporaryDirectory
            .appending(path: "codexmulti-capture-test-\(UUID().uuidString)", directoryHint: .isDirectory)
        try FileManager.default.createDirectory(at: directory, withIntermediateDirectories: true)
        defer { try? FileManager.default.removeItem(at: directory) }
        let output = directory.appending(path: "capture.png")
        let lifecycle = directory.appending(path: "lifecycle.log")

        XCTAssertTrue(FileManager.default.isExecutableFile(atPath: Self.executable.path),
                      "missing \(Self.executable.path)")
        let process = Process()
        process.executableURL = Self.executable
        process.arguments = [
            "--fixture=\(Fixtures.exported("proxy-reachable-mapped").path)",
            "--capture=\(output.path)",
            "--frame=0,0,1000,700",
            "--no-activate",
            "--no-status-item",
            "--tab=settings",
            "--set-appearance=dark",
        ]
        process.environment = ProcessInfo.processInfo.environment.merging([
            LaunchOptions.headlessEnvironmentKey: "1",
            LifecycleLog.environmentKey: lifecycle.path,
        ]) { $1 }
        process.standardOutput = FileHandle.nullDevice
        process.standardError = FileHandle.nullDevice
        try process.run()
        self.process = process

        let deadline = ContinuousClock.now + .seconds(5)
        while process.isRunning && ContinuousClock.now < deadline {
            Thread.sleep(forTimeInterval: 0.05)
        }
        XCTAssertFalse(process.isRunning, "capture must write once and exit without a visible window")
        if process.isRunning {
            kill(process.processIdentifier, SIGTERM)
            process.waitUntilExit()
        } else {
            XCTAssertEqual(process.terminationReason, .exit)
            XCTAssertEqual(process.terminationStatus, 0)
        }

        XCTAssertTrue(FileManager.default.fileExists(atPath: output.path), "capture PNG was not written")
        let attributes = try FileManager.default.attributesOfItem(atPath: output.path)
        XCTAssertGreaterThan((attributes[.size] as? NSNumber)?.intValue ?? 0, 100_000,
                             "the full fixture UI, not only an empty pane, must be present")
        let bitmap = try XCTUnwrap(NSBitmapImageRep(data: Data(contentsOf: output)))
        XCTAssertEqual(bitmap.pixelsWide, 2_000)
        XCTAssertEqual(bitmap.pixelsHigh, 1_400)
    }

    func testCaptureLaunchRefusesToEnterTheLiveCoreWithoutAFixture() throws {
        let directory = FileManager.default.temporaryDirectory
            .appending(path: "codexmulti-live-capture-refusal-\(UUID().uuidString)", directoryHint: .isDirectory)
        try FileManager.default.createDirectory(at: directory, withIntermediateDirectories: true)
        defer { try? FileManager.default.removeItem(at: directory) }
        let output = directory.appending(path: "must-not-exist.png")
        let lifecycle = directory.appending(path: "lifecycle.log")

        let process = Process()
        process.executableURL = Self.executable
        process.arguments = ["--capture=\(output.path)"]
        process.environment = ProcessInfo.processInfo.environment.merging([
            LifecycleLog.environmentKey: lifecycle.path,
        ]) { $1 }
        process.standardOutput = FileHandle.nullDevice
        process.standardError = FileHandle.nullDevice
        try process.run()
        self.process = process
        process.waitUntilExit()

        XCTAssertEqual(process.terminationReason, .exit)
        XCTAssertEqual(process.terminationStatus, 2)
        XCTAssertFalse(FileManager.default.fileExists(atPath: output.path))
    }
}
