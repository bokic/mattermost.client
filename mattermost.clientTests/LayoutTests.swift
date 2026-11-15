//
//  LayoutTests.swift
//  mattermost.clientTests
//

import AppKit
import XCTest

#if canImport(mattermost_client)
    @testable import mattermost_client
#endif

@MainActor
final class LayoutTests: XCTestCase {

    func testMainWindowKeepsUsableMinimumSizeAndReflows() {
        let window = MainWindow(
            contentRect: NSRect(x: 0, y: 0, width: 1000, height: 700),
            styleMask: [.titled, .resizable],
            backing: .buffered,
            defer: true
        )
        defer { window.close() }

        XCTAssertEqual(window.contentMinSize.width, 860)
        XCTAssertEqual(window.contentMinSize.height, 520)

        window.setContentSize(NSSize(width: 860, height: 520))
        window.updateViews()
        XCTAssertGreaterThan(window.chatPanel.frame.width, 0)
        XCTAssertGreaterThan(window.timelineScrollView.frame.width, 0)
        XCTAssertGreaterThan(window.sidebarScroll.frame.height, 0)
        XCTAssertTrue(window.sidebarScroll.superview === window.mainPanel)
        XCTAssertTrue(window.sidebarScroll.documentView === window.sidebarDoc)
        XCTAssertLessThanOrEqual(window.sidebarScroll.frame.maxY, window.findChannelPanel.frame.minY)
        XCTAssertGreaterThanOrEqual(
            window.sidebarDoc.frame.height,
            window.sidebarScroll.contentView.bounds.height
        )

        window.showRightPanel(mode: .settings)
        XCTAssertTrue(window.isRightPanelVisible)
        window.closeRightPanel()
        XCTAssertFalse(window.isRightPanelVisible)
    }

    func testLoginWindowExposesPasswordMFAAndSSOControls() {
        let window = LoginWindow(
            contentRect: NSRect(x: 0, y: 0, width: 640, height: 480),
            styleMask: [.titled, .closable, .resizable],
            backing: .buffered,
            defer: true
        )
        defer { window.close() }

        XCTAssertEqual(window.contentView?.bounds.width, 560)
        XCTAssertEqual(window.contentView?.bounds.height, 660)
        XCTAssertTrue(window.mfaField.isHidden)
        XCTAssertGreaterThan(window.connectButton.frame.width, 0)
        XCTAssertGreaterThan(window.ssoButton.frame.width, 0)
        XCTAssertEqual(window.ssoButton.title, "Continue with single sign-on")
        XCTAssertNotNil(window.findServerButton)
        XCTAssertEqual(window.findServerButton.title, "Find server by email")
    }
}
