const std = @import("std");
const domain = @import("../domain.zig");
const keychain = @import("../keychain.zig");
const oauth = @import("../oauth.zig");

const default_timeout_ms = oauth.default_timeout_ms;
const max_timeout_ms = oauth.max_timeout_ms;
const max_url_bytes = oauth.max_url_bytes;
const max_request_body_bytes = oauth.max_request_body_bytes;
const max_response_body_bytes = oauth.max_response_body_bytes;
const max_redacted_target_bytes = oauth.max_redacted_target_bytes;
const max_json_depth = oauth.max_json_depth;
const max_json_key_bytes = oauth.max_json_key_bytes;
const default_refresh_skew_s = oauth.default_refresh_skew_s;
const max_refresh_skew_s = oauth.max_refresh_skew_s;
const Method = oauth.Method;
const Header = oauth.Header;
const Request = oauth.Request;
const RedactedRequest = oauth.RedactedRequest;
const TransportError = oauth.TransportError;
const unwiredClient = oauth.unwiredClient;
const FakeHttpClient = oauth.FakeHttpClient;
const max_retry_after_text_bytes = oauth.max_retry_after_text_bytes;
const max_retry_after_s = oauth.max_retry_after_s;
const RetryAfterHeader = oauth.RetryAfterHeader;
const ExchangeResult = oauth.ExchangeResult;
const Exchange = oauth.Exchange;
const HttpTransport = oauth.HttpTransport;
const runBounded = oauth.runBounded;
const TlsExchange = oauth.TlsExchange;
const TlsTransport = oauth.TlsTransport;
const RefreshTrigger = oauth.RefreshTrigger;
const CredentialWindow = oauth.CredentialWindow;
const ExpiryDecision = oauth.ExpiryDecision;
const clampSkew = oauth.clampSkew;
const evaluateExpiry = oauth.evaluateExpiry;
const expiresAtUnix = oauth.expiresAtUnix;
const planRefresh = oauth.planRefresh;
const buildRefreshRequest = oauth.buildRefreshRequest;
const RefreshPayload = oauth.RefreshPayload;
const TokenType = oauth.TokenType;
const parseRefreshResponse = oauth.parseRefreshResponse;
const OAuthErrorCode = oauth.OAuthErrorCode;
const parseErrorCode = oauth.parseErrorCode;
const public_code_sign_in_required = oauth.public_code_sign_in_required;
const public_code_access_denied = oauth.public_code_access_denied;
const public_code_rate_limited = oauth.public_code_rate_limited;
const public_code_timeout = oauth.public_code_timeout;
const public_code_network = oauth.public_code_network;
const public_code_rejected = oauth.public_code_rejected;
const public_code_malformed = oauth.public_code_malformed;
const public_code_provider_unavailable = oauth.public_code_provider_unavailable;
const public_code_canceled = oauth.public_code_canceled;
const public_code_store_unavailable = oauth.public_code_store_unavailable;
const public_code_store_repair_required = oauth.public_code_store_repair_required;
const public_code_store_denied = oauth.public_code_store_denied;
const public_code_store_corrupt = oauth.public_code_store_corrupt;
const public_code_store_full = oauth.public_code_store_full;
const public_code_store_io = oauth.public_code_store_io;
const public_codes = oauth.public_codes;
const isPublicCode = oauth.isPublicCode;
const refreshErrorFromStatus = oauth.refreshErrorFromStatus;
const refreshErrorFromTransport = oauth.refreshErrorFromTransport;
const refreshErrorFromParse = oauth.refreshErrorFromParse;
const refreshErrorFromStore = oauth.refreshErrorFromStore;
const refreshErrorFromBuild = oauth.refreshErrorFromBuild;
const RotationOutcome = oauth.RotationOutcome;
const rotateRefreshCredential = oauth.rotateRefreshCredential;
const RecoveryOutcome = oauth.RecoveryOutcome;
const recoverStagedRotation = oauth.recoverStagedRotation;
const applyRefreshPayload = oauth.applyRefreshPayload;

const form_headers = [_]Header{
    .{ .name = "content-type", .value = "application/x-www-form-urlencoded" },
    .{ .name = "accept", .value = "application/json" },
};

const testing = std.testing;

const test_token_url = "https://token.example.invalid/v1/token";
const test_client_id = "demo-client-0000";
const test_refresh_placeholder = "demo-refresh-placeholder-0000";
const test_access_placeholder = "demo-access-placeholder-1111";
const test_rotated_placeholder = "demo-rotated-placeholder-2222";

fn demoAccount() keychain.AccountKey {
    return keychain.AccountKey.init("claude-demo") catch unreachable;
}

fn formatted(buffer: []u8, value: anytype) []const u8 {
    var writer = std.Io.Writer.fixed(buffer);
    writer.print("{f}", .{value}) catch unreachable;
    return writer.buffered();
}

test "refresh trigger has no automatic variant" {
    const fields = @typeInfo(RefreshTrigger).@"enum".fields;
    try testing.expectEqual(@as(usize, 1), fields.len);
    try testing.expectEqualStrings("user_requested", fields[0].name);
}

test "expiry decision refreshes when missing, unknown, past, or near" {
    const now: i64 = 2_000_000_000;
    const skew = default_refresh_skew_s;

    try testing.expectEqual(ExpiryDecision.refresh_missing_credential, evaluateExpiry(.{}, now, skew));
    try testing.expectEqual(ExpiryDecision.refresh_unknown_expiry, evaluateExpiry(
        .{ .has_access_credential = true },
        now,
        skew,
    ));
    try testing.expectEqual(ExpiryDecision.refresh_expired, evaluateExpiry(
        .{ .has_access_credential = true, .access_expires_at_unix_s = now },
        now,
        skew,
    ));
    try testing.expectEqual(ExpiryDecision.refresh_near_expiry, evaluateExpiry(
        .{ .has_access_credential = true, .access_expires_at_unix_s = now + skew },
        now,
        skew,
    ));
    try testing.expectEqual(ExpiryDecision.usable, evaluateExpiry(
        .{ .has_access_credential = true, .access_expires_at_unix_s = now + skew + 1 },
        now,
        skew,
    ));

    try testing.expectEqual(@as(i64, 0), clampSkew(-30));
    try testing.expectEqual(max_refresh_skew_s, clampSkew(max_refresh_skew_s * 10));
    try testing.expectEqual(ExpiryDecision.usable, evaluateExpiry(
        .{ .has_access_credential = true, .access_expires_at_unix_s = now + 1 },
        now,
        -30,
    ));

    try testing.expectEqual(ExpiryDecision.refresh_near_expiry, evaluateExpiry(
        .{ .has_access_credential = true, .access_expires_at_unix_s = std.math.maxInt(i64) },
        std.math.maxInt(i64) - 1,
        max_refresh_skew_s,
    ));
    try testing.expectEqual(ExpiryDecision.usable, evaluateExpiry(
        .{ .has_access_credential = true, .access_expires_at_unix_s = std.math.maxInt(i64) },
        0,
        max_refresh_skew_s,
    ));
    try testing.expectEqual(@as(?i64, std.math.maxInt(i64)), expiresAtUnix(std.math.maxInt(i64) - 1, 100));
    try testing.expectEqual(@as(?i64, now), expiresAtUnix(now, -5));
    try testing.expectEqual(@as(?i64, null), expiresAtUnix(now, null));

    const plan = planRefresh(.user_requested, .{ .has_access_credential = true, .access_expires_at_unix_s = now + 900 }, now, skew);
    try testing.expect(!plan.send_token_request);
    try testing.expectEqual(RefreshTrigger.user_requested, plan.trigger);
    try testing.expect(planRefresh(.user_requested, .{}, now, skew).send_token_request);
}

