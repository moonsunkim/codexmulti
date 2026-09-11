import AppKit
import Foundation

















@MainActor
enum QuitRequest {
    static func post() {
        RunLoop.main.perform {
            MainActor.assumeIsolated {
                endAttachedSheets()
                NSApp.terminate(nil)
            }
        }
    }


    @discardableResult
    static func endAttachedSheets(of hosts: [any SheetHost] = NSApp.windows) -> Int {
        var ended = 0
        for host in hosts {
            guard let sheet = host.attachedSheet else { continue }
            host.endSheet(sheet)
            ended += 1
        }
        return ended
    }
}


@MainActor
protocol SheetHost: AnyObject {
    var attachedSheet: NSWindow? { get }
    func endSheet(_ sheet: NSWindow)
}

extension NSWindow: SheetHost {}
