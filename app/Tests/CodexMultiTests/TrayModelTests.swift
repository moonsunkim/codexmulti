import Foundation
import XCTest
@testable import CodexMulti


final class TrayModelTests: XCTestCase {


    private func view(_ name: String) throws -> ViewState {
        let url = Fixtures.exported(name)
        return try JSONDecoder().decode(Projection.self, from: Data(contentsOf: url)).view
    }


    private func view(_ name: String, trayItems: [[String: Any]], rows: [[String: Any]]? = nil) throws -> ViewState {
        let url = Fixtures.exported(name)
        var root = try XCTUnwrap(JSONSerialization.jsonObject(with: Data(contentsOf: url)) as? [String: Any])
        var object = try XCTUnwrap(root["view"] as? [String: Any])
        var tray = try XCTUnwrap(object["tray"] as? [String: Any])
        tray["items"] = trayItems
        object["tray"] = tray
        if let rows { object["rows"] = rows }
        root["view"] = object
        return try JSONDecoder().decode(Projection.self, from: Fixtures.data(from: root)).view
    }

    private func row(_ overrides: [String: Any]) throws -> AccountView {
        var object = SampleProjection.accountView
        for (key, value) in overrides { object[key] = value }
        return try JSONDecoder().decode(AccountView.self, from: JSONSerialization.data(withJSONObject: object))
    }

    private func item(_ id: Int, _ label: String, _ command: String = "", enabled: Bool = true) -> [String: Any] {
        ["id": id, "label": label, "command": command, "separator": false, "enabled": enabled]
    }

    private var separator: [String: Any] { ["id": 0, "label": "", "command": "", "separator": true, "enabled": false] }


    private func labels(_ entries: [TrayModel.Entry]) -> [String] {
        entries.flatMap { entry -> [String] in
            switch entry {
            case .separator: []
            case .info(_, let label): [label]
            case .action(let action): [action.label]
            case .account(let account): [account.title]
            case .section(let section): [section.header] + labels(section.entries)
            }
        }
    }

    private func account(_ entries: [TrayModel.Entry], id: String) throws -> TrayModel.Account {
        for entry in TrayModel.flattened(entries) {
            if case .account(let account) = entry, account.accountID == id { return account }
        }
        throw XCTSkip("no account \(id)")
    }



    func testTrayCommandsMapToTheirIntents() {
        XCTAssertEqual(TrayModel.intent(for: "tray.refresh_all"), .refresh_all)
        XCTAssertEqual(TrayModel.intent(for: "tray.open_details"), .open_details)
        XCTAssertEqual(TrayModel.intent(for: "tray.open_accounts"), .tab_accounts)
        XCTAssertEqual(TrayModel.intent(for: "tray.quit"), .quit_app)
        XCTAssertEqual(TrayModel.intent(for: "tray.open_account:acct-codex-0007"), .open_account(account_id: "acct-codex-0007"))
        XCTAssertNil(TrayModel.intent(for: ""))
        XCTAssertNil(TrayModel.intent(for: "tray.open_account:"))
        XCTAssertNil(TrayModel.intent(for: "tray.unknown"))
    }





    func testEmptyTrayKeepsTheCoreOrderAndEnablement() throws {
        let entries = TrayModel.entries(try view("empty-attached"))
        XCTAssertEqual(entries, [
            .action(TrayModel.Action(id: 1, label: "Accounts…", enabled: true, intent: .tab_accounts)),
            .action(TrayModel.Action(id: 2, label: "Refresh All Accounts", enabled: false, intent: .refresh_all)),
            .separator(position: 2),
            .info(id: 3, label: "No saved accounts"),
            .separator(position: 4),
            .action(TrayModel.Action(id: 4, label: "Settings…", enabled: true, intent: .open_details)),
            .action(TrayModel.Action(id: 5, label: "Quit", enabled: true, intent: .quit_app)),
        ])
    }




    func testEveryFixtureRendersExactlyTheCoreItems() throws {
        for url in try Fixtures.projectionFiles() {
            let view = try JSONDecoder().decode(Projection.self, from: Data(contentsOf: url)).view
            let entries = TrayModel.entries(view)
            let expected = view.tray.items.filter { !$0.separator }.map(\.label)
            XCTAssertEqual(labels(entries), expected, url.lastPathComponent)
            XCTAssertLessThanOrEqual(view.tray.items.count, 32, url.lastPathComponent)
        }
    }



