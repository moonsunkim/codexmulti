import Foundation




enum DialogKind: String, CaseIterable, Sendable, Identifiable {
    case addAccount, failoverSwitch, clearCooldown, rename, remove, reset
    var id: Self { self }
}





enum DialogModel {



    static func presented(_ shell: ShellState) -> DialogKind? {
        if shell.add_account.open { return .addAccount }
        if shell.failover_switch.open { return .failoverSwitch }
        if shell.clear_cooldown.open { return .clearCooldown }
        if shell.rename.open { return .rename }
        if shell.remove.open { return .remove }
        if shell.reset.open { return .reset }
        return nil
    }


    static func cancelIntent(_ kind: DialogKind) -> Intent {
        switch kind {
        case .addAccount: .cancel_add_account
        case .failoverSwitch: .cancel_failover_switch
        case .clearCooldown: .cancel_clear_cooldown
        case .rename: .cancel_rename
        case .remove: .cancel_remove
        case .reset: .cancel_reset
        }
    }


    static func width(_ kind: DialogKind) -> Double {
        switch kind {
        case .addAccount: 440
        case .failoverSwitch: 560
        case .clearCooldown: 520
        case .rename: 440
        case .remove: 460
        case .reset: 520
        }
    }






    enum ControlID: String, Hashable, Sendable, CaseIterable {
        case field, checkbox, cancel, refresh, finish, retry, confirm
    }

    enum ButtonStyle: Equatable, Sendable { case ghost, secondary, primary, destructive }



    struct Button: Equatable, Identifiable, Sendable {
        let id: ControlID
        let label: String
        let style: ButtonStyle
        let enabled: Bool
        let intent: Intent

        init(_ id: ControlID, _ label: String, _ style: ButtonStyle, enabled: Bool = true, intent: Intent) {
            self.id = id
            self.label = label
            self.style = style
            self.enabled = enabled
            self.intent = intent
        }
    }



    struct Spec: Equatable, Sendable {
        let kind: DialogKind
        let leading: [ControlID]
        let buttons: [Button]
        let initialFocus: ControlID
        let disabledLeading: Set<ControlID>

        init(kind: DialogKind, leading: [ControlID], buttons: [Button],
             initialFocus: ControlID, disabledLeading: Set<ControlID> = []) {
            self.kind = kind
            self.leading = leading
            self.buttons = buttons
            self.initialFocus = initialFocus
            self.disabledLeading = disabledLeading
        }

        var order: [ControlID] { leading + buttons.map(\.id) }

        func button(_ id: ControlID) -> Button? { buttons.first { $0.id == id } }

        func isEnabled(_ id: ControlID) -> Bool {
            if leading.contains(id) { return !disabledLeading.contains(id) }
            return button(id)?.enabled ?? false
        }
    }



