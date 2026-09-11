const std = @import("std");

const coordinator = @import("coordinator.zig");
const login_runtime = @import("login_runtime.zig");
const runtime_paths = @import("runtime_paths.zig");
const transport = @import("process_jsonl.zig");
const codex = @import("providers/codex.zig");

pub const generated_hex_digits: usize = 16;

pub const idempotency_key_prefix = "reset-";
pub const max_generated_key_bytes: usize = idempotency_key_prefix.len + 32;

comptime {
    if (max_generated_key_bytes > codex.max_idempotency_key_bytes) {
        @compileError("a generated key must fit the protocol's idempotency-key bound");
    }
}

pub const max_executable_bytes: usize = runtime_paths.max_path_bytes;

pub const private_dir_permissions: std.Io.File.Permissions = @enumFromInt(0o700);

pub const ExecutablePath = struct {
    bytes: [max_executable_bytes]u8 = @splat(0),
    len: u16 = 0,

    pub fn slice(self: *const ExecutablePath) []const u8 {
        return self.bytes[0..self.len];
    }

    pub fn isEmpty(self: *const ExecutablePath) bool {
        return self.len == 0;
    }
};

pub fn resolveExecutable(
    io: std.Io,
    path_variable: []const u8,
    name: []const u8,
    out: *ExecutablePath,
) bool {
    out.* = .{};
    if (name.len == 0) return false;
    var entries = std.mem.splitScalar(u8, path_variable, ':');
    while (entries.next()) |entry| {
        if (entry.len == 0 or entry[0] != '/') continue;
        if (resolveExecutableInDirectory(io, entry, name, out)) return true;
    }
    return false;
}

pub fn resolveProviderExecutable(
    io: std.Io,
    path_variable: []const u8,
    home: []const u8,
    name: []const u8,
    out: *ExecutablePath,
) bool {
    if (resolveExecutable(io, path_variable, name, out)) return true;
    if (name.len == 0) return false;
    runtime_paths.validateAbsoluteDir(home) catch return false;

    const home_relative_dirs = [_][]const u8{
        ".local/bin",
        ".bun/bin",
        "Library/pnpm",
        "bin",
    };
    var directory_buffer: [max_executable_bytes]u8 = undefined;
    for (home_relative_dirs) |relative| {
        const directory = std.fmt.bufPrint(&directory_buffer, "{s}/{s}", .{ home, relative }) catch continue;
        if (resolveExecutableInDirectory(io, directory, name, out)) return true;
    }

    const system_dirs = [_][]const u8{ "/opt/homebrew/bin", "/usr/local/bin" };
    for (system_dirs) |directory| {
        if (resolveExecutableInDirectory(io, directory, name, out)) return true;
    }
    out.* = .{};
    return false;
}

fn resolveExecutableInDirectory(
    io: std.Io,
    directory: []const u8,
    name: []const u8,
    out: *ExecutablePath,
) bool {
    if (directory.len == 0 or directory[0] != '/') return false;
    if (directory.len + 1 + name.len > max_executable_bytes) return false;
    var candidate: [max_executable_bytes]u8 = undefined;
    var length = directory.len;
    @memcpy(candidate[0..length], directory);

    while (length > 1 and candidate[length - 1] == '/') length -= 1;
    candidate[length] = '/';
    length += 1;
    @memcpy(candidate[length..][0..name.len], name);
    length += name.len;

    const resolved = candidate[0..length];
    runtime_paths.validateAbsoluteDir(resolved) catch return false;
    std.Io.Dir.cwd().access(io, resolved, .{ .execute = true }) catch return false;
    @memcpy(out.bytes[0..length], resolved);
    out.len = @intCast(length);
    return true;
}

pub const DirectoryError = error{ Unsupported, Denied, Io };

pub const Directories = struct {
    context: *anyopaque,
    vtable: *const VTable,

    pub const VTable = struct {
        ensure: *const fn (context: *anyopaque, path: []const u8) DirectoryError!void,
        remove: *const fn (context: *anyopaque, path: []const u8) DirectoryError!void,
    };

    pub fn ensure(self: Directories, path: []const u8) DirectoryError!void {
        return self.vtable.ensure(self.context, path);
    }

    pub fn remove(self: Directories, path: []const u8) DirectoryError!void {
        return self.vtable.remove(self.context, path);
    }
};

var unwired_directories_context: u8 = 0;
const unwired_directories_vtable: Directories.VTable = .{
    .ensure = unwiredEnsure,
    .remove = unwiredRemove,
};

fn unwiredEnsure(_: *anyopaque, _: []const u8) DirectoryError!void {
    return error.Unsupported;
}

fn unwiredRemove(_: *anyopaque, _: []const u8) DirectoryError!void {
    return error.Unsupported;
}

pub fn unwiredDirectories() Directories {
    return .{ .context = &unwired_directories_context, .vtable = &unwired_directories_vtable };
}