test "redacted descriptor drops body, header values, query, and userinfo" {
    const request: Request = .{
        .method = .post,
        .url = "https://user:secret@token.example.invalid/v1/token?access_token=demo-leak-0000#frag",
        .headers = &[_]Header{
            .{ .name = "authorization", .value = "Bearer demo-leak-1111", .sensitive = true },
            .{ .name = "accept", .value = "application/json" },
        },
        .body = "grant_type=refresh_token&refresh_token=demo-leak-2222",
        .body_is_sensitive = true,
    };

    var buffer: [512]u8 = undefined;
    const line = formatted(&buffer, request);
    try testing.expectEqualStrings(
        "POST https://token.example.invalid/v1/token?<redacted> headers=2(1 sensitive) body=<redacted> timeout=15000ms",
        line,
    );
    for ([_][]const u8{ "demo-leak-0000", "demo-leak-1111", "demo-leak-2222", "secret", "Bearer", "authorization" }) |needle| {
        try testing.expect(std.mem.indexOf(u8, line, needle) == null);
    }

    const descriptor = request.redact();
    try testing.expectEqualStrings("https://token.example.invalid/v1/token", descriptor.target());
    try testing.expect(descriptor.query_present);
    try testing.expectEqual(@as(u32, 0), descriptor.body_bytes);

    const plain: Request = .{
        .method = .get,
        .url = "https://usage.example.invalid/v1/usage\x00\x0abad",
        .body = "abc",
    };
    const plain_descriptor = plain.redact();
    try testing.expectEqualStrings("https://usage.example.invalid/v1/usage..bad", plain_descriptor.target());
    try testing.expectEqual(@as(u32, 3), plain_descriptor.body_bytes);

    const long_request: Request = .{ .method = .get, .url = "https://usage.example.invalid/" ++ ("p" ** 200) };
    const long_descriptor = long_request.redact();
    try testing.expect(long_descriptor.truncated);
    try testing.expectEqual(@as(usize, max_redacted_target_bytes), long_descriptor.target().len);
    try testing.expect(std.mem.indexOf(u8, formatted(&buffer, long_descriptor), "...") != null);
}

test "request validation rejects insecure, oversized, and unmarked-secret requests" {
    const base: Request = .{ .method = .post, .url = test_token_url, .headers = &form_headers, .body = "grant_type=refresh_token" };
    try base.validate();

    var invalid = base;
    invalid.url = "http://token.example.invalid/v1/token";
    try testing.expectError(error.InsecureUrl, invalid.validate());
    invalid.url = "";
    try testing.expectError(error.InvalidUrl, invalid.validate());
    invalid.url = "https://";
    try testing.expectError(error.InvalidUrl, invalid.validate());
    invalid.url = "https://token.example.invalid/v1/token with space";
    try testing.expectError(error.InvalidUrl, invalid.validate());
    invalid.url = "https://token.example.invalid/" ++ ("p" ** max_url_bytes);
    try testing.expectError(error.UrlTooLong, invalid.validate());

    var unmarked = base;
    unmarked.headers = &[_]Header{.{ .name = "Authorization", .value = "Bearer demo-leak-3333" }};
    try testing.expectError(error.SensitiveHeaderNotMarked, unmarked.validate());

    var forged = base;
    forged.headers = &[_]Header{.{ .name = "accept", .value = "application/json\r\nx-injected: 1" }};
    try testing.expectError(error.InvalidHeader, forged.validate());

    var bad_name = base;
    bad_name.headers = &[_]Header{.{ .name = "bad header", .value = "1" }};
    try testing.expectError(error.InvalidHeader, bad_name.validate());

    var timeout = base;
    timeout.timeout_ms = max_timeout_ms + 1;
    try testing.expectError(error.InvalidTimeout, timeout.validate());

    var redirecting = base;
    redirecting.body_is_sensitive = true;
    redirecting.follow_redirects = true;
    try testing.expectError(error.RedirectsWithSecretBody, redirecting.validate());
}

test "refresh grant body carries the encoded credential and never the redacted view" {
    var credential = try keychain.Credential.init(test_refresh_placeholder ++ "/+= &");
    defer credential.wipe();

    var body_buffer: [max_request_body_bytes]u8 = undefined;
    const request = try buildRefreshRequest(
        .{ .token_url = test_token_url, .client_id = test_client_id, .scope = "usage read" },
        &credential,
        &body_buffer,
    );

    try testing.expectEqualStrings(
        "grant_type=refresh_token&client_id=demo-client-0000&scope=usage%20read&refresh_token=" ++
            test_refresh_placeholder ++ "%2F%2B%3D%20%26",
        request.body,
    );
    try testing.expect(request.body_is_sensitive);
    try testing.expect(!request.follow_redirects);
    try testing.expectEqual(Method.post, request.method);

    var line_buffer: [256]u8 = undefined;
    const line = formatted(&line_buffer, request);
    try testing.expect(std.mem.indexOf(u8, line, test_refresh_placeholder) == null);
    try testing.expect(std.mem.indexOf(u8, line, "grant_type") == null);
    try testing.expect(std.mem.indexOf(u8, line, "body=<redacted>") != null);

    std.crypto.secureZero(u8, &body_buffer);
}

test "JSON refresh grant matches providers that rotate through a JSON token endpoint" {
    var credential = try keychain.Credential.init(test_refresh_placeholder ++ "\"\\");
    defer credential.wipe();

    var body_buffer: [max_request_body_bytes]u8 = undefined;
    const request = try buildRefreshRequest(
        .{
            .token_url = test_token_url,
            .client_id = test_client_id,
            .body_format = .json,
        },
        &credential,
        &body_buffer,
    );

    try testing.expectEqualStrings(
        "{\"grant_type\":\"refresh_token\",\"refresh_token\":\"" ++
            test_refresh_placeholder ++ "\\\"\\\\\",\"client_id\":\"demo-client-0000\"}",
        request.body,
    );
    try testing.expectEqualStrings("application/json", request.headers[0].value);
    try testing.expect(request.body_is_sensitive);
    try testing.expect(!request.follow_redirects);
    std.crypto.secureZero(u8, &body_buffer);
}

