//
//  AccessibilityTests.swift
//  mattermost.clientTests
//

import AppKit
import XCTest

#if canImport(mattermost_client)
    @testable import mattermost_client
#endif

@MainActor
final class AccessibilityTests: XCTestCase {

    func testClickablePanelExposesButtonRoleAndKeyboardActivation() {
        let panel = RoundedEdgePanel()
        panel.accessibilityTitle = "Send"
        panel.onClick = {}
        panel.layoutSubtreeIfNeeded()

        XCTAssertTrue(panel.acceptsFirstResponder)
        XCTAssertTrue(panel.isAccessibilityElement())
        XCTAssertEqual(panel.accessibilityRole(), .button)
        XCTAssertEqual(panel.accessibilityLabel(), "Send")
    }

    func testNonClickablePanelIsNotAnAccessibilityElement() {
        let panel = RoundedEdgePanel()
        panel.layoutSubtreeIfNeeded()

        XCTAssertFalse(panel.isAccessibilityElement())
    }
}
