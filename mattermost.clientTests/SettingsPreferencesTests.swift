//
//  SettingsPreferencesTests.swift
//  mattermost.clientTests
//

import AppKit
import XCTest

#if canImport(mattermost_client)
    @testable import mattermost_client
#endif

@MainActor
final class SettingsPreferencesTests: XCTestCase {

    private func makeWindow() -> MainWindow {
        MainWindow(
            contentRect: NSRect(x: 0, y: 0, width: 1000, height: 700),
            styleMask: [.titled, .resizable],
            backing: .buffered,
            defer: true
        )
    }

    private func makeChannel(id: String, displayName: String, type: String = "O") -> MMChannel {
        let json = """
        {"id": "\(id)", "type": "\(type)", "display_name": "\(displayName)", "name": "\(displayName.lowercased())"}
        """.data(using: .utf8)!
        return try! JSONDecoder().decode(MMChannel.self, from: json)
    }

    private func makeMembership(channelId: String, desktop: String? = nil, markUnread: String? = nil) -> MMChannelMembership {
        var notifyDict: [String: String] = [:]
        if let desktop = desktop { notifyDict["desktop"] = desktop }
        if let markUnread = markUnread { notifyDict["mark_unread"] = markUnread }
        let notifyJSON = (try? JSONSerialization.data(withJSONObject: notifyDict)) ?? Data()
        let notifyStr = String(data: notifyJSON, encoding: .utf8) ?? "{}"

        let json = """
        {"channel_id": "\(channelId)", "notify_props": \(notifyStr)}
        """.data(using: .utf8)!
        return try! JSONDecoder().decode(MMChannelMembership.self, from: json)
    }

    private func allTextFieldStrings(in view: NSView) -> [String] {
        var strings: [String] = []
        if let tf = view as? NSTextField {
            strings.append(tf.stringValue)
        }
        for subview in view.subviews {
            strings.append(contentsOf: allTextFieldStrings(in: subview))
        }
        return strings
    }

    func testAllMutedChannelIdsAggregatesAndSorts() {
        let window = makeWindow()
        defer { window.close() }

        let chA = makeChannel(id: "chA", displayName: "Alpha")
        let chB = makeChannel(id: "chB", displayName: "Bravo")
        let chC = makeChannel(id: "chC", displayName: "Charlie")
        let chD = makeChannel(id: "chD", displayName: "Delta")

        window.channelsById = [
            "chA": chA,
            "chB": chB,
            "chC": chC,
            "chD": chD
        ]

        // chC is in mutedChannelIds
        window.mutedChannelIds.insert("chC")

        // chA is muted via channelDesktopNotificationByChannel
        window.channelDesktopNotificationByChannel["chA"] = "none"

        // chB is muted via membershipsByChannel notify_props
        window.membershipsByChannel["chB"] = makeMembership(channelId: "chB", desktop: "none")

        // chD is default/unmuted
        window.membershipsByChannel["chD"] = makeMembership(channelId: "chD", desktop: "default")

        let muted = window.allMutedChannelIds()
        XCTAssertEqual(muted, ["chA", "chB", "chC"])
    }

    func testSettingsPanelBuildsSectionsAndMutedChannelsList() {
        let window = makeWindow()
        defer { window.close() }

        let ch1 = makeChannel(id: "c1", displayName: "Project X", type: "P")
        window.channelsById = ["c1": ch1]
        window.mutedChannelIds.insert("c1")

        let userJson = """
        {"id": "u1", "username": "tester", "email": "tester@example.com", "notify_props": {"mention_keys": "urgent, review", "desktop": "mention", "desktop_sound": "true"}}
        """.data(using: .utf8)!
        window.currentUser = try! JSONDecoder().decode(MMUser.self, from: userJson)

        window.loadSettingsPanel()

        let allLabels = allTextFieldStrings(in: window.rightPanelDoc)

        XCTAssertTrue(allLabels.contains("ACCOUNT & CONNECTION"))
        XCTAssertTrue(allLabels.contains("NOTIFICATIONS & MUTE"))
        XCTAssertTrue(allLabels.contains("MUTED CHANNELS"))
        XCTAssertTrue(allLabels.contains("APPEARANCE"))
        XCTAssertTrue(allLabels.contains("PRIVACY & MEDIA"))
        XCTAssertTrue(allLabels.contains("SESSION & DIAGNOSTICS"))

        XCTAssertTrue(allLabels.contains("Project X"))
        XCTAssertTrue(allLabels.contains("Unmute"))
        XCTAssertTrue(allLabels.contains("Mention keys"))
        XCTAssertTrue(allLabels.contains("urgent, review"))
        XCTAssertTrue(allLabels.contains("Theme override"))
        XCTAssertTrue(allLabels.contains("Connection details"))
    }

