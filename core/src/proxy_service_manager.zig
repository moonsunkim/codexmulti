const std = @import("std");
const account_registry = @import("account_registry.zig");
pub const codex_routing = @import("codex_routing_editor.zig");
const proxy_control = @import("proxy_control_client.zig");
pub const proxy_import = @import("proxy_import_runner.zig");
pub const proxy_launch = @import("proxy_launch_runner.zig");
pub const runtime_paths = @import("runtime_paths.zig");
pub const ui_model = @import("ui_model.zig");

pub const new_label = "dev.codexmulti.app.proxy";
pub const default_control_base_url = "http://127.0.0.1:8787";
pub const receipt_schema: u16 = 1;
pub const max_plist_bytes: usize = 16 * 1024;
pub const max_receipt_bytes: usize = 4 * 1024;
pub const drain_poll_limit: usize = 300;
pub const drain_poll_ms: u32 = 100;

fn Text(comptime capacity: usize) type {
    return struct {
        bytes: [capacity]u8 = @splat(0),
        len: u16 = 0,

        const Self = @This();

        pub fn init(value: []const u8) !Self {
            if (value.len == 0 or value.len > capacity) return error.InvalidText;
            var out: Self = .{};
            @memcpy(out.bytes[0..value.len], value);
            out.len = @intCast(value.len);
            return out;
        }

        pub fn slice(self: *const Self) []const u8 {
            return self.bytes[0..self.len];
        }

        pub fn eql(self: *const Self, value: []const u8) bool {
            return std.mem.eql(u8, self.slice(), value);
        }
    };
}

pub const BundleIdentity = struct {
    proxy_commit: Text(40),
    proxy_tree_sha256: Text(64),
    node_version: Text(32),
    node_sha256: Text(64),
    signed_node_sha256: Text(64),

    pub fn init(
        proxy_commit: []const u8,
        proxy_tree_sha256: []const u8,
        node_version: []const u8,
        node_sha256: []const u8,
        signed_node_sha256: []const u8,
    ) !BundleIdentity {
        if (!lowerHex(proxy_commit, 40) or !lowerHex(proxy_tree_sha256, 64) or
            !lowerHex(node_sha256, 64) or !lowerHex(signed_node_sha256, 64) or
            node_version.len < 2 or node_version[0] != 'v') return error.InvalidIdentity;
        return .{
            .proxy_commit = try .init(proxy_commit),
            .proxy_tree_sha256 = try .init(proxy_tree_sha256),
            .node_version = try .init(node_version),
            .node_sha256 = try .init(node_sha256),
            .signed_node_sha256 = try .init(signed_node_sha256),
        };
    }
};

fn lowerHex(value: []const u8, expected: usize) bool {
    if (value.len != expected) return false;
    for (value) |byte| switch (byte) {
        '0'...'9', 'a'...'f' => {},
        else => return false,
    };
    return true;
}

pub const Paths = struct {
    home: runtime_paths.Path,
    app_path: runtime_paths.Path,
    app_data_root: runtime_paths.Path,
    node_path: runtime_paths.Path,
    cli_path: runtime_paths.Path,
    server_path: runtime_paths.Path,
    proxy_working_dir: runtime_paths.Path,
    config_path: runtime_paths.Path,
    routing_config_path: runtime_paths.Path,
    plist_parent: runtime_paths.Path,
    plist_path: runtime_paths.Path,
    receipt_parent: runtime_paths.Path,
    receipt_path: runtime_paths.Path,
    log_parent: runtime_paths.Path,
    stdout_path: runtime_paths.Path,
    stderr_path: runtime_paths.Path,
    uid: u32,

    pub fn init(home: []const u8, app_path: []const u8, app_data_root: []const u8, config_path: []const u8, uid: u32) !Paths {
        const home_path = try runtime_paths.Path.init(home);
        const app = try runtime_paths.Path.init(app_path);
        const data = try runtime_paths.Path.init(app_data_root);

        var node = app;
        try appendMany(&node, &.{ "Contents", "Helpers", "node" });
        var work = app;
        try appendMany(&work, &.{ "Contents", "Resources", "proxy" });
        var cli = work;
        try appendMany(&cli, &.{ "bin", "codexmulti-proxy" });
        var server = work;
        try appendMany(&server, &.{ "src", "server.mjs" });

        var routing = home_path;
        try appendMany(&routing, &.{ ".codex", "config.toml" });
        var plist_parent = home_path;
        try appendMany(&plist_parent, &.{ "Library", "LaunchAgents" });
        var plist = plist_parent;
        try plist.appendComponent(new_label ++ ".plist");
        var receipt = data;
        try receipt.appendComponent("proxy-service.json");
        var logs = home_path;
        try appendMany(&logs, &.{ "Library", "Logs", "CodexMulti" });
        var stdout_path = logs;
        try stdout_path.appendComponent("proxy.log");
        var stderr_path = logs;
        try stderr_path.appendComponent("proxy.error.log");

        return .{
            .home = home_path,
            .app_path = app,
            .app_data_root = data,
            .node_path = node,
            .cli_path = cli,
            .server_path = server,
            .proxy_working_dir = work,
            .config_path = try runtime_paths.Path.init(config_path),
            .routing_config_path = routing,
            .plist_parent = plist_parent,
            .plist_path = plist,
            .receipt_parent = data,
            .receipt_path = receipt,
            .log_parent = logs,
            .stdout_path = stdout_path,
            .stderr_path = stderr_path,
            .uid = uid,
        };
    }

    pub fn programArguments(self: *const Paths) [4][]const u8 {
        return .{ self.node_path.slice(), self.server_path.slice(), "--config", self.config_path.slice() };
    }

    fn appendMany(path: *runtime_paths.Path, components: []const []const u8) !void {
        for (components) |component| try path.appendComponent(component);
    }
};

pub const HealthState = enum { healthy, @"unreachable", incompatible };
pub const Health = struct { state: HealthState, in_flight: u32 = 0 };

pub const HealthProbe = struct {
    context: *anyopaque,
    vtable: *const VTable,

    pub const VTable = struct { read: *const fn (*anyopaque, []const u8, []const u8) Health };

    pub fn read(self: HealthProbe, expected_config_path: []const u8, base_url: []const u8) Health {
        return self.vtable.read(self.context, expected_config_path, base_url);
    }
};

var unwired_health_context: u8 = 0;
const unwired_health_vtable: HealthProbe.VTable = .{ .read = unwiredHealth };
fn unwiredHealth(_: *anyopaque, _: []const u8, _: []const u8) Health {
    return .{ .state = .@"unreachable" };
}
pub fn unwiredHealthProbe() HealthProbe {
    return .{ .context = &unwired_health_context, .vtable = &unwired_health_vtable };
}

