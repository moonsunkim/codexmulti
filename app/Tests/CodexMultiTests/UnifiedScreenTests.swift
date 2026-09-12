import SwiftUI
import XCTest
@testable import CodexMulti

@MainActor
final class UnifiedScreenTests: XCTestCase {
    private func projection(_ name: String) throws -> Projection {
        try JSONDecoder().decode(Projection.self, from: Data(contentsOf: Fixtures.exported(name)))
    }

    func testOrderAndRegistryNoteFollowCore() throws {
        for name in ["unified-proxy-order", "unified-registry-order"] {
            let view = try projection(name).view
            XCTAssertEqual(UnifiedModel.rows(view), view.unified_rows)
        }
    }

    func testMenusAndInspectorUseTheirOwnIndices() throws {
        let p = try projection("unified-proxy-order")
        let top = try XCTUnwrap(p.view.unified_rows.first?.account_id)
        for row in p.view.unified_rows {
            let menu = UnifiedModel.rowMenu(row, shell: p.shell, topAccountID: top).flatMap { $0 }
            XCTAssertEqual(UnifiedModel.menuShown(row, shell: p.shell, topAccountID: top), !menu.isEmpty)
            XCTAssertEqual(Set(menu.map(\.id)).count, menu.count)
            XCTAssertEqual(UnifiedModel.toggle(row), .toggle_account(row: row.account_index))
            XCTAssertEqual(UnifiedModel.panelShown(row, view: p.view), row.expanded && p.view.inspector.present && row.inspector_index == p.view.inspector.index)
        }
    }

    func testUnreadProxyRowsStillExposeRefreshRenameAndRemove() throws {
        let p = try projection("unified-registry-order")
        XCTAssertEqual(p.view.unified_order_source, .registry)
        XCTAssertFalse(p.view.unified_rows.isEmpty)
        let top = try XCTUnwrap(p.view.unified_rows.first?.account_id)
        for row in p.view.unified_rows {
            XCTAssertFalse(row.has_actions, "the fixture proves the proxy-dependent aggregate is unavailable")
            let groups = UnifiedModel.rowMenu(row, shell: p.shell, topAccountID: top)
            let menu = groups.flatMap { $0 }
            XCTAssertTrue(UnifiedModel.menuShown(row, shell: p.shell, topAccountID: top), row.identity_label)
            XCTAssertEqual(groups.map { $0.map(\.id) }, [["refresh", "reset"], ["move_to_top", "rename", "remove"]])
            XCTAssertTrue(menu.contains { $0.id == "refresh" && $0.label == "Refresh" }, row.identity_label)
            XCTAssertTrue(menu.contains { $0.id == "rename" && $0.label == "Rename…" }, row.identity_label)
            XCTAssertTrue(menu.contains { $0.id == "remove" && $0.label == "Remove…" }, row.identity_label)
        }
    }

    func testMoveToTopUsesProjectedIndicesAndDisablesTheFirstRow() throws {
        let p = try projection("unified-proxy-order")
        let rows = p.view.unified_rows
        let top = try XCTUnwrap(rows.first?.account_id)

        for (position, row) in rows.enumerated() {
            let item = try XCTUnwrap(UnifiedModel.rowMenu(
                row, shell: p.shell, topAccountID: top).flatMap { $0 }
                .first { $0.id == "move_to_top" })
            XCTAssertEqual(item.label, "Move to top")
            XCTAssertEqual(item.enabled, position != 0)
            XCTAssertEqual(item.intent, .move_account(account_id: row.account_id, target_account_id: top))
        }
    }

    func testUnifiedRowsExposeTheFailoverReorderAccessibilityHint() throws {
        XCTAssertEqual(Copy.reorderHint, "Drag to change its failover order")
        let source = try String(contentsOf:
            Fixtures.bridgeDirectory.deletingLastPathComponent().deletingLastPathComponent()
                .appending(path: "Sources/CodexMulti/Accounts/UnifiedScreen.swift"), encoding: .utf8)
        XCTAssertTrue(source.contains("Copy.rowHint + \". \" + Copy.reorderHint"))
    }

    func testRowRendersAt56PointsOffScreen() throws {
        let p = try projection("unified-registry-order")
        for row in p.view.unified_rows {
            let renderer = ImageRenderer(content: UnifiedRowHeader(row: row, shell: p.shell).frame(width: 900))
            renderer.scale = 1
            let image = try XCTUnwrap(renderer.cgImage)
            XCTAssertEqual(image.height, 56)
        }
    }

