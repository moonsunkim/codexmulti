const std = @import("std");
const account_registry = @import("account_registry.zig");
const proxy_control = @import("proxy_control_client.zig");
const runtime_paths = @import("runtime_paths.zig");
const strings = @import("strings.zig");
pub const domain = @import("domain.zig");
pub const ui_model = @import("ui_model.zig");

pub const max_intent_json_bytes: usize = 16 * 1024;
pub const max_effects: usize = 8;
pub const max_effect_text_bytes: usize = 2048;

pub const starting_text = "Starting…";
pub const quit_label = "Quit";
pub const tray_refresh_usage_label = "Refresh Usage";
pub const tray_open_in_settings_label = "Show Account…";
pub const tray_help_text = "CodexMulti — saved usage and CLI accounts";
pub const proxy_empty_unattached_text = "Proxy control is not attached.";
pub const proxy_empty_attached_text = "No proxy accounts have been read yet. Use Refresh failover status in the … menu to read the failover order from the proxy.";

pub const add_account_title = "Add Codex account";
pub const add_account_explanation_text = "Name this account before opening the browser to sign in.";
pub const add_account_confirm_label = "Sign in…";
pub const add_account_cancel_label = "Cancel";
pub const add_account_progress_text = "Add account in progress · Codex";
pub const add_account_invalid_label_text = "Enter an account name before continuing.";

pub const MoveAccountRequest = struct {
    account_id: []const u8,
    target_account_id: []const u8,
};

pub fn busySuffixText(view: *const ui_model.ViewState) []const u8 {
    return if (view.busy_count != 0 or view.proxy_work != .idle) " · refreshing" else "";
}

pub fn proxyEmptyText(view: *const ui_model.ViewState) []const u8 {
    return if (view.capabilities.proxy_control) proxy_empty_attached_text else proxy_empty_unattached_text;
}

pub fn traySummaryLine(row: *const ui_model.AccountView, buffer: []u8) []const u8 {
    const plan = if (row.plan_label.len != 0) row.plan_label else "Account";
    return std.fmt.bufPrint(buffer, "{s} · {s}", .{ plan, ui_model.providerName(row.provider) }) catch "";
}

pub fn inspectorUpdatedAgoText(view: *const ui_model.ViewState, buffer: []u8) []const u8 {
    const format = ui_model.Localized.init(view.resolved_language);
    if (!view.inspector.present) return "";
    const row = view.rowAt(view.inspector.index) orelse return "";
    const at = row.last_success_at_unix_s orelse return format.freshnessPhrase(row.freshness);
    if (row.freshness == .as_of) return format.agoPhrase(buffer, view.now_unix_s, at);
    var ago_buffer: [ui_model.max_line_bytes]u8 = undefined;
    return std.fmt.bufPrint(buffer, "{s} · {s}", .{
        format.agoPhrase(&ago_buffer, view.now_unix_s, at),
        format.freshnessPhrase(row.freshness),
    }) catch "";
}

pub const Intent = union(enum) {
    set_appearance: ui_model.Appearance,
    set_language: ui_model.SetLanguage,
    set_codex_usage_window: ui_model.CodexUsageWindow,
    set_codex_show_model_limits: bool,
    set_launch_at_login: bool,
    report_launch_at_login_registration_failure: bool,
    set_auto_refresh: u16,
    open_details,
    quit_app,
    open_account: []const u8,
    tab_accounts,
    tab_failover,
    open_toolbar_menu,
    close_toolbar_menu,
    toggle_account: u32,
    open_row_menu: u32,
    close_row_menu,
    open_proxy_row_menu: u32,
    close_proxy_row_menu,
    toggle_proxy_settings,
    copy_diagnostics: u32,
    diagnostics_copied: bool,
    claude_tray_weekly,
    claude_tray_session,
    dismiss_notice,
    refresh_proxy_status,
    sync_proxy_config,
    pause_proxy_account: u32,
    resume_proxy_account: u32,
    begin_proxy_switch: u32,
    begin_clear_cooldown: u32,
    confirm_clear_cooldown,
    cancel_clear_cooldown,
    save_proxy_settings: ui_model.ProxySettingsDraft,
    install_proxy_service,
    repair_proxy_service,
    stop_proxy_service,
    set_proxy_enabled: bool,
    enable_codex_routing: bool,
    disable_codex_routing,
    refresh_all,
    refresh_account: u32,
    refresh_account_id: []const u8,
    move_account: MoveAccountRequest,
    begin_failover_switch: u32,
    begin_failover_switch_id: []const u8,
    confirm_failover_switch,
    cancel_failover_switch,
    pause_failover_account: u32,
    begin_clear_cooldown_account: u32,
    reauthenticate: u32,
    add_claude_account,
    add_codex_account,
    begin_add_account,
    commit_add_account: []const u8,
    cancel_add_account,
    begin_rename: u32,
    commit_rename: []const u8,
    cancel_rename,
    begin_remove: u32,
    confirm_remove,
    finish_mapped_remove,
    cancel_remove,
    begin_reset: u32,
    acknowledge_reset,
    confirm_reset,
    retry_reset,
    cancel_reset,
};

pub const EffectKind = enum { show_settings, quit, clipboard };

pub const Effect = struct {
    kind: EffectKind = .show_settings,
    text_buffer: [max_effect_text_bytes]u8 = @splat(0),
    text_len: usize = 0,

    pub fn text(self: *const Effect) []const u8 {
        return self.text_buffer[0..self.text_len];
    }
};