pub const LoopbackHealth = struct {
    allocator: std.mem.Allocator,
    exchange: proxy_control.Exchange,
    timeout_ms: u32 = proxy_control.default_timeout_ms,

    const vtable: HealthProbe.VTable = .{ .read = read };

    pub fn init(allocator: std.mem.Allocator, exchange: proxy_control.Exchange) LoopbackHealth {
        return .{ .allocator = allocator, .exchange = exchange };
    }

    pub fn probe(self: *LoopbackHealth) HealthProbe {
        return .{ .context = self, .vtable = &vtable };
    }

    fn read(context: *anyopaque, expected_config_path: []const u8, base_url: []const u8) Health {
        const self: *LoopbackHealth = @ptrCast(@alignCast(context));
        const parsed_base = proxy_control.BaseUrl.init(base_url) catch return .{ .state = .incompatible };
        var client = proxy_control.Client{
            .allocator = self.allocator,
            .exchange = self.exchange,
            .base_url = parsed_base,
            .config_path = expected_config_path,
            .timeout_ms = self.timeout_ms,
        };
        const status = client.status() catch |err| return .{ .state = switch (err) {
            error.IncompatibleVersion, error.InvalidResponse, error.InvalidStatus => .incompatible,
            else => .@"unreachable",
        } };
        if (status.version != 2 or !status.has_config_path or !status.config_path.eql(expected_config_path)) {
            return .{ .state = .incompatible };
        }
        return .{ .state = .healthy, .in_flight = status.in_flight };
    }
};

pub const ArtifactInspection = struct {
    plist_exists: bool = false,
    receipt_exists: bool = false,
    plist_matches: bool = false,
    receipt_matches: bool = false,
    bundle_matches: bool = false,

    pub fn anyInstalled(self: ArtifactInspection) bool {
        return self.plist_exists or self.receipt_exists;
    }
    pub fn current(self: ArtifactInspection) bool {
        return self.plist_exists and self.receipt_exists and self.plist_matches and self.receipt_matches and self.bundle_matches;
    }
};

pub const ArtifactStore = struct {
    context: *anyopaque,
    vtable: *const VTable,

    pub const VTable = struct {
        inspect: *const fn (*anyopaque, *const Paths, *const BundleIdentity, []const u8, []const u8) ArtifactInspection,
        ensure_parents: *const fn (*anyopaque, *const Paths) bool,
        write_plist: *const fn (*anyopaque, *const Paths, []const u8) bool,
        write_receipt: *const fn (*anyopaque, *const Paths, []const u8) bool,
        remove_owned: *const fn (*anyopaque, *const Paths) bool,
    };

    pub fn inspect(self: ArtifactStore, paths: *const Paths, identity: *const BundleIdentity, plist: []const u8, digest_hex: []const u8) ArtifactInspection {
        return self.vtable.inspect(self.context, paths, identity, plist, digest_hex);
    }
    pub fn ensureParents(self: ArtifactStore, paths: *const Paths) bool {
        return self.vtable.ensure_parents(self.context, paths);
    }
    pub fn writePlist(self: ArtifactStore, paths: *const Paths, bytes: []const u8) bool {
        return self.vtable.write_plist(self.context, paths, bytes);
    }
    pub fn writeReceipt(self: ArtifactStore, paths: *const Paths, bytes: []const u8) bool {
        return self.vtable.write_receipt(self.context, paths, bytes);
    }
    pub fn removeOwned(self: ArtifactStore, paths: *const Paths) bool {
        return self.vtable.remove_owned(self.context, paths);
    }
};

var unwired_artifacts_context: u8 = 0;
const unwired_artifacts_vtable: ArtifactStore.VTable = .{
    .inspect = unwiredInspectArtifacts,
    .ensure_parents = unwiredArtifactsFalse,
    .write_plist = unwiredArtifactsWrite,
    .write_receipt = unwiredArtifactsWrite,
    .remove_owned = unwiredArtifactsFalse,
};
fn unwiredInspectArtifacts(_: *anyopaque, _: *const Paths, _: *const BundleIdentity, _: []const u8, _: []const u8) ArtifactInspection {
    return .{};
}
fn unwiredArtifactsFalse(_: *anyopaque, _: *const Paths) bool {
    return false;
}
fn unwiredArtifactsWrite(_: *anyopaque, _: *const Paths, _: []const u8) bool {
    return false;
}
pub fn unwiredArtifactStore() ArtifactStore {
    return .{ .context = &unwired_artifacts_context, .vtable = &unwired_artifacts_vtable };
}

pub const Receipt = struct {
    schema: u16,
    canonical_app_path: []const u8,
    proxy_commit: []const u8,
    proxy_tree_sha256: []const u8,
    node_version: []const u8,
    node_sha256: []const u8,
    signed_node_sha256: []const u8,
    plist_sha256: []const u8,
    healthy_at_unix_ns: i128,
};

pub const Live = struct {
    io: std.Io,
    allocator: std.mem.Allocator,
    paths: Paths,
    identity: BundleIdentity,
    launch: proxy_launch.Runner = proxy_launch.unwiredRunner(),
    artifacts: ArtifactStore = unwiredArtifactStore(),
    routing: codex_routing.Editor = codex_routing.unwiredEditor(),
    health: HealthProbe = unwiredHealthProbe(),
    importer: proxy_import.Runner = proxy_import.unwiredRunner(),

    import_cli_path: []const u8 = "",
    import_node_path: []const u8 = "",
    control_base_url: []const u8 = default_control_base_url,
};

pub const LaunchPresence = enum { loaded, not_loaded, unknown };

pub const Discovery = struct {
    state: ui_model.ProxyServiceState = .not_installed,
    new_presence: LaunchPresence = .unknown,
    new_arguments_match: bool = false,
    health: Health = .{ .state = .@"unreachable" },
    artifacts: ArtifactInspection = .{},
    routing: codex_routing.Inspection = .{},
    detail: Text(256) = Text(256).init("Proxy service is not installed") catch unreachable,
};

pub const JobKind = enum { install, repair, stop, enable_routing, disable_routing, set_enabled_on, set_enabled_off };

pub const WorkerResult = struct {
    discovery: Discovery = .{},
    ok: bool = false,
};

