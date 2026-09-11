const builtin = @import("builtin");
const std = @import("std");
const domain = @import("domain.zig");
const runtime_paths = @import("runtime_paths.zig");
const transport = @import("process_jsonl.zig");

const posix = std.posix;

pub const max_login_argv: usize = 2;
pub const max_child_env_vars: usize = transport.max_child_env_vars;

pub const max_line_bytes: usize = 512;

pub const min_scan_bytes: usize = 2 * max_line_bytes;

pub const default_timeout_ms: u32 = 5 * 60 * 1000;
pub const min_timeout_ms: u32 = 1_000;
pub const max_timeout_ms: u32 = 15 * 60 * 1000;

pub const default_max_output_bytes: usize = 64 * 1024;
pub const max_lines_scanned: usize = 2048;

pub const max_empty_reads: usize = 8;

pub const default_grace_ms: u32 = 500;

pub const default_poll_interval_ms: u32 = 25;
pub const max_grace_polls: usize = 64;

pub const max_verification_url_bytes: usize = 128;
pub const max_verification_code_bytes: usize = 24;

pub const max_url_alphanumeric_run: usize = 24;

pub const public_code_login_unsupported = "login-unsupported";
pub const public_code_login_spawn_failed = "login-spawn-failed";
pub const public_code_login_timeout = "login-timeout";
pub const public_code_login_canceled = "login-canceled";
pub const public_code_login_io = "login-io";
pub const public_code_login_rejected = "login-rejected";
pub const public_code_login_noisy = "login-noisy";

pub const public_codes = [_][]const u8{
    public_code_login_unsupported,
    public_code_login_spawn_failed,
    public_code_login_timeout,
    public_code_login_canceled,
    public_code_login_io,
    public_code_login_rejected,
    public_code_login_noisy,
};

pub fn isPublicCode(code: []const u8) bool {
    for (public_codes) |known| {
        if (std.mem.eql(u8, code, known)) return true;
    }
    return false;
}

pub const EnvError = error{
    EnvironmentTooLarge,
    ValueTooLarge,
    DuplicateVariable,

    ScrubbedVariable,
};

pub const EnvSpec = struct {
    vars: [max_child_env_vars]transport.EnvVar = @splat(.{ .name = "", .value = "" }),
    count: usize = 0,

    pub fn slice(self: *const EnvSpec) []const transport.EnvVar {
        return self.vars[0..self.count];
    }

    pub fn find(self: *const EnvSpec, name: []const u8) ?[]const u8 {
        for (self.slice()) |variable| {
            if (std.mem.eql(u8, variable.name, name)) return variable.value;
        }
        return null;
    }

    pub fn contains(self: *const EnvSpec, name: []const u8) bool {
        return self.find(name) != null;
    }

    pub fn holdsOnlyAllowedVariables(self: *const EnvSpec, home_var: []const u8) bool {
        return self.holdsOnlyAllowedVariablesFor(&.{home_var});
    }

    pub fn holdsOnlyAllowedVariablesFor(self: *const EnvSpec, exempt: []const []const u8) bool {
        for (self.slice()) |variable| {
            if (containsName(exempt, variable.name)) continue;
            if (transport.isScrubbed(variable.name)) return false;
            if (!transport.isInheritable(variable.name)) return false;
        }
        return true;
    }

    fn put(self: *EnvSpec, name: []const u8, value: []const u8) EnvError!void {
        if (value.len > transport.max_env_value_bytes) return error.ValueTooLarge;
        if (self.count == max_child_env_vars) return error.EnvironmentTooLarge;
        if (self.contains(name)) return error.DuplicateVariable;
        self.vars[self.count] = .{ .name = name, .value = value };
        self.count += 1;
    }

    pub fn writeEnvMap(self: *const EnvSpec, out: *std.process.Environ.Map) !void {
        for (self.slice()) |variable| try out.put(variable.name, variable.value);
    }
};

fn containsName(names: []const []const u8, name: []const u8) bool {
    for (names) |candidate| {
        if (std.mem.eql(u8, candidate, name)) return true;
    }
    return false;
}

fn copyInheritable(spec: *EnvSpec, parent: transport.ParentEnv) EnvError!void {
    switch (parent) {
        .pairs => |pairs| for (pairs) |pair| {
            if (!transport.isInheritable(pair.name)) continue;
            spec.put(pair.name, pair.value) catch |err| switch (err) {
                error.DuplicateVariable => {},
                else => return err,
            };
        },
        .map => |map| {
            var it = map.iterator();
            while (it.next()) |entry| {
                if (!transport.isInheritable(entry.key_ptr.*)) continue;
                spec.put(entry.key_ptr.*, entry.value_ptr.*) catch |err| switch (err) {
                    error.DuplicateVariable => {},
                    else => return err,
                };
            }
        },
    }
}

pub const codex_login_args = [_][]const u8{"login"};

pub const LoginSpecError = EnvError || error{
    UnknownAccount,
    ProviderMismatch,

    InvalidExecutable,
    InvalidAccountHome,

    HomeOutsideAppRoot,

    IsolationInconsistent,
};

