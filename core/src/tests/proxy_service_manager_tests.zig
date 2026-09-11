const std = @import("std");
const manager = @import("proxy_service_manager");
const routing = manager.codex_routing;
const importer = manager.proxy_import;
const launcher = manager.proxy_launch;
const runtime_paths = manager.runtime_paths;
const ui_model = manager.ui_model;

const testing = std.testing;

const Action = enum {
    print_new,
    health,
    importer,
    ensure_parents,
    write_plist,
    bootstrap_new,
    bootout_new,
    write_receipt,
    remove_owned,
    routing_inspect,
    routing_enable,
    routing_disable,
};

const Trace = struct {
    items: [1024]Action = @splat(.health),
    len: usize = 0,
    fn push(self: *Trace, action: Action) void {
        self.items[self.len] = action;
        self.len += 1;
    }
    fn slice(self: *const Trace) []const Action {
        return self.items[0..self.len];
    }
    fn count(self: *const Trace, action: Action) usize {
        var total: usize = 0;
        for (self.slice()) |item| if (item == action) {
            total += 1;
        };
        return total;
    }
    fn first(self: *const Trace, action: Action) ?usize {
        for (self.slice(), 0..) |item, index| if (item == action) return index;
        return null;
    }
};

const FakeLaunch = struct {
    trace: *Trace,
    new_loaded: bool = false,
    new_arguments_match: bool = true,

    const vtable: launcher.Runner.VTable = .{ .run = run };
    fn runner(self: *FakeLaunch) launcher.Runner {
        return .{ .context = self, .vtable = &vtable };
    }
    fn run(context: *anyopaque, command: launcher.Command) launcher.Result {
        const self: *FakeLaunch = @ptrCast(@alignCast(context));
        return switch (command) {
            .print => |request| blk: {
                _ = request;
                self.trace.push(.print_new);
                if (!self.new_loaded) break :blk .{ .status = .not_loaded };
                break :blk .{ .status = if (!self.new_arguments_match) .loaded_arguments_mismatch else .loaded };
            },
            .bootstrap => blk: {
                self.trace.push(.bootstrap_new);
                self.new_loaded = true;
                break :blk .{ .status = .success };
            },
            .bootout => blk: {
                self.trace.push(.bootout_new);
                self.new_loaded = false;
                break :blk .{ .status = .success };
            },
            .kickstart => .{ .status = .success },
        };
    }
};

const FakeArtifacts = struct {
    trace: *Trace,
    value: manager.ArtifactInspection = .{ .bundle_matches = true },
    ensure_ok: bool = true,
    receipt_ok: bool = true,

    const vtable: manager.ArtifactStore.VTable = .{
        .inspect = inspect,
        .ensure_parents = ensureParents,
        .write_plist = writePlist,
        .write_receipt = writeReceipt,
        .remove_owned = removeOwned,
    };
    fn store(self: *FakeArtifacts) manager.ArtifactStore {
        return .{ .context = self, .vtable = &vtable };
    }
    fn inspect(context: *anyopaque, _: *const manager.Paths, _: *const manager.BundleIdentity, _: []const u8, _: []const u8) manager.ArtifactInspection {
        return @as(*FakeArtifacts, @ptrCast(@alignCast(context))).value;
    }
    fn ensureParents(context: *anyopaque, _: *const manager.Paths) bool {
        const self: *FakeArtifacts = @ptrCast(@alignCast(context));
        self.trace.push(.ensure_parents);
        return self.ensure_ok;
    }
    fn writePlist(context: *anyopaque, _: *const manager.Paths, _: []const u8) bool {
        const self: *FakeArtifacts = @ptrCast(@alignCast(context));
        self.trace.push(.write_plist);
        self.value.plist_exists = true;
        self.value.plist_matches = true;
        return true;
    }
    fn writeReceipt(context: *anyopaque, _: *const manager.Paths, _: []const u8) bool {
        const self: *FakeArtifacts = @ptrCast(@alignCast(context));
        self.trace.push(.write_receipt);
        if (!self.receipt_ok) return false;
        self.value.receipt_exists = true;
        self.value.receipt_matches = true;
        return true;
    }
    fn removeOwned(context: *anyopaque, _: *const manager.Paths) bool {
        const self: *FakeArtifacts = @ptrCast(@alignCast(context));
        self.trace.push(.remove_owned);
        self.value = .{ .bundle_matches = true };
        return true;
    }
};

