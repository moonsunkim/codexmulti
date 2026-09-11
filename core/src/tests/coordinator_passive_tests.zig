const std = @import("std");
const account_registry = @import("../account_registry.zig");
const coordinator = @import("../coordinator.zig");
const domain = @import("../domain.zig");
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
const codex_home = support.codex_home;
const codex_profile_dir = support.codex_profile_dir;
const codex_executable = support.codex_executable;
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

const frame = protocol.frame;
const resultFrame = protocol.resultFrame;

const initialize_result = "{\"userAgent\":\"codex-demo/0.0\",\"codexHome\":\"" ++ codex_home ++ "\"}";
const account_result = "{\"account\":{\"type\":\"chatgpt\",\"email\":\"demo-user@example.invalid\"}}";
const rate_limits_result =
    "{\"rateLimits\":{\"primary\":{\"usedPercent\":24,\"windowDurationMins\":300,\"resetsAt\":2000003600}," ++
    "\"secondary\":{\"usedPercent\":61,\"windowDurationMins\":10080,\"resetsAt\":2000600000}}," ++
    "\"rateLimitResetCredits\":{\"availableCount\":2,\"credits\":[" ++
    "{\"id\":\"credit-demo-b\",\"description\":\"Later reset\",\"expiresAt\":2000600000}," ++
    "{\"id\":\"credit-demo-a\",\"description\":\"Earlier reset\",\"expiresAt\":2000300000}]}}";

fn readScript(comptime first_id: u8, comptime limits: []const u8) []const u8 {
    const a = std.fmt.comptimePrint("{d}", .{first_id});
    const b = std.fmt.comptimePrint("{d}", .{first_id + 1});
    const c = std.fmt.comptimePrint("{d}", .{first_id + 2});
    return resultFrame(a, initialize_result) ++ resultFrame(b, account_result) ++ resultFrame(c, limits);
}
const script_read = readScript(1, rate_limits_result);

test "load, tray, details, and countdown perform no provider I/O" {
    const app = try newCoordinator();
    defer app.destroy();
    const sink = try RecordingSink.create();
    defer sink.destroy();

    const codex_harness = try CodexHarness.create(&.{.{ .bytes = script_read }});
    defer codex_harness.destroy();

    try seedAccounts(app);
    const ticket = try admit(app, codex_account_id, fixture_now);
    _ = try app.applyObservation(ticket, supportedObservation(fixture_now, demoCredits(2)), fixture_now);
    try app.persistAll(sink.sink());
    const registry_bytes = sink.lastOf(.registry).?;
    const snapshot_bytes = sink.lastOf(.snapshots).?;

    const restarted = try newCoordinator();
    defer restarted.destroy();
    try restarted.loadRegistryBytes(registry_bytes);
    const loaded = try restarted.loadSnapshotBytes(snapshot_bytes);
    try testing.expectEqual(@as(usize, 1), loaded);
    try testing.expectEqual(@as(usize, 2), restarted.accountCount());

    var tick: i64 = 0;
    while (tick < 60) : (tick += 1) {
        const now = fixture_now + tick;
        var index: usize = 0;
        while (index < restarted.accountCount()) : (index += 1) {
            _ = restarted.rowAt(index, now);
            _ = restarted.statusAt(index);
            _ = restarted.snapshotAt(index);
            _ = restarted.countdownAt(index, now);
        }
        _ = restarted.planLedgerRecovery();
    }

    try testing.expectEqual(@as(usize, 0), codex_harness.stream.arm_count);
    try testing.expectEqual(@as(usize, 0), codex_harness.stream.read_count);
    try testing.expectEqual(@as(usize, 0), codex_harness.stream.written_len);
    try testing.expectEqual(@as(usize, 0), restarted.inFlightCount());
    try testing.expectEqual(@as(usize, 0), restarted.queuedCount());
}

