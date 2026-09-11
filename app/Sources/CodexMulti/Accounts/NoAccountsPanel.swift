import SwiftUI



struct NoAccountsPanel: View {
    let title: String
    let bodyText: String?
    let actionTitle: String?
    let showsButtons: Bool
    let canManage: Bool
    @Environment(\.tone) private var tone
    @Environment(\.submit) private var submit

    init(title: String, bodyText: String? = nil, actionTitle: String? = nil,
         showsButtons: Bool, canManage: Bool) {
        self.title = title
        self.bodyText = bodyText
        self.actionTitle = actionTitle
        self.showsButtons = showsButtons
        self.canManage = canManage
    }

    var body: some View {
        VStack(spacing: Grid.noticePadding) {
            Text(verbatim: title).font(Face.sheetTitle).foregroundStyle(tone.text)
            if showsButtons, let bodyText, let actionTitle {
                Text(verbatim: bodyText)
                    .font(Face.secondary)
                    .foregroundStyle(tone.text3)
                    .multilineTextAlignment(.center)
                    .fixedSize(horizontal: false, vertical: true)
                PrimaryButton(title: actionTitle, enabled: canManage) { submit(.begin_add_account) }
                    .padding(.top, 4)
            }
        }
        .padding(Grid.emptyStatePadding)
        .frame(width: Grid.emptyStateWidth)
        .background(RoundedRectangle(cornerRadius: Grid.containerRadius, style: .continuous).fill(tone.surface))
    }
}



struct EmptyAccountsPage: View {
    let projection: Projection

    var body: some View {
        NoAccountsPanel(
            title: projection.view.no_accounts_title_text,
            bodyText: projection.view.no_accounts_body_text,
            actionTitle: projection.view.no_accounts_action_text,
            showsButtons: true,
            canManage: projection.shell.can_manage_accounts
        )
        .frame(maxWidth: .infinity, maxHeight: .infinity, alignment: .center)
    }
}