const FakeRouting = struct {
    trace: *Trace,
    state: ui_model.CodexRoutingState = .off,
    fingerprint: routing.Fingerprint = @splat(7),

    const vtable: routing.Editor.VTable = .{ .inspect = inspect, .enable = enable, .disable = disable };
    fn editor(self: *FakeRouting) routing.Editor {
        return .{ .context = self, .vtable = &vtable };
    }
    fn inspect(context: *anyopaque, _: []const u8) routing.Inspection {
        const self: *FakeRouting = @ptrCast(@alignCast(context));
        self.trace.push(.routing_inspect);
        return .{ .state = self.state, .fingerprint = self.fingerprint, .readable = true, .exists = true };
    }
    fn enable(context: *anyopaque, _: []const u8, replace: bool, expected: ?routing.Fingerprint) routing.Mutation {
        const self: *FakeRouting = @ptrCast(@alignCast(context));
        self.trace.push(.routing_enable);
        if (self.state == .conflicting and (!replace or expected == null or !std.mem.eql(u8, &expected.?, &self.fingerprint))) return .{ .status = .refused, .state = self.state };
        self.state = .on;
        return .{ .status = .success, .state = .on, .fingerprint = self.fingerprint };
    }
    fn disable(context: *anyopaque, _: []const u8) routing.Mutation {
        const self: *FakeRouting = @ptrCast(@alignCast(context));
        self.trace.push(.routing_disable);
        if (self.state == .conflicting) return .{ .status = .refused, .state = .conflicting };
        self.state = .off;
        return .{ .status = .success, .state = .off, .fingerprint = self.fingerprint };
    }
};

const FakeHealth = struct {
    trace: *Trace,
    values: [32]manager.Health = @splat(.{ .state = .healthy, .in_flight = 0 }),
    len: usize = 1,
    index: usize = 0,

    const vtable: manager.HealthProbe.VTable = .{ .read = read };
    fn probe(self: *FakeHealth) manager.HealthProbe {
        return .{ .context = self, .vtable = &vtable };
    }
    fn read(context: *anyopaque, _: []const u8, _: []const u8) manager.Health {
        const self: *FakeHealth = @ptrCast(@alignCast(context));
        self.trace.push(.health);
        const at = @min(self.index, self.len - 1);
        const value = self.values[at];
        self.index += 1;
        return value;
    }
    fn set(self: *FakeHealth, values: []const manager.Health) void {
        @memcpy(self.values[0..values.len], values);
        self.len = values.len;
        self.index = 0;
    }
};

const FakeImporter = struct {
    trace: *Trace,
    outcome: importer.Outcome = .success,
    const vtable: importer.Runner.VTable = .{ .run = run };
    fn runner(self: *FakeImporter) importer.Runner {
        return .{ .context = self, .vtable = &vtable };
    }
    fn run(context: *anyopaque, request: importer.Request) importer.Outcome {
        const self: *FakeImporter = @ptrCast(@alignCast(context));
        self.trace.push(.importer);
        testing.expectEqualStrings("/private/tmp/p3-home/CodexMulti.app/Contents/Helpers/node", request.node_path) catch return .invalid_configuration;
        return self.outcome;
    }
};