pub const Effects = struct {
    items: [max_effects]Effect = @splat(.{}),
    len: usize = 0,

    pub fn slice(self: *const Effects) []const Effect {
        return self.items[0..self.len];
    }

    pub fn clear(self: *Effects) void {
        for (self.items[0..self.len]) |*item| {
            std.crypto.secureZero(u8, item.text_buffer[0..item.text_len]);
            item.* = .{};
        }
        self.len = 0;
    }

    fn append(self: *Effects, effect: Effect) void {
        if (self.len >= self.items.len) return;
        self.items[self.len] = effect;
        self.len += 1;
    }

    pub fn showSettings(self: *Effects) void {
        self.append(.{ .kind = .show_settings });
    }

    pub fn quit(self: *Effects) void {
        self.append(.{ .kind = .quit });
    }

    pub fn clipboard(self: *Effects, value: []const u8) void {
        var effect: Effect = .{ .kind = .clipboard };
        copyInto(&effect.text_buffer, &effect.text_len, value);
        self.append(effect);
    }
};

pub const RemoveFlow = struct {
    open: bool = false,
    row: u32 = 0,
    uses_proxy: bool = false,
    pause_requested: bool = false,
    status_revision_at_pause: u64 = 0,
    label_buffer: [account_registry.max_label_bytes]u8 = @splat(0),
    label_len: usize = 0,
    account_id_buffer: [account_registry.max_id_bytes]u8 = @splat(0),
    account_id_len: usize = 0,

    pub fn label(self: *const RemoveFlow) []const u8 {
        return self.label_buffer[0..self.label_len];
    }
    pub fn accountId(self: *const RemoveFlow) []const u8 {
        return self.account_id_buffer[0..self.account_id_len];
    }
};

pub const ClearCooldownFlow = struct {
    open: bool = false,
    row: u32 = 0,
    label_buffer: [account_registry.max_label_bytes]u8 = @splat(0),
    label_len: usize = 0,
    account_id_buffer: [account_registry.max_id_bytes]u8 = @splat(0),
    account_id_len: usize = 0,

    pub fn label(self: *const ClearCooldownFlow) []const u8 {
        return self.label_buffer[0..self.label_len];
    }
    pub fn accountId(self: *const ClearCooldownFlow) []const u8 {
        return self.account_id_buffer[0..self.account_id_len];
    }
};

pub const RenameFlow = struct {
    open: bool = false,
    row: u32 = 0,
    initial_label_buffer: [account_registry.max_label_bytes]u8 = @splat(0),
    initial_label_len: usize = 0,
    account_id_buffer: [account_registry.max_id_bytes]u8 = @splat(0),
    account_id_len: usize = 0,

    pub fn initialLabel(self: *const RenameFlow) []const u8 {
        return self.initial_label_buffer[0..self.initial_label_len];
    }
    pub fn accountId(self: *const RenameFlow) []const u8 {
        return self.account_id_buffer[0..self.account_id_len];
    }
};

pub const AddAccountFlow = struct {
    open: bool = false,
    in_flight: bool = false,
    baseline_row_count: usize = 0,
    label_buffer: [account_registry.max_label_bytes]u8 = @splat(0),
    label_len: usize = 0,
    account_id_buffer: [account_registry.max_id_bytes]u8 = @splat(0),
    account_id_len: usize = 0,
    error_buffer: [ui_model.max_line_bytes]u8 = @splat(0),
    error_len: usize = 0,

    pub fn initialLabel(self: *const AddAccountFlow) []const u8 {
        return self.label_buffer[0..self.label_len];
    }

    pub fn accountId(self: *const AddAccountFlow) []const u8 {
        return self.account_id_buffer[0..self.account_id_len];
    }

    pub fn errorText(self: *const AddAccountFlow) []const u8 {
        return self.error_buffer[0..self.error_len];
    }

    pub fn confirmEnabled(self: *const AddAccountFlow) bool {
        if (!self.open or self.in_flight) return false;
        const label = trimmedLabel(self.initialLabel());
        if (label.len == 0) return false;
        account_registry.validateLabel(label) catch return false;
        return true;
    }

    fn failWithOutcome(self: *AddAccountFlow, outcome: ui_model.CommandOutcome) void {
        var notice: ui_model.Notice = .{};
        notice.setOutcome("Add account", "Codex", outcome);
        copyInto(&self.error_buffer, &self.error_len, notice.text());
        self.open = false;
        self.in_flight = false;
    }

    fn observe(self: *AddAccountFlow, view: *const ui_model.ViewState) void {
        if (!self.in_flight) return;
        if (self.account_id_len == 0) {
            var index = @min(self.baseline_row_count, view.row_count);
            while (index < view.row_count) : (index += 1) {
                const row = view.rowAt(index) orelse break;
                if (row.provider != .codex or !std.mem.eql(u8, row.label, self.initialLabel())) continue;
                copyInto(&self.account_id_buffer, &self.account_id_len, row.account_id);
                break;
            }
        }
        if (self.account_id_len == 0) return;
        const index = view.indexOfAccount(self.accountId()) orelse return;
        const row = view.rowAt(index) orelse return;
        if (row.operation_in_flight or row.queued) return;
        if (row.last_attempt_code.len != 0) {
            self.failWithOutcome(.failed);
            return;
        }
        if (row.last_attempt_at_unix_s != null or row.auth_state == .connected) self.* = .{};
    }
};

pub const FailoverSwitchFlow = struct {
    open: bool = false,
    row: u32 = 0,
    account_id_buffer: [account_registry.max_id_bytes]u8 = @splat(0),
    account_id_len: usize = 0,
    target_label_buffer: [account_registry.max_label_bytes]u8 = @splat(0),
    target_label_len: usize = 0,

    pub fn accountId(self: *const FailoverSwitchFlow) []const u8 {
        return self.account_id_buffer[0..self.account_id_len];
    }
    pub fn targetLabel(self: *const FailoverSwitchFlow) []const u8 {
        return self.target_label_buffer[0..self.target_label_len];
    }
};

