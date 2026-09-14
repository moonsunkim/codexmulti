const std = @import("std");
const account_registry = @import("account_registry.zig");
const domain = @import("domain.zig");
const runtime_paths = @import("runtime_paths.zig");

pub const max_response_body_bytes: usize = 64 * 1024;
pub const max_response_head_bytes: usize = 8 * 1024;
pub const response_transfer_buffer_bytes: usize = 8 * 1024;
pub const max_request_body_bytes: usize = 256;
pub const max_request_path_bytes: usize = 192;
pub const max_base_url_bytes: usize = 32;
pub const max_proxy_name_bytes: usize = 64;
pub const max_label_bytes: usize = account_registry.max_label_bytes;
pub const max_refresh_error_kind_bytes: usize = 64;
pub const default_timeout_ms: u32 = 5_000;

pub fn BoundedText(comptime capacity: usize) type {
    return struct {
        bytes: [capacity]u8 = @splat(0),
        len: u16 = 0,

        const Self = @This();

        pub fn init(value: []const u8) error{TextTooLong}!Self {
            if (value.len > capacity) return error.TextTooLong;
            var result: Self = .{};
            @memcpy(result.bytes[0..value.len], value);
            result.len = @intCast(value.len);
            return result;
        }

        pub fn slice(self: *const Self) []const u8 {
            return self.bytes[0..self.len];
        }

        pub fn eql(self: *const Self, value: []const u8) bool {
            return std.mem.eql(u8, self.slice(), value);
        }
    };
}

pub const BaseUrl = struct {
    text: BoundedText(max_base_url_bytes),
    port: u16,

    pub fn init(value: []const u8) error{InvalidBaseUrl}!BaseUrl {
        const prefix = "http://127.0.0.1:";
        if (!std.mem.startsWith(u8, value, prefix)) return error.InvalidBaseUrl;
        if (value.len <= prefix.len or value.len > max_base_url_bytes) return error.InvalidBaseUrl;
        const port_text = value[prefix.len..];
        if (port_text.len > 1 and port_text[0] == '0') return error.InvalidBaseUrl;
        for (port_text) |byte| if (!std.ascii.isDigit(byte)) return error.InvalidBaseUrl;
        const port = std.fmt.parseInt(u16, port_text, 10) catch return error.InvalidBaseUrl;
        if (port == 0) return error.InvalidBaseUrl;
        return .{
            .text = BoundedText(max_base_url_bytes).init(value) catch return error.InvalidBaseUrl,
            .port = port,
        };
    }

    pub fn slice(self: *const BaseUrl) []const u8 {
        return self.text.slice();
    }
};

pub const Method = enum { get, post };

pub const Request = struct {
    method: Method,
    base_url: []const u8,
    path: []const u8,
    body: []const u8 = "",
    content_type_json: bool = false,
    config_path: []const u8 = "",
    timeout_ms: u32 = default_timeout_ms,
};

pub const ExchangeResult = struct {
    status: u16,
    body_len: usize,
};

pub const TransportError = error{
    RequestRejected,
    Network,
    Timeout,
    Canceled,
    ResponseTooLarge,
    InvalidResponse,
};

pub const Exchange = struct {
    context: *anyopaque,
    vtable: *const VTable,

    pub const VTable = struct {
        perform: *const fn (*anyopaque, Request, []u8) TransportError!ExchangeResult,
    };

    pub fn perform(self: Exchange, request: Request, response_buffer: []u8) TransportError!ExchangeResult {
        return self.vtable.perform(self.context, request, response_buffer);
    }
};

var unwired_exchange_context: u8 = 0;
const unwired_exchange_vtable: Exchange.VTable = .{ .perform = unwiredPerform };

fn unwiredPerform(_: *anyopaque, _: Request, _: []u8) TransportError!ExchangeResult {
    return error.Network;
}

pub fn unwiredExchange() Exchange {
    return .{ .context = &unwired_exchange_context, .vtable = &unwired_exchange_vtable };
}

pub const AccountState = enum { ready, cooldown, paused, invalid, refreshing };

pub const RawAccount = struct {
    name: BoundedText(max_proxy_name_bytes) = .{},
    label: BoundedText(max_label_bytes) = .{},
    has_label: bool = false,
    auth_file: BoundedText(runtime_paths.max_path_bytes) = .{},
    has_auth_file: bool = false,
    state: AccountState = .ready,
    cooldown_until_unix_s: ?i64 = null,
    token_expires_at_unix_s: ?i64 = null,
    token_refresh_last_ok_at_unix_s: ?i64 = null,
    token_refresh_last_error: BoundedText(max_refresh_error_kind_bytes) = .{},
    has_token_refresh_last_error: bool = false,
    token_refresh_next_attempt_at_unix_s: ?i64 = null,
    in_flight: u32 = 0,
};

