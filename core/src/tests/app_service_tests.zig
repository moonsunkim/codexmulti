const std = @import("std");

const account_registry = @import("../account_registry.zig");
const app_service = @import("../app_service.zig");
const coordinator = @import("../coordinator.zig");
const domain = @import("../domain.zig");
const keychain = @import("../keychain.zig");
const login_runtime = @import("../login_runtime.zig");
const proxy_control = @import("../proxy_control_client.zig");
const proxy_import = @import("../proxy_import_runner.zig");
const keychain_test_support = @import("keychain_test_support.zig");
const runtime_paths = @import("../runtime_paths.zig");
const store = @import("../store.zig");
const transport = @import("../process_jsonl.zig");
const ui_model = @import("../ui_model.zig");
const codex = @import("../providers/codex.zig");
const protocol = @import("codex_protocol_test_fixtures.zig");

const testing = std.testing;

const now: i64 = 2_000_000_000;

const home_dir = "/demo/home/demo-user";
const app_root = home_dir ++ "/Library/Application Support/" ++ runtime_paths.app_data_directory_name;
const accounts_root = app_root ++ "/accounts";

const codex_account_id = "acct-codex-demo";
const claude_account_id = "acct-claude-demo";
const codex_storage_key = "codex-demo";
const claude_storage_key = "claude-demo";
const move_alpha_id = "acct-codex-alpha";
const move_beta_id = "acct-codex-beta";
const move_gamma_id = "acct-codex-gamma";
const codex_home = accounts_root ++ "/" ++ codex_storage_key ++ "/codex";
const claude_config_dir = accounts_root ++ "/" ++ claude_storage_key ++ "/claude";

const codex_executable = "/demo/bin/codex";

const canary_access = "demo-access-placeholder-1111";
const canary_refresh = "demo-refresh-placeholder-0000";
const codex_auth_backup_bytes =
    "{\"auth_mode\":\"chatgpt\",\"tokens\":{\"access_token\":\"demo-auth-backup-access\",\"refresh_token\":\"demo-auth-backup-refresh\"}}\n";
const rotated_codex_auth_backup_bytes =
    "{\"auth_mode\":\"chatgpt\",\"tokens\":{\"access_token\":\"demo-auth-rotated-access\",\"refresh_token\":\"demo-auth-rotated-refresh-chain\"}}\n";

const frame = protocol.frame;
const resultFrame = protocol.resultFrame;

const initialize_result = "{\"userAgent\":\"codex-demo/0.0\",\"codexHome\":\"" ++ codex_home ++ "\"}";
const account_result = "{\"account\":{\"type\":\"chatgpt\",\"email\":\"demo-user@example.invalid\",\"planType\":\"pro\"}}";
const plus_account_result = "{\"account\":{\"type\":\"chatgpt\",\"email\":\"demo-user@example.invalid\",\"planType\":\"plus\"}}";
const rate_limits_result =
    "{\"rateLimits\":{\"primary\":{\"usedPercent\":24,\"windowDurationMins\":300,\"resetsAt\":2000003600}," ++
    "\"secondary\":{\"usedPercent\":61,\"windowDurationMins\":10080,\"resetsAt\":2000600000}}," ++
    "\"rateLimitResetCredits\":{\"availableCount\":2,\"credits\":[" ++
    "{\"id\":\"credit-demo-b\",\"description\":\"Later reset\",\"expiresAt\":2000600000}," ++
    "{\"id\":\"credit-demo-a\",\"description\":\"Earlier reset\",\"expiresAt\":2000300000}]}}";
const rate_limits_single_credit_result =
    "{\"rateLimits\":{\"primary\":{\"usedPercent\":24,\"windowDurationMins\":300,\"resetsAt\":2000003600}}," ++
    "\"rateLimitResetCredits\":{\"availableCount\":1}}";
const rate_limits_no_credit_result =
    "{\"rateLimits\":{\"primary\":{\"usedPercent\":9,\"windowDurationMins\":300,\"resetsAt\":2000003600}}}";
const rate_limits_exhausted_result =
    "{\"rateLimits\":{\"primary\":{\"usedPercent\":100,\"windowDurationMins\":300,\"resetsAt\":2000003600}," ++
    "\"secondary\":{\"usedPercent\":100,\"windowDurationMins\":10080,\"resetsAt\":2000600000}}}";
const rate_limits_after_weekly_reset_result =
    "{\"rateLimits\":{\"primary\":{\"usedPercent\":12,\"windowDurationMins\":300,\"resetsAt\":2000003600}," ++
    "\"secondary\":{\"usedPercent\":16,\"windowDurationMins\":10080,\"resetsAt\":2000600000}}}";
const rate_limits_session_exhausted_weekly_available_result =
    "{\"rateLimits\":{\"primary\":{\"usedPercent\":100,\"windowDurationMins\":300,\"resetsAt\":2000003600}," ++
    "\"secondary\":{\"usedPercent\":20,\"windowDurationMins\":10080,\"resetsAt\":2000600000}}}";
const rate_limits_plus_session_available_result =
    "{\"rateLimits\":{\"primary\":{\"usedPercent\":90,\"windowDurationMins\":300,\"resetsAt\":2000003600}," ++
    "\"secondary\":{\"usedPercent\":20,\"windowDurationMins\":10080,\"resetsAt\":2000600000}}}";
const rate_limits_plus_weekly_exhausted_result =
    "{\"rateLimits\":{\"primary\":{\"usedPercent\":10,\"windowDurationMins\":300,\"resetsAt\":2000003600}," ++
    "\"secondary\":{\"usedPercent\":100,\"windowDurationMins\":10080,\"resetsAt\":2000600000}}}";

fn readScriptForAccount(comptime first_id: u8, comptime account: []const u8, comptime limits: []const u8) []const u8 {
    const a = std.fmt.comptimePrint("{d}", .{first_id});
    const b = std.fmt.comptimePrint("{d}", .{first_id + 1});
    const c = std.fmt.comptimePrint("{d}", .{first_id + 2});
    return resultFrame(a, initialize_result) ++ resultFrame(b, account) ++ resultFrame(c, limits);
}

fn readScript(comptime first_id: u8, comptime limits: []const u8) []const u8 {
    return readScriptForAccount(first_id, account_result, limits);
}

fn consumeScript(comptime first_id: u8, comptime outcome: []const u8) []const u8 {
    const a = std.fmt.comptimePrint("{d}", .{first_id});
    return resultFrame(a, "{\"outcome\":\"" ++ outcome ++ "\"}");
}

fn postReadScript(comptime first_id: u8, comptime limits: []const u8) []const u8 {
    const a = std.fmt.comptimePrint("{d}", .{first_id});
    const b = std.fmt.comptimePrint("{d}", .{first_id + 1});
    return resultFrame(a, account_result) ++ resultFrame(b, limits);
}

const script_read = readScript(1, rate_limits_result);
const script_read_single_credit = readScript(1, rate_limits_single_credit_result);
const script_read_no_credit = readScript(1, rate_limits_no_credit_result);
const script_read_exhausted = readScript(1, rate_limits_exhausted_result);
const script_read_after_weekly_reset = readScript(1, rate_limits_after_weekly_reset_result);
const script_read_pro_session_exhausted_weekly_available = readScript(1, rate_limits_session_exhausted_weekly_available_result);
const script_read_plus_session_available = readScriptForAccount(1, plus_account_result, rate_limits_plus_session_available_result);
const script_read_plus_weekly_exhausted = readScriptForAccount(1, plus_account_result, rate_limits_plus_weekly_exhausted_result);

const script_reset_transaction = readScript(1, rate_limits_result) ++
    consumeScript(4, "reset") ++
    postReadScript(5, rate_limits_no_credit_result);

const script_reset_ambiguous = readScript(1, rate_limits_result) ++
    frame("{\"jsonrpc\":\"2.0\",\"id\":4,\"error\":{\"code\":-32603,\"message\":\"demo-detail-should-not-leak\"}}") ++
    postReadScript(5, rate_limits_single_credit_result);

const script_reset_reconcile = readScript(1, rate_limits_single_credit_result) ++
    consumeScript(4, "alreadyRedeemed") ++
    postReadScript(5, rate_limits_no_credit_result);

const RecordingSink = struct {
    const max_records: usize = 48;
    const max_bytes: usize = 64 * 1024;

    const Record = struct { kind: runtime_paths.DocumentKind, start: usize, len: usize };

    records: [max_records]Record = @splat(.{ .kind = .registry, .start = 0, .len = 0 }),
    record_count: usize = 0,
    bytes: [max_bytes]u8 = @splat(0),
    bytes_len: usize = 0,

    const vtable: coordinator.DocumentSink.VTable = .{ .write = write };

    fn sink(self: *RecordingSink) coordinator.DocumentSink {
        return .{ .context = self, .vtable = &vtable };
    }

    fn write(context: *anyopaque, kind: runtime_paths.DocumentKind, bytes: []const u8) coordinator.SinkError!void {
        const self: *RecordingSink = @ptrCast(@alignCast(context));
        if (self.record_count == max_records) return error.TooLarge;
        if (bytes.len > max_bytes - self.bytes_len) return error.TooLarge;
        const start = self.bytes_len;
        @memcpy(self.bytes[start..][0..bytes.len], bytes);
        self.bytes_len += bytes.len;
        self.records[self.record_count] = .{ .kind = kind, .start = start, .len = bytes.len };
        self.record_count += 1;
    }

    fn countOf(self: *const RecordingSink, kind: runtime_paths.DocumentKind) usize {
        var count: usize = 0;
        for (self.records[0..self.record_count]) |record| {
            if (record.kind == kind) count += 1;
        }
        return count;
    }

    fn lastOf(self: *const RecordingSink, kind: runtime_paths.DocumentKind) ?[]const u8 {
        var index = self.record_count;
        while (index > 0) {
            index -= 1;
            const record = self.records[index];
            if (record.kind == kind) return self.bytes[record.start..][0..record.len];
        }
        return null;
    }

    fn allBytes(self: *const RecordingSink) []const u8 {
        return self.bytes[0..self.bytes_len];
    }
};

const RecordingDirectories = struct {
    const max_paths: usize = 32;

    ensured: [max_paths][runtime_paths.max_path_bytes]u8 = @splat(@splat(0)),
    ensured_len: [max_paths]usize = @splat(0),
    ensured_count: usize = 0,
    removed: [max_paths][runtime_paths.max_path_bytes]u8 = @splat(@splat(0)),
    removed_len: [max_paths]usize = @splat(0),
    removed_count: usize = 0,
    fail_ensure: bool = false,

    const vtable: app_service.Directories.VTable = .{ .ensure = ensure, .remove = remove };

    fn directories(self: *RecordingDirectories) app_service.Directories {
        return .{ .context = self, .vtable = &vtable };
    }

    fn ensure(context: *anyopaque, path: []const u8) app_service.DirectoryError!void {
        const self: *RecordingDirectories = @ptrCast(@alignCast(context));
        if (self.fail_ensure) return error.Denied;
        if (self.ensured_count == max_paths) return error.Io;
        const take = @min(path.len, runtime_paths.max_path_bytes);
        @memcpy(self.ensured[self.ensured_count][0..take], path[0..take]);
        self.ensured_len[self.ensured_count] = take;
        self.ensured_count += 1;
    }

    fn remove(context: *anyopaque, path: []const u8) app_service.DirectoryError!void {
        const self: *RecordingDirectories = @ptrCast(@alignCast(context));
        if (self.removed_count == max_paths) return error.Io;
        const take = @min(path.len, runtime_paths.max_path_bytes);
        @memcpy(self.removed[self.removed_count][0..take], path[0..take]);
        self.removed_len[self.removed_count] = take;
        self.removed_count += 1;
    }

    fn ensuredAt(self: *const RecordingDirectories, index: usize) []const u8 {
        return self.ensured[index][0..self.ensured_len[index]];
    }

    fn removedAt(self: *const RecordingDirectories, index: usize) []const u8 {
        return self.removed[index][0..self.removed_len[index]];
    }

    fn ensuredContains(self: *const RecordingDirectories, path: []const u8) bool {
        var index: usize = 0;
        while (index < self.ensured_count) : (index += 1) {
            if (std.mem.eql(u8, self.ensuredAt(index), path)) return true;
        }
        return false;
    }
};

const CountingKeys = struct {
    next_value: u32 = 1,
    calls: usize = 0,

    const vtable: app_service.KeySource.VTable = .{ .next = next };

    fn source(self: *CountingKeys) app_service.KeySource {
        return .{ .context = self, .vtable = &vtable };
    }

    fn next(context: *anyopaque, out: []u8) usize {
        const self: *CountingKeys = @ptrCast(@alignCast(context));
        self.calls += 1;
        const text = std.fmt.bufPrint(out, "{x:0>8}", .{self.next_value}) catch return 0;
        self.next_value += 1;
        return text.len;
    }
};

const ScriptedCodexLauncher = struct {
    stream: transport.FakeStream = .{},

    custom_stream: ?transport.Stream = null,
    lifecycle: transport.FakeChildLifecycle = .{},
    opens: usize = 0,
    last_home: [runtime_paths.max_path_bytes]u8 = @splat(0),
    last_home_len: usize = 0,
    failure: ?app_service.LaunchError = null,

    const vtable: app_service.CodexLauncher.VTable = .{ .open = open };
    const lifecycle_vtable: coordinator.ChildLifecycle.VTable = .{ .close = closeLifecycle };

    fn launcher(self: *ScriptedCodexLauncher) app_service.CodexLauncher {
        return .{ .context = self, .vtable = &vtable };
    }

    fn open(context: *anyopaque, home: []const u8, channel: *app_service.CodexChannel) app_service.LaunchError!void {
        const self: *ScriptedCodexLauncher = @ptrCast(@alignCast(context));
        if (self.failure) |err| return err;
        self.opens += 1;
        const take = @min(home.len, runtime_paths.max_path_bytes);
        @memcpy(self.last_home[0..take], home[0..take]);
        self.last_home_len = take;
        channel.bind(self.custom_stream orelse self.stream.stream(), .{ .context = self, .vtable = &lifecycle_vtable });
    }

    fn closeLifecycle(context: *anyopaque) void {
        const self: *ScriptedCodexLauncher = @ptrCast(@alignCast(context));
        self.lifecycle.close();
    }

    fn homePath(self: *const ScriptedCodexLauncher) []const u8 {
        return self.last_home[0..self.last_home_len];
    }

    fn writtenBytes(self: *const ScriptedCodexLauncher) []const u8 {
        return self.stream.writtenBytes();
    }
};

const StatefulAppServer = struct {
    const queue_bytes: usize = 16 * 1024;

    initialized: bool = false,
    consumed: bool = false,
    initialize_requests: usize = 0,
    consume_requests: usize = 0,
    line: [transport.max_request_bytes]u8 = @splat(0),
    line_len: usize = 0,
    queue: [queue_bytes]u8 = @splat(0),
    queue_head: usize = 0,
    queue_len: usize = 0,
    arm_count: usize = 0,

    const vtable: transport.Stream.VTable = .{ .arm = arm, .read = read, .write = write };

    fn stream(self: *StatefulAppServer) transport.Stream {
        return .{ .context = self, .vtable = &vtable };
    }

    fn arm(context: *anyopaque, _: u32) void {
        const self: *StatefulAppServer = @ptrCast(@alignCast(context));
        self.arm_count += 1;
    }

    fn read(context: *anyopaque, buffer: []u8) transport.TransportError!usize {
        const self: *StatefulAppServer = @ptrCast(@alignCast(context));
        if (self.queue_len == 0) return error.EndOfStream;
        const count = @min(buffer.len, self.queue_len);
        @memcpy(buffer[0..count], self.queue[self.queue_head..][0..count]);
        self.queue_head += count;
        self.queue_len -= count;
        if (self.queue_len == 0) self.queue_head = 0;
        return count;
    }

    fn write(context: *anyopaque, bytes: []const u8) transport.TransportError!void {
        const self: *StatefulAppServer = @ptrCast(@alignCast(context));
        for (bytes) |byte| {
            if (byte == '\n') {
                self.handle(self.line[0..self.line_len]);
                self.line_len = 0;
                continue;
            }
            if (self.line_len >= self.line.len) return error.Io;
            self.line[self.line_len] = byte;
            self.line_len += 1;
        }
    }

    fn handle(self: *StatefulAppServer, line: []const u8) void {
        const method = methodOf(line) orelse return;
        const id = idOf(line);
        if (std.mem.eql(u8, method, codex.method_initialize)) {
            self.initialize_requests += 1;
            if (self.initialized) {
                self.reply(id, "error", "{\"code\":-32600,\"message\":\"Already initialized\"}");
                return;
            }
            self.initialized = true;
            self.reply(id, "result", initialize_result);
            return;
        }
        if (std.mem.eql(u8, method, codex.method_initialized)) return;
        if (std.mem.eql(u8, method, codex.method_account_read)) {
            self.reply(id, "result", account_result);
            return;
        }
        if (std.mem.eql(u8, method, codex.method_rate_limits_read)) {
            self.reply(id, "result", if (self.consumed) rate_limits_no_credit_result else rate_limits_result);
            return;
        }
        if (std.mem.eql(u8, method, codex.method_reset_credit_consume)) {
            self.consume_requests += 1;
            self.consumed = true;
            self.reply(id, "result", "{\"outcome\":\"reset\"}");
            return;
        }
    }

    fn reply(self: *StatefulAppServer, id: i64, key: []const u8, body: []const u8) void {
        var scratch: [4 * 1024]u8 = undefined;
        const text = std.fmt.bufPrint(&scratch, "{{\"jsonrpc\":\"2.0\",\"id\":{d},\"{s}\":{s}}}\n", .{ id, key, body }) catch return;
        if (text.len > self.queue.len - (self.queue_head + self.queue_len)) return;
        @memcpy(self.queue[self.queue_head + self.queue_len ..][0..text.len], text);
        self.queue_len += text.len;
    }

    fn methodOf(line: []const u8) ?[]const u8 {
        const marker = "\"method\":\"";
        const start = std.mem.indexOf(u8, line, marker) orelse return null;
        const rest = line[start + marker.len ..];
        const end = std.mem.indexOfScalar(u8, rest, '"') orelse return null;
        return rest[0..end];
    }

    fn idOf(line: []const u8) i64 {
        const marker = "\"id\":";
        const start = std.mem.indexOf(u8, line, marker) orelse return 0;
        const rest = line[start + marker.len ..];
        var end: usize = 0;
        while (end < rest.len and rest[end] >= '0' and rest[end] <= '9') : (end += 1) {}
        return std.fmt.parseInt(i64, rest[0..end], 10) catch 0;
    }
};