test "refresh grant construction rejects bad inputs and wipes the body buffer" {
    var credential = try keychain.Credential.init(test_refresh_placeholder);
    defer credential.wipe();
    var empty: keychain.Credential = .empty;
    var body_buffer: [max_request_body_bytes]u8 = undefined;

    try testing.expectError(error.MissingRefreshCredential, buildRefreshRequest(
        .{ .token_url = test_token_url, .client_id = test_client_id },
        &empty,
        &body_buffer,
    ));
    try testing.expectError(error.InvalidClientId, buildRefreshRequest(
        .{ .token_url = test_token_url, .client_id = "" },
        &credential,
        &body_buffer,
    ));
    try testing.expectError(error.InvalidScope, buildRefreshRequest(
        .{ .token_url = test_token_url, .client_id = test_client_id, .scope = "read\nwrite" },
        &credential,
        &body_buffer,
    ));
    try testing.expectError(error.InsecureUrl, buildRefreshRequest(
        .{ .token_url = "http://token.example.invalid/v1/token", .client_id = test_client_id },
        &credential,
        &body_buffer,
    ));

    var tiny_buffer: [40]u8 = undefined;
    try testing.expectError(error.BodyBufferTooSmall, buildRefreshRequest(
        .{ .token_url = test_token_url, .client_id = test_client_id },
        &credential,
        &tiny_buffer,
    ));
    try testing.expect(std.mem.indexOf(u8, &tiny_buffer, test_refresh_placeholder[0..8]) == null);
    try testing.expect(std.mem.allEqual(u8, &tiny_buffer, 0));

    var oversized = try keychain.Credential.init("t" ** 3000);
    defer oversized.wipe();
    var small_buffer: [1024]u8 = undefined;
    try testing.expectError(error.BodyBufferTooSmall, buildRefreshRequest(
        .{ .token_url = test_token_url, .client_id = test_client_id },
        &oversized,
        &small_buffer,
    ));
}

test "response parser is tolerant about shape and strict about bounds" {
    var payload: RefreshPayload = .{};
    defer payload.wipe();

    const tolerant_body =
        \\{"token_type":"Bearer","unknown_object":{"nested":[1,2,{"deep":true}]},
        \\ "expires_in":"3600","access_token":"demo-access-placeholder-1111",
        \\ "unknown_null":null,"scope":"usage read","access_token":"demo-ignored-duplicate"}
    ;
    try parseRefreshResponse(tolerant_body, &payload);
    try testing.expect(payload.access.eqlPlaintext(test_access_placeholder));
    try testing.expect(payload.rotated_refresh == null);
    try testing.expect(!payload.saw_empty_rotated_refresh);
    try testing.expectEqual(@as(?i64, 3600), payload.expires_in_s);
    try testing.expectEqual(TokenType.bearer, payload.token_type);
    try testing.expectEqual(@as(?i64, 2_000_003_600), payload.expiresAt(2_000_000_000));

    payload.wipe();
    const rotated_body =
        \\{"access_token":"demo-access\u002dplaceholder-1111","refresh_token":"demo-rotated-placeholder-2222",
        \\ "expires_in":1800.9,"token_type":"mac"}
    ;
    try parseRefreshResponse(rotated_body, &payload);
    try testing.expect(payload.access.eqlPlaintext(test_access_placeholder));
    try testing.expect(payload.rotatedRefresh().?.eqlPlaintext(test_rotated_placeholder));
    try testing.expectEqual(@as(?i64, 1800), payload.expires_in_s);
    try testing.expectEqual(TokenType.other, payload.token_type);

    payload.wipe();
    try parseRefreshResponse("{\"access_token\":\"demo-access-placeholder-1111\",\"refresh_token\":\"\"}", &payload);
    try testing.expect(payload.rotated_refresh == null);
    try testing.expect(payload.saw_empty_rotated_refresh);
    payload.wipe();
    try parseRefreshResponse("{\"access_token\":\"demo-access-placeholder-1111\",\"refresh_token\":null}", &payload);
    try testing.expect(payload.rotatedRefresh() == null);
    try testing.expect(payload.saw_empty_rotated_refresh);

    payload.wipe();
    try parseRefreshResponse("{\"access_token\":\"demo-access-placeholder-1111\",\"expires_in\":\"soon\"}", &payload);
    try testing.expectEqual(@as(?i64, null), payload.expires_in_s);
    payload.wipe();
    try parseRefreshResponse("{\"access_token\":\"demo-access-placeholder-1111\",\"expires_in\":{\"seconds\":1}}", &payload);
    try testing.expectEqual(@as(?i64, null), payload.expires_in_s);
}

test "response parser rejects malformed, unbounded, and token-free bodies" {
    var payload: RefreshPayload = .{};
    defer payload.wipe();

    try testing.expectError(error.MalformedResponse, parseRefreshResponse("", &payload));
    try testing.expectError(error.MalformedResponse, parseRefreshResponse("[]", &payload));
    try testing.expectError(error.MalformedResponse, parseRefreshResponse("{\"access_token\":\"a\"", &payload));
    try testing.expectError(error.MalformedResponse, parseRefreshResponse("{\"access_token\":\"a\"} trailing", &payload));
    try testing.expectError(error.MalformedResponse, parseRefreshResponse("{\"access_token\":\"a\",}", &payload));
    try testing.expectError(error.MissingAccessToken, parseRefreshResponse("{\"token_type\":\"bearer\"}", &payload));
    try testing.expectError(error.MissingAccessToken, parseRefreshResponse("{\"access_token\":\"\"}", &payload));
    try testing.expectError(error.MissingAccessToken, parseRefreshResponse("{\"access_token\":1234}", &payload));

    const deep = "{\"a\":" ++ ("[" ** (max_json_depth + 2)) ++ ("]" ** (max_json_depth + 2)) ++ "}";
    try testing.expectError(error.NestingTooDeep, parseRefreshResponse(deep, &payload));

    var oversized: [max_response_body_bytes + 1]u8 = @splat('{');
    try testing.expectError(error.ResponseTooLarge, parseRefreshResponse(&oversized, &payload));

    const long_token = "{\"access_token\":\"" ++ ("t" ** (keychain.max_credential_bytes + 1)) ++ "\"}";
    try testing.expectError(error.ValueTooLong, parseRefreshResponse(long_token, &payload));

    const long_key = "{\"" ++ ("k" ** (max_json_key_bytes + 8)) ++ "\":1,\"access_token\":\"demo-access-placeholder-1111\"}";
    try parseRefreshResponse(long_key, &payload);
    try testing.expect(payload.access.eqlPlaintext(test_access_placeholder));
}

