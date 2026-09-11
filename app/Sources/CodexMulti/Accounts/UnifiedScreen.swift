import SwiftUI

enum UnifiedModel {
    static func rows(_ view: ViewState) -> [UnifiedRowView] { view.unified_rows }
    static func menuShown(_ row: UnifiedRowView, shell: ShellState, topAccountID: String? = nil) -> Bool {
        let shown = !rowMenu(row, shell: shell, topAccountID: topAccountID).flatMap { $0 }.isEmpty
        assert(shown, "A saved account must expose at least one row action")
        return shown
    }
    static func toggle(_ row: UnifiedRowView) -> Intent { .toggle_account(row: row.account_index) }
    static func panelShown(_ row: UnifiedRowView, view: ViewState) -> Bool {
        row.expanded && view.inspector.present && row.inspector_index == view.inspector.index
    }


    static func rowOpacity(_ row: UnifiedRowView, enabled: Bool, expanded: Bool) -> Double {
        !expanded && (row.usage_exhausted || !enabled) ? Tone.exhaustedOpacity : 1
    }
    static func rowMenu(_ row: UnifiedRowView, shell: ShellState,
                        topAccountID: String? = nil) -> [[AccountsModel.MenuItem]] {
        typealias Item = AccountsModel.MenuItem
        let account = row.account_index
        let accountID = row.account_id
        var actions: [Item] = []
        if row.action_refresh { actions.append(Item("refresh", Copy.refresh, enabled: shell.can_refresh && !row.action_busy, intent: .refresh_account(row: account))) }


        if row.has_actions {
            if row.can_switch_proxy {
                actions.append(Item("switch", row.switch_label, intent: .begin_failover_switch(row: account)))
            } else if row.can_switch, let proxy = row.proxy_index {
                actions.append(Item("switch", Copy.useInFailover, intent: .begin_proxy_switch(row: proxy)))
            }
            if row.can_pause_proxy {
                actions.append(Item("pause", Copy.pauseInFailover, intent: .pause_failover_account(row: account)))
            } else if row.can_pause, let proxy = row.proxy_index {
                actions.append(Item("pause", Copy.pauseInFailover, intent: .pause_proxy_account(row: proxy)))
            }
            if row.can_resume, let proxy = row.proxy_index {
                actions.append(Item("resume", Copy.resumeInFailover, intent: .resume_proxy_account(row: proxy)))
            }
        }
        if row.can_reset { actions.append(Item("reset", row.reset_label, intent: .begin_reset(row: account))) }
        if row.has_actions && row.can_clear_cooldown {
            actions.append(Item("clear_cooldown", Copy.clearCooldown, intent: .begin_clear_cooldown_account(row: account)))
        }
        let top = topAccountID ?? accountID
        var management = [
            Item("move_to_top", Copy.moveToTop,
                 enabled: shell.can_manage_accounts && accountID != top,
                 intent: .move_account(account_id: accountID, target_account_id: top)),
        ]
        if shell.can_manage_accounts {
            management.append(Item("rename", Copy.rename, intent: .begin_rename(row: account)))
            management.append(Item("remove", Copy.remove, destructive: true, intent: .begin_remove(row: account)))
        }
        return [actions, management].filter { !$0.isEmpty }
    }
}

struct UnifiedPage: View {
    let projection: Projection
    @Environment(\.tone) private var tone
    @Environment(\.submit) private var submit
    @Environment(\.accessibilityReduceMotion) private var reduceMotion
    @State private var order: OptimisticAccountOrder
    @State private var rowFrames: [UInt32: CGRect] = [:]
    @State private var drag: AccountDragState?
    private static let reorderSpace = "CodexMulti.AccountReorder"

    init(projection: Projection) {
        self.projection = projection
        _order = State(initialValue: OptimisticAccountOrder(
            projectedKeys: projection.view.unified_rows.map(\.key)))
    }

    private var rows: [UnifiedRowView] {
        order.rows(from: projection.view.unified_rows)
    }

