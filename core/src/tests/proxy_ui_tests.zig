const std = @import("std");
const bridge = @import("../bridge_json.zig");
const shell = @import("../shell_model.zig");
const ui_model = @import("../ui_model.zig");
const support = @import("ui_projection_test_support.zig");

const testing = std.testing;
const RecordingService = support.RecordingService;
const now = support.now;

const mapped_ready = [_]ui_model.ProxyAccountFact{.{
    .app_id = "acct-codex-personal",
    .storage_key = "codex-personal",
    .proxy_name = "codex-1",
    .label = "Codex Personal",
    .state = .ready,
    .mapped = true,
}};

fn proxyFact(reachability: ui_model.ProxyReachability) ui_model.ProxyFact {
    return .{
        .base_url = "http://127.0.0.1:48787",
        .cli_path = "/private/tmp/codexmulti-ui/bin/proxy-cli",
        .config_path = "/private/tmp/codexmulti-ui/proxy/config.json",
        .reachability = reachability,
        .sync_state = .needed,
        .last_attempt_at_unix_s = now - 60,
        .last_attempt_result = if (reachability == .@"unreachable") .@"unreachable" else .ok,
        .last_success_at_unix_s = now - 120,
        .success_revision = 1,
        .config_path_matches = reachability == .reachable,
        .accounts = &mapped_ready,
    };
}

test "proxy projection remains passive across initial projection tray expansion tabs menus and pump" {
    const model = try support.newModel();
    defer testing.allocator.destroy(model);
    var accounts = [_]RecordingService.Account{.{ .fact = support.codexFact() }};
    var service: RecordingService = .{
        .accounts = &accounts,
        .capabilities = .{ .connected = true, .proxy_control = true },
        .proxy_fact = proxyFact(.reachable),
    };
    model.service = service.port();
    var effects: shell.Effects = .{};

    shell.reproject(model);
    shell.update(model, .open_details, &effects);
    shell.update(model, .{ .toggle_account = 0 }, &effects);
    shell.update(model, .tab_failover, &effects);
    shell.update(model, .{ .open_row_menu = 0 }, &effects);
    shell.update(model, .close_row_menu, &effects);
    shell.update(model, .toggle_proxy_settings, &effects);
    shell.pump(model, now + 60);
    var items: [ui_model.max_tray_items]ui_model.TrayItem = @splat(.{});
    const count = ui_model.buildTray(&model.view, &items);
    const wire = bridge.viewToWire(&model.view, &.{}, items[0..count], "");
    var saw_proxy = false;
    for (wire.tray.items) |item| {
        if (std.mem.startsWith(u8, item.label, "Failover last seen")) saw_proxy = true;
    }
    try testing.expect(saw_proxy);
    try testing.expectEqual(@as(usize, 0), service.submissions);
}

test "proxy cockpit actions emit one exact service command each" {
    const model = try support.newModel();
    defer testing.allocator.destroy(model);
    var rows = mapped_ready;
    var proxy = proxyFact(.reachable);
    proxy.accounts = &rows;
    var accounts = [_]RecordingService.Account{.{ .fact = support.codexFact() }};
    var service: RecordingService = .{
        .accounts = &accounts,
        .capabilities = .{ .connected = true, .proxy_control = true },
        .proxy_fact = proxy,
    };
    model.service = service.port();
    shell.reproject(model);
    var effects: shell.Effects = .{};

    shell.update(model, .refresh_proxy_status, &effects);
    try testing.expectEqual(std.meta.Tag(ui_model.Command).proxy_refresh_status, service.tags[0]);
    shell.update(model, .{ .pause_proxy_account = 0 }, &effects);
    try testing.expectEqualStrings("acct-codex-personal", service.last.?.proxy_pause_account);
    rows[0].state = .paused;
    service.proxy_fact.?.accounts = &rows;
    shell.reproject(model);
    shell.update(model, .{ .resume_proxy_account = 0 }, &effects);
    try testing.expectEqualStrings("acct-codex-personal", service.last.?.proxy_reload_account);
    shell.update(model, .{ .save_proxy_settings = .{
        .base_url = "http://127.0.0.1:49999",
        .cli_path = proxy.cli_path,
        .config_path = proxy.config_path,
        .node_path = "",
    } }, &effects);
    try testing.expectEqualStrings("http://127.0.0.1:49999", service.last.?.save_proxy_settings.base_url);
    try testing.expectEqual(@as(usize, 4), service.submissions);

    rows[0].state = .ready;
    rows[0].active = false;
    service.proxy_fact.?.accounts = &rows;
    shell.reproject(model);
    try testing.expect(model.view.proxyRowSlice()[0].can_switch);
    shell.update(model, .{ .begin_proxy_switch = 0 }, &effects);
    try testing.expect(model.failoverSwitchIsOpen());
    try testing.expectEqual(@as(usize, 4), service.submissions);
    shell.update(model, .confirm_failover_switch, &effects);
    try testing.expectEqualStrings("acct-codex-personal", service.last.?.proxy_switch_account);
    try testing.expectEqual(@as(usize, 5), service.submissions);
    shell.update(model, .{ .begin_proxy_switch = 4 }, &effects);
    try testing.expect(!model.failoverSwitchIsOpen());
}

