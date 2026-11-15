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

    func testApplyServerCustomStatusSetsLocalStatus() {
        let window = makeWindow()
        defer {
            window.clearLocalCustomStatus()
            window.close()
        }

        let future = ISO8601DateFormatter().string(from: Date().addingTimeInterval(3600))
        let userJson = """
        {
            "id": "u1",
            "username": "bob",
            "props": {
                "customStatus": "{\\\"emoji\\\":\\\"calendar\\\",\\\"text\\\":\\\"In a meeting\\\",\\\"expires_at\\\":\\\"\(future)\\\"}"
            }
        }
        """.data(using: .utf8)!
        let user = try! JSONDecoder().decode(MMUser.self, from: userJson)

        window.applyServerCustomStatus(from: user)
        XCTAssertEqual(window.customStatusText, "In a meeting")
        XCTAssertEqual(window.customStatusEmoji, "calendar")
        XCTAssertNotNil(window.customStatusExpiresAt)
        XCTAssertEqual(UserDefaults.standard.string(forKey: "customStatusText"), "In a meeting")
        XCTAssertEqual(UserDefaults.standard.string(forKey: "customStatusEmoji"), "calendar")
    }

    func testApplyServerCustomStatusClearsLocalStatusWhenMissingOrEmpty() {
        let window = makeWindow()
        defer {
            window.clearLocalCustomStatus()
            window.close()
        }

        window.customStatusText = "Busy"
        window.customStatusEmoji = "calendar"
        UserDefaults.standard.set("Busy", forKey: "customStatusText")
        UserDefaults.standard.set("calendar", forKey: "customStatusEmoji")

        let userJson = """
        {
            "id": "u1",
            "username": "bob",
            "props": {}
        }
        """.data(using: .utf8)!
        let user = try! JSONDecoder().decode(MMUser.self, from: userJson)

        window.applyServerCustomStatus(from: user)
        XCTAssertEqual(window.customStatusText, "")
        XCTAssertEqual(window.customStatusEmoji, "")
        XCTAssertNil(window.customStatusExpiresAt)
        XCTAssertNil(UserDefaults.standard.string(forKey: "customStatusText"))
        XCTAssertNil(UserDefaults.standard.string(forKey: "customStatusEmoji"))
    }

    func testApplyServerCustomStatusClearsWhenExpired() {
        let window = makeWindow()
        defer {
            window.clearLocalCustomStatus()
            window.close()
        }

        window.customStatusText = "Past Status"
        window.customStatusEmoji = "palm_tree"

        let past = ISO8601DateFormatter().string(from: Date().addingTimeInterval(-3600))
        let userJson = """
        {
            "id": "u1",
            "username": "bob",
            "props": {
                "customStatus": "{\\\"emoji\\\":\\\"palm_tree\\\",\\\"text\\\":\\\"Past Status\\\",\\\"expires_at\\\":\\\"\(past)\\\"}"
            }
        }
        """.data(using: .utf8)!
        let user = try! JSONDecoder().decode(MMUser.self, from: userJson)

        window.applyServerCustomStatus(from: user)
        XCTAssertEqual(window.customStatusText, "")
        XCTAssertEqual(window.customStatusEmoji, "")
        XCTAssertNil(window.customStatusExpiresAt)
    }

    func testCustomStatusTargetDateAndExpiryForPresetsAndCustomDate() {
        let window = makeWindow()
        defer { window.close() }

        XNil: do {
            XCTAssertNil(window.customStatusTargetDate(for: 0))
            XCTAssertNil(window.customStatusExpiry(for: 0))
        }

        let thirtyMins = window.customStatusTargetDate(for: 1)
        XCTAssertNotNil(thirtyMins)
        XCTAssertGreaterThan(thirtyMins!.timeIntervalSinceNow, 25 * 60)

        let customDate = Date(timeIntervalSince1970: 1_700_000_000)
        let targetCustom = window.customStatusTargetDate(for: 6, customDate: customDate)
        XCTAssertEqual(targetCustom, customDate)

        let expiryCustom = window.customStatusExpiry(for: 6, customDate: customDate)
        let formatter = ISO8601DateFormatter()
        formatter.formatOptions = [.withInternetDateTime]
        XCTAssertEqual(expiryCustom, formatter.string(from: customDate))
    }

    func testRecentCustomStatusesStorageAndDeduplication() {
        let window = makeWindow()
        defer {
            UserDefaults.standard.removeObject(forKey: "recentCustomStatuses")
            window.close()
        }

        UserDefaults.standard.removeObject(forKey: "recentCustomStatuses")

        window.saveRecentCustomStatus(emoji: "💬", text: "Status 1", durationIndex: 1)
        window.saveRecentCustomStatus(emoji: "📅", text: "Status 2", durationIndex: 2)
        window.saveRecentCustomStatus(emoji: "🌴", text: "Status 3", durationIndex: 3)
        window.saveRecentCustomStatus(emoji: "🤒", text: "Status 4", durationIndex: 4)
        window.saveRecentCustomStatus(emoji: "🚗", text: "Status 5", durationIndex: 5)
        window.saveRecentCustomStatus(emoji: "🚀", text: "Status 6", durationIndex: 6)

        let recents = window.recentCustomStatuses()
        XCTAssertEqual(recents.count, 5)
        XCTAssertEqual(recents.first?.text, "Status 6")
        XCTAssertFalse(recents.contains(where: { $0.text == "Status 1" }))

        // Deduplication & moving to front
        window.saveRecentCustomStatus(emoji: "🎯", text: "Status 4", durationIndex: 1)
        let updatedRecents = window.recentCustomStatuses()
        XCTAssertEqual(updatedRecents.count, 5)
        XCTAssertEqual(updatedRecents.first?.text, "Status 4")
        XCTAssertEqual(updatedRecents.first?.emoji, "🎯")
    }

    func testNormalizeCustomStatusEmoji() {
        let window = makeWindow()
        defer { window.close() }

        XCTAssertEqual(window.normalizeCustomStatusEmoji("💬"), "speech_balloon")
        XCTAssertEqual(window.normalizeCustomStatusEmoji(":calendar:"), "calendar")
        XCTAssertEqual(window.normalizeCustomStatusEmoji("calendar"), "calendar")
        XCTAssertEqual(window.normalizeCustomStatusEmoji("custom_nonexistent"), "custom_nonexistent")
    }

    func testCustomStatusDialogHelperActions() {
        let window = makeWindow()
        defer { window.close() }

        let helper = CustomStatusDialogHelper()
        helper.mainWindow = window

        let emojiField = NSTextField()
        let textField = NSTextField()
        let durationPopup = NSPopUpButton(frame: .zero, pullsDown: false)
        durationPopup.addItems(withTitles: ["0", "1", "2", "3", "4", "5", "6"])
        let datePicker = NSDatePicker()
        datePicker.isHidden = true

        helper.emojiField = emojiField
        helper.textField = textField
        helper.durationPopup = durationPopup
        helper.datePicker = datePicker

        // durationChanged toggles datePicker visibility
        durationPopup.selectItem(at: 6)
        helper.durationChanged(durationPopup)
        XCTAssertFalse(datePicker.isHidden)

        durationPopup.selectItem(at: 2)
        helper.durationChanged(durationPopup)
        XCTAssertTrue(datePicker.isHidden)

        // suggestionSelected applies preset
        let menuItem = NSMenuItem()
        let item = CustomStatusItem(emoji: "calendar", text: "Meeting", durationIndex: 2)
        menuItem.representedObject = item
        helper.suggestionSelected(menuItem)

        XCTAssertEqual(emojiField.stringValue, window.emojiGlyph(for: "calendar"))
        XCTAssertEqual(textField.stringValue, "Meeting")
        XCTAssertEqual(durationPopup.indexOfSelectedItem, 2)
        XCTAssertTrue(datePicker.isHidden)
    }

    func testExistingDMChannelLookup() {
        let window = makeWindow()
        defer { window.close() }

        let userJson = """
        {"id": "myUser", "username": "me"}
        """.data(using: .utf8)!
        window.currentUser = try! JSONDecoder().decode(MMUser.self, from: userJson)

        let chJson = """
        {"id": "dm1", "type": "D", "name": "myUser__otherUser", "display_name": "otherUser"}
        """.data(using: .utf8)!
        let ch = try! JSONDecoder().decode(MMChannel.self, from: chJson)
        window.channelsById[ch.id] = ch

        XCTAssertEqual(window.existingDMChannel(for: "otherUser")?.id, "dm1")
        XCTAssertNil(window.existingDMChannel(for: "nonexistentUser"))
    }

    func testUserBadgeString() {
        let window = makeWindow()
        defer { window.close() }

        let botJson = """
        {"id": "b1", "username": "botty", "is_bot": true}
        """.data(using: .utf8)!
        let bot = try! JSONDecoder().decode(MMUser.self, from: botJson)
        XCTAssertEqual(window.userBadgeString(for: bot), "BOT")

        let guestJson = """
        {"id": "g1", "username": "guest_user", "roles": "system_guest"}
        """.data(using: .utf8)!
        let guest = try! JSONDecoder().decode(MMUser.self, from: guestJson)
        XCTAssertEqual(window.userBadgeString(for: guest), "GUEST")

        let regularJson = """
        {"id": "u1", "username": "alice", "roles": "system_user"}
        """.data(using: .utf8)!
        let regular = try! JSONDecoder().decode(MMUser.self, from: regularJson)
        XCTAssertNil(window.userBadgeString(for: regular))
    }

    func testInvalidateDMUsers() {
        let window = makeWindow()
        defer { window.close() }

        let u1 = try! JSONDecoder().decode(MMUser.self, from: "{\"id\":\"u1\",\"username\":\"alice\"}".data(using: .utf8)!)
        window.dmUsers = [u1]
        window.dmSearchResults = [u1]
        window.selectedDMUserIds = ["u1"]
        window.dmUsersPage = 3
        window.dmHasMoreUsers = false

        window.invalidateDMUsers()

        XCTAssertTrue(window.dmUsers.isEmpty)
        XCTAssertTrue(window.dmSearchResults.isEmpty)
        XCTAssertTrue(window.selectedDMUserIds.isEmpty)
        XCTAssertEqual(window.dmUsersPage, 0)
        XCTAssertTrue(window.dmHasMoreUsers)
    }

    func testTeamSwitchInvalidatesDMUsers() {
        let window = makeWindow()
        defer { window.close() }

        let teamA = try! JSONDecoder().decode(MMTeam.self, from: "{\"id\":\"tA\",\"name\":\"team-a\",\"display_name\":\"Team A\"}".data(using: .utf8)!)
        let teamB = try! JSONDecoder().decode(MMTeam.self, from: "{\"id\":\"tB\",\"name\":\"team-b\",\"display_name\":\"Team B\"}".data(using: .utf8)!)

        window.activeTeam = teamA
        let u1 = try! JSONDecoder().decode(MMUser.self, from: "{\"id\":\"u1\",\"username\":\"alice\"}".data(using: .utf8)!)
        window.dmUsers = [u1]

        window.updateTeamHeader(with: teamB)
        XCTAssertTrue(window.dmUsers.isEmpty)
    }

    func testUpdateDMStartButtonState() {
        let window = makeWindow()
        defer { window.close() }

        window.selectedDMUserIds.removeAll()
        window.updateDMStartButtonState()
        XCTAssertEqual(window.dmSelectionCountLabel.stringValue, "Select members")
        XCTAssertEqual(window.dmStartButtonLabel.stringValue, "Go")

        window.selectedDMUserIds = ["u1"]
        window.updateDMStartButtonState()
        XCTAssertEqual(window.dmSelectionCountLabel.stringValue, "1 member selected")
        XCTAssertEqual(window.dmStartButtonLabel.stringValue, "Go")

        window.selectedDMUserIds = ["u1", "u2", "u3"]
        window.updateDMStartButtonState()
        XCTAssertEqual(window.dmSelectionCountLabel.stringValue, "3 members (up to 7)")
        XCTAssertEqual(window.dmStartButtonLabel.stringValue, "Go (3)")
    }

    func testBrowseChannelsPrivateChannelDiscoveryAndJoinRequestState() {
        let window = makeWindow()
        defer { window.close() }

        let team = try! JSONDecoder().decode(MMTeam.self, from: "{\"id\":\"t1\",\"name\":\"team-one\",\"display_name\":\"Team One\"}".data(using: .utf8)!)
        window.activeTeam = team

        let pubCh = try! JSONDecoder().decode(MMChannel.self, from: "{\"id\":\"chPub\",\"team_id\":\"t1\",\"type\":\"O\",\"display_name\":\"Town Square\",\"name\":\"town-square\"}".data(using: .utf8)!)
        let privChJoined = try! JSONDecoder().decode(MMChannel.self, from: "{\"id\":\"chPriv1\",\"team_id\":\"t1\",\"type\":\"P\",\"display_name\":\"Executives\",\"name\":\"executives\"}".data(using: .utf8)!)
        let privChUnjoined = try! JSONDecoder().decode(MMChannel.self, from: "{\"id\":\"chPriv2\",\"team_id\":\"t1\",\"type\":\"P\",\"display_name\":\"Secret Ops\",\"name\":\"secret-ops\"}".data(using: .utf8)!)

        window.channelsById[pubCh.id] = pubCh
        window.channelsById[privChJoined.id] = privChJoined

        // Verify pending state tracking
        XCTAssertFalse(window.pendingJoinRequestChannelIds.contains(privChUnjoined.id))
        window.pendingJoinRequestChannelIds.insert(privChUnjoined.id)
        XCTAssertTrue(window.pendingJoinRequestChannelIds.contains(privChUnjoined.id))

        // Right panel row rendering tests
        window.rightPanelMode = .browse
        let isJoined = window.channelsById.keys.contains(privChJoined.id)
        XCTAssertTrue(isJoined)

        let isUnjoinedPending = window.pendingJoinRequestChannelIds.contains(privChUnjoined.id)
        XCTAssertTrue(isUnjoinedPending)
    }
}
