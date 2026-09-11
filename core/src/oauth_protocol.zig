const std = @import("std");
const domain = @import("domain.zig");
const keychain = @import("keychain.zig");
const transport = @import("oauth_transport.zig");

const default_timeout_ms = transport.default_timeout_ms;
const max_response_body_bytes = transport.max_response_body_bytes;
const max_client_id_bytes = transport.max_client_id_bytes;
const max_scope_bytes = transport.max_scope_bytes;
const max_json_depth = transport.max_json_depth;
const max_json_key_bytes = transport.max_json_key_bytes;
const max_refresh_skew_s = transport.max_refresh_skew_s;
const Header = transport.Header;
const RequestError = transport.RequestError;
const Request = transport.Request;
const TransportError = transport.TransportError;
const isLogSafeByte = transport.isLogSafeByte;

pub const RefreshTrigger = enum { user_requested };

pub const CredentialWindow = struct {
    has_access_credential: bool = false,

    access_expires_at_unix_s: ?i64 = null,
};

pub const ExpiryDecision = enum {
    refresh_missing_credential,

    refresh_unknown_expiry,
    refresh_expired,
    refresh_near_expiry,
    usable,

    pub fn requiresRefresh(self: ExpiryDecision) bool {
        return self != .usable;
    }
};

pub fn clampSkew(skew_s: i64) i64 {
    if (skew_s <= 0) return 0;
    return @min(skew_s, max_refresh_skew_s);
}

pub fn evaluateExpiry(window: CredentialWindow, now_unix_s: i64, skew_s: i64) ExpiryDecision {
    if (!window.has_access_credential) return .refresh_missing_credential;
    const expires_at = window.access_expires_at_unix_s orelse return .refresh_unknown_expiry;
    if (expires_at <= now_unix_s) return .refresh_expired;
    if (expires_at <= now_unix_s +| clampSkew(skew_s)) return .refresh_near_expiry;
    return .usable;
}

pub fn expiresAtUnix(now_unix_s: i64, expires_in_s: ?i64) ?i64 {
    const lifetime = expires_in_s orelse return null;
    if (lifetime <= 0) return now_unix_s;
    return now_unix_s +| lifetime;
}

pub const RefreshPlan = struct {
    trigger: RefreshTrigger,
    decision: ExpiryDecision,

    send_token_request: bool,
};

pub fn planRefresh(trigger: RefreshTrigger, window: CredentialWindow, now_unix_s: i64, skew_s: i64) RefreshPlan {
    const decision = evaluateExpiry(window, now_unix_s, skew_s);
    return .{ .trigger = trigger, .decision = decision, .send_token_request = decision.requiresRefresh() };
}

pub const RefreshGrant = struct {
    token_url: []const u8,
    client_id: []const u8,
    scope: ?[]const u8 = null,
    timeout_ms: u32 = default_timeout_ms,

    body_format: BodyFormat = .form,
};

pub const BodyFormat = enum { form, json };

pub const BuildError = RequestError || error{
    MissingRefreshCredential,
    InvalidClientId,
    InvalidScope,
    BodyBufferTooSmall,
};

const form_headers = [_]Header{
    .{ .name = "content-type", .value = "application/x-www-form-urlencoded" },
    .{ .name = "accept", .value = "application/json" },
};

const json_headers = [_]Header{
    .{ .name = "content-type", .value = "application/json" },
    .{ .name = "accept", .value = "application/json" },
};

