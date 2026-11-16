//
//  WorkspaceRepositoryTests.swift
//  mattermost.clientTests
//

import XCTest

#if canImport(mattermost_client)
    @testable import mattermost_client
#endif

@MainActor
final class WorkspaceRepositoryTests: XCTestCase {

    private func makeRepository() -> (ChatViewModel, WorkspaceRepository) {
        let model = ChatViewModel()
        let repo = WorkspaceRepository(state: model)
        return (model, repo)
    }

    private func makeUser(
        id: String,
        username: String,
        roles: String = "system_user",
        isBot: Bool = false,
        notifyProps: MMUser.NotifyProps? = nil
    ) -> MMUser {
        MMUser(
            id: id,
            create_at: nil,
            update_at: nil,
            delete_at: nil,
            username: username,
            first_name: "Test",
            last_name: "User",
            nickname: nil,
            email: "\(username)@example.com",
            email_verified: nil,
            auth_service: nil,
            roles: roles,
            locale: nil,
            position: nil,
            is_bot: isBot,
            last_password_update: nil,
            remote_id: nil,
            disable_welcome_email: nil,
            notify_props: notifyProps,
            props: nil,
            timezone: nil,
            auth_data: nil
        )
    }

    private func makePost(
        id: String,
        createAt: Int64 = 1_000,
        userId: String = "u1",
        channelId: String = "c1",
        rootId: String? = nil,
        message: String = "Hello",
        type: String? = nil,
        replyCount: Int? = nil
    ) -> MMPost {
        MMPost(
            id: id,
            create_at: createAt,
            update_at: createAt,
            edit_at: nil,
            delete_at: nil,
            is_pinned: false,
            user_id: userId,
            channel_id: channelId,
            root_id: rootId,
            original_id: nil,
            message: message,
            type: type,
            file_ids: nil,
            metadata: nil,
            reply_count: replyCount,
            props: nil
        )
    }

    private func makeChannel(
        id: String,
        name: String,
        displayName: String,
        type: String = "O",
        teamId: String? = "t1"
    ) -> MMChannel {
        MMChannel(
            id: id,
            create_at: 0,
            update_at: 0,
            delete_at: 0,
            team_id: teamId,
            type: type,
            display_name: displayName,
            name: name,
            header: nil,
            purpose: nil,
            last_post_at: 0,
            total_msg_count: 0,
            creator_id: nil
        )
    }

    // MARK: - Read State Tests

    func testMarkChannelReadLocally() {
        let (model, repo) = makeRepository()
        model.unreadByChannel["c1"] = 5
        model.mentionsByChannel["c1"] = 2

        repo.markChannelReadLocally(channelId: "c1")

        XCTAssertEqual(model.unreadByChannel["c1"], 0)
        XCTAssertEqual(model.mentionsByChannel["c1"], 0)
    }

    func testHandleRemoteChannelViewed() {
        let (model, repo) = makeRepository()
        model.unreadByChannel["c1"] = 7
        model.mentionsByChannel["c1"] = 3

        repo.handleRemoteChannelViewed("c1")

        XCTAssertEqual(model.unreadByChannel["c1"], 0)
        XCTAssertEqual(model.mentionsByChannel["c1"], 0)
        XCTAssertGreaterThan(model.lastViewedAtByChannel["c1"] ?? 0, 0)
    }

    func testHandleRemoteChannelUnread() {
        let (model, repo) = makeRepository()
        model.activeChannelId = "c1"

        // Incoming unread on active channel is ignored
        repo.handleRemoteChannelUnread("c1")
        XCTAssertNil(model.unreadByChannel["c1"])

        // Incoming unread on other channel increments badge
        repo.handleRemoteChannelUnread("c2")
        XCTAssertEqual(model.unreadByChannel["c2"], 1)

        repo.handleRemoteChannelUnread("c2")
        XCTAssertEqual(model.unreadByChannel["c2"], 1)
    }