    var body: some View {
        VStack(alignment: .leading, spacing: 0) {
            if AccountsModel.bannerIsShown(projection.view) {
                ProxyBanner(text: projection.view.proxy_banner_text,
                            showsRetry: AccountsModel.bannerShowsRetry(projection.view),
                            canRetry: projection.shell.proxy_can_refresh)
                    .padding(.bottom, Grid.bannerToContainer)
            }
            if !projection.view.unified_rows.isEmpty {
                Container {
                    ForEach(Array(rows.enumerated()), id: \.element.key) { index, row in
                        UnifiedAccountRow(row: row, projection: projection,
                                          topAccountID: rows.first?.account_id)
                            .background {
                                GeometryReader { geometry in
                                    Color.clear.preference(
                                        key: AccountRowFramePreferenceKey.self,
                                        value: [row.key: geometry.frame(in: .named(Self.reorderSpace))])
                                }
                            }
                            .background {
                                if drag?.key == row.key {
                                    RoundedRectangle(cornerRadius: Grid.panelRadius, style: .continuous)
                                        .fill(tone.opaqueFloat)
                                }
                            }
                            .opacity(drag?.key == row.key ? 0.94 : 1)
                            .shadow(color: .black.opacity(drag?.key == row.key ? 0.18 : 0),
                                    radius: drag?.key == row.key ? 10 : 0, y: 3)
                            .offset(y: drag?.key == row.key ? drag?.translationY ?? 0 : 0)
                            .zIndex(drag?.key == row.key ? 1 : 0)
                            .simultaneousGesture(reorderGesture(for: row))
                        if index < rows.count - 1 { Hairline() }
                    }
                }
                .background(WindowMoveExclusion())
                .coordinateSpace(name: Self.reorderSpace)
                .overlay(alignment: .topLeading) {
                    if let insertionY {
                        Rectangle()
                            .fill(tone.point)
                            .frame(height: 1.5)
                            .padding(.horizontal, Grid.inset)
                            .offset(y: insertionY - 0.75)
                            .accessibilityHidden(true)
                    }
                }
                .onPreferenceChange(AccountRowFramePreferenceKey.self) { frames in
                    if drag == nil { rowFrames = frames }
                }
            }
        }
        .padding(.horizontal, Grid.L)
        .onChange(of: projection) { _, next in
            order.receiveProjection(keys: next.view.unified_rows.map(\.key))
            drag = nil
        }
    }

    private var insertionY: CGFloat? {
        guard let drag, drag.destinationIndex != drag.sourceIndex,
              rows.indices.contains(drag.destinationIndex),
              let frame = rowFrames[rows[drag.destinationIndex].key] else { return nil }
        return drag.destinationIndex < drag.sourceIndex ? frame.minY : frame.maxY
    }

    private func reorderGesture(for row: UnifiedRowView) -> some Gesture {
        DragGesture(minimumDistance: 8, coordinateSpace: .named(Self.reorderSpace))
            .onChanged { value in updateDrag(row: row, translationY: value.translation.height) }
            .onEnded { _ in finishDrag(row: row) }
    }

    private func updateDrag(row: UnifiedRowView, translationY: CGFloat) {
        guard !order.awaitingProjection,
              let sourceIndex = rows.firstIndex(where: { $0.key == row.key }) else { return }
        var next = drag
        if next?.key != row.key {
            let midpoints = rows.enumerated().map { index, candidate in
                rowFrames[candidate.key]?.midY ?? (CGFloat(index) + 0.5) * Grid.accountsRow
            }
            next = AccountDragState(key: row.key, sourceIndex: sourceIndex,
                                    sourceAccountID: row.account_id,
                                    originMidY: midpoints[sourceIndex], rowMidpoints: midpoints,
                                    translationY: 0, destinationIndex: sourceIndex)
        }
        guard var next else { return }
        next.translationY = translationY
        next.destinationIndex = AccountReorder.destinationIndex(
            rowMidpoints: next.rowMidpoints, draggedIndex: next.sourceIndex,
            draggedMidY: next.originMidY + translationY) ?? next.sourceIndex
        drag = next
    }

    private func finishDrag(row: UnifiedRowView) {
        guard let finished = drag, finished.key == row.key else { return }
        let destination = finished.destinationIndex
        guard destination != finished.sourceIndex, rows.indices.contains(destination) else {
            drag = nil
            return
        }
        let destinationAccountID = rows[destination].account_id
        let moved = withAnimation(Motion.snappy(reduceMotion)) {
            drag = nil
            return order.move(from: finished.sourceIndex, to: destination)
        }
        guard moved else { return }
        submit(.move_account(account_id: finished.sourceAccountID, target_account_id: destinationAccountID))
    }
}

private struct AccountDragState {
    let key: UInt32
    let sourceIndex: Int
    let sourceAccountID: String
    let originMidY: CGFloat
    let rowMidpoints: [CGFloat]
    var translationY: CGFloat
    var destinationIndex: Int
}

private struct AccountRowFramePreferenceKey: PreferenceKey {
    static let defaultValue: [UInt32: CGRect] = [:]
    static func reduce(value: inout [UInt32: CGRect], nextValue: () -> [UInt32: CGRect]) {
        value.merge(nextValue(), uniquingKeysWith: { _, latest in latest })
    }
}

struct UnifiedRowHeader: View {
    let row: UnifiedRowView
    let shell: ShellState
    let topAccountID: String?
    @Environment(\.tone) private var tone

    init(row: UnifiedRowView, shell: ShellState, topAccountID: String? = nil) {
        self.row = row
        self.shell = shell
        self.topAccountID = topAccountID
    }