test "parsed payload keeps no plaintext in its own bytes and wipes clean" {
    var payload: RefreshPayload = .{};
    const body =
        \\{"access_token":"demo-access-placeholder-1111","refresh_token":"demo-rotated-placeholder-2222","expires_in":3600}
    ;
    try parseRefreshResponse(body, &payload);
    try testing.expect(std.mem.indexOf(u8, std.mem.asBytes(&payload.access), test_access_placeholder) == null);
    try testing.expect(std.mem.indexOf(u8, std.mem.asBytes(&payload.rotated_refresh.?), test_rotated_placeholder) == null);

    var buffer: [256]u8 = undefined;
    const line = formatted(&buffer, &payload);
    try testing.expectEqualStrings("access=[redacted credential] rotated=true type=unspecified expires_in=3600s", line);
    try testing.expect(std.mem.indexOf(u8, line, test_access_placeholder) == null);

    payload.wipe();
    try testing.expect(payload.access.isEmpty());
    try testing.expect(payload.rotated_refresh == null);
    try testing.expectEqual(@as(?i64, null), payload.expires_in_s);

    try testing.expectError(error.MissingAccessToken, parseRefreshResponse("{\"refresh_token\":\"demo-rotated-placeholder-2222\"}", &payload));
    try testing.expect(payload.access.isEmpty());
    try testing.expect(payload.rotated_refresh == null);
}

test "oauth error codes stay inside the allowlist" {
    try testing.expectEqual(OAuthErrorCode.invalid_grant, parseErrorCode("{\"error\":\"invalid_grant\"}").?);
    try testing.expectEqual(OAuthErrorCode.invalid_grant, parseErrorCode(
        "{\"error_description\":\"do not log me\",\"error\":\"invalid_grant\"}",
    ).?);
    try testing.expectEqual(OAuthErrorCode.unrecognized, parseErrorCode("{\"error\":\"teapot_on_fire\"}").?);
    try testing.expectEqual(OAuthErrorCode.unrecognized, parseErrorCode("{\"error\":\"unrecognized\"}").?);
    try testing.expect(parseErrorCode("{\"error\":404}") == null);
    try testing.expect(parseErrorCode("not json") == null);
    try testing.expect(parseErrorCode("{}") == null);
    try testing.expect(OAuthErrorCode.invalid_grant.requiresReauth());
    try testing.expect(!OAuthErrorCode.invalid_scope.requiresReauth());
}

test "failure mapping is sanitized and domain compatible" {
    try testing.expect(refreshErrorFromStatus(200, null) == null);

    const cases = [_]struct { status: u16, code: ?OAuthErrorCode, kind: domain.RefreshErrorKind, public_code: []const u8, retryable: bool }{
        .{ .status = 204, .code = null, .kind = .malformed_response, .public_code = public_code_malformed, .retryable = false },
        .{ .status = 302, .code = null, .kind = .unknown, .public_code = public_code_rejected, .retryable = false },
        .{ .status = 400, .code = .invalid_grant, .kind = .authentication, .public_code = public_code_sign_in_required, .retryable = false },
        .{ .status = 400, .code = .invalid_scope, .kind = .unknown, .public_code = public_code_rejected, .retryable = false },
        .{ .status = 401, .code = null, .kind = .authentication, .public_code = public_code_sign_in_required, .retryable = false },
        .{ .status = 403, .code = null, .kind = .authentication, .public_code = public_code_access_denied, .retryable = false },
        .{ .status = 408, .code = null, .kind = .timeout, .public_code = public_code_timeout, .retryable = true },
        .{ .status = 429, .code = null, .kind = .rate_limited, .public_code = public_code_rate_limited, .retryable = true },
        .{ .status = 451, .code = null, .kind = .unknown, .public_code = public_code_rejected, .retryable = false },
        .{ .status = 500, .code = null, .kind = .provider_unavailable, .public_code = public_code_provider_unavailable, .retryable = true },
        .{ .status = 503, .code = null, .kind = .provider_unavailable, .public_code = public_code_provider_unavailable, .retryable = true },
    };
    for (cases) |case| {
        const failure = refreshErrorFromStatus(case.status, case.code).?;
        try testing.expectEqual(case.kind, failure.kind);
        try testing.expectEqualStrings(case.public_code, failure.public_code);
        try testing.expectEqual(case.retryable, failure.retryable);
        try testing.expect(isPublicCode(failure.public_code));
    }

    try testing.expectEqual(domain.RefreshErrorKind.timeout, refreshErrorFromTransport(error.Timeout).kind);
    try testing.expectEqual(domain.RefreshErrorKind.network, refreshErrorFromTransport(error.Network).kind);
    try testing.expectEqual(domain.RefreshErrorKind.network, refreshErrorFromTransport(error.Tls).kind);
    try testing.expectEqualStrings(public_code_network, refreshErrorFromTransport(error.Tls).public_code);
    try testing.expectEqual(domain.RefreshErrorKind.malformed_response, refreshErrorFromTransport(error.ResponseTooLarge).kind);
    try testing.expectEqual(domain.RefreshErrorKind.provider_unavailable, refreshErrorFromTransport(error.Unsupported).kind);
    try testing.expect(!refreshErrorFromTransport(error.Unsupported).retryable);

    try testing.expectEqual(domain.RefreshErrorKind.malformed_response, refreshErrorFromParse(error.MalformedResponse).kind);
    try testing.expectEqual(domain.RefreshErrorKind.malformed_response, refreshErrorFromParse(error.NestingTooDeep).kind);
    try testing.expectEqual(domain.RefreshErrorKind.authentication, refreshErrorFromParse(error.MissingAccessToken).kind);

    try testing.expectEqual(domain.RefreshErrorKind.persistence, refreshErrorFromStore(error.Unavailable).kind);
    try testing.expect(refreshErrorFromStore(error.Unavailable).retryable);
    try testing.expectEqual(domain.RefreshErrorKind.persistence, refreshErrorFromStore(error.Unsupported).kind);
    try testing.expect(!refreshErrorFromStore(error.Unsupported).retryable);
    try testing.expectEqual(domain.RefreshErrorKind.authentication, refreshErrorFromStore(error.NotFound).kind);
    try testing.expectEqual(domain.RefreshErrorKind.authentication, refreshErrorFromBuild(error.MissingRefreshCredential).kind);
    try testing.expectEqual(domain.RefreshErrorKind.unknown, refreshErrorFromBuild(error.InvalidClientId).kind);

    for (public_codes) |code| {
        try testing.expect(code.len > 0 and code.len < 40);
        for (code) |byte| try testing.expect(byte == '-' or std.ascii.isLower(byte));
    }
}

