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
        rightPanel.addSubview(rightPanelScroll)

        threadReplyPanel.color = Theme.shared.centerBg
        threadReplyPanel.cornerRadius = MMRadius.control
        threadReplyPanel.borderWidth = 1
        threadReplyPanel.borderColor = dividerColor
        threadReplyPanel.isHidden = true

        threadReplyField.placeholderString = "Reply to thread…"
        threadReplyField.font = MMFont.font(ofSize: 13)
        threadReplyField.textColor = Theme.shared.centerText
        threadReplyField.isBordered = false
        threadReplyField.drawsBackground = false
        threadReplyField.focusRingType = .none
        threadReplyField.target = self
        threadReplyField.action = #selector(sendThreadReply)
        threadReplyField.delegate = self
        threadReplyPanel.addSubview(threadReplyField)

        threadPlaceholderLabel.font = MMFont.font(ofSize: 13)
        threadPlaceholderLabel.textColor = Theme.shared.centerTextPlaceholder
        threadPlaceholderLabel.isEditable = false
        threadPlaceholderLabel.isSelectable = false
        threadReplyPanel.addSubview(threadPlaceholderLabel, positioned: .below, relativeTo: threadReplyField)

        threadSendButton.color = Theme.shared.buttonBg
        threadSendButton.cornerRadius = MMRadius.control
        let sendIcon = NSImageView()
        if let image = NSImage(systemSymbolName: "paperplane.fill", accessibilityDescription: "Send reply") {
            sendIcon.image = image.withSymbolConfiguration(.init(pointSize: 12, weight: .semibold))
            sendIcon.contentTintColor = .white
        }
        sendIcon.frame = NSRect(x: 6, y: 6, width: 14, height: 14)
        threadSendButton.addSubview(sendIcon)
        threadSendButton.onClick = { [weak self] in
            self?.sendThreadReply()
        }
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
            rightPanelTitle.stringValue = "Threads"
            loadThreads()
        case .members:
            rightPanelTitle.stringValue = "Members"
            loadChannelMembers()
        case .pinned:
            rightPanelTitle.stringValue = "Pinned Posts"
            loadPinnedPosts()
        case .mentions:
            rightPanelTitle.stringValue = "Recent Mentions"
            loadMentions()
        case .saved:
            rightPanelTitle.stringValue = "Saved Posts"
            loadSavedPosts()
        case .settings:
            rightPanelTitle.stringValue = "Settings"
            loadSettingsPanel()
        case .browse:
            rightPanelTitle.stringValue = "Browse Channels"
            loadBrowseChannels()
        case .thread:
            rightPanelTitle.stringValue = "Thread"
            loadThread()
        case .files:
            rightPanelTitle.stringValue = "Files"
            loadChannelFiles()
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
        isRightPanelVisible = false
        rightPanel.isHidden = true
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
        }
    }

    func loadThreads() {
        guard let ws = webService, ws.isLogged(),
              let team = activeTeam else {
            renderRightPanel(empty: "Sign in to see your threads", rows: [])
            return
        }
        let userId = currentUser?.id ?? ws.currentUserId
        guard !userId.isEmpty else {
            renderRightPanel(empty: "Sign in to see your threads", rows: [])
            return
        }
        Task { @MainActor [weak self] in
            guard let self = self else { return }
            guard let threads = try? await ws.fetchThreads(userId: userId, teamId: team.id) else {
                self.renderRightPanel(empty: "Could not load threads", rows: [])
                return
            }
            self.threadItems = threads
            let authorIds = threads.compactMap { $0.post?.user_id }
            self.hydrateUsers(authorIds) { [weak self] in
                guard let self = self else { return }
                let rows = threads.compactMap { thread -> RightPanelRow? in
                    guard let post = thread.post else { return nil }
                    let author = self.usersById[post.user_id]?.username ?? "Unknown"
                    let channelName = self.channelsById[post.channel_id].map { self.channelDisplayName(for: $0) } ?? ""
                    let snippet = post.message.replacingOccurrences(of: "\n", with: " ")
                    let replies = thread.reply_count ?? 0
                    return RightPanelRow(
                        title: snippet.isEmpty ? "(attachment)" : snippet,
                        subtitle: [author, channelName].filter { !$0.isEmpty }.joined(separator: " · "),
                        meta: "\(replies) repl\(replies == 1 ? "y" : "ies")",
                        action: { [weak self] in
                            guard let self = self else { return }
                            self.pendingJumpPostId = post.id
                            self.openChannel(withId: post.channel_id)
                            self.closeRightPanel()
                        }
                    )
                }
                self.renderRightPanel(empty: "No threads yet", rows: rows)
            }
        }
    }

    func showThread(for post: MMPost) {
        let root = (post.root_id?.isEmpty == false) ? post.root_id! : post.id
        threadRootId = root
        threadPosts = [post]
        rightPanelMode = .thread
        isRightPanelVisible = true
        rightPanel.isHidden = false
        rightPanelTitle.stringValue = "Thread"
        rightPanelSubtitle.stringValue = channelsById[activeChannelId].map { channelDisplayName(for: $0) } ?? ""
        layoutRightChatPanel()
        loadThread()
    }

    func loadThread() {
        guard let ws = webService, ws.isLogged(),
              !threadRootId.isEmpty else {
            renderThreadPanel(empty: "Could not load thread")
            return
        }
        let rootId = threadRootId
        Task { @MainActor [weak self] in
            guard let self = self else { return }
            guard let list = try? await ws.fetchPostThread(postId: rootId) else {
                self.renderThreadPanel(empty: "Could not load thread")
                return
            }
            let posts = list.order.compactMap { list.posts[$0] }
            // The thread endpoint accepts any post in the thread; normalise the
            // reply target to the actual root post.
            if let root = posts.first(where: { ($0.root_id ?? "").isEmpty }) {
                self.threadRootId = root.id
            }
            self.threadPosts = posts
            self.hydrateUsers(posts.map { $0.user_id }) {
                self.renderThreadPanel()
            }
        }
    }

    func renderThreadPanel(empty: String? = nil) {
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
        var y: CGFloat = 8
        var lastUserId: String?
        var lastTimestamp: Int64 = 0
        var replyHeaderAdded = false

        for post in threadPosts {
            let isReply = post.id != rootId
            if isReply && !replyHeaderAdded {
                replyHeaderAdded = true
                let replyCount = max(0, threadPosts.count - 1)
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
        rightPanelScroll.contentView.scroll(to: .zero)
        rightPanelScroll.reflectScrolledClipView(rightPanelScroll.contentView)
    }

    @objc func sendThreadReply() {
        guard let ws = webService, ws.isLogged(),
              !threadRootId.isEmpty else { return }
        let text = threadReplyField.stringValue.trimmingCharacters(in: .whitespacesAndNewlines)
        guard !text.isEmpty else { return }
        let channelId = threadPosts.first(where: { $0.id == threadRootId })?.channel_id ?? activeChannelId
        let rootId = threadRootId
        threadReplyField.stringValue = ""
        threadPlaceholderLabel.isHidden = false
        Task { @MainActor [weak self] in
            guard let self = self else { return }
            do {
                try await ws.createPost(channelId: channelId, message: text, rootId: rootId)
                self.loadThread()
            } catch {
                NSLog("Thread reply failed: \(error.localizedDescription)")
                self.threadReplyField.stringValue = text
                self.threadPlaceholderLabel.isHidden = true
            }
        }
    }

    func loadChannelMembers() {
        guard let ws = webService, ws.isLogged(),
              !activeChannelId.isEmpty else {
            renderRightPanel(empty: "No channel selected", rows: [])
            return
        }
        let channelId = activeChannelId
        Task { @MainActor [weak self] in
            guard let self = self else { return }
            guard let members = try? await ws.fetchChannelMembers(channelId: channelId) else {
                self.renderRightPanel(empty: "Could not load members", rows: [])
                return
            }
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
                self.renderRightPanel(empty: "No members", rows: rows)
            }
        }
    }

    func loadPinnedPosts() {
        guard let ws = webService, ws.isLogged(),
              !activeChannelId.isEmpty else {
            renderRightPanel(empty: "No channel selected", rows: [])
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
                self.renderFilesPanel(files, empty: "No files yet")
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
            let thumbFrame = NSRect(x: 12, y: 12, width: 40, height: 40)
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
                    self?.showLightbox(image: thumbImage, file: file, filename: file.name ?? "Image")
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
        rightPanelDoc.frame = NSRect(x: 0, y: 0, width: width, height: max(y, 1))
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
