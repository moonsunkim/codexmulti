const std = @import("std");
const bridge = @import("../bridge_json.zig");
const shell = @import("../shell_model.zig");
const domain = @import("../domain.zig");
const runtime_paths = @import("../runtime_paths.zig");
const ui_model = @import("../ui_model.zig");
const support = @import("ui_projection_test_support.zig");

const testing = std.testing;
const now = support.now;
const RecordingService = support.RecordingService;
const weeklyWindow = support.weeklyWindow;
const sessionWindow = support.sessionWindow;
const claudeFact = support.claudeFact;
const codexFact = support.codexFact;
const newModel = support.newModel;

fn projectedView(model: *const shell.Model, items: []const ui_model.TrayItem) bridge.ViewWire {
    return bridge.viewToWire(&model.view, &.{}, items, "");
}

test "CodexMulti display rename preserves every live continuity namespace" {
    try testing.expectEqualStrings("dev.codexmulti.app", runtime_paths.app_bundle_id);
    try testing.expectEqualStrings("CodexMulti", runtime_paths.app_data_directory_name);
}

test "tray projection retains only the failover switch command namespace" {
    try testing.expectEqualStrings("tray.switch_failover:", ui_model.tray_command_switch_failover_prefix);
}

test "status item is icon-only and the bridge projects its exact help text" {
    const model = try newModel();
    defer testing.allocator.destroy(model);
    shell.reproject(model);

    var items: [ui_model.max_tray_items]ui_model.TrayItem = @splat(.{});
    const count = ui_model.buildTray(&model.view, &items);
    const wire = projectedView(model, items[0..count]);
    try testing.expectEqualStrings("", wire.tray.title);
    try testing.expectEqualStrings("CodexMulti — saved usage and CLI accounts", wire.tray.help_text);
}

test "the tray stays inside the 32-item bound and always keeps its actions" {
    const model = try newModel();
    defer testing.allocator.destroy(model);

    var storage: [ui_model.max_rows]RecordingService.Account = undefined;
    var labels: [ui_model.max_rows][12]u8 = undefined;
    for (&storage, 0..) |*entry, index| {
        var fact = codexFact();
        const label = std.fmt.bufPrint(&labels[index], "Account {d}", .{index}) catch "Account";
        fact.label = label;
        entry.* = .{ .fact = fact };
    }
    var service: RecordingService = .{ .accounts = &storage };
    model.service = service.port();
    shell.reproject(model);
    try testing.expectEqual(ui_model.max_rows, model.view.row_count);

    var items: [ui_model.max_tray_items]ui_model.TrayItem = @splat(.{});
    const count = ui_model.buildTray(&model.view, &items);
    try testing.expect(count <= ui_model.max_tray_items);
    try testing.expectEqualStrings("Accounts…", items[0].label);
    try testing.expectEqualStrings("tray.open_accounts", items[0].command);
    try testing.expectEqualStrings("Refresh All Accounts", items[1].label);
    try testing.expectEqualStrings(ui_model.tray_command_refresh_all, items[1].command);
    try testing.expectEqualStrings("Settings…", items[count - 2].label);
    try testing.expectEqualStrings("Quit", items[count - 1].label);
    try testing.expect(items[count - 3].separator);
    try testing.expect(items[1].enabled);

    var account_rows: usize = 0;
    for (items[0..count]) |item| {
        if (item.separator) continue;
        if (std.mem.startsWith(u8, item.command, ui_model.tray_command_open_account_prefix)) {
            try testing.expect(item.enabled);
            try testing.expect(std.mem.indexOf(u8, item.label, "\u{2063}") == null);
            account_rows += 1;
        }
    }
    try testing.expect(account_rows > 0);
    for (items[0..count]) |item| {
        try testing.expect(std.mem.indexOf(u8, item.command, "reset") == null);
        try testing.expect(std.mem.indexOf(u8, item.label, "Use one reset") == null);
    }
}

