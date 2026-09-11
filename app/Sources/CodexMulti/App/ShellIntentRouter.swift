import ServiceManagement



enum ShellIntentOrigin {
    case window
    case tray
}



struct LaunchAtLoginRegistrar: Sendable {
    private let update: @MainActor @Sendable (Bool) throws -> Void

    init(_ update: @escaping @MainActor @Sendable (Bool) throws -> Void) {
        self.update = update
    }

    @MainActor
    func setEnabled(_ enabled: Bool) throws {
        try update(enabled)
    }

    static let live = LaunchAtLoginRegistrar { enabled in
        if enabled {
            try SMAppService.mainApp.register()
        } else {
            try SMAppService.mainApp.unregister()
        }
    }
}



@MainActor
struct ShellIntentRouter {
    let core: any CoreProtocol
    let launchAtLogin: LaunchAtLoginRegistrar
    let presentSettings: @MainActor () -> Void

    init(core: any CoreProtocol,
         launchAtLogin: LaunchAtLoginRegistrar,
         presentSettings: @escaping @MainActor () -> Void = { WindowPresenter.shared.showSettings() }) {
        self.core = core
        self.launchAtLogin = launchAtLogin
        self.presentSettings = presentSettings
    }

    func route(_ intent: Intent, origin: ShellIntentOrigin = .window) async {
        let fromTray: Bool
        switch origin {
        case .window: fromTray = false
        case .tray: fromTray = true
        }
        if fromTray { prepareTrayPresentation(intent) }
        await routePrepared(intent, fromTray: fromTray)
    }

    private func prepareTrayPresentation(_ intent: Intent) {
        if ShellRoute.requiresSettingsPresentation(intent) { presentSettings() }
    }

    private func routePrepared(_ intent: Intent, fromTray: Bool) async {
        if ShellRoute.destination(intent) == .settingsTab {
            if fromTray {
                SettingsTabPresenter.shared.selectSettings()
            } else {
                SettingsTabPresenter.shared.show()
            }
            return
        }

        await core.submit(intent)
        guard case .set_launch_at_login(let enabled) = intent else { return }

        let failed: Bool
        do {
            try launchAtLogin.setEnabled(enabled)
            failed = false
        } catch {
            failed = true
        }
        await core.submit(.report_launch_at_login_registration_failure(failed: failed))
    }

    var sink: IntentSink {
        { intent in
            Task { @MainActor in await route(intent) }
        }
    }

    var traySink: IntentSink {
        { intent in
            prepareTrayPresentation(intent)
            Task { @MainActor in await routePrepared(intent, fromTray: true) }
        }
    }
}
