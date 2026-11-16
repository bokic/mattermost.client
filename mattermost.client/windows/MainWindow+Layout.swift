//
//  MainWindow+Layout.swift
//  mattermost.client
//
//  Split from MainWindow.swift.
//

import AppKit
import Foundation
import UniformTypeIdentifiers

extension MainWindow {

    func setupRightChatPanel() {
        let darkText = Theme.shared.centerText
        let mutedText = Theme.shared.centerTextMuted
        let dividerColor = Theme.shared.divider
        let hoverBg = Theme.shared.centerHover
        let brandBlue = Theme.shared.buttonBg
        let brandBlueHover = Theme.shared.buttonBg.blended(withFraction: 0.2, of: .black) ?? Theme.shared.buttonBg

        // 0. Timeline clipping container (clips messages & hero text to channelHeaderBorder below star icon)
        chatTimelineContainer.wantsLayer = true
        chatTimelineContainer.layer?.masksToBounds = true
        chatPanel.addSubview(chatTimelineContainer, positioned: .below, relativeTo: chatEntryPanel)

        // 1. Channel Header Bar
        channelStarButton.cornerRadius = MMRadius.control
        channelStarButton.color = .clear
        if let starImg = NSImage(systemSymbolName: "star", accessibilityDescription: "Favorite") {
            channelStarIconView.image = starImg.withSymbolConfiguration(.init(pointSize: 12.5, weight: .medium))
            channelStarIconView.contentTintColor = mutedText
        }
        channelStarButton.addSubview(channelStarIconView)
        channelStarButton.onHoverChanged = { [weak self] isHovered in
            guard let self = self else { return }
            self.channelStarButton.color = isHovered ? hoverBg : .clear
            self.channelStarButton.setNeedsAppearanceUpdate()
            if !self.isChannelFavorited {
                self.channelStarIconView.contentTintColor = isHovered ? darkText : mutedText
            }
        }
        channelStarButton.onClick = { [weak self] in
            guard let self = self, !self.activeChannelId.isEmpty else { return }
            self.setChannelFavorite(!self.isChannelFavorited, channelId: self.activeChannelId)
        }
        chatPanel.addSubview(channelStarButton)

        channelTitleButton.cornerRadius = MMRadius.control
        channelTitleButton.color = .clear
        channelTitleLabel.font = MMFont.font(ofSize: 14, weight: .semibold)
        channelTitleLabel.textColor = darkText
        channelTitleLabel.isEditable = false
        channelTitleLabel.isSelectable = false
        channelTitleButton.addSubview(channelTitleLabel)

        channelHeaderBotBadge.cornerRadius = MMRadius.control
        channelHeaderBotBadge.color = Theme.shared.centerText.withAlphaComponent(0.12)
        channelHeaderBotBadgeLabel.font = MMFont.font(ofSize: 9.5, weight: .bold)
        channelHeaderBotBadgeLabel.textColor = Theme.shared.centerText.withAlphaComponent(0.75)
        channelHeaderBotBadgeLabel.alignment = .center
        channelHeaderBotBadgeLabel.isEditable = false
        channelHeaderBotBadgeLabel.isSelectable = false
        channelHeaderBotBadge.addSubview(channelHeaderBotBadgeLabel)
        channelHeaderBotBadge.isHidden = true
        channelTitleButton.addSubview(channelHeaderBotBadge)

        if let chevImg = NSImage(systemSymbolName: "chevron.down", accessibilityDescription: "Channel Menu") {
            channelTitleChevron.image = chevImg.withSymbolConfiguration(.init(pointSize: 9, weight: .bold))
            channelTitleChevron.contentTintColor = mutedText
        }
        channelTitleButton.addSubview(channelTitleChevron)
        channelTitleButton.onHoverChanged = { [weak self] isHovered in
            guard let self = self else { return }
            self.channelTitleButton.color = isHovered ? hoverBg : .clear
            self.channelTitleButton.setNeedsAppearanceUpdate()
            self.channelTitleChevron.contentTintColor = isHovered ? darkText : mutedText
        }
        channelTitleButton.onClick = { [weak self] in
            self?.toggleChannelMenu()
        }
        channelTitleButton.accessibilityTitle = L10n.string("Channel Menu")
        channelTitleButton.accessibilityHelp = "Open channel menu"
        channelTitleButton.accessibilityRoleOverride = .button
        chatPanel.addSubview(channelTitleButton)

        channelMembersButton.cornerRadius = MMRadius.control
        channelMembersButton.color = .clear
        channelMembersButton.accessibilityTitle = L10n.string("Channel Members")
        channelMembersButton.accessibilityHelp = "View and manage channel members"
        channelMembersButton.accessibilityRoleOverride = .button
        if let personImg = NSImage(systemSymbolName: "person", accessibilityDescription: "Members") {
            channelMembersIconView.image = personImg.withSymbolConfiguration(.init(pointSize: 12, weight: .medium))
            channelMembersIconView.contentTintColor = mutedText
        }
        channelMembersCountLabel.font = MMFont.font(ofSize: 12, weight: .semibold)
        channelMembersCountLabel.textColor = mutedText
        channelMembersCountLabel.isEditable = false
        channelMembersCountLabel.isSelectable = false
        channelMembersButton.addSubview(channelMembersIconView)
        channelMembersButton.addSubview(channelMembersCountLabel)
        channelMembersButton.onHoverChanged = { [weak self] isHovered in
            guard let self = self else { return }
            self.channelMembersButton.color = isHovered ? hoverBg : .clear
            self.channelMembersButton.setNeedsAppearanceUpdate()
            self.channelMembersIconView.contentTintColor = isHovered ? darkText : mutedText
            self.channelMembersCountLabel.textColor = isHovered ? darkText : mutedText
        }
        channelMembersButton.onClick = { [weak self] in
            self?.toggleRightPanel(mode: .members)
        }
        chatPanel.addSubview(channelMembersButton)

        channelPinsButton.cornerRadius = MMRadius.control
        channelPinsButton.color = .clear
        channelPinsButton.accessibilityTitle = L10n.string("Pinned Posts")
        channelPinsButton.accessibilityHelp = "View pinned messages"
        channelPinsButton.accessibilityRoleOverride = .button
        if let pinImg = NSImage(systemSymbolName: "pin", accessibilityDescription: "Pinned Messages") {
            channelPinsIconView.image = pinImg.withSymbolConfiguration(.init(pointSize: 11, weight: .medium))
            channelPinsIconView.contentTintColor = mutedText
        }
        channelPinsButton.addSubview(channelPinsIconView)
        channelPinsButton.onHoverChanged = { [weak self] isHovered in
            guard let self = self else { return }
            self.channelPinsButton.color = isHovered ? hoverBg : .clear
            self.channelPinsButton.setNeedsAppearanceUpdate()
            self.channelPinsIconView.contentTintColor = isHovered ? darkText : mutedText
        }
        channelPinsButton.onClick = { [weak self] in
            self?.toggleRightPanel(mode: .pinned)
        }
        chatPanel.addSubview(channelPinsButton)

        channelFilesButton.cornerRadius = MMRadius.control
        channelFilesButton.color = .clear
        channelFilesButton.accessibilityTitle = L10n.string("Files")
        channelFilesButton.accessibilityHelp = "View files shared in this channel"
        channelFilesButton.accessibilityRoleOverride = .button
        if let filesImg = NSImage(systemSymbolName: "doc.text", accessibilityDescription: "Channel files") {
            channelFilesIconView.image = filesImg.withSymbolConfiguration(.init(pointSize: 12, weight: .regular))
            channelFilesIconView.contentTintColor = mutedText
        }
        channelFilesButton.addSubview(channelFilesIconView)
        channelFilesButton.onHoverChanged = { [weak self] isHovered in
            guard let self = self else { return }
            self.channelFilesButton.color = isHovered ? hoverBg : .clear
            self.channelFilesButton.setNeedsAppearanceUpdate()
            self.channelFilesIconView.contentTintColor = isHovered ? darkText : mutedText
        }
        channelFilesButton.onClick = { [weak self] in
            self?.toggleRightPanel(mode: .files)
        }
        chatPanel.addSubview(channelFilesButton)

        channelSidebarButton.cornerRadius = MMRadius.control
        channelSidebarButton.color = .clear
        channelSidebarButton.accessibilityTitle = L10n.string("Threads")
        channelSidebarButton.accessibilityHelp = "Toggle threads right panel"
        channelSidebarButton.accessibilityRoleOverride = .button
        if let sideImg = NSImage(systemSymbolName: "sidebar.right", accessibilityDescription: "Channel Sidebar") {
            channelSidebarIconView.image = sideImg.withSymbolConfiguration(.init(pointSize: 13.5, weight: .regular))
            channelSidebarIconView.contentTintColor = mutedText
        }
        channelSidebarButton.addSubview(channelSidebarIconView)
        channelSidebarButton.onHoverChanged = { [weak self] isHovered in
            guard let self = self else { return }
            self.channelSidebarButton.color = isHovered ? hoverBg : .clear
            self.channelSidebarButton.setNeedsAppearanceUpdate()
            self.channelSidebarIconView.contentTintColor = isHovered ? darkText : mutedText
        }
        channelSidebarButton.onClick = { [weak self] in
            self?.toggleRightPanel(mode: .threads)
        }
        chatPanel.addSubview(channelSidebarButton)

        channelInfoButton.cornerRadius = MMRadius.control
        channelInfoButton.color = .clear
        channelInfoButton.accessibilityTitle = L10n.string("Channel Info")
        channelInfoButton.accessibilityHelp = "View channel details"
        channelInfoButton.accessibilityRoleOverride = .button
        if let infoImg = NSImage(systemSymbolName: "info.circle", accessibilityDescription: "View Info") {
            channelInfoIconView.image = infoImg.withSymbolConfiguration(.init(pointSize: 13.5, weight: .medium))
            channelInfoIconView.contentTintColor = mutedText
        }
        channelInfoButton.addSubview(channelInfoIconView)
        channelInfoButton.onHoverChanged = { [weak self] isHovered in
            guard let self = self else { return }
            self.channelInfoButton.color = isHovered ? hoverBg : .clear
            self.channelInfoButton.setNeedsAppearanceUpdate()
            self.channelInfoIconView.contentTintColor = isHovered ? darkText : mutedText
        }
        channelInfoButton.onClick = { [weak self] in
            self?.toggleRightPanel(mode: .channelInfo)
        }
        chatPanel.addSubview(channelInfoButton)

        // 2. Welcome Hero Section (Illustration + Title + Subtitle + Invite button)
        timelineHeroContainer.cornerRadius = 0
        timelineHeroContainer.color = .clear

        heroIllustrationCircle.cornerRadius = 38
        heroIllustrationCircle.color = Theme.shared.centerHover
        timelineHeroContainer.addSubview(heroIllustrationCircle)

        heroBotAvatarView.imageScaling = .scaleProportionallyUpOrDown
        heroBotAvatarView.isHidden = true
        heroIllustrationCircle.addSubview(heroBotAvatarView)

        heroWhiteBubble.cornerRadius = MMRadius.control
        heroWhiteBubble.borderWidth = 1.5
        heroWhiteBubble.color = Theme.shared.centerTextPlaceholder
        for i in 0..<3 {
            let line = RoundedEdgePanel()
            line.cornerRadius = 1
            line.color = Theme.shared.centerTextPlaceholder
            let w: CGFloat = (i == 2) ? 20 : 32
            line.frame = NSRect(x: 9, y: CGFloat(24 - i * 7), width: w, height: 2)
            heroWhiteBubble.addSubview(line)
        }
        timelineHeroContainer.addSubview(heroWhiteBubble)

        heroBlueBubble.cornerRadius = MMRadius.control
        heroBlueBubble.color = brandBlue
        for i in 0..<2 {
            let line = RoundedEdgePanel()
            line.cornerRadius = 1
            line.color = .white
            let w: CGFloat = (i == 1) ? 16 : 24
            line.frame = NSRect(x: 8, y: CGFloat(15 - i * 6), width: w, height: 2)
            heroBlueBubble.addSubview(line)
        }
        timelineHeroContainer.addSubview(heroBlueBubble)

        heroTitleLabel.font = MMFont.font(ofSize: 22, weight: .bold)
        heroTitleLabel.textColor = darkText
        heroTitleLabel.alignment = .center
        heroTitleLabel.isEditable = false
        heroTitleLabel.isSelectable = false
        timelineHeroContainer.addSubview(heroTitleLabel)

        heroBotBadge.cornerRadius = MMRadius.control
        heroBotBadge.color = Theme.shared.centerText.withAlphaComponent(0.12)
        heroBotBadgeLabel.font = MMFont.font(ofSize: 10, weight: .bold)
        heroBotBadgeLabel.textColor = Theme.shared.centerText.withAlphaComponent(0.75)
        heroBotBadgeLabel.alignment = .center
        heroBotBadgeLabel.isEditable = false
        heroBotBadgeLabel.isSelectable = false
        heroBotBadge.addSubview(heroBotBadgeLabel)
        heroBotBadge.isHidden = true
        timelineHeroContainer.addSubview(heroBotBadge)

        heroDescriptionLabel.font = MMFont.font(ofSize: 12)
        heroDescriptionLabel.textColor = mutedText
        heroDescriptionLabel.alignment = .center
        heroDescriptionLabel.maximumNumberOfLines = 2
        heroDescriptionLabel.lineBreakMode = .byWordWrapping
        heroDescriptionLabel.cell?.wraps = true
        heroDescriptionLabel.cell?.isScrollable = false
        heroDescriptionLabel.isEditable = false
        heroDescriptionLabel.isSelectable = false
        timelineHeroContainer.addSubview(heroDescriptionLabel)

        heroInviteButton.cornerRadius = MMRadius.control
        heroInviteButton.color = brandBlue
        if let invImg = NSImage(systemSymbolName: "person.badge.plus", accessibilityDescription: "Invite") {
            heroInviteIconView.image = invImg.withSymbolConfiguration(.init(pointSize: 12, weight: .semibold))
            heroInviteIconView.contentTintColor = .white
        }
        heroInviteIconView.frame = NSRect(x: 14, y: 8, width: 16, height: 16)
        heroInviteButton.addSubview(heroInviteIconView)

        heroInviteLabel.font = MMFont.font(ofSize: 12, weight: .semibold)
        heroInviteLabel.textColor = .white
        heroInviteLabel.isEditable = false
        heroInviteLabel.isSelectable = false
        heroInviteLabel.frame = NSRect(x: 34, y: 7, width: 154, height: 17)
        heroInviteButton.addSubview(heroInviteLabel)
        heroInviteButton.onHoverChanged = { [weak self] isHovered in
            guard let self = self else { return }
            self.heroInviteButton.color = isHovered ? brandBlueHover : brandBlue
            self.heroInviteButton.setNeedsAppearanceUpdate()
        }
        heroInviteButton.onClick = { [weak self] in
            self?.showInviteDialog()
        }
        timelineHeroContainer.addSubview(heroInviteButton)

        // 2. Timeline Scroll View & Dynamic Document View
        timelineScrollView.drawsBackground = false
        timelineScrollView.hasVerticalScroller = true
        timelineScrollView.hasHorizontalScroller = false
        timelineScrollView.autohidesScrollers = true
        timelineScrollView.documentView = timelineDocView
        chatTimelineContainer.addSubview(timelineScrollView)

        timelineScrollView.contentView.postsBoundsChangedNotifications = true
        NotificationCenter.default.addObserver(
            self,
            selector: #selector(timelineBoundsDidChange(_:)),
            name: NSView.boundsDidChangeNotification,
            object: timelineScrollView.contentView
        )
        timelineScrollView.onScrollWheel = { [weak self] in
            guard let self = self else { return }
            self.newMessagesDividerArmed = true
            self.updateTimelineHoverState()
            self.updateNewMessagesDividerState()
        }

        // 4. Message Composer (Non-editable placeholder + Formatting Toolbar + Help link)
        // The editor draws its own placeholder; keep the label only as the
        // canonical string source and never put it in the hit-test path.
        composerPlaceholderLabel.font = MMFont.font(ofSize: 14)
        composerPlaceholderLabel.textColor = Theme.shared.centerTextPlaceholder
        composerPlaceholderLabel.isEditable = false
        composerPlaceholderLabel.isSelectable = false
        composerPlaceholderLabel.isHidden = true

        composerLeftButtons.removeAll()
        let formatDescriptors: [(symbol: String, title: String, help: String)] = [
            ("bold", "Bold", "Format selection as bold"),
            ("italic", "Italic", "Format selection as italic"),
            ("strikethrough", "Strikethrough", "Format selection as strikethrough"),
            ("number", "Heading", "Format selection as heading"),
            ("link", "Link", "Insert markdown link"),
            ("chevron.left.forwardslash.chevron.right", "Code", "Format selection as code block"),
            ("text.quote", "Quote", "Format selection as quote"),
            ("list.bullet", "Bulleted List", "Insert bulleted list"),
            ("list.number", "Numbered List", "Insert numbered list"),
            ("info.circle", "Formatting Help", "Show markdown formatting help"),
        ]
        for desc in formatDescriptors {
            let btn = RoundedEdgePanel()
            btn.cornerRadius = MMRadius.control
            btn.color = .clear
            btn.accessibilityTitle = desc.title
            btn.accessibilityHelp = desc.help
            btn.accessibilityRoleOverride = .button
            let icon = NSImageView()
            if let img = NSImage(systemSymbolName: desc.symbol, accessibilityDescription: desc.title) {
                icon.image = img.withSymbolConfiguration(.init(pointSize: 12, weight: .medium))
                icon.contentTintColor = mutedText
            }
            icon.frame = NSRect(x: 8, y: 8, width: 16, height: 16)
            btn.addSubview(icon)
            btn.onHoverChanged = { [weak btn, weak icon] isHovered in
                btn?.color = isHovered ? hoverBg : .clear
                btn?.setNeedsAppearanceUpdate()
                icon?.contentTintColor = isHovered ? darkText : mutedText
            }
            let symbol = desc.symbol
            btn.onClick = { [weak self] in
                self?.applyComposerFormat(symbol)
            }
            chatEntryPanel.addSubview(btn)
            composerLeftButtons.append(btn)
        }

        composerLeftSeparator.cornerRadius = 0
        composerLeftSeparator.color = dividerColor
        chatEntryPanel.addSubview(composerLeftSeparator)

        // Right composer toolbar controls: "Aa ^" | sep | Emoji | Paperclip | Send
        composerAaButton.cornerRadius = MMRadius.control
        composerAaButton.color = .clear
        let aaLabel = NSTextField(labelWithString: "Aa")
        let aaFont = MMFont.font(ofSize: 14, weight: .semibold)
        aaLabel.font = aaFont
        aaLabel.textColor = mutedText
        aaLabel.isEditable = false
        aaLabel.isSelectable = false
        let aaSize = ("Aa" as NSString).size(withAttributes: [.font: aaFont])
        let aaTextW = ceil(aaSize.width) + 2
        let aaTextH = ceil(aaSize.height)
        aaLabel.frame = NSRect(x: 6, y: (32 - aaTextH) / 2, width: aaTextW, height: aaTextH)
        composerAaButton.addSubview(aaLabel)
        if let cImg = NSImage(systemSymbolName: "chevron.down", accessibilityDescription: "Formatting") {
            composerAaChevron.image = cImg.withSymbolConfiguration(.init(pointSize: 8, weight: .bold))
            composerAaChevron.contentTintColor = mutedText
        }
        composerAaChevron.frame = NSRect(x: 6 + aaTextW + 3, y: (32 - 9) / 2, width: 9, height: 9)
        composerAaButton.addSubview(composerAaChevron)
        composerAaButton.onHoverChanged = { [weak self, weak aaLabel] isHovered in
            self?.composerAaButton.color = isHovered ? hoverBg : .clear
            self?.composerAaButton.setNeedsAppearanceUpdate()
            aaLabel?.textColor = isHovered ? darkText : mutedText
            self?.composerAaChevron.contentTintColor = isHovered ? darkText : mutedText
        }
        composerAaButton.onClick = { [weak self] in
            self?.toggleComposerToolbar()
        }
        composerAaButton.accessibilityTitle = L10n.string("Toggle formatting toolbar")
        composerAaButton.accessibilityHelp = "Show or hide text formatting buttons"
        composerAaButton.accessibilityRoleOverride = .button
        chatEntryPanel.addSubview(composerAaButton)

        composerRightSeparator.cornerRadius = 0
        composerRightSeparator.color = dividerColor
        chatEntryPanel.addSubview(composerRightSeparator)

        let setupRightIconBtn: (RoundedEdgePanel, String) -> Void = { btn, sym in
            btn.cornerRadius = MMRadius.control
            btn.color = .clear
            btn.accessibilityRoleOverride = .button
            let icon = NSImageView()
            if let img = NSImage(systemSymbolName: sym, accessibilityDescription: sym) {
                icon.image = img.withSymbolConfiguration(.init(pointSize: 14, weight: .medium))
                icon.contentTintColor = mutedText
            }
            icon.frame = NSRect(x: 7, y: 7, width: 18, height: 18)
            btn.addSubview(icon)
            btn.onHoverChanged = { [weak btn, weak icon] isHovered in
                btn?.color = isHovered ? hoverBg : .clear
                btn?.setNeedsAppearanceUpdate()
                icon?.contentTintColor = isHovered ? darkText : mutedText
            }
            self.chatEntryPanel.addSubview(btn)
        }
        setupRightIconBtn(composerEmojiButton, "face.smiling")
        composerEmojiButton.accessibilityTitle = L10n.string("Emoji")
        composerEmojiButton.accessibilityHelp = L10n.string("Emoji")
        composerEmojiButton.accessibilityRoleOverride = .button
        composerEmojiButton.onClick = { [weak self] in
            self?.toggleEmojiPanel()
        }

        // GIF button in composer
        composerGifButton.cornerRadius = MMRadius.control
        composerGifButton.color = .clear
        composerGifButton.accessibilityTitle = "Add GIF"
        composerGifButton.accessibilityHelp = "Search and insert animated GIFs"
        composerGifButton.accessibilityRoleOverride = .button
        let gifLabel = NSTextField(labelWithString: "GIF")
        let gifFont = MMFont.font(ofSize: 11, weight: .bold)
        gifLabel.font = gifFont
        gifLabel.textColor = mutedText
        gifLabel.isEditable = false
        gifLabel.isSelectable = false
        gifLabel.alignment = .center
        gifLabel.frame = NSRect(x: 2, y: 5, width: 26, height: 16)
        composerGifButton.addSubview(gifLabel)
        composerGifButton.onHoverChanged = { [weak self, weak gifLabel] isHovered in
            self?.composerGifButton.color = .clear
            self?.composerGifButton.setNeedsAppearanceUpdate()
            gifLabel?.textColor = isHovered ? darkText : mutedText
        }
        // GIF search is not available yet; the button is hidden in
        // applyComposerToolbarVisibility() rather than inserting a fake post.
        chatEntryPanel.addSubview(composerGifButton)

        setupRightIconBtn(composerAttachButton, "paperclip")
        composerAttachButton.accessibilityTitle = L10n.string("Attach files")
        composerAttachButton.accessibilityHelp = L10n.string("Attach files")
        composerAttachButton.accessibilityRoleOverride = .button
        composerAttachButton.onClick = { [weak self] in
            self?.attachFiles()
        }

        composerSendButton.cornerRadius = MMRadius.control
        composerSendButton.color = Theme.shared.centerText.withAlphaComponent(0.08)
        composerSendButton.accessibilityRoleOverride = .button
        let sendIcon = NSImageView()
        if let sImg = NSImage(systemSymbolName: "paperplane.fill", accessibilityDescription: "Send") {
            sendIcon.image = sImg.withSymbolConfiguration(.init(pointSize: 15, weight: .regular))
            sendIcon.contentTintColor = Theme.shared.centerText.withAlphaComponent(0.32)
        }
        sendIcon.frame = NSRect(x: 15, y: 7, width: 18, height: 18)
        composerSendButton.addSubview(sendIcon)
        composerSendButton.accessibilityTitle = L10n.string("Send")
        composerSendButton.accessibilityHelp = L10n.string("Send")
        composerSendIconView = sendIcon
        composerSendButton.onHoverChanged = { [weak self] isHovered in
            guard let self = self else { return }
            if self.composerSendEnabled {
                self.composerSendButton.color = isHovered
                    ? Theme.shared.buttonBg.blended(withFraction: 0.2, of: .black) ?? Theme.shared.buttonBg
                    : Theme.shared.buttonBg
            } else {
                self.composerSendButton.color = Theme.shared.centerText.withAlphaComponent(0.08)
            }
            self.composerSendButton.setNeedsAppearanceUpdate()
        }
        composerSendButton.onClick = { [weak self] in
            self?.sendComposerMessage()
        }
        chatEntryPanel.addSubview(composerSendButton)

        composerHelpLabel.font = MMFont.font(ofSize: 12)
        composerHelpLabel.textColor = Theme.shared.centerText.withAlphaComponent(0.75)
        composerHelpLabel.alignment = .right
        composerHelpLabel.isEditable = false
        composerHelpLabel.isSelectable = false
        chatPanel.addSubview(composerHelpLabel)

        connectionBanner.color = Theme.shared.mentionHighlightBg.withAlphaComponent(0.98)
        connectionBanner.cornerRadius = 0
        connectionBanner.isHidden = true
        connectionLabel.font = MMFont.font(ofSize: 12, weight: .semibold)
        connectionLabel.textColor = Theme.shared.mentionHighlightLink
        connectionLabel.alignment = .center
        connectionLabel.isEditable = false
        connectionLabel.isSelectable = false
        connectionBanner.addSubview(connectionLabel)
        chatPanel.addSubview(connectionBanner)

        applyComposerToolbarVisibility()
        updateComposerSendState()
        setupRightPanel()
        setupEmojiPanel()
        setupPostInteractionPanels()
        setupLightbox()
        setupNewMessagesPill()
        setupChannelMenu()
        setupDMPicker()
        setupProfilePopover()
        rebuildTimelineContent(scrollToBottom: true)
    }

