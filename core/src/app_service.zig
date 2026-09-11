const std = @import("std");

const account_registry = @import("account_registry.zig");
const app_reset_service = @import("app_reset_service.zig");
const app_proxy_service = @import("app_proxy_service.zig");
const app_worker = @import("app_worker.zig");
const coordinator = @import("coordinator.zig");
const domain = @import("domain.zig");
const keychain = @import("keychain.zig");
const login_runtime = @import("login_runtime.zig");
const proxy_control = @import("proxy_control_client.zig");
const proxy_import = @import("proxy_import_runner.zig");
const proxy_service_manager = @import("proxy_service_manager.zig");
const runtime_paths = @import("runtime_paths.zig");
const store = @import("store.zig");
const transport = @import("process_jsonl.zig");
const ui_model = @import("ui_model.zig");
const codex = @import("providers/codex.zig");

pub const max_workers = app_worker.max_workers;
pub const login_scan_bytes = app_worker.login_scan_bytes;

pub const public_code_service_unavailable = "service-unavailable";
pub const public_code_worker_unavailable = "worker-unavailable";
pub const public_code_directory_unavailable = "account-home-unavailable";
pub const public_code_executable_missing = "provider-cli-missing";
pub const public_code_key_unavailable = "reset-key-unavailable";

const private_auth_file_permissions = std.Io.File.Permissions.fromMode(0o600);

pub const public_codes = [_][]const u8{
    public_code_service_unavailable,
    public_code_worker_unavailable,
    public_code_directory_unavailable,
    public_code_executable_missing,
    public_code_key_unavailable,
};

pub fn isPublicCode(code: []const u8) bool {
    for (public_codes) |known| {
        if (std.mem.eql(u8, code, known)) return true;
    }
    return coordinator.isPublicCode(code);
}

const runtime_adapters = @import("app_runtime_adapters.zig");

pub const generated_hex_digits = runtime_adapters.generated_hex_digits;
pub const idempotency_key_prefix = runtime_adapters.idempotency_key_prefix;
pub const max_generated_key_bytes = runtime_adapters.max_generated_key_bytes;
pub const max_executable_bytes = runtime_adapters.max_executable_bytes;
pub const private_dir_permissions = runtime_adapters.private_dir_permissions;
pub const ExecutablePath = runtime_adapters.ExecutablePath;
pub const DirectoryError = runtime_adapters.DirectoryError;
pub const Directories = runtime_adapters.Directories;
pub const FileDirectories = runtime_adapters.FileDirectories;
pub const KeySource = runtime_adapters.KeySource;
pub const RandomKeySource = runtime_adapters.RandomKeySource;
pub const LaunchError = runtime_adapters.LaunchError;
pub const CodexChannel = runtime_adapters.CodexChannel;
pub const CodexLauncher = runtime_adapters.CodexLauncher;
pub const ChildCodexLauncher = runtime_adapters.ChildCodexLauncher;
pub const LoginChannel = runtime_adapters.LoginChannel;
pub const LoginLauncher = runtime_adapters.LoginLauncher;
pub const ProcessLoginLauncher = runtime_adapters.ProcessLoginLauncher;

pub fn resolveExecutable(
    io: std.Io,
    path_variable: []const u8,
    name: []const u8,
    out: *ExecutablePath,
) bool {
    return runtime_adapters.resolveExecutable(io, path_variable, name, out);
}

pub fn resolveProviderExecutable(
    io: std.Io,
    path_variable: []const u8,
    home: []const u8,
    name: []const u8,
    out: *ExecutablePath,
) bool {
    return runtime_adapters.resolveProviderExecutable(io, path_variable, home, name, out);
}

pub fn unwiredDirectories() Directories {
    return runtime_adapters.unwiredDirectories();
}

pub fn unwiredKeySource() KeySource {
    return runtime_adapters.unwiredKeySource();
}

pub fn unwiredCodexLauncher() CodexLauncher {
    return runtime_adapters.unwiredCodexLauncher();
}

pub fn unwiredLoginLauncher() LoginLauncher {
    return runtime_adapters.unwiredLoginLauncher();
}

pub const Live = struct {
    io: std.Io,
    allocator: std.mem.Allocator,

    sink: coordinator.DocumentSink = coordinator.unwiredDocumentSink(),

    credentials: keychain.CredentialStore,
    codex_launcher: CodexLauncher = unwiredCodexLauncher(),
    codex_cli_too_old: bool = false,
    login_launcher: LoginLauncher = unwiredLoginLauncher(),
    directories: Directories = unwiredDirectories(),
    keys: KeySource = unwiredKeySource(),

    parent_env: transport.ParentEnv = .{ .pairs = &.{} },

    proxy_exchange: proxy_control.Exchange = proxy_control.unwiredExchange(),
    proxy_importer: proxy_import.Runner = proxy_import.unwiredRunner(),

    proxy_node_resolver: proxy_import.NodeResolver = proxy_import.unwiredNodeResolver(),

    proxy_service: ?proxy_service_manager.Live = null,
    codex_client: codex.ClientInfo = .{},
    codex_timeouts: CodexTimeouts = .{},
    login_options: LoginOptions = .{},
};

pub const CodexTimeouts = struct {
    startup_ms: u32 = transport.default_startup_timeout_ms,
    request_ms: u32 = transport.default_request_timeout_ms,
};

pub const LoginOptions = app_worker.LoginOptions;

const JobKind = app_worker.JobKind;
const Worker = app_worker.Worker;
pub const ProxyReachability = app_proxy_service.Reachability;
pub const ProxyAttemptResult = app_proxy_service.AttemptResult;
pub const ProxySyncState = app_proxy_service.SyncState;
pub const ProxyRuntimeState = app_proxy_service.State;

const ResetService = app_reset_service.ResetService;

pub const Activity = struct {
    refreshes_started: usize = 0,
    logins_started: usize = 0,
    imports_attempted: usize = 0,
    resets_started: usize = 0,
    consumes_sent: usize = 0,

    last_reset_outcome: ?domain.ResetOutcome = null,
    last_code: ?[]const u8 = null,
};

const ResetProxyClearRecord = struct {
    account_id: proxy_control.BoundedText(account_registry.max_id_bytes) = .{},
    state: ui_model.ResetProxyClear = .none,

    submitted_serial: u64 = 0,
    awaiting: bool = false,
};

const UsageRefreshFlow = struct {
    const Stage = enum { idle, provider, status, sync, verify };

    stage: Stage = .idle,
    awaiting: bool = false,
    submitted_serial: u64 = 0,
    successful_accounts: [account_registry.max_accounts]proxy_control.BoundedText(account_registry.max_id_bytes) = @splat(.{}),
    successful_count: usize = 0,

    fn active(self: UsageRefreshFlow) bool {
        return self.stage != .idle;
    }
};

const CooldownReconcileRecord = struct {
    account_id: proxy_control.BoundedText(account_registry.max_id_bytes) = .{},
    occupied: bool = false,
    cooldown_until_unix_s: ?i64 = null,
    attempted: bool = false,
    queued: bool = false,
};

const PendingLogin = struct {
    active: bool = false,
    session: coordinator.LoginSession = undefined,
    purpose: coordinator.LoginPurpose = .initial,
};

