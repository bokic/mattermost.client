//
//  TimelineSupportTests.swift
//  mattermost.clientTests
//

import XCTest

#if canImport(mattermost_client)
    @testable import mattermost_client
#endif

@MainActor
final class TimelineSupportTests: XCTestCase {

    // MARK: - Pagination

    func testMergeSortsAndDeduplicatesOlderPage() {
        let existing = [
            makePost(id: "c", createAt: 300),
            makePost(id: "a", createAt: 100),
        ]
        let older = [
            makePost(id: "b", createAt: 200),
            makePost(id: "a", createAt: 100),
        ]

        let page = TimelinePager.merge(existing: existing, older: older, pageSize: 2)

        XCTAssertEqual(page.posts.map { $0.id }, ["a", "b", "c"])
        XCTAssertEqual(page.inserted.map { $0.id }, ["b"])
        XCTAssertFalse(page.didReachEnd)
    }

    func testShortPageMarksEndOfHistory() {
        let page = TimelinePager.merge(
            existing: [makePost(id: "a", createAt: 100)],
            older: [makePost(id: "b", createAt: 200)],
            pageSize: 60
        )

        XCTAssertTrue(page.didReachEnd)
        XCTAssertEqual(page.inserted.count, 1)
    }

    func testFullPageOfDuplicatesMarksEndOfHistory() {
        let existing = [makePost(id: "a", createAt: 100), makePost(id: "b", createAt: 200)]
        let page = TimelinePager.merge(existing: existing, older: existing, pageSize: 2)

        XCTAssertTrue(page.inserted.isEmpty)
        XCTAssertTrue(page.didReachEnd)
    }

    func testEmptyOlderPageLeavesTimelineUnchanged() {
        let existing = [makePost(id: "a", createAt: 100)]
        let page = TimelinePager.merge(existing: existing, older: [], pageSize: 60)

        XCTAssertEqual(page.posts.map { $0.id }, ["a"])
        XCTAssertTrue(page.inserted.isEmpty)
        XCTAssertTrue(page.didReachEnd)
    }

    func testStableCacheKeyIsDeterministicAndDistinct() {
        XCTAssertEqual(
            TimelineCacheKey.stable("https://example.com/a.gif"),
            TimelineCacheKey.stable("https://example.com/a.gif")
        )
        XCTAssertNotEqual(
            TimelineCacheKey.stable("https://example.com/a.gif"),
            TimelineCacheKey.stable("https://example.com/b.gif")
        )
    }

    // MARK: - Date separators

    func testDateStyleIsRelativeForTodayAndYesterday() {
        var calendar = Calendar(identifier: .gregorian)
        calendar.timeZone = TimeZone(secondsFromGMT: 0)!
        let now = Date(timeIntervalSince1970: 1_700_000_000)  // 2023-11-14 22:13:20 UTC

        XCTAssertEqual(
            TimelineDateSeparator.style(for: now, now: now, calendar: calendar),
            .relative
        )
        let yesterday = calendar.date(byAdding: .day, value: -1, to: now)!
        XCTAssertEqual(
            TimelineDateSeparator.style(for: yesterday, now: now, calendar: calendar),
            .relative
        )
    }

    func testDateStyleIsWeekdayWithinSixDays() {
        var calendar = Calendar(identifier: .gregorian)
        calendar.timeZone = TimeZone(secondsFromGMT: 0)!
        let now = Date(timeIntervalSince1970: 1_700_000_000)
        let threeDaysAgo = calendar.date(byAdding: .day, value: -3, to: now)!

        XCTAssertEqual(
            TimelineDateSeparator.style(for: threeDaysAgo, now: now, calendar: calendar),
            .weekday
        )
    }

    func testDateStyleIsAbsoluteAfterAWeek() {
        var calendar = Calendar(identifier: .gregorian)
        calendar.timeZone = TimeZone(secondsFromGMT: 0)!
        let now = Date(timeIntervalSince1970: 1_700_000_000)
        let tenDaysAgo = calendar.date(byAdding: .day, value: -10, to: now)!

        XCTAssertEqual(
            TimelineDateSeparator.style(for: tenDaysAgo, now: now, calendar: calendar),
            .absolute
        )
    }

