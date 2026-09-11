const std = @import("std");
const domain = @import("../domain.zig");
const store = @import("../store.zig");
const transport = @import("../process_jsonl.zig");
const codex = @import("../providers/codex.zig");
const protocol = @import("codex_protocol_test_fixtures.zig");

const testing = std.testing;

const account_home = "/demo/app-data/accounts/codex-demo";
const other_account_home = "/demo/app-data/accounts/codex-other";
const account_id = "acct-codex-demo";

const fixture_now: i64 = 2_000_000_000;

const canary_email = "demo-user@example.invalid";
const canary_plan = "demo-plan-name";
const canary_message = "provider-detail-should-not-leak";

const frame = protocol.frame;

const initialize_ok = frame(
    \\{"jsonrpc":"2.0","id":1,"result":{"userAgent":"codex-demo/0.0","codexHome":"/demo/app-data/accounts/codex-demo","platformOs":"macos","platformFamily":"unix"}}
);

const initialize_other_home = frame(
    \\{"jsonrpc":"2.0","id":1,"result":{"userAgent":"codex-demo/0.0","codexHome":"/demo/app-data/accounts/codex-other","platformOs":"macos","platformFamily":"unix"}}
);

const initialize_no_home = frame(
    \\{"jsonrpc":"2.0","id":1,"result":{"userAgent":"codex-demo/0.0","platformOs":"macos"}}
);

const account_ok = frame(
    \\{"jsonrpc":"2.0","id":2,"result":{"account":{"type":"chatgpt","email":"demo-user@example.invalid","planType":"demo-plan-name"}}}
);

const account_pro = frame(
    \\{"jsonrpc":"2.0","id":2,"result":{"account":{"type":"chatgpt","email":"demo-user@example.invalid","planType":"pro"}}}
);

const account_signed_out = frame(
    \\{"jsonrpc":"2.0","id":2,"result":{"account":null}}
);

const rate_limits_multi = frame(
    \\{"jsonrpc":"2.0","id":3,"result":{"rateLimits":{"limitId":"chatgpt","limitName":"ChatGPT","primary":{"usedPercent":24.4,"windowDurationMins":300,"resetsAt":2000003600},"secondary":{"usedPercent":61,"windowDurationMins":10080,"resetsAt":2000600000}},"rateLimitsByLimitId":{"demo-model":{"limitName":"Demo Model","primary":{"usedPercent":7,"windowDurationMins":300,"resetsAt":2000003600}}},"rateLimitResetCredits":{"availableCount":2,"credits":[{"id":"credit-demo-a","resetType":"weekly","grantedAt":1999000000,"expiresAt":2000600000,"description":"Weekly reset"},{"id":"credit-demo-b","resetType":"weekly","grantedAt":1999000000,"expiresAt":null,"description":"Bonus reset"}]}}}
);

const rate_limits_single = frame(
    \\{"jsonrpc":"2.0","id":3,"result":{"rateLimits":{"primary":{"usedPercent":10,"windowDurationMins":null,"resetsAt":null}},"rateLimitsByLimitId":null,"rateLimitResetCredits":null}}
);

const rate_limits_count_only = frame(
    \\{"jsonrpc":"2.0","id":3,"result":{"rateLimits":{"primary":{"usedPercent":33,"windowDurationMins":300,"resetsAt":2000003600}},"rateLimitResetCredits":{"availableCount":3,"credits":null}}}
);

const rate_limits_capped_details = frame(
    \\{"jsonrpc":"2.0","id":3,"result":{"rateLimits":{"primary":{"usedPercent":5,"windowDurationMins":300,"resetsAt":2000003600}},"rateLimitResetCredits":{"availableCount":1,"credits":[{"id":"credit-demo-a","description":"First"},{"id":"credit-demo-b","description":"Second"}]}}}
);

const rate_limits_unusable_credit = frame(
    \\{"jsonrpc":"2.0","id":3,"result":{"rateLimits":{"primary":{"usedPercent":5,"windowDurationMins":300,"resetsAt":2000003600}},"rateLimitResetCredits":{"availableCount":2,"credits":[{"id":"credit-demo-a","description":"First"},{"resetType":"weekly","description":"No id"}]}}}
);

const rate_limits_no_count = frame(
    \\{"jsonrpc":"2.0","id":3,"result":{"rateLimits":{"primary":{"usedPercent":5,"windowDurationMins":300,"resetsAt":2000003600}},"rateLimitResetCredits":{"credits":[{"id":"credit-demo-a"}]}}}
);

const rate_limits_empty = frame(
    \\{"jsonrpc":"2.0","id":3,"result":{"rateLimits":null,"rateLimitsByLimitId":null,"rateLimitResetCredits":null}}
);

const rate_limits_absurd_numbers = frame(
    \\{"jsonrpc":"2.0","id":3,"result":{"rateLimits":{"primary":{"usedPercent":50,"windowDurationMins":1e300,"resetsAt":1e300},"secondary":{"usedPercent":50,"windowDurationMins":99999999999999999999999,"resetsAt":-1e300}},"rateLimitResetCredits":{"availableCount":1e300}}}
);

const rate_limits_clamped = frame(
    \\{"jsonrpc":"2.0","id":3,"result":{"rateLimits":{"primary":{"usedPercent":140,"windowDurationMins":300,"resetsAt":99999999999},"secondary":{"usedPercent":-4,"windowDurationMins":10080,"resetsAt":0}}}}
);

const rate_limits_malformed_window = frame(
    \\{"jsonrpc":"2.0","id":3,"result":{"rateLimits":{"primary":{"usedPercent":12,"windowDurationMins":300},"secondary":{"windowDurationMins":10080}}}}
);

const notification_rate_limits_updated = frame(
    \\{"jsonrpc":"2.0","method":"account/rateLimits/updated","params":{"id":99,"rateLimits":{"primary":{"usedPercent":1}}}}
);

const notification_account_updated = frame(
    \\{"jsonrpc":"2.0","method":"account/updated","params":{"authMode":"chatgpt","planType":"demo-plan-name"}}
);

const foreign_response = frame(
    \\{"jsonrpc":"2.0","id":424242,"result":{"ignored":true}}
);

const string_id_response = frame(
    \\{"jsonrpc":"2.0","id":"not-ours","result":{"ignored":true}}
);

const server_request = frame(
    \\{"jsonrpc":"2.0","id":7001,"method":"item/commandExecution/requestApproval","params":{"callId":"demo"}}
);

fn errorFrame(comptime id: []const u8, comptime code: []const u8) []const u8 {
    return frame("{\"jsonrpc\":\"2.0\",\"id\":" ++ id ++ ",\"error\":{\"code\":" ++ code ++
        ",\"message\":\"" ++ canary_message ++ "\"}}");
}

fn consumeResponse(comptime outcome: []const u8) []const u8 {
    return frame("{\"jsonrpc\":\"2.0\",\"id\":2,\"result\":{\"outcome\":\"" ++ outcome ++ "\"}}");
}

const script_consume_reset = initialize_ok ++ consumeResponse("reset");
const script_consume_already_redeemed = initialize_ok ++ consumeResponse("alreadyRedeemed");
const script_consume_unknown_outcome = initialize_ok ++ consumeResponse("somethingElse");
const script_consume_no_outcome = initialize_ok ++ frame(
    \\{"jsonrpc":"2.0","id":2,"result":{}}
);
const script_consume_not_routed = initialize_ok ++ errorFrame("2", "-32601");
const script_consume_internal_error = initialize_ok ++ errorFrame("2", "-32603");
const script_consume_wrong_home = initialize_other_home ++ consumeResponse("reset");

const script_rpc_method_not_found = initialize_ok ++ account_ok ++ errorFrame("3", "-32601");
const script_rpc_invalid_params = initialize_ok ++ account_ok ++ errorFrame("3", "-32602");
const script_rpc_parse_error = initialize_ok ++ account_ok ++ errorFrame("3", "-32700");
const script_rpc_internal_error = initialize_ok ++ account_ok ++ errorFrame("3", "-32603");
const script_rpc_server_error = initialize_ok ++ account_ok ++ errorFrame("3", "-32000");

const script_consume_reset_outcomes = [_]struct { script: []const u8, outcome: domain.ResetOutcome }{
    .{ .script = script_consume_reset, .outcome = .reset },
    .{ .script = initialize_ok ++ consumeResponse("nothingToReset"), .outcome = .nothing_to_reset },
    .{ .script = initialize_ok ++ consumeResponse("noCredit"), .outcome = .no_credit },
    .{ .script = script_consume_already_redeemed, .outcome = .already_redeemed },
};

const consume_after_refresh = frame(
    \\{"jsonrpc":"2.0","id":4,"result":{"outcome":"reset"}}
);

