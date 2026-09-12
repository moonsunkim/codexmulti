const std = @import("std");

pub const Language = enum { system, en, ko, ja };
const Japanese = @import("strings_ja.zig").Static;
const JapaneseFormat = @import("strings_ja.zig").Format;

const catalog_languages = [_]Language{ .en, .ko, .ja };
pub const supported_languages = blk: {
    var values: [catalog_languages.len + 1]Language = undefined;
    values[0] = .system;
    for (catalog_languages, 1..) |language, index| values[index] = language;
    break :blk values;
};
pub const month_count = English.month_names.len;

pub const StaticKey = enum {
    add_account_dialog_title,
    add_account_dialog_explanation,
    add_account_dialog_progress,
    add_account_dialog_invalid_label,

    reset_proxy_clearing,
    reset_proxy_cleared,
    reset_proxy_unmapped,
    reset_proxy_unreachable,
    reset_proxy_busy,
    reset_proxy_failed,
    reset_only_codex,
    reset_no_credit,
    reset_prior_pending,
    reset_prior_unsent,
    reset_needs_auth,
    reset_disabled,
    reset_unknown_account,
    reset_service_missing,
    reset_settled,
    reset_settled_unsent,
    reset_pending,
    reset_unsent_service,
    reset_unsent_cli,
    reset_unsent_offer,
    reset_unsent_busy,
    reset_unsent_refused,
    reset_unsent_unknown,
    reset_unconfirmed_failure,

    appearance_system,
    appearance_light,
    appearance_dark,
    codex_usage_window_label,
    codex_usage_window_detail,
    codex_model_limits_label,
    codex_model_limits_detail,

    shell_settings,
    shell_system,
    shell_proxy,
    shell_appearance,
    shell_theme,
    shell_launch_at_login,
    shell_launch_at_login_registration_failed,
    shell_auto_refresh,
    shell_about,
    shell_version,
    shell_update_title,
    shell_update_check,
    shell_update_install,
    shell_update_available,
    shell_update_current,
    shell_update_ready,
    shell_update_pending,
    shell_update_apply,
    shell_update_check_failed,
    shell_update_no_compatible,
    shell_update_checking,
    shell_update_preparing,
    shell_update_downloading,
    shell_update_installing,
    shell_update_waiting,
    shell_update_applying,
    shell_update_complete,
    shell_update_rollback,
    shell_update_failed,
    shell_update_recovery,
    shell_update_unconfigured,
    shell_update_migration,
    shell_update_migration_detail,
    shell_update_migration_confirm,
    shell_update_cancel,
    shell_update_off,
    shell_update_frozen,

    shell_failover_state,
    shell_failover_detail,
    shell_in_flight,
    shell_tab_accounts,
    shell_tab_settings,
    shell_tab_failover,
    shell_update_proxy_accounts,
    shell_add_codex_menu,
    shell_refresh_all_help,
    shell_status_accessibility,
    shell_segment_accessibility,
    shell_dismiss_notice,
    shell_retry,
    shell_starting,
    shell_row_menu_accessibility,
    shell_row_hint,
    shell_reorder_hint,
    shell_usage_bar_accessibility,
    shell_refresh,
    shell_sign_in,
    shell_sign_in_again,
    shell_pause_in_failover,
    shell_clear_cooldown,
    shell_move_to_top,
    shell_rename,
    shell_remove,
    shell_fact_resets,
    shell_fact_status,
    shell_fact_failover,
    shell_fact_o_auth_token,
    shell_fact_last_refresh,
    shell_fact_reset_credits,
    shell_fact_updated,
    shell_not_applicable,
    shell_failover_row_menu_accessibility,
    shell_use_in_failover,
    shell_pause,
    shell_resume,
    shell_resume_in_failover,
    shell_in_flight_suffix,
    shell_status_separator,
    shell_use_failover_proxy,
    shell_advanced_proxy_controls,
    shell_codex_routing,
    shell_install_and_start,
    shell_repair_proxy_service,
    shell_stop_proxy_service,
    shell_enable_for_codex,
    shell_disable_for_codex,
    shell_replace_codex_routing,
    shell_routing_off,
    shell_routing_on,
    shell_routing_conflicting,
    shell_client_quiescence_title,
    shell_client_quiescence_message,
    shell_replace_routing_title,
    shell_replace_routing_message,
    shell_connection_settings,
    shell_field_control_u_r_l,
    shell_field_proxy_c_l_i,
    shell_field_config,
    shell_field_node_path,
    shell_bundled_proxy_c_l_i_default,
    shell_bundled_node_default,
    shell_advanced_overrides,
    shell_field_proxy_c_l_i_override,
    shell_field_node_override,
    shell_empty_override_help,
    shell_save,
    shell_quit,
    shell_failover_switch_title_prefix,
    shell_failover_switch_title_suffix,
    shell_failover_switch_body_prefix,
    shell_failover_switch_body_suffix,
    shell_failover_switch_muted,
    shell_use_account,
    shell_clear_cooldown_title_prefix,
    shell_clear_cooldown_title_suffix,
    shell_clear_cooldown_body,
    shell_clear_cooldown_muted,
    shell_clear_cooldown_confirm,
    shell_rename_title,
    shell_rename_muted,
    shell_account_label,
    shell_remove_title,
    shell_remove_body_suffix,
    shell_remove_mapped_muted,
    shell_remove_plain_muted,
    shell_refresh_drain_status,
    shell_finish_removal,
    shell_remove_and_sync,
    shell_remove_confirm,
    shell_reset_title,
    shell_reset_retry_muted,
    shell_close,
    shell_retry_same_request,
    shell_reset_body_prefix,
    shell_reset_body_suffix,
    shell_reset_available_suffix,
    shell_reset_next_reset_infix,
    shell_reset_acknowledge,
    shell_use_one_reset,
    shell_cancel,
    shell_auto_refresh_off,
    shell_fifteen_minutes,
    shell_thirty_minutes,
    shell_one_hour,
    shell_usage_auto,
    shell_usage_weekly,
    shell_usage_session,
    shell_expanded,
    shell_collapsed,
    proxy_update_pending,
    proxy_enabling_pending,
    proxy_disabling_pending,
    proxy_retrying,
    proxy_sign_in_first,
    proxy_accounts_syncing,
    proxy_running_routing,
    proxy_unavailable_routing,
    proxy_conflicting_routing,
    proxy_applying_switch,
    proxy_settings_changed,
    proxy_service_starting,
    proxy_waiting_requests,
    proxy_service_stale,
    proxy_service_running,
    proxy_service_unreachable,
    proxy_loaded_unreachable,

    plan_pro_20x,
    plan_pro_5x,
    reset_time_not_reported,
    reset_passed_refresh,
    countdown_passed_refresh,
    provider_unsupported,
    provider_codex,
    window_weekly,
    window_session,
    window_daily,
    window_monthly,
    window_hourly,
    window_codex,
    freshness_never,
    freshness_as_of,
    freshness_saved_snapshot,
    freshness_refresh_failed,
    freshness_reauthentication_required,
    freshness_usage_unavailable,
    freshness_refresh_deferred,
    freshness_reset_passed,
    freshness_never_lower,
    freshness_as_of_lower,
    freshness_saved_snapshot_lower,
    freshness_refresh_failed_lower,
    freshness_reauthentication_required_lower,
    freshness_usage_unavailable_lower,
    freshness_refresh_deferred_lower,
    freshness_reset_passed_lower,
    attempt_reason_helper_closed,
    attempt_reason_helper_unavailable,
    attempt_reason_cli_too_old,
    attempt_reason_timed_out,
    attempt_reason_canceled,
    attempt_reason_refresh_rejected,
    attempt_reason_malformed_reply,
    attempt_reason_sign_in_required,
    attempt_reason_workspace_invalid,
    attempt_reason_wrong_workspace,
    attempt_reason_no_usage_window,
    attempt_reason_incomplete_reading,
    attempt_reason_sign_in_unsupported,
    attempt_reason_sign_in_could_not_start,
    attempt_reason_sign_in_timed_out,
    attempt_reason_sign_in_canceled,
    attempt_reason_sign_in_handoff_failed,
    attempt_reason_sign_in_rejected,
    attempt_reason_sign_in_output_unclear,
    attempt_reason_credential_not_saved,
    attempt_reason_credential_incomplete,
    attempt_reason_keychain_repair_needed,
    attempt_reason_account_unknown,
    attempt_reason_account_busy,
    attempt_reason_account_disabled,
    attempt_reason_provider_mismatch,
    attempt_reason_reset_unconfirmed,
    attempt_reason_reset_key_invalid,
    attempt_reason_reset_outcome_unknown,
    attempt_reason_refresh_failed,
    attempt_message_helper_closed,
    attempt_message_helper_unavailable,
    attempt_message_cli_unsupported,
    attempt_message_refresh_timeout,
    attempt_message_sign_in_required,
    attempt_message_wrong_workspace,
    attempt_message_usage_unsupported,
    attempt_message_usage_incomplete,
    attempt_message_login_import_unavailable,
    attempt_message_login_import_incomplete,
    attempt_message_login_rejected,
    attempt_message_login_timeout,
    attempt_message_login_io,
    attempt_message_keychain_repair,
    attempt_message_refresh_failed,
    auth_connected,
    auth_reauthentication_required,
    auth_unavailable,
    snapshot_none,
    snapshot_fresh,
    snapshot_stale,
    snapshot_partial,
    snapshot_reauthentication_required,
    snapshot_error_state,
    snapshot_unavailable,
    snapshot_deferred,
    no_saved_snapshot_yet,
    no_saved_snapshot_yet_sentence,
    no_usage_window_reported,
    service_not_connected,
    service_local_only,
    service_refresh_not_attached,
    service_accounts_not_attached,
    service_reset_not_attached,
    service_all_attached,
    unrepresentable_local_time,
    just_now,
    tray_refresh_usage,
    tray_open_in_settings,
    tray_help,
    tray_accounts,
    tray_settings,
    tray_quit,
    tray_refresh_all_accounts,
    tray_no_saved_accounts,
    tray_more_accounts,
    tray_one_more_account,
    tray_two_more_accounts,
    tray_three_more_accounts,
    tray_four_more_accounts,
    tray_five_more_accounts,
    tray_six_more_accounts,
    tray_seven_more_accounts,
    tray_eight_more_accounts,
    tray_nine_more_accounts,
    tray_ten_more_accounts,
    tray_eleven_more_accounts,
    tray_twelve_more_accounts,
    tray_thirteen_more_accounts,
    tray_fourteen_more_accounts,
    tray_fifteen_more_accounts,
    tray_sixteen_more_accounts,
    node_missing_reason,
    app_version,
    proxy_service_not_installed,
    proxy_direct_routing,
    onboarding_add_account,
    onboarding_install_proxy,
    onboarding_enable_routing,
    add_codex,
    install_and_start,
    repair_proxy_service,
    turn_on_routing,
    proxy_ready,
    proxy_cooldown,
    proxy_paused,
    proxy_invalid,
    proxy_refreshing,
    proxy_unknown,
    none_lower,
    not_mapped,
    active,
    not_mapped_saved_account,
    cooldown_end_not_reported,
    credential_needs_attention,
    refreshing_token,
    token_refresh_failed,
    token_refresh_retrying,
    proxy_status_unknown,
    failover_proxy_reachable,
    proxy_config_mismatch,
    proxy_unreachable,
    proxy_incompatible,
    proxy_press_refresh,
    proxy_busy_retry,
    proxy_changes_next_refresh,
    proxy_synchronized,
    proxy_sync_failed,
    proxy_checking,
    proxy_switching,
    proxy_pausing,
    proxy_reloading,
    proxy_clearing_cooldown,
    proxy_importing,
    proxy_applying_config,
    failover_status_unknown_settings,
    failover_config_mismatch,
    failover_unreachable,
    failover_incompatible,
    failover_unknown,
    proxy_unreachable_never_seen,
    proxy_incompatible_update,
    proxy_config_fix_next_refresh,
    node_not_found,
    node_auto,
    no_control_url,
    cli_path_set,
    cli_path_missing,
    config_matches,
    config_not_confirmed,
    refreshing_ellipsis,
    queued,
    updating_ellipsis,
    sign_in_required,
    disabled,
    proxy_invalid_label,
    use_in_failover,
    use_in_failover_proxy,
    review_reset_attempt,
    retry_reset_attempt,
    account_singular,
    account_plural,
    not_mapped_to_failover,
    auto_refresh_off,
    no_accounts,
    no_cursor_separator,
    row_refreshing_usage,
    row_queued_to_refresh,
    row_sign_in_required,
    row_refresh_failed,
    row_not_refreshed_yet,
    row_disabled,
    evidence_no_success,
    evidence_no_attempt,
    header_not_refreshed_suffix,
    not_refreshed_yet,
    active_in_failover_proxy,
    codexmulti,
    no_accounts_registered,
    codex_accounts_header,
    attention_sign_in_again,
    attention_usage_unavailable,
    attention_refresh_failed,
    no_usage_in_snapshot,
    codex_usage_api,
    reset_unconfirmed,
    reset_unconfirmed_note,
    reset_not_sent,
    reset_not_sent_note,
    credit_detail_mismatch,
    not_reported,
    reset_time_not_reported_title,
    connection_disabled_suffix,
    connection_paused_suffix,
    middle_dot_separator,
    language_label,
    language_system,
    language_english,
    language_korean,
    language_japanese,
};