pub const Status = struct {
    version: u8,
    config_path: BoundedText(runtime_paths.max_path_bytes) = .{},
    has_config_path: bool = false,
    active: BoundedText(max_proxy_name_bytes) = .{},
    has_active: bool = false,
    cursor: BoundedText(max_proxy_name_bytes) = .{},
    in_flight: u32 = 0,
    accounts: [account_registry.max_accounts]RawAccount = @splat(.{}),
    account_count: u8 = 0,

    pub fn accountCount(self: *const Status) usize {
        return self.account_count;
    }

    pub fn accountAt(self: *const Status, index: usize) ?*const RawAccount {
        if (index >= self.account_count) return null;
        return &self.accounts[index];
    }

    pub fn accountSlice(self: *const Status) []const RawAccount {
        return self.accounts[0..self.account_count];
    }
};

pub const AppAccount = struct {
    app_id: []const u8,
    storage_key: []const u8,
    label: []const u8,
    provider: domain.Provider,
    enabled: bool,
    connected: bool,

    pub fn eligible(self: AppAccount) bool {
        return self.provider == .codex and self.enabled and self.connected;
    }
};

pub const MappedAccount = struct {
    proxy_name: BoundedText(max_proxy_name_bytes) = .{},
    app_id: BoundedText(account_registry.max_id_bytes) = .{},
    storage_key: BoundedText(account_registry.max_storage_key_bytes) = .{},
    label: BoundedText(max_label_bytes) = .{},
    state: AccountState = .ready,
    cooldown_until_unix_s: ?i64 = null,
    token_expires_at_unix_s: ?i64 = null,
    token_refresh_last_ok_at_unix_s: ?i64 = null,
    token_refresh_last_error: BoundedText(max_refresh_error_kind_bytes) = .{},
    has_token_refresh_last_error: bool = false,
    token_refresh_next_attempt_at_unix_s: ?i64 = null,
    in_flight: u32 = 0,
    active: bool = false,
    mapped: bool = false,
};

pub const MappedStatus = struct {
    api_version: u8 = 2,
    in_flight: u32 = 0,
    accounts: [account_registry.max_accounts]MappedAccount = @splat(.{}),
    account_count: u8 = 0,
    active_index: ?usize = null,

    pub fn accountCount(self: *const MappedStatus) usize {
        return self.account_count;
    }

    pub fn accountAt(self: *const MappedStatus, index: usize) ?*const MappedAccount {
        if (index >= self.account_count) return null;
        return &self.accounts[index];
    }

    pub fn accountSlice(self: *const MappedStatus) []const MappedAccount {
        return self.accounts[0..self.account_count];
    }

    pub fn requireMapped(self: *const MappedStatus, app_id: []const u8) error{UnmappedAccount}!*const MappedAccount {
        for (self.accountSlice()) |*account| {
            if (account.mapped and account.app_id.eql(app_id)) return account;
        }
        return error.UnmappedAccount;
    }
};

pub const PauseReceipt = struct {
    name: BoundedText(max_proxy_name_bytes),
    in_flight: u32,
};

pub const ClearCooldownReceipt = struct {
    name: BoundedText(max_proxy_name_bytes),
    state: AccountState,
    cooldown_until_unix_s: ?i64,
};

pub const ParseError = error{
    ResponseTooLarge,
    MalformedJson,
    IncompatibleVersion,
    TooManyAccounts,
    InvalidAccountName,
    InvalidLabel,
    InvalidAuthPath,
    InvalidConfigPath,
    InvalidTimestamp,
    InvalidStatus,
    DuplicateAccountName,
    DuplicateAuthPath,
    InvalidActiveAccount,
    InvalidCursor,
    InvalidInFlight,
};

const VersionWire = struct { version: u8 };
const AccountV1Wire = struct {
    name: []const u8,
    state: []const u8,
    cooldown_until: ?[]const u8,
    reason: ?[]const u8,
    token_expires_at: ?[]const u8,
    in_flight: u32,
};
const AccountV2Wire = struct {
    name: []const u8,
    label: ?[]const u8,
    auth_file: []const u8,
    state: []const u8,
    cooldown_until: ?[]const u8,
    reason: ?[]const u8,
    token_expires_at: ?[]const u8,
    in_flight: u32,
    token_refresh: ?TokenRefreshWire = null,
};
const TokenRefreshWire = struct {
    last_ok_at: ?[]const u8,
    last_error: ?[]const u8,
    next_attempt_at: ?[]const u8,
};
const StatusV1Wire = struct {
    version: u8,
    active: ?[]const u8,
    cursor: []const u8,
    in_flight: u32,
    accounts: []const AccountV1Wire,
};
const StatusV2Wire = struct {
    version: u8,
    config_path: []const u8,
    active: ?[]const u8,
    cursor: []const u8,
    in_flight: u32,
    accounts: []const AccountV2Wire,
};

