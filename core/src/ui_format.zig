const std = @import("std");
const domain = @import("domain.zig");
const contracts = @import("ui_contracts.zig");
const strings = @import("strings.zig");
const c = @cImport({
    @cInclude("stdlib.h");
    @cInclude("time.h");
});

const AuthState = contracts.AuthState;
const Freshness = contracts.Freshness;
const WindowView = contracts.WindowView;
const AccountView = contracts.AccountView;
const ServiceCapabilities = contracts.ServiceCapabilities;
const CommandOutcome = contracts.CommandOutcome;
const TimeZone = contracts.TimeZone;
const TrayItem = contracts.TrayItem;
const max_tray_items = contracts.max_tray_items;
const max_line_bytes = contracts.max_line_bytes;
const tray_command_refresh_all = contracts.tray_command_refresh_all;
const tray_command_open_details = contracts.tray_command_open_details;
const tray_command_quit = contracts.tray_command_quit;
const default_copy = strings.system;

pub const Localized = struct {
    copy: strings.Catalog,

    pub fn init(language: strings.Language) Localized {
        return .{ .copy = strings.catalog(language) };
    }

    pub fn displayPlanLabel(self: Localized, stored: []const u8) []const u8 {
        return displayPlanLabelWith(self.copy, stored);
    }

    pub fn resetPhrase(self: Localized, buffer: []u8, reset_at_unix_s: ?i64, now_unix_s: i64) []const u8 {
        return resetPhraseWith(self.copy, buffer, reset_at_unix_s, now_unix_s);
    }

    pub fn remainingPhrase(self: Localized, buffer: []u8, remaining_s: i64) []const u8 {
        return remainingPhraseWith(self.copy, buffer, remaining_s);
    }

    pub fn providerName(self: Localized, provider: domain.Provider) []const u8 {
        return providerNameWith(self.copy, provider);
    }

    pub fn humanizeWindowLabel(self: Localized, buffer: []u8, label: []const u8) []const u8 {
        return humanizeWindowLabelWith(self.copy, buffer, label);
    }

    pub fn freshnessText(self: Localized, freshness: Freshness) []const u8 {
        return freshnessTextWith(self.copy, freshness);
    }

    pub fn freshnessPhrase(self: Localized, freshness: Freshness) []const u8 {
        return freshnessPhraseWith(self.copy, freshness);
    }

    pub fn attemptReason(self: Localized, code: []const u8) []const u8 {
        return attemptReasonWith(self.copy, code);
    }

    pub fn attemptMessage(self: Localized, code: []const u8) []const u8 {
        return attemptMessageWith(self.copy, code);
    }

    pub fn authStateText(self: Localized, state: AuthState) []const u8 {
        return authStateTextWith(self.copy, state);
    }

    pub fn snapshotStatusText(self: Localized, status: ?domain.SnapshotStatus) []const u8 {
        return snapshotStatusTextWith(self.copy, status);
    }

    pub fn noWindowWording(self: Localized, row: AccountView) []const u8 {
        return noWindowWordingWith(self.copy, row);
    }

    pub fn serviceText(self: Localized, capabilities: ServiceCapabilities) []const u8 {
        return serviceTextWith(self.copy, capabilities);
    }

    pub fn formatLocal(self: Localized, buffer: []u8, unix_s: i64, time_zone: TimeZone) []const u8 {
        return formatLocalWith(self.copy, buffer, unix_s, time_zone);
    }

    pub fn agoPhrase(self: Localized, buffer: []u8, now_unix_s: i64, at_unix_s: i64) []const u8 {
        return agoPhraseWith(self.copy, buffer, now_unix_s, at_unix_s);
    }

    pub fn shortLocal(self: Localized, buffer: []u8, now_unix_s: i64, at_unix_s: i64, time_zone: TimeZone) []const u8 {
        return shortLocalWith(self.copy, buffer, now_unix_s, at_unix_s, time_zone);
    }

    pub fn mediumLocal(self: Localized, buffer: []u8, unix_s: i64, time_zone: TimeZone) []const u8 {
        return mediumLocalWith(self.copy, buffer, unix_s, time_zone);
    }

    pub fn countdownPhrase(self: Localized, buffer: []u8, reset_at_unix_s: ?i64, now_unix_s: i64) []const u8 {
        return countdownPhraseWith(self.copy, buffer, reset_at_unix_s, now_unix_s);
    }

    pub fn durationPhrase(self: Localized, buffer: []u8, minutes: u32) []const u8 {
        return durationPhraseWith(self.copy, buffer, minutes);
    }
};

