const std = @import("std");
const testing = std.testing;

const attempt_ledger = @import("../attempt_ledger.zig");
const domain = @import("../domain.zig");

test "attempt ledger owns identifiers and preserves a key across updates" {
    var ledger: attempt_ledger.AttemptLedger = .{};
    var key = [_]u8{ 'k', 'e', 'y', '-', '1' };
    var account = [_]u8{ 'a', 'c', 'c', 't' };
    var credit = [_]u8{ 'c', 'r', 'e', 'd', 'i', 't' };
    var attempt = try domain.ResetAttempt.init(&key, &account, &credit, 100, 1, 101);
    const index = try ledger.append(attempt);

    key[0] = 'x';
    account[0] = 'x';
    credit[0] = 'x';
    attempt = ledger.attemptAt(index);
    try attempt.markSubmitted(102, 10);
    ledger.updateAt(index, attempt);

    const stored = ledger.attemptAt(index);
    try testing.expectEqualStrings("key-1", stored.idempotency_key);
    try testing.expectEqualStrings("acct", stored.account_id);
    try testing.expectEqualStrings("credit", stored.selected_credit_id.?);
    try testing.expectEqual(domain.ResetAttemptPhase.submitted, stored.phase);
    try testing.expectError(error.DuplicateKey, ledger.append(stored));
}
