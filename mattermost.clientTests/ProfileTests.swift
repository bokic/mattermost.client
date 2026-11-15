//
//  ProfileTests.swift
//  mattermost.clientTests
//

import AppKit
import XCTest

#if canImport(mattermost_client)
    @testable import mattermost_client
#endif

@MainActor
final class ProfileTests: XCTestCase {

    func testFormattedLocalTime() {
        let autoTz = MMUser.MMTimeZone(
            useAutomaticTimezone: "true",
            manualTimezone: "",
            automaticTimezone: "UTC"
        )
        let result = MainWindow.formattedLocalTime(for: autoTz)
        XCTAssertNotNil(result)
        XCTAssertTrue(result?.tzName == "UTC" || result?.tzName == "GMT")
        XCTAssertFalse(result?.timeString.isEmpty ?? true)

        let manualTz = MMUser.MMTimeZone(
            useAutomaticTimezone: "false",
            manualTimezone: "America/New_York",
            automaticTimezone: ""
        )
        let manualResult = MainWindow.formattedLocalTime(for: manualTz)
        XCTAssertNotNil(manualResult)

        let invalidTz = MMUser.MMTimeZone(
            useAutomaticTimezone: "false",
            manualTimezone: "Invalid/Not_A_Timezone",
            automaticTimezone: ""
        )
        XCTAssertNil(MainWindow.formattedLocalTime(for: invalidTz))
        XCTAssertNil(MainWindow.formattedLocalTime(for: nil))
    }

    func testDisplayRoleName() {
        let window = makeWindow()
        defer { window.close() }

        let botUser = makeUser(id: "u1", username: "botuser", roles: "system_user", isBot: true)
        XCTAssertEqual(window.displayRoleName(for: botUser), "BOT")

        let adminUser = makeUser(id: "u2", username: "admin", roles: "system_admin system_user")
        XCTAssertEqual(window.displayRoleName(for: adminUser), "SYSTEM ADMIN")

        let teamAdmin = makeUser(id: "u3", username: "teamadmin", roles: "team_admin")
        XCTAssertEqual(window.displayRoleName(for: teamAdmin), "TEAM ADMIN")

        let regularUser = makeUser(id: "u4", username: "regular", roles: "system_user")
        XCTAssertNil(window.displayRoleName(for: regularUser))
    }

    func testUserCustomStatus() {
        let window = makeWindow()
        defer { window.close() }

        var user = makeUser(id: "u1", username: "alice")
        user.props = ["customStatus": "{\"emoji\":\"calendar\",\"text\":\"In a meeting\"}"]
        let status = window.userCustomStatus(for: user)
        XCTAssertEqual(status?.emoji, "calendar")
        XCTAssertEqual(status?.text, "In a meeting")

        // Expired custom status returns nil
        let pastDate = ISO8601DateFormatter().string(from: Date().addingTimeInterval(-3600))
        user.props = ["customStatus": "{\"emoji\":\"beach_umbrella\",\"text\":\"Vacation\",\"expires_at\":\"\(pastDate)\"}"]
        XCTAssertNil(window.userCustomStatus(for: user))
    }

    func testShowAndCloseUserProfile() {
        let window = makeWindow()
        defer { window.close() }

        let user = makeUser(
            id: "u1",
            username: "johndoe",
            firstName: "John",
            lastName: "Doe",
            position: "Software Engineer",
            email: "john@example.com"
        )
        window.usersById[user.id] = user

        XCTAssertFalse(window.isProfilePopoverOpen)
        window.showUserProfile(user: user)

        XCTAssertTrue(window.isProfilePopoverOpen)
        XCTAssertFalse(window.profilePopoverPanel.isHidden)
        XCTAssertEqual(window.activeProfileUserId, "u1")

        // Calling closeTopOverlay dismisses the profile popover
        let handled = window.closeTopOverlay()
        XCTAssertTrue(handled)
        XCTAssertFalse(window.isProfilePopoverOpen)
        XCTAssertTrue(window.profilePopoverPanel.isHidden)
    }

    func testCopyUsernameToPasteboard() {
        let window = makeWindow()
        defer { window.close() }

        let user = makeUser(id: "u1", username: "testuser")
        window.showUserProfile(user: user)

        // Find the copy username button in profilePopoverPanel subviews
        let copyBtn = window.profilePopoverPanel.subviews
            .compactMap { $0 as? RoundedEdgePanel }
            .first { $0.accessibilityTitle == "Copy username" }
        XCTAssertNotNil(copyBtn)

        copyBtn?.onClick?()
        let copied = NSPasteboard.general.string(forType: .string)
        XCTAssertEqual(copied, "@testuser")
    }

    func testStatusMenuProfileRowOpensProfile() {
        let window = makeWindow()
        defer { window.close() }

        let me = makeUser(id: "me123", username: "current_user")
        window.currentUser = me
        window.setupStatusMenu()

        // Find the Profile row in statusMenu subviews
        let profileRow = window.statusMenu.subviews
            .compactMap { $0 as? RoundedEdgePanel }
            .first { row in
                row.subviews.compactMap { $0 as? NSTextField }.contains { $0.stringValue == "Profile" }
            }
        XCTAssertNotNil(profileRow)

        profileRow?.onClick?()
        XCTAssertTrue(window.isProfilePopoverOpen)
        XCTAssertEqual(window.activeProfileUserId, "me123")
    }

    func testMemberRowClickOpensProfile() {
        let window = makeWindow()
        defer { window.close() }

        let memberUser = makeUser(id: "mem1", username: "member1", firstName: "Alice", lastName: "Smith")
        window.usersById[memberUser.id] = memberUser

        let member = MMChannelMember(
            user_id: "mem1",
            channel_id: "c1",
            roles: "channel_user"
        )
        window.channelMembers = [member]
        window.renderMembersPanel()

        // The first row view in rightPanelDoc is the member row
        let row = window.rightPanelDoc.subviews.compactMap { $0 as? RoundedEdgePanel }.first
        XCTAssertNotNil(row)

        row?.onClick?()
        XCTAssertTrue(window.isProfilePopoverOpen)
        XCTAssertEqual(window.activeProfileUserId, "mem1")
    }

    func testBuildUserEndpointURL() {
        let ws = WebService(host: "chat.example.com", port: 8065)
        let url = ws.buildURL(path: "/api/v4/users/u123")
        XCTAssertEqual(url?.absoluteString, "https://chat.example.com:8065/api/v4/users/u123")
    }

    private func makeUser(
        id: String,
        username: String,
        firstName: String? = nil,
        lastName: String? = nil,
        roles: String? = nil,
        position: String? = nil,
        email: String? = nil,
        isBot: Bool? = nil
    ) -> MMUser {
        MMUser(
            id: id,
            create_at: nil,
            update_at: nil,
            delete_at: nil,
            username: username,
            first_name: firstName,
            last_name: lastName,
            nickname: nil,
            email: email,
            email_verified: nil,
            auth_service: nil,
            roles: roles,
            locale: nil,
            position: position,
            is_bot: isBot,
            last_password_update: nil,
            remote_id: nil,
            disable_welcome_email: nil,
            notify_props: nil,
            props: nil,
            timezone: nil,
            auth_data: nil
        )
    }

    private func makeWindow() -> MainWindow {
        MainWindow(
            contentRect: NSRect(x: 0, y: 0, width: 1000, height: 700),
            styleMask: [.titled, .resizable],
            backing: .buffered,
            defer: true
        )
    }
}
