const std = @import("std");
const account_registry = @import("account_registry.zig");
pub const shell = @import("shell_model.zig");
pub const ui_model = @import("ui_model.zig");

pub const CM_OK: i32 = 0;
pub const CM_ERR_HANDLE: i32 = 1;
pub const CM_ERR_JSON: i32 = 2;
pub const CM_ERR_SCHEMA: i32 = 3;
pub const CM_ERR_INTENT: i32 = 4;
pub const CM_ERR_PAYLOAD: i32 = 5;
pub const CM_ERR_INTERNAL: i32 = -1;

pub const RuntimeProjection = struct {
    started: bool = false,
    @"error": ?RuntimeError = null,
    codex_cli_version_exact: bool = false,
    claude_cli_version_exact: bool = false,
};

pub const RuntimeError = enum {
    missing_home,
    invalid_root,
    directory_unavailable,
    keychain_unavailable,
    out_of_memory,
};

pub const ParsedIntent = struct {
    parsed: std.json.Parsed(std.json.Value),
    intent: shell.Intent,

    pub fn deinit(self: *ParsedIntent) void {
        self.parsed.deinit();
    }
};

pub const ParseResult = union(enum) {
    accepted: ParsedIntent,
    rejected: i32,
};

fn stringField(object: std.json.ObjectMap, name: []const u8) ?[]const u8 {
    const value = object.get(name) orelse return null;
    return switch (value) {
        .string => |s| s,
        else => null,
    };
}

fn boolField(object: std.json.ObjectMap, name: []const u8) ?bool {
    const value = object.get(name) orelse return null;
    return switch (value) {
        .bool => |b| b,
        else => null,
    };
}

fn positionField(object: std.json.ObjectMap, name: []const u8) ?u32 {
    const value = object.get(name) orelse return null;
    const number = switch (value) {
        .integer => |n| n,
        else => return null,
    };
    if (number < 0 or number >= account_registry.max_accounts) return null;
    return @intCast(number);
}

fn rowField(object: std.json.ObjectMap) ?u32 {
    return positionField(object, "row");
}

fn autoRefreshMinutesField(object: std.json.ObjectMap) ?u16 {
    const value = object.get("minutes") orelse return null;
    const number = switch (value) {
        .integer => |n| n,
        else => return null,
    };
    if (number < 0 or number > std.math.maxInt(u16)) return null;
    const minutes: u16 = @intCast(number);
    if (!@import("store.zig").validAutoRefreshMinutes(minutes)) return null;
    return minutes;
}

fn accountIdField(object: std.json.ObjectMap) ?[]const u8 {
    const value = stringField(object, "account_id") orelse return null;
    account_registry.validateId(value) catch return null;
    return value;
}

