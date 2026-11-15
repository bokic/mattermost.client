//
//  MainWindow+Sidebar.swift
//  mattermost.client
//
//  Split from MainWindow.swift.
//

import AppKit
import Foundation
import UniformTypeIdentifiers

extension MainWindow {

    func loadFavoriteChannels() {
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

    func refreshFavoriteState() {
        guard !activeChannelId.isEmpty else { return }
        isChannelFavorited = favoriteChannelIds.contains(activeChannelId)
        let symbol = isChannelFavorited ? "star.fill" : "star"
        if let image = NSImage(systemSymbolName: symbol, accessibilityDescription: "Favorite") {
            channelStarIconView.image = image.withSymbolConfiguration(.init(pointSize: 12.5, weight: .medium))
        }
        let starGold = Theme.shared.awayIndicator
        let muted = Theme.shared.centerTextMuted
        let dark = Theme.shared.centerText
        channelStarIconView.contentTintColor = isChannelFavorited
            ? starGold
            : (channelStarButton.isHovered ? dark : muted)
    }

    func setChannelFavorite(_ favorite: Bool, channelId: String) {
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

    func loadUnreadState() {
        guard let ws = (NSApp.delegate as? AppDelegate)?.webService, ws.isLogged(),
              let team = activeTeam else { return }
        let userId = currentUser?.id ?? ws.currentUserId
        guard !userId.isEmpty else { return }
        Task { @MainActor [weak self] in
            guard let self = self else { return }
            guard let memberships = try? await ws.fetchChannelMemberships(userId: userId, teamId: team.id) else { return }
            self.membershipsByChannel = Dictionary(uniqueKeysWithValues: memberships.map { ($0.channel_id, $0) })
            var unread: [String: Int] = [:]
            var mentions: [String: Int] = [:]
            var viewed: [String: Int64] = [:]
            for membership in memberships {
                let total = Int(self.channelsById[membership.channel_id]?.total_msg_count ?? 0)
                unread[membership.channel_id] = max(0, total - (membership.msg_count ?? 0))
                mentions[membership.channel_id] = membership.mention_count ?? 0
                if let when = membership.last_viewed_at {
                    viewed[membership.channel_id] = when
                }
            }
            self.unreadByChannel = unread
            self.mentionsByChannel = mentions
            self.lastViewedAtByChannel = viewed
            self.updateSidebarBadges()
            self.updateNewMessagesBaseline()
            self.markActiveChannelViewed()
        }
    }

    func updateSidebarBadges() {
        let allItems: [SidebarItemView] = (threadsSidebarItem.map { [$0] } ?? [])
            + (favoritesCategory?.items ?? [])
            + sidebarCategories.flatMap { $0.items }
        for item in allItems {
            let unread = unreadByChannel[item.id] ?? 0
            let mentions = mentionsByChannel[item.id] ?? 0
            item.badgePanel.frame = NSRect(x: 264 - 16 - 34, y: 6, width: 34, height: 20)
            item.badgeLabel.frame = NSRect(x: 2, y: 3, width: 30, height: 14)
            if mentions > 0 {
                item.badgePanel.isHidden = false
                item.badgePanel.color = Theme.shared.buttonBg
                item.badgeLabel.stringValue = mentions > 99 ? "99+" : "\(mentions)"
                item.badgeLabel.alignment = .center
                item.badgeLabel.textColor = .white
            } else if unread > 0 {
                item.badgePanel.isHidden = false
                item.badgePanel.color = .clear
                item.badgeLabel.stringValue = unread > 99 ? "99+" : "\(unread)"
                item.badgeLabel.alignment = .right
                item.badgeLabel.textColor = Theme.shared.sidebarText.withAlphaComponent(0.88)
            } else {
                item.badgePanel.isHidden = true
                item.badgeLabel.stringValue = ""
            }
            item.badgePanel.setNeedsAppearanceUpdate()
        }
    }

    func rebuildFavoritesCategory() {
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
        updateSidebarBadges()
        layoutLeftSidebar(topBarY: mainPanel.bounds.height)
    }

    func setupLeftChannelSidebar() {
        let mutedTint = Theme.shared.sidebarText.withAlphaComponent(0.64)
        let hoverBg = Theme.shared.sidebarText.withAlphaComponent(0.08)

        // 1. Team Header Row: "None v" button + "+" button
        teamHeaderButton.color = .clear
        teamHeaderButton.cornerRadius = 4
        teamHeaderLabel.font = MMFont.font(ofSize: 16, weight: .semibold)
        teamHeaderLabel.textColor = Theme.shared.sidebarText
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
            self.teamHeaderChevron.contentTintColor = isHovered ? Theme.shared.sidebarText : mutedTint
        }
        teamHeaderButton.onClick = { [weak self] in
            self?.toggleTeamMenu()
        }
        mainPanel.addSubview(teamHeaderButton)

        teamDropdownMenu.isHidden = true
        contentView?.addSubview(teamDropdownMenu)

        teamAddButton.color = Theme.shared.sidebarText.withAlphaComponent(0.12)
        teamAddButton.cornerRadius = 16
        if let plusImg = NSImage(systemSymbolName: "plus", accessibilityDescription: "Add") {
            teamAddIconView.image = plusImg.withSymbolConfiguration(.init(pointSize: 15, weight: .medium))
            teamAddIconView.contentTintColor = mutedTint
        }
        teamAddButton.addSubview(teamAddIconView)
        teamAddButton.onHoverChanged = { [weak self] isHovered in
            guard let self = self else { return }
            self.teamAddButton.color = Theme.shared.sidebarText.withAlphaComponent(isHovered ? 0.18 : 0.12)
            self.teamAddButton.setNeedsAppearanceUpdate()
            self.teamAddIconView.contentTintColor = isHovered ? Theme.shared.sidebarText : mutedTint
        }
        teamAddButton.onClick = { [weak self] in
            self?.showCreateTeamDialog()
        }
        mainPanel.addSubview(teamAddButton)

        // 2. Filter & Find Channel Row
        filterChannelButton.color = Theme.shared.sidebarText.withAlphaComponent(0.08)
        filterChannelButton.cornerRadius = 4
        if let filterImg = NSImage(systemSymbolName: "line.3.horizontal.decrease", accessibilityDescription: "Filter") {
            filterChannelIconView.image = filterImg.withSymbolConfiguration(.init(pointSize: 13, weight: .medium))
            filterChannelIconView.contentTintColor = mutedTint
        }
        filterChannelButton.addSubview(filterChannelIconView)
        filterChannelButton.onHoverChanged = { [weak self] isHovered in
            guard let self = self else { return }
            self.filterChannelButton.color = Theme.shared.sidebarText.withAlphaComponent(isHovered ? 0.15 : 0.08)
            self.filterChannelButton.setNeedsAppearanceUpdate()
            self.filterChannelIconView.contentTintColor = isHovered ? Theme.shared.sidebarText : mutedTint
        }
        filterChannelButton.onClick = { [weak self] in
            guard let self = self else { return }
            self.setFilterMenuOpen(!self.isFilterMenuOpen)
        }
        mainPanel.addSubview(filterChannelButton)

        findChannelPanel.color = Theme.shared.sidebarText.withAlphaComponent(0.08)
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
            self.findChannelPanel.color = Theme.shared.sidebarText.withAlphaComponent(isHovered ? 0.14 : 0.08)
            self.findChannelPanel.setNeedsAppearanceUpdate()
            self.findChannelIconView.contentTintColor = isHovered ? Theme.shared.sidebarText : mutedTint
            self.findChannelLabel.textColor = isHovered ? Theme.shared.sidebarText : mutedTint
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

    func buildDefaultSidebarCategories() {
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
        wireDMCategoryAddButton(dmCat)
        sidebarCategories.append(dmCat)

        updateSidebarSelectionAppearance()
        fetchAvatarForUsernameIfNeeded("system-bot")
    }

    func isLikelyMattermostId(_ str: String) -> Bool {
        return str.count == 26 && str.allSatisfy { ($0 >= "a" && $0 <= "z") || ($0 >= "0" && $0 <= "9") }
    }

    func isRawDMNameOrId(_ str: String) -> Bool {
        if str.contains("__") { return true }
        return isLikelyMattermostId(str)
    }

    func resolveDMTargetUserId(for channel: MMChannel) -> String? {
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

    func channelDisplayName(for channel: MMChannel) -> String {
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

    func isChannelBot(for channel: MMChannel) -> Bool {
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

    func isCurrentChannelBot() -> Bool {
        if let chId = activeChannelId.isEmpty ? nil : activeChannelId, let ch = channelsById[chId] {
            return isChannelBot(for: ch)
        }
        if selectedSidebarItemId.lowercased().contains("bot") || channelTitleLabel.stringValue.lowercased().contains("bot") {
            return true
        }
        return false
    }

    func populateSidebarCategories(from response: MMSidebarCategoriesResponse, channels: [MMChannel]) {
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
            if cat.type == "direct_messages" {
                wireDMCategoryAddButton(categoryView)
            }
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

        // Include any public/channels not explicitly in categories
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
        updateSidebarBadges()
        loadUnreadState()
        fetchAvatarForUsernameIfNeeded("system-bot")
    }

    func createSidebarCategory(
        id: String,
        title: String,
        showsAddButton: Bool,
        items: [SidebarItemView],
        isCollapsed: Bool = false
    ) -> SidebarCategoryView {
        let mutedTint = Theme.shared.sidebarText.withAlphaComponent(0.64)
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
                btn?.color = isHovered ? Theme.shared.sidebarText.withAlphaComponent(0.12) : .clear
                btn?.setNeedsAppearanceUpdate()
                addIcon?.contentTintColor = isHovered ? Theme.shared.sidebarText : mutedTint
            }
            headerRow.addSubview(btn)
            addBtn = btn
        }

        headerRow.onHoverChanged = { [weak chevronView, weak titleLabel] isHovered in
            chevronView?.contentTintColor = isHovered ? Theme.shared.sidebarText : mutedTint
            titleLabel?.textColor = isHovered ? Theme.shared.sidebarText : mutedTint
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

    func createSidebarItem(
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
        leftBar.color = Theme.shared.sidebarActiveBorder
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
                iconView.contentTintColor = Theme.shared.sidebarText.withAlphaComponent(0.85)
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

        let badgePanel = RoundedEdgePanel()
        badgePanel.cornerRadius = 10
        badgePanel.color = .clear
        badgePanel.isHidden = true
        row.addSubview(badgePanel)

        let badgeLabel = NSTextField(labelWithString: "")
        badgeLabel.font = MMFont.font(ofSize: 11, weight: .semibold)
        badgeLabel.textColor = .white
        badgeLabel.alignment = .center
        badgeLabel.isEditable = false
        badgeLabel.isSelectable = false
        badgePanel.addSubview(badgeLabel)

        var closeView: NSImageView? = nil
        if showsCloseOnHover {
            let xView = NSImageView()
            if let xImg = NSImage(systemSymbolName: "xmark", accessibilityDescription: "Close") {
                xView.image = xImg.withSymbolConfiguration(.init(pointSize: 9.5, weight: .bold))
                xView.contentTintColor = Theme.shared.sidebarText.withAlphaComponent(0.72)
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
            hoverCloseView: closeView,
            badgePanel: badgePanel,
            badgeLabel: badgeLabel
        )
    }

    func toggleSidebarCategory(_ categoryId: String) {
        guard let idx = sidebarCategories.firstIndex(where: { $0.id == categoryId }) else { return }
        sidebarCategories[idx].isCollapsed.toggle()
        let collapsed = sidebarCategories[idx].isCollapsed
        let symbolName = collapsed ? "chevron.right" : "chevron.down"
        if let chevImg = NSImage(systemSymbolName: symbolName, accessibilityDescription: sidebarCategories[idx].titleLabel.stringValue) {
            sidebarCategories[idx].chevronView.image = chevImg.withSymbolConfiguration(.init(pointSize: 8.5, weight: .bold))
        }
        if contentView != nil {
            layoutLeftSidebar(topBarY: mainPanel.bounds.height)
        }
    }

    func updateSidebarSelectionAppearance() {
        let allItems: [SidebarItemView] = (threadsSidebarItem.map { [$0] } ?? [])
            + (favoritesCategory?.items ?? [])
            + sidebarCategories.flatMap { $0.items }
        // Web: selected and hovered rows both use 8% white, labels are 14pt regular.
        let selectedBg = Theme.shared.sidebarText.withAlphaComponent(0.08)
        let hoverBg = Theme.shared.sidebarText.withAlphaComponent(0.08)
        let defaultText = Theme.shared.sidebarText.withAlphaComponent(0.64)
        let defaultIcon = Theme.shared.sidebarText.withAlphaComponent(0.64)

        for item in allItems {
            let isSelected = item.isSelectable && (item.id == selectedSidebarItemId)
            let isHovered = item.row.isHovered

            if isSelected {
                item.row.color = selectedBg
                item.label.font = MMFont.font(ofSize: 14, weight: .regular)
                item.label.textColor = Theme.shared.sidebarActiveColor
                if !item.isBotBadge {
                    item.iconView.contentTintColor = Theme.shared.sidebarActiveColor
                } else {
                    item.iconView.contentTintColor = nil
                }
            } else if isHovered {
                item.row.color = hoverBg
                item.label.font = MMFont.font(ofSize: 14, weight: .regular)
                item.label.textColor = Theme.shared.sidebarActiveColor
                if !item.isBotBadge {
                    item.iconView.contentTintColor = Theme.shared.sidebarActiveColor
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
            item.leftBar.color = Theme.shared.sidebarActiveBorder
            item.leftBar.setNeedsAppearanceUpdate()
            item.row.setNeedsAppearanceUpdate()
            item.hoverCloseView?.isHidden = !isHovered
        }
    }

    func layoutTeamHeader(topBarY: CGFloat? = nil) {
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

    func rebuildTeamMenu() {
        teamDropdownMenu.subviews.forEach { $0.removeFromSuperview() }

        let rowHeight: CGFloat = 34
        let teamsToDisplay = userTeams.isEmpty ? (activeTeam != nil ? [activeTeam!] : []) : userTeams
        let menuHeight: CGFloat = max(42, CGFloat(teamsToDisplay.count) * rowHeight + 12)
        let menuWidth: CGFloat = 220
        let menuX: CGFloat = 8
        let menuY = teamHeaderButton.frame.minY - menuHeight - 4

        teamDropdownMenu.frame = NSRect(x: menuX, y: menuY, width: menuWidth, height: menuHeight)
        teamDropdownMenu.color = Theme.shared.centerBg
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

    func updateTeamHeader(with team: MMTeam) {
        self.activeTeam = team
        self.teamHeaderLabel.stringValue = team.display_name.isEmpty ? team.name : team.display_name
        self.layoutTeamHeader()
    }

    func switchActiveTeam(to team: MMTeam) {
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

    func layoutLeftSidebar(topBarY: CGFloat) {
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
}
