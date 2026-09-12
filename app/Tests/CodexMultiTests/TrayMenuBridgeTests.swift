import AppKit
import SwiftUI
import XCTest
@testable import CodexMulti







@MainActor
final class TrayMenuBridgeTests: XCTestCase {
    @MainActor private final class Sink {
        var intents: [Intent] = []
    }

    override func setUp() {
        super.setUp()

        NSApplication.shared.setActivationPolicy(.accessory)
    }

    private func store(_ name: String?) throws -> CoreStore {
        let store = CoreStore()
        if let name {
            let url = Fixtures.exported(name)
            store.publish(try JSONDecoder().decode(Projection.self, from: Data(contentsOf: url)))
        }
        return store
    }

    private func menu(_ name: String?, sink: Sink) throws -> NSMenu {
        let menu = NSHostingMenu(rootView: TrayMenu(store: try store(name)) { intent in sink.intents.append(intent) })
        menu.update()
        return menu
    }

    private func lines(_ menu: NSMenu) -> [NSMenuItem] { menu.items.filter { !$0.isSeparatorItem } }


    private func describe(_ menu: NSMenu) -> [String] {
        menu.items.map { item in
            item.isSeparatorItem ? "---"
                : "\(item.title)|\(item.isEnabled ? "on" : "off")|\(item.state == .on ? "checked" : "-")|\(item.isSectionHeader ? "header" : "-")|\(item.submenu == nil ? "-" : "submenu")"
        }
    }



    func testMappedFixtureRendersTheCoreItemsWithNativeSubmenus() throws {
        let sink = Sink()
        let menu = try menu("proxy-reachable-mapped", sink: sink)
        let view = try store("proxy-reachable-mapped").projection!.view

        XCTAssertEqual(lines(menu).map(\.title), view.tray.items.filter { !$0.separator && !isProviderHeader($0, view) }.map(\.label),
                       "every non-separator item but the provider header, verbatim, in the core's order")
        XCTAssertEqual(describe(menu), [
            "Accounts…|on|-|-|-",
            "Refresh All Accounts|on|-|-|-",
            "\(view.tray.items[2].label)|off|-|-|-",
            "---",
            "active@example.com — 73% · in 3d 0h|on|-|-|submenu",
            "ready@example.com — 73% · in 3d 0h|on|-|-|submenu",
            "cooling@example.com — 73% · in 3d 0h|on|-|-|submenu",
            "paused@example.com — 73% · in 3d 0h|on|-|-|submenu",
            "---",
            "Settings…|on|-|-|-",
            "Quit|on|-|-|-",
        ])
        XCTAssertEqual(lines(menu).last?.keyEquivalent, "q")
        if let settings = lines(menu).first(where: { $0.title == "Settings…" }) {
            XCTAssertEqual(settings.keyEquivalent, ",")
        }
        XCTAssertTrue(sink.intents.isEmpty, "building and updating the menu submits nothing (P-64)")



        let active = try XCTUnwrap(lines(menu).first { $0.title.hasPrefix("active@example.com") })
        let submenu = try XCTUnwrap(active.submenu)
        submenu.update()
        XCTAssertEqual(describe(submenu), [
            "Pro 20x · Codex|off|-|-|-",
            "73% used · Weekly · resets in 3d 0h|off|-|-|-",
            "Updated 2026-Jul-25 02:50 UTC|off|-|-|-",
            "---",
            "Refresh Usage|on|-|-|-",
            "Active in failover proxy|off|checked|-|-",
            "---",
            "Show Account…|on|-|-|-",
        ])


        let ready = try XCTUnwrap(lines(menu).first { $0.title.hasPrefix("ready@") }?.submenu)
        ready.update()
        XCTAssertEqual(describe(ready)[5], "Use in failover proxy…|on|-|-|-")
        let cooling = try XCTUnwrap(lines(menu).first { $0.title.hasPrefix("cooling@") }?.submenu)
        cooling.update()
        XCTAssertEqual(describe(cooling)[5], "Failover proxy · Cooldown|off|-|-|-")
    }


