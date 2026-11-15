//
//  MainWindow+RightPanel.swift
//  mattermost.client
//
//  Split from MainWindow.swift.
//

import AppKit
import Foundation
import UniformTypeIdentifiers

extension MainWindow {

    func setupRightPanel() {
        let dividerColor = Theme.shared.divider
        rightPanel.color = Theme.shared.centerBg
        rightPanel.cornerRadius = 0
        rightPanel.borderWidth = 1
        rightPanel.borderColor = dividerColor
        rightPanel.isHidden = true

        rightPanelTitle.font = MMFont.font(ofSize: 16, weight: .semibold)
        rightPanelTitle.textColor = Theme.shared.centerText
        rightPanelTitle.isEditable = false
        rightPanelTitle.isSelectable = false
        rightPanel.addSubview(rightPanelTitle)

        rightPanelSubtitle.font = MMFont.font(ofSize: 12)
        rightPanelSubtitle.textColor = Theme.shared.centerText.withAlphaComponent(0.75)
        rightPanelSubtitle.isEditable = false
        rightPanelSubtitle.isSelectable = false
        rightPanel.addSubview(rightPanelSubtitle)

        rightPanelCloseButton.cornerRadius = MMRadius.control
        rightPanelCloseButton.color = .clear
        let closeIcon = NSImageView()
        if let image = NSImage(systemSymbolName: "xmark", accessibilityDescription: "Close panel") {
            closeIcon.image = image.withSymbolConfiguration(.init(pointSize: 10, weight: .semibold))
            closeIcon.contentTintColor = Theme.shared.centerTextMuted
        }
        closeIcon.frame = NSRect(x: 9, y: 9, width: 14, height: 14)
        rightPanelCloseButton.addSubview(closeIcon)
        rightPanelCloseButton.onClick = { [weak self] in
            self?.closeRightPanel()
        }
        rightPanel.addSubview(rightPanelCloseButton)

        rightPanelScroll.drawsBackground = false
        rightPanelScroll.hasVerticalScroller = true
        rightPanelScroll.autohidesScrollers = true
        rightPanelScroll.documentView = rightPanelDoc
        rightPanelScroll.contentView.postsBoundsChangedNotifications = true
        NotificationCenter.default.addObserver(
            self,
            selector: #selector(rightPanelDidScroll),
            name: NSView.boundsDidChangeNotification,
            object: rightPanelScroll.contentView
        )
        rightPanel.addSubview(rightPanelScroll)

        threadReplyPanel.color = Theme.shared.centerBg
        threadReplyPanel.cornerRadius = MMRadius.control
        threadReplyPanel.borderWidth = 1
        threadReplyPanel.borderColor = dividerColor
        threadReplyPanel.isHidden = true

        threadReplyTextView.font = MMFont.font(ofSize: 13)
        threadReplyTextView.textColor = Theme.shared.centerText
        threadReplyTextView.drawsBackground = false
        threadReplyTextView.isRichText = false
        threadReplyTextView.isAutomaticQuoteSubstitutionEnabled = false
        threadReplyTextView.isAutomaticDashSubstitutionEnabled = false
        threadReplyTextView.isAutomaticTextReplacementEnabled = false
        threadReplyTextView.isAutomaticSpellingCorrectionEnabled = false
        threadReplyTextView.textContainerInset = NSSize(width: 0, height: 5)
        threadReplyTextView.textContainer?.lineFragmentPadding = 0
        threadReplyTextView.placeholderString = "Reply to thread…"
        threadReplyTextView.delegate = self
        threadReplyTextView.onFilesDropped = { [weak self] urls in
            self?.uploadThreadFiles(urls)
        }
        threadReplyTextView.onDropStateChanged = { [weak self] active in
            self?.threadReplyPanel.borderColor = active
                ? Theme.shared.buttonBg
                : Theme.shared.divider
            self?.threadReplyPanel.setNeedsAppearanceUpdate()
        }
        threadReplyTextView.onImagePasted = { [weak self] data, filename in
            self?.uploadThreadPastedImage(data, filename: filename)
        }

        threadReplyScroll.drawsBackground = false
        threadReplyScroll.hasVerticalScroller = true
        threadReplyScroll.autohidesScrollers = true
        threadReplyScroll.borderType = .noBorder
        threadReplyScroll.documentView = threadReplyTextView
        threadReplyTextView.minSize = NSSize(width: 0, height: 48)
        threadReplyTextView.maxSize = NSSize(width: CGFloat.greatestFiniteMagnitude, height: 48)
        threadReplyTextView.isVerticallyResizable = true
        threadReplyTextView.isHorizontallyResizable = false
        threadReplyTextView.autoresizingMask = [.width]
        threadReplyPanel.addSubview(threadReplyScroll)

        threadAttachmentTray.isHidden = true
        threadReplyPanel.addSubview(threadAttachmentTray)

        threadEmojiButton.color = .clear
        threadEmojiButton.cornerRadius = MMRadius.control
        let threadEmojiIcon = NSImageView()
        if let image = NSImage(systemSymbolName: "face.smiling", accessibilityDescription: "Add emoji") {
            threadEmojiIcon.image = image.withSymbolConfiguration(.init(pointSize: 12, weight: .regular))
            threadEmojiIcon.contentTintColor = Theme.shared.centerTextMuted
        }
        threadEmojiIcon.frame = NSRect(x: 5, y: 5, width: 14, height: 14)
        threadEmojiButton.addSubview(threadEmojiIcon)
        threadEmojiButton.onClick = { [weak self] in
            self?.toggleEmojiPanel(for: .thread)
        }
        threadEmojiButton.accessibilityTitle = "Add emoji"
        threadReplyPanel.addSubview(threadEmojiButton)

        threadAttachButton.color = .clear
        threadAttachButton.cornerRadius = MMRadius.control
        let threadAttachIcon = NSImageView()
        if let image = NSImage(systemSymbolName: "paperclip", accessibilityDescription: "Attach files") {
            threadAttachIcon.image = image.withSymbolConfiguration(.init(pointSize: 12, weight: .regular))
            threadAttachIcon.contentTintColor = Theme.shared.centerTextMuted
        }
        threadAttachIcon.frame = NSRect(x: 5, y: 5, width: 14, height: 14)
        threadAttachButton.addSubview(threadAttachIcon)
        threadAttachButton.onClick = { [weak self] in
            self?.attachThreadFiles()
        }
        threadAttachButton.accessibilityTitle = "Attach files"
        threadReplyPanel.addSubview(threadAttachButton)

        threadSendButton.color = Theme.shared.centerText.withAlphaComponent(0.08)
        threadSendButton.cornerRadius = MMRadius.control
        if let image = NSImage(systemSymbolName: "paperplane.fill", accessibilityDescription: "Send reply") {
            threadSendIconView.image = image.withSymbolConfiguration(.init(pointSize: 12, weight: .semibold))
            threadSendIconView.contentTintColor = Theme.shared.centerText.withAlphaComponent(0.32)
        }
        threadSendIconView.frame = NSRect(x: 6, y: 6, width: 14, height: 14)
        threadSendButton.addSubview(threadSendIconView)
        threadSendButton.onClick = { [weak self] in
            self?.sendThreadReply()
        }
        threadSendButton.accessibilityTitle = "Send reply"
        threadReplyPanel.addSubview(threadSendButton)
        rightPanel.addSubview(threadReplyPanel)

        rightPanelResizeHandle.onDrag = { [weak self] deltaX in
            guard let self = self else { return }
            let maxWidth = max(280, self.chatPanel.bounds.width - 360)
            self.rightPanelWidth = min(max(MMMetric.rightPanelMinWidth, self.rightPanelWidth - deltaX), maxWidth)
            self.layoutRightChatPanel()
        }
        rightPanelResizeHandle.onEnd = { [weak self] in
            guard let self = self else { return }
            UserDefaults.standard.set(Double(self.rightPanelWidth), forKey: "rhsWidth")
            self.reloadRightPanelIfNeeded()
        }
        rightPanel.addSubview(rightPanelResizeHandle)

        chatPanel.addSubview(rightPanel)
    }

