//
//  SystemMessageTests.swift
//  mattermost.clientTests
//

import AppKit
import XCTest

#if canImport(mattermost_client)
    @testable import mattermost_client
#endif

@MainActor
final class SystemMessageTests: XCTestCase {

    func testSystemJoinAndAddMessagesUsePostProps() {
        let join = makePost(
            id: "join",
            type: "system_join_channel",
            message: "",
            props: MMPostProps(username: "alice", channel_display_name: "Town Square")
        )
        XCTAssertEqual(SystemMessageText.text(for: join), "alice joined Town Square.")

        let add = makePost(
            id: "add",
            type: "system_add_to_channel",
            message: "",
            props: MMPostProps(
                username: "alice",
                channel_display_name: "Town Square",
                addedUsername: "bob"
            )
        )
        XCTAssertEqual(SystemMessageText.text(for: add), "alice added bob to Town Square.")
    }

    func testSystemHeaderAndPurposeMessages() {
        let header = makePost(
            id: "header",
            type: "system_header_change",
            message: "",
            props: MMPostProps(username: "alice", new_header: "Deploys at 5pm")
        )
        XCTAssertEqual(
            SystemMessageText.text(for: header),
            "alice updated the channel header to: Deploys at 5pm"
        )

        let removed = makePost(
            id: "purpose",
            type: "system_purpose_change",
            message: "",
            props: MMPostProps(username: "alice", new_purpose: "")
        )
        XCTAssertEqual(
            SystemMessageText.text(for: removed),
            "alice removed the channel purpose."
        )
    }

    func testUnknownSystemPostFallsBackToMessage() {
        let post = makePost(
            id: "generic",
            type: "system_generic",
            message: "A custom system update",
            props: nil
        )
        XCTAssertEqual(SystemMessageText.text(for: post), "A custom system update")

        let empty = makePost(id: "empty", type: "system_generic", message: "", props: nil)
        XCTAssertEqual(SystemMessageText.text(for: empty), "System update")
    }

    func testBotDetectionUsesIsBotAndRolesNotUsernameSubstrings() throws {
        let window = makeWindow()
        defer { window.close() }

        let human = try decodeUser(#"{"id":"1","username":"abbott","is_bot":false,"roles":""}"#)
        let roleBot = try decodeUser(#"{"id":"2","username":"ci","is_bot":false,"roles":"system_user bot"}"#)
        let realBot = try decodeUser(#"{"id":"3","username":"helper","is_bot":true,"roles":"system_user"}"#)

        XCTAssertFalse(window.isBotAccount(human))
        XCTAssertTrue(window.isBotAccount(roleBot))
        XCTAssertTrue(window.isBotAccount(realBot))
    }

    func testUnknownPresenceFallsBackToOffline() {
        let window = makeWindow()
        defer { window.close() }
        XCTAssertEqual(
            window.statusColor(for: "not-a-status"),
            Theme.shared.centerTextPlaceholder
        )
        XCTAssertEqual(window.statusString(for: 99), "offline")
        XCTAssertEqual(window.indexForStatus("not-a-status"), 3)
    }

    private func decodeUser(_ json: String) throws -> MMUser {
        try JSONDecoder().decode(MMUser.self, from: Data(json.utf8))
    }

    private func makeWindow() -> MainWindow {
        MainWindow(
            contentRect: NSRect(x: 0, y: 0, width: 1000, height: 700),
            styleMask: [.titled, .resizable],
            backing: .buffered,
            defer: true
        )
    }

    private func makePost(
        id: String,
        type: String,
        message: String,
        props: MMPostProps?
    ) -> MMPost {
        MMPost(
            id: id,
            create_at: 1,
            update_at: nil,
            edit_at: nil,
            delete_at: nil,
            is_pinned: nil,
            user_id: "user",
            channel_id: "channel",
            root_id: nil,
            original_id: nil,
            message: message,
            type: type,
            file_ids: nil,
            metadata: nil,
            reply_count: 0,
            props: props
        )
    }
}