pub const Service = struct {
    allocator: std.mem.Allocator,
    core: *coordinator.Coordinator,

    live: ?Live = null,

    sink_target: ?coordinator.DocumentSink = null,
    inactive_registry: ?[]u8 = null,
    inactive_snapshots: ?[]u8 = null,
    inactive_account_count: usize = 0,
    workers: [max_workers]Worker = @splat(.{}),
    proxy: app_proxy_service.Controller = .{},
    proxy_service: proxy_service_manager.Controller = .{},
    pending_logins: [max_workers]PendingLogin = @splat(.{}),
    reset: ResetService = .{},
    reset_proxy_clear: ResetProxyClearRecord = .{},
    usage_refresh: UsageRefreshFlow = .{},
    cooldown_reconciliations: [account_registry.max_accounts]CooldownReconcileRecord = @splat(.{}),
    activity: Activity = .{},
    appearance: ui_model.Appearance = .system,
    codex_usage_window: ui_model.CodexUsageWindow = .auto,
    codex_show_model_limits: bool = false,
    launch_at_login: bool = false,
    launch_at_login_registration_failed: bool = false,
    auto_refresh_minutes: u16 = 0,
    last_successful_refresh_at_unix_s: ?i64 = null,

    last_auto_refresh_attempt_at_unix_s: ?i64 = null,

    now_unix_s: i64 = 0,

    pub fn create(allocator: std.mem.Allocator, core: *coordinator.Coordinator) error{OutOfMemory}!*Service {
        const self = try allocator.create(Service);
        self.* = .{ .allocator = allocator, .core = core };
        for (&self.workers, 0..) |*worker, index| worker.index = index;
        return self;
    }

    pub fn destroy(self: *Service) void {
        self.shutdown();
        self.clearInactiveDocuments();
        self.allocator.destroy(self);
    }

    pub fn attach(self: *Service, live: Live) void {
        self.sink_target = live.sink;
        var wired = live;
        wired.sink = self.preservingSink();
        self.live = wired;
    }

    const preserving_sink_vtable: coordinator.DocumentSink.VTable = .{ .write = preservingWrite };

    fn preservingSink(self: *Service) coordinator.DocumentSink {
        return .{ .context = self, .vtable = &preserving_sink_vtable };
    }

    fn preservingWrite(
        context: *anyopaque,
        kind: runtime_paths.DocumentKind,
        bytes: []const u8,
    ) coordinator.SinkError!void {
        const self: *Service = @ptrCast(@alignCast(context));
        const target = self.sink_target orelse return error.Unavailable;
        const merged = switch (kind) {
            .registry => try self.mergeRegistry(bytes),
            .snapshots => try self.mergeSnapshots(bytes),
            else => return target.write(kind, bytes),
        };
        defer self.allocator.free(merged);
        if (merged.len > store.max_document_bytes) return error.TooLarge;
        return target.write(kind, merged);
    }

    fn mergeRegistry(self: *Service, active_bytes: []const u8) coordinator.SinkError![]u8 {
        const inactive_bytes = self.inactive_registry orelse
            return self.allocator.dupe(u8, active_bytes) catch error.TooLarge;
        var active = std.json.parseFromSlice(
            account_registry.RegistryDocument,
            self.allocator,
            active_bytes,
            .{ .allocate = .alloc_always },
        ) catch return error.Denied;
        defer active.deinit();
        var inactive = std.json.parseFromSlice(
            account_registry.RegistryDocument,
            self.allocator,
            inactive_bytes,
            .{ .allocate = .alloc_always },
        ) catch return error.Denied;
        defer inactive.deinit();
        const total = active.value.accounts.len + inactive.value.accounts.len;
        if (total > account_registry.max_accounts) return error.Denied;
        var accounts: [account_registry.max_accounts]account_registry.Account = undefined;
        @memcpy(accounts[0..active.value.accounts.len], active.value.accounts);
        @memcpy(accounts[active.value.accounts.len..total], inactive.value.accounts);
        const document: account_registry.RegistryDocument = .{
            .schema_version = active.value.schema_version,
            .accounts = accounts[0..total],
        };
        account_registry.validateDocument(document) catch return error.Denied;
        return store.encode(self.allocator, document) catch error.TooLarge;
    }

    fn mergeSnapshots(self: *Service, active_bytes: []const u8) coordinator.SinkError![]u8 {
        const inactive_bytes = self.inactive_snapshots orelse
            return self.allocator.dupe(u8, active_bytes) catch error.TooLarge;
        var active = store.decodeSnapshots(self.allocator, active_bytes) catch return error.Denied;
        defer active.deinit();
        var inactive = store.decodeSnapshots(self.allocator, inactive_bytes) catch return error.Denied;
        defer inactive.deinit();
        const profile_total = active.value.profiles.len + inactive.value.profiles.len;
        const snapshot_total = active.value.snapshots.len + inactive.value.snapshots.len;
        if (profile_total > account_registry.max_accounts or snapshot_total > account_registry.max_accounts) return error.Denied;
        var profiles: [account_registry.max_accounts]domain.AccountProfile = undefined;
        var snapshots: [account_registry.max_accounts]domain.UsageSnapshot = undefined;
        @memcpy(profiles[0..active.value.profiles.len], active.value.profiles);
        @memcpy(profiles[active.value.profiles.len..profile_total], inactive.value.profiles);
        @memcpy(snapshots[0..active.value.snapshots.len], active.value.snapshots);
        @memcpy(snapshots[active.value.snapshots.len..snapshot_total], inactive.value.snapshots);
        const document: store.SnapshotDocument = .{
            .schema_version = active.value.schema_version,
            .profiles = profiles[0..profile_total],
            .snapshots = snapshots[0..snapshot_total],
        };
        store.validateSnapshotDocument(document) catch return error.Denied;
        return store.encode(self.allocator, document) catch error.TooLarge;
    }

    fn clearInactiveDocuments(self: *Service) void {
        if (self.inactive_registry) |bytes| self.allocator.free(bytes);
        if (self.inactive_snapshots) |bytes| self.allocator.free(bytes);
        self.inactive_registry = null;
        self.inactive_snapshots = null;
        self.inactive_account_count = 0;
    }

    fn captureInactiveDocuments(self: *Service, io: std.Io, dir: std.Io.Dir) void {
        self.clearInactiveDocuments();
        if (dir.readFileAlloc(
            io,
            runtime_paths.registry_file_name,
            self.allocator,
            .limited(store.max_document_bytes),
        )) |bytes| {
            defer self.allocator.free(bytes);
            self.inactive_registry = self.filterInactiveRegistry(bytes) catch null;
        } else |_| {}
        if (dir.readFileAlloc(
            io,
            runtime_paths.snapshots_file_name,
            self.allocator,
            .limited(store.max_document_bytes),
        )) |bytes| {
            defer self.allocator.free(bytes);
            self.inactive_snapshots = self.filterInactiveSnapshots(bytes) catch null;
        } else |_| {}
    }

    fn filterInactiveRegistry(self: *Service, bytes: []const u8) ![]u8 {
        var parsed = try std.json.parseFromSlice(
            account_registry.RegistryDocument,
            self.allocator,
            bytes,
            .{ .allocate = .alloc_always },
        );
        defer parsed.deinit();
        try account_registry.validateDocument(parsed.value);
        var accounts: [account_registry.max_accounts]account_registry.Account = undefined;
        var count: usize = 0;
        for (parsed.value.accounts) |account| {
            if (account.provider != .claude) continue;
            accounts[count] = account;
            count += 1;
        }
        self.inactive_account_count = count;
        if (count == 0) return error.NoInactiveAccounts;
        return store.encode(self.allocator, account_registry.RegistryDocument{
            .schema_version = parsed.value.schema_version,
            .accounts = accounts[0..count],
        });
    }

    fn filterInactiveSnapshots(self: *Service, bytes: []const u8) ![]u8 {
        var parsed = try store.decodeSnapshots(self.allocator, bytes);
        defer parsed.deinit();
        var profiles: [account_registry.max_accounts]domain.AccountProfile = undefined;
        var snapshots: [account_registry.max_accounts]domain.UsageSnapshot = undefined;
        var profile_count: usize = 0;
        var snapshot_count: usize = 0;
        for (parsed.value.profiles) |profile| {
            if (profile.provider != .claude) continue;
            profiles[profile_count] = profile;
            profile_count += 1;
        }
        for (parsed.value.snapshots) |snapshot| {
            if (snapshot.provider != .claude) continue;
            snapshots[snapshot_count] = snapshot;
            snapshot_count += 1;
        }
        if (profile_count == 0 and snapshot_count == 0) return error.NoInactiveSnapshots;
        return store.encode(self.allocator, store.SnapshotDocument{
            .schema_version = parsed.value.schema_version,
            .profiles = profiles[0..profile_count],
            .snapshots = snapshots[0..snapshot_count],
        });
    }

    pub fn isAttached(self: *const Service) bool {
        return self.live != null;
    }

    pub fn port(self: *Service) ui_model.ServicePort {
        return .{
            .context = self,
            .capabilities_fn = capabilitiesFn,
            .project_fn = projectFn,
            .submit_fn = submitFn,
            .add_account_labeled_fn = addAccountLabeledFn,
            .pump_fn = pumpFn,
        };
    }

    pub fn capabilities(self: *const Service) ui_model.ServiceCapabilities {
        const live = self.live orelse return .{ .connected = true };
        return .{
            .connected = true,

            .refresh = true,
            .accounts = true,
            .reset = live.keys.vtable != unwiredKeySource().vtable,
            .proxy_control = true,
        };
    }

    fn capabilitiesFn(context: *anyopaque) ui_model.ServiceCapabilities {
        const self: *Service = @ptrCast(@alignCast(context));
        return self.capabilities();
    }

    fn projectFn(context: *anyopaque, view: *ui_model.ViewState) void {
        const self: *Service = @ptrCast(@alignCast(context));
        self.project(view);
    }

    pub fn project(self: *Service, view: *ui_model.ViewState) void {
        const now = view.now_unix_s;
        self.now_unix_s = now;
        view.applyAppearance(self.appearance);
        view.applyCodexSettings(self.codex_usage_window, self.codex_show_model_limits);
        view.applyLaunchAtLogin(self.launch_at_login, self.launch_at_login_registration_failed);
        view.applyAutoRefresh(self.auto_refresh_minutes, self.autoRefreshAccountCount());
        var index: usize = 0;
        while (index < self.core.accountCount()) : (index += 1) {
            const row = self.core.rowAt(index, now) orelse continue;
            if (row.provider != .codex) continue;
            const status = self.core.statusAt(index) orelse continue;
            const pending = self.core.pendingAttemptFor(row.account_id) != null;
            const unsent = !pending and self.core.unsentAttemptFor(row.account_id) != null;
            const slot = view.pushAccount(.{
                .account_id = row.account_id,
                .label = row.label,
                .provider_email = row.provider_email,
                .plan_label = row.plan_label,
                .provider = row.provider,
                .enabled = row.enabled,
                .auth_state = row.auth_state,
                .freshness = row.freshness,
                .snapshot_status = row.snapshot_status,
                .has_snapshot = status.has_snapshot,
                .snapshot_captured_at_unix_s = row.snapshot_captured_at_unix_s,
                .last_attempt_at_unix_s = row.last_attempt_at_unix_s,
                .last_success_at_unix_s = row.last_success_at_unix_s,
                .last_attempt_code = row.last_attempt_code,
                .reset_credit_count = row.reset_credit_count,
                .credit_detail_status = row.credit_detail_status,
                .credit_detail_count = creditDetailCount(self.core, index),
                .operation_in_flight = row.operation_in_flight,
                .queued = row.queued,
                .pending_reset_attempt = pending,
                .unsent_reset_attempt = unsent,
                .reset_proxy_clear = self.resetProxyClearFor(row.account_id),
            }) catch return;
            const snapshot = self.core.snapshotAt(index) orelse continue;
            for (snapshot.windows) |window| {
                view.pushWindow(slot, window) catch break;
            }
        }
        self.projectProxy(view);
    }

    fn pumpFn(context: *anyopaque, now_unix_s: i64) void {
        const self: *Service = @ptrCast(@alignCast(context));
        self.pump(now_unix_s);
    }

    fn submitFn(context: *anyopaque, command: ui_model.Command) ui_model.CommandOutcome {
        const self: *Service = @ptrCast(@alignCast(context));
        return self.submit(command);
    }

    pub fn submit(self: *Service, command: ui_model.Command) ui_model.CommandOutcome {
        return switch (command) {
            .set_appearance => |appearance| self.submitAppearance(appearance),
            .set_codex_usage_window => |window| self.submitCodexUsageWindow(window),
            .set_codex_show_model_limits => |on| self.submitCodexShowModelLimits(on),
            .set_launch_at_login => |on| self.submitLaunchAtLogin(on),
            .report_launch_at_login_registration_failure => |failed| self.submitLaunchAtLoginRegistrationFailure(failed),
            .set_auto_refresh => |minutes| self.submitAutoRefresh(minutes),
            .refresh_all => self.submitRefreshAll(),
            .refresh_account => |account_id| self.submitRefresh(account_id),
            .add_account => |provider| self.submitAddAccount(provider, null),
            .reauthenticate => |account_id| self.submitReauthenticate(account_id),
            .relabel => |request| self.submitRelabel(request),
            .move_account => |request| self.submitMoveAccount(request),
            .remove_account => |account_id| self.submitRemoveAccount(account_id),
            .redeem_reset => |request| self.submitRedeemReset(request),
            .retry_reset => |account_id| self.submitRetryReset(account_id),
            .proxy_refresh_status => self.startProxy(.refresh_status, null),
            .proxy_switch_account => |account_id| self.startProxy(.switch_account, account_id),
            .proxy_pause_account => |account_id| self.startProxy(.pause_account, account_id),
            .proxy_reload_account => |account_id| self.startProxy(.reload_account, account_id),
            .proxy_clear_cooldown => |account_id| self.startProxy(.clear_cooldown, account_id),
            .proxy_sync_config => self.startProxy(.sync_config, null),
            .save_proxy_settings => |draft| self.submitProxySettings(draft),
            .install_proxy_service => self.startProxyService(.install, false),
            .repair_proxy_service => self.startProxyService(.repair, false),
            .stop_proxy_service => self.startProxyService(.stop, false),
            .set_proxy_enabled => |on| self.startProxyService(if (on) .set_enabled_on else .set_enabled_off, false),
            .enable_codex_routing => |replace| self.startProxyService(.enable_routing, replace),
            .disable_codex_routing => self.startProxyService(.disable_routing, false),
        };
    }

    fn submitAppearance(self: *Service, appearance: ui_model.Appearance) ui_model.CommandOutcome {
        const document = self.appSettingsDocument();
        var updated = document;
        updated.appearance = appearance;
        if (!self.persistAppSettings(updated)) return if (self.live == null) .service_unavailable else .failed;
        self.appearance = appearance;
        return .accepted_pending;
    }

    fn submitCodexUsageWindow(self: *Service, window: ui_model.CodexUsageWindow) ui_model.CommandOutcome {
        var updated = self.appSettingsDocument();
        updated.codex_usage_window = window;
        if (!self.persistAppSettings(updated)) return if (self.live == null) .service_unavailable else .failed;
        self.codex_usage_window = window;
        return .accepted_pending;
    }

    fn submitCodexShowModelLimits(self: *Service, on: bool) ui_model.CommandOutcome {
        var updated = self.appSettingsDocument();
        updated.codex_show_model_limits = on;
        if (!self.persistAppSettings(updated)) return if (self.live == null) .service_unavailable else .failed;
        self.codex_show_model_limits = on;
        return .accepted_pending;
    }

    fn submitLaunchAtLogin(self: *Service, on: bool) ui_model.CommandOutcome {
        var updated = self.appSettingsDocument();
        updated.launch_at_login = on;

        updated.launch_at_login_registration_failed = false;
        if (!self.persistAppSettings(updated)) return if (self.live == null) .service_unavailable else .failed;
        self.launch_at_login = on;
        self.launch_at_login_registration_failed = false;
        return .accepted_pending;
    }

    fn submitLaunchAtLoginRegistrationFailure(self: *Service, failed: bool) ui_model.CommandOutcome {
        var updated = self.appSettingsDocument();
        updated.launch_at_login_registration_failed = failed;
        if (!self.persistAppSettings(updated)) return if (self.live == null) .service_unavailable else .failed;
        self.launch_at_login_registration_failed = failed;
        return .accepted_pending;
    }

    fn submitAutoRefresh(self: *Service, minutes: u16) ui_model.CommandOutcome {
        if (!store.validAutoRefreshMinutes(minutes)) return .rejected_not_allowed;
        var updated = self.appSettingsDocument();
        updated.auto_refresh_minutes = minutes;
        if (!self.persistAppSettings(updated)) return if (self.live == null) .service_unavailable else .failed;
        self.auto_refresh_minutes = minutes;
        self.last_auto_refresh_attempt_at_unix_s = null;
        return .accepted_pending;
    }

    fn appSettingsDocument(self: *const Service) store.AppSettingsDocument {
        return .{
            .appearance = self.appearance,
            .codex_usage_window = self.codex_usage_window,
            .codex_show_model_limits = self.codex_show_model_limits,
            .launch_at_login = self.launch_at_login,
            .launch_at_login_registration_failed = self.launch_at_login_registration_failed,
            .auto_refresh_minutes = self.auto_refresh_minutes,
            .last_successful_refresh_at_unix_s = self.last_successful_refresh_at_unix_s,
        };
    }

    fn persistAppSettings(self: *Service, document: store.AppSettingsDocument) bool {
        const live = self.live orelse return false;
        store.validateAppSettings(document) catch return false;
        const bytes = store.encode(self.allocator, document) catch return false;
        defer self.allocator.free(bytes);
        live.sink.write(.app_settings, bytes) catch return false;
        return true;
    }

    pub fn proxyState(self: *const Service) *const ProxyRuntimeState {
        return self.proxy.statePtr();
    }

    pub fn proxyWorkerBusy(self: *const Service) bool {
        return self.proxy.busy();
    }

    fn submitProxySettings(self: *Service, draft: ui_model.ProxySettingsDraft) ui_model.CommandOutcome {
        const live = self.live orelse return .service_unavailable;
        const outcome = self.proxy.submitSettings(draft, self.now_unix_s, proxyDrivers(live));
        if (outcome == .accepted_pending) self.proxy_service.markSettingsChanged();
        return outcome;
    }

    fn startProxy(self: *Service, kind: app_worker.ProxyJobKind, account_id: ?[]const u8) ui_model.CommandOutcome {
        const live = self.live orelse return .service_unavailable;
        if (account_id) |id| {
            const account = self.core.account(id) orelse return .rejected_unknown_account;
            if (account.provider != .codex) return .rejected_not_allowed;
        }
        return self.proxy.submit(self.core, proxyDrivers(live), kind, account_id, self.now_unix_s);
    }

    fn scheduleProxySyncAfterRegistryChange(self: *Service) void {
        self.proxy.recordRegistryChange();
        if (self.proxy.state.last_success) |status| {
            if (status.in_flight != 0) return;
        }
        _ = self.startProxy(.sync_config, null);
    }

    fn projectProxy(self: *Service, view: *ui_model.ViewState) void {
        self.proxy.project(view);
        const live = self.live orelse return;
        const service_live = live.proxy_service orelse return;
        self.proxy_service.project(view, self.hasEligibleCodexAccount(), &service_live.paths);
    }

    fn startProxyService(self: *Service, kind: proxy_service_manager.JobKind, replace_conflicting: bool) ui_model.CommandOutcome {
        const live = self.live orelse return .service_unavailable;
        const service_live = self.currentProxyServiceLive(live) orelse return .rejected_not_allowed;
        return self.proxy_service.submit(kind, replace_conflicting, self.hasEligibleCodexAccount(), service_live);
    }

    fn currentProxyServiceLive(self: *const Service, live: Live) ?proxy_service_manager.Live {
        var lifecycle = live.proxy_service orelse return null;
        const home = parentEnvironmentValue(live.parent_env, "HOME") orelse return null;
        lifecycle.paths.config_path = proxy_import.expandConfigPath(self.proxy.state.settings.config_path.slice(), home) catch return null;
        lifecycle.control_base_url = self.proxy.state.settings.base_url.slice();
        lifecycle.import_cli_path = if (self.proxy.state.settings.cli_path) |*path| path.slice() else "";
        lifecycle.import_node_path = if (self.proxy.state.settings.node_path) |*path| path.slice() else "";
        return lifecycle;
    }

    fn hasEligibleCodexAccount(self: *const Service) bool {
        var index: usize = 0;
        while (index < self.core.accountCount()) : (index += 1) {
            const account = self.core.accountAt(index) orelse continue;
            if (account.provider == .codex and account.enabled and account.auth_state == .connected) return true;
        }
        return false;
    }

    pub fn discoverProxyService(self: *Service, live: proxy_service_manager.Live) void {
        self.proxy_service.refresh(live);
    }

    pub fn proxyServiceWorkerBusy(self: *const Service) bool {
        return self.proxy_service.busy();
    }

    fn submitRefreshAll(self: *Service) ui_model.CommandOutcome {
        if (self.live == null) return .service_unavailable;
        if (self.usage_refresh.active()) return .rejected_busy;
        const plan = self.core.requestRefreshAllForProvider(.codex);
        if (plan.queued == 0 and plan.already_pending == 0) return .rejected_not_allowed;
        self.usage_refresh = .{ .stage = .provider };
        self.startQueued(self.now_unix_s);
        return .accepted_pending;
    }

    fn submitRefresh(self: *Service, account_id: []const u8) ui_model.CommandOutcome {
        if (self.live == null) return .service_unavailable;
        if (self.usage_refresh.active()) return .rejected_busy;
        const account = self.core.account(account_id) orelse return .rejected_unknown_account;
        if (account.provider != .codex) return .rejected_not_allowed;
        _ = self.core.requestRefresh(account_id) catch |err| return switch (err) {
            error.UnknownAccount => .rejected_unknown_account,
            error.AccountDisabled => .rejected_not_allowed,
            error.AccountBusy, error.ConcurrencyLimit => .rejected_busy,
        };
        self.usage_refresh = .{ .stage = .provider };
        self.startQueued(self.now_unix_s);
        return .accepted_pending;
    }

    fn rememberRefreshSuccess(self: *Service, account_id: []const u8) void {
        for (self.usage_refresh.successful_accounts[0..self.usage_refresh.successful_count]) |*id| {
            if (id.eql(account_id)) return;
        }
        if (self.usage_refresh.successful_count == self.usage_refresh.successful_accounts.len) return;
        self.usage_refresh.successful_accounts[self.usage_refresh.successful_count] =
            proxy_control.BoundedText(account_registry.max_id_bytes).init(account_id) catch return;
        self.usage_refresh.successful_count += 1;
    }

    fn finishUsageRefresh(self: *Service) void {
        for (self.usage_refresh.successful_accounts[0..self.usage_refresh.successful_count]) |*id| {
            self.observeFreshUsageForCooldown(id.slice(), self.now_unix_s);
        }
        if (self.usage_refresh.successful_count != 0) {
            self.last_successful_refresh_at_unix_s = self.now_unix_s;
            const document = self.appSettingsDocument();
            if (!self.persistAppSettings(document)) self.recordCode(coordinator.public_code_persist_failed);
        }
        self.usage_refresh = .{};
    }

    fn advanceUsageRefresh(self: *Service) void {
        if (!self.usage_refresh.active()) return;
        if (self.usage_refresh.stage == .provider) {
            if (!self.core.schedulerIsIdle() or self.busyWorkerCount() != 0) return;
            self.usage_refresh.stage = .status;
        }

        if (self.usage_refresh.awaiting) {
            const completion = self.proxy.lastCompletion();
            if (completion.serial == self.usage_refresh.submitted_serial) return;
            self.usage_refresh.awaiting = false;
            switch (self.usage_refresh.stage) {
                .status => {
                    if (!completion.ok) return self.finishUsageRefresh();
                    if (self.proxy.state.sync_state == .needed) {
                        self.usage_refresh.stage = .sync;
                    } else return self.finishUsageRefresh();
                },
                .sync => {
                    if (!completion.ok or self.proxy.state.sync_state != .synced) return self.finishUsageRefresh();
                    self.usage_refresh.stage = .verify;
                },
                .verify => return self.finishUsageRefresh(),
                .idle, .provider => unreachable,
            }
        }

        if (self.proxy.busy()) return;
        const kind: app_worker.ProxyJobKind = switch (self.usage_refresh.stage) {
            .status, .verify => .refresh_status,
            .sync => .sync_config,
            .idle, .provider => return,
        };
        const submitted_serial = self.proxy.lastCompletion().serial;
        if (self.startProxy(kind, null) == .accepted_pending) {
            self.usage_refresh.awaiting = true;
            self.usage_refresh.submitted_serial = submitted_serial;
        } else {
            self.finishUsageRefresh();
        }
    }

    fn addAccountLabeledFn(context: *anyopaque, provider: domain.Provider, label: []const u8) ui_model.CommandOutcome {
        const self: *Service = @ptrCast(@alignCast(context));
        return self.submitAddAccount(provider, label);
    }

    fn submitAddAccount(self: *Service, provider: domain.Provider, custom_label: ?[]const u8) ui_model.CommandOutcome {
        if (provider == .claude) return .accepted_pending;
        if (custom_label) |label| account_registry.validateLabel(label) catch return .rejected_not_allowed;
        const live = self.live orelse return .service_unavailable;
        const now = self.now_unix_s;
        if (self.core.accountCount() + self.inactive_account_count >= account_registry.max_accounts) {
            return .rejected_not_allowed;
        }

        if (provider == .codex and self.core.config.target.executableFor(provider).len == 0) {
            self.recordCode(public_code_executable_missing);
            return .provider_cli_missing;
        }

        var suffix_storage: [generated_hex_digits * 2]u8 = undefined;
        const suffix = live.keys.next(&suffix_storage);
        if (suffix.len == 0) return .failed;

        var id_storage: [account_registry.max_id_bytes]u8 = undefined;
        var key_storage: [account_registry.max_storage_key_bytes]u8 = undefined;
        const provider_name = providerSegment(provider);
        const id = std.fmt.bufPrint(&id_storage, "acct-{s}-{s}", .{ provider_name, suffix }) catch return .failed;
        const storage_key = std.fmt.bufPrint(&key_storage, "{s}-{s}", .{ provider_name, suffix }) catch return .failed;

        var label_storage: [account_registry.max_label_bytes]u8 = undefined;
        const label = custom_label orelse (std.fmt.bufPrint(&label_storage, "{s} account", .{providerLabel(provider)}) catch
            return .failed);

        _ = self.core.addAccount(.{
            .id = id,
            .provider = provider,
            .label = label,
            .label_is_custom = custom_label != null,
            .storage_key = storage_key,
            .created_at_unix_s = now,
        }) catch return .failed;

        self.ensureAccountHomes(storage_key) catch {
            self.rollbackNewAccount(id, live);
            self.recordCode(public_code_directory_unavailable);
            return .failed;
        };
        self.core.persistRegistry(live.sink) catch {
            self.rollbackNewAccount(id, live);
            self.recordCode(coordinator.public_code_persist_failed);
            return .failed;
        };

        const outcome = self.startLogin(id, .initial, now);
        if (!outcome.accepted()) self.rollbackNewAccount(id, live);
        return outcome;
    }

    fn submitReauthenticate(self: *Service, account_id: []const u8) ui_model.CommandOutcome {
        if (self.live == null) return .service_unavailable;
        const account = self.core.account(account_id) orelse return .rejected_unknown_account;
        if (account.provider != .codex) return .rejected_not_allowed;
        return self.startLogin(account_id, .reauthenticate, self.now_unix_s);
    }

    fn submitRelabel(self: *Service, request: ui_model.Relabel) ui_model.CommandOutcome {
        const live = self.live orelse return .service_unavailable;
        const account = self.core.account(request.account_id) orelse return .rejected_unknown_account;
        if (account.provider != .codex) return .rejected_not_allowed;
        self.core.registry.setLabel(request.account_id, request.label) catch |err| return switch (err) {
            error.UnknownAccount => .rejected_unknown_account,
            error.InvalidLabel => .rejected_not_allowed,
            else => .failed,
        };
        self.core.persistRegistry(live.sink) catch {
            self.recordCode(coordinator.public_code_persist_failed);
            return .failed;
        };
        return .accepted_pending;
    }

    fn submitMoveAccount(self: *Service, request: ui_model.MoveAccount) ui_model.CommandOutcome {
        const live = self.live orelse return .service_unavailable;
        const account = self.core.account(request.account_id) orelse return .rejected_unknown_account;
        const target = self.core.account(request.target_account_id) orelse return .rejected_unknown_account;
        if (account.provider != .codex or target.provider != .codex) return .rejected_not_allowed;

        const from = self.core.registry.indexOf(request.account_id) orelse return .rejected_unknown_account;
        const to = self.core.registry.indexOf(request.target_account_id) orelse return .rejected_unknown_account;
        if (from == to) return .none;
        self.core.moveAccount(request.account_id, to) catch |err| return switch (err) {
            error.UnknownAccount => .rejected_unknown_account,
            error.SchedulerBusy => .rejected_busy,
        };
        self.core.persistRegistry(live.sink) catch {
            self.recordCode(coordinator.public_code_persist_failed);
            return .failed;
        };
        self.scheduleProxySyncAfterRegistryChange();
        return .accepted_pending;
    }

    fn submitRemoveAccount(self: *Service, account_id: []const u8) ui_model.CommandOutcome {
        const live = self.live orelse return .service_unavailable;
        const account = self.core.account(account_id) orelse return .rejected_unknown_account;
        if (account.provider != .codex) return .rejected_not_allowed;
        if (!self.proxy.allowsRemoval(account_id)) return .rejected_not_allowed;
        const plan = self.core.planAccountRemoval(account_id) catch return .rejected_unknown_account;
        if (!plan.isExecutable()) {
            self.recordCode(plan.blocked_code.?);
            return .rejected_busy;
        }

        var directories: [2]runtime_paths.Path = plan.directories;
        const directory_count = plan.directory_count;

        _ = self.core.applyAccountRemoval(plan, .{
            .account_id = plan.account_id,
            .delete_credentials = true,
            .directories_acknowledged = true,
        }, live.credentials, live.sink) catch |err| return switch (err) {
            error.UnknownAccount, error.ConfirmationMismatch => .rejected_unknown_account,
            error.Blocked => .rejected_busy,
            error.CredentialStoreMissing, error.CredentialRemovalFailed => .failed,
        };

        for (directories[0..directory_count]) |*path| {
            live.directories.remove(path.slice()) catch {
                self.recordCode(public_code_directory_unavailable);
            };
        }
        self.proxy.recordRemoval(account_id);
        return .accepted_pending;
    }

    fn ensureAccountHomes(self: *Service, storage_key: []const u8) !void {
        const live = self.live orelse return error.Unsupported;
        const paths = self.core.config.layout.profilePaths(storage_key) catch return error.InvalidHome;
        try live.directories.ensure(paths.profile_dir.slice());
        try live.directories.ensure(paths.codex_home.slice());
    }

    fn rollbackNewAccount(self: *Service, account_id: []const u8, live: Live) void {
        const plan = self.core.planAccountRemoval(account_id) catch return;
        if (!plan.isExecutable()) return;
        var directories: [2]runtime_paths.Path = plan.directories;
        const directory_count = plan.directory_count;
        _ = self.core.applyAccountRemoval(plan, .{
            .account_id = plan.account_id,
            .delete_credentials = false,
            .directories_acknowledged = true,
        }, null, live.sink) catch return;
        for (directories[0..directory_count]) |*path| {
            live.directories.remove(path.slice()) catch {};
        }
    }

    fn startLogin(
        self: *Service,
        account_id: []const u8,
        purpose: coordinator.LoginPurpose,
        now_unix_s: i64,
    ) ui_model.CommandOutcome {
        const live = self.live orelse return .service_unavailable;
        const account = self.core.account(account_id) orelse return .rejected_unknown_account;
        if (account.provider != .codex) return .rejected_not_allowed;
        const worker_index = app_worker.free(&self.workers) orelse return .rejected_busy;

        var session = self.core.beginLogin(account_id, purpose, .details, now_unix_s) catch |err|
            return switch (err) {
                error.UnknownAccount => .rejected_unknown_account,
                error.AccountDisabled, error.SurfaceNotAllowed, error.InvalidAccountHome => .rejected_not_allowed,
                error.AccountBusy, error.ConcurrencyLimit, error.PendingAttempt => .rejected_busy,
            };

        const worker = &self.workers[worker_index];
        worker.kind = .login;
        worker.provider = session.provider;
        worker.now_unix_s = now_unix_s;
        worker.home = session.home;
        copyInto(&worker.account_id_buffer, &worker.account_id_len, session.account_id);
        worker.login_launcher = live.login_launcher;
        worker.login_options = live.login_options;

        if (session.provider == .codex) {
            self.core.writeSessionLoginSpec(&session, &worker.login_spec, live.parent_env) catch |err| {
                self.core.closeLoginSession(&session);
                self.recordCode(login_runtime.public_code_login_unsupported);
                return if (err == error.InvalidExecutable) .provider_cli_missing else .rejected_not_allowed;
            };

            worker.login_spec.rebind();
            worker.login_spec.account_id = worker.accountId();
        }

        self.pending_logins[worker_index] = .{ .active = true, .session = session, .purpose = purpose };
        if (!app_worker.start(live.io, &self.workers[worker_index])) {
            self.pending_logins[worker_index] = .{};
            self.core.closeLoginSession(&session);
            self.recordCode(public_code_worker_unavailable);
            return .rejected_busy;
        }
        self.activity.logins_started += 1;
        return .accepted_pending;
    }

    fn submitRedeemReset(self: *Service, request: ui_model.RedeemReset) ui_model.CommandOutcome {
        const live = self.live orelse return .offer_unavailable;
        if (!self.capabilities().reset) return .offer_unavailable;
        const outcome = self.reset.submitRedeem(self.resetContext(live), request, self.now_unix_s);
        if (outcome == .accepted_pending) self.reset_proxy_clear = .{};
        return outcome;
    }

    fn submitRetryReset(self: *Service, account_id: []const u8) ui_model.CommandOutcome {
        const live = self.live orelse return .offer_unavailable;
        if (!self.capabilities().reset) return .offer_unavailable;
        const outcome = self.reset.submitRetry(self.resetContext(live), account_id, self.now_unix_s);
        if (outcome == .accepted_pending) self.reset_proxy_clear = .{};
        return outcome;
    }

    pub fn resetProxyClearFor(self: *const Service, account_id: []const u8) ui_model.ResetProxyClear {
        if (!self.reset_proxy_clear.account_id.eql(account_id)) return .none;
        return self.reset_proxy_clear.state;
    }

    fn resetOnSettled(context: *anyopaque, account_id: []const u8, now_unix_s: i64) void {
        const self: *Service = @ptrCast(@alignCast(context));
        _ = now_unix_s;
        self.reset_proxy_clear = .{};
        self.reset_proxy_clear.account_id = proxy_control.BoundedText(account_registry.max_id_bytes).init(account_id) catch return;
        const submitted_serial = self.proxy.lastCompletion().serial;
        self.reset_proxy_clear.state = switch (self.startProxy(.clear_cooldown, account_id)) {
            .accepted_pending => .pending,
            .rejected_busy => .busy,
            .rejected_not_allowed => .@"unreachable",
            .rejected_unknown_account => .not_mapped,
            .none, .service_unavailable, .provider_cli_missing, .offer_unavailable, .failed => .failed,
        };
        if (self.reset_proxy_clear.state == .pending) {
            self.reset_proxy_clear.submitted_serial = submitted_serial;
            self.reset_proxy_clear.awaiting = true;
        }
    }

    fn settleResetProxyClear(self: *Service) void {
        if (!self.reset_proxy_clear.awaiting) return;
        const completion = self.proxy.lastCompletion();
        if (completion.serial == self.reset_proxy_clear.submitted_serial) return;
        self.reset_proxy_clear.awaiting = false;
        self.reset_proxy_clear.state = if (completion.kind == .clear_cooldown and completion.ok) .cleared else .failed;
    }

    fn resetContext(self: *Service, live: Live) app_reset_service.Context {
        return .{
            .core = self.core,
            .workers = &self.workers,
            .io = live.io,
            .sink = live.sink,
            .keys = live.keys,
            .resets_started = &self.activity.resets_started,
            .consumes_sent = &self.activity.consumes_sent,
            .last_reset_outcome = &self.activity.last_reset_outcome,
            .callback_context = self,
            .prepare_codex_fn = resetPrepareCodex,
            .apply_observation_fn = resetApplyObservation,
            .record_code_fn = resetRecordCode,
            .on_settled_fn = resetOnSettled,
        };
    }

    fn cooldownRecord(self: *Service, account_id: []const u8) ?*CooldownReconcileRecord {
        var free: ?*CooldownReconcileRecord = null;
        for (&self.cooldown_reconciliations) |*record| {
            if (record.occupied and record.account_id.eql(account_id)) return record;
            if (!record.occupied and free == null) free = record;
        }
        const record = free orelse return null;
        record.* = .{
            .account_id = proxy_control.BoundedText(account_registry.max_id_bytes).init(account_id) catch return null,
            .occupied = true,
        };
        return record;
    }

    fn snapshotHasAvailableBindingWindow(plan_label: ?[]const u8, snapshot: domain.UsageSnapshot) bool {
        const selected = ui_model.selectCodexPrimaryWindow(plan_label, snapshot.windows) orelse return false;
        return snapshot.windows[selected].used_percent < 100;
    }

    fn observeFreshUsageForCooldown(self: *Service, account_id: []const u8, now_unix_s: i64) void {
        if (self.proxy.state.reachability != .reachable or !self.proxy.state.config_path_matches) return;
        const proxy_checked_at = self.proxy.state.last_success_at_unix_s orelse return;
        const status = self.proxy.state.last_success orelse return;
        const mapped = status.requireMapped(account_id) catch return;
        const snapshot = self.core.snapshotFor(account_id) orelse return;
        const account = self.core.account(account_id) orelse return;
        if (snapshot.status != .fresh or snapshot.captured_at_unix_s > proxy_checked_at) return;

        const record = self.cooldownRecord(account_id) orelse return;
        if (mapped.state != .cooldown) {
            record.* = .{};
            return;
        }
        if (record.cooldown_until_unix_s != mapped.cooldown_until_unix_s) {
            record.cooldown_until_unix_s = mapped.cooldown_until_unix_s;
            record.attempted = false;
            record.queued = false;
        }
        const deadline_passed = if (mapped.cooldown_until_unix_s) |until| until <= now_unix_s else false;
        if (!deadline_passed and !snapshotHasAvailableBindingWindow(account.plan_label, snapshot)) return;
        if (record.attempted) return;

        record.attempted = true;
        record.queued = true;
    }

    fn resetEndedCooldownRecords(self: *Service) void {
        if (self.proxy.state.reachability != .reachable or !self.proxy.state.config_path_matches) return;
        const status = self.proxy.state.last_success orelse return;
        for (&self.cooldown_reconciliations) |*record| {
            if (!record.occupied) continue;
            const mapped = status.requireMapped(record.account_id.slice()) catch {
                record.* = .{};
                continue;
            };
            if (mapped.state != .cooldown) record.* = .{};
        }
    }

    fn submitOneCooldownReconciliation(self: *Service) void {
        if (self.proxy.busy()) return;
        for (&self.cooldown_reconciliations) |*record| {
            if (!record.occupied or !record.queued) continue;
            record.queued = false;
            _ = self.startProxy(.clear_cooldown, record.account_id.slice());
            return;
        }
    }

    fn resetPrepareCodex(
        context: *anyopaque,
        worker: *Worker,
        account_index: u16,
        kind: JobKind,
        now_unix_s: i64,
    ) ?[]const u8 {
        const self: *Service = @ptrCast(@alignCast(context));
        return self.prepareCodexWorker(worker, account_index, kind, now_unix_s, self.live.?);
    }

    fn resetApplyObservation(
        context: *anyopaque,
        ticket: coordinator.Ticket,
        observation: coordinator.Observation,
        now_unix_s: i64,
    ) void {
        const self: *Service = @ptrCast(@alignCast(context));
        self.applyObservation(ticket, observation, now_unix_s, self.live.?);
    }

    fn resetRecordCode(context: *anyopaque, code: []const u8) void {
        const self: *Service = @ptrCast(@alignCast(context));
        self.recordCode(code);
    }

    pub fn pump(self: *Service, now_unix_s: i64) void {
        self.now_unix_s = now_unix_s;
        if (self.live) |live| if (live.proxy_service) |service_live| self.proxy_service.drain(service_live.io);
        self.drainProxy(now_unix_s);
        self.resetEndedCooldownRecords();
        self.settleResetProxyClear();
        self.drainWorkers(now_unix_s);
        if (self.usage_refresh.stage == .provider) self.startQueued(now_unix_s);
        self.advanceUsageRefresh();
        self.submitOneCooldownReconciliation();
        if (!self.usage_refresh.active()) self.startQueued(now_unix_s);
        self.maybeStartAutoRefresh(now_unix_s);
    }

    fn maybeStartAutoRefresh(self: *Service, now_unix_s: i64) void {
        if (self.auto_refresh_minutes == 0 or self.live == null or self.usage_refresh.active()) return;
        if (!self.core.schedulerIsIdle() or self.busyWorkerCount() != 0) return;
        var anchor = self.last_successful_refresh_at_unix_s;
        if (self.last_auto_refresh_attempt_at_unix_s) |attempt| {
            if (anchor == null or attempt > anchor.?) anchor = attempt;
        }
        if (anchor) |at| {
            if (now_unix_s < at) return;
            const interval_s: i64 = @as(i64, self.auto_refresh_minutes) * 60;
            if (now_unix_s - at < interval_s) return;
        }
        self.last_auto_refresh_attempt_at_unix_s = now_unix_s;
        _ = self.submitRefreshAll();
    }

    fn autoRefreshAccountCount(self: *const Service) u16 {
        var count: u16 = 0;
        var index: usize = 0;
        while (index < self.core.accountCount()) : (index += 1) {
            const account = self.core.accountAt(index) orelse continue;
            if (account.provider == .codex and account.enabled and account.auth_state == .connected) count += 1;
        }
        return count;
    }

    fn drainProxy(self: *Service, now_unix_s: i64) void {
        const live = self.live orelse return;
        self.proxy.drain(self.core, proxyDrivers(live), now_unix_s);
        switch (self.proxy.state.reachability) {
            .reachable => if (self.proxy.state.config_path_matches) {
                const in_flight = if (self.proxy.state.last_success) |status| status.in_flight else 0;
                self.proxy_service.observeProxyHealth(.{ .state = .healthy, .in_flight = in_flight });
            },
            .@"unreachable" => self.proxy_service.observeProxyHealth(.{ .state = .@"unreachable" }),
            .incompatible => self.proxy_service.observeProxyHealth(.{ .state = .incompatible }),
            .unknown => {},
        }
    }

    fn drainWorkers(self: *Service, now_unix_s: i64) void {
        const live = self.live orelse return;
        for (&self.workers, 0..) |*worker, index| {
            if (worker.state != .running) continue;
            if (!worker.done.isSet()) continue;

            _ = worker.future.await(live.io);
            worker.started = false;
            worker.state = .complete;
            self.applyWorker(index, now_unix_s);
            app_worker.release(worker);
        }
    }

    fn applyWorker(self: *Service, index: usize, now_unix_s: i64) void {
        const live = self.live orelse return;
        const worker = &self.workers[index];
        const backs_up_codex_auth = worker.provider == .codex and switch (worker.result) {
            .codex, .consume => true,
            else => false,
        };
        switch (worker.kind) {
            .codex_refresh => self.applyCodexRefresh(worker, now_unix_s, live),
            .login => self.applyLogin(index, now_unix_s, live),
            .reset_preflight => self.reset.applyPreflight(self.resetContext(live), worker, now_unix_s),
            .reset_consume => self.reset.applyConsume(self.resetContext(live), worker, now_unix_s),
            .reset_post_read => self.reset.applyPostRead(self.resetContext(live), worker, now_unix_s),
        }
        if (backs_up_codex_auth) self.backupCodexAuth(worker.accountId(), live);
    }

    fn applyCodexRefresh(self: *Service, worker: *Worker, now_unix_s: i64, live: Live) void {
        const registry_revision = self.core.registry.revision;
        if (worker.result == .codex) {
            const metadata = worker.result.codex.account_metadata;
            if (metadata.hasObservation()) {
                self.core.recordProviderMetadata(worker.ticket.account_id, .{
                    .email = metadata.email,
                    .email_observed = metadata.email_observed,
                    .plan_label = metadata.plan_label,
                    .plan_observed = metadata.plan_observed,
                }) catch {};
            }
        }
        const observation = app_worker.codexObservation(worker, now_unix_s) orelse {
            self.core.abandonOperation(worker.ticket, now_unix_s, app_worker.rejectionCode(worker));
            return;
        };
        self.applyObservation(worker.ticket, observation, now_unix_s, live);
        if (self.core.registry.revision != registry_revision) {
            self.core.persistRegistry(live.sink) catch self.recordCode(coordinator.public_code_persist_failed);
        }
    }

    fn applyObservation(
        self: *Service,
        ticket: coordinator.Ticket,
        observation: coordinator.Observation,
        now_unix_s: i64,
        live: Live,
    ) void {
        const registry_revision = self.core.registry.revision;
        var report = self.core.applyObservation(ticket, observation, now_unix_s) catch {
            self.recordCode(coordinator.public_code_operation_unknown);
            return;
        };
        if (report.replaced_snapshot) {
            self.core.persistSnapshots(live.sink) catch {
                report.persist_code = coordinator.public_code_persist_failed;
            };
        }
        if (self.core.registry.revision != registry_revision) {
            self.core.persistRegistry(live.sink) catch {
                if (report.persist_code == null) report.persist_code = coordinator.public_code_persist_failed;
            };
        }
        if (report.replaced_snapshot and ticket.purpose == .user_refresh and self.usage_refresh.active())
            self.rememberRefreshSuccess(ticket.account_id);
        if (report.public_code) |code| self.recordCode(code);
        if (report.persist_code) |code| self.recordCode(code);
    }

    fn applyLogin(self: *Service, index: usize, now_unix_s: i64, live: Live) void {
        const worker = &self.workers[index];
        var pending = self.pending_logins[index];
        self.pending_logins[index] = .{};
        if (!pending.active) return;

        const status = switch (worker.result) {
            .login => |value| value,
            else => login_runtime.spawnFailedStatus(worker.provider, worker.accountId()),
        };

        const report = self.core.applyLoginResult(&pending.session, status, now_unix_s, live.sink) catch {
            self.core.closeLoginSession(&pending.session);
            self.recordCode(coordinator.public_code_operation_unknown);
            return;
        };
        self.core.closeLoginSession(&pending.session);
        if (report.public_code) |code| self.recordCode(code);

        if (report.provider == .codex and report.succeeded() and status.endedCleanly()) {
            self.backupCodexAuth(report.account_id, live);
            if (report.persist_code == null) _ = self.core.requestSignInRefresh(report.account_id) catch return;
        }
    }

    fn startQueued(self: *Service, now_unix_s: i64) void {
        const live = self.live orelse return;
        while (app_worker.free(&self.workers)) |worker_index| {
            const ticket = self.core.nextOperation(now_unix_s) orelse return;
            const failure = switch (ticket.provider) {
                .codex => self.startCodexStep(worker_index, ticket, .codex_refresh, now_unix_s, live),
                .claude => coordinator.public_code_provider_mismatch,
            };
            if (failure) |code| {
                self.core.abandonOperation(ticket, now_unix_s, code);
                continue;
            }
            self.activity.refreshes_started += 1;
        }
    }

    fn startCodexStep(
        self: *Service,
        worker_index: usize,
        ticket: coordinator.Ticket,
        kind: JobKind,
        now_unix_s: i64,
        live: Live,
    ) ?[]const u8 {
        const worker = &self.workers[worker_index];
        if (self.prepareCodexWorker(worker, ticket.account_index, kind, now_unix_s, live)) |code| return code;
        worker.ticket = ticket;
        worker.external_channel = null;
        if (!app_worker.start(live.io, &self.workers[worker_index])) {
            self.recordCode(public_code_worker_unavailable);
            return public_code_worker_unavailable;
        }
        return null;
    }

    fn prepareCodexWorker(
        self: *Service,
        worker: *Worker,
        account_index: u16,
        kind: JobKind,
        now_unix_s: i64,
        live: Live,
    ) ?[]const u8 {
        if (live.codex_cli_too_old) {
            self.recordCode(codex.public_code_app_server_unsupported);
            return codex.public_code_app_server_unsupported;
        }
        const value = self.core.accountAt(account_index) orelse {
            self.recordCode(coordinator.public_code_account_unknown);
            return coordinator.public_code_account_unknown;
        };

        const home = self.core.config.layout.codexHome(value.storage_key) catch {
            self.recordCode(coordinator.public_code_account_home_invalid);
            return coordinator.public_code_account_home_invalid;
        };

        worker.kind = kind;
        worker.provider = .codex;
        worker.now_unix_s = now_unix_s;
        worker.home = home;
        copyInto(&worker.account_id_buffer, &worker.account_id_len, value.id);
        worker.codex_launcher = live.codex_launcher;
        worker.codex_config = .{
            .codex_home = worker.home.slice(),
            .client = live.codex_client,
            .startup_timeout_ms = live.codex_timeouts.startup_ms,
            .request_timeout_ms = live.codex_timeouts.request_ms,
        };
        worker.external_channel = null;
        worker.result = .none;
        return null;
    }

    pub fn busyWorkerCount(self: *const Service) usize {
        return app_worker.busyCount(&self.workers);
    }

    pub fn shutdown(self: *Service) void {
        if (self.live) |live| {
            if (live.proxy_service) |service_live| self.proxy_service.shutdown(service_live.io);
            self.proxy.shutdown(live.io);
            for (&self.workers, 0..) |*worker, index| {
                app_worker.cancelAndJoin(live.io, worker);
                if (self.pending_logins[index].active) {
                    self.core.closeLoginSession(&self.pending_logins[index].session);
                    self.pending_logins[index] = .{};
                }
            }
        }
        self.reset.shutdown(self.core);
        self.live = null;
    }

    fn recordCode(self: *Service, code: []const u8) void {
        self.activity.last_code = coordinator.canonicalPublicCode(code);
    }

    fn backupCodexAuth(self: *Service, account_id: []const u8, live: Live) void {
        const account = self.core.account(account_id) orelse {
            std.log.warn("Codex auth backup failed for unknown account", .{});
            return;
        };
        if (account.provider != .codex) return;
        const auth_path = self.core.config.layout.codexAuthFile(account.storage_key) catch |err| {
            logAuthFailure("backup path", account.storage_key, err);
            return;
        };
        const bytes = readPrivateAuthFile(self.allocator, live.io, auth_path.slice()) catch |err| {
            logAuthFailure("backup read", account.storage_key, err);
            return;
        };
        defer {
            std.crypto.secureZero(u8, bytes);
            self.allocator.free(bytes);
        }
        var credential = keychain.Credential.init(bytes) catch |err| {
            logAuthFailure("backup encode", account.storage_key, err);
            return;
        };
        defer credential.wipe();
        const account_key = account.accountKey() catch |err| {
            logAuthFailure("backup account", account.storage_key, err);
            return;
        };
        live.credentials.save(&account_key, .codex_auth_backup, &credential) catch |err| {
            logAuthFailure("backup save", account.storage_key, err);
        };
    }

    pub fn restoreCodexAuthBackups(self: *Service) void {
        const live = self.live orelse return;
        var index: usize = 0;
        while (index < self.core.accountCount()) : (index += 1) {
            const account = self.core.accountAt(index) orelse continue;
            if (account.provider != .codex) continue;
            const auth_path = self.core.config.layout.codexAuthFile(account.storage_key) catch |err| {
                logAuthFailure("restore path", account.storage_key, err);
                continue;
            };
            const missing = authFileMissing(live.io, auth_path.slice()) catch |err| {
                logAuthFailure("restore inspect", account.storage_key, err);
                continue;
            };
            if (!missing) continue;

            const account_key = account.accountKey() catch |err| {
                logAuthFailure("restore account", account.storage_key, err);
                continue;
            };
            var credential: keychain.Credential = .empty;
            live.credentials.load(&account_key, .codex_auth_backup, &credential) catch |err| switch (err) {
                error.NotFound => continue,
                else => {
                    logAuthFailure("restore load", account.storage_key, err);
                    continue;
                },
            };
            defer credential.wipe();
            writeRestoredAuthFile(live.io, &self.core.config.layout, account.storage_key, &credential) catch |err| {
                logAuthFailure("restore write", account.storage_key, err);
                continue;
            };
            std.log.info("restored Codex auth backup for storage key {s}", .{account.storage_key});
        }
    }

    pub fn load(self: *Service, io: std.Io, dir: std.Io.Dir) coordinator.LoadReport {
        self.captureInactiveDocuments(io, dir);
        var app_settings = store.loadAppSettings(self.allocator, io, dir, runtime_paths.app_settings_file_name) catch null;
        if (app_settings) |*loaded| {
            defer loaded.deinit();
            self.appearance = loaded.value.appearance;
            self.codex_usage_window = loaded.value.codex_usage_window;
            self.codex_show_model_limits = loaded.value.codex_show_model_limits;
            self.launch_at_login = loaded.value.launch_at_login;
            self.launch_at_login_registration_failed = loaded.value.launch_at_login_registration_failed;
            self.auto_refresh_minutes = loaded.value.auto_refresh_minutes;
            self.last_successful_refresh_at_unix_s = loaded.value.last_successful_refresh_at_unix_s;
        }
        const report = self.core.loadFromDirectoryForProvider(io, dir, .codex);
        if (report.registry_code) |code| self.recordCode(code);
        if (report.snapshots_code) |code| self.recordCode(code);
        if (report.attempts_code) |code| self.recordCode(code);
        self.proxy.load(self.core, self.allocator, io, dir);
        self.restoreCodexAuthBackups();
        return report;
    }

    pub fn recoveryPlan(self: *const Service) coordinator.RecoveryPlan {
        return self.core.planLedgerRecovery();
    }
};

