import AppKit
import SwiftUI




enum Grid {
    static let width: CGFloat = 1000
    static let height: CGFloat = 680
    static let minWidth: CGFloat = 900
    static let minHeight: CGFloat = 580
    static let windowRadius: CGFloat = 28
    static let containerRadius: CGFloat = 16
    static let panelRadius: CGFloat = 12
    static let hoverRadius: CGFloat = 10
    static let noticeRadius: CGFloat = 10
    static let L: CGFloat = 24
    static let inset: CGFloat = 16
    static let gap: CGFloat = 16
    static let band: CGFloat = 52
    static let contentTop: CGFloat = 20
    static let contentBottom: CGFloat = 24
    static let betweenContainers: CGFloat = 24
    static let accountsRow: CGFloat = 56
    static let emptyLine: CGFloat = 44
    static let usage: CGFloat = 280
    static let menu: CGFloat = 28
    static let menuPillHeight: CGFloat = 24
    static let nameMinWidth: CGFloat = 300
    static let panelInset: CGFloat = 4
    static let panelPadding: CGFloat = 12
    static let panelTrailing: CGFloat = 12 + 28 + 16
    static let panelVertical: CGFloat = 14
    static let panelSectionGap: CGFloat = 16
    static let factRowGap: CGFloat = 14
    static let factLabelGap: CGFloat = 3
    static let barHeight: CGFloat = 3
    static let captionToBar: CGFloat = 7
    static let nameToStatus: CGFloat = 4
    static let pillHeight: CGFloat = 32
    static let bandGap: CGFloat = 8
    static let segmentWidth: CGFloat = 104
    static let segmentHeight: CGFloat = 26
    static let segmentPadding: CGFloat = 3
    static let menuWidth: CGFloat = 220
    static let menuPadding: CGFloat = 6
    static let menuGroupGap: CGFloat = 6
    static let noticePadding: CGFloat = 12
    static let noticeBelowBand: CGFloat = 12
    static let bannerToContainer: CGFloat = 16
    static let emptyStateWidth: CGFloat = 420
    static let emptyStatePadding: CGFloat = 24



    static let failoverRow: CGFloat = 52
    static let settingsLabelGap: CGFloat = 8
    static let planGap: CGFloat = 8
    static let settingsControlWidth: CGFloat = 600
    static let languageMenuWidth: CGFloat = 240
    static let appearanceSegmentWidth: CGFloat = 68
    static let autoRefreshSegmentWidth: CGFloat = 62
    static let settingsSegmentHeight: CGFloat = 24
    static let settingsSegmentPadding: CGFloat = 2
    static let badgeGap: CGFloat = 8
    static let detailGap: CGFloat = 12
    static let badgePaddingHorizontal: CGFloat = 8
    static let badgePaddingVertical: CGFloat = 2
    static let fieldHeight: CGFloat = 28
    static let fieldRadius: CGFloat = 8
    static let fieldPadding: CGFloat = 10
    static let fieldGap: CGFloat = 8
}





struct BarTone: Equatable, Sendable {
    var meter: Color
    var meterInk: Color




    static let middle = BarTone(
        meter: Color(red: 0x5E / 255, green: 0x5B / 255, blue: 0x57 / 255),
        meterInk: Color(red: 0x5E / 255, green: 0x5B / 255, blue: 0x57 / 255))

    static let calm = BarTone(
        meter: Color(red: 0x8F / 255, green: 0x8B / 255, blue: 0x85 / 255),
        meterInk: Color(red: 0x8F / 255, green: 0x8B / 255, blue: 0x85 / 255))

    static let firm = BarTone(meter: .black.opacity(0.60), meterInk: .black.opacity(0.60))
}







enum PaneMaterial: Equatable, Sendable {
    case thin, ultraThin

    var material: Material {
        switch self {
        case .thin: .thinMaterial
        case .ultraThin: .ultraThinMaterial
        }
    }
}



struct Tone: Sendable {
    var text: Color
    var text2: Color
    var text3: Color
    var surface: Color
    var raised: Color
    var hover: Color
    var pill: Color
    var pillHover: Color
    var segment: Color
    var hairline: Color
    var track: Color
    var bar: BarTone
    var paneMaterial: PaneMaterial


    var tint: Color


    var bandTint: Color
    var rim: Color





    var capsule: Color
    var fill: Color
    var onFill: Color
    var destructive: Color
    var point: Color


    var badge: Color
    var badgeMuted: Color
    var badgePoint: Color
    var opaqueGround: Color
    var opaqueFloat: Color

