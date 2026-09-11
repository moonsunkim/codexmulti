const std = @import("std");
const shell = @import("shell_model");
const domain = shell.domain;
const ui_model = shell.ui_model;

const testing = std.testing;
pub const now: i64 = 1_784_948_400;

pub const RecordingService = struct {
    capabilities: ui_model.ServiceCapabilities = .{ .connected = true },
    outcome: ui_model.CommandOutcome = .accepted_pending,
    projections: usize = 0,
    submissions: usize = 0,
    labeled_adds: usize = 0,
    last: ?ui_model.Command = null,
    last_labeled_provider: ?domain.Provider = null,
    accounts: []const Account = &.{},
    proxy_fact: ?ui_model.ProxyFact = null,
    complete_proxy_on_pump: bool = false,
    pumps: usize = 0,
    tags: [64]std.meta.Tag(ui_model.Command) = @splat(.refresh_all),
    kept: [4][1024]u8 = @splat(@splat(0)),
    kept_len: [4]usize = @splat(0),

    pub const Account = struct {
        fact: ui_model.AccountFact,
        windows: []const domain.UsageWindow = &.{},
    };

    pub fn port(self: *RecordingService) ui_model.ServicePort {
        return .{
            .context = self,
            .capabilities_fn = readCapabilities,
            .project_fn = project,
            .submit_fn = submit,
            .add_account_labeled_fn = addAccountLabeled,
            .pump_fn = pump,
        };
    }

    fn readCapabilities(context: *anyopaque) ui_model.ServiceCapabilities {
        const self: *RecordingService = @ptrCast(@alignCast(context));
        return self.capabilities;
    }

    fn project(context: *anyopaque, view: *ui_model.ViewState) void {
        const self: *RecordingService = @ptrCast(@alignCast(context));
        self.projections += 1;
        for (self.accounts) |entry| {
            const slot = view.pushAccount(entry.fact) catch return;
            for (entry.windows) |window| view.pushWindow(slot, window) catch break;
        }
        if (self.proxy_fact) |fact| view.applyProxy(fact);
    }

    fn submit(context: *anyopaque, command: ui_model.Command) ui_model.CommandOutcome {
        const self: *RecordingService = @ptrCast(@alignCast(context));
        self.tags[self.submissions] = std.meta.activeTag(command);
        self.submissions += 1;
        self.last = switch (command) {
            .set_appearance, .set_codex_usage_window, .refresh_all, .add_account, .proxy_refresh_status, .proxy_sync_config, .install_proxy_service, .repair_proxy_service, .stop_proxy_service, .disable_codex_routing => command,
            .set_codex_show_model_limits => |v| .{ .set_codex_show_model_limits = v },
            .set_launch_at_login => |v| .{ .set_launch_at_login = v },
            .report_launch_at_login_registration_failure => |v| .{ .report_launch_at_login_registration_failure = v },
            .set_auto_refresh => |v| .{ .set_auto_refresh = v },
            .set_proxy_enabled => |v| .{ .set_proxy_enabled = v },
            .enable_codex_routing => |v| .{ .enable_codex_routing = v },
            .refresh_account => |v| .{ .refresh_account = self.keep(0, v) },
            .reauthenticate => |v| .{ .reauthenticate = self.keep(0, v) },
            .remove_account => |v| .{ .remove_account = self.keep(0, v) },
            .retry_reset => |v| .{ .retry_reset = self.keep(0, v) },
            .proxy_switch_account => |v| .{ .proxy_switch_account = self.keep(0, v) },
            .proxy_pause_account => |v| .{ .proxy_pause_account = self.keep(0, v) },
            .proxy_reload_account => |v| .{ .proxy_reload_account = self.keep(0, v) },
            .proxy_clear_cooldown => |v| .{ .proxy_clear_cooldown = self.keep(0, v) },
            .relabel => |v| .{ .relabel = .{ .account_id = self.keep(0, v.account_id), .label = self.keep(1, v.label) } },
            .move_account => |v| .{ .move_account = .{
                .account_id = self.keep(0, v.account_id),
                .target_account_id = self.keep(1, v.target_account_id),
            } },
            .redeem_reset => |v| .{ .redeem_reset = .{
                .account_id = self.keep(0, v.account_id),
                .expected_available_count = v.expected_available_count,
                .confirmed_at_unix_s = v.confirmed_at_unix_s,
                .surface = v.surface,
            } },
            .save_proxy_settings => |v| .{ .save_proxy_settings = .{
                .base_url = self.keep(0, v.base_url),
                .cli_path = self.keep(1, v.cli_path),
                .config_path = self.keep(2, v.config_path),
                .node_path = self.keep(3, v.node_path),
            } },
        };
        return self.outcome;
    }

    fn addAccountLabeled(context: *anyopaque, provider: domain.Provider, label: []const u8) ui_model.CommandOutcome {
        const self: *RecordingService = @ptrCast(@alignCast(context));
        self.labeled_adds += 1;
        self.last_labeled_provider = provider;
        _ = self.keep(0, label);
        return self.outcome;
    }

    pub fn lastLabeledLabel(self: *const RecordingService) []const u8 {
        return self.kept[0][0..self.kept_len[0]];
    }

    fn pump(context: *anyopaque, _: i64) void {
        const self: *RecordingService = @ptrCast(@alignCast(context));
        self.pumps += 1;
        if (!self.complete_proxy_on_pump) return;
        if (self.proxy_fact) |*fact| fact.work = .idle;
        self.complete_proxy_on_pump = false;
    }

    fn keep(self: *RecordingService, slot: usize, value: []const u8) []const u8 {
        const take = @min(value.len, self.kept[slot].len);
        @memcpy(self.kept[slot][0..take], value[0..take]);
        self.kept_len[slot] = take;
        return self.kept[slot][0..take];
    }
};

pub fn weeklyWindow(used: u8, reset_at: ?i64) domain.UsageWindow {
    return .{ .kind = .weekly, .label = "Weekly", .used_percent = used, .reset_at_unix_s = reset_at, .duration_minutes = 7 * 24 * 60 };
}

