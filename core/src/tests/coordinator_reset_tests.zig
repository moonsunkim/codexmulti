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
const rate_limits_no_credit_result =
    "{\"rateLimits\":{\"primary\":{\"usedPercent\":24,\"windowDurationMins\":300,\"resetsAt\":2000003600}}}";

fn readScript(comptime first_id: u8, comptime limits: []const u8) []const u8 {
    const a = std.fmt.comptimePrint("{d}", .{first_id});
    const b = std.fmt.comptimePrint("{d}", .{first_id + 1});
    const c = std.fmt.comptimePrint("{d}", .{first_id + 2});
    return resultFrame(a, initialize_result) ++ resultFrame(b, account_result) ++ resultFrame(c, limits);
}

fn consumeScript(comptime first_id: u8, comptime outcome: []const u8) []const u8 {
    const a = std.fmt.comptimePrint("{d}", .{first_id});
    return resultFrame(a, "{\"outcome\":\"" ++ outcome ++ "\"}");
}

fn postReadScript(comptime first_id: u8, comptime limits: []const u8) []const u8 {
    const a = std.fmt.comptimePrint("{d}", .{first_id});
    const b = std.fmt.comptimePrint("{d}", .{first_id + 1});
    return resultFrame(a, account_result) ++ resultFrame(b, limits);
}

const script_read = readScript(1, rate_limits_result);
const script_read_no_credit = readScript(1, rate_limits_no_credit_result);

const script_reset_transaction = readScript(1, rate_limits_result) ++
    consumeScript(4, "reset") ++
    postReadScript(5, rate_limits_no_credit_result);
const script_reset_ambiguous = readScript(1, rate_limits_result) ++
    frame("{\"jsonrpc\":\"2.0\",\"id\":4,\"error\":{\"code\":-32603,\"message\":\"demo-detail-should-not-leak\"}}");

test "a reset offer needs the details surface and a fresh successful preflight" {
    const app = try newCoordinator();
    defer app.destroy();
    const sink = try RecordingSink.create();
    defer sink.destroy();
    const harness = try CodexHarness.create(&.{.{ .bytes = script_read }});
    defer harness.destroy();
    try seedAccounts(app);

    try testing.expectError(error.SurfaceNotAllowed, app.openResetSession(codex_account_id, .tray, fixture_now));

    try testing.expectError(error.ProviderMismatch, app.openResetSession(claude_account_id, .details, fixture_now));

    _ = try app.registry.markAuthState(codex_account_id, .reauth_required);
    try testing.expectError(error.AuthStateNotConnected, app.openResetSession(codex_account_id, .details, fixture_now));
    _ = try app.registry.markConnected(codex_account_id, null);

    var session = try app.openResetSession(codex_account_id, .details, fixture_now);

    try testing.expectEqual(@as(usize, 1), app.inFlightCount());
    try testing.expectError(error.AccountBusy, app.openResetSession(codex_account_id, .details, fixture_now));

    try testing.expectError(error.PreflightMissing, app.prepareResetOffer(&session, fixture_now));

    const report = try runPreflight(app, &session, harness, sink.sink(), fixture_now);
    try testing.expect(report.replaced_snapshot);

    try testing.expect(!harness.lifecycle.inner.closed);
    try testing.expectEqual(@as(usize, 1), app.inFlightCount());

    try testing.expectError(error.StalePreflight, app.prepareResetOffer(&session, fixture_now + 10_000));

    const offer = try app.prepareResetOffer(&session, fixture_now);
    try testing.expectEqual(@as(u32, 2), offer.available_count);

    try testing.expectEqualStrings("credit-demo-a", offer.selected_credit_id.?);
    try testing.expect(!offer.usesNextAvailableWording());
    try testing.expect(offer.revision != 0);

    app.closeResetSession(&session, harness.lifecycle.lifecycle());
    try testing.expect(harness.lifecycle.inner.reapedExactlyOnce());
    try testing.expect(app.schedulerIsIdle());
}

