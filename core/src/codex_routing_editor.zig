const std = @import("std");
const ui_model = @import("ui_model.zig");

pub const max_config_bytes: usize = 1024 * 1024;
pub const chatgpt_key = "chatgpt_base_url";
pub const openai_key = "openai_base_url";
pub const chatgpt_value = "http://127.0.0.1:8787/backend-api/";
pub const openai_value = "http://127.0.0.1:8787/backend-api/codex";
pub const canonical_pair =
    "chatgpt_base_url = \"" ++ chatgpt_value ++ "\"\n" ++
    "openai_base_url = \"" ++ openai_value ++ "\"\n";

pub const Fingerprint = [std.crypto.hash.sha2.Sha256.digest_length]u8;

pub const Inspection = struct {
    state: ui_model.CodexRoutingState = .conflicting,
    fingerprint: Fingerprint = @splat(0),
    readable: bool = false,
    exists: bool = false,
};

pub const MutationStatus = enum { success, no_change, refused, raced, unsafe_file, too_large, io };

pub const Mutation = struct {
    status: MutationStatus,
    state: ui_model.CodexRoutingState,
    fingerprint: Fingerprint = @splat(0),
};

pub const Editor = struct {
    context: *anyopaque,
    vtable: *const VTable,

    pub const VTable = struct {
        inspect: *const fn (*anyopaque, []const u8) Inspection,
        enable: *const fn (*anyopaque, []const u8, bool, ?Fingerprint) Mutation,
        disable: *const fn (*anyopaque, []const u8) Mutation,
    };

    pub fn inspect(self: Editor, path: []const u8) Inspection {
        return self.vtable.inspect(self.context, path);
    }

    pub fn enable(self: Editor, path: []const u8, replace_conflicting: bool, expected: ?Fingerprint) Mutation {
        return self.vtable.enable(self.context, path, replace_conflicting, expected);
    }

    pub fn disable(self: Editor, path: []const u8) Mutation {
        return self.vtable.disable(self.context, path);
    }
};

var unwired_context: u8 = 0;
const unwired_vtable: Editor.VTable = .{
    .inspect = unwiredInspect,
    .enable = unwiredEnable,
    .disable = unwiredDisable,
};

fn unwiredInspect(_: *anyopaque, _: []const u8) Inspection {
    return .{};
}

fn unwiredEnable(_: *anyopaque, _: []const u8, _: bool, _: ?Fingerprint) Mutation {
    return .{ .status = .io, .state = .conflicting };
}

fn unwiredDisable(_: *anyopaque, _: []const u8) Mutation {
    return .{ .status = .io, .state = .conflicting };
}

pub fn unwiredEditor() Editor {
    return .{ .context = &unwired_context, .vtable = &unwired_vtable };
}

const Managed = enum { chatgpt, openai };

const Line = struct {
    start: usize,
    content_end: usize,
    end: usize,
    managed: ?Managed = null,
    exact: bool = false,
};

pub const Parsed = struct {
    state: ui_model.CodexRoutingState,
    safe: bool,
    chatgpt_count: usize,
    openai_count: usize,
    first_table_offset: usize,
    first_managed_offset: ?usize,
};

pub fn fingerprint(bytes: []const u8) Fingerprint {
    var digest: Fingerprint = undefined;
    std.crypto.hash.sha2.Sha256.hash(bytes, &digest, .{});
    return digest;
}

