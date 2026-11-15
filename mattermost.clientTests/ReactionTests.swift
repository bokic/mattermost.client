//
//  ReactionTests.swift
//  mattermost.clientTests
//

import AppKit
import XCTest

#if canImport(mattermost_client)
    @testable import mattermost_client
#endif

@MainActor
final class ReactionTests: XCTestCase {

    func testGroupedReactionsSortByCountThenName() {
        let post = makePost(reactions: [
            makeReaction("thumbsup", user: "u2"),
            makeReaction("heart", user: "u1"),
            makeReaction("heart", user: "u2"),
            makeReaction("clap", user: "u1"),
            makeReaction("clap", user: "u2"),
        ])
        let window = makeWindow()
        defer { window.close() }
        let groups = window.groupedReactions(post)
        XCTAssertEqual(groups.map(\.0), ["clap", "heart", "thumbsup"])
        XCTAssertEqual(groups.map(\.1), [2, 2, 1])
    }

    func testOptimisticReactionAddAndRemove() {
        let window = makeWindow()
        defer { window.close() }
        let post = makePost(reactions: [])
        let added = window.reactionPost(
            post,
            adding: true,
            userId: "me",
            emojiName: "rocket"
        )
        XCTAssertEqual(added?.metadata?.reactions?.count, 1)
        XCTAssertEqual(added?.metadata?.reactions?.first?.emoji_name, "rocket")

        let removed = window.reactionPost(
            added!,
            adding: false,
            userId: "me",
            emojiName: "rocket"
        )
        XCTAssertEqual(removed?.metadata?.reactions?.count, 0)
    }

    func testReactionChipsWrapAtNarrowWidths() {
        let window = makeWindow()
        defer { window.close() }
        let post = makePost(reactions: [
            makeReaction("thumbsup", user: "u1"),
            makeReaction("heart", user: "u1"),
            makeReaction("clap", user: "u1"),
            makeReaction("rocket", user: "u1"),
            makeReaction("fire", user: "u1"),
        ])
        let wide = window.reactionChipsHeight(for: post, maxWidth: 500)
        let narrow = window.reactionChipsHeight(for: post, maxWidth: 80)
        XCTAssertGreaterThan(narrow, wide)
    }

    func testDeletedPostDoesNotRenderReactionControls() {
        let window = makeWindow()
        defer { window.close() }
        let post = makePost(
            reactions: [makeReaction("heart", user: "u1")],
            deleteAt: 2
        )
        let (row, _) = window.createPostRow(post: post, width: 900, timeStr: "12:00")
        XCTAssertNil(findView(in: row, identifier: "reactionAddChip"))
    }

    func testReactionPickerSearchFiltersTheFullCatalog() {
        let window = makeWindow()
        defer { window.close() }
        window.activeChannelId = "channel"
        let post = makePost(reactions: [])
        window.showReactionPicker(
            for: post,
            anchorRect: NSRect(x: 20, y: 20, width: 20, height: 20)
        )
        window.reactionPickerSearchField.stringValue = "rocket"
        window.renderReactionPickerGrid()
        XCTAssertTrue(window.reactionPickerEntries.contains { $0.name == "rocket" })
        XCTAssertFalse(window.reactionPickerEntries.contains { $0.name == "thumbsup" })
        window.closeReactionPicker()
    }

    func testRecentReactionsAreDeduplicatedAndCapped() {
        let window = makeWindow()
        defer { window.close() }
        window.recentReactionNames = []
        for index in 0..<30 {
            window.recordRecentReaction("emoji_\(index)")
        }
        window.recordRecentReaction("emoji_5")
        XCTAssertEqual(window.recentReactionNames.count, 24)
        XCTAssertEqual(window.recentReactionNames.first, "emoji_5")
        XCTAssertEqual(
            window.recentReactionNames.filter { $0 == "emoji_5" }.count,
            1
        )
    }

    private func findView(in view: NSView, identifier: String) -> NSView? {
        if view.identifier?.rawValue == identifier { return view }
        for subview in view.subviews {
            if let found = findView(in: subview, identifier: identifier) { return found }
        }
        return nil
    }

    private func makeWindow() -> MainWindow {
        MainWindow(
            contentRect: NSRect(x: 0, y: 0, width: 1000, height: 700),
            styleMask: [.titled, .resizable],
            backing: .buffered,
            defer: true
        )
    }

    private func makeReaction(_ name: String, user: String) -> MMReaction {
        MMReaction(user_id: user, post_id: "post", emoji_name: name, create_at: 1)
    }

    private func makePost(reactions: [MMReaction], deleteAt: Int64 = 0) -> MMPost {
        MMPost(
            id: "post",
            create_at: 1,
            update_at: nil,
            edit_at: nil,
            delete_at: deleteAt,
            is_pinned: nil,
            user_id: "user",
            channel_id: "channel",
            root_id: nil,
            original_id: nil,
            message: "hello",
            type: nil,
            file_ids: nil,
            metadata: MMPostMetadata(files: nil, reactions: reactions)
        )
    }
}
