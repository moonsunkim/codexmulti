const std = @import("std");
const cmcore = @import("cmcore");
const bridge = cmcore.bridge_json;
const shell = bridge.shell;
const ui = bridge.ui_model;

const testing = std.testing;

test "Codex CLI minimum version boundary classifies too old supported and unknown" {
    try testing.expectEqual(
        cmcore.CliVersionCompatibility.too_old,
        cmcore.classifyCliVersionOutput("codex-cli 0.145.9", cmcore.minimum_codex_cli_version),
    );
    try testing.expectEqual(
        cmcore.CliVersionCompatibility.supported,
        cmcore.classifyCliVersionOutput("codex-cli 0.146.0", cmcore.minimum_codex_cli_version),
    );
    try testing.expectEqual(
        cmcore.CliVersionCompatibility.supported,
        cmcore.classifyCliVersionOutput("codex-cli 0.153.2", cmcore.minimum_codex_cli_version),
    );
    try testing.expectEqual(
        cmcore.CliVersionCompatibility.unknown,
        cmcore.classifyCliVersionOutput("codex-cli dev", cmcore.minimum_codex_cli_version),
    );
}

extern "c" fn setenv(name: [*:0]const u8, value: [*:0]const u8, overwrite: c_int) c_int;
extern "c" fn unsetenv(name: [*:0]const u8) c_int;
extern "c" fn getenv(name: [*:0]const u8) ?[*:0]const u8;

const SavedEnv = struct {
    name: [:0]const u8,
    value: ?[:0]u8,

    fn capture(name: [:0]const u8) !SavedEnv {
        const value = if (getenv(name.ptr)) |raw| try testing.allocator.dupeZ(u8, std.mem.span(raw)) else null;
        return .{ .name = name, .value = value };
    }

    fn restore(self: SavedEnv) void {
        if (self.value) |value| {
            _ = setenv(self.name.ptr, value.ptr, 1);
            testing.allocator.free(value);
        } else {
            _ = unsetenv(self.name.ptr);
        }
    }
};

fn projectedGeneration(bytes: []const u8) !u64 {
    var parsed = try std.json.parseFromSlice(std.json.Value, testing.allocator, bytes, .{});
    defer parsed.deinit();
    return @intCast(parsed.value.object.get("generation").?.integer);
}

test "C4 keychain probe ABI is retained as an empty non-reading document" {
    const source = try std.Io.Dir.cwd().readFileAlloc(
        testing.io,
        "src/cmcore.zig",
        testing.allocator,
        .limited(256 * 1024),
    );
    defer testing.allocator.free(source);
    const marker = "pub export fn cm_service_keychain_probe";
    const start = std.mem.indexOf(u8, source, marker) orelse return error.TestUnexpectedResult;
    const body = source[start..];
    try testing.expect(std.mem.indexOf(u8, body, "runtime") == null);
    try testing.expect(std.mem.indexOf(u8, body, ".load(") == null);
    try testing.expect(std.mem.indexOf(u8, body, "probeOne") == null);

    const inert_handle = try testing.allocator.create(cmcore.cm_service);
    defer testing.allocator.destroy(inert_handle);
    var output: [128]u8 = undefined;
    const count = cmcore.cm_service_keychain_probe(inert_handle, &output, output.len);
    try testing.expect(count > 0);
    try testing.expectEqualStrings(
        "{\"schema\":1,\"signer_valid\":true,\"accounts\":[]}",
        output[0..@intCast(count)],
    );
    try testing.expectEqual(@as(i32, -2), cmcore.cm_service_keychain_probe(inert_handle, null, output.len));
    try testing.expectEqual(@as(i32, -2), cmcore.cm_service_keychain_probe(inert_handle, &output, 1));
}

test "C4 core startup and worker have no Claude route" {
    const forbidden_startup_tokens = [_][]const u8{
        "claude_credential_source.zig",
        "claude_oauth_login.zig",
        "expected_claude_cli_version",
        "claude_executable",
        "resolveProviderExecutable(io, path_variable, home, \"claude\"",
        "systemSecItemApi()",
        ".claude_login =",
        ".credential_source =",
        ".claude_config =",
        "codexmulti_claude_tray_window_get",
        "codexmulti_claude_tray_window_set",
    };
    const roots = [_][]const u8{"src/cmcore.zig"};
    for (roots) |path| {
        const source = try std.Io.Dir.cwd().readFileAlloc(
            testing.io,
            path,
            testing.allocator,
            .limited(1024 * 1024),
        );
        defer testing.allocator.free(source);
        for (forbidden_startup_tokens) |token| {
            if (std.mem.indexOf(u8, source, token) != null) {
                std.debug.print("C4 forbidden startup token {s} in {s}\n", .{ token, path });
                return error.TestUnexpectedResult;
            }
        }
    }

    const worker_source = try std.Io.Dir.cwd().readFileAlloc(
        testing.io,
        "src/app_worker.zig",
        testing.allocator,
        .limited(1024 * 1024),
    );
    defer testing.allocator.free(worker_source);
    try testing.expect(std.mem.indexOf(u8, worker_source, "claude") == null);
    try testing.expect(std.mem.indexOf(u8, worker_source, "Claude") == null);
}

test "cm.bridge schema 1 projects Swift shell wording additions and enabled behavior" {
    var model = shell.initialModel(.kst);
    model.now_unix_s = 1_784_948_400;
    model.view.begin(model.now_unix_s, .{ .connected = true, .refresh = true, .accounts = true, .reset = true }, .kst);
    _ = try model.view.pushAccount(.{
        .account_id = "acct-codex-disabled",
        .label = "Disabled Codex",
        .plan_label = "Pro",
        .provider = .codex,
        .enabled = false,
        .auth_state = .connected,
        .freshness = .as_of,
        .has_snapshot = true,
        .snapshot_status = .fresh,
        .last_success_at_unix_s = model.now_unix_s - 12 * 60,
    });
    _ = try model.view.pushAccount(.{
        .account_id = "acct-codex-fallback",
        .label = "Codex fallback",
        .provider = .codex,
        .enabled = true,
        .auth_state = .connected,
        .freshness = .saved_snapshot,
        .has_snapshot = true,
        .snapshot_status = .fresh,
        .last_success_at_unix_s = model.now_unix_s - 2 * 60 * 60,
    });
    _ = try model.view.pushAccount(.{
        .account_id = "acct-codex-failed",
        .label = "Failed Codex",
        .provider = .codex,
        .enabled = true,
        .auth_state = .connected,
        .freshness = .refresh_failed,
        .has_snapshot = true,
        .snapshot_status = .error_state,
        .last_success_at_unix_s = model.now_unix_s - 24 * 60 * 60,
        .last_attempt_at_unix_s = model.now_unix_s - 5 * 60,
        .last_attempt_code = "network",
    });
    model.view.finish(.{ .selected = 0 });

    var effects: shell.Effects = .{};
    const bytes = try bridge.serialize(testing.allocator, 1, .{ .started = true }, &model, &effects);
    defer testing.allocator.free(bytes);
    var parsed = try std.json.parseFromSlice(std.json.Value, testing.allocator, bytes, .{});
    defer parsed.deinit();
    const root = parsed.value.object;
    try testing.expectEqual(@as(i64, 1), root.get("schema").?.integer);
    const shell_state = root.get("shell").?.object;
    try testing.expectEqualStrings("Starting…", shell_state.get("starting_text").?.string);
    try testing.expectEqualStrings("Quit", shell_state.get("quit_label").?.string);
    try testing.expectEqualStrings("", shell_state.get("claude_summary_weekly_label").?.string);
    try testing.expectEqualStrings("", shell_state.get("claude_summary_session_label").?.string);
    const view = root.get("view").?.object;
    try testing.expectEqualStrings("", view.get("busy_suffix_text").?.string);
    try testing.expectEqualStrings("Proxy control is not attached.", view.get("proxy_empty_text").?.string);
    const rows = view.get("rows").?.array.items;
    try testing.expect(!rows[0].object.get("enabled").?.bool);
    try testing.expect(rows[1].object.get("enabled").?.bool);
    try testing.expectEqualStrings("Pro · Codex", rows[0].object.get("tray_summary_line").?.string);
    try testing.expectEqualStrings("Account · Codex", rows[1].object.get("tray_summary_line").?.string);
    try testing.expectEqualStrings("12m ago", view.get("inspector").?.object.get("updated_ago_text").?.string);
    const tray = view.get("tray").?.object;
    try testing.expectEqualStrings("Refresh Usage", tray.get("refresh_usage_label").?.string);
    try testing.expectEqualStrings("Open in Settings…", tray.get("open_in_settings_label").?.string);
    try testing.expectEqualStrings("CodexMulti — saved usage and CLI accounts", tray.get("help_text").?.string);

    model.view.finish(.{ .selected = 1 });
    const saved_bytes = try bridge.serialize(testing.allocator, 2, .{ .started = true }, &model, &effects);
    defer testing.allocator.free(saved_bytes);
    var saved_parsed = try std.json.parseFromSlice(std.json.Value, testing.allocator, saved_bytes, .{});
    defer saved_parsed.deinit();
    try testing.expectEqualStrings(
        "2h ago · saved snapshot",
        saved_parsed.value.object.get("view").?.object.get("inspector").?.object.get("updated_ago_text").?.string,
    );

    model.view.finish(.{ .selected = 2 });
    const failed_bytes = try bridge.serialize(testing.allocator, 3, .{ .started = true }, &model, &effects);
    defer testing.allocator.free(failed_bytes);
    var failed_parsed = try std.json.parseFromSlice(std.json.Value, testing.allocator, failed_bytes, .{});
    defer failed_parsed.deinit();
    const failed_inspector = failed_parsed.value.object.get("view").?.object.get("inspector").?.object;
    try testing.expectEqualStrings("1d ago · refresh failed", failed_inspector.get("updated_ago_text").?.string);
    try testing.expect(failed_inspector.get("attention").?.bool);

    model.view.rows[0].operation_in_flight = true;
    model.view.finish(.{ .selected = 0 });
    const busy_bytes = try bridge.serialize(testing.allocator, 4, .{ .started = true }, &model, &effects);
    defer testing.allocator.free(busy_bytes);
    var busy_parsed = try std.json.parseFromSlice(std.json.Value, testing.allocator, busy_bytes, .{});
    defer busy_parsed.deinit();
    try testing.expectEqualStrings(" · refreshing", busy_parsed.value.object.get("view").?.object.get("busy_suffix_text").?.string);

    model.view.begin(model.now_unix_s, .{ .connected = true, .proxy_control = true }, .kst);
    model.view.finish(.{});
    const attached_bytes = try bridge.serialize(testing.allocator, 5, .{ .started = true }, &model, &effects);
    defer testing.allocator.free(attached_bytes);
    var attached_parsed = try std.json.parseFromSlice(std.json.Value, testing.allocator, attached_bytes, .{});
    defer attached_parsed.deinit();
    try testing.expectEqualStrings(
        "No proxy accounts have been read yet. Use Refresh failover status in the … menu to read the failover order from the proxy.",
        attached_parsed.value.object.get("view").?.object.get("proxy_empty_text").?.string,
    );
}