pub const CodexPlanClass = enum {
    weekly_only,

    session_and_weekly,

    all_windows,
};

pub fn displayPlanLabel(stored: []const u8) []const u8 {
    return displayPlanLabelWith(default_copy, stored);
}

fn displayPlanLabelWith(localized: strings.Catalog, stored: []const u8) []const u8 {
    if (std.mem.eql(u8, stored, "Pro") or std.mem.eql(u8, stored, "x20")) return localized.text(.plan_pro_20x);
    if (std.mem.eql(u8, stored, "Pro Lite") or std.mem.eql(u8, stored, "x5")) return localized.text(.plan_pro_5x);
    return stored;
}

pub fn codexPlanClass(plan_label: ?[]const u8) CodexPlanClass {
    const plan = plan_label orelse return .all_windows;
    if (std.mem.eql(u8, plan, "Pro 5x") or
        std.mem.eql(u8, plan, "Pro 20x") or
        std.mem.eql(u8, plan, "x5") or
        std.mem.eql(u8, plan, "x20") or
        std.mem.eql(u8, plan, "Pro") or
        std.mem.eql(u8, plan, "Pro Lite")) return .weekly_only;
    if (std.mem.eql(u8, plan, "Plus")) return .session_and_weekly;
    return .all_windows;
}

fn selectMostConstraining(
    windows: anytype,
    plan_class: CodexPlanClass,
    include_model_scoped: bool,
) ?usize {
    var best: ?usize = null;
    for (windows, 0..) |candidate, index| {
        const eligible = if (candidate.kind == .model_scoped)
            include_model_scoped
        else switch (plan_class) {
            .weekly_only => candidate.kind == .weekly,
            .session_and_weekly => candidate.kind == .session or candidate.kind == .weekly,
            .all_windows => true,
        };
        if (!eligible) continue;
        const current_index = best orelse {
            best = index;
            continue;
        };
        const current = windows[current_index];
        if (candidate.used_percent > current.used_percent) {
            best = index;
            continue;
        }
        if (candidate.used_percent < current.used_percent) continue;
        const candidate_reset = candidate.reset_at_unix_s orelse continue;
        const current_reset = current.reset_at_unix_s orelse {
            best = index;
            continue;
        };
        if (candidate_reset < current_reset) best = index;
    }
    return best;
}

pub fn selectPrimaryWindow(windows: []const WindowView) ?usize {
    return selectMostConstraining(windows, .all_windows, true);
}

pub fn selectCodexPrimaryWindow(plan_label: ?[]const u8, windows: anytype) ?usize {
    return selectConfiguredCodexPrimaryWindow(plan_label, windows, .auto, false);
}

pub fn selectConfiguredCodexPrimaryWindow(
    plan_label: ?[]const u8,
    windows: anytype,
    preference: contracts.CodexUsageWindow,
    include_model_scoped: bool,
) ?usize {
    const preferred_kind: ?domain.UsageWindowKind = switch (preference) {
        .auto => null,
        .weekly => .weekly,
        .session => .session,
    };
    if (preferred_kind) |kind| {
        var preferred: ?usize = null;
        for (windows, 0..) |candidate, index| {
            if (candidate.kind != kind) continue;
            const current_index = preferred orelse {
                preferred = index;
                continue;
            };
            const current = windows[current_index];
            if (candidate.used_percent > current.used_percent or
                (candidate.used_percent == current.used_percent and
                    candidate.reset_at_unix_s != null and
                    (current.reset_at_unix_s == null or candidate.reset_at_unix_s.? < current.reset_at_unix_s.?)))
            {
                preferred = index;
            }
        }
        if (preferred != null) return preferred;
    }
    return selectMostConstraining(windows, codexPlanClass(plan_label), include_model_scoped);
}

pub fn resetPhrase(buffer: []u8, reset_at_unix_s: ?i64, now_unix_s: i64) []const u8 {
    return resetPhraseWith(default_copy, buffer, reset_at_unix_s, now_unix_s);
}

fn resetPhraseWith(localized: strings.Catalog, buffer: []u8, reset_at_unix_s: ?i64, now_unix_s: i64) []const u8 {
    const reset_at = reset_at_unix_s orelse return localized.text(.reset_time_not_reported);
    if (reset_at - now_unix_s <= 0) return localized.text(.reset_passed_refresh);
    var countdown: [max_line_bytes]u8 = undefined;
    const phrase = formatCountdownWith(localized, &countdown, reset_at - now_unix_s);
    var writer = std.Io.Writer.fixed(buffer);
    localized.write(&writer, .reset_phrase, .{phrase});
    return writer.buffered();
}

