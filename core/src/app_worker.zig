const std = @import("std");

const account_registry = @import("account_registry.zig");
const coordinator = @import("coordinator.zig");
const domain = @import("domain.zig");
const login_runtime = @import("login_runtime.zig");
const proxy_control = @import("proxy_control_client.zig");
const proxy_import = @import("proxy_import_runner.zig");
const runtime_paths = @import("runtime_paths.zig");
const runtime_adapters = @import("app_runtime_adapters.zig");
const codex = @import("providers/codex.zig");

const CodexChannel = runtime_adapters.CodexChannel;
const CodexLauncher = runtime_adapters.CodexLauncher;
const LaunchError = runtime_adapters.LaunchError;
const LoginChannel = runtime_adapters.LoginChannel;
const LoginLauncher = runtime_adapters.LoginLauncher;
const unwiredCodexLauncher = runtime_adapters.unwiredCodexLauncher;
const unwiredLoginLauncher = runtime_adapters.unwiredLoginLauncher;

pub const max_workers: usize = coordinator.max_concurrent_operations;

comptime {
    if (max_workers == 0) @compileError("the worker pool must be able to run one operation");
}

pub const login_scan_bytes: usize = 4 * 1024;

comptime {
    if (login_scan_bytes < login_runtime.min_scan_bytes) {
        @compileError("login scan storage must hold at least two maximum-length lines");
    }
}

pub const LoginOptions = struct {
    timeout_ms: u32 = login_runtime.default_timeout_ms,
    max_output_bytes: usize = login_runtime.default_max_output_bytes,
};

pub const ProxyJobKind = enum { refresh_status, switch_account, pause_account, reload_account, clear_cooldown, sync_config };
pub const ProxyFailure = enum { @"unreachable", timeout, protocol_error, incompatible, action_failed, import_failed, import_node_missing };

pub const ProxyJobResult = union(enum) {
    none,
    status: proxy_control.Status,
    pause: proxy_control.PauseReceipt,
    clear_cooldown: proxy_control.ClearCooldownReceipt,
    failure: ProxyFailure,
};

pub const ProxyWorker = struct {
    state: enum { idle, running, complete } = .idle,
    kind: ProxyJobKind = .refresh_status,
    done: std.Io.Event = .unset,
    future: std.Io.Future(void) = undefined,
    started: bool = false,

    allocator: std.mem.Allocator = undefined,
    exchange: proxy_control.Exchange = proxy_control.unwiredExchange(),
    importer: proxy_import.Runner = proxy_import.unwiredRunner(),
    base_url: proxy_control.BaseUrl = proxy_control.BaseUrl.init("http://127.0.0.1:8787") catch unreachable,
    proxy_name: proxy_control.BoundedText(proxy_control.max_proxy_name_bytes) = .{},
    app_root: runtime_paths.Path = .{},
    node_path: runtime_paths.Path = .{},
    cli_path: runtime_paths.Path = .{},
    config_path: runtime_paths.Path = .{},
    parent_env: @import("process_jsonl.zig").ParentEnv = .{ .pairs = &.{} },
    timeout_ms: u32 = proxy_control.default_timeout_ms,
    max_output_bytes: usize = proxy_import.default_max_output_bytes,

    result: ProxyJobResult = .none,

    fn run(io: std.Io, done: *std.Io.Event, self: *ProxyWorker) void {
        defer done.set(io);
        var client = proxy_control.Client{
            .allocator = self.allocator,
            .exchange = self.exchange,
            .base_url = self.base_url,
            .config_path = self.config_path.slice(),
            .timeout_ms = self.timeout_ms,
        };
        self.result = switch (self.kind) {
            .refresh_status => statusResult(client.status()),
            .switch_account => statusResult(client.switchAccount(self.proxy_name.slice())),
            .pause_account => pauseResult(client.pauseAccount(self.proxy_name.slice())),
            .reload_account => statusResult(client.reloadAccount(self.proxy_name.slice())),
            .clear_cooldown => clearCooldownResult(client.clearCooldown(self.proxy_name.slice())),
            .sync_config => blk: {
                const imported = self.importer.run(.{
                    .node_path = self.node_path.slice(),
                    .cli_path = self.cli_path.slice(),
                    .app_root = self.app_root.slice(),
                    .config_path = self.config_path.slice(),
                    .parent_env = self.parent_env,
                    .timeout_ms = self.timeout_ms,
                    .max_output_bytes = self.max_output_bytes,
                });
                if (imported != .success) {
                    break :blk .{
                        .failure = switch (imported) {
                            .timeout, .canceled => .timeout,

                            .spawn_failed => .import_node_missing,
                            else => .import_failed,
                        },
                    };
                }
                break :blk statusResult(client.reloadConfig());
            },
        };
    }
};

