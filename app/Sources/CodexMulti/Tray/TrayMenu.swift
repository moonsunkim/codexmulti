import SwiftUI













struct TrayMenu: View {
    let store: CoreStore
    let submit: IntentSink

    var body: some View {
        if let projection = store.tray.projection {
            ForEach(TrayModel.entries(projection.view)) { entry in
                switch entry {
                case .separator:
                    Divider()
                case .info(_, let label):
                    Text(verbatim: label)
                case .action(let action):
                    TrayActionButton(action: action, submit: submit)
                case .section(let section):

                    Section {
                        ForEach(section.entries) { inner in
                            TraySectionLine(entry: inner, submit: submit)
                        }
                    }
                case .account(let account):
                    TrayAccountItem(account: account, submit: submit)
                }
            }
        } else {
            Text(verbatim: Copy.starting)
            Divider()

            Button { LifecycleLog.shared?.note(.trayQuit); QuitRequest.post() } label: { Text(verbatim: Copy.quit) }
                .keyboardShortcut("q")
        }
    }
}





struct TrayLabel: View {
    let store: CoreStore
    @Environment(\.openWindow) private var openWindow

    var body: some View {
        Group {
            if let image = TrayIcon.image() {
                Image(nsImage: image)
            }
        }
            .help(TrayModel.helpText(store.projection) ?? "")
            .onAppear {
                WindowPresenter.shared.open = { openWindow(id: SettingsWindowScene.id) }
            }
    }
}


private struct TraySectionLine: View {
    let entry: TrayModel.Entry
    let submit: IntentSink

    var body: some View {
        switch entry {
        case .account(let account):
            TrayAccountItem(account: account, submit: submit)
        case .action(let action):
            TrayActionButton(action: action, submit: submit)
        case .info(_, let label):
            Text(verbatim: label)
        case .separator:
            Divider()
        case .section(let section):


            ForEach(section.entries) { inner in
                TraySectionLine(entry: inner, submit: submit)
            }
        }
    }
}


private struct TrayActionButton: View {
    let action: TrayModel.Action
    let submit: IntentSink

    var body: some View {
        if action.isQuit {
            button.keyboardShortcut("q")
        } else if action.intent == .open_details {
            button.keyboardShortcut(",", modifiers: .command)
        } else {
            button
        }
    }

    private var button: some View {
        Button { submit(action.intent) } label: { Text(verbatim: action.label) }
            .disabled(!action.enabled)
    }
}






private struct TrayAccountItem: View {
    let account: TrayModel.Account
    let submit: IntentSink

    var body: some View {
        if let submenu = account.submenu {
            Menu {
                Text(verbatim: submenu.summary)
                Text(verbatim: submenu.usage)
                Text(verbatim: submenu.updated)
                Divider()
                Button { submit(submenu.refresh) } label: { Text(verbatim: submenu.refreshLabel) }
                    .disabled(!submenu.canRefresh)
                if let failover = submenu.failover {
                    switch failover {
                    case .active(let label):
                        Toggle(isOn: .constant(true)) { Text(verbatim: label) }
                            .disabled(true)
                    case .switchable(let label, let intent):
                        Button { submit(intent) } label: { Text(verbatim: label) }
                    case .info(let label):
                        Text(verbatim: label)
                    }
                }
                Divider()
                Button { submit(submenu.open) } label: { Text(verbatim: submenu.openLabel) }
            } label: {
                title
            }
            .disabled(!account.enabled)
        } else {
            Button { submit(.open_account(account_id: account.accountID)) } label: { title }
                .disabled(!account.enabled)
        }
    }

    @ViewBuilder private var title: some View {
        if account.isCursor {
            Label { titleText } icon: { Image(systemName: "checkmark") }
        } else {
            titleText
        }
    }

    private var titleText: Text {
        if let split = account.split {
            Text(verbatim: split.label) + Text(verbatim: split.suffix).foregroundStyle(.secondary)
        } else {
            Text(verbatim: account.title)
        }
    }
}
