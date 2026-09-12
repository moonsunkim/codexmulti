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
        OnboardingChecklist(projection: projection, compact: false)
        .frame(maxWidth: .infinity, maxHeight: .infinity, alignment: .center)
    }
}


enum OnboardingChecklistModel {
    static func intent(_ action: OnboardingNextAction?) -> Intent? {
        guard let action else { return nil }
        switch action.kind {
        case .add_account: return .begin_add_account
        case .install_proxy_service: return .install_proxy_service
        case .enable_codex_routing: return .enable_codex_routing(replace_conflicting: action.replace_conflicting)
        }
    }
}


struct OnboardingChecklist: View {
    let projection: Projection
    let compact: Bool
    @Environment(\.tone) private var tone
    @Environment(\.submit) private var submit

    var body: some View {
        Group {
            if compact { compactBody } else { cardBody }
        }
        .accessibilityElement(children: .contain)
    }

    private var compactBody: some View {
        HStack(spacing: Grid.gap) {
            ForEach(Array(projection.view.onboarding_steps.enumerated()), id: \.element.kind) { index, step in
                stepLabel(step, compact: true)
                if index < projection.view.onboarding_steps.count - 1 {
                    Image(systemName: "chevron.right")
                        .font(.system(size: 9, weight: .semibold))
                        .foregroundStyle(tone.text3)
                        .accessibilityHidden(true)
                }
            }
            Spacer(minLength: 0)
            actionButton
        }
        .padding(.horizontal, Grid.inset)
        .frame(minHeight: Grid.accountsRow)
        .background(RoundedRectangle(cornerRadius: Grid.noticeRadius, style: .continuous).fill(tone.raised))
    }

    private var cardBody: some View {
        VStack(spacing: 0) {
            ForEach(Array(projection.view.onboarding_steps.enumerated()), id: \.element.kind) { index, step in
                HStack(spacing: Grid.noticePadding) {
                    stepLabel(step, compact: false)
                    Spacer(minLength: Grid.gap)
                    if projection.view.onboarding_next_action?.kind == step.kind { actionButton }
                }
                .frame(minHeight: Grid.emptyLine)
                if index < projection.view.onboarding_steps.count - 1 { Hairline() }
            }
        }
        .padding(Grid.inset)
        .frame(width: Grid.emptyStateWidth)
        .background(RoundedRectangle(cornerRadius: Grid.containerRadius, style: .continuous).fill(tone.surface))
    }

    private func stepLabel(_ step: OnboardingStepView, compact: Bool) -> some View {
        HStack(spacing: Grid.settingsLabelGap) {
            Image(systemName: step.completed ? "checkmark.circle.fill" : "circle")
                .font(.system(size: compact ? 13 : 16, weight: .semibold))
                .foregroundStyle(step.completed ? tone.point : tone.text3)
                .accessibilityHidden(true)
            Text(verbatim: step.title)
                .font(compact ? Face.notice : Face.body)
                .foregroundStyle(step.completed ? tone.text3 : tone.text)
                .fixedSize(horizontal: true, vertical: false)
        }
    }

    @ViewBuilder private var actionButton: some View {
        if let action = projection.view.onboarding_next_action,
           let intent = OnboardingChecklistModel.intent(action) {
            PrimaryButton(title: action.label, enabled: action.enabled) { submit(intent) }
        }
    }
}