pub fn parseIntent(allocator: std.mem.Allocator, bytes: []const u8) ParseResult {
    if (bytes.len > shell.max_intent_json_bytes or !std.unicode.utf8ValidateSlice(bytes)) return .{ .rejected = CM_ERR_JSON };
    var parsed = std.json.parseFromSlice(std.json.Value, allocator, bytes, .{
        .allocate = .alloc_always,
        .duplicate_field_behavior = .@"error",
    }) catch |err| return .{ .rejected = if (err == error.OutOfMemory) CM_ERR_INTERNAL else CM_ERR_JSON };
    var keep_parsed = false;
    defer if (!keep_parsed) parsed.deinit();
    const object = switch (parsed.value) {
        .object => |o| o,
        else => return .{ .rejected = CM_ERR_JSON },
    };

    if (object.get("schema")) |value| {
        const schema = switch (value) {
            .integer => |n| n,
            else => return .{ .rejected = CM_ERR_SCHEMA },
        };
        if (schema != 1) return .{ .rejected = CM_ERR_SCHEMA };
    }
    const name = stringField(object, "intent") orelse return .{ .rejected = CM_ERR_INTENT };

    const tag = std.meta.stringToEnum(std.meta.Tag(shell.Intent), name) orelse
        return .{ .rejected = CM_ERR_INTENT };
    const intent: shell.Intent = switch (tag) {
        .open_details => .open_details,
        .quit_app => .quit_app,
        .tab_accounts => .tab_accounts,
        .tab_failover => .tab_failover,
        .open_toolbar_menu => .open_toolbar_menu,
        .close_toolbar_menu => .close_toolbar_menu,
        .close_row_menu => .close_row_menu,
        .close_proxy_row_menu => .close_proxy_row_menu,
        .toggle_proxy_settings => .toggle_proxy_settings,
        .claude_tray_weekly => .claude_tray_weekly,
        .claude_tray_session => .claude_tray_session,
        .dismiss_notice => .dismiss_notice,
        .refresh_proxy_status => .refresh_proxy_status,
        .sync_proxy_config => .sync_proxy_config,
        .confirm_clear_cooldown => .confirm_clear_cooldown,
        .cancel_clear_cooldown => .cancel_clear_cooldown,
        .refresh_all => .refresh_all,
        .confirm_failover_switch => .confirm_failover_switch,
        .cancel_failover_switch => .cancel_failover_switch,
        .add_claude_account => .add_claude_account,
        .add_codex_account => .add_codex_account,
        .begin_add_account => .begin_add_account,
        .cancel_add_account => .cancel_add_account,
        .cancel_rename => .cancel_rename,
        .confirm_remove => .confirm_remove,
        .finish_mapped_remove => .finish_mapped_remove,
        .cancel_remove => .cancel_remove,
        .acknowledge_reset => .acknowledge_reset,
        .confirm_reset => .confirm_reset,
        .retry_reset => .retry_reset,
        .cancel_reset => .cancel_reset,
        .install_proxy_service => .install_proxy_service,
        .repair_proxy_service => .repair_proxy_service,
        .stop_proxy_service => .stop_proxy_service,
        .disable_codex_routing => .disable_codex_routing,

        .set_appearance => appearance: {
            const value = stringField(object, "value") orelse return .{ .rejected = CM_ERR_PAYLOAD };
            const parsed_appearance = std.meta.stringToEnum(ui_model.Appearance, value) orelse
                return .{ .rejected = CM_ERR_PAYLOAD };
            break :appearance .{ .set_appearance = parsed_appearance };
        },
        .set_language => language: {
            const value = stringField(object, "value") orelse return .{ .rejected = CM_ERR_PAYLOAD };
            const system = stringField(object, "system") orelse return .{ .rejected = CM_ERR_PAYLOAD };
            const parsed_value = std.meta.stringToEnum(ui_model.Language, value) orelse
                return .{ .rejected = CM_ERR_PAYLOAD };
            const parsed_system = std.meta.stringToEnum(ui_model.Language, system) orelse
                return .{ .rejected = CM_ERR_PAYLOAD };
            if (parsed_system == .system) return .{ .rejected = CM_ERR_PAYLOAD };
            break :language .{ .set_language = .{ .value = parsed_value, .system = parsed_system } };
        },
        .set_codex_usage_window => usage_window: {
            const value = stringField(object, "value") orelse return .{ .rejected = CM_ERR_PAYLOAD };
            const parsed_window = std.meta.stringToEnum(ui_model.CodexUsageWindow, value) orelse
                return .{ .rejected = CM_ERR_PAYLOAD };
            break :usage_window .{ .set_codex_usage_window = parsed_window };
        },
        .set_codex_show_model_limits => .{ .set_codex_show_model_limits = boolField(object, "on") orelse return .{ .rejected = CM_ERR_PAYLOAD } },
        .set_launch_at_login => .{ .set_launch_at_login = boolField(object, "on") orelse return .{ .rejected = CM_ERR_PAYLOAD } },
        .report_launch_at_login_registration_failure => .{ .report_launch_at_login_registration_failure = boolField(object, "failed") orelse return .{ .rejected = CM_ERR_PAYLOAD } },
        .set_auto_refresh => .{ .set_auto_refresh = autoRefreshMinutesField(object) orelse return .{ .rejected = CM_ERR_PAYLOAD } },

        .toggle_account => .{ .toggle_account = rowField(object) orelse return .{ .rejected = CM_ERR_PAYLOAD } },
        .open_row_menu => .{ .open_row_menu = rowField(object) orelse return .{ .rejected = CM_ERR_PAYLOAD } },
        .open_proxy_row_menu => .{ .open_proxy_row_menu = rowField(object) orelse return .{ .rejected = CM_ERR_PAYLOAD } },
        .copy_diagnostics => .{ .copy_diagnostics = rowField(object) orelse return .{ .rejected = CM_ERR_PAYLOAD } },
        .pause_proxy_account => .{ .pause_proxy_account = rowField(object) orelse return .{ .rejected = CM_ERR_PAYLOAD } },
        .resume_proxy_account => .{ .resume_proxy_account = rowField(object) orelse return .{ .rejected = CM_ERR_PAYLOAD } },
        .begin_proxy_switch => .{ .begin_proxy_switch = rowField(object) orelse return .{ .rejected = CM_ERR_PAYLOAD } },
        .begin_clear_cooldown => .{ .begin_clear_cooldown = rowField(object) orelse return .{ .rejected = CM_ERR_PAYLOAD } },
        .refresh_account => .{ .refresh_account = rowField(object) orelse return .{ .rejected = CM_ERR_PAYLOAD } },
        .move_account => move: {
            const account_id = accountIdField(object) orelse return .{ .rejected = CM_ERR_PAYLOAD };
            const target_account_id = stringField(object, "target_account_id") orelse return .{ .rejected = CM_ERR_PAYLOAD };
            break :move .{ .move_account = .{ .account_id = account_id, .target_account_id = target_account_id } };
        },
        .begin_failover_switch => .{ .begin_failover_switch = rowField(object) orelse return .{ .rejected = CM_ERR_PAYLOAD } },
        .pause_failover_account => .{ .pause_failover_account = rowField(object) orelse return .{ .rejected = CM_ERR_PAYLOAD } },
        .begin_clear_cooldown_account => .{ .begin_clear_cooldown_account = rowField(object) orelse return .{ .rejected = CM_ERR_PAYLOAD } },
        .reauthenticate => .{ .reauthenticate = rowField(object) orelse return .{ .rejected = CM_ERR_PAYLOAD } },
        .begin_rename => .{ .begin_rename = rowField(object) orelse return .{ .rejected = CM_ERR_PAYLOAD } },
        .begin_remove => .{ .begin_remove = rowField(object) orelse return .{ .rejected = CM_ERR_PAYLOAD } },
        .begin_reset => .{ .begin_reset = rowField(object) orelse return .{ .rejected = CM_ERR_PAYLOAD } },

        .open_account => .{ .open_account = accountIdField(object) orelse return .{ .rejected = CM_ERR_PAYLOAD } },
        .refresh_account_id => .{ .refresh_account_id = accountIdField(object) orelse return .{ .rejected = CM_ERR_PAYLOAD } },
        .begin_failover_switch_id => .{ .begin_failover_switch_id = accountIdField(object) orelse return .{ .rejected = CM_ERR_PAYLOAD } },
        .diagnostics_copied => .{ .diagnostics_copied = boolField(object, "ok") orelse return .{ .rejected = CM_ERR_PAYLOAD } },
        .set_proxy_enabled => .{ .set_proxy_enabled = boolField(object, "on") orelse return .{ .rejected = CM_ERR_PAYLOAD } },
        .enable_codex_routing => routing: {
            const replace = if (object.get("replace_conflicting")) |value| switch (value) {
                .bool => |flag| flag,
                else => return .{ .rejected = CM_ERR_PAYLOAD },
            } else false;
            break :routing .{ .enable_codex_routing = replace };
        },
        .commit_rename => rename: {
            const label = stringField(object, "label") orelse return .{ .rejected = CM_ERR_PAYLOAD };
            account_registry.validateLabel(label) catch return .{ .rejected = CM_ERR_PAYLOAD };
            break :rename .{ .commit_rename = label };
        },
        .commit_add_account => add: {
            const label = stringField(object, "label") orelse return .{ .rejected = CM_ERR_PAYLOAD };
            account_registry.validateLabel(shell.trimmedLabel(label)) catch return .{ .rejected = CM_ERR_PAYLOAD };
            break :add .{ .commit_add_account = label };
        },
        .save_proxy_settings => settings: {
            const base_url = stringField(object, "base_url") orelse return .{ .rejected = CM_ERR_PAYLOAD };
            const cli_path = stringField(object, "cli_path") orelse return .{ .rejected = CM_ERR_PAYLOAD };
            const config_path = stringField(object, "config_path") orelse return .{ .rejected = CM_ERR_PAYLOAD };
            const node_path = stringField(object, "node_path") orelse return .{ .rejected = CM_ERR_PAYLOAD };
            if (base_url.len > 32 or cli_path.len > 512 or config_path.len > 512 or node_path.len > 512) {
                return .{ .rejected = CM_ERR_PAYLOAD };
            }
            break :settings .{ .save_proxy_settings = .{
                .base_url = base_url,
                .cli_path = cli_path,
                .config_path = config_path,
                .node_path = node_path,
            } };
        },
    };
    keep_parsed = true;
    return .{ .accepted = .{ .parsed = parsed, .intent = intent } };
}

