const std = @import("std");
const login_runtime = @import("login_runtime.zig");
const runtime_paths = @import("runtime_paths.zig");
const transport = @import("process_jsonl.zig");

pub const default_timeout_ms: u32 = 10_000;
pub const default_max_output_bytes: usize = 64 * 1024;
pub const max_argv: usize = 7;

pub const Outcome = enum {
    success,
    spawn_failed,
    nonzero_exit,
    timeout,
    canceled,
    io,
    output_too_large,
    invalid_configuration,
};

pub const Request = struct {
    node_path: []const u8,
    cli_path: []const u8,
    app_root: []const u8,
    config_path: []const u8,
    parent_env: transport.ParentEnv = .{ .pairs = &.{} },
    timeout_ms: u32 = default_timeout_ms,
    max_output_bytes: usize = default_max_output_bytes,
};

pub const Runner = struct {
    context: *anyopaque,
    vtable: *const VTable,

    pub const VTable = struct {
        run: *const fn (*anyopaque, Request) Outcome,
    };

    pub fn run(self: Runner, request: Request) Outcome {
        return self.vtable.run(self.context, request);
    }
};

var unwired_context: u8 = 0;
const unwired_vtable: Runner.VTable = .{ .run = unwiredRun };

fn unwiredRun(_: *anyopaque, _: Request) Outcome {
    return .spawn_failed;
}

pub fn unwiredRunner() Runner {
    return .{ .context = &unwired_context, .vtable = &unwired_vtable };
}

pub const InvocationError = error{
    InvalidNodeExecutable,
    InvalidExecutable,
    InvalidAppRoot,
    InvalidConfigPath,
    EnvironmentTooLarge,
    ValueTooLarge,
};

pub const Invocation = struct {
    node_path: runtime_paths.Path = .{},
    cli_path: runtime_paths.Path = .{},
    app_root: runtime_paths.Path = .{},
    config_path: runtime_paths.Path = .{},
    argv_storage: [max_argv][]const u8 = @splat(""),
    env: login_runtime.EnvSpec = .{},
    env_value_storage: [3][transport.max_env_value_bytes]u8 = @splat(@splat(0)),
    env_value_lengths: [3]u16 = @splat(0),

    pub fn argv(self: *const Invocation) []const []const u8 {
        return &self.argv_storage;
    }

    pub fn rebind(self: *Invocation) void {
        self.argv_storage = .{
            self.node_path.slice(),
            self.cli_path.slice(),
            "import-codexmulti",
            "--store",
            self.app_root.slice(),
            "--out",
            self.config_path.slice(),
        };
        for (self.env.vars[0..self.env.count], 0..) |*variable, index| {
            variable.value = self.env_value_storage[index][0..self.env_value_lengths[index]];
        }
    }
};

pub const InvocationOptions = struct {
    node_path: []const u8,
    cli_path: []const u8,
    app_root: []const u8,
    config_path: []const u8,
    parent_env: transport.ParentEnv,
};

const inherited_names = [_][]const u8{ "PATH", "HOME", "TMPDIR" };

pub fn writeInvocation(out: *Invocation, options: InvocationOptions) InvocationError!void {
    out.* = .{};
    out.node_path = runtime_paths.Path.init(options.node_path) catch return error.InvalidNodeExecutable;
    out.cli_path = runtime_paths.Path.init(options.cli_path) catch return error.InvalidExecutable;
    out.app_root = runtime_paths.Path.init(options.app_root) catch return error.InvalidAppRoot;
    out.config_path = runtime_paths.Path.init(options.config_path) catch return error.InvalidConfigPath;

    for (inherited_names) |name| {
        const value = parentValue(options.parent_env, name) orelse continue;
        if (value.len > transport.max_env_value_bytes) return error.ValueTooLarge;
        if (out.env.count == out.env.vars.len) return error.EnvironmentTooLarge;
        const slot = out.env.count;
        @memcpy(out.env_value_storage[slot][0..value.len], value);
        out.env_value_lengths[slot] = @intCast(value.len);
        out.env.vars[out.env.count] = .{
            .name = name,
            .value = out.env_value_storage[slot][0..value.len],
        };
        out.env.count += 1;
    }
    out.rebind();
}