pub fn sessionWindow(used: u8, reset_at: ?i64) domain.UsageWindow {
    return .{ .kind = .session, .label = "5-hour", .used_percent = used, .reset_at_unix_s = reset_at, .duration_minutes = 300 };
}

pub fn claudeFact() ui_model.AccountFact {
    return .{
        .account_id = "acct-claude-work",
        .label = "Claude Work",
        .provider = .claude,
        .auth_state = .connected,
        .freshness = .saved_snapshot,
        .snapshot_status = .fresh,
        .has_snapshot = true,
        .snapshot_captured_at_unix_s = now - 3600,
        .last_attempt_at_unix_s = now - 3600,
        .last_success_at_unix_s = now - 3600,
    };
}

pub fn codexFact() ui_model.AccountFact {
    return .{
        .account_id = "acct-codex-personal",
        .label = "Codex Personal",
        .provider = .codex,
        .auth_state = .connected,
        .freshness = .saved_snapshot,
        .snapshot_status = .fresh,
        .has_snapshot = true,
        .snapshot_captured_at_unix_s = now - 600,
        .last_attempt_at_unix_s = now - 600,
        .last_success_at_unix_s = now - 600,
        .reset_credit_count = 2,
        .credit_detail_status = .count_only,
    };
}

fn newModel(service: *RecordingService) *shell.Model {
    const model = testing.allocator.create(shell.Model) catch unreachable;
    model.* = shell.initialModel();
    model.now_unix_s = now;
    model.service = service.port();
    shell.reproject(model);
    return model;
}

test "C4 projection drops Claude facts and tray sections while preserving Codex group facts" {
    const claude_windows = [_]domain.UsageWindow{weeklyWindow(99, now + 3600)};
    const codex_windows = [_]domain.UsageWindow{weeklyWindow(100, now + 3600)};
    var accounts = [_]RecordingService.Account{
        .{ .fact = claudeFact(), .windows = &claude_windows },
        .{ .fact = codexFact(), .windows = &codex_windows },
    };
    var service: RecordingService = .{ .accounts = &accounts };
    const model = newModel(&service);
    defer testing.allocator.destroy(model);

    try testing.expectEqual(@as(usize, 1), model.view.row_count);
    try testing.expectEqual(@as(usize, 1), model.view.account_row_count);
    try testing.expectEqual(@as(usize, 0), model.view.claude_row_count);
    try testing.expectEqual(@as(u32, 0), model.view.claude_count);
    try testing.expectEqual(domain.Provider.codex, model.view.rows[0].provider);
    try testing.expectEqual(domain.Provider.codex, model.view.account_rows[0].provider);
    try testing.expectEqualStrings("CODEX · 1 account · 1 exhausted this week", model.view.codex_group_title);

    var tray_items: [ui_model.max_tray_items]ui_model.TrayItem = @splat(.{});
    const tray_count = ui_model.buildTray(&model.view, &tray_items);
    for (tray_items[0..tray_count]) |item| {
        try testing.expect(std.mem.indexOf(u8, item.label, "CLAUDE") == null);
        try testing.expect(std.mem.indexOf(u8, item.label, "Claude Work") == null);
    }
}

test "C4 retained Claude shell intents are accepted state-preserving no-ops" {
    var service: RecordingService = .{};
    const model = newModel(&service);
    defer testing.allocator.destroy(model);
    var effects: shell.Effects = .{};
    model.toolbar_menu_open = true;
    const before_projection_count = service.projections;

    shell.update(model, .add_claude_account, &effects);
    shell.update(model, .claude_tray_session, &effects);
    shell.update(model, .claude_tray_weekly, &effects);

    try testing.expectEqual(@as(usize, 0), service.submissions);
    try testing.expectEqual(before_projection_count, service.projections);
    try testing.expect(model.toolbar_menu_open);
    try testing.expectEqual(ui_model.ClaudeTrayWindow.weekly, model.claude_tray_window);
    try testing.expectEqual(ui_model.NoticeKind.none, model.notice.kind);
    try testing.expectEqual(@as(usize, 0), effects.len);
}

test "Claude facts and tray intents remain invisible and inert" {
    const windows = [_]domain.UsageWindow{
        .{ .kind = .session, .label = "Current session", .used_percent = 0, .reset_at_unix_s = null, .duration_minutes = 300 },
        .{ .kind = .weekly, .label = "Current week", .used_percent = 100, .reset_at_unix_s = null, .duration_minutes = 7 * 24 * 60 },
    };
    var accounts = [_]RecordingService.Account{.{ .fact = claudeFact(), .windows = &windows }};
    var service: RecordingService = .{ .accounts = &accounts };
    const model = newModel(&service);
    defer testing.allocator.destroy(model);
    var effects: shell.Effects = .{};

    const before = service.projections;
    shell.update(model, .claude_tray_session, &effects);
    try testing.expectEqual(ui_model.ClaudeTrayWindow.weekly, model.claude_tray_window);
    try testing.expectEqual(before, service.projections);
    try testing.expectEqual(@as(usize, 0), model.view.row_count);
    var tray_items: [ui_model.max_tray_items]ui_model.TrayItem = @splat(.{});
    const tray_count = ui_model.buildTray(&model.view, &tray_items);
    for (tray_items[0..tray_count]) |item| {
        try testing.expect(std.mem.indexOf(u8, item.label, "Claude") == null);
    }

    shell.update(model, .claude_tray_weekly, &effects);
    try testing.expectEqual(ui_model.ClaudeTrayWindow.weekly, model.claude_tray_window);
    try testing.expectEqual(@as(usize, 0), service.submissions);
}

