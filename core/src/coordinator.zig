const std = @import("std");
const account_registry = @import("account_registry.zig");
const attempt_ledger = @import("attempt_ledger.zig");
const domain = @import("domain.zig");
const keychain = @import("keychain.zig");
const login_runtime = @import("login_runtime.zig");
const oauth = @import("oauth.zig");
const operation_scheduler = @import("operation_scheduler.zig");
const reset_engine = @import("reset_engine.zig");
const runtime_paths = @import("runtime_paths.zig");
const snapshot_book = @import("snapshot_book.zig");
const store = @import("store.zig");
const transport = @import("process_jsonl.zig");
const codex = @import("providers/codex.zig");

pub const max_accounts: usize = account_registry.max_accounts;

pub const max_concurrent_operations: usize = operation_scheduler.max_concurrent_operations;
pub const max_operations_per_account: usize = operation_scheduler.max_operations_per_account;

pub const max_windows_per_account: usize = snapshot_book.max_windows_per_account;
pub const max_credit_details_per_account: usize = snapshot_book.max_credit_details_per_account;
pub const max_window_label_bytes: usize = snapshot_book.max_window_label_bytes;
pub const max_credit_id_bytes: usize = snapshot_book.max_credit_id_bytes;
pub const max_snapshot_text_bytes: usize = snapshot_book.max_snapshot_text_bytes;

pub const Supported = snapshot_book.Supported;
const SnapshotBook = snapshot_book.SnapshotBook;

pub const max_attempts: usize = attempt_ledger.max_attempts;
pub const max_idempotency_key_bytes: usize = attempt_ledger.max_idempotency_key_bytes;
pub const max_ledger_text_bytes: usize = attempt_ledger.max_ledger_text_bytes;
pub const LedgerError = attempt_ledger.LedgerError;
const AttemptLedger = attempt_ledger.AttemptLedger;

pub const default_max_preflight_age_s: i64 = codex.default_max_preflight_age_s;

pub const max_login_argv: usize = login_runtime.max_login_argv;
pub const max_child_env_vars: usize = login_runtime.max_child_env_vars;

pub const public_code_account_unknown = "account-unknown";
pub const public_code_account_busy = "account-busy";
pub const public_code_account_disabled = "account-disabled";
pub const public_code_provider_mismatch = "provider-mismatch";
pub const public_code_account_home_invalid = codex.public_code_account_home_invalid;
pub const public_code_home_mismatch = codex.public_code_codex_home_mismatch;
pub const public_code_refresh_failed = "refresh-failed";
pub const public_code_operation_unknown = "operation-unknown";
pub const public_code_snapshot_capacity = "snapshot-capacity";
pub const public_code_document_unreadable = "document-unreadable";
pub const public_code_document_unsupported = "document-unsupported";
pub const public_code_persist_failed = "persist-failed";
pub const public_code_login_import_unavailable = "login-import-unavailable";
pub const public_code_login_import_incomplete = "login-import-incomplete";
pub const public_code_offer_changed = "reset-offer-changed";
pub const public_code_offer_stale = "reset-offer-stale";
pub const public_code_attempt_pending = "reset-attempt-pending";
pub const public_code_ledger_unavailable = "reset-ledger-unavailable";

pub const public_codes = [_][]const u8{
    public_code_account_unknown,
    public_code_account_busy,
    public_code_account_disabled,
    public_code_provider_mismatch,
    public_code_refresh_failed,
    public_code_operation_unknown,
    public_code_snapshot_capacity,
    public_code_document_unreadable,
    public_code_document_unsupported,
    public_code_persist_failed,
    public_code_login_import_unavailable,
    public_code_login_import_incomplete,
    public_code_offer_changed,
    public_code_offer_stale,
    public_code_attempt_pending,
    public_code_ledger_unavailable,
};

pub const login_public_codes = login_runtime.public_codes;

pub fn canonicalPublicCode(code: []const u8) []const u8 {
    for (public_codes) |known| {
        if (std.mem.eql(u8, code, known)) return known;
    }
    for (login_public_codes) |known| {
        if (std.mem.eql(u8, code, known)) return known;
    }
    for (codex.public_codes) |known| {
        if (std.mem.eql(u8, code, known)) return known;
    }
    for (oauth.public_codes) |known| {
        if (std.mem.eql(u8, code, known)) return known;
    }
    return public_code_refresh_failed;
}

pub fn isPublicCode(code: []const u8) bool {
    for (public_codes) |known| {
        if (std.mem.eql(u8, code, known)) return true;
    }
    return login_runtime.isPublicCode(code) or codex.isPublicCode(code);
}

pub fn sanitizeRefreshError(failure: domain.RefreshError) domain.RefreshError {
    return .{
        .kind = failure.kind,
        .public_code = canonicalPublicCode(failure.public_code),
        .retryable = failure.retryable,
    };
}

fn refreshError(kind: domain.RefreshErrorKind, code: []const u8, retryable: bool) domain.RefreshError {
    return .{ .kind = kind, .public_code = canonicalPublicCode(code), .retryable = retryable };
}

pub const codex_home_var = runtime_paths.codex_home_var;

pub const codex_login_args = login_runtime.codex_login_args;

pub const EnvError = login_runtime.EnvError;
pub const EnvSpec = login_runtime.EnvSpec;
pub const LoginSpecError = login_runtime.LoginSpecError;
pub const LoginSpec = login_runtime.LoginSpec;
pub const LoginOptions = login_runtime.LoginOptions;
pub const writeLoginSpec = login_runtime.writeLoginSpec;

pub const LoginStatus = login_runtime.Status;
pub const LoginPhase = login_runtime.Phase;
pub const LoginExit = login_runtime.Exit;

pub const LoginPurpose = enum {
    initial,

    reauthenticate,
};

pub const LoginBeginError = AdmitError || error{
    SurfaceNotAllowed,

    PendingAttempt,
    InvalidAccountHome,
};

pub const LoginApplyError = error{
    SessionClosed,
    UnknownAccount,

    UnknownOperation,
};

pub const LoginSession = struct {
    pub const Stage = enum { running, finished, closed };

    account_index: u16,
    account_id: []const u8,
    provider: domain.Provider,
    purpose: LoginPurpose,
    surface: Surface,
    operation_id: u64,
    started_at_unix_s: i64,
    stage: Stage = .running,

    auth_revision: u64 = 0,

    home: runtime_paths.Path = .{},

    pub fn homePath(self: *const LoginSession) []const u8 {
        return self.home.slice();
    }
};

pub const LoginReport = struct {
    account_id: []const u8,
    provider: domain.Provider,
    purpose: LoginPurpose,
    operation_id: u64,
    phase: LoginPhase,
    exit: LoginExit = .unknown,
    auth_state: account_registry.AuthState,
    auth_revision: u64,
    auth_state_changed: bool = false,

    child_closed: bool = false,
    public_code: ?[]const u8 = null,
    persist_code: ?[]const u8 = null,

    pub fn succeeded(self: LoginReport) bool {
        return self.public_code == null and self.phase == .ended;
    }
};

pub const SinkError = error{ Unavailable, Denied, TooLarge, Io };

pub const DocumentSink = struct {
    context: *anyopaque,
    vtable: *const VTable,

    pub const VTable = struct {
        write: *const fn (context: *anyopaque, kind: runtime_paths.DocumentKind, bytes: []const u8) SinkError!void,
    };

    pub fn write(self: DocumentSink, kind: runtime_paths.DocumentKind, bytes: []const u8) SinkError!void {
        return self.vtable.write(self.context, kind, bytes);
    }
};

var unwired_sink_context: u8 = 0;
const unwired_sink_vtable: DocumentSink.VTable = .{ .write = unwiredSinkWrite };

fn unwiredSinkWrite(_: *anyopaque, _: runtime_paths.DocumentKind, _: []const u8) SinkError!void {
    return error.Unavailable;
}

pub fn unwiredDocumentSink() DocumentSink {
    return .{ .context = &unwired_sink_context, .vtable = &unwired_sink_vtable };
}