pub fn buildRefreshRequest(
    grant: RefreshGrant,
    refresh_credential: *const keychain.Credential,
    body_buffer: []u8,
) BuildError!Request {
    if (refresh_credential.isEmpty()) return error.MissingRefreshCredential;
    if (grant.client_id.len == 0 or grant.client_id.len > max_client_id_bytes) return error.InvalidClientId;
    for (grant.client_id) |byte| {
        if (!isLogSafeByte(byte)) return error.InvalidClientId;
    }
    if (grant.scope) |scope| {
        if (scope.len == 0 or scope.len > max_scope_bytes) return error.InvalidScope;
        for (scope) |byte| {
            if (byte != ' ' and !isLogSafeByte(byte)) return error.InvalidScope;
        }
    }

    errdefer std.crypto.secureZero(u8, body_buffer);

    var writer = std.Io.Writer.fixed(body_buffer);
    switch (grant.body_format) {
        .form => writeFormBody(&writer, grant, refresh_credential) catch return error.BodyBufferTooSmall,
        .json => writeJsonBody(&writer, grant, refresh_credential) catch return error.BodyBufferTooSmall,
    }

    const request: Request = .{
        .method = .post,
        .url = grant.token_url,
        .headers = switch (grant.body_format) {
            .form => &form_headers,
            .json => &json_headers,
        },
        .body = writer.buffered(),
        .timeout_ms = grant.timeout_ms,
        .body_is_sensitive = true,
        .follow_redirects = false,
    };
    try request.validate();
    return request;
}

fn writeJsonBody(
    writer: *std.Io.Writer,
    grant: RefreshGrant,
    refresh_credential: *const keychain.Credential,
) std.Io.Writer.Error!void {
    try writer.writeAll("{\"grant_type\":\"refresh_token\",\"refresh_token\":\"");
    var index: usize = 0;
    while (index < refresh_credential.length()) : (index += 1) {
        try writeJsonStringByte(writer, refresh_credential.byteAt(index));
    }
    try writer.writeAll("\",\"client_id\":\"");
    for (grant.client_id) |byte| try writeJsonStringByte(writer, byte);
    if (grant.scope) |scope| {
        try writer.writeAll("\",\"scope\":\"");
        for (scope) |byte| try writeJsonStringByte(writer, byte);
    }
    try writer.writeAll("\"}");
}

fn writeJsonStringByte(writer: *std.Io.Writer, byte: u8) std.Io.Writer.Error!void {
    switch (byte) {
        '"' => try writer.writeAll("\\\""),
        '\\' => try writer.writeAll("\\\\"),
        0x08 => try writer.writeAll("\\b"),
        0x0c => try writer.writeAll("\\f"),
        '\n' => try writer.writeAll("\\n"),
        '\r' => try writer.writeAll("\\r"),
        '\t' => try writer.writeAll("\\t"),
        0x00...0x07, 0x0b, 0x0e...0x1f => try writer.print("\\u00{X:0>2}", .{byte}),
        else => try writer.writeByte(byte),
    }
}

fn writeFormBody(
    writer: *std.Io.Writer,
    grant: RefreshGrant,
    refresh_credential: *const keychain.Credential,
) std.Io.Writer.Error!void {
    try writer.writeAll("grant_type=refresh_token&client_id=");
    try writeFormEncoded(writer, grant.client_id);
    if (grant.scope) |scope| {
        try writer.writeAll("&scope=");
        try writeFormEncoded(writer, scope);
    }
    try writer.writeAll("&refresh_token=");
    var index: usize = 0;
    while (index < refresh_credential.length()) : (index += 1) {
        try writeFormEncodedByte(writer, refresh_credential.byteAt(index));
    }
}

fn writeFormEncoded(writer: *std.Io.Writer, text: []const u8) std.Io.Writer.Error!void {
    for (text) |byte| try writeFormEncodedByte(writer, byte);
}

fn writeFormEncodedByte(writer: *std.Io.Writer, byte: u8) std.Io.Writer.Error!void {
    if (isFormUnreserved(byte)) {
        try writer.writeByte(byte);
    } else {
        try writer.print("%{X:0>2}", .{byte});
    }
}

fn isFormUnreserved(byte: u8) bool {
    return switch (byte) {
        'a'...'z', 'A'...'Z', '0'...'9', '-', '.', '_', '~' => true,
        else => false,
    };
}

pub const ParseError = error{
    ResponseTooLarge,
    MalformedResponse,
    MissingAccessToken,

    ValueTooLong,
    NestingTooDeep,
};