    func showRightPanel(mode: RightPanelMode) {
        if rightPanelMode == .thread && mode != .thread {
            saveThreadDraft()
        }
        if completionTarget == .thread && mode != .thread {
            closeCompletion()
        }
        rightPanelMode = mode
        isRightPanelVisible = true
        rightPanel.isHidden = false
        if mode == .settings || mode == .browse {
            rightPanelSubtitle.stringValue = ""
        } else {
            rightPanelSubtitle.stringValue = channelsById[activeChannelId].map { channelDisplayName(for: $0) } ?? ""
        }
        layoutRightChatPanel()

        switch mode {
        case .threads:
            rightPanelTitle.stringValue = L10n.string("Threads")
            loadThreads()
        case .members:
            rightPanelTitle.stringValue = L10n.string("Members")
            loadChannelMembers()
        case .pinned:
            rightPanelTitle.stringValue = L10n.string("Pinned Posts")
            loadPinnedPosts()
        case .mentions:
            rightPanelTitle.stringValue = L10n.string("Recent Mentions")
            loadMentions()
        case .saved:
            rightPanelTitle.stringValue = L10n.string("Saved Posts")
            loadSavedPosts()
        case .settings:
            rightPanelTitle.stringValue = L10n.string("Settings")
            loadSettingsPanel()
        case .browse:
            rightPanelTitle.stringValue = L10n.string("Browse Channels")
            loadBrowseChannels()
        case .thread:
            rightPanelTitle.stringValue = "Thread"
            restoreThreadDraft()
            renderThreadAttachments()
            updateThreadSendState()
            loadThread()
        case .files:
            rightPanelTitle.stringValue = L10n.string("Files")
            loadChannelFiles()
        case .channelInfo:
            rightPanelTitle.stringValue = L10n.string("Channel Info")
            loadChannelInfo()
        }
        layoutRightChatPanel()
    }

    func toggleRightPanel(mode: RightPanelMode) {
        if isRightPanelVisible && rightPanelMode == mode {
            closeRightPanel()
        } else {
            showRightPanel(mode: mode)
        }
    }

    func closeRightPanel() {
        if rightPanelMode == .thread { saveThreadDraft() }
        if completionTarget == .thread { closeCompletion() }
        isRightPanelVisible = false
        rightPanel.isHidden = true
        lastRightPanelContentWidth = 0
        layoutRightChatPanel()
    }

    func reloadRightPanelIfNeeded() {
        guard isRightPanelVisible else { return }
        switch rightPanelMode {
        case .threads: loadThreads()
        case .members: loadChannelMembers()
        case .pinned: loadPinnedPosts()
        case .mentions: loadMentions()
        case .saved: loadSavedPosts()
        case .settings: loadSettingsPanel()
        case .browse: loadBrowseChannels()
        case .thread: loadThread()
        case .files: loadChannelFiles()
        case .channelInfo: loadChannelInfo()
        }
    }

    func loadThreads(reset: Bool = true) {
        guard let ws = webService, ws.isLogged(),
              let team = activeTeam else {
            if reset { renderRightPanel(empty: "Sign in to see your threads", rows: []) }
            return
        }
        let userId = currentUser?.id ?? ws.currentUserId
        guard !userId.isEmpty else {
            if reset { renderRightPanel(empty: "Sign in to see your threads", rows: []) }
            return
        }

        if reset {
            threadsRequestToken += 1
            threadItemsPage = 0
            threadItemsHasMore = false
            threadItemsLoading = true
            renderRightPanel(empty: "Loading threads…", rows: [])
        } else {
            guard threadItemsHasMore, !threadItemsLoading else { return }
            threadItemsLoading = true
            renderThreadsPanel()
        }

        let token = threadsRequestToken
        let page = reset ? 0 : threadItemsPage + 1
        let pageSize = 30
        Task { @MainActor [weak self] in
            guard let self = self else { return }
            do {
                let response = try await ws.fetchThreadsPage(
                    userId: userId,
                    teamId: team.id,
                    page: page,
                    perPage: pageSize
                )
                guard token == self.threadsRequestToken else { return }
                if reset {
                    self.threadItems = response.threads
                } else {
                    let existing = Set(self.threadItems.map(\.id))
                    self.threadItems += response.threads.filter { !existing.contains($0.id) }
                }
                self.threadItemsPage = page
                self.threadItemsHasMore = response.threads.count == pageSize
                self.threadItemsLoading = false
                if let unread = response.total_unread_threads {
                    self.totalUnreadThreads = unread
                } else {
                    self.recomputeThreadUnreadCount()
                }
                self.updateSidebarBadges()

                let authorIds = response.threads.compactMap { $0.post?.user_id }
                self.hydrateUsers(authorIds) { [weak self] in
                    guard let self = self, token == self.threadsRequestToken else { return }
                    self.renderThreadsPanel()
                }
            } catch {
                guard token == self.threadsRequestToken else { return }
                self.threadItemsLoading = false
                if reset {
                    self.renderRightPanel(empty: "Could not load threads", rows: [])
                } else {
                    self.renderThreadsPanel()
                }
            }
        }
    }

    func loadMoreThreads() {
        guard threadItemsHasMore, !threadItemsLoading else { return }
        loadThreads(reset: false)
    }

    @objc func rightPanelDidScroll() {
        guard isRightPanelVisible,
              rightPanelMode == .threads,
              threadItemsHasMore,
              !threadItemsLoading
        else { return }
        let clip = rightPanelScroll.contentView.bounds
        if clip.maxY >= rightPanelDoc.frame.height - 100 {
            loadMoreThreads()
        }
    }

    func isThreadUnread(_ thread: MMThread) -> Bool {
        ThreadSupport.isUnread(
            lastReplyAt: thread.last_reply_at,
            lastViewedAt: thread.last_viewed_at,
            isMarkedRead: readThreadIds.contains(thread.id)
        )
    }

    func recomputeThreadUnreadCount() {
        totalUnreadThreads = threadItems.filter { isThreadUnread($0) }.count
        updateSidebarBadges()
    }

    func refreshThreadUnreadCount() {
        guard let ws = webService, ws.isLogged(), let team = activeTeam else { return }
        let userId = currentUser?.id ?? ws.currentUserId
        guard !userId.isEmpty else { return }
        Task { @MainActor [weak self] in
            guard let self = self else { return }
            guard let response = try? await ws.fetchThreadsPage(
                userId: userId,
                teamId: team.id,
                page: 0,
                perPage: 1
            ) else { return }
            if let unread = response.total_unread_threads {
                self.totalUnreadThreads = unread
                self.updateSidebarBadges()
            }
        }
    }