test "a count-only offer says next available and claims no expiry" {
    const app = try newCoordinator();
    defer app.destroy();
    const sink = try RecordingSink.create();
    defer sink.destroy();
    try seedAccounts(app);

    var session = try app.openResetSession(codex_account_id, .details, fixture_now);
    const ticket = try app.beginSessionStep(&session, .reset_preflight, fixture_now);
    _ = try app.applyObservation(ticket, .{ .supported = .{
        .status = .fresh,
        .observed_at_unix_s = fixture_now,
        .windows = &demo_windows,
        .reset_credits = .{
            .available_count = 3,
            .observed_at_unix_s = fixture_now,
            .detail_status = .count_only,
        },
    } }, fixture_now);

    const offer = try app.prepareResetOffer(&session, fixture_now);
    try testing.expectEqual(@as(u32, 3), offer.available_count);
    try testing.expect(offer.selected_credit_id == null);
    try testing.expect(offer.selected_expires_at_unix_s == null);
    try testing.expect(offer.usesNextAvailableWording());
    try testing.expectEqual(domain.CreditDetailStatus.count_only, offer.detail_status);

    const second = try app.beginSessionStep(&session, .reset_preflight, fixture_now + 1);
    _ = try app.applyObservation(second, .{ .supported = .{
        .status = .fresh,
        .observed_at_unix_s = fixture_now + 1,
        .windows = &demo_windows,
        .reset_credits = .{ .available_count = 0, .observed_at_unix_s = fixture_now + 1, .detail_status = .detailed },
    } }, fixture_now + 1);
    try testing.expectError(error.NoCredit, app.prepareResetOffer(&session, fixture_now + 1));

    app.closeResetSession(&session, coordinator.noChildLifecycle());
}

test "confirmation binds to the exact account, auth revision, and offer" {
    const app = try newCoordinator();
    defer app.destroy();
    const sink = try RecordingSink.create();
    defer sink.destroy();
    const harness = try CodexHarness.create(&.{.{ .bytes = script_read }});
    defer harness.destroy();
    try seedAccounts(app);

    var session = try app.openResetSession(codex_account_id, .details, fixture_now);
    defer app.closeResetSession(&session, harness.lifecycle.lifecycle());
    _ = try runPreflight(app, &session, harness, sink.sink(), fixture_now);
    const offer = try app.prepareResetOffer(&session, fixture_now);
    const confirmation = try app.confirmResetOffer(&session, offer, fixture_now + 1);

    try testing.expectEqualStrings(codex_account_id, confirmation.account_id);
    try testing.expectEqual(offer.revision, confirmation.offer_revision);
    try testing.expectEqual(offer.auth_revision, confirmation.auth_revision);
    try testing.expectEqualStrings("credit-demo-a", confirmation.selected_credit_id.?);

    var forged = confirmation;
    forged.offer_revision = confirmation.offer_revision ^ 1;
    try testing.expectError(error.OfferChanged, app.beginResetAttempt(.{
        .session = &session,
        .confirmation = forged,
        .idempotency_key = "attempt-demo-forged",
        .now_unix_s = fixture_now + 2,
        .sink = sink.sink(),
    }));

    _ = try app.registry.markConnected(codex_account_id, null);
    try testing.expectError(error.AuthRevisionChanged, app.beginResetAttempt(.{
        .session = &session,
        .confirmation = confirmation,
        .idempotency_key = "attempt-demo-0001",
        .now_unix_s = fixture_now + 2,
        .sink = sink.sink(),
    }));
    try testing.expectEqual(@as(usize, 0), app.attempts().len);
}

test "a registry or snapshot change between confirmation and send forces reconfirmation" {
    const app = try newCoordinator();
    defer app.destroy();
    const sink = try RecordingSink.create();
    defer sink.destroy();
    const harness = try CodexHarness.create(&.{.{ .bytes = script_read }});
    defer harness.destroy();
    try seedAccounts(app);

    var session = try app.openResetSession(codex_account_id, .details, fixture_now);
    defer app.closeResetSession(&session, harness.lifecycle.lifecycle());
    _ = try runPreflight(app, &session, harness, sink.sink(), fixture_now);
    const offer = try app.prepareResetOffer(&session, fixture_now);
    const confirmation = try app.confirmResetOffer(&session, offer, fixture_now);

    try app.registry.setLabel(codex_account_id, "Codex Renamed");
    try testing.expectError(error.OfferChanged, app.beginResetAttempt(.{
        .session = &session,
        .confirmation = confirmation,
        .idempotency_key = "attempt-demo-0002",
        .now_unix_s = fixture_now,
        .sink = sink.sink(),
    }));
    try testing.expectEqual(@as(usize, 0), app.attempts().len);
}

