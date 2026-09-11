import AppKit
import XCTest
@testable import CodexMulti




final class FocusOriginTests: XCTestCase {
    func testTheLastInputDeviceDecides() {
        XCTAssertEqual(FocusOrigin.source(after: .keyDown, from: .pointer), .keyboard)
        XCTAssertEqual(FocusOrigin.source(after: .leftMouseDown, from: .keyboard), .pointer)
        XCTAssertEqual(FocusOrigin.source(after: .rightMouseDown, from: .keyboard), .pointer)
        XCTAssertEqual(FocusOrigin.source(after: .otherMouseDown, from: .keyboard), .pointer)
        XCTAssertEqual(FocusOrigin.source(after: .mouseMoved, from: .keyboard), .keyboard, "movement is not a click")
        XCTAssertEqual(FocusOrigin.source(after: .scrollWheel, from: .keyboard), .keyboard)
        XCTAssertEqual(FocusOrigin.source(after: .flagsChanged, from: .pointer), .pointer, "a bare modifier is not navigation")
    }

    @MainActor
    func testAFreshOriginIsThePointerAndRecordsEvents() {
        let origin = FocusOrigin()
        XCTAssertFalse(origin.isKeyboard, "before any input nothing shows a ring")
        origin.record(.keyDown)
        XCTAssertTrue(origin.isKeyboard)
        origin.record(.leftMouseDown)
        XCTAssertFalse(origin.isKeyboard)
    }

    func testTheRingNeedsFocusKeyboardAndAnActiveWindow() {
        XCTAssertTrue(FocusOrigin.ringShown(focused: true, keyboard: true, appearsActive: true))
        XCTAssertFalse(FocusOrigin.ringShown(focused: true, keyboard: false, appearsActive: true), "focus by click: no ring")
        XCTAssertFalse(FocusOrigin.ringShown(focused: false, keyboard: true, appearsActive: true))
        XCTAssertFalse(FocusOrigin.ringShown(focused: true, keyboard: true, appearsActive: false), "inactive window: no ring")
    }
}
