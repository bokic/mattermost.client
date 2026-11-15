//
//  MainWindow.swift
//  mattermost.client
//
//  Window shell: live-data forwarding, view state, init and AppKit overrides.
//  Components live in MainWindow+*.swift; shared helpers in MainWindowSupport.swift.
//

import Cocoa
import ImageIO
import UniformTypeIdentifiers

class MainWindow: NSWindow, NSTextViewDelegate, NSTextFieldDelegate, NSSearchFieldDelegate {
    let viewModel = ChatViewModel()
    var zoomController: WindowZoomController?

    let mainPanel = RoundedEdgePanel()
    let chatPanel = RoundedEdgePanel()
    let chatEntryPanel = OutlinePanel()
    let entryView = ComposerTextView()

    let boxImage = NSImageView(image: NSImage(named: NSImage.Name("E82F")) ?? NSImage())
    let logo = NSImageView(image: NSImage(named: NSImage.Name("Mattermost Logo")) ?? NSImage())

    // Top Global Bar views
    let productSwitcherPanel = RoundedEdgePanel()
    let editionBadgePanel = RoundedEdgePanel()
    let editionBadgeLabel = NSTextField(labelWithString: "TEAM EDITION")

    let searchPanel = RoundedEdgePanel()
    let searchIconView = NSImageView()
    let searchLabel = NSTextField(labelWithString: L10n.string("Search"))
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
    let rightPanelTitle = NSTextField(labelWithString: L10n.string("Threads"))
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
    enum RightPanelMode {
        case threads, members, pinned, mentions, saved, settings, browse, thread, files, channelInfo, teamMembers
    }
    var rightPanelMode: RightPanelMode = .threads
    var isRightPanelVisible = false
    var pendingJoinRequestChannelIds: Set<String> = []
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
    let threadReplyPanel = RoundedEdgePanel()
    let threadReplyScroll = NSScrollView()
    let threadReplyTextView = ComposerTextView()
    let threadSendButton = RoundedEdgePanel()
    let threadSendIconView = NSImageView()
    let threadEmojiButton = RoundedEdgePanel()
    let threadAttachButton = RoundedEdgePanel()
    let threadAttachmentTray = NSView()
    var readThreadIds: Set<String> = []
    var threadRequestToken = 0
    var threadsRequestToken = 0
    var threadVisibleReplyLimit = 50
    var threadItemsPage = 0
    var threadItemsHasMore = false
    var threadItemsLoading = false
    var threadPendingAttachmentsByRootId: [String: [PendingAttachment]] = [:]
    var lastThreadTypingSentAt: Date?
    var threadComposerSending = false
    var threadComposerBaseHeight: CGFloat = 92
    var threadAttachmentTrayHeight: CGFloat {
        let hasPending = threadPendingAttachmentsByRootId[threadRootId]?.isEmpty == false
        let hasUploads = activeAttachmentUploads.contains {
            $0.threadRootId == threadRootId && $0.isInProgress
        }
        return hasPending || hasUploads ? 30 : 0
    }
    var threadComposerHeight: CGFloat {
        threadComposerBaseHeight + threadAttachmentTrayHeight
    }
    enum EmojiInsertionTarget { case composer, thread }
    var emojiInsertionTarget: EmojiInsertionTarget = .composer
    enum CompletionTarget { case composer, thread }
    var completionTarget: CompletionTarget = .composer

    // Post hover toolbar extras: reaction picker and the "more" menu
    let reactionPickerPanel = RoundedEdgePanel()
    let reactionPickerSearchField = NSSearchField()
    let reactionPickerScroll = NSScrollView()
    let reactionPickerDoc = TimelineFlippedView()
    var reactionPickerEntries: [EmojiEntry] = []
    var recentReactionNames = UserDefaults.standard.stringArray(forKey: "recentReactions") ?? []
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
    let lightboxScrollView = NSScrollView()
    let lightboxCanvas = NSView()
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
    var inlineImageSizeCache = BoundedSizeCache()
    var attachmentSizeCache = BoundedSizeCache()
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
    var customEmojiImages = BoundedImageCache(countLimit: 500)
    var recentEmojiNames: [String] = []
    var emojiSelectedCategory = "Recent"
    var isCustomEmojiLoaded = false
    var emojiCategoryBarButtons: [String: RoundedEdgePanel] = [:]

