const std = @import("std");
const domain = @import("domain.zig");
const transport = @import("process_jsonl.zig");

pub const max_path_bytes: usize = 512;

pub const max_component_bytes: usize = 128;

pub const max_segment_bytes: usize = 64;

comptime {
    if (max_path_bytes > transport.max_path_bytes) {
        @compileError("runtime path bound must not exceed the transport path bound");
    }
}

pub const app_bundle_id = "dev.codexmulti.app";

pub const app_data_directory_name = "CodexMulti";

pub const library_component = "Library";
pub const application_support_component = "Application Support";

pub const accounts_component = "accounts";

pub const codex_home_component = "codex";
pub const claude_config_component = "claude";

pub const registry_file_name = "accounts.json";
pub const registry_temp_file_name = "accounts.json.tmp";
pub const snapshots_file_name = "snapshots.json";
pub const snapshots_temp_file_name = "snapshots.json.tmp";
pub const attempts_file_name = "attempts.json";
pub const attempts_temp_file_name = "attempts.json.tmp";
pub const app_settings_file_name = "app-settings.json";
pub const app_settings_temp_file_name = "app-settings.json.tmp";
pub const proxy_settings_file_name = "proxy-settings.json";
pub const proxy_settings_temp_file_name = "proxy-settings.json.tmp";
pub const proxy_status_file_name = "proxy-status.json";
pub const proxy_status_temp_file_name = "proxy-status.json.tmp";
pub const codex_auth_file_name = "auth.json";

pub const reserved_segments = [_][]const u8{
    accounts_component,
    registry_file_name,
    registry_temp_file_name,
    snapshots_file_name,
    snapshots_temp_file_name,
    attempts_file_name,
    attempts_temp_file_name,
    app_settings_file_name,
    app_settings_temp_file_name,
    proxy_settings_file_name,
    proxy_settings_temp_file_name,
    proxy_status_file_name,
    proxy_status_temp_file_name,
};

pub const PathError = error{
    EmptyPath,
    PathTooLong,

    PathNotAbsolute,

    PathNotCanonical,
    InvalidPathByte,
    ComponentTooLong,

    NotAppRoot,

    OutsideAppRoot,
};

pub const SegmentError = error{
    EmptySegment,
    SegmentTooLong,

    SegmentNotRelative,

    SegmentTraversal,
    InvalidSegmentByte,
    ReservedSegment,
};

pub fn validateAbsoluteDir(path: []const u8) PathError!void {
    if (path.len == 0) return error.EmptyPath;
    if (path.len > max_path_bytes) return error.PathTooLong;
    if (path[0] != '/') return error.PathNotAbsolute;
    if (path[path.len - 1] == '/') return error.PathNotCanonical;
    for (path) |byte| {
        if (byte == 0 or byte == '=' or byte == 0x7f or byte < 0x20) return error.InvalidPathByte;
    }

    var components = std.mem.splitScalar(u8, path[1..], '/');
    var count: usize = 0;
    while (components.next()) |component| {
        if (component.len == 0) return error.PathNotCanonical;
        if (component.len > max_component_bytes) return error.ComponentTooLong;
        if (std.mem.eql(u8, component, ".") or std.mem.eql(u8, component, "..")) return error.PathNotCanonical;
        count += 1;
    }
    if (count == 0) return error.PathNotCanonical;

    transport.validateCodexHome(path) catch return error.PathNotCanonical;
}

pub fn validateComponent(component: []const u8) SegmentError!void {
    if (component.len == 0) return error.EmptySegment;
    if (component.len > max_component_bytes) return error.SegmentTooLong;
    if (std.mem.indexOfScalar(u8, component, '/') != null) return error.SegmentNotRelative;
    if (std.mem.eql(u8, component, ".") or std.mem.eql(u8, component, "..")) return error.SegmentTraversal;
    if (std.mem.indexOf(u8, component, "..") != null) return error.SegmentTraversal;
    for (component) |byte| {
        if (byte == 0 or byte == '=' or byte == 0x7f or byte < 0x20) return error.InvalidSegmentByte;
    }
    return;
}