pub const ProxyServiceWorker = struct {
    state: enum { idle, running, complete } = .idle,
    kind: JobKind = .install,
    replace_conflicting: bool = false,
    eligible_account: bool = false,
    live: Live = undefined,
    done: std.Io.Event = .unset,
    future: std.Io.Future(void) = undefined,
    started: bool = false,
    plist: [max_plist_bytes]u8 = @splat(0),
    plist_len: usize = 0,
    plist_digest_hex: [64]u8 = @splat(0),
    result: WorkerResult = .{},
    progress_in_flight: std.atomic.Value(u32) = .init(0),

    fn plistBytes(self: *const ProxyServiceWorker) []const u8 {
        return self.plist[0..self.plist_len];
    }

    fn run(io: std.Io, done: *std.Io.Event, self: *ProxyServiceWorker) void {
        defer done.set(io);
        self.result.ok = self.runJob();
        self.result.discovery = discoverNow(self.live, self.plistBytes(), &self.plist_digest_hex);
    }

    fn runJob(self: *ProxyServiceWorker) bool {
        const before = discoverNow(self.live, self.plistBytes(), &self.plist_digest_hex);
        return switch (self.kind) {
            .install => self.install(before),
            .repair => self.repair(before),
            .stop => self.stop(before),
            .enable_routing => self.enableRouting(before),
            .disable_routing => self.disableRouting(),
            .set_enabled_on => self.setEnabledOn(before),
            .set_enabled_off => self.setEnabledOff(before),
        };
    }

    fn runImporter(self: *ProxyServiceWorker) bool {
        if (!self.eligible_account) return false;
        return self.live.importer.run(.{
            .node_path = if (self.live.import_node_path.len == 0) self.live.paths.node_path.slice() else self.live.import_node_path,
            .cli_path = if (self.live.import_cli_path.len == 0) self.live.paths.cli_path.slice() else self.live.import_cli_path,
            .app_root = self.live.paths.app_data_root.slice(),
            .config_path = self.live.paths.config_path.slice(),
            .parent_env = .{ .pairs = &.{.{ .name = "HOME", .value = self.live.paths.home.slice() }} },
        }) == .success;
    }

    fn install(self: *ProxyServiceWorker, before: Discovery) bool {
        if (!self.eligible_account or before.new_presence != .not_loaded or before.artifacts.anyInstalled()) return false;

        if (!self.runImporter()) return false;
        if (!self.live.artifacts.ensureParents(&self.live.paths)) return false;
        if (!self.live.artifacts.writePlist(&self.live.paths, self.plistBytes())) return false;
        if (!runBootstrap(self.live)) return false;
        const health = self.waitForHealth() orelse return false;
        return self.writeReceipt(health);
    }

    fn repair(self: *ProxyServiceWorker, before: Discovery) bool {
        const loaded = before.new_presence == .loaded;
        if (loaded) {
            if (!before.new_arguments_match or !before.artifacts.bundle_matches) return false;
        } else if (before.new_presence != .not_loaded) return false;
        if (!self.live.artifacts.ensureParents(&self.live.paths)) return false;
        if (loaded) {
            if (before.health.state == .healthy) {
                _ = self.waitForZero() orelse return false;
                const fresh = self.live.health.read(self.live.paths.config_path.slice(), self.live.control_base_url);
                if (fresh.state != .healthy or fresh.in_flight != 0) return false;
            }
            if (!runBootout(self.live, new_label)) return false;
        }
        if (!self.live.artifacts.writePlist(&self.live.paths, self.plistBytes())) return false;
        if (!runBootstrap(self.live)) return false;
        const health = self.waitForHealth() orelse return false;
        return self.writeReceipt(health);
    }

    fn stop(self: *ProxyServiceWorker, before: Discovery) bool {
        if (before.state != .running or before.new_presence != .loaded or before.routing.state == .conflicting) return false;
        const disabled = self.live.routing.disable(self.live.paths.routing_config_path.slice());
        if (disabled.status != .success and disabled.status != .no_change) return false;
        _ = self.waitForZero() orelse return false;
        const fresh = self.live.health.read(self.live.paths.config_path.slice(), self.live.control_base_url);
        if (fresh.state != .healthy or fresh.in_flight != 0) return false;
        if (!runBootout(self.live, new_label)) return false;
        return self.live.artifacts.removeOwned(&self.live.paths);
    }

    fn enableRouting(self: *ProxyServiceWorker, before: Discovery) bool {
        if (before.state != .running or !std.mem.eql(u8, self.live.control_base_url, default_control_base_url)) return false;
        const expected = if (before.routing.state == .conflicting) before.routing.fingerprint else null;
        const result = self.live.routing.enable(
            self.live.paths.routing_config_path.slice(),
            self.replace_conflicting,
            expected,
        );
        return result.status == .success or result.status == .no_change;
    }

    fn disableRouting(self: *ProxyServiceWorker) bool {
        const result = self.live.routing.disable(self.live.paths.routing_config_path.slice());
        return result.status == .success or result.status == .no_change;
    }

    fn switchCanMutate(before: Discovery) bool {
        if (before.new_presence != .loaded) return before.new_presence == .not_loaded;
        return before.new_arguments_match and
            (before.health.state != .healthy or before.health.in_flight == 0);
    }

    fn setEnabledOn(self: *ProxyServiceWorker, before: Discovery) bool {
        if (!switchCanMutate(before) or before.routing.state == .conflicting or
            !std.mem.eql(u8, self.live.control_base_url, default_control_base_url)) return false;
        if (before.state == .running) return self.enableRouting(before);
        const started = switch (before.state) {
            .not_installed => self.install(before),
            .installed_stale, .@"unreachable" => self.repair(before),
            .starting, .running => false,
        };
        if (!started) return false;
        const after = discoverNow(self.live, self.plistBytes(), &self.plist_digest_hex);
        return self.enableRouting(after);
    }

    fn setEnabledOff(self: *ProxyServiceWorker, before: Discovery) bool {
        if (before.routing.state == .conflicting) return false;
        if (before.new_presence != .loaded or before.health.state != .healthy or
            !before.new_arguments_match) return self.disableRouting();
        if (!switchCanMutate(before)) return false;

        const disabled = self.live.routing.disable(self.live.paths.routing_config_path.slice());
        if (disabled.status != .success and disabled.status != .no_change) return false;

        const fresh = self.live.health.read(self.live.paths.config_path.slice(), self.live.control_base_url);
        if (fresh.state != .healthy or fresh.in_flight != 0) {
            if (before.routing.state == .on) {
                _ = self.live.routing.enable(self.live.paths.routing_config_path.slice(), false, null);
            }
            return false;
        }
        if (!runBootout(self.live, new_label)) return false;
        return self.live.artifacts.removeOwned(&self.live.paths);
    }

    fn waitForZero(self: *ProxyServiceWorker) ?Health {
        var attempts: usize = 0;
        while (attempts < drain_poll_limit) : (attempts += 1) {
            const health = self.live.health.read(self.live.paths.config_path.slice(), self.live.control_base_url);
            if (health.state != .healthy) return null;
            self.progress_in_flight.store(health.in_flight, .release);
            if (health.in_flight == 0) return health;
            self.live.io.sleep(.fromMilliseconds(drain_poll_ms), .awake) catch return null;
        }
        return null;
    }

    fn waitForHealth(self: *ProxyServiceWorker) ?Health {
        var attempts: usize = 0;
        while (attempts < drain_poll_limit) : (attempts += 1) {
            const health = self.live.health.read(self.live.paths.config_path.slice(), self.live.control_base_url);
            if (health.state == .healthy and health.in_flight == 0) return health;
            if (health.state == .incompatible) return null;
            self.live.io.sleep(.fromMilliseconds(drain_poll_ms), .awake) catch return null;
        }
        return null;
    }

    fn writeReceipt(self: *ProxyServiceWorker, _: Health) bool {
        var bytes: [max_receipt_bytes]u8 = undefined;
        const timestamp = std.Io.Clock.real.now(self.live.io).nanoseconds;
        const rendered = renderReceipt(&bytes, &self.live.paths, &self.live.identity, &self.plist_digest_hex, timestamp) catch return false;
        return self.live.artifacts.writeReceipt(&self.live.paths, rendered);
    }
};

