const domain = @import("domain.zig");

pub const fixture_now_unix_s: i64 = 2_000_000_000;

pub const profiles = [_]domain.AccountProfile{
    .{ .id = "acct-codex-demo", .provider = .codex, .display_name = "Codex Demo", .storage_key = "codex-demo" },
    .{ .id = "acct-claude-demo", .provider = .claude, .display_name = "Claude Demo", .storage_key = "claude-demo" },
};

const fresh_windows = [_]domain.UsageWindow{
    .{ .kind = .session, .label = "Current session", .used_percent = 24, .reset_at_unix_s = fixture_now_unix_s + 3600, .duration_minutes = 300 },
    .{ .kind = .weekly, .label = "Current week", .used_percent = 61, .reset_at_unix_s = fixture_now_unix_s + 86_400, .duration_minutes = 10_080 },
};

const stale_windows = [_]domain.UsageWindow{
    .{ .kind = .session, .label = "Current session", .used_percent = 78, .reset_at_unix_s = fixture_now_unix_s - 60, .duration_minutes = 300 },
};

const partial_windows = [_]domain.UsageWindow{
    .{ .kind = .weekly, .label = "Current week", .used_percent = 43, .reset_at_unix_s = fixture_now_unix_s + 7200 },
};

pub const detailed_credit_items = [_]domain.ResetCreditDetail{
    .{ .id = "credit-demo-a", .label = "Reset credit A", .expires_at_unix_s = fixture_now_unix_s + 86_400 },
    .{ .id = "credit-demo-b", .label = "Reset credit B", .expires_at_unix_s = fixture_now_unix_s + 172_800 },
};

pub const expired_credit_items = [_]domain.ResetCreditDetail{
    .{ .id = "credit-demo-expired", .label = "Expired demo credit", .expires_at_unix_s = fixture_now_unix_s - 1 },
};

pub const count_only_credits: domain.ResetCreditSummary = .{
    .available_count = 3,
    .observed_at_unix_s = fixture_now_unix_s,
    .detail_status = .count_only,
};

pub const detailed_credits: domain.ResetCreditSummary = .{
    .available_count = 2,
    .observed_at_unix_s = fixture_now_unix_s,
    .detail_status = .detailed,
    .details = &detailed_credit_items,
};

pub const no_credits: domain.ResetCreditSummary = .{
    .available_count = 0,
    .observed_at_unix_s = fixture_now_unix_s,
    .detail_status = .detailed,
};

pub const expired_detail_credits: domain.ResetCreditSummary = .{
    .available_count = 1,
    .observed_at_unix_s = fixture_now_unix_s,
    .detail_status = .detailed,
    .details = &expired_credit_items,
};

pub const fresh_snapshot: domain.UsageSnapshot = .{
    .account_id = "acct-codex-demo",
    .provider = .codex,
    .captured_at_unix_s = fixture_now_unix_s,
    .status = .fresh,
    .windows = &fresh_windows,
    .reset_credits = detailed_credits,
};

pub const count_only_snapshot: domain.UsageSnapshot = .{
    .account_id = "acct-codex-demo",
    .provider = .codex,
    .captured_at_unix_s = fixture_now_unix_s,
    .status = .fresh,
    .windows = &fresh_windows,
    .reset_credits = count_only_credits,
};

pub const no_credit_snapshot: domain.UsageSnapshot = .{
    .account_id = "acct-codex-demo",
    .provider = .codex,
    .captured_at_unix_s = fixture_now_unix_s,
    .status = .fresh,
    .windows = &fresh_windows,
    .reset_credits = no_credits,
};

pub const stale_snapshot: domain.UsageSnapshot = .{
    .account_id = "acct-claude-demo",
    .provider = .claude,
    .captured_at_unix_s = fixture_now_unix_s - 86_400,
    .status = .stale,
    .windows = &stale_windows,
};

pub const partial_snapshot: domain.UsageSnapshot = .{
    .account_id = "acct-claude-demo",
    .provider = .claude,
    .captured_at_unix_s = fixture_now_unix_s,
    .status = .partial,
    .windows = &partial_windows,
    .refresh_error = .{ .kind = .malformed_response, .public_code = "partial-data", .retryable = true },
};

pub const reauth_snapshot: domain.UsageSnapshot = .{
    .account_id = "acct-claude-demo",
    .provider = .claude,
    .captured_at_unix_s = fixture_now_unix_s,
    .status = .reauth_required,
    .refresh_error = .{ .kind = .authentication, .public_code = "sign-in-required", .retryable = false },
};

pub const error_snapshot: domain.UsageSnapshot = .{
    .account_id = "acct-codex-demo",
    .provider = .codex,
    .captured_at_unix_s = fixture_now_unix_s,
    .status = .error_state,
    .refresh_error = .{ .kind = .timeout, .public_code = "refresh-timeout", .retryable = true },
};

pub const unavailable_snapshot: domain.UsageSnapshot = .{
    .account_id = "acct-codex-demo",
    .provider = .codex,
    .captured_at_unix_s = fixture_now_unix_s,
    .status = .unavailable,
    .refresh_error = .{ .kind = .provider_unavailable, .public_code = "provider-unavailable", .retryable = true },
};

pub const deferred_snapshot: domain.UsageSnapshot = .{
    .account_id = "acct-claude-demo",
    .provider = .claude,
    .captured_at_unix_s = fixture_now_unix_s,
    .status = .deferred,
};

pub const all_snapshots = [_]domain.UsageSnapshot{
    fresh_snapshot,
    stale_snapshot,
    partial_snapshot,
    reauth_snapshot,
    error_snapshot,
    unavailable_snapshot,
    deferred_snapshot,
};

pub fn preparedAttempt() domain.ResetAttempt {
    return domain.ResetAttempt.init(
        "attempt-demo-0001",
        "acct-codex-demo",
        "credit-demo-a",
        fixture_now_unix_s,
        2,
        fixture_now_unix_s + 1,
    ) catch unreachable;
}
