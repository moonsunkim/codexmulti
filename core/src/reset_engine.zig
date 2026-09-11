const std = @import("std");
const account_registry = @import("account_registry.zig");
const attempt_ledger = @import("attempt_ledger.zig");
const domain = @import("domain.zig");
const keychain = @import("keychain.zig");
const operation_scheduler = @import("operation_scheduler.zig");
const runtime_paths = @import("runtime_paths.zig");
const snapshot_book = @import("snapshot_book.zig");

pub const Surface = enum { tray, details };

pub const SessionError = operation_scheduler.AdmitError || error{
    ProviderMismatch,

    SurfaceNotAllowed,
    AuthStateNotConnected,

    PendingAttempt,
    SessionClosed,
};

pub const OfferError = error{
    UnknownAccount,
    ProviderMismatch,
    SurfaceNotAllowed,
    SessionClosed,

    PreflightMissing,
    StalePreflight,
    NoSnapshot,
    NoCredit,
    AuthStateNotConnected,
    PendingAttempt,
    InvalidAccountHome,
};

pub const ResetSession = struct {
    pub const Stage = enum { open, offered, confirmed, submitted, settled, closed };

    account_index: u16,
    account_id: []const u8,
    surface: Surface,
    opened_at_unix_s: i64,
    stage: Stage = .open,
    offer_revision: u64 = 0,
    auth_revision: u64 = 0,

    idempotency_key: []const u8 = "",
};

pub const ResetOffer = struct {
    account_id: []const u8,
    provider: domain.Provider = .codex,
    label: []const u8,
    auth_revision: u64,
    registry_revision: u64,
    snapshot_revision: u64,

    available_count: u32,
    detail_status: domain.CreditDetailStatus,

    selected_credit_id: ?[]const u8 = null,
    selected_expires_at_unix_s: ?i64 = null,
    observed_at_unix_s: i64,
    revision: u64,
    surface: Surface,

    pub fn usesNextAvailableWording(self: ResetOffer) bool {
        return self.selected_credit_id == null;
    }

    pub fn isFresh(self: ResetOffer, now_unix_s: i64, max_age_s: i64) bool {
        if (now_unix_s < self.observed_at_unix_s) return false;
        return now_unix_s - self.observed_at_unix_s <= max_age_s;
    }
};

pub const Confirmation = struct {
    account_id: []const u8,
    auth_revision: u64,
    offer_revision: u64,
    available_count: u32,
    selected_credit_id: ?[]const u8 = null,
    preflight_observed_at_unix_s: i64,
    confirmed_at_unix_s: i64,
    surface: Surface,
};

pub const ResetBeginError = error{
    UnknownAccount,
    ProviderMismatch,
    SurfaceNotAllowed,
    SessionClosed,

    OfferChanged,
    AuthRevisionChanged,
    StalePreflight,
    NoCredit,
    PendingAttempt,
    ConfirmationBeforePreflight,
    InvalidKey,
    DuplicateKey,
    LedgerFull,
    TextStorageFull,

    LedgerUnavailable,
    InvalidAccountHome,
    PreflightMissing,
    NoSnapshot,
    AuthStateNotConnected,
};

pub const ResetResolution = struct {
    idempotency_key: []const u8,
    account_id: []const u8,
    phase: domain.ResetAttemptPhase,
    outcome: ?domain.ResetOutcome = null,

    credit_may_have_been_spent: bool = false,

    requires_post_read: bool = false,

    may_retry_same_key: bool = false,
    public_code: ?[]const u8 = null,
    persist_code: ?[]const u8 = null,
};

pub const RecoveryAction = enum {
    none,

    discard_never_sent,

    reconcile_read,

    post_read_required,

    orphaned,
};

pub const RecoveryEntry = struct {
    idempotency_key: []const u8,
    account_id: []const u8,
    phase: domain.ResetAttemptPhase,
    outcome: ?domain.ResetOutcome = null,
    action: RecoveryAction,
    may_retry_same_key: bool = false,
};

pub const RecoveryPlan = struct {
    entries: [attempt_ledger.max_attempts]RecoveryEntry = @splat(.{
        .idempotency_key = "",
        .account_id = "",
        .phase = .prepared,
        .action = .none,
    }),
    count: usize = 0,

    pub fn slice(self: *const RecoveryPlan) []const RecoveryEntry {
        return self.entries[0..self.count];
    }

    pub fn requiresUserAction(self: *const RecoveryPlan) bool {
        for (self.slice()) |entry| {
            if (entry.action != .none and entry.action != .orphaned) return true;
        }
        return false;
    }
};

pub const CleanupPlan = struct {
    account_id: []const u8,
    provider: domain.Provider,
    label: []const u8,
    storage_key: []const u8,
    removes_registry_entry: bool = true,
    removes_snapshot: bool = false,
    credential_slots: [5]keychain.CredentialKind = .{
        .access_token,
        .refresh_token,
        .staged_refresh_token,
        .codex_cli_record,
        .codex_auth_backup,
    },

    directories: [2]runtime_paths.Path = @splat(.{}),
    directory_count: usize = 0,

    retained_attempts: usize = 0,

    blocked_code: ?[]const u8 = null,
    requires_confirmation: bool = true,

    pub fn isExecutable(self: CleanupPlan) bool {
        return self.blocked_code == null;
    }

    pub fn directorySlice(self: *const CleanupPlan) []const runtime_paths.Path {
        return self.directories[0..self.directory_count];
    }
};

