//
//  MainWindow.swift
//  mattermost.client
//
//  Window shell: live-data forwarding, view state, init and AppKit overrides.
//  Components live in MainWindow+*.swift; shared helpers in MainWindowSupport.swift.
//

import Cocoa
import UniformTypeIdentifiers
import ImageIO
import UniformTypeIdentifiers

class MainWindow: NSWindow, NSTextViewDelegate, NSTextFieldDelegate, NSSearchFieldDelegate {
    let viewModel = ChatViewModel()
    var zoomController: WindowZoomController?

    let mainPanel = RoundedEdgePanel()
    let chatPanel = RoundedEdgePanel()
    let chatEntryPanel = OutlinePanel()
    let entryView = ComposerTextView()

    let boxImage = NSImageView(image: NSImage(named: NSImage.Name("E82F"))!)
    let logo = NSImageView(image: NSImage(named: NSImage.Name("Mattermost Logo"))!)

    // Top Global Bar views
    let productSwitcherPanel = RoundedEdgePanel()
    let editionBadgePanel = RoundedEdgePanel()
    let editionBadgeLabel = NSTextField(labelWithString: "TEAM EDITION")

    let searchPanel = RoundedEdgePanel()
    let searchIconView = NSImageView()
    let searchLabel = NSTextField(labelWithString: "Search")
    let helpPanel = RoundedEdgePanel()
    let helpIconView = NSImageView()

    let mentionsPanel = RoundedEdgePanel()
    let mentionsIconView = NSImageView()
    let savedPostsPanel = RoundedEdgePanel()
    let savedPostsIconView = NSImageView()
    let settingsPanel = RoundedEdgePanel()
    let settingsIconView = NSImageView()

    // Right-hand side panel (threads / members / pinned posts / files)
    let rightPanel = RoundedEdgePanel()
    let rightPanelTitle = NSTextField(labelWithString: "Threads")
    let rightPanelSubtitle = NSTextField(labelWithString: "")
    let rightPanelCloseButton = RoundedEdgePanel()
    let rightPanelResizeHandle = RightPanelResizeHandle()
    var rightPanelWidth: CGFloat = {
        let stored = UserDefaults.standard.double(forKey: "rhsWidth")
        return stored > 0 ? CGFloat(stored) : MMMetric.rightPanelDefaultWidth
    }()
    static let localizedTimeFormatter: DateFormatter = {
        let formatter = DateFormatter()
        formatter.locale = .current
        formatter.dateStyle = .none
        formatter.timeStyle = .short
        return formatter
    }()
    static let localizedDateTimeFormatter: DateFormatter = {
        let formatter = DateFormatter()
        formatter.locale = .current
        formatter.dateStyle = .medium
        formatter.timeStyle = .short
        return formatter
    }()
    static let localizedShortWeekdayFormatter: DateFormatter = {
        let formatter = DateFormatter()
        formatter.locale = .current
        formatter.setLocalizedDateFormatFromTemplate("EEE")
        return formatter
    }()

    let connectionBanner = RoundedEdgePanel()
    let connectionLabel = NSTextField(labelWithString: "")
    let rightPanelScroll = NSScrollView()
    let rightPanelDoc = TimelineFlippedView()
    enum RightPanelMode { case threads, members, pinned, mentions, saved, settings, browse, thread, files }
    var rightPanelMode: RightPanelMode = .threads
    var isRightPanelVisible = false
    var threadItems: [MMThread] {
        get { viewModel.threadItems }
        set { viewModel.threadItems = newValue }
    }
    var threadPosts: [MMPost] {
        get { viewModel.threadPosts }
        set { viewModel.threadPosts = newValue }
    }
    var threadRootId: String {
        get { viewModel.threadRootId }
        set { viewModel.threadRootId = newValue }
    }
    let threadReplyField = NSTextField()
    let threadReplyPanel = RoundedEdgePanel()
    let threadSendButton = RoundedEdgePanel()
    let threadPlaceholderLabel = NSTextField(labelWithString: "Reply to thread…")

    // Post hover toolbar extras: reaction picker and the "more" menu
    let reactionPickerPanel = RoundedEdgePanel()
    var isReactionPickerOpen = false
    var reactionPickerAnchorInChat: NSRect = .zero
    var reactionPickerPostId: String = ""
    let postActionMenu = RoundedEdgePanel()
    var isPostActionMenuOpen = false
    var postActionMenuAnchorInChat: NSRect = .zero
    var postActionMenuPost: MMPost?

