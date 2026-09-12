import AppKit
import SwiftUI
import XCTest
@testable import CodexMulti












@MainActor
final class StatusPillSpinTests: XCTestCase {
    override func setUp() {
        super.setUp()
        _ = MainActor.assumeIsolated { NSApplication.shared.setActivationPolicy(.accessory) }
    }



    private func inputs(accountWork: Bool = false, proxyWork: ProxyWork = .idle, reachability: ProxyReachability = .unknown,
                        attemptAt: Int64? = nil, revision: UInt64 = 0, pill: String = "Failover · unknown") -> RefreshSpin.Inputs {
        RefreshSpin.Inputs(accountWork: accountWork, proxyWork: proxyWork, read: RefreshSpin.ProxyRead(
            reachability: reachability, lastAttemptAt: attemptAt, lastAttemptResult: attemptAt == nil ? nil : .ok,
            lastSuccessAt: nil, successRevision: revision, pillText: pill))
    }



    func testSpinFollowsAccountWorkAndProxyWork() {
        var spin = RefreshSpin()
        XCTAssertFalse(spin.spinning)
        XCTAssertNil(spin.observe(inputs()), "idle at rest: no transition")
        XCTAssertEqual(spin.observe(inputs(proxyWork: .checking)), .started("proxy_work=checking"))
        XCTAssertTrue(spin.spinning)
        XCTAssertNil(spin.observe(inputs(proxyWork: .checking)), "still checking: no transition")
        XCTAssertEqual(spin.observe(inputs(proxyWork: .idle)), .stopped("idle"))
        XCTAssertFalse(spin.spinning)
        XCTAssertEqual(spin.observe(inputs(accountWork: true)), .started("busy_count>0"))
        XCTAssertNil(spin.observe(inputs(accountWork: true, proxyWork: .checking)), "already turning")
        XCTAssertNil(spin.observe(inputs(accountWork: false, proxyWork: .checking)), "proxy work keeps it turning")
        XCTAssertEqual(spin.observe(inputs()), .stopped("idle"))
    }





    func testSpinGoesStillWhenTheReadReportsWhileProxyWorkStaysUp() {
        var spin = RefreshSpin()
        XCTAssertEqual(spin.observe(inputs(proxyWork: .checking)), .started("proxy_work=checking"))
        XCTAssertEqual(spin.observe(inputs(proxyWork: .checking, reachability: .reachable, attemptAt: 100, revision: 1, pill: "Failover · Active a · 0 cooling")),
                       .stopped("read reported while proxy_work=checking"))
        XCTAssertFalse(spin.spinning)
        XCTAssertNil(spin.observe(inputs(proxyWork: .checking, reachability: .reachable, attemptAt: 100, revision: 1, pill: "Failover · Active a · 0 cooling")))
        XCTAssertNil(spin.observe(inputs(proxyWork: .idle, reachability: .reachable, attemptAt: 100, revision: 1, pill: "Failover · Active a · 0 cooling")), "already still")
        XCTAssertEqual(spin.observe(inputs(proxyWork: .checking, reachability: .reachable, attemptAt: 100, revision: 1, pill: "Failover · Active a · 0 cooling")),
                       .started("proxy_work=checking"), "a new cycle turns again")
        XCTAssertEqual(spin.observe(inputs(proxyWork: .checking, reachability: .reachable, attemptAt: 160, revision: 1, pill: "Failover · Active a · 0 cooling")),
                       .stopped("read reported while proxy_work=checking"))
        XCTAssertEqual(spin.observe(inputs(proxyWork: .switching, reachability: .reachable, attemptAt: 160, revision: 1, pill: "Failover · Active a · 0 cooling")),
                       .started("proxy_work=switching"), "different work without an idle in between")

        XCTAssertNil(spin.observe(inputs(accountWork: true, proxyWork: .switching, reachability: .reachable, attemptAt: 200, revision: 2, pill: "x")), "account work keeps it turning")
    }





    func testInputsReadTheProjectionFields() throws {
        let checking = try JSONDecoder().decode(Projection.self, from: Data(contentsOf: Fixtures.exported("proxy-checking"))).view
        let inputs = RefreshSpin.Inputs(checking)
        XCTAssertFalse(inputs.accountWork)
        XCTAssertEqual(inputs.proxyWork, .checking)
        XCTAssertEqual(inputs.read, RefreshSpin.ProxyRead(reachability: .unknown, lastAttemptAt: 1_784_948_355, lastAttemptResult: .ok,
                                                          lastSuccessAt: nil, successRevision: 0, pillText: "Failover · unknown"))
        let pending = try JSONDecoder().decode(Projection.self, from: Data(contentsOf: Fixtures.exported("notice-pending"))).view
        XCTAssertTrue(RefreshSpin.Inputs(pending).accountWork, "busy_count=1")
    }


    func testAngleIsOneTurnPerSecond() {
        let start = Date(timeIntervalSinceReferenceDate: 1000)
        XCTAssertEqual(RefreshSpin.angle(at: start).degrees, 0, accuracy: 1e-9)
        XCTAssertEqual(RefreshSpin.angle(at: start.addingTimeInterval(0.25)).degrees, 90, accuracy: 1e-9)
        XCTAssertEqual(RefreshSpin.angle(at: start.addingTimeInterval(1.5)).degrees, 180, accuracy: 1e-9)
    }






