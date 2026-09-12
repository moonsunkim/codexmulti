import AppKit
import Foundation
import os







@MainActor
final class AppDelegate: NSObject, NSApplicationDelegate {
    static let shutdownWatchdog: Duration = .seconds(10)

    nonisolated static let headlessStartupFailureStatus: Int32 = 3

    nonisolated static let captureFailureStatus: Int32 = 4

    let options: LaunchOptions
    let store: CoreStore
    let effects: EffectRunner
    let core: any CoreProtocol

    private let log = Logger(subsystem: "dev.codexmulti.app", category: "app")
    private var signalSources: [DispatchSourceSignal] = []
    private var terminationReplied = false
    private let lifecycle = LifecycleLog(url: LifecycleLog.url())

    override init() {
        let options = LaunchOptions(arguments: CommandLine.arguments)
        self.options = options
        if options.keychainProbe {
            exit(KeychainProbeLaunch.run())
        }
        if options.capturePath != nil && options.fixturePath == nil {
            FileHandle.standardError.write(Data(
                "CodexMulti: --capture requires --fixture; live account capture is refused\n".utf8))
            exit(2)
        }
        store = CoreStore()
        if options.capturePath == nil {
            store.tray.observeMenuTracking()
        }
        effects = options.capturePath == nil ? EffectRunner.forApp() : EffectRunner.forCapture()
        if let fixturePath = options.fixturePath {
            do {
                core = try FixtureCore(contentsOf: URL(fileURLWithPath: fixturePath), store: store, effects: effects)
            } catch {
                FileHandle.standardError.write(Data("CodexMulti: cannot read fixture \(fixturePath): \(error)\n".utf8))
                exit(2)
            }
        } else {
            core = CoreBridge(store: store, effects: effects)
        }
        super.init()
        WindowPresenter.shared.headless = options.headless
        let core = core
        if options.capturePath == nil &&
            (options.showWindow || options.visualQAShowSettings || options.setAppearanceOnLaunch != nil) {




            let showWindow = options.showWindow
            let noActivate = options.noActivate
            let showForVisualQA = options.visualQAShowSettings
            let appearance = options.setAppearanceOnLaunch
            store.onFirstPublish = {
                if showWindow {
                    WindowPresenter.shared.showSettings(
                        activation: noActivate ? .nonactivating : .userInitiated)
                } else if showForVisualQA {
                    WindowPresenter.shared.showSettings(activation: .nonactivating)
                }
                if let appearance { Task { await core.submit(Intent.set_appearance(value: appearance)) } }
            }
        }
        effects.reply = { intent in Task { await core.submit(intent) } }
    }

    func applicationWillFinishLaunching(_ notification: Notification) {
        NSApp.setActivationPolicy(.accessory)
        lifecycle?.launch()
        if options.capturePath == nil, let other = SingleInstanceGuard.otherInstance() {
            log.notice("another instance is running (pid \(other.processIdentifier, privacy: .public)); activating it and exiting")

            if !options.headless { other.activate() }
            lifecycle?.note(.duplicateInstance(pid: other.processIdentifier))
            lifecycle?.exit()
            exit(0)
        }
        if options.capturePath == nil {
            lifecycle?.installCrashHandlers()
            installSignalSources()
        }
        let core = core
        Task {
            do {
                try await core.start()
                log.notice("core started fixture=\(self.options.fixturePath != nil, privacy: .public)")
                if let capturePath = self.options.capturePath {
                    do {
                        let output = URL(fileURLWithPath: capturePath)
                        let result = try ScreenshotCapture.write(store: self.store, options: self.options, to: output)
                        FileHandle.standardOutput.write(Data(
                            "Captured \(output.path) (\(result.pixelsWide)x\(result.pixelsHigh), \(result.bytes) bytes)\n".utf8))
                        await core.shutdown()
                        self.lifecycle?.exit()
                        exit(0)
                    } catch {
                        FileHandle.standardError.write(Data(
                            "CodexMulti: cannot capture \(capturePath): \(error.localizedDescription)\n".utf8))
                        await core.shutdown()
                        self.lifecycle?.exit()
                        exit(Self.captureFailureStatus)
                    }
                }
            } catch {

                RunLoop.main.perform { MainActor.assumeIsolated { self.failStartup(error) } }
            }
        }
    }

    func applicationShouldTerminateAfterLastWindowClosed(_ sender: NSApplication) -> Bool {
        false
    }




    func applicationShouldTerminate(_ sender: NSApplication) -> NSApplication.TerminateReply {
        if lifecycle?.notedReason == nil {
            lifecycle?.note(.systemTerminate(sender: LifecycleLog.currentAppleEventSender()))
        }
        let core = core
        let watchdog = Task { @MainActor in
            try await Task.sleep(for: Self.shutdownWatchdog)
            self.replyToTermination(reason: "watchdog fired; core shutdown did not return in time")
        }
        Task {
            await core.shutdown()
            await MainActor.run {
                watchdog.cancel()
                self.replyToTermination(reason: "core drained")
            }
        }
        return .terminateLater
    }

    func applicationWillTerminate(_ notification: Notification) {
        lifecycle?.exit()
    }



    private func replyToTermination(reason: String) {
        guard !terminationReplied else { return }
        terminationReplied = true
        log.notice("terminating: \(reason, privacy: .public)")
        lifecycle?.reply(reason)
        NSApp.reply(toApplicationShouldTerminate: true)
    }




    private func installSignalSources() {
        for signalNumber in [SIGTERM, SIGINT] {
            signal(signalNumber, SIG_IGN)
            let source = DispatchSource.makeSignalSource(signal: signalNumber, queue: .main)
            source.setEventHandler { [lifecycle] in
                lifecycle?.note(.signal(signalNumber))
                MainActor.assumeIsolated { QuitRequest.post() }
            }
            source.resume()
            signalSources.append(source)
        }
    }


    private func failStartup(_ error: any Error) {
        let bridgeError = error as? CoreBridgeError
        store.startupFailure = bridgeError
        log.error("core failed to start: \(String(describing: error), privacy: .public)")
        lifecycle?.note(.startupFailure(String(describing: error)))
        if options.headless {



            lifecycle?.exit()
            exit(Self.headlessStartupFailureStatus)
        }
        let alert = NSAlert()
        alert.alertStyle = .critical
        alert.messageText = "CodexMulti cannot start"
        switch bridgeError {
        case .versionMismatch(let found, let expected):
            alert.informativeText = "Core bridge version \(found); this build requires \(expected)."
        case .createFailed:
            alert.informativeText = "The core could not be created."
        case .runtimeUnavailable(let reason):
            alert.informativeText = "CodexMulti could not load your saved accounts (\(reason?.rawValue ?? "unknown startup error")). Your account data has not been deleted."
        case .invalidInitialProjection:
            alert.informativeText = "CodexMulti could not read its startup status. Your account data has not been deleted."
        case .alreadyStarted, nil:
            alert.informativeText = String(describing: error)
        }
        NSApp.activate()
        alert.runModal()
        QuitRequest.post()
    }
}
