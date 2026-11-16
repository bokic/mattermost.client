//
//  ComposerIntegrationTests.swift
//  mattermost.clientTests
//

import XCTest

#if canImport(mattermost_client)
    @testable import mattermost_client
#endif

@MainActor
final class ComposerIntegrationTests: XCTestCase {

    // MARK: - Pending Outgoing Post Lifecycle

    func testPendingPostInitialStateIsSending() {
        let post = MainWindow.PendingOutgoingPost(
            id: "pending-1",
            channelId: "chan-1",
            message: "Hello world!",
            fileIds: ["file-1", "file-2"],
            status: .sending
        )

        XCTAssertEqual(post.id, "pending-1")
        XCTAssertEqual(post.channelId, "chan-1")
        XCTAssertEqual(post.message, "Hello world!")
        XCTAssertEqual(post.fileIds, ["file-1", "file-2"])
        if case .sending = post.status {
            // expected
        } else {
            XCTFail("Expected status to be .sending")
        }
    }

    func testPendingPostFailureAndRetryTransition() {
        var posts: [MainWindow.PendingOutgoingPost] = [
            MainWindow.PendingOutgoingPost(
                id: "pending-2",
                channelId: "chan-1",
                message: "Retry test message",
                fileIds: [],
                status: .sending
            )
        ]

        // Transition to failed
        let failureError = "Connection timed out"
        if let idx = posts.firstIndex(where: { $0.id == "pending-2" }) {
            posts[idx].status = .failed(failureError)
        }

        if case .failed(let reason) = posts[0].status {
            XCTAssertEqual(reason, failureError)
        } else {
            XCTFail("Expected status to be .failed")
        }

        // Retry: transition back to sending
        if let idx = posts.firstIndex(where: { $0.id == "pending-2" }) {
            posts[idx].status = .sending
        }

        if case .sending = posts[0].status {
            // expected
        } else {
            XCTFail("Expected status to be .sending on retry")
        }

        // Delete pending post
        posts.removeAll { $0.id == "pending-2" }
        XCTAssertTrue(posts.isEmpty)
    }

    // MARK: - Composer Draft Lifecycle

    func testComposerDraftSavedAndClearedOnSend() {
        let suite = "ComposerIntegrationTests.\(UUID().uuidString)"
        let defaults = UserDefaults(suiteName: suite)!
        defer { defaults.removePersistentDomain(forName: suite) }

        let store = DraftStore(scope: StoreScope(server: "chat.example.com", userId: "user-1"), defaults: defaults)

        // User types a draft in channel
        let draft = ComposerDraft(
            text: "Unsent message draft",
            attachments: [
                PendingAttachment(id: "att-1", name: "report.pdf", size: 2048)
            ]
        )
        store.saveChannelDraft(draft, for: "chan-alpha")

        // Draft is preserved
        let loaded = store.channelDraft(for: "chan-alpha")
        XCTAssertNotNil(loaded)
        XCTAssertEqual(loaded?.text, "Unsent message draft")
        XCTAssertEqual(loaded?.attachments.count, 1)

        // When message is sent, draft is cleared
        store.removeChannelDraft(for: "chan-alpha")
        XCTAssertNil(store.channelDraft(for: "chan-alpha"))
    }

    func testThreadDraftSavedAndClearedOnSend() {
        let suite = "ComposerIntegrationTests.\(UUID().uuidString)"
        let defaults = UserDefaults(suiteName: suite)!
        defer { defaults.removePersistentDomain(forName: suite) }

        let store = DraftStore(scope: StoreScope(server: "chat.example.com", userId: "user-1"), defaults: defaults)

        store.saveThreadDraft("Thread reply draft", for: "root-post-99")
        XCTAssertEqual(store.threadDraft(for: "root-post-99"), "Thread reply draft")

        store.removeThreadDraft(for: "root-post-99")
        XCTAssertNil(store.threadDraft(for: "root-post-99"))
    }

    // MARK: - Attachment Validation in Composer

    func testAttachmentExceedsLimitValidation() {
        let limit: Int64 = 50 * 1024 * 1024  // 50 MB
        let acceptableFile = PendingAttachment(id: "att-ok", name: "image.png", size: 10 * 1024 * 1024)
        let oversizedFile = PendingAttachment(id: "att-big", name: "video.mov", size: 60 * 1024 * 1024)

        XCTAssertFalse(AttachmentUploadPolicy.exceedsLimit(size: acceptableFile.size ?? 0, limit: limit))
        XCTAssertTrue(AttachmentUploadPolicy.exceedsLimit(size: oversizedFile.size ?? 0, limit: limit))
    }
}
