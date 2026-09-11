import SwiftUI







struct SettingsWindowScene: Scene {
    static let id = "main"
    static let title = "CodexMulti"

    let store: CoreStore
    let options: LaunchOptions
    let submit: IntentSink

    var body: some Scene {
        Window(Self.title, id: Self.id) {
            SettingsShell(store: store, options: options, submit: submit)
        }
        .defaultLaunchBehavior(options.showWindow ? .presented : .suppressed)
        .restorationBehavior(.disabled)
        .windowStyle(.hiddenTitleBar)
        .windowToolbarStyle(.unified(showsTitle: false))
        .defaultSize(width: Grid.width, height: Grid.height)
        .windowResizability(.contentMinSize)
        .defaultPosition(.center)
        .commands {
            CommandGroup(replacing: .appSettings) {
                Button(Copy.settings) { SettingsTabPresenter.shared.show() }
                    .keyboardShortcut(",", modifiers: .command)
            }
        }
    }
}
