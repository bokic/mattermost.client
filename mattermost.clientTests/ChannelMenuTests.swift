//
//  ChannelMenuTests.swift
//  mattermost.clientTests
//

import AppKit
import XCTest

#if canImport(mattermost_client)
    @testable import mattermost_client
#endif

@MainActor
final class ChannelMenuTests: XCTestCase {

    func testMuteStateUsesOverridesAndMutedIds() {
        let window = makeWindow()
        defer { window.close() }
        window.channelDesktopNotificationByChannel["channel"] = "none"
        XCTAssertTrue(window.isChannelMuted("channel"))

        window.channelDesktopNotificationByChannel["channel"] = "default"
        XCTAssertFalse(window.isChannelMuted("channel"))

        window.mutedChannelIds.insert("channel")
        XCTAssertTrue(window.isChannelMuted("channel"))
    }

    func testUnreadFilterAndFavoritesAreMutuallyExclusiveInMenuState() {
        let window = makeWindow()
        defer { window.close() }
        window.sidebarUnreadOnly = true
        window.sidebarFavoritesOnly = false
        window.updateFilterMenuAppearance()
        XCTAssertEqual(window.filterUnreadCheck?.isHidden, false)
        XCTAssertEqual(window.filterFavoritesCheck?.isHidden, true)
        XCTAssertEqual(window.filterAllCheck?.isHidden, true)

        window.sidebarUnreadOnly = false
        window.sidebarFavoritesOnly = false
        window.updateFilterMenuAppearance()
        XCTAssertEqual(window.filterAllCheck?.isHidden, false)
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