pub fn remainingPhrase(buffer: []u8, remaining_s: i64) []const u8 {
    return remainingPhraseWith(default_copy, buffer, remaining_s);
}

fn remainingPhraseWith(localized: strings.Catalog, buffer: []u8, remaining_s: i64) []const u8 {
    if (remaining_s <= 0) return localized.text(.countdown_passed_refresh);
    var writer = std.Io.Writer.fixed(buffer);
    const days = @divTrunc(remaining_s, std.time.s_per_day);
    const hours = @divTrunc(remaining_s - days * std.time.s_per_day, 3600);
    const minutes = @divTrunc(remaining_s - days * std.time.s_per_day - hours * 3600, 60);
    if (days > 0) {
        localized.write(&writer, .remaining_days, .{ days, hours });
    } else if (hours > 0) {
        localized.write(&writer, .remaining_hours, .{ hours, minutes });
    } else if (minutes > 0) {
        localized.write(&writer, .remaining_minutes, .{minutes});
    } else {
        localized.write(&writer, .remaining_seconds, .{remaining_s});
    }
    return writer.buffered();
}

pub fn providerName(provider: domain.Provider) []const u8 {
    return providerNameWith(default_copy, provider);
}

fn providerNameWith(localized: strings.Catalog, provider: domain.Provider) []const u8 {
    return switch (provider) {
        .claude => localized.text(.provider_unsupported),
        .codex => localized.text(.provider_codex),
    };
}

pub fn humanizeWindowLabel(buffer: []u8, label: []const u8) []const u8 {
    return humanizeWindowLabelWith(default_copy, buffer, label);
}

fn humanizeWindowLabelWith(localized: strings.Catalog, buffer: []u8, label: []const u8) []const u8 {
    const known = [_]struct { source: []const u8, key: strings.StaticKey }{
        .{ .source = "weekly", .key = .window_weekly },
        .{ .source = "session", .key = .window_session },
        .{ .source = "daily", .key = .window_daily },
        .{ .source = "monthly", .key = .window_monthly },
        .{ .source = "hourly", .key = .window_hourly },
        .{ .source = "codex", .key = .window_codex },
    };
    for (known) |candidate| {
        if (std.mem.eql(u8, label, candidate.source)) return localized.text(candidate.key);
        if (!std.ascii.eqlIgnoreCase(label, candidate.source)) continue;
        if (localized.language == .ko) return localized.text(candidate.key);
        const take = @min(label.len, buffer.len);
        if (take == 0) return label;
        @memcpy(buffer[0..take], label[0..take]);
        buffer[0] = std.ascii.toUpper(buffer[0]);
        return buffer[0..take];
    }
    return label;
}

pub fn freshnessText(freshness: Freshness) []const u8 {
    return freshnessTextWith(default_copy, freshness);
}

fn freshnessTextWith(localized: strings.Catalog, freshness: Freshness) []const u8 {
    return switch (freshness) {
        .never_refreshed => localized.text(.freshness_never),
        .as_of => localized.text(.freshness_as_of),
        .saved_snapshot => localized.text(.freshness_saved_snapshot),
        .refresh_failed => localized.text(.freshness_refresh_failed),
        .reauth_required => localized.text(.freshness_reauthentication_required),
        .usage_unavailable => localized.text(.freshness_usage_unavailable),
        .refresh_deferred => localized.text(.freshness_refresh_deferred),
        .reset_passed => localized.text(.freshness_reset_passed),
    };
}

pub fn freshnessPhrase(freshness: Freshness) []const u8 {
    return freshnessPhraseWith(default_copy, freshness);
}

fn freshnessPhraseWith(localized: strings.Catalog, freshness: Freshness) []const u8 {
    return switch (freshness) {
        .never_refreshed => localized.text(.freshness_never_lower),
        .as_of => localized.text(.freshness_as_of_lower),
        .saved_snapshot => localized.text(.freshness_saved_snapshot_lower),
        .refresh_failed => localized.text(.freshness_refresh_failed_lower),
        .reauth_required => localized.text(.freshness_reauthentication_required_lower),
        .usage_unavailable => localized.text(.freshness_usage_unavailable_lower),
        .refresh_deferred => localized.text(.freshness_refresh_deferred_lower),
        .reset_passed => localized.text(.freshness_reset_passed_lower),
    };
}

pub fn attemptReason(code: []const u8) []const u8 {
    return attemptReasonWith(default_copy, code);
}