pub const LoginSpec = struct {
    provider: domain.Provider = .codex,
    account_id: []const u8 = "",
    executable: []const u8 = "",
    argv_storage: [max_login_argv][]const u8 = @splat(""),
    argv_count: usize = 0,
    env: EnvSpec = .{},

    home_var: []const u8 = "",
    isolation_storage: [runtime_paths.max_isolation_variables][]const u8 = @splat(""),
    isolation_count: usize = 0,
    home: runtime_paths.Path = .{},

    pub fn argv(self: *const LoginSpec) []const []const u8 {
        return self.argv_storage[0..self.argv_count];
    }

    pub fn homePath(self: *const LoginSpec) []const u8 {
        return self.home.slice();
    }

    pub fn isolationVars(self: *const LoginSpec) []const []const u8 {
        return self.isolation_storage[0..self.isolation_count];
    }

    pub fn homeValue(self: *const LoginSpec) ?[]const u8 {
        return self.env.find(self.home_var);
    }

    pub fn isolationIsConsistent(self: *const LoginSpec) bool {
        if (self.isolation_count == 0) return false;
        for (self.isolationVars()) |name| {
            const value = self.env.find(name) orelse return false;
            if (!std.mem.eql(u8, value, self.home.slice())) return false;
        }
        return true;
    }

    pub fn rebind(self: *LoginSpec) void {
        for (self.env.vars[0..self.env.count]) |*variable| {
            if (containsName(self.isolationVars(), variable.name)) variable.value = self.home.slice();
        }
    }
};

pub const LoginOptions = struct {
    provider: domain.Provider,
    account_id: []const u8,

    executable: []const u8,

    home: []const u8,
    parent_env: transport.ParentEnv,

    app_root: ?*const runtime_paths.Layout = null,
};

pub fn writeLoginSpec(out: *LoginSpec, options: LoginOptions) LoginSpecError!void {
    if (options.provider != .codex) return error.ProviderMismatch;
    runtime_paths.validateAbsoluteDir(options.executable) catch return error.InvalidExecutable;
    const home = runtime_paths.Path.init(options.home) catch return error.InvalidAccountHome;
    if (options.app_root) |layout| {
        if (!layout.contains(home.slice())) return error.HomeOutsideAppRoot;
    }

    transport.validateCodexHome(home.slice()) catch return error.InvalidAccountHome;

    out.* = .{
        .provider = options.provider,
        .account_id = options.account_id,
        .executable = options.executable,
        .home_var = runtime_paths.Layout.homeVariable(options.provider),
        .home = home,
    };

    out.argv_storage[0] = options.executable;
    out.argv_count = 1;
    for (codex_login_args) |argument| {
        if (out.argv_count == max_login_argv) return error.EnvironmentTooLarge;
        out.argv_storage[out.argv_count] = argument;
        out.argv_count += 1;
    }

    for (runtime_paths.Layout.isolationVariables(options.provider)) |name| {
        out.isolation_storage[out.isolation_count] = name;
        out.isolation_count += 1;
    }

    try copyInheritable(&out.env, options.parent_env);

    for (out.isolationVars()) |name| try out.env.put(name, out.home.slice());
    out.rebind();

    if (!out.env.holdsOnlyAllowedVariablesFor(out.isolationVars())) return error.ScrubbedVariable;
    if (!out.isolationIsConsistent()) return error.IsolationInconsistent;
}

pub const ChildError = error{
    EndOfOutput,

    Timeout,
    Canceled,

    Io,

    Unsupported,
};

pub const SpawnError = error{SpawnFailed};

pub const Exit = enum {
    unknown,

    success,

    failure,

    signaled,
};

pub const Child = struct {
    context: *anyopaque,
    vtable: *const VTable,

    pub const VTable = struct {
        arm: *const fn (context: *anyopaque, timeout_ms: u32) void,

        read: *const fn (context: *anyopaque, buffer: []u8) ChildError!usize,

        close: *const fn (context: *anyopaque) void,

        exit: *const fn (context: *anyopaque) Exit,
    };

    pub fn arm(self: Child, timeout_ms: u32) void {
        self.vtable.arm(self.context, timeout_ms);
    }

    pub fn read(self: Child, buffer: []u8) ChildError!usize {
        return self.vtable.read(self.context, buffer);
    }

    pub fn close(self: Child) void {
        self.vtable.close(self.context);
    }

    pub fn exit(self: Child) Exit {
        return self.vtable.exit(self.context);
    }
};

var unwired_context: u8 = 0;
const unwired_vtable: Child.VTable = .{
    .arm = unwiredArm,
    .read = unwiredRead,
    .close = unwiredClose,
    .exit = unwiredExit,
};

fn unwiredArm(_: *anyopaque, _: u32) void {}
fn unwiredRead(_: *anyopaque, _: []u8) ChildError!usize {
    return error.Unsupported;
}
fn unwiredClose(_: *anyopaque) void {}
fn unwiredExit(_: *anyopaque) Exit {
    return .unknown;
}

pub fn unwiredChild() Child {
    return .{ .context = &unwired_context, .vtable = &unwired_vtable };
}

pub const CancelToken = struct {
    context: *anyopaque,
    vtable: *const VTable,

    pub const VTable = struct {
        isCanceled: *const fn (context: *anyopaque) bool,
    };

    pub fn isCanceled(self: CancelToken) bool {
        return self.vtable.isCanceled(self.context);
    }
};

var never_canceled_context: u8 = 0;
const never_canceled_vtable: CancelToken.VTable = .{ .isCanceled = neverCanceledPoll };

fn neverCanceledPoll(_: *anyopaque) bool {
    return false;
}

pub fn neverCanceled() CancelToken {
    return .{ .context = &never_canceled_context, .vtable = &never_canceled_vtable };
}

pub const FlagCancelToken = struct {
    canceled: bool = false,
    polls: usize = 0,

    cancel_after_polls: ?usize = null,

    const vtable: CancelToken.VTable = .{ .isCanceled = poll };

    pub fn token(self: *FlagCancelToken) CancelToken {
        return .{ .context = self, .vtable = &vtable };
    }

    pub fn cancel(self: *FlagCancelToken) void {
        self.canceled = true;
    }

    fn poll(context: *anyopaque) bool {
        const self: *FlagCancelToken = @ptrCast(@alignCast(context));
        self.polls += 1;
        if (self.cancel_after_polls) |threshold| {
            if (self.polls > threshold) self.canceled = true;
        }
        return self.canceled;
    }
};

