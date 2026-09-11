import AppKit
import Darwin
import Foundation




enum ExitReason: Equatable, Sendable {

    case quitEffect

    case trayQuit

    case signal(Int32)


    case systemTerminate(sender: String?)

    case startupFailure(String)

    case duplicateInstance(pid: Int32)

    case unknown

    var text: String {
        switch self {
        case .quitEffect: return "quit effect"
        case .trayQuit: return "tray Quit before the core started"
        case .signal(let number):
            let name = LifecycleLog.signalName(number)
            return name.isEmpty ? "signal \(number)" : name
        case .systemTerminate(let sender):
            return sender.map { "terminate: from \($0)" } ?? "terminate: (sender unknown)"
        case .startupFailure(let detail): return "startup failure: \(detail)"
        case .duplicateInstance(let pid): return "another instance is running (pid \(pid))"
        case .unknown: return "unknown (no quit path noted)"
        }
    }
}













final class LifecycleLog: @unchecked Sendable {
    static let environmentKey = "CODEXMULTI_LIFECYCLE_LOG"

    nonisolated(unsafe) static var shared: LifecycleLog?

    let url: URL
    let pid: Int32
    let build: String
    private(set) var notedReason: ExitReason?

    private let descriptor: Int32
    private let lock = NSLock()

    private let signalPrefix: UnsafeMutableBufferPointer<UInt8>
    private let signalBuffer: UnsafeMutableBufferPointer<UInt8>


    static func url(environment: [String: String] = ProcessInfo.processInfo.environment, home: String = NSHomeDirectory()) -> URL {
        if let override = environment[environmentKey], !override.isEmpty {
            return URL(fileURLWithPath: override)
        }
        return URL(fileURLWithPath: home).appending(path: "Library/Logs/CodexMulti/lifecycle.log")
    }


    init?(url: URL, pid: Int32 = ProcessInfo.processInfo.processIdentifier, build: String = LifecycleLog.bundleBuild()) {
        self.url = url
        self.pid = pid
        self.build = build
        try? FileManager.default.createDirectory(at: url.deletingLastPathComponent(), withIntermediateDirectories: true)
        let fd = open(url.path, O_WRONLY | O_APPEND | O_CREAT | O_CLOEXEC, 0o644)
        guard fd >= 0 else { return nil }
        descriptor = fd
        let prefix = Array(" pid=\(pid) build=\(build) signal number=".utf8)
        signalPrefix = .allocate(capacity: prefix.count)
        _ = signalPrefix.initialize(from: prefix)
        signalBuffer = .allocate(capacity: 160)
        signalBuffer.initialize(repeating: 0)
    }


    static func bundleBuild() -> String {
        (Bundle.main.object(forInfoDictionaryKey: "CFBundleVersion") as? String) ?? "dev"
    }



    func launch() {
        write(Self.line(pid: pid, build: build, event: "launch", fields: []))
    }



    func note(_ reason: ExitReason) {
        lock.lock(); defer { lock.unlock() }
        if notedReason == nil { notedReason = reason }
    }


    func reply(_ reason: String) {
        write(Self.line(pid: pid, build: build, event: "reply", fields: [("reason", reason)]))
    }


    func exit() {
        let reason = lock.withLock { notedReason } ?? .unknown
        write(Self.line(pid: pid, build: build, event: "will-terminate", fields: [("reason", reason.text)]))
    }

    func exception(name: String, reason: String?) {
        write(Self.line(pid: pid, build: build, event: "exception", fields: [("name", name), ("reason", reason ?? "")]))
    }



    static func line(pid: Int32, build: String, event: String, fields: [(String, String)],
                     at date: Date = Date(), zone: TimeZone = .current) -> String {
        var text = "\(timestamp(date, zone: zone)) pid=\(pid) build=\(build) \(event)"
        for (key, value) in fields {
            text += " \(key)=\(quoted(value))"
        }
        return text
    }

    private static func timestamp(_ date: Date, zone: TimeZone) -> String {
        let formatter = ISO8601DateFormatter()
        formatter.timeZone = zone
        formatter.formatOptions = [.withInternetDateTime]
        return formatter.string(from: date)
    }

