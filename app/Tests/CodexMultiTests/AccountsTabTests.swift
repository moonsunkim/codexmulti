import Foundation
import XCTest
@testable import CodexMulti


final class AccountsTabTests: XCTestCase {



    private func fixture(_ name: String) throws -> Projection {
        try JSONDecoder().decode(Projection.self, from: Data(contentsOf: Fixtures.exported(name)))
    }


    private func row(_ overrides: [String: Any]) throws -> AccountRowView {
        var object = SampleProjection.accountRowView
        for (key, value) in overrides { object[key] = value }
        return try JSONDecoder().decode(AccountRowView.self, from: JSONSerialization.data(withJSONObject: object))
    }

    private func shell(_ overrides: [String: Any] = [:]) throws -> ShellState {
        var object = try XCTUnwrap(try Fixtures.emptyAttachedObject()["shell"] as? [String: Any])
        for (key, value) in overrides { object[key] = value }
        return try JSONDecoder().decode(ShellState.self, from: JSONSerialization.data(withJSONObject: object))
    }

    private func labels(_ groups: [[AccountsModel.MenuItem]]) -> [[String]] {
        groups.map { $0.map(\.label) }
    }






    func testRowMenuItemsAppearIffTheirFlagIsSet() throws {
        let shell = try shell()
        let none = try row(["action_refresh": false, "action_sign_in": false, "action_sign_in_again": false,
                            "can_switch_proxy": false, "can_pause_proxy": false, "can_reset": false, "can_clear_cooldown": false])
        XCTAssertEqual(labels(AccountsModel.rowMenu(none, shell: shell)), [["Rename…", "Remove…"]])

        let flags: [(String, String, Intent)] = [
            ("action_refresh", "Refresh", .refresh_account(row: 0)),
            ("action_sign_in", "Sign in…", .reauthenticate(row: 0)),
            ("action_sign_in_again", "Sign in again…", .reauthenticate(row: 0)),
            ("can_pause_proxy", "Pause in failover", .pause_failover_account(row: 0)),
            ("can_clear_cooldown", "Clear cooldown…", .begin_clear_cooldown_account(row: 0)),
        ]
        for (flag, label, intent) in flags {
            var overrides: [String: Any] = ["action_refresh": false, "action_sign_in": false, "action_sign_in_again": false,
                                            "can_switch_proxy": false, "can_pause_proxy": false, "can_reset": false, "can_clear_cooldown": false]
            overrides[flag] = true
            let menu = AccountsModel.rowMenu(try row(overrides), shell: shell)
            XCTAssertEqual(labels(menu), [[label], ["Rename…", "Remove…"]], flag)
            XCTAssertEqual(menu[0][0].intent, intent, flag)
        }
        let switchRow = try row(["action_refresh": false, "can_switch_proxy": true, "switch_label": "Use in failover…", "can_reset": false])
        XCTAssertEqual(labels(AccountsModel.rowMenu(switchRow, shell: shell))[0], ["Use in failover…"])
        XCTAssertEqual(AccountsModel.rowMenu(switchRow, shell: shell)[0][0].intent, .begin_failover_switch(row: 0))
        let resetRow = try row(["action_refresh": false, "can_reset": true, "reset_label": "Use one reset (1 left)…"])
        XCTAssertEqual(labels(AccountsModel.rowMenu(resetRow, shell: shell))[0], ["Use one reset (1 left)…"])
        XCTAssertEqual(AccountsModel.rowMenu(resetRow, shell: shell)[0][0].intent, .begin_reset(row: 0))
    }


    func testRowMenuSwitchLabelWinsOverPause() throws {
        let both = try row(["action_refresh": false, "can_reset": false, "can_switch_proxy": true, "switch_label": "Use in failover…", "can_pause_proxy": true])
        XCTAssertEqual(labels(AccountsModel.rowMenu(both, shell: try shell()))[0], ["Use in failover…"])
    }