test "C11 add-account flow projects core-owned dialog fields" {
    var model = shell.initialModel(.kst);
    model.add_account.open = true;
    var effects: shell.Effects = .{};

    const empty_bytes = try bridge.serialize(testing.allocator, 1, .{ .started = true }, &model, &effects);
    defer testing.allocator.free(empty_bytes);
    var empty = try std.json.parseFromSlice(std.json.Value, testing.allocator, empty_bytes, .{});
    defer empty.deinit();
    const empty_flow = empty.value.object.get("shell").?.object.get("add_account").?.object;
    try testing.expect(empty_flow.get("open").?.bool);
    try testing.expectEqualStrings("Add Codex account", empty_flow.get("title").?.string);
    try testing.expectEqualStrings(
        "Name this account before opening the browser to sign in.",
        empty_flow.get("explanation_text").?.string,
    );
    try testing.expectEqualStrings("", empty_flow.get("initial_label").?.string);
    try testing.expect(!empty_flow.get("confirm_enabled").?.bool);
    try testing.expectEqualStrings("Sign in…", empty_flow.get("confirm_label").?.string);
    try testing.expectEqualStrings("Cancel", empty_flow.get("cancel_label").?.string);
    try testing.expectEqualStrings("", empty_flow.get("progress_text").?.string);
    try testing.expectEqualStrings("", empty_flow.get("error_text").?.string);

    shell.copyInto(&model.add_account.label_buffer, &model.add_account.label_len, "Owner Work");
    const valid_bytes = try bridge.serialize(testing.allocator, 2, .{ .started = true }, &model, &effects);
    defer testing.allocator.free(valid_bytes);
    var valid = try std.json.parseFromSlice(std.json.Value, testing.allocator, valid_bytes, .{});
    defer valid.deinit();
    const valid_flow = valid.value.object.get("shell").?.object.get("add_account").?.object;
    try testing.expectEqualStrings("Owner Work", valid_flow.get("initial_label").?.string);
    try testing.expect(valid_flow.get("confirm_enabled").?.bool);

    model.add_account.in_flight = true;
    const busy_bytes = try bridge.serialize(testing.allocator, 3, .{ .started = true }, &model, &effects);
    defer testing.allocator.free(busy_bytes);
    var busy = try std.json.parseFromSlice(std.json.Value, testing.allocator, busy_bytes, .{});
    defer busy.deinit();
    const busy_flow = busy.value.object.get("shell").?.object.get("add_account").?.object;
    try testing.expect(!busy_flow.get("confirm_enabled").?.bool);
    try testing.expectEqualStrings("Add account in progress · Codex", busy_flow.get("progress_text").?.string);
}

test "P3 cm.bridge schema 1 exposes proxy service routing fields and intents" {
    const required_view_fields = [_][]const u8{
        "proxy_service_state",
        "proxy_service_detail_text",
        "proxy_service_can_install",
        "proxy_service_can_repair",
        "proxy_service_can_stop",
        "codex_routing_state",
        "proxy_cli_default_path",
        "proxy_node_default_path",
    };
    inline for (required_view_fields) |field| {
        try testing.expect(@hasField(ui.ViewState, field));
    }

    const IntentTag = std.meta.Tag(shell.Intent);
    const required_intents = [_][]const u8{
        "install_proxy_service",
        "repair_proxy_service",
        "stop_proxy_service",
        "enable_codex_routing",
        "disable_codex_routing",
    };
    for (required_intents) |name| {
        try testing.expect(std.meta.stringToEnum(IntentTag, name) != null);
    }
}

test "P6 bridge version text is grounded in the Zig package version" {
    const build_zon = try std.Io.Dir.cwd().readFileAlloc(testing.io, "build.zig.zon", testing.allocator, .limited(64 * 1024));
    defer testing.allocator.free(build_zon);
    try testing.expect(std.mem.indexOf(u8, build_zon, ".version = \"0.1.0\"") != null);
    try testing.expectEqualStrings("Version 0.1.0 (build 0.1.0)", ui.app_version_text);
}

fn expectedAccountWire(a: *const ui.AccountView, capabilities: ui.ServiceCapabilities, tray_summary_line: []const u8) bridge.AccountWire {
    return .{
        .account_id = a.account_id,
        .label = a.label,
        .provider_email = a.provider_email,
        .plan_label = a.plan_label,
        .provider = a.provider,
        .enabled = a.enabled,
        .auth_state = a.auth_state,
        .freshness = a.freshness,
        .snapshot_status = a.snapshot_status,
        .has_snapshot = a.has_snapshot,
        .snapshot_captured_at_unix_s = a.snapshot_captured_at_unix_s,
        .last_attempt_at_unix_s = a.last_attempt_at_unix_s,
        .last_success_at_unix_s = a.last_success_at_unix_s,
        .last_attempt_code = a.last_attempt_code,
        .reset_credit_count = a.reset_credit_count,
        .credit_detail_status = a.credit_detail_status,
        .credit_detail_count = a.credit_detail_count,
        .operation_in_flight = a.operation_in_flight,
        .queued = a.queued,
        .pending_reset_attempt = a.pending_reset_attempt,
        .unsent_reset_attempt = a.unsent_reset_attempt,
        .reset_proxy_clear = a.reset_proxy_clear,
        .proxy_mode = a.proxy_mode,
        .proxy_active = a.proxy_active,
        .proxy_can_switch = a.proxy_can_switch,
        .proxy_state = a.proxy_state,
        .proxy_in_flight = a.proxy_in_flight,
        .proxy_cooldown_until_unix_s = a.proxy_cooldown_until_unix_s,
        .windows = a.windows[0..a.window_count],
        .primary = a.primary,
        .tray_primary = a.tray_primary,
        .summary_text = a.summary_text,
        .freshness_text = a.freshness_text,
        .evidence_text = a.evidence_text,
        .tray_text = a.tray_text,
        .tray_account_text = a.tray_account_text,
        .tray_identity_text = a.tray_identity_text,
        .tray_detail_text = a.tray_detail_text,
        .tray_open_command = a.tray_open_command,
        .tray_usage_text = a.tray_usage_text,
        .tray_updated_text = a.tray_updated_text,
        .tray_failover_text = a.tray_failover_text,
        .tray_summary_line = tray_summary_line,
        .tray_can_refresh = a.canRefreshFromTray(capabilities),
        .tray_can_switch = a.canSwitchProxy(),
        .tray_is_active = a.proxy_mode and a.proxy_active,
        .tray_uses_proxy = a.proxy_mode,
        .needs_attention = a.needsAttention(),
        .reset_is_offerable = a.resetIsOfferable(),
    };
}

