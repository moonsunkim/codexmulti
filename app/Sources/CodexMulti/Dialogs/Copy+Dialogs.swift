import Foundation










extension Copy {



    static let failoverSwitchTitlePrefix = "Route new requests to “"
    static let failoverSwitchTitleSuffix = "”?"

    static let failoverSwitchBodyPrefix = "This changes the proxy cursor to "
    static let failoverSwitchBodySuffix = " for new routed requests."

    static let failoverSwitchMuted = "This does not copy or install an auth file. Requests already in flight continue on their current account."

    static let useAccount = "Use Account"




    static let clearCooldownTitlePrefix = "Clear the cooldown for “"
    static let clearCooldownTitleSuffix = "”?"

    static let clearCooldownBody = "The proxy will use this account again immediately. Do this only if you reset its limit elsewhere."

    static let clearCooldownMuted = "If the limit is not actually reset, the next request may still be refused and the account is cooled down again from the provider's own answer. No request is sent to the provider now."

    static let clearCooldownConfirm = "Clear cooldown"




    static let renameTitle = "Rename account"

    static let renameMuted = "This changes only the label shown in CodexMulti."

    static let accountLabel = "Account label"





    static let removeTitle = "Remove account?"

    static let removeBodySuffix = " will be removed from CodexMulti."

    static let removeMappedMuted = "Remove and sync first pauses new proxy traffic. Use Refresh to observe Paused with no requests in flight; only then can CodexMulti remove the saved account and synchronize the proxy configuration."


    static let removePlainMuted = "Its saved usage snapshot is also removed. This does not delete the account at OpenAI."

    static let refreshDrainStatus = "Refresh drain status"

    static let finishRemoval = "Finish removal"

    static let removeAndSync = "Remove and sync"

    static let removeConfirm = "Remove"




    static let resetTitle = "Use one Codex reset?"

    static let resetRetryMuted = "Retrying checks the same request. It does not spend another reset."

    static let close = "Close"

    static let retrySameRequest = "Retry same request"

    static let resetBodyPrefix = "Spends one reset credit on "
    static let resetBodySuffix = ". If the account is cooling in the failover proxy, its cooldown is cleared once the reset settles."

    static let resetAvailableSuffix = " available · "
    static let resetNextResetInfix = " · next reset "

    static let resetAcknowledge = "I understand this cannot be undone"

    static let useOneReset = "Use one reset"



    static let cancel = "Cancel"
}