    // Sidebar filter menu
    let filterMenu = RoundedEdgePanel()
    let sidebarEmptyStateLabel = NSTextField(labelWithString: "")
    let sidebarScroll = NSScrollView()
    let sidebarDoc = TimelineFlippedView()
    var isFilterMenuOpen = false
    var sidebarFavoritesOnly = false
    var sidebarUnreadOnly = false
    var filterAllCheck: NSImageView?
    var filterFavoritesCheck: NSImageView?
    var filterUnreadCheck: NSImageView?
    var mutedChannelIds: Set<String> = []
    var channelDesktopNotificationByChannel: [String: String] = [:]

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
    let searchPopoverInputLabel = NSTextField(labelWithString: L10n.string("Search messages"))
    let searchResultsPanel = RoundedEdgePanel()
    let searchResultsScroll = NSScrollView()
    let searchResultsDoc = TimelineFlippedView()
    let searchResultsTitle = NSTextField(labelWithString: L10n.string("Search results"))
    let searchResultsCloseButton = RoundedEdgePanel()
    let messagesTabPanel = RoundedEdgePanel()
    let messagesTabLabel = NSTextField(labelWithString: L10n.string("Messages"))
    let filesTabPanel = RoundedEdgePanel()
    let filesTabLabel = NSTextField(labelWithString: L10n.string("Files"))
    var isSearchPopoverOpen = false
    var isSearchFilesTabSelected = false
    var searchResultsTerms = ""
    var searchResultPosts: [MMPost] = []
    var searchResultFiles: [MMFileInfo] = []
    var searchResultRowViews: [RoundedEdgePanel] = []
    var searchResultsSelectionIndex = -1
    var searchResultsPage = 0
    var searchResultsHasMore = false
    var searchResultsLoading = false
    var searchResultsAreFiles = false
    var searchResultsAreRecents = false
    var recentSearches: [String] =
        UserDefaults.standard.stringArray(forKey: "recentSearches") ?? []
    var searchRequestToken = 0

    // Direct Message picker (opened from the + in the Direct Messages header)
    let dmPickerPanel = RoundedEdgePanel()
    let dmTitleLabel = NSTextField(labelWithString: L10n.string("Direct Messages"))
    let dmCloseButton = RoundedEdgePanel()
    let dmSearchField = NSSearchField()
    let dmScroll = NSScrollView()
    let dmDoc = TimelineFlippedView()
    let dmBottomBar = RoundedEdgePanel()
    let dmSelectionCountLabel = NSTextField(labelWithString: "")
    let dmStartButton = RoundedEdgePanel()
    let dmStartButtonLabel = NSTextField(labelWithString: L10n.string("Go"))
    var dmUsers: [MMUser] = []
    var dmSearchResults: [MMUser] = []
    var selectedDMUserIds: Set<String> = []
    var dmUsersPage: Int = 0
    var dmHasMoreUsers: Bool = true
    var isLoadingDMUsers: Bool = false
    var isDMPickerOpen = false
    var dmAnchorFrame: NSRect = .zero
    var dmSearchWorkItem: DispatchWorkItem?

    // User profile popover
    let profilePopoverPanel = RoundedEdgePanel()
    var isProfilePopoverOpen = false
    var profileAnchorFrame: NSRect = .zero
    var activeProfileUserId: String?

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
    var customStatusDialogHelper: CustomStatusDialogHelper?
    var customStatusExpiresAt: Date? = {
        let timestamp = UserDefaults.standard.double(forKey: "customStatusExpiresAt")
        guard timestamp > 0 else { return nil }
        let date = Date(timeIntervalSince1970: timestamp)
        if date <= Date() {
            UserDefaults.standard.removeObject(forKey: "customStatusEmoji")
            UserDefaults.standard.removeObject(forKey: "customStatusText")
            UserDefaults.standard.removeObject(forKey: "customStatusExpiresAt")
            return nil
        }
        return date
    }()
    var customStatusText: String = {
        let timestamp = UserDefaults.standard.double(forKey: "customStatusExpiresAt")
        if timestamp > 0 && Date(timeIntervalSince1970: timestamp) <= Date() {
            return ""
        }
        return UserDefaults.standard.string(forKey: "customStatusText") ?? ""
    }()
    var customStatusEmoji: String = {
        let timestamp = UserDefaults.standard.double(forKey: "customStatusExpiresAt")
        if timestamp > 0 && Date(timeIntervalSince1970: timestamp) <= Date() {
            return ""
        }
        return UserDefaults.standard.string(forKey: "customStatusEmoji") ?? ""
    }()
    var loadRemoteImagesAutomatically: Bool = {
        UserDefaults.standard.object(forKey: "loadRemoteImagesAutomatically") as? Bool ?? true
    }()
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
    let findChannelLabel = NSTextField(labelWithString: L10n.string("Find channel"))