const FakeLoginChild = struct {
    lines: []const []const u8 = &.{},
    index: usize = 0,
    offset: usize = 0,
    closes: usize = 0,
    arms: usize = 0,
    exit_state: login_runtime.Exit = .success,

    const vtable: login_runtime.Child.VTable = .{
        .arm = arm,
        .read = read,
        .close = close,
        .exit = exitOf,
    };

    fn handle(self: *FakeLoginChild) login_runtime.Child {
        return .{ .context = self, .vtable = &vtable };
    }

    fn arm(context: *anyopaque, _: u32) void {
        const self: *FakeLoginChild = @ptrCast(@alignCast(context));
        self.arms += 1;
    }

    fn read(context: *anyopaque, buffer: []u8) login_runtime.ChildError!usize {
        const self: *FakeLoginChild = @ptrCast(@alignCast(context));
        if (self.index >= self.lines.len) return error.EndOfOutput;
        const line = self.lines[self.index];
        const rest = line[self.offset..];
        const count = @min(rest.len, buffer.len);
        @memcpy(buffer[0..count], rest[0..count]);
        self.offset += count;
        if (self.offset == line.len) {
            self.index += 1;
            self.offset = 0;
        }
        return count;
    }

    fn close(context: *anyopaque) void {
        const self: *FakeLoginChild = @ptrCast(@alignCast(context));
        self.closes += 1;
    }

    fn exitOf(context: *anyopaque) login_runtime.Exit {
        const self: *FakeLoginChild = @ptrCast(@alignCast(context));
        return self.exit_state;
    }
};

const ScriptedLoginLauncher = struct {
    lines: []const []const u8 = &.{},
    auth_bytes: ?[]const u8 = null,
    child: FakeLoginChild = .{},
    opens: usize = 0,
    last_argv0: [runtime_paths.max_path_bytes]u8 = @splat(0),
    last_argv0_len: usize = 0,
    last_home: [runtime_paths.max_path_bytes]u8 = @splat(0),
    last_home_len: usize = 0,
    failure: ?app_service.LaunchError = null,

    const vtable: app_service.LoginLauncher.VTable = .{ .open = open };

    fn launcher(self: *ScriptedLoginLauncher) app_service.LoginLauncher {
        return .{ .context = self, .vtable = &vtable };
    }

    fn open(
        context: *anyopaque,
        spec: *const coordinator.LoginSpec,
        channel: *app_service.LoginChannel,
    ) app_service.LaunchError!void {
        const self: *ScriptedLoginLauncher = @ptrCast(@alignCast(context));
        if (self.failure) |err| return err;
        self.opens += 1;
        const argv = spec.argv();
        const take = @min(argv[0].len, runtime_paths.max_path_bytes);
        @memcpy(self.last_argv0[0..take], argv[0][0..take]);
        self.last_argv0_len = take;
        const home = spec.homeValue() orelse "";
        const home_take = @min(home.len, runtime_paths.max_path_bytes);
        @memcpy(self.last_home[0..home_take], home[0..home_take]);
        self.last_home_len = home_take;

        if (self.auth_bytes) |bytes| {
            var path_buffer: [runtime_paths.max_path_bytes]u8 = undefined;
            const path = std.fmt.bufPrint(&path_buffer, "{s}/{s}", .{ home, runtime_paths.codex_auth_file_name }) catch
                return error.InvalidHome;
            var file = std.Io.Dir.cwd().createFile(testing.io, path, .{
                .permissions = std.Io.File.Permissions.fromMode(0o600),
            }) catch return error.SpawnFailed;
            file.writeStreamingAll(testing.io, bytes) catch {
                file.close(testing.io);
                return error.SpawnFailed;
            };
            file.close(testing.io);
        }

        self.child = .{ .lines = self.lines };
        channel.bind(self.child.handle());
    }

    fn argv0(self: *const ScriptedLoginLauncher) []const u8 {
        return self.last_argv0[0..self.last_argv0_len];
    }

    fn homePath(self: *const ScriptedLoginLauncher) []const u8 {
        return self.last_home[0..self.last_home_len];
    }
};

const Harness = struct {
    core: *coordinator.Coordinator,
    service: *app_service.Service,
    sink: RecordingSink = .{},
    directories: RecordingDirectories = .{},
    keys: CountingKeys = .{},
    credentials: keychain.MemoryStore = .{},
    codex_launcher: ScriptedCodexLauncher = .{},
    login_launcher: ScriptedLoginLauncher = .{},
    proxy_exchange: FakeProxyExchange = .{},
    proxy_importer: FakeProxyImporter = .{},
    proxy_node_resolver: FakeProxyNodeResolver = .{},

    parent_env: []const transport.EnvVar = &.{},

    fn create() !*Harness {
        const layout = try runtime_paths.Layout.fromHomeDir(home_dir);
        return createWithLayout(layout);
    }

    fn createWithLayout(layout: runtime_paths.Layout) !*Harness {
        const core = try coordinator.Coordinator.create(testing.allocator, .{
            .layout = layout,
            .target = .{
                .codex_executable = codex_executable,
            },
        });
        errdefer core.destroy();

        const self = try testing.allocator.create(Harness);
        self.* = .{
            .core = core,
            .service = try app_service.Service.create(testing.allocator, core),
        };
        return self;
    }

    fn destroy(self: *Harness) void {
        self.service.destroy();
        self.core.destroy();
        self.credentials.deinit();
        testing.allocator.destroy(self);
    }

    fn live(self: *Harness) app_service.Live {
        return .{
            .io = testing.io,
            .allocator = testing.allocator,
            .sink = self.sink.sink(),
            .credentials = self.credentials.store(),
            .codex_launcher = self.codex_launcher.launcher(),
            .login_launcher = self.login_launcher.launcher(),
            .directories = self.directories.directories(),
            .keys = self.keys.source(),
            .parent_env = .{ .pairs = self.parent_env },
            .proxy_exchange = self.proxy_exchange.exchange(),
            .proxy_importer = self.proxy_importer.runner(),
            .proxy_node_resolver = self.proxy_node_resolver.resolver(),
        };
    }

    fn attach(self: *Harness) void {
        self.service.attach(self.live());
        self.service.now_unix_s = now;
    }

    fn addCodex(self: *Harness) !void {
        _ = try self.core.addAccount(.{
            .id = codex_account_id,
            .provider = .codex,
            .label = "Codex Demo",
            .storage_key = codex_storage_key,
            .created_at_unix_s = now - 1000,
        });
        _ = try self.core.registry.markConnected(codex_account_id, null);
    }

    fn addClaude(self: *Harness) !void {
        _ = try self.core.addAccount(.{
            .id = claude_account_id,
            .provider = .claude,
            .label = "Claude Demo",
            .storage_key = claude_storage_key,
            .created_at_unix_s = now - 1000,
        });
        _ = try self.core.registry.markConnected(claude_account_id, null);
    }

    fn drain(self: *Harness) !void {
        var spins: usize = 0;
        while (true) {
            self.service.pump(now);
            if (self.service.busyWorkerCount() == 0 and self.core.schedulerIsIdle() and !self.service.proxyWorkerBusy()) break;
            spins += 1;
            if (spins > 4000) return error.WorkerDidNotFinish;
            testing.io.sleep(.fromMilliseconds(1), .awake) catch {};
        }
    }

    fn drainAll(self: *Harness) !void {
        return self.drainAllAt(now);
    }

    fn drainAllAt(self: *Harness, at_unix_s: i64) !void {
        var spins: usize = 0;
        while (true) {
            self.service.pump(at_unix_s);
            if (self.service.busyWorkerCount() == 0 and !self.service.proxyWorkerBusy()) break;
            spins += 1;
            if (spins > 4000) return error.WorkerDidNotFinish;
            testing.io.sleep(.fromMilliseconds(1), .awake) catch {};
        }
        self.service.pump(at_unix_s);
    }
};

fn addMoveAccount(harness: *Harness, id: []const u8, label: []const u8, storage_key: []const u8, created_at_unix_s: i64) !void {
    _ = try harness.core.addAccount(.{
        .id = id,
        .provider = .codex,
        .label = label,
        .storage_key = storage_key,
        .created_at_unix_s = created_at_unix_s,
    });
    _ = try harness.core.registry.markConnected(id, null);
}

fn addMoveAccounts(harness: *Harness) !void {
    try addMoveAccount(harness, move_alpha_id, "Alpha", "codex-alpha", now - 300);
    try addMoveAccount(harness, move_beta_id, "Beta", "codex-beta", now - 200);
    try addMoveAccount(harness, move_gamma_id, "Gamma", "codex-gamma", now - 100);
}

fn observeMoveAccount(core: *coordinator.Coordinator, id: []const u8, observed_at_unix_s: i64, label: []const u8) !void {
    const windows = [_]domain.UsageWindow{.{
        .kind = .weekly,
        .label = label,
        .used_percent = @intCast(@mod(observed_at_unix_s, 100)),
    }};
    _ = try core.requestRefresh(id);
    const ticket = core.nextOperation(observed_at_unix_s) orelse return error.MissingOperation;
    _ = try core.applyObservation(ticket, .{ .supported = .{
        .observed_at_unix_s = observed_at_unix_s,
        .windows = &windows,
    } }, observed_at_unix_s);
}

fn expectAccountOrder(core: *const coordinator.Coordinator, expected: []const []const u8) !void {
    try testing.expectEqual(expected.len, core.accountCount());
    for (expected, 0..) |id, index| try testing.expectEqualStrings(id, core.accountAt(index).?.id);
}

fn expectRegistryBytesOrder(bytes: []const u8, expected: []const []const u8) !void {
    var parsed = try std.json.parseFromSlice(
        account_registry.RegistryDocument,
        testing.allocator,
        bytes,
        .{ .allocate = .alloc_always },
    );
    defer parsed.deinit();
    try testing.expectEqual(expected.len, parsed.value.accounts.len);
    for (expected, 0..) |id, index| try testing.expectEqualStrings(id, parsed.value.accounts[index].id);
}

test "P6 appearance preference survives an app-owned document round trip" {
    var temp = testing.tmpDir(.{});
    defer temp.cleanup();

    const first = try Harness.create();
    defer first.destroy();
    var file_sink: coordinator.FileDocumentSink = .{ .io = testing.io, .dir = temp.dir };
    var first_live = first.live();
    first_live.sink = file_sink.sink();
    first.service.attach(first_live);
    first.service.now_unix_s = now;

    try testing.expectEqual(
        ui_model.CommandOutcome.accepted_pending,
        first.service.submit(.{ .set_appearance = .dark }),
    );
    var saved = try store.loadAppSettings(
        testing.allocator,
        testing.io,
        temp.dir,
        runtime_paths.app_settings_file_name,
    );
    defer saved.deinit();
    try testing.expectEqual(store.current_schema_version, saved.value.schema_version);
    try testing.expectEqual(store.Appearance.dark, saved.value.appearance);
    try testing.expectError(
        error.FileNotFound,
        temp.dir.statFile(testing.io, runtime_paths.app_settings_temp_file_name, .{}),
    );

    const restarted = try Harness.create();
    defer restarted.destroy();
    restarted.attach();
    _ = restarted.service.load(testing.io, temp.dir);
    var view: ui_model.ViewState = .{};
    view.begin(now, restarted.service.capabilities(), .kst);
    restarted.service.project(&view);
    view.finish(.{});
    try testing.expectEqual(ui_model.Appearance.dark, view.settings.appearance);
}

test "F18 language preference persists while system Korean reprojects without changing the selection" {
    var temp = testing.tmpDir(.{});
    defer temp.cleanup();

    const first = try Harness.create();
    defer first.destroy();
    var file_sink: coordinator.FileDocumentSink = .{ .io = testing.io, .dir = temp.dir };
    var first_live = first.live();
    first_live.sink = file_sink.sink();
    first.service.attach(first_live);
    first.service.now_unix_s = now;

    try testing.expectEqual(
        ui_model.CommandOutcome.accepted_pending,
        first.service.submit(.{ .set_language = .{ .value = .ko, .system = .en } }),
    );
    var saved_korean = try store.loadAppSettings(
        testing.allocator,
        testing.io,
        temp.dir,
        runtime_paths.app_settings_file_name,
    );
    defer saved_korean.deinit();
    try testing.expectEqual(store.Language.ko, saved_korean.value.language);

    try testing.expectEqual(
        ui_model.CommandOutcome.accepted_pending,
        first.service.submit(.{ .set_language = .{ .value = .system, .system = .ko } }),
    );
    var saved_system = try store.loadAppSettings(
        testing.allocator,
        testing.io,
        temp.dir,
        runtime_paths.app_settings_file_name,
    );
    defer saved_system.deinit();
    try testing.expectEqual(store.Language.system, saved_system.value.language);

    var view: ui_model.ViewState = .{};
    view.begin(now, first.service.capabilities(), .kst);
    first.service.project(&view);
    view.finish(.{});
    try testing.expectEqual(ui_model.Language.system, view.settings.language);
    try testing.expectEqualStrings("등록된 계정 없음", view.summary_text);
    try testing.expectEqualStrings("언어", view.settings.language_label);
}

test "Codex display settings survive an app-owned document round trip and project supported values" {
    var temp = testing.tmpDir(.{});
    defer temp.cleanup();

    const first = try Harness.create();
    defer first.destroy();
    var file_sink: coordinator.FileDocumentSink = .{ .io = testing.io, .dir = temp.dir };
    var first_live = first.live();
    first_live.sink = file_sink.sink();
    first.service.attach(first_live);
    first.service.now_unix_s = now;

    try testing.expectEqual(
        ui_model.CommandOutcome.accepted_pending,
        first.service.submit(.{ .set_codex_usage_window = .session }),
    );
    try testing.expectEqual(
        ui_model.CommandOutcome.accepted_pending,
        first.service.submit(.{ .set_codex_show_model_limits = true }),
    );
    var saved = try store.loadAppSettings(
        testing.allocator,
        testing.io,
        temp.dir,
        runtime_paths.app_settings_file_name,
    );
    defer saved.deinit();
    try testing.expectEqual(store.CodexUsageWindow.session, saved.value.codex_usage_window);
    try testing.expect(saved.value.codex_show_model_limits);

    const restarted = try Harness.create();
    defer restarted.destroy();
    restarted.attach();
    _ = restarted.service.load(testing.io, temp.dir);
    var view: ui_model.ViewState = .{};
    view.begin(now, restarted.service.capabilities(), .kst);
    restarted.service.project(&view);
    view.finish(.{});
    try testing.expectEqual(ui_model.CodexUsageWindow.session, view.settings.codex_usage_window);
    try testing.expect(view.settings.codex_show_model_limits);
    try testing.expectEqual(
        [3]ui_model.CodexUsageWindow{ .auto, .weekly, .session },
        view.settings.codex_usage_window_supported,
    );
    try testing.expectEqual([2]bool{ false, true }, view.settings.codex_show_model_limits_supported);
    try testing.expectEqualStrings("Codex", view.settings.codex_section_title);
    try testing.expectEqualStrings("Usage shown", view.settings.codex_usage_window_label);
    try testing.expectEqualStrings(
        "Prefer a usage window when the provider reports it.",
        view.settings.codex_usage_window_detail_text,
    );
    try testing.expectEqualStrings("Per-model limits", view.settings.codex_show_model_limits_label);
    try testing.expectEqualStrings(
        "Show reported model limits in account details and headlines.",
        view.settings.codex_show_model_limits_detail_text,
    );
}

