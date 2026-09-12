import Darwin
import Foundation
import XCTest
@testable import UpdaterKit

final class NativeLifecycleTests: XCTestCase, @unchecked Sendable {
    private func freePort() throws -> Int {
        let descriptor = socket(AF_INET, SOCK_STREAM, 0)
        guard descriptor >= 0 else { throw UpdateFailure.candidateFailed }
        defer { close(descriptor) }
        var address = sockaddr_in()
        address.sin_len = UInt8(MemoryLayout<sockaddr_in>.size)
        address.sin_family = sa_family_t(AF_INET)
        address.sin_addr.s_addr = inet_addr("127.0.0.1")
        let bound = withUnsafePointer(to: &address) {
            $0.withMemoryRebound(to: sockaddr.self, capacity: 1) { Darwin.bind(descriptor, $0, socklen_t(MemoryLayout<sockaddr_in>.size)) }
        }
        guard bound == 0 else { throw UpdateFailure.candidateFailed }
        var size = socklen_t(MemoryLayout<sockaddr_in>.size)
        let result = withUnsafeMutablePointer(to: &address) {
            $0.withMemoryRebound(to: sockaddr.self, capacity: 1) { getsockname(descriptor, $0, &size) }
        }
        guard result == 0 else { throw UpdateFailure.candidateFailed }
        return Int(UInt16(bigEndian: address.sin_port))
    }

    private func partialRequest(port: Int) throws -> Int32 {
        let descriptor = socket(AF_INET, SOCK_STREAM, 0)
        guard descriptor >= 0 else { throw UpdateFailure.candidateFailed }
        var address = sockaddr_in()
        address.sin_len = UInt8(MemoryLayout<sockaddr_in>.size)
        address.sin_family = sa_family_t(AF_INET)
        address.sin_addr.s_addr = inet_addr("127.0.0.1")
        address.sin_port = UInt16(port).bigEndian
        let connected = withUnsafePointer(to: &address) {
            $0.withMemoryRebound(to: sockaddr.self, capacity: 1) { connect(descriptor, $0, socklen_t(MemoryLayout<sockaddr_in>.size)) }
        }
        guard connected == 0 else { close(descriptor); throw UpdateFailure.candidateFailed }
        let bytes = Data("POST /backend-api/codex/responses HTTP/1.1\r\nHost: 127.0.0.1:\(port)\r\nContent-Type: application/json\r\nContent-Length: 100\r\n\r\n{".utf8)
        let count = bytes.withUnsafeBytes { Darwin.write(descriptor, $0.baseAddress, $0.count) }
        guard count == bytes.count else { close(descriptor); throw UpdateFailure.candidateFailed }
        return descriptor
    }

    private func health(_ client: ProxyClient, matching: @escaping @Sendable (ProxyHealth) -> Bool) async throws -> ProxyHealth {
        for _ in 0..<100 {
            if let health = try? await client.health(), matching(health) { return health }
            try await Task.sleep(for: .milliseconds(100))
        }
        if let reply = try? await client.exchange("health", nil) {
            print("Native health timeout:", reply.status, String(describing: reply.health), reply.error ?? "")
        }
        throw UpdateFailure.proxyUnreachable
    }

