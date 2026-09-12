import Foundation






struct ViewState: Decodable, Sendable, Equatable {

    var now_unix_s: Int64
    let capabilities: ServiceCapabilities

    let tray_provider_headers: [String]

    let proxy_base_url: String
    let proxy_cli_path: String
    let proxy_config_path: String
    let proxy_node_path: String
    let proxy_node_resolved: String
    let proxy_reachability: ProxyReachability
    let proxy_work: ProxyWork
    let proxy_sync_state: ProxySyncState
    let proxy_last_attempt_at_unix_s: Int64?
    let proxy_last_attempt_result: ProxyAttemptResult?
    let proxy_last_success_at_unix_s: Int64?
    let proxy_success_revision: UInt64
    let proxy_config_path_matches: Bool
    let proxy_in_flight: UInt32
    let proxy_accounts: [ProxyAccountFact]
    let proxy_rows: [ProxyAccountView]
    let proxy_summary_text: String
    let proxy_detail_text: String
    let proxy_tray_text: String


    let proxy_empty_text: String
    let proxy_service_state: ProxyServiceState
    let proxy_service_detail_text: String
    let proxy_service_can_install: Bool
    let proxy_service_can_repair: Bool
    let proxy_service_can_stop: Bool
    let codex_routing_state: CodexRoutingState
    let proxy_cli_default_path: String
    let proxy_node_default_path: String


    let unified_order_source: UnifiedOrderSource
    let unified_rows: [UnifiedRowView]
    let settings: SettingsView

    let rows: [AccountView]
    let usage_rows: [UsageRow]
    let inspector: Inspector

    let account_row_count: Int

    let claude_row_count: Int
    let codex_exhausted_count: UInt32
    let account_rows: [AccountRowView]
    let claude_group_title: String
    let codex_group_title: String
    let claude_group_summary: String
    let codex_group_summary: String
    let onboarding_visible: Bool
    let onboarding_steps: [OnboardingStepView]
    let onboarding_next_action: OnboardingNextAction?
    let toolbar_status_text: String


    let busy_suffix_text: String
    let header_fresh_text: String
    let header_failed_text: String
    let header_has_failures: Bool
    let proxy_pill_text: String
    let proxy_pill_ok: Bool
    let proxy_pill_warn: Bool
    let proxy_pill_bad: Bool
    let proxy_active_label: String
    let proxy_cooling_count: UInt32
    let proxy_mapped_count: UInt32
    let proxy_settings_summary_text: String
    let proxy_node_hint_text: String
    let proxy_banner_text: String

    let claude_count: UInt32
    let codex_count: UInt32
    let reauth_count: UInt32
    let error_count: UInt32
    let stale_count: UInt32
    let busy_count: UInt32
    let snapshot_count: UInt32
    let newest_success_at_unix_s: Int64?

    let headline_text: String
    let summary_text: String
    let tray_summary_text: String
    let service_text: String

    let tray: Tray

    enum CodingKeys: String, CodingKey, CaseIterable {
        case now_unix_s, capabilities, tray_provider_headers
        case proxy_base_url, proxy_cli_path, proxy_config_path, proxy_node_path, proxy_node_resolved
        case proxy_reachability, proxy_work, proxy_sync_state
        case proxy_last_attempt_at_unix_s, proxy_last_attempt_result, proxy_last_success_at_unix_s
        case proxy_success_revision, proxy_config_path_matches, proxy_in_flight
        case proxy_accounts, proxy_rows, proxy_summary_text, proxy_detail_text, proxy_tray_text, proxy_empty_text
        case proxy_service_state, proxy_service_detail_text
        case proxy_service_can_install, proxy_service_can_repair, proxy_service_can_stop
        case codex_routing_state, proxy_cli_default_path, proxy_node_default_path
        case unified_order_source, unified_rows, settings
        case rows, usage_rows, inspector
        case account_row_count, claude_row_count, codex_exhausted_count, account_rows
        case claude_group_title, codex_group_title, claude_group_summary, codex_group_summary
        case onboarding_visible, onboarding_steps, onboarding_next_action
        case toolbar_status_text, busy_suffix_text, header_fresh_text, header_failed_text, header_has_failures
        case proxy_pill_text, proxy_pill_ok, proxy_pill_warn, proxy_pill_bad
        case proxy_active_label, proxy_cooling_count, proxy_mapped_count
        case proxy_settings_summary_text, proxy_node_hint_text, proxy_banner_text
        case claude_count, codex_count, reauth_count, error_count, stale_count, busy_count, snapshot_count
        case newest_success_at_unix_s
        case headline_text, summary_text, tray_summary_text, service_text
        case tray
    }
}