pub const Model = struct {
    view: ui_model.ViewState = .{},
    service: ui_model.ServicePort = .{},
    now_unix_s: i64 = 0,
    time_zone: ui_model.TimeZone = .system,
    settings_tab: ui_model.SettingsTab = .accounts,
    expanded: ?u32 = null,
    row_menu: ?u32 = null,
    proxy_row_menu: ?u32 = null,
    toolbar_menu_open: bool = false,
    proxy_settings_expanded: bool = false,
    claude_tray_window: ui_model.ClaudeTrayWindow = .weekly,
    notice: ui_model.Notice = .{},
    add_account: AddAccountFlow = .{},
    reset: ui_model.ResetFlow = .{},
    remove: RemoveFlow = .{},
    rename: RenameFlow = .{},
    failover_switch: FailoverSwitchFlow = .{},
    clear_cooldown: ClearCooldownFlow = .{},

    pub fn footerText(model: *const Model) []const u8 {
        if (!model.view.capabilities.refresh) return model.view.service_text;
        return model.view.summary_text;
    }
    pub fn fleetSummary(model: *const Model) []const u8 {
        return model.view.summary_text;
    }
    pub fn serviceSummary(model: *const Model) []const u8 {
        return model.view.service_text;
    }
    pub fn usageRows(model: *const Model) []const ui_model.UsageRow {
        return model.view.usageSlice();
    }
    pub fn proxyNodeHint(model: *const Model) []const u8 {
        return model.view.proxy_node_hint_text;
    }
    pub fn proxyBusy(model: *const Model) bool {
        return model.view.proxy_work != .idle;
    }
    pub fn proxyCanRefresh(model: *const Model) bool {
        return model.view.capabilities.proxy_control and !model.proxyBusy();
    }
    pub fn proxyCanSync(model: *const Model) bool {
        _ = model;

        return false;
    }
    pub fn removeCanFinish(model: *const Model) bool {
        if (!model.remove.open or !model.remove.uses_proxy or !model.remove.pause_requested) return false;
        if (model.view.proxy_reachability != .reachable or !model.view.proxy_config_path_matches) return false;
        if (model.view.proxy_success_revision <= model.remove.status_revision_at_pause) return false;
        for (model.view.proxyRowSlice()) |row| {
            if (std.mem.eql(u8, row.app_id, model.remove.accountId())) {
                return row.mapped and row.state == .paused and row.in_flight == 0;
            }
        }
        return false;
    }
    pub fn tabAccounts(model: *const Model) bool {
        return model.settings_tab == .accounts;
    }
    pub fn tabFailover(model: *const Model) bool {
        return model.settings_tab == .failover;
    }
    pub fn toolbarMenuOpen(model: *const Model) bool {
        return model.toolbar_menu_open;
    }
    pub fn claudeAccountRows(model: *const Model) []const ui_model.AccountRowView {
        return model.view.claudeAccountRowSlice();
    }
    pub fn codexAccountRows(model: *const Model) []const ui_model.AccountRowView {
        return model.view.codexAccountRowSlice();
    }
    pub fn hasCodexAccounts(model: *const Model) bool {
        return model.view.codex_count != 0;
    }
    pub fn claudeGroupTitle(model: *const Model) []const u8 {
        return model.view.claude_group_title;
    }
    pub fn codexGroupTitle(model: *const Model) []const u8 {
        return model.view.codex_group_title;
    }
    pub fn claudeGroupSummary(model: *const Model) []const u8 {
        return model.view.claude_group_summary;
    }
    pub fn codexGroupSummary(model: *const Model) []const u8 {
        return model.view.codex_group_summary;
    }
    pub fn toolbarStatusText(model: *const Model) []const u8 {
        return model.view.toolbar_status_text;
    }
    pub fn headerFreshText(model: *const Model) []const u8 {
        return model.view.header_fresh_text;
    }
    pub fn headerFailedText(model: *const Model) []const u8 {
        return model.view.header_failed_text;
    }
    pub fn headerHasFailures(model: *const Model) bool {
        return model.view.header_has_failures;
    }
    pub fn proxyPillVisible(model: *const Model) bool {
        return model.view.capabilities.proxy_control;
    }
    pub fn proxyPillText(model: *const Model) []const u8 {
        return model.view.proxy_pill_text;
    }
    pub fn proxyPillOk(model: *const Model) bool {
        return model.view.proxy_pill_ok;
    }
    pub fn proxyPillBad(model: *const Model) bool {
        return model.view.proxy_pill_bad;
    }
    pub fn proxyTableRows(model: *const Model) []const ui_model.ProxyTableRow {
        return model.view.proxyRowSlice();
    }
    pub fn proxyConfigNeedsSync(model: *const Model) bool {
        return model.view.proxy_sync_state == .needed;
    }
    pub fn proxyShowsBanner(model: *const Model) bool {
        return model.view.proxy_banner_text.len != 0;
    }
    pub fn proxyBannerText(model: *const Model) []const u8 {
        return model.view.proxy_banner_text;
    }
    pub fn proxySettingsSummary(model: *const Model) []const u8 {
        return model.view.proxy_settings_summary_text;
    }
    pub fn proxySettingsExpanded(model: *const Model) bool {
        return model.proxy_settings_expanded;
    }
    pub fn proxySettingsChevron(model: *const Model) []const u8 {
        return if (model.proxy_settings_expanded) "chevron-down" else "chevron-right";
    }
    pub fn inspectorTitle(model: *const Model) []const u8 {
        return model.view.inspector.title;
    }
    pub fn inspectorFreshness(model: *const Model) []const u8 {
        return model.view.inspector.freshness_line;
    }
    pub fn inspectorAttention(model: *const Model) bool {
        return model.view.inspector.attention;
    }
    pub fn inspectorAttentionText(model: *const Model) []const u8 {
        return model.view.inspector.attention_text;
    }
    pub fn inspectorNoUsage(model: *const Model) []const u8 {
        return model.view.inspector.no_usage_text;
    }
    pub fn inspectorFailoverTitle(model: *const Model) []const u8 {
        return model.view.inspector.failover_title;
    }
    pub fn inspectorFailoverState(model: *const Model) []const u8 {
        return model.view.inspector.failover_state;
    }
    pub fn inspectorFailoverAction(model: *const Model) []const u8 {
        return model.view.inspector.failover_action;
    }
    pub fn inspectorFailoverCanSwitch(model: *const Model) bool {
        return model.view.inspector.failover_can_switch;
    }
    pub fn inspectorUsesProxy(model: *const Model) bool {
        return model.view.inspector.uses_proxy;
    }
    pub fn inspectorHasCredits(model: *const Model) bool {
        return model.view.inspector.has_credits;
    }
    pub fn creditValue(model: *const Model) []const u8 {
        return model.view.inspector.credit_value;
    }
    pub fn creditHasNote(model: *const Model) bool {
        return model.view.inspector.has_credit_note;
    }
    pub fn creditNote(model: *const Model) []const u8 {
        return model.view.inspector.credit_note;
    }
    pub fn creditOffersUse(model: *const Model) bool {
        return model.view.inspector.credit_offer == .use_one;
    }
    pub fn creditOffersReview(model: *const Model) bool {
        return model.view.inspector.credit_offer == .review;
    }
    pub fn detailEvidence(model: *const Model) []const u8 {
        return model.view.inspector.evidence_line;
    }
    pub fn detailPlan(model: *const Model) []const u8 {
        return model.view.inspector.plan_line;
    }
    pub fn detailConnection(model: *const Model) []const u8 {
        return model.view.inspector.connection_line;
    }
    pub fn hasAccounts(model: *const Model) bool {
        return model.view.row_count != 0;
    }
    pub fn hasClaudeAccounts(model: *const Model) bool {
        return model.view.claude_count != 0;
    }
    pub fn hasNotice(model: *const Model) bool {
        return model.notice.kind != .none;
    }
    pub fn addAccountIsOpen(model: *const Model) bool {
        return model.add_account.open;
    }
    pub fn addAccountInitialLabel(model: *const Model) []const u8 {
        return model.add_account.initialLabel();
    }
    pub fn addAccountConfirmEnabled(model: *const Model) bool {
        return model.add_account.confirmEnabled();
    }
    pub fn addAccountProgressText(model: *const Model) []const u8 {
        return if (model.add_account.in_flight) add_account_progress_text else "";
    }
    pub fn addAccountErrorText(model: *const Model) []const u8 {
        return model.add_account.errorText();
    }
    pub fn noticeIsBlocked(model: *const Model) bool {
        return model.notice.kind == .blocked;
    }
    pub fn noticeText(model: *const Model) []const u8 {
        return model.notice.text();
    }
    pub fn canRefresh(model: *const Model) bool {
        return model.view.capabilities.refresh;
    }
    pub fn canRefreshAll(model: *const Model) bool {
        return model.view.row_count != 0 and model.view.capabilities.refresh;
    }
    pub fn canManageAccounts(model: *const Model) bool {
        return model.view.capabilities.accounts;
    }
    pub fn failoverSwitchIsOpen(model: *const Model) bool {
        return model.failover_switch.open;
    }
    pub fn failoverSwitchTargetLabel(model: *const Model) []const u8 {
        return model.failover_switch.targetLabel();
    }
    pub fn resetIsOpen(model: *const Model) bool {
        return model.reset.isOpen();
    }
    pub fn resetIsReview(model: *const Model) bool {
        return model.reset.stage == .review;
    }
    pub fn resetIsArmed(model: *const Model) bool {
        return model.reset.stage == .armed;
    }
    pub fn resetIsBlocked(model: *const Model) bool {
        return model.reset.stage == .blocked;
    }
    pub fn resetIsDispatched(model: *const Model) bool {
        return model.reset.stage == .dispatched;
    }
    pub fn resetAwaitsReconciliation(model: *const Model) bool {
        return model.reset.awaitsReconciliation();
    }
    pub fn resetAccountLabel(model: *const Model) []const u8 {
        return model.reset.label();
    }
    pub fn resetAvailableCount(model: *const Model) u32 {
        return model.reset.available_count;
    }
    pub fn resetUsageText(model: *const Model) []const u8 {
        return model.reset.usageEvidence();
    }
    pub fn resetResetText(model: *const Model) []const u8 {
        return model.reset.resetEvidence();
    }
    pub fn resetBlockedText(model: *const Model) []const u8 {
        return strings.catalog(model.view.resolved_language).translateEnglish(model.reset.blockedText());
    }
    pub fn resetOutcomeText(model: *const Model) []const u8 {
        return strings.catalog(model.view.resolved_language).translateEnglish(model.reset.outcomeText());
    }
    pub fn resetShowsProxyClear(model: *const Model) bool {
        return model.reset.showsProxyClear();
    }
    pub fn resetProxyClearText(model: *const Model) []const u8 {
        return strings.catalog(model.view.resolved_language).translateEnglish(model.reset.proxyClearText());
    }
    pub fn removeIsOpen(model: *const Model) bool {
        return model.remove.open;
    }
    pub fn removeLabel(model: *const Model) []const u8 {
        return model.remove.label();
    }
    pub fn removeUsesProxy(model: *const Model) bool {
        return model.remove.uses_proxy;
    }
    pub fn removePauseRequested(model: *const Model) bool {
        return model.remove.pause_requested;
    }
    pub fn clearCooldownIsOpen(model: *const Model) bool {
        return model.clear_cooldown.open;
    }
    pub fn clearCooldownLabel(model: *const Model) []const u8 {
        return model.clear_cooldown.label();
    }
    pub fn renameIsOpen(model: *const Model) bool {
        return model.rename.open;
    }
    pub fn renameInitialLabel(model: *const Model) []const u8 {
        return model.rename.initialLabel();
    }
    pub fn renameDraft(model: *const Model) []const u8 {
        return model.renameInitialLabel();
    }
};

