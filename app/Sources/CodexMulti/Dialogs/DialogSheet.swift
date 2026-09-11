import AppKit
import SwiftUI






struct DialogHost: ViewModifier {
    let store: CoreStore
    @Environment(\.submit) private var submit
    @Environment(\.autoOpen) private var autoOpen
    @Environment(\.tone) private var tone
    @State private var settled = false
    @State private var reported = false

    private var target: DialogTarget? {
        if case .dialog(let target) = autoOpen { return target }
        return nil
    }

    private var presented: Binding<DialogKind?> {
        Binding(
            get: {
                guard let shell = store.projection?.shell, let kind = DialogModel.presented(shell) else { return nil }
                if target != nil, !settled { return nil }
                return kind
            },
            set: { next in
                guard next == nil, let shell = store.projection?.shell, let kind = DialogModel.presented(shell) else { return }
                if kind == .addAccount, shell.add_account.in_flight { return }
                submit(DialogModel.cancelIntent(kind))
            })
    }

    func body(content: Content) -> some View {
        content
            .sheet(item: presented) { kind in
                if let projection = store.projection {
                    DialogSheet(kind: kind, shell: projection.shell)
                        .environment(\.tone, tone)
                        .environment(\.submit, submit)
                        .interactiveDismissDisabled(kind == .addAccount && projection.shell.add_account.in_flight)
                }
            }
            .task(id: target) {
                guard target != nil else { return }
                try? await Task.sleep(for: AutoOpen.settle)
                settled = true
            }
            .onChange(of: store.projection?.generation, initial: true) { _, _ in
                guard let target, !reported, let shell = store.projection?.shell else { return }
                reported = true
                if !target.matches(shell) {
                    let open = DialogModel.presented(shell)?.rawValue ?? "no dialog"
                    FileHandle.standardError.write(Data("CodexMulti: --open=\(target.flag) but the projection holds \(open) open\n".utf8))
                }
            }
    }
}

extension View {
    func dialogs(store: CoreStore) -> some View {
        modifier(DialogHost(store: store))
    }
}


struct DialogSheet: View {
    let kind: DialogKind
    let shell: ShellState

    var body: some View {
        switch kind {
        case .addAccount: AddAccountSheet(flow: shell.add_account, shell: shell)
        case .failoverSwitch: FailoverSwitchSheet(flow: shell.failover_switch, shell: shell)
        case .clearCooldown: ClearCooldownSheet(flow: shell.clear_cooldown, shell: shell)
        case .rename: RenameSheet(flow: shell.rename, shell: shell)
        case .remove: RemoveSheet(flow: shell.remove, shell: shell)
        case .reset: ResetSheet(flow: shell.reset, shell: shell)
        }
    }
}




struct DialogChrome: ViewModifier {
    let kind: DialogKind
    let accessibilityTitle: String
    @Environment(\.tone) private var tone
    @Environment(\.accessibilityReduceTransparency) private var reduceTransparency

    func body(content: Content) -> some View {
        content
            .padding(DialogMetrics.padding)
            .frame(width: DialogModel.width(kind))
            .presentationBackground {
                if reduceTransparency {
                    tone.opaqueFloat
                } else {
                    ZStack {
                        Rectangle().fill(.regularMaterial)
                        tone.tint
                    }
                }
            }
            .presentationCornerRadius(DialogMetrics.radius)
            .accessibilityElement(children: .contain)
            .accessibilityLabel(accessibilityTitle)
    }
}

enum DialogMetrics {
    static let padding: CGFloat = 20
    static let bodyGap: CGFloat = 12
    static let buttonGap: CGFloat = 8
    static let radius: CGFloat = 20
    static let fieldRadius: CGFloat = 8
    static let buttonHeight: CGFloat = 28
    static let buttonPadding: CGFloat = 14
    static let focusInset: CGFloat = -3
    static let checkbox: CGFloat = 14
    static let checkboxRadius: CGFloat = 3.5
    static let checkboxGap: CGFloat = 8
}




struct DialogLayout<Lines: View>: View {
    let spec: DialogModel.Spec
    let title: String
    var focus: FocusState<DialogModel.ControlID?>.Binding
    @ViewBuilder let lines: () -> Lines
    @Environment(\.tone) private var tone