    // Full-window image lightbox
    let lightboxOverlay = RoundedEdgePanel()
    let lightboxHeaderPanel = RoundedEdgePanel()
    let lightboxZoomBar = RoundedEdgePanel()
    let lightboxContentPanel = RoundedEdgePanel()
    let lightboxImageView = NSImageView()
    let lightboxAvatarView = NSImageView()
    let lightboxAvatarPanel = RoundedEdgePanel()
    let lightboxTitleLabel = NSTextField(labelWithString: "")
    let lightboxSubtitleLabel = NSTextField(labelWithString: "")
    let lightboxDownloadButton = RoundedEdgePanel()
    let lightboxCloseButton = RoundedEdgePanel()
    let lightboxZoomOutButton = RoundedEdgePanel()
    let lightboxZoomFitButton = RoundedEdgePanel()
    let lightboxZoomInButton = RoundedEdgePanel()
    var isLightboxVisible = false
    var lightboxFile: MMFileInfo?
    var lightboxRemoteURL: String?
    var lightboxNaturalSize: NSSize = .zero
    var lightboxScale: CGFloat = 1
    var lightboxKeyMonitor: Any?
    var lightboxLoadToken = UUID()

    // Natural sizes cached after an inline image loads so the timeline can reflow once.
    var inlineImageSizeCache: [String: NSSize] = [:]
    var attachmentSizeCache: [String: NSSize] = [:]
    var isRelayoutScheduled = false

    // Channel header dropdown menu
    let channelMenu = RoundedEdgePanel()
    var isChannelMenuOpen = false

    // Composer emoji picker
    let emojiPanel = RoundedEdgePanel()
    var isEmojiPanelOpen = false
    let emojiSearchField = NSSearchField()
    let emojiScroll = NSScrollView()
    let emojiDoc = TimelineFlippedView()
    let emojiCategoryBar = NSView()
    var customEmojiEntries: [EmojiEntry] = []
    var customEmojiImages: [String: NSImage] = [:]
    var recentEmojiNames: [String] = []
    var emojiSelectedCategory = "Recent"
    var isCustomEmojiLoaded = false
    var emojiCategoryBarButtons: [String: RoundedEdgePanel] = [:]

    // Sidebar filter menu
    let filterMenu = RoundedEdgePanel()
    var isFilterMenuOpen = false
    var sidebarFavoritesOnly = false
    var filterAllCheck: NSImageView?
    var filterFavoritesCheck: NSImageView?

    let avatarButtonPanel = RoundedEdgePanel()
    let avatarPanel = RoundedEdgePanel()
    let avatarImageView = NSImageView()
    let avatarLabel = NSTextField(labelWithString: "B")
    let statusDotPanel = RoundedEdgePanel()

    // Product Switcher dropdown menu
    let productSwitcherMenu = RoundedEdgePanel()
    var isProductMenuOpen = false

    // Search popover panel
    let searchPopoverPanel = RoundedEdgePanel()
    let searchPopoverInputLabel = NSTextField(labelWithString: "Search messages")
    let searchResultsPanel = RoundedEdgePanel()
    let searchResultsScroll = NSScrollView()
    let searchResultsDoc = TimelineFlippedView()
    let searchResultsTitle = NSTextField(labelWithString: "Search results")
    let searchResultsCloseButton = RoundedEdgePanel()
    let messagesTabPanel = RoundedEdgePanel()
    let messagesTabLabel = NSTextField(labelWithString: "Messages")
    let filesTabPanel = RoundedEdgePanel()
    let filesTabLabel = NSTextField(labelWithString: "Files")
    var isSearchPopoverOpen = false
    var isSearchFilesTabSelected = false

    // Direct Message picker (opened from the + in the Direct Messages header)
    let dmPickerPanel = RoundedEdgePanel()
    let dmSearchField = NSSearchField()
    let dmScroll = NSScrollView()
    let dmDoc = TimelineFlippedView()
    var dmUsers: [LoginWebService] = []
    var isDMPickerOpen = false
    var dmAnchorFrame: NSRect = .zero

    // Help popup menu
    let helpMenu = RoundedEdgePanel()
    var isHelpMenuOpen = false