pub const FormatKey = enum {
    reset_phrase,
    absolute_datetime,
    countdown_days,
    countdown_hours,
    countdown_minutes,
    countdown_seconds,
    remaining_days,
    remaining_hours,
    remaining_minutes,
    remaining_seconds,
    ago_minutes,
    ago_hours,
    ago_days,
    short_date,
    clock_time,
    medium_datetime,
    duration_days,
    duration_hours,
    duration_minutes,
    proxy_cooldown_until,
    proxy_draining_resume,
    decimal_usize,
    decimal_u32,
    tray_failover_last_seen,
    tray_proxy_unreachable_last_seen,
    tray_proxy_incompatible_last_seen,
    tray_failover_unknown_last_seen,
    failover_active_cooling,
    proxy_unreachable_banner,
    node_path,
    node_auto_path,
    proxy_settings_summary,
    percent,
    window_caption,
    identity_secondary,
    freshness_with_ago,
    cooldown_remaining,
    reset_available_action,
    account_access_expanded,
    account_access,
    account_group_exhausted,
    account_group_count,
    codex_group_title,
    auto_refresh_traffic,
    last_refresh,
    failed_count,
    toolbar_proxy_off,
    toolbar_proxy_unreachable,
    toolbar_none_ready_reset,
    toolbar_none_ready,
    toolbar_ready_in_flight,
    toolbar_ready,
    toolbar_pool_suffix,
    toolbar_proxy_status,
    toolbar_failed_suffix,
    row_usage_summary,
    evidence_last_success,
    evidence_last_attempt,
    row_tray_status,
    tray_usage,
    updated,
    failover_proxy_state,
    header_accounts,
    header_need_sign_in,
    header_unreadable,
    header_in_progress,
    header_updated,
    tray_summary,
    tray_pool,
    default_account_label,
    numbered_account_label,
    last_good_reading,
    updated_freshness,
    active_in_flight,
    cooldown_until,
    paused_draining,
    credits_available,
    evidence_deferred,
    evidence_failed,
    token_valid_until,
};

pub fn FormatArgs(comptime key: FormatKey) type {
    return switch (key) {
        .reset_phrase,
        .tray_proxy_unreachable_last_seen,
        .tray_proxy_incompatible_last_seen,
        .tray_failover_unknown_last_seen,
        .proxy_unreachable_banner,
        .node_path,
        .node_auto_path,
        .identity_secondary,
        .cooldown_remaining,
        .toolbar_proxy_off,
        .toolbar_proxy_unreachable,
        .toolbar_none_ready_reset,
        .toolbar_none_ready,
        .updated,
        .failover_proxy_state,
        .tray_summary,
        .last_good_reading,
        .evidence_deferred,
        .token_valid_until,
        => @Tuple(&.{[]const u8}),
        .countdown_days,
        .countdown_hours,
        .remaining_days,
        .remaining_hours,
        => @Tuple(&.{ i64, i64 }),
        .countdown_minutes,
        .countdown_seconds,
        .remaining_minutes,
        .remaining_seconds,
        .ago_minutes,
        .ago_hours,
        .ago_days,
        => @Tuple(&.{i64}),
        .short_date => @Tuple(&.{ []const u8, u32 }),
        .clock_time => @Tuple(&.{ u32, u32 }),
        .absolute_datetime => @Tuple(&.{ u32, []const u8, u32, u32, u32, []const u8 }),
        .medium_datetime => @Tuple(&.{ []const u8, u32, u32, u32, []const u8 }),
        .duration_days,
        .duration_hours,
        .duration_minutes,
        .proxy_draining_resume,
        .decimal_u32,
        .failed_count,
        .toolbar_failed_suffix,
        .reset_available_action,
        .active_in_flight,
        .paused_draining,
        .credits_available,
        .toolbar_pool_suffix,
        => @Tuple(&.{u32}),
        .decimal_usize,
        .header_accounts,
        => @Tuple(&.{usize}),
        .proxy_cooldown_until,
        .window_caption,
        .freshness_with_ago,
        .last_refresh,
        .toolbar_proxy_status,
        .row_tray_status,
        .updated_freshness,
        .cooldown_until,
        .evidence_failed,
        => @Tuple(&.{ []const u8, []const u8 }),
        .tray_failover_last_seen => @Tuple(&.{ []const u8, u32, []const u8 }),
        .failover_active_cooling => @Tuple(&.{ []const u8, u32 }),
        .proxy_settings_summary,
        .account_access_expanded,
        .account_access,
        => @Tuple(&.{ []const u8, []const u8, []const u8 }),
        .percent => @Tuple(&.{u8}),
        .account_group_exhausted => @Tuple(&.{ u32, []const u8, u32 }),
        .account_group_count => @Tuple(&.{ u32, []const u8 }),
        .codex_group_title,
        .default_account_label,
        => @Tuple(&.{[]const u8}),
        .auto_refresh_traffic => @Tuple(&.{ u16, []const u8, u16, u32 }),
        .toolbar_ready_in_flight => @Tuple(&.{ u32, u32 }),
        .toolbar_ready => @Tuple(&.{ u32, []const u8 }),
        .row_usage_summary => @Tuple(&.{ u8, []const u8 }),
        .tray_usage => @Tuple(&.{ u8, []const u8, []const u8 }),
        .evidence_last_success,
        .evidence_last_attempt,
        .header_updated,
        => @Tuple(&.{[]const u8}),
        .header_need_sign_in,
        .header_unreadable,
        .header_in_progress,
        => @Tuple(&.{u32}),
        .tray_pool => @Tuple(&.{ u32, u32, u32 }),
        .numbered_account_label => @Tuple(&.{ []const u8, u32 }),
    };
}

pub const Catalog = struct {
    language: Language,

    pub fn lookup(self: Catalog, name: []const u8) ?[]const u8 {
        for (static_key_names, 0..) |candidate, index| {
            if (std.mem.eql(u8, candidate, name)) return self.text(@enumFromInt(index));
        }
        return null;
    }

    pub fn translateEnglish(self: Catalog, value: []const u8) []const u8 {
        if (self.language == .en or self.language == .system) return value;
        for (english_static, 0..) |english_value, index| {
            if (std.mem.eql(u8, english_value, value)) return self.text(@enumFromInt(index));
        }
        return value;
    }

    pub fn text(self: Catalog, key: StaticKey) []const u8 {
        return switch (self.language) {
            .system, .en => english_static[@intFromEnum(key)],
            .ko => korean_static[@intFromEnum(key)],
            .ja => japanese_static[@intFromEnum(key)],
        };
    }

    pub fn write(self: Catalog, writer: *std.Io.Writer, comptime key: FormatKey, args: FormatArgs(key)) void {
        switch (self.language) {
            .system, .en => writer.print(@field(EnglishFormat, @tagName(key)), args) catch {},
            .ko => writer.print(@field(KoreanFormat, @tagName(key)), args) catch {},
            .ja => writer.print(@field(JapaneseFormat, @tagName(key)), args) catch {},
        }
    }

    pub fn monthName(self: Catalog, index: usize) []const u8 {
        return switch (self.language) {
            .system, .en => English.month_names[index],
            .ko => Korean.month_names[index],
            .ja => Japanese.month_names[index],
        };
    }
};

const static_key_names = blk: {
    const fields = @typeInfo(StaticKey).@"enum".fields;
    var names: [fields.len][]const u8 = undefined;
    for (fields, 0..) |field, index| names[index] = field.name;
    break :blk names;
};

pub fn catalog(language: Language) Catalog {
    return .{ .language = language };
}

pub const system = catalog(.system);
pub const english = catalog(.en);
pub const korean = catalog(.ko);
pub const japanese = catalog(.ja);