    var body: some View {
        VStack(alignment: .leading, spacing: DialogMetrics.bodyGap) {
            Text(verbatim: title)
                .font(Face.sheetTitle)
                .foregroundStyle(tone.text)
                .fixedSize(horizontal: false, vertical: true)
            lines()
            DialogButtonRow(buttons: spec.buttons, focus: focus)
        }
        .frame(maxWidth: .infinity, alignment: .leading)
        .modifier(DialogChrome(kind: spec.kind, accessibilityTitle: title))
        .defaultFocus(focus, spec.initialFocus)
    }
}

extension Text {


    static func runs(_ prefix: String, medium value: String, _ suffix: String) -> Text {
        Text("\(Text(verbatim: prefix))\(Text(verbatim: value).fontWeight(.medium))\(Text(verbatim: suffix))")
    }
}


struct DialogLine: View {
    let text: Text
    var muted = false
    @Environment(\.tone) private var tone

    init(_ text: Text, muted: Bool = false) {
        self.text = text
        self.muted = muted
    }

    init(verbatim string: String, muted: Bool = false) {
        self.init(Text(verbatim: string), muted: muted)
    }

    var body: some View {
        text
            .font(Face.sheetBody)
            .foregroundStyle(muted ? tone.text3 : tone.text)
            .fixedSize(horizontal: false, vertical: true)
            .frame(maxWidth: .infinity, alignment: .leading)
    }
}



struct DialogButtonRow: View {
    let buttons: [DialogModel.Button]
    var focus: FocusState<DialogModel.ControlID?>.Binding
    @Environment(\.submit) private var submit

    var body: some View {
        HStack(spacing: DialogMetrics.buttonGap) {
            Spacer(minLength: 0)
            ForEach(buttons) { button in
                DialogButton(button: button, focused: focus.wrappedValue == button.id) { submit(button.intent) }
                    .focused(focus, equals: button.id)
                    .cancelShortcut(button.id == .cancel)
            }
        }
    }
}

private extension View {
    @ViewBuilder func cancelShortcut(_ isCancel: Bool) -> some View {
        if isCancel { keyboardShortcut(.cancelAction) } else { self }
    }
}





struct DialogButton: View {
    let button: DialogModel.Button
    let focused: Bool
    let action: () -> Void
    @Environment(\.tone) private var tone
    @State private var hovering = false

    var body: some View {
        Button(action: action) {
            Text(verbatim: button.label)
                .font(Face.bandStrong)
                .foregroundStyle(ink)
                .padding(.horizontal, DialogMetrics.buttonPadding)
                .frame(height: DialogMetrics.buttonHeight)
                .background(Capsule().fill(fill))
                .contentShape(Capsule())
                .opacity(button.enabled ? 1 : Tone.disabledOpacity)
        }
        .buttonStyle(.plain)
        .disabled(!button.enabled)
        .focusEffectDisabled()
        .overlay(Capsule().strokeBorder(tone.point, lineWidth: focused ? 2 : 0).padding(DialogMetrics.focusInset))
        .onHover { hovering = $0 }
        .accessibilityLabel(button.label)
    }

    private var ink: Color {
        switch button.style {
        case .ghost: tone.text2
        case .secondary: tone.text
        case .primary: tone.onFill
        case .destructive: tone.destructive
        }
    }

    private var fill: Color {
        switch button.style {
        case .ghost: hovering && button.enabled ? tone.hover : .clear
        case .secondary, .destructive: hovering && button.enabled ? tone.pillHover : tone.pill
        case .primary: tone.fill
        }
    }
}









struct DialogCheckboxStyle: ToggleStyle {
    let focused: Bool
    @Environment(\.tone) private var tone

    func makeBody(configuration: Configuration) -> some View {
        Button { configuration.isOn.toggle() } label: {
            HStack(spacing: DialogMetrics.checkboxGap) {
                RoundedRectangle(cornerRadius: DialogMetrics.checkboxRadius, style: .continuous)
                    .fill(configuration.isOn ? tone.controlOn : tone.pill)
                    .frame(width: DialogMetrics.checkbox, height: DialogMetrics.checkbox)
                    .overlay {
                        if configuration.isOn {
                            Image(systemName: "checkmark")
                                .font(.system(size: 9, weight: .bold))
                                .foregroundStyle(tone.onFill)
                        }
                    }
                configuration.label
            }
            .contentShape(Rectangle())
        }
        .buttonStyle(.plain)
        .focusEffectDisabled()
        .overlay(RoundedRectangle(cornerRadius: DialogMetrics.fieldRadius, style: .continuous)
            .strokeBorder(tone.point, lineWidth: focused ? 2 : 0)
            .padding(DialogMetrics.focusInset))
    }
}
