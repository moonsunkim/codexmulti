import SwiftUI
import os



struct SegmentPill: View {
    let tab: ShellTab
    let select: (ShellTab) -> Void
    @Environment(\.tone) private var tone
    @Environment(\.accessibilityReduceMotion) private var reduceMotion
    @Environment(\.keyboardFocus) private var keyboardFocus
    @Environment(\.appearsActive) private var appearsActive
    @Namespace private var namespace
    @FocusState private var focused: Bool

    private var ringShown: Bool {
        FocusOrigin.ringShown(focused: focused, keyboard: keyboardFocus, appearsActive: appearsActive)
    }

    private static let order: [ShellTab] = [.accounts, .settings]

    var body: some View {
        HStack(spacing: 0) {
            ForEach(Self.order, id: \.self) { candidate in
                Text(verbatim: label(candidate))
                    .font(tab == candidate ? Face.bandStrong : Face.band)
                    .foregroundStyle(tab == candidate ? tone.text : tone.text2)
                    .frame(width: Grid.segmentWidth, height: Grid.segmentHeight)
                    .background {
                        if tab == candidate {
                            Capsule().fill(tone.segment).matchedGeometryEffect(id: "segment", in: namespace)
                        }
                    }
                    .contentShape(Capsule())
                    .onTapGesture { pick(candidate) }
            }
        }
        .padding(Grid.segmentPadding)
        .bandGlass()
        .overlay(Capsule().strokeBorder(tone.point, lineWidth: ringShown ? 2 : 0).padding(-2))
        .focusable()
        .focusEffectDisabled()
        .focused($focused)
        .onKeyPress(.leftArrow) { step(-1); return .handled }
        .onKeyPress(.rightArrow) { step(1); return .handled }
        .accessibilityElement(children: .ignore)
        .accessibilityLabel(Copy.segmentAccessibility)
        .accessibilityValue(label(tab))
    }

    private func label(_ tab: ShellTab) -> String {
        switch tab {
        case .accounts: Copy.tabAccounts
        case .settings: Copy.tabSettings
        }
    }

    private func pick(_ candidate: ShellTab) {
        guard candidate != tab else { return }
        withAnimation(Motion.snappy(reduceMotion)) { select(candidate) }
    }

    private func step(_ delta: Int) {
        guard let index = Self.order.firstIndex(of: tab) else { return }
        let next = min(max(index + delta, 0), Self.order.count - 1)
        pick(Self.order[next])
    }
}



struct StatusPill: View {
    let projection: Projection
    @Environment(\.tone) private var tone
    @Environment(\.accessibilityReduceMotion) private var reduceMotion

    var body: some View {
        HStack(spacing: Grid.bandGap) {
            switch AccountsModel.pillDot(projection.view) {
            case .point: Circle().fill(tone.point).frame(width: 6, height: 6)
            case .muted: Circle().fill(tone.text3).frame(width: 6, height: 6)
            case .none: EmptyView()
            }
            Text(verbatim: AccountsModel.pillText(projection.view, reduceMotion: reduceMotion))
                .font(Face.band)
                .foregroundStyle(tone.text2)
                .lineLimit(1)
        }
        .padding(.horizontal, 14)
        .frame(height: Grid.pillHeight)
        .bandGlass()
        .accessibilityElement(children: .ignore)
        .accessibilityLabel(Copy.statusAccessibility)
        .accessibilityValue(AccountsModel.pillText(projection.view, reduceMotion: reduceMotion))
    }
}



struct RefreshButton: View {
    let projection: Projection
    @Environment(\.tone) private var tone
    @Environment(\.submit) private var submit
    @Environment(\.accessibilityReduceMotion) private var reduceMotion
    @State private var spin = RefreshSpin()

    private static let log = Logger(subsystem: "dev.codexmulti.app", category: "band")
    private var enabled: Bool { projection.shell.can_refresh_all }
    private var turning: Bool { spin.spinning && !reduceMotion }

