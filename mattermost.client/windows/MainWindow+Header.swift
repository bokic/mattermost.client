//
//  MainWindow+Header.swift
//  mattermost.client
//
//  Split from MainWindow.swift.
//

import AppKit
import Foundation
import UniformTypeIdentifiers

extension MainWindow {

    func setupTopGlobalBar() {
        // Web client: header icons/text sit at 56% white, the search field at 64%.
        let topBarTint = Theme.shared.sidebarText.withAlphaComponent(0.56)
        let searchTint = Theme.shared.sidebarText.withAlphaComponent(0.64)
        let hoverBg = Theme.shared.sidebarText.withAlphaComponent(0.08)

        // Left: Product switcher container (grid icon + Mattermost logo + TEAM EDITION badge)
        productSwitcherPanel.color = .clear
        productSwitcherPanel.cornerRadius = MMRadius.control

        boxImage.imageScaling = .scaleProportionallyUpOrDown
        boxImage.alphaValue = 0.72
        logo.imageScaling = .scaleProportionallyUpOrDown
        logo.alphaValue = 0.94

        editionBadgePanel.color = Theme.shared.sidebarText.withAlphaComponent(0.08)
        editionBadgePanel.cornerRadius = MMRadius.control
        editionBadgeLabel.font = MMFont.font(ofSize: 10, weight: .semibold)
        editionBadgeLabel.textColor = Theme.shared.sidebarText.withAlphaComponent(0.75)
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
        searchPanel.color = Theme.shared.sidebarText.withAlphaComponent(0.08)
        searchPanel.cornerRadius = MMRadius.control
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
            self.searchPanel.color = Theme.shared.sidebarText.withAlphaComponent(isHovered ? 0.12 : 0.08)
            self.searchPanel.setNeedsAppearanceUpdate()
            self.searchIconView.contentTintColor = isHovered ? Theme.shared.sidebarText : searchTint
            self.searchLabel.textColor = isHovered ? Theme.shared.sidebarText : searchTint
        }
        searchPanel.onClick = { [weak self] in
            self?.toggleSearchPopover()
        }
        contentView?.addSubview(searchPanel)

        helpPanel.color = .clear
        helpPanel.cornerRadius = MMRadius.control
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
        avatarButtonPanel.cornerRadius = MMRadius.control
        // The status badge intentionally overhangs the avatar's bottom-right corner,
        // so let it render outside the rounded hover container.
        avatarButtonPanel.clipContentToBounds = false

        let initial = (UserDefaults.standard.string(forKey: "username")?.first).map { String($0).uppercased() } ?? "B"
        avatarLabel.stringValue = initial
        avatarLabel.font = MMFont.font(ofSize: 10, weight: .semibold)
        avatarLabel.textColor = .white
        avatarLabel.alignment = .center

        avatarPanel.color = MMPalette.avatarYellow
        avatarPanel.cornerRadius = MMRadius.window
        avatarPanel.addSubview(avatarLabel)

        avatarImageView.imageScaling = .scaleProportionallyUpOrDown
        avatarImageView.frame = NSRect(x: 0, y: 0, width: MMMetric.avatarSmall, height: MMMetric.avatarSmall)
        avatarImageView.isHidden = true
        avatarPanel.addSubview(avatarImageView)

        statusDotPanel.color = statusColor(for: currentUserStatus)
        statusDotPanel.cornerRadius = MMRadius.panel
        statusDotPanel.borderWidth = 1.35
        statusDotPanel.borderColor = Theme.shared.sidebarTeamBarBg

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

    func updateProductSwitcherAppearance() {
        let active = productSwitcherPanel.isHovered || isProductMenuOpen
        let hoverBg = Theme.shared.sidebarText.withAlphaComponent(0.08)
        productSwitcherPanel.color = active ? hoverBg : .clear
        productSwitcherPanel.setNeedsAppearanceUpdate()
        boxImage.alphaValue = active ? 1.0 : 0.72
        logo.alphaValue = active ? 1.0 : 0.94
        editionBadgePanel.color = Theme.shared.sidebarText.withAlphaComponent(active ? 0.16 : 0.12)
        editionBadgePanel.setNeedsAppearanceUpdate()
        editionBadgeLabel.textColor = active ? Theme.shared.sidebarText : Theme.shared.sidebarText.withAlphaComponent(0.72)
    }

    func updateHelpButtonAppearance() {
        let active = helpPanel.isHovered || isHelpMenuOpen
        let topBarTint = Theme.shared.sidebarText.withAlphaComponent(0.64)
        let activeBg = Theme.shared.sidebarText.withAlphaComponent(isHelpMenuOpen ? 0.12 : 0.08)
        helpPanel.color = active ? activeBg : .clear
        helpPanel.setNeedsAppearanceUpdate()
        helpIconView.contentTintColor = active ? Theme.shared.sidebarText : topBarTint
    }

