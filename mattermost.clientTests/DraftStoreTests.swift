//
//  DraftStoreTests.swift
//  mattermost.clientTests
//

import XCTest

@testable import mattermost_client

@MainActor
final class DraftStoreTests: XCTestCase {

    private func makeStore(scope: StoreScope = .global) -> (DraftStore, UserDefaults, String) {
        let suite = "DraftStoreTests.\(UUID().uuidString)"
        let defaults = UserDefaults(suiteName: suite)!
        let store = DraftStore(scope: scope, defaults: defaults)
        return (store, defaults, suite)
    }

    func testSaveAndRestoreChannelDraft() {
        let (store, defaults, suite) = makeStore(scope: StoreScope(server: "serverA", userId: "userA"))
        defer { defaults.removePersistentDomain(forName: suite) }

        let attachment = PendingAttachment(
            id: "att_1",
            name: "screenshot.png",
            size: 1024
        )
        let draft = ComposerDraft(text: "Hello world!", attachments: [attachment])

        store.saveChannelDraft(draft, for: "chan_123")

        let restored = store.channelDraft(for: "chan_123")
        XCTAssertNotNil(restored)
        XCTAssertEqual(restored?.text, "Hello world!")
        XCTAssertEqual(restored?.attachments.count, 1)
        XCTAssertEqual(restored?.attachments.first?.name, "screenshot.png")

        let all = store.allChannelDrafts()
        XCTAssertEqual(all["chan_123"]?.text, "Hello world!")

        store.removeChannelDraft(for: "chan_123")
        XCTAssertNil(store.channelDraft(for: "chan_123"))
    }

    func testSaveAndRestoreThreadDraft() {
        let (store, defaults, suite) = makeStore(scope: StoreScope(server: "serverA", userId: "userA"))
        defer { defaults.removePersistentDomain(forName: suite) }

        store.saveThreadDraft("Reply in thread", for: "root_post_456")

        let restored = store.threadDraft(for: "root_post_456")
        XCTAssertNotNil(restored)
        XCTAssertEqual(restored, "Reply in thread")

        let all = store.allThreadDrafts()
        XCTAssertEqual(all["root_post_456"], "Reply in thread")

        store.removeThreadDraft(for: "root_post_456")
        XCTAssertNil(store.threadDraft(for: "root_post_456"))
    }

    func testDraftScopeIsolation() {
        let (store, defaults, suite) = makeStore(scope: StoreScope(server: "serverA", userId: "userA"))
        defer { defaults.removePersistentDomain(forName: suite) }

        let draftA = ComposerDraft(text: "Draft on Server A")
        store.saveChannelDraft(draftA, for: "common_chan")

        // Switch scope to serverB / userB
        store.scope = StoreScope(server: "serverB", userId: "userB")
        XCTAssertNil(store.channelDraft(for: "common_chan"))

        let draftB = ComposerDraft(text: "Draft on Server B")
        store.saveChannelDraft(draftB, for: "common_chan")
        XCTAssertEqual(store.channelDraft(for: "common_chan")?.text, "Draft on Server B")

        // Switch back to serverA / userA
        store.scope = StoreScope(server: "serverA", userId: "userA")
        XCTAssertEqual(store.channelDraft(for: "common_chan")?.text, "Draft on Server A")
    }

    func testEmptyDraftClearsAutomatically() {
        let (store, defaults, suite) = makeStore(scope: .global)
        defer { defaults.removePersistentDomain(forName: suite) }

        let draft = ComposerDraft(text: "Initial text")
        store.saveChannelDraft(draft, for: "chan_1")
        XCTAssertNotNil(store.channelDraft(for: "chan_1"))

        // Saving empty text with no attachments clears the draft
        let emptyDraft = ComposerDraft(text: "")
        store.saveChannelDraft(emptyDraft, for: "chan_1")
        XCTAssertNil(store.channelDraft(for: "chan_1"))

        // Thread draft
        store.saveThreadDraft("Thread text", for: "root_1")
        XCTAssertEqual(store.threadDraft(for: "root_1"), "Thread text")
        store.saveThreadDraft("", for: "root_1")
        XCTAssertNil(store.threadDraft(for: "root_1"))
    }

    func testClearAll() {
        let (store, defaults, suite) = makeStore(scope: .global)
        defer { defaults.removePersistentDomain(forName: suite) }

        store.saveChannelDraft(ComposerDraft(text: "draft 1"), for: "c1")
        store.saveThreadDraft("thread 1", for: "t1")

        XCTAssertFalse(store.allChannelDrafts().isEmpty)
        XCTAssertFalse(store.allThreadDrafts().isEmpty)

        store.clearAllChannelDrafts()
        store.clearAllThreadDrafts()

        XCTAssertTrue(store.allChannelDrafts().isEmpty)
        XCTAssertTrue(store.allThreadDrafts().isEmpty)
    }
}