const Harness = struct {
    trace: Trace = .{},
    launch: FakeLaunch = undefined,
    artifacts: FakeArtifacts = undefined,
    routing_editor: FakeRouting = undefined,
    health: FakeHealth = undefined,
    importer_runner: FakeImporter = undefined,
    paths: manager.Paths,
    identity: manager.BundleIdentity,
    controller: manager.Controller = .{},

    fn init() !Harness {
        const home = "/private/tmp/p3-home";
        const app = home ++ "/CodexMulti.app";
        const data = home ++ "/Library/Application Support/" ++ runtime_paths.app_data_directory_name;
        var self: Harness = .{
            .paths = try .init(home, app, data, home ++ "/.config/codexmulti/proxy.json", 501),
            .identity = try .init("0123456789abcdef0123456789abcdef01234567", "aaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaa", "v22.15.0", "bbbbbbbbbbbbbbbbbbbbbbbbbbbbbbbbbbbbbbbbbbbbbbbbbbbbbbbbbbbbbbbb", "cccccccccccccccccccccccccccccccccccccccccccccccccccccccccccccccc"),
        };
        self.rebind();
        return self;
    }
    fn rebind(self: *Harness) void {
        self.launch = .{ .trace = &self.trace };
        self.artifacts = .{ .trace = &self.trace };
        self.routing_editor = .{ .trace = &self.trace };
        self.health = .{ .trace = &self.trace };
        self.importer_runner = .{ .trace = &self.trace };
    }
    fn live(self: *Harness) manager.Live {
        return .{
            .io = testing.io,
            .allocator = testing.allocator,
            .paths = self.paths,
            .identity = self.identity,
            .launch = self.launch.runner(),
            .artifacts = self.artifacts.store(),
            .routing = self.routing_editor.editor(),
            .health = self.health.probe(),
            .importer = self.importer_runner.runner(),
        };
    }
    fn refresh(self: *Harness) void {
        self.controller.refresh(self.live());
    }
    fn drain(self: *Harness) !void {
        var spins: usize = 0;
        while (self.controller.busy()) {
            self.controller.drain(testing.io);
            spins += 1;
            if (spins > 10_000) return error.WorkerDidNotFinish;
            testing.io.sleep(.fromMilliseconds(1), .awake) catch {};
        }
    }
};

test "canonical plist has exactly four ProgramArguments and stable digest" {
    var harness = try Harness.init();
    harness.rebind();
    var bytes: [manager.max_plist_bytes]u8 = undefined;
    const plist = try manager.renderPlist(&bytes, &harness.paths, &harness.identity);
    try testing.expectEqual(@as(usize, 1), std.mem.count(u8, plist, "<key>ProgramArguments</key>"));
    try testing.expectEqual(@as(usize, 4), std.mem.count(u8, plist, "<string>") - 5);
    const expected_arguments =
        "<key>ProgramArguments</key>\n<array>\n" ++
        "<string>/private/tmp/p3-home/CodexMulti.app/Contents/Helpers/node</string>\n" ++
        "<string>/private/tmp/p3-home/CodexMulti.app/Contents/Resources/proxy/src/server.mjs</string>\n" ++
        "<string>--config</string>\n" ++
        "<string>/private/tmp/p3-home/.config/codexmulti/proxy.json</string>\n" ++
        "</array>";
    try testing.expect(std.mem.indexOf(u8, plist, expected_arguments) != null);
    var digest_a: [64]u8 = undefined;
    var digest_b: [64]u8 = undefined;
    manager.digestHex(plist, &digest_a);
    manager.digestHex(plist, &digest_b);
    try testing.expectEqualSlices(u8, &digest_a, &digest_b);
}

test "state precedence covers not installed stale running and unreachable" {
    var harness = try Harness.init();
    harness.rebind();
    harness.launch.new_loaded = false;
    harness.artifacts.value = .{ .bundle_matches = true };
    harness.refresh();
    try testing.expectEqual(ui_model.ProxyServiceState.not_installed, harness.controller.discovery.state);
    var fact = harness.controller.fact(true, &harness.paths);
    try testing.expect(fact.can_install and !fact.can_repair and !fact.can_stop);
    harness.artifacts.value = .{ .plist_exists = true, .plist_matches = true, .bundle_matches = false };
    harness.refresh();
    try testing.expectEqual(ui_model.ProxyServiceState.installed_stale, harness.controller.discovery.state);
    fact = harness.controller.fact(true, &harness.paths);
    try testing.expect(!fact.can_install and fact.can_repair and !fact.can_stop);
    harness.artifacts.value = .{ .plist_exists = true, .receipt_exists = true, .plist_matches = true, .receipt_matches = true, .bundle_matches = true };
    harness.launch.new_loaded = true;
    harness.health.set(&.{.{ .state = .healthy }});
    harness.refresh();
    try testing.expectEqual(ui_model.ProxyServiceState.running, harness.controller.discovery.state);
    fact = harness.controller.fact(true, &harness.paths);
    try testing.expect(!fact.can_install and !fact.can_repair and fact.can_stop);
    harness.health.set(&.{.{ .state = .@"unreachable" }});
    harness.refresh();
    try testing.expectEqual(ui_model.ProxyServiceState.@"unreachable", harness.controller.discovery.state);
    fact = harness.controller.fact(true, &harness.paths);
    try testing.expect(!fact.can_install and !fact.can_repair and !fact.can_stop);
}

