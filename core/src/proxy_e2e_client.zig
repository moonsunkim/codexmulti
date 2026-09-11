const std = @import("std");
const domain = @import("domain.zig");
const proxy_control = @import("proxy_control_client.zig");
const runtime_paths = @import("runtime_paths.zig");

const E2eError = error{ InvalidArguments, UnexpectedStatus };

const app_accounts = [_]proxy_control.AppAccount{
    .{ .app_id = "fixture-app-a", .storage_key = "fixture-a", .label = "Fixture A", .provider = .codex, .enabled = true, .connected = true },
    .{ .app_id = "fixture-app-b", .storage_key = "fixture-b", .label = "Fixture B", .provider = .codex, .enabled = true, .connected = true },
    .{ .app_id = "fixture-app-c", .storage_key = "fixture-c", .label = "Fixture C", .provider = .codex, .enabled = true, .connected = true },
    .{ .app_id = "fixture-app-d", .storage_key = "fixture-d", .label = "Fixture D", .provider = .codex, .enabled = true, .connected = true },
};

pub fn main(init: std.process.Init) !void {
    const args = try init.minimal.args.toSlice(init.arena.allocator());
    if (args.len != 5) return E2eError.InvalidArguments;

    var exchange = proxy_control.LoopbackExchange.init(init.gpa, init.io);
    var client = try proxy_control.Client.init(init.gpa, exchange.exchange(), args[2]);
    const layout = try runtime_paths.Layout.fromApplicationSupportDir(args[4]);

    var stdout_buffer: [512]u8 = undefined;
    var stdout_writer = std.Io.File.stdout().writer(init.io, &stdout_buffer);
    const stdout = &stdout_writer.interface;

    if (std.mem.eql(u8, args[1], "initial")) {
        try verifyInitial(&client, &layout, args[3], stdout);
    } else if (std.mem.eql(u8, args[1], "reload")) {
        try verifyReload(&client, &layout, args[3], stdout);
    } else {
        return E2eError.InvalidArguments;
    }
    try stdout.flush();
}

fn verifyInitial(
    client: *proxy_control.Client,
    layout: *const runtime_paths.Layout,
    config_path: []const u8,
    stdout: *std.Io.Writer,
) !void {
    const initial = try client.status();
    try requireV2Config(initial, config_path, 3);
    const mapped = try proxy_control.mapStatus(initial, layout, &app_accounts);
    if (mapped.accountCount() != 3) return E2eError.UnexpectedStatus;
    for (mapped.accountSlice()) |account| if (!account.mapped) return E2eError.UnexpectedStatus;
    try stdout.print("E2E status_v2: PASS accounts=3 mapped=3\n", .{});

    const switched = try client.switchAccount("route-b");
    if (!switched.cursor.eql("route-b")) return E2eError.UnexpectedStatus;
    try stdout.print("E2E switch: PASS cursor_moved=true\n", .{});

    const receipt = try client.pauseAccount("route-a");
    if (!receipt.name.eql("route-a") or receipt.in_flight != 0) return E2eError.UnexpectedStatus;
    const observed = try client.status();
    const paused = rawByName(observed, "route-a") orelse return E2eError.UnexpectedStatus;
    if (paused.state != .paused or paused.in_flight != 0) return E2eError.UnexpectedStatus;
    const observed_mapped = try proxy_control.mapStatus(observed, layout, &app_accounts);
    const mapped_paused = mappedByAppId(observed_mapped, "fixture-app-a") orelse return E2eError.UnexpectedStatus;
    if (mapped_paused.state != .paused or mapped_paused.in_flight != 0) return E2eError.UnexpectedStatus;
    try stdout.print("E2E pause_202: PASS drain_observed=true\n", .{});
}

fn verifyReload(
    client: *proxy_control.Client,
    layout: *const runtime_paths.Layout,
    config_path: []const u8,
    stdout: *std.Io.Writer,
) !void {
    const status = try client.reloadConfig();
    try requireV2Config(status, config_path, 4);
    const expected_order = [_][]const u8{ "route-c", "route-a-next", "route-d", "route-b" };
    for (status.accountSlice(), expected_order) |account, expected| {
        if (!account.name.eql(expected)) return E2eError.UnexpectedStatus;
    }
    if (!status.cursor.eql("route-b")) return E2eError.UnexpectedStatus;
    const renamed = rawByName(status, "route-a-next") orelse return E2eError.UnexpectedStatus;
    const added = rawByName(status, "route-d") orelse return E2eError.UnexpectedStatus;
    if (renamed.state != .paused or added.state != .ready) return E2eError.UnexpectedStatus;

    const mapped = try proxy_control.mapStatus(status, layout, &app_accounts);
    if (mapped.accountCount() != 4) return E2eError.UnexpectedStatus;
    for (mapped.accountSlice()) |account| if (!account.mapped) return E2eError.UnexpectedStatus;
    const migrated = mappedByAppId(mapped, "fixture-app-a") orelse return E2eError.UnexpectedStatus;
    if (migrated.state != .paused) return E2eError.UnexpectedStatus;
    try stdout.print("E2E reload_config: PASS add=true reorder=true mapping=true state_migrated=true\n", .{});
}

fn requireV2Config(status: proxy_control.Status, config_path: []const u8, account_count: usize) !void {
    if (status.version != 2 or !status.has_config_path or
        !status.config_path.eql(config_path) or status.accountCount() != account_count)
    {
        return E2eError.UnexpectedStatus;
    }
}

fn rawByName(status: proxy_control.Status, name: []const u8) ?proxy_control.RawAccount {
    for (status.accountSlice()) |account| if (account.name.eql(name)) return account;
    return null;
}

fn mappedByAppId(status: proxy_control.MappedStatus, app_id: []const u8) ?proxy_control.MappedAccount {
    for (status.accountSlice()) |account| {
        if (account.mapped and account.app_id.eql(app_id)) return account;
    }
    return null;
}