    func testSignedNativeLaunchAgentWaitsForPartialBodyAndSwitchesImmutableRuntime() async throws {
        guard let oldPath = ProcessInfo.processInfo.environment["CODEXMULTI_UPDATER_TEST_OLD_APP"],
              let newPath = ProcessInfo.processInfo.environment["CODEXMULTI_UPDATER_TEST_NEW_APP"] else {
            throw XCTSkip("Signed application fixtures are required for the native lifecycle check")
        }
        let home = FileManager.default.temporaryDirectory.resolvingSymlinksInPath()
            .appendingPathComponent("codexmulti-native-lifecycle-\(UUID().uuidString)")
        try Disk.privateDirectory(home)
        let store = try RuntimeStore(root: home.appendingPathComponent("Library/Application Support/CodexMulti"))
        let root = store.root
        let old = try store.stage(app: URL(fileURLWithPath: oldPath))
        let new = try store.stage(app: URL(fileURLWithPath: newPath))
        XCTAssertNotEqual(old.runtimeID, new.runtimeID)
        let label = "dev.codexmulti.tests." + UUID().uuidString.lowercased()
        let launch = LaunchService(home: home)
        addTeardownBlock {
            let logs = root.appendingPathComponent("logs")
            for file in (try? FileManager.default.contentsOfDirectory(at: logs, includingPropertiesForKeys: nil)) ?? [] {
                if let text = try? String(contentsOf: file, encoding: .utf8), !text.isEmpty { print("Native test log", file.lastPathComponent, String(text.suffix(2000))) }
            }
            if let snapshot = try launch.snapshot(label) {
                let expected = [old.runtimeID, new.runtimeID].contains { runtimeID in
                    (try? RuntimeOperations.arguments(app: store.bundle(runtimeID), configPath: root.appendingPathComponent("proxy.json").path)) == snapshot.arguments
                }
                guard expected else { throw UpdateFailure.serviceOwnershipUnknown }
                try launch.bootout(snapshot)
                for _ in 0..<50 {
                    if try launch.removed(snapshot) { break }
                    usleep(100_000)
                }
                guard try launch.removed(snapshot) else { throw UpdateFailure.processStillRunning }
            }
            try FileManager.default.removeItem(at: home)
        }
        try store.select(ActiveRuntime(runtimeID: old.runtimeID, generation: 1))
        let port = try freePort()
        XCTAssertNotEqual(port, 8787)
        let claims = Data("{\"exp\":4102444800,\"https://api.openai.com/auth\":{\"chatgpt_account_id\":\"synthetic-native\",\"chatgpt_plan_type\":\"pro\"}}".utf8)
            .base64EncodedString().replacingOccurrences(of: "+", with: "-").replacingOccurrences(of: "/", with: "_").replacingOccurrences(of: "=", with: "")
        let auth = root.appendingPathComponent("auth.json")
        let authObject: [String: Any] = ["auth_mode": "chatgpt", "tokens": [
            "access_token": "eyJhbGciOiJub25lIn0.\(claims).synthetic", "refresh_token": "synthetic-native", "account_id": "synthetic-native",
        ]]
        try Disk.atomicWrite(try JSONSerialization.data(withJSONObject: authObject), at: auth)
        let config = root.appendingPathComponent("proxy.json")
        let configObject: [String: Any] = ["listen_host": "127.0.0.1", "port": port, "mode": "failover",
            "accounts": [["name": "native-test", "label": "native test", "auth_file": auth.path]],
            "state_file": root.appendingPathComponent("state.json").path, "log_file": root.appendingPathComponent("logs/proxy.jsonl").path]
        try Disk.atomicWrite(try JSONSerialization.data(withJSONObject: configObject), at: config)
        let oldApp = try store.bundle(old.runtimeID)
        _ = try launch.bootstrap(label: label, arguments: RuntimeOperations.arguments(app: oldApp, configPath: config.path),
            workingDirectory: oldApp.appendingPathComponent("Contents/Resources/proxy"), logRoot: root.appendingPathComponent("logs"))
        for _ in 0..<100 {
            if Disk.exists(URL(fileURLWithPath: config.path + ".control-token")) { break }
            try await Task.sleep(for: .milliseconds(100))
        }
        let client = try ProxyClient(configPath: config)
        let serving = try await health(client) { $0.gate == "serving" }
        XCTAssertEqual(serving.runtimeID, old.runtimeID)
        let original = try XCTUnwrap(launch.snapshot(label))
        let descriptor = try partialRequest(port: port)
        var connectionOpen = true
        defer { if connectionOpen { close(descriptor) } }
        let busy = try await health(client) { $0.workTotal == 1 }
        XCTAssertEqual(busy.work["http"], 1)
        var journal = UpdateJournal(phase: .waitingIdle, appPath: newPath, previousAppBuild: old.appBuild,
            targetAppBuild: new.appBuild, oldRuntimeID: old.runtimeID, targetRuntimeID: new.runtimeID,
            configPath: config.path, configRevision: busy.configRevision!, desiredEnabled: true,
            previousGeneration: 1, serviceLabel: label, kind: "runtime")
        journal.guiReady = true
        try store.save(journal)
        let operations = RuntimeOperations(snapshot: launch.snapshot, bootout: launch.bootout,
            removed: launch.removed, process: launch.inspectProcess, writerAvailable: {
                do { let lock = try FileLock(store.writerLockURL); return withExtendedLifetime(lock) { true } }
                catch UpdateFailure.updateBusy { return false }
            }, bootstrap: { runtimeID, journal in
                let app = try store.bundle(runtimeID)
                let plist = try launch.plistURL(label)
                return try launch.bootstrap(label: label, arguments: RuntimeOperations.arguments(app: app, configPath: config.path),
                    workingDirectory: app.appendingPathComponent("Contents/Resources/proxy"),
                    expectedPlistDigest: Disk.exists(plist) ? try Disk.fileDigest(plist) : nil,
                    logRoot: root.appendingPathComponent("logs"))
            }, plistDigest: { _ in try Disk.fileDigest(launch.plistURL(label)) }, client: { _ in client })
        let engine = UpdateEngine(store: store, transactionID: journal.transactionID, operations: operations)
        for _ in 0..<4 {
            let pending = try await engine.advance()
            XCTAssertEqual(pending.phase, .waitingIdle)
            XCTAssertEqual(try launch.snapshot(label), original)
        }
        close(descriptor); connectionOpen = false
        _ = try await health(client) { $0.workTotal == 0 }
        var result = journal
        for _ in 0..<60 {
            let resumed = UpdateEngine(store: store, transactionID: journal.transactionID, operations: operations)
            result = try await resumed.advance()
            print("Native transition", result.phase.rawValue, result.failure?.rawValue ?? "")
            if result.phase.terminal { break }
            try await Task.sleep(for: .milliseconds(200))
        }
        XCTAssertEqual(result.phase, .complete, "\(result.failure?.rawValue ?? "pending")")
        let current = try await client.health()
        XCTAssertEqual(current.runtimeID, new.runtimeID)
        XCTAssertEqual(current.gate, "serving")
        XCTAssertEqual(current.generation, 2)
        XCTAssertNotEqual(current.bootID, serving.bootID)
        XCTAssertNotEqual(try launch.snapshot(label)?.process, original.process)
        let priorData = try Disk.read(auth)
        XCTAssertEqual(try JSONSerialization.jsonObject(with: priorData) as? NSDictionary, authObject as NSDictionary)
        let offConnection = try partialRequest(port: port)
        defer { close(offConnection) }
        _ = try await health(client) { $0.workTotal == 1 }
        let beforeOff = try XCTUnwrap(launch.snapshot(label))
        var offJournal = UpdateJournal(phase: .waitingIdle, appPath: newPath, previousAppBuild: new.appBuild,
            targetAppBuild: new.appBuild, oldRuntimeID: new.runtimeID, targetRuntimeID: new.runtimeID,
            configPath: config.path, configRevision: current.configRevision!, desiredEnabled: false,
            previousGeneration: 2, serviceLabel: label, kind: "service")
        offJournal.guiReady = true
        try store.save(offJournal)
        var offOperations = operations
        offOperations.removeServiceArtifacts = RuntimeOperations(store: store, launch: launch).removeServiceArtifacts
        let offEngine = UpdateEngine(store: store, transactionID: offJournal.transactionID, operations: offOperations)
        let pendingOff = try await offEngine.advance()
        XCTAssertEqual(pendingOff.phase, .waitingIdle)
        XCTAssertEqual(try launch.snapshot(label), beforeOff)
        XCTAssertEqual(shutdown(offConnection, SHUT_RDWR), 0)
        _ = try await health(client) { $0.workTotal == 0 }
        var offResult = pendingOff
        for _ in 0..<60 {
            offResult = try await offEngine.advance()
            if offResult.phase.terminal { break }
            try await Task.sleep(for: .milliseconds(100))
        }
        XCTAssertEqual(offResult.phase, .complete)
        XCTAssertNil(try launch.snapshot(label))
        XCTAssertFalse(Disk.exists(try launch.plistURL(label)))
        XCTAssertEqual(try store.active()?.generation, 3)
    }
}