fn expectedShellWire(m: *const shell.Model) bridge.ShellWire {
    const r = &m.reset;
    return .{
        .settings_tab = m.settings_tab,
        .settings_tab_is_meaningful = false,
        .expanded = m.expanded,
        .row_menu = m.row_menu,
        .proxy_row_menu = m.proxy_row_menu,
        .toolbar_menu_open = m.toolbar_menu_open,
        .proxy_settings_expanded = m.proxy_settings_expanded,
        .claude_tray_window = m.claude_tray_window,
        .footer_text = m.footerText(),
        .claude_summary_weekly_label = "",
        .claude_summary_session_label = "",
        .starting_text = "Starting…",
        .quit_label = "Quit",
        .can_refresh = m.view.capabilities.refresh,
        .can_refresh_all = m.view.row_count != 0 and m.view.capabilities.refresh,
        .can_manage_accounts = m.view.capabilities.accounts,
        .proxy_busy = m.proxyBusy(),
        .proxy_can_refresh = m.proxyCanRefresh(),
        .proxy_can_sync = m.proxyCanSync(),
        .notice = .{ .kind = m.notice.kind, .text = m.notice.text() },
        .add_account = .{
            .open = m.add_account.open,
            .title = "Add Codex account",
            .explanation_text = "Name this account before opening the browser to sign in.",
            .initial_label = m.add_account.initialLabel(),
            .in_flight = m.add_account.in_flight,
            .confirm_enabled = m.add_account.confirmEnabled(),
            .confirm_label = "Sign in…",
            .cancel_label = "Cancel",
            .progress_text = if (m.add_account.in_flight) "Add account in progress · Codex" else "",
            .error_text = m.add_account.errorText(),
        },
        .reset = .{
            .open = r.isOpen(),
            .stage = r.stage,
            .reason = r.reason,
            .outcome = r.outcome,
            .settle = r.settle,
            .proxy_clear = r.proxy_clear,
            .row = r.row,
            .account_id = r.accountId(),
            .label = r.label(),
            .available_count = r.available_count,
            .usage_text = r.usageEvidence(),
            .reset_text = r.resetEvidence(),
            .blocked_text = r.blockedText(),
            .outcome_text = r.outcomeText(),
            .proxy_clear_text = r.proxyClearText(),
            .is_review = r.stage == .review,
            .is_armed = r.stage == .armed,
            .is_blocked = r.stage == .blocked,
            .is_dispatched = r.stage == .dispatched,
            .awaits_reconciliation = r.awaitsReconciliation(),
            .shows_proxy_clear = r.showsProxyClear(),
        },
        .remove = .{
            .open = m.remove.open,
            .row = m.remove.row,
            .account_id = m.remove.accountId(),
            .label = m.remove.label(),
            .uses_proxy = m.remove.uses_proxy,
            .pause_requested = m.remove.pause_requested,
            .can_finish = m.removeCanFinish(),
        },
        .rename = .{
            .open = m.rename.open,
            .row = m.rename.row,
            .account_id = m.rename.accountId(),
            .initial_label = m.rename.initialLabel(),
        },
        .failover_switch = .{
            .open = m.failover_switch.open,
            .row = m.failover_switch.row,
            .account_id = m.failover_switch.accountId(),
            .target_label = m.failover_switch.targetLabel(),
        },
        .clear_cooldown = .{
            .open = m.clear_cooldown.open,
            .row = m.clear_cooldown.row,
            .account_id = m.clear_cooldown.accountId(),
            .label = m.clear_cooldown.label(),
        },
    };
}

fn expectedInspectorWire(i: *const ui.Inspector, updated_ago_text: []const u8) bridge.InspectorWire {
    return .{
        .present = i.present,
        .index = i.index,
        .title = i.title,
        .freshness_line = i.freshness_line,
        .updated_ago_text = updated_ago_text,
        .attention = i.attention,
        .attention_text = i.attention_text,
        .busy = i.busy,
        .busy_label = i.busy_label,
        .needs_auth = i.needs_auth,
        .needs_keychain_repair = i.needs_keychain_repair,
        .no_usage_text = i.no_usage_text,
        .uses_proxy = i.uses_proxy,
        .failover_title = i.failover_title,
        .failover_state = i.failover_state,
        .failover_source_text = i.failover_source_text,
        .failover_action = i.failover_action,
        .failover_can_switch = i.failover_can_switch,
        .usage_source_text = i.usage_source_text,
        .token_value = i.token_value,
        .token_source_text = i.token_source_text,
        .has_credits = i.has_credits,
        .credit_value = i.credit_value,
        .can_reset = i.can_reset,
        .reset_label = i.reset_label,
        .credit_note = i.credit_note,
        .has_credit_note = i.has_credit_note,
        .credit_offer = i.credit_offer,
        .evidence_line = i.evidence_line,
        .plan_line = i.plan_line,
        .connection_line = i.connection_line,
    };
}

fn expectedViewWire(
    v: *const ui.ViewState,
    accounts: []const bridge.AccountWire,
    tray_items: []const ui.TrayItem,
    inspector_updated_ago_text: []const u8,
) bridge.ViewWire {
    return .{
        .now_unix_s = v.now_unix_s,
        .capabilities = v.capabilities,
        .tray_provider_headers = v.tray_provider_headers,
        .proxy_base_url = v.proxy_base_url,
        .proxy_cli_path = v.proxy_cli_path,
        .proxy_config_path = v.proxy_config_path,
        .proxy_node_path = v.proxy_node_path,
        .proxy_node_resolved = v.proxy_node_resolved,
        .proxy_reachability = v.proxy_reachability,
        .proxy_work = v.proxy_work,
        .proxy_sync_state = v.proxy_sync_state,
        .proxy_last_attempt_at_unix_s = v.proxy_last_attempt_at_unix_s,
        .proxy_last_attempt_result = v.proxy_last_attempt_result,
        .proxy_last_success_at_unix_s = v.proxy_last_success_at_unix_s,
        .proxy_success_revision = v.proxy_success_revision,
        .proxy_config_path_matches = v.proxy_config_path_matches,
        .proxy_in_flight = v.proxy_in_flight,
        .proxy_accounts = v.proxy_accounts[0..v.proxy_account_count],
        .proxy_rows = v.proxy_rows[0..v.proxy_row_count],
        .proxy_summary_text = v.proxy_summary_text,
        .proxy_detail_text = v.proxy_detail_text,
        .proxy_tray_text = v.proxy_tray_text,
        .proxy_empty_text = if (v.capabilities.proxy_control)
            "No proxy accounts have been read yet. Use Refresh failover status in the … menu to read the failover order from the proxy."
        else
            "Proxy control is not attached.",
        .proxy_service_state = v.proxy_service_state,
        .proxy_service_detail_text = v.proxy_service_detail_text,
        .proxy_service_can_install = v.proxy_service_can_install,
        .proxy_service_can_repair = v.proxy_service_can_repair,
        .proxy_service_can_stop = v.proxy_service_can_stop,
        .codex_routing_state = v.codex_routing_state,
        .proxy_cli_default_path = v.proxy_cli_default_path,
        .proxy_node_default_path = v.proxy_node_default_path,
        .rows = accounts,
        .usage_rows = v.usage_rows[0..v.usage_count],
        .inspector = expectedInspectorWire(&v.inspector, inspector_updated_ago_text),
        .account_row_count = v.account_row_count,
        .claude_row_count = v.claude_row_count,
        .codex_exhausted_count = v.codex_exhausted_count,
        .account_rows = v.account_rows[0..v.account_row_count],
        .unified_order_source = v.unified_order_source,
        .unified_rows = v.unified_rows[0..v.unified_row_count],
        .settings = v.settings,
        .claude_group_title = v.claude_group_title,
        .codex_group_title = v.codex_group_title,
        .claude_group_summary = v.claude_group_summary,
        .codex_group_summary = v.codex_group_summary,
        .onboarding_visible = v.onboarding_visible,
        .onboarding_steps = v.onboarding_steps,
        .onboarding_next_action = v.onboarding_next_action,
        .toolbar_status_text = v.toolbar_status_text,
        .busy_suffix_text = if (v.busy_count != 0 or v.proxy_work != .idle) " · refreshing" else "",
        .header_fresh_text = v.header_fresh_text,
        .header_failed_text = v.header_failed_text,
        .header_has_failures = v.header_has_failures,
        .proxy_pill_text = v.proxy_pill_text,
        .proxy_pill_ok = v.proxy_pill_ok,
        .proxy_pill_warn = v.proxy_pill_warn,
        .proxy_pill_bad = v.proxy_pill_bad,
        .proxy_active_label = v.proxy_active_label,
        .proxy_cooling_count = v.proxy_cooling_count,
        .proxy_mapped_count = v.proxy_mapped_count,
        .proxy_settings_summary_text = v.proxy_settings_summary_text,
        .proxy_node_hint_text = v.proxy_node_hint_text,
        .proxy_banner_text = v.proxy_banner_text,
        .claude_count = v.claude_count,
        .codex_count = v.codex_count,
        .reauth_count = v.reauth_count,
        .error_count = v.error_count,
        .stale_count = v.stale_count,
        .busy_count = v.busy_count,
        .snapshot_count = v.snapshot_count,
        .newest_success_at_unix_s = v.newest_success_at_unix_s,
        .headline_text = v.headline_text,
        .summary_text = v.summary_text,
        .tray_summary_text = v.tray_summary_text,
        .service_text = v.service_text,
        .tray = .{
            .title = "",
            .items = tray_items,
            .refresh_usage_label = "Refresh Usage",
            .open_in_settings_label = "Open in Settings…",
            .help_text = "CodexMulti — saved usage and CLI accounts",
        },
    };
}

fn expectedTraySummaryLine(a: *const ui.AccountView, buffer: []u8) []const u8 {
    const plan = if (a.plan_label.len != 0) a.plan_label else "Account";
    return std.fmt.bufPrint(buffer, "{s} · {s}", .{ plan, ui.providerName(a.provider) }) catch "";
}

