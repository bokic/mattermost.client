//
//  MainWindow+LiveData.swift
//  mattermost.client
//
//  Split from MainWindow.swift.
//

import AppKit
import Foundation
import UniformTypeIdentifiers

extension MainWindow {

    func updateNewMessagesBaseline() {
        guard !activeChannelId.isEmpty else { return }
        newMessagesBaseline = lastViewedAtByChannel[activeChannelId] ?? 0
        if newMessagesBaseline > 0 {
            let unread = currentChannelPosts.filter { $0.create_at > newMessagesBaseline }
            newMessagesCount = unread.count
            newMessagesDividerPostId = unread.first?.id
            rebuildTimelineContent(scrollToBottom: false)
        }
    }

    func markActiveChannelViewed() {
        guard !activeChannelId.isEmpty,
              let ws = webService, ws.isLogged() else { return }
        let channelId = activeChannelId
        Task { @MainActor [weak self] in
            guard let self = self else { return }
            do {
                let viewedAt = try await ws.markChannelViewed(channelId: channelId)
                self.lastViewedAtByChannel[channelId] = viewedAt
                // Only clear local badges after the server accepted the view;
                // otherwise a transient failure would hide real unread state.
                self.unreadByChannel[channelId] = 0
                self.mentionsByChannel[channelId] = 0
                self.updateSidebarBadges()
                (NSApp.delegate as? AppDelegate)?.markChannelRead(channelId)
            } catch {
                DebugLog.error("markActiveChannelViewed failed for \(channelId): \(error)")
            }
        }
    }

    func markAllChannelsRead() {
        guard let ws = webService, ws.isLogged(), let team = activeTeam else { return }
        let userId = currentUser?.id ?? ws.currentUserId
        guard !userId.isEmpty else { return }
        let teamChannelIds = Set(channelsById.values.filter {
            channelBelongsToTeam($0, teamId: team.id)
        }.map { $0.id })
        Task { @MainActor [weak self] in
            guard let self = self else { return }
            do {
                try await ws.markAllChannelsRead(userId: userId, teamId: team.id)
                for channelId in teamChannelIds {
                    self.unreadByChannel[channelId] = 0
                    self.mentionsByChannel[channelId] = 0
                    self.lastViewedAtByChannel[channelId] = Int64(Date().timeIntervalSince1970 * 1000)
                }
                self.updateSidebarBadges()
                self.updateNewMessagesBaseline()
                if let appDelegate = NSApp.delegate as? AppDelegate {
                    for channelId in teamChannelIds {
                        appDelegate.markChannelRead(channelId)
                    }
                }
                self.composerHelpLabel.stringValue = "All channels marked as read"
                DispatchQueue.main.asyncAfter(deadline: .now() + 3) { [weak self] in
                    guard let self = self, self.composerHelpLabel.stringValue == "All channels marked as read" else { return }
                    self.composerHelpLabel.stringValue = self.defaultComposerStatusText()
                }
            } catch {
                self.showInfoAlert("Could not mark all channels as read: \(error.localizedDescription)")
            }
        }
    }

    func markActiveChannelRead() {
        guard !activeChannelId.isEmpty else { return }
        let channelId = activeChannelId
        unreadByChannel[channelId] = 0
        mentionsByChannel[channelId] = 0
        updateSidebarBadges()
        markActiveChannelViewed()
        (NSApp.delegate as? AppDelegate)?.markChannelRead(channelId)
    }

    func markActiveChannelUnread() {
        guard let ws = webService, ws.isLogged(),
              !activeChannelId.isEmpty,
              let lastPost = currentChannelPosts.last(where: { ($0.root_id ?? "").isEmpty }) else { return }
        let userId = currentUser?.id ?? ws.currentUserId
        guard !userId.isEmpty else { return }
        let channelId = activeChannelId
        Task { @MainActor [weak self] in
            guard let self = self else { return }
            do {
                try await ws.markChannelUnread(userId: userId, channelId: channelId, postId: lastPost.id)
                self.unreadByChannel[channelId, default: 0] = max(1, self.unreadByChannel[channelId] ?? 0)
                self.updateSidebarBadges()
            } catch {
                self.showInfoAlert("Could not mark the channel unread: \(error.localizedDescription)")
            }
        }
    }

    /// Called once by `AppDelegate` after the window is created, so the service is
    /// injected explicitly instead of being looked up throughout the view code.
    func start(with webService: WebService) {
        self.webService = webService
        bindWebServiceAndLoadData()
    }