    private static func quoted(_ value: String) -> String {
        let plain = !value.isEmpty && !value.contains { $0 == " " || $0 == "\"" || $0 == "\n" }
        if plain { return value }
        return "\"" + value.replacingOccurrences(of: "\\", with: "\\\\").replacingOccurrences(of: "\"", with: "\\\"").replacingOccurrences(of: "\n", with: " ") + "\""
    }

    private func write(_ line: String) {
        let data = Array((line + "\n").utf8)
        lock.lock(); defer { lock.unlock() }
        data.withUnsafeBufferPointer { bytes in
            _ = Darwin.write(descriptor, bytes.baseAddress, bytes.count)
        }
    }





    func installCrashHandlers() {
        Self.shared = self
        for number in [SIGABRT, SIGSEGV, SIGBUS] {
            var action = sigaction()
            action.__sigaction_u.__sa_handler = { number in
                LifecycleLog.shared?.writeSignalLine(number)
                signal(number, SIG_DFL)
                raise(number)
            }
            action.sa_flags = SA_RESETHAND | SA_NODEFER
            sigemptyset(&action.sa_mask)
            sigaction(number, &action, nil)
        }
        NSSetUncaughtExceptionHandler { exception in
            LifecycleLog.shared?.exception(name: exception.name.rawValue, reason: exception.reason)
        }
    }


    private func writeSignalLine(_ number: Int32) {
        let length = Self.formatSignalLine(unix: time(nil), prefix: UnsafeBufferPointer(signalPrefix), signal: number, into: signalBuffer)
        _ = Darwin.write(descriptor, signalBuffer.baseAddress, length)
    }



    static func formatSignalLine(unix: Int, prefix: UnsafeBufferPointer<UInt8>, signal number: Int32,
                                 into buffer: UnsafeMutableBufferPointer<UInt8>) -> Int {
        var count = 0
        func put(_ byte: UInt8) {
            if count < buffer.count { buffer[count] = byte; count += 1 }
        }
        func digits(_ value: Int) {
            var value = value
            var reversed: (UInt8, UInt8, UInt8, UInt8, UInt8, UInt8, UInt8, UInt8, UInt8, UInt8, UInt8, UInt8, UInt8, UInt8, UInt8, UInt8, UInt8, UInt8, UInt8, UInt8) = (0, 0, 0, 0, 0, 0, 0, 0, 0, 0, 0, 0, 0, 0, 0, 0, 0, 0, 0, 0)
            var length = 0
            if value <= 0 { put(UInt8(ascii: "0")); return }
            withUnsafeMutableBytes(of: &reversed) { raw in
                while value > 0, length < raw.count {
                    raw[length] = UInt8(ascii: "0") + UInt8(value % 10)
                    value /= 10
                    length += 1
                }
                var index = length - 1
                while index >= 0 { put(raw[index]); index -= 1 }
            }
        }
        digits(unix)
        for byte in prefix { put(byte) }
        digits(Int(number))
        for byte in " name=".utf8 { put(byte) }
        for byte in signalName(number).utf8 { put(byte) }
        put(UInt8(ascii: "\n"))
        return count
    }


    static func signalName(_ number: Int32) -> String {
        switch number {
        case SIGABRT: "SIGABRT"
        case SIGSEGV: "SIGSEGV"
        case SIGBUS: "SIGBUS"
        case SIGTERM: "SIGTERM"
        case SIGINT: "SIGINT"
        default: ""
        }
    }





    @MainActor static func currentAppleEventSender() -> String? {
        guard let event = NSAppleEventManager.shared().currentAppleEvent,
              let pidValue = event.attributeDescriptor(forKeyword: AEKeyword(keySenderPIDAttr))?.int32Value, pidValue > 0 else { return nil }
        let name = NSRunningApplication(processIdentifier: pidValue)?.localizedName
            ?? NSRunningApplication(processIdentifier: pidValue)?.bundleIdentifier
            ?? "pid \(pidValue)"
        return "\(name) (pid \(pidValue))"
    }
}