fn expectedUpdatedAgoText(v: *const ui.ViewState, buffer: []u8) []const u8 {
    if (!v.inspector.present) return "";
    const row = v.rowAt(v.inspector.index) orelse return "";
    const at = row.last_success_at_unix_s orelse return ui.freshnessPhrase(row.freshness);
    if (row.freshness == .as_of) return ui.agoPhrase(buffer, v.now_unix_s, at);
    var ago_buffer: [ui.max_line_bytes]u8 = undefined;
    return std.fmt.bufPrint(buffer, "{s} · {s}", .{
        ui.agoPhrase(&ago_buffer, v.now_unix_s, at),
        ui.freshnessPhrase(row.freshness),
    }) catch "";
}

fn expectIndependentWireProjection(model: *shell.Model) !void {
    var effects: shell.Effects = .{};
    const bytes = try bridge.serialize(testing.allocator, 91, .{}, model, &effects);
    defer testing.allocator.free(bytes);
    var parsed = try std.json.parseFromSlice(bridge.ProjectionWire, testing.allocator, bytes, .{ .allocate = .alloc_always });
    defer parsed.deinit();

    var accounts: [ui.max_rows]bridge.AccountWire = undefined;
    var tray_summary_buffers: [ui.max_rows][ui.max_line_bytes]u8 = undefined;
    for (model.view.rows[0..model.view.row_count], 0..) |*account, index| {
        accounts[index] = expectedAccountWire(
            account,
            model.view.capabilities,
            expectedTraySummaryLine(account, &tray_summary_buffers[index]),
        );
        try testing.expectEqualDeep(accounts[index], parsed.value.view.rows[index]);
    }
    var tray_items: [ui.max_tray_items]ui.TrayItem = @splat(.{});
    const tray_count = ui.buildTray(&model.view, &tray_items);
    var inspector_updated_ago_buffer: [ui.max_line_bytes]u8 = undefined;
    try testing.expectEqualDeep(
        expectedViewWire(
            &model.view,
            accounts[0..model.view.row_count],
            tray_items[0..tray_count],
            expectedUpdatedAgoText(&model.view, &inspector_updated_ago_buffer),
        ),
        parsed.value.view,
    );
    try testing.expectEqualDeep(expectedShellWire(model), parsed.value.shell);
}

fn sentinelBit(code: usize, plane: usize) bool {
    return (code & (@as(usize, 1) << @intCast(plane))) != 0;
}

const IntentCase = struct { name: []const u8, json: []const u8 };
const all_intents = [_]IntentCase{
    .{ .name = "set_appearance", .json = "{\"intent\":\"set_appearance\",\"value\":\"dark\"}" },
    .{ .name = "set_language", .json = "{\"intent\":\"set_language\",\"value\":\"ko\",\"system\":\"en\"}" },
    .{ .name = "set_codex_usage_window", .json = "{\"intent\":\"set_codex_usage_window\",\"value\":\"weekly\"}" },
    .{ .name = "set_codex_show_model_limits", .json = "{\"intent\":\"set_codex_show_model_limits\",\"on\":true}" },
    .{ .name = "set_launch_at_login", .json = "{\"intent\":\"set_launch_at_login\",\"on\":true}" },
    .{ .name = "report_launch_at_login_registration_failure", .json = "{\"intent\":\"report_launch_at_login_registration_failure\",\"failed\":true}" },
    .{ .name = "set_auto_refresh", .json = "{\"intent\":\"set_auto_refresh\",\"minutes\":15}" },
    .{ .name = "open_details", .json = "{\"intent\":\"open_details\"}" },
    .{ .name = "quit_app", .json = "{\"intent\":\"quit_app\"}" },
    .{ .name = "open_account", .json = "{\"intent\":\"open_account\",\"account_id\":\"acct-codex-one\"}" },
    .{ .name = "tab_accounts", .json = "{\"intent\":\"tab_accounts\"}" },
    .{ .name = "tab_failover", .json = "{\"intent\":\"tab_failover\"}" },
    .{ .name = "open_toolbar_menu", .json = "{\"intent\":\"open_toolbar_menu\"}" },
    .{ .name = "close_toolbar_menu", .json = "{\"intent\":\"close_toolbar_menu\"}" },
    .{ .name = "toggle_account", .json = "{\"intent\":\"toggle_account\",\"row\":0}" },
    .{ .name = "open_row_menu", .json = "{\"intent\":\"open_row_menu\",\"row\":0}" },
    .{ .name = "close_row_menu", .json = "{\"intent\":\"close_row_menu\"}" },
    .{ .name = "open_proxy_row_menu", .json = "{\"intent\":\"open_proxy_row_menu\",\"row\":0}" },
    .{ .name = "close_proxy_row_menu", .json = "{\"intent\":\"close_proxy_row_menu\"}" },
    .{ .name = "toggle_proxy_settings", .json = "{\"intent\":\"toggle_proxy_settings\"}" },
    .{ .name = "copy_diagnostics", .json = "{\"intent\":\"copy_diagnostics\",\"row\":0}" },
    .{ .name = "diagnostics_copied", .json = "{\"intent\":\"diagnostics_copied\",\"ok\":true}" },
    .{ .name = "claude_tray_weekly", .json = "{\"intent\":\"claude_tray_weekly\"}" },
    .{ .name = "claude_tray_session", .json = "{\"intent\":\"claude_tray_session\"}" },
    .{ .name = "dismiss_notice", .json = "{\"intent\":\"dismiss_notice\"}" },
    .{ .name = "refresh_proxy_status", .json = "{\"intent\":\"refresh_proxy_status\"}" },
    .{ .name = "sync_proxy_config", .json = "{\"intent\":\"sync_proxy_config\"}" },
    .{ .name = "pause_proxy_account", .json = "{\"intent\":\"pause_proxy_account\",\"row\":0}" },
    .{ .name = "resume_proxy_account", .json = "{\"intent\":\"resume_proxy_account\",\"row\":0}" },
    .{ .name = "begin_proxy_switch", .json = "{\"intent\":\"begin_proxy_switch\",\"row\":0}" },
    .{ .name = "begin_clear_cooldown", .json = "{\"intent\":\"begin_clear_cooldown\",\"row\":0}" },
    .{ .name = "confirm_clear_cooldown", .json = "{\"intent\":\"confirm_clear_cooldown\"}" },
    .{ .name = "cancel_clear_cooldown", .json = "{\"intent\":\"cancel_clear_cooldown\"}" },
    .{ .name = "save_proxy_settings", .json = "{\"intent\":\"save_proxy_settings\",\"base_url\":\"http://127.0.0.1:8787\",\"cli_path\":\"/tmp/proxy\",\"config_path\":\"/tmp/config\",\"node_path\":\"\"}" },
    .{ .name = "refresh_all", .json = "{\"intent\":\"refresh_all\"}" },
    .{ .name = "refresh_account", .json = "{\"intent\":\"refresh_account\",\"row\":0}" },
    .{ .name = "refresh_account_id", .json = "{\"intent\":\"refresh_account_id\",\"account_id\":\"acct-codex-one\"}" },
    .{ .name = "move_account", .json = "{\"intent\":\"move_account\",\"account_id\":\"acct-codex-one\",\"target_account_id\":\"acct-codex-two\"}" },
    .{ .name = "begin_failover_switch", .json = "{\"intent\":\"begin_failover_switch\",\"row\":0}" },
    .{ .name = "begin_failover_switch_id", .json = "{\"intent\":\"begin_failover_switch_id\",\"account_id\":\"acct-codex-one\"}" },
    .{ .name = "confirm_failover_switch", .json = "{\"intent\":\"confirm_failover_switch\"}" },
    .{ .name = "cancel_failover_switch", .json = "{\"intent\":\"cancel_failover_switch\"}" },
    .{ .name = "pause_failover_account", .json = "{\"intent\":\"pause_failover_account\",\"row\":0}" },
    .{ .name = "begin_clear_cooldown_account", .json = "{\"intent\":\"begin_clear_cooldown_account\",\"row\":0}" },
    .{ .name = "reauthenticate", .json = "{\"intent\":\"reauthenticate\",\"row\":0}" },
    .{ .name = "add_claude_account", .json = "{\"intent\":\"add_claude_account\"}" },
    .{ .name = "add_codex_account", .json = "{\"intent\":\"add_codex_account\"}" },
    .{ .name = "begin_add_account", .json = "{\"intent\":\"begin_add_account\"}" },
    .{ .name = "commit_add_account", .json = "{\"intent\":\"commit_add_account\",\"label\":\"  Owner Work  \"}" },
    .{ .name = "cancel_add_account", .json = "{\"intent\":\"cancel_add_account\"}" },
    .{ .name = "begin_rename", .json = "{\"intent\":\"begin_rename\",\"row\":0}" },
    .{ .name = "commit_rename", .json = "{\"intent\":\"commit_rename\",\"label\":\"Renamed account\"}" },
    .{ .name = "cancel_rename", .json = "{\"intent\":\"cancel_rename\"}" },
    .{ .name = "begin_remove", .json = "{\"intent\":\"begin_remove\",\"row\":0}" },
    .{ .name = "confirm_remove", .json = "{\"intent\":\"confirm_remove\"}" },
    .{ .name = "finish_mapped_remove", .json = "{\"intent\":\"finish_mapped_remove\"}" },
    .{ .name = "cancel_remove", .json = "{\"intent\":\"cancel_remove\"}" },
    .{ .name = "begin_reset", .json = "{\"intent\":\"begin_reset\",\"row\":0}" },
    .{ .name = "acknowledge_reset", .json = "{\"intent\":\"acknowledge_reset\"}" },
    .{ .name = "confirm_reset", .json = "{\"intent\":\"confirm_reset\"}" },
    .{ .name = "retry_reset", .json = "{\"intent\":\"retry_reset\"}" },
    .{ .name = "cancel_reset", .json = "{\"intent\":\"cancel_reset\"}" },
    .{ .name = "install_proxy_service", .json = "{\"intent\":\"install_proxy_service\"}" },
    .{ .name = "repair_proxy_service", .json = "{\"intent\":\"repair_proxy_service\"}" },
    .{ .name = "stop_proxy_service", .json = "{\"intent\":\"stop_proxy_service\"}" },
    .{ .name = "set_proxy_enabled", .json = "{\"intent\":\"set_proxy_enabled\",\"on\":true}" },
    .{ .name = "enable_codex_routing", .json = "{\"intent\":\"enable_codex_routing\",\"replace_conflicting\":true}" },
    .{ .name = "disable_codex_routing", .json = "{\"intent\":\"disable_codex_routing\"}" },
};

