import Foundation







enum FailoverModel {
    typealias MenuItem = AccountsModel.MenuItem






    static func rowMenu(_ row: ProxyAccountView) -> [[MenuItem]] {
        var lines: [MenuItem] = []
        if row.can_switch {
            lines.append(MenuItem("switch", Copy.useInFailover, intent: .begin_proxy_switch(row: row.index)))
        }
        if row.can_pause {
            lines.append(MenuItem("pause", Copy.pause, intent: .pause_proxy_account(row: row.index)))
        }
        if row.can_resume {
            lines.append(MenuItem("resume", Copy.resume, intent: .resume_proxy_account(row: row.index)))
        }
        if row.can_clear_cooldown {
            lines.append(MenuItem("clear_cooldown", Copy.clearCooldown, intent: .begin_clear_cooldown(row: row.index)))
        }
        return lines.isEmpty ? [] : [lines]
    }



    static func menuShown(_ row: ProxyAccountView) -> Bool {
        row.has_actions
    }






    enum BadgeStyle: Equatable, Sendable { case active, ready, muted }

    static func badgeStyle(_ row: ProxyAccountView) -> BadgeStyle {
        if row.state_accent { return .active }
        return row.label_muted ? .muted : .ready
    }




    enum LabelInk: Equatable, Sendable { case text, muted }

    static func labelInk(_ row: ProxyAccountView) -> LabelInk {
        row.label_muted ? .muted : .text
    }





    static func detailLine(_ row: ProxyAccountView) -> String {
        var parts: [String] = []
        if !row.detail_text.isEmpty { parts.append(row.detail_text) }
        if row.in_flight > 0 { parts.append(row.in_flight_text + Copy.inFlightSuffix) }
        return parts.joined(separator: Copy.statusSeparator)
    }



    static func accessibilityLabel(_ row: ProxyAccountView) -> String {
        "\(row.label), \(row.state_text)"
    }

    static func accessibilityValue(_ row: ProxyAccountView) -> String {
        row.in_flight == 0 ? row.detail_text : "\(row.detail_text), \(row.in_flight_text)\(Copy.inFlightSuffix)"
    }






    static func emptyText(_ view: ViewState) -> String {
        view.proxy_empty_text
    }

    static func bannerIsShown(_ view: ViewState) -> Bool {
        AccountsModel.bannerIsShown(view)
    }



    static func proxyEnabledIntent(_ enabled: Bool) -> Intent { .set_proxy_enabled(on: enabled) }

    struct LifecycleAction: Identifiable, Equatable, Sendable {
        enum ID: String, Hashable, Sendable {
            case install, repair, stop, enableRouting, disableRouting, replaceRouting
        }

        enum Confirmation: Equatable, Sendable {
            case none
            case clientQuiescence
            case replaceRouting
        }

        let id: ID
        let title: String
        let enabled: Bool
        let intent: Intent
        let confirmation: Confirmation
    }




    static func serviceActions(_ view: ViewState) -> [LifecycleAction] {
        serviceActions(view.settings)
    }

    static func serviceActions(_ view: SettingsView) -> [LifecycleAction] {
        switch view.proxy_service_state {
        case .not_installed:
            [LifecycleAction(id: .install, title: Copy.installAndStart,
                             enabled: view.proxy_service_can_install, intent: .install_proxy_service,
                             confirmation: .none)]
        case .installed_stale, .unreachable:
            view.proxy_service_can_repair
                ? [LifecycleAction(id: .repair, title: Copy.repairProxyService, enabled: true,
                                   intent: .repair_proxy_service,
                                   confirmation: .clientQuiescence)]
                : []
        case .starting:
            []
        case .running:
            view.proxy_service_can_stop
                ? [LifecycleAction(id: .stop, title: Copy.stopProxyService, enabled: true,
                                   intent: .stop_proxy_service,
                                   confirmation: .clientQuiescence)]
                : []
        }
    }



    static func routingActions(_ view: ViewState) -> [LifecycleAction] {
        routingActions(view.settings)
    }

    static func routingActions(_ view: SettingsView) -> [LifecycleAction] {
        switch view.codex_routing_state {
        case .off where view.proxy_service_state == .running:
            [LifecycleAction(id: .enableRouting, title: Copy.enableForCodex, enabled: true,
                             intent: .enable_codex_routing(), confirmation: .none)]
        case .on:
            [LifecycleAction(id: .disableRouting, title: Copy.disableForCodex, enabled: true,
                             intent: .disable_codex_routing, confirmation: .none)]
        case .conflicting where view.proxy_service_state == .running:
            [LifecycleAction(id: .replaceRouting, title: Copy.replaceCodexRouting, enabled: true,
                             intent: .enable_codex_routing(replace_conflicting: true),
                             confirmation: .replaceRouting)]
        case .off, .conflicting:
            []
        }
    }

    static func routingStateText(_ state: CodexRoutingState) -> String {
        switch state {
        case .off: Copy.routingOff
        case .on: Copy.routingOn
        case .conflicting: Copy.routingConflicting
        }
    }







    static func settingsSummary(_ view: ViewState, expanded: Bool) -> String {
        if view.proxy_work != .idle { return view.proxy_detail_text }
        if !expanded, view.proxy_sync_state == .needed { return view.proxy_detail_text }
        return view.settings.proxy_settings_summary_text
    }


    static func canSave(_ shell: ShellState) -> Bool {
        !shell.proxy_busy
    }
}




struct ProxyConfirmationGate: Equatable, Sendable {
    enum Kind: Equatable, Sendable { case clientQuiescence, replaceRouting }

    struct Pending: Equatable, Sendable {
        let kind: Kind
        let title: String
        let message: String
        let confirmTitle: String
        let intent: Intent
    }

    private(set) var pending: Pending?

    mutating func request(_ action: FailoverModel.LifecycleAction) -> Intent? {
        guard action.enabled else { return nil }
        switch action.confirmation {
        case .none:
            return action.intent
        case .clientQuiescence:
            pending = Pending(kind: .clientQuiescence, title: Copy.clientQuiescenceTitle,
                              message: Copy.clientQuiescenceMessage, confirmTitle: action.title,
                              intent: action.intent)
            return nil
        case .replaceRouting:
            pending = Pending(kind: .replaceRouting, title: Copy.replaceRoutingTitle,
                              message: Copy.replaceRoutingMessage, confirmTitle: Copy.replaceCodexRouting,
                              intent: action.intent)
            return nil
        }
    }

    mutating func cancel(_ kind: Kind? = nil) {
        guard kind == nil || pending?.kind == kind else { return }
        pending = nil
    }

    mutating func confirm(_ kind: Kind) -> Intent? {
        guard pending?.kind == kind else { return nil }
        let intent = pending?.intent
        pending = nil
        return intent
    }
}




struct ProxyDrafts: Equatable, Sendable {
    var base_url = ""
    var cli_path = ""
    var config_path = ""
    var node_path = ""
    private(set) var seeded = false


    mutating func seedIfNeeded(from view: ViewState) {
        seedIfNeeded(from: view.settings)
    }

    mutating func seedIfNeeded(from view: SettingsView) {
        guard !seeded else { return }
        base_url = view.proxy_base_url
        cli_path = view.proxy_cli_path
        config_path = view.proxy_config_path
        node_path = view.proxy_node_path
        seeded = true
    }


    var saveIntent: Intent {
        .save_proxy_settings(base_url: base_url, cli_path: cli_path, config_path: config_path, node_path: node_path)
    }
}
