import AppKit
import Foundation
import SwiftUI
import XCTest
@testable import CodexMulti








@MainActor
final class LayoutRenderTests: XCTestCase {
    private static let scale: CGFloat = 2


    func testNoticeTextAndDismissButtonSitOnTheBoxCentre() throws {
        let notice = try JSONDecoder().decode(Notice.self, from: JSONSerialization.data(withJSONObject: [
            "kind": "pending", "text": "0000000000 0000000000",
        ]))
        let ink = try render(NoticeSlot(notice: notice), width: 600)
        let box = ink.size
        let text = try XCTUnwrap(ink.bounds(x: 0..<(box.width * 0.7)), "no text ink")
        let dismiss = try XCTUnwrap(ink.bounds(x: (box.width - 40)..<box.width), "no × ink")
        XCTAssertEqual(text.midY, box.height / 2, accuracy: 1.5, "text centre \(text.midY) vs box centre \(box.height / 2) (box \(box))")
        XCTAssertEqual(dismiss.midY, box.height / 2, accuracy: 1.5, "× centre \(dismiss.midY) vs box centre \(box.height / 2)")
    }






    func testUnifiedBadgeColumnAlignsTheNameForEveryProjectedState() throws {
        let data = try Data(contentsOf: Fixtures.exported("proxy-reachable-mapped"))
        let root = try XCTUnwrap(JSONSerialization.jsonObject(with: data) as? [String: Any])
        let view = try XCTUnwrap(root["view"] as? [String: Any])
        let projectedStates = try XCTUnwrap(view["proxy_rows"] as? [[String: Any]])
        let unifiedRows = try XCTUnwrap(view["unified_rows"] as? [[String: Any]])
        let shell = try JSONDecoder().decode(Projection.self, from: data).shell
        XCTAssertEqual(projectedStates.compactMap { $0["state_text"] as? String },
                       ["Active", "Ready", "Cooldown", "Paused", "Not mapped"])

        let badgeColumnEnd = Grid.inset + StateBadgeLayout.columnWidth
        let nameFrameX = badgeColumnEnd + Grid.badgeGap
        let nameBearing = try leftSideBearing(of: "7", size: 14)
        var nameLefts: [CGFloat] = []
        for state in projectedStates {
            var object = try XCTUnwrap(unifiedRows.first)
            object["failover_state_text"] = state["state_text"]
            object["failover_accent"] = state["state_accent"]
            object["failover_muted"] = state["label_muted"]
            object["email_local"] = "7777"
            object["email_domain"] = ""
            object["has_domain"] = false
            let row = try JSONDecoder().decode(
                UnifiedRowView.self, from: JSONSerialization.data(withJSONObject: object))
            let ink = try render(UnifiedRowHeader(row: row, shell: shell), width: 900)
            let capsule = try XCTUnwrap(
                ink.firstRun(from: 0, y: 0..<ink.size.height, threshold: 8),
                "no \(row.failover_state_text) badge capsule")
            let name = try XCTUnwrap(
                ink.firstRun(from: nameFrameX, y: 0..<ink.size.height, threshold: 160),
                "no \(row.failover_state_text) account identity")
            XCTAssertEqual(capsule.minX, Grid.inset, accuracy: 0.5,
                           "\(row.failover_state_text) badge starts at the shared text edge")
            XCTAssertNil(ink.bounds(x: badgeColumnEnd..<nameFrameX,
                                    y: 0..<ink.size.height, threshold: 2),
                         "the full former-rule gap stays plain space for \(row.failover_state_text)")
            XCTAssertEqual(name.minX - nameBearing, nameFrameX, accuracy: 0.75,
                           "the unchanged \(Grid.badgeGap) pt gap ends at the name frame")
            nameLefts.append(name.minX)
        }

        let expected = try XCTUnwrap(nameLefts.first)
        for (state, nameLeft) in zip(projectedStates, nameLefts) {
            XCTAssertEqual(nameLeft, expected, accuracy: 0.5,
                           "\(state["state_text"] ?? "state") name starts at \(nameLeft), expected \(expected)")
        }
    }




    func testDarkPaneRendersNeutralAndMateriallyDarkerThanLightOverMidGrey() throws {
        let side: CGFloat = 64
        let light = try render(
            P13PaneSwatch(tone: .light)
                .environment(\.colorScheme, .light),
            width: side, tone: .light)
        let dark = try render(
            P13PaneSwatch(tone: .dark)
                .environment(\.colorScheme, .dark),
            width: side, tone: .dark)
        let point = CGPoint(x: side / 2, y: side / 2)
        let lightRGB = light.colour(at: point)
        let darkRGB = dark.colour(at: point)
        let lightLevels = (lightRGB.r * 255, lightRGB.g * 255, lightRGB.b * 255)
        let darkLevels = (darkRGB.r * 255, darkRGB.g * 255, darkRGB.b * 255)
        let lightMean = (lightLevels.0 + lightLevels.1 + lightLevels.2) / 3
        let darkMean = (darkLevels.0 + darkLevels.1 + darkLevels.2) / 3

        print(String(format: "P13 pane RGB over mid-grey: light=(%.0f, %.0f, %.0f), dark=(%.0f, %.0f, %.0f)",
                     lightLevels.0, lightLevels.1, lightLevels.2,
                     darkLevels.0, darkLevels.1, darkLevels.2))
        XCTAssertLessThanOrEqual(darkLevels.0 - darkLevels.2, 3,
                                 "dark pane is warm, not neutral: \(darkLevels)")
        XCTAssertLessThanOrEqual(darkMean, lightMean - 32,
                                 "dark pane is not materially darker: light \(lightLevels), dark \(darkLevels)")
    }




