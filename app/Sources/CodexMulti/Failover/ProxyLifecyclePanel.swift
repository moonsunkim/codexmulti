import SwiftUI

struct ProxyLifecyclePanel: View {
    let settings: SettingsView
    init(settings: SettingsView) { self.settings = settings }
    init(view: ViewState) { self.settings = view.settings }
    @Environment(\.submit) private var submit
    @State private var confirmingReplacement = false

    var body: some View {
        Container {
            SettingsRow(label: PreferencesModel.Row.useFailoverProxy.label(settings: settings),
                        subtitle: settings.proxy_enabled_detail_text) {
                HStack(spacing: Grid.noticePadding) {
                    if settings.proxy_enabled && settings.proxy_service_state == .unreachable {
                        SecondaryButton(title: Copy.retry, enabled: settings.proxy_service_can_repair) {
                            submit(.set_proxy_enabled(on: true))
                        }
                    }
                    Toggle("", isOn: Binding(
                        get: { settings.proxy_enabled },
                        set: { enabled in
                            guard enabled != settings.proxy_enabled else { return }
                            if enabled && settings.codex_routing_state == .conflicting {
                                confirmingReplacement = true
                            } else {
                                submit(.set_proxy_enabled(on: enabled))
                            }
                        }))
                        .labelsHidden()
                        .toggleStyle(InkSwitchStyle())
                }
            }
            .accessibilityLabel(Copy.useFailoverProxy)
            .accessibilityValue(settings.proxy_enabled_detail_text)
        }
        .confirmationDialog(Copy.replaceRoutingTitle, isPresented: $confirmingReplacement,
                            titleVisibility: .visible) {
            Button(Copy.replaceCodexRouting, role: .destructive) {
                submit(.enable_codex_routing(replace_conflicting: true))
            }
            Button(Copy.cancel, role: .cancel) {}
        } message: {
            Text(verbatim: Copy.replaceRoutingMessage)
        }
    }
}
