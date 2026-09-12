import Darwin
import Foundation

public struct RuntimeStore: Sendable {
    public let root: URL
    public let verifyBundle: @Sendable (URL) throws -> Void
    public var runtimes: URL { root.appendingPathComponent("runtimes", isDirectory: true) }
    public var updates: URL { root.appendingPathComponent("updates", isDirectory: true) }
    public var activeURL: URL { root.appendingPathComponent("active-runtime.json") }
    public var pointerURL: URL { root.appendingPathComponent("current-update.json") }
    public var deferredURL: URL { root.appendingPathComponent("deferred-runtime.json") }
    public var lockURL: URL { root.appendingPathComponent("update.lock") }
    public var writerLockURL: URL { root.appendingPathComponent("runtime-writer.lock") }

    public init(root: URL, verifyBundle: @escaping @Sendable (URL) throws -> Void = { try Signatures.verify($0) }) throws {
        try Disk.privateDirectory(root)
        self.root = try Disk.canonicalURL(root)
        self.verifyBundle = verifyBundle
        try Disk.privateDirectory(runtimes)
        try Disk.privateDirectory(updates)
    }

    public static var defaultRoot: URL {
        FileManager.default.homeDirectoryForCurrentUser.appendingPathComponent("Library/Application Support/CodexMulti", isDirectory: true)
    }

    public func bundle(_ runtimeID: String) throws -> URL {
        guard Disk.isDigest(runtimeID) else { throw UpdateFailure.invalidManifest }
        return runtimes.appendingPathComponent(runtimeID, isDirectory: true).appendingPathComponent("CodexMulti.app", isDirectory: true)
    }

    public func transactionDirectory(_ id: String) throws -> URL {
        guard UUID(uuidString: id) != nil, id == id.lowercased() else { throw UpdateFailure.invalidTransaction }
        return updates.appendingPathComponent(id, isDirectory: true)
    }

    public func journalURL(_ id: String) throws -> URL {
        try transactionDirectory(id).appendingPathComponent("journal.json")
    }

    public func active() throws -> ActiveRuntime? {
        guard Disk.exists(activeURL) else { return nil }
        let value = try Disk.decode(ActiveRuntime.self, at: activeURL)
        guard value.schema == 1, Disk.isDigest(value.runtimeID), value.generation >= 1, value.epoch >= 1 else {
            throw UpdateFailure.invalidManifest
        }
        return value
    }

    public func current() throws -> UpdateJournal? {
        guard Disk.exists(pointerURL) else { return nil }
        let pointer = try Disk.decode(UpdatePointer.self, at: pointerURL)
        guard pointer.schema == 1 else { throw UpdateFailure.invalidTransaction }
        return try journal(pointer.transactionID)
    }

    public func deferred() throws -> DeferredRuntime? {
        guard Disk.exists(deferredURL) else { return nil }
        let value = try Disk.decode(DeferredRuntime.self, at: deferredURL)
        guard value.schema == 1, Disk.isDigest(value.runtimeID), !value.appBuild.isEmpty else { throw UpdateFailure.invalidManifest }
        return value
    }

    public func journal(_ id: String) throws -> UpdateJournal {
        let value = try Disk.decode(UpdateJournal.self, at: journalURL(id))
        guard value.schema == 1, value.transactionID == id, value.epoch > 0,
              Disk.isDigest(value.oldRuntimeID), Disk.isDigest(value.targetRuntimeID),
              value.configPath.hasPrefix("/"), value.previousGeneration > 0,
              value.activationGeneration > value.previousGeneration else { throw UpdateFailure.invalidTransaction }
        return value
    }

    public func save(_ journal: UpdateJournal) throws {
        var journal = journal
        let path = try journalURL(journal.transactionID)
        if Disk.exists(path) {
            let current = try self.journal(journal.transactionID)
            guard current.epoch == journal.epoch else { throw UpdateFailure.invalidTransaction }
            journal.cancellationRequested = journal.cancellationRequested || current.cancellationRequested
            journal.desiredEnabled = journal.desiredEnabled && current.desiredEnabled
        }
        journal.updatedAt = Date()
        if [.cancelled, .rolledBack].contains(journal.phase), journal.targetRuntimeID != journal.oldRuntimeID {
            try Disk.write(DeferredRuntime(appBuild: journal.targetAppBuild, runtimeID: journal.targetRuntimeID), at: deferredURL)
        }
        try Disk.privateDirectory(transactionDirectory(journal.transactionID))
        try Disk.write(journal, at: path)
        try Disk.write(UpdatePointer(transactionID: journal.transactionID), at: pointerURL)
        if journal.phase == .complete, let deferred = try deferred(),
           deferred.appBuild == journal.targetAppBuild, deferred.runtimeID == journal.targetRuntimeID {
            try Disk.removePrivateFile(deferredURL)
        }
    }

