const std = @import("std");
const app_service = @import("../app_service.zig");
const coordinator = @import("../coordinator.zig");
const domain = @import("../domain.zig");
const keychain = @import("../keychain.zig");
const proxy = @import("../proxy_control_client.zig");
const importer = @import("../proxy_import_runner.zig");
const runtime_paths = @import("../runtime_paths.zig");
const transport = @import("../process_jsonl.zig");
const ui_model = @import("../ui_model.zig");

const testing = std.testing;

const now: i64 = 2_000_000_000;
const home = "/private/tmp/codexmulti-service/home";
const app_root = home ++ "/Library/Application Support/" ++ runtime_paths.app_data_directory_name;
const config_path = "/private/tmp/codexmulti-service/proxy/config.json";
const cli_path = "/private/tmp/codexmulti-service/bin/codexmulti-proxy";
const account_id = "acct-proxy-fixture";
const storage_key = "proxy-fixture";
const auth_file = app_root ++ "/accounts/" ++ storage_key ++ "/codex/auth.json";

const status_v2 =
    "{\"version\":2,\"config_path\":\"" ++ config_path ++
    "\",\"active\":\"codex-1\",\"cursor\":\"codex-1\",\"in_flight\":0,\"accounts\":[{" ++
    "\"name\":\"codex-1\",\"label\":\"Fixture\",\"auth_file\":\"" ++ auth_file ++
    "\",\"state\":\"READY\",\"cooldown_until\":null,\"reason\":null,\"token_expires_at\":null,\"in_flight\":0}]}";

const paused_status_v2 =
    "{\"version\":2,\"config_path\":\"" ++ config_path ++
    "\",\"active\":null,\"cursor\":\"codex-1\",\"in_flight\":0,\"accounts\":[{" ++
    "\"name\":\"codex-1\",\"label\":\"Fixture\",\"auth_file\":\"" ++ auth_file ++
    "\",\"state\":\"PAUSED\",\"cooldown_until\":null,\"reason\":\"operator_paused\",\"token_expires_at\":null,\"in_flight\":0}]}";

const inactive_status_v2 =
    "{\"version\":2,\"config_path\":\"" ++ config_path ++
    "\",\"active\":null,\"cursor\":\"codex-1\",\"in_flight\":0,\"accounts\":[{" ++
    "\"name\":\"codex-1\",\"label\":\"Fixture\",\"auth_file\":\"" ++ auth_file ++
    "\",\"state\":\"PAUSED\",\"cooldown_until\":null,\"reason\":\"operator_paused\",\"token_expires_at\":null,\"in_flight\":0}]}";

const mismatched_status_v2 =
    "{\"version\":2,\"config_path\":\"/private/tmp/codexmulti-service/other/config.json\"" ++
    ",\"active\":\"codex-1\",\"cursor\":\"codex-1\",\"in_flight\":0,\"accounts\":[{" ++
    "\"name\":\"codex-1\",\"label\":\"Fixture\",\"auth_file\":\"" ++ auth_file ++
    "\",\"state\":\"READY\",\"cooldown_until\":null,\"reason\":null,\"token_expires_at\":null,\"in_flight\":0}]}";

const status_v1 =
    "{\"version\":1,\"active\":\"codex-1\",\"cursor\":\"codex-1\",\"in_flight\":0," ++
    "\"accounts\":[{\"name\":\"codex-1\",\"state\":\"READY\",\"cooldown_until\":null," ++
    "\"reason\":null,\"token_expires_at\":null,\"in_flight\":0}]}";

const StepOrder = struct {
    values: [8]u8 = @splat(0),
    count: usize = 0,

    fn push(self: *StepOrder, value: u8) void {
        self.values[self.count] = value;
        self.count += 1;
    }
};

const FakeExchange = struct {
    const Reply = union(enum) { response: struct { status: u16, body: []const u8 }, failure: proxy.TransportError };

    replies: []const Reply = &.{},
    reply_index: usize = 0,
    calls: usize = 0,
    order: ?*StepOrder = null,
    last_path: [proxy.max_request_path_bytes]u8 = @splat(0),
    last_path_len: usize = 0,

    const vtable: proxy.Exchange.VTable = .{ .perform = perform };

    fn exchange(self: *FakeExchange) proxy.Exchange {
        return .{ .context = self, .vtable = &vtable };
    }

    fn perform(context: *anyopaque, request: proxy.Request, response_buffer: []u8) proxy.TransportError!proxy.ExchangeResult {
        const self: *FakeExchange = @ptrCast(@alignCast(context));
        self.calls += 1;
        if (self.order) |order| order.push(2);
        self.last_path_len = request.path.len;
        @memcpy(self.last_path[0..request.path.len], request.path);
        if (self.reply_index >= self.replies.len) return error.Network;
        const reply = self.replies[self.reply_index];
        self.reply_index += 1;
        return switch (reply) {
            .failure => |failure| failure,
            .response => |response| blk: {
                if (response.body.len > response_buffer.len) return error.ResponseTooLarge;
                @memcpy(response_buffer[0..response.body.len], response.body);
                break :blk .{ .status = response.status, .body_len = response.body.len };
            },
        };
    }

    fn lastPath(self: *const FakeExchange) []const u8 {
        return self.last_path[0..self.last_path_len];
    }
};

