import Foundation
import XCTest
@testable import CodexMulti



final class FailoverTabTests: XCTestCase {



    private func fixture(_ name: String) throws -> Projection {
        try JSONDecoder().decode(Projection.self, from: Data(contentsOf: Fixtures.exported(name)))
    }


    private func row(_ overrides: [String: Any]) throws -> ProxyAccountView {
        var object = SampleProjection.proxyAccountView
        for (key, value) in overrides { object[key] = value }
        return try JSONDecoder().decode(ProxyAccountView.self, from: JSONSerialization.data(withJSONObject: object))
    }

    private func shell(_ overrides: [String: Any] = [:]) throws -> ShellState {
        var object = try XCTUnwrap(try Fixtures.emptyAttachedObject()["shell"] as? [String: Any])
        for (key, value) in overrides { object[key] = value }
        return try JSONDecoder().decode(ShellState.self, from: JSONSerialization.data(withJSONObject: object))
    }

    private func view(_ overrides: [String: Any], from name: String = "proxy-reachable-mapped") throws -> ViewState {
        let url = Fixtures.exported(name)
        var root = try XCTUnwrap(JSONSerialization.jsonObject(with: Data(contentsOf: url)) as? [String: Any])
        var object = try XCTUnwrap(root["view"] as? [String: Any])
        for (key, value) in overrides { object[key] = value }
        var settings = try XCTUnwrap(object["settings"] as? [String: Any])
        for (key, value) in overrides where settings[key] != nil { settings[key] = value }
        object["settings"] = settings
        root["view"] = object
        return try JSONDecoder().decode(Projection.self, from: Fixtures.data(from: root)).view
    }

    private func labels(_ groups: [[FailoverModel.MenuItem]]) -> [[String]] {
        groups.map { $0.map(\.label) }
    }

    private var noVerbs: [String: Any] { ["can_switch": false, "can_pause": false, "can_resume": false, "can_clear_cooldown": false, "has_actions": false] }




    func testRowMenuItemsAppearIffTheirFlagIsSet() throws {
        XCTAssertEqual(labels(FailoverModel.rowMenu(try row(noVerbs))), [])
        let flags: [(String, String, Intent)] = [
            ("can_switch", "Use in failover…", .begin_proxy_switch(row: 0)),
            ("can_pause", "Pause", .pause_proxy_account(row: 0)),
            ("can_resume", "Resume", .resume_proxy_account(row: 0)),
            ("can_clear_cooldown", "Clear cooldown…", .begin_clear_cooldown(row: 0)),
        ]
        for (flag, label, intent) in flags {
            var overrides = noVerbs
            overrides[flag] = true
            overrides["has_actions"] = true
            let menu = FailoverModel.rowMenu(try row(overrides))
            XCTAssertEqual(labels(menu), [[label]], flag)
            XCTAssertEqual(menu[0][0].intent, intent, flag)
            XCTAssertTrue(menu[0][0].enabled, flag)
            XCTAssertFalse(menu[0][0].destructive, flag)
        }
    }



    func testRowMenuFullOrderAndIntents() throws {
        let full = try row(["index": 5, "can_switch": true, "can_pause": true, "can_resume": true, "can_clear_cooldown": true, "has_actions": true])
        let menu = FailoverModel.rowMenu(full)
        XCTAssertEqual(labels(menu), [["Use in failover…", "Pause", "Resume", "Clear cooldown…"]])
        XCTAssertEqual(menu.flatMap { $0 }.map(\.intent), [
            .begin_proxy_switch(row: 5), .pause_proxy_account(row: 5), .resume_proxy_account(row: 5), .begin_clear_cooldown(row: 5),
        ])
    }





    func testStateBadgeIsPointOnlyForTheActiveRow() throws {
        XCTAssertEqual(FailoverModel.badgeStyle(try row(["state_accent": true, "state_ok": false])), .active)
        XCTAssertEqual(FailoverModel.badgeStyle(try row(["state_accent": false, "state_ok": true])), .ready)
        XCTAssertEqual(FailoverModel.badgeStyle(try row(["state_accent": false, "state_ok": false, "state_info": true, "label_muted": true])), .muted)
        XCTAssertEqual(FailoverModel.badgeStyle(try row(["state_accent": false, "state_ok": false, "state_destructive": true, "label_muted": true])), .muted)
        let rows = try fixture("proxy-reachable-mapped").view.proxy_rows
        XCTAssertEqual(rows.map(\.state_text), ["Active", "Ready", "Cooldown", "Paused", "Not mapped"])
        XCTAssertEqual(rows.map(FailoverModel.badgeStyle), [.active, .ready, .muted, .muted, .muted])
        XCTAssertEqual(rows.map(\.label_muted), [false, false, true, true, true])
        XCTAssertEqual(rows.map(\.in_flight), [0, 0, 0, 0, 0])
        XCTAssertEqual(rows.map(\.in_flight_text), ["", "", "", "", ""], "blank at zero, never a dash")
        XCTAssertEqual(rows.filter(\.state_accent).count, 1, "one active row")
    }