test "every intent table name parses with strict typed payloads" {
    try testing.expectEqual(@typeInfo(shell.Intent).@"union".fields.len, all_intents.len);
    for (all_intents) |case| {
        var parsed = switch (bridge.parseIntent(testing.allocator, case.json)) {
            .accepted => |value| value,
            .rejected => |code| {
                std.debug.print("intent {s} rejected with {d}\n", .{ case.name, code });
                return error.TestUnexpectedResult;
            },
        };
        defer parsed.deinit();
        try testing.expectEqualStrings(case.name, @tagName(parsed.intent));
        if (std.mem.eql(u8, case.name, "move_account")) switch (parsed.intent) {
            .move_account => |move| {
                try testing.expectEqualStrings("acct-codex-one", move.account_id);
                try testing.expectEqualStrings("acct-codex-two", move.target_account_id);
            },
            else => return error.TestUnexpectedResult,
        };
    }
}

test "move_account accepts account ids and rejects legacy row positions" {
    var decoded = switch (bridge.parseIntent(
        testing.allocator,
        "{\"intent\":\"move_account\",\"account_id\":\"acct-codex-one\",\"target_account_id\":\"acct-codex-two\"}",
    )) {
        .accepted => |value| value,
        .rejected => return error.TestUnexpectedResult,
    };
    defer decoded.deinit();
    try testing.expectEqualStrings("move_account", @tagName(decoded.intent));

    switch (bridge.parseIntent(testing.allocator, "{\"intent\":\"move_account\",\"row\":0,\"to\":1}")) {
        .rejected => |code| try testing.expectEqual(bridge.CM_ERR_PAYLOAD, code),
        .accepted => |value| {
            var legacy = value;
            legacy.deinit();
            return error.TestUnexpectedResult;
        },
    }
}

test "malformed oversized schema intent and payload errors are distinct" {
    const cases = [_]struct { json: []const u8, code: i32 }{
        .{ .json = "[", .code = bridge.CM_ERR_JSON },
        .{ .json = "[]", .code = bridge.CM_ERR_JSON },
        .{ .json = "{\"schema\":2,\"intent\":\"refresh_all\"}", .code = bridge.CM_ERR_SCHEMA },
        .{ .json = "{\"schema\":\"1\",\"intent\":\"refresh_all\"}", .code = bridge.CM_ERR_SCHEMA },
        .{ .json = "{\"schema\":1}", .code = bridge.CM_ERR_INTENT },
        .{ .json = "{\"intent\":\"unknown\"}", .code = bridge.CM_ERR_INTENT },
        .{ .json = "{\"intent\":\"toggle_account\",\"row\":16}", .code = bridge.CM_ERR_PAYLOAD },
        .{ .json = "{\"intent\":\"toggle_account\",\"row\":0.0}", .code = bridge.CM_ERR_PAYLOAD },
        .{ .json = "{\"intent\":\"move_account\",\"account_id\":\"acct-codex-one\"}", .code = bridge.CM_ERR_PAYLOAD },
        .{ .json = "{\"intent\":\"move_account\",\"target_account_id\":\"acct-codex-two\"}", .code = bridge.CM_ERR_PAYLOAD },
        .{ .json = "{\"intent\":\"move_account\",\"account_id\":\"bad/id\",\"target_account_id\":\"acct-codex-two\"}", .code = bridge.CM_ERR_PAYLOAD },
        .{ .json = "{\"intent\":\"diagnostics_copied\",\"ok\":1}", .code = bridge.CM_ERR_PAYLOAD },
        .{ .json = "{\"intent\":\"set_proxy_enabled\",\"on\":1}", .code = bridge.CM_ERR_PAYLOAD },
        .{ .json = "{\"intent\":\"enable_codex_routing\",\"replace_conflicting\":1}", .code = bridge.CM_ERR_PAYLOAD },
        .{ .json = "{\"intent\":\"set_appearance\",\"value\":\"sepia\"}", .code = bridge.CM_ERR_PAYLOAD },
        .{ .json = "{\"intent\":\"set_codex_usage_window\",\"value\":\"daily\"}", .code = bridge.CM_ERR_PAYLOAD },
        .{ .json = "{\"intent\":\"set_codex_show_model_limits\",\"on\":1}", .code = bridge.CM_ERR_PAYLOAD },
        .{ .json = "{\"intent\":\"set_launch_at_login\",\"on\":1}", .code = bridge.CM_ERR_PAYLOAD },
        .{ .json = "{\"intent\":\"report_launch_at_login_registration_failure\",\"failed\":1}", .code = bridge.CM_ERR_PAYLOAD },
        .{ .json = "{\"intent\":\"set_auto_refresh\",\"minutes\":17}", .code = bridge.CM_ERR_PAYLOAD },
        .{ .json = "{\"intent\":\"set_auto_refresh\",\"minutes\":15.0}", .code = bridge.CM_ERR_PAYLOAD },
        .{ .json = "{\"intent\":\"open_account\",\"account_id\":\"bad/id\"}", .code = bridge.CM_ERR_PAYLOAD },
        .{ .json = "{\"intent\":\"commit_rename\",\"label\":\" leading\"}", .code = bridge.CM_ERR_PAYLOAD },
        .{ .json = "{\"intent\":\"commit_add_account\",\"label\":\"   \"}", .code = bridge.CM_ERR_PAYLOAD },
    };
    for (cases) |case| switch (bridge.parseIntent(testing.allocator, case.json)) {
        .rejected => |code| try testing.expectEqual(case.code, code),
        .accepted => |value| {
            var parsed = value;
            parsed.deinit();
            return error.TestUnexpectedResult;
        },
    };
    var oversized: [shell.max_intent_json_bytes + 1]u8 = @splat(' ');
    switch (bridge.parseIntent(testing.allocator, &oversized)) {
        .rejected => |code| try testing.expectEqual(bridge.CM_ERR_JSON, code),
        .accepted => |value| {
            var parsed = value;
            parsed.deinit();
            return error.TestUnexpectedResult;
        },
    }
}

test "allocation failure rejects without an accepted intent" {
    switch (bridge.parseIntent(testing.failing_allocator, "{\"intent\":\"refresh_all\"}")) {
        .rejected => |code| try testing.expectEqual(bridge.CM_ERR_INTERNAL, code),
        .accepted => |value| {
            var parsed = value;
            parsed.deinit();
            return error.TestUnexpectedResult;
        },
    }
}

