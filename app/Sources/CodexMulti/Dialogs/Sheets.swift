import SwiftUI






struct AddAccountSheet: View {
    let flow: AddAccountFlow
    let shell: ShellState
    @State private var draft: String
    @FocusState private var focus: DialogModel.ControlID?
    @Environment(\.tone) private var tone
    @Environment(\.submit) private var submit

    init(flow: AddAccountFlow, shell: ShellState) {
        self.flow = flow
        self.shell = shell
        _draft = State(initialValue: flow.initial_label)
    }

    var body: some View {
        let spec = DialogModel.spec(.addAccount, shell: shell, addAccountDraft: draft)
        DialogLayout(spec: spec, title: flow.title, focus: $focus) {
            DialogLine(verbatim: flow.explanation_text)
            TextField(Copy.accountLabel, text: $draft, prompt: Text(verbatim: Copy.accountLabel))
                .textFieldStyle(.plain)
                .font(Face.body)
                .foregroundStyle(tone.text)
                .padding(.horizontal, 10)
                .frame(height: DialogMetrics.buttonHeight)
                .background(RoundedRectangle(cornerRadius: DialogMetrics.fieldRadius, style: .continuous).fill(tone.pill))
                .focusEffectDisabled()
                .focused($focus, equals: .field)
                .disabled(flow.in_flight)
                .onSubmit {
                    if let intent = DialogModel.addAccountCommitIntent(flow, draft: draft) {
                        submit(intent)
                    }
                }
                .accessibilityLabel(Copy.accountLabel)
            if flow.in_flight {
                DialogLine(verbatim: flow.progress_text, muted: true)
            } else if !flow.error_text.isEmpty {
                DialogLine(verbatim: flow.error_text)
            }
        }
    }
}



struct FailoverSwitchSheet: View {
    let flow: FailoverSwitchFlow
    let shell: ShellState
    @FocusState private var focus: DialogModel.ControlID?

    var body: some View {
        let spec = DialogModel.spec(.failoverSwitch, shell: shell)
        DialogLayout(spec: spec, title: Copy.failoverSwitchTitlePrefix + flow.target_label + Copy.failoverSwitchTitleSuffix, focus: $focus) {
            DialogLine(.runs(Copy.failoverSwitchBodyPrefix, medium: flow.target_label, Copy.failoverSwitchBodySuffix))
            DialogLine(verbatim: Copy.failoverSwitchMuted, muted: true)
        }
    }
}



struct ClearCooldownSheet: View {
    let flow: ClearCooldownFlow
    let shell: ShellState
    @FocusState private var focus: DialogModel.ControlID?

    var body: some View {
        let spec = DialogModel.spec(.clearCooldown, shell: shell)
        DialogLayout(spec: spec, title: Copy.clearCooldownTitlePrefix + flow.label + Copy.clearCooldownTitleSuffix, focus: $focus) {
            DialogLine(verbatim: Copy.clearCooldownBody)
            DialogLine(verbatim: Copy.clearCooldownMuted, muted: true)
        }
    }
}




struct RenameSheet: View {
    let flow: RenameFlow
    let shell: ShellState
    @State private var draft: String
    @FocusState private var focus: DialogModel.ControlID?
    @Environment(\.tone) private var tone
    @Environment(\.submit) private var submit

    init(flow: RenameFlow, shell: ShellState) {
        self.flow = flow
        self.shell = shell
        _draft = State(initialValue: flow.initial_label)
    }

    var body: some View {
        let spec = DialogModel.spec(.rename, shell: shell, renameDraft: draft)
        DialogLayout(spec: spec, title: Copy.renameTitle, focus: $focus) {
            DialogLine(verbatim: Copy.renameMuted, muted: true)
            TextField(Copy.accountLabel, text: $draft, prompt: Text(verbatim: Copy.accountLabel))
                .textFieldStyle(.plain)
                .font(Face.body)
                .foregroundStyle(tone.text)
                .padding(.horizontal, 10)
                .frame(height: DialogMetrics.buttonHeight)
                .background(RoundedRectangle(cornerRadius: DialogMetrics.fieldRadius, style: .continuous).fill(tone.pill))
                .overlay(RoundedRectangle(cornerRadius: DialogMetrics.fieldRadius + 3, style: .continuous)
                    .strokeBorder(tone.point, lineWidth: focus == .field ? 2 : 0)
                    .padding(DialogMetrics.focusInset))
                .focusEffectDisabled()
                .focused($focus, equals: .field)
                .onSubmit { submit(.commit_rename(label: draft)) }
                .accessibilityLabel(Copy.accountLabel)
        }
    }
}




struct RemoveSheet: View {
    let flow: RemoveFlow
    let shell: ShellState
    @FocusState private var focus: DialogModel.ControlID?

    var body: some View {
        let spec = DialogModel.spec(.remove, shell: shell)
        DialogLayout(spec: spec, title: Copy.removeTitle, focus: $focus) {
            DialogLine(.runs("", medium: flow.label, Copy.removeBodySuffix))
            DialogLine(verbatim: DialogModel.removeMuted(flow), muted: true)
        }
    }
}






struct ResetSheet: View {
    let flow: ResetFlow
    let shell: ShellState
    @FocusState private var focus: DialogModel.ControlID?
    @Environment(\.tone) private var tone
    @Environment(\.submit) private var submit

    var body: some View {
        let spec = DialogModel.spec(.reset, shell: shell)
        DialogLayout(spec: spec, title: Copy.resetTitle, focus: $focus) {
            switch DialogModel.resetScreen(flow) {
            case .blocked:
                DialogLine(verbatim: flow.blocked_text)
                if flow.awaits_reconciliation {
                    DialogLine(verbatim: Copy.resetRetryMuted, muted: true)
                }
            case .dispatched:
                DialogLine(verbatim: flow.outcome_text)
                if let line = DialogModel.resetProxyClearLine(flow) {
                    DialogLine(verbatim: line, muted: true)
                }
            case .review:
                DialogLine(.runs(Copy.resetBodyPrefix, medium: flow.label, Copy.resetBodySuffix))
                DialogLine(verbatim: DialogModel.resetEvidenceLine(flow), muted: true)
                Toggle(isOn: Binding(get: { flow.is_armed }, set: { _ in submit(.acknowledge_reset) })) {
                    Text(verbatim: Copy.resetAcknowledge)
                        .font(Face.sheetBody)
                        .foregroundStyle(tone.text)
                }
                .toggleStyle(DialogCheckboxStyle(focused: focus == .checkbox))
                .focused($focus, equals: .checkbox)
                .accessibilityLabel(Copy.resetAcknowledge)
            }
        }
    }
}
