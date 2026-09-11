import SwiftUI
import XCTest
@testable import CodexMulti




final class BundledProxyLifecycleTests: XCTestCase {
    private func projection(_ name: String) throws -> Projection {
        try JSONDecoder().decode(Projection.self, from: Data(contentsOf: Fixtures.exported("proxy-service-\(name)")))
    }

    private func view(_ overrides: [String: Any], from name: String) throws -> ViewState {
        var root = try XCTUnwrap(JSONSerialization.jsonObject(
            with: Data(contentsOf: Fixtures.exported("proxy-service-\(name)"))) as? [String: Any])
        var object = try XCTUnwrap(root["view"] as? [String: Any])
        for (key, value) in overrides { object[key] = value }
        var settings = try XCTUnwrap(object["settings"] as? [String: Any])
        for (key, value) in overrides where settings[key] != nil { settings[key] = value }
        object["settings"] = settings
        root["view"] = object
        return try JSONDecoder().decode(Projection.self, from: Fixtures.data(from: root)).view
    }

    private func ids(_ actions: [FailoverModel.LifecycleAction]) -> [FailoverModel.LifecycleAction.ID] {
        actions.map(\.id)
    }

    func testFiveServiceStateBannerAndActionMatrixUsesOnlyProjection() throws {
        let cases: [(String, ProxyServiceState, String, [FailoverModel.LifecycleAction.ID], [FailoverModel.LifecycleAction.ID])] = [
            ("not-installed", .not_installed, "Proxy service is not installed", [.install], []),
            ("installed-stale", .installed_stale, "Bundled proxy files or receipt changed; repair is required.", [.repair], []),
            ("starting", .starting, "Waiting for 2 proxy request(s) to finish", [], [.disableRouting]),
            ("running", .running, "Bundled proxy service is running.", [.stop], [.enableRouting]),
            ("unreachable", .unreachable, "Proxy service is installed but unreachable.", [.repair], [.disableRouting]),
        ]
        for (name, state, detail, service, routing) in cases {
            let view = try projection(name).view
            XCTAssertEqual(view.proxy_service_state, state, name)
            XCTAssertEqual(view.proxy_service_detail_text, detail, name)
            XCTAssertEqual(ids(FailoverModel.serviceActions(view)), service, name)
            XCTAssertEqual(ids(FailoverModel.routingActions(view)), routing, name)
        }
        XCTAssertEqual(Set(cases.map { $0.1.rawValue }), Set(ProxyServiceState.allCases.map(\.rawValue)))
    }

    func testFirstRunHasExactlyOneInstallActionAndProjectedDisablement() throws {
        let firstRun = try projection("not-installed").view
        let actions = FailoverModel.serviceActions(firstRun) + FailoverModel.routingActions(firstRun)
        XCTAssertEqual(firstRun.proxy_service_detail_text, "Proxy service is not installed")
        XCTAssertEqual(actions.count, 1)
        XCTAssertEqual(actions[0].title, "Install & Start")
        XCTAssertEqual(actions[0].intent, .install_proxy_service)
        XCTAssertTrue(actions[0].enabled)

        let ineligible = try view(["proxy_service_can_install": false], from: "not-installed")
        let disabled = FailoverModel.serviceActions(ineligible)
        XCTAssertEqual(disabled.count, 1, "first run keeps its sole explanation/action visible")
        XCTAssertFalse(disabled[0].enabled, "install enablement is the projected boolean")
        var gate = ProxyConfirmationGate()
        XCTAssertNil(gate.request(disabled[0]), "a disabled action cannot submit")
        XCTAssertNil(gate.pending)
    }

    func testPositiveCountRepairRemainsActionableAndStartingDetailIsVerbatim() throws {
        let waitingRepair = try view([
            "proxy_service_detail_text": "Waiting for 3 proxy request(s) before repair",
            "proxy_in_flight": 3,
            "proxy_service_can_repair": true,
        ], from: "installed-stale")
        XCTAssertEqual(waitingRepair.proxy_service_detail_text, "Waiting for 3 proxy request(s) before repair")
        XCTAssertEqual(ids(FailoverModel.serviceActions(waitingRepair)), [.repair])
        XCTAssertTrue(FailoverModel.serviceActions(waitingRepair)[0].enabled)

        let starting = try projection("starting").view
        XCTAssertEqual(starting.proxy_service_detail_text, "Waiting for 2 proxy request(s) to finish")
        XCTAssertEqual(FailoverModel.serviceActions(starting), [])
    }

    func testRepairAndStopShareCancelAndSingleConfirmGate() throws {
        let cases: [(FailoverModel.LifecycleAction, Intent)] = [
            (try XCTUnwrap(FailoverModel.serviceActions(projection("installed-stale").view).first), .repair_proxy_service),
            (try XCTUnwrap(FailoverModel.serviceActions(projection("running").view).first), .stop_proxy_service),
        ]
        for (action, expected) in cases {
            var submitted: [Intent] = []
            var gate = ProxyConfirmationGate()
            if let intent = gate.request(action) { submitted.append(intent) }
            XCTAssertEqual(gate.pending?.kind, .clientQuiescence, action.title)
            XCTAssertEqual(gate.pending?.title, Copy.clientQuiescenceTitle, action.title)
            XCTAssertEqual(gate.pending?.message, Copy.clientQuiescenceMessage, action.title)
            gate.cancel(.clientQuiescence)
            XCTAssertEqual(submitted, [], "cancel submits nothing: \(action.title)")

            if let intent = gate.request(action) { submitted.append(intent) }
            if let intent = gate.confirm(.clientQuiescence) { submitted.append(intent) }
            if let intent = gate.confirm(.clientQuiescence) { submitted.append(intent) }
            XCTAssertEqual(submitted, [expected], "confirm consumes the existing intent once: \(action.title)")
        }
        XCTAssertTrue(cases.allSatisfy { $0.0.confirmation == .clientQuiescence })
    }

