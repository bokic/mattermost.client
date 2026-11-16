//
//  WorkspaceRepository.swift
//  mattermost.client
//
//  Coordinates workspace orchestration: loading initial workspace data, channel switching,
//  pagination and merging via TimelinePager, read-state transitions, mention detection,
//  notification routing, and real-time reconciliation.
//  Decoupled from AppKit / NSWindow so that the business logic can be unit-tested
//  independently of view components.
//

import Foundation

struct NotificationRoute: Equatable, Sendable {
    let channelId: String
    let channelName: String
    let author: String
    let body: String
    let postId: String
    let rootId: String?
    let shouldNotify: Bool
    let sound: Bool

    init(
        channelId: String,
        channelName: String,
        author: String,
        body: String,
        postId: String,
        rootId: String?,
        shouldNotify: Bool,
        sound: Bool
    ) {
        self.channelId = channelId
        self.channelName = channelName
        self.author = author
        self.body = body
        self.postId = postId
        self.rootId = rootId
        self.shouldNotify = shouldNotify
        self.sound = sound
    }
}

enum IncomingPostDecision: Equatable, Sendable {
    case ignoreSelfOrSystem
    case visibleInActiveChannel(channelId: String)
    case muted(channelId: String)
    case notify(NotificationRoute)
}

struct ChannelPostsFetchResult: Equatable, Sendable {
    let posts: [MMPost]
    let missingUserIds: [String]
    let unknownStatusIds: [String]
    let didReachEnd: Bool
    let newMessagesBaseline: Int64
    let newMessagesCount: Int
    let newMessagesDividerPostId: String?

    init(
        posts: [MMPost],
        missingUserIds: [String],
        unknownStatusIds: [String],
        didReachEnd: Bool,
        newMessagesBaseline: Int64,
        newMessagesCount: Int,
        newMessagesDividerPostId: String?
    ) {
        self.posts = posts
        self.missingUserIds = missingUserIds
        self.unknownStatusIds = unknownStatusIds
        self.didReachEnd = didReachEnd
        self.newMessagesBaseline = newMessagesBaseline
        self.newMessagesCount = newMessagesCount
        self.newMessagesDividerPostId = newMessagesDividerPostId
    }
}

struct OlderPostsMergeResult: Equatable, Sendable {
    let posts: [MMPost]
    let insertedCount: Int
    let didReachEnd: Bool
    let missingUserIds: [String]

    init(
        posts: [MMPost],
        insertedCount: Int,
        didReachEnd: Bool,
        missingUserIds: [String]
    ) {
        self.posts = posts
        self.insertedCount = insertedCount
        self.didReachEnd = didReachEnd
        self.missingUserIds = missingUserIds
    }
}

enum RealtimePostResult: Equatable, Sendable {
    case ignoredNotCurrentChannel
    case ignoredDuplicate
    case threadReply(rootId: String, replyCount: Int)
    case topLevel(post: MMPost, isUnread: Bool, missingUserId: String?)
}

struct PostDeletionResult: Equatable, Sendable {
    let postId: String
    let channelId: String
    let wasThreadRoot: Bool
    let isCurrentChannel: Bool

    init(
        postId: String,
        channelId: String,
        wasThreadRoot: Bool,
        isCurrentChannel: Bool
    ) {
        self.postId = postId
        self.channelId = channelId
        self.wasThreadRoot = wasThreadRoot
        self.isCurrentChannel = isCurrentChannel
    }
}

struct InitialWorkspaceResult: @unchecked Sendable {
    let me: MMUser
    let myStatus: String?
    let dndEndTime: Int64?
    let teams: [MMTeam]
    let activeTeam: MMTeam
    let allChannels: [MMChannel]
    let initialChannel: MMChannel?

    init(
        me: MMUser,
        myStatus: String?,
        dndEndTime: Int64?,
        teams: [MMTeam],
        activeTeam: MMTeam,
        allChannels: [MMChannel],
        initialChannel: MMChannel?
    ) {
        self.me = me
        self.myStatus = myStatus
        self.dndEndTime = dndEndTime
        self.teams = teams
        self.activeTeam = activeTeam
        self.allChannels = allChannels
        self.initialChannel = initialChannel
    }
}

@MainActor
protocol WorkspaceRepositoryProtocol: AnyObject {
    var state: ChatViewModel { get }
    var webService: WebService? { get set }

