import AppKit
import SwiftUI
import XCTest
@testable import CodexMulti



@MainActor
final class WindowLifecycleTests: XCTestCase {
    private final class AppearanceWriterSpy: WindowAppearanceWriting {
        private(set) var explicitAppearanceName: NSAppearance.Name?
        private(set) var writes: [NSAppearance.Name?] = []

        init(_ name: NSAppearance.Name? = nil) {
            explicitAppearanceName = name
        }

        func writeAppearance(named name: NSAppearance.Name?) {
            writes.append(name)
            explicitAppearanceName = name
        }
    }


    private final class InnerDelegate: NSObject, NSWindowDelegate {
        var shouldCloseAsked = 0
        var resizes = 0
        func windowShouldClose(_ sender: NSWindow) -> Bool {
            shouldCloseAsked += 1
            return true
        }
        func windowDidResize(_ notification: Notification) { resizes += 1 }
    }

    override func setUp() {
        super.setUp()
        NSApplication.shared.setActivationPolicy(.accessory)
    }


    private func hiddenWindow() -> NSWindow {
        let window = NSWindow(contentRect: NSRect(x: -20000, y: -20000, width: 300, height: 200),
                              styleMask: [.titled, .closable, .resizable], backing: .buffered, defer: true)
        window.isReleasedWhenClosed = false
        return window
    }





    func testWindowChromeAppliesSystemLightAndDarkAppearance() {
        let window = hiddenWindow()
        let options = LaunchOptions(arguments: [], environment: [:])

        window.appearance = NSAppearance(named: .darkAqua)
        WindowChrome.configure(window, options, appearanceName: nil)
        XCTAssertNil(window.appearance)

        WindowChrome.configure(window, options, appearanceName: .aqua)
        XCTAssertEqual(window.appearance?.name, .aqua)

        WindowChrome.configure(window, options, appearanceName: .darkAqua)
        XCTAssertEqual(window.appearance?.name, .darkAqua)

        WindowChrome.configure(window, options, appearanceName: nil)
        XCTAssertNil(window.appearance, "switching back to System removes the explicit override")
    }


    func testWindowChromeMakesTheNativeTitlebarTransparentOverFullSizeContent() {
        let window = hiddenWindow()
        WindowChrome.configure(window, LaunchOptions(arguments: [], environment: [:]), appearanceName: .aqua)

        XCTAssertTrue(window.styleMask.contains(.fullSizeContentView))
        XCTAssertTrue(window.titlebarAppearsTransparent)
        XCTAssertEqual(window.titlebarSeparatorStyle, .none)
    }



    func testAccountRowsRejectWindowMovementWhileBandAndEmptyPaneRemainMovable() throws {
        let projection = try JSONDecoder().decode(
            Projection.self, from: Data(contentsOf: Fixtures.exported("unified-proxy-order")))
        let store = CoreStore()
        store.publish(projection)
        let hosting = NSHostingView(rootView: SettingsShell(
            store: store,
            options: LaunchOptions(arguments: [], environment: [:]),
            submit: { _ in }
        ))
        let window = hiddenWindow()
        window.setContentSize(NSSize(width: Grid.width, height: Grid.height))
        window.contentView = hosting
        hosting.layoutSubtreeIfNeeded()
        addTeardownBlock { @MainActor [window] in window.contentView = nil }

        func descendants(of view: NSView) -> [NSView] {
            view.subviews.flatMap { [$0] + descendants(of: $0) }
        }
        let exclusion = try XCTUnwrap(
            descendants(of: hosting).compactMap { $0 as? WindowMoveExclusion.ExclusionView }.first,
            "the account-list AppKit exclusion is missing from the hosted shell")

        func canMoveWindow(at point: NSPoint, _ region: String) throws -> Bool {
            let hit = try XCTUnwrap(hosting.hitTest(point), "no AppKit view covers the \(region)")
            return hit.mouseDownCanMoveWindow
        }

        let band = NSPoint(x: hosting.bounds.midX, y: Grid.band / 2)
        let firstRow = NSPoint(
            x: Grid.L + Grid.inset,
            y: Grid.band + Grid.contentTop + Grid.accountsRow / 2)
        let emptyPane = NSPoint(x: hosting.bounds.midX, y: hosting.bounds.maxY - Grid.windowRadius)

        let exclusionFrame = exclusion.convert(exclusion.bounds, to: hosting)

        XCTAssertTrue(window.isMovableByWindowBackground)
        XCTAssertTrue(exclusionFrame.contains(firstRow), "the exclusion must cover the first row")
        XCTAssertFalse(exclusion.mouseDownCanMoveWindow)
        XCTAssertFalse(exclusionFrame.contains(band), "the band must stay outside the exclusion")
        XCTAssertFalse(exclusionFrame.contains(emptyPane), "unused pane must stay outside the exclusion")
        XCTAssertTrue(try canMoveWindow(at: band, "band"))
        XCTAssertTrue(try canMoveWindow(at: emptyPane, "empty pane"))
    }



    func testWindowChromeUpdateTwiceWithTheSamePreferenceWritesAtMostOnce() {
        let writer = AppearanceWriterSpy()
        let hook = WindowChrome.HookView()
        hook.appearanceWriterOverride = writer
        let light = AppearanceResolver.resolve(.light, system: .dark, contrast: .standard)

        hook.updateWindowAppearance(to: light.name)
        hook.updateWindowAppearance(to: light.name)

        XCTAssertEqual(writer.writes.count, 1)
        XCTAssertEqual(writer.writes.first!, .aqua)
    }