    func testFutureDateIsNotGivenAWeekdayLabel() {
        var calendar = Calendar(identifier: .gregorian)
        calendar.timeZone = TimeZone(secondsFromGMT: 0)!
        let now = Date(timeIntervalSince1970: 1_700_000_000)
        let tomorrow = calendar.date(byAdding: .day, value: 1, to: now)!

        XCTAssertEqual(
            TimelineDateSeparator.style(for: tomorrow, now: now, calendar: calendar),
            .absolute
        )
    }

    // MARK: - Timeline Image Cache & Diffing

    func testTimelineImageCacheStoreAndRetrieve() {
        let cache = TimelineImageCache(countLimit: 10, totalCostLimit: 1024 * 1024)
        let image = NSImage(size: NSSize(width: 50, height: 50))
        cache.setImage(image, forKey: "test_key")

        XCTAssertNotNil(cache.image(forKey: "test_key"))
        cache.removeImage(forKey: "test_key")
        XCTAssertNil(cache.image(forKey: "test_key"))

        cache.setImage(image, forKey: "key1")
        cache.setImage(image, forKey: "key2")
        cache.clear()
        XCTAssertNil(cache.image(forKey: "key1"))
        XCTAssertNil(cache.image(forKey: "key2"))
    }

    func testTimelineRowKeyEqualityAndDiff() {
        let key1 = TimelineRowKey(
            postId: "p1",
            message: "Hello",
            editAt: nil,
            deleteAt: nil,
            replyCount: 0,
            reactionsHash: 42,
            isPinned: false,
            isConsecutive: false,
            width: 800,
            fileIds: ["f1"]
        )
        let key2 = TimelineRowKey(
            postId: "p1",
            message: "Hello",
            editAt: nil,
            deleteAt: nil,
            replyCount: 0,
            reactionsHash: 42,
            isPinned: false,
            isConsecutive: false,
            width: 800,
            fileIds: ["f1"]
        )
        let keyModifiedMessage = TimelineRowKey(
            postId: "p1",
            message: "Hello World",
            editAt: nil,
            deleteAt: nil,
            replyCount: 0,
            reactionsHash: 42,
            isPinned: false,
            isConsecutive: false,
            width: 800,
            fileIds: ["f1"]
        )
        let keyModifiedReactions = TimelineRowKey(
            postId: "p1",
            message: "Hello",
            editAt: nil,
            deleteAt: nil,
            replyCount: 0,
            reactionsHash: 99,
            isPinned: false,
            isConsecutive: false,
            width: 800,
            fileIds: ["f1"]
        )

        XCTAssertEqual(key1, key2)
        XCTAssertNotEqual(key1, keyModifiedMessage)
        XCTAssertNotEqual(key1, keyModifiedReactions)
    }

    func testRebuildTimelineContentReusesUnchangedRows() {
        let window = makeWindow()
        defer { window.close() }

        let post1 = makePost(id: "p1", createAt: 1000)
        let post2 = makePost(id: "p2", createAt: 2000)
        window.currentChannelPosts = [post1, post2]
        window.rebuildTimelineContent(scrollToBottom: false)

        let initialRow1 = window.timelineDocView.subviews.first(where: {
            $0.identifier?.rawValue == "postRow_p1"
        })
        let initialRow2 = window.timelineDocView.subviews.first(where: {
            $0.identifier?.rawValue == "postRow_p2"
        })
        XCTAssertNotNil(initialRow1)
        XCTAssertNotNil(initialRow2)

        // Rebuild again without changes: rows MUST be reused directly (identical view instances)
        window.rebuildTimelineContent(scrollToBottom: false)

        let secondRow1 = window.timelineDocView.subviews.first(where: {
            $0.identifier?.rawValue == "postRow_p1"
        })
        let secondRow2 = window.timelineDocView.subviews.first(where: {
            $0.identifier?.rawValue == "postRow_p2"
        })

        XCTAssertTrue(initialRow1 === secondRow1, "Unchanged row p1 must be reused from cache")
        XCTAssertTrue(initialRow2 === secondRow2, "Unchanged row p2 must be reused from cache")
    }

