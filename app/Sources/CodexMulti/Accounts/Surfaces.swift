import SwiftUI


struct Container<Content: View>: View {
    @ViewBuilder let content: () -> Content
    @Environment(\.tone) private var tone

    var body: some View {
        VStack(spacing: 0) { content() }
            .frame(maxWidth: .infinity)
            .background(RoundedRectangle(cornerRadius: Grid.containerRadius, style: .continuous).fill(tone.surface))
    }
}


struct Hairline: View {
    @Environment(\.tone) private var tone

    var body: some View {
        Rectangle().fill(tone.hairline).frame(height: 0.5).padding(.horizontal, Grid.inset)
    }
}


struct Bar: View {
    let fraction: Double
    @Environment(\.tone) private var tone

    var body: some View {
        GeometryReader { geometry in
            ZStack(alignment: .leading) {
                Capsule().fill(tone.track)
                Capsule().fill(tone.meter).frame(width: max(0, geometry.size.width * min(max(fraction, 0), 1)))
            }
        }
        .frame(height: Grid.barHeight)
        .accessibilityLabel(Copy.usageBarAccessibility)
    }
}




struct NoticeSlot: View {
    let notice: Notice
    @Environment(\.tone) private var tone
    @Environment(\.submit) private var submit

    var body: some View {
        HStack(alignment: .center, spacing: Grid.noticePadding) {
            Text(verbatim: notice.text)
                .font(Face.notice)
                .foregroundStyle(tone.text2)
                .fixedSize(horizontal: false, vertical: true)
                .frame(maxWidth: .infinity, alignment: .leading)
            Button { submit(.dismiss_notice) } label: {
                Image(systemName: "xmark")
                    .font(.system(size: 11, weight: .semibold))
                    .foregroundStyle(tone.text3)
                    .frame(width: 24, height: 24)
                    .contentShape(Rectangle())
            }
            .buttonStyle(.plain)
            .accessibilityLabel(Copy.dismissNotice)
        }
        .padding(Grid.noticePadding)
        .background(RoundedRectangle(cornerRadius: Grid.noticeRadius, style: .continuous).fill(tone.raised))
        .accessibilityElement(children: .contain)
        .accessibilityAddTraits(.updatesFrequently)
    }
}




struct ProxyBanner: View {
    let text: String
    let showsRetry: Bool
    let canRetry: Bool
    @Environment(\.tone) private var tone
    @Environment(\.submit) private var submit

    var body: some View {
        HStack(alignment: .center, spacing: Grid.noticePadding) {
            Text(verbatim: text)
                .font(Face.notice)
                .foregroundStyle(tone.text2)
                .fixedSize(horizontal: false, vertical: true)
                .frame(maxWidth: .infinity, alignment: .leading)
            if showsRetry {
                SecondaryButton(title: Copy.retry, enabled: canRetry) { submit(.refresh_proxy_status) }
            }
        }
        .padding(Grid.noticePadding)
        .background(RoundedRectangle(cornerRadius: Grid.noticeRadius, style: .continuous).fill(tone.raised))
    }
}


struct SecondaryButton: View {
    let title: String
    var enabled = true
    let action: () -> Void
    @Environment(\.tone) private var tone
    @State private var hovering = false

    var body: some View {
        Button(action: action) {
            Text(verbatim: title)
                .font(Face.bandStrong)
                .foregroundStyle(tone.text)
                .padding(.horizontal, 14)
                .frame(height: 28)
                .background(Capsule().fill(hovering && enabled ? tone.pillHover : tone.pill))
                .contentShape(Capsule())
                .opacity(enabled ? 1 : Tone.disabledOpacity)
        }
        .buttonStyle(.plain)
        .disabled(!enabled)
        .onHover { hovering = $0 }
    }
}


struct PrimaryButton: View {
    let title: String
    var enabled = true
    let action: () -> Void
    @Environment(\.tone) private var tone

    var body: some View {
        Button(action: action) {
            Text(verbatim: title)
                .font(Face.bandStrong)
                .foregroundStyle(tone.onFill)
                .padding(.horizontal, 14)
                .frame(height: 28)
                .background(Capsule().fill(tone.fill))
                .contentShape(Capsule())
                .opacity(enabled ? 1 : Tone.disabledOpacity)
        }
        .buttonStyle(.plain)
        .disabled(!enabled)
    }
}
