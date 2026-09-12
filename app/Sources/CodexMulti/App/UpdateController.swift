import AppKit
import Foundation
import Observation
import Sparkle
import UpdaterKit

struct UpdateEnvironment: Sendable {
    var root = RuntimeStore.defaultRoot
    var launch = LaunchService()
    var serviceLabel = "dev.codexmulti.app.proxy"
}

@MainActor @Observable
final class UpdateController: NSObject, SPUUserDriver, SPUUpdaterDelegate {
    static let shared = UpdateController()
    private(set) var journal: UpdateJournal?
    private(set) var status = "unconfigured"
    private(set) var offeredVersion: String?
    private(set) var progress: Double?
    private(set) var needsMigration = false
    private(set) var pendingRuntime = false
    private(set) var started = false
    @ObservationIgnored private(set) var lastError: NSError?
    @ObservationIgnored private var updater: SPUUpdater?
    @ObservationIgnored private var core: (any CoreProtocol)?
    @ObservationIgnored private weak var coreStore: CoreStore?
    @ObservationIgnored private var runtimeStore: RuntimeStore?
    @ObservationIgnored private var monitor: Task<Void, Never>?
    @ObservationIgnored private var offer: SUAppcastItem?
    @ObservationIgnored private var installReply: ((SPUUserUpdateChoice) -> Void)?
    @ObservationIgnored private var checkCancellation: (() -> Void)?
    @ObservationIgnored private var expectedBytes: UInt64 = 0
    @ObservationIgnored private var receivedBytes: UInt64 = 0
    @ObservationIgnored private var coreStopped = false
    @ObservationIgnored private var downloadWasFresh = false
    @ObservationIgnored private var extractionStarted = false
    @ObservationIgnored private var observedTransactionID: String?
    @ObservationIgnored private var restartedTransactionID: String?
    @ObservationIgnored private var ignoredTransactionID: String?
    @ObservationIgnored private var environment = UpdateEnvironment()

    var isFrozen: Bool {
        if coreStopped { return true }
        guard let journal else { return false }
        return ![.complete, .cancelled, .rolledBack].contains(journal.phase)
    }
    var canCheck: Bool { started && updater != nil && !isFrozen && installReply == nil && updater?.sessionInProgress != true }
    var canInstall: Bool { installReply != nil && !isFrozen && !needsMigration }
    var canCancel: Bool { journal?.phase == .waitingIdle || journal?.phase == .quiescent }
    var canRequestOff: Bool { journal?.desiredEnabled == true && journal?.phase.terminal == false }
    var canRecover: Bool { journal?.phase == .appRecoveryRequired || journal?.phase == .recoveryRequired }
    var canApplyRuntime: Bool { pendingRuntime && !isFrozen && !needsMigration }

    var statusKey: String {
        if needsMigration { return "migration_detail" }
        guard let journal else { return status }
        if pendingRuntime, [.cancelled, .complete].contains(journal.phase) { return "pending" }
        switch journal.phase {
        case .preparingApp, .appPrepared: return "preparing"
        case .installingApp: return status == "downloading" ? "downloading" : "installing"
        case .awaitingGUI: return "installing"
        case .waitingIdle, .quiescent: return "waiting"
        case .stopCommitted, .candidateGated, .activationCommitted, .verifying, .rollingBack: return "applying"
        case .complete: return "complete"
        case .rolledBack: return "rollback"
        case .cancelled: return pendingRuntime ? "pending" : status
        case .recoveryRequired, .appRecoveryRequired: return "failed"
        }
    }

    static func text(_ key: String) -> String { Copy.text("shell_update_" + key, fallback: "") }