test "real cmcore ABI accepts and rejects fixtures with stable generation and one-shot effects" {
    var temp = testing.tmpDir(.{});
    defer temp.cleanup();
    var home_buffer: [std.fs.max_path_bytes]u8 = undefined;
    const home_len = try temp.dir.realPath(testing.io, &home_buffer);
    const home = try testing.allocator.dupeZ(u8, home_buffer[0..home_len]);
    defer testing.allocator.free(home);
    const old_home = try SavedEnv.capture("HOME");
    defer old_home.restore();
    const old_path = try SavedEnv.capture("PATH");
    defer old_path.restore();
    try testing.expectEqual(@as(c_int, 0), setenv("HOME", home.ptr, 1));
    try testing.expectEqual(@as(c_int, 0), setenv("PATH", "/usr/bin:/bin", 1));

    try testing.expectEqual(@as(u32, 1), cmcore.cm_service_version());
    try testing.expectEqualStrings("CODEXMULTI_CORE_SRC_SHA256=TEST-BRIDGE", std.mem.span(cmcore.cm_service_provenance()));
    cmcore.cm_service_destroy(null);
    const service = cmcore.cm_service_create() orelse return error.CreateFailed;
    defer cmcore.cm_service_destroy(service);

    const first_pointer = cmcore.cm_service_project(service);
    const first_bytes = std.mem.span(first_pointer);
    try testing.expectEqual(@as(u64, 0), try projectedGeneration(first_bytes));
    try testing.expect(std.mem.indexOf(u8, first_bytes, "\"runtime\":{\"started\":false") != null);
    try testing.expectEqual(@as(u8, 0), first_pointer[first_bytes.len]);

    const intents_bytes = try std.Io.Dir.cwd().readFileAlloc(testing.io, "fixtures/bridge/intents-all.json", testing.allocator, .limited(64 * 1024));
    defer testing.allocator.free(intents_bytes);
    var intents = try std.json.parseFromSlice(std.json.Value, testing.allocator, intents_bytes, .{});
    defer intents.deinit();
    for (intents.value.array.items) |intent_value| {
        const encoded = try std.json.Stringify.valueAlloc(testing.allocator, intent_value, .{});
        defer testing.allocator.free(encoded);
        const terminated = try testing.allocator.dupeZ(u8, encoded);
        defer testing.allocator.free(terminated);
        try testing.expectEqual(bridge.CM_OK, cmcore.cm_service_submit(service, terminated.ptr));
    }

    const accepted_pointer = cmcore.cm_service_project(service);
    const accepted_bytes = std.mem.span(accepted_pointer);
    const accepted_generation: u64 = @intCast(intents.value.array.items.len);
    try testing.expectEqual(accepted_generation, try projectedGeneration(accepted_bytes));
    const show_at = std.mem.indexOf(u8, accepted_bytes, "\"kind\":\"show_settings\"") orelse return error.MissingEffect;
    const quit_at = std.mem.indexOf(u8, accepted_bytes, "\"kind\":\"quit\"") orelse return error.MissingEffect;
    try testing.expect(show_at < quit_at);
    try testing.expectEqual(@as(u8, 0), accepted_pointer[accepted_bytes.len]);
    const drained_bytes = std.mem.span(cmcore.cm_service_project(service));
    try testing.expect(std.mem.indexOf(u8, drained_bytes, "\"effects\":[]") != null);
    try testing.expectEqual(accepted_generation, try projectedGeneration(drained_bytes));

    cmcore.cm_service_pump(service, 1_784_948_400);
    const pumped_bytes = std.mem.span(cmcore.cm_service_project(service));
    try testing.expectEqual(accepted_generation + 1, try projectedGeneration(pumped_bytes));
    const stable_pumped_bytes = try testing.allocator.dupe(u8, pumped_bytes);
    defer testing.allocator.free(stable_pumped_bytes);
    cmcore.cm_service_pump(service, 1_784_948_401);
    const idle_pumped_bytes = std.mem.span(cmcore.cm_service_project(service));
    try testing.expectEqualSlices(u8, stable_pumped_bytes, idle_pumped_bytes);

    const rejected_bytes = try std.Io.Dir.cwd().readFileAlloc(testing.io, "fixtures/bridge/intents-rejected.json", testing.allocator, .limited(64 * 1024));
    defer testing.allocator.free(rejected_bytes);
    var rejected = try std.json.parseFromSlice(std.json.Value, testing.allocator, rejected_bytes, .{});
    defer rejected.deinit();
    var rejected_count: usize = 0;
    for (rejected.value.array.items) |case_value| {
        const case = case_value.object;
        const name = case.get("case").?.string;
        const expected: i32 = @intCast(case.get("expected").?.integer);
        const before = try projectedGeneration(std.mem.span(cmcore.cm_service_project(service)));
        const actual = if (std.mem.eql(u8, name, "allocation_failure_injection"))
            cmcore.submitWithAllocator(service, case.get("input").?.string, testing.failing_allocator)
        else if (case.get("input").? == .null)
            cmcore.cm_service_submit(null, null)
        else blk: {
            const input = try testing.allocator.dupeZ(u8, case.get("input").?.string);
            defer testing.allocator.free(input);
            break :blk cmcore.cm_service_submit(service, input.ptr);
        };
        try testing.expectEqual(expected, actual);
        const after = try projectedGeneration(std.mem.span(cmcore.cm_service_project(service)));
        try testing.expectEqual(before, after);
        rejected_count += 1;
    }
    try testing.expectEqual(rejected.value.array.items.len, rejected_count);
    try testing.expectEqual(bridge.CM_ERR_JSON, cmcore.cm_service_submit(service, null));

    try testing.expectEqual(bridge.CM_OK, cmcore.submitWithAllocator(service, "{\"intent\":\"open_details\"}", testing.allocator));
    const fallback_pointer = cmcore.projectWithAllocator(service, testing.failing_allocator);
    const fallback_bytes = std.mem.span(fallback_pointer);
    var fallback = try std.json.parseFromSlice(std.json.Value, testing.allocator, fallback_bytes, .{});
    defer fallback.deinit();
    try testing.expectEqual(@as(i64, @intCast(service.generation)), fallback.value.object.get("generation").?.integer);
    try testing.expectEqualStrings("out_of_memory", fallback.value.object.get("serialize_error").?.string);
    try testing.expectEqual(@as(usize, 1), service.effects.len);
    try testing.expectEqual(@as(u8, 0), fallback_pointer[fallback_bytes.len]);
    const recovered = std.mem.span(cmcore.cm_service_project(service));
    try testing.expect(std.mem.indexOf(u8, recovered, "\"kind\":\"show_settings\"") != null);
    try testing.expectEqual(@as(usize, 0), service.effects.len);
}

test "projection starts with schema and contains exact top-level sections" {
    var model = shell.initialModel(.kst);
    model.now_unix_s = 1_784_948_400;
    shell.reproject(&model);
    var effects: shell.Effects = .{};
    const bytes = try bridge.serialize(testing.allocator, 7, .{}, &model, &effects);
    defer testing.allocator.free(bytes);
    try testing.expect(std.mem.startsWith(u8, bytes, "{\"schema\":1,\"generation\":7,"));
    var parsed = try std.json.parseFromSlice(std.json.Value, testing.allocator, bytes, .{});
    defer parsed.deinit();
    const object = parsed.value.object;
    try testing.expect(object.get("runtime") != null);
    try testing.expect(object.get("effects") != null);
    try testing.expect(object.get("shell") != null);
    try testing.expect(object.get("view") != null);
}

test "projection emits counted arrays at their logical length" {
    var model = shell.initialModel(.kst);
    shell.reproject(&model);
    var effects: shell.Effects = .{};
    const bytes = try bridge.serialize(testing.allocator, 0, .{}, &model, &effects);
    defer testing.allocator.free(bytes);
    var parsed = try std.json.parseFromSlice(std.json.Value, testing.allocator, bytes, .{});
    defer parsed.deinit();
    const view = parsed.value.object.get("view").?.object;
    try testing.expectEqual(@as(usize, 0), view.get("rows").?.array.items.len);
    try testing.expectEqual(@as(usize, 0), view.get("proxy_rows").?.array.items.len);
    try testing.expectEqual(@as(usize, 0), view.get("usage_rows").?.array.items.len);
}

