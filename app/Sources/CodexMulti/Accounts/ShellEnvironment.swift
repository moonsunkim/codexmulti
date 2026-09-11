import SwiftUI



typealias IntentSink = @MainActor @Sendable (Intent) -> Void

private struct SubmitKey: EnvironmentKey {
    static let defaultValue: IntentSink = { _ in }
}



private struct AutoOpenKey: EnvironmentKey {
    static let defaultValue: LaunchOptions.OpenTarget? = nil
}



private struct RenderedAppearanceKey: EnvironmentKey {
    static let defaultValue: Appearance? = nil
}



private struct RenderedVersionTextKey: EnvironmentKey {
    static let defaultValue: String? = nil
}

extension EnvironmentValues {
    var submit: IntentSink {
        get { self[SubmitKey.self] }
        set { self[SubmitKey.self] = newValue }
    }

    var autoOpen: LaunchOptions.OpenTarget? {
        get { self[AutoOpenKey.self] }
        set { self[AutoOpenKey.self] = newValue }
    }

    var renderedAppearance: Appearance? {
        get { self[RenderedAppearanceKey.self] }
        set { self[RenderedAppearanceKey.self] = newValue }
    }

    var renderedVersionText: String? {
        get { self[RenderedVersionTextKey.self] }
        set { self[RenderedVersionTextKey.self] = newValue }
    }
}


enum AutoOpen {
    static let settle: Duration = .milliseconds(900)
}
