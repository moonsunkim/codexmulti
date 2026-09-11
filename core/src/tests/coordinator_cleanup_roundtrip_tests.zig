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

const claude_usage_body =
    \\{"five_hour":{"utilization":42,"resets_at":2000003600},
    \\ "seven_day":{"utilization":61,"resets_at":2000600000}}
;
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

test "removing an account returns a plan and deletes nothing" {
    const app = try newCoordinator();
    defer app.destroy();
    const sink = try RecordingSink.create();
    defer sink.destroy();
    try seedAccounts(app);
    const ticket = try admit(app, codex_account_id, fixture_now);
    _ = try app.applyObservation(ticket, supportedObservation(fixture_now, demoCredits(2)), fixture_now);

    const plan = try app.planAccountRemoval(codex_account_id);
    try testing.expectEqualStrings(codex_account_id, plan.account_id);
    try testing.expect(plan.requires_confirmation);
    try testing.expect(plan.isExecutable());
    try testing.expect(plan.removes_snapshot);
    try testing.expectEqual(@as(usize, 2), plan.directorySlice().len);
    try testing.expectEqualStrings(codex_home, plan.directorySlice()[0].slice());
    try testing.expectEqualStrings(codex_profile_dir, plan.directorySlice()[1].slice());
    try testing.expectEqual(@as(usize, 5), plan.credential_slots.len);

    try testing.expectEqual(@as(usize, 2), app.accountCount());
    try testing.expect(app.snapshotFor(codex_account_id) != null);
    try testing.expectEqual(@as(usize, 0), sink.record_count);

    var credentials: keychain.MemoryStore = .{};
    defer credentials.deinit();
    try testing.expectError(error.ConfirmationMismatch, app.applyAccountRemoval(
        plan,
        .{ .account_id = claude_account_id, .delete_credentials = true },
        credentials.store(),
        sink.sink(),
    ));

    try testing.expectError(error.CredentialStoreMissing, app.applyAccountRemoval(
        plan,
        .{ .account_id = codex_account_id, .delete_credentials = true },
        null,
        sink.sink(),
    ));
    try testing.expectEqual(@as(usize, 2), app.accountCount());
}

test "confirmed removal forgets metadata, keeps history, and never touches directories" {
    const app = try newCoordinator();
    defer app.destroy();
    const sink = try RecordingSink.create();
    defer sink.destroy();
    var credentials: keychain.MemoryStore = .{};
    defer credentials.deinit();
    try seedAccounts(app);

    const codex_ticket = try admit(app, codex_account_id, fixture_now);
    _ = try app.applyObservation(codex_ticket, supportedObservation(fixture_now, demoCredits(2)), fixture_now);
    const claude_ticket = try admit(app, claude_account_id, fixture_now);
    _ = try app.applyObservation(claude_ticket, supportedObservation(fixture_now, null), fixture_now);

    var session = try app.openResetSession(codex_account_id, .details, fixture_now);
    const step = try app.beginSessionStep(&session, .reset_preflight, fixture_now);
    _ = try app.applyObservation(step, supportedObservation(fixture_now, demoCredits(2)), fixture_now);
    const offer = try app.prepareResetOffer(&session, fixture_now);
    const confirmation = try app.confirmResetOffer(&session, offer, fixture_now);
    _ = try app.beginResetAttempt(.{
        .session = &session,
        .confirmation = confirmation,
        .idempotency_key = "attempt-demo-0009",
        .now_unix_s = fixture_now,
        .sink = sink.sink(),
    });
    _ = try app.applyResetOutcome(&session, .{ .completed = .reset }, fixture_now + 1, sink.sink());
    app.closeResetSession(&session, coordinator.noChildLifecycle());

    var access = try keychain.Credential.init(canary_access);
    defer access.wipe();
    const account_key = try keychain.AccountKey.init(codex_storage_key);
    try credentials.store().save(&account_key, .access_token, &access);
    credentials.resetOperations();
    sink.reset();

    const plan = try app.planAccountRemoval(codex_account_id);
    try testing.expectEqual(@as(usize, 1), plan.retained_attempts);
    const result = try app.applyAccountRemoval(
        plan,
        .{ .account_id = codex_account_id, .delete_credentials = true, .directories_acknowledged = true },
        credentials.store(),
        sink.sink(),
    );

    try testing.expect(result.removed_registry_entry);
    try testing.expect(result.removed_snapshot);
    try testing.expectEqual(@as(usize, 5), result.removed_credential_slots);
    try testing.expectEqual(@as(usize, 1), result.retained_attempts);

    try testing.expectEqual(@as(usize, 2), result.directories_pending);
    try testing.expect(result.persist_code == null);

    try testing.expectEqual(@as(usize, 1), app.accountCount());
    try testing.expect(app.account(codex_account_id) == null);
    try testing.expect(app.snapshotFor(codex_account_id) == null);
    try testing.expect(app.snapshotFor(claude_account_id) != null);
    try testing.expectEqual(@as(usize, 2), app.snapshotFor(claude_account_id).?.windows.len);
    try testing.expectEqual(@as(usize, 1), app.attempts().len);
    try testing.expectEqualStrings("attempt-demo-0009", app.attempts()[0].idempotency_key);

    var loaded: keychain.Credential = .empty;
    defer loaded.wipe();
    try testing.expectError(error.NotFound, credentials.store().load(&account_key, .access_token, &loaded));
    try testing.expectEqual(@as(usize, 1), sink.countOf(.registry));
    try testing.expectEqual(@as(usize, 1), sink.countOf(.snapshots));
}