test "passive navigation and menu intents submit no service command" {
    var accounts = [_]RecordingService.Account{ .{ .fact = claudeFact() }, .{ .fact = codexFact() } };
    var service: RecordingService = .{ .accounts = &accounts };
    const model = newModel(&service);
    defer testing.allocator.destroy(model);
    var effects: shell.Effects = .{};
    shell.update(model, .tab_failover, &effects);
    shell.update(model, .tab_accounts, &effects);
    shell.update(model, .{ .toggle_account = 1 }, &effects);
    shell.update(model, .{ .open_row_menu = 0 }, &effects);
    shell.update(model, .close_row_menu, &effects);
    shell.update(model, .toggle_proxy_settings, &effects);
    try testing.expectEqual(@as(usize, 0), service.submissions);
}

test "proxy pending notice remains while proxy work is busy and clears after settle" {
    var service: RecordingService = .{
        .capabilities = .{ .connected = true, .proxy_control = true },
        .proxy_fact = .{
            .base_url = "http://127.0.0.1:8787",
            .cli_path = "/tmp/proxy",
            .config_path = "/tmp/proxy.json",
            .reachability = .unknown,
            .work = .checking,
            .sync_state = .unknown,
            .accounts = &.{},
        },
    };
    const model = newModel(&service);
    defer testing.allocator.destroy(model);
    var effects: shell.Effects = .{};

    shell.update(model, .refresh_proxy_status, &effects);
    try testing.expectEqual(ui_model.NoticeKind.pending, model.notice.kind);
    try testing.expectEqualStrings(" · refreshing", shell.busySuffixText(&model.view));

    service.proxy_fact.?.work = .idle;
    shell.pump(model, now + 1);
    try testing.expectEqual(ui_model.NoticeKind.none, model.notice.kind);
    try testing.expectEqualStrings("", shell.busySuffixText(&model.view));
}

test "pump projects idle after a proxy status read completes" {
    var service: RecordingService = .{
        .capabilities = .{ .connected = true, .proxy_control = true },
        .proxy_fact = .{
            .base_url = "http://127.0.0.1:8787",
            .cli_path = "/tmp/proxy",
            .config_path = "/tmp/proxy.json",
            .reachability = .unknown,
            .work = .checking,
            .sync_state = .unknown,
            .accounts = &.{},
        },
        .complete_proxy_on_pump = true,
    };
    const model = newModel(&service);
    defer testing.allocator.destroy(model);

    try testing.expectEqual(ui_model.ProxyWork.checking, model.view.proxy_work);
    shell.pump(model, now + 1);

    try testing.expectEqual(@as(usize, 1), service.pumps);
    try testing.expectEqual(ui_model.ProxyWork.idle, model.view.proxy_work);
}

test "each direct mutating action submits exactly one typed command" {
    var accounts = [_]RecordingService.Account{.{ .fact = codexFact() }};
    var service: RecordingService = .{
        .accounts = &accounts,
        .capabilities = .{ .connected = true, .refresh = true, .accounts = true, .reset = true, .proxy_control = true },
    };
    const model = newModel(&service);
    defer testing.allocator.destroy(model);
    var effects: shell.Effects = .{};
    const actions = [_]shell.Intent{
        .{ .set_launch_at_login = true },
        .{ .report_launch_at_login_registration_failure = true },
        .{ .set_auto_refresh = 30 },
        .{ .set_proxy_enabled = true },
        .refresh_all,
        .{ .refresh_account = 0 },
        .{ .reauthenticate = 0 },
        .add_codex_account,
        .refresh_proxy_status,
        .sync_proxy_config,
        .{ .save_proxy_settings = .{ .base_url = "http://127.0.0.1:8787", .cli_path = "/tmp/proxy", .config_path = "/tmp/config", .node_path = "" } },
    };
    const expected_tags = [_]std.meta.Tag(ui_model.Command){
        .set_launch_at_login,
        .report_launch_at_login_registration_failure,
        .set_auto_refresh,
        .set_proxy_enabled,
        .refresh_all,
        .refresh_account,
        .reauthenticate,
        .add_account,
        .proxy_refresh_status,
        .refresh_all,
        .save_proxy_settings,
    };
    for (actions, 1..) |action, expected| {
        shell.update(model, action, &effects);
        try testing.expectEqual(expected, service.submissions);
        try testing.expectEqual(expected_tags[expected - 1], service.tags[expected - 1]);
        switch (action) {
            .set_launch_at_login => try testing.expect(service.last.?.set_launch_at_login),
            .report_launch_at_login_registration_failure => try testing.expect(service.last.?.report_launch_at_login_registration_failure),
            .set_auto_refresh => try testing.expectEqual(@as(u16, 30), service.last.?.set_auto_refresh),
            .set_proxy_enabled => try testing.expect(service.last.?.set_proxy_enabled),
            .refresh_account => try testing.expectEqualStrings("acct-codex-personal", service.last.?.refresh_account),
            .reauthenticate => try testing.expectEqualStrings("acct-codex-personal", service.last.?.reauthenticate),
            .add_codex_account => try testing.expectEqual(domain.Provider.codex, service.last.?.add_account),
            else => {},
        }
    }
    try testing.expectEqualStrings("http://127.0.0.1:8787", service.last.?.save_proxy_settings.base_url);
    try testing.expectEqualStrings("/tmp/proxy", service.last.?.save_proxy_settings.cli_path);
    try testing.expectEqualStrings("/tmp/config", service.last.?.save_proxy_settings.config_path);
    try testing.expectEqualStrings("", service.last.?.save_proxy_settings.node_path);
}

test "cancelled rename and removal submit nothing" {
    var accounts = [_]RecordingService.Account{.{ .fact = codexFact() }};
    var service: RecordingService = .{ .accounts = &accounts };
    const model = newModel(&service);
    defer testing.allocator.destroy(model);
    var effects: shell.Effects = .{};
    shell.update(model, .{ .begin_rename = 0 }, &effects);
    shell.update(model, .cancel_rename, &effects);
    shell.update(model, .{ .begin_remove = 0 }, &effects);
    shell.update(model, .cancel_remove, &effects);
    try testing.expectEqual(@as(usize, 0), service.submissions);
}