pub const EffectWire = union(enum) {
    show_settings: void,
    quit: void,
    clipboard: []const u8,

    pub fn jsonStringify(self: EffectWire, stringify: anytype) !void {
        switch (self) {
            .show_settings => try stringify.write(EffectKindWire{ .kind = "show_settings" }),
            .quit => try stringify.write(EffectKindWire{ .kind = "quit" }),
            .clipboard => |text| try stringify.write(EffectClipboardWire{ .kind = "clipboard", .text = text }),
        }
    }

    pub fn jsonParse(allocator_: std.mem.Allocator, source: anytype, options: std.json.ParseOptions) !EffectWire {
        const value = try std.json.Value.jsonParse(allocator_, source, options);
        if (value != .object) return error.UnexpectedToken;
        const kind_value = value.object.get("kind") orelse return error.MissingField;
        if (kind_value != .string) return error.UnexpectedToken;
        if (std.mem.eql(u8, kind_value.string, "show_settings")) return .{ .show_settings = {} };
        if (std.mem.eql(u8, kind_value.string, "quit")) return .{ .quit = {} };
        if (std.mem.eql(u8, kind_value.string, "clipboard")) {
            const text_value = value.object.get("text") orelse return error.MissingField;
            if (text_value != .string) return error.UnexpectedToken;
            return .{ .clipboard = text_value.string };
        }
        return error.UnknownField;
    }
};
const EffectKindWire = struct { kind: []const u8 };
const EffectClipboardWire = struct { kind: []const u8, text: []const u8 };

pub const AccountWire = struct {
    account_id: @FieldType(ui_model.AccountView, "account_id"),
    label: @FieldType(ui_model.AccountView, "label"),
    provider_email: @FieldType(ui_model.AccountView, "provider_email"),
    plan_label: @FieldType(ui_model.AccountView, "plan_label"),
    provider: @FieldType(ui_model.AccountView, "provider"),
    enabled: bool,
    auth_state: @FieldType(ui_model.AccountView, "auth_state"),
    freshness: @FieldType(ui_model.AccountView, "freshness"),
    snapshot_status: @FieldType(ui_model.AccountView, "snapshot_status"),
    has_snapshot: bool,
    snapshot_captured_at_unix_s: ?i64,
    last_attempt_at_unix_s: ?i64,
    last_success_at_unix_s: ?i64,
    last_attempt_code: []const u8,
    reset_credit_count: ?u32,
    credit_detail_status: @FieldType(ui_model.AccountView, "credit_detail_status"),
    credit_detail_count: usize,
    operation_in_flight: bool,
    queued: bool,
    pending_reset_attempt: bool,
    unsent_reset_attempt: bool,
    reset_proxy_clear: @FieldType(ui_model.AccountView, "reset_proxy_clear"),
    proxy_mode: bool,
    proxy_active: bool,
    proxy_can_switch: bool,
    proxy_state: @FieldType(ui_model.AccountView, "proxy_state"),
    proxy_in_flight: u32,
    proxy_cooldown_until_unix_s: ?i64,
    windows: []const ui_model.WindowView,
    primary: ?usize,
    tray_primary: ?usize,
    summary_text: []const u8,
    freshness_text: []const u8,
    evidence_text: []const u8,
    tray_text: []const u8,
    tray_account_text: []const u8,
    tray_identity_text: []const u8,
    tray_detail_text: []const u8,
    tray_open_command: []const u8,
    tray_usage_text: []const u8,
    tray_updated_text: []const u8,
    tray_failover_text: []const u8,
    tray_summary_line: []const u8,
    tray_can_refresh: bool,
    tray_can_switch: bool,
    tray_is_active: bool,
    tray_uses_proxy: bool,
    needs_attention: bool,
    reset_is_offerable: bool,
};

pub const NoticeWire = struct { kind: ui_model.NoticeKind, text: []const u8 };
pub const AddAccountWire = struct {
    open: bool,
    title: []const u8,
    explanation_text: []const u8,
    initial_label: []const u8,
    in_flight: bool,
    confirm_enabled: bool,
    confirm_label: []const u8,
    cancel_label: []const u8,
    progress_text: []const u8,
    error_text: []const u8,
};
pub const ResetWire = struct {
    open: bool,
    stage: ui_model.ResetStage,
    reason: ui_model.ResetBlockReason,
    outcome: ui_model.CommandOutcome,
    settle: @FieldType(ui_model.ResetFlow, "settle"),
    proxy_clear: ui_model.ResetProxyClear,
    row: u32,
    account_id: []const u8,
    label: []const u8,
    available_count: u32,
    usage_text: []const u8,
    reset_text: []const u8,
    blocked_text: []const u8,
    outcome_text: []const u8,
    proxy_clear_text: []const u8,
    is_review: bool,
    is_armed: bool,
    is_blocked: bool,
    is_dispatched: bool,
    awaits_reconciliation: bool,
    shows_proxy_clear: bool,
};
pub const RemoveWire = struct { open: bool, row: u32, account_id: []const u8, label: []const u8, uses_proxy: bool, pause_requested: bool, can_finish: bool };
pub const RenameWire = struct { open: bool, row: u32, account_id: []const u8, initial_label: []const u8 };
pub const FailoverSwitchWire = struct { open: bool, row: u32, account_id: []const u8, target_label: []const u8 };
pub const ClearCooldownWire = struct { open: bool, row: u32, account_id: []const u8, label: []const u8 };
pub const InspectorWire = struct {
    present: bool,
    index: u32,
    title: []const u8,
    freshness_line: []const u8,
    updated_ago_text: []const u8,
    attention: bool,
    attention_text: []const u8,
    busy: bool,
    busy_label: []const u8,
    needs_auth: bool,
    needs_keychain_repair: bool,
    no_usage_text: []const u8,
    uses_proxy: bool,
    failover_title: []const u8,
    failover_state: []const u8,
    failover_source_text: []const u8,
    failover_action: []const u8,
    failover_can_switch: bool,
    usage_source_text: []const u8,
    token_value: []const u8,
    token_source_text: []const u8,
    has_credits: bool,
    credit_value: []const u8,
    can_reset: bool,
    reset_label: []const u8,
    credit_note: []const u8,
    has_credit_note: bool,
    credit_offer: ui_model.CreditOffer,
    evidence_line: []const u8,
    plan_line: []const u8,
    connection_line: []const u8,
};
pub const ShellWire = struct {
    settings_tab: ui_model.SettingsTab,
    settings_tab_is_meaningful: bool,
    expanded: ?u32,
    row_menu: ?u32,
    proxy_row_menu: ?u32,
    toolbar_menu_open: bool,
    proxy_settings_expanded: bool,
    claude_tray_window: ui_model.ClaudeTrayWindow,
    footer_text: []const u8,
    claude_summary_weekly_label: []const u8,
    claude_summary_session_label: []const u8,
    starting_text: []const u8,
    quit_label: []const u8,
    can_refresh: bool,
    can_refresh_all: bool,
    can_manage_accounts: bool,
    proxy_busy: bool,
    proxy_can_refresh: bool,
    proxy_can_sync: bool,
    notice: NoticeWire,
    add_account: AddAccountWire,
    reset: ResetWire,
    remove: RemoveWire,
    rename: RenameWire,
    failover_switch: FailoverSwitchWire,
    clear_cooldown: ClearCooldownWire,
};