    var meter: Color { bar.meter }
    var meterInk: Color { bar.meterInk }


    var controlOn: Color { text }


    static let exhaustedOpacity: Double = 0.6

    static let disabledOpacity: Double = 0.5

    static let light = Tone(
        text: .black.opacity(0.86),
        text2: .black.opacity(0.60),
        text3: .black.opacity(0.46),
        surface: .black.opacity(0.04),
        raised: .black.opacity(0.06),
        hover: .black.opacity(0.03),
        pill: .black.opacity(0.06),
        pillHover: .black.opacity(0.10),
        segment: .white.opacity(0.80),
        hairline: .black.opacity(0.10),
        track: .black.opacity(0.12),
        bar: .middle,
        paneMaterial: .ultraThin,
        tint: Color(red: 0.97, green: 0.965, blue: 0.955).opacity(0.83),
        bandTint: Color(red: 0.97, green: 0.965, blue: 0.955).opacity(0.35),
        rim: .white.opacity(0.35),
        capsule: Color(red: 223 / 255, green: 220 / 255, blue: 216 / 255).opacity(0.31),
        fill: .black.opacity(0.86),
        onFill: .white,
        destructive: Color(red: 0xD9 / 255, green: 0x30 / 255, blue: 0x25 / 255),
        point: Color(red: 0x2F / 255, green: 0x6F / 255, blue: 0xE0 / 255),
        badge: .black.opacity(0.08),
        badgeMuted: .black.opacity(0.05),
        badgePoint: Color(red: 0x2F / 255, green: 0x6F / 255, blue: 0xE0 / 255).opacity(0.12),
        opaqueGround: Color(red: 0xF5 / 255, green: 0xF3 / 255, blue: 0xEE / 255),
        opaqueFloat: .white)

    static let dark = Tone(
        text: .white.opacity(0.94), text2: .white.opacity(0.68), text3: .white.opacity(0.46),
        surface: .white.opacity(0.04), raised: .white.opacity(0.06), hover: .white.opacity(0.04),
        pill: .white.opacity(0.10), pillHover: .white.opacity(0.16), segment: .white.opacity(0.18),
        hairline: .white.opacity(0.10), track: .white.opacity(0.14),
        bar: BarTone(meter: .white.opacity(0.88), meterInk: .white.opacity(0.94)),
        paneMaterial: .thin,
        tint: Color(red: 0x17 / 255, green: 0x17 / 255, blue: 0x1A / 255).opacity(0.86),
        bandTint: Color(red: 0x17 / 255, green: 0x17 / 255, blue: 0x1A / 255).opacity(0.35),
        rim: .white.opacity(0.12), capsule: .white.opacity(0.10), fill: .white.opacity(0.94),
        onFill: Color(red: 17 / 255, green: 17 / 255, blue: 17 / 255),
        destructive: Color(red: 1, green: 107 / 255, blue: 107 / 255),
        point: Color(red: 108 / 255, green: 168 / 255, blue: 1),
        badge: .white.opacity(0.08), badgeMuted: .white.opacity(0.05),
        badgePoint: Color(red: 108 / 255, green: 168 / 255, blue: 1).opacity(0.12),
        opaqueGround: Color(red: 0x17 / 255, green: 0x17 / 255, blue: 0x1A / 255),
        opaqueFloat: Color(red: 0x24 / 255, green: 0x24 / 255, blue: 0x28 / 255))

    static let darkHighContrast: Tone = {
        var tone = dark
        tone.text2 = .white.opacity(0.82)
        tone.text3 = .white.opacity(0.66)
        tone.hairline = .white.opacity(0.22)
        tone.surface = .white.opacity(0.09)
        tone.raised = .white.opacity(0.12)
        tone.pill = .white.opacity(0.20)
        tone.badge = .white.opacity(0.16)
        tone.badgeMuted = .white.opacity(0.10)
        tone.badgePoint = tone.point.opacity(0.20)
        return tone
    }()


    static let lightHighContrast: Tone = {
        var tone = light
        tone.text2 = .black.opacity(0.72)
        tone.text3 = .black.opacity(0.56)
        tone.bar = BarTone(meter: tone.text2, meterInk: tone.text2)
        tone.hairline = .black.opacity(0.22)
        tone.surface = .black.opacity(0.09)
        tone.raised = .black.opacity(0.12)
        tone.pill = .black.opacity(0.16)
        tone.badge = .black.opacity(0.16)
        tone.badgeMuted = .black.opacity(0.10)
        tone.badgePoint = tone.point.opacity(0.20)
        return tone
    }()
}