test "C11 begin add is passive and commit invokes the labeled adapter once with a trimmed label" {
    var service: RecordingService = .{ .capabilities = .{ .connected = true, .accounts = true } };
    const model = newModel(&service);
    defer testing.allocator.destroy(model);
    var effects: shell.Effects = .{};

    shell.update(model, .begin_add_account, &effects);
    try testing.expect(model.add_account.open);
    try testing.expectEqual(@as(usize, 0), service.labeled_adds);
    try testing.expectEqual(@as(usize, 0), service.submissions);

    shell.update(model, .{ .commit_add_account = "  Owner Work  " }, &effects);
    try testing.expectEqual(@as(usize, 1), service.labeled_adds);
    try testing.expectEqual(domain.Provider.codex, service.last_labeled_provider.?);
    try testing.expectEqualStrings("Owner Work", service.lastLabeledLabel());
    try testing.expect(model.add_account.open);
    try testing.expect(model.add_account.in_flight);

    shell.update(model, .{ .commit_add_account = "Owner Work" }, &effects);
    try testing.expectEqual(@as(usize, 1), service.labeled_adds);
}

test "C11 cancel add closes the draft and submits nothing" {
    var service: RecordingService = .{ .capabilities = .{ .connected = true, .accounts = true } };
    const model = newModel(&service);
    defer testing.allocator.destroy(model);
    var effects: shell.Effects = .{};

    shell.update(model, .begin_add_account, &effects);
    shell.update(model, .cancel_add_account, &effects);

    try testing.expect(!model.add_account.open);
    try testing.expectEqual(@as(usize, 0), service.labeled_adds);
    try testing.expectEqual(@as(usize, 0), service.submissions);
}

test "C11 add flow stays open while login is busy and closes when the named account lands" {
    var account_storage: [1]RecordingService.Account = undefined;
    var service: RecordingService = .{ .capabilities = .{ .connected = true, .accounts = true }, .accounts = account_storage[0..0] };
    const model = newModel(&service);
    defer testing.allocator.destroy(model);
    var effects: shell.Effects = .{};

    shell.update(model, .begin_add_account, &effects);
    shell.update(model, .{ .commit_add_account = "Owner Work" }, &effects);
    account_storage[0] = .{ .fact = .{
        .account_id = "acct-codex-added",
        .label = "Owner Work",
        .provider = .codex,
        .operation_in_flight = true,
    } };
    service.accounts = &account_storage;
    shell.reproject(model);
    try testing.expect(model.add_account.open and model.add_account.in_flight);
    try testing.expectEqualStrings("acct-codex-added", model.add_account.accountId());

    account_storage[0].fact.operation_in_flight = false;
    account_storage[0].fact.last_attempt_at_unix_s = now;
    shell.reproject(model);
    try testing.expect(!model.add_account.open and !model.add_account.in_flight);
    try testing.expectEqualStrings("", model.add_account.errorText());
}

test "C11 failed add closes and keeps the existing Add-account failure wording on the flow" {
    var account_storage: [1]RecordingService.Account = undefined;
    var service: RecordingService = .{ .capabilities = .{ .connected = true, .accounts = true }, .accounts = account_storage[0..0] };
    const model = newModel(&service);
    defer testing.allocator.destroy(model);
    var effects: shell.Effects = .{};

    shell.update(model, .begin_add_account, &effects);
    shell.update(model, .{ .commit_add_account = "Owner Work" }, &effects);
    account_storage[0] = .{ .fact = .{
        .account_id = "acct-codex-added",
        .label = "Owner Work",
        .provider = .codex,
        .last_attempt_at_unix_s = now,
        .last_attempt_code = "login-rejected",
    } };
    service.accounts = &account_storage;
    shell.reproject(model);

    try testing.expect(!model.add_account.open and !model.add_account.in_flight);
    try testing.expectEqualStrings(
        "Add account failed for Codex. Nothing is claimed about the provider's state.",
        model.add_account.errorText(),
    );
    try testing.expectEqual(ui_model.NoticeKind.none, model.notice.kind);
}

test "C11 blank commit stays local and starts no add" {
    var service: RecordingService = .{ .capabilities = .{ .connected = true, .accounts = true } };
    const model = newModel(&service);
    defer testing.allocator.destroy(model);
    var effects: shell.Effects = .{};

    shell.update(model, .begin_add_account, &effects);
    shell.update(model, .{ .commit_add_account = " \t " }, &effects);
    try testing.expect(model.add_account.open and !model.add_account.in_flight);
    try testing.expectEqual(@as(usize, 0), service.labeled_adds);
    try testing.expectEqualStrings("Enter an account name before continuing.", model.add_account.errorText());
}

test "rename commit carries the shell-owned full label" {
    var accounts = [_]RecordingService.Account{.{ .fact = codexFact() }};
    var service: RecordingService = .{ .accounts = &accounts };
    const model = newModel(&service);
    defer testing.allocator.destroy(model);
    var effects: shell.Effects = .{};
    shell.update(model, .{ .begin_rename = 0 }, &effects);
    try testing.expectEqualStrings("Codex Personal", model.rename.initialLabel());
    shell.update(model, .{ .commit_rename = "Primary Codex" }, &effects);
    try testing.expectEqualStrings("Primary Codex", service.last.?.relabel.label);
    try testing.expectEqual(@as(usize, 1), service.submissions);
}

test "notices persist across pumps until dismissed or replaced" {
    var fact = codexFact();
    fact.operation_in_flight = true;
    var accounts = [_]RecordingService.Account{.{ .fact = fact }};
    var service: RecordingService = .{ .accounts = &accounts };
    const model = newModel(&service);
    defer testing.allocator.destroy(model);
    var effects: shell.Effects = .{};
    shell.update(model, .refresh_all, &effects);
    try testing.expectEqual(ui_model.NoticeKind.pending, model.notice.kind);
    shell.pump(model, now + 1);
    try testing.expectEqual(ui_model.NoticeKind.pending, model.notice.kind);
    const first_notice = try testing.allocator.dupe(u8, model.notice.text());
    defer testing.allocator.free(first_notice);
    service.outcome = .rejected_busy;
    shell.update(model, .{ .refresh_account = 0 }, &effects);
    try testing.expectEqual(ui_model.NoticeKind.blocked, model.notice.kind);
    try testing.expect(!std.mem.eql(u8, first_notice, model.notice.text()));
    try testing.expect(std.mem.indexOf(u8, model.notice.text(), "Refresh refused") != null);
    shell.update(model, .dismiss_notice, &effects);
    try testing.expectEqual(ui_model.NoticeKind.none, model.notice.kind);
}

