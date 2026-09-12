import Foundation
import XCTest
@testable import CodexMulti

final class P6ModelContractTests: XCTestCase {
    private func decode(_ name: String) throws -> Projection {
        try JSONDecoder().decode(Projection.self, from: Data(contentsOf: Fixtures.exported(name)))
    }

    private func object(_ name: String) throws -> [String: Any] {
        try XCTUnwrap(JSONSerialization.jsonObject(with: Data(contentsOf: Fixtures.exported(name))) as? [String: Any])
    }

    func testUnifiedFixturesDecodeEveryP6FieldAndOrderingRule() throws {
        let proxy = try decode("unified-proxy-order")
        XCTAssertFalse(proxy.shell.settings_tab_is_meaningful)
        XCTAssertEqual(proxy.view.unified_order_source, .registry)
        XCTAssertEqual(proxy.view.unified_rows.map(\.account_id), [
            "acct-codex-alpha", "acct-codex-unmapped", "acct-codex-gamma",
        ])
        XCTAssertEqual(proxy.view.unified_rows.map(\.failover_state), [.cooldown, .not_mapped, .active])

        let gamma = try XCTUnwrap(proxy.view.unified_rows.first { $0.account_id == "acct-codex-gamma" })
        XCTAssertEqual(gamma.key, 3)
        XCTAssertEqual(gamma.account_index, 2)
        XCTAssertEqual(gamma.proxy_index, 0)
        XCTAssertEqual(gamma.identity_label, "gamma@example.com")
        XCTAssertEqual(gamma.email_local, "owner")
        XCTAssertEqual(gamma.email_domain, "@example.com")
        XCTAssertTrue(gamma.has_domain)
        XCTAssertEqual(gamma.plan, "Pro 20x")
        XCTAssertTrue(gamma.has_plan)
        XCTAssertEqual(gamma.usage_caption, "Weekly · resets in 3d 0h")
        XCTAssertEqual(gamma.usage_percent_text, "73%")
        XCTAssertEqual(gamma.usage_bar_fraction, 0.73, accuracy: 0.0001)
        XCTAssertFalse(gamma.usage_exhausted)
        XCTAssertEqual(gamma.failover_state_text, "Active")
        XCTAssertTrue(gamma.failover_accent)
        XCTAssertFalse(gamma.failover_muted)
        XCTAssertEqual(gamma.failover_detail_text, "", "C6 keeps Ready/Active rows free of OAuth clocks")
        XCTAssertEqual(gamma.failover_in_flight, 0)
        XCTAssertEqual(gamma.failover_in_flight_text, "")
        XCTAssertTrue(gamma.expanded)
        XCTAssertEqual(gamma.inspector_index, 2)
        XCTAssertFalse(gamma.account_menu_open)
        XCTAssertFalse(gamma.proxy_menu_open)
        XCTAssertFalse(gamma.menu_open)
        XCTAssertTrue(gamma.action_refresh)
        XCTAssertFalse(gamma.action_sign_in)
        XCTAssertFalse(gamma.action_sign_in_again)
        XCTAssertFalse(gamma.action_busy)
        XCTAssertEqual(gamma.busy_label, "")
        XCTAssertFalse(gamma.can_switch_proxy)
        XCTAssertEqual(gamma.switch_label, "Use in failover…")
        XCTAssertTrue(gamma.can_pause_proxy)
        XCTAssertFalse(gamma.can_clear_cooldown)
        XCTAssertTrue(gamma.can_reset)
        XCTAssertEqual(gamma.reset_label, "Use one reset (2 left)…")
        XCTAssertFalse(gamma.can_switch)
        XCTAssertTrue(gamma.can_pause)
        XCTAssertFalse(gamma.can_resume)
        XCTAssertFalse(gamma.can_reload)
        XCTAssertTrue(gamma.has_actions)

        let registry = try decode("unified-registry-order")
        XCTAssertEqual(registry.view.unified_order_source, .registry)
        XCTAssertEqual(registry.view.unified_rows.map(\.account_id), ["acct-codex-second", "acct-codex-first"])
    }

