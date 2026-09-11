import AppKit
import SwiftUI




enum StateBadgeLayout {
    static let renderedLabels = UnifiedFailoverState.allCases.map(\.renderedBadgeText)
    static let columnWidth: CGFloat = {
        let font = NSFont.systemFont(ofSize: Face.badgePointSize, weight: .semibold)
        let widestText = renderedLabels
            .map { ($0 as NSString).size(withAttributes: [.font: font]).width }
            .max() ?? 0
        return ceil(widestText) + 2 * Grid.badgePaddingHorizontal
    }()
}












struct FailoverRow: View {
    let row: ProxyAccountView
    @Environment(\.tone) private var tone

    var body: some View {
        HStack(spacing: Grid.gap) {
            HStack(alignment: .firstTextBaseline, spacing: 0) {
                StateBadge(text: row.state_text, style: FailoverModel.badgeStyle(row))
                    .frame(width: StateBadgeLayout.columnWidth, alignment: .leading)
                IdentityText(primary: row.label_local, secondary: row.label_domain,
                             ink: FailoverModel.labelInk(row) == .muted ? .muted : .text)
                    .padding(.leading, Grid.badgeGap)
                    .layoutPriority(1)
                Text(verbatim: FailoverModel.detailLine(row))
                    .font(Face.secondary)
                    .foregroundStyle(tone.text3)
                    .lineLimit(1)
                    .truncationMode(.tail)
                    .padding(.leading, Grid.detailGap)
            }
            .frame(maxWidth: .infinity, alignment: .leading)
            if FailoverModel.menuShown(row) {
                MenuPill(groups: FailoverModel.rowMenu(row),
                         autoOpenKey: .proxyRowMenu(row: row.index),
                         accessibilityLabel: Copy.failoverRowMenuAccessibility)
            } else {
                Color.clear.frame(width: Grid.menu, height: Grid.menuPillHeight)
            }
        }
        .padding(.horizontal, Grid.inset)
        .frame(height: Grid.failoverRow)
        .accessibilityElement(children: .contain)
        .accessibilityLabel(FailoverModel.accessibilityLabel(row))
        .accessibilityValue(FailoverModel.accessibilityValue(row))
    }
}






struct StateBadge: View {
    let text: String
    let style: FailoverModel.BadgeStyle
    @Environment(\.tone) private var tone

    private var ink: Color {
        switch style {
        case .active: tone.point
        case .ready: tone.text
        case .muted: tone.text3
        }
    }

    private var fill: Color {
        switch style {
        case .active: tone.badgePoint
        case .ready: tone.badge
        case .muted: tone.badgeMuted
        }
    }

    var body: some View {
        Text(verbatim: text)
            .font(Face.badge)
            .foregroundStyle(ink)
            .lineLimit(1)
            .padding(.horizontal, Grid.badgePaddingHorizontal)
            .padding(.vertical, Grid.badgePaddingVertical)
            .background(Capsule().fill(fill))
            .accessibilityHidden(true)
    }
}