test "install is importer first and no eligible account touches nothing" {
    var harness = try Harness.init();
    harness.rebind();
    harness.refresh();
    try testing.expectEqual(ui_model.CommandOutcome.rejected_not_allowed, harness.controller.submit(.install, false, false, harness.live()));
    try testing.expectEqual(@as(usize, 0), harness.trace.count(.importer));
    try testing.expectEqual(@as(usize, 0), harness.trace.count(.write_plist));

    harness.trace.len = 0;
    try testing.expectEqual(ui_model.CommandOutcome.accepted_pending, harness.controller.submit(.install, false, true, harness.live()));
    try harness.drain();
    try testing.expect(harness.trace.first(.importer).? < harness.trace.first(.ensure_parents).?);
    try testing.expect(harness.trace.first(.ensure_parents).? < harness.trace.first(.write_plist).?);
    try testing.expect(harness.trace.first(.write_plist).? < harness.trace.first(.bootstrap_new).?);
    try testing.expect(harness.trace.first(.bootstrap_new).? < harness.trace.first(.write_receipt).?);
    try testing.expectEqual(ui_model.ProxyServiceState.running, harness.controller.discovery.state);
}

test "loaded repair admits positive count and never bootouts before a fresh zero" {
    var harness = try Harness.init();
    harness.rebind();
    harness.launch.new_loaded = true;
    harness.artifacts.value = .{ .plist_exists = true, .receipt_exists = true, .plist_matches = false, .receipt_matches = false, .bundle_matches = true };
    harness.health.set(&.{ .{ .state = .healthy, .in_flight = 3 }, .{ .state = .healthy, .in_flight = 2 }, .{ .state = .healthy, .in_flight = 0 }, .{ .state = .healthy, .in_flight = 0 } });
    harness.refresh();
    try testing.expect(harness.controller.fact(true, &harness.paths).can_repair);
    harness.trace.len = 0;
    harness.health.index = 0;
    try testing.expectEqual(ui_model.CommandOutcome.accepted_pending, harness.controller.submit(.repair, false, true, harness.live()));
    try harness.drain();
    const bootout = harness.trace.first(.bootout_new).?;
    try testing.expect(harness.trace.count(.health) >= 4);
    var health_before: usize = 0;
    for (harness.trace.slice()[0..bootout]) |item| if (item == .health) {
        health_before += 1;
    };
    try testing.expect(health_before >= 4);
    try testing.expect(bootout < harness.trace.first(.write_plist).?);
    try testing.expect(harness.trace.first(.write_plist).? < harness.trace.first(.bootstrap_new).?);
}

test "loaded unreachable fails closed while definitely unloaded repair skips health and bootout" {
    var harness = try Harness.init();
    harness.rebind();
    harness.launch.new_loaded = true;
    harness.artifacts.value = .{ .plist_exists = true, .plist_matches = false, .bundle_matches = true };
    harness.health.set(&.{.{ .state = .@"unreachable" }});
    harness.refresh();
    try testing.expect(!harness.controller.fact(true, &harness.paths).can_repair);
    try testing.expectEqual(ui_model.CommandOutcome.rejected_not_allowed, harness.controller.submit(.repair, false, true, harness.live()));
    try testing.expectEqual(@as(usize, 0), harness.trace.count(.bootout_new));

    harness.launch.new_loaded = false;
    harness.refresh();
    harness.trace.len = 0;
    harness.health.set(&.{.{ .state = .healthy }});
    try testing.expectEqual(ui_model.CommandOutcome.accepted_pending, harness.controller.submit(.repair, false, true, harness.live()));
    try harness.drain();
    try testing.expectEqual(@as(usize, 0), harness.trace.count(.bootout_new));
    try testing.expect(harness.trace.first(.write_plist).? < harness.trace.first(.bootstrap_new).?);
}