test "a restored snapshot claims only its own age" {
    const app = try newCoordinator();
    defer app.destroy();
    const sink = try RecordingSink.create();
    defer sink.destroy();
    try seedAccounts(app);

    const ticket = try admit(app, codex_account_id, fixture_now);
    _ = try app.applyObservation(ticket, supportedObservation(fixture_now, demoCredits(2)), fixture_now);

    const live_row = app.rowFor(codex_account_id, fixture_now).?;
    try testing.expectEqual(coordinator.Freshness.as_of, live_row.freshness);
    try testing.expectEqual(@as(u8, 61), live_row.window.?.used_percent);
    try testing.expectEqualStrings("Current week", live_row.window.?.label);
    try testing.expectEqual(@as(u32, 2), live_row.reset_credit_count.?);

    try app.persistAll(sink.sink());
    const restarted = try newCoordinator();
    defer restarted.destroy();
    try restarted.loadRegistryBytes(sink.lastOf(.registry).?);
    _ = try restarted.loadSnapshotBytes(sink.lastOf(.snapshots).?);

    const saved_row = restarted.rowFor(codex_account_id, fixture_now).?;
    try testing.expectEqual(coordinator.Freshness.saved_snapshot, saved_row.freshness);
    try testing.expectEqual(@as(?i64, fixture_now), saved_row.snapshot_captured_at_unix_s);
    try testing.expectEqual(@as(?i64, null), saved_row.last_attempt_at_unix_s);
    try testing.expectEqual(@as(?i64, fixture_now), saved_row.last_success_at_unix_s);
    try testing.expectEqual(@as(?i64, 86_400), saved_row.countdown.remaining_s);
    try testing.expect(!saved_row.countdown.passed);

    const later = fixture_now + 90_000;
    const passed_row = restarted.rowFor(codex_account_id, later).?;
    try testing.expectEqual(coordinator.Freshness.reset_passed, passed_row.freshness);
    try testing.expectEqual(@as(?i64, 0), passed_row.countdown.remaining_s);
    try testing.expect(passed_row.countdown.passed);
    try testing.expectEqual(@as(?i64, fixture_now), passed_row.snapshot_captured_at_unix_s);
}

test "a supported observation replaces the snapshot whole" {
    const app = try newCoordinator();
    defer app.destroy();
    try seedAccounts(app);

    const first = try admit(app, codex_account_id, fixture_now);
    const first_report = try app.applyObservation(first, supportedObservation(fixture_now, demoCredits(2)), fixture_now);
    try testing.expect(first_report.replaced_snapshot);
    try testing.expectEqual(@as(usize, 2), first_report.windows_stored);
    try testing.expectEqual(@as(u32, 2), first_report.credits_available.?);

    const stored = app.snapshotFor(codex_account_id).?;
    try testing.expectEqual(@as(usize, 2), stored.windows.len);
    try testing.expectEqual(@as(u32, 2), stored.reset_credits.?.available_count);
    try testing.expectEqual(@as(usize, 2), stored.reset_credits.?.details.len);

    try testing.expectEqualStrings("credit-demo-a", stored.reset_credits.?.details[1].id);

    const one_window = [_]domain.UsageWindow{demo_windows[0]};
    const second = try admit(app, codex_account_id, fixture_now + 10);
    _ = try app.applyObservation(second, .{ .supported = .{
        .status = .fresh,
        .observed_at_unix_s = fixture_now + 10,
        .windows = &one_window,
    } }, fixture_now + 10);

    const replaced = app.snapshotFor(codex_account_id).?;
    try testing.expectEqual(@as(usize, 1), replaced.windows.len);
    try testing.expect(replaced.reset_credits == null);
    try testing.expectEqual(@as(i64, fixture_now + 10), replaced.captured_at_unix_s);
    try testing.expectEqualStrings("Current session", replaced.windows[0].label);
}

