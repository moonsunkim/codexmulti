const std = @import("std");
const account_registry = @import("../account_registry.zig");
const coordinator = @import("../coordinator.zig");
const domain = @import("../domain.zig");
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

fn readScript(comptime first_id: u8, comptime limits: []const u8) []const u8 {
    const a = std.fmt.comptimePrint("{d}", .{first_id});
    const b = std.fmt.comptimePrint("{d}", .{first_id + 1});
    const c = std.fmt.comptimePrint("{d}", .{first_id + 2});
    return resultFrame(a, initialize_result) ++ resultFrame(b, account_result) ++ resultFrame(c, limits);
}
const script_read = readScript(1, rate_limits_result);

test "the runtime layout stays inside one app-owned root" {
    const layout = try testLayout();
    try testing.expectEqualStrings(app_root, layout.rootPath());
    try testing.expectEqualStrings(accounts_root, (try layout.accountsDir()).slice());
    try testing.expectEqualStrings(codex_home, (try layout.codexHome(codex_storage_key)).slice());
    try testing.expectEqualStrings(claude_config_dir, (try layout.claudeConfigDir(claude_storage_key)).slice());
    try testing.expectEqualStrings(codex_profile_dir, (try layout.profileDir(codex_storage_key)).slice());

    const paths = try layout.profilePaths(codex_storage_key);
    try testing.expectEqualStrings(codex_home, paths.homeFor(.codex).slice());
    try testing.expect(layout.contains(paths.homeFor(.claude).slice()));

    try testing.expect(layout.contains(codex_home));
    try testing.expect(!layout.contains("/demo/home/demo-user/.codex"));
    try testing.expect(!layout.contains(app_root ++ "-other"));

    try transport.validateCodexHome(codex_home);
    try transport.validateCodexHome(claude_config_dir);

    try testing.expectEqualStrings("CODEX_HOME", runtime_paths.Layout.homeVariable(.codex));
    try testing.expectEqualStrings("CLAUDE_CONFIG_DIR", runtime_paths.Layout.homeVariable(.claude));
}

test "path and segment validation refuse absolute, traversal, and colliding input" {
    const layout = try testLayout();

    try testing.expectError(error.SegmentNotRelative, runtime_paths.validateAccountSegment("/etc"));
    try testing.expectError(error.SegmentNotRelative, runtime_paths.validateAccountSegment("codex/demo"));
    try testing.expectError(error.SegmentNotRelative, runtime_paths.validateAccountSegment("codex\\demo"));
    try testing.expectError(error.SegmentTraversal, runtime_paths.validateAccountSegment(".."));
    try testing.expectError(error.SegmentTraversal, runtime_paths.validateAccountSegment("a..b"));
    try testing.expectError(error.SegmentTraversal, runtime_paths.validateAccountSegment(".hidden"));
    try testing.expectError(error.ReservedSegment, runtime_paths.validateAccountSegment("accounts"));
    try testing.expectError(error.ReservedSegment, runtime_paths.validateAccountSegment("Snapshots.json"));
    try testing.expectError(error.EmptySegment, runtime_paths.validateAccountSegment(""));
    try testing.expectError(error.InvalidSegmentByte, runtime_paths.validateAccountSegment("demo account"));
    try testing.expectError(error.InvalidSegmentByte, runtime_paths.validateAccountSegment("demo\nkey"));
    try testing.expectError(error.SegmentTooLong, runtime_paths.validateAccountSegment("a" ** 65));

    try testing.expectError(error.SegmentTraversal, layout.profileDir(".."));
    try testing.expectError(error.SegmentNotRelative, layout.codexHome("../../etc"));

    try testing.expectError(error.PathNotAbsolute, runtime_paths.Path.init("relative/path"));
    try testing.expectError(error.PathNotCanonical, runtime_paths.Path.init("/demo/trailing/"));
    try testing.expectError(error.PathNotCanonical, runtime_paths.Path.init("/demo/../escape"));
    try testing.expectError(error.PathNotCanonical, runtime_paths.Path.init("/demo//double"));
    try testing.expectError(error.PathNotCanonical, runtime_paths.Path.init("/"));
    try testing.expectError(error.InvalidPathByte, runtime_paths.Path.init("/demo/for=ged"));
    try testing.expectError(error.EmptyPath, runtime_paths.Path.init(""));

    try testing.expectError(error.NotAppRoot, runtime_paths.Layout.fromAppDataDir("/demo/home/demo-user/Library/Application Support"));
    const from_data_dir = try runtime_paths.Layout.fromAppDataDir(app_root);
    try testing.expectEqualStrings(app_root, from_data_dir.rootPath());

    try testing.expect(runtime_paths.segmentsCollide("codex-demo", "Codex-Demo"));
    try testing.expect(!runtime_paths.segmentsCollide("codex-demo", "codex-demo2"));
}