    func layoutRightChatPanel() {
        let chatW = chatPanel.bounds.width
        let chatH = chatPanel.bounds.height
        let headerH: CGFloat = 56
        let headerY = chatH - headerH

        connectionBanner.frame = NSRect(x: 0, y: headerY - 26, width: chatW, height: 26)
        connectionLabel.frame = NSRect(x: 12, y: 4, width: max(0, chatW - 24), height: 18)

        if isRightPanelVisible {
            let composerArea: CGFloat = 24 + composerTotalHeight + 8
            let maxPanelWidth = max(280, chatW - 360)
            let panelWidth = min(max(MMMetric.rightPanelMinWidth, rightPanelWidth), maxPanelWidth)
            let panelHeight = max(0, chatH - headerH - composerArea)
            rightPanel.frame = NSRect(x: chatW - panelWidth, y: composerArea, width: panelWidth, height: panelHeight)

            let titleFont = rightPanelTitle.font ?? MMFont.font(ofSize: 16, weight: .semibold)
            let titleWidth = min(
                ceil((rightPanelTitle.stringValue as NSString).size(withAttributes: [.font: titleFont]).width) + 2,
                panelWidth - 100
            )
            rightPanelTitle.frame = NSRect(x: 16, y: panelHeight - 40, width: titleWidth, height: 24)
            rightPanelSubtitle.frame = NSRect(
                x: 16 + titleWidth + 8,
                y: panelHeight - 38,
                width: max(0, panelWidth - titleWidth - 100),
                height: 20
            )
            rightPanelCloseButton.frame = NSRect(x: panelWidth - 48, y: panelHeight - 44, width: MMMetric.iconButtonRegular, height: MMMetric.iconButtonRegular)
            rightPanelResizeHandle.frame = NSRect(x: 0, y: 0, width: 6, height: panelHeight)

            let isThreadMode = (rightPanelMode == .thread)
            let isMembersMode = (rightPanelMode == .members)
            let isFilesMode = (rightPanelMode == .files)
            let replyBarHeight: CGFloat = isThreadMode ? threadComposerHeight : 0
            let listSearchHeight: CGFloat = (isMembersMode || isFilesMode) ? 34 : 0
            memberSearchField.isHidden = !isMembersMode
            if isMembersMode {
                memberSearchField.frame = NSRect(
                    x: 16,
                    y: panelHeight - 56 - 30,
                    width: max(80, panelWidth - 32),
                    height: 24
                )
            }
            filesSearchField.isHidden = !isFilesMode
            if isFilesMode {
                filesSearchField.frame = NSRect(
                    x: 16,
                    y: panelHeight - 56 - 30,
                    width: max(80, panelWidth - 32),
                    height: 24
                )
            }
            rightPanelScroll.frame = NSRect(
                x: 0,
                y: replyBarHeight,
                width: panelWidth,
                height: max(0, panelHeight - 56 - replyBarHeight - listSearchHeight)
            )
            if abs(panelWidth - lastRightPanelContentWidth) > 1 {
                lastRightPanelContentWidth = panelWidth
                DispatchQueue.main.async { [weak self] in
                    self?.reloadRightPanelIfNeeded()
                }
            }
            threadReplyPanel.isHidden = !isThreadMode
            if isThreadMode {
                let trayHeight = threadAttachmentTrayHeight
                threadReplyPanel.frame = NSRect(
                    x: 8,
                    y: 8,
                    width: panelWidth - 16,
                    height: threadComposerBaseHeight + trayHeight
                )
                let textWidth = max(120, panelWidth - 16 - 108)
                threadReplyScroll.frame = NSRect(x: 10, y: 36, width: textWidth, height: 48)
                threadReplyTextView.frame = NSRect(
                    origin: .zero,
                    size: NSSize(width: textWidth, height: 48)
                )
                threadAttachmentTray.frame = NSRect(
                    x: 8,
                    y: threadComposerBaseHeight + 2,
                    width: panelWidth - 16,
                    height: 26
                )
                threadAttachmentTray.isHidden = trayHeight == 0
                threadEmojiButton.frame = NSRect(x: panelWidth - 16 - 86, y: 48, width: 24, height: 24)
                threadAttachButton.frame = NSRect(x: panelWidth - 16 - 58, y: 48, width: 24, height: 24)
                threadSendButton.frame = NSRect(x: panelWidth - 16 - 30, y: 46, width: 26, height: 26)
                renderThreadAttachments()
            }
        }

        chatTimelineContainer.frame = NSRect(x: 0, y: 0, width: chatW, height: headerY)

        // 1. Channel Header Bar (web: 56pt tall, 12pt padding, 12pt top corners)
        channelStarButton.frame = NSRect(x: 14, y: headerY + 16, width: MMMetric.iconButtonCompact, height: MMMetric.iconButtonCompact)
        channelStarIconView.frame = NSRect(x: 4, y: 4, width: 16, height: 16)

        let isBot = isCurrentChannelBot()
        channelHeaderBotBadge.isHidden = !isBot

        let titleFont = channelTitleLabel.font ?? MMFont.font(ofSize: 14, weight: .bold)
        let titleStr = channelTitleLabel.stringValue.isEmpty ? "Town Square" : channelTitleLabel.stringValue
        let titleSize = (titleStr as NSString).size(withAttributes: [.font: titleFont])
        let titleTextW = min(max(ceil(titleSize.width) + 4, 40), max(chatW - 240, 100))
        let titleTextH = ceil(titleSize.height)

        let botBadgeW: CGFloat = isBot ? 32 : 0
        let botBadgeSpacing: CGFloat = isBot ? 6 : 0
        let titleBtnW = titleTextW + botBadgeSpacing + botBadgeW + 28
        let titleBtnH: CGFloat = 24
        channelTitleButton.frame = NSRect(x: 40, y: headerY + (headerH - titleBtnH) / 2, width: titleBtnW, height: titleBtnH)
        channelTitleLabel.frame = NSRect(x: 4, y: (titleBtnH - titleTextH) / 2, width: titleTextW, height: titleTextH)
        if isBot {
            channelHeaderBotBadge.frame = NSRect(x: 4 + titleTextW + 4, y: (titleBtnH - 16) / 2, width: 32, height: 16)
            channelHeaderBotBadgeLabel.frame = NSRect(x: 0, y: 1, width: 32, height: 14)
        }
        channelTitleChevron.frame = NSRect(x: 4 + titleTextW + 4 + (isBot ? (botBadgeW + botBadgeSpacing) : 0), y: (titleBtnH - 10) / 2, width: 10, height: 10)

        let membersX = channelTitleButton.frame.maxX + 2
        let countFont = channelMembersCountLabel.font ?? MMFont.font(ofSize: 12, weight: .semibold)
        let countStr = channelMembersCountLabel.stringValue.isEmpty ? "1" : channelMembersCountLabel.stringValue
        let countSize = (countStr as NSString).size(withAttributes: [.font: countFont])
        let countTextW = ceil(countSize.width) + 4
        let countTextH = ceil(countSize.height)
        let countBtnW = 6 + 12 + 4 + countTextW + 6
        let countBtnH: CGFloat = 24
        channelMembersButton.frame = NSRect(x: membersX, y: headerY + (headerH - countBtnH) / 2, width: max(34, countBtnW), height: countBtnH)
        channelMembersIconView.frame = NSRect(x: 6, y: (countBtnH - 12) / 2, width: 12, height: 12)
        channelMembersCountLabel.frame = NSRect(x: 22, y: (countBtnH - countTextH) / 2, width: countTextW, height: countTextH)

        channelPinsButton.frame = NSRect(x: channelMembersButton.frame.maxX + 4, y: headerY + 16, width: MMMetric.iconButtonCompact, height: MMMetric.iconButtonCompact)
        channelPinsIconView.frame = NSRect(x: 5, y: 5, width: 14, height: 14)

        channelFilesButton.frame = NSRect(x: channelPinsButton.frame.maxX + 4, y: headerY + 16, width: MMMetric.iconButtonCompact, height: MMMetric.iconButtonCompact)
        channelFilesIconView.frame = NSRect(x: 5, y: 5, width: 14, height: 14)

        // Web: 32pt icon buttons at the trailing edge, 4pt apart, 12pt from the right.
        channelInfoButton.frame = NSRect(x: chatW - 44, y: headerY + 12, width: MMMetric.iconButtonRegular, height: MMMetric.iconButtonRegular)
        channelInfoIconView.frame = NSRect(x: 7, y: 7, width: 18, height: 18)

        channelSidebarButton.frame = NSRect(x: chatW - 80, y: headerY + 12, width: MMMetric.iconButtonRegular, height: MMMetric.iconButtonRegular)
        channelSidebarIconView.frame = NSRect(x: 7, y: 7, width: 18, height: 18)

        // 2. Composer at bottom (web: 2pt border, 4pt radius, 50pt editor + 24pt footer)
        let composerW = max(chatW - 48, 200)
        let baseComposerH = composerBaseHeight
        let composerH = composerTotalHeight
        let composerBottom: CGFloat = 24
        chatEntryPanel.frame = NSRect(x: 24, y: composerBottom, width: composerW, height: composerH)
        if isComposerToolbarVisible {
            entryView.textContainerInset = NSSize(width: 0, height: 4)
            entryView.frame = NSRect(x: 14, y: 40, width: composerW - 28, height: 36)
        } else {
            entryView.textContainerInset = NSSize(width: 0, height: 13)
            entryView.frame = NSRect(x: 14, y: 0, width: max(120, composerW - 234), height: baseComposerH)
        }
        composerAttachmentTray.frame = NSRect(x: 8, y: baseComposerH + 2, width: composerW - 16, height: 28)
        composerHelpLabel.frame = NSRect(x: chatW - 24 - 180, y: 3, width: 180, height: 18)
        composerHelpLabel.alignment = .right

        let toolY: CGFloat = isComposerToolbarVisible ? 8 : (baseComposerH - 32) / 2

        var btnX: CGFloat = 8
        for (i, btn) in composerLeftButtons.enumerated() {
            if i == 3 {
                composerLeftSeparator.frame = NSRect(x: btnX + 3, y: toolY + 4, width: 1, height: 24)
                btnX += 9
            }
            btn.frame = NSRect(x: btnX, y: toolY, width: MMMetric.iconButtonRegular, height: MMMetric.iconButtonRegular)
            btnX += 34
        }

        composerSendButton.frame = NSRect(x: composerW - 9 - 48, y: toolY, width: 48, height: 32)
        composerEmojiButton.frame = NSRect(x: composerSendButton.frame.minX - 4 - MMMetric.iconButtonRegular, y: toolY, width: MMMetric.iconButtonRegular, height: MMMetric.iconButtonRegular)
        composerAttachButton.frame = NSRect(x: composerEmojiButton.frame.minX - 4 - MMMetric.iconButtonRegular, y: toolY, width: MMMetric.iconButtonRegular, height: MMMetric.iconButtonRegular)
        composerRightSeparator.frame = NSRect(x: composerAttachButton.frame.minX - 6, y: toolY + 4, width: 1, height: 24)

        let aaText = "Aa"
        let aaFont = composerAaButton.subviews.compactMap { ($0 as? NSTextField)?.font }.first ?? MMFont.font(ofSize: 14, weight: .semibold)
        let aaSize = (aaText as NSString).size(withAttributes: [.font: aaFont])
        let aaBtnW = max(44, ceil(aaSize.width) + 26)
        let aaX = composerRightSeparator.frame.minX - 4 - aaBtnW
        composerAaButton.frame = NSRect(x: aaX, y: toolY, width: aaBtnW, height: 32)
        composerGifButton.frame = NSRect(x: aaX - 36, y: toolY, width: MMMetric.iconButtonRegular, height: MMMetric.iconButtonRegular)

        // 3. Scrollable Timeline
        let composerTop = composerBottom + composerH
        let bannerHeight: CGFloat = connectionBanner.isHidden ? 0 : 26
        let scrollH = max(0, headerY - bannerHeight - composerTop)
        let timelineWidth = isRightPanelVisible ? rightPanel.frame.minX : chatW
        timelineScrollView.frame = NSRect(x: 0, y: composerTop, width: timelineWidth, height: scrollH)
        let listRight = isRightPanelVisible ? rightPanel.frame.minX : chatW
        newMessagesPill.frame = NSRect(
            x: 15,
            y: composerTop + 8,
            width: max(0, listRight - 30),
            height: 32
        )
        layoutNewMessagesPill()
        let wasNearBottom = (timelineScrollView.contentView.bounds.maxY >= (timelineDocView.frame.height - 40))
        if abs(timelineWidth - lastTimelineWidth) > 1 {
            lastTimelineWidth = timelineWidth
            rebuildTimelineContent(scrollToBottom: wasNearBottom)
        }
    }