struct OnboardingStepView: Decodable, Sendable, Equatable {
    let kind: OnboardingStepKind
    let title: String
    let completed: Bool

    enum CodingKeys: String, CodingKey, CaseIterable { case kind, title, completed }
}


struct OnboardingNextAction: Decodable, Sendable, Equatable {
    let kind: OnboardingStepKind
    let label: String
    let enabled: Bool
    let replace_conflicting: Bool

    enum CodingKeys: String, CodingKey, CaseIterable { case kind, label, enabled, replace_conflicting }
}


struct UnifiedRowView: Decodable, Sendable, Equatable {
    let key: UInt32
    let account_index: UInt32
    let proxy_index: UInt32?
    let account_id: String
    let identity_label: String
    let email_local: String
    let email_domain: String
    let has_domain: Bool
    let plan: String
    let has_plan: Bool

    let usage_caption: String
    let usage_percent_text: String
    let usage_bar_fraction: Double
    let usage_exhausted: Bool

    let failover_state: UnifiedFailoverState
    let failover_state_text: String
    let failover_accent: Bool
    let failover_muted: Bool
    let failover_detail_text: String
    let failover_in_flight: UInt32
    let failover_in_flight_text: String

    let expanded: Bool
    let inspector_index: UInt32?
    let account_menu_open: Bool
    let proxy_menu_open: Bool
    let menu_open: Bool

    let action_refresh: Bool
    let action_sign_in: Bool
    let action_sign_in_again: Bool
    let action_busy: Bool
    let busy_label: String
    let can_switch_proxy: Bool
    let switch_label: String
    let can_pause_proxy: Bool
    let can_clear_cooldown: Bool
    let can_reset: Bool
    let reset_label: String

    let can_switch: Bool
    let can_pause: Bool
    let can_resume: Bool
    let can_reload: Bool
    let has_actions: Bool

    enum CodingKeys: String, CodingKey, CaseIterable {
        case key, account_index, proxy_index, account_id, identity_label
        case email_local, email_domain, has_domain, plan, has_plan
        case usage_caption, usage_percent_text, usage_bar_fraction, usage_exhausted
        case failover_state, failover_state_text, failover_accent, failover_muted, failover_detail_text
        case failover_in_flight, failover_in_flight_text
        case expanded, inspector_index, account_menu_open, proxy_menu_open, menu_open
        case action_refresh, action_sign_in, action_sign_in_again, action_busy, busy_label
        case can_switch_proxy, switch_label, can_pause_proxy, can_clear_cooldown, can_reset, reset_label
        case can_switch, can_pause, can_resume, can_reload, has_actions
    }
}


struct SettingsView: Decodable, Sendable, Equatable {
    let appearance: Appearance
    let appearance_label_system: String
    let appearance_label_light: String
    let appearance_label_dark: String

    let codex_section_title: String
    let codex_usage_window: CodexUsageWindow
    let codex_usage_window_supported: [CodexUsageWindow]
    let codex_usage_window_label: String
    let codex_usage_window_detail_text: String
    let codex_show_model_limits: Bool
    let codex_show_model_limits_supported: [Bool]
    let codex_show_model_limits_label: String
    let codex_show_model_limits_detail_text: String

    let language: Language
    let language_supported: [Language]
    let language_label: String
    let language_label_system: String
    let language_label_english: String
    let language_label_korean: String
    let auto_update_state: AutoUpdateState
    let auto_update_detail_text: String
    let app_version_text: String
    let launch_at_login: Bool
    let launch_at_login_registration_failed: Bool
    let auto_refresh_minutes: UInt16
    let auto_refresh_traffic_text: String