    func testResolvedLightPaneIsMeasurablyLightAndFarAboveDark() throws {
        let side: CGFloat = 64
        let light = AppearanceResolver.resolve(.light, system: .dark, contrast: .standard)
        let dark = AppearanceResolver.resolve(.dark, system: .light, contrast: .standard)
        let lightOnWhite = try render(
            P16PaneSwatch(tone: light.tone, backdrop: .white)
                .environment(\.colorScheme, .light),
            width: side, tone: light.tone)
        let lightOnBlack = try render(
            P16PaneSwatch(tone: light.tone, backdrop: .black)
                .environment(\.colorScheme, .light),
            width: side, tone: light.tone)
        let darkOnWhite = try render(
            P16PaneSwatch(tone: dark.tone, backdrop: .white)
                .environment(\.colorScheme, .dark),
            width: side, tone: dark.tone)
        let lightFloorOnBlack = try render(
            P16PaneTintFloorSwatch(tint: light.tone.tint, backdrop: .black),
            width: side, tone: light.tone)
        let priorThousandthFloor = try render(
            P16PaneTintFloorSwatch(
                tint: Color(red: 0.97, green: 0.965, blue: 0.955).opacity(0.814),
                backdrop: .black),
            width: side, tone: light.tone)
        let point = CGPoint(x: side / 2, y: side / 2)
        let lightRGB = lightOnWhite.colour(at: point)
        let blackRGB = lightOnBlack.colour(at: point)
        let darkRGB = darkOnWhite.colour(at: point)
        let floorRGB = lightFloorOnBlack.colour(at: point)
        let priorFloorRGB = priorThousandthFloor.colour(at: point)
        let lightLevels = [lightRGB.r, lightRGB.g, lightRGB.b].map { $0 * 255 }
        let blackLevels = [blackRGB.r, blackRGB.g, blackRGB.b].map { $0 * 255 }
        let darkLevels = [darkRGB.r, darkRGB.g, darkRGB.b].map { $0 * 255 }
        let floorLevels = [floorRGB.r, floorRGB.g, floorRGB.b].map { $0 * 255 }
        let priorFloorLevels = [priorFloorRGB.r, priorFloorRGB.g, priorFloorRGB.b].map { $0 * 255 }
        let lightMean = lightLevels.reduce(0, +) / 3
        let blackMean = blackLevels.reduce(0, +) / 3
        let darkMean = darkLevels.reduce(0, +) / 3
        let floorMean = floorLevels.reduce(0, +) / 3
        let priorFloorMean = priorFloorLevels.reduce(0, +) / 3

        print(String(format: "P16 resolved pane RGB: light/white=(%.0f, %.0f, %.0f), light/black=(%.0f, %.0f, %.0f), dark/white=(%.0f, %.0f, %.0f), light tint-only/black=(%.0f, %.0f, %.0f), 0.814 tint-only/black=(%.0f, %.0f, %.0f)",
                     lightLevels[0], lightLevels[1], lightLevels[2],
                     blackLevels[0], blackLevels[1], blackLevels[2],
                     darkLevels[0], darkLevels[1], darkLevels[2],
                     floorLevels[0], floorLevels[1], floorLevels[2],
                     priorFloorLevels[0], priorFloorLevels[1], priorFloorLevels[2]))
        XCTAssertGreaterThan(lightMean, 200, "Light must look light over white: \(lightLevels)")
        XCTAssertGreaterThan(blackMean, 200, "Light must stay light over a dark backdrop: \(blackLevels)")
        XCTAssertGreaterThan(floorMean, 200,
                             "even the tint-only darkest floor must stay light: \(floorLevels)")
        XCTAssertLessThanOrEqual(priorFloorMean, 200,
                                 "0.815 is not the smallest thousandth-step token: \(priorFloorLevels)")
        XCTAssertLessThan(darkMean, lightMean - 80,
                          "Dark must remain far below Light: light \(lightLevels), dark \(darkLevels)")
    }






    func testProductionBandBackdropIsBlurConfiguredAndEndsInAHairline() throws {
        let effect = BandVisualEffectView.makeEffectView()
        XCTAssertEqual(effect.blendingMode, .withinWindow, "the band samples the window's own content")
        XCTAssertEqual(effect.material, .headerView)
        XCTAssertEqual(effect.state, .active, "key and non-key windows must look the same")
        XCTAssertNil(effect.window, "the off-screen proof never attaches the compositor view to a window")

        let width: CGFloat = 128
        let raw = try render(P17BandContentSwatch(includesBand: false), width: width)
        let band = try render(P17BandContentSwatch(includesBand: true), width: width)
        let sampleY: CGFloat = 24
        let rawRowMean = Ink.rgbMean(raw.colour(at: CGPoint(x: width / 2, y: sampleY))) * 255
        let bandRowMean = Ink.rgbMean(band.colour(at: CGPoint(x: width / 2, y: sampleY))) * 255
        let emptyBandMean = Ink.rgbMean(band.colour(at: CGPoint(x: 20, y: sampleY))) * 255
        print(String(format: "band: raw-row=%.1f band-row=%.1f empty-band=%.1f", rawRowMean, bandRowMean, emptyBandMean))
        XCTAssertGreaterThan(bandRowMean, rawRowMean + 4,
                             "the translucent Light band must lighten the strong dark row")



        XCTAssertLessThan(bandRowMean, emptyBandMean - 12,
                          "the band must not erase the dark row into the empty pane")
    }



    func testBandStatusRefreshAndAddUseSeparateEqualGapFrames() {
        let frames = BandControlLayout.frames(statusWidth: 176)
        XCTAssertFalse(frames.status.intersects(frames.refresh))
        XCTAssertFalse(frames.refresh.intersects(frames.add))
        XCTAssertEqual(frames.refresh.width, frames.refresh.height, accuracy: 0.001)
        XCTAssertEqual(frames.add.width, frames.add.height, accuracy: 0.001)
        XCTAssertEqual(frames.refresh.width, frames.add.width, accuracy: 0.001)
        XCTAssertEqual(frames.refresh.width, Grid.pillHeight, accuracy: 0.001)
        XCTAssertEqual(frames.refresh.minX - frames.status.maxX, Grid.bandGap, accuracy: 0.001)
        XCTAssertEqual(frames.add.minX - frames.refresh.maxX, Grid.bandGap, accuracy: 0.001)
        XCTAssertEqual(frames.status.midY, frames.refresh.midY, accuracy: 0.001)
        XCTAssertEqual(frames.refresh.midY, frames.add.midY, accuracy: 0.001)
    }



    func testBandBackdropAndScrollInsetKeepBothTabsContentBelowTheBand() {
        for tab in ShellTab.allCases {
            let band = ShellBandLayout.backdropFrame(width: Grid.width)
            let firstContent = ShellBandLayout.firstContentFrame(tab: tab, width: Grid.width)
            XCTAssertEqual(band, CGRect(x: 0, y: 0, width: Grid.width, height: Grid.band))
            XCTAssertEqual(ShellBandLayout.scrollTopInset, band.height, accuracy: 0.001)
            XCTAssertGreaterThanOrEqual(firstContent.minY, band.maxY, "\(tab) content starts below the fixed band")
        }
    }