    func renderThreadsPanel() {
        guard !threadItems.isEmpty else {
            renderRightPanel(empty: L10n.string("No threads yet"), rows: [])
            return
        }
        let rows = threadItems.compactMap { thread -> RightPanelRow? in
            guard let post = thread.post else { return nil }
            let author = usersById[post.user_id]?.username ?? "Unknown"
            let channelName = channelsById[post.channel_id].map { channelDisplayName(for: $0) } ?? ""
            let snippet = post.message.replacingOccurrences(of: "\n", with: " ")
            let replies = thread.reply_count ?? 0
            let unread = isThreadUnread(thread)
            let meta = "\(replies) repl\(replies == 1 ? "y" : "ies")\(unread ? " • unread" : "")"
            return RightPanelRow(
                title: snippet.isEmpty ? "(attachment)" : snippet,
                subtitle: [author, channelName].filter { !$0.isEmpty }.joined(separator: " · "),
                meta: meta,
                action: { [weak self] in
                    self?.showThread(for: post)
                }
            )
        }
        renderRightPanel(empty: L10n.string("No threads yet"), rows: rows)
    }

    func showThread(for post: MMPost) {
        let root = (post.root_id?.isEmpty == false) ? post.root_id! : post.id
        if rightPanelMode == .thread && threadRootId != root {
            saveThreadDraft()
        }
        threadRequestToken += 1
        threadRootId = root
        threadPosts = [post]
        threadVisibleReplyLimit = 50
        threadComposerSending = false
        rightPanelMode = .thread
        isRightPanelVisible = true
        rightPanel.isHidden = false
        rightPanelTitle.stringValue = "Thread"
        let channel = channelsById[post.channel_id] ?? channelsById[activeChannelId]
        rightPanelSubtitle.stringValue = channel.map { channelDisplayName(for: $0) } ?? ""
        restoreThreadDraft()
        renderThreadPanel(empty: "Loading thread…")
        renderThreadAttachments()
        updateThreadSendState()
        layoutRightChatPanel()
        loadThread()
    }

    func loadThread() {
        guard let ws = webService, ws.isLogged(),
              !threadRootId.isEmpty else {
            renderThreadPanel(empty: "Could not load thread")
            return
        }
        threadRequestToken += 1
        let token = threadRequestToken
        let rootId = threadRootId
        let wasUnread = threadItems.first(where: { $0.id == rootId }).map { isThreadUnread($0) } ?? false

        Task { @MainActor [weak self] in
            guard let self = self else { return }
            do {
                let list = try await ws.fetchPostThread(postId: rootId)
                guard token == self.threadRequestToken, self.threadRootId == rootId else { return }
                let posts = list.order.compactMap { list.posts[$0] }
                    .sorted { $0.create_at < $1.create_at }
                guard !posts.isEmpty else {
                    self.threadPosts = []
                    self.renderThreadPanel(empty: "Could not load thread")
                    return
                }
                // The thread endpoint accepts any post in the thread; normalise the
                // reply target to the actual root post.
                if let root = posts.first(where: { ($0.root_id ?? "").isEmpty }) {
                    self.threadRootId = root.id
                }
                self.threadPosts = posts
                self.threadVisibleReplyLimit = max(50, self.threadVisibleReplyLimit)
                self.hydrateUsers(posts.map { $0.user_id }) { [weak self] in
                    guard let self = self, token == self.threadRequestToken else { return }
                    self.renderThreadPanel(scrollToBottom: true)
                }

                if let team = self.activeTeam {
                    try? await ws.markThreadRead(teamId: team.id, threadId: self.threadRootId)
                    guard token == self.threadRequestToken else { return }
                    let threadId = self.threadRootId
                    self.readThreadIds.insert(threadId)
                    if wasUnread {
                        self.totalUnreadThreads = max(0, self.totalUnreadThreads - 1)
                    }
                    self.updateSidebarBadges()
                    self.refreshThreadUnreadCount()
                    if self.rightPanelMode == .threads {
                        self.renderThreadsPanel()
                    }
                }
            } catch {
                guard token == self.threadRequestToken else { return }
                self.threadPosts = []
                self.renderThreadPanel(empty: "Could not load thread")
            }
        }
    }

    func renderThreadPanel(empty: String? = nil, scrollToBottom: Bool = true) {
        let panelWidth = max(rightPanelScroll.bounds.width, rightPanel.bounds.width)
        rightPanelDoc.subviews.forEach { $0.removeFromSuperview() }

        guard !threadPosts.isEmpty else {
            let label = NSTextField(labelWithString: empty ?? "No replies yet")
            label.font = MMFont.font(ofSize: 13)
            label.textColor = Theme.shared.centerTextMuted
            label.alignment = .center
            label.isEditable = false
            label.isSelectable = false
            label.frame = NSRect(x: 12, y: 24, width: panelWidth - 24, height: 20)
            rightPanelDoc.addSubview(label)
            rightPanelDoc.frame = NSRect(x: 0, y: 0, width: panelWidth, height: 64)
            return
        }

        let contentWidth = max(200, panelWidth - 24)
        let rootId = threadRootId
        let rootPost = threadPosts.first(where: { $0.id == rootId }) ?? threadPosts[0]
        let replies = threadPosts.filter { $0.id != rootPost.id }
        let pagination = ThreadSupport.visibleReplies(replies, limit: max(1, threadVisibleReplyLimit))
        let visibleReplies = pagination.posts
        let hiddenReplies = pagination.hidden
        var y: CGFloat = 8

        if hiddenReplies > 0 {
            let loadRow = RoundedEdgePanel()
            loadRow.color = .clear
            loadRow.cornerRadius = MMRadius.menu
            loadRow.frame = NSRect(x: 12, y: y, width: contentWidth, height: 28)
            let title = NSTextField(
                labelWithString: "Load \(min(50, hiddenReplies)) earlier repl\(hiddenReplies == 1 ? "y" : "ies")"
            )
            title.font = MMFont.font(ofSize: 12, weight: .semibold)
            title.textColor = Theme.shared.buttonBg
            title.alignment = .center
            title.isEditable = false
            title.isSelectable = false
            title.frame = NSRect(x: 8, y: 6, width: contentWidth - 16, height: 16)
            loadRow.addSubview(title)
            loadRow.onHoverChanged = { [weak loadRow] isHovered in
                loadRow?.color = isHovered ? Theme.shared.centerHover : .clear
                loadRow?.setNeedsAppearanceUpdate()
            }
            loadRow.onClick = { [weak self] in
                guard let self = self else { return }
                self.threadVisibleReplyLimit += 50
                self.renderThreadPanel(scrollToBottom: false)
            }
            loadRow.accessibilityTitle = "Load earlier replies"
            rightPanelDoc.addSubview(loadRow)
            y += 34
        }

        var lastUserId: String?
        var lastTimestamp: Int64 = 0
        var replyHeaderAdded = false

        for post in [rootPost] + visibleReplies {
            let isReply = post.id != rootPost.id
            if isReply && !replyHeaderAdded {
                replyHeaderAdded = true
                let replyCount = replies.count
                let header = NSTextField(labelWithString: "\(replyCount) \(replyCount == 1 ? "reply" : "replies")")
                header.font = MMFont.font(ofSize: 11, weight: .semibold)
                header.textColor = Theme.shared.centerTextMuted
                header.isEditable = false
                header.isSelectable = false
                header.frame = NSRect(x: 13, y: y + 4, width: contentWidth - 2, height: 16)
                rightPanelDoc.addSubview(header)
                y += 28
                lastUserId = nil
                lastTimestamp = 0
            }

            let postDate = Date(timeIntervalSince1970: TimeInterval(post.create_at) / 1000.0)
            let isSystem = (post.type?.hasPrefix("system_") ?? false)
            let withinGroupingWindow = (post.create_at - lastTimestamp) <= 5 * 60 * 1000
            let isConsecutive = (!isSystem && post.user_id == lastUserId
                && !post.user_id.isEmpty && withinGroupingWindow)
            let (rowView, rowH) = createPostRow(
                post: post,
                width: contentWidth,
                timeStr: Self.localizedTimeFormatter.string(from: postDate),
                isConsecutive: isConsecutive
            )
            rowView.frame.origin = CGPoint(x: 12, y: y)
            rightPanelDoc.addSubview(rowView)
            y += rowH + (isConsecutive ? 2 : 4)
            lastUserId = post.user_id
            lastTimestamp = post.create_at
        }

        y += 8
        rightPanelDoc.frame = NSRect(x: 0, y: 0, width: panelWidth, height: max(y, 1))
        guard scrollToBottom else { return }
        let clip = rightPanelScroll.contentView
        let maxY = max(0, rightPanelDoc.frame.height - clip.bounds.height)
        clip.scroll(to: NSPoint(x: 0, y: maxY))
        rightPanelScroll.reflectScrolledClipView(clip)
    }

