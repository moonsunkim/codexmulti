const std = @import("std");
const testing = std.testing;

const operation_scheduler = @import("../operation_scheduler.zig");

test "operation scheduler enforces global and per-account reservations" {
    var scheduler: operation_scheduler.OperationScheduler = .{};

    try scheduler.reserveAccount(3, 0);
    try testing.expectError(error.AccountBusy, scheduler.reserveAccount(3, 0));
    try scheduler.reserveAccount(3, 1);
    try testing.expectError(error.ConcurrencyLimit, scheduler.reserveAccount(3, 2));
    try testing.expectEqual(@as(usize, 2), scheduler.inFlightCount());

    scheduler.releaseAccount(0);
    scheduler.releaseAccount(0);
    try testing.expectEqual(@as(usize, 1), scheduler.inFlightCount());
    try testing.expectEqual(operation_scheduler.EnqueueOutcome.queued, try scheduler.enqueue(0, .user_refresh));
    try testing.expectEqual(operation_scheduler.EnqueueOutcome.already_pending, try scheduler.enqueue(0, .user_refresh));
    try testing.expectEqual(@as(usize, 1), scheduler.queuedCount());
}
