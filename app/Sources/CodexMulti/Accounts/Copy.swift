import Foundation
import CMCore

private final class ShellCopyLanguage: @unchecked Sendable {
    private let lock = NSLock()
    private var value: UInt8 = 0

    func set(_ language: UInt8) { lock.lock(); defer { lock.unlock() }; value = language }
    func get() -> UInt8 { lock.lock(); defer { lock.unlock() }; return value }
}

enum Copy {
    private static let language = ShellCopyLanguage()

    static func setLanguage(_ selection: Language) {
        let resolved = selection == .system ? SystemLanguageResolver.current : selection
        language.set(resolved == .ko ? 1 : 0)
    }

    static func text(_ key: String, fallback: String) -> String {
        var buffer = [UInt8](repeating: 0, count: 2048)
        let count = key.withCString { keyBytes in
            buffer.withUnsafeMutableBytes { output in
                cm_copy_text(language.get(), keyBytes, key.utf8.count,
                             output.bindMemory(to: CChar.self).baseAddress, output.count)
            }
        }
        guard count > 0, count <= buffer.count else { return fallback }
        return String(decoding: buffer.prefix(count), as: UTF8.self)
    }

    static var settings: String { text("shell_settings", fallback: "Settings…") }
    static var system: String { text("shell_system", fallback: "System") }
    static var proxy: String { text("shell_proxy", fallback: "Proxy") }
    static var appearance: String { text("shell_appearance", fallback: "Appearance") }
    static var theme: String { text("shell_theme", fallback: "Theme") }
    static var launchAtLogin: String { text("shell_launch_at_login", fallback: "Launch at login") }
    static var launchAtLoginRegistrationFailed: String { text("shell_launch_at_login_registration_failed", fallback: "Registration failed") }
    static var autoRefresh: String { text("shell_auto_refresh", fallback: "Auto refresh") }
    static var about: String { text("shell_about", fallback: "About") }
    static var version: String { text("shell_version", fallback: "Version") }
    static var failoverState: String { text("shell_failover_state", fallback: "Failover state") }
    static var failoverDetail: String { text("shell_failover_detail", fallback: "Failover detail") }
    static var inFlight: String { text("shell_in_flight", fallback: "In flight") }

    static var tabAccounts: String { text("shell_tab_accounts", fallback: "Accounts") }
    static var tabSettings: String { text("shell_tab_settings", fallback: "Settings") }
    static var tabFailover: String { text("shell_tab_failover", fallback: "Failover") }

    static var updateProxyAccounts: String { text("shell_update_proxy_accounts", fallback: "Update proxy accounts") }
    static var addCodexMenu: String { text("shell_add_codex_menu", fallback: "Add Codex…") }
    static var refreshAllHelp: String { text("shell_refresh_all_help", fallback: "Refresh all accounts") }
    static var statusAccessibility: String { text("shell_status_accessibility", fallback: "Failover status") }
    static var segmentAccessibility: String { text("shell_segment_accessibility", fallback: "Settings sections") }

    static var dismissNotice: String { text("shell_dismiss_notice", fallback: "Dismiss message") }
    static var retry: String { text("shell_retry", fallback: "Retry") }

    static var starting: String { text("shell_starting", fallback: "Starting…") }

    static var rowMenuAccessibility: String { text("shell_row_menu_accessibility", fallback: "More actions") }
    static var rowHint: String { text("shell_row_hint", fallback: "Expands the account") }
    static var reorderHint: String { text("shell_reorder_hint", fallback: "Drag to change its failover order") }
    static var usageBarAccessibility: String { text("shell_usage_bar_accessibility", fallback: "Reported usage") }
    static var refresh: String { text("shell_refresh", fallback: "Refresh") }
    static var signIn: String { text("shell_sign_in", fallback: "Sign in…") }
    static var signInAgain: String { text("shell_sign_in_again", fallback: "Sign in again…") }
    static var pauseInFailover: String { text("shell_pause_in_failover", fallback: "Pause in failover") }
    static var clearCooldown: String { text("shell_clear_cooldown", fallback: "Clear cooldown…") }
    static var moveToTop: String { text("shell_move_to_top", fallback: "Move to top") }
    static var rename: String { text("shell_rename", fallback: "Rename…") }
    static var remove: String { text("shell_remove", fallback: "Remove…") }

