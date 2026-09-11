import Foundation

enum FixtureCoreError: Error, Equatable {
    case undecodable(reason: String)
}






actor FixtureCore: CoreProtocol {
    let bytes: Data
    private let store: CoreStore
    private let effects: EffectRunner
    private var pipeline = ProjectionPipeline()
    private(set) var submitted: [Intent] = []
    private(set) var isRunning = false

    init(data: Data, store: CoreStore, effects: EffectRunner) {
        self.bytes = data
        self.store = store
        self.effects = effects
    }

    init(contentsOf url: URL, store: CoreStore, effects: EffectRunner) throws {
        self.init(data: try Data(contentsOf: url), store: store, effects: effects)
    }

    func start() async throws {
        isRunning = true
        try await publishIfChanged()
    }


    func submit(_ intent: Intent) {
        submitted.append(intent)
    }

    func pumpNow() async {
        try? await publishIfChanged()
    }

    func shutdown() {
        isRunning = false
    }

    private func publishIfChanged() async throws {
        switch pipeline.ingest(bytes) {
        case .unchanged:
            return
        case .published(let projection):
            let store = store
            let effects = effects
            await MainActor.run {
                effects.runPresentationEffects(projection.effects)
                store.publish(projection)
                effects.runRemainingEffects(projection.effects)
            }
        case .rejected(_, let reason):
            throw FixtureCoreError.undecodable(reason: reason)
        }
    }
}
