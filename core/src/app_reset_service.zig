const std = @import("std");

const app_worker = @import("app_worker.zig");
const coordinator = @import("coordinator.zig");
const domain = @import("domain.zig");
const runtime_adapters = @import("app_runtime_adapters.zig");
const ui_model = @import("ui_model.zig");
const codex = @import("providers/codex.zig");

const JobKind = app_worker.JobKind;
const Worker = app_worker.Worker;
const CodexChannel = runtime_adapters.CodexChannel;
const KeySource = runtime_adapters.KeySource;

const generated_hex_digits = runtime_adapters.generated_hex_digits;
const idempotency_key_prefix = runtime_adapters.idempotency_key_prefix;
const max_generated_key_bytes = runtime_adapters.max_generated_key_bytes;

pub const public_code_worker_unavailable = "worker-unavailable";
pub const public_code_key_unavailable = "reset-key-unavailable";

pub const Context = struct {
    core: *coordinator.Coordinator,
    workers: *[app_worker.max_workers]Worker,
    io: std.Io,
    sink: coordinator.DocumentSink,
    keys: KeySource,
    resets_started: *usize,
    consumes_sent: *usize,
    last_reset_outcome: *?domain.ResetOutcome,
    callback_context: *anyopaque,
    prepare_codex_fn: *const fn (
        context: *anyopaque,
        worker: *Worker,
        account_index: u16,
        kind: JobKind,
        now_unix_s: i64,
    ) ?[]const u8,
    apply_observation_fn: *const fn (
        context: *anyopaque,
        ticket: coordinator.Ticket,
        observation: coordinator.Observation,
        now_unix_s: i64,
    ) void,
    record_code_fn: *const fn (context: *anyopaque, code: []const u8) void,

    on_settled_fn: *const fn (context: *anyopaque, account_id: []const u8, now_unix_s: i64) void,

    fn prepareCodex(
        self: Context,
        worker: *Worker,
        account_index: u16,
        kind: JobKind,
        now_unix_s: i64,
    ) ?[]const u8 {
        return self.prepare_codex_fn(self.callback_context, worker, account_index, kind, now_unix_s);
    }

    fn applyObservation(
        self: Context,
        ticket: coordinator.Ticket,
        observation: coordinator.Observation,
        now_unix_s: i64,
    ) void {
        self.apply_observation_fn(self.callback_context, ticket, observation, now_unix_s);
    }

    fn recordCode(self: Context, code: []const u8) void {
        self.record_code_fn(self.callback_context, code);
    }

    fn onSettled(self: Context, account_id: []const u8, now_unix_s: i64) void {
        self.on_settled_fn(self.callback_context, account_id, now_unix_s);
    }
};

