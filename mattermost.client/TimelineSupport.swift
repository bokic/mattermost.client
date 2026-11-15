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
    static func merge(existing: [MMPost], older: [MMPost], pageSize: Int) -> TimelinePageMerge {
        let existingIds = Set(existing.map { $0.id })
        let inserted = older.filter { !existingIds.contains($0.id) }
        let posts = (existing + inserted).sorted { $0.create_at < $1.create_at }
        return TimelinePageMerge(
            posts: posts,
            inserted: inserted,
            didReachEnd: older.count < pageSize
        )
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
        if days < 6 {
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