pub const Event = union(enum) {
    started: Started,

    signal: Signal,

    verification: Verification,

    finished: Finished,

    pub const Started = struct {
        provider: domain.Provider,
        timeout_ms: u32,
    };

    pub const Finished = struct {
        phase: Phase,
        public_code: ?[]const u8 = null,
        exit: Exit = .unknown,
    };
};

pub const ProgressSink = struct {
    context: *anyopaque,
    vtable: *const VTable,

    pub const VTable = struct {
        emit: *const fn (context: *anyopaque, event: Event) void,
    };

    pub fn emit(self: ProgressSink, event: Event) void {
        self.vtable.emit(self.context, event);
    }
};

var discard_progress_context: u8 = 0;
const discard_progress_vtable: ProgressSink.VTable = .{ .emit = discardProgressEmit };

fn discardProgressEmit(_: *anyopaque, _: Event) void {}

pub fn discardProgress() ProgressSink {
    return .{ .context = &discard_progress_context, .vtable = &discard_progress_vtable };
}

pub const RecordingProgress = struct {
    pub const max_events: usize = 64;

    events: [max_events]Event = @splat(.{ .signal = .unclassified }),
    count: usize = 0,
    dropped: usize = 0,

    const vtable: ProgressSink.VTable = .{ .emit = emit };

    pub fn sink(self: *RecordingProgress) ProgressSink {
        return .{ .context = self, .vtable = &vtable };
    }

    pub fn slice(self: *const RecordingProgress) []const Event {
        return self.events[0..self.count];
    }

    pub fn countOf(self: *const RecordingProgress, comptime tag: std.meta.Tag(Event)) usize {
        var total: usize = 0;
        for (self.slice()) |event| {
            if (event == tag) total += 1;
        }
        return total;
    }

    pub fn firstVerification(self: *const RecordingProgress) ?Verification {
        for (self.slice()) |event| {
            if (event == .verification) return event.verification;
        }
        return null;
    }

    pub fn finished(self: *const RecordingProgress) ?Event.Finished {
        for (self.slice()) |event| {
            if (event == .finished) return event.finished;
        }
        return null;
    }

    fn emit(context: *anyopaque, event: Event) void {
        const self: *RecordingProgress = @ptrCast(@alignCast(context));
        if (self.count == max_events) {
            self.dropped += 1;
            return;
        }
        self.events[self.count] = event;
        self.count += 1;
    }
};

pub const TerminationSignal = enum { terminate, kill };

pub const TerminationPolicy = struct {
    grace_ms: u32 = default_grace_ms,
    poll_interval_ms: u32 = default_poll_interval_ms,

    output_ended: bool = false,
};

pub const Termination = struct {
    stdin_closed: bool = false,
    output_closed: bool = false,
    terminate_signals: usize = 0,
    kill_signals: usize = 0,
    polls: usize = 0,
    waits: usize = 0,
    reaps: usize = 0,
    escalated: bool = false,

    pub fn isComplete(self: Termination) bool {
        if (!self.stdin_closed or !self.output_closed) return false;
        if (self.reaps != 1) return false;
        if (self.terminate_signals > 1 or self.kill_signals > 1) return false;
        return self.kill_signals == 0 or self.terminate_signals == 1;
    }

    pub fn exitedOnItsOwn(self: Termination) bool {
        return self.reaps == 1 and self.terminate_signals == 0 and self.kill_signals == 0;
    }
};

pub const ProcessControl = struct {
    context: *anyopaque,
    vtable: *const VTable,

    pub const VTable = struct {
        closeStdin: *const fn (context: *anyopaque) void,

        closeOutput: *const fn (context: *anyopaque) void,
        signal: *const fn (context: *anyopaque, which: TerminationSignal) void,

        poll: *const fn (context: *anyopaque) bool,

        reap: *const fn (context: *anyopaque) void,
        pause: *const fn (context: *anyopaque, milliseconds: u32) void,
    };
};

pub fn terminate(control: ProcessControl, policy: TerminationPolicy) Termination {
    var record: Termination = .{};

    control.vtable.closeStdin(control.context);
    record.stdin_closed = true;
    control.vtable.closeOutput(control.context);
    record.output_closed = true;

    const first_window: u32 = if (policy.output_ended) policy.grace_ms else 0;
    if (pollUntilReaped(control, &record, policy, first_window)) return record;

    control.vtable.signal(control.context, .terminate);
    record.terminate_signals = 1;
    if (pollUntilReaped(control, &record, policy, policy.grace_ms)) return record;

    control.vtable.signal(control.context, .kill);
    record.kill_signals = 1;
    record.escalated = true;
    control.vtable.reap(control.context);
    record.reaps = 1;
    return record;
}

fn pollUntilReaped(
    control: ProcessControl,
    record: *Termination,
    policy: TerminationPolicy,
    window_ms: u32,
) bool {
    record.polls += 1;
    if (control.vtable.poll(control.context)) {
        record.reaps = 1;
        return true;
    }
    const interval = @max(policy.poll_interval_ms, 1);
    var waited: u32 = 0;
    while (waited < window_ms and record.waits < max_grace_polls) {
        control.vtable.pause(control.context, interval);
        record.waits += 1;
        waited +|= interval;
        record.polls += 1;
        if (control.vtable.poll(control.context)) {
            record.reaps = 1;
            return true;
        }
    }
    return false;
}