pub fn prepareUninstall(live: Live) !void {
    const restored = live.routing.disable(live.paths.routing_config_path.slice());
    if (restored.state != .off or (restored.status != .success and restored.status != .no_change))
        return error.RoutingNeedsManualReview;
    var plist_buffer: [max_plist_bytes]u8 = undefined;
    const plist = try renderPlist(&plist_buffer, &live.paths, &live.identity);
    var digest: [64]u8 = undefined;
    digestHex(plist, &digest);
    const before = discoverNow(live, plist, &digest);
    if (before.new_presence == .unknown) return error.ServiceOwnershipUnknown;
    if (before.new_presence == .loaded) {
        if (!before.new_arguments_match) return error.ServiceOwnershipUnknown;
        var attempts: usize = 0;
        while (true) : (attempts += 1) {
            const health = live.health.read(live.paths.config_path.slice(), live.control_base_url);
            if (health.state == .incompatible) return error.ServiceOwnershipUnknown;
            if (health.state == .@"unreachable" or health.in_flight == 0) break;
            if (attempts >= drain_poll_limit) return error.RequestsStillRunning;
            try live.io.sleep(.fromMilliseconds(drain_poll_ms), .awake);
        }
        var target_buffer: [192]u8 = undefined;
        const target = domainTarget(&target_buffer, live.paths.uid, new_label) orelse return error.InvalidTarget;
        const arguments = live.paths.programArguments();
        if (live.launch.run(.{ .print = .{ .domain_target = target, .program_arguments = &arguments } }).status != .loaded)
            return error.ServiceOwnershipUnknown;
        if (!runBootout(live, new_label)) return error.StopFailed;
    } else if (before.artifacts.plist_exists and !before.artifacts.plist_matches) {
        return error.ServiceOwnershipUnknown;
    }
    if (!live.artifacts.removeOwned(&live.paths)) return error.RemoveFailed;
}

pub const Controller = struct {
    worker: ProxyServiceWorker = .{},
    discovery: Discovery = .{},
    initialized: bool = false,
    switch_refusal_detail: ?Text(256) = null,

    pub fn refresh(self: *Controller, live: Live) void {
        var plist: [max_plist_bytes]u8 = undefined;
        const bytes = renderPlist(&plist, &live.paths, &live.identity) catch return;
        var digest: [64]u8 = undefined;
        digestHex(bytes, &digest);
        self.discovery = discoverNow(live, bytes, &digest);
        if (self.discovery.health.state != .healthy or self.discovery.health.in_flight == 0) {
            self.switch_refusal_detail = null;
        }
        self.initialized = true;
    }

    pub fn observeProxyHealth(self: *Controller, health: Health) void {
        if (!self.initialized or self.discovery.new_presence != .loaded) return;
        self.discovery.health = health;
        if (health.state != .healthy or health.in_flight == 0) self.switch_refusal_detail = null;
    }

    pub fn busy(self: *const Controller) bool {
        return self.worker.state != .idle;
    }

    pub fn submit(self: *Controller, kind: JobKind, replace_conflicting: bool, eligible_account: bool, live: Live) ui_model.CommandOutcome {
        if (self.busy()) return .rejected_busy;
        const whole_switch = kind == .set_enabled_on or kind == .set_enabled_off;
        if (whole_switch and self.discovery.new_presence == .loaded and
            self.discovery.health.state == .healthy and self.discovery.health.in_flight != 0)
        {
            var buffer: [256]u8 = undefined;
            const detail = std.fmt.bufPrint(
                &buffer,
                "{d} proxy request(s) are in flight. The switch will apply when they finish.",
                .{self.discovery.health.in_flight},
            ) catch "Proxy requests are in flight. The switch will apply when they finish.";
            self.switch_refusal_detail = Text(256).init(detail) catch null;
            return .rejected_busy;
        }
        const projected = self.fact(eligible_account, &live.paths);
        const allowed = switch (kind) {
            .install => projected.can_install,
            .repair => projected.can_repair,
            .stop => projected.can_stop,
            .enable_routing => self.discovery.state == .running and
                (self.discovery.routing.state != .conflicting or replace_conflicting) and
                std.mem.eql(u8, live.control_base_url, default_control_base_url),
            .disable_routing => self.discovery.routing.readable and self.discovery.routing.state != .conflicting,
            .set_enabled_on => self.discovery.routing.state != .conflicting and
                std.mem.eql(u8, live.control_base_url, default_control_base_url) and
                switch (self.discovery.state) {
                    .running => self.discovery.health.state == .healthy,
                    .not_installed => projected.can_install,
                    .installed_stale, .@"unreachable" => projected.can_repair,
                    .starting => false,
                },
            .set_enabled_off => self.discovery.routing.readable and self.discovery.routing.state != .conflicting,
        };
        if (!allowed) return .rejected_not_allowed;
        if (whole_switch) self.switch_refusal_detail = null;

        self.worker = .{};
        self.worker.kind = kind;
        self.worker.replace_conflicting = replace_conflicting;
        self.worker.eligible_account = eligible_account;
        self.worker.live = live;
        const plist = renderPlist(&self.worker.plist, &self.worker.live.paths, &self.worker.live.identity) catch return .failed;
        self.worker.plist_len = plist.len;
        digestHex(plist, &self.worker.plist_digest_hex);
        self.worker.done = .unset;
        self.worker.future = live.io.concurrent(ProxyServiceWorker.run, .{ live.io, &self.worker.done, &self.worker }) catch return .failed;
        self.worker.started = true;
        self.worker.state = .running;
        return .accepted_pending;
    }

    pub fn drain(self: *Controller, io: std.Io) void {
        if (self.worker.state != .running or !self.worker.done.isSet()) return;
        _ = self.worker.future.await(io);
        self.worker.started = false;
        self.worker.state = .complete;
        self.discovery = self.worker.result.discovery;
        self.initialized = true;
        self.worker.state = .idle;
    }

    pub fn shutdown(self: *Controller, io: std.Io) void {
        if (self.worker.state == .running and self.worker.started) {
            _ = self.worker.future.cancel(io);
            _ = self.worker.future.await(io);
        }
        self.worker = .{};
    }

    pub fn markSettingsChanged(self: *Controller) void {
        if (self.worker.state != .idle) return;
        switch (self.discovery.state) {
            .running, .@"unreachable", .installed_stale => {
                self.discovery.state = .installed_stale;
                self.discovery.detail = Text(256).init("Proxy settings changed; repair is required.") catch unreachable;
            },
            else => {},
        }
    }

    pub fn fact(self: *const Controller, eligible_account: bool, paths: *const Paths) ui_model.ProxyServiceFact {
        if (self.worker.state == .running) {
            const count = self.worker.progress_in_flight.load(.acquire);
            return .{
                .state = .starting,
                .detail_text = if (count == 0) "Proxy service change is starting" else "Waiting for proxy requests to finish",
                .routing_state = self.discovery.routing.state,
                .enabled = self.discovery.routing.state == .on,
                .enabled_detail_text = "Applying the failover proxy switch…",
                .cli_default_path = paths.cli_path.slice(),
                .node_default_path = paths.node_path.slice(),
            };
        }
        const state = self.discovery.state;
        const no_job = self.worker.state == .idle;
        const repairable_loaded = self.discovery.new_presence == .loaded and
            self.discovery.new_arguments_match and self.discovery.artifacts.bundle_matches;
        const repairable_unloaded = self.discovery.new_presence == .not_loaded;
        const enabled = self.discovery.routing.state == .on;
        return .{
            .state = state,
            .detail_text = self.discovery.detail.slice(),
            .can_install = no_job and state == .not_installed and self.discovery.new_presence == .not_loaded and eligible_account,
            .can_repair = no_job and (state == .installed_stale or state == .@"unreachable") and (repairable_loaded or repairable_unloaded),
            .can_stop = no_job and state == .running and self.discovery.routing.state != .conflicting,
            .routing_state = self.discovery.routing.state,
            .enabled = enabled,
            .enabled_detail_text = if (self.switch_refusal_detail) |*detail|
                detail.slice()
            else if (enabled and state == .running)
                "Codex routes through the running failover proxy."
            else if (enabled)
                "Codex still routes to an unavailable proxy. Turn this off to restore direct routing."
            else if (self.discovery.routing.state == .conflicting)
                "Codex routing has conflicting settings. Review advanced controls."
            else
                "Codex routes directly; the failover proxy is off.",
            .cli_default_path = paths.cli_path.slice(),
            .node_default_path = paths.node_path.slice(),
        };
    }

    pub fn project(self: *const Controller, view: *ui_model.ViewState, eligible_account: bool, paths: *const Paths) void {
        var projected = self.fact(eligible_account, paths);
        var detail_buffer: [128]u8 = undefined;
        if (self.worker.state == .running) {
            const count = self.worker.progress_in_flight.load(.acquire);
            if (count != 0) projected.detail_text = std.fmt.bufPrint(
                &detail_buffer,
                "Waiting for {d} proxy request(s) to finish",
                .{count},
            ) catch projected.detail_text;
        }
        view.applyProxyService(projected);
    }
};