    var body: some View {
        Button { submit(.refresh_all) } label: {
            TimelineView(.animation(paused: !turning)) { context in
                Image(systemName: "arrow.clockwise")
                    .font(.system(size: 11, weight: .semibold))
                    .foregroundStyle(tone.text2)
                    .rotationEffect(turning ? RefreshSpin.angle(at: context.date) : .zero)
                    .frame(width: BandControlLayout.buttonDiameter,
                           height: BandControlLayout.buttonDiameter)
                    .contentShape(Circle())
                    .opacity(enabled ? 1 : Tone.disabledOpacity)
            }
        }
        .buttonStyle(.plain)
        .disabled(!enabled)
        .bandGlass(interactive: true)
        .help(Copy.refreshAllHelp)
        .accessibilityLabel(Copy.refreshAllHelp)
        .accessibilityValue(AccountsModel.pillText(projection.view, reduceMotion: reduceMotion))
        .onChange(of: RefreshSpin.Inputs(projection.view), initial: true) { _, inputs in
            if let transition = spin.observe(inputs) {
                Self.log.debug("refresh glyph \(transition.description, privacy: .public) busy_count=\(projection.view.busy_count, privacy: .public) proxy_work=\(projection.view.proxy_work.rawValue, privacy: .public)")
            }
        }
    }
}



struct AddButton: View {
    let projection: Projection
    @Environment(\.tone) private var tone
    @Environment(\.submit) private var submit

    private var enabled: Bool { projection.shell.can_manage_accounts }

    var body: some View {
        Button { submit(.begin_add_account) } label: {
            Image(systemName: "plus")
                .font(.system(size: 13, weight: .semibold))
                .foregroundStyle(tone.text2)
                .frame(width: BandControlLayout.buttonDiameter,
                       height: BandControlLayout.buttonDiameter)
                .contentShape(Circle())
                .opacity(enabled ? 1 : Tone.disabledOpacity)
        }
        .buttonStyle(.plain)
        .disabled(!enabled)
        .bandGlass(interactive: true)
        .help(Copy.addCodexMenu)
        .accessibilityLabel(Copy.addCodexMenu)
    }
}




struct BandControlLayout: Layout {
    static let buttonDiameter = Grid.pillHeight

    struct Frames: Equatable {
        let status: CGRect
        let refresh: CGRect
        let add: CGRect
    }

    static func frames(statusWidth: CGFloat, origin: CGPoint = .zero) -> Frames {
        let status = CGRect(x: origin.x, y: origin.y, width: statusWidth, height: buttonDiameter)
        let refresh = CGRect(x: status.maxX + Grid.bandGap, y: origin.y,
                             width: buttonDiameter, height: buttonDiameter)
        let add = CGRect(x: refresh.maxX + Grid.bandGap, y: origin.y,
                         width: buttonDiameter, height: buttonDiameter)
        return Frames(status: status, refresh: refresh, add: add)
    }

    func sizeThatFits(proposal: ProposedViewSize, subviews: Subviews, cache: inout ()) -> CGSize {
        guard subviews.count == 3 else { return .zero }
        let statusWidth = subviews[0].sizeThatFits(.unspecified).width
        let frames = Self.frames(statusWidth: statusWidth)
        return CGSize(width: frames.add.maxX, height: Self.buttonDiameter)
    }

    func placeSubviews(in bounds: CGRect, proposal: ProposedViewSize,
                       subviews: Subviews, cache: inout ()) {
        guard subviews.count == 3 else { return }
        let statusWidth = subviews[0].sizeThatFits(.unspecified).width
        let frames = Self.frames(statusWidth: statusWidth, origin: bounds.origin)
        for (subview, frame) in zip(subviews, [frames.status, frames.refresh, frames.add]) {
            subview.place(
                at: frame.origin,
                anchor: .topLeading,
                proposal: ProposedViewSize(width: frame.width, height: frame.height))
        }
    }
}

struct BandControls: View {
    let projection: Projection

    var body: some View {
        BandControlLayout {
            StatusPill(projection: projection)
            RefreshButton(projection: projection)
            AddButton(projection: projection)
        }
        .padding(.trailing, Grid.inset)
    }
}