    func testChoosingLinesSubmitsExactlyOneIntentEach() throws {
        let sink = Sink()
        let menu = try menu("proxy-reachable-mapped", sink: sink)
        let ready = try XCTUnwrap(lines(menu).first { $0.title.hasPrefix("ready@") }?.submenu)
        ready.update()
        func fire(_ item: NSMenuItem) throws {
            let action = try XCTUnwrap(item.action, "\(item.title) has no action")
            XCTAssertTrue(NSApp.sendAction(action, to: item.target, from: item), "\(item.title) action not delivered")
        }
        try fire(try XCTUnwrap(ready.items.first { $0.title == "Refresh Usage" }))
        XCTAssertEqual(sink.intents, [.refresh_account_id(account_id: "acct-codex-ready")])
        try fire(try XCTUnwrap(ready.items.first { $0.title == "Use in failover proxy…" }))
        try fire(try XCTUnwrap(ready.items.first { $0.title == "Show Account…" }))
        try fire(try XCTUnwrap(lines(menu).first { $0.title == "Accounts…" }))
        try fire(try XCTUnwrap(lines(menu).first { $0.title == "Refresh All Accounts" }))
        try fire(try XCTUnwrap(lines(menu).first { $0.title == "Settings…" }))
        try fire(try XCTUnwrap(lines(menu).first { $0.title == "Quit" }))
        XCTAssertEqual(sink.intents, [
            .refresh_account_id(account_id: "acct-codex-ready"),
            .begin_failover_switch_id(account_id: "acct-codex-ready"),
            .open_account(account_id: "acct-codex-ready"),
            .tab_accounts,
            .refresh_all,
            .open_details,
            .quit_app,
        ])
    }



    func testEmptyTrayRendersDisabledRefreshAndTheEmptyLine() throws {
        let menu = try menu("empty-attached", sink: Sink())
        XCTAssertEqual(describe(menu), [
            "Accounts…|on|-|-|-",
            "Refresh All Accounts|off|-|-|-",
            "---",
            "No saved accounts|off|-|-|-",
            "---",
            "Settings…|on|-|-|-",
            "Quit|on|-|-|-",
        ])
    }



    func testSubmenuRefreshUsageIsDisabledWhenTheRowCannotRefresh() throws {
        let attention = try self.menu("attention-states", sink: Sink())
        XCTAssertEqual(attention.items.filter(\.isSectionHeader).map(\.title), [], "no section header is rendered")
        let reauth = try XCTUnwrap(lines(attention).first { $0.title.hasPrefix("Reauth") }?.submenu)
        reauth.update()
        XCTAssertEqual(describe(reauth), [
            "Pro 20x · Codex|off|-|-|-",
            "No usage window reported|off|-|-|-",
            "Updated 2026-Jul-25 02:50 UTC|off|-|-|-",
            "---",
            "Refresh Usage|off|-|-|-",
            "---",
            "Show Account…|on|-|-|-",
        ], "Refresh Usage disabled when the row cannot refresh")
    }




    func testSubmenuActionLabelsRenderTheProjectedStrings() throws {
        var root = try XCTUnwrap(JSONSerialization.jsonObject(with: Data(contentsOf: Fixtures.exported("two-accounts-fresh"))) as? [String: Any])
        var view = try XCTUnwrap(root["view"] as? [String: Any])
        var tray = try XCTUnwrap(view["tray"] as? [String: Any])
        tray["refresh_usage_label"] = "Refresh Usage (projected)"
        tray["open_in_settings_label"] = "Show Account… (projected)"
        view["tray"] = tray
        root["view"] = view
        let store = CoreStore()
        store.publish(try JSONDecoder().decode(Projection.self, from: Fixtures.data(from: root)))
        let sink = Sink()
        let menu = NSHostingMenu(rootView: TrayMenu(store: store) { intent in sink.intents.append(intent) })
        menu.update()
        let personal = try XCTUnwrap(lines(menu).first { $0.title.hasPrefix("Codex Personal") }?.submenu)
        personal.update()
        XCTAssertEqual(describe(personal)[4], "Refresh Usage (projected)|on|-|-|-")
        XCTAssertEqual(describe(personal)[6], "Show Account… (projected)|on|-|-|-")
    }