fn statusResult(result: proxy_control.ClientError!proxy_control.Status) ProxyJobResult {
    return if (result) |status| .{ .status = status } else |err| .{ .failure = proxyFailure(err) };
}

fn clearCooldownResult(result: proxy_control.ClientError!proxy_control.ClearCooldownReceipt) ProxyJobResult {
    return if (result) |receipt| .{ .clear_cooldown = receipt } else |err| .{ .failure = proxyFailure(err) };
}

fn pauseResult(result: proxy_control.ClientError!proxy_control.PauseReceipt) ProxyJobResult {
    return if (result) |receipt| .{ .pause = receipt } else |err| .{ .failure = proxyFailure(err) };
}

fn proxyFailure(err: proxy_control.ClientError) ProxyFailure {
    return switch (err) {
        error.Network => .@"unreachable",
        error.Timeout, error.Canceled => .timeout,
        error.IncompatibleVersion => .incompatible,
        error.ApiRejected, error.InvalidAccountName, error.RequestRejected => .action_failed,
        else => .protocol_error,
    };
}

pub fn startProxy(io: std.Io, worker: *ProxyWorker) bool {
    if (worker.state != .idle) return false;
    worker.done = .unset;
    worker.result = .none;
    worker.future = io.concurrent(ProxyWorker.run, .{ io, &worker.done, worker }) catch return false;
    worker.started = true;
    worker.state = .running;
    return true;
}

pub fn releaseProxy(worker: *ProxyWorker) void {
    worker.result = .none;
    worker.state = .idle;
}

pub fn cancelAndJoinProxy(io: std.Io, worker: *ProxyWorker) void {
    if (worker.state == .running and worker.started) {
        _ = worker.future.cancel(io);
        _ = worker.future.await(io);
    }
    worker.started = false;
    worker.result = .none;
    worker.state = .idle;
}

pub const JobKind = enum {
    codex_refresh,
    login,
    reset_preflight,
    reset_consume,
    reset_post_read,
};

const JobResult = union(enum) {
    none,

    rejected: []const u8,
    codex: codex.RefreshOutcome,
    login: login_runtime.Status,
    consume: codex.ConsumeOutcome,
};

pub const Worker = struct {
    index: usize = 0,
    state: enum { idle, running, complete } = .idle,
    kind: JobKind = .codex_refresh,
    done: std.Io.Event = .unset,
    future: std.Io.Future(void) = undefined,
    started: bool = false,

    ticket: coordinator.Ticket = undefined,
    provider: domain.Provider = .codex,
    now_unix_s: i64 = 0,
    home: runtime_paths.Path = .{},
    account_id_buffer: [account_registry.max_id_bytes]u8 = @splat(0),
    account_id_len: usize = 0,
    login_spec: coordinator.LoginSpec = .{},

    attempt: domain.ResetAttempt = empty_attempt,
    attempt_key: [codex.max_idempotency_key_bytes]u8 = @splat(0),
    attempt_key_len: usize = 0,
    credit_id_buffer: [codex.max_credit_id_bytes]u8 = @splat(0),
    credit_id_len: usize = 0,
    has_credit_id: bool = false,

    codex_launcher: CodexLauncher = unwiredCodexLauncher(),
    login_launcher: LoginLauncher = unwiredLoginLauncher(),
    codex_config: codex.Config = .{ .codex_home = "" },
    login_options: LoginOptions = .{},

    codex_workspace: codex.Workspace = .{},
    channel: CodexChannel = .{},

    external_channel: ?*CodexChannel = null,
    login_channel: LoginChannel = .{},
    login_scan: [login_scan_bytes]u8 = @splat(0),

    result: JobResult = .none,

    pub fn accountId(self: *const Worker) []const u8 {
        return self.account_id_buffer[0..self.account_id_len];
    }

    pub fn creditId(self: *const Worker) ?[]const u8 {
        if (!self.has_credit_id) return null;
        return self.credit_id_buffer[0..self.credit_id_len];
    }

    fn isIdle(self: *const Worker) bool {
        return self.state == .idle;
    }

    fn activeChannel(self: *Worker) *CodexChannel {
        return self.external_channel orelse &self.channel;
    }

    fn run(io: std.Io, done: *std.Io.Event, self: *Worker) void {
        defer done.set(io);
        self.result = switch (self.kind) {
            .codex_refresh, .reset_preflight, .reset_post_read => self.runCodexRead(),
            .login => self.runLogin(),
            .reset_consume => self.runConsume(),
        };
    }

    fn runCodexRead(self: *Worker) JobResult {
        const channel = self.activeChannel();
        if (!channel.isBound()) {
            self.codex_launcher.open(self.home.slice(), channel) catch |err| {
                return .{ .rejected = launchCode(err) };
            };
        }
        const adapter: codex.Adapter = .{ .config = self.codex_config };
        const outcome = adapter.refresh(&channel.connection, &self.codex_workspace, .{
            .account_id = self.accountId(),
            .now_unix_s = self.now_unix_s,
        });

        if (self.external_channel == null) channel.close();
        return .{ .codex = outcome };
    }

    fn runLogin(self: *Worker) JobResult {
        self.login_launcher.open(&self.login_spec, &self.login_channel) catch {
            return .{ .login = login_runtime.spawnFailedStatus(self.provider, self.accountId()) };
        };
        var runner: login_runtime.Runner = .init(
            self.login_channel.handle,
            &self.login_scan,
            self.provider,
            self.accountId(),
        );
        const status = runner.run(.{
            .timeout_ms = self.login_options.timeout_ms,
            .max_output_bytes = self.login_options.max_output_bytes,
        });

        self.login_channel.release();
        return .{ .login = status };
    }

    fn runConsume(self: *Worker) JobResult {
        const channel = self.activeChannel();
        if (!channel.isBound()) {
            return .{ .consume = .{ .rejected = .{
                .kind = .provider_unavailable,
                .public_code = codex.public_code_app_server_closed,
                .retryable = true,
            } } };
        }
        const adapter: codex.Adapter = .{ .config = self.codex_config };
        const outcome = adapter.consumeResetCredit(&channel.connection, &self.codex_workspace, .{
            .account_id = self.accountId(),
            .attempt = &self.attempt,
            .credit_id = self.creditId(),
            .now_unix_s = self.now_unix_s,
        });
        return .{ .consume = outcome };
    }
};