    func testRowMenuFullOrderAndIntents() throws {
        let full = try row(["index": 7, "action_refresh": true, "action_sign_in": true, "action_sign_in_again": true,
                            "can_switch_proxy": true, "switch_label": "Use in failover…", "can_pause_proxy": true,
                            "can_reset": true, "reset_label": "Review reset attempt…", "can_clear_cooldown": true])
        let menu = AccountsModel.rowMenu(full, shell: try shell())
        XCTAssertEqual(labels(menu), [
            ["Refresh", "Sign in…", "Sign in again…", "Use in failover…", "Review reset attempt…", "Clear cooldown…"],
            ["Rename…", "Remove…"],
        ])
        XCTAssertEqual(menu.flatMap { $0 }.map(\.intent), [
            .refresh_account(row: 7), .reauthenticate(row: 7), .reauthenticate(row: 7), .begin_failover_switch(row: 7),
            .begin_reset(row: 7), .begin_clear_cooldown_account(row: 7),
            .begin_rename(row: 7), .begin_remove(row: 7),
        ])
        XCTAssertEqual(menu[1][1].destructive, true)
        XCTAssertFalse(menu.flatMap { $0 }.contains { $0.label == "Copy diagnostics" })
        XCTAssertEqual(menu.flatMap { $0 }.filter(\.destructive).count, 1)
    }


    func testRowMenuRefreshEnablement() throws {
        let idle = try row(["action_refresh": true, "action_busy": false])
        XCTAssertEqual(AccountsModel.rowMenu(idle, shell: try shell(["can_refresh": true]))[0][0].enabled, true)
        XCTAssertEqual(AccountsModel.rowMenu(idle, shell: try shell(["can_refresh": false]))[0][0].enabled, false)
        let busy = try row(["action_refresh": true, "action_busy": true])
        XCTAssertEqual(AccountsModel.rowMenu(busy, shell: try shell(["can_refresh": true]))[0][0].enabled, false)
    }



    func testBandAddUsesTheExistingProjectedCapabilityAndWording() throws {
        XCTAssertTrue(try fixture("two-accounts-fresh").shell.can_manage_accounts)
        XCTAssertTrue(try JSONDecoder().decode(Projection.self, from: Fixtures.emptyAttachedData()).shell.can_manage_accounts)
        XCTAssertEqual(Copy.addCodexMenu, "Add Codex…")
    }



    func testRowSurfaceIsRaisedWhileExpandedAndHoverOnlyWhenCollapsed() {
        XCTAssertEqual(AccountsModel.rowSurface(expanded: true, hovering: false), .raised)
        XCTAssertEqual(AccountsModel.rowSurface(expanded: true, hovering: true), .raised, "no hover wash inside the box")
        XCTAssertEqual(AccountsModel.rowSurface(expanded: false, hovering: true), .hover)
        XCTAssertEqual(AccountsModel.rowSurface(expanded: false, hovering: false), .none)
    }



    func testPillDotFollowsTheProxyReadState() throws {
        XCTAssertEqual(AccountsModel.pillDot(try fixture("proxy-reachable-mapped").view), .point)
        XCTAssertEqual(AccountsModel.pillDot(try fixture("proxy-config-mismatch").view), .muted, "reachable but the config path does not match")
        XCTAssertEqual(AccountsModel.pillDot(try fixture("two-accounts-fresh").view), .muted, "proxy never read, no last-seen table")
        XCTAssertEqual(AccountsModel.pillDot(try fixture("proxy-unreachable").view), .muted)
        XCTAssertEqual(AccountsModel.pillDot(try fixture("empty-attached").view), .muted, "proxy control, nothing read, no table")
        var object = try Fixtures.emptyAttachedObject()
        var view = try XCTUnwrap(object["view"] as? [String: Any])
        view["capabilities"] = ["connected": true, "refresh": true, "accounts": true, "reset": true, "proxy_control": false]
        object["view"] = view
        let noProxy = try JSONDecoder().decode(Projection.self, from: Fixtures.data(from: object))
        XCTAssertEqual(AccountsModel.pillDot(noProxy.view), AccountsModel.PillDot.none)
        view["capabilities"] = ["connected": true, "refresh": true, "accounts": true, "reset": true, "proxy_control": true]
        view["proxy_reachability"] = "unknown"
        view["proxy_accounts"] = [SampleProjection.proxyAccountFact]
        object["view"] = view
        let lastSeen = try JSONDecoder().decode(Projection.self, from: Fixtures.data(from: object))
        XCTAssertEqual(AccountsModel.pillDot(lastSeen.view), .point, "unread this run but a last-seen table exists")
    }




