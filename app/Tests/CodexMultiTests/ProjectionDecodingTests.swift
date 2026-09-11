import Foundation
import XCTest
@testable import CodexMulti

final class ProjectionDecodingTests: XCTestCase {

    func testShowcaseExpandedAccountFixture() throws {
        let file = Fixtures.bridgeDirectory
            .deletingLastPathComponent()
            .appending(path: "showcase/accounts-expanded.json")
        let projection = try JSONDecoder().decode(Projection.self, from: Data(contentsOf: file))
        let accountRows = projection.view.account_rows
        let unifiedRows = projection.view.unified_rows
        let emails = accountRows.map { $0.email_local + $0.email_domain }

        XCTAssertEqual(accountRows.count, 7)
        XCTAssertEqual(Set(emails).count, 7)
        XCTAssertTrue(accountRows.allSatisfy { $0.has_domain && $0.email_domain.hasPrefix("@example.") })
        XCTAssertEqual(accountRows.map(\.plan).filter { $0 == "Plus" }.count, 1)
        XCTAssertEqual(unifiedRows.map(\.usage_percent_text), ["8%", "24%", "39%", "57%", "76%", "91%", "100%"])
        XCTAssertEqual(unifiedRows.filter { $0.failover_state == .active }.count, 1)
        XCTAssertEqual(unifiedRows.filter { $0.failover_state == .ready }.count, 2)
        XCTAssertEqual(unifiedRows.filter { $0.failover_state == .cooldown }.count, 3)
        XCTAssertEqual(unifiedRows.filter { $0.failover_state == .paused }.count, 1)
        XCTAssertEqual(projection.view.toolbar_status_text, "3 ready · 9 in flight")
        XCTAssertEqual(projection.shell.expanded, 6)
        XCTAssertTrue(accountRows.dropLast().allSatisfy { !$0.expanded })
        XCTAssertEqual(accountRows.last?.index, 6)
        XCTAssertEqual(accountRows.last?.expanded, true)
        XCTAssertEqual(unifiedRows.last?.inspector_index, 6)
        XCTAssertEqual(unifiedRows.last?.expanded, true)
        XCTAssertEqual(projection.view.usage_rows.first?.label, "Weekly")
        XCTAssertEqual(projection.view.usage_rows.first?.percent_text, "100%")
        XCTAssertEqual(projection.view.usage_rows.first?.reset_line, "resets Sep 16 12:47 KST")
        XCTAssertEqual(projection.view.inspector.index, 6)
        XCTAssertTrue(projection.view.inspector.present)
        XCTAssertEqual(projection.view.inspector.connection_line, "Connected")
        XCTAssertEqual(projection.view.inspector.failover_state, "Cooldown until Sep 16 12:48 · 4d 15h")
        XCTAssertEqual(projection.view.inspector.evidence_line, "Sep 11 20:59 KST")
        XCTAssertEqual(projection.view.inspector.credit_value, "1 available")
        XCTAssertEqual(projection.view.inspector.reset_label, "Use one reset (1 left)…")
        XCTAssertEqual(projection.view.inspector.updated_ago_text, "just now")
        XCTAssertEqual(accountRows.last?.reset_label, "Use one reset (1 left)…")
        XCTAssertEqual(unifiedRows.last?.reset_label, "Use one reset (1 left)…")
    }

    func testEveryFixtureDecodes() throws {
        let files = try Fixtures.projectionFiles()
        XCTAssertFalse(files.isEmpty, "no fixtures under \(Fixtures.bridgeDirectory.path)")
        for file in files {
            let projection = try JSONDecoder().decode(Projection.self, from: Data(contentsOf: file))
            XCTAssertEqual(projection.schema, 1, file.lastPathComponent)
            XCTAssertEqual(projection.view.tray_provider_headers.count, 2, file.lastPathComponent)


            XCTAssertEqual(projection.view.tray_provider_headers[0], "CODEX ACCOUNTS", file.lastPathComponent)
            XCTAssertEqual(projection.view.tray_provider_headers[1], "", file.lastPathComponent)
            XCTAssertEqual(projection.view.claude_row_count, 0, file.lastPathComponent)
            XCTAssertEqual(projection.view.claude_count, 0, file.lastPathComponent)
            XCTAssertEqual(projection.view.claude_group_title, "", file.lastPathComponent)
            XCTAssertEqual(projection.view.claude_group_summary, "", file.lastPathComponent)
            XCTAssertTrue(projection.view.rows.allSatisfy { $0.provider == .codex }, file.lastPathComponent)
            XCTAssertEqual(projection.view.account_rows.count, projection.view.account_row_count, file.lastPathComponent)
            XCTAssertLessThanOrEqual(projection.view.tray.items.count, 32, file.lastPathComponent)
        }
    }