    func testRoutingOffOnAndConflictingUseFalseDirectTrueConfirmed() throws {
        let off = try projection("running").view
        let ordinary = try XCTUnwrap(FailoverModel.routingActions(off).first)
        XCTAssertEqual(ordinary.intent, .enable_codex_routing(replace_conflicting: false))
        var directGate = ProxyConfirmationGate()
        XCTAssertEqual(directGate.request(ordinary), .enable_codex_routing(replace_conflicting: false))
        XCTAssertNil(directGate.pending)

        let on = try view(["codex_routing_state": "on"], from: "running")
        XCTAssertEqual(FailoverModel.routingActions(on).map(\.intent), [.disable_codex_routing])

        let conflicting = try view(["codex_routing_state": "conflicting"], from: "running")
        let replacement = try XCTUnwrap(FailoverModel.routingActions(conflicting).first)
        XCTAssertEqual(replacement.intent, .enable_codex_routing(replace_conflicting: true))
        var submitted: [Intent] = []
        var replacementGate = ProxyConfirmationGate()
        if let intent = replacementGate.request(replacement) { submitted.append(intent) }
        XCTAssertEqual(replacementGate.pending?.kind, .replaceRouting)
        XCTAssertEqual(replacementGate.pending?.title, Copy.replaceRoutingTitle)
        replacementGate.cancel(.replaceRouting)
        XCTAssertEqual(submitted, [])
        _ = replacementGate.request(replacement)
        if let intent = replacementGate.confirm(.replaceRouting) { submitted.append(intent) }
        if let intent = replacementGate.confirm(.replaceRouting) { submitted.append(intent) }
        XCTAssertEqual(submitted, [.enable_codex_routing(replace_conflicting: true)])
    }

    func testDefaultsAreReadOnlyTruthAndEmptyOverridesRemainDefaults() throws {
        let view = try projection("running").view
        XCTAssertEqual(view.proxy_cli_default_path,
                       "/Applications/CodexMulti.app/Contents/Resources/proxy/bin/codexmulti-proxy")
        XCTAssertEqual(view.proxy_node_default_path, "/Applications/CodexMulti.app/Contents/Helpers/node")
        XCTAssertEqual(Copy.advancedOverrides, "Advanced overrides")

        var drafts = ProxyDrafts()
        drafts.seedIfNeeded(from: view)
        XCTAssertEqual(drafts.cli_path, "")
        XCTAssertEqual(drafts.node_path, "")
        XCTAssertEqual(drafts.saveIntent, .save_proxy_settings(base_url: "", cli_path: "", config_path: "", node_path: ""))
        drafts.base_url = "http://127.0.0.1:9999"
        drafts.config_path = "/tmp/explicit-config.json"
        drafts.cli_path = "/tmp/explicit-cli"
        drafts.node_path = "/tmp/explicit-node"
        XCTAssertEqual(drafts.saveIntent, .save_proxy_settings(
            base_url: "http://127.0.0.1:9999", cli_path: "/tmp/explicit-cli",
            config_path: "/tmp/explicit-config.json", node_path: "/tmp/explicit-node"))
    }

    func testLifecycleAndRoutingAccessibilityLabelsAreStable() throws {
        let running = try projection("running").view
        XCTAssertEqual(Copy.proxy, "Proxy")
        XCTAssertEqual(running.proxy_service_detail_text, "Bundled proxy service is running.")
        XCTAssertEqual(Copy.codexRouting, "Codex routing")
        XCTAssertEqual(FailoverModel.routingStateText(.off), "Off")
        XCTAssertEqual(FailoverModel.routingStateText(.on), "On")
        XCTAssertEqual(FailoverModel.routingStateText(.conflicting), "Conflicting")
        XCTAssertEqual(FailoverModel.serviceActions(running).map(\.title), ["Stop Proxy Service"])
        XCTAssertEqual(FailoverModel.routingActions(running).map(\.title), ["Enable for Codex"])
        XCTAssertEqual(Copy.bundledProxyCLIDefault, "Bundled Proxy CLI default")
        XCTAssertEqual(Copy.bundledNodeDefault, "Bundled Node default")
    }

    @MainActor
    func testRenderingAndAppearanceSubmitNoServiceIntent() throws {
        let recorder = LifecycleIntentRecorder()
        let panel = ProxyLifecyclePanel(view: try projection("running").view)
            .environment(\.tone, .light)
            .environment(\.submit, recorder.sink)
            .frame(width: 720)
        let renderer = ImageRenderer(content: panel)
        renderer.scale = 2
        XCTAssertNotNil(renderer.cgImage)
        XCTAssertEqual(recorder.intents, [], "body evaluation and off-screen appearance are passive")
    }
}

@MainActor
private final class LifecycleIntentRecorder {
    var intents: [Intent] = []
    var sink: IntentSink { { [weak self] intent in self?.intents.append(intent) } }
}
