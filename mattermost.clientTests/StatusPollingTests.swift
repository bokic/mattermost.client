//
//  StatusPollingTests.swift
//  mattermost.clientTests
//

import AppKit
import XCTest

#if canImport(mattermost_client)
    @testable import mattermost_client
#endif

@MainActor
final class StatusPollingTests: XCTestCase {

    private func makeWindow() -> MainWindow {
        MainWindow(
            contentRect: NSRect(x: 0, y: 0, width: 1000, height: 700),
            styleMask: [.titled, .resizable],
            backing: .buffered,
            defer: true
        )
    }

    private func makeUser(id: String, username: String) -> MMUser {
        MMUser(
            id: id,
            create_at: nil,
            update_at: nil,
            delete_at: nil,
            username: username,
            first_name: "Test",
            last_name: "User",
            nickname: nil,
            email: "\(username)@example.com",
            email_verified: nil,
            auth_service: nil,
            roles: "system_user",
            locale: nil,
            position: nil,
            is_bot: nil,
            last_password_update: nil,
            remote_id: nil,
            disable_welcome_email: nil,
            notify_props: nil,
            props: nil,
            timezone: nil,
            auth_data: nil
        )
    }

    func testRegisterAndUnregisterStatusDot() {
        let window = makeWindow()
        defer { window.close() }

        let dot = RoundedEdgePanel()
        window.registerStatusDot(dot, for: "user_abc")

        let dots = window.statusDots(for: "user_abc")
        XCTAssertEqual(dots.count, 1)
        XCTAssertTrue(dots.first === dot)

        window.unregisterStatusDot(dot, for: "user_abc")
        XCTAssertEqual(window.statusDots(for: "user_abc").count, 0)
    }

    func testDirectStatusDotUpdateChangesColorAndCheck() {
        let window = makeWindow()
        defer { window.close() }

        let parentView = NSView(frame: NSRect(x: 0, y: 0, width: 100, height: 100))
        let dot = RoundedEdgePanel()
        dot.color = .gray
        parentView.addSubview(dot)
        window.contentView?.addSubview(parentView)

        window.registerStatusDot(dot, for: "user_xyz")

        window.updateChatWidgetUserStatus(userId: "user_xyz", status: "dnd")
        XCTAssertEqual(window.userStatusById["user_xyz"], "dnd")
        XCTAssertEqual(dot.color, window.statusColor(for: "dnd"))

        window.updateChatWidgetUserStatus(userId: "user_xyz", status: "online")
        XCTAssertEqual(window.userStatusById["user_xyz"], "online")
        XCTAssertEqual(dot.color, window.statusColor(for: "online"))

        window.updateChatWidgetUserStatus(userId: "user_xyz", status: "away")
        XCTAssertEqual(window.userStatusById["user_xyz"], "away")
        XCTAssertEqual(dot.color, window.statusColor(for: "away"))

        window.updateChatWidgetUserStatus(userId: "user_xyz", status: "offline")
        XCTAssertEqual(window.userStatusById["user_xyz"], "offline")
        XCTAssertEqual(dot.color, window.statusColor(for: "offline"))
    }

    func testDetachedStatusDotNotUpdated() {
        let window = makeWindow()
        defer { window.close() }

        let dot = RoundedEdgePanel()
        dot.color = .gray
        // Not added to any superview
        XCTAssertNil(dot.superview)

        window.registerStatusDot(dot, for: "user_detached")
        window.updateChatWidgetUserStatus(userId: "user_detached", status: "online")

        // Status in dictionary is updated, but detached dot is not touched
        XCTAssertEqual(window.userStatusById["user_detached"], "online")
        XCTAssertEqual(dot.color, .gray)
    }

    func testCurrentUserStatusDotUpdates() {
        let window = makeWindow()
        defer { window.close() }

        let currentUserId = "curr_user_123"
        window.currentUser = makeUser(id: currentUserId, username: "me")

        let parentView = NSView(frame: NSRect(x: 0, y: 0, width: 100, height: 100))
        let dot = RoundedEdgePanel()
        dot.color = .gray
        parentView.addSubview(dot)
        window.contentView?.addSubview(parentView)

        window.registerStatusDot(dot, for: "statusDot_currentUser")
        window.registerStatusDot(dot, for: currentUserId)

        window.updateChatWidgetUserStatus(userId: currentUserId, status: "dnd")
        XCTAssertEqual(window.currentUserStatus, "dnd")
        XCTAssertEqual(dot.color, window.statusColor(for: "dnd"))
    }

    func testPruneStatusDotsCleansEmptyEntries() {
        let window = makeWindow()
        defer { window.close() }

        autoreleasepool {
            let tempDot = RoundedEdgePanel()
            window.registerStatusDot(tempDot, for: "temp_user")
            XCTAssertEqual(window.statusDots(for: "temp_user").count, 1)
        }

        window.pruneStatusDots()
        XCTAssertEqual(window.statusDots(for: "temp_user").count, 0)
        XCTAssertNil(window.statusDotsByUserId["temp_user"])
    }

    func testClearTimelineRowCacheCallsPruneStatusDots() {
        let window = makeWindow()
        defer { window.close() }

        let dot = RoundedEdgePanel()
        window.registerStatusDot(dot, for: "usr_dummy")
        XCTAssertEqual(window.statusDots(for: "usr_dummy").count, 1)

        window.unregisterStatusDot(dot, for: "usr_dummy")
        window.clearTimelineRowCache()
        XCTAssertNil(window.statusDotsByUserId["usr_dummy"])
    }

    func testBatchFetchUserStatusesThrottlesRapidRequests() {
        let window = makeWindow()
        defer { window.close() }

        // Last poll time set to now
        window.lastRESTStatusPollTime = Date()
        window.isFetchingStatusesViaREST = false

        // Unforced call should throttle
        window.batchFetchUserStatusesViaREST(userIds: ["u1", "u2"], force: false)
        XCTAssertFalse(window.isFetchingStatusesViaREST)
    }
}
