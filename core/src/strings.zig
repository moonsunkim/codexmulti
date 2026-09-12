const std = @import("std");

pub const Language = enum { system };

pub const supported_languages = [_]Language{.system};
pub const month_count = English.month_names.len;

pub const StaticKey = enum {
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

    pub fn text(self: Catalog, key: StaticKey) []const u8 {
        return switch (self.language) {
            .system => english_static[@intFromEnum(key)],
        };
    }

    pub fn write(self: Catalog, writer: *std.Io.Writer, comptime key: FormatKey, args: FormatArgs(key)) void {
        switch (self.language) {
            .system => writer.print(@field(EnglishFormat, @tagName(key)), args) catch {},
        }
    }

    pub fn monthName(self: Catalog, index: usize) []const u8 {
        return switch (self.language) {
            .system => English.month_names[index],
        };
    }
};

pub fn catalog(language: Language) Catalog {
    return .{ .language = language };
}

pub const system = catalog(.system);

const English = struct {
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
    const tray_settings = "Settings…";
    const tray_quit = "Quit";
    const tray_refresh_all_accounts = "Refresh All Accounts";
    const tray_no_saved_accounts = "No saved accounts";
    const tray_more_accounts = "More accounts in Settings…";
    const tray_one_more_account = "1 more account in Settings…";
    const tray_two_more_accounts = "2 more accounts in Settings…";
    const tray_three_more_accounts = "3 more accounts in Settings…";
    const tray_four_more_accounts = "4 more accounts in Settings…";
    const tray_five_more_accounts = "5 more accounts in Settings…";
    const tray_six_more_accounts = "6 more accounts in Settings…";
    const tray_seven_more_accounts = "7 more accounts in Settings…";
    const tray_eight_more_accounts = "8 more accounts in Settings…";
    const tray_nine_more_accounts = "9 more accounts in Settings…";
    const tray_ten_more_accounts = "10 more accounts in Settings…";
    const tray_eleven_more_accounts = "11 more accounts in Settings…";
    const tray_twelve_more_accounts = "12 more accounts in Settings…";
    const tray_thirteen_more_accounts = "13 more accounts in Settings…";
    const tray_fourteen_more_accounts = "14 more accounts in Settings…";
    const tray_fifteen_more_accounts = "15 more accounts in Settings…";
    const tray_sixteen_more_accounts = "16 more accounts in Settings…";
    const node_missing_reason = "node not found — set Node path in Connection settings";
    const app_version = "Version 0.1.0 (build 0.1.0)";
    const proxy_service_not_installed = "Proxy service is not installed";
    const proxy_direct_routing = "Codex routes directly; the failover proxy is off.";
    const onboarding_add_account = "Add a Codex account";
    const onboarding_install_proxy = "Install the proxy service";
    const onboarding_enable_routing = "Turn on Codex routing";
    const add_codex = "Add Codex";
    const install_and_start = "Install & Start";
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
    const proxy_status_unknown = "Proxy status unknown";
    const failover_proxy_reachable = "Failover proxy reachable";
    const proxy_config_mismatch = "Proxy config does not match this app";
    const proxy_unreachable = "Proxy unreachable";
    const proxy_incompatible = "Proxy incompatible for account control";
    const proxy_press_refresh = "Press Refresh to read status v2.";
    const proxy_busy_retry = "The proxy was busy · account changes will be retried on the next refresh.";
    const proxy_changes_next_refresh = "Account changes reach the proxy on the next refresh.";
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

const english_static = blk: {
    const fields = std.meta.fields(StaticKey);
    var values: [fields.len][]const u8 = undefined;
    for (fields, 0..) |field, index| {
        values[index] = @field(English, field.name);
    }
    break :blk values;
};

comptime {
    for (std.meta.fields(StaticKey)) |field| {
        if (!@hasDecl(English, field.name)) @compileError("missing English static string: " ++ field.name);
    }
    for (std.meta.fields(FormatKey)) |field| {
        if (!@hasDecl(EnglishFormat, field.name)) @compileError("missing English format string: " ++ field.name);
    }
}

test "catalog exposes the supported system language and typed formatting" {
    try std.testing.expectEqual([1]Language{.system}, supported_languages);
    try std.testing.expectEqualStrings("Never refreshed", system.text(.freshness_never));
    var buffer: [64]u8 = undefined;
    var writer = std.Io.Writer.fixed(&buffer);
    system.write(&writer, .ago_days, .{@as(i64, 3)});
    try std.testing.expectEqualStrings("3d ago", writer.buffered());
}
