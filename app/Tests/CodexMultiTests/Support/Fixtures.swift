import Foundation
import XCTest
@testable import CodexMulti


enum Fixtures {
    static let bridgeDirectory: URL = URL(fileURLWithPath: #filePath)
        .deletingLastPathComponent()
        .deletingLastPathComponent()
        .deletingLastPathComponent()
        .deletingLastPathComponent()
        .appending(path: "fixtures/bridge", directoryHint: .isDirectory)

    static func projectionFiles() throws -> [URL] {
        try FileManager.default.contentsOfDirectory(at: bridgeDirectory, includingPropertiesForKeys: nil)
            .filter { $0.lastPathComponent.hasPrefix("viewstate-") && $0.pathExtension == "json" }
            .sorted { $0.lastPathComponent < $1.lastPathComponent }
    }


    static func exported(_ name: String) -> URL {
        bridgeDirectory.appending(path: "viewstate-\(name).json")
    }


    static var emptyAttached: URL { exported("empty-attached") }

    static func emptyAttachedData() throws -> Data {
        try Data(contentsOf: emptyAttached)
    }


    static func emptyAttachedObject() throws -> [String: Any] {
        try XCTUnwrap(JSONSerialization.jsonObject(with: emptyAttachedData()) as? [String: Any])
    }

    static func data(from object: [String: Any]) throws -> Data {
        try JSONSerialization.data(withJSONObject: object, options: [.sortedKeys])
    }
}
