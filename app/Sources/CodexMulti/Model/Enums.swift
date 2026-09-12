import Foundation







enum SettingsTab: String, Codable, Sendable, Equatable, CaseIterable { case accounts, failover }


enum Appearance: String, Codable, Sendable, Equatable, CaseIterable { case system, light, dark }


enum CodexUsageWindow: String, Codable, Sendable, Equatable, CaseIterable { case auto, weekly, session }


enum Language: String, Codable, Sendable, Equatable, CaseIterable { case system }


enum AutoUpdateState: String, Codable, Sendable, Equatable, CaseIterable { case unavailable }


enum UnifiedOrderSource: String, Codable, Sendable, Equatable, CaseIterable { case registry }


enum UnifiedFailoverState: String, Codable, Sendable, Equatable, CaseIterable {
    case not_mapped, active, ready, cooldown, paused, invalid, refreshing, unknown




    var renderedBadgeText: String {
        let words = rawValue.replacingOccurrences(of: "_", with: " ")
        return words.prefix(1).uppercased() + words.dropFirst()
    }
}


enum ClaudeTrayWindow: String, Codable, Sendable, Equatable, CaseIterable { case weekly, session }


enum NoticeKind: String, Codable, Sendable, Equatable, CaseIterable { case none, pending, blocked, info }


enum ResetStage: String, Codable, Sendable, Equatable, CaseIterable { case idle, review, armed, dispatched, blocked }


enum ResetBlockReason: String, Codable, Sendable, Equatable, CaseIterable {
    case none, not_codex, no_credit, pending_attempt, unsent_attempt, not_connected, disabled, unknown_account, service_unavailable
}


enum CommandOutcome: String, Codable, Sendable, Equatable, CaseIterable {
    case none, accepted_pending, service_unavailable, provider_cli_missing, offer_unavailable
    case rejected_busy, rejected_not_allowed, rejected_unknown_account, failed
}


enum SettleWatch: String, Codable, Sendable, Equatable, CaseIterable { case none, waiting, seen, settled, settled_unsent }


enum ResetProxyClear: String, Codable, Sendable, Equatable, CaseIterable {
    case none, pending, cleared, not_mapped, unreachable, busy, failed
}


enum RuntimeStartError: String, Codable, Sendable, Equatable, CaseIterable {
    case missing_home, invalid_root, directory_unavailable, keychain_unavailable, out_of_memory
}


enum Provider: String, Codable, Sendable, Equatable, CaseIterable { case codex, claude }


enum AuthState: String, Codable, Sendable, Equatable, CaseIterable { case connected, reauth_required, unavailable }


enum Freshness: String, Codable, Sendable, Equatable, CaseIterable {
    case never_refreshed, as_of, saved_snapshot, refresh_failed, reauth_required, usage_unavailable, refresh_deferred, reset_passed
}


enum SnapshotStatus: String, Codable, Sendable, Equatable, CaseIterable {
    case fresh, stale, partial, reauth_required, error_state, unavailable, deferred
}


enum CreditDetailStatus: String, Codable, Sendable, Equatable, CaseIterable { case count_only, detailed }


enum ProxyReachability: String, Codable, Sendable, Equatable, CaseIterable { case unknown, reachable, unreachable, incompatible }


enum ProxyAccountState: String, Codable, Sendable, Equatable, CaseIterable { case ready, cooldown, paused, invalid, refreshing, unknown }


enum ProxyWork: String, Codable, Sendable, Equatable, CaseIterable {
    case idle, checking, switching, pausing, reloading, clearing_cooldown, importing, applying_config
}


enum ProxySyncState: String, Codable, Sendable, Equatable, CaseIterable { case unknown, needed, synced, failed }


enum ProxyAttemptResult: String, Codable, Sendable, Equatable, CaseIterable {
    case ok, unreachable, timeout, protocol_error, incompatible, action_failed, import_failed
    case mapping_failed, config_mismatch, persist_failed, import_node_missing
}


enum ProxyServiceState: String, Codable, Sendable, Equatable, CaseIterable {
    case not_installed, installed_stale, starting, running, unreachable
}


enum CodexRoutingState: String, Codable, Sendable, Equatable, CaseIterable { case off, on, conflicting }


enum OnboardingStepKind: String, Codable, Sendable, Equatable, CaseIterable {
    case add_account, install_proxy_service, enable_codex_routing
}


enum UsageWindowKind: String, Codable, Sendable, Equatable, CaseIterable { case session, weekly, model_scoped, other }


enum CreditOffer: String, Codable, Sendable, Equatable, CaseIterable { case none, use_one, review }


enum EffectKind: String, Codable, Sendable, Equatable, CaseIterable { case show_settings, quit, clipboard }


enum ProjectionEnums {
    static let registry: [(zigName: String, cases: [String])] = [
        ("SettingsTab", SettingsTab.allCases.map(\.rawValue)),
        ("Appearance", Appearance.allCases.map(\.rawValue)),
        ("CodexUsageWindow", CodexUsageWindow.allCases.map(\.rawValue)),
        ("Language", Language.allCases.map(\.rawValue)),
        ("AutoUpdateState", AutoUpdateState.allCases.map(\.rawValue)),
        ("UnifiedOrderSource", UnifiedOrderSource.allCases.map(\.rawValue)),
        ("UnifiedFailoverState", UnifiedFailoverState.allCases.map(\.rawValue)),
        ("ClaudeTrayWindow", ClaudeTrayWindow.allCases.map(\.rawValue)),
        ("NoticeKind", NoticeKind.allCases.map(\.rawValue)),
        ("ResetStage", ResetStage.allCases.map(\.rawValue)),
        ("ResetBlockReason", ResetBlockReason.allCases.map(\.rawValue)),
        ("CommandOutcome", CommandOutcome.allCases.map(\.rawValue)),
        ("SettleWatch", SettleWatch.allCases.map(\.rawValue)),
        ("ResetProxyClear", ResetProxyClear.allCases.map(\.rawValue)),
        ("RuntimeError", RuntimeStartError.allCases.map(\.rawValue)),
        ("Provider", Provider.allCases.map(\.rawValue)),
        ("AuthState", AuthState.allCases.map(\.rawValue)),
        ("Freshness", Freshness.allCases.map(\.rawValue)),
        ("SnapshotStatus", SnapshotStatus.allCases.map(\.rawValue)),
        ("CreditDetailStatus", CreditDetailStatus.allCases.map(\.rawValue)),
        ("ProxyReachability", ProxyReachability.allCases.map(\.rawValue)),
        ("ProxyAccountState", ProxyAccountState.allCases.map(\.rawValue)),
        ("ProxyWork", ProxyWork.allCases.map(\.rawValue)),
        ("ProxySyncState", ProxySyncState.allCases.map(\.rawValue)),
        ("ProxyAttemptResult", ProxyAttemptResult.allCases.map(\.rawValue)),
        ("ProxyServiceState", ProxyServiceState.allCases.map(\.rawValue)),
        ("CodexRoutingState", CodexRoutingState.allCases.map(\.rawValue)),
        ("OnboardingStepKind", OnboardingStepKind.allCases.map(\.rawValue)),
        ("UsageWindowKind", UsageWindowKind.allCases.map(\.rawValue)),
        ("CreditOffer", CreditOffer.allCases.map(\.rawValue)),
        ("EffectKind", EffectKind.allCases.map(\.rawValue)),
    ]
}