const English = struct {
    const add_account_dialog_title = "Add Codex account";
    const add_account_dialog_explanation = "Name this account before opening the browser to sign in.";
    const add_account_dialog_progress = "Add account in progress · Codex";
    const add_account_dialog_invalid_label = "Enter an account name before continuing.";

    const reset_proxy_clearing = "Failover: clearing cooldown for this account's proxy row…";
    const reset_proxy_cleared = "Failover: cooldown cleared.";
    const reset_proxy_unmapped = "Failover: cooldown not cleared — this account is not mapped to a proxy row at the last read. Use Clear cooldown… in Failover if it is.";
    const reset_proxy_unreachable = "Failover: cooldown not cleared — the proxy was not reachable at the last read. Use Clear cooldown… in Failover after refreshing its status.";
    const reset_proxy_busy = "Failover: cooldown not cleared — the proxy was busy with another action. Use Clear cooldown… in Failover.";
    const reset_proxy_failed = "Failover: cooldown not cleared — the proxy refused or did not answer. Use Clear cooldown… in Failover.";
    const reset_only_codex = "Reset redemption exists only for Codex accounts.";
    const reset_no_credit = "This account has no reset credit the provider reported as available.";
    const reset_prior_pending = "An earlier reset attempt for this account has not settled. Reconcile it first.";
    const reset_prior_unsent = "The last reset attempt was not sent. Retry runs a fresh preflight and resends it with the same key.";
    const reset_needs_auth = "This account needs reauthentication before a reset can be considered.";
    const reset_disabled = "This account is disabled.";
    const reset_unknown_account = "That account is no longer in the local view.";
    const reset_service_missing = "The reset service is not attached.";
    const reset_settled = "This request has settled. The account row now shows the provider's reported usage and remaining resets.";
    const reset_settled_unsent = "This request was not sent after all. The account row offers Retry reset attempt…, which resends it with the same key.";
    const reset_pending = "The reset request was accepted and is pending. It is not complete until the service reports a settled outcome.";
    const reset_unsent_service = "Nothing was sent: the reset service is not attached.";
    const reset_unsent_cli = "Nothing was sent: the provider CLI is not installed in a supported location.";
    const reset_unsent_offer = "Nothing was sent: a reset needs a fresh Codex preflight read and no current offer exists.";
    const reset_unsent_busy = "Nothing was sent: this account already has an operation in flight.";
    const reset_unsent_refused = "Nothing was sent: the service refused this surface or account state.";
    const reset_unsent_unknown = "Nothing was sent: the service does not know that account.";
    const reset_unconfirmed_failure = "Nothing was confirmed: the service reported a failure. The credit state is unchanged as far as this app can prove.";

    const appearance_system = "System";
    const appearance_light = "Light";
    const appearance_dark = "Dark";
    const codex_usage_window_label = "Usage shown";
    const codex_usage_window_detail = "Prefer a usage window when the provider reports it.";
    const codex_model_limits_label = "Per-model limits";
    const codex_model_limits_detail = "Show reported model limits in account details and headlines.";

    const shell_settings = "Settings…";
    const shell_system = "System";
    const shell_proxy = "Proxy";
    const shell_appearance = "Appearance";
    const shell_theme = "Theme";
    const shell_launch_at_login = "Launch at login";
    const shell_launch_at_login_registration_failed = "Registration failed";
    const shell_auto_refresh = "Auto refresh";
    const shell_about = "About";
    const shell_version = "Version";
    const shell_update_title = "Software update";
    const shell_update_check = "Check for updates";
    const shell_update_install = "Update and relaunch";
    const shell_update_available = "An update is available.";
    const shell_update_current = "You’re up to date.";
    const shell_update_ready = "Check for a newer version.";
    const shell_update_pending = "Engine update cancelled. The previous engine is still in use.";
    const shell_update_apply = "Apply engine update";
    const shell_update_check_failed = "Could not check for updates. Try again.";
    const shell_update_no_compatible = "No compatible update is available.";
    const shell_update_checking = "Checking for updates…";
    const shell_update_preparing = "Preparing update…";
    const shell_update_downloading = "Downloading update…";
    const shell_update_installing = "Installing and relaunching…";
    const shell_update_waiting = "Waiting for requests and connections to finish.";
    const shell_update_applying = "Applying proxy update…";
    const shell_update_complete = "Update complete.";
    const shell_update_rollback = "The previous proxy version was restored.";
    const shell_update_failed = "The update needs recovery.";
    const shell_update_recovery = "Show previous app";
    const shell_update_unconfigured = "Update checks will be available in a release build.";
    const shell_update_migration = "Set up safe updates";
    const shell_update_migration_detail = "One-time setup requires closing all Codex clients.";
    const shell_update_migration_confirm = "I’ve closed all Codex clients";
    const shell_update_cancel = "Cancel pending update";
    const shell_update_off = "Turn off when requests finish";
    const shell_update_frozen = "Account changes are paused while the update finishes.";

    const shell_failover_state = "Failover state";
    const shell_failover_detail = "Failover detail";
    const shell_in_flight = "In flight";
    const shell_tab_accounts = "Accounts";
    const shell_tab_settings = "Settings";
    const shell_tab_failover = "Failover";
    const shell_update_proxy_accounts = "Update proxy accounts";
    const shell_add_codex_menu = "Add Codex…";
    const shell_refresh_all_help = "Refresh all accounts";
    const shell_status_accessibility = "Failover status";
    const shell_segment_accessibility = "Settings sections";
    const shell_dismiss_notice = "Dismiss message";
    const shell_retry = "Retry";
    const shell_starting = "Starting…";
    const shell_row_menu_accessibility = "More actions";
    const shell_row_hint = "Expands the account";
    const shell_reorder_hint = "Drag to change its failover order";
    const shell_usage_bar_accessibility = "Reported usage";
    const shell_refresh = "Refresh";
    const shell_sign_in = "Sign in…";
    const shell_sign_in_again = "Sign in again…";
    const shell_pause_in_failover = "Pause in failover";
    const shell_clear_cooldown = "Clear cooldown…";
    const shell_move_to_top = "Move to top";
    const shell_rename = "Rename…";
    const shell_remove = "Remove…";
    const shell_fact_resets = "Resets";
    const shell_fact_status = "Status";
    const shell_fact_failover = "Failover";
    const shell_fact_o_auth_token = "OAuth token";
    const shell_fact_last_refresh = "Last refresh";
    const shell_fact_reset_credits = "Reset credits";
    const shell_fact_updated = "Updated";
    const shell_not_applicable = "—";
    const shell_failover_row_menu_accessibility = "Failover actions";
    const shell_use_in_failover = "Use in failover…";
    const shell_pause = "Pause";
    const shell_resume = "Resume";
    const shell_resume_in_failover = "Resume in failover";
    const shell_in_flight_suffix = " in flight";
    const shell_status_separator = " · ";
    const shell_use_failover_proxy = "Use Failover";
    const shell_advanced_proxy_controls = "Advanced proxy controls";
    const shell_codex_routing = "Codex routing";
    const shell_install_and_start = "Install & Start";
    const shell_repair_proxy_service = "Repair";
    const shell_stop_proxy_service = "Stop Proxy Service";
    const shell_enable_for_codex = "Enable for Codex";
    const shell_disable_for_codex = "Disable for Codex";
    const shell_replace_codex_routing = "Replace Codex routing";
    const shell_routing_off = "Off";
    const shell_routing_on = "On";
    const shell_routing_conflicting = "Conflicting";
    const shell_client_quiescence_title = "Close or idle Codex clients";
    const shell_client_quiescence_message = "Close or idle all Codex clients and start no new work until the operation settles.";
    const shell_replace_routing_title = "Replace conflicting Codex routing?";
    const shell_replace_routing_message = "Codex has routing values that do not match this proxy. Replace them with the bundled proxy routing values?";
    const shell_connection_settings = "Connection settings";
    const shell_field_control_u_r_l = "Control URL";
    const shell_field_proxy_c_l_i = "CLI path";
    const shell_field_config = "Config path";
    const shell_field_node_path = "Node path";
    const shell_bundled_proxy_c_l_i_default = "Bundled Proxy CLI default";
    const shell_bundled_node_default = "Bundled Node default";
    const shell_advanced_overrides = "Advanced overrides";
    const shell_field_proxy_c_l_i_override = "Proxy CLI override (blank = default)";
    const shell_field_node_override = "Node override (blank = default)";
    const shell_empty_override_help = "Leave empty to use the bundled default.";
    const shell_save = "Save";
    const shell_quit = "Quit";
    const shell_failover_switch_title_prefix = "Route new requests to “";
    const shell_failover_switch_title_suffix = "”?";
    const shell_failover_switch_body_prefix = "This changes the proxy cursor to ";
    const shell_failover_switch_body_suffix = " for new routed requests.";
    const shell_failover_switch_muted = "This does not copy or install an auth file. Requests already in flight continue on their current account.";
    const shell_use_account = "Use Account";
    const shell_clear_cooldown_title_prefix = "Clear the cooldown for “";
    const shell_clear_cooldown_title_suffix = "”?";
    const shell_clear_cooldown_body = "The proxy will use this account again immediately. Do this only if you reset its limit elsewhere.";
    const shell_clear_cooldown_muted = "If the limit is not actually reset, the next request may still be refused and the account is cooled down again from the provider's own answer. No request is sent to the provider now.";
    const shell_clear_cooldown_confirm = "Clear cooldown";
    const shell_rename_title = "Rename account";
    const shell_rename_muted = "This changes only the label shown in CodexMulti.";
    const shell_account_label = "Account label";
    const shell_remove_title = "Remove account?";
    const shell_remove_body_suffix = " will be removed from CodexMulti.";
    const shell_remove_mapped_muted = "The account will be removed automatically after its current requests finish.";
    const shell_remove_plain_muted = "Its saved usage snapshot is also removed. This does not delete the account at OpenAI.";
    const shell_refresh_drain_status = "Refresh drain status";
    const shell_finish_removal = "Finish removal";
    const shell_remove_and_sync = "Remove and sync";
    const shell_remove_confirm = "Remove";
    const shell_reset_title = "Use one Codex reset?";
    const shell_reset_retry_muted = "Retrying checks the same request. It does not spend another reset.";
    const shell_close = "Close";
    const shell_retry_same_request = "Retry same request";
    const shell_reset_body_prefix = "Spends one reset credit on ";
    const shell_reset_body_suffix = ". If the account is cooling in the failover proxy, its cooldown is cleared once the reset settles.";
    const shell_reset_available_suffix = " available · ";
    const shell_reset_next_reset_infix = " · next reset ";
    const shell_reset_acknowledge = "I understand this cannot be undone";
    const shell_use_one_reset = "Use one reset";
    const shell_cancel = "Cancel";
    const shell_auto_refresh_off = "Off";
    const shell_fifteen_minutes = "15 min";
    const shell_thirty_minutes = "30 min";
    const shell_one_hour = "1 hour";
    const shell_usage_auto = "auto";
    const shell_usage_weekly = "weekly";
    const shell_usage_session = "session";
    const shell_expanded = "Expanded";
    const shell_collapsed = "Collapsed";
    const proxy_update_pending = "Failover is on. Updating automatically after current requests finish.";
    const proxy_enabling_pending = "Turning on Failover automatically after current requests finish.";
    const proxy_disabling_pending = "Turning off Failover automatically after current requests finish.";
    const proxy_retrying = "Failover could not connect. Retrying automatically.";
    const proxy_sign_in_first = "Add a Codex account to use Failover.";
    const proxy_accounts_syncing = "Applying account changes automatically after current requests finish.";
    const proxy_running_routing = "Failover is on. New accounts are included automatically.";
    const proxy_unavailable_routing = "Reconnecting Failover automatically. You can turn it off to connect directly.";
    const proxy_conflicting_routing = "Codex has another connection setting. Turn on Failover to replace it.";
    const proxy_applying_switch = "Applying your Failover setting…";
    const proxy_settings_changed = "Proxy settings changed; repair is required.";
    const proxy_service_starting = "Proxy service change is starting";
    const proxy_waiting_requests = "Waiting for proxy requests to finish";
    const proxy_service_stale = "Bundled proxy files or receipt changed; repair is required.";
    const proxy_service_running = "Bundled proxy service is running.";
    const proxy_service_unreachable = "Proxy service is installed but unreachable.";
    const proxy_loaded_unreachable = "The proxy is not responding. Repair it or turn off routing to connect directly.";

    const plan_pro_20x = "Pro 20x";
    const plan_pro_5x = "Pro 5x";
    const reset_time_not_reported = "reset time not reported";
    const reset_passed_refresh = "reset passed · refresh";
    const countdown_passed_refresh = "reset passed — refresh to confirm";
    const provider_unsupported = "Unsupported";
    const provider_codex = "Codex";
    const window_weekly = "Weekly";
    const window_session = "Session";
    const window_daily = "Daily";
    const window_monthly = "Monthly";
    const window_hourly = "Hourly";
    const window_codex = "Codex";
    const freshness_never = "Never refreshed";
    const freshness_as_of = "As of the last successful refresh";
    const freshness_saved_snapshot = "Saved snapshot";
    const freshness_refresh_failed = "Refresh failed";
    const freshness_reauthentication_required = "Reauthentication required";
    const freshness_usage_unavailable = "Usage unavailable";
    const freshness_refresh_deferred = "Refresh deferred";
    const freshness_reset_passed = "Reset passed — refresh to confirm";
    const freshness_never_lower = "never refreshed";
    const freshness_as_of_lower = "as of the last successful refresh";
    const freshness_saved_snapshot_lower = "saved snapshot";
    const freshness_refresh_failed_lower = "refresh failed";
    const freshness_reauthentication_required_lower = "reauthentication required";
    const freshness_usage_unavailable_lower = "usage unavailable";
    const freshness_refresh_deferred_lower = "refresh deferred";
    const freshness_reset_passed_lower = "reset passed — refresh to confirm";
    const attempt_reason_helper_closed = "helper closed";
    const attempt_reason_helper_unavailable = "helper unavailable";
    const attempt_reason_cli_too_old = "Codex CLI too old";
    const attempt_reason_timed_out = "timed out";
    const attempt_reason_canceled = "canceled";
    const attempt_reason_refresh_rejected = "refresh rejected";
    const attempt_reason_malformed_reply = "malformed reply";
    const attempt_reason_sign_in_required = "sign-in required";
    const attempt_reason_workspace_invalid = "workspace invalid";
    const attempt_reason_wrong_workspace = "wrong workspace";
    const attempt_reason_no_usage_window = "no usage window";
    const attempt_reason_incomplete_reading = "incomplete reading";
    const attempt_reason_sign_in_unsupported = "sign-in unsupported";
    const attempt_reason_sign_in_could_not_start = "sign-in could not start";
    const attempt_reason_sign_in_timed_out = "sign-in timed out";
    const attempt_reason_sign_in_canceled = "sign-in canceled";
    const attempt_reason_sign_in_handoff_failed = "sign-in hand-off failed";
    const attempt_reason_sign_in_rejected = "sign-in rejected";
    const attempt_reason_sign_in_output_unclear = "sign-in output unclear";
    const attempt_reason_credential_not_saved = "credential not saved";
    const attempt_reason_credential_incomplete = "credential incomplete";
    const attempt_reason_keychain_repair_needed = "Keychain repair needed";
    const attempt_reason_account_unknown = "account unknown";
    const attempt_reason_account_busy = "account busy";
    const attempt_reason_account_disabled = "account disabled";
    const attempt_reason_provider_mismatch = "provider mismatch";
    const attempt_reason_reset_unconfirmed = "reset unconfirmed";
    const attempt_reason_reset_key_invalid = "reset key invalid";
    const attempt_reason_reset_outcome_unknown = "reset outcome unknown";
    const attempt_reason_refresh_failed = "refresh failed";
    const attempt_message_helper_closed = "The Codex helper closed before replying. Try Refresh again; if it repeats, sign in again.";
    const attempt_message_helper_unavailable = "The Codex helper is unavailable. Check that the Codex CLI can run, then try again.";
    const attempt_message_cli_unsupported = "This Codex CLI does not support the usage reader. Update Codex and try again.";
    const attempt_message_refresh_timeout = "The provider did not reply in time. Your previous reading is still shown.";
    const attempt_message_sign_in_required = "This sign-in is no longer valid. Sign in again to refresh usage.";
    const attempt_message_wrong_workspace = "Codex opened the wrong account workspace. Sign in to this account again.";
    const attempt_message_usage_unsupported = "The provider did not return a usable usage window.";
    const attempt_message_usage_incomplete = "The provider returned an incomplete reading. The last complete values remain visible.";
    const attempt_message_login_import_unavailable = "Sign-in finished, but the credential could not be saved to this account. Sign in again.";
    const attempt_message_login_import_incomplete = "Sign-in did not return a complete reusable credential. Sign in again.";
    const attempt_message_login_rejected = "Codex did not approve this sign-in. Try again and finish the browser confirmation.";
    const attempt_message_login_timeout = "The sign-in window expired before the browser confirmation arrived. Try again.";
    const attempt_message_login_io = "CodexMulti could not complete the secure sign-in hand-off. Try again.";
    const attempt_message_keychain_repair = "Older saved credentials need one-time Keychain access repair. Choose Sign In Again to save a fresh protected copy; the old item will be kept.";
    const attempt_message_refresh_failed = "Refresh failed. Your previous saved reading is still visible.";
    const auth_connected = "Connected";
    const auth_reauthentication_required = "Reauthentication required";
    const auth_unavailable = "Unavailable";
    const snapshot_none = "No snapshot has been stored for this account.";
    const snapshot_fresh = "Stored from a complete successful read.";
    const snapshot_stale = "Stored earlier; no claim that it is current.";
    const snapshot_partial = "Stored from a partial read. Missing fields stayed missing.";
    const snapshot_reauthentication_required = "Stored before credentials stopped working.";
    const snapshot_error_state = "Stored before the most recent failure.";
    const snapshot_unavailable = "Authentication worked but no supported window was returned.";
    const snapshot_deferred = "A live provider session owned the credential; this app did not interfere.";
    const no_saved_snapshot_yet = "No saved snapshot yet";
    const no_saved_snapshot_yet_sentence = "No saved snapshot yet.";
    const no_usage_window_reported = "No usage window reported";
    const service_not_connected = "Application service not connected — this window shows local view state only.";
    const service_local_only = "Local state only: no refresh, account, or reset service is attached.";
    const service_refresh_not_attached = "Refresh service not attached.";
    const service_accounts_not_attached = "Account management service not attached.";
    const service_reset_not_attached = "Reset redemption service not attached.";
    const service_all_attached = "All application services attached.";
    const unrepresentable_local_time = "unrepresentable local time";
    const just_now = "just now";
    const tray_refresh_usage = "Refresh Usage";
    const tray_open_in_settings = "Show Account…";
    const tray_help = "CodexMulti — saved usage and CLI accounts";
    const tray_accounts = "Accounts…";
    const tray_settings = "Settings…";
    const tray_quit = "Quit";
    const tray_refresh_all_accounts = "Refresh All Accounts";
    const tray_no_saved_accounts = "No saved accounts";
    const tray_more_accounts = "Show More Accounts…";
    const tray_one_more_account = "Show 1 More Account…";
    const tray_two_more_accounts = "Show 2 More Accounts…";
    const tray_three_more_accounts = "Show 3 More Accounts…";
    const tray_four_more_accounts = "Show 4 More Accounts…";
    const tray_five_more_accounts = "Show 5 More Accounts…";
    const tray_six_more_accounts = "Show 6 More Accounts…";
    const tray_seven_more_accounts = "Show 7 More Accounts…";
    const tray_eight_more_accounts = "Show 8 More Accounts…";
    const tray_nine_more_accounts = "Show 9 More Accounts…";
    const tray_ten_more_accounts = "Show 10 More Accounts…";
    const tray_eleven_more_accounts = "Show 11 More Accounts…";
    const tray_twelve_more_accounts = "Show 12 More Accounts…";
    const tray_thirteen_more_accounts = "Show 13 More Accounts…";
    const tray_fourteen_more_accounts = "Show 14 More Accounts…";
    const tray_fifteen_more_accounts = "Show 15 More Accounts…";
    const tray_sixteen_more_accounts = "Show 16 More Accounts…";
    const node_missing_reason = "node not found — set Node path in Connection settings";
    const app_version = "Version 0.1.0 (build 0.1.0)";
    const proxy_service_not_installed = "Proxy service is not installed";
    const proxy_direct_routing = "Failover is off. Codex connects directly.";
    const onboarding_add_account = "Add a Codex account";
    const onboarding_install_proxy = "Install the proxy service";
    const onboarding_enable_routing = "Turn on Failover";
    const add_codex = "Add Codex";
    const install_and_start = "Install & Start";
    const repair_proxy_service = "Repair";
    const turn_on_routing = "Turn on routing";
    const proxy_ready = "Ready";
    const proxy_cooldown = "Cooldown";
    const proxy_paused = "Paused";
    const proxy_invalid = "Invalid";
    const proxy_refreshing = "Refreshing";
    const proxy_unknown = "Unknown";
    const none_lower = "none";
    const not_mapped = "Not mapped";
    const active = "Active";
    const not_mapped_saved_account = "Not mapped to a saved Codex account";
    const cooldown_end_not_reported = "cooldown end not reported";
    const credential_needs_attention = "credential needs attention";
    const refreshing_token = "refreshing token…";
    const token_refresh_failed = "Refresh failed · sign in again";
    const token_refresh_retrying = "Token renewal delayed · retrying automatically";
    const proxy_status_unknown = "Proxy status unknown";
    const failover_proxy_reachable = "Failover proxy reachable";
    const proxy_config_mismatch = "Proxy config does not match this app";
    const proxy_unreachable = "Proxy unreachable";
    const proxy_incompatible = "Proxy incompatible for account control";
    const proxy_press_refresh = "Press Refresh to read status v2.";
    const proxy_busy_retry = "Account changes will be applied automatically after current requests finish.";
    const proxy_changes_next_refresh = "Account changes are being applied automatically.";
    const proxy_synchronized = "Saved accounts and proxy mappings are synchronized.";
    const proxy_sync_failed = "The last proxy synchronization failed.";
    const proxy_checking = "Checking proxy status…";
    const proxy_switching = "Switching the proxy cursor…";
    const proxy_pausing = "Pausing new traffic…";
    const proxy_reloading = "Reloading one proxy account…";
    const proxy_clearing_cooldown = "Clearing one proxy cooldown…";
    const proxy_importing = "Importing saved accounts…";
    const proxy_applying_config = "Applying proxy configuration…";
    const failover_status_unknown_settings = "Failover status unknown — open Settings to check";
    const failover_config_mismatch = "Failover · config mismatch";
    const failover_unreachable = "Failover · unreachable";
    const failover_incompatible = "Failover · incompatible";
    const failover_unknown = "Failover · unknown";
    const proxy_unreachable_never_seen = "Proxy unreachable · never seen · Codex switching falls back to local login until the proxy answers.";
    const proxy_incompatible_update = "Proxy incompatible for account control · update the proxy to status v2.";
    const proxy_config_fix_next_refresh = "Proxy config does not match this app · the next refresh will try to fix it after checking the Config path.";
    const node_not_found = "Node: not found — set Node path in Connection settings";
    const node_auto = "Node: auto";
    const no_control_url = "no control URL";
    const cli_path_set = "CLI path set";
    const cli_path_missing = "CLI path missing";
    const config_matches = "config matches";
    const config_not_confirmed = "config not confirmed";
    const refreshing_ellipsis = "Refreshing…";
    const queued = "Queued";
    const updating_ellipsis = "Updating…";
    const sign_in_required = "Sign in required";
    const disabled = "Disabled";
    const proxy_invalid_label = "Proxy invalid";
    const use_in_failover = "Use in failover…";
    const use_in_failover_proxy = "Use in failover proxy…";
    const review_reset_attempt = "Review reset attempt…";
    const retry_reset_attempt = "Retry reset attempt…";
    const account_singular = "account";
    const account_plural = "accounts";
    const not_mapped_to_failover = "Not mapped to failover";
    const auto_refresh_off = "Off — no scheduled provider traffic.";
    const no_accounts = "No accounts";
    const no_cursor_separator = "no cursor · ";
    const row_refreshing_usage = "refreshing usage";
    const row_queued_to_refresh = "queued to refresh";
    const row_sign_in_required = "sign-in required";
    const row_refresh_failed = "refresh failed";
    const row_not_refreshed_yet = "not refreshed yet";
    const row_disabled = "disabled";
    const evidence_no_success = "no successful refresh recorded";
    const evidence_no_attempt = " · no attempt recorded";
    const header_not_refreshed_suffix = " · not refreshed yet";
    const not_refreshed_yet = "Not refreshed yet";
    const active_in_failover_proxy = "Active in failover proxy";
    const codexmulti = "CodexMulti";
    const no_accounts_registered = "No accounts registered yet";
    const codex_accounts_header = "CODEX ACCOUNTS";
    const attention_sign_in_again = "Sign in again to refresh usage. Saved information remains visible.";
    const attention_usage_unavailable = "The provider did not return a usable usage window.";
    const attention_refresh_failed = "Refresh failed. Your previous saved reading is still visible.";
    const no_usage_in_snapshot = "The saved snapshot contains no usage window. No percentage is shown because none was observed.";
    const codex_usage_api = "Codex usage API";
    const reset_unconfirmed = "Reset unconfirmed";
    const reset_unconfirmed_note = "An earlier reset attempt has not settled. Review it before anything else is sent.";
    const reset_not_sent = "Reset not sent";
    const reset_not_sent_note = "The last reset attempt was not sent. Retry runs a fresh preflight and resends it with the same key.";
    const credit_detail_mismatch = "Count reported without matching detail rows";
    const not_reported = "Not reported";
    const reset_time_not_reported_title = "Reset time not reported";
    const connection_disabled_suffix = " · disabled";
    const connection_paused_suffix = " · paused";
    const middle_dot_separator = " · ";
    const language_label = "Language";
    const language_system = "System";
    const language_english = "English";
    const language_korean = "한국어";
    const language_japanese = "日本語";

    const month_names = [_][]const u8{
        "Jan", "Feb", "Mar", "Apr", "May", "Jun",
        "Jul", "Aug", "Sep", "Oct", "Nov", "Dec",
    };
};

