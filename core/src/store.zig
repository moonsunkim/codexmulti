const std = @import("std");
const account_registry = @import("account_registry.zig");
const domain = @import("domain.zig");
const proxy_control = @import("proxy_control_client.zig");
const runtime_paths = @import("runtime_paths.zig");

pub const current_schema_version: u16 = 1;
pub const max_document_bytes: usize = 1024 * 1024;
pub const max_proxy_fingerprint_bytes: usize = 128;
pub const Appearance = enum { system, light, dark };
pub const CodexUsageWindow = enum { auto, weekly, session };
pub const Language = @import("strings.zig").Language;

pub const default_proxy_base_url = "http://127.0.0.1:8787";

pub const default_proxy_cli_path = "";
pub const default_proxy_config_path = "~/.config/codexmulti/proxy.json";

pub const SnapshotDocument = struct {
    schema_version: u16 = current_schema_version,
    profiles: []const domain.AccountProfile,
    snapshots: []const domain.UsageSnapshot,
};

pub const AttemptDocument = struct {
    schema_version: u16 = current_schema_version,
    attempts: []const domain.ResetAttempt,
};

pub const AppSettingsDocument = struct {
    schema_version: u16 = current_schema_version,
    appearance: Appearance = .system,
    language: Language = .system,
    codex_usage_window: CodexUsageWindow = .auto,
    codex_show_model_limits: bool = false,
    launch_at_login: bool = false,
    launch_at_login_registration_failed: bool = false,
    auto_refresh_minutes: u16 = 0,

    last_successful_refresh_at_unix_s: ?i64 = null,
};

pub const ProxySettings = struct {
    base_url: []const u8 = default_proxy_base_url,
    cli_path: []const u8 = default_proxy_cli_path,
    config_path: []const u8 = default_proxy_config_path,

    node_path: ?[]const u8 = null,
};

pub const ProxySettingsDocument = struct {
    schema_version: u16 = current_schema_version,
    proxy: ProxySettings = .{},
    last_synced_accounts_fingerprint: ?[]const u8 = null,
};

pub const ProxyAttemptResult = enum {
    ok,
    @"unreachable",
    timeout,
    protocol_error,
    incompatible,
    action_failed,
    import_failed,
    mapping_failed,
    config_mismatch,
    persist_failed,
    import_node_missing,
};
pub const ProxyStoredState = enum { ready, cooldown, paused, invalid, refreshing, unknown };

pub const ProxyLastAttempt = struct {
    at_unix_s: i64,
    result: ProxyAttemptResult,
};

pub const ProxyStoredAccount = struct {
    proxy_name: []const u8,
    storage_key: ?[]const u8 = null,
    label: []const u8,
    state: ProxyStoredState,
    cooldown_until_unix_s: ?i64 = null,
    token_expires_at_unix_s: ?i64 = null,
    token_refresh_last_ok_at_unix_s: ?i64 = null,
    token_refresh_last_error: ?[]const u8 = null,
    token_refresh_next_attempt_at_unix_s: ?i64 = null,
    in_flight: u32,
    active: bool,
};

pub const ProxyLastSuccess = struct {
    checked_at_unix_s: i64,
    api_version: u8,
    active_storage_key: ?[]const u8 = null,
    cooldown_count: u8,
    accounts: []const ProxyStoredAccount,
};

pub const ProxyStatusDocument = struct {
    schema_version: u16 = current_schema_version,
    last_attempt: ?ProxyLastAttempt = null,
    last_success: ?ProxyLastSuccess = null,
};

pub const LoadedSnapshots = std.json.Parsed(SnapshotDocument);
pub const LoadedAttempts = std.json.Parsed(AttemptDocument);
pub const LoadedAppSettings = std.json.Parsed(AppSettingsDocument);
pub const LoadedProxySettings = std.json.Parsed(ProxySettingsDocument);
pub const LoadedProxyStatus = std.json.Parsed(ProxyStatusDocument);

pub fn encode(allocator: std.mem.Allocator, value: anytype) ![]u8 {
    var writer: std.Io.Writer.Allocating = .init(allocator);
    defer writer.deinit();
    try std.json.Stringify.value(value, .{ .emit_null_optional_fields = true }, &writer.writer);
    return try writer.toOwnedSlice();
}

pub fn decodeSnapshots(allocator: std.mem.Allocator, bytes: []const u8) !LoadedSnapshots {
    var parsed = try std.json.parseFromSlice(SnapshotDocument, allocator, bytes, .{ .allocate = .alloc_always });
    errdefer parsed.deinit();
    try validateSnapshotDocument(parsed.value);
    return parsed;
}