pub fn initialModel(time_zone: ui_model.TimeZone) Model {
    return .{ .time_zone = time_zone };
}

pub fn reproject(model: *Model) void {
    projectView(model);
    model.add_account.observe(&model.view);
    var follow_up_submitted = false;
    if (model.reset.stage == .dispatched) {
        var index: usize = 0;
        while (index < model.view.row_count) : (index += 1) {
            const row = model.view.rowAt(index) orelse break;
            if (std.mem.eql(u8, row.account_id, model.reset.accountId())) {
                const settle_before = model.reset.settle;
                const proxy_clear_before = model.reset.proxy_clear;
                model.reset.observe(row);

                if (settle_before == .seen and
                    model.reset.settle == .settled and
                    model.reset.proxy_clear == .none)
                {
                    model.reset.proxy_clear = resetProxyClearOutcome(model.service.submit(.{
                        .proxy_clear_cooldown = model.reset.accountId(),
                    }));
                    follow_up_submitted = true;
                } else if (settle_before == .settled and
                    row.reset_proxy_clear == .none and
                    proxy_clear_before != .none)
                {
                    model.reset.proxy_clear = proxy_clear_before;
                }
                if (proxy_clear_before == .pending and model.reset.proxy_clear == .failed) {
                    model.notice.setOutcome("Clear cooldown", model.reset.label(), .failed);
                }
                break;
            }
        }
    }

    if (follow_up_submitted) projectView(model);
    if (model.notice.kind == .pending and model.view.busy_count == 0 and !model.proxyBusy()) model.notice.clear();
    var changed = false;
    if (model.expanded) |index| if (index >= model.view.row_count) {
        model.expanded = null;
        changed = true;
    };
    if (model.row_menu) |index| if (index >= model.view.row_count) {
        model.row_menu = null;
        changed = true;
    };
    if (model.proxy_row_menu) |index| if (index >= model.view.proxy_row_count) {
        model.proxy_row_menu = null;
        changed = true;
    };
    if (changed) projectView(model);
}