test "stop disables routing before positive drain and bootout" {
    var harness = try Harness.init();
    harness.rebind();
    harness.launch.new_loaded = true;
    harness.artifacts.value = .{ .plist_exists = true, .receipt_exists = true, .plist_matches = true, .receipt_matches = true, .bundle_matches = true };
    harness.routing_editor.state = .on;
    harness.health.set(&.{ .{ .state = .healthy, .in_flight = 2 }, .{ .state = .healthy, .in_flight = 1 }, .{ .state = .healthy }, .{ .state = .healthy } });
    harness.refresh();
    harness.trace.len = 0;
    harness.health.index = 0;
    try testing.expectEqual(ui_model.CommandOutcome.accepted_pending, harness.controller.submit(.stop, false, true, harness.live()));
    try harness.drain();
    const disabled_at = harness.trace.first(.routing_disable).?;
    var drained_health_after_disable = false;
    for (harness.trace.slice()[disabled_at + 1 .. harness.trace.first(.bootout_new).?]) |item| {
        if (item == .health) drained_health_after_disable = true;
    }
    try testing.expect(drained_health_after_disable);
    try testing.expect(harness.trace.first(.bootout_new).? < harness.trace.first(.remove_owned).?);
    try testing.expectEqual(ui_model.ProxyServiceState.not_installed, harness.controller.discovery.state);
}

test "C9 whole-proxy switch refuses an in-flight request without any mutation" {
    var harness = try Harness.init();
    harness.rebind();
    harness.launch.new_loaded = true;
    harness.artifacts.value = .{ .plist_exists = true, .receipt_exists = true, .plist_matches = true, .receipt_matches = true, .bundle_matches = true };
    harness.routing_editor.state = .on;
    harness.health.set(&.{.{ .state = .healthy, .in_flight = 4 }});
    harness.refresh();
    harness.trace.len = 0;

    try testing.expectEqual(ui_model.CommandOutcome.rejected_busy, harness.controller.submit(.set_enabled_off, false, true, harness.live()));
    try testing.expectEqual(@as(usize, 0), harness.trace.count(.routing_disable));
    try testing.expectEqual(@as(usize, 0), harness.trace.count(.bootout_new));
    const fact = harness.controller.fact(true, &harness.paths);
    try testing.expect(fact.enabled);
    try testing.expect(std.mem.indexOf(u8, fact.enabled_detail_text, "4") != null);
    try testing.expect(std.mem.indexOf(u8, fact.enabled_detail_text, "will apply when they finish") != null);

    harness.controller.observeProxyHealth(.{ .state = .healthy, .in_flight = 0 });
    const drained = harness.controller.fact(true, &harness.paths);
    try testing.expectEqualStrings("Codex routes through the running failover proxy.", drained.enabled_detail_text);
}

test "C9 whole-proxy switch on installs starts and enables routing as one job" {
    var harness = try Harness.init();
    harness.rebind();
    harness.refresh();
    harness.trace.len = 0;

    try testing.expectEqual(ui_model.CommandOutcome.accepted_pending, harness.controller.submit(.set_enabled_on, false, true, harness.live()));
    try harness.drain();
    try testing.expect(harness.trace.first(.importer).? < harness.trace.first(.bootstrap_new).?);
    try testing.expect(harness.trace.first(.bootstrap_new).? < harness.trace.first(.routing_enable).?);
    const fact = harness.controller.fact(true, &harness.paths);
    try testing.expect(fact.enabled);
    try testing.expectEqual(ui_model.ProxyServiceState.running, fact.state);
    try testing.expectEqual(ui_model.CodexRoutingState.on, fact.routing_state);
}

