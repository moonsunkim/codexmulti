import Dispatch
import Foundation
import UpdaterKit
import os

enum CoreBridgeError: Error, Equatable {

    case versionMismatch(found: UInt32, expected: UInt32)

    case createFailed
    case alreadyStarted
    case invalidInitialProjection
    case runtimeUnavailable(RuntimeStartError?)
}





actor CoreBridge: CoreProtocol {
    static let contractVersion: UInt32 = 1

    private let queue: DispatchSerialQueue
    nonisolated var unownedExecutor: UnownedSerialExecutor { queue.asUnownedSerialExecutor() }

    private let abi: CoreABI
    private let store: CoreStore
    private let effects: EffectRunner
    private let pumpInterval: DispatchTimeInterval
    private let log = Logger(subsystem: "dev.codexmulti.app", category: "core")

    private var handle: CoreHandle?
    private var pump: DispatchSourceTimer?
    private var pipeline = ProjectionPipeline()
    private(set) var pumpCount = 0

    init(store: CoreStore,
         effects: EffectRunner,
         abi: CoreABI = .live,
         pumpInterval: DispatchTimeInterval = .seconds(1)) {
        self.queue = DispatchSerialQueue(label: "dev.codexmulti.app.core", qos: .userInitiated)
        self.store = store
        self.effects = effects
        self.abi = abi
        self.pumpInterval = pumpInterval
    }

    var isRunning: Bool { handle != nil }
    var lastGeneration: UInt64? { pipeline.lastGeneration }



    func start() throws {
        guard handle == nil else { throw CoreBridgeError.alreadyStarted }
        let found = abi.version()
        guard found == Self.contractVersion else {
            log.error("core bridge version mismatch found=\(found, privacy: .public) expected=\(Self.contractVersion, privacy: .public)")
            throw CoreBridgeError.versionMismatch(found: found, expected: Self.contractVersion)
        }


        log.notice("core provenance \(self.abi.provenance(), privacy: .public) \(BridgeProvenance.bridgeSchemaMarker.description, privacy: .public)")
        guard let created = abi.create() else { throw CoreBridgeError.createFailed }
        do {
            guard let bytes = abi.project(created),
                  let initial = try? JSONDecoder().decode(Projection.self, from: bytes) else {
                throw CoreBridgeError.invalidInitialProjection
            }
            guard initial.runtime.started else {
                throw CoreBridgeError.runtimeUnavailable(initial.runtime.error)
            }
            handle = created
            projectAndPublish(bytes)
        } catch {
            abi.destroy(created)
            throw error
        }
        startPump()
    }

    func submit(_ intent: Intent) {
        if let runtime = try? RuntimeStore(root: RuntimeStore.defaultRoot),
           let journal = try? runtime.current(), ![.complete, .cancelled, .rolledBack].contains(journal.phase) {
            if intent == .quit_app {
                Task { @MainActor in QuitRequest.post() }
            } else if intent == .open_details {
                Task { @MainActor in WindowPresenter.shared.showSettings(activation: .userInitiated) }
            } else if case .set_proxy_enabled(on: false) = intent {
                _ = try? AgentConnection.send(AgentRequest("off", transactionID: journal.transactionID), store: runtime)
            }
            return
        }
        guard let handle else {
            log.error("intent dropped before start: \(intent.name, privacy: .public)")
            return
        }
        send(intent, to: handle)
        projectAndPublish()
    }

    func pumpNow() {
        tick()
    }

    func shutdown() {
        pump?.cancel()
        pump = nil
        if let handle {
            abi.destroy(handle)
        }
        handle = nil
        pipeline = ProjectionPipeline()
    }



    private func send(_ intent: Intent, to handle: CoreHandle) {
        let json: Data
        do {
            json = try IntentEncoder.encode(intent)
        } catch {
            assertionFailure("intent encoding failed: \(intent.name)")
            return
        }
        let code = abi.submit(handle, json)
        if code != 0 {

            log.error("cm_service_submit rejected \(intent.name, privacy: .public) code=\(code, privacy: .public)")
            assertionFailure("cm_service_submit(\(intent.name)) returned \(code)")
        }
    }

    private func tick() {
        guard let handle else { return }
        pumpCount += 1
        abi.pump(handle, Int64(Date().timeIntervalSince1970.rounded(.down)))
        projectAndPublish()
    }

    private func startPump() {
        let timer = DispatchSource.makeTimerSource(queue: queue)
        timer.schedule(deadline: .now() + pumpInterval, repeating: pumpInterval, leeway: .milliseconds(100))
        timer.setEventHandler { [weak self] in
            guard let self else { return }

            self.assumeIsolated { $0.tick() }
        }
        timer.resume()
        pump = timer
    }



    private func projectAndPublish(_ initialBytes: Data? = nil) {
        guard let handle, let bytes = initialBytes ?? abi.project(handle) else { return }
        switch pipeline.ingest(bytes) {
        case .unchanged:
            return
        case .published(let projection):
            let store = store
            let effects = effects
            Task { @MainActor in
                effects.runPresentationEffects(projection.effects)
                store.publish(projection)
                effects.runRemainingEffects(projection.effects)
            }
        case .rejected(let generation, let reason):
            let label = generation.map(String.init) ?? "unknown"
            log.error("projection rejected generation=\(label, privacy: .public): \(reason, privacy: .public)")
        }
    }
}