    // Read State
    func markChannelViewed(channelId: String) async throws -> Int64
    func markChannelReadLocally(channelId: String)
    func markChannelUnread(channelId: String, userId: String, postId: String) async throws
    func markAllChannelsRead(teamId: String, userId: String) async throws -> Set<String>
    func handleRemoteChannelViewed(_ channelId: String)
    func handleRemoteChannelUnread(_ channelId: String)
    func computeNewMessagesBaseline(for channelId: String, posts: [MMPost]) -> (baseline: Int64, unreadCount: Int, dividerPostId: String?)

    // Mentions & Notification Routing
    func isCurrentUserMentioned(in post: MMPost) -> Bool
    func isChannelMuted(_ channelId: String, mutedChannelIds: Set<String>, desktopNotificationOverrides: [String: String]) -> Bool
    func notificationExcerpt(from message: String) -> String
    func evaluateIncomingPost(_ post: MMPost, isVisible: Bool, mutedChannelIds: Set<String>, desktopNotificationOverrides: [String: String]) -> IncomingPostDecision

    // Posts & Pagination
    func fetchChannelPosts(channelId: String, pageSize: Int) async throws -> ChannelPostsFetchResult
    func mergeOlderPosts(older: [MMPost], pageSize: Int) -> OlderPostsMergeResult
    func appendRealtimePost(_ post: MMPost, isScrolledUp: Bool) -> RealtimePostResult
    func handleRealtimePostDeleted(postId: String, channelId: String) -> PostDeletionResult
    func updateThreadReplyCount(rootId: String, replyCount: Int?) -> (previousCount: Int?, newCount: Int)

    // Workspace Navigation & Setup
    func channelBelongsToTeam(_ channel: MMChannel, teamId: String) -> Bool
    func resolveDefaultChannel(teamId: String, channels: [MMChannel], savedChannelId: String?, systemBotArg: Bool) -> MMChannel?
    func updateChannel(_ channel: MMChannel)
    func updateTeam(_ team: MMTeam)
    func updateUserTeams(_ teams: [MMTeam], savedTeamId: String?) -> (teams: [MMTeam], activeTeam: MMTeam?)
    func channelDisplayName(for channel: MMChannel) -> String
}

@MainActor
final class WorkspaceRepository: WorkspaceRepositoryProtocol {
    let state: ChatViewModel

    var webService: WebService? {
        get { state.webService }
        set { state.webService = newValue }
    }

    init(state: ChatViewModel) {
        self.state = state
    }

    // MARK: - ID & DM Helpers

    static func isLikelyMattermostId(_ str: String) -> Bool {
        return str.count == 26 && str.allSatisfy { ($0 >= "a" && $0 <= "z") || ($0 >= "0" && $0 <= "9") }
    }

    static func isRawDMNameOrId(_ str: String) -> Bool {
        if str.contains("__") { return true }
        return isLikelyMattermostId(str)
    }

    func resolveDMTargetUserId(for channel: MMChannel) -> String? {
        guard channel.type == "D" else { return nil }
        let myId = state.currentUser?.id ?? ""
        if channel.name.contains("__") {
            let parts = channel.name.components(separatedBy: "__")
            if parts.count >= 2 {
                if !myId.isEmpty {
                    if parts[0] == myId && parts[1] == myId {
                        return myId
                    } else if parts[0] == myId {
                        return parts[1]
                    } else if parts[1] == myId {
                        return parts[0]
                    }
                }
                return (parts[0] == myId && parts.count > 1) ? parts[1] : parts[0]
            }
        }
        if !channel.name.isEmpty {
            return channel.name
        }
        return nil
    }

    func channelDisplayName(for channel: MMChannel) -> String {
        if channel.type == "D" {
            if let targetId = resolveDMTargetUserId(for: channel),
               let user = state.usersById[targetId] {
                return (user.id == state.currentUser?.id) ? "\(user.username) (you)" : user.username
            }
            if !channel.display_name.isEmpty && !Self.isRawDMNameOrId(channel.display_name) {
                return channel.display_name
            }
            if let targetId = resolveDMTargetUserId(for: channel), !Self.isLikelyMattermostId(targetId) {
                return targetId
            }
        }
        return channel.display_name.isEmpty ? channel.name : channel.display_name
    }