test "C9 launch-at-login preference and shell registration failure survive an app-owned document round trip" {
    var temp = testing.tmpDir(.{});
    defer temp.cleanup();

    const first = try Harness.create();
    defer first.destroy();
    var file_sink: coordinator.FileDocumentSink = .{ .io = testing.io, .dir = temp.dir };
    var first_live = first.live();
    first_live.sink = file_sink.sink();
    first.service.attach(first_live);
    first.service.now_unix_s = now;

    try testing.expectEqual(
        ui_model.CommandOutcome.accepted_pending,
        first.service.submit(.{ .set_launch_at_login = true }),
    );
    try testing.expectEqual(
        ui_model.CommandOutcome.accepted_pending,
        first.service.submit(.{ .report_launch_at_login_registration_failure = true }),
    );

    var saved = try store.loadAppSettings(
        testing.allocator,
        testing.io,
        temp.dir,
        runtime_paths.app_settings_file_name,
    );
    defer saved.deinit();
    try testing.expect(saved.value.launch_at_login);
    try testing.expect(saved.value.launch_at_login_registration_failed);

    const restarted = try Harness.create();
    defer restarted.destroy();
    restarted.attach();
    _ = restarted.service.load(testing.io, temp.dir);
    var view: ui_model.ViewState = .{};
    view.begin(now, restarted.service.capabilities(), .kst);
    restarted.service.project(&view);
    view.finish(.{});
    try testing.expect(view.settings.launch_at_login);
    try testing.expect(view.settings.launch_at_login_registration_failed);

    try testing.expectEqual(
        ui_model.CommandOutcome.accepted_pending,
        restarted.service.submit(.{ .set_launch_at_login = false }),
    );
    view.begin(now, restarted.service.capabilities(), .kst);
    restarted.service.project(&view);
    view.finish(.{});
    try testing.expect(!view.settings.launch_at_login);
    try testing.expect(!view.settings.launch_at_login_registration_failed);
}

test "C9 auto-refresh setting accepts only the four policy values and projects honest traffic" {
    var temp = testing.tmpDir(.{});
    defer temp.cleanup();

    const harness = try Harness.create();
    defer harness.destroy();
    try harness.addCodex();
    var file_sink: coordinator.FileDocumentSink = .{ .io = testing.io, .dir = temp.dir };
    var live = harness.live();
    live.sink = file_sink.sink();
    harness.service.attach(live);
    harness.service.now_unix_s = now;

    try testing.expectEqual(
        ui_model.CommandOutcome.accepted_pending,
        harness.service.submit(.{ .set_auto_refresh = 15 }),
    );
    var saved = try store.loadAppSettings(testing.allocator, testing.io, temp.dir, runtime_paths.app_settings_file_name);
    defer saved.deinit();
    try testing.expectEqual(@as(u16, 15), saved.value.auto_refresh_minutes);

    var view: ui_model.ViewState = .{};
    view.begin(now, harness.service.capabilities(), .kst);
    harness.service.project(&view);
    view.finish(.{});
    try testing.expectEqual(@as(u16, 15), view.settings.auto_refresh_minutes);
    try testing.expect(std.mem.indexOf(u8, view.settings.auto_refresh_traffic_text, "1 account") != null);
    try testing.expect(std.mem.indexOf(u8, view.settings.auto_refresh_traffic_text, "4") != null);

    try testing.expectEqual(
        ui_model.CommandOutcome.rejected_not_allowed,
        harness.service.submit(.{ .set_auto_refresh = 17 }),
    );
    view.begin(now, harness.service.capabilities(), .kst);
    harness.service.project(&view);
    view.finish(.{});
    try testing.expectEqual(@as(u16, 15), view.settings.auto_refresh_minutes);
}

test "C9 auto-refresh pump stays idle before the interval and starts the shared refresh when due" {
    const harness = try Harness.create();
    defer harness.destroy();
    try harness.addCodex();
    harness.parent_env = &proxy_env;
    const proxy_replies = [_]FakeProxyExchange.Reply{
        .{ .status = 200, .body = proxy_ready_status_v2 },
        .{ .status = 200, .body = proxy_ready_status_v2 },
    };
    harness.proxy_exchange.replies = &proxy_replies;
    harness.attach();
    try saveProxySettings(harness);

    harness.codex_launcher.stream = .{ .chunks = &.{.{ .bytes = script_read }} };
    try testing.expectEqual(ui_model.CommandOutcome.accepted_pending, harness.service.submit(.refresh_all));
    try harness.drainAllAt(now);
    try testing.expectEqual(@as(usize, 1), harness.codex_launcher.opens);

    try testing.expectEqual(
        ui_model.CommandOutcome.accepted_pending,
        harness.service.submit(.{ .set_auto_refresh = 15 }),
    );
    harness.codex_launcher.stream = .{ .chunks = &.{.{ .bytes = script_read }} };
    harness.codex_launcher.lifecycle = .{};

    harness.service.pump(now + 15 * 60 - 1);
    try testing.expectEqual(@as(usize, 1), harness.codex_launcher.opens);

    harness.service.pump(now + 15 * 60);
    var spins: usize = 0;
    while (harness.codex_launcher.opens != 2) {
        harness.service.pump(now + 15 * 60);
        spins += 1;
        if (spins > 4000) return error.AutoRefreshDidNotStart;
        testing.io.sleep(.fromMilliseconds(1), .awake) catch {};
    }
    try harness.drainAllAt(now + 15 * 60);
    try testing.expectEqual(@as(usize, 2), harness.codex_launcher.opens);
    try testing.expectEqual(@as(usize, 2), harness.proxy_exchange.calls);
}

const FakeProxyExchange = struct {
    const Reply = struct { status: u16, body: []const u8 };

    replies: []const Reply = &.{},
    reply_index: usize = 0,
    calls: usize = 0,
    block_until_canceled: bool = false,
    io: std.Io = testing.io,
    last_path: [proxy_control.max_request_path_bytes]u8 = @splat(0),
    last_path_len: usize = 0,
    paths: [8][proxy_control.max_request_path_bytes]u8 = @splat(@splat(0)),
    path_lens: [8]usize = @splat(0),

    const vtable: proxy_control.Exchange.VTable = .{ .perform = perform };

    fn exchange(self: *FakeProxyExchange) proxy_control.Exchange {
        return .{ .context = self, .vtable = &vtable };
    }

    fn perform(context: *anyopaque, request: proxy_control.Request, response_buffer: []u8) proxy_control.TransportError!proxy_control.ExchangeResult {
        const self: *FakeProxyExchange = @ptrCast(@alignCast(context));
        self.calls += 1;
        self.last_path_len = request.path.len;
        @memcpy(self.last_path[0..request.path.len], request.path);
        if (self.calls <= self.paths.len) {
            self.path_lens[self.calls - 1] = request.path.len;
            @memcpy(self.paths[self.calls - 1][0..request.path.len], request.path);
        }
        if (self.block_until_canceled) {
            while (true) self.io.sleep(.fromSeconds(1), .awake) catch return error.Canceled;
        }
        if (self.reply_index >= self.replies.len) return error.Network;
        const reply = self.replies[self.reply_index];
        self.reply_index += 1;
        if (reply.body.len > response_buffer.len) return error.ResponseTooLarge;
        @memcpy(response_buffer[0..reply.body.len], reply.body);
        return .{ .status = reply.status, .body_len = reply.body.len };
    }

    fn lastPath(self: *const FakeProxyExchange) []const u8 {
        return self.last_path[0..self.last_path_len];
    }

    fn pathAt(self: *const FakeProxyExchange, index: usize) []const u8 {
        return self.paths[index][0..self.path_lens[index]];
    }
};

const FakeProxyImporter = struct {
    calls: usize = 0,
    outcome: proxy_import.Outcome = .success,

    const vtable: proxy_import.Runner.VTable = .{ .run = run };

    fn runner(self: *FakeProxyImporter) proxy_import.Runner {
        return .{ .context = self, .vtable = &vtable };
    }

    fn run(context: *anyopaque, _: proxy_import.Request) proxy_import.Outcome {
        const self: *FakeProxyImporter = @ptrCast(@alignCast(context));
        self.calls += 1;
        return self.outcome;
    }
};

const FakeProxyNodeResolver = struct {
    const vtable: proxy_import.NodeResolver.VTable = .{ .resolve = resolve };

    fn resolver(self: *FakeProxyNodeResolver) proxy_import.NodeResolver {
        return .{ .context = self, .vtable = &vtable };
    }

    fn resolve(_: *anyopaque, _: proxy_import.NodeSearch, out: *runtime_paths.Path) bool {
        out.* = runtime_paths.Path.init("/demo/bin/node") catch return false;
        return true;
    }
};

const proxy_config_path = home_dir ++ "/proxy/config.json";
const proxy_cli_path = home_dir ++ "/bin/codexmulti-proxy";
const proxy_auth_file = home_dir ++ "/Library/Application Support/" ++ runtime_paths.app_data_directory_name ++ "/accounts/" ++ codex_storage_key ++ "/codex/auth.json";
const proxy_env = [_]transport.EnvVar{
    .{ .name = "PATH", .value = "/usr/bin:/bin" },
    .{ .name = "HOME", .value = home_dir },
    .{ .name = "TMPDIR", .value = "/private/tmp" },
};

const proxy_cooldown_status_v2 =
    "{\"version\":2,\"config_path\":\"" ++ proxy_config_path ++
    "\",\"active\":null,\"cursor\":\"codex-1\",\"in_flight\":0,\"accounts\":[{" ++
    "\"name\":\"codex-1\",\"label\":\"Codex Demo\",\"auth_file\":\"" ++ proxy_auth_file ++
    "\",\"state\":\"COOLDOWN\",\"cooldown_until\":\"2033-06-01T00:01:02Z\",\"reason\":\"usage_limit_reached\",\"token_expires_at\":null,\"in_flight\":0}]}";

const proxy_expired_cooldown_status_v2 =
    "{\"version\":2,\"config_path\":\"" ++ proxy_config_path ++
    "\",\"active\":null,\"cursor\":\"codex-1\",\"in_flight\":0,\"accounts\":[{" ++
    "\"name\":\"codex-1\",\"label\":\"Codex Demo\",\"auth_file\":\"" ++ proxy_auth_file ++
    "\",\"state\":\"COOLDOWN\",\"cooldown_until\":\"2033-01-01T00:01:02Z\",\"reason\":\"usage_limit_reached\",\"token_expires_at\":null,\"in_flight\":0}]}";

const proxy_ready_status_v2 =
    "{\"version\":2,\"config_path\":\"" ++ proxy_config_path ++
    "\",\"active\":\"codex-1\",\"cursor\":\"codex-1\",\"in_flight\":0,\"accounts\":[{" ++
    "\"name\":\"codex-1\",\"label\":\"Codex Demo\",\"auth_file\":\"" ++ proxy_auth_file ++
    "\",\"state\":\"READY\",\"cooldown_until\":null,\"reason\":null,\"token_expires_at\":\"2033-06-14T01:43:00Z\",\"in_flight\":0}]}";

const proxy_move_accounts_status_v2 =
    "{\"version\":2,\"config_path\":\"" ++ proxy_config_path ++
    "\",\"active\":\"alpha\",\"cursor\":\"alpha\",\"in_flight\":0,\"accounts\":[" ++
    "{\"name\":\"alpha\",\"label\":\"Alpha\",\"auth_file\":\"" ++ accounts_root ++
    "/codex-alpha/codex/auth.json\",\"state\":\"READY\",\"cooldown_until\":null,\"reason\":null,\"token_expires_at\":null,\"in_flight\":0}," ++
    "{\"name\":\"beta\",\"label\":\"Beta\",\"auth_file\":\"" ++ accounts_root ++
    "/codex-beta/codex/auth.json\",\"state\":\"READY\",\"cooldown_until\":null,\"reason\":null,\"token_expires_at\":null,\"in_flight\":0}," ++
    "{\"name\":\"gamma\",\"label\":\"Gamma\",\"auth_file\":\"" ++ accounts_root ++
    "/codex-gamma/codex/auth.json\",\"state\":\"READY\",\"cooldown_until\":null,\"reason\":null,\"token_expires_at\":null,\"in_flight\":0}]}";

const proxy_unmapped_status_v2 =
    "{\"version\":2,\"config_path\":\"" ++ proxy_config_path ++
    "\",\"active\":null,\"cursor\":\"codex-1\",\"in_flight\":0,\"accounts\":[{" ++
    "\"name\":\"codex-1\",\"label\":\"Someone Else\",\"auth_file\":\"" ++ home_dir ++
    "/Library/Application Support/" ++ runtime_paths.app_data_directory_name ++ "/accounts/other-key/codex/auth.json" ++
    "\",\"state\":\"COOLDOWN\",\"cooldown_until\":\"2033-01-01T00:01:02Z\",\"reason\":\"usage_limit_reached\",\"token_expires_at\":null,\"in_flight\":0}]}";

const proxy_saved_account_mismatch_status_v2 =
    "{\"version\":2,\"config_path\":\"" ++ proxy_config_path ++
    "\",\"active\":null,\"cursor\":\"other\",\"in_flight\":0,\"accounts\":[{" ++
    "\"name\":\"other\",\"label\":\"Other\",\"auth_file\":\"" ++ home_dir ++
    "/Library/Application Support/" ++ runtime_paths.app_data_directory_name ++ "/accounts/other/codex/auth.json" ++
    "\",\"state\":\"READY\",\"cooldown_until\":null,\"reason\":null,\"token_expires_at\":null,\"in_flight\":0}]}";

fn saveProxySettings(harness: *Harness) !void {
    try testing.expectEqual(ui_model.CommandOutcome.accepted_pending, harness.service.submit(.{ .save_proxy_settings = .{
        .base_url = "http://127.0.0.1:48787",
        .cli_path = proxy_cli_path,
        .config_path = proxy_config_path,
    } }));
}

fn runSettledReset(harness: *Harness, server: *StatefulAppServer) !void {
    harness.codex_launcher.custom_stream = server.stream();
    try testing.expectEqual(ui_model.CommandOutcome.accepted_pending, harness.service.submit(.{
        .redeem_reset = .{
            .account_id = codex_account_id,
            .expected_available_count = 2,
            .confirmed_at_unix_s = now,
        },
    }));
    try harness.drainAll();
    const attempts = harness.core.attempts();
    try testing.expectEqual(@as(usize, 1), attempts.len);
    try testing.expectEqual(domain.ResetOutcome.reset, attempts[0].outcome.?);
}

fn projectedProxyClear(harness: *Harness) !ui_model.ResetProxyClear {
    const view = try projectView(harness.service);
    defer testing.allocator.destroy(view);
    var index: usize = 0;
    while (index < view.row_count) : (index += 1) {
        const row = view.rowAt(index) orelse break;
        if (std.mem.eql(u8, row.account_id, codex_account_id)) return row.reset_proxy_clear;
    }
    return error.RowMissing;
}

fn projectView(service: *app_service.Service) !*ui_model.ViewState {
    const view = try testing.allocator.create(ui_model.ViewState);
    view.* = .{};
    service.port().project(view, now, .kst, .{});
    return view;
}

test "an unattached service projects saved state and refuses every command" {
    const harness = try Harness.create();
    defer harness.destroy();
    try harness.addCodex();

    const capabilities = harness.service.capabilities();
    try testing.expect(capabilities.connected);
    try testing.expect(!capabilities.refresh);
    try testing.expect(!capabilities.accounts);
    try testing.expect(!capabilities.reset);

    const view = try projectView(harness.service);
    defer testing.allocator.destroy(view);
    try testing.expectEqual(@as(usize, 1), view.row_count);
    try testing.expectEqualStrings("Codex Demo", view.rowAt(0).?.label);

    try testing.expectEqual(ui_model.CommandOutcome.service_unavailable, harness.service.submit(.refresh_all));
    try testing.expectEqual(
        ui_model.CommandOutcome.service_unavailable,
        harness.service.submit(.{ .refresh_account = codex_account_id }),
    );
    try testing.expectEqual(
        ui_model.CommandOutcome.service_unavailable,
        harness.service.submit(.{ .add_account = .codex }),
    );
    try testing.expectEqual(
        ui_model.CommandOutcome.service_unavailable,
        harness.service.submit(.{ .relabel = .{ .account_id = codex_account_id, .label = "Renamed" } }),
    );
    try testing.expectEqual(
        ui_model.CommandOutcome.service_unavailable,
        harness.service.submit(.{ .remove_account = codex_account_id }),
    );
    try testing.expectEqual(ui_model.CommandOutcome.offer_unavailable, harness.service.submit(.{
        .redeem_reset = .{
            .account_id = codex_account_id,
            .expected_available_count = 1,
            .confirmed_at_unix_s = now,
        },
    }));

    try testing.expect(harness.core.schedulerIsIdle());
    try testing.expectEqual(@as(usize, 0), harness.sink.record_count);
    try testing.expectEqual(@as(usize, 0), harness.codex_launcher.opens);
    try testing.expectEqual(@as(usize, 0), harness.login_launcher.opens);
}

