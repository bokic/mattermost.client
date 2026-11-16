//
//  ThemeTests.swift
//  mattermost.clientTests
//

import AppKit
import XCTest

#if canImport(mattermost_client)
    @testable import mattermost_client
#endif

@MainActor
final class ThemeTests: XCTestCase {

    private func components(_ color: NSColor) -> (CGFloat, CGFloat, CGFloat) {
        let rgb = color.usingColorSpace(.sRGB) ?? color
        return (rgb.redComponent, rgb.greenComponent, rgb.blueComponent)
    }

    func testDefaultAndBuiltInDarkThemes() {
        let defaultTheme = MMTheme(json: ["type": "Mattermost"])
        XCTAssertFalse(defaultTheme.isDark)
        XCTAssertEqual(defaultTheme.typeName, "Mattermost")

        let onyx = MMTheme(json: ["type": "Onyx"])
        XCTAssertTrue(onyx.isDark)
        let center = components(onyx.centerBg)
        XCTAssertEqual(center.0, CGFloat(0x19) / 255, accuracy: 0.01)
        XCTAssertEqual(center.1, CGFloat(0x1b) / 255, accuracy: 0.01)
        XCTAssertEqual(center.2, CGFloat(0x1f) / 255, accuracy: 0.01)

        let quartz = MMTheme(json: ["type": "Quartz"])
        XCTAssertFalse(quartz.isDark)
        XCTAssertEqual(components(quartz.sidebarBg).0, CGFloat(0xf4) / 255, accuracy: 0.01)
    }

    func testCustomThemeColors() {
        let theme = MMTheme(json: [
            "type": "custom",
            "sidebarBg": "#112233",
            "sidebarText": "#abcdef",
            "centerChannelBg": "#101010",
            "centerChannelColor": "#eeeeee",
            "buttonBg": "#ff0000",
            "linkColor": "#00ff00",
            "mentionHighlightBg": "#123456",
        ])
        XCTAssertTrue(theme.isDark)
        XCTAssertEqual(components(theme.sidebarBg).0, CGFloat(0x11) / 255, accuracy: 0.01)
        XCTAssertEqual(components(theme.sidebarText).1, CGFloat(0xcd) / 255, accuracy: 0.01)
        XCTAssertEqual(components(theme.linkColor).1, 1.0, accuracy: 0.01)
        XCTAssertEqual(components(theme.mentionHighlightBg).2, CGFloat(0x56) / 255, accuracy: 0.01)
    }