pub fn validateAccountSegment(segment: []const u8) SegmentError!void {
    if (segment.len == 0) return error.EmptySegment;
    if (segment.len > max_segment_bytes) return error.SegmentTooLong;
    if (std.mem.indexOfScalar(u8, segment, '/') != null) return error.SegmentNotRelative;
    if (std.mem.indexOfScalar(u8, segment, '\\') != null) return error.SegmentNotRelative;
    if (std.mem.eql(u8, segment, ".") or std.mem.eql(u8, segment, "..")) return error.SegmentTraversal;
    if (std.mem.indexOf(u8, segment, "..") != null) return error.SegmentTraversal;
    if (segment[0] == '.' or segment[segment.len - 1] == '.') return error.SegmentTraversal;
    if (segment[0] == '-') return error.InvalidSegmentByte;
    for (segment) |byte| {
        if (!isSegmentByte(byte)) return error.InvalidSegmentByte;
    }
    for (reserved_segments) |reserved| {
        if (segmentsCollide(segment, reserved)) return error.ReservedSegment;
    }
    return;
}

fn isSegmentByte(byte: u8) bool {
    return switch (byte) {
        'a'...'z', 'A'...'Z', '0'...'9', '-', '_', '.' => true,
        else => false,
    };
}

pub fn segmentsCollide(a: []const u8, b: []const u8) bool {
    if (a.len != b.len) return false;
    for (a, b) |left, right| {
        if (std.ascii.toLower(left) != std.ascii.toLower(right)) return false;
    }
    return true;
}

pub const Path = struct {
    bytes: [max_path_bytes]u8 = @splat(0),
    len: u16 = 0,

    pub fn init(path: []const u8) PathError!Path {
        try validateAbsoluteDir(path);
        var value: Path = .{};
        @memcpy(value.bytes[0..path.len], path);
        value.len = @intCast(path.len);
        return value;
    }

    pub fn slice(self: *const Path) []const u8 {
        return self.bytes[0..self.len];
    }

    pub fn isEmpty(self: *const Path) bool {
        return self.len == 0;
    }

    pub fn eql(self: *const Path, other: *const Path) bool {
        return std.mem.eql(u8, self.slice(), other.slice());
    }

    pub fn eqlText(self: *const Path, text: []const u8) bool {
        return std.mem.eql(u8, self.slice(), text);
    }

    pub fn appendComponent(self: *Path, component: []const u8) (PathError || SegmentError)!void {
        try validateComponent(component);
        if (self.len == 0) return error.EmptyPath;
        if (self.len + 1 + component.len > max_path_bytes) return error.PathTooLong;
        self.bytes[self.len] = '/';
        self.len += 1;
        @memcpy(self.bytes[self.len..][0..component.len], component);
        self.len += @intCast(component.len);
    }

    pub fn appendAccountSegment(self: *Path, segment: []const u8) (PathError || SegmentError)!void {
        try validateAccountSegment(segment);
        try self.appendComponent(segment);
    }

    pub fn contains(self: *const Path, other: []const u8) bool {
        const root = self.slice();
        if (root.len == 0 or other.len < root.len) return false;
        if (!std.mem.eql(u8, other[0..root.len], root)) return false;
        if (other.len == root.len) return true;
        return other[root.len] == '/';
    }

    pub fn format(self: Path, writer: *std.Io.Writer) std.Io.Writer.Error!void {
        const value = self;
        try writer.writeAll(value.bytes[0..value.len]);
    }
};

pub const ProfilePaths = struct {
    profile_dir: Path,
    codex_home: Path,
    claude_config_dir: Path,

    pub fn homeFor(self: *const ProfilePaths, provider: domain.Provider) *const Path {
        return switch (provider) {
            .codex => &self.codex_home,
            .claude => &self.claude_config_dir,
        };
    }
};