test "the registry keeps stable order and refuses colliding identities" {
    var registry: account_registry.Registry = .{};
    const first = try registry.add(.{
        .id = codex_account_id,
        .provider = .codex,
        .label = "Codex Demo",
        .storage_key = codex_storage_key,
        .created_at_unix_s = fixture_now,
    });
    const second = try registry.add(.{
        .id = claude_account_id,
        .provider = .claude,
        .label = "Claude Demo",
        .storage_key = claude_storage_key,
        .created_at_unix_s = fixture_now,
    });
    try testing.expectEqual(@as(usize, 0), first);
    try testing.expectEqual(@as(usize, 1), second);
    try testing.expectEqualStrings(codex_account_id, registry.at(0).?.id);
    try testing.expectEqualStrings(claude_account_id, registry.at(1).?.id);

    try testing.expectError(error.DuplicateId, registry.add(.{
        .id = codex_account_id,
        .provider = .codex,
        .label = "Duplicate",
        .storage_key = "codex-other",
        .created_at_unix_s = fixture_now,
    }));

    try testing.expectError(error.DuplicateStorageKey, registry.add(.{
        .id = "acct-codex-other",
        .provider = .codex,
        .label = "Other",
        .storage_key = "Codex-Demo",
        .created_at_unix_s = fixture_now,
    }));
    try testing.expectError(error.InvalidStorageKey, registry.add(.{
        .id = "acct-codex-third",
        .provider = .codex,
        .label = "Third",
        .storage_key = "../escape",
        .created_at_unix_s = fixture_now,
    }));
    try testing.expectError(error.InvalidLabel, registry.add(.{
        .id = "acct-codex-fourth",
        .provider = .codex,
        .label = "bad\nlabel",
        .storage_key = "codex-fourth",
        .created_at_unix_s = fixture_now,
    }));
    try testing.expectError(error.InvalidId, registry.add(.{
        .id = "acct codex fifth",
        .provider = .codex,
        .label = "Fifth",
        .storage_key = "codex-fifth",
        .created_at_unix_s = fixture_now,
    }));

    _ = try registry.setProviderIdentity(codex_account_id, canary_identity);
    try testing.expectError(error.DuplicateProviderIdentity, registry.add(.{
        .id = "acct-codex-sixth",
        .provider = .codex,
        .label = "Sixth",
        .storage_key = "codex-sixth",
        .provider_account_key = canary_identity,
        .created_at_unix_s = fixture_now,
    }));

    try registry.move(claude_account_id, 0);
    try testing.expectEqualStrings(claude_account_id, registry.at(0).?.id);
    try registry.remove(claude_account_id);
    try testing.expectEqual(@as(usize, 1), registry.accountCount());
    try testing.expectEqualStrings(codex_account_id, registry.at(0).?.id);
    try testing.expectEqualStrings(canary_identity, registry.at(0).?.provider_account_key.?);
    try testing.expectError(error.UnknownAccount, registry.remove(claude_account_id));
}

