const std = @import("std");
const domain = @import("../domain.zig");
const fixtures = @import("../fixtures.zig");
const store = @import("../store.zig");

const testing = std.testing;

test "snapshot document JSON round trip preserves provider-neutral state" {
    const snapshots = [_]domain.UsageSnapshot{ fixtures.fresh_snapshot, fixtures.partial_snapshot };
    const document: store.SnapshotDocument = .{ .profiles = &fixtures.profiles, .snapshots = &snapshots };

    const bytes = try store.encode(testing.allocator, document);
    defer testing.allocator.free(bytes);
    var parsed = try store.decodeSnapshots(testing.allocator, bytes);
    defer parsed.deinit();

    try testing.expectEqual(store.current_schema_version, parsed.value.schema_version);
    try testing.expectEqual(@as(usize, 2), parsed.value.profiles.len);
    try testing.expectEqual(domain.Provider.codex, parsed.value.profiles[0].provider);
    try testing.expectEqualStrings("acct-codex-demo", parsed.value.snapshots[0].account_id);
    try testing.expectEqual(@as(u8, 24), parsed.value.snapshots[0].windows[0].used_percent);
    try testing.expectEqual(@as(u32, 2), parsed.value.snapshots[0].reset_credits.?.available_count);
    try testing.expectEqual(domain.SnapshotStatus.partial, parsed.value.snapshots[1].status);
}

test "attempt document JSON round trip retains one immutable idempotency key" {
    var attempt = fixtures.preparedAttempt();
    try attempt.markSubmitted(fixtures.fixture_now_unix_s + 2, 30);
    try attempt.markAmbiguous(fixtures.fixture_now_unix_s + 3);
    const attempts = [_]domain.ResetAttempt{attempt};
    const document: store.AttemptDocument = .{ .attempts = &attempts };

    const bytes = try store.encode(testing.allocator, document);
    defer testing.allocator.free(bytes);
    var parsed = try store.decodeAttempts(testing.allocator, bytes);
    defer parsed.deinit();

    try testing.expectEqual(domain.ResetAttemptPhase.ambiguous, parsed.value.attempts[0].phase);
    try testing.expectEqualStrings("attempt-demo-0001", parsed.value.attempts[0].idempotency_key);
    try testing.expect(parsed.value.attempts[0].outcome == null);
}

test "snapshot replacement never merges fields from the stale observation" {
    var snapshots = [_]domain.UsageSnapshot{fixtures.fresh_snapshot};
    const replacement: domain.UsageSnapshot = .{
        .account_id = "acct-codex-demo",
        .provider = .codex,
        .captured_at_unix_s = fixtures.fixture_now_unix_s + 10,
        .status = .reauth_required,
        .refresh_error = .{ .kind = .authentication, .public_code = "sign-in-required", .retryable = false },
    };

    try testing.expect(domain.replaceSnapshot(&snapshots, replacement));
    try testing.expectEqual(@as(usize, 0), snapshots[0].windows.len);
    try testing.expect(snapshots[0].reset_credits == null);
    try testing.expectEqual(domain.SnapshotStatus.reauth_required, snapshots[0].status);
    try testing.expect(!domain.replaceSnapshot(&snapshots, fixtures.stale_snapshot));
}

test "refresh state enforces operation ownership and terminal transitions" {
    var state: domain.RefreshState = .{};
    try state.begin(7, 100);
    try testing.expectError(error.AlreadyRefreshing, state.begin(8, 101));
    try testing.expectError(error.OperationMismatch, state.succeed(8, 102));
    try state.fail(7, 103, .{ .kind = .timeout, .public_code = "refresh-timeout", .retryable = true });
    try testing.expectEqual(domain.RefreshPhase.failed, state.phase);
    try testing.expectEqual(@as(?i64, 103), state.finished_at_unix_s);
    try testing.expect(state.last_error.?.retryable);

    try state.begin(9, 104);
    try state.requireReauth(9, 105, .{ .kind = .authentication, .public_code = "sign-in-required", .retryable = false });
    try testing.expectEqual(domain.RefreshPhase.reauth_required, state.phase);

    state.markDeferred();
    try testing.expectEqual(domain.RefreshPhase.deferred, state.phase);
    state.markUnavailable(.{ .kind = .provider_unavailable, .public_code = "provider-unavailable", .retryable = true });
    try testing.expectEqual(domain.RefreshPhase.unavailable, state.phase);
}

