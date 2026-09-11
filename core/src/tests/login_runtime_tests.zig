const std = @import("std");
const account_registry = @import("../account_registry.zig");
const coordinator = @import("../coordinator.zig");
const domain = @import("../domain.zig");
const keychain = @import("../keychain.zig");
const login = @import("../login_runtime.zig");
const runtime_paths = @import("../runtime_paths.zig");
const transport = @import("../process_jsonl.zig");

const testing = std.testing;

const fixture_now: i64 = 2_000_000_000;

const home_dir = "/demo/home/demo-user";
const app_root = home_dir ++ "/Library/Application Support/" ++ runtime_paths.app_data_directory_name;
const accounts_root = app_root ++ "/accounts";

const codex_executable = "/Users/demo/.local/bin/codex";
const claude_executable = "/Users/demo/.local/bin/claude";

const codex_one_id = "acct-codex-one";
const codex_two_id = "acct-codex-two";
const claude_one_id = "acct-claude-one";
const claude_two_id = "acct-claude-two";

const codex_one_key = "codex-one";
const codex_two_key = "codex-two";
const claude_one_key = "claude-one";
const claude_two_key = "claude-two";

const codex_one_home = accounts_root ++ "/" ++ codex_one_key ++ "/codex";
const codex_two_home = accounts_root ++ "/" ++ codex_two_key ++ "/codex";
const claude_one_dir = accounts_root ++ "/" ++ claude_one_key ++ "/claude";
const claude_two_dir = accounts_root ++ "/" ++ claude_two_key ++ "/claude";

const canary_access = "demo-access-not-a-real-token-0001";
const canary_refresh = "demo-refresh-not-a-real-token-0002";
const canary_bearer = "Bearer demo-should-never-appear-0003";
const canary_cookie = "sessionKey=demo-should-never-appear-0004";
const canary_line = "debug: authorization=" ++ canary_bearer ++ " cookie=" ++ canary_cookie;

const canaries = [_][]const u8{
    canary_access,
    canary_refresh,
    canary_bearer,
    canary_cookie,
    "not-a-real-token",
    "should-never-appear",
};

const verification_url = "https://auth.openai.com/device";
const verification_code = "WDJB-MJHT";

const device_lines = [_][]const u8{
    "Starting device authorization",
    "Open the following URL in your browser: " ++ verification_url,
    "Enter the code: " ++ verification_code,
    "Waiting for authorization...",
    "You are now logged in",
};

fn parentPairs() []const transport.EnvVar {
    return &parent_pairs;
}

const parent_pairs = [_]transport.EnvVar{
    .{ .name = "PATH", .value = "/usr/bin:/bin" },
    .{ .name = "HOME", .value = home_dir },
    .{ .name = "TZ", .value = "Asia/Seoul" },
    .{ .name = "LANG", .value = "en_US.UTF-8" },

    .{ .name = "CODEX_HOME", .value = home_dir ++ "/.codex" },
    .{ .name = "CLAUDE_CONFIG_DIR", .value = home_dir ++ "/.claude" },
    .{ .name = "CLAUDE_SECURESTORAGE_CONFIG_DIR", .value = home_dir ++ "/.claude" },
    .{ .name = "ANTHROPIC_API_KEY", .value = canary_access },
    .{ .name = "OPENAI_API_KEY", .value = canary_access },
    .{ .name = "CLAUDE_CODE_OAUTH_TOKEN", .value = canary_refresh },
    .{ .name = "https_proxy", .value = "http://demo.invalid:8080" },
    .{ .name = "NODE_OPTIONS", .value = "--require /demo/inject.js" },
};

fn parentEnv() transport.ParentEnv {
    return .{ .pairs = parentPairs() };
}

fn testLayout() !runtime_paths.Layout {
    return runtime_paths.Layout.fromHomeDir(home_dir);
}

fn newCoordinator() !*coordinator.Coordinator {
    return coordinator.Coordinator.create(testing.allocator, .{
        .layout = try testLayout(),
        .target = .{
            .codex_executable = codex_executable,
            .codex_cli_version = "0.145.0",
        },
    });
}

fn seedAccounts(app: *coordinator.Coordinator) !void {
    _ = try app.addAccount(.{
        .id = codex_one_id,
        .provider = .codex,
        .label = "Codex One",
        .storage_key = codex_one_key,
        .created_at_unix_s = fixture_now - 10_000,
    });
    _ = try app.addAccount(.{
        .id = codex_two_id,
        .provider = .codex,
        .label = "Codex Two",
        .storage_key = codex_two_key,
        .created_at_unix_s = fixture_now - 10_000,
    });
    _ = try app.addAccount(.{
        .id = claude_one_id,
        .provider = .claude,
        .label = "Claude One",
        .storage_key = claude_one_key,
        .created_at_unix_s = fixture_now - 10_000,
    });
    _ = try app.addAccount(.{
        .id = claude_two_id,
        .provider = .claude,
        .label = "Claude Two",
        .storage_key = claude_two_key,
        .created_at_unix_s = fixture_now - 10_000,
    });
}

fn expectNoCanary(text: []const u8) !void {
    for (canaries) |canary| {
        try testing.expect(std.mem.indexOf(u8, text, canary) == null);
    }
}