    let proxy_service_state: ProxyServiceState
    let proxy_service_detail_text: String
    let proxy_service_can_install: Bool
    let proxy_service_can_repair: Bool
    let proxy_service_can_stop: Bool
    let codex_routing_state: CodexRoutingState
    let proxy_enabled: Bool
    let proxy_enabled_detail_text: String
    let proxy_cli_default_path: String
    let proxy_node_default_path: String

    let proxy_base_url: String
    let proxy_cli_path: String
    let proxy_config_path: String
    let proxy_node_path: String
    let proxy_node_resolved: String
    let proxy_settings_summary_text: String
    let proxy_node_hint_text: String

    enum CodingKeys: String, CodingKey, CaseIterable {
        case appearance, appearance_label_system, appearance_label_light, appearance_label_dark
        case codex_section_title, codex_usage_window, codex_usage_window_supported
        case codex_usage_window_label, codex_usage_window_detail_text
        case codex_show_model_limits, codex_show_model_limits_supported
        case codex_show_model_limits_label, codex_show_model_limits_detail_text
        case language, language_supported, language_label, language_label_system
        case language_label_english, language_label_korean
        case auto_update_state, auto_update_detail_text, app_version_text
        case launch_at_login, launch_at_login_registration_failed, auto_refresh_minutes, auto_refresh_traffic_text
        case proxy_service_state, proxy_service_detail_text
        case proxy_service_can_install, proxy_service_can_repair, proxy_service_can_stop
        case codex_routing_state, proxy_enabled, proxy_enabled_detail_text
        case proxy_cli_default_path, proxy_node_default_path
        case proxy_base_url, proxy_cli_path, proxy_config_path, proxy_node_path, proxy_node_resolved
        case proxy_settings_summary_text, proxy_node_hint_text
    }
}

extension ViewState {

    func rendersSame(as other: ViewState) -> Bool {
        var mine = self
        var theirs = other
        mine.now_unix_s = 0
        theirs.now_unix_s = 0
        return mine == theirs
    }
}


struct ServiceCapabilities: Decodable, Sendable, Equatable {
    let connected: Bool
    let refresh: Bool
    let accounts: Bool
    let reset: Bool
    let proxy_control: Bool

    enum CodingKeys: String, CodingKey, CaseIterable { case connected, refresh, accounts, reset, proxy_control }
}


struct AccountView: Decodable, Sendable, Equatable {
    let account_id: String
    let label: String
    let provider_email: String
    let plan_label: String
    let provider: Provider
    let enabled: Bool
    let auth_state: AuthState
    let freshness: Freshness
    let snapshot_status: SnapshotStatus?
    let has_snapshot: Bool
    let snapshot_captured_at_unix_s: Int64?
    let last_attempt_at_unix_s: Int64?
    let last_success_at_unix_s: Int64?
    let last_attempt_code: String
    let reset_credit_count: UInt32?
    let credit_detail_status: CreditDetailStatus?
    let credit_detail_count: Int
    let operation_in_flight: Bool
    let queued: Bool
    let pending_reset_attempt: Bool
    let unsent_reset_attempt: Bool
    let reset_proxy_clear: ResetProxyClear
    let proxy_mode: Bool
    let proxy_active: Bool
    let proxy_can_switch: Bool
    let proxy_state: ProxyAccountState
    let proxy_in_flight: UInt32
    let proxy_cooldown_until_unix_s: Int64?
    let windows: [WindowView]
    let primary: Int?
    let tray_primary: Int?
    let summary_text: String
    let freshness_text: String
    let evidence_text: String
    let tray_text: String
    let tray_account_text: String
    let tray_identity_text: String
    let tray_detail_text: String
    let tray_open_command: String
    let tray_usage_text: String
    let tray_updated_text: String
    let tray_failover_text: String