    func testSettingsFixturesDecodeEveryP6SettingAndEnum() throws {
        let expected: [(String, Appearance)] = [("system", .system), ("light", .light), ("dark", .dark)]
        for (name, appearance) in expected {
            let projection = try decode("settings-appearance-\(name)")
            let settings = projection.view.settings
            XCTAssertEqual(settings.appearance, appearance)
            XCTAssertEqual(settings.appearance_label_system, "System")
            XCTAssertEqual(settings.appearance_label_light, "Light")
            XCTAssertEqual(settings.appearance_label_dark, "Dark")
            XCTAssertEqual(settings.codex_section_title, "Codex")
            XCTAssertEqual(settings.codex_usage_window, .auto)
            XCTAssertEqual(settings.codex_usage_window_supported, [.auto, .weekly, .session])
            XCTAssertEqual(settings.codex_usage_window_label, "Usage shown")
            XCTAssertEqual(settings.codex_usage_window_detail_text,
                           "Prefer a usage window when the provider reports it.")
            XCTAssertFalse(settings.codex_show_model_limits)
            XCTAssertEqual(settings.codex_show_model_limits_supported, [false, true])
            XCTAssertEqual(settings.codex_show_model_limits_label, "Per-model limits")
            XCTAssertEqual(settings.codex_show_model_limits_detail_text,
                           "Show reported model limits in account details and headlines.")
            XCTAssertEqual(settings.language, .en)
            XCTAssertEqual(settings.language_supported, [.system, .en, .ko])
            XCTAssertEqual(settings.language_label, "Language")
            XCTAssertEqual(settings.language_label_system, "System")
            XCTAssertEqual(settings.language_label_english, "English")
            XCTAssertEqual(settings.language_label_korean, "한국어")
            XCTAssertEqual(settings.auto_update_state, .unavailable)
            XCTAssertFalse(settings.auto_update_detail_text.isEmpty)
            XCTAssertEqual(settings.app_version_text, "Version 0.1.0 (build 0.1.0)")
            XCTAssertFalse(settings.launch_at_login)
            XCTAssertFalse(settings.launch_at_login_registration_failed)
            XCTAssertEqual(settings.auto_refresh_minutes, 0)
            XCTAssertEqual(settings.auto_refresh_traffic_text, "Off — no scheduled provider traffic.")
            XCTAssertEqual(settings.proxy_service_state, projection.view.proxy_service_state)
            XCTAssertEqual(settings.proxy_service_detail_text, projection.view.proxy_service_detail_text)
            XCTAssertEqual(settings.proxy_service_can_install, projection.view.proxy_service_can_install)
            XCTAssertEqual(settings.proxy_service_can_repair, projection.view.proxy_service_can_repair)
            XCTAssertEqual(settings.proxy_service_can_stop, projection.view.proxy_service_can_stop)
            XCTAssertEqual(settings.codex_routing_state, projection.view.codex_routing_state)
            XCTAssertEqual(settings.proxy_enabled, settings.codex_routing_state == .on)
            XCTAssertFalse(settings.proxy_enabled_detail_text.isEmpty)
            XCTAssertEqual(settings.proxy_cli_default_path, projection.view.proxy_cli_default_path)
            XCTAssertEqual(settings.proxy_node_default_path, projection.view.proxy_node_default_path)
            XCTAssertEqual(settings.proxy_base_url, projection.view.proxy_base_url)
            XCTAssertEqual(settings.proxy_cli_path, projection.view.proxy_cli_path)
            XCTAssertEqual(settings.proxy_config_path, projection.view.proxy_config_path)
            XCTAssertEqual(settings.proxy_node_path, projection.view.proxy_node_path)
            XCTAssertEqual(settings.proxy_node_resolved, projection.view.proxy_node_resolved)
            XCTAssertEqual(settings.proxy_settings_summary_text, projection.view.proxy_settings_summary_text)
            XCTAssertEqual(settings.proxy_node_hint_text, projection.view.proxy_node_hint_text)
        }
    }

