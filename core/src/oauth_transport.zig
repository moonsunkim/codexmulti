const std = @import("std");

pub const default_timeout_ms: u32 = 15_000;
pub const min_timeout_ms: u32 = 1_000;
pub const max_timeout_ms: u32 = 60_000;

pub const max_url_bytes: usize = 512;
pub const max_header_count: usize = 12;
pub const max_header_name_bytes: usize = 64;
pub const max_header_value_bytes: usize = 512;
pub const max_request_body_bytes: usize = 8 * 1024;
pub const max_response_body_bytes: usize = 64 * 1024;
pub const max_redacted_target_bytes: usize = 160;
pub const max_client_id_bytes: usize = 128;
pub const max_scope_bytes: usize = 256;

pub const max_json_depth: usize = 8;

pub const max_json_key_bytes: usize = 48;

pub const default_refresh_skew_s: i64 = 120;
pub const max_refresh_skew_s: i64 = 3600;

pub const Method = enum {
    get,
    post,

    pub fn name(self: Method) []const u8 {
        return switch (self) {
            .get => "GET",
            .post => "POST",
        };
    }
};

pub const Header = struct {
    name: []const u8,
    value: []const u8,

    sensitive: bool = false,
};

const sensitive_header_names = [_][]const u8{
    "authorization",
    "proxy-authorization",
    "authentication",
    "cookie",
    "set-cookie",
    "api-key",
    "x-api-key",
};

pub fn headerNameIsSensitive(name: []const u8) bool {
    for (sensitive_header_names) |candidate| {
        if (std.ascii.eqlIgnoreCase(name, candidate)) return true;
    }
    return false;
}
pub const RequestError = error{
    InvalidUrl,

    InsecureUrl,
    UrlTooLong,
    TooManyHeaders,
    InvalidHeader,
    HeaderTooLong,

    SensitiveHeaderNotMarked,
    BodyTooLarge,
    InvalidTimeout,

    RedirectsWithSecretBody,
};

pub const Request = struct {
    method: Method,

    url: []const u8,
    headers: []const Header = &.{},
    body: []const u8 = &.{},
    timeout_ms: u32 = default_timeout_ms,

    body_is_sensitive: bool = false,

    follow_redirects: bool = false,

    pub fn validate(self: Request) RequestError!void {
        if (self.url.len == 0) return error.InvalidUrl;
        if (self.url.len > max_url_bytes) return error.UrlTooLong;
        if (!std.mem.startsWith(u8, self.url, "https://")) return error.InsecureUrl;
        if (self.url.len == "https://".len) return error.InvalidUrl;
        for (self.url) |byte| {
            if (!isLogSafeByte(byte)) return error.InvalidUrl;
        }
        if (self.headers.len > max_header_count) return error.TooManyHeaders;
        for (self.headers) |header| {
            if (header.name.len == 0) return error.InvalidHeader;
            if (header.name.len > max_header_name_bytes) return error.HeaderTooLong;
            if (header.value.len > max_header_value_bytes) return error.HeaderTooLong;
            for (header.name) |byte| {
                if (!isHeaderNameByte(byte)) return error.InvalidHeader;
            }
            for (header.value) |byte| {
                if (byte < 0x20 or byte == 0x7f) return error.InvalidHeader;
            }
            if (!header.sensitive and headerNameIsSensitive(header.name)) return error.SensitiveHeaderNotMarked;
        }
        if (self.body.len > max_request_body_bytes) return error.BodyTooLarge;
        if (self.timeout_ms < min_timeout_ms or self.timeout_ms > max_timeout_ms) return error.InvalidTimeout;
        if (self.body_is_sensitive and self.follow_redirects) return error.RedirectsWithSecretBody;
    }

    pub fn redact(self: Request) RedactedRequest {
        var descriptor: RedactedRequest = .{
            .method = self.method,
            .body_is_sensitive = self.body_is_sensitive,
            .body_bytes = if (self.body_is_sensitive) 0 else @intCast(self.body.len),
            .timeout_ms = self.timeout_ms,
            .header_count = @intCast(@min(self.headers.len, max_header_count)),
        };
        for (self.headers) |header| {
            if (header.sensitive or headerNameIsSensitive(header.name)) descriptor.sensitive_header_count += 1;
        }
        var target: TargetWriter = .{ .buffer = descriptor.target_buffer[0..] };
        writeRedactedTarget(self.url, &target, &descriptor);
        descriptor.target_len = @intCast(target.len);
        descriptor.truncated = target.truncated;
        return descriptor;
    }

    pub fn format(self: Request, writer: *std.Io.Writer) std.Io.Writer.Error!void {
        const descriptor = self.redact();
        try descriptor.format(writer);
    }
};