const RunHarness = struct {
    child: login.FakeChild,
    progress: login.RecordingProgress,
    cancel: login.FlagCancelToken,
    storage: [login.min_scan_bytes]u8,

    const Overrides = struct {
        timeout_ms: u32 = login.default_timeout_ms,
        max_output_bytes: usize = login.default_max_output_bytes,
    };

    fn create(chunks: []const login.FakeChild.Chunk) !*RunHarness {
        const harness = try testing.allocator.create(RunHarness);
        harness.* = .{
            .child = .{ .chunks = chunks },
            .progress = .{},
            .cancel = .{},
            .storage = @splat(0),
        };
        return harness;
    }

    fn destroy(self: *RunHarness) void {
        testing.allocator.destroy(self);
    }

    fn run(
        self: *RunHarness,
        provider: domain.Provider,
        account_id: []const u8,
        overrides: Overrides,
    ) login.Status {
        var runner: login.Runner = .init(self.child.handle(), &self.storage, provider, account_id);
        return runner.run(.{
            .timeout_ms = overrides.timeout_ms,
            .max_output_bytes = overrides.max_output_bytes,
            .cancel = self.cancel.token(),
            .progress = self.progress.sink(),
        });
    }
};

fn runUnwired(provider: domain.Provider, account_id: []const u8) login.Status {
    var storage: [login.min_scan_bytes]u8 = @splat(0);
    var runner: login.Runner = .init(login.unwiredChild(), &storage, provider, account_id);
    return runner.run(.{});
}

test "the codex login command is the official browser argv under this account's own home" {
    const app = try newCoordinator();
    defer app.destroy();
    try seedAccounts(app);

    var spec: coordinator.LoginSpec = .{};
    try app.writeAccountLoginSpec(&spec, codex_one_id, parentEnv());

    try testing.expectEqual(@as(usize, 2), spec.argv().len);
    try testing.expectEqualStrings(codex_executable, spec.argv()[0]);
    try testing.expectEqualStrings("login", spec.argv()[1]);
    try testing.expect(std.fs.path.isAbsolute(spec.argv()[0]));

    for (spec.argv()[1..]) |argument| {
        try testing.expect(std.mem.indexOfAny(u8, argument, " \t\n;|&$`") == null);
    }

    try testing.expectEqual(@as(usize, 1), spec.isolationVars().len);
    try testing.expectEqualStrings("CODEX_HOME", spec.isolationVars()[0]);
    try testing.expectEqualStrings(codex_one_home, spec.homePath());
    try testing.expectEqualStrings(codex_one_home, spec.homeValue().?);
    try testing.expect(spec.isolationIsConsistent());

    try testing.expect(!spec.env.contains("CLAUDE_CONFIG_DIR"));
    try testing.expect(!spec.env.contains("CLAUDE_SECURESTORAGE_CONFIG_DIR"));
}

test "the login environment is an allowlist and the parent process is never rewritten" {
    const app = try newCoordinator();
    defer app.destroy();
    try seedAccounts(app);

    var spec: coordinator.LoginSpec = .{};
    try app.writeAccountLoginSpec(&spec, codex_one_id, parentEnv());

    try testing.expectEqualStrings("/usr/bin:/bin", spec.env.find("PATH").?);
    try testing.expectEqualStrings(home_dir, spec.env.find("HOME").?);
    try testing.expect(spec.env.holdsOnlyAllowedVariablesFor(spec.isolationVars()));

    for (spec.env.slice()) |variable| {
        if (std.mem.eql(u8, variable.value, spec.homePath())) continue;
        try testing.expect(transport.isInheritable(variable.name));
        try testing.expect(!transport.isScrubbed(variable.name));
        try expectNoCanary(variable.value);
    }

    try testing.expect(!spec.env.contains("ANTHROPIC_API_KEY"));
    try testing.expect(!spec.env.contains("OPENAI_API_KEY"));
    try testing.expect(!spec.env.contains("CLAUDE_CODE_OAUTH_TOKEN"));
    try testing.expect(!spec.env.contains("https_proxy"));
    try testing.expect(!spec.env.contains("NODE_OPTIONS"));

    try testing.expectEqualStrings(home_dir ++ "/.codex", parent_pairs[4].value);
    try testing.expectEqualStrings(home_dir ++ "/.claude", parent_pairs[5].value);
    try testing.expectEqualStrings(home_dir ++ "/.claude", parent_pairs[6].value);
}

test "a login spec refuses an unsupported provider, a relative binary, a foreign home, and an unknown account" {
    var spec: coordinator.LoginSpec = .{};
    const layout = try testLayout();

    try testing.expectError(error.InvalidExecutable, coordinator.writeLoginSpec(&spec, .{
        .provider = .codex,
        .account_id = codex_one_id,
        .executable = "codex",
        .home = codex_one_home,
        .parent_env = parentEnv(),
        .app_root = &layout,
    }));
    try testing.expectError(error.ProviderMismatch, coordinator.writeLoginSpec(&spec, .{
        .provider = .claude,
        .account_id = claude_one_id,
        .executable = "./claude",
        .home = claude_one_dir,
        .parent_env = parentEnv(),
        .app_root = &layout,
    }));

    try testing.expectError(error.HomeOutsideAppRoot, coordinator.writeLoginSpec(&spec, .{
        .provider = .codex,
        .account_id = codex_one_id,
        .executable = codex_executable,
        .home = home_dir ++ "/.codex",
        .parent_env = parentEnv(),
        .app_root = &layout,
    }));

    try testing.expectError(error.InvalidAccountHome, coordinator.writeLoginSpec(&spec, .{
        .provider = .codex,
        .account_id = codex_one_id,
        .executable = codex_executable,
        .home = accounts_root ++ "/../../escape",
        .parent_env = parentEnv(),
        .app_root = &layout,
    }));
    try testing.expectError(error.InvalidAccountHome, coordinator.writeLoginSpec(&spec, .{
        .provider = .codex,
        .account_id = codex_one_id,
        .executable = codex_executable,
        .home = "accounts/codex-one/codex",
        .parent_env = parentEnv(),
        .app_root = &layout,
    }));

    const app = try newCoordinator();
    defer app.destroy();
    try seedAccounts(app);
    try testing.expectError(
        error.UnknownAccount,
        app.writeAccountLoginSpec(&spec, "acct-does-not-exist", parentEnv()),
    );
}