    func threadChannelId() -> String {
        threadPosts.first(where: { $0.id == threadRootId })?.channel_id
            ?? threadPosts.first?.channel_id
            ?? activeChannelId
    }

    func attachThreadFiles() {
        guard !threadRootId.isEmpty else { return }
        let panel = NSOpenPanel()
        panel.allowsMultipleSelection = true
        panel.canChooseDirectories = false
        panel.canChooseFiles = true
        panel.beginSheetModal(for: self) { [weak self] response in
            guard response == .OK, let self = self else { return }
            self.uploadThreadFiles(panel.urls)
        }
    }

    func uploadThreadFiles(_ urls: [URL]) {
        let files = urls.filter { !$0.hasDirectoryPath }
        guard !files.isEmpty, !threadRootId.isEmpty else { return }
        let rootId = threadRootId
        let channelId = threadChannelId()
        let limit = attachmentSizeLimit
        for url in files {
            let size = (try? url.resourceValues(forKeys: [.fileSizeKey]))?.fileSize.map(Int64.init) ?? 0
            let name = url.lastPathComponent
            if AttachmentUploadPolicy.exceedsLimit(size: size, limit: limit) {
                showInfoAlert(
                    "\(name) is \(AttachmentUploadPolicy.formattedBytes(size)); the limit is \(AttachmentUploadPolicy.formattedBytes(limit))."
                )
                continue
            }
            let mime = UTType(filenameExtension: url.pathExtension)?.preferredMIMEType
                ?? "application/octet-stream"
            enqueueUpload(
                ActiveAttachmentUpload(
                    id: UUID(),
                    channelId: channelId,
                    threadRootId: rootId,
                    name: name,
                    size: size,
                    mimeType: mime,
                    source: .file(url),
                    state: .queued
                )
            )
        }
    }

    func uploadThreadPastedImage(_ data: Data, filename: String) {
        guard !threadRootId.isEmpty else { return }
        let limit = attachmentSizeLimit
        guard !AttachmentUploadPolicy.exceedsLimit(size: Int64(data.count), limit: limit) else {
            showInfoAlert(
                "The pasted image is \(AttachmentUploadPolicy.formattedBytes(Int64(data.count))); the limit is \(AttachmentUploadPolicy.formattedBytes(limit))."
            )
            return
        }
        enqueueUpload(
            ActiveAttachmentUpload(
                id: UUID(),
                channelId: threadChannelId(),
                threadRootId: threadRootId,
                name: filename,
                size: Int64(data.count),
                mimeType: "image/png",
                source: .data(data),
                state: .queued
            )
        )
    }

    func renderThreadAttachments() {
        threadAttachmentTray.subviews.forEach { $0.removeFromSuperview() }
        let pending = threadPendingAttachmentsByRootId[threadRootId] ?? []
        let uploads = activeAttachmentUploads.filter { $0.threadRootId == threadRootId }
        threadAttachmentTray.isHidden = pending.isEmpty && uploads.isEmpty
        guard !pending.isEmpty || !uploads.isEmpty else { return }

        let trayWidth = max(threadAttachmentTray.bounds.width, 200)
        let chipW: CGFloat = 160
        let chipH: CGFloat = 24
        let gap: CGFloat = 6
        let maxVisible = max(1, Int((trayWidth + gap) / (chipW + gap)))
        var x: CGFloat = 0
        var rendered = 0

        for upload in uploads.prefix(maxVisible) {
            renderUploadChip(
                upload,
                frame: NSRect(x: x, y: 2, width: chipW, height: chipH),
                in: threadAttachmentTray
            )
            x += chipW + gap
            rendered += 1
        }

        for attachment in pending.prefix(max(0, maxVisible - rendered)) {
            let chip = RoundedEdgePanel()
            chip.cornerRadius = MMRadius.control
            chip.color = Theme.shared.centerHover
            chip.borderWidth = 1
            chip.borderColor = Theme.shared.divider
            chip.frame = NSRect(x: x, y: 2, width: chipW, height: chipH)

            let icon = NSImageView()
            if let image = NSImage(systemSymbolName: "doc.fill", accessibilityDescription: attachment.name) {
                icon.image = image.withSymbolConfiguration(.init(pointSize: 11, weight: .regular))
                icon.contentTintColor = Theme.shared.centerTextMuted
            }
            icon.frame = NSRect(x: 7, y: 6, width: 12, height: 12)
            chip.addSubview(icon)

            let name = NSTextField(labelWithString: attachment.name)
            name.font = MMFont.font(ofSize: 11)
            name.textColor = Theme.shared.centerText
            name.lineBreakMode = .byTruncatingMiddle
            name.isEditable = false
            name.isSelectable = false
            name.frame = NSRect(x: 24, y: 5, width: chipW - 50, height: 14)
            chip.addSubview(name)

            let remove = RoundedEdgePanel()
            remove.cornerRadius = MMRadius.tiny
            remove.color = .clear
            remove.frame = NSRect(x: chipW - 22, y: 4, width: 16, height: 16)
            let xIcon = NSImageView()
            if let image = NSImage(systemSymbolName: "xmark", accessibilityDescription: "Remove attachment") {
                xIcon.image = image.withSymbolConfiguration(.init(pointSize: 8, weight: .bold))
                xIcon.contentTintColor = Theme.shared.centerTextMuted
            }
            xIcon.frame = NSRect(x: 4, y: 4, width: 8, height: 8)
            remove.addSubview(xIcon)
            let attachmentId = attachment.id
            remove.onClick = { [weak self] in
                self?.removeThreadAttachment(id: attachmentId)
            }
            chip.addSubview(remove)
            threadAttachmentTray.addSubview(chip)
            x += chipW + gap
            rendered += 1
        }
    }