pub const RedactedRequest = struct {
    method: Method,
    target_buffer: [max_redacted_target_bytes]u8 = @splat(0),
    target_len: u16 = 0,

    query_present: bool = false,
    truncated: bool = false,
    header_count: u8 = 0,
    sensitive_header_count: u8 = 0,

    body_bytes: u32 = 0,
    body_is_sensitive: bool = false,
    timeout_ms: u32 = default_timeout_ms,

    pub fn target(self: *const RedactedRequest) []const u8 {
        return self.target_buffer[0..self.target_len];
    }

    pub fn format(self: RedactedRequest, writer: *std.Io.Writer) std.Io.Writer.Error!void {
        const descriptor = self;
        try writer.print("{s} {s}", .{ descriptor.method.name(), descriptor.target_buffer[0..descriptor.target_len] });
        if (descriptor.truncated) try writer.writeAll("...");
        if (descriptor.query_present) try writer.writeAll("?<redacted>");
        try writer.print(" headers={d}({d} sensitive)", .{ descriptor.header_count, descriptor.sensitive_header_count });
        if (descriptor.body_is_sensitive) {
            try writer.writeAll(" body=<redacted>");
        } else {
            try writer.print(" body={d}b", .{descriptor.body_bytes});
        }
        try writer.print(" timeout={d}ms", .{descriptor.timeout_ms});
    }
};

const TargetWriter = struct {
    buffer: []u8,
    len: usize = 0,
    truncated: bool = false,

    fn push(self: *TargetWriter, text: []const u8) void {
        for (text) |byte| {
            if (self.len == self.buffer.len) {
                self.truncated = true;
                return;
            }
            self.buffer[self.len] = if (isLogSafeByte(byte)) byte else '.';
            self.len += 1;
        }
    }
};

fn writeRedactedTarget(url: []const u8, target: *TargetWriter, descriptor: *RedactedRequest) void {
    const scheme_end = if (std.mem.indexOf(u8, url, "://")) |index| index + 3 else 0;
    var cut = url.len;
    if (std.mem.indexOfScalarPos(u8, url, scheme_end, '?')) |index| cut = @min(cut, index);
    if (std.mem.indexOfScalarPos(u8, url, scheme_end, '#')) |index| cut = @min(cut, index);
    descriptor.query_present = cut < url.len;

    const path_start = std.mem.indexOfScalarPos(u8, url, scheme_end, '/') orelse cut;
    var authority_start = scheme_end;
    if (std.mem.indexOfScalarPos(u8, url, scheme_end, '@')) |at_index| {
        if (at_index < path_start and at_index < cut) authority_start = at_index + 1;
    }

    target.push(url[0..scheme_end]);
    if (authority_start < cut) target.push(url[authority_start..cut]);
}

pub fn isLogSafeByte(byte: u8) bool {
    return byte >= 0x21 and byte <= 0x7e and byte != '"' and byte != '\\';
}

fn isHeaderNameByte(byte: u8) bool {
    return switch (byte) {
        'a'...'z', 'A'...'Z', '0'...'9', '-', '_' => true,
        else => false,
    };
}

pub const Response = struct {
    status: u16,
    body: []const u8 = &.{},

    retry_after_s: ?u32 = null,

    pub fn isSuccess(self: Response) bool {
        return self.status >= 200 and self.status < 300;
    }

    pub fn format(self: Response, writer: *std.Io.Writer) std.Io.Writer.Error!void {
        try writer.print("status={d} body=<redacted>", .{self.status});
        if (self.retry_after_s) |seconds| try writer.print(" retry_after={d}s", .{seconds});
    }
};

pub const TransportError = error{
    Timeout,
    Network,
    Tls,

    ResponseTooLarge,

    RequestRejected,
    Canceled,

    Unsupported,
};

pub const HttpClient = struct {
    context: *anyopaque,
    vtable: *const VTable,

    pub const VTable = struct {
        send: *const fn (context: *anyopaque, request: Request, body_buffer: []u8) TransportError!Response,
    };

    pub fn send(self: HttpClient, request: Request, body_buffer: []u8) TransportError!Response {
        return self.vtable.send(self.context, request, body_buffer);
    }
};

