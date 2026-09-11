import AppKit
import Observation
import SwiftUI







@MainActor @Observable
final class FocusOrigin {
    enum Source: Equatable, Sendable { case pointer, keyboard }

    private(set) var source: Source = .pointer
    @ObservationIgnored private var monitor: Any?

    var isKeyboard: Bool { source == .keyboard }



    nonisolated static func source(after type: NSEvent.EventType, from current: Source) -> Source {
        switch type {
        case .keyDown: .keyboard
        case .leftMouseDown, .rightMouseDown, .otherMouseDown: .pointer
        default: current
        }
    }



    nonisolated static func ringShown(focused: Bool, keyboard: Bool, appearsActive: Bool) -> Bool {
        focused && keyboard && appearsActive
    }

    func record(_ type: NSEvent.EventType) {
        let next = Self.source(after: type, from: source)
        if next != source { source = next }
    }



    func install() {
        guard monitor == nil else { return }
        monitor = NSEvent.addLocalMonitorForEvents(matching: [.keyDown, .leftMouseDown, .rightMouseDown, .otherMouseDown]) { [weak self] event in
            MainActor.assumeIsolated { self?.record(event.type) }
            return event
        }
    }

    func uninstall() {
        if let monitor { NSEvent.removeMonitor(monitor) }
        monitor = nil
    }
}



private struct KeyboardFocusKey: EnvironmentKey {
    static let defaultValue = false
}

extension EnvironmentValues {
    var keyboardFocus: Bool {
        get { self[KeyboardFocusKey.self] }
        set { self[KeyboardFocusKey.self] = newValue }
    }
}
