import Darwin
import Foundation

public struct AgentRequest: Codable, Sendable {
    public var command: String
    public var transactionID: String
    public var appPath: String?
    enum CodingKeys: String, CodingKey {
        case command
        case transactionID = "transaction_id", appPath = "app_path"
    }
    public init(_ command: String, transactionID: String, appPath: String? = nil) {
        self.command = command; self.transactionID = transactionID; self.appPath = appPath
    }
}

public struct AgentReply: Codable, Sendable {
    public var journal: UpdateJournal?
    public var error: UpdateFailure?
    public init(journal: UpdateJournal? = nil, error: UpdateFailure? = nil) {
        self.journal = journal; self.error = error
    }
}

public enum AgentConnection {
    public static func socketURL(root: URL) throws -> URL {
        let directory = URL(fileURLWithPath: "/private/tmp/dev.codexmulti.\(getuid())", isDirectory: true)
        try Disk.privateDirectory(directory)
        return directory.appendingPathComponent(String(Disk.digest(Data(root.path.utf8)).prefix(20)) + ".sock")
    }

    static func address(_ path: String) throws -> sockaddr_un {
        var address = sockaddr_un()
        address.sun_family = sa_family_t(AF_UNIX)
        address.sun_len = UInt8(MemoryLayout<sockaddr_un>.size)
        let bytes = Array(path.utf8) + [0]
        guard bytes.count <= MemoryLayout.size(ofValue: address.sun_path) else { throw UpdateFailure.invalidPath }
        withUnsafeMutableBytes(of: &address.sun_path) { destination in destination.copyBytes(from: bytes) }
        return address
    }

    static func configure(_ descriptor: Int32) throws {
        var timeout = timeval(tv_sec: 5, tv_usec: 0)
        var one: Int32 = 1
        guard setsockopt(descriptor, SOL_SOCKET, SO_RCVTIMEO, &timeout, socklen_t(MemoryLayout<timeval>.size)) == 0,
              setsockopt(descriptor, SOL_SOCKET, SO_SNDTIMEO, &timeout, socklen_t(MemoryLayout<timeval>.size)) == 0,
              setsockopt(descriptor, SOL_SOCKET, SO_NOSIGPIPE, &one, socklen_t(MemoryLayout<Int32>.size)) == 0 else {
            throw UpdateFailure.invalidCommand
        }
    }

    static func peer(_ descriptor: Int32) throws -> ProcessIdentity {
        var uid: uid_t = 0
        var gid: gid_t = 0
        var pid: pid_t = 0
        var size = socklen_t(MemoryLayout<pid_t>.size)
        guard getpeereid(descriptor, &uid, &gid) == 0, uid == getuid(),
              getsockopt(descriptor, SOL_LOCAL, LOCAL_PEERPID, &pid, &size) == 0,
              let process = try ProcessIdentity.inspect(pid) else { throw UpdateFailure.invalidSignature }
        return process
    }

    static func read<T: Decodable>(_ type: T.Type, from descriptor: Int32) throws -> T {
        var result = Data()
        var buffer = [UInt8](repeating: 0, count: 4096)
        while true {
            let count = Darwin.read(descriptor, &buffer, buffer.count)
            guard count > 0 else { throw UpdateFailure.invalidCommand }
            result.append(contentsOf: buffer.prefix(count))
            guard result.count <= 65_536 else { throw UpdateFailure.invalidCommand }
            if result.last == 10 {
                let decoder = JSONDecoder()
                decoder.dateDecodingStrategy = .iso8601
                return try decoder.decode(type, from: result)
            }
        }
    }

    static func write<T: Encodable>(_ value: T, to descriptor: Int32) throws {
        let encoder = JSONEncoder()
        encoder.dateEncodingStrategy = .iso8601
        var data = try encoder.encode(value)
        data.append(10)
        guard data.count <= 65_536 else { throw UpdateFailure.invalidCommand }
        try data.withUnsafeBytes { bytes in
            var offset = 0
            while offset < bytes.count {
                let count = Darwin.write(descriptor, bytes.baseAddress!.advanced(by: offset), bytes.count - offset)
                guard count > 0 else { throw UpdateFailure.invalidCommand }
                offset += count
            }
        }
    }