fn attemptReasonWith(localized: strings.Catalog, code: []const u8) []const u8 {
    const mappings = [_]struct { code: []const u8, key: strings.StaticKey }{
        .{ .code = "app-server-closed", .key = .attempt_reason_helper_closed },
        .{ .code = "app-server-unavailable", .key = .attempt_reason_helper_unavailable },
        .{ .code = "app-server-unsupported", .key = .attempt_reason_cli_too_old },
        .{ .code = "refresh-timeout", .key = .attempt_reason_timed_out },
        .{ .code = "refresh-canceled", .key = .attempt_reason_canceled },
        .{ .code = "refresh-rejected", .key = .attempt_reason_refresh_rejected },
        .{ .code = "malformed-response", .key = .attempt_reason_malformed_reply },
        .{ .code = "sign-in-required", .key = .attempt_reason_sign_in_required },
        .{ .code = "account-home-invalid", .key = .attempt_reason_workspace_invalid },
        .{ .code = "codex-home-mismatch", .key = .attempt_reason_wrong_workspace },
        .{ .code = "usage-unsupported", .key = .attempt_reason_no_usage_window },
        .{ .code = "usage-incomplete", .key = .attempt_reason_incomplete_reading },
        .{ .code = "login-unsupported", .key = .attempt_reason_sign_in_unsupported },
        .{ .code = "login-spawn-failed", .key = .attempt_reason_sign_in_could_not_start },
        .{ .code = "login-timeout", .key = .attempt_reason_sign_in_timed_out },
        .{ .code = "login-canceled", .key = .attempt_reason_sign_in_canceled },
        .{ .code = "login-io", .key = .attempt_reason_sign_in_handoff_failed },
        .{ .code = "login-rejected", .key = .attempt_reason_sign_in_rejected },
        .{ .code = "login-noisy", .key = .attempt_reason_sign_in_output_unclear },
        .{ .code = "login-import-unavailable", .key = .attempt_reason_credential_not_saved },
        .{ .code = "login-import-incomplete", .key = .attempt_reason_credential_incomplete },
        .{ .code = "keychain-access-repair-required", .key = .attempt_reason_keychain_repair_needed },
        .{ .code = "account-unknown", .key = .attempt_reason_account_unknown },
        .{ .code = "account-busy", .key = .attempt_reason_account_busy },
        .{ .code = "account-disabled", .key = .attempt_reason_account_disabled },
        .{ .code = "provider-mismatch", .key = .attempt_reason_provider_mismatch },
        .{ .code = "reset-not-confirmed", .key = .attempt_reason_reset_unconfirmed },
        .{ .code = "reset-key-invalid", .key = .attempt_reason_reset_key_invalid },
        .{ .code = "reset-outcome-unknown", .key = .attempt_reason_reset_outcome_unknown },
    };
    for (mappings) |mapping| {
        if (std.mem.eql(u8, code, mapping.code)) return localized.text(mapping.key);
    }
    return localized.text(.attempt_reason_refresh_failed);
}

pub fn attemptMessage(code: []const u8) []const u8 {
    return attemptMessageWith(default_copy, code);
}

fn attemptMessageWith(localized: strings.Catalog, code: []const u8) []const u8 {
    const mappings = [_]struct { code: []const u8, key: strings.StaticKey }{
        .{ .code = "app-server-closed", .key = .attempt_message_helper_closed },
        .{ .code = "app-server-unavailable", .key = .attempt_message_helper_unavailable },
        .{ .code = "app-server-unsupported", .key = .attempt_message_cli_unsupported },
        .{ .code = "refresh-timeout", .key = .attempt_message_refresh_timeout },
        .{ .code = "sign-in-required", .key = .attempt_message_sign_in_required },
        .{ .code = "codex-home-mismatch", .key = .attempt_message_wrong_workspace },
        .{ .code = "usage-unsupported", .key = .attempt_message_usage_unsupported },
        .{ .code = "usage-incomplete", .key = .attempt_message_usage_incomplete },
        .{ .code = "login-import-unavailable", .key = .attempt_message_login_import_unavailable },
        .{ .code = "login-import-incomplete", .key = .attempt_message_login_import_incomplete },
        .{ .code = "login-rejected", .key = .attempt_message_login_rejected },
        .{ .code = "login-timeout", .key = .attempt_message_login_timeout },
        .{ .code = "login-io", .key = .attempt_message_login_io },
        .{ .code = "keychain-access-repair-required", .key = .attempt_message_keychain_repair },
    };
    for (mappings) |mapping| {
        if (std.mem.eql(u8, code, mapping.code)) return localized.text(mapping.key);
    }
    return localized.text(.attempt_message_refresh_failed);
}

