import Foundation
import XCTest
@testable import CodexMulti

final class EnumMirrorTests: XCTestCase {



    func testEnumsMirrorTheExportedTagNames() throws {
        let url = Fixtures.bridgeDirectory.appending(path: "enums.json")
        XCTAssertTrue(FileManager.default.fileExists(atPath: url.path), "fixtures/bridge/enums.json is not synced (scripts/sync-fixtures.sh --sync)")
        let document = try XCTUnwrap(JSONSerialization.jsonObject(with: Data(contentsOf: url)) as? [String: Any])
        XCTAssertEqual(document["schema"] as? Int, Int(CoreBridge.contractVersion))
        let entries = try XCTUnwrap(document["enums"] as? [[String: Any]])
        let exported = try Dictionary(uniqueKeysWithValues: entries.map {
            (try XCTUnwrap($0["name"] as? String), try XCTUnwrap($0["tags"] as? [String]))
        })
        let mirrored = Dictionary(uniqueKeysWithValues: ProjectionEnums.registry.map { ($0.zigName, $0.cases) })
        for (name, cases) in exported {
            XCTAssertEqual(mirrored[name], cases, "enum \(name) differs from the export")
        }
        XCTAssertEqual(Set(mirrored.keys).subtracting(exported.keys), [], "Swift enums with no exported counterpart")
    }

    func testRegistryNamesAreUniqueAndCasesAreSnakeCase() {
        let names = ProjectionEnums.registry.map(\.zigName)
        XCTAssertEqual(names.count, Set(names).count)
        for entry in ProjectionEnums.registry {
            XCTAssertEqual(entry.cases.count, Set(entry.cases).count, entry.zigName)
            for tag in entry.cases {
                XCTAssertTrue(tag.allSatisfy { $0.isLowercase || $0 == "_" }, "\(entry.zigName).\(tag) is not a Zig tag spelling")
            }
        }
    }
}