test "reordering accounts carries each snapshot with its own account" {
    const app = try newCoordinator();
    defer app.destroy();
    try seedAccounts(app);

    const codex_ticket = try admit(app, codex_account_id, fixture_now);
    _ = try app.applyObservation(codex_ticket, supportedObservation(fixture_now, demoCredits(2)), fixture_now);
    const claude_ticket = try admit(app, claude_account_id, fixture_now + 1);
    const one_window = [_]domain.UsageWindow{demo_windows[0]};
    _ = try app.applyObservation(claude_ticket, .{ .supported = .{
        .status = .fresh,
        .observed_at_unix_s = fixture_now + 1,
        .windows = &one_window,
    } }, fixture_now + 1);

    try app.moveAccount(claude_account_id, 0);
    try testing.expectEqualStrings(claude_account_id, app.accountAt(0).?.id);
    try testing.expectEqualStrings(codex_account_id, app.accountAt(1).?.id);

    const claude_snapshot = app.snapshotAt(0).?;
    try testing.expectEqualStrings(claude_account_id, claude_snapshot.account_id);
    try testing.expectEqual(@as(usize, 1), claude_snapshot.windows.len);
    try testing.expectEqualStrings("Current session", claude_snapshot.windows[0].label);
    try testing.expect(claude_snapshot.reset_credits == null);

    const codex_snapshot = app.snapshotAt(1).?;
    try testing.expectEqualStrings(codex_account_id, codex_snapshot.account_id);
    try testing.expectEqual(@as(usize, 2), codex_snapshot.windows.len);
    try testing.expectEqualStrings("Current week", codex_snapshot.windows[1].label);
    try testing.expectEqual(@as(u32, 2), codex_snapshot.reset_credits.?.available_count);
    try testing.expectEqualStrings("credit-demo-a", codex_snapshot.reset_credits.?.details[1].id);
    try testing.expectEqual(@as(?i64, fixture_now + 1), app.statusFor(claude_account_id).?.last_success_at_unix_s);

    try testing.expectError(error.UnknownAccount, app.moveAccount("acct-missing", 0));

    _ = try app.requestRefresh(codex_account_id);
    try testing.expectError(error.SchedulerBusy, app.moveAccount(codex_account_id, 0));
}

