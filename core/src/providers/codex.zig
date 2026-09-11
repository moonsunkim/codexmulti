const std = @import("std");
const domain = @import("../domain.zig");
const transport = @import("../process_jsonl.zig");

pub const method_initialize = "initialize";
pub const method_initialized = "initialized";
pub const method_account_read = "account/read";
pub const method_rate_limits_read = "account/rateLimits/read";
pub const method_reset_credit_consume = "account/rateLimitResetCredit/consume";

pub const app_server_subcommand = "app-server";

pub fn appServerArgv(binary_path: []const u8) [2][]const u8 {
    return .{ binary_path, app_server_subcommand };
}

pub const ClientInfo = struct {
    name: []const u8 = "CodexMulti",
    title: ?[]const u8 = "CodexMulti",
    version: []const u8 = "0.1.0",
};

const InitializeParams = struct {
    clientInfo: struct {
        name: []const u8,
        title: ?[]const u8 = null,
        version: []const u8,
    },
    capabilities: struct {
        experimentalApi: bool = true,
    } = .{},
};

const InitializedParams = struct {};

const AccountReadParams = struct {};

const RateLimitsReadParams = struct {};

const ConsumeResetCreditParams = struct {
    idempotencyKey: []const u8,
    creditId: ?[]const u8 = null,
};

comptime {
    for (std.meta.fields(AccountReadParams)) |field| {
        if (std.mem.eql(u8, field.name, "refreshToken")) {
            @compileError("account/read must not carry refreshToken: an ordinary read never rotates credentials");
        }
    }
}

pub const max_usage_windows: usize = 8;
pub const max_credit_details: usize = 8;
pub const max_label_bytes: usize = 40;
pub const max_account_email_bytes: usize = 254;
pub const max_credit_id_bytes: usize = 96;
pub const max_idempotency_key_bytes: usize = 128;

pub const max_text_storage_bytes: usize =
    (max_usage_windows + max_credit_details * 2) * 96 + max_account_email_bytes;

pub const max_json_scratch_bytes: usize = 192 * 1024;

pub const max_reset_at_unix_s: i64 = 4_102_444_800;

pub const default_max_preflight_age_s: i64 = 120;

pub const public_code_sign_in_required = "sign-in-required";
pub const public_code_timeout = "refresh-timeout";
pub const public_code_canceled = "refresh-canceled";
pub const public_code_rejected = "refresh-rejected";
pub const public_code_malformed = "malformed-response";

pub const public_code_app_server_closed = "app-server-closed";

pub const public_code_app_server_unavailable = "app-server-unavailable";

pub const public_code_app_server_unsupported = "app-server-unsupported";

pub const public_code_account_home_invalid = "account-home-invalid";

pub const public_code_codex_home_mismatch = "codex-home-mismatch";

pub const public_code_usage_unsupported = "usage-unsupported";

pub const public_code_usage_incomplete = "usage-incomplete";

pub const public_code_reset_unconfirmed = "reset-not-confirmed";

pub const public_code_reset_key_invalid = "reset-key-invalid";

pub const public_code_reset_outcome_unknown = "reset-outcome-unknown";

pub const public_codes = [_][]const u8{
    public_code_sign_in_required,
    public_code_timeout,
    public_code_canceled,
    public_code_rejected,
    public_code_malformed,
    public_code_app_server_closed,
    public_code_app_server_unavailable,
    public_code_app_server_unsupported,
    public_code_account_home_invalid,
    public_code_codex_home_mismatch,
    public_code_usage_unsupported,
    public_code_usage_incomplete,
    public_code_reset_unconfirmed,
    public_code_reset_key_invalid,
    public_code_reset_outcome_unknown,
};

pub fn isPublicCode(code: []const u8) bool {
    for (public_codes) |known| {
        if (std.mem.eql(u8, known, code)) return true;
    }
    return false;
}