test "an isolation set that disagrees about the directory is not a usable spec" {
    var spec: coordinator.LoginSpec = .{};
    const layout = try testLayout();
    try coordinator.writeLoginSpec(&spec, .{
        .provider = .codex,
        .account_id = codex_one_id,
        .executable = codex_executable,
        .home = codex_one_home,
        .parent_env = parentEnv(),
        .app_root = &layout,
    });
    try testing.expect(spec.isolationIsConsistent());

    for (spec.env.vars[0..spec.env.count]) |*variable| {
        if (std.mem.eql(u8, variable.name, "CODEX_HOME")) {
            variable.value = codex_two_home;
        }
    }
    try testing.expect(!spec.isolationIsConsistent());

    var moved = spec;
    moved.rebind();
    try testing.expect(moved.isolationIsConsistent());
    try testing.expectEqualStrings(codex_one_home, moved.env.find("CODEX_HOME").?);
    try testing.expectEqual(
        moved.homePath().ptr,
        moved.env.find("CODEX_HOME").?.ptr,
    );
}

test "two accounts of one provider never share a home, and no home is a default location" {
    const app = try newCoordinator();
    defer app.destroy();
    try seedAccounts(app);

    var first: coordinator.LoginSpec = .{};
    var second: coordinator.LoginSpec = .{};
    try app.writeAccountLoginSpec(&first, codex_one_id, parentEnv());
    try app.writeAccountLoginSpec(&second, codex_two_id, parentEnv());
    try testing.expectEqualStrings(codex_one_home, first.homePath());
    try testing.expectEqualStrings(codex_two_home, second.homePath());
    try testing.expect(!std.mem.eql(u8, first.homePath(), second.homePath()));
    try testing.expect(!first.home.contains(second.homePath()));
    try testing.expect(!second.home.contains(first.homePath()));

    const defaults = [_][]const u8{ home_dir ++ "/.codex", home_dir ++ "/.claude" };
    for ([_]*const coordinator.LoginSpec{ &first, &second }) |spec| {
        for (defaults) |default| {
            try testing.expect(!std.mem.eql(u8, spec.homePath(), default));
        }
    }
}

test "lines are reassembled from arbitrary fragments and from bundled reads" {
    const harness = try RunHarness.create(&.{
        .{ .bytes = "Starting device auth" },
        .empty,
        .{ .bytes = "orization\nOpen the following URL in your browser: " },
        .{ .bytes = verification_url ++ "\n" },
        .{ .bytes = "Enter the code: " ++ verification_code ++ "\nWaiting for authorization...\n" },
        .empty,
        .{ .bytes = "You are now logged in\n" },
    });
    defer harness.destroy();

    const status = harness.run(.codex, codex_one_id, .{});
    try testing.expectEqual(login.Phase.ended, status.phase);
    try testing.expectEqual(@as(usize, device_lines.len), status.lines_scanned);
    try testing.expectEqual(@as(usize, 0), status.lines_dropped);
    try testing.expect(status.signals.awaiting_user >= 2);
    try testing.expectEqual(@as(usize, 1), status.signals.authorized);
    try testing.expect(status.endedCleanly());

    const verification = status.verification.?;
    try testing.expectEqualStrings(verification_url, verification.url());
    try testing.expectEqualStrings(verification_code, verification.code());
}

test "an over-long line is dropped and counted, and scanning resynchronizes after it" {
    const banner = "b" ** (2 * login.min_scan_bytes);
    const harness = try RunHarness.create(&.{
        .{ .bytes = "Waiting for authorization\n" },
        .{ .bytes = banner ++ "\n" },
        .{ .bytes = "You are now logged in\n" },
    });
    defer harness.destroy();

    const status = harness.run(.codex, codex_one_id, .{});
    try testing.expectEqual(login.Phase.ended, status.phase);

    try testing.expectEqual(@as(usize, 1), status.lines_dropped);
    try testing.expectEqual(@as(usize, 2), status.lines_scanned);
    try testing.expectEqual(@as(usize, 1), status.signals.authorized);
    try testing.expect(status.endedCleanly());
}

test "both output streams arrive interleaved through one scanner" {
    const harness = try RunHarness.create(&.{
        .{ .bytes = "stdout: Starting device authorizat" },
        .{ .bytes = "ion\nstderr: Open the following URL in your brow" },
        .{ .bytes = "ser: " ++ verification_url ++ "\nstdout: Enter the co" },
        .{ .bytes = "de: " ++ verification_code ++ "\nstderr: You are now logged in\n" },
    });
    defer harness.destroy();

    const status = harness.run(.claude, claude_one_id, .{});
    try testing.expectEqual(login.Phase.ended, status.phase);
    try testing.expectEqual(@as(usize, 4), status.lines_scanned);
    try testing.expectEqual(@as(usize, 1), status.signals.authorized);
    try testing.expectEqualStrings(verification_url, status.verification.?.url());
    try testing.expectEqualStrings(verification_code, status.verification.?.code());

    try testing.expectEqual(@as(usize, 0), status.lines_dropped);
}