    func testProviderHeaderIsNeverRenderedAndItsSeparatorsStay() throws {
        var fixturesWithAHeader = 0
        for url in try Fixtures.projectionFiles() {
            let store = CoreStore()
            store.publish(try JSONDecoder().decode(Projection.self, from: Data(contentsOf: url)))
            let view = store.projection!.view
            let menu = NSHostingMenu(rootView: TrayMenu(store: store) { _ in })
            menu.update()
            let name = url.lastPathComponent
            let headers = view.tray.items.filter { isProviderHeader($0, view) }
            if !headers.isEmpty { fixturesWithAHeader += 1 }
            XCTAssertTrue(menu.items.allSatisfy { !$0.isSectionHeader }, "\(name): a section header is rendered")
            XCTAssertFalse(menu.items.contains { view.tray_provider_headers.contains($0.title) && !$0.title.isEmpty },
                           "\(name): a provider header is rendered as an item")
            XCTAssertEqual(menu.items.map { $0.isSeparatorItem ? "---" : $0.title },
                           view.tray.items.filter { !isProviderHeader($0, view) }.map { $0.separator ? "---" : $0.label },
                           "\(name): the lines are the core's items minus the provider header, separators where the core put them")
        }
        XCTAssertGreaterThan(fixturesWithAHeader, 0, "at least one export carries the provider header")
    }


    private func isProviderHeader(_ item: TrayItem, _ view: ViewState) -> Bool {
        item.command.isEmpty && !item.enabled && !item.label.isEmpty && view.tray_provider_headers.contains(item.label)
    }


    func testPreProjectionMenuIsStartingAndQuit() throws {
        let menu = try menu(nil, sink: Sink())
        XCTAssertEqual(describe(menu), ["Starting…|off|-|-|-", "---", "Quit|on|-|-|-"])
        XCTAssertEqual(lines(menu).last?.keyEquivalent, "q")
        if let settings = lines(menu).first(where: { $0.title == "Settings…" }) {
            XCTAssertEqual(settings.keyEquivalent, ",")
        }
    }







    func testMenuBarExtraGapVerdicts() throws {
        let menu = try menu("proxy-reachable-mapped", sink: Sink())
        let active = try XCTUnwrap(lines(menu).first { $0.title.hasPrefix("active@example.com") })
        let ready = try XCTUnwrap(lines(menu).first { $0.title.hasPrefix("ready@example.com") })


        XCTAssertNotNil(active.submenu)
        XCTAssertEqual(active.state, .off, "the bridge never sets a state on a submenu item")
        let mark = try XCTUnwrap(active.image, "the cursor row carries the checkmark image fallback")
        XCTAssertTrue(mark.isTemplate)
        XCTAssertNil(ready.image, "a non-cursor row carries no image")
        XCTAssertEqual(ready.state, .off)


        for item in [active, ready] {
            let title = try XCTUnwrap(item.attributedTitle, "\(item.title): no attributed title")
            XCTAssertEqual(title.string, item.title)
            let labelRange = NSRange(location: 0, length: (item.title as NSString).range(of: TrayModel.titleSeparator).location)
            let suffixRange = NSRange(location: labelRange.length, length: title.length - labelRange.length)
            var suffixColours: [NSColor] = []
            var labelColours: [NSColor] = []
            var links = 0
            title.enumerateAttributes(in: NSRange(location: 0, length: title.length)) { attributes, range, _ in
                if attributes[.link] != nil { links += 1 }
                if let colour = attributes[.foregroundColor] as? NSColor {
                    if NSIntersectionRange(range, suffixRange).length == range.length { suffixColours.append(colour) }
                    if NSIntersectionRange(range, labelRange).length == range.length { labelColours.append(colour) }
                }
            }
            XCTAssertEqual(links, 0, "\(item.title): the e-mail must not become a link (Text(verbatim:))")
            XCTAssertFalse(suffixColours.isEmpty, "\(item.title): the suffix carries a colour")
            XCTAssertTrue(labelColours.isEmpty, "\(item.title): the label is plain")
            for colour in suffixColours {
                XCTAssertLessThan(colour.alphaComponent, 1, "\(item.title): the suffix colour is the muted secondary")
            }
        }


        XCTAssertEqual(menu.minimumWidth, 0, "SwiftUI exposes no minimum width; natural width applies")
    }



    func testBuildingMenusOpensNoWindow() throws {
        _ = try menu("proxy-reachable-mapped", sink: Sink())
        XCTAssertTrue(NSApp.windows.allSatisfy { !$0.isVisible }, "\(NSApp.windows)")
    }
}