pub fn authStateText(state: AuthState) []const u8 {
    return authStateTextWith(default_copy, state);
}

fn authStateTextWith(localized: strings.Catalog, state: AuthState) []const u8 {
    return switch (state) {
        .connected => localized.text(.auth_connected),
        .reauth_required => localized.text(.auth_reauthentication_required),
        .unavailable => localized.text(.auth_unavailable),
    };
}

pub fn snapshotStatusText(status: ?domain.SnapshotStatus) []const u8 {
    return snapshotStatusTextWith(default_copy, status);
}

fn snapshotStatusTextWith(localized: strings.Catalog, status: ?domain.SnapshotStatus) []const u8 {
    const value = status orelse return localized.text(.snapshot_none);
    return switch (value) {
        .fresh => localized.text(.snapshot_fresh),
        .stale => localized.text(.snapshot_stale),
        .partial => localized.text(.snapshot_partial),
        .reauth_required => localized.text(.snapshot_reauthentication_required),
        .error_state => localized.text(.snapshot_error_state),
        .unavailable => localized.text(.snapshot_unavailable),
        .deferred => localized.text(.snapshot_deferred),
    };
}

fn noWindowWording(row: AccountView) []const u8 {
    return noWindowWordingWith(default_copy, row);
}

fn noWindowWordingWith(localized: strings.Catalog, row: AccountView) []const u8 {
    if (!row.has_snapshot) return localized.text(.no_saved_snapshot_yet);
    return localized.text(.no_usage_window_reported);
}

fn serviceText(capabilities: ServiceCapabilities) []const u8 {
    return serviceTextWith(default_copy, capabilities);
}

fn serviceTextWith(localized: strings.Catalog, capabilities: ServiceCapabilities) []const u8 {
    if (!capabilities.connected) {
        return localized.text(.service_not_connected);
    }
    if (!capabilities.refresh and !capabilities.accounts and !capabilities.reset) {
        return localized.text(.service_local_only);
    }
    if (!capabilities.refresh) return localized.text(.service_refresh_not_attached);
    if (!capabilities.accounts) return localized.text(.service_accounts_not_attached);
    if (!capabilities.reset) return localized.text(.service_reset_not_attached);
    return localized.text(.service_all_attached);
}

pub fn outcomeIsHonestFailure(outcome: CommandOutcome) bool {
    return switch (outcome) {
        .none, .accepted_pending => false,
        else => true,
    };
}

const LocalInstant = struct {
    year: u32,
    month_index: usize,
    day: u32,
    hour: u32,
    minute: u32,
    gmtoff_s: i64,
    zone: []const u8,
};

fn localInstant(unix_s: i64, time_zone: TimeZone) ?LocalInstant {
    var local: c.struct_tm = undefined;
    var gmtoff_s: i64 = 0;
    const zone = switch (time_zone) {
        .system => blk: {
            var timestamp = std.math.cast(c.time_t, unix_s) orelse return null;
            if (c.localtime_r(&timestamp, &local) == null or local.tm_zone == null) return null;
            gmtoff_s = local.tm_gmtoff;
            break :blk std.mem.span(local.tm_zone);
        },
        .fixed => |fixed| blk: {
            const shifted = std.math.add(i64, unix_s, fixed.offset_seconds) catch return null;
            var timestamp = std.math.cast(c.time_t, shifted) orelse return null;
            if (c.gmtime_r(&timestamp, &local) == null) return null;
            gmtoff_s = fixed.offset_seconds;
            break :blk fixed.abbreviation;
        },
    };
    if (local.tm_year < -1900 or
        local.tm_mon < 0 or local.tm_mon >= strings.month_count or
        local.tm_mday < 1 or local.tm_mday > 31 or
        local.tm_hour < 0 or local.tm_hour > 23 or
        local.tm_min < 0 or local.tm_min > 59)
    {
        return null;
    }
    return .{
        .year = @intCast(local.tm_year + 1900),
        .month_index = @intCast(local.tm_mon),
        .day = @intCast(local.tm_mday),
        .hour = @intCast(local.tm_hour),
        .minute = @intCast(local.tm_min),
        .gmtoff_s = gmtoff_s,
        .zone = zone,
    };
}

fn localDayIndex(unix_s: i64, gmtoff_s: i64) ?i64 {
    const shifted = std.math.add(i64, unix_s, gmtoff_s) catch return null;
    return @divFloor(shifted, std.time.s_per_day);
}