pub fn refreshErrorFromTransport(err: transport.TransportError) domain.RefreshError {
    return switch (err) {
        error.Timeout => .{ .kind = .timeout, .public_code = public_code_timeout, .retryable = true },
        error.EndOfStream => .{ .kind = .provider_unavailable, .public_code = public_code_app_server_closed, .retryable = true },
        error.Io => .{ .kind = .provider_unavailable, .public_code = public_code_app_server_closed, .retryable = true },
        error.MalformedFrame, error.FrameTooLarge, error.TooManyFrames => .{
            .kind = .malformed_response,
            .public_code = public_code_malformed,
            .retryable = false,
        },
        error.RequestTooLarge => .{ .kind = .unknown, .public_code = public_code_rejected, .retryable = false },
        error.SpawnFailed, error.Unsupported => .{
            .kind = .provider_unavailable,
            .public_code = public_code_app_server_unavailable,
            .retryable = false,
        },
        error.Canceled => .{ .kind = .unknown, .public_code = public_code_canceled, .retryable = true },
    };
}

pub fn refreshErrorFromRpcCode(code: i64) domain.RefreshError {
    return switch (code) {
        -32700, -32600, -32602 => .{ .kind = .unknown, .public_code = public_code_rejected, .retryable = false },
        -32601 => .{ .kind = .provider_unavailable, .public_code = public_code_app_server_unsupported, .retryable = false },
        else => .{ .kind = .provider_unavailable, .public_code = public_code_app_server_unavailable, .retryable = true },
    };
}

fn rpcCodeProvesNotExecuted(code: i64) bool {
    return switch (code) {
        -32700, -32600, -32601, -32602 => true,
        else => false,
    };
}

pub fn signInRequired() domain.RefreshError {
    return .{ .kind = .authentication, .public_code = public_code_sign_in_required, .retryable = false };
}

pub const Workspace = struct {
    frames: [transport.max_frame_bytes]u8 = @splat(0),
    request: [transport.max_request_bytes]u8 = @splat(0),
    json: [max_json_scratch_bytes]u8 = @splat(0),

    text: [max_text_storage_bytes]u8 = @splat(0),
    text_len: usize = 0,

    windows: [max_usage_windows]domain.UsageWindow = @splat(.{ .kind = .other, .label = "", .used_percent = 0 }),
    window_count: usize = 0,
    details: [max_credit_details]domain.ResetCreditDetail = @splat(.{ .id = "", .label = "" }),
    detail_count: usize = 0,
    credits: ?domain.ResetCreditSummary = null,

    dropped_windows: usize = 0,
    dropped_details: usize = 0,

    capped_windows: usize = 0,
    capped_details: usize = 0,

    pub fn resetReading(self: *Workspace) void {
        self.text_len = 0;
        self.window_count = 0;
        self.detail_count = 0;
        self.credits = null;
        self.dropped_windows = 0;
        self.dropped_details = 0;
        self.capped_windows = 0;
        self.capped_details = 0;
    }

    pub fn parsedWindows(self: *const Workspace) []const domain.UsageWindow {
        return self.windows[0..self.window_count];
    }

    pub fn parsedDetails(self: *const Workspace) []const domain.ResetCreditDetail {
        return self.details[0..self.detail_count];
    }

    fn dupeLabel(self: *Workspace, text: []const u8, limit: usize) ?[]const u8 {
        const start = self.text_len;
        var written: usize = 0;
        for (text) |byte| {
            if (written == limit) break;
            if (byte < 0x20 or byte > 0x7e) continue;
            if (self.text_len == self.text.len) return null;
            self.text[self.text_len] = byte;
            self.text_len += 1;
            written += 1;
        }
        if (written == 0) return null;
        return self.text[start..self.text_len];
    }

    fn dupeIdentifier(self: *Workspace, text: []const u8, limit: usize) ?[]const u8 {
        if (text.len == 0 or text.len > limit) return null;
        for (text) |byte| {
            if (byte < 0x20 or byte > 0x7e) return null;
        }
        if (text.len > self.text.len - self.text_len) return null;
        const start = self.text_len;
        @memcpy(self.text[start..][0..text.len], text);
        self.text_len += text.len;
        return self.text[start..self.text_len];
    }

    fn dupeEmail(self: *Workspace, text: []const u8) ?[]const u8 {
        var at_count: usize = 0;
        var at_index: usize = 0;
        for (text, 0..) |byte, index| {
            if (byte == '@') {
                at_count += 1;
                at_index = index;
            }
        }
        if (at_count != 1 or at_index == 0 or at_index + 1 == text.len) return null;
        return self.dupeIdentifier(text, max_account_email_bytes);
    }
};