    // User status / profile dropdown menu + Do not disturb submenu
    let statusMenu = RoundedEdgePanel()
    let dndSubMenu = RoundedEdgePanel()
    weak var dndStatusRow: RoundedEdgePanel?
    var isStatusMenuOpen = false
    var isDndSubMenuOpen = false
    var selectedStatusIndex = 0
    weak var customStatusMenuRow: RoundedEdgePanel?
    var customStatusText: String = UserDefaults.standard.string(forKey: "customStatusText") ?? ""
    var customStatusEmoji: String = UserDefaults.standard.string(forKey: "customStatusEmoji") ?? ""
    var statusCheckViews: [NSImageView] = []

    // Left Channel Sidebar views
    let teamHeaderButton = RoundedEdgePanel()
    let teamHeaderLabel = NSTextField(labelWithString: "")
    let teamHeaderChevron = NSImageView()
    let teamDropdownMenu = RoundedEdgePanel()
    var isTeamMenuOpen = false
    var userTeams: [MMTeam] {
        get { viewModel.userTeams }
        set { viewModel.userTeams = newValue }
    }
    let teamAddButton = RoundedEdgePanel()
    let teamAddIconView = NSImageView()

    let filterChannelButton = RoundedEdgePanel()
    let filterChannelIconView = NSImageView()
    let findChannelPanel = RoundedEdgePanel()
    let findChannelIconView = NSImageView()
    let findChannelLabel = NSTextField(labelWithString: "Find channel")

    struct SidebarItemView {
        let id: String
        let isSelectable: Bool
        var isBotBadge: Bool
        let row: RoundedEdgePanel
        let leftBar: RoundedEdgePanel
        let iconView: NSImageView
        let label: NSTextField
        let hoverCloseView: NSImageView?
        let badgePanel: RoundedEdgePanel
        let badgeLabel: NSTextField
    }

    struct SidebarCategoryView {
        let id: String
        let headerRow: RoundedEdgePanel
        let chevronView: NSImageView
        let titleLabel: NSTextField
        let addButton: RoundedEdgePanel?
        var isCollapsed: Bool
        var items: [SidebarItemView]
    }

    var threadsSidebarItem: SidebarItemView?
    var sidebarCategories: [SidebarCategoryView] = []
    var selectedSidebarItemId: String = "town-square"

    // Right Chat Panel views
    // 1. Channel Header Bar
    let channelHeaderBorder = RoundedEdgePanel()
    let channelStarButton = RoundedEdgePanel()
    let channelStarIconView = NSImageView()
    var isChannelFavorited = false
    var favoriteChannelIds: Set<String> = []
    var favoritesCategory: SidebarCategoryView?
    var isFavoritesCollapsed = false
    var channelFilterQuery: String = ""
    var membershipsByChannel: [String: MMChannelMembership] {
        get { viewModel.membershipsByChannel }
        set { viewModel.membershipsByChannel = newValue }
    }
    var unreadByChannel: [String: Int] {
        get { viewModel.unreadByChannel }
        set { viewModel.unreadByChannel = newValue }
    }
    var mentionsByChannel: [String: Int] {
        get { viewModel.mentionsByChannel }
        set { viewModel.mentionsByChannel = newValue }
    }
    var lastViewedAtByChannel: [String: Int64] {
        get { viewModel.lastViewedAtByChannel }
        set { viewModel.lastViewedAtByChannel = newValue }
    }
    var dndEndTimeByUser: [String: Int64] {
        get { viewModel.dndEndTimeByUser }
        set { viewModel.dndEndTimeByUser = newValue }
    }
    var newMessagesBaseline: Int64 = 0
    var newMessagesDividerPostId: String?
    var newMessagesDividerView: NSView?
    var newMessagesCount: Int = 0
    var newMessagesDividerArmed = false
    let newMessagesPill = RoundedEdgePanel()
    let newMessagesPillIcon = NSImageView()
    let newMessagesPillLabel = NSTextField(labelWithString: "")
    var isLoadingOlderPosts: Bool {
        get { viewModel.isLoadingOlderPosts }
        set { viewModel.isLoadingOlderPosts = newValue }
    }
    var didLoadAllHistory: Bool {
        get { viewModel.didLoadAllHistory }
        set { viewModel.didLoadAllHistory = newValue }
    }
    let postsPerPage = 60
    let channelTitleButton = RoundedEdgePanel()
    let channelTitleLabel = NSTextField(labelWithString: "Town Square")
    let channelHeaderBotBadge = RoundedEdgePanel()
    let channelHeaderBotBadgeLabel = NSTextField(labelWithString: "BOT")
    let channelTitleChevron = NSImageView()
    let channelMembersButton = RoundedEdgePanel()
    let channelMembersIconView = NSImageView()
    let channelMembersCountLabel = NSTextField(labelWithString: "1")
    let channelPinsButton = RoundedEdgePanel()
    let channelPinsIconView = NSImageView()
    let channelFilesButton = RoundedEdgePanel()
    let channelFilesIconView = NSImageView()
    let channelSidebarButton = RoundedEdgePanel()
    let channelSidebarIconView = NSImageView()
    let channelInfoButton = RoundedEdgePanel()
    let channelInfoIconView = NSImageView()