pub fn classifyBytes(bytes: []const u8) Parsed {
    if (!std.unicode.utf8ValidateSlice(bytes)) return .{
        .state = .conflicting,
        .safe = false,
        .chatgpt_count = 0,
        .openai_count = 0,
        .first_table_offset = bytes.len,
        .first_managed_offset = null,
    };
    var root = true;
    var safe = true;
    var chatgpt_count: usize = 0;
    var openai_count: usize = 0;
    var chatgpt_exact = false;
    var openai_exact = false;
    var first_table = bytes.len;
    var first_managed: ?usize = null;
    var cursor: usize = 0;
    while (cursor < bytes.len) {
        const line = nextLine(bytes, cursor);
        const content = bytes[line.start..line.content_end];
        const trimmed = std.mem.trim(u8, content, " \t");
        if (std.mem.indexOf(u8, trimmed, "\"\"\"") != null or std.mem.indexOf(u8, trimmed, "'''") != null) safe = false;
        if (root and trimmed.len != 0 and trimmed[0] != '#') {
            if (trimmed[0] == '[') {
                root = false;
                first_table = line.start;
            } else if (managedAssignment(trimmed)) |assignment| {
                if (first_managed == null) first_managed = line.start;
                switch (assignment.managed) {
                    .chatgpt => {
                        chatgpt_count += 1;
                        chatgpt_exact = chatgpt_exact or assignment.exact;
                    },
                    .openai => {
                        openai_count += 1;
                        openai_exact = openai_exact or assignment.exact;
                    },
                }
                if (!assignment.safe) safe = false;
            } else if (mentionsManagedKey(trimmed)) safe = false;
        }
        cursor = line.end;
    }
    const state: ui_model.CodexRoutingState = if (!safe)
        .conflicting
    else if (chatgpt_count == 0 and openai_count == 0)
        .off
    else if (chatgpt_count == 1 and openai_count == 1 and chatgpt_exact and openai_exact)
        .on
    else
        .conflicting;
    return .{
        .state = state,
        .safe = safe,
        .chatgpt_count = chatgpt_count,
        .openai_count = openai_count,
        .first_table_offset = first_table,
        .first_managed_offset = first_managed,
    };
}

const Assignment = struct { managed: Managed, exact: bool, safe: bool };

fn managedAssignment(trimmed: []const u8) ?Assignment {
    const equal = findUnquotedEqual(trimmed) orelse return null;
    const raw_key = std.mem.trim(u8, trimmed[0..equal], " \t");
    const managed = parseManagedKey(raw_key) orelse return null;
    const raw_value = stripInlineComment(trimmed[equal + 1 ..]) orelse return .{ .managed = managed, .exact = false, .safe = false };
    const value = std.mem.trim(u8, raw_value, " \t");
    const expected = switch (managed) {
        .chatgpt => "\"" ++ chatgpt_value ++ "\"",
        .openai => "\"" ++ openai_value ++ "\"",
    };
    return .{ .managed = managed, .exact = std.mem.eql(u8, value, expected), .safe = true };
}

fn parseManagedKey(raw: []const u8) ?Managed {
    var key = raw;
    if (raw.len >= 2 and ((raw[0] == '"' and raw[raw.len - 1] == '"') or (raw[0] == '\'' and raw[raw.len - 1] == '\''))) {
        key = raw[1 .. raw.len - 1];
    } else if (std.mem.indexOfAny(u8, raw, ".\"'") != null) return null;
    if (std.mem.eql(u8, key, chatgpt_key)) return .chatgpt;
    if (std.mem.eql(u8, key, openai_key)) return .openai;
    return null;
}

fn mentionsManagedKey(line: []const u8) bool {
    return std.mem.indexOf(u8, line, chatgpt_key) != null or std.mem.indexOf(u8, line, openai_key) != null;
}

fn findUnquotedEqual(line: []const u8) ?usize {
    var quote: u8 = 0;
    var escaped = false;
    for (line, 0..) |byte, index| {
        if (quote != 0) {
            if (quote == '"' and !escaped and byte == '\\') {
                escaped = true;
                continue;
            }
            if (!escaped and byte == quote) quote = 0;
            escaped = false;
            continue;
        }
        if (byte == '"' or byte == '\'') quote = byte else if (byte == '=') return index else if (byte == '#') return null;
    }
    return null;
}

fn stripInlineComment(value: []const u8) ?[]const u8 {
    var quote: u8 = 0;
    var escaped = false;
    for (value, 0..) |byte, index| {
        if (quote != 0) {
            if (quote == '"' and !escaped and byte == '\\') {
                escaped = true;
                continue;
            }
            if (!escaped and byte == quote) quote = 0;
            escaped = false;
            continue;
        }
        if (byte == '"' or byte == '\'') quote = byte else if (byte == '#') return value[0..index];
    }
    if (quote != 0) return null;
    return value;
}

fn nextLine(bytes: []const u8, start: usize) Line {
    const lf = std.mem.indexOfScalarPos(u8, bytes, start, '\n') orelse return .{
        .start = start,
        .content_end = bytes.len,
        .end = bytes.len,
    };
    const content_end = if (lf > start and bytes[lf - 1] == '\r') lf - 1 else lf;
    return .{ .start = start, .content_end = content_end, .end = lf + 1 };
}