    func bindWebServiceAndLoadData() {
        guard let ws = webService else { return }
        loadAttachmentSizeLimit()

        ws.onPostReceived = { [weak self] post, _ in
            guard let self = self else { return }
            Task { @MainActor [weak self] in
                guard let self = self else { return }
                if post.channel_id == self.activeChannelId {
                    self.appendRealtimePost(post)
                }
                self.handleIncomingPost(post)
            }
        }

        ws.onReactionChanged = { [weak self] postId in
            Task { @MainActor [weak self] in
                guard let self = self,
                      let ws = self.webService else { return }
                if let updated = try? await ws.fetchPost(postId: postId) {
                    self.applyUpdatedPost(updated)
                }
            }
        }

        ws.onWebSocketStateChanged = { [weak self] connected, message in
            Task { @MainActor [weak self] in
                guard let self = self else { return }
                self.updateConnectionState(connected: connected, message: message)
                if connected, self.settingsAwaitingReconnect {
                    self.settingsAwaitingReconnect = false
                    if self.isRightPanelVisible, self.rightPanelMode == .settings {
                        self.loadSettingsPanel()
                    }
                }
            }
        }
        updateConnectionState(
            connected: ws.isWebSocketConnected,
            message: ws.isWebSocketConnected ? "Connected" : "Connecting to Mattermost…"
        )

        ws.onWebSocketEvent = { [weak self] event in
            DebugLog.logSensitive("ws.onWebSocketEvent: \(event)")
            Task { @MainActor [weak self] in
                guard let self = self else { return }
                switch event {
                case .postEdited(let post):
                    self.applyUpdatedPost(post)
                case .postDeleted(let postId, let channelId):
                    self.handleRealtimePostDeleted(postId: postId, channelId: channelId)
                case .postUnread(let channelId):
                    self.handleRemoteChannelUnread(channelId)
                case .channelViewed(let channelId):
                    self.handleRemoteChannelViewed(channelId)
                case .channelMembershipChanged(let channelId, let userId):
                    let myId = self.currentUser?.id ?? self.webService?.currentUserId ?? ""
                    if userId == myId {
                        self.loadUnreadState()
                        if let team = self.activeTeam, let ws = self.webService,
                           let categories = try? await ws.fetchSidebarCategories(teamId: team.id) {
                            self.populateSidebarCategories(
                                from: categories,
                                channels: Array(self.channelsById.values)
                            )
                        }
                    } else if self.isRightPanelVisible && self.rightPanelMode == .members
                        && (channelId.isEmpty || channelId == self.activeChannelId) {
                        self.loadChannelMembers()
                    }
                case .channelUpdated(let channel):
                    self.channelsById[channel.id] = channel
                    self.channelsByName[channel.name.lowercased()] = channel
                    self.channelsByName[channel.display_name.lowercased()] = channel
                    if channel.id == self.activeChannelId {
                        self.channelTitleLabel.stringValue = self.channelDisplayName(for: channel)
                        self.heroTitleLabel.stringValue = self.channelDisplayName(for: channel)
                        self.rebuildTimelineContent(scrollToBottom: false)
                    }
                case .preferencesChanged(let userId):
                    let myId = self.currentUser?.id ?? self.webService?.currentUserId ?? ""
                    if !myId.isEmpty && userId == myId {
                        self.loadFavoriteChannels()
                        self.refreshServerTheme(teamId: self.activeTeam?.id)
                        if self.isRightPanelVisible && self.rightPanelMode == .settings {
                            self.loadSettingsPanel()
                        }
                    }
                case .threadUpdated(let rootId, let replyCount):
                    self.updateThreadReplyCount(rootId: rootId, replyCount: replyCount)
                    if self.isRightPanelVisible && self.rightPanelMode == .thread && self.threadRootId == rootId {
                        self.loadThread()
                    } else if self.isRightPanelVisible && self.rightPanelMode == .threads {
                        self.loadThreads()
                    }
                case .emojiAdded:
                    self.loadCustomEmojis()
                case .other(let eventName, _):
                    if eventName == "custom_status_set" || eventName == "custom_status_removed" || eventName == "user_updated" {
                        self.refreshCustomStatus()
                    }
                default:
                    break
                }
            }
        }

        ws.onWebSocketConnected = { [weak self] in
            DebugLog.log("ws.onWebSocketConnected callback triggered")
            guard let self = self else { return }
            self.refreshCustomStatus()
            self.refreshUserStatuses()
            self.loadUnreadState()
            let channelId = self.activeChannelId
            if !channelId.isEmpty {
                Task { @MainActor [weak self] in
                    await self?.fetchAndRenderPosts(channelId: channelId)
                }
            }
        }

        ws.onMultipleStatusesReceived = { [weak self] statuses in
            DebugLog.log("ws.onMultipleStatusesReceived: \(statuses)")
            guard let self = self else { return }
            for (userId, status) in statuses {
                let normalized = self.normalizedStatusForKnownUser(status, userId: userId)
                self.userStatusById[userId] = normalized
                self.updateChatWidgetUserStatus(userId: userId, status: normalized)
                if userId == self.currentUser?.id, normalized != status {
                    self.applyCurrentUserStatus(normalized)
                }
            }
        }

        ws.onStatusChanged = { [weak self] userId, status in
            DebugLog.log("ws.onStatusChanged: userId=\(userId), status=\(status)")
            guard let self = self else { return }
            let normalized = self.normalizedStatusForKnownUser(status, userId: userId)
            self.userStatusById[userId] = normalized
            self.updateChatWidgetUserStatus(userId: userId, status: normalized)
            if let myId = self.currentUser?.id ?? webService?.currentUserId, myId == userId {
                self.applyCurrentUserStatus(normalized)
            }
        }

        ws.onUserTyping = { [weak self] userId, channelId, parentId in
            guard let self = self else { return }
            if let myId = self.currentUser?.id, myId == userId { return }
            let typer = self.usersById[userId]?.username ?? "Someone"

            if let parentId = parentId, !parentId.isEmpty {
                // Thread typing belongs to its thread composer, not the main one.
                guard self.rightPanelMode == .thread, self.threadRootId == parentId else { return }
                self.threadTypingIndicatorWorkItem?.cancel()
                let typingPlaceholder = "\(typer) is typing…"
                self.threadReplyTextView.placeholderString = typingPlaceholder
                let work = DispatchWorkItem { [weak self] in
                    guard let self = self,
                          self.threadReplyTextView.placeholderString == typingPlaceholder else { return }
                    self.threadReplyTextView.placeholderString = "Reply to thread…"
                }
                self.threadTypingIndicatorWorkItem = work
                DispatchQueue.main.asyncAfter(deadline: .now() + 3.0, execute: work)
                return
            }

            guard channelId == self.activeChannelId else { return }

            // Don't replace a real status (editing/upload/send) with a typing hint.
            let currentStatus = self.composerHelpLabel.stringValue
            guard self.editingPostId == nil,
                  !currentStatus.hasPrefix("Uploading"),
                  !currentStatus.hasPrefix("Sending"),
                  !currentStatus.hasPrefix("Saving"),
                  currentStatus != "Drop files to attach" else { return }

            self.typingIndicatorWorkItem?.cancel()
            let typingStatus = "\(typer) is typing..."
            self.composerHelpLabel.stringValue = typingStatus
            let work = DispatchWorkItem { [weak self] in
                guard let self = self, self.composerHelpLabel.stringValue == typingStatus else { return }
                self.composerHelpLabel.stringValue = self.defaultComposerStatusText()
            }
            self.typingIndicatorWorkItem = work
            DispatchQueue.main.asyncAfter(deadline: .now() + 3.0, execute: work)
        }

        ws.onTeamUpdated = { [weak self] updatedTeam in
            guard let self = self else { return }
            if let index = self.userTeams.firstIndex(where: { $0.id == updatedTeam.id }) {
                self.userTeams[index] = updatedTeam
            }
            if self.activeTeam?.id == updatedTeam.id {
                self.updateTeamHeader(with: updatedTeam)
            }
            self.rebuildTeamMenu()
        }

        ws.onUserTeamsChanged = { [weak self] in
            guard let self = self else { return }
            Task { @MainActor [weak self] in
                guard let self = self else { return }
                do {
                    let teams = try await ws.fetchTeams()
                    self.userTeams = teams
                    if let active = self.activeTeam, let refreshed = teams.first(where: { $0.id == active.id }) {
                        self.updateTeamHeader(with: refreshed)
                    } else if let firstTeam = teams.first {
                        self.switchActiveTeam(to: firstTeam)
                    }
                    self.rebuildTeamMenu()
                } catch {
                    NSLog("Failed to refresh teams on websocket event: \(error.localizedDescription)")
                }
            }
        }

        ws.onSidebarCategoriesUpdated = { [weak self] in
            guard let self = self, let team = self.activeTeam else { return }
            Task { @MainActor [weak self] in
                guard let self = self else { return }
                if let cats = try? await ws.fetchSidebarCategories(teamId: team.id) {
                    let chs = Array(self.channelsById.values)
                    await self.preloadDMUsers(for: chs)
                    self.populateSidebarCategories(from: cats, channels: chs)
                }
            }
        }

        statusPollingTimer?.invalidate()
        statusPollingTimer = Timer.scheduledTimer(withTimeInterval: 15.0, repeats: true) { [weak self] _ in
            MainActor.assumeIsolated {
                self?.clearExpiredCustomStatusIfNeeded()
                self?.refreshCustomStatus()
                self?.refreshUserStatuses()
            }
        }

        guard ws.isLogged() else { return }

        Task { @MainActor [weak self] in
            guard let self = self else { return }
            do {
                let me = try await ws.fetchCurrentUser()
                self.currentUser = me
                self.applyServerCustomStatus(from: me)
                self.usersById[me.id] = me
                self.usersByUsername[me.username.lowercased()] = me
                self.fetchAvatarIfNeeded(for: me.id)
                self.loadFavoriteChannels()

                if let statuses = try? await ws.fetchUserStatuses(userIds: [me.id]), let myStatus = statuses.first {
                    if let end = myStatus.dnd_end_time, end > 0 {
                        self.dndEndTimeByUser[me.id] = end
                    }
                    let status = self.normalizedStatus(myStatus.status, dndEndTime: myStatus.dnd_end_time)
                    self.userStatusById[me.id] = status
                    self.applyCurrentUserStatus(status)
                    self.updateChatWidgetUserStatus(userId: me.id, status: status)
                }

                let teams = try await ws.fetchTeams()
                self.userTeams = teams
                let savedTeamId = UserDefaults.standard.string(forKey: "lastTeamId")
                guard let team = teams.first(where: { $0.id == savedTeamId }) ?? teams.first else { return }
                self.updateTeamHeader(with: team)
                UserDefaults.standard.set(team.id, forKey: "lastTeamId")

                let channels = try await ws.fetchChannels(teamId: team.id)
                var allChannels = channels
                if let myChannels = try? await ws.fetchAllChannels() {
                    var chMap: [String: MMChannel] = [:]
                    for c in channels { chMap[c.id] = c }
                    for c in myChannels where self.channelBelongsToTeam(c, teamId: team.id) {
                        chMap[c.id] = c
                    }
                    allChannels = Array(chMap.values)
                }
                for ch in allChannels {
                    self.channelsById[ch.id] = ch
                    self.channelsByName[ch.name.lowercased()] = ch
                    self.channelsByName[ch.display_name.lowercased()] = ch
                }

                await self.preloadDMUsers(for: allChannels)

                if let categoriesResponse = try? await ws.fetchSidebarCategories(teamId: team.id) {
                    self.populateSidebarCategories(from: categoriesResponse, channels: allChannels)
                }

                let savedChannelId = UserDefaults.standard.string(forKey: "lastChannelId")
                let savedChannel = savedChannelId.flatMap { self.channelsById[$0] }
                let botCh = self.channelsByName["system-bot"]
                    ?? self.channelsByName["system bot"]
                    ?? allChannels.first(where: { self.isChannelBot(for: $0) })
                let defaultCh = (CommandLine.arguments.contains("--system-bot") ? botCh : nil)
                    ?? savedChannel
                    ?? self.channelsByName["town-square"]
                    ?? self.channelsByName["town square"]
                    ?? channels.first
                if let initialCh = defaultCh {
                    self.selectedSidebarItemId = initialCh.id
                    self.updateSidebarSelectionAppearance()
                    self.loadChannelPosts(forSidebarItemId: initialCh.id)
                }
            } catch {
                NSLog("Failed to load initial Mattermost workspace data: \(error.localizedDescription)")
            }
        }

        loadCustomEmojis()

    }