pub const FileDocumentSink = struct {
    io: std.Io,
    dir: std.Io.Dir,

    const vtable: DocumentSink.VTable = .{ .write = write };

    pub fn sink(self: *FileDocumentSink) DocumentSink {
        return .{ .context = self, .vtable = &vtable };
    }

    fn write(context: *anyopaque, kind: runtime_paths.DocumentKind, bytes: []const u8) SinkError!void {
        const self: *FileDocumentSink = @ptrCast(@alignCast(context));
        if (bytes.len > store.max_document_bytes) return error.TooLarge;
        store.writeAtomically(
            self.io,
            self.dir,
            runtime_paths.documentFileName(kind),
            runtime_paths.documentTempFileName(kind),
            bytes,
        ) catch |err| return switch (err) {
            error.TempPathMatchesFinalPath => error.Denied,
            else => error.Io,
        };
    }
};

fn sinkErrorCode(err: SinkError) []const u8 {
    return switch (err) {
        error.Unavailable, error.Denied, error.TooLarge, error.Io => public_code_persist_failed,
    };
}

pub const Failure = struct {
    failure: domain.RefreshError,
    observed_at_unix_s: i64,
};

pub const Observation = union(enum) {
    supported: Supported,
    failure: Failure,

    deferred,
};

pub const Purpose = operation_scheduler.Purpose;
pub const AdmitError = operation_scheduler.AdmitError;
pub const Ticket = operation_scheduler.Ticket;
pub const EnqueueOutcome = operation_scheduler.EnqueueOutcome;
pub const RefreshAllPlan = operation_scheduler.RefreshAllPlan;
const OperationScheduler = operation_scheduler.OperationScheduler;
const Runtime = operation_scheduler.Runtime;

pub const RefreshReport = struct {
    operation_id: u64,
    account_id: []const u8,
    provider: domain.Provider,
    phase: domain.RefreshPhase,

    replaced_snapshot: bool = false,

    retained_previous: bool = false,
    public_code: ?[]const u8 = null,
    persist_code: ?[]const u8 = null,
    windows_stored: usize = 0,
    credits_available: ?u32 = null,

    reached_provider: bool = false,
};

pub const AccountStatus = struct {
    account_id: []const u8,
    provider: domain.Provider,
    label: []const u8,
    enabled: bool,
    auth_state: account_registry.AuthState,
    auth_revision: u64,
    phase: domain.RefreshPhase,
    operation_in_flight: bool,
    queued: bool,
    last_attempt_at_unix_s: ?i64 = null,
    last_success_at_unix_s: ?i64 = null,
    last_attempt_code: ?[]const u8 = null,
    has_snapshot: bool = false,
    snapshot_captured_at_unix_s: ?i64 = null,
};

pub const Freshness = enum {
    never_refreshed,

    as_of,

    saved_snapshot,
    refresh_failed,
    reauth_required,
    usage_unavailable,
    refresh_deferred,

    reset_passed,
};

pub const Countdown = struct {
    window_label: []const u8 = "",
    reset_at_unix_s: ?i64 = null,
    remaining_s: ?i64 = null,
    passed: bool = false,
};

pub const Row = struct {
    account_id: []const u8,
    label: []const u8,
    provider_email: ?[]const u8 = null,
    plan_label: ?[]const u8 = null,
    provider: domain.Provider,
    enabled: bool,
    auth_state: account_registry.AuthState,
    freshness: Freshness,
    snapshot_status: ?domain.SnapshotStatus = null,
    snapshot_captured_at_unix_s: ?i64 = null,
    last_attempt_at_unix_s: ?i64 = null,
    last_success_at_unix_s: ?i64 = null,
    last_attempt_code: ?[]const u8 = null,

    window: ?domain.UsageWindow = null,
    countdown: Countdown = .{},

    reset_credit_count: ?u32 = null,
    credit_detail_status: ?domain.CreditDetailStatus = null,
    operation_in_flight: bool = false,
    queued: bool = false,
};

pub const Surface = reset_engine.Surface;
pub const SessionError = reset_engine.SessionError;
pub const OfferError = reset_engine.OfferError;
pub const ResetSession = reset_engine.ResetSession;
pub const ResetOffer = reset_engine.ResetOffer;
pub const Confirmation = reset_engine.Confirmation;
pub const ResetBeginError = reset_engine.ResetBeginError;
pub const ResetResolution = reset_engine.ResetResolution;
pub const RecoveryAction = reset_engine.RecoveryAction;
pub const RecoveryEntry = reset_engine.RecoveryEntry;
pub const RecoveryPlan = reset_engine.RecoveryPlan;
pub const CleanupPlan = reset_engine.CleanupPlan;
pub const CleanupConfirmation = reset_engine.CleanupConfirmation;
pub const CleanupError = reset_engine.CleanupError;
pub const CleanupResult = reset_engine.CleanupResult;
const ResetEngine = reset_engine.ResetEngine;

pub const LoadReport = struct {
    accounts_loaded: usize = 0,
    snapshots_loaded: usize = 0,

    snapshots_dropped: usize = 0,
    attempts_loaded: usize = 0,
    registry_code: ?[]const u8 = null,
    snapshots_code: ?[]const u8 = null,
    attempts_code: ?[]const u8 = null,

    reached_provider: bool = false,
};

pub const ChildLifecycle = struct {
    context: *anyopaque,
    vtable: *const VTable,

    pub const VTable = struct {
        close: *const fn (context: *anyopaque) void,
    };

    pub fn close(self: ChildLifecycle) void {
        self.vtable.close(self.context);
    }
};

var no_child_context: u8 = 0;
const no_child_vtable: ChildLifecycle.VTable = .{ .close = noChildClose };

fn noChildClose(_: *anyopaque) void {}

pub fn noChildLifecycle() ChildLifecycle {
    return .{ .context = &no_child_context, .vtable = &no_child_vtable };
}

pub const LiveCodex = struct {
    adapter: codex.Adapter,
    connection: *transport.Connection,
    workspace: *codex.Workspace,
    lifecycle: ChildLifecycle = noChildLifecycle(),

    close_when_done: bool = true,
};

pub const LiveAdapters = union(enum) {
    codex: LiveCodex,

    pub fn provider(_: LiveAdapters) domain.Provider {
        return .codex;
    }
};

pub const RuntimeTarget = struct {
    codex_executable: []const u8 = "",
    codex_cli_version: []const u8 = "unknown",

    pub fn executableFor(self: RuntimeTarget, provider: domain.Provider) []const u8 {
        return switch (provider) {
            .codex => self.codex_executable,
            .claude => "",
        };
    }

    pub fn versionFor(self: RuntimeTarget, provider: domain.Provider) []const u8 {
        return switch (provider) {
            .codex => self.codex_cli_version,
            .claude => "unknown",
        };
    }
};

pub const Config = struct {
    layout: runtime_paths.Layout,
    target: RuntimeTarget = .{},
    max_preflight_age_s: i64 = default_max_preflight_age_s,
};