    // MARK: - Read State

    func markChannelViewed(channelId: String) async throws -> Int64 {
        guard let ws = webService, ws.isLogged() else { return 0 }
        let viewedAt = (try await ws.markChannelViewed(channelId: channelId)) ?? Int64(Date().timeIntervalSince1970 * 1000)
        state.lastViewedAtByChannel[channelId] = viewedAt
        state.unreadByChannel[channelId] = 0
        state.mentionsByChannel[channelId] = 0
        return viewedAt
    }

    func markChannelReadLocally(channelId: String) {
        state.unreadByChannel[channelId] = 0
        state.mentionsByChannel[channelId] = 0
    }

    func markChannelUnread(channelId: String, userId: String, postId: String) async throws {
        guard let ws = webService, ws.isLogged() else { return }
        try await ws.markChannelUnread(userId: userId, channelId: channelId, postId: postId)
        state.unreadByChannel[channelId, default: 0] = max(1, state.unreadByChannel[channelId] ?? 0)
    }

    func markAllChannelsRead(teamId: String, userId: String) async throws -> Set<String> {
        guard let ws = webService, ws.isLogged() else { return [] }
        let teamChannelIds = Set(state.channelsById.values.filter {
            channelBelongsToTeam($0, teamId: teamId)
        }.map { $0.id })
        try await ws.markAllChannelsRead(userId: userId, teamId: teamId)
        let now = Int64(Date().timeIntervalSince1970 * 1000)
        for channelId in teamChannelIds {
            state.unreadByChannel[channelId] = 0
            state.mentionsByChannel[channelId] = 0
            state.lastViewedAtByChannel[channelId] = now
        }
        return teamChannelIds
    }

    func handleRemoteChannelViewed(_ channelId: String) {
        guard !channelId.isEmpty else { return }
        state.unreadByChannel[channelId] = 0
        state.mentionsByChannel[channelId] = 0
        state.lastViewedAtByChannel[channelId] = Int64(Date().timeIntervalSince1970 * 1000)
    }

    func handleRemoteChannelUnread(_ channelId: String) {
        guard !channelId.isEmpty, channelId != state.activeChannelId else { return }
        state.unreadByChannel[channelId, default: 0] = max(1, state.unreadByChannel[channelId] ?? 0)
    }

    func computeNewMessagesBaseline(
        for channelId: String,
        posts: [MMPost]
    ) -> (baseline: Int64, unreadCount: Int, dividerPostId: String?) {
        guard !channelId.isEmpty else { return (0, 0, nil) }
        let baseline = state.lastViewedAtByChannel[channelId] ?? 0
        if baseline > 0 {
            let unread = posts.filter { $0.create_at > baseline && ($0.root_id ?? "").isEmpty }
            return (baseline, unread.count, unread.first?.id)
        }
        return (0, 0, nil)
    }

    // MARK: - Mentions & Notification Routing

    func isCurrentUserMentioned(in post: MMPost) -> Bool {
        guard let username = state.currentUser?.username.lowercased(), !username.isEmpty else { return false }
        let message = post.message.lowercased()
        var candidates = ["@" + username, "@here", "@channel", "@all"]
        if let keys = state.currentUser?.notify_props?.mention_keys {
            candidates += keys
                .split(separator: ",")
                .map { $0.trimmingCharacters(in: .whitespacesAndNewlines).lowercased() }
                .filter { !$0.isEmpty }
        }
        for candidate in candidates {
            let escaped = NSRegularExpression.escapedPattern(for: candidate)
            let pattern = "(^|[^a-z0-9_.])" + escaped + "($|[^a-z0-9_])"
            if message.range(of: pattern, options: .regularExpression) != nil {
                return true
            }
        }
        return false
    }

    func isChannelMuted(
        _ channelId: String,
        mutedChannelIds: Set<String> = [],
        desktopNotificationOverrides: [String: String] = [:]
    ) -> Bool {
        if mutedChannelIds.contains(channelId) { return true }
        if let desktop = desktopNotificationOverrides[channelId] {
            return desktop.lowercased() == "none"
        }
        guard let props = state.membershipsByChannel[channelId]?.notify_props else { return false }
        return props.desktop?.lowercased() == "none"
            || props.mark_unread?.lowercased() == "mention"
    }