test "a completed login ends cleanly and its child is reaped exactly once" {
    const harness = try RunHarness.create(&.{
        .{ .bytes = "Open the following URL in your browser: " ++ verification_url ++ "\n" },
        .{ .bytes = "Enter the code: " ++ verification_code ++ "\n" },
        .{ .bytes = "You are now logged in\n" },
    });
    defer harness.destroy();

    const status = harness.run(.codex, codex_one_id, .{});
    try testing.expect(status.endedCleanly());
    try testing.expectEqual(login.Exit.success, status.exit);
    try testing.expect(status.public_code == null);
    try testing.expect(status.child_closed);

    try testing.expectEqual(@as(usize, 1), harness.child.arm_count);
    try testing.expectEqual(login.default_timeout_ms, harness.child.last_timeout_ms);
    try testing.expect(harness.child.reapedExactlyOnce());
    try testing.expectEqual(@as(usize, 1), harness.child.termination.reaps);
    try testing.expect(harness.child.termination.stdin_closed);
    try testing.expect(harness.child.termination.output_closed);
    try testing.expectEqual(@as(usize, 0), harness.child.termination.kill_signals);

    try testing.expect(harness.child.output_ended);
    try testing.expect(harness.child.termination.exitedOnItsOwn());
    try testing.expectEqual(login.Exit.success, status.exit);

    harness.child.handle().close();
    harness.child.handle().close();
    try testing.expectEqual(@as(usize, 1), harness.child.closes);
    try testing.expect(harness.child.reapedExactlyOnce());
}

test "a login still running when the run ends is signalled, and only then" {
    const harness = try RunHarness.create(&.{
        .{ .bytes = "Waiting for authorization...\n" },
        .{ .failure = error.Timeout },
    });
    defer harness.destroy();

    harness.child.reaped_after_polls = null;

    const status = harness.run(.codex, codex_one_id, .{ .timeout_ms = 60_000 });
    try testing.expectEqual(login.Phase.timed_out, status.phase);
    try testing.expect(!harness.child.output_ended);
    try testing.expect(!harness.child.termination.exitedOnItsOwn());
    try testing.expectEqual(@as(usize, 1), harness.child.termination.terminate_signals);
    try testing.expectEqual(@as(usize, 1), harness.child.termination.kill_signals);
    try testing.expect(harness.child.termination.escalated);
    try testing.expect(harness.child.reapedExactlyOnce());

    try testing.expectEqual(login.Exit.signaled, status.exit);
    try testing.expectEqualStrings(login.public_code_login_timeout, status.public_code.?);
}

test "a login the provider rejected never claims success" {
    const harness = try RunHarness.create(&.{
        .{ .bytes = "Open the following URL in your browser: " ++ verification_url ++ "\n" },
        .{ .bytes = "Authorization request expired\n" },
    });
    defer harness.destroy();
    harness.child.scripted_exit = .success;

    const status = harness.run(.codex, codex_one_id, .{});
    try testing.expectEqual(login.Phase.ended, status.phase);
    try testing.expect(!status.endedCleanly());
    try testing.expectEqualStrings(login.public_code_login_rejected, status.public_code.?);
    try testing.expectEqual(@as(usize, 1), status.signals.rejected);
    try testing.expectEqual(@as(usize, 0), status.signals.authorized);
    try testing.expect(harness.child.reapedExactlyOnce());
}

test "a non-zero exit fails the run even when the output read as progress" {
    const harness = try RunHarness.create(&.{
        .{ .bytes = "Open the following URL in your browser: " ++ verification_url ++ "\n" },
        .{ .bytes = "Waiting for authorization...\n" },
    });
    defer harness.destroy();
    harness.child.scripted_exit = .failure;

    const status = harness.run(.codex, codex_one_id, .{});
    try testing.expectEqual(login.Phase.failed, status.phase);
    try testing.expectEqual(login.Exit.failure, status.exit);
    try testing.expectEqualStrings(login.public_code_login_rejected, status.public_code.?);
    try testing.expect(!status.endedCleanly());

    const signaled = try RunHarness.create(&.{.{ .bytes = "Waiting for authorization...\n" }});
    defer signaled.destroy();
    signaled.child.scripted_exit = .signaled;
    const signaled_status = signaled.run(.codex, codex_one_id, .{});
    try testing.expectEqual(login.Phase.failed, signaled_status.phase);
    try testing.expectEqual(login.Exit.signaled, signaled_status.exit);
}

test "an already-authenticated home is reported as its own signal, not as a new login" {
    const harness = try RunHarness.create(&.{.{ .bytes = "Already logged in as demo-user\n" }});
    defer harness.destroy();

    const status = harness.run(.claude, claude_one_id, .{});
    try testing.expectEqual(@as(usize, 1), status.signals.already_authenticated);
    try testing.expectEqual(@as(usize, 0), status.signals.authorized);
    try testing.expect(status.endedCleanly());
}

test "the wall-clock budget closes a login that is still talking" {
    const harness = try RunHarness.create(&.{
        .{ .bytes = "Open the following URL in your browser: " ++ verification_url ++ "\n" },
        .{ .failure = error.Timeout },
    });
    defer harness.destroy();

    const status = harness.run(.codex, codex_one_id, .{ .timeout_ms = 90_000 });
    try testing.expectEqual(login.Phase.timed_out, status.phase);
    try testing.expectEqualStrings(login.public_code_login_timeout, status.public_code.?);
    try testing.expectEqual(@as(u32, 90_000), harness.child.last_timeout_ms);

    try testing.expectEqualStrings(verification_url, status.verification.?.url());
    try testing.expect(harness.child.reapedExactlyOnce());

    try testing.expectEqual(login.min_timeout_ms, login.clampTimeout(0));
    try testing.expectEqual(login.max_timeout_ms, login.clampTimeout(std.math.maxInt(u32)));
    try testing.expectEqual(@as(u32, 90_000), login.clampTimeout(90_000));
}