    public static func send(_ request: AgentRequest, store: RuntimeStore) throws -> UpdateJournal {
        let path = try socketURL(root: store.root)
        var info = stat()
        guard lstat(path.path, &info) == 0, (info.st_mode & S_IFMT) == S_IFSOCK,
              info.st_uid == getuid(), (info.st_mode & 0o077) == 0 else { throw UpdateFailure.unsafePermissions }
        let descriptor = socket(AF_UNIX, SOCK_STREAM, 0)
        guard descriptor >= 0 else { throw UpdateFailure.invalidCommand }
        defer { close(descriptor) }
        try configure(descriptor)
        var address = try address(path.path)
        let connected = withUnsafePointer(to: &address) {
            $0.withMemoryRebound(to: sockaddr.self, capacity: 1) { connect(descriptor, $0, socklen_t(MemoryLayout<sockaddr_un>.size)) }
        }
        guard connected == 0 else { throw UpdateFailure.proxyUnreachable }
        let identity = try peer(descriptor)
        let journal = try store.journal(request.transactionID)
        let app = try store.bundle(journal.oldRuntimeID)
        guard identity.executable == app.appendingPathComponent("Contents/Helpers/codexmulti-update-agent").path else {
            throw UpdateFailure.invalidSignature
        }
        try store.verifyBundle(app)
        try write(request, to: descriptor)
        let reply = try read(AgentReply.self, from: descriptor)
        if let error = reply.error { throw error }
        guard let result = reply.journal, result.transactionID == request.transactionID else { throw UpdateFailure.invalidTransaction }
        return result
    }
}

public final class AgentListener: @unchecked Sendable {
    let descriptor: Int32
    let path: URL

    public init(store: RuntimeStore) throws {
        path = try AgentConnection.socketURL(root: store.root)
        var info = stat()
        if lstat(path.path, &info) == 0 {
            guard (info.st_mode & S_IFMT) == S_IFSOCK, info.st_uid == getuid(), (info.st_mode & 0o077) == 0 else {
                throw UpdateFailure.unsafePermissions
            }
            guard unlink(path.path) == 0 else { throw UpdateFailure.unsafePermissions }
        }
        descriptor = socket(AF_UNIX, SOCK_STREAM, 0)
        guard descriptor >= 0 else { throw UpdateFailure.invalidCommand }
        var address = try AgentConnection.address(path.path)
        let result = withUnsafePointer(to: &address) {
            $0.withMemoryRebound(to: sockaddr.self, capacity: 1) { bind(descriptor, $0, socklen_t(MemoryLayout<sockaddr_un>.size)) }
        }
        guard result == 0, chmod(path.path, 0o600) == 0, listen(descriptor, 4) == 0 else {
            close(descriptor); throw UpdateFailure.unsafePermissions
        }
    }

    public func serve(engine: UpdateEngine) async {
        while !Task.isCancelled {
            var poller = pollfd(fd: descriptor, events: Int16(POLLIN), revents: 0)
            if poll(&poller, 1, 500) <= 0 { continue }
            let client = accept(descriptor, nil, nil)
            if client < 0 { continue }
            defer { close(client) }
            do {
                try AgentConnection.configure(client)
                let peer = try AgentConnection.peer(client)
                let request = try AgentConnection.read(AgentRequest.self, from: client)
                let journal = try await engine.state()
                guard request.transactionID == journal.transactionID else { throw UpdateFailure.invalidTransaction }
                let app = URL(fileURLWithPath: journal.appPath)
                guard peer.executable == app.appendingPathComponent("Contents/MacOS/CodexMulti").path else {
                    throw UpdateFailure.invalidSignature
                }
                try engine.store.verifyBundle(app)
                switch request.command {
                case "state": break
                case "cancel": try await engine.requestCancellation()
                case "off": try await engine.requestOff()
                case "arm": try await engine.armInstallation()
                case "download-aborted": try await engine.disarmAfterInstallerAbort()
                case "installer-failed": try await engine.installerFailed()
                case "gui-ready":
                    guard request.appPath == journal.appPath else { throw UpdateFailure.invalidPath }
                    try await engine.markGUIReady(appPath: journal.appPath)
                default: throw UpdateFailure.invalidCommand
                }
                try AgentConnection.write(AgentReply(journal: try await engine.state()), to: client)
            } catch {
                try? AgentConnection.write(AgentReply(error: error as? UpdateFailure ?? .invalidCommand), to: client)
            }
        }
    }

    deinit { close(descriptor); unlink(path.path) }
}
