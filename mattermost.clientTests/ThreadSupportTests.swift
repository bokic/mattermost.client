//
//  ThreadSupportTests.swift
//  mattermost.clientTests
//

import XCTest

#if canImport(mattermost_client)
    @testable import mattermost_client
#endif

final class ThreadSupportTests: XCTestCase {

    func testUnreadStateUsesReplyAndViewedTimestamps() {
        XCTAssertTrue(
            ThreadSupport.isUnread(lastReplyAt: 200, lastViewedAt: 100, isMarkedRead: false)
        )
        XCTAssertFalse(
            ThreadSupport.isUnread(lastReplyAt: 100, lastViewedAt: 100, isMarkedRead: false)
        )
        XCTAssertFalse(
            ThreadSupport.isUnread(lastReplyAt: 200, lastViewedAt: 100, isMarkedRead: true)
        )
    }

    func testVisibleRepliesKeepsNewestReplies() {
        let replies = (0..<120).map(makePost)
        let page = ThreadSupport.visibleReplies(replies, limit: 50)
        XCTAssertEqual(page.posts.count, 50)
        XCTAssertEqual(page.hidden, 70)
        XCTAssertEqual(page.posts.first?.id, "post-70")
        XCTAssertEqual(page.posts.last?.id, "post-119")
    }

    func testVisibleRepliesHandlesShortThreadsAndZeroLimit() {
        let replies = (0..<3).map(makePost)
        let all = ThreadSupport.visibleReplies(replies, limit: 50)
        XCTAssertEqual(all.posts.count, 3)
        XCTAssertEqual(all.hidden, 0)

        let none = ThreadSupport.visibleReplies(replies, limit: 0)
        XCTAssertTrue(none.posts.isEmpty)
        XCTAssertEqual(none.hidden, 3)
    }

    func testRepliesChronologicalOrdering() {
        let p1 = MMPost(id: "p1", create_at: 300, update_at: nil, edit_at: nil, delete_at: nil, is_pinned: nil, user_id: "u1", channel_id: "c1", root_id: "root", original_id: nil, message: "third", type: nil)
        let p2 = MMPost(id: "p2", create_at: 100, update_at: nil, edit_at: nil, delete_at: nil, is_pinned: nil, user_id: "u1", channel_id: "c1", root_id: "root", original_id: nil, message: "first", type: nil)
        let p3 = MMPost(id: "p3", create_at: 200, update_at: nil, edit_at: nil, delete_at: nil, is_pinned: nil, user_id: "u1", channel_id: "c1", root_id: "root", original_id: nil, message: "second", type: nil)

        let unordered = [p1, p2, p3]
        let ordered = unordered.sorted { $0.create_at < $1.create_at }
        XCTAssertEqual(ordered.map(\.id), ["p2", "p3", "p1"])
        XCTAssertEqual(ordered.map(\.message), ["first", "second", "third"])
    }

    func testRootAndRepliesSeparation() {
        let root = MMPost(id: "root-1", create_at: 50, update_at: nil, edit_at: nil, delete_at: nil, is_pinned: nil, user_id: "u1", channel_id: "c1", root_id: "", original_id: nil, message: "root message", type: nil)
        let reply1 = MMPost(id: "reply-1", create_at: 100, update_at: nil, edit_at: nil, delete_at: nil, is_pinned: nil, user_id: "u2", channel_id: "c1", root_id: "root-1", original_id: nil, message: "reply 1", type: nil)
        let reply2 = MMPost(id: "reply-2", create_at: 150, update_at: nil, edit_at: nil, delete_at: nil, is_pinned: nil, user_id: "u3", channel_id: "c1", root_id: "root-1", original_id: nil, message: "reply 2", type: nil)

        let threadPosts = [root, reply1, reply2]
        let rootPost = threadPosts.first(where: { ($0.root_id ?? "").isEmpty }) ?? threadPosts[0]
        XCTAssertEqual(rootPost.id, "root-1")

        let replies = threadPosts.filter { $0.id != rootPost.id }
        XCTAssertEqual(replies.count, 2)
        XCTAssertEqual(replies.map(\.id), ["reply-1", "reply-2"])

        let paginated = ThreadSupport.visibleReplies(replies, limit: 1)
        XCTAssertEqual(paginated.posts.count, 1)
        XCTAssertEqual(paginated.posts[0].id, "reply-2")
        XCTAssertEqual(paginated.hidden, 1)
    }

    private func makePost(_ index: Int) -> MMPost {
        MMPost(
            id: "post-\(index)",
            create_at: Int64(index),
            update_at: nil,
            edit_at: nil,
            delete_at: nil,
            is_pinned: nil,
            user_id: "user",
            channel_id: "channel",
            root_id: "root",
            original_id: nil,
            message: "reply \(index)",
            type: nil
        )
    }
}
