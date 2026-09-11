import Foundation
import XCTest
@testable import CodexMulti

@MainActor
final class P19CodexSettingsTests: XCTestCase {
    private func settings() throws -> SettingsView {
        try JSONDecoder().decode(
            Projection.self,
            from: Data(contentsOf: Fixtures.exported("settings-appearance-system"))
        ).view.settings
    }

    func testCodexSectionUsesEveryProjectedValueAndPieceOfCopy() throws {
        let settings = try settings()

        XCTAssertEqual(PreferencesModel.sectionLayout[1].title(settings: settings), settings.codex_section_title)
        XCTAssertEqual(PreferencesModel.Row.codexUsageWindow.label(settings: settings), settings.codex_usage_window_label)
        XCTAssertEqual(PreferencesModel.Row.codexShowModelLimits.label(settings: settings), settings.codex_show_model_limits_label)
        XCTAssertEqual(settings.codex_usage_window, .auto)
        XCTAssertEqual(settings.codex_usage_window_supported, [.auto, .weekly, .session])
        XCTAssertEqual(settings.codex_usage_window_detail_text,
                       "Prefer a usage window when the provider reports it.")
        XCTAssertFalse(settings.codex_show_model_limits)
        XCTAssertEqual(settings.codex_show_model_limits_supported, [false, true])
        XCTAssertEqual(settings.codex_show_model_limits_detail_text,
                       "Show reported model limits in account details and headlines.")
    }

    func testCodexSelectionsSubmitOnlySupportedChanges() throws {
        let settings = try settings()
        let recorder = P19IntentRecorder()

        PreferencesModel.selectCodexUsageWindow(
            .weekly,
            current: settings.codex_usage_window,
            supported: settings.codex_usage_window_supported,
            submit: recorder.sink)
        PreferencesModel.selectCodexUsageWindow(
            .auto,
            current: settings.codex_usage_window,
            supported: settings.codex_usage_window_supported,
            submit: recorder.sink)
        PreferencesModel.selectCodexShowModelLimits(
            true,
            current: settings.codex_show_model_limits,
            supported: settings.codex_show_model_limits_supported,
            submit: recorder.sink)
        PreferencesModel.selectCodexShowModelLimits(
            false,
            current: settings.codex_show_model_limits,
            supported: settings.codex_show_model_limits_supported,
            submit: recorder.sink)

        XCTAssertEqual(recorder.intents, [
            .set_codex_usage_window(value: .weekly),
            .set_codex_show_model_limits(on: true),
        ])
    }
}

@MainActor
private final class P19IntentRecorder {
    var intents: [Intent] = []
    var sink: IntentSink { { [weak self] intent in self?.intents.append(intent) } }
}
