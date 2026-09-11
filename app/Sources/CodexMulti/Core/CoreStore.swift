import Foundation
import Observation








@MainActor @Observable
final class CoreStore {
    private(set) var projection: Projection?

    private(set) var publishCount = 0

    @ObservationIgnored private(set) var receivedCount = 0

    let tray = TrayGate()

    var startupFailure: CoreBridgeError?


    @ObservationIgnored var onFirstPublish: (@MainActor () -> Void)?

    init() {}

    var isStarted: Bool { projection != nil }

    func publish(_ next: Projection) {
        receivedCount += 1
        let previous = projection
        if let previous, previous.rendersSame(as: next) { return }
        projection = next
        publishCount += 1
        tray.receive(next)
        if previous == nil, let onFirstPublish {
            self.onFirstPublish = nil
            onFirstPublish()
        }
    }
}
