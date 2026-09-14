const std = @import("std");
const bridge = @import("bridge_json");
const shell = bridge.shell;
const domain = shell.domain;
const ui_model = bridge.ui_model;

const testing = std.testing;
const now: i64 = 1_784_948_400;
const fixture_dir = "fixtures/bridge";

const projection_names = [_][]const u8{
    "viewstate-unattached",
    "viewstate-empty-attached",
    "viewstate-two-accounts-fresh",
    "viewstate-attention-states",
    "viewstate-proxy-reachable-mapped",
    "viewstate-proxy-unreachable",
    "viewstate-proxy-config-mismatch",
    "viewstate-expanded-codex",
    "viewstate-expanded-claude",
    "viewstate-tray-truncated",
    "viewstate-reset-review",
    "viewstate-reset-armed",
    "viewstate-reset-blocked-pending",
    "viewstate-reset-dispatched-settled-cleared",
    "viewstate-reset-dispatched-settled-unsent",
    "viewstate-remove-mapped-pause-requested",
    "viewstate-rename-open",
    "viewstate-add-account-empty",
    "viewstate-add-account-valid",
    "viewstate-add-account-in-flight",
    "viewstate-failover-switch-open",
    "viewstate-clear-cooldown-open",
    "viewstate-notice-blocked",
    "viewstate-notice-pending",
    "viewstate-runtime-error-keychain",
    "viewstate-proxy-checking",
    "viewstate-proxy-settings-open",
    "viewstate-remove-plain-open",
    "viewstate-remove-mapped-open",
    "viewstate-remove-mapped-can-finish",
    "viewstate-reset-blocked-no-credit",
    "viewstate-reset-dispatched-pending",
    "viewstate-reset-settled-clear-failed",
    "viewstate-proxy-service-not-installed",
    "viewstate-proxy-service-installed-stale",
    "viewstate-proxy-service-starting",
    "viewstate-proxy-service-running",
    "viewstate-proxy-service-unreachable",
    "viewstate-unified-proxy-order",
    "viewstate-unified-registry-order",
    "viewstate-c6-ready-token",
    "viewstate-c6-cooling-explained",
    "viewstate-c7-plus-session-binding",
    "viewstate-c7-plus-weekly-binding",
    "viewstate-c7-pro-weekly-only",
    "viewstate-c7-unknown-plan-binding",
    "viewstate-c8-zero-credit",
    "viewstate-settings-appearance-system",
    "viewstate-settings-appearance-light",
    "viewstate-settings-appearance-dark",
    "viewstate-c9-refresh-mismatch-pending",
    "viewstate-c9-refresh-mismatch-fixed",
    "viewstate-c9-proxy-switch-refused",
    "viewstate-c9-settings-launch-auto",
};

const FixtureService = struct {
    capabilities: ui_model.ServiceCapabilities = .{
        .connected = true,
        .refresh = true,
        .accounts = true,
        .reset = true,
        .proxy_control = true,
    },
    outcome: ui_model.CommandOutcome = .accepted_pending,
    accounts: [ui_model.max_rows]Account = undefined,
    account_count: usize = 0,
    proxy_present: bool = false,
    proxy_reachability: ui_model.ProxyReachability = .unknown,
    proxy_work: ui_model.ProxyWork = .idle,
    proxy_sync_state: ui_model.ProxySyncState = .unknown,
    proxy_config_matches: bool = false,
    proxy_success_revision: u64 = 0,
    proxy_in_flight: u32 = 0,
    start_proxy_check_on_submit: bool = false,
    proxy_accounts: [ui_model.max_rows]ui_model.ProxyAccountFact = undefined,
    proxy_account_count: usize = 0,
    proxy_service_present: bool = false,
    proxy_service_state: ui_model.ProxyServiceState = .not_installed,
    codex_routing_state: ui_model.CodexRoutingState = .off,
    proxy_enabled_detail_text: ?[]const u8 = null,
    appearance: ui_model.Appearance = .system,
    language: ui_model.Language = .en,
    codex_usage_window: ui_model.CodexUsageWindow = .auto,
    codex_show_model_limits: bool = false,
    launch_at_login: bool = false,
    launch_at_login_registration_failed: bool = false,
    auto_refresh_minutes: u16 = 0,

    const Account = struct {
        fact: ui_model.AccountFact,
        windows: []const domain.UsageWindow = &.{},
    };

    fn port(self: *FixtureService) ui_model.ServicePort {
        return .{
            .context = self,
            .capabilities_fn = readCapabilities,
            .project_fn = project,
            .submit_fn = submit,
            .add_account_labeled_fn = addAccountLabeled,
        };
    }

    fn readCapabilities(context: *anyopaque) ui_model.ServiceCapabilities {
        const self: *FixtureService = @ptrCast(@alignCast(context));
        return self.capabilities;
    }

    fn project(context: *anyopaque, view: *ui_model.ViewState) void {
        const self: *FixtureService = @ptrCast(@alignCast(context));
        view.applyAppearance(self.appearance);
        view.applyLanguage(self.language, if (self.language == .system) .en else self.language);
        view.applyCodexSettings(self.codex_usage_window, self.codex_show_model_limits);
        view.applyLaunchAtLogin(self.launch_at_login, self.launch_at_login_registration_failed);
        var auto_accounts: u16 = 0;
        for (self.accounts[0..self.account_count]) |entry| {
            if (entry.fact.provider == .codex and entry.fact.enabled and entry.fact.auth_state == .connected) auto_accounts += 1;
        }
        view.applyAutoRefresh(self.auto_refresh_minutes, auto_accounts);
        for (self.accounts[0..self.account_count]) |entry| {
            const slot = view.pushAccount(entry.fact) catch return;
            for (entry.windows) |window| view.pushWindow(slot, window) catch break;
        }
        if (self.proxy_present) view.applyProxy(.{
            .base_url = "http://127.0.0.1:8787",
            .cli_path = "/opt/codexmulti-proxy/bin/codexmulti-proxy",
            .config_path = "/tmp/fixture-proxy.json",
            .node_path = "",
            .node_resolved = "/usr/bin/node",
            .reachability = self.proxy_reachability,
            .work = self.proxy_work,
            .sync_state = self.proxy_sync_state,
            .last_attempt_at_unix_s = now - 45,
            .last_attempt_result = if (self.proxy_reachability == .@"unreachable") .@"unreachable" else .ok,
            .last_success_at_unix_s = if (self.proxy_reachability == .reachable) now - 60 else null,
            .success_revision = self.proxy_success_revision,
            .config_path_matches = self.proxy_config_matches,
            .in_flight = self.proxy_in_flight,
            .accounts = self.proxy_accounts[0..self.proxy_account_count],
        });
        if (self.proxy_service_present) view.applyProxyService(.{
            .state = self.proxy_service_state,
            .detail_text = switch (self.proxy_service_state) {
                .not_installed => "Proxy service is not installed",
                .installed_stale => "Bundled proxy files or receipt changed; repair is required.",
                .starting => "Waiting for 2 proxy request(s) to finish",
                .running => "Bundled proxy service is running.",
                .@"unreachable" => "Proxy service is installed but unreachable.",
            },
            .can_install = self.proxy_service_state == .not_installed,
            .can_repair = self.proxy_service_state == .installed_stale or self.proxy_service_state == .@"unreachable",
            .can_stop = self.proxy_service_state == .running and self.codex_routing_state != .conflicting,
            .routing_state = self.codex_routing_state,
            .enabled = self.codex_routing_state == .on,
            .enabled_detail_text = self.proxy_enabled_detail_text orelse if (self.proxy_service_state == .running and self.codex_routing_state == .on)
                "Failover is on. New accounts are included automatically."
            else if (self.codex_routing_state == .on)
                "Reconnecting Failover automatically. You can turn it off to connect directly."
            else
                "Failover is off. Codex connects directly.",
            .cli_default_path = "/Applications/CodexMulti.app/Contents/Resources/proxy/bin/codexmulti-proxy",
            .node_default_path = "/Applications/CodexMulti.app/Contents/Helpers/node",
        });
    }

    fn submit(context: *anyopaque, command: ui_model.Command) ui_model.CommandOutcome {
        const self: *FixtureService = @ptrCast(@alignCast(context));
        switch (command) {
            .set_appearance => |appearance| self.appearance = appearance,
            .set_language => |request| self.language = request.value,
            .set_codex_usage_window => |window| self.codex_usage_window = window,
            .set_codex_show_model_limits => |on| self.codex_show_model_limits = on,
            else => {},
        }
        if (self.start_proxy_check_on_submit) switch (command) {
            .proxy_refresh_status => {
                self.proxy_present = true;
                self.proxy_work = .checking;
            },
            else => {},
        };
        return self.outcome;
    }

    fn addAccountLabeled(context: *anyopaque, provider: domain.Provider, label: []const u8) ui_model.CommandOutcome {
        const self: *FixtureService = @ptrCast(@alignCast(context));
        if (provider != .codex or !self.outcome.accepted()) return self.outcome;
        var fact = codexFact("acct-codex-added", label);
        fact.operation_in_flight = true;
        self.add(fact, &.{});
        return self.outcome;
    }

    fn add(self: *FixtureService, fact: ui_model.AccountFact, windows: []const domain.UsageWindow) void {
        self.accounts[self.account_count] = .{ .fact = fact, .windows = windows };
        self.account_count += 1;
    }

    fn addProxy(self: *FixtureService, fact: ui_model.ProxyAccountFact) void {
        self.proxy_accounts[self.proxy_account_count] = fact;
        self.proxy_account_count += 1;
        self.proxy_present = true;
    }
};

const codex_windows = [_]domain.UsageWindow{
    .{ .kind = .session, .label = "5-hour", .used_percent = 42, .reset_at_unix_s = now + 2 * 3600, .duration_minutes = 300 },
    .{ .kind = .weekly, .label = "Weekly", .used_percent = 73, .reset_at_unix_s = now + 3 * 86400, .duration_minutes = 7 * 24 * 60 },
};
const c7_plus_session_binding_windows = [_]domain.UsageWindow{
    .{ .kind = .session, .label = "5-hour", .used_percent = 90, .reset_at_unix_s = now + 2 * 3600, .duration_minutes = 300 },
    .{ .kind = .weekly, .label = "Weekly", .used_percent = 20, .reset_at_unix_s = now + 5 * 86400, .duration_minutes = 7 * 24 * 60 },
};
const c7_plus_weekly_binding_windows = [_]domain.UsageWindow{
    .{ .kind = .session, .label = "5-hour", .used_percent = 10, .reset_at_unix_s = now + 2 * 3600, .duration_minutes = 300 },
    .{ .kind = .weekly, .label = "Weekly", .used_percent = 100, .reset_at_unix_s = now + 5 * 86400, .duration_minutes = 7 * 24 * 60 },
};
const c8_pro_panel_windows = [_]domain.UsageWindow{
    .{ .kind = .weekly, .label = "Weekly", .used_percent = 73, .reset_at_unix_s = now + 5 * 86400, .duration_minutes = 7 * 24 * 60 },
    .{ .kind = .model_scoped, .label = "GPT-5.3-Codex-Spark", .model_label = "GPT-5.3-Codex-Spark", .used_percent = 0, .reset_at_unix_s = now + 2 * 3600, .duration_minutes = 300 },
    .{ .kind = .model_scoped, .label = "gpt-reserve", .model_label = "gpt-reserve", .used_percent = 0, .reset_at_unix_s = now + 5 * 86400, .duration_minutes = 7 * 24 * 60 },
    .{ .kind = .weekly, .label = "Codex", .used_percent = 72, .reset_at_unix_s = now + 5 * 86400, .duration_minutes = 7 * 24 * 60 },
};
const c7_unknown_plan_windows = [_]domain.UsageWindow{
    .{ .kind = .weekly, .label = "Weekly", .used_percent = 55, .reset_at_unix_s = now + 6 * 86400 },
    .{ .kind = .other, .label = "Untyped weekly mirror", .used_percent = 55, .reset_at_unix_s = now + 6 * 86400 },
    .{ .kind = .other, .label = "Quarterly pool", .used_percent = 80, .reset_at_unix_s = now + 40 * 86400 },
};
const claude_windows = [_]domain.UsageWindow{
    .{ .kind = .session, .label = "5-hour", .used_percent = 31, .reset_at_unix_s = now + 3 * 3600, .duration_minutes = 300 },
    .{ .kind = .weekly, .label = "Weekly", .used_percent = 54, .reset_at_unix_s = now + 5 * 86400, .duration_minutes = 7 * 24 * 60 },
    .{ .kind = .model_scoped, .label = "Sonnet", .model_label = "Sonnet", .used_percent = 20, .reset_at_unix_s = now + 4 * 86400 },
};

