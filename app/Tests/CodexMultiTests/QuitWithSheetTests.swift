import AppKit
import XCTest
@testable import CodexMulti








final class QuitWithSheetTests: XCTestCase {
    @MainActor
    final class FakeHost: SheetHost {
        var attachedSheet: NSWindow?
        var ended: [NSWindow] = []
        init(sheet: NSWindow?) { attachedSheet = sheet }
        func endSheet(_ sheet: NSWindow) {
            ended.append(sheet)
            if attachedSheet === sheet { attachedSheet = nil }
        }
    }


    @MainActor
    private func detachedWindow() -> NSWindow {
        let window = NSWindow(contentRect: NSRect(x: 0, y: 0, width: 10, height: 10), styleMask: .borderless, backing: .buffered, defer: true)
        window.isReleasedWhenClosed = false
        return window
    }

    @MainActor
    func testAttachedSheetsAreEndedBeforeTerminate() {
        let sheet = detachedWindow()
        let withSheet = FakeHost(sheet: sheet)
        let plain = FakeHost(sheet: nil)
        let hosts: [any SheetHost] = [plain, withSheet]

        XCTAssertEqual(QuitRequest.endAttachedSheets(of: hosts), 1)
        XCTAssertNil(withSheet.attachedSheet, "the sheet must be ended so AppKit lets `terminate` reach the delegate")
        XCTAssertTrue(withSheet.ended.first === sheet)
        XCTAssertEqual(plain.ended.count, 0, "a host without a sheet is left alone")
        XCTAssertEqual(QuitRequest.endAttachedSheets(of: hosts), 0, "idempotent")
    }


    @MainActor
    func testNSWindowIsASheetHostAndTheDefaultIsTheAppWindows() {
        let window = detachedWindow()
        XCTAssertNil((window as any SheetHost).attachedSheet)
        _ = NSApplication.shared
        NSApp.setActivationPolicy(.prohibited)
        XCTAssertEqual(QuitRequest.endAttachedSheets(), 0, "no test window carries a sheet")
    }
}
