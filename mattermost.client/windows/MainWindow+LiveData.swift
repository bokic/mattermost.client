//
//  MainWindow+LiveData.swift
//  mattermost.client
//
//  View projection layer: binds WorkspaceRepository orchestration events to AppKit UI.
//  Business logic, pagination, read state, mention parsing and notification routing
//  are orchestrated by WorkspaceRepository.
//

import AppKit
import Foundation
import UniformTypeIdentifiers

extension MainWindow {

    func updateNewMessagesBaseline() {
        guard !activeChannelId.isEmpty else { return }
        let result = repository.computeNewMessagesBaseline(for: activeChannelId, posts: currentChannelPosts)
        newMessagesBaseline = result.baseline
        if newMessagesBaseline > 0 {
            newMessagesCount = result.unreadCount
            newMessagesDividerPostId = result.dividerPostId
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
                _ = try await self.repository.markChannelViewed(channelId: channelId)
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
        Task { @MainActor [weak self] in
            guard let self = self else { return }
            do {
                let teamChannelIds = try await self.repository.markAllChannelsRead(teamId: team.id, userId: userId)
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
        repository.markChannelReadLocally(channelId: channelId)
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
                try await self.repository.markChannelUnread(channelId: channelId, userId: userId, postId: lastPost.id)
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
        updateStoreScope()
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
                    self.repository.updateChannel(channel)
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
            DebugLog.log("ws.onMultipleStatusesReceived: \(statuses.count) statuses")
            guard let self = self else { return }
            for (userId, status) in statuses {
                let normalized = self.normalizedStatusForKnownUser(status, userId: userId)
                let oldStatus = self.userStatusById[userId]
                self.userStatusById[userId] = normalized
                if oldStatus != normalized {
                    self.updateChatWidgetUserStatus(userId: userId, status: normalized)
                    if userId == self.currentUser?.id {
                        self.applyCurrentUserStatus(normalized)
                    }
                }
            }
        }

        ws.onStatusChanged = { [weak self] userId, status in
            DebugLog.log("ws.onStatusChanged: userId=\(userId), status=\(status)")
            guard let self = self else { return }
            let normalized = self.normalizedStatusForKnownUser(status, userId: userId)
            let oldStatus = self.userStatusById[userId]
            self.userStatusById[userId] = normalized
            if oldStatus != normalized {
                self.updateChatWidgetUserStatus(userId: userId, status: normalized)
                if let myId = self.currentUser?.id ?? webService?.currentUserId, myId == userId {
                    self.applyCurrentUserStatus(normalized)
                }
            }
        }

        ws.onUserTyping = { [weak self] userId, channelId, parentId in
            guard let self = self else { return }
            if let myId = self.currentUser?.id, myId == userId { return }
            let typer = self.usersById[userId]?.username ?? "Someone"

            if let parentId = parentId, !parentId.isEmpty {
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
            self.repository.updateTeam(updatedTeam)
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
                    let (_, activeTeam) = self.repository.updateUserTeams(teams, savedTeamId: self.activeTeam?.id)
                    if let active = activeTeam {
                        self.updateTeamHeader(with: active)
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
        statusPollingTimer = Timer.scheduledTimer(withTimeInterval: 60.0, repeats: true) { [weak self] _ in
            MainActor.assumeIsolated {
                guard let self = self else { return }
                self.clearExpiredCustomStatusIfNeeded()
                if let ws = self.webService, !ws.isWebSocketConnected {
                    self.refreshUserStatuses()
                }
            }
        }

        guard ws.isLogged() else { return }

        Task { @MainActor [weak self] in
            guard let self = self else { return }
            do {
                let savedTeamId = UserDefaults.standard.string(forKey: "lastTeamId")
                let savedChannelId = UserDefaults.standard.string(forKey: "lastChannelId")
                #if DEBUG
                let isSystemBotArg = CommandLine.arguments.contains("--system-bot")
                #else
                let isSystemBotArg = false
                #endif
                let initial = try await self.repository.loadInitialWorkspaceData(
                    savedTeamId: savedTeamId,
                    savedChannelId: savedChannelId,
                    systemBotArg: isSystemBotArg
                )

                self.applyServerCustomStatus(from: initial.me)
                self.fetchAvatarIfNeeded(for: initial.me.id)
                self.loadFavoriteChannels()

                if let status = initial.myStatus {
                    self.applyCurrentUserStatus(status)
                    self.updateChatWidgetUserStatus(userId: initial.me.id, status: status)
                }

                self.updateTeamHeader(with: initial.activeTeam)
                UserDefaults.standard.set(initial.activeTeam.id, forKey: "lastTeamId")

                await self.preloadDMUsers(for: initial.allChannels)

                if let categoriesResponse = try? await ws.fetchSidebarCategories(teamId: initial.activeTeam.id) {
                    self.populateSidebarCategories(from: categoriesResponse, channels: initial.allChannels)
                }

                if let initialCh = initial.initialChannel {
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
        let (chOpt, channelChanged, previousChannelId) = repository.prepareChannelSwitch(to: itemId)
        guard let ch = chOpt else { return }

        if channelChanged {
            saveComposerDraft(for: previousChannelId)
            saveChannelScrollPosition(for: previousChannelId)
            if rightPanelMode == .thread { saveThreadDraft() }
            clearTimelineRowCache()
        }
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
            let result = try await repository.fetchChannelPosts(channelId: channelId, pageSize: postsPerPage)
            for post in result.posts {
                fetchAvatarIfNeeded(for: post.user_id)
            }
            if !result.missingUserIds.isEmpty,
               let fetchedUsers = try? await ws.fetchUsersByIds(result.missingUserIds) {
                for u in fetchedUsers {
                    usersById[u.id] = u
                    usersByUsername[u.username.lowercased()] = u
                    fetchAvatarIfNeeded(for: u.id)
                }
            }
            if !result.unknownStatusIds.isEmpty {
                if ws.isWebSocketConnected {
                    ws.requestStatusesByIds(result.unknownStatusIds)
                } else if let fetchedStatuses = try? await ws.fetchUserStatuses(userIds: result.unknownStatusIds) {
                    for st in fetchedStatuses {
                        if let end = st.dnd_end_time, end > 0 {
                            self.dndEndTimeByUser[st.user_id] = end
                        }
                        self.userStatusById[st.user_id] = self.normalizedStatus(st.status, dndEndTime: st.dnd_end_time)
                    }
                }
            }
            guard self.activeChannelId == channelId else { return }
            self.newMessagesBaseline = result.newMessagesBaseline
            self.newMessagesCount = result.newMessagesCount
            self.newMessagesDividerPostId = result.newMessagesDividerPostId
            self.newMessagesDividerArmed = false
            applyPostsToTimeline(result.posts)
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
        let (previous, next) = repository.updateThreadReplyCount(rootId: rootId, replyCount: replyCount)
        guard next > 0 || (previous ?? 0) > 0 else { return }

        if next == 0 {
            if (previous ?? 0) > 0 {
                rebuildTimelineContent(scrollToBottom: false)
            }
        } else if (previous ?? 0) == 0 {
            rebuildTimelineContent(scrollToBottom: false)
        } else {
            updateThreadReplyFooterLabel(rootId: rootId, count: next)
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
        let clip = timelineScrollView.contentView
        let wasNearBottom = clip.bounds.maxY >= (timelineDocView.frame.height - 40)
        let result = repository.appendRealtimePost(post, isScrolledUp: !wasNearBottom)

        switch result {
        case .ignoredNotCurrentChannel, .ignoredDuplicate:
            return
        case .threadReply(let rootId, let replyCount):
            updateThreadReplyFooterLabel(rootId: rootId, count: replyCount)
            if isRightPanelVisible && rightPanelMode == .thread {
                loadThread()
            }
        case .topLevel(let appendedPost, let isUnread, let missingUserId):
            fetchAvatarIfNeeded(for: appendedPost.user_id)
            if wasNearBottom {
                newMessagesCount = 0
                newMessagesDividerPostId = nil
                newMessagesDividerView = nil
            } else if isUnread {
                if newMessagesCount == 0 {
                    newMessagesDividerPostId = appendedPost.id
                    newMessagesDividerArmed = true
                }
                newMessagesCount += 1
            }
            if !appendRenderedPostRow(appendedPost, wasNearBottom: wasNearBottom) {
                rebuildTimelineContent(scrollToBottom: wasNearBottom)
            }
            if let userId = missingUserId, let ws = webService {
                Task { @MainActor [weak self] in
                    guard let self = self else { return }
                    if let users = try? await ws.fetchUsersByIds([userId]), let user = users.first {
                        self.usersById[user.id] = user
                        self.usersByUsername[user.username.lowercased()] = user
                        self.fetchAvatarIfNeeded(for: user.id)
                        self.updateAuthorInfo(for: user.id, username: user.username)
                    }
                }
            }
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

    func isCurrentUserMentioned(in post: MMPost) -> Bool {
        repository.isCurrentUserMentioned(in: post)
    }

    func isChannelMuted(_ channelId: String) -> Bool {
        repository.isChannelMuted(
            channelId,
            mutedChannelIds: mutedChannelIds,
            desktopNotificationOverrides: channelDesktopNotificationByChannel
        )
    }

    func handleRemoteChannelViewed(_ channelId: String) {
        guard !channelId.isEmpty else { return }
        repository.handleRemoteChannelViewed(channelId)
        (NSApp.delegate as? AppDelegate)?.markChannelRead(channelId)
        updateSidebarBadges()
    }

    func handleRemoteChannelUnread(_ channelId: String) {
        guard !channelId.isEmpty, channelId != activeChannelId else { return }
        repository.handleRemoteChannelUnread(channelId)
        updateSidebarBadges()
    }

    func handleRealtimePostDeleted(postId: String, channelId: String) {
        let result = repository.handleRealtimePostDeleted(postId: postId, channelId: channelId)
        if result.wasThreadRoot {
            closeRightPanel()
            return
        }
        if result.isCurrentChannel {
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
        let isVisible = NSApp.isActive && isKeyWindow && post.channel_id == activeChannelId
        let decision = repository.evaluateIncomingPost(
            post,
            isVisible: isVisible,
            mutedChannelIds: mutedChannelIds,
            desktopNotificationOverrides: channelDesktopNotificationByChannel
        )

        guard let appDelegate = NSApp.delegate as? AppDelegate else { return }
        switch decision {
        case .ignoreSelfOrSystem:
            break
        case .visibleInActiveChannel(let channelId):
            appDelegate.markChannelRead(channelId)
        case .muted:
            updateSidebarBadges()
        case .notify(let route):
            updateSidebarBadges()
            appDelegate.noteIncomingMessage(
                channelId: route.channelId,
                channelName: route.channelName,
                author: route.author,
                body: route.body,
                notify: route.shouldNotify,
                sound: route.sound,
                postId: route.postId,
                rootId: route.rootId
            )
        }
    }

    func notificationExcerpt(from message: String) -> String {
        repository.notificationExcerpt(from: message)
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
        refreshUserStatuses()
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
            let page = self.repository.mergeOlderPosts(older: older, pageSize: self.postsPerPage)
            guard page.insertedCount > 0 else {
                self.rebuildTimelineContent(scrollToBottom: false)
                return
            }

            let anchorHeight = self.timelineDocView.frame.height
            let anchorOffset = self.timelineScrollView.contentView.bounds.origin.y

            if !page.missingUserIds.isEmpty, let users = try? await ws.fetchUsersByIds(page.missingUserIds) {
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
