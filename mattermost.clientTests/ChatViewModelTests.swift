//
//  ChatViewModelTests.swift
//  mattermost.clientTests
//

import XCTest

#if canImport(mattermost_client)
    @testable import mattermost_client
#endif

@MainActor
final class ChatViewModelTests: XCTestCase {

    func testWorkspaceDefaults() {
        let model = ChatViewModel()

        XCTAssertNil(model.webService)
        XCTAssertFalse(model.isWebSocketConnected)
        XCTAssertNil(model.currentUser)
        XCTAssertTrue(model.userTeams.isEmpty)
        XCTAssertNil(model.activeTeam)
        XCTAssertEqual(model.activeChannelId, "")
        XCTAssertTrue(model.channelsById.isEmpty)
        XCTAssertTrue(model.usersById.isEmpty)
        XCTAssertTrue(model.currentChannelPosts.isEmpty)
        XCTAssertFalse(model.isLoadingOlderPosts)
        XCTAssertFalse(model.didLoadAllHistory)
        XCTAssertNil(model.pendingJumpPostId)
        XCTAssertEqual(model.threadRootId, "")
        XCTAssertTrue(model.threadItems.isEmpty)
        XCTAssertTrue(model.threadPosts.isEmpty)
    }

    func testReadStateAndConnectionStorage() {
        let model = ChatViewModel()

        model.isWebSocketConnected = true
        model.unreadByChannel["town-square"] = 4
        model.mentionsByChannel["town-square"] = 2
        model.lastViewedAtByChannel["town-square"] = 1_700_000_000
        model.dndEndTimeByUser["user-1"] = 1_700_003_600
        model.membershipsByChannel["town-square"] = MMChannelMembership(
            channel_id: "town-square",
            msg_count: 12,
            mention_count: 2,
            last_viewed_at: 1_700_000_000,
            last_update_at: 1_700_000_100
        )

        XCTAssertTrue(model.isWebSocketConnected)
        XCTAssertEqual(model.unreadByChannel["town-square"], 4)
        XCTAssertEqual(model.mentionsByChannel["town-square"], 2)
        XCTAssertEqual(model.lastViewedAtByChannel["town-square"], 1_700_000_000)
        XCTAssertEqual(model.dndEndTimeByUser["user-1"], 1_700_003_600)
        XCTAssertEqual(model.membershipsByChannel["town-square"]?.msg_count, 12)
    }

    func testPaginationAndThreadStorage() {
        let model = ChatViewModel()
        let first = makePost(id: "post-1", createAt: 100)
        let reply = makePost(id: "post-2", createAt: 200, rootId: "post-1")

        model.currentChannelPosts = [first]
        model.isLoadingOlderPosts = true
        model.didLoadAllHistory = true
        model.pendingJumpPostId = "post-1"
        model.threadRootId = "post-1"
        model.threadPosts = [first, reply]

        XCTAssertEqual(model.currentChannelPosts.map { $0.id }, ["post-1"])
        XCTAssertTrue(model.isLoadingOlderPosts)
        XCTAssertTrue(model.didLoadAllHistory)
        XCTAssertEqual(model.pendingJumpPostId, "post-1")
        XCTAssertEqual(model.threadRootId, "post-1")
        XCTAssertEqual(model.threadPosts.map { $0.id }, ["post-1", "post-2"])
        XCTAssertEqual(model.threadPosts.last?.root_id, "post-1")
    }

    private func makePost(id: String, createAt: Int64, rootId: String? = nil) -> MMPost {
        MMPost(
            id: id,
            create_at: createAt,
            update_at: createAt,
            edit_at: nil,
            delete_at: nil,
            is_pinned: false,
            user_id: "user-1",
            channel_id: "town-square",
            root_id: rootId,
            original_id: nil,
            message: id,
            type: nil
        )
    }
}
