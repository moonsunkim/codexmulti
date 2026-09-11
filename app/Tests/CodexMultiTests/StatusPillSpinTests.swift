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






    func testGlyphStopsWithinAFrameOfProxyWorkClearing() throws {
        let control = try Hosted(self, try projection("proxy-checking", proxyWork: "idle"))
        control.spin(0.2)
        let rest = control.glyph()
        control.spin(0.15)
        XCTAssertEqual(Hosted.differing(control.glyph(), rest), 0, "the control never moves")
        XCTAssertGreaterThan(rest.count, 0, "the glyph was found")

        let pill = try Hosted(self, try projection("proxy-checking"))
        pill.spin(0.2)
        let turning = pill.glyph()
        pill.spin(0.15)
        XCTAssertGreaterThan(Hosted.differing(pill.glyph(), turning), 0, "busy: the glyph turns")

        pill.store.publish(try projection("proxy-checking", proxyWork: "idle"))
        pill.spin(1.0 / 60.0)
        XCTAssertEqual(Hosted.differing(pill.glyph(), rest), 0, "idle: the glyph is at rest within a frame (pixels differing from the control)")
        for _ in 0..<3 {
            pill.spin(0.15)
            XCTAssertEqual(Hosted.differing(pill.glyph(), rest), 0, "idle: it stays at rest (pixels differing from the control)")
        }
    }



    func testGlyphIsAtRestOnceTheReadReportsWhileProxyWorkStaysUp() throws {
        let control = try Hosted(self, try projection("proxy-checking", proxyWork: "idle"))
        control.spin(0.2)
        let rest = control.glyph()

        let pill = try Hosted(self, try projection("proxy-checking"))
        pill.spin(0.2)
        let turning = pill.glyph()
        pill.spin(0.15)
        XCTAssertGreaterThan(Hosted.differing(pill.glyph(), turning), 0, "busy: the glyph turns")

        pill.store.publish(try projection("proxy-checking") { root, view in
            root["generation"] = 9
            view["proxy_last_attempt_at_unix_s"] = 1_784_948_399
            view["proxy_last_success_at_unix_s"] = 1_784_948_399
            view["proxy_success_revision"] = 1
            view["proxy_reachability"] = "reachable"
        })
        pill.spin(0.1)
        XCTAssertEqual(Hosted.differing(pill.glyph(), rest), 0, "read reported: at rest (pixels differing from the control)")
        pill.spin(0.15)
        XCTAssertEqual(Hosted.differing(pill.glyph(), rest), 0, "and stays at rest (pixels differing from the control)")
    }


    func testHostingOpensNoVisibleWindow() throws {
        let pill = try Hosted(self, try projection("proxy-checking"))
        pill.spin(0.1)
        XCTAssertFalse(pill.window.isVisible)
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

    private struct PillHost: View {
        let store: CoreStore
        var body: some View {
            if let projection = store.projection {
                RefreshButton(projection: projection)
                    .environment(\.tone, .light)
                    .environment(\.submit, { _ in })
                    .padding(20)
            }
        }
    }



    @MainActor
    private final class Hosted {
        let store: CoreStore
        let window: NSWindow
        private let hosting: NSHostingView<PillHost>
        private static let scale = 2

        init(_ test: XCTestCase, _ projection: Projection) throws {
            store = CoreStore()
            store.publish(projection)
            hosting = NSHostingView(rootView: PillHost(store: store))
            hosting.frame = NSRect(x: 0, y: 0, width: 400, height: 80)
            window = NSWindow(contentRect: NSRect(x: -20000, y: -20000, width: 400, height: 80), styleMask: .borderless, backing: .buffered, defer: true)
            window.isReleasedWhenClosed = false
            window.contentView = hosting
            hosting.layoutSubtreeIfNeeded()
            test.addTeardownBlock { @MainActor [window] in window.contentView = nil }
        }

        func spin(_ seconds: TimeInterval) {
            RunLoop.main.run(until: Date(timeIntervalSinceNow: seconds))
        }

        func glyph() -> [UInt8] {
            let width = Int(hosting.bounds.width) * Self.scale
            let height = Int(hosting.bounds.height) * Self.scale
            var bytes = [UInt8](repeating: 0, count: width * height * 4)
            bytes.withUnsafeMutableBytes { buffer in
                guard let layer = hosting.layer,
                      let context = CGContext(data: buffer.baseAddress, width: width, height: height, bitsPerComponent: 8, bytesPerRow: width * 4,
                                              space: CGColorSpaceCreateDeviceRGB(), bitmapInfo: CGImageAlphaInfo.premultipliedLast.rawValue) else { return }
                context.scaleBy(x: CGFloat(Self.scale), y: CGFloat(Self.scale))
                layer.render(in: context)
            }
            let alpha = (0..<height).map { y in (0..<width).map { x in bytes[(y * width + x) * 4 + 3] } }
            let inked = (0..<width).map { x in alpha.contains { $0[x] > 64 } }
            guard let last = inked.lastIndex(of: true) else { return [] }
            let columns = max(0, last - 20 * Self.scale)..<(last + 1)
            return alpha.flatMap { Array($0[columns]) }
        }

        static func differing(_ a: [UInt8], _ b: [UInt8]) -> Int {
            a.count == b.count ? zip(a, b).filter { $0 != $1 }.count : max(a.count, b.count)
        }
    }
}