pub const TrayWire = struct {
    title: []const u8,
    items: []const ui_model.TrayItem,
    refresh_usage_label: []const u8,
    open_in_settings_label: []const u8,
    help_text: []const u8,
};
pub const ViewWire = struct {
    now_unix_s: i64,
    capabilities: ui_model.ServiceCapabilities,
    tray_provider_headers: [2][]const u8,
    proxy_base_url: []const u8,
    proxy_cli_path: []const u8,
    proxy_config_path: []const u8,
    proxy_node_path: []const u8,
    proxy_node_resolved: []const u8,
    proxy_reachability: ui_model.ProxyReachability,
    proxy_work: ui_model.ProxyWork,
    proxy_sync_state: ui_model.ProxySyncState,
    proxy_last_attempt_at_unix_s: ?i64,
    proxy_last_attempt_result: ?ui_model.ProxyAttemptResult,
    proxy_last_success_at_unix_s: ?i64,
    proxy_success_revision: u64,
    proxy_config_path_matches: bool,
    proxy_in_flight: u32,
    proxy_accounts: []const ui_model.ProxyAccountFact,
    proxy_rows: []const ui_model.ProxyTableRow,
    proxy_summary_text: []const u8,
    proxy_detail_text: []const u8,
    proxy_tray_text: []const u8,
    proxy_empty_text: []const u8,
    proxy_service_state: ui_model.ProxyServiceState,
    proxy_service_detail_text: []const u8,
    proxy_service_can_install: bool,
    proxy_service_can_repair: bool,
    proxy_service_can_stop: bool,
    codex_routing_state: ui_model.CodexRoutingState,
    proxy_cli_default_path: []const u8,
    proxy_node_default_path: []const u8,
    rows: []const AccountWire,
    usage_rows: []const ui_model.UsageRow,
    inspector: InspectorWire,
    account_row_count: usize,
    claude_row_count: usize,
    codex_exhausted_count: u32,
    account_rows: []const ui_model.AccountRowView,
    unified_order_source: ui_model.UnifiedOrderSource,
    unified_rows: []const ui_model.UnifiedRowView,
    settings: ui_model.SettingsView,
    claude_group_title: []const u8,
    codex_group_title: []const u8,
    claude_group_summary: []const u8,
    codex_group_summary: []const u8,
    onboarding_visible: bool,
    onboarding_steps: [3]ui_model.OnboardingStepView,
    onboarding_next_action: ?ui_model.OnboardingNextAction,
    toolbar_status_text: []const u8,
    busy_suffix_text: []const u8,
    header_fresh_text: []const u8,
    header_failed_text: []const u8,
    header_has_failures: bool,
    proxy_pill_text: []const u8,
    proxy_pill_ok: bool,
    proxy_pill_warn: bool,
    proxy_pill_bad: bool,
    proxy_active_label: []const u8,
    proxy_cooling_count: u32,
    proxy_mapped_count: u32,
    proxy_settings_summary_text: []const u8,
    proxy_node_hint_text: []const u8,
    proxy_banner_text: []const u8,
    claude_count: u32,
    codex_count: u32,
    reauth_count: u32,
    error_count: u32,
    stale_count: u32,
    busy_count: u32,
    snapshot_count: u32,
    newest_success_at_unix_s: ?i64,
    headline_text: []const u8,
    summary_text: []const u8,
    tray_summary_text: []const u8,
    service_text: []const u8,
    tray: TrayWire,
};
pub const ProjectionWire = struct { schema: u32, generation: u64, runtime: RuntimeProjection, effects: []const EffectWire, shell: ShellWire, view: ViewWire };

const EffectJson = struct {
    value: *const shell.Effect,
    pub fn jsonStringify(self: EffectJson, stringify: anytype) !void {
        switch (self.value.kind) {
            .show_settings => try stringify.write(EffectWire{ .show_settings = {} }),
            .quit => try stringify.write(EffectWire{ .quit = {} }),
            .clipboard => try stringify.write(EffectWire{ .clipboard = self.value.text() }),
        }
    }
};