    func notificationExcerpt(from message: String) -> String {
        var text = message
            .replacingOccurrences(of: "\n", with: " ")
            .replacingOccurrences(of: ">", with: "")
            .trimmingCharacters(in: .whitespacesAndNewlines)
        if text.count > 160 {
            text = String(text.prefix(160)) + "…"
        }
        return text.isEmpty ? "New message" : text
    }

    func evaluateIncomingPost(
        _ post: MMPost,
        isVisible: Bool,
        mutedChannelIds: Set<String> = [],
        desktopNotificationOverrides: [String: String] = [:]
    ) -> IncomingPostDecision {
        let isSystemMessage = post.type?.hasPrefix("system_") ?? false
        let myUserId = state.currentUser?.id ?? webService?.currentUserId ?? ""
        let isMine = !myUserId.isEmpty && post.user_id == myUserId
        guard !isSystemMessage, !isMine else { return .ignoreSelfOrSystem }

        if isVisible {
            return .visibleInActiveChannel(channelId: post.channel_id)
        }

        guard !isChannelMuted(
            post.channel_id,
            mutedChannelIds: mutedChannelIds,
            desktopNotificationOverrides: desktopNotificationOverrides
        ) else {
            return .muted(channelId: post.channel_id)
        }

        let isMentioned = isCurrentUserMentioned(in: post)
        state.unreadByChannel[post.channel_id, default: 0] += 1
        if isMentioned {
            state.mentionsByChannel[post.channel_id, default: 0] += 1
        }

        let prefs = state.currentUser?.notify_props
        let desktop = prefs?.desktop?.lowercased() ?? "all"
        let desktopThreads = prefs?.desktop_threads?.lowercased() != "false"
        let soundEnabled = prefs?.desktop_sound?.lowercased() != "false"
        let isThreadReply = !(post.root_id ?? "").isEmpty
        let status = state.currentUserStatus.lowercased()

        let shouldNotify = status != "dnd"
            && status != "offline"
            && desktop != "none"
            && (desktop != "mention" || isMentioned)
            && (desktopThreads || !isThreadReply)

        let channel = state.channelsById[post.channel_id]
        let channelName = channel.map { channelDisplayName(for: $0) } ?? ""
        let author = state.usersById[post.user_id]?.username ?? "New message"

        let route = NotificationRoute(
            channelId: post.channel_id,
            channelName: channelName,
            author: author,
            body: notificationExcerpt(from: post.message),
            postId: post.id,
            rootId: post.root_id,
            shouldNotify: shouldNotify,
            sound: shouldNotify && soundEnabled
        )
        return .notify(route)
    }

    // MARK: - Posts & Pagination

    func fetchChannelPosts(channelId: String, pageSize: Int = 60) async throws -> ChannelPostsFetchResult {
        guard let ws = webService, ws.isLogged() else {
            return ChannelPostsFetchResult(
                posts: [],
                missingUserIds: [],
                unknownStatusIds: [],
                didReachEnd: true,
                newMessagesBaseline: 0,
                newMessagesCount: 0,
                newMessagesDividerPostId: nil
            )
        }

        let postList = try await ws.fetchChannelPosts(channelId: channelId)
        var posts = postList.chronologicalPosts

        if let jumpId = state.pendingJumpPostId,
           !posts.contains(where: { $0.id == jumpId }),
           let target = try? await ws.fetchPost(postId: jumpId),
           target.channel_id == channelId {
            posts.append(target)
            posts.sort { $0.create_at < $1.create_at }
        }

        let missingUserIds = Array(Set(posts.map { $0.user_id }).subtracting(state.usersById.keys))
        let allUserIds = Array(Set(posts.map { $0.user_id }.filter { $0 != "system" }))
        let unknownStatusIds = allUserIds.filter { state.userStatusById[$0] == nil && Self.isLikelyMattermostId($0) }

        let topLevelPosts = posts.filter { ($0.root_id ?? "").isEmpty }
        let didReachEnd = posts.count < pageSize
        state.didLoadAllHistory = didReachEnd
        state.currentChannelPosts = topLevelPosts

        let baselineResult = computeNewMessagesBaseline(for: channelId, posts: topLevelPosts)

        return ChannelPostsFetchResult(
            posts: topLevelPosts,
            missingUserIds: missingUserIds,
            unknownStatusIds: unknownStatusIds,
            didReachEnd: didReachEnd,
            newMessagesBaseline: baselineResult.baseline,
            newMessagesCount: baselineResult.unreadCount,
            newMessagesDividerPostId: baselineResult.dividerPostId
        )
    }