pub const FileDirectories = struct {
    io: std.Io,
    layout: runtime_paths.Layout,

    const vtable: Directories.VTable = .{ .ensure = ensure, .remove = remove };

    pub fn directories(self: *FileDirectories) Directories {
        return .{ .context = self, .vtable = &vtable };
    }

    fn ensure(context: *anyopaque, path: []const u8) DirectoryError!void {
        const self: *FileDirectories = @ptrCast(@alignCast(context));
        runtime_paths.validateAbsoluteDir(path) catch return error.Denied;
        if (!self.layout.contains(path)) return error.Denied;
        _ = std.Io.Dir.cwd().createDirPathStatus(self.io, path, private_dir_permissions) catch |err|
            return switch (err) {
                error.AccessDenied, error.PermissionDenied => error.Denied,
                else => error.Io,
            };
    }

    fn remove(context: *anyopaque, path: []const u8) DirectoryError!void {
        const self: *FileDirectories = @ptrCast(@alignCast(context));
        runtime_paths.validateAbsoluteDir(path) catch return error.Denied;

        if (!self.layout.contains(path)) return error.Denied;
        if (std.mem.eql(u8, path, self.layout.rootPath())) return error.Denied;
        std.Io.Dir.cwd().deleteTree(self.io, path) catch |err| return switch (err) {
            error.AccessDenied, error.PermissionDenied => error.Denied,
            else => error.Io,
        };
    }
};

pub const KeySource = struct {
    context: *anyopaque,
    vtable: *const VTable,

    pub const VTable = struct {
        next: *const fn (context: *anyopaque, out: []u8) usize,
    };

    pub fn next(self: KeySource, out: []u8) []const u8 {
        return out[0..self.vtable.next(self.context, out)];
    }
};

var unwired_keys_context: u8 = 0;
const unwired_keys_vtable: KeySource.VTable = .{ .next = unwiredNextKey };

fn unwiredNextKey(_: *anyopaque, _: []u8) usize {
    return 0;
}

pub fn unwiredKeySource() KeySource {
    return .{ .context = &unwired_keys_context, .vtable = &unwired_keys_vtable };
}

pub const RandomKeySource = struct {
    io: std.Io,

    const vtable: KeySource.VTable = .{ .next = next };

    pub fn source(self: *RandomKeySource) KeySource {
        return .{ .context = self, .vtable = &vtable };
    }

    fn next(context: *anyopaque, out: []u8) usize {
        const self: *RandomKeySource = @ptrCast(@alignCast(context));
        const digits = @min(out.len, generated_hex_digits * 2);
        if (digits == 0) return 0;
        var entropy: [generated_hex_digits]u8 = undefined;
        self.io.random(&entropy);
        return writeHex(out[0..digits], &entropy);
    }
};

fn writeHex(out: []u8, bytes: []const u8) usize {
    const table = "0123456789abcdef";
    var written: usize = 0;
    for (bytes) |byte| {
        if (written + 2 > out.len) break;
        out[written] = table[byte >> 4];
        out[written + 1] = table[byte & 0x0f];
        written += 2;
    }
    return written;
}

pub const LaunchError = error{
    Unsupported,

    InvalidHome,

    EnvironmentFailed,
    SpawnFailed,
};

pub const CodexChannel = struct {
    frames: [transport.max_frame_bytes]u8 = @splat(0),
    connection: transport.Connection = undefined,
    lifecycle: coordinator.ChildLifecycle = coordinator.noChildLifecycle(),
    bound: bool = false,

    child: transport.ChildTransport = undefined,
    child_active: bool = false,
    env: ?std.process.Environ.Map = null,

    const child_vtable: coordinator.ChildLifecycle.VTable = .{ .close = closeChild };

    pub fn bind(self: *CodexChannel, stream: transport.Stream, lifecycle: coordinator.ChildLifecycle) void {
        self.connection = .init(&self.frames, stream);
        self.lifecycle = lifecycle;
        self.bound = true;
    }

    pub fn ownedLifecycle(self: *CodexChannel) coordinator.ChildLifecycle {
        return .{ .context = self, .vtable = &child_vtable };
    }

    pub fn isBound(self: *const CodexChannel) bool {
        return self.bound;
    }

    pub fn close(self: *CodexChannel) void {
        if (!self.bound) return;
        self.bound = false;
        const lifecycle = self.lifecycle;
        self.lifecycle = coordinator.noChildLifecycle();
        lifecycle.close();
    }

    fn closeChild(context: *anyopaque) void {
        const self: *CodexChannel = @ptrCast(@alignCast(context));
        if (self.child_active) {
            self.child.close();
            self.child_active = false;
        }
        if (self.env) |*map| {
            map.deinit();
            self.env = null;
        }
    }
};

pub const CodexLauncher = struct {
    context: *anyopaque,
    vtable: *const VTable,

    pub const VTable = struct {
        open: *const fn (context: *anyopaque, home: []const u8, channel: *CodexChannel) LaunchError!void,
    };

    pub fn open(self: CodexLauncher, home: []const u8, channel: *CodexChannel) LaunchError!void {
        return self.vtable.open(self.context, home, channel);
    }
};