pub const ParseError = error{MalformedResponse};

const RpcFailure = struct { code: i64 };

const Response = union(enum) {
    result: std.json.Value,
    failure: RpcFailure,
};

fn parseResponse(frame: []const u8, scratch: []u8) ParseError!Response {
    var fba: std.heap.FixedBufferAllocator = .init(scratch);
    const value = std.json.parseFromSliceLeaky(std.json.Value, fba.allocator(), frame, .{
        .duplicate_field_behavior = .use_last,
        .allocate = .alloc_if_needed,
    }) catch return error.MalformedResponse;

    const object = switch (value) {
        .object => |object| object,
        else => return error.MalformedResponse,
    };

    if (object.get("error")) |failure| {
        const code = switch (failure) {
            .object => |fields| asInteger(fields.get("code") orelse return error.MalformedResponse) orelse
                return error.MalformedResponse,
            else => return error.MalformedResponse,
        };
        return .{ .failure = .{ .code = code } };
    }
    return .{ .result = object.get("result") orelse return error.MalformedResponse };
}

fn asInteger(value: std.json.Value) ?i64 {
    return switch (value) {
        .integer => |number| number,
        .float => |number| integerFromFloat(number),

        .number_string => |text| std.fmt.parseInt(i64, text, 10) catch null,
        else => null,
    };
}

fn integerFromFloat(number: f64) ?i64 {
    if (!std.math.isFinite(number)) return null;
    const truncated = @trunc(number);
    if (truncated < -9_223_372_036_854_775_000.0 or truncated > 9_223_372_036_854_775_000.0) return null;
    return @intFromFloat(truncated);
}

fn asFloat(value: std.json.Value) ?f64 {
    return switch (value) {
        .integer => |number| @floatFromInt(number),
        .float => |number| if (std.math.isFinite(number)) number else null,
        .number_string => |text| blk: {
            const parsed = std.fmt.parseFloat(f64, text) catch break :blk null;
            break :blk if (std.math.isFinite(parsed)) parsed else null;
        },
        else => null,
    };
}

fn asString(value: std.json.Value) ?[]const u8 {
    return switch (value) {
        .string => |text| text,
        else => null,
    };
}

fn asObject(value: std.json.Value) ?std.json.ObjectMap {
    return switch (value) {
        .object => |object| object,
        else => null,
    };
}

fn memberOf(object: std.json.ObjectMap, name: []const u8) ?std.json.Value {
    const value = object.get(name) orelse return null;
    return switch (value) {
        .null => null,
        else => value,
    };
}

const WindowSlot = enum { primary, secondary, by_limit_id };

fn windowKind(slot: WindowSlot, duration_minutes: ?u32) domain.UsageWindowKind {
    if (slot == .by_limit_id) return .model_scoped;
    if (duration_minutes) |minutes| return if (minutes <= 24 * 60) .session else .weekly;
    return switch (slot) {
        .primary => .session,
        .secondary => .weekly,
        .by_limit_id => .model_scoped,
    };
}

fn staticLabel(kind: domain.UsageWindowKind) []const u8 {
    return switch (kind) {
        .session => "session",
        .weekly => "weekly",
        .model_scoped => "model",
        .other => "window",
    };
}

fn percentFrom(value: std.json.Value) ?u8 {
    const raw = asFloat(value) orelse return null;
    if (raw < 0) return 0;
    if (raw >= 100) return 100;
    return @intFromFloat(@round(raw));
}

fn resetAtFrom(value: ?std.json.Value) ?i64 {
    const raw = asInteger(value orelse return null) orelse return null;
    if (raw <= 0 or raw > max_reset_at_unix_s) return null;
    return raw;
}