test "the attempt is durable before anything can be sent" {
    const app = try newCoordinator();
    defer app.destroy();
    const sink = try RecordingSink.create();
    defer sink.destroy();
    const harness = try CodexHarness.create(&.{.{ .bytes = script_read }});
    defer harness.destroy();
    try seedAccounts(app);

    var session = try app.openResetSession(codex_account_id, .details, fixture_now);
    defer app.closeResetSession(&session, harness.lifecycle.lifecycle());
    _ = try runPreflight(app, &session, harness, sink.sink(), fixture_now);
    const offer = try app.prepareResetOffer(&session, fixture_now);
    const confirmation = try app.confirmResetOffer(&session, offer, fixture_now);

    sink.fail_kind = .attempts;
    sink.fail_after_matches = 0;
    try testing.expectError(error.LedgerUnavailable, app.beginResetAttempt(.{
        .session = &session,
        .confirmation = confirmation,
        .idempotency_key = "attempt-demo-0003",
        .now_unix_s = fixture_now,
        .sink = sink.sink(),
    }));
    try testing.expectEqual(@as(usize, 0), app.attempts().len);
    try testing.expectEqual(@as(usize, 0), sink.countOf(.attempts));

    sink.matches = 0;
    sink.fail_after_matches = 1;
    try testing.expectError(error.LedgerUnavailable, app.beginResetAttempt(.{
        .session = &session,
        .confirmation = confirmation,
        .idempotency_key = "attempt-demo-0004",
        .now_unix_s = fixture_now,
        .sink = sink.sink(),
    }));
    try testing.expectEqual(@as(usize, 1), app.attempts().len);
    try testing.expectEqual(domain.ResetAttemptPhase.prepared, app.attempts()[0].phase);
    try testing.expectEqualStrings("attempt-demo-0004", app.attempts()[0].idempotency_key);
    try testing.expectEqual(@as(usize, 1), sink.countOf(.attempts));

    const plan = app.planLedgerRecovery();
    try testing.expectEqual(@as(usize, 1), plan.count);
    try testing.expectEqual(coordinator.RecoveryAction.discard_never_sent, plan.slice()[0].action);
    try testing.expect(!plan.slice()[0].may_retry_same_key);

    sink.fail_kind = null;
    try app.discardPreparedAttempt("attempt-demo-0004", sink.sink());
    try testing.expectEqual(@as(usize, 0), app.attempts().len);
}

