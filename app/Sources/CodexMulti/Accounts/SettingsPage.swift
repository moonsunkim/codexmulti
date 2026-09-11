import SwiftUI



enum ShellTab: Equatable, CaseIterable, Sendable {
    case accounts
    case settings
}

enum ShellRoute {
    enum Destination: Equatable { case core, settingsTab }
    static func destination(_ intent: Intent) -> Destination { intent == .open_details ? .settingsTab : .core }

    static func requiresSettingsPresentation(_ intent: Intent) -> Bool {
        switch intent {
        case .open_details, .open_account,
             .begin_proxy_switch, .begin_clear_cooldown,
             .begin_failover_switch, .begin_failover_switch_id,
             .begin_clear_cooldown_account,
             .begin_add_account, .begin_rename, .begin_remove, .begin_reset:
            true
        default:
            false
        }
    }
}



@MainActor
final class SettingsTabPresenter {
    static let shared = SettingsTabPresenter()
    private var select: ((ShellTab) -> Void)?
    private var pending: ShellTab?

    func show(presentSettings: () -> Void = { WindowPresenter.shared.showSettings() }) {
        presentSettings()
        selectSettings()
    }

    func selectSettings() {
        if let select { select(.settings) }
        else { pending = .settings }
    }

    func register(select: @escaping (ShellTab) -> Void) {
        self.select = select
        if let pending {
            self.pending = nil
            select(pending)
        }
    }

    func unregister() {
        select = nil
    }
}

enum PreferencesModel {
    enum SectionID: Equatable, Sendable {
        case system
        case codex
        case proxy
        case about

        func title(settings: SettingsView) -> String {
            switch self {
            case .system: Copy.system
            case .codex: settings.codex_section_title
            case .proxy: Copy.proxy
            case .about: Copy.about
            }
        }
    }

    enum Row: CaseIterable, Equatable, Sendable {
        case launchAtLogin
        case autoRefresh
        case theme
        case codexUsageWindow
        case codexShowModelLimits
        case useFailoverProxy
        case advancedProxyControls
        case proxyServiceStatus
        case codexRouting
        case version

        func label(settings: SettingsView) -> String {
            switch self {
            case .launchAtLogin: Copy.launchAtLogin
            case .autoRefresh: Copy.autoRefresh
            case .theme: Copy.theme
            case .codexUsageWindow: settings.codex_usage_window_label
            case .codexShowModelLimits: settings.codex_show_model_limits_label
            case .useFailoverProxy: Copy.useFailoverProxy
            case .advancedProxyControls: Copy.advancedProxyControls
            case .proxyServiceStatus: Copy.factStatus
            case .codexRouting: Copy.codexRouting
            case .version: Copy.version
            }
        }
    }

    struct Section: Equatable, Sendable {
        let id: SectionID
        let rows: [Row]

        func title(settings: SettingsView) -> String { id.title(settings: settings) }
    }

    struct AutoRefreshOption: Equatable, Identifiable, Sendable {
        let minutes: UInt16
        let label: String
        var id: UInt16 { minutes }
    }

    static let sectionLayout = [
        Section(id: .system, rows: [.launchAtLogin, .autoRefresh, .theme]),
        Section(id: .codex, rows: [.codexUsageWindow, .codexShowModelLimits]),
        Section(id: .proxy, rows: [
            .useFailoverProxy, .advancedProxyControls, .proxyServiceStatus, .codexRouting,
        ]),
        Section(id: .about, rows: [.version]),
    ]
    static func sections(settings: SettingsView) -> [String] {
        sectionLayout.map { $0.title(settings: settings) }
    }


    static var versionText: String {
        let info = Bundle.main.infoDictionary
        let short = info?["CFBundleShortVersionString"] as? String ?? "—"
        let build = info?["CFBundleVersion"] as? String ?? "—"
        return short == build ? short : "\(short) (\(build))"
    }

