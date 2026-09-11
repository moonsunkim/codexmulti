const std = @import("std");
const account_registry = @import("account_registry.zig");
const contracts = @import("ui_contracts.zig");
const format = @import("ui_format.zig");
const projection = @import("ui_projection.zig");

const ViewState = projection.ViewState;
const AccountView = contracts.AccountView;
const Command = contracts.Command;
const CommandOutcome = contracts.CommandOutcome;
const max_line_bytes = contracts.max_line_bytes;
const formatKst = format.formatKst;
const countdownPhrase = format.countdownPhrase;

pub const ResetStage = enum {
    idle,

    review,

    armed,

    dispatched,

    blocked,
};

pub const ResetBlockReason = enum {
    none,
    not_codex,
    no_credit,
    pending_attempt,

    unsent_attempt,
    not_connected,
    disabled,
    unknown_account,
    service_unavailable,
};

pub const SettleWatch = enum {
    none,

    waiting,

    seen,

    settled,

    settled_unsent,
};

pub const ResetFlow = struct {
    stage: ResetStage = .idle,
    reason: ResetBlockReason = .none,
    outcome: CommandOutcome = .none,
    settle: SettleWatch = .none,

    proxy_clear: contracts.ResetProxyClear = .none,
    row: u32 = 0,
    account_id_buffer: [account_registry.max_id_bytes]u8 = @splat(0),
    account_id_len: usize = 0,
    label_buffer: [account_registry.max_label_bytes]u8 = @splat(0),
    label_len: usize = 0,
    evidence_buffer: [max_line_bytes]u8 = @splat(0),
    evidence_len: usize = 0,
    reset_buffer: [max_line_bytes]u8 = @splat(0),
    reset_len: usize = 0,
    available_count: u32 = 0,

    pub fn accountId(self: *const ResetFlow) []const u8 {
        return self.account_id_buffer[0..self.account_id_len];
    }

    pub fn label(self: *const ResetFlow) []const u8 {
        return self.label_buffer[0..self.label_len];
    }

    pub fn usageEvidence(self: *const ResetFlow) []const u8 {
        return self.evidence_buffer[0..self.evidence_len];
    }

    pub fn resetEvidence(self: *const ResetFlow) []const u8 {
        return self.reset_buffer[0..self.reset_len];
    }

    pub fn isOpen(self: *const ResetFlow) bool {
        return self.stage != .idle;
    }

    pub fn cancel(self: *ResetFlow) void {
        self.* = .{};
    }

    pub fn open(self: *ResetFlow, view: *const ViewState, row_index: u32) void {
        self.* = .{};
        self.row = row_index;
        const row = view.rowAt(row_index) orelse {
            self.stage = .blocked;
            self.reason = .unknown_account;
            return;
        };
        copyInto(&self.account_id_buffer, &self.account_id_len, row.account_id);
        copyInto(&self.label_buffer, &self.label_len, row.label);
        if (row.provider != .codex) {
            self.stage = .blocked;
            self.reason = .not_codex;
            return;
        }
        if (!row.enabled) {
            self.stage = .blocked;
            self.reason = .disabled;
            return;
        }
        if (row.auth_state != .connected) {
            self.stage = .blocked;
            self.reason = .not_connected;
            return;
        }
        if (row.pending_reset_attempt) {
            self.stage = .blocked;
            self.reason = .pending_attempt;
            return;
        }
        if (row.unsent_reset_attempt) {
            self.stage = .blocked;
            self.reason = .unsent_attempt;
            return;
        }
        const count = row.reset_credit_count orelse 0;
        if (count == 0) {
            self.stage = .blocked;
            self.reason = .no_credit;
            return;
        }
        self.available_count = count;

        var absolute: [max_line_bytes]u8 = undefined;
        var relative: [max_line_bytes]u8 = undefined;
        if (row.primaryWindow()) |window| {
            var line: [max_line_bytes]u8 = undefined;
            var writer = std.Io.Writer.fixed(&line);
            writer.print("{d}% used · {s}", .{ window.used_percent, window.label }) catch {};
            copyInto(&self.evidence_buffer, &self.evidence_len, writer.buffered());
            var reset_line: [max_line_bytes]u8 = undefined;
            var reset_writer = std.Io.Writer.fixed(&reset_line);
            if (window.reset_at_unix_s) |at| {
                reset_writer.print("{s} ({s})", .{
                    formatKst(&absolute, at),
                    countdownPhrase(&relative, at, view.now_unix_s),
                }) catch {};
            } else {
                reset_writer.print("not reported by the provider", .{}) catch {};
            }
            copyInto(&self.reset_buffer, &self.reset_len, reset_writer.buffered());
        } else {
            copyInto(&self.evidence_buffer, &self.evidence_len, "no usage window reported");
            copyInto(&self.reset_buffer, &self.reset_len, "not reported by the provider");
        }
        self.stage = .review;
    }

    pub fn acknowledge(self: *ResetFlow) bool {
        switch (self.stage) {
            .review => self.stage = .armed,
            .armed => self.stage = .review,
            else => return false,
        }
        return true;
    }

    pub fn commandForConfirmation(self: *ResetFlow, now_unix_s: i64) ?Command {
        if (self.stage != .armed) return null;
        return .{ .redeem_reset = .{
            .account_id = self.accountId(),
            .expected_available_count = self.available_count,
            .confirmed_at_unix_s = now_unix_s,
            .surface = .details,
        } };
    }

    pub fn recordOutcome(self: *ResetFlow, outcome: CommandOutcome) void {
        self.stage = .dispatched;
        self.outcome = outcome;
        self.settle = if (outcome == .accepted_pending) .waiting else .none;
    }

    pub fn observe(self: *ResetFlow, row: *const AccountView) void {
        if (self.stage != .dispatched or self.outcome != .accepted_pending) return;
        const working = row.operation_in_flight or row.queued or row.pending_reset_attempt;
        switch (self.settle) {
            .waiting => if (working) {
                self.settle = .seen;
            },
            .seen => if (!working) {
                self.settle = if (row.unsent_reset_attempt) .settled_unsent else .settled;
            },
            .none, .settled, .settled_unsent => {},
        }
        if (self.settle == .settled) self.proxy_clear = row.reset_proxy_clear;
    }

    pub fn showsProxyClear(self: *const ResetFlow) bool {
        return self.settle == .settled and self.proxy_clear != .none;
    }

    pub fn proxyClearText(self: *const ResetFlow) []const u8 {
        if (!self.showsProxyClear()) return "";
        return switch (self.proxy_clear) {
            .none => "",
            .pending => "Failover: clearing cooldown for this account's proxy row…",
            .cleared => "Failover: cooldown cleared.",
            .not_mapped => "Failover: cooldown not cleared — this account is not mapped to a proxy row at the last read. Use Clear cooldown… in Failover if it is.",
            .@"unreachable" => "Failover: cooldown not cleared — the proxy was not reachable at the last read. Use Clear cooldown… in Failover after refreshing its status.",
            .busy => "Failover: cooldown not cleared — the proxy was busy with another action. Use Clear cooldown… in Failover.",
            .failed => "Failover: cooldown not cleared — the proxy refused or did not answer. Use Clear cooldown… in Failover.",
        };
    }

    pub fn awaitsReconciliation(self: *const ResetFlow) bool {
        return self.stage == .blocked and (self.reason == .pending_attempt or self.reason == .unsent_attempt);
    }

    pub fn commandForReconciliation(self: *const ResetFlow) ?Command {
        if (!self.awaitsReconciliation()) return null;
        return .{ .retry_reset = self.accountId() };
    }

    pub fn blockedText(self: *const ResetFlow) []const u8 {
        return switch (self.reason) {
            .none => "",
            .not_codex => "Reset redemption exists only for Codex accounts.",
            .no_credit => "This account has no reset credit the provider reported as available.",
            .pending_attempt => "An earlier reset attempt for this account has not settled. Reconcile it first.",
            .unsent_attempt => "The last reset attempt was not sent. Retry runs a fresh preflight and resends it with the same key.",
            .not_connected => "This account needs reauthentication before a reset can be considered.",
            .disabled => "This account is disabled.",
            .unknown_account => "That account is no longer in the local view.",
            .service_unavailable => "The reset service is not attached.",
        };
    }

    pub fn outcomeText(self: *const ResetFlow) []const u8 {
        return switch (self.outcome) {
            .none => "",
            .accepted_pending => switch (self.settle) {
                .settled => "This request has settled. The account row now shows the provider's reported usage and remaining resets.",
                .settled_unsent => "This request was not sent after all. The account row offers Retry reset attempt…, which resends it with the same key.",
                .none, .waiting, .seen => "The reset request was accepted and is pending. It is not complete until the service reports a settled outcome.",
            },
            .service_unavailable => "Nothing was sent: the reset service is not attached.",
            .provider_cli_missing => "Nothing was sent: the provider CLI is not installed in a supported location.",
            .offer_unavailable => "Nothing was sent: a reset needs a fresh Codex preflight read and no current offer exists.",
            .rejected_busy => "Nothing was sent: this account already has an operation in flight.",
            .rejected_not_allowed => "Nothing was sent: the service refused this surface or account state.",
            .rejected_unknown_account => "Nothing was sent: the service does not know that account.",
            .failed => "Nothing was confirmed: the service reported a failure. The credit state is unchanged as far as this app can prove.",
        };
    }
};