const empty_attempt: domain.ResetAttempt = .{
    .idempotency_key = "",
    .account_id = "",
    .selected_credit_id = null,
    .created_at_unix_s = 0,
    .updated_at_unix_s = 0,
    .preflight_observed_at_unix_s = 0,
    .preflight_available_count = 0,
    .confirmed_at_unix_s = 0,
};

fn launchCode(err: LaunchError) []const u8 {
    return switch (err) {
        error.Unsupported => codex.public_code_app_server_unavailable,
        error.InvalidHome, error.EnvironmentFailed => coordinator.public_code_account_home_invalid,
        error.SpawnFailed => codex.public_code_app_server_unavailable,
    };
}

pub fn start(io: std.Io, worker: *Worker) bool {
    worker.done = .unset;
    worker.result = .none;
    worker.future = io.concurrent(Worker.run, .{ io, &worker.done, worker }) catch {
        return false;
    };
    worker.started = true;
    worker.state = .running;
    return true;
}

pub fn release(worker: *Worker) void {
    if (worker.external_channel == null) worker.channel.close();
    worker.external_channel = null;
    worker.login_channel.release();
    worker.result = .none;
    worker.state = .idle;
}

pub fn free(workers: *[max_workers]Worker) ?usize {
    for (workers, 0..) |*worker, index| {
        if (worker.isIdle()) return index;
    }
    return null;
}

pub fn busyCount(workers: *const [max_workers]Worker) usize {
    var count: usize = 0;
    for (workers) |*worker| {
        if (!worker.isIdle()) count += 1;
    }
    return count;
}

pub fn cancelAndJoin(io: std.Io, worker: *Worker) void {
    if (worker.state == .running and worker.started) {
        _ = worker.future.cancel(io);
        worker.started = false;
    }
    worker.state = .idle;
    worker.channel.close();
    worker.login_channel.release();
}

pub fn codexObservation(worker: *Worker, now_unix_s: i64) ?coordinator.Observation {
    const outcome = switch (worker.result) {
        .codex => |value| value,
        else => return null,
    };
    if (outcome.hasObservation()) {
        return .{ .supported = .{
            .status = outcome.status,
            .observed_at_unix_s = now_unix_s,
            .windows = outcome.windows,
            .reset_credits = outcome.reset_credits,
            .partial_failure = outcome.failure,
        } };
    }
    return .{ .failure = .{
        .failure = outcome.failure orelse .{
            .kind = .provider_unavailable,
            .public_code = codex.public_code_usage_unsupported,
            .retryable = true,
        },
        .observed_at_unix_s = now_unix_s,
    } };
}

pub fn rejectionCode(worker: *const Worker) []const u8 {
    return switch (worker.result) {
        .rejected => |code| code,
        else => coordinator.public_code_refresh_failed,
    };
}