test "auth revision moves exactly when credential ownership changes" {
    var registry: account_registry.Registry = .{};
    _ = try registry.add(.{
        .id = codex_account_id,
        .provider = .codex,
        .label = "Codex Demo",
        .storage_key = codex_storage_key,
        .created_at_unix_s = fixture_now,
    });
    try testing.expectEqual(@as(u64, 0), registry.at(0).?.auth_revision);
    try testing.expectEqual(account_registry.AuthState.unavailable, registry.at(0).?.auth_state);

    const after_login = try registry.markConnected(codex_account_id, null);
    try testing.expectEqual(@as(u64, 1), after_login);
    try testing.expectEqual(account_registry.AuthState.connected, registry.at(0).?.auth_state);

    try testing.expectEqual(after_login, try registry.markAuthState(codex_account_id, .connected));

    const after_revoke = try registry.markAuthState(codex_account_id, .reauth_required);
    try testing.expectEqual(after_login + 1, after_revoke);

    try testing.expectEqual(after_revoke, try registry.markAuthState(codex_account_id, .unavailable));

    try testing.expectEqual(after_revoke + 1, try registry.markConnected(codex_account_id, null));
    try testing.expectEqual(after_revoke + 2, try registry.markCredentialsRemoved(codex_account_id));
}

test "the registry document round trips order, labels, and auth facts" {
    var registry: account_registry.Registry = .{};
    _ = try registry.add(.{
        .id = codex_account_id,
        .provider = .codex,
        .label = "Codex Demo",
        .storage_key = codex_storage_key,
        .created_at_unix_s = fixture_now,
    });
    _ = try registry.add(.{
        .id = claude_account_id,
        .provider = .claude,
        .label = "Ünicode ラベル",
        .storage_key = claude_storage_key,
        .created_at_unix_s = fixture_now,
    });
    _ = try registry.markConnected(codex_account_id, canary_identity);
    _ = try registry.markAuthState(claude_account_id, .reauth_required);
    try registry.setAccessExpiry(claude_account_id, fixture_now + 3600);

    var views: [account_registry.max_accounts]account_registry.Account = undefined;
    const document = try registry.toDocument(views[0..]);
    const bytes = try store.encode(testing.allocator, document);
    defer testing.allocator.free(bytes);

    var parsed = try std.json.parseFromSlice(
        account_registry.RegistryDocument,
        testing.allocator,
        bytes,
        .{ .allocate = .alloc_always },
    );
    defer parsed.deinit();

    var restored: account_registry.Registry = .{};
    try restored.loadDocument(parsed.value);
    try testing.expectEqual(@as(usize, 2), restored.accountCount());
    try testing.expectEqualStrings(codex_account_id, restored.at(0).?.id);
    try testing.expectEqualStrings("Ünicode ラベル", restored.at(1).?.label);
    try testing.expectEqual(@as(u64, 1), restored.at(0).?.auth_revision);
    try testing.expectEqual(account_registry.AuthState.reauth_required, restored.at(1).?.auth_state);
    try testing.expectEqual(@as(?i64, fixture_now + 3600), restored.at(1).?.access_expires_at_unix_s);
    try testing.expectEqualStrings(canary_identity, restored.at(0).?.provider_account_key.?);

    const colliding = [_]account_registry.Account{
        .{ .id = "acct-a", .provider = .codex, .label = "A", .storage_key = "shared-key", .created_at_unix_s = 0 },
        .{ .id = "acct-b", .provider = .codex, .label = "B", .storage_key = "Shared-Key", .created_at_unix_s = 0 },
    };
    try testing.expectError(
        error.DuplicateStorageKey,
        account_registry.validateDocument(.{ .accounts = &colliding }),
    );
    try testing.expectError(
        error.UnsupportedSchemaVersion,
        account_registry.validateDocument(.{ .schema_version = 99, .accounts = &.{} }),
    );
}

