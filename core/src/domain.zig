const std = @import("std");

pub const Provider = enum { codex, claude };

pub const AccountProfile = struct {
    id: []const u8,
    provider: Provider,
    display_name: []const u8,

    storage_key: []const u8,
    enabled: bool = true,
};

pub const UsageWindowKind = enum { session, weekly, model_scoped, other };

pub const UsageWindow = struct {
    kind: UsageWindowKind,
    label: []const u8,
    used_percent: u8,
    reset_at_unix_s: ?i64 = null,
    duration_minutes: ?u32 = null,
    model_label: ?[]const u8 = null,

    pub fn isExpired(self: UsageWindow, now_unix_s: i64) bool {
        const reset_at = self.reset_at_unix_s orelse return false;
        return reset_at <= now_unix_s;
    }
};

pub const RefreshErrorKind = enum {
    authentication,
    rate_limited,
    network,
    timeout,
    malformed_response,
    provider_unavailable,
    persistence,
    unknown,
};

pub const RefreshError = struct {
    kind: RefreshErrorKind,

    public_code: []const u8,
    retryable: bool,
};

pub const SnapshotStatus = enum {
    fresh,
    stale,
    partial,
    reauth_required,
    error_state,
    unavailable,
    deferred,
};

pub const CreditDetailStatus = enum { count_only, detailed };

pub const ResetCreditDetail = struct {
    id: []const u8,
    label: []const u8,
    expires_at_unix_s: ?i64 = null,

    pub fn isExpired(self: ResetCreditDetail, now_unix_s: i64) bool {
        const expires_at = self.expires_at_unix_s orelse return false;
        return expires_at <= now_unix_s;
    }
};

pub const ResetCreditSummary = struct {
    available_count: u32,
    observed_at_unix_s: i64,
    detail_status: CreditDetailStatus,
    details: []const ResetCreditDetail = &.{},

    pub fn authoritativeCount(self: ResetCreditSummary) u32 {
        return self.available_count;
    }

    pub fn knownUnexpiredDetailCount(self: ResetCreditSummary, now_unix_s: i64) usize {
        var count: usize = 0;
        for (self.details) |detail| {
            if (!detail.isExpired(now_unix_s)) count += 1;
        }
        return count;
    }

    pub fn detailsAreComplete(self: ResetCreditSummary) bool {
        return self.detail_status == .detailed and self.details.len == self.available_count;
    }
};

pub const UsageSnapshot = struct {
    account_id: []const u8,
    provider: Provider,
    captured_at_unix_s: i64,
    status: SnapshotStatus,
    windows: []const UsageWindow = &.{},
    reset_credits: ?ResetCreditSummary = null,
    refresh_error: ?RefreshError = null,
};

pub fn replaceSnapshot(snapshots: []UsageSnapshot, replacement: UsageSnapshot) bool {
    for (snapshots) |*snapshot| {
        if (std.mem.eql(u8, snapshot.account_id, replacement.account_id)) {
            snapshot.* = replacement;
            return true;
        }
    }
    return false;
}

pub const RefreshPhase = enum {
    idle,
    refreshing,
    succeeded,
    failed,
    reauth_required,
    deferred,
    unavailable,
};

pub const RefreshState = struct {
    phase: RefreshPhase = .idle,
    operation_id: ?u64 = null,
    started_at_unix_s: ?i64 = null,
    finished_at_unix_s: ?i64 = null,
    last_error: ?RefreshError = null,

    pub fn begin(self: *RefreshState, operation_id: u64, now_unix_s: i64) error{AlreadyRefreshing}!void {
        if (self.phase == .refreshing) return error.AlreadyRefreshing;
        self.* = .{
            .phase = .refreshing,
            .operation_id = operation_id,
            .started_at_unix_s = now_unix_s,
        };
    }

    pub fn succeed(self: *RefreshState, operation_id: u64, now_unix_s: i64) error{OperationMismatch}!void {
        try self.finish(operation_id, now_unix_s, .succeeded, null);
    }

    pub fn fail(self: *RefreshState, operation_id: u64, now_unix_s: i64, failure: RefreshError) error{OperationMismatch}!void {
        try self.finish(operation_id, now_unix_s, .failed, failure);
    }

    pub fn requireReauth(self: *RefreshState, operation_id: u64, now_unix_s: i64, failure: RefreshError) error{OperationMismatch}!void {
        try self.finish(operation_id, now_unix_s, .reauth_required, failure);
    }

    pub fn markDeferred(self: *RefreshState) void {
        self.* = .{ .phase = .deferred };
    }

    pub fn markUnavailable(self: *RefreshState, failure: RefreshError) void {
        self.* = .{ .phase = .unavailable, .last_error = failure };
    }

    fn finish(self: *RefreshState, operation_id: u64, now_unix_s: i64, phase: RefreshPhase, failure: ?RefreshError) error{OperationMismatch}!void {
        if (self.phase != .refreshing or self.operation_id == null or self.operation_id.? != operation_id) {
            return error.OperationMismatch;
        }
        self.phase = phase;
        self.finished_at_unix_s = now_unix_s;
        self.last_error = failure;
    }
};

