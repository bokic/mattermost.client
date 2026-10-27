//
//  WebServiceTests.swift
//  mattermost.clientTests
//

import XCTest
#if canImport(mattermost_client)
@testable import mattermost_client
#endif

final class WebServiceTests: XCTestCase {

    // MARK: - URL Building Tests

    func testBuildURLWithPlainHostAddsHTTPSchemeAndPort() {
        let ws = WebService(host: "chat.example.com", port: 8065)
        let url = ws.buildURL(path: "/api/v4/users/me")
        XCTAssertEqual(url?.absoluteString, "http://chat.example.com:8065/api/v4/users/me")
    }

    func testBuildURLStripsTrailingSlashesAndWhitespace() {
        let ws = WebService(host: "  https://chat.example.com///  ", port: 8443)
        let url = ws.buildURL(path: "/api/v4/users/login")
        XCTAssertEqual(url?.absoluteString, "https://chat.example.com:8443/api/v4/users/login")
    }

    func testBuildURLWithQueryItems() {
        let ws = WebService(host: "chat.example.com", port: 8065)
        let queryItems = [
            URLQueryItem(name: "page", value: "0"),
            URLQueryItem(name: "per_page", value: "60")
        ]
        let url = ws.buildURL(path: "/api/v4/channels/channel123/posts", queryItems: queryItems)
        XCTAssertEqual(url?.absoluteString, "http://chat.example.com:8065/api/v4/channels/channel123/posts?page=0&per_page=60")
    }

    func testBuildWebSocketURLUsesWSAndWSSSchemes() {
        let httpWS = WebService(host: "http://chat.example.com", port: 8065)
        XCTAssertEqual(
            httpWS.buildURL(path: "/api/v4/websocket", isWebSocket: true)?.absoluteString,
            "ws://chat.example.com:8065/api/v4/websocket"
        )

        let httpsWS = WebService(host: "https://chat.example.com", port: 443)
        XCTAssertEqual(
            httpsWS.buildURL(path: "/api/v4/websocket", isWebSocket: true)?.absoluteString,
            "wss://chat.example.com:443/api/v4/websocket"
        )
    }

    func testBuildURLReturnsNilForEmptyOrInvalidHost() {
        let emptyWS = WebService(host: "", port: 8065)
        XCTAssertNil(emptyWS.buildURL(path: "/api/v4/users/me"))

        let slashOnlyWS = WebService(host: "   ///   ", port: 8065)
        XCTAssertNil(slashOnlyWS.buildURL(path: "/api/v4/users/me"))
    }

    func testBuildUserImageURL() {
        let ws = WebService(host: "chat.example.com", port: 8065)
        let url = ws.buildURL(path: "/api/v4/users/eb9f11xqsjdsf83d1t5cn7e3hy/image")
        XCTAssertEqual(url?.absoluteString, "http://chat.example.com:8065/api/v4/users/eb9f11xqsjdsf83d1t5cn7e3hy/image")
    }

    // MARK: - JSON Decoding Tests

    func testDecodeLoginWebService() throws {
        let json = """
        {
            "id": "u12345",
            "create_at": 1700000000000,
            "username": "boris",
            "first_name": "Boris",
            "last_name": "Barbulovski",
            "email": "boris@example.com",
            "roles": "system_admin system_user",
            "notify_props": {
                "desktop": "all",
                "desktop_sound": "true",
                "push": "mention"
            },
            "timezone": {
                "useAutomaticTimezone": "true",
                "automaticTimezone": "Europe/Skopje",
                "manualTimezone": ""
            }
        }
        """.data(using: .utf8)!

        let user = try JSONDecoder().decode(LoginWebService.self, from: json)
        XCTAssertEqual(user.id, "u12345")
        XCTAssertEqual(user.username, "boris")
        XCTAssertEqual(user.first_name, "Boris")
        XCTAssertEqual(user.notify_props?.desktop, "all")
        XCTAssertEqual(user.timezone?.automaticTimezone, "Europe/Skopje")
    }