    func loadChannelPosts(forSidebarItemId itemId: String) {
        let normalized = itemId.lowercased()
        guard let ch = channelsById[itemId] ?? channelsByName[normalized] else { return }
        let previousChannelId = activeChannelId
        let channelChanged = !previousChannelId.isEmpty && previousChannelId != ch.id
        if channelChanged {
            saveComposerDraft(for: previousChannelId)
            saveChannelScrollPosition(for: previousChannelId)
            if rightPanelMode == .thread { saveThreadDraft() }
        }
        activeChannelId = ch.id
        UserDefaults.standard.set(ch.id, forKey: "lastChannelId")
        if let teamId = activeTeam?.id { UserDefaults.standard.set(teamId, forKey: "lastTeamId") }
        closeCompletion()
        newMessagesDividerPostId = nil
        newMessagesDividerView = nil
        newMessagesCount = 0
        newMessagesDividerArmed = false
        newMessagesPill.isHidden = true
        newMessagesBaseline = lastViewedAtByChannel[ch.id] ?? 0
        refreshFavoriteState()
        markActiveChannelViewed()
        reloadRightPanelIfNeeded()
        let resolvedTitle = channelDisplayName(for: ch)
        channelTitleLabel.stringValue = resolvedTitle
        if isRightPanelVisible {
            rightPanelSubtitle.stringValue = resolvedTitle
        }
        heroTitleLabel.stringValue = resolvedTitle
        composerPlaceholderLabel.stringValue = L10n.format("Write to %@", resolvedTitle)
        entryView.placeholderString = composerPlaceholderLabel.stringValue
        if ch.type == "D" {
            heroDescriptionLabel.stringValue = "This is the start of your direct message history with \(resolvedTitle). Messages and files shared here are not shown to people outside this conversation."
        } else if ch.type == "G" {
            heroDescriptionLabel.stringValue = "This is the start of your group message history with \(resolvedTitle). Messages and files shared here are not shown to people outside this conversation."
        } else {
            heroDescriptionLabel.stringValue = "Welcome to \(resolvedTitle). Post messages here that you want everyone to see. Everyone\nautomatically becomes a member of this channel when they join the team."
        }
        if channelChanged {
            restoreComposerDraft(for: ch.id)
        } else {
            updateComposerSendState()
        }
        layoutRightChatPanel()
        closeSearchResults()
        isLoadingOlderPosts = false
        didLoadAllHistory = false
        currentChannelPosts = []
        rebuildTimelineContent(scrollToBottom: false)
        refreshChannelMemberCount(channelId: ch.id)
        Task { @MainActor [weak self] in
            await self?.fetchAndRenderPosts(channelId: ch.id)
        }
    }