pub fn accountToWire(a: *const ui_model.AccountView, capabilities: ui_model.ServiceCapabilities, tray_summary_line: []const u8) AccountWire {
    return AccountWire{
        .account_id = a.account_id,
        .label = a.label,
        .provider_email = a.provider_email,
        .plan_label = a.plan_label,
        .provider = a.provider,
        .enabled = a.enabled,
        .auth_state = a.auth_state,
        .freshness = a.freshness,
        .snapshot_status = a.snapshot_status,
        .has_snapshot = a.has_snapshot,
        .snapshot_captured_at_unix_s = a.snapshot_captured_at_unix_s,
        .last_attempt_at_unix_s = a.last_attempt_at_unix_s,
        .last_success_at_unix_s = a.last_success_at_unix_s,
        .last_attempt_code = a.last_attempt_code,
        .reset_credit_count = a.reset_credit_count,
        .credit_detail_status = a.credit_detail_status,
        .credit_detail_count = a.credit_detail_count,
        .operation_in_flight = a.operation_in_flight,
        .queued = a.queued,
        .pending_reset_attempt = a.pending_reset_attempt,
        .unsent_reset_attempt = a.unsent_reset_attempt,
        .reset_proxy_clear = a.reset_proxy_clear,
        .proxy_mode = a.proxy_mode,
        .proxy_active = a.proxy_active,
        .proxy_can_switch = a.proxy_can_switch,
        .proxy_state = a.proxy_state,
        .proxy_in_flight = a.proxy_in_flight,
        .proxy_cooldown_until_unix_s = a.proxy_cooldown_until_unix_s,
        .windows = a.windows[0..a.window_count],
        .primary = a.primary,
        .tray_primary = a.tray_primary,
        .summary_text = a.summary_text,
        .freshness_text = a.freshness_text,
        .evidence_text = a.evidence_text,
        .tray_text = a.tray_text,
        .tray_account_text = a.tray_account_text,
        .tray_identity_text = a.tray_identity_text,
        .tray_detail_text = a.tray_detail_text,
        .tray_open_command = a.tray_open_command,
        .tray_usage_text = a.tray_usage_text,
        .tray_updated_text = a.tray_updated_text,
        .tray_failover_text = a.tray_failover_text,
        .tray_summary_line = tray_summary_line,
        .tray_can_refresh = a.canRefreshFromTray(capabilities),
        .tray_can_switch = a.canSwitchProxy(),
        .tray_is_active = a.proxy_mode and a.proxy_active,
        .tray_uses_proxy = a.proxy_mode,
        .needs_attention = a.needsAttention(),
        .reset_is_offerable = a.resetIsOfferable(),
    };
}

pub fn shellToWire(m: *const shell.Model) ShellWire {
    const r = &m.reset;
    const copy = @import("strings.zig").catalog(m.view.resolved_language);
    return ShellWire{
        .settings_tab = m.settings_tab,
        .settings_tab_is_meaningful = false,
        .expanded = m.expanded,
        .row_menu = m.row_menu,
        .proxy_row_menu = m.proxy_row_menu,
        .toolbar_menu_open = m.toolbar_menu_open,
        .proxy_settings_expanded = m.proxy_settings_expanded,
        .claude_tray_window = m.claude_tray_window,
        .footer_text = m.footerText(),

        .claude_summary_weekly_label = "",
        .claude_summary_session_label = "",
        .starting_text = copy.translateEnglish(shell.starting_text),
        .quit_label = copy.translateEnglish(shell.quit_label),
        .can_refresh = m.view.capabilities.refresh,
        .can_refresh_all = m.view.row_count != 0 and m.view.capabilities.refresh,
        .can_manage_accounts = m.view.capabilities.accounts,
        .proxy_busy = m.proxyBusy(),
        .proxy_can_refresh = m.proxyCanRefresh(),
        .proxy_can_sync = m.proxyCanSync(),
        .notice = NoticeWire{ .kind = m.notice.kind, .text = m.notice.text() },
        .add_account = AddAccountWire{
            .open = m.add_account.open,
            .title = copy.translateEnglish(shell.add_account_title),
            .explanation_text = copy.translateEnglish(shell.add_account_explanation_text),
            .initial_label = m.add_account.initialLabel(),
            .in_flight = m.add_account.in_flight,
            .confirm_enabled = m.add_account.confirmEnabled(),
            .confirm_label = copy.translateEnglish(shell.add_account_confirm_label),
            .cancel_label = copy.translateEnglish(shell.add_account_cancel_label),
            .progress_text = copy.translateEnglish(m.addAccountProgressText()),
            .error_text = copy.translateEnglish(m.add_account.errorText()),
        },
        .reset = ResetWire{
            .open = r.isOpen(),
            .stage = r.stage,
            .reason = r.reason,
            .outcome = r.outcome,
            .settle = r.settle,
            .proxy_clear = r.proxy_clear,
            .row = r.row,
            .account_id = r.accountId(),
            .label = r.label(),
            .available_count = r.available_count,
            .usage_text = r.usageEvidence(),
            .reset_text = r.resetEvidence(),
            .blocked_text = copy.translateEnglish(r.blockedText()),
            .outcome_text = copy.translateEnglish(r.outcomeText()),
            .proxy_clear_text = copy.translateEnglish(r.proxyClearText()),
            .is_review = r.stage == .review,
            .is_armed = r.stage == .armed,
            .is_blocked = r.stage == .blocked,
            .is_dispatched = r.stage == .dispatched,
            .awaits_reconciliation = r.awaitsReconciliation(),
            .shows_proxy_clear = r.showsProxyClear(),
        },
        .remove = RemoveWire{
            .open = m.remove.open,
            .row = m.remove.row,
            .account_id = m.remove.accountId(),
            .label = m.remove.label(),
            .uses_proxy = m.remove.uses_proxy,
            .pause_requested = m.remove.pause_requested,
            .can_finish = m.removeCanFinish(),
        },
        .rename = RenameWire{
            .open = m.rename.open,
            .row = m.rename.row,
            .account_id = m.rename.accountId(),
            .initial_label = m.rename.initialLabel(),
        },
        .failover_switch = FailoverSwitchWire{
            .open = m.failover_switch.open,
            .row = m.failover_switch.row,
            .account_id = m.failover_switch.accountId(),
            .target_label = m.failover_switch.targetLabel(),
        },
        .clear_cooldown = ClearCooldownWire{
            .open = m.clear_cooldown.open,
            .row = m.clear_cooldown.row,
            .account_id = m.clear_cooldown.accountId(),
            .label = m.clear_cooldown.label(),
        },
    };
}

const ShellJson = struct {
    model: *const shell.Model,
    pub fn jsonStringify(self: ShellJson, stringify: anytype) !void {
        try stringify.write(shellToWire(self.model));
    }
};