fn discoverNow(live: Live, plist: []const u8, digest_hex: []const u8) Discovery {
    const args = live.paths.programArguments();
    var new_target_buffer: [192]u8 = undefined;
    const new_target = domainTarget(&new_target_buffer, live.paths.uid, new_label) orelse return .{};
    const new_result = live.launch.run(.{ .print = .{ .domain_target = new_target, .program_arguments = &args } });
    const new_presence = launchPresence(new_result.status);
    const arguments_match = new_result.status == .loaded;
    const artifacts = live.artifacts.inspect(&live.paths, &live.identity, plist, digest_hex);
    const routing = live.routing.inspect(live.paths.routing_config_path.slice());
    var health: Health = .{ .state = .@"unreachable" };
    if (new_presence == .loaded) {
        health = live.health.read(live.paths.config_path.slice(), live.control_base_url);
    }
    const state: ui_model.ProxyServiceState = if (!artifacts.anyInstalled() and new_presence == .not_loaded)
        .not_installed
    else if (!artifacts.current() or (new_presence == .loaded and !arguments_match))
        .installed_stale
    else if (new_presence == .loaded and health.state == .healthy)
        .running
    else
        .@"unreachable";
    const detail_text: []const u8 = switch (state) {
        .not_installed => "Proxy service is not installed",
        .installed_stale => "Bundled proxy files or receipt changed; repair is required.",
        .starting => "Proxy service change is starting",
        .running => "Bundled proxy service is running.",
        .@"unreachable" => if (new_presence == .loaded) "The proxy is not responding. Repair it or turn off routing to connect directly." else "Proxy service is installed but unreachable.",
    };
    return .{
        .state = state,
        .new_presence = new_presence,
        .new_arguments_match = arguments_match,
        .health = health,
        .artifacts = artifacts,
        .routing = routing,
        .detail = Text(256).init(detail_text) catch unreachable,
    };
}

fn launchPresence(status: proxy_launch.Status) LaunchPresence {
    return switch (status) {
        .loaded, .loaded_arguments_mismatch => .loaded,
        .not_loaded => .not_loaded,
        else => .unknown,
    };
}

fn domainText(buffer: []u8, uid: u32) ?[]const u8 {
    return std.fmt.bufPrint(buffer, "gui/{d}", .{uid}) catch null;
}

fn domainTarget(buffer: []u8, uid: u32, label: []const u8) ?[]const u8 {
    return std.fmt.bufPrint(buffer, "gui/{d}/{s}", .{ uid, label }) catch null;
}

fn runBootstrap(live: Live) bool {
    var buffer: [64]u8 = undefined;
    const domain = domainText(&buffer, live.paths.uid) orelse return false;
    return live.launch.run(.{ .bootstrap = .{ .domain = domain, .plist_path = live.paths.plist_path.slice() } }).status == .success;
}

fn runBootout(live: Live, label: []const u8) bool {
    var buffer: [192]u8 = undefined;
    const target = domainTarget(&buffer, live.paths.uid, label) orelse return false;
    return live.launch.run(.{ .bootout = .{ .domain_target = target } }).status == .success;
}