test "provider email owns the automatic label while Rename remains authoritative" {
    var registry: account_registry.Registry = .{};
    _ = try registry.add(.{
        .id = codex_account_id,
        .provider = .codex,
        .label = "Codex account",
        .label_is_custom = false,
        .storage_key = codex_storage_key,
        .created_at_unix_s = fixture_now,
    });

    try registry.setProviderMetadata(codex_account_id, .{
        .email = "first@example.invalid",
        .email_observed = true,
        .plan_label = "Pro",
        .plan_observed = true,
    });
    var account = registry.at(0).?;
    try testing.expectEqualStrings("first@example.invalid", account.label);
    try testing.expect(!account.label_is_custom);
    try testing.expectEqualStrings("first@example.invalid", account.provider_email.?);
    try testing.expectEqualStrings("Pro", account.plan_label.?);

    try registry.setLabel(codex_account_id, "Primary coding");
    try registry.setProviderMetadata(codex_account_id, .{
        .email = "second@example.invalid",
        .email_observed = true,
        .plan_label = "Plus",
        .plan_observed = true,
    });
    account = registry.at(0).?;
    try testing.expectEqualStrings("Primary coding", account.label);
    try testing.expect(account.label_is_custom);
    try testing.expectEqualStrings("second@example.invalid", account.provider_email.?);
    try testing.expectEqualStrings("Plus", account.plan_label.?);

    var views: [account_registry.max_accounts]account_registry.Account = undefined;
    const document = try registry.toDocument(views[0..]);
    const bytes = try store.encode(testing.allocator, document);
    defer testing.allocator.free(bytes);
    var parsed = try std.json.parseFromSlice(
        account_registry.RegistryDocument,
        testing.allocator,
        bytes,
        .{ .allocate = .alloc_always },
    );
    defer parsed.deinit();
    var restored: account_registry.Registry = .{};
    try restored.loadDocument(parsed.value);
    const restored_account = restored.at(0).?;
    try testing.expectEqualStrings("Primary coding", restored_account.label);
    try testing.expect(restored_account.label_is_custom);
    try testing.expectEqualStrings("second@example.invalid", restored_account.provider_email.?);
    try testing.expectEqualStrings("Plus", restored_account.plan_label.?);
}

const parent_pairs = [_]transport.EnvVar{
    .{ .name = "PATH", .value = "/usr/bin:/bin" },
    .{ .name = "HOME", .value = home_dir },
    .{ .name = "TZ", .value = "Asia/Seoul" },
    .{ .name = "LANG", .value = "en_US.UTF-8" },

    .{ .name = "CODEX_HOME", .value = "/demo/home/demo-user/.codex" },
    .{ .name = "CLAUDE_CONFIG_DIR", .value = "/demo/home/demo-user/.claude" },
    .{ .name = "ANTHROPIC_API_KEY", .value = canary_access },
    .{ .name = "OPENAI_API_KEY", .value = canary_access },
    .{ .name = "CHATGPT_SESSION", .value = canary_access },
    .{ .name = "https_proxy", .value = "http://demo.invalid:8080" },
    .{ .name = "NODE_OPTIONS", .value = "--require /demo/inject.js" },
    .{ .name = "SSL_CERT_FILE", .value = "/demo/ca.pem" },
};

fn parentEnv() transport.ParentEnv {
    return .{ .pairs = &parent_pairs };
}

test "codex login is the official browser command with this account's own home" {
    const app = try newCoordinator();
    defer app.destroy();
    try seedAccounts(app);

    var spec: coordinator.LoginSpec = .{};
    try app.writeAccountLoginSpec(&spec, codex_account_id, parentEnv());

    try testing.expectEqual(@as(usize, 2), spec.argv().len);
    try testing.expectEqualStrings(codex_executable, spec.argv()[0]);
    try testing.expectEqualStrings("login", spec.argv()[1]);
    try testing.expectEqualStrings("CODEX_HOME", spec.home_var);
    try testing.expectEqualStrings(codex_home, spec.homePath());
    try testing.expectEqualStrings(codex_home, spec.homeValue().?);

    try testing.expect(!spec.env.contains("CLAUDE_CONFIG_DIR"));
}

