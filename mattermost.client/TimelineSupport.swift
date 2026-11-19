//
//  TimelineSupport.swift
//  mattermost.client
//
//  Pure helpers for timeline pagination and date-separator labelling. Keeping
//  them outside the window makes the behaviour straightforward to unit test.
//

import AppKit
import Foundation

/// In-memory cache for decoded attachment previews and inline images/gifs.
public final class TimelineImageCache: @unchecked Sendable {
    public static let shared = TimelineImageCache()

    private let cache = NSCache<NSString, NSImage>()

    public init(countLimit: Int = 300, totalCostLimit: Int = 100 * 1024 * 1024) {
        cache.countLimit = countLimit
        cache.totalCostLimit = totalCostLimit
    }

    public func image(forKey key: String) -> NSImage? {
        cache.object(forKey: key as NSString)
    }

    public func setImage(_ image: NSImage, forKey key: String, cost: Int = 0) {
        let estimatedCost = cost > 0 ? cost : Int(image.size.width * image.size.height * 4)
        cache.setObject(image, forKey: key as NSString, cost: estimatedCost)
    }

    public func removeImage(forKey key: String) {
        cache.removeObject(forKey: key as NSString)
    }

    public func clear() {
        cache.removeAllObjects()
    }
}

/// Identifies the rendered state of a post row to determine whether it can be reused without recreating views.
struct TimelineRowKey: Equatable {
    let postId: String
    let message: String
    let editAt: Int64?
    let deleteAt: Int64?
    let replyCount: Int
    let reactionsHash: Int
    let isPinned: Bool
    var isSaved: Bool = false
    let isConsecutive: Bool
    let width: CGFloat
    let fileIds: [String]
}

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

/// Human-readable text for Mattermost system posts. Falls back to the server's
/// message when a system type does not have a known local template.
enum SystemMessageText {
    static func text(for post: MMPost) -> String {
        let props = post.props
        let username = props?.username ?? "Someone"
        let channel = props?.channel_display_name ?? "the channel"
        let team = props?.team_display_name ?? "the team"
        let type = post.type ?? ""

        switch type {
        case "system_join_channel":
            return "\(username) joined \(channel)."
        case "system_leave_channel":
            return "\(username) left \(channel)."
        case "system_add_to_channel":
            return "\(username) added \(props?.addedUsername ?? "a member") to \(channel)."
        case "system_remove_from_channel":
            return "\(username) removed \(props?.removedUsername ?? "a member") from \(channel)."
        case "system_join_team":
            return "\(username) joined \(team)."
        case "system_leave_team":
            return "\(username) left \(team)."
        case "system_add_to_team":
            return "\(username) added \(props?.addedUsername ?? "a member") to \(team)."
        case "system_remove_from_team":
            return "\(username) removed \(props?.removedUsername ?? "a member") from \(team)."
        case "system_header_change":
            let header = props?.new_header?.trimmingCharacters(in: .whitespacesAndNewlines) ?? ""
            return header.isEmpty
                ? "\(username) removed the channel header."
                : "\(username) updated the channel header to: \(header)"
        case "system_purpose_change":
            let purpose = props?.new_purpose?.trimmingCharacters(in: .whitespacesAndNewlines) ?? ""
            return purpose.isEmpty
                ? "\(username) removed the channel purpose."
                : "\(username) updated the channel purpose to: \(purpose)"
        case "system_displayname_change":
            let oldName = props?.old_displayname ?? "the old name"
            let newName = props?.new_displayname ?? channel
            return "\(username) changed the channel name from \(oldName) to \(newName)."
        case "system_channel_deleted":
            return "\(username) deleted \(channel)."
        case "system_channel_restored":
            return "\(username) restored \(channel)."
        case "system_convert_channel_to_private":
            return "\(username) converted \(channel) to a private channel."
        case "system_convert_channel_to_public":
            return "\(username) converted \(channel) to a public channel."
        default:
            let message = post.message.trimmingCharacters(in: .whitespacesAndNewlines)
            return message.isEmpty ? "System update" : message
        }
    }
}