    func start(core: any CoreProtocol, store: CoreStore, environment: UpdateEnvironment = UpdateEnvironment()) async {
        guard !started else { return }
        started = true
        self.core = core; coreStore = store
        self.environment = environment
        do {
            let runtime = try await Task.detached { try RuntimeStore(root: environment.root) }.value
            runtimeStore = runtime
            journal = try await Task.detached { try runtime.current() }.value
            needsMigration = try await Task.detached { try runtime.active() == nil }.value
            if let pending = journal, [.preparingApp, .appPrepared].contains(pending.phase), !pending.installArmed {
                coreStopped = true
                await core.shutdown()
                do {
                    try await Task.detached { try UpdatePreparation.cancelUnarmed(store: runtime, transactionID: pending.transactionID) }.value
                } catch UpdateFailure.updateBusy {
                    _ = try await contact(AgentRequest("cancel", transactionID: pending.transactionID), store: runtime)
                }
                journal = try await Task.detached { try runtime.current() }.value
            }
            if let journal, !journal.phase.terminal {
                observedTransactionID = journal.transactionID
                try await Task.detached { try UpdatePreparation.startAgent(store: runtime, journal: journal, launch: environment.launch) }.value
                if [.appPrepared, .installingApp, .awaitingGUI].contains(journal.phase),
                   Bundle.main.object(forInfoDictionaryKey: "CFBundleVersion") as? String == journal.targetAppBuild {
                    let request = AgentRequest("gui-ready", transactionID: journal.transactionID, appPath: Bundle.main.bundlePath)
                    self.journal = try await contact(request, store: runtime)
                }
            }
            if (journal == nil || [.complete, .cancelled, .rolledBack].contains(journal!.phase)), !needsMigration,
               let settings = store.projection?.view.settings {
                let app = Bundle.main.bundleURL
                let changed = try await Task.detached {
                    try runtime.manifest(in: app).runtimeID != runtime.active()?.runtimeID
                }.value
                if changed {
                    let config = NSString(string: settings.proxy_config_path).expandingTildeInPath
                    do { try await beginExternalRuntime(configPath: config, enabled: settings.proxy_enabled, automatically: true) }
                    catch UpdateFailure.runtimeDeferred { pendingRuntime = true }
                }
            }
            configureSparkle()
            monitor = Task { [weak self] in
                while !Task.isCancelled {
                    await self?.refreshJournal()
                    try? await Task.sleep(for: .seconds(1))
                }
            }
        } catch {
            lastError = error as NSError
            status = "failed"
        }
    }

    private func configureSparkle() {
        guard let feed = Bundle.main.object(forInfoDictionaryKey: "SUFeedURL") as? String,
              URL(string: feed)?.scheme == "https",
              let key = Bundle.main.object(forInfoDictionaryKey: "SUPublicEDKey") as? String,
              Data(base64Encoded: key)?.count == 32 else { status = "unconfigured"; return }
        let updater = SPUUpdater(hostBundle: .main, applicationBundle: .main, userDriver: self, delegate: self)
        updater.automaticallyChecksForUpdates = false
        updater.automaticallyDownloadsUpdates = false
        do { try updater.start(); self.updater = updater; status = "ready" }
        catch { lastError = error as NSError; status = "check_failed" }
    }

    func check() {
        guard canCheck else { return }
        offeredVersion = nil
        lastError = nil
        ignoredTransactionID = journal?.transactionID
        journal = nil
        status = "checking"
        updater?.checkForUpdates()
    }

    func install() {
        guard canInstall, let offer, let reply = installReply, let runtimeStore, let core,
              let settings = coreStore?.projection?.view.settings else { return }
        installReply = nil
        status = "preparing"
        let targetID = offer.propertiesDictionary["codexmulti:runtimeID"] as? String
        guard let targetID, Disk.isDigest(targetID),
              offer.propertiesDictionary["codexmulti:updateProtocol"] as? String == "1",
              offer.signingValidationStatus == .succeeded, !offer.isInformationOnlyUpdate else { status = "failed"; reply(.skip); return }
        let app = Bundle.main.bundleURL
        let targetBuild = offer.versionString
        let configPath = NSString(string: settings.proxy_config_path).expandingTildeInPath
        let environment = environment
        Task {
            do {
                let prepared = try await Task.detached {
                    try UpdatePreparation.begin(store: runtimeStore, app: app,
                        targetBuild: targetBuild, targetRuntimeID: targetID,
                        configPath: configPath, desiredEnabled: settings.proxy_enabled, serviceLabel: environment.serviceLabel)
                }.value
                journal = prepared
                observedTransactionID = prepared.transactionID
                coreStopped = true
                await core.shutdown()
                let ready = try await Task.detached {
                    try UpdatePreparation.prepared(store: runtimeStore, transactionID: prepared.transactionID)
                }.value
                try await Task.detached { try UpdatePreparation.startAgent(store: runtimeStore, journal: ready, launch: environment.launch) }.value
                journal = try await contact(AgentRequest("arm", transactionID: ready.transactionID), store: runtimeStore)
                reply(.install)
            } catch {
                lastError = error as NSError
                status = "failed"
                reply(.skip)
                if let journal, !journal.installArmed {
                    try? await Task.detached {
                        try UpdatePreparation.cancelUnarmed(store: runtimeStore, transactionID: journal.transactionID)
                    }.value
                }
            }
        }
    }