test "rotation stages and verifies before the live credential is replaced" {
    var fake: keychain.MemoryStore = .{};
    defer fake.deinit();
    const store = fake.store();
    const account = demoAccount();

    var current = try keychain.Credential.init(test_refresh_placeholder);
    defer current.wipe();
    var replacement = try keychain.Credential.init(test_rotated_placeholder);
    defer replacement.wipe();
    try store.save(&account, .refresh_token, &current);

    fake.resetOperations();
    const result = rotateRefreshCredential(store, &account, &replacement);
    try testing.expectEqual(RotationOutcome.rotated, result.outcome);
    try testing.expect(result.ok());

    const expected = [_]keychain.MemoryStore.Operation{
        .{ .action = .save, .kind = .staged_refresh_token },
        .{ .action = .load, .kind = .staged_refresh_token },
        .{ .action = .save, .kind = .refresh_token },
        .{ .action = .remove, .kind = .staged_refresh_token },
    };
    try testing.expectEqualSlices(keychain.MemoryStore.Operation, &expected, fake.recordedOperations());

    var live: keychain.Credential = .empty;
    defer live.wipe();
    try store.load(&account, .refresh_token, &live);
    try testing.expect(live.eql(&replacement));
    try testing.expect(!try store.contains(&account, .staged_refresh_token));

    fake.resetOperations();
    try testing.expectEqual(RotationOutcome.no_rotation, rotateRefreshCredential(store, &account, null).outcome);
    var empty: keychain.Credential = .empty;
    try testing.expectEqual(RotationOutcome.no_rotation, rotateRefreshCredential(store, &account, &empty).outcome);
    try testing.expectEqual(@as(usize, 0), fake.recordedOperations().len);
}

test "failed staging retains the old durable refresh credential" {
    var fake: keychain.MemoryStore = .{};
    defer fake.deinit();
    const store = fake.store();
    const account = demoAccount();

    var current = try keychain.Credential.init(test_refresh_placeholder);
    defer current.wipe();
    var replacement = try keychain.Credential.init(test_rotated_placeholder);
    defer replacement.wipe();
    try store.save(&account, .refresh_token, &current);

    fake.fail_saves_for = .staged_refresh_token;
    fake.fail_next_save = error.Unavailable;
    fake.resetOperations();
    const result = rotateRefreshCredential(store, &account, &replacement);
    try testing.expectEqual(RotationOutcome.staging_failed_old_credential_retained, result.outcome);
    try testing.expectEqual(domain.RefreshErrorKind.persistence, result.failure.?.kind);
    try testing.expect(result.failure.?.retryable);
    try testing.expect(result.outcome.oldRefreshCredentialRetained());
    try testing.expect(!result.outcome.refreshCredentialAdvanced());

    try testing.expectEqual(@as(usize, 1), fake.recordedOperations().len);
    var live: keychain.Credential = .empty;
    defer live.wipe();
    try store.load(&account, .refresh_token, &live);
    try testing.expect(live.eql(&current));
    try testing.expect(!try store.contains(&account, .staged_refresh_token));
}

test "unverifiable staging is discarded and never promoted" {
    var fake: keychain.MemoryStore = .{};
    defer fake.deinit();
    const store = fake.store();
    const account = demoAccount();

    var current = try keychain.Credential.init(test_refresh_placeholder);
    defer current.wipe();
    var replacement = try keychain.Credential.init(test_rotated_placeholder);
    defer replacement.wipe();
    try store.save(&account, .refresh_token, &current);

    fake.fail_loads_for = .staged_refresh_token;
    fake.fail_next_load = error.Corrupt;
    const result = rotateRefreshCredential(store, &account, &replacement);
    try testing.expectEqual(RotationOutcome.staging_failed_old_credential_retained, result.outcome);
    try testing.expectEqualStrings(public_code_store_corrupt, result.failure.?.public_code);

    fake.fail_loads_for = null;
    fake.fail_next_load = null;
    var live: keychain.Credential = .empty;
    defer live.wipe();
    try store.load(&account, .refresh_token, &live);
    try testing.expect(live.eql(&current));

    try testing.expect(!try store.contains(&account, .staged_refresh_token));
}

test "failed promotion keeps the replacement recoverable from staging" {
    var fake: keychain.MemoryStore = .{};
    defer fake.deinit();
    const store = fake.store();
    const account = demoAccount();

    var current = try keychain.Credential.init(test_refresh_placeholder);
    defer current.wipe();
    var replacement = try keychain.Credential.init(test_rotated_placeholder);
    defer replacement.wipe();
    try store.save(&account, .refresh_token, &current);

    fake.fail_saves_for = .refresh_token;
    fake.fail_next_save = error.AccessDenied;
    const result = rotateRefreshCredential(store, &account, &replacement);
    try testing.expectEqual(RotationOutcome.promotion_failed_staged_recoverable, result.outcome);
    try testing.expect(result.outcome.needsRecoverySweep());
    try testing.expect(result.outcome.oldRefreshCredentialRetained());
    try testing.expect(try store.contains(&account, .staged_refresh_token));

    var live: keychain.Credential = .empty;
    defer live.wipe();
    try store.load(&account, .refresh_token, &live);
    try testing.expect(live.eql(&current));

    fake.fail_saves_for = null;
    fake.fail_next_save = null;
    const recovery = recoverStagedRotation(store, &account);
    try testing.expectEqual(RecoveryOutcome.promoted_staged, recovery.outcome);
    try store.load(&account, .refresh_token, &live);
    try testing.expect(live.eql(&replacement));
    try testing.expect(!try store.contains(&account, .staged_refresh_token));

    try testing.expectEqual(RecoveryOutcome.nothing_staged, recoverStagedRotation(store, &account).outcome);
}

test "uncleared staging still counts as a completed rotation" {
    var fake: keychain.MemoryStore = .{};
    defer fake.deinit();
    const store = fake.store();
    const account = demoAccount();

    var replacement = try keychain.Credential.init(test_rotated_placeholder);
    defer replacement.wipe();

    fake.fail_removes_for = .staged_refresh_token;
    fake.fail_next_remove = error.Unavailable;
    const result = rotateRefreshCredential(store, &account, &replacement);
    try testing.expectEqual(RotationOutcome.rotated_staging_not_cleared, result.outcome);

    try testing.expect(result.ok());
    try testing.expect(result.outcome.refreshCredentialAdvanced());
    try testing.expect(result.outcome.needsRecoverySweep());

    var live: keychain.Credential = .empty;
    defer live.wipe();
    try store.load(&account, .refresh_token, &live);
    try testing.expect(live.eql(&replacement));

    fake.fail_removes_for = null;
    fake.fail_next_remove = null;
    try testing.expectEqual(RecoveryOutcome.promoted_staged, recoverStagedRotation(store, &account).outcome);
    try store.load(&account, .refresh_token, &live);
    try testing.expect(live.eql(&replacement));
}

test "every rotation outcome leaves a usable durable refresh credential" {
    for (std.enums.values(RotationOutcome)) |outcome| {
        try testing.expect(outcome.refreshCredentialAdvanced() or outcome.oldRefreshCredentialRetained());
    }
    try testing.expect(!RotationOutcome.rotated.needsRecoverySweep());
}

