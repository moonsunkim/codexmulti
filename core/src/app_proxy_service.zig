const std = @import("std");
const account_registry = @import("account_registry.zig");
const app_worker = @import("app_worker.zig");
const coordinator = @import("coordinator.zig");
const proxy_control = @import("proxy_control_client.zig");
const proxy_import = @import("proxy_import_runner.zig");
const runtime_paths = @import("runtime_paths.zig");
const store = @import("store.zig");
const transport = @import("process_jsonl.zig");
const ui_model = @import("ui_model.zig");

pub const Reachability = ui_model.ProxyReachability;
pub const AttemptResult = ui_model.ProxyAttemptResult;
pub const SyncState = ui_model.ProxySyncState;

pub const Attempt = struct { at_unix_s: i64, result: AttemptResult };

pub const Settings = struct {
    base_url: proxy_control.BaseUrl = proxy_control.BaseUrl.init(store.default_proxy_base_url) catch unreachable,

    cli_path: ?runtime_paths.Path = null,
    config_path: proxy_control.BoundedText(runtime_paths.max_path_bytes) = proxy_control.BoundedText(runtime_paths.max_path_bytes).init(store.default_proxy_config_path) catch unreachable,

    node_path: ?runtime_paths.Path = null,
    last_synced_fingerprint: ?proxy_control.BoundedText(store.max_proxy_fingerprint_bytes) = null,
};

pub const State = struct {
    settings: Settings = .{},
    reachability: Reachability = .unknown,
    work: ui_model.ProxyWork = .idle,
    sync_state: SyncState = .unknown,
    last_attempt: ?Attempt = null,
    last_success_at_unix_s: ?i64 = null,
    success_revision: u64 = 0,
    last_success: ?proxy_control.MappedStatus = null,
    config_path_matches: bool = false,

    resolved_node: ?runtime_paths.Path = null,
};

pub const Drivers = struct {
    io: std.Io,
    allocator: std.mem.Allocator,
    sink: coordinator.DocumentSink,
    parent_env: transport.ParentEnv,
    exchange: proxy_control.Exchange,
    importer: proxy_import.Runner,
    node_resolver: proxy_import.NodeResolver,
    bundle_cli_path: []const u8 = "",
    bundle_node_path: []const u8 = "",
};

pub const Completion = struct {
    serial: u64 = 0,
    kind: app_worker.ProxyJobKind = .refresh_status,

    ok: bool = false,
};

