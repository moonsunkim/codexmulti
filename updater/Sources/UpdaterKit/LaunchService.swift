import Darwin
import Foundation

public struct ServiceSnapshot: Equatable, Sendable {
    public var label: String
    public var arguments: [String]
    public var process: ProcessIdentity?
    public init(label: String, arguments: [String], process: ProcessIdentity? = nil) {
        self.label = label; self.arguments = arguments; self.process = process
    }
}

public struct LaunchService: Sendable {
    public typealias Runner = @Sendable (String, [String]) throws -> CommandResult
    public let home: URL
    public let uid: UInt32
    public let run: Runner
    public let inspectProcess: @Sendable (Int32) throws -> ProcessIdentity?

    public init(home: URL = FileManager.default.homeDirectoryForCurrentUser, uid: UInt32 = getuid(),
                run: @escaping Runner = { try Commands.run($0, $1) },
                inspectProcess: @escaping @Sendable (Int32) throws -> ProcessIdentity? = ProcessIdentity.inspect) {
        self.home = home; self.uid = uid; self.run = run; self.inspectProcess = inspectProcess
    }

    public func target(_ label: String) throws -> String {
        guard label == "dev.codexmulti.app.proxy" || label.hasPrefix("dev.codexmulti.app.update.")
                || label.hasPrefix("dev.codexmulti.tests."), label.count <= 128,
              label.utf8.allSatisfy({ (48...57).contains($0) || (65...90).contains($0) || (97...122).contains($0) || [45, 46, 95].contains($0) }) else {
            throw UpdateFailure.serviceOwnershipUnknown
        }
        return "gui/\(uid)/\(label)"
    }

    public func plistURL(_ label: String) throws -> URL {
        _ = try target(label)
        return home.appendingPathComponent("Library/LaunchAgents", isDirectory: true).appendingPathComponent(label + ".plist")
    }

    public func snapshot(_ label: String) throws -> ServiceSnapshot? {
        let result = try run("/bin/launchctl", ["print", target(label)])
        if result.status != 0 {
            let output = result.output + result.errorOutput
            if output.contains("Could not find service") || output.contains("service not found") { return nil }
            throw UpdateFailure.serviceOwnershipUnknown
        }
        let arguments = try Self.parseArguments(result.output)
        let pidLines = result.output.components(separatedBy: .newlines).map { $0.trimmingCharacters(in: .whitespaces) }
            .filter { $0.hasPrefix("pid = ") }
        guard pidLines.count <= 1 else { throw UpdateFailure.serviceOwnershipUnknown }
        let pid = pidLines.first.flatMap { Int32($0.dropFirst(6)) }
        return ServiceSnapshot(label: label, arguments: arguments, process: try pid.flatMap(inspectProcess))
    }

    public static func parseArguments(_ output: String) throws -> [String] {
        var inside = false
        var found = false
        var arguments: [String] = []
        for raw in output.components(separatedBy: .newlines) {
            let line = raw.trimmingCharacters(in: .whitespaces)
            if line == "arguments = {" {
                guard !found else { throw UpdateFailure.serviceOwnershipUnknown }
                inside = true; found = true
            } else if inside && line == "}" {
                inside = false
            } else if inside {
                guard !line.isEmpty, !line.contains("\0") else { throw UpdateFailure.serviceOwnershipUnknown }
                arguments.append(line)
            }
        }
        guard found, !inside, !arguments.isEmpty else { throw UpdateFailure.serviceOwnershipUnknown }
        return arguments
    }

    public func bootstrap(label: String, arguments: [String], workingDirectory: URL,
                          expectedPlistDigest: String? = nil, logRoot: URL? = nil) throws -> String {
        guard try snapshot(label) == nil, !arguments.isEmpty,
              arguments.allSatisfy({ !$0.contains("\n") && !$0.contains("\0") }) else {
            throw UpdateFailure.serviceOwnershipUnknown
        }
        let plist = try plistURL(label)
        try Disk.ownedDirectory(plist.deletingLastPathComponent())
        if Disk.exists(plist) {
            guard let expectedPlistDigest, try Disk.fileDigest(plist) == expectedPlistDigest else {
                throw UpdateFailure.serviceOwnershipUnknown
            }
        }
        var values: [String: Any] = [
            "Label": label, "ProgramArguments": arguments, "WorkingDirectory": workingDirectory.path,
            "RunAtLoad": true, "KeepAlive": true, "ThrottleInterval": 5, "Umask": 63,
            "EnvironmentVariables": ["HOME": home.path],
        ]
        if let logRoot {
            try Disk.privateDirectory(logRoot)
            values["StandardOutPath"] = logRoot.appendingPathComponent(label + ".log").path
            values["StandardErrorPath"] = logRoot.appendingPathComponent(label + ".error.log").path
        }
        let data = try PropertyListSerialization.data(fromPropertyList: values, format: .xml, options: 0)
        try Disk.atomicWrite(data, at: plist)
        guard try run("/bin/launchctl", ["bootstrap", "gui/\(uid)", plist.path]).status == 0 else {
            throw UpdateFailure.candidateFailed
        }
        return Disk.digest(data)
    }

    public func bootstrap(label: String, data: Data, expectedPlistDigest: String?) throws -> String {
        guard try snapshot(label) == nil,
              let values = try PropertyListSerialization.propertyList(from: data, format: nil) as? [String: Any],
              values["Label"] as? String == label else { throw UpdateFailure.serviceOwnershipUnknown }
        let path = try plistURL(label)
        try Disk.ownedDirectory(path.deletingLastPathComponent())
        if Disk.exists(path), try Disk.fileDigest(path) != expectedPlistDigest { throw UpdateFailure.serviceOwnershipUnknown }
        for key in ["StandardOutPath", "StandardErrorPath"] {
            if let log = values[key] as? String { try Disk.ownedDirectory(URL(fileURLWithPath: log).deletingLastPathComponent()) }
        }
        try Disk.atomicWrite(data, at: path)
        guard try run("/bin/launchctl", ["bootstrap", "gui/\(uid)", path.path]).status == 0 else { throw UpdateFailure.candidateFailed }
        return Disk.digest(data)
    }

    public func bootout(_ expected: ServiceSnapshot) throws {
        guard try snapshot(expected.label) == expected else { throw UpdateFailure.serviceOwnershipUnknown }
        guard try run("/bin/launchctl", ["bootout", target(expected.label)]).status == 0 else {
            throw UpdateFailure.processStillRunning
        }
    }

    public func removed(_ expected: ServiceSnapshot) throws -> Bool {
        guard try snapshot(expected.label) == nil else { return false }
        guard let process = expected.process else { return true }
        guard let current = try inspectProcess(process.pid) else { return true }
        return current != process
    }
}
