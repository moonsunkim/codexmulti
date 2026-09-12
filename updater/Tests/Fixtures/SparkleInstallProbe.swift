import AppKit
import Darwin
import Foundation
import ObjectiveC
import UpdaterKit

protocol CoreProtocol: Sendable {
    func start() async throws
    func shutdown() async
}

@MainActor final class CoreStore {
    struct Settings { let proxy_config_path: String; let proxy_enabled: Bool }
    struct View { let settings: Settings }
    struct Projection { let view: View }
    let projection: Projection?
    init(config: String) { projection = Projection(view: View(settings: Settings(proxy_config_path: config, proxy_enabled: true))) }
}

enum Copy { static func text(_ key: String, fallback: String) -> String { key } }

struct ProbePlan: Codable {
    let label: String
    let port: Int
    let oldBuild: String
    let newBuild: String
    let changedRuntime: Bool
    let transport: String?
}

enum Probe {
    static let root = Bundle.main.bundleURL.deletingLastPathComponent().deletingLastPathComponent()
    static let home = root.appendingPathComponent("Home")
    static let runtime = home.appendingPathComponent("Library/Application Support/CodexMulti")
    static let config = runtime.appendingPathComponent("proxy.json")
    static var build: String { Bundle.main.object(forInfoDictionaryKey: "CFBundleVersion") as! String }
    static func event(_ name: String, _ details: [String: Any] = [:]) {
        var object = details
        object["event"] = name; object["pid"] = getpid(); object["build"] = build
        object["time"] = Date().timeIntervalSince1970
        guard let data = try? JSONSerialization.data(withJSONObject: object, options: [.sortedKeys]) else { return }
        let descriptor = Darwin.open(root.appendingPathComponent("events.jsonl").path, O_CREAT | O_WRONLY | O_APPEND, 0o600)
        guard descriptor >= 0 else { return }
        defer { close(descriptor) }
        let line = data + Data([10])
        _ = line.withUnsafeBytes { Darwin.write(descriptor, $0.baseAddress, $0.count) }
        fsync(descriptor)
    }
}

actor ProbeCore: CoreProtocol {
    func start() async throws { Probe.event("core-start") }
    func shutdown() async { Probe.event("core-shutdown-joined") }
}

final class FixtureTransport: URLProtocol, @unchecked Sendable {
    override class func canInit(with request: URLRequest) -> Bool { request.url?.host == "sparkle.codexmulti.test" }
    override class func canonicalRequest(for request: URLRequest) -> URLRequest { request }
    override func startLoading() {
        do {
            guard let url = request.url, ["/appcast.xml", "/CodexMulti.zip"].contains(url.path) else { throw URLError(.fileDoesNotExist) }
            let data = try Data(contentsOf: Probe.root.appendingPathComponent("Feed").appendingPathComponent(url.lastPathComponent))
            Probe.event("transport", ["path": url.path, "bytes": data.count])
            let response = HTTPURLResponse(url: url, statusCode: 200, httpVersion: "HTTP/1.1", headerFields: [
                "Content-Length": String(data.count), "Content-Type": url.path.hasSuffix("xml") ? "application/xml" : "application/octet-stream",
            ])!
            client?.urlProtocol(self, didReceive: response, cacheStoragePolicy: .notAllowed)
            for offset in stride(from: 0, to: data.count, by: 262_144) {
                client?.urlProtocol(self, didLoad: data.subdata(in: offset..<min(offset + 262_144, data.count)))
            }
            client?.urlProtocolDidFinishLoading(self)
        } catch { client?.urlProtocol(self, didFailWithError: error) }
    }
    override func stopLoading() {}
}

extension URLSessionConfiguration {
    @objc class func fixtureConfiguration() -> URLSessionConfiguration {
        let configuration = fixtureConfiguration()
        configuration.protocolClasses = [FixtureTransport.self] + (configuration.protocolClasses ?? [])
        return configuration
    }
}