pub const TokenType = enum { bearer, unspecified, other };

pub const RefreshPayload = struct {
    access: keychain.Credential = .empty,

    rotated_refresh: ?keychain.Credential = null,
    expires_in_s: ?i64 = null,
    token_type: TokenType = .unspecified,

    saw_empty_rotated_refresh: bool = false,

    pub fn wipe(self: *RefreshPayload) void {
        self.access.wipe();
        if (self.rotated_refresh) |*credential| credential.wipe();
        self.* = .{};
    }

    pub fn rotatedRefresh(self: *const RefreshPayload) ?*const keychain.Credential {
        if (self.rotated_refresh == null) return null;
        return &self.rotated_refresh.?;
    }

    pub fn expiresAt(self: *const RefreshPayload, now_unix_s: i64) ?i64 {
        return expiresAtUnix(now_unix_s, self.expires_in_s);
    }

    pub fn format(self: *const RefreshPayload, writer: *std.Io.Writer) std.Io.Writer.Error!void {
        try writer.print("access={f} rotated={} type={s}", .{
            &self.access,
            self.rotated_refresh != null,
            @tagName(self.token_type),
        });
        if (self.expires_in_s) |lifetime| try writer.print(" expires_in={d}s", .{lifetime});
    }
};

pub fn parseRefreshResponse(body: []const u8, out: *RefreshPayload) ParseError!void {
    out.* = .{};
    errdefer out.wipe();
    if (body.len > max_response_body_bytes) return error.ResponseTooLarge;

    var nesting_stack: [256]u8 = undefined;
    var nesting: std.heap.FixedBufferAllocator = .init(&nesting_stack);
    var scanner = std.json.Scanner.initCompleteInput(nesting.allocator(), body);
    defer scanner.deinit();

    switch (try nextToken(&scanner)) {
        .object_begin => {},
        else => return error.MalformedResponse,
    }

    var have_access = false;
    var key_buffer: [max_json_key_bytes]u8 = undefined;
    while (true) {
        switch (peekType(&scanner)) {
            .object_end => {
                _ = try nextToken(&scanner);
                break;
            },
            .string => {},
            else => return error.MalformedResponse,
        }

        var key_sink: BufferSink = .{ .buffer = &key_buffer };
        try readString(&scanner, &key_sink);
        const key = key_buffer[0..key_sink.len];
        const value_type = peekType(&scanner);

        if (key_sink.truncated) {
            try skipValue(&scanner);
        } else if (std.mem.eql(u8, key, "access_token")) {
            if (have_access or value_type != .string) {
                try skipValue(&scanner);
            } else {
                out.access.reset();
                var sink: CredentialSink = .{ .credential = &out.access };
                try readString(&scanner, &sink);
                have_access = true;
            }
        } else if (std.mem.eql(u8, key, "refresh_token")) {
            const already_seen = out.rotated_refresh != null or out.saw_empty_rotated_refresh;
            if (already_seen or (value_type != .string and value_type != .null)) {
                try skipValue(&scanner);
            } else if (value_type == .null) {
                _ = try nextToken(&scanner);
                out.saw_empty_rotated_refresh = true;
            } else {
                out.rotated_refresh = keychain.Credential.empty;
                const credential = &out.rotated_refresh.?;
                credential.reset();
                var sink: CredentialSink = .{ .credential = credential };
                try readString(&scanner, &sink);
                if (credential.isEmpty()) {
                    credential.wipe();
                    out.rotated_refresh = null;
                    out.saw_empty_rotated_refresh = true;
                }
            }
        } else if (std.mem.eql(u8, key, "expires_in")) {
            if (out.expires_in_s != null) {
                try skipValue(&scanner);
            } else {
                out.expires_in_s = try readLifetime(&scanner, value_type);
            }
        } else if (std.mem.eql(u8, key, "token_type")) {
            if (value_type != .string or out.token_type != .unspecified) {
                try skipValue(&scanner);
            } else {
                var type_buffer: [32]u8 = undefined;
                var sink: BufferSink = .{ .buffer = &type_buffer };
                try readString(&scanner, &sink);
                const text = type_buffer[0..sink.len];
                out.token_type = if (!sink.truncated and std.ascii.eqlIgnoreCase(text, "bearer")) .bearer else .other;
            }
        } else {
            try skipValue(&scanner);
        }
    }

    switch (try nextToken(&scanner)) {
        .end_of_document => {},
        else => return error.MalformedResponse,
    }
    if (!have_access or out.access.isEmpty()) return error.MissingAccessToken;
}