    func testProjectedTrayHasNoSeparateProxyStatusRefreshAction() throws {
        for url in try Fixtures.projectionFiles() {
            let view = try JSONDecoder().decode(Projection.self, from: Data(contentsOf: url)).view
            let actions = TrayModel.flattened(TrayModel.entries(view)).compactMap { entry -> Intent? in
                guard case .action(let action) = entry else { return nil }
                return action.intent
            }
            XCTAssertFalse(actions.contains(.refresh_proxy_status), url.lastPathComponent)
            XCTAssertLessThanOrEqual(actions.filter { $0 == .refresh_all }.count, 1, url.lastPathComponent)
        }
    }




    func testMappedFixtureFoldsTheCodexHeaderIntoASection() throws {
        let view = try view("proxy-reachable-mapped")
        let entries = TrayModel.entries(view)
        XCTAssertEqual(entries.count, 6)
        guard case .action(let refresh) = entries[1], case .info(_, let poolLine) = entries[2],
              case .section(let codex) = entries[3],
              case .action(let settings) = entries[4], case .action(let quit) = entries[5] else {
            return XCTFail("unexpected shape: \(entries)")
        }
        XCTAssertEqual(refresh.intent, .refresh_all)
        XCTAssertTrue(refresh.enabled)
        XCTAssertEqual(poolLine, view.tray.items[2].label)
        XCTAssertFalse(entries.contains { if case .info(_, let text) = $0 { return text == view.proxy_tray_text }; return false })
        XCTAssertEqual(codex.header, view.tray_provider_headers[0])
        XCTAssertEqual(codex.entries.count, 4)
        XCTAssertEqual(settings.intent, .open_details)
        XCTAssertEqual(quit.intent, .quit_app)
        XCTAssertTrue(quit.isQuit)
        XCTAssertFalse(settings.isQuit)
    }




    func testTheProviderSectionCarriesItsOwnSeparators() throws {
        let view = try view("two-accounts-fresh")
        let entries = TrayModel.entries(view)
        let sections = entries.compactMap { entry -> TrayModel.Section? in
            if case .section(let section) = entry { return section }
            return nil
        }
        XCTAssertEqual(sections.first?.header, "CODEX ACCOUNTS")
        XCTAssertEqual(sections.first?.entries.count, 1)
        XCTAssertFalse(entries.contains { if case .separator = $0 { true } else { false } }, "sections carry their own separators")
    }




    func testEmptyLabelLineNeverFoldsAsTheEmptyHeaderSlot() throws {
        let items: [[String: Any]] = [
            item(1, "Refresh All Accounts", "tray.refresh_all"), separator,
            item(2, "CODEX ACCOUNTS", enabled: false),
            item(3, "a@example.com — 10%", "tray.open_account:acct-codex-0001"), separator,
            item(4, "", enabled: false),
            item(5, "Settings…", "tray.open_details"), item(6, "Quit", "tray.quit"),
        ]
        let view = try view("empty-attached", trayItems: items)
        XCTAssertEqual(view.tray_provider_headers, ["CODEX ACCOUNTS", ""])
        let entries = TrayModel.entries(view)
        let sections = entries.compactMap { entry -> TrayModel.Section? in
            if case .section(let section) = entry { return section }
            return nil
        }
        XCTAssertEqual(sections.map(\.header), ["CODEX ACCOUNTS"], "one section; the empty line is not a header")
        XCTAssertTrue(entries.contains { if case .info(4, "") = $0 { true } else { false } }, "the empty line stays an information line")
        XCTAssertEqual(labels(entries), items.filter { ($0["separator"] as? Bool) == false }.map { $0["label"] as! String })
    }