fn codexFact(id: []const u8, label: []const u8) ui_model.AccountFact {
    return .{
        .account_id = id,
        .label = label,
        .provider_email = "owner@example.com",
        .plan_label = "Pro 20x",
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

fn claudeFact() ui_model.AccountFact {
    return .{
        .account_id = "acct-claude-work",
        .label = "Claude Work",
        .provider_email = "work@example.com",
        .plan_label = "Max 20x",
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

fn attach(model: *shell.Model, service: *FixtureService) void {
    model.* = shell.initialModel(.utc);
    model.now_unix_s = now;
    model.service = service.port();
    shell.reproject(model);
}

fn addTwo(service: *FixtureService) void {
    service.add(claudeFact(), &claude_windows);
    service.add(codexFact("acct-codex-personal", "Codex Personal"), &codex_windows);
}

fn enableProxyLifecycle(service: *FixtureService) void {
    service.proxy_service_present = true;
    service.proxy_service_state = .running;
    service.codex_routing_state = .on;
}

fn addMapped(service: *FixtureService) void {
    enableProxyLifecycle(service);
    service.proxy_present = true;
    service.proxy_reachability = .reachable;
    service.proxy_sync_state = .synced;
    service.proxy_config_matches = true;
    service.proxy_success_revision = 4;
    service.add(codexFact("acct-codex-active", "active@example.com"), &codex_windows);
    service.add(codexFact("acct-codex-ready", "ready@example.com"), &codex_windows);
    service.add(codexFact("acct-codex-cooling", "cooling@example.com"), &codex_windows);
    service.add(codexFact("acct-codex-paused", "paused@example.com"), &codex_windows);
    service.addProxy(.{ .app_id = "acct-codex-active", .storage_key = "codex-active", .proxy_name = "active", .label = "active@example.com", .state = .ready, .active = true, .mapped = true });
    service.addProxy(.{ .app_id = "acct-codex-ready", .storage_key = "codex-ready", .proxy_name = "ready", .label = "ready@example.com", .state = .ready, .mapped = true });
    service.addProxy(.{ .app_id = "acct-codex-cooling", .storage_key = "codex-cooling", .proxy_name = "cooling", .label = "cooling@example.com", .state = .cooldown, .cooldown_until_unix_s = now + 7200, .mapped = true });
    service.addProxy(.{ .app_id = "acct-codex-paused", .storage_key = "codex-paused", .proxy_name = "paused", .label = "paused@example.com", .state = .paused, .mapped = true });
    service.addProxy(.{ .proxy_name = "invalid", .label = "invalid@example.com", .state = .invalid });
}

fn makeProjection(allocator: std.mem.Allocator, name: []const u8) ![]u8 {
    return makeProjectionLanguage(allocator, name, .en);
}

fn makeProjectionLanguage(allocator: std.mem.Allocator, name: []const u8, language: ui_model.Language) ![]u8 {
    var service: FixtureService = .{};
    var model = shell.initialModel(.utc);
    var effects: shell.Effects = .{};
    var runtime: bridge.RuntimeProjection = .{ .started = true };

    if (std.mem.eql(u8, name, "viewstate-unattached")) {
        model.now_unix_s = now;
        shell.reproject(&model);
        model.view.applyLanguage(.en, .en);
        model.view.finish(.{});
        runtime = .{};
    } else if (std.mem.eql(u8, name, "viewstate-empty-attached")) {
        attach(&model, &service);
    } else if (std.mem.eql(u8, name, "viewstate-two-accounts-fresh")) {
        addTwo(&service);
        attach(&model, &service);
    } else if (std.mem.eql(u8, name, "viewstate-attention-states")) {
        var reauth = codexFact("acct-codex-reauth", "Reauth");
        reauth.auth_state = .reauth_required;
        reauth.freshness = .reauth_required;
        reauth.snapshot_status = .reauth_required;
        var failed = codexFact("acct-codex-failed", "Refresh failed");
        failed.freshness = .refresh_failed;
        failed.snapshot_status = .error_state;
        failed.last_attempt_code = "network";
        var unavailable = codexFact("acct-codex-unavailable", "Usage unavailable");
        unavailable.freshness = .usage_unavailable;
        unavailable.snapshot_status = .unavailable;
        var deferred = codexFact("acct-codex-deferred", "Refresh deferred");
        deferred.freshness = .refresh_deferred;
        deferred.snapshot_status = .deferred;
        var passed = codexFact("acct-codex-reset-passed", "Reset passed");
        passed.freshness = .reset_passed;
        service.add(reauth, &.{});
        service.add(failed, &codex_windows);
        service.add(unavailable, &.{});
        service.add(deferred, &codex_windows);
        service.add(passed, &codex_windows);
        attach(&model, &service);
    } else if (std.mem.eql(u8, name, "viewstate-proxy-reachable-mapped")) {
        addMapped(&service);
        attach(&model, &service);
    } else if (std.mem.eql(u8, name, "viewstate-proxy-unreachable")) {
        addTwo(&service);
        service.proxy_service_present = true;
        service.proxy_service_state = .@"unreachable";
        service.codex_routing_state = .on;
        service.proxy_present = true;
        service.proxy_reachability = .@"unreachable";
        service.proxy_sync_state = .failed;
        attach(&model, &service);
    } else if (std.mem.eql(u8, name, "viewstate-proxy-config-mismatch")) {
        addMapped(&service);
        service.proxy_config_matches = false;
        service.proxy_sync_state = .needed;
        attach(&model, &service);
    } else if (std.mem.eql(u8, name, "viewstate-proxy-checking")) {
        service.proxy_present = true;
        service.start_proxy_check_on_submit = true;
        attach(&model, &service);
        shell.update(&model, .refresh_proxy_status, &effects);
    } else if (std.mem.eql(u8, name, "viewstate-proxy-settings-open")) {
        service.proxy_present = true;
        attach(&model, &service);
        shell.update(&model, .toggle_proxy_settings, &effects);
    } else if (std.mem.eql(u8, name, "viewstate-expanded-codex")) {
        addTwo(&service);
        attach(&model, &service);
        shell.update(&model, .{ .toggle_account = 0 }, &effects);
    } else if (std.mem.eql(u8, name, "viewstate-expanded-claude")) {
        service.add(claudeFact(), &claude_windows);
        attach(&model, &service);
        shell.update(&model, .{ .toggle_account = 0 }, &effects);
    } else if (std.mem.eql(u8, name, "viewstate-tray-truncated")) {
        const ids = [_][]const u8{
            "acct-codex-01", "acct-codex-02", "acct-codex-03", "acct-codex-04",
            "acct-codex-05", "acct-codex-06", "acct-codex-07", "acct-codex-08",
            "acct-codex-09", "acct-codex-10", "acct-codex-11", "acct-codex-12",
            "acct-codex-13", "acct-codex-14", "acct-codex-15", "acct-codex-16",
        };
        const labels = [_][]const u8{
            "Account 01", "Account 02", "Account 03", "Account 04",
            "Account 05", "Account 06", "Account 07", "Account 08",
            "Account 09", "Account 10", "Account 11", "Account 12",
            "Account 13", "Account 14", "Account 15", "Account 16",
        };
        for (ids, labels) |id, label| service.add(codexFact(id, label), &codex_windows);
        attach(&model, &service);
    } else if (std.mem.startsWith(u8, name, "viewstate-reset-")) {
        var fact = codexFact("acct-codex-personal", "Codex Personal");
        if (std.mem.eql(u8, name, "viewstate-reset-blocked-pending")) fact.pending_reset_attempt = true;
        if (std.mem.eql(u8, name, "viewstate-reset-blocked-no-credit")) fact.reset_credit_count = 0;
        service.add(fact, &codex_windows);
        attach(&model, &service);
        shell.update(&model, .{ .begin_reset = 0 }, &effects);
        if (!std.mem.eql(u8, name, "viewstate-reset-review") and
            !std.mem.eql(u8, name, "viewstate-reset-blocked-pending") and
            !std.mem.eql(u8, name, "viewstate-reset-blocked-no-credit"))
        {
            shell.update(&model, .acknowledge_reset, &effects);
        }
        const dispatched = std.mem.startsWith(u8, name, "viewstate-reset-dispatched") or
            std.mem.eql(u8, name, "viewstate-reset-settled-clear-failed");
        if (dispatched) {
            shell.update(&model, .confirm_reset, &effects);
            if (!std.mem.eql(u8, name, "viewstate-reset-dispatched-pending")) {
                service.accounts[0].fact.operation_in_flight = true;
                shell.reproject(&model);
                service.accounts[0].fact.operation_in_flight = false;
                service.accounts[0].fact.pending_reset_attempt = false;
                if (std.mem.endsWith(u8, name, "settled-cleared")) {
                    service.accounts[0].fact.reset_credit_count = 1;
                    service.accounts[0].fact.reset_proxy_clear = .cleared;
                } else if (std.mem.eql(u8, name, "viewstate-reset-settled-clear-failed")) {
                    service.accounts[0].fact.reset_credit_count = 1;
                    service.accounts[0].fact.reset_proxy_clear = .failed;
                } else {
                    service.accounts[0].fact.unsent_reset_attempt = true;
                }
                shell.reproject(&model);
            }
        }
    } else if (std.mem.eql(u8, name, "viewstate-remove-plain-open")) {
        service.add(codexFact("acct-codex-plain", "Plain account"), &codex_windows);
        attach(&model, &service);
        shell.update(&model, .{ .begin_remove = 0 }, &effects);
    } else if (std.mem.eql(u8, name, "viewstate-remove-mapped-open")) {
        addMapped(&service);
        attach(&model, &service);
        shell.update(&model, .{ .begin_remove = 0 }, &effects);
    } else if (std.mem.eql(u8, name, "viewstate-remove-mapped-can-finish")) {
        addMapped(&service);
        attach(&model, &service);
        shell.update(&model, .{ .begin_remove = 0 }, &effects);
        shell.update(&model, .confirm_remove, &effects);
        service.proxy_success_revision += 1;
        service.proxy_accounts[0].state = .paused;
        service.proxy_accounts[0].active = false;
        service.proxy_accounts[0].in_flight = 0;
        shell.reproject(&model);
    } else if (std.mem.eql(u8, name, "viewstate-remove-mapped-pause-requested")) {
        addMapped(&service);
        attach(&model, &service);
        shell.update(&model, .{ .begin_remove = 0 }, &effects);
        shell.update(&model, .confirm_remove, &effects);
    } else if (std.mem.eql(u8, name, "viewstate-rename-open")) {
        addTwo(&service);
        attach(&model, &service);
        shell.update(&model, .{ .begin_rename = 0 }, &effects);
    } else if (std.mem.eql(u8, name, "viewstate-add-account-empty")) {
        attach(&model, &service);
        shell.update(&model, .begin_add_account, &effects);
    } else if (std.mem.eql(u8, name, "viewstate-add-account-valid")) {
        attach(&model, &service);
        shell.update(&model, .begin_add_account, &effects);
        shell.copyInto(&model.add_account.label_buffer, &model.add_account.label_len, "Owner Work");
    } else if (std.mem.eql(u8, name, "viewstate-add-account-in-flight")) {
        attach(&model, &service);
        shell.update(&model, .begin_add_account, &effects);
        shell.update(&model, .{ .commit_add_account = "  Owner Work  " }, &effects);
    } else if (std.mem.eql(u8, name, "viewstate-failover-switch-open")) {
        addMapped(&service);
        attach(&model, &service);
        shell.update(&model, .{ .begin_failover_switch = 1 }, &effects);
    } else if (std.mem.eql(u8, name, "viewstate-clear-cooldown-open")) {
        addMapped(&service);
        attach(&model, &service);
        shell.update(&model, .{ .begin_clear_cooldown = 2 }, &effects);
    } else if (std.mem.eql(u8, name, "viewstate-notice-blocked")) {
        addTwo(&service);
        service.outcome = .rejected_not_allowed;
        attach(&model, &service);
        shell.update(&model, .refresh_all, &effects);
    } else if (std.mem.eql(u8, name, "viewstate-notice-pending")) {
        var fact = codexFact("acct-codex-personal", "Codex Personal");
        fact.operation_in_flight = true;
        service.add(fact, &codex_windows);
        attach(&model, &service);
        shell.update(&model, .refresh_all, &effects);
    } else if (std.mem.eql(u8, name, "viewstate-runtime-error-keychain")) {
        model.now_unix_s = now;
        shell.reproject(&model);
        model.view.applyLanguage(.en, .en);
        model.view.finish(.{});
        runtime = .{ .@"error" = .keychain_unavailable };
    } else if (std.mem.startsWith(u8, name, "viewstate-proxy-service-")) {
        service.proxy_service_present = true;
        if (std.mem.endsWith(u8, name, "not-installed")) {
            service.proxy_service_state = .not_installed;
            service.codex_routing_state = .off;
        } else if (std.mem.endsWith(u8, name, "installed-stale")) {
            service.proxy_service_state = .installed_stale;
            service.codex_routing_state = .conflicting;
        } else if (std.mem.endsWith(u8, name, "starting")) {
            service.proxy_service_state = .starting;
            service.codex_routing_state = .on;
        } else if (std.mem.endsWith(u8, name, "running")) {
            service.proxy_service_state = .running;
            service.codex_routing_state = .off;
        } else if (std.mem.endsWith(u8, name, "unreachable")) {
            service.proxy_service_state = .@"unreachable";
            service.codex_routing_state = .on;
        } else return error.UnknownFixture;
        attach(&model, &service);
    } else if (std.mem.eql(u8, name, "viewstate-unified-proxy-order")) {
        enableProxyLifecycle(&service);
        service.proxy_present = true;
        service.proxy_reachability = .reachable;
        service.proxy_sync_state = .synced;
        service.proxy_config_matches = true;
        service.proxy_success_revision = 1;
        service.add(codexFact("acct-codex-alpha", "alpha@example.com"), &codex_windows);
        service.add(codexFact("acct-codex-unmapped", "unmapped@example.com"), &codex_windows);
        service.add(codexFact("acct-codex-gamma", "gamma@example.com"), &codex_windows);
        service.addProxy(.{ .app_id = "acct-codex-gamma", .storage_key = "codex-gamma", .proxy_name = "gamma", .label = "gamma@example.com", .state = .ready, .active = true, .mapped = true });
        service.addProxy(.{ .app_id = "acct-codex-alpha", .storage_key = "codex-alpha", .proxy_name = "alpha", .label = "alpha@example.com", .state = .cooldown, .cooldown_until_unix_s = now + 7200, .mapped = true });
        attach(&model, &service);
        shell.update(&model, .{ .toggle_account = 2 }, &effects);
    } else if (std.mem.eql(u8, name, "viewstate-unified-registry-order")) {
        service.proxy_present = true;
        service.add(codexFact("acct-codex-second", "second@example.com"), &codex_windows);
        service.add(codexFact("acct-codex-first", "first@example.com"), &codex_windows);
        service.addProxy(.{ .app_id = "acct-codex-first", .storage_key = "codex-first", .proxy_name = "first", .label = "first@example.com", .state = .ready, .active = true, .mapped = true });
        service.addProxy(.{ .app_id = "acct-codex-second", .storage_key = "codex-second", .proxy_name = "second", .label = "second@example.com", .state = .cooldown, .cooldown_until_unix_s = now + 7200, .mapped = true });
        attach(&model, &service);
    } else if (std.mem.eql(u8, name, "viewstate-c6-ready-token")) {
        enableProxyLifecycle(&service);
        service.proxy_present = true;
        service.proxy_reachability = .reachable;
        service.proxy_sync_state = .synced;
        service.proxy_config_matches = true;
        service.proxy_success_revision = 1;
        service.add(codexFact("acct-codex-ready", "ready@example.com"), &codex_windows);
        service.addProxy(.{ .app_id = "acct-codex-ready", .storage_key = "codex-ready", .proxy_name = "ready", .label = "ready@example.com", .state = .ready, .token_expires_at_unix_s = now + 5 * 86400, .active = true, .mapped = true });
        attach(&model, &service);
        shell.update(&model, .{ .toggle_account = 0 }, &effects);
    } else if (std.mem.eql(u8, name, "viewstate-c6-cooling-explained")) {
        enableProxyLifecycle(&service);
        service.proxy_present = true;
        service.proxy_reachability = .reachable;
        service.proxy_sync_state = .synced;
        service.proxy_config_matches = true;
        service.proxy_success_revision = 1;
        service.add(codexFact("acct-codex-cooling", "cooling@example.com"), &codex_windows);
        service.addProxy(.{ .app_id = "acct-codex-cooling", .storage_key = "codex-cooling", .proxy_name = "cooling", .label = "cooling@example.com", .state = .cooldown, .cooldown_until_unix_s = now + 7200, .mapped = true });
        attach(&model, &service);
        shell.update(&model, .{ .toggle_account = 0 }, &effects);
    } else if (std.mem.eql(u8, name, "viewstate-c7-plus-session-binding")) {
        var fact = codexFact("acct-codex-plus-session", "plus-session@example.com");
        fact.plan_label = "Plus";
        service.add(fact, &c7_plus_session_binding_windows);
        attach(&model, &service);
        shell.update(&model, .{ .toggle_account = 0 }, &effects);
    } else if (std.mem.eql(u8, name, "viewstate-c7-plus-weekly-binding")) {
        var fact = codexFact("acct-codex-plus-weekly", "plus-weekly@example.com");
        fact.plan_label = "Plus";
        service.add(fact, &c7_plus_weekly_binding_windows);
        attach(&model, &service);
        shell.update(&model, .{ .toggle_account = 0 }, &effects);
    } else if (std.mem.eql(u8, name, "viewstate-c7-pro-weekly-only")) {
        service.add(codexFact("acct-codex-pro", "pro@example.com"), &c8_pro_panel_windows);
        attach(&model, &service);
        shell.update(&model, .{ .toggle_account = 0 }, &effects);
    } else if (std.mem.eql(u8, name, "viewstate-c7-unknown-plan-binding")) {
        var fact = codexFact("acct-codex-future", "future@example.com");
        fact.plan_label = "Team";
        service.add(fact, &c7_unknown_plan_windows);
        attach(&model, &service);
        shell.update(&model, .{ .toggle_account = 0 }, &effects);
    } else if (std.mem.eql(u8, name, "viewstate-c8-zero-credit")) {
        var fact = codexFact("acct-codex-zero-credit", "zero-credit@example.com");
        fact.reset_credit_count = 0;
        service.add(fact, &codex_windows);
        attach(&model, &service);
        shell.update(&model, .{ .toggle_account = 0 }, &effects);
    } else if (std.mem.startsWith(u8, name, "viewstate-settings-appearance-")) {
        service.proxy_present = true;
        service.proxy_service_present = true;
        service.proxy_service_state = .running;
        service.codex_routing_state = .on;
        attach(&model, &service);
        if (std.mem.endsWith(u8, name, "light")) {
            shell.update(&model, .{ .set_appearance = .light }, &effects);
        } else if (std.mem.endsWith(u8, name, "dark")) {
            shell.update(&model, .{ .set_appearance = .dark }, &effects);
        } else if (!std.mem.endsWith(u8, name, "system")) return error.UnknownFixture;
    } else if (std.mem.eql(u8, name, "viewstate-c9-refresh-mismatch-pending")) {
        addMapped(&service);
        service.proxy_sync_state = .needed;
        service.proxy_success_revision = 5;
        attach(&model, &service);
    } else if (std.mem.eql(u8, name, "viewstate-c9-refresh-mismatch-fixed")) {
        addMapped(&service);
        service.proxy_sync_state = .synced;
        service.proxy_success_revision = 6;
        attach(&model, &service);
    } else if (std.mem.eql(u8, name, "viewstate-c9-proxy-switch-refused")) {
        service.proxy_service_present = true;
        service.proxy_service_state = .running;
        service.codex_routing_state = .on;
        service.proxy_enabled_detail_text = "4 proxy request(s) are in flight. The switch will apply when they finish.";
        service.proxy_present = true;
        service.proxy_reachability = .reachable;
        service.proxy_config_matches = true;
        service.proxy_in_flight = 4;
        attach(&model, &service);
    } else if (std.mem.eql(u8, name, "viewstate-c9-settings-launch-auto")) {
        service.add(codexFact("acct-codex-personal", "Codex Personal"), &codex_windows);
        service.launch_at_login = true;
        service.launch_at_login_registration_failed = true;
        service.auto_refresh_minutes = 15;
        attach(&model, &service);
    } else return error.UnknownFixture;

    if (language != .en) shell.update(&model, .{ .set_language = .{ .value = language, .system = .en } }, &effects);
    return bridge.serialize(allocator, 1, runtime, &model, &effects);
}

const EnumTags = struct {
    name: []const u8,
    tags: []const []const u8,
};

fn enumTagNames(comptime T: type) []const []const u8 {
    const fields = @typeInfo(T).@"enum".fields;
    const Holder = struct {
        const names = names: {
            var values: [fields.len][]const u8 = undefined;
            for (fields, 0..) |field, index| values[index] = field.name;
            break :names values;
        };
    };
    return &Holder.names;
}

fn enumsJson(allocator: std.mem.Allocator) ![]u8 {
    const values = [_]EnumTags{
        .{ .name = "Provider", .tags = enumTagNames(domain.Provider) },
        .{ .name = "UsageWindowKind", .tags = enumTagNames(domain.UsageWindowKind) },
        .{ .name = "SnapshotStatus", .tags = enumTagNames(domain.SnapshotStatus) },
        .{ .name = "CreditDetailStatus", .tags = enumTagNames(domain.CreditDetailStatus) },
        .{ .name = "AuthState", .tags = enumTagNames(ui_model.AuthState) },
        .{ .name = "Freshness", .tags = enumTagNames(ui_model.Freshness) },
        .{ .name = "ClaudeTrayWindow", .tags = enumTagNames(ui_model.ClaudeTrayWindow) },
        .{ .name = "SettingsTab", .tags = enumTagNames(ui_model.SettingsTab) },
        .{ .name = "Appearance", .tags = enumTagNames(ui_model.Appearance) },
        .{ .name = "CodexUsageWindow", .tags = enumTagNames(ui_model.CodexUsageWindow) },
        .{ .name = "Language", .tags = enumTagNames(ui_model.Language) },
        .{ .name = "AutoUpdateState", .tags = enumTagNames(ui_model.AutoUpdateState) },
        .{ .name = "UnifiedOrderSource", .tags = enumTagNames(ui_model.UnifiedOrderSource) },
        .{ .name = "UnifiedFailoverState", .tags = enumTagNames(ui_model.UnifiedFailoverState) },
        .{ .name = "ProxyReachability", .tags = enumTagNames(ui_model.ProxyReachability) },
        .{ .name = "ProxyAccountState", .tags = enumTagNames(ui_model.ProxyAccountState) },
        .{ .name = "ProxyWork", .tags = enumTagNames(ui_model.ProxyWork) },
        .{ .name = "ProxySyncState", .tags = enumTagNames(ui_model.ProxySyncState) },
        .{ .name = "ProxyAttemptResult", .tags = enumTagNames(ui_model.ProxyAttemptResult) },
        .{ .name = "ProxyServiceState", .tags = enumTagNames(ui_model.ProxyServiceState) },
        .{ .name = "CodexRoutingState", .tags = enumTagNames(ui_model.CodexRoutingState) },
        .{ .name = "OnboardingStepKind", .tags = enumTagNames(ui_model.OnboardingStepKind) },
        .{ .name = "ResetProxyClear", .tags = enumTagNames(ui_model.ResetProxyClear) },
        .{ .name = "CreditOffer", .tags = enumTagNames(ui_model.CreditOffer) },
        .{ .name = "CommandOutcome", .tags = enumTagNames(ui_model.CommandOutcome) },
        .{ .name = "ResetStage", .tags = enumTagNames(ui_model.ResetStage) },
        .{ .name = "ResetBlockReason", .tags = enumTagNames(ui_model.ResetBlockReason) },
        .{ .name = "SettleWatch", .tags = enumTagNames(@TypeOf((ui_model.ResetFlow{}).settle)) },
        .{ .name = "NoticeKind", .tags = enumTagNames(ui_model.NoticeKind) },
        .{ .name = "RuntimeError", .tags = enumTagNames(bridge.RuntimeError) },
        .{ .name = "EffectKind", .tags = enumTagNames(shell.EffectKind) },
    };
    return std.json.Stringify.valueAlloc(allocator, .{ .schema = @as(u32, 1), .enums = values }, .{});
}

const valid_intent_documents = [_][]const u8{
    "{\"intent\":\"set_appearance\",\"value\":\"dark\"}",
    "{\"intent\":\"set_language\",\"value\":\"ko\",\"system\":\"en\"}",
    "{\"intent\":\"set_codex_usage_window\",\"value\":\"weekly\"}",
    "{\"intent\":\"set_codex_show_model_limits\",\"on\":true}",
    "{\"intent\":\"set_launch_at_login\",\"on\":true}",
    "{\"intent\":\"report_launch_at_login_registration_failure\",\"failed\":true}",
    "{\"intent\":\"set_auto_refresh\",\"minutes\":15}",
    "{\"intent\":\"open_details\"}",
    "{\"intent\":\"quit_app\"}",
    "{\"intent\":\"open_account\",\"account_id\":\"acct-codex-one\"}",
    "{\"intent\":\"tab_accounts\"}",
    "{\"intent\":\"tab_failover\"}",
    "{\"intent\":\"open_toolbar_menu\"}",
    "{\"intent\":\"close_toolbar_menu\"}",
    "{\"intent\":\"toggle_account\",\"row\":0}",
    "{\"intent\":\"open_row_menu\",\"row\":0}",
    "{\"intent\":\"close_row_menu\"}",
    "{\"intent\":\"open_proxy_row_menu\",\"row\":0}",
    "{\"intent\":\"close_proxy_row_menu\"}",
    "{\"intent\":\"toggle_proxy_settings\"}",
    "{\"intent\":\"copy_diagnostics\",\"row\":0}",
    "{\"intent\":\"diagnostics_copied\",\"ok\":true}",
    "{\"intent\":\"claude_tray_weekly\"}",
    "{\"intent\":\"claude_tray_session\"}",
    "{\"intent\":\"dismiss_notice\"}",
    "{\"intent\":\"refresh_proxy_status\"}",
    "{\"intent\":\"sync_proxy_config\"}",
    "{\"intent\":\"pause_proxy_account\",\"row\":0}",
    "{\"intent\":\"resume_proxy_account\",\"row\":0}",
    "{\"intent\":\"begin_proxy_switch\",\"row\":0}",
    "{\"intent\":\"begin_clear_cooldown\",\"row\":0}",
    "{\"intent\":\"confirm_clear_cooldown\"}",
    "{\"intent\":\"cancel_clear_cooldown\"}",
    "{\"intent\":\"save_proxy_settings\",\"base_url\":\"http://127.0.0.1:8787\",\"cli_path\":\"/tmp/proxy\",\"config_path\":\"/tmp/config\",\"node_path\":\"\"}",
    "{\"intent\":\"refresh_all\"}",
    "{\"intent\":\"refresh_account\",\"row\":0}",
    "{\"intent\":\"refresh_account_id\",\"account_id\":\"acct-codex-one\"}",
    "{\"intent\":\"move_account\",\"account_id\":\"acct-codex-one\",\"target_account_id\":\"acct-codex-two\"}",
    "{\"intent\":\"begin_failover_switch\",\"row\":0}",
    "{\"intent\":\"begin_failover_switch_id\",\"account_id\":\"acct-codex-one\"}",
    "{\"intent\":\"confirm_failover_switch\"}",
    "{\"intent\":\"cancel_failover_switch\"}",
    "{\"intent\":\"pause_failover_account\",\"row\":0}",
    "{\"intent\":\"begin_clear_cooldown_account\",\"row\":0}",
    "{\"intent\":\"reauthenticate\",\"row\":0}",
    "{\"intent\":\"add_claude_account\"}",
    "{\"intent\":\"add_codex_account\"}",
    "{\"intent\":\"begin_add_account\"}",
    "{\"intent\":\"commit_add_account\",\"label\":\"  Owner Work  \"}",
    "{\"intent\":\"cancel_add_account\"}",
    "{\"intent\":\"begin_rename\",\"row\":0}",
    "{\"intent\":\"commit_rename\",\"label\":\"Renamed account\"}",
    "{\"intent\":\"cancel_rename\"}",
    "{\"intent\":\"begin_remove\",\"row\":0}",
    "{\"intent\":\"confirm_remove\"}",
    "{\"intent\":\"finish_mapped_remove\"}",
    "{\"intent\":\"cancel_remove\"}",
    "{\"intent\":\"begin_reset\",\"row\":0}",
    "{\"intent\":\"acknowledge_reset\"}",
    "{\"intent\":\"confirm_reset\"}",
    "{\"intent\":\"retry_reset\"}",
    "{\"intent\":\"cancel_reset\"}",
    "{\"intent\":\"install_proxy_service\"}",
    "{\"intent\":\"repair_proxy_service\"}",
    "{\"intent\":\"stop_proxy_service\"}",
    "{\"intent\":\"set_proxy_enabled\",\"on\":true}",
    "{\"intent\":\"enable_codex_routing\",\"replace_conflicting\":true}",
    "{\"intent\":\"disable_codex_routing\"}",
};

fn intentsAllJson(allocator: std.mem.Allocator) ![]u8 {
    var values: [valid_intent_documents.len]std.json.Value = undefined;
    var parsed: [valid_intent_documents.len]?std.json.Parsed(std.json.Value) = @splat(null);
    defer for (&parsed) |*entry| if (entry.*) |*value| value.deinit();
    for (valid_intent_documents, 0..) |document, index| {
        parsed[index] = try std.json.parseFromSlice(std.json.Value, allocator, document, .{});
        values[index] = parsed[index].?.value;
    }
    return std.json.Stringify.valueAlloc(allocator, values, .{});
}

fn intentsRejectedJson(allocator: std.mem.Allocator) ![]u8 {
    return std.json.Stringify.valueAlloc(allocator, &.{
        .{ .case = "null_handle", .input = @as(?[]const u8, null), .expected = bridge.CM_ERR_HANDLE },
        .{ .case = "malformed_json", .input = @as(?[]const u8, "["), .expected = bridge.CM_ERR_JSON },
        .{ .case = "wrong_schema", .input = @as(?[]const u8, "{\"schema\":2,\"intent\":\"refresh_all\"}"), .expected = bridge.CM_ERR_SCHEMA },
        .{ .case = "unknown_intent", .input = @as(?[]const u8, "{\"intent\":\"unknown\"}"), .expected = bridge.CM_ERR_INTENT },
        .{ .case = "bad_payload", .input = @as(?[]const u8, "{\"intent\":\"toggle_account\",\"row\":16}"), .expected = bridge.CM_ERR_PAYLOAD },
        .{ .case = "allocation_failure_injection", .input = @as(?[]const u8, "{\"intent\":\"refresh_all\"}"), .expected = bridge.CM_ERR_INTERNAL },
    }, .{});
}

fn writeFixture(io: std.Io, name: []const u8, bytes: []const u8) !void {
    var path_buffer: [160]u8 = undefined;
    const path = try std.fmt.bufPrint(&path_buffer, "{s}/{s}.json", .{ fixture_dir, name });
    try std.Io.Dir.cwd().writeFile(io, .{ .sub_path = path, .data = bytes });
}

fn exportAll(allocator: std.mem.Allocator, io: std.Io) !void {
    try std.Io.Dir.cwd().createDirPath(io, fixture_dir);
    for (projection_names) |name| {
        const bytes = try makeProjection(allocator, name);
        defer allocator.free(bytes);
        try writeFixture(io, name, bytes);
    }
    const enums = try enumsJson(allocator);
    defer allocator.free(enums);
    try writeFixture(io, "enums", enums);
    const intents_all = try intentsAllJson(allocator);
    defer allocator.free(intents_all);
    try writeFixture(io, "intents-all", intents_all);
    const intents_rejected = try intentsRejectedJson(allocator);
    defer allocator.free(intents_rejected);
    try writeFixture(io, "intents-rejected", intents_rejected);
}

pub fn main(init: std.process.Init) !void {
    const args = try init.minimal.args.toSlice(init.arena.allocator());
    const localized_options = .{
        .{ "--korean", ui_model.Language.ko },
        .{ "--japanese", ui_model.Language.ja },
        .{ "--chinese", ui_model.Language.@"zh-Hans" },
        .{ "--spanish", ui_model.Language.es },
    };
    if (args.len == 4) {
        inline for (localized_options) |option| {
            if (std.mem.eql(u8, args[1], option[0])) {
                const bytes = try makeProjectionLanguage(init.gpa, args[2], option[1]);
                defer init.gpa.free(bytes);
                try std.Io.Dir.cwd().writeFile(init.io, .{ .sub_path = args[3], .data = bytes });
                return;
            }
        }
    }
    try exportAll(init.gpa, init.io);
}

test "P6 R1 unified_rows and unified_order_source are projected" {
    const bytes = try makeProjection(testing.allocator, "viewstate-proxy-reachable-mapped");
    defer testing.allocator.free(bytes);
    var parsed = try std.json.parseFromSlice(std.json.Value, testing.allocator, bytes, .{});
    defer parsed.deinit();
    const view = parsed.value.object.get("view").?.object;
    const unified_rows = view.get("unified_rows") orelse return error.MissingUnifiedRows;
    try testing.expect(unified_rows.array.items.len != 0);
    const source = view.get("unified_order_source") orelse return error.MissingUnifiedOrderSource;
    try testing.expectEqualStrings("registry", source.string);
}

test "F17 empty fixture exports the core-owned onboarding checklist" {
    const bytes = try makeProjection(testing.allocator, "viewstate-empty-attached");
    defer testing.allocator.free(bytes);
    var parsed = try std.json.parseFromSlice(std.json.Value, testing.allocator, bytes, .{});
    defer parsed.deinit();
    const view = parsed.value.object.get("view").?.object;

    try testing.expect(view.get("onboarding_visible").?.bool);
    const steps = view.get("onboarding_steps").?.array.items;
    try testing.expectEqual(@as(usize, 2), steps.len);
    try testing.expectEqualStrings("Add a Codex account", steps[0].object.get("title").?.string);
    try testing.expectEqualStrings("Turn on Failover", steps[1].object.get("title").?.string);
    const action = view.get("onboarding_next_action").?.object;
    try testing.expectEqualStrings("add_account", action.get("kind").?.string);
    try testing.expectEqualStrings("Add Codex", action.get("label").?.string);
}

test "P6 R2 settings projection set_appearance intent and persistence are present" {
    const bytes = try makeProjection(testing.allocator, "viewstate-empty-attached");
    defer testing.allocator.free(bytes);
    var parsed = try std.json.parseFromSlice(std.json.Value, testing.allocator, bytes, .{});
    defer parsed.deinit();
    const view = parsed.value.object.get("view").?.object;
    const settings = view.get("settings") orelse return error.MissingSettingsProjection;
    try testing.expectEqualStrings("system", settings.object.get("appearance").?.string);

    var intent = switch (bridge.parseIntent(testing.allocator, "{\"intent\":\"set_appearance\",\"value\":\"dark\"}")) {
        .accepted => |value| value,
        else => return error.MissingSetAppearanceIntent,
    };
    defer intent.deinit();
}

test "F18 selecting Korean immediately reprojects the visible catalog copy" {
    var service: FixtureService = .{};
    var model: shell.Model = undefined;
    attach(&model, &service);
    try testing.expectEqual(ui_model.Language.en, model.view.settings.language);
    try testing.expectEqualStrings("No accounts registered yet", model.view.summary_text);

    var effects: shell.Effects = .{};
    shell.update(&model, .{ .set_language = .{ .value = .ko, .system = .en } }, &effects);
    try testing.expectEqual(ui_model.Language.ko, model.view.settings.language);
    try testing.expectEqualStrings("등록된 계정 없음", model.view.summary_text);
    try testing.expectEqualStrings("언어", model.view.settings.language_label);
    try testing.expectEqualStrings("시스템", model.view.settings.appearance_label_system);
    try testing.expectEqualStrings("표시할 사용량", model.view.settings.codex_usage_window_label);
    try testing.expectEqualStrings("모델별 한도", model.view.settings.codex_show_model_limits_label);
}

test "Codex settings projection owns labels supported values and typed intents" {
    const bytes = try makeProjection(testing.allocator, "viewstate-empty-attached");
    defer testing.allocator.free(bytes);
    var parsed = try std.json.parseFromSlice(std.json.Value, testing.allocator, bytes, .{});
    defer parsed.deinit();
    const settings = parsed.value.object.get("view").?.object.get("settings").?.object;
    try testing.expectEqualStrings("Codex", settings.get("codex_section_title").?.string);
    try testing.expectEqualStrings("auto", settings.get("codex_usage_window").?.string);
    try testing.expect(!settings.get("codex_show_model_limits").?.bool);
    const usage_supported = settings.get("codex_usage_window_supported").?.array.items;
    try testing.expectEqual(@as(usize, 3), usage_supported.len);
    try testing.expectEqualStrings("auto", usage_supported[0].string);
    try testing.expectEqualStrings("weekly", usage_supported[1].string);
    try testing.expectEqualStrings("session", usage_supported[2].string);
    const model_supported = settings.get("codex_show_model_limits_supported").?.array.items;
    try testing.expectEqual(@as(usize, 2), model_supported.len);
    try testing.expect(!model_supported[0].bool);
    try testing.expect(model_supported[1].bool);
    try testing.expectEqualStrings("Usage shown", settings.get("codex_usage_window_label").?.string);
    try testing.expectEqualStrings(
        "Prefer a usage window when the provider reports it.",
        settings.get("codex_usage_window_detail_text").?.string,
    );
    try testing.expectEqualStrings("Per-model limits", settings.get("codex_show_model_limits_label").?.string);
    try testing.expectEqualStrings(
        "Show reported model limits in account details and headlines.",
        settings.get("codex_show_model_limits_detail_text").?.string,
    );

    var usage_intent = switch (bridge.parseIntent(testing.allocator, "{\"intent\":\"set_codex_usage_window\",\"value\":\"session\"}")) {
        .accepted => |value| value,
        else => return error.MissingSetCodexUsageWindowIntent,
    };
    defer usage_intent.deinit();
    try testing.expectEqual(ui_model.CodexUsageWindow.session, usage_intent.intent.set_codex_usage_window);

    var model_intent = switch (bridge.parseIntent(testing.allocator, "{\"intent\":\"set_codex_show_model_limits\",\"on\":true}")) {
        .accepted => |value| value,
        else => return error.MissingSetCodexShowModelLimitsIntent,
    };
    defer model_intent.deinit();
    try testing.expect(model_intent.intent.set_codex_show_model_limits);
}

test "P6 R3 retired settings_tab compatibility is explicitly not meaningful" {
    const bytes = try makeProjection(testing.allocator, "viewstate-empty-attached");
    defer testing.allocator.free(bytes);
    var parsed = try std.json.parseFromSlice(std.json.Value, testing.allocator, bytes, .{});
    defer parsed.deinit();
    const shell_state = parsed.value.object.get("shell").?.object;
    const meaningful = shell_state.get("settings_tab_is_meaningful") orelse
        return error.MissingSettingsTabMeaningfulFlag;
    try testing.expect(!meaningful.bool);
}

test "C8 ready row keeps OAuth token fields empty in the expanded panel" {
    const bytes = try makeProjection(testing.allocator, "viewstate-c6-ready-token");
    defer testing.allocator.free(bytes);
    var parsed = try std.json.parseFromSlice(std.json.Value, testing.allocator, bytes, .{});
    defer parsed.deinit();
    const view = parsed.value.object.get("view").?.object;
    const active = view.get("unified_rows").?.array.items[0].object;
    try testing.expectEqualStrings("", active.get("failover_detail_text").?.string);
    const inspector = view.get("inspector").?.object;
    const token = inspector.get("token_value") orelse return error.MissingExpandedTokenFact;
    try testing.expectEqualStrings("", token.string);
    try testing.expectEqualStrings("", inspector.get("token_source_text").?.string);
}

test "C10 toolbar status keeps one account-free projected string" {
    const bytes = try makeProjection(testing.allocator, "viewstate-c6-ready-token");
    defer testing.allocator.free(bytes);
    var parsed = try std.json.parseFromSlice(bridge.ProjectionWire, testing.allocator, bytes, .{ .allocate = .alloc_always });
    defer parsed.deinit();
    const status = parsed.value.view.toolbar_status_text;
    try testing.expect(status.len != 0);
    try testing.expect(std.mem.indexOf(u8, status, "ready@example.com") == null);
}

test "C8 expanded cooling account projects one complete Failover value" {
    const bytes = try makeProjection(testing.allocator, "viewstate-c6-cooling-explained");
    defer testing.allocator.free(bytes);
    var parsed = try std.json.parseFromSlice(std.json.Value, testing.allocator, bytes, .{});
    defer parsed.deinit();
    const inspector = parsed.value.object.get("view").?.object.get("inspector").?.object;
    const usage_source = inspector.get("usage_source_text") orelse return error.MissingUsageClockSource;
    const failover_source = inspector.get("failover_source_text") orelse return error.MissingFailoverClockSource;
    try testing.expectEqualStrings("Codex usage API", usage_source.string);
    try testing.expectEqualStrings("Cooldown until 05:00 · 2h 0m", inspector.get("failover_state").?.string);
    try testing.expectEqualStrings("", inspector.get("failover_title").?.string);
    try testing.expectEqualStrings("", failover_source.string);
}

test "C7 Plus session 90 weekly 20 selects session and keeps credits and both panel windows" {
    const bytes = try makeProjection(testing.allocator, "viewstate-c7-plus-session-binding");
    defer testing.allocator.free(bytes);
    var parsed = try std.json.parseFromSlice(bridge.ProjectionWire, testing.allocator, bytes, .{ .allocate = .alloc_always });
    defer parsed.deinit();
    const view = parsed.value.view;
    try testing.expectEqualStrings("5-hour", view.account_rows[0].window.label);
    try testing.expectEqual(@as(usize, 2), view.usage_rows.len);
    try testing.expectEqualStrings("5-hour", view.usage_rows[0].label);
    try testing.expectEqualStrings("Weekly", view.usage_rows[1].label);
    try testing.expect(view.inspector.has_credits);
    try testing.expectEqualStrings("2 available", view.inspector.credit_value);
}

test "C7 Plus session 10 weekly 100 selects weekly and keeps both panel windows" {
    const bytes = try makeProjection(testing.allocator, "viewstate-c7-plus-weekly-binding");
    defer testing.allocator.free(bytes);
    var parsed = try std.json.parseFromSlice(bridge.ProjectionWire, testing.allocator, bytes, .{ .allocate = .alloc_always });
    defer parsed.deinit();
    const view = parsed.value.view;
    try testing.expectEqualStrings("Weekly", view.account_rows[0].window.label);
    try testing.expectEqual(@as(usize, 2), view.usage_rows.len);
    try testing.expectEqualStrings("5-hour", view.usage_rows[0].label);
    try testing.expectEqualStrings("Weekly", view.usage_rows[1].label);
}

test "C8 Pro 20x panel keeps one weekly and hides model reserve and duplicate windows by kind" {
    const bytes = try makeProjection(testing.allocator, "viewstate-c7-pro-weekly-only");
    defer testing.allocator.free(bytes);
    var parsed = try std.json.parseFromSlice(bridge.ProjectionWire, testing.allocator, bytes, .{ .allocate = .alloc_always });
    defer parsed.deinit();
    const view = parsed.value.view;
    try testing.expectEqualStrings("Weekly", view.account_rows[0].window.label);
    try testing.expectEqual(@as(usize, 4), view.rows[0].windows.len);
    try testing.expectEqual(domain.UsageWindowKind.model_scoped, view.rows[0].windows[1].kind);
    try testing.expectEqualStrings("gpt-reserve", view.rows[0].windows[2].label);
    try testing.expectEqual(@as(usize, 1), view.usage_rows.len);
    try testing.expectEqualStrings("Weekly", view.usage_rows[0].label);
}

test "C7 unknown plan selects the most constraining window and preserves unknown labels in API order" {
    const bytes = try makeProjection(testing.allocator, "viewstate-c7-unknown-plan-binding");
    defer testing.allocator.free(bytes);
    var parsed = try std.json.parseFromSlice(bridge.ProjectionWire, testing.allocator, bytes, .{ .allocate = .alloc_always });
    defer parsed.deinit();
    const view = parsed.value.view;
    try testing.expectEqualStrings("Team", view.account_rows[0].plan);
    try testing.expectEqualStrings("Quarterly pool", view.account_rows[0].window.label);
    try testing.expectEqual(@as(usize, 2), view.usage_rows.len);
    try testing.expectEqualStrings("Weekly", view.usage_rows[0].label);
    try testing.expectEqualStrings("Quarterly pool", view.usage_rows[1].label);
}

test "C8 inspector projects the existing begin-reset action only when credits remain" {
    const available_bytes = try makeProjection(testing.allocator, "viewstate-c7-pro-weekly-only");
    defer testing.allocator.free(available_bytes);
    var available = try std.json.parseFromSlice(bridge.ProjectionWire, testing.allocator, available_bytes, .{ .allocate = .alloc_always });
    defer available.deinit();
    try testing.expect(available.value.view.inspector.can_reset);
    try testing.expectEqualStrings("Use one reset (2 left)…", available.value.view.inspector.reset_label);

    const zero_bytes = try makeProjection(testing.allocator, "viewstate-c8-zero-credit");
    defer testing.allocator.free(zero_bytes);
    var zero = try std.json.parseFromSlice(bridge.ProjectionWire, testing.allocator, zero_bytes, .{ .allocate = .alloc_always });
    defer zero.deinit();
    try testing.expectEqualStrings("0 available", zero.value.view.inspector.credit_value);
    try testing.expect(!zero.value.view.inspector.can_reset);
    try testing.expectEqualStrings("", zero.value.view.inspector.reset_label);
}

test "C9 mismatch projection advances from next-refresh repair to synchronized" {
    const pending_bytes = try makeProjection(testing.allocator, "viewstate-c9-refresh-mismatch-pending");
    defer testing.allocator.free(pending_bytes);
    var pending = try std.json.parseFromSlice(bridge.ProjectionWire, testing.allocator, pending_bytes, .{ .allocate = .alloc_always });
    defer pending.deinit();
    try testing.expectEqual(ui_model.ProxySyncState.needed, pending.value.view.proxy_sync_state);
    try testing.expect(std.mem.indexOf(u8, pending.value.view.proxy_banner_text, "automatically") != null);

    const fixed_bytes = try makeProjection(testing.allocator, "viewstate-c9-refresh-mismatch-fixed");
    defer testing.allocator.free(fixed_bytes);
    var fixed = try std.json.parseFromSlice(bridge.ProjectionWire, testing.allocator, fixed_bytes, .{ .allocate = .alloc_always });
    defer fixed.deinit();
    try testing.expectEqual(ui_model.ProxySyncState.synced, fixed.value.view.proxy_sync_state);
    try testing.expectEqualStrings("", fixed.value.view.proxy_banner_text);
    try testing.expect(pending.value.view.proxy_success_revision < fixed.value.view.proxy_success_revision);
}

test "C9 switch refusal and launch auto settings are shell-ready facts" {
    const refused_bytes = try makeProjection(testing.allocator, "viewstate-c9-proxy-switch-refused");
    defer testing.allocator.free(refused_bytes);
    var refused = try std.json.parseFromSlice(bridge.ProjectionWire, testing.allocator, refused_bytes, .{ .allocate = .alloc_always });
    defer refused.deinit();
    try testing.expect(refused.value.view.settings.proxy_enabled);
    try testing.expectEqual(@as(u32, 4), refused.value.view.proxy_in_flight);
    try testing.expect(std.mem.indexOf(u8, refused.value.view.settings.proxy_enabled_detail_text, "will apply when they finish") != null);

    const settings_bytes = try makeProjection(testing.allocator, "viewstate-c9-settings-launch-auto");
    defer testing.allocator.free(settings_bytes);
    var settings = try std.json.parseFromSlice(bridge.ProjectionWire, testing.allocator, settings_bytes, .{ .allocate = .alloc_always });
    defer settings.deinit();
    try testing.expect(settings.value.view.settings.launch_at_login);
    try testing.expect(settings.value.view.settings.launch_at_login_registration_failed);
    try testing.expectEqual(@as(u16, 15), settings.value.view.settings.auto_refresh_minutes);
    try testing.expect(std.mem.indexOf(u8, settings.value.view.settings.auto_refresh_traffic_text, "4 provider requests/hour") != null);
}

test "exported bridge fixtures regenerate byte-identically" {
    for (projection_names) |name| {
        const expected = try makeProjection(testing.allocator, name);
        defer testing.allocator.free(expected);
        var path_buffer: [160]u8 = undefined;
        const path = try std.fmt.bufPrint(&path_buffer, "{s}/{s}.json", .{ fixture_dir, name });
        const actual = try std.Io.Dir.cwd().readFileAlloc(testing.io, path, testing.allocator, .limited(512 * 1024));
        defer testing.allocator.free(actual);
        try testing.expectEqualStrings(expected, actual);
    }
}

test "enum and intent fixture goldens regenerate byte-identically" {
    const cases = .{
        .{ "enums.json", enumsJson },
        .{ "intents-all.json", intentsAllJson },
        .{ "intents-rejected.json", intentsRejectedJson },
    };
    inline for (cases) |case| {
        const expected = try case[1](testing.allocator);
        defer testing.allocator.free(expected);
        var path_buffer: [160]u8 = undefined;
        const path = try std.fmt.bufPrint(&path_buffer, "{s}/{s}", .{ fixture_dir, case[0] });
        const actual = try std.Io.Dir.cwd().readFileAlloc(testing.io, path, testing.allocator, .limited(512 * 1024));
        defer testing.allocator.free(actual);
        try testing.expectEqualStrings(expected, actual);
    }
}

test "every committed projection typed-decodes and preserves its wire semantics" {
    for (projection_names) |name| {
        var path_buffer: [160]u8 = undefined;
        const path = try std.fmt.bufPrint(&path_buffer, "{s}/{s}.json", .{ fixture_dir, name });
        const bytes = try std.Io.Dir.cwd().readFileAlloc(testing.io, path, testing.allocator, .limited(512 * 1024));
        defer testing.allocator.free(bytes);
        var parsed = try std.json.parseFromSlice(bridge.ProjectionWire, testing.allocator, bytes, .{ .allocate = .alloc_always });
        defer parsed.deinit();
        const semantic = try std.json.Stringify.valueAlloc(testing.allocator, parsed.value, .{ .emit_null_optional_fields = true });
        defer testing.allocator.free(semantic);

        try testing.expectEqual(ui_model.Language.en, parsed.value.view.settings.language);
        try testing.expectEqualStrings(bytes, semantic);
    }
}

fn scanCommittedFixture(path: []const u8) !void {
    const bytes = try std.Io.Dir.cwd().readFileAlloc(testing.io, path, testing.allocator, .limited(512 * 1024));
    defer testing.allocator.free(bytes);
    var parsed = try std.json.parseFromSlice(std.json.Value, testing.allocator, bytes, .{});
    defer parsed.deinit();
    const forbidden = [_][]const u8{
        "access_token", "refresh_token", "Bearer ", "bearer ",  "authorization", "api_key",
        "sk-",          "eyJ",           "cookie",  "password", "auth.json",
    };
    for (forbidden) |pattern| try testing.expect(std.mem.indexOf(u8, bytes, pattern) == null);
}

test "all 57 committed fixtures are valid JSON and contain no credential-like material" {
    try testing.expectEqual(@as(usize, 54), projection_names.len);
    for (projection_names) |name| {
        var path_buffer: [160]u8 = undefined;
        const path = try std.fmt.bufPrint(&path_buffer, "{s}/{s}.json", .{ fixture_dir, name });
        try scanCommittedFixture(path);
    }
    try scanCommittedFixture(fixture_dir ++ "/enums.json");
    try scanCommittedFixture(fixture_dir ++ "/intents-all.json");
    try scanCommittedFixture(fixture_dir ++ "/intents-rejected.json");
}

fn expectCodexFresh(view: *const bridge.ViewWire) !void {
    try testing.expectEqual(@as(usize, 1), view.rows.len);
    const account = view.rows[0];
    try testing.expectEqual(domain.Provider.codex, account.provider);
    try testing.expectEqual(ui_model.Freshness.saved_snapshot, account.freshness);
    try testing.expectEqual(@as(?domain.SnapshotStatus, .fresh), account.snapshot_status);
    try testing.expect(account.has_snapshot);
    try testing.expectEqual(@as(?i64, now - 600), account.snapshot_captured_at_unix_s);
    try testing.expectEqual(@as(?i64, now - 600), account.last_attempt_at_unix_s);
    try testing.expectEqual(@as(?i64, now - 600), account.last_success_at_unix_s);
}

test "every named projection fixture proves its distinguishing state" {
    for (projection_names) |name| {
        var path_buffer: [160]u8 = undefined;
        const path = try std.fmt.bufPrint(&path_buffer, "{s}/{s}.json", .{ fixture_dir, name });
        const bytes = try std.Io.Dir.cwd().readFileAlloc(testing.io, path, testing.allocator, .limited(512 * 1024));
        defer testing.allocator.free(bytes);
        var parsed = try std.json.parseFromSlice(std.json.Value, testing.allocator, bytes, .{});
        defer parsed.deinit();
        var typed = try std.json.parseFromSlice(bridge.ProjectionWire, testing.allocator, bytes, .{ .allocate = .alloc_always });
        defer typed.deinit();
        const wire = typed.value;
        const root = parsed.value.object;
        const shell_state = root.get("shell").?.object;
        const view = root.get("view").?.object;
        try testing.expectEqualStrings("", shell_state.get("claude_summary_weekly_label").?.string);
        try testing.expectEqualStrings("", shell_state.get("claude_summary_session_label").?.string);
        if (std.mem.eql(u8, name, "viewstate-unattached")) {
            try testing.expect(!wire.runtime.started and wire.runtime.@"error" == null);
            try testing.expectEqual(ui_model.ServiceCapabilities{}, wire.view.capabilities);
            try testing.expectEqual(@as(usize, 0), wire.view.rows.len);
        } else if (std.mem.eql(u8, name, "viewstate-empty-attached")) {
            try testing.expect(wire.runtime.started and wire.view.capabilities.connected);
            try testing.expectEqual(@as(usize, 0), wire.view.rows.len);
        } else if (std.mem.eql(u8, name, "viewstate-two-accounts-fresh")) {
            try testing.expectEqual(@as(i64, 1), view.get("account_row_count").?.integer);
            try testing.expectEqual(@as(i64, 0), view.get("claude_count").?.integer);
            try testing.expectEqual(@as(i64, 1), view.get("codex_count").?.integer);
            try expectCodexFresh(&wire.view);
            const generated = try makeProjection(testing.allocator, name);
            defer testing.allocator.free(generated);
            var generated_typed = try std.json.parseFromSlice(bridge.ProjectionWire, testing.allocator, generated, .{ .allocate = .alloc_always });
            defer generated_typed.deinit();
            try expectCodexFresh(&generated_typed.value.view);
        } else if (std.mem.eql(u8, name, "viewstate-attention-states")) {
            try testing.expectEqual(@as(i64, 5), view.get("account_row_count").?.integer);
            try testing.expect(view.get("error_count").?.integer > 0);
            try testing.expect(view.get("reauth_count").?.integer > 0);
            const expected = [_]ui_model.Freshness{ .reauth_required, .refresh_failed, .usage_unavailable, .refresh_deferred, .reset_passed };
            for (expected, wire.view.rows) |freshness, account| try testing.expectEqual(freshness, account.freshness);
        } else if (std.mem.eql(u8, name, "viewstate-proxy-reachable-mapped")) {
            try testing.expectEqualStrings("reachable", view.get("proxy_reachability").?.string);
            try testing.expect(view.get("proxy_config_path_matches").?.bool);
            try testing.expectEqual(@as(u32, 4), wire.view.proxy_mapped_count);
            try testing.expect(wire.view.proxy_rows[0].active and wire.view.proxy_rows[0].mapped);
            try testing.expectEqual(ui_model.ProxyAccountState.cooldown, wire.view.proxy_rows[2].state);
            try testing.expectEqual(ui_model.ProxyAccountState.paused, wire.view.proxy_rows[3].state);
            try testing.expectEqual(ui_model.ProxyAccountState.invalid, wire.view.proxy_rows[4].state);
            try testing.expect(!wire.view.proxy_rows[4].mapped);
        } else if (std.mem.eql(u8, name, "viewstate-proxy-unreachable")) {
            try testing.expectEqual(ui_model.ProxyReachability.@"unreachable", wire.view.proxy_reachability);
            try testing.expectEqual(ui_model.ProxySyncState.failed, wire.view.proxy_sync_state);
            try testing.expectEqual(@as(usize, 0), wire.view.proxy_rows.len);
        } else if (std.mem.eql(u8, name, "viewstate-proxy-config-mismatch")) {
            try testing.expectEqual(ui_model.ProxyReachability.reachable, wire.view.proxy_reachability);
            try testing.expectEqual(ui_model.ProxySyncState.needed, wire.view.proxy_sync_state);
            try testing.expect(!wire.view.proxy_config_path_matches);
        } else if (std.mem.eql(u8, name, "viewstate-proxy-checking")) {
            try testing.expectEqual(ui_model.ProxyWork.checking, wire.view.proxy_work);
            try testing.expectEqual(ui_model.NoticeKind.pending, wire.shell.notice.kind);
            try testing.expect(std.mem.indexOf(u8, wire.shell.notice.text, "Proxy status in progress") != null);
            try testing.expectEqualStrings(" · refreshing", wire.view.busy_suffix_text);
        } else if (std.mem.eql(u8, name, "viewstate-proxy-settings-open")) {
            try testing.expect(wire.shell.proxy_settings_expanded);
        } else if (std.mem.eql(u8, name, "viewstate-expanded-codex")) {
            try testing.expectEqual(@as(?u32, 0), wire.shell.expanded);
            try testing.expectEqual(domain.Provider.codex, wire.view.rows[wire.shell.expanded.?].provider);
            try testing.expectEqualStrings("Codex Personal", wire.view.inspector.title);
        } else if (std.mem.eql(u8, name, "viewstate-expanded-claude")) {
            try testing.expect(wire.shell.expanded == null);
            try testing.expectEqual(@as(usize, 0), wire.view.rows.len);
            try testing.expect(!wire.view.inspector.present);
        } else if (std.mem.eql(u8, name, "viewstate-tray-truncated")) {
            try testing.expectEqual(@as(i64, 16), view.get("account_row_count").?.integer);
            try testing.expectEqual(@as(usize, 24), view.get("tray").?.object.get("items").?.array.items.len);
            try testing.expect(wire.view.tray.items.len < ui_model.max_tray_items);
        } else if (std.mem.startsWith(u8, name, "viewstate-reset-")) {
            const reset = shell_state.get("reset").?.object;
            if (std.mem.endsWith(u8, name, "review")) {
                try testing.expectEqualStrings("review", reset.get("stage").?.string);
                try testing.expectEqual(ui_model.CommandOutcome.none, wire.shell.reset.outcome);
            } else if (std.mem.endsWith(u8, name, "armed")) {
                try testing.expectEqualStrings("armed", reset.get("stage").?.string);
                try testing.expectEqual(ui_model.CommandOutcome.none, wire.shell.reset.outcome);
            } else if (std.mem.indexOf(u8, name, "blocked") != null) {
                try testing.expectEqualStrings("blocked", reset.get("stage").?.string);
                if (std.mem.endsWith(u8, name, "no-credit")) {
                    try testing.expectEqual(ui_model.ResetBlockReason.no_credit, wire.shell.reset.reason);
                    try testing.expect(!wire.shell.reset.awaits_reconciliation);
                } else {
                    try testing.expectEqualStrings("pending_attempt", reset.get("reason").?.string);
                    try testing.expect(wire.shell.reset.awaits_reconciliation);
                }
            } else if (std.mem.endsWith(u8, name, "dispatched-pending")) {
                try testing.expectEqual(ui_model.ResetStage.dispatched, wire.shell.reset.stage);
                try testing.expectEqual(ui_model.CommandOutcome.accepted_pending, wire.shell.reset.outcome);
                try testing.expectEqual(@as(@TypeOf(wire.shell.reset.settle), .waiting), wire.shell.reset.settle);
                try testing.expectEqual(ui_model.ResetProxyClear.none, wire.shell.reset.proxy_clear);
            } else if (std.mem.endsWith(u8, name, "settled-clear-failed")) {
                try testing.expectEqual(ui_model.ResetStage.dispatched, wire.shell.reset.stage);
                try testing.expectEqual(@as(@TypeOf(wire.shell.reset.settle), .settled), wire.shell.reset.settle);
                try testing.expectEqual(ui_model.ResetProxyClear.failed, wire.shell.reset.proxy_clear);
                try testing.expect(wire.shell.reset.shows_proxy_clear);
            } else if (std.mem.endsWith(u8, name, "settled-cleared")) {
                try testing.expectEqualStrings("settled", reset.get("settle").?.string);
                try testing.expectEqualStrings("cleared", reset.get("proxy_clear").?.string);
                try testing.expectEqual(ui_model.CommandOutcome.accepted_pending, wire.shell.reset.outcome);
                try testing.expect(wire.shell.reset.shows_proxy_clear);
            } else {
                try testing.expectEqualStrings("settled_unsent", reset.get("settle").?.string);
                try testing.expectEqual(ui_model.CommandOutcome.accepted_pending, wire.shell.reset.outcome);
                try testing.expect(!wire.shell.reset.shows_proxy_clear);
            }
        } else if (std.mem.eql(u8, name, "viewstate-remove-plain-open")) {
            try testing.expect(wire.shell.remove.open);
            try testing.expect(!wire.shell.remove.uses_proxy and !wire.shell.remove.pause_requested and !wire.shell.remove.can_finish);
        } else if (std.mem.eql(u8, name, "viewstate-remove-mapped-open")) {
            try testing.expect(wire.shell.remove.open and wire.shell.remove.uses_proxy);
            try testing.expect(!wire.shell.remove.pause_requested and !wire.shell.remove.can_finish);
        } else if (std.mem.eql(u8, name, "viewstate-remove-mapped-can-finish")) {
            try testing.expect(wire.shell.remove.open and wire.shell.remove.uses_proxy and wire.shell.remove.pause_requested);
            try testing.expect(wire.shell.remove.can_finish);
            try testing.expectEqual(ui_model.ProxyAccountState.paused, wire.view.proxy_rows[0].state);
            try testing.expectEqual(@as(u32, 0), wire.view.proxy_rows[0].in_flight);
        } else if (std.mem.eql(u8, name, "viewstate-remove-mapped-pause-requested")) {
            try testing.expect(wire.shell.remove.open and wire.shell.remove.pause_requested and wire.shell.remove.uses_proxy);
            try testing.expectEqualStrings("acct-codex-active", wire.shell.remove.account_id);
        } else if (std.mem.eql(u8, name, "viewstate-rename-open")) {
            try testing.expect(wire.shell.rename.open);
            try testing.expectEqualStrings("Codex Personal", wire.shell.rename.initial_label);
        } else if (std.mem.eql(u8, name, "viewstate-add-account-empty")) {
            try testing.expect(wire.shell.add_account.open);
            try testing.expectEqualStrings("", wire.shell.add_account.initial_label);
            try testing.expect(!wire.shell.add_account.confirm_enabled and !wire.shell.add_account.in_flight);
        } else if (std.mem.eql(u8, name, "viewstate-add-account-valid")) {
            try testing.expect(wire.shell.add_account.open);
            try testing.expectEqualStrings("Owner Work", wire.shell.add_account.initial_label);
            try testing.expect(wire.shell.add_account.confirm_enabled and !wire.shell.add_account.in_flight);
        } else if (std.mem.eql(u8, name, "viewstate-add-account-in-flight")) {
            try testing.expect(wire.shell.add_account.open and wire.shell.add_account.in_flight);
            try testing.expect(!wire.shell.add_account.confirm_enabled);
            try testing.expectEqualStrings("Owner Work", wire.shell.add_account.initial_label);
            try testing.expectEqualStrings("Add account in progress · Codex", wire.shell.add_account.progress_text);
        } else if (std.mem.eql(u8, name, "viewstate-failover-switch-open")) {
            try testing.expect(wire.shell.failover_switch.open);
            try testing.expectEqualStrings("acct-codex-ready", wire.shell.failover_switch.account_id);
        } else if (std.mem.eql(u8, name, "viewstate-clear-cooldown-open")) {
            try testing.expect(wire.shell.clear_cooldown.open);
            try testing.expectEqualStrings("cooling@example.com", wire.shell.clear_cooldown.label);
        } else if (std.mem.eql(u8, name, "viewstate-notice-blocked")) {
            try testing.expectEqual(ui_model.NoticeKind.blocked, wire.shell.notice.kind);
            try testing.expect(std.mem.indexOf(u8, wire.shell.notice.text, "refused") != null);
        } else if (std.mem.eql(u8, name, "viewstate-notice-pending")) {
            try testing.expectEqual(ui_model.NoticeKind.pending, wire.shell.notice.kind);
            try testing.expect(std.mem.indexOf(u8, wire.shell.notice.text, "in progress") != null);
        } else if (std.mem.startsWith(u8, name, "viewstate-proxy-service-")) {
            const expected: ui_model.ProxyServiceState = if (std.mem.endsWith(u8, name, "not-installed"))
                .not_installed
            else if (std.mem.endsWith(u8, name, "installed-stale"))
                .installed_stale
            else if (std.mem.endsWith(u8, name, "starting"))
                .starting
            else if (std.mem.endsWith(u8, name, "running"))
                .running
            else if (std.mem.endsWith(u8, name, "unreachable"))
                .@"unreachable"
            else
                return error.UnknownFixtureName;
            try testing.expectEqual(expected, wire.view.proxy_service_state);
            try testing.expect(wire.view.proxy_cli_default_path.len != 0);
            try testing.expect(wire.view.proxy_node_default_path.len != 0);
        } else if (std.mem.eql(u8, name, "viewstate-unified-proxy-order")) {
            try testing.expectEqual(ui_model.UnifiedOrderSource.registry, wire.view.unified_order_source);
            try testing.expectEqual(@as(usize, 3), wire.view.unified_rows.len);
            try testing.expectEqualStrings("alpha@example.com", wire.view.unified_rows[0].identity_label);
            try testing.expectEqualStrings("unmapped@example.com", wire.view.unified_rows[1].identity_label);
            try testing.expectEqualStrings("gamma@example.com", wire.view.unified_rows[2].identity_label);
            try testing.expectEqual(ui_model.UnifiedFailoverState.cooldown, wire.view.unified_rows[0].failover_state);
            try testing.expectEqual(ui_model.UnifiedFailoverState.not_mapped, wire.view.unified_rows[1].failover_state);
            try testing.expectEqual(ui_model.UnifiedFailoverState.active, wire.view.unified_rows[2].failover_state);
            try testing.expectEqual(@as(?u32, 2), wire.view.unified_rows[2].inspector_index);
        } else if (std.mem.eql(u8, name, "viewstate-unified-registry-order")) {
            try testing.expectEqual(ui_model.UnifiedOrderSource.registry, wire.view.unified_order_source);
            try testing.expectEqualStrings("second@example.com", wire.view.unified_rows[0].identity_label);
            try testing.expectEqualStrings("first@example.com", wire.view.unified_rows[1].identity_label);
            try testing.expectEqual(ui_model.UnifiedFailoverState.cooldown, wire.view.unified_rows[0].failover_state);
            try testing.expectEqual(ui_model.UnifiedFailoverState.active, wire.view.unified_rows[1].failover_state);
        } else if (std.mem.eql(u8, name, "viewstate-c6-ready-token")) {
            try testing.expectEqual(@as(usize, 1), wire.view.unified_rows.len);
            try testing.expectEqual(ui_model.UnifiedFailoverState.active, wire.view.unified_rows[0].failover_state);
            try testing.expectEqualStrings("", wire.view.unified_rows[0].failover_detail_text);
            try testing.expectEqualStrings("", wire.view.inspector.token_value);
            try testing.expectEqualStrings("", wire.view.inspector.token_source_text);
        } else if (std.mem.eql(u8, name, "viewstate-c6-cooling-explained")) {
            try testing.expectEqual(ui_model.UnifiedFailoverState.cooldown, wire.view.unified_rows[0].failover_state);
            try testing.expectEqualStrings("Cooldown until 05:00 · 2h 0m", wire.view.inspector.failover_state);
            try testing.expect(std.mem.indexOf(u8, wire.view.usage_rows[0].reset_line, "Jul 28 03:00") != null);
            try testing.expectEqualStrings("Codex usage API", wire.view.inspector.usage_source_text);
            try testing.expectEqualStrings("", wire.view.inspector.failover_title);
            try testing.expectEqualStrings("", wire.view.inspector.failover_source_text);
        } else if (std.mem.startsWith(u8, name, "viewstate-c7-")) {
            try testing.expectEqual(@as(usize, 1), wire.view.account_rows.len);
            try testing.expect(wire.view.inspector.has_credits);
            if (std.mem.endsWith(u8, name, "plus-session-binding")) {
                try testing.expectEqual(@as(usize, 2), wire.view.usage_rows.len);
                try testing.expectEqualStrings("Plus", wire.view.account_rows[0].plan);
                try testing.expectEqualStrings("5-hour", wire.view.account_rows[0].window.label);
                try testing.expectEqualStrings("5-hour", wire.view.usage_rows[0].label);
                try testing.expectEqualStrings("Weekly", wire.view.usage_rows[1].label);
            } else if (std.mem.endsWith(u8, name, "plus-weekly-binding")) {
                try testing.expectEqual(@as(usize, 2), wire.view.usage_rows.len);
                try testing.expectEqualStrings("Plus", wire.view.account_rows[0].plan);
                try testing.expectEqualStrings("Weekly", wire.view.account_rows[0].window.label);
            } else if (std.mem.endsWith(u8, name, "pro-weekly-only")) {
                try testing.expectEqual(@as(usize, 1), wire.view.usage_rows.len);
                try testing.expectEqualStrings("Pro 20x", wire.view.account_rows[0].plan);
                try testing.expectEqualStrings("Weekly", wire.view.account_rows[0].window.label);
                try testing.expectEqualStrings("Weekly", wire.view.usage_rows[0].label);
                try testing.expectEqual(domain.UsageWindowKind.model_scoped, wire.view.rows[0].windows[1].kind);
                try testing.expectEqualStrings("gpt-reserve", wire.view.rows[0].windows[2].label);
            } else if (std.mem.endsWith(u8, name, "unknown-plan-binding")) {
                try testing.expectEqual(@as(usize, 2), wire.view.usage_rows.len);
                try testing.expectEqualStrings("Team", wire.view.account_rows[0].plan);
                try testing.expectEqualStrings("Quarterly pool", wire.view.account_rows[0].window.label);
                try testing.expectEqualStrings("Weekly", wire.view.usage_rows[0].label);
                try testing.expectEqualStrings("Quarterly pool", wire.view.usage_rows[1].label);
            } else return error.UnknownFixtureName;
        } else if (std.mem.eql(u8, name, "viewstate-c8-zero-credit")) {
            try testing.expect(wire.view.inspector.present);
            try testing.expectEqualStrings("0 available", wire.view.inspector.credit_value);
            try testing.expect(!wire.view.inspector.can_reset);
            try testing.expectEqualStrings("", wire.view.inspector.reset_label);
        } else if (std.mem.startsWith(u8, name, "viewstate-settings-appearance-")) {
            const expected: ui_model.Appearance = if (std.mem.endsWith(u8, name, "light"))
                .light
            else if (std.mem.endsWith(u8, name, "dark"))
                .dark
            else
                .system;
            try testing.expectEqual(expected, wire.view.settings.appearance);
            try testing.expectEqual(ui_model.Language.en, wire.view.settings.language);
            try testing.expectEqual([6]ui_model.Language{ .system, .en, .ko, .ja, .@"zh-Hans", .es }, wire.view.settings.language_supported);
            try testing.expectEqual(ui_model.AutoUpdateState.unavailable, wire.view.settings.auto_update_state);
            try testing.expect(std.mem.indexOf(u8, wire.view.settings.auto_update_detail_text, "no update channel is configured") != null);
            try testing.expectEqualStrings("Version 0.1.0 (build 0.1.0)", wire.view.settings.app_version_text);
            try testing.expectEqual(wire.view.proxy_service_state, wire.view.settings.proxy_service_state);
            try testing.expectEqual(wire.view.codex_routing_state, wire.view.settings.codex_routing_state);
            try testing.expectEqualStrings(wire.view.proxy_base_url, wire.view.settings.proxy_base_url);
            try testing.expectEqualStrings(wire.view.proxy_cli_default_path, wire.view.settings.proxy_cli_default_path);
            try testing.expectEqualStrings(wire.view.proxy_node_default_path, wire.view.settings.proxy_node_default_path);
        } else if (std.mem.eql(u8, name, "viewstate-c9-refresh-mismatch-pending")) {
            try testing.expectEqual(ui_model.ProxySyncState.needed, wire.view.proxy_sync_state);
            try testing.expect(std.mem.indexOf(u8, wire.view.proxy_banner_text, "automatically") != null);
            try testing.expectEqual(@as(u64, 5), wire.view.proxy_success_revision);
        } else if (std.mem.eql(u8, name, "viewstate-c9-refresh-mismatch-fixed")) {
            try testing.expectEqual(ui_model.ProxySyncState.synced, wire.view.proxy_sync_state);
            try testing.expectEqualStrings("", wire.view.proxy_banner_text);
            try testing.expectEqual(@as(u64, 6), wire.view.proxy_success_revision);
        } else if (std.mem.eql(u8, name, "viewstate-c9-proxy-switch-refused")) {
            try testing.expect(wire.view.settings.proxy_enabled);
            try testing.expectEqual(@as(u32, 4), wire.view.proxy_in_flight);
            try testing.expect(std.mem.indexOf(u8, wire.view.settings.proxy_enabled_detail_text, "will apply when they finish") != null);
        } else if (std.mem.eql(u8, name, "viewstate-c9-settings-launch-auto")) {
            try testing.expect(wire.view.settings.launch_at_login);
            try testing.expect(wire.view.settings.launch_at_login_registration_failed);
            try testing.expectEqual(@as(u16, 15), wire.view.settings.auto_refresh_minutes);
            try testing.expect(std.mem.indexOf(u8, wire.view.settings.auto_refresh_traffic_text, "4 provider requests/hour") != null);
        } else if (std.mem.eql(u8, name, "viewstate-runtime-error-keychain")) {
            try testing.expectEqual(bridge.RuntimeError.keychain_unavailable, wire.runtime.@"error".?);
            try testing.expect(!wire.runtime.started);
            try testing.expectEqual(ui_model.ServiceCapabilities{}, wire.view.capabilities);
        } else return error.UnknownFixtureName;
    }
}

test "Korean reset and account dialogs serialize localized user-facing text" {
    const bytes = try makeProjectionLanguage(testing.allocator, "viewstate-reset-blocked-no-credit", .ko);
    defer testing.allocator.free(bytes);
    var parsed = try std.json.parseFromSlice(bridge.ProjectionWire, testing.allocator, bytes, .{ .allocate = .alloc_always });
    defer parsed.deinit();
    try testing.expectEqualStrings("이 계정에는 제공자가 확인한 사용 가능한 리셋 크레딧이 없습니다.", parsed.value.shell.reset.blocked_text);
    try testing.expectEqualStrings("Codex 계정 추가", parsed.value.shell.add_account.title);
    try testing.expectEqualStrings("취소", parsed.value.shell.add_account.cancel_label);
}

test "Chinese and Spanish selections parse and immediately project localized settings and dialogs" {
    const cases = .{
        .{ ui_model.Language.@"zh-Hans", "zh-Hans", "语言", "尚未添加账户", "添加 Codex 账户" },
        .{ ui_model.Language.es, "es", "Idioma", "Aún no hay cuentas registradas", "Añadir cuenta de Codex" },
    };
    inline for (cases) |case| {
        const json = "{\"intent\":\"set_language\",\"value\":\"" ++ case[1] ++ "\",\"system\":\"" ++ case[1] ++ "\"}";
        var intent = switch (bridge.parseIntent(testing.allocator, json)) {
            .accepted => |value| value,
            else => return error.LanguageIntentRejected,
        };
        defer intent.deinit();
        var service: FixtureService = .{};
        var model: shell.Model = undefined;
        attach(&model, &service);
        var effects: shell.Effects = .{};
        shell.update(&model, intent.intent, &effects);
        try testing.expectEqual(case[0], model.view.settings.language);
        try testing.expectEqualStrings(case[2], model.view.settings.language_label);
        try testing.expectEqualStrings(case[3], model.view.summary_text);
        const bytes = try makeProjectionLanguage(testing.allocator, "viewstate-add-account-empty", case[0]);
        defer testing.allocator.free(bytes);
        var parsed = try std.json.parseFromSlice(std.json.Value, testing.allocator, bytes, .{});
        defer parsed.deinit();
        try testing.expectEqualStrings(case[4], parsed.value.object.get("shell").?.object.get("add_account").?.object.get("title").?.string);
    }
}
