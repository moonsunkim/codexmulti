import AppKit
import SwiftUI



enum ShellBandLayout {
    static let scrollTopInset = Grid.band

    static func backdropFrame(width: CGFloat) -> CGRect {
        CGRect(x: 0, y: 0, width: width, height: Grid.band)
    }

    static func firstContentFrame(tab: ShellTab, width: CGFloat) -> CGRect {
        _ = tab
        return CGRect(
            x: Grid.L,
            y: scrollTopInset + Grid.contentTop,
            width: max(0, width - 2 * Grid.L),
            height: Grid.accountsRow)
    }
}




struct PaneBackdrop: View {
    @Environment(\.tone) private var tone
    @Environment(\.accessibilityReduceTransparency) private var reduceTransparency

    var body: some View {
        if reduceTransparency {
            tone.opaqueGround
        } else {
            ZStack {
                Rectangle().fill(tone.paneMaterial.material)
                tone.tint
            }
        }
    }
}




struct BandBackdrop: View {
    @Environment(\.tone) private var tone
    @Environment(\.accessibilityReduceTransparency) private var reduceTransparency

    var body: some View {
        Group {
            if reduceTransparency {
                tone.opaqueGround
            } else {
                ZStack(alignment: .bottom) {
                    BandVisualEffectView()
                        .frame(maxWidth: .infinity, maxHeight: .infinity)
                    tone.bandTint
                    Rectangle().fill(tone.hairline).frame(height: 1)
                }
            }
        }
        .frame(height: Grid.band)
        .frame(maxWidth: .infinity)
        .allowsHitTesting(false)
        .accessibilityHidden(true)
    }
}



struct BandVisualEffectView: NSViewRepresentable {
    static func makeEffectView() -> NSVisualEffectView {
        let view = NSVisualEffectView()
        configure(view)
        return view
    }

    static func configure(_ view: NSVisualEffectView) {
        if view.blendingMode != .withinWindow { view.blendingMode = .withinWindow }
        if view.material != .headerView { view.material = .headerView }
        if view.state != .active { view.state = .active }
    }

    func makeNSView(context: Context) -> NSVisualEffectView { Self.makeEffectView() }
    func updateNSView(_ nsView: NSVisualEffectView, context: Context) { Self.configure(nsView) }
}



struct SettingsShell: View {
    let store: CoreStore
    let options: LaunchOptions
    let submit: IntentSink
    @Environment(\.openWindow) private var openWindow
    @Environment(\.accessibilityReduceTransparency) private var reduceTransparency
    @Environment(\.accessibilityReduceMotion) private var reduceMotion
    @Environment(\.colorSchemeContrast) private var contrast
    @Environment(\.colorScheme) private var colorScheme
    @State private var selectedTab: ShellTab
    @State private var launchIntentsSent = false
    @State private var languageResolutionSent = false
    @State private var proxyDrafts = ProxyDrafts()
    @State private var focusOrigin = FocusOrigin()
    private var appearance: Appearance {
        if options.capturePath != nil, let override = options.setAppearanceOnLaunch { return override }
        return store.projection?.view.settings.appearance ?? .system
    }

    init(store: CoreStore, options: LaunchOptions, submit: @escaping IntentSink) {
        self.store = store
        self.options = options
        self.submit = submit
        _selectedTab = State(initialValue: options.tab == .failover ? .settings : .accounts)
    }

