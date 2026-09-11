import Foundation







struct Projection: Decodable, Sendable, Equatable {
    let schema: Int
    let generation: UInt64
    let runtime: RuntimeState
    let effects: [Effect]
    let shell: ShellState
    let view: ViewState

    enum CodingKeys: String, CodingKey, CaseIterable { case schema, generation, runtime, effects, shell, view }






    func rendersSame(as other: Projection) -> Bool {
        schema == other.schema && runtime == other.runtime && shell == other.shell && view.rendersSame(as: other.view)
    }
}


struct RuntimeState: Decodable, Sendable, Equatable {
    let started: Bool
    let error: RuntimeStartError?
    let codex_cli_version_exact: Bool
    let claude_cli_version_exact: Bool

    enum CodingKeys: String, CodingKey, CaseIterable { case started, error, codex_cli_version_exact, claude_cli_version_exact }
}


enum Effect: Decodable, Sendable, Equatable {
    case show_settings
    case quit
    case clipboard(text: String)

    var kind: EffectKind {
        switch self {
        case .show_settings: .show_settings
        case .quit: .quit
        case .clipboard: .clipboard
        }
    }

    enum CodingKeys: String, CodingKey, CaseIterable { case kind, text }

    init(from decoder: any Decoder) throws {
        let container = try decoder.container(keyedBy: CodingKeys.self)
        switch try container.decode(EffectKind.self, forKey: .kind) {
        case .show_settings: self = .show_settings
        case .quit: self = .quit
        case .clipboard: self = .clipboard(text: try container.decode(String.self, forKey: .text))
        }
    }
}


struct ShellState: Decodable, Sendable, Equatable {
    let settings_tab: SettingsTab

    let settings_tab_is_meaningful: Bool
    let expanded: UInt32?
    let row_menu: UInt32?
    let proxy_row_menu: UInt32?
    let toolbar_menu_open: Bool
    let proxy_settings_expanded: Bool
    let claude_tray_window: ClaudeTrayWindow
    let footer_text: String
    let claude_summary_weekly_label: String
    let claude_summary_session_label: String



    let starting_text: String
    let quit_label: String
    let can_refresh: Bool
    let can_refresh_all: Bool
    let can_manage_accounts: Bool
    let proxy_busy: Bool
    let proxy_can_refresh: Bool
    let proxy_can_sync: Bool
    let notice: Notice
    let add_account: AddAccountFlow
    let reset: ResetFlow
    let remove: RemoveFlow
    let rename: RenameFlow
    let failover_switch: FailoverSwitchFlow
    let clear_cooldown: ClearCooldownFlow

    enum CodingKeys: String, CodingKey, CaseIterable {
        case settings_tab, settings_tab_is_meaningful
        case expanded, row_menu, proxy_row_menu, toolbar_menu_open, proxy_settings_expanded
        case claude_tray_window, footer_text, claude_summary_weekly_label, claude_summary_session_label
        case starting_text, quit_label
        case can_refresh, can_refresh_all, can_manage_accounts, proxy_busy, proxy_can_refresh, proxy_can_sync
        case notice, add_account, reset, remove, rename, failover_switch, clear_cooldown
    }
}


struct AddAccountFlow: Decodable, Sendable, Equatable {
    let open: Bool
    let title: String
    let explanation_text: String
    let initial_label: String
    let in_flight: Bool
    let confirm_enabled: Bool
    let confirm_label: String
    let cancel_label: String
    let progress_text: String
    let error_text: String

    enum CodingKeys: String, CodingKey, CaseIterable {
        case open, title, explanation_text, initial_label, in_flight, confirm_enabled
        case confirm_label, cancel_label, progress_text, error_text
    }
}


struct Notice: Decodable, Sendable, Equatable {
    let kind: NoticeKind
    let text: String

    enum CodingKeys: String, CodingKey, CaseIterable { case kind, text }
}


struct ResetFlow: Decodable, Sendable, Equatable {
    let open: Bool
    let stage: ResetStage
    let reason: ResetBlockReason
    let outcome: CommandOutcome
    let settle: SettleWatch
    let proxy_clear: ResetProxyClear
    let row: UInt32
    let account_id: String
    let label: String
    let available_count: UInt32
    let usage_text: String
    let reset_text: String
    let blocked_text: String
    let outcome_text: String
    let proxy_clear_text: String
    let is_review: Bool
    let is_armed: Bool
    let is_blocked: Bool
    let is_dispatched: Bool
    let awaits_reconciliation: Bool
    let shows_proxy_clear: Bool

    enum CodingKeys: String, CodingKey, CaseIterable {
        case open, stage, reason, outcome, settle, proxy_clear, row, account_id, label, available_count
        case usage_text, reset_text, blocked_text, outcome_text, proxy_clear_text
        case is_review, is_armed, is_blocked, is_dispatched, awaits_reconciliation, shows_proxy_clear
    }
}


struct RemoveFlow: Decodable, Sendable, Equatable {
    let open: Bool
    let row: UInt32
    let account_id: String
    let label: String
    let uses_proxy: Bool
    let pause_requested: Bool
    let can_finish: Bool

    enum CodingKeys: String, CodingKey, CaseIterable { case open, row, account_id, label, uses_proxy, pause_requested, can_finish }
}


struct RenameFlow: Decodable, Sendable, Equatable {
    let open: Bool
    let row: UInt32
    let account_id: String
    let initial_label: String

    enum CodingKeys: String, CodingKey, CaseIterable { case open, row, account_id, initial_label }
}


struct FailoverSwitchFlow: Decodable, Sendable, Equatable {
    let open: Bool
    let row: UInt32
    let account_id: String
    let target_label: String

    enum CodingKeys: String, CodingKey, CaseIterable { case open, row, account_id, target_label }
}


struct ClearCooldownFlow: Decodable, Sendable, Equatable {
    let open: Bool
    let row: UInt32
    let account_id: String
    let label: String

    enum CodingKeys: String, CodingKey, CaseIterable { case open, row, account_id, label }
}