    // 2. Message Timeline & Welcome Hero
    let chatTimelineContainer = TimelineContainerView()
    let timelineScrollView = TimelineScrollView()
    let timelineDocView = TimelineFlippedView()
    var currentChannelPosts: [MMPost] {
        get { viewModel.currentChannelPosts }
        set { viewModel.currentChannelPosts = newValue }
    }
    var pendingJumpPostId: String? {
        get { viewModel.pendingJumpPostId }
        set { viewModel.pendingJumpPostId = newValue }
    }
    var editingPostId: String?
    var lastTimelineWidth: CGFloat = 0
    let timelineHeroContainer = RoundedEdgePanel()
    let heroIllustrationCircle = RoundedEdgePanel()
    let heroWhiteBubble = OutlinePanel()
    let heroBlueBubble = RoundedEdgePanel()
    let heroBotAvatarView = NSImageView()
    let heroTitleLabel = NSTextField(labelWithString: "Town Square")
    let heroBotBadge = RoundedEdgePanel()
    let heroBotBadgeLabel = NSTextField(labelWithString: "BOT")
    let heroDescriptionLabel = NSTextField(labelWithString: "Welcome to Town Square. Post messages here that you want everyone to see. Everyone\nautomatically becomes a member of this channel when they join the team.")
    let heroInviteButton = RoundedEdgePanel()
    let heroInviteIconView = NSImageView()
    let heroInviteLabel = NSTextField(labelWithString: "Invite others to the workspace")


    let statusPromptPill = RoundedEdgePanel()

    // 3. Message Composer & Formatting Toolbar
    let composerPlaceholderLabel = NSTextField(labelWithString: "Write to Town Square")
    var composerLeftButtons: [RoundedEdgePanel] = []
    var composerLeftSeparator = RoundedEdgePanel()
    let composerAaButton = RoundedEdgePanel()
    let composerAaChevron = NSImageView()
    var isComposerToolbarVisible = false
    let composerRightSeparator = RoundedEdgePanel()
    let composerEmojiButton = RoundedEdgePanel()
    let composerGifButton = RoundedEdgePanel()
    let composerAttachButton = RoundedEdgePanel()
    let composerSendButton = RoundedEdgePanel()
    let composerHelpLabel = NSTextField(labelWithString: "Help")
    let composerAttachmentTray = NSView()

    struct PendingAttachment {
        let id: String
        let name: String
        let size: Int64?
    }

    var pendingAttachments: [PendingAttachment] = []
    let completionPanel = RoundedEdgePanel()
    var completionItems: [CompletionItem] = []
    var completionRowViews: [RoundedEdgePanel] = []
    var completionRange = NSRange(location: 0, length: 0)
    var completionKind: CompletionKind = .user
    var completionSelectedIndex = 0
    var isCompletionVisible = false
    var completionUsers: [LoginWebService] = []
    var completionUsersTeamId: String?
    var completionUsersLoading = false
    var composerBaseHeight: CGFloat { isComposerToolbarVisible ? MMMetric.composerToolbarHeight : MMMetric.composerHeight }
    var composerPendingHeight: CGFloat { pendingAttachments.isEmpty ? 0 : MMMetric.composerAttachmentsHeight }
    var composerTotalHeight: CGFloat { composerBaseHeight + composerPendingHeight }

