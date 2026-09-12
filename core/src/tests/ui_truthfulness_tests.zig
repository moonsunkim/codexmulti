const std = @import("std");

const domain = @import("../domain.zig");
const coordinator = @import("../coordinator.zig");
const ui_model = @import("../ui_model.zig");
const shell = @import("../shell_model.zig");
const support = @import("ui_projection_test_support.zig");

const testing = std.testing;

const now = support.now;
const RecordingService = support.RecordingService;
const weeklyWindow = support.weeklyWindow;
const sessionWindow = support.sessionWindow;
const claudeFact = support.claudeFact;
const codexFact = support.codexFact;
const newModel = support.newModel;

fn moveAccounts() [3]RecordingService.Account {
    var alpha = codexFact();
    alpha.account_id = "acct-codex-alpha";
    alpha.label = "Alpha";
    var beta = codexFact();
    beta.account_id = "acct-codex-beta";
    beta.label = "Beta";
    var gamma = codexFact();
    gamma.account_id = "acct-codex-gamma";
    gamma.label = "Gamma";
    return .{ .{ .fact = alpha }, .{ .fact = beta }, .{ .fact = gamma } };
}

test "Codex sign-in rejection copy does not name another product" {
    try testing.expectEqualStrings(
        "Codex did not approve this sign-in. Try again and finish the browser confirmation.",
        ui_model.attemptMessage("login-rejected"),
    );
}

test "production core user-facing string literals do not name Claude" {
    const paths = [_][]const u8{
        "src/ui_format.zig",
        "src/account_registry.zig",
        "src/app_service.zig",
    };
    for (paths) |path| {
        const source = try std.Io.Dir.cwd().readFileAlloc(
            testing.io,
            path,
            testing.allocator,
            .limited(1024 * 1024),
        );
        defer testing.allocator.free(source);
        try testing.expect(std.mem.indexOf(u8, source, "\"Claude") == null);
    }
}

test "an unattached service yields an empty view that claims nothing" {
    const model = try newModel();
    defer testing.allocator.destroy(model);

    shell.reproject(model);

    try testing.expect(model.view.isEmpty());
    try testing.expect(!model.hasAccounts());
    try testing.expectEqualStrings("No accounts registered yet", model.fleetSummary());
    try testing.expectEqualStrings(
        "Application service not connected — this window shows local view state only.",
        model.serviceSummary(),
    );
    try testing.expect(!model.canRefresh());
    try testing.expect(!model.canManageAccounts());

    try testing.expect(std.mem.indexOf(u8, model.fleetSummary(), "%") == null);
}

