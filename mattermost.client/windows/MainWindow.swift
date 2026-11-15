//
//  LoginWindow.swift
//  mattermost.client
//
//  Created by Boris Barbulovski on 31.10.24.
//

import Cocoa
import UniformTypeIdentifiers
import ImageIO
import UniformTypeIdentifiers

private class MainWindowViewController: NSViewController {
    override func loadView() {
        self.view = NSView()
    }

    override func viewDidLoad() {
        super.viewDidLoad()
        // Do view setup here.
    }
}

class MainWindowDelegate: NSObject, NSOutlineViewDelegate {
    
}

class TimelineFlippedView: NSView {
    override var isFlipped: Bool { true }
}

private class TimelineRowView: RoundedEdgePanel {
    override var isFlipped: Bool { true }
}

private class TimelineScrollView: NSScrollView {
    var onScrollWheel: (() -> Void)?

    override func scrollWheel(with event: NSEvent) {
        super.scrollWheel(with: event)
        onScrollWheel?()
    }
}

private class TimelineContainerView: NSView {
    override func hitTest(_ point: NSPoint) -> NSView? {
        let view = super.hitTest(point)
        return (view === self) ? nil : view
    }
}

/// Composer editor that draws its own placeholder so the placeholder never
/// intercepts clicks meant for the text view.
final class ComposerTextView: NSTextView {
    var placeholderString: String = "" {
        didSet { needsDisplay = true }
    }
    var placeholderColor: NSColor = NSColor(red: 153 / 255, green: 153 / 255, blue: 153 / 255, alpha: 1.0) {
        didSet { needsDisplay = true }
    }

    override func draw(_ dirtyRect: NSRect) {
        super.draw(dirtyRect)
        guard string.isEmpty, !placeholderString.isEmpty, let font = font else { return }
        let attributes: [NSAttributedString.Key: Any] = [
            .font: font,
            .foregroundColor: placeholderColor
        ]
        let origin = NSPoint(
            x: textContainerInset.width + (textContainer?.lineFragmentPadding ?? 0),
            y: textContainerInset.height
        )
        placeholderString.draw(at: origin, withAttributes: attributes)
    }
}

class MainWindow: NSWindow, NSTextViewDelegate, NSTextFieldDelegate {
    let mainPanel = RoundedEdgePanel()
    let chatPanel = RoundedEdgePanel()
    let chatEntryPanel = OutlinePanel()
    let mainTreeDelegate = MainWindowDelegate()
    let treeView = NSOutlineView()
    let entryView = ComposerTextView()
    
    let boxImage = NSImageView(image: NSImage(named: NSImage.Name("E82F"))!)
    let logo = NSImageView(image: NSImage(named: NSImage.Name("Mattermost Logo"))!)
    
    // Top Global Bar views
    let sidebarTopBorder = RoundedEdgePanel()
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
    
    // Right-hand side panel (threads / members / pinned posts)
    let rightPanel = RoundedEdgePanel()
    let rightPanelTitle = NSTextField(labelWithString: "Threads")
    let rightPanelCloseButton = RoundedEdgePanel()
    let rightPanelScroll = NSScrollView()
    let rightPanelDoc = TimelineFlippedView()
    private enum RightPanelMode { case threads, members, pinned, mentions, saved, settings, browse }
    private var rightPanelMode: RightPanelMode = .threads
    private var isRightPanelVisible = false
    private var threadItems: [MMThread] = []
    
    // Channel header dropdown menu
    let channelMenu = RoundedEdgePanel()
    private var isChannelMenuOpen = false
    
    // Composer emoji picker
    let emojiPanel = RoundedEdgePanel()
    private var isEmojiPanelOpen = false
    
    // Sidebar filter menu
    let filterMenu = RoundedEdgePanel()
    private var isFilterMenuOpen = false
    private var sidebarFavoritesOnly = false
    private var filterAllCheck: NSImageView?
    private var filterFavoritesCheck: NSImageView?
    
    let avatarButtonPanel = RoundedEdgePanel()
    let avatarPanel = RoundedEdgePanel()
    let avatarImageView = NSImageView()
    let avatarLabel = NSTextField(labelWithString: "B")
    let statusDotPanel = RoundedEdgePanel()
    
    // Product Switcher dropdown menu
    let productSwitcherMenu = RoundedEdgePanel()
    private var isProductMenuOpen = false
    
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
    private var isSearchPopoverOpen = false
    private var isSearchFilesTabSelected = false
    
    // Help popup menu
    let helpMenu = RoundedEdgePanel()
    private var isHelpMenuOpen = false
    
    // User status / profile dropdown menu + Do not disturb submenu
    let statusMenu = RoundedEdgePanel()
    let dndSubMenu = RoundedEdgePanel()
    private weak var dndStatusRow: RoundedEdgePanel?
    private var isStatusMenuOpen = false
    private var isDndSubMenuOpen = false
    private var selectedStatusIndex = 0
    private var statusCheckViews: [NSImageView] = []
    
    // Left Channel Sidebar views
    let teamHeaderButton = RoundedEdgePanel()
    let teamHeaderLabel = NSTextField(labelWithString: "")
    let teamHeaderChevron = NSImageView()
    let teamDropdownMenu = RoundedEdgePanel()
    private var isTeamMenuOpen = false
    private var userTeams: [MMTeam] = []
    let teamAddButton = RoundedEdgePanel()
    let teamAddIconView = NSImageView()
    
    let filterChannelButton = RoundedEdgePanel()
    let filterChannelIconView = NSImageView()
    let findChannelPanel = RoundedEdgePanel()
    let findChannelIconView = NSImageView()
    let findChannelLabel = NSTextField(labelWithString: "Find channel")
    
    private struct SidebarItemView {
        let id: String
        let isSelectable: Bool
        var isBotBadge: Bool
        let row: RoundedEdgePanel
        let leftBar: RoundedEdgePanel
        let iconView: NSImageView
        let label: NSTextField
        let hoverCloseView: NSImageView?
    }
    
    private struct SidebarCategoryView {
        let id: String
        let headerRow: RoundedEdgePanel
        let chevronView: NSImageView
        let titleLabel: NSTextField
        let addButton: RoundedEdgePanel?
        var isCollapsed: Bool
        var items: [SidebarItemView]
    }
    
    private var threadsSidebarItem: SidebarItemView?
    private var sidebarCategories: [SidebarCategoryView] = []
    private var selectedSidebarItemId: String = "town-square"
    
    // Right Chat Panel views
    // 1. Channel Header Bar
    let channelHeaderBorder = RoundedEdgePanel()
    let channelStarButton = RoundedEdgePanel()
    let channelStarIconView = NSImageView()
    private var isChannelFavorited = false
    private var favoriteChannelIds: Set<String> = []
    private var favoritesCategory: SidebarCategoryView?
    private var isFavoritesCollapsed = false
    private var channelFilterQuery: String = ""
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
    let channelSidebarButton = RoundedEdgePanel()
    let channelSidebarIconView = NSImageView()
    let channelInfoButton = RoundedEdgePanel()
    let channelInfoIconView = NSImageView()
    
    // 2. Message Timeline & Welcome Hero
    private let chatTimelineContainer = TimelineContainerView()
    private let timelineScrollView = TimelineScrollView()
    private let timelineDocView = TimelineFlippedView()
    private var currentChannelPosts: [MMPost] = []
    private var lastTimelineWidth: CGFloat = 0
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
    
    let dateSep1LeftLine = RoundedEdgePanel()
    let dateSep1RightLine = RoundedEdgePanel()
    let dateSep1Label = NSTextField(labelWithString: "December 01, 2025")
    let systemMessageRow = RoundedEdgePanel()
    
    let dateSep2LeftLine = RoundedEdgePanel()
    let dateSep2RightLine = RoundedEdgePanel()
    let dateSep2Label = NSTextField(labelWithString: "December 11, 2025")
    let userMessageRow = RoundedEdgePanel()
    let statusPromptPill = RoundedEdgePanel()
    private weak var statusPromptLabelRef: NSTextField?
    private weak var statusPromptIconRef: NSImageView?
    
    // 3. Message Composer & Formatting Toolbar
    let composerPlaceholderLabel = NSTextField(labelWithString: "Write to Town Square")
    private var composerLeftButtons: [RoundedEdgePanel] = []
    private var composerLeftSeparator = RoundedEdgePanel()
    let composerAaButton = RoundedEdgePanel()
    let composerAaChevron = NSImageView()
    private var isComposerToolbarVisible = false
    let composerRightSeparator = RoundedEdgePanel()
    let composerEmojiButton = RoundedEdgePanel()
    let composerGifButton = RoundedEdgePanel()
    let composerAttachButton = RoundedEdgePanel()
    let composerSendButton = RoundedEdgePanel()
    let composerHelpLabel = NSTextField(labelWithString: "Help")
    
    // Live WebService state
    private var currentUser: LoginWebService?
    private var activeTeam: MMTeam?
    private var activeChannelId: String = ""
    private var channelsById: [String: MMChannel] = [:]
    private var channelsByName: [String: MMChannel] = [:]
    private var usersById: [String: LoginWebService] = [:]
    private var usersByUsername: [String: LoginWebService] = [:]
    private var userAvatarsById: [String: NSImage] = [:]
    private var userAvatarFetchTasks: [String: Task<NSImage?, Never>] = [:]
    private var userStatusById: [String: String] = [:]
    private var currentUserStatus: String = "online"
    private var composerSendIconView: NSImageView?
    private var composerSendEnabled = false
    private var lastTypingSentAt: Date?
    private var menuAvatarStatusDot: RoundedEdgePanel?
    private var statusPollingTimer: Timer?
    private var sysAuthorLabelRef: NSTextField?
    private var sysTimeLabelRef: NSTextField?
    private var sysBodyLabelRef: NSTextField?
    private var usrAuthorLabelRef: NSTextField?
    private var usrTimeLabelRef: NSTextField?
    private var usrBodyLabelRef: NSTextField?

