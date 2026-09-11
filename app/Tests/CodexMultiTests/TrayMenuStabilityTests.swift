import AppKit
import SwiftUI
import XCTest
@testable import CodexMulti










@MainActor
final class TrayMenuStabilityTests: XCTestCase {
    override func setUp() {
        super.setUp()
        _ = MainActor.assumeIsolated { NSApplication.shared.setActivationPolicy(.accessory) }
    }



    private func projection(_ name: String, mutate: (inout [String: Any], inout [String: Any]) -> Void = { _, _ in }) throws -> Projection {
        var root = try XCTUnwrap(JSONSerialization.jsonObject(with: Data(contentsOf: Fixtures.exported(name))) as? [String: Any])
        var view = try XCTUnwrap(root["view"] as? [String: Any])
        mutate(&root, &view)
        root["view"] = view
        return try JSONDecoder().decode(Projection.self, from: Fixtures.data(from: root))
    }



    private func volatileTick(_ generation: Int) throws -> Projection {
        try projection("proxy-reachable-mapped") { root, view in
            root["generation"] = generation
            view["now_unix_s"] = 1_784_948_400 + generation
        }
    }


    private func activeTitleChanged(_ generation: Int) throws -> Projection {
        try projection("proxy-reachable-mapped") { root, view in
            root["generation"] = generation
            var tray = view["tray"] as! [String: Any]
            var items = tray["items"] as! [[String: Any]]
            items[3]["label"] = "active@example.com — 73% · in 2d 23h"
            tray["items"] = items
            view["tray"] = tray
            var rows = view["rows"] as! [[String: Any]]
            rows[0]["tray_account_text"] = "active@example.com — 73% · in 2d 23h"
            view["rows"] = rows
        }
    }



    private func hostedMenu(_ store: CoreStore) -> NSMenu {
        let menu = NSHostingMenu(rootView: TrayMenu(store: store) { _ in })
        menu.update()
        settle()
        return menu
    }

    private func settle() {
        RunLoop.main.run(until: Date(timeIntervalSinceNow: 0.05))
    }





    private final class ItemEvents: @unchecked Sendable {
        private(set) var changes = 0
        private(set) var removals = 0
        private(set) var insertions = 0
        private var observers: [any NSObjectProtocol] = []
        init(_ menu: NSMenu) {
            let center = NotificationCenter.default
            observers.append(center.addObserver(forName: NSMenu.didChangeItemNotification, object: menu, queue: nil) { [self] _ in changes += 1 })
            observers.append(center.addObserver(forName: NSMenu.didRemoveItemNotification, object: menu, queue: nil) { [self] _ in removals += 1 })
            observers.append(center.addObserver(forName: NSMenu.didAddItemNotification, object: menu, queue: nil) { [self] _ in insertions += 1 })
        }
        var summary: String { "changes=\(changes) removals=\(removals) insertions=\(insertions)" }
        deinit { observers.forEach { NotificationCenter.default.removeObserver($0) } }
    }

    private func activeItem(_ menu: NSMenu) throws -> NSMenuItem {
        try XCTUnwrap(menu.items.first { $0.title.hasPrefix("active@example.com") }, "no active row: \(menu.items.map(\.title))")
    }






    func testStorePublishesOnlyWhenARenderedFieldChanges() throws {
        let store = CoreStore()
        let first = try volatileTick(1)
        store.publish(first)
        XCTAssertEqual(store.publishCount, 1)

        store.publish(try volatileTick(2))
        XCTAssertEqual(store.receivedCount, 2, "the tick reached the store")
        XCTAssertEqual(store.publishCount, 1, "a tick that moved only generation and now_unix_s is not published")
        XCTAssertEqual(store.projection, first, "the rendered projection stays the one the views hold")

        store.publish(try projection("proxy-reachable-mapped") { root, _ in
            root["generation"] = 3
            root["effects"] = [["kind": "show_settings"]]
        })
        XCTAssertEqual(store.publishCount, 1, "effects are one-shot and run by the effect runner, never rendered")

        store.publish(try activeTitleChanged(4))
        XCTAssertEqual(store.publishCount, 2, "a rendered change publishes")
        XCTAssertEqual(store.projection?.generation, 4)
        XCTAssertEqual(store.receivedCount, 4)
    }




    func testRendersSameIsEqualityMinusTheVolatileFields() throws {
        let base = try projection("proxy-reachable-mapped")
        XCTAssertTrue(base.rendersSame(as: try projection("proxy-reachable-mapped")))
        XCTAssertTrue(base.rendersSame(as: try volatileTick(2)))
        for (key, value) in [("toolbar_status_text", "changed"), ("proxy_tray_text", "changed"), ("busy_suffix_text", " · x")] as [(String, String)] {
            let changed = try projection("proxy-reachable-mapped") { _, view in view[key] = value }
            XCTAssertFalse(base.rendersSame(as: changed), "\(key) is rendered")
        }
        let proxyWork = try projection("proxy-reachable-mapped") { _, view in view["proxy_work"] = "checking" }
        XCTAssertFalse(base.rendersSame(as: proxyWork), "proxy_work drives the refresh glyph")
        let shell = try projection("proxy-reachable-mapped") { root, _ in
            var shell = root["shell"] as! [String: Any]
            shell["can_refresh_all"] = false
            root["shell"] = shell
        }
        XCTAssertFalse(base.rendersSame(as: shell), "shell fields are rendered")
    }




