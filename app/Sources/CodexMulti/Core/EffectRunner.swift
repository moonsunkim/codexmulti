import AppKit
import Foundation





@MainActor
final class EffectRunner {
    var showSettings: () -> Void
    var quit: () -> Void

    var writeClipboard: (String) -> Bool

    var reply: (Intent) -> Void

    private(set) var runCount = 0

    init(showSettings: @escaping () -> Void,
         quit: @escaping () -> Void,
         writeClipboard: @escaping (String) -> Bool,
         reply: @escaping (Intent) -> Void) {
        self.showSettings = showSettings
        self.quit = quit
        self.writeClipboard = writeClipboard
        self.reply = reply
    }





    static func forApp() -> EffectRunner {
        EffectRunner(
            showSettings: { WindowPresenter.shared.showSettings() },
            quit: { LifecycleLog.shared?.note(.quitEffect); QuitRequest.post() },
            writeClipboard: { text in
                let pasteboard = NSPasteboard.general
                pasteboard.clearContents()
                return pasteboard.setString(text, forType: .string)
            },
            reply: { _ in }
        )
    }




    static func forCapture() -> EffectRunner {
        EffectRunner(
            showSettings: {},
            quit: {},
            writeClipboard: { _ in false },
            reply: { _ in }
        )
    }

    func run(_ effects: [Effect]) {
        for effect in effects {
            run(effect)
        }
    }

    func runPresentationEffects(_ effects: [Effect]) {
        for effect in effects {
            if case .show_settings = effect {
                run(effect)
            }
        }
    }

    func runRemainingEffects(_ effects: [Effect]) {
        for effect in effects {
            if case .show_settings = effect { continue }
            run(effect)
        }
    }

    private func run(_ effect: Effect) {
        runCount += 1
        switch effect {
        case .show_settings: showSettings()
        case .quit: quit()
        case .clipboard(let text): reply(.diagnostics_copied(ok: writeClipboard(text)))
        }
    }
}