    func testPillTextGainsTheBusySuffixOnlyUnderReduceMotion() throws {
        let checking = try fixture("proxy-checking").view
        XCTAssertEqual(checking.proxy_work, .checking)
        XCTAssertEqual(checking.busy_suffix_text, " · refreshing")
        XCTAssertEqual(AccountsModel.pillText(checking, reduceMotion: true), "No accounts · refreshing")
        XCTAssertEqual(AccountsModel.pillText(checking, reduceMotion: false), "No accounts")
        let idle = try fixture("two-accounts-fresh").view
        XCTAssertEqual(idle.busy_suffix_text, "")
        XCTAssertEqual(AccountsModel.pillText(idle, reduceMotion: true), idle.toolbar_status_text)
        XCTAssertEqual(AccountsModel.pillText(idle, reduceMotion: false), idle.toolbar_status_text)
    }







    func testAccountsListIsCodexRowsOnlyWithoutAGroupHeader() throws {
        for file in try Fixtures.projectionFiles() {
            let exported = try JSONDecoder().decode(Projection.self, from: Data(contentsOf: file)).view
            XCTAssertEqual(exported.claude_row_count, 0, "\(file.lastPathComponent): Codex-only export (C4)")
            XCTAssertTrue(exported.account_rows.allSatisfy(\.is_codex), "\(file.lastPathComponent): only Codex rows are exported")
            XCTAssertEqual(AccountsModel.rows(exported), exported.account_rows, "\(file.lastPathComponent): the list is the whole export")
        }
        let fiveCodex = try fixture("attention-states").view
        XCTAssertEqual(AccountsModel.rows(fiveCodex).count, 5)

        XCTAssertEqual(AccountsModel.rows(fiveCodex).map(\.divider_below), [true, true, true, true, false])
        XCTAssertEqual(AccountsModel.rows(try fixture("expanded-codex").view).map(\.identity_primary), ["Codex Personal"])
        XCTAssertFalse(AccountsModel.hasNoAccounts(fiveCodex))
        XCTAssertTrue(AccountsModel.hasNoAccounts(try fixture("empty-attached").view))
        XCTAssertTrue(AccountsModel.hasNoAccounts(try fixture("expanded-claude").view), "the legacy-named export carries no row since C4")



        var root = try XCTUnwrap(JSONSerialization.jsonObject(with: Data(contentsOf: Fixtures.exported("two-accounts-fresh"))) as? [String: Any])
        var view = try XCTUnwrap(root["view"] as? [String: Any])
        let codexRow = try XCTUnwrap((view["account_rows"] as? [[String: Any]])?.first)
        var otherRow = codexRow
        otherRow["key"] = 99
        otherRow["index"] = 1
        otherRow["provider"] = "claude"
        otherRow["is_codex"] = false
        otherRow["identity_primary"] = "Other"
        view["account_rows"] = [otherRow, codexRow]
        view["account_row_count"] = 2
        view["claude_row_count"] = 1
        root["view"] = view
        let mixed = try JSONDecoder().decode(Projection.self, from: Fixtures.data(from: root)).view
        XCTAssertEqual(AccountsModel.rows(mixed).map(\.identity_primary), ["Codex Personal"])
        XCTAssertFalse(AccountsModel.hasNoAccounts(mixed))
        view["account_rows"] = [otherRow]
        view["account_row_count"] = 1
        root["view"] = view
        let otherOnly = try JSONDecoder().decode(Projection.self, from: Fixtures.data(from: root)).view
        XCTAssertEqual(AccountsModel.rows(otherOnly), [])
        XCTAssertTrue(AccountsModel.hasNoAccounts(otherOnly))
    }

