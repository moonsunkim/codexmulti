const std = @import("std");
const shell = @import("../shell_model.zig");
const domain = shell.domain;
const ui_model = shell.ui_model;

const testing = std.testing;
pub const now: i64 = 1_784_948_400;

pub const RecordingService = struct {
    capabilities: ui_model.ServiceCapabilities = .{ .connected = true },
    outcome: ui_model.CommandOutcome = .accepted_pending,
    projections: usize = 0,
    submissions: usize = 0,
    labeled_adds: usize = 0,
    last: ?ui_model.Command = null,
    last_labeled_provider: ?domain.Provider = null,
    accounts: []const Account = &.{},
    proxy_fact: ?ui_model.ProxyFact = null,
    complete_proxy_on_pump: bool = false,
    pumps: usize = 0,
    tags: [64]std.meta.Tag(ui_model.Command) = @splat(.refresh_all),
    kept: [4][1024]u8 = @splat(@splat(0)),
    kept_len: [4]usize = @splat(0),

    pub const Account = struct {
        fact: ui_model.AccountFact,
        windows: []const domain.UsageWindow = &.{},
    };

    pub fn port(self: *RecordingService) ui_model.ServicePort {
        return .{
            .context = self,
            .capabilities_fn = readCapabilities,
            .project_fn = project,
            .submit_fn = submit,
            .add_account_labeled_fn = addAccountLabeled,
            .pump_fn = pump,
        };
    }

    fn readCapabilities(context: *anyopaque) ui_model.ServiceCapabilities {
        const self: *RecordingService = @ptrCast(@alignCast(context));
        return self.capabilities;
    }

    fn project(context: *anyopaque, view: *ui_model.ViewState) void {
        const self: *RecordingService = @ptrCast(@alignCast(context));
        self.projections += 1;
        for (self.accounts) |entry| {
            const slot = view.pushAccount(entry.fact) catch return;
            for (entry.windows) |window| view.pushWindow(slot, window) catch break;
        }
        if (self.proxy_fact) |fact| view.applyProxy(fact);
    }

    fn submit(context: *anyopaque, command: ui_model.Command) ui_model.CommandOutcome {
        const self: *RecordingService = @ptrCast(@alignCast(context));
        self.tags[self.submissions] = std.meta.activeTag(command);
        self.submissions += 1;
        self.last = switch (command) {
            .set_appearance, .set_codex_usage_window, .refresh_all, .add_account, .proxy_refresh_status, .proxy_sync_config, .install_proxy_service, .repair_proxy_service, .stop_proxy_service, .disable_codex_routing => command,
            .set_codex_show_model_limits => |v| .{ .set_codex_show_model_limits = v },
            .set_launch_at_login => |v| .{ .set_launch_at_login = v },
            .report_launch_at_login_registration_failure => |v| .{ .report_launch_at_login_registration_failure = v },
            .set_auto_refresh => |v| .{ .set_auto_refresh = v },
            .set_proxy_enabled => |v| .{ .set_proxy_enabled = v },
            .enable_codex_routing => |v| .{ .enable_codex_routing = v },
            .refresh_account => |v| .{ .refresh_account = self.keep(0, v) },
            .reauthenticate => |v| .{ .reauthenticate = self.keep(0, v) },
            .remove_account => |v| .{ .remove_account = self.keep(0, v) },
            .retry_reset => |v| .{ .retry_reset = self.keep(0, v) },
            .proxy_switch_account => |v| .{ .proxy_switch_account = self.keep(0, v) },
            .proxy_pause_account => |v| .{ .proxy_pause_account = self.keep(0, v) },
            .proxy_reload_account => |v| .{ .proxy_reload_account = self.keep(0, v) },
            .proxy_clear_cooldown => |v| .{ .proxy_clear_cooldown = self.keep(0, v) },
            .relabel => |v| .{ .relabel = .{ .account_id = self.keep(0, v.account_id), .label = self.keep(1, v.label) } },
            .move_account => |v| .{ .move_account = .{
                .account_id = self.keep(0, v.account_id),
                .target_account_id = self.keep(1, v.target_account_id),
            } },
            .redeem_reset => |v| .{ .redeem_reset = .{
                .account_id = self.keep(0, v.account_id),
                .expected_available_count = v.expected_available_count,
                .confirmed_at_unix_s = v.confirmed_at_unix_s,
                .surface = v.surface,
            } },
            .save_proxy_settings => |v| .{ .save_proxy_settings = .{
                .base_url = self.keep(0, v.base_url),
                .cli_path = self.keep(1, v.cli_path),
                .config_path = self.keep(2, v.config_path),
                .node_path = self.keep(3, v.node_path),
            } },
        };
        return self.outcome;
    }

    fn addAccountLabeled(context: *anyopaque, provider: domain.Provider, label: []const u8) ui_model.CommandOutcome {
        const self: *RecordingService = @ptrCast(@alignCast(context));
        self.labeled_adds += 1;
        self.last_labeled_provider = provider;
        _ = self.keep(0, label);
        return self.outcome;
    }

    pub fn lastLabeledLabel(self: *const RecordingService) []const u8 {
        return self.kept[0][0..self.kept_len[0]];
    }

    fn pump(context: *anyopaque, _: i64) void {
        const self: *RecordingService = @ptrCast(@alignCast(context));
        self.pumps += 1;
        if (!self.complete_proxy_on_pump) return;
        if (self.proxy_fact) |*fact| fact.work = .idle;
        self.complete_proxy_on_pump = false;
    }

    fn keep(self: *RecordingService, slot: usize, value: []const u8) []const u8 {
        const take = @min(value.len, self.kept[slot].len);
        @memcpy(self.kept[slot][0..take], value[0..take]);
        self.kept_len[slot] = take;
        return self.kept[slot][0..take];
    }
};

pub fn weeklyWindow(used: u8, reset_at: ?i64) domain.UsageWindow {
    return .{ .kind = .weekly, .label = "Weekly", .used_percent = used, .reset_at_unix_s = reset_at, .duration_minutes = 7 * 24 * 60 };
}

pub fn sessionWindow(used: u8, reset_at: ?i64) domain.UsageWindow {
    return .{ .kind = .session, .label = "5-hour", .used_percent = used, .reset_at_unix_s = reset_at, .duration_minutes = 300 };
}

pub fn claudeFact() ui_model.AccountFact {
    return .{
        .account_id = "acct-claude-work",
        .label = "Claude Work",
        .provider = .claude,
        .auth_state = .connected,
        .freshness = .saved_snapshot,
        .snapshot_status = .fresh,
        .has_snapshot = true,
        .snapshot_captured_at_unix_s = now - 3600,
        .last_attempt_at_unix_s = now - 3600,
        .last_success_at_unix_s = now - 3600,
    };
}

pub fn codexFact() ui_model.AccountFact {
    return .{
        .account_id = "acct-codex-personal",
        .label = "Codex Personal",
        .provider = .codex,
        .auth_state = .connected,
        .freshness = .saved_snapshot,
        .snapshot_status = .fresh,
        .has_snapshot = true,
        .snapshot_captured_at_unix_s = now - 600,
        .last_attempt_at_unix_s = now - 600,
        .last_success_at_unix_s = now - 600,
        .reset_credit_count = 2,
        .credit_detail_status = .count_only,
    };
}

pub fn newModel() !*shell.Model {
    const model = try testing.allocator.create(shell.Model);
    model.* = shell.initialModel(.kst);
    model.now_unix_s = now;
    return model;
}
