//
//  LoginWindow.swift
//  mattermost.client
//
//  Created by Boris Barbulovski on 31.10.24.
//

import Cocoa

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

private class TimelineFlippedView: NSView {
    override var isFlipped: Bool { true }
}

private class TimelineRowView: RoundedEdgePanel {
    override var isFlipped: Bool { true }
}

private class TimelineContainerView: NSView {
    override func hitTest(_ point: NSPoint) -> NSView? {
        let view = super.hitTest(point)
        return (view === self) ? nil : view
    }
}

class MainWindow: NSWindow {
    let mainPanel = RoundedEdgePanel()
    let chatPanel = RoundedEdgePanel()
    let chatEntryPanel = OutlinePanel()
    let mainTreeDelegate = MainWindowDelegate()
    let treeView = NSOutlineView()
    let entryView = NSTextView()
    
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
    let channelInfoButton = RoundedEdgePanel()
    let channelInfoIconView = NSImageView()
    
    // 2. Message Timeline & Welcome Hero
    private let chatTimelineContainer = TimelineContainerView()
    private let timelineScrollView = NSScrollView()
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
    let composerRightSeparator = RoundedEdgePanel()
    let composerEmojiButton = RoundedEdgePanel()
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

        mainPanel.color = NSColor(red: 30 / 255, green: 50 / 255, blue: 92 / 255, alpha: 1)
        mainPanel.cornerRadius = 0
        sidebarTopBorder.color = NSColor(white: 1.0, alpha: 0.10)
        sidebarTopBorder.cornerRadius = 0
        
        entryView.backgroundColor = .white
        entryView.isEditable = false
        entryView.isSelectable = false
        entryView.isHidden = true
        