pub const Coordinator = struct {
    allocator: std.mem.Allocator,
    config: Config,

    registry: account_registry.Registry = .{},
    snapshots: SnapshotBook = .{},
    ledger: AttemptLedger = .{},
    scheduler: OperationScheduler = .{},
    reset: ResetEngine = .{},

    profile_scratch: [max_accounts]domain.AccountProfile = @splat(.{
        .id = "",
        .provider = .codex,
        .display_name = "",
        .storage_key = "",
    }),
    snapshot_scratch: [max_accounts]domain.UsageSnapshot = @splat(.{
        .account_id = "",
        .provider = .codex,
        .captured_at_unix_s = 0,
        .status = .unavailable,
    }),
    account_scratch: [max_accounts]account_registry.Account = @splat(.{
        .id = "",
        .provider = .codex,
        .label = "",
        .storage_key = "",
        .created_at_unix_s = 0,
    }),

    pub fn create(allocator: std.mem.Allocator, config: Config) error{OutOfMemory}!*Coordinator {
        const self = try allocator.create(Coordinator);
        self.* = .{ .allocator = allocator, .config = config };
        return self;
    }

    pub fn destroy(self: *Coordinator) void {
        const allocator = self.allocator;
        allocator.destroy(self);
    }

    pub fn accountCount(self: *const Coordinator) usize {
        return self.registry.accountCount();
    }

    pub fn accountAt(self: *const Coordinator, index: usize) ?account_registry.Account {
        return self.registry.at(index);
    }

    pub fn account(self: *const Coordinator, account_id: []const u8) ?account_registry.Account {
        return self.registry.get(account_id);
    }

    pub fn addAccount(self: *Coordinator, draft: account_registry.Draft) account_registry.AddError!usize {
        _ = self.config.layout.profileDir(draft.storage_key) catch return error.InvalidStorageKey;
        return self.registry.add(draft);
    }

    pub fn moveAccount(self: *Coordinator, account_id: []const u8, new_index: usize) error{ UnknownAccount, SchedulerBusy }!void {
        if (!self.schedulerIsIdle()) return error.SchedulerBusy;
        const from = self.registry.indexOf(account_id) orelse return error.UnknownAccount;
        const count = self.registry.accountCount();
        if (count == 0) return error.UnknownAccount;
        const to = @min(new_index, count - 1);
        if (from == to) return;
        self.registry.move(account_id, to) catch return error.UnknownAccount;

        self.snapshots.move(from, to);
        self.scheduler.moveRuntime(from, to);
    }

    pub fn providerHome(self: *const Coordinator, account_id: []const u8) error{ UnknownAccount, InvalidAccountHome }!runtime_paths.Path {
        const value = self.registry.get(account_id) orelse return error.UnknownAccount;
        return self.config.layout.providerHome(value.provider, value.storage_key) catch
            return error.InvalidAccountHome;
    }

    pub fn profilePaths(self: *const Coordinator, account_id: []const u8) error{ UnknownAccount, InvalidAccountHome }!runtime_paths.ProfilePaths {
        const value = self.registry.get(account_id) orelse return error.UnknownAccount;
        return self.config.layout.profilePaths(value.storage_key) catch return error.InvalidAccountHome;
    }

    pub fn writeAccountLoginSpec(
        self: *const Coordinator,
        out: *LoginSpec,
        account_id: []const u8,
        parent_env: transport.ParentEnv,
    ) LoginSpecError!void {
        const value = self.registry.get(account_id) orelse return error.UnknownAccount;
        const home = self.config.layout.providerHome(value.provider, value.storage_key) catch
            return error.InvalidAccountHome;
        try writeLoginSpec(out, .{
            .provider = value.provider,
            .account_id = value.id,
            .executable = self.config.target.executableFor(value.provider),
            .home = home.slice(),
            .parent_env = parent_env,
            .app_root = &self.config.layout,
        });
    }

    pub fn beginLogin(
        self: *Coordinator,
        account_id: []const u8,
        purpose: LoginPurpose,
        surface: Surface,
        now_unix_s: i64,
    ) LoginBeginError!LoginSession {
        if (surface != .details) return error.SurfaceNotAllowed;
        const index = self.registry.indexOf(account_id) orelse return error.UnknownAccount;
        const value = self.registry.at(index).?;
        if (!value.enabled) return error.AccountDisabled;
        if (self.ledger.pendingIndexFor(value.id) != null) return error.PendingAttempt;

        const home = self.config.layout.providerHome(value.provider, value.storage_key) catch
            return error.InvalidAccountHome;

        try self.scheduler.reserveAccount(self.registry.accountCount(), index);
        const operation_id = self.scheduler.takeOperationId();
        return .{
            .account_index = @intCast(index),
            .account_id = value.id,
            .provider = value.provider,
            .purpose = purpose,
            .surface = surface,
            .operation_id = operation_id,
            .started_at_unix_s = now_unix_s,
            .auth_revision = value.auth_revision,
            .home = home,
        };
    }

    pub fn writeSessionLoginSpec(
        self: *const Coordinator,
        session: *const LoginSession,
        out: *LoginSpec,
        parent_env: transport.ParentEnv,
    ) LoginSpecError!void {
        if (session.stage != .running) return error.UnknownAccount;
        try self.writeAccountLoginSpec(out, session.account_id, parent_env);
    }

    pub fn applyLoginResult(
        self: *Coordinator,
        session: *LoginSession,
        status: LoginStatus,
        now_unix_s: i64,
        sink: DocumentSink,
    ) LoginApplyError!LoginReport {
        if (session.stage != .running) return error.SessionClosed;
        const index = session.account_index;
        if (index >= self.registry.accountCount()) return error.UnknownAccount;
        const value = self.registry.at(index).?;
        if (!std.mem.eql(u8, value.id, session.account_id)) return error.UnknownAccount;

        if (!status.belongsTo(session.provider, session.account_id)) return error.UnknownOperation;

        session.stage = .finished;
        self.scheduler.releaseAccount(index);
        const runtime = self.scheduler.runtimeAt(index);
        runtime.last_attempt_at_unix_s = now_unix_s;
        const registry_revision = self.registry.revision;

        var report: LoginReport = .{
            .account_id = value.id,
            .provider = value.provider,
            .purpose = session.purpose,
            .operation_id = session.operation_id,
            .phase = status.phase,
            .exit = status.exit,
            .auth_state = value.auth_state,
            .auth_revision = value.auth_revision,
            .child_closed = status.child_closed,
        };

        if (status.endedCleanly()) {
            runtime.refresh = .{};
            runtime.last_attempt_code = null;
            if (value.auth_state == .reauth_required) {
                report.auth_revision = self.registry.markAuthState(value.id, .unavailable) catch {
                    report.public_code = public_code_account_unknown;
                    return report;
                };
                report.auth_state = .unavailable;
                report.auth_state_changed = true;
            }
        } else {
            report.public_code = canonicalPublicCode(
                status.public_code orelse login_runtime.public_code_login_rejected,
            );
            runtime.last_attempt_code = report.public_code;
        }

        if (self.registry.revision != registry_revision) {
            self.persistRegistry(sink) catch |err| {
                report.persist_code = sinkErrorCode(err);
            };
        }
        return report;
    }

    pub fn closeLoginSession(self: *Coordinator, session: *LoginSession) void {
        if (session.stage == .closed) return;
        const was_running = session.stage == .running;
        session.stage = .closed;
        if (was_running) self.scheduler.releaseAccount(session.account_index);
    }

    pub fn snapshotAt(self: *const Coordinator, index: usize) ?domain.UsageSnapshot {
        if (index >= self.registry.accountCount()) return null;
        const value = self.registry.at(index).?;
        return self.snapshots.snapshotAt(index, value.id);
    }

    pub fn snapshotFor(self: *const Coordinator, account_id: []const u8) ?domain.UsageSnapshot {
        return self.snapshotAt(self.registry.indexOf(account_id) orelse return null);
    }

    pub fn statusAt(self: *const Coordinator, index: usize) ?AccountStatus {
        if (index >= self.registry.accountCount()) return null;
        const value = self.registry.at(index).?;
        const runtime = self.scheduler.runtimeAtConst(index).*;
        const snapshot = self.snapshots.stateAt(index);
        return .{
            .account_id = value.id,
            .provider = value.provider,
            .label = value.label,
            .enabled = value.enabled,
            .auth_state = value.auth_state,
            .auth_revision = value.auth_revision,
            .phase = runtime.refresh.phase,
            .operation_in_flight = runtime.reserved,
            .queued = runtime.queued,
            .last_attempt_at_unix_s = runtime.last_attempt_at_unix_s,
            .last_success_at_unix_s = runtime.last_success_at_unix_s,
            .last_attempt_code = runtime.last_attempt_code,
            .has_snapshot = snapshot.present,
            .snapshot_captured_at_unix_s = if (snapshot.present) snapshot.captured_at_unix_s else null,
        };
    }

    pub fn statusFor(self: *const Coordinator, account_id: []const u8) ?AccountStatus {
        return self.statusAt(self.registry.indexOf(account_id) orelse return null);
    }

    pub fn rowAt(self: *const Coordinator, index: usize, now_unix_s: i64) ?Row {
        if (index >= self.registry.accountCount()) return null;
        const value = self.registry.at(index).?;
        const runtime = self.scheduler.runtimeAtConst(index).*;
        const snapshot = self.snapshots.stateAt(index);
        const window = self.snapshots.mostConstrainingWindowAt(index);

        var row: Row = .{
            .account_id = value.id,
            .label = value.label,
            .provider_email = value.provider_email,
            .plan_label = value.plan_label,
            .provider = value.provider,
            .enabled = value.enabled,
            .auth_state = value.auth_state,
            .freshness = .never_refreshed,
            .snapshot_status = if (snapshot.present) snapshot.status else null,
            .snapshot_captured_at_unix_s = if (snapshot.present) snapshot.captured_at_unix_s else null,
            .last_attempt_at_unix_s = runtime.last_attempt_at_unix_s,
            .last_success_at_unix_s = runtime.last_success_at_unix_s,
            .last_attempt_code = runtime.last_attempt_code,
            .window = window,
            .operation_in_flight = runtime.reserved,
            .queued = runtime.queued,
        };
        if (snapshot.credits) |credits| {
            row.reset_credit_count = credits.authoritativeCount();
            row.credit_detail_status = credits.detail_status;
        }
        row.countdown = countdownFor(window, now_unix_s);
        row.freshness = freshnessFor(snapshot, runtime, value, row.countdown);
        return row;
    }

    pub fn rowFor(self: *const Coordinator, account_id: []const u8, now_unix_s: i64) ?Row {
        return self.rowAt(self.registry.indexOf(account_id) orelse return null, now_unix_s);
    }

    pub fn countdownAt(self: *const Coordinator, index: usize, now_unix_s: i64) ?Countdown {
        if (index >= self.registry.accountCount()) return null;
        return countdownFor(self.snapshots.mostConstrainingWindowAt(index), now_unix_s);
    }

    pub fn inFlightCount(self: *const Coordinator) usize {
        return self.scheduler.inFlightCount();
    }

    pub fn queuedCount(self: *const Coordinator) usize {
        return self.scheduler.queuedCount();
    }

    pub fn schedulerIsIdle(self: *const Coordinator) bool {
        return self.scheduler.isIdle();
    }

    pub fn requestRefresh(self: *Coordinator, account_id: []const u8) AdmitError!EnqueueOutcome {
        const index = self.registry.indexOf(account_id) orelse return error.UnknownAccount;
        const value = self.registry.at(index).?;
        if (!value.enabled) return error.AccountDisabled;
        return self.scheduler.enqueue(index, .user_refresh);
    }

    pub fn requestSignInRefresh(self: *Coordinator, account_id: []const u8) AdmitError!EnqueueOutcome {
        const index = self.registry.indexOf(account_id) orelse return error.UnknownAccount;
        const value = self.registry.at(index).?;
        if (!value.enabled) return error.AccountDisabled;
        return self.scheduler.enqueue(index, .sign_in_refresh);
    }

    pub fn requestRefreshAll(self: *Coordinator) RefreshAllPlan {
        return self.requestRefreshAllForProvider(null);
    }

    pub fn requestRefreshAllForProvider(self: *Coordinator, provider: ?domain.Provider) RefreshAllPlan {
        var plan: RefreshAllPlan = .{};
        var index: usize = 0;
        while (index < self.registry.accountCount()) : (index += 1) {
            const value = self.registry.at(index).?;
            if (provider) |allowed| {
                if (value.provider != allowed) continue;
            }
            if (!value.enabled) {
                plan.skipped_disabled += 1;
                continue;
            }
            switch (self.scheduler.enqueue(index, .user_refresh) catch {
                plan.already_pending += 1;
                continue;
            }) {
                .queued => plan.queued += 1,
                .already_pending => plan.already_pending += 1,
            }
        }
        return plan;
    }

    pub fn nextOperation(self: *Coordinator, now_unix_s: i64) ?Ticket {
        return self.scheduler.nextOperation(&self.registry, now_unix_s);
    }

    pub fn abandonOperation(self: *Coordinator, ticket: Ticket, now_unix_s: i64, code: []const u8) void {
        const index = ticket.account_index;
        if (index >= self.registry.accountCount()) return;
        const runtime = self.scheduler.runtimeAt(index);
        if (runtime.refresh.operation_id != ticket.operation_id) return;
        runtime.refresh.fail(ticket.operation_id, now_unix_s, refreshError(.unknown, code, true)) catch {};
        runtime.last_attempt_code = canonicalPublicCode(code);
        if (!ticket.retains_account) self.scheduler.releaseAccount(index);
    }

    pub fn applyObservation(
        self: *Coordinator,
        ticket: Ticket,
        observation: Observation,
        now_unix_s: i64,
    ) error{UnknownOperation}!RefreshReport {
        const index = ticket.account_index;
        if (index >= self.registry.accountCount()) return error.UnknownOperation;
        const runtime = self.scheduler.runtimeAt(index);
        if (runtime.refresh.phase != .refreshing or runtime.refresh.operation_id != ticket.operation_id) {
            return error.UnknownOperation;
        }
        const value = self.registry.at(index).?;

        var report: RefreshReport = .{
            .operation_id = ticket.operation_id,
            .account_id = value.id,
            .provider = value.provider,
            .phase = .idle,
            .reached_provider = true,
        };

        switch (observation) {
            .supported => |supported| {
                var sanitized = supported;
                sanitized.partial_failure = if (supported.partial_failure) |failure| sanitizeRefreshError(failure) else null;
                self.snapshots.replace(
                    index,
                    value.provider,
                    sanitized,
                    refreshError(.malformed_response, public_code_snapshot_capacity, true),
                );
                const snapshot = self.snapshots.stateAt(index);
                runtime.refresh.succeed(ticket.operation_id, now_unix_s) catch {};
                runtime.last_success_at_unix_s = snapshot.captured_at_unix_s;
                runtime.last_attempt_code = if (snapshot.failure) |failure| failure.public_code else null;
                report.phase = .succeeded;
                report.replaced_snapshot = true;
                report.windows_stored = snapshot.window_count;
                report.public_code = runtime.last_attempt_code;
                if (snapshot.credits) |credits| report.credits_available = credits.authoritativeCount();

                _ = self.registry.markAuthState(value.id, .connected) catch {};
            },
            .failure => |failure| {
                const sanitized = sanitizeRefreshError(failure.failure);
                runtime.last_attempt_code = sanitized.public_code;
                report.public_code = sanitized.public_code;
                report.retained_previous = self.snapshots.stateAt(index).present;
                if (sanitized.kind == .authentication) {
                    runtime.refresh.requireReauth(ticket.operation_id, now_unix_s, sanitized) catch {};
                    report.phase = .reauth_required;
                    _ = self.registry.markAuthState(value.id, .reauth_required) catch {};
                } else {
                    runtime.refresh.fail(ticket.operation_id, now_unix_s, sanitized) catch {};
                    report.phase = .failed;
                }
            },
            .deferred => {
                runtime.refresh.markDeferred();
                runtime.last_attempt_code = null;
                report.phase = .deferred;
                report.retained_previous = self.snapshots.stateAt(index).present;
            },
        }

        if (!ticket.retains_account) self.scheduler.releaseAccount(index);
        return report;
    }

    pub fn runRefresh(
        self: *Coordinator,
        ticket: Ticket,
        live: LiveAdapters,
        now_unix_s: i64,
        sink: DocumentSink,
    ) RefreshReport {
        const live_codex = switch (live) {
            .codex => |value| value,
        };
        defer if (live_codex.close_when_done) live_codex.lifecycle.close();

        if (live.provider() != ticket.provider) {
            return self.rejectOperation(ticket, now_unix_s, public_code_provider_mismatch);
        }

        const registry_revision = self.registry.revision;
        const observation = self.observeCodex(ticket, live_codex, now_unix_s) catch |err| {
            return self.rejectOperation(ticket, now_unix_s, switch (err) {
                error.UnknownAccount => public_code_account_unknown,
                error.InvalidAccountHome => public_code_account_home_invalid,
                error.HomeMismatch => public_code_home_mismatch,
            });
        };

        var report = self.applyObservation(ticket, observation, now_unix_s) catch {
            return .{
                .operation_id = ticket.operation_id,
                .account_id = ticket.account_id,
                .provider = ticket.provider,
                .phase = .idle,
                .public_code = public_code_operation_unknown,
            };
        };
        if (report.replaced_snapshot) {
            self.persistSnapshots(sink) catch |err| {
                report.persist_code = sinkErrorCode(err);
            };
        }
        if (self.registry.revision != registry_revision) {
            self.persistRegistry(sink) catch |err| {
                if (report.persist_code == null) report.persist_code = sinkErrorCode(err);
            };
        }
        return report;
    }

    pub fn recordProviderMetadata(
        self: *Coordinator,
        account_id: []const u8,
        metadata: account_registry.ProviderMetadata,
    ) (account_registry.LookupError || account_registry.ValidationError || error{TextStorageFull})!void {
        try self.registry.setProviderMetadata(account_id, metadata);
    }

    pub fn openResetSession(
        self: *Coordinator,
        account_id: []const u8,
        surface: Surface,
        now_unix_s: i64,
    ) SessionError!ResetSession {
        if (surface != .details) return error.SurfaceNotAllowed;
        const index = self.registry.indexOf(account_id) orelse return error.UnknownAccount;
        const value = self.registry.at(index).?;
        if (value.provider != .codex) return error.ProviderMismatch;
        if (!value.enabled) return error.AccountDisabled;
        if (value.auth_state != .connected) return error.AuthStateNotConnected;
        if (self.ledger.pendingIndexFor(value.id) != null) return error.PendingAttempt;
        try self.scheduler.reserveAccount(self.registry.accountCount(), index);
        return .{
            .account_index = @intCast(index),
            .account_id = value.id,
            .surface = surface,
            .opened_at_unix_s = now_unix_s,
            .auth_revision = value.auth_revision,
        };
    }

    pub fn reopenResetSession(
        self: *Coordinator,
        account_id: []const u8,
        idempotency_key: []const u8,
        surface: Surface,
        now_unix_s: i64,
    ) SessionError!ResetSession {
        if (surface != .details) return error.SurfaceNotAllowed;
        const index = self.registry.indexOf(account_id) orelse return error.UnknownAccount;
        const value = self.registry.at(index).?;
        if (value.provider != .codex) return error.ProviderMismatch;
        if (!value.enabled) return error.AccountDisabled;
        if (value.auth_state != .connected) return error.AuthStateNotConnected;

        const pending = self.ledger.retryableIndexFor(value.id) orelse return error.SessionClosed;
        const attempt = self.ledger.attemptAt(pending);
        if (!std.mem.eql(u8, attempt.idempotency_key, idempotency_key)) return error.PendingAttempt;

        try self.scheduler.reserveAccount(self.registry.accountCount(), index);
        return .{
            .account_index = @intCast(index),
            .account_id = value.id,
            .surface = surface,
            .opened_at_unix_s = now_unix_s,
            .auth_revision = value.auth_revision,

            .idempotency_key = self.ledger.attemptAt(pending).idempotency_key,
        };
    }

    pub fn beginSessionStep(
        self: *Coordinator,
        session: *ResetSession,
        purpose: Purpose,
        now_unix_s: i64,
    ) error{ SessionClosed, AccountBusy, UnknownAccount }!Ticket {
        if (session.stage == .closed) return error.SessionClosed;
        const index = session.account_index;
        if (index >= self.registry.accountCount()) return error.UnknownAccount;
        const value = self.registry.at(index).?;
        const runtime = self.scheduler.runtimeAt(index);
        const operation_id = self.scheduler.takeOperationId();
        runtime.refresh.begin(operation_id, now_unix_s) catch return error.AccountBusy;
        runtime.last_attempt_at_unix_s = now_unix_s;
        runtime.last_attempt_code = null;
        return .{
            .operation_id = operation_id,
            .account_index = index,
            .account_id = value.id,
            .provider = value.provider,
            .started_at_unix_s = now_unix_s,
            .purpose = purpose,
            .retains_account = true,
        };
    }

    pub fn closeResetSession(self: *Coordinator, session: *ResetSession, lifecycle: ChildLifecycle) void {
        if (session.stage == .closed) return;
        session.stage = .closed;
        self.scheduler.releaseAccount(session.account_index);
        lifecycle.close();
    }

    pub fn prepareResetOffer(self: *Coordinator, session: *ResetSession, now_unix_s: i64) OfferError!ResetOffer {
        if (session.stage == .closed) return error.SessionClosed;
        if (session.surface != .details) return error.SurfaceNotAllowed;
        const index = session.account_index;
        if (index >= self.registry.accountCount()) return error.UnknownAccount;
        const value = self.registry.at(index).?;
        if (value.provider != .codex) return error.ProviderMismatch;
        if (value.auth_state != .connected) return error.AuthStateNotConnected;
        if (self.ledger.pendingIndexFor(value.id)) |pending| {
            if (!std.mem.eql(u8, self.ledger.attemptAt(pending).idempotency_key, session.idempotency_key)) {
                return error.PendingAttempt;
            }
        }

        const offer = try self.reset.prepareOffer(.{
            .account = value,
            .refresh_phase = self.scheduler.runtimeAtConst(index).refresh.phase,
            .snapshot = self.snapshots.stateAt(index),
            .registry_revision = self.registry.revision,
            .snapshot_revision = self.snapshots.revisionValue(),
            .surface = session.surface,
            .now_unix_s = now_unix_s,
            .max_preflight_age_s = self.config.max_preflight_age_s,
            .layout = &self.config.layout,
            .codex_executable = self.config.target.executableFor(.codex),
            .codex_cli_version = self.config.target.versionFor(.codex),
        });

        session.stage = .offered;
        session.offer_revision = offer.revision;
        session.auth_revision = value.auth_revision;
        return offer;
    }

    pub fn confirmResetOffer(
        self: *Coordinator,
        session: *ResetSession,
        offer: ResetOffer,
        now_unix_s: i64,
    ) error{ SessionClosed, OfferChanged, ConfirmationBeforePreflight, StalePreflight }!Confirmation {
        return self.reset.confirmOffer(session, offer, now_unix_s, self.config.max_preflight_age_s);
    }

    pub const BeginResetOptions = struct {
        session: *ResetSession,
        confirmation: Confirmation,

        idempotency_key: []const u8,
        now_unix_s: i64,
        sink: DocumentSink,
    };

    pub fn beginResetAttempt(self: *Coordinator, options: BeginResetOptions) ResetBeginError!*const domain.ResetAttempt {
        const session = options.session;
        if (session.stage == .closed) return error.SessionClosed;
        if (session.stage != .confirmed) return error.OfferChanged;
        if (session.surface != .details) return error.SurfaceNotAllowed;

        const confirmation = options.confirmation;
        if (!std.mem.eql(u8, confirmation.account_id, session.account_id)) return error.OfferChanged;
        if (confirmation.surface != .details) return error.SurfaceNotAllowed;
        if (confirmation.offer_revision != session.offer_revision) return error.OfferChanged;

        const index = session.account_index;
        if (index >= self.registry.accountCount()) return error.UnknownAccount;
        const value = self.registry.at(index).?;
        if (value.provider != .codex) return error.ProviderMismatch;
        if (!std.mem.eql(u8, value.id, confirmation.account_id)) return error.UnknownAccount;
        if (value.auth_state != .connected) return error.AuthStateNotConnected;
        if (value.auth_revision != confirmation.auth_revision) return error.AuthRevisionChanged;
        if (self.ledger.pendingIndexFor(value.id) != null) return error.PendingAttempt;

        const current = self.recomputeOffer(index, session.surface, options.now_unix_s) catch |err| return switch (err) {
            error.NoCredit => error.NoCredit,
            error.StalePreflight => error.StalePreflight,
            error.NoSnapshot => error.NoSnapshot,
            error.PreflightMissing => error.PreflightMissing,
            error.InvalidAccountHome => error.InvalidAccountHome,
            error.AuthStateNotConnected => error.AuthStateNotConnected,
            error.PendingAttempt => error.PendingAttempt,
            error.ProviderMismatch => error.ProviderMismatch,
            error.SurfaceNotAllowed => error.SurfaceNotAllowed,
            error.SessionClosed => error.SessionClosed,
            error.UnknownAccount => error.UnknownAccount,
        };
        if (current.revision != confirmation.offer_revision) return error.OfferChanged;
        if (current.available_count == 0) return error.NoCredit;

        var attempt = domain.ResetAttempt.init(
            options.idempotency_key,
            value.id,
            confirmation.selected_credit_id,
            confirmation.preflight_observed_at_unix_s,
            confirmation.available_count,
            confirmation.confirmed_at_unix_s,
        ) catch |err| return switch (err) {
            error.InvalidIdempotencyKey => error.InvalidKey,
            error.InvalidAccount => error.UnknownAccount,
            error.NoCredit => error.NoCredit,
            error.ConfirmationBeforePreflight => error.ConfirmationBeforePreflight,
        };

        const ledger_index = self.ledger.append(attempt) catch |err| return switch (err) {
            error.LedgerFull => error.LedgerFull,
            error.DuplicateKey => error.DuplicateKey,
            error.TextStorageFull => error.TextStorageFull,
            error.InvalidKey, error.UnknownKey => error.InvalidKey,
        };

        self.persistLedger(options.sink) catch {
            self.ledger.dropLast();
            return error.LedgerUnavailable;
        };

        const persisted = self.ledger.attemptAt(ledger_index);
        attempt = persisted;
        attempt.markSubmitted(options.now_unix_s, self.config.max_preflight_age_s) catch |err| return switch (err) {
            error.StalePreflight => error.StalePreflight,
            error.InvalidTransition => error.OfferChanged,
        };
        self.ledger.updateAt(ledger_index, attempt);
        self.persistLedger(options.sink) catch {
            self.ledger.updateAt(ledger_index, persisted);
            return error.LedgerUnavailable;
        };

        session.stage = .submitted;
        session.idempotency_key = self.ledger.attemptAt(ledger_index).idempotency_key;
        return self.ledger.attemptPtrAt(ledger_index);
    }

    pub fn applyResetOutcome(
        self: *Coordinator,
        session: *ResetSession,
        outcome: codex.ConsumeOutcome,
        now_unix_s: i64,
        sink: DocumentSink,
    ) error{ SessionClosed, UnknownKey, InvalidTransition }!ResetResolution {
        if (session.stage == .closed) return error.SessionClosed;
        if (session.stage != .submitted) return error.InvalidTransition;
        const ledger_index = self.ledger.indexOfKey(session.idempotency_key) orelse return error.UnknownKey;

        var attempt = self.ledger.attemptAt(ledger_index);
        var resolution: ResetResolution = .{
            .idempotency_key = attempt.idempotency_key,
            .account_id = attempt.account_id,
            .phase = attempt.phase,
            .credit_may_have_been_spent = outcome.requestWasSent(),
        };

        switch (outcome) {
            .completed => |provider_outcome| {
                attempt.complete(provider_outcome, now_unix_s) catch return error.InvalidTransition;
                resolution.outcome = provider_outcome;

                resolution.requires_post_read = true;
            },
            .ambiguous => |failure| {
                attempt.markAmbiguous(now_unix_s) catch return error.InvalidTransition;
                resolution.public_code = canonicalPublicCode(failure.public_code);

                resolution.requires_post_read = true;
                resolution.may_retry_same_key = true;
            },
            .rejected => |failure| {
                attempt.markNotSent(now_unix_s) catch return error.InvalidTransition;
                resolution.public_code = canonicalPublicCode(failure.public_code);
                resolution.may_retry_same_key = true;
            },
        }

        self.ledger.updateAt(ledger_index, attempt);
        resolution.phase = self.ledger.attemptAt(ledger_index).phase;
        resolution.outcome = self.ledger.attemptAt(ledger_index).outcome;
        self.persistLedger(sink) catch |err| {
            resolution.persist_code = sinkErrorCode(err);
        };
        session.stage = .settled;
        return resolution;
    }

    pub const RetryOptions = struct {
        session: *ResetSession,

        offer: ResetOffer,
        now_unix_s: i64,
        sink: DocumentSink,
    };

    pub fn prepareSameKeyRetry(self: *Coordinator, options: RetryOptions) ResetBeginError!*const domain.ResetAttempt {
        const session = options.session;
        if (session.stage == .closed) return error.SessionClosed;
        if (session.surface != .details) return error.SurfaceNotAllowed;
        if (session.idempotency_key.len == 0) return error.InvalidKey;
        const ledger_index = self.ledger.indexOfKey(session.idempotency_key) orelse return error.InvalidKey;

        const previous = self.ledger.attemptAt(ledger_index);
        if (previous.outcome != null) return error.OfferChanged;
        if (previous.phase != .ambiguous and previous.phase != .submitted and previous.phase != .not_sent) return error.OfferChanged;

        const index = session.account_index;
        if (index >= self.registry.accountCount()) return error.UnknownAccount;
        const value = self.registry.at(index).?;
        if (value.auth_revision != options.offer.auth_revision) return error.AuthRevisionChanged;
        if (!std.mem.eql(u8, options.offer.account_id, previous.account_id)) return error.OfferChanged;
        if (session.offer_revision != options.offer.revision) return error.OfferChanged;

        previous.assertSameOperation(options.offer.account_id, previous.selected_credit_id) catch
            return error.OfferChanged;
        if (!options.offer.isFresh(options.now_unix_s, self.config.max_preflight_age_s)) return error.StalePreflight;

        var retry = domain.ResetAttempt.init(
            previous.idempotency_key,
            previous.account_id,
            previous.selected_credit_id,
            options.offer.observed_at_unix_s,
            options.offer.available_count,
            options.now_unix_s,
        ) catch |err| return switch (err) {
            error.InvalidIdempotencyKey => error.InvalidKey,
            error.InvalidAccount => error.UnknownAccount,
            error.NoCredit => error.NoCredit,
            error.ConfirmationBeforePreflight => error.ConfirmationBeforePreflight,
        };

        retry.created_at_unix_s = previous.created_at_unix_s;
        retry.markSubmitted(options.now_unix_s, self.config.max_preflight_age_s) catch |err| return switch (err) {
            error.StalePreflight => error.StalePreflight,
            error.InvalidTransition => error.OfferChanged,
        };

        self.ledger.updateAt(ledger_index, retry);
        self.persistLedger(options.sink) catch {
            self.ledger.updateAt(ledger_index, previous);
            return error.LedgerUnavailable;
        };
        session.stage = .submitted;
        return self.ledger.attemptPtrAt(ledger_index);
    }

    pub fn planLedgerRecovery(self: *const Coordinator) RecoveryPlan {
        return self.reset.planRecovery(self.ledger.slice(), &self.registry);
    }

    pub fn discardPreparedAttempt(self: *Coordinator, key: []const u8, sink: DocumentSink) error{ UnknownKey, InvalidTransition, LedgerUnavailable }!void {
        const index = self.ledger.indexOfKey(key) orelse return error.UnknownKey;
        if (self.ledger.attemptAt(index).phase != .prepared) return error.InvalidTransition;
        if (index != self.ledger.countValue() - 1) return error.InvalidTransition;
        const previous = self.ledger.attemptAt(index);
        self.ledger.dropLast();
        self.persistLedger(sink) catch {
            _ = self.ledger.append(previous) catch {};
            return error.LedgerUnavailable;
        };
    }

    pub fn attempts(self: *const Coordinator) []const domain.ResetAttempt {
        return self.ledger.slice();
    }

    pub fn attemptByKey(self: *const Coordinator, key: []const u8) ?*const domain.ResetAttempt {
        const index = self.ledger.indexOfKey(key) orelse return null;
        return self.ledger.attemptPtrAt(index);
    }

    pub fn pendingAttemptFor(self: *const Coordinator, account_id: []const u8) ?*const domain.ResetAttempt {
        const index = self.ledger.pendingIndexFor(account_id) orelse return null;
        return self.ledger.attemptPtrAt(index);
    }

    pub fn unsentAttemptFor(self: *const Coordinator, account_id: []const u8) ?*const domain.ResetAttempt {
        const index = self.ledger.unsentIndexFor(account_id) orelse return null;
        return self.ledger.attemptPtrAt(index);
    }

    pub fn retryableAttemptFor(self: *const Coordinator, account_id: []const u8) ?*const domain.ResetAttempt {
        const index = self.ledger.retryableIndexFor(account_id) orelse return null;
        return self.ledger.attemptPtrAt(index);
    }

    pub fn planAccountRemoval(self: *const Coordinator, account_id: []const u8) error{UnknownAccount}!CleanupPlan {
        const index = self.registry.indexOf(account_id) orelse return error.UnknownAccount;
        const value = self.registry.at(index).?;
        return self.reset.planAccountRemoval(.{
            .account = value,
            .removes_snapshot = self.snapshots.stateAt(index).present,
            .attempts = self.ledger.slice(),
            .has_pending_attempt = self.ledger.pendingIndexFor(value.id) != null,
            .scheduler_idle = self.schedulerIsIdle(),
            .layout = &self.config.layout,
            .attempt_pending_code = public_code_attempt_pending,
            .account_busy_code = public_code_account_busy,
        });
    }

    pub fn applyAccountRemoval(
        self: *Coordinator,
        plan: CleanupPlan,
        confirmation: CleanupConfirmation,
        credentials: ?keychain.CredentialStore,
        sink: DocumentSink,
    ) CleanupError!CleanupResult {
        if (!std.mem.eql(u8, plan.account_id, confirmation.account_id)) return error.ConfirmationMismatch;
        if (!plan.isExecutable()) return error.Blocked;
        const index = self.registry.indexOf(plan.account_id) orelse return error.UnknownAccount;
        const value = self.registry.at(index).?;
        if (!self.schedulerIsIdle()) return error.Blocked;
        if (self.ledger.pendingIndexFor(value.id) != null) return error.Blocked;

        var result: CleanupResult = .{
            .account_id = value.id,
            .retained_attempts = plan.retained_attempts,
            .directories_pending = plan.directory_count,
        };

        if (confirmation.delete_credentials) {
            const store_value = credentials orelse return error.CredentialStoreMissing;
            const account_key = value.accountKey() catch return error.UnknownAccount;
            for (plan.credential_slots) |slot| {
                store_value.remove(&account_key, slot) catch |err| {
                    result.store_failure_code = canonicalPublicCode(oauth.refreshErrorFromStore(err).public_code);
                    return error.CredentialRemovalFailed;
                };
                result.removed_credential_slots += 1;
            }
            _ = self.registry.markCredentialsRemoved(value.id) catch {};
        }

        result.removed_snapshot = self.snapshots.stateAt(index).present;
        self.forgetAccountState(index);
        self.registry.remove(plan.account_id) catch return error.UnknownAccount;
        result.removed_registry_entry = true;

        self.persistRegistry(sink) catch |err| {
            result.persist_code = sinkErrorCode(err);
        };
        self.persistSnapshots(sink) catch |err| {
            if (result.persist_code == null) result.persist_code = sinkErrorCode(err);
        };
        return result;
    }

    pub fn snapshotDocument(self: *Coordinator) store.SnapshotDocument {
        var snapshots: usize = 0;
        var index: usize = 0;
        while (index < self.registry.accountCount()) : (index += 1) {
            const value = self.registry.at(index).?;
            self.profile_scratch[index] = value.profile();
            if (self.snapshots.snapshotAt(index, value.id)) |snapshot| {
                self.snapshot_scratch[snapshots] = snapshot;
                snapshots += 1;
            }
        }
        return .{
            .profiles = self.profile_scratch[0..self.registry.accountCount()],
            .snapshots = self.snapshot_scratch[0..snapshots],
        };
    }

    pub fn registryDocument(self: *Coordinator) account_registry.RegistryDocument {
        return self.registry.toDocument(self.account_scratch[0..]) catch .{};
    }

    pub fn attemptDocument(self: *const Coordinator) store.AttemptDocument {
        return .{ .attempts = self.ledger.slice() };
    }

    pub fn persistRegistry(self: *Coordinator, sink: DocumentSink) SinkError!void {
        return self.writeDocument(sink, .registry, self.registryDocument());
    }

    pub fn persistSnapshots(self: *Coordinator, sink: DocumentSink) SinkError!void {
        const document = self.snapshotDocument();
        store.validateSnapshotDocument(document) catch return error.Denied;
        return self.writeDocument(sink, .snapshots, document);
    }

    pub fn persistLedger(self: *Coordinator, sink: DocumentSink) SinkError!void {
        const document = self.attemptDocument();
        store.validateAttemptDocument(document) catch return error.Denied;
        return self.writeDocument(sink, .attempts, document);
    }

    pub fn persistAll(self: *Coordinator, sink: DocumentSink) SinkError!void {
        try self.persistRegistry(sink);
        try self.persistSnapshots(sink);
        try self.persistLedger(sink);
    }

    pub fn loadRegistryBytes(self: *Coordinator, bytes: []const u8) (account_registry.LoadError || error{Malformed})!void {
        var parsed = std.json.parseFromSlice(
            account_registry.RegistryDocument,
            self.allocator,
            bytes,
            .{ .allocate = .alloc_always },
        ) catch return error.Malformed;
        defer parsed.deinit();
        try self.registry.loadDocument(parsed.value);
        self.snapshots.clear();
        self.scheduler.clearRuntimes();
    }

    pub fn loadRegistryBytesForProvider(
        self: *Coordinator,
        bytes: []const u8,
        provider: domain.Provider,
    ) (account_registry.LoadError || error{Malformed})!void {
        var parsed = std.json.parseFromSlice(
            account_registry.RegistryDocument,
            self.allocator,
            bytes,
            .{ .allocate = .alloc_always },
        ) catch return error.Malformed;
        defer parsed.deinit();
        var accounts: [account_registry.max_accounts]account_registry.Account = undefined;
        var count: usize = 0;
        for (parsed.value.accounts) |candidate| {
            if (candidate.provider != provider) continue;
            accounts[count] = candidate;
            count += 1;
        }
        try self.registry.loadDocument(.{
            .schema_version = parsed.value.schema_version,
            .accounts = accounts[0..count],
        });
        self.snapshots.clear();
        self.scheduler.clearRuntimes();
    }

    pub fn loadSnapshotBytes(self: *Coordinator, bytes: []const u8) error{Malformed}!usize {
        var parsed = store.decodeSnapshots(self.allocator, bytes) catch return error.Malformed;
        defer parsed.deinit();
        var loaded: usize = 0;
        for (parsed.value.snapshots) |snapshot| {
            const index = self.registry.indexOf(snapshot.account_id) orelse continue;
            const value = self.registry.at(index).?;
            if (value.provider != snapshot.provider) continue;
            self.snapshots.restore(index, value.provider, .{
                .status = snapshot.status,
                .observed_at_unix_s = snapshot.captured_at_unix_s,
                .windows = snapshot.windows,
                .reset_credits = snapshot.reset_credits,
                .partial_failure = if (snapshot.refresh_error) |failure| sanitizeRefreshError(failure) else null,
            }, refreshError(.malformed_response, public_code_snapshot_capacity, true));

            self.scheduler.runtimeAt(index).last_success_at_unix_s = snapshot.captured_at_unix_s;
            self.scheduler.runtimeAt(index).refresh = .{};
            loaded += 1;
        }
        self.snapshots.finishRestore();
        return loaded;
    }

    pub fn loadAttemptBytes(self: *Coordinator, bytes: []const u8) error{Malformed}!usize {
        var parsed = store.decodeAttempts(self.allocator, bytes) catch return error.Malformed;
        defer parsed.deinit();
        self.ledger.loadDocument(parsed.value) catch return error.Malformed;
        return self.ledger.countValue();
    }

    pub fn loadFromDirectory(self: *Coordinator, io: std.Io, dir: std.Io.Dir) LoadReport {
        return self.loadFromDirectoryFiltered(io, dir, null);
    }

    pub fn loadFromDirectoryForProvider(
        self: *Coordinator,
        io: std.Io,
        dir: std.Io.Dir,
        provider: domain.Provider,
    ) LoadReport {
        return self.loadFromDirectoryFiltered(io, dir, provider);
    }

    fn loadFromDirectoryFiltered(
        self: *Coordinator,
        io: std.Io,
        dir: std.Io.Dir,
        provider: ?domain.Provider,
    ) LoadReport {
        var report: LoadReport = .{};

        if (self.readDocument(io, dir, .registry)) |bytes| {
            defer self.allocator.free(bytes);
            const loaded = if (provider) |allowed|
                self.loadRegistryBytesForProvider(bytes, allowed)
            else
                self.loadRegistryBytes(bytes);
            loaded catch |err| {
                report.registry_code = loadErrorCode(err);
            };
            report.accounts_loaded = self.registry.accountCount();
        } else |err| switch (err) {
            error.FileNotFound => {},
            else => report.registry_code = public_code_document_unreadable,
        }

        if (self.readDocument(io, dir, .snapshots)) |bytes| {
            defer self.allocator.free(bytes);
            if (self.loadSnapshotBytes(bytes)) |loaded| {
                report.snapshots_loaded = loaded;
            } else |_| {
                report.snapshots_code = public_code_document_unsupported;
            }
        } else |err| switch (err) {
            error.FileNotFound => {},
            else => report.snapshots_code = public_code_document_unreadable,
        }

        if (self.readDocument(io, dir, .attempts)) |bytes| {
            defer self.allocator.free(bytes);
            if (self.loadAttemptBytes(bytes)) |loaded| {
                report.attempts_loaded = loaded;
            } else |_| {
                report.attempts_code = public_code_document_unsupported;
            }
        } else |err| switch (err) {
            error.FileNotFound => {},
            else => report.attempts_code = public_code_document_unreadable,
        }

        return report;
    }

    fn readDocument(
        self: *Coordinator,
        io: std.Io,
        dir: std.Io.Dir,
        kind: runtime_paths.DocumentKind,
    ) ![]u8 {
        return dir.readFileAlloc(
            io,
            runtime_paths.documentFileName(kind),
            self.allocator,
            .limited(store.max_document_bytes),
        );
    }

    fn writeDocument(self: *Coordinator, sink: DocumentSink, kind: runtime_paths.DocumentKind, document: anytype) SinkError!void {
        assertCredentialFree(@TypeOf(document), 0);
        const bytes = store.encode(self.allocator, document) catch return error.TooLarge;
        defer self.allocator.free(bytes);
        return sink.write(kind, bytes);
    }

    fn rejectOperation(self: *Coordinator, ticket: Ticket, now_unix_s: i64, code: []const u8) RefreshReport {
        const canonical = canonicalPublicCode(code);
        const index = ticket.account_index;
        var report: RefreshReport = .{
            .operation_id = ticket.operation_id,
            .account_id = ticket.account_id,
            .provider = ticket.provider,
            .phase = .failed,
            .public_code = canonical,
            .reached_provider = false,
        };
        if (index >= self.registry.accountCount()) return report;
        const runtime = self.scheduler.runtimeAt(index);
        report.retained_previous = self.snapshots.stateAt(index).present;
        runtime.refresh.fail(ticket.operation_id, now_unix_s, refreshError(.unknown, canonical, false)) catch {};
        runtime.last_attempt_code = canonical;
        if (!ticket.retains_account) self.scheduler.releaseAccount(index);
        return report;
    }

    fn observeCodex(
        self: *Coordinator,
        ticket: Ticket,
        live: LiveCodex,
        now_unix_s: i64,
    ) error{ UnknownAccount, InvalidAccountHome, HomeMismatch }!Observation {
        const value = self.registry.at(ticket.account_index) orelse return error.UnknownAccount;
        const expected = self.config.layout.codexHome(value.storage_key) catch return error.InvalidAccountHome;

        if (!expected.eqlText(live.adapter.config.codex_home)) return error.HomeMismatch;

        const outcome = live.adapter.refresh(live.connection, live.workspace, .{
            .account_id = value.id,
            .now_unix_s = now_unix_s,
        });
        if (outcome.account_metadata.hasObservation()) {
            self.recordProviderMetadata(value.id, .{
                .email = outcome.account_metadata.email,
                .email_observed = outcome.account_metadata.email_observed,
                .plan_label = outcome.account_metadata.plan_label,
                .plan_observed = outcome.account_metadata.plan_observed,
            }) catch {};
        }
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
            .failure = outcome.failure orelse
                refreshError(.provider_unavailable, codex.public_code_usage_unsupported, true),
            .observed_at_unix_s = now_unix_s,
        } };
    }

    fn recomputeOffer(self: *Coordinator, index: usize, surface: Surface, now_unix_s: i64) OfferError!ResetOffer {
        const value = self.registry.at(index) orelse return error.UnknownAccount;
        return self.reset.prepareOffer(.{
            .account = value,
            .refresh_phase = self.scheduler.runtimeAtConst(index).refresh.phase,
            .snapshot = self.snapshots.stateAt(index),
            .registry_revision = self.registry.revision,
            .snapshot_revision = self.snapshots.revisionValue(),
            .surface = surface,
            .now_unix_s = now_unix_s,
            .max_preflight_age_s = self.config.max_preflight_age_s,
            .layout = &self.config.layout,
            .codex_executable = self.config.target.executableFor(.codex),
            .codex_cli_version = self.config.target.versionFor(.codex),
        });
    }

    fn forgetAccountState(self: *Coordinator, index: usize) void {
        self.snapshots.remove(index);
        self.scheduler.removeRuntime(index);
    }
};