pub fn renderPlist(buffer: []u8, paths: *const Paths, identity: *const BundleIdentity) ![]const u8 {
    var writer: std.Io.Writer = .fixed(buffer);
    try writer.writeAll("<?xml version=\"1.0\" encoding=\"UTF-8\"?>\n<!DOCTYPE plist PUBLIC \"-//Apple//DTD PLIST 1.0//EN\" \"http://www.apple.com/DTDs/PropertyList-1.0.dtd\">\n<plist version=\"1.0\">\n<dict>\n");
    try writer.print("<!-- proxy_commit={s} proxy_tree_sha256={s} node_version={s} node_sha256={s} signed_node_sha256={s} -->\n", .{
        identity.proxy_commit.slice(), identity.proxy_tree_sha256.slice(), identity.node_version.slice(), identity.node_sha256.slice(), identity.signed_node_sha256.slice(),
    });
    try writer.writeAll("<key>Label</key>\n<string>" ++ new_label ++ "</string>\n<key>ProgramArguments</key>\n<array>\n");
    for (paths.programArguments()) |argument| {
        try writer.writeAll("<string>");
        try writeXmlEscaped(&writer, argument);
        try writer.writeAll("</string>\n");
    }
    try writer.writeAll("</array>\n<key>WorkingDirectory</key>\n<string>");
    try writeXmlEscaped(&writer, paths.proxy_working_dir.slice());
    try writer.writeAll("</string>\n<key>RunAtLoad</key>\n<true/>\n<key>KeepAlive</key>\n<true/>\n<key>ThrottleInterval</key>\n<integer>5</integer>\n<key>Umask</key>\n<integer>63</integer>\n<key>StandardOutPath</key>\n<string>");
    try writeXmlEscaped(&writer, paths.stdout_path.slice());
    try writer.writeAll("</string>\n<key>StandardErrorPath</key>\n<string>");
    try writeXmlEscaped(&writer, paths.stderr_path.slice());
    try writer.writeAll("</string>\n<key>EnvironmentVariables</key>\n<dict>\n<key>HOME</key>\n<string>");
    try writeXmlEscaped(&writer, paths.home.slice());
    try writer.writeAll("</string>\n</dict>\n</dict>\n</plist>\n");
    return buffer[0..writer.end];
}

fn writeXmlEscaped(writer: *std.Io.Writer, value: []const u8) !void {
    for (value) |byte| switch (byte) {
        '&' => try writer.writeAll("&amp;"),
        '<' => try writer.writeAll("&lt;"),
        '>' => try writer.writeAll("&gt;"),
        '"' => try writer.writeAll("&quot;"),
        '\'' => try writer.writeAll("&apos;"),
        0...0x1f, 0x7f => return error.InvalidXmlText,
        else => try writer.writeByte(byte),
    };
}

pub fn digestHex(bytes: []const u8, out: *[64]u8) void {
    var digest: [32]u8 = undefined;
    std.crypto.hash.sha2.Sha256.hash(bytes, &digest, .{});
    const alphabet = "0123456789abcdef";
    for (digest, 0..) |byte, index| {
        out[index * 2] = alphabet[byte >> 4];
        out[index * 2 + 1] = alphabet[byte & 0x0f];
    }
}

pub fn renderReceipt(buffer: []u8, paths: *const Paths, identity: *const BundleIdentity, plist_digest: []const u8, healthy_at_unix_ns: i128) ![]const u8 {
    var writer: std.Io.Writer = .fixed(buffer);
    try std.json.Stringify.value(Receipt{
        .schema = receipt_schema,
        .canonical_app_path = paths.app_path.slice(),
        .proxy_commit = identity.proxy_commit.slice(),
        .proxy_tree_sha256 = identity.proxy_tree_sha256.slice(),
        .node_version = identity.node_version.slice(),
        .node_sha256 = identity.node_sha256.slice(),
        .signed_node_sha256 = identity.signed_node_sha256.slice(),
        .plist_sha256 = plist_digest,
        .healthy_at_unix_ns = healthy_at_unix_ns,
    }, .{}, &writer);
    try writer.writeByte('\n');
    return buffer[0..writer.end];
}

pub const FileArtifacts = struct {
    io: std.Io,
    allocator: std.mem.Allocator,

    const vtable: ArtifactStore.VTable = .{
        .inspect = inspect,
        .ensure_parents = ensureParents,
        .write_plist = writePlist,
        .write_receipt = writeReceipt,
        .remove_owned = removeOwned,
    };

    pub fn init(io: std.Io, allocator: std.mem.Allocator) FileArtifacts {
        return .{ .io = io, .allocator = allocator };
    }
    pub fn store(self: *FileArtifacts) ArtifactStore {
        return .{ .context = self, .vtable = &vtable };
    }

    fn inspect(context: *anyopaque, paths: *const Paths, identity: *const BundleIdentity, plist: []const u8, digest_hex: []const u8) ArtifactInspection {
        const self: *FileArtifacts = @ptrCast(@alignCast(context));
        const plist_bytes = self.readRegular(paths.plist_path.slice(), max_plist_bytes, paths.uid) catch null;
        defer if (plist_bytes) |bytes| self.allocator.free(bytes);
        const receipt_bytes = self.readRegular(paths.receipt_path.slice(), max_receipt_bytes, paths.uid) catch null;
        defer if (receipt_bytes) |bytes| self.allocator.free(bytes);
        return .{
            .plist_exists = plist_bytes != null,
            .receipt_exists = receipt_bytes != null,
            .plist_matches = if (plist_bytes) |bytes| std.mem.eql(u8, bytes, plist) else false,
            .receipt_matches = if (receipt_bytes) |bytes| receiptMatches(self.allocator, bytes, paths, identity, digest_hex) else false,
            .bundle_matches = bundleMatches(self.io, self.allocator, paths, identity),
        };
    }

    fn ensureParents(context: *anyopaque, paths: *const Paths) bool {
        const self: *FileArtifacts = @ptrCast(@alignCast(context));
        return ensurePrivateTree(self.io, paths.home.slice(), paths.plist_parent.slice(), paths.uid) and
            ensurePrivateTree(self.io, paths.home.slice(), paths.receipt_parent.slice(), paths.uid) and
            ensurePrivateTree(self.io, paths.home.slice(), paths.log_parent.slice(), paths.uid);
    }

    fn writePlist(context: *anyopaque, paths: *const Paths, bytes: []const u8) bool {
        const self: *FileArtifacts = @ptrCast(@alignCast(context));
        return writeAtomicPrivate(self.io, paths.plist_path.slice(), bytes, paths.uid);
    }

    fn writeReceipt(context: *anyopaque, paths: *const Paths, bytes: []const u8) bool {
        const self: *FileArtifacts = @ptrCast(@alignCast(context));
        return writeAtomicPrivate(self.io, paths.receipt_path.slice(), bytes, paths.uid);
    }

    fn removeOwned(context: *anyopaque, paths: *const Paths) bool {
        const self: *FileArtifacts = @ptrCast(@alignCast(context));
        return removeRegularOrMissing(self.io, paths.plist_path.slice(), paths.uid) and removeRegularOrMissing(self.io, paths.receipt_path.slice(), paths.uid);
    }

    fn readRegular(self: *FileArtifacts, path: []const u8, max: usize, uid: u32) ![]u8 {
        const cwd = std.Io.Dir.cwd();
        var file = try cwd.openFile(self.io, path, .{ .allow_directory = false, .follow_symlinks = false });
        defer file.close(self.io);
        const stat = try file.stat(self.io);
        if (stat.kind != .file) return error.Unsafe;
        if (stat.size > max) return error.FileTooBig;
        if (!handleOwnedBy(file.handle, uid)) return error.Unsafe;
        var reader = file.reader(self.io, &.{});
        return reader.interface.allocRemaining(self.allocator, .limited(max)) catch |err| switch (err) {
            error.StreamTooLong => return error.FileTooBig,
            error.OutOfMemory => return error.OutOfMemory,
            error.ReadFailed => return reader.err.?,
        };
    }
};