const EnglishFormat = struct {
    const reset_phrase = "resets {s}";
    const absolute_datetime = "{d}-{s}-{d:0>2} {d:0>2}:{d:0>2} {s}";
    const countdown_days = "in {d}d {d}h";
    const countdown_hours = "in {d}h {d}m";
    const countdown_minutes = "in {d}m";
    const countdown_seconds = "in {d}s";
    const remaining_days = "{d}d {d}h";
    const remaining_hours = "{d}h {d}m";
    const remaining_minutes = "{d}m";
    const remaining_seconds = "{d}s";
    const ago_minutes = "{d}m ago";
    const ago_hours = "{d}h ago";
    const ago_days = "{d}d ago";
    const short_date = "{s} {d:0>2} ";
    const clock_time = "{d:0>2}:{d:0>2}";
    const medium_datetime = "{s} {d:0>2} {d:0>2}:{d:0>2} {s}";
    const duration_days = "{d}-day";
    const duration_hours = "{d}-hour";
    const duration_minutes = "{d}-minute";
    const proxy_cooldown_until = "until {s} · {s}";
    const proxy_draining_resume = "{d} draining · resume anytime";
    const decimal_usize = "{d}";
    const decimal_u32 = "{d}";
    const tray_failover_last_seen = "Failover last seen · Active {s} · {d} cooling · {s}";
    const tray_proxy_unreachable_last_seen = "Proxy unreachable · last seen {s}";
    const tray_proxy_incompatible_last_seen = "Proxy incompatible · last seen {s}";
    const tray_failover_unknown_last_seen = "Failover status unknown · last seen {s}";
    const failover_active_cooling = "Failover · Active {s} · {d} cooling";
    const proxy_unreachable_banner = "Proxy unreachable · last seen {s} · Codex switching falls back to local login until the proxy answers.";
    const node_path = "Node: {s}";
    const node_auto_path = "Node: auto → {s}";
    const proxy_settings_summary = "{s} · {s} · {s}";
    const percent = "{d}%";
    const window_caption = "{s} · {s}";
    const identity_secondary = " · {s}";
    const freshness_with_ago = "{s} · {s}";
    const cooldown_remaining = "Cooldown {s}";
    const reset_available_action = "Use one reset ({d} left)…";
    const account_access_expanded = "{s}, {s}, {s}, expanded";
    const account_access = "{s}, {s}, {s}";
    const account_group_exhausted = "{d} {s} · {d} exhausted this week";
    const account_group_count = "{d} {s}";
    const codex_group_title = "CODEX · {s}";
    const auto_refresh_traffic = "{d} {s} × {d} refreshes/hour = {d} provider requests/hour.";
    const last_refresh = "Last refresh {s} · {s}";
    const failed_count = "{d} failed";
    const toolbar_proxy_off = "Proxy off · {s}";
    const toolbar_proxy_unreachable = "Proxy unreachable · {s}";
    const toolbar_none_ready_reset = "None ready · next reset in {s}";
    const toolbar_none_ready = "None ready · {s}";
    const toolbar_ready_in_flight = "{d} ready · {d} in flight";
    const toolbar_ready = "{d} ready · {s}";
    const toolbar_pool_suffix = " · pool {d}%";
    const toolbar_proxy_status = "{s} · {s}";
    const toolbar_failed_suffix = " · {d} failed";
    const row_usage_summary = "{d}% · {s}";
    const evidence_last_success = "last success {s}";
    const evidence_last_attempt = " · last attempt {s}";
    const row_tray_status = "{s} — {s}";
    const tray_usage = "{d}% used · {s} · resets {s}";
    const updated = "Updated {s}";
    const failover_proxy_state = "Failover proxy · {s}";
    const header_accounts = "{d} accounts";
    const header_need_sign_in = " · {d} need sign-in";
    const header_unreadable = " · {d} unreadable";
    const header_in_progress = " · {d} in progress";
    const header_updated = " · updated {s}";
    const tray_summary = "Saved usage · {s}";
    const tray_pool = "Pool {d}% left · {d} of {d} usable";
    const default_account_label = "{s} account";
    const numbered_account_label = "{s} {d}";
    const last_good_reading = " Last good reading: {s}.";
    const updated_freshness = "Updated {s} · {s}";
    const active_in_flight = "Active · {d} in flight";
    const cooldown_until = "Cooldown until {s} · {s}";
    const paused_draining = "Paused · {d} draining";
    const credits_available = "{d} available";
    const evidence_deferred = "deferred {s}";
    const evidence_failed = "failed {s} · {s}";
    const token_valid_until = "Token valid until {s}";
};