test "a dispatched reset reports settlement once the row attempt clears" {
    const windows = [_]domain.UsageWindow{weeklyWindow(90, now + 3600)};
    var fact = codexFact();
    var accounts = [_]RecordingService.Account{.{ .fact = fact, .windows = &windows }};
    var service: RecordingService = .{ .accounts = &accounts };
    const model = newModel(&service);
    defer testing.allocator.destroy(model);
    var effects: shell.Effects = .{};
    shell.update(model, .{ .begin_reset = 0 }, &effects);
    shell.update(model, .acknowledge_reset, &effects);
    shell.update(model, .confirm_reset, &effects);
    try testing.expectEqual(ui_model.ResetStage.dispatched, model.reset.stage);
    fact.operation_in_flight = true;
    accounts[0].fact = fact;
    shell.pump(model, now + 1);
    try testing.expectEqual(@as(@TypeOf(model.reset.settle), .seen), model.reset.settle);
    fact.operation_in_flight = false;
    fact.reset_credit_count = 1;
    fact.reset_proxy_clear = .cleared;
    accounts[0].fact = fact;
    shell.pump(model, now + 2);
    try testing.expectEqual(@as(@TypeOf(model.reset.settle), .settled), model.reset.settle);
    try testing.expect(std.mem.indexOf(u8, model.reset.outcomeText(), "settled") != null);
}

test "confirm reset before acknowledgement is a no-op" {
    var accounts = [_]RecordingService.Account{.{ .fact = codexFact() }};
    var service: RecordingService = .{ .accounts = &accounts };
    const model = newModel(&service);
    defer testing.allocator.destroy(model);
    var effects: shell.Effects = .{};
    shell.update(model, .{ .begin_reset = 0 }, &effects);
    shell.update(model, .confirm_reset, &effects);
    try testing.expectEqual(@as(usize, 0), service.submissions);
}

test "open details and quit become ordered one-shot effect records" {
    var service: RecordingService = .{};
    const model = newModel(&service);
    defer testing.allocator.destroy(model);
    var effects: shell.Effects = .{};
    shell.update(model, .open_details, &effects);
    shell.update(model, .quit_app, &effects);
    try testing.expectEqual(shell.EffectKind.show_settings, effects.slice()[0].kind);
    try testing.expectEqual(shell.EffectKind.quit, effects.slice()[1].kind);
}

test "toolbar menus row expansion account-id tray paths and diagnostics remain passive or exact" {
    var accounts = [_]RecordingService.Account{ .{ .fact = claudeFact() }, .{ .fact = codexFact() } };
    var service: RecordingService = .{ .accounts = &accounts, .capabilities = .{ .connected = true, .refresh = true, .accounts = true, .proxy_control = true } };
    const model = newModel(&service);
    defer testing.allocator.destroy(model);
    var effects: shell.Effects = .{};

    shell.update(model, .{ .toggle_account = 0 }, &effects);
    try testing.expectEqual(@as(?u32, 0), model.expanded);
    shell.update(model, .tab_failover, &effects);
    shell.update(model, .tab_accounts, &effects);
    try testing.expectEqual(@as(?u32, 0), model.expanded);
    shell.update(model, .{ .open_row_menu = 0 }, &effects);
    shell.update(model, .open_toolbar_menu, &effects);
    try testing.expect(model.row_menu == null and model.proxy_row_menu == null and model.toolbar_menu_open);
    shell.update(model, .close_toolbar_menu, &effects);

    shell.update(model, .{ .open_account = "acct-codex-personal" }, &effects);
    try testing.expectEqual(@as(?u32, 0), model.expanded);
    try testing.expectEqual(shell.EffectKind.show_settings, effects.slice()[0].kind);
    shell.update(model, .{ .refresh_account_id = "acct-codex-personal" }, &effects);
    try testing.expectEqual(std.meta.Tag(ui_model.Command).refresh_account, service.tags[0]);
    try testing.expectEqualStrings("acct-codex-personal", service.last.?.refresh_account);

    const before = service.submissions;
    shell.update(model, .{ .copy_diagnostics = 0 }, &effects);
    try testing.expectEqual(before, service.submissions);
    const diagnostic = effects.slice()[effects.len - 1];
    try testing.expectEqual(shell.EffectKind.clipboard, diagnostic.kind);
    try testing.expect(std.mem.indexOf(u8, diagnostic.text(), "account id: acct-codex-personal") != null);
    for ([_][]const u8{ "access_token", "refresh_token", "Bearer ", "authorization", "password" }) |secret| {
        try testing.expect(std.mem.indexOf(u8, diagnostic.text(), secret) == null);
    }

    const toolbar_actions = [_]shell.Intent{ .add_codex_account, .refresh_all, .refresh_proxy_status, .sync_proxy_config };
    for (toolbar_actions) |action| {
        shell.update(model, .open_toolbar_menu, &effects);
        const n = service.submissions;
        shell.update(model, action, &effects);
        try testing.expectEqual(n + 1, service.submissions);
        try testing.expect(!model.toolbar_menu_open);
    }
    shell.update(model, .open_toolbar_menu, &effects);
    const n = service.submissions;
    shell.update(model, .add_claude_account, &effects);
    try testing.expectEqual(n, service.submissions);
    try testing.expect(model.toolbar_menu_open);
}

