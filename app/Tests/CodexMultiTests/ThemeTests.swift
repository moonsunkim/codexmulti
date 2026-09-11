import AppKit
import SwiftUI
import XCTest
@testable import CodexMulti








@MainActor
final class ThemeTests: XCTestCase {



    private let materialOverWhite: RGB = (236.0 / 255, 237.0 / 255, 237.0 / 255)




    func testPaneIsUltraThinUnderALightTintThatKeepsInkContrast() {
        XCTAssertEqual(Tone.light.paneMaterial, .ultraThin)
        XCTAssertEqual(alpha(Tone.light.tint), 0.83, accuracy: 0.0005,
                       "Light window ground stays light over a black desktop/editor")
        XCTAssertEqual(alpha(Tone.light.bandTint), 0.35, accuracy: 0.005,
                       "the band stays translucent relative to in-app content")
        XCTAssertEqual(alpha(Tone.light.text3), 0.46, accuracy: 0.005, "muted ink")
        let pane = over(Tone.light.tint, materialOverWhite)
        XCTAssertGreaterThanOrEqual(contrast(over(Tone.light.text, pane), pane), 4.5, "primary ink on the pane")
        XCTAssertGreaterThanOrEqual(contrast(over(Tone.light.text3, pane), pane), 3.0, "muted ink on the pane \(hex(pane))")
        let container = over(Tone.light.surface, pane)
        XCTAssertGreaterThanOrEqual(contrast(over(Tone.light.text3, container), container), 3.0, "muted ink on a container \(hex(container))")
        XCTAssertGreaterThanOrEqual(luminance(pane) - luminance(container), 0.03, "a container still separates from the pane")
        XCTAssertLessThan(pane.r - pane.b, 8.0 / 255, "the pane is not the old beige (r − b was 10 levels)")
    }










    func testBandCapsuleWashReproducesTheInactiveGlassOnBothMeasuredPanes() {
        let capsule = Tone.light.capsule
        XCTAssertEqual(alpha(capsule), 0.31, accuracy: 0.005, "wash opacity")
        let c = sRGB(capsule)
        XCTAssertEqual(c.r * 255, 223, accuracy: 0.6, "warm light grey, r")
        XCTAssertEqual(c.g * 255, 220, accuracy: 0.6, "warm light grey, g")
        XCTAssertEqual(c.b * 255, 216, accuracy: 0.6, "warm light grey, b")
        let whitePane: RGB = (236.0 / 255, 232.0 / 255, 226.0 / 255)
        let onWhite = over(capsule, whitePane)
        XCTAssertEqual(onWhite.r * 255, 232.0, accuracy: 1.5, "over the white-backdrop pane, r \(onWhite.r * 255)")
        XCTAssertEqual(onWhite.g * 255, 228.0, accuracy: 1.5, "over the white-backdrop pane, g \(onWhite.g * 255)")
        XCTAssertEqual(onWhite.b * 255, 223.0, accuracy: 1.5, "over the white-backdrop pane, b \(onWhite.b * 255)")
        let greyPane: RGB = (164.0 / 255, 164.5 / 255, 159.8 / 255)
        let onGrey = over(capsule, greyPane)
        XCTAssertEqual(onGrey.r * 255, 181.8, accuracy: 1.5, "over the grey-backdrop pane, r \(onGrey.r * 255)")
        XCTAssertEqual(onGrey.g * 255, 182.6, accuracy: 1.5, "over the grey-backdrop pane, g \(onGrey.g * 255)")
        XCTAssertEqual(onGrey.b * 255, 177.8, accuracy: 1.5, "over the grey-backdrop pane, b \(onGrey.b * 255)")
        XCTAssertEqual(alpha(Tone.light.segment), 0.80, accuracy: 0.005, "the selected segment stays white 80 %")
    }