var unwired_context: u8 = 0;
const unwired_vtable: HttpClient.VTable = .{ .send = unwiredSend };

fn unwiredSend(_: *anyopaque, _: Request, _: []u8) TransportError!Response {
    return error.Unsupported;
}

pub fn unwiredClient() HttpClient {
    return .{ .context = &unwired_context, .vtable = &unwired_vtable };
}

pub const FakeHttpClient = struct {
    pub const max_recorded_requests: usize = 8;

    pub const Reply = union(enum) {
        response: struct { status: u16, body: []const u8 = &.{}, retry_after_s: ?u32 = null },
        failure: TransportError,
    };

    replies: []const Reply = &.{},
    next_index: usize = 0,
    call_count: usize = 0,
    recorded: [max_recorded_requests]RedactedRequest = @splat(.{ .method = .post }),
    recorded_count: usize = 0,

    const vtable: HttpClient.VTable = .{ .send = send };

    pub fn client(self: *FakeHttpClient) HttpClient {
        return .{ .context = self, .vtable = &vtable };
    }

    pub fn requests(self: *const FakeHttpClient) []const RedactedRequest {
        return self.recorded[0..self.recorded_count];
    }

    fn send(context: *anyopaque, request: Request, body_buffer: []u8) TransportError!Response {
        const self: *FakeHttpClient = @ptrCast(@alignCast(context));
        self.call_count += 1;
        if (self.recorded_count < max_recorded_requests) {
            self.recorded[self.recorded_count] = request.redact();
            self.recorded_count += 1;
        }
        request.validate() catch return error.RequestRejected;
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
                    .body = body_buffer[0..scripted.body.len],
                    .retry_after_s = scripted.retry_after_s,
                };
            },
        }
    }
};

pub const max_retry_after_text_bytes: usize = 32;

pub const max_retry_after_s: u32 = 24 * 60 * 60;

pub const max_response_head_bytes: usize = 8 * 1024;

pub const response_transfer_buffer_bytes: usize = 4 * 1024;

pub const RetryAfterHeader = struct {
    bytes: [max_retry_after_text_bytes]u8 = @splat(0),
    len: u8 = 0,

    pub const absent: RetryAfterHeader = .{};

    pub fn init(value: []const u8) RetryAfterHeader {
        if (value.len == 0 or value.len > max_retry_after_text_bytes) return .absent;
        var header: RetryAfterHeader = .{};
        @memcpy(header.bytes[0..value.len], value);
        header.len = @intCast(value.len);
        return header;
    }

    pub fn text(self: *const RetryAfterHeader) []const u8 {
        return self.bytes[0..self.len];
    }

    pub fn seconds(self: *const RetryAfterHeader) ?u32 {
        const trimmed = std.mem.trim(u8, self.text(), " \t");

        if (trimmed.len == 0 or trimmed.len > 10) return null;
        for (trimmed) |byte| {
            if (!std.ascii.isDigit(byte)) return null;
        }
        const parsed = std.fmt.parseInt(u64, trimmed, 10) catch return null;
        return @intCast(@min(parsed, max_retry_after_s));
    }
};

pub const ExchangeResult = struct {
    status: u16,

    body_len: usize = 0,
    retry_after: RetryAfterHeader = .absent,
};

pub const Exchange = struct {
    context: *anyopaque,
    vtable: *const VTable,

    pub const VTable = struct {
        perform: *const fn (context: *anyopaque, request: Request, body_buffer: []u8) TransportError!ExchangeResult,
    };

    pub fn perform(self: Exchange, request: Request, body_buffer: []u8) TransportError!ExchangeResult {
        return self.vtable.perform(self.context, request, body_buffer);
    }
};

pub const HttpTransport = struct {
    exchange: Exchange,

    const vtable: HttpClient.VTable = .{ .send = send };

    pub fn init(exchange: Exchange) HttpTransport {
        return .{ .exchange = exchange };
    }

    pub fn client(self: *HttpTransport) HttpClient {
        return .{ .context = self, .vtable = &vtable };
    }

    fn send(context: *anyopaque, request: Request, body_buffer: []u8) TransportError!Response {
        const self: *HttpTransport = @ptrCast(@alignCast(context));

        request.validate() catch return error.RequestRejected;

        if (request.follow_redirects) return error.RequestRejected;

        const result = try self.exchange.perform(request, body_buffer);

        if (result.body_len > body_buffer.len) return error.ResponseTooLarge;
        return .{
            .status = result.status,
            .body = body_buffer[0..result.body_len],
            .retry_after_s = result.retry_after.seconds(),
        };
    }
};