fn preferredNewline(bytes: []const u8) []const u8 {
    const lf = std.mem.indexOfScalar(u8, bytes, '\n') orelse return "\n";
    return if (lf > 0 and bytes[lf - 1] == '\r') "\r\n" else "\n";
}

pub fn enabledBytes(allocator: std.mem.Allocator, original: []const u8, replace: bool) ![]u8 {
    const parsed = classifyBytes(original);
    if (parsed.state == .on) return allocator.dupe(u8, original);
    if (parsed.state == .conflicting and !replace) return error.Conflict;
    if (!parsed.safe and parsed.state == .conflicting) return error.Ambiguous;

    var stripped = std.ArrayList(u8).empty;
    defer stripped.deinit(allocator);
    const insertion = if (parsed.state == .off) parsed.first_table_offset else (parsed.first_managed_offset orelse parsed.first_table_offset);
    var adjusted_insertion = insertion;
    var cursor: usize = 0;
    while (cursor < original.len) {
        const line = nextLine(original, cursor);
        const trimmed = std.mem.trim(u8, original[line.start..line.content_end], " \t");
        const remove = parseManagedAtRoot(original, line.start, trimmed);
        if (remove) {
            if (line.start < insertion) adjusted_insertion -= line.end - line.start;
        } else try stripped.appendSlice(allocator, original[line.start..line.end]);
        cursor = line.end;
    }
    if (parsed.state == .off) adjusted_insertion = parsed.first_table_offset;

    const nl = preferredNewline(original);
    var pair = std.ArrayList(u8).empty;
    defer pair.deinit(allocator);
    try pair.appendSlice(allocator, "chatgpt_base_url = \"");
    try pair.appendSlice(allocator, chatgpt_value);
    try pair.appendSlice(allocator, "\"");
    try pair.appendSlice(allocator, nl);
    try pair.appendSlice(allocator, "openai_base_url = \"");
    try pair.appendSlice(allocator, openai_value);
    try pair.appendSlice(allocator, "\"");
    try pair.appendSlice(allocator, nl);

    var result = std.ArrayList(u8).empty;
    errdefer result.deinit(allocator);
    const source = stripped.items;
    const point = @min(adjusted_insertion, source.len);
    try result.appendSlice(allocator, source[0..point]);
    if (point > 0 and source[point - 1] != '\n') try result.appendSlice(allocator, nl);
    try result.appendSlice(allocator, pair.items);
    try result.appendSlice(allocator, source[point..]);
    return result.toOwnedSlice(allocator);
}

pub fn disabledBytes(allocator: std.mem.Allocator, original: []const u8) ![]u8 {
    const parsed = classifyBytes(original);
    if (parsed.state == .off) return allocator.dupe(u8, original);
    if (parsed.state != .on or !parsed.safe) return error.Conflict;
    var result = std.ArrayList(u8).empty;
    errdefer result.deinit(allocator);
    var root = true;
    var cursor: usize = 0;
    while (cursor < original.len) {
        const line = nextLine(original, cursor);
        const trimmed = std.mem.trim(u8, original[line.start..line.content_end], " \t");
        if (root and trimmed.len != 0 and trimmed[0] != '#' and trimmed[0] == '[') root = false;
        const remove = root and managedAssignment(trimmed) != null;
        if (!remove) try result.appendSlice(allocator, original[line.start..line.end]);
        cursor = line.end;
    }
    return result.toOwnedSlice(allocator);
}

fn parseManagedAtRoot(bytes: []const u8, target_start: usize, target_trimmed: []const u8) bool {
    var root = true;
    var cursor: usize = 0;
    while (cursor < target_start) {
        const line = nextLine(bytes, cursor);
        const trimmed = std.mem.trim(u8, bytes[line.start..line.content_end], " \t");
        if (root and trimmed.len != 0 and trimmed[0] != '#' and trimmed[0] == '[') root = false;
        cursor = line.end;
    }
    return root and managedAssignment(target_trimmed) != null;
}