fn resetProxyClearOutcome(outcome: ui_model.CommandOutcome) ui_model.ResetProxyClear {
    return switch (outcome) {
        .accepted_pending => .pending,
        .rejected_busy => .busy,
        .rejected_not_allowed => .@"unreachable",
        .rejected_unknown_account => .not_mapped,
        .none, .service_unavailable, .provider_cli_missing, .offer_unavailable, .failed => .failed,
    };
}

pub fn projectView(model: *Model) void {
    const options: ui_model.RenderOptions = .{
        .selected = model.expanded,
        .row_menu = model.row_menu,
        .proxy_row_menu = model.proxy_row_menu,
        .claude_tray_window = model.claude_tray_window,
    };
    model.service.project(&model.view, model.now_unix_s, model.time_zone, options);
    model.view.finish(options);
}

pub fn pump(model: *Model, now_unix_s: i64) void {
    model.service.pump(now_unix_s);
    model.now_unix_s = @divFloor(now_unix_s, 60) * 60;
    reproject(model);
    if (model.removeCanFinish()) {
        const outcome = model.service.submit(.{ .remove_account = model.remove.accountId() });
        model.notice.setOutcome("Remove", model.remove.label(), outcome);
        if (outcome.accepted()) model.remove = .{};
        reproject(model);
    }
}