    func testEmptyAccountCardUsesTheFullWindowCenteredOverlay() throws {
        let root = Fixtures.bridgeDirectory.deletingLastPathComponent().deletingLastPathComponent()
        let shell = try String(
            contentsOf: root.appending(path: "Sources/CodexMulti/Accounts/SettingsShell.swift"),
            encoding: .utf8
        )
        let unified = try String(
            contentsOf: root.appending(path: "Sources/CodexMulti/Accounts/UnifiedScreen.swift"),
            encoding: .utf8
        )
        XCTAssertTrue(shell.contains("EmptyAccountsPage(projection: projection)"))
        XCTAssertFalse(unified.contains("NoAccountsPanel("), "the scrolling list must not own the empty card")

        let projection = try JSONDecoder().decode(Projection.self, from: Fixtures.emptyAttachedData())
        let ink = try render(
            EmptyAccountsPage(projection: projection)
                .frame(width: Grid.width, height: Grid.minHeight),
            width: Grid.width
        )
        let card = try XCTUnwrap(ink.bounds(x: 0..<ink.size.width, threshold: 8), "no empty-state card")
        XCTAssertEqual(card.midY, Grid.minHeight / 2, accuracy: 1,
                       "the empty-state card centre follows the window centre")
    }



    func testUnifiedCollapsedRowsAreOneLineAtOneUniformHeight() throws {
        let data = try Data(contentsOf: Fixtures.exported("proxy-reachable-mapped"))
        let root = try XCTUnwrap(JSONSerialization.jsonObject(with: data) as? [String: Any])
        let view = try XCTUnwrap(root["view"] as? [String: Any])
        let projectedStates = try XCTUnwrap(view["proxy_rows"] as? [[String: Any]])
        let unifiedRows = try XCTUnwrap(view["unified_rows"] as? [[String: Any]])
        let shell = try JSONDecoder().decode(Projection.self, from: data).shell
        let nameStart = Grid.inset + StateBadgeLayout.columnWidth + Grid.badgeGap

        for state in projectedStates {
            var object = try XCTUnwrap(unifiedRows.first)
            object["failover_state_text"] = state["state_text"]
            object["failover_accent"] = state["state_accent"]
            object["failover_muted"] = state["label_muted"]
            object["failover_detail_text"] = "until Sep 15 21:04 · 6d 8h"
            object["failover_in_flight"] = 16
            object["failover_in_flight_text"] = "16"
            object["email_local"] = "7777"
            object["email_domain"] = ""
            object["has_domain"] = false
            object["usage_caption"] = ""
            object["usage_percent_text"] = ""
            let row = try JSONDecoder().decode(
                UnifiedRowView.self, from: JSONSerialization.data(withJSONObject: object))
            let ink = try render(UnifiedRowHeader(row: row, shell: shell), width: 900)
            XCTAssertEqual(ink.size.height, Grid.accountsRow, accuracy: 0.5, row.failover_state_text)
            let name = try XCTUnwrap(
                ink.bounds(x: nameStart..<(nameStart + 80), y: 0..<ink.size.height, threshold: 160),
                "no \(row.failover_state_text) name")
            XCTAssertEqual(name.midY, ink.size.height / 2, accuracy: 1.5,
                           "\(row.failover_state_text) has one centred name line (\(name))")
            XCTAssertNil(
                ink.bounds(x: Grid.inset..<(nameStart + 160),
                           y: (ink.size.height / 2 + 9)..<ink.size.height, threshold: 64),
                "\(row.failover_state_text) still draws a second line")
        }
    }




    func testUnifiedRowRendersProjectedPlanOnlyWhenHasPlan() throws {
        let width: CGFloat = 900
        let nameStart = Grid.inset + StateBadgeLayout.columnWidth + Grid.badgeGap
        let identityEnd = unifiedIdentityColumnEnd(width: width)
        let overrides: [String: Any] = [
            "email_local": "7777", "email_domain": "", "has_domain": false,
            "plan": "1177", "usage_caption": "", "usage_percent_text": "",
        ]
        let visible = try unifiedRow(overrides.merging(["has_plan": true]) { $1 })
        let visibleAlternate = try unifiedRow(overrides.merging([
            "plan": "7111", "has_plan": true,
        ]) { $1 })
        let hidden = try unifiedRow(overrides.merging(["has_plan": false]) { $1 })
        let hiddenAlternate = try unifiedRow(overrides.merging([
            "plan": "7111", "has_plan": false,
        ]) { $1 })
        let visibleInk = try render(UnifiedRowHeader(row: visible.row, shell: visible.shell), width: width)
        let visibleAlternateInk = try render(
            UnifiedRowHeader(row: visibleAlternate.row, shell: visibleAlternate.shell), width: width)
        let hiddenInk = try render(UnifiedRowHeader(row: hidden.row, shell: hidden.shell), width: width)
        let hiddenAlternateInk = try render(
            UnifiedRowHeader(row: hiddenAlternate.row, shell: hiddenAlternate.shell), width: width)
        let email = try XCTUnwrap(
            visibleInk.bounds(x: nameStart..<identityEnd, threshold: 160), "no email ink")
        let planRange = (email.maxX + 4)..<identityEnd

        XCTAssertNotNil(visibleInk.bounds(x: planRange, threshold: 64),
                        "the projected 1177 plan is rendered after the email")
        XCTAssertNil(hiddenInk.bounds(x: planRange, threshold: 64),
                     "has_plan=false draws no plan or placeholder")
        XCTAssertGreaterThan(visibleInk.differentPixelCount(from: hiddenInk, x: planRange), 0,
                             "showing the plan adds its glyphs")
        XCTAssertGreaterThan(visibleInk.differentPixelCount(
            from: visibleAlternateInk, x: planRange), 0,
            "changing the projected plan changes the rendered glyphs")
        XCTAssertEqual(hiddenInk.differentPixelCount(
            from: hiddenAlternateInk, x: 0..<hiddenInk.size.width), 0,
            "the plan payload occupies no rendered space while has_plan is false")
    }