test "a retained Claude account has no executable login path" {
    const app = try newCoordinator();
    defer app.destroy();
    try seedAccounts(app);

    var spec: coordinator.LoginSpec = .{};
    try testing.expectError(
        error.ProviderMismatch,
        app.writeAccountLoginSpec(&spec, claude_account_id, parentEnv()),
    );
}

test "the child environment is an allowlist and the parent is never changed" {
    const app = try newCoordinator();
    defer app.destroy();
    try seedAccounts(app);

    var spec: coordinator.LoginSpec = .{};
    try app.writeAccountLoginSpec(&spec, codex_account_id, parentEnv());

    try testing.expectEqualStrings("/usr/bin:/bin", spec.env.find("PATH").?);
    try testing.expectEqualStrings(home_dir, spec.env.find("HOME").?);
    try testing.expectEqualStrings("Asia/Seoul", spec.env.find("TZ").?);

    try testing.expectEqual(@as(usize, 5), spec.env.slice().len);
    try testing.expect(spec.env.holdsOnlyAllowedVariables(spec.home_var));
    try testing.expect(!spec.env.holdsOnlyAllowedVariables("SOMETHING_ELSE"));

    for (spec.env.slice()) |variable| {
        if (std.mem.eql(u8, variable.name, spec.home_var)) continue;
        try testing.expect(!transport.isScrubbed(variable.name));
        try testing.expect(transport.isInheritable(variable.name));
        try testing.expect(std.mem.indexOf(u8, variable.value, canary_access) == null);
        try testing.expect(std.mem.indexOf(u8, variable.value, "/.codex") == null);
        try testing.expect(std.mem.indexOf(u8, variable.value, "/.claude") == null);
    }

    try testing.expectEqualStrings("/demo/home/demo-user/.codex", parent_pairs[4].value);
    try testing.expectEqualStrings("/demo/home/demo-user/.claude", parent_pairs[5].value);
}

test "a login spec refuses a relative executable or a home outside the app root" {
    var spec: coordinator.LoginSpec = .{};
    const layout = try testLayout();

    try testing.expectError(error.InvalidExecutable, coordinator.writeLoginSpec(&spec, .{
        .provider = .codex,
        .account_id = codex_account_id,
        .executable = "codex",
        .home = codex_home,
        .parent_env = parentEnv(),
        .app_root = &layout,
    }));
    try testing.expectError(error.HomeOutsideAppRoot, coordinator.writeLoginSpec(&spec, .{
        .provider = .codex,
        .account_id = codex_account_id,
        .executable = codex_executable,
        .home = "/demo/home/demo-user/.codex",
        .parent_env = parentEnv(),
        .app_root = &layout,
    }));
    try testing.expectError(error.InvalidAccountHome, coordinator.writeLoginSpec(&spec, .{
        .provider = .codex,
        .account_id = codex_account_id,
        .executable = codex_executable,
        .home = accounts_root ++ "/../../escape",
        .parent_env = parentEnv(),
        .app_root = &layout,
    }));

    const app = try coordinator.Coordinator.create(testing.allocator, .{ .layout = layout });
    defer app.destroy();
    try seedAccounts(app);
    try testing.expectError(
        error.InvalidExecutable,
        app.writeAccountLoginSpec(&spec, codex_account_id, parentEnv()),
    );
    try testing.expectError(
        error.UnknownAccount,
        app.writeAccountLoginSpec(&spec, "acct-missing", parentEnv()),
    );
}

