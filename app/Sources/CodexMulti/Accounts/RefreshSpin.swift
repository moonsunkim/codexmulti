import SwiftUI













struct RefreshSpin: Equatable {


    struct ProxyRead: Equatable {
        let reachability: ProxyReachability
        let lastAttemptAt: Int64?
        let lastAttemptResult: ProxyAttemptResult?
        let lastSuccessAt: Int64?
        let successRevision: UInt64
        let pillText: String
    }


    struct Inputs: Equatable {
        let accountWork: Bool
        let proxyWork: ProxyWork
        let read: ProxyRead

        init(accountWork: Bool, proxyWork: ProxyWork, read: ProxyRead) {
            self.accountWork = accountWork
            self.proxyWork = proxyWork
            self.read = read
        }

        init(_ view: ViewState) {
            accountWork = view.busy_count > 0
            proxyWork = view.proxy_work
            read = ProxyRead(reachability: view.proxy_reachability, lastAttemptAt: view.proxy_last_attempt_at_unix_s,
                             lastAttemptResult: view.proxy_last_attempt_result, lastSuccessAt: view.proxy_last_success_at_unix_s,
                             successRevision: view.proxy_success_revision, pillText: view.proxy_pill_text)
        }
    }


    enum Transition: Equatable, CustomStringConvertible {
        case started(String)
        case stopped(String)

        var description: String {
            switch self {
            case .started(let reason): "turning: \(reason)"
            case .stopped(let reason): "still: \(reason)"
            }
        }
    }


    private struct ProxyCycle: Equatable {
        let kind: ProxyWork
        let readAtStart: ProxyRead
        var reported = false
    }

    private(set) var spinning = false
    private var cycle: ProxyCycle?


    mutating func observe(_ inputs: Inputs) -> Transition? {
        if inputs.proxyWork == .idle {
            cycle = nil
        } else if var current = cycle, current.kind == inputs.proxyWork {
            if !current.reported, inputs.read != current.readAtStart { current.reported = true }
            cycle = current
        } else {
            cycle = ProxyCycle(kind: inputs.proxyWork, readAtStart: inputs.read)
        }
        let proxyTurning = cycle.map { !$0.reported } ?? false
        let next = inputs.accountWork || proxyTurning
        guard next != spinning else { return nil }
        spinning = next
        if next {
            return .started(inputs.accountWork ? "busy_count>0" : "proxy_work=\(inputs.proxyWork.rawValue)")
        }
        if let cycle, cycle.reported {
            return .stopped("read reported while proxy_work=\(cycle.kind.rawValue)")
        }
        return .stopped("idle")
    }


    static func angle(at date: Date) -> Angle {
        .degrees((date.timeIntervalSinceReferenceDate * 360).truncatingRemainder(dividingBy: 360))
    }
}