fn isRegular(io: std.Io, path: []const u8) bool {
    var file = std.Io.Dir.cwd().openFile(io, path, .{ .allow_directory = false, .follow_symlinks = false }) catch return false;
    defer file.close(io);
    const stat = file.stat(io) catch return false;
    return stat.kind == .file;
}

fn isOwnedRegular(io: std.Io, path: []const u8, uid: u32) bool {
    var file = std.Io.Dir.cwd().openFile(io, path, .{ .allow_directory = false, .follow_symlinks = false }) catch return false;
    defer file.close(io);
    const stat = file.stat(io) catch return false;
    return stat.kind == .file and handleOwnedBy(file.handle, uid);
}

fn ensurePrivateTree(io: std.Io, home: []const u8, target: []const u8, uid: u32) bool {
    if (!std.mem.startsWith(u8, target, home) or target.len <= home.len or target[home.len] != '/') return false;
    var buffer: [runtime_paths.max_path_bytes]u8 = undefined;
    @memcpy(buffer[0..home.len], home);
    var len = home.len;
    const cwd = std.Io.Dir.cwd();
    var parts = std.mem.splitScalar(u8, target[home.len + 1 ..], '/');
    while (parts.next()) |part| {
        if (part.len == 0 or len + 1 + part.len > buffer.len) return false;
        buffer[len] = '/';
        len += 1;
        @memcpy(buffer[len..][0..part.len], part);
        len += part.len;
        const path = buffer[0..len];
        const stat = cwd.statFile(io, path, .{ .follow_symlinks = false }) catch |err| switch (err) {
            error.FileNotFound => {
                cwd.createDir(io, path, std.Io.File.Permissions.fromMode(0o700)) catch return false;
                continue;
            },
            else => return false,
        };
        if (stat.kind != .directory or (stat.permissions.toMode() & 0o022) != 0) return false;
        var opened = std.Io.Dir.openDirAbsolute(io, path, .{ .follow_symlinks = false }) catch return false;
        defer opened.close(io);
        if (!handleOwnedBy(opened.handle, uid)) return false;
    }
    return true;
}

fn writeAtomicPrivate(io: std.Io, path: []const u8, bytes: []const u8, uid: u32) bool {
    const cwd = std.Io.Dir.cwd();
    if (cwd.statFile(io, path, .{ .follow_symlinks = false })) |stat| {
        if (stat.kind != .file or !isOwnedRegular(io, path, uid)) return false;
    } else |err| if (err != error.FileNotFound) return false;
    var temp_buffer: [runtime_paths.max_path_bytes + 48]u8 = undefined;
    const stamp = std.Io.Clock.real.now(io).nanoseconds;
    const temp = std.fmt.bufPrint(&temp_buffer, "{s}.tmp.{d}", .{ path, stamp }) catch return false;
    var file = cwd.createFile(io, temp, .{
        .exclusive = true,
        .permissions = std.Io.File.Permissions.fromMode(0o600),
    }) catch return false;
    file.setPermissions(io, std.Io.File.Permissions.fromMode(0o600)) catch {
        file.close(io);
        cwd.deleteFile(io, temp) catch {};
        return false;
    };
    file.writeStreamingAll(io, bytes) catch {
        file.close(io);
        cwd.deleteFile(io, temp) catch {};
        return false;
    };
    file.sync(io) catch {
        file.close(io);
        cwd.deleteFile(io, temp) catch {};
        return false;
    };
    file.close(io);
    cwd.rename(temp, cwd, path, io) catch {
        cwd.deleteFile(io, temp) catch {};
        return false;
    };
    return true;
}

fn removeRegularOrMissing(io: std.Io, path: []const u8, uid: u32) bool {
    const cwd = std.Io.Dir.cwd();
    const stat = cwd.statFile(io, path, .{ .follow_symlinks = false }) catch |err| return err == error.FileNotFound;
    if (stat.kind != .file or !isOwnedRegular(io, path, uid)) return false;
    cwd.deleteFile(io, path) catch return false;
    return true;
}

fn handleOwnedBy(handle: std.posix.fd_t, uid: u32) bool {
    var stat: std.c.Stat = undefined;
    if (std.c.fstat(handle, &stat) != 0) return false;
    return stat.uid == uid;
}

fn receiptMatches(allocator: std.mem.Allocator, bytes: []const u8, paths: *const Paths, identity: *const BundleIdentity, digest_hex: []const u8) bool {
    var parsed = std.json.parseFromSlice(Receipt, allocator, bytes, .{ .ignore_unknown_fields = false }) catch return false;
    defer parsed.deinit();
    const value = parsed.value;
    return value.schema == receipt_schema and
        std.mem.eql(u8, value.canonical_app_path, paths.app_path.slice()) and
        identity.proxy_commit.eql(value.proxy_commit) and
        identity.proxy_tree_sha256.eql(value.proxy_tree_sha256) and
        identity.node_version.eql(value.node_version) and
        identity.node_sha256.eql(value.node_sha256) and
        identity.signed_node_sha256.eql(value.signed_node_sha256) and
        std.mem.eql(u8, value.plist_sha256, digest_hex);
}

fn bundleMatches(io: std.Io, allocator: std.mem.Allocator, paths: *const Paths, identity: *const BundleIdentity) bool {
    if (!isRegular(io, paths.node_path.slice()) or !isRegular(io, paths.server_path.slice()) or !isRegular(io, paths.cli_path.slice())) return false;
    var node_file = std.Io.Dir.cwd().openFile(io, paths.node_path.slice(), .{ .allow_directory = false, .follow_symlinks = false }) catch return false;
    defer node_file.close(io);
    var node_reader = node_file.reader(io, &.{});
    const node = node_reader.interface.allocRemaining(allocator, .limited(145 * 1024 * 1024)) catch return false;
    defer allocator.free(node);
    var digest: [64]u8 = undefined;
    digestHex(node, &digest);
    if (!identity.signed_node_sha256.eql(&digest)) return false;
    var tree_digest: [64]u8 = undefined;
    if (!computeProxyTreeDigest(allocator, io, paths.proxy_working_dir.slice(), &tree_digest)) return false;
    if (!identity.proxy_tree_sha256.eql(&tree_digest)) return false;
    return provenanceMatches(allocator, io, paths.proxy_working_dir.slice(), identity);
}

const ManifestEntry = struct {
    path: []u8,
    mode: std.posix.mode_t,
    size: u64,
    digest: [64]u8,
};