    func removeThreadAttachment(id: String) {
        guard !threadRootId.isEmpty else { return }
        threadPendingAttachmentsByRootId[threadRootId]?.removeAll { $0.id == id }
        renderThreadAttachments()
        layoutRightChatPanel()
        updateThreadSendState()
    }

    func updateThreadSendState() {
        let hasText = !threadReplyTextView.string
            .trimmingCharacters(in: .whitespacesAndNewlines).isEmpty
        let hasAttachments = !(threadPendingAttachmentsByRootId[threadRootId] ?? []).isEmpty
        let hasUploads = activeAttachmentUploads.contains {
            $0.threadRootId == threadRootId && $0.isInProgress
        }
        let enabled = !threadComposerSending && !hasUploads && (hasText || hasAttachments)
        threadSendButton.color = enabled
            ? Theme.shared.buttonBg
            : Theme.shared.centerText.withAlphaComponent(0.08)
        threadSendIconView.contentTintColor = enabled
            ? .white
            : Theme.shared.centerText.withAlphaComponent(0.32)
        threadSendButton.setNeedsAppearanceUpdate()
        threadSendButton.accessibilityHelp = enabled ? "Send reply" : "Enter a reply first"
    }

    func sendThreadTypingIfNeeded() {
        guard !threadRootId.isEmpty else { return }
        let text = threadReplyTextView.string
        guard !text.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty else { return }
        if let last = lastThreadTypingSentAt, Date().timeIntervalSince(last) < 1.5 { return }
        lastThreadTypingSentAt = Date()
        webService?.sendUserTyping(channelId: threadChannelId(), parentId: threadRootId)
    }

    @objc func sendThreadReply() {
        guard let ws = webService, ws.isLogged(),
              !threadRootId.isEmpty,
              !threadComposerSending else { return }
        let rootId = threadRootId
        let channelId = threadChannelId()
        let text = threadReplyTextView.string.trimmingCharacters(in: .whitespacesAndNewlines)
        let attachments = threadPendingAttachmentsByRootId[rootId] ?? []
        guard !text.isEmpty || !attachments.isEmpty else { return }
        threadComposerSending = true
        updateThreadSendState()

        Task { @MainActor [weak self] in
            guard let self = self else { return }
            do {
                try await ws.createPost(
                    channelId: channelId,
                    message: text,
                    rootId: rootId,
                    fileIds: attachments.map(\.id)
                )
                self.threadPendingAttachmentsByRootId.removeValue(forKey: rootId)
                self.clearThreadDraft(for: rootId)
                if self.threadRootId == rootId {
                    self.threadReplyTextView.string = ""
                    self.threadReplyTextView.needsDisplay = true
                    self.threadComposerSending = false
                    self.renderThreadAttachments()
                    self.updateThreadSendState()
                    self.loadThread()
                }
            } catch {
                if self.threadRootId == rootId {
                    self.threadComposerSending = false
                    self.updateThreadSendState()
                }
                self.showInfoAlert("Could not send the reply: \(error.localizedDescription)")
            }
        }
    }

    func loadChannelMembers() {
        guard let ws = webService, ws.isLogged(),
              !activeChannelId.isEmpty else {
            renderRightPanel(empty: L10n.string("No channel selected"), rows: [])
            return
        }
        let channelId = activeChannelId
        Task { @MainActor [weak self] in
            guard let self = self else { return }
            guard let members = try? await ws.fetchChannelMembers(channelId: channelId, perPage: 200) else {
                self.renderRightPanel(empty: "Could not load members", rows: [])
                return
            }
            guard self.activeChannelId == channelId else { return }
            self.channelMembersCountLabel.stringValue = members.count >= 200 ? "200+" : "\(members.count)"
            self.layoutRightChatPanel()
            self.hydrateUsers(members.map { $0.user_id }) {
                let rows = members.map { member -> RightPanelRow in
                    let user = self.usersById[member.user_id]
                    let name = user?.username ?? member.user_id
                    let role = (member.roles ?? "").contains("channel_admin") ? "Channel Admin"
                        : (member.roles ?? "").contains("channel_user") ? "Member" : ""
                    return RightPanelRow(
                        title: name,
                        subtitle: [user?.first_name, user?.last_name].compactMap { $0 }.joined(separator: " "),
                        meta: role,
                        action: nil
                    )
                }
                self.renderRightPanel(empty: L10n.string("No members"), rows: rows)
            }
        }
    }

    func loadPinnedPosts() {
        guard let ws = webService, ws.isLogged(),
              !activeChannelId.isEmpty else {
            renderRightPanel(empty: L10n.string("No channel selected"), rows: [])
            return
        }
        let channelId = activeChannelId
        Task { @MainActor [weak self] in
            guard let self = self else { return }
            guard let list = try? await ws.fetchPinnedPosts(channelId: channelId) else {
                self.renderRightPanel(empty: "Could not load pinned posts", rows: [])
                return
            }
            let posts = list.order.compactMap { list.posts[$0] }
            self.hydrateUsers(posts.map { $0.user_id }) { [weak self] in
                guard let self = self else { return }
                let dateFormatter = Self.localizedDateTimeFormatter
                let rows = posts.map { post -> RightPanelRow in
                    let author = self.usersById[post.user_id]?.username ?? "Unknown"
                    let when = dateFormatter.string(from: Date(timeIntervalSince1970: TimeInterval(post.create_at) / 1000))
                    return RightPanelRow(
                        title: post.message.replacingOccurrences(of: "\n", with: " "),
                        subtitle: "\(author) · \(when)",
                        meta: "",
                        action: { [weak self] in
                            guard let self = self else { return }
                            self.pendingJumpPostId = post.id
                            self.openChannel(withId: post.channel_id)
                            self.closeRightPanel()
                        }
                    )
                }
                self.renderRightPanel(empty: "No pinned posts", rows: rows)
            }
        }
    }

    func loadChannelFiles() {
        guard let ws = webService, ws.isLogged(),
              let team = activeTeam, !activeChannelId.isEmpty else {
            renderFilesPanel([], empty: "Sign in to see files")
            return
        }
        let channelId = activeChannelId
        Task { @MainActor [weak self] in
            guard let self = self else { return }
            guard let files = try? await ws.searchChannelFiles(teamId: team.id, channelId: channelId) else {
                self.renderFilesPanel([], empty: "Could not load files")
                return
            }
            self.hydrateUsers(files.compactMap { $0.user_id }) {
                self.renderFilesPanel(files, empty: L10n.string("No files yet"))
            }
        }
    }

    func fileTimestamp(_ file: MMFileInfo) -> String {
        guard let millis = file.create_at else { return "" }
        let date = Date(timeIntervalSince1970: TimeInterval(millis) / 1000.0)
        let calendar = Calendar.current
        let time = Self.localizedTimeFormatter.string(from: date)
        if calendar.isDateInToday(date) {
            return "Today at \(time)"
        }
        if calendar.isDateInYesterday(date) {
            return "Yesterday at \(time)"
        }
        return "\(TimelineDateFormatter.date.string(from: date)) at \(time)"
    }