    // Live WebService state (owned by the view model; exposed for the views).
    /// Injected by `AppDelegate` when the workspace window is created.
    var webService: WebService? {
        get { viewModel.webService }
        set { viewModel.webService = newValue }
    }
    var currentUser: LoginWebService? {
        get { viewModel.currentUser }
        set { viewModel.currentUser = newValue }
    }
    var activeTeam: MMTeam? {
        get { viewModel.activeTeam }
        set { viewModel.activeTeam = newValue }
    }
    var activeChannelId: String {
        get { viewModel.activeChannelId }
        set { viewModel.activeChannelId = newValue }
    }
    var channelsById: [String: MMChannel] {
        get { viewModel.channelsById }
        set { viewModel.channelsById = newValue }
    }
    var channelsByName: [String: MMChannel] {
        get { viewModel.channelsByName }
        set { viewModel.channelsByName = newValue }
    }
    var usersById: [String: LoginWebService] {
        get { viewModel.usersById }
        set { viewModel.usersById = newValue }
    }
    var usersByUsername: [String: LoginWebService] {
        get { viewModel.usersByUsername }
        set { viewModel.usersByUsername = newValue }
    }
    var userStatusById: [String: String] {
        get { viewModel.userStatusById }
        set { viewModel.userStatusById = newValue }
    }
    var currentUserStatus: String {
        get { viewModel.currentUserStatus }
        set { viewModel.currentUserStatus = newValue }
    }
    var userAvatarsById: [String: NSImage] = [:]
    var userAvatarFetchTasks: [String: Task<Void, Never>] = [:]
    var composerSendIconView: NSImageView?
    var composerSendEnabled = false
    var lastTypingSentAt: Date?
    var menuAvatarStatusDot: RoundedEdgePanel?
    var statusPollingTimer: Timer?