const fixture_node_path = "/private/tmp/codexmulti-fixture/bin/node";

const FakeNodeResolver = struct {
    auto_path: ?[]const u8 = fixture_node_path,
    calls: usize = 0,

    const vtable: importer.NodeResolver.VTable = .{ .resolve = resolve };

    fn resolver(self: *FakeNodeResolver) importer.NodeResolver {
        return .{ .context = self, .vtable = &vtable };
    }

    fn resolve(context: *anyopaque, options: importer.NodeSearch, out: *runtime_paths.Path) bool {
        const self: *FakeNodeResolver = @ptrCast(@alignCast(context));
        self.calls += 1;
        out.* = .{};
        if (options.configured) |configured| {
            if (!std.mem.eql(u8, configured, fixture_node_path)) return false;
            out.* = runtime_paths.Path.init(configured) catch return false;
            return true;
        }
        const path = self.auto_path orelse return false;
        out.* = runtime_paths.Path.init(path) catch return false;
        return true;
    }
};

const FakeImporter = struct {
    outcome: importer.Outcome = .success,
    calls: usize = 0,
    order: ?*StepOrder = null,
    last_node: [runtime_paths.max_path_bytes]u8 = @splat(0),
    last_node_len: usize = 0,
    last_cli: [runtime_paths.max_path_bytes]u8 = @splat(0),
    last_cli_len: usize = 0,
    last_store: [runtime_paths.max_path_bytes]u8 = @splat(0),
    last_store_len: usize = 0,
    last_config: [runtime_paths.max_path_bytes]u8 = @splat(0),
    last_config_len: usize = 0,

    const vtable: importer.Runner.VTable = .{ .run = run };

    fn runner(self: *FakeImporter) importer.Runner {
        return .{ .context = self, .vtable = &vtable };
    }

    fn run(context: *anyopaque, request: importer.Request) importer.Outcome {
        const self: *FakeImporter = @ptrCast(@alignCast(context));
        self.calls += 1;
        if (self.order) |order| order.push(1);
        copy(&self.last_node, &self.last_node_len, request.node_path);
        copy(&self.last_cli, &self.last_cli_len, request.cli_path);
        copy(&self.last_store, &self.last_store_len, request.app_root);
        copy(&self.last_config, &self.last_config_len, request.config_path);
        return self.outcome;
    }

    fn copy(buffer: []u8, len: *usize, value: []const u8) void {
        @memcpy(buffer[0..value.len], value);
        len.* = value.len;
    }
};

const RecordingSink = struct {
    kinds: [32]runtime_paths.DocumentKind = @splat(.registry),
    count: usize = 0,
    fail_proxy_status: bool = false,

    const vtable: coordinator.DocumentSink.VTable = .{ .write = write };

    fn sink(self: *RecordingSink) coordinator.DocumentSink {
        return .{ .context = self, .vtable = &vtable };
    }

    fn write(context: *anyopaque, kind: runtime_paths.DocumentKind, _: []const u8) coordinator.SinkError!void {
        const self: *RecordingSink = @ptrCast(@alignCast(context));
        if (self.fail_proxy_status and kind == .proxy_status) return error.Io;
        self.kinds[self.count] = kind;
        self.count += 1;
    }

    fn countOf(self: *const RecordingSink, kind: runtime_paths.DocumentKind) usize {
        var result: usize = 0;
        for (self.kinds[0..self.count]) |value| {
            if (value == kind) result += 1;
        }
        return result;
    }
};