pub const FileEditor = struct {
    io: std.Io,
    allocator: std.mem.Allocator,

    before_rename: ?*const fn ([]const u8) void = null,
    fixed_timestamp_ns: ?i96 = null,

    const vtable: Editor.VTable = .{ .inspect = inspect, .enable = enable, .disable = disable };

    pub fn init(io: std.Io, allocator: std.mem.Allocator) FileEditor {
        return .{ .io = io, .allocator = allocator };
    }

    pub fn editor(self: *FileEditor) Editor {
        return .{ .context = self, .vtable = &vtable };
    }

    fn inspect(context: *anyopaque, path: []const u8) Inspection {
        const self: *FileEditor = @ptrCast(@alignCast(context));
        const loaded = self.readSafe(path) catch |err| return switch (err) {
            error.FileNotFound => .{ .state = .off, .fingerprint = fingerprint(""), .readable = true, .exists = false },
            else => .{},
        };
        defer self.allocator.free(loaded.bytes);
        const parsed = classifyBytes(loaded.bytes);
        return .{
            .state = parsed.state,
            .fingerprint = fingerprint(loaded.bytes),
            .readable = true,
            .exists = true,
        };
    }

    fn enable(context: *anyopaque, path: []const u8, replace: bool, expected: ?Fingerprint) Mutation {
        const self: *FileEditor = @ptrCast(@alignCast(context));
        return self.mutate(path, .enable, replace, expected);
    }

    fn disable(context: *anyopaque, path: []const u8) Mutation {
        const self: *FileEditor = @ptrCast(@alignCast(context));
        return self.mutate(path, .disable, false, null);
    }

    const Loaded = struct { bytes: []u8, permissions: std.Io.File.Permissions };
    const Kind = enum { enable, disable };

    fn readSafe(self: *FileEditor, path: []const u8) !Loaded {
        if (path.len == 0 or path[0] != '/') return error.Unsafe;
        const cwd = std.Io.Dir.cwd();
        var file = try cwd.openFile(self.io, path, .{ .allow_directory = false, .follow_symlinks = false });
        defer file.close(self.io);
        const stat = try file.stat(self.io);
        if (stat.kind != .file) return error.Unsafe;
        if (stat.size > max_config_bytes) return error.FileTooBig;
        if (!handleOwnedByCurrentUser(file.handle)) return error.Unsafe;
        var reader = file.reader(self.io, &.{});
        const bytes = reader.interface.allocRemaining(self.allocator, .limited(max_config_bytes)) catch |err| switch (err) {
            error.StreamTooLong => return error.FileTooBig,
            error.OutOfMemory => return error.OutOfMemory,
            error.ReadFailed => return reader.err.?,
        };
        return .{ .bytes = bytes, .permissions = stat.permissions };
    }

    fn mutate(self: *FileEditor, path: []const u8, kind: Kind, replace: bool, expected: ?Fingerprint) Mutation {
        const loaded = self.readSafe(path) catch |err| {
            if (err == error.FileNotFound) {
                if (kind == .disable) return .{ .status = .no_change, .state = .off, .fingerprint = fingerprint("") };
                if (expected) |confirmed| {
                    if (!std.mem.eql(u8, &confirmed, &fingerprint(""))) return .{ .status = .raced, .state = .off };
                }
                self.createMissing(path) catch |create_error| return .{
                    .status = switch (create_error) {
                        error.PathAlreadyExists => .raced,
                        error.Unsafe, error.SymLinkLoop, error.NotDir => .unsafe_file,
                        else => .io,
                    },
                    .state = .off,
                };
                return .{ .status = .success, .state = .on, .fingerprint = fingerprint(canonical_pair) };
            }
            return .{
                .status = switch (err) {
                    error.FileTooBig => .too_large,
                    error.Unsafe, error.SymLinkLoop => .unsafe_file,
                    else => .io,
                },
                .state = .conflicting,
            };
        };
        defer self.allocator.free(loaded.bytes);
        const parsed = classifyBytes(loaded.bytes);
        const before = fingerprint(loaded.bytes);
        if (kind == .enable and parsed.state == .on) return .{ .status = .no_change, .state = .on, .fingerprint = before };
        if (kind == .disable and parsed.state == .off) return .{ .status = .no_change, .state = .off, .fingerprint = before };
        if (!parsed.safe or (kind == .disable and parsed.state == .conflicting) or
            (kind == .enable and parsed.state == .conflicting and !replace))
        {
            return .{ .status = .refused, .state = parsed.state, .fingerprint = before };
        }
        if (kind == .enable and parsed.state == .conflicting) {
            const confirmed = expected orelse return .{ .status = .refused, .state = .conflicting, .fingerprint = before };
            if (!std.mem.eql(u8, &confirmed, &before)) return .{ .status = .raced, .state = .conflicting, .fingerprint = before };
        }
        const next = switch (kind) {
            .enable => enabledBytes(self.allocator, loaded.bytes, replace) catch return .{ .status = .refused, .state = parsed.state, .fingerprint = before },
            .disable => disabledBytes(self.allocator, loaded.bytes) catch return .{ .status = .refused, .state = parsed.state, .fingerprint = before },
        };
        defer self.allocator.free(next);

        self.writeBackupAndTemp(path, loaded.bytes, next, loaded.permissions, before) catch |err| return .{
            .status = if (err == error.Raced) .raced else .io,
            .state = parsed.state,
            .fingerprint = before,
        };
        return .{ .status = .success, .state = classifyBytes(next).state, .fingerprint = fingerprint(next) };
    }

    fn createMissing(self: *FileEditor, path: []const u8) !void {
        const parent_path = std.fs.path.dirname(path) orelse return error.Unsafe;
        const cwd = std.Io.Dir.cwd();
        cwd.createDir(self.io, parent_path, .fromMode(0o700)) catch |err| {
            if (err != error.PathAlreadyExists) return err;
        };
        var parent = try cwd.openDir(self.io, parent_path, .{ .follow_symlinks = false });
        defer parent.close(self.io);
        if (!handleOwnedByCurrentUser(parent.handle)) return error.Unsafe;
        const name = std.fs.path.basename(path);
        var temp_buffer: [2048]u8 = undefined;
        const stamp = self.fixed_timestamp_ns orelse std.Io.Clock.real.now(self.io).nanoseconds;
        const temp = try std.fmt.bufPrint(&temp_buffer, ".{s}.tmp.{d}", .{ name, stamp });
        var file = try parent.createFile(self.io, temp, .{ .exclusive = true, .permissions = .fromMode(0o600) });
        defer file.close(self.io);
        defer parent.deleteFile(self.io, temp) catch {};
        try file.writeStreamingAll(self.io, canonical_pair);
        try @import("durable_file.zig").syncFile(self.io, file);
        if (self.before_rename) |hook| hook(path);
        try parent.renamePreserve(temp, parent, name, self.io);
        try @import("durable_file.zig").syncDirectory(self.io, parent);
    }

    fn writeBackupAndTemp(
        self: *FileEditor,
        path: []const u8,
        original: []const u8,
        next: []const u8,
        permissions: std.Io.File.Permissions,
        expected: Fingerprint,
    ) !void {
        var backup_buffer: [2048]u8 = undefined;
        var temp_buffer: [2048]u8 = undefined;
        const stamp = self.fixed_timestamp_ns orelse std.Io.Clock.real.now(self.io).nanoseconds;
        const backup = try std.fmt.bufPrint(&backup_buffer, "{s}.bak.{d}", .{ path, stamp });
        const temp = try std.fmt.bufPrint(&temp_buffer, "{s}.tmp.{d}", .{ path, stamp });
        const cwd = std.Io.Dir.cwd();

        var backup_file = try cwd.createFile(self.io, backup, .{ .exclusive = true, .permissions = permissions });
        defer backup_file.close(self.io);
        errdefer cwd.deleteFile(self.io, backup) catch {};
        try backup_file.setPermissions(self.io, permissions);
        try backup_file.writeStreamingAll(self.io, original);
        try backup_file.sync(self.io);

        var temp_file = try cwd.createFile(self.io, temp, .{
            .exclusive = true,
            .permissions = std.Io.File.Permissions.fromMode(0o600),
        });
        defer temp_file.close(self.io);
        errdefer cwd.deleteFile(self.io, temp) catch {};
        try temp_file.writeStreamingAll(self.io, next);
        try temp_file.sync(self.io);

        if (self.before_rename) |hook| hook(path);
        const reread = try self.readSafe(path);
        defer self.allocator.free(reread.bytes);
        if (!std.mem.eql(u8, &expected, &fingerprint(reread.bytes))) return error.Raced;
        try cwd.rename(temp, cwd, path, self.io);
        try cwd.setFilePermissions(self.io, path, permissions, .{ .follow_symlinks = false });
        try @import("durable_file.zig").syncFile(self.io, temp_file);
        try @import("durable_file.zig").syncParent(self.io, cwd, path);
    }
};

fn handleOwnedByCurrentUser(handle: std.posix.fd_t) bool {
    var stat: std.c.Stat = undefined;
    if (std.c.fstat(handle, &stat) != 0) return false;
    return stat.uid == std.c.getuid();
}