pub fn computeProxyTreeDigest(
    allocator: std.mem.Allocator,
    io: std.Io,
    proxy_root: []const u8,
    out: *[64]u8,
) bool {
    var dir = std.Io.Dir.openDirAbsolute(io, proxy_root, .{ .iterate = true }) catch return false;
    defer dir.close(io);
    var walker = dir.walk(allocator) catch return false;
    defer walker.deinit();
    var entries = std.ArrayList(ManifestEntry).empty;
    defer {
        for (entries.items) |entry| allocator.free(entry.path);
        entries.deinit(allocator);
    }
    var saw_package = false;
    var saw_bin = false;
    var saw_src = false;
    var total_bytes: u64 = 0;
    while (walker.next(io) catch return false) |entry| {
        const relative: []const u8 = entry.path;
        const top_end = std.mem.indexOfScalar(u8, relative, '/') orelse relative.len;
        const top = relative[0..top_end];
        if (std.mem.eql(u8, top, "PROVENANCE")) {
            if (relative.len != "PROVENANCE".len or entry.kind != .file) return false;
            continue;
        }
        const allowed = std.mem.eql(u8, top, "package.json") or std.mem.eql(u8, top, "bin") or std.mem.eql(u8, top, "src");
        if (!allowed) return false;
        if (std.mem.eql(u8, top, "package.json")) {
            if (relative.len != "package.json".len or entry.kind != .file) return false;
            saw_package = true;
        } else if (std.mem.eql(u8, top, "bin")) {
            saw_bin = true;
        } else saw_src = true;
        if (entry.kind == .directory) continue;
        if (entry.kind != .file) return false;
        const stat = entry.dir.statFile(io, entry.basename, .{ .follow_symlinks = false }) catch return false;
        if (stat.kind != .file or stat.size > 1024 * 1024 or total_bytes + stat.size > 1024 * 1024) return false;
        total_bytes += stat.size;
        const bytes = entry.dir.readFileAlloc(io, entry.basename, allocator, .limited(1024 * 1024)) catch return false;
        defer allocator.free(bytes);
        var file_digest: [64]u8 = undefined;
        digestHex(bytes, &file_digest);
        entries.append(allocator, .{
            .path = allocator.dupe(u8, relative) catch return false,
            .mode = stat.permissions.toMode() & 0o7777,
            .size = stat.size,
            .digest = file_digest,
        }) catch return false;
    }
    if (!saw_package or !saw_bin or !saw_src or entries.items.len == 0) return false;
    std.mem.sort(ManifestEntry, entries.items, {}, struct {
        fn less(_: void, left: ManifestEntry, right: ManifestEntry) bool {
            return std.mem.order(u8, left.path, right.path) == .lt;
        }
    }.less);
    var hasher = std.crypto.hash.sha2.Sha256.init(.{});
    var line: [1024]u8 = undefined;
    for (entries.items) |entry| {
        const rendered = std.fmt.bufPrint(&line, "{s}\t{o}\t{d}\t{s}\n", .{ entry.path, entry.mode, entry.size, &entry.digest }) catch return false;
        hasher.update(rendered);
    }
    var raw: [32]u8 = undefined;
    hasher.final(&raw);
    const alphabet = "0123456789abcdef";
    for (raw, 0..) |byte, index| {
        out[index * 2] = alphabet[byte >> 4];
        out[index * 2 + 1] = alphabet[byte & 0x0f];
    }
    return true;
}

fn provenanceMatches(allocator: std.mem.Allocator, io: std.Io, proxy_root: []const u8, identity: *const BundleIdentity) bool {
    const path = std.fmt.allocPrint(allocator, "{s}/PROVENANCE", .{proxy_root}) catch return false;
    defer allocator.free(path);
    const bytes = std.Io.Dir.cwd().readFileAlloc(io, path, allocator, .limited(4096)) catch return false;
    defer allocator.free(bytes);
    const markers = [_]struct { name: []const u8, value: []const u8 }{
        .{ .name = "CODEXMULTI_PROXY_COMMIT", .value = identity.proxy_commit.slice() },
        .{ .name = "CODEXMULTI_PROXY_TREE_SHA256", .value = identity.proxy_tree_sha256.slice() },
        .{ .name = "CODEXMULTI_NODE_VERSION", .value = identity.node_version.slice() },
        .{ .name = "CODEXMULTI_NODE_SHA256", .value = identity.node_sha256.slice() },
        .{ .name = "CODEXMULTI_SIGNED_NODE_SHA256", .value = identity.signed_node_sha256.slice() },
    };
    for (markers) |marker| {
        var expected: [160]u8 = undefined;
        const line = std.fmt.bufPrint(&expected, "{s}={s}", .{ marker.name, marker.value }) catch return false;
        var found: usize = 0;
        var lines = std.mem.splitScalar(u8, bytes, '\n');
        while (lines.next()) |candidate| if (std.mem.eql(u8, candidate, line)) {
            found += 1;
        };
        if (found != 1) return false;
    }
    return true;
}

pub fn loadBundleIdentity(allocator: std.mem.Allocator, io: std.Io, app_path: []const u8) !BundleIdentity {
    const provenance_path = try std.fmt.allocPrint(allocator, "{s}/Contents/Resources/proxy/PROVENANCE", .{app_path});
    defer allocator.free(provenance_path);
    const bytes = try std.Io.Dir.cwd().readFileAlloc(io, provenance_path, allocator, .limited(4096));
    defer allocator.free(bytes);
    var commit: ?[]const u8 = null;
    var tree: ?[]const u8 = null;
    var version: ?[]const u8 = null;
    var node: ?[]const u8 = null;
    var signed: ?[]const u8 = null;
    var lines = std.mem.splitScalar(u8, bytes, '\n');
    while (lines.next()) |line| {
        if (std.mem.startsWith(u8, line, "CODEXMULTI_PROXY_COMMIT=")) commit = line["CODEXMULTI_PROXY_COMMIT=".len..] else if (std.mem.startsWith(u8, line, "CODEXMULTI_PROXY_TREE_SHA256=")) tree = line["CODEXMULTI_PROXY_TREE_SHA256=".len..] else if (std.mem.startsWith(u8, line, "CODEXMULTI_NODE_VERSION=")) version = line["CODEXMULTI_NODE_VERSION=".len..] else if (std.mem.startsWith(u8, line, "CODEXMULTI_NODE_SHA256=")) node = line["CODEXMULTI_NODE_SHA256=".len..] else if (std.mem.startsWith(u8, line, "CODEXMULTI_SIGNED_NODE_SHA256=")) signed = line["CODEXMULTI_SIGNED_NODE_SHA256=".len..];
    }
    return BundleIdentity.init(commit orelse return error.MissingMarker, tree orelse return error.MissingMarker, version orelse return error.MissingMarker, node orelse return error.MissingMarker, signed orelse return error.MissingMarker);
}