    func refreshChannelMemberCount(channelId: String) {
        guard let ws = webService, ws.isLogged(), !channelId.isEmpty else { return }
        Task { @MainActor [weak self] in
            guard let self = self,
                  let members = try? await ws.fetchChannelMembers(channelId: channelId, perPage: 200),
                  self.activeChannelId == channelId else { return }
            self.channelMembersCountLabel.stringValue = members.count >= 200 ? "200+" : "\(members.count)"
            self.layoutRightChatPanel()
        }
    }

    func fetchAndRenderPosts(channelId: String) async {
        guard let ws = webService, ws.isLogged() else { return }
        do {
            let postList = try await ws.fetchChannelPosts(channelId: channelId)
            var posts = postList.chronologicalPosts
            if let jumpId = self.pendingJumpPostId,
               !posts.contains(where: { $0.id == jumpId }),
               let target = try? await ws.fetchPost(postId: jumpId),
               target.channel_id == channelId {
                posts.append(target)
                posts.sort { $0.create_at < $1.create_at }
            }
            for post in posts {
                fetchAvatarIfNeeded(for: post.user_id)
            }
            let missingUserIds = Array(Set(posts.map { $0.user_id }).subtracting(usersById.keys))
            if !missingUserIds.isEmpty,
               let fetchedUsers = try? await ws.fetchUsersByIds(missingUserIds) {
                for u in fetchedUsers {
                    usersById[u.id] = u
                    usersByUsername[u.username.lowercased()] = u
                    fetchAvatarIfNeeded(for: u.id)
                }
            }
            let allUserIds = Array(Set(posts.map { $0.user_id }.filter { $0 != "system" }))
            if !allUserIds.isEmpty,
               let fetchedStatuses = try? await ws.fetchUserStatuses(userIds: allUserIds) {
                for st in fetchedStatuses {
                    if let end = st.dnd_end_time, end > 0 {
                        self.dndEndTimeByUser[st.user_id] = end
                    }
                    self.userStatusById[st.user_id] = self.normalizedStatus(st.status, dndEndTime: st.dnd_end_time)
                }
            }
            // Discard results for a channel that is no longer open.
            guard self.activeChannelId == channelId else { return }
            let topLevelPosts = posts.filter { ($0.root_id ?? "").isEmpty }
            self.didLoadAllHistory = posts.count < self.postsPerPage
            if self.newMessagesBaseline > 0 {
                let unread = topLevelPosts.filter { $0.create_at > self.newMessagesBaseline }
                self.newMessagesCount = unread.count
                self.newMessagesDividerPostId = unread.first?.id
            }
            self.newMessagesDividerArmed = false
            applyPostsToTimeline(topLevelPosts)
        } catch {
            NSLog("Failed to fetch posts for channel \(channelId): \(error.localizedDescription)")
        }
    }