    func testExpandedPanelUsesInspectorAsItsSingleFactAuthority() throws {
        let p = try projection("unified-proxy-order")
        let facts = AccountsModel.facts(p.view.inspector, usage: p.view.usage_rows)
        XCTAssertEqual(facts.filter { $0.label == Copy.factFailover }.count, 1)
        let source = try String(contentsOf:
            Fixtures.bridgeDirectory.deletingLastPathComponent().deletingLastPathComponent()
                .appending(path: "Sources/CodexMulti/Accounts/UnifiedScreen.swift"), encoding: .utf8)
        XCTAssertFalse(source.contains("additionalFacts:"))
        XCTAssertFalse(source.contains("UnifiedModel.facts"))
    }

    func testFailoverStateDoesNotDriveRowOpacityButSeparateFlagsDo() throws {
        let p = try projection("unified-proxy-order")
        let cooling = try XCTUnwrap(p.view.unified_rows.first { $0.failover_muted })
        XCTAssertFalse(cooling.usage_exhausted)
        XCTAssertEqual(UnifiedModel.rowOpacity(cooling, enabled: true, expanded: false), 1)
        XCTAssertEqual(UnifiedModel.rowOpacity(cooling, enabled: false, expanded: false), Tone.exhaustedOpacity)

        let data = try Data(contentsOf: Fixtures.exported("unified-proxy-order"))
        let object = try XCTUnwrap(JSONSerialization.jsonObject(with: data) as? [String: Any])
        let view = try XCTUnwrap(object["view"] as? [String: Any])
        var row = try XCTUnwrap((view["unified_rows"] as? [[String: Any]])?.first)
        row["usage_exhausted"] = true
        let exhausted = try JSONDecoder().decode(
            UnifiedRowView.self, from: JSONSerialization.data(withJSONObject: row))
        XCTAssertEqual(UnifiedModel.rowOpacity(exhausted, enabled: true, expanded: false), Tone.exhaustedOpacity)
        XCTAssertEqual(UnifiedModel.rowOpacity(exhausted, enabled: false, expanded: true), 1)
    }

    func testSettingsSectionsAppearanceAndRouting() throws {
        let settings = try projection("settings-appearance-system").view.settings
        XCTAssertEqual(PreferencesModel.sections(settings: settings), ["System", "Codex", "Proxy", "About"])




        XCTAssertNil(AppearanceResolver.resolve(.system, system: .light, contrast: .standard).name)
        XCTAssertNil(AppearanceResolver.resolve(.system, system: .dark, contrast: .standard).name)
        XCTAssertEqual(AppearanceResolver.resolve(.system, system: .dark, contrast: .standard).tone.paneMaterial,
                       Tone.dark.paneMaterial)
        XCTAssertNil(AppearanceResolver.preferredScheme(.system))
        XCTAssertEqual(AppearanceResolver.preferredScheme(.light), .light)
        XCTAssertEqual(AppearanceResolver.preferredScheme(.dark), .dark)
        XCTAssertEqual(AppearanceResolver.resolve(.light, system: .dark, contrast: .standard).name, .aqua)
        XCTAssertEqual(AppearanceResolver.resolve(.dark, system: .light, contrast: .standard).name, .darkAqua)
        XCTAssertEqual(PreferencesModel.appearanceIntent(.dark), .set_appearance(value: .dark))
        XCTAssertEqual(ShellRoute.destination(.open_details), .settingsTab)
        XCTAssertEqual(ShellRoute.destination(.open_account(account_id: "a")), .core)
        XCTAssertEqual(SettingsWindowScene.id, "main")
    }

    func testSettingsExposeOneFailoverSwitchWithoutInternalControls() throws {
        let settings = try projection("settings-appearance-system").view.settings
        let previouslyRenderedLabels: Set<String> = [
            Copy.launchAtLogin, Copy.autoRefresh, Copy.theme, settings.language_label,
            settings.codex_usage_window_label, settings.codex_show_model_limits_label,
            Copy.useFailoverProxy,
            Copy.version,
        ]
        let regroupedLabels = PreferencesModel.sectionLayout.flatMap(\.rows).map { $0.label(settings: settings) }

        XCTAssertEqual(Set(regroupedLabels), previouslyRenderedLabels,
                       "regrouping must preserve the complete settings row-label set")
        XCTAssertEqual(regroupedLabels.count, previouslyRenderedLabels.count,
                       "no settings row may be duplicated across sections")
        XCTAssertEqual(PreferencesModel.sectionLayout, [
            .init(id: .system, rows: [.launchAtLogin, .autoRefresh, .theme, .language]),
            .init(id: .codex, rows: [.codexUsageWindow, .codexShowModelLimits]),
            .init(id: .proxy, rows: [
                .useFailoverProxy,
            ]),
            .init(id: .about, rows: [.version]),
        ])
    }