test "unattached capabilities stay truthful and accepted notices live until work clears" {
    var service: RecordingService = .{ .capabilities = .{}, .outcome = .accepted_pending };
    const model = newModel(&service);
    defer testing.allocator.destroy(model);
    try testing.expect(!model.canRefresh());
    try testing.expect(!model.canRefreshAll());
    try testing.expect(!model.canManageAccounts());
    try testing.expectEqualStrings(model.view.service_text, model.footerText());

    var busy = codexFact();
    busy.operation_in_flight = true;
    var accounts = [_]RecordingService.Account{.{ .fact = busy }};
    service.accounts = &accounts;
    service.capabilities = .{ .connected = true, .refresh = true };
    shell.reproject(model);
    var effects: shell.Effects = .{};
    shell.update(model, .refresh_all, &effects);
    try testing.expectEqual(ui_model.NoticeKind.pending, model.notice.kind);
    shell.pump(model, now + 1);
    try testing.expectEqual(ui_model.NoticeKind.pending, model.notice.kind);
    accounts[0].fact.operation_in_flight = false;
    shell.pump(model, now + 2);
    try testing.expectEqual(ui_model.NoticeKind.none, model.notice.kind);
}

test "proxy menu gates and mapped removal produce only the exact typed command sequence" {
    var second = codexFact();
    second.account_id = "acct-codex-ready";
    second.label = "Codex Ready";
    var cooling = codexFact();
    cooling.account_id = "acct-codex-cooling";
    cooling.label = "Codex Cooling";
    var paused = codexFact();
    paused.account_id = "acct-codex-paused";
    paused.label = "Codex Paused";
    var accounts = [_]RecordingService.Account{ .{ .fact = codexFact() }, .{ .fact = second }, .{ .fact = cooling }, .{ .fact = paused } };
    var proxy_accounts = [_]ui_model.ProxyAccountFact{
        .{ .app_id = "acct-codex-personal", .storage_key = "p0", .proxy_name = "p0", .label = "Codex Personal", .state = .ready, .active = true, .mapped = true },
        .{ .app_id = "acct-codex-ready", .storage_key = "p1", .proxy_name = "p1", .label = "Codex Ready", .state = .ready, .mapped = true },
        .{ .app_id = "acct-codex-cooling", .storage_key = "p2", .proxy_name = "p2", .label = "Codex Cooling", .state = .cooldown, .cooldown_until_unix_s = now + 3600, .mapped = true },
        .{ .app_id = "acct-codex-paused", .storage_key = "p3", .proxy_name = "p3", .label = "Codex Paused", .state = .paused, .mapped = true },
    };
    var service: RecordingService = .{
        .accounts = &accounts,
        .capabilities = .{ .connected = true, .accounts = true, .proxy_control = true },
        .proxy_fact = .{ .base_url = "http://127.0.0.1:8787", .cli_path = "/tmp/proxy", .config_path = "/tmp/config", .reachability = .reachable, .sync_state = .synced, .success_revision = 1, .config_path_matches = true, .accounts = &proxy_accounts },
    };
    const model = newModel(&service);
    defer testing.allocator.destroy(model);
    var effects: shell.Effects = .{};

    shell.update(model, .{ .open_proxy_row_menu = 0 }, &effects);
    shell.update(model, .{ .pause_proxy_account = 0 }, &effects);
    shell.update(model, .{ .resume_proxy_account = 3 }, &effects);
    shell.update(model, .{ .begin_proxy_switch = 1 }, &effects);
    try testing.expectEqual(shell.EffectKind.show_settings, effects.slice()[0].kind);
    shell.update(model, .confirm_failover_switch, &effects);
    shell.update(model, .{ .begin_clear_cooldown = 2 }, &effects);
    shell.update(model, .confirm_clear_cooldown, &effects);
    try testing.expectEqual(@as(usize, 4), service.submissions);
    const first = [_]std.meta.Tag(ui_model.Command){ .proxy_pause_account, .proxy_reload_account, .proxy_switch_account, .proxy_clear_cooldown };
    try testing.expectEqualSlices(std.meta.Tag(ui_model.Command), &first, service.tags[0..4]);

    const gated = service.submissions;
    shell.update(model, .{ .pause_proxy_account = 3 }, &effects);
    shell.update(model, .{ .resume_proxy_account = 0 }, &effects);
    shell.update(model, .{ .begin_proxy_switch = 0 }, &effects);
    shell.update(model, .{ .begin_clear_cooldown = 0 }, &effects);
    try testing.expectEqual(gated, service.submissions);

    shell.update(model, .{ .begin_remove = 0 }, &effects);
    shell.update(model, .confirm_remove, &effects);
    try testing.expectEqual(std.meta.Tag(ui_model.Command).proxy_pause_account, service.tags[4]);
    proxy_accounts[0].state = .paused;
    service.proxy_fact.?.success_revision = 2;
    shell.reproject(model);
    try testing.expect(model.removeCanFinish());
    shell.update(model, .finish_mapped_remove, &effects);
    try testing.expectEqual(@as(usize, 7), service.submissions);
    try testing.expectEqual(std.meta.Tag(ui_model.Command).remove_account, service.tags[5]);
    try testing.expectEqual(std.meta.Tag(ui_model.Command).proxy_sync_config, service.tags[6]);
}

