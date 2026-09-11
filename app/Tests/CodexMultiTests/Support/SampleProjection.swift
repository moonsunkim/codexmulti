import Foundation
import XCTest
@testable import CodexMulti




enum SampleProjection {
    static func populated(generation: UInt64 = 2, effects: [[String: Any]] = []) throws -> [String: Any] {
        var root = try Fixtures.emptyAttachedObject()
        root["generation"] = generation
        root["effects"] = effects
        var view = try XCTUnwrap(root["view"] as? [String: Any])
        view["rows"] = [accountView]
        view["account_rows"] = [accountRowView]
        view["account_row_count"] = 1
        view["usage_rows"] = [usageRow]
        view["inspector"] = inspector
        view["proxy_accounts"] = [proxyAccountFact]
        view["proxy_rows"] = [proxyAccountView]
        root["view"] = view
        return root
    }

    static func populatedData(generation: UInt64 = 2, effects: [[String: Any]] = []) throws -> Data {
        try Fixtures.data(from: try populated(generation: generation, effects: effects))
    }

    static var windowView: [String: Any] { [
        "label": "Weekly", "model_label": "", "kind": "weekly", "used_percent": 42, "fraction": 0.42,
        "reset_at_unix_s": 1785380400, "duration_minutes": 10080,
    ] }

    static var accountView: [String: Any] { [
        "account_id": "acct-codex-0001", "label": "user1@example.com", "provider_email": "user1@example.com",
        "plan_label": "Pro", "provider": "codex", "enabled": true, "auth_state": "connected", "freshness": "as_of",
        "snapshot_status": "fresh", "has_snapshot": true, "snapshot_captured_at_unix_s": 1784948000,
        "last_attempt_at_unix_s": 1784948000, "last_success_at_unix_s": 1784948000, "last_attempt_code": "",
        "reset_credit_count": 2, "credit_detail_status": "count_only", "credit_detail_count": 0,
        "operation_in_flight": false, "queued": false, "pending_reset_attempt": false, "unsent_reset_attempt": false,
        "reset_proxy_clear": "none", "proxy_mode": false, "proxy_active": false, "proxy_can_switch": false,
        "proxy_state": "unknown", "proxy_in_flight": 0, "proxy_cooldown_until_unix_s": NSNull(),
        "windows": [windowView], "primary": 0, "tray_primary": 0,
        "summary_text": "s", "freshness_text": "f", "evidence_text": "e",
        "tray_text": "t", "tray_account_text": "ta", "tray_identity_text": "ti", "tray_detail_text": "td",
        "tray_open_command": "tray.open_account:acct-codex-0001", "tray_usage_text": "tu", "tray_updated_text": "tp",
        "tray_failover_text": "", "tray_summary_line": "Pro · Codex", "tray_can_refresh": true, "tray_can_switch": false, "tray_is_active": false,
        "tray_uses_proxy": false, "needs_attention": false, "reset_is_offerable": true,
    ] }

    static var rowChip: [String: Any] { [
        "present": false, "text": "", "accent": false, "info": false, "warning": false, "destructive": false,
    ] }

    static var windowCell: [String: Any] { [
        "present": true, "label": "Weekly", "percent_text": "42%", "fraction": 0.42, "exhausted": false,
        "reset_phrase": "r", "caption": "c",
    ] }

    static var accountRowView: [String: Any] { [
        "key": 1, "index": 0, "provider": "codex", "is_codex": true, "title": "1 · user1@example.com",
        "email_local": "user1", "email_domain": "@example.com", "has_domain": true,
        "identity_primary": "user1", "identity_secondary": "@example.com", "has_identity_secondary": true,
        "plan": "Pro", "has_plan": true, "status_line": "Pro", "access_label": "a",
        "dot_ok": true, "dot_attention": false, "dot_sign_in": false, "dot_failed": false, "dot_busy": false,
        "chip_a": rowChip, "chip_b": rowChip, "window": windowCell,
        "is_cursor": false, "expanded": true, "menu_open": false,
        "action_refresh": true, "action_sign_in": false, "action_sign_in_again": false, "action_busy": false,
        "busy_label": "", "can_switch_proxy": false, "switch_label": "", "can_pause_proxy": false,
        "can_clear_cooldown": false, "can_reset": true, "reset_label": "rl", "divider_below": false,
    ] }

    static var usageRow: [String: Any] { [
        "key": 1, "label": "Weekly", "percent_text": "42%", "fraction": 0.42, "has_meter": true, "reset_line": "x",
    ] }

    static var inspector: [String: Any] { [
        "present": true, "index": 0, "title": "t", "freshness_line": "f", "updated_ago_text": "u", "attention": false, "attention_text": "",
        "busy": false, "busy_label": "", "needs_auth": false, "needs_keychain_repair": false, "no_usage_text": "",
        "uses_proxy": false, "failover_title": "", "failover_state": "", "failover_source_text": "",
        "failover_action": "", "failover_can_switch": false, "usage_source_text": "Codex usage API",
        "token_value": "", "token_source_text": "", "has_credits": true, "credit_value": "2",
        "can_reset": true, "reset_label": "Use one reset (2 left)…", "credit_note": "",
        "has_credit_note": false, "credit_offer": "use_one", "evidence_line": "e", "plan_line": "p",
        "connection_line": "c",
    ] }

    static var proxyAccountFact: [String: Any] { [
        "app_id": "acct-codex-0001", "storage_key": NSNull(), "proxy_name": "user1", "label": "user1@example.com",
        "state": "ready", "cooldown_until_unix_s": NSNull(), "token_expires_at_unix_s": 1785640000,
        "in_flight": 0, "active": false, "mapped": true,
    ] }

    static var proxyAccountView: [String: Any] { [
        "index": 0, "order_text": "1", "app_id": "acct-codex-0001", "label": "user1@example.com",
        "label_local": "user1", "label_domain": "@example.com", "state": "ready", "in_flight": 0,
        "state_text": "Ready", "state_accent": false, "state_ok": true, "state_info": false, "state_neutral": false,
        "state_destructive": false, "detail_text": "d", "in_flight_text": "", "active": false, "mapped": true,
        "can_switch": true, "can_pause": true, "can_resume": false, "can_reload": false, "can_clear_cooldown": false,
        "has_actions": true, "menu_open": false, "label_muted": false, "divider_below": false,
    ] }
}