    func testPreferenceSelectionUsesTeamThenGlobalTheme() {
        let preferences: [[String: String]] = [
            ["category": "theme", "name": "", "value": #"{"type":"Denim"}"#],
            ["category": "theme", "name": "team1", "value": #"{"type":"Onyx"}"#],
        ]

        ThemeManager.shared.apply(preferences: preferences, teamId: "team1")
        XCTAssertTrue(ThemeManager.shared.theme.isDark)

        ThemeManager.shared.apply(preferences: preferences, teamId: "team2")
        XCTAssertFalse(ThemeManager.shared.theme.isDark)

        // Unknown team falls back to the global preference (Denim).
        ThemeManager.shared.apply(preferences: [], teamId: nil)
    }

    func testSystemThemeFollowsSystemAppearance() {
        let preferences: [[String: String]] = [
            ["category": "theme", "name": "", "value": #"{"type":"System"}"#]
        ]
        ThemeManager.shared.apply(preferences: preferences, teamId: nil)
        XCTAssertTrue(ThemeManager.shared.usesSystemAppearance)

        ThemeManager.shared.apply(
            preferences: [["category": "theme", "name": "", "value": #"{"type":"Denim"}"#]],
            teamId: nil
        )
        XCTAssertFalse(ThemeManager.shared.usesSystemAppearance)
    }

    func testThemeOverrides() {
        let preferences: [[String: String]] = [
            ["category": "theme", "name": "", "value": #"{"type":"Denim"}"#]
        ]
        defer {
            ThemeManager.shared.themeOverride = .server
            ThemeManager.shared.apply(preferences: preferences, teamId: nil)
        }

        ThemeManager.shared.themeOverride = .light
        ThemeManager.shared.apply(preferences: preferences, teamId: nil)
        XCTAssertFalse(ThemeManager.shared.theme.isDark)
        XCTAssertFalse(ThemeManager.shared.usesSystemAppearance)

        ThemeManager.shared.themeOverride = .dark
        ThemeManager.shared.apply(preferences: preferences, teamId: nil)
        XCTAssertTrue(ThemeManager.shared.theme.isDark)
        XCTAssertFalse(ThemeManager.shared.usesSystemAppearance)

        ThemeManager.shared.themeOverride = .system
        ThemeManager.shared.apply(preferences: preferences, teamId: nil)
        XCTAssertTrue(ThemeManager.shared.usesSystemAppearance)

        ThemeManager.shared.themeOverride = .server
        ThemeManager.shared.apply(preferences: preferences, teamId: nil)
        XCTAssertFalse(ThemeManager.shared.usesSystemAppearance)
    }

    func testBuiltinSystemThemeMappingAndCustomFallback() {
        let isSystemDark =
            NSApplication.shared.effectiveAppearance.bestMatch(from: [.darkAqua, .aqua]) == .darkAqua
        let expectedBuiltin = isSystemDark ? "Onyx" : "Denim"

        let systemBuiltin = MMTheme.builtin(for: "system")
        XCTAssertNotNil(systemBuiltin)
        XCTAssertEqual(systemBuiltin?.typeName, expectedBuiltin)

        let systemTheme = MMTheme(json: ["type": "system"])
        XCTAssertEqual(systemTheme.isDark, isSystemDark)

        let customTheme = MMTheme(json: [:])
        XCTAssertEqual(customTheme.isDark, isSystemDark)
    }

    func testParseColorSupportedFormats() {
        // 4-digit hex #RGBA
        let fourDigit = MMTheme.parseColor("#f008")
        XCTAssertNotNil(fourDigit)
        let fourRgb = fourDigit?.usingColorSpace(.sRGB)
        XCTAssertEqual(fourRgb?.redComponent ?? 0, 1.0, accuracy: 0.02)
        XCTAssertEqual(fourRgb?.alphaComponent ?? 0, CGFloat(0x88) / 255.0, accuracy: 0.02)

        // CSS rgb(r, g, b)
        let rgbColor = MMTheme.parseColor("rgb(255, 128, 0)")
        XCTAssertNotNil(rgbColor)
        let rgbComp = rgbColor?.usingColorSpace(.sRGB)
        XCTAssertEqual(rgbComp?.redComponent ?? 0, 1.0, accuracy: 0.02)
        XCTAssertEqual(rgbComp?.greenComponent ?? 0, 128.0 / 255.0, accuracy: 0.02)
        XCTAssertEqual(rgbComp?.blueComponent ?? 0, 0.0, accuracy: 0.02)

        // CSS rgba(r, g, b, a)
        let rgbaColor = MMTheme.parseColor("rgba(0, 255, 128, 0.5)")
        XCTAssertNotNil(rgbaColor)
        let rgbaComp = rgbaColor?.usingColorSpace(.sRGB)
        XCTAssertEqual(rgbaComp?.greenComponent ?? 0, 1.0, accuracy: 0.02)
        XCTAssertEqual(rgbaComp?.alphaComponent ?? 0, 0.5, accuracy: 0.02)

        // Named colors
        XCTAssertEqual(MMTheme.parseColor("white"), .white)
        XCTAssertEqual(MMTheme.parseColor("black"), .black)
        XCTAssertEqual(MMTheme.parseColor("transparent"), .clear)
        XCTAssertEqual(MMTheme.parseColor("blue"), .blue)

        // Invalid fallback
        XCTAssertNil(MMTheme.parseColor("not-a-color"))
        XCTAssertNil(MMTheme.parseColor(""))
    }
}