test "proxy and account intents submit exact target account ids including plain removal" {
    var ready = codexFact();
    ready.account_id = "acct-codex-ready";
    ready.label = "Codex Ready";
    var cooling = codexFact();
    cooling.account_id = "acct-codex-cooling";
    cooling.label = "Codex Cooling";
    var paused = codexFact();
    paused.account_id = "acct-codex-paused";
    paused.label = "Codex Paused";
    var plain = codexFact();
    plain.account_id = "acct-codex-plain";
    plain.label = "Codex Plain";
    var accounts = [_]RecordingService.Account{
        .{ .fact = codexFact() },
        .{ .fact = ready },
        .{ .fact = cooling },
        .{ .fact = paused },
        .{ .fact = plain },
    };

    var proxy_accounts = [_]ui_model.ProxyAccountFact{
        .{ .app_id = "acct-codex-cooling", .storage_key = "p2", .proxy_name = "p2", .label = "Codex Cooling", .state = .cooldown, .cooldown_until_unix_s = now + 3600, .mapped = true },
        .{ .app_id = "acct-codex-paused", .storage_key = "p3", .proxy_name = "p3", .label = "Codex Paused", .state = .paused, .mapped = true },
        .{ .app_id = "acct-codex-personal", .storage_key = "p0", .proxy_name = "p0", .label = "Codex Personal", .state = .ready, .active = true, .mapped = true },
        .{ .app_id = "acct-codex-ready", .storage_key = "p1", .proxy_name = "p1", .label = "Codex Ready", .state = .ready, .mapped = true },
    };
    var service: RecordingService = .{
        .accounts = &accounts,
        .capabilities = .{ .connected = true, .accounts = true, .proxy_control = true },
        .proxy_fact = .{
            .base_url = "http://127.0.0.1:8787",
            .cli_path = "/tmp/proxy",
            .config_path = "/tmp/config",
            .reachability = .reachable,
            .sync_state = .synced,
            .success_revision = 1,
            .config_path_matches = true,
            .accounts = &proxy_accounts,
        },
    };
    const model = newModel(&service);
    defer testing.allocator.destroy(model);
    var effects: shell.Effects = .{};

    shell.update(model, .{ .pause_proxy_account = 2 }, &effects);
    try testing.expectEqualStrings("acct-codex-personal", service.last.?.proxy_pause_account);
    shell.update(model, .{ .resume_proxy_account = 1 }, &effects);
    try testing.expectEqualStrings("acct-codex-paused", service.last.?.proxy_reload_account);
    shell.update(model, .{ .begin_proxy_switch = 3 }, &effects);
    shell.update(model, .confirm_failover_switch, &effects);
    try testing.expectEqualStrings("acct-codex-ready", service.last.?.proxy_switch_account);
    shell.update(model, .{ .begin_clear_cooldown = 0 }, &effects);
    shell.update(model, .confirm_clear_cooldown, &effects);
    try testing.expectEqualStrings("acct-codex-cooling", service.last.?.proxy_clear_cooldown);

    shell.update(model, .{ .pause_failover_account = 1 }, &effects);
    try testing.expectEqual(@as(usize, 5), service.submissions);
    try testing.expectEqualStrings("acct-codex-ready", service.last.?.proxy_pause_account);
    shell.update(model, .{ .begin_clear_cooldown_account = 2 }, &effects);
    shell.update(model, .confirm_clear_cooldown, &effects);
    try testing.expectEqual(@as(usize, 6), service.submissions);
    try testing.expectEqualStrings("acct-codex-cooling", service.last.?.proxy_clear_cooldown);
    shell.update(model, .{ .begin_failover_switch_id = "acct-codex-ready" }, &effects);
    shell.update(model, .confirm_failover_switch, &effects);
    try testing.expectEqual(@as(usize, 7), service.submissions);
    try testing.expectEqualStrings("acct-codex-ready", service.last.?.proxy_switch_account);

    shell.update(model, .{ .begin_remove = 0 }, &effects);
    shell.update(model, .confirm_remove, &effects);
    try testing.expectEqualStrings("acct-codex-personal", service.last.?.proxy_pause_account);
    shell.update(model, .cancel_remove, &effects);
    shell.update(model, .{ .begin_remove = 4 }, &effects);
    shell.update(model, .confirm_remove, &effects);
    try testing.expectEqualStrings("acct-codex-plain", service.last.?.remove_account);
    try testing.expectEqual(@as(usize, 9), service.submissions);
}

test "reset review disarm blocked retry rejected outcome settlement and proxy clear are closed" {
    const windows = [_]domain.UsageWindow{weeklyWindow(87, now + 3600)};
    var normal = codexFact();
    var unsent = codexFact();
    unsent.account_id = "acct-unsent";
    unsent.unsent_reset_attempt = true;
    var accounts = [_]RecordingService.Account{ .{ .fact = normal, .windows = &windows }, .{ .fact = unsent, .windows = &windows } };
    var service: RecordingService = .{ .accounts = &accounts, .capabilities = .{ .connected = true, .reset = true }, .outcome = .offer_unavailable };
    const model = newModel(&service);
    defer testing.allocator.destroy(model);
    var effects: shell.Effects = .{};
    shell.update(model, .{ .begin_reset = 0 }, &effects);
    try testing.expectEqual(ui_model.ResetStage.review, model.reset.stage);
    shell.update(model, .acknowledge_reset, &effects);
    try testing.expectEqual(ui_model.ResetStage.armed, model.reset.stage);
    shell.update(model, .acknowledge_reset, &effects);
    try testing.expectEqual(ui_model.ResetStage.review, model.reset.stage);
    shell.update(model, .confirm_reset, &effects);
    try testing.expectEqual(@as(usize, 0), service.submissions);
    shell.update(model, .acknowledge_reset, &effects);
    shell.update(model, .confirm_reset, &effects);
    try testing.expectEqual(ui_model.CommandOutcome.offer_unavailable, model.reset.outcome);
    try testing.expect(std.mem.indexOf(u8, model.reset.outcomeText(), "Nothing was sent") != null);
    const redemption = service.last.?.redeem_reset;
    try testing.expectEqualStrings("acct-codex-personal", redemption.account_id);
    try testing.expectEqual(@as(u32, 2), redemption.expected_available_count);
    try testing.expectEqual(now, redemption.confirmed_at_unix_s);
    try testing.expectEqual(ui_model.Surface.details, redemption.surface);

    shell.update(model, .{ .begin_reset = 1 }, &effects);
    try testing.expectEqual(ui_model.ResetBlockReason.unsent_attempt, model.reset.reason);
    service.outcome = .accepted_pending;
    shell.update(model, .retry_reset, &effects);
    try testing.expectEqual(std.meta.Tag(ui_model.Command).retry_reset, service.tags[1]);
    try testing.expectEqualStrings("acct-unsent", service.last.?.retry_reset);

    normal.pending_reset_attempt = false;
    accounts[0].fact = normal;
    shell.update(model, .{ .begin_reset = 0 }, &effects);
    shell.update(model, .cancel_reset, &effects);
    const before_stale_confirm = service.submissions;
    shell.update(model, .confirm_reset, &effects);
    try testing.expectEqual(before_stale_confirm, service.submissions);
    shell.update(model, .{ .begin_reset = 0 }, &effects);
    shell.update(model, .acknowledge_reset, &effects);
    shell.update(model, .confirm_reset, &effects);
    accounts[0].fact.pending_reset_attempt = true;
    shell.pump(model, now + 1);
    try testing.expectEqual(@as(@TypeOf(model.reset.settle), .seen), model.reset.settle);
    accounts[0].fact.pending_reset_attempt = false;
    accounts[0].fact.reset_proxy_clear = .cleared;
    shell.pump(model, now + 2);
    try testing.expectEqual(@as(@TypeOf(model.reset.settle), .settled), model.reset.settle);
    try testing.expect(model.resetShowsProxyClear());
    try testing.expectEqualStrings("Failover: cooldown cleared.", model.resetProxyClearText());
}