    func testComputeNewMessagesBaseline() {
        let (model, repo) = makeRepository()
        model.lastViewedAtByChannel["c1"] = 1_500

        let p1 = makePost(id: "p1", createAt: 1_000)
        let p2 = makePost(id: "p2", createAt: 2_000)
        let p3 = makePost(id: "p3", createAt: 3_000)
        let threadReply = makePost(id: "p4", createAt: 4_000, rootId: "p1")

        let result = repo.computeNewMessagesBaseline(for: "c1", posts: [p1, p2, p3, threadReply])
        XCTAssertEqual(result.baseline, 1_500)
        XCTAssertEqual(result.unreadCount, 2) // p2 and p3 (p4 is thread reply)
        XCTAssertEqual(result.dividerPostId, "p2")
    }

    // MARK: - Mentions & Notification Routing Tests

    func testIsCurrentUserMentioned() {
        let (model, repo) = makeRepository()
        let notifyProps = MMUser.NotifyProps(
            channel: nil,
            comments: "never",
            desktop: "all",
            desktop_sound: "true",
            desktop_threads: "all",
            email: "true",
            email_threads: "all",
            first_name: nil,
            mention_keys: "customkey, alert",
            push: "mention",
            push_status: "away",
            push_threads: "all"
        )
        model.currentUser = makeUser(id: "me", username: "alice", notifyProps: notifyProps)

        // Word-bounded @username
        XCTAssertTrue(repo.isCurrentUserMentioned(in: makePost(id: "1", message: "Hi @alice!")))
        XCTAssertTrue(repo.isCurrentUserMentioned(in: makePost(id: "2", message: "@alice what's up")))
        XCTAssertFalse(repo.isCurrentUserMentioned(in: makePost(id: "3", message: "alice@example.com")))
        XCTAssertFalse(repo.isCurrentUserMentioned(in: makePost(id: "4", message: "notalice is here")))

        // Special mentions
        XCTAssertTrue(repo.isCurrentUserMentioned(in: makePost(id: "5", message: "Hey @channel!")))
        XCTAssertTrue(repo.isCurrentUserMentioned(in: makePost(id: "6", message: "Look @here")))
        XCTAssertTrue(repo.isCurrentUserMentioned(in: makePost(id: "7", message: "Attention @all")))

        // Custom keys
        XCTAssertTrue(repo.isCurrentUserMentioned(in: makePost(id: "8", message: "Trigger customkey now")))
        XCTAssertTrue(repo.isCurrentUserMentioned(in: makePost(id: "9", message: "urgent alert!")))
        XCTAssertFalse(repo.isCurrentUserMentioned(in: makePost(id: "10", message: "regular text")))
    }

    func testIsChannelMuted() {
        let (model, repo) = makeRepository()

        // Explicit set
        XCTAssertTrue(repo.isChannelMuted("c_muted", mutedChannelIds: ["c_muted"]))

        // Desktop override
        XCTAssertTrue(repo.isChannelMuted("c_override", desktopNotificationOverrides: ["c_override": "none"]))
        XCTAssertFalse(repo.isChannelMuted("c_override", desktopNotificationOverrides: ["c_override": "all"]))

        // Channel membership props
        let membership = MMChannelMembership(
            channel_id: "c_membership",
            msg_count: 0,
            mention_count: 0,
            last_viewed_at: 0,
            last_update_at: 0,
            notify_props: MMChannelMembership.NotifyProps(desktop: "none", mark_unread: "all", ignore_channel_mentions: nil)
        )
        model.membershipsByChannel["c_membership"] = membership
        XCTAssertTrue(repo.isChannelMuted("c_membership"))

        let mentionOnlyMembership = MMChannelMembership(
            channel_id: "c_mention_only",
            msg_count: 0,
            mention_count: 0,
            last_viewed_at: 0,
            last_update_at: 0,
            notify_props: MMChannelMembership.NotifyProps(desktop: "all", mark_unread: "mention", ignore_channel_mentions: nil)
        )
        model.membershipsByChannel["c_mention_only"] = mentionOnlyMembership
        XCTAssertTrue(repo.isChannelMuted("c_mention_only"))
    }