    func testServiceFixturesCarryConcreteBundledDefaultPaths() throws {
        let names = ["not-installed", "installed-stale", "starting", "running", "unreachable"]
        for name in names {
            let projection = try JSONDecoder().decode(
                Projection.self, from: Data(contentsOf: Fixtures.exported("proxy-service-\(name)")))
            XCTAssertFalse(projection.view.proxy_cli_default_path.isEmpty, name)
            XCTAssertFalse(projection.view.proxy_node_default_path.isEmpty, name)
        }
    }

    func testPopulatedSampleDecodesEveryNestedType() throws {
        let projection = try JSONDecoder().decode(Projection.self, from: SampleProjection.populatedData(
            effects: [["kind": "show_settings"], ["kind": "clipboard", "text": "diag"], ["kind": "quit"]]))
        XCTAssertEqual(projection.generation, 2)
        XCTAssertEqual(projection.effects, [.show_settings, .clipboard(text: "diag"), .quit])
        XCTAssertEqual(projection.view.rows.first?.windows.first?.kind, .weekly)
        XCTAssertEqual(projection.view.rows.first?.primary, 0)
        XCTAssertNil(projection.view.rows.first?.proxy_cooldown_until_unix_s)
        XCTAssertEqual(projection.view.account_rows.first?.window.percent_text, "42%")
        XCTAssertEqual(projection.view.usage_rows.first?.has_meter, true)
        XCTAssertEqual(projection.view.inspector.credit_offer, .use_one)
        XCTAssertNil(projection.view.proxy_accounts.first?.storage_key)
        XCTAssertEqual(projection.view.proxy_rows.first?.state, .ready)
    }


    func testUnknownEnumSpellingFails() throws {
        var root = try Fixtures.emptyAttachedObject()
        var view = try XCTUnwrap(root["view"] as? [String: Any])
        view["proxy_work"] = "resting"
        root["view"] = view
        XCTAssertThrowsError(try JSONDecoder().decode(Projection.self, from: Fixtures.data(from: root)))

        var serviceRoot = try Fixtures.emptyAttachedObject()
        var serviceView = try XCTUnwrap(serviceRoot["view"] as? [String: Any])
        serviceView["proxy_service_state"] = "installed_current"
        serviceRoot["view"] = serviceView
        XCTAssertThrowsError(try JSONDecoder().decode(Projection.self, from: Fixtures.data(from: serviceRoot)))

        var routingRoot = try Fixtures.emptyAttachedObject()
        var routingView = try XCTUnwrap(routingRoot["view"] as? [String: Any])
        routingView["codex_routing_state"] = "mixed"
        routingRoot["view"] = routingView
        XCTAssertThrowsError(try JSONDecoder().decode(Projection.self, from: Fixtures.data(from: routingRoot)))
    }


    func testMissingKeyFailsAndNullDecodesToNil() throws {
        var root = try Fixtures.emptyAttachedObject()
        var runtime = try XCTUnwrap(root["runtime"] as? [String: Any])
        runtime["error"] = NSNull()
        root["runtime"] = runtime
        XCTAssertNil(try JSONDecoder().decode(Projection.self, from: Fixtures.data(from: root)).runtime.error)
        runtime.removeValue(forKey: "started")
        root["runtime"] = runtime
        XCTAssertThrowsError(try JSONDecoder().decode(Projection.self, from: Fixtures.data(from: root)))

        var viewRoot = try Fixtures.emptyAttachedObject()
        var view = try XCTUnwrap(viewRoot["view"] as? [String: Any])
        view.removeValue(forKey: "proxy_service_state")
        viewRoot["view"] = view
        XCTAssertThrowsError(try JSONDecoder().decode(Projection.self, from: Fixtures.data(from: viewRoot)))
    }