@MainActor final class ProbeDelegate: NSObject, NSApplicationDelegate {
    let plan: ProbePlan
    let core = ProbeCore()
    let coreStore = CoreStore(config: Probe.config.path)
    init(plan: ProbePlan) { self.plan = plan }
    func applicationDidFinishLaunching(_ notification: Notification) {
        Task {
            do {
                Probe.event("gui-start")
                try await core.start()
                let controller = UpdateController.shared
                await controller.start(core: core, store: coreStore, environment: UpdateEnvironment(root: Probe.runtime,
                    launch: LaunchService(home: Probe.home), serviceLabel: plan.label))
                let runtime = try RuntimeStore(root: Probe.runtime)
                var checked = false
                var installed = false
                var last = ""
                let deadline = ProcessInfo.processInfo.systemUptime + 180
                while ProcessInfo.processInfo.systemUptime < deadline {
                    let journal = try runtime.current()
                    let state = controller.status + ":" + (journal?.phase.rawValue ?? "none")
                    if state != last {
                        Probe.event("state", ["status": controller.status, "phase": journal?.phase.rawValue ?? "none",
                                              "failure": journal?.failure?.rawValue ?? "", "armed": journal?.installArmed ?? false,
                                              "error": controller.lastError?.description ?? ""])
                        last = state
                    }
                    if Probe.build == plan.oldBuild, !checked, controller.canCheck {
                        checked = true; Probe.event("check"); controller.check()
                    }
                    if Probe.build == plan.oldBuild, !installed, controller.canInstall {
                        installed = true; Probe.event("install"); controller.install()
                    }
                    if Probe.build == plan.newBuild, journal?.phase == .complete {
                        let active = try runtime.active()!
                        let result: [String: Any] = ["build": Probe.build, "pid": getpid(), "runtime_id": active.runtimeID,
                            "generation": active.generation, "transaction_id": journal!.transactionID, "phase": journal!.phase.rawValue]
                        try Disk.atomicWrite(try JSONSerialization.data(withJSONObject: result, options: [.sortedKeys]),
                                             at: Probe.root.appendingPathComponent("success.json"))
                        Probe.event("success", result)
                        NSApp.terminate(nil)
                        return
                    }
                    if ["failed", "check_failed", "no_compatible", "current"].contains(controller.status), journal?.phase != .complete {
                        throw UpdateFailure.recoveryRequired
                    }
                    try await Task.sleep(for: .milliseconds(100))
                }
                throw UpdateFailure.proxyUnreachable
            } catch {
                Probe.event("failed", ["error": String(describing: error)])
                NSApp.terminate(nil)
            }
        }
    }
}

@main struct SparkleInstallProbe {
    @MainActor static func main() throws {
        setenv("HOME", Probe.home.path, 1)
        setenv("CFFIXED_USER_HOME", Probe.home.path, 1)
        let plan = try JSONDecoder().decode(ProbePlan.self, from: Data(contentsOf: Probe.root.appendingPathComponent("plan.json")))
        if CommandLine.arguments.contains("--prepare") {
            try Disk.privateDirectory(Probe.home)
            let store = try RuntimeStore(root: Probe.runtime)
            let manifest = try store.stage(app: Bundle.main.bundleURL)
            try store.select(ActiveRuntime(runtimeID: manifest.runtimeID, generation: 1))
            let claims = Data("{\"exp\":4102444800,\"https://api.openai.com/auth\":{\"chatgpt_account_id\":\"synthetic-sparkle\",\"chatgpt_plan_type\":\"pro\"}}".utf8)
                .base64EncodedString().replacingOccurrences(of: "+", with: "-").replacingOccurrences(of: "/", with: "_").replacingOccurrences(of: "=", with: "")
            let auth = store.root.appendingPathComponent("auth.json")
            let authObject: [String: Any] = ["auth_mode": "chatgpt", "tokens": ["access_token": "eyJhbGciOiJub25lIn0.\(claims).synthetic",
                "refresh_token": "synthetic-sparkle", "account_id": "synthetic-sparkle"]]
            try Disk.atomicWrite(try JSONSerialization.data(withJSONObject: authObject), at: auth)
            let config: [String: Any] = ["listen_host": "127.0.0.1", "port": plan.port, "mode": "failover",
                "accounts": [["name": "sparkle-test", "label": "sparkle test", "auth_file": auth.path]],
                "state_file": store.root.appendingPathComponent("state.json").path,
                "log_file": store.root.appendingPathComponent("logs/proxy.jsonl").path]
            try Disk.atomicWrite(try JSONSerialization.data(withJSONObject: config), at: Probe.config)
            let launch = LaunchService(home: Probe.home)
            let data = try ManagedArtifacts.plist(store: store, runtimeID: manifest.runtimeID, configPath: Probe.config.path, serviceLabel: plan.label)
            _ = try launch.bootstrap(label: plan.label, data: data, expectedPlistDigest: nil)
            Probe.event("prepared", ["runtime_id": manifest.runtimeID])
            return
        }
        if plan.transport != "https" {
            URLProtocol.registerClass(FixtureTransport.self)
            let original = class_getClassMethod(URLSessionConfiguration.self, #selector(getter: URLSessionConfiguration.default))!
            let fixture = class_getClassMethod(URLSessionConfiguration.self, #selector(URLSessionConfiguration.fixtureConfiguration))!
            method_exchangeImplementations(original, fixture)
        }
        let application = NSApplication.shared
        application.setActivationPolicy(.accessory)
        let delegate = ProbeDelegate(plan: plan)
        application.delegate = delegate
        withExtendedLifetime(delegate) { application.run() }
    }
}