test "a consume on an already initialized connection sends no second initialize" {
    const harness = try Harness.create(&.{chunk(initialize_ok ++ account_ok ++ rate_limits_multi ++ consume_after_refresh)});
    defer harness.destroy();
    const refreshed = harness.refresh();
    try testing.expect(refreshed.succeeded());
    try testing.expect(refreshed.home_verified);

    const attempt: domain.ResetAttempt = .{
        .idempotency_key = "attempt-demo-0001",
        .account_id = account_id,
        .selected_credit_id = "credit-demo-a",
        .created_at_unix_s = fixture_now,
        .updated_at_unix_s = fixture_now,
        .preflight_observed_at_unix_s = fixture_now,
        .preflight_available_count = 2,
        .confirmed_at_unix_s = fixture_now,
        .phase = .submitted,
    };
    const outcome = harness.adapter().consumeResetCredit(&harness.connection, &harness.workspace, .{
        .account_id = account_id,
        .attempt = &attempt,
        .credit_id = "credit-demo-a",
        .now_unix_s = fixture_now,
    });
    try testing.expectEqual(domain.ResetOutcome.reset, outcome.completed);
    try expectMethodSequence(&harness.stream, &.{
        codex.method_initialize,
        codex.method_initialized,
        codex.method_account_read,
        codex.method_rate_limits_read,
        codex.method_reset_credit_consume,
    });
}

const Harness = struct {
    stream: transport.FakeStream,
    storage: [transport.max_frame_bytes]u8,
    connection: transport.Connection,
    workspace: codex.Workspace,

    fn create(chunks: []const transport.FakeStream.Chunk) !*Harness {
        const harness = try testing.allocator.create(Harness);
        harness.stream = .{ .chunks = chunks };
        harness.connection = .init(&harness.storage, harness.stream.stream());
        harness.workspace.resetReading();
        return harness;
    }

    fn destroy(self: *Harness) void {
        testing.allocator.destroy(self);
    }

    fn adapter(_: *Harness) codex.Adapter {
        return .{ .config = .{ .codex_home = account_home } };
    }

    fn refresh(self: *Harness) codex.RefreshOutcome {
        return self.adapter().refresh(&self.connection, &self.workspace, .{
            .account_id = account_id,
            .now_unix_s = fixture_now,
        });
    }
};

fn chunk(bytes: []const u8) transport.FakeStream.Chunk {
    return .{ .bytes = bytes };
}

fn methodOf(line: []const u8) ?[]const u8 {
    const marker = "\"method\":\"";
    const start = std.mem.indexOf(u8, line, marker) orelse return null;
    const rest = line[start + marker.len ..];
    const end = std.mem.indexOfScalar(u8, rest, '"') orelse return null;
    return rest[0..end];
}

fn expectMethodSequence(stream: *const transport.FakeStream, expected: []const []const u8) !void {
    var lines = stream.writtenFrames();
    var index: usize = 0;
    while (lines.next()) |line| {
        if (line.len == 0) continue;
        if (index >= expected.len) return error.TestUnexpectedResult;
        const method = methodOf(line) orelse return error.TestUnexpectedResult;
        try testing.expectEqualStrings(expected[index], method);
        index += 1;
    }
    try testing.expectEqual(expected.len, index);
}

fn writtenLineCount(stream: *const transport.FakeStream) usize {
    var lines = stream.writtenFrames();
    var count: usize = 0;
    while (lines.next()) |line| {
        if (line.len != 0) count += 1;
    }
    return count;
}

fn expectNoCanaries(text: []const u8) !void {
    for ([_][]const u8{ canary_email, canary_plan, canary_message, "example.invalid" }) |needle| {
        try testing.expect(std.mem.indexOf(u8, text, needle) == null);
    }
}

fn windowOfKind(windows: []const domain.UsageWindow, kind: domain.UsageWindowKind) ?domain.UsageWindow {
    for (windows) |window| {
        if (window.kind == kind) return window;
    }
    return null;
}

test "frames reassemble from arbitrary fragmentation" {
    var chunks: [initialize_ok.len]transport.FakeStream.Chunk = undefined;
    for (&chunks, 0..) |*slot, index| slot.* = chunk(initialize_ok[index .. index + 1]);

    const harness = try Harness.create(&chunks);
    defer harness.destroy();

    const received = try harness.connection.awaitResponse(1);
    try testing.expect(std.mem.startsWith(u8, received, "{\"jsonrpc\""));
    try testing.expect(std.mem.endsWith(u8, received, "}"));
    try testing.expectEqual(@as(usize, 1), harness.connection.stats.frames_read);
    try testing.expect(harness.stream.read_count >= initialize_ok.len);
}

test "one read can deliver several frames" {
    const three_at_once = notification_account_updated ++ foreign_response ++ initialize_ok;
    const harness = try Harness.create(&[_]transport.FakeStream.Chunk{chunk(three_at_once)});
    defer harness.destroy();

    _ = try harness.connection.awaitResponse(1);
    try testing.expectEqual(@as(usize, 3), harness.connection.stats.frames_read);
    try testing.expectEqual(@as(usize, 1), harness.connection.stats.notifications_skipped);
    try testing.expectEqual(@as(usize, 1), harness.connection.stats.foreign_responses_skipped);

    try testing.expectEqual(@as(usize, 1), harness.stream.read_count);
}

test "a frame split across reads is one message" {
    const split_at = 40;
    const harness = try Harness.create(&[_]transport.FakeStream.Chunk{
        chunk(initialize_ok[0..split_at]),
        .empty,
        chunk(initialize_ok[split_at..]),
    });
    defer harness.destroy();

    const received = try harness.connection.awaitResponse(1);
    try testing.expectEqualStrings(initialize_ok[0 .. initialize_ok.len - 1], received);
}

test "blank lines and carriage returns are framing, not messages" {
    const noisy = "\n\r\n   \n" ++ initialize_ok[0 .. initialize_ok.len - 1] ++ "\r\n";
    const harness = try Harness.create(&[_]transport.FakeStream.Chunk{chunk(noisy)});
    defer harness.destroy();

    const received = try harness.connection.awaitResponse(1);
    try testing.expectEqualStrings(initialize_ok[0 .. initialize_ok.len - 1], received);

    try testing.expectEqual(@as(usize, 1), harness.connection.stats.frames_read);
}

test "notifications and foreign response ids are skipped while awaiting one response" {
    const script = notification_rate_limits_updated ++ foreign_response ++ string_id_response ++
        notification_account_updated ++ initialize_ok;
    const harness = try Harness.create(&[_]transport.FakeStream.Chunk{chunk(script)});
    defer harness.destroy();

    const received = try harness.connection.awaitResponse(1);
    try testing.expect(std.mem.indexOf(u8, received, "codexHome") != null);
    try testing.expectEqual(@as(usize, 2), harness.connection.stats.notifications_skipped);

    try testing.expectEqual(@as(usize, 2), harness.connection.stats.foreign_responses_skipped);
}

test "server requests are skipped rather than answered" {
    const harness = try Harness.create(&[_]transport.FakeStream.Chunk{chunk(server_request ++ initialize_ok)});
    defer harness.destroy();

    _ = try harness.connection.awaitResponse(1);
    try testing.expectEqual(@as(usize, 1), harness.connection.stats.server_requests_skipped);

    try testing.expectEqual(@as(usize, 0), harness.stream.written_len);
}

test "classification reads only top-level members" {
    const nested =
        \\{"jsonrpc":"2.0","method":"thread/started","params":{"id":5,"inner":{"method":"x","result":1}}}
    ;
    const envelope = try transport.classify(nested);
    try testing.expectEqual(transport.EnvelopeKind.notification, envelope.kind());
    try testing.expect(envelope.id == null);

    const response = try transport.classify(
        \\{"jsonrpc":"2.0","id":42,"result":{"id":"inner","method":"inner"}}
    );
    try testing.expectEqual(transport.EnvelopeKind.response, response.kind());
    try testing.expect(response.isResponseTo(42));
    try testing.expect(!response.isResponseTo(43));

    const failure = try transport.classify(
        \\{"jsonrpc":"2.0","id":42,"error":{"code":-32601,"message":"x"}}
    );
    try testing.expectEqual(transport.EnvelopeKind.response, failure.kind());
    try testing.expect(failure.has_error);

    try testing.expectError(error.MalformedFrame, transport.classify("[1,2,3]"));
    try testing.expectError(error.MalformedFrame, transport.classify("\"hello\""));
    try testing.expectEqual(transport.EnvelopeKind.unrecognized, (try transport.classify("{\"a\":1}")).kind());

    try testing.expectError(error.MalformedFrame, transport.classify("{\"a\":1} {\"b\":2}"));
}

test "malformed frame poisons the connection with one stable error" {
    const harness = try Harness.create(&[_]transport.FakeStream.Chunk{chunk("{not json\n" ++ initialize_ok)});
    defer harness.destroy();

    try testing.expectError(error.MalformedFrame, harness.connection.awaitResponse(1));

    try testing.expectError(error.MalformedFrame, harness.connection.awaitResponse(1));
    try testing.expectError(error.MalformedFrame, harness.connection.writeFrame("{}"));
}

