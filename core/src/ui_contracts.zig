const std = @import("std");
const domain = @import("domain.zig");
const account_registry = @import("account_registry.zig");
const coordinator = @import("coordinator.zig");
const store = @import("store.zig");
const strings = @import("strings.zig");

pub const AuthState = account_registry.AuthState;

pub const Freshness = coordinator.Freshness;
pub const Surface = coordinator.Surface;

pub const ClaudeTrayWindow = enum { weekly, session };

pub const SettingsTab = enum { accounts, failover };

pub const Appearance = store.Appearance;
pub const CodexUsageWindow = store.CodexUsageWindow;
pub const Language = strings.Language;
pub const AutoUpdateState = enum { unavailable };
pub const UnifiedOrderSource = enum { registry };
pub const TimeZone = union(enum) {
    system,
    fixed: Fixed,

    pub const Fixed = struct {
        offset_seconds: i32,
        abbreviation: []const u8,
    };

    pub const utc: TimeZone = .{ .fixed = .{ .offset_seconds = 0, .abbreviation = "UTC" } };
    pub const kst: TimeZone = .{ .fixed = .{ .offset_seconds = 9 * 60 * 60, .abbreviation = "KST" } };
};
pub const UnifiedFailoverState = enum {
    not_mapped,
    active,
    ready,
    cooldown,
    paused,
    invalid,
    refreshing,
    unknown,
};

pub const max_rows: usize = account_registry.max_accounts;
pub const max_windows_per_row: usize = coordinator.max_windows_per_account;

pub const max_tray_items: usize = 32;

pub const max_line_bytes: usize = 192;
pub const names_capacity: usize = 8 * 1024;
pub const text_capacity: usize = 24 * 1024;

pub const max_title_bytes: usize = 64;

pub const tray_fixed_items: usize = 5;

pub const WindowFact = domain.UsageWindow;

pub const AccountFact = struct {
    account_id: []const u8,
    label: []const u8,
    provider_email: ?[]const u8 = null,
    plan_label: ?[]const u8 = null,
    provider: domain.Provider,
    enabled: bool = true,
    auth_state: AuthState = .unavailable,
    freshness: Freshness = .never_refreshed,
    snapshot_status: ?domain.SnapshotStatus = null,
    has_snapshot: bool = false,
    snapshot_captured_at_unix_s: ?i64 = null,
    last_attempt_at_unix_s: ?i64 = null,
    last_success_at_unix_s: ?i64 = null,

    last_attempt_code: ?[]const u8 = null,

    reset_credit_count: ?u32 = null,
    credit_detail_status: ?domain.CreditDetailStatus = null,
    credit_detail_count: usize = 0,
    operation_in_flight: bool = false,
    queued: bool = false,

    pending_reset_attempt: bool = false,

    unsent_reset_attempt: bool = false,

    reset_proxy_clear: ResetProxyClear = .none,
};

pub const ResetProxyClear = enum {
    none,

    pending,

    cleared,

    not_mapped,

    @"unreachable",

    busy,

    failed,
};

pub const ProxyReachability = enum { unknown, reachable, @"unreachable", incompatible };
pub const ProxyAccountState = enum { ready, cooldown, paused, invalid, refreshing, unknown };
pub const ProxyWork = enum { idle, checking, switching, pausing, reloading, clearing_cooldown, importing, applying_config };
pub const ProxySyncState = enum { unknown, needed, synced, failed };
pub const ProxyAttemptResult = enum {
    ok,
    @"unreachable",
    timeout,
    protocol_error,
    incompatible,
    action_failed,
    import_failed,
    mapping_failed,
    config_mismatch,
    persist_failed,

    import_node_missing,
};

pub const ProxyServiceState = enum {
    not_installed,
    installed_stale,
    starting,
    running,
    @"unreachable",
};

pub const CodexRoutingState = enum { off, on, conflicting };

pub const OnboardingStepKind = enum { add_account, install_proxy_service, enable_codex_routing };

pub const OnboardingStepView = struct {
    kind: OnboardingStepKind = .add_account,
    title: []const u8 = "",
    completed: bool = false,
};

pub const OnboardingNextAction = struct {
    kind: OnboardingStepKind = .add_account,
    label: []const u8 = "",
    enabled: bool = false,
    replace_conflicting: bool = false,
};

pub const ProxyServiceFact = struct {
    state: ProxyServiceState = .not_installed,
    detail_text: []const u8 = "Proxy service is not installed",
    can_install: bool = false,
    can_repair: bool = false,
    can_stop: bool = false,
    routing_state: CodexRoutingState = .off,

    enabled: bool = false,
    enabled_detail_text: []const u8 = "Codex routes directly; the failover proxy is off.",
    cli_default_path: []const u8 = "",
    node_default_path: []const u8 = "",
};

