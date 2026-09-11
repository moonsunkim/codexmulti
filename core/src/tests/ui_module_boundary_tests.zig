const std = @import("std");
const testing = std.testing;

const contracts = @import("../ui_contracts.zig");
const projection = @import("../ui_projection.zig");
const format = @import("../ui_format.zig");
const reset = @import("../ui_reset.zig");
const ui_model = @import("../ui_model.zig");

const band_now: i64 = 1_784_948_400;

fn renderBand(
    view: *projection.ViewState,
    accounts: []const contracts.ProxyAccountFact,
    in_flight: u32,
) !void {
    view.begin(band_now, .{ .connected = true, .proxy_control = true }, .kst);
    _ = try view.pushAccount(.{
        .account_id = "freshness-only",
        .label = "Freshness only",
        .provider = .codex,
        .auth_state = .connected,
        .freshness = .saved_snapshot,
        .has_snapshot = true,
        .last_success_at_unix_s = band_now - 600,
    });
    view.applyProxy(.{
        .base_url = "http://127.0.0.1:8787",
        .cli_path = "/tmp/proxy",
        .config_path = "/tmp/proxy.json",
        .reachability = .reachable,
        .config_path_matches = true,
        .in_flight = in_flight,
        .accounts = accounts,
    });
    view.applyProxyService(.{
        .state = .running,
        .routing_state = .on,
        .enabled = true,
    });
    view.finish(.{});
}

fn renderAccountFreshness(view: *projection.ViewState) !void {
    view.begin(band_now, .{ .connected = true, .proxy_control = true }, .kst);
    _ = try view.pushAccount(.{
        .account_id = "freshness-only",
        .label = "Freshness only",
        .provider = .codex,
        .auth_state = .connected,
        .freshness = .saved_snapshot,
        .has_snapshot = true,
        .last_success_at_unix_s = band_now - 600,
    });
}

test "ui facade preserves extracted contract and projection types" {
    var view: projection.ViewState = .{};
    const facade_view: *ui_model.ViewState = &view;
    facade_view.begin(0, .{}, .kst);

    const direct_command: contracts.Command = .refresh_all;
    const facade_command: ui_model.Command = direct_command;
    try testing.expectEqual(
        std.meta.Tag(ui_model.Command).refresh_all,
        std.meta.activeTag(facade_command),
    );
}

test "ui facade preserves extracted formatting results" {
    var direct_buffer: [contracts.max_line_bytes]u8 = undefined;
    var facade_buffer: [ui_model.max_line_bytes]u8 = undefined;

    try testing.expectEqualStrings(
        format.formatCountdown(&direct_buffer, 3 * 3600 + 18 * 60),
        ui_model.formatCountdown(&facade_buffer, 3 * 3600 + 18 * 60),
    );
}

test "ui facade preserves extracted reset and notice presenters" {
    var notice: reset.Notice = .{};
    const facade_notice: *ui_model.Notice = &notice;
    facade_notice.setOutcome("Refresh", "Codex A", .accepted_pending);

    try testing.expectEqual(ui_model.NoticeKind.pending, facade_notice.kind);
    try testing.expectEqualStrings("Refresh in progress · Codex A", facade_notice.text());
}

test "band status counts every mapped account that can serve including active" {
    const accounts = [_]contracts.ProxyAccountFact{
        .{ .proxy_name = "active", .label = "private-active@example.com", .state = .ready, .active = true, .mapped = true },
        .{ .proxy_name = "ready", .label = "private-ready@example.com", .state = .ready, .mapped = true },
        .{ .proxy_name = "cooling", .label = "private-cooling@example.com", .state = .cooldown, .mapped = true },
        .{ .proxy_name = "paused", .label = "private-paused@example.com", .state = .paused, .mapped = true },
        .{ .proxy_name = "invalid", .label = "private-invalid@example.com", .state = .invalid, .mapped = true },
        .{ .proxy_name = "refreshing", .label = "private-refreshing@example.com", .state = .refreshing, .mapped = true },
        .{ .proxy_name = "unknown", .label = "private-unknown@example.com", .state = .unknown, .mapped = true },
        .{ .proxy_name = "unmapped", .label = "private-unmapped@example.com", .state = .ready },
    };
    var view: projection.ViewState = .{};
    try renderBand(&view, &accounts, 0);

    try testing.expectEqualStrings("2 ready · 10m ago", view.toolbar_status_text);
    try testing.expect(std.mem.indexOf(u8, view.toolbar_status_text, "private") == null);
}