pub const CleanupConfirmation = struct {
    account_id: []const u8,
    delete_credentials: bool,

    directories_acknowledged: bool = false,
};

pub const CleanupError = error{
    UnknownAccount,
    ConfirmationMismatch,
    Blocked,

    CredentialStoreMissing,
    CredentialRemovalFailed,
};

pub const CleanupResult = struct {
    account_id: []const u8,
    removed_registry_entry: bool = false,
    removed_snapshot: bool = false,
    removed_credential_slots: usize = 0,
    retained_attempts: usize = 0,

    directories_pending: usize = 0,
    persist_code: ?[]const u8 = null,

    store_failure_code: ?[]const u8 = null,
};

pub const OfferInput = struct {
    account: account_registry.Account,
    refresh_phase: domain.RefreshPhase,
    snapshot: snapshot_book.State,
    registry_revision: u64,
    snapshot_revision: u64,
    surface: Surface,
    now_unix_s: i64,
    max_preflight_age_s: i64,
    layout: *const runtime_paths.Layout,
    codex_executable: []const u8,
    codex_cli_version: []const u8,
};

pub const CleanupInput = struct {
    account: account_registry.Account,
    removes_snapshot: bool,
    attempts: []const domain.ResetAttempt,
    has_pending_attempt: bool,
    scheduler_idle: bool,
    layout: *const runtime_paths.Layout,
    attempt_pending_code: []const u8,
    account_busy_code: []const u8,
};

pub const ResetEngine = struct {
    pub fn prepareOffer(_: ResetEngine, input: OfferInput) OfferError!ResetOffer {
        const value = input.account;
        if (value.provider != .codex) return error.ProviderMismatch;
        if (value.auth_state != .connected) return error.AuthStateNotConnected;
        if (input.refresh_phase != .succeeded) return error.PreflightMissing;
        const snapshot = input.snapshot;
        if (!snapshot.present) return error.NoSnapshot;
        const credits = snapshot.credits orelse return error.NoCredit;
        if (credits.authoritativeCount() == 0) return error.NoCredit;
        if (!observationIsFresh(credits.observed_at_unix_s, input.now_unix_s, input.max_preflight_age_s)) return error.StalePreflight;
        if (!observationIsFresh(snapshot.captured_at_unix_s, input.now_unix_s, input.max_preflight_age_s)) return error.StalePreflight;

        const home = input.layout.codexHome(value.storage_key) catch return error.InvalidAccountHome;
        const selected = selectableCredit(snapshot.details, input.now_unix_s);

        var offer: ResetOffer = .{
            .account_id = value.id,
            .label = value.label,
            .auth_revision = value.auth_revision,
            .registry_revision = input.registry_revision,
            .snapshot_revision = input.snapshot_revision,
            .available_count = credits.authoritativeCount(),
            .detail_status = credits.detail_status,
            .selected_credit_id = if (selected) |detail| detail.id else null,
            .selected_expires_at_unix_s = if (selected) |detail| detail.expires_at_unix_s else null,
            .observed_at_unix_s = credits.observed_at_unix_s,
            .revision = 0,
            .surface = input.surface,
        };
        offer.revision = offerFingerprint(offer, snapshot, home.slice(), input.codex_executable, input.codex_cli_version);
        return offer;
    }

    pub fn confirmOffer(
        _: ResetEngine,
        session: *ResetSession,
        offer: ResetOffer,
        now_unix_s: i64,
        max_preflight_age_s: i64,
    ) error{ SessionClosed, OfferChanged, ConfirmationBeforePreflight, StalePreflight }!Confirmation {
        if (session.stage == .closed) return error.SessionClosed;
        if (session.stage != .offered) return error.OfferChanged;
        if (session.offer_revision != offer.revision) return error.OfferChanged;
        if (now_unix_s < offer.observed_at_unix_s) return error.ConfirmationBeforePreflight;
        if (!offer.isFresh(now_unix_s, max_preflight_age_s)) return error.StalePreflight;
        session.stage = .confirmed;
        return .{
            .account_id = offer.account_id,
            .auth_revision = offer.auth_revision,
            .offer_revision = offer.revision,
            .available_count = offer.available_count,
            .selected_credit_id = offer.selected_credit_id,
            .preflight_observed_at_unix_s = offer.observed_at_unix_s,
            .confirmed_at_unix_s = now_unix_s,
            .surface = offer.surface,
        };
    }

    pub fn planRecovery(_: ResetEngine, attempts: []const domain.ResetAttempt, registry: *const account_registry.Registry) RecoveryPlan {
        var plan: RecoveryPlan = .{};
        for (attempts) |attempt| {
            if (plan.count == attempt_ledger.max_attempts) break;
            const known_account = registry.indexOf(attempt.account_id) != null;
            const action: RecoveryAction = if (!known_account)
                .orphaned
            else switch (attempt.phase) {
                .prepared => .discard_never_sent,

                .submitted, .ambiguous, .not_sent => .reconcile_read,
                .completed => .post_read_required,
            };
            plan.entries[plan.count] = .{
                .idempotency_key = attempt.idempotency_key,
                .account_id = attempt.account_id,
                .phase = attempt.phase,
                .outcome = attempt.outcome,
                .action = action,
                .may_retry_same_key = action == .reconcile_read,
            };
            plan.count += 1;
        }
        return plan;
    }

    pub fn planAccountRemoval(_: ResetEngine, input: CleanupInput) CleanupPlan {
        const value = input.account;
        var plan: CleanupPlan = .{
            .account_id = value.id,
            .provider = value.provider,
            .label = value.label,
            .storage_key = value.storage_key,
            .removes_snapshot = input.removes_snapshot,
        };
        if (input.layout.providerHome(value.provider, value.storage_key)) |home| {
            plan.directories[plan.directory_count] = home;
            plan.directory_count += 1;
        } else |_| {}
        if (input.layout.profileDir(value.storage_key)) |profile_dir| {
            plan.directories[plan.directory_count] = profile_dir;
            plan.directory_count += 1;
        } else |_| {}
        for (input.attempts) |attempt| {
            if (std.mem.eql(u8, attempt.account_id, value.id)) plan.retained_attempts += 1;
        }
        if (input.has_pending_attempt) {
            plan.blocked_code = input.attempt_pending_code;
        } else if (!input.scheduler_idle) {
            plan.blocked_code = input.account_busy_code;
        }
        return plan;
    }
};

