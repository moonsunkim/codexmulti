import SwiftUI




struct ProxyLifecyclePanel: View {
    let settings: SettingsView
    init(settings: SettingsView) { self.settings = settings }
    init(view: ViewState) { self.settings = view.settings }
    @Environment(\.tone) private var tone
    @Environment(\.submit) private var submit
    @State private var confirmation = ProxyConfirmationGate()
    @State private var advancedExpanded = false

    var body: some View {
        Container {
            proxyEnabledRow
            Hairline()
            advancedDisclosureRow
            if advancedExpanded {
                Hairline()
                serviceRow
                Hairline()
                routingRow
            }
        }
        .confirmationDialog(clientPresentation.title, isPresented: presented(.clientQuiescence), titleVisibility: .visible) {
            Button(clientPresentation.confirmTitle) { confirm(.clientQuiescence) }
            Button(Copy.cancel, role: .cancel) { confirmation.cancel(.clientQuiescence) }
        } message: {
            Text(verbatim: clientPresentation.message)
        }
        .confirmationDialog(replacementPresentation.title, isPresented: presented(.replaceRouting), titleVisibility: .visible) {
            Button(replacementPresentation.confirmTitle, role: .destructive) { confirm(.replaceRouting) }
            Button(Copy.cancel, role: .cancel) { confirmation.cancel(.replaceRouting) }
        } message: {
            Text(verbatim: replacementPresentation.message)
        }
    }

    private var proxyEnabledRow: some View {
        SettingsRow(label: PreferencesModel.Row.useFailoverProxy.label(settings: settings),
                    subtitle: settings.proxy_enabled_detail_text) {
            Toggle("", isOn: Binding(
                get: { settings.proxy_enabled },
                set: { enabled in
                    guard enabled != settings.proxy_enabled else { return }
                    submit(FailoverModel.proxyEnabledIntent(enabled))
                }))
                .labelsHidden()
                .toggleStyle(InkSwitchStyle())
        }
        .accessibilityLabel(Copy.useFailoverProxy)
        .accessibilityValue(settings.proxy_enabled_detail_text)
    }

    private var advancedDisclosureRow: some View {
        Button {
            advancedExpanded.toggle()
        } label: {
            HStack(spacing: Grid.gap) {
                Text(verbatim: PreferencesModel.Row.advancedProxyControls.label(settings: settings))
                    .font(Face.body)
                    .foregroundStyle(tone.text)
                Spacer(minLength: Grid.gap)
                Image(systemName: "chevron.right")
                    .font(Face.secondary)
                    .foregroundStyle(tone.text3)
                    .rotationEffect(.degrees(advancedExpanded ? 90 : 0))
            }
            .padding(.horizontal, Grid.inset)
            .frame(height: Grid.accountsRow)
            .contentShape(Rectangle())
        }
        .buttonStyle(.plain)
        .accessibilityLabel(Copy.advancedProxyControls)
        .accessibilityValue(advancedExpanded ? "Expanded" : "Collapsed")
    }

    private var serviceRow: some View {
        SettingsRow(label: PreferencesModel.Row.proxyServiceStatus.label(settings: settings)) {
            HStack(alignment: .center, spacing: Grid.noticePadding) {
                Text(verbatim: settings.proxy_service_detail_text)
                    .font(Face.secondary)
                    .foregroundStyle(tone.text3)
                    .lineLimit(1)
                    .truncationMode(.tail)
                ForEach(FailoverModel.serviceActions(settings)) { action in
                    SecondaryButton(title: action.title, enabled: action.enabled) { perform(action) }
                        .accessibilityLabel(action.title)
                }
            }
            .frame(maxWidth: .infinity, alignment: .trailing)
        }
        .accessibilityLabel(Copy.factStatus)
        .accessibilityValue(settings.proxy_service_detail_text)
    }

    private var routingRow: some View {
        SettingsRow(label: PreferencesModel.Row.codexRouting.label(settings: settings)) {
            HStack(alignment: .center, spacing: Grid.noticePadding) {
                Text(verbatim: FailoverModel.routingStateText(settings.codex_routing_state))
                    .font(Face.secondary)
                    .foregroundStyle(tone.text3)
                Toggle("", isOn: Binding(
                    get: { settings.codex_routing_state == .on },
                    set: { enabled in route(enabled) }))
                    .labelsHidden()
                    .toggleStyle(InkSwitchStyle())
                    .disabled(routingAction == nil)
            }
            .frame(maxWidth: .infinity, alignment: .trailing)
        }
        .accessibilityLabel(Copy.codexRouting)
        .accessibilityValue(FailoverModel.routingStateText(settings.codex_routing_state))
    }

    private var routingAction: FailoverModel.LifecycleAction? {
        FailoverModel.routingActions(settings).first
    }

    private func route(_ enabled: Bool) {
        guard enabled != (settings.codex_routing_state == .on), let routingAction else { return }
        perform(routingAction)
    }

    private var clientPresentation: ProxyConfirmationGate.Pending {
        confirmation.pending?.kind == .clientQuiescence
            ? confirmation.pending!
            : ProxyConfirmationGate.Pending(kind: .clientQuiescence, title: Copy.clientQuiescenceTitle,
                                             message: Copy.clientQuiescenceMessage, confirmTitle: Copy.repairProxyService,
                                             intent: .repair_proxy_service)
    }

    private var replacementPresentation: ProxyConfirmationGate.Pending {
        confirmation.pending?.kind == .replaceRouting
            ? confirmation.pending!
            : ProxyConfirmationGate.Pending(kind: .replaceRouting, title: Copy.replaceRoutingTitle,
                                             message: Copy.replaceRoutingMessage, confirmTitle: Copy.replaceCodexRouting,
                                             intent: .enable_codex_routing(replace_conflicting: true))
    }

    private func presented(_ kind: ProxyConfirmationGate.Kind) -> Binding<Bool> {
        Binding(get: { confirmation.pending?.kind == kind },
                set: { shown in if !shown { confirmation.cancel(kind) } })
    }

    private func perform(_ action: FailoverModel.LifecycleAction) {
        if let intent = confirmation.request(action) { submit(intent) }
    }

    private func confirm(_ kind: ProxyConfirmationGate.Kind) {
        if let intent = confirmation.confirm(kind) { submit(intent) }
    }
}