fn parentValue(parent: transport.ParentEnv, name: []const u8) ?[]const u8 {
    return switch (parent) {
        .pairs => |pairs| blk: {
            for (pairs) |pair| if (std.mem.eql(u8, pair.name, name)) break :blk pair.value;
            break :blk null;
        },
        .map => |map| map.get(name),
    };
}

pub fn expandConfigPath(config_path: []const u8, home: []const u8) error{InvalidConfigPath}!runtime_paths.Path {
    if (std.mem.startsWith(u8, config_path, "~/")) {
        const canonical_home = runtime_paths.Path.init(home) catch return error.InvalidConfigPath;
        var buffer: [runtime_paths.max_path_bytes]u8 = undefined;
        const value = std.fmt.bufPrint(&buffer, "{s}/{s}", .{ canonical_home.slice(), config_path[2..] }) catch
            return error.InvalidConfigPath;
        return runtime_paths.Path.init(value) catch return error.InvalidConfigPath;
    }
    return runtime_paths.Path.init(config_path) catch return error.InvalidConfigPath;
}

pub const NodeSearch = struct {
    configured: ?[]const u8 = null,
    home: []const u8,
    path_variable: []const u8 = "",
    user_dirs: []const []const u8 = &default_user_dirs,
    system_dirs: []const []const u8 = &default_system_dirs,
};

pub const default_user_dirs = [_][]const u8{".local/bin"};
pub const default_system_dirs = [_][]const u8{ "/opt/homebrew/bin", "/usr/local/bin" };
pub const node_binary_name = "node";

pub fn resolveNodeExecutable(io: std.Io, search: NodeSearch, out: *runtime_paths.Path) bool {
    out.* = .{};
    if (search.configured) |configured| {
        return acceptExecutable(io, configured, out);
    }
    var candidate: [runtime_paths.max_path_bytes]u8 = undefined;
    if (runtime_paths.validateAbsoluteDir(search.home)) |_| {
        for (search.user_dirs) |relative| {
            const joined = std.fmt.bufPrint(&candidate, "{s}/{s}/{s}", .{ search.home, relative, node_binary_name }) catch continue;
            if (acceptExecutable(io, joined, out)) return true;
        }
    } else |_| {}
    for (search.system_dirs) |directory| {
        const joined = std.fmt.bufPrint(&candidate, "{s}/{s}", .{ directory, node_binary_name }) catch continue;
        if (acceptExecutable(io, joined, out)) return true;
    }
    var entries = std.mem.splitScalar(u8, search.path_variable, ':');
    while (entries.next()) |entry| {
        if (entry.len == 0 or entry[0] != '/') continue;
        var trimmed = entry;
        while (trimmed.len > 1 and trimmed[trimmed.len - 1] == '/') trimmed = trimmed[0 .. trimmed.len - 1];
        const joined = std.fmt.bufPrint(&candidate, "{s}/{s}", .{ trimmed, node_binary_name }) catch continue;
        if (acceptExecutable(io, joined, out)) return true;
    }
    out.* = .{};
    return false;
}

fn acceptExecutable(io: std.Io, path: []const u8, out: *runtime_paths.Path) bool {
    const canonical = runtime_paths.Path.init(path) catch return false;
    const cwd = std.Io.Dir.cwd();
    const stat = cwd.statFile(io, canonical.slice(), .{ .follow_symlinks = true }) catch return false;
    if (stat.kind != .file) return false;
    cwd.access(io, canonical.slice(), .{ .execute = true }) catch return false;
    out.* = canonical;
    return true;
}

pub const NodeResolver = struct {
    context: *anyopaque,
    vtable: *const VTable,

    pub const VTable = struct {
        resolve: *const fn (*anyopaque, NodeSearch, *runtime_paths.Path) bool,
    };

    pub fn resolve(self: NodeResolver, search: NodeSearch, out: *runtime_paths.Path) bool {
        return self.vtable.resolve(self.context, search, out);
    }
};

var unwired_resolver_context: u8 = 0;
const unwired_resolver_vtable: NodeResolver.VTable = .{ .resolve = unwiredResolve };