pub fn inspectorToWire(i: *const ui_model.Inspector, updated_ago_text: []const u8) InspectorWire {
    return .{
        .present = i.present,
        .index = i.index,
        .title = i.title,
        .freshness_line = i.freshness_line,
        .updated_ago_text = updated_ago_text,
        .attention = i.attention,
        .attention_text = i.attention_text,
        .busy = i.busy,
        .busy_label = i.busy_label,
        .needs_auth = i.needs_auth,
        .needs_keychain_repair = i.needs_keychain_repair,
        .no_usage_text = i.no_usage_text,
        .uses_proxy = i.uses_proxy,
        .failover_title = i.failover_title,
        .failover_state = i.failover_state,
        .failover_source_text = i.failover_source_text,
        .failover_action = i.failover_action,
        .failover_can_switch = i.failover_can_switch,
        .usage_source_text = i.usage_source_text,
        .token_value = i.token_value,
        .token_source_text = i.token_source_text,
        .has_credits = i.has_credits,
        .credit_value = i.credit_value,
        .can_reset = i.can_reset,
        .reset_label = i.reset_label,
        .credit_note = i.credit_note,
        .has_credit_note = i.has_credit_note,
        .credit_offer = i.credit_offer,
        .evidence_line = i.evidence_line,
        .plan_line = i.plan_line,
        .connection_line = i.connection_line,
    };
}

pub fn viewToWire(
    v: *const ui_model.ViewState,
    accounts: []const AccountWire,
    tray_items: []const ui_model.TrayItem,
    inspector_updated_ago_text: []const u8,
) ViewWire {
    return ViewWire{
        .now_unix_s = v.now_unix_s,
        .capabilities = v.capabilities,
        .tray_provider_headers = v.tray_provider_headers,
        .proxy_base_url = v.proxy_base_url,
        .proxy_cli_path = v.proxy_cli_path,
        .proxy_config_path = v.proxy_config_path,
        .proxy_node_path = v.proxy_node_path,
        .proxy_node_resolved = v.proxy_node_resolved,
        .proxy_reachability = v.proxy_reachability,
        .proxy_work = v.proxy_work,
        .proxy_sync_state = v.proxy_sync_state,
        .proxy_last_attempt_at_unix_s = v.proxy_last_attempt_at_unix_s,
        .proxy_last_attempt_result = v.proxy_last_attempt_result,
        .proxy_last_success_at_unix_s = v.proxy_last_success_at_unix_s,
        .proxy_success_revision = v.proxy_success_revision,
        .proxy_config_path_matches = v.proxy_config_path_matches,
        .proxy_in_flight = v.proxy_in_flight,
        .proxy_accounts = v.proxy_accounts[0..v.proxy_account_count],
        .proxy_rows = v.proxy_rows[0..v.proxy_row_count],
        .proxy_summary_text = v.proxy_summary_text,
        .proxy_detail_text = v.proxy_detail_text,
        .proxy_tray_text = v.proxy_tray_text,
        .proxy_empty_text = shell.proxyEmptyText(v),
        .proxy_service_state = v.proxy_service_state,
        .proxy_service_detail_text = v.proxy_service_detail_text,
        .proxy_service_can_install = v.proxy_service_can_install,
        .proxy_service_can_repair = v.proxy_service_can_repair,
        .proxy_service_can_stop = v.proxy_service_can_stop,
        .codex_routing_state = v.codex_routing_state,
        .proxy_cli_default_path = v.proxy_cli_default_path,
        .proxy_node_default_path = v.proxy_node_default_path,
        .rows = accounts,
        .usage_rows = v.usage_rows[0..v.usage_count],
        .inspector = inspectorToWire(&v.inspector, inspector_updated_ago_text),
        .account_row_count = v.account_row_count,
        .claude_row_count = v.claude_row_count,
        .codex_exhausted_count = v.codex_exhausted_count,
        .account_rows = v.account_rows[0..v.account_row_count],
        .unified_order_source = v.unified_order_source,
        .unified_rows = v.unified_rows[0..v.unified_row_count],
        .settings = v.settings,
        .claude_group_title = v.claude_group_title,
        .codex_group_title = v.codex_group_title,
        .claude_group_summary = v.claude_group_summary,
        .codex_group_summary = v.codex_group_summary,
        .onboarding_visible = v.onboarding_visible,
        .onboarding_steps = v.onboarding_steps,
        .onboarding_next_action = v.onboarding_next_action,
        .toolbar_status_text = v.toolbar_status_text,
        .busy_suffix_text = shell.busySuffixText(v),
        .header_fresh_text = v.header_fresh_text,
        .header_failed_text = v.header_failed_text,
        .header_has_failures = v.header_has_failures,
        .proxy_pill_text = v.proxy_pill_text,
        .proxy_pill_ok = v.proxy_pill_ok,
        .proxy_pill_warn = v.proxy_pill_warn,
        .proxy_pill_bad = v.proxy_pill_bad,
        .proxy_active_label = v.proxy_active_label,
        .proxy_cooling_count = v.proxy_cooling_count,
        .proxy_mapped_count = v.proxy_mapped_count,
        .proxy_settings_summary_text = v.proxy_settings_summary_text,
        .proxy_node_hint_text = v.proxy_node_hint_text,
        .proxy_banner_text = v.proxy_banner_text,
        .claude_count = v.claude_count,
        .codex_count = v.codex_count,
        .reauth_count = v.reauth_count,
        .error_count = v.error_count,
        .stale_count = v.stale_count,
        .busy_count = v.busy_count,
        .snapshot_count = v.snapshot_count,
        .newest_success_at_unix_s = v.newest_success_at_unix_s,
        .headline_text = v.headline_text,
        .summary_text = v.summary_text,
        .tray_summary_text = v.tray_summary_text,
        .service_text = v.service_text,
        .tray = TrayWire{
            .title = "",
            .items = tray_items,
            .refresh_usage_label = shell.tray_refresh_usage_label,
            .open_in_settings_label = shell.tray_open_in_settings_label,
            .help_text = shell.tray_help_text,
        },
    };
}

const ViewJson = struct {
    view: *const ui_model.ViewState,
    accounts: []const AccountWire,
    tray_items: []const ui_model.TrayItem,
    inspector_updated_ago_text: []const u8,

    pub fn jsonStringify(self: ViewJson, stringify: anytype) !void {
        try stringify.write(viewToWire(self.view, self.accounts, self.tray_items, self.inspector_updated_ago_text));
    }
};

