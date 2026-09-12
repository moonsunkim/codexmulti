import SwiftUI







struct SettingsWindowScene: Scene {
    static let id = "main"
    static let title = "CodexMulti"

    let store: CoreStore
    let options: LaunchOptions
    let submit: IntentSink

    var body: some Scene {
        Window(Self.title, id: Self.id) {
            SettingsPresentation(store: store, options: options, submit: submit)
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

private struct SettingsPresentation: View {
    let store: CoreStore
    let options: LaunchOptions
    let submit: IntentSink
    @StateObject private var systemAppearance = SystemAppearance()

    var body: some View {
        let preference = store.projection?.view.settings.appearance ?? .system
        SettingsShell(store: store, options: options, submit: submit)
            .preferredColorScheme(AppearanceResolver.preferredScheme(preference) ?? systemAppearance.scheme)
    }
}