pub const ProxySettingsDraft = struct {
    base_url: []const u8,
    cli_path: []const u8,
    config_path: []const u8,

    node_path: []const u8 = "",
};

pub const ProxyAccountFact = struct {
    app_id: ?[]const u8 = null,
    storage_key: ?[]const u8 = null,
    proxy_name: []const u8,
    label: []const u8,
    state: ProxyAccountState,
    cooldown_until_unix_s: ?i64 = null,
    token_expires_at_unix_s: ?i64 = null,
    in_flight: u32 = 0,
    active: bool = false,
    mapped: bool = false,
};

pub const ProxyFact = struct {
    base_url: []const u8,
    cli_path: []const u8,
    config_path: []const u8,

    node_path: []const u8 = "",

    node_resolved: []const u8 = "",
    reachability: ProxyReachability = .unknown,
    work: ProxyWork = .idle,
    sync_state: ProxySyncState = .unknown,
    last_attempt_at_unix_s: ?i64 = null,
    last_attempt_result: ?ProxyAttemptResult = null,
    last_success_at_unix_s: ?i64 = null,

    success_revision: u64 = 0,
    config_path_matches: bool = false,
    in_flight: u32 = 0,
    accounts: []const ProxyAccountFact = &.{},
    token_refresh_failures: []const bool = &.{},
};

pub const ProxyAccountView = struct {
    index: u32 = 0,

    order_text: []const u8 = "",
    app_id: []const u8 = "",
    label: []const u8 = "",

    label_local: []const u8 = "",
    label_domain: []const u8 = "",
    state: ProxyAccountState = .unknown,
    in_flight: u32 = 0,

    state_text: []const u8 = "",
    state_accent: bool = false,
    state_ok: bool = false,
    state_info: bool = false,
    state_neutral: bool = false,
    state_destructive: bool = false,

    detail_text: []const u8 = "",

    in_flight_text: []const u8 = "",
    active: bool = false,
    mapped: bool = false,
    can_switch: bool = false,
    can_pause: bool = false,

    can_resume: bool = false,

    can_reload: bool = false,

    can_clear_cooldown: bool = false,

    has_actions: bool = false,

    menu_open: bool = false,

    label_muted: bool = false,

    divider_below: bool = false,
};

pub const ProxyTableRow = ProxyAccountView;

pub const WindowView = struct {
    label: []const u8 = "",
    model_label: []const u8 = "",
    kind: domain.UsageWindowKind = .other,
    used_percent: u8 = 0,
    fraction: f32 = 0,
    reset_at_unix_s: ?i64 = null,
    duration_minutes: ?u32 = null,
};

pub const AccountView = struct {
    account_id: []const u8 = "",
    label: []const u8 = "",
    provider_email: []const u8 = "",
    plan_label: []const u8 = "",
    provider: domain.Provider = .codex,
    enabled: bool = true,
    auth_state: AuthState = .unavailable,
    freshness: Freshness = .never_refreshed,
    snapshot_status: ?domain.SnapshotStatus = null,
    has_snapshot: bool = false,
    snapshot_captured_at_unix_s: ?i64 = null,
    last_attempt_at_unix_s: ?i64 = null,
    last_success_at_unix_s: ?i64 = null,
    last_attempt_code: []const u8 = "",
    reset_credit_count: ?u32 = null,
    credit_detail_status: ?domain.CreditDetailStatus = null,
    credit_detail_count: usize = 0,
    operation_in_flight: bool = false,
    queued: bool = false,
    pending_reset_attempt: bool = false,
    unsent_reset_attempt: bool = false,
    reset_proxy_clear: ResetProxyClear = .none,

    proxy_mode: bool = false,
    proxy_active: bool = false,
    proxy_can_switch: bool = false,
    proxy_state: ProxyAccountState = .unknown,
    proxy_in_flight: u32 = 0,
    proxy_cooldown_until_unix_s: ?i64 = null,

    window_count: usize = 0,
    windows: [max_windows_per_row]WindowView = @splat(.{}),

    primary: ?usize = null,

    tray_primary: ?usize = null,

    summary_text: []const u8 = "",
    freshness_text: []const u8 = "",
    evidence_text: []const u8 = "",

    tray_identity_text: []const u8 = "",
    tray_detail_text: []const u8 = "",

    tray_text: []const u8 = "",

    tray_account_text: []const u8 = "",
    tray_open_command: []const u8 = "",
    tray_usage_text: []const u8 = "",
    tray_updated_text: []const u8 = "",

    tray_failover_text: []const u8 = "",

    pub fn primaryWindow(self: *const AccountView) ?WindowView {
        const index = self.primary orelse return null;
        return self.windows[index];
    }

    pub fn trayWindow(self: *const AccountView) ?WindowView {
        const index = self.tray_primary orelse return null;
        return self.windows[index];
    }

    pub fn resetIsOfferable(self: *const AccountView) bool {
        if (self.provider != .codex) return false;
        if (self.pending_reset_attempt) return false;
        if (!self.enabled or self.auth_state != .connected) return false;
        const count = self.reset_credit_count orelse return false;
        return count > 0;
    }

    pub fn canRefreshFromTray(self: *const AccountView, capabilities: ServiceCapabilities) bool {
        return capabilities.refresh and self.enabled and self.auth_state == .connected and
            !self.operation_in_flight and !self.queued;
    }

    pub fn canSwitchProxy(self: *const AccountView) bool {
        return self.proxy_mode and self.proxy_can_switch;
    }

    pub fn needsAttention(self: *const AccountView) bool {
        return switch (self.freshness) {
            .reauth_required, .refresh_failed, .usage_unavailable => true,
            else => false,
        };
    }
};

