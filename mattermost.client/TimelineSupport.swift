//
//  TimelineSupport.swift
//  mattermost.client
//
//  Pure helpers for timeline pagination and date-separator labelling. Keeping
//  them outside the window makes the behaviour straightforward to unit test.
//

import Foundation

/// Result of merging a page of older posts into the current timeline.
struct TimelinePageMerge {
    let posts: [MMPost]
    /// Posts that were not already present, in the server's page order.
    let inserted: [MMPost]
    /// True when the page was shorter than a full page (start of history).
    let didReachEnd: Bool
}

enum TimelinePager {
    static let pageSize = 60
    static func merge(existing: [MMPost], older: [MMPost], pageSize: Int) -> TimelinePageMerge {
        let existingIds = Set(existing.map { $0.id })
        var byId: [String: MMPost] = [:]
        for post in existing { byId[post.id] = post }
        // Older pages may contain a fresher copy (or an edit) of an existing post;
        // prefer it instead of dropping it as a duplicate.
        for post in older { byId[post.id] = post }
        let inserted = older.filter { !existingIds.contains($0.id) }
        let posts = byId.values.sorted {
            if $0.create_at == $1.create_at { return $0.id < $1.id }
            return $0.create_at < $1.create_at
        }
        return TimelinePageMerge(
            posts: posts,
            inserted: inserted,
            // A page made entirely of duplicates means the server repeated a page;
            // stop rather than refetching it forever.
            didReachEnd: older.count < pageSize || (inserted.isEmpty && !older.isEmpty)
        )
    }
}

/// Stable, process-independent key for on-disk image caches. Swift's
/// `hashValue` is seeded per launch and must not be used for cache names.
enum TimelineCacheKey {
    static func stable(_ value: String) -> String {
        var hash: UInt64 = 14_695_981_039_346_656_037
        for byte in value.utf8 {
            hash ^= UInt64(byte)
            hash = hash &* 1_099_511_628_211
        }
        return String(hash, radix: 16)
    }
}

/// Which label style a date separator should use.
enum TimelineDateStyle: Equatable {
    case relative
    case weekday
    case absolute
}

/// Date formatters for timeline separators and post metadata.
@MainActor
enum TimelineDateFormatter {
    static let relative: DateFormatter = {
        let formatter = DateFormatter()
        formatter.locale = .current
        formatter.dateStyle = .medium
        formatter.timeStyle = .none
        formatter.doesRelativeDateFormatting = true
        return formatter
    }()

    static let weekday: DateFormatter = {
        let formatter = DateFormatter()
        formatter.locale = .current
        formatter.setLocalizedDateFormatFromTemplate("EEEE")
        return formatter
    }()

    static let date: DateFormatter = {
        let formatter = DateFormatter()
        formatter.locale = .current
        formatter.dateStyle = .medium
        formatter.timeStyle = .none
        return formatter
    }()
}

/// Matches the web client's date separator labels: relative for today/yesterday,
/// weekday name for the previous few days, then a localized date.
@MainActor
enum TimelineDateSeparator {
    static func style(for date: Date, now: Date = Date(), calendar: Calendar = .current) -> TimelineDateStyle {
        let start = calendar.startOfDay(for: date)
        let today = calendar.startOfDay(for: now)
        let days = calendar.dateComponents([.day], from: start, to: today).day ?? 99

        if days == 0 || days == 1 {
            return .relative
        }
        if days >= 2 && days < 6 {
            return .weekday
        }
        return .absolute
    }

    static func string(for date: Date, now: Date = Date(), calendar: Calendar = .current) -> String {
        switch style(for: date, now: now, calendar: calendar) {
        case .relative:
            return TimelineDateFormatter.relative.string(from: date)
        case .weekday:
            return TimelineDateFormatter.weekday.string(from: date)
        case .absolute:
            return TimelineDateFormatter.date.string(from: date)
        }
    }
}