    func testUnifiedPlanSharesEmailBaselineAndSurvivesEmailTruncationWithoutCrossingColumns() throws {
        let wideWidth: CGFloat = 1500
        let narrowWidth: CGFloat = 900
        let longEmail = String(repeating: "7", count: 100)
        let base: [String: Any] = [
            "email_local": longEmail, "email_domain": "", "has_domain": false,
            "plan": "1177", "has_plan": true,
            "usage_caption": "7777", "usage_percent_text": "77%",
        ]
        let long = try unifiedRow(base)
        let short = try unifiedRow(base.merging(["email_local": "7777"]) { $1 })
        let wide = try render(UnifiedRowHeader(row: long.row, shell: long.shell), width: wideWidth)
        let narrow = try render(UnifiedRowHeader(row: long.row, shell: long.shell), width: narrowWidth)
        let narrowShort = try render(
            UnifiedRowHeader(row: short.row, shell: short.shell), width: narrowWidth)
        let nameStart = Grid.inset + StateBadgeLayout.columnWidth + Grid.badgeGap
        let wideIdentityEnd = unifiedIdentityColumnEnd(width: wideWidth)
        let narrowIdentityEnd = unifiedIdentityColumnEnd(width: narrowWidth)
        let narrowUsageStart = narrowIdentityEnd + Grid.gap

        let wideEmail = try XCTUnwrap(
            wide.bounds(x: nameStart..<wideIdentityEnd, threshold: 160), "no wide email ink")
        let narrowEmail = try XCTUnwrap(
            narrow.bounds(x: nameStart..<narrowIdentityEnd, threshold: 160), "no narrow email ink")
        let widePlan = try XCTUnwrap(
            wide.bounds(x: (wideEmail.maxX + 4)..<wideIdentityEnd, threshold: 64), "no wide plan ink")
        let planFrameWidth = ("1177" as NSString).size(withAttributes: [
            .font: NSFont.systemFont(ofSize: 12.5, weight: .regular),
        ]).width
        let narrowPlan = try XCTUnwrap(
            narrow.bounds(x: (narrowIdentityEnd - planFrameWidth - 4)..<narrowIdentityEnd, threshold: 64),
            "no narrow plan ink")
        let narrowEmailFirstGlyph = try XCTUnwrap(
            narrow.firstRun(from: nameStart, y: 0..<narrow.size.height, threshold: 160),
            "no first email glyph")
        let emailBearing = try rightSideBearing(of: "7", size: 14)
        let planBearing = try leftSideBearing(of: "1", size: 12.5)

        XCTAssertEqual((widePlan.minX - planBearing) - (wideEmail.maxX + emailBearing),
                       Grid.planGap, accuracy: 1,
                       "the plan follows the untruncated email by the plan gap")
        XCTAssertEqual(narrowPlan.maxY, narrowEmailFirstGlyph.maxY, accuracy: 0.5,
                       "plan and email share their first text baseline")
        XCTAssertLessThan(narrowEmail.width, wideEmail.width - 100,
                          "the email, not the plan, truncates in the narrow row")
        XCTAssertEqual(narrowPlan.width, widePlan.width, accuracy: 0.5,
                       "the plan keeps its full intrinsic width")
        XCTAssertEqual(narrowPlan.height, widePlan.height, accuracy: 0.5,
                       "the plan keeps the same glyph raster after email truncation")
        XCTAssertGreaterThanOrEqual(narrowPlan.minX, nameStart,
                                    "the plan stays beyond the status-badge column")
        XCTAssertLessThanOrEqual(narrowPlan.maxX, narrowIdentityEnd,
                                 "the plan stays inside the identity column")
        XCTAssertNil(narrow.bounds(
            x: narrowIdentityEnd..<narrowUsageStart, y: 0..<narrow.size.height, threshold: 2),
            "the column gap between plan and usage remains clear")
        XCTAssertEqual(narrow.differentPixelCount(
            from: narrowShort, x: narrowUsageStart..<narrow.size.width), 0,
            "email pressure never changes or overlaps usage and action columns")
    }




    func testUnifiedCoolingMutesOnlyTheBadge() throws {
        func projection(muted: Bool) throws -> Projection {
            let data = try Data(contentsOf: Fixtures.exported("unified-proxy-order"))
            var root = try XCTUnwrap(JSONSerialization.jsonObject(with: data) as? [String: Any])
            var view = try XCTUnwrap(root["view"] as? [String: Any])
            var rows = try XCTUnwrap(view["unified_rows"] as? [[String: Any]])
            rows[0]["failover_state_text"] = "1177"
            rows[0]["failover_accent"] = false
            rows[0]["failover_muted"] = muted
            rows[0]["failover_detail_text"] = ""
            rows[0]["failover_in_flight"] = 0
            rows[0]["failover_in_flight_text"] = ""
            rows[0]["email_local"] = "7777"
            rows[0]["email_domain"] = "@1177.71"
            rows[0]["has_domain"] = true
            rows[0]["usage_caption"] = "7777"
            rows[0]["usage_percent_text"] = "77%"
            rows[0]["usage_bar_fraction"] = 0.77
            rows[0]["usage_exhausted"] = false
            rows[0]["action_busy"] = false
            rows[0]["expanded"] = false
            view["unified_rows"] = rows
            root["view"] = view
            return try JSONDecoder().decode(Projection.self, from: Fixtures.data(from: root))
        }

        let readyProjection = try projection(muted: false)
        let mutedProjection = try projection(muted: true)
        let ready = try render(
            UnifiedAccountRow(row: try XCTUnwrap(readyProjection.view.unified_rows.first), projection: readyProjection),
            width: 900)
        let cooling = try render(
            UnifiedAccountRow(row: try XCTUnwrap(mutedProjection.view.unified_rows.first), projection: mutedProjection),
            width: 900)
        let badgeEnd = Grid.inset + StateBadgeLayout.columnWidth
        XCTAssertGreaterThan(ready.differentPixelCount(from: cooling, x: Grid.inset..<badgeEnd), 0,
                             "the muted badge should use its muted fill and ink")
        XCTAssertEqual(ready.differentPixelCount(from: cooling, x: badgeEnd..<ready.size.width), 0,
                       "cooldown may not mute the identity, usage, bar or action")
    }



    func testUnifiedNameUsesOneRegularWeightAndOneInk() throws {
        let data = try Data(contentsOf: Fixtures.exported("c6-ready-token"))
        var root = try XCTUnwrap(JSONSerialization.jsonObject(with: data) as? [String: Any])
        var view = try XCTUnwrap(root["view"] as? [String: Any])
        var rows = try XCTUnwrap(view["unified_rows"] as? [[String: Any]])
        rows[0]["email_local"] = "7777"
        rows[0]["email_domain"] = "7777"
        rows[0]["has_domain"] = true
        rows[0]["has_plan"] = false
        view["unified_rows"] = rows
        root["view"] = view
        let projection = try JSONDecoder().decode(Projection.self, from: Fixtures.data(from: root))
        let row = try XCTUnwrap(projection.view.unified_rows.first)
        let actual = try render(UnifiedRowHeader(row: row, shell: projection.shell), width: 900)
        let expected = try render(P10RegularIdentityReference(row: row), width: 900)
        let nameStart = Grid.inset + StateBadgeLayout.columnWidth + Grid.badgeGap
        XCTAssertEqual(actual.differentPixelCount(from: expected, x: nameStart..<(nameStart + 100)), 0,
                       "the local and domain glyphs must be the same regular face and text ink")
    }