pub fn formatLocal(buffer: []u8, unix_s: i64, time_zone: TimeZone) []const u8 {
    return formatLocalWith(default_copy, buffer, unix_s, time_zone);
}

fn formatLocalWith(localized: strings.Catalog, buffer: []u8, unix_s: i64, time_zone: TimeZone) []const u8 {
    const local = localInstant(unix_s, time_zone) orelse return localized.text(.unrepresentable_local_time);
    var writer = std.Io.Writer.fixed(buffer);
    localized.write(&writer, .absolute_datetime, .{
        local.year,
        localized.monthName(local.month_index),
        local.day,
        local.hour,
        local.minute,
        local.zone,
    });
    return writer.buffered();
}

pub fn formatCountdown(buffer: []u8, remaining_s: i64) []const u8 {
    return formatCountdownWith(default_copy, buffer, remaining_s);
}

fn formatCountdownWith(localized: strings.Catalog, buffer: []u8, remaining_s: i64) []const u8 {
    if (remaining_s <= 0) return localized.text(.countdown_passed_refresh);
    var writer = std.Io.Writer.fixed(buffer);
    const days = @divTrunc(remaining_s, std.time.s_per_day);
    const hours = @divTrunc(remaining_s - days * std.time.s_per_day, 3600);
    const minutes = @divTrunc(remaining_s - days * std.time.s_per_day - hours * 3600, 60);
    if (days > 0) {
        localized.write(&writer, .countdown_days, .{ days, hours });
    } else if (hours > 0) {
        localized.write(&writer, .countdown_hours, .{ hours, minutes });
    } else if (minutes > 0) {
        localized.write(&writer, .countdown_minutes, .{minutes});
    } else {
        localized.write(&writer, .countdown_seconds, .{remaining_s});
    }
    return writer.buffered();
}

pub fn agoPhrase(buffer: []u8, now_unix_s: i64, at_unix_s: i64) []const u8 {
    return agoPhraseWith(default_copy, buffer, now_unix_s, at_unix_s);
}

fn agoPhraseWith(localized: strings.Catalog, buffer: []u8, now_unix_s: i64, at_unix_s: i64) []const u8 {
    const elapsed = now_unix_s - at_unix_s;
    if (elapsed < 60) return localized.text(.just_now);
    var writer = std.Io.Writer.fixed(buffer);
    if (elapsed < 3600) {
        localized.write(&writer, .ago_minutes, .{@divTrunc(elapsed, 60)});
    } else if (elapsed < std.time.s_per_day) {
        localized.write(&writer, .ago_hours, .{@divTrunc(elapsed, 3600)});
    } else {
        localized.write(&writer, .ago_days, .{@divTrunc(elapsed, std.time.s_per_day)});
    }
    return writer.buffered();
}

pub fn shortLocal(buffer: []u8, now_unix_s: i64, at_unix_s: i64, time_zone: TimeZone) []const u8 {
    return shortLocalWith(default_copy, buffer, now_unix_s, at_unix_s, time_zone);
}

fn shortLocalWith(localized: strings.Catalog, buffer: []u8, now_unix_s: i64, at_unix_s: i64, time_zone: TimeZone) []const u8 {
    const local = localInstant(at_unix_s, time_zone) orelse return localized.text(.unrepresentable_local_time);
    const now_local = localInstant(now_unix_s, time_zone) orelse return localized.text(.unrepresentable_local_time);
    const day_index = localDayIndex(at_unix_s, local.gmtoff_s) orelse return localized.text(.unrepresentable_local_time);
    const now_day_index = localDayIndex(now_unix_s, now_local.gmtoff_s) orelse return localized.text(.unrepresentable_local_time);
    var writer = std.Io.Writer.fixed(buffer);
    if (day_index != now_day_index) {
        localized.write(&writer, .short_date, .{
            localized.monthName(local.month_index),
            local.day,
        });
    }
    localized.write(&writer, .clock_time, .{ local.hour, local.minute });
    return writer.buffered();
}

pub fn mediumLocal(buffer: []u8, unix_s: i64, time_zone: TimeZone) []const u8 {
    return mediumLocalWith(default_copy, buffer, unix_s, time_zone);
}

fn mediumLocalWith(localized: strings.Catalog, buffer: []u8, unix_s: i64, time_zone: TimeZone) []const u8 {
    const local = localInstant(unix_s, time_zone) orelse return localized.text(.unrepresentable_local_time);
    var writer = std.Io.Writer.fixed(buffer);
    localized.write(&writer, .medium_datetime, .{
        localized.monthName(local.month_index),
        local.day,
        local.hour,
        local.minute,
        local.zone,
    });
    return writer.buffered();
}