test "capabilities become true only once a complete driver set is attached" {
    const harness = try Harness.create();
    defer harness.destroy();

    try testing.expect(!harness.service.isAttached());
    harness.attach();
    try testing.expect(harness.service.isAttached());

    const capabilities = harness.service.capabilities();
    try testing.expect(capabilities.connected);
    try testing.expect(capabilities.refresh);
    try testing.expect(capabilities.accounts);
    try testing.expect(capabilities.reset);

    var partial = harness.live();
    partial.keys = app_service.unwiredKeySource();
    harness.service.attach(partial);
    try testing.expect(!harness.service.capabilities().reset);
    try testing.expect(harness.service.capabilities().refresh);
}

test "the pump starts nothing the user did not ask for" {
    const harness = try Harness.create();
    defer harness.destroy();
    try harness.addCodex();
    try harness.addClaude();
    harness.attach();

    var tick: usize = 0;
    while (tick < 8) : (tick += 1) harness.service.pump(now + @as(i64, @intCast(tick)));

    try testing.expectEqual(@as(usize, 0), harness.codex_launcher.opens);
    try testing.expectEqual(@as(usize, 0), harness.login_launcher.opens);
    try testing.expectEqual(@as(usize, 0), harness.service.busyWorkerCount());
    try testing.expect(harness.core.schedulerIsIdle());
    try testing.expectEqual(@as(usize, 0), harness.sink.record_count);
}

test "C9 single-account refresh reads usage before its loopback proxy status" {
    const harness = try Harness.create();
    defer harness.destroy();
    try harness.addCodex();
    harness.parent_env = &proxy_env;
    harness.attach();
    try saveProxySettings(harness);
    harness.codex_launcher.stream = .{ .chunks = &.{.{ .bytes = script_read }} };

    try testing.expectEqual(
        ui_model.CommandOutcome.accepted_pending,
        harness.service.submit(.{ .refresh_account = codex_account_id }),
    );
    var spins: usize = 0;
    while (harness.codex_launcher.opens == 0) {
        spins += 1;
        if (spins > 4000) return error.ProviderReadDidNotStart;
        testing.io.sleep(.fromMilliseconds(1), .awake) catch {};
    }
    try testing.expectEqual(@as(usize, 1), harness.codex_launcher.opens);
    try testing.expectEqual(@as(usize, 0), harness.proxy_exchange.calls);
    try harness.drainAll();
    try testing.expectEqualStrings("/_proxy/status", harness.proxy_exchange.lastPath());
    try testing.expect(harness.core.snapshotFor(codex_account_id) != null);
}

test "C9 refresh fixes a saved-account mismatch and re-reads status" {
    const harness = try Harness.create();
    defer harness.destroy();
    try harness.addCodex();
    const replies = [_]FakeProxyExchange.Reply{
        .{ .status = 200, .body = proxy_saved_account_mismatch_status_v2 },
        .{ .status = 200, .body = proxy_ready_status_v2 },
        .{ .status = 200, .body = proxy_ready_status_v2 },
    };
    harness.proxy_exchange.replies = &replies;
    harness.parent_env = &proxy_env;
    harness.attach();
    try saveProxySettings(harness);
    harness.codex_launcher.stream = .{ .chunks = &.{.{ .bytes = script_read }} };

    try testing.expectEqual(ui_model.CommandOutcome.accepted_pending, harness.service.submit(.refresh_all));
    try harness.drainAll();

    try testing.expectEqual(@as(usize, 1), harness.codex_launcher.opens);
    try testing.expectEqual(@as(usize, 1), harness.proxy_importer.calls);
    try testing.expectEqual(@as(usize, 3), harness.proxy_exchange.calls);
    try testing.expectEqualStrings("/_proxy/status", harness.proxy_exchange.pathAt(0));
    try testing.expectEqualStrings("/_proxy/reload-config", harness.proxy_exchange.pathAt(1));
    try testing.expectEqualStrings("/_proxy/status", harness.proxy_exchange.pathAt(2));
    try testing.expectEqual(app_service.ProxySyncState.synced, harness.service.proxyState().sync_state);
}

test "C9 refresh defers a busy config reload until the next refresh without retrying" {
    const harness = try Harness.create();
    defer harness.destroy();
    try harness.addCodex();
    const replies = [_]FakeProxyExchange.Reply{
        .{ .status = 200, .body = proxy_saved_account_mismatch_status_v2 },
        .{ .status = 409, .body = "{\"error\":\"requests_in_flight\"}" },
    };
    harness.proxy_exchange.replies = &replies;
    harness.parent_env = &proxy_env;
    harness.attach();
    try saveProxySettings(harness);
    harness.codex_launcher.stream = .{ .chunks = &.{.{ .bytes = script_read }} };

    try testing.expectEqual(ui_model.CommandOutcome.accepted_pending, harness.service.submit(.refresh_all));
    try harness.drainAll();
    harness.service.pump(now + 1);
    harness.service.pump(now + 2);

    try testing.expectEqual(@as(usize, 1), harness.proxy_importer.calls);
    try testing.expectEqual(@as(usize, 2), harness.proxy_exchange.calls);
    try testing.expectEqual(app_service.ProxySyncState.needed, harness.service.proxyState().sync_state);
    const view = try projectView(harness.service);
    defer testing.allocator.destroy(view);
    try testing.expect(std.mem.indexOf(u8, view.proxy_detail_text, "next refresh") != null);
    try testing.expect(std.mem.indexOf(u8, view.proxy_banner_text, "next refresh") != null);
}

test "C9 cooldown reconciliation accepts a proxy status read completed after fresh usage" {
    const harness = try Harness.create();
    defer harness.destroy();
    try harness.addCodex();
    const replies = [_]FakeProxyExchange.Reply{
        .{ .status = 200, .body = proxy_expired_cooldown_status_v2 },
        .{ .status = 200, .body = "{\"name\":\"codex-1\",\"state\":\"READY\",\"cooldown_until\":null}" },
    };
    harness.proxy_exchange.replies = &replies;
    harness.parent_env = &proxy_env;
    harness.attach();
    try saveProxySettings(harness);
    harness.codex_launcher.stream = .{ .chunks = &.{.{ .bytes = script_read_after_weekly_reset }} };

    try testing.expectEqual(ui_model.CommandOutcome.accepted_pending, harness.service.submit(.refresh_all));
    var tick: i64 = 1;
    while (harness.proxy_exchange.calls < 2) : (tick += 1) {
        harness.service.pump(now + tick);
        if (tick > 4000) return error.CooldownReconciliationDidNotFinish;
        testing.io.sleep(.fromMilliseconds(1), .awake) catch {};
    }
    try harness.drainAllAt(now + tick);
    try testing.expect(harness.core.snapshotFor(codex_account_id).?.captured_at_unix_s < harness.service.proxyState().last_success_at_unix_s.?);
    try testing.expectEqual(proxy_control.AccountState.ready, harness.service.proxyState().last_success.?.accountAt(0).?.state);
}

test "C6 cooling account whose weekly window reset clears exactly once" {
    const harness = try Harness.create();
    defer harness.destroy();
    try harness.addCodex();
    const replies = [_]FakeProxyExchange.Reply{
        .{ .status = 200, .body = proxy_cooldown_status_v2 },
        .{ .status = 200, .body = "{\"name\":\"codex-1\",\"state\":\"READY\",\"cooldown_until\":null}" },
    };
    harness.proxy_exchange.replies = &replies;
    harness.parent_env = &proxy_env;
    harness.attach();
    try saveProxySettings(harness);
    harness.codex_launcher.stream = .{ .chunks = &.{.{ .bytes = script_read_after_weekly_reset }} };

    try testing.expectEqual(
        ui_model.CommandOutcome.accepted_pending,
        harness.service.submit(.{ .refresh_account = codex_account_id }),
    );
    try harness.drainAll();

    try testing.expectEqual(@as(usize, 2), harness.proxy_exchange.calls);
    try testing.expectEqualStrings("/_proxy/accounts/codex-1/clear-cooldown", harness.proxy_exchange.lastPath());
    try testing.expectEqual(proxy_control.AccountState.ready, harness.service.proxyState().last_success.?.accountAt(0).?.state);
    harness.service.pump(now + 1);
    harness.service.pump(now + 2);
    try testing.expectEqual(@as(usize, 2), harness.proxy_exchange.calls);
}

test "C6 a refused stale-cooldown clear is one automatic attempt, never a retry" {
    const harness = try Harness.create();
    defer harness.destroy();
    try harness.addCodex();
    const replies = [_]FakeProxyExchange.Reply{
        .{ .status = 200, .body = proxy_cooldown_status_v2 },
        .{ .status = 409, .body = "{\"error\":\"account_paused\"}" },
    };
    harness.proxy_exchange.replies = &replies;
    harness.parent_env = &proxy_env;
    harness.attach();
    try saveProxySettings(harness);
    harness.codex_launcher.stream = .{ .chunks = &.{.{ .bytes = script_read_after_weekly_reset }} };

    try testing.expectEqual(
        ui_model.CommandOutcome.accepted_pending,
        harness.service.submit(.{ .refresh_account = codex_account_id }),
    );
    try harness.drainAll();

    try testing.expectEqual(@as(usize, 2), harness.proxy_exchange.calls);
    try testing.expectEqualStrings("/_proxy/accounts/codex-1/clear-cooldown", harness.proxy_exchange.lastPath());
    try testing.expectEqual(proxy_control.AccountState.cooldown, harness.service.proxyState().last_success.?.accountAt(0).?.state);
    harness.service.pump(now + 1);
    harness.service.pump(now + 2);
    try testing.expectEqual(@as(usize, 2), harness.proxy_exchange.calls);
}

test "C6 fresh exhausted usage keeps a reconciled future proxy cooldown" {
    const harness = try Harness.create();
    defer harness.destroy();
    try harness.addCodex();
    const replies = [_]FakeProxyExchange.Reply{.{ .status = 200, .body = proxy_cooldown_status_v2 }};
    harness.proxy_exchange.replies = &replies;
    harness.parent_env = &proxy_env;
    harness.attach();
    try saveProxySettings(harness);
    harness.codex_launcher.stream = .{ .chunks = &.{.{ .bytes = script_read_exhausted }} };

    try testing.expectEqual(ui_model.CommandOutcome.accepted_pending, harness.service.submit(.refresh_all));
    try harness.drainAll();

    try testing.expectEqual(@as(usize, 1), harness.proxy_exchange.calls);
    try testing.expectEqualStrings("/_proxy/status", harness.proxy_exchange.lastPath());
    try testing.expectEqual(proxy_control.AccountState.cooldown, harness.service.proxyState().last_success.?.accountAt(0).?.state);
}

test "C7 Pro 20x cooldown reconciliation ignores an exhausted session when weekly is available" {
    const harness = try Harness.create();
    defer harness.destroy();
    try harness.addCodex();
    const replies = [_]FakeProxyExchange.Reply{
        .{ .status = 200, .body = proxy_cooldown_status_v2 },
        .{ .status = 200, .body = "{\"name\":\"codex-1\",\"state\":\"READY\",\"cooldown_until\":null}" },
    };
    harness.proxy_exchange.replies = &replies;
    harness.parent_env = &proxy_env;
    harness.attach();
    try saveProxySettings(harness);
    harness.codex_launcher.stream = .{ .chunks = &.{.{ .bytes = script_read_pro_session_exhausted_weekly_available }} };

    try testing.expectEqual(ui_model.CommandOutcome.accepted_pending, harness.service.submit(.refresh_all));
    try harness.drainAll();

    try testing.expectEqualStrings("Pro 20x", harness.core.account(codex_account_id).?.plan_label.?);
    try testing.expectEqual(@as(usize, 2), harness.proxy_exchange.calls);
    try testing.expectEqualStrings("/_proxy/accounts/codex-1/clear-cooldown", harness.proxy_exchange.lastPath());
}

test "C7 Plus cooldown reconciliation clears when its binding session window is available" {
    const harness = try Harness.create();
    defer harness.destroy();
    try harness.addCodex();
    const replies = [_]FakeProxyExchange.Reply{
        .{ .status = 200, .body = proxy_cooldown_status_v2 },
        .{ .status = 200, .body = "{\"name\":\"codex-1\",\"state\":\"READY\",\"cooldown_until\":null}" },
    };
    harness.proxy_exchange.replies = &replies;
    harness.parent_env = &proxy_env;
    harness.attach();
    try saveProxySettings(harness);
    harness.codex_launcher.stream = .{ .chunks = &.{.{ .bytes = script_read_plus_session_available }} };

    try testing.expectEqual(ui_model.CommandOutcome.accepted_pending, harness.service.submit(.refresh_all));
    try harness.drainAll();

    try testing.expectEqualStrings("Plus", harness.core.account(codex_account_id).?.plan_label.?);
    try testing.expectEqual(@as(usize, 2), harness.proxy_exchange.calls);
    try testing.expectEqualStrings("/_proxy/accounts/codex-1/clear-cooldown", harness.proxy_exchange.lastPath());
}

test "C7 Plus cooldown reconciliation stays when its binding weekly window is exhausted" {
    const harness = try Harness.create();
    defer harness.destroy();
    try harness.addCodex();
    const replies = [_]FakeProxyExchange.Reply{.{ .status = 200, .body = proxy_cooldown_status_v2 }};
    harness.proxy_exchange.replies = &replies;
    harness.parent_env = &proxy_env;
    harness.attach();
    try saveProxySettings(harness);
    harness.codex_launcher.stream = .{ .chunks = &.{.{ .bytes = script_read_plus_weekly_exhausted }} };

    try testing.expectEqual(ui_model.CommandOutcome.accepted_pending, harness.service.submit(.refresh_all));
    try harness.drainAll();

    try testing.expectEqualStrings("Plus", harness.core.account(codex_account_id).?.plan_label.?);
    try testing.expectEqual(@as(usize, 1), harness.proxy_exchange.calls);
    try testing.expectEqualStrings("/_proxy/status", harness.proxy_exchange.lastPath());
    try testing.expectEqual(proxy_control.AccountState.cooldown, harness.service.proxyState().last_success.?.accountAt(0).?.state);
}

test "C6 an expired proxy cooldown clears after a fresh exhausted usage read" {
    const harness = try Harness.create();
    defer harness.destroy();
    try harness.addCodex();
    const replies = [_]FakeProxyExchange.Reply{
        .{ .status = 200, .body = proxy_expired_cooldown_status_v2 },
        .{ .status = 200, .body = "{\"name\":\"codex-1\",\"state\":\"READY\",\"cooldown_until\":null}" },
    };
    harness.proxy_exchange.replies = &replies;
    harness.parent_env = &proxy_env;
    harness.attach();
    try saveProxySettings(harness);
    harness.codex_launcher.stream = .{ .chunks = &.{.{ .bytes = script_read_exhausted }} };

    try testing.expectEqual(
        ui_model.CommandOutcome.accepted_pending,
        harness.service.submit(.{ .refresh_account = codex_account_id }),
    );
    try harness.drainAll();

    try testing.expectEqual(@as(usize, 2), harness.proxy_exchange.calls);
    try testing.expectEqualStrings("/_proxy/accounts/codex-1/clear-cooldown", harness.proxy_exchange.lastPath());
}

test "C6 a failed refresh never clears from a missing fresh snapshot" {
    const harness = try Harness.create();
    defer harness.destroy();
    try harness.addCodex();
    const replies = [_]FakeProxyExchange.Reply{.{ .status = 200, .body = proxy_cooldown_status_v2 }};
    harness.proxy_exchange.replies = &replies;
    harness.parent_env = &proxy_env;
    harness.attach();
    try saveProxySettings(harness);
    harness.codex_launcher.stream = .{ .chunks = &.{.{ .failure = error.EndOfStream }} };

    try testing.expectEqual(
        ui_model.CommandOutcome.accepted_pending,
        harness.service.submit(.{ .refresh_account = codex_account_id }),
    );
    try harness.drainAll();

    try testing.expect(harness.core.snapshotFor(codex_account_id) == null);
    try testing.expectEqual(@as(usize, 1), harness.proxy_exchange.calls);
    try testing.expectEqual(proxy_control.AccountState.cooldown, harness.service.proxyState().last_success.?.accountAt(0).?.state);
}

