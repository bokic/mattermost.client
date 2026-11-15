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
