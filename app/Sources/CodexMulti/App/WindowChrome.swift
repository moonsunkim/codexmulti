import AppKit
import SwiftUI



@MainActor
protocol WindowAppearanceWriting: AnyObject {
    var explicitAppearanceName: NSAppearance.Name? { get }
    func writeAppearance(named name: NSAppearance.Name?)
}

extension NSWindow: WindowAppearanceWriting {
    var explicitAppearanceName: NSAppearance.Name? { appearance?.name }

    func writeAppearance(named name: NSAppearance.Name?) {
        appearance = name.flatMap { NSAppearance(named: $0) }
    }
}




struct WindowMoveExclusion: NSViewRepresentable {
    final class ExclusionView: NSView {
        override var mouseDownCanMoveWindow: Bool { false }
    }

    func makeNSView(context: Context) -> ExclusionView { ExclusionView() }
    func updateNSView(_ nsView: ExclusionView, context: Context) {}
}







struct WindowChrome: NSViewRepresentable {
    let options: LaunchOptions
    let appearanceName: NSAppearance.Name?

    func makeNSView(context: Context) -> HookView {
        let view = HookView()
        view.options = options
        view.appearanceName = appearanceName
        return view
    }

    func updateNSView(_ nsView: HookView, context: Context) {


        nsView.updateWindowAppearance(to: appearanceName)
    }



    final class HookView: NSView {
        var options = LaunchOptions(arguments: [])
        var appearanceName: NSAppearance.Name?
        var appearanceWriterOverride: (any WindowAppearanceWriting)?
        private var configured: ObjectIdentifier?






        private var appliedName: NSAppearance.Name??

        func updateWindowAppearance(to name: NSAppearance.Name?) {
            if appearanceName != name { appearanceName = name }
            guard appliedName != .some(name) else { return }
            appliedName = .some(name)
            if let appearanceWriterOverride {
                appearanceWriterOverride.writeAppearance(named: name)
            } else if let window {
                window.writeAppearance(named: name)
            }
        }

        override func viewDidMoveToWindow() {
            super.viewDidMoveToWindow()
            guard let window, configured != ObjectIdentifier(window) else { return }
            configured = ObjectIdentifier(window)
            WindowChrome.configure(window, options, appearanceName: appearanceName)
        }
    }

    @MainActor static func configure(_ window: NSWindow, _ options: LaunchOptions,
                                     appearanceName: NSAppearance.Name?) {
        updateAppearance(appearanceName, on: window)
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



    @MainActor static func updateAppearance(_ name: NSAppearance.Name?,
                                            on target: any WindowAppearanceWriting) {
        guard target.explicitAppearanceName != name else { return }
        target.writeAppearance(named: name)
    }
}