pub fn parseStatus(allocator: std.mem.Allocator, bytes: []const u8) ParseError!Status {
    if (bytes.len > max_response_body_bytes) return error.ResponseTooLarge;
    var version = std.json.parseFromSlice(VersionWire, allocator, bytes, .{
        .allocate = .alloc_always,
        .ignore_unknown_fields = true,
    }) catch return error.MalformedJson;
    defer version.deinit();
    return switch (version.value.version) {
        1 => parseStatusV1(allocator, bytes),
        2 => parseStatusV2(allocator, bytes),
        else => error.IncompatibleVersion,
    };
}

fn parseStatusV1(allocator: std.mem.Allocator, bytes: []const u8) ParseError!Status {
    var parsed = std.json.parseFromSlice(StatusV1Wire, allocator, bytes, .{
        .allocate = .alloc_always,
        .ignore_unknown_fields = true,
    }) catch return error.MalformedJson;
    defer parsed.deinit();
    const wire = parsed.value;
    if (wire.version != 1) return error.IncompatibleVersion;
    if (wire.accounts.len == 0 or wire.accounts.len > account_registry.max_accounts) return error.TooManyAccounts;
    var result: Status = .{
        .version = 1,
        .active = try optionalName(wire.active),
        .has_active = wire.active != null,
        .cursor = try proxyName(wire.cursor),
        .in_flight = wire.in_flight,
    };
    for (wire.accounts) |account| {
        const raw: RawAccount = .{
            .name = try proxyName(account.name),
            .state = try parseState(account.state),
            .cooldown_until_unix_s = try optionalTimestamp(account.cooldown_until),
            .token_expires_at_unix_s = try optionalTimestamp(account.token_expires_at),
            .in_flight = account.in_flight,
        };
        try appendRawAccount(&result, raw);
    }
    try validateStatusLinks(&result);
    return result;
}

fn parseStatusV2(allocator: std.mem.Allocator, bytes: []const u8) ParseError!Status {
    var parsed = std.json.parseFromSlice(StatusV2Wire, allocator, bytes, .{
        .allocate = .alloc_always,
        .ignore_unknown_fields = true,
    }) catch return error.MalformedJson;
    defer parsed.deinit();
    const wire = parsed.value;
    if (wire.version != 2) return error.IncompatibleVersion;
    if (wire.accounts.len == 0 or wire.accounts.len > account_registry.max_accounts) return error.TooManyAccounts;
    try validateFilePath(wire.config_path, null, .config);
    var result: Status = .{
        .version = 2,
        .config_path = BoundedText(runtime_paths.max_path_bytes).init(wire.config_path) catch return error.InvalidConfigPath,
        .has_config_path = true,
        .active = try optionalName(wire.active),
        .has_active = wire.active != null,
        .cursor = try proxyName(wire.cursor),
        .in_flight = wire.in_flight,
    };
    for (wire.accounts) |account| {
        try validateLabel(account.label);
        try validateFilePath(account.auth_file, "auth.json", .auth);
        const raw: RawAccount = .{
            .name = try proxyName(account.name),
            .label = BoundedText(max_label_bytes).init(account.label orelse "") catch return error.InvalidLabel,
            .has_label = account.label != null,
            .auth_file = BoundedText(runtime_paths.max_path_bytes).init(account.auth_file) catch return error.InvalidAuthPath,
            .has_auth_file = true,
            .state = try parseState(account.state),
            .cooldown_until_unix_s = try optionalTimestamp(account.cooldown_until),
            .token_expires_at_unix_s = try optionalTimestamp(account.token_expires_at),
            .token_refresh_last_ok_at_unix_s = if (account.token_refresh) |refresh| try optionalTimestamp(refresh.last_ok_at) else null,
            .token_refresh_last_error = if (account.token_refresh) |refresh| try refreshErrorKind(refresh.last_error) else .{},
            .has_token_refresh_last_error = if (account.token_refresh) |refresh| refresh.last_error != null else false,
            .token_refresh_next_attempt_at_unix_s = if (account.token_refresh) |refresh| try optionalTimestamp(refresh.next_attempt_at) else null,
            .in_flight = account.in_flight,
        };
        try appendRawAccount(&result, raw);
    }
    try validateStatusLinks(&result);
    return result;
}

fn appendRawAccount(status: *Status, account: RawAccount) ParseError!void {
    for (status.accountSlice()) |existing| {
        if (existing.name.eql(account.name.slice())) return error.DuplicateAccountName;
        if (account.has_auth_file and existing.has_auth_file and existing.auth_file.eql(account.auth_file.slice())) {
            return error.DuplicateAuthPath;
        }
    }
    status.accounts[status.account_count] = account;
    status.account_count += 1;
}