test "the tray gives every Codex account one complete provider-grouped native row" {
    const model = try newModel();
    defer testing.allocator.destroy(model);

    const claude_windows = [_]domain.UsageWindow{weeklyWindow(34, now + 3 * 86400)};
    const codex_windows = [_]domain.UsageWindow{sessionWindow(81, now + 2 * 3600)};
    var accounts = [_]RecordingService.Account{
        .{ .fact = claudeFact(), .windows = &claude_windows },
        .{ .fact = codexFact(), .windows = &codex_windows },
    };
    var service: RecordingService = .{ .accounts = &accounts };
    model.service = service.port();
    shell.reproject(model);

    var items: [ui_model.max_tray_items]ui_model.TrayItem = @splat(.{});
    const count = ui_model.buildTray(&model.view, &items);
    try testing.expectEqual(@as(usize, 8), count);
    try testing.expectEqualStrings("Refresh All Accounts", items[1].label);
    try testing.expect(items[2].separator);
    try testing.expectEqualStrings("CODEX ACCOUNTS", items[3].label);
    try testing.expectEqualStrings("Codex Personal — 81% · in 2h 0m", items[4].label);
    try testing.expect(std.mem.startsWith(u8, items[4].command, ui_model.tray_command_open_account_prefix));
    try testing.expect(items[4].enabled);
    try testing.expect(items[5].separator);
    try testing.expectEqualStrings("Settings…", items[6].label);
    try testing.expectEqualStrings("Quit", items[7].label);

    for (items[0..count]) |item| {
        try testing.expect(std.mem.indexOf(u8, item.command, "switch") == null);
        try testing.expect(std.mem.indexOf(u8, item.command, "reset") == null);
        try testing.expect(std.mem.indexOf(u8, item.label, "Reset credits") == null);
    }
    try testing.expectEqual(@as(usize, 0), service.submissions);
}

test "the bridge projects the native tray submenu labels" {
    const model = try newModel();
    defer testing.allocator.destroy(model);
    shell.reproject(model);

    var items: [ui_model.max_tray_items]ui_model.TrayItem = @splat(.{});
    const count = ui_model.buildTray(&model.view, &items);
    const view_wire = projectedView(model, items[0..count]);
    const shell_wire = bridge.shellToWire(model);
    try testing.expectEqualStrings("Refresh Usage", view_wire.tray.refresh_usage_label);
    try testing.expectEqualStrings("Show Account…", view_wire.tray.open_in_settings_label);
    try testing.expectEqualStrings("Quit", shell_wire.quit_label);
}

test "bridge tray account commands resolve directly to projected account ids" {
    const model = try newModel();
    defer testing.allocator.destroy(model);

    var accounts = [_]RecordingService.Account{
        .{ .fact = claudeFact() },
        .{ .fact = codexFact() },
    };
    var service: RecordingService = .{ .accounts = &accounts };
    model.service = service.port();
    shell.reproject(model);

    var items: [ui_model.max_tray_items]ui_model.TrayItem = @splat(.{});
    const count = ui_model.buildTray(&model.view, &items);
    var resolved: usize = 0;
    for (items[0..count]) |item| {
        const command_account = if (std.mem.startsWith(u8, item.command, ui_model.tray_command_open_account_prefix))
            item.command[ui_model.tray_command_open_account_prefix.len..]
        else
            continue;
        const index = model.view.indexOfAccount(command_account).?;
        try testing.expectEqualStrings(command_account, model.view.rowAt(index).?.account_id);
        try testing.expect(std.mem.indexOf(u8, item.label, "\u{2063}") == null);
        resolved += 1;
    }
    try testing.expectEqual(@as(usize, 1), resolved);
    try testing.expect(model.view.indexOfAccount("") == null);
    try testing.expect(model.view.indexOfAccount("missing-account") == null);
}

test "the tray disables refresh all when no enabled account exists" {
    const model = try newModel();
    defer testing.allocator.destroy(model);

    var items: [ui_model.max_tray_items]ui_model.TrayItem = @splat(.{});
    var count = ui_model.buildTray(&model.view, &items);
    try testing.expect(!items[1].enabled);

    var accounts = [_]RecordingService.Account{.{ .fact = claudeFact() }};
    accounts[0].fact.enabled = false;
    var service: RecordingService = .{ .accounts = &accounts };
    model.service = service.port();
    shell.reproject(model);

    count = ui_model.buildTray(&model.view, &items);
    try testing.expect(!items[1].enabled);
}

test "a tray that cannot hold every account truncates deterministically" {
    const model = try newModel();
    defer testing.allocator.destroy(model);

    var storage: [ui_model.max_rows]RecordingService.Account = undefined;
    var labels: [ui_model.max_rows][12]u8 = undefined;
    for (&storage, 0..) |*entry, index| {
        var fact = codexFact();
        const label = std.fmt.bufPrint(&labels[index], "Account {d}", .{index}) catch "Account";
        fact.label = label;
        entry.* = .{ .fact = fact };
    }
    var service: RecordingService = .{ .accounts = &storage };
    model.service = service.port();
    shell.reproject(model);

    var items: [ui_model.max_tray_items]ui_model.TrayItem = @splat(.{});
    const budget = 12;
    const count = ui_model.buildTray(&model.view, items[0..budget]);
    try testing.expect(count <= budget);
    try testing.expectEqualStrings("Quit", items[count - 1].label);

    var summary_rows: usize = 0;
    for (items[0..count]) |item| {
        if (std.mem.indexOf(u8, item.label, "More Accounts") != null) summary_rows += 1;
    }
    try testing.expectEqual(@as(usize, 1), summary_rows);

    var repeat: [ui_model.max_tray_items]ui_model.TrayItem = @splat(.{});
    const repeat_count = ui_model.buildTray(&model.view, repeat[0..budget]);
    try testing.expectEqual(count, repeat_count);
    for (items[0..count], repeat[0..repeat_count]) |left, right| {
        try testing.expectEqualStrings(left.label, right.label);
        try testing.expectEqualStrings(left.command, right.command);
    }

    var tiny: [ui_model.max_tray_items]ui_model.TrayItem = @splat(.{});
    const tiny_count = ui_model.buildTray(&model.view, tiny[0..3]);
    try testing.expectEqual(@as(usize, 3), tiny_count);
    try testing.expectEqualStrings(ui_model.tray_command_quit, tiny[2].command);
}

