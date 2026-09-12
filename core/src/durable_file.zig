const std = @import("std");
const builtin = @import("builtin");

pub fn syncFile(io: std.Io, file: std.Io.File) !void {
    try file.sync(io);
    if (builtin.os.tag == .macos) {
        while (std.c.fcntl(file.handle, std.c.F.FULLFSYNC) != 0) {
            if (std.posix.errno(-1) != .INTR) return error.FileSyncFailed;
        }
    }
}

pub fn syncDirectory(io: std.Io, dir: std.Io.Dir) !void {
    try syncFile(io, .{ .handle = dir.handle, .flags = .{ .nonblocking = false } });
}

pub fn syncParent(io: std.Io, dir: std.Io.Dir, sub_path: []const u8) !void {
    var parent = try dir.openDir(io, std.fs.path.dirname(sub_path) orelse ".", .{});
    defer parent.close(io);
    try syncDirectory(io, parent);
}