    func testUpdatePostRowInTimelineReplacesTargetRowInPlace() {
        let window = makeWindow()
        defer { window.close() }

        let post1 = makePost(id: "p1", createAt: 1000)
        let post2 = makePost(id: "p2", createAt: 2000)
        window.currentChannelPosts = [post1, post2]
        window.rebuildTimelineContent(scrollToBottom: false)

        let originalRow2 = window.timelineDocView.subviews.first(where: {
            $0.identifier?.rawValue == "postRow_p2"
        })

        let updatedPost1 = makePost(
            id: "p1", createAt: 1000, message: "Updated message content that causes re-rendering")
        window.currentChannelPosts[0] = updatedPost1

        let didUpdate = window.updatePostRowInTimeline(updatedPost1)
        XCTAssertTrue(didUpdate)

        let newRow2 = window.timelineDocView.subviews.first(where: {
            $0.identifier?.rawValue == "postRow_p2"
        })
        XCTAssertTrue(originalRow2 === newRow2, "Post 2 must not be recreated when Post 1 updates")
    }

    func testDeletePostRowFromTimelineRemovesRowAndShiftsSubsequent() {
        let window = makeWindow()
        defer { window.close() }

        let post1 = makePost(id: "p1", createAt: 1000)
        let post2 = makePost(id: "p2", createAt: 2000)
        window.currentChannelPosts = [post1, post2]
        window.rebuildTimelineContent(scrollToBottom: false)

        let initialY2 =
            window.timelineDocView.subviews.first(where: {
                $0.identifier?.rawValue == "postRow_p2"
            })?.frame.origin.y ?? 0

        let didDelete = window.deletePostRowFromTimeline("p1")
        XCTAssertTrue(didDelete)
        XCTAssertNil(
            window.timelineDocView.subviews.first(where: {
                $0.identifier?.rawValue == "postRow_p1"
            }))

        let newY2 =
            window.timelineDocView.subviews.first(where: {
                $0.identifier?.rawValue == "postRow_p2"
            })?.frame.origin.y ?? 0
        XCTAssertLessThan(newY2, initialY2, "Post 2 should shift upward after deleting Post 1")
    }

    func testUpdateTimelineAvatarUpdatesAvatarInPlace() {
        let window = makeWindow()
        defer { window.close() }

        let post = makePost(id: "p1", createAt: 1000)
        window.currentChannelPosts = [post]
        window.rebuildTimelineContent(scrollToBottom: false)

        let newAvatar = NSImage(size: NSSize(width: 32, height: 32))
        window.updateTimelineAvatar(userId: "user-1", image: newAvatar)

        var foundAvatarImage: NSImage?
        func checkAvatar(_ view: NSView) {
            if view.identifier?.rawValue == "avatar_user-1",
                let imgView = view.subviews.compactMap({ $0 as? NSImageView }).first
            {
                foundAvatarImage = imgView.image
                return
            }
            view.subviews.forEach(checkAvatar)
        }
        checkAvatar(window.timelineDocView)

        XCTAssertTrue(foundAvatarImage === newAvatar, "Avatar view should have updated in place")
    }

    func testUpdateAuthorInfoUpdatesAuthorLabelInPlace() {
        let window = makeWindow()
        defer { window.close() }

        let post = makePost(id: "p1", createAt: 1000)
        window.currentChannelPosts = [post]
        window.rebuildTimelineContent(scrollToBottom: false)

        window.updateAuthorInfo(for: "user-1", username: "new_alice")

        var foundLabelText: String?
        func checkLabel(_ view: NSView) {
            if view.identifier?.rawValue == "authorLabel_user-1",
                let label = view as? NSTextField
            {
                foundLabelText = label.stringValue
                return
            }
            view.subviews.forEach(checkLabel)
        }
        checkLabel(window.timelineDocView)

        XCTAssertEqual(foundLabelText, "new_alice", "Author label should update in place")
    }