    static let autoRefreshOptions = [
        AutoRefreshOption(minutes: 0, label: "Off"),
        AutoRefreshOption(minutes: 15, label: "15 min"),
        AutoRefreshOption(minutes: 30, label: "30 min"),
        AutoRefreshOption(minutes: 60, label: "1 hour"),
    ]

    static func appearanceIntent(_ appearance: Appearance) -> Intent { .set_appearance(value: appearance) }
    static func codexUsageWindowIntent(_ value: CodexUsageWindow) -> Intent { .set_codex_usage_window(value: value) }
    static func codexShowModelLimitsIntent(_ enabled: Bool) -> Intent { .set_codex_show_model_limits(on: enabled) }
    static func launchAtLoginIntent(_ enabled: Bool) -> Intent { .set_launch_at_login(on: enabled) }
    static func autoRefreshIntent(_ minutes: UInt16) -> Intent { .set_auto_refresh(minutes: minutes) }

    @MainActor
    static func selectCodexUsageWindow(
        _ candidate: CodexUsageWindow,
        current: CodexUsageWindow,
        supported: [CodexUsageWindow],
        submit: IntentSink
    ) {
        guard candidate != current, supported.contains(candidate) else { return }
        submit(codexUsageWindowIntent(candidate))
    }

    @MainActor
    static func selectCodexShowModelLimits(
        _ enabled: Bool,
        current: Bool,
        supported: [Bool],
        submit: IntentSink
    ) {
        guard enabled != current, supported.contains(enabled) else { return }
        submit(codexShowModelLimitsIntent(enabled))
    }



    static func launchAtLoginFailureText(_ settings: SettingsView) -> String? {
        settings.launch_at_login_registration_failed ? Copy.launchAtLoginRegistrationFailed : nil
    }

    static func label(_ appearance: Appearance, settings: SettingsView) -> String {
        switch appearance {
        case .system: settings.appearance_label_system
        case .light: settings.appearance_label_light
        case .dark: settings.appearance_label_dark
        }
    }
}



struct SettingsPage: View {
    let projection: Projection
    @Binding var drafts: ProxyDrafts
    @Environment(\.tone) private var tone
    @Environment(\.renderedVersionText) private var renderedVersionText

    var body: some View {
        VStack(alignment: .leading, spacing: Grid.betweenContainers) {
            SettingsSection(title: PreferencesModel.sectionLayout[0].title(settings: projection.view.settings)) {
                Container {
                    SettingsRow(
                        label: PreferencesModel.Row.launchAtLogin.label(settings: projection.view.settings),
                        subtitle: PreferencesModel.launchAtLoginFailureText(projection.view.settings)) {
                        LaunchAtLoginSwitch(settings: projection.view.settings)
                    }
                    Hairline()
                    SettingsRow(label: PreferencesModel.Row.autoRefresh.label(settings: projection.view.settings),
                                subtitle: projection.view.settings.auto_refresh_traffic_text) {
                        AutoRefreshSegments(settings: projection.view.settings)
                    }
                    Hairline()
                    SettingsRow(label: PreferencesModel.Row.theme.label(settings: projection.view.settings)) {
                        AppearanceSegments(settings: projection.view.settings)
                    }
                }
            }
            SettingsSection(title: PreferencesModel.sectionLayout[1].title(settings: projection.view.settings)) {
                CodexSettingsPanel(settings: projection.view.settings)
            }
            SettingsSection(title: PreferencesModel.sectionLayout[2].title(settings: projection.view.settings)) {
                VStack(spacing: Grid.betweenContainers) {
                    ProxyLifecyclePanel(settings: projection.view.settings)
                }
            }
            SettingsSection(title: PreferencesModel.sectionLayout[3].title(settings: projection.view.settings)) {
                Container {
                    SettingsRow(label: PreferencesModel.Row.version.label(settings: projection.view.settings)) {
                        Text(verbatim: renderedVersionText ?? PreferencesModel.versionText)
                            .font(Face.secondary)
                            .foregroundStyle(tone.text2)
                    }
                }
            }
        }
        .padding(.horizontal, Grid.L)
        .onAppear { drafts.seedIfNeeded(from: projection.view.settings) }
    }
}