test "clear cooldown is offered only on cooldown rows and submits only after a two-step confirmation" {
    const model = try support.newModel();
    defer testing.allocator.destroy(model);
    var rows = mapped_ready;
    rows[0].state = .cooldown;
    rows[0].cooldown_until_unix_s = now + 5 * 24 * 3600;
    var proxy = proxyFact(.reachable);
    proxy.accounts = &rows;
    var accounts = [_]RecordingService.Account{.{ .fact = support.codexFact() }};
    var service: RecordingService = .{
        .accounts = &accounts,
        .capabilities = .{ .connected = true, .proxy_control = true },
        .proxy_fact = proxy,
    };
    model.service = service.port();
    shell.reproject(model);
    var effects: shell.Effects = .{};

    try testing.expect(model.view.proxyRowSlice()[0].can_clear_cooldown);
    try testing.expect(!model.view.proxyRowSlice()[0].can_resume);
    rows[0].state = .ready;
    service.proxy_fact.?.accounts = &rows;
    shell.reproject(model);
    try testing.expect(!model.view.proxyRowSlice()[0].can_clear_cooldown);
    rows[0].state = .paused;
    service.proxy_fact.?.accounts = &rows;
    shell.reproject(model);
    try testing.expect(!model.view.proxyRowSlice()[0].can_clear_cooldown);
    rows[0].state = .cooldown;
    service.proxy_fact.?.accounts = &rows;
    shell.reproject(model);

    shell.update(model, .{ .begin_clear_cooldown = 0 }, &effects);
    try testing.expect(model.clearCooldownIsOpen());
    try testing.expectEqualStrings("Codex Personal", model.clearCooldownLabel());
    try testing.expectEqual(@as(usize, 0), service.submissions);
    shell.update(model, .cancel_clear_cooldown, &effects);
    try testing.expect(!model.clearCooldownIsOpen());
    try testing.expectEqual(@as(usize, 0), service.submissions);
    shell.update(model, .{ .begin_clear_cooldown = 0 }, &effects);
    shell.update(model, .confirm_clear_cooldown, &effects);
    try testing.expect(!model.clearCooldownIsOpen());
    try testing.expectEqual(@as(usize, 1), service.submissions);
    try testing.expectEqualStrings("acct-codex-personal", service.last.?.proxy_clear_cooldown);
    shell.update(model, .confirm_clear_cooldown, &effects);
    try testing.expectEqual(@as(usize, 1), service.submissions);
    shell.update(model, .{ .begin_clear_cooldown = 7 }, &effects);
    try testing.expect(!model.clearCooldownIsOpen());
}