fn durationFrom(value: ?std.json.Value) ?u32 {
    const raw = asInteger(value orelse return null) orelse return null;
    if (raw <= 0 or raw > std.math.maxInt(u32)) return null;
    return @intCast(raw);
}

fn normalizeWindow(
    workspace: *Workspace,
    value: std.json.Value,
    slot: WindowSlot,
    label_source: ?[]const u8,
) void {
    const object = asObject(value) orelse {
        workspace.dropped_windows += 1;
        return;
    };
    const percent_value = memberOf(object, "usedPercent") orelse {
        workspace.dropped_windows += 1;
        return;
    };
    const used_percent = percentFrom(percent_value) orelse {
        workspace.dropped_windows += 1;
        return;
    };
    if (workspace.window_count == max_usage_windows) {
        workspace.capped_windows += 1;
        return;
    }

    const duration_minutes = durationFrom(memberOf(object, "windowDurationMins"));
    const kind = windowKind(slot, duration_minutes);
    const label = if (label_source) |text|
        workspace.dupeLabel(text, max_label_bytes) orelse staticLabel(kind)
    else
        staticLabel(kind);

    workspace.windows[workspace.window_count] = .{
        .kind = kind,
        .label = label,
        .used_percent = used_percent,
        .reset_at_unix_s = resetAtFrom(memberOf(object, "resetsAt")),
        .duration_minutes = duration_minutes,
        .model_label = if (kind == .model_scoped) label else null,
    };
    workspace.window_count += 1;
}

fn normalizeSnapshotWindows(workspace: *Workspace, snapshot: std.json.Value, label_source: ?[]const u8) void {
    const object = asObject(snapshot) orelse {
        workspace.dropped_windows += 1;
        return;
    };
    if (memberOf(object, "primary")) |primary| {
        normalizeWindow(workspace, primary, if (label_source == null) .primary else .by_limit_id, label_source);
    }
    if (memberOf(object, "secondary")) |secondary| {
        normalizeWindow(workspace, secondary, if (label_source == null) .secondary else .by_limit_id, label_source);
    }
}

fn normalizeResetCredits(workspace: *Workspace, value: std.json.Value, observed_at_unix_s: i64) void {
    const object = asObject(value) orelse {
        workspace.dropped_details += 1;
        return;
    };
    const count_value = memberOf(object, "availableCount") orelse {
        workspace.dropped_details += 1;
        return;
    };
    const raw_count = asInteger(count_value) orelse {
        workspace.dropped_details += 1;
        return;
    };
    if (raw_count < 0) {
        workspace.dropped_details += 1;
        return;
    }
    const available_count: u32 = @intCast(@min(raw_count, @as(i64, std.math.maxInt(u32))));

    const credits_value = memberOf(object, "credits") orelse {
        workspace.credits = .{
            .available_count = available_count,
            .observed_at_unix_s = observed_at_unix_s,
            .detail_status = .count_only,
            .details = &.{},
        };
        return;
    };

    const items = switch (credits_value) {
        .array => |array| array.items,
        else => {
            workspace.dropped_details += 1;
            workspace.credits = .{
                .available_count = available_count,
                .observed_at_unix_s = observed_at_unix_s,
                .detail_status = .count_only,
                .details = &.{},
            };
            return;
        },
    };

    for (items) |item| {
        if (workspace.detail_count == max_credit_details) {
            workspace.capped_details += 1;
            continue;
        }

        if (workspace.detail_count == available_count) {
            workspace.capped_details += 1;
            continue;
        }
        const fields = asObject(item) orelse {
            workspace.dropped_details += 1;
            continue;
        };

        const id_value = memberOf(fields, "id") orelse {
            workspace.dropped_details += 1;
            continue;
        };
        const id_text = asString(id_value) orelse {
            workspace.dropped_details += 1;
            continue;
        };
        const id = workspace.dupeIdentifier(id_text, max_credit_id_bytes) orelse {
            workspace.dropped_details += 1;
            continue;
        };

        const label_source = if (memberOf(fields, "description")) |description|
            asString(description)
        else if (memberOf(fields, "resetType")) |reset_type|
            asString(reset_type)
        else
            null;
        const label = if (label_source) |text|
            workspace.dupeLabel(text, max_label_bytes) orelse "reset credit"
        else
            "reset credit";

        workspace.details[workspace.detail_count] = .{
            .id = id,
            .label = label,
            .expires_at_unix_s = resetAtFrom(memberOf(fields, "expiresAt")),
        };
        workspace.detail_count += 1;
    }

    workspace.credits = .{
        .available_count = available_count,
        .observed_at_unix_s = observed_at_unix_s,
        .detail_status = .detailed,
        .details = workspace.parsedDetails(),
    };
}