    var body: some View {
        HStack(spacing: Grid.gap) {
            HStack(alignment: .center, spacing: 0) {
                StateBadge(text: row.failover_state_text,
                           style: row.failover_accent ? .active : row.failover_muted ? .muted : .ready)
                    .frame(width: StateBadgeLayout.columnWidth, alignment: .leading)
                Color.clear
                    .frame(width: Grid.badgeGap)
                HStack(alignment: .firstTextBaseline, spacing: Grid.planGap) {
                    Text(verbatim: row.email_local + (row.has_domain ? row.email_domain : ""))
                        .font(Face.body)
                        .foregroundStyle(tone.text)
                        .lineLimit(1)
                        .truncationMode(.tail)
                    if row.has_plan {
                        Text(verbatim: row.plan)
                            .font(Face.secondary)
                            .foregroundStyle(tone.text3)
                            .lineLimit(1)
                            .fixedSize(horizontal: true, vertical: false)
                            .layoutPriority(1)
                    }
                }
                .frame(maxWidth: .infinity, alignment: .leading)
            }
            .frame(maxWidth: .infinity, alignment: .leading)
            VStack(alignment: .leading, spacing: Grid.captionToBar) {
                HStack(alignment: .firstTextBaseline, spacing: Grid.bandGap) {
                    Text(verbatim: row.usage_caption)
                        .font(Face.secondary)
                        .foregroundStyle(tone.text3)
                        .lineLimit(1)
                    Spacer(minLength: Grid.bandGap)
                    Text(verbatim: row.usage_percent_text)
                        .font(Face.numeral)
                        .foregroundStyle(row.action_busy ? tone.text3 : tone.meterInk)
                }
                Group {
                    if row.usage_caption.isEmpty { Color.clear.frame(height: Grid.barHeight) }
                    else { Bar(fraction: row.usage_bar_fraction) }
                }
            }
            .frame(width: Grid.usage)
            if UnifiedModel.menuShown(row, shell: shell, topAccountID: topAccountID) {
                MenuPill(groups: UnifiedModel.rowMenu(row, shell: shell, topAccountID: topAccountID), autoOpenKey: .rowMenu(row: row.account_index), accessibilityLabel: Copy.rowMenuAccessibility)
            } else { Color.clear.frame(width: Grid.menu, height: Grid.menuPillHeight) }
        }
        .padding(.horizontal, Grid.inset)
        .frame(height: Grid.accountsRow)
    }
}

struct UnifiedAccountRow: View {
    let row: UnifiedRowView
    let projection: Projection
    let topAccountID: String?
    @Environment(\.tone) private var tone
    @Environment(\.submit) private var submit
    @Environment(\.accessibilityReduceMotion) private var reduceMotion
    @Environment(\.keyboardFocus) private var keyboardFocus
    @Environment(\.appearsActive) private var appearsActive
    @State private var hovering = false
    @FocusState private var focused: Bool

    init(row: UnifiedRowView, projection: Projection, topAccountID: String? = nil) {
        self.row = row
        self.projection = projection
        self.topAccountID = topAccountID
    }

    private var expanded: Bool { UnifiedModel.panelShown(row, view: projection.view) }
    private var radius: CGFloat { expanded ? Grid.panelRadius : Grid.hoverRadius }
    private var enabled: Bool {
        let index = Int(row.account_index)
        return projection.view.rows.indices.contains(index) ? projection.view.rows[index].enabled : true
    }

    var body: some View {
        VStack(spacing: 0) {
            UnifiedRowHeader(row: row, shell: projection.shell, topAccountID: topAccountID)
                .contentShape(Rectangle())
                .onTapGesture(perform: toggle)
                .onHover { value in withAnimation(value ? Motion.hoverIn(reduceMotion) : Motion.hoverOut(reduceMotion)) { hovering = value } }
                .focusable().focusEffectDisabled().focused($focused)
                .onKeyPress(.return) { toggle(); return .handled }
                .onKeyPress(.space) { toggle(); return .handled }
                .accessibilityElement(children: .contain)
                .accessibilityLabel(row.identity_label + ", " + row.failover_state_text)
                .accessibilityValue(row.usage_caption + " " + row.usage_percent_text)
                .accessibilityHint(Copy.rowHint + ". " + Copy.reorderHint).accessibilityAddTraits(.isButton)
                .opacity(UnifiedModel.rowOpacity(row, enabled: enabled, expanded: expanded))
            if expanded {
                AccountDetail(usage: projection.view.usage_rows, inspector: projection.view.inspector)
                    .padding(.horizontal, Grid.panelInset).padding(.bottom, Grid.panelInset)
                    .transition(reduceMotion ? .opacity : .opacity.combined(with: .move(edge: .top)))
            }
        }
        .background(RoundedRectangle(cornerRadius: radius, style: .continuous).fill(expanded ? tone.raised : hovering ? tone.hover : .clear).padding(Grid.panelInset))
        .overlay(RoundedRectangle(cornerRadius: radius, style: .continuous).strokeBorder(tone.point, lineWidth: FocusOrigin.ringShown(focused: focused, keyboard: keyboardFocus, appearsActive: appearsActive) ? 2 : 0).padding(Grid.panelInset))
    }
    private func toggle() { withAnimation(Motion.snappy(reduceMotion)) { submit(UnifiedModel.toggle(row)) } }
}