    static var factResets: String { text("shell_fact_resets", fallback: "Resets") }
    static var factStatus: String { text("shell_fact_status", fallback: "Status") }
    static var factFailover: String { text("shell_fact_failover", fallback: "Failover") }
    static var factOAuthToken: String { text("shell_fact_o_auth_token", fallback: "OAuth token") }
    static var factLastRefresh: String { text("shell_fact_last_refresh", fallback: "Last refresh") }
    static var factResetCredits: String { text("shell_fact_reset_credits", fallback: "Reset credits") }
    static var factUpdated: String { text("shell_fact_updated", fallback: "Updated") }

    static var notApplicable: String { text("shell_not_applicable", fallback: "—") }

    static var failoverRowMenuAccessibility: String { text("shell_failover_row_menu_accessibility", fallback: "Failover actions") }
    static var useInFailover: String { text("shell_use_in_failover", fallback: "Use in failover…") }
    static var pause: String { text("shell_pause", fallback: "Pause") }
    static var resume: String { text("shell_resume", fallback: "Resume") }
    static var resumeInFailover: String { text("shell_resume_in_failover", fallback: "Resume in failover") }

    static var inFlightSuffix: String { text("shell_in_flight_suffix", fallback: " in flight") }

    static var statusSeparator: String { text("shell_status_separator", fallback: " · ") }

    static var useFailoverProxy: String { text("shell_use_failover_proxy", fallback: "Use the failover proxy") }
    static var advancedProxyControls: String { text("shell_advanced_proxy_controls", fallback: "Advanced proxy controls") }
    static var codexRouting: String { text("shell_codex_routing", fallback: "Codex routing") }
    static var installAndStart: String { text("shell_install_and_start", fallback: "Install & Start") }
    static var repairProxyService: String { text("shell_repair_proxy_service", fallback: "Repair") }
    static var stopProxyService: String { text("shell_stop_proxy_service", fallback: "Stop Proxy Service") }
    static var enableForCodex: String { text("shell_enable_for_codex", fallback: "Enable for Codex") }
    static var disableForCodex: String { text("shell_disable_for_codex", fallback: "Disable for Codex") }
    static var replaceCodexRouting: String { text("shell_replace_codex_routing", fallback: "Replace Codex routing") }
    static var routingOff: String { text("shell_routing_off", fallback: "Off") }
    static var routingOn: String { text("shell_routing_on", fallback: "On") }
    static var routingConflicting: String { text("shell_routing_conflicting", fallback: "Conflicting") }
    static var clientQuiescenceTitle: String { text("shell_client_quiescence_title", fallback: "Close or idle Codex clients") }
    static var clientQuiescenceMessage: String { text("shell_client_quiescence_message", fallback: "Close or idle all Codex clients and start no new work until the operation settles.") }
    static var replaceRoutingTitle: String { text("shell_replace_routing_title", fallback: "Replace conflicting Codex routing?") }
    static var replaceRoutingMessage: String { text("shell_replace_routing_message", fallback: "Codex has routing values that do not match this proxy. Replace them with the bundled proxy routing values?") }

    static var connectionSettings: String { text("shell_connection_settings", fallback: "Connection settings") }
    static var fieldControlURL: String { text("shell_field_control_u_r_l", fallback: "Control URL") }
    static var fieldProxyCLI: String { text("shell_field_proxy_c_l_i", fallback: "CLI path") }
    static var fieldConfig: String { text("shell_field_config", fallback: "Config path") }
    static var fieldNodePath: String { text("shell_field_node_path", fallback: "Node path") }
    static var bundledProxyCLIDefault: String { text("shell_bundled_proxy_c_l_i_default", fallback: "Bundled Proxy CLI default") }
    static var bundledNodeDefault: String { text("shell_bundled_node_default", fallback: "Bundled Node default") }
    static var advancedOverrides: String { text("shell_advanced_overrides", fallback: "Advanced overrides") }
    static var fieldProxyCLIOverride: String { text("shell_field_proxy_c_l_i_override", fallback: "Proxy CLI override (blank = default)") }
    static var fieldNodeOverride: String { text("shell_field_node_override", fallback: "Node override (blank = default)") }
    static var emptyOverrideHelp: String { text("shell_empty_override_help", fallback: "Leave empty to use the bundled default.") }
    static var save: String { text("shell_save", fallback: "Save") }

    static var quit: String { text("shell_quit", fallback: "Quit") }
}