pub fn decodeAttempts(allocator: std.mem.Allocator, bytes: []const u8) !LoadedAttempts {
    var parsed = try std.json.parseFromSlice(AttemptDocument, allocator, bytes, .{ .allocate = .alloc_always });
    errdefer parsed.deinit();
    try validateAttemptDocument(parsed.value);
    return parsed;
}

pub fn decodeAppSettings(allocator: std.mem.Allocator, bytes: []const u8) !LoadedAppSettings {
    var parsed = try std.json.parseFromSlice(AppSettingsDocument, allocator, bytes, .{ .allocate = .alloc_always });
    errdefer parsed.deinit();
    try validateAppSettings(parsed.value);
    return parsed;
}

pub fn decodeProxySettings(allocator: std.mem.Allocator, bytes: []const u8) !LoadedProxySettings {
    var parsed = try std.json.parseFromSlice(ProxySettingsDocument, allocator, bytes, .{ .allocate = .alloc_always });
    errdefer parsed.deinit();
    try validateProxySettings(parsed.value);
    return parsed;
}

pub fn decodeProxyStatus(allocator: std.mem.Allocator, bytes: []const u8) !LoadedProxyStatus {
    var parsed = try std.json.parseFromSlice(ProxyStatusDocument, allocator, bytes, .{ .allocate = .alloc_always });
    errdefer parsed.deinit();
    try validateProxyStatus(parsed.value);
    return parsed;
}

pub fn validateSnapshotDocument(document: SnapshotDocument) !void {
    if (document.schema_version != current_schema_version) return error.UnsupportedSchemaVersion;
    for (document.profiles) |profile| {
        if (profile.id.len == 0 or profile.storage_key.len == 0) return error.InvalidProfile;
    }
    for (document.snapshots) |snapshot| {
        if (snapshot.account_id.len == 0) return error.InvalidSnapshot;
        for (snapshot.windows) |window| {
            if (window.used_percent > 100) return error.InvalidUsagePercent;
        }
        if (snapshot.reset_credits) |credits| {
            if (credits.detail_status == .detailed and credits.details.len > credits.available_count) {
                return error.InvalidCreditDetails;
            }
        }
    }
}

pub fn validateAttemptDocument(document: AttemptDocument) !void {
    if (document.schema_version != current_schema_version) return error.UnsupportedSchemaVersion;
    for (document.attempts, 0..) |attempt, index| {
        if (attempt.idempotency_key.len == 0 or attempt.account_id.len == 0) return error.InvalidAttempt;
        if (attempt.phase == .completed and attempt.outcome == null) return error.InvalidAttempt;
        if (attempt.phase != .completed and attempt.outcome != null) return error.InvalidAttempt;
        for (document.attempts[index + 1 ..]) |other| {
            if (std.mem.eql(u8, attempt.idempotency_key, other.idempotency_key)) return error.DuplicateIdempotencyKey;
        }
    }
}

pub fn validateAppSettings(document: AppSettingsDocument) !void {
    if (document.schema_version != current_schema_version) return error.UnsupportedSchemaVersion;
    if (!validAutoRefreshMinutes(document.auto_refresh_minutes)) return error.InvalidAutoRefreshMinutes;
    if (document.last_successful_refresh_at_unix_s) |at| if (at < 0) return error.InvalidRefreshTimestamp;
}

pub fn validAutoRefreshMinutes(minutes: u16) bool {
    return switch (minutes) {
        0, 15, 30, 60 => true,
        else => false,
    };
}

pub fn validateProxySettings(document: ProxySettingsDocument) !void {
    if (document.schema_version != current_schema_version) return error.UnsupportedSchemaVersion;
    _ = proxy_control.BaseUrl.init(document.proxy.base_url) catch return error.InvalidProxyBaseUrl;
    if (document.proxy.cli_path.len != 0) try validateAbsoluteFileText(document.proxy.cli_path);
    try validateConfigPathText(document.proxy.config_path);
    if (document.proxy.node_path) |node_path| try validateAbsoluteFileText(node_path);
    if (document.last_synced_accounts_fingerprint) |fingerprint| {
        if (fingerprint.len == 0 or fingerprint.len > max_proxy_fingerprint_bytes) return error.InvalidProxyFingerprint;
        for (fingerprint) |byte| switch (byte) {
            'a'...'z', 'A'...'Z', '0'...'9', '.', '_', '-' => {},
            else => return error.InvalidProxyFingerprint,
        };
    }
}