    func testRowAccessibilityBindsTheProjection() throws {
        let idle = try row(["label": "ai6@example.com", "state_text": "Ready", "detail_text": "expires 8d", "in_flight": 0, "in_flight_text": ""])
        XCTAssertEqual(FailoverModel.accessibilityLabel(idle), "ai6@example.com, Ready")
        XCTAssertEqual(FailoverModel.accessibilityValue(idle), "expires 8d")
        let active = try row(["label": "dev@example.com", "state_text": "Active", "detail_text": "expires 7d", "in_flight": 16, "in_flight_text": "16"])
        XCTAssertEqual(FailoverModel.accessibilityLabel(active), "dev@example.com, Active")
        XCTAssertEqual(FailoverModel.accessibilityValue(active), "expires 7d, 16 in flight")
    }



    func testBannerIsShownWithoutRetryAndEmptyTableText() throws {
        XCTAssertTrue(FailoverModel.bannerIsShown(try fixture("proxy-unreachable").view))
        XCTAssertTrue(FailoverModel.bannerIsShown(try fixture("proxy-config-mismatch").view))
        XCTAssertFalse(FailoverModel.bannerIsShown(try fixture("proxy-reachable-mapped").view))
        XCTAssertTrue(AccountsModel.bannerShowsRetry(try fixture("proxy-unreachable").view))
        XCTAssertFalse(AccountsModel.bannerShowsRetry(try fixture("proxy-config-mismatch").view),
                       "the next comprehensive Refresh owns mismatch repair")
        XCTAssertEqual(try fixture("proxy-config-mismatch").view.proxy_banner_text,
                       "Proxy config does not match this app · the next refresh will try to fix it after checking the Config path.")
        let unread = try fixture("proxy-unreachable").view
        XCTAssertTrue(unread.proxy_rows.isEmpty)
        XCTAssertEqual(FailoverModel.emptyText(unread),
                       "No proxy accounts have been read yet. Use Refresh failover status in the … menu to read the failover order from the proxy.")
        XCTAssertEqual(FailoverModel.emptyText(unread), unread.proxy_empty_text)

        let unattached = try fixture("unattached").view
        XCTAssertFalse(unattached.capabilities.proxy_control)
        XCTAssertTrue(unattached.proxy_rows.isEmpty)
        XCTAssertEqual(FailoverModel.emptyText(unattached), "Proxy control is not attached.")
        let renamed = try view(["proxy_empty_text": "Nothing here (projected)"], from: "unattached")
        XCTAssertEqual(FailoverModel.emptyText(renamed), "Nothing here (projected)", "the line is the projection's, not typed in the shell")
    }





    func testSettingsSummaryPrefersDetailWhileBusyOrSyncNeeded() throws {
        let idle = try fixture("proxy-reachable-mapped").view
        XCTAssertEqual(FailoverModel.settingsSummary(idle, expanded: false), "127.0.0.1:8787 · CLI path set · config matches")
        XCTAssertEqual(FailoverModel.settingsSummary(idle, expanded: true), "127.0.0.1:8787 · CLI path set · config matches")
        let checking = try fixture("proxy-checking").view
        XCTAssertEqual(checking.proxy_work, .checking)
        XCTAssertEqual(FailoverModel.settingsSummary(checking, expanded: false), "Checking proxy status…")
        XCTAssertEqual(FailoverModel.settingsSummary(checking, expanded: true), "Checking proxy status…")
        let mismatch = try fixture("proxy-config-mismatch").view
        XCTAssertEqual(mismatch.proxy_sync_state, .needed)
        XCTAssertEqual(FailoverModel.settingsSummary(mismatch, expanded: false),
                       "Account changes reach the proxy on the next refresh.")
        XCTAssertEqual(FailoverModel.settingsSummary(mismatch, expanded: true), "127.0.0.1:8787 · CLI path set · config not confirmed")
        let synced = try view(["proxy_sync_state": "synced", "proxy_detail_text": "Saved accounts and proxy mappings are synchronized."])
        XCTAssertEqual(FailoverModel.settingsSummary(synced, expanded: false), "127.0.0.1:8787 · CLI path set · config matches")
    }