    func testNotificationExcerpt() {
        let (_, repo) = makeRepository()

        XCTAssertEqual(repo.notificationExcerpt(from: "Hello World"), "Hello World")
        XCTAssertEqual(repo.notificationExcerpt(from: "> quote\nLine two"), "quote Line two")

        let longText = String(repeating: "A", count: 200)
        let excerpt = repo.notificationExcerpt(from: longText)
        XCTAssertEqual(excerpt.count, 161) // 160 + "…"
        XCTAssertTrue(excerpt.hasSuffix("…"))

        XCTAssertEqual(repo.notificationExcerpt(from: "   \n\n  "), "New message")
    }

    func testEvaluateIncomingPostIgnoresSelfAndSystem() {
        let (model, repo) = makeRepository()
        model.currentUser = makeUser(id: "my_id", username: "me")

        // Own post
        let ownPost = makePost(id: "p1", userId: "my_id")
        XCTAssertEqual(repo.evaluateIncomingPost(ownPost, isVisible: false), .ignoreSelfOrSystem)

        // System message
        let sysPost = makePost(id: "p2", userId: "other", type: "system_add_to_channel")
        XCTAssertEqual(repo.evaluateIncomingPost(sysPost, isVisible: false), .ignoreSelfOrSystem)
    }

    func testEvaluateIncomingPostVisibleInActiveChannel() {
        let (model, repo) = makeRepository()
        model.currentUser = makeUser(id: "my_id", username: "me")
        model.activeChannelId = "c1"

        let post = makePost(id: "p1", userId: "other", channelId: "c1")
        XCTAssertEqual(repo.evaluateIncomingPost(post, isVisible: true), .visibleInActiveChannel(channelId: "c1"))
    }

    func testEvaluateIncomingPostMutedChannel() {
        let (model, repo) = makeRepository()
        model.currentUser = makeUser(id: "my_id", username: "me")

        let post = makePost(id: "p1", userId: "other", channelId: "c_muted")
        let decision = repo.evaluateIncomingPost(post, isVisible: false, mutedChannelIds: ["c_muted"])

        XCTAssertEqual(decision, .muted(channelId: "c_muted"))
        // Muted channels do not accrue unread badges
        XCTAssertNil(model.unreadByChannel["c_muted"])
    }

    func testEvaluateIncomingPostNotifiesAndBadges() {
        let (model, repo) = makeRepository()
        model.currentUser = makeUser(
            id: "my_id",
            username: "me",
            notifyProps: MMUser.NotifyProps(
                channel: nil,
                comments: "never",
                desktop: "all",
                desktop_sound: "true",
                desktop_threads: "all",
                email: "true",
                email_threads: "all",
                first_name: nil,
                mention_keys: nil,
                push: "all",
                push_status: "online",
                push_threads: "all"
            )
        )
        model.currentUserStatus = "online"

        let channel = makeChannel(id: "c1", name: "general", displayName: "General")
        repo.updateChannel(channel)
        let author = makeUser(id: "author1", username: "bob")
        model.usersById["author1"] = author

        let post = makePost(id: "p1", userId: "author1", channelId: "c1", message: "Hello @me!")
        let decision = repo.evaluateIncomingPost(post, isVisible: false)

        XCTAssertEqual(model.unreadByChannel["c1"], 1)
        XCTAssertEqual(model.mentionsByChannel["c1"], 1)

        guard case .notify(let route) = decision else {
            XCTFail("Expected .notify, got \(decision)")
            return
        }

        XCTAssertEqual(route.channelId, "c1")
        XCTAssertEqual(route.channelName, "General")
        XCTAssertEqual(route.author, "bob")
        XCTAssertEqual(route.body, "Hello @me!")
        XCTAssertTrue(route.shouldNotify)
        XCTAssertTrue(route.sound)
    }

    func testEvaluateIncomingPostSuppressesNotificationOnDND() {
        let (model, repo) = makeRepository()
        model.currentUser = makeUser(id: "my_id", username: "me")
        model.currentUserStatus = "dnd"

        let post = makePost(id: "p1", userId: "author1", channelId: "c1", message: "urgent message")
        let decision = repo.evaluateIncomingPost(post, isVisible: false)

        guard case .notify(let route) = decision else {
            XCTFail("Expected .notify, got \(decision)")
            return
        }

        // Accrues badge, but shouldNotify is false
        XCTAssertEqual(model.unreadByChannel["c1"], 1)
        XCTAssertFalse(route.shouldNotify)
    }