struct ResolvedAppearance {
    let name: NSAppearance.Name?
    let tone: Tone
}

enum AppearanceResolver {
    static func preferredScheme(_ preference: Appearance) -> ColorScheme? {
        switch preference {
        case .system: nil
        case .light: .light
        case .dark: .dark
        }
    }

    static func tone(for scheme: ColorScheme, contrast: ColorSchemeContrast) -> Tone {
        resolve(.system, system: scheme, contrast: contrast).tone
    }

    static func resolve(_ preference: Appearance, system: ColorScheme,
                        contrast: ColorSchemeContrast) -> ResolvedAppearance {
        let name: NSAppearance.Name?
        let scheme: ColorScheme
        switch preference {
        case .system:





            name = nil
            scheme = system
        case .light:
            name = .aqua
            scheme = .light
        case .dark:
            name = .darkAqua
            scheme = .dark
        }
        let tone: Tone
        switch (scheme, contrast) {
        case (.dark, .increased): tone = .darkHighContrast
        case (.dark, _): tone = .dark
        case (_, .increased): tone = .lightHighContrast
        case (_, _): tone = .light
        }
        return ResolvedAppearance(name: name, tone: tone)
    }
}

@MainActor
final class SystemAppearance: ObservableObject {
    @Published private(set) var scheme = SystemAppearance.current
    private var observation: NSKeyValueObservation?

    init() {
        observation = NSApp?.observe(\.effectiveAppearance, options: [.new]) { [weak self] _, _ in
            Task { @MainActor [weak self] in
                guard let self else { return }
                let current = SystemAppearance.current
                if self.scheme != current { self.scheme = current }
            }
        }
    }

    private static var current: ColorScheme {
        NSApp?.effectiveAppearance.bestMatch(from: [.aqua, .darkAqua]) == .darkAqua ? .dark : .light
    }
}


enum Face {
    static let name = Font.system(size: 14, weight: .semibold)
    static let body = Font.system(size: 14, weight: .regular)
    static let secondary = Font.system(size: 12.5, weight: .regular)
    static let secondaryStrong = Font.system(size: 12.5, weight: .semibold)
    static let numeral = Font.system(size: 13, weight: .semibold).monospacedDigit()


    static let badgePointSize: CGFloat = 11
    static let badge = Font.system(size: badgePointSize, weight: .semibold)
    static let factLabel = Font.system(size: 11, weight: .regular)
    static let factValue = Font.system(size: 13, weight: .regular)
    static let band = Font.system(size: 13, weight: .medium)
    static let bandStrong = Font.system(size: 13, weight: .semibold)
    static let menu = Font.system(size: 13, weight: .regular)
    static let sheetTitle = Font.system(size: 15, weight: .semibold)
    static let sheetBody = Font.system(size: 13, weight: .regular)
    static let notice = Font.system(size: 12.5, weight: .regular)
}



struct InkSwitchStyle: ToggleStyle {
    @Environment(\.tone) private var tone

    private let width: CGFloat = 32
    private let height: CGFloat = 18
    private let knob: CGFloat = 14
    private let inset: CGFloat = 2

    func makeBody(configuration: Configuration) -> some View {
        Button { configuration.isOn.toggle() } label: {
            ZStack(alignment: .leading) {
                Capsule()
                    .fill(configuration.isOn ? tone.controlOn : tone.track)
                    .frame(width: width, height: height)
                Circle()
                    .fill(configuration.isOn ? tone.onFill : Color.white)
                    .frame(width: knob, height: knob)
                    .offset(x: configuration.isOn ? width - knob - inset : inset)
            }
            .frame(width: width, height: height)
            .contentShape(Capsule())
        }
        .buttonStyle(.plain)
        .focusEffectDisabled()
    }
}


enum Motion {
    static func snappy(_ reduce: Bool) -> Animation? { reduce ? nil : .snappy(duration: 0.22) }
    static func crossfade(_ reduce: Bool) -> Animation? { reduce ? nil : .easeOut(duration: 0.15) }
    static func hoverIn(_ reduce: Bool) -> Animation? { reduce ? nil : .easeOut(duration: 0.10) }
    static func hoverOut(_ reduce: Bool) -> Animation? { reduce ? nil : .easeOut(duration: 0.15) }
}

private struct ToneKey: EnvironmentKey { static let defaultValue = Tone.light }

extension EnvironmentValues {
    var tone: Tone {
        get { self[ToneKey.self] }
        set { self[ToneKey.self] = newValue }
    }
}