pub fn runBounded(
    io: std.Io,
    timeout_ms: u32,
    comptime task: anytype,
    args: std.meta.ArgsTuple(@TypeOf(task)),
) TransportError!ExchangeResult {
    const Bounded = struct {
        fn run(inner: std.Io, event: *std.Io.Event, inner_args: std.meta.ArgsTuple(@TypeOf(task))) TransportError!ExchangeResult {
            defer event.set(inner);
            return @call(.auto, task, inner_args);
        }
    };

    var finished: std.Io.Event = .unset;

    var future = io.concurrent(Bounded.run, .{ io, &finished, args }) catch return error.Network;

    const deadline: std.Io.Timeout = (std.Io.Timeout{
        .duration = .{ .raw = .fromMilliseconds(timeout_ms), .clock = .awake },
    }).toDeadline(io);

    while (true) {
        if (finished.waitTimeout(io, deadline)) |_| break else |err| switch (err) {
            error.Canceled => {
                _ = future.cancel(io) catch {};
                return error.Canceled;
            },

            error.Timeout => {
                if (finished.isSet()) break;
                if (deadlinePassed(io, deadline)) {
                    _ = future.cancel(io) catch {};
                    return error.Timeout;
                }
            },
        }
    }
    return future.await(io);
}

fn deadlinePassed(io: std.Io, deadline: std.Io.Timeout) bool {
    const timestamp = switch (deadline) {
        .deadline => |value| value,
        else => return false,
    };
    return timestamp.durationFromNow(io).raw.nanoseconds <= 0;
}

pub const TlsExchange = struct {
    allocator: std.mem.Allocator,
    io: std.Io,

    const vtable: Exchange.VTable = .{ .perform = perform };

    pub fn init(allocator: std.mem.Allocator, io: std.Io) TlsExchange {
        return .{ .allocator = allocator, .io = io };
    }

    pub fn exchange(self: *TlsExchange) Exchange {
        return .{ .context = self, .vtable = &vtable };
    }

    fn perform(context: *anyopaque, request: Request, body_buffer: []u8) TransportError!ExchangeResult {
        const self: *TlsExchange = @ptrCast(@alignCast(context));

        request.validate() catch return error.RequestRejected;
        if (request.follow_redirects) return error.RequestRejected;
        return runBounded(self.io, request.timeout_ms, exchangeOnce, .{
            self.allocator,
            self.io,
            request,
            body_buffer,
        });
    }
};