test "a user cancellation ends the login at the next line boundary" {
    const harness = try RunHarness.create(&.{
        .{ .bytes = "Open the following URL in your browser: " ++ verification_url ++ "\n" },
        .{ .bytes = "Waiting for authorization...\n" },
        .{ .bytes = "Waiting for authorization...\n" },
        .{ .bytes = "You are now logged in\n" },
    });
    defer harness.destroy();

    harness.cancel.cancel_after_polls = 2;

    const status = harness.run(.codex, codex_one_id, .{});
    try testing.expectEqual(login.Phase.canceled, status.phase);
    try testing.expectEqualStrings(login.public_code_login_canceled, status.public_code.?);

    try testing.expectEqual(@as(usize, 2), status.lines_scanned);
    try testing.expectEqual(@as(usize, 0), status.signals.authorized);
    try testing.expect(harness.child.reapedExactlyOnce());

    const from_child = try RunHarness.create(&.{.{ .failure = error.Canceled }});
    defer from_child.destroy();
    const child_status = from_child.run(.codex, codex_one_id, .{});
    try testing.expectEqual(login.Phase.canceled, child_status.phase);
    try testing.expectEqualStrings(login.public_code_login_canceled, child_status.public_code.?);
}

test "an unreadable stream, a stalled stream, and an unwired child all fail closed" {
    const failed = try RunHarness.create(&.{.{ .failure = error.Io }});
    defer failed.destroy();
    const io_status = failed.run(.codex, codex_one_id, .{});
    try testing.expectEqual(login.Phase.failed, io_status.phase);
    try testing.expectEqualStrings(login.public_code_login_io, io_status.public_code.?);
    try testing.expect(failed.child.reapedExactlyOnce());

    const empties = [_]login.FakeChild.Chunk{.empty} ** (login.max_empty_reads + 2);
    const stalled = try RunHarness.create(&empties);
    defer stalled.destroy();
    const stalled_status = stalled.run(.codex, codex_one_id, .{});
    try testing.expectEqual(login.Phase.failed, stalled_status.phase);
    try testing.expectEqualStrings(login.public_code_login_io, stalled_status.public_code.?);

    const unwired = runUnwired(.claude, claude_one_id);
    try testing.expectEqual(login.Phase.failed, unwired.phase);
    try testing.expectEqualStrings(login.public_code_login_unsupported, unwired.public_code.?);
    try testing.expect(unwired.child_closed);
    try testing.expectEqual(login.Exit.unknown, unwired.exit);
}

test "a child that could not be started has no child to reap" {
    const status = login.spawnFailedStatus(.codex, codex_one_id);
    try testing.expectEqual(login.Phase.failed, status.phase);
    try testing.expectEqualStrings(login.public_code_login_spawn_failed, status.public_code.?);
    try testing.expect(!status.child_closed);
    try testing.expectEqual(login.Exit.unknown, status.exit);
    try testing.expect(!status.endedCleanly());
    try testing.expect(status.verification == null);
    try testing.expect(status.belongsTo(.codex, codex_one_id));
}

test "output past the scan bound stops the run instead of growing it" {
    const noise = "unclassified filler line that says nothing at all\n";
    const harness = try RunHarness.create(&.{
        .{ .bytes = noise ** 8 },
        .{ .bytes = "You are now logged in\n" },
    });
    defer harness.destroy();

    const status = harness.run(.codex, codex_one_id, .{ .max_output_bytes = 64 });
    try testing.expectEqual(login.Phase.output_limit, status.phase);
    try testing.expectEqualStrings(login.public_code_login_noisy, status.public_code.?);
    try testing.expect(status.bytes_scanned <= login.min_scan_bytes);
    try testing.expect(!status.endedCleanly());
    try testing.expect(harness.child.reapedExactlyOnce());

    try testing.expect(login.max_lines_scanned > 0);
}

test "a status belongs to exactly one provider and one account" {
    const harness = try RunHarness.create(&.{.{ .bytes = "You are now logged in\n" }});
    defer harness.destroy();

    const status = harness.run(.claude, claude_one_id, .{});
    try testing.expect(status.belongsTo(.claude, claude_one_id));
    try testing.expect(!status.belongsTo(.codex, claude_one_id));
    try testing.expect(!status.belongsTo(.claude, claude_two_id));
}

test "a child that has already exited is reaped without ever being signalled" {
    var prompt: login.FakeProcessControl = .{ .reaped_after_polls = 1 };
    const quick = login.terminate(prompt.control(), .{ .grace_ms = 100, .poll_interval_ms = 5 });
    try testing.expect(quick.isComplete());
    try testing.expect(quick.exitedOnItsOwn());
    try testing.expectEqual(@as(usize, 0), quick.terminate_signals);
    try testing.expectEqual(@as(usize, 0), quick.kill_signals);
    try testing.expectEqual(@as(usize, 1), quick.polls);
    try testing.expectEqual(@as(usize, 0), quick.waits);
    try testing.expect(!quick.escalated);
    try testing.expectEqual(@as(usize, 0), prompt.blocking_reaps);

    try testing.expectEqual(@as(usize, 1), prompt.stdin_closes);
    try testing.expectEqual(@as(usize, 1), prompt.output_closes);

    var exiting: login.FakeProcessControl = .{ .reaped_after_polls = 3 };
    const waited = login.terminate(exiting.control(), .{
        .grace_ms = 100,
        .poll_interval_ms = 5,
        .output_ended = true,
    });
    try testing.expect(waited.isComplete());
    try testing.expect(waited.exitedOnItsOwn());
    try testing.expectEqual(@as(usize, 3), waited.polls);
    try testing.expectEqual(@as(usize, 2), waited.waits);
}