    func migrateClientsClosed() {
        guard needsMigration, !isFrozen, let core, let runtimeStore,
              let settings = coreStore?.projection?.view.settings else { return }
        coreStopped = true
        status = "preparing"
        let app = Bundle.main.bundleURL
        let config = NSString(string: settings.proxy_config_path).expandingTildeInPath
        let environment = environment
        Task {
            await core.shutdown()
            do {
                let prepared = try await Task.detached {
                    try ServicePreparation.begin(store: runtimeStore, app: app, configPath: config,
                        enabled: settings.proxy_enabled, clientsClosed: true)
                }.value
                journal = prepared
                observedTransactionID = prepared.transactionID
                needsMigration = false
                try await Task.detached { try UpdatePreparation.startAgent(store: runtimeStore, journal: prepared, launch: environment.launch) }.value
            } catch {
                status = "failed"
                let current = try? await Task.detached { try runtimeStore.current() }.value
                if current == nil || current?.phase.terminal == true {
                    try? await core.start()
                    coreStopped = false
                }
            }
        }
    }

    func cancelPending() { command("cancel") }
    func requestOff() { command("off") }
    func applyRuntime() {
        guard canApplyRuntime, let settings = coreStore?.projection?.view.settings else { return }
        let config = NSString(string: settings.proxy_config_path).expandingTildeInPath
        Task {
            do { try await beginExternalRuntime(configPath: config, enabled: settings.proxy_enabled, automatically: false) }
            catch { status = "failed" }
        }
    }

    private func beginExternalRuntime(configPath: String, enabled: Bool, automatically: Bool) async throws {
        guard let runtimeStore, let core else { throw UpdateFailure.invalidTransaction }
        let app = Bundle.main.bundleURL
        let environment = environment
        let prepared = try await Task.detached {
            try UpdatePreparation.externalApp(store: runtimeStore, app: app, configPath: configPath,
                                               desiredEnabled: enabled, automatically: automatically,
                                               serviceLabel: environment.serviceLabel)
        }.value
        journal = prepared
        observedTransactionID = prepared.transactionID
        pendingRuntime = false
        coreStopped = true
        await core.shutdown()
        let ready = try await Task.detached {
            try UpdatePreparation.prepared(store: runtimeStore, transactionID: prepared.transactionID)
        }.value
        journal = ready
        try await Task.detached { try UpdatePreparation.startAgent(store: runtimeStore, journal: ready, launch: environment.launch) }.value
    }

    private func command(_ command: String) {
        guard let journal, let runtimeStore else { return }
        Task {
            do { self.journal = try await contact(AgentRequest(command, transactionID: journal.transactionID), store: runtimeStore) }
            catch { status = "failed" }
        }
    }

    func showRecovery() {
        guard let journal, let runtimeStore,
              let directory = try? runtimeStore.transactionDirectory(journal.transactionID) else { return }
        let app = directory.appendingPathComponent("previous-app/CodexMulti.app")
        NSWorkspace.shared.activateFileViewerSelecting([Disk.exists(app) ? app : directory])
    }

    private func contact(_ request: AgentRequest, store: RuntimeStore) async throws -> UpdateJournal {
        for attempt in 0..<20 {
            do { return try await Task.detached { try AgentConnection.send(request, store: store) }.value }
            catch {
                if attempt == 19 { throw error }
                try await Task.sleep(for: .milliseconds(250))
            }
        }
        throw UpdateFailure.proxyUnreachable
    }

