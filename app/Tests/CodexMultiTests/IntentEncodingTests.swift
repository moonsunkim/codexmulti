import Foundation
import XCTest
@testable import CodexMulti

final class IntentEncodingTests: XCTestCase {

    static let golden: [(Intent, String)] = [
        (.set_appearance(value: .dark), #"{"intent":"set_appearance","value":"dark"}"#),
        (.set_codex_usage_window(value: .weekly), #"{"intent":"set_codex_usage_window","value":"weekly"}"#),
        (.set_codex_show_model_limits(on: true), #"{"intent":"set_codex_show_model_limits","on":true}"#),
        (.set_launch_at_login(on: true), #"{"intent":"set_launch_at_login","on":true}"#),
        (.report_launch_at_login_registration_failure(failed: true), #"{"failed":true,"intent":"report_launch_at_login_registration_failure"}"#),
        (.set_auto_refresh(minutes: 15), #"{"intent":"set_auto_refresh","minutes":15}"#),
        (.open_details, #"{"intent":"open_details"}"#),
        (.quit_app, #"{"intent":"quit_app"}"#),
        (.open_account(account_id: "acct-codex-0001"), #"{"account_id":"acct-codex-0001","intent":"open_account"}"#),
        (.tab_accounts, #"{"intent":"tab_accounts"}"#),
        (.tab_failover, #"{"intent":"tab_failover"}"#),
        (.open_toolbar_menu, #"{"intent":"open_toolbar_menu"}"#),
        (.close_toolbar_menu, #"{"intent":"close_toolbar_menu"}"#),
        (.toggle_account(row: 3), #"{"intent":"toggle_account","row":3}"#),
        (.move_account(account_id: "acct-codex-a", target_account_id: "acct-codex-b"),
         #"{"account_id":"acct-codex-a","intent":"move_account","target_account_id":"acct-codex-b"}"#),
        (.open_row_menu(row: 0), #"{"intent":"open_row_menu","row":0}"#),
        (.close_row_menu, #"{"intent":"close_row_menu"}"#),
        (.open_proxy_row_menu(row: 2), #"{"intent":"open_proxy_row_menu","row":2}"#),
        (.close_proxy_row_menu, #"{"intent":"close_proxy_row_menu"}"#),
        (.toggle_proxy_settings, #"{"intent":"toggle_proxy_settings"}"#),
        (.copy_diagnostics(row: 1), #"{"intent":"copy_diagnostics","row":1}"#),
        (.diagnostics_copied(ok: true), #"{"intent":"diagnostics_copied","ok":true}"#),
        (.claude_tray_weekly, #"{"intent":"claude_tray_weekly"}"#),
        (.claude_tray_session, #"{"intent":"claude_tray_session"}"#),
        (.dismiss_notice, #"{"intent":"dismiss_notice"}"#),
        (.refresh_proxy_status, #"{"intent":"refresh_proxy_status"}"#),
        (.sync_proxy_config, #"{"intent":"sync_proxy_config"}"#),
        (.pause_proxy_account(row: 4), #"{"intent":"pause_proxy_account","row":4}"#),
        (.resume_proxy_account(row: 4), #"{"intent":"resume_proxy_account","row":4}"#),
        (.begin_proxy_switch(row: 5), #"{"intent":"begin_proxy_switch","row":5}"#),
        (.begin_clear_cooldown(row: 6), #"{"intent":"begin_clear_cooldown","row":6}"#),
        (.confirm_clear_cooldown, #"{"intent":"confirm_clear_cooldown"}"#),
        (.cancel_clear_cooldown, #"{"intent":"cancel_clear_cooldown"}"#),
        (.save_proxy_settings(base_url: "http://127.0.0.1:8080", cli_path: "/usr/local/bin/cmproxy", config_path: "/Users/x/.cmproxy/config.json", node_path: ""),
         #"{"base_url":"http://127.0.0.1:8080","cli_path":"/usr/local/bin/cmproxy","config_path":"/Users/x/.cmproxy/config.json","intent":"save_proxy_settings","node_path":""}"#),
        (.refresh_all, #"{"intent":"refresh_all"}"#),
        (.refresh_account(row: 7), #"{"intent":"refresh_account","row":7}"#),
        (.refresh_account_id(account_id: "acct-claude-0002"), #"{"account_id":"acct-claude-0002","intent":"refresh_account_id"}"#),
        (.begin_failover_switch(row: 8), #"{"intent":"begin_failover_switch","row":8}"#),
        (.begin_failover_switch_id(account_id: "acct-codex-0003"), #"{"account_id":"acct-codex-0003","intent":"begin_failover_switch_id"}"#),
        (.confirm_failover_switch, #"{"intent":"confirm_failover_switch"}"#),
        (.cancel_failover_switch, #"{"intent":"cancel_failover_switch"}"#),
        (.pause_failover_account(row: 9), #"{"intent":"pause_failover_account","row":9}"#),
        (.begin_clear_cooldown_account(row: 10), #"{"intent":"begin_clear_cooldown_account","row":10}"#),
        (.reauthenticate(row: 11), #"{"intent":"reauthenticate","row":11}"#),
        (.add_claude_account, #"{"intent":"add_claude_account"}"#),
        (.add_codex_account, #"{"intent":"add_codex_account"}"#),
        (.begin_add_account, #"{"intent":"begin_add_account"}"#),
        (.commit_add_account(label: "Owner Work"), #"{"intent":"commit_add_account","label":"Owner Work"}"#),
        (.cancel_add_account, #"{"intent":"cancel_add_account"}"#),
        (.begin_rename(row: 12), #"{"intent":"begin_rename","row":12}"#),
        (.commit_rename(label: "Work"), #"{"intent":"commit_rename","label":"Work"}"#),
        (.cancel_rename, #"{"intent":"cancel_rename"}"#),
        (.begin_remove(row: 13), #"{"intent":"begin_remove","row":13}"#),
        (.confirm_remove, #"{"intent":"confirm_remove"}"#),
        (.finish_mapped_remove, #"{"intent":"finish_mapped_remove"}"#),
        (.cancel_remove, #"{"intent":"cancel_remove"}"#),
        (.begin_reset(row: 14), #"{"intent":"begin_reset","row":14}"#),
        (.acknowledge_reset, #"{"intent":"acknowledge_reset"}"#),
        (.confirm_reset, #"{"intent":"confirm_reset"}"#),
        (.retry_reset, #"{"intent":"retry_reset"}"#),
        (.cancel_reset, #"{"intent":"cancel_reset"}"#),
        (.install_proxy_service, #"{"intent":"install_proxy_service"}"#),
        (.repair_proxy_service, #"{"intent":"repair_proxy_service"}"#),
        (.stop_proxy_service, #"{"intent":"stop_proxy_service"}"#),
        (.set_proxy_enabled(on: true), #"{"intent":"set_proxy_enabled","on":true}"#),
        (.enable_codex_routing(), #"{"intent":"enable_codex_routing","replace_conflicting":false}"#),
        (.disable_codex_routing, #"{"intent":"disable_codex_routing"}"#),
    ]


    static let contractNames: [String] = [
        "set_appearance", "set_codex_usage_window", "set_codex_show_model_limits", "set_launch_at_login",
        "report_launch_at_login_registration_failure", "set_auto_refresh",
        "open_details", "quit_app", "open_account", "tab_accounts", "tab_failover",
        "open_toolbar_menu", "close_toolbar_menu", "toggle_account", "move_account", "open_row_menu", "close_row_menu",
        "open_proxy_row_menu", "close_proxy_row_menu", "toggle_proxy_settings", "copy_diagnostics", "diagnostics_copied",
        "claude_tray_weekly", "claude_tray_session", "dismiss_notice", "refresh_proxy_status", "sync_proxy_config",
        "pause_proxy_account", "resume_proxy_account", "begin_proxy_switch", "begin_clear_cooldown",
        "confirm_clear_cooldown", "cancel_clear_cooldown", "save_proxy_settings", "refresh_all", "refresh_account",
        "refresh_account_id", "begin_failover_switch", "begin_failover_switch_id", "confirm_failover_switch",
        "cancel_failover_switch", "pause_failover_account", "begin_clear_cooldown_account", "reauthenticate",
        "add_claude_account", "add_codex_account", "begin_add_account", "commit_add_account", "cancel_add_account",
        "begin_rename", "commit_rename", "cancel_rename",
        "begin_remove", "confirm_remove", "finish_mapped_remove", "cancel_remove",
        "begin_reset", "acknowledge_reset", "confirm_reset", "retry_reset", "cancel_reset",
        "install_proxy_service", "repair_proxy_service", "stop_proxy_service", "set_proxy_enabled",
        "enable_codex_routing", "disable_codex_routing",
    ]

    func testEveryIntentEncodesToItsGolden() throws {
        for (intent, expected) in Self.golden {
            let encoded = String(decoding: try IntentEncoder.encode(intent), as: UTF8.self)
            XCTAssertEqual(encoded, expected, intent.name)
            let object = try XCTUnwrap(JSONSerialization.jsonObject(with: Data(encoded.utf8)) as? [String: Any])
            XCTAssertEqual(object["intent"] as? String, intent.name)
        }
    }


    func testGoldenCoversTheContractTableExactlyOnce() {
        let names = Self.golden.map(\.0.name)
        XCTAssertEqual(names.count, 67)
        XCTAssertEqual(names, Self.contractNames)
        XCTAssertEqual(Set(names).count, names.count)
    }


    func testPayloadKeysAreTheContractFieldNames() throws {
        let allowed = Set(Intent.CodingKeys.allCases.map(\.stringValue))
        XCTAssertEqual(allowed, ["intent", "account_id", "target_account_id", "row", "to", "ok", "base_url", "cli_path", "config_path", "node_path", "label", "replace_conflicting", "value", "on", "failed", "minutes"])
        for (intent, _) in Self.golden {
            let object = try XCTUnwrap(JSONSerialization.jsonObject(with: try IntentEncoder.encode(intent)) as? [String: Any])
            XCTAssertTrue(Set(object.keys).isSubset(of: allowed), intent.name)
        }
    }


    func testIntentsAllFixtureNamesMatchShellContract() throws {
        let url = Fixtures.bridgeDirectory.appending(path: "intents-all.json")
        XCTAssertTrue(FileManager.default.fileExists(atPath: url.path), "fixtures/bridge/intents-all.json is not synced (scripts/sync-fixtures.sh --sync)")
        let entries = try XCTUnwrap(JSONSerialization.jsonObject(with: Data(contentsOf: url)) as? [[String: Any]])
        let exported = Set(entries.compactMap { $0["intent"] as? String })
        XCTAssertEqual(exported, Set(Self.contractNames))
        XCTAssertTrue(exported.contains("move_account"))
    }

    func testCodexRoutingEnableDefaultsFalseAndReplacementEncodesTrue() throws {
        XCTAssertEqual(String(decoding: try IntentEncoder.encode(.enable_codex_routing()), as: UTF8.self),
                       #"{"intent":"enable_codex_routing","replace_conflicting":false}"#)
        XCTAssertEqual(String(decoding: try IntentEncoder.encode(.enable_codex_routing(replace_conflicting: true)), as: UTF8.self),
                       #"{"intent":"enable_codex_routing","replace_conflicting":true}"#)
    }
}