test "move_account maps registry-ordered rows upward downward and to the final place" {
    const model = try newModel();
    defer testing.allocator.destroy(model);
    var accounts = moveAccounts();
    var proxy_accounts = [_]ui_model.ProxyAccountFact{
        .{ .app_id = "acct-codex-gamma", .storage_key = "gamma", .proxy_name = "gamma", .label = "Gamma", .state = .ready, .mapped = true },
        .{ .app_id = "acct-codex-alpha", .storage_key = "alpha", .proxy_name = "alpha", .label = "Alpha", .state = .ready, .mapped = true },
        .{ .app_id = "acct-codex-beta", .storage_key = "beta", .proxy_name = "beta", .label = "Beta", .state = .ready, .mapped = true },
    };
    var service: RecordingService = .{
        .accounts = &accounts,
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
    model.service = service.port();
    shell.reproject(model);
    var effects: shell.Effects = .{};

    try testing.expectEqual(ui_model.UnifiedOrderSource.registry, model.view.unified_order_source);
    try testing.expectEqualStrings("acct-codex-alpha", model.view.unified_rows[0].account_id);
    try testing.expectEqualStrings("acct-codex-beta", model.view.unified_rows[1].account_id);
    try testing.expectEqualStrings("acct-codex-gamma", model.view.unified_rows[2].account_id);

    shell.update(model, .{ .move_account = .{ .account_id = model.view.unified_rows[0].account_id, .target_account_id = model.view.unified_rows[1].account_id } }, &effects);
    try testing.expectEqualStrings("acct-codex-alpha", service.last.?.move_account.account_id);
    try testing.expectEqualStrings("acct-codex-beta", service.last.?.move_account.target_account_id);

    shell.update(model, .{ .move_account = .{ .account_id = model.view.unified_rows[2].account_id, .target_account_id = model.view.unified_rows[0].account_id } }, &effects);
    try testing.expectEqualStrings("acct-codex-gamma", service.last.?.move_account.account_id);
    try testing.expectEqualStrings("acct-codex-alpha", service.last.?.move_account.target_account_id);

    shell.update(model, .{ .move_account = .{ .account_id = model.view.unified_rows[0].account_id, .target_account_id = model.view.unified_rows[2].account_id } }, &effects);
    try testing.expectEqualStrings("acct-codex-alpha", service.last.?.move_account.account_id);
    try testing.expectEqualStrings("acct-codex-gamma", service.last.?.move_account.target_account_id);
    try testing.expectEqual(@as(usize, 3), service.submissions);
}

test "unified rows keep registry order when reachable proxy order differs" {
    const model = try newModel();
    defer testing.allocator.destroy(model);
    var accounts = moveAccounts();
    var proxy_accounts = [_]ui_model.ProxyAccountFact{
        .{ .app_id = "acct-codex-alpha", .storage_key = "alpha", .proxy_name = "alpha", .label = "Alpha", .state = .ready, .mapped = true },
        .{ .app_id = "acct-codex-gamma", .storage_key = "gamma", .proxy_name = "gamma", .label = "Gamma", .state = .ready, .mapped = true },
        .{ .app_id = "acct-codex-beta", .storage_key = "beta", .proxy_name = "beta", .label = "Beta", .state = .ready, .mapped = true },
    };
    var service: RecordingService = .{
        .accounts = &accounts,
        .proxy_fact = .{
            .base_url = "http://127.0.0.1:8787",
            .cli_path = "/tmp/proxy",
            .config_path = "/tmp/config",
            .reachability = .reachable,
            .sync_state = .needed,
            .success_revision = 1,
            .config_path_matches = true,
            .accounts = &proxy_accounts,
        },
    };
    model.service = service.port();

    shell.reproject(model);

    try testing.expectEqual(ui_model.UnifiedOrderSource.registry, model.view.unified_order_source);
    try testing.expectEqualStrings("acct-codex-alpha", model.view.unified_rows[0].account_id);
    try testing.expectEqualStrings("acct-codex-beta", model.view.unified_rows[1].account_id);
    try testing.expectEqualStrings("acct-codex-gamma", model.view.unified_rows[2].account_id);
    try testing.expectEqual(@as(?u32, 0), model.view.unified_rows[0].proxy_index);
    try testing.expectEqual(@as(?u32, 2), model.view.unified_rows[1].proxy_index);
    try testing.expectEqual(@as(?u32, 1), model.view.unified_rows[2].proxy_index);
}

test "move_account silently ignores the same place and unknown projected rows" {
    const model = try newModel();
    defer testing.allocator.destroy(model);
    var accounts = moveAccounts();
    var service: RecordingService = .{ .accounts = &accounts };
    model.service = service.port();
    shell.reproject(model);
    var effects: shell.Effects = .{};
    const projections = service.projections;

    shell.update(model, .{ .move_account = .{ .account_id = model.view.unified_rows[1].account_id, .target_account_id = model.view.unified_rows[1].account_id } }, &effects);
    shell.update(model, .{ .move_account = .{ .account_id = model.view.unified_rows[3].account_id, .target_account_id = model.view.unified_rows[0].account_id } }, &effects);
    shell.update(model, .{ .move_account = .{ .account_id = model.view.unified_rows[0].account_id, .target_account_id = model.view.unified_rows[3].account_id } }, &effects);

    try testing.expectEqual(@as(usize, 0), service.submissions);
    try testing.expectEqual(projections, service.projections);
    try testing.expectEqual(ui_model.NoticeKind.none, model.notice.kind);
    try testing.expectEqual(@as(usize, 0), effects.len);
}

test "move_account busy result uses the existing notice outcome wording" {
    const model = try newModel();
    defer testing.allocator.destroy(model);
    var accounts = moveAccounts();
    var service: RecordingService = .{ .accounts = &accounts, .outcome = .rejected_busy };
    model.service = service.port();
    shell.reproject(model);
    var effects: shell.Effects = .{};

    shell.update(model, .{ .move_account = .{ .account_id = model.view.unified_rows[0].account_id, .target_account_id = model.view.unified_rows[1].account_id } }, &effects);

    try testing.expectEqual(@as(usize, 1), service.submissions);
    try testing.expectEqual(ui_model.NoticeKind.blocked, model.notice.kind);
    try testing.expectEqualStrings(
        "Account order refused for Alpha: an operation is already in flight.",
        model.notice.text(),
    );
}

test "every freshness state renders its own honest wording" {
    const expected = [_]struct { state: ui_model.Freshness, text: []const u8, phrase: []const u8 }{
        .{ .state = .never_refreshed, .text = "Never refreshed", .phrase = "never refreshed" },
        .{ .state = .as_of, .text = "As of the last successful refresh", .phrase = "as of the last successful refresh" },
        .{ .state = .saved_snapshot, .text = "Saved snapshot", .phrase = "saved snapshot" },
        .{ .state = .refresh_failed, .text = "Refresh failed", .phrase = "refresh failed" },
        .{ .state = .reauth_required, .text = "Reauthentication required", .phrase = "reauthentication required" },
        .{ .state = .usage_unavailable, .text = "Usage unavailable", .phrase = "usage unavailable" },
        .{ .state = .refresh_deferred, .text = "Refresh deferred", .phrase = "refresh deferred" },
        .{ .state = .reset_passed, .text = "Reset passed — refresh to confirm", .phrase = "reset passed — refresh to confirm" },
    };
    inline for (@typeInfo(ui_model.Freshness).@"enum".fields) |field| {
        var found = false;
        for (expected) |entry| {
            if (@intFromEnum(entry.state) == field.value) {
                try testing.expectEqualStrings(entry.text, ui_model.freshnessText(entry.state));

                try testing.expectEqualStrings(entry.phrase, ui_model.freshnessPhrase(entry.state));
                found = true;
            }
        }

        try testing.expect(found);
    }
}

test "a failed attempt's short reason is a phrase, never the sanitized slug" {
    try testing.expectEqualStrings("helper closed", ui_model.attemptReason("app-server-closed"));
    try testing.expectEqualStrings("timed out", ui_model.attemptReason("refresh-timeout"));
    try testing.expectEqualStrings("sign-in required", ui_model.attemptReason("sign-in-required"));
    try testing.expectEqualStrings("Keychain repair needed", ui_model.attemptReason("keychain-access-repair-required"));

    try testing.expectEqualStrings("refresh failed", ui_model.attemptReason("some-new-code"));
    for ([_][]const u8{ "app-server-closed", "refresh-timeout", "login-io", "usage-incomplete", "codex-home-mismatch" }) |code| {
        const reason = ui_model.attemptReason(code);
        try testing.expect(!std.mem.eql(u8, reason, code));
        try testing.expect(std.mem.indexOf(u8, reason, code) == null);

        try testing.expect(std.mem.indexOf(u8, reason, " ") != null);
    }
}

test "a loading account keeps its saved snapshot and says it is working" {
    const model = try newModel();
    defer testing.allocator.destroy(model);

    var fact = codexFact();
    fact.operation_in_flight = true;
    const windows = [_]domain.UsageWindow{weeklyWindow(34, now + 3 * 86400)};
    var accounts = [_]RecordingService.Account{.{ .fact = fact, .windows = &windows }};
    var service: RecordingService = .{ .accounts = &accounts };
    model.service = service.port();
    model.expanded = 0;

    shell.reproject(model);

    const row = model.view.rowAt(0).?;
    try testing.expect(row.operation_in_flight);
    try testing.expectEqualStrings("Saved snapshot", row.freshness_text);

    try testing.expectEqualStrings("Codex Personal — refreshing usage", row.tray_text);

    try testing.expectEqualStrings("Updating…", row.summary_text);
    try testing.expectEqual(@as(u32, 1), model.view.busy_count);

    const rows = model.view.accountRowSlice();
    try testing.expectEqual(@as(usize, 1), rows.len);
    try testing.expect(rows[0].dot_busy);
    try testing.expect(rows[0].action_busy);
    try testing.expectEqualStrings("Refreshing…", rows[0].busy_label);
    try testing.expectEqualStrings("Updating…", rows[0].chip_a.text);

    try testing.expect(rows[0].window.present);
    try testing.expectEqualStrings("34%", rows[0].window.percent_text);
    try testing.expectEqual(@as(usize, 1), model.usageRows().len);
    try testing.expectEqualStrings("34%", model.usageRows()[0].percent_text);
}

test "a failed refresh explains the problem beside the account" {
    const model = try newModel();
    defer testing.allocator.destroy(model);

    var fact = codexFact();
    fact.freshness = .refresh_failed;
    fact.last_attempt_code = "app-server-closed";
    fact.last_attempt_at_unix_s = now - 120;
    var accounts = [_]RecordingService.Account{.{ .fact = fact }};
    var service: RecordingService = .{ .accounts = &accounts };
    model.service = service.port();
    model.expanded = 0;
    shell.reproject(model);

    const rows = model.view.accountRowSlice();
    try testing.expect(rows[0].dot_failed);
    try testing.expect(rows[0].chip_a.destructive);
    try testing.expect(std.mem.startsWith(u8, rows[0].chip_a.text, "Refresh failed"));
    try testing.expect(rows[0].action_refresh);

    try testing.expect(model.inspectorAttention());
    try testing.expect(std.mem.indexOf(u8, model.inspectorAttentionText(), "Codex helper closed before replying") != null);
    try testing.expect(std.mem.indexOf(u8, model.inspectorAttentionText(), "Last good reading") != null);

    try testing.expectEqualStrings("failed Jul 25 11:58 KST · helper closed", model.detailEvidence());
    try testing.expect(std.mem.indexOf(u8, model.detailEvidence(), "last success") == null);

    accounts[0].fact.freshness = .saved_snapshot;
    accounts[0].fact.last_attempt_code = null;
    accounts[0].fact.operation_in_flight = true;
    shell.reproject(model);
    try testing.expectEqualStrings("Jul 25 11:50 KST", model.detailEvidence());
}

test "an account with no reported window says so instead of showing zero" {
    const model = try newModel();
    defer testing.allocator.destroy(model);

    var fact = codexFact();
    fact.freshness = .usage_unavailable;
    fact.snapshot_status = .unavailable;
    var accounts = [_]RecordingService.Account{.{ .fact = fact }};
    var service: RecordingService = .{ .accounts = &accounts };
    model.service = service.port();
    model.expanded = 0;

    shell.reproject(model);

    const row = model.view.rowAt(0).?;
    try testing.expect(row.primary == null);

    try testing.expectEqualStrings("Usage unavailable", row.summary_text);
    try testing.expect(std.mem.indexOf(u8, row.summary_text, "0%") == null);
    try testing.expectEqualStrings("Usage unavailable", row.freshness_text);
    try testing.expectEqual(@as(u32, 1), model.view.error_count);

    try testing.expectEqual(@as(usize, 0), model.usageRows().len);
    try testing.expect(std.mem.indexOf(u8, model.inspectorNoUsage(), "no usage window") != null);
}

test "pool projection excludes unavailable proxy accounts and rounds remaining weekly capacity" {
    var view: ui_model.ViewState = .{};
    view.begin(now, .{ .connected = true, .proxy_control = true }, .kst);

    const ids = [_][]const u8{
        "acct-active",
        "acct-ready-a",
        "acct-cooldown",
        "acct-ready-b",
        "acct-paused",
        "acct-invalid",
        "acct-unmapped",
        "acct-refreshing",
        "acct-missing",
    };
    const used = [_]u8{ 33, 32, 32, 33, 0, 0, 0, 0, 0 };
    for (ids, used) |account_id, used_percent| {
        var fact = codexFact();
        fact.account_id = account_id;
        const slot = try view.pushAccount(fact);
        try view.pushWindow(slot, .{
            .kind = .weekly,
            .label = "Weekly",
            .used_percent = used_percent,
            .reset_at_unix_s = now + 7 * 86400,
        });
    }
    const proxy_accounts = [_]ui_model.ProxyAccountFact{
        .{ .app_id = ids[0], .proxy_name = "active", .label = "Active", .state = .unknown, .active = true, .mapped = true },
        .{ .app_id = ids[1], .proxy_name = "ready-a", .label = "Ready A", .state = .ready, .mapped = true },
        .{ .app_id = ids[2], .proxy_name = "cooldown", .label = "Cooldown", .state = .cooldown, .mapped = true },
        .{ .app_id = ids[3], .proxy_name = "ready-b", .label = "Ready B", .state = .ready, .mapped = true },
        .{ .app_id = ids[4], .proxy_name = "paused", .label = "Paused", .state = .paused, .mapped = true },
        .{ .app_id = ids[5], .proxy_name = "invalid", .label = "Invalid", .state = .invalid, .active = true, .mapped = true },
        .{ .app_id = ids[6], .proxy_name = "unmapped", .label = "Unmapped", .state = .ready, .mapped = false },
        .{ .app_id = ids[7], .proxy_name = "refreshing", .label = "Refreshing", .state = .refreshing, .mapped = true },
    };
    view.applyProxy(.{
        .base_url = "",
        .cli_path = "",
        .config_path = "",
        .reachability = .reachable,
        .config_path_matches = true,
        .accounts = &proxy_accounts,
    });
    view.applyProxyService(.{ .state = .running, .routing_state = .on });
    view.finish(.{});

    try testing.expectEqual(@as(?u8, 68), view.pool_remaining_percent);
    try testing.expectEqual(@as(u32, 4), view.pool_usable_count);
    try testing.expectEqual(@as(u32, 9), view.pool_total_count);
}

test "pool projection uses every registered account when the proxy is not installed" {
    var view: ui_model.ViewState = .{};
    view.begin(now, .{ .connected = true }, .kst);

    const values = [_]u8{ 20, 80 };
    for (values, 0..) |used_percent, index| {
        var fact = codexFact();
        fact.account_id = if (index == 0) "acct-one" else "acct-two";
        const slot = try view.pushAccount(fact);
        try view.pushWindow(slot, weeklyWindow(used_percent, now + 7 * 86400));
    }
    view.finish(.{});

    try testing.expectEqual(@as(?u8, 50), view.pool_remaining_percent);
    try testing.expectEqual(@as(u32, 2), view.pool_usable_count);
    try testing.expectEqual(@as(u32, 2), view.pool_total_count);
}

test "pool projection stays absent when no accounts are registered" {
    var view: ui_model.ViewState = .{};
    view.begin(now, .{ .connected = true }, .kst);
    view.finish(.{});

    try testing.expectEqual(@as(?u8, null), view.pool_remaining_percent);
    try testing.expectEqual(@as(u32, 0), view.pool_usable_count);
    try testing.expectEqual(@as(u32, 0), view.pool_total_count);
    try testing.expectEqualStrings("", view.pool_tray_text);
}

test "reauth and deferred accounts are counted and worded apart" {
    const model = try newModel();
    defer testing.allocator.destroy(model);

    var reauth = codexFact();
    reauth.account_id = "acct-codex-reauth";
    reauth.label = "Codex Reauth";
    reauth.freshness = .reauth_required;
    reauth.auth_state = .reauth_required;
    var deferred = codexFact();
    deferred.freshness = .refresh_deferred;
    var accounts = [_]RecordingService.Account{
        .{ .fact = reauth },
        .{ .fact = deferred },
    };
    var service: RecordingService = .{ .accounts = &accounts };
    model.service = service.port();

    shell.reproject(model);

    try testing.expectEqual(@as(u32, 1), model.view.reauth_count);
    try testing.expectEqual(@as(u32, 1), model.view.stale_count);
    try testing.expectEqualStrings(
        "Codex Reauth — sign-in required",
        model.view.rowAt(0).?.tray_text,
    );
    try testing.expectEqualStrings("Refresh deferred", model.view.rowAt(1).?.freshness_text);
}

test "an account that never refreshed records no success and no attempt" {
    const model = try newModel();
    defer testing.allocator.destroy(model);

    var fact = codexFact();
    fact.freshness = .never_refreshed;
    fact.has_snapshot = false;
    fact.snapshot_status = null;
    fact.snapshot_captured_at_unix_s = null;
    fact.last_attempt_at_unix_s = null;
    fact.last_success_at_unix_s = null;
    var accounts = [_]RecordingService.Account{.{ .fact = fact }};
    var service: RecordingService = .{ .accounts = &accounts };
    model.service = service.port();
    model.expanded = 0;

    shell.reproject(model);

    const row = model.view.rowAt(0).?;
    try testing.expectEqualStrings("No saved snapshot yet", row.summary_text);
    try testing.expectEqualStrings(
        "no successful refresh recorded · no attempt recorded",
        row.evidence_text,
    );
    try testing.expectEqual(@as(u32, 0), model.view.snapshot_count);

    try testing.expectEqualStrings("Never refreshed", model.detailEvidence());
    try testing.expectEqualStrings("Never refreshed", model.inspectorFreshness());
    try testing.expectEqualStrings("No saved snapshot yet.", model.inspectorNoUsage());
}

test "the most constraining window is chosen, never synthesized" {
    try testing.expect(ui_model.selectPrimaryWindow(&.{}) == null);

    const higher_percentage = [_]ui_model.WindowView{
        .{ .label = "5-hour", .used_percent = 30, .reset_at_unix_s = now + 100 },
        .{ .label = "Weekly", .used_percent = 81, .reset_at_unix_s = now + 500_000 },
    };
    try testing.expectEqual(@as(?usize, 1), ui_model.selectPrimaryWindow(&higher_percentage));

    const tie_earlier_reset = [_]ui_model.WindowView{
        .{ .label = "Weekly", .used_percent = 50, .reset_at_unix_s = now + 900 },
        .{ .label = "5-hour", .used_percent = 50, .reset_at_unix_s = now + 300 },
    };
    try testing.expectEqual(@as(?usize, 1), ui_model.selectPrimaryWindow(&tie_earlier_reset));

    const tie_known_reset = [_]ui_model.WindowView{
        .{ .label = "Opus", .used_percent = 50, .reset_at_unix_s = null },
        .{ .label = "Weekly", .used_percent = 50, .reset_at_unix_s = now + 300 },
    };
    try testing.expectEqual(@as(?usize, 1), ui_model.selectPrimaryWindow(&tie_known_reset));
    const tie_unknown_second = [_]ui_model.WindowView{
        .{ .label = "Weekly", .used_percent = 50, .reset_at_unix_s = now + 300 },
        .{ .label = "Opus", .used_percent = 50, .reset_at_unix_s = null },
    };
    try testing.expectEqual(@as(?usize, 0), ui_model.selectPrimaryWindow(&tie_unknown_second));
}

test "Codex rows select the binding window from the provider plan" {
    const after_reset = [_]ui_model.WindowView{
        .{ .label = "5-hour", .kind = .session, .used_percent = 0, .reset_at_unix_s = now + 3 * 3600 },
        .{ .label = "Weekly", .kind = .weekly, .used_percent = 0, .reset_at_unix_s = now + 6 * 86400 },
    };
    try testing.expectEqual(@as(?usize, 0), ui_model.selectPrimaryWindow(&after_reset));
    try testing.expectEqual(@as(?usize, 1), ui_model.selectCodexPrimaryWindow("Pro 20x", &after_reset));
    try testing.expectEqual(@as(?usize, 0), ui_model.selectCodexPrimaryWindow("Plus", &after_reset));

    const fuller_session = [_]ui_model.WindowView{
        .{ .label = "5-hour", .kind = .session, .used_percent = 91, .reset_at_unix_s = now + 3600 },
        .{ .label = "Weekly", .kind = .weekly, .used_percent = 34, .reset_at_unix_s = now + 5 * 86400 },
    };
    try testing.expectEqual(@as(?usize, 1), ui_model.selectCodexPrimaryWindow("Pro 20x", &fuller_session));
    try testing.expectEqual(@as(?usize, 1), ui_model.selectCodexPrimaryWindow("Pro 5x", &fuller_session));
    try testing.expectEqual(@as(?usize, 0), ui_model.selectCodexPrimaryWindow("Plus", &fuller_session));
    try testing.expectEqual(@as(?usize, 0), ui_model.selectCodexPrimaryWindow("Future Max", &fuller_session));
    try testing.expectEqual(@as(?usize, 0), ui_model.selectCodexPrimaryWindow(null, &fuller_session));

    const no_weekly = [_]ui_model.WindowView{
        .{ .label = "5-hour", .kind = .session, .used_percent = 30, .reset_at_unix_s = now + 3600 },
        .{ .label = "GPT-5.3-Codex-Spark", .kind = .other, .used_percent = 70, .reset_at_unix_s = null },
    };
    try testing.expect(ui_model.selectCodexPrimaryWindow("Pro 20x", &no_weekly) == null);
    try testing.expectEqual(@as(?usize, 0), ui_model.selectCodexPrimaryWindow("Plus", &no_weekly));
    try testing.expectEqual(@as(?usize, 1), ui_model.selectCodexPrimaryWindow("Future Max", &no_weekly));
    try testing.expect(ui_model.selectCodexPrimaryWindow("Plus", &[_]ui_model.WindowView{}) == null);
}

test "Codex plan classes accept current and persisted Pro labels" {
    try testing.expectEqual(ui_model.CodexPlanClass.weekly_only, ui_model.codexPlanClass("Pro 5x"));
    try testing.expectEqual(ui_model.CodexPlanClass.weekly_only, ui_model.codexPlanClass("Pro 20x"));
    try testing.expectEqual(ui_model.CodexPlanClass.weekly_only, ui_model.codexPlanClass("x5"));
    try testing.expectEqual(ui_model.CodexPlanClass.weekly_only, ui_model.codexPlanClass("x20"));
    try testing.expectEqual(ui_model.CodexPlanClass.weekly_only, ui_model.codexPlanClass("Pro"));
    try testing.expectEqual(ui_model.CodexPlanClass.weekly_only, ui_model.codexPlanClass("Pro Lite"));
    try testing.expectEqual(ui_model.CodexPlanClass.session_and_weekly, ui_model.codexPlanClass("Plus"));
    try testing.expectEqual(ui_model.CodexPlanClass.all_windows, ui_model.codexPlanClass("Future Max"));
    try testing.expectEqual(ui_model.CodexPlanClass.all_windows, ui_model.codexPlanClass(null));
}

test "Codex usage preference selects weekly session or auto and falls back without invention" {
    const weekly_only = [_]ui_model.WindowView{
        .{ .label = "Weekly", .kind = .weekly, .used_percent = 34, .reset_at_unix_s = now + 5 * 86400 },
    };
    const session_and_weekly = [_]ui_model.WindowView{
        .{ .label = "5-hour", .kind = .session, .used_percent = 81, .reset_at_unix_s = now + 3600 },
        .{ .label = "Weekly", .kind = .weekly, .used_percent = 34, .reset_at_unix_s = now + 5 * 86400 },
    };
    const none = [_]ui_model.WindowView{};

    const cases = [_]struct {
        preference: ui_model.CodexUsageWindow,
        weekly_only: ?usize,
        session_and_weekly: ?usize,
    }{
        .{ .preference = .auto, .weekly_only = 0, .session_and_weekly = 0 },
        .{ .preference = .weekly, .weekly_only = 0, .session_and_weekly = 1 },
        .{ .preference = .session, .weekly_only = 0, .session_and_weekly = 0 },
    };
    for (cases) |case| {
        try testing.expectEqual(
            case.weekly_only,
            ui_model.selectConfiguredCodexPrimaryWindow("Plus", &weekly_only, case.preference, false),
        );
        try testing.expectEqual(
            case.session_and_weekly,
            ui_model.selectConfiguredCodexPrimaryWindow("Plus", &session_and_weekly, case.preference, false),
        );
        try testing.expect(
            ui_model.selectConfiguredCodexPrimaryWindow("Plus", &none, case.preference, false) == null,
        );
    }
}

test "Codex per-model limits control both headline eligibility and exact duplicate rows" {
    const windows = [_]domain.UsageWindow{
        weeklyWindow(50, now + 5 * 86400),
        .{ .kind = .model_scoped, .label = "GPT-5.3-Codex-Spark", .model_label = "GPT-5.3-Codex-Spark", .used_percent = 90, .reset_at_unix_s = now + 2 * 3600 },
        .{ .kind = .model_scoped, .label = "GPT-5.3-Codex-Spark", .model_label = "GPT-5.3-Codex-Spark", .used_percent = 90, .reset_at_unix_s = now + 2 * 3600 },
        .{ .kind = .model_scoped, .label = "GPT-5.3-Codex-Spark", .model_label = "GPT-5.3-Codex-Spark", .used_percent = 40, .reset_at_unix_s = now + 7 * 86400 },
        .{ .kind = .model_scoped, .label = "gpt-reserve", .model_label = "gpt-reserve", .used_percent = 70, .reset_at_unix_s = now + 7 * 86400 },
    };
    var fact = codexFact();
    fact.plan_label = "Team";

    const model = try newModel();
    defer testing.allocator.destroy(model);
    var accounts = [_]RecordingService.Account{.{ .fact = fact, .windows = &windows }};
    var service: RecordingService = .{ .accounts = &accounts };
    model.service = service.port();
    model.expanded = 0;

    shell.reproject(model);
    try testing.expectEqual(@as(?usize, 0), model.view.rowAt(0).?.primary);
    try testing.expectEqual(@as(usize, 1), model.usageRows().len);

    model.view.applyCodexSettings(.auto, true);
    model.view.finish(.{ .selected = 0 });
    try testing.expectEqual(@as(?usize, 1), model.view.rowAt(0).?.primary);
    try testing.expectEqual(@as(usize, 4), model.usageRows().len);
    try testing.expectEqualStrings("GPT-5.3-Codex-Spark", model.usageRows()[1].label);
    try testing.expectEqualStrings("GPT-5.3-Codex-Spark", model.usageRows()[2].label);
    try testing.expectEqualStrings("gpt-reserve", model.usageRows()[3].label);
}

test "Claude presentation is omitted even when detailed windows are supplied" {
    const session_reset = now + 2 * 3600;
    const weekly_reset = now + 5 * 86400;
    const windows = [_]domain.UsageWindow{
        .{ .kind = .session, .label = "Current session", .used_percent = 44, .reset_at_unix_s = session_reset, .duration_minutes = 300 },
        .{ .kind = .weekly, .label = "Current week", .used_percent = 34, .reset_at_unix_s = weekly_reset, .duration_minutes = 7 * 24 * 60 },
        .{ .kind = .other, .label = "Usage window", .used_percent = 44, .reset_at_unix_s = session_reset },
        .{ .kind = .other, .label = "Usage window", .used_percent = 34, .reset_at_unix_s = weekly_reset },
        .{ .kind = .other, .label = "Usage window", .used_percent = 4, .reset_at_unix_s = weekly_reset + 60 },
        .{ .kind = .other, .label = "spend", .used_percent = 0 },
    };
    const model = try newModel();
    defer testing.allocator.destroy(model);

    var accounts = [_]RecordingService.Account{.{ .fact = claudeFact(), .windows = &windows }};
    var service: RecordingService = .{ .accounts = &accounts };
    model.service = service.port();
    shell.reproject(model);
    try testing.expectEqual(@as(usize, 0), model.view.row_count);
    try testing.expectEqual(@as(usize, 0), model.usageRows().len);
}

test "Claude model-scoped quota is omitted from the Codex-only view" {
    const windows = [_]domain.UsageWindow{.{
        .kind = .model_scoped,
        .label = "Current week",
        .model_label = "opus",
        .used_percent = 19,
        .reset_at_unix_s = now + 4 * 86400,
        .duration_minutes = 7 * 24 * 60,
    }};
    const model = try newModel();
    defer testing.allocator.destroy(model);

    var accounts = [_]RecordingService.Account{.{ .fact = claudeFact(), .windows = &windows }};
    var service: RecordingService = .{ .accounts = &accounts };
    model.service = service.port();
    shell.reproject(model);

    try testing.expectEqual(@as(usize, 0), model.view.row_count);
    try testing.expectEqual(@as(u32, 0), model.view.claude_count);
}

test "Pro rail and expanded panel both keep only the reported weekly window" {
    const model = try newModel();
    defer testing.allocator.destroy(model);

    const windows = [_]domain.UsageWindow{
        sessionWindow(12, now + 3 * 3600),
        weeklyWindow(81, now + 2 * 86400 + 3 * 3600),
    };
    var fact = codexFact();
    fact.plan_label = "Pro";
    var accounts = [_]RecordingService.Account{.{ .fact = fact, .windows = &windows }};
    var service: RecordingService = .{ .accounts = &accounts };
    model.service = service.port();
    model.expanded = 0;

    shell.reproject(model);

    const row = model.view.rowAt(0).?;
    try testing.expectEqual(@as(usize, 2), row.window_count);
    try testing.expectEqual(@as(?usize, 1), row.primary);

    try testing.expectEqualStrings("81% · in 2d 3h", row.summary_text);

    var seen_session = false;
    var seen_weekly = false;
    for (model.usageRows()) |usage| {
        if (std.mem.eql(u8, usage.label, "5-hour")) seen_session = true;
        if (std.mem.eql(u8, usage.label, "Weekly")) seen_weekly = true;
        try testing.expect(std.mem.indexOf(u8, usage.reset_line, "most constraining") == null);
        try testing.expect(std.mem.indexOf(u8, usage.reset_line, "window") == null);
    }
    try testing.expect(!seen_session and seen_weekly);
    try testing.expectEqual(@as(usize, 1), model.usageRows().len);
}

test "an expanded Claude account remains absent from every detail surface" {
    const model = try newModel();
    defer testing.allocator.destroy(model);

    const windows = [_]domain.UsageWindow{
        sessionWindow(12, now + 3 * 3600),
        weeklyWindow(81, now + 2 * 86400),
        .{ .kind = .other, .label = "Extra pool", .used_percent = 5, .reset_at_unix_s = now + 86400 },
    };
    var accounts = [_]RecordingService.Account{.{ .fact = claudeFact(), .windows = &windows }};
    var service: RecordingService = .{ .accounts = &accounts };
    model.service = service.port();
    shell.reproject(model);
    try testing.expectEqual(@as(usize, 0), model.view.row_count);
    try testing.expectEqual(@as(usize, 0), model.usageRows().len);
    try testing.expect(!model.view.inspector.present);
}

test "the expanded Codex account keeps plan windows and hides typed model reserve noise" {
    const model = try newModel();
    defer testing.allocator.destroy(model);

    const windows = [_]domain.UsageWindow{
        .{ .kind = .model_scoped, .label = "GPT-5.3-Codex-Spark", .model_label = "GPT-5.3-Codex-Spark", .used_percent = 0, .reset_at_unix_s = now + 52 * 60, .duration_minutes = 300 },
        weeklyWindow(100, now + 5 * 86400 + 7 * 3600 + 16 * 60),
        .{ .kind = .model_scoped, .label = "GPT-5.3-Codex-Spark", .model_label = "GPT-5.3-Codex-Spark", .used_percent = 0, .reset_at_unix_s = now + 7 * 86400, .duration_minutes = 7 * 24 * 60 },
        .{ .kind = .model_scoped, .label = "gpt-reserve", .model_label = "gpt-reserve", .used_percent = 0, .reset_at_unix_s = now + 7 * 86400, .duration_minutes = 7 * 24 * 60 },
        .{ .kind = .other, .label = "codex", .used_percent = 100, .reset_at_unix_s = now + 5 * 86400 + 7 * 3600 + 16 * 60, .duration_minutes = 7 * 24 * 60 },
    };
    var fact = codexFact();
    fact.plan_label = "Pro";
    var accounts = [_]RecordingService.Account{.{ .fact = fact, .windows = &windows }};
    var service: RecordingService = .{ .accounts = &accounts };
    model.service = service.port();
    model.expanded = 0;
    shell.reproject(model);

    const usage = model.usageRows();
    try testing.expectEqual(@as(usize, 1), usage.len);
    try testing.expectEqualStrings("Weekly", usage[0].label);
    try testing.expectEqualStrings("100%", usage[0].percent_text);
    try testing.expectEqualStrings("resets Jul 30 19:16 KST", usage[0].reset_line);
    try testing.expectEqual(@as(usize, 5), model.view.rowAt(0).?.window_count);
    try testing.expectEqualStrings("Updated Jul 25 11:50 KST · saved snapshot", model.inspectorFreshness());
    try testing.expectEqualStrings("Jul 25 11:50 KST", model.detailEvidence());
    try testing.expectEqualStrings("2 available", model.creditValue());

    const no_weekly = [_]domain.UsageWindow{
        .{ .kind = .model_scoped, .label = "GPT-5.3-Codex-Spark", .model_label = "GPT-5.3-Codex-Spark", .used_percent = 40, .reset_at_unix_s = null },
        .{ .kind = .model_scoped, .label = "gpt-reserve", .model_label = "gpt-reserve", .used_percent = 70, .reset_at_unix_s = null },
    };
    accounts[0].windows = &no_weekly;
    shell.reproject(model);
    try testing.expect(model.view.rowAt(0).?.primary == null);
    try testing.expectEqual(@as(usize, 0), model.usageRows().len);
}

test "provider email is the account identity and no fact is stated twice" {
    const model = try newModel();
    defer testing.allocator.destroy(model);

    var fact = codexFact();
    fact.label = "demo-user@example.invalid";
    fact.provider_email = "demo-user@example.invalid";
    fact.plan_label = "Pro";
    const windows = [_]domain.UsageWindow{weeklyWindow(65, now + 6 * 86400)};
    var accounts = [_]RecordingService.Account{.{ .fact = fact, .windows = &windows }};
    var service: RecordingService = .{ .accounts = &accounts };
    model.service = service.port();
    model.expanded = 0;
    shell.reproject(model);

    const row = model.view.accountRowSlice()[0];
    try testing.expectEqualStrings("demo-user", row.identity_primary);
    try testing.expectEqualStrings("@example.invalid", row.identity_secondary);
    try testing.expect(row.has_identity_secondary and row.has_plan);

    try testing.expectEqualStrings("Pro 20x", row.plan);
    try testing.expectEqualStrings("demo-user@example.invalid", model.inspectorTitle());

    var items: [ui_model.max_tray_items]ui_model.TrayItem = @splat(.{});
    const count = ui_model.buildTray(&model.view, &items);
    var saw_identity = false;
    for (items[0..count]) |item| {
        if (std.mem.startsWith(u8, item.label, "demo-user@example.invalid — 65% · in 6d 0h")) saw_identity = true;
    }
    try testing.expect(saw_identity);
    try testing.expectEqualStrings("Pro", model.view.rowAt(0).?.plan_label);
    try testing.expect(std.mem.startsWith(u8, model.view.rowAt(0).?.tray_usage_text, "65% used · Weekly"));

    accounts[0].fact.label = "Work Codex";
    shell.reproject(model);
    const renamed = model.view.accountRowSlice()[0];
    try testing.expectEqualStrings("Work Codex", renamed.identity_primary);
    try testing.expectEqualStrings(" · demo-user@example.invalid", renamed.identity_secondary);
    try testing.expectEqualStrings("Work Codex", model.inspectorTitle());
}

test "nothing rendered anywhere looks like a credential or a raw provider error" {
    const model = try newModel();
    defer testing.allocator.destroy(model);

    var failed = codexFact();
    failed.account_id = "acct-codex-failed";
    failed.label = "Codex Failed";
    failed.freshness = .refresh_failed;

    failed.last_attempt_code = coordinator.public_code_refresh_failed;
    const windows = [_]domain.UsageWindow{weeklyWindow(81, now + 2 * 86400)};
    var accounts = [_]RecordingService.Account{
        .{ .fact = failed, .windows = &windows },
        .{ .fact = codexFact() },
    };
    var service: RecordingService = .{ .accounts = &accounts };
    model.service = service.port();
    model.expanded = 0;
    shell.reproject(model);

    var items: [ui_model.max_tray_items]ui_model.TrayItem = @splat(.{});
    const count = ui_model.buildTray(&model.view, &items);

    const forbidden = [_][]const u8{
        "access_token", "refresh_token", "Bearer ", "bearer ", "authorization",
        "api_key",      "sk-",           "eyJ",     "cookie",  "password",
    };
    const rendered = model.view.text[0..model.view.text_len];
    const names = model.view.names[0..model.view.names_len];
    for (forbidden) |needle| {
        try testing.expect(std.mem.indexOf(u8, rendered, needle) == null);
        try testing.expect(std.mem.indexOf(u8, names, needle) == null);
        for (items[0..count]) |item| {
            try testing.expect(std.mem.indexOf(u8, item.label, needle) == null);
        }
    }

    try testing.expect(std.mem.indexOf(u8, rendered, coordinator.public_code_refresh_failed) == null);
    try testing.expect(std.mem.indexOf(u8, rendered, "previous saved reading is still visible") != null);
    try testing.expect(coordinator.isPublicCode(coordinator.public_code_refresh_failed));
}

test "local timestamps are exact and the countdown covers a passed reset" {
    var buffer: [ui_model.max_line_bytes]u8 = undefined;

    try testing.expectEqualStrings("2026-Jul-25 12:00 KST", ui_model.formatLocal(&buffer, now, .kst));

    try testing.expectEqualStrings("2026-Jul-26 05:30 KST", ui_model.formatLocal(&buffer, now + 17 * 3600 + 30 * 60, .kst));

    try testing.expectEqualStrings("1970-Jan-01 09:00 KST", ui_model.formatLocal(&buffer, 0, .kst));

    try testing.expectEqualStrings("in 2d 3h", ui_model.formatCountdown(&buffer, 2 * 86400 + 3 * 3600 + 59));
    try testing.expectEqualStrings("in 3h 18m", ui_model.formatCountdown(&buffer, 3 * 3600 + 18 * 60));
    try testing.expectEqualStrings("in 42m", ui_model.formatCountdown(&buffer, 42 * 60));
    try testing.expectEqualStrings("in 30s", ui_model.formatCountdown(&buffer, 30));
    try testing.expectEqualStrings("reset passed — refresh to confirm", ui_model.formatCountdown(&buffer, 0));
    try testing.expectEqualStrings("reset passed — refresh to confirm", ui_model.formatCountdown(&buffer, -1));

    try testing.expectEqualStrings(
        "reset time not reported",
        ui_model.countdownPhrase(&buffer, null, now),
    );
}

test "overview bar captions fit the 190pt window cell" {
    var buffer: [128]u8 = undefined;
    const now_s: i64 = 1_784_000_000;
    try testing.expectEqualStrings("reset passed · refresh", ui_model.resetPhrase(&buffer, now_s - 1, now_s));
    try testing.expectEqualStrings("reset passed · refresh", ui_model.resetPhrase(&buffer, now_s, now_s));
    try testing.expectEqualStrings("reset time not reported", ui_model.resetPhrase(&buffer, null, now_s));
    try testing.expectEqualStrings("resets in 6d 13h", ui_model.resetPhrase(&buffer, now_s + 6 * 86400 + 13 * 3600 + 5, now_s));
    const captions = [_][]const u8{
        ui_model.resetPhrase(&buffer, now_s - 1, now_s),
        "reset time not reported",
        "resets in 99d 23h",
    };
    for (captions) |caption| {
        try testing.expect(std.unicode.utf8CountCodepoints(caption) catch caption.len <= 24);
    }

    try testing.expectEqualStrings("reset passed — refresh to confirm", ui_model.formatCountdown(&buffer, 0));
}

test "a passed reset is reported, not refreshed away" {
    const model = try newModel();
    defer testing.allocator.destroy(model);

    var fact = codexFact();
    fact.freshness = .reset_passed;
    const windows = [_]domain.UsageWindow{weeklyWindow(74, now - 60)};
    var accounts = [_]RecordingService.Account{.{ .fact = fact, .windows = &windows }};
    var service: RecordingService = .{ .accounts = &accounts };
    model.service = service.port();
    model.expanded = 0;

    shell.reproject(model);

    const row = model.view.rowAt(0).?;
    try testing.expectEqualStrings("Reset passed — refresh to confirm", row.freshness_text);
    try testing.expect(std.mem.indexOf(u8, row.summary_text, "reset passed") != null);

    try testing.expectEqual(@as(usize, 0), service.submissions);
}

test "relative age phrases and short local times derive from now without inventing values" {
    var buffer: [ui_model.max_line_bytes]u8 = undefined;
    try testing.expectEqualStrings("just now", ui_model.agoPhrase(&buffer, now, now - 30));
    try testing.expectEqualStrings("2m ago", ui_model.agoPhrase(&buffer, now, now - 2 * 60 - 5));
    try testing.expectEqualStrings("3h ago", ui_model.agoPhrase(&buffer, now, now - 3 * 3600 - 59));
    try testing.expectEqualStrings("2d ago", ui_model.agoPhrase(&buffer, now, now - 2 * 86400 - 3600));

    try testing.expectEqualStrings("just now", ui_model.agoPhrase(&buffer, now, now + 5));

    try testing.expectEqualStrings("09:30", ui_model.shortLocal(&buffer, now, now - 2 * 3600 - 30 * 60, .kst));
    try testing.expectEqualStrings("Jul 24 23:50", ui_model.shortLocal(&buffer, now, now - 12 * 3600 - 10 * 60, .kst));
    try testing.expectEqualStrings("Jul 26 05:30", ui_model.shortLocal(&buffer, now, now + 17 * 3600 + 30 * 60, .kst));

    try testing.expectEqualStrings("Jul 05 12:00", ui_model.shortLocal(&buffer, now, now - 20 * 86400, .kst));

    try testing.expectEqualStrings("Jul 25 12:00 KST", ui_model.mediumLocal(&buffer, now, .kst));
    try testing.expectEqualStrings("Jul 05 09:30 KST", ui_model.mediumLocal(&buffer, now - 20 * 86400 - 2 * 3600 - 30 * 60, .kst));
    try testing.expectEqualStrings("Jan 01 09:00 KST", ui_model.mediumLocal(&buffer, 0, .kst));
}

test "the authoritative count is used and count-only details say so" {
    const model = try newModel();
    defer testing.allocator.destroy(model);

    var count_only = codexFact();
    count_only.reset_credit_count = 3;
    count_only.credit_detail_status = .count_only;
    count_only.credit_detail_count = 0;

    var capped = codexFact();
    capped.account_id = "acct-codex-work";
    capped.label = "Codex Work";
    capped.reset_credit_count = 4;
    capped.credit_detail_status = .detailed;
    capped.credit_detail_count = 1;

    var detailed = codexFact();
    detailed.account_id = "acct-codex-third";
    detailed.label = "Codex Third";
    detailed.reset_credit_count = 2;
    detailed.credit_detail_status = .detailed;
    detailed.credit_detail_count = 2;

    var none = codexFact();
    none.account_id = "acct-codex-none";
    none.label = "Codex None";
    none.reset_credit_count = null;
    none.credit_detail_status = null;

    var accounts = [_]RecordingService.Account{
        .{ .fact = count_only },
        .{ .fact = capped },
        .{ .fact = detailed },
        .{ .fact = none },
    };
    var service: RecordingService = .{ .accounts = &accounts };
    model.service = service.port();

    model.expanded = 0;
    shell.reproject(model);
    try testing.expect(model.inspectorHasCredits());
    try testing.expectEqualStrings("3 available", model.creditValue());
    try testing.expect(model.creditHasNote());
    try testing.expectEqualStrings("Count reported without matching detail rows", model.creditNote());
    try testing.expect(model.creditOffersUse());

    model.expanded = 1;
    shell.reproject(model);
    try testing.expectEqualStrings("4 available", model.creditValue());
    try testing.expect(model.creditHasNote());

    model.expanded = 2;
    shell.reproject(model);
    try testing.expectEqualStrings("2 available", model.creditValue());
    try testing.expect(!model.creditHasNote());

    model.expanded = 3;
    shell.reproject(model);
    try testing.expectEqualStrings("Not reported", model.creditValue());
    try testing.expect(!model.creditOffersUse());
    try testing.expect(!model.creditOffersReview());
}

test "the reset confirmation needs two explicit steps before any command" {
    const model = try newModel();
    defer testing.allocator.destroy(model);

    const windows = [_]domain.UsageWindow{weeklyWindow(87, now + 5 * 86400)};
    var accounts = [_]RecordingService.Account{.{ .fact = codexFact(), .windows = &windows }};
    var service: RecordingService = .{ .accounts = &accounts, .capabilities = .{
        .connected = true,
        .reset = true,
    } };
    model.service = service.port();
    shell.reproject(model);

    var fx: shell.Effects = .{};

    shell.update(model, .{ .begin_reset = 0 }, &fx);
    try testing.expectEqual(ui_model.ResetStage.review, model.reset.stage);
    try testing.expectEqualStrings("Codex Personal", model.resetAccountLabel());
    try testing.expectEqual(@as(u32, 2), model.resetAvailableCount());
    try testing.expectEqualStrings("87% used · Weekly", model.resetUsageText());

    try testing.expectEqualStrings("2026-Jul-30 12:00 KST (in 5d 0h)", model.resetResetText());
    shell.update(model, .confirm_reset, &fx);
    try testing.expectEqual(@as(usize, 0), service.submissions);
    try testing.expectEqual(ui_model.ResetStage.review, model.reset.stage);

    shell.update(model, .acknowledge_reset, &fx);
    try testing.expectEqual(ui_model.ResetStage.armed, model.reset.stage);
    shell.update(model, .confirm_reset, &fx);
    try testing.expectEqual(@as(usize, 1), service.submissions);
    try testing.expectEqual(ui_model.ResetStage.dispatched, model.reset.stage);
    switch (service.last.?) {
        .redeem_reset => |request| {
            try testing.expectEqualStrings("acct-codex-personal", request.account_id);
            try testing.expectEqual(@as(u32, 2), request.expected_available_count);
            try testing.expectEqual(ui_model.Surface.details, request.surface);
        },
        else => return error.WrongCommand,
    }

    shell.update(model, .cancel_reset, &fx);
    try testing.expectEqual(ui_model.ResetStage.idle, model.reset.stage);
    try testing.expect(!model.resetIsOpen());
}

test "unchecking the acknowledgement disarms the reset again" {
    const model = try newModel();
    defer testing.allocator.destroy(model);

    const windows = [_]domain.UsageWindow{weeklyWindow(87, now + 5 * 86400)};
    var accounts = [_]RecordingService.Account{.{ .fact = codexFact(), .windows = &windows }};
    var service: RecordingService = .{ .accounts = &accounts, .capabilities = .{ .connected = true, .reset = true } };
    model.service = service.port();
    shell.reproject(model);

    var fx: shell.Effects = .{};

    shell.update(model, .{ .begin_reset = 0 }, &fx);
    try testing.expect(model.resetIsReview() and !model.resetIsArmed());
    shell.update(model, .acknowledge_reset, &fx);
    try testing.expect(model.resetIsArmed());
    shell.update(model, .acknowledge_reset, &fx);
    try testing.expect(model.resetIsReview() and !model.resetIsArmed());
    shell.update(model, .confirm_reset, &fx);
    try testing.expectEqual(@as(usize, 0), service.submissions);
    shell.update(model, .acknowledge_reset, &fx);
    shell.update(model, .confirm_reset, &fx);
    try testing.expectEqual(@as(usize, 1), service.submissions);
    try testing.expectEqual(ui_model.ResetStage.dispatched, model.reset.stage);

    shell.update(model, .acknowledge_reset, &fx);
    try testing.expectEqual(ui_model.ResetStage.dispatched, model.reset.stage);
}

test "the reset confirmation fails closed and never claims success" {
    const model = try newModel();
    defer testing.allocator.destroy(model);

    var no_credit = codexFact();
    no_credit.reset_credit_count = 0;
    var pending = codexFact();
    pending.account_id = "acct-codex-pending";
    pending.label = "Codex Pending";
    pending.pending_reset_attempt = true;
    var accounts = [_]RecordingService.Account{
        .{ .fact = no_credit },
        .{ .fact = pending },
    };
    var service: RecordingService = .{
        .accounts = &accounts,
        .outcome = .offer_unavailable,
    };
    model.service = service.port();
    shell.reproject(model);

    var fx: shell.Effects = .{};

    shell.update(model, .{ .begin_reset = 0 }, &fx);
    try testing.expectEqual(ui_model.ResetStage.blocked, model.reset.stage);
    try testing.expectEqual(ui_model.ResetBlockReason.no_credit, model.reset.reason);
    shell.update(model, .acknowledge_reset, &fx);
    shell.update(model, .confirm_reset, &fx);
    try testing.expectEqual(@as(usize, 0), service.submissions);

    shell.update(model, .{ .begin_reset = 1 }, &fx);
    try testing.expectEqual(ui_model.ResetBlockReason.pending_attempt, model.reset.reason);
    try testing.expectEqual(@as(usize, 0), service.submissions);
}

test "an unsent reset attempt is retryable from the row and does not block the account" {
    const model = try newModel();
    defer testing.allocator.destroy(model);

    var unsent = codexFact();
    unsent.unsent_reset_attempt = true;
    var accounts = [_]RecordingService.Account{.{ .fact = unsent }};
    var service: RecordingService = .{ .accounts = &accounts, .outcome = .accepted_pending };
    model.service = service.port();
    shell.reproject(model);

    var fx: shell.Effects = .{};

    const row = model.view.accountRowSlice()[0];
    try testing.expect(row.can_reset);
    try testing.expectEqualStrings("Retry reset attempt…", row.reset_label);
    try testing.expect(!model.view.rowAt(0).?.pending_reset_attempt);

    shell.update(model, .{ .begin_reset = 0 }, &fx);
    try testing.expectEqual(ui_model.ResetStage.blocked, model.reset.stage);
    try testing.expectEqual(ui_model.ResetBlockReason.unsent_attempt, model.reset.reason);
    try testing.expect(std.mem.indexOf(u8, model.reset.blockedText(), "was not sent") != null);
    try testing.expectEqual(@as(usize, 0), service.submissions);
    shell.update(model, .retry_reset, &fx);
    try testing.expectEqual(@as(usize, 1), service.submissions);
    try testing.expectEqual(std.meta.Tag(ui_model.Command).retry_reset, service.tags[0]);
    try testing.expectEqualStrings("acct-codex-personal", service.last.?.retry_reset);
}

test "an unavailable reset offer reports nothing was sent" {
    const model = try newModel();
    defer testing.allocator.destroy(model);

    var accounts = [_]RecordingService.Account{.{ .fact = codexFact() }};
    var service: RecordingService = .{ .accounts = &accounts, .outcome = .offer_unavailable };
    model.service = service.port();
    shell.reproject(model);

    var fx: shell.Effects = .{};

    shell.update(model, .{ .begin_reset = 0 }, &fx);
    shell.update(model, .acknowledge_reset, &fx);
    shell.update(model, .confirm_reset, &fx);

    try testing.expectEqual(ui_model.CommandOutcome.offer_unavailable, model.reset.outcome);
    try testing.expect(std.mem.indexOf(u8, model.resetOutcomeText(), "Nothing was sent") != null);
    try testing.expect(model.noticeIsBlocked());
    try testing.expect(std.mem.indexOf(u8, model.noticeText(), "Nothing was sent") != null);
}

test "a dispatched reset reports settlement once the row's attempt clears" {
    const model = try newModel();
    defer testing.allocator.destroy(model);

    var accounts = [_]RecordingService.Account{.{ .fact = codexFact() }};
    var service: RecordingService = .{ .accounts = &accounts, .outcome = .accepted_pending };
    model.service = service.port();
    shell.reproject(model);

    var fx: shell.Effects = .{};

    shell.update(model, .{ .begin_reset = 0 }, &fx);
    shell.update(model, .acknowledge_reset, &fx);
    shell.update(model, .confirm_reset, &fx);
    try testing.expect(model.resetIsDispatched());
    try testing.expect(std.mem.indexOf(u8, model.resetOutcomeText(), "accepted and is pending") != null);

    shell.reproject(model);
    try testing.expect(std.mem.indexOf(u8, model.resetOutcomeText(), "accepted and is pending") != null);

    accounts[0].fact.pending_reset_attempt = true;
    shell.reproject(model);
    try testing.expect(std.mem.indexOf(u8, model.resetOutcomeText(), "accepted and is pending") != null);

    accounts[0].fact.pending_reset_attempt = false;
    shell.reproject(model);
    try testing.expect(model.resetIsDispatched());
    try testing.expect(std.mem.indexOf(u8, model.resetOutcomeText(), "settled") != null);
    try testing.expect(std.mem.indexOf(u8, model.resetOutcomeText(), "pending") == null);

    shell.update(model, .cancel_reset, &fx);
    try testing.expect(!model.resetIsOpen());
}

test "a settled reset dialog reports whether the proxy cooldown was cleared" {
    const model = try newModel();
    defer testing.allocator.destroy(model);

    var accounts = [_]RecordingService.Account{.{ .fact = codexFact() }};
    var service: RecordingService = .{ .accounts = &accounts, .outcome = .accepted_pending };
    model.service = service.port();
    shell.reproject(model);

    var fx: shell.Effects = .{};

    shell.update(model, .{ .begin_reset = 0 }, &fx);
    shell.update(model, .acknowledge_reset, &fx);
    shell.update(model, .confirm_reset, &fx);

    accounts[0].fact.pending_reset_attempt = true;
    shell.reproject(model);
    try testing.expect(!model.resetShowsProxyClear());

    accounts[0].fact.pending_reset_attempt = false;
    accounts[0].fact.reset_proxy_clear = .pending;
    shell.reproject(model);
    try testing.expect(std.mem.indexOf(u8, model.resetOutcomeText(), "settled") != null);
    try testing.expect(model.resetShowsProxyClear());
    try testing.expect(std.mem.indexOf(u8, model.resetProxyClearText(), "Failover: clearing cooldown") != null);

    accounts[0].fact.reset_proxy_clear = .cleared;
    shell.reproject(model);
    try testing.expectEqualStrings("Failover: cooldown cleared.", model.resetProxyClearText());

    accounts[0].fact.reset_proxy_clear = .@"unreachable";
    shell.reproject(model);
    try testing.expect(std.mem.indexOf(u8, model.resetProxyClearText(), "Failover: cooldown not cleared") != null);
    try testing.expect(std.mem.indexOf(u8, model.resetProxyClearText(), "not reachable") != null);
    try testing.expect(std.mem.indexOf(u8, model.resetProxyClearText(), "Clear cooldown") != null);

    accounts[0].fact.reset_proxy_clear = .not_mapped;
    shell.reproject(model);
    try testing.expect(std.mem.indexOf(u8, model.resetProxyClearText(), "not mapped") != null);

    const untouched = try newModel();
    defer testing.allocator.destroy(untouched);
    var untouched_accounts = [_]RecordingService.Account{.{ .fact = codexFact() }};
    var unavailable_service: RecordingService = .{
        .accounts = &untouched_accounts,
        .outcome = .offer_unavailable,
    };
    untouched.service = unavailable_service.port();
    shell.reproject(untouched);
    var untouched_fx: shell.Effects = .{};
    shell.update(untouched, .{ .begin_reset = 0 }, &untouched_fx);
    shell.update(untouched, .acknowledge_reset, &untouched_fx);
    shell.update(untouched, .confirm_reset, &untouched_fx);
    try testing.expect(!untouched.resetShowsProxyClear());
    try testing.expectEqualStrings("", untouched.resetProxyClearText());
    try testing.expectEqual(@as(usize, 1), unavailable_service.submissions);

    try testing.expectEqual(@as(usize, 1), service.submissions);
}

test "a dispatched reset reports an attempt that was not sent after all" {
    const model = try newModel();
    defer testing.allocator.destroy(model);

    var accounts = [_]RecordingService.Account{.{ .fact = codexFact() }};
    var service: RecordingService = .{ .accounts = &accounts, .outcome = .accepted_pending };
    model.service = service.port();
    shell.reproject(model);

    var fx: shell.Effects = .{};

    shell.update(model, .{ .begin_reset = 0 }, &fx);
    shell.update(model, .acknowledge_reset, &fx);
    shell.update(model, .confirm_reset, &fx);

    accounts[0].fact.operation_in_flight = true;
    shell.reproject(model);
    try testing.expect(std.mem.indexOf(u8, model.resetOutcomeText(), "accepted and is pending") != null);
    accounts[0].fact.operation_in_flight = false;
    accounts[0].fact.unsent_reset_attempt = true;
    shell.reproject(model);
    try testing.expect(std.mem.indexOf(u8, model.resetOutcomeText(), "not sent") != null);
    try testing.expect(std.mem.indexOf(u8, model.resetOutcomeText(), "settled") == null);
}

test "stored plan labels from earlier builds display as the current wording" {
    const ui_format = @import("../ui_format.zig");
    try std.testing.expectEqualStrings("Pro 20x", ui_format.displayPlanLabel("x20"));
    try std.testing.expectEqualStrings("Pro 20x", ui_format.displayPlanLabel("Pro"));
    try std.testing.expectEqualStrings("Pro 5x", ui_format.displayPlanLabel("x5"));
    try std.testing.expectEqualStrings("Pro 5x", ui_format.displayPlanLabel("Pro Lite"));
    try std.testing.expectEqualStrings("Pro 20x", ui_format.displayPlanLabel("Pro 20x"));
    try std.testing.expectEqualStrings("Plus", ui_format.displayPlanLabel("Plus"));
    try std.testing.expectEqualStrings("Team", ui_format.displayPlanLabel("Team"));
}