    func applyPostsToTimeline(_ posts: [MMPost]) {
        currentChannelPosts = posts
        if pendingJumpPostId != nil {
            rebuildTimelineContent(scrollToBottom: false)
            scrollToPendingPostIfNeeded()
        } else if newMessagesDividerPostId != nil {
            rebuildTimelineContent(scrollToBottom: false)
            DispatchQueue.main.async { [weak self] in
                guard let self = self, let divider = self.newMessagesDividerView else { return }
                let clip = self.timelineScrollView.contentView
                let maxY = max(0, self.timelineDocView.frame.height - clip.bounds.height)
                let target = min(maxY, max(0, divider.frame.minY - 16))
                clip.scroll(to: NSPoint(x: 0, y: target))
                self.timelineScrollView.reflectScrolledClipView(clip)
                self.updateNewMessagesDividerState()
            }
        } else if channelScrollPositions[activeChannelId] != nil {
            rebuildTimelineContent(scrollToBottom: false)
            if !restoreChannelScrollPosition(for: activeChannelId) {
                scrollTimelineToBottom()
            }
        } else {
            rebuildTimelineContent(scrollToBottom: true)
        }
    }

    func scrollToPendingPostIfNeeded() {
        guard let postId = pendingJumpPostId else { return }
        DispatchQueue.main.async { [weak self] in
            guard let self = self, self.pendingJumpPostId == postId else { return }
            guard let row = self.timelineDocView.subviews.first(where: {
                $0.identifier?.rawValue == "postRow_\(postId)"
            }) else {
                self.pendingJumpPostId = nil
                return
            }
            let clip = self.timelineScrollView.contentView
            let maxY = max(0, self.timelineDocView.frame.height - clip.bounds.height)
            let target = min(maxY, max(0, row.frame.minY - 80))
            clip.scroll(to: NSPoint(x: 0, y: target))
            self.timelineScrollView.reflectScrolledClipView(clip)
            self.updateTimelineHoverState()
            self.updateNewMessagesDividerState()
            self.pendingJumpPostId = nil

            if let panel = row as? RoundedEdgePanel {
                let previous = panel.color
                panel.color = Theme.shared.buttonBg.withAlphaComponent(0.08)
                panel.setNeedsAppearanceUpdate()
                DispatchQueue.main.asyncAfter(deadline: .now() + 1.5) {
                    panel.color = previous
                    panel.setNeedsAppearanceUpdate()
                }
            }
        }
    }

