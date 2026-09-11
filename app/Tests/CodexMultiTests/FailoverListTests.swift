import Foundation
import XCTest
@testable import CodexMulti





final class FailoverListTests: XCTestCase {
    private func fixture(_ name: String) throws -> Projection {
        try JSONDecoder().decode(Projection.self, from: Data(contentsOf: Fixtures.exported(name)))
    }

    private func row(_ overrides: [String: Any]) throws -> ProxyAccountView {
        var object = SampleProjection.proxyAccountView
        for (key, value) in overrides { object[key] = value }
        return try JSONDecoder().decode(ProxyAccountView.self, from: JSONSerialization.data(withJSONObject: object))
    }



    func testWholeEmailSharesTheRowInk() throws {
        XCTAssertEqual(FailoverModel.labelInk(try row(["label_muted": false])), .text)
        XCTAssertEqual(FailoverModel.labelInk(try row(["label_muted": true])), .muted)
        let rows = try fixture("proxy-reachable-mapped").view.proxy_rows
        XCTAssertEqual(rows.map(\.state_text), ["Active", "Ready", "Cooldown", "Paused", "Not mapped"])
        XCTAssertEqual(rows.map(FailoverModel.labelInk), [.text, .text, .muted, .muted, .muted])
    }





    func testDetailLineIsTheDetailAloneWithInFlight() throws {
        let ready = try row(["state_text": "Ready", "detail_text": "expires 6d", "in_flight": 0, "in_flight_text": ""])
        XCTAssertEqual(FailoverModel.detailLine(ready), "expires 6d")
        let cooling = try row(["state_text": "Cooldown", "detail_text": "until Sep 12 19:17 · 5d 3h", "in_flight": 0, "in_flight_text": ""])
        XCTAssertEqual(FailoverModel.detailLine(cooling), "until Sep 12 19:17 · 5d 3h")
        let active = try row(["state_text": "Active", "detail_text": "expires 6d", "in_flight": 12, "in_flight_text": "12"])
        XCTAssertEqual(FailoverModel.detailLine(active), "expires 6d · 12 in flight")
        let bare = try row(["state_text": "Refreshing", "detail_text": "", "in_flight": 0, "in_flight_text": ""])
        XCTAssertEqual(FailoverModel.detailLine(bare), "", "no state word, no dangling separator")
        let verbatim = try row(["detail_text": "token ok · expires 6d", "in_flight": 3, "in_flight_text": "3"])
        XCTAssertEqual(FailoverModel.detailLine(verbatim), "token ok · expires 6d · 3 in flight", "nothing is cut from the projected detail")
        let rows = try fixture("proxy-reachable-mapped").view.proxy_rows
        XCTAssertEqual(rows.map(\.state_text), ["Active", "Ready", "Cooldown", "Paused", "Not mapped"])
        XCTAssertEqual(rows.map(FailoverModel.detailLine), rows.map(\.detail_text), "no in-flight tail at zero: the detail verbatim")
        XCTAssertEqual(rows.map(\.detail_text), ["", "", "until 05:00 · 2h 0m", "0 draining · resume anytime", "Not mapped to a saved Codex account"])
        for file in try Fixtures.projectionFiles() {
            let exported = try JSONDecoder().decode(Projection.self, from: Data(contentsOf: file)).view
            XCTAssertFalse(exported.proxy_rows.contains { $0.detail_text.hasPrefix("token ok") }, "\(file.lastPathComponent): C4 wording, no `token ok`")
        }
        XCTAssertEqual(FailoverModel.accessibilityValue(active), "expires 6d, 12 in flight", "VoiceOver reads the same detail")
        XCTAssertEqual(FailoverModel.accessibilityLabel(active), "user1@example.com, Active", "the state stays in the label")
    }



    func testStateBadgeStyleFollowsTheActiveAndMutedFlags() throws {
        XCTAssertEqual(FailoverModel.badgeStyle(try row(["state_accent": true, "label_muted": false])), .active)
        XCTAssertEqual(FailoverModel.badgeStyle(try row(["state_accent": false, "label_muted": false])), .ready)
        XCTAssertEqual(FailoverModel.badgeStyle(try row(["state_accent": false, "label_muted": true])), .muted)
        XCTAssertEqual(FailoverModel.badgeStyle(try row(["state_accent": false, "label_muted": true, "state_ok": true])), .muted, "`state_ok` never lifts a muted row")
        let rows = try fixture("proxy-reachable-mapped").view.proxy_rows
        XCTAssertEqual(rows.map(FailoverModel.badgeStyle), [.active, .ready, .muted, .muted, .muted])
        XCTAssertEqual(rows.map(\.state_text), ["Active", "Ready", "Cooldown", "Paused", "Not mapped"], "the badge text is the core's state word")
    }



    func testMenuIsShownOnlyWhenAVerbApplies() throws {
        XCTAssertTrue(FailoverModel.menuShown(try row(["has_actions": true])))
        XCTAssertFalse(FailoverModel.menuShown(try row(["has_actions": false])))
        let mismatch = try fixture("proxy-config-mismatch").view.proxy_rows
        XCTAssertTrue(mismatch.allSatisfy { !FailoverModel.menuShown($0) && FailoverModel.rowMenu($0).isEmpty }, "config mismatch: no … anywhere")
        let checking = try fixture("proxy-checking").view.proxy_rows
        XCTAssertTrue(checking.allSatisfy { !FailoverModel.menuShown($0) }, "work in flight: no … on any row")
        let mapped = try fixture("proxy-reachable-mapped").view.proxy_rows
        XCTAssertEqual(mapped.map(FailoverModel.menuShown), [true, true, true, true, false])
        XCTAssertEqual(mapped.map { FailoverModel.rowMenu($0).flatMap { $0 }.map(\.label) }, [
            ["Pause"], ["Use in failover…", "Pause"], ["Pause", "Clear cooldown…"], ["Resume"], [],
        ])
    }
}