pub fn countdownPhrase(buffer: []u8, reset_at_unix_s: ?i64, now_unix_s: i64) []const u8 {
    return countdownPhraseWith(default_copy, buffer, reset_at_unix_s, now_unix_s);
}

fn countdownPhraseWith(localized: strings.Catalog, buffer: []u8, reset_at_unix_s: ?i64, now_unix_s: i64) []const u8 {
    const reset_at = reset_at_unix_s orelse return localized.text(.reset_time_not_reported);
    return formatCountdownWith(localized, buffer, reset_at - now_unix_s);
}

pub fn durationPhrase(buffer: []u8, minutes: u32) []const u8 {
    return durationPhraseWith(default_copy, buffer, minutes);
}

fn durationPhraseWith(localized: strings.Catalog, buffer: []u8, minutes: u32) []const u8 {
    var writer = std.Io.Writer.fixed(buffer);
    if (minutes % (60 * 24) == 0 and minutes >= 60 * 24) {
        localized.write(&writer, .duration_days, .{minutes / (60 * 24)});
    } else if (minutes % 60 == 0 and minutes >= 60) {
        localized.write(&writer, .duration_hours, .{minutes / 60});
    } else {
        localized.write(&writer, .duration_minutes, .{minutes});
    }
    return writer.buffered();
}

pub fn trayTitle(_: anytype, _: []u8) []const u8 {
    return "";
}

pub fn buildTray(view: anytype, out: []TrayItem) usize {
    const copy = strings.catalog(view.resolved_language);
    var count: usize = 0;
    var next_id: u32 = 1;
    var can_refresh = false;
    for (view.rows[0..view.row_count]) |row| {
        if (row.enabled) {
            can_refresh = true;
            break;
        }
    }

    const capacity = @min(out.len, max_tray_items);
    if (capacity == 0) return 0;

    const push = struct {
        fn call(items: []TrayItem, at: *usize, id: *u32, item: TrayItem) void {
            if (at.* >= items.len) return;
            var stored = item;
            if (!stored.separator) {
                stored.id = id.*;
                id.* += 1;
            }
            items[at.*] = stored;
            at.* += 1;
        }
    }.call;

    const footer_items: usize = 3;
    if (capacity <= footer_items) {
        push(out[0..capacity], &count, &next_id, .{ .separator = true });
        push(out[0..capacity], &count, &next_id, .{ .label = copy.text(.tray_settings), .command = tray_command_open_details });
        push(out[0..capacity], &count, &next_id, .{ .label = copy.text(.tray_quit), .command = tray_command_quit });
        return count;
    }
    const body_limit = capacity - footer_items;
    const body = out[0..body_limit];

    push(body, &count, &next_id, .{ .label = copy.text(.tray_refresh_all_accounts), .command = tray_command_refresh_all, .enabled = can_refresh });
    if (view.pool_tray_text.len != 0) {
        push(body, &count, &next_id, .{ .label = view.pool_tray_text, .enabled = false });
    }
    if (view.capabilities.proxy_control) {
        push(body, &count, &next_id, .{ .label = view.proxy_tray_text, .enabled = false });
    }
    push(body, &count, &next_id, .{ .separator = true });

    if (view.row_count == 0) {
        push(body, &count, &next_id, .{
            .label = copy.text(.tray_no_saved_accounts),
            .enabled = false,
        });
    } else {
        var shown: usize = 0;
        var provider_sections: usize = 0;

        const order = [_]domain.Provider{.codex};
        outer: for (order) |provider| {
            var section_written = false;
            for (view.rows[0..view.row_count]) |row| {
                if (row.provider != provider) continue;

                const remaining = view.row_count - shown;
                const free = body.len - count;
                const needs_section: usize = if (section_written)
                    0
                else
                    1 + @as(usize, @intFromBool(provider_sections != 0));
                const reserve_summary: usize = if (remaining > 1) 1 else 0;
                if (free < needs_section + 1 + reserve_summary) break :outer;
                if (!section_written) {
                    section_written = true;
                    if (provider_sections != 0) {
                        push(body, &count, &next_id, .{ .separator = true });
                    }
                    push(body, &count, &next_id, .{
                        .label = view.tray_provider_headers[@intFromEnum(provider)],
                        .enabled = false,
                    });
                    provider_sections += 1;
                }
                push(body, &count, &next_id, .{
                    .label = row.tray_account_text,
                    .command = row.tray_open_command,
                    .enabled = true,
                });
                shown += 1;
            }
        }
        if (shown < view.row_count) {
            push(body, &count, &next_id, .{
                .label = truncationLabel(copy, view.row_count - shown),
                .command = tray_command_open_details,
                .enabled = true,
            });
        }
    }

    push(out[0..capacity], &count, &next_id, .{ .separator = true });
    push(out[0..capacity], &count, &next_id, .{ .label = copy.text(.tray_settings), .command = tray_command_open_details });
    push(out[0..capacity], &count, &next_id, .{ .label = copy.text(.tray_quit), .command = tray_command_quit });
    return count;
}

