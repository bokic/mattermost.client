//
//  TeamAdminTests.swift
//  mattermost.clientTests
//

import AppKit
import XCTest

@testable import mattermost_client

@MainActor
final class TeamAdminTests: XCTestCase {
    private func makeWindow() -> MainWindow {
        MainWindow(
            contentRect: NSRect(x: 0, y: 0, width: 1000, height: 700),
            styleMask: [.titled, .resizable],
            backing: .buffered,
            defer: true
        )
    }

    private func makeTeam(
        id: String = "team_1",
        name: String = "engineering",
        displayName: String = "Engineering",
        inviteId: String = "inv_token_123"
    ) -> MMTeam {
        MMTeam(
            id: id,
            create_at: 1000,
            update_at: 2000,
            delete_at: 0,
            display_name: displayName,
            name: name,
            description: "Engineering Department",
            email: "eng@example.com",
            type: "O",
            company_name: "Acme",
            allowed_domains: "acme.com",
            invite_id: inviteId,
            allow_open_invite: true
        )
    }

    private func makeUser(
        id: String,
        username: String,
        firstName: String? = nil,
        lastName: String? = nil,
        roles: String? = nil
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
            email: "\(username)@example.com",
            email_verified: nil,
            auth_service: nil,
            roles: roles,
            locale: nil,
            position: nil,
            is_bot: false,
            last_password_update: nil,
            remote_id: nil,
            disable_welcome_email: nil,
            notify_props: nil,
            props: nil,
            timezone: nil,
            auth_data: nil
        )
    }

    func testTeamMenuActionEntries() {
        let window = makeWindow()
        defer { window.close() }

        window.setupLeftChannelSidebar()
        window.activeTeam = makeTeam()
        window.rebuildTeamMenu()

        // Inspect labels in teamDropdownMenu subviews
        var titles: [String] = []
        func collectLabels(in view: NSView) {
            for sub in view.subviews {
                if let tf = sub as? NSTextField {
                    titles.append(tf.stringValue)
                }
                collectLabels(in: sub)
            }
        }
        collectLabels(in: window.teamDropdownMenu)

        XCTAssertTrue(titles.contains("Invite People"))
        XCTAssertTrue(titles.contains("Team Members"))
        XCTAssertTrue(titles.contains("Team Settings"))
        XCTAssertTrue(titles.contains("Create New Team"))
        XCTAssertTrue(titles.contains("Join another team"))
        XCTAssertTrue(titles.contains("Leave Team"))
    }

    func testTeamMembersPanelRendering() {
        let window = makeWindow()
        defer { window.close() }

        let team = makeTeam()
        window.activeTeam = team
        window.usersById["u1"] = makeUser(
            id: "u1",
            username: "alice",
            firstName: "Alice",
            lastName: "Smith",
            roles: "team_admin"
        )
        window.usersById["u2"] = makeUser(
            id: "u2",
            username: "bob",
            firstName: "Bob",
            lastName: "Jones",
            roles: "team_user"
        )

        window.teamMembers = [
            MMTeamMember(
                team_id: team.id,
                user_id: "u1",
                roles: "team_user team_admin",
                delete_at: 0,
                scheme_guest: false,
                scheme_user: true,
                scheme_admin: true,
                explicit_roles: "team_admin"
            ),
            MMTeamMember(
                team_id: team.id,
                user_id: "u2",
                roles: "team_user",
                delete_at: 0,
                scheme_guest: false,
                scheme_user: true,
                scheme_admin: false,
                explicit_roles: nil
            ),
        ]

        window.renderTeamMembersPanel()

        // Collect all text from rightPanelDoc
        var textLabels: [String] = []
        func collect(in view: NSView) {
            for sub in view.subviews {
                if let tf = sub as? NSTextField {
                    textLabels.append(tf.stringValue)
                }
                collect(in: sub)
            }
        }
        collect(in: window.rightPanelDoc)

        XCTAssertTrue(textLabels.contains("Add Members"))
        XCTAssertTrue(textLabels.contains("Team Admins"))
        XCTAssertTrue(textLabels.contains("Members"))
        XCTAssertTrue(textLabels.contains("alice"))
        XCTAssertTrue(textLabels.contains("bob"))
    }

    func testTeamMembersFilterByQuery() {
        let window = makeWindow()
        defer { window.close() }

        let team = makeTeam()
        window.activeTeam = team
        window.usersById["u1"] = makeUser(
            id: "u1",
            username: "charlie",
            firstName: "Charlie",
            lastName: "Brown",
            roles: "team_user"
        )

        window.teamMembers = [
            MMTeamMember(
                team_id: team.id,
                user_id: "u1",
                roles: "team_user",
                delete_at: 0,
                scheme_guest: false,
                scheme_user: true,
                scheme_admin: false,
                explicit_roles: nil
            ),
        ]

        window.memberSearchQuery = "char"
        window.renderTeamMembersPanel()

        var textLabels: [String] = []
        func collect(in view: NSView) {
            for sub in view.subviews {
                if let tf = sub as? NSTextField {
                    textLabels.append(tf.stringValue)
                }
                collect(in: sub)
            }
        }
        collect(in: window.rightPanelDoc)

        XCTAssertTrue(textLabels.contains("Search Results"))
        XCTAssertTrue(textLabels.contains("charlie"))

        // Search non-matching query
        window.memberSearchQuery = "nonexistent"
        window.renderTeamMembersPanel()

        textLabels.removeAll()
        collect(in: window.rightPanelDoc)
        XCTAssertFalse(textLabels.contains("charlie"))
    }

    func testRightPanelModeSubtitleForTeamMembers() {
        let window = makeWindow()
        defer { window.close() }

        window.activeTeam = makeTeam(displayName: "Core Platform")
        let subtitle = window.rightPanelSubtitleText(for: .teamMembers)
        XCTAssertEqual(subtitle, "Core Platform")
    }
}
