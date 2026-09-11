const std = @import("std");
const login_runtime = @import("../login_runtime.zig");
const importer = @import("../proxy_import_runner.zig");
const runtime_paths = @import("../runtime_paths.zig");
const transport = @import("../process_jsonl.zig");

const testing = std.testing;

const node_path = "/private/tmp/codexmulti-fixture/bin/node";
const cli_path = "/private/tmp/codexmulti-fixture/bin/codexmulti-proxy";
const app_root = "/private/tmp/codexmulti-fixture/app-root";
const config_path = "/private/tmp/codexmulti-fixture/proxy/config.json";

test "proxy importer invocation runs the resolved node binary first and never relies on a shebang" {
    const parent = [_]transport.EnvVar{
        .{ .name = "PATH", .value = "/usr/bin:/bin" },
        .{ .name = "HOME", .value = "/private/tmp/codexmulti-fixture/home" },
        .{ .name = "TMPDIR", .value = "/private/tmp/codexmulti-fixture/tmp" },
        .{ .name = "LANG", .value = "en_US.UTF-8" },
        .{ .name = "HTTP_PROXY", .value = "http://not-forwarded.invalid" },
    };
    var invocation: importer.Invocation = .{};
    try importer.writeInvocation(&invocation, .{
        .node_path = node_path,
        .cli_path = cli_path,
        .app_root = app_root,
        .config_path = config_path,
        .parent_env = .{ .pairs = &parent },
    });

    const expected = [_][]const u8{ node_path, cli_path, "import-codexmulti", "--store", app_root, "--out", config_path };
    try testing.expectEqual(expected.len, invocation.argv().len);
    for (expected, invocation.argv()) |want, actual| try testing.expectEqualStrings(want, actual);
    try testing.expectEqual(@as(usize, 3), invocation.env.count);
    try testing.expectEqualStrings("/usr/bin:/bin", invocation.env.find("PATH").?);
    try testing.expect(invocation.env.find("LANG") == null);
    try testing.expect(invocation.env.find("HTTP_PROXY") == null);
}

test "proxy importer expands only a leading home marker into a canonical path" {
    var expanded = try importer.expandConfigPath("~/proxy/config.json", "/private/tmp/codexmulti-fixture/home");
    try testing.expectEqualStrings("/private/tmp/codexmulti-fixture/home/proxy/config.json", expanded.slice());
    try testing.expectError(error.InvalidConfigPath, importer.expandConfigPath("relative/config.json", "/private/tmp/home"));
    try testing.expectError(error.InvalidConfigPath, importer.expandConfigPath("~/../escape.json", "/private/tmp/home"));
}

test "proxy importer keeps environment values bound when an earlier allowlisted name is absent" {
    const parent = [_]transport.EnvVar{
        .{ .name = "HOME", .value = "/private/tmp/codexmulti-fixture/home" },
        .{ .name = "TMPDIR", .value = "/private/tmp/codexmulti-fixture/tmp" },
    };
    var invocation: importer.Invocation = .{};
    try importer.writeInvocation(&invocation, .{
        .node_path = node_path,
        .cli_path = cli_path,
        .app_root = app_root,
        .config_path = config_path,
        .parent_env = .{ .pairs = &parent },
    });
    try testing.expect(invocation.env.find("PATH") == null);
    try testing.expectEqualStrings("/private/tmp/codexmulti-fixture/home", invocation.env.find("HOME").?);
    try testing.expectEqualStrings("/private/tmp/codexmulti-fixture/tmp", invocation.env.find("TMPDIR").?);
}

test "proxy importer drains bounded output and reaps a successful child once" {
    const chunks = [_]login_runtime.FakeChild.Chunk{.{ .bytes = "discarded importer output\n" }};
    var child: login_runtime.FakeChild = .{ .chunks = &chunks, .scripted_exit = .success };
    const outcome = importer.runChild(child.handle(), .{ .timeout_ms = 1_000, .max_output_bytes = 1024 });
    try testing.expectEqual(importer.Outcome.success, outcome);
    try testing.expect(child.reapedExactlyOnce());
    try testing.expectEqual(@as(usize, 1), child.arm_count);
}

test "proxy importer timeout and output cap both close and reap the owned child" {
    const timeout_chunks = [_]login_runtime.FakeChild.Chunk{.{ .failure = error.Timeout }};
    var timeout_child: login_runtime.FakeChild = .{ .chunks = &timeout_chunks };
    try testing.expectEqual(importer.Outcome.timeout, importer.runChild(timeout_child.handle(), .{ .timeout_ms = 1_000 }));
    try testing.expect(timeout_child.reapedExactlyOnce());

    const noisy_chunks = [_]login_runtime.FakeChild.Chunk{.{ .bytes = "0123456789abcdef" }};
    var noisy_child: login_runtime.FakeChild = .{ .chunks = &noisy_chunks };
    try testing.expectEqual(importer.Outcome.output_too_large, importer.runChild(noisy_child.handle(), .{ .timeout_ms = 1_000, .max_output_bytes = 8 }));
    try testing.expect(noisy_child.reapedExactlyOnce());
}