    func testWindowChromeLightDarkSystemWritesExactlyOncePerChange() {
        let writer = AppearanceWriterSpy()
        let hook = WindowChrome.HookView()
        hook.appearanceWriterOverride = writer
        let names = [
            AppearanceResolver.resolve(.light, system: .dark, contrast: .standard).name,
            AppearanceResolver.resolve(.dark, system: .light, contrast: .standard).name,
            AppearanceResolver.resolve(.system, system: .light, contrast: .standard).name,
        ]

        for name in names {
            hook.updateWindowAppearance(to: name)
            hook.updateWindowAppearance(to: name)
        }


        var expectedWrites = 0
        var previous: NSAppearance.Name?? = nil
        for name in names where previous != .some(name) {
            expectedWrites += 1
            previous = .some(name)
        }

        XCTAssertEqual(writer.writes.count, expectedWrites)

        var expected: [NSAppearance.Name?] = []
        var seen: NSAppearance.Name?? = nil
        for name in names where seen != .some(name) {
            expected.append(name)
            seen = .some(name)
        }
        XCTAssertEqual(writer.writes.map { $0 }, expected)
        XCTAssertEqual(writer.writes.first, .aqua)
    }






    func testPerformCloseHidesInsteadOfClosingAndForwardsTheRest() {
        let window = hiddenWindow()
        let inner = InnerDelegate()
        window.delegate = inner
        var closed = 0
        let observer = NotificationCenter.default.addObserver(forName: NSWindow.willCloseNotification, object: window, queue: nil) { _ in closed += 1 }
        defer { NotificationCenter.default.removeObserver(observer) }

        let proxy = CloseToHideDelegate.install(on: window)
        XCTAssertTrue(window.delegate === proxy)
        XCTAssertTrue(proxy.forwardee === inner)

        window.performClose(nil)
        XCTAssertEqual(proxy.hides, 1)
        XCTAssertEqual(closed, 0, "the window must not close")
        XCTAssertEqual(inner.shouldCloseAsked, 0, "SwiftUI's delegate is never asked (it would tear the scene down)")
        XCTAssertFalse(window.isVisible)

        window.setFrame(NSRect(x: -20000, y: -20000, width: 320, height: 210), display: false)
        XCTAssertEqual(inner.resizes, 1, "other delegate messages are forwarded")
        XCTAssertTrue(proxy.responds(to: #selector(NSWindowDelegate.windowDidResize(_:))))
        XCTAssertFalse(proxy.responds(to: #selector(NSWindowDelegate.windowDidMiniaturize(_:))))
    }



    func testInstallIsIdempotentAndTheProxyIsRetainedByTheWindow() {
        let window = hiddenWindow()
        weak var weakProxy: CloseToHideDelegate?
        autoreleasepool {
            let first = CloseToHideDelegate.install(on: window)
            weakProxy = first
            XCTAssertTrue(CloseToHideDelegate.install(on: window) === first)
        }
        XCTAssertNotNil(weakProxy)
        XCTAssertNotNil(CloseToHideDelegate.installed(on: window))
        XCTAssertNil(weakProxy?.forwardee, "a window without a delegate forwards to nothing")
        window.performClose(nil)
        XCTAssertEqual(weakProxy?.hides, 1)
    }



    func testVisualQAOverrideIsReadFromTheEnvironment() {
        XCTAssertTrue(LaunchOptions(arguments: ["CodexMulti"], environment: [LaunchOptions.visualQAEnvironmentKey: "1"]).visualQAShowSettings)
        XCTAssertFalse(LaunchOptions(arguments: ["CodexMulti"], environment: [LaunchOptions.visualQAEnvironmentKey: "0"]).visualQAShowSettings)
        XCTAssertFalse(LaunchOptions(arguments: ["CodexMulti"], environment: [:]).visualQAShowSettings)
        XCTAssertEqual(LaunchOptions.visualQAEnvironmentKey, "CODEXMULTI_VISUAL_QA_SHOW_SETTINGS")
    }


    func testStoreRunsTheFirstPublishHookOnce() throws {
        let store = CoreStore()
        var runs = 0
        var publishCountAtRun = 0
        store.onFirstPublish = {
            runs += 1
            publishCountAtRun = store.publishCount
        }
        let first = try JSONDecoder().decode(Projection.self, from: Fixtures.emptyAttachedData())
        let second = try JSONDecoder().decode(Projection.self, from: SampleProjection.populatedData(generation: 2))
        store.publish(first)
        XCTAssertEqual(runs, 1)
        XCTAssertEqual(publishCountAtRun, 1, "runs after the projection is in the store")
        XCTAssertNil(store.onFirstPublish)
        store.publish(second)
        XCTAssertEqual(runs, 1)
    }


    func testHeadlessPresenterCountsTheOverride() {
        let presenter = WindowPresenter()
        presenter.headless = true
        presenter.showSettings()
        XCTAssertEqual(presenter.suppressedShowRequests, 1)
        XCTAssertEqual(presenter.shows, 0)
    }

    func testSceneIdentityMatchesTheDesign() {
        XCTAssertEqual(SettingsWindowScene.id, "main")
        XCTAssertEqual(SettingsWindowScene.title, "CodexMulti")
    }
}