test "removal is blocked while an attempt is unsettled or the account is busy" {
    const app = try newCoordinator();
    defer app.destroy();
    const sink = try RecordingSink.create();
    defer sink.destroy();
    var credentials: keychain.MemoryStore = .{};
    defer credentials.deinit();
    try seedAccounts(app);

    const ticket = try admit(app, codex_account_id, fixture_now);
    const busy_plan = try app.planAccountRemoval(codex_account_id);
    try testing.expect(!busy_plan.isExecutable());
    try testing.expectEqualStrings(coordinator.public_code_account_busy, busy_plan.blocked_code.?);
    try testing.expectError(error.Blocked, app.applyAccountRemoval(
        busy_plan,
        .{ .account_id = codex_account_id, .delete_credentials = false },
        credentials.store(),
        sink.sink(),
    ));

    _ = try app.applyObservation(ticket, supportedObservation(fixture_now, demoCredits(2)), fixture_now);
    _ = try app.requestRefresh(claude_account_id);
    const queued_plan = try app.planAccountRemoval(codex_account_id);
    try testing.expect(!queued_plan.isExecutable());
    try testing.expectEqualStrings(coordinator.public_code_account_busy, queued_plan.blocked_code.?);
    const queued_ticket = app.nextOperation(fixture_now).?;
    _ = try app.applyObservation(queued_ticket, .{ .deferred = {} }, fixture_now);
    try testing.expect(app.schedulerIsIdle());

    var session = try app.openResetSession(codex_account_id, .details, fixture_now);
    const step = try app.beginSessionStep(&session, .reset_preflight, fixture_now);
    _ = try app.applyObservation(step, supportedObservation(fixture_now, demoCredits(2)), fixture_now);
    const offer = try app.prepareResetOffer(&session, fixture_now);
    const confirmation = try app.confirmResetOffer(&session, offer, fixture_now);
    _ = try app.beginResetAttempt(.{
        .session = &session,
        .confirmation = confirmation,
        .idempotency_key = "attempt-demo-0010",
        .now_unix_s = fixture_now,
        .sink = sink.sink(),
    });
    app.closeResetSession(&session, coordinator.noChildLifecycle());

    const pending_plan = try app.planAccountRemoval(codex_account_id);
    try testing.expect(!pending_plan.isExecutable());
    try testing.expectEqualStrings(coordinator.public_code_attempt_pending, pending_plan.blocked_code.?);
    try testing.expectEqual(@as(usize, 2), app.accountCount());
}

test "no document, report, or plan carries credential material" {
    const app = try newCoordinator();
    defer app.destroy();
    const sink = try RecordingSink.create();
    defer sink.destroy();
    try seedAccounts(app);
    _ = try app.registry.setProviderIdentity(codex_account_id, canary_identity);

    const ticket = try admit(app, codex_account_id, fixture_now);
    const report = try app.applyObservation(
        ticket,
        supportedObservation(fixture_now, demoCredits(2)),
        fixture_now,
    );
    try testing.expect(report.replaced_snapshot);

    var session = try app.openResetSession(codex_account_id, .details, fixture_now);
    const step = try app.beginSessionStep(&session, .reset_preflight, fixture_now);
    _ = try app.applyObservation(step, supportedObservation(fixture_now, demoCredits(2)), fixture_now);
    const offer = try app.prepareResetOffer(&session, fixture_now);
    const confirmation = try app.confirmResetOffer(&session, offer, fixture_now);
    _ = try app.beginResetAttempt(.{
        .session = &session,
        .confirmation = confirmation,
        .idempotency_key = "attempt-demo-0011",
        .now_unix_s = fixture_now,
        .sink = sink.sink(),
    });
    app.closeResetSession(&session, coordinator.noChildLifecycle());
    try app.persistAll(sink.sink());

    const forbidden = [_][]const u8{
        canary_access,
        canary_refresh,
        "Bearer",
        "access_token",
        "refresh_token",
        "api_key",
        "password",
        "authorization",
        "session_cookie",
        "expires_in",
        "client_id",
    };
    for (forbidden) |needle| {
        try testing.expect(std.mem.indexOf(u8, sink.allBytes(), needle) == null);
    }

    const registry_bytes = sink.lastOf(.registry).?;
    try testing.expect(std.mem.indexOf(u8, registry_bytes, "token") == null);

    try testing.expect(std.mem.indexOf(u8, sink.lastOf(.snapshots).?, "expires_at_unix_s") != null);

    if (report.public_code) |code| try testing.expect(coordinator.isPublicCode(code));
    try testing.expectEqualStrings(
        coordinator.public_code_refresh_failed,
        coordinator.canonicalPublicCode("provider said: token demo-access-placeholder-1111 expired"),
    );
    const sanitized = coordinator.sanitizeRefreshError(.{
        .kind = .authentication,
        .public_code = "raw provider text with " ++ canary_access,
        .retryable = false,
    });
    try testing.expectEqualStrings(coordinator.public_code_refresh_failed, sanitized.public_code);
    try testing.expect(std.mem.indexOf(u8, sanitized.public_code, canary_access) == null);

    try testing.expect(std.mem.indexOf(u8, sink.lastOf(.registry).?, canary_identity) != null);
}

