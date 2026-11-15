//
//  SidebarCategoryTests.swift
//  mattermost.clientTests
//

import AppKit
import XCTest

#if canImport(mattermost_client)
    @testable import mattermost_client
#endif

@MainActor
final class SidebarCategoryTests: XCTestCase {

    func testCustomCategoryDetection() {
        let window = makeWindow()
        defer { window.close() }
        XCTAssertFalse(window.isCustomSidebarCategory("favorites"))
        XCTAssertFalse(window.isCustomSidebarCategory("channels"))
        XCTAssertFalse(window.isCustomSidebarCategory("direct_messages"))
        XCTAssertFalse(window.isCustomSidebarCategory("favorites_user"))
        XCTAssertTrue(window.isCustomSidebarCategory("custom_123"))
    }

    func testCollapsedStatePersistsPerTeam() {
        let window = makeWindow()
        defer { window.close() }
        UserDefaults.standard.removeObject(forKey: window.sidebarCollapseStorageKey())
        window.setSidebarCollapsedState(true, categoryId: "custom_1")
        XCTAssertEqual(window.savedSidebarCollapsedState("custom_1"), true)
        window.setSidebarCollapsedState(false, categoryId: "custom_1")
        XCTAssertEqual(window.savedSidebarCollapsedState("custom_1"), false)
        XCTAssertNil(window.savedSidebarCollapsedState("missing"))
    }

    func testFavoritesOrderPreservesServerOrder() {
        let window = makeWindow()
        defer { window.close() }
        let chA = MMChannel(id: "ch_a", create_at: 0, update_at: 0, delete_at: 0, team_id: "t1", type: "O", display_name: "Alpha", name: "alpha", header: nil, purpose: nil, last_post_at: 0, total_msg_count: 0, creator_id: nil)
        let chZ = MMChannel(id: "ch_z", create_at: 0, update_at: 0, delete_at: 0, team_id: "t1", type: "O", display_name: "Zulu", name: "zulu", header: nil, purpose: nil, last_post_at: 0, total_msg_count: 0, creator_id: nil)
        window.channelsById = ["ch_a": chA, "ch_z": chZ]
        window.favoriteChannelOrder = ["ch_z", "ch_a"]
        window.favoriteChannelIds = ["ch_z", "ch_a"]
        window.rebuildFavoritesCategory()
        XCTAssertEqual(window.favoritesCategory?.items.map(\.id), ["ch_z", "ch_a"])
    }

    func testBotRowTintWithoutCustomAvatar() {
        let window = makeWindow()
        defer { window.close() }
        let botItem = window.createSidebarItem(
            id: "bot_1",
            symbolName: "cpu",
            title: "bot",
            isSelectable: true,
            isBotBadge: true,
            showsCloseOnHover: false,
            customImage: nil
        )
        XCTAssertTrue(botItem.isBotBadge)
        XCTAssertFalse(botItem.hasCustomAvatar)
        window.sidebarCategories = [window.createSidebarCategory(id: "c1", title: "C", showsAddButton: false, items: [botItem])]
        window.selectedSidebarItemId = "bot_1"
        window.updateSidebarSelectionAppearance()
        XCTAssertEqual(botItem.iconView.contentTintColor, Theme.shared.sidebarActiveColor)
    }

    func testBadgeOffsetWithDMCloseView() {
        let window = makeWindow()
        defer { window.close() }
        let itemWithClose = window.createSidebarItem(
            id: "dm_1",
            symbolName: "person.fill",
            title: "user",
            isSelectable: true,
            isBotBadge: false,
            showsCloseOnHover: true,
            customImage: nil
        )
        let itemWithoutClose = window.createSidebarItem(
            id: "ch_1",
            symbolName: "globe",
            title: "general",
            isSelectable: true,
            isBotBadge: false,
            showsCloseOnHover: false,
            customImage: nil
        )
        window.sidebarCategories = [
            window.createSidebarCategory(id: "cat", title: "Cat", showsAddButton: false, items: [itemWithClose, itemWithoutClose])
        ]
        window.unreadByChannel = ["dm_1": 5, "ch_1": 3]
        window.updateSidebarBadges()

        XCTAssertNotNil(itemWithClose.hoverCloseView)
        XCTAssertNil(itemWithoutClose.hoverCloseView)
        XCTAssertLessThan(itemWithClose.badgePanel.frame.minX, itemWithoutClose.badgePanel.frame.minX)
    }

    func testThreadsRowSelectionState() {
        let window = makeWindow()
        defer { window.close() }
        window.setupLeftChannelSidebar()
        guard let threadsItem = window.threadsSidebarItem else {
            XCTFail("Missing threadsSidebarItem")
            return
        }
        threadsItem.row.onClick?()
        XCTAssertEqual(window.selectedSidebarItemId, "threads")
        XCTAssertTrue(window.isRightPanelVisible)
        XCTAssertEqual(window.rightPanelMode, .threads)

        window.closeRightPanel()
        XCTAssertNotEqual(window.selectedSidebarItemId, "threads")
    }

    func testBadgeColorParity() {
        let window = makeWindow()
        defer { window.close() }
        let item = window.createSidebarItem(
            id: "ch_badge",
            symbolName: "globe",
            title: "channel",
            isSelectable: true,
            isBotBadge: false,
            showsCloseOnHover: false
        )
        window.sidebarCategories = [window.createSidebarCategory(id: "c", title: "C", showsAddButton: false, items: [item])]
        // Mention badge
        window.mentionsByChannel = ["ch_badge": 2]
        window.updateSidebarBadges()
        XCTAssertEqual(item.badgePanel.color, Theme.shared.mentionBg)
        XCTAssertEqual(item.badgeLabel.textColor, Theme.shared.mentionColor)

        // Unread badge
        window.mentionsByChannel = [:]
        window.unreadByChannel = ["ch_badge": 4]
        window.updateSidebarBadges()
        XCTAssertEqual(item.badgeLabel.textColor, Theme.shared.sidebarUnreadText)
    }

    func testTeamHeaderLabelClampedToAvoidOverlap() {
        let window = makeWindow()
        defer { window.close() }
        window.setupLeftChannelSidebar()
        let team = MMTeam(
            id: "t_long",
            create_at: 0,
            update_at: 0,
            delete_at: 0,
            display_name: "A Very Long Team Name That Exceeds Width Limit",
            name: "long-team",
            description: nil,
            email: nil,
            type: "O",
            company_name: nil,
            allowed_domains: nil,
            invite_id: nil,
            allow_open_invite: nil
        )
        window.updateTeamHeader(with: team)
        XCTAssertLessThanOrEqual(window.teamHeaderLabel.frame.width, 168)
        XCTAssertLessThan(window.teamHeaderButton.frame.maxX, window.teamAddButton.frame.minX)
    }

    func testTeamDropdownMenuThemed() {
        let window = makeWindow()
        defer { window.close() }
        window.setupLeftChannelSidebar()
        window.rebuildTeamMenu()
        XCTAssertEqual(window.teamDropdownMenu.color, Theme.shared.centerBg)
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