test "C6 a failed refresh never reuses a snapshot older than the cooldown read" {
    const harness = try Harness.create();
    defer harness.destroy();
    try harness.addCodex();
    const replies = [_]FakeProxyExchange.Reply{
        .{ .status = 200, .body = proxy_ready_status_v2 },
        .{ .status = 200, .body = proxy_cooldown_status_v2 },
    };
    harness.proxy_exchange.replies = &replies;
    harness.parent_env = &proxy_env;
    harness.attach();
    try saveProxySettings(harness);

    harness.codex_launcher.stream = .{ .chunks = &.{.{ .bytes = script_read_after_weekly_reset }} };
    _ = harness.service.submit(.{ .refresh_account = codex_account_id });
    try harness.drainAll();
    const old_snapshot_at = harness.core.snapshotFor(codex_account_id).?.captured_at_unix_s;

    harness.codex_launcher.stream = .{ .chunks = &.{.{ .failure = error.EndOfStream }} };
    harness.codex_launcher.lifecycle = .{};
    harness.service.now_unix_s = now + 120;
    _ = harness.service.submit(.{ .refresh_account = codex_account_id });
    try harness.drainAllAt(now + 120);

    try testing.expectEqual(old_snapshot_at, harness.core.snapshotFor(codex_account_id).?.captured_at_unix_s);
    try testing.expect(old_snapshot_at < harness.service.proxyState().last_success_at_unix_s.?);
    try testing.expectEqual(@as(usize, 2), harness.proxy_exchange.calls);
    try testing.expectEqualStrings("/_proxy/status", harness.proxy_exchange.lastPath());
    try testing.expectEqual(proxy_control.AccountState.cooldown, harness.service.proxyState().last_success.?.accountAt(0).?.state);
}

test "a codex refresh runs on a worker and stores the authoritative reading" {
    const harness = try Harness.create();
    defer harness.destroy();
    try harness.addCodex();
    harness.attach();
    harness.codex_launcher.stream = .{ .chunks = &.{.{ .bytes = script_read }} };

    try testing.expectEqual(
        ui_model.CommandOutcome.accepted_pending,
        harness.service.submit(.{ .refresh_account = codex_account_id }),
    );

    try testing.expect(!harness.core.schedulerIsIdle());

    try harness.drain();

    const snapshot = harness.core.snapshotFor(codex_account_id).?;
    try testing.expectEqual(domain.SnapshotStatus.fresh, snapshot.status);
    try testing.expectEqual(@as(usize, 2), snapshot.windows.len);
    try testing.expectEqual(@as(u32, 2), snapshot.reset_credits.?.authoritativeCount());
    const account = harness.core.account(codex_account_id).?;

    try testing.expectEqualStrings("Codex Demo", account.label);
    try testing.expectEqualStrings("demo-user@example.invalid", account.provider_email.?);
    try testing.expectEqualStrings("Pro 20x", account.plan_label.?);
    try testing.expectEqualStrings(codex_home, harness.codex_launcher.homePath());

    try testing.expectEqual(@as(usize, 1), harness.codex_launcher.opens);
    try testing.expect(harness.codex_launcher.lifecycle.reapedExactlyOnce());
    try testing.expect(harness.core.schedulerIsIdle());

    try testing.expect(harness.sink.countOf(.snapshots) >= 1);
}

test "a too-old Codex CLI uses the existing unsupported path without launching a worker" {
    const harness = try Harness.create();
    defer harness.destroy();
    try harness.addCodex();
    var live = harness.live();
    live.codex_cli_too_old = true;
    harness.service.attach(live);
    harness.service.now_unix_s = now;

    try testing.expectEqual(
        ui_model.CommandOutcome.accepted_pending,
        harness.service.submit(.{ .refresh_account = codex_account_id }),
    );
    try harness.drainAll();

    try testing.expectEqual(@as(usize, 0), harness.codex_launcher.opens);
    try testing.expectEqualStrings(
        codex.public_code_app_server_unsupported,
        harness.core.statusFor(codex_account_id).?.last_attempt_code.?,
    );
}

test "a direct Claude refresh is rejected without transport or credential work" {
    const harness = try Harness.create();
    defer harness.destroy();
    try harness.addClaude();

    harness.attach();

    try testing.expectEqual(
        ui_model.CommandOutcome.rejected_not_allowed,
        harness.service.submit(.{ .refresh_account = claude_account_id }),
    );
    try testing.expect(harness.core.snapshotFor(claude_account_id) == null);
    try testing.expectEqual(@as(usize, 0), harness.sink.record_count);
}

test "a failed refresh preserves the prior saved snapshot and records the attempt" {
    const harness = try Harness.create();
    defer harness.destroy();
    try harness.addCodex();
    harness.attach();

    harness.codex_launcher.stream = .{ .chunks = &.{.{ .bytes = script_read }} };
    _ = harness.service.submit(.{ .refresh_account = codex_account_id });
    try harness.drain();
    const first = harness.core.snapshotFor(codex_account_id).?;
    const first_captured = first.captured_at_unix_s;
    const first_windows = first.windows.len;
    const success_at = harness.core.statusFor(codex_account_id).?.last_success_at_unix_s;

    harness.codex_launcher.stream = .{ .chunks = &.{.{ .failure = error.EndOfStream }} };
    harness.codex_launcher.lifecycle = .{};
    _ = harness.service.submit(.{ .refresh_account = codex_account_id });
    try harness.drain();

    const kept = harness.core.snapshotFor(codex_account_id).?;
    try testing.expectEqual(first_captured, kept.captured_at_unix_s);
    try testing.expectEqual(first_windows, kept.windows.len);

    const status = harness.core.statusFor(codex_account_id).?;
    try testing.expectEqual(success_at, status.last_success_at_unix_s);
    try testing.expect(status.last_attempt_code != null);
    try testing.expect(coordinator.isPublicCode(status.last_attempt_code.?));

    try testing.expect(harness.codex_launcher.lifecycle.reapedExactlyOnce());
}

test "a launcher that cannot start an app-server fails closed and keeps the snapshot" {
    const harness = try Harness.create();
    defer harness.destroy();
    try harness.addCodex();
    harness.attach();

    harness.codex_launcher.failure = error.SpawnFailed;
    _ = harness.service.submit(.{ .refresh_account = codex_account_id });
    try harness.drain();

    try testing.expect(harness.core.snapshotFor(codex_account_id) == null);
    const status = harness.core.statusFor(codex_account_id).?;
    try testing.expectEqualStrings(codex.public_code_app_server_unavailable, status.last_attempt_code.?);
    try testing.expect(harness.core.schedulerIsIdle());
}

test "refresh all admits at most two operations at once and one per account" {
    const harness = try Harness.create();
    defer harness.destroy();
    harness.attach();

    var index: usize = 0;
    while (index < 5) : (index += 1) {
        var id_storage: [account_registry.max_id_bytes]u8 = undefined;
        var key_storage: [account_registry.max_storage_key_bytes]u8 = undefined;
        const id = try std.fmt.bufPrint(&id_storage, "acct-codex-{d}", .{index});
        const key = try std.fmt.bufPrint(&key_storage, "codex-{d}", .{index});
        _ = try harness.core.addAccount(.{
            .id = id,
            .provider = .codex,
            .label = "Codex",
            .storage_key = key,
            .created_at_unix_s = now - 1000,
        });
    }

    harness.codex_launcher.stream = .{ .chunks = &.{.{ .failure = error.EndOfStream }} };

    try testing.expectEqual(ui_model.CommandOutcome.accepted_pending, harness.service.submit(.refresh_all));
    try testing.expect(harness.service.busyWorkerCount() <= app_service.max_workers);
    try testing.expect(harness.core.inFlightCount() <= coordinator.max_concurrent_operations);

    var spins: usize = 0;
    while (!harness.core.schedulerIsIdle()) {
        try testing.expect(harness.core.inFlightCount() <= coordinator.max_concurrent_operations);
        try testing.expect(harness.service.busyWorkerCount() <= app_service.max_workers);
        harness.service.pump(now);
        spins += 1;
        if (spins > 4000) return error.SchedulerDidNotDrain;
        testing.io.sleep(.fromMilliseconds(1), .awake) catch {};
    }

    var account: usize = 0;
    while (account < 5) : (account += 1) {
        const status = harness.core.statusAt(account).?;
        try testing.expect(status.last_attempt_at_unix_s != null);
        try testing.expect(!status.operation_in_flight);
        try testing.expect(!status.queued);
    }
}

test "C4 direct Claude commands are inert and refresh all admits Codex only" {
    const harness = try Harness.create();
    defer harness.destroy();
    try harness.addClaude();
    try harness.addCodex();
    harness.attach();
    harness.codex_launcher.stream = .{ .chunks = &.{.{ .bytes = script_read }} };

    try testing.expectEqual(
        ui_model.CommandOutcome.accepted_pending,
        harness.service.submit(.{ .add_account = .claude }),
    );
    try testing.expectEqual(
        ui_model.CommandOutcome.rejected_not_allowed,
        harness.service.submit(.{ .refresh_account = claude_account_id }),
    );
    try testing.expectEqual(
        ui_model.CommandOutcome.rejected_not_allowed,
        harness.service.submit(.{ .reauthenticate = claude_account_id }),
    );
    try testing.expectEqual(ui_model.CommandOutcome.rejected_not_allowed, harness.service.submit(.{ .relabel = .{
        .account_id = claude_account_id,
        .label = "Changed Claude",
    } }));
    try testing.expectEqual(
        ui_model.CommandOutcome.rejected_not_allowed,
        harness.service.submit(.{ .remove_account = claude_account_id }),
    );
    try testing.expectEqual(
        ui_model.CommandOutcome.rejected_not_allowed,
        harness.service.submit(.{ .proxy_switch_account = claude_account_id }),
    );
    try testing.expectEqual(ui_model.CommandOutcome.accepted_pending, harness.service.submit(.refresh_all));
    try harness.drain();

    try testing.expectEqual(@as(usize, 1), harness.proxy_exchange.calls);
    try testing.expectEqualStrings("/_proxy/status", harness.proxy_exchange.lastPath());
    try testing.expectEqualStrings("Claude Demo", harness.core.account(claude_account_id).?.label);
    try testing.expect(harness.core.statusFor(claude_account_id).?.last_attempt_at_unix_s == null);
    try testing.expect(harness.core.statusFor(codex_account_id).?.last_attempt_at_unix_s != null);
}

test "C4 startup recovery reads only the Codex auth backup and never queries Claude slots" {
    const directory = ".zig-cache/test-c4-codex-only-load";
    var cwd = std.Io.Dir.cwd();
    cwd.deleteTree(testing.io, directory) catch {};
    try cwd.createDirPath(testing.io, directory);
    defer cwd.deleteTree(testing.io, directory) catch {};
    var dir = try cwd.openDir(testing.io, directory, .{});
    defer dir.close(testing.io);

    const layout = try runtime_paths.Layout.fromHomeDir(home_dir);
    const seed = try coordinator.Coordinator.create(testing.allocator, .{
        .layout = layout,
        .target = .{ .codex_executable = codex_executable },
    });
    defer seed.destroy();
    _ = try seed.addAccount(.{
        .id = claude_account_id,
        .provider = .claude,
        .label = "Claude Demo",
        .storage_key = claude_storage_key,
        .created_at_unix_s = now - 1000,
    });
    _ = try seed.registry.markConnected(claude_account_id, null);
    _ = try seed.addAccount(.{
        .id = codex_account_id,
        .provider = .codex,
        .label = "Codex Demo",
        .storage_key = codex_storage_key,
        .created_at_unix_s = now - 1000,
    });
    _ = try seed.registry.markConnected(codex_account_id, null);
    try seed.recordProviderMetadata(claude_account_id, .{
        .email = "claude-preserved@example.invalid",
        .email_observed = true,
        .plan_label = "Legacy Claude plan",
        .plan_observed = true,
    });
    const claude_saved_windows = [_]domain.UsageWindow{.{
        .kind = .weekly,
        .label = "Claude preserved weekly",
        .used_percent = 73,
        .reset_at_unix_s = now + 12345,
    }};
    _ = try seed.requestRefresh(claude_account_id);
    const claude_ticket = seed.nextOperation(now - 20) orelse return error.ExpectedClaudeTicket;
    _ = try seed.applyObservation(claude_ticket, .{ .supported = .{
        .observed_at_unix_s = now - 20,
        .windows = &claude_saved_windows,
    } }, now - 20);
    const codex_saved_windows = [_]domain.UsageWindow{.{
        .kind = .weekly,
        .label = "Weekly",
        .used_percent = 41,
        .reset_at_unix_s = now + 20000,
    }};
    _ = try seed.requestRefresh(codex_account_id);
    const codex_ticket = seed.nextOperation(now - 10) orelse return error.ExpectedCodexTicket;
    _ = try seed.applyObservation(codex_ticket, .{ .supported = .{
        .observed_at_unix_s = now - 10,
        .windows = &codex_saved_windows,
    } }, now - 10);
    const claude_attempt = try domain.ResetAttempt.init(
        "attempt-claude-preserved",
        claude_account_id,
        null,
        now - 30,
        1,
        now - 29,
    );
    const attempt_bytes = try store.encode(testing.allocator, store.AttemptDocument{
        .attempts = &.{claude_attempt},
    });
    defer testing.allocator.free(attempt_bytes);
    try testing.expectEqual(@as(usize, 1), try seed.loadAttemptBytes(attempt_bytes));
    var file_sink: coordinator.FileDocumentSink = .{ .io = testing.io, .dir = dir };
    try seed.persistAll(file_sink.sink());

    var fake: keychain_test_support.FakeSecItem = .{};
    defer fake.deinit();
    var backend: keychain.macos.SecItemStore = .init(fake.api());
    var primary = try keychain.macos.KeychainStore.init(keychain.macos.v2_service);
    var legacy = try keychain.macos.KeychainStore.init(keychain.macos.legacy_service);
    primary.backend = backend.backend();
    legacy.backend = backend.backend();
    var versioned: keychain.macos.VersionedKeychainStore = .{ .primary = primary.store(), .legacy = legacy.store() };

    const harness = try Harness.create();
    defer harness.destroy();
    var live = harness.live();
    live.credentials = versioned.store();
    harness.service.attach(live);
    harness.service.now_unix_s = now;

    const report = harness.service.load(testing.io, dir);
    try testing.expectEqual(@as(usize, 1), report.accounts_loaded);
    try testing.expectEqual(@as(usize, 1), report.snapshots_loaded);
    try testing.expectEqual(@as(usize, 1), report.attempts_loaded);
    try testing.expectEqual(@as(usize, 1), harness.core.accountCount());
    try testing.expectEqual(domain.Provider.codex, harness.core.accountAt(0).?.provider);

    harness.codex_launcher.stream = .{ .chunks = &.{.{ .bytes = script_read }} };
    try testing.expectEqual(ui_model.CommandOutcome.accepted_pending, harness.service.submit(.{ .relabel = .{
        .account_id = codex_account_id,
        .label = "Codex relabeled",
    } }));
    try testing.expectEqual(ui_model.CommandOutcome.accepted_pending, harness.service.submit(.refresh_all));
    try harness.drain();

    try harness.core.persistLedger(harness.service.live.?.sink);

    var view: ui_model.ViewState = .{};
    view.begin(now, harness.service.capabilities(), .kst);
    harness.service.project(&view);
    view.finish(.{});
    var tray_items: [ui_model.max_tray_items]ui_model.TrayItem = @splat(.{});
    _ = ui_model.buildTray(&view, &tray_items);

    try testing.expectEqual(@as(usize, 2), fake.recordedItems().len);
    for (fake.recordedItems()) |*item| {
        try testing.expectEqualStrings("codex-demo.codex-auth", item.accountText());
    }

    const registry_bytes = harness.sink.lastOf(.registry) orelse return error.MissingRegistryWrite;
    var registry_doc = try std.json.parseFromSlice(
        account_registry.RegistryDocument,
        testing.allocator,
        registry_bytes,
        .{ .allocate = .alloc_always },
    );
    defer registry_doc.deinit();
    try testing.expectEqual(@as(usize, 2), registry_doc.value.accounts.len);
    var preserved_claude = false;
    for (registry_doc.value.accounts) |account| {
        if (account.provider != .claude) continue;
        preserved_claude = true;
        try testing.expectEqualStrings(claude_account_id, account.id);
        try testing.expectEqualStrings("Claude Demo", account.label);
        try testing.expectEqualStrings("claude-preserved@example.invalid", account.provider_email.?);
        try testing.expectEqualStrings("Legacy Claude plan", account.plan_label.?);
    }
    try testing.expect(preserved_claude);

    const snapshot_bytes = harness.sink.lastOf(.snapshots) orelse return error.MissingSnapshotWrite;
    var snapshot_doc = try store.decodeSnapshots(testing.allocator, snapshot_bytes);
    defer snapshot_doc.deinit();
    var preserved_claude_snapshot = false;
    for (snapshot_doc.value.snapshots) |snapshot| {
        if (snapshot.provider != .claude) continue;
        preserved_claude_snapshot = true;
        try testing.expectEqualStrings(claude_account_id, snapshot.account_id);
        try testing.expectEqual(@as(i64, now - 20), snapshot.captured_at_unix_s);
        try testing.expectEqual(@as(usize, 1), snapshot.windows.len);
        try testing.expectEqualStrings("Claude preserved weekly", snapshot.windows[0].label);
        try testing.expectEqual(@as(u8, 73), snapshot.windows[0].used_percent);
    }
    try testing.expect(preserved_claude_snapshot);

    const persisted_attempt_bytes = harness.sink.lastOf(.attempts) orelse return error.MissingAttemptWrite;
    var persisted_attempts = try store.decodeAttempts(testing.allocator, persisted_attempt_bytes);
    defer persisted_attempts.deinit();
    try testing.expectEqual(@as(usize, 1), persisted_attempts.value.attempts.len);
    try testing.expectEqualStrings("attempt-claude-preserved", persisted_attempts.value.attempts[0].idempotency_key);
    try testing.expectEqualStrings(claude_account_id, persisted_attempts.value.attempts[0].account_id);
}