    let tray_summary_line: String
    let tray_can_refresh: Bool
    let tray_can_switch: Bool
    let tray_is_active: Bool
    let tray_uses_proxy: Bool
    let needs_attention: Bool
    let reset_is_offerable: Bool

    enum CodingKeys: String, CodingKey, CaseIterable {
        case account_id, label, provider_email, plan_label, provider, enabled, auth_state, freshness
        case snapshot_status, has_snapshot, snapshot_captured_at_unix_s, last_attempt_at_unix_s, last_success_at_unix_s
        case last_attempt_code, reset_credit_count, credit_detail_status, credit_detail_count
        case operation_in_flight, queued, pending_reset_attempt, unsent_reset_attempt, reset_proxy_clear
        case proxy_mode, proxy_active, proxy_can_switch, proxy_state, proxy_in_flight, proxy_cooldown_until_unix_s
        case windows, primary, tray_primary
        case summary_text, freshness_text, evidence_text
        case tray_text, tray_account_text, tray_identity_text, tray_detail_text, tray_open_command
        case tray_usage_text, tray_updated_text, tray_failover_text, tray_summary_line
        case tray_can_refresh, tray_can_switch, tray_is_active, tray_uses_proxy
        case needs_attention, reset_is_offerable
    }
}


struct WindowView: Decodable, Sendable, Equatable {
    let label: String
    let model_label: String
    let kind: UsageWindowKind
    let used_percent: UInt8
    let fraction: Double
    let reset_at_unix_s: Int64?
    let duration_minutes: UInt32?

    enum CodingKeys: String, CodingKey, CaseIterable { case label, model_label, kind, used_percent, fraction, reset_at_unix_s, duration_minutes }
}


struct AccountRowView: Decodable, Sendable, Equatable {
    let key: UInt32

    let index: UInt32
    let provider: Provider
    let is_codex: Bool
    let title: String
    let email_local: String
    let email_domain: String
    let has_domain: Bool
    let identity_primary: String
    let identity_secondary: String
    let has_identity_secondary: Bool
    let plan: String
    let has_plan: Bool
    let status_line: String
    let access_label: String
    let dot_ok: Bool
    let dot_attention: Bool
    let dot_sign_in: Bool
    let dot_failed: Bool
    let dot_busy: Bool
    let chip_a: RowChip
    let chip_b: RowChip
    let window: WindowCell
    let is_cursor: Bool
    let expanded: Bool
    let menu_open: Bool
    let action_refresh: Bool
    let action_sign_in: Bool
    let action_sign_in_again: Bool
    let action_busy: Bool
    let busy_label: String
    let can_switch_proxy: Bool
    let switch_label: String
    let can_pause_proxy: Bool
    let can_clear_cooldown: Bool
    let can_reset: Bool
    let reset_label: String
    let divider_below: Bool

    enum CodingKeys: String, CodingKey, CaseIterable {
        case key, index, provider, is_codex, title, email_local, email_domain, has_domain
        case identity_primary, identity_secondary, has_identity_secondary, plan, has_plan, status_line, access_label
        case dot_ok, dot_attention, dot_sign_in, dot_failed, dot_busy, chip_a, chip_b, window
        case is_cursor, expanded, menu_open, action_refresh, action_sign_in, action_sign_in_again, action_busy, busy_label
        case can_switch_proxy, switch_label, can_pause_proxy, can_clear_cooldown, can_reset, reset_label, divider_below
    }
}


struct RowChip: Decodable, Sendable, Equatable {
    let present: Bool
    let text: String
    let accent: Bool
    let info: Bool
    let warning: Bool
    let destructive: Bool

    enum CodingKeys: String, CodingKey, CaseIterable { case present, text, accent, info, warning, destructive }
}


struct WindowCell: Decodable, Sendable, Equatable {
    let present: Bool
    let label: String
    let percent_text: String
    let fraction: Double
    let exhausted: Bool
    let reset_phrase: String
    let caption: String

    enum CodingKeys: String, CodingKey, CaseIterable { case present, label, percent_text, fraction, exhausted, reset_phrase, caption }
}