pub const UsageRow = struct {
    key: u32 = 0,
    label: []const u8 = "",
    percent_text: []const u8 = "",
    fraction: f32 = 0,
    has_meter: bool = false,

    reset_line: []const u8 = "",
};

pub const CreditOffer = enum { none, use_one, review };

pub const Inspector = struct {
    present: bool = false,
    index: u32 = 0,

    title: []const u8 = "",

    freshness_line: []const u8 = "",
    attention: bool = false,
    attention_text: []const u8 = "",
    busy: bool = false,
    busy_label: []const u8 = "",
    needs_auth: bool = false,

    needs_keychain_repair: bool = false,

    no_usage_text: []const u8 = "",

    uses_proxy: bool = false,

    failover_title: []const u8 = "",

    failover_state: []const u8 = "",

    failover_source_text: []const u8 = "",
    failover_action: []const u8 = "",
    failover_can_switch: bool = false,

    usage_source_text: []const u8 = "",

    token_value: []const u8 = "",
    token_source_text: []const u8 = "",
    has_credits: bool = false,
    credit_value: []const u8 = "",

    can_reset: bool = false,
    reset_label: []const u8 = "",
    credit_note: []const u8 = "",
    has_credit_note: bool = false,

    credit_offer: CreditOffer = .none,

    evidence_line: []const u8 = "",
    plan_line: []const u8 = "",

    connection_line: []const u8 = "",
};

pub const RowChip = struct {
    present: bool = false,
    text: []const u8 = "",
    accent: bool = false,
    info: bool = false,
    warning: bool = false,
    destructive: bool = false,
};

pub const WindowCell = struct {
    present: bool = false,
    label: []const u8 = "",
    percent_text: []const u8 = "—",
    fraction: f32 = 0,
    exhausted: bool = false,
    reset_phrase: []const u8 = "",

    caption: []const u8 = "",
};

pub const AccountRowView = struct {
    key: u32 = 0,
    index: u32 = 0,
    provider: domain.Provider = .codex,

    title: []const u8 = "",
    email_local: []const u8 = "",

    email_domain: []const u8 = "",
    has_domain: bool = false,

    identity_primary: []const u8 = "",
    identity_secondary: []const u8 = "",
    has_identity_secondary: bool = false,
    plan: []const u8 = "",
    has_plan: bool = false,

    status_line: []const u8 = "",
    access_label: []const u8 = "",
    dot_ok: bool = false,
    dot_attention: bool = false,
    dot_sign_in: bool = false,
    dot_failed: bool = false,
    dot_busy: bool = false,
    chip_a: RowChip = .{},
    chip_b: RowChip = .{},
    window: WindowCell = .{},

    is_cursor: bool = false,
    expanded: bool = false,
    menu_open: bool = false,
    action_refresh: bool = false,
    action_sign_in: bool = false,
    action_sign_in_again: bool = false,
    action_busy: bool = false,
    busy_label: []const u8 = "",
    can_switch_proxy: bool = false,
    switch_label: []const u8 = "",

    can_pause_proxy: bool = false,

    can_clear_cooldown: bool = false,
    can_reset: bool = false,
    reset_label: []const u8 = "",
    is_codex: bool = false,

    divider_below: bool = false,
};