    func testSettingsPanelEmptyMutedChannelsPlaceholder() {
        let window = makeWindow()
        defer { window.close() }

        window.mutedChannelIds.removeAll()
        window.channelDesktopNotificationByChannel.removeAll()
        window.membershipsByChannel.removeAll()

        window.loadSettingsPanel()

        let allLabels = allTextFieldStrings(in: window.rightPanelDoc)
        XCTAssertTrue(allLabels.contains("No muted channels"))
    }

    func testUnmutingChannelUpdatesMutedList() {
        let window = makeWindow()
        defer { window.close() }

        window.mutedChannelIds.insert("ch_test")
        XCTAssertTrue(window.isChannelMuted("ch_test"))
        XCTAssertTrue(window.allMutedChannelIds().contains("ch_test"))

        window.setChannelNotificationPreference(channelId: "ch_test", desktop: "default")
        XCTAssertFalse(window.isChannelMuted("ch_test"))
        XCTAssertFalse(window.allMutedChannelIds().contains("ch_test"))
    }

    func testThemeOverrideCycle() {
        let original = ThemeManager.shared.themeOverride
        defer { ThemeManager.shared.themeOverride = original }

        ThemeManager.shared.themeOverride = .server
        XCTAssertEqual(ThemeOverride.allCases.count, 4)
        XCTAssertEqual(ThemeOverride.server.displayName, "Server (Default)")
        XCTAssertEqual(ThemeOverride.system.displayName, "System (macOS)")
        XCTAssertEqual(ThemeOverride.light.displayName, "Light (Denim)")
        XCTAssertEqual(ThemeOverride.dark.displayName, "Dark (Onyx)")

        let window = makeWindow()
        defer { window.close() }

        window.cycleThemeOverride()
        XCTAssertEqual(ThemeManager.shared.themeOverride, .system)

        window.cycleThemeOverride()
        XCTAssertEqual(ThemeManager.shared.themeOverride, .light)

        window.cycleThemeOverride()
        XCTAssertEqual(ThemeManager.shared.themeOverride, .dark)

        window.cycleThemeOverride()
        XCTAssertEqual(ThemeManager.shared.themeOverride, .server)
    }

    func testWebServiceWebSocketURL() {
        let ws = WebService(host: "example.com", port: 443)
        XCTAssertEqual(ws.webSocketURL?.absoluteString, "wss://example.com:443/api/v4/websocket")

        let wsHttp = WebService(host: "http://localhost", port: 8065)
        XCTAssertEqual(wsHttp.webSocketURL?.absoluteString, "ws://localhost:8065/api/v4/websocket")
    }

    func testAppVersionString() {
        XCTAssertFalse(AppVersion.versionString.isEmpty)
    }

    func testNativeControlsAppearanceFollowsTheme() {
        let window = makeWindow()
        defer {
            window.close()
            ThemeManager.shared.themeOverride = .server
            window.applyCurrentTheme()
        }

        // Forced dark override
        ThemeManager.shared.themeOverride = .dark
        window.applyCurrentTheme()
        XCTAssertEqual(window.appearance?.name, .darkAqua)
        XCTAssertEqual(NSApp.appearance?.name, .darkAqua)
        XCTAssertEqual(window.teamHeaderButton.color, Theme.shared.sidebarHeaderBg)
        XCTAssertEqual(window.teamHeaderLabel.textColor, Theme.shared.sidebarHeaderText)

        // Forced light override
        ThemeManager.shared.themeOverride = .light
        window.applyCurrentTheme()
        XCTAssertEqual(window.appearance?.name, .aqua)
        XCTAssertEqual(NSApp.appearance?.name, .aqua)

        // System appearance
        ThemeManager.shared.themeOverride = .system
        window.applyCurrentTheme()
        XCTAssertNil(window.appearance)
        XCTAssertNil(NSApp.appearance)
    }

    func testNewMessagesDividerUsesThemeSeparator() {
        let window = makeWindow()
        defer { window.close() }

        let divider = window.createNewMessagesDivider(width: 400)
        let labels = allTextFieldStrings(in: divider)
        XCTAssertTrue(labels.contains("New Messages"))
    }

    func testPostRowMentionHighlightColor() {
        let window = makeWindow()
        defer { window.close() }

        let userJson = """
        {"id": "user123", "username": "alice"}
        """.data(using: .utf8)!
        window.currentUser = try! JSONDecoder().decode(MMUser.self, from: userJson)

        let postJson = """
        {"id": "p1", "create_at": 100000, "channel_id": "c1", "user_id": "user456", "message": "Hey @alice check this out"}
        """.data(using: .utf8)!
        let post = try! JSONDecoder().decode(MMPost.self, from: postJson)

        let (rowView, _) = window.createPostRow(post: post, width: 600, timeStr: "12:00 PM")
        guard let panel = rowView as? RoundedEdgePanel else {
            XCTFail("Expected post row to be RoundedEdgePanel")
            return
        }
        XCTAssertNotEqual(panel.color, .clear)
    }
}
