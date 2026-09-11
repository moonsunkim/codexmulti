import SwiftUI







struct AccountDetail: View {
    let usage: [UsageRow]
    let inspector: Inspector
    @Environment(\.tone) private var tone

    var body: some View {
        VStack(alignment: .leading, spacing: Grid.panelSectionGap) {
            if inspector.attention {
                Text(verbatim: inspector.attention_text)
                    .font(Face.body)
                    .foregroundStyle(tone.text)
                    .fixedSize(horizontal: false, vertical: true)
            }
            if usage.isEmpty {
                Text(verbatim: inspector.no_usage_text)
                    .font(Face.secondary)
                    .foregroundStyle(tone.text3)
                    .fixedSize(horizontal: false, vertical: true)
            }
            FactGrid(facts: AccountsModel.facts(inspector, usage: usage))
            if inspector.has_credit_note {
                Text(verbatim: inspector.credit_note)
                    .font(Face.secondary)
                    .foregroundStyle(tone.text3)
                    .fixedSize(horizontal: false, vertical: true)
            }
        }
        .padding(.leading, Grid.panelPadding)
        .padding(.trailing, Grid.panelTrailing)
        .padding(.vertical, Grid.panelVertical)
        .frame(maxWidth: .infinity, alignment: .leading)
    }
}



struct FactGrid: View {
    let facts: [AccountsModel.Fact]
    @Environment(\.tone) private var tone

    private static let columns = 3

    var body: some View {
        VStack(alignment: .leading, spacing: Grid.factRowGap) {
            ForEach(Array(stride(from: 0, to: facts.count, by: Self.columns)), id: \.self) { start in
                HStack(alignment: .top, spacing: Grid.gap) {
                    ForEach(0..<Self.columns, id: \.self) { column in
                        let index = start + column
                        Group {
                            if index < facts.count {
                                FactCell(fact: facts[index])
                            } else {
                                Color.clear.frame(height: 1)
                            }
                        }
                        .frame(maxWidth: column == Self.columns - 1 ? Grid.usage : .infinity, alignment: .leading)
                        .frame(width: column == Self.columns - 1 ? Grid.usage : nil, alignment: .leading)
                    }
                }
            }
        }
    }
}

struct FactCell: View {
    let fact: AccountsModel.Fact
    @Environment(\.tone) private var tone
    @Environment(\.submit) private var submit

    var body: some View {
        VStack(alignment: .leading, spacing: Grid.factLabelGap) {
            Text(verbatim: fact.label).font(Face.factLabel).foregroundStyle(tone.text3)
            HStack(spacing: Grid.bandGap) {
                Text(verbatim: fact.applies ? fact.value : Copy.notApplicable)
                    .font(Face.factValue)
                    .foregroundStyle(fact.applies ? tone.text : tone.text3)
                    .lineLimit(1)
                    .truncationMode(.tail)
                if let action = fact.action {
                    SecondaryButton(title: action.label) { submit(action.intent) }
                        .accessibilityLabel(action.label)
                }
            }
            if fact.applies && !fact.source.isEmpty {
                Text(verbatim: fact.source)
                    .font(Face.factLabel)
                    .foregroundStyle(tone.text3)
                    .lineLimit(1)
                    .truncationMode(.tail)
            }
        }
        .accessibilityElement(children: .ignore)
        .accessibilityLabel(fact.label)
        .accessibilityValue([fact.applies ? fact.value : Copy.notApplicable, fact.action?.label]
            .compactMap { $0 }.joined(separator: Copy.statusSeparator))
    }
}