test "a child that is still talking is asked to stop, then killed, and reaped once" {
    var slow: login.FakeProcessControl = .{ .reaped_after_polls = 3 };
    const graceful = login.terminate(slow.control(), .{ .grace_ms = 100, .poll_interval_ms = 5 });
    try testing.expect(graceful.isComplete());
    try testing.expect(!graceful.exitedOnItsOwn());
    try testing.expectEqual(@as(usize, 1), graceful.terminate_signals);
    try testing.expectEqual(@as(usize, 0), graceful.kill_signals);
    try testing.expectEqual(@as(usize, 3), graceful.polls);
    try testing.expect(!graceful.escalated);

    var stubborn: login.FakeProcessControl = .{ .reaped_after_polls = null };
    const escalated = login.terminate(stubborn.control(), .{ .grace_ms = 20, .poll_interval_ms = 5 });
    try testing.expect(escalated.isComplete());
    try testing.expectEqual(@as(usize, 1), escalated.terminate_signals);
    try testing.expectEqual(@as(usize, 1), escalated.kill_signals);
    try testing.expectEqual(@as(usize, 1), escalated.reaps);
    try testing.expect(escalated.escalated);
    try testing.expectEqual(@as(usize, 1), stubborn.blocking_reaps);
    try testing.expectEqual(@as(u32, 20), stubborn.paused_ms);
}

test "the termination sequence is bounded no matter what the policy says" {
    var stubborn: login.FakeProcessControl = .{ .reaped_after_polls = null };
    const record = login.terminate(stubborn.control(), .{
        .grace_ms = std.math.maxInt(u32),
        .poll_interval_ms = 1,

        .output_ended = true,
    });
    try testing.expect(record.isComplete());
    try testing.expect(record.escalated);

    try testing.expectEqual(login.max_grace_polls, record.waits);
    try testing.expect(record.polls <= login.max_grace_polls + 2);

    var other: login.FakeProcessControl = .{ .reaped_after_polls = null };
    const zeroed = login.terminate(other.control(), .{ .grace_ms = 4, .poll_interval_ms = 0 });
    try testing.expect(zeroed.escalated);
    try testing.expectEqual(@as(u32, 4), other.paused_ms);

    var immediate: login.FakeProcessControl = .{ .reaped_after_polls = null };
    const now = login.terminate(immediate.control(), .{ .grace_ms = 0, .poll_interval_ms = 5 });
    try testing.expect(now.isComplete());
    try testing.expectEqual(@as(usize, 0), now.waits);
    try testing.expectEqual(@as(u32, 0), immediate.paused_ms);
    try testing.expect(now.escalated);
}

test "an incomplete termination is not reported as complete" {
    const nothing: login.Termination = .{};
    try testing.expect(!nothing.isComplete());

    const leaked: login.Termination = .{ .stdin_closed = true, .reaps = 1 };
    try testing.expect(!leaked.isComplete());
    const twice: login.Termination = .{
        .stdin_closed = true,
        .output_closed = true,
        .terminate_signals = 1,
        .reaps = 2,
    };
    try testing.expect(!twice.isComplete());
    const straight_to_kill: login.Termination = .{
        .stdin_closed = true,
        .output_closed = true,
        .kill_signals = 1,
        .reaps = 1,
    };
    try testing.expect(!straight_to_kill.isComplete());

    const natural: login.Termination = .{ .stdin_closed = true, .output_closed = true, .reaps = 1 };
    try testing.expect(natural.isComplete());
    try testing.expect(natural.exitedOnItsOwn());
}

test "no provider text survives a run, in any field a caller can read" {
    const harness = try RunHarness.create(&.{
        .{ .bytes = canary_line ++ "\n" },
        .{ .bytes = "access_token=" ++ canary_access ++ "\n" },
        .{ .bytes = "Open the following URL in your browser: " ++ verification_url ++ "\n" },
        .{ .bytes = "Enter the code: " ++ verification_code ++ "\n" },
        .{ .bytes = "refresh_token=" ++ canary_refresh ++ "\n" },
        .{ .bytes = "You are now logged in\n" },
    });
    defer harness.destroy();

    const status = harness.run(.claude, claude_one_id, .{});
    try testing.expectEqual(login.Phase.ended, status.phase);

    try expectNoCanary(std.mem.asBytes(&status));
    try expectNoCanary(status.verification.?.url());
    try expectNoCanary(status.verification.?.code());

    var buffer: [512]u8 = undefined;
    const rendered = try std.fmt.bufPrint(&buffer, "{f}", .{status});
    try expectNoCanary(rendered);
    try testing.expect(std.mem.indexOf(u8, rendered, "phase=") != null);

    try expectNoCanary(std.mem.asBytes(&harness.progress));
    if (status.public_code) |code| try testing.expect(login.isPublicCode(code));
}

test "a verification artifact must be https, host-allowlisted, and too short-runned to hold a token" {
    try testing.expectEqualStrings(
        verification_url,
        login.extractVerificationUrl("Visit " ++ verification_url ++ " to continue.").?,
    );
    try testing.expect(login.extractVerificationUrl("visit http://auth.openai.com/device") == null);
    try testing.expect(login.extractVerificationUrl("visit https://evil.example.invalid/device") == null);
    try testing.expect(login.extractVerificationUrl("visit https://auth.openai.com.evil.invalid/x") == null);

    try testing.expect(login.extractVerificationUrl(
        "visit https://auth.openai.com/cb?token=abcdefghijklmnopqrstuvwxyz0123456789",
    ) == null);
    try testing.expect(login.extractVerificationUrl("no url here at all") == null);

    try testing.expectEqualStrings(
        verification_code,
        login.extractVerificationCode("Enter the code: " ++ verification_code).?,
    );
    try testing.expect(login.extractVerificationCode("Enter the code: 123456789") == null);
    try testing.expect(login.extractVerificationCode("Enter the code: SHORT") == null);
    try testing.expect(login.extractVerificationCode("no code word means no code") == null);
    try testing.expect(login.extractVerificationCode(
        "code: ABCDEFGHIJKLMNOPQRSTUVWXYZ0123456789",
    ) == null);

    try testing.expect(login.extractVerificationCode("code=" ++ canary_access) == null);
}