    func mergeOlderPosts(older: [MMPost], pageSize: Int = 60) -> OlderPostsMergeResult {
        let page = TimelinePager.merge(
            existing: state.currentChannelPosts,
            older: older,
            pageSize: pageSize
        )
        if page.didReachEnd {
            state.didLoadAllHistory = true
        }
        state.currentChannelPosts = page.posts
        let missing = Array(Set(page.inserted.map { $0.user_id }).subtracting(state.usersById.keys))
        return OlderPostsMergeResult(
            posts: page.posts,
            insertedCount: page.inserted.count,
            didReachEnd: page.didReachEnd,
            missingUserIds: missing
        )
    }

    func appendRealtimePost(_ post: MMPost, isScrolledUp: Bool) -> RealtimePostResult {
        guard post.channel_id == state.activeChannelId else {
            return .ignoredNotCurrentChannel
        }
        guard !state.currentChannelPosts.contains(where: { $0.id == post.id }) else {
            return .ignoredDuplicate
        }

        let isReply = !(post.root_id ?? "").isEmpty
        if isReply, let rootId = post.root_id, !rootId.isEmpty {
            let (_, newCount) = updateThreadReplyCount(rootId: rootId, replyCount: nil)
            return .threadReply(rootId: rootId, replyCount: newCount)
        }

        state.currentChannelPosts.append(post)
        state.currentChannelPosts.sort { $0.create_at < $1.create_at }

        let missingUser = state.usersById[post.user_id] == nil ? post.user_id : nil
        return .topLevel(post: post, isUnread: isScrolledUp, missingUserId: missingUser)
    }

    func handleRealtimePostDeleted(postId: String, channelId: String) -> PostDeletionResult {
        state.currentChannelPosts.removeAll { $0.id == postId }
        state.threadPosts.removeAll { $0.id == postId }
        var wasThreadRoot = false
        if postId == state.threadRootId && !state.threadRootId.isEmpty {
            state.threadRootId = ""
            wasThreadRoot = true
        }
        let isCurrentChannel = (state.activeChannelId == channelId)
        return PostDeletionResult(
            postId: postId,
            channelId: channelId,
            wasThreadRoot: wasThreadRoot,
            isCurrentChannel: isCurrentChannel
        )
    }

    func updateThreadReplyCount(rootId: String, replyCount: Int?) -> (previousCount: Int?, newCount: Int) {
        guard !rootId.isEmpty else { return (nil, 0) }
        var previous: Int?
        var resolvedCount = 0

        if let index = state.currentChannelPosts.firstIndex(where: { $0.id == rootId }) {
            previous = state.currentChannelPosts[index].reply_count
            let next = replyCount ?? ((previous ?? 0) + 1)
            state.currentChannelPosts[index].reply_count = next
            resolvedCount = next
        }

        if let index = state.threadPosts.firstIndex(where: { $0.id == rootId }) {
            if previous == nil { previous = state.threadPosts[index].reply_count }
            let next = replyCount ?? ((state.threadPosts[index].reply_count ?? 0) + 1)
            state.threadPosts[index].reply_count = next
            resolvedCount = next
        }

        if resolvedCount == 0, let count = replyCount {
            resolvedCount = count
        }
        return (previous, resolvedCount)
    }

    // MARK: - Workspace Setup & Channel Switching

    func prepareChannelSwitch(to itemId: String) -> (channel: MMChannel?, channelChanged: Bool, previousChannelId: String) {
        let normalized = itemId.lowercased()
        guard let ch = state.channelsById[itemId] ?? state.channelsByName[normalized] else {
            return (nil, false, state.activeChannelId)
        }
        let previousChannelId = state.activeChannelId
        let channelChanged = !previousChannelId.isEmpty && previousChannelId != ch.id
        state.activeChannelId = ch.id
        state.isLoadingOlderPosts = false
        state.didLoadAllHistory = false
        state.currentChannelPosts = []
        return (ch, channelChanged, previousChannelId)
    }