    func updateThreadReplyCount(rootId: String, replyCount: Int?) {
        guard !rootId.isEmpty else { return }
        var previous: Int?
        if let index = currentChannelPosts.firstIndex(where: { $0.id == rootId }) {
            previous = currentChannelPosts[index].reply_count
            let next = replyCount ?? ((previous ?? 0) + 1)
            currentChannelPosts[index].reply_count = next
        }
        if let index = threadPosts.firstIndex(where: { $0.id == rootId }) {
            if previous == nil { previous = threadPosts[index].reply_count }
            let next = replyCount ?? ((threadPosts[index].reply_count ?? 0) + 1)
            threadPosts[index].reply_count = next
        }
        guard let count = replyCount
            ?? currentChannelPosts.first(where: { $0.id == rootId })?.reply_count
        else { return }

        if count == 0 {
            if (previous ?? 0) > 0 {
                rebuildTimelineContent(scrollToBottom: false)
            }
        } else if (previous ?? 0) == 0 {
            // The root row did not reserve a footer yet; rebuild it once.
            rebuildTimelineContent(scrollToBottom: false)
        } else {
            updateThreadReplyFooterLabel(rootId: rootId, count: count)
        }
    }

    func updateThreadReplyFooterLabel(rootId: String, count: Int) {
        let identifier = "replyFooter_\(rootId)"
        func findFooter(in view: NSView) -> NSView? {
            if view.identifier?.rawValue == identifier { return view }
            for subview in view.subviews {
                if let found = findFooter(in: subview) { return found }
            }
            return nil
        }
        guard let footer = findFooter(in: timelineDocView),
              let label = footer.subviews.compactMap({ $0 as? NSTextField }).first
        else { return }
        label.stringValue = "\(count) \(count == 1 ? "reply" : "replies")"
        footer.isHidden = count == 0
    }

    func appendRealtimePost(_ post: MMPost) {
        guard post.channel_id == activeChannelId else { return }
        guard !currentChannelPosts.contains(where: { $0.id == post.id }) else { return }

        // Replies belong to threads, not the channel feed.
        let isReply = !(post.root_id ?? "").isEmpty
        if isReply, let rootId = post.root_id, !rootId.isEmpty {
            self.updateThreadReplyCount(rootId: rootId, replyCount: nil)
        }
        let clip = timelineScrollView.contentView
        let wasNearBottom = clip.bounds.maxY >= (timelineDocView.frame.height - 40)

        if !isReply {
            currentChannelPosts.append(post)
            currentChannelPosts.sort { $0.create_at < $1.create_at }
            if !wasNearBottom {
                if newMessagesCount == 0 {
                    newMessagesDividerPostId = post.id
                    newMessagesDividerArmed = true
                }
                newMessagesCount += 1
            }
        }
        fetchAvatarIfNeeded(for: post.user_id)
        if wasNearBottom {
            // Reading the live edge clears the divider; only users who are
            // scrolled up get the floating "N new messages" pill.
            newMessagesCount = 0
            newMessagesDividerPostId = nil
            newMessagesDividerView = nil
        }
        if !isReply {
            if !appendRenderedPostRow(post, wasNearBottom: wasNearBottom) {
                rebuildTimelineContent(scrollToBottom: wasNearBottom)
            }
        } else if isRightPanelVisible && rightPanelMode == .thread {
            loadThread()
        }

        guard usersById[post.user_id] == nil,
              let ws = webService else { return }
        Task { @MainActor [weak self] in
            guard let self = self else { return }
            guard let users = try? await ws.fetchUsersByIds([post.user_id]),
                  let user = users.first else { return }
            self.usersById[user.id] = user
            self.usersByUsername[user.username.lowercased()] = user
            self.fetchAvatarIfNeeded(for: user.id)
            // The new user's display name was unknown when the row was built;
            // refresh once now that it is available.
            self.rebuildTimelineContent(scrollToBottom: false)
        }
    }