const Harness = struct {
    core: *coordinator.Coordinator,
    service: *app_service.Service,
    credentials: keychain.MemoryStore = .{},
    sink: RecordingSink = .{},
    exchange: FakeExchange = .{},
    import_runner: FakeImporter = .{},
    node_resolver: FakeNodeResolver = .{},

    fn create(replies: []const FakeExchange.Reply) !*Harness {
        const layout = try runtime_paths.Layout.fromHomeDir(home);
        const core = try coordinator.Coordinator.create(testing.allocator, .{ .layout = layout });
        errdefer core.destroy();
        const self = try testing.allocator.create(Harness);
        self.* = .{
            .core = core,
            .service = try app_service.Service.create(testing.allocator, core),
            .exchange = .{ .replies = replies },
        };
        return self;
    }

    fn destroy(self: *Harness) void {
        self.service.destroy();
        self.core.destroy();
        self.credentials.deinit();
        testing.allocator.destroy(self);
    }

    fn attach(self: *Harness) void {
        const env = &[_]transport.EnvVar{
            .{ .name = "PATH", .value = "/usr/bin:/bin" },
            .{ .name = "HOME", .value = home },
            .{ .name = "TMPDIR", .value = "/private/tmp" },
        };
        self.service.attach(.{
            .io = testing.io,
            .allocator = testing.allocator,
            .sink = self.sink.sink(),
            .credentials = self.credentials.store(),
            .parent_env = .{ .pairs = env },
            .proxy_exchange = self.exchange.exchange(),
            .proxy_importer = self.import_runner.runner(),
            .proxy_node_resolver = self.node_resolver.resolver(),
        });
        self.service.now_unix_s = now;
    }

    fn addCodex(self: *Harness) !void {
        _ = try self.core.addAccount(.{
            .id = account_id,
            .provider = .codex,
            .label = "Fixture",
            .storage_key = storage_key,
            .created_at_unix_s = now - 10,
        });
        _ = try self.core.registry.markConnected(account_id, null);
    }

    fn saveSettings(self: *Harness) !void {
        try testing.expectEqual(ui_model.CommandOutcome.accepted_pending, self.service.submit(.{ .save_proxy_settings = .{
            .base_url = "http://127.0.0.1:48787",
            .cli_path = cli_path,
            .config_path = config_path,
        } }));
    }

    fn drainProxy(self: *Harness) !void {
        var spins: usize = 0;
        while (self.service.proxyWorkerBusy()) {
            self.service.pump(self.service.now_unix_s);
            spins += 1;
            if (spins > 4_000) return error.WorkerDidNotFinish;
            testing.io.sleep(.fromMilliseconds(1), .awake) catch {};
        }
        self.service.pump(self.service.now_unix_s);
    }
};

test "proxy service load project and idle pump are passive" {
    const harness = try Harness.create(&.{});
    defer harness.destroy();
    harness.attach();
    var view: ui_model.ViewState = .{};
    harness.service.project(&view);
    harness.service.pump(now);
    try testing.expectEqual(@as(usize, 0), harness.exchange.calls);
    try testing.expectEqual(@as(usize, 0), harness.import_runner.calls);
    try testing.expectEqual(@as(usize, 0), harness.sink.count);
    try testing.expectEqual(app_service.ProxyReachability.unknown, harness.service.proxyState().reachability);
}

test "explicit proxy refresh persists one mapped v2 snapshot" {
    const replies = [_]FakeExchange.Reply{.{ .response = .{ .status = 200, .body = status_v2 } }};
    const harness = try Harness.create(&replies);
    defer harness.destroy();
    try harness.addCodex();
    harness.attach();
    try harness.saveSettings();

    try testing.expectEqual(ui_model.CommandOutcome.accepted_pending, harness.service.submit(.proxy_refresh_status));
    try harness.drainProxy();
    const state = harness.service.proxyState();
    try testing.expectEqual(app_service.ProxyReachability.reachable, state.reachability);
    try testing.expect(state.last_success != null);
    try testing.expect(state.last_success.?.accountAt(0).?.mapped);
    try testing.expectEqual(@as(usize, 1), harness.sink.countOf(.proxy_status));
}

test "one proxy worker rejects overlap and action names are resolved from latest mapping" {
    const replies = [_]FakeExchange.Reply{
        .{ .response = .{ .status = 200, .body = status_v2 } },
        .{ .response = .{ .status = 200, .body = paused_status_v2 } },
    };
    const harness = try Harness.create(&replies);
    defer harness.destroy();
    try harness.addCodex();
    harness.attach();
    try harness.saveSettings();
    _ = harness.service.submit(.proxy_refresh_status);
    try testing.expectEqual(ui_model.CommandOutcome.rejected_busy, harness.service.submit(.proxy_refresh_status));
    try harness.drainProxy();

    try testing.expectEqual(ui_model.CommandOutcome.accepted_pending, harness.service.submit(.{ .proxy_reload_account = account_id }));
    try harness.drainProxy();
    try testing.expectEqualStrings("/_proxy/accounts/codex-1/reload", harness.exchange.lastPath());
    try testing.expectEqual(ui_model.CommandOutcome.rejected_unknown_account, harness.service.submit(.{ .proxy_switch_account = "missing" }));
}