test "proxy importer invocation refuses an empty or relative node binary" {
    var invocation: importer.Invocation = .{};
    try testing.expectError(error.InvalidNodeExecutable, importer.writeInvocation(&invocation, .{
        .node_path = "",
        .cli_path = cli_path,
        .app_root = app_root,
        .config_path = config_path,
        .parent_env = .{ .pairs = &.{} },
    }));
    try testing.expectError(error.InvalidNodeExecutable, importer.writeInvocation(&invocation, .{
        .node_path = "node",
        .cli_path = cli_path,
        .app_root = app_root,
        .config_path = config_path,
        .parent_env = .{ .pairs = &.{} },
    }));
}

fn writeExecutable(io: std.Io, cwd: std.Io.Dir, path: []const u8) !void {
    var file = try cwd.createFile(io, path, .{ .permissions = .executable_file });
    defer file.close(io);
    try file.writeStreamingAll(io, "#!/bin/sh\n");
}

test "node resolution prefers the configured binary, then user-local, system, and PATH candidates" {
    const io = testing.io;
    var cwd = std.Io.Dir.cwd();
    const root = ".zig-cache/test-proxy-node-resolution";
    cwd.deleteTree(io, root) catch {};
    defer cwd.deleteTree(io, root) catch {};
    try cwd.createDirPath(io, root ++ "/home/.local/bin");
    try cwd.createDirPath(io, root ++ "/system/bin");
    try cwd.createDirPath(io, root ++ "/pathdir");
    try cwd.createDirPath(io, root ++ "/configured");
    try writeExecutable(io, cwd, root ++ "/home/.local/bin/node");
    try writeExecutable(io, cwd, root ++ "/system/bin/node");
    try writeExecutable(io, cwd, root ++ "/pathdir/node");
    try writeExecutable(io, cwd, root ++ "/configured/node");

    const home = try cwd.realPathFileAlloc(io, root ++ "/home", testing.allocator);
    defer testing.allocator.free(home);
    const system_dir = try cwd.realPathFileAlloc(io, root ++ "/system/bin", testing.allocator);
    defer testing.allocator.free(system_dir);
    const path_dir = try cwd.realPathFileAlloc(io, root ++ "/pathdir", testing.allocator);
    defer testing.allocator.free(path_dir);
    const configured_dir = try cwd.realPathFileAlloc(io, root ++ "/configured", testing.allocator);
    defer testing.allocator.free(configured_dir);
    var configured_buffer: [runtime_paths.max_path_bytes]u8 = undefined;
    const configured = try std.fmt.bufPrint(&configured_buffer, "{s}/node", .{configured_dir});
    const system_dirs = [_][]const u8{system_dir};

    var out: runtime_paths.Path = .{};

    try testing.expect(importer.resolveNodeExecutable(io, .{
        .configured = configured,
        .home = home,
        .path_variable = path_dir,
        .system_dirs = &system_dirs,
    }, &out));
    try testing.expectEqualStrings(configured, out.slice());

    try testing.expect(!importer.resolveNodeExecutable(io, .{
        .configured = root ++ "/configured/missing-node",
        .home = home,
        .path_variable = path_dir,
        .system_dirs = &system_dirs,
    }, &out));
    try testing.expect(out.isEmpty());

    try testing.expect(importer.resolveNodeExecutable(io, .{ .home = home, .path_variable = path_dir, .system_dirs = &system_dirs }, &out));
    try testing.expect(std.mem.endsWith(u8, out.slice(), "/home/.local/bin/node"));
    try cwd.deleteFile(io, root ++ "/home/.local/bin/node");
    try testing.expect(importer.resolveNodeExecutable(io, .{ .home = home, .path_variable = path_dir, .system_dirs = &system_dirs }, &out));
    try testing.expect(std.mem.endsWith(u8, out.slice(), "/system/bin/node"));
    try cwd.deleteFile(io, root ++ "/system/bin/node");
    try testing.expect(importer.resolveNodeExecutable(io, .{ .home = home, .path_variable = path_dir, .system_dirs = &system_dirs }, &out));
    try testing.expect(std.mem.endsWith(u8, out.slice(), "/pathdir/node"));
    try cwd.deleteFile(io, root ++ "/pathdir/node");
    try testing.expect(!importer.resolveNodeExecutable(io, .{ .home = home, .path_variable = path_dir, .system_dirs = &system_dirs }, &out));
    try testing.expect(out.isEmpty());
}