    func renderFilesPanel(_ files: [MMFileInfo], empty: String) {
        let width = max(rightPanelScroll.bounds.width, rightPanel.bounds.width)
        rightPanelDoc.subviews.forEach { $0.removeFromSuperview() }

        var y: CGFloat = 12
        let heading = NSTextField(labelWithString: "Recent files")
        heading.font = MMFont.font(ofSize: 14, weight: .semibold)
        heading.textColor = Theme.shared.centerText
        heading.isEditable = false
        heading.isSelectable = false
        heading.frame = NSRect(x: 15, y: y, width: max(0, width - 30), height: 20)
        rightPanelDoc.addSubview(heading)
        y += 30

        if files.isEmpty {
            let label = NSTextField(labelWithString: empty)
            label.font = MMFont.font(ofSize: 13)
            label.textColor = Theme.shared.centerTextMuted
            label.alignment = .center
            label.isEditable = false
            label.isSelectable = false
            label.frame = NSRect(x: 12, y: y + 8, width: max(0, width - 24), height: 20)
            rightPanelDoc.addSubview(label)
            rightPanelDoc.frame = NSRect(x: 0, y: 0, width: width, height: y + 48)
            return
        }

        let rowWidth = max(200, width - 28)
        let rowHeight: CGFloat = 64
        for file in files {
            let card = FlippedEdgePanel()
            card.cornerRadius = MMRadius.control
            card.color = Theme.shared.centerBg
            card.borderWidth = 1
            card.borderColor = Theme.shared.centerText.withAlphaComponent(0.16)
            card.frame = NSRect(x: 14, y: y, width: rowWidth, height: rowHeight)
            card.onHoverChanged = { [weak card] isHovered in
                card?.color = isHovered
                    ? Theme.shared.centerHoverSubtle
                    : Theme.shared.centerBg
                card?.setNeedsAppearanceUpdate()
            }

            let isImage = (file.mime_type ?? "").hasPrefix("image/")
            let thumbFrame = NSRect(x: 12, y: 12, width: MMMetric.avatarLarge, height: MMMetric.avatarLarge)
            var thumbImage: NSImage?
            if isImage {
                let thumb = RoundedEdgePanel()
                thumb.cornerRadius = MMRadius.control
                thumb.color = Theme.shared.centerHover
                thumb.clipContentToBounds = true
                thumb.frame = thumbFrame
                let imageView = NSImageView(frame: NSRect(origin: .zero, size: thumbFrame.size))
                imageView.imageScaling = .scaleProportionallyUpOrDown
                thumb.addSubview(imageView)
                card.addSubview(thumb)
                if let ws = webService {
                    Task { @MainActor [weak imageView] in
                        if let data = try? await ws.fetchFileData(fileId: file.id, preview: true),
                           let image = NSImage(data: data) {
                            imageView?.image = image
                            thumbImage = image
                        }
                    }
                }
            } else {
                let icon = FileTypeIconView(frame: thumbFrame)
                icon.fileExtension = fileExtensionLabel(for: file)
                card.addSubview(icon)
            }

            let name = NSTextField(labelWithString: file.name ?? file.id)
            name.font = MMFont.font(ofSize: 12, weight: .semibold)
            name.textColor = Theme.shared.centerText
            name.lineBreakMode = .byTruncatingMiddle
            name.isEditable = false
            name.isSelectable = false
            name.frame = NSRect(x: 64, y: 12, width: max(60, rowWidth - 76), height: 17)
            card.addSubview(name)

            let details = [formatFileSize(file.size), fileTimestamp(file)]
                .filter { !$0.isEmpty }
                .joined(separator: "  •  ")
            let metadata = NSTextField(labelWithString: details)
            metadata.font = MMFont.font(ofSize: 12)
            metadata.textColor = Theme.shared.centerText
            metadata.isEditable = false
            metadata.isSelectable = false
            metadata.frame = NSRect(x: 64, y: 32, width: max(60, rowWidth - 76), height: 17)
            card.addSubview(metadata)

            card.onClick = { [weak self] in
                if isImage {
                    self?.showLightbox(image: thumbImage, file: file, filename: file.name ?? "Image", authorId: file.user_id)
                } else {
                    self?.openAttachment(file)
                }
            }

            rightPanelDoc.addSubview(card)
            y += rowHeight + 8
        }

        rightPanelDoc.frame = NSRect(x: 0, y: 0, width: width, height: max(y, 1))
        rightPanelScroll.contentView.scroll(to: .zero)
        rightPanelScroll.reflectScrolledClipView(rightPanelScroll.contentView)
    }

    func loadMentions() {
        guard let ws = webService, ws.isLogged(),
              let team = activeTeam else {
            renderRightPanel(empty: "Sign in to see mentions", rows: [])
            return
        }
        let username = currentUser?.username ?? UserDefaults.standard.string(forKey: "username") ?? ""
        guard !username.isEmpty else {
            renderRightPanel(empty: "Sign in to see mentions", rows: [])
            return
        }
        Task { @MainActor [weak self] in
            guard let self = self else { return }
            guard let list = try? await ws.searchPosts(teamId: team.id, terms: "@" + username, perPage: 30) else {
                self.renderRightPanel(empty: "Could not load mentions", rows: [])
                return
            }
            let posts = list.order.compactMap { list.posts[$0] }
            self.hydrateUsers(posts.map { $0.user_id }) { [weak self] in
                guard let self = self else { return }
                let dateFormatter = Self.localizedDateTimeFormatter
                let rows = posts.map { post -> RightPanelRow in
                    let author = self.usersById[post.user_id]?.username ?? "Unknown"
                    let channelName = self.channelsById[post.channel_id].map { self.channelDisplayName(for: $0) } ?? ""
                    let when = dateFormatter.string(from: Date(timeIntervalSince1970: TimeInterval(post.create_at) / 1000))
                    return RightPanelRow(
                        title: post.message.replacingOccurrences(of: "\n", with: " "),
                        subtitle: [author, channelName, when].filter { !$0.isEmpty }.joined(separator: " · "),
                        meta: "",
                        action: { [weak self] in
                            guard let self = self else { return }
                            self.pendingJumpPostId = post.id
                            self.openChannel(withId: post.channel_id)
                            self.closeRightPanel()
                        }
                    )
                }
                self.renderRightPanel(empty: "No recent mentions", rows: rows)
            }
        }
    }

    func loadSavedPosts() {
        guard let ws = webService, ws.isLogged(),
              let team = activeTeam else {
            renderRightPanel(empty: "Sign in to see saved posts", rows: [])
            return
        }
        let userId = currentUser?.id ?? ws.currentUserId
        guard !userId.isEmpty else {
            renderRightPanel(empty: "Sign in to see saved posts", rows: [])
            return
        }
        Task { @MainActor [weak self] in
            guard let self = self else { return }
            guard let list = try? await ws.fetchFlaggedPosts(userId: userId, teamId: team.id) else {
                self.renderRightPanel(empty: "Could not load saved posts", rows: [])
                return
            }
            let posts = list.order.compactMap { list.posts[$0] }
            self.savedPostIds = Set(posts.map { $0.id })
            self.hydrateUsers(posts.map { $0.user_id }) { [weak self] in
                guard let self = self else { return }
                let dateFormatter = Self.localizedDateTimeFormatter
                let rows = posts.map { post -> RightPanelRow in
                    let author = self.usersById[post.user_id]?.username ?? "Unknown"
                    let channelName = self.channelsById[post.channel_id].map { self.channelDisplayName(for: $0) } ?? ""
                    let when = dateFormatter.string(from: Date(timeIntervalSince1970: TimeInterval(post.create_at) / 1000))
                    return RightPanelRow(
                        title: post.message.replacingOccurrences(of: "\n", with: " "),
                        subtitle: [author, channelName, when].filter { !$0.isEmpty }.joined(separator: " · "),
                        meta: "Saved",
                        action: { [weak self] in
                            guard let self = self else { return }
                            self.pendingJumpPostId = post.id
                            self.openChannel(withId: post.channel_id)
                            self.closeRightPanel()
                        }
                    )
                }
                self.renderRightPanel(empty: "No saved posts", rows: rows)
            }
        }
    }