pub fn update(model: *Model, intent: Intent, effects: *Effects) void {
    switch (intent) {
        .set_appearance => |appearance| {
            const outcome = model.service.submit(.{ .set_appearance = appearance });
            if (!outcome.accepted()) model.notice.setOutcome("Appearance", "app preference", outcome);
            reproject(model);
        },
        .set_language => |request| {
            const outcome = model.service.submit(.{ .set_language = request });
            const language_label = strings.catalog(model.view.resolved_language).text(.language_label);
            if (!outcome.accepted()) model.notice.setOutcome(language_label, language_label, outcome);
            reproject(model);
        },
        .set_codex_usage_window => |window| {
            const outcome = model.service.submit(.{ .set_codex_usage_window = window });
            if (!outcome.accepted()) model.notice.setOutcome("Usage shown", "Codex preference", outcome);
            reproject(model);
        },
        .set_codex_show_model_limits => |on| {
            const outcome = model.service.submit(.{ .set_codex_show_model_limits = on });
            if (!outcome.accepted()) model.notice.setOutcome("Per-model limits", "Codex preference", outcome);
            reproject(model);
        },
        .set_launch_at_login => |on| {
            const outcome = model.service.submit(.{ .set_launch_at_login = on });
            if (!outcome.accepted()) model.notice.setOutcome("Launch at login", "app preference", outcome);
            reproject(model);
        },
        .report_launch_at_login_registration_failure => |failed| {
            const outcome = model.service.submit(.{ .report_launch_at_login_registration_failure = failed });
            if (!outcome.accepted()) model.notice.setOutcome("Launch at login", "registration result", outcome);
            reproject(model);
        },
        .set_auto_refresh => |minutes| {
            const outcome = model.service.submit(.{ .set_auto_refresh = minutes });
            if (!outcome.accepted()) model.notice.setOutcome("Auto-refresh", "app preference", outcome);
            reproject(model);
        },
        .open_details => effects.showSettings(),
        .quit_app => effects.quit(),
        .open_account => |account_id| {
            const index = model.view.indexOfAccount(account_id) orelse return;
            model.settings_tab = .accounts;
            model.expanded = @intCast(index);
            model.row_menu = null;
            reproject(model);
            effects.showSettings();
        },
        .tab_accounts => switchTab(model, .accounts),
        .tab_failover => switchTab(model, .failover),
        .open_toolbar_menu => {
            model.row_menu = null;
            model.proxy_row_menu = null;
            model.toolbar_menu_open = true;
            reproject(model);
        },
        .close_toolbar_menu => {
            model.toolbar_menu_open = false;
            reproject(model);
        },
        .toggle_account => |index| {
            if (index >= model.view.row_count) return;
            model.expanded = if (model.expanded != null and model.expanded.? == index) null else index;
            model.row_menu = null;
            reproject(model);
        },
        .open_row_menu => |index| {
            if (index >= model.view.row_count) return;
            model.row_menu = index;
            model.proxy_row_menu = null;
            model.toolbar_menu_open = false;
            reproject(model);
        },
        .close_row_menu => {
            model.row_menu = null;
            reproject(model);
        },
        .open_proxy_row_menu => |index| {
            if (index >= model.view.proxy_row_count) return;
            model.proxy_row_menu = index;
            model.row_menu = null;
            model.toolbar_menu_open = false;
            reproject(model);
        },
        .close_proxy_row_menu => {
            model.proxy_row_menu = null;
            reproject(model);
        },
        .toggle_proxy_settings => model.proxy_settings_expanded = !model.proxy_settings_expanded,
        .copy_diagnostics => |index| {
            model.row_menu = null;
            const row = model.view.rowAt(index) orelse {
                reproject(model);
                return;
            };
            var buffer: [max_effect_text_bytes]u8 = undefined;
            effects.clipboard(diagnosticsText(row, model.time_zone, &buffer));
            reproject(model);
        },
        .diagnostics_copied => |ok| {
            if (ok) model.notice.set(.info, "Diagnostics copied to the clipboard.", .{}) else model.notice.set(.blocked, "Diagnostics were not copied: the clipboard refused the request.", .{});
        },
        .claude_tray_weekly, .claude_tray_session => {},
        .dismiss_notice => model.notice.clear(),
        .refresh_proxy_status => {
            model.toolbar_menu_open = false;
            model.notice.setOutcome("Proxy status", "the configured loopback service", model.service.submit(.proxy_refresh_status));
            reproject(model);
        },
        .sync_proxy_config => {
            model.toolbar_menu_open = false;

            model.notice.setOutcome("Refresh", "all Codex accounts", model.service.submit(.refresh_all));
            reproject(model);
        },
        .pause_proxy_account => |index| {
            model.proxy_row_menu = null;
            if (index >= model.view.proxy_row_count) return;
            const row = model.view.proxy_rows[index];
            if (!row.can_pause or row.app_id.len == 0) return;
            model.notice.setOutcome("Proxy pause", row.label, model.service.submit(.{ .proxy_pause_account = row.app_id }));
            reproject(model);
        },
        .resume_proxy_account => |index| {
            model.proxy_row_menu = null;
            if (index >= model.view.proxy_row_count) return;
            const row = model.view.proxy_rows[index];
            if (!row.can_resume or row.app_id.len == 0) return;
            model.notice.setOutcome("Proxy resume", row.label, model.service.submit(.{ .proxy_reload_account = row.app_id }));
            reproject(model);
        },
        .begin_proxy_switch => |index| {
            model.proxy_row_menu = null;
            if (index >= model.view.proxy_row_count) return;
            const row = model.view.proxy_rows[index];
            if (!row.can_switch or row.app_id.len == 0) return;
            const account_index = model.view.indexOfAccount(row.app_id) orelse return;
            update(model, .{ .begin_failover_switch = @intCast(account_index) }, effects);
        },
        .begin_clear_cooldown => |index| {
            model.proxy_row_menu = null;
            if (index >= model.view.proxy_row_count) return;
            const row = model.view.proxy_rows[index];
            if (!row.can_clear_cooldown or row.app_id.len == 0) return;
            model.clear_cooldown = .{ .open = true, .row = index };
            copyInto(&model.clear_cooldown.label_buffer, &model.clear_cooldown.label_len, row.label);
            copyInto(&model.clear_cooldown.account_id_buffer, &model.clear_cooldown.account_id_len, row.app_id);
            reproject(model);
        },
        .confirm_clear_cooldown => {
            if (!model.clear_cooldown.open) return;
            var allowed = false;
            for (model.view.proxyRowSlice()) |row| if (std.mem.eql(u8, row.app_id, model.clear_cooldown.accountId())) {
                allowed = row.can_clear_cooldown;
            };
            if (!allowed) {
                model.clear_cooldown = .{};
                reproject(model);
                return;
            }
            const outcome = model.service.submit(.{ .proxy_clear_cooldown = model.clear_cooldown.accountId() });
            model.notice.setOutcome("Clear proxy cooldown", model.clear_cooldown.label(), outcome);
            model.clear_cooldown = .{};
            reproject(model);
        },
        .cancel_clear_cooldown => {
            model.clear_cooldown = .{};
            reproject(model);
        },
        .save_proxy_settings => |draft| {
            const outcome = model.service.submit(.{ .save_proxy_settings = draft });
            model.notice.setOutcome("Proxy settings", "local control configuration", outcome);
            reproject(model);
        },
        .install_proxy_service => {
            model.notice.setOutcome("Proxy service", "install and start", model.service.submit(.install_proxy_service));
            reproject(model);
        },
        .repair_proxy_service => {
            model.notice.setOutcome("Proxy service", "repair and restart", model.service.submit(.repair_proxy_service));
            reproject(model);
        },
        .stop_proxy_service => {
            model.notice.setOutcome("Proxy service", "disable routing and stop", model.service.submit(.stop_proxy_service));
            reproject(model);
        },
        .set_proxy_enabled => |on| {
            model.notice.setOutcome(
                "Failover proxy",
                if (on) "turn on" else "turn off",
                model.service.submit(.{ .set_proxy_enabled = on }),
            );
            reproject(model);
        },
        .enable_codex_routing => |replace_conflicting| {
            model.notice.setOutcome("Codex routing", "enable failover routing", model.service.submit(.{ .enable_codex_routing = replace_conflicting }));
            reproject(model);
        },
        .disable_codex_routing => {
            model.notice.setOutcome("Codex routing", "restore direct routing", model.service.submit(.disable_codex_routing));
            reproject(model);
        },
        .refresh_all => {
            model.toolbar_menu_open = false;
            model.notice.setOutcome("Refresh all", "every enabled account", model.service.submit(.refresh_all));
            reproject(model);
        },
        .refresh_account => |index| {
            model.row_menu = null;
            const row = model.view.rowAt(index) orelse return;
            model.notice.setOutcome("Refresh", row.label, model.service.submit(.{ .refresh_account = row.account_id }));
            reproject(model);
        },
        .refresh_account_id => |account_id| {
            const index = model.view.indexOfAccount(account_id) orelse return;
            update(model, .{ .refresh_account = @intCast(index) }, effects);
        },
        .move_account => |move| {
            if (std.mem.eql(u8, move.account_id, move.target_account_id)) return;
            const source_index = model.view.indexOfAccount(move.account_id) orelse return;
            if (model.view.indexOfAccount(move.target_account_id) == null) return;
            const source = model.view.account_rows[source_index];
            model.notice.setOutcome("Account order", source.title, model.service.submit(.{ .move_account = .{
                .account_id = move.account_id,
                .target_account_id = move.target_account_id,
            } }));
            reproject(model);
        },
        .begin_failover_switch => |index| {
            model.row_menu = null;
            const row = model.view.rowAt(index) orelse return;
            if (!row.canSwitchProxy()) return;
            model.failover_switch = .{ .open = true, .row = index };
            copyInto(&model.failover_switch.account_id_buffer, &model.failover_switch.account_id_len, row.account_id);
            copyInto(&model.failover_switch.target_label_buffer, &model.failover_switch.target_label_len, row.label);
            reproject(model);
            effects.showSettings();
        },
        .begin_failover_switch_id => |account_id| {
            const index = model.view.indexOfAccount(account_id) orelse return;
            update(model, .{ .begin_failover_switch = @intCast(index) }, effects);
        },
        .confirm_failover_switch => {
            if (!model.failover_switch.open) return;
            const target = model.failover_switch.targetLabel();
            const index = model.view.indexOfAccount(model.failover_switch.accountId()) orelse {
                model.notice.setOutcome("Failover switch", target, .rejected_unknown_account);
                model.failover_switch = .{};
                return;
            };
            const row = model.view.rowAt(index).?;
            if (!row.canSwitchProxy()) {
                model.notice.setOutcome("Failover switch", target, .rejected_not_allowed);
                model.failover_switch = .{};
                return;
            }
            model.notice.setOutcome("Failover switch", target, model.service.submit(.{ .proxy_switch_account = row.account_id }));
            model.failover_switch = .{};
            reproject(model);
        },
        .cancel_failover_switch => model.failover_switch = .{},
        .pause_failover_account => |index| {
            model.row_menu = null;
            const proxy_index = proxyRowForAccount(model, index) orelse {
                reproject(model);
                return;
            };
            update(model, .{ .pause_proxy_account = proxy_index }, effects);
        },
        .begin_clear_cooldown_account => |index| {
            model.row_menu = null;
            const proxy_index = proxyRowForAccount(model, index) orelse {
                reproject(model);
                return;
            };
            update(model, .{ .begin_clear_cooldown = proxy_index }, effects);
        },
        .reauthenticate => |index| {
            model.row_menu = null;
            const row = model.view.rowAt(index) orelse return;
            model.notice.setOutcome("Reauthentication", row.label, model.service.submit(.{ .reauthenticate = row.account_id }));
            reproject(model);
        },
        .add_claude_account => {},
        .add_codex_account => {
            model.toolbar_menu_open = false;
            model.notice.setOutcome("Add account", "Codex", model.service.submit(.{ .add_account = .codex }));
            reproject(model);
        },
        .begin_add_account => {
            model.toolbar_menu_open = false;
            if (model.add_account.in_flight) return;
            model.add_account = .{ .open = true, .baseline_row_count = model.view.row_count };
            reproject(model);
        },
        .commit_add_account => |raw_label| {
            if (!model.add_account.open or model.add_account.in_flight) return;
            const label = trimmedLabel(raw_label);
            if (label.len == 0 or label.len > account_registry.max_label_bytes) {
                copyInto(&model.add_account.error_buffer, &model.add_account.error_len, add_account_invalid_label_text);
                return;
            }
            account_registry.validateLabel(label) catch {
                copyInto(&model.add_account.error_buffer, &model.add_account.error_len, add_account_invalid_label_text);
                return;
            };
            copyInto(&model.add_account.label_buffer, &model.add_account.label_len, label);
            model.add_account.error_len = 0;
            model.add_account.baseline_row_count = model.view.row_count;
            const outcome = model.service.addAccountLabeled(.codex, model.add_account.initialLabel());
            if (!outcome.accepted()) {
                model.add_account.failWithOutcome(outcome);
                reproject(model);
                return;
            }
            model.add_account.in_flight = true;
            reproject(model);
        },
        .cancel_add_account => {
            if (model.add_account.in_flight) return;
            model.add_account = .{};
            reproject(model);
        },
        .begin_rename => |index| {
            model.row_menu = null;
            const row = model.view.rowAt(index) orelse return;
            model.rename = .{ .open = true, .row = index };
            copyInto(&model.rename.account_id_buffer, &model.rename.account_id_len, row.account_id);
            copyInto(&model.rename.initial_label_buffer, &model.rename.initial_label_len, row.label);
            reproject(model);
        },
        .commit_rename => |label| {
            if (!model.rename.open) return;
            const outcome = model.service.submit(.{ .relabel = .{ .account_id = model.rename.accountId(), .label = label } });
            model.notice.setOutcome("Rename", label, outcome);
            model.rename = .{};
            reproject(model);
        },
        .cancel_rename => model.rename = .{},
        .begin_remove => |index| {
            model.row_menu = null;
            const row = model.view.rowAt(index) orelse return;
            model.remove = .{ .open = true, .row = index, .uses_proxy = row.proxy_mode, .status_revision_at_pause = model.view.proxy_success_revision };
            copyInto(&model.remove.label_buffer, &model.remove.label_len, row.label);
            copyInto(&model.remove.account_id_buffer, &model.remove.account_id_len, row.account_id);
            reproject(model);
        },
        .confirm_remove => {
            if (!model.remove.open) return;
            if (model.remove.uses_proxy) {
                const outcome = model.service.submit(.{ .proxy_pause_account = model.remove.accountId() });
                model.notice.setOutcome("Proxy pause before removal", model.remove.label(), outcome);
                if (outcome.accepted()) model.remove.pause_requested = true;
                reproject(model);
                return;
            }
            model.notice.setOutcome("Remove", model.remove.label(), model.service.submit(.{ .remove_account = model.remove.accountId() }));
            model.remove = .{};
            reproject(model);
        },
        .finish_mapped_remove => {
            if (!model.removeCanFinish()) return;
            const remove_outcome = model.service.submit(.{ .remove_account = model.remove.accountId() });
            if (!remove_outcome.accepted()) {
                model.notice.setOutcome("Remove", model.remove.label(), remove_outcome);
                reproject(model);
                return;
            }
            model.notice.setOutcome("Remove and sync", model.remove.label(), model.service.submit(.proxy_sync_config));
            model.remove = .{};
            reproject(model);
        },
        .cancel_remove => model.remove = .{},
        .begin_reset => |index| {
            model.row_menu = null;
            model.reset.open(&model.view, index);
            reproject(model);
        },
        .acknowledge_reset => _ = model.reset.acknowledge(),
        .confirm_reset => {
            const command = model.reset.commandForConfirmation(model.now_unix_s) orelse return;
            const outcome = model.service.submit(command);
            model.reset.recordOutcome(outcome);
            model.notice.setOutcome("Reset redemption", model.reset.label(), outcome);
            reproject(model);
        },
        .retry_reset => {
            const command = model.reset.commandForReconciliation() orelse return;
            const outcome = model.service.submit(command);
            model.reset.recordOutcome(outcome);
            model.notice.setOutcome("Reset reconciliation", model.reset.label(), outcome);
            reproject(model);
        },
        .cancel_reset => model.reset.cancel(),
    }
}