test "every public code is a static lowercase constant" {
    for (login.public_codes) |code| {
        try testing.expect(code.len != 0);
        try testing.expect(login.isPublicCode(code));
        try testing.expect(std.mem.startsWith(u8, code, "login-"));
        for (code) |byte| {
            const ok = (byte >= 'a' and byte <= 'z') or byte == '-';
            try testing.expect(ok);
        }

        try testing.expectEqualStrings(code, coordinator.canonicalPublicCode(code));
    }
    try testing.expect(!login.isPublicCode("something-else"));
    try testing.expect(!login.isPublicCode(""));
}

test "a run reports typed progress and never a line" {
    const harness = try RunHarness.create(&.{
        .{ .bytes = "Open the following URL in your browser: " ++ verification_url ++ "\n" },
        .{ .bytes = "Enter the code: " ++ verification_code ++ "\n" },
        .{ .bytes = canary_line ++ "\n" },
        .{ .bytes = "You are now logged in\n" },
    });
    defer harness.destroy();

    const status = harness.run(.codex, codex_one_id, .{ .timeout_ms = 60_000 });
    try testing.expectEqual(login.Phase.ended, status.phase);

    const events = harness.progress.slice();
    try testing.expect(events.len >= 6);
    try testing.expectEqual(login.Event.Started{ .provider = .codex, .timeout_ms = 60_000 }, events[0].started);
    try testing.expectEqual(@as(usize, 1), harness.progress.countOf(.started));
    try testing.expectEqual(@as(usize, 1), harness.progress.countOf(.finished));
    try testing.expectEqual(@as(usize, 4), harness.progress.countOf(.signal));

    try testing.expectEqual(@as(usize, 2), harness.progress.countOf(.verification));
    const first = harness.progress.firstVerification().?;
    try testing.expectEqualStrings(verification_url, first.url());
    try testing.expect(!first.hasCode());

    const finished = harness.progress.finished().?;
    try testing.expectEqual(login.Phase.ended, finished.phase);
    try testing.expectEqual(login.Exit.success, finished.exit);
    try testing.expect(finished.public_code == null);

    try testing.expect(events[events.len - 1] == .finished);

    const quiet = try RunHarness.create(&.{.{ .bytes = "You are now logged in\n" }});
    defer quiet.destroy();
    var runner: login.Runner = .init(quiet.child.handle(), &quiet.storage, .codex, codex_one_id);
    const quiet_status = runner.run(.{ .progress = login.discardProgress() });
    try testing.expect(quiet_status.endedCleanly());
}

test "a login session serializes the account and hands back the exact command" {
    const app = try newCoordinator();
    defer app.destroy();
    try seedAccounts(app);

    var session = try app.beginLogin(codex_one_id, .initial, .details, fixture_now);
    defer app.closeLoginSession(&session);
    try testing.expectEqualStrings(codex_one_id, session.account_id);
    try testing.expectEqual(domain.Provider.codex, session.provider);
    try testing.expectEqualStrings(codex_one_home, session.homePath());
    try testing.expectEqual(@as(usize, 1), app.inFlightCount());

    var spec: coordinator.LoginSpec = .{};
    try app.writeSessionLoginSpec(&session, &spec, parentEnv());
    try testing.expectEqualStrings(codex_executable, spec.argv()[0]);
    try testing.expectEqualStrings(codex_one_home, spec.env.find("CODEX_HOME").?);
    try testing.expect(spec.isolationIsConsistent());

    try testing.expectEqual(coordinator.EnqueueOutcome.already_pending, try app.requestRefresh(codex_one_id));
    try testing.expectError(error.AccountBusy, app.beginLogin(codex_one_id, .initial, .details, fixture_now));
    try testing.expect(app.statusFor(codex_one_id).?.operation_in_flight);

    var other = try app.beginLogin(codex_two_id, .initial, .details, fixture_now);
    app.closeLoginSession(&other);
}

test "a login is refused from the tray, for a disabled account, and for an unknown one" {
    const app = try newCoordinator();
    defer app.destroy();
    try seedAccounts(app);

    try testing.expectError(
        error.SurfaceNotAllowed,
        app.beginLogin(claude_one_id, .initial, .tray, fixture_now),
    );
    try testing.expectError(
        error.UnknownAccount,
        app.beginLogin("acct-does-not-exist", .initial, .details, fixture_now),
    );
    try app.registry.setEnabled(claude_one_id, false);
    try testing.expectError(
        error.AccountDisabled,
        app.beginLogin(claude_one_id, .initial, .details, fixture_now),
    );

    try testing.expect(app.schedulerIsIdle());
}

