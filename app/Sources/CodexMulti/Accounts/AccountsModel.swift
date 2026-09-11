import Foundation






enum AccountsModel {

    struct MenuItem: Equatable, Identifiable, Sendable {
        let id: String
        let label: String
        let enabled: Bool
        let destructive: Bool
        let intent: Intent

        init(_ id: String, _ label: String, enabled: Bool = true, destructive: Bool = false, intent: Intent) {
            self.id = id
            self.label = label
            self.enabled = enabled
            self.destructive = destructive
            self.intent = intent
        }
    }




    enum PillDot: Equatable, Sendable { case point, muted, none }

    static func pillDot(_ view: ViewState) -> PillDot {
        guard view.capabilities.proxy_control else { return .none }
        switch view.proxy_reachability {
        case .reachable where view.proxy_config_path_matches:
            return .point
        case .unknown where !view.proxy_accounts.isEmpty:
            return .point
        default:
            return .muted
        }
    }







    static func rows(_ view: ViewState) -> [AccountRowView] {
        let split = min(max(view.claude_row_count, 0), view.account_rows.count)
        return Array(view.account_rows[split...])
    }


    static func hasNoAccounts(_ view: ViewState) -> Bool {
        rows(view).isEmpty
    }







    static func rowMenu(_ row: AccountRowView, shell: ShellState) -> [[MenuItem]] {
        var first: [MenuItem] = []
        if row.action_refresh {
            first.append(MenuItem("refresh", Copy.refresh, enabled: shell.can_refresh && !row.action_busy,
                                  intent: .refresh_account(row: row.index)))
        }
        if row.action_sign_in {
            first.append(MenuItem("sign_in", Copy.signIn, intent: .reauthenticate(row: row.index)))
        }
        if row.action_sign_in_again {
            first.append(MenuItem("sign_in_again", Copy.signInAgain, intent: .reauthenticate(row: row.index)))
        }
        if row.can_switch_proxy {
            first.append(MenuItem("switch", row.switch_label, intent: .begin_failover_switch(row: row.index)))
        } else if row.can_pause_proxy {
            first.append(MenuItem("pause", Copy.pauseInFailover, intent: .pause_failover_account(row: row.index)))
        }
        if row.can_reset {
            first.append(MenuItem("reset", row.reset_label, intent: .begin_reset(row: row.index)))
        }
        if row.can_clear_cooldown {
            first.append(MenuItem("clear_cooldown", Copy.clearCooldown, intent: .begin_clear_cooldown_account(row: row.index)))
        }
        let second = [
            MenuItem("rename", Copy.rename, intent: .begin_rename(row: row.index)),
            MenuItem("remove", Copy.remove, destructive: true, intent: .begin_remove(row: row.index)),
        ]
        return first.isEmpty ? [second] : [first, second]
    }


    static func accessibilityLabel(_ row: AccountRowView) -> String {
        row.access_label
    }

    static func accessibilityValue(_ row: AccountRowView) -> String {
        row.window.present ? "\(row.window.caption) \(row.window.percent_text)" : row.window.percent_text
    }



    static func rowOpacity(_ row: AccountRowView, enabled: Bool) -> Double {
        (row.window.exhausted || !enabled) && !row.expanded ? Tone.exhaustedOpacity : 1
    }




    static func isEnabled(_ row: AccountRowView, in view: ViewState) -> Bool {
        let index = Int(row.index)
        return view.rows.indices.contains(index) ? view.rows[index].enabled : true
    }




    static func pillText(_ view: ViewState, reduceMotion: Bool) -> String {
        reduceMotion ? view.toolbar_status_text + view.busy_suffix_text : view.toolbar_status_text
    }



    enum RowSurface: Equatable, Sendable { case none, hover, raised }

    static func rowSurface(expanded: Bool, hovering: Bool) -> RowSurface {
        if expanded { return .raised }
        return hovering ? .hover : .none
    }



    static func panelRow(_ view: ViewState) -> AccountRowView? {
        guard view.inspector.present else { return nil }
        return rows(view).first { $0.expanded && $0.index == view.inspector.index }
    }



    struct Fact: Equatable, Identifiable, Sendable {
        struct Action: Equatable, Sendable {
            let label: String
            let intent: Intent
        }

        let label: String
        let value: String

        let applies: Bool

        let source: String

        let action: Action?
        var id: String { label }

        init(label: String, value: String, applies: Bool, source: String = "", action: Action? = nil) {
            self.label = label
            self.value = value
            self.applies = applies
            self.source = source
            self.action = action
        }
    }






    static func facts(_ inspector: Inspector, usage: [UsageRow]) -> [Fact] {
        var facts = usage.map { window in
            Fact(label: window.label,
                 value: window.percent_text + Copy.statusSeparator + window.reset_line,
                 applies: true,
                 source: inspector.usage_source_text)
        }
        facts.append(contentsOf: [
            Fact(label: Copy.factStatus, value: inspector.connection_line, applies: true),
            Fact(label: Copy.factFailover, value: inspector.failover_state, applies: inspector.uses_proxy),
            Fact(label: Copy.factLastRefresh, value: inspector.evidence_line, applies: true),
            Fact(label: Copy.factResetCredits, value: inspector.credit_value, applies: inspector.has_credits,
                 action: inspector.can_reset
                    ? Fact.Action(label: inspector.reset_label, intent: .begin_reset(row: inspector.index))
                    : nil),
            Fact(label: Copy.factUpdated, value: inspector.updated_ago_text, applies: true),
        ])
        return facts
    }



    static func noticeIsShown(_ shell: ShellState) -> Bool {
        shell.notice.kind != .none
    }

    static func bannerIsShown(_ view: ViewState) -> Bool {
        !view.proxy_banner_text.isEmpty
    }



    static func bannerShowsRetry(_ view: ViewState) -> Bool {
        view.proxy_sync_state != .needed
    }
}
