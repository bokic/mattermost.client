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

    private func makeWindow() -> MainWindow {
        MainWindow(
            contentRect: NSRect(x: 0, y: 0, width: 1000, height: 700),
            styleMask: [.titled, .resizable],
            backing: .buffered,
            defer: true
        )
    }
}
