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

    private func makePost(id: String, createAt: Int64) -> MMPost {
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
            message: id,
            type: nil
        )
    }
}