fn exchangeOnce(
    allocator: std.mem.Allocator,
    io: std.Io,
    request: Request,
    body_buffer: []u8,
) TransportError!ExchangeResult {
    const uri = std.Uri.parse(request.url) catch return error.RequestRejected;
    if (!std.mem.eql(u8, uri.scheme, "https")) return error.RequestRejected;

    if (uri.user != null or uri.password != null) return error.RequestRejected;

    var client_headers: std.http.Client.Request.Headers = .{
        .accept_encoding = .{ .override = "identity" },
    };
    var extra_headers: [max_header_count]std.http.Header = undefined;
    var extra_count: usize = 0;
    for (request.headers) |header| {
        if (std.ascii.eqlIgnoreCase(header.name, "host")) {
            client_headers.host = .{ .override = header.value };
        } else if (std.ascii.eqlIgnoreCase(header.name, "authorization")) {
            client_headers.authorization = .{ .override = header.value };
        } else if (std.ascii.eqlIgnoreCase(header.name, "user-agent")) {
            client_headers.user_agent = .{ .override = header.value };
        } else if (std.ascii.eqlIgnoreCase(header.name, "connection")) {
            client_headers.connection = .{ .override = header.value };
        } else if (std.ascii.eqlIgnoreCase(header.name, "content-type")) {
            client_headers.content_type = .{ .override = header.value };
        } else if (std.ascii.eqlIgnoreCase(header.name, "accept-encoding")) {
            if (!std.ascii.eqlIgnoreCase(std.mem.trim(u8, header.value, " \t"), "identity")) {
                return error.RequestRejected;
            }
        } else {
            extra_headers[extra_count] = .{ .name = header.name, .value = header.value };
            extra_count += 1;
        }
    }

    var client: std.http.Client = .{
        .allocator = allocator,
        .io = io,
        .read_buffer_size = max_response_head_bytes,
    };
    defer client.deinit();

    var http_request = client.request(httpMethod(request.method), uri, .{
        .redirect_behavior = .not_allowed,

        .keep_alive = false,
        .headers = client_headers,
        .extra_headers = extra_headers[0..extra_count],
    }) catch |err| return transportErrorFromRequest(err);
    defer http_request.deinit();

    switch (request.method) {
        .get => {
            if (request.body.len != 0) return error.RequestRejected;
            http_request.sendBodiless() catch return error.Network;
        },
        .post => {
            http_request.transfer_encoding = .{ .content_length = request.body.len };

            var send_buffer: [max_request_body_bytes]u8 = undefined;
            defer std.crypto.secureZero(u8, &send_buffer);
            var body_writer = http_request.sendBodyUnflushed(&send_buffer) catch return error.Network;
            body_writer.writer.writeAll(request.body) catch return error.Network;
            body_writer.end() catch return error.Network;
            (http_request.connection orelse return error.Network).flush() catch return error.Network;
        },
    }

    var redirect_buffer: [0]u8 = undefined;
    var response = http_request.receiveHead(&redirect_buffer) catch |err|
        return transportErrorFromReceive(err, http_request.connection);

    const status: u16 = @intFromEnum(response.head.status);

    var retry_after: RetryAfterHeader = .absent;
    var headers = std.http.HeaderIterator.init(response.head.bytes);
    while (headers.next()) |header| {
        if (std.ascii.eqlIgnoreCase(header.name, "retry-after")) {
            retry_after = .init(header.value);
            break;
        }
    }

    if (response.head.content_encoding != .identity) return error.Network;

    if (response.head.content_length) |length| {
        if (length > body_buffer.len) return error.ResponseTooLarge;
    }

    var transfer_buffer: [response_transfer_buffer_bytes]u8 = undefined;
    const body_reader = response.reader(&transfer_buffer);
    var body_writer = std.Io.Writer.fixed(body_buffer);
    const body_len = body_reader.streamRemaining(&body_writer) catch |err| switch (err) {
        error.WriteFailed => return error.ResponseTooLarge,
        error.ReadFailed => return transportErrorFromConnection(http_request.connection),
    };
    return .{ .status = status, .body_len = body_len, .retry_after = retry_after };
}

fn httpMethod(method: Method) std.http.Method {
    return switch (method) {
        .get => .GET,
        .post => .POST,
    };
}

fn isTlsError(err: anyerror) bool {
    inline for (@typeInfo(std.crypto.tls.Client.ReadError).error_set.?) |candidate| {
        if (err == @field(anyerror, candidate.name)) return true;
    }
    return false;
}

fn transportErrorFromConnection(connection: ?*std.http.Client.Connection) TransportError {
    const active = connection orelse return error.Network;
    const detail = active.getReadError() orelse return error.Network;
    return if (isTlsError(detail)) error.Tls else error.Network;
}

fn transportErrorFromRequest(err: std.http.Client.RequestError) TransportError {
    return switch (err) {
        error.TlsInitializationFailed, error.CertificateBundleLoadFailure => error.Tls,
        error.UnsupportedUriScheme, error.UriMissingHost => error.RequestRejected,
        error.Canceled => error.Canceled,
        else => error.Network,
    };
}

fn transportErrorFromReceive(
    err: std.http.Client.Request.ReceiveHeadError,
    connection: ?*std.http.Client.Connection,
) TransportError {
    return switch (err) {
        error.TlsInitializationFailed, error.CertificateBundleLoadFailure => error.Tls,

        error.TooManyHttpRedirects,
        error.RedirectRequiresResend,
        error.HttpRedirectLocationMissing,
        error.HttpRedirectLocationOversize,
        error.HttpRedirectLocationInvalid,
        error.UnsupportedUriScheme,
        error.UriMissingHost,
        => error.RequestRejected,
        error.Canceled => error.Canceled,
        error.ReadFailed => transportErrorFromConnection(connection),
        else => error.Network,
    };
}

pub const TlsTransport = struct {
    backend: TlsExchange,
    transport: HttpTransport = undefined,

    pub fn init(allocator: std.mem.Allocator, io: std.Io) TlsTransport {
        return .{ .backend = .init(allocator, io) };
    }

    pub fn client(self: *TlsTransport) HttpClient {
        self.transport = .init(self.backend.exchange());
        return self.transport.client();
    }
};