    func testVolatileTickLeavesTheHostedItemsUntouched() throws {
        let store = CoreStore()
        store.publish(try volatileTick(1))
        let menu = hostedMenu(store)
        let active = try activeItem(menu)
        let submenu = try XCTUnwrap(active.submenu)
        submenu.update()
        settle()
        let identities = menu.items.map { ObjectIdentifier($0) }
        let submenuIdentities = submenu.items.map { ObjectIdentifier($0) }
        let top = ItemEvents(menu)
        let sub = ItemEvents(submenu)

        store.publish(try volatileTick(2))
        settle()

        XCTAssertEqual(top.changes + top.removals + top.insertions, 0, "top-level items touched: \(top.summary)")
        XCTAssertEqual(sub.changes + sub.removals + sub.insertions, 0, "submenu items touched: \(sub.summary)")
        XCTAssertEqual(menu.items.map { ObjectIdentifier($0) }, identities)
        XCTAssertEqual(submenu.items.map { ObjectIdentifier($0) }, submenuIdentities)
        XCTAssertTrue(try activeItem(menu).submenu === submenu)
    }







    func testTrayContentIsFrozenWhileTheMenuTracks() throws {
        let store = CoreStore()
        store.tray.observeMenuTracking()
        store.publish(try volatileTick(1))
        let menu = hostedMenu(store)
        let active = try activeItem(menu)
        let submenu = try XCTUnwrap(active.submenu)
        submenu.update()
        settle()
        let titles = menu.items.map(\.title)
        let top = ItemEvents(menu)
        let sub = ItemEvents(submenu)

        NotificationCenter.default.post(name: NSMenu.didBeginTrackingNotification, object: menu)
        XCTAssertTrue(store.tray.isOpen)
        store.publish(try activeTitleChanged(2))
        settle()

        XCTAssertEqual(store.publishCount, 2, "the store published the change")
        XCTAssertEqual(menu.items.map(\.title), titles, "the menu shows the projection it opened with")
        XCTAssertTrue(try activeItem(menu) === active, "the account item survives")
        XCTAssertTrue(try activeItem(menu).submenu === submenu, "its open submenu survives")
        XCTAssertEqual(top.changes + top.removals + top.insertions, 0, "top-level items touched while open: \(top.summary)")
        XCTAssertEqual(sub.changes + sub.removals + sub.insertions, 0, "submenu items touched while open: \(sub.summary)")

        NotificationCenter.default.post(name: NSMenu.didEndTrackingNotification, object: menu)
        XCTAssertFalse(store.tray.isOpen)
        settle()
        XCTAssertEqual(try activeItem(menu).title, "active@example.com — 73% · in 2d 23h", "the held projection is applied as the menu closes")
    }





    func testTrayGateHoldsTheNewestProjectionUntilTheTrackedMenuEnds() throws {
        let gate = TrayGate()
        gate.observeMenuTracking()
        let menu = NSMenu()
        let other = NSMenu()
        let center = NotificationCenter.default

        center.post(name: NSMenu.didBeginTrackingNotification, object: menu)
        XCTAssertTrue(gate.isOpen)
        XCTAssertNil(gate.projection)
        gate.receive(try volatileTick(1))
        XCTAssertNil(gate.projection, "a first projection waits while the Starting… menu is open")
        center.post(name: NSMenu.didEndTrackingNotification, object: other)
        XCTAssertTrue(gate.isOpen, "another menu's end does not release the tray")
        gate.receive(try volatileTick(2))
        gate.receive(try activeTitleChanged(3))
        center.post(name: NSMenu.didEndTrackingNotification, object: menu)
        XCTAssertFalse(gate.isOpen)
        XCTAssertEqual(gate.projection?.generation, 3, "the newest projection wins")

        center.post(name: NSMenu.didBeginTrackingNotification, object: menu)
        center.post(name: NSMenu.didEndTrackingNotification, object: menu)
        XCTAssertEqual(gate.projection?.generation, 3, "nothing arrived: nothing re-applied")

        gate.receive(try activeTitleChanged(4))
        XCTAssertEqual(gate.projection?.generation, 4, "closed: applied at once")
    }



    func testStoreFeedsTheTrayGate() throws {
        let store = CoreStore()
        XCTAssertNil(store.tray.projection)
        let first = try volatileTick(1)
        store.publish(first)
        XCTAssertEqual(store.tray.projection, first)
        store.publish(try volatileTick(2))
        XCTAssertEqual(store.tray.projection, first, "a volatile tick reaches neither the store's projection nor the tray")
        store.tray.menuDidOpen()
        store.publish(try activeTitleChanged(3))
        XCTAssertEqual(store.projection?.generation, 3)
        XCTAssertEqual(store.tray.projection, first, "held while open")
        store.tray.menuDidClose()
        XCTAssertEqual(store.tray.projection?.generation, 3)
    }


    func testStabilityChecksOpenNoWindow() throws {
        let store = CoreStore()
        store.publish(try volatileTick(1))
        _ = hostedMenu(store)
        XCTAssertTrue(NSApp.windows.allSatisfy { !$0.isVisible }, "\(NSApp.windows)")
    }
}