    func testBandGlassDefaultsToTheStateIndependentMaterialCapsule() throws {
        XCTAssertEqual(BandGlassStyle.defaultsKey, "BandGlass")
        XCTAssertEqual(BandGlassStyle(defaultsValue: nil), .material)
        XCTAssertEqual(BandGlassStyle(defaultsValue: "material"), .material)
        XCTAssertEqual(BandGlassStyle(defaultsValue: "clear"), .clear, "opt-in")
        XCTAssertEqual(BandGlassStyle(defaultsValue: "regular"), .regular, "opt-in")
        XCTAssertEqual(BandGlassStyle(defaultsValue: " Regular "), .regular, "case and whitespace are forgiven")
        XCTAssertEqual(BandGlassStyle(defaultsValue: "frosted"), .material, "an unknown word is the default")
        XCTAssertEqual(BandGlassStyle(defaultsValue: ""), .material)
        let name = "dev.codexmulti.app.tests.BandGlass"
        let suite = try XCTUnwrap(UserDefaults(suiteName: name))
        suite.removePersistentDomain(forName: name)
        XCTAssertEqual(BandGlassStyle(defaults: suite), .material, "no key → material")
        suite.set("clear", forKey: BandGlassStyle.defaultsKey)
        XCTAssertEqual(BandGlassStyle(defaults: suite), .clear)
        suite.set(7, forKey: BandGlassStyle.defaultsKey)
        XCTAssertEqual(BandGlassStyle(defaults: suite), .material, "a non-string value is the default")
        suite.removePersistentDomain(forName: name)
        if UserDefaults.standard.string(forKey: BandGlassStyle.defaultsKey) == nil {
            XCTAssertEqual(BandGlassStyle.launch, .material, "the launch value with no default written")
            XCTAssertEqual(BandGlass(interactive: true).style, .material, "the band modifier starts from the launch value")
        }


        XCTAssertNil(BandGlassStyle.material.glass(tint: Tone.light.bandTint))
        XCTAssertEqual(BandGlassStyle.clear.glass(tint: Tone.light.bandTint), .clear)
        XCTAssertEqual(BandGlassStyle.regular.glass(tint: Tone.light.bandTint),
                       Glass.regular.tint(Tone.light.bandTint))
        XCTAssertEqual(BandGlassStyle.allCases.map(\.rawValue), ["clear", "regular", "material"])
    }

    func testBarFillClearsTheRailAtTextContrast() {
        let pane = sRGB(Tone.light.opaqueGround)
        let rail = composite(black: 0.12, over: pane)
        let fill = sRGB(BarTone.middle.meter)
        let ratio = contrast(fill, rail)
        XCTAssertGreaterThanOrEqual(ratio, 4.5, "fill \(hex(fill)) over rail \(hex(rail)) = \(String(format: "%.2f", ratio)):1")
        XCTAssertGreaterThanOrEqual(contrast(sRGB(BarTone.middle.meterInk), rail), 4.5, "numerals keep their strength")
        XCTAssertGreaterThan(luminance(rail), luminance(fill), "the fill is the darker of the two")
    }



    func testFilledControlOnStateUsesThePrimaryInkToken() {
        for tone in [Tone.light, Tone.dark, Tone.lightHighContrast, Tone.darkHighContrast] {
            let control = sRGB(tone.controlOn)
            let ink = sRGB(tone.text)
            XCTAssertEqual(control.r, ink.r, accuracy: 0.001)
            XCTAssertEqual(control.g, ink.g, accuracy: 0.001)
            XCTAssertEqual(control.b, ink.b, accuracy: 0.001)
            XCTAssertEqual(alpha(tone.controlOn), alpha(tone.text), accuracy: 0.001)
        }
        let on = sRGB(Tone.light.controlOn)
        let point = sRGB(Tone.light.point)
        XCTAssertNotEqual(on.b - on.r, point.b - point.r, "control fill is neutral ink, not ice-blue status")
    }