    func testTruncationRowOpensAccountsInsideTheSection() throws {
        let items: [[String: Any]] = [
            item(1, "Refresh All Accounts", "tray.refresh_all"), separator,
            item(2, "CODEX ACCOUNTS", enabled: false),
            item(3, "a@example.com — 10%", "tray.open_account:acct-codex-0001"),
            item(4, "Show 12 More Accounts…", "tray.open_accounts"), separator,
            item(5, "Settings…", "tray.open_details"), item(6, "Quit", "tray.quit"),
        ]
        let entries = TrayModel.entries(try view("empty-attached", trayItems: items))
        guard entries.count == 4, case .section(let section) = entries[1] else { return XCTFail("\(entries)") }
        XCTAssertEqual(section.entries.count, 2)
        guard case .action(let more) = section.entries[1] else { return XCTFail("\(section.entries)") }
        XCTAssertEqual(more.label, "Show 12 More Accounts…")
        XCTAssertEqual(more.intent, .tab_accounts)
        XCTAssertTrue(more.enabled)
        XCTAssertEqual(labels(entries), items.filter { ($0["separator"] as? Bool) == false }.map { $0["label"] as! String })
    }






    func testSubmenuFactsComeFromTheMatchingRow() throws {
        let view = try view("proxy-reachable-mapped")
        let entries = TrayModel.entries(view)
        let active = try account(entries, id: "acct-codex-active")
        let row = try XCTUnwrap(view.rows.first { $0.account_id == "acct-codex-active" })
        let submenu = try XCTUnwrap(active.submenu)
        XCTAssertEqual(submenu.summary, "Pro 20x · Codex")
        XCTAssertEqual(submenu.usage, row.tray_usage_text)
        XCTAssertEqual(submenu.usage, "73% used · Weekly · resets in 3d 0h")
        XCTAssertEqual(submenu.updated, row.tray_updated_text)
        XCTAssertEqual(submenu.updated, "Updated 2026-Jul-25 02:50 UTC")
        XCTAssertTrue(submenu.canRefresh)
        XCTAssertEqual(submenu.refresh, .refresh_account_id(account_id: "acct-codex-active"))
        XCTAssertEqual(submenu.failover, .active("Active in failover proxy"))
        XCTAssertEqual(submenu.open, .open_account(account_id: "acct-codex-active"))
        XCTAssertTrue(active.isCursor, "the active row is the failover cursor")


        XCTAssertEqual(active.title, try XCTUnwrap(view.tray.items.first { $0.command == "tray.open_account:acct-codex-active" }).label)
        XCTAssertEqual(active.title, row.tray_account_text)
        XCTAssertEqual(active.split, TrayModel.TitleSplit(label: "active@example.com", suffix: " — 73% · in 3d 0h"))

        let ready = try account(entries, id: "acct-codex-ready")
        XCTAssertEqual(ready.submenu?.failover, .switchable("Use in failover proxy…", .begin_failover_switch_id(account_id: "acct-codex-ready")))
        XCTAssertFalse(ready.isCursor)
        let cooling = try account(entries, id: "acct-codex-cooling")
        XCTAssertEqual(cooling.submenu?.failover, .info("Failover proxy · Cooldown"))
    }



    func testSubmenuFailoverLineAppearsOnlyForMappedRows() throws {
        let unmapped = try account(TrayModel.entries(try view("two-accounts-fresh")), id: "acct-codex-personal")
        XCTAssertNil(unmapped.submenu?.failover)
        XCTAssertEqual(unmapped.submenu?.summary, "Pro 20x · Codex")
        XCTAssertEqual(unmapped.submenu?.canRefresh, true)
        let reauth = try account(TrayModel.entries(try view("attention-states")), id: "acct-codex-reauth")
        XCTAssertNil(reauth.submenu?.failover)
        XCTAssertEqual(reauth.submenu?.canRefresh, false, "sign-in required: the row cannot refresh")
        let paused = try account(TrayModel.entries(try view("proxy-reachable-mapped")), id: "acct-codex-paused")
        XCTAssertEqual(paused.submenu?.failover, .info("Failover proxy · Paused"))
        XCTAssertEqual(paused.submenu?.canRefresh, true)



        let tray = try view("empty-attached").tray
        XCTAssertEqual(TrayModel.submenu(for: try row(["plan_label": "", "tray_summary_line": "Account · Codex"]), tray: tray).summary, "Account · Codex")
        XCTAssertEqual(TrayModel.submenu(for: try row(["plan_label": "Team", "tray_summary_line": "Team · Codex (projected)"]), tray: tray).summary, "Team · Codex (projected)")
        XCTAssertNil(TrayModel.submenu(for: try row(["tray_uses_proxy": true, "tray_failover_text": ""]), tray: tray).failover,
                     "an empty failover line is never rendered")
        XCTAssertEqual(TrayModel.submenu(for: try row(["tray_uses_proxy": true, "tray_failover_text": "x", "tray_is_active": true]), tray: tray).failover, .active("x"))
    }