test "reachable mapped Codex routes switching only through the proxy service" {
    const model = try support.newModel();
    defer testing.allocator.destroy(model);
    var accounts = [_]RecordingService.Account{.{ .fact = support.codexFact() }};
    var service: RecordingService = .{
        .accounts = &accounts,
        .capabilities = .{ .connected = true, .proxy_control = true },
        .proxy_fact = proxyFact(.reachable),
    };
    model.service = service.port();
    model.expanded = 0;
    shell.reproject(model);
    try testing.expect(model.inspectorUsesProxy());
    try testing.expect(model.inspectorFailoverCanSwitch());
    try testing.expectEqualStrings("Use in failover proxy…", model.inspectorFailoverAction());
    try testing.expectEqualStrings("", model.inspectorFailoverTitle());
    try testing.expect(model.view.rowAt(0).?.canSwitchProxy());
    try testing.expectEqualStrings("Use in failover proxy…", model.view.rowAt(0).?.tray_failover_text);
    var effects: shell.Effects = .{};
    shell.update(model, .{ .begin_failover_switch = 0 }, &effects);
    try testing.expect(model.failoverSwitchIsOpen());
    try testing.expectEqualStrings("Codex Personal", model.failoverSwitchTargetLabel());
    try testing.expectEqual(@as(usize, 0), service.submissions);
    shell.update(model, .confirm_failover_switch, &effects);
    try testing.expect(!model.failoverSwitchIsOpen());
    try testing.expectEqual(@as(usize, 1), service.submissions);
    try testing.expectEqualStrings("acct-codex-personal", service.last.?.proxy_switch_account);

    service.outcome = .failed;
    shell.update(model, .{ .begin_failover_switch = 0 }, &effects);
    shell.update(model, .confirm_failover_switch, &effects);
    try testing.expectEqual(@as(usize, 2), service.submissions);
    try testing.expect(std.mem.indexOf(u8, model.notice.text(), "Failover switch failed") != null);
}

test "F15 expanded Status shows token expiry and repeated renewal failure uses invalid state" {
    const model = try support.newModel();
    defer testing.allocator.destroy(model);
    var rows = mapped_ready;
    rows[0].token_expires_at_unix_s = now + 3 * 24 * 3600;
    var proxy = proxyFact(.reachable);
    proxy.accounts = &rows;
    var accounts = [_]RecordingService.Account{.{ .fact = support.codexFact() }};
    var service: RecordingService = .{
        .accounts = &accounts,
        .capabilities = .{ .connected = true, .proxy_control = true },
        .proxy_fact = proxy,
    };
    model.service = service.port();
    model.expanded = 0;
    shell.reproject(model);

    try testing.expect(std.mem.startsWith(u8, model.view.inspector.connection_line, "Token valid until "));

    rows[0].state = .invalid;
    var token_refresh_failures = [_]bool{true};
    service.proxy_fact.?.accounts = &rows;
    service.proxy_fact.?.token_refresh_failures = &token_refresh_failures;
    shell.reproject(model);

    try testing.expectEqualStrings("Refresh failed · sign in again", model.view.inspector.connection_line);
    try testing.expectEqual(ui_model.ProxyAccountState.invalid, model.view.proxyRowSlice()[0].state);
    try testing.expect(model.view.proxyRowSlice()[0].state_destructive);
    try testing.expectEqual(ui_model.UnifiedFailoverState.invalid, model.view.unifiedRowSlice()[0].failover_state);
}

test "unknown unreachable and incompatible proxy states offer no switch at all" {
    inline for (.{ ui_model.ProxyReachability.unknown, ui_model.ProxyReachability.@"unreachable", ui_model.ProxyReachability.incompatible }) |reachability| {
        const model = try support.newModel();
        defer testing.allocator.destroy(model);
        var accounts = [_]RecordingService.Account{.{ .fact = support.codexFact() }};
        var service: RecordingService = .{
            .accounts = &accounts,
            .capabilities = .{ .connected = true, .proxy_control = true },
            .proxy_fact = proxyFact(reachability),
        };
        model.service = service.port();
        model.expanded = 0;
        shell.reproject(model);
        try testing.expect(!model.inspectorUsesProxy());
        try testing.expect(!model.inspectorFailoverCanSwitch());
        try testing.expectEqualStrings("", model.inspectorFailoverAction());
        try testing.expect(!model.view.rowAt(0).?.canSwitchProxy());
        try testing.expect(!model.view.codexAccountRowSlice()[0].can_switch_proxy);
        try testing.expectEqualStrings("", model.view.rowAt(0).?.tray_failover_text);
        var effects: shell.Effects = .{};
        shell.update(model, .{ .begin_failover_switch = 0 }, &effects);
        try testing.expect(!model.failoverSwitchIsOpen());
        shell.update(model, .confirm_failover_switch, &effects);
        try testing.expectEqual(@as(usize, 0), service.submissions);
    }
}