test "non-empty projection deep round-trips through the named wire DTO tree" {
    var model = shell.initialModel(.kst);
    model.now_unix_s = 1_784_948_400;
    model.view.begin(model.now_unix_s, .{ .connected = true, .refresh = true, .accounts = true, .reset = true, .proxy_control = true }, .kst);
    const row = try model.view.pushAccount(.{
        .account_id = "acct-deep",
        .label = "Deep account",
        .provider = .codex,
        .provider_email = "safe@example.invalid",
        .plan_label = "Pro",
        .auth_state = .connected,
        .freshness = .saved_snapshot,
        .has_snapshot = true,
        .snapshot_status = .fresh,
        .snapshot_captured_at_unix_s = 1_784_948_001,
        .last_attempt_at_unix_s = 1_784_948_002,
        .last_success_at_unix_s = 1_784_948_003,
        .reset_credit_count = 2,
    });
    try model.view.pushWindow(row, .{ .label = "Weekly", .kind = .weekly, .used_percent = 73, .reset_at_unix_s = 1_785_207_600, .duration_minutes = 10_080 });
    const proxy_accounts = [_]ui.ProxyAccountFact{.{
        .app_id = "acct-deep",
        .storage_key = "safe-key",
        .proxy_name = "deep",
        .label = "Deep account",
        .state = .ready,
        .active = true,
        .mapped = true,
    }};
    model.view.applyProxy(.{
        .base_url = "http://127.0.0.1:8787",
        .cli_path = "/opt/safe/proxy",
        .config_path = "/tmp/safe.json",
        .node_resolved = "/usr/bin/node",
        .reachability = .reachable,
        .sync_state = .synced,
        .last_attempt_at_unix_s = 1_784_948_355,
        .last_attempt_result = .ok,
        .last_success_at_unix_s = 1_784_948_340,
        .success_revision = 4,
        .config_path_matches = true,
        .accounts = &proxy_accounts,
    });
    model.view.finish(.{ .selected = 0, .row_menu = 0, .proxy_row_menu = 0, .claude_tray_window = .session });
    model.settings_tab = .failover;
    model.expanded = 0;
    model.row_menu = 0;
    model.proxy_row_menu = 0;
    model.toolbar_menu_open = true;
    model.proxy_settings_expanded = true;
    model.claude_tray_window = .session;
    model.notice.set(.blocked, "Safe blocked notice", .{});
    model.reset.stage = .dispatched;
    model.reset.reason = .none;
    model.reset.outcome = .accepted_pending;
    model.reset.settle = .seen;
    model.reset.proxy_clear = .pending;
    model.reset.row = 0;
    model.reset.available_count = 2;
    shell.copyInto(&model.reset.account_id_buffer, &model.reset.account_id_len, "acct-deep");
    shell.copyInto(&model.reset.label_buffer, &model.reset.label_len, "Deep account");
    shell.copyInto(&model.reset.evidence_buffer, &model.reset.evidence_len, "73% used");
    shell.copyInto(&model.reset.reset_buffer, &model.reset.reset_len, "next week");
    model.remove = .{ .open = true, .row = 0, .uses_proxy = true, .pause_requested = true, .status_revision_at_pause = 3 };
    shell.copyInto(&model.remove.account_id_buffer, &model.remove.account_id_len, "acct-deep");
    shell.copyInto(&model.remove.label_buffer, &model.remove.label_len, "Deep account");
    model.rename = .{ .open = true, .row = 0 };
    shell.copyInto(&model.rename.account_id_buffer, &model.rename.account_id_len, "acct-deep");
    shell.copyInto(&model.rename.initial_label_buffer, &model.rename.initial_label_len, "Deep account");
    model.failover_switch = .{ .open = true, .row = 0 };
    shell.copyInto(&model.failover_switch.account_id_buffer, &model.failover_switch.account_id_len, "acct-deep");
    shell.copyInto(&model.failover_switch.target_label_buffer, &model.failover_switch.target_label_len, "Deep account");
    model.clear_cooldown = .{ .open = true, .row = 0 };
    shell.copyInto(&model.clear_cooldown.account_id_buffer, &model.clear_cooldown.account_id_len, "acct-deep");
    shell.copyInto(&model.clear_cooldown.label_buffer, &model.clear_cooldown.label_len, "Deep account");

    var effects: shell.Effects = .{};
    effects.clipboard("safe diagnostics");
    const bytes = try bridge.serialize(testing.allocator, 77, .{ .started = true, .codex_cli_version_exact = true }, &model, &effects);
    defer testing.allocator.free(bytes);
    var parsed = try std.json.parseFromSlice(bridge.ProjectionWire, testing.allocator, bytes, .{ .allocate = .alloc_always });
    defer parsed.deinit();
    var account_wires: [ui.max_rows]bridge.AccountWire = undefined;
    var tray_summary_buffers: [ui.max_rows][ui.max_line_bytes]u8 = undefined;
    for (model.view.rows[0..model.view.row_count], 0..) |*account, index| {
        account_wires[index] = expectedAccountWire(
            account,
            model.view.capabilities,
            expectedTraySummaryLine(account, &tray_summary_buffers[index]),
        );
    }
    var tray_items: [ui.max_tray_items]ui.TrayItem = @splat(.{});
    const tray_count = ui.buildTray(&model.view, &tray_items);
    var inspector_updated_ago_buffer: [ui.max_line_bytes]u8 = undefined;
    const expected_view = expectedViewWire(
        &model.view,
        account_wires[0..model.view.row_count],
        tray_items[0..tray_count],
        expectedUpdatedAgoText(&model.view, &inspector_updated_ago_buffer),
    );
    const expected_shell = expectedShellWire(&model);
    try testing.expectEqual(@as(u64, 77), parsed.value.generation);
    try testing.expectEqualDeep(account_wires[0], parsed.value.view.rows[0]);
    try testing.expectEqualDeep(expected_view, parsed.value.view);
    try testing.expectEqualDeep(expected_shell, parsed.value.shell);
    try testing.expectEqualStrings("safe diagnostics", parsed.value.effects[0].clipboard);
    const round_trip = try std.json.Stringify.valueAlloc(testing.allocator, parsed.value, .{ .emit_null_optional_fields = true });
    defer testing.allocator.free(round_trip);
    try testing.expectEqualStrings(bytes, round_trip);
}