const ProjectionJson = struct {
    generation: u64,
    runtime: RuntimeProjection,
    effects: []const EffectJson,
    shell_model: *const shell.Model,
    view: ViewJson,

    pub fn jsonStringify(self: ProjectionJson, stringify: anytype) !void {
        try stringify.beginObject();
        try stringify.objectField("schema");
        try stringify.write(@as(u32, 1));
        try stringify.objectField("generation");
        try stringify.write(self.generation);
        try stringify.objectField("runtime");
        try stringify.write(self.runtime);
        try stringify.objectField("effects");
        try stringify.write(self.effects);
        try stringify.objectField("shell");
        try stringify.write(ShellJson{ .model = self.shell_model });
        try stringify.objectField("view");
        try stringify.write(self.view);
        try stringify.endObject();
    }
};

pub fn serialize(
    allocator: std.mem.Allocator,
    generation: u64,
    runtime: RuntimeProjection,
    model: *const shell.Model,
    effects: *const shell.Effects,
) error{OutOfMemory}![]u8 {
    var account_wrappers: [ui_model.max_rows]AccountWire = undefined;
    var tray_summary_buffers: [ui_model.max_rows][ui_model.max_line_bytes]u8 = undefined;
    for (model.view.rows[0..model.view.row_count], 0..) |*row, index| {
        account_wrappers[index] = accountToWire(
            row,
            model.view.capabilities,
            shell.traySummaryLine(row, &tray_summary_buffers[index]),
        );
    }
    var inspector_updated_ago_buffer: [ui_model.max_line_bytes]u8 = undefined;
    const inspector_updated_ago_text = shell.inspectorUpdatedAgoText(&model.view, &inspector_updated_ago_buffer);
    var effect_wrappers: [shell.max_effects]EffectJson = undefined;
    for (effects.slice(), 0..) |*effect, index| effect_wrappers[index] = .{ .value = effect };
    var tray_items: [ui_model.max_tray_items]ui_model.TrayItem = @splat(.{});
    const tray_count = ui_model.buildTray(&model.view, &tray_items);
    return std.json.Stringify.valueAlloc(allocator, ProjectionJson{
        .generation = generation,
        .runtime = runtime,
        .effects = effect_wrappers[0..effects.len],
        .shell_model = model,
        .view = .{
            .view = &model.view,
            .accounts = account_wrappers[0..model.view.row_count],
            .tray_items = tray_items[0..tray_count],
            .inspector_updated_ago_text = inspector_updated_ago_text,
        },
    }, .{ .emit_null_optional_fields = true });
}

pub fn minimalSerializeError(allocator: std.mem.Allocator, generation: u64, name: []const u8) error{OutOfMemory}![]u8 {
    return std.json.Stringify.valueAlloc(allocator, .{ .schema = @as(u32, 1), .generation = generation, .serialize_error = name }, .{});
}

fn fieldListed(comptime name: []const u8, comptime names: []const []const u8) bool {
    inline for (names) |candidate| if (std.mem.eql(u8, name, candidate)) return true;
    return false;
}

fn assertFieldsCovered(comptime T: type, comptime names: []const []const u8, comptime exempt: []const []const u8) void {
    inline for (@typeInfo(T).@"struct".fields) |field| {
        if (!fieldListed(field.name, names) and !fieldListed(field.name, exempt)) {
            @compileError("bridge serializer omits " ++ @typeName(T) ++ "." ++ field.name);
        }
    }
}

fn assertSourceFieldsBackedByWire(comptime Source: type, comptime Wire: type, comptime exempt: []const []const u8) void {
    inline for (@typeInfo(Source).@"struct".fields) |field| {
        if (!@hasField(Wire, field.name) and !fieldListed(field.name, exempt)) {
            @compileError("actual bridge wire type " ++ @typeName(Wire) ++ " omits " ++ @typeName(Source) ++ "." ++ field.name);
        }
    }
}

fn assertDirectStruct(comptime T: type) void {
    inline for (@typeInfo(T).@"struct".fields) |field| {
        if (std.mem.endsWith(u8, field.name, "_len") or std.mem.endsWith(u8, field.name, "_count")) {
            @compileError("direct bridge JSON type gained an arena/count field: " ++ @typeName(T) ++ "." ++ field.name);
        }
    }
}

