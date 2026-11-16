//
//  WebSocketClientTests.swift
//  mattermost.clientTests
//

import XCTest

#if canImport(mattermost_client)
    @testable import mattermost_client
#endif

@MainActor
final class WebSocketClientTests: XCTestCase {

    // MARK: - Backoff & Reconnect

    func testReconnectDelayExponentialAndCapped() {
        XCTAssertEqual(WebSocketClient.reconnectDelay(attempt: 0), 1)
        XCTAssertEqual(WebSocketClient.reconnectDelay(attempt: 1), 2)
        XCTAssertEqual(WebSocketClient.reconnectDelay(attempt: 2), 4)
        XCTAssertEqual(WebSocketClient.reconnectDelay(attempt: 3), 8)
        XCTAssertEqual(WebSocketClient.reconnectDelay(attempt: 4), 16)
        XCTAssertEqual(WebSocketClient.reconnectDelay(attempt: 5), 30)
        XCTAssertEqual(WebSocketClient.reconnectDelay(attempt: 10), 30)
        XCTAssertEqual(WebSocketClient.reconnectDelay(attempt: 10, jitter: 0.75), 30.75)
    }

    // MARK: - Event Parsing

    func testParseHelloEvent() {
        let client = WebSocketClient(
            urlProvider: { nil },
            tokenProvider: { nil },
            isLoggedProvider: { false }
        )
        let json = #"{"event":"hello","data":{"server_version":"10.0.0"},"seq":1}"#
        let result = client.parseWebSocketMessage(json)
        XCTAssertTrue(result.didConnect)
        if case .hello = result.event {
            // expected
        } else {
            XCTFail("Expected .hello event")
        }
    }

    func testParsePostedEvent() {
        let client = WebSocketClient(
            urlProvider: { nil },
            tokenProvider: { nil },
            isLoggedProvider: { false }
        )
        let json = """
            {
                "event": "posted",
                "data": {
                    "channel_display_name": "General",
                    "channel_name": "general",
                    "sender_name": "bob",
                    "team_id": "team1",
                    "post": "{\\"id\\":\\"p1\\",\\"create_at\\":1000,\\"user_id\\":\\"u1\\",\\"channel_id\\":\\"c1\\",\\"message\\":\\"hello world\\"}"
                },
                "seq": 2
            }
            """
        let result = client.parseWebSocketMessage(json)
        if case .posted(let post, let sender, let channelDisplay, let channelName, let teamId) = result.event {
            XCTAssertEqual(post.id, "p1")
            XCTAssertEqual(post.message, "hello world")
            XCTAssertEqual(sender, "bob")
            XCTAssertEqual(channelDisplay, "General")
            XCTAssertEqual(channelName, "general")
            XCTAssertEqual(teamId, "team1")
        } else {
            XCTFail("Expected .posted event")
        }
    }

    func testParsePostEditedAndDeleted() {
        let client = WebSocketClient(
            urlProvider: { nil },
            tokenProvider: { nil },
            isLoggedProvider: { false }
        )

        let editJson = """
            {
                "event": "post_edited",
                "data": {
                    "post": "{\\"id\\":\\"p1\\",\\"create_at\\":1000,\\"user_id\\":\\"u1\\",\\"channel_id\\":\\"c1\\",\\"message\\":\\"updated\\"}"
                },
                "seq": 3
            }
            """
        let editResult = client.parseWebSocketMessage(editJson)
        if case .postEdited(let post) = editResult.event {
            XCTAssertEqual(post.id, "p1")
            XCTAssertEqual(post.message, "updated")
        } else {
            XCTFail("Expected .postEdited event")
        }

        let deleteJson = """
            {
                "event": "post_deleted",
                "data": {
                    "post": "{\\"id\\":\\"p1\\",\\"create_at\\":1000,\\"user_id\\":\\"u1\\",\\"channel_id\\":\\"c1\\",\\"message\\":\\"deleted\\"}"
                },
                "seq": 4
            }
            """
        let deleteResult = client.parseWebSocketMessage(deleteJson)
        if case .postDeleted(let postId, let channelId) = deleteResult.event {
            XCTAssertEqual(postId, "p1")
            XCTAssertEqual(channelId, "c1")
        } else {
            XCTFail("Expected .postDeleted event")
        }
    }

