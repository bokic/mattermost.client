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
              (unreadByChannel[activeChannelId] ?? 0) > 0 || (mentionsByChannel[activeChannelId] ?? 0) > 0,
              let ws = (NSApp.delegate as? AppDelegate)?.webService, ws.isLogged() else { return }
        let channelId = activeChannelId
        Task { @MainActor [weak self] in
            guard let self = self else { return }
            if let viewedAt = try? await ws.markChannelViewed(channelId: channelId) {
                self.lastViewedAtByChannel[channelId] = viewedAt
            }
            self.unreadByChannel[channelId] = 0
            self.mentionsByChannel[channelId] = 0
            self.updateSidebarBadges()
        }
    }

    func bindWebServiceAndLoadData() {
        guard let ws = (NSApp.delegate as? AppDelegate)?.webService else { return }
        viewModel.webService = ws

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
                      let ws = (NSApp.delegate as? AppDelegate)?.webService else { return }
                if let updated = try? await ws.fetchPost(postId: postId) {
                    self.applyUpdatedPost(updated)
                }
            }
        }

        ws.onWebSocketStateChanged = { [weak self] connected, message in
            Task { @MainActor [weak self] in
                self?.updateConnectionState(connected: connected, message: message)
            }
        }
        updateConnectionState(
            connected: ws.isWebSocketConnected,
            message: ws.isWebSocketConnected ? "Connected" : "Connecting to Mattermost…"
        )

        ws.onWebSocketEvent = { event in
            DebugLog.logSensitive("ws.onWebSocketEvent: \(event)")
        }

        ws.onWebSocketConnected = { [weak self] in
            DebugLog.log("ws.onWebSocketConnected callback triggered")
            self?.refreshUserStatuses()
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
            if let myId = self.currentUser?.id ?? (NSApp.delegate as? AppDelegate)?.webService.currentUserId, myId == userId {
                self.applyCurrentUserStatus(normalized)
            }
        }

        ws.onUserTyping = { [weak self] userId, channelId, _ in
            guard let self = self, channelId == self.activeChannelId else { return }
            if let myId = self.currentUser?.id, myId == userId { return }
            let typer = self.usersById[userId]?.username ?? "Someone"
            self.composerHelpLabel.stringValue = "\(typer) is typing..."
            DispatchQueue.main.asyncAfter(deadline: .now() + 3.0) { [weak self] in
                self?.composerHelpLabel.stringValue = "Help"
            }
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
            self?.refreshUserStatuses()
        }

        guard ws.isLogged() else { return }

        Task { @MainActor [weak self] in
            guard let self = self else { return }
            do {
                let me = try await ws.fetchCurrentUser()
                self.currentUser = me
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
                guard let team = teams.first else { return }
                self.updateTeamHeader(with: team)

                let channels = try await ws.fetchChannels(teamId: team.id)
                var allChannels = channels
                if let myChannels = try? await ws.fetchAllChannels() {
                    var chMap: [String: MMChannel] = [:]
                    for c in channels { chMap[c.id] = c }
                    for c in myChannels { chMap[c.id] = c }
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

                let botCh = self.channelsByName["system-bot"]
                    ?? self.channelsByName["system bot"]
                    ?? allChannels.first(where: { self.isChannelBot(for: $0) })
                let defaultCh = (CommandLine.arguments.contains("--system-bot") ? botCh : nil)
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
        activeChannelId = ch.id
        _ = cancelEditing()
        closeCompletion()
        clearPendingAttachments()
        newMessagesDividerPostId = nil
        newMessagesDividerView = nil
        newMessagesCount = 0
        newMessagesDividerArmed = false
        newMessagesPill.isHidden = true
        newMessagesBaseline = lastViewedAtByChannel[ch.id] ?? 0
        refreshFavoriteState()
        (NSApp.delegate as? AppDelegate)?.markChannelRead(ch.id)
        markActiveChannelViewed()
        reloadRightPanelIfNeeded()
        let resolvedTitle = channelDisplayName(for: ch)
        channelTitleLabel.stringValue = resolvedTitle
        if isRightPanelVisible {
            rightPanelSubtitle.stringValue = resolvedTitle
        }
        heroTitleLabel.stringValue = resolvedTitle
        composerPlaceholderLabel.stringValue = "Write to \(resolvedTitle)"
        entryView.placeholderString = composerPlaceholderLabel.stringValue
        if ch.type == "D" {
            heroDescriptionLabel.stringValue = "This is the start of your direct message history with \(resolvedTitle). Messages and files shared here are not shown to people outside this conversation."
        } else {
            heroDescriptionLabel.stringValue = "Welcome to \(resolvedTitle). Post messages here that you want everyone to see. Everyone\nautomatically becomes a member of this channel when they join the team."
        }
        layoutRightChatPanel()
        closeSearchResults()
        isLoadingOlderPosts = false
        didLoadAllHistory = false
        currentChannelPosts = []
        rebuildTimelineContent(scrollToBottom: false)
        Task { @MainActor [weak self] in
            await self?.fetchAndRenderPosts(channelId: ch.id)
        }
    }

    func fetchAndRenderPosts(channelId: String) async {
        guard let ws = (NSApp.delegate as? AppDelegate)?.webService, ws.isLogged() else { return }
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
            self.didLoadAllHistory = posts.count < self.postsPerPage
            if self.newMessagesBaseline > 0 {
                let unread = posts.filter { $0.create_at > self.newMessagesBaseline }
                self.newMessagesCount = unread.count
                self.newMessagesDividerPostId = unread.first?.id
            }
            self.newMessagesDividerArmed = false
            applyPostsToTimeline(posts)
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

    func appendRealtimePost(_ post: MMPost) {
        guard post.channel_id == activeChannelId else { return }
        guard !currentChannelPosts.contains(where: { $0.id == post.id }) else { return }

        currentChannelPosts.append(post)
        currentChannelPosts.sort { $0.create_at < $1.create_at }
        fetchAvatarIfNeeded(for: post.user_id)
        rebuildTimelineContent(scrollToBottom: true)

        guard usersById[post.user_id] == nil,
              let ws = (NSApp.delegate as? AppDelegate)?.webService else { return }
        Task { @MainActor [weak self] in
            guard let self = self else { return }
            guard let users = try? await ws.fetchUsersByIds([post.user_id]),
                  let user = users.first else { return }
            self.usersById[user.id] = user
            self.usersByUsername[user.username.lowercased()] = user
            self.fetchAvatarIfNeeded(for: user.id)
            self.rebuildTimelineContent(scrollToBottom: true)
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

    func handleIncomingPost(_ post: MMPost) {
        let isSystemMessage = post.type?.hasPrefix("system_") ?? false
        let ws = (NSApp.delegate as? AppDelegate)?.webService
        let myUserId = currentUser?.id ?? ws?.currentUserId ?? ""
        let isMine = !myUserId.isEmpty && post.user_id == myUserId
        guard !isSystemMessage, !isMine else { return }

        let isVisible = NSApp.isActive && isKeyWindow && post.channel_id == activeChannelId
        guard let appDelegate = NSApp.delegate as? AppDelegate else { return }
        if isVisible {
            appDelegate.markChannelRead(post.channel_id)
            return
        }

        unreadByChannel[post.channel_id, default: 0] += 1
        let username = (currentUser?.username ?? "").lowercased()
        if !username.isEmpty && post.message.lowercased().contains("@" + username) {
            mentionsByChannel[post.channel_id, default: 0] += 1
        }
        updateSidebarBadges()

        let channel = channelsById[post.channel_id]
        let channelName = channel.map { channelDisplayName(for: $0) } ?? ""
        let author = usersById[post.user_id]?.username ?? "New message"
        appDelegate.noteIncomingMessage(
            channelId: post.channel_id,
            channelName: channelName,
            author: author,
            body: notificationExcerpt(from: post.message)
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
        guard !activeChannelId.isEmpty else { return }
        (NSApp.delegate as? AppDelegate)?.markChannelRead(activeChannelId)
        markActiveChannelViewed()
    }

    func loadOlderPosts() {
        guard !isLoadingOlderPosts, !didLoadAllHistory,
              let before = currentChannelPosts.first?.id,
              !activeChannelId.isEmpty,
              let ws = (NSApp.delegate as? AppDelegate)?.webService, ws.isLogged() else { return }
        let channelId = activeChannelId
        isLoadingOlderPosts = true

        Task { @MainActor [weak self] in
            guard let self = self else { return }
            defer { self.isLoadingOlderPosts = false }
            guard let list = try? await ws.fetchChannelPosts(channelId: channelId, before: before) else { return }
            let older = list.order.compactMap { list.posts[$0] }
            guard self.activeChannelId == channelId else { return }
            if older.count < self.postsPerPage {
                self.didLoadAllHistory = true
            }
            let existingIds = Set(self.currentChannelPosts.map { $0.id })
            let newPosts = older.filter { !existingIds.contains($0.id) }
            guard !newPosts.isEmpty else {
                self.rebuildTimelineContent(scrollToBottom: false)
                return
            }

            let anchorHeight = self.timelineDocView.frame.height
            let anchorOffset = self.timelineScrollView.contentView.bounds.origin.y

            self.currentChannelPosts.append(contentsOf: newPosts)
            self.currentChannelPosts.sort { $0.create_at < $1.create_at }
            let missingUserIds = Array(Set(newPosts.map { $0.user_id }).subtracting(self.usersById.keys))
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