test "a line longer than the frame bound fails closed" {
    const oversized = "x" ** (transport.max_frame_bytes + 16);
    const harness = try Harness.create(&[_]transport.FakeStream.Chunk{chunk(oversized)});
    defer harness.destroy();

    try testing.expectError(error.FrameTooLarge, harness.connection.awaitResponse(1));
    try testing.expectError(error.FrameTooLarge, harness.connection.awaitResponse(2));
}

test "timeout and end of stream are distinct sanitized failures" {
    const timed_out = try Harness.create(&[_]transport.FakeStream.Chunk{
        chunk(notification_account_updated),
        .{ .failure = error.Timeout },
    });
    defer timed_out.destroy();
    try testing.expectError(error.Timeout, timed_out.connection.awaitResponse(1));

    const closed = try Harness.create(&[_]transport.FakeStream.Chunk{});
    defer closed.destroy();
    try testing.expectError(error.EndOfStream, closed.connection.awaitResponse(1));
}

test "a truncated trailing frame is not a frame" {
    const harness = try Harness.create(&[_]transport.FakeStream.Chunk{
        chunk(initialize_ok[0 .. initialize_ok.len - 8]),
    });
    defer harness.destroy();

    try testing.expectError(error.EndOfStream, harness.connection.awaitResponse(1));
    try testing.expectEqual(@as(usize, 0), harness.connection.stats.frames_read);
}

test "interleaved traffic is bounded" {
    var chunks: [transport.max_interleaved_frames + 2]transport.FakeStream.Chunk = undefined;
    for (&chunks) |*slot| slot.* = chunk(notification_account_updated);

    const harness = try Harness.create(&chunks);
    defer harness.destroy();

    try testing.expectError(error.TooManyFrames, harness.connection.awaitResponse(1));
    try testing.expect(harness.connection.stats.notifications_skipped <= transport.max_interleaved_frames + 1);
}

test "empty reads are tolerated but not forever" {
    var chunks: [transport.max_empty_reads + 2]transport.FakeStream.Chunk = undefined;
    for (&chunks) |*slot| slot.* = .empty;

    const harness = try Harness.create(&chunks);
    defer harness.destroy();
    try testing.expectError(error.Io, harness.connection.awaitResponse(1));

    var tolerant: [transport.max_empty_reads]transport.FakeStream.Chunk = undefined;
    for (&tolerant) |*slot| slot.* = .empty;
    const patient = try Harness.create(&tolerant);
    defer patient.destroy();

    try testing.expectError(error.EndOfStream, patient.connection.awaitResponse(1));
}

test "request ids are never reused" {
    const harness = try Harness.create(&[_]transport.FakeStream.Chunk{});
    defer harness.destroy();

    var seen: [8]i64 = undefined;
    for (&seen) |*slot| slot.* = harness.connection.allocateId();
    for (seen, 0..) |value, index| {
        for (seen[index + 1 ..]) |other| try testing.expect(value != other);
    }
}

test "encoded requests omit absent optional members" {
    var buffer: [512]u8 = undefined;
    const with_credit = try transport.encodeRequest(&buffer, 9, "demo/method", .{
        .idempotencyKey = @as([]const u8, "attempt-demo-0001"),
        .creditId = @as(?[]const u8, "credit-demo-a"),
    });
    try testing.expect(std.mem.indexOf(u8, with_credit, "\"creditId\":\"credit-demo-a\"") != null);
    try testing.expect(std.mem.indexOf(u8, with_credit, "\"id\":9") != null);
    try testing.expect(std.mem.indexOf(u8, with_credit, "\"jsonrpc\":\"2.0\"") != null);

    var other: [512]u8 = undefined;
    const without_credit = try transport.encodeRequest(&other, 10, "demo/method", .{
        .idempotencyKey = @as([]const u8, "attempt-demo-0001"),
        .creditId = @as(?[]const u8, null),
    });

    try testing.expect(std.mem.indexOf(u8, without_credit, "creditId") == null);

    var notification: [512]u8 = undefined;
    const line = try transport.encodeNotification(&notification, "initialized", struct {}{});

    try testing.expect(std.mem.indexOf(u8, line, "\"id\"") == null);
    try testing.expect(std.mem.indexOf(u8, line, "\"params\":{}") != null);

    var tiny: [8]u8 = undefined;
    try testing.expectError(error.RequestTooLarge, transport.encodeRequest(&tiny, 1, "demo/method", .{}));
}

test "an unwired stream fails closed" {
    var storage: [64]u8 = undefined;
    var connection: transport.Connection = .init(&storage, transport.unwiredStream());
    try testing.expectError(error.Unsupported, connection.writeFrame("{}"));
    try testing.expectError(error.Unsupported, connection.awaitResponse(1));
}

test "a spawned child is terminated and reaped exactly once" {
    var lifecycle: transport.FakeChildLifecycle = .{};
    try testing.expect(!lifecycle.reapedExactlyOnce());

    lifecycle.close();
    try testing.expect(lifecycle.reapedExactlyOnce());

    lifecycle.close();
    lifecycle.close();
    try testing.expectEqual(@as(usize, 1), lifecycle.kills);
    try testing.expectEqual(@as(usize, 1), lifecycle.stdin_closes);
    try testing.expect(lifecycle.reapedExactlyOnce());
}

test "frame descriptors carry shape, never content" {
    const envelope = try transport.classify(
        \\{"jsonrpc":"2.0","id":42,"result":{"secretish":"provider-detail-should-not-leak"}}
    );
    const descriptor = transport.FrameDescriptor.of(initialize_ok, envelope);

    var buffer: [128]u8 = undefined;
    var writer = std.Io.Writer.fixed(&buffer);
    try descriptor.format(&writer);
    const rendered = writer.buffered();

    try testing.expect(std.mem.indexOf(u8, rendered, "id=42") != null);
    try expectNoCanaries(rendered);
    try testing.expect(std.mem.indexOf(u8, rendered, "codexHome") == null);
}

test "child environment is an allowlist plus exactly one CODEX_HOME" {
    var child_env: std.process.Environ.Map = .init(testing.allocator);
    defer child_env.deinit();

    const parent = [_]transport.EnvVar{
        .{ .name = "PATH", .value = "/usr/bin:/bin" },
        .{ .name = "HOME", .value = "/demo/home" },
        .{ .name = "LANG", .value = "en_US.UTF-8" },
        .{ .name = "EDITOR", .value = "demo-editor" },
    };

    try transport.buildChildEnv(&child_env, .{ .pairs = &parent }, account_home);

    try testing.expectEqualStrings("/usr/bin:/bin", child_env.get("PATH").?);
    try testing.expectEqualStrings("/demo/home", child_env.get("HOME").?);
    try testing.expectEqualStrings(account_home, child_env.get(transport.codex_home_var).?);

    try testing.expect(child_env.get("EDITOR") == null);
    try testing.expectEqual(@as(usize, 4), child_env.count());
}

test "a fallback CLI directory is prepended to Finder's minimal PATH" {
    var child_env: std.process.Environ.Map = .init(testing.allocator);
    defer child_env.deinit();
    try child_env.put("PATH", "/usr/bin:/bin:/usr/sbin:/sbin");
    try child_env.put("HOME", "/demo/home");

    try transport.prependExecutableDirectoryToPath(
        &child_env,
        "/demo/home/.local/bin/codex",
    );
    try testing.expectEqualStrings(
        "/demo/home/.local/bin:/usr/bin:/bin:/usr/sbin:/sbin",
        child_env.get("PATH").?,
    );

    try transport.prependExecutableDirectoryToPath(
        &child_env,
        "/demo/home/.local/bin/codex",
    );
    try testing.expectEqualStrings(
        "/demo/home/.local/bin:/usr/bin:/bin:/usr/sbin:/sbin",
        child_env.get("PATH").?,
    );
    try testing.expectEqualStrings("/demo/home", child_env.get("HOME").?);
    try testing.expectError(
        error.InvalidExecutablePath,
        transport.prependExecutableDirectoryToPath(&child_env, "relative/codex"),
    );
}