test "a settled reset records the outcome, requires a post read, and keeps one key" {
    const app = try newCoordinator();
    defer app.destroy();
    const sink = try RecordingSink.create();
    defer sink.destroy();
    const harness = try CodexHarness.create(&.{.{ .bytes = script_reset_transaction }});
    defer harness.destroy();
    try seedAccounts(app);

    var session = try app.openResetSession(codex_account_id, .details, fixture_now);
    _ = try runPreflight(app, &session, harness, sink.sink(), fixture_now);
    const offer = try app.prepareResetOffer(&session, fixture_now);
    const confirmation = try app.confirmResetOffer(&session, offer, fixture_now);

    const attempt = try app.beginResetAttempt(.{
        .session = &session,
        .confirmation = confirmation,
        .idempotency_key = "attempt-demo-0005",
        .now_unix_s = fixture_now,
        .sink = sink.sink(),
    });
    try testing.expectEqual(domain.ResetAttemptPhase.submitted, attempt.phase);
    try testing.expectEqualStrings("attempt-demo-0005", attempt.idempotency_key);
    try testing.expectEqual(@as(u32, 2), attempt.preflight_available_count);

    try testing.expectEqual(@as(usize, 2), sink.countOf(.attempts));

    try testing.expect(app.pendingAttemptFor(codex_account_id) != null);
    try testing.expectError(error.PendingAttempt, app.openResetSession(codex_account_id, .details, fixture_now));

    const outcome = harness.adapter(codex_home).consumeResetCredit(&harness.connection, &harness.workspace, .{
        .account_id = codex_account_id,
        .attempt = attempt,
        .credit_id = attempt.selected_credit_id,
        .now_unix_s = fixture_now,
    });
    try testing.expectEqual(domain.ResetOutcome.reset, outcome.completed);

    const resolution = try app.applyResetOutcome(&session, outcome, fixture_now + 1, sink.sink());
    try testing.expectEqual(domain.ResetAttemptPhase.completed, resolution.phase);
    try testing.expectEqual(domain.ResetOutcome.reset, resolution.outcome.?);
    try testing.expect(resolution.requires_post_read);
    try testing.expect(!resolution.may_retry_same_key);
    try testing.expect(resolution.credit_may_have_been_spent);
    try testing.expect(app.pendingAttemptFor(codex_account_id) == null);

    const post = try app.beginSessionStep(&session, .reset_post_read, fixture_now + 2);
    const post_report = app.runRefresh(post, harness.live(codex_home, false), fixture_now + 2, sink.sink());
    try testing.expect(post_report.replaced_snapshot);
    try testing.expect(app.snapshotFor(codex_account_id).?.reset_credits == null);

    try testing.expectEqual(@as(usize, 1), app.attempts().len);
    try testing.expect(!harness.lifecycle.inner.closed);
    app.closeResetSession(&session, harness.lifecycle.lifecycle());
    try testing.expect(harness.lifecycle.inner.reapedExactlyOnce());
    try testing.expect(app.schedulerIsIdle());

    const ledger_bytes = sink.lastOf(.attempts).?;
    try testing.expect(std.mem.indexOf(u8, ledger_bytes, "attempt-demo-0005") != null);
    try testing.expect(std.mem.indexOf(u8, ledger_bytes, "example.invalid") == null);
}

test "an ambiguous outcome never retries itself and a retry reuses the same key" {
    const app = try newCoordinator();
    defer app.destroy();
    const sink = try RecordingSink.create();
    defer sink.destroy();
    const harness = try CodexHarness.create(&.{.{ .bytes = script_reset_ambiguous }});
    defer harness.destroy();
    try seedAccounts(app);

    var session = try app.openResetSession(codex_account_id, .details, fixture_now);
    defer app.closeResetSession(&session, harness.lifecycle.lifecycle());
    _ = try runPreflight(app, &session, harness, sink.sink(), fixture_now);
    const offer = try app.prepareResetOffer(&session, fixture_now);
    const confirmation = try app.confirmResetOffer(&session, offer, fixture_now);
    const attempt = try app.beginResetAttempt(.{
        .session = &session,
        .confirmation = confirmation,
        .idempotency_key = "attempt-demo-0006",
        .now_unix_s = fixture_now,
        .sink = sink.sink(),
    });

    const outcome = harness.adapter(codex_home).consumeResetCredit(&harness.connection, &harness.workspace, .{
        .account_id = codex_account_id,
        .attempt = attempt,
        .credit_id = attempt.selected_credit_id,
        .now_unix_s = fixture_now,
    });
    try testing.expect(outcome.requestWasSent());
    try testing.expectEqualStrings(codex.public_code_reset_outcome_unknown, outcome.ambiguous.public_code);

    const resolution = try app.applyResetOutcome(&session, outcome, fixture_now + 1, sink.sink());
    try testing.expectEqual(domain.ResetAttemptPhase.ambiguous, resolution.phase);
    try testing.expect(resolution.outcome == null);
    try testing.expect(resolution.credit_may_have_been_spent);
    try testing.expect(resolution.requires_post_read);
    try testing.expect(resolution.may_retry_same_key);

    const plan = app.planLedgerRecovery();
    try testing.expectEqual(coordinator.RecoveryAction.reconcile_read, plan.slice()[0].action);
    try testing.expect(plan.requiresUserAction());
    try testing.expectEqualStrings("attempt-demo-0006", plan.slice()[0].idempotency_key);

    const step = try app.beginSessionStep(&session, .reset_preflight, fixture_now + 2);
    _ = try app.applyObservation(step, supportedObservation(fixture_now + 2, demoCredits(2)), fixture_now + 2);
    const fresh_offer = try app.prepareResetOffer(&session, fixture_now + 2);
    const retry = try app.prepareSameKeyRetry(.{
        .session = &session,
        .offer = fresh_offer,
        .now_unix_s = fixture_now + 2,
        .sink = sink.sink(),
    });
    try testing.expectEqualStrings("attempt-demo-0006", retry.idempotency_key);
    try testing.expectEqual(domain.ResetAttemptPhase.submitted, retry.phase);
    try testing.expectEqual(@as(i64, fixture_now), retry.created_at_unix_s);
    try testing.expectEqual(@as(usize, 1), app.attempts().len);

    try retry.assertSameOperation(codex_account_id, retry.selected_credit_id);
}

