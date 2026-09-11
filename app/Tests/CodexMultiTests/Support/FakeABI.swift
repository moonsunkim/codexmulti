import Foundation
import os
@testable import CodexMulti


final class FakeABI: @unchecked Sendable {
    private let lock = OSAllocatedUnfairLock()
    private var _version: UInt32 = 1
    private var _bytes: Data
    private var _submitted: [Data] = []
    private var _pumps: [Int64] = []
    private var _creates = 0
    private var _destroys = 0
    private var _projects = 0
    private var _probes = 0
    private var _provenanceReads = 0
    private var _probeBytes = Data()
    private var _probeResult: Int32?
    private var _createSucceeds = true
    private var _calls: [String] = []

    init(bytes: Data) { _bytes = bytes }

    var version: UInt32 {
        get { lock.withLock { _version } }
        set { lock.withLock { _version = newValue } }
    }
    var bytes: Data {
        get { lock.withLock { _bytes } }
        set { lock.withLock { _bytes = newValue } }
    }
    var submitted: [Data] { lock.withLock { _submitted } }
    var pumps: [Int64] { lock.withLock { _pumps } }
    var creates: Int { lock.withLock { _creates } }
    var destroys: Int { lock.withLock { _destroys } }
    var projects: Int { lock.withLock { _projects } }
    var probes: Int { lock.withLock { _probes } }
    var provenanceReads: Int { lock.withLock { _provenanceReads } }
    var calls: [String] { lock.withLock { _calls } }
    var probeBytes: Data {
        get { lock.withLock { _probeBytes } }
        set { lock.withLock { _probeBytes = newValue } }
    }
    var probeResult: Int32? {
        get { lock.withLock { _probeResult } }
        set { lock.withLock { _probeResult = newValue } }
    }
    var createSucceeds: Bool {
        get { lock.withLock { _createSucceeds } }
        set { lock.withLock { _createSucceeds = newValue } }
    }

    var submittedIntentNames: [String] {
        submitted.compactMap { data in
            (try? JSONSerialization.jsonObject(with: data) as? [String: Any])?["intent"] as? String
        }
    }

    var abi: CoreABI {
        CoreABI(
            version: { [self] in version },
            provenance: { [self] in
                lock.withLock { _provenanceReads += 1 }
                return "CODEXMULTI_CORE_SRC_SHA256=" + String(repeating: "0", count: 64)
            },
            create: { [self] in
                let succeeds = lock.withLock {
                    _creates += 1
                    _calls.append("create")
                    return _createSucceeds
                }
                return succeeds ? CoreHandle(bitPattern: 0x10) : nil
            },
            destroy: { [self] _ in
                lock.withLock {
                    _destroys += 1
                    _calls.append("destroy")
                }
            },
            submit: { [self] _, json in
                lock.withLock { _submitted.append(json) }
                return 0
            },
            pump: { [self] _, now in lock.withLock { _pumps.append(now) } },
            project: { [self] _ in
                lock.withLock {
                    _projects += 1
                    return _bytes
                }
            },
            keychainProbe: { [self] _, out, capacity in
                let (result, bytes) = lock.withLock {
                    _probes += 1
                    _calls.append("probe")
                    let result = _probeResult ?? Int32(_probeBytes.count)
                    return (result, _probeBytes)
                }
                guard result >= 0 else { return result }
                guard Int(result) <= capacity, Int(result) <= bytes.count else { return -2 }
                bytes.copyBytes(to: UnsafeMutableRawBufferPointer(start: out, count: Int(result)))
                return result
            }
        )
    }
}


@MainActor
func waitUntil(timeout: Duration = .seconds(2), _ condition: @MainActor () -> Bool) async {
    let deadline = ContinuousClock.now + timeout
    while !condition() && ContinuousClock.now < deadline {
        try? await Task.sleep(for: .milliseconds(10))
    }
}


@MainActor
final class RecordingEffects {
    var showSettings = 0
    var quits = 0
    var clipboard: [String] = []
    var replies: [Intent] = []
    var clipboardResult = true

    let runner: EffectRunner

    init() {
        let runner = EffectRunner(showSettings: {}, quit: {}, writeClipboard: { _ in true }, reply: { _ in })
        self.runner = runner
        runner.showSettings = { [unowned self] in showSettings += 1 }
        runner.quit = { [unowned self] in quits += 1 }
        runner.writeClipboard = { [unowned self] text in
            clipboard.append(text)
            return clipboardResult
        }
        runner.reply = { [unowned self] intent in replies.append(intent) }
    }
}