    func testDecodeMMTeamsAndChannels() throws {
        let teamsJSON = """
        [
            {
                "id": "team_none_id",
                "display_name": "None",
                "name": "none",
                "type": "O",
                "allow_open_invite": true
            }
        ]
        """.data(using: .utf8)!

        let teams = try JSONDecoder().decode([MMTeam].self, from: teamsJSON)
        XCTAssertEqual(teams.count, 1)
        XCTAssertEqual(teams.first?.id, "team_none_id")
        XCTAssertEqual(teams.first?.display_name, "None")

        let channelsJSON = """
        [
            {
                "id": "ch_town_square",
                "team_id": "team_none_id",
                "type": "O",
                "display_name": "Town Square",
                "name": "town-square",
                "total_msg_count": 2
            }
        ]
        """.data(using: .utf8)!

        let channels = try JSONDecoder().decode([MMChannel].self, from: channelsJSON)
        XCTAssertEqual(channels.count, 1)
        XCTAssertEqual(channels.first?.id, "ch_town_square")
        XCTAssertEqual(channels.first?.display_name, "Town Square")
        XCTAssertEqual(channels.first?.name, "town-square")
    }

    func testDecodeDirectMessageChannelWithUserIds() throws {
        let dmJSON = """
        [
            {
                "id": "ch_dm_bot",
                "team_id": "",
                "type": "D",
                "display_name": "",
                "name": "bcmikqjebf878f8w5qweqwe__useridme",
                "total_msg_count": 5
            }
        ]
        """.data(using: .utf8)!

        let channels = try JSONDecoder().decode([MMChannel].self, from: dmJSON)
        XCTAssertEqual(channels.count, 1)
        XCTAssertEqual(channels.first?.type, "D")
        XCTAssertEqual(channels.first?.name, "bcmikqjebf878f8w5qweqwe__useridme")
        XCTAssertEqual(channels.first?.display_name, "")
    }

    func testDecodeMMSidebarCategoriesResponse() throws {
        let categoriesJSON = """
        {
            "categories": [
                {
                    "id": "cat_custom_1",
                    "team_id": "team_none_id",
                    "type": "custom",
                    "display_name": "MOJ_CAT",
                    "collapsed": false,
                    "channel_ids": ["ch_off_topic"]
                },
                {
                    "id": "cat_channels",
                    "team_id": "team_none_id",
                    "type": "channels",
                    "display_name": "CHANNELS",
                    "collapsed": false,
                    "channel_ids": ["ch_2", "ch_town_square"]
                }
            ],
            "order": ["cat_custom_1", "cat_channels"]
        }
        """.data(using: .utf8)!

        let response = try JSONDecoder().decode(MMSidebarCategoriesResponse.self, from: categoriesJSON)
        XCTAssertEqual(response.order, ["cat_custom_1", "cat_channels"])
        XCTAssertEqual(response.categories.count, 2)
        XCTAssertEqual(response.categories[0].display_name, "MOJ_CAT")
        XCTAssertEqual(response.categories[1].channel_ids, ["ch_2", "ch_town_square"])
    }

    func testDecodeMMPostListAndChronologicalOrder() throws {
        let postListJSON = """
        {
            "order": ["post_newest", "post_oldest"],
            "posts": {
                "post_oldest": {
                    "id": "post_oldest",
                    "create_at": 1764573180000,
                    "user_id": "sys_user",
                    "channel_id": "ch_town_square",
                    "message": "You joined the team.",
                    "type": "system_join_team"
                },
                "post_newest": {
                    "id": "post_newest",
                    "create_at": 1765415100000,
                    "user_id": "u12345",
                    "channel_id": "ch_town_square",
                    "message": "ok",
                    "type": ""
                }
            },
            "next_post_id": "",
            "prev_post_id": ""
        }
        """.data(using: .utf8)!

        let postList = try JSONDecoder().decode(MMPostList.self, from: postListJSON)
        let chronological = postList.chronologicalPosts
        XCTAssertEqual(chronological.count, 2)
        XCTAssertEqual(chronological[0].id, "post_oldest")
        XCTAssertEqual(chronological[0].message, "You joined the team.")
        XCTAssertEqual(chronological[1].id, "post_newest")
        XCTAssertEqual(chronological[1].message, "ok")
    }