const Korean = struct {
    const add_account_dialog_title = "Codex 계정 추가";
    const add_account_dialog_explanation = "브라우저에서 로그인하기 전에 계정 이름을 입력하세요.";
    const add_account_dialog_progress = "Codex 계정을 추가하는 중…";
    const add_account_dialog_invalid_label = "계속하려면 계정 이름을 입력하세요.";

    const reset_proxy_clearing = "계정 전환: 이 계정의 프록시 대기 상태를 해제하는 중…";
    const reset_proxy_cleared = "계정 전환: 대기 상태가 해제되었습니다.";
    const reset_proxy_unmapped = "계정 전환: 마지막 확인에서 프록시 계정과 연결되지 않아 대기 상태를 해제하지 못했습니다. 연결된 계정이라면 대기 해제를 사용하세요.";
    const reset_proxy_unreachable = "계정 전환: 프록시에 연결할 수 없어 대기 상태를 해제하지 못했습니다. 상태를 새로 고친 뒤 대기 해제를 사용하세요.";
    const reset_proxy_busy = "계정 전환: 프록시가 다른 작업을 처리 중이라 대기 상태를 해제하지 못했습니다. 대기 해제를 사용하세요.";
    const reset_proxy_failed = "계정 전환: 프록시가 거절하거나 응답하지 않아 대기 상태를 해제하지 못했습니다. 대기 해제를 사용하세요.";
    const reset_only_codex = "리셋은 Codex 계정에서만 사용할 수 있습니다.";
    const reset_no_credit = "이 계정에는 제공자가 확인한 사용 가능한 리셋 크레딧이 없습니다.";
    const reset_prior_pending = "이 계정의 이전 리셋 요청이 아직 완료되지 않았습니다. 먼저 해당 요청의 결과를 확인하세요.";
    const reset_prior_unsent = "이전 리셋 요청이 전송되지 않았습니다. 다시 시도하면 현재 상태를 확인한 뒤 같은 키로 전송합니다.";
    const reset_needs_auth = "리셋을 사용하려면 이 계정에 다시 로그인해야 합니다.";
    const reset_disabled = "이 계정은 사용 중지 상태입니다.";
    const reset_unknown_account = "이 계정은 현재 목록에 없습니다.";
    const reset_service_missing = "리셋 서비스에 연결되지 않았습니다.";
    const reset_settled = "요청이 완료되었습니다. 계정 목록에 제공자가 확인한 사용량과 남은 리셋 수가 표시됩니다.";
    const reset_settled_unsent = "이 요청은 전송되지 않았습니다. 계정 목록에서 리셋 재시도를 선택하면 같은 키로 다시 전송합니다.";
    const reset_pending = "리셋 요청이 접수되어 처리 중입니다. 서비스에서 결과를 확인할 때까지 완료된 상태가 아닙니다.";
    const reset_unsent_service = "전송하지 않았습니다. 리셋 서비스에 연결되지 않았습니다.";
    const reset_unsent_cli = "전송하지 않았습니다. 지원되는 위치에서 제공자 CLI를 찾을 수 없습니다.";
    const reset_unsent_offer = "전송하지 않았습니다. Codex에서 최신 상태를 확인해야 하며, 현재 사용할 수 있는 리셋이 없습니다.";
    const reset_unsent_busy = "전송하지 않았습니다. 이 계정은 이미 다른 작업을 처리 중입니다.";
    const reset_unsent_refused = "전송하지 않았습니다. 서비스가 현재 요청 또는 계정 상태를 허용하지 않았습니다.";
    const reset_unsent_unknown = "전송하지 않았습니다. 서비스에서 이 계정을 찾을 수 없습니다.";
    const reset_unconfirmed_failure = "서비스 오류로 결과를 확인하지 못했습니다. 앱에서 확인한 크레딧 상태에는 변화가 없습니다.";

    const appearance_system = "시스템";
    const appearance_light = "라이트";
    const appearance_dark = "다크";
    const codex_usage_window_label = "표시할 사용량";
    const codex_usage_window_detail = "제공자가 알려 준 사용량 중 표시할 기간을 선택합니다.";
    const codex_model_limits_label = "모델별 한도";
    const codex_model_limits_detail = "계정 상세와 요약에 모델별 사용 한도를 표시합니다.";

    const shell_settings = "설정…";
    const shell_system = "시스템";
    const shell_proxy = "프록시";
    const shell_appearance = "화면 모드";
    const shell_theme = "테마";
    const shell_launch_at_login = "로그인 시 실행";
    const shell_launch_at_login_registration_failed = "등록 실패";
    const shell_auto_refresh = "자동 새로 고침";
    const shell_about = "앱 정보";
    const shell_version = "버전";
    const shell_update_title = "소프트웨어 업데이트";
    const shell_update_check = "업데이트 확인";
    const shell_update_install = "업데이트 후 다시 열기";
    const shell_update_available = "새 업데이트가 있습니다.";
    const shell_update_current = "최신 버전입니다.";
    const shell_update_ready = "새 버전이 있는지 확인할 수 있습니다.";
    const shell_update_pending = "엔진 적용을 취소했습니다. 기존 엔진을 사용 중입니다.";
    const shell_update_apply = "엔진 업데이트 적용";
    const shell_update_check_failed = "업데이트를 확인하지 못했습니다. 다시 시도해 주세요.";
    const shell_update_no_compatible = "이 Mac에서 사용할 수 있는 새 버전이 없습니다.";
    const shell_update_checking = "업데이트 확인 중…";
    const shell_update_preparing = "업데이트 준비 중…";
    const shell_update_downloading = "업데이트 다운로드 중…";
    const shell_update_installing = "설치 후 다시 여는 중…";
    const shell_update_waiting = "진행 중인 요청과 연결이 끝나기를 기다립니다.";
    const shell_update_applying = "프록시 업데이트 적용 중…";
    const shell_update_complete = "업데이트가 완료되었습니다.";
    const shell_update_rollback = "이전 프록시 버전으로 복구했습니다.";
    const shell_update_failed = "업데이트를 복구해야 합니다.";
    const shell_update_recovery = "이전 앱 보기";
    const shell_update_unconfigured = "업데이트 확인은 정식 배포 빌드에서 사용할 수 있습니다.";
    const shell_update_migration = "안전한 업데이트 설정";
    const shell_update_migration_detail = "처음 한 번은 모든 Codex 클라이언트를 종료한 뒤 설정해야 합니다.";
    const shell_update_migration_confirm = "모든 Codex 클라이언트를 종료했습니다";
    const shell_update_cancel = "대기 중인 업데이트 취소";
    const shell_update_off = "요청 완료 후 끄기";
    const shell_update_frozen = "업데이트가 끝날 때까지 계정 변경을 잠시 멈춥니다.";

    const shell_failover_state = "자동 계정 전환 상태";
    const shell_failover_detail = "자동 계정 전환 상세";
    const shell_in_flight = "진행 중";
    const shell_tab_accounts = "계정";
    const shell_tab_settings = "설정";
    const shell_tab_failover = "자동 계정 전환";
    const shell_update_proxy_accounts = "프록시 계정 업데이트";
    const shell_add_codex_menu = "Codex 계정 추가…";
    const shell_refresh_all_help = "모든 계정 새로 고침";
    const shell_status_accessibility = "자동 계정 전환 상태";
    const shell_segment_accessibility = "설정 영역";
    const shell_dismiss_notice = "알림 닫기";
    const shell_retry = "다시 시도";
    const shell_starting = "시작 중…";
    const shell_row_menu_accessibility = "더 많은 작업";
    const shell_row_hint = "계정 상세 보기";
    const shell_reorder_hint = "드래그하여 자동 계정 전환 순서 변경";
    const shell_usage_bar_accessibility = "보고된 사용량";
    const shell_refresh = "새로 고침";
    const shell_sign_in = "로그인…";
    const shell_sign_in_again = "다시 로그인…";
    const shell_pause_in_failover = "자동 전환 대상에서 제외";
    const shell_clear_cooldown = "대기 해제…";
    const shell_move_to_top = "맨 위로 이동";
    const shell_rename = "이름 변경…";
    const shell_remove = "제거…";
    const shell_fact_resets = "초기화 시점";
    const shell_fact_status = "상태";
    const shell_fact_failover = "자동 계정 전환";
    const shell_fact_o_auth_token = "OAuth 토큰";
    const shell_fact_last_refresh = "마지막 새로 고침";
    const shell_fact_reset_credits = "리셋 크레딧";
    const shell_fact_updated = "업데이트 시점";
    const shell_not_applicable = "—";
    const shell_failover_row_menu_accessibility = "자동 계정 전환 작업";
    const shell_use_in_failover = "이 계정으로 전환…";
    const shell_pause = "일시 중지";
    const shell_resume = "재개";
    const shell_resume_in_failover = "자동 전환 대상에 포함";
    const shell_in_flight_suffix = "개 진행 중";
    const shell_status_separator = " · ";
    const shell_use_failover_proxy = "자동 계정 전환 사용";
    const shell_advanced_proxy_controls = "프록시 고급 설정";
    const shell_codex_routing = "Codex 연결 경로";
    const shell_install_and_start = "설치 및 시작";
    const shell_repair_proxy_service = "복구";
    const shell_stop_proxy_service = "프록시 서비스 중지";
    const shell_enable_for_codex = "Codex에 적용";
    const shell_disable_for_codex = "직접 연결로 복구";
    const shell_replace_codex_routing = "Codex 연결 설정 교체";
    const shell_routing_off = "꺼짐";
    const shell_routing_on = "켜짐";
    const shell_routing_conflicting = "설정 충돌";
    const shell_client_quiescence_title = "Codex 작업을 먼저 마쳐 주세요";
    const shell_client_quiescence_message = "모든 Codex 작업을 마치거나 앱을 닫아 주세요. 복구나 중지가 끝날 때까지 새 작업을 시작하지 마세요.";
    const shell_replace_routing_title = "충돌하는 Codex 연결 설정을 교체할까요?";
    const shell_replace_routing_message = "Codex의 연결 설정이 이 프록시와 다릅니다. 앱에 포함된 프록시를 사용하도록 교체할까요?";
    const shell_connection_settings = "연결 설정";
    const shell_field_control_u_r_l = "제어 URL";
    const shell_field_proxy_c_l_i = "CLI 경로";
    const shell_field_config = "설정 파일 경로";
    const shell_field_node_path = "Node 경로";
    const shell_bundled_proxy_c_l_i_default = "내장 프록시 CLI 기본값";
    const shell_bundled_node_default = "내장 Node 기본값";
    const shell_advanced_overrides = "고급 경로 지정";
    const shell_field_proxy_c_l_i_override = "프록시 CLI 경로 (비워 두면 기본값)";
    const shell_field_node_override = "Node 경로 (비워 두면 기본값)";
    const shell_empty_override_help = "내장 기본값을 사용하려면 비워 두세요.";
    const shell_save = "저장";
    const shell_quit = "종료";
    const shell_failover_switch_title_prefix = "“";
    const shell_failover_switch_title_suffix = "” 계정으로 새 요청을 보낼까요?";
    const shell_failover_switch_body_prefix = "새 요청에 사용할 계정을 ";
    const shell_failover_switch_body_suffix = " 계정으로 바꿉니다.";
    const shell_failover_switch_muted = "인증 파일을 복사하거나 설치하지 않습니다. 이미 진행 중인 요청은 현재 계정에서 계속 처리됩니다.";
    const shell_use_account = "이 계정 사용";
    const shell_clear_cooldown_title_prefix = "“";
    const shell_clear_cooldown_title_suffix = "” 계정의 대기를 해제할까요?";
    const shell_clear_cooldown_body = "프록시에서 이 계정을 바로 다시 사용합니다. 다른 곳에서 한도를 초기화한 경우에만 실행하세요.";
    const shell_clear_cooldown_muted = "실제로 한도가 초기화되지 않았다면 다음 요청이 거절되고 제공자의 응답에 따라 다시 대기 상태가 됩니다. 지금 제공자에게 요청을 보내지는 않습니다.";
    const shell_clear_cooldown_confirm = "대기 해제";
    const shell_rename_title = "계정 이름 변경";
    const shell_rename_muted = "CodexMulti에 표시되는 이름만 바뀝니다.";
    const shell_account_label = "계정 이름";
    const shell_remove_title = "계정을 제거할까요?";
    const shell_remove_body_suffix = " 계정을 CodexMulti에서 제거합니다.";
    const shell_remove_mapped_muted = "이 계정의 현재 요청이 끝나면 자동으로 삭제합니다.";
    const shell_remove_plain_muted = "저장된 사용량 정보도 제거합니다. OpenAI 계정 자체는 삭제하지 않습니다.";
    const shell_refresh_drain_status = "진행 상태 새로 고침";
    const shell_finish_removal = "제거 완료";
    const shell_remove_and_sync = "제거 및 동기화";
    const shell_remove_confirm = "제거";
    const shell_reset_title = "Codex 리셋 1개를 사용할까요?";
    const shell_reset_retry_muted = "같은 요청의 결과를 다시 확인합니다. 리셋을 추가로 사용하지 않습니다.";
    const shell_close = "닫기";
    const shell_retry_same_request = "같은 요청 다시 확인";
    const shell_reset_body_prefix = "리셋 크레딧 1개를 사용할 계정: ";
    const shell_reset_body_suffix = ". 프록시에서 대기 중이면 리셋 완료 후 대기 상태가 해제됩니다.";
    const shell_reset_available_suffix = "개 사용 가능 · ";
    const shell_reset_next_reset_infix = " · 다음 초기화 ";
    const shell_reset_acknowledge = "되돌릴 수 없음을 이해했습니다";
    const shell_use_one_reset = "리셋 1개 사용";
    const shell_cancel = "취소";
    const shell_auto_refresh_off = "꺼짐";
    const shell_fifteen_minutes = "15분";
    const shell_thirty_minutes = "30분";
    const shell_one_hour = "1시간";
    const shell_usage_auto = "자동";
    const shell_usage_weekly = "주간";
    const shell_usage_session = "세션";
    const shell_expanded = "펼침";
    const shell_collapsed = "접힘";
    const proxy_update_pending = "자동 계정 전환 사용 중 · 현재 요청이 끝나면 자동으로 업데이트합니다.";
    const proxy_enabling_pending = "현재 요청이 끝나면 자동 계정 전환을 켭니다.";
    const proxy_disabling_pending = "현재 요청이 끝나면 자동 계정 전환을 끕니다.";
    const proxy_retrying = "자동 계정 전환 연결에 실패했습니다. 다시 시도합니다.";
    const proxy_sign_in_first = "Codex 계정을 추가하면 자동 계정 전환을 사용할 수 있습니다.";
    const proxy_accounts_syncing = "현재 요청이 끝나면 계정 변경을 자동으로 반영합니다.";
    const proxy_running_routing = "자동 계정 전환 사용 중 · 추가한 계정은 자동으로 반영됩니다.";
    const proxy_unavailable_routing = "자동 계정 전환 연결을 복구하고 있습니다. 끄면 Codex에 직접 연결합니다.";
    const proxy_conflicting_routing = "Codex의 다른 연결 설정을 사용 중입니다. 자동 계정 전환을 켜면 변경할 수 있습니다.";
    const proxy_applying_switch = "자동 계정 전환 설정을 적용하고 있습니다…";
    const proxy_settings_changed = "프록시 설정이 바뀌었습니다. 복구가 필요합니다.";
    const proxy_service_starting = "프록시 서비스 변경 시작 중";
    const proxy_waiting_requests = "프록시 요청이 끝나기를 기다리는 중";
    const proxy_service_stale = "내장 프록시 파일이나 설치 기록이 바뀌었습니다. 복구가 필요합니다.";
    const proxy_service_running = "내장 프록시 서비스가 실행 중입니다.";
    const proxy_service_unreachable = "프록시 서비스가 설치되어 있지만 연결할 수 없습니다.";
    const proxy_loaded_unreachable = "프록시가 응답하지 않습니다. 복구하거나 프록시 사용을 꺼서 직접 연결하세요.";

    const plan_pro_20x = "Pro 20x";
    const plan_pro_5x = "Pro 5x";
    const reset_time_not_reported = "재설정 시간 미보고";
    const reset_passed_refresh = "재설정 시각 지남 · 새로 고침";
    const countdown_passed_refresh = "재설정 시각 지남 — 새로 고쳐 확인";
    const provider_unsupported = "지원 안 함";
    const provider_codex = "Codex";
    const window_weekly = "주간";
    const window_session = "세션";
    const window_daily = "일간";
    const window_monthly = "월간";
    const window_hourly = "시간별";
    const window_codex = "Codex";
    const freshness_never = "새로 고친 적 없음";
    const freshness_as_of = "마지막 새로 고침 성공 기준";
    const freshness_saved_snapshot = "저장된 스냅샷";
    const freshness_refresh_failed = "새로 고침 실패";
    const freshness_reauthentication_required = "재인증 필요";
    const freshness_usage_unavailable = "사용량 확인 불가";
    const freshness_refresh_deferred = "새로 고침 보류";
    const freshness_reset_passed = "재설정 시각 지남 — 새로 고쳐 확인";
    const freshness_never_lower = "새로 고친 적 없음";
    const freshness_as_of_lower = "마지막 새로 고침 성공 기준";
    const freshness_saved_snapshot_lower = "저장된 스냅샷";
    const freshness_refresh_failed_lower = "새로 고침 실패";
    const freshness_reauthentication_required_lower = "재인증 필요";
    const freshness_usage_unavailable_lower = "사용량 확인 불가";
    const freshness_refresh_deferred_lower = "새로 고침 보류";
    const freshness_reset_passed_lower = "재설정 시각 지남 — 새로 고쳐 확인";
    const attempt_reason_helper_closed = "도우미 종료";
    const attempt_reason_helper_unavailable = "도우미 사용 불가";
    const attempt_reason_cli_too_old = "Codex CLI 버전 낮음";
    const attempt_reason_timed_out = "시간 초과";
    const attempt_reason_canceled = "취소됨";
    const attempt_reason_refresh_rejected = "새로 고침 거부됨";
    const attempt_reason_malformed_reply = "잘못된 응답";
    const attempt_reason_sign_in_required = "로그인 필요";
    const attempt_reason_workspace_invalid = "잘못된 작업 공간";
    const attempt_reason_wrong_workspace = "다른 작업 공간";
    const attempt_reason_no_usage_window = "사용량 기간 없음";
    const attempt_reason_incomplete_reading = "불완전한 측정값";
    const attempt_reason_sign_in_unsupported = "로그인 미지원";
    const attempt_reason_sign_in_could_not_start = "로그인 시작 실패";
    const attempt_reason_sign_in_timed_out = "로그인 시간 초과";
    const attempt_reason_sign_in_canceled = "로그인 취소됨";
    const attempt_reason_sign_in_handoff_failed = "로그인 전달 실패";
    const attempt_reason_sign_in_rejected = "로그인 거부됨";
    const attempt_reason_sign_in_output_unclear = "로그인 결과 불명확";
    const attempt_reason_credential_not_saved = "자격 증명 저장 안 됨";
    const attempt_reason_credential_incomplete = "불완전한 자격 증명";
    const attempt_reason_keychain_repair_needed = "키체인 복구 필요";
    const attempt_reason_account_unknown = "알 수 없는 계정";
    const attempt_reason_account_busy = "계정 사용 중";
    const attempt_reason_account_disabled = "계정 비활성화됨";
    const attempt_reason_provider_mismatch = "제공자 불일치";
    const attempt_reason_reset_unconfirmed = "재설정 미확인";
    const attempt_reason_reset_key_invalid = "잘못된 재설정 키";
    const attempt_reason_reset_outcome_unknown = "재설정 결과 불명";
    const attempt_reason_refresh_failed = "새로 고침 실패";
    const attempt_message_helper_closed = "Codex 도우미가 응답 전에 종료됨. 다시 새로 고침. 반복되면 다시 로그인.";
    const attempt_message_helper_unavailable = "Codex 도우미 사용 불가. Codex CLI 실행 가능 여부 확인 후 재시도.";
    const attempt_message_cli_unsupported = "이 Codex CLI는 사용량 판독을 지원하지 않음. Codex 업데이트 후 재시도.";
    const attempt_message_refresh_timeout = "제공자가 제시간에 응답하지 않음. 이전 측정값을 계속 표시.";
    const attempt_message_sign_in_required = "로그인이 더 이상 유효하지 않음. 사용량을 새로 고치려면 다시 로그인.";
    const attempt_message_wrong_workspace = "Codex가 다른 계정 작업 공간을 열었음. 이 계정에 다시 로그인.";
    const attempt_message_usage_unsupported = "제공자가 사용할 수 있는 사용량 기간을 반환하지 않음.";
    const attempt_message_usage_incomplete = "제공자가 불완전한 측정값을 반환함. 마지막 전체 값을 계속 표시.";
    const attempt_message_login_import_unavailable = "로그인은 끝났지만 자격 증명을 이 계정에 저장하지 못함. 다시 로그인.";
    const attempt_message_login_import_incomplete = "로그인에서 재사용 가능한 전체 자격 증명을 반환하지 않음. 다시 로그인.";
    const attempt_message_login_rejected = "Codex가 로그인을 승인하지 않음. 재시도하고 브라우저 확인 완료.";
    const attempt_message_login_timeout = "브라우저 확인 전에 로그인 창이 만료됨. 다시 시도.";
    const attempt_message_login_io = "CodexMulti가 보안 로그인 전달을 완료하지 못함. 다시 시도.";
    const attempt_message_keychain_repair = "이전 자격 증명에 일회성 키체인 접근 복구 필요. 다시 로그인을 선택해 새 보호 사본 저장. 기존 항목은 유지됨.";
    const attempt_message_refresh_failed = "새로 고침 실패. 이전에 저장된 측정값을 계속 표시.";
    const auth_connected = "연결됨";
    const auth_reauthentication_required = "재인증 필요";
    const auth_unavailable = "사용 불가";
    const snapshot_none = "이 계정에 저장된 스냅샷 없음.";
    const snapshot_fresh = "전체 판독 성공 결과로 저장됨.";
    const snapshot_stale = "이전에 저장됨. 현재 상태임을 보장하지 않음.";
    const snapshot_partial = "부분 판독 결과로 저장됨. 누락 필드는 그대로 유지.";
    const snapshot_reauthentication_required = "자격 증명이 중단되기 전에 저장됨.";
    const snapshot_error_state = "가장 최근 실패 전에 저장됨.";
    const snapshot_unavailable = "인증은 성공했지만 지원되는 기간이 반환되지 않음.";
    const snapshot_deferred = "실시간 제공자 세션이 자격 증명을 사용 중이어서 앱이 개입하지 않음.";
    const no_saved_snapshot_yet = "저장된 스냅샷 없음";
    const no_saved_snapshot_yet_sentence = "저장된 스냅샷 없음.";
    const no_usage_window_reported = "보고된 사용량 기간 없음";
    const service_not_connected = "앱 서비스 연결 안 됨 — 이 창에는 로컬 보기 상태만 표시.";
    const service_local_only = "로컬 상태만 표시: 새로 고침, 계정, 재설정 서비스 연결 안 됨.";
    const service_refresh_not_attached = "새로 고침 서비스 연결 안 됨.";
    const service_accounts_not_attached = "계정 관리 서비스 연결 안 됨.";
    const service_reset_not_attached = "재설정 사용 서비스 연결 안 됨.";
    const service_all_attached = "모든 앱 서비스 연결됨.";
    const unrepresentable_local_time = "표시할 수 없는 현지 시각";
    const just_now = "방금";
    const tray_refresh_usage = "사용량 새로 고침";
    const tray_open_in_settings = "계정 상세 보기…";
    const tray_help = "CodexMulti — 계정 및 사용량";
    const tray_accounts = "계정…";
    const tray_settings = "설정…";
    const tray_quit = "종료";
    const tray_refresh_all_accounts = "모든 계정 새로 고침";
    const tray_no_saved_accounts = "저장된 계정 없음";
    const tray_more_accounts = "계정 더 보기…";
    const tray_one_more_account = "계정 1개 더 보기…";
    const tray_two_more_accounts = "계정 2개 더 보기…";
    const tray_three_more_accounts = "계정 3개 더 보기…";
    const tray_four_more_accounts = "계정 4개 더 보기…";
    const tray_five_more_accounts = "계정 5개 더 보기…";
    const tray_six_more_accounts = "계정 6개 더 보기…";
    const tray_seven_more_accounts = "계정 7개 더 보기…";
    const tray_eight_more_accounts = "계정 8개 더 보기…";
    const tray_nine_more_accounts = "계정 9개 더 보기…";
    const tray_ten_more_accounts = "계정 10개 더 보기…";
    const tray_eleven_more_accounts = "계정 11개 더 보기…";
    const tray_twelve_more_accounts = "계정 12개 더 보기…";
    const tray_thirteen_more_accounts = "계정 13개 더 보기…";
    const tray_fourteen_more_accounts = "계정 14개 더 보기…";
    const tray_fifteen_more_accounts = "계정 15개 더 보기…";
    const tray_sixteen_more_accounts = "계정 16개 더 보기…";
    const node_missing_reason = "node를 찾을 수 없음 — 연결 설정에서 Node 경로 지정";
    const app_version = "버전 0.1.0 (빌드 0.1.0)";
    const proxy_service_not_installed = "프록시 서비스 설치 안 됨";
    const proxy_direct_routing = "자동 계정 전환 꺼짐 · Codex에 직접 연결합니다.";
    const onboarding_add_account = "Codex 계정 추가";
    const onboarding_install_proxy = "프록시 서비스 설치";
    const onboarding_enable_routing = "자동 계정 전환 켜기";
    const add_codex = "Codex 추가";
    const install_and_start = "설치 및 시작";
    const repair_proxy_service = "복구";
    const turn_on_routing = "라우팅 켜기";
    const proxy_ready = "준비됨";
    const proxy_cooldown = "대기 중";
    const proxy_paused = "제외됨";
    const proxy_invalid = "잘못됨";
    const proxy_refreshing = "새로 고치는 중";
    const proxy_unknown = "알 수 없음";
    const none_lower = "없음";
    const not_mapped = "매핑 안 됨";
    const active = "활성";
    const not_mapped_saved_account = "저장된 Codex 계정에 매핑 안 됨";
    const cooldown_end_not_reported = "대기 종료 시각 미보고";
    const credential_needs_attention = "자격 증명 확인 필요";
    const refreshing_token = "토큰 새로 고치는 중…";
    const token_refresh_failed = "새로 고침 실패 · 다시 로그인";
    const token_refresh_retrying = "토큰 갱신 지연 · 자동 재시도 예정";
    const proxy_status_unknown = "프록시 상태 알 수 없음";
    const failover_proxy_reachable = "자동 계정 전환 프록시 연결 가능";
    const proxy_config_mismatch = "프록시 설정이 이 앱과 일치하지 않음";
    const proxy_unreachable = "프록시 연결 불가";
    const proxy_incompatible = "계정 제어와 호환되지 않는 프록시";
    const proxy_press_refresh = "새로 고침을 눌러 상태 v2 확인.";
    const proxy_busy_retry = "현재 요청이 끝나면 계정 변경을 자동으로 반영합니다.";
    const proxy_changes_next_refresh = "계정 변경을 자동으로 반영하고 있습니다.";
    const proxy_synchronized = "저장된 계정과 프록시 매핑 동기화됨.";
    const proxy_sync_failed = "마지막 프록시 동기화 실패.";
    const proxy_checking = "프록시 상태 확인 중…";
    const proxy_switching = "새 요청에 사용할 계정을 바꾸는 중…";
    const proxy_pausing = "자동 전환 대상에서 제외하는 중…";
    const proxy_reloading = "프록시 계정 하나 다시 불러오는 중…";
    const proxy_clearing_cooldown = "프록시 대기 하나 해제 중…";
    const proxy_importing = "저장된 계정 가져오는 중…";
    const proxy_applying_config = "프록시 설정 적용 중…";
    const failover_status_unknown_settings = "자동 계정 전환 상태 알 수 없음 — 설정에서 확인";
    const failover_config_mismatch = "자동 계정 전환 · 설정 불일치";
    const failover_unreachable = "자동 계정 전환 · 연결 불가";
    const failover_incompatible = "자동 계정 전환 · 호환 안 됨";
    const failover_unknown = "자동 계정 전환 · 알 수 없음";
    const proxy_unreachable_never_seen = "프록시 연결 불가 · 연결 기록 없음 · 응답 전까지 Codex 전환은 로컬 로그인 사용.";
    const proxy_incompatible_update = "계정 제어와 호환되지 않는 프록시 · 상태 v2로 업데이트 필요.";
    const proxy_config_fix_next_refresh = "프록시 설정이 앱과 일치하지 않음 · 다음 새로 고침에서 Config 경로 확인 후 복구 시도.";
    const node_not_found = "Node: 찾을 수 없음 — 연결 설정에서 Node 경로 지정";
    const node_auto = "Node: 자동";
    const no_control_url = "제어 URL 없음";
    const cli_path_set = "CLI 경로 설정됨";
    const cli_path_missing = "CLI 경로 없음";
    const config_matches = "설정 일치";
    const config_not_confirmed = "설정 미확인";
    const refreshing_ellipsis = "새로 고치는 중…";
    const queued = "대기열";
    const updating_ellipsis = "업데이트 중…";
    const sign_in_required = "로그인 필요";
    const disabled = "비활성화됨";
    const proxy_invalid_label = "잘못된 프록시";
    const use_in_failover = "이 계정으로 전환…";
    const use_in_failover_proxy = "이 계정으로 전환…";
    const review_reset_attempt = "재설정 시도 검토…";
    const retry_reset_attempt = "재설정 다시 시도…";
    const account_singular = "계정";
    const account_plural = "계정";
    const not_mapped_to_failover = "자동 전환 대상에 연결되지 않음";
    const auto_refresh_off = "꺼짐 — 예약된 제공자 트래픽 없음.";
    const no_accounts = "계정 없음";
    const no_cursor_separator = "커서 없음 · ";
    const row_refreshing_usage = "사용량 새로 고치는 중";
    const row_queued_to_refresh = "새로 고침 대기 중";
    const row_sign_in_required = "로그인 필요";
    const row_refresh_failed = "새로 고침 실패";
    const row_not_refreshed_yet = "아직 새로 고치지 않음";
    const row_disabled = "비활성화됨";
    const evidence_no_success = "새로 고침 성공 기록 없음";
    const evidence_no_attempt = " · 시도 기록 없음";
    const header_not_refreshed_suffix = " · 아직 새로 고치지 않음";
    const not_refreshed_yet = "아직 새로 고치지 않음";
    const active_in_failover_proxy = "현재 요청에 사용 중";
    const codexmulti = "CodexMulti";
    const no_accounts_registered = "등록된 계정 없음";
    const codex_accounts_header = "CODEX 계정";
    const attention_sign_in_again = "사용량을 새로 고치려면 다시 로그인. 저장된 정보는 계속 표시.";
    const attention_usage_unavailable = "제공자가 사용할 수 있는 사용량 기간을 반환하지 않음.";
    const attention_refresh_failed = "새로 고침 실패. 이전에 저장된 측정값을 계속 표시.";
    const no_usage_in_snapshot = "저장된 스냅샷에 사용량 기간 없음. 관측값이 없어 백분율 표시 안 함.";
    const codex_usage_api = "Codex 사용량 API";
    const reset_unconfirmed = "재설정 미확인";
    const reset_unconfirmed_note = "이전 재설정 시도가 아직 완료되지 않음. 다른 작업 전 검토 필요.";
    const reset_not_sent = "재설정 전송 안 됨";
    const reset_not_sent_note = "마지막 재설정 시도가 전송되지 않음. 재시도 시 새 사전 점검 후 같은 키로 다시 전송.";
    const credit_detail_mismatch = "보고된 수량과 세부 항목 수 불일치";
    const not_reported = "미보고";
    const reset_time_not_reported_title = "재설정 시간 미보고";
    const connection_disabled_suffix = " · 비활성화됨";
    const connection_paused_suffix = " · 일시 정지됨";
    const middle_dot_separator = " · ";
    const language_label = "언어";
    const language_system = "시스템";
    const language_english = "English";
    const language_korean = "한국어";
    const language_japanese = "日本語";

    const month_names = [_][]const u8{
        "Jan", "Feb", "Mar", "Apr", "May", "Jun",
        "Jul", "Aug", "Sep", "Oct", "Nov", "Dec",
    };
};