    func testSettingsPresenterSelectsTheTabAndUsesTheOneWindowPresenterHeadlessly() {
        let windows = WindowPresenter.shared
        let wasHeadless = windows.headless
        windows.headless = true
        defer { windows.headless = wasHeadless; SettingsTabPresenter.shared.unregister() }
        var selected: ShellTab?
        let suppressed = windows.suppressedShowRequests
        SettingsTabPresenter.shared.register { selected = $0 }

        SettingsTabPresenter.shared.show()

        XCTAssertEqual(selected, .settings)
        XCTAssertEqual(windows.suppressedShowRequests, suppressed + 1)
    }

    func testSettingsIsAShellOwnedTabAndThereIsNoSeparateSettingsScene() throws {
        let root = Fixtures.bridgeDirectory.deletingLastPathComponent().deletingLastPathComponent()
        func source(_ path: String) throws -> String {
            try String(contentsOf: root.appending(path: "Sources/CodexMulti/" + path), encoding: .utf8)
        }
        let settings = try source("Accounts/SettingsPage.swift")
        XCTAssertFalse(settings.contains("struct PreferencesScene: Scene"))
        XCTAssertFalse(settings.contains("Settings {"))
        let positions = [
            "PreferencesModel.sectionLayout[0]", "PreferencesModel.sectionLayout[1]",
            "PreferencesModel.sectionLayout[2]", "PreferencesModel.sectionLayout[3]",
        ]
        var previous = settings.startIndex
        for marker in positions {
            let range = try XCTUnwrap(settings.range(of: marker))
            XCTAssertGreaterThanOrEqual(range.lowerBound, previous)
            previous = range.upperBound
        }
        for excluded in ["auto_update", "Automatic updates"] {
            XCTAssertFalse(settings.contains(excluded), excluded)
        }
        let main = try source("Accounts/SettingsShell.swift")
        XCTAssertTrue(main.contains("@State private var selectedTab"))
        XCTAssertTrue(main.contains("SegmentPill(tab: selectedTab)"))
        XCTAssertTrue(main.contains("case .accounts:"))
        XCTAssertTrue(main.contains("case .settings:"))
        XCTAssertFalse(main.contains("settings_tab"), "the core's tab projection is explicitly meaningless")
        let unified = try source("Accounts/UnifiedScreen.swift")
        XCTAssertFalse(unified.contains("orderNote"), "the list does not explain where its order came from")
        let band = try source("Accounts/Band.swift")
        XCTAssertTrue(band.contains("private static let order: [ShellTab] = [.accounts, .settings]"))
        XCTAssertTrue(band.contains("case .accounts: Copy.tabAccounts"))
        XCTAssertTrue(band.contains("case .settings: Copy.tabSettings"))
        let app = try source("App/CodexMultiApp.swift")
        XCTAssertFalse(app.contains("PreferencesScene("))
        XCTAssertTrue(app.contains("ShellIntentRouter(core: delegate.core, launchAtLogin: .live).sink"))
        XCTAssertTrue(app.contains("TrayMenu(store: delegate.store, submit: traySubmit)"))
        XCTAssertTrue(app.contains("ShellIntentRouter(core: delegate.core, launchAtLogin: .live).traySink"))
        let router = try source("App/ShellIntentRouter.swift")
        XCTAssertTrue(router.contains("ShellRoute.destination(intent) == .settingsTab"))
        let scene = try source("Window/SettingsWindowScene.swift")
        XCTAssertTrue(scene.contains("CommandGroup(replacing: .appSettings)"))
        XCTAssertTrue(scene.contains("Button(Copy.settings) { SettingsTabPresenter.shared.show() }"))
        XCTAssertTrue(scene.contains(".keyboardShortcut(\",\", modifiers: .command)"),
                      "Command-, must keep selecting the Settings tab")
        XCTAssertFalse(try source("Tray/TrayMenu.swift").contains("openSettings"))
        XCTAssertFalse(try source("Dialogs/DialogSheet.swift").contains("preferredColorScheme"),
                       "sheets inherit the configured window")
    }