test "recovery reports an unreadable staging slot without touching the live credential" {
    var fake: keychain.MemoryStore = .{};
    defer fake.deinit();
    const store = fake.store();
    const account = demoAccount();

    var current = try keychain.Credential.init(test_refresh_placeholder);
    defer current.wipe();
    try store.save(&account, .refresh_token, &current);
    var staged = try keychain.Credential.init(test_rotated_placeholder);
    defer staged.wipe();
    try store.save(&account, .staged_refresh_token, &staged);

    fake.fail_loads_for = .staged_refresh_token;
    fake.fail_next_load = error.Unavailable;
    const recovery = recoverStagedRotation(store, &account);
    try testing.expectEqual(RecoveryOutcome.staging_unreadable, recovery.outcome);
    try testing.expectEqual(domain.RefreshErrorKind.persistence, recovery.failure.?.kind);

    fake.fail_loads_for = null;
    fake.fail_next_load = null;
    var live: keychain.Credential = .empty;
    defer live.wipe();
    try store.load(&account, .refresh_token, &live);
    try testing.expect(live.eql(&current));
    try testing.expect(try store.contains(&account, .staged_refresh_token));
}

test "applying a payload persists the refresh credential before the access credential" {
    var fake: keychain.MemoryStore = .{};
    defer fake.deinit();
    const store = fake.store();
    const account = demoAccount();

    var payload: RefreshPayload = .{};
    defer payload.wipe();
    try parseRefreshResponse(
        \\{"access_token":"demo-access-placeholder-1111","refresh_token":"demo-rotated-placeholder-2222","expires_in":3600}
    , &payload);

    fake.resetOperations();
    const applied = applyRefreshPayload(store, &account, &payload);
    try testing.expectEqual(RotationOutcome.rotated, applied.rotation.outcome);
    try testing.expect(applied.access_stored);
    try testing.expect(applied.failure == null);

    const operations = fake.recordedOperations();
    try testing.expectEqual(@as(usize, 5), operations.len);
    try testing.expectEqual(keychain.CredentialKind.access_token, operations[4].kind);
    try testing.expectEqual(keychain.MemoryStore.Action.save, operations[4].action);

    var loaded: keychain.Credential = .empty;
    defer loaded.wipe();
    try store.load(&account, .access_token, &loaded);
    try testing.expect(loaded.eqlPlaintext(test_access_placeholder));
    try store.load(&account, .refresh_token, &loaded);
    try testing.expect(loaded.eqlPlaintext(test_rotated_placeholder));

    fake.fail_saves_for = .access_token;
    fake.fail_next_save = error.Unavailable;
    const failed = applyRefreshPayload(store, &account, &payload);
    try testing.expect(!failed.access_stored);
    try testing.expectEqual(domain.RefreshErrorKind.persistence, failed.failure.?.kind);
    try testing.expectEqual(RotationOutcome.rotated, failed.rotation.outcome);
}

test "unwired transport fails closed and maps to a sanitized failure" {
    const client = unwiredClient();
    var body_buffer: [64]u8 = undefined;
    const request: Request = .{ .method = .get, .url = "https://usage.example.invalid/v1/usage" };
    try testing.expectError(error.Unsupported, client.send(request, &body_buffer));
    const failure = refreshErrorFromTransport(error.Unsupported);
    try testing.expectEqual(domain.RefreshErrorKind.provider_unavailable, failure.kind);
    try testing.expect(isPublicCode(failure.public_code));
}

test "fake transport records only redacted descriptors and enforces the contract" {
    var fake: FakeHttpClient = .{ .replies = &[_]FakeHttpClient.Reply{
        .{ .response = .{ .status = 200, .body = "{\"access_token\":\"demo-access-placeholder-1111\"}" } },
        .{ .response = .{ .status = 429, .body = "{\"error\":\"slow_down\"}", .retry_after_s = 30 } },
        .{ .failure = error.Timeout },
    } };
    const client = fake.client();

    var credential = try keychain.Credential.init(test_refresh_placeholder);
    defer credential.wipe();
    var body_buffer: [max_request_body_bytes]u8 = undefined;
    defer std.crypto.secureZero(u8, &body_buffer);
    const request = try buildRefreshRequest(
        .{ .token_url = test_token_url, .client_id = test_client_id },
        &credential,
        &body_buffer,
    );

    var response_buffer: [max_response_body_bytes]u8 = undefined;
    defer std.crypto.secureZero(u8, &response_buffer);
    const response = try client.send(request, &response_buffer);
    try testing.expect(response.isSuccess());
    try testing.expect(refreshErrorFromStatus(response.status, null) == null);

    var payload: RefreshPayload = .{};
    defer payload.wipe();
    try parseRefreshResponse(response.body, &payload);
    try testing.expect(payload.access.eqlPlaintext(test_access_placeholder));

    const throttled = try client.send(request, &response_buffer);
    try testing.expectEqual(@as(?u32, 30), throttled.retry_after_s);
    const throttle_failure = refreshErrorFromStatus(throttled.status, parseErrorCode(throttled.body)).?;
    try testing.expectEqual(domain.RefreshErrorKind.rate_limited, throttle_failure.kind);
    try testing.expectError(error.Timeout, client.send(request, &response_buffer));

    try testing.expectError(error.RequestRejected, client.send(request, &response_buffer));

    try testing.expectEqual(@as(usize, 4), fake.call_count);
    var buffer: [256]u8 = undefined;
    for (fake.requests()) |descriptor| {
        const line = formatted(&buffer, descriptor);
        try testing.expect(std.mem.indexOf(u8, line, test_refresh_placeholder) == null);
        try testing.expect(std.mem.indexOf(u8, line, "body=<redacted>") != null);
    }

    var insecure: Request = request;
    insecure.url = "http://token.example.invalid/v1/token";
    try testing.expectError(error.RequestRejected, client.send(insecure, &response_buffer));

    var small_buffer: [8]u8 = undefined;
    var oversized: FakeHttpClient = .{ .replies = &[_]FakeHttpClient.Reply{
        .{ .response = .{ .status = 200, .body = "{\"access_token\":\"demo-access-placeholder-1111\"}" } },
    } };
    try testing.expectError(error.ResponseTooLarge, oversized.client().send(request, &small_buffer));
}

