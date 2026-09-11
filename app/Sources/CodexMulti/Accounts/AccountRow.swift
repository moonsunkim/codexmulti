import SwiftUI







struct AccountRow: View {
    let row: AccountRowView
    let shell: ShellState

    let enabled: Bool

    let panel: ([UsageRow], Inspector)?
    @Environment(\.tone) private var tone
    @Environment(\.submit) private var submit
    @Environment(\.accessibilityReduceMotion) private var reduceMotion
    @Environment(\.keyboardFocus) private var keyboardFocus
    @Environment(\.appearsActive) private var appearsActive
    @State private var hovering = false
    @FocusState private var focused: Bool

    private var expanded: Bool { panel != nil }
    private var surface: AccountsModel.RowSurface { AccountsModel.rowSurface(expanded: expanded, hovering: hovering) }
    private var radius: CGFloat { expanded ? Grid.panelRadius : Grid.hoverRadius }
    private var ringShown: Bool { FocusOrigin.ringShown(focused: focused, keyboard: keyboardFocus, appearsActive: appearsActive) }

    private var wash: Color {
        switch surface {
        case .none: .clear
        case .hover: tone.hover
        case .raised: tone.raised
        }
    }

    var body: some View {
        VStack(spacing: 0) {
            HStack(spacing: Grid.gap) {
                VStack(alignment: .leading, spacing: Grid.nameToStatus) {
                    IdentityText(primary: row.identity_primary, secondary: row.has_identity_secondary ? row.identity_secondary : "")
                    Text(verbatim: row.status_line)
                        .font(Face.secondary)
                        .foregroundStyle(tone.text3)
                        .lineLimit(1)
                }
                .frame(minWidth: Grid.nameMinWidth, maxWidth: .infinity, alignment: .leading)
                UsageCell(window: row.window, busy: row.dot_busy)
                    .frame(width: Grid.usage)
                MenuPill(groups: AccountsModel.rowMenu(row, shell: shell),
                         autoOpenKey: .rowMenu(row: row.index),
                         accessibilityLabel: Copy.rowMenuAccessibility)
            }
            .padding(.horizontal, Grid.inset)
            .frame(height: Grid.accountsRow)
            .contentShape(Rectangle())
            .onTapGesture(perform: toggle)
            .onHover { inside in
                withAnimation(inside ? Motion.hoverIn(reduceMotion) : Motion.hoverOut(reduceMotion)) { hovering = inside }
            }
            .focusable()
            .focusEffectDisabled()
            .focused($focused)
            .onKeyPress(.return) { toggle(); return .handled }
            .onKeyPress(.space) { toggle(); return .handled }
            .accessibilityElement(children: .contain)
            .accessibilityLabel(AccountsModel.accessibilityLabel(row))
            .accessibilityValue(AccountsModel.accessibilityValue(row))
            .accessibilityHint(Copy.rowHint)
            .accessibilityAddTraits(.isButton)
            .opacity(AccountsModel.rowOpacity(row, enabled: enabled))
            if let panel {
                AccountDetail(usage: panel.0, inspector: panel.1)
                    .padding(.horizontal, Grid.panelInset)
                    .padding(.bottom, Grid.panelInset)
                    .transition(reduceMotion ? .opacity : .opacity.combined(with: .move(edge: .top)))
            }
        }


        .background {
            RoundedRectangle(cornerRadius: radius, style: .continuous)
                .fill(wash)
                .padding(Grid.panelInset)
        }
        .overlay {
            RoundedRectangle(cornerRadius: radius, style: .continuous)
                .strokeBorder(tone.point, lineWidth: ringShown ? 2 : 0)
                .padding(Grid.panelInset)
        }
    }

    private func toggle() {
        withAnimation(Motion.snappy(reduceMotion)) { submit(.toggle_account(row: row.index)) }
    }
}





struct IdentityText: View {
    enum Ink { case accounts, text, muted }

    let primary: String
    let secondary: String
    var ink: Ink = .accounts
    @Environment(\.tone) private var tone

    private var nameInk: Color { ink == .muted ? tone.text3 : tone.text }
    private var domainInk: Color {
        switch ink {
        case .accounts: tone.text2
        case .text: tone.text
        case .muted: tone.text3
        }
    }

    var body: some View {
        let name = Text(verbatim: primary).font(Face.name).foregroundStyle(nameInk)
        let domain = Text(verbatim: secondary).font(Face.body).foregroundStyle(domainInk)
        Text("\(name)\(domain)")
            .lineLimit(1)
            .truncationMode(.tail)
    }
}




struct UsageCell: View {
    let window: WindowCell
    let busy: Bool
    @Environment(\.tone) private var tone

    var body: some View {
        VStack(alignment: .leading, spacing: Grid.captionToBar) {
            HStack(alignment: .firstTextBaseline, spacing: Grid.bandGap) {
                if window.present {
                    Text(verbatim: window.caption)
                        .font(Face.secondary)
                        .foregroundStyle(tone.text3)
                        .lineLimit(1)
                        .truncationMode(.tail)
                }
                Spacer(minLength: Grid.bandGap)
                Text(verbatim: window.percent_text)
                    .font(Face.numeral)
                    .foregroundStyle(window.present && !busy ? tone.meterInk : tone.text3)
            }
            if window.present {
                Bar(fraction: window.fraction)
                    .accessibilityValue(window.percent_text)
            } else {
                Color.clear.frame(height: Grid.barHeight)
            }
        }
    }
}