test "mapped removal does not start app deletion when pause admission fails" {
    const model = try support.newModel();
    defer testing.allocator.destroy(model);
    var accounts = [_]RecordingService.Account{.{ .fact = support.codexFact() }};
    var service: RecordingService = .{
        .accounts = &accounts,
        .capabilities = .{ .connected = true, .accounts = true, .proxy_control = true },
        .proxy_fact = proxyFact(.reachable),
        .outcome = .failed,
    };
    model.service = service.port();
    shell.reproject(model);
    var effects: shell.Effects = .{};

    shell.update(model, .{ .begin_remove = 0 }, &effects);
    shell.update(model, .confirm_remove, &effects);
    try testing.expect(!model.removePauseRequested());
    try testing.expect(!model.removeCanFinish());
    shell.update(model, .finish_mapped_remove, &effects);
    try testing.expectEqual(@as(usize, 1), service.submissions);
    try testing.expectEqual(std.meta.Tag(ui_model.Command).proxy_pause_account, service.tags[0]);
}

test "mapped removal pauses then requires a later explicit status revision before remove and sync" {
    const model = try support.newModel();
    defer testing.allocator.destroy(model);
    var rows = mapped_ready;
    rows[0].active = true;
    var proxy = proxyFact(.reachable);
    proxy.accounts = &rows;
    var accounts = [_]RecordingService.Account{.{ .fact = support.codexFact() }};
    var service: RecordingService = .{
        .accounts = &accounts,
        .capabilities = .{ .connected = true, .accounts = true, .proxy_control = true },
        .proxy_fact = proxy,
    };
    model.service = service.port();
    shell.reproject(model);
    var effects: shell.Effects = .{};

    shell.update(model, .{ .begin_remove = 0 }, &effects);
    try testing.expect(model.removeUsesProxy());
    shell.update(model, .confirm_remove, &effects);
    try testing.expectEqual(std.meta.Tag(ui_model.Command).proxy_pause_account, service.tags[0]);
    try testing.expectEqual(@as(usize, 1), service.submissions);

    rows[0].state = .paused;
    rows[0].in_flight = 0;
    service.proxy_fact.?.accounts = &rows;
    shell.reproject(model);
    try testing.expect(!model.removeCanFinish());
    shell.update(model, .finish_mapped_remove, &effects);
    try testing.expectEqual(@as(usize, 1), service.submissions);

    service.proxy_fact.?.success_revision = 2;
    shell.reproject(model);
    try testing.expect(model.removeCanFinish());
    shell.update(model, .finish_mapped_remove, &effects);
    try testing.expectEqual(std.meta.Tag(ui_model.Command).remove_account, service.tags[1]);
    try testing.expectEqual(std.meta.Tag(ui_model.Command).proxy_sync_config, service.tags[2]);
    try testing.expectEqual(@as(usize, 3), service.submissions);
}

test "an unreachable proxy raises a banner with retry and the header pill says so" {
    const model = try support.newModel();
    defer testing.allocator.destroy(model);
    var accounts = [_]RecordingService.Account{.{ .fact = support.codexFact() }};
    var service: RecordingService = .{
        .accounts = &accounts,
        .capabilities = .{ .connected = true, .proxy_control = true },
        .proxy_fact = proxyFact(.@"unreachable"),
    };
    model.service = service.port();
    shell.reproject(model);

    try testing.expect(model.proxyShowsBanner());
    try testing.expect(std.mem.startsWith(u8, model.proxyBannerText(), "Proxy unreachable · last seen 11:58"));
    try testing.expect(std.mem.indexOf(u8, model.proxyBannerText(), "falls back to local login") != null);
    try testing.expectEqualStrings("Failover · unreachable", model.proxyPillText());
    try testing.expect(model.proxyPillBad() and !model.proxyPillOk());
    try testing.expect(bridge.shellToWire(model).proxy_can_refresh);

    service.proxy_fact = proxyFact(.reachable);
    shell.reproject(model);
    try testing.expect(model.proxyShowsBanner());
    try testing.expectEqualStrings(
        "Account changes reach the proxy on the next refresh.",
        model.proxyBannerText(),
    );
    try testing.expectEqualStrings(
        "Account changes reach the proxy on the next refresh.",
        model.view.proxy_detail_text,
    );
    try testing.expect(model.proxyPillOk());
}