pub const FakeProcessControl = struct {
    reaped_after_polls: ?usize = null,

    killed: bool = false,

    polls: usize = 0,
    stdin_closes: usize = 0,
    output_closes: usize = 0,
    terminate_signals: usize = 0,
    kill_signals: usize = 0,
    blocking_reaps: usize = 0,
    paused_ms: u32 = 0,

    const vtable: ProcessControl.VTable = .{
        .closeStdin = closeStdin,
        .closeOutput = closeOutput,
        .signal = signal,
        .poll = poll,
        .reap = reap,
        .pause = pause,
    };

    pub fn control(self: *FakeProcessControl) ProcessControl {
        return .{ .context = self, .vtable = &vtable };
    }

    fn closeStdin(context: *anyopaque) void {
        const self: *FakeProcessControl = @ptrCast(@alignCast(context));
        self.stdin_closes += 1;
    }

    fn closeOutput(context: *anyopaque) void {
        const self: *FakeProcessControl = @ptrCast(@alignCast(context));
        self.output_closes += 1;
    }

    fn signal(context: *anyopaque, which: TerminationSignal) void {
        const self: *FakeProcessControl = @ptrCast(@alignCast(context));
        switch (which) {
            .terminate => self.terminate_signals += 1,
            .kill => {
                self.kill_signals += 1;
                self.killed = true;
            },
        }
    }

    fn poll(context: *anyopaque) bool {
        const self: *FakeProcessControl = @ptrCast(@alignCast(context));
        self.polls += 1;
        const threshold = self.reaped_after_polls orelse return false;
        return self.polls >= threshold;
    }

    fn reap(context: *anyopaque) void {
        const self: *FakeProcessControl = @ptrCast(@alignCast(context));
        self.blocking_reaps += 1;
    }

    fn pause(context: *anyopaque, milliseconds: u32) void {
        const self: *FakeProcessControl = @ptrCast(@alignCast(context));
        self.paused_ms +|= milliseconds;
    }
};

pub const SpawnOptions = struct {
    argv: []const []const u8,

    environ: *const std.process.Environ.Map,
    cwd: std.process.Child.Cwd = .inherit,
};

pub const ChildProcess = struct {
    io: std.Io,
    child: std.process.Child,

    output: ?std.Io.File = null,

    deadline: ?std.Io.Clock.Timestamp = null,
    closed: bool = false,

    output_ended: bool = false,
    exit_state: Exit = .unknown,
    termination: Termination = .{},
    policy: TerminationPolicy = .{},

    const vtable: Child.VTable = .{
        .arm = armChild,
        .read = readChild,
        .close = closeChild,
        .exit = exitChild,
    };

    const control_vtable: ProcessControl.VTable = .{
        .closeStdin = controlCloseStdin,
        .closeOutput = controlCloseOutput,
        .signal = controlSignal,
        .poll = controlPoll,
        .reap = controlReap,
        .pause = controlPause,
    };

    pub fn spawn(io: std.Io, options: SpawnOptions) SpawnError!ChildProcess {
        if (options.argv.len == 0) return error.SpawnFailed;
        const merged = try openMergedPipe();
        errdefer merged.read_end.close(io);

        const child = std.process.spawn(io, .{
            .argv = options.argv,
            .environ_map = options.environ,
            .cwd = options.cwd,
            .stdin = .pipe,

            .stdout = .{ .file = merged.write_end },
            .stderr = .{ .file = merged.write_end },
        }) catch {
            merged.write_end.close(io);
            return error.SpawnFailed;
        };

        merged.write_end.close(io);
        return .{ .io = io, .child = child, .output = merged.read_end };
    }

    pub fn handle(self: *ChildProcess) Child {
        return .{ .context = self, .vtable = &vtable };
    }

    pub fn close(self: *ChildProcess) void {
        if (self.closed) return;
        self.closed = true;
        var policy = self.policy;
        policy.output_ended = self.output_ended;
        self.termination = terminate(.{ .context = self, .vtable = &control_vtable }, policy);
    }

    fn armChild(context: *anyopaque, timeout_ms: u32) void {
        const self: *ChildProcess = @ptrCast(@alignCast(context));
        self.deadline = .fromNow(self.io, .{ .raw = .fromMilliseconds(timeout_ms), .clock = .awake });
    }

    fn readChild(context: *anyopaque, buffer: []u8) ChildError!usize {
        const self: *ChildProcess = @ptrCast(@alignCast(context));
        const output = self.output orelse {
            self.output_ended = true;
            return error.EndOfOutput;
        };
        const remaining_ms = self.remainingMs() orelse return error.Timeout;
        return transport.runBounded(self.io, remaining_ms, readOnce, .{ self.io, output, buffer }) catch |err| switch (err) {
            error.EndOfStream => {
                self.output_ended = true;
                return error.EndOfOutput;
            },
            error.Timeout => error.Timeout,
            error.Canceled => error.Canceled,
            else => error.Io,
        };
    }

    fn closeChild(context: *anyopaque) void {
        const self: *ChildProcess = @ptrCast(@alignCast(context));
        self.close();
    }

    fn exitChild(context: *anyopaque) Exit {
        const self: *ChildProcess = @ptrCast(@alignCast(context));
        return self.exit_state;
    }

    fn controlCloseStdin(context: *anyopaque) void {
        const self: *ChildProcess = @ptrCast(@alignCast(context));
        if (self.child.stdin) |stdin| {
            stdin.close(self.io);
            self.child.stdin = null;
        }
    }

    fn controlCloseOutput(context: *anyopaque) void {
        const self: *ChildProcess = @ptrCast(@alignCast(context));
        if (self.output) |output| {
            output.close(self.io);
            self.output = null;
        }
    }

    fn controlSignal(context: *anyopaque, which: TerminationSignal) void {
        const self: *ChildProcess = @ptrCast(@alignCast(context));

        const pid = self.child.id orelse return;
        posix.kill(pid, switch (which) {
            .terminate => .TERM,
            .kill => .KILL,
        }) catch {};
    }

    fn controlPoll(context: *anyopaque) bool {
        const self: *ChildProcess = @ptrCast(@alignCast(context));
        const pid = self.child.id orelse return true;
        var status: c_int = undefined;
        const result = posix.system.waitpid(pid, &status, posix.W.NOHANG);
        if (result > 0) {
            self.exit_state = exitFromStatus(@bitCast(status));
            self.finishCleanup();
            return true;
        }
        if (result == 0) return false;
        return switch (posix.errno(result)) {
            .CHILD => {
                self.finishCleanup();
                return true;
            },
            else => false,
        };
    }

    fn controlReap(context: *anyopaque) void {
        const self: *ChildProcess = @ptrCast(@alignCast(context));
        if (self.child.id == null) return;

        self.child.kill(self.io);
        if (self.exit_state == .unknown) self.exit_state = .signaled;
    }

    fn controlPause(context: *anyopaque, milliseconds: u32) void {
        const self: *ChildProcess = @ptrCast(@alignCast(context));
        self.io.sleep(.fromMilliseconds(milliseconds), .awake) catch {};
    }

    fn finishCleanup(self: *ChildProcess) void {
        std.debug.assert(self.child.stdin == null);
        std.debug.assert(self.child.stdout == null);
        std.debug.assert(self.child.stderr == null);
        self.child.id = null;
    }

    fn remainingMs(self: *ChildProcess) ?u32 {
        const deadline = self.deadline orelse return null;
        const remaining = deadline.durationFromNow(self.io).raw.toMilliseconds();
        if (remaining <= 0) return null;
        return @intCast(@min(remaining, @as(i64, std.math.maxInt(u32))));
    }
};