test "C9 whole-proxy switch off disables routing and stops a drained service" {
    var harness = try Harness.init();
    harness.rebind();
    harness.launch.new_loaded = true;
    harness.artifacts.value = .{ .plist_exists = true, .receipt_exists = true, .plist_matches = true, .receipt_matches = true, .bundle_matches = true };
    harness.routing_editor.state = .on;
    harness.health.set(&.{.{ .state = .healthy }});
    harness.refresh();
    harness.trace.len = 0;
    harness.health.index = 0;

    try testing.expectEqual(ui_model.CommandOutcome.accepted_pending, harness.controller.submit(.set_enabled_off, false, true, harness.live()));
    try harness.drain();
    try testing.expect(harness.trace.first(.routing_disable).? < harness.trace.first(.bootout_new).?);
    const fact = harness.controller.fact(true, &harness.paths);
    try testing.expect(!fact.enabled);
    try testing.expectEqual(ui_model.ProxyServiceState.not_installed, fact.state);
    try testing.expectEqual(ui_model.CodexRoutingState.off, fact.routing_state);
}

test "C9 whole-proxy switch off restores routing when a request races the final gate" {
    var harness = try Harness.init();
    harness.rebind();
    harness.launch.new_loaded = true;
    harness.artifacts.value = .{ .plist_exists = true, .receipt_exists = true, .plist_matches = true, .receipt_matches = true, .bundle_matches = true };
    harness.routing_editor.state = .on;
    harness.health.set(&.{
        .{ .state = .healthy },
        .{ .state = .healthy },
        .{ .state = .healthy, .in_flight = 1 },
    });
    harness.refresh();
    harness.trace.len = 0;

    try testing.expectEqual(ui_model.CommandOutcome.accepted_pending, harness.controller.submit(.set_enabled_off, false, true, harness.live()));
    try harness.drain();
    try testing.expectEqual(@as(usize, 1), harness.trace.count(.routing_disable));
    try testing.expectEqual(@as(usize, 1), harness.trace.count(.routing_enable));
    try testing.expectEqual(@as(usize, 0), harness.trace.count(.bootout_new));
    try testing.expect(!harness.controller.worker.result.ok);
    try testing.expectEqual(ui_model.CodexRoutingState.on, harness.controller.discovery.routing.state);
}

test "conflicting routing replacement requires the confirmed fingerprint" {
    var harness = try Harness.init();
    harness.rebind();
    harness.launch.new_loaded = true;
    harness.artifacts.value = .{ .plist_exists = true, .receipt_exists = true, .plist_matches = true, .receipt_matches = true, .bundle_matches = true };
    harness.routing_editor.state = .conflicting;
    harness.health.set(&.{.{ .state = .healthy }});
    harness.refresh();
    try testing.expectEqual(ui_model.CommandOutcome.rejected_not_allowed, harness.controller.submit(.enable_routing, false, true, harness.live()));
    try testing.expectEqual(ui_model.CommandOutcome.accepted_pending, harness.controller.submit(.enable_routing, true, true, harness.live()));
    try harness.drain();
    try testing.expectEqual(.on, harness.controller.discovery.routing.state);
}

test "reachable loaded repair remains actionable at positive count and projects starting while waiting" {
    var harness = try Harness.init();
    harness.rebind();
    harness.launch.new_loaded = true;
    harness.artifacts.value = .{ .plist_exists = true, .receipt_exists = true, .plist_matches = false, .receipt_matches = false, .bundle_matches = true };
    harness.health.set(&.{.{ .state = .healthy, .in_flight = 4 }});
    harness.refresh();
    harness.trace.len = 0;
    harness.health.index = 0;
    try testing.expect(harness.controller.fact(true, &harness.paths).can_repair);
    try testing.expectEqual(ui_model.CommandOutcome.accepted_pending, harness.controller.submit(.repair, false, true, harness.live()));
    const starting = harness.controller.fact(true, &harness.paths);
    try testing.expectEqual(ui_model.ProxyServiceState.starting, starting.state);
    try testing.expect(!starting.can_install and !starting.can_repair and !starting.can_stop);
    testing.io.sleep(.fromMilliseconds(5), .awake) catch {};
    try testing.expectEqual(@as(usize, 0), harness.trace.count(.bootout_new));
    harness.controller.shutdown(testing.io);
    try testing.expect(!harness.controller.busy());
}

