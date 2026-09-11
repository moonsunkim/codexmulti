import AppKit
import SwiftUI




@main
struct CodexMultiApp: App {
    @NSApplicationDelegateAdaptor(AppDelegate.self) private var delegate

    var body: some Scene {
        MenuBarExtra(isInserted: .constant(!(delegate.options.noStatusItem || delegate.options.headless))) {
            TrayMenu(store: delegate.store, submit: traySubmit)
        } label: {
            TrayLabel(store: delegate.store)
        }
        .menuBarExtraStyle(.menu)

        SettingsWindowScene(store: delegate.store, options: delegate.options, submit: submit)
    }


    private var submit: IntentSink {
        ShellIntentRouter(core: delegate.core, launchAtLogin: .live).sink
    }

    private var traySubmit: IntentSink {
        ShellIntentRouter(core: delegate.core, launchAtLogin: .live).traySink
    }
}
