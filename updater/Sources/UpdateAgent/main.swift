import AppKit
import Darwin
import Foundation
import UpdaterKit

@main
enum UpdateAgent {
    static func main() async {
        do {
            let arguments = Array(CommandLine.arguments.dropFirst())
            if arguments.first == "prepare-removal" || arguments.first == "homebrew-uninstall" {
                let prepare = arguments.first == "prepare-removal"
                guard arguments.count == (prepare ? 5 : 3), arguments[1] == "--app",
                      !prepare || arguments[3] == "--config" else { throw UpdateFailure.invalidCommand }
                let app = URL(fileURLWithPath: arguments[2])
                guard NSRunningApplication.runningApplications(withBundleIdentifier: Signatures.bundleIdentifier).isEmpty else {
                    throw UpdateFailure.updateBusy
                }
                let store = try RuntimeStore(root: RuntimeStore.defaultRoot)
                _ = try store.verifyPayload(in: app)
                if prepare {
                    let journal = try RemovalPreparation.begin(store: store, app: app, configPath: arguments[4])
                    try UpdatePreparation.startAgent(store: store, journal: journal)
                    for _ in 0..<30 {
                        let current = try store.journal(journal.transactionID)
                        if current.phase == .complete {
                            do { try RemovalPreparation.recordReady(store: store, transactionID: journal.transactionID); return }
                            catch UpdateFailure.updateBusy {}
                        } else if current.phase.terminal { throw current.failure ?? UpdateFailure.removalNotPrepared }
                        try await Task.sleep(for: .seconds(1))
                    }
                    throw UpdateFailure.proxyBusy
                }
                try RemovalPreparation.checkReady(store: store, app: app)
                return
            }
            if arguments.first == "service" || arguments.first == "migrate" {
                let migration = arguments.first == "migrate"
                let offset = migration ? 1 : 0
                guard arguments.count == 7 + offset, !migration || arguments[1] == "--clients-closed",
                      arguments[1 + offset] == "--app", arguments[3 + offset] == "--config",
                      arguments[5 + offset] == "--enabled", ["true", "false"].contains(arguments[6 + offset]) else {
                    throw UpdateFailure.invalidCommand
                }
                let store = try RuntimeStore(root: RuntimeStore.defaultRoot)
                let journal = try ServicePreparation.begin(store: store,
                    app: URL(fileURLWithPath: arguments[2 + offset]), configPath: arguments[4 + offset],
                    enabled: arguments[6 + offset] == "true", clientsClosed: migration)
                try UpdatePreparation.startAgent(store: store, journal: journal)
                return
            }
            guard arguments.count == 5, arguments[0] == "serve", arguments[1] == "--root",
                  arguments[3] == "--transaction" else { throw UpdateFailure.invalidCommand }
            let store = try RuntimeStore(root: URL(fileURLWithPath: arguments[2]))
            let lock = try FileLock(store.lockURL)
            let journal = try store.journal(arguments[4])
            let expected = try UpdatePreparation.helperURL(store: store, journal: journal)
            guard let process = try ProcessIdentity.inspect(getpid()), process.executable == expected.path,
                  try journal.helperSHA256 == nil || Disk.fileDigest(expected) == journal.helperSHA256 else {
                throw UpdateFailure.invalidSignature
            }
            guard let homePath = ProcessInfo.processInfo.environment["HOME"], homePath.hasPrefix("/") else {
                throw UpdateFailure.invalidPath
            }
            let home = try Disk.canonicalURL(URL(fileURLWithPath: homePath))
            _ = try Disk.checked(home, directory: true)
            let launch = LaunchService(home: home)
            let listener = try AgentListener(store: store)
            let engine = UpdateEngine(store: store, transactionID: journal.transactionID,
                                      operations: RuntimeOperations(store: store, launch: launch))
            let server = Task.detached { await listener.serve(engine: engine) }
            while true {
                let state = try await engine.advance()
                if state.phase.terminal {
                    server.cancel()
                    await server.value
                    try? UpdatePreparation.removeAgentPlist(store: store, journal: state, launch: launch)
                    withExtendedLifetime(lock) {}
                    exit(0)
                }
                try await Task.sleep(for: .seconds(1))
            }
        } catch {
            let failure = error as? UpdateFailure ?? .recoveryRequired
            FileHandle.standardError.write(Data((failure.rawValue + "\n").utf8))
            exit(2)
        }
    }
}