fn validateStatusLinks(status: *const Status) ParseError!void {
    var cursor_found = false;
    var active_found = !status.has_active;
    var total: u64 = 0;
    for (status.accountSlice()) |account| {
        if (account.name.eql(status.cursor.slice())) cursor_found = true;
        if (status.has_active and account.name.eql(status.active.slice())) active_found = true;
        total += account.in_flight;
    }
    if (!cursor_found) return error.InvalidCursor;
    if (!active_found) return error.InvalidActiveAccount;
    // V2 counts admitted client requests globally and upstream connections per
    // account. A Responses WebSocket can retain zero or multiple upstream peers,
    // so those counts are independent. Preserve the legacy V1 invariant only.
    if (status.version == 1 and total != status.in_flight) return error.InvalidInFlight;
}

fn proxyName(value: []const u8) ParseError!BoundedText(max_proxy_name_bytes) {
    if (value.len == 0 or value.len > max_proxy_name_bytes) return error.InvalidAccountName;
    for (value) |byte| switch (byte) {
        'a'...'z', 'A'...'Z', '0'...'9', '.', '_', '-' => {},
        else => return error.InvalidAccountName,
    };
    return BoundedText(max_proxy_name_bytes).init(value) catch return error.InvalidAccountName;
}

fn refreshErrorKind(value: ?[]const u8) ParseError!BoundedText(max_refresh_error_kind_bytes) {
    const text = value orelse return .{};
    if (text.len == 0 or text.len > max_refresh_error_kind_bytes) return error.InvalidStatus;
    for (text) |byte| switch (byte) {
        'a'...'z', '_' => {},
        else => return error.InvalidStatus,
    };
    return BoundedText(max_refresh_error_kind_bytes).init(text) catch return error.InvalidStatus;
}

fn optionalName(value: ?[]const u8) ParseError!BoundedText(max_proxy_name_bytes) {
    return if (value) |text| proxyName(text) else .{};
}

fn validateLabel(value: ?[]const u8) ParseError!void {
    const label = value orelse return;
    if (label.len > max_label_bytes or !std.unicode.utf8ValidateSlice(label)) return error.InvalidLabel;
    for (label) |byte| if (byte == 0 or byte == 0x7f or byte < 0x20) return error.InvalidLabel;
}

const PathFailure = enum { auth, config };

fn validateFilePath(value: []const u8, expected_basename: ?[]const u8, comptime failure: PathFailure) ParseError!void {
    _ = runtime_paths.Path.init(value) catch return switch (failure) {
        .auth => error.InvalidAuthPath,
        .config => error.InvalidConfigPath,
    };
    if (expected_basename) |basename| {
        const last = std.mem.lastIndexOfScalar(u8, value, '/') orelse return error.InvalidAuthPath;
        if (!std.mem.eql(u8, value[last + 1 ..], basename)) return error.InvalidAuthPath;
    }
}

fn parseState(value: []const u8) ParseError!AccountState {
    if (std.mem.eql(u8, value, "READY")) return .ready;
    if (std.mem.eql(u8, value, "COOLDOWN")) return .cooldown;
    if (std.mem.eql(u8, value, "PAUSED")) return .paused;
    if (std.mem.eql(u8, value, "INVALID")) return .invalid;
    if (std.mem.eql(u8, value, "REFRESHING")) return .refreshing;
    return error.InvalidStatus;
}

fn optionalTimestamp(value: ?[]const u8) ParseError!?i64 {
    return if (value) |text| try parseTimestamp(text) else null;
}

fn parseTimestamp(value: []const u8) ParseError!i64 {
    if (value.len < 20 or value.len > 30) return error.InvalidTimestamp;
    if (value[4] != '-' or value[7] != '-' or value[10] != 'T' or value[13] != ':' or value[16] != ':') {
        return error.InvalidTimestamp;
    }
    if (value[value.len - 1] != 'Z') return error.InvalidTimestamp;
    const year = parseDecimal(value[0..4]) orelse return error.InvalidTimestamp;
    const month = parseDecimal(value[5..7]) orelse return error.InvalidTimestamp;
    const day = parseDecimal(value[8..10]) orelse return error.InvalidTimestamp;
    const hour = parseDecimal(value[11..13]) orelse return error.InvalidTimestamp;
    const minute = parseDecimal(value[14..16]) orelse return error.InvalidTimestamp;
    const second = parseDecimal(value[17..19]) orelse return error.InvalidTimestamp;
    if (year < 1970 or month < 1 or month > 12 or hour > 23 or minute > 59 or second > 59) return error.InvalidTimestamp;
    if (value.len > 20) {
        if (value[19] != '.' or value.len == 21) return error.InvalidTimestamp;
        for (value[20 .. value.len - 1]) |byte| if (!std.ascii.isDigit(byte)) return error.InvalidTimestamp;
    }
    const days_in_month = [_]u8{ 31, if (isLeapYear(year)) 29 else 28, 31, 30, 31, 30, 31, 31, 30, 31, 30, 31 };
    if (day < 1 or day > days_in_month[month - 1]) return error.InvalidTimestamp;
    const days = daysFromCivil(@intCast(year), @intCast(month), @intCast(day));
    return days * std.time.s_per_day + @as(i64, @intCast(hour * 3600 + minute * 60 + second));
}

