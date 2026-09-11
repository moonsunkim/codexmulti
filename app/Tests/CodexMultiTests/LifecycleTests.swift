import Foundation
import XCTest
@testable import CodexMulti



final class LifecycleTests: XCTestCase {
    func testLaunchOptionsParseTheFixtureArgument() {
        XCTAssertNil(LaunchOptions(arguments: ["CodexMulti"]).fixturePath)
        XCTAssertNil(LaunchOptions(arguments: ["CodexMulti", "--fixture"]).fixturePath)
        XCTAssertEqual(LaunchOptions(arguments: ["CodexMulti", "--fixture", "/tmp/x.json"]).fixturePath, "/tmp/x.json")
    }


    @MainActor
    func testEffectRunnerRepliesWithTheClipboardResult() {
        let effects = RecordingEffects()
        effects.clipboardResult = false
        effects.runner.run([.clipboard(text: "a"), .show_settings, .quit, .clipboard(text: "b")])
        XCTAssertEqual(effects.clipboard, ["a", "b"])
        XCTAssertEqual(effects.replies, [.diagnostics_copied(ok: false), .diagnostics_copied(ok: false)])
        XCTAssertEqual(effects.showSettings, 1)
        XCTAssertEqual(effects.quits, 1)
        XCTAssertEqual(effects.runner.runCount, 4)
    }


    @MainActor
    func testSingleInstanceGuardIgnoresUnbundledAndUnknownIdentifiers() {
        XCTAssertNil(SingleInstanceGuard.otherInstance(bundleIdentifier: nil))
        XCTAssertNil(SingleInstanceGuard.otherInstance(bundleIdentifier: "dev.codexmulti.app.tests.\(UUID().uuidString)"))
    }
}