test "pause accepts the nonblocking receipt and leaves drain observation to refresh" {
    const replies = [_]FakeExchange.Reply{
        .{ .response = .{ .status = 200, .body = status_v2 } },
        .{ .response = .{ .status = 202, .body = "{\"name\":\"codex-1\",\"state\":\"PAUSED\",\"in_flight\":1}" } },
    };
    const harness = try Harness.create(&replies);
    defer harness.destroy();
    try harness.addCodex();
    harness.attach();
    try harness.saveSettings();
    _ = harness.service.submit(.proxy_refresh_status);
    try harness.drainProxy();

    try testing.expectEqual(ui_model.CommandOutcome.accepted_pending, harness.service.submit(.{ .proxy_pause_account = account_id }));
    try harness.drainProxy();
    const account = harness.service.proxyState().last_success.?.accountAt(0).?;
    try testing.expectEqual(proxy.AccountState.paused, account.state);
    try testing.expectEqual(@as(u32, 1), account.in_flight);
    try testing.expectEqualStrings("/_proxy/accounts/codex-1/pause", harness.exchange.lastPath());
}

const cooldown_status_v2 =
    "{\"version\":2,\"config_path\":\"" ++ config_path ++
    "\",\"active\":null,\"cursor\":\"codex-1\",\"in_flight\":0,\"accounts\":[{" ++
    "\"name\":\"codex-1\",\"label\":\"Fixture\",\"auth_file\":\"" ++ auth_file ++
    "\",\"state\":\"COOLDOWN\",\"cooldown_until\":\"2030-01-01T00:01:02Z\",\"reason\":\"usage_limit_reached\",\"token_expires_at\":null,\"in_flight\":0}]}";

test "clear cooldown applies the returned row to the last-seen table without a status refresh" {
    const replies = [_]FakeExchange.Reply{
        .{ .response = .{ .status = 200, .body = cooldown_status_v2 } },
        .{ .response = .{ .status = 200, .body = "{\"name\":\"codex-1\",\"state\":\"READY\",\"cooldown_until\":null}" } },
    };
    const harness = try Harness.create(&replies);
    defer harness.destroy();
    try harness.addCodex();
    harness.attach();
    try harness.saveSettings();
    _ = harness.service.submit(.proxy_refresh_status);
    try harness.drainProxy();
    try testing.expectEqual(proxy.AccountState.cooldown, harness.service.proxyState().last_success.?.accountAt(0).?.state);
    const revision_before = harness.service.proxyState().success_revision;

    try testing.expectEqual(ui_model.CommandOutcome.accepted_pending, harness.service.submit(.{ .proxy_clear_cooldown = account_id }));
    try testing.expectEqual(ui_model.CommandOutcome.rejected_busy, harness.service.submit(.{ .proxy_clear_cooldown = account_id }));
    try harness.drainProxy();
    try testing.expectEqualStrings("/_proxy/accounts/codex-1/clear-cooldown", harness.exchange.lastPath());
    try testing.expectEqual(@as(usize, 2), harness.exchange.calls);
    const account = harness.service.proxyState().last_success.?.accountAt(0).?;
    try testing.expectEqual(proxy.AccountState.ready, account.state);
    try testing.expectEqual(@as(?i64, null), account.cooldown_until_unix_s);
    try testing.expectEqual(app_service.ProxyAttemptResult.ok, harness.service.proxyState().last_attempt.?.result);

    try testing.expectEqual(revision_before, harness.service.proxyState().success_revision);
    try testing.expectEqual(@as(usize, 0), harness.service.busyWorkerCount());
}

test "clear cooldown rejection keeps the cooldown row and reports an action failure" {
    const replies = [_]FakeExchange.Reply{
        .{ .response = .{ .status = 200, .body = cooldown_status_v2 } },
        .{ .response = .{ .status = 409, .body = "{\"error\":\"account_paused\"}" } },
    };
    const harness = try Harness.create(&replies);
    defer harness.destroy();
    try harness.addCodex();
    harness.attach();
    try harness.saveSettings();
    _ = harness.service.submit(.proxy_refresh_status);
    try harness.drainProxy();
    _ = harness.service.submit(.{ .proxy_clear_cooldown = account_id });
    try harness.drainProxy();
    try testing.expectEqual(proxy.AccountState.cooldown, harness.service.proxyState().last_success.?.accountAt(0).?.state);
    try testing.expectEqual(app_service.ProxyAttemptResult.action_failed, harness.service.proxyState().last_attempt.?.result);
    try testing.expectEqual(app_service.ProxyReachability.reachable, harness.service.proxyState().reachability);

    const cold = try Harness.create(&.{});
    defer cold.destroy();
    try cold.addCodex();
    cold.attach();
    try cold.saveSettings();
    try testing.expectEqual(ui_model.CommandOutcome.rejected_not_allowed, cold.service.submit(.{ .proxy_clear_cooldown = account_id }));
}

