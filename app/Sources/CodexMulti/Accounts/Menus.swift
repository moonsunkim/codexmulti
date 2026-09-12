import SwiftUI





struct MenuPopover: View {
    let groups: [[AccountsModel.MenuItem]]
    let dismiss: () -> Void
    @Environment(\.tone) private var tone
    @Environment(\.submit) private var submit
    @Environment(\.accessibilityReduceTransparency) private var reduceTransparency
    @State private var highlighted: String?
    @FocusState private var focused: Bool

    private var enabledIDs: [String] { groups.flatMap { $0 }.filter(\.enabled).map(\.id) }

    var body: some View {
        VStack(alignment: .leading, spacing: Grid.menuGroupGap) {
            ForEach(Array(groups.enumerated()), id: \.offset) { _, group in
                VStack(alignment: .leading, spacing: 0) {
                    ForEach(group) { item in
                        MenuLine(item: item, highlighted: highlighted == item.id) {
                            choose(item)
                        } onHover: { inside in
                            if inside { highlighted = item.enabled ? item.id : nil } else if highlighted == item.id { highlighted = nil }
                        }
                    }
                }
            }
        }
        .padding(Grid.menuPadding)
        .frame(width: Grid.menuWidth)
        .background(reduceTransparency ? tone.opaqueFloat : Color.clear)
        .focusable()
        .focusEffectDisabled()
        .focused($focused)
        .onAppear { focused = true }
        .onKeyPress(.downArrow) { move(1); return .handled }
        .onKeyPress(.upArrow) { move(-1); return .handled }
        .onKeyPress(.return) { activateHighlighted() }
        .onKeyPress(.space) { activateHighlighted() }
    }

    private func choose(_ item: AccountsModel.MenuItem) {
        guard item.enabled else { return }
        dismiss()
        submit(item.intent)
    }

    private func move(_ delta: Int) {
        let ids = enabledIDs
        guard !ids.isEmpty else { return }
        guard let current = highlighted, let index = ids.firstIndex(of: current) else {
            highlighted = delta > 0 ? ids.first : ids.last
            return
        }
        highlighted = ids[(index + delta + ids.count) % ids.count]
    }

    private func activateHighlighted() -> KeyPress.Result {
        guard let id = highlighted, let item = groups.flatMap({ $0 }).first(where: { $0.id == id }) else { return .ignored }
        choose(item)
        return .handled
    }
}



struct MenuLine: View {
    let item: AccountsModel.MenuItem
    let highlighted: Bool
    let action: () -> Void
    let onHover: (Bool) -> Void
    @Environment(\.tone) private var tone

    var body: some View {
        Button(action: action) {
            HStack {
                Text(verbatim: item.label)
                    .font(Face.menu)
                    .foregroundStyle(item.enabled ? (item.destructive ? tone.destructive : tone.text) : tone.text3)
                    .lineLimit(1)
                Spacer(minLength: 0)
            }
            .padding(.horizontal, 10)
            .padding(.vertical, 6)
            .background(RoundedRectangle(cornerRadius: 7, style: .continuous).fill(highlighted && item.enabled ? tone.pillHover : .clear))
            .contentShape(Rectangle())
        }
        .buttonStyle(.plain)
        .disabled(!item.enabled)
        .onHover(perform: onHover)
        .accessibilityLabel(item.label)
    }
}







struct MenuPill: View {
    let groups: [[AccountsModel.MenuItem]]
    let autoOpenKey: LaunchOptions.OpenTarget
    let accessibilityLabel: String
    @Environment(\.tone) private var tone
    @Environment(\.autoOpen) private var autoOpen
    @State private var open = false
    @State private var hovering = false

    var body: some View {
        Button { open.toggle() } label: {
            Image(systemName: "ellipsis")
                .font(.system(size: 12, weight: .semibold))
                .foregroundStyle(tone.text2)
                .frame(width: Grid.menu, height: Grid.menuPillHeight)
                .background(Capsule().fill(hovering || open ? tone.pillHover : tone.pill))
                .contentShape(Capsule())
        }
        .buttonStyle(.plain)
        .onHover { hovering = $0 }
        .accessibilityLabel(accessibilityLabel)
        .popover(isPresented: $open, attachmentAnchor: .rect(.bounds), arrowEdge: .bottom) {
            MenuPopover(groups: groups) { open = false }
                .environment(\.tone, tone)
        }
        .task {
            guard autoOpen == autoOpenKey else { return }
            try? await Task.sleep(for: AutoOpen.settle)
            open = true
        }
    }
}









enum BandGlassStyle: String, CaseIterable, Equatable, Sendable {
    case clear, regular, material

    static let defaultsKey = "BandGlass"

    static let launch = BandGlassStyle(defaults: .standard)


    init(defaultsValue: String?) {
        let word = defaultsValue?.trimmingCharacters(in: .whitespacesAndNewlines).lowercased() ?? ""
        self = BandGlassStyle(rawValue: word) ?? .material
    }

    init(defaults: UserDefaults) {
        self.init(defaultsValue: defaults.string(forKey: Self.defaultsKey))
    }



    func glass(tint: Color) -> Glass? {
        switch self {
        case .clear: .clear
        case .regular: Glass.regular.tint(tint)
        case .material: nil
        }
    }
}









struct BandGlass: ViewModifier {
    let interactive: Bool
    var style: BandGlassStyle = .launch
    @Environment(\.tone) private var tone
    @Environment(\.accessibilityReduceTransparency) private var reduceTransparency

    func body(content: Content) -> some View {
        if reduceTransparency {
            content.background(Capsule().fill(tone.pill))
        } else if let glass = style.glass(tint: tone.bandTint) {
            content.glassEffect(glass.interactive(interactive), in: Capsule())
        } else {
            content.background(Capsule().fill(tone.capsule))
        }
    }
}

extension View {
    func bandGlass(interactive: Bool = false) -> some View {
        modifier(BandGlass(interactive: interactive))
    }
}