pub fn exitFromStatus(status: u32) Exit {
    if (posix.W.IFSIGNALED(status)) return .signaled;
    if (posix.W.IFEXITED(status)) {
        return if ((status >> 8) & 0xff == 0) .success else .failure;
    }
    return .unknown;
}

const MergedPipe = struct {
    read_end: std.Io.File,
    write_end: std.Io.File,
};

fn openMergedPipe() SpawnError!MergedPipe {
    if (builtin.os.tag == .windows) return error.SpawnFailed;
    var fds: [2]posix.fd_t = undefined;
    switch (posix.errno(posix.system.pipe(&fds))) {
        .SUCCESS => {},
        else => return error.SpawnFailed,
    }
    for (fds) |fd| {
        switch (posix.errno(posix.system.fcntl(fd, posix.F.SETFD, @as(c_int, posix.FD_CLOEXEC)))) {
            .SUCCESS => {},
            else => {
                _ = posix.system.close(fds[0]);
                _ = posix.system.close(fds[1]);
                return error.SpawnFailed;
            },
        }
    }
    return .{
        .read_end = .{ .handle = fds[0], .flags = .{ .nonblocking = false } },
        .write_end = .{ .handle = fds[1], .flags = .{ .nonblocking = false } },
    };
}

fn readOnce(io: std.Io, file: std.Io.File, buffer: []u8) transport.TransportError!usize {
    return file.readStreaming(io, &.{buffer}) catch |err| switch (err) {
        error.EndOfStream => error.EndOfStream,
        error.Canceled => error.Canceled,

        else => error.Io,
    };
}

pub const LineScanner = struct {
    storage: []u8,
    start: usize = 0,
    end: usize = 0,
    scan: usize = 0,
    dropping: bool = false,
    at_end_of_output: bool = false,
    empty_reads: usize = 0,

    lines_read: usize = 0,
    bytes_read: usize = 0,
    lines_dropped: usize = 0,

    pub fn init(storage: []u8) LineScanner {
        std.debug.assert(storage.len >= min_scan_bytes);
        return .{ .storage = storage };
    }

    pub fn next(self: *LineScanner, child: Child) ChildError![]const u8 {
        while (true) {
            if (self.takeBuffered()) |line| {
                if (line.len == 0) continue;
                self.lines_read += 1;
                return line;
            }
            if (self.at_end_of_output) return error.EndOfOutput;
            try self.fill(child);
        }
    }

    fn takeBuffered(self: *LineScanner) ?[]const u8 {
        while (self.scan < self.end) {
            if (self.storage[self.scan] == '\n') {
                const line = self.storage[self.start..self.scan];
                self.start = self.scan + 1;
                self.scan = self.start;

                if (self.dropping) {
                    self.dropping = false;
                    continue;
                }
                return std.mem.trim(u8, line, " \t\r");
            }
            self.scan += 1;
        }
        return null;
    }

    fn fill(self: *LineScanner, child: Child) ChildError!void {
        self.compact();
        if (self.end == self.storage.len) {
            if (!self.dropping) self.lines_dropped += 1;
            self.dropping = true;
            self.start = 0;
            self.end = 0;
            self.scan = 0;
            return;
        }
        const count = child.read(self.storage[self.end..]) catch |err| switch (err) {
            error.EndOfOutput => {
                self.at_end_of_output = true;
                return;
            },
            else => |other| return other,
        };
        if (count == 0) {
            self.empty_reads += 1;
            if (self.empty_reads > max_empty_reads) return error.Io;
            return;
        }
        self.empty_reads = 0;
        self.end += count;
        self.bytes_read += count;
    }

    fn compact(self: *LineScanner) void {
        if (self.start == 0) return;
        const pending = self.end - self.start;
        if (pending != 0) std.mem.copyForwards(u8, self.storage[0..pending], self.storage[self.start..self.end]);
        self.scan -= self.start;
        self.start = 0;
        self.end = pending;
    }
};

pub const Signal = enum {
    already_authenticated,

    rejected,

    authorized,

    awaiting_user,

    unclassified,
};