test "mapped removal is refused until pause is confirmed by a later drained status" {
    const replies = [_]FakeExchange.Reply{
        .{ .response = .{ .status = 200, .body = status_v2 } },
        .{ .response = .{ .status = 202, .body = "{\"name\":\"codex-1\",\"state\":\"PAUSED\",\"in_flight\":0}" } },
        .{ .response = .{ .status = 200, .body = paused_status_v2 } },
    };
    const harness = try Harness.create(&replies);
    defer harness.destroy();
    try harness.addCodex();
    harness.attach();
    try harness.saveSettings();
    _ = harness.service.submit(.proxy_refresh_status);
    try harness.drainProxy();

    try testing.expectEqual(ui_model.CommandOutcome.rejected_not_allowed, harness.service.submit(.{ .remove_account = account_id }));
    try testing.expectEqual(@as(usize, 1), harness.core.accountCount());

    _ = harness.service.submit(.{ .proxy_pause_account = account_id });
    try harness.drainProxy();
    try testing.expectEqual(ui_model.CommandOutcome.rejected_not_allowed, harness.service.submit(.{ .remove_account = account_id }));
    try testing.expectEqual(@as(usize, 1), harness.core.accountCount());

    _ = harness.service.submit(.proxy_refresh_status);
    try harness.drainProxy();
    try testing.expectEqual(ui_model.CommandOutcome.accepted_pending, harness.service.submit(.{ .remove_account = account_id }));
    try testing.expectEqual(@as(usize, 0), harness.core.accountCount());
}

test "switch response must make the requested mapped account active" {
    const replies = [_]FakeExchange.Reply{
        .{ .response = .{ .status = 200, .body = status_v2 } },
        .{ .response = .{ .status = 200, .body = inactive_status_v2 } },
    };
    const harness = try Harness.create(&replies);
    defer harness.destroy();
    try harness.addCodex();
    harness.attach();
    try harness.saveSettings();
    _ = harness.service.submit(.proxy_refresh_status);
    try harness.drainProxy();
    _ = harness.service.submit(.{ .proxy_switch_account = account_id });
    try harness.drainProxy();
    try testing.expectEqual(app_service.ProxyAttemptResult.action_failed, harness.service.proxyState().last_attempt.?.result);
    try testing.expect(harness.service.proxyState().last_success.?.accountAt(0).?.active);
}

test "v1 and mismatched config disable account control without erasing last success" {
    const replies = [_]FakeExchange.Reply{
        .{ .response = .{ .status = 200, .body = status_v2 } },
        .{ .response = .{ .status = 200, .body = status_v1 } },
        .{ .response = .{ .status = 200, .body = mismatched_status_v2 } },
    };
    const harness = try Harness.create(&replies);
    defer harness.destroy();
    try harness.addCodex();
    harness.attach();
    try harness.saveSettings();
    _ = harness.service.submit(.proxy_refresh_status);
    try harness.drainProxy();
    _ = harness.service.submit(.proxy_refresh_status);
    try harness.drainProxy();
    try testing.expectEqual(app_service.ProxyReachability.incompatible, harness.service.proxyState().reachability);
    try testing.expect(harness.service.proxyState().last_success != null);

    _ = harness.service.submit(.proxy_refresh_status);
    try harness.drainProxy();
    try testing.expectEqual(app_service.ProxyAttemptResult.config_mismatch, harness.service.proxyState().last_attempt.?.result);
    try testing.expect(!harness.service.proxyState().config_path_matches);
    try testing.expectEqual(ui_model.CommandOutcome.rejected_not_allowed, harness.service.submit(.{ .proxy_reload_account = account_id }));
}

