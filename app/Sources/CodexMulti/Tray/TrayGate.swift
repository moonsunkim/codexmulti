import AppKit
import Observation











@MainActor @Observable
final class TrayGate {

    private(set) var projection: Projection?
    @ObservationIgnored private(set) var isOpen = false
    @ObservationIgnored private var pending: Projection?

    @ObservationIgnored private var trackedMenu: ObjectIdentifier?
    @ObservationIgnored private var observers: [any NSObjectProtocol] = []

    init() {}


    func receive(_ next: Projection) {
        if isOpen {
            pending = next
        } else {
            projection = next
        }
    }

    func menuDidOpen() {
        isOpen = true
    }

    func menuDidClose() {
        isOpen = false
        if let pending {
            self.pending = nil
            projection = pending
        }
    }


    func observeMenuTracking(_ center: NotificationCenter = .default) {
        observers.append(center.addObserver(forName: NSMenu.didBeginTrackingNotification, object: nil, queue: nil) { [weak self] note in
            let menu = (note.object as? NSMenu).map { ObjectIdentifier($0) }
            MainActor.assumeIsolated { self?.trackingBegan(menu) }
        })
        observers.append(center.addObserver(forName: NSMenu.didEndTrackingNotification, object: nil, queue: nil) { [weak self] note in
            let menu = (note.object as? NSMenu).map { ObjectIdentifier($0) }
            MainActor.assumeIsolated { self?.trackingEnded(menu) }
        })
    }

    private func trackingBegan(_ menu: ObjectIdentifier?) {
        guard trackedMenu == nil, let menu else { return }
        trackedMenu = menu
        menuDidOpen()
    }

    private func trackingEnded(_ menu: ObjectIdentifier?) {
        guard let trackedMenu, trackedMenu == menu else { return }
        self.trackedMenu = nil
        menuDidClose()
    }
}