    func testP6UnknownEnumsAndMissingRequiredKeysFailClosed() throws {
        for (path, key, unknown) in [
            ("view", "unified_order_source", "saved_proxy"),
            ("view.settings", "appearance", "sepia"),
            ("view.settings", "codex_usage_window", "daily"),
            ("view.settings", "language", "english"),
            ("view.settings", "auto_update_state", "ready"),
            ("view.unified_rows.0", "failover_state", "detached"),
        ] {
            var root = try object("unified-proxy-order")
            try mutate(&root, path: path, key: key, value: unknown)
            XCTAssertThrowsError(try JSONDecoder().decode(Projection.self, from: Fixtures.data(from: root)), path)
        }

        for (path, key) in [
            ("shell", "settings_tab_is_meaningful"),
            ("view", "unified_order_source"),
            ("view", "unified_rows"),
            ("view", "settings"),
            ("view.settings", "appearance"),
            ("view.settings", "codex_section_title"),
            ("view.settings", "codex_usage_window"),
            ("view.settings", "codex_usage_window_supported"),
            ("view.settings", "codex_usage_window_label"),
            ("view.settings", "codex_usage_window_detail_text"),
            ("view.settings", "codex_show_model_limits"),
            ("view.settings", "codex_show_model_limits_supported"),
            ("view.settings", "codex_show_model_limits_label"),
            ("view.settings", "codex_show_model_limits_detail_text"),
            ("view.settings", "launch_at_login"),
            ("view.settings", "launch_at_login_registration_failed"),
            ("view.settings", "auto_refresh_minutes"),
            ("view.settings", "auto_refresh_traffic_text"),
            ("view.settings", "proxy_enabled"),
            ("view.settings", "proxy_enabled_detail_text"),
            ("view.unified_rows.0", "account_index"),
            ("view.inspector", "can_reset"),
            ("view.inspector", "reset_label"),
        ] {
            var root = try object("unified-proxy-order")
            try remove(&root, path: path, key: key)
            XCTAssertThrowsError(try JSONDecoder().decode(Projection.self, from: Fixtures.data(from: root)), "\(path).\(key)")
        }
    }

    func testP6UnknownKeysRemainVisibleToStrictContractWalker() throws {
        var root = try object("unified-proxy-order")
        try mutate(&root, path: "view.settings", key: "future_setting", value: true)
        try mutate(&root, path: "view.unified_rows.0", key: "future_row_field", value: true)
        let mismatches = ProjectionKeyWalker.mismatches(in: root)
        XCTAssertTrue(mismatches.contains("view.settings: unknown future_setting"), mismatches.joined(separator: "\n"))
        XCTAssertTrue(mismatches.contains("view.unified_rows[]: unknown future_row_field"), mismatches.joined(separator: "\n"))
    }

    func testP6EnumsAreStrictAndAppearanceIntentUsesTheEnumWireValue() throws {
        XCTAssertEqual(Appearance.allCases.map(\.rawValue), ["system", "light", "dark"])
        XCTAssertEqual(CodexUsageWindow.allCases.map(\.rawValue), ["auto", "weekly", "session"])
        XCTAssertEqual(Language.allCases.map(\.rawValue), ["system", "en", "ko"])
        XCTAssertEqual(AutoUpdateState.allCases.map(\.rawValue), ["unavailable"])
        XCTAssertEqual(UnifiedOrderSource.allCases.map(\.rawValue), ["registry"])
        XCTAssertEqual(UnifiedFailoverState.allCases.map(\.rawValue), [
            "not_mapped", "active", "ready", "cooldown", "paused", "invalid", "refreshing", "unknown",
        ])
        XCTAssertEqual(String(decoding: try IntentEncoder.encode(.set_appearance(value: .system)), as: UTF8.self),
                       #"{"intent":"set_appearance","value":"system"}"#)
        XCTAssertEqual(String(decoding: try IntentEncoder.encode(.set_appearance(value: .light)), as: UTF8.self),
                       #"{"intent":"set_appearance","value":"light"}"#)
        XCTAssertEqual(String(decoding: try IntentEncoder.encode(.set_appearance(value: .dark)), as: UTF8.self),
                       #"{"intent":"set_appearance","value":"dark"}"#)
    }

    private func mutate(_ root: inout [String: Any], path: String, key: String, value: Any) throws {
        var parts = path.split(separator: ".").map(String.init)
        try edit(&root, parts: &parts) { $0[key] = value }
    }

    private func remove(_ root: inout [String: Any], path: String, key: String) throws {
        var parts = path.split(separator: ".").map(String.init)
        try edit(&root, parts: &parts) { $0.removeValue(forKey: key) }
    }

    private func edit(
        _ object: inout [String: Any],
        parts: inout [String],
        mutation: (inout [String: Any]) -> Void
    ) throws {
        guard let part = parts.first else {
            mutation(&object)
            return
        }
        parts.removeFirst()
        if let index = Int(part) {
            throw NSError(domain: "P6ModelContractTests", code: index)
        }
        if parts.first.flatMap(Int.init) != nil {
            let index = Int(parts.removeFirst())!
            var array = try XCTUnwrap(object[part] as? [[String: Any]])
            var child = array[index]
            try edit(&child, parts: &parts, mutation: mutation)
            array[index] = child
            object[part] = array
        } else {
            var child = try XCTUnwrap(object[part] as? [String: Any])
            try edit(&child, parts: &parts, mutation: mutation)
            object[part] = child
        }
    }
}