    func updateViews() {
        let size = contentView?.bounds.size ?? NSSize(width: frame.width, height: frame.height)
        let topBarHeight: CGFloat = MMMetric.topBarHeight
        let topBarY = size.height - topBarHeight

        let gutter: CGFloat = MMMetric.panelGutter
        // Web: sidebar occupies 264pt starting 5pt from the window edge, then the
        // white channel card starts at 269pt; both share a 4pt gutter.
        let chatPanelX: CGFloat = MMMetric.chatPanelLeading
        mainPanel.frame = NSRect(x: gutter, y: gutter, width: size.width - gutter * 2, height: topBarY - gutter)
        mainPanel.cornerRadius = MMRadius.window
        chatPanel.frame = NSRect(x: chatPanelX, y: gutter, width: size.width - chatPanelX - gutter, height: topBarY - gutter)
        chatPanel.cornerRadius = MMRadius.window

        layoutLeftSidebar(topBarY: mainPanel.bounds.height)
        layoutRightChatPanel()
        if isLightboxVisible { layoutLightbox() }

        // Left: Product switcher container (grid icon, Mattermost logo, TEAM EDITION badge)
        let badgeText = editionBadgeLabel.stringValue.isEmpty ? "TEAM EDITION" : editionBadgeLabel.stringValue
        let badgeFont = editionBadgeLabel.font ?? MMFont.font(ofSize: 10, weight: .semibold)
        let badgeSize = (badgeText as NSString).size(withAttributes: [.font: badgeFont])
        let badgePadH: CGFloat = 6
        let badgeW = ceil(badgeSize.width) + (badgePadH * 2)
        let badgeH: CGFloat = 20
        let labelH: CGFloat = 14

        // Web: logo icon 20x20 at 5,3; wordmark 116x20 at 33,3 inside a 26pt tall button.
        boxImage.frame = NSRect(x: 5, y: 3, width: 20, height: 20)
        logo.frame = NSRect(x: 33, y: 3, width: 116, height: 20)

        let badgeX = logo.frame.maxX + 12
        let badgeY: CGFloat = 3
        editionBadgePanel.frame = NSRect(x: badgeX, y: badgeY, width: badgeW, height: badgeH)
        editionBadgeLabel.frame = NSRect(x: 0, y: (badgeH - labelH) / 2, width: badgeW, height: labelH)

        let switcherW = badgeX + badgeW + 3
        productSwitcherPanel.frame = NSRect(x: 4, y: topBarY + 9, width: switcherW, height: 26)
        productSwitcherMenu.frame = NSRect(x: 8, y: topBarY - 302, width: 220, height: 300)

        // Center: Search bar + Help (?) button + Search Popover
        // Web caps the search field at 432pt and centers it in the header.
        let rightClusterW: CGFloat = 152
        let searchWidth = max(180, min(min(432, size.width * 0.30), size.width - switcherW - rightClusterW - 24))
        let minSearchX: CGFloat = productSwitcherPanel.frame.maxX + 12
        let idealSearchX = (size.width - searchWidth) / 2
        let searchX = max(minSearchX, idealSearchX)
        searchPanel.frame = NSRect(x: searchX, y: topBarY + 8, width: searchWidth, height: 28)
        searchIconView.frame = NSRect(x: 4, y: 5, width: 18, height: 18)
        searchLabel.frame = NSRect(x: 29, y: 4, width: searchWidth - 37, height: 20)

        helpPanel.frame = NSRect(x: searchX + searchWidth + 8, y: topBarY + 8, width: MMMetric.iconButtonSmall, height: MMMetric.iconButtonSmall)
        helpIconView.frame = NSRect(x: 6, y: 6, width: 16, height: 16)
        helpMenu.frame = NSRect(x: helpPanel.frame.minX, y: topBarY - 178, width: 204, height: 176)

        searchPopoverPanel.frame = NSRect(x: searchX, y: topBarY - 124, width: MMMetric.searchPopoverWidth, height: 122)

        // Right: Mentions (@), Saved Posts, Settings, User Avatar + Status Dot.
        // Web: 28pt buttons with 8pt gaps ending 4pt from the window edge, 40x32 avatar button.
        avatarButtonPanel.frame = NSRect(x: size.width - 44, y: topBarY + 6, width: 40, height: 32)
        avatarPanel.frame = NSRect(x: 8, y: 4, width: MMMetric.avatarSmall, height: MMMetric.avatarSmall)
        avatarLabel.frame = NSRect(x: 0, y: 5, width: 24, height: 14)
        statusDotPanel.frame = NSRect(x: 21, y: 1, width: 16, height: 16)
        updateStatusCheck(in: statusDotPanel, status: currentUserStatus)
        statusMenu.frame = NSRect(x: size.width - 259, y: topBarY - 356, width: 248, height: 354)
        dndSubMenu.frame = NSRect(x: statusMenu.frame.minX - 210, y: statusMenu.frame.minY - 50, width: 212, height: 232)

        settingsPanel.frame = NSRect(x: size.width - 80, y: topBarY + 8, width: MMMetric.iconButtonSmall, height: MMMetric.iconButtonSmall)
        settingsIconView.frame = NSRect(x: 6, y: 6, width: 16, height: 16)

        savedPostsPanel.frame = NSRect(x: size.width - 116, y: topBarY + 8, width: MMMetric.iconButtonSmall, height: MMMetric.iconButtonSmall)
        savedPostsIconView.frame = NSRect(x: 6, y: 6, width: 16, height: 16)

        mentionsPanel.frame = NSRect(x: size.width - 152, y: topBarY + 8, width: MMMetric.iconButtonSmall, height: MMMetric.iconButtonSmall)
        mentionsIconView.frame = NSRect(x: 6, y: 6, width: 16, height: 16)

        // Search results float below the search field.
        let resultsWidth = min(560, max(360, size.width - chatPanel.frame.minX - 48))
        let resultsHeight = min(430, max(200, topBarY - 130))
        searchResultsPanel.frame = NSRect(
            x: chatPanel.frame.minX + 24,
            y: topBarY - resultsHeight - 68,
            width: resultsWidth,
            height: resultsHeight
        )
        searchResultsTitle.frame = NSRect(x: 16, y: resultsHeight - 34, width: resultsWidth - 60, height: 20)
        searchResultsCloseButton.frame = NSRect(x: resultsWidth - 36, y: resultsHeight - 38, width: MMMetric.iconButtonCompact, height: MMMetric.iconButtonCompact)
        if !searchResultsPanel.isHidden {
            searchResultsScroll.frame = NSRect(x: 0, y: 0, width: resultsWidth, height: resultsHeight - 44)
        }
    }
}