    static func spec(_ kind: DialogKind, shell: ShellState, renameDraft: String = "",
                     addAccountDraft: String = "") -> Spec {
        switch kind {
        case .addAccount:
            let flow = shell.add_account
            return Spec(kind: kind, leading: [.field], buttons: [
                Button(.cancel, flow.cancel_label, .ghost, enabled: !flow.in_flight,
                       intent: .cancel_add_account),
                Button(.confirm, flow.confirm_label, .primary, enabled: flow.confirm_enabled,
                       intent: .commit_add_account(label: trimmedLabel(addAccountDraft))),
            ], initialFocus: .field, disabledLeading: flow.in_flight ? [.field] : [])
        case .failoverSwitch:
            return Spec(kind: kind, leading: [], buttons: [
                Button(.cancel, Copy.cancel, .ghost, intent: .cancel_failover_switch),
                Button(.confirm, Copy.useAccount, .primary, intent: .confirm_failover_switch),
            ], initialFocus: .cancel)
        case .clearCooldown:
            return Spec(kind: kind, leading: [], buttons: [
                Button(.cancel, Copy.cancel, .ghost, intent: .cancel_clear_cooldown),
                Button(.confirm, Copy.clearCooldownConfirm, .primary, intent: .confirm_clear_cooldown),
            ], initialFocus: .cancel)
        case .rename:
            return Spec(kind: kind, leading: [.field], buttons: [
                Button(.cancel, Copy.cancel, .ghost, intent: .cancel_rename),
                Button(.confirm, Copy.save, .primary, intent: .commit_rename(label: renameDraft)),
            ], initialFocus: .field)
        case .remove:
            return Spec(kind: kind, leading: [], buttons: removeButtons(shell.remove, proxyCanRefresh: shell.proxy_can_refresh),
                        initialFocus: .cancel)
        case .reset:
            let reset = shell.reset
            switch resetScreen(reset) {
            case .blocked:
                var buttons = [Button(.cancel, Copy.close, .ghost, intent: .cancel_reset)]
                if reset.awaits_reconciliation {
                    buttons.append(Button(.retry, Copy.retrySameRequest, .primary, intent: .retry_reset))
                }
                return Spec(kind: kind, leading: [], buttons: buttons, initialFocus: .cancel)
            case .dispatched:
                return Spec(kind: kind, leading: [], buttons: [Button(.cancel, Copy.close, .primary, intent: .cancel_reset)],
                            initialFocus: .cancel)
            case .review:
                return Spec(kind: kind, leading: [.checkbox], buttons: [
                    Button(.cancel, Copy.cancel, .ghost, intent: .cancel_reset),
                    Button(.confirm, Copy.useOneReset, .primary, enabled: reset.is_armed, intent: .confirm_reset),
                ], initialFocus: .cancel)
            }
        }
    }



    static func trimmedLabel(_ draft: String) -> String {
        draft.trimmingCharacters(in: .whitespacesAndNewlines)
    }

    static func addAccountCommitIntent(_ flow: AddAccountFlow, draft: String) -> Intent? {
        let label = trimmedLabel(draft)
        guard flow.open, !flow.in_flight, !label.isEmpty else { return nil }
        return .commit_add_account(label: label)
    }






    static func removeButtons(_ remove: RemoveFlow, proxyCanRefresh: Bool) -> [Button] {
        var buttons = [Button(.cancel, Copy.cancel, .ghost, intent: .cancel_remove)]
        if !remove.uses_proxy || !remove.pause_requested {
            buttons.append(Button(.confirm, Copy.removeConfirm, .destructive, intent: .confirm_remove))
        }
        return buttons
    }


    static func removeMuted(_ remove: RemoveFlow) -> String {
        remove.uses_proxy ? Copy.removeMappedMuted : Copy.removePlainMuted
    }





    enum ResetScreen: Equatable, Sendable { case blocked, dispatched, review }

    static func resetScreen(_ reset: ResetFlow) -> ResetScreen {
        if reset.is_blocked { return .blocked }
        if reset.is_dispatched { return .dispatched }
        return .review
    }


    static func resetConfirmIntent(_ reset: ResetFlow) -> Intent? {
        reset.is_armed ? .confirm_reset : nil
    }


    static func resetRetryIntent(_ reset: ResetFlow) -> Intent? {
        reset.awaits_reconciliation ? .retry_reset : nil
    }


    static func resetEvidenceLine(_ reset: ResetFlow) -> String {
        "\(reset.available_count)\(Copy.resetAvailableSuffix)\(reset.usage_text)\(Copy.resetNextResetInfix)\(reset.reset_text)"
    }


    static func resetProxyClearLine(_ reset: ResetFlow) -> String? {
        reset.shows_proxy_clear ? reset.proxy_clear_text : nil
    }








    struct FocusModel: Equatable, Sendable {
        let spec: Spec
        private(set) var focused: ControlID?

        init(_ spec: Spec) {
            self.spec = spec
            focused = spec.isEnabled(spec.initialFocus)
                ? spec.initialFocus
                : spec.order.first(where: spec.isEnabled)
        }

