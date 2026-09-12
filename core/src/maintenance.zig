const std = @import("std");
const manager = @import("proxy_service_manager.zig");
const control = @import("proxy_control_client.zig");
const store = @import("store.zig");

pub fn main(init: std.process.Init) !void {
    const allocator = init.arena.allocator();
    const args = try init.minimal.args.toSlice(allocator);
    if (args.len == 2 and std.mem.eql(u8, args[1], "--help")) {
        std.debug.print("Usage: codexmulti-maintenance prepare-uninstall\nRestores direct Codex routing, drains and removes the owned LaunchAgent. Account data is retained.\n", .{});
        std.debug.print("{s}\n", .{@import("core_provenance").marker});
        return;
    }
    if (args.len != 2 or !std.mem.eql(u8, args[1], "prepare-uninstall")) return error.InvalidArguments;
    const uid = std.c.getuid();
    if (uid == 0) return error.RunAsDesktopUser;
    const home = init.environ_map.get("HOME") orelse return error.MissingHome;
    const executable = try std.process.executablePathAlloc(init.io, allocator);
    const suffix = "/Contents/Helpers/codexmulti-maintenance";
    if (!std.mem.endsWith(u8, executable, suffix)) return error.RunBundledHelper;
    const app_path = executable[0 .. executable.len - suffix.len];
    const data_path = try std.fmt.allocPrint(allocator, "{s}/Library/Application Support/CodexMulti", .{home});
    const settings_path = try std.fmt.allocPrint(allocator, "{s}/proxy-settings.json", .{data_path});
    const loaded = store.loadProxySettings(allocator, init.io, .cwd(), settings_path) catch |err| switch (err) {
        error.FileNotFound => null,
        else => return err,
    };
    defer if (loaded) |value| value.deinit();
    const settings = if (loaded) |value| value.value.proxy else store.ProxySettings{};
    const config = try manager.proxy_import.expandConfigPath(settings.config_path, home);
    const paths = try manager.Paths.init(home, app_path, data_path, config.slice(), @intCast(uid));
    var launch = manager.proxy_launch.ProcessRunner.init(init.io, init.gpa);
    var routing = manager.codex_routing.FileEditor.init(init.io, init.gpa);
    var artifacts = manager.FileArtifacts.init(init.io, init.gpa);
    var exchange = control.LoopbackExchange.init(init.gpa, init.io);
    try exchange.useConfigPath(config.slice());
    var health = manager.LoopbackHealth.init(init.gpa, exchange.exchange());
    manager.prepareUninstall(.{
        .io = init.io,
        .allocator = init.gpa,
        .paths = paths,
        .identity = try manager.loadBundleIdentity(init.gpa, init.io, app_path),
        .launch = launch.runner(),
        .routing = routing.editor(),
        .artifacts = artifacts.store(),
        .health = health.probe(),
        .control_base_url = settings.base_url,
    }) catch |err| {
        std.debug.print("Removal paused: {s}. Quit active Codex clients and retry. For conflicting routing or service ownership, follow README recovery instructions before deleting the app.\n", .{@errorName(err)});
        return err;
    };
    std.debug.print("Direct Codex routing restored; CodexMulti LaunchAgent removed. Account data retained.\n", .{});
}