pub const ResetAttemptPhase = enum { prepared, submitted, ambiguous, completed, not_sent };
pub const ResetOutcome = enum { reset, nothing_to_reset, no_credit, already_redeemed };

pub const ResetAttempt = struct {
    idempotency_key: []const u8,
    account_id: []const u8,
    selected_credit_id: ?[]const u8,
    created_at_unix_s: i64,
    updated_at_unix_s: i64,
    preflight_observed_at_unix_s: i64,
    preflight_available_count: u32,
    confirmed_at_unix_s: i64,
    phase: ResetAttemptPhase = .prepared,
    outcome: ?ResetOutcome = null,

    pub fn init(
        idempotency_key: []const u8,
        account_id: []const u8,
        selected_credit_id: ?[]const u8,
        preflight_observed_at_unix_s: i64,
        preflight_available_count: u32,
        confirmed_at_unix_s: i64,
    ) error{ InvalidIdempotencyKey, InvalidAccount, NoCredit, ConfirmationBeforePreflight }!ResetAttempt {
        if (idempotency_key.len == 0) return error.InvalidIdempotencyKey;
        if (account_id.len == 0) return error.InvalidAccount;
        if (preflight_available_count == 0) return error.NoCredit;
        if (confirmed_at_unix_s < preflight_observed_at_unix_s) return error.ConfirmationBeforePreflight;
        return .{
            .idempotency_key = idempotency_key,
            .account_id = account_id,
            .selected_credit_id = selected_credit_id,
            .created_at_unix_s = confirmed_at_unix_s,
            .updated_at_unix_s = confirmed_at_unix_s,
            .preflight_observed_at_unix_s = preflight_observed_at_unix_s,
            .preflight_available_count = preflight_available_count,
            .confirmed_at_unix_s = confirmed_at_unix_s,
        };
    }

    pub fn preflightIsFresh(self: ResetAttempt, now_unix_s: i64, max_age_s: i64) bool {
        if (max_age_s < 0 or now_unix_s < self.preflight_observed_at_unix_s) return false;
        return now_unix_s - self.preflight_observed_at_unix_s <= max_age_s;
    }

    pub fn canSubmit(self: ResetAttempt, now_unix_s: i64, max_age_s: i64) bool {
        return self.phase == .prepared and self.outcome == null and self.preflight_available_count > 0 and self.preflightIsFresh(now_unix_s, max_age_s);
    }

    pub fn assertSameOperation(self: ResetAttempt, account_id: []const u8, selected_credit_id: ?[]const u8) error{IdempotencyConflict}!void {
        if (!std.mem.eql(u8, self.account_id, account_id) or !optionalStringEqual(self.selected_credit_id, selected_credit_id)) {
            return error.IdempotencyConflict;
        }
    }

    pub fn markSubmitted(self: *ResetAttempt, now_unix_s: i64, max_age_s: i64) error{ InvalidTransition, StalePreflight }!void {
        if (self.phase != .prepared or self.outcome != null) return error.InvalidTransition;
        if (!self.preflightIsFresh(now_unix_s, max_age_s)) return error.StalePreflight;
        self.phase = .submitted;
        self.updated_at_unix_s = now_unix_s;
    }

    pub fn markNotSent(self: *ResetAttempt, now_unix_s: i64) error{InvalidTransition}!void {
        if (self.phase != .submitted or self.outcome != null) return error.InvalidTransition;
        self.phase = .not_sent;
        self.updated_at_unix_s = now_unix_s;
    }

    pub fn markAmbiguous(self: *ResetAttempt, now_unix_s: i64) error{InvalidTransition}!void {
        if (self.phase != .submitted or self.outcome != null) return error.InvalidTransition;
        self.phase = .ambiguous;
        self.updated_at_unix_s = now_unix_s;
    }

    pub fn complete(self: *ResetAttempt, outcome: ResetOutcome, now_unix_s: i64) error{ OutcomeConflict, InvalidTransition }!void {
        if (self.phase == .completed) {
            if (self.outcome.? != outcome) return error.OutcomeConflict;
            return;
        }
        if (self.phase != .submitted and self.phase != .ambiguous and self.phase != .not_sent) return error.InvalidTransition;
        self.phase = .completed;
        self.outcome = outcome;
        self.updated_at_unix_s = now_unix_s;
    }
};

pub fn findAttemptByKey(attempts: []const ResetAttempt, key: []const u8) ?*const ResetAttempt {
    for (attempts) |*attempt| {
        if (std.mem.eql(u8, attempt.idempotency_key, key)) return attempt;
    }
    return null;
}

fn optionalStringEqual(a: ?[]const u8, b: ?[]const u8) bool {
    if (a == null or b == null) return a == null and b == null;
    return std.mem.eql(u8, a.?, b.?);
}