pub const Controller = struct {
    worker: app_worker.ProxyWorker = .{},
    state: State = .{},
    last_completion: Completion = .{},
    sync_fingerprint: ?proxy_control.BoundedText(store.max_proxy_fingerprint_bytes) = null,
    removal_pause_account: proxy_control.BoundedText(account_registry.max_id_bytes) = .{},
    removal_pause_set: bool = false,
    removal_pause_revision: u64 = 0,

    pub fn statePtr(self: *const Controller) *const State {
        return &self.state;
    }

    pub fn busy(self: *const Controller) bool {
        return self.worker.state != .idle;
    }

    pub fn lastCompletion(self: *const Controller) Completion {
        return self.last_completion;
    }

    pub fn recordRegistryChange(self: *Controller) void {
        self.state.sync_state = .needed;
    }

    pub fn allowsRemoval(self: *const Controller, account_id: []const u8) bool {
        if (self.state.reachability != .reachable or !self.state.config_path_matches) return true;
        const successful = self.state.last_success orelse return true;
        const mapped = successful.requireMapped(account_id) catch return true;
        if (!self.removal_pause_set or !self.removal_pause_account.eql(account_id)) return false;
        if (self.state.success_revision <= self.removal_pause_revision) return false;
        return mapped.state == .paused and mapped.in_flight == 0;
    }

    pub fn recordRemoval(self: *Controller, account_id: []const u8) void {
        if (!self.removal_pause_set or !self.removal_pause_account.eql(account_id)) return;
        self.removal_pause_set = false;
        self.removal_pause_account = .{};
        self.removal_pause_revision = 0;
    }

    pub fn submitSettings(self: *Controller, draft: ui_model.ProxySettingsDraft, now_unix_s: i64, drivers: Drivers) ui_model.CommandOutcome {
        const node_path: ?[]const u8 = if (draft.node_path.len == 0) null else draft.node_path;
        const document: store.ProxySettingsDocument = .{ .proxy = .{
            .base_url = draft.base_url,
            .cli_path = draft.cli_path,
            .config_path = draft.config_path,
            .node_path = node_path,
        } };
        store.validateProxySettings(document) catch return .rejected_not_allowed;
        self.state.settings = .{
            .base_url = proxy_control.BaseUrl.init(draft.base_url) catch return .rejected_not_allowed,
            .cli_path = if (draft.cli_path.len == 0) null else (runtime_paths.Path.init(draft.cli_path) catch return .rejected_not_allowed),
            .config_path = proxy_control.BoundedText(runtime_paths.max_path_bytes).init(draft.config_path) catch return .rejected_not_allowed,
            .node_path = if (node_path) |value| (runtime_paths.Path.init(value) catch return .rejected_not_allowed) else null,
        };
        self.state.reachability = .unknown;
        self.state.config_path_matches = false;
        self.state.sync_state = .needed;
        self.removal_pause_set = false;
        self.removal_pause_account = .{};
        self.removal_pause_revision = 0;
        self.persistSettings(drivers) catch {
            self.state.last_attempt = .{ .at_unix_s = now_unix_s, .result = .persist_failed };
            return .failed;
        };

        var resolved: runtime_paths.Path = .{};
        self.state.resolved_node = if (self.resolveNode(drivers, &resolved)) resolved else null;
        return .accepted_pending;
    }

    fn resolveNode(self: *const Controller, drivers: Drivers, out: *runtime_paths.Path) bool {
        const home = parentEnvValue(drivers.parent_env, "HOME") orelse "";
        const configured: ?[]const u8 = if (self.state.settings.node_path) |*path|
            path.slice()
        else if (drivers.bundle_node_path.len != 0)
            drivers.bundle_node_path
        else
            null;
        return drivers.node_resolver.resolve(.{
            .configured = configured,
            .home = home,
            .path_variable = parentEnvValue(drivers.parent_env, "PATH") orelse "",
        }, out);
    }

    pub fn submit(
        self: *Controller,
        core: *const coordinator.Coordinator,
        drivers: Drivers,
        kind: app_worker.ProxyJobKind,
        account_id: ?[]const u8,
        now_unix_s: i64,
    ) ui_model.CommandOutcome {
        if (self.busy()) return .rejected_busy;
        var proxy_name: []const u8 = "";
        if (account_id) |id| {
            if (self.state.reachability != .reachable or !self.state.config_path_matches) return .rejected_not_allowed;
            const successful = self.state.last_success orelse return .rejected_not_allowed;
            proxy_name = (successful.requireMapped(id) catch return .rejected_unknown_account).proxy_name.slice();
        }
        if (kind == .sync_config and
            (self.state.reachability != .reachable or !self.state.config_path_matches or self.state.last_success == null))
        {
            return .rejected_not_allowed;
        }

        self.worker.kind = kind;
        self.worker.allocator = drivers.allocator;
        self.worker.exchange = drivers.exchange;
        self.worker.importer = drivers.importer;
        self.worker.base_url = self.state.settings.base_url;
        self.worker.parent_env = drivers.parent_env;
        self.worker.app_root = core.config.layout.root;
        self.worker.cli_path = .{};
        self.worker.timeout_ms = proxy_control.default_timeout_ms;
        self.worker.max_output_bytes = proxy_import.default_max_output_bytes;
        self.worker.proxy_name = proxy_control.BoundedText(proxy_control.max_proxy_name_bytes).init(proxy_name) catch return .rejected_not_allowed;
        var resolved: runtime_paths.Path = .{};
        const node_found = self.resolveNode(drivers, &resolved);
        self.state.resolved_node = if (node_found) resolved else null;
        const home = parentEnvValue(drivers.parent_env, "HOME") orelse "";
        self.worker.config_path = proxy_import.expandConfigPath(self.state.settings.config_path.slice(), home) catch return .rejected_not_allowed;
        if (kind == .sync_config) {
            self.worker.cli_path = if (self.state.settings.cli_path) |path|
                path
            else
                (runtime_paths.Path.init(drivers.bundle_cli_path) catch return .rejected_not_allowed);
            if (!node_found) {
                self.state.sync_state = .failed;
                self.recordFailure(.import_node_missing, now_unix_s, drivers);
                return .failed;
            }
            self.worker.node_path = resolved;
            self.sync_fingerprint = computeFingerprint(core);
        } else {
            self.worker.node_path = .{};
            self.sync_fingerprint = null;
        }
        if (!app_worker.startProxy(drivers.io, &self.worker)) return .rejected_busy;
        if (kind == .pause_account) {
            self.removal_pause_account = proxy_control.BoundedText(account_registry.max_id_bytes).init(account_id.?) catch unreachable;
            self.removal_pause_set = true;
            self.removal_pause_revision = self.state.success_revision;
        }
        self.state.work = switch (kind) {
            .refresh_status => .checking,
            .switch_account => .switching,
            .pause_account => .pausing,
            .reload_account => .reloading,
            .clear_cooldown => .clearing_cooldown,
            .sync_config => .importing,
        };
        return .accepted_pending;
    }

    pub fn project(self: *const Controller, view: *ui_model.ViewState) void {
        var accounts: [account_registry.max_accounts]ui_model.ProxyAccountFact = @splat(.{
            .proxy_name = "",
            .label = "",
            .state = .unknown,
        });
        var token_refresh_failures: [account_registry.max_accounts]bool = @splat(false);
        var count: usize = 0;
        var in_flight: u32 = 0;
        if (self.state.last_success) |*success| {
            in_flight = success.in_flight;
            for (success.accountSlice()) |*account| {
                accounts[count] = .{
                    .app_id = if (account.mapped) account.app_id.slice() else null,
                    .storage_key = if (account.mapped) account.storage_key.slice() else null,
                    .proxy_name = account.proxy_name.slice(),
                    .label = account.label.slice(),
                    .state = uiState(account.state),
                    .cooldown_until_unix_s = account.cooldown_until_unix_s,
                    .token_expires_at_unix_s = account.token_expires_at_unix_s,
                    .in_flight = account.in_flight,
                    .active = account.active,
                    .mapped = account.mapped,
                };
                token_refresh_failures[count] = account.has_token_refresh_last_error;
                count += 1;
            }
        }
        view.applyProxy(.{
            .base_url = self.state.settings.base_url.slice(),
            .cli_path = if (self.state.settings.cli_path) |*path| path.slice() else "",
            .config_path = self.state.settings.config_path.slice(),
            .node_path = if (self.state.settings.node_path) |*path| path.slice() else "",
            .node_resolved = if (self.state.resolved_node) |*path| path.slice() else "",
            .reachability = self.state.reachability,
            .work = self.state.work,
            .sync_state = self.state.sync_state,
            .last_attempt_at_unix_s = if (self.state.last_attempt) |attempt| attempt.at_unix_s else null,
            .last_attempt_result = if (self.state.last_attempt) |attempt| attempt.result else null,
            .last_success_at_unix_s = self.state.last_success_at_unix_s,
            .success_revision = self.state.success_revision,
            .config_path_matches = self.state.config_path_matches,
            .in_flight = in_flight,
            .accounts = accounts[0..count],
            .token_refresh_failures = token_refresh_failures[0..count],
        });
    }

    pub fn drain(self: *Controller, core: *const coordinator.Coordinator, drivers: Drivers, now_unix_s: i64) void {
        if (self.worker.state != .running or !self.worker.done.isSet()) return;
        _ = self.worker.future.await(drivers.io);
        self.worker.started = false;
        self.worker.state = .complete;
        self.applyWorker(core, drivers, now_unix_s);
        app_worker.releaseProxy(&self.worker);
    }

    fn applyWorker(self: *Controller, core: *const coordinator.Coordinator, drivers: Drivers, now_unix_s: i64) void {
        self.state.work = .idle;
        const revision_before = self.state.success_revision;
        defer self.last_completion = .{
            .serial = self.last_completion.serial +| 1,
            .kind = self.worker.kind,
            .ok = switch (self.worker.result) {
                .none, .failure => false,
                .pause, .clear_cooldown => true,
                .status => self.state.success_revision != revision_before,
            },
        };
        switch (self.worker.result) {
            .none => self.recordFailure(.protocol_error, now_unix_s, drivers),
            .failure => |failure| {
                const result: AttemptResult = switch (failure) {
                    .@"unreachable" => .@"unreachable",
                    .timeout => .timeout,
                    .protocol_error => .protocol_error,
                    .incompatible => .incompatible,
                    .action_failed => .action_failed,
                    .import_failed => .import_failed,
                    .import_node_missing => .import_node_missing,
                };
                if (self.worker.kind == .sync_config) {
                    self.state.sync_state = if (result == .action_failed) .needed else .failed;
                }
                self.recordFailure(result, now_unix_s, drivers);
            },
            .pause => |receipt| {
                if (self.state.last_success) |*success| for (success.accounts[0..success.account_count]) |*account| {
                    if (!account.proxy_name.eql(receipt.name.slice())) continue;
                    account.state = .paused;
                    account.in_flight = receipt.in_flight;
                    account.active = false;
                };
                self.state.reachability = .reachable;
                self.state.last_attempt = .{ .at_unix_s = now_unix_s, .result = .ok };
                self.persistStatus(drivers) catch {
                    self.state.last_attempt = .{ .at_unix_s = now_unix_s, .result = .persist_failed };
                };
            },
            .clear_cooldown => |receipt| {
                if (self.state.last_success) |*success| for (success.accounts[0..success.account_count]) |*account| {
                    if (!account.proxy_name.eql(receipt.name.slice())) continue;
                    account.state = receipt.state;
                    account.cooldown_until_unix_s = receipt.cooldown_until_unix_s;
                };
                self.state.reachability = .reachable;
                self.state.last_attempt = .{ .at_unix_s = now_unix_s, .result = .ok };
                self.persistStatus(drivers) catch {
                    self.state.last_attempt = .{ .at_unix_s = now_unix_s, .result = .persist_failed };
                };
            },
            .status => |status| self.applyStatus(core, drivers, status, self.worker.kind, now_unix_s),
        }
    }

    fn applyStatus(
        self: *Controller,
        core: *const coordinator.Coordinator,
        drivers: Drivers,
        status: proxy_control.Status,
        kind: app_worker.ProxyJobKind,
        now_unix_s: i64,
    ) void {
        if (status.version != 2) {
            if (kind == .sync_config) self.state.sync_state = .failed;
            self.recordFailure(.incompatible, now_unix_s, drivers);
            return;
        }
        const home = parentEnvValue(drivers.parent_env, "HOME") orelse {
            self.recordFailure(.config_mismatch, now_unix_s, drivers);
            return;
        };
        var expected_config = proxy_import.expandConfigPath(self.state.settings.config_path.slice(), home) catch {
            self.recordFailure(.config_mismatch, now_unix_s, drivers);
            return;
        };
        if (!status.has_config_path or !expected_config.eqlText(status.config_path.slice())) {
            self.state.reachability = .reachable;
            self.state.config_path_matches = false;
            if (kind == .sync_config) self.state.sync_state = .failed;
            self.recordFailure(.config_mismatch, now_unix_s, drivers);
            return;
        }

        var app_accounts: [account_registry.max_accounts]proxy_control.AppAccount = undefined;
        var count: usize = 0;
        var index: usize = 0;
        while (index < core.accountCount()) : (index += 1) {
            const account = core.accountAt(index) orelse continue;
            app_accounts[count] = .{
                .app_id = account.id,
                .storage_key = account.storage_key,
                .label = account.label,
                .provider = account.provider,
                .enabled = account.enabled,
                .connected = account.auth_state == .connected,
            };
            count += 1;
        }
        const mapped = proxy_control.mapStatus(status, &core.config.layout, app_accounts[0..count]) catch {
            if (kind == .sync_config) self.state.sync_state = .failed;
            self.recordFailure(.mapping_failed, now_unix_s, drivers);
            return;
        };

        if (kind == .switch_account) {
            var switched = false;
            for (mapped.accountSlice()) |account| {
                if (account.proxy_name.eql(self.worker.proxy_name.slice()) and account.active) {
                    switched = true;
                    break;
                }
            }
            if (!switched) {
                self.recordFailure(.action_failed, now_unix_s, drivers);
                return;
            }
        }

        if (kind == .sync_config) {
            const admitted = self.sync_fingerprint orelse {
                self.state.sync_state = .failed;
                self.recordFailure(.mapping_failed, now_unix_s, drivers);
                return;
            };
            const current = computeFingerprint(core);
            if (!admitted.eql(current.slice()) or !mappingMatchesRegistry(core, &mapped)) {
                self.state.sync_state = .failed;
                self.recordFailure(.mapping_failed, now_unix_s, drivers);
                return;
            }
            self.state.settings.last_synced_fingerprint = current;
            self.state.sync_state = .synced;
            self.persistSettings(drivers) catch {
                self.state.sync_state = .failed;
                self.recordFailure(.persist_failed, now_unix_s, drivers);
                return;
            };
        } else if (self.state.settings.last_synced_fingerprint) |fingerprint| {
            const current = computeFingerprint(core);
            self.state.sync_state = if (fingerprint.eql(current.slice()) and mappingMatchesRegistry(core, &mapped)) .synced else .needed;
        } else self.state.sync_state = if (mappingMatchesRegistry(core, &mapped)) .synced else .needed;

        self.state.reachability = .reachable;
        self.state.config_path_matches = true;
        self.state.last_attempt = .{ .at_unix_s = now_unix_s, .result = .ok };
        self.state.last_success_at_unix_s = now_unix_s;
        self.state.last_success = mapped;
        self.state.success_revision +|= 1;
        self.persistStatus(drivers) catch {
            self.state.last_attempt = .{ .at_unix_s = now_unix_s, .result = .persist_failed };
        };
    }

    fn recordFailure(self: *Controller, result: AttemptResult, now_unix_s: i64, drivers: Drivers) void {
        self.state.last_attempt = .{ .at_unix_s = now_unix_s, .result = result };
        switch (result) {
            .@"unreachable", .timeout => self.state.reachability = .@"unreachable",
            .incompatible, .protocol_error, .mapping_failed => self.state.reachability = .incompatible,
            else => {},
        }
        self.persistStatus(drivers) catch {
            self.state.last_attempt = .{ .at_unix_s = now_unix_s, .result = .persist_failed };
        };
    }

    fn persistSettings(self: *const Controller, drivers: Drivers) !void {
        const fingerprint: ?[]const u8 = if (self.state.settings.last_synced_fingerprint) |*value| value.slice() else null;
        const document: store.ProxySettingsDocument = .{
            .proxy = .{
                .base_url = self.state.settings.base_url.slice(),
                .cli_path = if (self.state.settings.cli_path) |*path| path.slice() else "",
                .config_path = self.state.settings.config_path.slice(),
                .node_path = if (self.state.settings.node_path) |*path| path.slice() else null,
            },
            .last_synced_accounts_fingerprint = fingerprint,
        };
        try store.validateProxySettings(document);
        const bytes = try store.encode(drivers.allocator, document);
        defer drivers.allocator.free(bytes);
        try drivers.sink.write(.proxy_settings, bytes);
    }

    fn persistStatus(self: *const Controller, drivers: Drivers) !void {
        var accounts: [account_registry.max_accounts]store.ProxyStoredAccount = undefined;
        var count: usize = 0;
        var cooldown_count: u8 = 0;
        var active_storage_key: ?[]const u8 = null;
        if (self.state.last_success) |*success| for (success.accountSlice()) |*account| {
            if (account.state == .cooldown) cooldown_count += 1;
            if (account.active and account.mapped) active_storage_key = account.storage_key.slice();
            accounts[count] = .{
                .proxy_name = account.proxy_name.slice(),
                .storage_key = if (account.mapped) account.storage_key.slice() else null,
                .label = account.label.slice(),
                .state = storeState(account.state),
                .cooldown_until_unix_s = account.cooldown_until_unix_s,
                .token_expires_at_unix_s = account.token_expires_at_unix_s,
                .token_refresh_last_ok_at_unix_s = account.token_refresh_last_ok_at_unix_s,
                .token_refresh_last_error = if (account.has_token_refresh_last_error) account.token_refresh_last_error.slice() else null,
                .token_refresh_next_attempt_at_unix_s = account.token_refresh_next_attempt_at_unix_s,
                .in_flight = account.in_flight,
                .active = account.active,
            };
            count += 1;
        };
        const last_attempt: ?store.ProxyLastAttempt = if (self.state.last_attempt) |attempt| .{
            .at_unix_s = attempt.at_unix_s,
            .result = storeResult(attempt.result),
        } else null;
        const last_success: ?store.ProxyLastSuccess = if (self.state.last_success) |*success| .{
            .checked_at_unix_s = self.state.last_success_at_unix_s orelse 0,
            .api_version = success.api_version,
            .active_storage_key = active_storage_key,
            .cooldown_count = cooldown_count,
            .accounts = accounts[0..count],
        } else null;
        const document: store.ProxyStatusDocument = .{ .last_attempt = last_attempt, .last_success = last_success };
        try store.validateProxyStatus(document);
        const bytes = try store.encode(drivers.allocator, document);
        defer drivers.allocator.free(bytes);
        try drivers.sink.write(.proxy_status, bytes);
    }

    pub fn shutdown(self: *Controller, io: std.Io) void {
        app_worker.cancelAndJoinProxy(io, &self.worker);
    }

    pub fn load(self: *Controller, core: *const coordinator.Coordinator, allocator: std.mem.Allocator, io: std.Io, dir: std.Io.Dir) void {
        var settings = store.loadProxySettings(allocator, io, dir, runtime_paths.proxy_settings_file_name) catch null;
        if (settings) |*loaded| {
            defer loaded.deinit();
            const value = loaded.value;
            self.state.settings.base_url = proxy_control.BaseUrl.init(value.proxy.base_url) catch self.state.settings.base_url;
            self.state.settings.cli_path = if (value.proxy.cli_path.len == 0)
                null
            else
                (runtime_paths.Path.init(value.proxy.cli_path) catch self.state.settings.cli_path);
            self.state.settings.config_path = proxy_control.BoundedText(runtime_paths.max_path_bytes).init(value.proxy.config_path) catch self.state.settings.config_path;
            self.state.settings.node_path = if (value.proxy.node_path) |path| (runtime_paths.Path.init(path) catch null) else null;
            if (value.last_synced_accounts_fingerprint) |fingerprint| {
                self.state.settings.last_synced_fingerprint = proxy_control.BoundedText(store.max_proxy_fingerprint_bytes).init(fingerprint) catch null;
            }
        }
        var status = store.loadProxyStatus(allocator, io, dir, runtime_paths.proxy_status_file_name) catch null;
        if (status) |*loaded| {
            defer loaded.deinit();
            if (loaded.value.last_attempt) |attempt| self.state.last_attempt = .{
                .at_unix_s = attempt.at_unix_s,
                .result = uiResult(attempt.result),
            };
            if (loaded.value.last_success) |success| {
                var mapped: proxy_control.MappedStatus = .{ .api_version = success.api_version };
                for (success.accounts, 0..) |account, index| {
                    var row: proxy_control.MappedAccount = .{
                        .proxy_name = proxy_control.BoundedText(proxy_control.max_proxy_name_bytes).init(account.proxy_name) catch continue,
                        .label = proxy_control.BoundedText(proxy_control.max_label_bytes).init(account.label) catch continue,
                        .state = clientState(account.state),
                        .cooldown_until_unix_s = account.cooldown_until_unix_s,
                        .token_expires_at_unix_s = account.token_expires_at_unix_s,
                        .token_refresh_last_ok_at_unix_s = account.token_refresh_last_ok_at_unix_s,
                        .token_refresh_last_error = if (account.token_refresh_last_error) |value|
                            (proxy_control.BoundedText(proxy_control.max_refresh_error_kind_bytes).init(value) catch .{})
                        else
                            .{},
                        .has_token_refresh_last_error = account.token_refresh_last_error != null,
                        .token_refresh_next_attempt_at_unix_s = account.token_refresh_next_attempt_at_unix_s,
                        .in_flight = account.in_flight,
                        .active = account.active,
                    };
                    if (account.storage_key) |key| {
                        var core_index: usize = 0;
                        while (core_index < core.accountCount()) : (core_index += 1) {
                            const current = core.accountAt(core_index) orelse continue;
                            if (!std.mem.eql(u8, current.storage_key, key)) continue;
                            row.storage_key = proxy_control.BoundedText(account_registry.max_storage_key_bytes).init(key) catch break;
                            row.app_id = proxy_control.BoundedText(account_registry.max_id_bytes).init(current.id) catch break;
                            row.mapped = true;
                            break;
                        }
                    }
                    mapped.accounts[mapped.account_count] = row;
                    mapped.account_count += 1;
                    mapped.in_flight += account.in_flight;
                    if (account.active) mapped.active_index = index;
                }
                self.state.last_success = mapped;
                self.state.last_success_at_unix_s = success.checked_at_unix_s;
            }
        }
        self.state.reachability = .unknown;
        self.state.config_path_matches = false;
        self.state.sync_state = if (self.state.settings.last_synced_fingerprint == null) .unknown else .needed;
    }
};

