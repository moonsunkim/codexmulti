import CryptoKit
import Darwin
import Foundation

public enum Disk {
    public static func canonicalURL(_ url: URL) throws -> URL {
        guard let pointer = realpath(url.path, nil) else { throw UpdateFailure.invalidPath }
        defer { free(pointer) }
        return URL(fileURLWithPath: String(cString: pointer))
    }

    public static func digest(_ data: Data) -> String {
        SHA256.hash(data: data).map { String(format: "%02x", $0) }.joined()
    }

    public static func isDigest(_ value: String) -> Bool {
        value.count == 64 && value.utf8.allSatisfy { (48...57).contains($0) || (97...102).contains($0) }
    }

    public static func checked(_ url: URL, directory: Bool = false, privateFile: Bool = false) throws -> stat {
        var info = stat()
        guard lstat(url.path, &info) == 0,
              (info.st_mode & S_IFMT) == (directory ? S_IFDIR : S_IFREG),
              info.st_uid == getuid(), (info.st_mode & 0o022) == 0,
              !privateFile || (info.st_mode & 0o077) == 0 else { throw UpdateFailure.unsafePermissions }
        return info
    }

    public static func privateDirectory(_ url: URL) throws {
        try ownedDirectory(url, privateDirectory: true)
    }

    public static func ownedDirectory(_ url: URL, privateDirectory: Bool = false) throws {
        if !FileManager.default.fileExists(atPath: url.path) {
            try FileManager.default.createDirectory(at: url, withIntermediateDirectories: true,
                                                   attributes: [.posixPermissions: 0o700])
        }
        _ = try checked(url, directory: true, privateFile: privateDirectory)
        guard url.standardizedFileURL.path == url.resolvingSymlinksInPath().path else { throw UpdateFailure.invalidPath }
    }

    public static func read(_ url: URL, privateFile: Bool = true, limit: Int = 1_048_576) throws -> Data {
        let descriptor = open(url.path, O_RDONLY | O_NOFOLLOW | O_CLOEXEC)
        guard descriptor >= 0 else { throw CocoaError(.fileReadNoSuchFile) }
        let handle = FileHandle(fileDescriptor: descriptor, closeOnDealloc: true)
        var info = stat()
        guard fstat(descriptor, &info) == 0, (info.st_mode & S_IFMT) == S_IFREG,
              info.st_uid == getuid(), (info.st_mode & 0o022) == 0,
              !privateFile || (info.st_mode & 0o077) == 0,
              info.st_size >= 0, info.st_size <= limit else { throw UpdateFailure.unsafePermissions }
        return try handle.readToEnd() ?? Data()
    }

    public static func decode<T: Decodable>(_ type: T.Type, at url: URL, privateFile: Bool = true) throws -> T {
        let decoder = JSONDecoder()
        decoder.dateDecodingStrategy = .iso8601
        return try decoder.decode(type, from: read(url, privateFile: privateFile))
    }

    public static func write<T: Encodable>(_ value: T, at url: URL) throws {
        let encoder = JSONEncoder()
        encoder.outputFormatting = [.sortedKeys, .prettyPrinted, .withoutEscapingSlashes]
        encoder.dateEncodingStrategy = .iso8601
        try atomicWrite(try encoder.encode(value), at: url)
    }

    public static func atomicWrite(_ data: Data, at url: URL) throws {
        _ = try checked(url.deletingLastPathComponent(), directory: true)
        if FileManager.default.fileExists(atPath: url.path) { _ = try checked(url, privateFile: true) }
        let temporary = url.deletingLastPathComponent().appendingPathComponent(".\(url.lastPathComponent).\(UUID().uuidString).tmp")
        let descriptor = open(temporary.path, O_WRONLY | O_CREAT | O_EXCL | O_NOFOLLOW | O_CLOEXEC, 0o600)
        guard descriptor >= 0 else { throw CocoaError(.fileWriteUnknown) }
        let handle = FileHandle(fileDescriptor: descriptor, closeOnDealloc: true)
        var committed = false
        defer { if !committed { unlink(temporary.path) } }
        try handle.write(contentsOf: data)
        try handle.synchronize()
        guard rename(temporary.path, url.path) == 0 else { throw CocoaError(.fileWriteUnknown) }
        committed = true
        let parent = open(url.deletingLastPathComponent().path, O_RDONLY | O_DIRECTORY | O_CLOEXEC)
        guard parent >= 0 else { throw CocoaError(.fileWriteUnknown) }
        defer { close(parent) }
        guard fsync(parent) == 0 else { throw CocoaError(.fileWriteUnknown) }
    }

    public static func removePrivateFile(_ url: URL) throws {
        _ = try checked(url, privateFile: true)
        guard unlink(url.path) == 0 else { throw CocoaError(.fileWriteUnknown) }
        let parent = open(url.deletingLastPathComponent().path, O_RDONLY | O_DIRECTORY | O_CLOEXEC)
        guard parent >= 0 else { throw CocoaError(.fileWriteUnknown) }
        defer { close(parent) }
        guard fsync(parent) == 0 else { throw CocoaError(.fileWriteUnknown) }
    }

    public static func fileDigest(_ url: URL) throws -> String {
        _ = try checked(url)
        return digest(try Data(contentsOf: url, options: .mappedIfSafe))
    }

    public static func exists(_ url: URL) -> Bool { FileManager.default.fileExists(atPath: url.path) }
}

public final class FileLock: @unchecked Sendable {
    public let descriptor: Int32

    public init(_ url: URL, blocking: Bool = false) throws {
        let descriptor = open(url.path, O_RDWR | O_CREAT | O_NOFOLLOW | O_CLOEXEC, 0o600)
        guard descriptor >= 0 else { throw UpdateFailure.unsafePermissions }
        var info = stat()
        guard fstat(descriptor, &info) == 0, (info.st_mode & S_IFMT) == S_IFREG,
              info.st_uid == getuid(), (info.st_mode & 0o077) == 0 else {
            close(descriptor); throw UpdateFailure.unsafePermissions
        }
        guard flock(descriptor, LOCK_EX | (blocking ? 0 : LOCK_NB)) == 0 else {
            close(descriptor); throw UpdateFailure.updateBusy
        }
        self.descriptor = descriptor
    }

    deinit { close(descriptor) }
}