    // MARK: - WebSocket Event Parsing Tests

    func testParseWebSocketPostedStatusAndTypingEvents() {
        let ws = WebService(host: "chat.example.com", port: 8065)

        // 1. Auth OK reply
        let authReply = #"{"status":"OK","seq_reply":1}"#
        let authResult = ws.parseWebSocketMessage(authReply)
        XCTAssertTrue(authResult.didConnect)
        XCTAssertNil(authResult.event)

        // 2. Posted event (nested JSON string inside data.post)
        let postedPayload = """
        {
            "event": "posted",
            "data": {
                "channel_display_name": "Town Square",
                "channel_name": "town-square",
                "sender_name": "@boris",
                "team_id": "team_none_id",
                "post": "{\\"id\\":\\"p999\\",\\"create_at\\":1765415200000,\\"user_id\\":\\"u12345\\",\\"channel_id\\":\\"ch_town_square\\",\\"message\\":\\"Hello from WebSocket\\"}"
            },
            "broadcast": {
                "channel_id": "ch_town_square"
            },
            "seq": 2
        }
        """
        let postedResult = ws.parseWebSocketMessage(postedPayload)
        if case .posted(let post, let senderName, let channelDisplayName, let channelName, let teamId) = postedResult.event {
            XCTAssertEqual(post.id, "p999")
            XCTAssertEqual(post.message, "Hello from WebSocket")
            XCTAssertEqual(senderName, "@boris")
            XCTAssertEqual(channelDisplayName, "Town Square")
            XCTAssertEqual(channelName, "town-square")
            XCTAssertEqual(teamId, "team_none_id")
        } else {
            XCTFail("Expected .posted WebSocket event")
        }

        // 3. Status change event
        let statusPayload = #"{"event":"status_change","data":{"status":"dnd","user_id":"u12345"},"seq":3}"#
        let statusResult = ws.parseWebSocketMessage(statusPayload)
        if case .statusChange(let userId, let status) = statusResult.event {
            XCTAssertEqual(userId, "u12345")
            XCTAssertEqual(status, "dnd")
        } else {
            XCTFail("Expected .statusChange WebSocket event")
        }

        // 4. Typing event
        let typingPayload = #"{"event":"typing","data":{"parent_id":"","user_id":"u67890"},"broadcast":{"channel_id":"ch_town_square"},"seq":4}"#
        let typingResult = ws.parseWebSocketMessage(typingPayload)
        if case .typing(let userId, let channelId, let parentId) = typingResult.event {
            XCTAssertEqual(userId, "u67890")
            XCTAssertEqual(channelId, "ch_town_square")
            XCTAssertEqual(parentId, "")
        } else {
            XCTFail("Expected .typing WebSocket event")
        }

        // 5. Update team event
        let updateTeamPayload = """
        {
            "event": "update_team",
            "data": {
                "team": "{\\"id\\":\\"team_none_id\\",\\"display_name\\":\\"Engineering Team\\",\\"name\\":\\"engineering\\",\\"type\\":\\"O\\"}"
            },
            "seq": 5
        }
        """
        let updateTeamResult = ws.parseWebSocketMessage(updateTeamPayload)
        if case .updateTeam(let team) = updateTeamResult.event {
            XCTAssertEqual(team.id, "team_none_id")
            XCTAssertEqual(team.display_name, "Engineering Team")
            XCTAssertEqual(team.name, "engineering")
        } else {
            XCTFail("Expected .updateTeam WebSocket event")
        }

        // 6. Added to team event
        let addedTeamPayload = #"{"event":"added_to_team","data":{"team_id":"team_2","user_id":"u12345"},"seq":6}"#
        let addedTeamResult = ws.parseWebSocketMessage(addedTeamPayload)
        if case .addedToTeam(let teamId, let userId) = addedTeamResult.event {
            XCTAssertEqual(teamId, "team_2")
            XCTAssertEqual(userId, "u12345")
        } else {
            XCTFail("Expected .addedToTeam WebSocket event")
        }
    }
}