test "band status replaces freshness with the authoritative in-flight total" {
    const accounts = [_]contracts.ProxyAccountFact{.{
        .proxy_name = "active",
        .label = "private-active@example.com",
        .state = .ready,
        .in_flight = 7,
        .active = true,
        .mapped = true,
    }};
    var view: projection.ViewState = .{};
    try renderBand(&view, &accounts, 7);

    try testing.expectEqualStrings("1 ready · 7 in flight", view.toolbar_status_text);
}

test "band status says No accounts before proxy lifecycle state" {
    var view: projection.ViewState = .{};
    view.begin(band_now, .{ .connected = true, .proxy_control = true }, .kst);
    view.applyProxyService(.{
        .state = .@"unreachable",
        .routing_state = .on,
        .enabled = false,
    });
    view.finish(.{});

    try testing.expectEqualStrings("No accounts", view.toolbar_status_text);
}

test "band status says Proxy off when the service is absent or routing is off" {
    var not_installed: projection.ViewState = .{};
    try renderAccountFreshness(&not_installed);
    not_installed.applyProxyService(.{
        .state = .not_installed,
        .routing_state = .on,
        .enabled = false,
    });
    not_installed.finish(.{});
    try testing.expectEqualStrings("Proxy off · 10m ago", not_installed.toolbar_status_text);

    var routing_off: projection.ViewState = .{};
    try renderAccountFreshness(&routing_off);
    routing_off.applyProxyService(.{
        .state = .running,
        .routing_state = .off,
        .enabled = false,
    });
    routing_off.finish(.{});
    try testing.expectEqualStrings("Proxy off · 10m ago", routing_off.toolbar_status_text);
}

test "band status says Proxy unreachable when the installed routed service has not answered" {
    var view: projection.ViewState = .{};
    try renderAccountFreshness(&view);
    view.applyProxyService(.{
        .state = .@"unreachable",
        .routing_state = .on,
        .enabled = false,
    });
    view.finish(.{});

    try testing.expectEqualStrings("Proxy unreachable · 10m ago", view.toolbar_status_text);
}

test "band status with none ready reports the soonest known cooldown reset" {
    const accounts = [_]contracts.ProxyAccountFact{
        .{ .proxy_name = "later", .label = "private-later@example.com", .state = .cooldown, .cooldown_until_unix_s = band_now + 7200, .mapped = true },
        .{ .proxy_name = "sooner", .label = "private-sooner@example.com", .state = .cooldown, .cooldown_until_unix_s = band_now + 1800, .mapped = true },
        .{ .proxy_name = "paused", .label = "private-paused@example.com", .state = .paused, .mapped = true },
        .{ .proxy_name = "invalid", .label = "private-invalid@example.com", .state = .invalid, .mapped = true },
        .{ .proxy_name = "unmapped", .label = "private-unmapped@example.com", .state = .ready },
    };
    var view: projection.ViewState = .{};
    try renderBand(&view, &accounts, 0);

    try testing.expectEqualStrings("no cursor · None ready · next reset in 30m", view.toolbar_status_text);
}

test "band status keeps the no-cursor prefix when ready accounts have no active cursor" {
    const accounts = [_]contracts.ProxyAccountFact{.{
        .proxy_name = "ready",
        .label = "private-ready@example.com",
        .state = .ready,
        .mapped = true,
    }};
    var view: projection.ViewState = .{};
    try renderBand(&view, &accounts, 0);

    try testing.expectEqualStrings("no cursor · 1 ready · 10m ago", view.toolbar_status_text);
}