const already_markers = [_][]const u8{ "already logged in", "already authenticated", "already signed in" };
const rejected_markers = [_][]const u8{ "error", "failed", "failure", "denied", "expired", "invalid", "cancel", "unauthorized", "timed out" };
const authorized_markers = [_][]const u8{ "logged in", "login successful", "successfully logged", "authentication complete", "signed in", "you are now" };
const awaiting_markers = [_][]const u8{ "waiting", "open the following", "press enter", "browser", "visit", "enter the code", "user code", "verification" };

pub fn classifyLine(line: []const u8) Signal {
    if (containsAnyIgnoreCase(line, &already_markers)) return .already_authenticated;
    if (containsAnyIgnoreCase(line, &rejected_markers)) return .rejected;
    if (containsAnyIgnoreCase(line, &authorized_markers)) return .authorized;
    if (containsAnyIgnoreCase(line, &awaiting_markers)) return .awaiting_user;
    return .unclassified;
}

fn containsAnyIgnoreCase(haystack: []const u8, needles: []const []const u8) bool {
    for (needles) |needle| {
        if (std.ascii.findIgnoreCase(haystack, needle) != null) return true;
    }
    return false;
}

pub const verification_hosts = [_][]const u8{
    "auth.openai.com",
    "chatgpt.com",
    "platform.openai.com",
};

pub const Verification = struct {
    url_bytes: [max_verification_url_bytes]u8 = @splat(0),
    url_len: u8 = 0,
    code_bytes: [max_verification_code_bytes]u8 = @splat(0),
    code_len: u8 = 0,

    pub fn url(self: *const Verification) []const u8 {
        return self.url_bytes[0..self.url_len];
    }

    pub fn code(self: *const Verification) []const u8 {
        return self.code_bytes[0..self.code_len];
    }

    pub fn hasUrl(self: *const Verification) bool {
        return self.url_len != 0;
    }

    pub fn hasCode(self: *const Verification) bool {
        return self.code_len != 0;
    }

    pub fn isEmpty(self: *const Verification) bool {
        return self.url_len == 0 and self.code_len == 0;
    }

    fn setUrl(self: *Verification, value: []const u8) void {
        if (value.len > max_verification_url_bytes) return;
        @memcpy(self.url_bytes[0..value.len], value);
        self.url_len = @intCast(value.len);
    }

    fn setCode(self: *Verification, value: []const u8) void {
        if (value.len > max_verification_code_bytes) return;
        @memcpy(self.code_bytes[0..value.len], value);
        self.code_len = @intCast(value.len);
    }

    pub fn format(self: Verification, writer: *std.Io.Writer) std.Io.Writer.Error!void {
        const value = self;
        try writer.print("url={s} code={s}", .{ value.url_bytes[0..value.url_len], value.code_bytes[0..value.code_len] });
    }
};

const url_scheme = "https://";

pub fn extractVerificationUrl(line: []const u8) ?[]const u8 {
    const scheme_index = std.ascii.findIgnoreCase(line, url_scheme) orelse return null;
    const rest = line[scheme_index..];
    var length: usize = 0;
    while (length < rest.len and isUrlByte(rest[length])) : (length += 1) {}

    while (length > 0 and isUrlTrailingPunctuation(rest[length - 1])) length -= 1;
    if (length == 0 or length > max_verification_url_bytes) return null;
    const candidate = rest[0..length];

    const authority = candidate[url_scheme.len..];
    const host_end = std.mem.indexOfAny(u8, authority, "/?#") orelse authority.len;
    const host = authority[0..host_end];
    if (host.len == 0) return null;
    var host_allowed = false;
    for (verification_hosts) |allowed| {
        if (std.ascii.eqlIgnoreCase(host, allowed)) host_allowed = true;
    }
    if (!host_allowed) return null;

    var run: usize = 0;
    for (candidate) |byte| {
        if (std.ascii.isAlphanumeric(byte)) {
            run += 1;
            if (run > max_url_alphanumeric_run) return null;
        } else {
            run = 0;
        }
    }
    return candidate;
}

fn isUrlByte(byte: u8) bool {
    return switch (byte) {
        'a'...'z', 'A'...'Z', '0'...'9' => true,
        '-', '.', '_', '~', ':', '/', '?', '#', '=', '&', '+', '%' => true,
        else => false,
    };
}

fn isUrlTrailingPunctuation(byte: u8) bool {
    return byte == '.' or byte == ':' or byte == '?' or byte == '&';
}

pub fn extractVerificationCode(line: []const u8) ?[]const u8 {
    if (std.ascii.findIgnoreCase(line, "code") == null) return null;
    var index: usize = 0;
    while (index < line.len) {
        if (!isCodeByte(line[index])) {
            index += 1;
            continue;
        }
        const start = index;
        while (index < line.len and isCodeByte(line[index])) : (index += 1) {}
        const candidate = line[start..index];
        if (isVerificationCode(candidate)) return candidate;
    }
    return null;
}

fn isCodeByte(byte: u8) bool {
    return switch (byte) {
        'A'...'Z', '0'...'9', '-' => true,
        else => false,
    };
}

fn isVerificationCode(candidate: []const u8) bool {
    if (candidate.len < 6 or candidate.len > max_verification_code_bytes) return false;
    if (candidate[0] == '-' or candidate[candidate.len - 1] == '-') return false;
    var letters: usize = 0;
    var run: usize = 0;
    var longest_run: usize = 0;
    for (candidate) |byte| {
        if (byte == '-') {
            run = 0;
            continue;
        }
        if (std.ascii.isAlphabetic(byte)) letters += 1;
        run += 1;
        longest_run = @max(longest_run, run);
    }

    if (letters == 0) return false;
    return longest_run <= 12;
}

