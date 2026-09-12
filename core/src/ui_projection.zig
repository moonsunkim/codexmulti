const std = @import("std");
const domain = @import("domain.zig");
const contracts = @import("ui_contracts.zig");
const ui_format = @import("ui_format.zig");
const strings = @import("strings.zig");
const format = ui_format.ProjectionFormat;
const copy = strings.system;

pub const node_missing_reason = copy.text(.node_missing_reason);

const ServiceCapabilities = contracts.ServiceCapabilities;
const AccountView = contracts.AccountView;
const WindowView = contracts.WindowView;
const UsageRow = contracts.UsageRow;
const Inspector = contracts.Inspector;
const AccountFact = contracts.AccountFact;
const WindowFact = contracts.WindowFact;
const ProxyFact = contracts.ProxyFact;
const ProxyAccountFact = contracts.ProxyAccountFact;
const ProxyAccountView = contracts.ProxyAccountView;
const AccountRowView = contracts.AccountRowView;
const UnifiedRowView = contracts.UnifiedRowView;
const RowChip = contracts.RowChip;
const WindowCell = contracts.WindowCell;
const RenderOptions = contracts.RenderOptions;
const TimeZone = contracts.TimeZone;
const max_rows = contracts.max_rows;
const max_windows_per_row = contracts.max_windows_per_row;
const max_line_bytes = contracts.max_line_bytes;
const names_capacity = contracts.names_capacity;
const text_capacity = contracts.text_capacity;

pub const app_version_text = copy.text(.app_version);