fn copyInto(buffer: []u8, len: *usize, value: []const u8) void {
    const take = @min(value.len, buffer.len);
    @memcpy(buffer[0..take], value[0..take]);
    len.* = take;
}

pub const NoticeKind = enum { none, pending, blocked, info };

pub const Notice = struct {
    kind: NoticeKind = .none,
    buffer: [max_line_bytes]u8 = @splat(0),
    len: usize = 0,

    pub fn text(self: *const Notice) []const u8 {
        return self.buffer[0..self.len];
    }

    pub fn clear(self: *Notice) void {
        self.kind = .none;
        self.len = 0;
    }

    pub fn set(self: *Notice, kind: NoticeKind, comptime template: []const u8, args: anytype) void {
        var scratch: [max_line_bytes]u8 = undefined;
        var writer = std.Io.Writer.fixed(&scratch);
        writer.print(template, args) catch {};
        copyInto(&self.buffer, &self.len, writer.buffered());
        self.kind = kind;
    }

    pub fn setOutcome(self: *Notice, action: []const u8, target: []const u8, outcome: CommandOutcome) void {
        switch (outcome) {
            .none => self.clear(),
            .accepted_pending => self.set(.pending, "{s} in progress · {s}", .{ action, target }),
            .service_unavailable => self.set(.blocked, "{s} unavailable for {s}: no application service is attached. Nothing was sent.", .{ action, target }),
            .provider_cli_missing => self.set(.blocked, "{s} unavailable for {s}: its CLI was not found. Install it in ~/.local/bin, Homebrew, or another PATH location.", .{ action, target }),
            .offer_unavailable => self.set(.blocked, "{s} unavailable for {s}: a fresh provider read is required and no current offer exists. Nothing was sent.", .{ action, target }),
            .rejected_busy => self.set(.blocked, "{s} refused for {s}: an operation is already in flight.", .{ action, target }),
            .rejected_not_allowed => self.set(.blocked, "{s} refused for {s}: the service does not allow it in this state.", .{ action, target }),
            .rejected_unknown_account => self.set(.blocked, "{s} refused: the service does not know {s}.", .{ action, target }),
            .failed => self.set(.blocked, "{s} failed for {s}. Nothing is claimed about the provider's state.", .{ action, target }),
        }
    }
};