pub fn assertProjectionFieldCoverage() void {
    comptime {
        @setEvalBranchQuota(20_000);
        assertSourceFieldsBackedByWire(ui_model.ViewState, ViewWire, &.{ "time_zone", "appearance", "language", "resolved_language", "codex_usage_window", "codex_show_model_limits", "launch_at_login", "launch_at_login_registration_failed", "auto_refresh_minutes", "auto_refresh_account_count", "proxy_enabled", "proxy_enabled_detail_text", "proxy_account_count", "proxy_token_refresh_failed", "proxy_row_count", "row_count", "usage_count", "unified_row_count", "pool_remaining_percent", "pool_usable_count", "pool_total_count", "pool_tray_text", "names", "names_len", "text", "text_len" });
        assertSourceFieldsBackedByWire(ui_model.AccountView, AccountWire, &.{"window_count"});
        assertSourceFieldsBackedByWire(ui_model.Inspector, InspectorWire, &.{});
        assertSourceFieldsBackedByWire(shell.Model, ShellWire, &.{ "view", "service", "now_unix_s", "time_zone" });
        assertSourceFieldsBackedByWire(shell.AddAccountFlow, AddAccountWire, &.{ "baseline_row_count", "label_buffer", "label_len", "account_id_buffer", "account_id_len", "error_buffer", "error_len" });
        assertSourceFieldsBackedByWire(shell.RemoveFlow, RemoveWire, &.{ "status_revision_at_pause", "label_buffer", "label_len", "account_id_buffer", "account_id_len" });
        assertSourceFieldsBackedByWire(shell.ClearCooldownFlow, ClearCooldownWire, &.{ "label_buffer", "label_len", "account_id_buffer", "account_id_len" });
        assertSourceFieldsBackedByWire(shell.RenameFlow, RenameWire, &.{ "initial_label_buffer", "initial_label_len", "account_id_buffer", "account_id_len" });
        assertSourceFieldsBackedByWire(shell.FailoverSwitchFlow, FailoverSwitchWire, &.{ "account_id_buffer", "account_id_len", "target_label_buffer", "target_label_len" });
        assertSourceFieldsBackedByWire(ui_model.ResetFlow, ResetWire, &.{ "account_id_buffer", "account_id_len", "label_buffer", "label_len", "evidence_buffer", "evidence_len", "reset_buffer", "reset_len" });
        assertSourceFieldsBackedByWire(ui_model.Notice, NoticeWire, &.{ "buffer", "len" });

        assertFieldsCovered(ui_model.ViewState, &.{
            "now_unix_s",                "capabilities",             "tray_provider_headers",  "proxy_base_url",               "proxy_cli_path",            "proxy_config_path",            "proxy_node_path",        "proxy_node_resolved",
            "proxy_reachability",        "proxy_work",               "proxy_sync_state",       "proxy_last_attempt_at_unix_s", "proxy_last_attempt_result", "proxy_last_success_at_unix_s", "proxy_success_revision", "proxy_config_path_matches",
            "proxy_in_flight",           "proxy_accounts",           "proxy_rows",             "proxy_summary_text",           "proxy_detail_text",         "proxy_tray_text",              "proxy_service_state",    "proxy_service_detail_text",
            "proxy_service_can_install", "proxy_service_can_repair", "proxy_service_can_stop", "codex_routing_state",          "proxy_cli_default_path",    "proxy_node_default_path",      "rows",                   "usage_rows",
            "inspector",                 "account_row_count",        "claude_row_count",       "codex_exhausted_count",        "account_rows",              "claude_group_title",           "codex_group_title",      "claude_group_summary",
            "codex_group_summary",       "onboarding_visible",       "onboarding_steps",       "onboarding_next_action",       "toolbar_status_text",       "header_fresh_text",            "header_failed_text",     "header_has_failures",
            "proxy_pill_text",           "proxy_pill_ok",            "proxy_pill_warn",        "proxy_pill_bad",               "proxy_active_label",        "proxy_cooling_count",          "proxy_mapped_count",     "proxy_settings_summary_text",
            "proxy_node_hint_text",      "proxy_banner_text",        "claude_count",           "codex_count",                  "reauth_count",              "error_count",                  "stale_count",            "busy_count",
            "snapshot_count",            "newest_success_at_unix_s", "headline_text",          "summary_text",                 "tray_summary_text",         "service_text",                 "appearance",             "language",
            "resolved_language",         "unified_order_source",     "unified_rows",           "settings",
        }, &.{ "time_zone", "codex_usage_window", "codex_show_model_limits", "launch_at_login", "launch_at_login_registration_failed", "auto_refresh_minutes", "auto_refresh_account_count", "proxy_enabled", "proxy_enabled_detail_text", "proxy_account_count", "proxy_token_refresh_failed", "proxy_row_count", "row_count", "usage_count", "unified_row_count", "pool_remaining_percent", "pool_usable_count", "pool_total_count", "pool_tray_text", "names", "names_len", "text", "text_len" });
        assertFieldsCovered(ui_model.AccountView, &.{
            "account_id",                  "label",                  "provider_email",         "plan_label",        "provider",           "enabled",              "auth_state",          "freshness",                   "snapshot_status",   "has_snapshot",
            "snapshot_captured_at_unix_s", "last_attempt_at_unix_s", "last_success_at_unix_s", "last_attempt_code", "reset_credit_count", "credit_detail_status", "credit_detail_count", "operation_in_flight",         "queued",            "pending_reset_attempt",
            "unsent_reset_attempt",        "reset_proxy_clear",      "proxy_mode",             "proxy_active",      "proxy_can_switch",   "proxy_state",          "proxy_in_flight",     "proxy_cooldown_until_unix_s", "windows",           "primary",
            "tray_primary",                "summary_text",           "freshness_text",         "evidence_text",     "tray_identity_text", "tray_detail_text",     "tray_text",           "tray_account_text",           "tray_open_command", "tray_usage_text",
            "tray_updated_text",           "tray_failover_text",
        }, &.{"window_count"});
        assertDirectStruct(ui_model.AccountRowView);
        assertDirectStruct(ui_model.UnifiedRowView);
        assertDirectStruct(ui_model.SettingsView);
        assertDirectStruct(ui_model.ProxyAccountView);
        assertDirectStruct(ui_model.ProxyAccountFact);
        assertDirectStruct(ui_model.OnboardingStepView);
        assertDirectStruct(ui_model.OnboardingNextAction);
        assertDirectStruct(ui_model.UsageRow);
        assertDirectStruct(ui_model.WindowCell);
        assertDirectStruct(ui_model.RowChip);
        assertDirectStruct(ui_model.TrayItem);
        assertDirectStruct(ui_model.WindowView);
        assertFieldsCovered(shell.Model, &.{
            "settings_tab",            "expanded",           "row_menu",        "proxy_row_menu", "toolbar_menu_open",
            "proxy_settings_expanded", "claude_tray_window", "notice",          "add_account",    "reset",
            "remove",                  "rename",             "failover_switch", "clear_cooldown",
        }, &.{ "view", "service", "now_unix_s", "time_zone" });
        assertFieldsCovered(shell.AddAccountFlow, &.{ "open", "in_flight" }, &.{
            "baseline_row_count", "label_buffer", "label_len", "account_id_buffer", "account_id_len", "error_buffer", "error_len",
        });
        assertFieldsCovered(shell.RemoveFlow, &.{
            "open", "row", "uses_proxy", "pause_requested",
        }, &.{ "status_revision_at_pause", "label_buffer", "label_len", "account_id_buffer", "account_id_len" });
        assertFieldsCovered(shell.ClearCooldownFlow, &.{ "open", "row" }, &.{
            "label_buffer", "label_len", "account_id_buffer", "account_id_len",
        });
        assertFieldsCovered(shell.RenameFlow, &.{ "open", "row" }, &.{
            "initial_label_buffer", "initial_label_len", "account_id_buffer", "account_id_len",
        });
        assertFieldsCovered(shell.FailoverSwitchFlow, &.{ "open", "row" }, &.{
            "account_id_buffer", "account_id_len", "target_label_buffer", "target_label_len",
        });
        assertFieldsCovered(ui_model.ResetFlow, &.{
            "stage", "reason", "outcome", "settle", "proxy_clear", "row", "available_count",
        }, &.{
            "account_id_buffer", "account_id_len", "label_buffer", "label_len", "evidence_buffer",
            "evidence_len",      "reset_buffer",   "reset_len",
        });
        assertFieldsCovered(ui_model.Notice, &.{"kind"}, &.{ "buffer", "len" });
        assertFieldsCovered(shell.Effect, &.{"kind"}, &.{ "text_buffer", "text_len" });
    }
}

comptime {
    assertProjectionFieldCoverage();
}