test "a failed attempt preserves the last success and is reported separately" {
    const app = try newCoordinator();
    defer app.destroy();
    try seedAccounts(app);

    const success = try admit(app, codex_account_id, fixture_now);
    _ = try app.applyObservation(success, supportedObservation(fixture_now, demoCredits(2)), fixture_now);

    const failed = try admit(app, codex_account_id, fixture_now + 300);
    const report = try app.applyObservation(failed, .{ .failure = .{
        .failure = .{ .kind = .timeout, .public_code = codex.public_code_timeout, .retryable = true },
        .observed_at_unix_s = fixture_now + 300,
    } }, fixture_now + 300);

    try testing.expect(!report.replaced_snapshot);
    try testing.expect(report.retained_previous);
    try testing.expectEqual(domain.RefreshPhase.failed, report.phase);
    try testing.expectEqualStrings(codex.public_code_timeout, report.public_code.?);

    const preserved = app.snapshotFor(codex_account_id).?;
    try testing.expectEqual(@as(i64, fixture_now), preserved.captured_at_unix_s);
    try testing.expectEqual(domain.SnapshotStatus.fresh, preserved.status);
    try testing.expectEqual(@as(usize, 2), preserved.windows.len);
    try testing.expect(preserved.refresh_error == null);

    const status = app.statusFor(codex_account_id).?;
    try testing.expectEqual(@as(?i64, fixture_now + 300), status.last_attempt_at_unix_s);
    try testing.expectEqual(@as(?i64, fixture_now), status.last_success_at_unix_s);
    try testing.expectEqualStrings(codex.public_code_timeout, status.last_attempt_code.?);
    try testing.expectEqual(coordinator.Freshness.refresh_failed, app.rowFor(codex_account_id, fixture_now + 300).?.freshness);

    const reauth = try admit(app, codex_account_id, fixture_now + 600);
    const reauth_report = try app.applyObservation(reauth, .{ .failure = .{
        .failure = codex.signInRequired(),
        .observed_at_unix_s = fixture_now + 600,
    } }, fixture_now + 600);
    try testing.expectEqual(domain.RefreshPhase.reauth_required, reauth_report.phase);
    try testing.expectEqual(account_registry.AuthState.reauth_required, app.account(codex_account_id).?.auth_state);
    try testing.expectEqual(@as(usize, 2), app.snapshotFor(codex_account_id).?.windows.len);
    try testing.expectEqual(coordinator.Freshness.reauth_required, app.rowFor(codex_account_id, fixture_now + 600).?.freshness);

    _ = try app.registry.markConnected(codex_account_id, null);
    const deferred = try admit(app, codex_account_id, fixture_now + 900);
    const deferred_report = try app.applyObservation(deferred, .{ .deferred = {} }, fixture_now + 900);
    try testing.expectEqual(domain.RefreshPhase.deferred, deferred_report.phase);
    try testing.expect(deferred_report.retained_previous);
    try testing.expectEqual(coordinator.Freshness.refresh_deferred, app.rowFor(codex_account_id, fixture_now + 900).?.freshness);
    try testing.expectEqual(@as(i64, fixture_now), app.snapshotFor(codex_account_id).?.captured_at_unix_s);
}

test "an observation that does not fit is stored as partial, never as complete" {
    const app = try newCoordinator();
    defer app.destroy();
    try seedAccounts(app);

    var many: [coordinator.max_windows_per_account + 3]domain.UsageWindow = @splat(demo_windows[0]);
    for (&many, 0..) |*window, index| window.used_percent = @intCast(index + 1);

    const ticket = try admit(app, codex_account_id, fixture_now);
    _ = try app.applyObservation(ticket, .{ .supported = .{
        .status = .fresh,
        .observed_at_unix_s = fixture_now,
        .windows = &many,
    } }, fixture_now);

    const stored = app.snapshotFor(codex_account_id).?;
    try testing.expectEqual(coordinator.max_windows_per_account, stored.windows.len);
    try testing.expectEqual(domain.SnapshotStatus.partial, stored.status);
    try testing.expectEqualStrings(coordinator.public_code_snapshot_capacity, stored.refresh_error.?.public_code);
}