    struct SidebarItemView {
        let id: String
        let isSelectable: Bool
        var isBotBadge: Bool
        var hasCustomAvatar: Bool
        let row: RoundedEdgePanel
        let leftBar: RoundedEdgePanel
        let iconView: NSImageView
        let label: NSTextField
        let hoverCloseView: NSView?
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
    var totalUnreadThreads = 0
    let memberSearchField = NSSearchField()
    var memberSearchQuery = ""
    var channelMembers: [MMChannelMember] = []
    var teamMembers: [MMTeamMember] = []
    var channelFiles: [MMFileInfo] = []
    var savedPosts: [MMPost] = []
    var mentionPosts: [MMPost] = []
    var pinnedPosts: [MMPost] = []
    var pinnedVisibleLimit = 20
    var filesSearchField = NSSearchField()
    var filesSearchQuery = ""
    var filePreviewImages = BoundedImageCache(countLimit: 200)
    var filePreviewLoading: Set<String> = []
    var settingsAwaitingReconnect = false
    var rhsPageByMode: [String: Int] = [:]
    var rhsHasMoreByMode: [String: Bool] = [:]
    var rhsLoadingByMode: [String: Bool] = [:]
    var rhsRequestTokenByMode: [String: Int] = [:]
    var sidebarCategories: [SidebarCategoryView] = []
    var selectedSidebarItemId: String = "town-square"
    var lastSidebarScrollSelection = ""
    var sidebarCategoryOrderIds: [String] = []

    // Right Chat Panel views
    // 1. Channel Header Bar
    let channelHeaderBorder = RoundedEdgePanel()
    let channelStarButton = RoundedEdgePanel()
    let channelStarIconView = NSImageView()
    var isChannelFavorited = false
    var favoriteChannelIds: Set<String> = []
    var favoriteChannelOrder: [String] = []
    var serverFavoritesCategoryId: String?
    var favoritesCategory: SidebarCategoryView?
    var isFavoritesCollapsed = false
    var teamUnreadById: [String: MMTeamUnread] = [:]
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
    let postsPerPage = TimelinePager.pageSize
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

    struct ActiveAttachmentUpload {
        enum Source {
            case file(URL)
            case data(Data)
        }

        enum State {
            case queued
            case uploading(progress: Double)
            case failed(message: String)
        }

        let id: UUID
        let channelId: String
        let threadRootId: String?
        let name: String
        let size: Int64
        let mimeType: String
        let source: Source
        var state: State

        var isUploading: Bool {
            if case .uploading = state { return true }
            return false
        }

        var isInProgress: Bool {
            switch state {
            case .queued, .uploading:
                return true
            case .failed:
                return false
            }
        }

        var isQueued: Bool {
            if case .queued = state { return true }
            return false
        }

        var currentProgress: Double {
            if case .uploading(let progress) = state { return progress }
            return 0
        }
    }

    /// Composer state is kept per channel so switching conversations cannot send
    /// text or attachments to the wrong channel.
    struct ComposerDraft {
        var text: String
        var attachments: [PendingAttachment]
        var editingPostId: String?
    }

    struct ChannelScrollPosition {
        var postId: String
        var offset: CGFloat
    }

    struct PendingOutgoingPost {
        enum Status {
            case sending
            case failed(String)
        }

        let id: String
        let channelId: String
        let message: String
        let fileIds: [String]
        var status: Status
    }

    var pendingOutgoingPosts: [PendingOutgoingPost] = []
    var savedPostIds: Set<String> = []
    var composerDraftsByChannelId: [String: ComposerDraft] = [:]
    var threadDraftsByRootId: [String: String] = [:]
    var teamSwitchToken = 0
    var lastRightPanelContentWidth: CGFloat = 0
    var channelScrollPositions: [String: ChannelScrollPosition] = [:]
    var typingIndicatorWorkItem: DispatchWorkItem?
    var threadTypingIndicatorWorkItem: DispatchWorkItem?
    var pendingAttachments: [PendingAttachment] = []
    var activeAttachmentUploads: [ActiveAttachmentUpload] = []
    var attachmentUploadTasks: [UUID: Task<Void, Never>] = [:]
    var attachmentSizeLimit = AttachmentUploadPolicy.fallbackLimitBytes
    let maxConcurrentAttachmentUploads = 3
    let completionPanel = RoundedEdgePanel()
    var completionItems: [CompletionItem] = []
    var completionRowViews: [RoundedEdgePanel] = []
    var completionRange = NSRange(location: 0, length: 0)
    var completionKind: CompletionKind = .user
    var completionSelectedIndex = 0
    var isCompletionVisible = false
    var completionUsers: [MMUser] = []
    var completionUsersTeamId: String?
    var completionUsersLoading = false
    var composerBaseHeight: CGFloat { isComposerToolbarVisible ? MMMetric.composerToolbarHeight : MMMetric.composerHeight }
    var composerPendingHeight: CGFloat {
        hasComposerAttachments ? MMMetric.composerAttachmentsHeight : 0
    }
    var composerTotalHeight: CGFloat { composerBaseHeight + composerPendingHeight }
    var hasComposerAttachments: Bool {
        !pendingAttachments.isEmpty
            || activeAttachmentUploads.contains {
                $0.channelId == activeChannelId && $0.threadRootId == nil
            }
    }

