import Foundation
import XCTest
@testable import CodexMulti

final class PipelineAndFixtureCoreTests: XCTestCase {

    func testPipelineSkipsByteIdenticalDocuments() throws {
        var pipeline = ProjectionPipeline()
        let bytes = try Fixtures.emptyAttachedData()
        guard case .published(let first) = pipeline.ingest(bytes) else { return XCTFail("first ingest must publish") }
        XCTAssertEqual(first.generation, 1)
        XCTAssertEqual(pipeline.ingest(bytes), .unchanged)
        XCTAssertEqual(pipeline.ingest(Data(bytes)), .unchanged)

        var padded = bytes
        padded.append(contentsOf: "\n".utf8)
        guard case .published(let again) = pipeline.ingest(padded) else { return XCTFail("padded ingest must publish") }
        XCTAssertEqual(again, first)
    }



    func testPipelineRejectsUndecodableDocumentsOnce() throws {
        var pipeline = ProjectionPipeline()
        _ = pipeline.ingest(try Fixtures.emptyAttachedData())
        let broken = Data(#"{"schema":1,"generation":9,"serialize_error":"out_of_memory"}"#.utf8)
        guard case .rejected(let generation, let reason) = pipeline.ingest(broken) else { return XCTFail("must reject") }
        XCTAssertEqual(generation, 9)
        XCTAssertTrue(reason.contains("serialize_error=out_of_memory"), reason)
        XCTAssertEqual(pipeline.lastGeneration, 1)
        XCTAssertEqual(pipeline.ingest(broken), .unchanged)
    }



    @MainActor
    func testEffectsRunOnceThroughTheFixtureCore() async throws {
        let store = CoreStore()
        let effects = RecordingEffects()
        let data = try SampleProjection.populatedData(effects: [
            ["kind": "show_settings"], ["kind": "clipboard", "text": "diag"], ["kind": "quit"],
        ])
        let core = FixtureCore(data: data, store: store, effects: effects.runner)
        try await core.start()
        await core.pumpNow()
        await core.submit(.refresh_all)
        await core.pumpNow()
        XCTAssertEqual(store.publishCount, 1)
        XCTAssertEqual(effects.runner.runCount, 3)
        XCTAssertEqual(effects.showSettings, 1)
        XCTAssertEqual(effects.clipboard, ["diag"])
        XCTAssertEqual(effects.quits, 1)
        XCTAssertEqual(effects.replies, [.diagnostics_copied(ok: true)])
        let submitted = await core.submitted
        XCTAssertEqual(submitted, [.refresh_all])
    }



    @MainActor
    func testFixtureCoreRecordsIntentsAndNeverMutates() async throws {
        let store = CoreStore()
        let effects = RecordingEffects()
        let core = try FixtureCore(contentsOf: Fixtures.emptyAttached, store: store, effects: effects.runner)
        try await core.start()
        await core.submit(.toggle_account(row: 0))
        await core.submit(.claude_tray_weekly)
        let submitted = await core.submitted
        XCTAssertEqual(submitted, [.toggle_account(row: 0), .claude_tray_weekly])
        XCTAssertEqual(store.projection?.shell.claude_tray_window, .weekly)
        XCTAssertEqual(store.publishCount, 1)
        await core.shutdown()
        let running = await core.isRunning
        XCTAssertFalse(running)
    }

    @MainActor
    func testFixtureCoreRefusesAnUndecodableFixture() async throws {
        let store = CoreStore()
        let core = FixtureCore(data: Data("{}".utf8), store: store, effects: RecordingEffects().runner)
        do {
            try await core.start()
            XCTFail("start must throw")
        } catch let error as FixtureCoreError {
            guard case .undecodable = error else { return XCTFail("\(error)") }
        }
        XCTAssertNil(store.projection)
    }
}