    // MARK: - Timeline Pagination & Merging Tests

    func testMergeOlderPosts() {
        let (model, repo) = makeRepository()
        model.usersById["u1"] = makeUser(id: "u1", username: "user1")

        let existing = [
            makePost(id: "p2", createAt: 200, userId: "u1"),
            makePost(id: "p3", createAt: 300, userId: "u1")
        ]
        model.currentChannelPosts = existing

        let older = [
            makePost(id: "p1", createAt: 100, userId: "u_missing"),
            makePost(id: "p2", createAt: 200, userId: "u1") // duplicate / refresh
        ]

        let result = repo.mergeOlderPosts(older: older, pageSize: 60)

        XCTAssertEqual(result.posts.map(\.id), ["p1", "p2", "p3"])
        XCTAssertEqual(result.insertedCount, 1) // p1 inserted
        XCTAssertTrue(result.didReachEnd) // older.count (2) < pageSize (60)
        XCTAssertEqual(result.missingUserIds, ["u_missing"])
        XCTAssertEqual(model.currentChannelPosts.map(\.id), ["p1", "p2", "p3"])
        XCTAssertTrue(model.didLoadAllHistory)
    }

    // MARK: - Realtime Post Appending & Deletion Tests

    func testAppendRealtimePost() {
        let (model, repo) = makeRepository()
        model.activeChannelId = "c1"
        model.usersById["u1"] = makeUser(id: "u1", username: "user1")

        // 1. Post for different channel is ignored
        let diffPost = makePost(id: "diff", channelId: "other")
        XCTAssertEqual(repo.appendRealtimePost(diffPost, isScrolledUp: false), .ignoredNotCurrentChannel)

        // 2. Normal top-level post added
        let p1 = makePost(id: "p1", createAt: 100, userId: "u1", channelId: "c1")
        let result = repo.appendRealtimePost(p1, isScrolledUp: true)

        guard case .topLevel(let post, let isUnread, let missingUserId) = result else {
            XCTFail("Expected .topLevel, got \(result)")
            return
        }
        XCTAssertEqual(post.id, "p1")
        XCTAssertTrue(isUnread)
        XCTAssertNil(missingUserId)
        XCTAssertEqual(model.currentChannelPosts.count, 1)

        // 3. Duplicate post is ignored
        XCTAssertEqual(repo.appendRealtimePost(p1, isScrolledUp: false), .ignoredDuplicate)

        // 4. Thread reply updates parent post reply count
        let reply = makePost(id: "r1", createAt: 150, userId: "u1", channelId: "c1", rootId: "p1")
        let replyResult = repo.appendRealtimePost(reply, isScrolledUp: false)

        guard case .threadReply(let rootId, let replyCount) = replyResult else {
            XCTFail("Expected .threadReply, got \(replyResult)")
            return
        }
        XCTAssertEqual(rootId, "p1")
        XCTAssertEqual(replyCount, 1)
        XCTAssertEqual(model.currentChannelPosts.first?.reply_count, 1)
        // Reply is not added to channel posts feed
        XCTAssertEqual(model.currentChannelPosts.count, 1)
    }

    func testHandleRealtimePostDeleted() {
        let (model, repo) = makeRepository()
        model.activeChannelId = "c1"
        model.threadRootId = "root1"

        let p1 = makePost(id: "p1", channelId: "c1")
        let root = makePost(id: "root1", channelId: "c1")
        let reply = makePost(id: "r1", channelId: "c1", rootId: "root1")

        model.currentChannelPosts = [root, p1]
        model.threadPosts = [root, reply]

        // Delete reply
        let delReply = repo.handleRealtimePostDeleted(postId: "r1", channelId: "c1")
        XCTAssertEqual(delReply.postId, "r1")
        XCTAssertFalse(delReply.wasThreadRoot)
        XCTAssertTrue(delReply.isCurrentChannel)
        XCTAssertEqual(model.threadPosts.map(\.id), ["root1"])

        // Delete thread root
        let delRoot = repo.handleRealtimePostDeleted(postId: "root1", channelId: "c1")
        XCTAssertTrue(delRoot.wasThreadRoot)
        XCTAssertEqual(model.threadRootId, "")
        XCTAssertEqual(model.currentChannelPosts.map(\.id), ["p1"])
    }