struct CodexSettingsPanel: View {
    let settings: SettingsView

    var body: some View {
        Container {
            SettingsRow(
                label: PreferencesModel.Row.codexUsageWindow.label(settings: settings),
                subtitle: settings.codex_usage_window_detail_text
            ) {
                CodexUsageWindowSegments(settings: settings)
            }
            Hairline()
            SettingsRow(
                label: PreferencesModel.Row.codexShowModelLimits.label(settings: settings),
                subtitle: settings.codex_show_model_limits_detail_text
            ) {
                CodexShowModelLimitsSwitch(settings: settings)
            }
        }
    }
}

struct SettingsSection<Content: View>: View {
    let title: String
    @ViewBuilder let content: () -> Content
    @Environment(\.tone) private var tone

    var body: some View {
        VStack(alignment: .leading, spacing: Grid.settingsLabelGap) {
            Text(verbatim: title)
                .font(Face.factLabel)
                .foregroundStyle(tone.text3)
                .padding(.leading, Grid.inset)
            content()
        }
        .frame(maxWidth: .infinity, alignment: .leading)
    }
}

struct SettingsRow<Control: View>: View {
    let label: String
    let subtitle: String?
    @ViewBuilder let control: () -> Control
    @Environment(\.tone) private var tone

    init(label: String, subtitle: String? = nil, @ViewBuilder control: @escaping () -> Control) {
        self.label = label
        self.subtitle = subtitle
        self.control = control
    }

    var body: some View {
        HStack(alignment: .center, spacing: Grid.gap) {
            VStack(alignment: .leading, spacing: Grid.factLabelGap) {
                Text(verbatim: label)
                    .font(Face.body)
                    .foregroundStyle(tone.text)
                    .lineLimit(1)
                if let subtitle, !subtitle.isEmpty {
                    Text(verbatim: subtitle)
                        .font(Face.secondary)
                        .foregroundStyle(tone.text3)
                        .lineLimit(1)
                        .truncationMode(.tail)
                }
            }
            control()
                .frame(maxWidth: .infinity, alignment: .trailing)
        }
        .padding(.horizontal, Grid.inset)
        .frame(height: Grid.accountsRow)
        .accessibilityElement(children: .contain)
    }
}

struct LaunchAtLoginSwitch: View {
    let settings: SettingsView
    @Environment(\.submit) private var submit

    var body: some View {
        Toggle("", isOn: Binding(
            get: { settings.launch_at_login },
            set: { enabled in
                guard enabled != settings.launch_at_login else { return }
                submit(PreferencesModel.launchAtLoginIntent(enabled))
            }))
            .labelsHidden()
            .toggleStyle(InkSwitchStyle())
            .accessibilityLabel(Copy.launchAtLogin)
    }
}

struct CodexUsageWindowSegments: View {
    let settings: SettingsView
    @Environment(\.tone) private var tone
    @Environment(\.submit) private var submit

    var body: some View {
        HStack(spacing: 0) {
            ForEach(settings.codex_usage_window_supported, id: \.self) { candidate in
                Button {
                    PreferencesModel.selectCodexUsageWindow(
                        candidate,
                        current: settings.codex_usage_window,
                        supported: settings.codex_usage_window_supported,
                        submit: submit)
                } label: {
                    Text(verbatim: candidate.rawValue)
                        .font(candidate == settings.codex_usage_window ? Face.bandStrong : Face.band)
                        .foregroundStyle(candidate == settings.codex_usage_window ? tone.text : tone.text2)
                        .frame(width: Grid.appearanceSegmentWidth, height: Grid.settingsSegmentHeight)
                        .background {
                            if candidate == settings.codex_usage_window { Capsule().fill(tone.segment) }
                        }
                        .contentShape(Capsule())
                }
                .buttonStyle(.plain)
            }
        }
        .padding(Grid.settingsSegmentPadding)
        .background(Capsule().fill(tone.pill))
        .accessibilityElement(children: .ignore)
        .accessibilityLabel(settings.codex_usage_window_label)
        .accessibilityValue(settings.codex_usage_window.rawValue)
    }
}