var unwired_codex_context: u8 = 0;
const unwired_codex_vtable: CodexLauncher.VTable = .{ .open = unwiredCodexOpen };

fn unwiredCodexOpen(_: *anyopaque, _: []const u8, _: *CodexChannel) LaunchError!void {
    return error.Unsupported;
}

pub fn unwiredCodexLauncher() CodexLauncher {
    return .{ .context = &unwired_codex_context, .vtable = &unwired_codex_vtable };
}

pub const ChildCodexLauncher = struct {
    io: std.Io,
    allocator: std.mem.Allocator,

    executable: []const u8,

    helpers_directory: []const u8 = "",
    parent_env: transport.ParentEnv,

    const vtable: CodexLauncher.VTable = .{ .open = open };

    pub fn launcher(self: *ChildCodexLauncher) CodexLauncher {
        return .{ .context = self, .vtable = &vtable };
    }

    fn open(context: *anyopaque, home: []const u8, channel: *CodexChannel) LaunchError!void {
        const self: *ChildCodexLauncher = @ptrCast(@alignCast(context));
        if (self.executable.len == 0) return error.Unsupported;
        transport.validateCodexHome(home) catch return error.InvalidHome;

        var env: std.process.Environ.Map = .init(self.allocator);
        errdefer env.deinit();
        transport.buildChildEnv(&env, self.parent_env, home) catch return error.EnvironmentFailed;
        transport.prepareProviderChildEnvironment(&env, self.executable, self.helpers_directory) catch
            return error.EnvironmentFailed;

        channel.env = env;
        errdefer {
            if (channel.env) |*map| {
                map.deinit();
                channel.env = null;
            }
        }

        const argv = codex.appServerArgv(self.executable);
        channel.child = transport.ChildTransport.spawn(self.io, .{
            .argv = &argv,
            .environ = &channel.env.?,
        }) catch return error.SpawnFailed;
        channel.child_active = true;
        channel.bind(channel.child.stream(), channel.ownedLifecycle());
    }
};

pub const LoginChannel = struct {
    child: login_runtime.ChildProcess = undefined,
    handle: login_runtime.Child = login_runtime.unwiredChild(),
    env: ?std.process.Environ.Map = null,
    bound: bool = false,

    pub fn bind(self: *LoginChannel, handle: login_runtime.Child) void {
        self.handle = handle;
        self.bound = true;
    }

    pub fn isBound(self: *const LoginChannel) bool {
        return self.bound;
    }

    pub fn release(self: *LoginChannel) void {
        if (!self.bound) return;
        self.bound = false;
        self.handle = login_runtime.unwiredChild();
        if (self.env) |*map| {
            map.deinit();
            self.env = null;
        }
    }
};

pub const LoginLauncher = struct {
    context: *anyopaque,
    vtable: *const VTable,

    pub const VTable = struct {
        open: *const fn (
            context: *anyopaque,
            spec: *const coordinator.LoginSpec,
            channel: *LoginChannel,
        ) LaunchError!void,
    };

    pub fn open(
        self: LoginLauncher,
        spec: *const coordinator.LoginSpec,
        channel: *LoginChannel,
    ) LaunchError!void {
        return self.vtable.open(self.context, spec, channel);
    }
};

var unwired_login_context: u8 = 0;
const unwired_login_vtable: LoginLauncher.VTable = .{ .open = unwiredLoginOpen };

fn unwiredLoginOpen(_: *anyopaque, _: *const coordinator.LoginSpec, _: *LoginChannel) LaunchError!void {
    return error.Unsupported;
}

pub fn unwiredLoginLauncher() LoginLauncher {
    return .{ .context = &unwired_login_context, .vtable = &unwired_login_vtable };
}

pub const ProcessLoginLauncher = struct {
    io: std.Io,
    allocator: std.mem.Allocator,

    helpers_directory: []const u8 = "",

    const vtable: LoginLauncher.VTable = .{ .open = open };

    pub fn launcher(self: *ProcessLoginLauncher) LoginLauncher {
        return .{ .context = self, .vtable = &vtable };
    }

    fn open(
        context: *anyopaque,
        spec: *const coordinator.LoginSpec,
        channel: *LoginChannel,
    ) LaunchError!void {
        const self: *ProcessLoginLauncher = @ptrCast(@alignCast(context));
        if (spec.argv_count == 0) return error.Unsupported;

        if (!spec.isolationIsConsistent()) return error.InvalidHome;

        var env: std.process.Environ.Map = .init(self.allocator);
        errdefer env.deinit();
        spec.env.writeEnvMap(&env) catch return error.EnvironmentFailed;
        transport.prepareProviderChildEnvironment(&env, spec.executable, self.helpers_directory) catch
            return error.EnvironmentFailed;

        channel.env = env;
        errdefer {
            if (channel.env) |*map| {
                map.deinit();
                channel.env = null;
            }
        }

        channel.child = login_runtime.ChildProcess.spawn(self.io, .{
            .argv = spec.argv(),
            .environ = &channel.env.?,
        }) catch return error.SpawnFailed;
        channel.bind(channel.child.handle());
    }
};
