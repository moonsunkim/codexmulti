import Foundation





enum Intent: Sendable, Equatable {
    case open_details
    case quit_app
    case open_account(account_id: String)
    case tab_accounts
    case tab_failover
    case open_toolbar_menu
    case close_toolbar_menu
    case toggle_account(row: UInt32)
    case move_account(account_id: String, target_account_id: String)
    case open_row_menu(row: UInt32)
    case close_row_menu
    case open_proxy_row_menu(row: UInt32)
    case close_proxy_row_menu
    case toggle_proxy_settings
    case copy_diagnostics(row: UInt32)
    case diagnostics_copied(ok: Bool)
    case claude_tray_weekly
    case claude_tray_session
    case dismiss_notice
    case refresh_proxy_status
    case sync_proxy_config
    case pause_proxy_account(row: UInt32)
    case resume_proxy_account(row: UInt32)
    case begin_proxy_switch(row: UInt32)
    case begin_clear_cooldown(row: UInt32)
    case confirm_clear_cooldown
    case cancel_clear_cooldown
    case save_proxy_settings(base_url: String, cli_path: String, config_path: String, node_path: String)
    case refresh_all
    case refresh_account(row: UInt32)
    case refresh_account_id(account_id: String)
    case begin_failover_switch(row: UInt32)
    case begin_failover_switch_id(account_id: String)
    case confirm_failover_switch
    case cancel_failover_switch
    case pause_failover_account(row: UInt32)
    case begin_clear_cooldown_account(row: UInt32)
    case reauthenticate(row: UInt32)
    case add_claude_account
    case add_codex_account
    case begin_add_account
    case commit_add_account(label: String)
    case cancel_add_account
    case begin_rename(row: UInt32)
    case commit_rename(label: String)
    case cancel_rename
    case begin_remove(row: UInt32)
    case confirm_remove
    case finish_mapped_remove
    case cancel_remove
    case begin_reset(row: UInt32)
    case acknowledge_reset
    case confirm_reset
    case retry_reset
    case cancel_reset
    case install_proxy_service
    case repair_proxy_service
    case stop_proxy_service
    case set_proxy_enabled(on: Bool)
    case enable_codex_routing(replace_conflicting: Bool = false)
    case disable_codex_routing
    case set_appearance(value: Appearance)
    case set_codex_usage_window(value: CodexUsageWindow)
    case set_codex_show_model_limits(on: Bool)
    case set_launch_at_login(on: Bool)
    case report_launch_at_login_registration_failure(failed: Bool)
    case set_auto_refresh(minutes: UInt16)


    var name: String {
        switch self {
        case .open_details: "open_details"
        case .quit_app: "quit_app"
        case .open_account: "open_account"
        case .tab_accounts: "tab_accounts"
        case .tab_failover: "tab_failover"
        case .open_toolbar_menu: "open_toolbar_menu"
        case .close_toolbar_menu: "close_toolbar_menu"
        case .toggle_account: "toggle_account"
        case .move_account: "move_account"
        case .open_row_menu: "open_row_menu"
        case .close_row_menu: "close_row_menu"
        case .open_proxy_row_menu: "open_proxy_row_menu"
        case .close_proxy_row_menu: "close_proxy_row_menu"
        case .toggle_proxy_settings: "toggle_proxy_settings"
        case .copy_diagnostics: "copy_diagnostics"
        case .diagnostics_copied: "diagnostics_copied"
        case .claude_tray_weekly: "claude_tray_weekly"
        case .claude_tray_session: "claude_tray_session"
        case .dismiss_notice: "dismiss_notice"
        case .refresh_proxy_status: "refresh_proxy_status"
        case .sync_proxy_config: "sync_proxy_config"
        case .pause_proxy_account: "pause_proxy_account"
        case .resume_proxy_account: "resume_proxy_account"
        case .begin_proxy_switch: "begin_proxy_switch"
        case .begin_clear_cooldown: "begin_clear_cooldown"
        case .confirm_clear_cooldown: "confirm_clear_cooldown"
        case .cancel_clear_cooldown: "cancel_clear_cooldown"
        case .save_proxy_settings: "save_proxy_settings"
        case .refresh_all: "refresh_all"
        case .refresh_account: "refresh_account"
        case .refresh_account_id: "refresh_account_id"
        case .begin_failover_switch: "begin_failover_switch"
        case .begin_failover_switch_id: "begin_failover_switch_id"
        case .confirm_failover_switch: "confirm_failover_switch"
        case .cancel_failover_switch: "cancel_failover_switch"
        case .pause_failover_account: "pause_failover_account"
        case .begin_clear_cooldown_account: "begin_clear_cooldown_account"
        case .reauthenticate: "reauthenticate"
        case .add_claude_account: "add_claude_account"
        case .add_codex_account: "add_codex_account"
        case .begin_add_account: "begin_add_account"
        case .commit_add_account: "commit_add_account"
        case .cancel_add_account: "cancel_add_account"
        case .begin_rename: "begin_rename"
        case .commit_rename: "commit_rename"
        case .cancel_rename: "cancel_rename"
        case .begin_remove: "begin_remove"
        case .confirm_remove: "confirm_remove"
        case .finish_mapped_remove: "finish_mapped_remove"
        case .cancel_remove: "cancel_remove"
        case .begin_reset: "begin_reset"
        case .acknowledge_reset: "acknowledge_reset"
        case .confirm_reset: "confirm_reset"
        case .retry_reset: "retry_reset"
        case .cancel_reset: "cancel_reset"
        case .install_proxy_service: "install_proxy_service"
        case .repair_proxy_service: "repair_proxy_service"
        case .stop_proxy_service: "stop_proxy_service"
        case .set_proxy_enabled: "set_proxy_enabled"
        case .enable_codex_routing: "enable_codex_routing"
        case .disable_codex_routing: "disable_codex_routing"
        case .set_appearance: "set_appearance"
        case .set_codex_usage_window: "set_codex_usage_window"
        case .set_codex_show_model_limits: "set_codex_show_model_limits"
        case .set_launch_at_login: "set_launch_at_login"
        case .report_launch_at_login_registration_failure: "report_launch_at_login_registration_failure"
        case .set_auto_refresh: "set_auto_refresh"
        }
    }
}