test "inherited provider credentials never reach the child" {
    var child_env: std.process.Environ.Map = .init(testing.allocator);
    defer child_env.deinit();

    const parent = [_]transport.EnvVar{
        .{ .name = "PATH", .value = "/usr/bin" },
        .{ .name = "CODEX_HOME", .value = "/demo/other-home" },
        .{ .name = "CODEX_API_KEY", .value = "placeholder-not-a-key" },
        .{ .name = "OPENAI_API_KEY", .value = "placeholder-not-a-key" },
        .{ .name = "OPENAI_BASE_URL", .value = "https://demo.example.invalid" },
        .{ .name = "ANTHROPIC_API_KEY", .value = "placeholder-not-a-key" },
        .{ .name = "CLAUDE_CONFIG_DIR", .value = "/demo/claude" },
        .{ .name = "CHATGPT_ACCOUNT_ID", .value = "demo-account" },
        .{ .name = "AWS_SECRET_ACCESS_KEY", .value = "placeholder-not-a-key" },
        .{ .name = "GITHUB_TOKEN", .value = "placeholder-not-a-key" },
        .{ .name = "HTTPS_PROXY", .value = "http://demo.example.invalid" },
        .{ .name = "NODE_OPTIONS", .value = "--require /demo/inject.js" },
    };

    try transport.buildChildEnv(&child_env, .{ .pairs = &parent }, account_home);

    try testing.expectEqual(@as(usize, 2), child_env.count());
    try testing.expectEqualStrings("/usr/bin", child_env.get("PATH").?);

    try testing.expectEqualStrings(account_home, child_env.get(transport.codex_home_var).?);

    for (parent[1..]) |scrubbed| {
        if (std.mem.eql(u8, scrubbed.name, transport.codex_home_var)) continue;
        try testing.expect(child_env.get(scrubbed.name) == null);
        try testing.expect(transport.isScrubbed(scrubbed.name));
        try testing.expect(!transport.isInheritable(scrubbed.name));
    }
}

test "two accounts get two homes and the parent environment is untouched" {
    var parent_map: std.process.Environ.Map = .init(testing.allocator);
    defer parent_map.deinit();
    try parent_map.put("PATH", "/usr/bin");
    try parent_map.put("CODEX_HOME", "/demo/ambient-home");

    var first: std.process.Environ.Map = .init(testing.allocator);
    defer first.deinit();
    var second: std.process.Environ.Map = .init(testing.allocator);
    defer second.deinit();

    try transport.buildChildEnv(&first, .{ .map = &parent_map }, account_home);
    try transport.buildChildEnv(&second, .{ .map = &parent_map }, other_account_home);

    try testing.expectEqualStrings(account_home, first.get(transport.codex_home_var).?);
    try testing.expectEqualStrings(other_account_home, second.get(transport.codex_home_var).?);

    try testing.expectEqualStrings("/demo/ambient-home", parent_map.get("CODEX_HOME").?);
    try testing.expectEqual(@as(usize, 2), parent_map.count());
}

test "a per-account home must be absolute and canonical" {
    try transport.validateCodexHome(account_home);

    const rejected = [_][]const u8{
        "",
        "relative/path",
        "/demo/trailing/",
        "/demo/../escape",
        "/demo/./here",
        "/demo//double",
        "/",
        "/demo/with\nnewline",
        "/demo/with=equals",
        "/demo/with\x00nul",
    };
    for (rejected) |candidate| {
        try testing.expectError(error.InvalidCodexHome, transport.validateCodexHome(candidate));
    }

    var child_env: std.process.Environ.Map = .init(testing.allocator);
    defer child_env.deinit();
    try testing.expectError(error.InvalidCodexHome, transport.buildChildEnv(&child_env, .{ .pairs = &.{} }, "relative"));

    try testing.expectEqual(@as(usize, 0), child_env.count());
}

test "initialize enables the experimental API and is followed by initialized" {
    const harness = try Harness.create(&[_]transport.FakeStream.Chunk{
        chunk(initialize_ok),
        chunk(account_ok),
        chunk(rate_limits_multi),
    });
    defer harness.destroy();

    const outcome = harness.refresh();
    try testing.expect(outcome.succeeded());
    try testing.expectEqual(domain.SnapshotStatus.fresh, outcome.status);
    try testing.expect(outcome.home_verified);
    try testing.expectEqual(codex.Stage.rate_limits_read, outcome.stage);
    try testing.expect(outcome.account_metadata.email_observed);
    try testing.expectEqualStrings(canary_email, outcome.account_metadata.email.?);
    try testing.expect(outcome.account_metadata.plan_observed);

    try testing.expect(outcome.account_metadata.plan_label == null);

    try expectMethodSequence(&harness.stream, &[_][]const u8{
        codex.method_initialize,
        codex.method_initialized,
        codex.method_account_read,
        codex.method_rate_limits_read,
    });

    var lines = harness.stream.writtenFrames();
    const initialize_line = lines.next().?;
    try testing.expect(std.mem.indexOf(u8, initialize_line, "\"experimentalApi\":true") != null);
    try testing.expect(std.mem.indexOf(u8, initialize_line, "\"clientInfo\"") != null);
    try testing.expect(std.mem.indexOf(u8, initialize_line, "\"id\":1") != null);

    const initialized_line = lines.next().?;

    try testing.expect(std.mem.indexOf(u8, initialized_line, "\"id\"") == null);

    try testing.expectEqual(@as(usize, 4), harness.stream.arm_count);
}

test "account metadata exposes official email and plan labels separately from usage" {
    const harness = try Harness.create(&[_]transport.FakeStream.Chunk{
        chunk(initialize_ok ++ account_pro ++ rate_limits_single),
    });
    defer harness.destroy();

    const outcome = harness.refresh();
    try testing.expect(outcome.succeeded());
    try testing.expectEqualStrings(canary_email, outcome.account_metadata.email.?);
    try testing.expectEqualStrings("Pro 20x", outcome.account_metadata.plan_label.?);
}

test "Codex plan labels retain plan names and expose Pro multipliers without inventing unknown plans" {
    const mappings = [_]struct { raw: []const u8, display: []const u8 }{
        .{ .raw = "free", .display = "Free" },
        .{ .raw = "go", .display = "Go" },
        .{ .raw = "plus", .display = "Plus" },
        .{ .raw = "pro", .display = "Pro 20x" },
        .{ .raw = "prolite", .display = "Pro 5x" },
        .{ .raw = "team", .display = "Team" },
        .{ .raw = "self_serve_business_usage_based", .display = "Business · usage based" },
        .{ .raw = "business", .display = "Business" },
        .{ .raw = "enterprise_cbp_usage_based", .display = "Enterprise · usage based" },
        .{ .raw = "enterprise", .display = "Enterprise" },
        .{ .raw = "edu", .display = "Edu" },
    };
    for (mappings) |mapping| {
        try testing.expectEqualStrings(mapping.display, codex.accountPlanLabel(mapping.raw).?);
    }
    try testing.expect(codex.accountPlanLabel("future-plan") == null);
}

test "account read never asks for a token refresh" {
    const harness = try Harness.create(&[_]transport.FakeStream.Chunk{
        chunk(initialize_ok ++ account_ok ++ rate_limits_single),
    });
    defer harness.destroy();

    _ = harness.refresh();
    try testing.expect(std.mem.indexOf(u8, harness.stream.writtenBytes(), "refreshToken") == null);
    try testing.expect(std.mem.indexOf(u8, harness.stream.writtenBytes(), "includeToken") == null);

    var lines = harness.stream.writtenFrames();
    _ = lines.next();
    _ = lines.next();
    const account_line = lines.next().?;
    try testing.expect(std.mem.indexOf(u8, account_line, "\"params\":{}") != null);
}

test "a mismatched codexHome stops the session before any account call" {
    const harness = try Harness.create(&[_]transport.FakeStream.Chunk{
        chunk(initialize_other_home ++ account_ok ++ rate_limits_multi),
    });
    defer harness.destroy();

    const outcome = harness.refresh();
    try testing.expect(!outcome.home_verified);
    try testing.expectEqual(codex.Stage.connected, outcome.stage);
    try testing.expectEqualStrings(codex.public_code_codex_home_mismatch, outcome.failure.?.public_code);
    try testing.expect(!outcome.failure.?.retryable);
    try testing.expectEqual(@as(usize, 0), outcome.windows.len);

    try expectMethodSequence(&harness.stream, &[_][]const u8{codex.method_initialize});
}

test "a missing codexHome is treated as a mismatch" {
    const harness = try Harness.create(&[_]transport.FakeStream.Chunk{chunk(initialize_no_home)});
    defer harness.destroy();

    const outcome = harness.refresh();
    try testing.expectEqualStrings(codex.public_code_codex_home_mismatch, outcome.failure.?.public_code);
    try testing.expectEqual(@as(usize, 1), writtenLineCount(&harness.stream));
}

test "an invalid configured home sends nothing" {
    const harness = try Harness.create(&[_]transport.FakeStream.Chunk{chunk(initialize_ok)});
    defer harness.destroy();

    const adapter: codex.Adapter = .{ .config = .{ .codex_home = "demo/relative" } };
    const outcome = adapter.refresh(&harness.connection, &harness.workspace, .{
        .account_id = account_id,
        .now_unix_s = fixture_now,
    });

    try testing.expectEqualStrings(codex.public_code_account_home_invalid, outcome.failure.?.public_code);
    try testing.expectEqual(@as(usize, 0), harness.stream.written_len);
    try testing.expectEqual(@as(usize, 0), harness.stream.arm_count);
}