const KoreanFormat = struct {
    const reset_phrase = "{s} 재설정";
    const absolute_datetime = "{d}-{s}-{d:0>2} {d:0>2}:{d:0>2} {s}";
    const countdown_days = "{d}일 {d}시간 후";
    const countdown_hours = "{d}시간 {d}분 후";
    const countdown_minutes = "{d}분 후";
    const countdown_seconds = "{d}초 후";
    const remaining_days = "{d}일 {d}시간";
    const remaining_hours = "{d}시간 {d}분";
    const remaining_minutes = "{d}분";
    const remaining_seconds = "{d}초";
    const ago_minutes = "{d}분 전";
    const ago_hours = "{d}시간 전";
    const ago_days = "{d}일 전";
    const short_date = "{s} {d:0>2} ";
    const clock_time = "{d:0>2}:{d:0>2}";
    const medium_datetime = "{s} {d:0>2} {d:0>2}:{d:0>2} {s}";
    const duration_days = "{d}일";
    const duration_hours = "{d}시간";
    const duration_minutes = "{d}분";
    const proxy_cooldown_until = "{s}까지 · {s}";
    const proxy_draining_resume = "기존 요청 {d}개 처리 중 · 다시 포함 가능";
    const decimal_usize = "{d}";
    const decimal_u32 = "{d}";
    const tray_failover_last_seen = "자동 계정 전환 마지막 확인 · 활성 {s} · {d}개 대기 · {s}";
    const tray_proxy_unreachable_last_seen = "프록시 연결 불가 · 마지막 확인 {s}";
    const tray_proxy_incompatible_last_seen = "프록시 호환 안 됨 · 마지막 확인 {s}";
    const tray_failover_unknown_last_seen = "자동 계정 전환 상태 알 수 없음 · 마지막 확인 {s}";
    const failover_active_cooling = "자동 계정 전환 · 활성 {s} · {d}개 대기";
    const proxy_unreachable_banner = "프록시 연결 불가 · 마지막 확인 {s} · 응답 전까지 Codex 전환은 로컬 로그인 사용.";
    const node_path = "Node: {s}";
    const node_auto_path = "Node: 자동 → {s}";
    const proxy_settings_summary = "{s} · {s} · {s}";
    const percent = "{d}%";
    const window_caption = "{s} · {s}";
    const identity_secondary = " · {s}";
    const freshness_with_ago = "{s} · {s}";
    const cooldown_remaining = "대기 {s}";
    const reset_available_action = "재설정 1개 사용({d}개 남음)…";
    const account_access_expanded = "{s}, {s}, {s}, 펼쳐짐";
    const account_access = "{s}, {s}, {s}";
    const account_group_exhausted = "{d}개 {s} · 이번 주 {d}개 소진";
    const account_group_count = "{d}개 {s}";
    const codex_group_title = "CODEX · {s}";
    const auto_refresh_traffic = "{d}개 {s} × 시간당 {d}회 새로 고침 = 시간당 제공자 요청 {d}회.";
    const last_refresh = "마지막 새로 고침 {s} · {s}";
    const failed_count = "{d}개 실패";
    const toolbar_proxy_off = "프록시 꺼짐 · {s}";
    const toolbar_proxy_unreachable = "프록시 연결 불가 · {s}";
    const toolbar_none_ready_reset = "준비된 계정 없음 · 다음 재설정까지 {s}";
    const toolbar_none_ready = "준비된 계정 없음 · {s}";
    const toolbar_ready_in_flight = "{d}개 준비됨 · {d}개 처리 중";
    const toolbar_ready = "{d}개 준비됨 · {s}";
    const toolbar_pool_suffix = " · 풀 {d}%";
    const toolbar_proxy_status = "{s} · {s}";
    const toolbar_failed_suffix = " · {d}개 실패";
    const row_usage_summary = "{d}% · {s}";
    const evidence_last_success = "마지막 성공 {s}";
    const evidence_last_attempt = " · 마지막 시도 {s}";
    const row_tray_status = "{s} — {s}";
    const tray_usage = "{d}% 사용 · {s} · {s} 재설정";
    const updated = "업데이트 {s}";
    const failover_proxy_state = "자동 계정 전환 프록시 · {s}";
    const header_accounts = "계정 {d}개";
    const header_need_sign_in = " · {d}개 로그인 필요";
    const header_unreadable = " · {d}개 판독 불가";
    const header_in_progress = " · {d}개 진행 중";
    const header_updated = " · 업데이트 {s}";
    const tray_summary = "저장된 사용량 · {s}";
    const tray_pool = "풀 {d}% 남음 · {d}/{d}개 사용 가능";
    const default_account_label = "{s} 계정";
    const numbered_account_label = "{s} {d}";
    const last_good_reading = " 마지막 정상 측정값: {s}.";
    const updated_freshness = "업데이트 {s} · {s}";
    const active_in_flight = "활성 · {d}개 처리 중";
    const cooldown_until = "{s}까지 대기 · {s}";
    const paused_draining = "제외됨 · 기존 요청 {d}개 처리 중";
    const credits_available = "{d}개 사용 가능";
    const evidence_deferred = "{s} 보류";
    const evidence_failed = "{s} 실패 · {s}";
    const token_valid_until = "토큰 유효 기한 {s}";
};

