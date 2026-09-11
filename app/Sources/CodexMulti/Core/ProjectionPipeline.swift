import Foundation




struct ProjectionPipeline {
    enum Ingest: Equatable {

        case unchanged
        case published(Projection)

        case rejected(generation: UInt64?, reason: String)
    }


    private struct Envelope: Decodable {
        let generation: UInt64?
        let serialize_error: String?
    }

    private(set) var lastBytes = Data()
    private(set) var lastGeneration: UInt64?

    mutating func ingest(_ bytes: Data) -> Ingest {
        if bytes == lastBytes { return .unchanged }
        lastBytes = bytes
        let decoder = JSONDecoder()
        do {
            let projection = try decoder.decode(Projection.self, from: bytes)
            lastGeneration = projection.generation
            return .published(projection)
        } catch {
            let envelope = try? decoder.decode(Envelope.self, from: bytes)
            var reason = String(describing: error)
            if let serializeError = envelope?.serialize_error { reason = "serialize_error=\(serializeError); \(reason)" }
            return .rejected(generation: envelope?.generation, reason: reason)
        }
    }
}