test "no request is sent unless the user asked for one" {
    var fake: FakeHttpClient = .{ .replies = &[_]FakeHttpClient.Reply{
        .{ .response = .{ .status = 200, .body = "{\"access_token\":\"demo-access-placeholder-1111\",\"expires_in\":3600}" } },
    } };
    const client = fake.client();
    const now: i64 = 2_000_000_000;

    const window: CredentialWindow = .{ .has_access_credential = true, .access_expires_at_unix_s = now - 1 };
    var passive: usize = 0;
    while (passive < 3) : (passive += 1) {
        const decision = evaluateExpiry(window, now, default_refresh_skew_s);
        try testing.expect(decision.requiresRefresh());
    }
    try testing.expectEqual(@as(usize, 0), fake.call_count);
    try testing.expectEqual(@as(usize, 0), fake.requests().len);

    const plan = planRefresh(.user_requested, window, now, default_refresh_skew_s);
    try testing.expect(plan.send_token_request);

    var credential = try keychain.Credential.init(test_refresh_placeholder);
    defer credential.wipe();
    var body_buffer: [max_request_body_bytes]u8 = undefined;
    defer std.crypto.secureZero(u8, &body_buffer);
    var response_buffer: [4096]u8 = undefined;
    defer std.crypto.secureZero(u8, &response_buffer);
    const request = try buildRefreshRequest(
        .{ .token_url = test_token_url, .client_id = test_client_id },
        &credential,
        &body_buffer,
    );
    _ = try client.send(request, &response_buffer);
    try testing.expectEqual(@as(usize, 1), fake.call_count);
}

const FakeExchange = struct {
    const max_recorded: usize = 8;

    const Reply = union(enum) {
        response: struct { status: u16, body: []const u8 = &.{}, retry_after: []const u8 = &.{} },
        failure: TransportError,
    };

    replies: []const Reply = &.{},
    next_index: usize = 0,
    call_count: usize = 0,
    recorded: [max_recorded]RedactedRequest = @splat(.{ .method = .post }),
    recorded_count: usize = 0,
    last_timeout_ms: u32 = 0,
    saw_follow_redirects: bool = false,

    const vtable: Exchange.VTable = .{ .perform = perform };

    fn exchange(self: *FakeExchange) Exchange {
        return .{ .context = self, .vtable = &vtable };
    }

    fn requests(self: *const FakeExchange) []const RedactedRequest {
        return self.recorded[0..self.recorded_count];
    }

    fn perform(context: *anyopaque, request: Request, body_buffer: []u8) TransportError!ExchangeResult {
        const self: *FakeExchange = @ptrCast(@alignCast(context));
        self.call_count += 1;
        self.last_timeout_ms = request.timeout_ms;
        self.saw_follow_redirects = self.saw_follow_redirects or request.follow_redirects;
        if (self.recorded_count < max_recorded) {
            self.recorded[self.recorded_count] = request.redact();
            self.recorded_count += 1;
        }
        if (self.next_index >= self.replies.len) return error.RequestRejected;
        const reply = self.replies[self.next_index];
        self.next_index += 1;
        switch (reply) {
            .failure => |err| return err,
            .response => |scripted| {
                if (scripted.body.len > body_buffer.len) return error.ResponseTooLarge;
                @memcpy(body_buffer[0..scripted.body.len], scripted.body);
                return .{
                    .status = scripted.status,
                    .body_len = scripted.body.len,
                    .retry_after = .init(scripted.retry_after),
                };
            },
        }
    }
};

test "live transport refuses a request it cannot prove safe before any byte leaves" {
    var backend: FakeExchange = .{ .replies = &[_]FakeExchange.Reply{
        .{ .response = .{ .status = 200 } },
    } };
    var transport: HttpTransport = .init(backend.exchange());
    const client = transport.client();
    var response_buffer: [64]u8 = undefined;

    const insecure: Request = .{ .method = .post, .url = "http://token.example.invalid/v1/token" };
    try testing.expectError(error.RequestRejected, client.send(insecure, &response_buffer));

    const unmarked: Request = .{
        .method = .get,
        .url = "https://usage.example.invalid/v1/usage",
        .headers = &[_]Header{.{ .name = "authorization", .value = "Bearer demo-leak-4444" }},
    };
    try testing.expectError(error.RequestRejected, client.send(unmarked, &response_buffer));

    const forged: Request = .{
        .method = .get,
        .url = "https://usage.example.invalid/v1/usage",
        .headers = &[_]Header{.{ .name = "accept", .value = "application/json\r\nx-injected: 1" }},
    };
    try testing.expectError(error.RequestRejected, client.send(forged, &response_buffer));

    var untimed: Request = .{ .method = .get, .url = "https://usage.example.invalid/v1/usage" };
    untimed.timeout_ms = max_timeout_ms + 1;
    try testing.expectError(error.RequestRejected, client.send(untimed, &response_buffer));

    const redirecting: Request = .{
        .method = .get,
        .url = "https://usage.example.invalid/v1/usage",
        .follow_redirects = true,
    };
    try testing.expectError(error.RequestRejected, client.send(redirecting, &response_buffer));

    try testing.expectEqual(@as(usize, 0), backend.call_count);
    try testing.expect(!backend.saw_follow_redirects);
}

test "live transport passes the caller's timeout down and keeps its record redacted" {
    var backend: FakeExchange = .{ .replies = &[_]FakeExchange.Reply{
        .{ .response = .{ .status = 200, .body = "{\"access_token\":\"demo-access-placeholder-1111\"}" } },
    } };
    var transport: HttpTransport = .init(backend.exchange());
    const client = transport.client();

    var credential = try keychain.Credential.init(test_refresh_placeholder);
    defer credential.wipe();
    var body_buffer: [max_request_body_bytes]u8 = undefined;
    defer std.crypto.secureZero(u8, &body_buffer);
    const request = try buildRefreshRequest(
        .{ .token_url = test_token_url, .client_id = test_client_id, .timeout_ms = 4_000 },
        &credential,
        &body_buffer,
    );

    var response_buffer: [max_response_body_bytes]u8 = undefined;
    defer std.crypto.secureZero(u8, &response_buffer);
    const response = try client.send(request, &response_buffer);
    try testing.expect(response.isSuccess());
    try testing.expectEqual(@as(u32, 4_000), backend.last_timeout_ms);
    try testing.expect(response.retry_after_s == null);

    var payload: RefreshPayload = .{};
    defer payload.wipe();
    try parseRefreshResponse(response.body, &payload);
    try testing.expect(payload.access.eqlPlaintext(test_access_placeholder));

    var line_buffer: [256]u8 = undefined;
    for (backend.requests()) |descriptor| {
        const line = formatted(&line_buffer, descriptor);
        try testing.expect(std.mem.indexOf(u8, line, test_refresh_placeholder) == null);
        try testing.expect(std.mem.indexOf(u8, line, "grant_type") == null);
        try testing.expect(std.mem.indexOf(u8, line, "body=<redacted>") != null);
    }
}