pub const ResetService = struct {
    stage: Stage = .idle,
    session: coordinator.ResetSession = undefined,

    channel: CodexChannel = .{},

    confirmed_count: u32 = 0,

    key_buffer: [max_generated_key_bytes]u8 = @splat(0),
    key_len: usize = 0,

    outcome_code: ?[]const u8 = null,

    settled_outcome: ?domain.ResetOutcome = null,

    const Stage = enum {
        idle,

        preflight,

        consuming,

        post_read,
    };

    pub fn isActive(self: *const ResetService) bool {
        return self.stage != .idle;
    }

    fn key(self: *const ResetService) []const u8 {
        return self.key_buffer[0..self.key_len];
    }

    pub fn submitRedeem(
        self: *ResetService,
        context: Context,
        request: ui_model.RedeemReset,
        now_unix_s: i64,
    ) ui_model.CommandOutcome {
        if (self.isActive()) return .rejected_busy;

        var session = context.core.openResetSession(
            request.account_id,
            request.surface,
            request.confirmed_at_unix_s,
        ) catch |err| return switch (err) {
            error.UnknownAccount => .rejected_unknown_account,
            error.AccountBusy, error.ConcurrencyLimit, error.PendingAttempt => .rejected_busy,
            else => .rejected_not_allowed,
        };

        const worker_index = app_worker.free(context.workers) orelse {
            context.core.closeResetSession(&session, coordinator.noChildLifecycle());
            return .rejected_busy;
        };

        self.* = .{
            .stage = .preflight,
            .session = session,
            .confirmed_count = request.expected_available_count,
        };

        const ticket = context.core.beginSessionStep(&self.session, .reset_preflight, now_unix_s) catch {
            self.close(context, coordinator.public_code_account_busy);
            return .rejected_busy;
        };
        if (self.startCodexStep(context, worker_index, ticket, .reset_preflight, now_unix_s)) |code| {
            context.core.abandonOperation(ticket, now_unix_s, code);
            self.close(context, code);
            return .rejected_busy;
        }
        context.resets_started.* += 1;
        return .accepted_pending;
    }

    pub fn submitRetry(
        self: *ResetService,
        context: Context,
        account_id: []const u8,
        now_unix_s: i64,
    ) ui_model.CommandOutcome {
        if (self.isActive()) return .rejected_busy;

        const attempt = context.core.retryableAttemptFor(account_id) orelse return .offer_unavailable;
        if (attempt.phase != .submitted and attempt.phase != .ambiguous and attempt.phase != .not_sent) return .offer_unavailable;

        const worker_index = app_worker.free(context.workers) orelse return .rejected_busy;
        const session = context.core.reopenResetSession(
            account_id,
            attempt.idempotency_key,
            .details,
            now_unix_s,
        ) catch |err| return switch (err) {
            error.UnknownAccount => .rejected_unknown_account,
            error.AccountBusy, error.ConcurrencyLimit, error.PendingAttempt => .rejected_busy,
            else => .rejected_not_allowed,
        };

        self.* = .{ .stage = .preflight, .session = session };
        copyInto(&self.key_buffer, &self.key_len, attempt.idempotency_key);

        const ticket = context.core.beginSessionStep(&self.session, .reset_preflight, now_unix_s) catch {
            self.close(context, coordinator.public_code_account_busy);
            return .rejected_busy;
        };
        if (self.startCodexStep(context, worker_index, ticket, .reset_preflight, now_unix_s)) |code| {
            context.core.abandonOperation(ticket, now_unix_s, code);
            self.close(context, code);
            return .rejected_busy;
        }
        return .accepted_pending;
    }

    pub fn applyPreflight(self: *ResetService, context: Context, worker: *Worker, now_unix_s: i64) void {
        if (self.stage != .preflight) return;

        const observation = app_worker.codexObservation(worker, now_unix_s) orelse {
            const code = app_worker.rejectionCode(worker);
            context.core.abandonOperation(worker.ticket, now_unix_s, code);
            self.close(context, code);
            return;
        };
        context.applyObservation(worker.ticket, observation, now_unix_s);

        const offer = context.core.prepareResetOffer(&self.session, now_unix_s) catch |err| {
            self.close(context, offerCode(err));
            return;
        };

        if (self.key_len != 0) {
            self.resumeSameKey(context, offer, now_unix_s);
            return;
        }

        if (offer.available_count != self.confirmed_count) {
            self.close(context, coordinator.public_code_offer_changed);
            return;
        }
        self.beginFreshAttempt(context, offer, now_unix_s);
    }

    fn beginFreshAttempt(
        self: *ResetService,
        context: Context,
        offer: coordinator.ResetOffer,
        now_unix_s: i64,
    ) void {
        const confirmation = context.core.confirmResetOffer(&self.session, offer, now_unix_s) catch |err| {
            self.close(context, switch (err) {
                error.StalePreflight => coordinator.public_code_offer_stale,
                else => coordinator.public_code_offer_changed,
            });
            return;
        };

        var key_storage: [max_generated_key_bytes]u8 = undefined;
        var suffix_storage: [generated_hex_digits * 2]u8 = undefined;
        const suffix = context.keys.next(&suffix_storage);
        if (suffix.len == 0) {
            self.close(context, public_code_key_unavailable);
            return;
        }
        const key_value = std.fmt.bufPrint(&key_storage, idempotency_key_prefix ++ "{s}", .{suffix}) catch {
            self.close(context, public_code_key_unavailable);
            return;
        };
        copyInto(&self.key_buffer, &self.key_len, key_value);

        const attempt = context.core.beginResetAttempt(.{
            .session = &self.session,
            .confirmation = confirmation,
            .idempotency_key = self.key(),
            .now_unix_s = now_unix_s,
            .sink = context.sink,
        }) catch |err| {
            self.key_len = 0;
            self.close(context, beginResetCode(err));
            return;
        };
        self.sendConsume(context, attempt.*, now_unix_s);
    }

    fn resumeSameKey(
        self: *ResetService,
        context: Context,
        offer: coordinator.ResetOffer,
        now_unix_s: i64,
    ) void {
        const attempt = context.core.prepareSameKeyRetry(.{
            .session = &self.session,
            .offer = offer,
            .now_unix_s = now_unix_s,
            .sink = context.sink,
        }) catch |err| {
            self.close(context, beginResetCode(err));
            return;
        };
        self.sendConsume(context, attempt.*, now_unix_s);
    }

    fn sendConsume(self: *ResetService, context: Context, attempt: domain.ResetAttempt, now_unix_s: i64) void {
        const worker_index = app_worker.free(context.workers) orelse {
            self.close(context, public_code_worker_unavailable);
            return;
        };

        const worker = &context.workers[worker_index];
        if (context.prepareCodex(worker, self.session.account_index, .reset_consume, now_unix_s)) |code| {
            self.close(context, code);
            return;
        }
        worker.external_channel = &self.channel;
        copyInto(&worker.attempt_key, &worker.attempt_key_len, attempt.idempotency_key);
        worker.has_credit_id = attempt.selected_credit_id != null;
        if (attempt.selected_credit_id) |credit_id| {
            copyInto(&worker.credit_id_buffer, &worker.credit_id_len, credit_id);
        } else {
            worker.credit_id_len = 0;
        }
        worker.attempt = attempt;
        worker.attempt.idempotency_key = worker.attempt_key[0..worker.attempt_key_len];
        worker.attempt.account_id = worker.accountId();
        worker.attempt.selected_credit_id = worker.creditId();

        if (!app_worker.start(context.io, &context.workers[worker_index])) {
            self.close(context, public_code_worker_unavailable);
            return;
        }
        self.stage = .consuming;
        context.consumes_sent.* += 1;
    }

    pub fn applyConsume(self: *ResetService, context: Context, worker: *Worker, now_unix_s: i64) void {
        if (self.stage != .consuming) return;
        const outcome = switch (worker.result) {
            .consume => |value| value,
            else => codex.ConsumeOutcome{ .rejected = .{
                .kind = .unknown,
                .public_code = codex.public_code_reset_outcome_unknown,
                .retryable = false,
            } },
        };
        const resolution = context.core.applyResetOutcome(
            &self.session,
            outcome,
            now_unix_s,
            context.sink,
        ) catch {
            self.close(context, coordinator.public_code_operation_unknown);
            return;
        };
        context.last_reset_outcome.* = resolution.outcome;
        self.settled_outcome = resolution.outcome;
        self.outcome_code = resolution.public_code;
        if (resolution.public_code) |code| context.recordCode(code);
        if (resolution.persist_code) |code| context.recordCode(code);

        if (!resolution.requires_post_read) {
            self.close(context, resolution.public_code);
            return;
        }
        self.startPostRead(context, now_unix_s);
    }

    fn startPostRead(self: *ResetService, context: Context, now_unix_s: i64) void {
        const worker_index = app_worker.free(context.workers) orelse {
            self.close(context, public_code_worker_unavailable);
            return;
        };
        const ticket = context.core.beginSessionStep(&self.session, .reset_post_read, now_unix_s) catch {
            self.close(context, coordinator.public_code_account_busy);
            return;
        };
        if (self.startCodexStep(context, worker_index, ticket, .reset_post_read, now_unix_s)) |code| {
            context.core.abandonOperation(ticket, now_unix_s, code);
            self.close(context, code);
            return;
        }
        self.stage = .post_read;
    }

    pub fn applyPostRead(self: *ResetService, context: Context, worker: *Worker, now_unix_s: i64) void {
        if (self.stage != .post_read) return;
        if (app_worker.codexObservation(worker, now_unix_s)) |observation| {
            context.applyObservation(worker.ticket, observation, now_unix_s);
        } else {
            context.core.abandonOperation(worker.ticket, now_unix_s, app_worker.rejectionCode(worker));
        }

        if (self.settled_outcome == .reset) context.onSettled(self.session.account_id, now_unix_s);
        self.close(context, self.outcome_code);
    }

    pub fn shutdown(self: *ResetService, core: *coordinator.Coordinator) void {
        if (self.stage == .idle) return;
        core.closeResetSession(&self.session, self.channel.lifecycle);
        self.channel.bound = false;
        self.channel.lifecycle = coordinator.noChildLifecycle();
        self.stage = .idle;
    }

    fn startCodexStep(
        self: *ResetService,
        context: Context,
        worker_index: usize,
        ticket: coordinator.Ticket,
        kind: JobKind,
        now_unix_s: i64,
    ) ?[]const u8 {
        const worker = &context.workers[worker_index];
        if (context.prepareCodex(worker, ticket.account_index, kind, now_unix_s)) |code| return code;
        worker.ticket = ticket;
        worker.external_channel = &self.channel;
        if (!app_worker.start(context.io, worker)) {
            context.recordCode(public_code_worker_unavailable);
            return public_code_worker_unavailable;
        }
        return null;
    }

    fn close(self: *ResetService, context: Context, code: ?[]const u8) void {
        if (self.stage != .idle) {
            context.core.closeResetSession(&self.session, self.channel.lifecycle);
            self.channel.bound = false;
            self.channel.lifecycle = coordinator.noChildLifecycle();
        }
        if (code) |value| context.recordCode(value);
        self.* = .{};
    }
};