test "a codex refresh runs the official read sequence and keeps the count authoritative" {
    const app = try newCoordinator();
    defer app.destroy();
    const sink = try RecordingSink.create();
    defer sink.destroy();
    const harness = try CodexHarness.create(&.{.{ .bytes = script_read }});
    defer harness.destroy();
    try seedAccounts(app);

    const ticket = try admit(app, codex_account_id, fixture_now);
    const report = app.runRefresh(ticket, harness.live(codex_home, true), fixture_now, sink.sink());

    try testing.expect(report.reached_provider);
    try testing.expect(report.replaced_snapshot);
    try testing.expectEqual(domain.RefreshPhase.succeeded, report.phase);
    try testing.expectEqual(@as(u32, 2), report.credits_available.?);
    try testing.expect(report.persist_code == null);

    const snapshot = app.snapshotFor(codex_account_id).?;
    try testing.expectEqual(@as(usize, 2), snapshot.windows.len);
    try testing.expectEqual(@as(u32, 2), snapshot.reset_credits.?.available_count);
    try testing.expectEqual(domain.CreditDetailStatus.detailed, snapshot.reset_credits.?.detail_status);

    var frames = harness.stream.writtenFrames();
    const methods = [_][]const u8{ "initialize", "initialized", "account/read", "account/rateLimits/read" };
    for (methods) |method| {
        const line = frames.next() orelse return error.MissingFrame;
        try testing.expect(std.mem.indexOf(u8, line, method) != null);
    }

    try testing.expect(std.mem.indexOf(u8, harness.stream.writtenBytes(), codex_home) == null);
    try testing.expect(std.mem.indexOf(u8, harness.stream.writtenBytes(), "example.invalid") == null);

    try testing.expect(harness.lifecycle.inner.reapedExactlyOnce());

    try testing.expectEqual(@as(usize, 1), sink.countOf(.snapshots));
    try testing.expect(std.mem.indexOf(u8, sink.lastOf(.snapshots).?, "credit-demo-a") != null);
}

test "a codex adapter aimed at another account is refused before any byte is written" {
    const app = try newCoordinator();
    defer app.destroy();
    const sink = try RecordingSink.create();
    defer sink.destroy();
    const harness = try CodexHarness.create(&.{.{ .bytes = script_read }});
    defer harness.destroy();
    try seedAccounts(app);

    const ticket = try admit(app, codex_account_id, fixture_now);
    const report = app.runRefresh(
        ticket,
        harness.live(accounts_root ++ "/codex-other/codex", true),
        fixture_now,
        sink.sink(),
    );

    try testing.expect(!report.reached_provider);
    try testing.expectEqualStrings(coordinator.public_code_home_mismatch, report.public_code.?);
    try testing.expectEqual(@as(usize, 0), harness.stream.written_len);
    try testing.expectEqual(@as(usize, 0), harness.stream.read_count);
    try testing.expect(app.snapshotFor(codex_account_id) == null);
    try testing.expect(harness.lifecycle.inner.reapedExactlyOnce());
    try testing.expect(app.schedulerIsIdle());

    const mismatch_harness = try CodexHarness.create(&.{.{ .bytes = script_read }});
    defer mismatch_harness.destroy();
    const second = try admit(app, claude_account_id, fixture_now + 5);
    const mismatch = app.runRefresh(
        second,
        mismatch_harness.live(codex_home, true),
        fixture_now + 5,
        sink.sink(),
    );
    try testing.expect(!mismatch.reached_provider);
    try testing.expectEqualStrings(coordinator.public_code_provider_mismatch, mismatch.public_code.?);
    try testing.expectEqual(@as(usize, 0), mismatch_harness.stream.written_len);
}
