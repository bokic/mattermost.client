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

        window.showRightPanel(mode: .settings)
        XCTAssertTrue(window.isRightPanelVisible)
        window.closeRightPanel()
        XCTAssertFalse(window.isRightPanelVisible)
    }
}