extension Intent: Encodable {

    enum CodingKeys: String, CodingKey, CaseIterable {
        case intent, account_id, row, to, ok, base_url, cli_path, config_path, node_path, label, replace_conflicting
        case value, on, failed, minutes, target_account_id
    }

    func encode(to encoder: any Encoder) throws {
        var container = encoder.container(keyedBy: CodingKeys.self)
        try container.encode(name, forKey: .intent)
        switch self {
        case .open_account(let account_id), .refresh_account_id(let account_id), .begin_failover_switch_id(let account_id):
            try container.encode(account_id, forKey: .account_id)
        case .toggle_account(let row), .open_row_menu(let row), .open_proxy_row_menu(let row), .copy_diagnostics(let row),
             .pause_proxy_account(let row), .resume_proxy_account(let row), .begin_proxy_switch(let row),
             .begin_clear_cooldown(let row), .refresh_account(let row), .begin_failover_switch(let row),
             .pause_failover_account(let row), .begin_clear_cooldown_account(let row), .reauthenticate(let row),
             .begin_rename(let row), .begin_remove(let row), .begin_reset(let row):
            try container.encode(row, forKey: .row)
        case .move_account(let accountID, let targetAccountID):
            try container.encode(accountID, forKey: .account_id)
            try container.encode(targetAccountID, forKey: .target_account_id)
        case .diagnostics_copied(let ok):
            try container.encode(ok, forKey: .ok)
        case .save_proxy_settings(let base_url, let cli_path, let config_path, let node_path):
            try container.encode(base_url, forKey: .base_url)
            try container.encode(cli_path, forKey: .cli_path)
            try container.encode(config_path, forKey: .config_path)
            try container.encode(node_path, forKey: .node_path)
        case .commit_rename(let label), .commit_add_account(let label):
            try container.encode(label, forKey: .label)
        case .enable_codex_routing(let replace_conflicting):
            try container.encode(replace_conflicting, forKey: .replace_conflicting)
        case .set_appearance(let value):
            try container.encode(value, forKey: .value)
        case .set_codex_usage_window(let value):
            try container.encode(value, forKey: .value)
        case .set_proxy_enabled(let on), .set_codex_show_model_limits(let on), .set_launch_at_login(let on):
            try container.encode(on, forKey: .on)
        case .report_launch_at_login_registration_failure(let failed):
            try container.encode(failed, forKey: .failed)
        case .set_auto_refresh(let minutes):
            try container.encode(minutes, forKey: .minutes)
        case .open_details, .quit_app, .tab_accounts, .tab_failover, .open_toolbar_menu, .close_toolbar_menu,
             .close_row_menu, .close_proxy_row_menu, .toggle_proxy_settings, .claude_tray_weekly, .claude_tray_session,
             .dismiss_notice, .refresh_proxy_status, .sync_proxy_config, .confirm_clear_cooldown, .cancel_clear_cooldown,
             .refresh_all, .confirm_failover_switch, .cancel_failover_switch, .add_claude_account, .add_codex_account,
             .begin_add_account, .cancel_add_account,
             .cancel_rename, .confirm_remove, .finish_mapped_remove, .cancel_remove, .acknowledge_reset, .confirm_reset,
             .retry_reset, .cancel_reset, .install_proxy_service, .repair_proxy_service, .stop_proxy_service,
             .disable_codex_routing:
            break
        }
    }
}


enum IntentEncoder {
    static func encode(_ intent: Intent) throws -> Data {
        let encoder = JSONEncoder()
        encoder.outputFormatting = [.sortedKeys, .withoutEscapingSlashes]
        return try encoder.encode(intent)
    }
}