test "reset attempt refuses stale preflight and preserves retry identity" {
    var attempt = fixtures.preparedAttempt();
    try attempt.assertSameOperation("acct-codex-demo", "credit-demo-a");
    try testing.expectError(error.IdempotencyConflict, attempt.assertSameOperation("acct-other-demo", "credit-demo-a"));
    try testing.expectError(error.StalePreflight, attempt.markSubmitted(fixtures.fixture_now_unix_s + 61, 60));
    try testing.expectEqual(domain.ResetAttemptPhase.prepared, attempt.phase);

    try attempt.markSubmitted(fixtures.fixture_now_unix_s + 10, 60);
    try attempt.markAmbiguous(fixtures.fixture_now_unix_s + 11);
    try testing.expectEqualStrings("attempt-demo-0001", attempt.idempotency_key);
    try attempt.complete(.already_redeemed, fixtures.fixture_now_unix_s + 12);
    try attempt.complete(.already_redeemed, fixtures.fixture_now_unix_s + 13);
    try testing.expectError(error.OutcomeConflict, attempt.complete(.reset, fixtures.fixture_now_unix_s + 14));
}

test "reset attempt cannot exist without confirmation-order and credit invariants" {
    try testing.expectError(error.NoCredit, domain.ResetAttempt.init("attempt-demo-zero", "acct-codex-demo", null, 100, 0, 101));
    try testing.expectError(error.ConfirmationBeforePreflight, domain.ResetAttempt.init("attempt-demo-time", "acct-codex-demo", null, 101, 1, 100));
    try testing.expectError(error.InvalidIdempotencyKey, domain.ResetAttempt.init("", "acct-codex-demo", null, 100, 1, 101));
}

test "availableCount remains authoritative for count-only and capped details" {
    try testing.expectEqual(@as(u32, 3), fixtures.count_only_credits.authoritativeCount());
    try testing.expectEqual(@as(usize, 0), fixtures.count_only_credits.details.len);
    try testing.expect(!fixtures.count_only_credits.detailsAreComplete());

    const capped_details = fixtures.detailed_credit_items[0..1];
    const capped: domain.ResetCreditSummary = .{
        .available_count = 4,
        .observed_at_unix_s = fixtures.fixture_now_unix_s,
        .detail_status = .detailed,
        .details = capped_details,
    };
    try testing.expectEqual(@as(u32, 4), capped.authoritativeCount());
    try testing.expectEqual(@as(usize, 1), capped.knownUnexpiredDetailCount(fixtures.fixture_now_unix_s));
    try testing.expect(!capped.detailsAreComplete());
}

test "expired detail is not selectable but does not override authoritative count" {
    const summary = fixtures.expired_detail_credits;
    try testing.expect(summary.details[0].isExpired(fixtures.fixture_now_unix_s));
    try testing.expectEqual(@as(usize, 0), summary.knownUnexpiredDetailCount(fixtures.fixture_now_unix_s));
    try testing.expectEqual(@as(u32, 1), summary.authoritativeCount());
    try testing.expect(!fixtures.detailed_credit_items[0].isExpired(fixtures.fixture_now_unix_s));
}

