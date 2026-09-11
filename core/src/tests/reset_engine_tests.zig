const std = @import("std");
const testing = std.testing;

const account_registry = @import("../account_registry.zig");
const domain = @import("../domain.zig");
const reset_engine = @import("../reset_engine.zig");
const runtime_paths = @import("../runtime_paths.zig");

test "reset engine account removal remains a plan-only calculation" {
    const layout: runtime_paths.Layout = .{
        .root = try runtime_paths.Path.init("/tmp/reset-engine-component"),
    };
    const account: account_registry.Account = .{
        .id = "acct-1",
        .provider = .codex,
        .label = "Primary",
        .storage_key = "acct-home",
        .created_at_unix_s = 1,
    };
    const attempts = [_]domain.ResetAttempt{
        try domain.ResetAttempt.init("key-1", "acct-1", null, 10, 1, 11),
    };
    const engine: reset_engine.ResetEngine = .{};

    const plan = engine.planAccountRemoval(.{
        .account = account,
        .removes_snapshot = true,
        .attempts = &attempts,
        .has_pending_attempt = true,
        .scheduler_idle = true,
        .layout = &layout,
        .attempt_pending_code = "reset-attempt-pending",
        .account_busy_code = "account-busy",
    });

    try testing.expect(plan.removes_registry_entry);
    try testing.expect(plan.removes_snapshot);
    try testing.expectEqual(@as(usize, 1), plan.retained_attempts);
    try testing.expectEqualStrings("reset-attempt-pending", plan.blocked_code.?);
    try testing.expectEqual(@as(usize, 2), plan.directorySlice().len);
    try testing.expectEqual(domain.ResetAttemptPhase.prepared, attempts[0].phase);
}
