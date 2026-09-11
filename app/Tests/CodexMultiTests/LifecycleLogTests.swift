import Foundation
import XCTest
@testable import CodexMulti






final class LifecycleLogTests: XCTestCase {
    private let stamp = Date(timeIntervalSince1970: 1_789_812_033)
    private let utc = TimeZone(identifier: "UTC")!

    func testExitReasonsReadAsOneShortPhrase() {
        XCTAssertEqual(ExitReason.quitEffect.text, "quit effect")
        XCTAssertEqual(ExitReason.trayQuit.text, "tray Quit before the core started")
        XCTAssertEqual(ExitReason.signal(SIGTERM).text, "SIGTERM")
        XCTAssertEqual(ExitReason.signal(SIGINT).text, "SIGINT")
        XCTAssertEqual(ExitReason.signal(SIGHUP).text, "signal 1")
        XCTAssertEqual(ExitReason.systemTerminate(sender: "osascript (pid 4242)").text, "terminate: from osascript (pid 4242)")
        XCTAssertEqual(ExitReason.systemTerminate(sender: nil).text, "terminate: (sender unknown)")
        XCTAssertEqual(ExitReason.startupFailure("core bridge version 2").text, "startup failure: core bridge version 2")
        XCTAssertEqual(ExitReason.duplicateInstance(pid: 76764).text, "another instance is running (pid 76764)")
        XCTAssertEqual(ExitReason.unknown.text, "unknown (no quit path noted)")
    }



    func testLinesCarryTimePidBuildEventAndQuotedFields() {
        XCTAssertEqual(LifecycleLog.line(pid: 76764, build: "37", event: "launch", fields: [], at: stamp, zone: utc),
                       "2026-09-19T10:00:33Z pid=76764 build=37 launch")
        XCTAssertEqual(LifecycleLog.line(pid: 76764, build: "37", event: "will-terminate", fields: [("reason", "quit effect")], at: stamp, zone: utc),
                       "2026-09-19T10:00:33Z pid=76764 build=37 will-terminate reason=\"quit effect\"")
        XCTAssertEqual(LifecycleLog.line(pid: 1, build: "dev", event: "reply", fields: [("reason", "SIGTERM")], at: stamp, zone: utc),
                       "2026-09-19T10:00:33Z pid=1 build=dev reply reason=SIGTERM")
        XCTAssertEqual(LifecycleLog.line(pid: 1, build: "dev", event: "exception",
                                         fields: [("name", "NSInvalidArgumentException"), ("reason", "say \"hi\"")], at: stamp, zone: utc),
                       "2026-09-19T10:00:33Z pid=1 build=dev exception name=NSInvalidArgumentException reason=\"say \\\"hi\\\"\"")
        let seoul = TimeZone(identifier: "Asia/Seoul")!
        XCTAssertTrue(LifecycleLog.line(pid: 1, build: "37", event: "launch", fields: [], at: stamp, zone: seoul).hasPrefix("2026-09-19T19:00:33+09:00 "))
    }