    func testParseUserTypingAndStatusChange() {
        let client = WebSocketClient(
            urlProvider: { nil },
            tokenProvider: { nil },
            isLoggedProvider: { false }
        )

        let typingJson = """
            {
                "event": "typing",
                "data": { "parent_id": "root_1", "user_id": "u2" },
                "broadcast": { "channel_id": "c1" },
                "seq": 5
            }
            """
        let typingResult = client.parseWebSocketMessage(typingJson)
        if case .typing(let userId, let channelId, let parentId) = typingResult.event {
            XCTAssertEqual(userId, "u2")
            XCTAssertEqual(channelId, "c1")
            XCTAssertEqual(parentId, "root_1")
        } else {
            XCTFail("Expected .typing event")
        }

        let statusJson = """
            {
                "event": "status_change",
                "data": { "status": "dnd", "user_id": "u2" },
                "seq": 6
            }
            """
        let statusResult = client.parseWebSocketMessage(statusJson)
        if case .statusChange(let userId, let status) = statusResult.event {
            XCTAssertEqual(userId, "u2")
            XCTAssertEqual(status, "dnd")
        } else {
            XCTFail("Expected .statusChange event")
        }
    }

    func testParseReactionEvents() {
        let client = WebSocketClient(
            urlProvider: { nil },
            tokenProvider: { nil },
            isLoggedProvider: { false }
        )

        let reactionJson = """
            {
                "event": "reaction_added",
                "data": {
                    "reaction": "{\\"user_id\\":\\"u1\\",\\"post_id\\":\\"p_react\\",\\"emoji_name\\":\\"smile\\"}"
                },
                "seq": 7
            }
            """
        let result = client.parseWebSocketMessage(reactionJson)
        if case .reactionChanged(let postId) = result.event {
            XCTAssertEqual(postId, "p_react")
        } else {
            XCTFail("Expected .reactionChanged event")
        }
    }

    func testConvenienceInitWithApiClient() {
        let api = APIClient(host: "chat.example.com", port: 8065)
        api.authToken = "token-test"
        let client = WebSocketClient(apiClient: api)
        XCTAssertFalse(client.isConnected)
    }

    func testParseChannelViewedEvent() {
        let client = WebSocketClient(
            urlProvider: { nil },
            tokenProvider: { nil },
            isLoggedProvider: { false }
        )

        let json = """
            {
                "event": "channel_viewed",
                "data": { "channel_id": "c_viewed_123" },
                "seq": 8
            }
            """
        let result = client.parseWebSocketMessage(json)
        if case .channelViewed(let channelId) = result.event {
            XCTAssertEqual(channelId, "c_viewed_123")
        } else {
            XCTFail("Expected .channelViewed event")
        }
    }

    func testParseMultipleChannelsViewedEvent() {
        let client = WebSocketClient(
            urlProvider: { nil },
            tokenProvider: { nil },
            isLoggedProvider: { false }
        )

        let json = """
            {
                "event": "multiple_channels_viewed",
                "data": { "channel_ids": ["c1", "c2", "c3"] },
                "seq": 9
            }
            """
        var additionalChannels: [String] = []
        client.onWebSocketEvent = { event in
            if case .channelViewed(let channelId) = event {
                additionalChannels.append(channelId)
            }
        }

        let result = client.parseWebSocketMessage(json)
        if case .channelViewed(let channelId) = result.event {
            XCTAssertEqual(channelId, "c1")
        } else {
            XCTFail("Expected first channel viewed")
        }
        XCTAssertEqual(additionalChannels, ["c2", "c3"])
    }

    func testParsePostUnreadEvent() {
        let client = WebSocketClient(
            urlProvider: { nil },
            tokenProvider: { nil },
            isLoggedProvider: { false }
        )

        let json = """
            {
                "event": "post_unread",
                "data": { "channel_id": "c_unread_456" },
                "seq": 10
            }
            """
        let result = client.parseWebSocketMessage(json)
        if case .postUnread(let channelId) = result.event {
            XCTAssertEqual(channelId, "c_unread_456")
        } else {
            XCTFail("Expected .postUnread event")
        }
    }

    func testParseStatusReplyEvent() {
        let client = WebSocketClient(
            urlProvider: { nil },
            tokenProvider: { nil },
            isLoggedProvider: { false }
        )

        let json = """
            {
                "status": "OK",
                "seq_reply": 1,
                "data": {
                    "u1": "online",
                    "u2": "away",
                    "u3": "dnd"
                }
            }
            """
        let result = client.parseWebSocketMessage(json)
        XCTAssertTrue(result.didConnect)
        if case .userStatuses(let statuses) = result.event {
            XCTAssertEqual(statuses["u1"], "online")
            XCTAssertEqual(statuses["u2"], "away")
            XCTAssertEqual(statuses["u3"], "dnd")
        } else {
            XCTFail("Expected .userStatuses event")
        }
    }

    func testBackoffProgressionAndCap() {
        let delays = (0...8).map { WebSocketClient.reconnectDelay(attempt: $0, jitter: 0) }
        XCTAssertEqual(delays, [1, 2, 4, 8, 16, 30, 30, 30, 30])

        let withJitter = WebSocketClient.reconnectDelay(attempt: 3, jitter: 0.5)
        XCTAssertEqual(withJitter, 8.5)
    }
}