fn readPrivateAuthFile(
    allocator: std.mem.Allocator,
    io: std.Io,
    path: []const u8,
) ![]u8 {
    var file = try std.Io.Dir.cwd().openFile(io, path, .{
        .allow_directory = false,
        .follow_symlinks = false,
    });
    defer file.close(io);
    const stat = try file.stat(io);
    if (stat.kind != .file) return error.NotAFile;
    if (stat.size > keychain.max_credential_bytes) return error.FileTooBig;
    var reader = file.reader(io, &.{});
    return reader.interface.allocRemaining(allocator, .limited(keychain.max_credential_bytes)) catch |err| switch (err) {
        error.StreamTooLong => error.FileTooBig,
        error.OutOfMemory => error.OutOfMemory,
        error.ReadFailed => reader.err.?,
    };
}

fn authFileMissing(io: std.Io, path: []const u8) !bool {
    const stat = std.Io.Dir.cwd().statFile(io, path, .{ .follow_symlinks = false }) catch |err| switch (err) {
        error.FileNotFound => return true,
        else => return err,
    };
    if (stat.kind != .file) return error.NotAFile;
    return false;
}

fn writeRestoredAuthFile(
    io: std.Io,
    layout: *const runtime_paths.Layout,
    storage_key: []const u8,
    credential: *const keychain.Credential,
) !void {
    const home = try layout.codexHome(storage_key);
    const auth_path = try layout.codexAuthFile(storage_key);
    const cwd = std.Io.Dir.cwd();
    _ = try cwd.createDirPathStatus(io, home.slice(), private_dir_permissions);
    var file = try cwd.createFile(io, auth_path.slice(), .{
        .exclusive = true,
        .permissions = private_auth_file_permissions,
    });
    var committed = false;
    defer {
        file.close(io);
        if (!committed) cwd.deleteFile(io, auth_path.slice()) catch {};
    }
    try file.setPermissions(io, private_auth_file_permissions);
    var plaintext: [keychain.max_credential_bytes]u8 = undefined;
    defer std.crypto.secureZero(u8, &plaintext);
    const bytes = try credential.copyPlaintext(&plaintext);
    try file.writeStreamingAll(io, bytes);
    try file.sync(io);
    committed = true;
}

