import AppKit
import SwiftUI



struct WindowMoveExclusion: NSViewRepresentable {
    final class ExclusionView: NSView {
        override var mouseDownCanMoveWindow: Bool { false }
    }

    func makeNSView(context: Context) -> ExclusionView { ExclusionView() }
    func updateNSView(_ nsView: ExclusionView, context: Context) {}
}







struct WindowChrome: NSViewRepresentable {
    let options: LaunchOptions

    func makeNSView(context: Context) -> HookView {
        let view = HookView()
        view.options = options
        return view
    }

    func updateNSView(_ nsView: HookView, context: Context) {}

    final class HookView: NSView {
        var options = LaunchOptions(arguments: [])
        private var configured: ObjectIdentifier?

        override func viewDidMoveToWindow() {
            super.viewDidMoveToWindow()
            guard let window, configured != ObjectIdentifier(window) else { return }
            configured = ObjectIdentifier(window)
            WindowChrome.configure(window, options)
        }
    }

    @MainActor static func configure(_ window: NSWindow, _ options: LaunchOptions) {
        window.isOpaque = false
        window.backgroundColor = .clear
        window.hasShadow = true



        window.styleMask.insert(.fullSizeContentView)
        window.titlebarAppearsTransparent = true
        window.titlebarSeparatorStyle = .none
        window.isMovableByWindowBackground = true
        window.standardWindowButton(.zoomButton)?.isEnabled = false
        window.isRestorable = false
        CloseToHideDelegate.install(on: window)
        WindowPresenter.shared.settingsWindow = window
        if options.showWindow && options.noActivate {


            window.orderFrontRegardless()
        }
        guard let frame = options.frame else { return }
        window.level = .floating

        for delay in [0.0, 0.25, 0.6, 1.2] {
            DispatchQueue.main.asyncAfter(deadline: .now() + delay) {
                window.setFrame(frame, display: true)
                if options.showWindow && options.noActivate { window.orderFrontRegardless() }
            }
        }
    }
}