fn parseDecimal(value: []const u8) ?u32 {
    if (value.len == 0) return null;
    var result: u32 = 0;
    for (value) |byte| {
        if (!std.ascii.isDigit(byte)) return null;
        result = result * 10 + byte - '0';
    }
    return result;
}

fn isLeapYear(year: u32) bool {
    return @mod(year, 4) == 0 and (@mod(year, 100) != 0 or @mod(year, 400) == 0);
}

fn daysFromCivil(year_input: i64, month: i64, day: i64) i64 {
    const year = year_input - @as(i64, @intFromBool(month <= 2));
    const era = @divFloor(year, 400);
    const year_of_era = year - era * 400;
    const adjusted_month = month + (if (month > 2) @as(i64, -3) else 9);
    const day_of_year = @divFloor(153 * adjusted_month + 2, 5) + day - 1;
    const day_of_era = year_of_era * 365 + @divFloor(year_of_era, 4) - @divFloor(year_of_era, 100) + day_of_year;
    return era * 146_097 + day_of_era - 719_468;
}

pub fn mapStatus(status: Status, layout: *const runtime_paths.Layout, app_accounts: []const AppAccount) (ParseError || runtime_paths.PathError || runtime_paths.SegmentError || error{ IncompatibleVersion, AmbiguousMapping })!MappedStatus {
    if (status.version != 2) return error.IncompatibleVersion;
    var result: MappedStatus = .{ .in_flight = status.in_flight };
    for (status.accountSlice(), 0..) |raw, row_index| {
        var match: ?AppAccount = null;
        for (app_accounts) |candidate| {
            if (!candidate.eligible()) continue;
            var expected = try layout.codexAuthFile(candidate.storage_key);
            if (!std.mem.eql(u8, raw.auth_file.slice(), expected.slice())) continue;
            if (match != null) return error.AmbiguousMapping;
            match = candidate;
        }
        const label = if (match) |candidate| candidate.label else if (raw.has_label) raw.label.slice() else "Unmapped proxy account";
        var mapped: MappedAccount = .{
            .proxy_name = raw.name,
            .label = BoundedText(max_label_bytes).init(label) catch return error.InvalidLabel,
            .state = if (raw.has_token_refresh_last_error) .invalid else raw.state,
            .cooldown_until_unix_s = raw.cooldown_until_unix_s,
            .token_expires_at_unix_s = raw.token_expires_at_unix_s,
            .token_refresh_last_ok_at_unix_s = raw.token_refresh_last_ok_at_unix_s,
            .token_refresh_last_error = raw.token_refresh_last_error,
            .has_token_refresh_last_error = raw.has_token_refresh_last_error,
            .token_refresh_next_attempt_at_unix_s = raw.token_refresh_next_attempt_at_unix_s,
            .in_flight = raw.in_flight,
            .active = status.has_active and raw.name.eql(status.active.slice()),
            .mapped = match != null,
        };
        if (match) |candidate| {
            mapped.app_id = BoundedText(account_registry.max_id_bytes).init(candidate.app_id) catch return error.InvalidStatus;
            mapped.storage_key = BoundedText(account_registry.max_storage_key_bytes).init(candidate.storage_key) catch return error.InvalidStatus;
        }
        result.accounts[result.account_count] = mapped;
        result.account_count += 1;
        if (mapped.active) result.active_index = row_index;
    }
    return result;
}

pub const ClientError = TransportError || ParseError || error{
    InvalidBaseUrl,
    InvalidAccountName,
    ApiRejected,
};