pub fn validateProxyStatus(document: ProxyStatusDocument) !void {
    if (document.schema_version != current_schema_version) return error.UnsupportedSchemaVersion;
    if (document.last_attempt) |attempt| if (attempt.at_unix_s < 0) return error.InvalidProxyTimestamp;
    if (document.last_success) |success| {
        if (success.checked_at_unix_s < 0) return error.InvalidProxyTimestamp;
        if (success.api_version != 2) return error.UnsupportedProxyApiVersion;
        if (success.accounts.len > account_registry.max_accounts) return error.TooManyProxyAccounts;
        if (success.cooldown_count > success.accounts.len) return error.InvalidProxyStatus;
        var active_count: usize = 0;
        for (success.accounts, 0..) |account, index| {
            try validateProxyName(account.proxy_name);
            try validateDisplayText(account.label);
            if (account.storage_key) |key| runtime_paths.validateAccountSegment(key) catch return error.InvalidProxyStorageKey;
            if (account.cooldown_until_unix_s) |value| if (value < 0) return error.InvalidProxyTimestamp;
            if (account.token_expires_at_unix_s) |value| if (value < 0) return error.InvalidProxyTimestamp;
            if (account.token_refresh_last_ok_at_unix_s) |value| if (value < 0) return error.InvalidProxyTimestamp;
            if (account.token_refresh_next_attempt_at_unix_s) |value| if (value < 0) return error.InvalidProxyTimestamp;
            if (account.token_refresh_last_error) |value| {
                if (value.len == 0 or value.len > proxy_control.max_refresh_error_kind_bytes) return error.InvalidProxyStatus;
                for (value) |byte| switch (byte) {
                    'a'...'z', '_' => {},
                    else => return error.InvalidProxyStatus,
                };
            }
            if (account.active) active_count += 1;
            for (success.accounts[index + 1 ..]) |other| {
                if (std.mem.eql(u8, account.proxy_name, other.proxy_name)) return error.DuplicateProxyAccount;
                if (account.storage_key != null and other.storage_key != null and
                    runtime_paths.segmentsCollide(account.storage_key.?, other.storage_key.?))
                {
                    return error.DuplicateProxyStorageKey;
                }
            }
        }
        if (active_count > 1) return error.InvalidProxyStatus;
        if (success.active_storage_key) |active_key| {
            runtime_paths.validateAccountSegment(active_key) catch return error.InvalidProxyStorageKey;
            var found = false;
            for (success.accounts) |account| {
                if (account.active and account.storage_key != null and std.mem.eql(u8, account.storage_key.?, active_key)) found = true;
            }
            if (!found) return error.InvalidProxyStatus;
        }
    }
}

fn validateAbsoluteFileText(value: []const u8) !void {
    _ = runtime_paths.Path.init(value) catch return error.InvalidProxyPath;
}

fn validateConfigPathText(value: []const u8) !void {
    if (std.mem.startsWith(u8, value, "~/")) {
        if (value.len <= 2 or value.len + 1 > runtime_paths.max_path_bytes) return error.InvalidProxyPath;
        var buffer: [runtime_paths.max_path_bytes]u8 = undefined;
        buffer[0] = '/';
        @memcpy(buffer[1 .. value.len - 1], value[2..]);
        _ = runtime_paths.Path.init(buffer[0 .. value.len - 1]) catch return error.InvalidProxyPath;
        return;
    }
    try validateAbsoluteFileText(value);
}

fn validateProxyName(value: []const u8) !void {
    if (value.len == 0 or value.len > proxy_control.max_proxy_name_bytes) return error.InvalidProxyName;
    for (value) |byte| switch (byte) {
        'a'...'z', 'A'...'Z', '0'...'9', '.', '_', '-' => {},
        else => return error.InvalidProxyName,
    };
}

fn validateDisplayText(value: []const u8) !void {
    if (value.len > proxy_control.max_label_bytes or !std.unicode.utf8ValidateSlice(value)) return error.InvalidProxyLabel;
    for (value) |byte| if (byte == 0 or byte == 0x7f or byte < 0x20) return error.InvalidProxyLabel;
}