pub const UnifiedRowView = struct {
    key: u32 = 0,
    account_index: u32 = 0,
    proxy_index: ?u32 = null,
    account_id: []const u8 = "",
    identity_label: []const u8 = "",
    email_local: []const u8 = "",
    email_domain: []const u8 = "",
    has_domain: bool = false,
    plan: []const u8 = "",
    has_plan: bool = false,
    usage_caption: []const u8 = "",
    usage_percent_text: []const u8 = "—",
    usage_bar_fraction: f32 = 0,
    usage_exhausted: bool = false,

    failover_state: UnifiedFailoverState = .not_mapped,
    failover_state_text: []const u8 = "Not mapped",
    failover_accent: bool = false,
    failover_muted: bool = true,
    failover_detail_text: []const u8 = "Not mapped to failover",
    failover_in_flight: u32 = 0,
    failover_in_flight_text: []const u8 = "",

    expanded: bool = false,

    inspector_index: ?u32 = null,
    account_menu_open: bool = false,
    proxy_menu_open: bool = false,
    menu_open: bool = false,

    action_refresh: bool = false,
    action_sign_in: bool = false,
    action_sign_in_again: bool = false,
    action_busy: bool = false,
    busy_label: []const u8 = "",
    show_switch: bool = false,
    show_pause: bool = false,
    show_resume: bool = false,
    show_clear_cooldown: bool = false,
    can_switch_proxy: bool = false,
    switch_label: []const u8 = "",
    can_pause_proxy: bool = false,
    can_clear_cooldown: bool = false,
    can_reset: bool = false,
    reset_label: []const u8 = "",

    can_switch: bool = false,
    can_pause: bool = false,
    can_resume: bool = false,
    can_reload: bool = false,
    has_actions: bool = false,
};

pub const SettingsView = struct {
    appearance: Appearance = .system,
    appearance_label_system: []const u8 = "System",
    appearance_label_light: []const u8 = "Light",
    appearance_label_dark: []const u8 = "Dark",
    language: Language = .system,
    language_supported: [strings.supported_languages.len]Language = strings.supported_languages,
    language_label: []const u8 = strings.system.text(.language_label),
    language_label_system: []const u8 = strings.system.text(.language_system),
    language_label_english: []const u8 = strings.system.text(.language_english),
    language_label_korean: []const u8 = strings.system.text(.language_korean),
    language_label_japanese: []const u8 = strings.system.text(.language_japanese),
    language_label_chinese_simplified: []const u8 = strings.system.text(.language_chinese_simplified),
    language_label_spanish: []const u8 = strings.system.text(.language_spanish),
    codex_section_title: []const u8 = "Codex",
    codex_usage_window: CodexUsageWindow = .auto,
    codex_usage_window_supported: [3]CodexUsageWindow = .{ .auto, .weekly, .session },
    codex_usage_window_label: []const u8 = "Usage shown",
    codex_usage_window_detail_text: []const u8 = "Prefer a usage window when the provider reports it.",
    codex_show_model_limits: bool = false,
    codex_show_model_limits_supported: [2]bool = .{ false, true },
    codex_show_model_limits_label: []const u8 = "Per-model limits",
    codex_show_model_limits_detail_text: []const u8 = "Show reported model limits in account details and headlines.",
    auto_update_state: AutoUpdateState = .unavailable,
    auto_update_detail_text: []const u8 = "Automatic updates are unavailable because no update channel is configured.",
    app_version_text: []const u8 = "",
    launch_at_login: bool = false,
    launch_at_login_registration_failed: bool = false,
    auto_refresh_minutes: u16 = 0,
    auto_refresh_traffic_text: []const u8 = "Off — no scheduled provider traffic.",

    proxy_service_state: ProxyServiceState = .not_installed,
    proxy_service_detail_text: []const u8 = "Proxy service is not installed",
    proxy_service_can_install: bool = false,
    proxy_service_can_repair: bool = false,
    proxy_service_can_stop: bool = false,
    codex_routing_state: CodexRoutingState = .off,
    proxy_enabled: bool = false,
    proxy_enabled_detail_text: []const u8 = "Codex routes directly; the failover proxy is off.",
    proxy_cli_default_path: []const u8 = "",
    proxy_node_default_path: []const u8 = "",

    proxy_base_url: []const u8 = "",
    proxy_cli_path: []const u8 = "",
    proxy_config_path: []const u8 = "",
    proxy_node_path: []const u8 = "",
    proxy_node_resolved: []const u8 = "",
    proxy_settings_summary_text: []const u8 = "",
    proxy_node_hint_text: []const u8 = "",
};

pub const TrayItem = struct {
    id: u32 = 0,
    label: []const u8 = "",
    command: []const u8 = "",
    separator: bool = false,
    enabled: bool = true,
};