    func updateAvatarButtonAppearance() {
        let active = avatarButtonPanel.isHovered || isStatusMenuOpen
        avatarButtonPanel.color = active ? Theme.shared.sidebarText.withAlphaComponent(0.14) : .clear
        avatarButtonPanel.setNeedsAppearanceUpdate()
    }

    func toggleSearchPopover() {
        if !isSearchPopoverOpen {
            setTeamMenuOpen(false)
            setProductSwitcherMenuOpen(false)
            setHelpMenuOpen(false)
            setStatusMenuOpen(false)
        }
        setSearchPopoverOpen(!isSearchPopoverOpen)
    }

    func setSearchPopoverOpen(_ open: Bool) {
        guard isSearchPopoverOpen != open else { return }
        isSearchPopoverOpen = open
        searchPopoverPanel.isHidden = !open
        if open {
            makeFirstResponder(searchPopoverInputLabel)
            showRecentSearchesIfNeeded()
        } else {
            hideRecentSearches()
        }
    }

    func setupSearchResultsPanel() {
        let dividerColor = Theme.shared.divider
        searchResultsPanel.color = Theme.shared.centerBg
        searchResultsPanel.cornerRadius = MMRadius.card
        searchResultsPanel.borderWidth = 1
        searchResultsPanel.borderColor = dividerColor
        searchResultsPanel.shadowColor = .black
        searchResultsPanel.shadowOpacity = 0.18
        searchResultsPanel.shadowRadius = 16
        searchResultsPanel.shadowOffset = CGSize(width: 0, height: -6)
        searchResultsPanel.isHidden = true

        searchResultsTitle.font = MMFont.font(ofSize: 13, weight: .semibold)
        searchResultsTitle.textColor = Theme.shared.centerText
        searchResultsTitle.isEditable = false
        searchResultsTitle.isSelectable = false
        searchResultsPanel.addSubview(searchResultsTitle)

        searchResultsCloseButton.cornerRadius = MMRadius.control
        searchResultsCloseButton.color = .clear
        let closeIcon = NSImageView()
        if let img = NSImage(systemSymbolName: "xmark", accessibilityDescription: "Close search") {
            closeIcon.image = img.withSymbolConfiguration(.init(pointSize: 10, weight: .semibold))
            closeIcon.contentTintColor = Theme.shared.centerTextMuted
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
        searchResultsScroll.contentView.postsBoundsChangedNotifications = true
        NotificationCenter.default.addObserver(
            self,
            selector: #selector(searchResultsDidScroll),
            name: NSView.boundsDidChangeNotification,
            object: searchResultsScroll.contentView
        )
        searchResultsPanel.addSubview(searchResultsScroll)

        contentView?.addSubview(searchResultsPanel)
    }

    @objc func performSearchFromPopover() {
        let terms = searchPopoverInputLabel.stringValue.trimmingCharacters(in: .whitespacesAndNewlines)
        guard !terms.isEmpty, activeTeam != nil else { return }
        setSearchPopoverOpen(false)
        startSearch(terms: terms)
    }

    func rerunSearchForActiveTab() {
        guard !searchResultsAreRecents,
              !searchResultsPanel.isHidden,
              !searchResultsTerms.isEmpty
        else { return }
        startSearch(terms: searchResultsTerms)
    }

    func recordRecentSearch(_ terms: String) {
        let trimmed = terms.trimmingCharacters(in: .whitespacesAndNewlines)
        guard !trimmed.isEmpty else { return }
        recentSearches.removeAll { $0.caseInsensitiveCompare(trimmed) == .orderedSame }
        recentSearches.insert(trimmed, at: 0)
        if recentSearches.count > 8 {
            recentSearches.removeLast(recentSearches.count - 8)
        }
        UserDefaults.standard.set(recentSearches, forKey: "recentSearches")
    }

    func showRecentSearchesIfNeeded() {
        let query = searchPopoverInputLabel.stringValue.trimmingCharacters(in: .whitespacesAndNewlines)
        guard isSearchPopoverOpen, query.isEmpty, !recentSearches.isEmpty else {
            hideRecentSearches()
            return
        }
        searchResultsAreRecents = true
        searchRequestToken += 1
        searchResultsLoading = false
        searchResultsHasMore = false
        searchResultsSelectionIndex = -1
        searchResultRowViews = []
        searchResultPosts = []
        searchResultFiles = []
        searchResultsTitle.stringValue = "Recent searches"
        searchResultsDoc.subviews.forEach { $0.removeFromSuperview() }

        let width = searchResultsPanel.bounds.width
        let inset: CGFloat = 8
        var y: CGFloat = 0
        for (index, term) in recentSearches.enumerated() {
            let row = makeRecentSearchRow(term, width: width - inset * 2, index: index)
            row.frame = NSRect(x: inset, y: y + 2, width: width - inset * 2, height: 34)
            searchResultsDoc.addSubview(row)
            searchResultRowViews.append(row)
            y += 38
        }
        searchResultsDoc.frame = NSRect(x: 0, y: 0, width: width, height: max(y, 1))
        searchResultsScroll.frame = NSRect(
            x: 0,
            y: 0,
            width: width,
            height: max(0, searchResultsPanel.bounds.height - 44)
        )
        searchResultsPanel.isHidden = false
    }

    func hideRecentSearches() {
        guard searchResultsAreRecents else { return }
        searchResultsAreRecents = false
        searchRequestToken += 1
        searchResultsPanel.isHidden = true
        searchResultRowViews = []
        searchResultsDoc.subviews.forEach { $0.removeFromSuperview() }
    }

    func makeRecentSearchRow(_ term: String, width: CGFloat, index: Int) -> RoundedEdgePanel {
        let row = RoundedEdgePanel()
        row.color = .clear
        row.cornerRadius = MMRadius.menu

        let icon = NSImageView()
        if let image = NSImage(systemSymbolName: "clock.arrow.circlepath", accessibilityDescription: "Recent search") {
            icon.image = image.withSymbolConfiguration(.init(pointSize: 12, weight: .regular))
            icon.contentTintColor = Theme.shared.centerTextMuted
        }
        icon.frame = NSRect(x: 10, y: 9, width: 16, height: 16)
        row.addSubview(icon)

        let label = NSTextField(labelWithString: term)
        label.font = MMFont.font(ofSize: 13)
        label.textColor = Theme.shared.centerText
        label.lineBreakMode = .byTruncatingTail
        label.isEditable = false
        label.isSelectable = false
        label.frame = NSRect(x: 36, y: 8, width: max(60, width - 48), height: 18)
        row.addSubview(label)

        row.onHoverChanged = { [weak self] _ in
            self?.updateSearchSelectionAppearance()
        }
        row.onClick = { [weak self] in
            self?.runRecentSearch(term)
        }
        row.accessibilityTitle = "Recent search: \(term)"
        return row
    }

    func runRecentSearch(_ term: String) {
        searchPopoverInputLabel.stringValue = term
        setSearchPopoverOpen(false)
        startSearch(terms: term)
    }

    func currentSearchResultCount() -> Int {
        if searchResultsAreRecents { return recentSearches.count }
        return searchResultsAreFiles ? searchResultFiles.count : searchResultPosts.count
    }

    func startSearch(terms: String) {
        guard activeTeam != nil else { return }
        recordRecentSearch(terms)
        searchResultsAreRecents = false
        searchRequestToken += 1
        let token = searchRequestToken
        searchResultsTerms = terms
        searchResultsAreFiles = isSearchFilesTabSelected
        searchResultsPage = 0
        searchResultsHasMore = false
        searchResultsLoading = true
        searchResultsSelectionIndex = -1
        searchResultPosts = []
        searchResultFiles = []
        searchResultRowViews = []
        searchResultsTitle.stringValue = "Searching…"
        searchResultsDoc.subviews.forEach { $0.removeFromSuperview() }
        searchResultsDoc.frame = NSRect(x: 0, y: 0, width: searchResultsPanel.bounds.width, height: 1)
        searchResultsPanel.isHidden = false
        makeFirstResponder(chatTimelineContainer)
        loadSearchPage(page: 0, append: false, token: token)
    }

    func loadSearchPage(page: Int, append: Bool, token: Int) {
        guard let team = activeTeam, let ws = webService else { return }
        let terms = searchResultsTerms
        let filesMode = searchResultsAreFiles
        let pageSize = 30
        if append {
            searchResultsLoading = true
            renderSearchResults()
        }

        Task { @MainActor [weak self] in
            guard let self = self else { return }
            do {
                if filesMode {
                    let files = try await ws.searchTeamFiles(
                        teamId: team.id,
                        terms: terms,
                        page: page,
                        perPage: pageSize
                    )
                    guard token == self.searchRequestToken else { return }
                    let userIds = Array(Set(files.compactMap(\.user_id)).subtracting(self.usersById.keys))
                    if !userIds.isEmpty, let users = try? await ws.fetchUsersByIds(userIds) {
                        for user in users { self.usersById[user.id] = user }
                    }
                    guard token == self.searchRequestToken else { return }
                    let existing = Set(append ? self.searchResultFiles.map(\.id) : [])
                    let newFiles = files.filter { !existing.contains($0.id) }
                    self.searchResultFiles = append ? self.searchResultFiles + newFiles : files
                    self.searchResultsPage = page
                    self.searchResultsHasMore = files.count == pageSize
                } else {
                    let list = try await ws.searchPosts(
                        teamId: team.id,
                        terms: terms,
                        page: page,
                        perPage: pageSize
                    )
                    guard token == self.searchRequestToken else { return }
                    let posts = list.order.compactMap { list.posts[$0] }
                    let missingUserIds = Array(Set(posts.map { $0.user_id }).subtracting(self.usersById.keys))
                    if !missingUserIds.isEmpty, let users = try? await ws.fetchUsersByIds(missingUserIds) {
                        for user in users { self.usersById[user.id] = user }
                    }
                    guard token == self.searchRequestToken else { return }
                    let existing = Set(append ? self.searchResultPosts.map(\.id) : [])
                    let newPosts = posts.filter { !existing.contains($0.id) }
                    self.searchResultPosts = append ? self.searchResultPosts + newPosts : posts
                    self.searchResultsPage = page
                    self.searchResultsHasMore = posts.count == pageSize
                }
                self.searchResultsLoading = false
                self.renderSearchResults()
            } catch {
                guard token == self.searchRequestToken else { return }
                self.searchResultsLoading = false
                if append {
                    self.searchResultsHasMore = false
                    self.renderSearchResults()
                    self.searchResultsTitle.stringValue = "Could not load more results"
                } else {
                    self.searchResultPosts = []
                    self.searchResultFiles = []
                    self.renderSearchResults()
                    self.searchResultsTitle.stringValue =
                        "Search failed for “\(self.searchResultsTerms)”"
                }
            }
        }
    }

    func loadNextSearchPage() {
        guard searchResultsHasMore, !searchResultsLoading, !searchResultsTerms.isEmpty else { return }
        loadSearchPage(page: searchResultsPage + 1, append: true, token: searchRequestToken)
    }

    func renderSearchResults() {
        searchResultRowViews.removeAll()
        searchResultsDoc.subviews.forEach { $0.removeFromSuperview() }

        let width = searchResultsPanel.bounds.width
        let rowHeight: CGFloat = 54
        let inset: CGFloat = 8
        var y: CGFloat = 0

        if searchResultsAreFiles {
            for (index, file) in searchResultFiles.enumerated() {
                let row = makeSearchFileResultRow(file, width: width - inset * 2, index: index)
                row.frame = NSRect(x: inset, y: y + 2, width: width - inset * 2, height: rowHeight - 4)
                searchResultsDoc.addSubview(row)
                searchResultRowViews.append(row)
                y += rowHeight
            }
        } else {
            for (index, post) in searchResultPosts.enumerated() {
                let row = makeSearchResultRow(post, width: width - inset * 2, index: index)
                row.frame = NSRect(x: inset, y: y + 2, width: width - inset * 2, height: rowHeight - 4)
                searchResultsDoc.addSubview(row)
                searchResultRowViews.append(row)
                y += rowHeight
            }
        }

        if searchResultsLoading || searchResultsHasMore {
            let footer = makeSearchResultsFooter(width: width - inset * 2)
            footer.frame = NSRect(x: inset, y: y + 2, width: width - inset * 2, height: 30)
            searchResultsDoc.addSubview(footer)
            y += 34
        }

        let count = searchResultsAreFiles ? searchResultFiles.count : searchResultPosts.count
        if count == 0 {
            searchResultsSelectionIndex = -1
        } else if searchResultsSelectionIndex < 0 || searchResultsSelectionIndex >= count {
            searchResultsSelectionIndex = 0
        }

        searchResultsTitle.stringValue = searchResultsTitleText(count: count)
        searchResultsDoc.frame = NSRect(x: 0, y: 0, width: width, height: max(y, 1))
        searchResultsScroll.frame = NSRect(
            x: 0,
            y: 0,
            width: width,
            height: max(0, searchResultsPanel.bounds.height - 44)
        )
        updateSearchSelectionAppearance()
    }

    func searchResultsTitleText(count: Int) -> String {
        if searchResultsLoading && count == 0 {
            return "Searching…"
        }
        if count == 0 {
            return searchResultsAreFiles
                ? "No files for “\(searchResultsTerms)”"
                : "No results for “\(searchResultsTerms)”"
        }
        let suffix = searchResultsHasMore ? "+" : ""
        let noun = searchResultsAreFiles ? "file" : "result"
        let plural = count == 1 ? "" : "s"
        return "\(count)\(suffix) \(noun)\(plural) for “\(searchResultsTerms)”"
    }

    func makeSearchResultsFooter(width: CGFloat) -> RoundedEdgePanel {
        let row = RoundedEdgePanel()
        row.color = .clear
        row.cornerRadius = MMRadius.menu
        let label = NSTextField(
            labelWithString: searchResultsLoading ? "Loading more results…" : "Load more results"
        )
        label.font = MMFont.font(ofSize: 12, weight: .semibold)
        label.textColor = searchResultsLoading ? Theme.shared.centerTextMuted : Theme.shared.buttonBg
        label.alignment = .center
        label.isEditable = false
        label.isSelectable = false
        label.frame = NSRect(x: 8, y: 6, width: max(80, width - 16), height: 18)
        row.addSubview(label)
        if !searchResultsLoading {
            row.onClick = { [weak self] in
                self?.loadNextSearchPage()
            }
            row.onHoverChanged = { [weak row] isHovered in
                row?.color = isHovered ? Theme.shared.centerHover : .clear
                row?.setNeedsAppearanceUpdate()
            }
        }
        row.accessibilityTitle = searchResultsLoading ? "Loading more results" : "Load more results"
        return row
    }

    func updateSearchSelectionAppearance() {
        let selectedBg = Theme.shared.buttonBg.withAlphaComponent(0.12)
        for (index, row) in searchResultRowViews.enumerated() {
            if index == searchResultsSelectionIndex {
                row.color = selectedBg
            } else {
                row.color = row.isHovered ? Theme.shared.centerHover : .clear
            }
            row.setNeedsAppearanceUpdate()
        }
    }

    func moveSearchSelection(by delta: Int) {
        let count = currentSearchResultCount()
        guard count > 0 else { return }
        if searchResultsSelectionIndex < 0 {
            searchResultsSelectionIndex = delta < 0 ? count - 1 : 0
        } else {
            searchResultsSelectionIndex = (searchResultsSelectionIndex + delta + count) % count
        }
        updateSearchSelectionAppearance()
        guard searchResultRowViews.indices.contains(searchResultsSelectionIndex) else { return }
        searchResultsDoc.scrollToVisible(
            searchResultRowViews[searchResultsSelectionIndex].frame.insetBy(dx: 0, dy: -4)
        )
        if searchResultsSelectionIndex == count - 1, searchResultsHasMore, !searchResultsLoading {
            loadNextSearchPage()
        }
    }

    @discardableResult
    func activateSearchSelection() -> Bool {
        let count = currentSearchResultCount()
        guard count > 0 else { return false }
        if searchResultsSelectionIndex < 0 || searchResultsSelectionIndex >= count {
            searchResultsSelectionIndex = 0
        }
        if searchResultsAreRecents {
            guard recentSearches.indices.contains(searchResultsSelectionIndex) else { return false }
            runRecentSearch(recentSearches[searchResultsSelectionIndex])
        } else if searchResultsAreFiles {
            guard searchResultFiles.indices.contains(searchResultsSelectionIndex) else { return false }
            let file = searchResultFiles[searchResultsSelectionIndex]
            closeSearchResults()
            openAttachment(file)
        } else {
            guard searchResultPosts.indices.contains(searchResultsSelectionIndex) else { return false }
            openSearchResult(searchResultPosts[searchResultsSelectionIndex])
        }
        return true
    }

    @objc func searchResultsDidScroll() {
        guard !searchResultsPanel.isHidden,
              searchResultsHasMore,
              !searchResultsLoading
        else { return }
        let clip = searchResultsScroll.contentView.bounds
        if clip.maxY >= searchResultsDoc.frame.height - 120 {
            loadNextSearchPage()
        }
    }

    func makeSearchFileResultRow(_ file: MMFileInfo, width: CGFloat, index: Int) -> RoundedEdgePanel {
        let row = RoundedEdgePanel()
        row.color = .clear
        row.cornerRadius = MMRadius.menu

        let uploader = file.user_id.flatMap { usersById[$0]?.username } ?? "Unknown"
        let channelName = file.channel_id.flatMap { channelsById[$0] }.map { channelDisplayName(for: $0) } ?? ""
        let date = file.create_at.map {
            Self.localizedDateTimeFormatter.string(from: Date(timeIntervalSince1970: TimeInterval($0) / 1000))
        } ?? ""
        let meta = [uploader, channelName, date].filter { !$0.isEmpty }.joined(separator: " · ")

        let icon = NSImageView()
        let isImage = (file.mime_type ?? "").hasPrefix("image/")
        let symbol = isImage ? "photo" : "doc.fill"
        if let image = NSImage(systemSymbolName: symbol, accessibilityDescription: file.name) {
            icon.image = image.withSymbolConfiguration(.init(pointSize: 16, weight: .regular))
            icon.contentTintColor = Theme.shared.centerTextMuted
        }
        icon.frame = NSRect(x: 12, y: 18, width: 20, height: 20)
        row.addSubview(icon)

        let nameLabel = NSTextField(labelWithAttributedString: SearchSupport.attributedSnippet(
            file.name ?? file.id,
            query: searchResultsTerms,
            font: MMFont.font(ofSize: 13, weight: .semibold),
            textColor: Theme.shared.centerText,
            highlightColor: Theme.shared.centerText
        ))
        nameLabel.isEditable = false
        nameLabel.isSelectable = false
        nameLabel.lineBreakMode = .byTruncatingMiddle
        nameLabel.frame = NSRect(x: 42, y: 24, width: max(60, width - 54), height: 18)
        row.addSubview(nameLabel)

        let metaLabel = NSTextField(labelWithString: meta)
        metaLabel.font = MMFont.font(ofSize: 12)
        metaLabel.textColor = Theme.shared.centerTextMuted
        metaLabel.isEditable = false
        metaLabel.isSelectable = false
        metaLabel.lineBreakMode = .byTruncatingTail
        metaLabel.frame = NSRect(x: 42, y: 6, width: max(60, width - 54), height: 16)
        row.addSubview(metaLabel)

        row.onHoverChanged = { [weak self] _ in
            self?.updateSearchSelectionAppearance()
        }
        row.onClick = { [weak self] in
            self?.closeSearchResults()
            self?.openAttachment(file)
        }
        row.accessibilityTitle = file.name ?? file.id
        return row
    }

    func makeSearchResultRow(_ post: MMPost, width: CGFloat, index: Int) -> RoundedEdgePanel {
        let row = RoundedEdgePanel()
        row.color = .clear
        row.cornerRadius = MMRadius.menu

        let author = usersById[post.user_id]?.username ?? "Unknown"
        let channelName = channelsById[post.channel_id].map { channelDisplayName(for: $0) } ?? ""
        let when = Self.localizedDateTimeFormatter.string(
            from: Date(timeIntervalSince1970: TimeInterval(post.create_at) / 1000)
        )

        let authorFont = MMFont.font(ofSize: 12, weight: .semibold)
        let authorSize = (author as NSString).size(withAttributes: [.font: authorFont])
        let authorBtn = RoundedEdgePanel()
        authorBtn.color = .clear
        authorBtn.cornerRadius = MMRadius.control
        let authorBtnW = ceil(authorSize.width) + 4
        authorBtn.frame = NSRect(x: 10, y: 5, width: authorBtnW, height: 18)
        let authorLabel = NSTextField(labelWithString: author)
        authorLabel.font = authorFont
        authorLabel.textColor = Theme.shared.centerTextMuted
        authorLabel.isEditable = false
        authorLabel.isSelectable = false
        authorLabel.frame = NSRect(x: 2, y: 1, width: ceil(authorSize.width), height: 16)
        authorBtn.addSubview(authorLabel)
        if !post.user_id.isEmpty {
            authorBtn.onClick = { [weak self, weak authorBtn] in
                guard let self = self else { return }
                self.showUserProfile(userId: post.user_id, from: authorBtn)
            }
            authorBtn.onHoverChanged = { [weak authorLabel] isHovered in
                authorLabel?.textColor = isHovered ? Theme.shared.buttonBg : Theme.shared.centerTextMuted
            }
        }
        row.addSubview(authorBtn)

        let restMeta = [channelName, when].filter { !$0.isEmpty }.joined(separator: " · ")
        let separator = restMeta.isEmpty ? "" : " · "
        let metaLabel = NSTextField(labelWithString: separator + restMeta)
        metaLabel.font = MMFont.font(ofSize: 12)
        metaLabel.textColor = Theme.shared.centerTextMuted.withAlphaComponent(0.8)
        metaLabel.isEditable = false
        metaLabel.isSelectable = false
        metaLabel.lineBreakMode = .byTruncatingTail
        metaLabel.frame = NSRect(x: authorBtn.frame.maxX, y: 6, width: max(40, width - authorBtn.frame.maxX - 12), height: 16)
        row.addSubview(metaLabel)

        let snippetText = post.message.replacingOccurrences(of: "\n", with: " ")
        let snippet = NSTextField(labelWithAttributedString: SearchSupport.attributedSnippet(
            snippetText,
            query: searchResultsTerms,
            font: MMFont.font(ofSize: 13),
            textColor: Theme.shared.centerText.withAlphaComponent(0.9),
            highlightColor: Theme.shared.centerText
        ))
        snippet.isEditable = false
        snippet.isSelectable = false
        snippet.lineBreakMode = .byTruncatingTail
        snippet.frame = NSRect(x: 12, y: 26, width: width - 24, height: 18)
        row.addSubview(snippet)

        row.onHoverChanged = { [weak self] _ in
            self?.updateSearchSelectionAppearance()
        }
        row.onClick = { [weak self] in
            self?.openSearchResult(post)
        }
        row.accessibilityTitle = snippetText
        return row
    }

    func insertSearchFilter(_ pill: String) {
        guard let insertion = SearchSupport.filterInsertion(
            for: pill,
            channelName: channelsById[activeChannelId]?.name
        ) else { return }
        if !isSearchPopoverOpen {
            setSearchPopoverOpen(true)
        }
        var current = searchPopoverInputLabel.stringValue
        if !current.isEmpty, !current.hasSuffix(" ") {
            current += " "
        }
        let updated = current + insertion
        searchPopoverInputLabel.stringValue = updated
        hideRecentSearches()
        makeFirstResponder(searchPopoverInputLabel)
        DispatchQueue.main.async { [weak self] in
            guard let self = self, let editor = self.searchPopoverInputLabel.currentEditor() else { return }
            editor.selectedRange = NSRange(location: (updated as NSString).length, length: 0)
        }
    }

    func openSearchResult(_ post: MMPost) {
        closeSearchResults()
        guard let channel = channelsById[post.channel_id] else { return }
        pendingJumpPostId = post.id
        selectedSidebarItemId = channel.id
        updateSidebarSelectionAppearance()
        loadChannelPosts(forSidebarItemId: channel.id)
    }

    func closeSearchResults() {
        searchRequestToken += 1
        searchResultsAreRecents = false
        searchResultsLoading = false
        searchResultsHasMore = false
        searchResultsSelectionIndex = -1
        searchResultPosts = []
        searchResultFiles = []
        searchResultRowViews = []
        searchResultsPanel.isHidden = true
        searchResultsDoc.subviews.forEach { $0.removeFromSuperview() }
    }

    func focusGlobalSearch() {
        if !isSearchPopoverOpen {
            setSearchPopoverOpen(true)
        }
        searchPopoverInputLabel.stringValue = ""
        makeFirstResponder(searchPopoverInputLabel)
        showRecentSearchesIfNeeded()
    }

    func focusChannelSearch() {
        guard let channel = channelsById[activeChannelId] else {
            focusGlobalSearch()
            return
        }
        if !isSearchPopoverOpen {
            setSearchPopoverOpen(true)
        }
        let prefix = "in:\(channel.name) "
        searchPopoverInputLabel.stringValue = prefix
        hideRecentSearches()
        makeFirstResponder(searchPopoverInputLabel)
        DispatchQueue.main.async { [weak self] in
            guard let self = self, let editor = self.searchPopoverInputLabel.currentEditor() else { return }
            editor.selectedRange = NSRange(location: (prefix as NSString).length, length: 0)
        }
    }

    func closeTopOverlay() -> Bool {
        if isProfilePopoverOpen { closeProfilePopover(); return true }
        if isCompletionVisible { closeCompletion(); return true }
        if isLightboxVisible { closeLightbox(); return true }
        if isDMPickerOpen { closeDMPicker(); return true }
        if isEmojiPanelOpen { closeEmojiPanel(); return true }
        if isReactionPickerOpen { closeReactionPicker(); return true }
        if isPostActionMenuOpen { closePostActionMenu(); return true }
        if isChannelMenuOpen { closeChannelMenu(); return true }
        if isProductMenuOpen { setProductSwitcherMenuOpen(false); return true }
        if isHelpMenuOpen { setHelpMenuOpen(false); return true }
        if isStatusMenuOpen { setStatusMenuOpen(false); return true }
        if isTeamMenuOpen { setTeamMenuOpen(false); return true }
        if isFilterMenuOpen { setFilterMenuOpen(false); return true }
        if isSearchPopoverOpen { setSearchPopoverOpen(false); return true }
        if !searchResultsPanel.isHidden { closeSearchResults(); return true }
        if isRightPanelVisible { closeRightPanel(); return true }
        if editingPostId != nil { _ = cancelEditing(); return true }
        return false
    }

    func currentFocusRegion() -> FocusRegion? {
        let first = firstResponder
        if first === entryView { return .composer }
        if let editor = findChannelLabel.currentEditor(), first === editor { return .sidebar }
        if first === chatTimelineContainer { return .timeline }
        return nil
    }

    func handleFocusTraversal(reverse: Bool) -> Bool {
        let flags = NSApp.currentEvent?.modifierFlags.intersection(.deviceIndependentFlagsMask) ?? []
        if flags.contains(.command) || flags.contains(.option) || flags.contains(.control) {
            return false
        }
        guard let region = currentFocusRegion() else { return false }
        // Tab is an editing key in the composer (indent/list/code blocks); do not
        // steal it for region traversal. Other regions keep the Tab shortcut.
        if region == .composer { return false }
        let next: FocusRegion
        switch (region, reverse) {
        case (.composer, false): next = .sidebar
        case (.composer, true): next = .timeline
        case (.sidebar, false): next = .timeline
        case (.sidebar, true): next = .composer
        case (.timeline, false): next = .composer
        case (.timeline, true): next = .sidebar
        }
        switch next {
        case .composer:
            makeFirstResponder(entryView)
        case .sidebar:
            makeFirstResponder(findChannelLabel)
        case .timeline:
            makeFirstResponder(chatTimelineContainer)
        }
        return true
    }

    func updateSearchTabsAppearance() {
        let brandBlue = Theme.shared.buttonBg
        let activeTabBg = Theme.shared.buttonBg.withAlphaComponent(0.12)
        let hoverTabBg = Theme.shared.centerHover
        let mutedText = Theme.shared.centerTextMuted

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

    func setupSearchPopover() {
        let popoverWidth: CGFloat = MMMetric.searchPopoverWidth
        let popoverHeight: CGFloat = 122
        let brandBlue = Theme.shared.buttonBg
        let mutedText = Theme.shared.centerTextMuted
        let placeholderColor = Theme.shared.centerTextPlaceholder
        let dividerColor = Theme.shared.divider
        let pillBg = Theme.shared.centerHover
        let pillHoverBg = Theme.shared.divider
        let pillText = Theme.shared.centerTextMuted

        searchPopoverPanel.color = Theme.shared.centerBg
        searchPopoverPanel.cornerRadius = MMRadius.panel
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
        messagesTabPanel.cornerRadius = MMRadius.control
        messagesTabPanel.frame = NSRect(x: 16, y: popoverHeight - 31, width: msgW, height: tabH)
        messagesTabLabel.frame = NSRect(x: 0, y: (tabH - 16) / 2, width: msgW, height: 16)
        messagesTabPanel.addSubview(messagesTabLabel)
        messagesTabPanel.onHoverChanged = { [weak self] _ in
            self?.updateSearchTabsAppearance()
        }
        messagesTabPanel.onClick = { [weak self] in
            guard let self = self else { return }
            self.isSearchFilesTabSelected = false
            self.updateSearchTabsAppearance()
            self.rerunSearchForActiveTab()
        }
        searchPopoverPanel.addSubview(messagesTabPanel)

        filesTabLabel.font = tabFont
        filesTabLabel.alignment = .center
        let filesSize = ("Files" as NSString).size(withAttributes: [.font: tabFont])
        let filesPadH: CGFloat = 8
        let filesW = ceil(filesSize.width) + (filesPadH * 2)
        filesTabPanel.cornerRadius = MMRadius.control
        filesTabPanel.frame = NSRect(x: messagesTabPanel.frame.maxX + 4, y: popoverHeight - 31, width: filesW, height: tabH)
        filesTabLabel.frame = NSRect(x: 0, y: (tabH - 16) / 2, width: filesW, height: 16)
        filesTabPanel.addSubview(filesTabLabel)
        filesTabPanel.onHoverChanged = { [weak self] _ in
            self?.updateSearchTabsAppearance()
        }
        filesTabPanel.onClick = { [weak self] in
            guard let self = self else { return }
            self.isSearchFilesTabSelected = true
            self.updateSearchTabsAppearance()
            self.rerunSearchForActiveTab()
        }
        searchPopoverPanel.addSubview(filesTabPanel)

        let closeBtn = RoundedEdgePanel()
        closeBtn.cornerRadius = MMRadius.control
        closeBtn.color = .clear
        closeBtn.frame = NSRect(x: popoverWidth - 36, y: popoverHeight - 32, width: MMMetric.iconButtonCompact, height: MMMetric.iconButtonCompact)
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
        searchInputBox.cornerRadius = MMRadius.control
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
        searchPopoverInputLabel.textColor = Theme.shared.centerText
        searchPopoverInputLabel.placeholderString = "Search messages"
        searchPopoverInputLabel.isEditable = true
        searchPopoverInputLabel.isSelectable = true
        searchPopoverInputLabel.isBezeled = false
        searchPopoverInputLabel.drawsBackground = false
        searchPopoverInputLabel.focusRingType = .none
        searchPopoverInputLabel.cell?.usesSingleLineMode = true
        searchPopoverInputLabel.target = self
        searchPopoverInputLabel.action = #selector(performSearchFromPopover)
        searchPopoverInputLabel.delegate = self
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
            pill.cornerRadius = MMRadius.tiny

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
            let pillName = title
            pill.onClick = { [weak self] in
                self?.insertSearchFilter(pillName)
            }
            pill.accessibilityTitle = "Insert \\(title) filter"
            searchPopoverPanel.addSubview(pill)
            pillX += pillW + 4
        }

        updateSearchTabsAppearance()
        contentView?.addSubview(searchPopoverPanel)
    }

    func makeMattermostCompassIcon() -> NSImage? {
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

    func configureIconButton(
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
        panel.cornerRadius = MMRadius.control
        if let img = NSImage(systemSymbolName: symbolName, accessibilityDescription: accessibilityDescription) {
            iconView.image = img.withSymbolConfiguration(.init(pointSize: pointSize, weight: .medium))
            iconView.contentTintColor = defaultTint
        }
        panel.addSubview(iconView)
        panel.onHoverChanged = { [weak panel, weak iconView] isHovered in
            panel?.color = isHovered ? hoverBg : .clear
            panel?.setNeedsAppearanceUpdate()
            iconView?.contentTintColor = isHovered ? Theme.shared.sidebarText : defaultTint
        }
        panel.onClick = onClick
        panel.accessibilityTitle = accessibilityDescription
        panel.accessibilityHelp = accessibilityDescription
        contentView?.addSubview(panel)
    }
}