    func testPopulatedSampleCarriesExactlyTheContractKeys() throws {
        let mismatches = ProjectionKeyWalker.mismatches(in: try SampleProjection.populated())
        XCTAssertEqual(mismatches, [], mismatches.joined(separator: "\n"))
    }

    func testEveryFixtureCarriesExactlyTheContractKeys() throws {
        for file in try Fixtures.projectionFiles() {
            let object = try XCTUnwrap(JSONSerialization.jsonObject(with: Data(contentsOf: file)) as? [String: Any])
            let mismatches = ProjectionKeyWalker.mismatches(in: object)
            XCTAssertEqual(mismatches, [], "\(file.lastPathComponent):\n" + mismatches.joined(separator: "\n"))
        }
    }
}



enum ProjectionKeyWalker {

    static let schema: [String: [String]] = [
        "": keys(Projection.CodingKeys.self),
        "runtime": keys(RuntimeState.CodingKeys.self),
        "shell": keys(ShellState.CodingKeys.self),
        "shell.notice": keys(Notice.CodingKeys.self),
        "shell.add_account": keys(AddAccountFlow.CodingKeys.self),
        "shell.reset": keys(ResetFlow.CodingKeys.self),
        "shell.remove": keys(RemoveFlow.CodingKeys.self),
        "shell.rename": keys(RenameFlow.CodingKeys.self),
        "shell.failover_switch": keys(FailoverSwitchFlow.CodingKeys.self),
        "shell.clear_cooldown": keys(ClearCooldownFlow.CodingKeys.self),
        "view": keys(ViewState.CodingKeys.self),
        "view.capabilities": keys(ServiceCapabilities.CodingKeys.self),
        "view.proxy_accounts[]": keys(ProxyAccountFact.CodingKeys.self),
        "view.proxy_rows[]": keys(ProxyAccountView.CodingKeys.self),
        "view.unified_rows[]": keys(UnifiedRowView.CodingKeys.self),
        "view.settings": keys(SettingsView.CodingKeys.self),
        "view.rows[]": keys(AccountView.CodingKeys.self),
        "view.rows[].windows[]": keys(WindowView.CodingKeys.self),
        "view.usage_rows[]": keys(UsageRow.CodingKeys.self),
        "view.inspector": keys(Inspector.CodingKeys.self),
        "view.account_rows[]": keys(AccountRowView.CodingKeys.self),
        "view.account_rows[].chip_a": keys(RowChip.CodingKeys.self),
        "view.account_rows[].chip_b": keys(RowChip.CodingKeys.self),
        "view.account_rows[].window": keys(WindowCell.CodingKeys.self),
        "view.tray": keys(Tray.CodingKeys.self),
        "view.tray.items[]": keys(TrayItem.CodingKeys.self),
    ]


    static func expectedEffectKeys(_ object: [String: Any]) -> [String] {
        (object["kind"] as? String) == "clipboard" ? ["kind", "text"] : ["kind"]
    }

    static func keys<K: CodingKey & CaseIterable>(_ type: K.Type) -> [String] {
        K.allCases.map(\.stringValue)
    }

    static func mismatches(in root: [String: Any]) -> [String] {
        var out: [String] = []
        walk(root, path: "", into: &out)
        return out
    }

    private static func walk(_ object: [String: Any], path: String, into out: inout [String]) {
        let expected: [String]?
        if path == "effects[]" {
            expected = expectedEffectKeys(object)
        } else {
            expected = schema[path]
        }
        guard let expected else {
            out.append("\(path.isEmpty ? "<root>" : path): no type mapped for this path")
            return
        }
        let actual = Set(object.keys)
        let wanted = Set(expected)
        for key in wanted.subtracting(actual).sorted() { out.append("\(path.isEmpty ? "<root>" : path): missing \(key)") }
        for key in actual.subtracting(wanted).sorted() { out.append("\(path.isEmpty ? "<root>" : path): unknown \(key)") }
        for (key, value) in object {
            let child = path.isEmpty ? key : "\(path).\(key)"
            if let nested = value as? [String: Any] {
                walk(nested, path: child, into: &out)
            } else if let array = value as? [Any] {
                for element in array {
                    if let nested = element as? [String: Any] { walk(nested, path: "\(child)[]", into: &out) }
                }
            }
        }
    }
}