    func testBoundedImageCacheLimitsAndRemoval() {
        let cache = BoundedImageCache(countLimit: 2, totalCostLimit: 1024 * 1024)
        XCTAssertEqual(cache.countLimit, 2)
        XCTAssertEqual(cache.totalCostLimit, 1024 * 1024)

        let img = NSImage(size: NSSize(width: 10, height: 10))
        cache["a"] = img
        cache["b"] = img
        XCTAssertNotNil(cache["a"])
        XCTAssertNotNil(cache["b"])

        cache.removeValue(forKey: "a")
        XCTAssertNil(cache["a"])

        cache["c"] = img
        cache.removeAll()
        XCTAssertNil(cache["b"])
        XCTAssertNil(cache["c"])
    }

    func testBoundedSizeCacheLimitsAndRemoval() {
        let cache = BoundedSizeCache(countLimit: 2)
        XCTAssertEqual(cache.countLimit, 2)

        cache["a"] = NSSize(width: 100, height: 50)
        cache["b"] = NSSize(width: 200, height: 100)
        XCTAssertEqual(cache["a"], NSSize(width: 100, height: 50))

        cache.removeValue(forKey: "a")
        XCTAssertNil(cache["a"])

        cache.removeAll()
        XCTAssertNil(cache["b"])
    }

    func testCancelThumbnailTasksAndClearCaches() {
        let window = makeWindow()
        defer { window.close() }

        window.userAvatarsById["user1"] = NSImage(size: NSSize(width: 10, height: 10))
        window.inlineImageSizeCache["url1"] = NSSize(width: 100, height: 100)
        window.attachmentSizeCache["att1"] = NSSize(width: 200, height: 200)

        window.filePreviewTasks["f1"] = Task {
            try? await Task.sleep(nanoseconds: 100_000_000)
        }
        window.attachmentThumbnailTasks["a1"] = Task {
            try? await Task.sleep(nanoseconds: 100_000_000)
        }

        window.cancelAllThumbnailTasks()
        XCTAssertTrue(window.filePreviewTasks.isEmpty)
        XCTAssertTrue(window.attachmentThumbnailTasks.isEmpty)

        window.clearAllCaches()
        XCTAssertNil(window.userAvatarsById["user1"])
        XCTAssertNil(window.inlineImageSizeCache["url1"])
        XCTAssertNil(window.attachmentSizeCache["att1"])
    }

    func testPruneGiphyCacheBySizeAndCount() throws {
        let tempDir = FileManager.default.temporaryDirectory.appendingPathComponent(
            "giphy_prune_test_\(UUID().uuidString)")
        try FileManager.default.createDirectory(at: tempDir, withIntermediateDirectories: true)
        defer { try? FileManager.default.removeItem(at: tempDir) }

        let payload = Data(repeating: 0x47, count: 1024)
        for i in 1...5 {
            let fileURL = tempDir.appendingPathComponent("file_\(i).gif")
            try payload.write(to: fileURL)
            let pastDate = Date(timeIntervalSinceNow: -TimeInterval(100 - i * 10))
            try FileManager.default.setAttributes(
                [.modificationDate: pastDate], ofItemAtPath: fileURL.path)
        }

        MainWindow.pruneGiphyCache(tempDir, keeping: 3, maxTotalBytes: 100 * 1024)
        var remaining = try FileManager.default.contentsOfDirectory(atPath: tempDir.path)
        XCTAssertEqual(remaining.count, 3)

        MainWindow.pruneGiphyCache(tempDir, keeping: 10, maxTotalBytes: 1500)
        remaining = try FileManager.default.contentsOfDirectory(atPath: tempDir.path)
        XCTAssertLessThanOrEqual(remaining.count, 1)
    }

    private func makeWindow() -> MainWindow {
        MainWindow(
            contentRect: NSRect(x: 0, y: 0, width: 1000, height: 700),
            styleMask: [.titled, .resizable],
            backing: .buffered,
            defer: true
        )
    }

    private func makePost(id: String, createAt: Int64, message: String? = nil) -> MMPost {
        MMPost(
            id: id,
            create_at: createAt,
            update_at: createAt,
            edit_at: nil,
            delete_at: nil,
            is_pinned: false,
            user_id: "user-1",
            channel_id: "town-square",
            root_id: nil,
            original_id: nil,
            message: message ?? id,
            type: nil
        )
    }
}
