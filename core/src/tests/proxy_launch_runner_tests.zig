const std = @import("std");
const runner = @import("proxy_launch_runner");

const testing = std.testing;

test "launch runner renders only the canonical exact argv forms" {
    var argv: runner.Argv = .{};
    try testing.expect(runner.writeArgv(&argv, .{ .print = .{ .domain_target = "gui/501/dev.codexmulti.app.proxy" } }));
    try testing.expectEqualDeep(([_][]const u8{ "/bin/launchctl", "print", "gui/501/dev.codexmulti.app.proxy" })[0..], argv.slice());

    try testing.expect(runner.writeArgv(&argv, .{ .bootstrap = .{
        .domain = "gui/501",
        .plist_path = "/private/tmp/Home With Space/Library/LaunchAgents/dev.codexmulti.app.proxy.plist",
    } }));
    try testing.expectEqualDeep(([_][]const u8{
        "/bin/launchctl",                                                                   "bootstrap", "gui/501",
        "/private/tmp/Home With Space/Library/LaunchAgents/dev.codexmulti.app.proxy.plist",
    })[0..], argv.slice());

    try testing.expect(runner.writeArgv(&argv, .{ .bootout = .{ .domain_target = "gui/501/dev.codexmulti.app.proxy" } }));
    try testing.expectEqualDeep(([_][]const u8{ "/bin/launchctl", "bootout", "gui/501/dev.codexmulti.app.proxy" })[0..], argv.slice());

    try testing.expect(runner.writeArgv(&argv, .{ .kickstart = .{ .domain_target = "gui/501/dev.codexmulti.app.proxy" } }));
    try testing.expectEqualDeep(([_][]const u8{ "/bin/launchctl", "kickstart", "gui/501/dev.codexmulti.app.proxy" })[0..], argv.slice());
}

test "launch runner refuses shell-shaped and traversal-bearing requests" {
    var argv: runner.Argv = .{};
    try testing.expect(!runner.writeArgv(&argv, .{ .print = .{ .domain_target = "gui/501/x; touch /tmp/pwn" } }));
    try testing.expect(!runner.writeArgv(&argv, .{ .bootstrap = .{ .domain = "gui/501", .plist_path = "/tmp/a/../b.plist" } }));
    try testing.expect(!runner.writeArgv(&argv, .{ .bootstrap = .{ .domain = "user/501", .plist_path = "/tmp/b.plist" } }));
}