    func testSubmenuActionLabelsAndHelpComeFromTheProjection() throws {
        let projection = try JSONDecoder().decode(Projection.self, from: Data(contentsOf: Fixtures.exported("two-accounts-fresh")))
        let personal = try account(TrayModel.entries(projection.view), id: "acct-codex-personal")
        XCTAssertEqual(personal.submenu?.refreshLabel, "Refresh Usage")
        XCTAssertEqual(personal.submenu?.openLabel, "Show Account…")
        XCTAssertEqual(TrayModel.helpText(projection), "CodexMulti — saved usage and CLI accounts")
        XCTAssertNil(TrayModel.helpText(nil))

        var root = try XCTUnwrap(JSONSerialization.jsonObject(with: Data(contentsOf: Fixtures.exported("two-accounts-fresh"))) as? [String: Any])
        var view = try XCTUnwrap(root["view"] as? [String: Any])
        var tray = try XCTUnwrap(view["tray"] as? [String: Any])
        tray["refresh_usage_label"] = "R (projected)"
        tray["open_in_settings_label"] = "O (projected)"
        tray["help_text"] = "H (projected)"
        view["tray"] = tray
        root["view"] = view
        let renamed = try JSONDecoder().decode(Projection.self, from: Fixtures.data(from: root))
        let renamedPersonal = try account(TrayModel.entries(renamed.view), id: "acct-codex-personal")
        XCTAssertEqual(renamedPersonal.submenu?.refreshLabel, "R (projected)")
        XCTAssertEqual(renamedPersonal.submenu?.openLabel, "O (projected)")
        XCTAssertEqual(TrayModel.helpText(renamed), "H (projected)")
    }



    func testPreProjectionStringsMatchEveryExport() throws {
        for file in try Fixtures.projectionFiles() {
            let shell = try JSONDecoder().decode(Projection.self, from: Data(contentsOf: file)).shell
            XCTAssertEqual(shell.starting_text, Copy.starting, file.lastPathComponent)
            XCTAssertEqual(shell.quit_label, Copy.quit, file.lastPathComponent)
        }
    }





    func testAccountItemWithoutARowIsTheFlatFallback() throws {
        let items: [[String: Any]] = [
            item(1, "Refresh All Accounts", "tray.refresh_all"), separator,
            item(2, "CODEX ACCOUNTS", enabled: false),
            item(3, "ghost@example.com — 10%", "tray.open_account:acct-missing"), separator,
            item(4, "Settings…", "tray.open_details"), item(5, "Quit", "tray.quit"),
        ]
        let entries = TrayModel.entries(try view("empty-attached", trayItems: items, rows: []))
        let ghost = try account(entries, id: "acct-missing")
        XCTAssertNil(ghost.submenu)
        XCTAssertNil(ghost.split)
        XCTAssertFalse(ghost.isCursor)
        XCTAssertEqual(ghost.title, "ghost@example.com — 10%")
    }



    func testTitleSplitsOnlyAtTheDocumentedSeparatorAfterTheLabel() {
        XCTAssertEqual(TrayModel.split(title: "a@b.c — 10%", label: "a@b.c"), TrayModel.TitleSplit(label: "a@b.c", suffix: " — 10%"))
        XCTAssertEqual(TrayModel.split(title: "x — y — z", label: "x — y"), TrayModel.TitleSplit(label: "x — y", suffix: " — z"))
        XCTAssertNil(TrayModel.split(title: "a@b.c — 10%", label: "other"))
        XCTAssertNil(TrayModel.split(title: "a@b.c — ", label: "a@b.c"), "an empty status is not split")
        XCTAssertNil(TrayModel.split(title: "a@b.c", label: "a@b.c"))
        XCTAssertNil(TrayModel.split(title: "a@b.c — 10%", label: ""))
    }
}
