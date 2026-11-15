//
//  ThreadSupport.swift
//  mattermost.client
//
//  Pure helpers for thread read state and reply pagination.
//

import Foundation

enum ThreadSupport {
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