test "an unsettled attempt can only be reopened by its own key, and never as a new one" {
    const app = try newCoordinator();
    defer app.destroy();
    const sink = try RecordingSink.create();
    defer sink.destroy();
    const harness = try CodexHarness.create(&.{.{ .bytes = script_read }});
    defer harness.destroy();
    try seedAccounts(app);

    try testing.expectError(error.SessionClosed, app.reopenResetSession(
        codex_account_id,
        "attempt-demo-0009",
        .details,
        fixture_now,
    ));

    {
        var session = try app.openResetSession(codex_account_id, .details, fixture_now);
        _ = try runPreflight(app, &session, harness, sink.sink(), fixture_now);
        const offer = try app.prepareResetOffer(&session, fixture_now);
        const confirmation = try app.confirmResetOffer(&session, offer, fixture_now);
        _ = try app.beginResetAttempt(.{
            .session = &session,
            .confirmation = confirmation,
            .idempotency_key = "attempt-demo-0009",
            .now_unix_s = fixture_now,
            .sink = sink.sink(),
        });
        app.closeResetSession(&session, harness.lifecycle.lifecycle());
    }
    try testing.expect(app.schedulerIsIdle());
    try testing.expectEqual(@as(usize, 1), app.attempts().len);

    try testing.expectError(
        error.PendingAttempt,
        app.openResetSession(codex_account_id, .details, fixture_now + 1),
    );

    try testing.expectError(error.PendingAttempt, app.reopenResetSession(
        codex_account_id,
        "attempt-demo-not-the-one",
        .details,
        fixture_now + 1,
    ));
    try testing.expectError(error.SurfaceNotAllowed, app.reopenResetSession(
        codex_account_id,
        "attempt-demo-0009",
        .tray,
        fixture_now + 1,
    ));
    try testing.expectError(error.UnknownAccount, app.reopenResetSession(
        "acct-does-not-exist",
        "attempt-demo-0009",
        .details,
        fixture_now + 1,
    ));

    try testing.expectError(error.ProviderMismatch, app.reopenResetSession(
        claude_account_id,
        "attempt-demo-0009",
        .details,
        fixture_now + 1,
    ));

    var resumed = try app.reopenResetSession(
        codex_account_id,
        "attempt-demo-0009",
        .details,
        fixture_now + 1,
    );
    defer app.closeResetSession(&resumed, coordinator.noChildLifecycle());

    try testing.expectEqualStrings("attempt-demo-0009", resumed.idempotency_key);
    try testing.expect(!app.schedulerIsIdle());

    const step = try app.beginSessionStep(&resumed, .reset_preflight, fixture_now + 2);
    _ = try app.applyObservation(step, supportedObservation(fixture_now + 2, demoCredits(1)), fixture_now + 2);
    const fresh_offer = try app.prepareResetOffer(&resumed, fixture_now + 2);
    const retry = try app.prepareSameKeyRetry(.{
        .session = &resumed,
        .offer = fresh_offer,
        .now_unix_s = fixture_now + 2,
        .sink = sink.sink(),
    });
    try testing.expectEqualStrings("attempt-demo-0009", retry.idempotency_key);
    try testing.expectEqual(@as(usize, 1), app.attempts().len);
}

