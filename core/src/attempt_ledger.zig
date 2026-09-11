const std = @import("std");
const account_registry = @import("account_registry.zig");
const domain = @import("domain.zig");
const store = @import("store.zig");
const codex = @import("providers/codex.zig");

pub const max_attempts: usize = 16;
pub const max_idempotency_key_bytes: usize = codex.max_idempotency_key_bytes;
const max_credit_id_bytes: usize = codex.max_credit_id_bytes;
pub const max_ledger_text_bytes: usize =
    max_attempts * (max_idempotency_key_bytes + account_registry.max_id_bytes + max_credit_id_bytes);

const TextSpan = struct { start: u16 = 0, len: u16 = 0 };

const empty_attempt: domain.ResetAttempt = .{
    .idempotency_key = "",
    .account_id = "",
    .selected_credit_id = null,
    .created_at_unix_s = 0,
    .updated_at_unix_s = 0,
    .preflight_observed_at_unix_s = 0,
    .preflight_available_count = 0,
    .confirmed_at_unix_s = 0,
};

pub const LedgerError = error{
    LedgerFull,
    DuplicateKey,
    TextStorageFull,
    InvalidKey,
    UnknownKey,
};

pub const AttemptLedger = struct {
    attempts: [max_attempts]domain.ResetAttempt = @splat(empty_attempt),
    key_spans: [max_attempts]TextSpan = @splat(.{}),
    account_spans: [max_attempts]TextSpan = @splat(.{}),
    credit_spans: [max_attempts]?TextSpan = @splat(null),
    count: usize = 0,
    text: [max_ledger_text_bytes]u8 = @splat(0),
    text_len: u16 = 0,

    fn clear(self: *AttemptLedger) void {
        self.* = .{};
    }

    fn textOf(self: *const AttemptLedger, span: TextSpan) []const u8 {
        return self.text[span.start..][0..span.len];
    }

    fn intern(self: *AttemptLedger, text: []const u8, limit: usize) ?TextSpan {
        if (text.len == 0 or text.len > limit) return null;
        for (text) |byte| {
            if (byte < 0x20 or byte > 0x7e) return null;
        }
        if (text.len > self.text.len - self.text_len) return null;
        const start = self.text_len;
        @memcpy(self.text[start..][0..text.len], text);
        self.text_len += @intCast(text.len);
        return .{ .start = start, .len = @intCast(text.len) };
    }

    fn rebindOne(self: *AttemptLedger, index: usize) void {
        self.attempts[index].idempotency_key = self.textOf(self.key_spans[index]);
        self.attempts[index].account_id = self.textOf(self.account_spans[index]);
        self.attempts[index].selected_credit_id =
            if (self.credit_spans[index]) |span| self.textOf(span) else null;
    }

    fn rebind(self: *AttemptLedger) void {
        var index: usize = 0;
        while (index < self.count) : (index += 1) self.rebindOne(index);
    }

    pub fn countValue(self: *const AttemptLedger) usize {
        return self.count;
    }

    pub fn slice(self: *const AttemptLedger) []const domain.ResetAttempt {
        return self.attempts[0..self.count];
    }

    pub fn attemptAt(self: *const AttemptLedger, index: usize) domain.ResetAttempt {
        return self.attempts[index];
    }

    pub fn attemptPtrAt(self: *const AttemptLedger, index: usize) *const domain.ResetAttempt {
        return &self.attempts[index];
    }

    pub fn indexOfKey(self: *const AttemptLedger, key: []const u8) ?usize {
        var index: usize = 0;
        while (index < self.count) : (index += 1) {
            if (std.mem.eql(u8, self.textOf(self.key_spans[index]), key)) return index;
        }
        return null;
    }

    pub fn pendingIndexFor(self: *const AttemptLedger, account_id: []const u8) ?usize {
        var index: usize = 0;
        while (index < self.count) : (index += 1) {
            const attempt = self.attempts[index];
            if (attempt.outcome != null or attempt.phase == .not_sent) continue;
            if (std.mem.eql(u8, self.textOf(self.account_spans[index]), account_id)) return index;
        }
        return null;
    }

    pub fn unsentIndexFor(self: *const AttemptLedger, account_id: []const u8) ?usize {
        var found: ?usize = null;
        var index: usize = 0;
        while (index < self.count) : (index += 1) {
            const attempt = self.attempts[index];
            if (attempt.phase != .not_sent or attempt.outcome != null) continue;
            if (std.mem.eql(u8, self.textOf(self.account_spans[index]), account_id)) found = index;
        }
        return found;
    }

    pub fn retryableIndexFor(self: *const AttemptLedger, account_id: []const u8) ?usize {
        return self.pendingIndexFor(account_id) orelse self.unsentIndexFor(account_id);
    }

    pub fn append(self: *AttemptLedger, attempt: domain.ResetAttempt) LedgerError!usize {
        if (self.count == max_attempts) return error.LedgerFull;
        if (self.indexOfKey(attempt.idempotency_key) != null) return error.DuplicateKey;
        const key = self.intern(attempt.idempotency_key, max_idempotency_key_bytes) orelse
            return error.TextStorageFull;
        const account = self.intern(attempt.account_id, account_registry.max_id_bytes) orelse
            return error.TextStorageFull;
        const credit: ?TextSpan = if (attempt.selected_credit_id) |id|
            self.intern(id, max_credit_id_bytes) orelse return error.TextStorageFull
        else
            null;

        const index = self.count;
        self.attempts[index] = attempt;
        self.key_spans[index] = key;
        self.account_spans[index] = account;
        self.credit_spans[index] = credit;
        self.count += 1;
        self.rebindOne(index);
        return index;
    }

    pub fn dropLast(self: *AttemptLedger) void {
        if (self.count == 0) return;
        self.count -= 1;

        self.text_len = @intCast(self.key_spans[self.count].start);
        self.attempts[self.count] = empty_attempt;
        self.key_spans[self.count] = .{};
        self.account_spans[self.count] = .{};
        self.credit_spans[self.count] = null;
    }

    pub fn updateAt(self: *AttemptLedger, index: usize, updated: domain.ResetAttempt) void {
        self.attempts[index] = updated;
        self.rebindOne(index);
    }

    pub fn loadDocument(self: *AttemptLedger, document: store.AttemptDocument) (LedgerError || error{UnsupportedSchemaVersion})!void {
        store.validateAttemptDocument(document) catch |err| return switch (err) {
            error.UnsupportedSchemaVersion => error.UnsupportedSchemaVersion,
            else => error.InvalidKey,
        };
        var rebuilt: AttemptLedger = .{};
        for (document.attempts) |attempt| {
            _ = try rebuilt.append(attempt);
        }
        self.* = rebuilt;
        self.rebind();
    }
};