    func updateConnectionState(connected: Bool, message: String) {
        viewModel.isWebSocketConnected = connected
        connectionLabel.stringValue = message
        connectionBanner.isHidden = connected
        if !connected {
            layoutRightChatPanel()
        }
    }

    func refreshServerTheme(teamId: String?) {
        guard let ws = webService, ws.isLogged() else { return }
        Task { @MainActor [weak self] in
            guard let self = self else { return }
            let me: MMUser?
            if let current = self.currentUser {
                me = current
            } else {
                me = try? await ws.fetchCurrentUser()
            }
            guard let userId = me?.id,
                  let preferences = try? await ws.fetchUserPreferences(userId: userId) else { return }
            ThemeManager.shared.apply(preferences: preferences, teamId: teamId)
            self.applyCurrentTheme()
        }
    }

    /// Mattermost-compatible mention detection: the user's @username, the
    /// special @here/@channel/@all mentions and any configured mention keys.
    /// Matching is word-bounded so emails and adjacent text do not count.
    func isCurrentUserMentioned(in post: MMPost) -> Bool {
        guard let username = currentUser?.username.lowercased(), !username.isEmpty else { return false }
        let message = post.message.lowercased()
        var candidates = ["@" + username, "@here", "@channel", "@all"]
        if let keys = currentUser?.notify_props?.mention_keys {
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

    func isChannelMuted(_ channelId: String) -> Bool {
        if mutedChannelIds.contains(channelId) { return true }
        if let desktop = channelDesktopNotificationByChannel[channelId] {
            return desktop.lowercased() == "none"
        }
        guard let props = membershipsByChannel[channelId]?.notify_props else { return false }
        return props.desktop?.lowercased() == "none"
            || props.mark_unread?.lowercased() == "mention"
    }

    func handleRemoteChannelViewed(_ channelId: String) {
        guard !channelId.isEmpty else { return }
        unreadByChannel[channelId] = 0
        mentionsByChannel[channelId] = 0
        lastViewedAtByChannel[channelId] = Int64(Date().timeIntervalSince1970 * 1000)
        (NSApp.delegate as? AppDelegate)?.markChannelRead(channelId)
        updateSidebarBadges()
    }

    func handleRemoteChannelUnread(_ channelId: String) {
        guard !channelId.isEmpty, channelId != activeChannelId else { return }
        unreadByChannel[channelId, default: 0] = max(1, unreadByChannel[channelId] ?? 0)
        updateSidebarBadges()
    }

    func handleRealtimePostDeleted(postId: String, channelId: String) {
        currentChannelPosts.removeAll { $0.id == postId }
        threadPosts.removeAll { $0.id == postId }
        if postId == threadRootId && !threadRootId.isEmpty {
            threadRootId = ""
            closeRightPanel()
            return
        }
        if activeChannelId == channelId {
            rebuildTimelineContent(scrollToBottom: false)
        }
        guard isRightPanelVisible else { return }
        switch rightPanelMode {
        case .thread:
            if !threadRootId.isEmpty { loadThread() } else { renderThreadPanel(empty: "This thread was deleted") }
        case .threads: loadThreads()
        case .pinned: loadPinnedPosts()
        case .mentions: loadMentions()
        case .saved: loadSavedPosts()
        case .files: loadChannelFiles()
        default: break
        }
    }

    func handleIncomingPost(_ post: MMPost) {
        let isSystemMessage = post.type?.hasPrefix("system_") ?? false
        let ws = webService
        let myUserId = currentUser?.id ?? ws?.currentUserId ?? ""
        let isMine = !myUserId.isEmpty && post.user_id == myUserId
        guard !isSystemMessage, !isMine else { return }

        let isVisible = NSApp.isActive && isKeyWindow && post.channel_id == activeChannelId
        guard let appDelegate = NSApp.delegate as? AppDelegate else { return }
        if isVisible {
            appDelegate.markChannelRead(post.channel_id)
            return
        }

        // Muted channels do not notify and do not accrue unread/mention badges.
        guard !isChannelMuted(post.channel_id) else {
            updateSidebarBadges()
            return
        }

        let isMentioned = isCurrentUserMentioned(in: post)
        unreadByChannel[post.channel_id, default: 0] += 1
        if isMentioned {
            mentionsByChannel[post.channel_id, default: 0] += 1
        }
        updateSidebarBadges()

        let prefs = currentUser?.notify_props
        let desktop = prefs?.desktop?.lowercased() ?? "all"
        let desktopThreads = prefs?.desktop_threads?.lowercased() != "false"
        let soundEnabled = prefs?.desktop_sound?.lowercased() != "false"
        let isThreadReply = !(post.root_id ?? "").isEmpty
        let status = currentUserStatus.lowercased()

        let shouldNotify = status != "dnd"
            && status != "offline"
            && desktop != "none"
            && (desktop != "mention" || isMentioned)
            && (desktopThreads || !isThreadReply)

        let channel = channelsById[post.channel_id]
        let channelName = channel.map { channelDisplayName(for: $0) } ?? ""
        let author = usersById[post.user_id]?.username ?? "New message"
        appDelegate.noteIncomingMessage(
            channelId: post.channel_id,
            channelName: channelName,
            author: author,
            body: notificationExcerpt(from: post.message),
            notify: shouldNotify,
            sound: shouldNotify && soundEnabled,
            postId: post.id,
            rootId: post.root_id
        )
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

    func openChannel(withId channelId: String) {
        guard let channel = channelsById[channelId] else { return }
        selectedSidebarItemId = channel.id
        updateSidebarSelectionAppearance()
        loadChannelPosts(forSidebarItemId: channel.id)
    }

    @objc func appDidBecomeActive() {
        clearExpiredCustomStatusIfNeeded()
        refreshCustomStatus()
        guard !activeChannelId.isEmpty else { return }
        markActiveChannelViewed()
    }

    func loadOlderPosts() {
        guard !isLoadingOlderPosts, !didLoadAllHistory,
              let before = currentChannelPosts.first?.id,
              !activeChannelId.isEmpty,
              let ws = webService, ws.isLogged() else { return }
        let channelId = activeChannelId
        isLoadingOlderPosts = true

        Task { @MainActor [weak self] in
            guard let self = self else { return }
            defer { self.isLoadingOlderPosts = false }
            guard let list = try? await ws.fetchChannelPosts(channelId: channelId, before: before) else { return }
            let older = list.order.compactMap { list.posts[$0] }
                .filter { ($0.root_id ?? "").isEmpty }
            guard self.activeChannelId == channelId else { return }
            let page = TimelinePager.merge(
                existing: self.currentChannelPosts,
                older: older,
                pageSize: self.postsPerPage
            )
            if page.didReachEnd {
                self.didLoadAllHistory = true
            }
            guard !page.inserted.isEmpty else {
                self.rebuildTimelineContent(scrollToBottom: false)
                return
            }

            let anchorHeight = self.timelineDocView.frame.height
            let anchorOffset = self.timelineScrollView.contentView.bounds.origin.y

            self.currentChannelPosts = page.posts
            let missingUserIds = Array(Set(page.inserted.map { $0.user_id }).subtracting(self.usersById.keys))
            if !missingUserIds.isEmpty, let users = try? await ws.fetchUsersByIds(missingUserIds) {
                for user in users {
                    self.usersById[user.id] = user
                }
            }
            self.rebuildTimelineContent(scrollToBottom: false)

            let addedHeight = self.timelineDocView.frame.height - anchorHeight
            if addedHeight > 0, anchorOffset > 0 {
                let clip = self.timelineScrollView.contentView
                clip.scroll(to: NSPoint(x: 0, y: anchorOffset + addedHeight))
                self.timelineScrollView.reflectScrolledClipView(clip)
            }
        }
    }

    @objc func timelineBoundsDidChange(_ notification: Notification) {
        updateTimelineHoverState()
        updateNewMessagesDividerState()
        if timelineScrollView.contentView.bounds.minY < 120 {
            loadOlderPosts()
        }
    }

    func updateTimelineHoverState() {
        let mouseLoc = self.mouseLocationOutsideOfEventStream
        let mouseInScroll = timelineScrollView.convert(mouseLoc, from: nil)
        let isMouseInScroll = timelineScrollView.bounds.contains(mouseInScroll)

        let visibleRect = timelineScrollView.contentView.bounds
        for subview in timelineDocView.subviews {
            guard let panel = subview as? RoundedEdgePanel else { continue }
            if !panel.frame.intersects(visibleRect) && !panel.isHovered {
                continue
            }
            panel.updateHoverRecursively(windowMouseLocation: mouseLoc, isWindowActiveAndInScrollView: isMouseInScroll)
        }
    }
}