test "the status-item title is always empty regardless of attention" {
    const model = try newModel();
    defer testing.allocator.destroy(model);
    var buffer: [ui_model.max_title_bytes]u8 = undefined;

    shell.reproject(model);
    try testing.expectEqualStrings("", ui_model.trayTitle(&model.view, &buffer));

    var stale = claudeFact();
    stale.freshness = .saved_snapshot;
    var fresh = codexFact();
    fresh.freshness = .as_of;
    var accounts = [_]RecordingService.Account{ .{ .fact = stale }, .{ .fact = fresh } };
    var service: RecordingService = .{ .accounts = &accounts };
    model.service = service.port();
    shell.reproject(model);
    try testing.expectEqualStrings("", ui_model.trayTitle(&model.view, &buffer));

    accounts[0].fact.freshness = .reauth_required;
    shell.reproject(model);
    try testing.expectEqualStrings("", ui_model.trayTitle(&model.view, &buffer));

    accounts[0].fact.freshness = .refresh_failed;
    shell.reproject(model);
    try testing.expectEqualStrings("", ui_model.trayTitle(&model.view, &buffer));

    accounts[0].fact.freshness = .as_of;
    shell.reproject(model);
    const title = ui_model.trayTitle(&model.view, &buffer);
    try testing.expectEqualStrings("", title);
    try testing.expect(std.mem.indexOf(u8, title, "%") == null);
    try testing.expect(title.len <= ui_model.max_title_bytes);
}

test "the tray dropdown is rebuilt from the model on every state change" {
    const model = try newModel();
    defer testing.allocator.destroy(model);

    const windows = [_]domain.UsageWindow{weeklyWindow(34, now + 3 * 86400)};
    var accounts = [_]RecordingService.Account{.{ .fact = codexFact(), .windows = &windows }};
    var service: RecordingService = .{ .accounts = &accounts };
    model.service = service.port();
    shell.reproject(model);

    var first_items: [ui_model.max_tray_items]ui_model.TrayItem = @splat(.{});
    const first_count = ui_model.buildTray(&model.view, &first_items);
    const first = projectedView(model, first_items[0..first_count]).tray;
    try testing.expect(first.items.len >= ui_model.tray_fixed_items);
    var found_row = false;
    for (first.items) |item| {
        if (std.mem.indexOf(u8, item.label, "Codex Personal — 34% · in 3d 0h") != null) found_row = true;
    }
    try testing.expect(found_row);

    model.now_unix_s = now + 86400;
    shell.reproject(model);
    var second_items: [ui_model.max_tray_items]ui_model.TrayItem = @splat(.{});
    const second_count = ui_model.buildTray(&model.view, &second_items);
    const second = projectedView(model, second_items[0..second_count]).tray;
    var found_moved = false;
    for (second.items) |item| {
        if (std.mem.indexOf(u8, item.label, "in 2d 0h") != null) found_moved = true;
    }
    try testing.expect(found_moved);
    try testing.expectEqual(@as(usize, 0), service.submissions);
}

test "per-account tray refresh submits only the existing typed refresh command" {
    const model = try newModel();
    defer testing.allocator.destroy(model);

    const windows = [_]domain.UsageWindow{weeklyWindow(34, now + 3 * 86400)};
    var accounts = [_]RecordingService.Account{.{ .fact = codexFact(), .windows = &windows }};
    var service: RecordingService = .{ .accounts = &accounts, .capabilities = .{ .connected = true, .refresh = true } };
    model.service = service.port();
    shell.reproject(model);
    try testing.expectEqual(@as(usize, 0), service.submissions);
    try testing.expect(model.view.rowAt(0).?.canRefreshFromTray(model.view.capabilities));

    var effects: shell.Effects = .{};
    shell.update(model, .{ .refresh_account = 0 }, &effects);

    try testing.expectEqual(@as(usize, 1), service.submissions);
    try testing.expectEqualStrings("acct-codex-personal", service.last.?.refresh_account);
}