    var body: some View {
        let tone = AppearanceResolver.tone(for: colorScheme, contrast: contrast)
        ZStack(alignment: .top) {
            PaneBackdrop()
                .environment(\.tone, tone)
            ScrollView {
                VStack(alignment: .leading, spacing: 0) {
                    if let projection = store.projection,
                       AccountsModel.noticeIsShown(projection.shell) {
                        NoticeSlot(notice: projection.shell.notice)
                            .padding(.horizontal, Grid.L)
                            .padding(.top, Grid.noticeBelowBand)
                    }
                    content
                        .padding(.top, Grid.contentTop)
                        .frame(maxWidth: .infinity, alignment: .leading)
                }
                .padding(.top, ShellBandLayout.scrollTopInset).padding(.bottom, Grid.contentBottom)
                .animation(Motion.snappy(reduceMotion), value: store.projection?.shell.notice)
            }.scrollIndicators(.hidden)
            if selectedTab == .accounts,
               let projection = store.projection,
               projection.view.onboarding_visible,
               projection.view.unified_rows.isEmpty {
                EmptyAccountsPage(projection: projection)
            }
        }
        .overlay(alignment: .top) {
            BandBackdrop().environment(\.tone, tone)
        }
        .overlay(alignment: .top) {
            if options.capturePath != nil {
                ZStack {
                    SegmentPill(tab: selectedTab) { selectedTab = $0 }
                    if let projection = store.projection {
                        HStack {
                            Spacer(minLength: 0)
                            BandControls(projection: projection)
                        }
                    }
                }
                .padding(.leading, Grid.L)
                .frame(height: Grid.band)
            }
        }
        .frame(maxWidth: .infinity, maxHeight: .infinity)
        .clipShape(RoundedRectangle(cornerRadius: Grid.windowRadius, style: .continuous))
        .overlay(RoundedRectangle(cornerRadius: Grid.windowRadius, style: .continuous).strokeBorder(tone.rim, lineWidth: 1))
        .ignoresSafeArea().frame(minWidth: Grid.minWidth, minHeight: Grid.minHeight)
        .background {
            if options.capturePath == nil {
                WindowChrome(options: options)
            }
        }
        .dialogs(store: store)
        .environment(\.tone, tone).environment(\.submit, submit).environment(\.autoOpen, options.open)
        .environment(\.renderedAppearance, options.capturePath == nil ? nil : appearance)
        .environment(\.renderedVersionText, options.capturePath == nil ? nil : options.captureVersionText)
        .environment(\.keyboardFocus, focusOrigin.isKeyboard)
        .toolbar {
            if options.capturePath == nil {
                ToolbarItem(placement: .principal) {
                    SegmentPill(tab: selectedTab) { selectedTab = $0 }
                        .environment(\.tone, tone)
                        .environment(\.keyboardFocus, focusOrigin.isKeyboard)
                }.sharedBackgroundVisibility(.hidden)
                ToolbarItem(placement: .primaryAction) {
                    if let projection = store.projection {
                        BandControls(projection: projection)
                            .environment(\.tone, tone)
                            .environment(\.submit, submit)
                    }
                }.sharedBackgroundVisibility(.hidden)
            }
        }
        .toolbarBackgroundVisibility(.hidden, for: .windowToolbar)
        .onAppear {
            if options.capturePath == nil {
                WindowPresenter.shared.open = { openWindow(id: SettingsWindowScene.id) }
                SettingsTabPresenter.shared.register { selectedTab = $0 }
                focusOrigin.install()
            }
        }
        .onDisappear {
            if options.capturePath == nil {
                SettingsTabPresenter.shared.unregister()
                focusOrigin.uninstall()
            }
        }
        .onChange(of: store.isStarted, initial: true) { _, started in
            guard started, !launchIntentsSent else { return }
            Task { @MainActor in
                guard !launchIntentsSent else { return }
                launchIntentsSent = true
                if let row = options.expand { submit(.toggle_account(row: row)) }
            }
        }
        .onChange(of: store.projection?.view.settings.language, initial: true) { _, language in
            guard let language, !languageResolutionSent else { return }
            languageResolutionSent = true
            submit(PreferencesModel.languageIntent(language, system: SystemLanguageResolver.current))
        }
    }

    @ViewBuilder private var content: some View {
        switch selectedTab {
        case .accounts:
            if let projection = store.projection {
                UnifiedPage(projection: projection)
            } else {
                starting
            }
        case .settings:
            if let projection = store.projection {
                SettingsPage(projection: projection, drafts: $proxyDrafts)
            } else {
                starting
            }
        }
    }

    private var starting: some View {
        NoAccountsPanel(title: Copy.starting, showsButtons: false, canManage: false)
            .frame(maxWidth: .infinity)
            .padding(.horizontal, Grid.L)
    }
}