fn loginStatus(
    provider: domain.Provider,
    account_id: []const u8,
    phase: coordinator.LoginPhase,
    public_code: ?[]const u8,
) coordinator.LoginStatus {
    return .{
        .provider = provider,
        .account_id = account_id,
        .phase = phase,
        .public_code = public_code,
        .child_closed = true,
        .exit = if (phase == .ended) .success else .unknown,
    };
}

test "a login holds the account for its whole run and originates no refresh" {
    const app = try newCoordinator();
    defer app.destroy();
    try seedAccounts(app);

    var session = try app.beginLogin(claude_account_id, .reauthenticate, .details, fixture_now);
    defer app.closeLoginSession(&session);

    try testing.expectEqual(@as(usize, 1), app.inFlightCount());
    try testing.expectEqual(coordinator.EnqueueOutcome.already_pending, try app.requestRefresh(claude_account_id));
    try testing.expect(app.nextOperation(fixture_now) == null);
    try testing.expectError(error.AccountBusy, app.beginLogin(claude_account_id, .initial, .details, fixture_now));

    try testing.expectEqual(domain.RefreshPhase.idle, app.statusFor(claude_account_id).?.phase);
    try testing.expect(app.snapshotFor(claude_account_id) == null);
    try testing.expect(app.statusFor(claude_account_id).?.last_success_at_unix_s == null);

    try testing.expectEqual(coordinator.EnqueueOutcome.queued, try app.requestRefresh(codex_account_id));
    const ticket = app.nextOperation(fixture_now) orelse return error.NotAdmitted;
    try testing.expectEqualStrings(codex_account_id, ticket.account_id);

    const report = try app.applyLoginResult(
        &session,
        loginStatus(.claude, claude_account_id, .ended, null),
        fixture_now + 5,
        coordinator.unwiredDocumentSink(),
    );
    try testing.expect(report.succeeded());
    try testing.expectEqual(@as(usize, 1), app.inFlightCount());
    app.closeLoginSession(&session);
    try testing.expectEqual(@as(usize, 1), app.inFlightCount());
}

test "a login is refused while a reset attempt for that account is unsettled" {
    const app = try newCoordinator();
    defer app.destroy();
    const sink = try RecordingSink.create();
    defer sink.destroy();
    const harness = try CodexHarness.create(&.{.{ .bytes = script_read }});
    defer harness.destroy();
    try seedAccounts(app);

    var session = try app.openResetSession(codex_account_id, .details, fixture_now);
    _ = try runPreflight(app, &session, harness, sink.sink(), fixture_now);
    const offer = try app.prepareResetOffer(&session, fixture_now);
    const confirmation = try app.confirmResetOffer(&session, offer, fixture_now);

    try testing.expectError(
        error.AccountBusy,
        app.beginLogin(codex_account_id, .reauthenticate, .details, fixture_now),
    );

    const attempt = try app.beginResetAttempt(.{
        .session = &session,
        .confirmation = confirmation,
        .idempotency_key = "attempt-demo-login-0001",
        .now_unix_s = fixture_now,
        .sink = sink.sink(),
    });
    try testing.expectEqual(domain.ResetAttemptPhase.submitted, attempt.phase);

    app.closeResetSession(&session, harness.lifecycle.lifecycle());
    try testing.expect(app.schedulerIsIdle());
    try testing.expect(app.pendingAttemptFor(codex_account_id) != null);
    try testing.expectError(
        error.PendingAttempt,
        app.beginLogin(codex_account_id, .reauthenticate, .details, fixture_now),
    );

    try testing.expect(app.schedulerIsIdle());
    try testing.expectEqual(@as(usize, 1), app.attempts().len);
    try testing.expectEqual(domain.ResetAttemptPhase.submitted, app.attempts()[0].phase);

    var other = try app.beginLogin(claude_account_id, .initial, .details, fixture_now);
    app.closeLoginSession(&other);
}