const english_static = blk: {
    const fields = std.meta.fields(StaticKey);
    var values: [fields.len][]const u8 = undefined;
    for (fields, 0..) |field, index| {
        values[index] = @field(English, field.name);
    }
    break :blk values;
};

const korean_static = blk: {
    const fields = std.meta.fields(StaticKey);
    var values: [fields.len][]const u8 = undefined;
    for (fields, 0..) |field, index| {
        values[index] = @field(Korean, field.name);
    }
    break :blk values;
};

const japanese_static = blk: {
    const fields = std.meta.fields(StaticKey);
    var values: [fields.len][]const u8 = undefined;
    for (fields, 0..) |field, index| {
        values[index] = @field(Japanese, field.name);
    }
    break :blk values;
};

comptime {
    for (std.meta.fields(StaticKey)) |field| {
        if (!@hasDecl(English, field.name)) @compileError("missing English static string: " ++ field.name);
        if (!@hasDecl(Korean, field.name)) @compileError("missing Korean static string: " ++ field.name);
        if (!@hasDecl(Japanese, field.name)) @compileError("missing Japanese static string: " ++ field.name);
    }
    for (std.meta.fields(FormatKey)) |field| {
        if (!@hasDecl(EnglishFormat, field.name)) @compileError("missing English format string: " ++ field.name);
        if (!@hasDecl(KoreanFormat, field.name)) @compileError("missing Korean format string: " ++ field.name);
        if (!@hasDecl(JapaneseFormat, field.name)) @compileError("missing Japanese format string: " ++ field.name);
    }
}