fn computeFingerprint(core: *const coordinator.Coordinator) proxy_control.BoundedText(store.max_proxy_fingerprint_bytes) {
    var hasher = std.crypto.hash.sha2.Sha256.init(.{});
    var index: usize = 0;
    while (index < core.accountCount()) : (index += 1) {
        const account = core.accountAt(index) orelse continue;
        if (account.provider != .codex or !account.enabled or account.auth_state != .connected) continue;
        hasher.update(account.storage_key);
        hasher.update(&.{0});
        hasher.update(account.label);
        hasher.update(&.{0xff});
    }
    var digest: [std.crypto.hash.sha2.Sha256.digest_length]u8 = undefined;
    hasher.final(&digest);
    var hex: [std.crypto.hash.sha2.Sha256.digest_length * 2]u8 = undefined;
    const alphabet = "0123456789abcdef";
    for (digest, 0..) |byte, offset| {
        hex[offset * 2] = alphabet[byte >> 4];
        hex[offset * 2 + 1] = alphabet[byte & 0x0f];
    }
    return proxy_control.BoundedText(store.max_proxy_fingerprint_bytes).init(&hex) catch unreachable;
}

fn mappingMatchesRegistry(core: *const coordinator.Coordinator, mapped: *const proxy_control.MappedStatus) bool {
    var mapped_index: usize = 0;
    var account_index: usize = 0;
    while (account_index < core.accountCount()) : (account_index += 1) {
        const account = core.accountAt(account_index) orelse continue;
        if (account.provider != .codex or !account.enabled or account.auth_state != .connected) continue;
        const row = mapped.accountAt(mapped_index) orelse return false;
        if (!row.mapped or !row.storage_key.eql(account.storage_key)) return false;
        mapped_index += 1;
    }
    return mapped_index == mapped.accountCount();
}