test "a failed login leaves the stored snapshot and the auth revision alone" {
    const app = try newCoordinator();
    defer app.destroy();
    const sink = try RecordingSink.create();
    defer sink.destroy();
    try seedAccounts(app);

    const ticket = try admit(app, claude_account_id, fixture_now);
    _ = try app.applyObservation(ticket, supportedObservation(fixture_now, null), fixture_now);
    const before_revision = app.account(claude_account_id).?.auth_revision;
    const before_capture = app.snapshotFor(claude_account_id).?.captured_at_unix_s;
    sink.reset();

    var session = try app.beginLogin(claude_account_id, .reauthenticate, .details, fixture_now + 10);
    defer app.closeLoginSession(&session);
    const report = try app.applyLoginResult(
        &session,
        loginStatus(.claude, claude_account_id, .canceled, "login-canceled"),
        fixture_now + 20,
        sink.sink(),
    );

    try testing.expect(!report.succeeded());
    try testing.expectEqualStrings("login-canceled", report.public_code.?);
    try testing.expect(!report.auth_state_changed);
    try testing.expect(report.persist_code == null);

    try testing.expectEqual(before_capture, app.snapshotFor(claude_account_id).?.captured_at_unix_s);
    try testing.expectEqual(before_revision, app.account(claude_account_id).?.auth_revision);

    try testing.expectEqual(@as(usize, 0), sink.record_count);
    try testing.expect(app.schedulerIsIdle());
}

test "a completed login makes its auth-state change durable and reports a failed write" {
    const app = try newCoordinator();
    defer app.destroy();
    const sink = try RecordingSink.create();
    defer sink.destroy();
    try seedAccounts(app);
    _ = try app.registry.markAuthState(claude_account_id, .reauth_required);
    sink.reset();

    var session = try app.beginLogin(claude_account_id, .reauthenticate, .details, fixture_now);
    defer app.closeLoginSession(&session);
    const report = try app.applyLoginResult(
        &session,
        loginStatus(.claude, claude_account_id, .ended, null),
        fixture_now + 1,
        sink.sink(),
    );
    try testing.expect(report.auth_state_changed);
    try testing.expectEqual(@as(usize, 1), sink.countOf(.registry));
    try testing.expect(std.mem.indexOf(u8, sink.allBytes(), "reauth_required") == null);

    _ = try app.registry.markAuthState(claude_account_id, .reauth_required);
    sink.reset();
    sink.fail_kind = .registry;
    sink.fail_after_matches = 0;
    var again = try app.beginLogin(claude_account_id, .reauthenticate, .details, fixture_now + 10);
    defer app.closeLoginSession(&again);
    const second = try app.applyLoginResult(
        &again,
        loginStatus(.claude, claude_account_id, .ended, null),
        fixture_now + 11,
        sink.sink(),
    );
    try testing.expect(second.succeeded());
    try testing.expectEqualStrings(coordinator.public_code_persist_failed, second.persist_code.?);
}

test "no login session or report carries credential material" {
    const app = try newCoordinator();
    defer app.destroy();
    const sink = try RecordingSink.create();
    defer sink.destroy();
    try seedAccounts(app);

    var session = try app.beginLogin(claude_account_id, .initial, .details, fixture_now);
    defer app.closeLoginSession(&session);
    const report = try app.applyLoginResult(
        &session,
        loginStatus(.claude, claude_account_id, .ended, null),
        fixture_now,
        sink.sink(),
    );
    const forbidden = [_][]const u8{ canary_access, canary_refresh, canary_identity };
    for (forbidden) |needle| {
        try testing.expect(std.mem.indexOf(u8, std.mem.asBytes(&session), needle) == null);
        try testing.expect(std.mem.indexOf(u8, std.mem.asBytes(&report), needle) == null);
        try testing.expect(std.mem.indexOf(u8, sink.allBytes(), needle) == null);
    }
}
