const std = @import("std");

fn read(allocator: std.mem.Allocator, io: std.Io, path: []const u8) ![]u8 {
    var file = try std.Io.Dir.cwd().openFile(io, path, .{ .allow_directory = false, .follow_symlinks = false });
    defer file.close(io);
    const info = try file.stat(io);
    if (info.kind != .file or info.size > 65_536) return error.UnsafeUpdateState;
    var reader = file.reader(io, &.{});
    return reader.interface.allocRemaining(allocator, .limited(65_536));
}

pub fn isFrozen(allocator: std.mem.Allocator, io: std.Io, root: []const u8) bool {
    const pointer_path = std.fmt.allocPrint(allocator, "{s}/current-update.json", .{root}) catch return true;
    defer allocator.free(pointer_path);
    const pointer_bytes = read(allocator, io, pointer_path) catch |err| return err != error.FileNotFound;
    defer allocator.free(pointer_bytes);
    const Pointer = struct { schema: u32, transaction_id: []const u8 };
    const pointer = std.json.parseFromSlice(Pointer, allocator, pointer_bytes, .{ .ignore_unknown_fields = true }) catch return true;
    defer pointer.deinit();
    if (pointer.value.schema != 1 or !validTransactionID(pointer.value.transaction_id)) return true;
    const path = std.fmt.allocPrint(allocator, "{s}/updates/{s}/journal.json", .{ root, pointer.value.transaction_id }) catch return true;
    defer allocator.free(path);
    const bytes = read(allocator, io, path) catch return true;
    defer allocator.free(bytes);
    return !allowsCoreWrites(allocator, bytes, pointer.value.transaction_id);
}

pub fn allowsCoreWrites(allocator: std.mem.Allocator, bytes: []const u8, expected_id: []const u8) bool {
    const Journal = struct { schema: u32, transaction_id: []const u8, phase: []const u8, install_armed: bool };
    const parsed = std.json.parseFromSlice(Journal, allocator, bytes, .{ .ignore_unknown_fields = true }) catch return false;
    defer parsed.deinit();
    const journal = parsed.value;
    if (journal.schema != 1 or journal.install_armed or !std.mem.eql(u8, journal.transaction_id, expected_id)) return false;
    for ([_][]const u8{ "COMPLETE", "CANCELLED", "ROLLED_BACK" }) |phase| {
        if (std.mem.eql(u8, phase, journal.phase)) return true;
    }
    return false;
}

fn validTransactionID(value: []const u8) bool {
    if (value.len != 36) return false;
    for (value, 0..) |byte, index| {
        if (index == 8 or index == 13 or index == 18 or index == 23) {
            if (byte != '-') return false;
        } else if (!std.ascii.isDigit(byte) and !(byte >= 'a' and byte <= 'f')) return false;
    }
    return true;
}

pub fn managedApp(allocator: std.mem.Allocator, io: std.Io, root: []const u8) !?[]u8 {
    const path = try std.fmt.allocPrint(allocator, "{s}/active-runtime.json", .{root});
    defer allocator.free(path);
    const bytes = read(allocator, io, path) catch |err| switch (err) {
        error.FileNotFound => return null,
        else => return err,
    };
    defer allocator.free(bytes);
    const Active = struct { schema: u32, runtime_id: []const u8, generation: u64 };
    const parsed = try std.json.parseFromSlice(Active, allocator, bytes, .{ .ignore_unknown_fields = true });
    defer parsed.deinit();
    if (parsed.value.schema != 1 or parsed.value.generation < 1 or parsed.value.runtime_id.len != 64) return error.UnsafeUpdateState;
    for (parsed.value.runtime_id) |byte| if (!std.ascii.isDigit(byte) and !(byte >= 'a' and byte <= 'f')) return error.UnsafeUpdateState;
    return try std.fmt.allocPrint(allocator, "{s}/runtimes/{s}/CodexMulti.app", .{ root, parsed.value.runtime_id });
}

test "update guard refuses every nonterminal and installer-armed state" {
    const allocator = std.testing.allocator;
    const id = "a577b4d5-a97d-4038-808c-83a79b474a57";
    for ([_][]const u8{ "PREPARING_APP", "APP_PREPARED", "INSTALLING_APP", "AWAITING_GUI", "WAITING_IDLE", "QUIESCENT", "STOP_COMMITTED", "CANDIDATE_GATED", "ACTIVATION_COMMITTED", "VERIFYING", "ROLLING_BACK", "RECOVERY_REQUIRED", "APP_RECOVERY_REQUIRED" }) |phase| {
        const json = try std.fmt.allocPrint(allocator, "{{\"schema\":1,\"transaction_id\":\"{s}\",\"phase\":\"{s}\",\"install_armed\":false}}", .{ id, phase });
        defer allocator.free(json);
        try std.testing.expect(!allowsCoreWrites(allocator, json, id));
    }
    try std.testing.expect(allowsCoreWrites(allocator, "{\"schema\":1,\"transaction_id\":\"x\",\"phase\":\"COMPLETE\",\"install_armed\":false}", "x"));
    try std.testing.expect(!allowsCoreWrites(allocator, "{\"schema\":1,\"transaction_id\":\"x\",\"phase\":\"COMPLETE\",\"install_armed\":true}", "x"));
    try std.testing.expect(!allowsCoreWrites(allocator, "{\"schema\":1,\"transaction_id\":\"x\",\"phase\":\"COMPLETE\",\"install_armed\":false}", "different"));
    try std.testing.expect(!allowsCoreWrites(allocator, "{}", "x"));
}