pub const ViewState = struct {
    now_unix_s: i64 = 0,
    time_zone: TimeZone = .system,
    capabilities: ServiceCapabilities = .{},
    appearance: contracts.Appearance = .system,
    codex_usage_window: contracts.CodexUsageWindow = .auto,
    codex_show_model_limits: bool = false,
    launch_at_login: bool = false,
    launch_at_login_registration_failed: bool = false,
    auto_refresh_minutes: u16 = 0,
    auto_refresh_account_count: u16 = 0,
    tray_provider_headers: [2][]const u8 = @splat(""),

    proxy_base_url: []const u8 = "",
    proxy_cli_path: []const u8 = "",
    proxy_config_path: []const u8 = "",
    proxy_node_path: []const u8 = "",
    proxy_node_resolved: []const u8 = "",
    proxy_reachability: contracts.ProxyReachability = .unknown,
    proxy_work: contracts.ProxyWork = .idle,
    proxy_sync_state: contracts.ProxySyncState = .unknown,
    proxy_last_attempt_at_unix_s: ?i64 = null,
    proxy_last_attempt_result: ?contracts.ProxyAttemptResult = null,
    proxy_last_success_at_unix_s: ?i64 = null,
    proxy_success_revision: u64 = 0,
    proxy_config_path_matches: bool = false,
    proxy_in_flight: u32 = 0,
    proxy_account_count: usize = 0,
    proxy_accounts: [max_rows]ProxyAccountFact = @splat(.{ .proxy_name = "", .label = "", .state = .unknown }),
    proxy_token_refresh_failed: [max_rows]bool = @splat(false),
    proxy_row_count: usize = 0,
    proxy_rows: [max_rows]ProxyAccountView = @splat(.{}),
    proxy_summary_text: []const u8 = "",
    proxy_detail_text: []const u8 = "",
    proxy_tray_text: []const u8 = "",
    proxy_service_state: contracts.ProxyServiceState = .not_installed,
    proxy_service_detail_text: []const u8 = copy.text(.proxy_service_not_installed),
    proxy_service_can_install: bool = false,
    proxy_service_can_repair: bool = false,
    proxy_service_can_stop: bool = false,
    codex_routing_state: contracts.CodexRoutingState = .off,
    proxy_enabled: bool = false,
    proxy_enabled_detail_text: []const u8 = copy.text(.proxy_direct_routing),
    proxy_cli_default_path: []const u8 = "",
    proxy_node_default_path: []const u8 = "",

    row_count: usize = 0,
    rows: [max_rows]AccountView = @splat(.{}),

    usage_count: usize = 0,
    usage_rows: [max_windows_per_row]UsageRow = @splat(.{}),
    inspector: Inspector = .{},

    account_row_count: usize = 0,
    claude_row_count: usize = 0,
    codex_exhausted_count: u32 = 0,
    account_rows: [max_rows]AccountRowView = @splat(.{}),
    unified_order_source: contracts.UnifiedOrderSource = .registry,
    unified_row_count: usize = 0,
    unified_rows: [max_rows]UnifiedRowView = @splat(.{}),
    settings: contracts.SettingsView = .{},
    claude_group_title: []const u8 = "",
    codex_group_title: []const u8 = "",

    claude_group_summary: []const u8 = "",
    codex_group_summary: []const u8 = "",
    no_accounts_title_text: []const u8 = copy.text(.no_accounts_yet),
    no_accounts_body_text: []const u8 = copy.text(.no_accounts_body),
    no_accounts_action_text: []const u8 = copy.text(.add_codex),

    toolbar_status_text: []const u8 = "",
    pool_remaining_percent: ?u8 = null,
    pool_usable_count: u32 = 0,
    pool_total_count: u32 = 0,
    pool_tray_text: []const u8 = "",
    header_fresh_text: []const u8 = "",
    header_failed_text: []const u8 = "",
    header_has_failures: bool = false,
    proxy_pill_text: []const u8 = "",
    proxy_pill_ok: bool = false,
    proxy_pill_warn: bool = false,
    proxy_pill_bad: bool = false,
    proxy_active_label: []const u8 = "",
    proxy_cooling_count: u32 = 0,
    proxy_mapped_count: u32 = 0,
    proxy_settings_summary_text: []const u8 = "",
    proxy_node_hint_text: []const u8 = "",
    proxy_banner_text: []const u8 = "",

    claude_count: u32 = 0,
    codex_count: u32 = 0,
    reauth_count: u32 = 0,
    error_count: u32 = 0,
    stale_count: u32 = 0,
    busy_count: u32 = 0,
    snapshot_count: u32 = 0,
    newest_success_at_unix_s: ?i64 = null,

    headline_text: []const u8 = "",
    summary_text: []const u8 = "",

    tray_summary_text: []const u8 = "",
    service_text: []const u8 = "",

    names: [names_capacity]u8 = @splat(0),
    names_len: usize = 0,
    text: [text_capacity]u8 = @splat(0),
    text_len: usize = 0,

    pub fn begin(self: *ViewState, now_unix_s: i64, capabilities: ServiceCapabilities, time_zone: TimeZone) void {
        self.now_unix_s = now_unix_s;
        self.time_zone = time_zone;
        self.capabilities = capabilities;
        self.appearance = .system;
        self.codex_usage_window = .auto;
        self.codex_show_model_limits = false;
        self.launch_at_login = false;
        self.launch_at_login_registration_failed = false;
        self.auto_refresh_minutes = 0;
        self.auto_refresh_account_count = 0;
        self.tray_provider_headers = @splat("");
        self.proxy_base_url = "";
        self.proxy_cli_path = "";
        self.proxy_config_path = "";
        self.proxy_node_path = "";
        self.proxy_node_resolved = "";
        self.proxy_reachability = .unknown;
        self.proxy_work = .idle;
        self.proxy_sync_state = .unknown;
        self.proxy_last_attempt_at_unix_s = null;
        self.proxy_last_attempt_result = null;
        self.proxy_last_success_at_unix_s = null;
        self.proxy_success_revision = 0;
        self.proxy_config_path_matches = false;
        self.proxy_in_flight = 0;
        self.proxy_account_count = 0;
        self.proxy_row_count = 0;
        self.proxy_summary_text = "";
        self.proxy_detail_text = "";
        self.proxy_tray_text = "";
        self.proxy_service_state = .not_installed;
        self.proxy_service_detail_text = copy.text(.proxy_service_not_installed);
        self.proxy_service_can_install = false;
        self.proxy_service_can_repair = false;
        self.proxy_service_can_stop = false;
        self.codex_routing_state = .off;
        self.proxy_enabled = false;
        self.proxy_enabled_detail_text = copy.text(.proxy_direct_routing);
        self.proxy_cli_default_path = "";
        self.proxy_node_default_path = "";
        self.row_count = 0;
        self.usage_count = 0;
        self.inspector = .{};
        self.unified_order_source = .registry;
        self.unified_row_count = 0;
        self.settings = .{};
        self.resetOverview();
        self.claude_count = 0;
        self.codex_count = 0;
        self.reauth_count = 0;
        self.error_count = 0;
        self.stale_count = 0;
        self.busy_count = 0;
        self.snapshot_count = 0;
        self.newest_success_at_unix_s = null;
        self.names_len = 0;
        self.text_len = 0;
        self.headline_text = "";
        self.summary_text = "";
        self.tray_summary_text = "";
        self.pool_remaining_percent = null;
        self.pool_usable_count = 0;
        self.pool_total_count = 0;
        self.pool_tray_text = "";
        self.service_text = "";
        self.no_accounts_title_text = copy.text(.no_accounts_yet);
        self.no_accounts_body_text = copy.text(.no_accounts_body);
        self.no_accounts_action_text = copy.text(.add_codex);
    }

    pub fn pushAccount(self: *ViewState, fact: AccountFact) error{ViewFull}!usize {
        if (fact.provider == .claude) return max_rows;
        if (self.row_count == max_rows) return error.ViewFull;
        const index = self.row_count;
        self.rows[index] = .{
            .account_id = self.internName(fact.account_id),
            .label = self.internName(fact.label),
            .provider_email = self.internName(fact.provider_email orelse ""),
            .plan_label = self.internName(fact.plan_label orelse ""),
            .provider = fact.provider,
            .enabled = fact.enabled,
            .auth_state = fact.auth_state,
            .freshness = fact.freshness,
            .snapshot_status = fact.snapshot_status,
            .has_snapshot = fact.has_snapshot,
            .snapshot_captured_at_unix_s = fact.snapshot_captured_at_unix_s,
            .last_attempt_at_unix_s = fact.last_attempt_at_unix_s,
            .last_success_at_unix_s = fact.last_success_at_unix_s,
            .last_attempt_code = self.internName(fact.last_attempt_code orelse ""),
            .reset_credit_count = fact.reset_credit_count,
            .credit_detail_status = fact.credit_detail_status,
            .credit_detail_count = fact.credit_detail_count,
            .operation_in_flight = fact.operation_in_flight,
            .queued = fact.queued,
            .pending_reset_attempt = fact.pending_reset_attempt,
            .unsent_reset_attempt = fact.unsent_reset_attempt,
            .reset_proxy_clear = fact.reset_proxy_clear,
        };
        self.row_count += 1;
        return index;
    }

    pub fn pushWindow(self: *ViewState, row_index: usize, window: WindowFact) error{ViewFull}!void {
        if (row_index == max_rows) return;
        if (row_index >= self.row_count) return error.ViewFull;
        const row = &self.rows[row_index];
        if (row.window_count == max_windows_per_row) return error.ViewFull;
        row.windows[row.window_count] = .{
            .label = self.internName(window.label),
            .model_label = self.internName(window.model_label orelse ""),
            .kind = window.kind,
            .used_percent = window.used_percent,
            .fraction = @as(f32, @floatFromInt(@min(window.used_percent, 100))) / 100.0,
            .reset_at_unix_s = window.reset_at_unix_s,
            .duration_minutes = window.duration_minutes,
        };
        row.window_count += 1;
    }

    pub fn applyProxy(self: *ViewState, fact: ProxyFact) void {
        self.proxy_base_url = self.internName(fact.base_url);
        self.proxy_cli_path = self.internName(fact.cli_path);
        self.proxy_config_path = self.internName(fact.config_path);
        self.proxy_node_path = self.internName(fact.node_path);
        self.proxy_node_resolved = self.internName(fact.node_resolved);
        self.proxy_reachability = fact.reachability;
        self.proxy_work = fact.work;
        self.proxy_sync_state = fact.sync_state;
        self.proxy_last_attempt_at_unix_s = fact.last_attempt_at_unix_s;
        self.proxy_last_attempt_result = fact.last_attempt_result;
        self.proxy_last_success_at_unix_s = fact.last_success_at_unix_s;
        self.proxy_success_revision = fact.success_revision;
        self.proxy_config_path_matches = fact.config_path_matches;
        self.proxy_in_flight = fact.in_flight;
        self.proxy_account_count = @min(fact.accounts.len, self.proxy_accounts.len);
        for (fact.accounts[0..self.proxy_account_count], 0..) |account, index| {
            self.proxy_accounts[index] = .{
                .app_id = if (account.app_id) |value| self.internName(value) else null,
                .storage_key = if (account.storage_key) |value| self.internName(value) else null,
                .proxy_name = self.internName(account.proxy_name),
                .label = self.internName(account.label),
                .state = account.state,
                .cooldown_until_unix_s = account.cooldown_until_unix_s,
                .token_expires_at_unix_s = account.token_expires_at_unix_s,
                .in_flight = account.in_flight,
                .active = account.active,
                .mapped = account.mapped,
            };
            self.proxy_token_refresh_failed[index] = index < fact.token_refresh_failures.len and fact.token_refresh_failures[index];

            const app_id = account.app_id orelse continue;
            if (fact.reachability != .reachable or !fact.config_path_matches or !account.mapped) continue;
            const row_index = self.indexOfAccount(app_id) orelse continue;
            const row = &self.rows[row_index];
            if (row.provider != .codex) continue;
            row.proxy_mode = true;
            row.proxy_active = account.active;
            row.proxy_state = account.state;
            row.proxy_in_flight = account.in_flight;
            row.proxy_cooldown_until_unix_s = account.cooldown_until_unix_s;
            row.proxy_can_switch = fact.work == .idle and account.state == .ready and !account.active;
        }
    }

    pub fn applyProxyService(self: *ViewState, fact: contracts.ProxyServiceFact) void {
        self.proxy_service_state = fact.state;
        self.proxy_service_detail_text = self.internName(fact.detail_text);
        self.proxy_service_can_install = fact.can_install;
        self.proxy_service_can_repair = fact.can_repair;
        self.proxy_service_can_stop = fact.can_stop;
        self.codex_routing_state = fact.routing_state;
        self.proxy_enabled = fact.enabled;
        self.proxy_enabled_detail_text = self.internName(fact.enabled_detail_text);
        self.proxy_cli_default_path = self.internName(fact.cli_default_path);
        self.proxy_node_default_path = self.internName(fact.node_default_path);
    }

    pub fn applyAppearance(self: *ViewState, appearance: contracts.Appearance) void {
        self.appearance = appearance;
    }

    pub fn applyCodexSettings(
        self: *ViewState,
        usage_window: contracts.CodexUsageWindow,
        show_model_limits: bool,
    ) void {
        self.codex_usage_window = usage_window;
        self.codex_show_model_limits = show_model_limits;
    }

    pub fn applyLaunchAtLogin(self: *ViewState, enabled: bool, registration_failed: bool) void {
        self.launch_at_login = enabled;
        self.launch_at_login_registration_failed = registration_failed;
    }

    pub fn applyAutoRefresh(self: *ViewState, minutes: u16, account_count: u16) void {
        self.auto_refresh_minutes = minutes;
        self.auto_refresh_account_count = account_count;
    }

    pub fn finish(self: *ViewState, options: RenderOptions) void {
        self.text_len = 0;
        self.usage_count = 0;
        self.inspector = .{};

        self.claude_count = 0;
        self.codex_count = 0;
        self.reauth_count = 0;
        self.error_count = 0;
        self.stale_count = 0;
        self.busy_count = 0;
        self.snapshot_count = 0;
        self.newest_success_at_unix_s = null;
        self.proxy_row_count = 0;
        self.proxy_summary_text = "";
        self.proxy_detail_text = "";
        self.proxy_tray_text = "";
        self.resetOverview();

        self.renderProxy(options);

        for (self.rows[0..self.row_count], 0..) |*row, row_index| {
            row.primary = format.selectConfiguredCodexPrimaryWindow(
                row.plan_label,
                row.windows[0..row.window_count],
                self.codex_usage_window,
                self.codex_show_model_limits,
            );
            row.tray_primary = row.primary;
            self.codex_count += 1;
            if (row.has_snapshot) self.snapshot_count += 1;
            if (row.operation_in_flight or row.queued) self.busy_count += 1;
            switch (row.freshness) {
                .reauth_required => self.reauth_count += 1,
                .refresh_failed, .usage_unavailable => self.error_count += 1,
                .saved_snapshot, .reset_passed, .refresh_deferred => self.stale_count += 1,
                else => {},
            }
            if (row.last_success_at_unix_s) |at| {
                if (self.newest_success_at_unix_s == null or at > self.newest_success_at_unix_s.?) {
                    self.newest_success_at_unix_s = at;
                }
            }
            self.renderRow(row, row_index);
        }

        self.renderHeader();
        self.renderTrayProviderHeaders();
        self.renderAccountRows(options);
        self.renderInspector(options);
        self.renderUnifiedRows();
        self.renderSettings();
        self.renderPool();
        self.renderHeaderView();
    }

    fn resetOverview(self: *ViewState) void {
        self.account_row_count = 0;
        self.claude_row_count = 0;
        self.codex_exhausted_count = 0;
        self.claude_group_title = "";
        self.codex_group_title = "";
        self.claude_group_summary = "";
        self.codex_group_summary = "";
        self.header_fresh_text = "";
        self.header_failed_text = "";
        self.header_has_failures = false;
        self.toolbar_status_text = "";
        self.pool_remaining_percent = null;
        self.pool_usable_count = 0;
        self.pool_total_count = 0;
        self.pool_tray_text = "";
        self.proxy_pill_text = "";
        self.proxy_pill_ok = false;
        self.proxy_pill_warn = false;
        self.proxy_pill_bad = false;
        self.proxy_active_label = "";
        self.proxy_cooling_count = 0;
        self.proxy_mapped_count = 0;
        self.proxy_settings_summary_text = "";
        self.proxy_node_hint_text = "";
        self.proxy_banner_text = "";
        self.unified_order_source = .registry;
        self.unified_row_count = 0;
        self.settings = .{};
    }

    pub fn rowSlice(self: *const ViewState) []const AccountView {
        return self.rows[0..self.row_count];
    }

    pub fn usageSlice(self: *const ViewState) []const UsageRow {
        return self.usage_rows[0..self.usage_count];
    }

    pub fn proxyRowSlice(self: *const ViewState) []const ProxyAccountView {
        return self.proxy_rows[0..self.proxy_row_count];
    }

    pub fn accountRowSlice(self: *const ViewState) []const AccountRowView {
        return self.account_rows[0..self.account_row_count];
    }

    pub fn unifiedRowSlice(self: *const ViewState) []const UnifiedRowView {
        return self.unified_rows[0..self.unified_row_count];
    }

    pub fn claudeAccountRowSlice(self: *const ViewState) []const AccountRowView {
        return self.account_rows[0..self.claude_row_count];
    }

    pub fn codexAccountRowSlice(self: *const ViewState) []const AccountRowView {
        return self.account_rows[self.claude_row_count..self.account_row_count];
    }

    pub fn rowAt(self: *const ViewState, index: usize) ?*const AccountView {
        if (index >= self.row_count) return null;
        return &self.rows[index];
    }

    pub fn proxyIndexOfAccount(self: *const ViewState, account_id: []const u8) ?usize {
        for (self.proxy_rows[0..self.proxy_row_count], 0..) |row, index| {
            if (row.app_id.len != 0 and std.mem.eql(u8, row.app_id, account_id)) return index;
        }
        return null;
    }

    pub fn indexOfAccount(self: *const ViewState, account_id: []const u8) ?usize {
        for (self.rows[0..self.row_count], 0..) |row, index| {
            if (std.mem.eql(u8, row.account_id, account_id)) return index;
        }
        return null;
    }

    pub fn isEmpty(self: *const ViewState) bool {
        return self.row_count == 0;
    }

    fn internName(self: *ViewState, value: []const u8) []const u8 {
        return internInto(&self.names, &self.names_len, value);
    }

    fn internText(self: *ViewState, value: []const u8) []const u8 {
        return internInto(&self.text, &self.text_len, value);
    }

    fn fmtText(self: *ViewState, comptime key: strings.FormatKey, args: strings.FormatArgs(key)) []const u8 {
        var scratch: [max_line_bytes]u8 = undefined;
        var writer = std.Io.Writer.fixed(&scratch);

        copy.write(&writer, key, args);
        return self.internText(writer.buffered());
    }

    fn proxyStateText(state: contracts.ProxyAccountState) []const u8 {
        return switch (state) {
            .ready => copy.text(.proxy_ready),
            .cooldown => copy.text(.proxy_cooldown),
            .paused => copy.text(.proxy_paused),
            .invalid => copy.text(.proxy_invalid),
            .refreshing => copy.text(.proxy_refreshing),
            .unknown => copy.text(.proxy_unknown),
        };
    }

    fn renderProxy(self: *ViewState, options: RenderOptions) void {
        var scratch: [max_line_bytes]u8 = undefined;
        var relative: [max_line_bytes]u8 = undefined;
        const controllable = self.proxy_reachability == .reachable and self.proxy_config_path_matches;
        const idle = self.proxy_work == .idle;
        var active_label: []const u8 = copy.text(.none_lower);
        var cooling: u32 = 0;
        var mapped: u32 = 0;

        for (self.proxy_accounts[0..self.proxy_account_count], 0..) |account, index| {
            if (account.active) active_label = account.label;
            if (account.state == .cooldown) cooling += 1;
            if (account.mapped) mapped += 1;
            const state_text: []const u8 = if (!account.mapped)
                copy.text(.not_mapped)
            else if (account.active)
                copy.text(.active)
            else
                proxyStateText(account.state);

            const detail_text: []const u8 = if (!account.mapped)
                self.internText(copy.text(.not_mapped_saved_account))
            else if (account.active)
                self.internText("")
            else switch (account.state) {
                .cooldown => if (account.cooldown_until_unix_s) |until|
                    self.fmtText(.proxy_cooldown_until, .{
                        format.shortLocal(&scratch, self.now_unix_s, until, self.time_zone),
                        format.remainingPhrase(&relative, until - self.now_unix_s),
                    })
                else
                    self.internText(copy.text(.cooldown_end_not_reported)),
                .paused => self.fmtText(.proxy_draining_resume, .{account.in_flight}),
                .invalid => self.internText(copy.text(.credential_needs_attention)),
                .refreshing => self.internText(copy.text(.refreshing_token)),
                .ready, .unknown => self.internText(""),
            };
            const label_at = std.mem.indexOfScalar(u8, account.label, '@');
            const can_resume = controllable and idle and account.mapped and
                (account.state == .paused or account.state == .invalid);
            const can_switch = controllable and idle and account.mapped and account.state == .ready and !account.active;
            const can_pause = controllable and idle and account.mapped and account.state != .paused;
            const can_clear_cooldown = controllable and idle and account.mapped and account.state == .cooldown;
            const state_accent = account.mapped and account.active;
            const state_ok = account.mapped and !account.active and account.state == .ready;
            self.proxy_rows[index] = .{
                .index = @intCast(index),
                .order_text = self.fmtText(.decimal_usize, .{index + 1}),
                .app_id = account.app_id orelse "",
                .label = account.label,
                .label_local = if (label_at) |at| account.label[0..at] else account.label,
                .label_domain = if (label_at) |at| account.label[at..] else "",
                .state = account.state,
                .in_flight = account.in_flight,
                .state_text = self.internText(state_text),
                .state_accent = state_accent,
                .state_ok = state_ok,
                .state_info = account.mapped and (account.state == .cooldown or account.state == .refreshing),
                .state_neutral = !account.mapped or account.state == .paused or account.state == .unknown,
                .state_destructive = account.mapped and account.state == .invalid,
                .detail_text = detail_text,
                .in_flight_text = if (account.in_flight != 0)
                    self.fmtText(.decimal_u32, .{account.in_flight})
                else
                    self.internText(""),
                .active = account.active,
                .mapped = account.mapped,
                .can_switch = can_switch,
                .can_pause = can_pause,
                .can_resume = can_resume,
                .can_reload = can_resume,
                .can_clear_cooldown = can_clear_cooldown,
                .has_actions = can_switch or can_pause or can_resume or can_clear_cooldown,
                .menu_open = options.proxy_row_menu != null and options.proxy_row_menu.? == index,
                .label_muted = !(state_accent or state_ok),
                .divider_below = index + 1 < self.proxy_account_count,
            };
        }
        self.proxy_row_count = self.proxy_account_count;
        self.proxy_active_label = self.internText(active_label);
        self.proxy_cooling_count = cooling;
        self.proxy_mapped_count = mapped;

        self.proxy_summary_text = switch (self.proxy_reachability) {
            .unknown => self.internText(copy.text(.proxy_status_unknown)),
            .reachable => if (self.proxy_config_path_matches)
                self.internText(copy.text(.failover_proxy_reachable))
            else
                self.internText(copy.text(.proxy_config_mismatch)),
            .@"unreachable" => self.internText(copy.text(.proxy_unreachable)),
            .incompatible => self.internText(copy.text(.proxy_incompatible)),
        };
        self.proxy_detail_text = switch (self.proxy_work) {
            .idle => switch (self.proxy_sync_state) {
                .unknown => self.internText(copy.text(.proxy_press_refresh)),
                .needed => if (self.proxy_last_attempt_result == .action_failed)
                    self.internText(copy.text(.proxy_busy_retry))
                else
                    self.internText(copy.text(.proxy_changes_next_refresh)),
                .synced => self.internText(copy.text(.proxy_synchronized)),
                .failed => self.internText(copy.text(.proxy_sync_failed)),
            },
            .checking => self.internText(copy.text(.proxy_checking)),
            .switching => self.internText(copy.text(.proxy_switching)),
            .pausing => self.internText(copy.text(.proxy_pausing)),
            .reloading => self.internText(copy.text(.proxy_reloading)),
            .clearing_cooldown => self.internText(copy.text(.proxy_clearing_cooldown)),
            .importing => self.internText(copy.text(.proxy_importing)),
            .applying_config => self.internText(copy.text(.proxy_applying_config)),
        };

        if (self.proxy_last_success_at_unix_s) |last_seen| {
            const seen = format.formatLocal(&scratch, last_seen, self.time_zone);
            self.proxy_tray_text = switch (self.proxy_reachability) {
                .reachable => self.fmtText(.tray_failover_last_seen, .{ localPart(active_label), cooling, seen }),
                .@"unreachable" => self.fmtText(.tray_proxy_unreachable_last_seen, .{seen}),
                .incompatible => self.fmtText(.tray_proxy_incompatible_last_seen, .{seen}),
                .unknown => self.fmtText(.tray_failover_unknown_last_seen, .{seen}),
            };
        } else {
            self.proxy_tray_text = self.internText(copy.text(.failover_status_unknown_settings));
        }

        self.proxy_pill_ok = controllable;
        self.proxy_pill_bad = self.proxy_reachability == .@"unreachable";
        self.proxy_pill_warn = !self.proxy_pill_ok and !self.proxy_pill_bad;
        self.proxy_pill_text = switch (self.proxy_reachability) {
            .reachable => if (self.proxy_config_path_matches)
                self.fmtText(.failover_active_cooling, .{ localPart(active_label), cooling })
            else
                self.internText(copy.text(.failover_config_mismatch)),
            .@"unreachable" => self.internText(copy.text(.failover_unreachable)),
            .incompatible => self.internText(copy.text(.failover_incompatible)),
            .unknown => self.internText(copy.text(.failover_unknown)),
        };

        self.proxy_banner_text = switch (self.proxy_reachability) {
            .@"unreachable" => if (self.proxy_last_success_at_unix_s) |at|
                self.fmtText(.proxy_unreachable_banner, .{
                    format.shortLocal(&scratch, self.now_unix_s, at, self.time_zone),
                })
            else
                self.internText(copy.text(.proxy_unreachable_never_seen)),
            .incompatible => self.internText(copy.text(.proxy_incompatible_update)),
            .reachable => if (!self.proxy_config_path_matches)
                self.internText(copy.text(.proxy_config_fix_next_refresh))
            else if (self.proxy_sync_state == .needed)
                if (self.proxy_last_attempt_result == .action_failed)
                    self.internText(copy.text(.proxy_busy_retry))
                else
                    self.internText(copy.text(.proxy_changes_next_refresh))
            else
                self.internText(""),
            .unknown => self.internText(""),
        };
        self.proxy_node_hint_text = if (self.proxy_node_path.len != 0)
            self.fmtText(.node_path, .{self.proxy_node_path})
        else if (self.proxy_node_resolved.len != 0)
            self.fmtText(.node_auto_path, .{self.proxy_node_resolved})
        else if (self.proxy_last_attempt_result == .import_node_missing)
            self.internText(copy.text(.node_not_found))
        else
            self.internText(copy.text(.node_auto));
        self.proxy_settings_summary_text = blk: {
            var host = self.proxy_base_url;
            if (std.mem.indexOf(u8, host, "://")) |at| host = host[at + 3 ..];
            break :blk self.fmtText(.proxy_settings_summary, .{
                if (host.len != 0) host else copy.text(.no_control_url),
                if (self.proxy_cli_path.len != 0) copy.text(.cli_path_set) else copy.text(.cli_path_missing),
                if (self.proxy_config_path_matches) copy.text(.config_matches) else copy.text(.config_not_confirmed),
            });
        };
    }

    fn chip(self: *ViewState, text: []const u8, tone: enum { accent, info, warning, destructive }) RowChip {
        return .{
            .present = true,
            .text = self.internText(text),
            .accent = tone == .accent,
            .info = tone == .info,
            .warning = tone == .warning,
            .destructive = tone == .destructive,
        };
    }

    fn pushChip(row: *AccountRowView, value: RowChip) void {
        if (!row.chip_a.present) {
            row.chip_a = value;
        } else if (!row.chip_b.present) {
            row.chip_b = value;
        }
    }

    fn windowCell(self: *ViewState, row: *const AccountView, index: ?usize) WindowCell {
        const slot = index orelse return .{};
        const window = row.windows[slot];
        var label_scratch: [max_line_bytes]u8 = undefined;
        var phrase: [max_line_bytes]u8 = undefined;
        const label = self.internText(format.humanizeWindowLabel(&label_scratch, window.label));
        const reset_phrase = self.internText(format.resetPhrase(&phrase, window.reset_at_unix_s, self.now_unix_s));
        return .{
            .present = true,
            .label = label,
            .percent_text = self.fmtText(.percent, .{window.used_percent}),
            .fraction = window.fraction,
            .exhausted = window.used_percent >= 100,
            .reset_phrase = reset_phrase,
            .caption = self.fmtText(.window_caption, .{ label, reset_phrase }),
        };
    }

    fn renderAccountRows(self: *ViewState, options: RenderOptions) void {
        var scratch: [max_line_bytes]u8 = undefined;
        const order = [_]domain.Provider{.codex};
        for (order) |provider| {
            var provider_ordinal: u32 = 0;
            for (self.rows[0..self.row_count], 0..) |*row, index| {
                if (row.provider != provider) continue;
                if (self.account_row_count == max_rows) break;
                provider_ordinal += 1;
                var view: AccountRowView = .{
                    .key = @intCast(self.account_row_count + 1),
                    .index = @intCast(index),
                    .provider = provider,
                    .is_codex = provider == .codex,
                    .title = self.displayLabel(row, provider_ordinal),
                    .plan = ui_format.displayPlanLabel(row.plan_label),
                    .has_plan = row.plan_label.len != 0,
                    .expanded = options.selected != null and options.selected.? == index,
                    .menu_open = options.row_menu != null and options.row_menu.? == index,

                    .is_cursor = row.proxy_mode and row.proxy_active,
                };

                if (std.mem.indexOfScalar(u8, row.provider_email, '@')) |at| {
                    view.email_local = row.provider_email[0..at];
                    view.email_domain = row.provider_email[at..];
                    view.has_domain = true;
                }
                if (view.has_domain and std.mem.eql(u8, row.provider_email, row.label)) {
                    view.identity_primary = view.email_local;
                    view.identity_secondary = view.email_domain;
                    view.has_identity_secondary = true;
                } else {
                    view.identity_primary = view.title;
                    view.identity_secondary = if (row.provider_email.len != 0)
                        self.fmtText(.identity_secondary, .{row.provider_email})
                    else
                        self.internText("");
                    view.has_identity_secondary = row.provider_email.len != 0;
                }

                const busy = row.operation_in_flight or row.queued;
                const needs_keychain_repair = std.mem.eql(u8, row.last_attempt_code, "keychain-access-repair-required");
                const needs_auth = row.auth_state != .connected or row.freshness == .reauth_required;
                if (busy) {
                    view.dot_busy = true;
                    view.action_busy = true;
                    view.busy_label = self.internText(if (row.operation_in_flight) copy.text(.refreshing_ellipsis) else copy.text(.queued));
                    pushChip(&view, self.chip(if (row.operation_in_flight) copy.text(.updating_ellipsis) else copy.text(.queued), .info));
                } else if (needs_auth) {
                    view.dot_sign_in = true;
                    if (needs_keychain_repair) view.action_sign_in_again = true else view.action_sign_in = true;
                    pushChip(&view, self.chip(copy.text(.sign_in_required), .warning));
                } else if (row.freshness == .refresh_failed or row.freshness == .usage_unavailable) {
                    view.dot_failed = true;
                    view.action_refresh = true;
                    const text = if (row.last_attempt_at_unix_s) |at|
                        self.fmtText(.freshness_with_ago, .{ format.freshnessText(row.freshness), format.agoPhrase(&scratch, self.now_unix_s, at) })
                    else
                        format.freshnessText(row.freshness);
                    pushChip(&view, self.chip(text, .destructive));
                } else if (row.freshness == .reset_passed or row.freshness == .refresh_deferred) {
                    view.dot_attention = true;
                    view.action_refresh = true;
                    pushChip(&view, self.chip(format.freshnessText(row.freshness), .warning));
                } else {
                    view.dot_ok = true;
                    view.action_refresh = true;
                    if (!row.enabled) pushChip(&view, self.chip(copy.text(.disabled), .info));
                }

                if (row.proxy_mode) {
                    if (row.proxy_active) {
                        pushChip(&view, self.chip(copy.text(.active), .accent));
                    } else switch (row.proxy_state) {
                        .cooldown => {
                            const text = if (row.proxy_cooldown_until_unix_s) |until|
                                self.fmtText(.cooldown_remaining, .{format.remainingPhrase(&scratch, until - self.now_unix_s)})
                            else
                                copy.text(.proxy_cooldown);
                            pushChip(&view, self.chip(text, .info));
                        },
                        .paused => pushChip(&view, self.chip(copy.text(.proxy_paused), .info)),
                        .invalid => pushChip(&view, self.chip(copy.text(.proxy_invalid_label), .destructive)),
                        else => {},
                    }
                }

                view.status_line = blk: {
                    var line: [max_line_bytes]u8 = undefined;
                    var writer = std.Io.Writer.fixed(&line);
                    if (view.has_plan) writer.writeAll(view.plan) catch {};
                    for ([_]RowChip{ view.chip_a, view.chip_b }) |phrase| {
                        if (!phrase.present) continue;
                        if (writer.buffered().len != 0) writer.writeAll(copy.text(.middle_dot_separator)) catch {};
                        writer.writeAll(phrase.text) catch {};
                    }
                    break :blk self.internText(writer.buffered());
                };

                view.window = self.windowCell(row, row.primary);
                if (provider == .codex) {
                    for (row.windows[0..row.window_count]) |window| {
                        if (window.kind == .weekly and window.used_percent >= 100) {
                            self.codex_exhausted_count += 1;
                            break;
                        }
                    }
                }

                view.can_switch_proxy = row.canSwitchProxy();
                view.switch_label = self.internText(copy.text(.use_in_failover));

                view.can_pause_proxy = row.proxy_mode and self.proxy_work == .idle and row.proxy_state != .paused;
                view.can_clear_cooldown = row.proxy_mode and self.proxy_work == .idle and row.proxy_state == .cooldown;
                if (row.provider == .codex) {
                    if (row.pending_reset_attempt) {
                        view.can_reset = true;
                        view.reset_label = self.internText(copy.text(.review_reset_attempt));
                    } else if (row.unsent_reset_attempt) {
                        view.can_reset = true;
                        view.reset_label = self.internText(copy.text(.retry_reset_attempt));
                    } else if (row.resetIsOfferable()) {
                        view.can_reset = true;
                        view.reset_label = self.fmtText(.reset_available_action, .{row.reset_credit_count.?});
                    }
                }

                const state_phrase: []const u8 = if (view.chip_a.present) view.chip_a.text else row.summary_text;
                view.access_label = if (view.expanded)
                    self.fmtText(.account_access_expanded, .{ view.title, state_phrase, format.providerName(provider) })
                else
                    self.fmtText(.account_access, .{ view.title, state_phrase, format.providerName(provider) });

                if (provider_ordinal > 1) self.account_rows[self.account_row_count - 1].divider_below = true;
                self.account_rows[self.account_row_count] = view;
                self.account_row_count += 1;
            }
        }

        self.claude_group_summary = self.internText("");
        self.codex_group_summary = if (self.codex_exhausted_count != 0)
            self.fmtText(.account_group_exhausted, .{
                self.codex_count,
                if (self.codex_count == 1) copy.text(.account_singular) else copy.text(.account_plural),
                self.codex_exhausted_count,
            })
        else
            self.fmtText(.account_group_count, .{
                self.codex_count,
                if (self.codex_count == 1) copy.text(.account_singular) else copy.text(.account_plural),
            });
        self.claude_group_title = self.internText("");
        self.codex_group_title = self.fmtText(.codex_group_title, .{self.codex_group_summary});
    }

    fn unifiedFailoverState(row: *const ProxyAccountView) contracts.UnifiedFailoverState {
        if (!row.mapped) return .not_mapped;
        if (row.active) return .active;
        return switch (row.state) {
            .ready => .ready,
            .cooldown => .cooldown,
            .paused => .paused,
            .invalid => .invalid,
            .refreshing => .refreshing,
            .unknown => .unknown,
        };
    }

    fn appendUnifiedRow(self: *ViewState, account: *const AccountRowView) void {
        if (self.unified_row_count >= self.unified_rows.len) return;
        const proxy_position = self.proxyIndexOfAccount(self.rows[account.index].account_id);
        const proxy: ?*const ProxyAccountView = if (proxy_position) |index| &self.proxy_rows[index] else null;
        const inspector_index: ?u32 = if (account.expanded and self.inspector.present and self.inspector.index == account.index)
            self.inspector.index
        else
            null;
        self.unified_rows[self.unified_row_count] = .{
            .key = @intCast(self.unified_row_count + 1),
            .account_index = account.index,
            .proxy_index = if (proxy_position) |index| @intCast(index) else null,
            .account_id = self.rows[account.index].account_id,
            .identity_label = account.title,
            .email_local = account.email_local,
            .email_domain = account.email_domain,
            .has_domain = account.has_domain,
            .plan = account.plan,
            .has_plan = account.has_plan,
            .usage_caption = account.window.caption,
            .usage_percent_text = account.window.percent_text,
            .usage_bar_fraction = account.window.fraction,
            .usage_exhausted = account.window.exhausted,
            .failover_state = if (proxy) |row| unifiedFailoverState(row) else .not_mapped,
            .failover_state_text = if (proxy) |row| row.state_text else copy.text(.not_mapped),
            .failover_accent = if (proxy) |row| row.state_accent else false,
            .failover_muted = if (proxy) |row| row.label_muted else true,
            .failover_detail_text = if (proxy) |row| row.detail_text else copy.text(.not_mapped_to_failover),
            .failover_in_flight = if (proxy) |row| row.in_flight else 0,
            .failover_in_flight_text = if (proxy) |row| row.in_flight_text else "",
            .expanded = account.expanded,
            .inspector_index = inspector_index,
            .account_menu_open = account.menu_open,
            .proxy_menu_open = if (proxy) |row| row.menu_open else false,
            .menu_open = account.menu_open or if (proxy) |row| row.menu_open else false,
            .action_refresh = account.action_refresh,
            .action_sign_in = account.action_sign_in,
            .action_sign_in_again = account.action_sign_in_again,
            .action_busy = account.action_busy,
            .busy_label = account.busy_label,
            .can_switch_proxy = account.can_switch_proxy,
            .switch_label = account.switch_label,
            .can_pause_proxy = account.can_pause_proxy,
            .can_clear_cooldown = account.can_clear_cooldown or if (proxy) |row| row.can_clear_cooldown else false,
            .can_reset = account.can_reset,
            .reset_label = account.reset_label,
            .can_switch = if (proxy) |row| row.can_switch else false,
            .can_pause = if (proxy) |row| row.can_pause else false,
            .can_resume = if (proxy) |row| row.can_resume else false,
            .can_reload = if (proxy) |row| row.can_reload else false,
            .has_actions = if (proxy) |row| row.has_actions else false,
        };
        self.unified_row_count += 1;
    }

    fn renderUnifiedRows(self: *ViewState) void {
        self.unified_row_count = 0;
        self.unified_order_source = .registry;
        for (self.account_rows[0..self.account_row_count]) |*account| {
            self.appendUnifiedRow(account);
        }
    }

    fn renderSettings(self: *ViewState) void {
        const auto_refresh_traffic_text = if (self.auto_refresh_minutes == 0)
            self.internText(copy.text(.auto_refresh_off))
        else blk: {
            const refreshes_per_hour: u16 = 60 / self.auto_refresh_minutes;
            const requests_per_hour: u32 = @as(u32, self.auto_refresh_account_count) * refreshes_per_hour;
            const account_word = if (self.auto_refresh_account_count == 1) copy.text(.account_singular) else copy.text(.account_plural);
            break :blk self.fmtText(
                .auto_refresh_traffic,
                .{ self.auto_refresh_account_count, account_word, refreshes_per_hour, requests_per_hour },
            );
        };
        self.settings = .{
            .appearance = self.appearance,
            .codex_usage_window = self.codex_usage_window,
            .codex_show_model_limits = self.codex_show_model_limits,
            .app_version_text = app_version_text,
            .launch_at_login = self.launch_at_login,
            .launch_at_login_registration_failed = self.launch_at_login_registration_failed,
            .auto_refresh_minutes = self.auto_refresh_minutes,
            .auto_refresh_traffic_text = auto_refresh_traffic_text,
            .proxy_service_state = self.proxy_service_state,
            .proxy_service_detail_text = self.proxy_service_detail_text,
            .proxy_service_can_install = self.proxy_service_can_install,
            .proxy_service_can_repair = self.proxy_service_can_repair,
            .proxy_service_can_stop = self.proxy_service_can_stop,
            .codex_routing_state = self.codex_routing_state,
            .proxy_enabled = self.proxy_enabled,
            .proxy_enabled_detail_text = self.proxy_enabled_detail_text,
            .proxy_cli_default_path = self.proxy_cli_default_path,
            .proxy_node_default_path = self.proxy_node_default_path,
            .proxy_base_url = self.proxy_base_url,
            .proxy_cli_path = self.proxy_cli_path,
            .proxy_config_path = self.proxy_config_path,
            .proxy_node_path = self.proxy_node_path,
            .proxy_node_resolved = self.proxy_node_resolved,
            .proxy_settings_summary_text = self.proxy_settings_summary_text,
            .proxy_node_hint_text = self.proxy_node_hint_text,
        };
    }

    fn renderHeaderView(self: *ViewState) void {
        var absolute: [max_line_bytes]u8 = undefined;
        var relative: [max_line_bytes]u8 = undefined;
        self.header_fresh_text = if (self.newest_success_at_unix_s) |at|
            self.fmtText(.last_refresh, .{
                format.shortLocal(&absolute, self.now_unix_s, at, self.time_zone),
                format.agoPhrase(&relative, self.now_unix_s, at),
            })
        else
            self.internText(copy.text(.freshness_never));
        self.header_has_failures = self.error_count != 0;
        self.header_failed_text = if (self.error_count != 0)
            self.fmtText(.failed_count, .{self.error_count})
        else
            self.internText("");

        var ago_scratch: [max_line_bytes]u8 = undefined;
        const ago: []const u8 = if (self.newest_success_at_unix_s) |at|
            format.agoPhrase(&ago_scratch, self.now_unix_s, at)
        else
            copy.text(.freshness_never_lower);
        const has_table = self.proxy_account_count != 0;
        const shows_cursor = self.capabilities.proxy_control and
            ((self.proxy_reachability == .reachable and self.proxy_config_path_matches) or
                (self.proxy_reachability == .unknown and has_table));
        var line: [max_line_bytes]u8 = undefined;
        var writer = std.Io.Writer.fixed(&line);
        if (self.codex_count == 0) {
            writer.writeAll(copy.text(.no_accounts)) catch {};
        } else if (self.proxy_service_state == .not_installed or self.codex_routing_state == .off) {
            copy.write(&writer, .toolbar_proxy_off, .{ago});
        } else if (self.proxy_service_state == .@"unreachable" or self.proxy_reachability == .unknown or self.proxy_reachability == .@"unreachable") {
            copy.write(&writer, .toolbar_proxy_unreachable, .{ago});
        } else if (shows_cursor) {
            var ready: u32 = 0;
            var soonest_cooldown_until: ?i64 = null;
            for (self.proxy_accounts[0..self.proxy_account_count]) |account| {
                if (!account.mapped) continue;
                if (account.active or account.state == .ready) ready += 1;
                if (account.state == .cooldown) {
                    const until = account.cooldown_until_unix_s orelse continue;
                    if (until <= self.now_unix_s) continue;
                    if (soonest_cooldown_until == null or until < soonest_cooldown_until.?) {
                        soonest_cooldown_until = until;
                    }
                }
            }
            if (std.mem.eql(u8, self.proxy_active_label, copy.text(.none_lower))) {
                writer.writeAll(copy.text(.no_cursor_separator)) catch {};
            }
            if (ready == 0) {
                if (soonest_cooldown_until) |until| {
                    var reset_scratch: [max_line_bytes]u8 = undefined;
                    copy.write(&writer, .toolbar_none_ready_reset, .{
                        format.remainingPhrase(&reset_scratch, until - self.now_unix_s),
                    });
                } else {
                    copy.write(&writer, .toolbar_none_ready, .{ago});
                }
            } else if (self.proxy_in_flight != 0) {
                copy.write(&writer, .toolbar_ready_in_flight, .{ ready, self.proxy_in_flight });
            } else {
                copy.write(&writer, .toolbar_ready, .{ ready, ago });
            }
        } else if (self.capabilities.proxy_control) {
            copy.write(&writer, .toolbar_proxy_status, .{ self.proxy_pill_text, ago });
        } else {
            writer.writeAll(self.header_fresh_text) catch {};
        }
        if (self.pool_remaining_percent) |remaining| {
            copy.write(&writer, .toolbar_pool_suffix, .{remaining});
        }
        if (self.error_count != 0) copy.write(&writer, .toolbar_failed_suffix, .{self.error_count});
        self.toolbar_status_text = self.internText(writer.buffered());
    }

    fn renderPool(self: *ViewState) void {
        self.pool_total_count = @intCast(self.row_count);
        if (self.row_count == 0) return;

        var remaining_sum: u32 = 0;
        var observed_count: u32 = 0;
        for (self.rows[0..self.row_count]) |*row| {
            if (!self.poolAccountUsable(row)) continue;
            self.pool_usable_count += 1;
            for (row.windows[0..row.window_count]) |window| {
                if (window.kind != .weekly) continue;
                remaining_sum += 100 - @min(@as(u32, window.used_percent), 100);
                observed_count += 1;
                break;
            }
        }
        if (observed_count == 0) return;

        const remaining: u8 = @intCast((remaining_sum + observed_count / 2) / observed_count);
        self.pool_remaining_percent = remaining;
        self.pool_tray_text = self.fmtText(.tray_pool, .{
            remaining,
            self.pool_usable_count,
            self.pool_total_count,
        });
    }

    fn poolAccountUsable(self: *const ViewState, row: *const AccountView) bool {
        if (self.proxy_service_state == .not_installed) return true;
        for (self.proxy_accounts[0..self.proxy_account_count]) |account| {
            const app_id = account.app_id orelse continue;
            if (!std.mem.eql(u8, app_id, row.account_id)) continue;
            if (!account.mapped) return false;
            return switch (account.state) {
                .ready, .cooldown => true,
                .paused, .invalid => false,
                .refreshing, .unknown => account.active,
            };
        }
        return false;
    }

    fn renderRow(self: *ViewState, row: *AccountView, row_index: usize) void {
        var scratch: [max_line_bytes]u8 = undefined;

        row.summary_text = blk: {
            if (row.operation_in_flight) break :blk self.internText(copy.text(.updating_ellipsis));
            if (row.queued) break :blk self.internText(copy.text(.row_queued_to_refresh));
            if (!row.enabled) break :blk self.internText(copy.text(.disabled));
            if (row.auth_state != .connected) break :blk self.internText(copy.text(.sign_in_required));
            if (row.needsAttention()) break :blk self.internText(format.freshnessText(row.freshness));
            const window = row.trayWindow() orelse
                break :blk self.internText(format.noWindowWording(row.*));
            break :blk self.fmtText(.row_usage_summary, .{
                window.used_percent,
                format.countdownPhrase(&scratch, window.reset_at_unix_s, self.now_unix_s),
            });
        };

        row.freshness_text = self.internText(format.freshnessText(row.freshness));

        row.evidence_text = blk: {
            var line: [max_line_bytes]u8 = undefined;
            var writer = std.Io.Writer.fixed(&line);
            if (row.last_success_at_unix_s) |at| {
                copy.write(&writer, .evidence_last_success, .{format.formatLocal(&scratch, at, self.time_zone)});
            } else {
                writer.writeAll(copy.text(.evidence_no_success)) catch {};
            }
            if (row.last_attempt_at_unix_s) |at| {
                copy.write(&writer, .evidence_last_attempt, .{format.formatLocal(&scratch, at, self.time_zone)});
            } else {
                writer.writeAll(copy.text(.evidence_no_attempt)) catch {};
            }

            if (row.last_attempt_code.len != 0 and !row.needsAttention()) {
                writer.writeAll(copy.text(.middle_dot_separator)) catch {};
                writer.writeAll(row.last_attempt_code) catch {};
            }
            break :blk self.internText(writer.buffered());
        };

        const status = blk: {
            if (row.operation_in_flight) break :blk copy.text(.row_refreshing_usage);
            if (row.queued) break :blk copy.text(.row_queued_to_refresh);
            if (row.freshness == .reauth_required or row.auth_state != .connected) break :blk copy.text(.row_sign_in_required);
            if (row.freshness == .refresh_failed or row.freshness == .usage_unavailable) break :blk copy.text(.row_refresh_failed);
            if (!row.has_snapshot or row.freshness == .never_refreshed) break :blk copy.text(.row_not_refreshed_yet);
            if (!row.enabled) break :blk copy.text(.row_disabled);
            const window = row.trayWindow() orelse break :blk format.noWindowWording(row.*);
            break :blk self.fmtText(.row_usage_summary, .{
                window.used_percent,
                format.countdownPhrase(&scratch, window.reset_at_unix_s, self.now_unix_s),
            });
        };

        row.tray_text = self.fmtText(.row_tray_status, .{ row.label, status });

        _ = row_index;
        row.tray_account_text = row.tray_text;
        var command: [max_line_bytes]u8 = undefined;
        var command_writer = std.Io.Writer.fixed(&command);
        command_writer.writeAll(contracts.tray_command_open_account_prefix) catch {};
        command_writer.writeAll(row.account_id) catch {};
        row.tray_open_command = self.internText(command_writer.buffered());

        row.tray_usage_text = blk: {
            const window = row.trayWindow() orelse break :blk self.internText(format.noWindowWording(row.*));
            break :blk self.fmtText(.tray_usage, .{
                window.used_percent,
                window.label,
                format.countdownPhrase(&scratch, window.reset_at_unix_s, self.now_unix_s),
            });
        };
        row.tray_updated_text = if (row.last_success_at_unix_s) |at|
            self.fmtText(.updated, .{format.formatLocal(&scratch, at, self.time_zone)})
        else
            self.internText(copy.text(.not_refreshed_yet));

        row.tray_failover_text = blk: {
            if (!row.proxy_mode) break :blk "";
            if (row.proxy_active) break :blk self.internText(copy.text(.active_in_failover_proxy));
            if (row.proxy_can_switch) break :blk self.internText(copy.text(.use_in_failover_proxy));
            break :blk self.fmtText(.failover_proxy_state, .{proxyStateText(row.proxy_state)});
        };

        row.tray_identity_text = row.tray_text;
        row.tray_detail_text = row.tray_usage_text;
    }

    fn renderHeader(self: *ViewState) void {
        var scratch: [max_line_bytes]u8 = undefined;
        self.headline_text = self.internText(copy.text(.codexmulti));

        if (self.row_count == 0) {
            self.summary_text = self.internText(copy.text(.no_accounts_registered));
        } else {
            var line: [max_line_bytes]u8 = undefined;
            var writer = std.Io.Writer.fixed(&line);
            copy.write(&writer, .header_accounts, .{self.row_count});
            if (self.reauth_count != 0) {
                copy.write(&writer, .header_need_sign_in, .{self.reauth_count});
            }
            if (self.error_count != 0) {
                copy.write(&writer, .header_unreadable, .{self.error_count});
            }
            if (self.busy_count != 0) {
                copy.write(&writer, .header_in_progress, .{self.busy_count});
            }
            if (self.newest_success_at_unix_s) |at| {
                copy.write(&writer, .header_updated, .{format.formatLocal(&scratch, at, self.time_zone)});
            } else if (self.snapshot_count == 0) {
                writer.writeAll(copy.text(.header_not_refreshed_suffix)) catch {};
            }
            self.summary_text = self.internText(writer.buffered());
        }
        self.tray_summary_text = self.fmtText(.tray_summary, .{self.summary_text});

        self.service_text = self.internText(format.serviceText(self.capabilities));
    }

    fn renderTrayProviderHeaders(self: *ViewState) void {
        self.tray_provider_headers[@intFromEnum(domain.Provider.codex)] = self.internText(copy.text(.codex_accounts_header));
    }

    fn displayLabel(self: *ViewState, row: *const AccountView, provider_ordinal: u32) []const u8 {
        const count = if (row.provider == .claude) self.claude_count else self.codex_count;
        var default_label_buffer: [max_line_bytes]u8 = undefined;
        var default_label_writer = std.Io.Writer.fixed(&default_label_buffer);
        copy.write(&default_label_writer, .default_account_label, .{format.providerName(row.provider)});
        const default_label = default_label_writer.buffered();
        if (count > 1 and std.mem.eql(u8, row.label, default_label)) {
            return self.fmtText(.numbered_account_label, .{ row.label, provider_ordinal });
        }
        return row.label;
    }

    fn renderAttentionText(self: *ViewState, row: *const AccountView) []const u8 {
        var scratch: [max_line_bytes]u8 = undefined;
        var line: [max_line_bytes]u8 = undefined;
        var writer = std.Io.Writer.fixed(&line);
        if (row.last_attempt_code.len != 0) {
            writer.writeAll(format.attemptMessage(row.last_attempt_code)) catch {};
        } else {
            const wording = switch (row.freshness) {
                .reauth_required => copy.text(.attention_sign_in_again),
                .usage_unavailable => copy.text(.attention_usage_unavailable),
                else => copy.text(.attention_refresh_failed),
            };
            writer.writeAll(wording) catch {};
        }
        if (row.last_success_at_unix_s) |at| {
            copy.write(&writer, .last_good_reading, .{format.formatLocal(&scratch, at, self.time_zone)});
        }
        return self.internText(writer.buffered());
    }

    fn overviewIndexOf(self: *const ViewState, row_index: u32) ?usize {
        for (self.account_rows[0..self.account_row_count], 0..) |row, position| {
            if (row.index == row_index) return position;
        }
        return null;
    }

    fn renderInspector(self: *ViewState, options: RenderOptions) void {
        const selected = options.selected orelse return;
        if (selected >= self.row_count) return;
        const row = &self.rows[selected];
        var absolute: [max_line_bytes]u8 = undefined;
        var relative: [max_line_bytes]u8 = undefined;

        const overview = &self.account_rows[self.overviewIndexOf(selected) orelse 0];
        var inspector: Inspector = .{ .present = true, .index = selected };
        inspector.title = overview.title;
        inspector.can_reset = overview.can_reset;
        inspector.reset_label = overview.reset_label;

        inspector.freshness_line = blk: {
            if (row.last_success_at_unix_s) |at| {
                break :blk self.fmtText(.updated_freshness, .{
                    format.mediumLocal(&absolute, at, self.time_zone),
                    format.freshnessPhrase(row.freshness),
                });
            }
            break :blk self.internText(format.freshnessText(row.freshness));
        };
        inspector.attention = row.needsAttention();
        if (inspector.attention) inspector.attention_text = self.renderAttentionText(row);
        inspector.busy = row.operation_in_flight or row.queued;
        inspector.busy_label = self.internText(if (row.operation_in_flight) copy.text(.refreshing_ellipsis) else copy.text(.queued));
        inspector.needs_auth = row.auth_state != .connected;

        inspector.needs_keychain_repair =
            std.mem.eql(u8, row.last_attempt_code, "keychain-access-repair-required");
        inspector.no_usage_text = self.internText(if (row.has_snapshot)
            copy.text(.no_usage_in_snapshot)
        else
            copy.text(.no_saved_snapshot_yet_sentence));
        if (row.provider == .codex and row.has_snapshot) {
            inspector.usage_source_text = self.internText(copy.text(.codex_usage_api));
        }

        if (row.proxy_mode) {
            inspector.uses_proxy = true;
            inspector.failover_can_switch = row.proxy_can_switch;

            inspector.failover_state = if (row.proxy_active)
                if (row.proxy_in_flight != 0)
                    self.fmtText(.active_in_flight, .{row.proxy_in_flight})
                else
                    self.internText(copy.text(.active))
            else switch (row.proxy_state) {
                .cooldown => if (row.proxy_cooldown_until_unix_s) |until|
                    self.fmtText(.cooldown_until, .{
                        format.shortLocal(&absolute, self.now_unix_s, until, self.time_zone),
                        format.remainingPhrase(&relative, until - self.now_unix_s),
                    })
                else
                    self.internText(copy.text(.proxy_cooldown)),
                .paused => if (row.proxy_in_flight != 0)
                    self.fmtText(.paused_draining, .{row.proxy_in_flight})
                else
                    self.internText(copy.text(.proxy_paused)),
                else => self.internText(proxyStateText(row.proxy_state)),
            };
            inspector.failover_action = if (row.proxy_can_switch)
                self.internText(copy.text(.use_in_failover_proxy))
            else
                self.internText("");
        }

        for (row.windows[0..row.window_count], 0..) |window, window_index| {
            const listed = switch (row.provider) {
                .codex => codexInspectorWindowListed(
                    row.plan_label,
                    row.windows[0..row.window_count],
                    window_index,
                    self.codex_show_model_limits,
                ),
                .claude => window.kind != .other,
            };
            if (!listed) continue;
            const reset_line = if (window.reset_at_unix_s) |at|
                self.fmtText(.reset_phrase, .{format.mediumLocal(&absolute, at, self.time_zone)})
            else
                self.internText(copy.text(.reset_time_not_reported_title));
            var label_scratch: [max_line_bytes]u8 = undefined;
            self.usage_rows[self.usage_count] = .{
                .key = @intCast(self.usage_count + 1),
                .label = self.internText(format.humanizeWindowLabel(&label_scratch, window.label)),
                .percent_text = self.fmtText(.percent, .{window.used_percent}),
                .fraction = window.fraction,
                .has_meter = true,
                .reset_line = reset_line,
            };
            self.usage_count += 1;
        }

        if (row.provider == .codex) {
            inspector.has_credits = true;
            if (row.pending_reset_attempt) {
                inspector.credit_value = self.internText(copy.text(.reset_unconfirmed));
                inspector.credit_note = self.internText(
                    copy.text(.reset_unconfirmed_note),
                );
                inspector.has_credit_note = true;
                inspector.credit_offer = .review;
            } else if (row.unsent_reset_attempt) {
                inspector.credit_value = self.internText(copy.text(.reset_not_sent));
                inspector.credit_note = self.internText(
                    copy.text(.reset_not_sent_note),
                );
                inspector.has_credit_note = true;
                inspector.credit_offer = .review;
            } else if (row.reset_credit_count) |count| {
                inspector.credit_value = self.fmtText(.credits_available, .{count});
                const detailed = row.credit_detail_status == .detailed and
                    row.credit_detail_count == count;
                if (count > 0 and !detailed) {
                    inspector.credit_note = self.internText(copy.text(.credit_detail_mismatch));
                    inspector.has_credit_note = true;
                }
                if (row.resetIsOfferable()) inspector.credit_offer = .use_one;
            } else {
                inspector.credit_value = self.internText(copy.text(.not_reported));
            }
        }

        inspector.evidence_line = blk: {
            if (row.last_attempt_at_unix_s) |attempt| {
                const newer = row.last_success_at_unix_s == null or attempt > row.last_success_at_unix_s.?;
                const failed = row.needsAttention() or row.last_attempt_code.len != 0 or row.freshness == .refresh_deferred;
                if (newer and failed and !row.operation_in_flight) {
                    if (row.freshness == .refresh_deferred) {
                        break :blk self.fmtText(.evidence_deferred, .{format.mediumLocal(&absolute, attempt, self.time_zone)});
                    }
                    const reason = if (row.last_attempt_code.len != 0)
                        format.attemptReason(row.last_attempt_code)
                    else
                        format.freshnessPhrase(row.freshness);
                    break :blk self.fmtText(.evidence_failed, .{ format.mediumLocal(&absolute, attempt, self.time_zone), reason });
                }
            }
            if (row.last_success_at_unix_s) |at| break :blk self.internText(format.mediumLocal(&absolute, at, self.time_zone));
            break :blk self.internText(copy.text(.freshness_never));
        };
        inspector.plan_line = if (row.plan_label.len != 0)
            row.plan_label
        else
            self.internText(copy.text(.not_reported));

        const proxy_account: ?*const ProxyAccountFact = if (row.proxy_mode)
            if (self.proxyIndexOfAccount(row.account_id)) |index| &self.proxy_accounts[index] else null
        else
            null;
        inspector.connection_line = blk: {
            if (proxy_account) |account| {
                const index = self.proxyIndexOfAccount(row.account_id).?;
                if (self.proxy_token_refresh_failed[index]) break :blk self.internText(copy.text(.token_refresh_failed));
                if (account.token_expires_at_unix_s) |expires_at| {
                    break :blk self.fmtText(.token_valid_until, .{format.mediumLocal(&absolute, expires_at, self.time_zone)});
                }
            }
            var line: [max_line_bytes]u8 = undefined;
            var writer = std.Io.Writer.fixed(&line);
            writer.writeAll(format.authStateText(row.auth_state)) catch {};
            if (!row.enabled) writer.writeAll(copy.text(.connection_disabled_suffix)) catch {};
            if (row.proxy_mode and row.proxy_state == .paused) writer.writeAll(copy.text(.connection_paused_suffix)) catch {};
            break :blk self.internText(writer.buffered());
        };

        self.inspector = inspector;
    }
};

