import Foundation
import XCTest
@testable import CodexMulti





final class ProvenanceMarkerTests: XCTestCase {
    private static let expectedBridgeMarker = "CODEXMULTI_BRIDGE_SCHEMA=1"


    private func retainedStrings() throws -> Set<String> {
        let executable = LifecycleIntegrationTests.executable
        XCTAssertTrue(FileManager.default.isExecutableFile(atPath: executable.path), "built product missing: \(executable.path)")
        let process = Process()
        process.executableURL = URL(fileURLWithPath: "/usr/bin/strings")
        process.arguments = ["-a", executable.path]
        let pipe = Pipe()
        process.standardOutput = pipe
        process.standardError = FileHandle.nullDevice
        try process.run()
        let data = pipe.fileHandleForReading.readDataToEndOfFile()
        process.waitUntilExit()
        XCTAssertEqual(process.terminationStatus, 0, "strings failed")
        return Set(String(decoding: data, as: UTF8.self).split(separator: "\n").map(String.init))
    }

    func testBuiltExecutableRetainsTheBridgeSchemaMarker() throws {
        let strings = try retainedStrings()
        XCTAssertTrue(strings.contains(Self.expectedBridgeMarker),
                      "the built CodexMulti does not retain \(Self.expectedBridgeMarker); verify-provenance.sh fails closed")
    }

    func testBridgeSchemaMarkerMatchesTheContractVersionAndInfoPlist() throws {
        XCTAssertEqual(BridgeProvenance.bridgeSchemaMarker.description, Self.expectedBridgeMarker)
        XCTAssertEqual(BridgeProvenance.bridgeSchemaMarker.description,
                       BridgeProvenance.bridgeSchemaPrefix + String(CoreBridge.contractVersion))
        let plist = Fixtures.bridgeDirectory
            .deletingLastPathComponent().deletingLastPathComponent()
            .appending(path: "Resources/Info.plist")
        let object = try PropertyListSerialization.propertyList(from: Data(contentsOf: plist), format: nil) as? [String: Any]
        XCTAssertEqual(try XCTUnwrap(object?["CodexMultiBridgeSchema"] as? Int), Int(CoreBridge.contractVersion))
    }



    func testBuiltExecutableRetainsTheCoreSourceMarkerTheLinkedCoreReports() throws {
        let marker = CoreABI.live.provenance()
        XCTAssertNotNil(marker.wholeMatch(of: /CODEXMULTI_CORE_SRC_SHA256=[0-9a-f]{64}/), "unexpected core marker: \(marker)")
        XCTAssertTrue(try retainedStrings().contains(marker), "the built CodexMulti does not retain \(marker)")
    }



    @MainActor
    func testCoreBridgeReadsTheProvenanceOnStart() async throws {
        let fake = FakeABI(bytes: try Fixtures.emptyAttachedData())
        let store = CoreStore()
        let bridge = CoreBridge(store: store, effects: RecordingEffects().runner, abi: fake.abi, pumpInterval: .seconds(60))
        try await bridge.start()
        XCTAssertEqual(fake.provenanceReads, 1)
        await bridge.shutdown()
    }
}