    override init(contentRect rect: NSRect, styleMask style: NSWindow.StyleMask, backing backingStoreType: NSWindow.BackingStoreType, defer flag: Bool) {

        super.init(contentRect: rect, styleMask: style, backing: backingStoreType, defer: flag)

        self.isReleasedWhenClosed = false
        self.backgroundColor = NSColor(red: 25 / 255, green: 42 / 255, blue: 77 / 255, alpha: 1)
        
        self.title = "Mattermost"
        self.contentViewController = MainWindowViewController()
        self.setContentSize(NSSize(width: rect.width, height: rect.height))
        self.center()
        // Restore the user's last window frame when one is stored; otherwise the
        // default 1440x783 content size from AppDelegate is used.
        self.setFrameAutosaveName("MainWindowFrame")

        mainPanel.color = NSColor(red: 30 / 255, green: 50 / 255, blue: 92 / 255, alpha: 1)
        mainPanel.cornerRadius = 8
        sidebarTopBorder.color = NSColor(white: 1.0, alpha: 0.10)
        sidebarTopBorder.cornerRadius = 0
        
        entryView.backgroundColor = .clear
        entryView.drawsBackground = false
        entryView.isEditable = true
        entryView.isSelectable = true
        entryView.isRichText = false
        entryView.allowsUndo = true
        entryView.isHidden = false
        entryView.font = MMFont.font(ofSize: 14)
        entryView.textColor = NSColor(red: 63 / 255, green: 67 / 255, blue: 80 / 255, alpha: 1.0)
        entryView.insertionPointColor = NSColor(red: 28 / 255, green: 88 / 255, blue: 217 / 255, alpha: 1.0)
        entryView.textContainerInset = NSSize(width: 0, height: 13)
        entryView.textContainer?.lineFragmentPadding = 0
        entryView.delegate = self
        entryView.placeholderString = "Write to Town Square"
        
        chatEntryPanel.color = NSColor(red: 63 / 255, green: 67 / 255, blue: 80 / 255, alpha: 0.16)
        chatEntryPanel.cornerRadius = 4
        chatEntryPanel.borderWidth = 2
        chatPanel.addSubview(chatEntryPanel)
        chatEntryPanel.addSubview(entryView)
        
        treeView.delegate = mainTreeDelegate
        treeView.isHidden = true
        
        mainPanel.addSubview(treeView)
        mainPanel.addSubview(sidebarTopBorder)
        
        contentView?.addSubview(mainPanel)

        chatPanel.color = .white
        chatPanel.cornerRadius = 8
        contentView?.addSubview(chatPanel)
        
        setupLeftChannelSidebar()
        setupRightChatPanel()
        setupTopGlobalBar()

        updateViews()
        applyZoomFactor(ZoomManager.shared.currentZoomFactor)
        self.makeKeyAndOrderFront(nil)
        
        NotificationCenter.default.addObserver(self, selector: #selector(windowDidResize), name: NSWindow.didResizeNotification, object: self)
        NotificationCenter.default.addObserver(self, selector: #selector(zoomDidChangeNotification), name: .zoomFactorDidChange, object: nil)
        NotificationCenter.default.addObserver(self, selector: #selector(appDidBecomeActive), name: NSApplication.didBecomeActiveNotification, object: nil)
        bindWebServiceAndLoadData()
    }
    
    private func setupTopGlobalBar() {
        // Web client: header icons/text sit at 56% white, the search field at 64%.
        let topBarTint = NSColor(white: 1.0, alpha: 0.56)
        let searchTint = NSColor(white: 1.0, alpha: 0.64)
        let hoverBg = NSColor(white: 1.0, alpha: 0.08)
        
        // Left: Product switcher container (grid icon + Mattermost logo + TEAM EDITION badge)
        productSwitcherPanel.color = .clear
        productSwitcherPanel.cornerRadius = 4
        
        boxImage.imageScaling = .scaleProportionallyUpOrDown
        boxImage.alphaValue = 0.72
        logo.imageScaling = .scaleProportionallyUpOrDown
        logo.alphaValue = 0.94
        
        editionBadgePanel.color = NSColor(white: 1.0, alpha: 0.08)
        editionBadgePanel.cornerRadius = 4
        editionBadgeLabel.font = MMFont.font(ofSize: 10, weight: .semibold)
        editionBadgeLabel.textColor = NSColor(white: 1.0, alpha: 0.75)
        editionBadgeLabel.alignment = .center
        editionBadgeLabel.isEditable = false
        editionBadgeLabel.isSelectable = false
        editionBadgePanel.addSubview(editionBadgeLabel)
        
        productSwitcherPanel.addSubview(boxImage)
        productSwitcherPanel.addSubview(logo)
        productSwitcherPanel.addSubview(editionBadgePanel)
        productSwitcherPanel.onHoverChanged = { [weak self] _ in
            self?.updateProductSwitcherAppearance()
        }
        productSwitcherPanel.onClick = { [weak self] in
            self?.toggleProductSwitcherMenu()
        }
        contentView?.addSubview(productSwitcherPanel)
        
        // Center: Search bar (non-editable trigger, no caret) + Help (?) button
        searchPanel.color = NSColor(white: 1.0, alpha: 0.08)
        searchPanel.cornerRadius = 4
        if let searchImg = NSImage(systemSymbolName: "magnifyingglass", accessibilityDescription: "Search") {
            searchIconView.image = searchImg.withSymbolConfiguration(.init(pointSize: 12, weight: .medium))
            searchIconView.contentTintColor = searchTint
        }
        searchLabel.font = MMFont.font(ofSize: 12, weight: .medium)
        searchLabel.textColor = searchTint
        searchLabel.isEditable = false
        searchLabel.isSelectable = false
        searchPanel.addSubview(searchIconView)
        searchPanel.addSubview(searchLabel)
        searchPanel.onHoverChanged = { [weak self] isHovered in
            guard let self = self else { return }
            self.searchPanel.color = NSColor(white: 1.0, alpha: isHovered ? 0.12 : 0.08)
            self.searchPanel.setNeedsAppearanceUpdate()
            self.searchIconView.contentTintColor = isHovered ? .white : searchTint
            self.searchLabel.textColor = isHovered ? .white : searchTint
        }
        searchPanel.onClick = { [weak self] in
            self?.toggleSearchPopover()
        }
        contentView?.addSubview(searchPanel)
        
        helpPanel.color = .clear
        helpPanel.cornerRadius = 4
        if let helpImg = NSImage(systemSymbolName: "questionmark.circle", accessibilityDescription: "Help") {
            helpIconView.image = helpImg.withSymbolConfiguration(.init(pointSize: 14, weight: .regular))
            helpIconView.contentTintColor = topBarTint
        }
        helpPanel.addSubview(helpIconView)
        helpPanel.onHoverChanged = { [weak self] _ in
            self?.updateHelpButtonAppearance()
        }
        helpPanel.onClick = { [weak self] in
            self?.toggleHelpMenu()
        }
        contentView?.addSubview(helpPanel)
        
        // Right action buttons (@, Bookmark, Settings)
        configureIconButton(
            panel: mentionsPanel,
            iconView: mentionsIconView,
            symbolName: "at",
            pointSize: 14,
            accessibilityDescription: "Recent Mentions",
            defaultTint: topBarTint,
            hoverBg: hoverBg,
            onClick: { [weak self] in
                self?.toggleRightPanel(mode: .mentions)
            }
        )
        configureIconButton(
            panel: savedPostsPanel,
            iconView: savedPostsIconView,
            symbolName: "bookmark",
            pointSize: 13,
            accessibilityDescription: "Saved Posts",
            defaultTint: topBarTint,
            hoverBg: hoverBg,
            onClick: { [weak self] in
                self?.toggleRightPanel(mode: .saved)
            }
        )
        configureIconButton(
            panel: settingsPanel,
            iconView: settingsIconView,
            symbolName: "gearshape",
            pointSize: 14,
            accessibilityDescription: "Settings",
            defaultTint: topBarTint,
            hoverBg: hoverBg,
            onClick: { [weak self] in
                self?.toggleRightPanel(mode: .settings)
            }
        )
        
        // User avatar circle + online status indicator dot
        avatarButtonPanel.color = .clear
        avatarButtonPanel.cornerRadius = 4
        // The status badge intentionally overhangs the avatar's bottom-right corner,
        // so let it render outside the rounded hover container.
        avatarButtonPanel.clipContentToBounds = false
        
        let initial = (UserDefaults.standard.string(forKey: "username")?.first).map { String($0).uppercased() } ?? "B"
        avatarLabel.stringValue = initial
        avatarLabel.font = MMFont.font(ofSize: 10, weight: .semibold)
        avatarLabel.textColor = .white
        avatarLabel.alignment = .center
        
        avatarPanel.color = NSColor(red: 224 / 255, green: 208 / 255, blue: 71 / 255, alpha: 1.0)
        avatarPanel.cornerRadius = 12
        avatarPanel.addSubview(avatarLabel)
        
        avatarImageView.imageScaling = .scaleProportionallyUpOrDown
        avatarImageView.frame = NSRect(x: 0, y: 0, width: 24, height: 24)
        avatarImageView.isHidden = true
        avatarPanel.addSubview(avatarImageView)
        
        statusDotPanel.color = statusColor(for: currentUserStatus)
        statusDotPanel.cornerRadius = 8
        statusDotPanel.borderWidth = 1.35
        statusDotPanel.borderColor = NSColor(red: 22 / 255, green: 37 / 255, blue: 69 / 255, alpha: 1.0)
        
        avatarButtonPanel.addSubview(avatarPanel)
        avatarButtonPanel.addSubview(statusDotPanel)
        avatarButtonPanel.onHoverChanged = { [weak self] _ in
            self?.updateAvatarButtonAppearance()
        }
        avatarButtonPanel.onClick = { [weak self] in
            self?.toggleStatusMenu()
        }
        contentView?.addSubview(avatarButtonPanel)
        
        setupProductSwitcherMenu()
        setupSearchPopover()
        setupSearchResultsPanel()
        setupHelpMenu()
        setupStatusMenu()
    }
    
    private func updateProductSwitcherAppearance() {
        let active = productSwitcherPanel.isHovered || isProductMenuOpen
        let hoverBg = NSColor(white: 1.0, alpha: 0.08)
        productSwitcherPanel.color = active ? hoverBg : .clear
        productSwitcherPanel.setNeedsAppearanceUpdate()
        boxImage.alphaValue = active ? 1.0 : 0.72
        logo.alphaValue = active ? 1.0 : 0.94
        editionBadgePanel.color = NSColor(white: 1.0, alpha: active ? 0.16 : 0.12)
        editionBadgePanel.setNeedsAppearanceUpdate()
        editionBadgeLabel.textColor = active ? .white : NSColor(white: 1.0, alpha: 0.72)
    }
    
    private func updateHelpButtonAppearance() {
        let active = helpPanel.isHovered || isHelpMenuOpen
        let topBarTint = NSColor(white: 1.0, alpha: 0.64)
        let activeBg = NSColor(white: 1.0, alpha: isHelpMenuOpen ? 0.12 : 0.08)
        helpPanel.color = active ? activeBg : .clear
        helpPanel.setNeedsAppearanceUpdate()
        helpIconView.contentTintColor = active ? .white : topBarTint
    }
    
    private func updateAvatarButtonAppearance() {
        let active = avatarButtonPanel.isHovered || isStatusMenuOpen
        avatarButtonPanel.color = active ? NSColor(white: 1.0, alpha: 0.14) : .clear
        avatarButtonPanel.setNeedsAppearanceUpdate()
    }
    
    private func toggleProductSwitcherMenu() {
        if !isProductMenuOpen {
            setTeamMenuOpen(false)
            setSearchPopoverOpen(false)
            setHelpMenuOpen(false)
            setStatusMenuOpen(false)
        }
        setProductSwitcherMenuOpen(!isProductMenuOpen)
    }
    
    private func setProductSwitcherMenuOpen(_ open: Bool) {
        guard isProductMenuOpen != open else { return }
        isProductMenuOpen = open
        productSwitcherMenu.isHidden = !open
        updateProductSwitcherAppearance()
    }
    
    private func toggleSearchPopover() {
        if !isSearchPopoverOpen {
            setTeamMenuOpen(false)
            setProductSwitcherMenuOpen(false)
            setHelpMenuOpen(false)
            setStatusMenuOpen(false)
        }
        setSearchPopoverOpen(!isSearchPopoverOpen)
    }
    
    private func setSearchPopoverOpen(_ open: Bool) {
        guard isSearchPopoverOpen != open else { return }
        isSearchPopoverOpen = open
        searchPopoverPanel.isHidden = !open
        if open {
            makeFirstResponder(searchPopoverInputLabel)
        }
    }
    
    private func toggleHelpMenu() {
        if !isHelpMenuOpen {
            setTeamMenuOpen(false)
            setProductSwitcherMenuOpen(false)
            setSearchPopoverOpen(false)
            setStatusMenuOpen(false)
        }
        setHelpMenuOpen(!isHelpMenuOpen)
    }
    
    private func setHelpMenuOpen(_ open: Bool) {
        guard isHelpMenuOpen != open else { return }
        isHelpMenuOpen = open
        helpMenu.isHidden = !open
        updateHelpButtonAppearance()
    }
    
    private func toggleStatusMenu() {
        if !isStatusMenuOpen {
            setTeamMenuOpen(false)
            setProductSwitcherMenuOpen(false)
            setSearchPopoverOpen(false)
            setHelpMenuOpen(false)
        }
        DebugLog.log("toggleStatusMenu, will set to: \(!isStatusMenuOpen)")
        setStatusMenuOpen(!isStatusMenuOpen)
    }
    
    private func setStatusMenuOpen(_ open: Bool) {
        guard isStatusMenuOpen != open else { return }
        DebugLog.log("setStatusMenuOpen: \(open)")
        isStatusMenuOpen = open
        statusMenu.isHidden = !open
        if !open {
            setDndSubMenuOpen(false)
        }
        updateAvatarButtonAppearance()
    }
    
    private func toggleTeamMenu() {
        setTeamMenuOpen(!isTeamMenuOpen)
    }
    
    private func setTeamMenuOpen(_ open: Bool) {
        guard isTeamMenuOpen != open else { return }
        isTeamMenuOpen = open
        teamDropdownMenu.isHidden = !open
        if open {
            setProductSwitcherMenuOpen(false)
            setSearchPopoverOpen(false)
            setHelpMenuOpen(false)
            setStatusMenuOpen(false)
            rebuildTeamMenu()
        }
    }
    
    private func setDndSubMenuOpen(_ open: Bool) {
        guard isDndSubMenuOpen != open else { return }
        isDndSubMenuOpen = open
        dndSubMenu.isHidden = !open
        let rowHoverBg = NSColor(red: 243 / 255, green: 244 / 255, blue: 246 / 255, alpha: 1.0)
        if let dndRow = dndStatusRow {
            dndRow.color = (open || dndRow.isHovered) ? rowHoverBg : .clear
            dndRow.setNeedsAppearanceUpdate()
        }
    }
    
    private func scheduleDndHoverCheck() {
        DispatchQueue.main.asyncAfter(deadline: .now() + 0.05) { [weak self] in
            guard let self = self, self.isDndSubMenuOpen, let contentView = self.contentView else { return }
            let mouseInWindow = self.mouseLocationOutsideOfEventStream
            let point = contentView.convert(mouseInWindow, from: nil)
            let inSubMenu = self.dndSubMenu.frame.insetBy(dx: -4, dy: -4).contains(point)
            let inDndRow: Bool = {
                guard let dndRow = self.dndStatusRow else { return false }
                let rowInContent = contentView.convert(dndRow.frame, from: self.statusMenu)
                return rowInContent.insetBy(dx: -4, dy: -2).contains(point)
            }()
            if !inSubMenu && !inDndRow {
                self.setDndSubMenuOpen(false)
            }
        }
    }
    
    private func statusColor(for status: String) -> NSColor {
        switch status.lowercased() {
        case "online":
            return NSColor(red: 99 / 255, green: 182 / 255, blue: 138 / 255, alpha: 1.0)
        case "away":
            return NSColor(red: 245 / 255, green: 171 / 255, blue: 0 / 255, alpha: 1.0)
        case "dnd":
            return NSColor(red: 210 / 255, green: 75 / 255, blue: 78 / 255, alpha: 1.0)
        case "offline":
            return NSColor(red: 156 / 255, green: 163 / 255, blue: 175 / 255, alpha: 1.0)
        default:
            return NSColor(red: 61 / 255, green: 184 / 255, blue: 135 / 255, alpha: 1.0)
        }
    }
    
    private func statusString(for index: Int) -> String {
        switch index {
        case 0: return "online"
        case 1: return "away"
        case 2: return "dnd"
        case 3: return "offline"
        default: return "online"
        }
    }
    
    /// Draws the Mattermost presence glyph inside a status dot:
    /// online = check, away = clock, do-not-disturb = minus, offline = no glyph.
    private func updateStatusCheck(in dot: RoundedEdgePanel, status: String) {
        dot.subviews
            .filter { $0.identifier?.rawValue == "statusCheck" }
            .forEach { $0.removeFromSuperview() }
        guard dot.bounds.width > 0 else { return }
        
        let symbolName: String?
        switch status.lowercased() {
        case "online": symbolName = "checkmark"
        case "away": symbolName = "clock"
        case "dnd": symbolName = "minus"
        default: symbolName = nil
        }
        guard let symbolName = symbolName,
              let image = NSImage(systemSymbolName: symbolName, accessibilityDescription: nil) else { return }
        
        let inset = max(2, dot.bounds.width * 0.16)
        let glyph = NSImageView(frame: dot.bounds.insetBy(dx: inset, dy: inset))
        glyph.identifier = NSUserInterfaceItemIdentifier("statusCheck")
        let glyphSize = max(5, dot.bounds.width * 0.58)
        glyph.image = image.withSymbolConfiguration(.init(pointSize: glyphSize, weight: .bold))
        glyph.contentTintColor = .white
        glyph.imageScaling = .scaleProportionallyUpOrDown
        dot.addSubview(glyph)
    }
    
    private func indexForStatus(_ status: String) -> Int {
        switch status.lowercased() {
        case "online": return 0
        case "away": return 1
        case "dnd": return 2
        case "offline": return 3
        default: return 0
        }
    }
    
    private func selectUserStatus(_ index: Int, dndEndTime: Int64? = nil) {
        selectedStatusIndex = index
        for (i, checkView) in statusCheckViews.enumerated() {
            checkView.isHidden = (i != index)
        }
        let statStr = statusString(for: index)
        currentUserStatus = statStr
        if let currentId = currentUser?.id {
            userStatusById[currentId] = statStr
        }
        userStatusById["usr"] = statStr
        userStatusById["sample_usr"] = statStr
        
        let color = statusColor(for: statStr)
        statusDotPanel.color = color
        statusDotPanel.setNeedsAppearanceUpdate()
        updateStatusCheck(in: statusDotPanel, status: statStr)
        menuAvatarStatusDot?.color = color
        menuAvatarStatusDot?.setNeedsAppearanceUpdate()
        
        updateChatWidgetUserStatus(userId: currentUser?.id ?? "usr", status: statStr)
        
        setStatusMenuOpen(false)
        setDndSubMenuOpen(false)
        
        if let ws = (NSApp.delegate as? AppDelegate)?.webService, ws.isLogged() {
            let targetUserId = currentUser?.id ?? ws.currentUserId
            DebugLog.log("selectUserStatus: index=\(index), statStr=\(statStr), targetUserId=\(targetUserId), dndEndTime=\(String(describing: dndEndTime))")
            Task {
                do {
                    let updated = try await ws.updateUserStatus(userId: targetUserId, status: statStr, dndEndTime: dndEndTime)
                    DebugLog.log("Successfully updated user status on backend for \(targetUserId) to \(updated.status)")
                } catch {
                    DebugLog.log("Failed to update user status on server: \(error)")
                }
            }
        } else {
            DebugLog.log("selectUserStatus: ws is not logged or nil!")
        }
    }
    
    private func updateChatWidgetUserStatus(userId: String, status: String) {
        userStatusById[userId] = status
        let color = statusColor(for: status)
        let isForCurrent = (userId == (currentUser?.id ?? "usr") || userId == "usr" || userId == "sample_usr")
        if isForCurrent {
            currentUserStatus = status
        }
        var updatedCount = 0
        func updateInView(_ view: NSView) {
            for subview in view.subviews {
                if let raw = subview.identifier?.rawValue {
                    if (isForCurrent && raw == "statusDot_currentUser") ||
                        raw == "statusDot_\(userId)" {
                        if let dotPanel = subview as? RoundedEdgePanel {
                            dotPanel.color = color
                            dotPanel.setNeedsAppearanceUpdate()
                            self.updateStatusCheck(in: dotPanel, status: status)
                            updatedCount += 1
                        }
                    }
                }
                updateInView(subview)
            }
        }
        updateInView(timelineDocView)
        DebugLog.log("updateChatWidgetUserStatus: userId=\(userId), status=\(status), updatedDotsCount=\(updatedCount)")
    }
    
    // MARK: - Search results
    
    private func setupSearchResultsPanel() {
        let dividerColor = NSColor(red: 229 / 255, green: 231 / 255, blue: 235 / 255, alpha: 1.0)
        searchResultsPanel.color = .white
        searchResultsPanel.cornerRadius = 10
        searchResultsPanel.borderWidth = 1
        searchResultsPanel.borderColor = dividerColor
        searchResultsPanel.shadowColor = .black
        searchResultsPanel.shadowOpacity = 0.18
        searchResultsPanel.shadowRadius = 16
        searchResultsPanel.shadowOffset = CGSize(width: 0, height: -6)
        searchResultsPanel.isHidden = true
        
        searchResultsTitle.font = MMFont.font(ofSize: 13, weight: .semibold)
        searchResultsTitle.textColor = NSColor(red: 31 / 255, green: 41 / 255, blue: 55 / 255, alpha: 1.0)
        searchResultsTitle.isEditable = false
        searchResultsTitle.isSelectable = false
        searchResultsPanel.addSubview(searchResultsTitle)
        
        searchResultsCloseButton.cornerRadius = 4
        searchResultsCloseButton.color = .clear
        let closeIcon = NSImageView()
        if let img = NSImage(systemSymbolName: "xmark", accessibilityDescription: "Close search") {
            closeIcon.image = img.withSymbolConfiguration(.init(pointSize: 10, weight: .semibold))
            closeIcon.contentTintColor = NSColor(red: 107 / 255, green: 114 / 255, blue: 128 / 255, alpha: 1.0)
        }
        closeIcon.frame = NSRect(x: 5, y: 5, width: 12, height: 12)
        searchResultsCloseButton.addSubview(closeIcon)
        searchResultsCloseButton.onClick = { [weak self] in
            self?.closeSearchResults()
        }
        searchResultsPanel.addSubview(searchResultsCloseButton)
        
        searchResultsScroll.drawsBackground = false
        searchResultsScroll.hasVerticalScroller = true
        searchResultsScroll.autohidesScrollers = true
        searchResultsScroll.documentView = searchResultsDoc
        searchResultsPanel.addSubview(searchResultsScroll)
        
        contentView?.addSubview(searchResultsPanel)
    }
    
    @objc private func performSearchFromPopover() {
        let terms = searchPopoverInputLabel.stringValue.trimmingCharacters(in: .whitespacesAndNewlines)
        guard !terms.isEmpty, let team = activeTeam else { return }
        setSearchPopoverOpen(false)
        searchResultsTitle.stringValue = "Searching…"
        searchResultsDoc.subviews.forEach { $0.removeFromSuperview() }
        searchResultsDoc.frame = NSRect(x: 0, y: 0, width: searchResultsPanel.bounds.width, height: 1)
        searchResultsPanel.isHidden = false
        
        Task { @MainActor [weak self] in
            guard let self = self, let ws = (NSApp.delegate as? AppDelegate)?.webService else { return }
            do {
                let list = try await ws.searchPosts(teamId: team.id, terms: terms)
                let posts = list.order.compactMap { list.posts[$0] }
                let missingUserIds = Array(Set(posts.map { $0.user_id }).subtracting(self.usersById.keys))
                if !missingUserIds.isEmpty, let users = try? await ws.fetchUsersByIds(missingUserIds) {
                    for user in users {
                        self.usersById[user.id] = user
                    }
                }
                self.presentSearchResults(posts, terms: terms)
            } catch {
                self.presentSearchResults([], terms: terms)
            }
        }
    }
    
    private func presentSearchResults(_ posts: [MMPost], terms: String) {
        searchResultsDoc.subviews.forEach { $0.removeFromSuperview() }
        searchResultsTitle.stringValue = posts.isEmpty
            ? "No results for “\(terms)”"
            : "\(posts.count) result\(posts.count == 1 ? "" : "s") for “\(terms)”"
        
        let width = searchResultsPanel.bounds.width
        let rowHeight: CGFloat = 54
        let inset: CGFloat = 8
        var y: CGFloat = 0
        for post in posts.prefix(50) {
            let row = makeSearchResultRow(post, width: width - inset * 2)
            row.frame = NSRect(x: inset, y: y + 2, width: width - inset * 2, height: rowHeight - 4)
            searchResultsDoc.addSubview(row)
            y += rowHeight
        }
        searchResultsDoc.frame = NSRect(x: 0, y: 0, width: width, height: max(y, 1))
        searchResultsScroll.frame = NSRect(x: 0, y: 0, width: width, height: max(0, searchResultsPanel.bounds.height - 44))
    }
    
    private func makeSearchResultRow(_ post: MMPost, width: CGFloat) -> RoundedEdgePanel {
        let row = RoundedEdgePanel()
        row.color = .clear
        row.cornerRadius = 6
        
        let author = usersById[post.user_id]?.username ?? "Unknown"
        let channelName = channelsById[post.channel_id].map { channelDisplayName(for: $0) } ?? ""
        let formatter = DateFormatter()
        formatter.dateFormat = "MMM d, h:mm a"
        let when = formatter.string(from: Date(timeIntervalSince1970: TimeInterval(post.create_at) / 1000))
        let meta = [author, channelName, when].filter { !$0.isEmpty }.joined(separator: " · ")
        
        let metaLabel = NSTextField(labelWithString: meta)
        metaLabel.font = MMFont.font(ofSize: 12, weight: .semibold)
        metaLabel.textColor = NSColor(red: 107 / 255, green: 114 / 255, blue: 128 / 255, alpha: 1.0)
        metaLabel.isEditable = false
        metaLabel.isSelectable = false
        metaLabel.lineBreakMode = .byTruncatingTail
        metaLabel.frame = NSRect(x: 12, y: 6, width: width - 24, height: 16)
        row.addSubview(metaLabel)
        
        let snippetText = post.message.replacingOccurrences(of: "\n", with: " ")
        let snippet = NSTextField(labelWithString: snippetText)
        snippet.font = MMFont.font(ofSize: 13)
        snippet.textColor = NSColor(red: 63 / 255, green: 67 / 255, blue: 80 / 255, alpha: 0.9)
        snippet.isEditable = false
        snippet.isSelectable = false
        snippet.lineBreakMode = .byTruncatingTail
        snippet.frame = NSRect(x: 12, y: 26, width: width - 24, height: 18)
        row.addSubview(snippet)
        
        row.onHoverChanged = { [weak row] isHovered in
            row?.color = isHovered
                ? NSColor(red: 243 / 255, green: 244 / 255, blue: 246 / 255, alpha: 1.0)
                : .clear
            row?.setNeedsAppearanceUpdate()
        }
        row.onClick = { [weak self] in
            self?.openSearchResult(post)
        }
        return row
    }
    
    private func openSearchResult(_ post: MMPost) {
        closeSearchResults()
        guard let channel = channelsById[post.channel_id] else { return }
        selectedSidebarItemId = channel.id
        updateSidebarSelectionAppearance()
        loadChannelPosts(forSidebarItemId: channel.id)
    }
    
    private func closeSearchResults() {
        searchResultsPanel.isHidden = true
        searchResultsDoc.subviews.forEach { $0.removeFromSuperview() }
    }
    
    // MARK: - Channel favorites
    
    private func loadFavoriteChannels() {
        guard let ws = (NSApp.delegate as? AppDelegate)?.webService, ws.isLogged() else { return }
        let userId = currentUser?.id ?? ws.currentUserId
        guard !userId.isEmpty else { return }
        Task { @MainActor [weak self] in
            guard let self = self else { return }
            if let preferences = try? await ws.fetchUserPreferences(userId: userId) {
                let favorites = preferences
                    .filter { $0["category"] == "favorite_channel" }
                    .compactMap { $0["name"] }
                self.favoriteChannelIds = Set(favorites)
                self.refreshFavoriteState()
                self.rebuildFavoritesCategory()
            }
        }
    }
    
    private func refreshFavoriteState() {
        guard !activeChannelId.isEmpty else { return }
        isChannelFavorited = favoriteChannelIds.contains(activeChannelId)
        let symbol = isChannelFavorited ? "star.fill" : "star"
        if let image = NSImage(systemSymbolName: symbol, accessibilityDescription: "Favorite") {
            channelStarIconView.image = image.withSymbolConfiguration(.init(pointSize: 12.5, weight: .medium))
        }
        let starGold = NSColor(red: 245 / 255, green: 171 / 255, blue: 0 / 255, alpha: 1.0)
        let muted = NSColor(red: 107 / 255, green: 114 / 255, blue: 128 / 255, alpha: 1.0)
        let dark = NSColor(red: 31 / 255, green: 41 / 255, blue: 55 / 255, alpha: 1.0)
        channelStarIconView.contentTintColor = isChannelFavorited
            ? starGold
            : (channelStarButton.isHovered ? dark : muted)
    }
    
    private func setChannelFavorite(_ favorite: Bool, channelId: String) {
        guard let ws = (NSApp.delegate as? AppDelegate)?.webService, ws.isLogged() else { return }
        let userId = currentUser?.id ?? ws.currentUserId
        guard !userId.isEmpty else { return }
        
        if favorite {
            favoriteChannelIds.insert(channelId)
        } else {
            favoriteChannelIds.remove(channelId)
        }
        refreshFavoriteState()
        rebuildFavoritesCategory()
        
        let preference: [[String: String]] = [[
            "user_id": userId,
            "category": "favorite_channel",
            "name": channelId,
            "value": ""
        ]]
        Task {
            do {
                if favorite {
                    try await ws.saveUserPreferences(userId: userId, preferences: preference)
                } else {
                    try await ws.deleteUserPreferences(userId: userId, preferences: preference)
                }
            } catch {
                NSLog("Failed to update favorite for \(channelId): \(error.localizedDescription)")
            }
        }
    }
    
    // MARK: - Favorites branch
    
    /// Mirrors the web client: favorited channels move into a dedicated
    /// "Favorites" group at the top of the sidebar and are removed from their
    /// original category until unfavorited.
    private func rebuildFavoritesCategory() {
        if let old = favoritesCategory {
            old.headerRow.removeFromSuperview()
            old.items.forEach { $0.row.removeFromSuperview() }
            favoritesCategory = nil
        }
        
        let channels = favoriteChannelIds
            .compactMap { channelsById[$0] }
            .sorted { channelDisplayName(for: $0).localizedCaseInsensitiveCompare(channelDisplayName(for: $1)) == .orderedAscending }
        
        guard !channels.isEmpty else {
            layoutLeftSidebar(topBarY: mainPanel.bounds.height)
            return
        }
        
        let items = channels.map { ch -> SidebarItemView in
            let symbol: String
            switch ch.type {
            case "P": symbol = "lock.fill"
            case "D": symbol = "person.crop.circle"
            default: symbol = "globe"
            }
            return createSidebarItem(
                id: ch.id,
                symbolName: symbol,
                title: channelDisplayName(for: ch),
                isSelectable: true,
                isBotBadge: false,
                showsCloseOnHover: false
            )
        }
        
        let category = createSidebarCategory(
            id: "favorites",
            title: "FAVORITES",
            showsAddButton: false,
            items: items,
            isCollapsed: isFavoritesCollapsed
        )
        category.headerRow.onClick = { [weak self] in
            guard let self = self else { return }
            self.isFavoritesCollapsed.toggle()
            self.layoutLeftSidebar(topBarY: self.mainPanel.bounds.height)
        }
        favoritesCategory = category
        updateSidebarSelectionAppearance()
        layoutLeftSidebar(topBarY: mainPanel.bounds.height)
    }
    
    private func updateSearchTabsAppearance() {
        let brandBlue = NSColor(red: 28 / 255, green: 88 / 255, blue: 217 / 255, alpha: 1.0)
        let activeTabBg = NSColor(red: 28 / 255, green: 88 / 255, blue: 217 / 255, alpha: 0.12)
        let hoverTabBg = NSColor(red: 243 / 255, green: 244 / 255, blue: 246 / 255, alpha: 1.0)
        let mutedText = NSColor(red: 107 / 255, green: 114 / 255, blue: 128 / 255, alpha: 1.0)
        
        if isSearchFilesTabSelected {
            messagesTabPanel.color = messagesTabPanel.isHovered ? hoverTabBg : .clear
            messagesTabLabel.textColor = mutedText
            filesTabPanel.color = activeTabBg
            filesTabLabel.textColor = brandBlue
            searchPopoverInputLabel.placeholderString = "Search files"
        } else {
            messagesTabPanel.color = activeTabBg
            messagesTabLabel.textColor = brandBlue
            filesTabPanel.color = filesTabPanel.isHovered ? hoverTabBg : .clear
            filesTabLabel.textColor = mutedText
            searchPopoverInputLabel.placeholderString = "Search messages"
        }
        messagesTabPanel.setNeedsAppearanceUpdate()
        filesTabPanel.setNeedsAppearanceUpdate()
    }
    
    private func setupSearchPopover() {
        let popoverWidth: CGFloat = 400
        let popoverHeight: CGFloat = 122
        let brandBlue = NSColor(red: 28 / 255, green: 88 / 255, blue: 217 / 255, alpha: 1.0)
        let mutedText = NSColor(red: 107 / 255, green: 114 / 255, blue: 128 / 255, alpha: 1.0)
        let placeholderColor = NSColor(red: 156 / 255, green: 163 / 255, blue: 175 / 255, alpha: 1.0)
        let dividerColor = NSColor(red: 229 / 255, green: 231 / 255, blue: 235 / 255, alpha: 1.0)
        let pillBg = NSColor(red: 243 / 255, green: 244 / 255, blue: 246 / 255, alpha: 1.0)
        let pillHoverBg = NSColor(red: 229 / 255, green: 231 / 255, blue: 235 / 255, alpha: 1.0)
        let pillText = NSColor(red: 75 / 255, green: 85 / 255, blue: 99 / 255, alpha: 1.0)
        
        searchPopoverPanel.color = .white
        searchPopoverPanel.cornerRadius = 8
        searchPopoverPanel.borderWidth = 1
        searchPopoverPanel.borderColor = dividerColor
        searchPopoverPanel.shadowColor = .black
        searchPopoverPanel.shadowOpacity = 0.18
        searchPopoverPanel.shadowRadius = 12
        searchPopoverPanel.shadowOffset = CGSize(width: 0, height: -4)
        searchPopoverPanel.isHidden = true
        
        // Row 1: Messages & Files tabs + Close (X) button
        let tabFont = MMFont.font(ofSize: 11, weight: .semibold)
        let tabH: CGFloat = 22
        
        messagesTabLabel.font = tabFont
        messagesTabLabel.alignment = .center
        let msgSize = ("Messages" as NSString).size(withAttributes: [.font: tabFont])
        let msgPadH: CGFloat = 8
        let msgW = ceil(msgSize.width) + (msgPadH * 2)
        messagesTabPanel.cornerRadius = 4
        messagesTabPanel.frame = NSRect(x: 16, y: popoverHeight - 31, width: msgW, height: tabH)
        messagesTabLabel.frame = NSRect(x: 0, y: (tabH - 16) / 2, width: msgW, height: 16)
        messagesTabPanel.addSubview(messagesTabLabel)
        messagesTabPanel.onHoverChanged = { [weak self] _ in
            self?.updateSearchTabsAppearance()
        }
        messagesTabPanel.onClick = { [weak self] in
            self?.isSearchFilesTabSelected = false
            self?.updateSearchTabsAppearance()
        }
        searchPopoverPanel.addSubview(messagesTabPanel)
        
        filesTabLabel.font = tabFont
        filesTabLabel.alignment = .center
        let filesSize = ("Files" as NSString).size(withAttributes: [.font: tabFont])
        let filesPadH: CGFloat = 8
        let filesW = ceil(filesSize.width) + (filesPadH * 2)
        filesTabPanel.cornerRadius = 4
        filesTabPanel.frame = NSRect(x: messagesTabPanel.frame.maxX + 4, y: popoverHeight - 31, width: filesW, height: tabH)
        filesTabLabel.frame = NSRect(x: 0, y: (tabH - 16) / 2, width: filesW, height: 16)
        filesTabPanel.addSubview(filesTabLabel)
        filesTabPanel.onHoverChanged = { [weak self] _ in
            self?.updateSearchTabsAppearance()
        }
        filesTabPanel.onClick = { [weak self] in
            self?.isSearchFilesTabSelected = true
            self?.updateSearchTabsAppearance()
        }
        searchPopoverPanel.addSubview(filesTabPanel)
        
        let closeBtn = RoundedEdgePanel()
        closeBtn.cornerRadius = 4
        closeBtn.color = .clear
        closeBtn.frame = NSRect(x: popoverWidth - 36, y: popoverHeight - 32, width: 24, height: 24)
        let closeIcon = NSImageView()
        if let xImg = NSImage(systemSymbolName: "xmark", accessibilityDescription: "Close") {
            closeIcon.image = xImg.withSymbolConfiguration(.init(pointSize: 11, weight: .semibold))
            closeIcon.contentTintColor = mutedText
        }
        closeIcon.frame = NSRect(x: 4, y: 4, width: 16, height: 16)
        closeBtn.addSubview(closeIcon)
        closeBtn.onHoverChanged = { [weak closeBtn, weak closeIcon] isHovered in
            closeBtn?.color = isHovered ? pillBg : .clear
            closeBtn?.setNeedsAppearanceUpdate()
            closeIcon?.contentTintColor = isHovered ? .black : mutedText
        }
        closeBtn.onClick = { [weak self] in
            self?.setSearchPopoverOpen(false)
        }
        searchPopoverPanel.addSubview(closeBtn)
        
        // Header divider line below tabs
        let headerDivider = RoundedEdgePanel()
        headerDivider.cornerRadius = 0
        headerDivider.color = dividerColor
        headerDivider.frame = NSRect(x: 0, y: popoverHeight - 38, width: popoverWidth, height: 1)
        searchPopoverPanel.addSubview(headerDivider)
        
        // Row 2: Bordered input box containing magnifying glass + "Search messages" label (no caret)
        let searchInputBox = OutlinePanel()
        searchInputBox.cornerRadius = 4
        searchInputBox.borderWidth = 1.5
        searchInputBox.color = brandBlue
        searchInputBox.frame = NSRect(x: 16, y: 42, width: popoverWidth - 32, height: 32)
        
        let innerSearchIcon = NSImageView()
        if let sImg = NSImage(systemSymbolName: "magnifyingglass", accessibilityDescription: "Search") {
            innerSearchIcon.image = sImg.withSymbolConfiguration(.init(pointSize: 13, weight: .medium))
            innerSearchIcon.contentTintColor = placeholderColor
        }
        innerSearchIcon.frame = NSRect(x: 10, y: 8, width: 16, height: 16)
        searchInputBox.addSubview(innerSearchIcon)
        
        searchPopoverInputLabel.font = MMFont.font(ofSize: 13)
        searchPopoverInputLabel.textColor = NSColor(red: 63 / 255, green: 67 / 255, blue: 80 / 255, alpha: 1.0)
        searchPopoverInputLabel.placeholderString = "Search messages"
        searchPopoverInputLabel.isEditable = true
        searchPopoverInputLabel.isSelectable = true
        searchPopoverInputLabel.isBezeled = false
        searchPopoverInputLabel.drawsBackground = false
        searchPopoverInputLabel.focusRingType = .none
        searchPopoverInputLabel.cell?.usesSingleLineMode = true
        searchPopoverInputLabel.target = self
        searchPopoverInputLabel.action = #selector(performSearchFromPopover)
        searchPopoverInputLabel.frame = NSRect(x: 32, y: 7, width: popoverWidth - 72, height: 18)
        searchInputBox.addSubview(searchPopoverInputLabel)
        searchPopoverPanel.addSubview(searchInputBox)
        
        // Row 3: Lightbulb + "Filter your search with:" + filter pills
        let bulbIcon = NSImageView()
        if let bImg = NSImage(systemSymbolName: "lightbulb", accessibilityDescription: "Tip") {
            bulbIcon.image = bImg.withSymbolConfiguration(.init(pointSize: 11, weight: .regular))
            bulbIcon.contentTintColor = placeholderColor
        }
        bulbIcon.frame = NSRect(x: 16, y: 14, width: 14, height: 14)
        searchPopoverPanel.addSubview(bulbIcon)
        
        let filterHintLabel = NSTextField(labelWithString: "Filter your search with:")
        filterHintLabel.font = MMFont.font(ofSize: 11)
        filterHintLabel.textColor = mutedText
        filterHintLabel.isEditable = false
        filterHintLabel.isSelectable = false
        let hintSize = ("Filter your search with:" as NSString).size(withAttributes: [.font: filterHintLabel.font!])
        let hintW = ceil(hintSize.width) + 4
        let hintH = ceil(hintSize.height)
        filterHintLabel.frame = NSRect(x: 34, y: 13, width: hintW, height: hintH)
        searchPopoverPanel.addSubview(filterHintLabel)
        
        let filterTitles = ["From:", "In:", "On:", "Before:", "After:"]
        let pillFont = MMFont.font(ofSize: 10, weight: .semibold)
        var pillX = filterHintLabel.frame.maxX + 8
        for title in filterTitles {
            let pill = RoundedEdgePanel()
            pill.color = pillBg
            pill.cornerRadius = 3
            
            let pillTextSize = (title as NSString).size(withAttributes: [.font: pillFont])
            let pillPadH: CGFloat = 6
            let pillTextW = ceil(pillTextSize.width)
            let pillTextH = ceil(pillTextSize.height)
            let pillW = pillTextW + (pillPadH * 2)
            let pillH: CGFloat = max(18, pillTextH + 4)
            pill.frame = NSRect(x: pillX, y: 11, width: pillW, height: pillH)
            
            let pillLabel = NSTextField(labelWithString: title)
            pillLabel.font = pillFont
            pillLabel.textColor = pillText
            pillLabel.alignment = .center
            pillLabel.isEditable = false
            pillLabel.isSelectable = false
            pillLabel.frame = NSRect(x: 0, y: (pillH - 14) / 2, width: pillW, height: 14)
            pill.addSubview(pillLabel)
            
            pill.onHoverChanged = { [weak pill] isHovered in
                pill?.color = isHovered ? pillHoverBg : pillBg
                pill?.setNeedsAppearanceUpdate()
            }
            searchPopoverPanel.addSubview(pill)
            pillX += pillW + 4
        }
        
        updateSearchTabsAppearance()
        contentView?.addSubview(searchPopoverPanel)
    }
    
    private func makeMattermostCompassIcon() -> NSImage? {
        guard let fullLogo = NSImage(named: NSImage.Name("Mattermost Logo")) else { return nil }
        let side = fullLogo.size.height
        guard side > 0 else { return nil }
        let targetSize = NSSize(width: 16, height: 16)
        let cropped = NSImage(size: targetSize, flipped: false) { dstRect in
            fullLogo.draw(
                in: dstRect,
                from: NSRect(x: 0, y: 0, width: side, height: side),
                operation: .sourceOver,
                fraction: 1.0
            )
            return true
        }
        cropped.isTemplate = true
        return cropped
    }
    
    private func setupProductSwitcherMenu() {
        let menuWidth: CGFloat = 220
        let brandBlue = NSColor(red: 28 / 255, green: 88 / 255, blue: 217 / 255, alpha: 1.0)
        let darkText = NSColor(red: 31 / 255, green: 41 / 255, blue: 55 / 255, alpha: 1.0)
        let mutedIcon = NSColor(red: 107 / 255, green: 114 / 255, blue: 128 / 255, alpha: 1.0)
        let rowHoverBg = NSColor(red: 243 / 255, green: 244 / 255, blue: 246 / 255, alpha: 1.0)
        let dividerColor = NSColor(red: 229 / 255, green: 231 / 255, blue: 235 / 255, alpha: 1.0)
        
        productSwitcherMenu.color = .white
        productSwitcherMenu.cornerRadius = 6
        productSwitcherMenu.borderWidth = 1
        productSwitcherMenu.borderColor = dividerColor
        productSwitcherMenu.shadowColor = .black
        productSwitcherMenu.shadowOpacity = 0.18
        productSwitcherMenu.shadowRadius = 12
        productSwitcherMenu.shadowOffset = CGSize(width: 0, height: -4)
        productSwitcherMenu.isHidden = true
        
        // Top row: Channels (active item with Mattermost compass icon + checkmark)
        let channelsRow = createMenuRow(
            frame: NSRect(x: 0, y: 256, width: menuWidth, height: 36),
            customIcon: makeMattermostCompassIcon(),
            symbolName: "safari.fill",
            iconTint: brandBlue,
            title: "Channels",
            font: MMFont.font(ofSize: 13, weight: .semibold),
            textColor: darkText,
            hoverBg: rowHoverBg,
            showsCheckmark: true,
            checkmarkColor: brandBlue
        )
        productSwitcherMenu.addSubview(channelsRow)
        
        // Top divider
        let topDivider = RoundedEdgePanel()
        topDivider.cornerRadius = 0
        topDivider.color = dividerColor
        topDivider.frame = NSRect(x: 0, y: 249, width: menuWidth, height: 1)
        productSwitcherMenu.addSubview(topDivider)
        
        // Action items
        let items: [(symbol: String, title: String, y: CGFloat)] = [
            ("wrench.and.screwdriver", "System Console", 211),
            ("point.3.connected.trianglepath.dotted", "Integrations", 179),
            ("square.grid.2x2", "App Marketplace", 147),
            ("arrow.down.to.line", "Download Apps", 115),
            ("info.circle", "About Mattermost", 83)
        ]
        
        for item in items {
            let row = createMenuRow(
                frame: NSRect(x: 0, y: item.y, width: menuWidth, height: 32),
                customIcon: nil,
                symbolName: item.symbol,
                iconTint: mutedIcon,
                title: item.title,
                font: MMFont.font(ofSize: 13, weight: .regular),
                textColor: darkText,
                hoverBg: rowHoverBg,
                showsCheckmark: false,
                checkmarkColor: brandBlue
            )
            productSwitcherMenu.addSubview(row)
        }
        
        // Bottom divider
        let bottomDivider = RoundedEdgePanel()
        bottomDivider.cornerRadius = 0
        bottomDivider.color = dividerColor
        bottomDivider.frame = NSRect(x: 0, y: 76, width: menuWidth, height: 1)
        productSwitcherMenu.addSubview(bottomDivider)
        
        // Footer: TEAM EDITION badge + description
        let footerBadgePanel = RoundedEdgePanel()
        footerBadgePanel.color = dividerColor
        footerBadgePanel.cornerRadius = 3
        
        let footerBadgeLabel = NSTextField(labelWithString: "TEAM EDITION")
        footerBadgeLabel.font = MMFont.font(ofSize: 8, weight: .bold)
        footerBadgeLabel.textColor = NSColor(red: 75 / 255, green: 85 / 255, blue: 99 / 255, alpha: 1.0)
        footerBadgeLabel.alignment = .center
        
        let footerBadgeText = footerBadgeLabel.stringValue.isEmpty ? "TEAM EDITION" : footerBadgeLabel.stringValue
        let footerFont = footerBadgeLabel.font ?? MMFont.font(ofSize: 8, weight: .bold)
        let footerSize = (footerBadgeText as NSString).size(withAttributes: [.font: footerFont])
        let footerPadH: CGFloat = 8
        let footerPadV: CGFloat = 3
        let footerW = ceil(footerSize.width) + (footerPadH * 2)
        let footerH: CGFloat = max(16, ceil(footerSize.height) + (footerPadV * 2))
        let footerLabelH: CGFloat = 14
        footerBadgePanel.frame = NSRect(x: 16, y: 48, width: footerW, height: footerH)
        footerBadgeLabel.frame = NSRect(x: 0, y: (footerH - footerLabelH) / 2, width: footerW, height: footerLabelH)
        footerBadgeLabel.isEditable = false
        footerBadgeLabel.isSelectable = false
        footerBadgePanel.addSubview(footerBadgeLabel)
        productSwitcherMenu.addSubview(footerBadgePanel)
        
        let footerText = NSMutableAttributedString(
            string: "This is the free ",
            attributes: [
                .font: MMFont.font(ofSize: 11),
                .foregroundColor: mutedIcon
            ]
        )
        footerText.append(NSAttributedString(
            string: "unsupported",
            attributes: [
                .font: MMFont.font(ofSize: 11),
                .foregroundColor: brandBlue,
                .underlineStyle: NSUnderlineStyle.single.rawValue
            ]
        ))
        footerText.append(NSAttributedString(
            string: " edition of\nMattermost.",
            attributes: [
                .font: MMFont.font(ofSize: 11),
                .foregroundColor: mutedIcon
            ]
        ))
        
        let footerLabel = NSTextField(labelWithAttributedString: footerText)
        footerLabel.maximumNumberOfLines = 2
        footerLabel.frame = NSRect(x: 16, y: 12, width: menuWidth - 32, height: 30)
        productSwitcherMenu.addSubview(footerLabel)
        
        contentView?.addSubview(productSwitcherMenu)
    }
    
    private func setupHelpMenu() {
        let menuWidth: CGFloat = 204
        let brandBlue = NSColor(red: 28 / 255, green: 88 / 255, blue: 217 / 255, alpha: 1.0)
        let darkText = NSColor(red: 31 / 255, green: 41 / 255, blue: 55 / 255, alpha: 1.0)
        let mutedIcon = NSColor(red: 107 / 255, green: 114 / 255, blue: 128 / 255, alpha: 1.0)
        let rowHoverBg = NSColor(red: 243 / 255, green: 244 / 255, blue: 246 / 255, alpha: 1.0)
        let dividerColor = NSColor(red: 229 / 255, green: 231 / 255, blue: 235 / 255, alpha: 1.0)
        
        helpMenu.color = .white
        helpMenu.cornerRadius = 6
        helpMenu.borderWidth = 1
        helpMenu.borderColor = dividerColor
        helpMenu.shadowColor = .black
        helpMenu.shadowOpacity = 0.18
        helpMenu.shadowRadius = 12
        helpMenu.shadowOffset = CGSize(width: 0, height: -4)
        helpMenu.isHidden = true
        
        let items: [(symbol: String, title: String, y: CGFloat)] = [
            ("book", "Mattermost user guide", 136),
            ("lightbulb", "Training resources", 104),
            ("questionmark", "Ask the community", 72),
            ("exclamationmark.triangle", "Report a problem", 40),
            ("return", "Keyboard shortcuts", 8)
        ]
        
        for item in items {
            let row = createMenuRow(
                frame: NSRect(x: 0, y: item.y, width: menuWidth, height: 32),
                customIcon: nil,
                symbolName: item.symbol,
                iconTint: mutedIcon,
                title: item.title,
                font: MMFont.font(ofSize: 13, weight: .regular),
                textColor: darkText,
                hoverBg: rowHoverBg,
                showsCheckmark: false,
                checkmarkColor: brandBlue
            )
            helpMenu.addSubview(row)
        }
        
        contentView?.addSubview(helpMenu)
    }
    
    private func setupStatusMenu() {
        let menuWidth: CGFloat = 248
        let brandBlue = NSColor(red: 28 / 255, green: 88 / 255, blue: 217 / 255, alpha: 1.0)
        let darkText = NSColor(red: 31 / 255, green: 41 / 255, blue: 55 / 255, alpha: 1.0)
        let mutedIcon = NSColor(red: 107 / 255, green: 114 / 255, blue: 128 / 255, alpha: 1.0)
        let rowHoverBg = NSColor(red: 243 / 255, green: 244 / 255, blue: 246 / 255, alpha: 1.0)
        let dividerColor = NSColor(red: 229 / 255, green: 231 / 255, blue: 235 / 255, alpha: 1.0)
        
        statusMenu.color = .white
        statusMenu.cornerRadius = 6
        statusMenu.borderWidth = 1
        statusMenu.borderColor = dividerColor
        statusMenu.shadowColor = .black
        statusMenu.shadowOpacity = 0.18
        statusMenu.shadowRadius = 12
        statusMenu.shadowOffset = CGSize(width: 0, height: -4)
        statusMenu.isHidden = true
        
        // 1. User Header Row (Avatar circle + @username)
        let headerRow = RoundedEdgePanel()
        headerRow.frame = NSRect(x: 0, y: 297, width: menuWidth, height: 50)
        headerRow.cornerRadius = 0
        headerRow.color = .clear
        
        let headerAvatar = RoundedEdgePanel()
        headerAvatar.frame = NSRect(x: 16, y: 11, width: 28, height: 28)
        headerAvatar.cornerRadius = 14
        headerAvatar.color = NSColor(red: 156 / 255, green: 171 / 255, blue: 36 / 255, alpha: 1.0)
        
        let rawUsername = UserDefaults.standard.string(forKey: "username") ?? "boris"
        let cleanUsername = rawUsername.isEmpty ? "boris" : rawUsername
        let initial = cleanUsername.first.map { String($0).uppercased() } ?? "B"
        
        let headerAvatarLabel = NSTextField(labelWithString: initial)
        headerAvatarLabel.font = MMFont.font(ofSize: 13, weight: .semibold)
        headerAvatarLabel.textColor = .white
        headerAvatarLabel.alignment = .center
        headerAvatarLabel.frame = NSRect(x: 0, y: 5, width: 28, height: 18)
        headerAvatar.addSubview(headerAvatarLabel)
        headerRow.addSubview(headerAvatar)
        
        let menuDot = RoundedEdgePanel()
        menuDot.frame = NSRect(x: 34, y: 11, width: 10, height: 10)
        menuDot.cornerRadius = 5
        menuDot.color = statusColor(for: currentUserStatus)
        menuDot.borderWidth = 1.5
        menuDot.borderColor = .white
        headerRow.addSubview(menuDot)
        menuAvatarStatusDot = menuDot
        
        let usernameLabel = NSTextField(labelWithString: "@\(cleanUsername)")
        usernameLabel.font = MMFont.font(ofSize: 13, weight: .semibold)
        usernameLabel.textColor = darkText
        usernameLabel.frame = NSRect(x: 54, y: 16, width: menuWidth - 70, height: 18)
        headerRow.addSubview(usernameLabel)
        
        headerRow.onHoverChanged = { [weak self, weak headerRow] isHovered in
            headerRow?.color = isHovered ? rowHoverBg : .clear
            headerRow?.setNeedsAppearanceUpdate()
            if isHovered {
                self?.setDndSubMenuOpen(false)
            }
        }
        headerRow.onClick = { [weak self] in
            self?.setStatusMenuOpen(false)
        }
        statusMenu.addSubview(headerRow)
        
        // 2. Set custom status row
        let customStatusRow = createMenuRow(
            frame: NSRect(x: 0, y: 263, width: menuWidth, height: 34),
            customIcon: nil,
            symbolName: "face.smiling",
            iconTint: mutedIcon,
            title: "Set custom status",
            font: MMFont.font(ofSize: 13, weight: .regular),
            textColor: darkText,
            hoverBg: rowHoverBg,
            showsCheckmark: false,
            checkmarkColor: brandBlue
        )
        customStatusRow.onHoverChanged = { [weak self, weak customStatusRow] isHovered in
            customStatusRow?.color = isHovered ? rowHoverBg : .clear
            customStatusRow?.setNeedsAppearanceUpdate()
            if isHovered {
                self?.setDndSubMenuOpen(false)
            }
        }
        statusMenu.addSubview(customStatusRow)
        
        // Top divider
        let topDivider = RoundedEdgePanel()
        topDivider.cornerRadius = 0
        topDivider.color = dividerColor
        topDivider.frame = NSRect(x: 0, y: 256, width: menuWidth, height: 1)
        statusMenu.addSubview(topDivider)
        
        // 3. Status rows: Online, Away, Do not disturb (two-line + chevron), Offline
        statusCheckViews.removeAll()
        
        let statusConfigs: [(index: Int, symbol: String, tint: NSColor, title: String, subtitle: String?, y: CGFloat, height: CGFloat, showsChevron: Bool)] = [
            (0, "checkmark.circle.fill", NSColor(red: 61 / 255, green: 184 / 255, blue: 135 / 255, alpha: 1.0), "Online", nil, 216, 34, false),
            (1, "clock.fill", NSColor(red: 245 / 255, green: 171 / 255, blue: 0 / 255, alpha: 1.0), "Away", nil, 182, 34, false),
            (2, "minus.circle.fill", NSColor(red: 210 / 255, green: 75 / 255, blue: 78 / 255, alpha: 1.0), "Do not disturb", "Disables all notifications", 136, 46, true),
            (3, "circle", NSColor(red: 156 / 255, green: 163 / 255, blue: 175 / 255, alpha: 1.0), "Offline", nil, 102, 34, false)
        ]
        
        for cfg in statusConfigs {
            let row = RoundedEdgePanel()
            row.frame = NSRect(x: 0, y: cfg.y, width: menuWidth, height: cfg.height)
            row.cornerRadius = 0
            row.color = .clear
            if cfg.index == 2 {
                dndStatusRow = row
            }
            
            let iconView = NSImageView()
            if let img = NSImage(systemSymbolName: cfg.symbol, accessibilityDescription: cfg.title) {
                iconView.image = img.withSymbolConfiguration(.init(pointSize: 14, weight: .medium))
                iconView.contentTintColor = cfg.tint
            }
            let iconY: CGFloat = cfg.subtitle != nil ? 22 : (cfg.height - 16) / 2
            iconView.frame = NSRect(x: 16, y: iconY, width: 16, height: 16)
            row.addSubview(iconView)
            
            let titleLabel = NSTextField(labelWithString: cfg.title)
            titleLabel.font = MMFont.font(ofSize: 13, weight: .regular)
            titleLabel.textColor = darkText
            let titleY: CGFloat = cfg.subtitle != nil ? 21 : (cfg.height - 18) / 2
            titleLabel.frame = NSRect(x: 42, y: titleY, width: menuWidth - 80, height: 18)
            row.addSubview(titleLabel)
            
            if let subtitle = cfg.subtitle {
                let subLabel = NSTextField(labelWithString: subtitle)
                subLabel.font = MMFont.font(ofSize: 11, weight: .regular)
                subLabel.textColor = mutedIcon
                subLabel.frame = NSRect(x: 42, y: 6, width: menuWidth - 80, height: 14)
                row.addSubview(subLabel)
            }
            
            if cfg.showsChevron {
                let chevronView = NSImageView()
                if let chevImg = NSImage(systemSymbolName: "chevron.right", accessibilityDescription: "More") {
                    chevronView.image = chevImg.withSymbolConfiguration(.init(pointSize: 10, weight: .semibold))
                    chevronView.contentTintColor = mutedIcon
                }
                chevronView.frame = NSRect(x: menuWidth - 26, y: (cfg.height - 12) / 2, width: 12, height: 12)
                row.addSubview(chevronView)
            }
            
            let checkView = NSImageView()
            if let checkImg = NSImage(systemSymbolName: "checkmark", accessibilityDescription: "Selected") {
                checkView.image = checkImg.withSymbolConfiguration(.init(pointSize: 12, weight: .bold))
                checkView.contentTintColor = brandBlue
            }
            let checkX: CGFloat = cfg.showsChevron ? (menuWidth - 44) : (menuWidth - 30)
            checkView.frame = NSRect(x: checkX, y: (cfg.height - 16) / 2, width: 16, height: 16)
            checkView.isHidden = (cfg.index != selectedStatusIndex)
            row.addSubview(checkView)
            statusCheckViews.append(checkView)
            
            let statusIdx = cfg.index
            row.onHoverChanged = { [weak self, weak row] isHovered in
                guard let self = self else { return }
                if statusIdx == 2 {
                    if isHovered {
                        self.setDndSubMenuOpen(true)
                        row?.color = rowHoverBg
                        row?.setNeedsAppearanceUpdate()
                    } else {
                        self.scheduleDndHoverCheck()
                    }
                } else {
                    row?.color = isHovered ? rowHoverBg : .clear
                    row?.setNeedsAppearanceUpdate()
                    if isHovered {
                        self.setDndSubMenuOpen(false)
                    }
                }
            }
            row.onClick = { [weak self] in
                self?.selectUserStatus(statusIdx)
            }
            statusMenu.addSubview(row)
        }
        
        // Middle divider
        let middleDivider = RoundedEdgePanel()
        middleDivider.cornerRadius = 0
        middleDivider.color = dividerColor
        middleDivider.frame = NSRect(x: 0, y: 95, width: menuWidth, height: 1)
        statusMenu.addSubview(middleDivider)
        
        // 4. Profile row
        let profileRow = createMenuRow(
            frame: NSRect(x: 0, y: 55, width: menuWidth, height: 34),
            customIcon: nil,
            symbolName: "person",
            iconTint: mutedIcon,
            title: "Profile",
            font: MMFont.font(ofSize: 13, weight: .regular),
            textColor: darkText,
            hoverBg: rowHoverBg,
            showsCheckmark: false,
            checkmarkColor: brandBlue
        )
        profileRow.onHoverChanged = { [weak self, weak profileRow] isHovered in
            profileRow?.color = isHovered ? rowHoverBg : .clear
            profileRow?.setNeedsAppearanceUpdate()
            if isHovered {
                self?.setDndSubMenuOpen(false)
            }
        }
        statusMenu.addSubview(profileRow)
        
        // Bottom divider
        let bottomDivider = RoundedEdgePanel()
        bottomDivider.cornerRadius = 0
        bottomDivider.color = dividerColor
        bottomDivider.frame = NSRect(x: 0, y: 48, width: menuWidth, height: 1)
        statusMenu.addSubview(bottomDivider)
        
        // 5. Log out row
        let logoutRow = createMenuRow(
            frame: NSRect(x: 0, y: 8, width: menuWidth, height: 34),
            customIcon: nil,
            symbolName: "rectangle.portrait.and.arrow.right",
            iconTint: mutedIcon,
            title: "Log out",
            font: MMFont.font(ofSize: 13, weight: .regular),
            textColor: darkText,
            hoverBg: rowHoverBg,
            showsCheckmark: false,
            checkmarkColor: brandBlue
        )
        logoutRow.onHoverChanged = { [weak self, weak logoutRow] isHovered in
            logoutRow?.color = isHovered ? rowHoverBg : .clear
            logoutRow?.setNeedsAppearanceUpdate()
            if isHovered {
                self?.setDndSubMenuOpen(false)
            }
        }
        logoutRow.onClick = { [weak self] in
            self?.setStatusMenuOpen(false)
            (NSApp.delegate as? AppDelegate)?.logout()
        }
        statusMenu.addSubview(logoutRow)
        
        contentView?.addSubview(statusMenu)
        setupDndSubMenu()
    }
    
    private func setupDndSubMenu() {
        let subWidth: CGFloat = 212
        let darkText = NSColor(red: 31 / 255, green: 41 / 255, blue: 55 / 255, alpha: 1.0)
        let mutedText = NSColor(red: 107 / 255, green: 114 / 255, blue: 128 / 255, alpha: 1.0)
        let rowHoverBg = NSColor(red: 243 / 255, green: 244 / 255, blue: 246 / 255, alpha: 1.0)
        let dividerColor = NSColor(red: 229 / 255, green: 231 / 255, blue: 235 / 255, alpha: 1.0)
        
        dndSubMenu.color = .white
        dndSubMenu.cornerRadius = 6
        dndSubMenu.borderWidth = 1
        dndSubMenu.borderColor = dividerColor
        dndSubMenu.shadowColor = .black
        dndSubMenu.shadowOpacity = 0.18
        dndSubMenu.shadowRadius = 12
        dndSubMenu.shadowOffset = CGSize(width: 0, height: -4)
        dndSubMenu.isHidden = true
        dndSubMenu.onHoverChanged = { [weak self] isHovered in
            if !isHovered {
                self?.scheduleDndHoverCheck()
            }
        }
        
        // Header: "Clear after:"
        let headerLabel = NSTextField(labelWithString: "Clear after:")
        headerLabel.font = MMFont.font(ofSize: 11.5, weight: .semibold)
        headerLabel.textColor = mutedText
        headerLabel.frame = NSRect(x: 20, y: 201, width: subWidth - 36, height: 18)
        dndSubMenu.addSubview(headerLabel)
        
        let tomorrowDayString: String = {
            let tomorrow = Calendar.current.date(byAdding: .day, value: 1, to: Date()) ?? Date()
            let formatter = DateFormatter()
            formatter.locale = Locale(identifier: "en_US_POSIX")
            formatter.dateFormat = "EEE"
            return "\(formatter.string(from: tomorrow)), 9:00 AM"
        }()
        
        let rows: [(title: String, rightText: String?, y: CGFloat, height: CGFloat, durationSeconds: TimeInterval?)] = [
            ("Don't clear", nil, 167, 30, nil),
            ("30 mins", nil, 137, 30, 30 * 60),
            ("1 hour", nil, 107, 30, 60 * 60),
            ("2 hours", nil, 77, 30, 120 * 60),
            ("Tomorrow", tomorrowDayString, 47, 30, nil),
            ("Choose date and time", nil, 6, 32, nil)
        ]
        
        for item in rows {
            let row = RoundedEdgePanel()
            row.frame = NSRect(x: 0, y: item.y, width: subWidth, height: item.height)
            row.cornerRadius = 0
            row.color = .clear
            
            let titleLabel = NSTextField(labelWithString: item.title)
            titleLabel.font = MMFont.font(ofSize: 13, weight: .regular)
            titleLabel.textColor = darkText
            titleLabel.frame = NSRect(x: 20, y: (item.height - 18) / 2, width: item.rightText != nil ? 90 : (subWidth - 36), height: 18)
            row.addSubview(titleLabel)
            
            if let rightText = item.rightText {
                let rightLabel = NSTextField(labelWithString: rightText)
                rightLabel.font = MMFont.font(ofSize: 12, weight: .regular)
                rightLabel.textColor = mutedText
                rightLabel.alignment = .right
                rightLabel.frame = NSRect(x: 100, y: (item.height - 16) / 2, width: subWidth - 116, height: 16)
                row.addSubview(rightLabel)
            }
            
            row.onHoverChanged = { [weak self, weak row] isHovered in
                row?.color = isHovered ? rowHoverBg : .clear
                row?.setNeedsAppearanceUpdate()
                if !isHovered {
                    self?.scheduleDndHoverCheck()
                }
            }
            row.onClick = { [weak self] in
                var dndEndMs: Int64? = nil
                if let dur = item.durationSeconds {
                    dndEndMs = Int64((Date().timeIntervalSince1970 + dur) * 1000)
                } else if item.title == "Tomorrow" {
                    let tomorrow = Calendar.current.date(byAdding: .day, value: 1, to: Date()) ?? Date()
                    var comp = Calendar.current.dateComponents([.year, .month, .day], from: tomorrow)
                    comp.hour = 9
                    comp.minute = 0
                    comp.second = 0
                    if let d = Calendar.current.date(from: comp) {
                        dndEndMs = Int64(d.timeIntervalSince1970 * 1000)
                    }
                }
                self?.selectUserStatus(2, dndEndTime: dndEndMs)
            }
            dndSubMenu.addSubview(row)
        }
        
        // Divider above "Choose date and time"
        let divider = RoundedEdgePanel()
        divider.cornerRadius = 0
        divider.color = dividerColor
        divider.frame = NSRect(x: 0, y: 42, width: subWidth, height: 1)
        dndSubMenu.addSubview(divider)
        
        contentView?.addSubview(dndSubMenu)
    }
    
    private func createMenuRow(
        frame: NSRect,
        customIcon: NSImage?,
        symbolName: String,
        iconTint: NSColor,
        title: String,
        font: NSFont,
        textColor: NSColor,
        hoverBg: NSColor,
        showsCheckmark: Bool,
        checkmarkColor: NSColor
    ) -> RoundedEdgePanel {
        let row = RoundedEdgePanel()
        row.frame = frame
        row.cornerRadius = 0
        row.color = .clear
        
        let iconView = NSImageView()
        if let customIcon = customIcon {
            iconView.image = customIcon
            iconView.contentTintColor = iconTint
        } else if let img = NSImage(systemSymbolName: symbolName, accessibilityDescription: title) {
            iconView.image = img.withSymbolConfiguration(.init(pointSize: 13.5, weight: .medium))
            iconView.contentTintColor = iconTint
        }
        iconView.frame = NSRect(x: 16, y: (frame.height - 16) / 2, width: 16, height: 16)
        row.addSubview(iconView)
        
        let label = NSTextField(labelWithString: title)
        label.font = font
        label.textColor = textColor
        label.frame = NSRect(x: 42, y: (frame.height - 18) / 2, width: frame.width - 54, height: 18)
        row.addSubview(label)
        
        if showsCheckmark {
            let checkView = NSImageView()
            if let checkImg = NSImage(systemSymbolName: "checkmark", accessibilityDescription: "Selected") {
                checkView.image = checkImg.withSymbolConfiguration(.init(pointSize: 12, weight: .bold))
                checkView.contentTintColor = checkmarkColor
            }
            checkView.frame = NSRect(x: frame.width - 30, y: (frame.height - 16) / 2, width: 16, height: 16)
            row.addSubview(checkView)
        }
        
        row.onHoverChanged = { [weak row] isHovered in
            row?.color = isHovered ? hoverBg : .clear
            row?.setNeedsAppearanceUpdate()
        }
        row.onClick = { [weak self] in
            self?.setProductSwitcherMenuOpen(false)
            self?.setHelpMenuOpen(false)
            self?.setStatusMenuOpen(false)
        }
        return row
    }
    
    override func sendEvent(_ event: NSEvent) {
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
                if isFilterMenuOpen {
                    let mainPoint = mainPanel.convert(event.locationInWindow, from: nil)
                    if !filterMenu.frame.contains(mainPoint) && !filterChannelButton.frame.contains(mainPoint) {
                        setFilterMenuOpen(false)
                    }
                }
            }
        }
        super.sendEvent(event)
    }
    
    override func performKeyEquivalent(with event: NSEvent) -> Bool {
        if event.modifierFlags.contains(.command) {
            let chars = event.charactersIgnoringModifiers ?? ""
            if chars == "+" || chars == "=" {
                ZoomManager.shared.zoomIn()
                return true
            } else if chars == "-" {
                ZoomManager.shared.zoomOut()
                return true
            } else if chars == "0" {
                ZoomManager.shared.resetZoom()
                return true
            }
        }
        return super.performKeyEquivalent(with: event)
    }
    
    private func configureIconButton(
        panel: RoundedEdgePanel,
        iconView: NSImageView,
        symbolName: String,
        pointSize: CGFloat,
        accessibilityDescription: String,
        defaultTint: NSColor,
        hoverBg: NSColor,
        onClick: (() -> Void)? = nil
    ) {
        panel.color = .clear
        panel.cornerRadius = 4
        if let img = NSImage(systemSymbolName: symbolName, accessibilityDescription: accessibilityDescription) {
            iconView.image = img.withSymbolConfiguration(.init(pointSize: pointSize, weight: .medium))
            iconView.contentTintColor = defaultTint
        }
        panel.addSubview(iconView)
        panel.onHoverChanged = { [weak panel, weak iconView] isHovered in
            panel?.color = isHovered ? hoverBg : .clear
            panel?.setNeedsAppearanceUpdate()
            iconView?.contentTintColor = isHovered ? .white : defaultTint
        }
        panel.onClick = onClick
        contentView?.addSubview(panel)
    }
    
    private func setupLeftChannelSidebar() {
        let mutedTint = NSColor(white: 1.0, alpha: 0.64)
        let hoverBg = NSColor(white: 1.0, alpha: 0.08)
        
        // 1. Team Header Row: "None v" button + "+" button
        teamHeaderButton.color = .clear
        teamHeaderButton.cornerRadius = 4
        teamHeaderLabel.font = MMFont.font(ofSize: 16, weight: .semibold)
        teamHeaderLabel.textColor = .white
        teamHeaderLabel.isEditable = false
        teamHeaderLabel.isSelectable = false
        teamHeaderButton.addSubview(teamHeaderLabel)
        
        if let chevImg = NSImage(systemSymbolName: "chevron.down", accessibilityDescription: "Team Menu") {
            teamHeaderChevron.image = chevImg.withSymbolConfiguration(.init(pointSize: 9.5, weight: .bold))
            teamHeaderChevron.contentTintColor = mutedTint
        }
        teamHeaderButton.addSubview(teamHeaderChevron)
        teamHeaderButton.onHoverChanged = { [weak self] isHovered in
            guard let self = self else { return }
            self.teamHeaderButton.color = isHovered ? hoverBg : .clear
            self.teamHeaderButton.setNeedsAppearanceUpdate()
            self.teamHeaderChevron.contentTintColor = isHovered ? .white : mutedTint
        }
        teamHeaderButton.onClick = { [weak self] in
            self?.toggleTeamMenu()
        }
        mainPanel.addSubview(teamHeaderButton)
        
        teamDropdownMenu.isHidden = true
        contentView?.addSubview(teamDropdownMenu)
        
        teamAddButton.color = NSColor(white: 1.0, alpha: 0.12)
        teamAddButton.cornerRadius = 16
        if let plusImg = NSImage(systemSymbolName: "plus", accessibilityDescription: "Add") {
            teamAddIconView.image = plusImg.withSymbolConfiguration(.init(pointSize: 15, weight: .medium))
            teamAddIconView.contentTintColor = mutedTint
        }
        teamAddButton.addSubview(teamAddIconView)
        teamAddButton.onHoverChanged = { [weak self] isHovered in
            guard let self = self else { return }
            self.teamAddButton.color = NSColor(white: 1.0, alpha: isHovered ? 0.18 : 0.12)
            self.teamAddButton.setNeedsAppearanceUpdate()
            self.teamAddIconView.contentTintColor = isHovered ? .white : mutedTint
        }
        teamAddButton.onClick = { [weak self] in
            self?.showCreateTeamDialog()
        }
        mainPanel.addSubview(teamAddButton)
        
        // 2. Filter & Find Channel Row
        filterChannelButton.color = NSColor(white: 1.0, alpha: 0.08)
        filterChannelButton.cornerRadius = 4
        if let filterImg = NSImage(systemSymbolName: "line.3.horizontal.decrease", accessibilityDescription: "Filter") {
            filterChannelIconView.image = filterImg.withSymbolConfiguration(.init(pointSize: 13, weight: .medium))
            filterChannelIconView.contentTintColor = mutedTint
        }
        filterChannelButton.addSubview(filterChannelIconView)
        filterChannelButton.onHoverChanged = { [weak self] isHovered in
            guard let self = self else { return }
            self.filterChannelButton.color = NSColor(white: 1.0, alpha: isHovered ? 0.15 : 0.08)
            self.filterChannelButton.setNeedsAppearanceUpdate()
            self.filterChannelIconView.contentTintColor = isHovered ? .white : mutedTint
        }
        filterChannelButton.onClick = { [weak self] in
            guard let self = self else { return }
            self.setFilterMenuOpen(!self.isFilterMenuOpen)
        }
        mainPanel.addSubview(filterChannelButton)
        
        findChannelPanel.color = NSColor(white: 1.0, alpha: 0.08)
        findChannelPanel.cornerRadius = 4
        if let findImg = NSImage(systemSymbolName: "magnifyingglass", accessibilityDescription: "Find channel") {
            findChannelIconView.image = findImg.withSymbolConfiguration(.init(pointSize: 13, weight: .medium))
            findChannelIconView.contentTintColor = mutedTint
        }
        findChannelLabel.font = MMFont.font(ofSize: 12)
        findChannelLabel.textColor = mutedTint
        findChannelLabel.placeholderString = "Find channel"
        findChannelLabel.isEditable = true
        findChannelLabel.isSelectable = true
        findChannelLabel.isBezeled = false
        findChannelLabel.drawsBackground = false
        findChannelLabel.focusRingType = .none
        findChannelLabel.cell?.usesSingleLineMode = true
        findChannelLabel.delegate = self
        findChannelPanel.addSubview(findChannelIconView)
        findChannelPanel.addSubview(findChannelLabel)
        findChannelPanel.onHoverChanged = { [weak self] isHovered in
            guard let self = self else { return }
            self.findChannelPanel.color = NSColor(white: 1.0, alpha: isHovered ? 0.14 : 0.08)
            self.findChannelPanel.setNeedsAppearanceUpdate()
            self.findChannelIconView.contentTintColor = isHovered ? .white : mutedTint
            self.findChannelLabel.textColor = isHovered ? .white : mutedTint
        }
        mainPanel.addSubview(findChannelPanel)
        setupFilterMenu()
        
        // 3. Threads Navigation Row
        let threadsItem = createSidebarItem(
            id: "threads",
            symbolName: "text.bubble",
            title: "Threads",
            isSelectable: true,
            isBotBadge: false,
            showsCloseOnHover: false
        )
        threadsSidebarItem = threadsItem
        mainPanel.addSubview(threadsItem.row)
        
        // 4. Collapsible Categories & Channels
        buildDefaultSidebarCategories()
    }
    
    private func buildDefaultSidebarCategories() {
        for cat in sidebarCategories {
            cat.headerRow.removeFromSuperview()
            for item in cat.items {
                item.row.removeFromSuperview()
            }
        }
        sidebarCategories.removeAll()
        
        let channelsItems = [
            createSidebarItem(id: "town-square", symbolName: "globe", title: "Town Square", isSelectable: true, isBotBadge: false, showsCloseOnHover: false),
            createSidebarItem(id: "off-topic", symbolName: "globe", title: "Off-Topic", isSelectable: true, isBotBadge: false, showsCloseOnHover: false),
            createSidebarItem(id: "add-channels", symbolName: "plus", title: "Add Channels", isSelectable: false, isBotBadge: false, showsCloseOnHover: false)
        ]
        let channelsCat = createSidebarCategory(id: "channels", title: "CHANNELS", showsAddButton: false, items: channelsItems)
        sidebarCategories.append(channelsCat)
        
        let dmItems = [
            createSidebarItem(id: "system-bot", symbolName: "cpu", title: "system-bot", isSelectable: true, isBotBadge: true, showsCloseOnHover: true),
            createSidebarItem(id: "invite-members", symbolName: "plus", title: "Invite Members", isSelectable: false, isBotBadge: false, showsCloseOnHover: false)
        ]
        let dmCat = createSidebarCategory(id: "direct_messages", title: "DIRECT MESSAGES", showsAddButton: true, items: dmItems)
        sidebarCategories.append(dmCat)
        
        updateSidebarSelectionAppearance()
        fetchAvatarForUsernameIfNeeded("system-bot")
    }
    
    // MARK: - Direct Message & Channel Name Resolution
    
    private func isLikelyMattermostId(_ str: String) -> Bool {
        return str.count == 26 && str.allSatisfy { ($0 >= "a" && $0 <= "z") || ($0 >= "0" && $0 <= "9") }
    }
    
    private func isRawDMNameOrId(_ str: String) -> Bool {
        if str.contains("__") { return true }
        return isLikelyMattermostId(str)
    }
    
    private func resolveDMTargetUserId(for channel: MMChannel) -> String? {
        guard channel.type == "D" else { return nil }
        let myId = currentUser?.id ?? ""
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
    
    private func channelDisplayName(for channel: MMChannel) -> String {
        if channel.type == "D" {
            if let targetId = resolveDMTargetUserId(for: channel),
               let user = usersById[targetId] {
                return (user.id == currentUser?.id) ? "\(user.username) (you)" : user.username
            }
            if !channel.display_name.isEmpty && !isRawDMNameOrId(channel.display_name) {
                return channel.display_name
            }
            if let targetId = resolveDMTargetUserId(for: channel), !isLikelyMattermostId(targetId) {
                return targetId
            }
        }
        return channel.display_name.isEmpty ? channel.name : channel.display_name
    }
    
    private func isChannelBot(for channel: MMChannel) -> Bool {
        guard channel.type == "D" else { return false }
        if let targetId = resolveDMTargetUserId(for: channel),
           let user = usersById[targetId] {
            if user.is_bot == true { return true }
            let roles = user.roles?.lowercased() ?? ""
            if roles.contains("bot") { return true }
            if user.username.lowercased().contains("bot") { return true }
        }
        let title = channelDisplayName(for: channel).lowercased()
        if title.contains("bot") { return true }
        if channel.name.lowercased().contains("bot") { return true }
        return false
    }
    
    private func isCurrentChannelBot() -> Bool {
        if let chId = activeChannelId.isEmpty ? nil : activeChannelId, let ch = channelsById[chId] {
            return isChannelBot(for: ch)
        }
        if selectedSidebarItemId.lowercased().contains("bot") || channelTitleLabel.stringValue.lowercased().contains("bot") {
            return true
        }
        return false
    }
    
    // MARK: - Avatar WebService Fetching & Caching
    
    @MainActor
    private func fetchAvatarIfNeeded(for userId: String) {
        guard !userId.isEmpty, userAvatarsById[userId] == nil, userAvatarFetchTasks[userId] == nil else { return }
        guard let ws = (NSApp.delegate as? AppDelegate)?.webService, ws.isLogged() else { return }
        
        userAvatarFetchTasks[userId] = Task { @MainActor [weak self] () -> NSImage? in
            defer { self?.userAvatarFetchTasks.removeValue(forKey: userId) }
            do {
                let data = try await ws.fetchUserImage(userId: userId)
                if let img = NSImage(data: data) {
                    self?.userAvatarsById[userId] = img
                    self?.onAvatarLoaded(userId: userId, image: img)
                    return img
                }
            } catch {
                NSLog("Failed to fetch user image for \(userId): \(error.localizedDescription)")
            }
            return nil
        }
    }
    
    @MainActor
    private func fetchAvatarForUsernameIfNeeded(_ username: String) {
        let norm = username.lowercased()
        if let u = usersByUsername[norm] {
            fetchAvatarIfNeeded(for: u.id)
            return
        }
        guard let ws = (NSApp.delegate as? AppDelegate)?.webService, ws.isLogged() else { return }
        Task { @MainActor [weak self] in
            guard let self = self else { return }
            if let user = try? await ws.fetchUserByUsername(norm) {
                self.usersById[user.id] = user
                self.usersByUsername[norm] = user
                self.fetchAvatarIfNeeded(for: user.id)
            }
        }
    }
    
    @MainActor
    private func onAvatarLoaded(userId: String, image: NSImage) {
        // 1. Top bar current user profile image
        if let currentId = currentUser?.id, currentId == userId {
            avatarImageView.image = image
            avatarImageView.isHidden = false
            avatarLabel.isHidden = true
            avatarPanel.color = .clear
            avatarPanel.setNeedsAppearanceUpdate()
        }
        
        // 2. Sidebar items representing this user
        for cat in sidebarCategories {
            for var item in cat.items {
                var matches = (item.id == userId)
                if !matches, let ch = channelsById[item.id], ch.type == "D", resolveDMTargetUserId(for: ch) == userId {
                    matches = true
                }
                if matches {
                    item.isBotBadge = true
                    item.iconView.image = image
                    item.iconView.imageScaling = .scaleProportionallyUpOrDown
                    item.iconView.contentTintColor = nil
                    item.iconView.frame = NSRect(x: 16, y: 5, width: 18, height: 18)
                }
            }
        }
        
        // 3. Welcome hero if active channel is DM with this user
        if let activeId = activeChannelId.isEmpty ? nil : activeChannelId,
           let ch = channelsById[activeId], ch.type == "D",
           resolveDMTargetUserId(for: ch) == userId {
            heroIllustrationCircle.color = .clear
            heroWhiteBubble.isHidden = true
            heroBlueBubble.isHidden = true
            heroBotAvatarView.isHidden = false
            heroBotAvatarView.image = image
            heroBotAvatarView.frame = NSRect(x: 0, y: 0, width: 76, height: 76)
        }
        
        // 4. Message rows
        let affectsTimeline = currentChannelPosts.contains { $0.user_id == userId }
        if affectsTimeline {
            rebuildTimelineContent(scrollToBottom: false)
        }
    }
    
    private func refreshUserStatuses() {
        guard let ws = (NSApp.delegate as? AppDelegate)?.webService, ws.isLogged() else { return }
        DebugLog.log("refreshUserStatuses triggered, requesting via WS get_statuses")
        ws.requestStatuses()
        let knownIds = Array(Set(usersById.keys.filter { isLikelyMattermostId($0) }))
        if !knownIds.isEmpty {
            DebugLog.log("refreshUserStatuses: fetching REST statuses for \(knownIds.count) users: \(knownIds)")
            Task { @MainActor [weak self] in
                do {
                    let statuses = try await ws.fetchUserStatuses(userIds: knownIds)
                    DebugLog.log("refreshUserStatuses: received REST statuses: \(statuses.map { "\($0.user_id)=\($0.status)" }.joined(separator: ", "))")
                    for st in statuses {
                        self?.userStatusById[st.user_id] = st.status
                        self?.updateChatWidgetUserStatus(userId: st.user_id, status: st.status)
                    }
                } catch {
                    DebugLog.log("refreshUserStatuses REST fetch error: \(error)")
                }
            }
        }
    }
    
    @MainActor
    private func preloadDMUsers(for channels: [MMChannel]) async {
        guard let ws = (NSApp.delegate as? AppDelegate)?.webService, ws.isLogged() else { return }
        let dmChannels = channels.filter { $0.type == "D" }
        var targetIds = Set<String>()
        for ch in dmChannels {
            if ch.name.contains("__") {
                for part in ch.name.components(separatedBy: "__") where isLikelyMattermostId(part) {
                    targetIds.insert(part)
                }
            } else if isLikelyMattermostId(ch.name) {
                targetIds.insert(ch.name)
            }
            if isLikelyMattermostId(ch.display_name) {
                targetIds.insert(ch.display_name)
            }
        }
        for id in targetIds {
            fetchAvatarIfNeeded(for: id)
        }
        let missingIds = Array(targetIds.subtracting(usersById.keys))
        if !missingIds.isEmpty {
            do {
                let fetchedUsers = try await ws.fetchUsersByIds(missingIds)
                for u in fetchedUsers {
                    usersById[u.id] = u
                    usersByUsername[u.username.lowercased()] = u
                    fetchAvatarIfNeeded(for: u.id)
                }
            } catch {
                NSLog("Failed to preload DM users: \(error.localizedDescription)")
            }
        }
        let allTargetIds = Array(targetIds.filter { isLikelyMattermostId($0) })
        if !allTargetIds.isEmpty, let statuses = try? await ws.fetchUserStatuses(userIds: allTargetIds) {
            for st in statuses {
                self.userStatusById[st.user_id] = st.status
                self.updateChatWidgetUserStatus(userId: st.user_id, status: st.status)
            }
        }
        for ch in dmChannels {
            if let targetId = resolveDMTargetUserId(for: ch), let u = usersById[targetId] {
                channelsByName[u.username.lowercased()] = ch
                channelsByName[u.id] = ch
            }
        }
    }
    
    @MainActor
    private func refreshSidebarDMTitles() {
        for cat in sidebarCategories {
            for var item in cat.items {
                guard let ch = channelsById[item.id], ch.type == "D" else { continue }
                let newTitle = channelDisplayName(for: ch)
                item.label.stringValue = newTitle
                if let targetId = resolveDMTargetUserId(for: ch) {
                    fetchAvatarIfNeeded(for: targetId)
                    if let userImg = userAvatarsById[targetId] {
                        item.isBotBadge = true
                        item.iconView.image = userImg
                        item.iconView.imageScaling = .scaleProportionallyUpOrDown
                        item.iconView.contentTintColor = nil
                        item.iconView.frame = NSRect(x: 16, y: 5, width: 18, height: 18)
                    }
                }
                if item.id == selectedSidebarItemId {
                    channelTitleLabel.stringValue = newTitle
                    heroTitleLabel.stringValue = newTitle
                    composerPlaceholderLabel.stringValue = "Write to \(newTitle)"
                    self.entryView.placeholderString = self.composerPlaceholderLabel.stringValue
                    layoutRightChatPanel()
                    rebuildTimelineContent(scrollToBottom: false)
                }
            }
        }
    }
    
    @MainActor
    private func populateSidebarCategories(from response: MMSidebarCategoriesResponse, channels: [MMChannel]) {
        for cat in sidebarCategories {
            cat.headerRow.removeFromSuperview()
            for item in cat.items {
                item.row.removeFromSuperview()
            }
        }
        sidebarCategories.removeAll()
        
        let orderedCategories: [MMSidebarCategory]
        if !response.order.isEmpty {
            let catMap = Dictionary(uniqueKeysWithValues: response.categories.map { ($0.id, $0) })
            orderedCategories = response.order.compactMap { catMap[$0] }
        } else {
            orderedCategories = response.categories
        }
        
        guard !orderedCategories.isEmpty else {
            buildDefaultSidebarCategories()
            return
        }
        
        var placedChannelIds = Set<String>()
        
        for cat in orderedCategories {
            var items: [SidebarItemView] = []
            
            for channelId in cat.channel_ids {
                placedChannelIds.insert(channelId)
                guard let ch = channelsById[channelId] else { continue }
                
                let isBot = isChannelBot(for: ch)
                let targetId = (ch.type == "D") ? resolveDMTargetUserId(for: ch) : nil
                if let tId = targetId {
                    fetchAvatarIfNeeded(for: tId)
                }
                let customImg = targetId.flatMap { userAvatarsById[$0] }
                let symbolName: String
                if ch.type == "P" {
                    symbolName = "lock.fill"
                } else if ch.type == "D" {
                    symbolName = isBot ? "cpu" : "person.fill"
                } else {
                    symbolName = "globe"
                }
                
                let displayTitle = channelDisplayName(for: ch)
                let showsClose = (ch.type == "D")
                
                let item = createSidebarItem(
                    id: ch.id,
                    symbolName: symbolName,
                    title: displayTitle,
                    isSelectable: true,
                    isBotBadge: isBot || (customImg != nil),
                    showsCloseOnHover: showsClose,
                    customImage: customImg
                )
                items.append(item)
            }
            
            if cat.type == "channels" {
                let addChannelsItem = createSidebarItem(
                    id: "add-channels",
                    symbolName: "plus",
                    title: "Add Channels",
                    isSelectable: false,
                    isBotBadge: false,
                    showsCloseOnHover: false
                )
                items.append(addChannelsItem)
            } else if cat.type == "direct_messages" {
                let inviteMembersItem = createSidebarItem(
                    id: "invite-members",
                    symbolName: "plus",
                    title: "Invite Members",
                    isSelectable: false,
                    isBotBadge: false,
                    showsCloseOnHover: false
                )
                items.append(inviteMembersItem)
            }
            
            // Mattermost hides the built-in Favorites section while it is empty.
            if items.isEmpty && cat.type == "favorites" {
                continue
            }
            
            let isCollapsed = cat.collapsed ?? false
            let categoryView = createSidebarCategory(
                id: cat.id,
                title: cat.display_name.uppercased(),
                showsAddButton: (cat.type == "direct_messages"),
                items: items,
                isCollapsed: isCollapsed
            )
            sidebarCategories.append(categoryView)
        }
        
        // Background check to resolve any remaining DM users if not already fetched
        let missingDMUserIds = channels.filter { $0.type == "D" }
            .compactMap { resolveDMTargetUserId(for: $0) }
            .filter { isLikelyMattermostId($0) && usersById[$0] == nil }
        if !missingDMUserIds.isEmpty {
            Task { @MainActor [weak self] in
                guard let self = self else { return }
                await self.preloadDMUsers(for: channels)
                self.refreshSidebarDMTitles()
            }
        }
        
        // Include any public/private channels not explicitly in categories
        let unplacedChannels = channels.filter { !placedChannelIds.contains($0.id) && $0.type != "D" }
        if !unplacedChannels.isEmpty {
            if let channelsIdx = sidebarCategories.firstIndex(where: { $0.id.contains("channels") }) {
                var existingItems = sidebarCategories[channelsIdx].items
                let addBtnItem = existingItems.last(where: { $0.id == "add-channels" })
                if addBtnItem != nil {
                    existingItems.removeLast()
                }
                for ch in unplacedChannels {
                    let sym = ch.type == "P" ? "lock.fill" : "globe"
                    let item = createSidebarItem(
                        id: ch.id,
                        symbolName: sym,
                        title: ch.display_name.isEmpty ? ch.name : ch.display_name,
                        isSelectable: true,
                        isBotBadge: false,
                        showsCloseOnHover: false
                    )
                    existingItems.append(item)
                }
                if let addBtn = addBtnItem {
                    existingItems.append(addBtn)
                }
                sidebarCategories[channelsIdx].items = existingItems
            }
        }
        
        rebuildFavoritesCategory()
        layoutLeftSidebar(topBarY: mainPanel.bounds.height)
        updateSidebarSelectionAppearance()
        fetchAvatarForUsernameIfNeeded("system-bot")
    }
    
    private func createSidebarCategory(
        id: String,
        title: String,
        showsAddButton: Bool,
        items: [SidebarItemView],
        isCollapsed: Bool = false
    ) -> SidebarCategoryView {
        let mutedTint = NSColor(white: 1.0, alpha: 0.64)
        let headerRow = RoundedEdgePanel()
        headerRow.cornerRadius = 0
        headerRow.color = .clear
        
        let chevronView = NSImageView()
        let chevSymbol = isCollapsed ? "chevron.right" : "chevron.down"
        if let chevImg = NSImage(systemSymbolName: chevSymbol, accessibilityDescription: title) {
            chevronView.image = chevImg.withSymbolConfiguration(.init(pointSize: 9, weight: .bold))
            chevronView.contentTintColor = mutedTint
        }
        headerRow.addSubview(chevronView)
        
        let titleLabel = NSTextField(labelWithString: title)
        titleLabel.font = MMFont.font(ofSize: 12, weight: .semibold)
        titleLabel.textColor = mutedTint
        titleLabel.isEditable = false
        titleLabel.isSelectable = false
        headerRow.addSubview(titleLabel)
        
        var addBtn: RoundedEdgePanel? = nil
        if showsAddButton {
            let btn = RoundedEdgePanel()
            btn.cornerRadius = 4
            btn.color = .clear
            let addIcon = NSImageView()
            if let plusImg = NSImage(systemSymbolName: "plus", accessibilityDescription: "Add Direct Message") {
                addIcon.image = plusImg.withSymbolConfiguration(.init(pointSize: 10.5, weight: .semibold))
                addIcon.contentTintColor = mutedTint
            }
            addIcon.frame = NSRect(x: 3, y: 3, width: 14, height: 14)
            btn.addSubview(addIcon)
            btn.onHoverChanged = { [weak btn, weak addIcon] isHovered in
                btn?.color = isHovered ? NSColor(white: 1.0, alpha: 0.12) : .clear
                btn?.setNeedsAppearanceUpdate()
                addIcon?.contentTintColor = isHovered ? .white : mutedTint
            }
            headerRow.addSubview(btn)
            addBtn = btn
        }
        
        headerRow.onHoverChanged = { [weak chevronView, weak titleLabel] isHovered in
            chevronView?.contentTintColor = isHovered ? .white : mutedTint
            titleLabel?.textColor = isHovered ? .white : mutedTint
        }
        headerRow.onClick = { [weak self] in
            self?.toggleSidebarCategory(id)
        }
        
        mainPanel.addSubview(headerRow)
        for item in items {
            mainPanel.addSubview(item.row)
        }
        
        return SidebarCategoryView(
            id: id,
            headerRow: headerRow,
            chevronView: chevronView,
            titleLabel: titleLabel,
            addButton: addBtn,
            isCollapsed: isCollapsed,
            items: items
        )
    }
    
    private func createSidebarItem(
        id: String,
        symbolName: String,
        title: String,
        isSelectable: Bool,
        isBotBadge: Bool,
        showsCloseOnHover: Bool,
        customImage: NSImage? = nil
    ) -> SidebarItemView {
        let row = RoundedEdgePanel()
        row.cornerRadius = 0
        row.color = .clear
        
        let leftBar = RoundedEdgePanel()
        leftBar.cornerRadius = 2
        leftBar.color = NSColor(red: 93 / 255, green: 137 / 255, blue: 234 / 255, alpha: 1.0)
        leftBar.isHidden = true
        row.addSubview(leftBar)
        
        let iconView = NSImageView()
        if let custom = customImage {
            iconView.image = custom
            iconView.imageScaling = .scaleProportionallyUpOrDown
            iconView.frame = NSRect(x: 21, y: 7, width: 18, height: 18)
            row.addSubview(iconView)
        } else if isBotBadge {
            if let img = NSImage(systemSymbolName: symbolName, accessibilityDescription: title) {
                iconView.image = img.withSymbolConfiguration(.init(pointSize: 9.5, weight: .semibold))
                iconView.contentTintColor = NSColor(white: 1.0, alpha: 0.85)
            }
            iconView.frame = NSRect(x: 21, y: 7, width: 18, height: 18)
            row.addSubview(iconView)
        } else {
            if let img = NSImage(systemSymbolName: symbolName, accessibilityDescription: title) {
                iconView.image = img.withSymbolConfiguration(.init(pointSize: 13.5, weight: .regular))
            }
            iconView.frame = NSRect(x: 21, y: 7, width: 18, height: 18)
            row.addSubview(iconView)
        }
        
        let label = NSTextField(labelWithString: title)
        label.isEditable = false
        label.isSelectable = false
        label.font = MMFont.font(ofSize: 14, weight: .regular)
        label.frame = NSRect(x: 49, y: 6, width: 140, height: 20)
        row.addSubview(label)
        
        var closeView: NSImageView? = nil
        if showsCloseOnHover {
            let xView = NSImageView()
            if let xImg = NSImage(systemSymbolName: "xmark", accessibilityDescription: "Close") {
                xView.image = xImg.withSymbolConfiguration(.init(pointSize: 9.5, weight: .bold))
                xView.contentTintColor = NSColor(white: 1.0, alpha: 0.72)
            }
            xView.isHidden = true
            row.addSubview(xView)
            closeView = xView
        }
        
        row.onHoverChanged = { [weak self] _ in
            self?.updateSidebarSelectionAppearance()
        }
        row.onClick = { [weak self] in
            guard let self = self else { return }
            if id == "threads" {
                self.showRightPanel(mode: .threads)
                return
            }
            if id == "add-channels" {
                self.showRightPanel(mode: .browse)
                return
            }
            if id == "invite-members" {
                self.showInviteDialog()
                return
            }
            if isSelectable {
                self.selectedSidebarItemId = id
                self.updateSidebarSelectionAppearance()
                self.channelTitleLabel.stringValue = title
                self.heroTitleLabel.stringValue = title
                self.composerPlaceholderLabel.stringValue = "Write to \(title)"
                self.entryView.placeholderString = self.composerPlaceholderLabel.stringValue
                if self.contentView != nil {
                    self.layoutRightChatPanel()
                }
                self.loadChannelPosts(forSidebarItemId: id)
            }
        }
        
        return SidebarItemView(
            id: id,
            isSelectable: isSelectable,
            isBotBadge: isBotBadge || (customImage != nil),
            row: row,
            leftBar: leftBar,
            iconView: iconView,
            label: label,
            hoverCloseView: closeView
        )
    }
    
    private func toggleSidebarCategory(_ categoryId: String) {
        guard let idx = sidebarCategories.firstIndex(where: { $0.id == categoryId }) else { return }
        sidebarCategories[idx].isCollapsed.toggle()
        let collapsed = sidebarCategories[idx].isCollapsed
        let symbolName = collapsed ? "chevron.right" : "chevron.down"
        if let chevImg = NSImage(systemSymbolName: symbolName, accessibilityDescription: sidebarCategories[idx].titleLabel.stringValue) {
            sidebarCategories[idx].chevronView.image = chevImg.withSymbolConfiguration(.init(pointSize: 8.5, weight: .bold))
        }
        if let contentView = contentView {
            layoutLeftSidebar(topBarY: mainPanel.bounds.height)
        }
    }
    
    private func updateSidebarSelectionAppearance() {
        let allItems: [SidebarItemView] = (threadsSidebarItem.map { [$0] } ?? [])
            + (favoritesCategory?.items ?? [])
            + sidebarCategories.flatMap { $0.items }
        // Web: selected and hovered rows both use 8% white, labels are 14pt regular.
        let selectedBg = NSColor(white: 1.0, alpha: 0.08)
        let hoverBg = NSColor(white: 1.0, alpha: 0.08)
        let defaultText = NSColor(white: 1.0, alpha: 0.64)
        let defaultIcon = NSColor(white: 1.0, alpha: 0.64)
        
        for item in allItems {
            let isSelected = item.isSelectable && (item.id == selectedSidebarItemId)
            let isHovered = item.row.isHovered
            
            if isSelected {
                item.row.color = selectedBg
                item.label.font = MMFont.font(ofSize: 14, weight: .regular)
                item.label.textColor = .white
                if !item.isBotBadge {
                    item.iconView.contentTintColor = .white
                } else {
                    item.iconView.contentTintColor = nil
                }
            } else if isHovered {
                item.row.color = hoverBg
                item.label.font = MMFont.font(ofSize: 14, weight: .regular)
                item.label.textColor = .white
                if !item.isBotBadge {
                    item.iconView.contentTintColor = .white
                } else {
                    item.iconView.contentTintColor = nil
                }
            } else {
                item.row.color = .clear
                item.label.font = MMFont.font(ofSize: 14, weight: .regular)
                item.label.textColor = defaultText
                if !item.isBotBadge {
                    item.iconView.contentTintColor = defaultIcon
                } else {
                    item.iconView.contentTintColor = nil
                }
            }
            item.leftBar.isHidden = !isSelected
            item.leftBar.color = NSColor(red: 93 / 255, green: 137 / 255, blue: 234 / 255, alpha: 1.0)
            item.leftBar.setNeedsAppearanceUpdate()
            item.row.setNeedsAppearanceUpdate()
            item.hoverCloseView?.isHidden = !isHovered
        }
    }
    
    private func layoutTeamHeader(topBarY: CGFloat? = nil) {
        let top = topBarY ?? (mainPanel.bounds.height > 0 ? mainPanel.bounds.height : (contentView?.bounds.height ?? 800) - 44)
        let textWidth = ceil(teamHeaderLabel.attributedStringValue.size().width)
        let maxLabelWidth: CGFloat = 202
        let labelWidth = max(24, min(textWidth + 4, maxLabelWidth))
        // Web: 6pt leading padding, 2pt between label and chevron, 12pt chevron, 5pt trailing.
        let buttonWidth = 6 + labelWidth + 2 + 12 + 5
        
        teamHeaderButton.frame = NSRect(x: 17, y: top - 43.5, width: buttonWidth, height: 32)
        teamHeaderLabel.frame = NSRect(x: 6, y: (32 - 22) / 2, width: labelWidth, height: 22)
        teamHeaderChevron.frame = NSRect(x: 6 + labelWidth + 2, y: (32 - 12) / 2, width: 12, height: 12)
        
        rebuildTeamMenu()
    }
    
    private func rebuildTeamMenu() {
        teamDropdownMenu.subviews.forEach { $0.removeFromSuperview() }
        
        let rowHeight: CGFloat = 34
        let teamsToDisplay = userTeams.isEmpty ? (activeTeam != nil ? [activeTeam!] : []) : userTeams
        let menuHeight: CGFloat = max(42, CGFloat(teamsToDisplay.count) * rowHeight + 12)
        let menuWidth: CGFloat = 220
        let menuX: CGFloat = 8
        let menuY = teamHeaderButton.frame.minY - menuHeight - 4
        
        teamDropdownMenu.frame = NSRect(x: menuX, y: menuY, width: menuWidth, height: menuHeight)
        teamDropdownMenu.color = .white
        teamDropdownMenu.cornerRadius = 6
        teamDropdownMenu.borderWidth = 1
        teamDropdownMenu.borderColor = NSColor(white: 0.85, alpha: 1.0)
        teamDropdownMenu.shadowColor = .black
        teamDropdownMenu.shadowOpacity = 0.18
        teamDropdownMenu.shadowRadius = 12
        teamDropdownMenu.shadowOffset = CGSize(width: 0, height: -4)
        
        if teamsToDisplay.isEmpty {
            let emptyLabel = NSTextField(labelWithString: "No teams available")
            emptyLabel.font = MMFont.font(ofSize: 13, weight: .regular)
            emptyLabel.textColor = NSColor(white: 0.5, alpha: 1.0)
            emptyLabel.frame = NSRect(x: 14, y: 10, width: menuWidth - 28, height: 20)
            teamDropdownMenu.addSubview(emptyLabel)
            return
        }
        
        var yPos = menuHeight - 6 - rowHeight
        for team in teamsToDisplay {
            let row = RoundedEdgePanel()
            row.frame = NSRect(x: 6, y: yPos, width: menuWidth - 12, height: rowHeight)
            row.cornerRadius = 4
            row.color = .clear
            
            let isActive = team.id == activeTeam?.id
            let label = NSTextField(labelWithString: team.display_name.isEmpty ? team.name : team.display_name)
            label.font = MMFont.font(ofSize: 13.5, weight: isActive ? .bold : .medium)
            label.textColor = NSColor(white: 0.15, alpha: 1.0)
            label.isEditable = false
            label.isSelectable = false
            label.frame = NSRect(x: 10, y: 7, width: menuWidth - 52, height: 20)
            row.addSubview(label)
            
            if isActive {
                let checkView = NSImageView()
                if let checkImg = NSImage(systemSymbolName: "checkmark", accessibilityDescription: "Active") {
                    checkView.image = checkImg.withSymbolConfiguration(.init(pointSize: 11, weight: .bold))
                    checkView.contentTintColor = NSColor(srgbRed: 0.11, green: 0.35, blue: 0.85, alpha: 1.0)
                }
                checkView.frame = NSRect(x: menuWidth - 36, y: 9, width: 16, height: 16)
                row.addSubview(checkView)
            }
            
            row.onHoverChanged = { [weak row] isHovered in
                row?.color = isHovered ? NSColor(white: 0.94, alpha: 1.0) : .clear
                row?.setNeedsAppearanceUpdate()
            }
            
            row.onClick = { [weak self] in
                self?.switchActiveTeam(to: team)
            }
            
            teamDropdownMenu.addSubview(row)
            yPos -= rowHeight
        }
    }
    
    @MainActor
    private func updateTeamHeader(with team: MMTeam) {
        self.activeTeam = team
        self.teamHeaderLabel.stringValue = team.display_name.isEmpty ? team.name : team.display_name
        self.layoutTeamHeader()
    }
    
    @MainActor
    private func switchActiveTeam(to team: MMTeam) {
        guard let ws = (NSApp.delegate as? AppDelegate)?.webService else { return }
        self.updateTeamHeader(with: team)
        self.setTeamMenuOpen(false)
        Task { @MainActor [weak self] in
            guard let self = self else { return }
            do {
                let channels = try await ws.fetchChannels(teamId: team.id)
                var allChannels = channels
                if let myChannels = try? await ws.fetchAllChannels() {
                    var chMap: [String: MMChannel] = [:]
                    for c in channels { chMap[c.id] = c }
                    for c in myChannels { chMap[c.id] = c }
                    allChannels = Array(chMap.values)
                }
                self.channelsById.removeAll()
                self.channelsByName.removeAll()
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
                NSLog("Failed to switch team: \(error.localizedDescription)")
            }
        }
    }
    
    private func layoutLeftSidebar(topBarY: CGFloat) {
        // Matches the web client at >=1201px: 264pt sidebar starting 5pt from the
        // window edge, 32pt rows, 19/16pt horizontal padding.
        let sidebarX: CGFloat = 1
        let sidebarWidth: CGFloat = 264
        
        // Row 1: Team header button + "+" button
        layoutTeamHeader(topBarY: topBarY)
        
        teamAddButton.frame = NSRect(x: sidebarX + 216, y: topBarY - 43.5, width: 32, height: 32)
        teamAddIconView.frame = NSRect(x: 7, y: 7, width: 18, height: 18)
        
        // Row 2: Filter button + "Find channel" pill
        filterChannelButton.frame = NSRect(x: sidebarX + 16, y: topBarY - 83, width: 28, height: 28)
        filterChannelIconView.frame = NSRect(x: 4, y: 4, width: 20, height: 20)
        filterMenu.frame = NSRect(x: sidebarX + 16, y: topBarY - 83 - 8 - 68, width: 180, height: 68)
        
        findChannelPanel.frame = NSRect(x: sidebarX + 48, y: topBarY - 83, width: 200, height: 28)
        findChannelIconView.frame = NSRect(x: 2, y: 5, width: 18, height: 18)
        findChannelLabel.frame = NSRect(x: 29, y: 4, width: 165, height: 20)
        
        let query = channelFilterQuery.lowercased()
        func matches(_ title: String) -> Bool {
            query.isEmpty || title.lowercased().contains(query)
        }
        
        // Row 3: Threads item
        var currentY = topBarY - 126
        if let threads = threadsSidebarItem {
            if matches(threads.label.stringValue) && !sidebarFavoritesOnly {
                threads.row.isHidden = false
                threads.row.frame = NSRect(x: sidebarX, y: currentY, width: sidebarWidth, height: 32)
                threads.leftBar.frame = NSRect(x: 0, y: 0, width: 4, height: 32)
                threads.iconView.frame = NSRect(x: 21, y: 7, width: 18, height: 18)
                threads.label.frame = NSRect(x: 49, y: 6, width: sidebarWidth - 64, height: 20)
                currentY -= 32
            } else {
                threads.row.isHidden = true
            }
        }
        
        // Favorites branch (channels marked with the star)
        if let favorites = favoritesCategory {
            let visibleFavorites = favorites.items.filter { matches($0.label.stringValue) }
            if !visibleFavorites.isEmpty || query.isEmpty {
                favorites.headerRow.isHidden = false
                favorites.headerRow.frame = NSRect(x: sidebarX, y: currentY, width: sidebarWidth, height: 32)
                favorites.chevronView.frame = NSRect(x: 1, y: 8, width: 16, height: 16)
                let chevron = isFavoritesCollapsed ? "chevron.right" : "chevron.down"
                if let img = NSImage(systemSymbolName: chevron, accessibilityDescription: "Favorites") {
                    favorites.chevronView.image = img.withSymbolConfiguration(.init(pointSize: 9, weight: .bold))
                }
                favorites.titleLabel.frame = NSRect(x: 17, y: 7, width: sidebarWidth - 60, height: 18)
                currentY -= 32
                for item in favorites.items {
                    if !matches(item.label.stringValue) || isFavoritesCollapsed {
                        item.row.isHidden = true
                        continue
                    }
                    item.row.isHidden = false
                    item.row.frame = NSRect(x: sidebarX, y: currentY, width: sidebarWidth, height: 32)
                    item.leftBar.frame = NSRect(x: 0, y: 0, width: 4, height: 32)
                    item.iconView.frame = NSRect(x: 21, y: 7, width: 18, height: 18)
                    item.label.frame = NSRect(x: 49, y: 6, width: sidebarWidth - 74, height: 20)
                    currentY -= 32
                }
                currentY -= 8
            } else {
                favorites.headerRow.isHidden = true
                favorites.items.forEach { $0.row.isHidden = true }
            }
        }
        
        // Categories & items (the server's own favorites group is replaced by
        // the locally derived FAVORITES branch above)
        for category in sidebarCategories where !category.id.lowercased().contains("favorites") {
            let visibleItems = category.items.filter {
                matches($0.label.stringValue)
                    && !favoriteChannelIds.contains($0.id)
                    && (!sidebarFavoritesOnly || favoriteChannelIds.contains($0.id))
            }
            if !query.isEmpty && visibleItems.isEmpty {
                category.headerRow.isHidden = true
                category.items.forEach { $0.row.isHidden = true }
                continue
            }
            category.headerRow.isHidden = false
            category.headerRow.frame = NSRect(x: sidebarX, y: currentY, width: sidebarWidth, height: 32)
            category.chevronView.frame = NSRect(x: 1, y: 8, width: 16, height: 16)
            category.titleLabel.frame = NSRect(x: 17, y: 7, width: sidebarWidth - 60, height: 18)
            category.addButton?.frame = NSRect(x: sidebarWidth - 32, y: 6, width: 20, height: 20)
            currentY -= 32
            
            for item in category.items {
                if !matches(item.label.stringValue)
                    || favoriteChannelIds.contains(item.id)
                    || (sidebarFavoritesOnly && !favoriteChannelIds.contains(item.id)) {
                    item.row.isHidden = true
                } else if category.isCollapsed && item.id != selectedSidebarItemId {
                    item.row.isHidden = true
                } else {
                    item.row.isHidden = false
                    item.row.frame = NSRect(x: sidebarX, y: currentY, width: sidebarWidth, height: 32)
                    item.leftBar.frame = NSRect(x: 0, y: 0, width: 4, height: 32)
                    item.iconView.frame = NSRect(x: 21, y: 7, width: 18, height: 18)
                    item.label.frame = NSRect(x: 49, y: 6, width: sidebarWidth - 74, height: 20)
                    item.hoverCloseView?.frame = NSRect(x: sidebarWidth - 28, y: 10, width: 12, height: 12)
                    currentY -= 32
                }
            }
            currentY -= 8
        }
    }
    
    private func setupFilterMenu() {
        let dividerColor = NSColor(red: 229 / 255, green: 231 / 255, blue: 235 / 255, alpha: 1.0)
        let textColor = NSColor(red: 31 / 255, green: 41 / 255, blue: 55 / 255, alpha: 1.0)
        
        filterMenu.color = .white
        filterMenu.cornerRadius = 6
        filterMenu.borderWidth = 1
        filterMenu.borderColor = dividerColor
        filterMenu.shadowColor = .black
        filterMenu.shadowOpacity = 0.18
        filterMenu.shadowRadius = 10
        filterMenu.shadowOffset = CGSize(width: 0, height: -4)
        filterMenu.isHidden = true
        
        let makeRow: (String, CGFloat, Bool) -> (RoundedEdgePanel, NSImageView) = { title, y, favorites in
            let row = RoundedEdgePanel()
            row.frame = NSRect(x: 6, y: y, width: 168, height: 28)
            row.cornerRadius = 4
            row.color = .clear
            let label = NSTextField(labelWithString: title)
            label.font = MMFont.font(ofSize: 13)
            label.textColor = textColor
            label.isEditable = false
            label.isSelectable = false
            label.frame = NSRect(x: 10, y: 5, width: 120, height: 18)
            row.addSubview(label)
            let check = NSImageView()
            if let image = NSImage(systemSymbolName: "checkmark", accessibilityDescription: "Selected") {
                check.image = image.withSymbolConfiguration(.init(pointSize: 11, weight: .bold))
                check.contentTintColor = NSColor(red: 28 / 255, green: 88 / 255, blue: 217 / 255, alpha: 1.0)
            }
            check.frame = NSRect(x: 146, y: 7, width: 14, height: 14)
            row.addSubview(check)
            row.onHoverChanged = { [weak row] isHovered in
                row?.color = isHovered
                    ? NSColor(red: 243 / 255, green: 244 / 255, blue: 246 / 255, alpha: 1.0)
                    : .clear
                row?.setNeedsAppearanceUpdate()
            }
            row.onClick = { [weak self] in
                guard let self = self else { return }
                self.sidebarFavoritesOnly = favorites
                self.setFilterMenuOpen(false)
                self.updateFilterMenuAppearance()
                self.layoutLeftSidebar(topBarY: self.mainPanel.bounds.height)
            }
            return (row, check)
        }
        
        let all = makeRow("All channels", 36, false)
        filterMenu.addSubview(all.0)
        filterAllCheck = all.1
        let favorites = makeRow("Favorites", 6, true)
        filterMenu.addSubview(favorites.0)
        filterFavoritesCheck = favorites.1
        
        mainPanel.addSubview(filterMenu)
        updateFilterMenuAppearance()
    }
    
    private func setFilterMenuOpen(_ open: Bool) {
        isFilterMenuOpen = open
        filterMenu.isHidden = !open
    }
    
    private func updateFilterMenuAppearance() {
        filterAllCheck?.isHidden = sidebarFavoritesOnly
        filterFavoritesCheck?.isHidden = !sidebarFavoritesOnly
    }
    
    private func setupRightChatPanel() {
        let darkText = NSColor(red: 31 / 255, green: 41 / 255, blue: 55 / 255, alpha: 1.0)
        let mutedText = NSColor(red: 107 / 255, green: 114 / 255, blue: 128 / 255, alpha: 1.0)
        let lightPlaceholder = NSColor(red: 156 / 255, green: 163 / 255, blue: 175 / 255, alpha: 1.0)
        let dividerColor = NSColor(red: 229 / 255, green: 231 / 255, blue: 235 / 255, alpha: 1.0)
        let hoverBg = NSColor(red: 243 / 255, green: 244 / 255, blue: 246 / 255, alpha: 1.0)
        let msgHoverBg = NSColor(red: 249 / 255, green: 250 / 255, blue: 251 / 255, alpha: 1.0)
        let brandBlue = NSColor(red: 28 / 255, green: 88 / 255, blue: 217 / 255, alpha: 1.0)
        let brandBlueHover = NSColor(red: 22 / 255, green: 70 / 255, blue: 176 / 255, alpha: 1.0)
        let starGold = NSColor(red: 245 / 255, green: 171 / 255, blue: 0 / 255, alpha: 1.0)
        
        // 0. Timeline clipping container (clips messages & hero text to channelHeaderBorder below star icon)
        chatTimelineContainer.wantsLayer = true
        chatTimelineContainer.layer?.masksToBounds = true
        chatPanel.addSubview(chatTimelineContainer, positioned: .below, relativeTo: chatEntryPanel)
        
        // 1. Channel Header Bar
        channelHeaderBorder.cornerRadius = 0
        channelHeaderBorder.color = dividerColor
        chatPanel.addSubview(channelHeaderBorder)
        
        channelStarButton.cornerRadius = 4
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
        
        channelTitleButton.cornerRadius = 4
        channelTitleButton.color = .clear
        channelTitleLabel.font = MMFont.font(ofSize: 14, weight: .semibold)
        channelTitleLabel.textColor = darkText
        channelTitleLabel.isEditable = false
        channelTitleLabel.isSelectable = false
        channelTitleButton.addSubview(channelTitleLabel)
        
        channelHeaderBotBadge.cornerRadius = 4
        channelHeaderBotBadge.color = NSColor(red: 63 / 255, green: 67 / 255, blue: 80 / 255, alpha: 0.12)
        channelHeaderBotBadgeLabel.font = MMFont.font(ofSize: 9.5, weight: .bold)
        channelHeaderBotBadgeLabel.textColor = NSColor(red: 63 / 255, green: 67 / 255, blue: 80 / 255, alpha: 0.75)
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
        chatPanel.addSubview(channelTitleButton)
        
        channelMembersButton.cornerRadius = 4
        channelMembersButton.color = .clear
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
        
        channelPinsButton.cornerRadius = 4
        channelPinsButton.color = .clear
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
        
        channelSidebarButton.cornerRadius = 4
        channelSidebarButton.color = .clear
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
        
        channelInfoButton.cornerRadius = 4
        channelInfoButton.color = .clear
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
        chatPanel.addSubview(channelInfoButton)
        
        // 2. Welcome Hero Section (Illustration + Title + Subtitle + Invite button)
        timelineHeroContainer.cornerRadius = 0
        timelineHeroContainer.color = .clear
        
        heroIllustrationCircle.cornerRadius = 38
        heroIllustrationCircle.color = NSColor(red: 243 / 255, green: 244 / 255, blue: 246 / 255, alpha: 1.0)
        timelineHeroContainer.addSubview(heroIllustrationCircle)
        
        heroBotAvatarView.imageScaling = .scaleProportionallyUpOrDown
        heroBotAvatarView.isHidden = true
        heroIllustrationCircle.addSubview(heroBotAvatarView)
        
        heroWhiteBubble.cornerRadius = 4
        heroWhiteBubble.borderWidth = 1.5
        heroWhiteBubble.color = NSColor(red: 156 / 255, green: 163 / 255, blue: 175 / 255, alpha: 1.0)
        for i in 0..<3 {
            let line = RoundedEdgePanel()
            line.cornerRadius = 1
            line.color = NSColor(red: 156 / 255, green: 163 / 255, blue: 175 / 255, alpha: 1.0)
            let w: CGFloat = (i == 2) ? 20 : 32
            line.frame = NSRect(x: 9, y: CGFloat(24 - i * 7), width: w, height: 2)
            heroWhiteBubble.addSubview(line)
        }
        timelineHeroContainer.addSubview(heroWhiteBubble)
        
        heroBlueBubble.cornerRadius = 4
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
        
        heroBotBadge.cornerRadius = 4
        heroBotBadge.color = NSColor(red: 63 / 255, green: 67 / 255, blue: 80 / 255, alpha: 0.12)
        heroBotBadgeLabel.font = MMFont.font(ofSize: 10, weight: .bold)
        heroBotBadgeLabel.textColor = NSColor(red: 63 / 255, green: 67 / 255, blue: 80 / 255, alpha: 0.75)
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
        heroDescriptionLabel.isEditable = false
        heroDescriptionLabel.isSelectable = false
        timelineHeroContainer.addSubview(heroDescriptionLabel)
        
        heroInviteButton.cornerRadius = 4
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
            self?.updateTimelineHoverState()
        }
        
        // 4. Message Composer (Non-editable placeholder + Formatting Toolbar + Help link)
        // The editor draws its own placeholder; keep the label only as the
        // canonical string source and never put it in the hit-test path.
        composerPlaceholderLabel.font = MMFont.font(ofSize: 14)
        composerPlaceholderLabel.textColor = NSColor(red: 153 / 255, green: 153 / 255, blue: 153 / 255, alpha: 1.0)
        composerPlaceholderLabel.isEditable = false
        composerPlaceholderLabel.isSelectable = false
        composerPlaceholderLabel.isHidden = true
        
        composerLeftButtons.removeAll()
        let leftSymbols: [String] = [
            "bold",
            "italic",
            "strikethrough",
            "number",
            "link",
            "chevron.left.forwardslash.chevron.right",
            "text.quote",
            "list.bullet",
            "list.number",
            "info.circle"
        ]
        for sym in leftSymbols {
            let btn = RoundedEdgePanel()
            btn.cornerRadius = 4
            btn.color = .clear
            let icon = NSImageView()
            if let img = NSImage(systemSymbolName: sym, accessibilityDescription: sym) {
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
            chatEntryPanel.addSubview(btn)
            composerLeftButtons.append(btn)
        }
        
        composerLeftSeparator.cornerRadius = 0
        composerLeftSeparator.color = dividerColor
        chatEntryPanel.addSubview(composerLeftSeparator)
        
        // Right composer toolbar controls: "Aa ^" | sep | Emoji | Paperclip | Send
        composerAaButton.cornerRadius = 4
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
        chatEntryPanel.addSubview(composerAaButton)
        
        composerRightSeparator.cornerRadius = 0
        composerRightSeparator.color = dividerColor
        chatEntryPanel.addSubview(composerRightSeparator)
        
        let setupRightIconBtn: (RoundedEdgePanel, String) -> Void = { btn, sym in
            btn.cornerRadius = 4
            btn.color = .clear
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
        composerEmojiButton.onClick = { [weak self] in
            self?.toggleEmojiPanel()
        }

        // GIF button in composer
        composerGifButton.cornerRadius = 4
        composerGifButton.color = .clear
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
        composerGifButton.onClick = { [weak self] in
            guard let self = self else { return }
            let nowMs = Int64(Date().timeIntervalSince1970 * 1000)
            let newPost = MMPost(
                id: "giphy_\(nowMs)",
                create_at: nowMs,
                update_at: nil, edit_at: nil, delete_at: nil, is_pinned: false,
                user_id: self.currentUser?.id ?? "usr",
                channel_id: self.activeChannelId,
                root_id: nil, original_id: nil,
                message: "![waving cat](https://media.giphy.com/media/ICOgUNjpvO0PC/giphy.gif)",
                type: nil
            )
            self.currentChannelPosts.append(newPost)
            self.rebuildTimelineContent(scrollToBottom: true)
        }
        chatEntryPanel.addSubview(composerGifButton)

        setupRightIconBtn(composerAttachButton, "paperclip")
        composerAttachButton.onClick = { [weak self] in
            self?.attachFiles()
        }
        
        composerSendButton.cornerRadius = 4
        composerSendButton.color = NSColor(red: 63 / 255, green: 67 / 255, blue: 80 / 255, alpha: 0.08)
        let sendIcon = NSImageView()
        if let sImg = NSImage(systemSymbolName: "paperplane.fill", accessibilityDescription: "Send") {
            sendIcon.image = sImg.withSymbolConfiguration(.init(pointSize: 15, weight: .regular))
            sendIcon.contentTintColor = NSColor(red: 63 / 255, green: 67 / 255, blue: 80 / 255, alpha: 0.32)
        }
        sendIcon.frame = NSRect(x: 15, y: 7, width: 18, height: 18)
        composerSendButton.addSubview(sendIcon)
        composerSendIconView = sendIcon
        composerSendButton.onHoverChanged = { [weak self] isHovered in
            guard let self = self else { return }
            if self.composerSendEnabled {
                self.composerSendButton.color = isHovered
                    ? NSColor(red: 22 / 255, green: 70 / 255, blue: 176 / 255, alpha: 1.0)
                    : NSColor(red: 28 / 255, green: 88 / 255, blue: 217 / 255, alpha: 1.0)
            } else {
                self.composerSendButton.color = NSColor(red: 63 / 255, green: 67 / 255, blue: 80 / 255, alpha: 0.08)
            }
            self.composerSendButton.setNeedsAppearanceUpdate()
        }
        composerSendButton.onClick = { [weak self] in
            self?.sendComposerMessage()
        }
        chatEntryPanel.addSubview(composerSendButton)
        
        composerHelpLabel.font = MMFont.font(ofSize: 12)
        composerHelpLabel.textColor = NSColor(red: 63 / 255, green: 67 / 255, blue: 80 / 255, alpha: 0.75)
        composerHelpLabel.alignment = .right
        composerHelpLabel.isEditable = false
        composerHelpLabel.isSelectable = false
        chatPanel.addSubview(composerHelpLabel)
        
        applyComposerToolbarVisibility()
        updateComposerSendState()
        setupRightPanel()
        setupEmojiPanel()
        setupChannelMenu()
        rebuildTimelineContent(scrollToBottom: true)
    }
    
    // MARK: - Right-hand side panel
    
    // MARK: - Composer actions
    
    // MARK: - Channel menu
    
    private func setupChannelMenu() {
        channelMenu.color = .white
        channelMenu.cornerRadius = 6
        channelMenu.borderWidth = 1
        channelMenu.borderColor = NSColor(red: 229 / 255, green: 231 / 255, blue: 235 / 255, alpha: 1.0)
        channelMenu.shadowColor = .black
        channelMenu.shadowOpacity = 0.18
        channelMenu.shadowRadius = 12
        channelMenu.shadowOffset = CGSize(width: 0, height: -4)
        channelMenu.isHidden = true
        chatPanel.addSubview(channelMenu)
    }
    
    private func toggleChannelMenu() {
        if isChannelMenuOpen {
            closeChannelMenu()
        } else {
            showChannelMenu()
        }
    }
    
    private func closeChannelMenu() {
        channelMenu.isHidden = true
        isChannelMenuOpen = false
    }
    
    private func showChannelMenu() {
        guard !activeChannelId.isEmpty, let channel = channelsById[activeChannelId] else { return }
        let channelName = channelDisplayName(for: channel)
        let favoriteTitle = isChannelFavorited ? "Remove from Favorites" : "Add to Favorites"
        let rows: [(symbol: String, title: String, action: () -> Void)] = [
            ("info.circle", "View Info", { [weak self] in
                self?.closeChannelMenu()
                self?.showRightPanel(mode: .members)
            }),
            ("pin", "Pinned Posts", { [weak self] in
                self?.closeChannelMenu()
                self?.showRightPanel(mode: .pinned)
            }),
            (isChannelFavorited ? "star.slash" : "star", favoriteTitle, { [weak self] in
                guard let self = self else { return }
                self.closeChannelMenu()
                self.setChannelFavorite(!self.isChannelFavorited, channelId: self.activeChannelId)
            }),
            ("link", "Copy Link", { [weak self] in
                guard let self = self else { return }
                self.closeChannelMenu()
                self.copyChannelLink()
            }),
            ("rectangle.portrait.and.arrow.right", "Leave Channel", { [weak self] in
                self?.closeChannelMenu()
                self?.confirmLeaveChannel()
            })
        ]
        
        channelMenu.subviews.forEach { $0.removeFromSuperview() }
        
        let rowHeight: CGFloat = 32
        let width: CGFloat = 230
        let height = CGFloat(rows.count) * rowHeight + 8
        var x = channelTitleButton.frame.minX
        x = min(max(8, x), chatPanel.bounds.width - width - 8)
        var y = channelTitleButton.frame.minY - height - 4
        if y < 8 { y = channelTitleButton.frame.maxY + 4 }
        channelMenu.frame = NSRect(x: x, y: y, width: width, height: height)
        
        let textColor = NSColor(red: 31 / 255, green: 41 / 255, blue: 55 / 255, alpha: 1.0)
        let iconColor = NSColor(red: 107 / 255, green: 114 / 255, blue: 128 / 255, alpha: 1.0)
        for (index, item) in rows.enumerated() {
            let row = RoundedEdgePanel()
            row.cornerRadius = 4
            row.color = .clear
            row.frame = NSRect(
                x: 4,
                y: height - 4 - CGFloat(index + 1) * rowHeight,
                width: width - 8,
                height: rowHeight
            )
            let icon = NSImageView()
            if let image = NSImage(systemSymbolName: item.symbol, accessibilityDescription: item.title) {
                icon.image = image.withSymbolConfiguration(.init(pointSize: 12, weight: .medium))
                icon.contentTintColor = iconColor
            }
            icon.frame = NSRect(x: 8, y: 8, width: 16, height: 16)
            row.addSubview(icon)
            
            let label = NSTextField(labelWithString: item.title)
            label.font = MMFont.font(ofSize: 13)
            label.textColor = textColor
            label.isEditable = false
            label.isSelectable = false
            label.frame = NSRect(x: 32, y: 7, width: width - 48, height: 18)
            row.addSubview(label)
            
            row.onHoverChanged = { [weak row] isHovered in
                row?.color = isHovered
                    ? NSColor(red: 243 / 255, green: 244 / 255, blue: 246 / 255, alpha: 1.0)
                    : .clear
                row?.setNeedsAppearanceUpdate()
            }
            row.onClick = item.action
            channelMenu.addSubview(row)
        }
        
        channelMenu.isHidden = false
        channelMenu.superview?.addSubview(channelMenu)
        isChannelMenuOpen = true
    }
    
    private func copyChannelLink() {
        guard let channel = channelsById[activeChannelId] else { return }
        var host = UserDefaults.standard.string(forKey: "host") ?? ""
        let port = UserDefaults.standard.integer(forKey: "port")
        if port > 0 && !host.hasSuffix(":\(port)") {
            host += ":\(port)"
        }
        let teamName = activeTeam?.name ?? ""
        let url = "\(host)/\(teamName)/channels/\(channel.name)"
        NSPasteboard.general.clearContents()
        NSPasteboard.general.setString(url, forType: .string)
        composerHelpLabel.stringValue = "Link copied"
        DispatchQueue.main.asyncAfter(deadline: .now() + 2) { [weak self] in
            self?.composerHelpLabel.stringValue = "Help"
        }
    }
    
    private func confirmLeaveChannel() {
        guard let channel = channelsById[activeChannelId] else { return }
        let alert = NSAlert()
        alert.messageText = "Leave \(channelDisplayName(for: channel))?"
        alert.informativeText = "You will stop receiving messages from this channel."
        alert.addButton(withTitle: "Leave")
        alert.addButton(withTitle: "Cancel")
        alert.beginSheetModal(for: self) { [weak self] response in
            guard let self = self, response == .alertFirstButtonReturn else { return }
            self.leaveChannel(channel)
        }
    }
    
    private func leaveChannel(_ channel: MMChannel) {
        guard let ws = (NSApp.delegate as? AppDelegate)?.webService, ws.isLogged(),
              let team = activeTeam else { return }
        let userId = currentUser?.id ?? ws.currentUserId
        guard !userId.isEmpty else { return }
        Task { @MainActor [weak self] in
            guard let self = self else { return }
            do {
                try await ws.leaveChannel(channelId: channel.id, userId: userId)
                self.channelsById.removeValue(forKey: channel.id)
                self.channelsByName.removeValue(forKey: channel.name.lowercased())
                self.channelsByName.removeValue(forKey: channel.display_name.lowercased())
                if let categories = try? await ws.fetchSidebarCategories(teamId: team.id) {
                    self.populateSidebarCategories(from: categories, channels: Array(self.channelsById.values))
                }
                if self.activeChannelId == channel.id,
                   let fallback = self.channelsByName["town-square"] ?? self.channelsById.values.first {
                    self.selectedSidebarItemId = fallback.id
                    self.updateSidebarSelectionAppearance()
                    self.loadChannelPosts(forSidebarItemId: fallback.id)
                }
            } catch {
                self.showInfoAlert("Could not leave channel: \(error.localizedDescription)")
            }
        }
    }
    
    private func setupEmojiPanel() {
        let dividerColor = NSColor(red: 229 / 255, green: 231 / 255, blue: 235 / 255, alpha: 1.0)
        emojiPanel.color = .white
        emojiPanel.cornerRadius = 8
        emojiPanel.borderWidth = 1
        emojiPanel.borderColor = dividerColor
        emojiPanel.shadowColor = .black
        emojiPanel.shadowOpacity = 0.18
        emojiPanel.shadowRadius = 12
        emojiPanel.shadowOffset = CGSize(width: 0, height: -4)
        emojiPanel.isHidden = true
        
        let emojis: [String] = [
            "😀", "😃", "😄", "😁", "😆", "😅", "😂", "🤣",
            "😊", "😇", "🙂", "😉", "😍", "🥰", "😘", "😋",
            "😜", "🤪", "🤨", "🧐", "🤓", "😎", "🥳", "😏",
            "😒", "😞", "😔", "😟", "😕", "🙁", "😣", "😖",
            "😫", "😩", "🥺", "😢", "😭", "😤", "😠", "👍"
        ]
        let cell: CGFloat = 32
        let gap: CGFloat = 4
        let margin: CGFloat = 8
        for (index, emoji) in emojis.enumerated() {
            let column = index % 8
            let row = index / 8
            let button = RoundedEdgePanel()
            button.cornerRadius = 4
            button.color = .clear
            button.frame = NSRect(
                x: margin + CGFloat(column) * (cell + gap),
                y: margin + CGFloat(4 - row) * (cell + gap),
                width: cell,
                height: cell
            )
            let label = NSTextField(labelWithString: emoji)
            label.font = MMFont.font(ofSize: 20)
            label.alignment = .center
            label.isEditable = false
            label.isSelectable = false
            label.frame = NSRect(x: 0, y: 4, width: cell, height: 24)
            button.addSubview(label)
            button.onHoverChanged = { [weak button] isHovered in
                button?.color = isHovered
                    ? NSColor(red: 243 / 255, green: 244 / 255, blue: 246 / 255, alpha: 1.0)
                    : .clear
                button?.setNeedsAppearanceUpdate()
            }
            button.onClick = { [weak self] in
                self?.insertEmoji(emoji)
            }
            emojiPanel.addSubview(button)
        }
        emojiPanel.frame = NSRect(x: 0, y: 0, width: 300, height: 192)
    }
    
    private func toggleEmojiPanel() {
        if isEmojiPanelOpen {
            closeEmojiPanel()
            return
        }
        guard !activeChannelId.isEmpty else { return }
        let buttonFrame = chatEntryPanel.convert(composerEmojiButton.frame, to: chatPanel)
        let width: CGFloat = 300
        let height: CGFloat = 192
        let x = min(max(8, buttonFrame.midX - width / 2), max(8, chatPanel.bounds.width - width - 8))
        let y = min(chatEntryPanel.frame.maxY + 8, chatPanel.bounds.height - height - 8)
        emojiPanel.frame = NSRect(x: x, y: y, width: width, height: height)
        emojiPanel.removeFromSuperview()
        chatPanel.addSubview(emojiPanel)
        emojiPanel.isHidden = false
        isEmojiPanelOpen = true
    }
    
    private func closeEmojiPanel() {
        emojiPanel.isHidden = true
        isEmojiPanelOpen = false
    }
    
    private func insertEmoji(_ emoji: String) {
        let range = entryView.selectedRange()
        entryView.insertText(emoji, replacementRange: range)
        entryView.needsDisplay = true
        updateComposerSendState()
        closeEmojiPanel()
        makeFirstResponder(entryView)
    }
    
    private func attachFiles() {
        guard !activeChannelId.isEmpty else { return }
        let panel = NSOpenPanel()
        panel.allowsMultipleSelection = true
        panel.canChooseDirectories = false
        panel.canChooseFiles = true
        panel.beginSheetModal(for: self) { [weak self] response in
            guard response == .OK, let self = self else { return }
            self.uploadAndSendFiles(panel.urls)
        }
    }
    
    private func uploadAndSendFiles(_ urls: [URL]) {
        guard !urls.isEmpty,
              !activeChannelId.isEmpty,
              let ws = (NSApp.delegate as? AppDelegate)?.webService else { return }
        let channelId = activeChannelId
        let message = entryView.string.trimmingCharacters(in: .whitespacesAndNewlines)
        composerHelpLabel.stringValue = "Uploading…"
        
        Task { @MainActor [weak self] in
            guard let self = self else { return }
            var fileIds: [String] = []
            for url in urls {
                guard let data = try? Data(contentsOf: url) else { continue }
                let mime = UTType(filenameExtension: url.pathExtension)?.preferredMIMEType ?? "application/octet-stream"
                if let fileId = try? await ws.uploadFile(
                    channelId: channelId,
                    data: data,
                    filename: url.lastPathComponent,
                    mimeType: mime
                ) {
                    fileIds.append(fileId)
                }
            }
            guard !fileIds.isEmpty else {
                self.composerHelpLabel.stringValue = "Upload failed"
                DispatchQueue.main.asyncAfter(deadline: .now() + 4) { [weak self] in
                    self?.composerHelpLabel.stringValue = "Help"
                }
                return
            }
            do {
                let post = try await ws.createPost(channelId: channelId, message: message, fileIds: fileIds)
                if self.activeChannelId == channelId {
                    self.currentChannelPosts.append(post)
                    self.rebuildTimelineContent(scrollToBottom: true)
                }
                self.entryView.string = ""
                self.updateComposerSendState()
                self.composerHelpLabel.stringValue = "Help"
            } catch {
                self.composerHelpLabel.stringValue = "Upload failed"
                NSLog("Failed to send attachment: \(error.localizedDescription)")
            }
        }
    }
    
    private func setupRightPanel() {
        let dividerColor = NSColor(red: 229 / 255, green: 231 / 255, blue: 235 / 255, alpha: 1.0)
        rightPanel.color = .white
        rightPanel.cornerRadius = 0
        rightPanel.borderWidth = 1
        rightPanel.borderColor = dividerColor
        rightPanel.isHidden = true
        
        rightPanelTitle.font = MMFont.font(ofSize: 14, weight: .semibold)
        rightPanelTitle.textColor = NSColor(red: 31 / 255, green: 41 / 255, blue: 55 / 255, alpha: 1.0)
        rightPanelTitle.isEditable = false
        rightPanelTitle.isSelectable = false
        rightPanel.addSubview(rightPanelTitle)
        
        rightPanelCloseButton.cornerRadius = 4
        rightPanelCloseButton.color = .clear
        let closeIcon = NSImageView()
        if let image = NSImage(systemSymbolName: "xmark", accessibilityDescription: "Close panel") {
            closeIcon.image = image.withSymbolConfiguration(.init(pointSize: 10, weight: .semibold))
            closeIcon.contentTintColor = NSColor(red: 107 / 255, green: 114 / 255, blue: 128 / 255, alpha: 1.0)
        }
        closeIcon.frame = NSRect(x: 5, y: 5, width: 12, height: 12)
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
        
        chatPanel.addSubview(rightPanel)
    }
    
    private func showRightPanel(mode: RightPanelMode) {
        rightPanelMode = mode
        isRightPanelVisible = true
        rightPanel.isHidden = false
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
        }
    }
    
    private func toggleRightPanel(mode: RightPanelMode) {
        if isRightPanelVisible && rightPanelMode == mode {
            closeRightPanel()
        } else {
            showRightPanel(mode: mode)
        }
    }
    
    private func closeRightPanel() {
        isRightPanelVisible = false
        rightPanel.isHidden = true
    }
    
    private func reloadRightPanelIfNeeded() {
        guard isRightPanelVisible else { return }
        switch rightPanelMode {
        case .threads: loadThreads()
        case .members: loadChannelMembers()
        case .pinned: loadPinnedPosts()
        case .mentions: loadMentions()
        case .saved: loadSavedPosts()
        case .settings: loadSettingsPanel()
        case .browse: loadBrowseChannels()
        }
    }
    
    private func loadThreads() {
        guard let ws = (NSApp.delegate as? AppDelegate)?.webService, ws.isLogged(),
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
            self.hydrateUsers(authorIds) {
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
                            self?.openChannel(withId: post.channel_id)
                            self?.closeRightPanel()
                        }
                    )
                }
                self.renderRightPanel(empty: "No threads yet", rows: rows)
            }
        }
    }
    
    private func loadChannelMembers() {
        guard let ws = (NSApp.delegate as? AppDelegate)?.webService, ws.isLogged(),
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
    
    private func loadPinnedPosts() {
        guard let ws = (NSApp.delegate as? AppDelegate)?.webService, ws.isLogged(),
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
            self.hydrateUsers(posts.map { $0.user_id }) {
                let formatter = DateFormatter()
                formatter.dateFormat = "MMM d, h:mm a"
                let rows = posts.map { post -> RightPanelRow in
                    let author = self.usersById[post.user_id]?.username ?? "Unknown"
                    let when = formatter.string(from: Date(timeIntervalSince1970: TimeInterval(post.create_at) / 1000))
                    return RightPanelRow(
                        title: post.message.replacingOccurrences(of: "\n", with: " "),
                        subtitle: "\(author) · \(when)",
                        meta: "",
                        action: { [weak self] in
                            self?.openChannel(withId: post.channel_id)
                            self?.closeRightPanel()
                        }
                    )
                }
                self.renderRightPanel(empty: "No pinned posts", rows: rows)
            }
        }
    }
    
    private func loadMentions() {
        guard let ws = (NSApp.delegate as? AppDelegate)?.webService, ws.isLogged(),
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
            self.hydrateUsers(posts.map { $0.user_id }) {
                let formatter = DateFormatter()
                formatter.dateFormat = "MMM d, h:mm a"
                let rows = posts.map { post -> RightPanelRow in
                    let author = self.usersById[post.user_id]?.username ?? "Unknown"
                    let channelName = self.channelsById[post.channel_id].map { self.channelDisplayName(for: $0) } ?? ""
                    let when = formatter.string(from: Date(timeIntervalSince1970: TimeInterval(post.create_at) / 1000))
                    return RightPanelRow(
                        title: post.message.replacingOccurrences(of: "\n", with: " "),
                        subtitle: [author, channelName, when].filter { !$0.isEmpty }.joined(separator: " · "),
                        meta: "",
                        action: { [weak self] in
                            self?.openChannel(withId: post.channel_id)
                            self?.closeRightPanel()
                        }
                    )
                }
                self.renderRightPanel(empty: "No recent mentions", rows: rows)
            }
        }
    }
    
    private func loadSavedPosts() {
        guard let ws = (NSApp.delegate as? AppDelegate)?.webService, ws.isLogged(),
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
            self.hydrateUsers(posts.map { $0.user_id }) {
                let formatter = DateFormatter()
                formatter.dateFormat = "MMM d, h:mm a"
                let rows = posts.map { post -> RightPanelRow in
                    let author = self.usersById[post.user_id]?.username ?? "Unknown"
                    let channelName = self.channelsById[post.channel_id].map { self.channelDisplayName(for: $0) } ?? ""
                    let when = formatter.string(from: Date(timeIntervalSince1970: TimeInterval(post.create_at) / 1000))
                    return RightPanelRow(
                        title: post.message.replacingOccurrences(of: "\n", with: " "),
                        subtitle: [author, channelName, when].filter { !$0.isEmpty }.joined(separator: " · "),
                        meta: "Saved",
                        action: { [weak self] in
                            self?.openChannel(withId: post.channel_id)
                            self?.closeRightPanel()
                        }
                    )
                }
                self.renderRightPanel(empty: "No saved posts", rows: rows)
            }
        }
    }
    
    private func loadSettingsPanel() {
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
                subtitle: "Re-establish the realtime connection",
                meta: "Connection",
                action: { [weak self] in
                    (NSApp.delegate as? AppDelegate)?.webService.reconnectIfNeeded()
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
    
    private func loadBrowseChannels() {
        guard let ws = (NSApp.delegate as? AppDelegate)?.webService, ws.isLogged(),
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
    
    private func joinChannel(_ channel: MMChannel) {
        guard let ws = (NSApp.delegate as? AppDelegate)?.webService, ws.isLogged(),
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
    
    private func showInviteDialog() {
        guard let team = activeTeam else { return }
        let alert = NSAlert()
        alert.messageText = "Invite people to \(team.display_name)"
        alert.informativeText = "Send an email invitation to join this team."
        alert.addButton(withTitle: "Send Invite")
        alert.addButton(withTitle: "Cancel")
        
        let field = NSTextField(frame: NSRect(x: 0, y: 0, width: 280, height: 24))
        field.placeholderString = "name@example.com"
        alert.accessoryView = field
        alert.beginSheetModal(for: self) { [weak self] response in
            guard let self = self, response == .alertFirstButtonReturn else { return }
            let email = field.stringValue.trimmingCharacters(in: .whitespacesAndNewlines)
            guard email.contains("@"), email.contains(".") else {
                self.showInfoAlert("Enter a valid email address.")
                return
            }
            guard let ws = (NSApp.delegate as? AppDelegate)?.webService else { return }
            Task { @MainActor in
                do {
                    try await ws.sendTeamInvite(teamId: team.id, email: email)
                    self.showInfoAlert("Invitation sent to \(email).")
                } catch {
                    self.showInfoAlert("Could not send invite: \(error.localizedDescription)")
                }
            }
        }
    }
    
    private func showCreateTeamDialog() {
        let alert = NSAlert()
        alert.messageText = "Create a team"
        alert.informativeText = "Teams group channels and members."
        alert.addButton(withTitle: "Create")
        alert.addButton(withTitle: "Cancel")
        
        let container = NSView(frame: NSRect(x: 0, y: 0, width: 280, height: 56))
        let displayField = NSTextField(frame: NSRect(x: 0, y: 30, width: 280, height: 24))
        displayField.placeholderString = "Display name (e.g. Engineering)"
        let nameField = NSTextField(frame: NSRect(x: 0, y: 0, width: 280, height: 24))
        nameField.placeholderString = "URL name (e.g. engineering)"
        container.addSubview(displayField)
        container.addSubview(nameField)
        alert.accessoryView = container
        
        alert.beginSheetModal(for: self) { [weak self] response in
            guard let self = self, response == .alertFirstButtonReturn else { return }
            var displayName = displayField.stringValue.trimmingCharacters(in: .whitespacesAndNewlines)
            var name = nameField.stringValue.trimmingCharacters(in: .whitespacesAndNewlines).lowercased()
            if displayName.isEmpty { displayName = name }
            if name.isEmpty {
                name = displayName.lowercased()
                    .replacingOccurrences(of: " ", with: "-")
                    .filter { $0.isLetter || $0.isNumber || $0 == "-" }
            }
            guard !name.isEmpty else {
                self.showInfoAlert("Enter a team name.")
                return
            }
            guard let ws = (NSApp.delegate as? AppDelegate)?.webService else { return }
            Task { @MainActor in
                do {
                    let team = try await ws.createTeam(name: name, displayName: displayName)
                    if let teams = try? await ws.fetchTeams() {
                        self.userTeams = teams
                    }
                    self.switchActiveTeam(to: team)
                } catch {
                    self.showInfoAlert("Could not create team: \(error.localizedDescription)")
                }
            }
        }
    }
    
    private func showInfoAlert(_ message: String) {
        let alert = NSAlert()
        alert.messageText = "Mattermost"
        alert.informativeText = message
        alert.addButton(withTitle: "OK")
        alert.beginSheetModal(for: self)
    }
    
    private struct RightPanelRow {
        let title: String
        let subtitle: String
        let meta: String
        let action: (() -> Void)?
    }
    
    private func hydrateUsers(_ ids: [String], completion: @escaping () -> Void) {
        let missing = Array(Set(ids).subtracting(usersById.keys))
        guard !missing.isEmpty, let ws = (NSApp.delegate as? AppDelegate)?.webService else {
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
    
    private func renderRightPanel(empty: String, rows: [RightPanelRow]) {
        let width = max(rightPanelScroll.bounds.width, rightPanel.bounds.width)
        rightPanelDoc.subviews.forEach { $0.removeFromSuperview() }
        
        var y: CGFloat = 8
        if rows.isEmpty {
            let label = NSTextField(labelWithString: empty)
            label.font = MMFont.font(ofSize: 13)
            label.textColor = NSColor(red: 107 / 255, green: 114 / 255, blue: 128 / 255, alpha: 1.0)
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
    
    private func makeRightPanelRow(_ item: RightPanelRow, width: CGFloat) -> RoundedEdgePanel {
        let row = RoundedEdgePanel()
        row.cornerRadius = 6
        row.color = .clear
        
        let title = NSTextField(labelWithString: item.title)
        title.font = MMFont.font(ofSize: 13, weight: .semibold)
        title.textColor = NSColor(red: 31 / 255, green: 41 / 255, blue: 55 / 255, alpha: 1.0)
        title.lineBreakMode = .byTruncatingTail
        title.isEditable = false
        title.isSelectable = false
        title.frame = NSRect(x: 10, y: 40, width: width - 20, height: 18)
        row.addSubview(title)
        
        if !item.subtitle.isEmpty {
            let subtitle = NSTextField(labelWithString: item.subtitle)
            subtitle.font = MMFont.font(ofSize: 12)
            subtitle.textColor = NSColor(red: 107 / 255, green: 114 / 255, blue: 128 / 255, alpha: 1.0)
            subtitle.lineBreakMode = .byTruncatingTail
            subtitle.isEditable = false
            subtitle.isSelectable = false
            subtitle.frame = NSRect(x: 10, y: 22, width: width - 20, height: 16)
            row.addSubview(subtitle)
        }
        
        if !item.meta.isEmpty {
            let meta = NSTextField(labelWithString: item.meta)
            meta.font = MMFont.font(ofSize: 11)
            meta.textColor = NSColor(red: 63 / 255, green: 67 / 255, blue: 80 / 255, alpha: 0.64)
            meta.isEditable = false
            meta.isSelectable = false
            meta.frame = NSRect(x: 10, y: 6, width: width - 20, height: 14)
            row.addSubview(meta)
        }
        
        row.onHoverChanged = { [weak row] isHovered in
            row?.color = isHovered
                ? NSColor(red: 243 / 255, green: 244 / 255, blue: 246 / 255, alpha: 1.0)
                : .clear
            row?.setNeedsAppearanceUpdate()
        }
        if let action = item.action {
            row.onClick = action
        }
        return row
    }
    
    private func applyComposerToolbarVisibility() {
        let visible = isComposerToolbarVisible
        for btn in composerLeftButtons {
            btn.isHidden = !visible
        }
        composerLeftSeparator.isHidden = !visible
        composerGifButton.isHidden = true
        let symbol = visible ? "chevron.up" : "chevron.down"
        if let img = NSImage(systemSymbolName: symbol, accessibilityDescription: "Formatting") {
            composerAaChevron.image = img.withSymbolConfiguration(.init(pointSize: 8, weight: .bold))
        }
    }
    
    private func toggleComposerToolbar() {
        isComposerToolbarVisible.toggle()
        applyComposerToolbarVisibility()
        layoutRightChatPanel()
        rebuildTimelineContent(scrollToBottom: true)
    }
    
    // MARK: - Dynamic Timeline Helpers
    
    private func layoutHeroSubviews(heroW: CGFloat) {
        let isBot = isCurrentChannelBot()
        let currentCh = activeChannelId.isEmpty ? nil : channelsById[activeChannelId]
        let isDM = (currentCh?.type == "D") || isBot
        let targetUserId = currentCh.flatMap { resolveDMTargetUserId(for: $0) }
        if let targetId = targetUserId {
            fetchAvatarIfNeeded(for: targetId)
        } else if isBot {
            fetchAvatarForUsernameIfNeeded("system-bot")
        }
        
        let heroAvatar = targetUserId.flatMap { userAvatarsById[$0] }
            ?? (isBot ? userAvatarsById["system-bot"] : nil)
        
        let heroMidX = heroW / 2
        heroIllustrationCircle.frame = NSRect(x: heroMidX - 38, y: 132, width: 76, height: 76)
        
        if isDM, let avatar = heroAvatar {
            heroIllustrationCircle.color = .clear
            heroWhiteBubble.isHidden = true
            heroBlueBubble.isHidden = true
            heroBotAvatarView.isHidden = false
            heroBotAvatarView.image = avatar
            heroBotAvatarView.frame = NSRect(x: 0, y: 0, width: 76, height: 76)
        } else {
            heroIllustrationCircle.color = NSColor(red: 243 / 255, green: 244 / 255, blue: 246 / 255, alpha: 1.0)
            heroWhiteBubble.isHidden = false
            heroBlueBubble.isHidden = false
            heroBotAvatarView.isHidden = true
            heroWhiteBubble.frame = NSRect(x: heroMidX - 32, y: 156, width: 52, height: 36)
            heroBlueBubble.frame = NSRect(x: heroMidX - 2, y: 140, width: 40, height: 26)
        }
        
        let titleFont = MMFont.font(ofSize: 22, weight: .bold)
        heroTitleLabel.font = titleFont
        let titleStr = heroTitleLabel.stringValue
        let titleSize = (titleStr as NSString).size(withAttributes: [.font: titleFont])
        let titleTextW = ceil(titleSize.width) + 4
        let titleTextH = ceil(titleSize.height)
        
        if isBot {
            heroBotBadge.isHidden = false
            let badgeW: CGFloat = 34
            let badgeH: CGFloat = 18
            let totalTitleW = titleTextW + 8 + badgeW
            let titleStartX = (heroW - totalTitleW) / 2
            heroTitleLabel.frame = NSRect(x: titleStartX, y: 92, width: titleTextW, height: titleTextH)
            heroTitleLabel.alignment = .left
            heroBotBadge.frame = NSRect(x: titleStartX + titleTextW + 8, y: 92 + (titleTextH - badgeH) / 2, width: badgeW, height: badgeH)
            heroBotBadgeLabel.frame = NSRect(x: 0, y: 1, width: badgeW, height: 16)
        } else {
            heroBotBadge.isHidden = true
            heroTitleLabel.frame = NSRect(x: 0, y: 92, width: heroW, height: 28)
            heroTitleLabel.alignment = .center
        }
        
        let descW = min(heroW - 32, 440)
        heroDescriptionLabel.frame = NSRect(x: (heroW - descW) / 2, y: 46, width: descW, height: 38)
        
        heroInviteButton.isHidden = isDM
        if !isDM {
            let inviteText = heroInviteLabel.stringValue.isEmpty ? "Invite others to the workspace" : heroInviteLabel.stringValue
            let inviteFont = heroInviteLabel.font ?? MMFont.font(ofSize: 12, weight: .semibold)
            let inviteSize = (inviteText as NSString).size(withAttributes: [.font: inviteFont])
            let inviteTextW = ceil(inviteSize.width) + 4
            let inviteTextH = ceil(inviteSize.height)
            let invitePadH: CGFloat = 12
            let inviteIconSize: CGFloat = 16
            let inviteSpacing: CGFloat = 8
            let inviteBtnW = invitePadH + inviteIconSize + inviteSpacing + inviteTextW + invitePadH
            let inviteBtnH: CGFloat = max(32, inviteTextH + 12)
            heroInviteButton.frame = NSRect(x: heroMidX - inviteBtnW / 2, y: 6, width: inviteBtnW, height: inviteBtnH)
            heroInviteIconView.frame = NSRect(x: invitePadH, y: (inviteBtnH - inviteIconSize) / 2, width: inviteIconSize, height: inviteIconSize)
            heroInviteLabel.frame = NSRect(x: invitePadH + inviteIconSize + inviteSpacing, y: (inviteBtnH - inviteTextH) / 2, width: inviteTextW, height: inviteTextH)
        }
    }
    
    private func createDateSeparator(dateStr: String, width: CGFloat) -> NSView {
        let container = TimelineFlippedView()
        let dividerColor = NSColor(red: 63 / 255, green: 67 / 255, blue: 80 / 255, alpha: 0.16)
        let separatorText = NSColor(red: 63 / 255, green: 67 / 255, blue: 80 / 255, alpha: 1.0)

        // Web: 1pt rule behind a white 26pt pill, 13pt bold label, 13pt horizontal padding.
        let font = MMFont.font(ofSize: 13, weight: .bold)
        let textSize = (dateStr as NSString).size(withAttributes: [.font: font])
        let textW = ceil(textSize.width)
        let textH = ceil(textSize.height)
        let pillH: CGFloat = 26
        let pillW = textW + 26
        let centerX = width / 2
        let pillX = centerX - pillW / 2

        let line = RoundedEdgePanel()
        line.cornerRadius = 0
        line.color = dividerColor
        line.frame = NSRect(x: 20, y: 16, width: max(0, width - 40), height: 1)

        let pill = RoundedEdgePanel()
        pill.color = .white
        pill.cornerRadius = pillH / 2
        pill.frame = NSRect(x: pillX, y: 4, width: pillW, height: pillH)

        let label = NSTextField(labelWithString: dateStr)
        label.font = font
        label.textColor = separatorText
        label.alignment = .center
        label.isEditable = false
        label.isSelectable = false
        label.frame = NSRect(x: 0, y: (pillH - textH) / 2, width: pillW, height: textH)
        pill.addSubview(label)

        container.addSubview(line)
        container.addSubview(pill)
        container.frame = NSRect(x: 0, y: 0, width: width, height: 34)
        return container
    }
    
    private func createFallbackAnimatedGif() -> NSImage? {
        let size = CGSize(width: 140, height: 100)
        let rep1 = NSBitmapImageRep(bitmapDataPlanes: nil, pixelsWide: 140, pixelsHigh: 100, bitsPerSample: 8, samplesPerPixel: 4, hasAlpha: true, isPlanar: false, colorSpaceName: .calibratedRGB, bytesPerRow: 0, bitsPerPixel: 0)
        if let rep1 = rep1 {
            NSGraphicsContext.saveGraphicsState()
            NSGraphicsContext.current = NSGraphicsContext(bitmapImageRep: rep1)
            NSColor(red: 0.1, green: 0.5, blue: 0.9, alpha: 1.0).setFill()
            NSBezierPath(roundedRect: NSRect(origin: .zero, size: size), xRadius: 10, yRadius: 10).fill()
            let str = NSAttributedString(string: "GIPHY", attributes: [.font: MMFont.bold(20), .foregroundColor: NSColor.white])
            str.draw(at: NSPoint(x: (140 - str.size().width) / 2, y: (100 - str.size().height) / 2))
            NSGraphicsContext.restoreGraphicsState()
        }

        let rep2 = NSBitmapImageRep(bitmapDataPlanes: nil, pixelsWide: 140, pixelsHigh: 100, bitsPerSample: 8, samplesPerPixel: 4, hasAlpha: true, isPlanar: false, colorSpaceName: .calibratedRGB, bytesPerRow: 0, bitsPerPixel: 0)
        if let rep2 = rep2 {
            NSGraphicsContext.saveGraphicsState()
            NSGraphicsContext.current = NSGraphicsContext(bitmapImageRep: rep2)
            NSColor(red: 0.9, green: 0.2, blue: 0.5, alpha: 1.0).setFill()
            NSBezierPath(roundedRect: NSRect(origin: .zero, size: size), xRadius: 10, yRadius: 10).fill()
            let str2 = NSAttributedString(string: "GIPHY", attributes: [.font: MMFont.bold(22), .foregroundColor: NSColor.white])
            str2.draw(at: NSPoint(x: (140 - str2.size().width) / 2, y: (100 - str2.size().height) / 2))
            NSGraphicsContext.restoreGraphicsState()
        }

        guard let cg1 = rep1?.cgImage, let cg2 = rep2?.cgImage else { return nil }
        let data = NSMutableData()
        guard let dest = CGImageDestinationCreateWithData(data as CFMutableData, UTType.gif.identifier as CFString, 2, nil) else { return nil }
        let gifProps = [kCGImagePropertyGIFDictionary as String: [kCGImagePropertyGIFLoopCount as String: 0]]
        CGImageDestinationSetProperties(dest, gifProps as CFDictionary)
        let frameProps = [kCGImagePropertyGIFDictionary as String: [kCGImagePropertyGIFDelayTime as String: 0.4]]
        CGImageDestinationAddImage(dest, cg1, frameProps as CFDictionary)
        CGImageDestinationAddImage(dest, cg2, frameProps as CFDictionary)
        guard CGImageDestinationFinalize(dest) else { return nil }
        return NSImage(data: data as Data)
    }

    private struct ParsedGiphyMessage {
        let text: String
        let gifURLs: [String]
    }

    private func parseGiphyInMessage(_ message: String) -> ParsedGiphyMessage {
        var text = message
        var gifURLs: [String] = []

        func isGiphyOrGifURL(_ urlStr: String) -> Bool {
            guard let url = URL(string: urlStr) else { return false }
            let host = (url.host ?? "").lowercased()
            let path = url.path.lowercased()
            if host.contains("giphy.com") || host.contains("gph.is") { return true }
            if path.hasSuffix(".gif") || path.hasSuffix(".webp") { return true }
            return false
        }

        // 1. Match Markdown images: ![alt](url)
        let mdPattern = #"(!\[(.*?)\]\((https?://[^\s\)]+)\))"#
        if let mdRegex = try? NSRegularExpression(pattern: mdPattern, options: []) {
            let nsText = text as NSString
            let matches = mdRegex.matches(in: text, options: [], range: NSRange(location: 0, length: nsText.length))
            for match in matches.reversed() {
                let url = nsText.substring(with: match.range(at: 3))
                if isGiphyOrGifURL(url) {
                    gifURLs.insert(url, at: 0)
                    text = (text as NSString).replacingCharacters(in: match.range(at: 1), with: "")
                }
            }
        }

        // 2. Match standalone URLs: https://...
        let urlPattern = #"(https?://[^\s]+)"#
        if let urlRegex = try? NSRegularExpression(pattern: urlPattern, options: []) {
            let nsText = text as NSString
            let matches = urlRegex.matches(in: text, options: [], range: NSRange(location: 0, length: nsText.length))
            for match in matches.reversed() {
                let url = nsText.substring(with: match.range(at: 1))
                if isGiphyOrGifURL(url) && !gifURLs.contains(url) {
                    gifURLs.insert(url, at: 0)
                    text = (text as NSString).replacingCharacters(in: match.range(at: 1), with: "")
                }
            }
        }

        let trimmed = text.trimmingCharacters(in: .whitespacesAndNewlines)
        return ParsedGiphyMessage(text: trimmed, gifURLs: gifURLs)
    }

    private func createGiphyView(urlString: String, maxWidth: CGFloat) -> (NSView, CGFloat) {
        let container = RoundedEdgePanel()
        let viewH: CGFloat = 160
        var viewW = min(maxWidth, 240)

        let cacheDir = FileManager.default.urls(for: .cachesDirectory, in: .userDomainMask).first?.appendingPathComponent("mattermost.client/giphy", isDirectory: true)
        if let dir = cacheDir {
            let sampleFile = dir.appendingPathComponent("sample_giphy.gif")
            let safeName = urlString.addingPercentEncoding(withAllowedCharacters: .alphanumerics) ?? "\(urlString.hashValue)"
            let filename = (safeName.count > 60 ? "\(urlString.hashValue)" : safeName) + ".gif"
            let diskURL = dir.appendingPathComponent(filename)
            let checkURL = (urlString.contains("ICOgUNjpvO0PC") && FileManager.default.fileExists(atPath: sampleFile.path)) ? sampleFile : diskURL
            if let data = try? Data(contentsOf: checkURL), let cachedImg = NSImage(data: data) {
                if cachedImg.size.height > 0 {
                    let aspect = cachedImg.size.width / cachedImg.size.height
                    viewW = min(maxWidth, max(40, viewH * aspect))
                }
            }
        }

        container.frame = NSRect(x: 0, y: 0, width: viewW, height: viewH)
        container.cornerRadius = 8
        container.borderWidth = 0
        container.borderColor = nil
        container.color = .clear

        let imageView = NSImageView(frame: NSRect(x: 0, y: 0, width: viewW, height: viewH))
        imageView.animates = true
        imageView.imageScaling = .scaleProportionallyUpOrDown
        imageView.imageAlignment = .alignLeft
        imageView.wantsLayer = true
        imageView.layer?.cornerRadius = 8
        imageView.layer?.masksToBounds = true
        container.addSubview(imageView)

        loadGiphyAnimatedImage(from: urlString) { [weak container, weak imageView] image in
            guard let image = image else { return }
            imageView?.image = image
            if image.size.height > 0 {
                let aspect = image.size.width / image.size.height
                let actualW = min(maxWidth, max(40, viewH * aspect))
                container?.frame.size.width = actualW
                imageView?.frame.size.width = actualW
            }
        }

        return (container, viewH)
    }

    private func loadGiphyAnimatedImage(from urlString: String, completion: @escaping (NSImage?) -> Void) {
        let cacheDir = FileManager.default.urls(for: .cachesDirectory, in: .userDomainMask).first?.appendingPathComponent("mattermost.client/giphy", isDirectory: true)
        if let dir = cacheDir {
            try? FileManager.default.createDirectory(at: dir, withIntermediateDirectories: true)
            let sampleFile = dir.appendingPathComponent("sample_giphy.gif")
            if urlString.contains("ICOgUNjpvO0PC"), let data = try? Data(contentsOf: sampleFile), let img = NSImage(data: data) {
                completion(img)
                return
            }
            let safeName = urlString.addingPercentEncoding(withAllowedCharacters: .alphanumerics) ?? "\(urlString.hashValue)"
            let filename = (safeName.count > 60 ? "\(urlString.hashValue)" : safeName) + ".gif"
            let diskURL = dir.appendingPathComponent(filename)
            if let data = try? Data(contentsOf: diskURL), let img = NSImage(data: data) {
                completion(img)
                return
            }
        }

        guard let url = URL(string: urlString) else {
            completion(createFallbackAnimatedGif())
            return
        }

        var request = URLRequest(url: url, cachePolicy: .returnCacheDataElseLoad, timeoutInterval: 15)
        request.setValue("Mozilla/5.0 (Macintosh; Intel Mac OS X 10_15_7) AppleWebKit/537.36", forHTTPHeaderField: "User-Agent")

        URLSession.shared.dataTask(with: request) { [weak self] data, _, _ in
            var resultImage: NSImage? = nil
            if let data = data, let image = NSImage(data: data) {
                resultImage = image
                if let dir = cacheDir {
                    let safeName = urlString.addingPercentEncoding(withAllowedCharacters: .alphanumerics) ?? "\(urlString.hashValue)"
                    let filename = (safeName.count > 60 ? "\(urlString.hashValue)" : safeName) + ".gif"
                    let diskURL = dir.appendingPathComponent(filename)
                    try? data.write(to: diskURL)
                }
            } else {
                resultImage = self?.createFallbackAnimatedGif()
            }
            DispatchQueue.main.async {
                completion(resultImage)
            }
        }.resume()
    }

    private func appendEditedIndicator(to attributedString: NSMutableAttributedString, font: NSFont, editDate: Date?) {
        let editFont = MMFont.font(ofSize: max(10, font.pointSize - 2))
        let editColor = NSColor(red: 156 / 255, green: 163 / 255, blue: 175 / 255, alpha: 1.0)
        
        let space = NSAttributedString(string: "  ", attributes: [
            .font: editFont,
            .foregroundColor: editColor
        ])
        attributedString.append(space)
        
        let att = NSTextAttachment()
        if let img = NSImage(systemSymbolName: "pencil", accessibilityDescription: "Edited") {
            let cfg = NSImage.SymbolConfiguration(pointSize: editFont.pointSize - 1, weight: .regular).applying(.init(hierarchicalColor: editColor))
            att.image = img.withSymbolConfiguration(cfg)
        }
        att.bounds = NSRect(x: 0, y: -1, width: editFont.pointSize, height: editFont.pointSize)
        
        var tooltipAttrs: [NSAttributedString.Key: Any] = [
            .font: editFont,
            .foregroundColor: editColor
        ]
        if let date = editDate {
            let editTimeFmt = DateFormatter()
            editTimeFmt.dateFormat = "h:mm a"
            tooltipAttrs[.toolTip] = "Edited at \(editTimeFmt.string(from: date))"
        } else {
            tooltipAttrs[.toolTip] = "Edited"
        }
        
        attributedString.append(NSAttributedString(attachment: att))
        attributedString.append(NSAttributedString(string: " Edited", attributes: tooltipAttrs))
    }

    private func createPostRow(post: MMPost, width: CGFloat, timeStr: String, isConsecutive: Bool = false) -> (NSView, CGFloat) {
        let row = TimelineRowView()
        row.cornerRadius = 0
        row.color = .clear
        
        let darkText = NSColor(red: 31 / 255, green: 41 / 255, blue: 55 / 255, alpha: 1.0)
        let mutedText = NSColor(red: 107 / 255, green: 114 / 255, blue: 128 / 255, alpha: 1.0)
        let lightPlaceholder = NSColor(red: 156 / 255, green: 163 / 255, blue: 175 / 255, alpha: 1.0)
        let hoverBg = NSColor(red: 243 / 255, green: 244 / 255, blue: 246 / 255, alpha: 1.0)
        let msgHoverBg = NSColor(red: 249 / 255, green: 250 / 255, blue: 251 / 255, alpha: 1.0)
        let dividerColor = NSColor(red: 229 / 255, green: 231 / 255, blue: 235 / 255, alpha: 1.0)

        let isSystem = (post.type?.hasPrefix("system_") ?? false) || (usersById[post.user_id]?.username == "System")

        // Parse message for text & Giphy GIF URLs
        let rawMessage = post.message.isEmpty ? (isSystem ? "System update" : "") : post.message
        let parsed = parseGiphyInMessage(rawMessage)
        let bodyText = parsed.text
        let gifURLs = parsed.gifURLs
        let hasBodyText = !bodyText.isEmpty
        let isEdited = (post.edit_at != nil && post.edit_at! > 0)
        let editDate = isEdited ? Date(timeIntervalSince1970: TimeInterval(post.edit_at!) / 1000.0) : nil

        let bodyFont = MMFont.font(ofSize: 14)
        let bodyMaxW = max(100, width - 79 - 8)
        
        let formattedBody: NSAttributedString
        if hasBodyText {
            let bodyColor = NSColor(red: 63 / 255, green: 67 / 255, blue: 80 / 255, alpha: 0.75)
            let mutable = NSMutableAttributedString(attributedString: formattedMessage(bodyText, font: bodyFont, color: bodyColor))
            if isEdited {
                appendEditedIndicator(to: mutable, font: bodyFont, editDate: editDate)
            }
            formattedBody = mutable
        } else if isEdited {
            let mutable = NSMutableAttributedString()
            appendEditedIndicator(to: mutable, font: bodyFont, editDate: editDate)
            formattedBody = mutable
        } else {
            formattedBody = NSAttributedString()
        }

        let hasDisplayableText = (hasBodyText || isEdited)
        let bodyH: CGFloat
        if hasDisplayableText {
            let textStorage = NSTextStorage(attributedString: formattedBody)
            let textContainer = NSTextContainer(containerSize: NSSize(width: bodyMaxW, height: CGFloat.greatestFiniteMagnitude))
            textContainer.lineFragmentPadding = 0
            let layoutManager = NSLayoutManager()
            layoutManager.addTextContainer(textContainer)
            textStorage.addLayoutManager(layoutManager)
            layoutManager.glyphRange(for: textContainer)
            let usedRect = layoutManager.usedRect(for: textContainer)
            bodyH = max(18, ceil(usedRect.height))
        } else {
            bodyH = 0
        }

        if isConsecutive {
            let hoverTimeLabel = NSTextField(labelWithString: timeStr)
            let hoverTimeFont = MMFont.font(ofSize: 12.6)
            hoverTimeLabel.font = hoverTimeFont
            hoverTimeLabel.textColor = lightPlaceholder
            hoverTimeLabel.isEditable = false
            hoverTimeLabel.isSelectable = false
            hoverTimeLabel.alignment = .right
            hoverTimeLabel.frame = NSRect(x: 4, y: 3, width: 48, height: 14)
            hoverTimeLabel.isHidden = true
            row.addSubview(hoverTimeLabel)

            var contentY: CGFloat = 2
            if hasDisplayableText {
                let bodyView = NSTextView(frame: NSRect(x: 79, y: contentY, width: bodyMaxW, height: bodyH))
                bodyView.isEditable = false
                bodyView.isSelectable = true
                bodyView.drawsBackground = false
                bodyView.textContainerInset = .zero
                bodyView.textContainer?.lineFragmentPadding = 0
                bodyView.textContainer?.widthTracksTextView = true
                bodyView.isHorizontallyResizable = false
                bodyView.isVerticallyResizable = false
                bodyView.delegate = self
                bodyView.linkTextAttributes = [
                    .foregroundColor: NSColor(red: 28 / 255, green: 88 / 255, blue: 217 / 255, alpha: 1.0),
                    .underlineStyle: NSUnderlineStyle.single.rawValue,
                    .cursor: NSCursor.pointingHand
                ]
                bodyView.textStorage?.setAttributedString(formattedBody)
                row.addSubview(bodyView)
                contentY += bodyH + 6
            }

            for gifURL in gifURLs {
                let (giphyView, gifH) = createGiphyView(urlString: gifURL, maxWidth: bodyMaxW)
                giphyView.frame.origin = CGPoint(x: 79, y: contentY)
                row.addSubview(giphyView)
                contentY += gifH + 6
            }

            let totalRowH = max(24, contentY)
            row.frame = NSRect(x: 0, y: 0, width: width, height: totalRowH)

            row.onHoverChanged = { [weak row, weak hoverTimeLabel] isHovered in
                row?.color = isHovered ? msgHoverBg : .clear
                row?.setNeedsAppearanceUpdate()
                hoverTimeLabel?.isHidden = !isHovered
            }
            return (row, totalRowH)
        }

        let authorName: String
        if isSystem {
            authorName = "System"
        } else if let user = usersById[post.user_id], !user.username.isEmpty {
            authorName = user.username
        } else if post.user_id == currentUser?.id {
            authorName = currentUser?.username ?? UserDefaults.standard.string(forKey: "username") ?? "User"
        } else {
            authorName = "User"
        }

        let userObj = usersById[post.user_id]
        let isBotUser = (authorName.lowercased() == "system-bot" ||
                         authorName.lowercased().contains("bot") ||
                         (userObj?.roles?.lowercased().contains("bot") ?? false) ||
                         (userObj?.is_bot ?? false))

        // Post header/body metrics mirror the web client:
        // 16pt top padding, 32pt avatar at 37pt, text column at 79pt, 14pt bottom padding.
        let topPad: CGFloat = 16
        let bottomPad: CGFloat = 14
        let headerH: CGFloat = 20
        let avatarSize: CGFloat = 32
        let contentX: CGFloat = 79

        // GIF attachments are created first so the row height is known before layout.
        var gifViews: [(NSView, CGFloat)] = []
        for gifURL in gifURLs {
            let (giphyView, gifH) = createGiphyView(urlString: gifURL, maxWidth: bodyMaxW)
            gifViews.append((giphyView, gifH))
        }

        var stackHeight: CGFloat = 0
        if hasDisplayableText { stackHeight += bodyH + 3 }
        for (_, gifH) in gifViews { stackHeight += gifH + 6 }

        let totalRowH = topPad + headerH + stackHeight + bottomPad
        row.frame = NSRect(x: 0, y: 0, width: width, height: totalRowH)
        // Rows use a flipped (top-down) coordinate system.
        let headerTopY = topPad

        // Avatar circle
        let avatarCircle = RoundedEdgePanel()
        avatarCircle.cornerRadius = avatarSize / 2
        avatarCircle.frame = NSRect(x: 37, y: topPad, width: avatarSize, height: avatarSize)

        let cachedAvatar = userAvatarsById[post.user_id] ?? (isBotUser ? userAvatarsById["system-bot"] : nil)
        if !post.user_id.isEmpty {
            fetchAvatarIfNeeded(for: post.user_id)
        } else if isBotUser {
            fetchAvatarForUsernameIfNeeded("system-bot")
        }

        if let userAvatar = cachedAvatar {
            avatarCircle.color = .clear
            let avatarImgView = NSImageView()
            avatarImgView.image = userAvatar
            avatarImgView.imageScaling = .scaleProportionallyUpOrDown
            avatarImgView.frame = NSRect(x: 0, y: 0, width: avatarSize, height: avatarSize)
            avatarCircle.addSubview(avatarImgView)
        } else if isSystem {
            avatarCircle.color = .white
            let sysAvatarIcon = NSImageView()
            if let compass = makeMattermostCompassIcon() {
                sysAvatarIcon.image = compass
                sysAvatarIcon.contentTintColor = darkText
            }
            sysAvatarIcon.frame = NSRect(x: 3, y: 3, width: avatarSize - 6, height: avatarSize - 6)
            avatarCircle.addSubview(sysAvatarIcon)
        } else {
            let palette: [NSColor] = [
                NSColor(red: 224 / 255, green: 208 / 255, blue: 71 / 255, alpha: 1.0),
                NSColor(red: 28 / 255, green: 88 / 255, blue: 217 / 255, alpha: 1.0),
                NSColor(red: 139 / 255, green: 92 / 255, blue: 246 / 255, alpha: 1.0),
                NSColor(red: 236 / 255, green: 72 / 255, blue: 153 / 255, alpha: 1.0),
                NSColor(red: 16 / 255, green: 185 / 255, blue: 129 / 255, alpha: 1.0),
                NSColor(red: 245 / 255, green: 158 / 255, blue: 11 / 255, alpha: 1.0)
            ]
            let hashVal = abs(authorName.hashValue)
            avatarCircle.color = palette[hashVal % palette.count]

            let initial = authorName.first.map { String($0).uppercased() } ?? "U"
            let initialLabel = NSTextField(labelWithString: initial)
            initialLabel.font = MMFont.font(ofSize: 14, weight: .semibold)
            initialLabel.textColor = .white
            initialLabel.alignment = .center
            initialLabel.isEditable = false
            initialLabel.isSelectable = false
            initialLabel.frame = NSRect(x: 0, y: (avatarSize - 20) / 2, width: avatarSize, height: 20)
            avatarCircle.addSubview(initialLabel)
        }
        row.addSubview(avatarCircle)

        let isCurrentUser = (post.user_id == currentUser?.id) || (!authorName.isEmpty && authorName == currentUser?.username) || (post.user_id == "usr" || post.user_id == "sample_usr")

        // Author label
        let authorLabel = NSTextField(labelWithString: authorName)
        let authorFont = MMFont.font(ofSize: 14, weight: .semibold)
        authorLabel.font = authorFont
        authorLabel.textColor = darkText
        authorLabel.isEditable = false
        authorLabel.isSelectable = false
        let authorSize = (authorName as NSString).size(withAttributes: [.font: authorFont])
        let authorW = ceil(authorSize.width) + 4
        let authorH = max(20, ceil(authorSize.height))
        authorLabel.frame = NSRect(x: contentX, y: headerTopY + (headerH - authorH) / 2, width: authorW, height: authorH)
        row.addSubview(authorLabel)

        var headerRightX = contentX + authorW + 8
        if isBotUser {
            let botBadge = createBotBadge()
            botBadge.frame = NSRect(x: contentX + authorW + 4, y: headerTopY + (headerH - 16) / 2, width: 32, height: 16)
            row.addSubview(botBadge)
            headerRightX = botBadge.frame.maxX + 8
        }

        // Status prompt pill if current user
        if isCurrentUser && !isSystem {
            let statusPromptPill = RoundedEdgePanel()
            statusPromptPill.cornerRadius = 4
            statusPromptPill.color = hoverBg
            let statusPromptIcon = NSImageView()
            if let smileImg = NSImage(systemSymbolName: "face.smiling", accessibilityDescription: "Status") {
                statusPromptIcon.image = smileImg.withSymbolConfiguration(.init(pointSize: 10, weight: .regular))
                statusPromptIcon.contentTintColor = mutedText
            }
            let statusPromptLabel = NSTextField(labelWithString: "Update your status")
            statusPromptLabel.font = MMFont.font(ofSize: 10, weight: .medium)
            statusPromptLabel.textColor = mutedText
            statusPromptLabel.isEditable = false
            statusPromptLabel.isSelectable = false
            let promptSize = ("Update your status" as NSString).size(withAttributes: [.font: statusPromptLabel.font!])
            let promptTextW = ceil(promptSize.width) + 4
            let promptTextH = ceil(promptSize.height)
            let pillPadH: CGFloat = 6
            let iconSize: CGFloat = 12
            let iconSpacing: CGFloat = 4
            let pillW = pillPadH + iconSize + iconSpacing + promptTextW + pillPadH
            let pillH = max(18, promptTextH + 4)
            statusPromptPill.frame = NSRect(x: headerRightX, y: headerTopY + (headerH - pillH) / 2, width: pillW, height: pillH)
            statusPromptIcon.frame = NSRect(x: pillPadH, y: (pillH - iconSize) / 2, width: iconSize, height: iconSize)
            statusPromptLabel.frame = NSRect(x: pillPadH + iconSize + iconSpacing, y: (pillH - promptTextH) / 2, width: promptTextW, height: promptTextH)
            statusPromptPill.addSubview(statusPromptIcon)
            statusPromptPill.addSubview(statusPromptLabel)
            statusPromptPill.onHoverChanged = { [weak statusPromptPill] isHovered in
                statusPromptPill?.color = isHovered ? dividerColor : hoverBg
                statusPromptPill?.setNeedsAppearanceUpdate()
            }
            statusPromptPill.onClick = { [weak self] in
                self?.setStatusMenuOpen(true)
            }
            row.addSubview(statusPromptPill)
            headerRightX = statusPromptPill.frame.maxX + 8
        }

        // Timestamp label
        let timeLabel = NSTextField(labelWithString: timeStr)
        let timeFont = MMFont.font(ofSize: 12.6)
        timeLabel.font = timeFont
        timeLabel.textColor = NSColor(red: 63 / 255, green: 67 / 255, blue: 80 / 255, alpha: 0.75)
        timeLabel.isEditable = false
        timeLabel.isSelectable = false
        let timeSize = (timeStr as NSString).size(withAttributes: [.font: timeFont])
        let timeW = ceil(timeSize.width) + 4
        let timeH = max(17, ceil(timeSize.height))
        timeLabel.frame = NSRect(x: headerRightX, y: headerTopY + (headerH - timeH) / 2, width: timeW, height: timeH)
        row.addSubview(timeLabel)

        // Body + GIFs stacked below the header.
        var stackTop = headerTopY + headerH
        if hasDisplayableText {
            let bodyView = NSTextView(frame: NSRect(x: contentX, y: stackTop, width: bodyMaxW, height: bodyH))
            bodyView.isEditable = false
            bodyView.isSelectable = true
            bodyView.drawsBackground = false
            bodyView.textContainerInset = .zero
            bodyView.textContainer?.lineFragmentPadding = 0
            bodyView.textContainer?.widthTracksTextView = true
            bodyView.isHorizontallyResizable = false
            bodyView.isVerticallyResizable = false
            bodyView.delegate = self
            bodyView.linkTextAttributes = [
                .foregroundColor: NSColor(red: 56 / 255, green: 111 / 255, blue: 229 / 255, alpha: 1.0),
                .underlineStyle: NSUnderlineStyle.single.rawValue,
                .cursor: NSCursor.pointingHand
            ]
            bodyView.textStorage?.setAttributedString(formattedBody)
            row.addSubview(bodyView)
            stackTop += bodyH + 3
        }

        for (giphyView, gifH) in gifViews {
            giphyView.frame.origin = CGPoint(x: contentX, y: stackTop)
            row.addSubview(giphyView)
            stackTop += gifH + 6
        }

        if !isSystem && !isBotUser {
            let usrDot = RoundedEdgePanel()
            if isCurrentUser {
                usrDot.identifier = NSUserInterfaceItemIdentifier("statusDot_currentUser")
            } else {
                usrDot.identifier = NSUserInterfaceItemIdentifier("statusDot_\(post.user_id)")
            }
            let dotSize: CGFloat = 12
            let stat = isCurrentUser ? currentUserStatus : (userStatusById[post.user_id] ?? "online")
            usrDot.frame = NSRect(x: 57, y: topPad + avatarSize - dotSize, width: dotSize, height: dotSize)
            usrDot.cornerRadius = dotSize / 2
            usrDot.color = statusColor(for: stat)
            usrDot.borderWidth = 1.5
            usrDot.borderColor = .white
            row.addSubview(usrDot)
            updateStatusCheck(in: usrDot, status: stat)
        }

        row.onHoverChanged = { [weak row] isHovered in
            row?.color = isHovered ? msgHoverBg : .clear
            row?.setNeedsAppearanceUpdate()
        }
        return (row, totalRowH)
    }

    func textView(_ textView: NSTextView, clickedOnLink link: Any, at charIndex: Int) -> Bool {
        let rawURL: URL?
        if let url = link as? URL {
            rawURL = url
        } else if let str = link as? String {
            rawURL = URL(string: str)
        } else {
            rawURL = nil
        }

        guard let url = rawURL else { return false }
        let finalURL: URL
        if url.scheme == nil || url.scheme?.isEmpty == true {
            finalURL = URL(string: "https://" + url.absoluteString) ?? url
        } else {
            finalURL = url
        }
        NSWorkspace.shared.open(finalURL)
        return true
    }

    private func preprocessMarkdownLine(_ line: String) -> String {
        var trimmed = line
        var indent = ""
        while let first = trimmed.first, first == " " || first == "\t" {
            indent.append(first)
            trimmed.removeFirst()
        }

        // Blockquote: starts with >
        if trimmed.hasPrefix(">") {
            var count = 0
            var rem = trimmed
            while rem.hasPrefix(">") {
                count += 1
                rem.removeFirst()
                while rem.hasPrefix(" ") {
                    rem.removeFirst()
                }
            }
            let padding = String(repeating: "|  ", count: count)
            if rem.hasPrefix("- ") || rem == "-" {
                let bulletRem = rem == "-" ? "" : rem.dropFirst(2)
                return indent + padding + "•  " + bulletRem
            }
            if rem.hasPrefix("* ") || rem == "*" {
                let bulletRem = rem == "*" ? "" : rem.dropFirst(2)
                return indent + padding + "•  " + bulletRem
            }
            return indent + padding + rem
        }

        // Bullet list: starts with "- " or "* " (or just "-" or "*")
        if trimmed.hasPrefix("- ") || trimmed == "-" {
            let rem = trimmed == "-" ? "" : trimmed.dropFirst(2)
            return indent + "•  " + rem
        }
        if trimmed.hasPrefix("* ") || trimmed == "*" {
            let rem = trimmed == "*" ? "" : trimmed.dropFirst(2)
            return indent + "•  " + rem
        }

        return line
    }

    private func preprocessMarkdown(_ message: String) -> String {
        let lines = message.components(separatedBy: "\n")
        return lines.map { preprocessMarkdownLine($0) }.joined(separator: "\n")
    }

    private func formattedMessage(_ message: String, font: NSFont, color: NSColor) -> NSAttributedString {
        let processedMessage = preprocessMarkdown(message)
        var options = AttributedString.MarkdownParsingOptions()
        options.interpretedSyntax = .inlineOnlyPreservingWhitespace

        let paragraphStyle = NSMutableParagraphStyle()
        paragraphStyle.lineBreakMode = .byWordWrapping

        guard let attr = try? AttributedString(markdown: processedMessage, options: options) else {
            return NSAttributedString(string: processedMessage, attributes: [
                .font: font,
                .foregroundColor: color,
                .paragraphStyle: paragraphStyle
            ])
        }

        let brandBlue = NSColor(red: 28 / 255, green: 88 / 255, blue: 217 / 255, alpha: 1.0)
        let result = NSMutableAttributedString()
        for run in attr.runs {
            let text = String(attr[run.range].characters)
            let intent = run.inlinePresentationIntent ?? []

            let isCode = intent.contains(.code)
            let isBold = intent.contains(.stronglyEmphasized)
            let isItalic = intent.contains(.emphasized)

            let runFont = resolveFont(from: font, isBold: isBold, isItalic: isItalic, isCode: isCode)
            var attrs: [NSAttributedString.Key: Any] = [
                .font: runFont,
                .foregroundColor: (run.link != nil) ? brandBlue : color,
                .paragraphStyle: paragraphStyle
            ]

            if intent.contains(.strikethrough) {
                attrs[.strikethroughStyle] = NSUnderlineStyle.single.rawValue
            }

            if let link = run.link {
                attrs[.link] = link
                attrs[.underlineStyle] = NSUnderlineStyle.single.rawValue
            }

            result.append(NSAttributedString(string: text, attributes: attrs))
        }

        return result
    }

    private func resolveFont(from base: NSFont, isBold: Bool, isItalic: Bool, isCode: Bool) -> NSFont {
        var baseFont = base
        if isCode {
            baseFont = NSFont.monospacedSystemFont(ofSize: base.pointSize, weight: .regular)
        }

        var traits: NSFontDescriptor.SymbolicTraits = []
        if isBold { traits.insert(.bold) }
        if isItalic { traits.insert(.italic) }

        if traits.isEmpty {
            return baseFont
        }

        let desc = baseFont.fontDescriptor.withSymbolicTraits(traits)
        if let customFont = NSFont(descriptor: desc, size: base.pointSize) {
            return customFont
        }

        var converted = baseFont
        if isBold {
            converted = NSFontManager.shared.convert(converted, toHaveTrait: .boldFontMask)
        }
        if isItalic {
            converted = NSFontManager.shared.convert(converted, toHaveTrait: .italicFontMask)
        }
        return converted
    }
    
    private func createBotBadge() -> RoundedEdgePanel {
        let badge = RoundedEdgePanel()
        badge.cornerRadius = 4
        badge.color = NSColor(red: 63 / 255, green: 67 / 255, blue: 80 / 255, alpha: 0.12)
        let label = NSTextField(labelWithString: "BOT")
        label.font = MMFont.font(ofSize: 9.5, weight: .bold)
        label.textColor = NSColor(red: 63 / 255, green: 67 / 255, blue: 80 / 255, alpha: 0.75)
        label.alignment = .center
        label.isEditable = false
        label.isSelectable = false
        label.frame = NSRect(x: 0, y: 1, width: 32, height: 14)
        badge.addSubview(label)
        return badge
    }
    
    private func rebuildTimelineContent(scrollToBottom: Bool = false) {
        let chatW = chatPanel.bounds.width
        let chatH = chatPanel.bounds.height
        // Keep in sync with layoutRightChatPanel(): 56pt header, 50/90pt composer.
        let headerH: CGFloat = 56
        let headerY = chatH - headerH
        let composerH: CGFloat = isComposerToolbarVisible ? 90 : 50
        let composerTop = 24 + composerH
        let scrollH = max(0, headerY - composerTop)
        timelineScrollView.frame = NSRect(x: 0, y: composerTop, width: chatW, height: scrollH)
        
        timelineDocView.subviews.forEach { $0.removeFromSuperview() }
        
        var currentY: CGFloat = 16
        
        // 1. Welcome Hero
        let heroW: CGFloat = min(chatW - 40, 480)
        let heroH: CGFloat = 216
        timelineHeroContainer.frame = NSRect(x: (chatW - heroW) / 2, y: currentY, width: heroW, height: heroH)
        timelineHeroContainer.isHidden = false
        layoutHeroSubviews(heroW: heroW)
        timelineDocView.addSubview(timelineHeroContainer)
        currentY += heroH + 16
        
        // 2. Posts and Date Separators
        let fullDateFmt = DateFormatter()
        fullDateFmt.locale = Locale(identifier: "en_US_POSIX")
        fullDateFmt.dateFormat = "MMMM d, yyyy"
        let weekdayFmt = DateFormatter()
        weekdayFmt.locale = Locale(identifier: "en_US_POSIX")
        weekdayFmt.dateFormat = "EEEE"
        let calendar = Calendar.current
        func separatorString(for date: Date) -> String {
            if calendar.isDateInToday(date) { return "Today" }
            if calendar.isDateInYesterday(date) { return "Yesterday" }
            let days = calendar.dateComponents([.day], from: calendar.startOfDay(for: date), to: calendar.startOfDay(for: Date())).day ?? 99
            if days < 6 {
                return weekdayFmt.string(from: date)
            }
            return fullDateFmt.string(from: date)
        }
        
        let timeFmt = DateFormatter()
        timeFmt.locale = Locale(identifier: "en_US_POSIX")
        timeFmt.dateFormat = "h:mm a"
        
        var postsToRender = currentChannelPosts
        if postsToRender.isEmpty && !((NSApp.delegate as? AppDelegate)?.webService.isLogged() ?? false) && CommandLine.arguments.contains("--demo") {
            let nowMs = Int64(Date().timeIntervalSince1970 * 1000)
            if userStatusById["sarah"] == nil {
                userStatusById["sarah"] = "away"
            }
            if usersById["sarah"] == nil {
                usersById["sarah"] = LoginWebService(
                    id: "sarah",
                    create_at: nil, update_at: nil, delete_at: nil,
                    username: "sarah.connor",
                    first_name: "Sarah", last_name: "Connor",
                    nickname: nil, email: "sarah@example.com",
                    email_verified: true, auth_service: nil,
                    roles: "system_user", locale: "en",
                    position: "DevOps", is_bot: false,
                    last_password_update: nil, remote_id: nil,
                    disable_welcome_email: nil, notify_props: nil,
                    timezone: nil, auth_data: nil
                )
            }
            postsToRender = [
                MMPost(
                    id: "sample_sys",
                    create_at: nowMs - 86400000 * 10,
                    update_at: nil, edit_at: nil, delete_at: nil, is_pinned: false,
                    user_id: "system", channel_id: activeChannelId, root_id: nil, original_id: nil,
                    message: "You joined the team.", type: "system_join_channel"
                ),
                MMPost(
                    id: "sample_usr_sarah",
                    create_at: nowMs - 120000,
                    update_at: nil, edit_at: nil, delete_at: nil, is_pinned: false,
                    user_id: "sarah", channel_id: activeChannelId, root_id: nil, original_id: nil,
                    message: "Hey everyone! I'll be stepping away for a moment.", type: nil
                ),
                MMPost(
                    id: "sample_usr",
                    create_at: nowMs - 60000,
                    update_at: nowMs - 15000,
                    edit_at: nowMs - 15000,
                    delete_at: nil,
                    is_pinned: false,
                    user_id: currentUser?.id ?? "usr", channel_id: activeChannelId, root_id: nil, original_id: nil,
                    message: "Welcome! Message formatting supports **bold**, *italic*, ~~strikethrough~~, and [clickable links](https://mattermost.com).\n> Quoted blockquote text\n- First bullet item\n- Second bullet with **bold**", type: nil
                ),
                MMPost(
                    id: "sample_usr_giphy",
                    create_at: nowMs - 30000,
                    update_at: nil, edit_at: nil, delete_at: nil, is_pinned: false,
                    user_id: currentUser?.id ?? "usr", channel_id: activeChannelId, root_id: nil, original_id: nil,
                    message: "Check out this animated Giphy icon:\n![waving cat](https://media.giphy.com/media/ICOgUNjpvO0PC/giphy.gif)", type: nil
                ),
                MMPost(
                    id: "sample_usr_2",
                    create_at: nowMs,
                    update_at: nil, edit_at: nil, delete_at: nil, is_pinned: false,
                    user_id: currentUser?.id ?? "usr", channel_id: activeChannelId, root_id: nil, original_id: nil,
                    message: "This is a consecutive message from the same person. It prints only the chat text without repeating the icon or name, exactly like Mattermost.", type: nil
                )
            ]
        }
        
        var lastDateStr: String? = nil
        var lastUserId: String? = nil
        var lastWasSystem = false
        for post in postsToRender {
            let postDate = Date(timeIntervalSince1970: TimeInterval(post.create_at) / 1000.0)
            let dateStr = separatorString(for: postDate)
            let isSystem = (post.type?.hasPrefix("system_") ?? false) || (usersById[post.user_id]?.username == "System")
            if dateStr != lastDateStr {
                lastDateStr = dateStr
                lastUserId = nil
                lastWasSystem = false
                let sepView = createDateSeparator(dateStr: dateStr, width: chatW)
                sepView.frame.origin.y = currentY
                timelineDocView.addSubview(sepView)
                currentY += 24 + 10
            }
            
            let isConsecutive = (!isSystem && !lastWasSystem && post.user_id == lastUserId && !post.user_id.isEmpty)
            let (rowView, rowH) = createPostRow(post: post, width: chatW, timeStr: timeFmt.string(from: postDate), isConsecutive: isConsecutive)
            rowView.frame.origin.y = currentY
            timelineDocView.addSubview(rowView)
            currentY += rowH + (isConsecutive ? 2 : 4)
            
            lastUserId = post.user_id
            lastWasSystem = isSystem
        }
        
        currentY += 16
        let totalHeight = max(scrollH, currentY)
        timelineDocView.frame = NSRect(x: 0, y: 0, width: chatW, height: totalHeight)
        
        if scrollToBottom {
            DispatchQueue.main.async { [weak self] in
                guard let self = self else { return }
                let maxY = max(0, self.timelineDocView.frame.height - self.timelineScrollView.contentView.bounds.height)
                self.timelineScrollView.contentView.scroll(to: NSPoint(x: 0, y: maxY))
                self.timelineScrollView.reflectScrolledClipView(self.timelineScrollView.contentView)
            }
        }
    }
    
    private func layoutRightChatPanel() {
        let chatW = chatPanel.bounds.width
        let chatH = chatPanel.bounds.height
        let headerH: CGFloat = 56
        let headerY = chatH - headerH
        
        if isRightPanelVisible {
            let composerArea: CGFloat = 24 + (isComposerToolbarVisible ? 90 : 50) + 8
            let panelWidth = min(320, max(240, chatW * 0.36))
            let panelHeight = max(0, chatH - headerH - composerArea)
            rightPanel.frame = NSRect(x: chatW - panelWidth, y: composerArea, width: panelWidth, height: panelHeight)
            rightPanelTitle.frame = NSRect(x: 16, y: panelHeight - 40, width: panelWidth - 64, height: 20)
            rightPanelCloseButton.frame = NSRect(x: panelWidth - 38, y: panelHeight - 44, width: 24, height: 24)
            rightPanelScroll.frame = NSRect(x: 0, y: 0, width: panelWidth, height: max(0, panelHeight - 48))
        }
        
        chatTimelineContainer.frame = NSRect(x: 0, y: 0, width: chatW, height: headerY)
        
        // 1. Channel Header Bar (web: 56pt tall, 12pt padding, 12pt top corners)
        channelHeaderBorder.isHidden = true
        channelStarButton.frame = NSRect(x: 14, y: headerY + 16, width: 24, height: 24)
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
        
        channelPinsButton.frame = NSRect(x: channelMembersButton.frame.maxX + 4, y: headerY + 16, width: 24, height: 24)
        channelPinsIconView.frame = NSRect(x: 5, y: 5, width: 14, height: 14)
        
        // Web: 32pt icon buttons at the trailing edge, 4pt apart, 12pt from the right.
        channelInfoButton.frame = NSRect(x: chatW - 44, y: headerY + 12, width: 32, height: 32)
        channelInfoIconView.frame = NSRect(x: 7, y: 7, width: 18, height: 18)
        
        channelSidebarButton.frame = NSRect(x: chatW - 80, y: headerY + 12, width: 32, height: 32)
        channelSidebarIconView.frame = NSRect(x: 7, y: 7, width: 18, height: 18)
        
        // 2. Composer at bottom (web: 2pt border, 4pt radius, 50pt editor + 24pt footer)
        let composerW = max(chatW - 48, 200)
        let composerH: CGFloat = isComposerToolbarVisible ? 90 : 50
        let composerBottom: CGFloat = 24
        chatEntryPanel.frame = NSRect(x: 24, y: composerBottom, width: composerW, height: composerH)
        if isComposerToolbarVisible {
            entryView.textContainerInset = NSSize(width: 0, height: 4)
            entryView.frame = NSRect(x: 14, y: 40, width: composerW - 28, height: 36)
        } else {
            entryView.textContainerInset = NSSize(width: 0, height: 13)
            entryView.frame = NSRect(x: 14, y: 0, width: composerW - 234, height: composerH)
        }
        composerHelpLabel.frame = NSRect(x: chatW - 24 - 60, y: 3, width: 60, height: 18)
        composerHelpLabel.alignment = .right
        
        let toolY: CGFloat = isComposerToolbarVisible ? 8 : (composerH - 32) / 2
        
        var btnX: CGFloat = 8
        for (i, btn) in composerLeftButtons.enumerated() {
            if i == 3 {
                composerLeftSeparator.frame = NSRect(x: btnX + 3, y: toolY + 4, width: 1, height: 24)
                btnX += 9
            }
            btn.frame = NSRect(x: btnX, y: toolY, width: 32, height: 32)
            btnX += 34
        }
        
        composerSendButton.frame = NSRect(x: composerW - 9 - 48, y: toolY, width: 48, height: 32)
        composerEmojiButton.frame = NSRect(x: composerSendButton.frame.minX - 4 - 32, y: toolY, width: 32, height: 32)
        composerAttachButton.frame = NSRect(x: composerEmojiButton.frame.minX - 4 - 32, y: toolY, width: 32, height: 32)
        composerRightSeparator.frame = NSRect(x: composerAttachButton.frame.minX - 6, y: toolY + 4, width: 1, height: 24)
        
        let aaText = "Aa"
        let aaFont = composerAaButton.subviews.compactMap { ($0 as? NSTextField)?.font }.first ?? MMFont.font(ofSize: 14, weight: .semibold)
        let aaSize = (aaText as NSString).size(withAttributes: [.font: aaFont])
        let aaBtnW = max(44, ceil(aaSize.width) + 26)
        let aaX = composerRightSeparator.frame.minX - 4 - aaBtnW
        composerAaButton.frame = NSRect(x: aaX, y: toolY, width: aaBtnW, height: 32)
        composerGifButton.frame = NSRect(x: aaX - 36, y: toolY, width: 32, height: 32)
        
        // 3. Scrollable Timeline
        let composerTop = composerBottom + composerH
        let scrollH = max(0, headerY - composerTop)
        timelineScrollView.frame = NSRect(x: 0, y: composerTop, width: chatW, height: scrollH)
        let wasNearBottom = (timelineScrollView.contentView.bounds.maxY >= (timelineDocView.frame.height - 40))
        if abs(chatW - lastTimelineWidth) > 1 {
            lastTimelineWidth = chatW
            rebuildTimelineContent(scrollToBottom: wasNearBottom)
        }
    }
    
    @objc func windowDidResize(_ notification: Notification) {
        let factor = ZoomManager.shared.currentZoomFactor
        if let cv = contentView, factor > 0 {
            cv.bounds = NSRect(x: 0, y: 0, width: cv.frame.width / factor, height: cv.frame.height / factor)
        }
        updateViews()
    }
    
    func applyZoomFactor(_ factor: CGFloat) {
        guard let cv = contentView, factor > 0 else { return }
        cv.bounds = NSRect(x: 0, y: 0, width: cv.frame.width / factor, height: cv.frame.height / factor)
        updateViews()
    }
    
    @objc private func zoomDidChangeNotification(_ notification: Notification) {
        applyZoomFactor(ZoomManager.shared.currentZoomFactor)
        ZoomHUD.shared.show(factor: ZoomManager.shared.currentZoomFactor, in: self)
    }
    
    func updateViews() {
        let size = contentView!.bounds.size
        let topBarHeight: CGFloat = 44
        let topBarY = size.height - topBarHeight
        
        let gutter: CGFloat = 4
        // Web: sidebar occupies 264pt starting 5pt from the window edge, then the
        // white channel card starts at 269pt; both share a 4pt gutter.
        let chatPanelX: CGFloat = 269
        mainPanel.frame = NSRect(x: gutter, y: gutter, width: size.width - gutter * 2, height: topBarY - gutter)
        mainPanel.cornerRadius = 12
        sidebarTopBorder.frame = NSRect(x: 0, y: mainPanel.bounds.height - 1, width: size.width - gutter * 2, height: 1)
        sidebarTopBorder.isHidden = true
        chatPanel.frame = NSRect(x: chatPanelX, y: gutter, width: size.width - chatPanelX - gutter, height: topBarY - gutter)
        chatPanel.cornerRadius = 12
        
        treeView.frame = NSRect(x: 0, y: 0, width: 264, height: mainPanel.bounds.height)
        layoutLeftSidebar(topBarY: mainPanel.bounds.height)
        layoutRightChatPanel()

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
        
        helpPanel.frame = NSRect(x: searchX + searchWidth + 8, y: topBarY + 8, width: 28, height: 28)
        helpIconView.frame = NSRect(x: 6, y: 6, width: 16, height: 16)
        helpMenu.frame = NSRect(x: helpPanel.frame.minX, y: topBarY - 178, width: 204, height: 176)
        
        searchPopoverPanel.frame = NSRect(x: searchX, y: topBarY - 124, width: 400, height: 122)
        
        // Right: Mentions (@), Saved Posts, Settings, User Avatar + Status Dot.
        // Web: 28pt buttons with 8pt gaps ending 4pt from the window edge, 40x32 avatar button.
        avatarButtonPanel.frame = NSRect(x: size.width - 44, y: topBarY + 6, width: 40, height: 32)
        avatarPanel.frame = NSRect(x: 8, y: 4, width: 24, height: 24)
        avatarLabel.frame = NSRect(x: 0, y: 5, width: 24, height: 14)
        statusDotPanel.frame = NSRect(x: 21, y: 1, width: 16, height: 16)
        updateStatusCheck(in: statusDotPanel, status: currentUserStatus)
        statusMenu.frame = NSRect(x: size.width - 259, y: topBarY - 356, width: 248, height: 354)
        dndSubMenu.frame = NSRect(x: statusMenu.frame.minX - 210, y: statusMenu.frame.minY - 50, width: 212, height: 232)
        
        settingsPanel.frame = NSRect(x: size.width - 80, y: topBarY + 8, width: 28, height: 28)
        settingsIconView.frame = NSRect(x: 6, y: 6, width: 16, height: 16)
        
        savedPostsPanel.frame = NSRect(x: size.width - 116, y: topBarY + 8, width: 28, height: 28)
        savedPostsIconView.frame = NSRect(x: 6, y: 6, width: 16, height: 16)
        
        mentionsPanel.frame = NSRect(x: size.width - 152, y: topBarY + 8, width: 28, height: 28)
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
        searchResultsCloseButton.frame = NSRect(x: resultsWidth - 36, y: resultsHeight - 38, width: 24, height: 24)
        if !searchResultsPanel.isHidden {
            searchResultsScroll.frame = NSRect(x: 0, y: 0, width: resultsWidth, height: resultsHeight - 44)
        }
    }
    
    // MARK: - Live REST API & WebSocket Integration
    
    private func bindWebServiceAndLoadData() {
        guard let ws = (NSApp.delegate as? AppDelegate)?.webService else { return }
        
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
        
        ws.onWebSocketEvent = { event in
            DebugLog.log("ws.onWebSocketEvent: \(event)")
        }
        
        ws.onWebSocketConnected = { [weak self] in
            DebugLog.log("ws.onWebSocketConnected callback triggered")
            self?.refreshUserStatuses()
        }
        
        ws.onMultipleStatusesReceived = { [weak self] statuses in
            DebugLog.log("ws.onMultipleStatusesReceived: \(statuses)")
            guard let self = self else { return }
            for (userId, status) in statuses {
                self.userStatusById[userId] = status
                self.updateChatWidgetUserStatus(userId: userId, status: status)
            }
        }
        
        ws.onStatusChanged = { [weak self] userId, status in
            DebugLog.log("ws.onStatusChanged: userId=\(userId), status=\(status)")
            guard let self = self else { return }
            self.userStatusById[userId] = status
            self.updateChatWidgetUserStatus(userId: userId, status: status)
            if let myId = self.currentUser?.id ?? (NSApp.delegate as? AppDelegate)?.webService.currentUserId, myId == userId {
                let idx = self.indexForStatus(status)
                self.selectedStatusIndex = idx
                for (i, checkView) in self.statusCheckViews.enumerated() {
                    checkView.isHidden = (i != idx)
                }
                self.currentUserStatus = status
                let color = self.statusColor(for: status)
                self.statusDotPanel.color = color
                self.statusDotPanel.setNeedsAppearanceUpdate()
                self.updateStatusCheck(in: self.statusDotPanel, status: status)
                self.menuAvatarStatusDot?.color = color
                self.menuAvatarStatusDot?.setNeedsAppearanceUpdate()
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
                    self.currentUserStatus = myStatus.status
                    self.userStatusById[me.id] = myStatus.status
                    let idx = self.indexForStatus(myStatus.status)
                    self.selectedStatusIndex = idx
                    for (i, checkView) in self.statusCheckViews.enumerated() {
                        checkView.isHidden = (i != idx)
                    }
                    let color = self.statusColor(for: myStatus.status)
                    self.statusDotPanel.color = color
                    self.statusDotPanel.setNeedsAppearanceUpdate()
                    self.updateStatusCheck(in: self.statusDotPanel, status: myStatus.status)
                    self.menuAvatarStatusDot?.color = color
                    self.menuAvatarStatusDot?.setNeedsAppearanceUpdate()
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
    }
    
    private func loadChannelPosts(forSidebarItemId itemId: String) {
        let normalized = itemId.lowercased()
        guard let ch = channelsById[itemId] ?? channelsByName[normalized] else { return }
        activeChannelId = ch.id
        refreshFavoriteState()
        (NSApp.delegate as? AppDelegate)?.markChannelRead(ch.id)
        reloadRightPanelIfNeeded()
        let resolvedTitle = channelDisplayName(for: ch)
        channelTitleLabel.stringValue = resolvedTitle
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
        currentChannelPosts = []
        rebuildTimelineContent(scrollToBottom: false)
        Task { @MainActor [weak self] in
            await self?.fetchAndRenderPosts(channelId: ch.id)
        }
    }
    
    @MainActor
    private func fetchAndRenderPosts(channelId: String) async {
        guard let ws = (NSApp.delegate as? AppDelegate)?.webService, ws.isLogged() else { return }
        do {
            let postList = try await ws.fetchChannelPosts(channelId: channelId)
            let posts = postList.chronologicalPosts
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
                    self.userStatusById[st.user_id] = st.status
                }
            }
            // Discard results for a channel that is no longer open.
            guard self.activeChannelId == channelId else { return }
            applyPostsToTimeline(posts)
        } catch {
            NSLog("Failed to fetch posts for channel \(channelId): \(error.localizedDescription)")
        }
    }
    
    @MainActor
    private func applyPostsToTimeline(_ posts: [MMPost]) {
        currentChannelPosts = posts
        rebuildTimelineContent(scrollToBottom: true)
    }
    
    /// Inserts a WebSocket post directly instead of refetching the channel.
    @MainActor
    private func appendRealtimePost(_ post: MMPost) {
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
    
    // MARK: - Unread handling
    
    @MainActor
    private func handleIncomingPost(_ post: MMPost) {
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
    
    private func notificationExcerpt(from message: String) -> String {
        var text = message
            .replacingOccurrences(of: "\n", with: " ")
            .replacingOccurrences(of: ">", with: "")
            .trimmingCharacters(in: .whitespacesAndNewlines)
        if text.count > 160 {
            text = String(text.prefix(160)) + "…"
        }
        return text.isEmpty ? "New message" : text
    }
    
    /// Opens a channel (used by notification taps).
    func openChannel(withId channelId: String) {
        guard let channel = channelsById[channelId] else { return }
        selectedSidebarItemId = channel.id
        updateSidebarSelectionAppearance()
        loadChannelPosts(forSidebarItemId: channel.id)
    }
    
    @objc private func appDidBecomeActive() {
        guard !activeChannelId.isEmpty else { return }
        (NSApp.delegate as? AppDelegate)?.markChannelRead(activeChannelId)
    }
    
    /// Enables/disables the send button as the editor content changes.
    private func updateComposerSendState() {
        let hasText = !entryView.string.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty
        guard hasText != composerSendEnabled else { return }
        composerSendEnabled = hasText
        if hasText {
            composerSendButton.color = NSColor(red: 28 / 255, green: 88 / 255, blue: 217 / 255, alpha: 1.0)
            composerSendIconView?.contentTintColor = .white
        } else {
            composerSendButton.color = NSColor(red: 63 / 255, green: 67 / 255, blue: 80 / 255, alpha: 0.08)
            composerSendIconView?.contentTintColor = NSColor(red: 63 / 255, green: 67 / 255, blue: 80 / 255, alpha: 0.32)
        }
        composerSendButton.setNeedsAppearanceUpdate()
    }
    
    /// Sends the composer contents, clearing the editor only once the post is
    /// accepted so a failure does not lose the user's text.
    private func sendComposerMessage() {
        let message = entryView.string.trimmingCharacters(in: .whitespacesAndNewlines)
        guard !message.isEmpty, !activeChannelId.isEmpty else { return }
        let channelId = activeChannelId
        
        entryView.string = ""
        entryView.needsDisplay = true
        updateComposerSendState()
        composerHelpLabel.stringValue = "Sending…"
        
        Task { @MainActor [weak self] in
            guard let self = self, let ws = (NSApp.delegate as? AppDelegate)?.webService else { return }
            do {
                let post = try await ws.createPost(channelId: channelId, message: message)
                if self.activeChannelId == channelId {
                    self.currentChannelPosts.append(post)
                    self.rebuildTimelineContent(scrollToBottom: true)
                }
                self.composerHelpLabel.stringValue = "Help"
            } catch {
                self.composerHelpLabel.stringValue = "Message failed to send"
                if self.entryView.string.isEmpty {
                    self.entryView.string = message
                    self.updateComposerSendState()
                }
                DispatchQueue.main.asyncAfter(deadline: .now() + 4) { [weak self] in
                    self?.composerHelpLabel.stringValue = "Help"
                }
                NSLog("Failed to send post: \(error.localizedDescription)")
            }
        }
    }
    
    func sendActiveChannelPost(message: String) {
        let trimmed = message.trimmingCharacters(in: .whitespacesAndNewlines)
        guard !trimmed.isEmpty, !activeChannelId.isEmpty else { return }
        let channelId = activeChannelId
        Task { @MainActor [weak self] in
            guard let self = self, let ws = (NSApp.delegate as? AppDelegate)?.webService else { return }
            do {
                let post = try await ws.createPost(channelId: channelId, message: trimmed)
                if self.activeChannelId == channelId {
                    self.currentChannelPosts.append(post)
                    self.rebuildTimelineContent(scrollToBottom: true)
                }
            } catch {
                NSLog("Failed to send post: \(error.localizedDescription)")
            }
        }
    }
    
    func controlTextDidChange(_ notification: Notification) {
        guard (notification.object as? NSTextField) === findChannelLabel else { return }
        channelFilterQuery = findChannelLabel.stringValue.trimmingCharacters(in: .whitespacesAndNewlines)
        layoutLeftSidebar(topBarY: mainPanel.bounds.height)
    }
    
    private func sendTypingIfNeeded() {
        guard !entryView.string.isEmpty, !activeChannelId.isEmpty else { return }
        if let last = lastTypingSentAt, Date().timeIntervalSince(last) < 1.5 { return }
        lastTypingSentAt = Date()
        (NSApp.delegate as? AppDelegate)?.webService.sendUserTyping(channelId: activeChannelId)
    }
    
    // MARK: - NSTextViewDelegate (composer)
    
    func textDidChange(_ notification: Notification) {
        guard (notification.object as? NSTextView) === entryView else { return }
        entryView.needsDisplay = true
        updateComposerSendState()
        sendTypingIfNeeded()
    }
    
    func textView(_ textView: NSTextView, doCommandBy commandSelector: Selector) -> Bool {
        guard textView === entryView else { return false }
        if commandSelector == #selector(NSResponder.insertNewline(_:)) {
            // Shift+Return inserts a newline; Return sends.
            if NSApp.currentEvent?.modifierFlags.contains(.shift) == true { return false }
            sendComposerMessage()
            return true
        }
        return false
    }

    @objc private func timelineBoundsDidChange(_ notification: Notification) {
        updateTimelineHoverState()
    }

    private func updateTimelineHoverState() {
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