test "definitively unloaded current artifacts classify unreachable and repair without status drain or bootout" {
    var harness = try Harness.init();
    harness.rebind();
    harness.artifacts.value = .{ .plist_exists = true, .receipt_exists = true, .plist_matches = true, .receipt_matches = true, .bundle_matches = true };
    harness.launch.new_loaded = false;
    harness.refresh();
    try testing.expectEqual(ui_model.ProxyServiceState.@"unreachable", harness.controller.discovery.state);
    try testing.expect(harness.controller.fact(true, &harness.paths).can_repair);
    harness.trace.len = 0;
    try testing.expectEqual(ui_model.CommandOutcome.accepted_pending, harness.controller.submit(.repair, false, true, harness.live()));
    try harness.drain();
    try testing.expectEqual(@as(usize, 0), harness.trace.count(.bootout_new));
    try testing.expect(harness.trace.first(.write_plist).? < harness.trace.first(.bootstrap_new).?);
}

test "crash before receipt and same-path proxy tree or signed Node drift project installed stale" {
    var harness = try Harness.init();
    harness.rebind();
    harness.refresh();
    harness.artifacts.receipt_ok = false;
    try testing.expectEqual(ui_model.CommandOutcome.accepted_pending, harness.controller.submit(.install, false, true, harness.live()));
    try harness.drain();
    try testing.expect(harness.artifacts.value.plist_exists);
    try testing.expect(!harness.artifacts.value.receipt_exists);
    try testing.expectEqual(ui_model.ProxyServiceState.installed_stale, harness.controller.discovery.state);

    harness.artifacts.value.receipt_exists = true;
    harness.artifacts.value.receipt_matches = true;
    harness.artifacts.value.bundle_matches = false;
    harness.refresh();
    try testing.expectEqual(ui_model.ProxyServiceState.installed_stale, harness.controller.discovery.state);
}

fn prepareFilesystemHarness(name: []const u8) !struct {
    root: [:0]u8,
    paths: manager.Paths,
    backing: manager.FileArtifacts,
} {
    const cwd = std.Io.Dir.cwd();
    const relative = try std.fmt.allocPrint(testing.allocator, ".zig-cache/{s}", .{name});
    defer testing.allocator.free(relative);
    cwd.deleteTree(testing.io, relative) catch {};
    try cwd.createDirPath(testing.io, relative);
    try cwd.setFilePermissions(testing.io, relative, std.Io.File.Permissions.fromMode(0o700), .{});
    const root = try cwd.realPathFileAlloc(testing.io, relative, testing.allocator);
    const app = try std.fmt.allocPrint(testing.allocator, "{s}/CodexMulti.app", .{root});
    defer testing.allocator.free(app);
    const data = try std.fmt.allocPrint(testing.allocator, "{s}/Library/Application Support/{s}", .{ root, runtime_paths.app_data_directory_name });
    defer testing.allocator.free(data);
    const config = try std.fmt.allocPrint(testing.allocator, "{s}/.config/codexmulti/proxy.json", .{root});
    defer testing.allocator.free(config);
    return .{
        .root = root,
        .paths = try .init(root, app, data, config, 501),
        .backing = manager.FileArtifacts.init(testing.io, testing.allocator),
    };
}

