const std = @import("std");
const transport = @import("../process_jsonl.zig");

const testing = std.testing;

test "bundled Helpers is first on the provider child PATH and preserves the parent PATH" {
    var child_env: std.process.Environ.Map = .init(testing.allocator);
    defer child_env.deinit();
    try child_env.put("PATH", "/usr/bin:/bin");

    try transport.prepareProviderChildEnvironment(
        &child_env,
        "",
        "/tmp/CodexMulti.app/Contents/Helpers",
    );

    try testing.expectEqualStrings(
        "/tmp/CodexMulti.app/Contents/Helpers:/usr/bin:/bin",
        child_env.get("PATH").?,
    );
}

test "missing bundled Helpers leaves the ordinary provider PATH behavior intact" {
    var child_env: std.process.Environ.Map = .init(testing.allocator);
    defer child_env.deinit();
    try child_env.put("PATH", "/usr/bin:/bin");

    try transport.prepareProviderChildEnvironment(
        &child_env,
        "/tmp/home/.local/bin/codex",
        "",
    );

    try testing.expectEqualStrings(
        "/tmp/home/.local/bin:/usr/bin:/bin",
        child_env.get("PATH").?,
    );
}

test "provider CLI with env node shebang runs through the bundled helper" {
    const io = testing.io;
    var cwd = std.Io.Dir.cwd();
    const root = ".zig-cache/test-provider-bundled-node";
    cwd.deleteTree(io, root) catch {};
    defer cwd.deleteTree(io, root) catch {};
    try cwd.createDirPath(io, root ++ "/CodexMulti.app/Contents/Helpers");
    try cwd.createDirPath(io, root ++ "/home/.local/bin");

    var node = try cwd.createFile(io, root ++ "/CodexMulti.app/Contents/Helpers/node", .{
        .permissions = .executable_file,
    });
    defer node.close(io);
    try node.writeStreamingAll(io, "#!/bin/sh\nprintf 'bundled-node:%s\\n' \"$1\"\n");

    var cli = try cwd.createFile(io, root ++ "/home/.local/bin/codex", .{
        .permissions = .executable_file,
    });
    defer cli.close(io);
    try cli.writeStreamingAll(io, "#!/usr/bin/env node\n");

    const app_path = try cwd.realPathFileAlloc(io, root ++ "/CodexMulti.app", testing.allocator);
    defer testing.allocator.free(app_path);
    const cli_path = try cwd.realPathFileAlloc(io, root ++ "/home/.local/bin/codex", testing.allocator);
    defer testing.allocator.free(cli_path);
    const helpers = try std.fmt.allocPrint(testing.allocator, "{s}/Contents/Helpers", .{app_path});
    defer testing.allocator.free(helpers);

    var child_env: std.process.Environ.Map = .init(testing.allocator);
    defer child_env.deinit();
    try child_env.put("PATH", "/usr/bin:/bin");
    try transport.prepareProviderChildEnvironment(&child_env, cli_path, helpers);

    const argv = [_][]const u8{ cli_path, "--version" };
    const result = try std.process.run(testing.allocator, io, .{
        .argv = &argv,
        .environ_map = &child_env,
        .stdout_limit = .limited(1024),
        .stderr_limit = .limited(1024),
    });
    defer testing.allocator.free(result.stdout);
    defer testing.allocator.free(result.stderr);

    try testing.expectEqual(std.process.Child.Term{ .exited = 0 }, result.term);
    const expected = try std.fmt.allocPrint(testing.allocator, "bundled-node:{s}\n", .{cli_path});
    defer testing.allocator.free(expected);
    try testing.expectEqualStrings(expected, result.stdout);
}