test "live transport surfaces a redirect as a status instead of chasing it" {
    var backend: FakeExchange = .{ .replies = &[_]FakeExchange.Reply{
        .{ .response = .{ .status = 302, .body = "" } },
    } };
    var transport: HttpTransport = .init(backend.exchange());
    const client = transport.client();

    var response_buffer: [64]u8 = undefined;
    const request: Request = .{ .method = .get, .url = "https://usage.example.invalid/v1/usage" };
    const response = try client.send(request, &response_buffer);
    try testing.expectEqual(@as(u16, 302), response.status);
    try testing.expect(!response.isSuccess());

    const failure = refreshErrorFromStatus(response.status, null).?;
    try testing.expectEqualStrings(public_code_rejected, failure.public_code);
    try testing.expect(!failure.retryable);
    try testing.expect(!backend.saw_follow_redirects);
}

test "retry-after is read only as a bounded delay in seconds" {
    const accepted = [_]struct { text: []const u8, expected: u32 }{
        .{ .text = "0", .expected = 0 },
        .{ .text = "30", .expected = 30 },
        .{ .text = " 45 ", .expected = 45 },
        .{ .text = "86400", .expected = max_retry_after_s },

        .{ .text = "9999999999", .expected = max_retry_after_s },
    };
    for (accepted) |case| {
        const header: RetryAfterHeader = .init(case.text);
        try testing.expectEqual(@as(?u32, case.expected), header.seconds());
    }

    const ignored = [_][]const u8{
        "",
        "-5",
        "+30",
        "30.5",
        "soon",

        "Wed, 21 Oct 2015 07:28:00 GMT",
        "99999999999999999999",
        "3" ** (max_retry_after_text_bytes + 1),
    };
    for (ignored) |text| {
        const header: RetryAfterHeader = .init(text);
        try testing.expectEqual(@as(?u32, null), header.seconds());
    }

    try testing.expectEqual(@as(usize, 0), RetryAfterHeader.init("9" ** (max_retry_after_text_bytes + 1)).text().len);

    var backend: FakeExchange = .{ .replies = &[_]FakeExchange.Reply{
        .{ .response = .{ .status = 429, .body = "{\"error\":\"slow_down\"}", .retry_after = "30" } },
        .{ .response = .{ .status = 429, .body = "{}", .retry_after = "Wed, 21 Oct 2015 07:28:00 GMT" } },
    } };
    var transport: HttpTransport = .init(backend.exchange());
    const client = transport.client();
    var response_buffer: [128]u8 = undefined;
    const request: Request = .{ .method = .get, .url = "https://usage.example.invalid/v1/usage" };

    const throttled = try client.send(request, &response_buffer);
    try testing.expectEqual(@as(?u32, 30), throttled.retry_after_s);
    try testing.expectEqual(
        domain.RefreshErrorKind.rate_limited,
        refreshErrorFromStatus(throttled.status, parseErrorCode(throttled.body)).?.kind,
    );

    const dated = try client.send(request, &response_buffer);
    try testing.expectEqual(@as(?u32, null), dated.retry_after_s);
}

test "live transport reports an over-long response instead of a prefix of one" {
    const body = "{\"access_token\":\"demo-access-placeholder-1111\"}";
    var backend: FakeExchange = .{ .replies = &[_]FakeExchange.Reply{
        .{ .response = .{ .status = 200, .body = body } },
        .{ .response = .{ .status = 200, .body = body } },
    } };
    var transport: HttpTransport = .init(backend.exchange());
    const client = transport.client();
    const request: Request = .{ .method = .get, .url = "https://usage.example.invalid/v1/usage" };

    var small_buffer: [8]u8 = undefined;
    try testing.expectError(error.ResponseTooLarge, client.send(request, &small_buffer));

    try testing.expect(std.mem.indexOf(u8, &small_buffer, "access_token") == null);

    var exact_buffer: [body.len]u8 = undefined;
    const response = try client.send(request, &exact_buffer);
    try testing.expectEqualStrings(body, response.body);

    const failure = refreshErrorFromTransport(error.ResponseTooLarge);
    try testing.expectEqual(domain.RefreshErrorKind.malformed_response, failure.kind);
    try testing.expect(isPublicCode(failure.public_code));
}

test "live transport failures stay sanitized and describe nothing" {
    const failures = [_]TransportError{
        error.Timeout,
        error.Network,
        error.Tls,
        error.ResponseTooLarge,
        error.RequestRejected,
        error.Canceled,
        error.Unsupported,
    };
    var replies: [failures.len]FakeExchange.Reply = undefined;
    for (failures, 0..) |err, index| replies[index] = .{ .failure = err };

    var backend: FakeExchange = .{ .replies = &replies };
    var transport: HttpTransport = .init(backend.exchange());
    const client = transport.client();
    var response_buffer: [64]u8 = undefined;
    const request: Request = .{ .method = .get, .url = "https://usage.example.invalid/v1/usage" };

    for (failures) |expected| {
        try testing.expectError(expected, client.send(request, &response_buffer));
        const failure = refreshErrorFromTransport(expected);
        try testing.expect(isPublicCode(failure.public_code));

        try testing.expect(std.mem.indexOf(u8, failure.public_code, "tls") == null);
        try testing.expect(std.mem.indexOf(u8, failure.public_code, "certificate") == null);
    }
    try testing.expectEqual(failures.len, backend.call_count);
}

fn immediateResult(status: u16) TransportError!ExchangeResult {
    return .{ .status = status };
}

fn stallingResult(io: std.Io, hold_ms: u32) TransportError!ExchangeResult {
    io.sleep(.fromMilliseconds(hold_ms), .awake) catch return error.Canceled;
    return .{ .status = 200 };
}

test "bounded execution returns a finished result and abandons an overrunning one" {
    var threaded: std.Io.Threaded = .init(testing.allocator, .{});
    defer threaded.deinit();
    const io = threaded.io();

    const finished = try runBounded(io, 5_000, immediateResult, .{@as(u16, 204)});
    try testing.expectEqual(@as(u16, 204), finished.status);
    try testing.expectEqual(@as(usize, 0), finished.body_len);

    try testing.expectError(error.Timeout, runBounded(io, 20, stallingResult, .{ io, 30_000 }));

    const failure = refreshErrorFromTransport(error.Timeout);
    try testing.expectEqual(domain.RefreshErrorKind.timeout, failure.kind);
    try testing.expect(failure.retryable);
}

test "constructing the TLS transport touches neither the network nor an allocator" {
    var live: TlsTransport = .init(testing.failing_allocator, .failing);
    const client = live.client();
    try testing.expect(client.context == @as(*anyopaque, @ptrCast(&live.transport)));
    try testing.expect(live.transport.exchange.context == @as(*anyopaque, @ptrCast(&live.backend)));

    var backend: TlsExchange = .init(testing.failing_allocator, .failing);
    var transport: HttpTransport = .init(backend.exchange());
    _ = transport.client();

    var response_buffer: [32]u8 = undefined;
    const insecure: Request = .{ .method = .post, .url = "http://token.example.invalid/v1/token" };
    try testing.expectError(error.RequestRejected, client.send(insecure, &response_buffer));
}