pub const Client = struct {
    allocator: std.mem.Allocator,
    exchange: Exchange,
    base_url: BaseUrl,
    config_path: []const u8 = "",
    timeout_ms: u32 = default_timeout_ms,

    pub fn init(allocator: std.mem.Allocator, exchange: Exchange, base_url: []const u8) error{InvalidBaseUrl}!Client {
        return .{ .allocator = allocator, .exchange = exchange, .base_url = BaseUrl.init(base_url) catch return error.InvalidBaseUrl };
    }

    pub fn status(self: *Client) ClientError!Status {
        return self.statusRequest(.get, "/_proxy/status", "");
    }

    pub fn switchAccount(self: *Client, name: []const u8) ClientError!Status {
        _ = proxyName(name) catch return error.InvalidAccountName;
        var body_buffer: [max_request_body_bytes]u8 = undefined;
        const body = std.fmt.bufPrint(&body_buffer, "{{\"name\":\"{s}\"}}", .{name}) catch return error.RequestRejected;
        return self.v2StatusRequest(.post, "/_proxy/switch", body);
    }

    pub fn pauseAccount(self: *Client, name: []const u8) ClientError!PauseReceipt {
        _ = proxyName(name) catch return error.InvalidAccountName;
        var path_buffer: [max_request_path_bytes]u8 = undefined;
        const path = std.fmt.bufPrint(&path_buffer, "/_proxy/accounts/{s}/pause", .{name}) catch return error.RequestRejected;
        var response_buffer: [max_response_body_bytes]u8 = undefined;
        const response = try self.perform(.post, path, "{}", &response_buffer);
        if (response.status != 202) return error.ApiRejected;
        const receipt = try parsePauseReceipt(self.allocator, response_buffer[0..response.body_len]);
        if (!receipt.name.eql(name)) return error.InvalidStatus;
        return receipt;
    }

    pub fn clearCooldown(self: *Client, name: []const u8) ClientError!ClearCooldownReceipt {
        _ = proxyName(name) catch return error.InvalidAccountName;
        var path_buffer: [max_request_path_bytes]u8 = undefined;
        const path = std.fmt.bufPrint(&path_buffer, "/_proxy/accounts/{s}/clear-cooldown", .{name}) catch return error.RequestRejected;
        var response_buffer: [max_response_body_bytes]u8 = undefined;
        const response = try self.perform(.post, path, "{}", &response_buffer);
        if (response.status != 200) return error.ApiRejected;
        const receipt = try parseClearCooldownReceipt(self.allocator, response_buffer[0..response.body_len]);
        if (!receipt.name.eql(name)) return error.InvalidStatus;
        return receipt;
    }

    pub fn reloadAccount(self: *Client, name: []const u8) ClientError!Status {
        _ = proxyName(name) catch return error.InvalidAccountName;
        var path_buffer: [max_request_path_bytes]u8 = undefined;
        const path = std.fmt.bufPrint(&path_buffer, "/_proxy/accounts/{s}/reload", .{name}) catch return error.RequestRejected;
        return self.v2StatusRequest(.post, path, "{}");
    }

    pub fn reloadConfig(self: *Client) ClientError!Status {
        return self.v2StatusRequest(.post, "/_proxy/reload-config", "{}");
    }

    fn statusRequest(self: *Client, method: Method, path: []const u8, body: []const u8) ClientError!Status {
        var response_buffer: [max_response_body_bytes]u8 = undefined;
        const response = try self.perform(method, path, body, &response_buffer);
        if (response.status != 200) return error.ApiRejected;
        return parseStatus(self.allocator, response_buffer[0..response.body_len]);
    }

    fn v2StatusRequest(self: *Client, method: Method, path: []const u8, body: []const u8) ClientError!Status {
        const result = try self.statusRequest(method, path, body);
        if (result.version != 2) return error.IncompatibleVersion;
        return result;
    }

    fn perform(self: *Client, method: Method, path: []const u8, body: []const u8, response_buffer: []u8) TransportError!ExchangeResult {
        if (path.len == 0 or path.len > max_request_path_bytes or path[0] != '/') return error.RequestRejected;
        if (body.len > max_request_body_bytes) return error.RequestRejected;
        const is_post = method == .post;
        if (!is_post and body.len != 0) return error.RequestRejected;
        return self.exchange.perform(.{
            .method = method,
            .base_url = self.base_url.slice(),
            .path = path,
            .body = body,
            .config_path = self.config_path,
            .content_type_json = is_post,
            .timeout_ms = self.timeout_ms,
        }, response_buffer);
    }
};

const PauseWire = struct {
    name: []const u8,
    state: []const u8,
    in_flight: u32,
};

fn parsePauseReceipt(allocator: std.mem.Allocator, bytes: []const u8) ParseError!PauseReceipt {
    if (bytes.len > max_response_body_bytes) return error.ResponseTooLarge;
    var parsed = std.json.parseFromSlice(PauseWire, allocator, bytes, .{
        .allocate = .alloc_always,
        .ignore_unknown_fields = true,
    }) catch return error.MalformedJson;
    defer parsed.deinit();
    if (!std.mem.eql(u8, parsed.value.state, "PAUSED")) return error.InvalidStatus;
    return .{ .name = try proxyName(parsed.value.name), .in_flight = parsed.value.in_flight };
}