test "sync runs importer before reload and verifies the ordered mapped result" {
    const replies = [_]FakeExchange.Reply{
        .{ .response = .{ .status = 200, .body = status_v2 } },
        .{ .response = .{ .status = 200, .body = status_v2 } },
    };
    const harness = try Harness.create(&replies);
    defer harness.destroy();
    try harness.addCodex();
    var order: StepOrder = .{};
    harness.exchange.order = &order;
    harness.import_runner.order = &order;
    harness.attach();
    try harness.saveSettings();
    _ = harness.service.submit(.proxy_refresh_status);
    try harness.drainProxy();
    order = .{};

    try testing.expectEqual(ui_model.CommandOutcome.accepted_pending, harness.service.submit(.proxy_sync_config));
    try harness.drainProxy();
    try testing.expectEqualSlices(u8, &.{ 1, 2 }, order.values[0..order.count]);
    try testing.expectEqual(@as(usize, 1), harness.import_runner.calls);
    try testing.expectEqualStrings("/_proxy/reload-config", harness.exchange.lastPath());
    try testing.expectEqual(app_service.ProxySyncState.synced, harness.service.proxyState().sync_state);
    try testing.expectEqual(@as(usize, 2), harness.sink.countOf(.proxy_settings));
}

test "sync hands the resolved node binary to the importer" {
    const replies = [_]FakeExchange.Reply{
        .{ .response = .{ .status = 200, .body = status_v2 } },
        .{ .response = .{ .status = 200, .body = status_v2 } },
    };
    const harness = try Harness.create(&replies);
    defer harness.destroy();
    try harness.addCodex();
    harness.attach();
    try harness.saveSettings();
    _ = harness.service.submit(.proxy_refresh_status);
    try harness.drainProxy();

    try testing.expectEqual(ui_model.CommandOutcome.accepted_pending, harness.service.submit(.proxy_sync_config));
    try harness.drainProxy();
    try testing.expectEqual(@as(usize, 1), harness.import_runner.calls);
    try testing.expectEqualStrings(fixture_node_path, harness.import_runner.last_node[0..harness.import_runner.last_node_len]);
    try testing.expectEqual(app_service.ProxySyncState.synced, harness.service.proxyState().sync_state);
}

test "an unresolvable node binary refuses sync before the importer and names the missing interpreter" {
    const replies = [_]FakeExchange.Reply{.{ .response = .{ .status = 200, .body = status_v2 } }};
    const harness = try Harness.create(&replies);
    defer harness.destroy();
    try harness.addCodex();
    harness.attach();
    try harness.saveSettings();
    _ = harness.service.submit(.proxy_refresh_status);
    try harness.drainProxy();
    harness.node_resolver.auto_path = null;

    try testing.expectEqual(ui_model.CommandOutcome.failed, harness.service.submit(.proxy_sync_config));
    try testing.expectEqual(@as(usize, 0), harness.import_runner.calls);
    try testing.expectEqual(@as(usize, 1), harness.exchange.calls);
    try testing.expectEqual(app_service.ProxyAttemptResult.import_node_missing, harness.service.proxyState().last_attempt.?.result);
    try testing.expectEqual(app_service.ProxySyncState.failed, harness.service.proxyState().sync_state);
    try testing.expectEqual(app_service.ProxyReachability.reachable, harness.service.proxyState().reachability);
    try testing.expect(harness.service.proxyState().last_success != null);
}

test "an importer that cannot be spawned is reported as a missing interpreter, not a timeout" {
    const replies = [_]FakeExchange.Reply{.{ .response = .{ .status = 200, .body = status_v2 } }};
    const harness = try Harness.create(&replies);
    defer harness.destroy();
    try harness.addCodex();
    harness.attach();
    try harness.saveSettings();
    _ = harness.service.submit(.proxy_refresh_status);
    try harness.drainProxy();
    harness.import_runner.outcome = .spawn_failed;

    _ = harness.service.submit(.proxy_sync_config);
    try harness.drainProxy();
    try testing.expectEqual(@as(usize, 1), harness.exchange.calls);
    try testing.expectEqual(app_service.ProxyAttemptResult.import_node_missing, harness.service.proxyState().last_attempt.?.result);
    try testing.expectEqual(app_service.ProxySyncState.failed, harness.service.proxyState().sync_state);
    try testing.expectEqual(app_service.ProxyReachability.reachable, harness.service.proxyState().reachability);
}