    func channelBelongsToTeam(_ channel: MMChannel, teamId: String) -> Bool {
        if channel.team_id == teamId { return true }
        if (channel.team_id ?? "").isEmpty && (channel.type == "D" || channel.type == "G") {
            return true
        }
        return false
    }

    func resolveDefaultChannel(
        teamId: String,
        channels: [MMChannel],
        savedChannelId: String?,
        systemBotArg: Bool
    ) -> MMChannel? {
        let savedChannel = savedChannelId.flatMap { state.channelsById[$0] }
        let botCh = state.channelsByName["system-bot"]
            ?? state.channelsByName["system bot"]
            ?? channels.first(where: { isChannelBot(for: $0) })

        return (systemBotArg ? botCh : nil)
            ?? savedChannel
            ?? state.channelsByName["town-square"]
            ?? state.channelsByName["town square"]
            ?? channels.first
    }

    func isChannelBot(for channel: MMChannel) -> Bool {
        guard channel.type == "D" else { return false }
        if let targetId = resolveDMTargetUserId(for: channel),
           let user = state.usersById[targetId],
           user.is_bot == true {
            return true
        }
        return channelDisplayName(for: channel).lowercased() == "system-bot"
    }

    func updateChannel(_ channel: MMChannel) {
        state.channelsById[channel.id] = channel
        state.channelsByName[channel.name.lowercased()] = channel
        state.channelsByName[channel.display_name.lowercased()] = channel
    }

    func updateTeam(_ team: MMTeam) {
        if let index = state.userTeams.firstIndex(where: { $0.id == team.id }) {
            state.userTeams[index] = team
        }
        if state.activeTeam?.id == team.id {
            state.activeTeam = team
        }
    }

    func updateUserTeams(_ teams: [MMTeam], savedTeamId: String?) -> (teams: [MMTeam], activeTeam: MMTeam?) {
        state.userTeams = teams
        let active = teams.first(where: { $0.id == savedTeamId })
            ?? (state.activeTeam.flatMap { active in teams.first(where: { $0.id == active.id }) })
            ?? teams.first
        state.activeTeam = active
        return (teams, active)
    }

    func loadInitialWorkspaceData(
        savedTeamId: String?,
        savedChannelId: String?,
        systemBotArg: Bool
    ) async throws -> InitialWorkspaceResult {
        guard let ws = webService, ws.isLogged() else {
            throw NSError(domain: "WorkspaceRepository", code: 401, userInfo: [NSLocalizedDescriptionKey: "Not logged in"])
        }

        let me = try await ws.fetchCurrentUser()
        state.currentUser = me
        state.usersById[me.id] = me
        state.usersByUsername[me.username.lowercased()] = me

        var myStatus: String?
        var dndEnd: Int64?
        if let statuses = try? await ws.fetchUserStatuses(userIds: [me.id]), let first = statuses.first {
            if let end = first.dnd_end_time, end > 0 {
                state.dndEndTimeByUser[me.id] = end
                dndEnd = end
            }
            state.userStatusById[me.id] = first.status
            state.currentUserStatus = first.status
            myStatus = first.status
        }

        let teams = try await ws.fetchTeams()
        let (_, activeTeamOpt) = updateUserTeams(teams, savedTeamId: savedTeamId)
        guard let activeTeam = activeTeamOpt else {
            throw NSError(domain: "WorkspaceRepository", code: 404, userInfo: [NSLocalizedDescriptionKey: "No teams found"])
        }

        let channels = try await ws.fetchChannels(teamId: activeTeam.id)
        var allChannels = channels
        if let myChannels = try? await ws.fetchAllChannels() {
            var chMap: [String: MMChannel] = [:]
            for c in channels { chMap[c.id] = c }
            for c in myChannels where channelBelongsToTeam(c, teamId: activeTeam.id) {
                chMap[c.id] = c
            }
            allChannels = Array(chMap.values)
        }

        for ch in allChannels {
            updateChannel(ch)
        }

        let initialChannel = resolveDefaultChannel(
            teamId: activeTeam.id,
            channels: allChannels,
            savedChannelId: savedChannelId,
            systemBotArg: systemBotArg
        )

        return InitialWorkspaceResult(
            me: me,
            myStatus: myStatus,
            dndEndTime: dndEnd,
            teams: teams,
            activeTeam: activeTeam,
            allChannels: allChannels,
            initialChannel: initialChannel
        )
    }
}