test "documents round trip through the atomic file sink" {
    const directory = ".zig-cache/test-ai-usage-coordinator";
    var cwd = std.Io.Dir.cwd();
    cwd.deleteTree(testing.io, directory) catch {};
    try cwd.createDirPath(testing.io, directory);
    defer cwd.deleteTree(testing.io, directory) catch {};
    var dir = try cwd.openDir(testing.io, directory, .{});
    defer dir.close(testing.io);

    const app = try newCoordinator();
    defer app.destroy();
    var file_sink: coordinator.FileDocumentSink = .{ .io = testing.io, .dir = dir };
    try seedAccounts(app);
    const ticket = try admit(app, codex_account_id, fixture_now);
    _ = try app.applyObservation(ticket, supportedObservation(fixture_now, demoCredits(2)), fixture_now);
    try app.persistAll(file_sink.sink());

    try testing.expectError(error.FileNotFound, dir.statFile(testing.io, runtime_paths.snapshots_temp_file_name, .{}));

    const restarted = try newCoordinator();
    defer restarted.destroy();
    const report = restarted.loadFromDirectory(testing.io, dir);
    try testing.expect(!report.reached_provider);
    try testing.expectEqual(@as(usize, 2), report.accounts_loaded);
    try testing.expectEqual(@as(usize, 1), report.snapshots_loaded);
    try testing.expectEqual(@as(usize, 0), report.attempts_loaded);
    try testing.expect(report.registry_code == null);
    try testing.expect(report.snapshots_code == null);
    try testing.expect(report.attempts_code == null);

    const snapshot = restarted.snapshotFor(codex_account_id).?;
    try testing.expectEqual(@as(usize, 2), snapshot.windows.len);
    try testing.expectEqual(@as(u32, 2), snapshot.reset_credits.?.available_count);
    try testing.expectEqualStrings("credit-demo-a", snapshot.reset_credits.?.details[1].id);
    try testing.expectEqual(account_registry.AuthState.connected, restarted.account(codex_account_id).?.auth_state);

    const empty_directory = ".zig-cache/test-ai-usage-coordinator-empty";
    cwd.deleteTree(testing.io, empty_directory) catch {};
    try cwd.createDirPath(testing.io, empty_directory);
    defer cwd.deleteTree(testing.io, empty_directory) catch {};
    var empty_dir = try cwd.openDir(testing.io, empty_directory, .{});
    defer empty_dir.close(testing.io);
    const fresh = try newCoordinator();
    defer fresh.destroy();
    const fresh_report = fresh.loadFromDirectory(testing.io, empty_dir);
    try testing.expectEqual(@as(usize, 0), fresh_report.accounts_loaded);
    try testing.expect(fresh_report.registry_code == null);
}

test "an unwired sink and an unreadable document fail closed" {
    const app = try newCoordinator();
    defer app.destroy();
    try seedAccounts(app);

    try testing.expectError(error.Unavailable, app.persistRegistry(coordinator.unwiredDocumentSink()));
    try testing.expectError(error.Malformed, app.loadSnapshotBytes("{not json"));
    try testing.expectError(error.Malformed, app.loadAttemptBytes("{\"schema_version\":99,\"attempts\":[]}"));
    try testing.expectError(error.Malformed, app.loadRegistryBytes("{not json"));
    try testing.expectError(
        error.UnsupportedSchemaVersion,
        app.loadRegistryBytes("{\"schema_version\":99,\"accounts\":[]}"),
    );
}

test "declarations stay analyzable" {
    testing.refAllDecls(account_registry);
    testing.refAllDecls(account_registry.Registry);
    testing.refAllDecls(runtime_paths);
    testing.refAllDecls(runtime_paths.Path);
    testing.refAllDecls(runtime_paths.Layout);
    testing.refAllDecls(coordinator);
    testing.refAllDecls(coordinator.Coordinator);
    testing.refAllDecls(coordinator.EnvSpec);
    testing.refAllDecls(coordinator.LoginSpec);
}

test "the file sink and the environment-map bridge are compiled but never run here" {
    _ = &coordinator.FileDocumentSink.sink;
    _ = &coordinator.EnvSpec.writeEnvMap;
    _ = &coordinator.Coordinator.loadFromDirectory;
}