fn truncationLabel(copy: strings.Catalog, remaining: usize) []const u8 {
    const keys = [_]strings.StaticKey{
        .tray_more_accounts,
        .tray_one_more_account,
        .tray_two_more_accounts,
        .tray_three_more_accounts,
        .tray_four_more_accounts,
        .tray_five_more_accounts,
        .tray_six_more_accounts,
        .tray_seven_more_accounts,
        .tray_eight_more_accounts,
        .tray_nine_more_accounts,
        .tray_ten_more_accounts,
        .tray_eleven_more_accounts,
        .tray_twelve_more_accounts,
        .tray_thirteen_more_accounts,
        .tray_fourteen_more_accounts,
        .tray_fifteen_more_accounts,
        .tray_sixteen_more_accounts,
    };
    if (remaining >= keys.len) return copy.text(.tray_more_accounts);
    return switch (remaining) {
        inline 0...16 => |index| copy.text(keys[index]),
        else => unreachable,
    };
}

const projection_attemptMessage = attemptMessage;
const projection_attemptReason = attemptReason;
const projection_authStateText = authStateText;
const projection_countdownPhrase = countdownPhrase;
const projection_durationPhrase = durationPhrase;
const projection_formatLocal = formatLocal;
const projection_agoPhrase = agoPhrase;
const projection_shortLocal = shortLocal;
const projection_mediumLocal = mediumLocal;
const projection_freshnessText = freshnessText;
const projection_freshnessPhrase = freshnessPhrase;
const projection_humanizeWindowLabel = humanizeWindowLabel;
const projection_noWindowWording = noWindowWording;
const projection_providerName = providerName;
const projection_selectPrimaryWindow = selectPrimaryWindow;
const projection_selectCodexPrimaryWindow = selectCodexPrimaryWindow;
const projection_selectConfiguredCodexPrimaryWindow = selectConfiguredCodexPrimaryWindow;
const projection_resetPhrase = resetPhrase;
const projection_remainingPhrase = remainingPhrase;
const projection_serviceText = serviceText;
const projection_snapshotStatusText = snapshotStatusText;

pub const ProjectionFormat = struct {
    pub const attemptMessage = projection_attemptMessage;
    pub const attemptReason = projection_attemptReason;
    pub const authStateText = projection_authStateText;
    pub const countdownPhrase = projection_countdownPhrase;
    pub const durationPhrase = projection_durationPhrase;
    pub const formatLocal = projection_formatLocal;
    pub const agoPhrase = projection_agoPhrase;
    pub const shortLocal = projection_shortLocal;
    pub const mediumLocal = projection_mediumLocal;
    pub const freshnessText = projection_freshnessText;
    pub const freshnessPhrase = projection_freshnessPhrase;
    pub const humanizeWindowLabel = projection_humanizeWindowLabel;
    pub const noWindowWording = projection_noWindowWording;
    pub const providerName = projection_providerName;
    pub const selectPrimaryWindow = projection_selectPrimaryWindow;
    pub const selectCodexPrimaryWindow = projection_selectCodexPrimaryWindow;
    pub const selectConfiguredCodexPrimaryWindow = projection_selectConfiguredCodexPrimaryWindow;
    pub const resetPhrase = projection_resetPhrase;
    pub const remainingPhrase = projection_remainingPhrase;
    pub const serviceText = projection_serviceText;
    pub const snapshotStatusText = projection_snapshotStatusText;
};

test "the same instant formats in supplied KST and UTC time zones" {
    const testing = std.testing;
    const unix_s: i64 = 1_784_948_400;

    var utc_buffer: [max_line_bytes]u8 = undefined;
    try testing.expectEqualStrings("2026-Jul-25 03:00 UTC", formatLocal(&utc_buffer, unix_s, .utc));

    var kst_buffer: [max_line_bytes]u8 = undefined;
    try testing.expectEqualStrings("2026-Jul-25 12:00 KST", formatLocal(&kst_buffer, unix_s, .kst));
}