fn unwiredResolve(_: *anyopaque, _: NodeSearch, out: *runtime_paths.Path) bool {
    out.* = .{};
    return false;
}

pub fn unwiredNodeResolver() NodeResolver {
    return .{ .context = &unwired_resolver_context, .vtable = &unwired_resolver_vtable };
}

pub const FilesystemNodeResolver = struct {
    io: std.Io,

    const vtable: NodeResolver.VTable = .{ .resolve = resolve };

    pub fn init(io: std.Io) FilesystemNodeResolver {
        return .{ .io = io };
    }

    pub fn resolver(self: *FilesystemNodeResolver) NodeResolver {
        return .{ .context = self, .vtable = &vtable };
    }

    fn resolve(context: *anyopaque, search: NodeSearch, out: *runtime_paths.Path) bool {
        const self: *FilesystemNodeResolver = @ptrCast(@alignCast(context));
        return resolveNodeExecutable(self.io, search, out);
    }
};

pub const RunOptions = struct {
    timeout_ms: u32 = default_timeout_ms,
    max_output_bytes: usize = default_max_output_bytes,
};

pub fn runChild(child: login_runtime.Child, options: RunOptions) Outcome {
    if (options.timeout_ms == 0 or options.max_output_bytes == 0) {
        child.close();
        return .invalid_configuration;
    }
    child.arm(options.timeout_ms);
    var scratch: [1024]u8 = undefined;
    var total: usize = 0;
    var empty_reads: usize = 0;
    var outcome: Outcome = .io;
    while (true) {
        const count = child.read(&scratch) catch |err| {
            outcome = switch (err) {
                error.EndOfOutput => .success,
                error.Timeout => .timeout,
                error.Canceled => .canceled,
                error.Io, error.Unsupported => .io,
            };
            break;
        };
        if (count == 0) {
            empty_reads += 1;
            if (empty_reads > transport.max_empty_reads) {
                outcome = .io;
                break;
            }
            continue;
        }
        empty_reads = 0;
        if (count > options.max_output_bytes -| total) {
            outcome = .output_too_large;
            break;
        }
        total += count;
    }
    child.close();
    if (outcome == .success and child.exit() != .success) return .nonzero_exit;
    return outcome;
}

pub const ProcessRunner = struct {
    io: std.Io,
    allocator: std.mem.Allocator,

    const vtable: Runner.VTable = .{ .run = run };

    pub fn init(io: std.Io, allocator: std.mem.Allocator) ProcessRunner {
        return .{ .io = io, .allocator = allocator };
    }

    pub fn runner(self: *ProcessRunner) Runner {
        return .{ .context = self, .vtable = &vtable };
    }

    fn run(context: *anyopaque, request: Request) Outcome {
        const self: *ProcessRunner = @ptrCast(@alignCast(context));
        var invocation: Invocation = .{};
        writeInvocation(&invocation, .{
            .node_path = request.node_path,
            .cli_path = request.cli_path,
            .app_root = request.app_root,
            .config_path = request.config_path,
            .parent_env = request.parent_env,
        }) catch return .invalid_configuration;
        invocation.rebind();

        var node: runtime_paths.Path = .{};
        if (!acceptExecutable(self.io, invocation.node_path.slice(), &node)) return .spawn_failed;
        const cwd = std.Io.Dir.cwd();
        const stat = cwd.statFile(self.io, invocation.cli_path.slice(), .{ .follow_symlinks = false }) catch
            return .spawn_failed;
        if (stat.kind != .file) return .spawn_failed;
        cwd.access(self.io, invocation.cli_path.slice(), .{ .read = true }) catch return .spawn_failed;

        var environ = std.process.Environ.Map.init(self.allocator);
        defer environ.deinit();
        invocation.env.writeEnvMap(&environ) catch return .invalid_configuration;
        var child = login_runtime.ChildProcess.spawn(self.io, .{
            .argv = invocation.argv(),
            .environ = &environ,
        }) catch return .spawn_failed;

        if (child.child.stdin) |stdin| {
            stdin.close(self.io);
            child.child.stdin = null;
        }
        return runChild(child.handle(), .{
            .timeout_ms = request.timeout_ms,
            .max_output_bytes = request.max_output_bytes,
        });
    }
};