    // Live WebService state (owned by the view model; exposed for the views).
    /// Injected by `AppDelegate` when the workspace window is created.
    var webService: WebService? {
        get { viewModel.webService }
        set { viewModel.webService = newValue }
    }
    var currentUser: MMUser? {
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
    var usersById: [String: MMUser] {
        get { viewModel.usersById }
        set { viewModel.usersById = newValue }
    }
    var usersByUsername: [String: MMUser] {
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
    var userAvatarsById = BoundedImageCache()
    var markdownCodeBlockBuffers: [String: String] = [:]
    var linkPreviewsEnabled = UserDefaults.standard.bool(forKey: "linkPreviewsEnabled")
    var linkPreviewsByURL: [String: LinkPreviewMetadata] = [:]
    var linkPreviewLoading: Set<String> = []
    var linkPreviewFailures: Set<String> = []
    var linkPreviewImages = BoundedImageCache(countLimit: 100)
    var linkPreviewImageLoading: Set<String> = []
    var userAvatarFetchTasks: [String: Task<Void, Never>] = [:]
    var composerSendIconView: NSImageView?
    var composerSendEnabled = false
    var lastTypingSentAt: Date?
    var menuAvatarStatusDot: RoundedEdgePanel?
    var statusPollingTimer: Timer?

    override init(contentRect rect: NSRect, styleMask style: NSWindow.StyleMask, backing backingStoreType: NSWindow.BackingStoreType, defer flag: Bool) {

        super.init(contentRect: rect, styleMask: style, backing: backingStoreType, defer: flag)

        self.isReleasedWhenClosed = false
        let initialAppearance = ThemeManager.shared.usesSystemAppearance ? nil : NSAppearance(named: ThemeManager.shared.theme.isDark ? .darkAqua : .aqua)
        self.appearance = initialAppearance
        NSApp.appearance = initialAppearance
        self.backgroundColor = Theme.shared.sidebarTeamBarBg
        self.contentMinSize = NSSize(width: 860, height: 520)

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
        entryView.onImagePasted = { [weak self] data, filename in
            self?.uploadPastedImage(data, filename: filename)
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
            if !searchResultsPanel.isHidden, !isSearchPopoverOpen,
               !event.modifierFlags.contains(.command),
               !(firstResponder is NSTextView), !(firstResponder is NSTextField) {
                switch event.keyCode {
                case 125:
                    moveSearchSelection(by: 1)
                    return
                case 126:
                    moveSearchSelection(by: -1)
                    return
                case 36, 76:
                    if activateSearchSelection() { return }
                default:
                    break
                }
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
                if isProfilePopoverOpen && !profilePopoverPanel.frame.contains(point) && (profileAnchorFrame.isEmpty || !profileAnchorFrame.contains(point)) {
                    closeProfilePopover()
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

    func applyCurrentTheme() {
        let appearance: NSAppearance?
        if ThemeManager.shared.usesSystemAppearance {
            appearance = nil
        } else {
            appearance = NSAppearance(named: ThemeManager.shared.theme.isDark ? .darkAqua : .aqua)
        }
        NSApp.appearance = appearance
        self.appearance = appearance

        backgroundColor = Theme.shared.sidebarTeamBarBg
        mainPanel.color = Theme.shared.sidebarBg
        chatPanel.color = Theme.shared.centerBg
        mainPanel.setNeedsAppearanceUpdate()
        chatPanel.setNeedsAppearanceUpdate()

        teamHeaderButton.color = Theme.shared.sidebarHeaderBg
        teamHeaderLabel.textColor = Theme.shared.sidebarHeaderText
        teamHeaderChevron.contentTintColor = Theme.shared.sidebarHeaderText.withAlphaComponent(0.85)
        teamHeaderButton.setNeedsAppearanceUpdate()

        emojiPanel.appearance = appearance
        emojiSearchField.appearance = appearance
        dmPickerPanel.appearance = appearance
        dmSearchField.appearance = appearance
        reactionPickerPanel.appearance = appearance
        reactionPickerSearchField.appearance = appearance
        profilePopoverPanel.appearance = appearance

        updateSidebarSelectionAppearance()
        updateSidebarBadges()
        rebuildTimelineContent(scrollToBottom: false)
        reloadRightPanelIfNeeded()
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
        var isSectionHeader: Bool = false
        var secondaryActionTitle: String = ""
        var secondaryAction: (() -> Void)? = nil
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

    override func close() {
        statusPollingTimer?.invalidate()
        statusPollingTimer = nil
        super.close()
    }

    deinit {
        NotificationCenter.default.removeObserver(self)
    }
}