pub const OAuthErrorCode = enum {
    invalid_request,
    invalid_client,
    invalid_grant,
    unauthorized_client,
    unsupported_grant_type,
    invalid_scope,
    unrecognized,

    pub fn requiresReauth(self: OAuthErrorCode) bool {
        return switch (self) {
            .invalid_grant, .invalid_client, .unauthorized_client => true,
            else => false,
        };
    }
};

pub fn parseErrorCode(body: []const u8) ?OAuthErrorCode {
    if (body.len > max_response_body_bytes) return null;

    var nesting_stack: [256]u8 = undefined;
    var nesting: std.heap.FixedBufferAllocator = .init(&nesting_stack);
    var scanner = std.json.Scanner.initCompleteInput(nesting.allocator(), body);
    defer scanner.deinit();

    switch (nextToken(&scanner) catch return null) {
        .object_begin => {},
        else => return null,
    }

    var key_buffer: [max_json_key_bytes]u8 = undefined;
    while (true) {
        switch (peekType(&scanner)) {
            .string => {},
            else => return null,
        }
        var key_sink: BufferSink = .{ .buffer = &key_buffer };
        readString(&scanner, &key_sink) catch return null;
        const is_error_key = !key_sink.truncated and std.mem.eql(u8, key_buffer[0..key_sink.len], "error");
        if (!is_error_key or peekType(&scanner) != .string) {
            skipValue(&scanner) catch return null;
            continue;
        }
        var code_buffer: [64]u8 = undefined;
        var code_sink: BufferSink = .{ .buffer = &code_buffer };
        readString(&scanner, &code_sink) catch return null;
        if (code_sink.truncated) return .unrecognized;
        const code = std.meta.stringToEnum(OAuthErrorCode, code_buffer[0..code_sink.len]) orelse return .unrecognized;
        return if (code == .unrecognized) .unrecognized else code;
    }
}

const BufferSink = struct {
    buffer: []u8,
    len: usize = 0,
    truncated: bool = false,

    fn push(self: *BufferSink, chunk: []const u8) ParseError!void {
        const room = self.buffer.len - self.len;
        if (chunk.len > room) {
            @memcpy(self.buffer[self.len..], chunk[0..room]);
            self.len = self.buffer.len;
            self.truncated = true;
            return;
        }
        @memcpy(self.buffer[self.len..][0..chunk.len], chunk);
        self.len += chunk.len;
    }
};

const CredentialSink = struct {
    credential: *keychain.Credential,

    fn push(self: CredentialSink, chunk: []const u8) ParseError!void {
        self.credential.append(chunk) catch return error.ValueTooLong;
    }
};

fn nextToken(scanner: *std.json.Scanner) ParseError!std.json.Token {
    return scanner.next() catch |err| switch (err) {
        error.OutOfMemory => error.NestingTooDeep,
        error.SyntaxError, error.UnexpectedEndOfInput, error.BufferUnderrun => error.MalformedResponse,
    };
}

fn peekType(scanner: *std.json.Scanner) std.json.TokenType {
    return scanner.peekNextTokenType() catch .end_of_document;
}

