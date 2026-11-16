//
//  Models.swift
//  mattermost.client
//

import Foundation

struct MMTeam: Codable {
    let id: String
    let create_at: Int64?
    let update_at: Int64?
    let delete_at: Int64?
    let display_name: String
    let name: String
    let description: String?
    let email: String?
    let type: String?
    let company_name: String?
    let allowed_domains: String?
    let invite_id: String?
    let allow_open_invite: Bool?
}

struct MMTeamUnread: Codable {
    let team_id: String
    let msg_count: Int
    let mention_count: Int
}

struct MMTeamMember: Codable {
    let team_id: String
    let user_id: String
    let roles: String?
    let delete_at: Int64?
    let scheme_guest: Bool?
    let scheme_user: Bool?
    let scheme_admin: Bool?
    let explicit_roles: String?
}

struct MMChannel: Codable {
    let id: String
    let create_at: Int64?
    let update_at: Int64?
    let delete_at: Int64?
    let team_id: String?
    let type: String
    let display_name: String
    let name: String
    let header: String?
    let purpose: String?
    let last_post_at: Int64?
    let total_msg_count: Int64?
    let creator_id: String?
}

struct MMSidebarCategory: Codable {
    let id: String
    let user_id: String?
    let team_id: String?
    let sort_order: Int?
    let sorting: String?
    let type: String
    let display_name: String
    let muted: Bool?
    let collapsed: Bool?
    let channel_ids: [String]
}

struct MMSidebarCategoriesResponse: Codable {
    let categories: [MMSidebarCategory]
    let order: [String]
}

struct MMFileInfo: Codable {
    let id: String
    let name: String?
    let `extension`: String?
    let mime_type: String?
    let size: Int64?
    let width: Int?
    let height: Int?
    // Present on file-search results but absent from post metadata.
    let user_id: String?
    let post_id: String?
    let channel_id: String?
    let create_at: Int64?
    let has_preview_image: Bool?
}

struct MMFileSearchResult: Decodable {
    let order: [String]
    let file_infos: [String: MMFileInfo]
    let next_file_info_id: String?
    let prev_file_info_id: String?
}

struct MMEmoji: Decodable {
    let id: String
    let name: String
    let creator_id: String?
}

struct MMReaction: Codable {
    let user_id: String?
    let post_id: String?
    let emoji_name: String?
    let create_at: Int64?
}

struct MMPostMetadata: Codable {
    let files: [MMFileInfo]?
    let reactions: [MMReaction]?
}

struct MMLinkMetadata: Codable {
    let url: String?
    let title: String?
    let description: String?
    let image_url: String?
    let site_name: String?
}

struct MMPostProps: Codable {
    var username: String? = nil
    var channel_display_name: String? = nil
    var team_display_name: String? = nil
    var addedUsername: String? = nil
    var removedUsername: String? = nil
    var new_header: String? = nil
    var old_header: String? = nil
    var new_purpose: String? = nil
    var old_purpose: String? = nil
    var new_displayname: String? = nil
    var old_displayname: String? = nil
}

struct MMPost: Codable {
    let id: String
    let create_at: Int64
    let update_at: Int64?
    let edit_at: Int64?
    let delete_at: Int64?
    let is_pinned: Bool?
    let user_id: String
    let channel_id: String
    let root_id: String?
    let original_id: String?
    let message: String
    let type: String?
    var file_ids: [String]? = nil
    var metadata: MMPostMetadata? = nil
    var reply_count: Int? = nil
    var props: MMPostProps? = nil
}

extension MMPost: Equatable {
    static func == (lhs: MMPost, rhs: MMPost) -> Bool {
        lhs.id == rhs.id
    }
}

struct MMThreadParticipant: Decodable {
    let id: String?
    let username: String?
}

struct MMThread: Decodable {
    let id: String
    let reply_count: Int?
    let last_reply_at: Int64?
    let last_viewed_at: Int64?
    let participants: [MMThreadParticipant]?
    let post: MMPost?
}

struct MMThreadsResponse: Decodable {
    let threads: [MMThread]
    let total: Int?
    let total_unread_threads: Int?
    let total_unread_mentions: Int?
}

struct MMChannelMembership: Decodable {
    struct NotifyProps: Decodable {
        let desktop: String?
        let mark_unread: String?
        let ignore_channel_mentions: String?
    }

    let channel_id: String
    let msg_count: Int?
    let mention_count: Int?
    let last_viewed_at: Int64?
    let last_update_at: Int64?
    let notify_props: NotifyProps?
}

struct MMChannelMember: Decodable {
    let user_id: String
    let channel_id: String
    let roles: String?
}

struct MMPostList: Codable {
    let order: [String]
    let posts: [String: MMPost]
    let next_post_id: String?
    let prev_post_id: String?

    var chronologicalPosts: [MMPost] {
        return order.reversed().compactMap { posts[$0] }
    }
}

struct MMUserStatus: Codable {
    let user_id: String
    let status: String
    let manual: Bool?
    let last_activity_at: Int64?
    let active_channel: String?
    let dnd_end_time: Int64?
}

enum MMWebSocketEvent {
    case hello
    case posted(post: MMPost, senderName: String?, channelDisplayName: String?, channelName: String?, teamId: String?)
    case postEdited(post: MMPost)
    case postDeleted(postId: String, channelId: String)
    case postUnread(channelId: String)
    case channelViewed(channelId: String)
    case channelUpdated(channel: MMChannel)
    case channelMembershipChanged(channelId: String, userId: String)
    case preferencesChanged(userId: String)
    case threadUpdated(rootId: String, replyCount: Int?)
    case emojiAdded
    case statusChange(userId: String, status: String)
    case userStatuses(statuses: [String: String])
    case typing(userId: String, channelId: String, parentId: String?)
    case updateTeam(team: MMTeam)
    case addedToTeam(teamId: String, userId: String)
    case leaveTeam(teamId: String, userId: String)
    case sidebarCategoriesUpdated
    case reactionChanged(postId: String)
    case other(event: String, data: [String: Any])
}

struct MMUser: Codable {
    let id: String
    let create_at: Int64?
    let update_at: Int64?
    let delete_at: Int64?
    let username: String
    let first_name: String?
    let last_name: String?
    let nickname: String?
    let email: String?
    let email_verified: Bool?
    let auth_service: String?
    let roles: String?
    let locale: String?
    let position: String?
    let is_bot: Bool?
    let last_password_update: Int64?
    let remote_id: String?
    let disable_welcome_email: Bool?

    let notify_props: NotifyProps?
    var props: [String: String]? = nil
    struct NotifyProps: Codable {
        let channel: String?
        let comments: String?
        let desktop: String?
        let desktop_sound: String?
        let desktop_threads: String?
        let email: String?
        let email_threads: String?
        let first_name: String?
        let mention_keys: String?
        let push: String?
        let push_status: String?
        let push_threads: String?
    }

    let timezone: MMTimeZone?
    struct MMTimeZone: Codable {
        let useAutomaticTimezone: String?
        let manualTimezone: String?
        let automaticTimezone: String?
    }

    let auth_data: String?
}