pub fn proxyRowForAccount(model: *const Model, index: u32) ?u32 {
    const row = model.view.rowAt(index) orelse return null;
    return @intCast(model.view.proxyIndexOfAccount(row.account_id) orelse return null);
}

pub fn switchTab(model: *Model, tab: ui_model.SettingsTab) void {
    model.settings_tab = tab;
    model.row_menu = null;
    model.proxy_row_menu = null;
    model.toolbar_menu_open = false;
    reproject(model);
}

pub fn diagnosticsText(row: *const ui_model.AccountView, time_zone: ui_model.TimeZone, buffer: []u8) []const u8 {
    var scratch: [ui_model.max_line_bytes]u8 = undefined;
    var duration: [ui_model.max_line_bytes]u8 = undefined;
    var writer = std.Io.Writer.fixed(buffer);
    writer.print("CodexMulti diagnostics\n", .{}) catch {};
    writer.print("account: {s}\n", .{row.label}) catch {};
    writer.print("provider: {s}\n", .{ui_model.providerName(row.provider)}) catch {};
    writer.print("account id: {s}\n", .{row.account_id}) catch {};
    writer.print("plan: {s}\n", .{if (row.plan_label.len != 0) row.plan_label else "not reported"}) catch {};
    writer.print("auth: {s}\n", .{ui_model.authStateText(row.auth_state)}) catch {};
    writer.print("freshness: {s}\n", .{ui_model.freshnessText(row.freshness)}) catch {};
    if (row.last_success_at_unix_s) |at| writer.print("last success: {s}\n", .{ui_model.formatLocal(&scratch, at, time_zone)}) catch {} else writer.print("last success: none\n", .{}) catch {};
    if (row.last_attempt_at_unix_s) |at| writer.print("last attempt: {s}\n", .{ui_model.formatLocal(&scratch, at, time_zone)}) catch {} else writer.print("last attempt: none\n", .{}) catch {};
    writer.print("last code: {s}\n", .{if (row.last_attempt_code.len != 0) row.last_attempt_code else "none"}) catch {};
    writer.print("snapshot: {s}\n", .{ui_model.snapshotStatusText(row.snapshot_status)}) catch {};
    if (row.snapshot_captured_at_unix_s) |at| writer.print("snapshot stored: {s}\n", .{ui_model.formatLocal(&scratch, at, time_zone)}) catch {};
    for (row.windows[0..row.window_count]) |window| {
        writer.print("window: {s}", .{window.label}) catch {};
        if (window.duration_minutes) |minutes| writer.print(" · {s}", .{ui_model.durationPhrase(&duration, minutes)}) catch {};
        writer.print(" · {d}%", .{window.used_percent}) catch {};
        if (window.reset_at_unix_s) |at| writer.print(" · resets {s}\n", .{ui_model.formatLocal(&scratch, at, time_zone)}) catch {} else writer.print(" · reset not reported\n", .{}) catch {};
    }
    return writer.buffered();
}

pub fn copyInto(buffer: []u8, len: *usize, value: []const u8) void {
    const take = @min(value.len, buffer.len);
    @memcpy(buffer[0..take], value[0..take]);
    len.* = take;
}

pub fn trimmedLabel(value: []const u8) []const u8 {
    return std.mem.trim(u8, value, " \t\r\n");
}

comptime {
    if (@typeInfo(Intent).@"union".fields.len != 68) {
        @compileError("Intent must have exactly every cm.bridge/1 table arm");
    }
}