fn readString(scanner: *std.json.Scanner, sink: anytype) ParseError!void {
    while (true) {
        switch (try nextToken(scanner)) {
            .string => |chunk| return sink.push(chunk),
            .partial_string => |chunk| try sink.push(chunk),
            .partial_string_escaped_1 => |chunk| try sink.push(chunk[0..]),
            .partial_string_escaped_2 => |chunk| try sink.push(chunk[0..]),
            .partial_string_escaped_3 => |chunk| try sink.push(chunk[0..]),
            .partial_string_escaped_4 => |chunk| try sink.push(chunk[0..]),
            else => return error.MalformedResponse,
        }
    }
}

fn readNumber(scanner: *std.json.Scanner, sink: *BufferSink) ParseError!void {
    while (true) {
        switch (try nextToken(scanner)) {
            .number => |chunk| return sink.push(chunk),
            .partial_number => |chunk| try sink.push(chunk),
            else => return error.MalformedResponse,
        }
    }
}

fn readLifetime(scanner: *std.json.Scanner, value_type: std.json.TokenType) ParseError!?i64 {
    var buffer: [32]u8 = undefined;
    var sink: BufferSink = .{ .buffer = &buffer };
    switch (value_type) {
        .number => try readNumber(scanner, &sink),
        .string => try readString(scanner, &sink),
        else => {
            try skipValue(scanner);
            return null;
        },
    }
    if (sink.truncated) return null;
    const text = buffer[0..sink.len];
    if (std.fmt.parseInt(i64, text, 10)) |seconds| return seconds else |_| {}
    const float = std.fmt.parseFloat(f64, text) catch return null;
    if (!std.math.isFinite(float)) return null;
    const truncated = @trunc(float);
    if (truncated > @as(f64, std.math.maxInt(i32)) or truncated < @as(f64, std.math.minInt(i32))) return null;
    return @intFromFloat(truncated);
}

fn skipValue(scanner: *std.json.Scanner) ParseError!void {
    var depth: usize = 0;
    while (true) {
        switch (try nextToken(scanner)) {
            .object_begin, .array_begin => {
                depth += 1;
                if (depth > max_json_depth) return error.NestingTooDeep;
            },
            .object_end, .array_end => {
                depth -= 1;
                if (depth == 0) return;
            },
            .partial_number,
            .partial_string,
            .partial_string_escaped_1,
            .partial_string_escaped_2,
            .partial_string_escaped_3,
            .partial_string_escaped_4,
            => {},
            .number, .string, .true, .false, .null => if (depth == 0) return,

            .allocated_number, .allocated_string, .end_of_document => return error.MalformedResponse,
        }
    }
}

pub const public_code_sign_in_required = "sign-in-required";
pub const public_code_access_denied = "access-denied";
pub const public_code_rate_limited = "rate-limited";
pub const public_code_timeout = "refresh-timeout";
pub const public_code_network = "network-unavailable";
pub const public_code_malformed = "malformed-response";
pub const public_code_provider_unavailable = "provider-unavailable";
pub const public_code_rejected = "refresh-rejected";
pub const public_code_canceled = "refresh-canceled";
pub const public_code_store_unavailable = "credential-store-unavailable";
pub const public_code_store_repair_required = "keychain-access-repair-required";
pub const public_code_store_denied = "credential-store-denied";
pub const public_code_store_corrupt = "credential-store-corrupt";
pub const public_code_store_full = "credential-store-full";
pub const public_code_store_io = "credential-store-io";

pub const public_codes = [_][]const u8{
    public_code_sign_in_required,
    public_code_access_denied,
    public_code_rate_limited,
    public_code_timeout,
    public_code_network,
    public_code_malformed,
    public_code_provider_unavailable,
    public_code_rejected,
    public_code_canceled,
    public_code_store_unavailable,
    public_code_store_repair_required,
    public_code_store_denied,
    public_code_store_corrupt,
    public_code_store_full,
    public_code_store_io,
};

pub fn isPublicCode(code: []const u8) bool {
    for (public_codes) |known| {
        if (std.mem.eql(u8, code, known)) return true;
    }
    return false;
}

