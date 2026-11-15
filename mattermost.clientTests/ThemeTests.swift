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
            "mentionHighlightBg": "#123456"
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
            ["category": "theme", "name": "team1", "value": #"{"type":"Onyx"}"#]
        ]

        ThemeManager.shared.apply(preferences: preferences, teamId: "team1")
        XCTAssertTrue(ThemeManager.shared.theme.isDark)

        ThemeManager.shared.apply(preferences: preferences, teamId: "team2")
        XCTAssertFalse(ThemeManager.shared.theme.isDark)

        // Unknown team falls back to the global preference (Denim).
        ThemeManager.shared.apply(preferences: [], teamId: nil)
    }
}