pub fn normalizeRateLimits(workspace: *Workspace, result: std.json.Value, observed_at_unix_s: i64) ParseError!void {
    const object = asObject(result) orelse return error.MalformedResponse;

    if (memberOf(object, "rateLimits")) |snapshot| {
        normalizeSnapshotWindows(workspace, snapshot, null);
    }

    if (memberOf(object, "rateLimitsByLimitId")) |by_limit_id| {
        if (asObject(by_limit_id)) |entries| {
            var it = entries.iterator();
            while (it.next()) |entry| {
                const snapshot = switch (entry.value_ptr.*) {
                    .null => continue,
                    else => entry.value_ptr.*,
                };
                const name = if (asObject(snapshot)) |fields| blk: {
                    const named = memberOf(fields, "limitName") orelse break :blk entry.key_ptr.*;
                    break :blk asString(named) orelse entry.key_ptr.*;
                } else entry.key_ptr.*;
                normalizeSnapshotWindows(workspace, snapshot, name);
            }
        } else {
            workspace.dropped_windows += 1;
        }
    }

    if (memberOf(object, "rateLimitResetCredits")) |credits| {
        normalizeResetCredits(workspace, credits, observed_at_unix_s);
    }
}

pub fn resetOutcomeFromText(text: []const u8) ?domain.ResetOutcome {
    if (std.mem.eql(u8, text, "reset")) return .reset;
    if (std.mem.eql(u8, text, "nothingToReset")) return .nothing_to_reset;
    if (std.mem.eql(u8, text, "noCredit")) return .no_credit;
    if (std.mem.eql(u8, text, "alreadyRedeemed")) return .already_redeemed;
    return null;
}

pub const Stage = enum {
    connected,

    initialized,
    account_read,
    rate_limits_read,
};

pub const RefreshRequest = struct {
    account_id: []const u8,
    now_unix_s: i64,
};

pub const AccountMetadata = struct {
    email: ?[]const u8 = null,
    email_observed: bool = false,
    plan_label: ?[]const u8 = null,
    plan_observed: bool = false,

    pub fn hasObservation(self: AccountMetadata) bool {
        return self.email_observed or self.plan_observed;
    }
};

pub const RefreshOutcome = struct {
    stage: Stage = .connected,
    status: domain.SnapshotStatus = .unavailable,
    windows: []const domain.UsageWindow = &.{},
    reset_credits: ?domain.ResetCreditSummary = null,
    failure: ?domain.RefreshError = null,

    home_verified: bool = false,
    account_metadata: AccountMetadata = .{},

    pub fn succeeded(self: RefreshOutcome) bool {
        return self.failure == null;
    }

    pub fn hasObservation(self: RefreshOutcome) bool {
        return self.windows.len != 0 or self.reset_credits != null;
    }

    pub fn snapshot(self: RefreshOutcome, request: RefreshRequest) domain.UsageSnapshot {
        return .{
            .account_id = request.account_id,
            .provider = .codex,
            .captured_at_unix_s = request.now_unix_s,
            .status = self.status,
            .windows = self.windows,
            .reset_credits = self.reset_credits,
            .refresh_error = self.failure,
        };
    }

    pub fn snapshotPreservingLastSuccess(
        self: RefreshOutcome,
        request: RefreshRequest,
        previous: ?domain.UsageSnapshot,
    ) domain.UsageSnapshot {
        if (self.hasObservation()) return self.snapshot(request);
        const failure = self.failure orelse return self.snapshot(request);
        const prior = previous orelse return self.snapshot(request);
        return .{
            .account_id = request.account_id,
            .provider = .codex,
            .captured_at_unix_s = prior.captured_at_unix_s,
            .status = if (failure.kind == .authentication) .reauth_required else .stale,
            .windows = prior.windows,
            .reset_credits = prior.reset_credits,
            .refresh_error = failure,
        };
    }

    fn fail(self: RefreshOutcome, failure: domain.RefreshError) RefreshOutcome {
        var updated = self;
        updated.failure = failure;
        updated.status = switch (failure.kind) {
            .authentication => .reauth_required,
            .malformed_response => .error_state,
            else => .unavailable,
        };
        return updated;
    }
};