pub const Phase = enum {
    ended,

    timed_out,
    canceled,

    failed,

    output_limit,
};

pub const SignalCounts = struct {
    already_authenticated: usize = 0,
    rejected: usize = 0,
    authorized: usize = 0,
    awaiting_user: usize = 0,
    unclassified: usize = 0,

    pub fn record(self: *SignalCounts, signal: Signal) void {
        switch (signal) {
            .already_authenticated => self.already_authenticated += 1,
            .rejected => self.rejected += 1,
            .authorized => self.authorized += 1,
            .awaiting_user => self.awaiting_user += 1,
            .unclassified => self.unclassified += 1,
        }
    }

    pub fn total(self: SignalCounts) usize {
        return self.already_authenticated + self.rejected + self.authorized +
            self.awaiting_user + self.unclassified;
    }
};

pub const Status = struct {
    provider: domain.Provider,
    account_id: []const u8,
    phase: Phase = .ended,
    public_code: ?[]const u8 = null,
    signals: SignalCounts = .{},
    lines_scanned: usize = 0,
    bytes_scanned: usize = 0,
    lines_dropped: usize = 0,

    verification: ?Verification = null,

    child_closed: bool = false,

    exit: Exit = .unknown,

    pub fn endedCleanly(self: Status) bool {
        return self.phase == .ended and self.public_code == null and self.signals.rejected == 0;
    }

    pub fn belongsTo(self: Status, provider: domain.Provider, account_id: []const u8) bool {
        return self.provider == provider and std.mem.eql(u8, self.account_id, account_id);
    }

    pub fn format(self: Status, writer: *std.Io.Writer) std.Io.Writer.Error!void {
        const value = self;
        try writer.print("login provider={t} account={s} phase={t} exit={t} lines={d} bytes={d}", .{
            value.provider,
            value.account_id,
            value.phase,
            value.exit,
            value.lines_scanned,
            value.bytes_scanned,
        });
        if (value.public_code) |code| try writer.print(" code={s}", .{code});
    }
};

pub fn spawnFailedStatus(provider: domain.Provider, account_id: []const u8) Status {
    return .{
        .provider = provider,
        .account_id = account_id,
        .phase = .failed,
        .public_code = public_code_login_spawn_failed,
    };
}

pub const RunOptions = struct {
    timeout_ms: u32 = default_timeout_ms,

    max_output_bytes: usize = default_max_output_bytes,

    cancel: CancelToken = neverCanceled(),

    progress: ProgressSink = discardProgress(),
};

pub fn clampTimeout(timeout_ms: u32) u32 {
    return std.math.clamp(timeout_ms, min_timeout_ms, max_timeout_ms);
}

pub const Runner = struct {
    child: Child,
    scanner: LineScanner,
    provider: domain.Provider,
    account_id: []const u8,

    pub fn init(child: Child, storage: []u8, provider: domain.Provider, account_id: []const u8) Runner {
        return .{
            .child = child,
            .scanner = .init(storage),
            .provider = provider,
            .account_id = account_id,
        };
    }

    pub fn run(self: *Runner, options: RunOptions) Status {
        var status: Status = .{ .provider = self.provider, .account_id = self.account_id };
        const timeout_ms = clampTimeout(options.timeout_ms);

        self.child.arm(timeout_ms);
        options.progress.emit(.{ .started = .{ .provider = self.provider, .timeout_ms = timeout_ms } });

        self.scan(&status, options);

        self.child.close();
        status.child_closed = true;
        status.exit = self.child.exit();

        status.lines_scanned = self.scanner.lines_read;
        status.bytes_scanned = self.scanner.bytes_read;
        status.lines_dropped = self.scanner.lines_dropped;
        if (status.public_code == null and status.signals.rejected != 0 and status.signals.authorized == 0) {
            status.public_code = public_code_login_rejected;
        }

        if (status.phase == .ended and (status.exit == .failure or status.exit == .signaled)) {
            status.phase = .failed;
            if (status.public_code == null) status.public_code = public_code_login_rejected;
        }
        options.progress.emit(.{ .finished = .{
            .phase = status.phase,
            .public_code = status.public_code,
            .exit = status.exit,
        } });
        return status;
    }

    fn scan(self: *Runner, status: *Status, options: RunOptions) void {
        while (true) {
            if (options.cancel.isCanceled()) {
                status.phase = .canceled;
                status.public_code = public_code_login_canceled;
                return;
            }
            if (self.scanner.bytes_read > options.max_output_bytes or
                self.scanner.lines_read >= max_lines_scanned)
            {
                status.phase = .output_limit;
                status.public_code = public_code_login_noisy;
                return;
            }
            const line = self.scanner.next(self.child) catch |err| {
                switch (err) {
                    error.EndOfOutput => status.phase = .ended,
                    error.Timeout => {
                        status.phase = .timed_out;
                        status.public_code = public_code_login_timeout;
                    },
                    error.Canceled => {
                        status.phase = .canceled;
                        status.public_code = public_code_login_canceled;
                    },
                    error.Unsupported => {
                        status.phase = .failed;
                        status.public_code = public_code_login_unsupported;
                    },
                    error.Io => {
                        status.phase = .failed;
                        status.public_code = public_code_login_io;
                    },
                }
                return;
            };
            observe(line, status, options.progress);
        }
    }
};

fn observe(line: []const u8, status: *Status, progress: ProgressSink) void {
    const signal = classifyLine(line);
    status.signals.record(signal);
    progress.emit(.{ .signal = signal });

    const found_url = extractVerificationUrl(line);
    const found_code = extractVerificationCode(line);
    if (found_url == null and found_code == null) return;

    if (status.verification == null) status.verification = .{};
    const verification = &status.verification.?;
    var changed = false;

    if (found_url) |value| {
        if (!verification.hasUrl()) {
            verification.setUrl(value);
            changed = verification.hasUrl();
        }
    }
    if (found_code) |value| {
        if (!verification.hasCode()) {
            verification.setCode(value);
            changed = changed or verification.hasCode();
        }
    }
    if (changed) progress.emit(.{ .verification = verification.* });
}