fn loadErrorCode(err: anyerror) []const u8 {
    return switch (err) {
        error.UnsupportedSchemaVersion => public_code_document_unsupported,
        else => public_code_document_unreadable,
    };
}

fn countdownFor(window: ?domain.UsageWindow, now_unix_s: i64) Countdown {
    const value = window orelse return .{};
    const reset_at = value.reset_at_unix_s orelse return .{ .window_label = value.label };
    const remaining = reset_at - now_unix_s;
    return .{
        .window_label = value.label,
        .reset_at_unix_s = reset_at,
        .remaining_s = @max(remaining, 0),
        .passed = remaining <= 0,
    };
}

fn freshnessFor(
    snapshot: snapshot_book.State,
    runtime: Runtime,
    value: account_registry.Account,
    countdown: Countdown,
) Freshness {
    if (!snapshot.present) {
        if (value.auth_state == .reauth_required or runtime.refresh.phase == .reauth_required) {
            return .reauth_required;
        }
        return .never_refreshed;
    }
    if (runtime.refresh.phase == .reauth_required or value.auth_state == .reauth_required) return .reauth_required;
    if (runtime.refresh.phase == .deferred) return .refresh_deferred;
    if (runtime.refresh.phase == .failed) return .refresh_failed;
    if (snapshot.status == .unavailable) return .usage_unavailable;

    if (countdown.passed and countdown.reset_at_unix_s != null) return .reset_passed;
    if (runtime.refresh.phase == .succeeded) return .as_of;
    return .saved_snapshot;
}