test "filesystem adapter creates all missing parents private and rejects symlink or unsafe parent cases" {
    var fixture = try prepareFilesystemHarness("p3-service-parents");
    defer testing.allocator.free(fixture.root);
    defer std.Io.Dir.cwd().deleteTree(testing.io, fixture.root) catch {};
    const store = fixture.backing.store();
    try testing.expect(store.ensureParents(&fixture.paths));
    for ([_][]const u8{ fixture.paths.plist_parent.slice(), fixture.paths.receipt_parent.slice(), fixture.paths.log_parent.slice() }) |path| {
        const stat = try std.Io.Dir.cwd().statFile(testing.io, path, .{ .follow_symlinks = false });
        try testing.expectEqual(std.Io.File.Kind.directory, stat.kind);
        try testing.expectEqual(@as(std.posix.mode_t, 0), stat.permissions.toMode() & 0o077);
    }

    const cases = [_]enum { plist, receipt, log }{ .plist, .receipt, .log };
    for (cases, 0..) |case, index| {
        var name_buffer: [64]u8 = undefined;
        const name = try std.fmt.bufPrint(&name_buffer, "p3-service-parent-link-{d}", .{index});
        var linked = try prepareFilesystemHarness(name);
        defer testing.allocator.free(linked.root);
        defer std.Io.Dir.cwd().deleteTree(testing.io, linked.root) catch {};
        try std.Io.Dir.cwd().createDirPath(testing.io, linked.paths.plist_parent.slice());
        try std.Io.Dir.cwd().createDirPath(testing.io, linked.paths.receipt_parent.slice());
        try std.Io.Dir.cwd().createDirPath(testing.io, linked.paths.log_parent.slice());
        const target = switch (case) {
            .plist => linked.paths.plist_parent.slice(),
            .receipt => linked.paths.receipt_parent.slice(),
            .log => linked.paths.log_parent.slice(),
        };
        try std.Io.Dir.cwd().deleteDir(testing.io, target);
        const safe = try std.fmt.allocPrint(testing.allocator, "{s}/safe-{d}", .{ linked.root, index });
        defer testing.allocator.free(safe);
        try std.Io.Dir.cwd().createDir(testing.io, safe, std.Io.File.Permissions.fromMode(0o700));
        try std.Io.Dir.cwd().symLink(testing.io, safe, target, .{});
        try testing.expect(!linked.backing.store().ensureParents(&linked.paths));
    }

    var unsafe = try prepareFilesystemHarness("p3-service-parent-mode");
    defer testing.allocator.free(unsafe.root);
    defer std.Io.Dir.cwd().deleteTree(testing.io, unsafe.root) catch {};
    try std.Io.Dir.cwd().createDirPath(testing.io, unsafe.paths.plist_parent.slice());
    try std.Io.Dir.cwd().setFilePermissions(testing.io, unsafe.paths.plist_parent.slice(), std.Io.File.Permissions.fromMode(0o777), .{});
    try testing.expect(!unsafe.backing.store().ensureParents(&unsafe.paths));
}

test "source contains no kickstart lifecycle path and public artifacts contain no secret-shaped text" {
    const source = try std.Io.Dir.cwd().readFileAlloc(testing.io, "src/proxy_service_manager.zig", testing.allocator, .limited(1024 * 1024));
    defer testing.allocator.free(source);
    try testing.expect(std.mem.indexOf(u8, source, "kick" ++ "start") == null);
    var harness = try Harness.init();
    harness.rebind();
    var plist_buffer: [manager.max_plist_bytes]u8 = undefined;
    const plist = try manager.renderPlist(&plist_buffer, &harness.paths, &harness.identity);
    var digest: [64]u8 = undefined;
    manager.digestHex(plist, &digest);
    var receipt_buffer: [manager.max_receipt_bytes]u8 = undefined;
    const receipt = try manager.renderReceipt(&receipt_buffer, &harness.paths, &harness.identity, &digest, 1);
    var parsed = try std.json.parseFromSlice(manager.Receipt, testing.allocator, receipt, .{ .allocate = .alloc_always });
    defer parsed.deinit();
    try testing.expectEqual(manager.receipt_schema, parsed.value.schema);
    try testing.expectEqualStrings(harness.paths.app_path.slice(), parsed.value.canonical_app_path);
    try testing.expectEqualStrings(harness.identity.proxy_commit.slice(), parsed.value.proxy_commit);
    try testing.expectEqualStrings(harness.identity.proxy_tree_sha256.slice(), parsed.value.proxy_tree_sha256);
    try testing.expectEqualStrings(harness.identity.node_version.slice(), parsed.value.node_version);
    try testing.expectEqualStrings(harness.identity.node_sha256.slice(), parsed.value.node_sha256);
    try testing.expectEqualStrings(harness.identity.signed_node_sha256.slice(), parsed.value.signed_node_sha256);
    try testing.expectEqualStrings(&digest, parsed.value.plist_sha256);
    for ([_][]const u8{ "access_token", "refresh_token", "authorization", "bearer ", "auth.json" }) |needle| {
        try testing.expect(std.mem.indexOf(u8, plist, needle) == null);
        try testing.expect(std.mem.indexOf(u8, receipt, needle) == null);
    }
}