    func loadSettingsPanel() {
        let host = UserDefaults.standard.string(forKey: "host") ?? ""
        let port = UserDefaults.standard.integer(forKey: "port")
        let username = currentUser?.username ?? UserDefaults.standard.string(forKey: "username") ?? ""
        let zoomPercent = Int((ZoomManager.shared.currentZoomFactor * 100).rounded())
        let server = port > 0 ? "\(host):\(port)" : host

        let rows: [RightPanelRow] = [
            RightPanelRow(
                title: "Reset zoom",
                subtitle: "Currently \(zoomPercent)%",
                meta: "Appearance",
                action: { [weak self] in
                    ZoomManager.shared.resetZoom()
                    self?.loadSettingsPanel()
                }
            ),
            RightPanelRow(
                title: "Reconnect",
                subtitle: webService?.isWebSocketConnected == true
                    ? "Connected"
                    : "Reconnecting…",
                meta: "Connection",
                action: { [weak self] in
                    self?.webService?.reconnectIfNeeded()
                    self?.loadSettingsPanel()
                }
            ),
            RightPanelRow(
                title: "Account",
                subtitle: username,
                meta: server,
                action: nil
            ),
            RightPanelRow(
                title: "Desktop notifications",
                subtitle: desktopNotificationModeLabel(),
                meta: "Change",
                action: { [weak self] in self?.cycleDesktopNotificationMode() }
            ),
            RightPanelRow(
                title: "Notification sound",
                subtitle: desktopSoundsEnabled() ? "On" : "Off",
                meta: "Toggle",
                action: { [weak self] in self?.toggleDesktopNotificationSound() }
            ),
            RightPanelRow(
                title: loadRemoteImagesAutomatically ? "Disable automatic remote images" : "Enable automatic remote images",
                subtitle: "When off, inline/Giphy images are not fetched from third-party hosts",
                meta: "Privacy",
                action: { [weak self] in
                    guard let self = self else { return }
                    self.loadRemoteImagesAutomatically.toggle()
                    UserDefaults.standard.set(
                        self.loadRemoteImagesAutomatically,
                        forKey: "loadRemoteImagesAutomatically"
                    )
                    self.rebuildTimelineContent(scrollToBottom: false)
                    self.loadSettingsPanel()
                }
            ),
            RightPanelRow(
                title: "Export diagnostics",
                subtitle: "Redacted log and build information for support",
                meta: "Support",
                action: { [weak self] in
                    self?.exportDiagnostics()
                }
            ),
            RightPanelRow(
                title: "Log out",
                subtitle: "Clear credentials and return to sign in",
                meta: "",
                action: {
                    (NSApp.delegate as? AppDelegate)?.logout()
                }
            )
        ]
        renderRightPanel(empty: "", rows: rows)
    }

    func exportDiagnostics() {
        let defaults = UserDefaults.standard
        var log = (try? String(contentsOfFile: DebugLog.logPath, encoding: .utf8)) ?? ""
        let redactions = [
            defaults.string(forKey: "host") ?? "",
            defaults.string(forKey: "username") ?? "",
            KeychainHelper.get(forKey: "token") ?? ""
        ].filter { !$0.isEmpty }
        for secret in redactions {
            log = log.replacingOccurrences(of: secret, with: "<redacted>")
        }
        let header = [
            "mattermost.client diagnostics",
            "Build: \(AppVersion.windowTitle)",
            "macOS: \(ProcessInfo.processInfo.operatingSystemVersionString)",
            "Generated: \(ISO8601DateFormatter().string(from: Date()))",
            "",
            "--- log ---",
            log.isEmpty ? "(no log entries)" : log
        ].joined(separator: "\n")

        let panel = NSSavePanel()
        panel.nameFieldStringValue = "mattermost-client-diagnostics.txt"
        panel.canCreateDirectories = true
        panel.beginSheetModal(for: self) { [weak self] response in
            guard response == .OK, let url = panel.url else { return }
            do {
                try header.write(to: url, atomically: true, encoding: .utf8)
            } catch {
                self?.showInfoAlert("Could not export diagnostics: \(error.localizedDescription)")
            }
        }
    }

    func loadChannelInfo() {
        guard let ws = webService, ws.isLogged(),
              let channel = channelsById[activeChannelId] else {
            renderRightPanel(empty: L10n.string("No channel selected"), rows: [])
            return
        }
        let channelId = channel.id
        Task { @MainActor [weak self] in
            guard let self = self else { return }
            let members = (try? await ws.fetchChannelMembers(channelId: channelId, perPage: 200)) ?? []
            guard self.activeChannelId == channelId else { return }
            let memberCount = members.count >= 200 ? "200+" : "\(members.count)"
            self.channelMembersCountLabel.stringValue = memberCount
            self.layoutRightChatPanel()

            var creatorName = ""
            if let creatorId = channel.creator_id, !creatorId.isEmpty {
                if let creator = self.usersById[creatorId] {
                    creatorName = creator.username
                } else if let users = try? await ws.fetchUsersByIds([creatorId]),
                          let creator = users.first {
                    self.usersById[creator.id] = creator
                    self.usersByUsername[creator.username.lowercased()] = creator
                    creatorName = creator.username
                }
            }

            let typeLabel: String
            switch channel.type {
            case "P": typeLabel = "Private channel"
            case "D": typeLabel = "Direct message"
            case "G": typeLabel = "Group message"
            default: typeLabel = "Public channel"
            }
            let created = channel.create_at.map {
                Self.localizedDateTimeFormatter.string(from: Date(timeIntervalSince1970: TimeInterval($0) / 1000))
            } ?? "Unknown"
            let header = (channel.header ?? "").trimmingCharacters(in: .whitespacesAndNewlines)
            let purpose = (channel.purpose ?? "").trimmingCharacters(in: .whitespacesAndNewlines)
            let rows: [RightPanelRow] = [
                RightPanelRow(
                    title: self.channelDisplayName(for: channel),
                    subtitle: header.isEmpty ? "No channel header" : header,
                    meta: typeLabel,
                    action: nil
                ),
                RightPanelRow(
                    title: "Purpose",
                    subtitle: purpose.isEmpty ? "No purpose set" : purpose,
                    meta: "",
                    action: nil
                ),
                RightPanelRow(
                    title: "Members",
                    subtitle: "\(memberCount) member\(memberCount == "1" ? "" : "s")",
                    meta: "View",
                    action: { [weak self] in self?.showRightPanel(mode: .members) }
                ),
                RightPanelRow(
                    title: "Created",
                    subtitle: created,
                    meta: creatorName.isEmpty ? "" : "by \(creatorName)",
                    action: nil
                ),
                RightPanelRow(
                    title: "Files",
                    subtitle: "Files shared in this channel",
                    meta: "View",
                    action: { [weak self] in self?.showRightPanel(mode: .files) }
                ),
                RightPanelRow(
                    title: "Pinned Posts",
                    subtitle: "Messages pinned in this channel",
                    meta: "View",
                    action: { [weak self] in self?.showRightPanel(mode: .pinned) }
                )
            ]
            self.renderRightPanel(empty: "", rows: rows)
        }
    }