    func testFailoverRowIsOneLineOnOneBaseline() throws {
        let ink = try render(FailoverRow(row: try sampleRow(state: "1177", detail: "11 77")), width: 900)
        XCTAssertEqual(ink.size.height, Grid.failoverRow, accuracy: 0.5, "row height \(ink.size.height)")
        let row: Range<CGFloat> = 0..<ink.size.height


        let capsule = try XCTUnwrap(ink.firstRun(from: 0, y: row, threshold: 8), "no badge capsule")
        XCTAssertEqual(capsule.minX, Grid.inset, accuracy: 0.5, "the badge starts at the row's text edge (capsule \(capsule))")
        XCTAssertGreaterThan(capsule.width, 20, "a capsule, not a glyph (\(capsule))")
        let badgeText = try XCTUnwrap(ink.bounds(x: capsule.minX..<capsule.maxX, y: row), "no badge text")



        let email = try XCTUnwrap(ink.bounds(x: capsule.maxX..<ink.size.width, y: row, threshold: 160), "no email ink")
        let emailFirst = try XCTUnwrap(ink.firstRun(from: capsule.maxX, y: row, threshold: 160), "no email glyph")
        XCTAssertEqual(email.minX - capsule.maxX,
                       StateBadgeLayout.columnWidth - capsule.width + Grid.badgeGap,
                       accuracy: 1, "email follows the fixed badge column (capsule \(capsule), email \(email))")

        let detail = try XCTUnwrap(ink.firstRun(from: email.maxX + 0.5, y: row), "no detail ink after the email")
        XCTAssertNil(ink.bounds(x: (email.maxX + 0.5)..<ink.size.width, y: row, threshold: 160), "everything after the email is muted ink: the detail in text3, nothing else")
        let emailBearing = try rightSideBearing(of: "1", size: 14)
        let detailBearing = try leftSideBearing(of: "1", size: 12.5)
        XCTAssertEqual((detail.minX - detailBearing) - (email.maxX + emailBearing), Grid.detailGap, accuracy: 1, "detail 12 pt after the email (email \(email), detail \(detail), bearings \(emailBearing) / \(detailBearing))")

        XCTAssertEqual(emailFirst.maxY, badgeText.maxY, accuracy: 0.5, "the email sits on the badge's baseline (badge \(badgeText), email \(emailFirst))")
        XCTAssertEqual(detail.maxY, emailFirst.maxY, accuracy: 0.5, "the detail sits on the email's baseline (email \(emailFirst), detail \(detail))")
        XCTAssertEqual(emailFirst.midY, ink.size.height / 2, accuracy: 1.5, "the line sits on the row's centre (email \(emailFirst), row \(ink.size))")
    }







    func testFailoverDetailTruncatesBeforeTheMenuSlotAndTheEmailStaysWhole() throws {
        let local = String(repeating: "7", count: 40)
        let detail = String(repeating: "1177", count: 8)
        let wide = try render(FailoverRow(row: try sampleRow(state: "1177", detail: detail, local: local)), width: 1600)
        let capsule = try XCTUnwrap(wide.firstRun(from: 0, y: 0..<wide.size.height, threshold: 8), "no badge capsule")
        let wideEmail = try XCTUnwrap(wide.bounds(x: capsule.maxX..<wide.size.width, threshold: 160), "no email ink (wide)")
        let wideDetail = try XCTUnwrap(wide.bounds(x: (wideEmail.maxX + 0.5)..<wide.size.width), "no detail ink (wide)")
        XCTAssertGreaterThan(wideEmail.width, wideDetail.width, "the sample email is the wider text (email \(wideEmail), detail \(wideDetail))")
        let column = wideDetail.maxX - 40
        let narrow = try render(FailoverRow(row: try sampleRow(state: "1177", detail: detail, local: local)), width: column + Grid.gap + Grid.menu + Grid.inset)
        let narrowEmail = try XCTUnwrap(narrow.bounds(x: capsule.maxX..<narrow.size.width, threshold: 160), "no email ink (narrow)")
        XCTAssertEqual(narrowEmail.minX, wideEmail.minX, accuracy: 0.5, "the email starts where it did (\(narrowEmail) vs \(wideEmail))")
        XCTAssertEqual(narrowEmail.maxX, wideEmail.maxX, accuracy: 0.5, "the email is whole: nothing of it gave way (\(narrowEmail) vs \(wideEmail))")
        let narrowDetail = try XCTUnwrap(narrow.bounds(x: (narrowEmail.maxX + 0.5)..<narrow.size.width), "no detail ink (narrow)")
        XCTAssertLessThanOrEqual(narrowDetail.maxX, column + 0.5, "the detail ends inside the text column, before the … slot (detail \(narrowDetail), column edge \(column))")
        XCTAssertGreaterThan(narrowDetail.maxX, column - 20, "the detail runs to its ellipsis at the column's edge (detail \(narrowDetail), column edge \(column))")
    }







    func testBandCapsuleIsAFlatWashWithNoRimOrShadow() throws {
        let margin: CGFloat = 12
        let ink = try render(Color.clear.frame(width: 120, height: Grid.pillHeight).bandGlass().padding(margin), width: 144)
        XCTAssertEqual(ink.size, CGSize(width: 144, height: Grid.pillHeight + 2 * margin))
        let frame = CGRect(x: margin, y: margin, width: 120, height: Grid.pillHeight)
        let everything = try XCTUnwrap(ink.bounds(x: 0..<ink.size.width, threshold: 2), "no capsule ink")
        XCTAssertEqual(everything.minX, frame.minX, accuracy: 0.5, "no shadow or stroke left of the capsule (\(everything))")
        XCTAssertEqual(everything.maxX, frame.maxX, accuracy: 0.5, "no shadow or stroke right of the capsule (\(everything))")
        XCTAssertEqual(everything.minY, frame.minY, accuracy: 0.5, "no shadow or stroke above the capsule (\(everything))")
        XCTAssertEqual(everything.maxY, frame.maxY, accuracy: 0.5, "no shadow below the capsule (\(everything))")
        let centre = ink.colour(at: CGPoint(x: frame.midX, y: frame.midY))
        XCTAssertEqual(centre.a, 0.31, accuracy: 0.03, "the wash is 31 % (\(centre))")
        XCTAssertEqual(centre.r * 255, 223, accuracy: 4, "the wash is the warm light grey, r (\(centre))")
        XCTAssertEqual(centre.g * 255, 220, accuracy: 4, "the wash is the warm light grey, g (\(centre))")
        XCTAssertEqual(centre.b * 255, 216, accuracy: 4, "the wash is the warm light grey, b (\(centre))")


        let edge = ink.colour(at: CGPoint(x: frame.minX + 0.75, y: frame.midY))
        XCTAssertEqual(edge.a, centre.a, accuracy: 0.03, "no edge stroke: the edge pixel is the wash (\(edge) vs \(centre))")
        XCTAssertEqual(edge.r, centre.r, accuracy: 0.03, "no highlight: the edge pixel is the wash (\(edge) vs \(centre))")
        let top = ink.colour(at: CGPoint(x: frame.midX, y: frame.minY + 0.75))
        XCTAssertEqual(top.a, centre.a, accuracy: 0.03, "no edge stroke along the top (\(top) vs \(centre))")
        XCTAssertEqual(top.r, centre.r, accuracy: 0.03, "no highlight along the top (\(top) vs \(centre))")
    }