test "a signed-out account becomes reauth required" {
    const harness = try Harness.create(&[_]transport.FakeStream.Chunk{
        chunk(initialize_ok ++ account_signed_out ++ rate_limits_multi),
    });
    defer harness.destroy();

    const outcome = harness.refresh();
    try testing.expectEqual(domain.SnapshotStatus.reauth_required, outcome.status);
    try testing.expectEqualStrings(codex.public_code_sign_in_required, outcome.failure.?.public_code);
    try testing.expectEqual(domain.RefreshErrorKind.authentication, outcome.failure.?.kind);
    try testing.expect(!outcome.failure.?.retryable);

    try expectMethodSequence(&harness.stream, &[_][]const u8{
        codex.method_initialize,
        codex.method_initialized,
        codex.method_account_read,
    });
}

test "notifications interleaved with the handshake do not disturb it" {
    const harness = try Harness.create(&[_]transport.FakeStream.Chunk{
        chunk(notification_account_updated),
        chunk(initialize_ok[0..30]),
        chunk(initialize_ok[30..]),
        chunk(notification_rate_limits_updated ++ server_request),
        chunk(account_ok),
        chunk(foreign_response),
        chunk(rate_limits_multi),
    });
    defer harness.destroy();

    const outcome = harness.refresh();
    try testing.expectEqual(domain.SnapshotStatus.fresh, outcome.status);
    try testing.expectEqual(@as(usize, 3), outcome.windows.len);
    try testing.expectEqual(@as(usize, 2), harness.connection.stats.notifications_skipped);
    try testing.expectEqual(@as(usize, 1), harness.connection.stats.server_requests_skipped);
    try testing.expectEqual(@as(usize, 1), harness.connection.stats.foreign_responses_skipped);
}

test "multi-window and per-limit responses normalize" {
    const harness = try Harness.create(&[_]transport.FakeStream.Chunk{
        chunk(initialize_ok ++ account_ok ++ rate_limits_multi),
    });
    defer harness.destroy();

    const outcome = harness.refresh();
    try testing.expectEqual(domain.SnapshotStatus.fresh, outcome.status);
    try testing.expectEqual(@as(usize, 3), outcome.windows.len);

    const session = windowOfKind(outcome.windows, .session).?;
    try testing.expectEqual(@as(u8, 24), session.used_percent);
    try testing.expectEqual(@as(?u32, 300), session.duration_minutes);
    try testing.expectEqual(@as(?i64, 2_000_003_600), session.reset_at_unix_s);
    try testing.expectEqualStrings("session", session.label);
    try testing.expect(session.model_label == null);

    const weekly = windowOfKind(outcome.windows, .weekly).?;
    try testing.expectEqual(@as(u8, 61), weekly.used_percent);
    try testing.expectEqual(@as(?u32, 10080), weekly.duration_minutes);

    const model = windowOfKind(outcome.windows, .model_scoped).?;
    try testing.expectEqual(@as(u8, 7), model.used_percent);
    try testing.expectEqualStrings("Demo Model", model.label);
    try testing.expectEqualStrings("Demo Model", model.model_label.?);

    const credits = outcome.reset_credits.?;
    try testing.expectEqual(@as(u32, 2), credits.authoritativeCount());
    try testing.expectEqual(domain.CreditDetailStatus.detailed, credits.detail_status);
    try testing.expectEqual(@as(usize, 2), credits.details.len);
    try testing.expect(credits.detailsAreComplete());
    try testing.expectEqualStrings("credit-demo-a", credits.details[0].id);
    try testing.expectEqualStrings("Weekly reset", credits.details[0].label);
    try testing.expectEqual(@as(?i64, 2_000_600_000), credits.details[0].expires_at_unix_s);
    try testing.expect(credits.details[1].expires_at_unix_s == null);
}

test "single-window responses normalize" {
    const harness = try Harness.create(&[_]transport.FakeStream.Chunk{
        chunk(initialize_ok ++ account_ok ++ rate_limits_single),
    });
    defer harness.destroy();

    const outcome = harness.refresh();
    try testing.expectEqual(domain.SnapshotStatus.fresh, outcome.status);
    try testing.expectEqual(@as(usize, 1), outcome.windows.len);
    try testing.expectEqual(domain.UsageWindowKind.session, outcome.windows[0].kind);
    try testing.expectEqual(@as(u8, 10), outcome.windows[0].used_percent);

    try testing.expect(outcome.windows[0].reset_at_unix_s == null);
    try testing.expect(outcome.windows[0].duration_minutes == null);
    try testing.expect(outcome.reset_credits == null);
}

test "out-of-range usage values are clamped and impossible resets dropped" {
    const harness = try Harness.create(&[_]transport.FakeStream.Chunk{
        chunk(initialize_ok ++ account_ok ++ rate_limits_clamped),
    });
    defer harness.destroy();

    const outcome = harness.refresh();
    try testing.expectEqual(@as(usize, 2), outcome.windows.len);
    try testing.expectEqual(@as(u8, 100), outcome.windows[0].used_percent);
    try testing.expectEqual(@as(u8, 0), outcome.windows[1].used_percent);

    try testing.expect(outcome.windows[0].reset_at_unix_s == null);
    try testing.expect(outcome.windows[1].reset_at_unix_s == null);

    for (outcome.windows) |window| try testing.expect(window.used_percent <= 100);
}

test "numbers no integer can hold are not numbers" {
    const harness = try Harness.create(&[_]transport.FakeStream.Chunk{
        chunk(initialize_ok ++ account_ok ++ rate_limits_absurd_numbers),
    });
    defer harness.destroy();

    const outcome = harness.refresh();
    try testing.expectEqual(@as(usize, 2), outcome.windows.len);
    for (outcome.windows) |window| {
        try testing.expectEqual(@as(u8, 50), window.used_percent);
        try testing.expect(window.duration_minutes == null);
        try testing.expect(window.reset_at_unix_s == null);
    }

    try testing.expect(outcome.reset_credits == null);

    try testing.expectEqual(domain.UsageWindowKind.session, outcome.windows[0].kind);
    try testing.expectEqual(domain.UsageWindowKind.weekly, outcome.windows[1].kind);
}

test "a window without a usage percent is dropped and the reading is incomplete" {
    const harness = try Harness.create(&[_]transport.FakeStream.Chunk{
        chunk(initialize_ok ++ account_ok ++ rate_limits_malformed_window),
    });
    defer harness.destroy();

    const outcome = harness.refresh();
    try testing.expectEqual(domain.SnapshotStatus.partial, outcome.status);
    try testing.expectEqualStrings(codex.public_code_usage_incomplete, outcome.failure.?.public_code);
    try testing.expect(outcome.failure.?.retryable);

    try testing.expectEqual(@as(usize, 1), outcome.windows.len);
    try testing.expectEqual(@as(u8, 12), outcome.windows[0].used_percent);
}

test "a response with nothing usable is reported, not invented" {
    const harness = try Harness.create(&[_]transport.FakeStream.Chunk{
        chunk(initialize_ok ++ account_ok ++ rate_limits_empty),
    });
    defer harness.destroy();

    const outcome = harness.refresh();
    try testing.expectEqual(domain.SnapshotStatus.partial, outcome.status);
    try testing.expectEqualStrings(codex.public_code_usage_unsupported, outcome.failure.?.public_code);
    try testing.expectEqual(@as(usize, 0), outcome.windows.len);
    try testing.expect(outcome.reset_credits == null);
}

test "count-only credits keep the authoritative count" {
    const harness = try Harness.create(&[_]transport.FakeStream.Chunk{
        chunk(initialize_ok ++ account_ok ++ rate_limits_count_only),
    });
    defer harness.destroy();

    const outcome = harness.refresh();
    const credits = outcome.reset_credits.?;
    try testing.expectEqual(domain.SnapshotStatus.fresh, outcome.status);
    try testing.expectEqual(domain.CreditDetailStatus.count_only, credits.detail_status);
    try testing.expectEqual(@as(u32, 3), credits.authoritativeCount());
    try testing.expectEqual(@as(usize, 0), credits.details.len);

    try testing.expect(!credits.detailsAreComplete());
    try testing.expectEqual(@as(usize, 0), credits.knownUnexpiredDetailCount(fixture_now));
}