test "source-to-wire sibling fields use distinguishable sentinels and complementary booleans" {
    var model = shell.initialModel(.kst);
    model.view.begin(9_001, .{ .connected = true, .refresh = true, .accounts = true, .reset = true, .proxy_control = true }, .kst);
    const row = try model.view.pushAccount(.{
        .account_id = "account-id-input",
        .label = "account-label-input",
        .provider_email = "account-email-input",
        .plan_label = "account-plan-input",
        .provider = .codex,
        .auth_state = .connected,
        .freshness = .saved_snapshot,
        .snapshot_status = .partial,
        .has_snapshot = true,
        .snapshot_captured_at_unix_s = 1_001,
        .last_attempt_at_unix_s = 1_002,
        .last_success_at_unix_s = 1_003,
        .last_attempt_code = "account-attempt-code-input",
        .reset_credit_count = 31,
        .credit_detail_status = .detailed,
    });
    try model.view.pushWindow(row, .{ .label = "window-primary", .kind = .weekly, .used_percent = 61, .reset_at_unix_s = 2_001 });
    try model.view.pushWindow(row, .{ .label = "window-tray", .kind = .session, .used_percent = 37, .reset_at_unix_s = 2_002 });
    const proxy_accounts = [_]ui.ProxyAccountFact{.{
        .app_id = "account-id-input",
        .storage_key = "proxy-storage-input",
        .proxy_name = "proxy-name-input",
        .label = "proxy-label-input",
        .state = .ready,
        .active = true,
        .mapped = true,
    }};
    model.view.applyProxy(.{
        .base_url = "proxy-base-input",
        .cli_path = "proxy-cli-input",
        .config_path = "proxy-config-input",
        .node_path = "proxy-node-input",
        .node_resolved = "proxy-node-resolved-input",
        .reachability = .reachable,
        .sync_state = .needed,
        .last_attempt_at_unix_s = 3_001,
        .last_attempt_result = .protocol_error,
        .last_success_at_unix_s = 3_002,
        .success_revision = 3_003,
        .accounts = &proxy_accounts,
    });
    model.view.finish(.{ .selected = 0, .row_menu = 0, .proxy_row_menu = 0, .claude_tray_window = .session });

    var account = &model.view.rows[0];
    account.account_id = "account:account_id";
    account.label = "account:label";
    account.provider_email = "account:provider_email";
    account.plan_label = "account:plan_label";
    account.last_attempt_code = "account:last_attempt_code";
    account.snapshot_captured_at_unix_s = 4_001;
    account.last_attempt_at_unix_s = 4_002;
    account.last_success_at_unix_s = 4_003;
    account.credit_detail_count = 41;
    account.proxy_in_flight = 42;
    account.proxy_cooldown_until_unix_s = 4_004;
    account.primary = 0;
    account.tray_primary = 1;
    account.summary_text = "account:summary_text";
    account.freshness_text = "account:freshness_text";
    account.evidence_text = "account:evidence_text";
    account.tray_text = "account:tray_text";
    account.tray_account_text = "account:tray_account_text";
    account.tray_identity_text = "account:tray_identity_text";
    account.tray_detail_text = "account:tray_detail_text";
    account.tray_open_command = "account:tray_open_command";
    account.tray_usage_text = "account:tray_usage_text";
    account.tray_updated_text = "account:tray_updated_text";
    account.tray_failover_text = "account:tray_failover_text";

    model.view.now_unix_s = 5_001;
    model.view.tray_provider_headers = .{ "view:provider_header_codex", "view:provider_header_claude" };
    model.view.proxy_base_url = "view:proxy_base_url";
    model.view.proxy_cli_path = "view:proxy_cli_path";
    model.view.proxy_config_path = "view:proxy_config_path";
    model.view.proxy_node_path = "view:proxy_node_path";
    model.view.proxy_node_resolved = "view:proxy_node_resolved";
    model.view.proxy_last_attempt_at_unix_s = 5_002;
    model.view.proxy_last_success_at_unix_s = 5_003;
    model.view.proxy_success_revision = 5_004;
    model.view.proxy_account_count = 2;
    model.view.proxy_row_count = 3;
    model.view.usage_count = 4;
    model.view.account_row_count = 5;
    model.view.claude_row_count = 6;
    model.view.proxy_in_flight = 101;
    model.view.codex_exhausted_count = 102;
    model.view.proxy_cooling_count = 103;
    model.view.proxy_mapped_count = 104;
    model.view.claude_count = 105;
    model.view.codex_count = 106;
    model.view.reauth_count = 107;
    model.view.error_count = 108;
    model.view.stale_count = 109;
    model.view.busy_count = 110;
    model.view.snapshot_count = 111;
    model.view.newest_success_at_unix_s = 5_005;
    model.view.proxy_summary_text = "view:proxy_summary_text";
    model.view.proxy_detail_text = "view:proxy_detail_text";
    model.view.proxy_tray_text = "view:proxy_tray_text";
    model.view.claude_group_title = "view:claude_group_title";
    model.view.codex_group_title = "view:codex_group_title";
    model.view.claude_group_summary = "view:claude_group_summary";
    model.view.codex_group_summary = "view:codex_group_summary";
    model.view.onboarding_visible = false;
    model.view.onboarding_steps = .{
        .{ .kind = .add_account, .title = "view:onboarding_step_1", .completed = true },
        .{ .kind = .install_proxy_service, .title = "view:onboarding_step_2" },
        .{ .kind = .enable_codex_routing, .title = "view:onboarding_step_3" },
    };
    model.view.onboarding_next_action = .{
        .kind = .enable_codex_routing,
        .label = "view:onboarding_next_action",
        .enabled = true,
        .replace_conflicting = true,
    };
    model.view.toolbar_status_text = "view:toolbar_status_text";
    model.view.header_fresh_text = "view:header_fresh_text";
    model.view.header_failed_text = "view:header_failed_text";
    model.view.proxy_pill_text = "view:proxy_pill_text";
    model.view.proxy_active_label = "view:proxy_active_label";
    model.view.proxy_settings_summary_text = "view:proxy_settings_summary_text";
    model.view.proxy_node_hint_text = "view:proxy_node_hint_text";
    model.view.proxy_banner_text = "view:proxy_banner_text";
    model.view.headline_text = "view:headline_text";
    model.view.summary_text = "view:summary_text";
    model.view.tray_summary_text = "view:tray_summary_text";
    model.view.service_text = "view:service_text";

    model.settings_tab = .failover;
    model.expanded = 11;
    model.row_menu = 12;
    model.proxy_row_menu = 13;
    model.claude_tray_window = .session;
    model.notice.set(.info, "shell:notice_text", .{});
    model.reset.row = 21;
    model.reset.reason = .pending_attempt;
    model.reset.outcome = .service_unavailable;
    model.reset.settle = .settled;
    model.reset.proxy_clear = .failed;
    model.reset.available_count = 26;
    shell.copyInto(&model.reset.account_id_buffer, &model.reset.account_id_len, "shell:reset_account_id");
    shell.copyInto(&model.reset.label_buffer, &model.reset.label_len, "shell:reset_label");
    shell.copyInto(&model.reset.evidence_buffer, &model.reset.evidence_len, "shell:reset_usage_text");
    shell.copyInto(&model.reset.reset_buffer, &model.reset.reset_len, "shell:reset_reset_text");
    model.remove.row = 22;
    model.remove.status_revision_at_pause = 27;
    shell.copyInto(&model.remove.account_id_buffer, &model.remove.account_id_len, "shell:remove_account_id");
    shell.copyInto(&model.remove.label_buffer, &model.remove.label_len, "shell:remove_label");
    model.rename.row = 23;
    shell.copyInto(&model.rename.account_id_buffer, &model.rename.account_id_len, "shell:rename_account_id");
    shell.copyInto(&model.rename.initial_label_buffer, &model.rename.initial_label_len, "shell:rename_initial_label");
    model.failover_switch.row = 24;
    shell.copyInto(&model.failover_switch.account_id_buffer, &model.failover_switch.account_id_len, "shell:failover_account_id");
    shell.copyInto(&model.failover_switch.target_label_buffer, &model.failover_switch.target_label_len, "shell:failover_target_label");
    model.clear_cooldown.row = 25;
    shell.copyInto(&model.clear_cooldown.account_id_buffer, &model.clear_cooldown.account_id_len, "shell:cooldown_account_id");
    shell.copyInto(&model.clear_cooldown.label_buffer, &model.clear_cooldown.label_len, "shell:cooldown_label");

    const account_bool_fields = [_][]const u8{
        "enabled",              "has_snapshot", "operation_in_flight", "queued",           "pending_reset_attempt",
        "unsent_reset_attempt", "proxy_mode",   "proxy_active",        "proxy_can_switch",
    };
    const capability_bool_fields = [_][]const u8{ "connected", "refresh", "accounts", "reset", "proxy_control" };
    const view_bool_fields = [_][]const u8{ "proxy_config_path_matches", "header_has_failures", "proxy_pill_ok", "proxy_pill_warn", "proxy_pill_bad" };

    for (0..5) |plane| {
        inline for (account_bool_fields, 1..) |field, code| @field(account, field) = sentinelBit(code, plane);
        inline for (capability_bool_fields, 10..) |field, code| @field(model.view.capabilities, field) = sentinelBit(code, plane);
        inline for (view_bool_fields, 15..) |field, code| @field(model.view, field) = sentinelBit(code, plane);
        model.view.proxy_work = if (sentinelBit(28, plane)) .checking else .idle;
        model.toolbar_menu_open = sentinelBit(20, plane);
        model.proxy_settings_expanded = sentinelBit(21, plane);
        model.add_account.open = sentinelBit(29, plane);
        model.add_account.in_flight = sentinelBit(30, plane);
        model.remove.open = sentinelBit(22, plane);
        model.rename.open = sentinelBit(23, plane);
        model.failover_switch.open = sentinelBit(24, plane);
        model.clear_cooldown.open = sentinelBit(25, plane);
        model.remove.uses_proxy = sentinelBit(26, plane);
        model.remove.pause_requested = sentinelBit(27, plane);
        model.reset.stage = .blocked;
        try expectIndependentWireProjection(&model);
    }

    const reset_variants = [_]struct { stage: ui.ResetStage, reason: ui.ResetBlockReason, settle: @FieldType(ui.ResetFlow, "settle"), proxy_clear: ui.ResetProxyClear }{
        .{ .stage = .idle, .reason = .none, .settle = .none, .proxy_clear = .none },
        .{ .stage = .review, .reason = .none, .settle = .none, .proxy_clear = .none },
        .{ .stage = .armed, .reason = .none, .settle = .none, .proxy_clear = .none },
        .{ .stage = .blocked, .reason = .no_credit, .settle = .none, .proxy_clear = .none },
        .{ .stage = .blocked, .reason = .pending_attempt, .settle = .none, .proxy_clear = .none },
        .{ .stage = .dispatched, .reason = .none, .settle = .waiting, .proxy_clear = .pending },
        .{ .stage = .dispatched, .reason = .none, .settle = .settled, .proxy_clear = .failed },
    };
    for (reset_variants) |variant| {
        model.reset.stage = variant.stage;
        model.reset.reason = variant.reason;
        model.reset.settle = variant.settle;
        model.reset.proxy_clear = variant.proxy_clear;
        try expectIndependentWireProjection(&model);
    }

    model.view.row_count = 0;
    model.view.capabilities.refresh = true;
    try expectIndependentWireProjection(&model);
}

test "effects are serialized in order and drain exactly once" {
    var model = shell.initialModel(.kst);
    shell.reproject(&model);
    var effects: shell.Effects = .{};
    shell.update(&model, .open_details, &effects);
    shell.update(&model, .quit_app, &effects);
    const first = try bridge.serialize(testing.allocator, 2, .{}, &model, &effects);
    defer testing.allocator.free(first);
    try testing.expect(std.mem.indexOf(u8, first, "\"show_settings\"") != null);
    try testing.expect(std.mem.indexOf(u8, first, "\"quit\"") != null);
    effects.clear();
    const second = try bridge.serialize(testing.allocator, 2, .{}, &model, &effects);
    defer testing.allocator.free(second);
    try testing.expect(std.mem.indexOf(u8, second, "\"effects\":[]") != null);
}

test "serialization allocation failure preserves queued effects" {
    var model = shell.initialModel(.kst);
    shell.reproject(&model);
    var effects: shell.Effects = .{};
    shell.update(&model, .open_details, &effects);
    try testing.expectError(error.OutOfMemory, bridge.serialize(testing.failing_allocator, 9, .{}, &model, &effects));
    try testing.expectEqual(@as(usize, 1), effects.len);
    try testing.expectEqual(shell.EffectKind.show_settings, effects.slice()[0].kind);
}

test "comptime reflection covers every exported projection field" {
    bridge.assertProjectionFieldCoverage();
}

fn sourceListContains(list: []const u8, candidate: []const u8) bool {
    var lines = std.mem.splitScalar(u8, list, '\n');
    while (lines.next()) |line| {
        if (std.mem.eql(u8, std.mem.trim(u8, line, " \t\r"), candidate)) return true;
    }
    return false;
}

test "core source list covers every reachable Zig import" {
    const list = try std.Io.Dir.cwd().readFileAlloc(
        testing.io,
        "scripts/core-source-list.txt",
        testing.allocator,
        .limited(64 * 1024),
    );
    defer testing.allocator.free(list);
    try testing.expect(sourceListContains(list, "src/cmcore.zig"));

    var lines = std.mem.splitScalar(u8, list, '\n');
    while (lines.next()) |raw_line| {
        const source_path = std.mem.trim(u8, raw_line, " \t\r");
        if (source_path.len == 0) continue;
        const source = try std.Io.Dir.cwd().readFileAlloc(
            testing.io,
            source_path,
            testing.allocator,
            .limited(1024 * 1024),
        );
        defer testing.allocator.free(source);

        var cursor: usize = 0;
        while (std.mem.indexOfPos(u8, source, cursor, "@import(\"")) |start| {
            const import_start = start + "@import(\"".len;
            const import_end = std.mem.indexOfPos(u8, source, import_start, "\")") orelse
                return error.MalformedImport;
            cursor = import_end + 2;
            const imported = source[import_start..import_end];
            if (!std.mem.endsWith(u8, imported, ".zig")) continue;
            const source_dir = std.fs.path.dirname(source_path) orelse ".";
            const resolved = try std.fs.path.resolve(testing.allocator, &.{ source_dir, imported });
            defer testing.allocator.free(resolved);
            if (!sourceListContains(list, resolved)) {
                std.debug.print("core source list missing {s}, imported by {s}\n", .{ resolved, source_path });
                return error.TestUnexpectedResult;
            }
        }
    }
}