test "reset blocks Claude no-credit and pending-attempt rows without submitting" {
    var no_credit = codexFact();
    no_credit.reset_credit_count = 0;
    var pending = codexFact();
    pending.account_id = "acct-pending";
    pending.pending_reset_attempt = true;
    var accounts = [_]RecordingService.Account{ .{ .fact = no_credit }, .{ .fact = pending } };
    var service: RecordingService = .{ .accounts = &accounts, .capabilities = .{ .connected = true, .reset = true } };
    const model = newModel(&service);
    defer testing.allocator.destroy(model);
    var effects: shell.Effects = .{};
    const reasons = [_]ui_model.ResetBlockReason{ .no_credit, .pending_attempt };
    for (reasons, 0..) |reason, row| {
        shell.update(model, .{ .begin_reset = @intCast(row) }, &effects);
        try testing.expectEqual(ui_model.ResetStage.blocked, model.reset.stage);
        try testing.expectEqual(reason, model.reset.reason);
        shell.update(model, .acknowledge_reset, &effects);
        shell.update(model, .confirm_reset, &effects);
    }
    try testing.expectEqual(@as(usize, 0), service.submissions);
}

test "settled reset submits automatic proxy cooldown clear exactly once" {
    const windows = [_]domain.UsageWindow{weeklyWindow(87, now + 3600)};
    var accounts = [_]RecordingService.Account{.{ .fact = codexFact(), .windows = &windows }};
    var service: RecordingService = .{
        .accounts = &accounts,
        .capabilities = .{ .connected = true, .reset = true, .proxy_control = true },
    };
    const model = newModel(&service);
    defer testing.allocator.destroy(model);
    var effects: shell.Effects = .{};

    shell.update(model, .{ .begin_reset = 0 }, &effects);
    shell.update(model, .acknowledge_reset, &effects);
    shell.update(model, .confirm_reset, &effects);
    try testing.expectEqual(@as(usize, 1), service.submissions);
    try testing.expectEqual(std.meta.Tag(ui_model.Command).redeem_reset, service.tags[0]);

    accounts[0].fact.pending_reset_attempt = true;
    shell.pump(model, now + 1);
    try testing.expectEqual(@as(@TypeOf(model.reset.settle), .seen), model.reset.settle);

    accounts[0].fact.pending_reset_attempt = false;
    shell.pump(model, now + 2);
    try testing.expectEqual(@as(@TypeOf(model.reset.settle), .settled), model.reset.settle);
    try testing.expectEqual(@as(usize, 2), service.submissions);
    try testing.expectEqual(std.meta.Tag(ui_model.Command).proxy_clear_cooldown, service.tags[1]);
    try testing.expectEqualStrings("acct-codex-personal", service.last.?.proxy_clear_cooldown);
    try testing.expectEqual(ui_model.ResetProxyClear.pending, model.reset.proxy_clear);

    shell.pump(model, now + 3);
    try testing.expectEqual(@as(usize, 2), service.submissions);
    try testing.expectEqual(ui_model.ResetProxyClear.pending, model.reset.proxy_clear);

    accounts[0].fact.reset_proxy_clear = .cleared;
    shell.pump(model, now + 4);
    try testing.expectEqual(@as(usize, 2), service.submissions);
    try testing.expectEqual(ui_model.ResetProxyClear.cleared, model.reset.proxy_clear);
}

test "settled reset does not duplicate a service-projected cooldown clear" {
    const windows = [_]domain.UsageWindow{weeklyWindow(87, now + 3600)};
    var accounts = [_]RecordingService.Account{.{ .fact = codexFact(), .windows = &windows }};
    var service: RecordingService = .{
        .accounts = &accounts,
        .capabilities = .{ .connected = true, .reset = true, .proxy_control = true },
    };
    const model = newModel(&service);
    defer testing.allocator.destroy(model);
    var effects: shell.Effects = .{};

    shell.update(model, .{ .begin_reset = 0 }, &effects);
    shell.update(model, .acknowledge_reset, &effects);
    shell.update(model, .confirm_reset, &effects);
    accounts[0].fact.pending_reset_attempt = true;
    shell.pump(model, now + 1);

    accounts[0].fact.pending_reset_attempt = false;
    accounts[0].fact.reset_proxy_clear = .pending;
    shell.pump(model, now + 2);

    try testing.expectEqual(@as(@TypeOf(model.reset.settle), .settled), model.reset.settle);
    try testing.expectEqual(ui_model.ResetProxyClear.pending, model.reset.proxy_clear);
    try testing.expectEqual(@as(usize, 1), service.submissions);
    try testing.expectEqual(std.meta.Tag(ui_model.Command).redeem_reset, service.tags[0]);
}