test "move account persists downward upward and final-slot registry order" {
    var temp = testing.tmpDir(.{});
    defer temp.cleanup();

    const harness = try Harness.create();
    defer harness.destroy();
    try addMoveAccounts(harness);
    try observeMoveAccount(harness.core, move_alpha_id, now - 30, "Alpha weekly");
    try observeMoveAccount(harness.core, move_beta_id, now - 20, "Beta weekly");
    try observeMoveAccount(harness.core, move_gamma_id, now - 10, "Gamma weekly");
    var file_sink: coordinator.FileDocumentSink = .{ .io = testing.io, .dir = temp.dir };
    var live = harness.live();
    live.sink = file_sink.sink();
    harness.service.attach(live);

    try testing.expectEqual(ui_model.CommandOutcome.accepted_pending, harness.service.submit(.{ .move_account = .{
        .account_id = move_alpha_id,
        .target_account_id = move_beta_id,
    } }));
    try expectAccountOrder(harness.core, &.{ move_beta_id, move_alpha_id, move_gamma_id });

    try testing.expectEqual(ui_model.CommandOutcome.accepted_pending, harness.service.submit(.{ .move_account = .{
        .account_id = move_alpha_id,
        .target_account_id = move_beta_id,
    } }));
    try expectAccountOrder(harness.core, &.{ move_alpha_id, move_beta_id, move_gamma_id });

    try testing.expectEqual(ui_model.CommandOutcome.accepted_pending, harness.service.submit(.{ .move_account = .{
        .account_id = move_alpha_id,
        .target_account_id = move_gamma_id,
    } }));
    try expectAccountOrder(harness.core, &.{ move_beta_id, move_gamma_id, move_alpha_id });

    const registry_bytes = try temp.dir.readFileAlloc(
        testing.io,
        runtime_paths.registry_file_name,
        testing.allocator,
        .limited(64 * 1024),
    );
    defer testing.allocator.free(registry_bytes);
    try expectRegistryBytesOrder(registry_bytes, &.{ move_beta_id, move_gamma_id, move_alpha_id });

    const alpha_snapshot = harness.core.snapshotAt(2).?;
    try testing.expectEqualStrings(move_alpha_id, alpha_snapshot.account_id);
    try testing.expectEqualStrings("Alpha weekly", alpha_snapshot.windows[0].label);
    const alpha_status = harness.core.statusAt(2).?;
    try testing.expectEqualStrings(move_alpha_id, alpha_status.account_id);
    try testing.expectEqual(@as(?i64, now - 30), alpha_status.last_attempt_at_unix_s);
    try testing.expectEqual(@as(?i64, now - 30), alpha_status.last_success_at_unix_s);

    const beta_status = harness.core.statusAt(0).?;
    try testing.expectEqualStrings(move_beta_id, beta_status.account_id);
    try testing.expectEqual(@as(?i64, now - 20), beta_status.last_success_at_unix_s);
    const gamma_status = harness.core.statusAt(1).?;
    try testing.expectEqualStrings(move_gamma_id, gamma_status.account_id);
    try testing.expectEqual(@as(?i64, now - 10), gamma_status.last_success_at_unix_s);
}

test "move account acceptance immediately schedules proxy config synchronization" {
    const harness = try Harness.create();
    defer harness.destroy();
    try addMoveAccounts(harness);
    const replies = [_]FakeProxyExchange.Reply{.{ .status = 200, .body = proxy_move_accounts_status_v2 }};
    harness.proxy_exchange.replies = &replies;
    harness.parent_env = &proxy_env;
    harness.attach();
    try saveProxySettings(harness);

    try testing.expectEqual(ui_model.CommandOutcome.accepted_pending, harness.service.submit(.proxy_refresh_status));
    try harness.drainAll();
    try testing.expectEqual(app_service.ProxySyncState.synced, harness.service.proxyState().sync_state);

    try testing.expectEqual(ui_model.CommandOutcome.accepted_pending, harness.service.submit(.{ .move_account = .{
        .account_id = move_alpha_id,
        .target_account_id = move_beta_id,
    } }));

    try expectAccountOrder(harness.core, &.{ move_beta_id, move_alpha_id, move_gamma_id });
    try testing.expectEqual(app_service.ProxySyncState.needed, harness.service.proxyState().sync_state);
    try testing.expectEqual(ui_model.ProxyWork.importing, harness.service.proxyState().work);
    try testing.expect(harness.service.proxyWorkerBusy());
}

test "move account same-place and unknown identities perform no registry write" {
    const harness = try Harness.create();
    defer harness.destroy();
    try addMoveAccounts(harness);
    harness.attach();

    try testing.expectEqual(ui_model.CommandOutcome.none, harness.service.submit(.{ .move_account = .{
        .account_id = move_beta_id,
        .target_account_id = move_beta_id,
    } }));
    try testing.expectEqual(ui_model.CommandOutcome.rejected_unknown_account, harness.service.submit(.{ .move_account = .{
        .account_id = "acct-codex-unknown",
        .target_account_id = move_beta_id,
    } }));
    try testing.expectEqual(ui_model.CommandOutcome.rejected_unknown_account, harness.service.submit(.{ .move_account = .{
        .account_id = move_beta_id,
        .target_account_id = "acct-codex-unknown",
    } }));

    try testing.expectEqual(@as(usize, 0), harness.sink.countOf(.registry));
    try expectAccountOrder(harness.core, &.{ move_alpha_id, move_beta_id, move_gamma_id });
}

test "move account is refused while the coordinator scheduler is busy" {
    const harness = try Harness.create();
    defer harness.destroy();
    try addMoveAccounts(harness);
    harness.attach();
    _ = try harness.core.requestRefresh(move_alpha_id);

    try testing.expectEqual(ui_model.CommandOutcome.rejected_busy, harness.service.submit(.{ .move_account = .{
        .account_id = move_alpha_id,
        .target_account_id = move_beta_id,
    } }));
    try testing.expectEqual(@as(usize, 0), harness.sink.countOf(.registry));
    try expectAccountOrder(harness.core, &.{ move_alpha_id, move_beta_id, move_gamma_id });
}

test "C11 labeled add persists the owner name before the injected login opens" {
    const harness = try Harness.create();
    defer harness.destroy();
    harness.attach();
    harness.login_launcher.lines = &.{"Login successful.\n"};

    try testing.expectEqual(
        ui_model.CommandOutcome.accepted_pending,
        harness.service.port().addAccountLabeled(.codex, "Owner Work"),
    );
    try testing.expectEqual(@as(usize, 1), harness.core.accountCount());
    const value = harness.core.accountAt(0).?;
    try testing.expectEqualStrings("Owner Work", value.label);
    try testing.expect(value.label_is_custom);

    const registry_bytes = harness.sink.lastOf(.registry) orelse return error.MissingRegistryWrite;
    try testing.expect(std.mem.indexOf(u8, registry_bytes, "Owner Work") != null);

    try harness.drain();
    try testing.expectEqual(@as(usize, 1), harness.login_launcher.opens);
    try testing.expectEqualStrings("Owner Work", harness.core.accountAt(0).?.label);
    try testing.expect(harness.core.accountAt(0).?.label_is_custom);
}

test "F9 completed Codex login backs up the exact auth file bytes" {
    const io = testing.io;
    var cwd = std.Io.Dir.cwd();
    const relative_root = ".zig-cache/test-f9-login-auth-backup/CodexMulti";
    cwd.deleteTree(io, ".zig-cache/test-f9-login-auth-backup") catch {};
    defer cwd.deleteTree(io, ".zig-cache/test-f9-login-auth-backup") catch {};
    try cwd.createDirPath(io, relative_root ++ "/accounts/" ++ codex_storage_key ++ "/codex");
    const root = try cwd.realPathFileAlloc(io, relative_root, testing.allocator);
    defer testing.allocator.free(root);

    const harness = try Harness.createWithLayout(try runtime_paths.Layout.fromAppDataDir(root));
    defer harness.destroy();
    try harness.addCodex();
    var fake: keychain_test_support.FakeSecItem = .{};
    defer fake.deinit();
    var backend: keychain.macos.SecItemStore = undefined;
    var adapter: keychain.macos.KeychainStore = undefined;
    const credentials = try keychain_test_support.wiredKeychain(&fake, &backend, &adapter);
    var live = harness.live();
    live.credentials = credentials;
    live.codex_cli_too_old = true;
    harness.service.attach(live);
    harness.login_launcher.lines = &.{"Login successful.\n"};
    harness.login_launcher.auth_bytes = codex_auth_backup_bytes;
    fake.resetCalls();

    try testing.expectEqual(
        ui_model.CommandOutcome.accepted_pending,
        harness.service.submit(.{ .reauthenticate = codex_account_id }),
    );
    try harness.drain();

    const account_key = try keychain.AccountKey.init(codex_storage_key);
    var restored: keychain.Credential = .empty;
    defer restored.wipe();
    try credentials.load(&account_key, .codex_auth_backup, &restored);
    try testing.expect(restored.eqlPlaintext(codex_auth_backup_bytes));
    var saw_backup_save = false;
    for (fake.recordedCalls(), 0..) |call, index| {
        if (call != .add and call != .update) continue;
        const item = fake.recordedItems()[index];
        if (!std.mem.eql(u8, item.accountText(), "codex-demo.codex-auth")) continue;
        try testing.expectEqualStrings(keychain.macos.default_service, item.serviceText());
        saw_backup_save = true;
    }
    try testing.expect(saw_backup_save);
}

test "F9 startup restores a missing Codex auth file from Keychain" {
    const io = testing.io;
    var cwd = std.Io.Dir.cwd();
    const parent = ".zig-cache/test-f9-auth-restore";
    const relative_root = parent ++ "/CodexMulti";
    cwd.deleteTree(io, parent) catch {};
    defer cwd.deleteTree(io, parent) catch {};
    try cwd.createDirPath(io, relative_root);
    const root = try cwd.realPathFileAlloc(io, relative_root, testing.allocator);
    defer testing.allocator.free(root);
    const layout = try runtime_paths.Layout.fromAppDataDir(root);
    var app_dir = try cwd.openDir(io, relative_root, .{});
    defer app_dir.close(io);

    const seed = try Harness.createWithLayout(layout);
    try seed.addCodex();
    var file_sink: coordinator.FileDocumentSink = .{ .io = io, .dir = app_dir };
    try seed.core.persistRegistry(file_sink.sink());
    seed.destroy();

    const restarted = try Harness.createWithLayout(layout);
    defer restarted.destroy();
    var live = restarted.live();
    live.sink = file_sink.sink();
    restarted.service.attach(live);
    var backup = try keychain.Credential.init(codex_auth_backup_bytes);
    defer backup.wipe();
    const account_key = try keychain.AccountKey.init(codex_storage_key);
    try restarted.credentials.store().save(&account_key, .codex_auth_backup, &backup);
    restarted.credentials.resetOperations();

    const report = restarted.service.load(io, app_dir);
    try testing.expectEqual(@as(usize, 1), report.accounts_loaded);
    const auth_path = "accounts/" ++ codex_storage_key ++ "/codex/" ++ runtime_paths.codex_auth_file_name;
    const bytes = try app_dir.readFileAlloc(io, auth_path, testing.allocator, .limited(keychain.max_credential_bytes));
    defer testing.allocator.free(bytes);
    try testing.expectEqualStrings(codex_auth_backup_bytes, bytes);
    const stat = try app_dir.statFile(io, auth_path, .{});
    try testing.expectEqual(@as(std.posix.mode_t, 0o600), stat.permissions.toMode() & 0o777);
    try testing.expectEqualSlices(keychain.MemoryStore.Operation, &.{.{
        .action = .load,
        .kind = .codex_auth_backup,
    }}, restarted.credentials.recordedOperations());
}

test "F15 pump detects a changed Codex auth file and resynchronizes its in-memory Keychain backup once" {
    const io = testing.io;
    var cwd = std.Io.Dir.cwd();
    const parent = ".zig-cache/test-f15-auth-resync";
    const relative_root = parent ++ "/CodexMulti";
    const auth_path = "accounts/" ++ codex_storage_key ++ "/codex/" ++ runtime_paths.codex_auth_file_name;
    cwd.deleteTree(io, parent) catch {};
    defer cwd.deleteTree(io, parent) catch {};
    try cwd.createDirPath(io, relative_root ++ "/accounts/" ++ codex_storage_key ++ "/codex");
    const root = try cwd.realPathFileAlloc(io, relative_root, testing.allocator);
    defer testing.allocator.free(root);
    const layout = try runtime_paths.Layout.fromAppDataDir(root);
    var app_dir = try cwd.openDir(io, relative_root, .{});
    defer app_dir.close(io);

    const harness = try Harness.createWithLayout(layout);
    defer harness.destroy();
    try harness.addCodex();
    harness.attach();
    var old_backup = try keychain.Credential.init(codex_auth_backup_bytes);
    defer old_backup.wipe();
    const account_key = try keychain.AccountKey.init(codex_storage_key);
    try harness.credentials.store().save(&account_key, .codex_auth_backup, &old_backup);
    var auth_file = try app_dir.createFile(io, auth_path, .{
        .permissions = std.Io.File.Permissions.fromMode(0o600),
    });
    try auth_file.writeStreamingAll(io, codex_auth_backup_bytes);
    auth_file.close(io);
    harness.service.synchronizeCodexAuthBackups();
    harness.credentials.resetOperations();
    auth_file = try app_dir.createFile(io, auth_path, .{
        .permissions = std.Io.File.Permissions.fromMode(0o600),
    });
    try auth_file.writeStreamingAll(io, rotated_codex_auth_backup_bytes);
    auth_file.close(io);

    harness.service.pump(now + 60);

    var synchronized: keychain.Credential = .empty;
    defer synchronized.wipe();
    try harness.credentials.store().load(&account_key, .codex_auth_backup, &synchronized);
    try testing.expect(synchronized.eqlPlaintext(rotated_codex_auth_backup_bytes));
    harness.credentials.resetOperations();

    harness.service.pump(now + 120);

    try testing.expectEqual(@as(usize, 0), harness.credentials.recordedOperations().len);
}

test "F15 startup resynchronizes an existing Codex auth file to Keychain" {
    const io = testing.io;
    var cwd = std.Io.Dir.cwd();
    const parent = ".zig-cache/test-f9-auth-present";
    const relative_root = parent ++ "/CodexMulti";
    const auth_path = "accounts/" ++ codex_storage_key ++ "/codex/" ++ runtime_paths.codex_auth_file_name;
    cwd.deleteTree(io, parent) catch {};
    defer cwd.deleteTree(io, parent) catch {};
    try cwd.createDirPath(io, relative_root ++ "/accounts/" ++ codex_storage_key ++ "/codex");
    const root = try cwd.realPathFileAlloc(io, relative_root, testing.allocator);
    defer testing.allocator.free(root);
    const layout = try runtime_paths.Layout.fromAppDataDir(root);
    var app_dir = try cwd.openDir(io, relative_root, .{});
    defer app_dir.close(io);

    const seed = try Harness.createWithLayout(layout);
    try seed.addCodex();
    var file_sink: coordinator.FileDocumentSink = .{ .io = io, .dir = app_dir };
    try seed.core.persistRegistry(file_sink.sink());
    seed.destroy();
    var auth_file = try app_dir.createFile(io, auth_path, .{
        .permissions = std.Io.File.Permissions.fromMode(0o600),
    });
    try auth_file.writeStreamingAll(io, rotated_codex_auth_backup_bytes);
    auth_file.close(io);

    const restarted = try Harness.createWithLayout(layout);
    defer restarted.destroy();
    const account_key = try keychain.AccountKey.init(codex_storage_key);
    var stale_backup = try keychain.Credential.init(codex_auth_backup_bytes);
    defer stale_backup.wipe();
    try restarted.credentials.store().save(&account_key, .codex_auth_backup, &stale_backup);
    var live = restarted.live();
    live.sink = file_sink.sink();
    restarted.service.attach(live);
    restarted.credentials.resetOperations();

    const report = restarted.service.load(io, app_dir);
    try testing.expectEqual(@as(usize, 1), report.accounts_loaded);
    try testing.expectEqualSlices(keychain.MemoryStore.Operation, &.{
        .{ .action = .load, .kind = .codex_auth_backup },
        .{ .action = .save, .kind = .codex_auth_backup },
    }, restarted.credentials.recordedOperations());
    var synchronized: keychain.Credential = .empty;
    defer synchronized.wipe();
    try restarted.credentials.store().load(&account_key, .codex_auth_backup, &synchronized);
    try testing.expect(synchronized.eqlPlaintext(rotated_codex_auth_backup_bytes));
}

