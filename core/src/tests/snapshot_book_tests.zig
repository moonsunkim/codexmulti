const std = @import("std");
const testing = std.testing;

const domain = @import("../domain.zig");
const snapshot_book = @import("../snapshot_book.zig");

test "snapshot book replaces an account observation whole" {
    var book: snapshot_book.SnapshotBook = .{};
    const capacity_failure: domain.RefreshError = .{
        .kind = .malformed_response,
        .public_code = "snapshot-capacity",
        .retryable = true,
    };
    const windows = [_]domain.UsageWindow{
        .{ .kind = .session, .label = "five hour", .used_percent = 80 },
    };
    const details = [_]domain.ResetCreditDetail{
        .{ .id = "credit-1", .label = "first" },
    };

    book.replace(0, .codex, .{
        .observed_at_unix_s = 100,
        .windows = &windows,
        .reset_credits = .{
            .available_count = 1,
            .observed_at_unix_s = 100,
            .detail_status = .detailed,
            .details = &details,
        },
    }, capacity_failure);
    book.replace(0, .codex, .{
        .observed_at_unix_s = 200,
        .windows = &.{},
        .reset_credits = null,
    }, capacity_failure);

    const snapshot = book.snapshotAt(0, "acct-1").?;
    try testing.expectEqual(@as(i64, 200), snapshot.captured_at_unix_s);
    try testing.expectEqual(@as(usize, 0), snapshot.windows.len);
    try testing.expect(snapshot.reset_credits == null);
    try testing.expectEqual(@as(u64, 2), book.revisionValue());
}
