import Foundation
import XCTest
@testable import CodexMulti

final class CoreBridgeTests: XCTestCase {

    @MainActor
    func testRefusesAVersionMismatchBeforeCreate() async throws {
        let fake = FakeABI(bytes: try Fixtures.emptyAttachedData())
        fake.version = 2
        let store = CoreStore()
        let bridge = CoreBridge(store: store, effects: RecordingEffects().runner, abi: fake.abi)
        do {
            try await bridge.start()
            XCTFail("start must throw")
        } catch let error as CoreBridgeError {
            XCTAssertEqual(error, .versionMismatch(found: 2, expected: 1))
        }
        XCTAssertEqual(fake.creates, 0)
        let running = await bridge.isRunning
        XCTAssertFalse(running)
        XCTAssertNil(store.projection)
    }




    @MainActor
    func testStartSubmitPumpAndShutdownAgainstAFakeCore() async throws {
        let fake = FakeABI(bytes: try Fixtures.emptyAttachedData())
        let store = CoreStore()
        let effects = RecordingEffects()
        let bridge = CoreBridge(store: store, effects: effects.runner, abi: fake.abi, pumpInterval: .seconds(60))

        try await bridge.start()
        XCTAssertEqual(fake.creates, 1)
        XCTAssertEqual(fake.submittedIntentNames, [])
        await waitUntil { store.publishCount == 1 }
        XCTAssertEqual(store.projection?.generation, 1)
        XCTAssertEqual(fake.pumps, [], "start must not pump")

        await bridge.submit(.toggle_account(row: 0))
        XCTAssertEqual(fake.submittedIntentNames, ["toggle_account"])
        XCTAssertEqual(fake.pumps, [], "submit must not pump (§2.2)")
        XCTAssertEqual(fake.projects, 2)

        let before = Int64(Date().timeIntervalSince1970.rounded(.down))
        await bridge.pumpNow()
        XCTAssertEqual(fake.pumps.count, 1)
        XCTAssertGreaterThanOrEqual(fake.pumps[0], before)
        XCTAssertLessThanOrEqual(fake.pumps[0], before + 1)
        try await Task.sleep(for: .milliseconds(50))
        XCTAssertEqual(store.publishCount, 1, "byte-identical projections are not re-published")

        fake.bytes = try SampleProjection.populatedData(generation: 7, effects: [["kind": "show_settings"]])
        await bridge.pumpNow()
        await waitUntil { store.publishCount == 2 }
        XCTAssertEqual(store.projection?.generation, 7)
        XCTAssertEqual(effects.showSettings, 1)
        let generation = await bridge.lastGeneration
        XCTAssertEqual(generation, 7)

        await bridge.shutdown()
        XCTAssertEqual(fake.destroys, 1)
        let running = await bridge.isRunning
        XCTAssertFalse(running)
        await bridge.submit(.refresh_all)
        XCTAssertEqual(fake.submittedIntentNames.count, 1)
    }



    @MainActor
    func testStartSubmitsNoSyntheticIntent() async throws {
        let fake = FakeABI(bytes: try Fixtures.emptyAttachedData())
        let store = CoreStore()
        let bridge = CoreBridge(store: store, effects: RecordingEffects().runner, abi: fake.abi, pumpInterval: .seconds(60))
        try await bridge.start()
        XCTAssertEqual(fake.submittedIntentNames, [])
        await waitUntil { store.publishCount == 1 }
        await bridge.pumpNow()
        XCTAssertEqual(fake.submittedIntentNames, [])
        await bridge.shutdown()
    }


    @MainActor
    func testPumpTimerFiresAndStopsAtShutdown() async throws {
        let fake = FakeABI(bytes: try Fixtures.emptyAttachedData())
        let store = CoreStore()
        let bridge = CoreBridge(store: store, effects: RecordingEffects().runner, abi: fake.abi, pumpInterval: .milliseconds(40))
        try await bridge.start()
        await waitUntil(timeout: .seconds(3)) { fake.pumps.count >= 3 }
        XCTAssertGreaterThanOrEqual(fake.pumps.count, 3)
        await bridge.shutdown()
        let atShutdown = fake.pumps.count
        try await Task.sleep(for: .milliseconds(200))
        XCTAssertEqual(fake.pumps.count, atShutdown, "timer must stop at shutdown")
        let count = await bridge.pumpCount
        XCTAssertEqual(count, atShutdown)
    }






    func testLiveObjectLinksAndAnswersTheContractVersion() {
        XCTAssertEqual(CoreABI.live.version(), CoreBridge.contractVersion)
    }
}