    func testDialogCheckboxIsDrawnByTheShellInPrimaryInk() throws {
        let on = try render(Toggle(isOn: .constant(true)) { Text(verbatim: "0000") }.toggleStyle(DialogCheckboxStyle(focused: false)), width: 200)
        let onBox = try XCTUnwrap(on.firstRun(from: 0, y: 0..<on.size.height, threshold: 8), "no box ink")
        XCTAssertEqual(onBox.width, DialogMetrics.checkbox, accuracy: 1, "the box is \(DialogMetrics.checkbox) pt wide (\(onBox))")
        let boxColour = on.colour(at: CGPoint(x: onBox.minX + 1.5, y: onBox.midY))
        XCTAssertEqual(boxColour.r, boxColour.g, accuracy: 0.03, "the on-box is neutral ink (\(boxColour))")
        XCTAssertEqual(boxColour.g, boxColour.b, accuracy: 0.03, "the on-box is neutral ink (\(boxColour))")
        XCTAssertLessThan(boxColour.r, 0.25, "the on-box is near-black primary ink (\(boxColour))")
        XCTAssertEqual(boxColour.a, 0.86, accuracy: 0.03, "the on-box uses the primary ink opacity")
        let off = try render(Toggle(isOn: .constant(false)) { Text(verbatim: "0000") }.toggleStyle(DialogCheckboxStyle(focused: false)), width: 200)
        let offBox = try XCTUnwrap(off.firstRun(from: 0, y: 0..<off.size.height, threshold: 4), "no off-box wash")
        XCTAssertEqual(offBox.width, DialogMetrics.checkbox, accuracy: 1, "the off box has the same size (\(offBox))")
        XCTAssertNil(off.firstRun(from: 0, y: 0..<off.size.height, threshold: 64).flatMap { $0.minX < offBox.maxX ? $0 : nil }, "the off box is a wash, no check mark")
    }



    func testSettingsSwitchUsesAnInkTrackAndWhiteKnob() throws {
        let on = try render(
            Toggle("", isOn: .constant(true))
                .labelsHidden()
                .toggleStyle(InkSwitchStyle()),
            width: 80)
        let frame = try XCTUnwrap(on.bounds(x: 0..<on.size.width, threshold: 2), "no switch pixels")
        let track = on.colour(at: CGPoint(x: frame.minX + 2, y: frame.midY))
        XCTAssertEqual(track.r, track.g, accuracy: 0.04, "the on track is neutral ink (\(track))")
        XCTAssertEqual(track.g, track.b, accuracy: 0.04, "the on track is neutral ink (\(track))")
        XCTAssertLessThan(track.r, 0.25, "the on track is near-black (\(track))")
        let knob = on.colour(at: CGPoint(x: frame.maxX - frame.height / 2, y: frame.midY))
        XCTAssertGreaterThan(knob.r, 0.90, "the on knob is white (\(knob))")
        XCTAssertGreaterThan(knob.g, 0.90, "the on knob is white (\(knob))")
        XCTAssertGreaterThan(knob.b, 0.90, "the on knob is white (\(knob))")
    }




    func testBundledProxyFiveStatesRenderOffscreenInBothAccessibilityModes() throws {
        let names = ["not-installed", "installed-stale", "starting", "running", "unreachable"]
        var routingStates: [CodexRoutingState] = []
        var accessibilityTransaction = Transaction(animation: nil)
        accessibilityTransaction.disablesAnimations = true
        XCTAssertNil(Motion.snappy(true))
        for name in names {
            let projection = try JSONDecoder().decode(
                Projection.self, from: Data(contentsOf: Fixtures.exported("proxy-service-\(name)")))
            routingStates.append(projection.view.codex_routing_state)
            let light = try render(ProxyLifecyclePanel(view: projection.view), width: 720)
            let accessible = try render(ProxyLifecyclePanel(view: projection.view), width: 720,
                                        tone: .lightHighContrast, transaction: accessibilityTransaction)
            XCTAssertEqual(light.size.width, 720, accuracy: 0.5, name)
            XCTAssertEqual(accessible.size.width, 720, accuracy: 0.5, name)
            XCTAssertGreaterThan(light.size.height, 70, name)
            XCTAssertGreaterThan(accessible.size.height, 70, name)
            XCTAssertNotNil(light.bounds(x: 0..<light.size.width), "no light-mode ink: \(name)")
            XCTAssertNotNil(accessible.bounds(x: 0..<accessible.size.width), "no accessible-mode ink: \(name)")
        }
        XCTAssertEqual(Set(routingStates.map(\.rawValue)), Set(CodexRoutingState.allCases.map(\.rawValue)))
    }

    func testProxySettingsUsePrimaryAndCollapsedAdvancedRows() throws {
        let projection = try JSONDecoder().decode(
            Projection.self, from: Data(contentsOf: Fixtures.exported("proxy-service-running")))
        let ink = try render(ProxyLifecyclePanel(settings: projection.view.settings), width: 720)
        XCTAssertEqual(ink.size.height, Grid.accountsRow * 2 + 0.5, accuracy: 0.5)
        XCTAssertEqual(ink.size.width, 720, accuracy: 0.5)
        XCTAssertNotNil(ink.bounds(x: 0..<ink.size.width))
        let firstLabel = try XCTUnwrap(
            ink.bounds(x: 0..<180, y: 0..<Grid.accountsRow, threshold: 180),
            "the row label uses the account row's primary body ink at the left text edge")
        XCTAssertLessThan(firstLabel.midY, Grid.accountsRow / 2,
                          "the primary label sits above its projected detail")
        XCTAssertNotNil(ink.bounds(x: 0..<620, y: (Grid.accountsRow / 2)..<Grid.accountsRow),
                        "the primary row shows the core-projected proxy detail")
    }

    func testFourSectionSettingsPageRendersOffscreenWithoutSubmitting() throws {
        let projection = try JSONDecoder().decode(
            Projection.self, from: Data(contentsOf: Fixtures.exported("proxy-service-running")))
        var drafts = ProxyDrafts()
        drafts.seedIfNeeded(from: projection.view.settings)
        let recorder = LayoutIntentRecorder()
        let ink = try render(
            SettingsPage(projection: projection, drafts: .constant(drafts))
                .environment(\.submit, recorder.sink),
            width: Grid.width)
        XCTAssertEqual(ink.size.width, Grid.width, accuracy: 0.5)
        XCTAssertGreaterThan(ink.size.height, Grid.accountsRow * 8)
        XCTAssertNotNil(ink.bounds(x: Grid.L..<(Grid.width - Grid.L)))
        XCTAssertEqual(recorder.intents, [], "off-screen Settings layout is passive")
    }

