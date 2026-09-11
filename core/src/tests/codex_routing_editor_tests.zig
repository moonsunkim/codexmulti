const std = @import("std");
const editor_mod = @import("codex_routing_editor");

const testing = std.testing;

test "routing classification covers off on conflicts duplicate and table-local keys" {
    try testing.expectEqual(.off, editor_mod.classifyBytes("model = \"gpt\"\n[profile.a]\nchatgpt_base_url = \"local\"\n").state);
    try testing.expectEqual(.on, editor_mod.classifyBytes(editor_mod.canonical_pair).state);
    try testing.expectEqual(.conflicting, editor_mod.classifyBytes("chatgpt_base_url = \"other\"\n").state);
    try testing.expectEqual(.conflicting, editor_mod.classifyBytes(editor_mod.canonical_pair ++ "chatgpt_base_url = \"http://127.0.0.1:8787/backend-api/\"\n").state);
    try testing.expectEqual(.conflicting, editor_mod.classifyBytes("chatgpt_base_url = \"\"\"multi\nline\"\"\"\n").state);
}

test "enable and disable preserve every unrelated byte and newline style" {
    const original = "# keep\r\nmodel = \"gpt-5.6\"\r\n[profiles.work]\r\nopenai_base_url = \"table-local\"\r\n";
    const enabled = try editor_mod.enabledBytes(testing.allocator, original, false);
    defer testing.allocator.free(enabled);
    try testing.expectEqual(.on, editor_mod.classifyBytes(enabled).state);
    try testing.expect(std.mem.indexOf(u8, enabled, "# keep\r\nmodel = \"gpt-5.6\"\r\n") != null);
    try testing.expect(std.mem.indexOf(u8, enabled, "[profiles.work]\r\nopenai_base_url = \"table-local\"\r\n") != null);
    try testing.expect(std.mem.indexOf(u8, enabled, "\n") != null);

    const disabled = try editor_mod.disabledBytes(testing.allocator, enabled);
    defer testing.allocator.free(disabled);
    try testing.expectEqualStrings(original, disabled);
}

fn setupRoot(name: []const u8) !struct { root: [:0]u8, path: []u8 } {
    const cwd = std.Io.Dir.cwd();
    const relative = try std.fmt.allocPrint(testing.allocator, ".zig-cache/{s}", .{name});
    defer testing.allocator.free(relative);
    cwd.deleteTree(testing.io, relative) catch {};
    try cwd.createDirPath(testing.io, relative);
    const root = try cwd.realPathFileAlloc(testing.io, relative, testing.allocator);
    const path = try std.fmt.allocPrint(testing.allocator, "{s}/config.toml", .{root});
    return .{ .root = root, .path = path };
}

test "file editor makes a timestamped byte backup and preserves mode" {
    const fixture = try setupRoot("p3-routing-backup");
    defer testing.allocator.free(fixture.root);
    defer testing.allocator.free(fixture.path);
    defer std.Io.Dir.cwd().deleteTree(testing.io, fixture.root) catch {};
    const original = "model = \"gpt-5.6\"\n";
    var file = try std.Io.Dir.cwd().createFile(testing.io, fixture.path, .{ .permissions = std.Io.File.Permissions.fromMode(0o640) });
    try file.writeStreamingAll(testing.io, original);
    file.close(testing.io);

    var backing = editor_mod.FileEditor.init(testing.io, testing.allocator);
    backing.fixed_timestamp_ns = 123456789;
    const editor = backing.editor();
    const result = editor.enable(fixture.path, false, null);
    try testing.expectEqual(editor_mod.MutationStatus.success, result.status);
    try testing.expectEqual(.on, result.state);

    const backup_path = try std.fmt.allocPrint(testing.allocator, "{s}.bak.123456789", .{fixture.path});
    defer testing.allocator.free(backup_path);
    const backup = try std.Io.Dir.cwd().readFileAlloc(testing.io, backup_path, testing.allocator, .limited(1024));
    defer testing.allocator.free(backup);
    try testing.expectEqualStrings(original, backup);
    const before_mode = (try std.Io.Dir.cwd().statFile(testing.io, backup_path, .{})).permissions.toMode() & 0o777;
    const after_mode = (try std.Io.Dir.cwd().statFile(testing.io, fixture.path, .{})).permissions.toMode() & 0o777;
    try testing.expectEqual(@as(std.posix.mode_t, 0o640), before_mode);
    try testing.expectEqual(before_mode, after_mode);

    try testing.expectEqual(editor_mod.MutationStatus.no_change, editor.enable(fixture.path, false, null).status);
}

var race_replacement: []const u8 = "model = \"raced\"\n";
fn raceHook(path: []const u8) void {
    std.Io.Dir.cwd().writeFile(testing.io, .{ .sub_path = path, .data = race_replacement }) catch {};
}

test "conflict replacement requires the confirmed fingerprint and refuses a pre-rename race" {
    const fixture = try setupRoot("p3-routing-race");
    defer testing.allocator.free(fixture.root);
    defer testing.allocator.free(fixture.path);
    defer std.Io.Dir.cwd().deleteTree(testing.io, fixture.root) catch {};
    try std.Io.Dir.cwd().writeFile(testing.io, .{ .sub_path = fixture.path, .data = "chatgpt_base_url = \"other\"\n" });

    var backing = editor_mod.FileEditor.init(testing.io, testing.allocator);
    backing.fixed_timestamp_ns = 987654321;
    const editor = backing.editor();
    const inspected = editor.inspect(fixture.path);
    try testing.expectEqual(.conflicting, inspected.state);
    try testing.expectEqual(editor_mod.MutationStatus.refused, editor.enable(fixture.path, false, null).status);
    var wrong = inspected.fingerprint;
    wrong[0] ^= 0xff;
    try testing.expectEqual(editor_mod.MutationStatus.raced, editor.enable(fixture.path, true, wrong).status);

    backing.before_rename = raceHook;
    try testing.expectEqual(editor_mod.MutationStatus.raced, editor.enable(fixture.path, true, inspected.fingerprint).status);
    const current = try std.Io.Dir.cwd().readFileAlloc(testing.io, fixture.path, testing.allocator, .limited(1024));
    defer testing.allocator.free(current);
    try testing.expectEqualStrings(race_replacement, current);
}

test "file editor refuses symlink and oversized TOML" {
    const fixture = try setupRoot("p3-routing-unsafe");
    defer testing.allocator.free(fixture.root);
    defer testing.allocator.free(fixture.path);
    defer std.Io.Dir.cwd().deleteTree(testing.io, fixture.root) catch {};
    const real_path = try std.fmt.allocPrint(testing.allocator, "{s}/real.toml", .{fixture.root});
    defer testing.allocator.free(real_path);
    try std.Io.Dir.cwd().writeFile(testing.io, .{ .sub_path = real_path, .data = "" });
    try std.Io.Dir.cwd().symLink(testing.io, real_path, fixture.path, .{});
    var backing = editor_mod.FileEditor.init(testing.io, testing.allocator);
    const editor = backing.editor();
    try testing.expectEqual(editor_mod.MutationStatus.unsafe_file, editor.enable(fixture.path, false, null).status);

    try std.Io.Dir.cwd().deleteFile(testing.io, fixture.path);
    var huge = try std.Io.Dir.cwd().createFile(testing.io, fixture.path, .{});
    try huge.setLength(testing.io, editor_mod.max_config_bytes + 1);
    huge.close(testing.io);
    try testing.expectEqual(editor_mod.MutationStatus.too_large, editor.enable(fixture.path, false, null).status);
}
