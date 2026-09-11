const std = @import("std");

pub const launchctl_path = "/bin/launchctl";
pub const max_output_bytes: usize = 64 * 1024;
pub const default_timeout_ms: u32 = 5_000;

pub const PrintExpectation = struct {
    domain_target: []const u8,

    program_arguments: []const []const u8 = &.{},
};

pub const Command = union(enum) {
    print: PrintExpectation,
    bootstrap: struct { domain: []const u8, plist_path: []const u8 },
    bootout: struct { domain_target: []const u8 },
    kickstart: struct { domain_target: []const u8 },
};

pub const Status = enum {
    loaded,
    loaded_arguments_mismatch,
    not_loaded,
    success,
    failed,
    timeout,
    canceled,
    output_too_large,
    invalid_request,
};

pub const Result = struct {
    status: Status,
    exit_code: ?u8 = null,

    pub fn succeeded(self: Result) bool {
        return self.status == .success or self.status == .loaded;
    }
};

pub const Runner = struct {
    context: *anyopaque,
    vtable: *const VTable,

    pub const VTable = struct {
        run: *const fn (*anyopaque, Command) Result,
    };

    pub fn run(self: Runner, command: Command) Result {
        return self.vtable.run(self.context, command);
    }
};

var unwired_context: u8 = 0;
const unwired_vtable: Runner.VTable = .{ .run = unwiredRun };

fn unwiredRun(_: *anyopaque, _: Command) Result {
    return .{ .status = .failed };
}

pub fn unwiredRunner() Runner {
    return .{ .context = &unwired_context, .vtable = &unwired_vtable };
}

pub const Argv = struct {
    values: [4][]const u8 = @splat(""),
    len: usize = 0,

    pub fn slice(self: *const Argv) []const []const u8 {
        return self.values[0..self.len];
    }
};

pub fn writeArgv(out: *Argv, command: Command) bool {
    out.* = .{};
    switch (command) {
        .print => |request| {
            if (!validTarget(request.domain_target)) return false;
            out.values = .{ launchctl_path, "print", request.domain_target, "" };
            out.len = 3;
        },
        .bootstrap => |request| {
            if (!validDomain(request.domain) or !validAbsolutePath(request.plist_path)) return false;
            out.values = .{ launchctl_path, "bootstrap", request.domain, request.plist_path };
            out.len = 4;
        },
        .bootout => |request| {
            if (!validTarget(request.domain_target)) return false;
            out.values = .{ launchctl_path, "bootout", request.domain_target, "" };
            out.len = 3;
        },
        .kickstart => |request| {
            if (!validTarget(request.domain_target)) return false;
            out.values = .{ launchctl_path, "kickstart", request.domain_target, "" };
            out.len = 3;
        },
    }
    return true;
}

fn validDomain(value: []const u8) bool {
    if (!std.mem.startsWith(u8, value, "gui/") or value.len <= 4) return false;
    for (value[4..]) |byte| if (byte < '0' or byte > '9') return false;
    return true;
}

fn validTarget(value: []const u8) bool {
    const slash = std.mem.indexOfScalarPos(u8, value, 4, '/') orelse return false;
    if (!validDomain(value[0..slash])) return false;
    const label = value[slash + 1 ..];
    if (label.len == 0 or label.len > 128) return false;
    for (label) |byte| switch (byte) {
        'a'...'z', 'A'...'Z', '0'...'9', '.', '-', '_' => {},
        else => return false,
    };
    return true;
}

fn validAbsolutePath(value: []const u8) bool {
    if (value.len == 0 or value[0] != '/' or value[value.len - 1] == '/') return false;
    for (value) |byte| if (byte == 0 or byte == '\n' or byte == '\r') return false;
    return std.mem.indexOf(u8, value, "/../") == null and
        !std.mem.endsWith(u8, value, "/..") and
        std.mem.indexOf(u8, value, "/./") == null;
}

pub const ProcessRunner = struct {
    io: std.Io,
    allocator: std.mem.Allocator,
    timeout_ms: u32 = default_timeout_ms,

    const vtable: Runner.VTable = .{ .run = run };

    pub fn init(io: std.Io, allocator: std.mem.Allocator) ProcessRunner {
        return .{ .io = io, .allocator = allocator };
    }

    pub fn runner(self: *ProcessRunner) Runner {
        return .{ .context = self, .vtable = &vtable };
    }

    fn run(context: *anyopaque, command: Command) Result {
        const self: *ProcessRunner = @ptrCast(@alignCast(context));
        if (self.timeout_ms == 0) return .{ .status = .invalid_request };
        var argv: Argv = .{};
        if (!writeArgv(&argv, command)) return .{ .status = .invalid_request };

        const child = std.process.run(self.allocator, self.io, .{
            .argv = argv.slice(),
            .stdout_limit = .limited(max_output_bytes),
            .stderr_limit = .limited(max_output_bytes),
            .timeout = .{ .duration = .{ .raw = .fromMilliseconds(self.timeout_ms), .clock = .awake } },
        }) catch |err| return .{ .status = switch (err) {
            error.StreamTooLong => .output_too_large,
            error.Timeout => .timeout,
            error.Canceled => .canceled,
            else => .failed,
        } };
        defer self.allocator.free(child.stdout);
        defer self.allocator.free(child.stderr);

        const exit_code: ?u8 = switch (child.term) {
            .exited => |code| @intCast(@min(code, 255)),
            else => null,
        };
        const successful = if (exit_code) |code| code == 0 else false;
        return switch (command) {
            .bootstrap, .bootout, .kickstart => .{
                .status = if (successful) .success else .failed,
                .exit_code = exit_code,
            },
            .print => |request| classifyPrint(successful, exit_code, child.stdout, child.stderr, request.program_arguments),
        };
    }
};

fn classifyPrint(
    successful: bool,
    exit_code: ?u8,
    stdout: []const u8,
    stderr: []const u8,
    expected_arguments: []const []const u8,
) Result {
    if (!successful) {
        const absent = std.mem.indexOf(u8, stderr, "Could not find service") != null or
            std.mem.indexOf(u8, stdout, "Could not find service") != null or
            std.mem.indexOf(u8, stderr, "service not found") != null;
        return .{ .status = if (absent) .not_loaded else .failed, .exit_code = exit_code };
    }
    if (expected_arguments.len == 0) return .{ .status = .loaded, .exit_code = exit_code };
    return .{
        .status = if (containsArgumentsInOrder(stdout, expected_arguments)) .loaded else .loaded_arguments_mismatch,
        .exit_code = exit_code,
    };
}

fn containsArgumentsInOrder(output: []const u8, expected: []const []const u8) bool {
    var offset: usize = 0;
    for (expected) |argument| {
        if (argument.len == 0) return false;
        const relative = std.mem.indexOfPos(u8, output, offset, argument) orelse return false;
        offset = relative + argument.len;
    }
    return true;
}