test "saved proxy settings carry an optional explicit node binary" {
    const harness = try Harness.create(&.{});
    defer harness.destroy();
    harness.attach();
    try testing.expectEqual(ui_model.CommandOutcome.accepted_pending, harness.service.submit(.{ .save_proxy_settings = .{
        .base_url = "http://127.0.0.1:48787",
        .cli_path = cli_path,
        .config_path = config_path,
        .node_path = fixture_node_path,
    } }));
    try testing.expectEqualStrings(fixture_node_path, harness.service.proxyState().settings.node_path.?.slice());

    try testing.expectEqual(ui_model.CommandOutcome.rejected_not_allowed, harness.service.submit(.{ .save_proxy_settings = .{
        .base_url = "http://127.0.0.1:48787",
        .cli_path = cli_path,
        .config_path = config_path,
        .node_path = "node",
    } }));
    try testing.expectEqual(ui_model.CommandOutcome.accepted_pending, harness.service.submit(.{ .save_proxy_settings = .{
        .base_url = "http://127.0.0.1:48787",
        .cli_path = cli_path,
        .config_path = config_path,
        .node_path = "",
    } }));
    try testing.expect(harness.service.proxyState().settings.node_path == null);
}

test "import failure stops sync before reload and keeps the prior success" {
    const replies = [_]FakeExchange.Reply{.{ .response = .{ .status = 200, .body = status_v2 } }};
    const harness = try Harness.create(&replies);
    defer harness.destroy();
    try harness.addCodex();
    harness.attach();
    try harness.saveSettings();
    _ = harness.service.submit(.proxy_refresh_status);
    try harness.drainProxy();
    harness.import_runner.outcome = .nonzero_exit;

    _ = harness.service.submit(.proxy_sync_config);
    try harness.drainProxy();
    try testing.expectEqual(@as(usize, 1), harness.exchange.calls);
    try testing.expectEqual(app_service.ProxySyncState.failed, harness.service.proxyState().sync_state);
    try testing.expect(harness.service.proxyState().last_success != null);
}

test "timeout marks the current run unreachable without erasing last success" {
    const replies = [_]FakeExchange.Reply{
        .{ .response = .{ .status = 200, .body = status_v2 } },
        .{ .failure = error.Timeout },
    };
    const harness = try Harness.create(&replies);
    defer harness.destroy();
    try harness.addCodex();
    harness.attach();
    try harness.saveSettings();
    _ = harness.service.submit(.proxy_refresh_status);
    try harness.drainProxy();
    _ = harness.service.submit(.proxy_refresh_status);
    try harness.drainProxy();
    try testing.expectEqual(app_service.ProxyReachability.@"unreachable", harness.service.proxyState().reachability);
    try testing.expect(harness.service.proxyState().last_success != null);
    try testing.expectEqual(app_service.ProxyAttemptResult.timeout, harness.service.proxyState().last_attempt.?.result);
}

test "proxy action failure never starts provider work or a local fallback" {
    const replies = [_]FakeExchange.Reply{
        .{ .response = .{ .status = 200, .body = status_v2 } },
        .{ .failure = error.Network },
    };
    const harness = try Harness.create(&replies);
    defer harness.destroy();
    try harness.addCodex();
    harness.attach();
    try harness.saveSettings();
    _ = harness.service.submit(.proxy_refresh_status);
    try harness.drainProxy();
    _ = harness.service.submit(.{ .proxy_switch_account = account_id });
    try harness.drainProxy();
    try testing.expectEqual(@as(usize, 0), harness.service.busyWorkerCount());
    try testing.expectEqual(@as(usize, 2), harness.exchange.calls);
    try testing.expectEqual(@as(usize, 0), harness.import_runner.calls);
    try testing.expectEqual(app_service.ProxyReachability.@"unreachable", harness.service.proxyState().reachability);
}

const BlockingExchange = struct {
    io: std.Io,
    started: std.atomic.Value(bool) = .init(false),
    canceled: std.atomic.Value(bool) = .init(false),
    event: std.Io.Event = .unset,

    const vtable: proxy.Exchange.VTable = .{ .perform = perform };

    fn exchange(self: *BlockingExchange) proxy.Exchange {
        return .{ .context = self, .vtable = &vtable };
    }

    fn perform(context: *anyopaque, _: proxy.Request, _: []u8) proxy.TransportError!proxy.ExchangeResult {
        const self: *BlockingExchange = @ptrCast(@alignCast(context));
        self.started.store(true, .release);
        self.event.wait(self.io) catch {
            self.canceled.store(true, .release);
            return error.Canceled;
        };
        return error.Network;
    }
};