    func testSignalLineIsBuiltWithoutAllocation() {
        let prefix = Array(" pid=76764 build=37 signal number=".utf8)
        var buffer = [UInt8](repeating: 0, count: 128)
        let length = prefix.withUnsafeBufferPointer { prefixBuffer in
            buffer.withUnsafeMutableBufferPointer { out in
                LifecycleLog.formatSignalLine(unix: 1_789_812_033, prefix: prefixBuffer, signal: SIGSEGV, into: out)
            }
        }
        XCTAssertEqual(String(decoding: buffer[0..<length], as: UTF8.self), "1789812033 pid=76764 build=37 signal number=11 name=SIGSEGV\n")
        let short = prefix.withUnsafeBufferPointer { prefixBuffer in
            buffer.withUnsafeMutableBufferPointer { out in
                LifecycleLog.formatSignalLine(unix: 0, prefix: prefixBuffer, signal: SIGBUS, into: out)
            }
        }
        XCTAssertEqual(String(decoding: buffer[0..<short], as: UTF8.self), "0 pid=76764 build=37 signal number=10 name=SIGBUS\n")
        XCTAssertEqual(LifecycleLog.signalName(SIGABRT), "SIGABRT")
        XCTAssertEqual(LifecycleLog.signalName(SIGSEGV), "SIGSEGV")
        XCTAssertEqual(LifecycleLog.signalName(SIGBUS), "SIGBUS")
        XCTAssertEqual(LifecycleLog.signalName(SIGTERM), "SIGTERM")
        XCTAssertEqual(LifecycleLog.signalName(SIGINT), "SIGINT")
        XCTAssertEqual(LifecycleLog.signalName(SIGHUP), "")
        var tiny = [UInt8](repeating: 0, count: 8)
        let truncated = prefix.withUnsafeBufferPointer { prefixBuffer in
            tiny.withUnsafeMutableBufferPointer { out in
                LifecycleLog.formatSignalLine(unix: 1_789_812_033, prefix: prefixBuffer, signal: SIGSEGV, into: out)
            }
        }
        XCTAssertEqual(truncated, 8, "a small buffer is filled, never overrun")
    }



    func testFileGetsLaunchNotedExitReplyAndExceptionLines() throws {
        let directory = FileManager.default.temporaryDirectory.appending(path: "codexmulti-lifecycle-\(UUID().uuidString)")
        let url = directory.appending(path: "nested/lifecycle.log")
        let log = try XCTUnwrap(LifecycleLog(url: url, pid: 4242, build: "37"))
        log.launch()
        log.note(.signal(SIGTERM))
        log.reply("core drained")
        log.exception(name: "NSRangeException", reason: "index 3 beyond bounds")
        log.exit()
        let lines = try String(contentsOf: url, encoding: .utf8).split(separator: "\n").map(String.init)
        XCTAssertEqual(lines.count, 4)
        XCTAssertTrue(lines[0].hasSuffix(" pid=4242 build=37 launch"), lines[0])
        XCTAssertTrue(lines[1].hasSuffix(" pid=4242 build=37 reply reason=\"core drained\""), lines[1])
        XCTAssertTrue(lines[2].hasSuffix(" pid=4242 build=37 exception name=NSRangeException reason=\"index 3 beyond bounds\""), lines[2])
        XCTAssertTrue(lines[3].hasSuffix(" pid=4242 build=37 will-terminate reason=SIGTERM"), lines[3])
        XCTAssertEqual(log.notedReason, .signal(SIGTERM))
        let again = try XCTUnwrap(LifecycleLog(url: url, pid: 4243, build: "37"))
        again.launch()
        again.exit()
        let appended = try String(contentsOf: url, encoding: .utf8).split(separator: "\n")
        XCTAssertEqual(appended.count, 6, "appends, never truncates")
        XCTAssertTrue(appended[5].hasSuffix("will-terminate reason=\"unknown (no quit path noted)\""), String(appended[5]))
        try? FileManager.default.removeItem(at: directory)
    }



    func testFirstNotedReasonWins() throws {
        let url = FileManager.default.temporaryDirectory.appending(path: "codexmulti-lifecycle-\(UUID().uuidString).log")
        let log = try XCTUnwrap(LifecycleLog(url: url, pid: 1, build: "dev"))
        log.note(.quitEffect)
        log.note(.signal(SIGTERM))
        XCTAssertEqual(log.notedReason, .quitEffect)
        try? FileManager.default.removeItem(at: url)
    }



    func testDefaultPathIsUnderLibraryLogsUnlessOverridden() {
        XCTAssertEqual(LifecycleLog.url(environment: [:], home: "/Users/x").path, "/Users/x/Library/Logs/CodexMulti/lifecycle.log")
        XCTAssertEqual(LifecycleLog.url(environment: [LifecycleLog.environmentKey: "/tmp/l.log"], home: "/Users/x").path, "/tmp/l.log")
        XCTAssertEqual(LifecycleLog.environmentKey, "CODEXMULTI_LIFECYCLE_LOG")
    }
}