test "F18 Korean catalog covers every key and preserves date and time formats" {
    try std.testing.expectEqual([4]Language{ .system, .en, .ko, .ja }, supported_languages);
    try std.testing.expectEqualStrings("Never refreshed", system.text(.freshness_never));
    try std.testing.expectEqualStrings("새로 고친 적 없음", catalog(.ko).text(.freshness_never));
    var buffer: [64]u8 = undefined;
    var writer = std.Io.Writer.fixed(&buffer);
    catalog(.ko).write(&writer, .ago_days, .{@as(i64, 3)});
    try std.testing.expectEqualStrings("3일 전", writer.buffered());

    var datetime_buffer: [64]u8 = undefined;
    var datetime_writer = std.Io.Writer.fixed(&datetime_buffer);
    catalog(.ko).write(&datetime_writer, .absolute_datetime, .{ 2026, "Jul", 25, 12, 0, "KST" });
    try std.testing.expectEqualStrings("2026-Jul-25 12:00 KST", datetime_writer.buffered());
}

test "Japanese catalog renders settings durations and dates without English fallbacks" {
    for (japanese_static) |value| {
        try std.testing.expect(value.len != 0);
        try std.testing.expect(std.unicode.utf8ValidateSlice(value));
    }
    try std.testing.expectEqualStrings("言語", japanese.text(.language_label));
    try std.testing.expectEqualStrings("日本語", japanese.text(.language_japanese));
    try std.testing.expectEqualStrings("Failoverを使用", japanese.translateEnglish(english.text(.shell_use_failover_proxy)));
    var buffer: [128]u8 = undefined;
    var writer = std.Io.Writer.fixed(&buffer);
    japanese.write(&writer, .countdown_hours, .{ @as(i64, 2), @as(i64, 15) });
    try std.testing.expectEqualStrings("2時間15分後", writer.buffered());
    writer = std.Io.Writer.fixed(&buffer);
    japanese.write(&writer, .absolute_datetime, .{ 2026, japanese.monthName(8), 12, 15, 30, "JST" });
    try std.testing.expectEqualStrings("2026年9月12日 15:30 JST", writer.buffered());
}