test "detailed credits are capped by the authoritative count" {
    const harness = try Harness.create(&[_]transport.FakeStream.Chunk{
        chunk(initialize_ok ++ account_ok ++ rate_limits_capped_details),
    });
    defer harness.destroy();

    const outcome = harness.refresh();
    const credits = outcome.reset_credits.?;
    try testing.expectEqual(@as(u32, 1), credits.authoritativeCount());
    try testing.expectEqual(@as(usize, 1), credits.details.len);

    try testing.expectEqual(domain.SnapshotStatus.fresh, outcome.status);
    try testing.expect(outcome.failure == null);
    try testing.expectEqual(@as(usize, 1), harness.workspace.capped_details);
    try testing.expectEqual(@as(usize, 0), harness.workspace.dropped_details);

    const document: store.SnapshotDocument = .{
        .profiles = &.{},
        .snapshots = &.{outcome.snapshot(.{ .account_id = account_id, .now_unix_s = fixture_now })},
    };

    try store.validateSnapshotDocument(document);
}

test "credits without an id are dropped and reported as incomplete" {
    const harness = try Harness.create(&[_]transport.FakeStream.Chunk{
        chunk(initialize_ok ++ account_ok ++ rate_limits_unusable_credit),
    });
    defer harness.destroy();

    const outcome = harness.refresh();
    const credits = outcome.reset_credits.?;

    try testing.expectEqual(@as(u32, 2), credits.authoritativeCount());
    try testing.expectEqual(@as(usize, 1), credits.details.len);
    try testing.expect(!credits.detailsAreComplete());
    try testing.expectEqual(domain.SnapshotStatus.partial, outcome.status);
    try testing.expectEqualStrings(codex.public_code_usage_incomplete, outcome.failure.?.public_code);
}

test "a missing availableCount produces no summary" {
    const harness = try Harness.create(&[_]transport.FakeStream.Chunk{
        chunk(initialize_ok ++ account_ok ++ rate_limits_no_count),
    });
    defer harness.destroy();

    const outcome = harness.refresh();

    try testing.expect(outcome.reset_credits == null);
    try testing.expectEqual(domain.SnapshotStatus.partial, outcome.status);
    try testing.expectEqualStrings(codex.public_code_usage_incomplete, outcome.failure.?.public_code);
}

test "JSON-RPC error codes map to sanitized states" {
    const cases = [_]struct {
        script: []const u8,
        public_code: []const u8,
        kind: domain.RefreshErrorKind,
        retryable: bool,
    }{
        .{ .script = script_rpc_method_not_found, .public_code = codex.public_code_app_server_unsupported, .kind = .provider_unavailable, .retryable = false },
        .{ .script = script_rpc_invalid_params, .public_code = codex.public_code_rejected, .kind = .unknown, .retryable = false },
        .{ .script = script_rpc_parse_error, .public_code = codex.public_code_rejected, .kind = .unknown, .retryable = false },
        .{ .script = script_rpc_internal_error, .public_code = codex.public_code_app_server_unavailable, .kind = .provider_unavailable, .retryable = true },
        .{ .script = script_rpc_server_error, .public_code = codex.public_code_app_server_unavailable, .kind = .provider_unavailable, .retryable = true },
    };

    for (cases) |case| {
        const harness = try Harness.create(&[_]transport.FakeStream.Chunk{chunk(case.script)});
        defer harness.destroy();

        const outcome = harness.refresh();
        const failure = outcome.failure.?;
        try testing.expectEqualStrings(case.public_code, failure.public_code);
        try testing.expectEqual(case.kind, failure.kind);
        try testing.expectEqual(case.retryable, failure.retryable);

        try expectNoCanaries(failure.public_code);
        try testing.expect(codex.isPublicCode(failure.public_code));
    }
}

test "a malformed response is an error state, not a guess" {
    const harness = try Harness.create(&[_]transport.FakeStream.Chunk{
        chunk(initialize_ok ++ account_ok ++ "{\"jsonrpc\":\"2.0\",\"id\":3,\"result\"\n"),
    });
    defer harness.destroy();

    const outcome = harness.refresh();
    try testing.expectEqual(domain.SnapshotStatus.error_state, outcome.status);
    try testing.expectEqualStrings(codex.public_code_malformed, outcome.failure.?.public_code);
    try testing.expectEqual(@as(usize, 0), outcome.windows.len);

    const empty = try Harness.create(&[_]transport.FakeStream.Chunk{
        chunk(initialize_ok ++ account_ok ++ "{\"jsonrpc\":\"2.0\",\"id\":3}\n"),
    });
    defer empty.destroy();
    const empty_outcome = empty.refresh();

    try testing.expectEqualStrings(codex.public_code_malformed, empty_outcome.failure.?.public_code);
}

test "transport failures map to sanitized, preserving states" {
    const cases = [_]struct {
        failure: transport.TransportError,
        public_code: []const u8,
        kind: domain.RefreshErrorKind,
        status: domain.SnapshotStatus,
    }{
        .{ .failure = error.Timeout, .public_code = codex.public_code_timeout, .kind = .timeout, .status = .unavailable },
        .{ .failure = error.EndOfStream, .public_code = codex.public_code_app_server_closed, .kind = .provider_unavailable, .status = .unavailable },
        .{ .failure = error.Io, .public_code = codex.public_code_app_server_closed, .kind = .provider_unavailable, .status = .unavailable },
        .{ .failure = error.FrameTooLarge, .public_code = codex.public_code_malformed, .kind = .malformed_response, .status = .error_state },
        .{ .failure = error.Canceled, .public_code = codex.public_code_canceled, .kind = .unknown, .status = .unavailable },
    };

    for (cases) |case| {
        const harness = try Harness.create(&[_]transport.FakeStream.Chunk{
            chunk(initialize_ok ++ account_ok),
            .{ .failure = case.failure },
        });
        defer harness.destroy();

        const outcome = harness.refresh();
        try testing.expectEqualStrings(case.public_code, outcome.failure.?.public_code);
        try testing.expectEqual(case.kind, outcome.failure.?.kind);
        try testing.expectEqual(case.status, outcome.status);
        try testing.expectEqual(codex.Stage.account_read, outcome.stage);
        try testing.expect(codex.isPublicCode(outcome.failure.?.public_code));
    }
}

test "a failed refresh preserves the last success" {
    const previous_windows = [_]domain.UsageWindow{.{
        .kind = .session,
        .label = "session",
        .used_percent = 42,
        .reset_at_unix_s = fixture_now + 600,
    }};
    const previous: domain.UsageSnapshot = .{
        .account_id = account_id,
        .provider = .codex,
        .captured_at_unix_s = fixture_now - 300,
        .status = .fresh,
        .windows = &previous_windows,
        .reset_credits = .{
            .available_count = 2,
            .observed_at_unix_s = fixture_now - 300,
            .detail_status = .count_only,
        },
    };

    const harness = try Harness.create(&[_]transport.FakeStream.Chunk{
        chunk(initialize_ok),
        .{ .failure = error.Timeout },
    });
    defer harness.destroy();

    const request: codex.RefreshRequest = .{ .account_id = account_id, .now_unix_s = fixture_now };
    const outcome = harness.adapter().refresh(&harness.connection, &harness.workspace, request);
    const snapshot = outcome.snapshotPreservingLastSuccess(request, previous);

    try testing.expectEqual(domain.SnapshotStatus.stale, snapshot.status);

    try testing.expectEqual(previous.captured_at_unix_s, snapshot.captured_at_unix_s);
    try testing.expectEqual(@as(usize, 1), snapshot.windows.len);
    try testing.expectEqual(@as(u8, 42), snapshot.windows[0].used_percent);
    try testing.expectEqual(@as(u32, 2), snapshot.reset_credits.?.available_count);
    try testing.expectEqualStrings(codex.public_code_timeout, snapshot.refresh_error.?.public_code);

    const first_ever = outcome.snapshotPreservingLastSuccess(request, null);
    try testing.expectEqual(domain.SnapshotStatus.unavailable, first_ever.status);
    try testing.expectEqual(@as(usize, 0), first_ever.windows.len);
    try testing.expectEqual(fixture_now, first_ever.captured_at_unix_s);
}

test "an authentication failure preserves data and asks for sign-in" {
    const previous_windows = [_]domain.UsageWindow{.{ .kind = .weekly, .label = "weekly", .used_percent = 88 }};
    const previous: domain.UsageSnapshot = .{
        .account_id = account_id,
        .provider = .codex,
        .captured_at_unix_s = fixture_now - 60,
        .status = .fresh,
        .windows = &previous_windows,
    };

    const harness = try Harness.create(&[_]transport.FakeStream.Chunk{
        chunk(initialize_ok ++ account_signed_out),
    });
    defer harness.destroy();

    const request: codex.RefreshRequest = .{ .account_id = account_id, .now_unix_s = fixture_now };
    const outcome = harness.adapter().refresh(&harness.connection, &harness.workspace, request);
    const snapshot = outcome.snapshotPreservingLastSuccess(request, previous);

    try testing.expectEqual(domain.SnapshotStatus.reauth_required, snapshot.status);
    try testing.expectEqual(@as(usize, 1), snapshot.windows.len);
    try testing.expectEqualStrings(codex.public_code_sign_in_required, snapshot.refresh_error.?.public_code);
}