test "a rejected consume keeps its durable record and sends nothing" {
    const app = try newCoordinator();
    defer app.destroy();
    const sink = try RecordingSink.create();
    defer sink.destroy();
    const harness = try CodexHarness.create(&.{.{ .bytes = script_read }});
    defer harness.destroy();
    try seedAccounts(app);

    var session = try app.openResetSession(codex_account_id, .details, fixture_now);
    defer app.closeResetSession(&session, harness.lifecycle.lifecycle());
    _ = try runPreflight(app, &session, harness, sink.sink(), fixture_now);
    const offer = try app.prepareResetOffer(&session, fixture_now);
    const confirmation = try app.confirmResetOffer(&session, offer, fixture_now);
    _ = try app.beginResetAttempt(.{
        .session = &session,
        .confirmation = confirmation,
        .idempotency_key = "attempt-demo-0007",
        .now_unix_s = fixture_now,
        .sink = sink.sink(),
    });

    const resolution = try app.applyResetOutcome(&session, .{
        .rejected = .{ .kind = .unknown, .public_code = codex.public_code_reset_unconfirmed, .retryable = false },
    }, fixture_now + 1, sink.sink());
    try testing.expect(!resolution.credit_may_have_been_spent);
    try testing.expect(!resolution.requires_post_read);
    try testing.expect(resolution.may_retry_same_key);
    try testing.expectEqualStrings(codex.public_code_reset_unconfirmed, resolution.public_code.?);

    try testing.expectEqual(@as(usize, 1), app.attempts().len);
    try testing.expectEqual(domain.ResetAttemptPhase.not_sent, app.attempts()[0].phase);
    try testing.expect(app.attempts()[0].outcome == null);
    try testing.expect(app.pendingAttemptFor(codex_account_id) == null);
    try testing.expectEqualStrings("attempt-demo-0007", app.unsentAttemptFor(codex_account_id).?.idempotency_key);
    try testing.expectEqual(@as(usize, 3), sink.countOf(.attempts));
    app.closeResetSession(&session, harness.lifecycle.lifecycle());

    var reopened = try app.reopenResetSession(codex_account_id, "attempt-demo-0007", .details, fixture_now + 2);
    try testing.expectEqualStrings("attempt-demo-0007", reopened.idempotency_key);
    app.closeResetSession(&reopened, harness.lifecycle.lifecycle());
}

test "ledger recovery survives a restart without inventing an attempt" {
    const app = try newCoordinator();
    defer app.destroy();
    const sink = try RecordingSink.create();
    defer sink.destroy();
    const harness = try CodexHarness.create(&.{.{ .bytes = script_reset_transaction }});
    defer harness.destroy();
    try seedAccounts(app);
    try app.persistRegistry(sink.sink());

    var session = try app.openResetSession(codex_account_id, .details, fixture_now);
    _ = try runPreflight(app, &session, harness, sink.sink(), fixture_now);
    const offer = try app.prepareResetOffer(&session, fixture_now);
    const confirmation = try app.confirmResetOffer(&session, offer, fixture_now);
    const attempt = try app.beginResetAttempt(.{
        .session = &session,
        .confirmation = confirmation,
        .idempotency_key = "attempt-demo-0008",
        .now_unix_s = fixture_now,
        .sink = sink.sink(),
    });
    _ = attempt;
    app.closeResetSession(&session, harness.lifecycle.lifecycle());

    const restarted = try newCoordinator();
    defer restarted.destroy();
    try restarted.loadRegistryBytes(sink.lastOf(.registry).?);
    const loaded = try restarted.loadAttemptBytes(sink.lastOf(.attempts).?);
    try testing.expectEqual(@as(usize, 1), loaded);
    try testing.expectEqual(domain.ResetAttemptPhase.submitted, restarted.attempts()[0].phase);

    const plan = restarted.planLedgerRecovery();
    try testing.expectEqual(@as(usize, 1), plan.count);
    try testing.expectEqual(coordinator.RecoveryAction.reconcile_read, plan.slice()[0].action);
    try testing.expect(plan.slice()[0].may_retry_same_key);
    try testing.expectEqualStrings("attempt-demo-0008", plan.slice()[0].idempotency_key);

    try testing.expectError(
        error.PendingAttempt,
        restarted.openResetSession(codex_account_id, .details, fixture_now + 100),
    );
    try testing.expect(restarted.attemptByKey("attempt-demo-0008") != null);

    try restarted.registry.remove(codex_account_id);
    const orphaned = restarted.planLedgerRecovery();
    try testing.expectEqual(coordinator.RecoveryAction.orphaned, orphaned.slice()[0].action);
    try testing.expect(!orphaned.requiresUserAction());
    try testing.expectEqual(@as(usize, 1), restarted.attempts().len);
}