fn isForbiddenType(comptime T: type) bool {
    return T == keychain.Credential or T == oauth.Request or
        T == oauth.RedactedRequest or T == oauth.Header or T == oauth.RefreshGrant or
        T == oauth.RefreshPayload or T == codex.Workspace or T == LiveCodex or
        T == keychain.CredentialStore;
}

fn typeIsString(comptime T: type) bool {
    return switch (@typeInfo(T)) {
        .pointer => |info| info.size == .slice and info.child == u8,
        .optional => |info| typeIsString(info.child),
        else => false,
    };
}

const forbidden_field_words = [_][]const u8{
    "token",  "secret", "credential", "password",   "bearer",
    "cookie", "header", "session",    "auth_value",
};

fn assertSerializableFieldName(comptime name: []const u8) void {
    comptime {
        @setEvalBranchQuota(20_000);
        var lowered: [name.len]u8 = undefined;
        for (name, 0..) |byte, index| lowered[index] = std.ascii.toLower(byte);
        for (forbidden_field_words) |word| {
            if (std.mem.indexOf(u8, &lowered, word) != null) {
                @compileError("serialized text field '" ++ name ++ "' is named like credential data");
            }
        }
    }
}

fn assertCredentialFree(comptime T: type, comptime depth: usize) void {
    comptime {
        if (isForbiddenType(T)) @compileError("value must not reach " ++ @typeName(T));

        if (typeIsString(T)) return;
        if (depth > 8) @compileError("type nests too deeply to verify: " ++ @typeName(T));
        switch (@typeInfo(T)) {
            .@"struct" => |info| for (info.fields) |field| {
                if (typeIsString(field.type)) assertSerializableFieldName(field.name);
                assertCredentialFree(field.type, depth + 1);
            },
            .@"union" => |info| for (info.fields) |field| {
                assertCredentialFree(field.type, depth + 1);
            },
            .optional => |info| assertCredentialFree(info.child, depth + 1),
            .array => |info| assertCredentialFree(info.child, depth + 1),
            .pointer => |info| if (info.child != u8) assertCredentialFree(info.child, depth + 1),
            else => {},
        }
    }
}

comptime {
    assertCredentialFree(store.SnapshotDocument, 0);
    assertCredentialFree(store.AttemptDocument, 0);
    assertCredentialFree(account_registry.RegistryDocument, 0);
    assertCredentialFree(RefreshReport, 0);
    assertCredentialFree(AccountStatus, 0);
    assertCredentialFree(Row, 0);
    assertCredentialFree(ResetOffer, 0);
    assertCredentialFree(Confirmation, 0);
    assertCredentialFree(ResetResolution, 0);
    assertCredentialFree(RecoveryPlan, 0);
    assertCredentialFree(CleanupPlan, 0);
    assertCredentialFree(CleanupResult, 0);
    assertCredentialFree(LoadReport, 0);
    assertCredentialFree(LoginReport, 0);
    assertCredentialFree(LoginSession, 0);

    for (login_public_codes) |code| {
        if (!std.mem.eql(u8, canonicalPublicCode(code), code)) {
            @compileError("login code is not canonical here: " ++ code);
        }
        if (!isPublicCode(code)) @compileError("login code is not a public code: " ++ code);
    }
}