    func testGlyphIsAtRestOnTheFirstFrameAfterProxyWorkClears() throws {
        var spin = RefreshSpin()
        let idle = try projection("proxy-checking", proxyWork: "idle")
        let checking = try projection("proxy-checking")
        let start = Date(timeIntervalSinceReferenceDate: 1000.125)
        let rest = try glyph(turning: false, at: start)
        XCTAssertTrue(rest.contains { $0 > 64 }, "the rendered glyph contains visible pixels")
        XCTAssertEqual(pixelDifference(rest, try glyph(turning: false, at: start.addingTimeInterval(0.25))), 0)

        _ = spin.observe(.init(checking.view))
        let turning = try glyph(turning: spin.spinning, at: start)
        XCTAssertGreaterThan(pixelDifference(turning, try glyph(turning: spin.spinning, at: start.addingTimeInterval(0.25))), 20,
                          "busy frames render different arrow rotations")
        _ = spin.observe(.init(idle.view))
        for offset in [1.0 / 60.0, 0.25, 0.5, 0.75] {
            XCTAssertEqual(pixelDifference(rest, try glyph(turning: spin.spinning, at: start.addingTimeInterval(offset))), 0,
                           "every idle frame renders the unrotated glyph")
        }
    }

    func testGlyphIsAtRestOnceTheReadReportsWhileProxyWorkStaysUp() throws {
        var spin = RefreshSpin()
        let start = Date(timeIntervalSinceReferenceDate: 1000.125)
        let rest = try glyph(turning: false, at: start)
        _ = spin.observe(.init(try projection("proxy-checking").view))
        let turning = try glyph(turning: spin.spinning, at: start)
        XCTAssertGreaterThan(pixelDifference(turning, try glyph(turning: spin.spinning, at: start.addingTimeInterval(0.25))), 20)

        let reported = try projection("proxy-checking") { root, view in
            root["generation"] = 9
            view["proxy_last_attempt_at_unix_s"] = 1_784_948_399
            view["proxy_last_success_at_unix_s"] = 1_784_948_399
            view["proxy_success_revision"] = 1
            view["proxy_reachability"] = "reachable"
        }
        XCTAssertEqual(spin.observe(.init(reported.view)), .stopped("read reported while proxy_work=checking"))
        XCTAssertFalse(spin.spinning)
        XCTAssertEqual(pixelDifference(rest, try glyph(turning: spin.spinning, at: start.addingTimeInterval(1.0 / 60.0))), 0)
        XCTAssertEqual(pixelDifference(rest, try glyph(turning: spin.spinning, at: start.addingTimeInterval(0.25))), 0)
    }

    func testRenderingOpensNoVisibleWindow() throws {
        _ = try glyph(turning: true, at: Date(timeIntervalSinceReferenceDate: 1000.125))
        XCTAssertTrue(NSApp.windows.allSatisfy { !$0.isVisible }, "\(NSApp.windows)")
    }

    private func projection(_ name: String, proxyWork: String? = nil, mutate: (inout [String: Any], inout [String: Any]) -> Void = { _, _ in }) throws -> Projection {
        var root = try XCTUnwrap(JSONSerialization.jsonObject(with: Data(contentsOf: Fixtures.exported(name))) as? [String: Any])
        var view = try XCTUnwrap(root["view"] as? [String: Any])
        if let proxyWork {
            view["proxy_work"] = proxyWork
            root["generation"] = 2
        }
        mutate(&root, &view)
        root["view"] = view
        return try JSONDecoder().decode(Projection.self, from: Fixtures.data(from: root))
    }

    // Render the same glyph as RefreshButton at explicit timeline dates. Hidden
    // NSHostingView windows can yield no pixels and no display ticks on CI VMs.
    // The tests cover state transitions and rendered frames, not wall-clock latency.
    private func pixelDifference(_ a: [UInt8], _ b: [UInt8]) -> Int {
        // Repeated SF Symbol rasterization can differ by one 8-bit alpha level.
        a.count == b.count ? zip(a, b).filter { abs(Int($0) - Int($1)) > 1 }.count : max(a.count, b.count)
    }

    private func glyph(turning: Bool, at date: Date) throws -> [UInt8] {
        let renderer = ImageRenderer(content:
            RefreshGlyph(turning: turning, enabled: true, date: date)
                .environment(\.tone, Tone.light)
                .padding(8))
        renderer.scale = 2
        let image = try XCTUnwrap(renderer.cgImage)
        let width = image.width
        let height = image.height
        var rgba = [UInt8](repeating: 0, count: width * height * 4)
        let rendered = rgba.withUnsafeMutableBytes { bytes -> Bool in
            guard let context = CGContext(data: bytes.baseAddress, width: width, height: height,
                                          bitsPerComponent: 8, bytesPerRow: width * 4,
                                          space: CGColorSpaceCreateDeviceRGB(),
                                          bitmapInfo: CGImageAlphaInfo.premultipliedLast.rawValue) else { return false }
            context.draw(image, in: CGRect(x: 0, y: 0, width: width, height: height))
            return true
        }
        XCTAssertTrue(rendered)
        return stride(from: 3, to: rgba.count, by: 4).map { rgba[$0] }
    }
}
