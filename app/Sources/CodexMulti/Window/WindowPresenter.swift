import AppKit







@MainActor
struct WindowPresentationActions {
    var activateIgnoringOtherApps: () -> Bool
    var activateIgnoringOtherAppsFallback: () -> Void
    var deminiaturize: (NSWindow) -> Void
    var moveToActiveSpace: (NSWindow) -> Void
    var makeKeyAndOrderFront: (NSWindow) -> Void
    var orderFrontRegardless: (NSWindow) -> Void

    static let live = WindowPresentationActions(
        activateIgnoringOtherApps: {
            let application = NSRunningApplication.current
            let selector = NSSelectorFromString("activateFromApplication:options:")
            typealias Activate = @convention(c) (
                NSRunningApplication,
                Selector,
                NSRunningApplication?,
                UInt
            ) -> Bool
            let implementation = application.method(for: selector)
            let activate = unsafeBitCast(implementation, to: Activate.self)
            return activate(
                application,
                selector,
                nil,
                NSApplication.ActivationOptions.activateIgnoringOtherApps.rawValue)
        },
        activateIgnoringOtherAppsFallback: {
            NSApp.activate(ignoringOtherApps: true)
        },
        deminiaturize: { $0.deminiaturize(nil) },
        moveToActiveSpace: { $0.collectionBehavior.insert(.moveToActiveSpace) },
        makeKeyAndOrderFront: { $0.makeKeyAndOrderFront(nil) },
        orderFrontRegardless: { $0.orderFrontRegardless() }
    )
}



@MainActor
final class WindowPresenter {
    enum Activation {
        case userInitiated
        case nonactivating
    }

    static let shared = WindowPresenter()

    private let actions: WindowPresentationActions

    var open: (() -> Void)?

    weak var settingsWindow: NSWindow?

    var headless = false

    private(set) var suppressedShowRequests = 0

    private(set) var shows = 0

    init(actions: WindowPresentationActions = .live) {
        self.actions = actions
    }

    func showSettings(activation: Activation = .userInitiated) {
        if headless {
            suppressedShowRequests += 1
            return
        }
        shows += 1
        let existingWindow = settingsWindow ?? Self.findSettingsWindow()
        switch activation {
        case .userInitiated:
            if !actions.activateIgnoringOtherApps() {
                actions.activateIgnoringOtherAppsFallback()
            }
        case .nonactivating:
            break
        }
        open?()
        guard case .userInitiated = activation else { return }
        if let window = existingWindow ?? settingsWindow ?? Self.findSettingsWindow() {
            actions.deminiaturize(window)
            actions.moveToActiveSpace(window)
            actions.makeKeyAndOrderFront(window)
            actions.orderFrontRegardless(window)
        }
    }



    private static func findSettingsWindow() -> NSWindow? {
        NSApp.windows.first { $0.identifier?.rawValue.hasPrefix(SettingsWindowScene.id) == true }
    }
}