test "F9 removing a Codex account removes its auth backup" {
    const harness = try Harness.create();
    defer harness.destroy();
    try harness.addCodex();
    harness.attach();
    const account_key = try keychain.AccountKey.init(codex_storage_key);
    var backup = try keychain.Credential.init(codex_auth_backup_bytes);
    defer backup.wipe();
    try harness.credentials.store().save(&account_key, .codex_auth_backup, &backup);
    harness.credentials.resetOperations();

    try testing.expectEqual(
        ui_model.CommandOutcome.accepted_pending,
        harness.service.submit(.{ .remove_account = codex_account_id }),
    );

    var saw_backup_remove = false;
    for (harness.credentials.recordedOperations()) |operation| {
        if (operation.action == .remove and operation.kind == .codex_auth_backup) saw_backup_remove = true;
    }
    try testing.expect(saw_backup_remove);
    try testing.expect(!try harness.credentials.store().contains(&account_key, .codex_auth_backup));
}

test "adding an account creates its isolated homes and starts the official login" {
    const harness = try Harness.create();
    defer harness.destroy();
    harness.attach();
    harness.login_launcher.lines = &.{"Login successful.\n"};

    try testing.expectEqual(
        ui_model.CommandOutcome.accepted_pending,
        harness.service.submit(.{ .add_account = .codex }),
    );
    try testing.expectEqual(@as(usize, 1), harness.core.accountCount());
    const value = harness.core.accountAt(0).?;
    try testing.expect(!value.label_is_custom);

    const paths = try harness.core.config.layout.profilePaths(value.storage_key);
    try testing.expect(harness.directories.ensuredContains(paths.profile_dir.slice()));
    try testing.expect(harness.directories.ensuredContains(paths.codex_home.slice()));
    try testing.expect(!harness.directories.ensuredContains(paths.claude_config_dir.slice()));
    try testing.expect(harness.sink.countOf(.registry) >= 1);

    var dynamic_script_storage: [4096]u8 = undefined;
    const dynamic_script = try std.fmt.bufPrint(
        &dynamic_script_storage,
        "{{\"jsonrpc\":\"2.0\",\"id\":1,\"result\":{{\"userAgent\":\"codex-demo/0.0\",\"codexHome\":\"{s}\"}}}}\n" ++
            "{{\"jsonrpc\":\"2.0\",\"id\":2,\"result\":{s}}}\n" ++
            "{{\"jsonrpc\":\"2.0\",\"id\":3,\"result\":{s}}}\n",
        .{ paths.codex_home.slice(), account_result, rate_limits_result },
    );
    harness.codex_launcher.stream = .{ .chunks = &.{.{ .bytes = dynamic_script }} };
    try harness.drain();
    try testing.expectEqual(@as(usize, 1), harness.login_launcher.opens);
    try testing.expectEqualStrings(codex_executable, harness.login_launcher.argv0());
    try testing.expectEqualStrings(paths.codex_home.slice(), harness.login_launcher.homePath());
    try testing.expectEqual(@as(usize, 1), harness.codex_launcher.opens);
    try testing.expect(harness.core.schedulerIsIdle());

    const identified = harness.core.account(value.id).?;
    try testing.expectEqualStrings("demo-user@example.invalid", identified.provider_email.?);
    try testing.expectEqualStrings("Pro 20x", identified.plan_label.?);
    try testing.expect(!identified.label_is_custom);
    try testing.expectEqualStrings("demo-user@example.invalid", identified.label);
    try testing.expectEqual(domain.SnapshotStatus.fresh, harness.core.snapshotFor(value.id).?.status);
}

test "adding Claude retains the command arm but creates no account" {
    const harness = try Harness.create();
    defer harness.destroy();
    harness.attach();

    try testing.expectEqual(
        ui_model.CommandOutcome.accepted_pending,
        harness.service.submit(.{ .add_account = .claude }),
    );
    try testing.expectEqual(@as(usize, 0), harness.core.accountCount());
    try testing.expectEqual(@as(usize, 0), harness.login_launcher.opens);
    try testing.expectEqual(@as(usize, 0), harness.sink.record_count);
}

test "Claude reauthentication is rejected before browser login" {
    const harness = try Harness.create();
    defer harness.destroy();
    try harness.addClaude();
    harness.attach();

    try testing.expectEqual(
        ui_model.CommandOutcome.rejected_not_allowed,
        harness.service.submit(.{ .reauthenticate = claude_account_id }),
    );
    try testing.expect(harness.core.statusFor(claude_account_id).?.last_attempt_code == null);
    try testing.expectEqual(@as(usize, 0), harness.codex_launcher.opens);
}

test "Claude reauthentication never reaches credential persistence" {
    const harness = try Harness.create();
    defer harness.destroy();
    try harness.addClaude();
    harness.attach();

    try testing.expectEqual(
        ui_model.CommandOutcome.rejected_not_allowed,
        harness.service.submit(.{ .reauthenticate = claude_account_id }),
    );
    try testing.expect(harness.core.snapshotFor(claude_account_id) == null);
    try testing.expect(harness.core.statusFor(claude_account_id).?.last_attempt_code == null);
}

test "adding an account with no provider CLI creates no placeholder" {
    const harness = try Harness.create();
    defer harness.destroy();
    harness.core.config.target.codex_executable = "";
    harness.attach();

    try testing.expectEqual(
        ui_model.CommandOutcome.provider_cli_missing,
        harness.service.submit(.{ .add_account = .codex }),
    );
    try testing.expectEqual(@as(usize, 0), harness.core.accountCount());
    try testing.expectEqual(@as(usize, 0), harness.directories.ensured_count);
    try testing.expectEqual(@as(usize, 0), harness.keys.calls);
    try testing.expectEqual(@as(usize, 0), harness.login_launcher.opens);
    try testing.expectEqual(@as(usize, 0), harness.sink.record_count);
}

test "a login-spec failure rolls a newly added account back atomically" {
    const harness = try Harness.create();
    defer harness.destroy();

    harness.core.config.target.codex_executable = "relative/codex";
    harness.attach();

    try testing.expectEqual(
        ui_model.CommandOutcome.provider_cli_missing,
        harness.service.submit(.{ .add_account = .codex }),
    );
    try testing.expectEqual(@as(usize, 0), harness.core.accountCount());
    try testing.expectEqual(@as(usize, 0), harness.login_launcher.opens);
    try testing.expect(harness.directories.ensured_count >= 2);
    try testing.expect(harness.directories.removed_count >= 1);
    try testing.expect(harness.core.schedulerIsIdle());

    const registry = harness.sink.lastOf(.registry).?;
    try testing.expect(std.mem.indexOf(u8, registry, "acct-codex-") == null);
}

test "Claude reauthentication cannot import into any credential slot" {
    const harness = try Harness.create();
    defer harness.destroy();
    try harness.addClaude();
    harness.attach();

    try testing.expectEqual(
        ui_model.CommandOutcome.rejected_not_allowed,
        harness.service.submit(.{ .reauthenticate = claude_account_id }),
    );
    try testing.expectEqual(@as(usize, 0), harness.login_launcher.opens);
    try testing.expect(harness.core.snapshotFor(claude_account_id) == null);

    const account_key = try keychain.AccountKey.init(claude_storage_key);
    try testing.expect(!try harness.credentials.store().contains(&account_key, .access_token));
    try testing.expect(!try harness.credentials.store().contains(&account_key, .refresh_token));
}

test "a rejected Claude refresh performs no Keychain query" {
    var fake: keychain_test_support.FakeSecItem = .{};
    defer fake.deinit();
    var backend: keychain.macos.SecItemStore = .init(fake.api());
    var primary = try keychain.macos.KeychainStore.init(keychain.macos.v2_service);
    var legacy = try keychain.macos.KeychainStore.init(keychain.macos.legacy_service);
    primary.backend = backend.backend();
    legacy.backend = backend.backend();
    var versioned: keychain.macos.VersionedKeychainStore = .{ .primary = primary.store(), .legacy = legacy.store() };
    const credentials = versioned.store();

    const harness = try Harness.create();
    defer harness.destroy();
    try harness.addClaude();
    const account_key = try keychain.AccountKey.init(claude_storage_key);
    const access = try keychain.Credential.init(canary_access);
    const refresh = try keychain.Credential.init(canary_refresh);
    try credentials.save(&account_key, .access_token, &access);
    try credentials.save(&account_key, .refresh_token, &refresh);
    try harness.core.registry.setAccessExpiry(claude_account_id, now + 3600);
    fake.resetCalls();

    var live = harness.live();
    live.credentials = credentials;
    harness.service.attach(live);
    harness.service.now_unix_s = now;
    try testing.expectEqual(
        ui_model.CommandOutcome.rejected_not_allowed,
        harness.service.submit(.{ .refresh_account = claude_account_id }),
    );

    const items = fake.recordedItems();
    try testing.expectEqual(@as(usize, 0), items.len);
}

test "a service restart leaves Claude reauthentication inert" {
    const harness = try Harness.create();
    defer harness.destroy();
    try harness.addClaude();
    harness.attach();

    try testing.expectEqual(
        ui_model.CommandOutcome.rejected_not_allowed,
        harness.service.submit(.{ .reauthenticate = claude_account_id }),
    );
    try testing.expect(harness.core.account(claude_account_id).?.access_expires_at_unix_s == null);

    harness.service.destroy();
    harness.service = try app_service.Service.create(testing.allocator, harness.core);
    const live = harness.live();
    harness.service.attach(live);
    harness.service.now_unix_s = now;

    try testing.expectEqual(
        ui_model.CommandOutcome.rejected_not_allowed,
        harness.service.submit(.{ .refresh_account = claude_account_id }),
    );
    try testing.expectEqual(
        account_registry.AuthState.connected,
        harness.core.account(claude_account_id).?.auth_state,
    );
}

test "relabel and remove are durable, and removal touches only this app's directories" {
    const harness = try Harness.create();
    defer harness.destroy();
    try harness.addCodex();
    harness.attach();

    const account_key = try keychain.AccountKey.init(codex_storage_key);
    const access = try keychain.Credential.init(canary_access);
    try harness.credentials.store().save(&account_key, .access_token, &access);

    try testing.expectEqual(ui_model.CommandOutcome.accepted_pending, harness.service.submit(.{
        .relabel = .{ .account_id = codex_account_id, .label = "Codex Renamed" },
    }));
    try testing.expectEqualStrings("Codex Renamed", harness.core.account(codex_account_id).?.label);
    try testing.expect(std.mem.indexOf(u8, harness.sink.lastOf(.registry).?, "Codex Renamed") != null);

    try testing.expectEqual(
        ui_model.CommandOutcome.accepted_pending,
        harness.service.submit(.{ .remove_account = codex_account_id }),
    );
    try testing.expectEqual(@as(usize, 0), harness.core.accountCount());
    try testing.expect(!try harness.credentials.store().contains(&account_key, .access_token));
    try testing.expect(harness.directories.removed_count >= 1);
    var index: usize = 0;
    while (index < harness.directories.removed_count) : (index += 1) {
        try testing.expect(std.mem.startsWith(u8, harness.directories.removedAt(index), accounts_root));
    }
}

test "removal is refused while an operation for that account is in flight" {
    const harness = try Harness.create();
    defer harness.destroy();
    try harness.addCodex();
    harness.attach();
    harness.codex_launcher.stream = .{ .chunks = &.{.{ .failure = error.EndOfStream }} };

    _ = harness.service.submit(.{ .refresh_account = codex_account_id });
    try testing.expectEqual(
        ui_model.CommandOutcome.rejected_busy,
        harness.service.submit(.{ .remove_account = codex_account_id }),
    );
    try testing.expectEqual(@as(usize, 1), harness.core.accountCount());
    try harness.drain();
}

test "the whole reset transaction holds one app-server and persists before the send" {
    const harness = try Harness.create();
    defer harness.destroy();
    try harness.addCodex();
    harness.attach();
    harness.codex_launcher.stream = .{ .chunks = &.{.{ .bytes = script_reset_transaction }} };

    try testing.expectEqual(ui_model.CommandOutcome.accepted_pending, harness.service.submit(.{
        .redeem_reset = .{
            .account_id = codex_account_id,
            .expected_available_count = 2,
            .confirmed_at_unix_s = now,
        },
    }));
    try harness.drain();

    try testing.expectEqual(@as(usize, 1), harness.codex_launcher.opens);
    try testing.expect(harness.codex_launcher.lifecycle.reapedExactlyOnce());

    const attempts = harness.core.attempts();
    try testing.expectEqual(@as(usize, 1), attempts.len);
    try testing.expectEqual(domain.ResetAttemptPhase.completed, attempts[0].phase);
    try testing.expectEqual(domain.ResetOutcome.reset, attempts[0].outcome.?);

    try testing.expectEqualStrings("credit-demo-a", attempts[0].selected_credit_id.?);
    try testing.expectEqualStrings("reset-00000001", attempts[0].idempotency_key);

    try testing.expect(harness.sink.countOf(.attempts) >= 3);
    const written = harness.codex_launcher.writtenBytes();
    try testing.expect(std.mem.indexOf(u8, written, codex.method_reset_credit_consume) != null);
    try testing.expect(std.mem.indexOf(u8, written, "reset-00000001") != null);

    const snapshot = harness.core.snapshotFor(codex_account_id).?;
    try testing.expect(snapshot.reset_credits == null);
    try testing.expect(harness.core.schedulerIsIdle());
    try testing.expect(harness.core.pendingAttemptFor(codex_account_id) == null);
}

test "a reset transaction initializes its held app-server exactly once and settles against a stateful server" {
    const harness = try Harness.create();
    defer harness.destroy();
    try harness.addCodex();
    harness.attach();
    const server = try testing.allocator.create(StatefulAppServer);
    defer testing.allocator.destroy(server);
    server.* = .{};
    harness.codex_launcher.custom_stream = server.stream();

    try testing.expectEqual(ui_model.CommandOutcome.accepted_pending, harness.service.submit(.{
        .redeem_reset = .{
            .account_id = codex_account_id,
            .expected_available_count = 2,
            .confirmed_at_unix_s = now,
        },
    }));
    try harness.drain();

    try testing.expectEqual(@as(usize, 1), harness.codex_launcher.opens);
    try testing.expectEqual(@as(usize, 1), server.initialize_requests);
    try testing.expectEqual(@as(usize, 1), server.consume_requests);
    const attempts = harness.core.attempts();
    try testing.expectEqual(@as(usize, 1), attempts.len);
    try testing.expectEqual(domain.ResetAttemptPhase.completed, attempts[0].phase);
    try testing.expectEqual(domain.ResetOutcome.reset, attempts[0].outcome.?);
    try testing.expect(harness.core.pendingAttemptFor(codex_account_id) == null);
    try testing.expect(harness.core.schedulerIsIdle());
}

test "a fresh preflight that disagrees with the confirmed count sends nothing" {
    const harness = try Harness.create();
    defer harness.destroy();
    try harness.addCodex();
    harness.attach();

    harness.codex_launcher.stream = .{ .chunks = &.{.{ .bytes = script_read_single_credit }} };

    try testing.expectEqual(ui_model.CommandOutcome.accepted_pending, harness.service.submit(.{
        .redeem_reset = .{
            .account_id = codex_account_id,
            .expected_available_count = 2,
            .confirmed_at_unix_s = now,
        },
    }));
    try harness.drain();

    try testing.expectEqual(@as(usize, 0), harness.core.attempts().len);
    try testing.expectEqual(@as(usize, 0), harness.sink.countOf(.attempts));
    const written = harness.codex_launcher.writtenBytes();
    try testing.expect(std.mem.indexOf(u8, written, codex.method_reset_credit_consume) == null);
    try testing.expectEqualStrings(coordinator.public_code_offer_changed, harness.service.activity.last_code.?);
    try testing.expect(harness.core.schedulerIsIdle());
}