        chatEntryPanel.color = NSColor(red: 209 / 255, green: 213 / 255, blue: 219 / 255, alpha: 1.0)
        chatEntryPanel.cornerRadius = 6
        chatEntryPanel.borderWidth = 1
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
        bindWebServiceAndLoadData()
    }
    
    private func setupTopGlobalBar() {
        let topBarTint = NSColor(white: 1.0, alpha: 0.64)
        let hoverBg = NSColor(white: 1.0, alpha: 0.08)
        
        // Left: Product switcher container (grid icon + Mattermost logo + TEAM EDITION badge)
        productSwitcherPanel.color = .clear
        productSwitcherPanel.cornerRadius = 4
        
        boxImage.imageScaling = .scaleProportionallyUpOrDown
        boxImage.alphaValue = 0.56
        logo.imageScaling = .scaleProportionallyUpOrDown
        logo.alphaValue = 0.64
        
        editionBadgePanel.color = NSColor(white: 1.0, alpha: 0.12)
        editionBadgePanel.cornerRadius = 3
        editionBadgeLabel.font = NSFont.systemFont(ofSize: 7.5, weight: .bold)
        editionBadgeLabel.textColor = NSColor(white: 1.0, alpha: 0.72)
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
        searchPanel.color = NSColor(white: 1.0, alpha: 0.10)
        searchPanel.cornerRadius = 4
        if let searchImg = NSImage(systemSymbolName: "magnifyingglass", accessibilityDescription: "Search") {
            searchIconView.image = searchImg.withSymbolConfiguration(.init(pointSize: 12, weight: .medium))
            searchIconView.contentTintColor = topBarTint
        }
        searchLabel.font = NSFont.systemFont(ofSize: 12)
        searchLabel.textColor = topBarTint
        searchLabel.isEditable = false
        searchLabel.isSelectable = false
        searchPanel.addSubview(searchIconView)
        searchPanel.addSubview(searchLabel)
        searchPanel.onHoverChanged = { [weak self] isHovered in
            guard let self = self else { return }
            self.searchPanel.color = NSColor(white: 1.0, alpha: isHovered ? 0.16 : 0.10)
            self.searchPanel.setNeedsAppearanceUpdate()
            self.searchIconView.contentTintColor = isHovered ? .white : topBarTint
            self.searchLabel.textColor = isHovered ? .white : topBarTint
        }
        searchPanel.onClick = { [weak self] in
            self?.toggleSearchPopover()
        }
        contentView?.addSubview(searchPanel)
        
        helpPanel.color = .clear
        helpPanel.cornerRadius = 4
        if let helpImg = NSImage(systemSymbolName: "questionmark.circle.fill", accessibilityDescription: "Help") {
            helpIconView.image = helpImg.withSymbolConfiguration(.init(pointSize: 14, weight: .medium))
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
            hoverBg: hoverBg
        )
        configureIconButton(
            panel: savedPostsPanel,
            iconView: savedPostsIconView,
            symbolName: "bookmark",
            pointSize: 13,
            accessibilityDescription: "Saved Posts",
            defaultTint: topBarTint,
            hoverBg: hoverBg
        )
        configureIconButton(
            panel: settingsPanel,
            iconView: settingsIconView,
            symbolName: "gearshape",
            pointSize: 14,
            accessibilityDescription: "Settings",
            defaultTint: topBarTint,
            hoverBg: hoverBg
        )
        
        // User avatar circle + online status indicator dot
        avatarButtonPanel.color = .clear
        avatarButtonPanel.cornerRadius = 15
        
        let initial = (UserDefaults.standard.string(forKey: "username")?.first).map { String($0).uppercased() } ?? "B"
        avatarLabel.stringValue = initial
        avatarLabel.font = NSFont.systemFont(ofSize: 12, weight: .semibold)
        avatarLabel.textColor = .white
        avatarLabel.alignment = .center
        
        avatarPanel.color = NSColor(red: 156 / 255, green: 171 / 255, blue: 36 / 255, alpha: 1.0)
        avatarPanel.cornerRadius = 12
        avatarPanel.addSubview(avatarLabel)
        
        avatarImageView.imageScaling = .scaleProportionallyUpOrDown
        avatarImageView.frame = NSRect(x: 0, y: 0, width: 24, height: 24)
        avatarImageView.isHidden = true
        avatarPanel.addSubview(avatarImageView)
        
        statusDotPanel.color = NSColor(red: 61 / 255, green: 184 / 255, blue: 135 / 255, alpha: 1.0)
        statusDotPanel.cornerRadius = 4.5
        statusDotPanel.borderWidth = 1.5
        statusDotPanel.borderColor = NSColor(red: 25 / 255, green: 42 / 255, blue: 77 / 255, alpha: 1.0)
        
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
        setupHelpMenu()
        setupStatusMenu()
    }
    
    private func updateProductSwitcherAppearance() {
        let active = productSwitcherPanel.isHovered || isProductMenuOpen
        let hoverBg = NSColor(white: 1.0, alpha: 0.08)
        productSwitcherPanel.color = active ? hoverBg : .clear
        productSwitcherPanel.setNeedsAppearanceUpdate()
        boxImage.alphaValue = active ? 1.0 : 0.56
        logo.alphaValue = active ? 1.0 : 0.64
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
        setStatusMenuOpen(!isStatusMenuOpen)
    }
    
    private func setStatusMenuOpen(_ open: Bool) {
        guard isStatusMenuOpen != open else { return }
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
    
    private func selectUserStatus(_ index: Int) {
        selectedStatusIndex = index
        for (i, checkView) in statusCheckViews.enumerated() {
            checkView.isHidden = (i != index)
        }
        let statusColors: [NSColor] = [
            NSColor(red: 61 / 255, green: 184 / 255, blue: 135 / 255, alpha: 1.0),
            NSColor(red: 245 / 255, green: 171 / 255, blue: 0 / 255, alpha: 1.0),
            NSColor(red: 210 / 255, green: 75 / 255, blue: 78 / 255, alpha: 1.0),
            NSColor(red: 156 / 255, green: 163 / 255, blue: 175 / 255, alpha: 1.0)
        ]
        if index >= 0 && index < statusColors.count {
            statusDotPanel.color = statusColors[index]
            statusDotPanel.setNeedsAppearanceUpdate()
        }
        setStatusMenuOpen(false)
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
            searchPopoverInputLabel.stringValue = "Search files"
        } else {
            messagesTabPanel.color = activeTabBg
            messagesTabLabel.textColor = brandBlue
            filesTabPanel.color = filesTabPanel.isHovered ? hoverTabBg : .clear
            filesTabLabel.textColor = mutedText
            searchPopoverInputLabel.stringValue = "Search messages"
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
        let tabFont = NSFont.systemFont(ofSize: 11, weight: .semibold)
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
        
        searchPopoverInputLabel.font = NSFont.systemFont(ofSize: 13)
        searchPopoverInputLabel.textColor = placeholderColor
        searchPopoverInputLabel.isEditable = false
        searchPopoverInputLabel.isSelectable = false
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
        filterHintLabel.font = NSFont.systemFont(ofSize: 11)
        filterHintLabel.textColor = mutedText
        filterHintLabel.isEditable = false
        filterHintLabel.isSelectable = false
        let hintSize = ("Filter your search with:" as NSString).size(withAttributes: [.font: filterHintLabel.font!])
        let hintW = ceil(hintSize.width) + 4
        let hintH = ceil(hintSize.height)
        filterHintLabel.frame = NSRect(x: 34, y: 13, width: hintW, height: hintH)
        searchPopoverPanel.addSubview(filterHintLabel)
        
        let filterTitles = ["From:", "In:", "On:", "Before:", "After:"]
        let pillFont = NSFont.systemFont(ofSize: 10, weight: .semibold)
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
            font: NSFont.systemFont(ofSize: 13, weight: .semibold),
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
                font: NSFont.systemFont(ofSize: 13, weight: .regular),
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
        footerBadgeLabel.font = NSFont.systemFont(ofSize: 8, weight: .bold)
        footerBadgeLabel.textColor = NSColor(red: 75 / 255, green: 85 / 255, blue: 99 / 255, alpha: 1.0)
        footerBadgeLabel.alignment = .center
        
        let footerBadgeText = footerBadgeLabel.stringValue.isEmpty ? "TEAM EDITION" : footerBadgeLabel.stringValue
        let footerFont = footerBadgeLabel.font ?? NSFont.systemFont(ofSize: 8, weight: .bold)
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
                .font: NSFont.systemFont(ofSize: 11),
                .foregroundColor: mutedIcon
            ]
        )
        footerText.append(NSAttributedString(
            string: "unsupported",
            attributes: [
                .font: NSFont.systemFont(ofSize: 11),
                .foregroundColor: brandBlue,
                .underlineStyle: NSUnderlineStyle.single.rawValue
            ]
        ))
        footerText.append(NSAttributedString(
            string: " edition of\nMattermost.",
            attributes: [
                .font: NSFont.systemFont(ofSize: 11),
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
                font: NSFont.systemFont(ofSize: 13, weight: .regular),
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
        headerAvatarLabel.font = NSFont.systemFont(ofSize: 13, weight: .semibold)
        headerAvatarLabel.textColor = .white
        headerAvatarLabel.alignment = .center
        headerAvatarLabel.frame = NSRect(x: 0, y: 5, width: 28, height: 18)
        headerAvatar.addSubview(headerAvatarLabel)
        headerRow.addSubview(headerAvatar)
        
        let usernameLabel = NSTextField(labelWithString: "@\(cleanUsername)")
        usernameLabel.font = NSFont.systemFont(ofSize: 13, weight: .semibold)
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
            font: NSFont.systemFont(ofSize: 13, weight: .regular),
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
            titleLabel.font = NSFont.systemFont(ofSize: 13, weight: .regular)
            titleLabel.textColor = darkText
            let titleY: CGFloat = cfg.subtitle != nil ? 21 : (cfg.height - 18) / 2
            titleLabel.frame = NSRect(x: 42, y: titleY, width: menuWidth - 80, height: 18)
            row.addSubview(titleLabel)
            
            if let subtitle = cfg.subtitle {
                let subLabel = NSTextField(labelWithString: subtitle)
                subLabel.font = NSFont.systemFont(ofSize: 11, weight: .regular)
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
            font: NSFont.systemFont(ofSize: 13, weight: .regular),
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
            font: NSFont.systemFont(ofSize: 13, weight: .regular),
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
        headerLabel.font = NSFont.systemFont(ofSize: 11.5, weight: .semibold)
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
        
        let rows: [(title: String, rightText: String?, y: CGFloat, height: CGFloat)] = [
            ("Don't clear", nil, 167, 30),
            ("30 mins", nil, 137, 30),
            ("1 hour", nil, 107, 30),
            ("2 hours", nil, 77, 30),
            ("Tomorrow", tomorrowDayString, 47, 30),
            ("Choose date and time", nil, 6, 32)
        ]
        
        for item in rows {
            let row = RoundedEdgePanel()
            row.frame = NSRect(x: 0, y: item.y, width: subWidth, height: item.height)
            row.cornerRadius = 0
            row.color = .clear
            
            let titleLabel = NSTextField(labelWithString: item.title)
            titleLabel.font = NSFont.systemFont(ofSize: 13, weight: .regular)
            titleLabel.textColor = darkText
            titleLabel.frame = NSRect(x: 20, y: (item.height - 18) / 2, width: item.rightText != nil ? 90 : (subWidth - 36), height: 18)
            row.addSubview(titleLabel)
            
            if let rightText = item.rightText {
                let rightLabel = NSTextField(labelWithString: rightText)
                rightLabel.font = NSFont.systemFont(ofSize: 12, weight: .regular)
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
                self?.selectUserStatus(2)
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
                if isHelpMenuOpen && !helpMenu.frame.contains(point) && !helpPanel.frame.contains(point) {
                    setHelpMenuOpen(false)
                }
                if isStatusMenuOpen && !statusMenu.frame.contains(point) && !avatarButtonPanel.frame.contains(point) && !(isDndSubMenuOpen && dndSubMenu.frame.contains(point)) {
                    setStatusMenuOpen(false)
                }
                if isTeamMenuOpen && !teamDropdownMenu.frame.contains(point) && !teamHeaderButton.frame.contains(point) {
                    setTeamMenuOpen(false)
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
        hoverBg: NSColor
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
        contentView?.addSubview(panel)
    }
    
    private func setupLeftChannelSidebar() {
        let mutedTint = NSColor(white: 1.0, alpha: 0.64)
        let hoverBg = NSColor(white: 1.0, alpha: 0.08)
        
        // 1. Team Header Row: "None v" button + "+" button
        teamHeaderButton.color = .clear
        teamHeaderButton.cornerRadius = 4
        teamHeaderLabel.font = NSFont.systemFont(ofSize: 14.5, weight: .bold)
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
        
        teamAddButton.color = .clear
        teamAddButton.cornerRadius = 4
        if let plusImg = NSImage(systemSymbolName: "plus", accessibilityDescription: "Add") {
            teamAddIconView.image = plusImg.withSymbolConfiguration(.init(pointSize: 13, weight: .medium))
            teamAddIconView.contentTintColor = mutedTint
        }
        teamAddButton.addSubview(teamAddIconView)
        teamAddButton.onHoverChanged = { [weak self] isHovered in
            guard let self = self else { return }
            self.teamAddButton.color = isHovered ? hoverBg : .clear
            self.teamAddButton.setNeedsAppearanceUpdate()
            self.teamAddIconView.contentTintColor = isHovered ? .white : mutedTint
        }
        mainPanel.addSubview(teamAddButton)
        
        // 2. Filter & Find Channel Row
        filterChannelButton.color = .clear
        filterChannelButton.cornerRadius = 4
        if let filterImg = NSImage(systemSymbolName: "line.3.horizontal.decrease", accessibilityDescription: "Filter") {
            filterChannelIconView.image = filterImg.withSymbolConfiguration(.init(pointSize: 12, weight: .medium))
            filterChannelIconView.contentTintColor = mutedTint
        }
        filterChannelButton.addSubview(filterChannelIconView)
        filterChannelButton.onHoverChanged = { [weak self] isHovered in
            guard let self = self else { return }
            self.filterChannelButton.color = isHovered ? hoverBg : .clear
            self.filterChannelButton.setNeedsAppearanceUpdate()
            self.filterChannelIconView.contentTintColor = isHovered ? .white : mutedTint
        }
        mainPanel.addSubview(filterChannelButton)
        
        findChannelPanel.color = NSColor(white: 1.0, alpha: 0.08)
        findChannelPanel.cornerRadius = 4
        if let findImg = NSImage(systemSymbolName: "magnifyingglass", accessibilityDescription: "Find channel") {
            findChannelIconView.image = findImg.withSymbolConfiguration(.init(pointSize: 11.5, weight: .medium))
            findChannelIconView.contentTintColor = mutedTint
        }
        findChannelLabel.font = NSFont.systemFont(ofSize: 12)
        findChannelLabel.textColor = mutedTint
        findChannelLabel.isEditable = false
        findChannelLabel.isSelectable = false
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
            chevronView.image = chevImg.withSymbolConfiguration(.init(pointSize: 8.5, weight: .bold))
            chevronView.contentTintColor = mutedTint
        }
        headerRow.addSubview(chevronView)
        
        let titleLabel = NSTextField(labelWithString: title)
        titleLabel.font = NSFont.systemFont(ofSize: 10, weight: .bold)
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
        leftBar.cornerRadius = 1.5
        leftBar.color = .white
        leftBar.isHidden = true
        row.addSubview(leftBar)
        
        let iconView = NSImageView()
        if let custom = customImage {
            iconView.image = custom
            iconView.imageScaling = .scaleProportionallyUpOrDown
            iconView.frame = NSRect(x: 16, y: 5, width: 18, height: 18)
            row.addSubview(iconView)
        } else if isBotBadge {
            if let img = NSImage(systemSymbolName: symbolName, accessibilityDescription: title) {
                iconView.image = img.withSymbolConfiguration(.init(pointSize: 9.5, weight: .semibold))
                iconView.contentTintColor = NSColor(white: 1.0, alpha: 0.85)
            }
            iconView.frame = NSRect(x: 16, y: 5, width: 18, height: 18)
            row.addSubview(iconView)
        } else {
            if let img = NSImage(systemSymbolName: symbolName, accessibilityDescription: title) {
                iconView.image = img.withSymbolConfiguration(.init(pointSize: 12.5, weight: .medium))
            }
            iconView.frame = NSRect(x: 16, y: 6, width: 16, height: 16)
            row.addSubview(iconView)
        }
        
        let label = NSTextField(labelWithString: title)
        label.isEditable = false
        label.isSelectable = false
        label.frame = NSRect(x: 38, y: 5, width: 140, height: 18)
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
            if isSelectable {
                self.selectedSidebarItemId = id
                self.updateSidebarSelectionAppearance()
                self.channelTitleLabel.stringValue = title
                self.heroTitleLabel.stringValue = title
                self.composerPlaceholderLabel.stringValue = "Write to \(title)"
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
            layoutLeftSidebar(topBarY: contentView.bounds.height - 40)
        }
    }
    
    private func updateSidebarSelectionAppearance() {
        let allItems: [SidebarItemView] = (threadsSidebarItem.map { [$0] } ?? []) + sidebarCategories.flatMap { $0.items }
        let selectedBg = NSColor(white: 1.0, alpha: 0.12)
        let hoverBg = NSColor(white: 1.0, alpha: 0.08)
        let defaultText = NSColor(white: 1.0, alpha: 0.68)
        let defaultIcon = NSColor(white: 1.0, alpha: 0.64)
        
        for item in allItems {
            let isSelected = item.isSelectable && (item.id == selectedSidebarItemId)
            let isHovered = item.row.isHovered
            
            if isSelected {
                item.row.color = selectedBg
                item.leftBar.isHidden = false
                item.label.font = NSFont.systemFont(ofSize: 12.5, weight: .semibold)
                item.label.textColor = .white
                if !item.isBotBadge {
                    item.iconView.contentTintColor = .white
                } else {
                    item.iconView.contentTintColor = nil
                }
            } else if isHovered {
                item.row.color = hoverBg
                item.leftBar.isHidden = true
                item.label.font = NSFont.systemFont(ofSize: 12.5, weight: .regular)
                item.label.textColor = .white
                if !item.isBotBadge {
                    item.iconView.contentTintColor = .white
                } else {
                    item.iconView.contentTintColor = nil
                }
            } else {
                item.row.color = .clear
                item.leftBar.isHidden = true
                item.label.font = NSFont.systemFont(ofSize: 12.5, weight: .regular)
                item.label.textColor = defaultText
                if !item.isBotBadge {
                    item.iconView.contentTintColor = defaultIcon
                } else {
                    item.iconView.contentTintColor = nil
                }
            }
            item.row.setNeedsAppearanceUpdate()
            item.hoverCloseView?.isHidden = !isHovered
        }
    }
    
    private func layoutTeamHeader(topBarY: CGFloat? = nil) {
        let sidebarWidth: CGFloat = 206
        let top = topBarY ?? (mainPanel.bounds.height > 0 ? mainPanel.bounds.height : (contentView?.bounds.height ?? 800) - 40)
        let textWidth = ceil(teamHeaderLabel.attributedStringValue.size().width)
        let maxLabelWidth = sidebarWidth - 64
        let labelWidth = max(24, min(textWidth + 4, maxLabelWidth))
        let buttonWidth = labelWidth + 8 + 4 + 10 + 8
        
        teamHeaderButton.frame = NSRect(x: 8, y: top - 40, width: buttonWidth, height: 28)
        teamHeaderLabel.frame = NSRect(x: 8, y: 5, width: labelWidth, height: 18)
        teamHeaderChevron.frame = NSRect(x: 8 + labelWidth + 4, y: 9, width: 10, height: 10)
        
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
            emptyLabel.font = NSFont.systemFont(ofSize: 13, weight: .regular)
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
            label.font = NSFont.systemFont(ofSize: 13.5, weight: isActive ? .bold : .medium)
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
        let sidebarWidth: CGFloat = 206
        
        // Row 1: Team header button + "+" button
        layoutTeamHeader(topBarY: topBarY)
        
        teamAddButton.frame = NSRect(x: sidebarWidth - 36, y: topBarY - 39, width: 26, height: 26)
        teamAddIconView.frame = NSRect(x: 5, y: 5, width: 16, height: 16)
        
        // Row 2: Filter button + "Find channel" pill
        filterChannelButton.frame = NSRect(x: 8, y: topBarY - 74, width: 26, height: 26)
        filterChannelIconView.frame = NSRect(x: 5, y: 5, width: 16, height: 16)
        
        findChannelPanel.frame = NSRect(x: 36, y: topBarY - 74, width: sidebarWidth - 46, height: 26)
        findChannelIconView.frame = NSRect(x: 8, y: 5.5, width: 15, height: 15)
        findChannelLabel.frame = NSRect(x: 27, y: 4, width: sidebarWidth - 80, height: 18)
        
        // Row 3: Threads item
        var currentY = topBarY - 110
        if let threads = threadsSidebarItem {
            threads.row.frame = NSRect(x: 0, y: currentY, width: sidebarWidth, height: 28)
            threads.leftBar.frame = NSRect(x: 0, y: 0, width: 3, height: 28)
            threads.label.frame = NSRect(x: 38, y: 5, width: sidebarWidth - 48, height: 18)
            currentY -= 36
        }
        
        // Categories & items
        for category in sidebarCategories {
            category.headerRow.frame = NSRect(x: 0, y: currentY, width: sidebarWidth, height: 26)
            category.chevronView.frame = NSRect(x: 10, y: 8, width: 10, height: 10)
            category.titleLabel.frame = NSRect(x: 24, y: 6, width: sidebarWidth - 56, height: 14)
            category.addButton?.frame = NSRect(x: sidebarWidth - 30, y: 3, width: 20, height: 20)
            currentY -= 28
            
            for item in category.items {
                if category.isCollapsed && item.id != selectedSidebarItemId {
                    item.row.isHidden = true
                } else {
                    item.row.isHidden = false
                    item.row.frame = NSRect(x: 0, y: currentY, width: sidebarWidth, height: 28)
                    item.leftBar.frame = NSRect(x: 0, y: 0, width: 3, height: 28)
                    item.label.frame = NSRect(x: 38, y: 5, width: sidebarWidth - 64, height: 18)
                    item.hoverCloseView?.frame = NSRect(x: sidebarWidth - 24, y: 8, width: 12, height: 12)
                    currentY -= 28
                }
            }
            currentY -= 10
        }
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
            guard let self = self else { return }
            self.isChannelFavorited.toggle()
            let symbol = self.isChannelFavorited ? "star.fill" : "star"
            if let img = NSImage(systemSymbolName: symbol, accessibilityDescription: "Favorite") {
                self.channelStarIconView.image = img.withSymbolConfiguration(.init(pointSize: 12.5, weight: .medium))
            }
            self.channelStarIconView.contentTintColor = self.isChannelFavorited ? starGold : (self.channelStarButton.isHovered ? darkText : mutedText)
        }
        chatPanel.addSubview(channelStarButton)
        
        channelTitleButton.cornerRadius = 4
        channelTitleButton.color = .clear
        channelTitleLabel.font = NSFont.systemFont(ofSize: 14, weight: .bold)
        channelTitleLabel.textColor = darkText
        channelTitleLabel.isEditable = false
        channelTitleLabel.isSelectable = false
        channelTitleButton.addSubview(channelTitleLabel)
        
        channelHeaderBotBadge.cornerRadius = 4
        channelHeaderBotBadge.color = NSColor(red: 63 / 255, green: 67 / 255, blue: 80 / 255, alpha: 0.12)
        channelHeaderBotBadgeLabel.font = NSFont.systemFont(ofSize: 9.5, weight: .bold)
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
        chatPanel.addSubview(channelTitleButton)
        
        channelMembersButton.cornerRadius = 4
        channelMembersButton.color = .clear
        if let personImg = NSImage(systemSymbolName: "person", accessibilityDescription: "Members") {
            channelMembersIconView.image = personImg.withSymbolConfiguration(.init(pointSize: 11, weight: .medium))
            channelMembersIconView.contentTintColor = mutedText
        }
        channelMembersCountLabel.font = NSFont.systemFont(ofSize: 11.5, weight: .semibold)
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
        chatPanel.addSubview(channelPinsButton)
        
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
        
        heroTitleLabel.font = NSFont.systemFont(ofSize: 22, weight: .bold)
        heroTitleLabel.textColor = darkText
        heroTitleLabel.alignment = .center
        heroTitleLabel.isEditable = false
        heroTitleLabel.isSelectable = false
        timelineHeroContainer.addSubview(heroTitleLabel)
        
        heroBotBadge.cornerRadius = 4
        heroBotBadge.color = NSColor(red: 63 / 255, green: 67 / 255, blue: 80 / 255, alpha: 0.12)
        heroBotBadgeLabel.font = NSFont.systemFont(ofSize: 10, weight: .bold)
        heroBotBadgeLabel.textColor = NSColor(red: 63 / 255, green: 67 / 255, blue: 80 / 255, alpha: 0.75)
        heroBotBadgeLabel.alignment = .center
        heroBotBadgeLabel.isEditable = false
        heroBotBadgeLabel.isSelectable = false
        heroBotBadge.addSubview(heroBotBadgeLabel)
        heroBotBadge.isHidden = true
        timelineHeroContainer.addSubview(heroBotBadge)
        
        heroDescriptionLabel.font = NSFont.systemFont(ofSize: 12)
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
        
        heroInviteLabel.font = NSFont.systemFont(ofSize: 12, weight: .semibold)
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
        timelineHeroContainer.addSubview(heroInviteButton)
        
        // 2. Timeline Scroll View & Dynamic Document View
        timelineScrollView.drawsBackground = false
        timelineScrollView.hasVerticalScroller = true
        timelineScrollView.hasHorizontalScroller = false
        timelineScrollView.autohidesScrollers = true
        timelineScrollView.documentView = timelineDocView
        chatTimelineContainer.addSubview(timelineScrollView)
        
        // 4. Message Composer (Non-editable placeholder + Formatting Toolbar + Help link)
        composerPlaceholderLabel.font = NSFont.systemFont(ofSize: 13)
        composerPlaceholderLabel.textColor = lightPlaceholder
        composerPlaceholderLabel.isEditable = false
        composerPlaceholderLabel.isSelectable = false
        chatEntryPanel.addSubview(composerPlaceholderLabel)
        
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
            icon.frame = NSRect(x: 5, y: 5, width: 16, height: 16)
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
        let aaFont = NSFont.systemFont(ofSize: 11.5, weight: .semibold)
        aaLabel.font = aaFont
        aaLabel.textColor = mutedText
        aaLabel.isEditable = false
        aaLabel.isSelectable = false
        let aaSize = ("Aa" as NSString).size(withAttributes: [.font: aaFont])
        let aaTextW = ceil(aaSize.width) + 2
        let aaTextH = ceil(aaSize.height)
        aaLabel.frame = NSRect(x: 6, y: (26 - aaTextH) / 2, width: aaTextW, height: aaTextH)
        composerAaButton.addSubview(aaLabel)
        let aaChev = NSImageView()
        if let cImg = NSImage(systemSymbolName: "chevron.up", accessibilityDescription: "Formatting") {
            aaChev.image = cImg.withSymbolConfiguration(.init(pointSize: 8, weight: .bold))
            aaChev.contentTintColor = mutedText
        }
        aaChev.frame = NSRect(x: 6 + aaTextW + 3, y: (26 - 9) / 2, width: 9, height: 9)
        composerAaButton.addSubview(aaChev)
        composerAaButton.onHoverChanged = { [weak self, weak aaLabel, weak aaChev] isHovered in
            self?.composerAaButton.color = isHovered ? hoverBg : .clear
            self?.composerAaButton.setNeedsAppearanceUpdate()
            aaLabel?.textColor = isHovered ? darkText : mutedText
            aaChev?.contentTintColor = isHovered ? darkText : mutedText
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
                icon.image = img.withSymbolConfiguration(.init(pointSize: 13, weight: .medium))
                icon.contentTintColor = mutedText
            }
            icon.frame = NSRect(x: 5, y: 5, width: 16, height: 16)
            btn.addSubview(icon)
            btn.onHoverChanged = { [weak btn, weak icon] isHovered in
                btn?.color = isHovered ? hoverBg : .clear
                btn?.setNeedsAppearanceUpdate()
                icon?.contentTintColor = isHovered ? darkText : mutedText
            }
            self.chatEntryPanel.addSubview(btn)
        }
        setupRightIconBtn(composerEmojiButton, "face.smiling")
        setupRightIconBtn(composerAttachButton, "paperclip")
        
        composerSendButton.cornerRadius = 4
        composerSendButton.color = hoverBg
        let sendIcon = NSImageView()
        if let sImg = NSImage(systemSymbolName: "paperplane", accessibilityDescription: "Send") {
            sendIcon.image = sImg.withSymbolConfiguration(.init(pointSize: 12, weight: .medium))
            sendIcon.contentTintColor = lightPlaceholder
        }
        sendIcon.frame = NSRect(x: 8, y: 5, width: 16, height: 16)
        composerSendButton.addSubview(sendIcon)
        composerSendButton.onHoverChanged = { [weak self] isHovered in
            self?.composerSendButton.color = isHovered ? dividerColor : hoverBg
            self?.composerSendButton.setNeedsAppearanceUpdate()
        }
        chatEntryPanel.addSubview(composerSendButton)
        
        composerHelpLabel.font = NSFont.systemFont(ofSize: 10.5)
        composerHelpLabel.textColor = mutedText
        composerHelpLabel.alignment = .right
        composerHelpLabel.isEditable = false
        composerHelpLabel.isSelectable = false
        chatPanel.addSubview(composerHelpLabel)
        
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
        
        let titleFont = NSFont.systemFont(ofSize: 22, weight: .bold)
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
            let inviteFont = heroInviteLabel.font ?? NSFont.systemFont(ofSize: 12, weight: .semibold)
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
        let dividerColor = NSColor(red: 229 / 255, green: 231 / 255, blue: 235 / 255, alpha: 1.0)
        let darkText = NSColor(red: 31 / 255, green: 41 / 255, blue: 55 / 255, alpha: 1.0)
        
        let label = NSTextField(labelWithString: dateStr)
        label.font = NSFont.systemFont(ofSize: 11, weight: .bold)
        label.textColor = darkText
        label.alignment = .center
        label.isEditable = false
        label.isSelectable = false
        
        let font = label.font ?? NSFont.systemFont(ofSize: 11, weight: .bold)
        let textSize = (dateStr as NSString).size(withAttributes: [.font: font])
        let textW = ceil(textSize.width) + 20
        let textH = ceil(textSize.height)
        let centerX = width / 2
        let labelX = centerX - textW / 2
        
        let leftLine = RoundedEdgePanel()
        leftLine.cornerRadius = 0
        leftLine.color = dividerColor
        leftLine.frame = NSRect(x: 20, y: 11, width: max(0, labelX - 28), height: 1)
        
        label.frame = NSRect(x: labelX, y: 4, width: textW, height: max(16, textH + 2))
        
        let rightLine = RoundedEdgePanel()
        rightLine.cornerRadius = 0
        rightLine.color = dividerColor
        rightLine.frame = NSRect(x: labelX + textW + 8, y: 11, width: max(0, width - (labelX + textW + 28)), height: 1)
        
        container.addSubview(leftLine)
        container.addSubview(label)
        container.addSubview(rightLine)
        container.frame = NSRect(x: 0, y: 0, width: width, height: 24)
        return container
    }
    
    private func createPostRow(post: MMPost, width: CGFloat, timeStr: String) -> (NSView, CGFloat) {
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

        // Avatar circle
        let avatarCircle = RoundedEdgePanel()
        avatarCircle.frame = NSRect(x: 20, y: 8, width: 28, height: 28)
        avatarCircle.cornerRadius = 14
        
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
            avatarImgView.frame = NSRect(x: 0, y: 0, width: 28, height: 28)
            avatarCircle.addSubview(avatarImgView)
        } else if isSystem {
            avatarCircle.color = .white
            let sysAvatarIcon = NSImageView()
            if let compass = makeMattermostCompassIcon() {
                sysAvatarIcon.image = compass
                sysAvatarIcon.contentTintColor = darkText
            }
            sysAvatarIcon.frame = NSRect(x: 3, y: 3, width: 22, height: 22)
            avatarCircle.addSubview(sysAvatarIcon)
        } else {
            let palette: [NSColor] = [
                NSColor(red: 156 / 255, green: 171 / 255, blue: 36 / 255, alpha: 1.0),
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
            initialLabel.font = NSFont.systemFont(ofSize: 13, weight: .semibold)
            initialLabel.textColor = .white
            initialLabel.alignment = .center
            initialLabel.isEditable = false
            initialLabel.isSelectable = false
            initialLabel.frame = NSRect(x: 0, y: 5, width: 28, height: 18)
            avatarCircle.addSubview(initialLabel)
        }
        row.addSubview(avatarCircle)
        
        let isCurrentUser = (post.user_id == currentUser?.id) || (!authorName.isEmpty && authorName == currentUser?.username)
        if isCurrentUser && !isSystem && !isBotUser {
            let usrDot = RoundedEdgePanel()
            usrDot.frame = NSRect(x: 38, y: 26, width: 10, height: 10)
            usrDot.cornerRadius = 5
            usrDot.color = NSColor(red: 61 / 255, green: 184 / 255, blue: 135 / 255, alpha: 1.0)
            usrDot.borderWidth = 1.5
            usrDot.borderColor = .white
            row.addSubview(usrDot)
        }
        
        // Author label
        let authorLabel = NSTextField(labelWithString: authorName)
        let authorFont = NSFont.systemFont(ofSize: 13, weight: .bold)
        authorLabel.font = authorFont
        authorLabel.textColor = darkText
        authorLabel.isEditable = false
        authorLabel.isSelectable = false
        let authorSize = (authorName as NSString).size(withAttributes: [.font: authorFont])
        let authorW = ceil(authorSize.width) + 4
        let authorH = max(17, ceil(authorSize.height))
        authorLabel.frame = NSRect(x: 58, y: 8, width: authorW, height: authorH)
        row.addSubview(authorLabel)
        
        var headerRightX = authorLabel.frame.maxX + 8
        if isBotUser {
            let botBadge = createBotBadge()
            botBadge.frame = NSRect(x: authorLabel.frame.maxX + 4, y: 9, width: 32, height: 16)
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
            statusPromptLabel.font = NSFont.systemFont(ofSize: 10, weight: .medium)
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
            statusPromptPill.frame = NSRect(x: headerRightX, y: 7, width: pillW, height: pillH)
            statusPromptIcon.frame = NSRect(x: pillPadH, y: (pillH - iconSize) / 2, width: iconSize, height: iconSize)
            statusPromptLabel.frame = NSRect(x: pillPadH + iconSize + iconSpacing, y: (pillH - promptTextH) / 2, width: promptTextW, height: promptTextH)
            statusPromptPill.addSubview(statusPromptIcon)
            statusPromptPill.addSubview(statusPromptLabel)
            statusPromptPill.onHoverChanged = { [weak statusPromptPill] isHovered in
                statusPromptPill?.color = isHovered ? dividerColor : hoverBg
                statusPromptPill?.setNeedsAppearanceUpdate()
            }
            row.addSubview(statusPromptPill)
            headerRightX = statusPromptPill.frame.maxX + 8
        }
        
        // Timestamp label
        let timeLabel = NSTextField(labelWithString: timeStr)
        let timeFont = NSFont.systemFont(ofSize: 10.5)
        timeLabel.font = timeFont
        timeLabel.textColor = lightPlaceholder
        timeLabel.isEditable = false
        timeLabel.isSelectable = false
        let timeSize = (timeStr as NSString).size(withAttributes: [.font: timeFont])
        let timeW = ceil(timeSize.width) + 4
        timeLabel.frame = NSRect(x: headerRightX, y: 10, width: timeW, height: max(15, ceil(timeSize.height)))
        row.addSubview(timeLabel)
        
        // Body label
        let bodyText = post.message.isEmpty ? (isSystem ? "System update" : "") : post.message
        let bodyFont = NSFont.systemFont(ofSize: 13)
        let bodyMaxW = max(100, width - 58 - 30)
        
        let textStorage = NSTextStorage(string: bodyText, attributes: [.font: bodyFont])
        let textContainer = NSTextContainer(containerSize: NSSize(width: bodyMaxW, height: .greatestFiniteMagnitude))
        textContainer.lineFragmentPadding = 0
        let layoutManager = NSLayoutManager()
        layoutManager.addTextContainer(textContainer)
        textStorage.addLayoutManager(layoutManager)
        layoutManager.glyphRange(for: textContainer)
        let usedRect = layoutManager.usedRect(for: textContainer)
        let bodyH = max(18, ceil(usedRect.height))
        
        let bodyLabel = NSTextField()
        bodyLabel.isEditable = false
        bodyLabel.isSelectable = true
        bodyLabel.drawsBackground = false
        bodyLabel.isBezeled = false
        bodyLabel.font = bodyFont
        bodyLabel.textColor = isSystem ? mutedText : darkText
        bodyLabel.stringValue = bodyText
        bodyLabel.lineBreakMode = .byWordWrapping
        bodyLabel.cell?.isScrollable = false
        bodyLabel.cell?.wraps = true
        bodyLabel.frame = NSRect(x: 58, y: 28, width: bodyMaxW, height: bodyH)
        row.addSubview(bodyLabel)
        
        let totalRowH = max(48, 28 + bodyH + 8)
        row.frame = NSRect(x: 0, y: 0, width: width, height: totalRowH)
        
        row.onHoverChanged = { [weak row] isHovered in
            row?.color = isHovered ? msgHoverBg : .clear
            row?.setNeedsAppearanceUpdate()
        }
        return (row, totalRowH)
    }
    
    private func createBotBadge() -> RoundedEdgePanel {
        let badge = RoundedEdgePanel()
        badge.cornerRadius = 4
        badge.color = NSColor(red: 63 / 255, green: 67 / 255, blue: 80 / 255, alpha: 0.12)
        let label = NSTextField(labelWithString: "BOT")
        label.font = NSFont.systemFont(ofSize: 9.5, weight: .bold)
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
        let headerH: CGFloat = 48
        let headerY = chatH - headerH
        let scrollH = max(0, headerY - 114)
        timelineScrollView.frame = NSRect(x: 0, y: 114, width: chatW, height: scrollH)
        
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
        let dateFmt = DateFormatter()
        dateFmt.locale = Locale(identifier: "en_US_POSIX")
        dateFmt.dateFormat = "MMMM dd, yyyy"
        
        let timeFmt = DateFormatter()
        timeFmt.locale = Locale(identifier: "en_US_POSIX")
        timeFmt.dateFormat = "h:mm a"
        
        var postsToRender = currentChannelPosts
        if postsToRender.isEmpty && !((NSApp.delegate as? AppDelegate)?.webService.isLogged() ?? false) {
            let nowMs = Int64(Date().timeIntervalSince1970 * 1000)
            postsToRender = [
                MMPost(
                    id: "sample_sys",
                    create_at: nowMs - 86400000 * 10,
                    update_at: nil, edit_at: nil, delete_at: nil, is_pinned: false,
                    user_id: "system", channel_id: activeChannelId, root_id: nil, original_id: nil,
                    message: "You joined the team.", type: "system_join_channel"
                ),
                MMPost(
                    id: "sample_usr",
                    create_at: nowMs,
                    update_at: nil, edit_at: nil, delete_at: nil, is_pinned: false,
                    user_id: currentUser?.id ?? "usr", channel_id: activeChannelId, root_id: nil, original_id: nil,
                    message: "ok", type: nil
                )
            ]
        }
        
        var lastDateStr: String? = nil
        for post in postsToRender {
            let postDate = Date(timeIntervalSince1970: TimeInterval(post.create_at) / 1000.0)
            let dateStr = dateFmt.string(from: postDate)
            if dateStr != lastDateStr {
                lastDateStr = dateStr
                let sepView = createDateSeparator(dateStr: dateStr, width: chatW)
                sepView.frame.origin.y = currentY
                timelineDocView.addSubview(sepView)
                currentY += 24 + 10
            }
            
            let (rowView, rowH) = createPostRow(post: post, width: chatW, timeStr: timeFmt.string(from: postDate))
            rowView.frame.origin.y = currentY
            timelineDocView.addSubview(rowView)
            currentY += rowH + 4
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
        let headerH: CGFloat = 48
        let headerY = chatH - headerH
        
        chatTimelineContainer.frame = NSRect(x: 0, y: 0, width: chatW, height: headerY)
        
        // 1. Channel Header Bar
        channelHeaderBorder.frame = NSRect(x: 0, y: headerY, width: chatW, height: 1)
        channelStarButton.frame = NSRect(x: 16, y: headerY + 12, width: 24, height: 24)
        channelStarIconView.frame = NSRect(x: 4, y: 4, width: 16, height: 16)
        
        let isBot = isCurrentChannelBot()
        channelHeaderBotBadge.isHidden = !isBot
        
        let titleFont = channelTitleLabel.font ?? NSFont.systemFont(ofSize: 14, weight: .bold)
        let titleStr = channelTitleLabel.stringValue.isEmpty ? "Town Square" : channelTitleLabel.stringValue
        let titleSize = (titleStr as NSString).size(withAttributes: [.font: titleFont])
        let titleTextW = min(max(ceil(titleSize.width) + 4, 40), max(chatW - 240, 100))
        let titleTextH = ceil(titleSize.height)
        
        let botBadgeW: CGFloat = isBot ? 32 : 0
        let botBadgeSpacing: CGFloat = isBot ? 6 : 0
        let titleBtnW = titleTextW + botBadgeSpacing + botBadgeW + 28
        let titleBtnH: CGFloat = max(28, titleTextH + 8)
        channelTitleButton.frame = NSRect(x: 42, y: headerY + (headerH - titleBtnH) / 2, width: titleBtnW, height: titleBtnH)
        channelTitleLabel.frame = NSRect(x: 8, y: (titleBtnH - titleTextH) / 2, width: titleTextW, height: titleTextH)
        if isBot {
            channelHeaderBotBadge.frame = NSRect(x: 8 + titleTextW + 4, y: (titleBtnH - 16) / 2, width: 32, height: 16)
            channelHeaderBotBadgeLabel.frame = NSRect(x: 0, y: 1, width: 32, height: 14)
        }
        channelTitleChevron.frame = NSRect(x: 8 + titleTextW + 4 + (isBot ? (botBadgeW + botBadgeSpacing) : 0), y: (titleBtnH - 10) / 2, width: 10, height: 10)
        
        let membersX = channelTitleButton.frame.maxX + 8
        let countFont = channelMembersCountLabel.font ?? NSFont.systemFont(ofSize: 11.5, weight: .semibold)
        let countStr = channelMembersCountLabel.stringValue.isEmpty ? "1" : channelMembersCountLabel.stringValue
        let countSize = (countStr as NSString).size(withAttributes: [.font: countFont])
        let countTextW = ceil(countSize.width) + 4
        let countTextH = ceil(countSize.height)
        let countBtnW = 6 + 13 + 4 + countTextW + 6
        let countBtnH: CGFloat = 24
        channelMembersButton.frame = NSRect(x: membersX, y: headerY + (headerH - countBtnH) / 2, width: max(34, countBtnW), height: countBtnH)
        channelMembersIconView.frame = NSRect(x: 6, y: (countBtnH - 13) / 2, width: 13, height: 13)
        channelMembersCountLabel.frame = NSRect(x: 23, y: (countBtnH - countTextH) / 2, width: countTextW, height: countTextH)
        
        channelPinsButton.frame = NSRect(x: channelMembersButton.frame.maxX + 8, y: headerY + 12, width: 24, height: 24)
        channelPinsIconView.frame = NSRect(x: 5, y: 5, width: 14, height: 14)
        
        channelInfoButton.frame = NSRect(x: chatW - 42, y: headerY + 10, width: 28, height: 28)
        channelInfoIconView.frame = NSRect(x: 5, y: 5, width: 18, height: 18)
        
        // 2. Composer at bottom
        let composerW = max(chatW - 40, 200)
        chatEntryPanel.frame = NSRect(x: 20, y: 24, width: composerW, height: 86)
        entryView.frame = NSRect(x: 12, y: 44, width: composerW - 24, height: 32)
        composerPlaceholderLabel.frame = NSRect(x: 16, y: 50, width: composerW - 32, height: 20)
        composerHelpLabel.frame = NSRect(x: chatW - 60, y: 6, width: 40, height: 14)
        
        var btnX: CGFloat = 10
        for (i, btn) in composerLeftButtons.enumerated() {
            if i == 3 {
                composerLeftSeparator.frame = NSRect(x: btnX + 3, y: 13, width: 1, height: 16)
                btnX += 9
            }
            btn.frame = NSRect(x: btnX, y: 8, width: 26, height: 26)
            btnX += 28
        }
        
        composerSendButton.frame = NSRect(x: composerW - 42, y: 8, width: 32, height: 26)
        composerAttachButton.frame = NSRect(x: composerW - 72, y: 8, width: 26, height: 26)
        composerEmojiButton.frame = NSRect(x: composerW - 100, y: 8, width: 26, height: 26)
        composerRightSeparator.frame = NSRect(x: composerW - 106, y: 13, width: 1, height: 16)
        
        let aaText = "Aa"
        let aaFont = composerAaButton.subviews.compactMap { ($0 as? NSTextField)?.font }.first ?? NSFont.systemFont(ofSize: 11.5, weight: .semibold)
        let aaSize = (aaText as NSString).size(withAttributes: [.font: aaFont])
        let aaBtnW = ceil(aaSize.width) + 24
        composerAaButton.frame = NSRect(x: composerW - (aaBtnW + 110), y: 8, width: aaBtnW, height: 26)
        
        // 3. Scrollable Timeline
        let scrollH = max(0, headerY - 114)
        timelineScrollView.frame = NSRect(x: 0, y: 114, width: chatW, height: scrollH)
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
    }
    
    func updateViews() {
        let size = contentView!.bounds.size
        let topBarHeight: CGFloat = 40
        let topBarY = size.height - topBarHeight
        
        mainPanel.frame = NSRect(x: 0, y: 0, width: size.width, height: topBarY)
        sidebarTopBorder.frame = NSRect(x: 0, y: topBarY - 1, width: 206, height: 1)
        chatPanel.frame = NSRect(x: 206, y: 0, width: size.width - 206, height: topBarY)
        
        treeView.frame = NSRect(x: 0, y: 0, width: 206, height: topBarY - 1)
        layoutLeftSidebar(topBarY: topBarY)
        layoutRightChatPanel()

        // Left: Product switcher container (grid icon, Mattermost logo, TEAM EDITION badge)
        let badgeText = editionBadgeLabel.stringValue.isEmpty ? "TEAM EDITION" : editionBadgeLabel.stringValue
        let badgeFont = editionBadgeLabel.font ?? NSFont.systemFont(ofSize: 7.5, weight: .bold)
        let badgeSize = (badgeText as NSString).size(withAttributes: [.font: badgeFont])
        let badgePadH: CGFloat = 7
        let badgeW = ceil(badgeSize.width) + (badgePadH * 2)
        let badgeH: CGFloat = 16
        let labelH: CGFloat = 13
        
        boxImage.frame = NSRect(x: 6, y: 5, width: 18, height: 18)
        logo.frame = NSRect(x: 28, y: 6.5, width: 92, height: 15)
        
        let badgeX = logo.frame.maxX + 6
        let badgeY = (28 - badgeH) / 2
        editionBadgePanel.frame = NSRect(x: badgeX, y: badgeY, width: badgeW, height: badgeH)
        editionBadgeLabel.frame = NSRect(x: 0, y: (badgeH - labelH) / 2, width: badgeW, height: labelH)
        
        let switcherW = badgeX + badgeW + 8
        productSwitcherPanel.frame = NSRect(x: 8, y: topBarY + 6, width: switcherW, height: 28)
        productSwitcherMenu.frame = NSRect(x: 12, y: topBarY - 302, width: 220, height: 300)
        
        // Center: Search bar + Help (?) button + Search Popover
        let searchWidth = min(max(size.width * 0.34, 240), 440)
        let minSearchX: CGFloat = productSwitcherPanel.frame.maxX + 12
        let idealSearchX = (size.width - searchWidth) / 2
        let searchX = max(minSearchX, idealSearchX)
        searchPanel.frame = NSRect(x: searchX, y: topBarY + 7, width: searchWidth, height: 26)
        searchIconView.frame = NSRect(x: 8, y: 5, width: 16, height: 16)
        searchLabel.frame = NSRect(x: 28, y: 4, width: searchWidth - 36, height: 18)
        
        helpPanel.frame = NSRect(x: searchX + searchWidth + 4, y: topBarY + 6, width: 28, height: 28)
        helpIconView.frame = NSRect(x: 4, y: 4, width: 20, height: 20)
        helpMenu.frame = NSRect(x: helpPanel.frame.minX, y: topBarY - 178, width: 204, height: 176)
        
        searchPopoverPanel.frame = NSRect(x: searchX, y: topBarY - 124, width: 400, height: 122)
        
        // Right: Mentions (@), Saved Posts, Settings, User Avatar + Status Dot
        avatarButtonPanel.frame = NSRect(x: size.width - 41, y: topBarY + 5, width: 30, height: 30)
        avatarPanel.frame = NSRect(x: 3, y: 3, width: 24, height: 24)
        avatarLabel.frame = NSRect(x: 0, y: 4, width: 24, height: 16)
        statusDotPanel.frame = NSRect(x: 20, y: 1, width: 9, height: 9)
        statusMenu.frame = NSRect(x: size.width - 259, y: topBarY - 356, width: 248, height: 354)
        dndSubMenu.frame = NSRect(x: statusMenu.frame.minX - 210, y: statusMenu.frame.minY - 50, width: 212, height: 232)
        
        settingsPanel.frame = NSRect(x: size.width - 74, y: topBarY + 6, width: 28, height: 28)
        settingsIconView.frame = NSRect(x: 4, y: 4, width: 20, height: 20)
        
        savedPostsPanel.frame = NSRect(x: size.width - 106, y: topBarY + 6, width: 28, height: 28)
        savedPostsIconView.frame = NSRect(x: 4, y: 4, width: 20, height: 20)
        
        mentionsPanel.frame = NSRect(x: size.width - 138, y: topBarY + 6, width: 28, height: 28)
        mentionsIconView.frame = NSRect(x: 4, y: 4, width: 20, height: 20)
    }
    
    // MARK: - Live REST API & WebSocket Integration
    
    private func bindWebServiceAndLoadData() {
        guard let ws = (NSApp.delegate as? AppDelegate)?.webService else { return }
        
        ws.onPostReceived = { [weak self] post, _ in
            guard let self = self else { return }
            guard post.channel_id == self.activeChannelId else { return }
            Task { @MainActor [weak self] in
                await self?.fetchAndRenderPosts(channelId: post.channel_id)
            }
        }
        
        ws.onStatusChanged = { [weak self] userId, status in
            guard let self = self else { return }
            if let myId = self.currentUser?.id, myId == userId {
                switch status {
                case "online":
                    self.selectUserStatus(0)
                case "away":
                    self.selectUserStatus(1)
                case "dnd":
                    self.selectUserStatus(2)
                case "offline":
                    self.selectUserStatus(3)
                default:
                    break
                }
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
        
        guard ws.isLogged() else { return }
        
        Task { @MainActor [weak self] in
            guard let self = self else { return }
            do {
                let me = try await ws.fetchCurrentUser()
                self.currentUser = me
                self.usersById[me.id] = me
                self.usersByUsername[me.username.lowercased()] = me
                self.fetchAvatarIfNeeded(for: me.id)
                
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
        let resolvedTitle = channelDisplayName(for: ch)
        channelTitleLabel.stringValue = resolvedTitle
        heroTitleLabel.stringValue = resolvedTitle
        composerPlaceholderLabel.stringValue = "Write to \(resolvedTitle)"
        if ch.type == "D" {
            heroDescriptionLabel.stringValue = "This is the start of your direct message history with \(resolvedTitle). Messages and files shared here are not shown to people outside this conversation."
        } else {
            heroDescriptionLabel.stringValue = "Welcome to \(resolvedTitle). Post messages here that you want everyone to see. Everyone\nautomatically becomes a member of this channel when they join the team."
        }
        layoutRightChatPanel()
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
    
    @MainActor
    private func appendRealtimePost(_ post: MMPost, senderName: String?) {
        guard post.channel_id == activeChannelId else { return }
        Task { @MainActor [weak self] in
            await self?.fetchAndRenderPosts(channelId: post.channel_id)
        }
    }
    
    func sendActiveChannelPost(message: String) {
        let trimmed = message.trimmingCharacters(in: .whitespacesAndNewlines)
        guard !trimmed.isEmpty, !activeChannelId.isEmpty else { return }
        let channelId = activeChannelId
        Task { @MainActor in
            guard let ws = (NSApp.delegate as? AppDelegate)?.webService else { return }
            do {
                _ = try await ws.createPost(channelId: channelId, message: trimmed)
                await self.fetchAndRenderPosts(channelId: channelId)
            } catch {
                NSLog("Failed to send post: \(error.localizedDescription)")
            }
        }
    }
}
