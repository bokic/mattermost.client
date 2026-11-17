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

    func testAccessibilityRoleOverrideAndValue() {
        let panel = RoundedEdgePanel()
        panel.accessibilityTitle = "Online"
        panel.accessibilityRoleOverride = .menuItem
        panel.accessibilityValueString = "Selected"
        panel.accessibilityHelp = "Set status to online"
        panel.onClick = {}
        panel.layoutSubtreeIfNeeded()

        XCTAssertTrue(panel.isAccessibilityElement())
        XCTAssertEqual(panel.accessibilityRole(), .menuItem)
        XCTAssertEqual(panel.accessibilityLabel(), "Online")
        XCTAssertEqual(panel.accessibilityHelp(), "Set status to online")
        XCTAssertEqual(panel.accessibilityValue() as? String, "Selected")
    }

    func testSpaceAndReturnKeyActivation() {
        let panel = RoundedEdgePanel()
        var clicked = false
        panel.onClick = { clicked = true }

        // Test Return (keyCode 36)
        let returnEvent = NSEvent.keyEvent(
            with: .keyDown,
            location: .zero,
            modifierFlags: [],
            timestamp: 0,
            windowNumber: 0,
            context: nil,
            characters: "\r",
            charactersIgnoringModifiers: "\r",
            isARepeat: false,
            keyCode: 36
        )!
        panel.keyDown(with: returnEvent)
        XCTAssertTrue(clicked)

        // Test Space (keyCode 49)
        clicked = false
        let spaceEvent = NSEvent.keyEvent(
            with: .keyDown,
            location: .zero,
            modifierFlags: [],
            timestamp: 0,
            windowNumber: 0,
            context: nil,
            characters: " ",
            charactersIgnoringModifiers: " ",
            isARepeat: false,
            keyCode: 49
        )!
        panel.keyDown(with: spaceEvent)
        XCTAssertTrue(clicked)

        // Test accessibilityPerformPress()
        clicked = false
        let handled = panel.accessibilityPerformPress()
        XCTAssertTrue(handled)
        XCTAssertTrue(clicked)
    }

    func testArrowKeyHandling() {
        let panel = RoundedEdgePanel()
        panel.onClick = {}

        var receivedDirection: RoundedEdgePanel.ArrowDirection?
        panel.onArrowKey = { dir in
            receivedDirection = dir
            return true
        }

        let downArrow = NSEvent.keyEvent(
            with: .keyDown,
            location: .zero,
            modifierFlags: [],
            timestamp: 0,
            windowNumber: 0,
            context: nil,
            characters: "",
            charactersIgnoringModifiers: "",
            isARepeat: false,
            keyCode: 125
        )!
        panel.keyDown(with: downArrow)
        XCTAssertEqual(receivedDirection, .down)

        let upArrow = NSEvent.keyEvent(
            with: .keyDown,
            location: .zero,
            modifierFlags: [],
            timestamp: 0,
            windowNumber: 0,
            context: nil,
            characters: "",
            charactersIgnoringModifiers: "",
            isARepeat: false,
            keyCode: 126
        )!
        panel.keyDown(with: upArrow)
        XCTAssertEqual(receivedDirection, .up)
    }

    func testFocusRingMaskAndResponderState() {
        let panel = RoundedEdgePanel(frame: NSRect(x: 0, y: 0, width: 100, height: 40))
        panel.cornerRadius = 8
        panel.onClick = {}

        XCTAssertTrue(panel.acceptsFirstResponder)
        XCTAssertEqual(panel.focusRingMaskBounds, NSRect(x: 0, y: 0, width: 100, height: 40))

        XCTAssertTrue(panel.becomeFirstResponder())
        XCTAssertTrue(panel.resignFirstResponder())
    }

    func testComposerButtonsHaveAccessibilityTitlesAndRoles() {
        let window = MainWindow(
            contentRect: NSRect(x: 0, y: 0, width: 1000, height: 700),
            styleMask: [.titled, .resizable],
            backing: .buffered,
            defer: true
        )
        defer { window.close() }

        // Formatting toggle and action buttons
        XCTAssertEqual(window.composerAaButton.accessibilityTitle, "Toggle formatting toolbar")
        XCTAssertEqual(window.composerAaButton.accessibilityRoleOverride, .button)
        XCTAssertEqual(window.composerAttachButton.accessibilityTitle, "Attach files")
        XCTAssertEqual(window.composerEmojiButton.accessibilityTitle, "Emoji")
        XCTAssertEqual(window.composerSendButton.accessibilityTitle, "Send")

        // Format buttons inside composerLeftButtons
        XCTAssertFalse(window.composerLeftButtons.isEmpty)
        for btn in window.composerLeftButtons {
            btn.layoutSubtreeIfNeeded()
            XCTAssertTrue(btn.isAccessibilityElement())
            XCTAssertEqual(btn.accessibilityRole(), .button)
            XCTAssertFalse(btn.accessibilityLabel()?.isEmpty ?? true)
        }
    }

    func testChannelHeaderButtonsHaveAccessibilityTitlesAndRoles() {
        let window = MainWindow(
            contentRect: NSRect(x: 0, y: 0, width: 1000, height: 700),
            styleMask: [.titled, .resizable],
            backing: .buffered,
            defer: true
        )
        defer { window.close() }

        XCTAssertEqual(window.channelTitleButton.accessibilityTitle, "Channel Menu")
        XCTAssertEqual(window.channelMembersButton.accessibilityTitle, "Channel Members")
        XCTAssertEqual(window.channelPinsButton.accessibilityTitle, "Pinned Posts")
        XCTAssertEqual(window.channelFilesButton.accessibilityTitle, "Files")
        XCTAssertEqual(window.channelSidebarButton.accessibilityTitle, "Threads")
        XCTAssertEqual(window.channelInfoButton.accessibilityTitle, "Channel Info")
    }

    func testHeaderAndThreadReplyControlsHaveAccessibilityTitlesAndRoles() {
        let window = MainWindow(
            contentRect: NSRect(x: 0, y: 0, width: 1000, height: 700),
            styleMask: [.titled, .resizable],
            backing: .buffered,
            defer: true
        )
        defer { window.close() }

        XCTAssertEqual(window.productSwitcherPanel.accessibilityTitle, "Product Switcher")
        XCTAssertEqual(window.productSwitcherPanel.accessibilityRole(), .button)
        XCTAssertEqual(window.searchPanel.accessibilityTitle, "Search")
        XCTAssertEqual(window.searchPanel.accessibilityRole(), .button)
        XCTAssertEqual(window.helpPanel.accessibilityTitle, "Help")
        XCTAssertEqual(window.helpPanel.accessibilityRole(), .button)
        XCTAssertEqual(window.rightPanelCloseButton.accessibilityTitle, "Close panel")
        XCTAssertEqual(window.rightPanelCloseButton.accessibilityRole(), .button)
        XCTAssertEqual(window.threadEmojiButton.accessibilityTitle, "Add emoji")
        XCTAssertEqual(window.threadEmojiButton.accessibilityRole(), .button)
        XCTAssertEqual(window.threadAttachButton.accessibilityTitle, "Attach files")
        XCTAssertEqual(window.threadAttachButton.accessibilityRole(), .button)
        XCTAssertEqual(window.threadSendButton.accessibilityTitle, "Send reply")
        XCTAssertEqual(window.threadSendButton.accessibilityRole(), .button)
        XCTAssertEqual(window.threadReplyTextView.accessibilityLabel(), "Reply to thread")
    }
}