test "a partial reading replaces the previous one instead of preserving it" {
    const previous_windows = [_]domain.UsageWindow{.{ .kind = .weekly, .label = "weekly", .used_percent = 88 }};
    const previous: domain.UsageSnapshot = .{
        .account_id = account_id,
        .provider = .codex,
        .captured_at_unix_s = fixture_now - 60,
        .status = .fresh,
        .windows = &previous_windows,
    };

    const harness = try Harness.create(&[_]transport.FakeStream.Chunk{
        chunk(initialize_ok ++ account_ok ++ rate_limits_malformed_window),
    });
    defer harness.destroy();

    const request: codex.RefreshRequest = .{ .account_id = account_id, .now_unix_s = fixture_now };
    const outcome = harness.adapter().refresh(&harness.connection, &harness.workspace, request);
    const snapshot = outcome.snapshotPreservingLastSuccess(request, previous);

    try testing.expectEqual(domain.SnapshotStatus.partial, snapshot.status);
    try testing.expectEqual(fixture_now, snapshot.captured_at_unix_s);
    try testing.expectEqual(@as(u8, 12), snapshot.windows[0].used_percent);
}

fn submittedAttempt(credit_id: ?[]const u8) domain.ResetAttempt {
    var attempt = domain.ResetAttempt.init(
        "attempt-demo-0001",
        account_id,
        credit_id,
        fixture_now - 10,
        2,
        fixture_now - 5,
    ) catch unreachable;
    attempt.markSubmitted(fixture_now, codex.default_max_preflight_age_s) catch unreachable;
    return attempt;
}

fn consumeRequest(attempt: *const domain.ResetAttempt, credit_id: ?[]const u8) codex.ConsumeRequest {
    return .{
        .account_id = account_id,
        .attempt = attempt,
        .credit_id = credit_id,
        .now_unix_s = fixture_now,
    };
}

test "every reset outcome maps to its domain outcome" {
    for (script_consume_reset_outcomes) |case| {
        const harness = try Harness.create(&[_]transport.FakeStream.Chunk{chunk(case.script)});
        defer harness.destroy();

        const attempt = submittedAttempt(null);
        const outcome = harness.adapter().consumeResetCredit(
            &harness.connection,
            &harness.workspace,
            consumeRequest(&attempt, null),
        );
        try testing.expectEqual(case.outcome, outcome.completed);
        try testing.expect(outcome.requestWasSent());
        try testing.expect(outcome.failure() == null);
    }

    try testing.expect(codex.resetOutcomeFromText("resets") == null);
    try testing.expect(codex.resetOutcomeFromText("RESET") == null);
    try testing.expectEqual(domain.ResetOutcome.reset, codex.resetOutcomeFromText("reset").?);
}

test "the consume carries the caller's key and omits an absent credit id" {
    const harness = try Harness.create(&[_]transport.FakeStream.Chunk{
        chunk(script_consume_reset),
    });
    defer harness.destroy();

    const attempt = submittedAttempt(null);
    _ = harness.adapter().consumeResetCredit(&harness.connection, &harness.workspace, consumeRequest(&attempt, null));

    try expectMethodSequence(&harness.stream, &[_][]const u8{
        codex.method_initialize,
        codex.method_initialized,
        codex.method_reset_credit_consume,
    });

    var lines = harness.stream.writtenFrames();
    _ = lines.next();
    _ = lines.next();
    const consume_line = lines.next().?;
    try testing.expect(std.mem.indexOf(u8, consume_line, "\"idempotencyKey\":\"attempt-demo-0001\"") != null);
    try testing.expect(std.mem.indexOf(u8, consume_line, "creditId") == null);
}

test "a selected credit id is sent exactly as the attempt recorded it" {
    const harness = try Harness.create(&[_]transport.FakeStream.Chunk{
        chunk(script_consume_reset),
    });
    defer harness.destroy();

    const attempt = submittedAttempt("credit-demo-a");
    const outcome = harness.adapter().consumeResetCredit(
        &harness.connection,
        &harness.workspace,
        consumeRequest(&attempt, "credit-demo-a"),
    );
    try testing.expectEqual(domain.ResetOutcome.reset, outcome.completed);
    try testing.expect(std.mem.indexOf(u8, harness.stream.writtenBytes(), "\"creditId\":\"credit-demo-a\"") != null);
}

test "an unconfirmed, stale, or exhausted attempt sends nothing" {
    const Case = struct { name: []const u8, attempt: domain.ResetAttempt, now: i64, code: []const u8 };

    const prepared = domain.ResetAttempt.init("attempt-demo-0002", account_id, null, fixture_now - 10, 2, fixture_now - 5) catch unreachable;
    var completed = submittedAttempt(null);
    completed.complete(.reset, fixture_now) catch unreachable;
    var empty_key = submittedAttempt(null);
    empty_key.idempotency_key = "";
    var control_key = submittedAttempt(null);
    control_key.idempotency_key = "attempt\ndemo";
    var zero_credits = submittedAttempt(null);
    zero_credits.preflight_available_count = 0;

    const cases = [_]Case{
        .{ .name = "prepared", .attempt = prepared, .now = fixture_now, .code = codex.public_code_reset_unconfirmed },

        .{ .name = "completed", .attempt = completed, .now = fixture_now, .code = codex.public_code_reset_unconfirmed },

        .{ .name = "stale", .attempt = submittedAttempt(null), .now = fixture_now + 10_000, .code = codex.public_code_reset_unconfirmed },

        .{ .name = "no credits", .attempt = zero_credits, .now = fixture_now, .code = codex.public_code_reset_unconfirmed },
        .{ .name = "empty key", .attempt = empty_key, .now = fixture_now, .code = codex.public_code_reset_key_invalid },
        .{ .name = "control character key", .attempt = control_key, .now = fixture_now, .code = codex.public_code_reset_key_invalid },
    };

    for (cases) |case| {
        const harness = try Harness.create(&[_]transport.FakeStream.Chunk{
            chunk(script_consume_reset),
        });
        defer harness.destroy();

        const outcome = harness.adapter().consumeResetCredit(&harness.connection, &harness.workspace, .{
            .account_id = account_id,
            .attempt = &case.attempt,
            .credit_id = null,
            .now_unix_s = case.now,
        });

        try testing.expect(!outcome.requestWasSent());
        try testing.expectEqualStrings(case.code, outcome.rejected.public_code);

        try testing.expectEqual(@as(usize, 0), harness.stream.written_len);
        try testing.expectEqual(@as(usize, 0), harness.stream.arm_count);
    }
}

test "an attempt for another account or another credit sends nothing" {
    const attempt = submittedAttempt("credit-demo-a");

    const wrong_account = try Harness.create(&[_]transport.FakeStream.Chunk{chunk(initialize_ok)});
    defer wrong_account.destroy();
    const account_outcome = wrong_account.adapter().consumeResetCredit(
        &wrong_account.connection,
        &wrong_account.workspace,
        .{ .account_id = "acct-codex-other", .attempt = &attempt, .credit_id = "credit-demo-a", .now_unix_s = fixture_now },
    );
    try testing.expect(!account_outcome.requestWasSent());
    try testing.expectEqualStrings(codex.public_code_reset_unconfirmed, account_outcome.rejected.public_code);
    try testing.expectEqual(@as(usize, 0), wrong_account.stream.written_len);

    const wrong_credit = try Harness.create(&[_]transport.FakeStream.Chunk{chunk(initialize_ok)});
    defer wrong_credit.destroy();
    const credit_outcome = wrong_credit.adapter().consumeResetCredit(
        &wrong_credit.connection,
        &wrong_credit.workspace,
        consumeRequest(&attempt, "credit-demo-b"),
    );
    try testing.expect(!credit_outcome.requestWasSent());
    try testing.expectEqual(@as(usize, 0), wrong_credit.stream.written_len);

    const dropped_credit = try Harness.create(&[_]transport.FakeStream.Chunk{chunk(initialize_ok)});
    defer dropped_credit.destroy();
    const dropped_outcome = dropped_credit.adapter().consumeResetCredit(
        &dropped_credit.connection,
        &dropped_credit.workspace,
        consumeRequest(&attempt, null),
    );
    try testing.expect(!dropped_outcome.requestWasSent());
    try testing.expectEqual(@as(usize, 0), dropped_credit.stream.written_len);
}