fn sameReportedReset(left: WindowView, right: WindowView) bool {
    const left_at = left.reset_at_unix_s orelse return false;
    const right_at = right.reset_at_unix_s orelse return false;
    return left_at == right_at;
}

fn codexInspectorWindowListed(
    plan_label: []const u8,
    windows: []const WindowView,
    candidate_index: usize,
    show_model_limits: bool,
) bool {
    const candidate = windows[candidate_index];
    switch (candidate.kind) {
        .model_scoped => if (!show_model_limits) return false,
        .session => if (ui_format.codexPlanClass(plan_label) == .weekly_only) return false,
        .weekly => {},
        .other => {
            for (windows, 0..) |typed, index| {
                if (index == candidate_index or typed.kind == .other) continue;
                if (sameReportedReset(candidate, typed) and
                    candidate.used_percent == typed.used_percent)
                {
                    return false;
                }
            }
        },
    }

    for (windows[0..candidate_index]) |previous| {
        if (candidate.kind == .model_scoped) {
            if (previous.kind == .model_scoped and
                std.mem.eql(u8, previous.label, candidate.label) and
                previous.reset_at_unix_s == candidate.reset_at_unix_s and
                previous.used_percent == candidate.used_percent)
            {
                return false;
            }
            continue;
        }

        if (previous.kind == candidate.kind and sameReportedReset(candidate, previous)) return false;
    }
    return true;
}

fn internInto(buffer: []u8, len: *usize, value: []const u8) []const u8 {
    if (value.len == 0) return buffer[len.*..len.*];
    const room = buffer.len - len.*;
    const take = @min(value.len, room);
    if (take == 0) return buffer[len.*..len.*];
    const start = len.*;
    @memcpy(buffer[start..][0..take], value[0..take]);
    len.* += take;
    return buffer[start..][0..take];
}

fn localPart(label: []const u8) []const u8 {
    return if (std.mem.indexOfScalar(u8, label, '@')) |at| label[0..at] else label;
}