const ClearCooldownWire = struct {
    name: []const u8,
    state: []const u8,
    cooldown_until: ?[]const u8 = null,
};

fn parseClearCooldownReceipt(allocator: std.mem.Allocator, bytes: []const u8) ParseError!ClearCooldownReceipt {
    if (bytes.len > max_response_body_bytes) return error.ResponseTooLarge;
    var parsed = std.json.parseFromSlice(ClearCooldownWire, allocator, bytes, .{
        .allocate = .alloc_always,
        .ignore_unknown_fields = true,
    }) catch return error.MalformedJson;
    defer parsed.deinit();
    const state = try parseState(parsed.value.state);
    const cooldown_until: ?i64 = if (parsed.value.cooldown_until) |text| try parseTimestamp(text) else null;
    return .{ .name = try proxyName(parsed.value.name), .state = state, .cooldown_until_unix_s = cooldown_until };
}

pub const LoopbackExchange = struct {
    allocator: std.mem.Allocator,
    io: std.Io,
    control_token_path: runtime_paths.Path = .{},

    const vtable: Exchange.VTable = .{ .perform = perform };

    pub fn init(allocator: std.mem.Allocator, io: std.Io) LoopbackExchange {
        return .{ .allocator = allocator, .io = io };
    }

    pub fn exchange(self: *LoopbackExchange) Exchange {
        return .{ .context = self, .vtable = &vtable };
    }

    pub fn useConfigPath(self: *LoopbackExchange, config_path: []const u8) !void {
        try runtime_paths.validateAbsoluteDir(config_path);
        var buffer: [runtime_paths.max_path_bytes]u8 = undefined;
        self.control_token_path = try runtime_paths.Path.init(try std.fmt.bufPrint(&buffer, "{s}.control-token", .{config_path}));
    }

    fn perform(context: *anyopaque, request: Request, response_buffer: []u8) TransportError!ExchangeResult {
        const self: *LoopbackExchange = @ptrCast(@alignCast(context));
        _ = BaseUrl.init(request.base_url) catch return error.RequestRejected;
        var token_path = self.control_token_path;
        if (request.config_path.len != 0) {
            runtime_paths.validateAbsoluteDir(request.config_path) catch return error.RequestRejected;
            var path_buffer: [runtime_paths.max_path_bytes]u8 = undefined;
            token_path = runtime_paths.Path.init(std.fmt.bufPrint(&path_buffer, "{s}.control-token", .{request.config_path}) catch return error.RequestRejected) catch return error.RequestRejected;
        }
        return runBounded(self.io, request.timeout_ms, exchangeOnce, .{
            self.allocator,
            self.io,
            request,
            response_buffer,
            token_path.slice(),
        });
    }
};

fn runBounded(io: std.Io, timeout_ms: u32, comptime func: anytype, args: anytype) TransportError!ExchangeResult {
    if (timeout_ms == 0) return error.RequestRejected;
    const Bounded = struct {
        fn run(inner: std.Io, event: *std.Io.Event, inner_args: std.meta.ArgsTuple(@TypeOf(func))) TransportError!ExchangeResult {
            defer event.set(inner);
            return @call(.auto, func, inner_args);
        }
    };

    const deadline: std.Io.Timeout = (std.Io.Timeout{
        .duration = .{ .raw = .fromMilliseconds(timeout_ms), .clock = .awake },
    }).toDeadline(io);
    var finished: std.Io.Event = .unset;
    var future = io.concurrent(Bounded.run, .{ io, &finished, args }) catch return error.Network;
    defer {
        _ = future.cancel(io) catch {};
        _ = future.await(io) catch {};
    }
    while (true) {
        if (finished.waitTimeout(io, deadline)) |_| break else |err| switch (err) {
            error.Canceled => {
                _ = future.cancel(io) catch {};
                return error.Canceled;
            },
            error.Timeout => {
                if (finished.isSet()) break;
                const timestamp = switch (deadline) {
                    .deadline => |value| value,
                    else => return error.RequestRejected,
                };
                if (timestamp.durationFromNow(io).raw.nanoseconds <= 0) {
                    _ = future.cancel(io) catch {};
                    return error.Timeout;
                }
            },
        }
    }
    return future.await(io);
}

