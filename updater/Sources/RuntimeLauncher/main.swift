import Darwin
import Foundation
import UpdaterKit

@main
enum RuntimeLauncher {
    static func main() {
        do {
            let arguments = CommandLine.arguments
            guard arguments.count == 4, arguments[1] == "--config", arguments[2].hasPrefix("/"), arguments[3] == "--managed" else {
                throw UpdateFailure.invalidCommand
            }
            let executable = try Disk.canonicalURL(URL(fileURLWithPath: arguments[0]))
            let app = executable.deletingLastPathComponent().deletingLastPathComponent().deletingLastPathComponent()
            let runtimeDirectory = app.deletingLastPathComponent()
            let root = runtimeDirectory.deletingLastPathComponent().deletingLastPathComponent()
            guard app.lastPathComponent == "CodexMulti.app", runtimeDirectory.deletingLastPathComponent().lastPathComponent == "runtimes",
                  Disk.isDigest(runtimeDirectory.lastPathComponent) else { throw UpdateFailure.invalidPath }
            let store = try RuntimeStore(root: root)
            let manifest = try store.verifyPayload(in: app)
            guard manifest.runtimeID == runtimeDirectory.lastPathComponent else { throw UpdateFailure.identityMismatch }
            guard let active = try store.active() else { throw UpdateFailure.invalidManifest }
            let journal = try store.current()
            let permitted = active.runtimeID == manifest.runtimeID && (journal?.phase.permitsOldRuntime ?? true)
            if let journal, !journal.phase.terminal {
                guard journal.oldRuntimeID == manifest.runtimeID || journal.targetRuntimeID == manifest.runtimeID else {
                    throw UpdateFailure.identityMismatch
                }
            } else if active.runtimeID != manifest.runtimeID {
                throw UpdateFailure.identityMismatch
            }
            let writer = try FileLock(store.writerLockURL)
            let inheritedDescriptor: Int32 = 198
            guard dup2(writer.descriptor, inheritedDescriptor) == inheritedDescriptor,
                  fcntl(inheritedDescriptor, F_SETFD, 0) == 0 else { throw UpdateFailure.unsafePermissions }
            setenv("CODEXMULTI_RUNTIME_ROOT", root.path, 1)
            setenv("CODEXMULTI_RUNTIME_APP", app.path, 1)
            setenv("CODEXMULTI_RUNTIME_LOCK_FD", String(inheritedDescriptor), 1)
            setenv("CODEXMULTI_RUNTIME_GATE", permitted ? "serving" : "gated", 1)
            let node = app.appendingPathComponent("Contents/Helpers/node").path
            let server = app.appendingPathComponent("Contents/Resources/proxy/src/server.mjs").path
            let strings = [node, server, "--config", arguments[2]]
            let pointers = strings.map { strdup($0) } + [nil]
            defer { for pointer in pointers { free(pointer) } }
            pointers.withUnsafeBufferPointer { buffer in _ = execv(node, buffer.baseAddress!) }
            throw UpdateFailure.candidateFailed
        } catch {
            let code = (error as? UpdateFailure)?.rawValue ?? "runtime_start_failed"
            FileHandle.standardError.write(Data((code + "\n").utf8))
            exit(1)
        }
    }
}