    private func refreshJournal() async {
        guard let runtimeStore else { return }
        do {
            let current = try await Task.detached { try runtimeStore.current() }.value
            journal = current?.transactionID == ignoredTransactionID && current?.phase.terminal == true ? nil : current
            if let current, !current.phase.terminal { observedTransactionID = current.transactionID }
            if let current, [.complete, .cancelled, .rolledBack].contains(current.phase),
               (observedTransactionID == current.transactionID || coreStopped),
               restartedTransactionID != current.transactionID, let core {
                await core.shutdown()
                try await core.start()
                coreStopped = false
                restartedTransactionID = current.transactionID
                needsMigration = try await Task.detached { try runtimeStore.active() == nil }.value
                if [.cancelled, .rolledBack].contains(current.phase) {
                    let app = Bundle.main.bundleURL
                    pendingRuntime = try await Task.detached {
                        try runtimeStore.manifest(in: app).runtimeID != runtimeStore.active()?.runtimeID
                    }.value
                }
            }
        } catch { status = "failed" }
    }

    func show(_ request: SPUUpdatePermissionRequest,
                                     reply: @escaping (SUUpdatePermissionResponse) -> Void) {
        reply(SUUpdatePermissionResponse(automaticUpdateChecks: false, sendSystemProfile: false))
    }
    func showUserInitiatedUpdateCheck(cancellation: @escaping () -> Void) {
        status = "checking"; checkCancellation = cancellation
    }
    func showUpdateFound(with appcastItem: SUAppcastItem, state: SPUUserUpdateState,
                         reply: @escaping (SPUUserUpdateChoice) -> Void) {
        checkCancellation = nil
        guard !isFrozen, !needsMigration, state.stage != .installing else { reply(.skip); return }
        downloadWasFresh = state.stage == .notDownloaded
        extractionStarted = false
        offer = appcastItem
        offeredVersion = appcastItem.displayVersionString
        installReply = reply
        status = "available"
    }
    func showUpdateReleaseNotes(with downloadData: SPUDownloadData) {}
    func showUpdateReleaseNotesFailedToDownloadWithError(_ error: any Error) {}
    func showUpdateNotFoundWithError(_ error: any Error, acknowledgement: @escaping () -> Void) {
        let reason = ((error as NSError).userInfo[SPUNoUpdateFoundReasonKey] as? NSNumber)?.intValue ?? -1
        status = reason == Int(SPUNoUpdateFoundReason.onLatestVersion.rawValue)
            || reason == Int(SPUNoUpdateFoundReason.onNewerThanLatestVersion.rawValue) ? "current" : "no_compatible"
        checkCancellation = nil; acknowledgement()
    }
    func showUpdaterError(_ error: any Error, acknowledgement: @escaping () -> Void) {
        lastError = error as NSError
        status = journal?.installArmed == true ? "failed" : "check_failed"
        installReply = nil; acknowledgement()
    }
    func showDownloadInitiated(cancellation: @escaping () -> Void) {
        status = "downloading"; expectedBytes = 0; receivedBytes = 0; progress = nil
    }
    func showDownloadDidReceiveExpectedContentLength(_ expectedContentLength: UInt64) { expectedBytes = expectedContentLength }
    func showDownloadDidReceiveData(ofLength length: UInt64) {
        receivedBytes += length
        if expectedBytes > 0 { progress = min(1, Double(receivedBytes) / Double(expectedBytes)) }
    }
    func showDownloadDidStartExtractingUpdate() { extractionStarted = true; status = "installing"; progress = nil }
    func showExtractionReceivedProgress(_ progress: Double) { self.progress = progress }
    func showReady(toInstallAndRelaunch reply: @escaping (SPUUserUpdateChoice) -> Void) {
        guard coreStopped, journal?.installArmed == true else { status = "failed"; reply(.skip); return }
        reply(.install)
    }
    func showInstallingUpdate(withApplicationTerminated applicationTerminated: Bool, retryTerminatingApplication: @escaping () -> Void) {
        status = "installing"
    }
    func showUpdateInstalledAndRelaunched(_ relaunched: Bool, acknowledgement: @escaping () -> Void) { acknowledgement() }
    func updater(_ updater: SPUUpdater, didFinishUpdateCycleFor updateCheck: SPUUpdateCheck, error: (any Error)?) {
        guard error != nil, journal?.installArmed == true else { return }
        command(downloadWasFresh && !extractionStarted ? "download-aborted" : "installer-failed")
    }
    func dismissUpdateInstallation() { installReply = nil; checkCancellation = nil; progress = nil }
}
