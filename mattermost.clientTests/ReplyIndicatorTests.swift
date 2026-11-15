//
//  ReplyIndicatorTests.swift
//  mattermost.clientTests
//

import AppKit
import XCTest

#if canImport(mattermost_client)
    @testable import mattermost_client
#endif

@MainActor
final class ReplyIndicatorTests: XCTestCase {

    func testRootPostWithRepliesRendersThreadFooter() {
        let window = makeWindow()
        defer { window.close() }
        let post = makePost(id: "root", rootId: nil, replyCount: 3)
        let (row, _) = window.createPostRow(
            post: post,
            width: 900,
            timeStr: "12:00"
        )
        let footer = findFooter(in: row, rootId: "root")
        XCTAssertNotNil(footer)
        let label = footer?.subviews.compactMap { $0 as? NSTextField }.first
        XCTAssertEqual(label?.stringValue, "3 replies")
    }

    func testThreadPanelHidesRootReplyFooter() {
        let window = makeWindow()
        defer { window.close() }
        let post = makePost(id: "root", rootId: nil, replyCount: 3)
        let (row, _) = window.createPostRow(
            post: post,
            width: 900,
            timeStr: "12:00",
            showsThreadFooter: false
        )
        XCTAssertNil(findFooter(in: row, rootId: "root"))
    }

    func testReplyPostsDoNotGetTheirOwnFooter() {
        let window = makeWindow()
        defer { window.close() }
        let post = makePost(id: "reply", rootId: "root", replyCount: 0)
        let (row, _) = window.createPostRow(
            post: post,
            width: 900,
            timeStr: "12:00"
        )
        XCTAssertNil(findFooter(in: row, rootId: "reply"))
    }

    func testDecodesReplyCountFromPostJSON() throws {
        let json = """
            {
              "id": "root",
              "create_at": 1,
              "user_id": "user",
              "channel_id": "channel",
              "message": "hello",
              "reply_count": 4
            }
            """
        let post = try JSONDecoder().decode(MMPost.self, from: Data(json.utf8))
        XCTAssertEqual(post.reply_count, 4)
    }

    func testThreadUpdateRefreshesVisibleFooterLabel() {
        let window = makeWindow()
        defer { window.close() }
        window.setContentSize(NSSize(width: 1000, height: 700))
        window.updateViews()
        window.currentChannelPosts = [makePost(id: "root", rootId: nil, replyCount: 3)]
        window.rebuildTimelineContent(scrollToBottom: false)
        window.updateThreadReplyCount(rootId: "root", replyCount: 5)
        XCTAssertEqual(window.currentChannelPosts.first?.reply_count, 5)
        let footer = findFooter(in: window.timelineDocView, rootId: "root")
        let label = footer?.subviews.compactMap { $0 as? NSTextField }.first
        XCTAssertEqual(label?.stringValue, "5 replies")
    }

    private func makeWindow() -> MainWindow {
        MainWindow(
            contentRect: NSRect(x: 0, y: 0, width: 1000, height: 700),
            styleMask: [.titled, .resizable],
            backing: .buffered,
            defer: true
        )
    }

    private func findFooter(in view: NSView, rootId: String) -> NSView? {
        if view.identifier?.rawValue == "replyFooter_\(rootId)" { return view }
        for subview in view.subviews {
            if let found = findFooter(in: subview, rootId: rootId) { return found }
        }
        return nil
    }

    private func makePost(id: String, rootId: String?, replyCount: Int) -> MMPost {
        MMPost(
            id: id,
            create_at: 1,
            update_at: nil,
            edit_at: nil,
            delete_at: nil,
            is_pinned: nil,
            user_id: "user",
            channel_id: "channel",
            root_id: rootId,
            original_id: nil,
            message: "hello",
            type: nil,
            file_ids: nil,
            metadata: nil,
            reply_count: replyCount
        )
    }
}
