import AppKit
import Foundation
import os
import XCTest
@testable import CodexMulti

@MainActor
final class WindowPresentationTests: XCTestCase {
    func testExistingWindowUserOpenForcesTheApplicationAndWindowToTheFrontInOrder() {
        let recorder = PresentationRecorder()
        let window = NSWindow(
            contentRect: NSRect(x: -20_000, y: -20_000, width: 300, height: 200),
            styleMask: [.titled],
            backing: .buffered,
            defer: true)
        let presenter = WindowPresenter(actions: recorder.actions())
        presenter.settingsWindow = window
        presenter.open = { recorder.append("open") }

        presenter.showSettings()

        XCTAssertEqual(recorder.events, [
            "activate(ignoringOtherApps)",
            "open",
            "deminiaturize",
            "moveToActiveSpace",
            "makeKeyAndOrderFront",
            "orderFrontRegardless",
        ])
    }

    func testNoActivatePresentationDoesNotForceTheApplicationOrWindowForward() {
        let recorder = PresentationRecorder()
        let window = NSWindow(
            contentRect: NSRect(x: -20_000, y: -20_000, width: 300, height: 200),
            styleMask: [.titled],
            backing: .buffered,
            defer: true)
        let presenter = WindowPresenter(actions: recorder.actions())
        presenter.settingsWindow = window
        presenter.open = { recorder.append("open") }

        presenter.showSettings(activation: .nonactivating)

        XCTAssertEqual(recorder.events, ["open"])
    }

    func testRejectedRunningApplicationActivationUsesTheIgnoringOtherAppsFallback() {
        let recorder = PresentationRecorder()
        let window = NSWindow(
            contentRect: NSRect(x: -20_000, y: -20_000, width: 300, height: 200),
            styleMask: [.titled],
            backing: .buffered,
            defer: true)
        let presenter = WindowPresenter(actions: recorder.actions(activationResult: false))
        presenter.settingsWindow = window

        presenter.showSettings()

        XCTAssertEqual(recorder.events, [
            "activate(ignoringOtherApps)",
            "activateFallback(ignoringOtherApps)",
            "deminiaturize",
            "moveToActiveSpace",
            "makeKeyAndOrderFront",
            "orderFrontRegardless",
        ])
    }

    func testTrayPresentationScopeIncludesEveryWindowAndSheetOpeningIntent() {
        let presentationIntents: [Intent] = [
            .open_details,
            .open_account(account_id: "account"),
            .begin_proxy_switch(row: 1),
            .begin_clear_cooldown(row: 1),
            .begin_failover_switch(row: 1),
            .begin_failover_switch_id(account_id: "account"),
            .begin_clear_cooldown_account(row: 1),
            .begin_add_account,
            .begin_rename(row: 1),
            .begin_remove(row: 1),
            .begin_reset(row: 1),
        ]

        XCTAssertTrue(presentationIntents.allSatisfy(ShellRoute.requiresSettingsPresentation))
        XCTAssertFalse(ShellRoute.requiresSettingsPresentation(.refresh_all))
        XCTAssertFalse(ShellRoute.requiresSettingsPresentation(.confirm_remove))
    }

    func testSettingsCommandBringsTheWindowForwardBeforeChangingTabs() {
        let recorder = PresentationRecorder()
        SettingsTabPresenter.shared.register { _ in recorder.append("select settings tab") }
        defer { SettingsTabPresenter.shared.unregister() }

        SettingsTabPresenter.shared.show {
            recorder.append("bring-to-front")
        }

        XCTAssertEqual(recorder.events, ["bring-to-front", "select settings tab"])
    }

    func testTrayOpenRequestsPresentationBeforeSubmittingToTheCore() async {
        let recorder = PresentationRecorder()
        let core = PresentationRecordingCore(recorder: recorder)
        let router = ShellIntentRouter(
            core: core,
            launchAtLogin: LaunchAtLoginRegistrar { _ in },
            presentSettings: { recorder.append("bring-to-front") })

        router.traySink(.open_account(account_id: "acct-codex-ready"))

        XCTAssertEqual(recorder.events, ["bring-to-front"])
        await waitUntil { recorder.events.count == 2 }
        XCTAssertEqual(recorder.events, ["bring-to-front", "submit open_account"])
    }

    func testTrayFailoverSwitchBringsTheWindowForwardBeforeTheSheetProjection() async {
        let recorder = PresentationRecorder()
        let core = PresentationRecordingCore(recorder: recorder)
        let router = ShellIntentRouter(
            core: core,
            launchAtLogin: LaunchAtLoginRegistrar { _ in },
            presentSettings: { recorder.append("bring-to-front") })

        await router.route(
            .begin_failover_switch_id(account_id: "acct-codex-ready"),
            origin: .tray)

        XCTAssertEqual(recorder.events, ["bring-to-front", "present sheet"])
    }

    func testShowSettingsEffectRunsBeforePublishingSheetState() async throws {
        let recorder = PresentationRecorder()
        var root = try XCTUnwrap(JSONSerialization.jsonObject(
            with: SampleProjection.populatedData(effects: [["kind": "show_settings"]])) as? [String: Any])
        var shell = try XCTUnwrap(root["shell"] as? [String: Any])
        var failover = try XCTUnwrap(shell["failover_switch"] as? [String: Any])
        failover["open"] = true
        shell["failover_switch"] = failover
        root["shell"] = shell
        let store = CoreStore()
        store.onFirstPublish = {
            if let shell = store.projection?.shell, DialogModel.presented(shell) != nil {
                recorder.append("present sheet")
            }
        }
        let effects = EffectRunner(
            showSettings: { recorder.append("bring-to-front") },
            quit: {},
            writeClipboard: { _ in false },
            reply: { _ in })
        let core = FixtureCore(data: try Fixtures.data(from: root), store: store, effects: effects)

        try await core.start()

        XCTAssertEqual(recorder.events, ["bring-to-front", "present sheet"])
    }
}

private final class PresentationRecorder: @unchecked Sendable {
    private let storage = OSAllocatedUnfairLock(initialState: [String]())

    var events: [String] { storage.withLock { $0 } }

    func append(_ event: String) {
        storage.withLock { $0.append(event) }
    }

    @MainActor
    func actions(activationResult: Bool = true) -> WindowPresentationActions {
        WindowPresentationActions(
            activateIgnoringOtherApps: { [self] in
                append("activate(ignoringOtherApps)")
                return activationResult
            },
            activateIgnoringOtherAppsFallback: { [self] in
                append("activateFallback(ignoringOtherApps)")
            },
            deminiaturize: { [self] _ in append("deminiaturize") },
            moveToActiveSpace: { [self] _ in append("moveToActiveSpace") },
            makeKeyAndOrderFront: { [self] _ in append("makeKeyAndOrderFront") },
            orderFrontRegardless: { [self] _ in append("orderFrontRegardless") }
        )
    }
}

private actor PresentationRecordingCore: CoreProtocol {
    let recorder: PresentationRecorder

    init(recorder: PresentationRecorder) {
        self.recorder = recorder
    }

    func start() async throws {}

    func submit(_ intent: Intent) async {
        if case .begin_failover_switch_id = intent {
            recorder.append("present sheet")
        } else {
            recorder.append("submit \(intent.name)")
        }
    }

    func pumpNow() async {}
    func shutdown() async {}
}