    func testDarkPaletteAndSystemContrastMapping() {
        XCTAssertEqual(Tone.dark.paneMaterial, .thin)
        XCTAssertEqual(alpha(Tone.dark.tint), 0.86, accuracy: 0.005,
                       "Dark stays dark over a light desktop, mirroring Light's floor (owner rule, 2026-09-09) instead of becoming a flat slab")
        XCTAssertEqual(alpha(Tone.dark.bandTint), 0.35, accuracy: 0.005,
                       "Dark scrolling content remains visible beneath the band blur")
        XCTAssertEqual(alpha(Tone.dark.text), 0.94, accuracy: 0.005)
        XCTAssertEqual(alpha(Tone.dark.text2), 0.68, accuracy: 0.005)
        XCTAssertEqual(alpha(Tone.dark.text3), 0.46, accuracy: 0.005)
        let ground = sRGB(Tone.dark.opaqueGround)
        XCTAssertEqual(ground.r * 255, 0x17, accuracy: 0.5)
        XCTAssertEqual(ground.g * 255, 0x17, accuracy: 0.5)
        XCTAssertEqual(ground.b * 255, 0x1A, accuracy: 0.5)
        XCTAssertGreaterThan(contrast(over(Tone.dark.text, ground), ground), 4.5)
        let high = AppearanceResolver.resolve(.system, system: .dark, contrast: .increased).tone
        XCTAssertGreaterThan(alpha(high.text3), alpha(Tone.dark.text3))
        XCTAssertGreaterThan(contrast(over(high.text3, ground), ground), 4.5)
        XCTAssertEqual(alpha(AppearanceResolver.resolve(.light, system: .dark, contrast: .standard).tone.text), alpha(Tone.light.text))
        XCTAssertEqual(alpha(AppearanceResolver.resolve(.dark, system: .light, contrast: .standard).tone.text), alpha(Tone.dark.text))
    }



    func testEveryAppearancePreferenceResolvesAConsistentWindowAndTonePair() {
        let light = AppearanceResolver.resolve(.light, system: .dark, contrast: .standard)
        XCTAssertEqual(light.name, .aqua)
        assertSamePalette(light.tone, Tone.light)

        let dark = AppearanceResolver.resolve(.dark, system: .light, contrast: .standard)
        XCTAssertEqual(dark.name, .darkAqua)
        assertSamePalette(dark.tone, Tone.dark)

        let systemLight = AppearanceResolver.resolve(.system, system: .light, contrast: .standard)
        XCTAssertNil(systemLight.name)
        assertSamePalette(systemLight.tone, Tone.light)

        let systemDark = AppearanceResolver.resolve(.system, system: .dark, contrast: .increased)
        XCTAssertNil(systemDark.name)
        assertSamePalette(systemDark.tone, Tone.darkHighContrast)
    }




    func testDarkPaletteUsesTheLightSurfaceAlphaLadderOnANeutralBase() {
        for (name, dark, light) in [
            ("surface", Tone.dark.surface, Tone.light.surface),
            ("raised", Tone.dark.raised, Tone.light.raised),
            ("hairline", Tone.dark.hairline, Tone.light.hairline),
            ("badge", Tone.dark.badge, Tone.light.badge),
            ("badgeMuted", Tone.dark.badgeMuted, Tone.light.badgeMuted),
            ("badgePoint", Tone.dark.badgePoint, Tone.light.badgePoint),
        ] {
            XCTAssertEqual(alpha(dark), alpha(light), accuracy: 0.001, name)
        }
        for (name, dark, light) in [
            ("surface", Tone.darkHighContrast.surface, Tone.lightHighContrast.surface),
            ("raised", Tone.darkHighContrast.raised, Tone.lightHighContrast.raised),
            ("hairline", Tone.darkHighContrast.hairline, Tone.lightHighContrast.hairline),
            ("badge", Tone.darkHighContrast.badge, Tone.lightHighContrast.badge),
            ("badgeMuted", Tone.darkHighContrast.badgeMuted, Tone.lightHighContrast.badgeMuted),
            ("badgePoint", Tone.darkHighContrast.badgePoint, Tone.lightHighContrast.badgePoint),
        ] {
            XCTAssertEqual(alpha(dark), alpha(light), accuracy: 0.001, "high contrast \(name)")
        }
        for (name, overlay) in [
            ("surface", Tone.dark.surface),
            ("raised", Tone.dark.raised),
            ("hairline", Tone.dark.hairline),
            ("badge", Tone.dark.badge),
            ("badgeMuted", Tone.dark.badgeMuted),
        ] {
            let rgb = sRGB(overlay)
            XCTAssertEqual(rgb.r, rgb.g, accuracy: 0.001, name)
            XCTAssertEqual(rgb.g, rgb.b, accuracy: 0.001, name)
            XCTAssertGreaterThan(rgb.r, 0.99, "\(name) steps up in neutral white")
        }
        let tint = sRGB(Tone.dark.tint)
        XCTAssertLessThanOrEqual(abs(tint.r - tint.g) * 255, 1, "dark tint is near-neutral")
        XCTAssertLessThanOrEqual(tint.b * 255 - tint.r * 255, 3, "dark tint is only slightly cool")
        XCTAssertLessThan(tint.r * 255, 32, "dark tint is a charcoal base")
        XCTAssertEqual(sRGB(Tone.dark.point).r, 108.0 / 255, accuracy: 0.001)
        XCTAssertEqual(sRGB(Tone.dark.point).g, 168.0 / 255, accuracy: 0.001)
        XCTAssertEqual(sRGB(Tone.dark.point).b, 1, accuracy: 0.001)
        XCTAssertEqual(alpha(Tone.dark.controlOn), alpha(Tone.dark.text), accuracy: 0.001)
    }

