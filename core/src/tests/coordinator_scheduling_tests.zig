const std = @import("std");
const account_registry = @import("../account_registry.zig");
const coordinator = @import("../coordinator.zig");
const domain = @import("../domain.zig");
const keychain = @import("../keychain.zig");
const oauth = @import("../oauth.zig");
const runtime_paths = @import("../runtime_paths.zig");
const store = @import("../store.zig");
const transport = @import("../process_jsonl.zig");
const codex = @import("../providers/codex.zig");
const support = @import("coordinator_test_support.zig");
const protocol = @import("codex_protocol_test_fixtures.zig");

const testing = std.testing;

const fixture_now = support.fixture_now;
const home_dir = support.home_dir;
const app_root = support.app_root;
const accounts_root = support.accounts_root;
const codex_account_id = support.codex_account_id;
const claude_account_id = support.claude_account_id;
const codex_storage_key = support.codex_storage_key;
const claude_storage_key = support.claude_storage_key;
const codex_home = support.codex_home;
const codex_profile_dir = support.codex_profile_dir;
const claude_config_dir = support.claude_config_dir;
const codex_executable = support.codex_executable;
const canary_access = support.canary_access;
const canary_refresh = support.canary_refresh;
const canary_identity = support.canary_identity;
const RecordingSink = support.RecordingSink;
const CodexHarness = support.CodexHarness;
const testLayout = support.testLayout;
const newCoordinator = support.newCoordinator;
const seedAccounts = support.seedAccounts;
const demo_windows = support.demo_windows;
const demo_details = support.demo_details;
const demoCredits = support.demoCredits;
const supportedObservation = support.supportedObservation;
const admit = support.admit;
const runPreflight = support.runPreflight;

test "refresh all queues every enabled account once and admits at most two" {
    const app = try newCoordinator();
    defer app.destroy();
    try seedAccounts(app);
    _ = try app.addAccount(.{
        .id = "acct-codex-third",
        .provider = .codex,
        .label = "Codex Third",
        .storage_key = "codex-third",
        .created_at_unix_s = fixture_now,
    });
    _ = try app.addAccount(.{
        .id = "acct-codex-off",
        .provider = .codex,
        .label = "Codex Off",
        .storage_key = "codex-off",
        .created_at_unix_s = fixture_now,
        .enabled = false,
    });

    const plan = app.requestRefreshAll();
    try testing.expectEqual(@as(usize, 3), plan.queued);
    try testing.expectEqual(@as(usize, 1), plan.skipped_disabled);
    try testing.expectEqual(@as(usize, 0), plan.already_pending);

    const again = app.requestRefreshAll();
    try testing.expectEqual(@as(usize, 0), again.queued);
    try testing.expectEqual(@as(usize, 3), again.already_pending);
    try testing.expectEqual(@as(usize, 3), app.queuedCount());

    const first = app.nextOperation(fixture_now).?;
    const second = app.nextOperation(fixture_now).?;
    try testing.expectEqual(@as(usize, 2), app.inFlightCount());
    try testing.expect(app.nextOperation(fixture_now) == null);
    try testing.expect(first.operation_id != second.operation_id);
    try testing.expect(first.account_index != second.account_index);

    _ = try app.applyObservation(first, .{ .deferred = {} }, fixture_now);
    try testing.expectEqual(@as(usize, 1), app.inFlightCount());
    const third = app.nextOperation(fixture_now).?;
    try testing.expect(third.account_index != second.account_index);
    try testing.expect(app.nextOperation(fixture_now) == null);

    _ = try app.applyObservation(second, .{ .deferred = {} }, fixture_now);
    _ = try app.applyObservation(third, .{ .deferred = {} }, fixture_now);
    try testing.expect(app.schedulerIsIdle());
    try testing.expect(app.nextOperation(fixture_now) == null);
}

test "one operation per account, and a stale ticket applies to nothing" {
    const app = try newCoordinator();
    defer app.destroy();
    try seedAccounts(app);

    const ticket = try admit(app, codex_account_id, fixture_now);

    try testing.expectEqual(coordinator.EnqueueOutcome.already_pending, try app.requestRefresh(codex_account_id));
    try testing.expectEqual(@as(usize, 0), app.queuedCount());
    try testing.expectEqual(@as(usize, 1), app.inFlightCount());

    _ = try app.applyObservation(ticket, supportedObservation(fixture_now, null), fixture_now);

    try testing.expectError(
        error.UnknownOperation,
        app.applyObservation(ticket, supportedObservation(fixture_now, null), fixture_now),
    );

    try testing.expectError(error.UnknownAccount, app.requestRefresh("acct-missing"));
    try app.registry.setEnabled(claude_account_id, false);
    try testing.expectError(error.AccountDisabled, app.requestRefresh(claude_account_id));
}

test "an operation that never reached the provider releases the account intact" {
    const app = try newCoordinator();
    defer app.destroy();
    try seedAccounts(app);

    try testing.expectEqualStrings(codex_home, (try app.providerHome(codex_account_id)).slice());
    try testing.expectEqualStrings(claude_config_dir, (try app.providerHome(claude_account_id)).slice());
    try testing.expectEqualStrings(codex_profile_dir, (try app.profilePaths(codex_account_id)).profile_dir.slice());
    try testing.expectError(error.UnknownAccount, app.providerHome("acct-missing"));

    const success = try admit(app, codex_account_id, fixture_now);
    _ = try app.applyObservation(success, supportedObservation(fixture_now, demoCredits(2)), fixture_now);

    const failed = try admit(app, codex_account_id, fixture_now + 30);
    app.abandonOperation(failed, fixture_now + 30, codex.public_code_app_server_unavailable);
    try testing.expect(app.schedulerIsIdle());

    const status = app.statusFor(codex_account_id).?;
    try testing.expectEqual(domain.RefreshPhase.failed, status.phase);
    try testing.expectEqualStrings(codex.public_code_app_server_unavailable, status.last_attempt_code.?);
    try testing.expectEqual(@as(?i64, fixture_now + 30), status.last_attempt_at_unix_s);
    try testing.expectEqual(@as(?i64, fixture_now), status.last_success_at_unix_s);
    try testing.expectEqual(@as(usize, 2), app.snapshotFor(codex_account_id).?.windows.len);

    const next = try admit(app, codex_account_id, fixture_now + 60);
    try testing.expect(next.operation_id != failed.operation_id);
    try testing.expectError(
        error.UnknownOperation,
        app.applyObservation(failed, supportedObservation(fixture_now + 60, null), fixture_now + 60),
    );
}
