import Foundation
import XCTest
@testable import CodexMulti

@MainActor
final class P12SettingsTests: XCTestCase {
    private func projection(_ name: String) throws -> Projection {
        try JSONDecoder().decode(Projection.self, from: Data(contentsOf: Fixtures.exported(name)))
    }

    func testGeneralRowsBindLaunchAndProjectedAutoRefreshPolicy() throws {
        let settings = try projection("c9-settings-launch-auto").view.settings
        XCTAssertTrue(settings.launch_at_login)
        XCTAssertTrue(settings.launch_at_login_registration_failed)
        XCTAssertEqual(PreferencesModel.launchAtLoginIntent(false), .set_launch_at_login(on: false))
        XCTAssertEqual(PreferencesModel.launchAtLoginFailureText(settings), Copy.launchAtLoginRegistrationFailed)
        XCTAssertEqual(settings.auto_refresh_minutes, 15)
        XCTAssertEqual(settings.auto_refresh_traffic_text,
                       "1 account × 4 refreshes/hour = 4 provider requests/hour.")
        XCTAssertEqual(PreferencesModel.autoRefreshOptions.map(\.minutes), [0, 15, 30, 60])
        XCTAssertEqual(PreferencesModel.autoRefreshOptions.map(\.label), ["Off", "15 min", "30 min", "1 hour"])
        XCTAssertEqual(PreferencesModel.autoRefreshIntent(60), .set_auto_refresh(minutes: 60))
    }

    func testWholeProxySwitchUsesProjectedStateAndRefusalDetail() throws {
        let settings = try projection("c9-proxy-switch-refused").view.settings
        XCTAssertTrue(settings.proxy_enabled)
        XCTAssertEqual(settings.proxy_enabled_detail_text,
                       "4 proxy request(s) are in flight. The switch will apply when they finish.")
        XCTAssertEqual(FailoverModel.proxyEnabledIntent(false), .set_proxy_enabled(on: false))
        XCTAssertEqual(Copy.useFailoverProxy, "Use the failover proxy")
    }

    func testInjectedLaunchRegistrationReportsSuccessAndFailureAfterPreference() async {
        let successCore = P12RecordingCore()
        let successRegistration = P12RegistrationRecorder()
        let successRouter = ShellIntentRouter(
            core: successCore,
            launchAtLogin: LaunchAtLoginRegistrar { successRegistration.values.append($0) })
        await successRouter.route(.set_launch_at_login(on: true))
        XCTAssertEqual(successRegistration.values, [true])
        let successIntents = await successCore.snapshot()
        XCTAssertEqual(successIntents, [
            .set_launch_at_login(on: true),
            .report_launch_at_login_registration_failure(failed: false),
        ])

        let failureCore = P12RecordingCore()
        let failureRegistration = P12RegistrationRecorder()
        let failureRouter = ShellIntentRouter(
            core: failureCore,
            launchAtLogin: LaunchAtLoginRegistrar {
                failureRegistration.values.append($0)
                throw P12RegistrationError.refused
            })
        await failureRouter.route(.set_launch_at_login(on: false))
        XCTAssertEqual(failureRegistration.values, [false])
        let failureIntents = await failureCore.snapshot()
        XCTAssertEqual(failureIntents, [
            .set_launch_at_login(on: false),
            .report_launch_at_login_registration_failure(failed: true),
        ])
    }
}

@MainActor
private final class P12RegistrationRecorder {
    var values: [Bool] = []
}

private enum P12RegistrationError: Error { case refused }

private actor P12RecordingCore: CoreProtocol {
    private var intents: [Intent] = []
    func start() async throws {}
    func submit(_ intent: Intent) async { intents.append(intent) }
    func pumpNow() async {}
    func shutdown() async {}
    func snapshot() -> [Intent] { intents }
}