pub fn refreshErrorFromStatus(status: u16, error_code: ?OAuthErrorCode) ?domain.RefreshError {
    if (status == 200) return null;
    if (status >= 200 and status < 300) {
        return .{ .kind = .malformed_response, .public_code = public_code_malformed, .retryable = false };
    }
    if (status >= 300 and status < 400) {
        return .{ .kind = .unknown, .public_code = public_code_rejected, .retryable = false };
    }
    switch (status) {
        400 => {
            const reauth = if (error_code) |code| code.requiresReauth() else false;
            if (reauth) return .{ .kind = .authentication, .public_code = public_code_sign_in_required, .retryable = false };
            return .{ .kind = .unknown, .public_code = public_code_rejected, .retryable = false };
        },
        401 => return .{ .kind = .authentication, .public_code = public_code_sign_in_required, .retryable = false },
        403 => return .{ .kind = .authentication, .public_code = public_code_access_denied, .retryable = false },
        408 => return .{ .kind = .timeout, .public_code = public_code_timeout, .retryable = true },
        429 => return .{ .kind = .rate_limited, .public_code = public_code_rate_limited, .retryable = true },
        else => {},
    }
    if (status >= 500 and status < 600) {
        return .{ .kind = .provider_unavailable, .public_code = public_code_provider_unavailable, .retryable = true };
    }
    return .{ .kind = .unknown, .public_code = public_code_rejected, .retryable = false };
}

pub fn refreshErrorFromTransport(err: TransportError) domain.RefreshError {
    return switch (err) {
        error.Timeout => .{ .kind = .timeout, .public_code = public_code_timeout, .retryable = true },

        error.Network, error.Tls => .{ .kind = .network, .public_code = public_code_network, .retryable = true },
        error.ResponseTooLarge => .{ .kind = .malformed_response, .public_code = public_code_malformed, .retryable = false },
        error.RequestRejected => .{ .kind = .unknown, .public_code = public_code_rejected, .retryable = false },
        error.Canceled => .{ .kind = .unknown, .public_code = public_code_canceled, .retryable = true },
        error.Unsupported => .{ .kind = .provider_unavailable, .public_code = public_code_provider_unavailable, .retryable = false },
    };
}

pub fn refreshErrorFromParse(err: ParseError) domain.RefreshError {
    return switch (err) {
        error.MissingAccessToken => .{ .kind = .authentication, .public_code = public_code_sign_in_required, .retryable = false },
        error.ResponseTooLarge, error.MalformedResponse, error.ValueTooLong, error.NestingTooDeep => .{
            .kind = .malformed_response,
            .public_code = public_code_malformed,
            .retryable = false,
        },
    };
}

pub fn refreshErrorFromStore(err: keychain.StoreError) domain.RefreshError {
    return switch (err) {
        error.Unsupported => .{ .kind = .persistence, .public_code = public_code_store_unavailable, .retryable = false },

        error.NotFound => .{ .kind = .authentication, .public_code = public_code_sign_in_required, .retryable = false },
        error.AccessDenied => .{ .kind = .persistence, .public_code = public_code_store_denied, .retryable = true },
        error.RepairRequired => .{ .kind = .persistence, .public_code = public_code_store_repair_required, .retryable = false },
        error.Unavailable => .{ .kind = .persistence, .public_code = public_code_store_unavailable, .retryable = true },
        error.ValueTooLarge, error.Corrupt => .{ .kind = .persistence, .public_code = public_code_store_corrupt, .retryable = false },
        error.StoreFull => .{ .kind = .persistence, .public_code = public_code_store_full, .retryable = false },
        error.Io => .{ .kind = .persistence, .public_code = public_code_store_io, .retryable = true },
    };
}

pub fn refreshErrorFromBuild(err: BuildError) domain.RefreshError {
    return switch (err) {
        error.MissingRefreshCredential => .{ .kind = .authentication, .public_code = public_code_sign_in_required, .retryable = false },
        else => .{ .kind = .unknown, .public_code = public_code_rejected, .retryable = false },
    };
}