fn offerCode(err: coordinator.OfferError) []const u8 {
    return switch (err) {
        error.StalePreflight => coordinator.public_code_offer_stale,
        error.PendingAttempt => coordinator.public_code_attempt_pending,
        error.NoCredit, error.NoSnapshot, error.PreflightMissing => coordinator.public_code_offer_changed,
        error.InvalidAccountHome => coordinator.public_code_account_home_invalid,
        error.UnknownAccount => coordinator.public_code_account_unknown,
        error.ProviderMismatch => coordinator.public_code_provider_mismatch,
        error.AuthStateNotConnected, error.SurfaceNotAllowed, error.SessionClosed => coordinator.public_code_offer_changed,
    };
}

fn beginResetCode(err: coordinator.ResetBeginError) []const u8 {
    return switch (err) {
        error.LedgerUnavailable, error.LedgerFull, error.TextStorageFull => coordinator.public_code_ledger_unavailable,
        error.StalePreflight => coordinator.public_code_offer_stale,
        error.PendingAttempt, error.DuplicateKey => coordinator.public_code_attempt_pending,
        error.InvalidKey => public_code_key_unavailable,
        error.NoCredit, error.NoSnapshot, error.PreflightMissing, error.OfferChanged, error.AuthRevisionChanged, error.ConfirmationBeforePreflight => coordinator.public_code_offer_changed,
        error.UnknownAccount => coordinator.public_code_account_unknown,
        error.ProviderMismatch => coordinator.public_code_provider_mismatch,
        error.AuthStateNotConnected, error.SurfaceNotAllowed, error.SessionClosed => coordinator.public_code_offer_changed,
        error.InvalidAccountHome => coordinator.public_code_account_home_invalid,
    };
}

fn copyInto(buffer: []u8, len: *usize, value: []const u8) void {
    const take = @min(value.len, buffer.len);
    @memcpy(buffer[0..take], value[0..take]);
    len.* = take;
}