pub const ConsumeRequest = struct {
    account_id: []const u8,

    attempt: *const domain.ResetAttempt,

    credit_id: ?[]const u8 = null,
    now_unix_s: i64,
    max_preflight_age_s: i64 = default_max_preflight_age_s,
};

pub const ConsumeOutcome = union(enum) {
    completed: domain.ResetOutcome,

    ambiguous: domain.RefreshError,

    rejected: domain.RefreshError,

    pub fn requestWasSent(self: ConsumeOutcome) bool {
        return switch (self) {
            .completed, .ambiguous => true,
            .rejected => false,
        };
    }

    pub fn failure(self: ConsumeOutcome) ?domain.RefreshError {
        return switch (self) {
            .completed => null,
            .ambiguous, .rejected => |err| err,
        };
    }
};

pub const Config = struct {
    codex_home: []const u8,
    client: ClientInfo = .{},
    startup_timeout_ms: u32 = transport.default_startup_timeout_ms,
    request_timeout_ms: u32 = transport.default_request_timeout_ms,
};

pub const Adapter = struct {
    config: Config,

    pub fn refresh(
        self: Adapter,
        connection: *transport.Connection,
        workspace: *Workspace,
        request: RefreshRequest,
    ) RefreshOutcome {
        workspace.resetReading();
        var outcome: RefreshOutcome = .{};

        if (self.handshake(connection, workspace, &outcome)) |failure| return outcome.fail(failure);
        if (self.readAccount(connection, workspace, &outcome)) |failure| return outcome.fail(failure);
        if (self.readRateLimits(connection, workspace, request, &outcome)) |failure| return outcome.fail(failure);
        return outcome;
    }

    pub fn consumeResetCredit(
        self: Adapter,
        connection: *transport.Connection,
        workspace: *Workspace,
        request: ConsumeRequest,
    ) ConsumeOutcome {
        if (consumeGuard(request)) |failure| return .{ .rejected = failure };

        var handshake_outcome: RefreshOutcome = .{};
        if (self.handshake(connection, workspace, &handshake_outcome)) |failure| return .{ .rejected = failure };

        const id = connection.allocateId();
        connection.arm(self.config.request_timeout_ms);
        connection.sendRequest(id, method_reset_credit_consume, ConsumeResetCreditParams{
            .idempotencyKey = request.attempt.idempotency_key,
            .creditId = request.credit_id,
        }, &workspace.request) catch |err| return .{ .rejected = refreshErrorFromTransport(err) };

        const frame = connection.awaitResponse(id) catch |err| return .{ .ambiguous = ambiguousFrom(refreshErrorFromTransport(err)) };
        const response = parseResponse(frame, &workspace.json) catch return .{
            .ambiguous = ambiguousFrom(.{ .kind = .malformed_response, .public_code = public_code_malformed, .retryable = false }),
        };

        switch (response) {
            .failure => |rpc| {
                const failure = refreshErrorFromRpcCode(rpc.code);
                if (rpcCodeProvesNotExecuted(rpc.code)) return .{ .rejected = failure };
                return .{ .ambiguous = ambiguousFrom(failure) };
            },
            .result => |value| {
                const object = asObject(value) orelse return .{ .ambiguous = ambiguousFrom(malformedResponse()) };
                const outcome_value = memberOf(object, "outcome") orelse return .{ .ambiguous = ambiguousFrom(malformedResponse()) };
                const text = asString(outcome_value) orelse return .{ .ambiguous = ambiguousFrom(malformedResponse()) };
                const outcome = resetOutcomeFromText(text) orelse return .{ .ambiguous = ambiguousFrom(malformedResponse()) };
                return .{ .completed = outcome };
            },
        }
    }

    fn handshake(
        self: Adapter,
        connection: *transport.Connection,
        workspace: *Workspace,
        outcome: *RefreshOutcome,
    ) ?domain.RefreshError {
        transport.validateCodexHome(self.config.codex_home) catch return .{
            .kind = .unknown,
            .public_code = public_code_account_home_invalid,
            .retryable = false,
        };

        if (connection.initialized) {
            outcome.home_verified = connection.home_verified;
            outcome.stage = .initialized;
            return null;
        }

        const id = connection.allocateId();
        connection.arm(self.config.startup_timeout_ms);
        connection.sendRequest(id, method_initialize, InitializeParams{
            .clientInfo = .{
                .name = self.config.client.name,
                .title = self.config.client.title,
                .version = self.config.client.version,
            },
        }, &workspace.request) catch |err| return refreshErrorFromTransport(err);

        const result = switch (exchangeResult(connection, workspace, id)) {
            .failure => |failure| return failure,
            .value => |value| value,
        };
        const object = asObject(result) orelse return malformedResponse();

        const reported = memberOf(object, "codexHome") orelse return homeMismatch();
        const home = asString(reported) orelse return homeMismatch();
        if (!std.mem.eql(u8, home, self.config.codex_home)) return homeMismatch();

        outcome.home_verified = true;
        connection.arm(self.config.request_timeout_ms);
        connection.sendNotification(method_initialized, InitializedParams{}, &workspace.request) catch |err|
            return refreshErrorFromTransport(err);
        outcome.stage = .initialized;
        connection.initialized = true;
        connection.home_verified = true;
        return null;
    }

    fn readAccount(
        self: Adapter,
        connection: *transport.Connection,
        workspace: *Workspace,
        outcome: *RefreshOutcome,
    ) ?domain.RefreshError {
        const id = connection.allocateId();
        connection.arm(self.config.request_timeout_ms);
        connection.sendRequest(id, method_account_read, AccountReadParams{}, &workspace.request) catch |err|
            return refreshErrorFromTransport(err);

        const result = switch (exchangeResult(connection, workspace, id)) {
            .failure => |failure| return failure,
            .value => |value| value,
        };
        const object = asObject(result) orelse return malformedResponse();

        const account_value = object.get("account") orelse return signInRequired();
        const account = asObject(account_value) orelse return signInRequired();
        const type_text = if (account.get("type")) |value| asString(value) else null;
        if (type_text != null and std.mem.eql(u8, type_text.?, "chatgpt")) {
            if (account.get("email")) |value| {
                outcome.account_metadata.email_observed = true;
                outcome.account_metadata.email = switch (value) {
                    .string => |email| workspace.dupeEmail(email),
                    .null => null,
                    else => null,
                };
            }
            if (account.get("planType")) |value| {
                outcome.account_metadata.plan_observed = true;
                outcome.account_metadata.plan_label = if (asString(value)) |plan|
                    accountPlanLabel(plan)
                else
                    null;
            }
        }
        outcome.stage = .account_read;
        return null;
    }

    fn readRateLimits(
        self: Adapter,
        connection: *transport.Connection,
        workspace: *Workspace,
        request: RefreshRequest,
        outcome: *RefreshOutcome,
    ) ?domain.RefreshError {
        const id = connection.allocateId();
        connection.arm(self.config.request_timeout_ms);
        connection.sendRequest(id, method_rate_limits_read, RateLimitsReadParams{}, &workspace.request) catch |err|
            return refreshErrorFromTransport(err);

        const result = switch (exchangeResult(connection, workspace, id)) {
            .failure => |failure| return failure,
            .value => |value| value,
        };
        normalizeRateLimits(workspace, result, request.now_unix_s) catch return malformedResponse();

        outcome.stage = .rate_limits_read;
        outcome.windows = workspace.parsedWindows();
        outcome.reset_credits = workspace.credits;

        if (!outcome.hasObservation()) {
            outcome.status = .partial;
            outcome.failure = .{
                .kind = .malformed_response,
                .public_code = public_code_usage_unsupported,
                .retryable = false,
            };
            return null;
        }
        if (workspace.dropped_windows != 0 or workspace.dropped_details != 0) {
            outcome.status = .partial;
            outcome.failure = .{
                .kind = .malformed_response,
                .public_code = public_code_usage_incomplete,
                .retryable = true,
            };
            return null;
        }
        outcome.status = .fresh;
        return null;
    }
};