struct ProxyAccountFact: Decodable, Sendable, Equatable {
    let app_id: String?

    let storage_key: String?
    let proxy_name: String
    let label: String
    let state: ProxyAccountState
    let cooldown_until_unix_s: Int64?
    let token_expires_at_unix_s: Int64?
    let in_flight: UInt32
    let active: Bool
    let mapped: Bool

    enum CodingKeys: String, CodingKey, CaseIterable {
        case app_id, storage_key, proxy_name, label, state, cooldown_until_unix_s, token_expires_at_unix_s, in_flight, active, mapped
    }
}


struct ProxyAccountView: Decodable, Sendable, Equatable {

    let index: UInt32
    let order_text: String
    let app_id: String
    let label: String
    let label_local: String
    let label_domain: String
    let state: ProxyAccountState
    let in_flight: UInt32
    let state_text: String
    let state_accent: Bool
    let state_ok: Bool
    let state_info: Bool
    let state_neutral: Bool
    let state_destructive: Bool
    let detail_text: String
    let in_flight_text: String
    let active: Bool
    let mapped: Bool
    let can_switch: Bool
    let can_pause: Bool
    let can_resume: Bool

    let can_reload: Bool
    let can_clear_cooldown: Bool
    let has_actions: Bool
    let menu_open: Bool
    let label_muted: Bool
    let divider_below: Bool

    enum CodingKeys: String, CodingKey, CaseIterable {
        case index, order_text, app_id, label, label_local, label_domain, state, in_flight, state_text
        case state_accent, state_ok, state_info, state_neutral, state_destructive, detail_text, in_flight_text
        case active, mapped, can_switch, can_pause, can_resume, can_reload, can_clear_cooldown, has_actions
        case menu_open, label_muted, divider_below
    }
}


struct UsageRow: Decodable, Sendable, Equatable {
    let key: UInt32
    let label: String
    let percent_text: String
    let fraction: Double
    let has_meter: Bool
    let reset_line: String

    enum CodingKeys: String, CodingKey, CaseIterable { case key, label, percent_text, fraction, has_meter, reset_line }
}


struct Inspector: Decodable, Sendable, Equatable {
    let present: Bool
    let index: UInt32
    let title: String
    let freshness_line: String



    let updated_ago_text: String
    let attention: Bool
    let attention_text: String
    let busy: Bool
    let busy_label: String
    let needs_auth: Bool
    let needs_keychain_repair: Bool
    let no_usage_text: String
    let uses_proxy: Bool
    let failover_title: String
    let failover_state: String


    let failover_source_text: String
    let failover_action: String
    let failover_can_switch: Bool

    let usage_source_text: String

    let token_value: String
    let token_source_text: String
    let has_credits: Bool
    let credit_value: String
    let can_reset: Bool
    let reset_label: String
    let credit_note: String
    let has_credit_note: Bool
    let credit_offer: CreditOffer
    let evidence_line: String
    let plan_line: String
    let connection_line: String

    enum CodingKeys: String, CodingKey, CaseIterable {
        case present, index, title, freshness_line, updated_ago_text, attention, attention_text, busy, busy_label
        case needs_auth, needs_keychain_repair, no_usage_text, uses_proxy
        case failover_title, failover_state, failover_source_text, failover_action, failover_can_switch
        case usage_source_text, token_value, token_source_text
        case has_credits, credit_value, can_reset, reset_label, credit_note, has_credit_note, credit_offer
        case evidence_line, plan_line, connection_line
    }
}


struct Tray: Decodable, Sendable, Equatable {
    let title: String
    let items: [TrayItem]


    let refresh_usage_label: String
    let open_in_settings_label: String
    let help_text: String

    enum CodingKeys: String, CodingKey, CaseIterable { case title, items, refresh_usage_label, open_in_settings_label, help_text }
}


struct TrayItem: Decodable, Sendable, Equatable {

    let id: UInt32
    let label: String

    let command: String
    let separator: Bool
    let enabled: Bool

    enum CodingKeys: String, CodingKey, CaseIterable { case id, label, command, separator, enabled }
}