    public func select(_ active: ActiveRuntime) throws { try Disk.write(active, at: activeURL) }

    public func manifest(in app: URL) throws -> RuntimeManifest {
        let manifest = try Disk.decode(RuntimeManifest.self,
            at: app.appendingPathComponent("Contents/Resources/runtime-manifest.json"), privateFile: false)
        try manifest.validate()
        return manifest
    }

    public func verifyPayload(in app: URL) throws -> RuntimeManifest {
        _ = try Disk.checked(app, directory: true)
        guard app.standardizedFileURL.path == app.resolvingSymlinksInPath().path else { throw UpdateFailure.invalidPath }
        try verifyBundle(app)
        let manifest = try manifest(in: app)
        let proxy = app.appendingPathComponent("Contents/Resources/proxy", isDirectory: true)
        var actualFiles: [String: String] = [:]
        var tree: [String] = []
        func inventory(_ relative: String) throws {
            let url = proxy.appendingPathComponent(relative)
            var info = stat()
            guard lstat(url.path, &info) == 0 else { throw UpdateFailure.payloadMismatch }
            if (info.st_mode & S_IFMT) == S_IFDIR {
                for name in try FileManager.default.contentsOfDirectory(atPath: url.path).sorted() {
                    try inventory(relative + "/" + name)
                }
            } else {
                guard (info.st_mode & S_IFMT) == S_IFREG,
                      !relative.contains(where: { "\t\r\n".contains($0) }) else { throw UpdateFailure.payloadMismatch }
                let digest = try Disk.fileDigest(url)
                actualFiles[relative] = digest
                tree.append("\(relative)\t\(String(info.st_mode & 0o7777, radix: 8))\t\(info.st_size)\t\(digest)\n")
            }
        }
        for name in ["bin", "package.json", "src"] { try inventory(name) }
        guard actualFiles == manifest.proxyFiles,
              Disk.digest(Data(tree.sorted().joined().utf8)) == manifest.proxyTreeSHA256 else { throw UpdateFailure.payloadMismatch }
        for (relative, digest) in manifest.proxyFiles {
            guard !relative.hasPrefix("/"), !relative.split(separator: "/").contains(".."), Disk.isDigest(digest),
                  relative == "package.json" || relative.hasPrefix("bin/") || relative.hasPrefix("src/") else {
                throw UpdateFailure.invalidManifest
            }
            let file = proxy.appendingPathComponent(relative)
            guard file.resolvingSymlinksInPath().path == file.standardizedFileURL.path,
                  try Disk.fileDigest(file) == digest else { throw UpdateFailure.payloadMismatch }
        }
        guard try Disk.fileDigest(app.appendingPathComponent("Contents/Helpers/node")) == manifest.nodeSignedSHA256,
              try Disk.fileDigest(app.appendingPathComponent("Contents/Helpers/codexmulti-runtime-launcher")) == manifest.launcherSignedSHA256,
              try Disk.fileDigest(app.appendingPathComponent("Contents/Helpers/codexmulti-update-agent")) == manifest.agentSignedSHA256 else {
            throw UpdateFailure.payloadMismatch
        }
        return manifest
    }

    public func stage(app: URL) throws -> RuntimeManifest {
        let manifest = try verifyPayload(in: app)
        let destination = try bundle(manifest.runtimeID)
        if Disk.exists(destination) {
            let installed = try verifyPayload(in: destination)
            guard installed.runtimeID == manifest.runtimeID else { throw UpdateFailure.payloadMismatch }
            return installed
        }
        let temporary = runtimes.appendingPathComponent(".stage-\(UUID().uuidString)", isDirectory: true)
        try Disk.privateDirectory(temporary)
        defer { if Disk.exists(temporary) { try? FileManager.default.removeItem(at: temporary) } }
        let copied = temporary.appendingPathComponent("CodexMulti.app", isDirectory: true)
        try FileManager.default.copyItem(at: app, to: copied)
        let copiedManifest = try verifyPayload(in: copied)
        guard copiedManifest == manifest else { throw UpdateFailure.payloadMismatch }
        try FileManager.default.moveItem(at: temporary, to: destination.deletingLastPathComponent())
        return manifest
    }
}