    func testCodexSettingsPanelRendersBothCoreProjectedRows() throws {
        let projection = try JSONDecoder().decode(
            Projection.self, from: Data(contentsOf: Fixtures.exported("settings-appearance-system")))
        let ink = try render(CodexSettingsPanel(settings: projection.view.settings), width: 720)

        XCTAssertEqual(ink.size.height, Grid.accountsRow * 2 + 0.5, accuracy: 0.5)
        XCTAssertNotNil(ink.bounds(x: 0..<ink.size.width, y: 0..<Grid.accountsRow))
        XCTAssertNotNil(ink.bounds(x: 0..<ink.size.width, y: Grid.accountsRow..<ink.size.height))
    }



    func testBothLifecycleConfirmationPresentationsRenderOffscreen() throws {
        let stale = try JSONDecoder().decode(
            Projection.self, from: Data(contentsOf: Fixtures.exported("proxy-service-installed-stale")))
        var clientGate = ProxyConfirmationGate()
        _ = clientGate.request(try XCTUnwrap(FailoverModel.serviceActions(stale.view).first))
        let client = try XCTUnwrap(clientGate.pending)

        var root = try XCTUnwrap(JSONSerialization.jsonObject(
            with: Data(contentsOf: Fixtures.exported("proxy-service-running"))) as? [String: Any])
        var view = try XCTUnwrap(root["view"] as? [String: Any])
        view["codex_routing_state"] = "conflicting"
        var settings = try XCTUnwrap(view["settings"] as? [String: Any])
        settings["codex_routing_state"] = "conflicting"
        view["settings"] = settings
        root["view"] = view
        let conflicting = try JSONDecoder().decode(Projection.self, from: Fixtures.data(from: root))
        var replacementGate = ProxyConfirmationGate()
        _ = replacementGate.request(try XCTUnwrap(FailoverModel.routingActions(conflicting.view).first))
        let replacement = try XCTUnwrap(replacementGate.pending)

        XCTAssertEqual(client.kind, .clientQuiescence)
        XCTAssertEqual(replacement.kind, .replaceRouting)
        XCTAssertNotEqual(client.title, replacement.title)
        XCTAssertNotEqual(client.message, replacement.message)
        var accessibilityTransaction = Transaction(animation: nil)
        accessibilityTransaction.disablesAnimations = true
        for pending in [client, replacement] {
            let normal = try render(ConfirmationEvidence(pending: pending), width: 520)
            let accessible = try render(ConfirmationEvidence(pending: pending), width: 520,
                                        tone: .lightHighContrast, transaction: accessibilityTransaction)
            XCTAssertNotNil(normal.bounds(x: 0..<normal.size.width))
            XCTAssertNotNil(accessible.bounds(x: 0..<accessible.size.width))
            XCTAssertGreaterThan(normal.size.height, 60)
        }
    }




    private func leftSideBearing(of character: Character, size: CGFloat) throws -> CGFloat {
        try glyphMetrics(of: character, size: size).bounds.minX
    }


    private func rightSideBearing(of character: Character, size: CGFloat) throws -> CGFloat {
        let metrics = try glyphMetrics(of: character, size: size)
        return metrics.advance - metrics.bounds.maxX
    }

    private func glyphMetrics(of character: Character, size: CGFloat) throws -> (bounds: CGRect, advance: CGFloat) {
        let font = NSFont.systemFont(ofSize: size, weight: .regular)
        var code = UniChar(try XCTUnwrap(character.utf16.first))
        var glyph = CGGlyph(0)
        XCTAssertTrue(CTFontGetGlyphsForCharacters(font, &code, &glyph, 1), "no glyph for \(character)")
        var rect = CGRect.zero
        CTFontGetBoundingRectsForGlyphs(font, .horizontal, &glyph, &rect, 1)
        var advance = CGSize.zero
        CTFontGetAdvancesForGlyphs(font, .horizontal, &glyph, &advance, 1)
        return (rect, advance.width)
    }




    private func sampleRow(state: String, detail: String, local: String = "7777") throws -> ProxyAccountView {
        var object = SampleProjection.proxyAccountView
        object["order_text"] = "1"
        object["label_local"] = local
        object["label_domain"] = "@1177.71"
        object["state_text"] = state
        object["detail_text"] = detail
        object["has_actions"] = false
        object["can_switch"] = false
        object["can_pause"] = false
        return try JSONDecoder().decode(ProxyAccountView.self, from: JSONSerialization.data(withJSONObject: object))
    }

    private func unifiedRow(_ overrides: [String: Any]) throws -> (row: UnifiedRowView, shell: ShellState) {
        let data = try Data(contentsOf: Fixtures.exported("unified-proxy-order"))
        let root = try XCTUnwrap(JSONSerialization.jsonObject(with: data) as? [String: Any])
        let view = try XCTUnwrap(root["view"] as? [String: Any])
        var object = try XCTUnwrap((view["unified_rows"] as? [[String: Any]])?.first)
        for (key, value) in overrides { object[key] = value }
        return (
            try JSONDecoder().decode(
                UnifiedRowView.self, from: JSONSerialization.data(withJSONObject: object)),
            try JSONDecoder().decode(Projection.self, from: data).shell)
    }

    private func unifiedIdentityColumnEnd(width: CGFloat) -> CGFloat {
        width - Grid.inset - Grid.menu - Grid.gap - Grid.usage - Grid.gap
    }



    private func render<V: View>(_ view: V, width: CGFloat, tone: Tone = .light,
                                 transaction: Transaction = Transaction()) throws -> Ink {
        let renderer = ImageRenderer(content: view.frame(width: width)
            .environment(\.tone, tone)
            .transaction { $0 = transaction })
        renderer.scale = Self.scale
        let image = try XCTUnwrap(renderer.cgImage, "ImageRenderer produced no image")
        return try Ink(image, scale: Self.scale)
    }


    private struct Ink {
        let size: CGSize
        private let width: Int
        private let height: Int
        private let scale: CGFloat
        private let alpha: [UInt8]
        private let rgba: [UInt8]