    private typealias RGB = (r: Double, g: Double, b: Double)

    private func sRGB(_ color: Color) -> RGB {
        let ns = NSColor(color).usingColorSpace(.sRGB)!
        return (Double(ns.redComponent), Double(ns.greenComponent), Double(ns.blueComponent))
    }

    private func composite(black opacity: Double, over base: RGB) -> RGB {
        ((1 - opacity) * base.r, (1 - opacity) * base.g, (1 - opacity) * base.b)
    }

    private func alpha(_ color: Color) -> Double {
        Double(NSColor(color).usingColorSpace(.sRGB)!.alphaComponent)
    }

    private func assertSamePalette(_ actual: Tone, _ expected: Tone,
                                   file: StaticString = #filePath, line: UInt = #line) {
        XCTAssertEqual(actual.paneMaterial, expected.paneMaterial, file: file, line: line)
        for (actualColor, expectedColor) in [
            (actual.text, expected.text),
            (actual.tint, expected.tint),
            (actual.bandTint, expected.bandTint),
            (actual.opaqueGround, expected.opaqueGround),
            (actual.point, expected.point),
        ] {
            let a = sRGB(actualColor)
            let e = sRGB(expectedColor)
            XCTAssertEqual(a.r, e.r, accuracy: 0.001, file: file, line: line)
            XCTAssertEqual(a.g, e.g, accuracy: 0.001, file: file, line: line)
            XCTAssertEqual(a.b, e.b, accuracy: 0.001, file: file, line: line)
            XCTAssertEqual(alpha(actualColor), alpha(expectedColor), accuracy: 0.001,
                           file: file, line: line)
        }
    }


    private func over(_ color: Color, _ base: RGB) -> RGB {
        let c = sRGB(color)
        let a = alpha(color)
        return (a * c.r + (1 - a) * base.r, a * c.g + (1 - a) * base.g, a * c.b + (1 - a) * base.b)
    }

    private func linear(_ c: Double) -> Double {
        c <= 0.03928 ? c / 12.92 : pow((c + 0.055) / 1.055, 2.4)
    }

    private func luminance(_ c: RGB) -> Double {
        0.2126 * linear(c.r) + 0.7152 * linear(c.g) + 0.0722 * linear(c.b)
    }

    private func contrast(_ a: RGB, _ b: RGB) -> Double {
        let (la, lb) = (luminance(a), luminance(b))
        return (max(la, lb) + 0.05) / (min(la, lb) + 0.05)
    }

    private func hex(_ c: RGB) -> String {
        String(format: "#%02X%02X%02X", Int((c.r * 255).rounded()), Int((c.g * 255).rounded()), Int((c.b * 255).rounded()))
    }
}