fn parentEnvValue(parent: transport.ParentEnv, name: []const u8) ?[]const u8 {
    return switch (parent) {
        .pairs => |pairs| blk: {
            for (pairs) |pair| if (std.mem.eql(u8, pair.name, name)) break :blk pair.value;
            break :blk null;
        },
        .map => |map| map.get(name),
    };
}

fn uiState(state: proxy_control.AccountState) ui_model.ProxyAccountState {
    return switch (state) {
        .ready => .ready,
        .cooldown => .cooldown,
        .paused => .paused,
        .invalid => .invalid,
        .refreshing => .refreshing,
    };
}

fn storeState(state: proxy_control.AccountState) store.ProxyStoredState {
    return switch (state) {
        .ready => .ready,
        .cooldown => .cooldown,
        .paused => .paused,
        .invalid => .invalid,
        .refreshing => .refreshing,
    };
}

fn clientState(state: store.ProxyStoredState) proxy_control.AccountState {
    return switch (state) {
        .ready => .ready,
        .cooldown => .cooldown,
        .paused => .paused,
        .invalid, .unknown => .invalid,
        .refreshing => .refreshing,
    };
}

fn storeResult(result: AttemptResult) store.ProxyAttemptResult {
    return @enumFromInt(@intFromEnum(result));
}

fn uiResult(result: store.ProxyAttemptResult) AttemptResult {
    return @enumFromInt(@intFromEnum(result));
}