    override init(contentRect rect: NSRect, styleMask style: NSWindow.StyleMask, backing backingStoreType: NSWindow.BackingStoreType, defer flag: Bool) {

        super.init(contentRect: rect, styleMask: style, backing: backingStoreType, defer: flag)

        self.isReleasedWhenClosed = false
        self.backgroundColor = Theme.shared.sidebarTeamBarBg

        self.title = AppVersion.windowTitle
        self.contentViewController = MainWindowViewController()
        self.setContentSize(NSSize(width: rect.width, height: rect.height))
        self.center()
        // Restore the user's last window frame when one is stored; otherwise the
        // default 1440x783 content size from AppDelegate is used.
        self.setFrameAutosaveName("MainWindowFrame")

        mainPanel.color = Theme.shared.sidebarBg
        mainPanel.cornerRadius = MMRadius.panel

        entryView.backgroundColor = .clear
        entryView.drawsBackground = false
        entryView.isEditable = true
        entryView.isSelectable = true
        entryView.isRichText = false
        entryView.allowsUndo = true
        entryView.isHidden = false
        entryView.font = MMFont.font(ofSize: 14)
        entryView.textColor = Theme.shared.centerText
        entryView.insertionPointColor = Theme.shared.buttonBg
        entryView.textContainerInset = NSSize(width: 0, height: 13)
        entryView.textContainer?.lineFragmentPadding = 0
        entryView.delegate = self
        entryView.placeholderString = "Write to Town Square"

        chatEntryPanel.color = Theme.shared.centerText.withAlphaComponent(0.16)
        chatEntryPanel.cornerRadius = MMRadius.control
        chatEntryPanel.borderWidth = 2
        chatPanel.addSubview(chatEntryPanel)
        chatEntryPanel.addSubview(entryView)

        chatEntryPanel.onFilesDropped = { [weak self] urls in
            self?.uploadFiles(urls)
        }
        chatEntryPanel.onDropStateChanged = { [weak self] active in
            self?.setComposerDropHighlight(active)
        }
        entryView.onFilesDropped = { [weak self] urls in
            self?.uploadFiles(urls)
        }
        entryView.onDropStateChanged = { [weak self] active in
            self?.setComposerDropHighlight(active)
        }
        composerAttachmentTray.isHidden = true
        chatEntryPanel.addSubview(composerAttachmentTray)

        completionPanel.color = Theme.shared.centerBg
        completionPanel.cornerRadius = MMRadius.menu
        completionPanel.borderWidth = 1
        completionPanel.borderColor = Theme.shared.divider
        completionPanel.shadowColor = .black
        completionPanel.shadowOpacity = 0.16
        completionPanel.shadowRadius = 10
        completionPanel.shadowOffset = CGSize(width: 0, height: -3)
        completionPanel.isHidden = true
        chatPanel.addSubview(completionPanel)


        contentView?.addSubview(mainPanel)

        chatPanel.color = Theme.shared.centerBg
        chatPanel.cornerRadius = MMRadius.panel
        contentView?.addSubview(chatPanel)

        setupLeftChannelSidebar()
        setupRightChatPanel()
        setupTopGlobalBar()

        updateViews()
        zoomController = WindowZoomController(window: self, onLayout: { [weak self] in
            self?.updateViews()
        })
        zoomController?.applyCurrentZoom()
        if CommandLine.arguments.contains("--custom-status-test") {
            DispatchQueue.main.asyncAfter(deadline: .now() + 5.0) { [weak self] in self?.showCustomStatusDialog() }
        }
        if CommandLine.arguments.contains("--statusmenu-test") {
            DispatchQueue.main.asyncAfter(deadline: .now() + 8.0) { [weak self] in self?.setStatusMenuOpen(true) }
        }
        if CommandLine.arguments.contains("--custom-set-test") {
            DispatchQueue.main.asyncAfter(deadline: .now() + 5.0) { [weak self] in
                self?.applyCustomStatus(emoji: "coffee", text: "Focusing", durationIndex: 1)
            }
            DispatchQueue.main.asyncAfter(deadline: .now() + 8.0) { [weak self] in
                self?.setStatusMenuOpen(true)
            }
        }
        if CommandLine.arguments.contains("--view-test") {
            DispatchQueue.main.asyncAfter(deadline: .now() + 5.0) { [weak self] in
                guard let self = self, let ws = self.webService else { return }
                ws.sendWebSocketMessage(action: "view_channel", data: [
                    "channel_id": self.activeChannelId,
                    "prev_channel_id": "",
                    "channel_type": "O"
                ])
            }
        }
        self.makeKeyAndOrderFront(nil)

        NotificationCenter.default.addObserver(self, selector: #selector(appDidBecomeActive), name: NSApplication.didBecomeActiveNotification, object: nil)
    }

    enum FocusRegion {
        case sidebar
        case timeline
        case composer
    }

    override func sendEvent(_ event: NSEvent) {
        if event.type == .keyDown {
            if event.keyCode == 53, closeTopOverlay() {
                return
            }
            if event.keyCode == 48, !isCompletionVisible,
               handleFocusTraversal(reverse: event.modifierFlags.contains(.shift)) {
                return
            }
        }
        if event.type == .leftMouseDown || event.type == .rightMouseDown {
            if let contentView = contentView {
                let point = contentView.convert(event.locationInWindow, from: nil)
                if isProductMenuOpen && !productSwitcherMenu.frame.contains(point) && !productSwitcherPanel.frame.contains(point) {
                    setProductSwitcherMenuOpen(false)
                }
                if isSearchPopoverOpen && !searchPopoverPanel.frame.contains(point) && !searchPanel.frame.contains(point) {
                    setSearchPopoverOpen(false)
                }
                if !searchResultsPanel.isHidden && !searchResultsPanel.frame.contains(point) && !searchPanel.frame.contains(point) {
                    closeSearchResults()
                }
                if isHelpMenuOpen && !helpMenu.frame.contains(point) && !helpPanel.frame.contains(point) {
                    setHelpMenuOpen(false)
                }
                if isStatusMenuOpen && !statusMenu.frame.contains(point) && !avatarButtonPanel.frame.contains(point) && !(isDndSubMenuOpen && dndSubMenu.frame.contains(point)) {
                    setStatusMenuOpen(false)
                }
                if isTeamMenuOpen && !teamDropdownMenu.frame.contains(point) && !teamHeaderButton.frame.contains(point) {
                    setTeamMenuOpen(false)
                }
                if isChannelMenuOpen {
                    let chatPoint = chatPanel.convert(event.locationInWindow, from: nil)
                    let titleFrame = channelTitleButton.frame
                    if !channelMenu.frame.contains(chatPoint) && !titleFrame.contains(chatPoint) {
                        closeChannelMenu()
                    }
                }
                if isEmojiPanelOpen {
                    let chatPoint = chatPanel.convert(event.locationInWindow, from: nil)
                    let emojiButtonFrame = chatEntryPanel.convert(composerEmojiButton.frame, to: chatPanel)
                    if !emojiPanel.frame.contains(chatPoint) && !emojiButtonFrame.contains(chatPoint) {
                        closeEmojiPanel()
                    }
                }
                if isReactionPickerOpen {
                    let chatPoint = chatPanel.convert(event.locationInWindow, from: nil)
                    if !reactionPickerPanel.frame.contains(chatPoint) && !reactionPickerAnchorInChat.contains(chatPoint) {
                        closeReactionPicker()
                    }
                }
                if isPostActionMenuOpen {
                    let chatPoint = chatPanel.convert(event.locationInWindow, from: nil)
                    if !postActionMenu.frame.contains(chatPoint) && !postActionMenuAnchorInChat.contains(chatPoint) {
                        closePostActionMenu()
                    }
                }
                if isFilterMenuOpen {
                    let mainPoint = mainPanel.convert(event.locationInWindow, from: nil)
                    if !filterMenu.frame.contains(mainPoint) && !filterChannelButton.frame.contains(mainPoint) {
                        setFilterMenuOpen(false)
                    }
                }
                if isDMPickerOpen && !dmPickerPanel.frame.contains(point) && !dmAnchorFrame.contains(point) {
                    closeDMPicker()
                }
                if isCompletionVisible {
                    let chatPoint = chatPanel.convert(event.locationInWindow, from: nil)
                    if !completionPanel.frame.contains(chatPoint) && !chatEntryPanel.frame.contains(chatPoint) {
                        closeCompletion()
                    }
                }
            }
        }
        super.sendEvent(event)
    }

    override func performKeyEquivalent(with event: NSEvent) -> Bool {
        if zoomController?.handleKeyEquivalent(event) == true {
            return true
        }
        if event.modifierFlags.contains(.command) {
            let chars = event.charactersIgnoringModifiers ?? ""
            if chars == "k" {
                focusGlobalSearch()
                return true
            } else if chars == "f" {
                focusChannelSearch()
                return true
            }
        }
        return super.performKeyEquivalent(with: event)
    }

    struct CompletionTrigger {
        let kind: CompletionKind
        let query: String
        let range: NSRange
    }

    struct RightPanelRow {
        let title: String
        let subtitle: String
        let meta: String
        let action: (() -> Void)?
    }

    struct ParsedGiphyMessage {
        let text: String
        let gifURLs: [String]
    }

    /// Shortcodes used by the reaction picker and the chip renderer.
    static let emojiGlyphs: [String: String] = [
        "thumbsup": "👍", "+1": "👍", "thumbsdown": "👎", "-1": "👎",
        "smile": "😄", "grinning": "😀", "joy": "😂", "heart": "❤️",
        "red_heart": "❤️", "tada": "🎉", "eyes": "👀", "fire": "🔥",
        "wave": "👋", "clap": "👏", "pray": "🙏", "rocket": "🚀",
        "white_check_mark": "✅", "x": "❌", "thinking_face": "🤔",
        "cry": "😢", "sob": "😭", "sunglasses": "😎", "100": "💯",
        "ok_hand": "👌", "point_up": "☝️", "muscle": "💪", "star": "⭐",
        "coffee": "☕", "computer": "💻", "palm_tree": "🌴", "beer": "🍺",
        "pizza": "🍕", "cake": "🎂", "sunny": "☀️", "rainbow": "🌈",
        "warning": "⚠️", "bulb": "💡", "lock": "🔒", "bell": "🔔"
    ]

    /// The first page of the reaction picker, mirroring Mattermost's common reactions.
    static let quickReactions: [(name: String, glyph: String)] = [
        ("thumbsup", "👍"), ("thumbsdown", "👎"), ("smile", "😄"), ("joy", "😂"),
        ("heart", "❤️"), ("tada", "🎉"), ("eyes", "👀"), ("fire", "🔥"),
        ("wave", "👋"), ("clap", "👏"), ("rocket", "🚀"), ("white_check_mark", "✅"),
        ("thinking_face", "🤔"), ("sob", "😭"), ("sunglasses", "😎"), ("100", "💯")
    ]

    override func resignKey() {
        super.resignKey()
        for subview in timelineDocView.subviews {
            if let panel = subview as? RoundedEdgePanel, panel.isHovered {
                panel.setHovered(false)
            }
        }
    }

    deinit {
        NotificationCenter.default.removeObserver(self)
    }
}