    func testEmptyScreenCopyComesFromTheCoreProjection() throws {
        let root = try Fixtures.emptyAttachedObject()
        let view = try XCTUnwrap(root["view"] as? [String: Any])
        XCTAssertEqual(view["no_accounts_title_text"] as? String, "No accounts yet")
        XCTAssertEqual(
            view["no_accounts_body_text"] as? String,
            "Add a Codex account to get started. Then install the proxy service and turn on routing in Settings."
        )
        XCTAssertEqual(view["no_accounts_action_text"] as? String, "Add Codex")

        let sources = URL(fileURLWithPath: #filePath).deletingLastPathComponent().deletingLastPathComponent().deletingLastPathComponent()
            .appending(path: "Sources/CodexMulti", directoryHint: .isDirectory)
        let copy = try String(contentsOf: sources.appending(path: "Accounts/Copy.swift"), encoding: .utf8)
        let panel = try String(contentsOf: sources.appending(path: "Accounts/NoAccountsPanel.swift"), encoding: .utf8)
        XCTAssertFalse(copy.contains("Usage is read only after you press Refresh."))
        XCTAssertTrue(panel.contains("bodyText:"))
        XCTAssertTrue(panel.contains("actionTitle:"))
    }



    func testShellCopyNamesOnlyCodex() throws {
        XCTAssertEqual(Copy.removePlainMuted, "Its saved usage snapshot is also removed. This does not delete the account at OpenAI.")
        let sources = URL(fileURLWithPath: #filePath).deletingLastPathComponent().deletingLastPathComponent().deletingLastPathComponent()
            .appending(path: "Sources/CodexMulti", directoryHint: .isDirectory)
        for name in ["Accounts/Copy.swift", "Dialogs/Copy+Dialogs.swift"] {
            let text = try String(contentsOf: sources.appending(path: name), encoding: .utf8)
            XCTAssertFalse(text.contains("Claude"), "\(name) still names the other provider")
        }
    }



    func testExhaustedRowsDimUnlessExpanded() throws {
        let exhausted = try row(["expanded": false, "window": SampleProjection.windowCell.merging(["exhausted": true, "percent_text": "100%", "fraction": 1.0]) { $1 }])
        XCTAssertEqual(AccountsModel.rowOpacity(exhausted, enabled: true), Tone.exhaustedOpacity)
        XCTAssertEqual(Tone.exhaustedOpacity, 0.6)
        let expanded = try row(["expanded": true, "window": SampleProjection.windowCell.merging(["exhausted": true]) { $1 }])
        XCTAssertEqual(AccountsModel.rowOpacity(expanded, enabled: true), 1)
        XCTAssertEqual(AccountsModel.rowOpacity(try row([:]), enabled: true), 1)
    }




    func testDisabledRowsDimLikeExhaustedRows() throws {
        XCTAssertEqual(AccountsModel.rowOpacity(try row(["expanded": false]), enabled: false), Tone.exhaustedOpacity)
        XCTAssertEqual(AccountsModel.rowOpacity(try row(["expanded": false]), enabled: true), 1)
        XCTAssertEqual(AccountsModel.rowOpacity(try row(["expanded": true]), enabled: false), 1, "the expanded box keeps full opacity")
        XCTAssertEqual(AccountsModel.rowOpacity(try row(["expanded": false, "window": SampleProjection.windowCell.merging(["exhausted": true]) { $1 }]), enabled: false), Tone.exhaustedOpacity)



        var root = try XCTUnwrap(JSONSerialization.jsonObject(with: Data(contentsOf: Fixtures.exported("attention-states"))) as? [String: Any])
        var view = try XCTUnwrap(root["view"] as? [String: Any])
        var rows = try XCTUnwrap(view["rows"] as? [[String: Any]])
        rows[0]["enabled"] = false
        view["rows"] = rows
        root["view"] = view
        let derived = try JSONDecoder().decode(Projection.self, from: Fixtures.data(from: root)).view
        XCTAssertEqual(derived.account_rows.map { AccountsModel.isEnabled($0, in: derived) }, [false, true, true, true, true])
        XCTAssertEqual(derived.account_rows.map { AccountsModel.rowOpacity($0, enabled: AccountsModel.isEnabled($0, in: derived)) },
                       [Tone.exhaustedOpacity, 1, 1, 1, 1])
        for file in try Fixtures.projectionFiles() {
            let exported = try JSONDecoder().decode(Projection.self, from: Data(contentsOf: file)).view
            XCTAssertTrue(exported.account_rows.allSatisfy { AccountsModel.isEnabled($0, in: exported) }, "\(file.lastPathComponent): every exported account is enabled")
            XCTAssertTrue(exported.account_rows.allSatisfy { Int($0.index) < exported.rows.count }, "\(file.lastPathComponent): every account row names a registry row")
        }
    }


    func testRowAccessibilityComesFromTheProjection() throws {
        let present = try row(["access_label": "agent@example.com, Pro · Active"])
        XCTAssertEqual(AccountsModel.accessibilityLabel(present), "agent@example.com, Pro · Active")
        XCTAssertEqual(AccountsModel.accessibilityValue(present), "c 42%")
        let absent = try row(["window": SampleProjection.windowCell.merging(["present": false, "percent_text": "—", "caption": ""]) { $1 }])
        XCTAssertEqual(AccountsModel.accessibilityValue(absent), "—")
    }



    func testPanelRowIsTheExpandedRowTheInspectorDescribes() throws {
        let codex = try fixture("expanded-codex").view
        XCTAssertEqual(AccountsModel.panelRow(codex)?.identity_primary, "Codex Personal")
        XCTAssertEqual(AccountsModel.panelRow(codex)?.index, codex.inspector.index)
        XCTAssertNil(AccountsModel.panelRow(try fixture("two-accounts-fresh").view))
        XCTAssertNil(AccountsModel.panelRow(try fixture("empty-attached").view))
    }




    func testFactGridBindsExactlyTheProjectedPanelFactSet() throws {
        let view = try fixture("expanded-codex").view
        let codex = view.inspector
        XCTAssertEqual(view.usage_rows.map(\.label), ["Weekly"])
        XCTAssertEqual(view.usage_rows.map(\.reset_line), ["resets Jul 28 03:00 UTC"])
        let facts = AccountsModel.facts(codex, usage: view.usage_rows)
        XCTAssertEqual(facts.map(\.label), ["Weekly", "Status", "Failover", "Last refresh", "Reset credits", "Updated"])
        XCTAssertEqual(facts.map(\.value), [
            "73% · resets Jul 28 03:00 UTC", "Connected", "",
            "Jul 25 02:50 UTC", "2 available", "10m ago · saved snapshot",
        ])
        XCTAssertEqual(facts.map(\.source), ["Codex usage API", "", "", "", "", ""])
        XCTAssertEqual(facts[5].value, codex.updated_ago_text)
        XCTAssertEqual(codex.freshness_line, "Updated Jul 25 02:50 UTC · saved snapshot", "the absolute line stays in the projection; the cell no longer derives from it")
        XCTAssertEqual(facts.map(\.applies), [true, true, false, true, true, true], "this export's Codex row is not proxy-mapped, so Failover does not apply")
        XCTAssertEqual(facts.filter { $0.label == Copy.factFailover }.count, 1)
        XCTAssertFalse(facts.contains { $0.label == Copy.factOAuthToken })
        XCTAssertFalse(facts.contains { $0.label == "Plan" }, "the plan is on the row, not repeated in the grid")

        var line = SampleProjection.usageRow
        line["reset_line"] = "Reset time not reported"
        let unreported = try JSONDecoder().decode(UsageRow.self, from: JSONSerialization.data(withJSONObject: line))
        XCTAssertEqual(AccountsModel.facts(codex, usage: [unreported])[0].value, "42% · Reset time not reported", "the core's sentence stays whole")
        XCTAssertTrue(AccountsModel.facts(codex, usage: [unreported])[0].applies)
        let none = AccountsModel.facts(codex, usage: [])
        XCTAssertEqual(none[0].label, "Status")
        XCTAssertFalse(none.contains { $0.label == "5-hour" || $0.label == "Weekly" })
        XCTAssertEqual(none.count, 5)
    }

    func testC8ExpandedWindowsArePlanRelevantAndKeepProjectedOrder() throws {
        let cases: [(String, [String], [String])] = [
            ("c7-plus-session-binding", ["5-hour", "Weekly"], ["90%", "20%"]),
            ("c7-plus-weekly-binding", ["5-hour", "Weekly"], ["10%", "100%"]),
            ("c7-pro-weekly-only", ["Weekly"], ["73%"]),
            ("c7-unknown-plan-binding", ["Weekly", "Quarterly pool"], ["55%", "80%"]),
        ]
        for (fixtureName, labels, percentages) in cases {
            let view = try fixture(fixtureName).view
            XCTAssertEqual(view.usage_rows.map(\.label), labels, fixtureName)
            let usageFacts = Array(AccountsModel.facts(view.inspector, usage: view.usage_rows).prefix(view.usage_rows.count))
            XCTAssertEqual(usageFacts.map(\.label), labels, fixtureName)
            XCTAssertEqual(usageFacts.map { $0.value.components(separatedBy: Copy.statusSeparator).first ?? "" },
                           percentages, fixtureName)
            XCTAssertEqual(usageFacts.map(\.source), Array(repeating: "Codex usage API", count: labels.count), fixtureName)
        }
    }

    func testC8ExpandedFactsContainOneCompleteFailoverAndNoOAuthCell() throws {
        let ready = try fixture("c6-ready-token").view
        let readyFacts = AccountsModel.facts(ready.inspector, usage: ready.usage_rows)
        XCTAssertFalse(readyFacts.contains { $0.label == Copy.factOAuthToken })
        let readyFailover = try XCTUnwrap(readyFacts.first { $0.label == Copy.factFailover })
        XCTAssertEqual(readyFailover.value, "Active")
        XCTAssertEqual(readyFailover.source, "")
        XCTAssertEqual(readyFacts.filter { $0.label == Copy.factFailover }.count, 1)

        let cooling = try fixture("c6-cooling-explained").view
        let coolingFacts = AccountsModel.facts(cooling.inspector, usage: cooling.usage_rows)
        let coolingFailover = try XCTUnwrap(coolingFacts.first { $0.label == Copy.factFailover })
        XCTAssertEqual(coolingFailover.value, "Cooldown until 05:00 · 2h 0m")
        XCTAssertEqual(coolingFailover.source, "")
        XCTAssertEqual(coolingFacts.prefix(cooling.usage_rows.count).map(\.source),
                       Array(repeating: "Codex usage API", count: cooling.usage_rows.count))
    }

    func testInspectorResetActionExistsExactlyWhenCoreAllowsIt() throws {
        let available = try fixture("c6-ready-token").view.inspector
        let availableFact = try XCTUnwrap(
            AccountsModel.facts(available, usage: []).first { $0.label == Copy.factResetCredits })
        XCTAssertTrue(available.can_reset)
        XCTAssertEqual(availableFact.action,
                       .init(label: "Use one reset (2 left)…", intent: .begin_reset(row: available.index)))

        let zero = try fixture("c8-zero-credit").view.inspector
        let zeroFact = try XCTUnwrap(
            AccountsModel.facts(zero, usage: []).first { $0.label == Copy.factResetCredits })
        XCTAssertFalse(zero.can_reset)
        XCTAssertEqual(zero.credit_value, "0 available")
        XCTAssertNil(zeroFact.action)
    }



    func testNoticeAndBannerVisibility() throws {
        XCTAssertTrue(AccountsModel.noticeIsShown(try fixture("notice-blocked").shell))
        XCTAssertFalse(AccountsModel.noticeIsShown(try fixture("two-accounts-fresh").shell))
        XCTAssertTrue(AccountsModel.bannerIsShown(try fixture("proxy-unreachable").view))
        XCTAssertFalse(AccountsModel.bannerIsShown(try fixture("two-accounts-fresh").view))
    }



    @MainActor
    func testEveryMenuActionSubmitsExactlyOneIntent() async throws {
        let store = CoreStore()
        let core = try FixtureCore(contentsOf: Fixtures.exported("expanded-codex"), store: store, effects: RecordingEffects().runner)
        try await core.start()
        let projection = try XCTUnwrap(store.projection)
        var expected: [Intent] = []
        await core.submit(.refresh_all)
        expected.append(.refresh_all)
        await core.submit(.add_codex_account)
        expected.append(.add_codex_account)
        for row in projection.view.account_rows {
            for item in AccountsModel.rowMenu(row, shell: projection.shell).flatMap({ $0 }) {
                await core.submit(item.intent)
                expected.append(item.intent)
            }
        }
        let submitted = await core.submitted
        XCTAssertEqual(submitted, expected)
        XCTAssertEqual(store.publishCount, 1, "the fixture core never mutates; the view shows the exporter's state")
    }



    func testLaunchOptionsParseTheCaptureFlags() {
        let options = LaunchOptions(arguments: [
            "CodexMulti", "--fixture", "/tmp/x.json", "--show-window", "--frame", "-3008,0,1000,680",
            "--no-activate", "--no-status-item", "--tab", "failover", "--expand", "3", "--open", "rowmenu:2",
        ])
        XCTAssertEqual(options.fixturePath, "/tmp/x.json")
        XCTAssertTrue(options.showWindow)
        XCTAssertEqual(options.frame, CGRect(x: -3008, y: 0, width: 1000, height: 680))
        XCTAssertTrue(options.noActivate)
        XCTAssertTrue(options.noStatusItem)
        XCTAssertEqual(options.tab, .failover)
        XCTAssertEqual(options.expand, 3)
        XCTAssertEqual(options.open, .rowMenu(row: 2))
        XCTAssertNil(LaunchOptions(arguments: ["x", "--open", "bandmenu"]).open,
                     "the removed band menu has no capture target")
        XCTAssertEqual(LaunchOptions(arguments: ["x", "--tab", "accounts"]).tab, .accounts)

        let joined = LaunchOptions(arguments: [
            "CodexMulti", "--fixture=/tmp/x.json", "--show-window", "--frame=-3008,0,1000,680",
            "--no-activate", "--no-status-item", "--tab=failover", "--expand=3", "--open=rowmenu:2",
        ], environment: [:])
        XCTAssertEqual(joined, LaunchOptions(arguments: [
            "CodexMulti", "--fixture", "/tmp/x.json", "--show-window", "--frame", "-3008,0,1000,680",
            "--no-activate", "--no-status-item", "--tab", "failover", "--expand", "3", "--open", "rowmenu:2",
        ], environment: [:]))
        XCTAssertEqual(joined.tab, .failover)
        XCTAssertEqual(joined.open, .rowMenu(row: 2))

        let bare = LaunchOptions(arguments: ["CodexMulti"])
        XCTAssertEqual(bare, LaunchOptions(arguments: []))
        XCTAssertFalse(bare.showWindow || bare.noActivate || bare.noStatusItem)
        XCTAssertNil(bare.frame)
        XCTAssertNil(bare.tab)
        XCTAssertNil(bare.expand)
        XCTAssertNil(bare.open)
        XCTAssertNil(LaunchOptions(arguments: ["x", "--frame", "1,2,3"]).frame)
        XCTAssertNil(LaunchOptions(arguments: ["x", "--tab", "tray"]).tab)
        XCTAssertNil(LaunchOptions(arguments: ["x", "--open", "sheet"]).open)
    }
}