test "busy proxy sync copy says account changes will be retried" {
    const model = try support.newModel();
    defer testing.allocator.destroy(model);
    var accounts = [_]RecordingService.Account{.{ .fact = support.codexFact() }};
    var fact = proxyFact(.reachable);
    fact.last_attempt_result = .action_failed;
    var service: RecordingService = .{
        .accounts = &accounts,
        .capabilities = .{ .connected = true, .proxy_control = true },
        .proxy_fact = fact,
    };
    model.service = service.port();
    shell.reproject(model);

    const expected = "The proxy was busy · account changes will be retried on the next refresh.";
    try testing.expectEqualStrings(expected, model.view.proxy_detail_text);
    try testing.expectEqualStrings(expected, model.proxyBannerText());
}

test "a sync that failed on a missing node interpreter names the setting to fix" {
    const model = try support.newModel();
    defer testing.allocator.destroy(model);
    var accounts = [_]RecordingService.Account{.{ .fact = support.codexFact() }};
    var fact = proxyFact(.reachable);
    fact.sync_state = .failed;
    fact.last_attempt_result = .import_node_missing;
    fact.node_path = "";
    fact.node_resolved = "";
    var service: RecordingService = .{
        .accounts = &accounts,
        .capabilities = .{ .connected = true, .proxy_control = true },
        .proxy_fact = fact,
    };
    model.service = service.port();
    shell.reproject(model);

    try testing.expectEqualStrings("Node: not found — set Node path in Connection settings", model.proxyNodeHint());

    fact.sync_state = .synced;
    fact.last_attempt_result = .ok;
    fact.node_resolved = "/private/tmp/codexmulti-ui/bin/node";
    service.proxy_fact = fact;
    shell.reproject(model);
    try testing.expectEqualStrings("Node: auto → /private/tmp/codexmulti-ui/bin/node", model.proxyNodeHint());

    fact.node_path = "/private/tmp/codexmulti-ui/explicit/node";
    fact.node_resolved = "/private/tmp/codexmulti-ui/explicit/node";
    service.proxy_fact = fact;
    shell.reproject(model);
    try testing.expectEqualStrings("Node: /private/tmp/codexmulti-ui/explicit/node", model.proxyNodeHint());

    const wire = bridge.viewToWire(&model.view, &.{}, &.{}, "");
    try testing.expectEqualStrings("/private/tmp/codexmulti-ui/explicit/node", wire.proxy_node_path);
}

test "the failover projection has no summary helpers and in flight is a number" {
    try testing.expect(!@hasDecl(shell.Model, "proxySummaryLine"));
    try testing.expect(!@hasDecl(shell.Model, "proxyFreshnessLine"));

    const model = try support.newModel();
    defer testing.allocator.destroy(model);
    var rows = mapped_ready;
    rows[0].in_flight = 4;
    var proxy = proxyFact(.reachable);
    proxy.sync_state = .synced;
    proxy.in_flight = 4;
    proxy.accounts = &rows;
    var accounts = [_]RecordingService.Account{.{ .fact = support.codexFact() }};
    var service: RecordingService = .{
        .accounts = &accounts,
        .capabilities = .{ .connected = true, .proxy_control = true },
        .proxy_fact = proxy,
    };
    model.service = service.port();
    shell.reproject(model);
    try testing.expectEqualStrings("4", model.proxyTableRows()[0].in_flight_text);
    rows[0].in_flight = 0;
    service.proxy_fact = proxy;
    shell.reproject(model);
    try testing.expectEqualStrings("", model.proxyTableRows()[0].in_flight_text);
}
