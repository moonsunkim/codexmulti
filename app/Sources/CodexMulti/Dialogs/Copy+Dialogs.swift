import Foundation

extension Copy {

    static var failoverSwitchTitlePrefix: String { text("shell_failover_switch_title_prefix", fallback: "Route new requests to “") }
    static var failoverSwitchTitleSuffix: String { text("shell_failover_switch_title_suffix", fallback: "”?") }

    static var failoverSwitchBodyPrefix: String { text("shell_failover_switch_body_prefix", fallback: "This changes the proxy cursor to ") }
    static var failoverSwitchBodySuffix: String { text("shell_failover_switch_body_suffix", fallback: " for new routed requests.") }

    static var failoverSwitchMuted: String { text("shell_failover_switch_muted", fallback: "This does not copy or install an auth file. Requests already in flight continue on their current account.") }

    static var useAccount: String { text("shell_use_account", fallback: "Use Account") }

    static var clearCooldownTitlePrefix: String { text("shell_clear_cooldown_title_prefix", fallback: "Clear the cooldown for “") }
    static var clearCooldownTitleSuffix: String { text("shell_clear_cooldown_title_suffix", fallback: "”?") }

    static var clearCooldownBody: String { text("shell_clear_cooldown_body", fallback: "The proxy will use this account again immediately. Do this only if you reset its limit elsewhere.") }

    static var clearCooldownMuted: String { text("shell_clear_cooldown_muted", fallback: "If the limit is not actually reset, the next request may still be refused and the account is cooled down again from the provider's own answer. No request is sent to the provider now.") }

    static var clearCooldownConfirm: String { text("shell_clear_cooldown_confirm", fallback: "Clear cooldown") }

    static var renameTitle: String { text("shell_rename_title", fallback: "Rename account") }

    static var renameMuted: String { text("shell_rename_muted", fallback: "This changes only the label shown in CodexMulti.") }

    static var accountLabel: String { text("shell_account_label", fallback: "Account label") }

    static var removeTitle: String { text("shell_remove_title", fallback: "Remove account?") }

    static var removeBodySuffix: String { text("shell_remove_body_suffix", fallback: " will be removed from CodexMulti.") }

    static var removeMappedMuted: String { text("shell_remove_mapped_muted", fallback: "Remove and sync first pauses new proxy traffic. Use Refresh to observe Paused with no requests in flight; only then can CodexMulti remove the saved account and synchronize the proxy configuration.") }

    static var removePlainMuted: String { text("shell_remove_plain_muted", fallback: "Its saved usage snapshot is also removed. This does not delete the account at OpenAI.") }

    static var refreshDrainStatus: String { text("shell_refresh_drain_status", fallback: "Refresh drain status") }

    static var finishRemoval: String { text("shell_finish_removal", fallback: "Finish removal") }

    static var removeAndSync: String { text("shell_remove_and_sync", fallback: "Remove and sync") }

    static var removeConfirm: String { text("shell_remove_confirm", fallback: "Remove") }

    static var resetTitle: String { text("shell_reset_title", fallback: "Use one Codex reset?") }

    static var resetRetryMuted: String { text("shell_reset_retry_muted", fallback: "Retrying checks the same request. It does not spend another reset.") }

    static var close: String { text("shell_close", fallback: "Close") }

    static var retrySameRequest: String { text("shell_retry_same_request", fallback: "Retry same request") }

    static var resetBodyPrefix: String { text("shell_reset_body_prefix", fallback: "Spends one reset credit on ") }
    static var resetBodySuffix: String { text("shell_reset_body_suffix", fallback: ". If the account is cooling in the failover proxy, its cooldown is cleared once the reset settles.") }

    static var resetAvailableSuffix: String { text("shell_reset_available_suffix", fallback: " available · ") }
    static var resetNextResetInfix: String { text("shell_reset_next_reset_infix", fallback: " · next reset ") }

    static var resetAcknowledge: String { text("shell_reset_acknowledge", fallback: "I understand this cannot be undone") }

    static var useOneReset: String { text("shell_use_one_reset", fallback: "Use one reset") }

    static var cancel: String { text("shell_cancel", fallback: "Cancel") }
}