    // MARK: - Workspace Setup & Navigation Tests

    func testPrepareChannelSwitch() {
        let (model, repo) = makeRepository()
        let c1 = makeChannel(id: "c1", name: "general", displayName: "General")
        let c2 = makeChannel(id: "c2", name: "random", displayName: "Random")
        repo.updateChannel(c1)
        repo.updateChannel(c2)

        model.activeChannelId = "c1"
        model.currentChannelPosts = [makePost(id: "p1")]
        model.isLoadingOlderPosts = true
        model.didLoadAllHistory = true

        let (ch, changed, prev) = repo.prepareChannelSwitch(to: "random")

        XCTAssertEqual(ch?.id, "c2")
        XCTAssertTrue(changed)
        XCTAssertEqual(prev, "c1")
        XCTAssertEqual(model.activeChannelId, "c2")
        XCTAssertTrue(model.currentChannelPosts.isEmpty)
        XCTAssertFalse(model.isLoadingOlderPosts)
        XCTAssertFalse(model.didLoadAllHistory)
    }

    func testChannelBelongsToTeam() {
        let (_, repo) = makeRepository()

        let publicCh = makeChannel(id: "c1", name: "pub", displayName: "Pub", teamId: "t1")
        XCTAssertTrue(repo.channelBelongsToTeam(publicCh, teamId: "t1"))
        XCTAssertFalse(repo.channelBelongsToTeam(publicCh, teamId: "t2"))

        // DM / GM channels belong to any team
        let dmCh = makeChannel(id: "dm1", name: "dm", displayName: "DM", type: "D", teamId: "")
        XCTAssertTrue(repo.channelBelongsToTeam(dmCh, teamId: "t1"))
        XCTAssertTrue(repo.channelBelongsToTeam(dmCh, teamId: "t2"))
    }

    func testResolveDefaultChannel() {
        let (_, repo) = makeRepository()
        let c1 = makeChannel(id: "c1", name: "other", displayName: "Other")
        let cTown = makeChannel(id: "c2", name: "town-square", displayName: "Town Square")
        let cBot = makeChannel(id: "c3", name: "system-bot", displayName: "System Bot", type: "D")
        repo.updateChannel(c1)
        repo.updateChannel(cTown)
        repo.updateChannel(cBot)

        let channels = [c1, cTown, cBot]

        // 1. System bot arg takes precedence if requested
        let botResult = repo.resolveDefaultChannel(teamId: "t1", channels: channels, savedChannelId: "c1", systemBotArg: true)
        XCTAssertEqual(botResult?.id, "c3")

        // 2. Saved channel ID takes precedence otherwise
        let savedResult = repo.resolveDefaultChannel(teamId: "t1", channels: channels, savedChannelId: "c1", systemBotArg: false)
        XCTAssertEqual(savedResult?.id, "c1")

        // 3. Fallback to town-square
        let townResult = repo.resolveDefaultChannel(teamId: "t1", channels: channels, savedChannelId: nil, systemBotArg: false)
        XCTAssertEqual(townResult?.id, "c2")
    }

    func testChannelDisplayName() {
        let (model, repo) = makeRepository()
        let me = makeUser(id: "me", username: "alice")
        model.currentUser = me
        model.usersById["me"] = me
        let bob = makeUser(id: "bob_id", username: "bob")
        model.usersById["bob_id"] = bob

        // DM channel with bob
        let dmChannel = makeChannel(
            id: "dm_c",
            name: "me__bob_id",
            displayName: "",
            type: "D"
        )
        XCTAssertEqual(repo.channelDisplayName(for: dmChannel), "bob")

        // Self DM channel
        let selfDM = makeChannel(
            id: "self_c",
            name: "me__me",
            displayName: "",
            type: "D"
        )
        XCTAssertEqual(repo.channelDisplayName(for: selfDM), "alice (you)")

        // Public channel
        let pubChannel = makeChannel(id: "pub", name: "engineering", displayName: "Engineering")
        XCTAssertEqual(repo.channelDisplayName(for: pubChannel), "Engineering")
    }
}