        var cycle: [ControlID] { spec.order.filter(spec.isEnabled) }

        mutating func tab() { move(1) }
        mutating func shiftTab() { move(-1) }

        private mutating func move(_ delta: Int) {
            let ids = cycle
            guard !ids.isEmpty else { focused = nil; return }
            guard let current = focused, let index = ids.firstIndex(of: current) else {
                focused = delta > 0 ? ids.first : ids.last
                return
            }
            focused = ids[(index + delta + ids.count) % ids.count]
        }


        func escape() -> Intent {
            DialogModel.cancelIntent(spec.kind)
        }


        func returnKey(renameDraft: String = "", addAccountDraft: String = "") -> Intent? {
            guard focused == .field, spec.isEnabled(.field) else { return nil }
            switch spec.kind {
            case .rename: return .commit_rename(label: renameDraft)
            case .addAccount:
                let label = trimmedLabel(addAccountDraft)
                return label.isEmpty ? nil : .commit_add_account(label: label)
            default: return nil
            }
        }


        func space() -> Intent? {
            guard let focused, spec.isEnabled(focused) else { return nil }
            switch focused {
            case .checkbox: return .acknowledge_reset
            case .field: return nil
            default: return spec.button(focused)?.intent
            }
        }
    }
}



enum DialogTarget: Equatable, Sendable {
    enum RemoveState: String, Sendable, CaseIterable { case plain, mapped, mappedPaused = "mapped-paused" }
    enum ResetState: String, Sendable, CaseIterable { case review, armed, dispatched, blocked, blockedRetry = "blocked-retry" }

    case failoverSwitch
    case clearCooldown
    case rename
    case remove(RemoveState)
    case reset(ResetState)


    init?(flag text: String) {
        switch text {
        case "failover-switch": self = .failoverSwitch
        case "clear-cooldown": self = .clearCooldown
        case "rename": self = .rename
        default:
            if text.hasPrefix("remove:"), let state = RemoveState(rawValue: String(text.dropFirst("remove:".count))) {
                self = .remove(state)
            } else if text.hasPrefix("reset:"), let state = ResetState(rawValue: String(text.dropFirst("reset:".count))) {
                self = .reset(state)
            } else {
                return nil
            }
        }
    }

    var flag: String {
        switch self {
        case .failoverSwitch: "failover-switch"
        case .clearCooldown: "clear-cooldown"
        case .rename: "rename"
        case .remove(let state): "remove:\(state.rawValue)"
        case .reset(let state): "reset:\(state.rawValue)"
        }
    }

    var kind: DialogKind {
        switch self {
        case .failoverSwitch: .failoverSwitch
        case .clearCooldown: .clearCooldown
        case .rename: .rename
        case .remove: .remove
        case .reset: .reset
        }
    }


    func matches(_ shell: ShellState) -> Bool {
        guard DialogModel.presented(shell) == kind else { return false }
        switch self {
        case .failoverSwitch, .clearCooldown, .rename:
            return true
        case .remove(let state):
            let remove = shell.remove
            switch state {
            case .plain: return !remove.uses_proxy
            case .mapped: return remove.uses_proxy && !remove.pause_requested
            case .mappedPaused: return remove.uses_proxy && remove.pause_requested
            }
        case .reset(let state):
            let reset = shell.reset
            switch state {
            case .review: return DialogModel.resetScreen(reset) == .review && !reset.is_armed
            case .armed: return DialogModel.resetScreen(reset) == .review && reset.is_armed
            case .dispatched: return DialogModel.resetScreen(reset) == .dispatched
            case .blocked: return DialogModel.resetScreen(reset) == .blocked && !reset.awaits_reconciliation
            case .blockedRetry: return DialogModel.resetScreen(reset) == .blocked && reset.awaits_reconciliation
            }
        }
    }
}
