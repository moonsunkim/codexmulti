import AppKit
import ObjectiveC
import os








@MainActor
final class CloseToHideDelegate: NSObject, NSWindowDelegate {
    nonisolated(unsafe) private(set) weak var forwardee: (any NSWindowDelegate)?
    private(set) var hides = 0

    private init(forwardee: (any NSWindowDelegate)?) {
        self.forwardee = forwardee
        super.init()
    }


    @discardableResult
    static func install(on window: NSWindow) -> CloseToHideDelegate {
        if let installed = window.delegate as? CloseToHideDelegate { return installed }
        let proxy = CloseToHideDelegate(forwardee: window.delegate)
        window.delegate = proxy
        objc_setAssociatedObject(window, &associationKey, proxy, .OBJC_ASSOCIATION_RETAIN_NONATOMIC)
        Logger(subsystem: "dev.codexmulti.app", category: "window")
            .notice("close-to-hide installed; forwarding to \(proxy.forwardee.map { String(describing: type(of: $0)) } ?? "nil", privacy: .public)")
        return proxy
    }

    static func installed(on window: NSWindow) -> CloseToHideDelegate? {
        window.delegate as? CloseToHideDelegate
    }

    func windowShouldClose(_ sender: NSWindow) -> Bool {
        hides += 1
        sender.orderOut(nil)
        return false
    }



    nonisolated override func responds(to aSelector: Selector!) -> Bool {
        super.responds(to: aSelector) || (forwardee?.responds(to: aSelector) ?? false)
    }

    nonisolated override func forwardingTarget(for aSelector: Selector!) -> Any? {
        forwardee
    }
}

nonisolated(unsafe) private var associationKey: UInt8 = 0