    func testShellOwnsOneFixedBandBackdropAndOneRightControlGroup() throws {
        let root = Fixtures.bridgeDirectory.deletingLastPathComponent().deletingLastPathComponent()
        let source = try String(contentsOf: root.appending(path: "Sources/CodexMulti/Accounts/SettingsShell.swift"), encoding: .utf8)
        XCTAssertEqual(source.components(separatedBy: "BandBackdrop(").count - 1, 1)
        XCTAssertTrue(source.contains("struct PaneBackdrop: View"))
        XCTAssertTrue(source.contains(".overlay(alignment: .top)"),
                      "the fixed band must be composited above the pane and scrolling content")
        XCTAssertTrue(source.contains("tone.bandTint"),
                      "the band must not reuse the near-opaque pane tint")
        XCTAssertTrue(source.contains(".padding(.top, ShellBandLayout.scrollTopInset)"))
        XCTAssertTrue(source.contains("BandControls(projection: projection)"))
        XCTAssertFalse(source.contains("StatusPill(projection: projection).environment"),
                       "Status and refresh must not remain a single toolbar control")

        let band = try String(contentsOf: root.appending(path: "Sources/CodexMulti/Accounts/Band.swift"), encoding: .utf8)
        let statusStart = try XCTUnwrap(band.range(of: "struct StatusPill: View"))
        let refreshStart = try XCTUnwrap(band.range(of: "struct RefreshButton: View"))
        let addStart = try XCTUnwrap(band.range(of: "struct AddButton: View"))
        let layoutStart = try XCTUnwrap(band.range(of: "struct BandControlLayout: Layout"))
        let status = band[statusStart.lowerBound..<refreshStart.lowerBound]
        let refresh = band[refreshStart.lowerBound..<addStart.lowerBound]
        let add = band[addStart.lowerBound..<layoutStart.lowerBound]
        XCTAssertFalse(status.contains("Button {"), "the status pill is not a press target")
        XCTAssertFalse(status.contains("arrow.clockwise"), "the status pill contains no refresh glyph")
        XCTAssertTrue(refresh.contains("Button { submit(.refresh_all) }"))
        XCTAssertTrue(refresh.contains("private var enabled: Bool { projection.shell.can_refresh_all }"))
        XCTAssertTrue(refresh.contains(".disabled(!enabled)"))
        XCTAssertTrue(refresh.contains(".accessibilityLabel(Copy.refreshAllHelp)"))
        XCTAssertTrue(add.contains("Button { submit(.begin_add_account) }"))
        XCTAssertFalse(add.contains(".add_codex_account"),
                       "the band must never bypass the passive name-first flow")
        XCTAssertTrue(add.contains("private var enabled: Bool { projection.shell.can_manage_accounts }"))
        XCTAssertTrue(add.contains("Image(systemName: \"plus\")"))
        XCTAssertTrue(add.contains(".accessibilityLabel(Copy.addCodexMenu)"))
        XCTAssertFalse(band.contains("struct BandMenu: View"))
        XCTAssertFalse(band.contains("MenuPopover("), "the band has no menu")
        let controls = try XCTUnwrap(band.range(of: "struct BandControls: View"))
        let controlSource = band[controls.lowerBound...]
        XCTAssertEqual(controlSource.components(separatedBy: "projection: projection").count - 1, 3,
                       "status, refresh and add are the only three projected band controls")
    }

    func testProxyFacetGatesOnlyProxyItemsAndProxyResumeUsesProxyIndex() throws {
        let data = try Data(contentsOf: Fixtures.exported("unified-proxy-order"))
        let object = try XCTUnwrap(JSONSerialization.jsonObject(with: data) as? [String: Any])
        let view = try XCTUnwrap(object["view"] as? [String: Any])
        var row = try XCTUnwrap((view["unified_rows"] as? [[String: Any]])?.first {
            $0["account_id"] as? String == "acct-codex-gamma"
        })
        row["has_actions"] = false
        row["can_resume"] = true
        row["action_refresh"] = true
        row["can_reset"] = false
        func decode() throws -> UnifiedRowView { try JSONDecoder().decode(UnifiedRowView.self, from: Fixtures.data(from: row)) }
        let shell = try projection("unified-proxy-order").shell
        let accountOnly = UnifiedModel.rowMenu(try decode(), shell: shell, topAccountID: "acct-codex-top").flatMap { $0 }
        XCTAssertEqual(accountOnly.map(\.id), ["refresh", "move_to_top", "rename", "remove"])
        row["has_actions"] = true
        row["account_index"] = 8
        row["proxy_index"] = 3
        row["can_switch"] = true
        row["can_switch_proxy"] = true
        row["action_sign_in"] = true
        row["action_sign_in_again"] = true
        let menu = UnifiedModel.rowMenu(try decode(), shell: shell, topAccountID: "acct-codex-top").flatMap { $0 }
        XCTAssertEqual(menu.first { $0.id == "resume" }?.intent, .resume_proxy_account(row: 3))
        XCTAssertEqual(menu.first { $0.id == "refresh" }?.intent, .refresh_account(row: 8))
        XCTAssertEqual(menu.map(\.id), ["refresh", "switch", "pause", "resume", "move_to_top", "rename", "remove"])
        XCTAssertEqual(menu.filter { $0.id == "switch" }.count, 1)
        XCTAssertFalse(menu.contains { $0.id == "sign_in" }, "the owner-defined unified menu has no auth line")
        XCTAssertFalse(menu.contains { $0.id == "reload" })
    }
}