pub const FakeChild = struct {
    pub const Chunk = union(enum) {
        bytes: []const u8,

        empty,
        failure: ChildError,
    };

    chunks: []const Chunk = &.{},
    chunk_index: usize = 0,
    chunk_offset: usize = 0,

    exhausted: ChildError = error.EndOfOutput,

    scripted_exit: Exit = .success,

    reaped_after_polls: ?usize = 1,
    policy: TerminationPolicy = .{ .grace_ms = 4, .poll_interval_ms = 1 },

    arm_count: usize = 0,
    last_timeout_ms: u32 = 0,
    read_count: usize = 0,
    exit_queries: usize = 0,
    closes: usize = 0,

    output_ended: bool = false,

    termination: Termination = .{},
    lifecycle: transport.FakeChildLifecycle = .{},
    process: FakeProcessControl = .{},

    const vtable: Child.VTable = .{
        .arm = arm,
        .read = read,
        .close = close,
        .exit = exitState,
    };

    pub fn handle(self: *FakeChild) Child {
        return .{ .context = self, .vtable = &vtable };
    }

    pub fn reapedExactlyOnce(self: *const FakeChild) bool {
        return self.lifecycle.reapedExactlyOnce() and
            self.closes == 1 and
            self.termination.isComplete();
    }

    fn arm(context: *anyopaque, timeout_ms: u32) void {
        const self: *FakeChild = @ptrCast(@alignCast(context));
        self.arm_count += 1;
        self.last_timeout_ms = timeout_ms;
    }

    fn read(context: *anyopaque, buffer: []u8) ChildError!usize {
        const self: *FakeChild = @ptrCast(@alignCast(context));
        self.read_count += 1;
        if (self.chunk_index >= self.chunks.len) {
            if (self.exhausted == error.EndOfOutput) self.output_ended = true;
            return self.exhausted;
        }
        switch (self.chunks[self.chunk_index]) {
            .failure => |err| {
                self.chunk_index += 1;
                if (err == error.EndOfOutput) self.output_ended = true;
                return err;
            },
            .empty => {
                self.chunk_index += 1;
                return 0;
            },
            .bytes => |bytes| {
                const rest = bytes[self.chunk_offset..];
                const count = @min(rest.len, buffer.len);
                @memcpy(buffer[0..count], rest[0..count]);
                self.chunk_offset += count;
                if (self.chunk_offset == bytes.len) {
                    self.chunk_index += 1;
                    self.chunk_offset = 0;
                }
                return count;
            },
        }
    }

    fn close(context: *anyopaque) void {
        const self: *FakeChild = @ptrCast(@alignCast(context));
        if (self.lifecycle.closed) return;
        self.lifecycle.close();
        self.closes += 1;
        self.process.reaped_after_polls = self.reaped_after_polls;
        var policy = self.policy;
        policy.output_ended = self.output_ended;
        self.termination = terminate(self.process.control(), policy);

        if (self.process.killed) self.scripted_exit = .signaled;
    }

    fn exitState(context: *anyopaque) Exit {
        const self: *FakeChild = @ptrCast(@alignCast(context));
        self.exit_queries += 1;
        if (self.closes == 0) return .unknown;
        return self.scripted_exit;
    }
};

const forbidden_field_words = [_][]const u8{
    "token",  "secret", "credential", "password",
    "bearer", "cookie", "session",    "auth_value",
};

fn assertSanitizedFieldName(comptime name: []const u8) void {
    comptime {
        var lowered: [name.len]u8 = undefined;
        for (name, 0..) |byte, index| lowered[index] = std.ascii.toLower(byte);
        for (forbidden_field_words) |word| {
            if (std.mem.indexOf(u8, &lowered, word) != null) {
                @compileError("reported field '" ++ name ++ "' is named like credential data");
            }
        }
    }
}

fn assertSanitized(comptime T: type, comptime depth: usize) void {
    comptime {
        @setEvalBranchQuota(20_000);
        if (depth > 8) @compileError("type nests too deeply to verify: " ++ @typeName(T));
        switch (@typeInfo(T)) {
            .@"struct" => |info| for (info.fields) |field| {
                assertSanitizedFieldName(field.name);
                assertSanitized(field.type, depth + 1);
            },
            .@"union" => |info| for (info.fields) |field| {
                assertSanitizedFieldName(field.name);
                assertSanitized(field.type, depth + 1);
            },
            .optional => |info| assertSanitized(info.child, depth + 1),
            .array => |info| assertSanitized(info.child, depth + 1),
            .pointer => |info| if (info.child != u8) assertSanitized(info.child, depth + 1),
            else => {},
        }
    }
}

comptime {
    assertSanitized(Status, 0);
    assertSanitized(SignalCounts, 0);
    assertSanitized(Verification, 0);
    assertSanitized(Event, 0);
    assertSanitized(Termination, 0);

    for (codex_login_args) |argument| {
        if (argument.len == 0) @compileError("a login argument must not be empty");
        for (argument) |byte| {
            if (byte == 0 or byte == ' ' or byte < 0x20) @compileError("a login argument must be one shell-free token");
        }
    }

    if (runtime_paths.Layout.isolationVariables(.codex).len != 1) {
        @compileError("a codex login sets exactly one home variable");
    }
    if (min_scan_bytes < 2 * max_line_bytes) @compileError("scan storage must hold two lines");
}