pub fn accountPlanLabel(plan: []const u8) ?[]const u8 {
    const mappings = [_]struct { key: []const u8, label: []const u8 }{
        .{ .key = "free", .label = "Free" },
        .{ .key = "go", .label = "Go" },
        .{ .key = "plus", .label = "Plus" },
        .{ .key = "pro", .label = "Pro 20x" },
        .{ .key = "prolite", .label = "Pro 5x" },
        .{ .key = "team", .label = "Team" },
        .{ .key = "self_serve_business_usage_based", .label = "Business · usage based" },
        .{ .key = "business", .label = "Business" },
        .{ .key = "enterprise_cbp_usage_based", .label = "Enterprise · usage based" },
        .{ .key = "enterprise", .label = "Enterprise" },
        .{ .key = "edu", .label = "Edu" },
    };
    for (mappings) |mapping| {
        if (std.mem.eql(u8, plan, mapping.key)) return mapping.label;
    }
    return null;
}

const Step = union(enum) {
    value: std.json.Value,
    failure: domain.RefreshError,
};

fn exchangeResult(connection: *transport.Connection, workspace: *Workspace, id: i64) Step {
    const frame = connection.awaitResponse(id) catch |err| return .{ .failure = refreshErrorFromTransport(err) };
    const response = parseResponse(frame, &workspace.json) catch return .{ .failure = malformedResponse() };
    return switch (response) {
        .result => |value| .{ .value = value },
        .failure => |rpc| .{ .failure = refreshErrorFromRpcCode(rpc.code) },
    };
}

