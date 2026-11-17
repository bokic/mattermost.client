//
//  ThreadSupport.swift
//  mattermost.client
//
//  Pure helpers for thread read state and reply pagination.
//

import CoreGraphics
import Foundation

enum ThreadSupport {
    static let minThreadComposerScrollHeight: CGFloat = 48
    static let maxThreadComposerScrollHeight: CGFloat = 140
    static let threadComposerBaseOverhead: CGFloat = 44

    static func composerScrollHeight(
        contentHeight: CGFloat,
        minHeight: CGFloat = minThreadComposerScrollHeight,
        maxHeight: CGFloat = maxThreadComposerScrollHeight
    ) -> CGFloat {
        let clampedMin = max(0, minHeight)
        let clampedMax = max(clampedMin, maxHeight)
        let rounded = ceil(contentHeight)
        return min(max(rounded, clampedMin), clampedMax)
    }

    static func isUnread(
        lastReplyAt: Int64?,
        lastViewedAt: Int64?,
        isMarkedRead: Bool
    ) -> Bool {
        guard !isMarkedRead else { return false }
        return (lastReplyAt ?? 0) > (lastViewedAt ?? 0)
    }

    static func visibleReplies(_ replies: [MMPost], limit: Int) -> (posts: [MMPost], hidden: Int) {
        let safeLimit = max(0, limit)
        guard replies.count > safeLimit else { return (replies, 0) }
        return (Array(replies.suffix(safeLimit)), replies.count - safeLimit)
    }
}