test "fixtures cover every offline snapshot state" {
    var seen: [7]bool = @splat(false);
    for (fixtures.all_snapshots) |snapshot| seen[@intFromEnum(snapshot.status)] = true;
    for (seen) |value| try testing.expect(value);
    try testing.expectEqual(@as(u32, 3), fixtures.count_only_snapshot.reset_credits.?.available_count);
    try testing.expectEqual(@as(u32, 0), fixtures.no_credit_snapshot.reset_credits.?.available_count);
}

test "persisted JSON has no credential-bearing field names or values" {
    const snapshots = [_]domain.UsageSnapshot{ fixtures.fresh_snapshot, fixtures.reauth_snapshot, fixtures.error_snapshot };
    const snapshot_document: store.SnapshotDocument = .{ .profiles = &fixtures.profiles, .snapshots = &snapshots };
    const snapshot_bytes = try store.encode(testing.allocator, snapshot_document);
    defer testing.allocator.free(snapshot_bytes);

    const attempt = fixtures.preparedAttempt();
    const attempts = [_]domain.ResetAttempt{attempt};
    const attempt_bytes = try store.encode(testing.allocator, store.AttemptDocument{ .attempts = &attempts });
    defer testing.allocator.free(attempt_bytes);

    const forbidden = [_][]const u8{
        "access_token",
        "refresh_token",
        "api_key",
        "password",
        "authorization",
        "session_cookie",
        "bearer ",
    };
    for (forbidden) |needle| {
        try testing.expect(std.mem.indexOf(u8, snapshot_bytes, needle) == null);
        try testing.expect(std.mem.indexOf(u8, attempt_bytes, needle) == null);
    }
}

test "schema validation rejects incompatible and internally invalid documents" {
    const wrong_version =
        \\{"schema_version":2,"profiles":[],"snapshots":[]}
    ;
    try testing.expectError(error.UnsupportedSchemaVersion, store.decodeSnapshots(testing.allocator, wrong_version));

    const duplicate_attempts = [_]domain.ResetAttempt{ fixtures.preparedAttempt(), fixtures.preparedAttempt() };
    try testing.expectError(error.DuplicateIdempotencyKey, store.validateAttemptDocument(.{ .attempts = &duplicate_attempts }));
}

test "atomic file helpers replace complete snapshot and attempt documents" {
    const directory = ".zig-cache/test-ai-usage-domain-store";
    var cwd = std.Io.Dir.cwd();
    cwd.deleteTree(testing.io, directory) catch {};
    try cwd.createDirPath(testing.io, directory);
    defer cwd.deleteTree(testing.io, directory) catch {};
    var dir = try cwd.openDir(testing.io, directory, .{});
    defer dir.close(testing.io);

    const snapshots = [_]domain.UsageSnapshot{fixtures.fresh_snapshot};
    try store.saveSnapshotsAtomic(testing.allocator, testing.io, dir, "snapshots.json", "snapshots.json.tmp", .{
        .profiles = &fixtures.profiles,
        .snapshots = &snapshots,
    });
    var loaded_snapshots = try store.loadSnapshots(testing.allocator, testing.io, dir, "snapshots.json");
    defer loaded_snapshots.deinit();
    try testing.expectEqualStrings("acct-codex-demo", loaded_snapshots.value.snapshots[0].account_id);
    try testing.expectError(error.FileNotFound, dir.statFile(testing.io, "snapshots.json.tmp", .{}));

    const attempt = fixtures.preparedAttempt();
    const attempts = [_]domain.ResetAttempt{attempt};
    try store.saveAttemptsAtomic(testing.allocator, testing.io, dir, "attempts.json", "attempts.json.tmp", .{ .attempts = &attempts });
    var loaded_attempts = try store.loadAttempts(testing.allocator, testing.io, dir, "attempts.json");
    defer loaded_attempts.deinit();
    try testing.expectEqualStrings("attempt-demo-0001", loaded_attempts.value.attempts[0].idempotency_key);
    try testing.expectError(error.TempPathMatchesFinalPath, store.writeAtomically(testing.io, dir, "same.json", "same.json", "{}"));
}