    func testDraftsSeedOnceFromTheSavedSettings() throws {
        var drafts = ProxyDrafts()
        XCTAssertFalse(drafts.seeded)
        XCTAssertEqual(drafts, ProxyDrafts())
        let saved = try fixture("proxy-reachable-mapped").view
        drafts.seedIfNeeded(from: saved)
        XCTAssertTrue(drafts.seeded)
        XCTAssertEqual(drafts.base_url, "http://127.0.0.1:8787")
        XCTAssertEqual(drafts.cli_path, "/opt/codexmulti-proxy/bin/codexmulti-proxy")
        XCTAssertEqual(drafts.config_path, "/tmp/fixture-proxy.json")
        XCTAssertEqual(drafts.node_path, "")
        drafts.node_path = "/usr/local/bin/node"
        let later = try view(["proxy_base_url": "http://127.0.0.1:9999", "proxy_node_path": "/opt/homebrew/bin/node"])
        drafts.seedIfNeeded(from: later)
        XCTAssertEqual(drafts.base_url, "http://127.0.0.1:8787", "seeded once: the edit survives the next projection")
        XCTAssertEqual(drafts.node_path, "/usr/local/bin/node")
    }


    func testSaveSendsTheFourStringsAndIsDisabledWhileProxyBusy() throws {
        var drafts = ProxyDrafts()
        drafts.seedIfNeeded(from: try fixture("proxy-reachable-mapped").view)
        drafts.cli_path = "/usr/local/bin/proxy-cli"
        XCTAssertEqual(drafts.saveIntent, .save_proxy_settings(
            base_url: "http://127.0.0.1:8787", cli_path: "/usr/local/bin/proxy-cli", config_path: "/tmp/fixture-proxy.json", node_path: ""))
        let encoded = try XCTUnwrap(String(data: try IntentEncoder.encode(drafts.saveIntent), encoding: .utf8))
        XCTAssertEqual(encoded, #"{"base_url":"http://127.0.0.1:8787","cli_path":"/usr/local/bin/proxy-cli","config_path":"/tmp/fixture-proxy.json","intent":"save_proxy_settings","node_path":""}"#)
        XCTAssertTrue(FailoverModel.canSave(try shell(["proxy_busy": false])))
        XCTAssertFalse(FailoverModel.canSave(try shell(["proxy_busy": true])))
        XCTAssertFalse(FailoverModel.canSave(try fixture("proxy-checking").shell))
        XCTAssertTrue(FailoverModel.canSave(try fixture("proxy-reachable-mapped").shell))
    }



    @MainActor
    func testEveryFailoverActionSubmitsExactlyOneIntent() async throws {
        let store = CoreStore()
        let core = try FixtureCore(contentsOf: Fixtures.exported("proxy-reachable-mapped"), store: store, effects: RecordingEffects().runner)
        try await core.start()
        let projection = try XCTUnwrap(store.projection)
        var expected: [Intent] = []
        for row in projection.view.proxy_rows {
            for item in FailoverModel.rowMenu(row).flatMap({ $0 }) {
                await core.submit(item.intent)
                expected.append(item.intent)
            }
        }
        await core.submit(.toggle_proxy_settings)
        expected.append(.toggle_proxy_settings)
        var drafts = ProxyDrafts()
        drafts.seedIfNeeded(from: projection.view)
        await core.submit(drafts.saveIntent)
        expected.append(drafts.saveIntent)
        let submitted = await core.submitted
        XCTAssertEqual(submitted, expected)
        XCTAssertEqual(submitted.count, 6 + 2)

        let allowed: Set<String> = ["toggle_proxy_settings", "save_proxy_settings", "pause_proxy_account", "resume_proxy_account",
                                    "begin_proxy_switch", "begin_clear_cooldown", "refresh_proxy_status"]
        XCTAssertTrue(submitted.allSatisfy { allowed.contains($0.name) }, submitted.map(\.name).joined(separator: ","))
        XCTAssertEqual(store.publishCount, 1, "the fixture core never mutates; the view shows the exporter's state")
    }



    func testLaunchOptionsParseTheFailoverOpenTargets() {
        XCTAssertEqual(LaunchOptions(arguments: ["x", "--open=failovermenu:6"]).open, .proxyRowMenu(row: 6))
        XCTAssertEqual(LaunchOptions(arguments: ["x", "--open", "failovermenu:0"]).open, .proxyRowMenu(row: 0))
        XCTAssertNil(LaunchOptions(arguments: ["x", "--open=tooltip"]).open, "the order tooltip is gone (lane D8 item 3): nothing to open")
        XCTAssertEqual(LaunchOptions(arguments: ["x", "--open=rowmenu:6"]).open, .rowMenu(row: 6))
        XCTAssertNotEqual(LaunchOptions.OpenTarget.rowMenu(row: 0), .proxyRowMenu(row: 0))
        XCTAssertNil(LaunchOptions(arguments: ["x", "--open=failovermenu:x"]).open)
    }
}