pub const tray_command_refresh_all = "tray.refresh_all";
pub const tray_command_open_accounts = "tray.open_accounts";
pub const tray_command_open_details = "tray.open_details";
pub const tray_command_quit = "tray.quit";
pub const tray_command_open_account_prefix = "tray.open_account:";
pub const tray_command_refresh_account_prefix = "tray.refresh_account:";
pub const tray_command_switch_failover_prefix = "tray.switch_failover:";

pub const Relabel = struct {
    account_id: []const u8,
    label: []const u8,
};

pub const MoveAccount = struct {
    account_id: []const u8,
    target_account_id: []const u8,
};

pub const RedeemReset = struct {
    account_id: []const u8,
    expected_available_count: u32,
    confirmed_at_unix_s: i64,
    surface: Surface = .details,
};

pub const SetLanguage = struct {
    value: Language,
    system: Language,
};

pub const Command = union(enum) {
    set_appearance: Appearance,
    set_language: SetLanguage,
    set_codex_usage_window: CodexUsageWindow,
    set_codex_show_model_limits: bool,
    set_launch_at_login: bool,

    report_launch_at_login_registration_failure: bool,
    set_auto_refresh: u16,
    refresh_all,
    refresh_account: []const u8,
    add_account: domain.Provider,
    reauthenticate: []const u8,
    relabel: Relabel,
    move_account: MoveAccount,
    remove_account: []const u8,
    redeem_reset: RedeemReset,

    retry_reset: []const u8,
    proxy_refresh_status,
    proxy_switch_account: []const u8,
    proxy_pause_account: []const u8,
    proxy_reload_account: []const u8,

    proxy_clear_cooldown: []const u8,
    proxy_sync_config,
    save_proxy_settings: ProxySettingsDraft,
    install_proxy_service,
    repair_proxy_service,
    stop_proxy_service,
    set_proxy_enabled: bool,
    enable_codex_routing: bool,
    disable_codex_routing,
};

pub const CommandOutcome = enum {
    none,

    accepted_pending,

    service_unavailable,

    provider_cli_missing,

    offer_unavailable,
    rejected_busy,
    rejected_not_allowed,
    rejected_unknown_account,
    failed,

    pub fn accepted(self: CommandOutcome) bool {
        return self == .accepted_pending;
    }
};

pub const ServiceCapabilities = struct {
    connected: bool = false,

    refresh: bool = false,

    accounts: bool = false,

    reset: bool = false,

    proxy_control: bool = false,
};

pub fn ServicePortFor(comptime ViewState: type) type {
    return struct {
        const ServicePort = @This();
        context: ?*anyopaque = null,
        capabilities_fn: ?*const fn (context: *anyopaque) ServiceCapabilities = null,

        project_fn: ?*const fn (context: *anyopaque, view: *ViewState) void = null,
        submit_fn: ?*const fn (context: *anyopaque, command: Command) CommandOutcome = null,

        add_account_labeled_fn: ?*const fn (context: *anyopaque, provider: domain.Provider, label: []const u8) CommandOutcome = null,

        pump_fn: ?*const fn (context: *anyopaque, now_unix_s: i64) void = null,

        pub fn capabilities(self: ServicePort) ServiceCapabilities {
            const context = self.context orelse return .{};
            const call = self.capabilities_fn orelse return .{};
            return call(context);
        }

        pub fn project(self: ServicePort, view: *ViewState, now_unix_s: i64, time_zone: TimeZone, options: RenderOptions) void {
            view.begin(now_unix_s, self.capabilities(), time_zone);
            if (self.context) |context| {
                if (self.project_fn) |call| call(context, view);
            }
            view.finish(options);
        }

        pub fn submit(self: ServicePort, command: Command) CommandOutcome {
            const context = self.context orelse return .service_unavailable;
            const call = self.submit_fn orelse return .service_unavailable;
            return call(context, command);
        }

        pub fn addAccountLabeled(self: ServicePort, provider: domain.Provider, label: []const u8) CommandOutcome {
            const context = self.context orelse return .service_unavailable;
            const call = self.add_account_labeled_fn orelse return .service_unavailable;
            return call(context, provider, label);
        }

        pub fn pump(self: ServicePort, now_unix_s: i64) void {
            const context = self.context orelse return;
            const call = self.pump_fn orelse return;
            call(context, now_unix_s);
        }
    };
}

pub const RenderOptions = struct {
    selected: ?u32 = null,

    row_menu: ?u32 = null,

    proxy_row_menu: ?u32 = null,

    claude_tray_window: ClaudeTrayWindow = .weekly,
};