test "service shutdown cancels and joins its one proxy worker" {
    const harness = try Harness.create(&.{});
    defer {
        harness.core.destroy();
        harness.credentials.deinit();
        testing.allocator.destroy(harness);
    }
    var blocking: BlockingExchange = .{ .io = testing.io };
    harness.attach();
    harness.service.live.?.proxy_exchange = blocking.exchange();
    try harness.saveSettings();
    _ = harness.service.submit(.proxy_refresh_status);
    var spins: usize = 0;
    while (!blocking.started.load(.acquire)) : (spins += 1) {
        if (spins > 4_000) return error.WorkerDidNotStart;
        testing.io.sleep(.fromMilliseconds(1), .awake) catch {};
    }
    harness.service.destroy();
    try testing.expect(blocking.canceled.load(.acquire));
}

test "managed failover automatically includes a new account after busy requests drain" {
    const busy = "{\"version\":2,\"config_path\":\"" ++ config_path ++ "\",\"active\":\"codex-1\",\"cursor\":\"codex-1\",\"in_flight\":1,\"accounts\":[{\"name\":\"codex-1\",\"label\":\"Fixture\",\"auth_file\":\"" ++ auth_file ++ "\",\"state\":\"READY\",\"cooldown_until\":null,\"reason\":null,\"token_expires_at\":null,\"in_flight\":1}]}";
    const updated = "{\"version\":2,\"config_path\":\"" ++ config_path ++ "\",\"active\":\"codex-1\",\"cursor\":\"codex-1\",\"in_flight\":0,\"accounts\":[{\"name\":\"codex-1\",\"label\":\"Fixture\",\"auth_file\":\"" ++ auth_file ++ "\",\"state\":\"READY\",\"cooldown_until\":null,\"reason\":null,\"token_expires_at\":null,\"in_flight\":0},{\"name\":\"codex-2\",\"label\":\"New\",\"auth_file\":\"" ++ app_root ++ "/accounts/new/codex/auth.json\",\"state\":\"READY\",\"cooldown_until\":null,\"reason\":null,\"token_expires_at\":null,\"in_flight\":0}]}";
    const harness = try Harness.create(&.{
        .{ .response = .{ .status = 200, .body = status_v2 } },
        .{ .response = .{ .status = 200, .body = busy } },
        .{ .response = .{ .status = 200, .body = status_v2 } },
        .{ .response = .{ .status = 200, .body = updated } },
    });
    defer harness.destroy();
    try harness.addCodex();
    harness.attach();
    try harness.saveSettings();
    _ = harness.service.submit(.proxy_refresh_status);
    try harness.drainProxy();
    harness.service.proxy_service.initialized = true;
    harness.service.proxy_service.discovery.routing.state = .on;
    _ = try harness.core.addAccount(.{ .id = "acct-new", .provider = .codex, .label = "New", .storage_key = "new", .created_at_unix_s = now });
    _ = try harness.core.registry.markConnected("acct-new", null);
    harness.service.pump(now + 3);
    try testing.expect(harness.service.proxyWorkerBusy());
    try harness.drainProxy();
    try testing.expectEqual(@as(usize, 0), harness.import_runner.calls);
    try testing.expectEqual(app_service.ProxySyncState.needed, harness.service.proxyState().sync_state);
    harness.service.pump(now + 6);
    try harness.drainProxy();
    try testing.expectEqual(@as(usize, 1), harness.import_runner.calls);
    try testing.expectEqual(app_service.ProxySyncState.synced, harness.service.proxyState().sync_state);
    try testing.expectEqual(@as(usize, 2), harness.service.proxyState().last_success.?.accountCount());
    try testing.expectEqual(@as(usize, 0), harness.service.activity.refreshes_started);
}

test "background failover checks keep status current without writing on every poll" {
    const reply: FakeExchange.Reply = .{ .response = .{ .status = 200, .body = status_v2 } };
    const harness = try Harness.create(&.{ reply, reply, reply, reply, reply });
    defer harness.destroy();
    try harness.addCodex();
    harness.attach();
    try harness.saveSettings();
    _ = harness.service.submit(.proxy_refresh_status);
    try harness.drainProxy();
    harness.service.proxy_service.initialized = true;
    harness.service.proxy_service.discovery.routing.state = .on;
    harness.service.pump(now + 3);
    try harness.drainProxy();
    harness.service.pump(now + 6);
    try harness.drainProxy();
    try testing.expectEqual(@as(i64, now + 6), harness.service.proxyState().last_success_at_unix_s.?);
    try testing.expectEqual(@as(usize, 1), harness.sink.countOf(.proxy_status));
    harness.service.pump(now + 31);
    try harness.drainProxy();
    try testing.expectEqual(@as(usize, 2), harness.sink.countOf(.proxy_status));
    _ = harness.service.submit(.proxy_refresh_status);
    try harness.drainProxy();
    try testing.expectEqual(@as(usize, 3), harness.sink.countOf(.proxy_status));
}