fn malformedResponse() domain.RefreshError {
    return .{ .kind = .malformed_response, .public_code = public_code_malformed, .retryable = false };
}

fn homeMismatch() domain.RefreshError {
    return .{ .kind = .unknown, .public_code = public_code_codex_home_mismatch, .retryable = false };
}

fn ambiguousFrom(failure: domain.RefreshError) domain.RefreshError {
    return .{ .kind = failure.kind, .public_code = public_code_reset_outcome_unknown, .retryable = false };
}

fn consumeGuard(request: ConsumeRequest) ?domain.RefreshError {
    const attempt = request.attempt;
    if (!isUsableIdempotencyKey(attempt.idempotency_key)) return .{
        .kind = .unknown,
        .public_code = public_code_reset_key_invalid,
        .retryable = false,
    };
    if (!std.mem.eql(u8, attempt.account_id, request.account_id)) return unconfirmed();
    attempt.assertSameOperation(request.account_id, request.credit_id) catch return unconfirmed();
    if (request.credit_id) |credit_id| {
        if (!isUsableIdempotencyKey(credit_id)) return .{
            .kind = .unknown,
            .public_code = public_code_reset_key_invalid,
            .retryable = false,
        };
    }

    if (attempt.phase != .submitted or attempt.outcome != null) return unconfirmed();
    if (attempt.preflight_available_count == 0) return unconfirmed();
    if (!attempt.preflightIsFresh(request.now_unix_s, request.max_preflight_age_s)) return unconfirmed();
    if (attempt.confirmed_at_unix_s < attempt.preflight_observed_at_unix_s) return unconfirmed();
    return null;
}

fn unconfirmed() domain.RefreshError {
    return .{ .kind = .unknown, .public_code = public_code_reset_unconfirmed, .retryable = false };
}

fn isUsableIdempotencyKey(key: []const u8) bool {
    if (key.len == 0 or key.len > max_idempotency_key_bytes) return false;
    for (key) |byte| {
        if (byte < 0x20 or byte > 0x7e) return false;
    }
    return true;
}