        init(_ image: CGImage, scale: CGFloat) throws {
            let width = image.width
            let height = image.height
            var bytes = [UInt8](repeating: 0, count: width * height * 4)
            try bytes.withUnsafeMutableBytes { buffer in
                let context = try XCTUnwrap(CGContext(
                    data: buffer.baseAddress, width: width, height: height, bitsPerComponent: 8, bytesPerRow: width * 4,
                    space: CGColorSpaceCreateDeviceRGB(), bitmapInfo: CGImageAlphaInfo.premultipliedLast.rawValue))
                context.draw(image, in: CGRect(x: 0, y: 0, width: width, height: height))
            }
            self.width = width
            self.height = height
            self.scale = scale
            size = CGSize(width: CGFloat(width) / scale, height: CGFloat(height) / scale)
            alpha = stride(from: 3, to: bytes.count, by: 4).map { bytes[$0] }
            rgba = bytes
        }


        func colour(at point: CGPoint) -> (r: Double, g: Double, b: Double, a: Double) {
            let px = min(width - 1, max(0, Int(point.x * scale)))
            let py = min(height - 1, max(0, Int(point.y * scale)))
            let i = (py * width + px) * 4
            let a = Double(rgba[i + 3]) / 255
            guard a > 0 else { return (0, 0, 0, 0) }
            return (Double(rgba[i]) / 255 / a, Double(rgba[i + 1]) / 255 / a, Double(rgba[i + 2]) / 255 / a, a)
        }

        static func rgbDistance(_ lhs: (r: Double, g: Double, b: Double, a: Double),
                                _ rhs: (r: Double, g: Double, b: Double, a: Double)) -> Double {
            sqrt(pow(lhs.r - rhs.r, 2) + pow(lhs.g - rhs.g, 2) + pow(lhs.b - rhs.b, 2))
        }

        static func rgbMean(_ colour: (r: Double, g: Double, b: Double, a: Double)) -> Double {
            (colour.r + colour.g + colour.b) / 3
        }




        func bounds(x: Range<CGFloat>, y: Range<CGFloat>? = nil, threshold: UInt8 = 64) -> CGRect? {
            let yRange = y ?? 0..<size.height
            var minX = Int.max, minY = Int.max, maxX = -1, maxY = -1
            for py in Int(yRange.lowerBound * scale)..<min(height, Int(yRange.upperBound * scale)) {
                for px in Int(x.lowerBound * scale)..<min(width, Int(x.upperBound * scale)) where alpha[py * width + px] > threshold {
                    minX = min(minX, px); maxX = max(maxX, px)
                    minY = min(minY, py); maxY = max(maxY, py)
                }
            }
            guard maxX >= 0 else { return nil }
            return CGRect(x: CGFloat(minX) / scale, y: CGFloat(minY) / scale,
                          width: CGFloat(maxX - minX + 1) / scale, height: CGFloat(maxY - minY + 1) / scale)
        }




        func firstRun(from x: CGFloat, y: Range<CGFloat>, threshold: UInt8 = 64) -> CGRect? {
            let rows = Int(y.lowerBound * scale)..<min(height, Int(y.upperBound * scale))
            func inked(_ px: Int) -> Bool { rows.contains { alpha[$0 * width + px] > threshold } }
            guard let start = (Int(x * scale)..<width).first(where: inked) else { return nil }
            var end = start
            while end + 1 < width, inked(end + 1) { end += 1 }
            return bounds(x: (CGFloat(start) / scale)..<(CGFloat(end + 1) / scale), y: y, threshold: threshold)
        }



        func differentPixelCount(from other: Ink, x: Range<CGFloat>, y: Range<CGFloat>? = nil) -> Int {
            guard width == other.width, height == other.height, scale == other.scale else { return .max }
            let yRange = y ?? 0..<size.height
            var differences = 0
            for py in Int(yRange.lowerBound * scale)..<min(height, Int(yRange.upperBound * scale)) {
                for px in Int(x.lowerBound * scale)..<min(width, Int(x.upperBound * scale)) {
                    let i = (py * width + px) * 4
                    if rgba[i..<(i + 4)] != other.rgba[i..<(i + 4)] { differences += 1 }
                }
            }
            return differences
        }
    }
}

@MainActor
private final class LayoutIntentRecorder {
    var intents: [Intent] = []
    var sink: IntentSink { { [weak self] intent in self?.intents.append(intent) } }
}



private struct P13PaneSwatch: View {
    let tone: Tone

    var body: some View {
        ZStack {
            Color(red: 0.5, green: 0.5, blue: 0.5)
            Rectangle().fill(tone.paneMaterial.material)
            tone.tint
        }
        .frame(width: 64, height: 64)
    }
}

private struct P16PaneSwatch: View {
    let tone: Tone
    let backdrop: Color

    var body: some View {
        ZStack {
            backdrop
            Rectangle().fill(tone.paneMaterial.material)
            tone.tint
        }
        .frame(width: 64, height: 64)
    }
}



private struct P16PaneTintFloorSwatch: View {
    let tint: Color
    let backdrop: Color

    var body: some View {
        ZStack { backdrop; tint }
            .frame(width: 64, height: 64)
    }
}




private struct P17BandContentSwatch: View {
    let includesBand: Bool

    var body: some View {
        ZStack(alignment: .top) {
            PaneBackdrop()
            Rectangle()
                .fill(Color.black.opacity(0.78))
                .frame(width: 40)
                .frame(maxHeight: .infinity)
            if includesBand {
                BandBackdrop()
            }
        }
        .frame(width: 128, height: Grid.band + 16)
        .clipped()
    }
}



private struct P10RegularIdentityReference: View {
    let row: UnifiedRowView
    @Environment(\.tone) private var tone

    var body: some View {
        HStack(alignment: .center, spacing: 0) {
            StateBadge(text: row.failover_state_text,
                       style: row.failover_accent ? .active : row.failover_muted ? .muted : .ready)
                .frame(width: StateBadgeLayout.columnWidth, alignment: .leading)
            Color.clear.frame(width: Grid.badgeGap)
            Text(verbatim: row.email_local + (row.has_domain ? row.email_domain : ""))
                .font(Face.body)
                .foregroundStyle(tone.text)
                .lineLimit(1)
                .truncationMode(.tail)
        }
        .frame(maxWidth: .infinity, alignment: .leading)
        .padding(.horizontal, Grid.inset)
        .frame(height: Grid.accountsRow)
    }
}


private struct ConfirmationEvidence: View {
    let pending: ProxyConfirmationGate.Pending

    var body: some View {
        VStack(alignment: .leading, spacing: Grid.fieldGap) {
            Text(verbatim: pending.title).font(Face.body)
            Text(verbatim: pending.message).font(Face.secondary)
            HStack {
                SecondaryButton(title: Copy.cancel) {}
                SecondaryButton(title: pending.confirmTitle) {}
            }
        }
        .padding(Grid.noticePadding)
    }
}