test "a completed login clears a reauthentication state without claiming a credential" {
    const app = try newCoordinator();
    defer app.destroy();
    try seedAccounts(app);
    _ = try app.registry.markConnected(claude_one_id, null);
    _ = try app.registry.markAuthState(claude_one_id, .reauth_required);
    const before = app.account(claude_one_id).?.auth_revision;

    var session = try app.beginLogin(claude_one_id, .reauthenticate, .details, fixture_now);
    defer app.closeLoginSession(&session);

    const harness = try RunHarness.create(&.{
        .{ .bytes = "Open the following URL in your browser: https://claude.ai/device\n" },
        .{ .bytes = "You are now logged in\n" },
    });
    defer harness.destroy();
    const status = harness.run(.claude, claude_one_id, .{});
    try testing.expect(status.endedCleanly());

    const report = try app.applyLoginResult(&session, status, fixture_now + 30, coordinator.unwiredDocumentSink());
    try testing.expect(report.succeeded());
    try testing.expectEqual(coordinator.LoginPurpose.reauthenticate, report.purpose);
    try testing.expect(report.child_closed);

    try testing.expectEqual(authState(app, claude_one_id), .unavailable);
    try testing.expect(report.auth_state_changed);
    try testing.expectEqual(before, report.auth_revision);
    try testing.expect(report.public_code == null);

    try testing.expect(app.schedulerIsIdle());
    try testing.expectEqual(domain.RefreshPhase.idle, app.statusFor(claude_one_id).?.phase);
    try testing.expect(app.statusFor(claude_one_id).?.last_attempt_code == null);
    try testing.expectEqual(coordinator.Freshness.never_refreshed, app.rowFor(claude_one_id, fixture_now).?.freshness);

    var codex_session = try app.beginLogin(codex_one_id, .initial, .details, fixture_now);
    defer app.closeLoginSession(&codex_session);
    const codex_harness = try RunHarness.create(&.{.{ .bytes = "You are now logged in\n" }});
    defer codex_harness.destroy();
    const codex_report = try app.applyLoginResult(
        &codex_session,
        codex_harness.run(.codex, codex_one_id, .{}),
        fixture_now + 40,
        coordinator.unwiredDocumentSink(),
    );
    try testing.expect(codex_report.succeeded());
}

fn authState(app: *coordinator.Coordinator, id: []const u8) account_registry.AuthState {
    return app.account(id).?.auth_state;
}

test "a failed login records why and changes nothing about the credentials" {
    const app = try newCoordinator();
    defer app.destroy();
    try seedAccounts(app);
    _ = try app.registry.markConnected(claude_one_id, null);
    const before = app.account(claude_one_id).?.auth_revision;

    var session = try app.beginLogin(claude_one_id, .reauthenticate, .details, fixture_now);
    defer app.closeLoginSession(&session);

    const harness = try RunHarness.create(&.{.{ .failure = error.Timeout }});
    defer harness.destroy();
    const status = harness.run(.claude, claude_one_id, .{ .timeout_ms = 60_000 });

    const report = try app.applyLoginResult(&session, status, fixture_now + 60, coordinator.unwiredDocumentSink());
    try testing.expect(!report.succeeded());
    try testing.expectEqual(login.Phase.timed_out, report.phase);
    try testing.expectEqualStrings(login.public_code_login_timeout, report.public_code.?);
    try testing.expect(!report.auth_state_changed);

    try testing.expectEqual(before, app.account(claude_one_id).?.auth_revision);
    try testing.expectEqual(authState(app, claude_one_id), .connected);
    try testing.expectEqualStrings(
        login.public_code_login_timeout,
        app.statusFor(claude_one_id).?.last_attempt_code.?,
    );
    try testing.expect(app.schedulerIsIdle());
}

test "a status from another account or provider is not evidence about this login" {
    const app = try newCoordinator();
    defer app.destroy();
    try seedAccounts(app);

    var session = try app.beginLogin(claude_one_id, .initial, .details, fixture_now);
    defer app.closeLoginSession(&session);

    const harness = try RunHarness.create(&.{.{ .bytes = "You are now logged in\n" }});
    defer harness.destroy();
    const foreign_account = harness.run(.claude, claude_two_id, .{});
    try testing.expectError(
        error.UnknownOperation,
        app.applyLoginResult(&session, foreign_account, fixture_now, coordinator.unwiredDocumentSink()),
    );

    const other = try RunHarness.create(&.{.{ .bytes = "You are now logged in\n" }});
    defer other.destroy();
    const foreign_provider = other.run(.codex, claude_one_id, .{});
    try testing.expectError(
        error.UnknownOperation,
        app.applyLoginResult(&session, foreign_provider, fixture_now, coordinator.unwiredDocumentSink()),
    );

    try testing.expectEqual(coordinator.LoginSession.Stage.running, session.stage);
    try testing.expectEqual(@as(usize, 1), app.inFlightCount());

    const good = try RunHarness.create(&.{.{ .bytes = "You are now logged in\n" }});
    defer good.destroy();
    const status = good.run(.claude, claude_one_id, .{});
    _ = try app.applyLoginResult(&session, status, fixture_now, coordinator.unwiredDocumentSink());
    try testing.expectError(
        error.SessionClosed,
        app.applyLoginResult(&session, status, fixture_now, coordinator.unwiredDocumentSink()),
    );
}

test "abandoning a login releases the account exactly once" {
    const app = try newCoordinator();
    defer app.destroy();
    try seedAccounts(app);

    var session = try app.beginLogin(codex_one_id, .initial, .details, fixture_now);
    try testing.expectEqual(@as(usize, 1), app.inFlightCount());
    app.closeLoginSession(&session);
    try testing.expectEqual(@as(usize, 0), app.inFlightCount());

    app.closeLoginSession(&session);
    app.closeLoginSession(&session);
    try testing.expectEqual(@as(usize, 0), app.inFlightCount());
    try testing.expect(app.schedulerIsIdle());

    var spec: coordinator.LoginSpec = .{};
    try testing.expectError(error.UnknownAccount, app.writeSessionLoginSpec(&session, &spec, parentEnv()));
}

test "the production child and its spawn path are compiled but never started here" {
    testing.refAllDecls(login);
    testing.refAllDecls(login.ChildProcess);
    testing.refAllDecls(login.LoginSpec);

    try testing.expectEqual(login.Exit.success, login.exitFromStatus(0));
    try testing.expectEqual(login.Exit.failure, login.exitFromStatus(1 << 8));
    try testing.expectEqual(login.Exit.signaled, login.exitFromStatus(9));

    try testing.expect(login.min_scan_bytes >= 2 * login.max_line_bytes);
    try testing.expectEqual(login.codex_login_args.len + 1, login.max_login_argv);
}