fn observationIsFresh(observed_at_unix_s: i64, now_unix_s: i64, max_preflight_age_s: i64) bool {
    if (now_unix_s < observed_at_unix_s) return false;
    return now_unix_s - observed_at_unix_s <= max_preflight_age_s;
}

fn selectableCredit(details: []const domain.ResetCreditDetail, now_unix_s: i64) ?domain.ResetCreditDetail {
    var best: ?domain.ResetCreditDetail = null;
    for (details) |detail| {
        if (detail.isExpired(now_unix_s)) continue;
        const current = best orelse {
            best = detail;
            continue;
        };
        const candidate_expiry = detail.expires_at_unix_s orelse continue;
        const current_expiry = current.expires_at_unix_s orelse {
            best = detail;
            continue;
        };
        if (candidate_expiry < current_expiry) best = detail;
    }
    return best;
}

fn offerFingerprint(
    offer: ResetOffer,
    snapshot: snapshot_book.State,
    home: []const u8,
    codex_executable: []const u8,
    codex_cli_version: []const u8,
) u64 {
    var hasher = std.crypto.hash.sha2.Sha256.init(.{});
    hashText(&hasher, "codexmulti/reset-offer/v1");
    hashText(&hasher, offer.account_id);
    hashText(&hasher, @tagName(offer.provider));
    hashText(&hasher, home);
    hashText(&hasher, codex_executable);
    hashText(&hasher, codex_cli_version);
    hashU64(&hasher, offer.auth_revision);
    hashU64(&hasher, offer.registry_revision);
    hashU64(&hasher, offer.snapshot_revision);
    hashU64(&hasher, offer.available_count);
    hashText(&hasher, @tagName(offer.detail_status));
    hashText(&hasher, offer.selected_credit_id orelse "");
    hashOptionalTime(&hasher, offer.selected_expires_at_unix_s);
    hashU64(&hasher, @bitCast(offer.observed_at_unix_s));

    hashU64(&hasher, @bitCast(snapshot.captured_at_unix_s));
    hashText(&hasher, @tagName(snapshot.status));
    hashU64(&hasher, snapshot.windows.len);
    for (snapshot.windows) |window| {
        hashText(&hasher, @tagName(window.kind));
        hashText(&hasher, window.label);
        hashU64(&hasher, window.used_percent);
        hashOptionalTime(&hasher, window.reset_at_unix_s);
        hashU64(&hasher, window.duration_minutes orelse 0);
    }
    hashU64(&hasher, snapshot.details.len);
    for (snapshot.details) |detail| {
        hashText(&hasher, detail.id);
        hashOptionalTime(&hasher, detail.expires_at_unix_s);
    }

    var digest: [std.crypto.hash.sha2.Sha256.digest_length]u8 = undefined;
    hasher.final(&digest);
    return std.mem.readInt(u64, digest[0..8], .big);
}

fn hashText(hasher: *std.crypto.hash.sha2.Sha256, text: []const u8) void {
    hashU64(hasher, text.len);
    hasher.update(text);
}

fn hashU64(hasher: *std.crypto.hash.sha2.Sha256, value: u64) void {
    var bytes: [8]u8 = undefined;
    std.mem.writeInt(u64, &bytes, value, .big);
    hasher.update(&bytes);
}

fn hashOptionalTime(hasher: *std.crypto.hash.sha2.Sha256, value: ?i64) void {
    const present: u64 = if (value == null) 0 else 1;
    hashU64(hasher, present);
    hashU64(hasher, @bitCast(value orelse 0));
}