pub fn writeAtomically(io: std.Io, dir: std.Io.Dir, final_path: []const u8, temp_path: []const u8, bytes: []const u8) !void {
    if (std.mem.eql(u8, final_path, temp_path)) return error.TempPathMatchesFinalPath;
    // A unique exclusive file preserves stale crash remnants and cannot follow a symlink.
    var nonce: [16]u8 = undefined;
    io.random(&nonce);
    var path_buffer: [std.Io.Dir.max_path_bytes]u8 = undefined;
    const unique_temp = try std.fmt.bufPrint(&path_buffer, "{s}.{x}", .{ temp_path, nonce });
    var file = try dir.createFile(io, unique_temp, .{ .exclusive = true, .permissions = .fromMode(0o600) });
    defer file.close(io);
    errdefer dir.deleteFile(io, unique_temp) catch {};
    try file.writeStreamingAll(io, bytes);
    try @import("durable_file.zig").syncFile(io, file);
    try dir.rename(unique_temp, dir, final_path, io);
    try @import("durable_file.zig").syncParent(io, dir, final_path);
}

pub fn saveSnapshotsAtomic(
    allocator: std.mem.Allocator,
    io: std.Io,
    dir: std.Io.Dir,
    final_path: []const u8,
    temp_path: []const u8,
    document: SnapshotDocument,
) !void {
    try validateSnapshotDocument(document);
    const bytes = try encode(allocator, document);
    defer allocator.free(bytes);
    try writeAtomically(io, dir, final_path, temp_path, bytes);
}

pub fn saveAttemptsAtomic(
    allocator: std.mem.Allocator,
    io: std.Io,
    dir: std.Io.Dir,
    final_path: []const u8,
    temp_path: []const u8,
    document: AttemptDocument,
) !void {
    try validateAttemptDocument(document);
    const bytes = try encode(allocator, document);
    defer allocator.free(bytes);
    try writeAtomically(io, dir, final_path, temp_path, bytes);
}

pub fn saveAppSettingsAtomic(
    allocator: std.mem.Allocator,
    io: std.Io,
    dir: std.Io.Dir,
    final_path: []const u8,
    temp_path: []const u8,
    document: AppSettingsDocument,
) !void {
    try validateAppSettings(document);
    const bytes = try encode(allocator, document);
    defer allocator.free(bytes);
    try writeAtomically(io, dir, final_path, temp_path, bytes);
}

pub fn saveProxySettingsAtomic(
    allocator: std.mem.Allocator,
    io: std.Io,
    dir: std.Io.Dir,
    final_path: []const u8,
    temp_path: []const u8,
    document: ProxySettingsDocument,
) !void {
    try validateProxySettings(document);
    const bytes = try encode(allocator, document);
    defer allocator.free(bytes);
    try writeAtomically(io, dir, final_path, temp_path, bytes);
}

pub fn saveProxyStatusAtomic(
    allocator: std.mem.Allocator,
    io: std.Io,
    dir: std.Io.Dir,
    final_path: []const u8,
    temp_path: []const u8,
    document: ProxyStatusDocument,
) !void {
    try validateProxyStatus(document);
    const bytes = try encode(allocator, document);
    defer allocator.free(bytes);
    try writeAtomically(io, dir, final_path, temp_path, bytes);
}

pub fn loadSnapshots(allocator: std.mem.Allocator, io: std.Io, dir: std.Io.Dir, path: []const u8) !LoadedSnapshots {
    const bytes = try dir.readFileAlloc(io, path, allocator, .limited(max_document_bytes));
    defer allocator.free(bytes);
    return decodeSnapshots(allocator, bytes);
}

pub fn loadAttempts(allocator: std.mem.Allocator, io: std.Io, dir: std.Io.Dir, path: []const u8) !LoadedAttempts {
    const bytes = try dir.readFileAlloc(io, path, allocator, .limited(max_document_bytes));
    defer allocator.free(bytes);
    return decodeAttempts(allocator, bytes);
}

pub fn loadAppSettings(allocator: std.mem.Allocator, io: std.Io, dir: std.Io.Dir, path: []const u8) !LoadedAppSettings {
    const bytes = try dir.readFileAlloc(io, path, allocator, .limited(max_document_bytes));
    defer allocator.free(bytes);
    return decodeAppSettings(allocator, bytes);
}

pub fn loadProxySettings(allocator: std.mem.Allocator, io: std.Io, dir: std.Io.Dir, path: []const u8) !LoadedProxySettings {
    const bytes = try dir.readFileAlloc(io, path, allocator, .limited(max_document_bytes));
    defer allocator.free(bytes);
    return decodeProxySettings(allocator, bytes);
}

pub fn loadProxyStatus(allocator: std.mem.Allocator, io: std.Io, dir: std.Io.Dir, path: []const u8) !LoadedProxyStatus {
    const bytes = try dir.readFileAlloc(io, path, allocator, .limited(max_document_bytes));
    defer allocator.free(bytes);
    return decodeProxyStatus(allocator, bytes);
}