    func loadBrowseChannels() {
        guard let ws = webService, ws.isLogged(),
              let team = activeTeam else {
            renderRightPanel(empty: "Sign in to browse channels", rows: [])
            return
        }
        Task { @MainActor [weak self] in
            guard let self = self else { return }
            guard let channels = try? await ws.fetchPublicChannels(teamId: team.id) else {
                self.renderRightPanel(empty: "Could not load channels", rows: [])
                return
            }
            let joinedIds = Set(self.channelsById.keys)
            let rows = channels
                .filter { $0.type == "O" }
                .sorted { $0.display_name.localizedCaseInsensitiveCompare($1.display_name) == .orderedAscending }
                .map { channel -> RightPanelRow in
                    let isJoined = joinedIds.contains(channel.id)
                    let subtitle = (channel.purpose ?? channel.header ?? "").isEmpty
                        ? "Public channel" : (channel.purpose ?? channel.header ?? "")
                    return RightPanelRow(
                        title: channel.display_name,
                        subtitle: subtitle,
                        meta: isJoined ? "Joined" : "Click to join",
                        action: { [weak self] in
                            if isJoined {
                                self?.openChannel(withId: channel.id)
                                self?.closeRightPanel()
                            } else {
                                self?.joinChannel(channel)
                            }
                        }
                    )
                }
            self.renderRightPanel(empty: "No public channels", rows: rows)
        }
    }

    func joinChannel(_ channel: MMChannel) {
        guard let ws = webService, ws.isLogged(),
              let team = activeTeam else { return }
        let userId = currentUser?.id ?? ws.currentUserId
        guard !userId.isEmpty else { return }
        Task { @MainActor [weak self] in
            guard let self = self else { return }
            do {
                try await ws.joinChannel(channelId: channel.id, userId: userId)
                self.channelsById[channel.id] = channel
                self.channelsByName[channel.name.lowercased()] = channel
                self.channelsByName[channel.display_name.lowercased()] = channel
                if let categories = try? await ws.fetchSidebarCategories(teamId: team.id) {
                    self.populateSidebarCategories(from: categories, channels: Array(self.channelsById.values))
                }
                self.loadBrowseChannels()
            } catch {
                NSLog("Failed to join channel \(channel.name): \(error.localizedDescription)")
            }
        }
    }

    func hydrateUsers(_ ids: [String], completion: @escaping () -> Void) {
        let missing = Array(Set(ids).subtracting(usersById.keys))
        guard !missing.isEmpty, let ws = webService else {
            completion()
            return
        }
        Task { @MainActor in
            if let users = try? await ws.fetchUsersByIds(missing) {
                for user in users {
                    self.usersById[user.id] = user
                }
            }
            completion()
        }
    }

    func renderRightPanel(empty: String, rows: [RightPanelRow]) {
        let width = max(rightPanelScroll.bounds.width, rightPanel.bounds.width)
        rightPanelDoc.subviews.forEach { $0.removeFromSuperview() }

        var y: CGFloat = 8
        if rows.isEmpty {
            let label = NSTextField(labelWithString: empty)
            label.font = MMFont.font(ofSize: 13)
            label.textColor = Theme.shared.centerTextMuted
            label.alignment = .center
            label.isEditable = false
            label.isSelectable = false
            label.frame = NSRect(x: 12, y: 24, width: width - 24, height: 20)
            rightPanelDoc.addSubview(label)
            y = 56
        } else {
            for item in rows {
                let row = makeRightPanelRow(item, width: width - 24)
                row.frame = NSRect(x: 12, y: y, width: width - 24, height: 64)
                rightPanelDoc.addSubview(row)
                y += 68
            }
        }

        if rightPanelMode == .threads, !rows.isEmpty,
           threadItemsHasMore || threadItemsLoading {
            let footer = makeRightPanelFooter(
                title: threadItemsLoading ? "Loading more threads…" : "Load more threads",
                width: width - 24,
                action: threadItemsLoading ? nil : { [weak self] in self?.loadMoreThreads() }
            )
            footer.frame = NSRect(x: 12, y: y, width: width - 24, height: 32)
            rightPanelDoc.addSubview(footer)
            y += 38
        }

        rightPanelDoc.frame = NSRect(x: 0, y: 0, width: width, height: max(y, 1))
    }

    func makeRightPanelFooter(title: String, width: CGFloat, action: (() -> Void)?) -> RoundedEdgePanel {
        let row = RoundedEdgePanel()
        row.cornerRadius = MMRadius.menu
        row.color = .clear
        let label = NSTextField(labelWithString: title)
        label.font = MMFont.font(ofSize: 12, weight: .semibold)
        label.textColor = action == nil ? Theme.shared.centerTextMuted : Theme.shared.buttonBg
        label.alignment = .center
        label.isEditable = false
        label.isSelectable = false
        label.frame = NSRect(x: 8, y: 7, width: max(40, width - 16), height: 18)
        row.addSubview(label)
        if let action = action {
            row.onClick = action
            row.onHoverChanged = { [weak row] isHovered in
                row?.color = isHovered ? Theme.shared.centerHover : .clear
                row?.setNeedsAppearanceUpdate()
            }
        }
        row.accessibilityTitle = title
        return row
    }

    func makeRightPanelRow(_ item: RightPanelRow, width: CGFloat) -> RoundedEdgePanel {
        let row = RoundedEdgePanel()
        row.cornerRadius = MMRadius.menu
        row.color = .clear

        let title = NSTextField(labelWithString: item.title)
        title.font = MMFont.font(ofSize: 13, weight: .semibold)
        title.textColor = Theme.shared.centerText
        title.lineBreakMode = .byTruncatingTail
        title.isEditable = false
        title.isSelectable = false
        title.frame = NSRect(x: 10, y: 40, width: width - 20, height: 18)
        row.addSubview(title)

        if !item.subtitle.isEmpty {
            let subtitle = NSTextField(labelWithString: item.subtitle)
            subtitle.font = MMFont.font(ofSize: 12)
            subtitle.textColor = Theme.shared.centerTextMuted
            subtitle.lineBreakMode = .byTruncatingTail
            subtitle.isEditable = false
            subtitle.isSelectable = false
            subtitle.frame = NSRect(x: 10, y: 22, width: width - 20, height: 16)
            row.addSubview(subtitle)
        }

        if !item.meta.isEmpty {
            let meta = NSTextField(labelWithString: item.meta)
            meta.font = MMFont.font(ofSize: 11)
            meta.textColor = Theme.shared.centerText.withAlphaComponent(0.64)
            meta.isEditable = false
            meta.isSelectable = false
            meta.frame = NSRect(x: 10, y: 6, width: width - 20, height: 14)
            row.addSubview(meta)
        }

        row.onHoverChanged = { [weak row] isHovered in
            row?.color = isHovered
                ? Theme.shared.centerHover
                : .clear
            row?.setNeedsAppearanceUpdate()
        }
        if let action = item.action {
            row.onClick = action
        }
        return row
    }
}