fn exchangeOnce(
    allocator: std.mem.Allocator,
    io: std.Io,
    request: Request,
    response_buffer: []u8,
    control_token_path: []const u8,
) TransportError!ExchangeResult {
    var url_buffer: [max_base_url_bytes + max_request_path_bytes]u8 = undefined;
    const url = std.fmt.bufPrint(&url_buffer, "{s}{s}", .{ request.base_url, request.path }) catch return error.RequestRejected;
    const uri = std.Uri.parse(url) catch return error.RequestRejected;
    if (!std.mem.eql(u8, uri.scheme, "http") or uri.user != null or uri.password != null) return error.RequestRejected;

    var headers: std.http.Client.Request.Headers = .{
        .accept_encoding = .{ .override = "identity" },
    };
    if (request.content_type_json) headers.content_type = .{ .override = "application/json" };
    var authorization: [71]u8 = undefined;
    if (try readControlAuthorization(io, control_token_path, &authorization)) |value| {
        headers.authorization = .{ .override = value };
    }
    var client: std.http.Client = .{
        .allocator = allocator,
        .io = io,
        .read_buffer_size = max_response_head_bytes,
    };
    defer client.deinit();
    var http_request = client.request(if (request.method == .get) .GET else .POST, uri, .{
        .redirect_behavior = .not_allowed,
        .keep_alive = false,
        .headers = headers,
    }) catch |err| switch (err) {
        error.Canceled => return error.Canceled,
        error.UnsupportedUriScheme, error.UriMissingHost => return error.RequestRejected,
        else => return error.Network,
    };
    defer http_request.deinit();

    switch (request.method) {
        .get => http_request.sendBodiless() catch return error.Network,
        .post => {
            http_request.transfer_encoding = .{ .content_length = request.body.len };
            var send_buffer: [max_request_body_bytes]u8 = undefined;
            var body_writer = http_request.sendBodyUnflushed(&send_buffer) catch return error.Network;
            body_writer.writer.writeAll(request.body) catch return error.Network;
            body_writer.end() catch return error.Network;
            (http_request.connection orelse return error.Network).flush() catch return error.Network;
        },
    }

    var redirect_buffer: [0]u8 = undefined;
    var response = http_request.receiveHead(&redirect_buffer) catch |err| switch (err) {
        error.Canceled => return error.Canceled,
        error.TooManyHttpRedirects,
        error.RedirectRequiresResend,
        error.HttpRedirectLocationMissing,
        error.HttpRedirectLocationOversize,
        error.HttpRedirectLocationInvalid,
        error.UnsupportedUriScheme,
        error.UriMissingHost,
        => return error.RequestRejected,
        else => return error.Network,
    };
    if (response.head.content_encoding != .identity) return error.InvalidResponse;
    if (response.head.content_length) |length| if (length > response_buffer.len) return error.ResponseTooLarge;
    var json_content_type = false;
    var header_iterator = std.http.HeaderIterator.init(response.head.bytes);
    while (header_iterator.next()) |header| {
        if (std.ascii.eqlIgnoreCase(header.name, "content-type")) {
            const value = std.mem.trim(u8, header.value, " \t");
            const semicolon = std.mem.indexOfScalar(u8, value, ';') orelse value.len;
            json_content_type = std.ascii.eqlIgnoreCase(std.mem.trim(u8, value[0..semicolon], " \t"), "application/json");
        }
    }
    if (!json_content_type) return error.InvalidResponse;
    var transfer_buffer: [response_transfer_buffer_bytes]u8 = undefined;
    const body_reader = response.reader(&transfer_buffer);
    var body_writer = std.Io.Writer.fixed(response_buffer);
    const body_len = body_reader.streamRemaining(&body_writer) catch |err| switch (err) {
        error.WriteFailed => return error.ResponseTooLarge,
        error.ReadFailed => return error.Network,
    };
    return .{ .status = @intFromEnum(response.head.status), .body_len = body_len };
}

fn readControlAuthorization(io: std.Io, path: []const u8, buffer: *[71]u8) TransportError!?[]const u8 {
    if (path.len == 0) return null;
    const file = std.Io.Dir.cwd().openFile(io, path, .{ .allow_directory = false, .follow_symlinks = false }) catch |err| {
        if (err == error.FileNotFound) return null;
        return error.RequestRejected;
    };
    defer file.close(io);
    var stat: std.c.Stat = undefined;
    if (std.c.fstat(file.handle, &stat) != 0 or stat.uid != std.c.getuid() or
        (stat.mode & 0o077) != 0 or stat.size != 64) return error.RequestRejected;
    const info = file.stat(io) catch return error.RequestRejected;
    if (info.kind != .file) return error.RequestRejected;
    @memcpy(buffer[0..7], "Bearer ");
    var reader = file.reader(io, &.{});
    reader.interface.readSliceAll(buffer[7..]) catch return error.RequestRejected;
    for (buffer[7..]) |byte| if (!std.ascii.isHex(byte) or std.ascii.isUpper(byte)) return error.RequestRejected;
    return buffer;
}
