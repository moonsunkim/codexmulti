import Darwin
import Foundation

public struct CommandResult: Sendable {
    public var status: Int32
    public var output: String
    public var errorOutput: String
    public init(status: Int32, output: String = "", errorOutput: String = "") {
        self.status = status; self.output = output; self.errorOutput = errorOutput
    }
}

public enum Commands {
    public static func run(_ executable: String, _ arguments: [String], timeout: TimeInterval = 10) throws -> CommandResult {
        let process = Process()
        let output = Pipe()
        let errors = Pipe()
        process.executableURL = URL(fileURLWithPath: executable)
        process.arguments = arguments
        process.standardOutput = output
        process.standardError = errors
        process.standardInput = FileHandle.nullDevice
        try process.run()
        let descriptors = [output.fileHandleForReading.fileDescriptor, errors.fileHandleForReading.fileDescriptor]
        for descriptor in descriptors { _ = fcntl(descriptor, F_SETFL, O_NONBLOCK) }
        let deadline = ProcessInfo.processInfo.systemUptime + timeout
        var captured = [Data(), Data()]
        var buffer = [UInt8](repeating: 0, count: 8192)
        while true {
            for (index, descriptor) in descriptors.enumerated() {
                while true {
                    let count = Darwin.read(descriptor, &buffer, buffer.count)
                    if count <= 0 { break }
                    captured[index].append(contentsOf: buffer.prefix(count))
                    if captured[index].count > 262_144 {
                        if process.isRunning { kill(process.processIdentifier, SIGKILL) }
                        process.waitUntilExit()
                        throw UpdateFailure.serviceOwnershipUnknown
                    }
                }
            }
            if !process.isRunning { break }
            if ProcessInfo.processInfo.systemUptime >= deadline {
                kill(process.processIdentifier, SIGKILL)
                process.waitUntilExit()
                throw UpdateFailure.serviceOwnershipUnknown
            }
            usleep(10_000)
        }
        process.waitUntilExit()
        for (index, descriptor) in descriptors.enumerated() {
            while true {
                let count = Darwin.read(descriptor, &buffer, buffer.count)
                if count <= 0 { break }
                captured[index].append(contentsOf: buffer.prefix(count))
                if captured[index].count > 262_144 { throw UpdateFailure.serviceOwnershipUnknown }
            }
        }
        return CommandResult(status: process.terminationStatus,
            output: String(decoding: captured[0], as: UTF8.self),
            errorOutput: String(decoding: captured[1], as: UTF8.self))
    }
}

public struct ProcessIdentity: Codable, Equatable, Sendable {
    public var pid: Int32
    public var start: String
    public var executable: String

    public static func inspect(_ pid: Int32) throws -> ProcessIdentity? {
        guard pid > 0 else { throw UpdateFailure.serviceOwnershipUnknown }
        var info = proc_bsdinfo()
        let size = Int32(MemoryLayout<proc_bsdinfo>.size)
        let result = proc_pidinfo(pid, PROC_PIDTBSDINFO, 0, &info, size)
        if result != size, kill(pid, 0) != 0, errno == ESRCH { return nil }
        guard result == size, info.pbi_uid == getuid() else { throw UpdateFailure.serviceOwnershipUnknown }
        var path = [CChar](repeating: 0, count: 4 * Int(MAXPATHLEN))
        guard proc_pidpath(pid, &path, UInt32(path.count)) > 0 else {
            if kill(pid, 0) != 0, errno == ESRCH { return nil }
            if info.pbi_status == SZOMB { return nil }
            throw UpdateFailure.serviceOwnershipUnknown
        }
        return ProcessIdentity(pid: pid, start: "\(info.pbi_start_tvsec)-\(info.pbi_start_tvusec)",
                               executable: String(cString: path))
    }
}