fn logAuthFailure(action: []const u8, storage_key: []const u8, err: anyerror) void {
    if (err == error.FileNotFound) {
        std.log.info("Codex auth {s} failed for storage key {s}: {s}", .{ action, storage_key, @errorName(err) });
        return;
    }
    std.log.warn("Codex auth {s} failed for storage key {s}: {s}", .{ action, storage_key, @errorName(err) });
}

fn creditDetailCount(core: *const coordinator.Coordinator, index: usize) usize {
    const snapshot = core.snapshotAt(index) orelse return 0;
    const credits = snapshot.reset_credits orelse return 0;
    return credits.details.len;
}

fn providerSegment(provider: domain.Provider) []const u8 {
    return switch (provider) {
        .claude => "claude",
        .codex => "codex",
    };
}

fn providerLabel(provider: domain.Provider) []const u8 {
    return switch (provider) {
        .claude => "Unsupported",
        .codex => "Codex",
    };
}

fn copyInto(buffer: []u8, len: *usize, value: []const u8) void {
    const take = @min(value.len, buffer.len);
    @memcpy(buffer[0..take], value[0..take]);
    len.* = take;
}

fn proxyDrivers(live: Live) app_proxy_service.Drivers {
    const lifecycle = live.proxy_service;
    return .{
        .io = live.io,
        .allocator = live.allocator,
        .sink = live.sink,
        .parent_env = live.parent_env,
        .exchange = live.proxy_exchange,
        .importer = live.proxy_importer,
        .node_resolver = live.proxy_node_resolver,
        .bundle_cli_path = if (lifecycle) |value| value.paths.cli_path.slice() else "",
        .bundle_node_path = if (lifecycle) |value| value.paths.node_path.slice() else "",
    };
}

fn parentEnvironmentValue(parent: transport.ParentEnv, name: []const u8) ?[]const u8 {
    return switch (parent) {
        .pairs => |pairs| blk: {
            for (pairs) |pair| if (std.mem.eql(u8, pair.name, name)) break :blk pair.value;
            break :blk null;
        },
        .map => |map| map.get(name),
    };
}