struct CodexShowModelLimitsSwitch: View {
    let settings: SettingsView
    @Environment(\.submit) private var submit

    var body: some View {
        Toggle("", isOn: Binding(
            get: { settings.codex_show_model_limits },
            set: { enabled in
                PreferencesModel.selectCodexShowModelLimits(
                    enabled,
                    current: settings.codex_show_model_limits,
                    supported: settings.codex_show_model_limits_supported,
                    submit: submit)
            }))
            .labelsHidden()
            .toggleStyle(InkSwitchStyle())
            .disabled(!settings.codex_show_model_limits_supported.contains(!settings.codex_show_model_limits))
            .accessibilityLabel(settings.codex_show_model_limits_label)
            .accessibilityValue(settings.codex_show_model_limits_detail_text)
    }
}


struct AutoRefreshSegments: View {
    let settings: SettingsView
    @Environment(\.tone) private var tone
    @Environment(\.submit) private var submit

    var body: some View {
        HStack(spacing: 0) {
            ForEach(PreferencesModel.autoRefreshOptions) { option in
                Button {
                    guard option.minutes != settings.auto_refresh_minutes else { return }
                    submit(PreferencesModel.autoRefreshIntent(option.minutes))
                } label: {
                    Text(verbatim: option.label)
                        .font(option.minutes == settings.auto_refresh_minutes ? Face.bandStrong : Face.band)
                        .foregroundStyle(option.minutes == settings.auto_refresh_minutes ? tone.text : tone.text2)
                        .frame(width: Grid.autoRefreshSegmentWidth, height: Grid.settingsSegmentHeight)
                        .background {
                            if option.minutes == settings.auto_refresh_minutes {
                                Capsule().fill(tone.segment)
                            }
                        }
                        .contentShape(Capsule())
                }
                .buttonStyle(.plain)
            }
        }
        .padding(Grid.settingsSegmentPadding)
        .background(Capsule().fill(tone.pill))
        .accessibilityElement(children: .contain)
        .accessibilityLabel(Copy.autoRefresh)
    }
}


struct AppearanceSegments: View {
    let settings: SettingsView
    @Environment(\.tone) private var tone
    @Environment(\.submit) private var submit
    @Environment(\.renderedAppearance) private var renderedAppearance

    private static let order: [Appearance] = [.system, .light, .dark]
    private var current: Appearance { renderedAppearance ?? settings.appearance }

    var body: some View {
        HStack(spacing: 0) {
            ForEach(Self.order, id: \.self) { candidate in
                Button {
                    guard candidate != settings.appearance else { return }
                    submit(PreferencesModel.appearanceIntent(candidate))
                } label: {
                    Text(verbatim: PreferencesModel.label(candidate, settings: settings))
                        .font(candidate == current ? Face.bandStrong : Face.band)
                        .foregroundStyle(candidate == current ? tone.text : tone.text2)
                        .frame(width: Grid.appearanceSegmentWidth, height: Grid.settingsSegmentHeight)
                        .background {
                            if candidate == current { Capsule().fill(tone.segment) }
                        }
                        .contentShape(Capsule())
                }
                .buttonStyle(.plain)
            }
        }
        .padding(Grid.settingsSegmentPadding)
        .background(Capsule().fill(tone.pill))
        .accessibilityElement(children: .ignore)
        .accessibilityLabel(Copy.appearance)
        .accessibilityValue(PreferencesModel.label(current, settings: settings))
    }
}