test "a lost consume response is unknown, and a retry reuses the same key" {
    const first = try Harness.create(&[_]transport.FakeStream.Chunk{
        chunk(initialize_ok),
        .{ .failure = error.Timeout },
    });
    defer first.destroy();

    const attempt = submittedAttempt(null);
    const outcome = first.adapter().consumeResetCredit(&first.connection, &first.workspace, consumeRequest(&attempt, null));

    try testing.expect(outcome.requestWasSent());
    try testing.expectEqualStrings(codex.public_code_reset_outcome_unknown, outcome.ambiguous.public_code);

    try testing.expect(!outcome.ambiguous.retryable);
    try testing.expect(std.mem.indexOf(u8, first.stream.writtenBytes(), "attempt-demo-0001") != null);

    var ambiguous = attempt;
    try ambiguous.markAmbiguous(fixture_now + 1);
    const second = try Harness.create(&[_]transport.FakeStream.Chunk{
        chunk(script_consume_already_redeemed),
    });
    defer second.destroy();

    var retry = consumeRequest(&attempt, null);
    retry.now_unix_s = fixture_now + 5;
    const retry_outcome = second.adapter().consumeResetCredit(&second.connection, &second.workspace, retry);
    try testing.expectEqual(domain.ResetOutcome.already_redeemed, retry_outcome.completed);

    var first_key: []const u8 = undefined;
    var second_key: []const u8 = undefined;
    first_key = keyFrom(first.stream.writtenBytes()).?;
    second_key = keyFrom(second.stream.writtenBytes()).?;
    try testing.expectEqualStrings(first_key, second_key);
    try testing.expectEqualStrings(attempt.idempotency_key, second_key);
}

fn keyFrom(written: []const u8) ?[]const u8 {
    const marker = "\"idempotencyKey\":\"";
    const start = std.mem.indexOf(u8, written, marker) orelse return null;
    const rest = written[start + marker.len ..];
    const end = std.mem.indexOfScalar(u8, rest, '"') orelse return null;
    return rest[0..end];
}

test "an unknown outcome string is not guessed" {
    const harness = try Harness.create(&[_]transport.FakeStream.Chunk{
        chunk(script_consume_unknown_outcome),
    });
    defer harness.destroy();

    const attempt = submittedAttempt(null);
    const outcome = harness.adapter().consumeResetCredit(&harness.connection, &harness.workspace, consumeRequest(&attempt, null));
    try testing.expectEqualStrings(codex.public_code_reset_outcome_unknown, outcome.ambiguous.public_code);
    try testing.expect(outcome.requestWasSent());

    const missing = try Harness.create(&[_]transport.FakeStream.Chunk{
        chunk(script_consume_no_outcome),
    });
    defer missing.destroy();
    const missing_outcome = missing.adapter().consumeResetCredit(&missing.connection, &missing.workspace, consumeRequest(&attempt, null));
    try testing.expectEqualStrings(codex.public_code_reset_outcome_unknown, missing_outcome.ambiguous.public_code);
}

test "routing errors prove the consume never ran" {
    const not_routed = try Harness.create(&[_]transport.FakeStream.Chunk{
        chunk(script_consume_not_routed),
    });
    defer not_routed.destroy();

    const attempt = submittedAttempt(null);
    const rejected = not_routed.adapter().consumeResetCredit(&not_routed.connection, &not_routed.workspace, consumeRequest(&attempt, null));
    try testing.expect(!rejected.requestWasSent());
    try testing.expectEqualStrings(codex.public_code_app_server_unsupported, rejected.rejected.public_code);

    const maybe_ran = try Harness.create(&[_]transport.FakeStream.Chunk{
        chunk(script_consume_internal_error),
    });
    defer maybe_ran.destroy();
    const ambiguous = maybe_ran.adapter().consumeResetCredit(&maybe_ran.connection, &maybe_ran.workspace, consumeRequest(&attempt, null));
    try testing.expectEqualStrings(codex.public_code_reset_outcome_unknown, ambiguous.ambiguous.public_code);
}

test "a home mismatch blocks the consume before it is written" {
    const harness = try Harness.create(&[_]transport.FakeStream.Chunk{
        chunk(script_consume_wrong_home),
    });
    defer harness.destroy();

    const attempt = submittedAttempt(null);
    const outcome = harness.adapter().consumeResetCredit(&harness.connection, &harness.workspace, consumeRequest(&attempt, null));
    try testing.expect(!outcome.requestWasSent());
    try testing.expectEqualStrings(codex.public_code_codex_home_mismatch, outcome.rejected.public_code);
    try expectMethodSequence(&harness.stream, &[_][]const u8{codex.method_initialize});
}

test "the adapter never mutates the caller's attempt" {
    const harness = try Harness.create(&[_]transport.FakeStream.Chunk{
        chunk(script_consume_reset),
    });
    defer harness.destroy();

    const attempt = submittedAttempt("credit-demo-a");
    const before = attempt;
    _ = harness.adapter().consumeResetCredit(&harness.connection, &harness.workspace, consumeRequest(&attempt, "credit-demo-a"));

    try testing.expectEqual(before.phase, attempt.phase);
    try testing.expectEqual(before.updated_at_unix_s, attempt.updated_at_unix_s);
    try testing.expect(attempt.outcome == null);
    try testing.expectEqualStrings(before.idempotency_key, attempt.idempotency_key);
}

test "normalized snapshots satisfy the persistence contract and carry no account text" {
    const harness = try Harness.create(&[_]transport.FakeStream.Chunk{
        chunk(initialize_ok ++ account_ok ++ rate_limits_multi),
    });
    defer harness.destroy();

    const request: codex.RefreshRequest = .{ .account_id = account_id, .now_unix_s = fixture_now };
    const outcome = harness.adapter().refresh(&harness.connection, &harness.workspace, request);
    const snapshot = outcome.snapshot(request);

    const snapshots = [_]domain.UsageSnapshot{snapshot};
    const document: store.SnapshotDocument = .{ .profiles = &.{}, .snapshots = &snapshots };
    try store.validateSnapshotDocument(document);

    const bytes = try store.encode(testing.allocator, document);
    defer testing.allocator.free(bytes);

    try expectNoCanaries(bytes);
    for ([_][]const u8{ "access_token", "refresh_token", "authorization", "bearer ", "codexHome", account_home }) |needle| {
        try testing.expect(std.mem.indexOf(u8, bytes, needle) == null);
    }
}

test "written frames never carry account identity or a token request" {
    const harness = try Harness.create(&[_]transport.FakeStream.Chunk{
        chunk(initialize_ok ++ account_ok ++ rate_limits_multi),
    });
    defer harness.destroy();

    _ = harness.refresh();
    const written = harness.stream.writtenBytes();
    try expectNoCanaries(written);
    for ([_][]const u8{ "refreshToken", "includeToken", "accessToken", "apiKey", "authorization" }) |needle| {
        try testing.expect(std.mem.indexOf(u8, written, needle) == null);
    }

    try testing.expect(std.mem.endsWith(u8, written, "\n"));
    try testing.expect(std.mem.indexOf(u8, written, "\n\n") == null);
}

test "every public code is known, lowercase, and free of provider text" {
    for (codex.public_codes) |code| {
        try testing.expect(code.len != 0);
        try testing.expect(codex.isPublicCode(code));
        try expectNoCanaries(code);
        for (code) |byte| {
            const is_lower = byte >= 'a' and byte <= 'z';
            try testing.expect(is_lower or byte == '-');
        }
    }
    try testing.expect(!codex.isPublicCode("provider-said-no"));

    const failures = [_]transport.TransportError{
        error.Timeout,         error.EndOfStream,   error.Io,
        error.MalformedFrame,  error.FrameTooLarge, error.TooManyFrames,
        error.RequestTooLarge, error.SpawnFailed,   error.Unsupported,
        error.Canceled,
    };
    for (failures) |failure| {
        try testing.expect(codex.isPublicCode(codex.refreshErrorFromTransport(failure).public_code));
    }
    for ([_]i64{ -32700, -32600, -32601, -32602, -32603, -32000, 0, 12345 }) |code| {
        try testing.expect(codex.isPublicCode(codex.refreshErrorFromRpcCode(code).public_code));
    }
}

test "neither module logs, mutates the process environment, or hardcodes a home" {
    const sources = [_][]const u8{
        @embedFile("../process_jsonl.zig"),
        @embedFile("../providers/codex.zig"),
    };

    const forbidden = [_][]const u8{
        "std.log",
        "std.debug.print",
        "setenv",
        "putenv",
        "/Users/",
        "getEnvVarOwned",
    };
    for (sources) |source| {
        for (forbidden) |needle| {
            try testing.expect(std.mem.indexOf(u8, source, needle) == null);
        }
    }
}

test "declarations stay analyzable" {
    testing.refAllDecls(transport);
    testing.refAllDecls(codex);
}

test "the live child transport is compiled but never run here" {
    _ = &transport.ChildTransport.spawn;
    _ = &transport.ChildTransport.stream;
    _ = &transport.ChildTransport.close;
    _ = &transport.runBounded;
    _ = &codex.appServerArgv;

    const argv = codex.appServerArgv("/demo/bin/codex");
    try testing.expectEqualStrings("/demo/bin/codex", argv[0]);
    try testing.expectEqualStrings(codex.app_server_subcommand, argv[1]);
}