test "a preflight with no available credit never opens an attempt" {
    const harness = try Harness.create();
    defer harness.destroy();
    try harness.addCodex();
    harness.attach();
    harness.codex_launcher.stream = .{ .chunks = &.{.{ .bytes = script_read_no_credit }} };

    _ = harness.service.submit(.{ .redeem_reset = .{
        .account_id = codex_account_id,
        .expected_available_count = 1,
        .confirmed_at_unix_s = now,
    } });
    try harness.drain();

    try testing.expectEqual(@as(usize, 0), harness.core.attempts().len);
    const written = harness.codex_launcher.writtenBytes();
    try testing.expect(std.mem.indexOf(u8, written, codex.method_reset_credit_consume) == null);
    try testing.expect(harness.core.schedulerIsIdle());
}

test "a reset from the tray surface is refused before a transaction opens" {
    const harness = try Harness.create();
    defer harness.destroy();
    try harness.addCodex();
    harness.attach();

    try testing.expectEqual(ui_model.CommandOutcome.rejected_not_allowed, harness.service.submit(.{
        .redeem_reset = .{
            .account_id = codex_account_id,
            .expected_available_count = 1,
            .confirmed_at_unix_s = now,
            .surface = .tray,
        },
    }));
    try testing.expectEqual(@as(usize, 0), harness.codex_launcher.opens);
    try testing.expectEqual(@as(usize, 0), harness.core.attempts().len);
}

test "an ambiguous consume never retries itself and an explicit retry reuses the key" {
    const harness = try Harness.create();
    defer harness.destroy();
    try harness.addCodex();
    harness.attach();
    harness.codex_launcher.stream = .{ .chunks = &.{.{ .bytes = script_reset_ambiguous }} };

    _ = harness.service.submit(.{ .redeem_reset = .{
        .account_id = codex_account_id,
        .expected_available_count = 2,
        .confirmed_at_unix_s = now,
    } });
    try harness.drain();

    const after_ambiguous = harness.core.attempts();
    try testing.expectEqual(@as(usize, 1), after_ambiguous.len);
    try testing.expectEqualStrings("reset-00000001", after_ambiguous[0].idempotency_key);
    try testing.expect(after_ambiguous[0].outcome == null);
    try testing.expectEqual(@as(usize, 1), harness.service.activity.consumes_sent);

    try testing.expectEqual(@as(usize, 1), harness.codex_launcher.opens);
    try testing.expect(harness.codex_launcher.lifecycle.reapedExactlyOnce());
    try testing.expect(harness.core.schedulerIsIdle());
    try testing.expect(harness.core.pendingAttemptFor(codex_account_id) != null);

    var tick: usize = 0;
    while (tick < 5) : (tick += 1) harness.service.pump(now);
    try testing.expectEqual(@as(usize, 1), harness.service.activity.consumes_sent);
    try testing.expectEqual(@as(usize, 1), harness.core.attempts().len);

    try testing.expectEqual(ui_model.CommandOutcome.rejected_busy, harness.service.submit(.{
        .redeem_reset = .{
            .account_id = codex_account_id,
            .expected_available_count = 1,
            .confirmed_at_unix_s = now,
        },
    }));
    try testing.expectEqual(@as(usize, 1), harness.core.attempts().len);

    harness.codex_launcher.stream = .{ .chunks = &.{.{ .bytes = script_reset_reconcile }} };
    harness.codex_launcher.lifecycle = .{};
    try testing.expectEqual(
        ui_model.CommandOutcome.accepted_pending,
        harness.service.submit(.{ .retry_reset = codex_account_id }),
    );
    try harness.drain();

    const settled = harness.core.attempts();
    try testing.expectEqual(@as(usize, 1), settled.len);
    try testing.expectEqualStrings("reset-00000001", settled[0].idempotency_key);
    try testing.expectEqual(domain.ResetAttemptPhase.completed, settled[0].phase);

    try testing.expectEqual(domain.ResetOutcome.already_redeemed, settled[0].outcome.?);
    try testing.expectEqual(@as(usize, 2), harness.service.activity.consumes_sent);

    try testing.expect(std.mem.indexOf(u8, harness.codex_launcher.writtenBytes(), "reset-00000001") != null);
    try testing.expect(harness.codex_launcher.lifecycle.reapedExactlyOnce());
    try testing.expect(harness.core.schedulerIsIdle());
    try testing.expect(harness.core.pendingAttemptFor(codex_account_id) == null);
}

test "a reconciliation after a restart resends the key the ledger holds" {
    const harness = try Harness.create();
    defer harness.destroy();
    try harness.addCodex();
    harness.attach();
    harness.codex_launcher.stream = .{ .chunks = &.{.{ .bytes = script_reset_ambiguous }} };

    _ = harness.service.submit(.{ .redeem_reset = .{
        .account_id = codex_account_id,
        .expected_available_count = 2,
        .confirmed_at_unix_s = now,
    } });
    try harness.drain();
    const key = harness.core.attempts()[0].idempotency_key;

    harness.service.destroy();
    harness.service = try app_service.Service.create(testing.allocator, harness.core);
    harness.codex_launcher = .{ .stream = .{ .chunks = &.{.{ .bytes = script_reset_reconcile }} } };
    harness.attach();

    var tick: usize = 0;
    while (tick < 5) : (tick += 1) harness.service.pump(now);
    try testing.expectEqual(@as(usize, 0), harness.codex_launcher.opens);
    try testing.expectEqual(@as(usize, 0), harness.service.activity.consumes_sent);

    const plan = harness.service.recoveryPlan();
    try testing.expect(plan.requiresUserAction());
    try testing.expectEqual(coordinator.RecoveryAction.reconcile_read, plan.slice()[0].action);

    try testing.expectEqual(
        ui_model.CommandOutcome.accepted_pending,
        harness.service.submit(.{ .retry_reset = codex_account_id }),
    );
    try harness.drain();

    const settled = harness.core.attempts();
    try testing.expectEqual(@as(usize, 1), settled.len);
    try testing.expectEqualStrings(key, settled[0].idempotency_key);
    try testing.expectEqual(domain.ResetOutcome.already_redeemed, settled[0].outcome.?);
    try testing.expectEqual(@as(usize, 1), harness.service.activity.consumes_sent);
}

test "a settled reset clears the mapped account's proxy cooldown exactly once and applies the receipt" {
    const harness = try Harness.create();
    defer harness.destroy();
    try harness.addCodex();
    const replies = [_]FakeProxyExchange.Reply{
        .{ .status = 200, .body = proxy_cooldown_status_v2 },
        .{ .status = 200, .body = "{\"name\":\"codex-1\",\"state\":\"READY\",\"cooldown_until\":null}" },
    };
    harness.proxy_exchange.replies = &replies;
    harness.parent_env = &proxy_env;
    harness.attach();
    try saveProxySettings(harness);
    try testing.expectEqual(ui_model.CommandOutcome.accepted_pending, harness.service.submit(.proxy_refresh_status));
    try harness.drainAll();
    try testing.expectEqual(app_service.ProxyReachability.reachable, harness.service.proxyState().reachability);
    try testing.expectEqual(proxy_control.AccountState.cooldown, harness.service.proxyState().last_success.?.accountAt(0).?.state);
    try testing.expectEqual(ui_model.ResetProxyClear.none, try projectedProxyClear(harness));

    const server = try testing.allocator.create(StatefulAppServer);
    defer testing.allocator.destroy(server);
    server.* = .{};
    try runSettledReset(harness, server);

    try testing.expectEqual(@as(usize, 2), harness.proxy_exchange.calls);
    try testing.expectEqualStrings("/_proxy/accounts/codex-1/clear-cooldown", harness.proxy_exchange.lastPath());
    const account = harness.service.proxyState().last_success.?.accountAt(0).?;
    try testing.expectEqual(proxy_control.AccountState.ready, account.state);
    try testing.expectEqual(@as(?i64, null), account.cooldown_until_unix_s);
    try testing.expectEqual(ui_model.ResetProxyClear.cleared, harness.service.resetProxyClearFor(codex_account_id));
    try testing.expectEqual(ui_model.ResetProxyClear.cleared, try projectedProxyClear(harness));

    harness.service.pump(now);
    harness.service.pump(now);
    try testing.expectEqual(@as(usize, 2), harness.proxy_exchange.calls);
}

test "a settled reset without a reachable mapped proxy row submits nothing and says why" {
    const cold = try Harness.create();
    defer cold.destroy();
    try cold.addCodex();
    cold.parent_env = &proxy_env;
    cold.attach();
    try saveProxySettings(cold);
    const cold_server = try testing.allocator.create(StatefulAppServer);
    defer testing.allocator.destroy(cold_server);
    cold_server.* = .{};
    try runSettledReset(cold, cold_server);
    try testing.expectEqual(@as(usize, 0), cold.proxy_exchange.calls);
    try testing.expectEqual(ui_model.ResetProxyClear.@"unreachable", cold.service.resetProxyClearFor(codex_account_id));
    try testing.expectEqual(ui_model.ResetProxyClear.@"unreachable", try projectedProxyClear(cold));

    const unmapped = try Harness.create();
    defer unmapped.destroy();
    try unmapped.addCodex();
    const replies = [_]FakeProxyExchange.Reply{.{ .status = 200, .body = proxy_unmapped_status_v2 }};
    unmapped.proxy_exchange.replies = &replies;
    unmapped.parent_env = &proxy_env;
    unmapped.attach();
    try saveProxySettings(unmapped);
    _ = unmapped.service.submit(.proxy_refresh_status);
    try unmapped.drainAll();
    try testing.expectEqual(app_service.ProxyReachability.reachable, unmapped.service.proxyState().reachability);
    const server = try testing.allocator.create(StatefulAppServer);
    defer testing.allocator.destroy(server);
    server.* = .{};
    try runSettledReset(unmapped, server);
    try testing.expectEqual(@as(usize, 1), unmapped.proxy_exchange.calls);
    try testing.expectEqual(ui_model.ResetProxyClear.not_mapped, unmapped.service.resetProxyClearFor(codex_account_id));
    try testing.expectEqual(ui_model.ResetProxyClear.not_mapped, try projectedProxyClear(unmapped));
}

test "a proxy that refuses the automatic cooldown clear is reported as failed without a retry" {
    const harness = try Harness.create();
    defer harness.destroy();
    try harness.addCodex();
    const replies = [_]FakeProxyExchange.Reply{
        .{ .status = 200, .body = proxy_cooldown_status_v2 },
        .{ .status = 409, .body = "{\"error\":\"account_paused\"}" },
    };
    harness.proxy_exchange.replies = &replies;
    harness.parent_env = &proxy_env;
    harness.attach();
    try saveProxySettings(harness);
    _ = harness.service.submit(.proxy_refresh_status);
    try harness.drainAll();
    const server = try testing.allocator.create(StatefulAppServer);
    defer testing.allocator.destroy(server);
    server.* = .{};
    try runSettledReset(harness, server);
    try testing.expectEqual(@as(usize, 2), harness.proxy_exchange.calls);
    try testing.expectEqual(ui_model.ResetProxyClear.failed, harness.service.resetProxyClearFor(codex_account_id));
    try testing.expectEqual(proxy_control.AccountState.cooldown, harness.service.proxyState().last_success.?.accountAt(0).?.state);
    harness.service.pump(now);
    try testing.expectEqual(@as(usize, 2), harness.proxy_exchange.calls);
}

test "a second reset is refused while one transaction is open" {
    const harness = try Harness.create();
    defer harness.destroy();
    try harness.addCodex();
    harness.attach();
    harness.codex_launcher.stream = .{ .chunks = &.{.{ .bytes = script_reset_transaction }} };

    const request: ui_model.Command = .{ .redeem_reset = .{
        .account_id = codex_account_id,
        .expected_available_count = 2,
        .confirmed_at_unix_s = now,
    } };
    try testing.expectEqual(ui_model.CommandOutcome.accepted_pending, harness.service.submit(request));
    try testing.expectEqual(ui_model.CommandOutcome.rejected_busy, harness.service.submit(request));
    try harness.drain();
    try testing.expectEqual(@as(usize, 1), harness.core.attempts().len);
}

test "a retry is refused when no unsettled attempt is waiting for one" {
    const harness = try Harness.create();
    defer harness.destroy();
    try harness.addCodex();
    harness.attach();

    try testing.expectEqual(
        ui_model.CommandOutcome.offer_unavailable,
        harness.service.submit(.{ .retry_reset = codex_account_id }),
    );
    try testing.expectEqual(@as(usize, 0), harness.codex_launcher.opens);
}

test "no document the service writes carries credential material" {
    const harness = try Harness.create();
    defer harness.destroy();
    try harness.addCodex();
    try harness.addClaude();
    harness.attach();
    harness.login_launcher.lines = &.{"Login successful.\n"};
    harness.codex_launcher.stream = .{ .chunks = &.{.{ .bytes = script_reset_transaction }} };

    _ = harness.service.submit(.{ .reauthenticate = claude_account_id });
    try harness.drain();
    _ = harness.service.submit(.{ .redeem_reset = .{
        .account_id = codex_account_id,
        .expected_available_count = 2,
        .confirmed_at_unix_s = now,
    } });
    try harness.drain();

    const bytes = harness.sink.allBytes();
    try testing.expect(bytes.len != 0);
    const forbidden = [_][]const u8{
        canary_access,
        canary_refresh,
        "access_token",
        "refresh_token",
        "authorization",
        "Bearer ",
    };
    for (forbidden) |needle| {
        try testing.expect(std.mem.indexOf(u8, bytes, needle) == null);
    }
}

test "shutdown leaves no worker running and no child unreaped" {
    const harness = try Harness.create();
    defer harness.destroy();
    try harness.addCodex();
    harness.attach();
    harness.codex_launcher.stream = .{ .chunks = &.{.{ .bytes = script_read }} };

    _ = harness.service.submit(.{ .refresh_account = codex_account_id });
    harness.service.shutdown();

    try testing.expectEqual(@as(usize, 0), harness.service.busyWorkerCount());
    try testing.expect(!harness.service.proxyWorkerBusy());
    try testing.expect(!harness.service.isAttached());

    try testing.expect(harness.codex_launcher.opens <= 1);

    harness.service.shutdown();
}

test "shutdown and reattach keep Claude login inert" {
    const harness = try Harness.create();
    defer harness.destroy();
    try harness.addClaude();
    harness.attach();

    try testing.expectEqual(
        ui_model.CommandOutcome.rejected_not_allowed,
        harness.service.submit(.{ .reauthenticate = claude_account_id }),
    );
    harness.service.shutdown();
    try testing.expect(harness.core.schedulerIsIdle());
    try testing.expectEqual(@as(usize, 0), harness.service.busyWorkerCount());

    harness.attach();
    try testing.expectEqual(
        ui_model.CommandOutcome.rejected_not_allowed,
        harness.service.submit(.{ .reauthenticate = claude_account_id }),
    );
    try testing.expectEqual(account_registry.AuthState.connected, harness.core.account(claude_account_id).?.auth_state);
}

test "the executable resolver only accepts an absolute, executable path entry" {
    var resolved: app_service.ExecutablePath = .{};

    try testing.expect(!app_service.resolveExecutable(
        testing.io,
        "relative/bin:/demo/definitely-not-here",
        "codex",
        &resolved,
    ));
    try testing.expect(resolved.isEmpty());

    try testing.expect(!app_service.resolveExecutable(testing.io, "/usr/bin", "", &resolved));
    try testing.expect(resolved.isEmpty());
}

test "the GUI executable resolver finds a user-local CLI outside Finder PATH" {
    const io = testing.io;
    var cwd = std.Io.Dir.cwd();
    const root = ".zig-cache/test-provider-executable";
    cwd.deleteTree(io, root) catch {};
    defer cwd.deleteTree(io, root) catch {};
    try cwd.createDirPath(io, root ++ "/home/.local/bin");
    var executable = try cwd.createFile(io, root ++ "/home/.local/bin/codex", .{
        .permissions = .executable_file,
    });
    try executable.writeStreamingAll(io, "#!/bin/sh\n");
    executable.close(io);

    const home = try cwd.realPathFileAlloc(io, root ++ "/home", testing.allocator);
    defer testing.allocator.free(home);
    var resolved: app_service.ExecutablePath = .{};
    try testing.expect(app_service.resolveProviderExecutable(
        io,
        "/usr/bin:/bin",
        home,
        "codex",
        &resolved,
    ));
    try testing.expect(std.mem.endsWith(u8, resolved.slice(), "/.local/bin/codex"));
}

test "every code this module can originate is sanitized before it is shown" {
    for (app_service.public_codes) |code| {
        try testing.expect(app_service.isPublicCode(code));

        try testing.expectEqualStrings(
            coordinator.public_code_refresh_failed,
            coordinator.canonicalPublicCode(code),
        );
    }
}

test "declarations stay analyzable" {
    testing.refAllDecls(app_service);
    testing.refAllDecls(ui_model);
    _ = store;
    _ = transport;
    _ = login_runtime;
}