pub const Layout = struct {
    root: Path,

    pub fn fromAppDataDir(app_data_dir: []const u8) PathError!Layout {
        const root = try Path.init(app_data_dir);
        const last = lastComponent(root.slice());
        if (!std.mem.eql(u8, last, app_data_directory_name)) return error.NotAppRoot;
        return .{ .root = root };
    }

    pub fn fromApplicationSupportDir(application_support_dir: []const u8) (PathError || SegmentError)!Layout {
        var root = try Path.init(application_support_dir);
        try root.appendComponent(app_data_directory_name);
        return .{ .root = root };
    }

    pub fn fromHomeDir(home_dir: []const u8) (PathError || SegmentError)!Layout {
        var root = try Path.init(home_dir);
        try root.appendComponent(library_component);
        try root.appendComponent(application_support_component);
        try root.appendComponent(app_data_directory_name);
        return .{ .root = root };
    }

    pub fn rootPath(self: *const Layout) []const u8 {
        return self.root.slice();
    }

    pub fn accountsDir(self: *const Layout) (PathError || SegmentError)!Path {
        var path = self.root;
        try path.appendComponent(accounts_component);
        return path;
    }

    pub fn profileDir(self: *const Layout, segment: []const u8) (PathError || SegmentError)!Path {
        var path = try self.accountsDir();
        try path.appendAccountSegment(segment);
        return path;
    }

    pub fn codexHome(self: *const Layout, segment: []const u8) (PathError || SegmentError)!Path {
        var path = try self.profileDir(segment);
        try path.appendComponent(codex_home_component);
        return path;
    }

    pub fn codexAuthFile(self: *const Layout, segment: []const u8) (PathError || SegmentError)!Path {
        var path = try self.codexHome(segment);
        try path.appendComponent(codex_auth_file_name);
        return path;
    }

    pub fn claudeConfigDir(self: *const Layout, segment: []const u8) (PathError || SegmentError)!Path {
        var path = try self.profileDir(segment);
        try path.appendComponent(claude_config_component);
        return path;
    }

    pub fn providerHome(self: *const Layout, provider: domain.Provider, segment: []const u8) (PathError || SegmentError)!Path {
        return switch (provider) {
            .codex => self.codexHome(segment),
            .claude => self.claudeConfigDir(segment),
        };
    }

    pub fn profilePaths(self: *const Layout, segment: []const u8) (PathError || SegmentError)!ProfilePaths {
        return .{
            .profile_dir = try self.profileDir(segment),
            .codex_home = try self.codexHome(segment),
            .claude_config_dir = try self.claudeConfigDir(segment),
        };
    }

    pub fn contains(self: *const Layout, path: []const u8) bool {
        return self.root.contains(path);
    }

    pub fn homeVariable(provider: domain.Provider) []const u8 {
        return switch (provider) {
            .codex => codex_home_var,
            .claude => claude_config_dir_var,
        };
    }

    pub fn isolationVariables(provider: domain.Provider) []const []const u8 {
        return switch (provider) {
            .codex => &codex_isolation_variables,
            .claude => &claude_isolation_variables,
        };
    }
};

pub const codex_home_var = transport.codex_home_var;
pub const claude_config_dir_var = "CLAUDE_CONFIG_DIR";

pub const claude_securestorage_config_dir_var = "CLAUDE_SECURESTORAGE_CONFIG_DIR";

pub const codex_isolation_variables = [_][]const u8{codex_home_var};
pub const claude_isolation_variables = [_][]const u8{ claude_config_dir_var, claude_securestorage_config_dir_var };

pub const max_isolation_variables: usize = @max(codex_isolation_variables.len, claude_isolation_variables.len);

comptime {
    for (std.enums.values(domain.Provider)) |provider| {
        const variables = Layout.isolationVariables(provider);
        if (variables.len == 0) @compileError("every provider needs an isolation variable");
        if (!std.mem.eql(u8, variables[0], Layout.homeVariable(provider))) {
            @compileError("the primary isolation variable must be the provider home variable");
        }
        for (variables) |name| {
            if (transport.isInheritable(name)) @compileError("isolation variable must never be inherited: " ++ name);
            if (!transport.isScrubbed(name)) @compileError("isolation variable must be scrubbed: " ++ name);
        }
    }
}

fn lastComponent(path: []const u8) []const u8 {
    const index = std.mem.lastIndexOfScalar(u8, path, '/') orelse return path;
    return path[index + 1 ..];
}

pub const DocumentKind = enum { registry, snapshots, attempts, app_settings, proxy_settings, proxy_status };

pub fn documentFileName(kind: DocumentKind) []const u8 {
    return switch (kind) {
        .registry => registry_file_name,
        .snapshots => snapshots_file_name,
        .attempts => attempts_file_name,
        .app_settings => app_settings_file_name,
        .proxy_settings => proxy_settings_file_name,
        .proxy_status => proxy_status_file_name,
    };
}

pub fn documentTempFileName(kind: DocumentKind) []const u8 {
    return switch (kind) {
        .registry => registry_temp_file_name,
        .snapshots => snapshots_temp_file_name,
        .attempts => attempts_temp_file_name,
        .app_settings => app_settings_temp_file_name,
        .proxy_settings => proxy_settings_temp_file_name,
        .proxy_status => proxy_status_temp_file_name,
    };
}

comptime {
    for (std.enums.values(DocumentKind)) |kind| {
        if (std.mem.eql(u8, documentFileName(kind), documentTempFileName(kind))) {
            @compileError("document temp name must differ from its final name");
        }
    }
}
