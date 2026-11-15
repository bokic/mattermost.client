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

    func channelBelongsToTeam(_ channel: MMChannel, teamId: String) -> Bool {
        // Direct and group messages have no team; every other channel must match
        // the active team or it belongs in another team's sidebar.
        guard let channelTeamId = channel.team_id, !channelTeamId.isEmpty else { return true }
        return channelTeamId == teamId
    }

    func isDirectMessageType(_ channel: MMChannel) -> Bool {
        channel.type == "D" || channel.type == "G"
    }

    func loadFavoriteChannels() {
        guard let ws = webService, ws.isLogged() else { return }
        let userId = currentUser?.id ?? ws.currentUserId
        guard !userId.isEmpty else { return }
        Task { @MainActor [weak self] in
            guard let self = self else { return }
            if let preferences = try? await ws.fetchUserPreferences(userId: userId) {
                let favorites = preferences
                    .filter { $0["category"] == "favorite_channel" }
                    .compactMap { $0["name"] }
                for favId in favorites {
                    if !self.favoriteChannelOrder.contains(favId) {
                        self.favoriteChannelOrder.append(favId)
                    }
                }
                self.favoriteChannelIds = Set(self.favoriteChannelOrder).union(favorites)
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
        guard let ws = webService, ws.isLogged() else { return }
        let userId = currentUser?.id ?? ws.currentUserId
        guard !userId.isEmpty else { return }

        let previousFavoriteIds = favoriteChannelIds
        let previousFavoriteOrder = favoriteChannelOrder

        if favorite {
            favoriteChannelIds.insert(channelId)
            if !favoriteChannelOrder.contains(channelId) {
                favoriteChannelOrder.append(channelId)
            }
        } else {
            favoriteChannelIds.remove(channelId)
            favoriteChannelOrder.removeAll(where: { $0 == channelId })
        }
        refreshFavoriteState()
        rebuildFavoritesCategory()

        let preference: [[String: String]] = [[
            "user_id": userId,
            "category": "favorite_channel",
            "name": channelId,
            "value": ""
        ]]
        Task { @MainActor [weak self] in
            guard let self = self else { return }
            do {
                if let team = self.activeTeam,
                   let favCatId = self.serverFavoritesCategoryId {
                    if favorite {
                        try await ws.addChannelToSidebarCategory(
                            teamId: team.id,
                            userId: userId,
                            categoryId: favCatId,
                            channelId: channelId
                        )
                    } else {
                        try await ws.removeChannelFromSidebarCategory(
                            teamId: team.id,
                            userId: userId,
                            categoryId: favCatId,
                            channelId: channelId
                        )
                    }
                }
                if favorite {
                    try await ws.saveUserPreferences(userId: userId, preferences: preference)
                } else {
                    try await ws.deleteUserPreferences(userId: userId, preferences: preference)
                }
            } catch {
                NSLog("Failed to update favorite for \(channelId): \(error.localizedDescription)")
                self.favoriteChannelIds = previousFavoriteIds
                self.favoriteChannelOrder = previousFavoriteOrder
                self.refreshFavoriteState()
                self.rebuildFavoritesCategory()
            }
        }
    }

    func loadUnreadState() {
        guard let ws = webService, ws.isLogged(),
              let team = activeTeam else { return }
        let userId = currentUser?.id ?? ws.currentUserId
        guard !userId.isEmpty else { return }
        Task { @MainActor [weak self] in
            guard let self = self else { return }
            var memberships: [MMChannelMembership] = []
            var page = 0
            while true {
                guard let batch = try? await ws.fetchChannelMemberships(
                    userId: userId,
                    teamId: team.id,
                    page: page,
                    perPage: 200
                ) else { return }
                memberships += batch
                if batch.count < 200 { break }
                page += 1
            }
            guard self.activeTeam?.id == team.id else { return }
            self.membershipsByChannel = Dictionary(memberships.map { ($0.channel_id, $0) }, uniquingKeysWith: { _, latest in latest })
            var unread: [String: Int] = [:]
            var mentions: [String: Int] = [:]
            var viewed: [String: Int64] = [:]
            var muted: Set<String> = []
            var desktopNotifications: [String: String] = [:]
            for membership in memberships {
                let total = Int(self.channelsById[membership.channel_id]?.total_msg_count ?? 0)
                unread[membership.channel_id] = max(0, total - (membership.msg_count ?? 0))
                mentions[membership.channel_id] = membership.mention_count ?? 0
                if let when = membership.last_viewed_at {
                    viewed[membership.channel_id] = when
                }
                let desktop = membership.notify_props?.desktop?.lowercased() ?? "default"
                desktopNotifications[membership.channel_id] = desktop
                if desktop == "none" || membership.notify_props?.mark_unread?.lowercased() == "mention" {
                    muted.insert(membership.channel_id)
                }
            }
            self.unreadByChannel = unread
            self.mentionsByChannel = mentions
            self.lastViewedAtByChannel = viewed
            self.mutedChannelIds = muted
            self.channelDesktopNotificationByChannel = desktopNotifications
            (NSApp.delegate as? AppDelegate)?.syncUnreadCounts(unread)
            if let threadResp = try? await ws.fetchThreadsPage(userId: userId, teamId: team.id, page: 0, perPage: 1) {
                self.totalUnreadThreads = threadResp.total_unread_threads ?? 0
            }
            if let teamsUnread = try? await ws.fetchTeamsUnread(userId: userId) {
                self.teamUnreadById = Dictionary(teamsUnread.map { ($0.team_id, $0) }, uniquingKeysWith: { _, latest in latest })
                self.rebuildTeamMenu()
            }
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
            if item.id != "threads", isChannelMuted(item.id) {
                item.badgePanel.isHidden = true
                item.badgeLabel.stringValue = ""
                item.badgePanel.setNeedsAppearanceUpdate()
                continue
            }
            let unread = item.id == "threads" ? totalUnreadThreads : (unreadByChannel[item.id] ?? 0)
            let mentions = item.id == "threads" ? 0 : (mentionsByChannel[item.id] ?? 0)
            let badgeX = (item.hoverCloseView != nil)
                ? (MMMetric.sidebarWidth - 28 - 34 - 4)
                : (MMMetric.sidebarWidth - 16 - 34)
            item.badgePanel.frame = NSRect(x: badgeX, y: 6, width: 34, height: 20)
            item.badgeLabel.frame = NSRect(x: 2, y: 3, width: 30, height: 14)
            if mentions > 0 {
                item.badgePanel.isHidden = false
                item.badgePanel.color = Theme.shared.mentionBg
                item.badgeLabel.stringValue = mentions > 99 ? "99+" : "\(mentions)"
                item.badgeLabel.alignment = .center
                item.badgeLabel.textColor = Theme.shared.mentionColor
            } else if unread > 0 {
                item.badgePanel.isHidden = false
                item.badgePanel.color = .clear
                item.badgeLabel.stringValue = unread > 99 ? "99+" : "\(unread)"
                item.badgeLabel.alignment = .right
                item.badgeLabel.textColor = Theme.shared.sidebarUnreadText
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

        var orderedChannels: [MMChannel] = []
        for channelId in favoriteChannelOrder {
            if let ch = channelsById[channelId], favoriteChannelIds.contains(channelId) {
                orderedChannels.append(ch)
            }
        }
        let remainingIds = favoriteChannelIds.subtracting(orderedChannels.map(\.id))
        let remainingChannels = remainingIds
            .compactMap { channelsById[$0] }
            .sorted { channelDisplayName(for: $0).localizedCaseInsensitiveCompare(channelDisplayName(for: $1)) == .orderedAscending }
        let channels = orderedChannels + remainingChannels

        guard !channels.isEmpty else {
            layoutLeftSidebar(topBarY: mainPanel.bounds.height)
            return
        }

        let items = channels.map { ch -> SidebarItemView in
            let isBot = isChannelBot(for: ch)
            let targetId = (ch.type == "D") ? resolveDMTargetUserId(for: ch) : nil
            if let tId = targetId {
                fetchAvatarIfNeeded(for: tId)
            }
            let customImg = targetId.flatMap { userAvatarsById[$0] }
            let symbol: String
            switch ch.type {
            case "P": symbol = "lock.fill"
            case "D": symbol = isBot ? "cpu" : "person.fill"
            case "G": symbol = "person.2.circle"
            default: symbol = "globe"
            }
            return createSidebarItem(
                id: ch.id,
                symbolName: symbol,
                title: channelDisplayName(for: ch),
                isSelectable: true,
                isBotBadge: isBot,
                showsCloseOnHover: isDirectMessageType(ch),
                customImage: customImg
            )
        }

        let categoryId = serverFavoritesCategoryId ?? "favorites"
        let category = createSidebarCategory(
            id: categoryId,
            title: L10n.string("FAVORITES"),
            showsAddButton: false,
            items: items,
            isCollapsed: isFavoritesCollapsed
        )
        category.headerRow.onClick = { [weak self] in
            guard let self = self else { return }
            self.isFavoritesCollapsed.toggle()
            self.setSidebarCollapsedState(self.isFavoritesCollapsed, categoryId: categoryId)
            self.persistSidebarCategoryCollapsed(self.isFavoritesCollapsed, categoryId: categoryId)
            let symbolName = self.isFavoritesCollapsed ? "chevron.right" : "chevron.down"
            if let chevImg = NSImage(systemSymbolName: symbolName, accessibilityDescription: "Favorites") {
                category.chevronView.image = chevImg.withSymbolConfiguration(.init(pointSize: 8.5, weight: .bold))
            }
            if self.contentView != nil {
                self.layoutLeftSidebar(topBarY: self.mainPanel.bounds.height)
            }
        }
        isFavoritesCollapsed = category.isCollapsed
        favoritesCategory = category
        if contentView != nil {
            layoutLeftSidebar(topBarY: mainPanel.bounds.height)
            updateSidebarSelectionAppearance()
            updateSidebarBadges()
        }
    }

    func setupLeftChannelSidebar() {
        let mutedTint = Theme.shared.sidebarText.withAlphaComponent(0.64)
        let hoverBg = Theme.shared.sidebarHoverBg

        // 1. Team Header Row: "None v" button + "+" button
        teamHeaderButton.color = Theme.shared.sidebarHeaderBg
        teamHeaderButton.cornerRadius = MMRadius.control
        teamHeaderLabel.font = MMFont.font(ofSize: 16, weight: .semibold)
        teamHeaderLabel.textColor = Theme.shared.sidebarHeaderText
        teamHeaderLabel.isEditable = false
        teamHeaderLabel.isSelectable = false
        teamHeaderLabel.lineBreakMode = .byTruncatingTail
        teamHeaderLabel.maximumNumberOfLines = 1
        teamHeaderButton.addSubview(teamHeaderLabel)

        if let chevImg = NSImage(systemSymbolName: "chevron.down", accessibilityDescription: "Team Menu") {
            teamHeaderChevron.image = chevImg.withSymbolConfiguration(.init(pointSize: 9.5, weight: .bold))
            teamHeaderChevron.contentTintColor = Theme.shared.sidebarHeaderText.withAlphaComponent(0.85)
        }
        teamHeaderButton.addSubview(teamHeaderChevron)
        teamHeaderButton.onHoverChanged = { [weak self] isHovered in
            guard let self = self else { return }
            self.teamHeaderButton.color = isHovered ? hoverBg : Theme.shared.sidebarHeaderBg
            self.teamHeaderButton.setNeedsAppearanceUpdate()
            self.teamHeaderChevron.contentTintColor = isHovered ? Theme.shared.sidebarHeaderText : Theme.shared.sidebarHeaderText.withAlphaComponent(0.85)
        }
        teamHeaderButton.onClick = { [weak self] in
            self?.toggleTeamMenu()
        }
        teamHeaderButton.accessibilityTitle = "Team menu"
        teamHeaderButton.accessibilityHelp = "Switch team or manage active team"
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
        teamAddButton.accessibilityTitle = "Add Team"
        teamAddButton.accessibilityHelp = "Create or join a team"
        mainPanel.addSubview(teamAddButton)

        // 2. Filter & Find Channel Row
        filterChannelButton.color = Theme.shared.sidebarText.withAlphaComponent(0.08)
        filterChannelButton.cornerRadius = MMRadius.control
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
        filterChannelButton.accessibilityTitle = "Filter channels"
        filterChannelButton.accessibilityHelp = "Filter channel list"
        mainPanel.addSubview(filterChannelButton)

        findChannelPanel.color = Theme.shared.sidebarText.withAlphaComponent(0.08)
        findChannelPanel.cornerRadius = MMRadius.control
        findChannelPanel.accessibilityTitle = "Find channel"
        findChannelPanel.accessibilityHelp = "Search channels by name"
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

        sidebarScroll.drawsBackground = false
        sidebarScroll.hasVerticalScroller = true
        sidebarScroll.hasHorizontalScroller = false
        sidebarScroll.horizontalScrollElasticity = .none
        sidebarScroll.autohidesScrollers = true
        sidebarScroll.borderType = .noBorder
        sidebarScroll.documentView = sidebarDoc
        sidebarScroll.contentView.postsBoundsChangedNotifications = false
        mainPanel.addSubview(sidebarScroll)

        setupFilterMenu()

        // 3. Threads Navigation Row
        let threadsItem = createSidebarItem(
            id: "threads",
            symbolName: "text.bubble",
            title: L10n.string("Threads"),
            isSelectable: true,
            isBotBadge: false,
            showsCloseOnHover: false
        )
        threadsSidebarItem = threadsItem
        sidebarDoc.addSubview(threadsItem.row)

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

        let teamId = activeTeam?.id ?? ""
        let channels = channelsById.values
            .filter { channelBelongsToTeam($0, teamId: teamId) }
            .sorted { channelDisplayName(for: $0).localizedCaseInsensitiveCompare(channelDisplayName(for: $1)) == .orderedAscending }

        var channelsItems: [SidebarItemView] = channels
            .filter { !isDirectMessageType($0) }
            .map { ch in
                createSidebarItem(
                    id: ch.id,
                    symbolName: ch.type == "P" ? "lock.fill" : "globe",
                    title: channelDisplayName(for: ch),
                    isSelectable: true,
                    isBotBadge: false,
                    showsCloseOnHover: false
                )
            }
        channelsItems.append(
            createSidebarItem(id: "add-channels", symbolName: "plus", title: L10n.string("Add Channels"), isSelectable: false, isBotBadge: false, showsCloseOnHover: false)
        )
        let channelsCat = createSidebarCategory(id: "channels", title: L10n.string("CHANNELS"), showsAddButton: false, items: channelsItems)
        sidebarCategories.append(channelsCat)

        var dmItems: [SidebarItemView] = channels
            .filter { isDirectMessageType($0) }
            .map { ch in
                createSidebarItem(
                    id: ch.id,
                    symbolName: ch.type == "G" ? "person.2.fill" : (isChannelBot(for: ch) ? "cpu" : "person.fill"),
                    title: channelDisplayName(for: ch),
                    isSelectable: true,
                    isBotBadge: isChannelBot(for: ch),
                    showsCloseOnHover: true
                )
            }
        dmItems.append(
            createSidebarItem(id: "invite-members", symbolName: "plus", title: L10n.string("Invite Members"), isSelectable: false, isBotBadge: false, showsCloseOnHover: false)
        )
        let dmCat = createSidebarCategory(id: "direct_messages", title: L10n.string("DIRECT MESSAGES"), showsAddButton: true, items: dmItems)
        wireDMCategoryAddButton(dmCat)
        sidebarCategories.append(dmCat)

        updateSidebarSelectionAppearance()
        updateSidebarBadges()
        for ch in channels where ch.type == "D" {
            if let targetId = resolveDMTargetUserId(for: ch) {
                fetchAvatarIfNeeded(for: targetId)
            }
        }
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
           let user = usersById[targetId],
           isBotAccount(user) {
            return true
        }
        return channelDisplayName(for: channel).lowercased() == "system-bot"
    }

    func isCurrentChannelBot() -> Bool {
        if let chId = activeChannelId.isEmpty ? nil : activeChannelId, let ch = channelsById[chId] {
            return isChannelBot(for: ch)
        }
        return selectedSidebarItemId == "system-bot"
    }

    func populateSidebarCategories(from response: MMSidebarCategoriesResponse, channels: [MMChannel]) {
        for cat in sidebarCategories {
            cat.headerRow.removeFromSuperview()
            for item in cat.items {
                item.row.removeFromSuperview()
            }
        }
        sidebarCategories.removeAll()

        sidebarCategoryOrderIds = response.order.isEmpty
            ? response.categories.map(\.id)
            : response.order
        let orderedCategories: [MMSidebarCategory]
        if !response.order.isEmpty {
            let catMap = Dictionary(response.categories.map { ($0.id, $0) }, uniquingKeysWith: { _, latest in latest })
            orderedCategories = response.order.compactMap { catMap[$0] }
        } else {
            orderedCategories = response.categories
        }

        if let favCat = response.categories.first(where: { $0.type == "favorites" }) {
            self.serverFavoritesCategoryId = favCat.id
            self.favoriteChannelOrder = favCat.channel_ids
            self.favoriteChannelIds = Set(favCat.channel_ids)
            self.isFavoritesCollapsed = favCat.collapsed ?? false
        }

        guard !orderedCategories.isEmpty else {
            buildDefaultSidebarCategories()
            rebuildFavoritesCategory()
            layoutLeftSidebar(topBarY: mainPanel.bounds.height)
            updateSidebarSelectionAppearance()
            updateSidebarBadges()
            loadUnreadState()
            return
        }

        var placedChannelIds = Set<String>()

        for cat in orderedCategories {
            if cat.type == "favorites" || cat.id == (self.serverFavoritesCategoryId ?? "") || cat.id.lowercased().contains("favorites") {
                for channelId in cat.channel_ids {
                    placedChannelIds.insert(channelId)
                }
                continue
            }

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
                } else if ch.type == "G" {
                    symbolName = "person.2.fill"
                } else {
                    symbolName = "globe"
                }

                let displayTitle = channelDisplayName(for: ch)
                let showsClose = isDirectMessageType(ch)

                let item = createSidebarItem(
                    id: ch.id,
                    symbolName: symbolName,
                    title: displayTitle,
                    isSelectable: true,
                    isBotBadge: isBot,
                    showsCloseOnHover: showsClose,
                    customImage: customImg
                )
                items.append(item)
            }

            if cat.type == "channels" {
                let addChannelsItem = createSidebarItem(
                    id: "add-channels",
                    symbolName: "plus",
                    title: L10n.string("Add Channels"),
                    isSelectable: false,
                    isBotBadge: false,
                    showsCloseOnHover: false
                )
                items.append(addChannelsItem)
            } else if cat.type == "direct_messages" {
                let inviteMembersItem = createSidebarItem(
                    id: "invite-members",
                    symbolName: "plus",
                    title: L10n.string("Invite Members"),
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
                showsAddButton: (cat.type == "direct_messages" || cat.type == "custom"),
                items: items,
                isCollapsed: isCollapsed
            )
            if cat.type == "direct_messages" {
                wireDMCategoryAddButton(categoryView)
            } else if cat.type == "custom" {
                wireCategoryAddChannelButton(categoryView)
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

        // Include any channels not explicitly in categories. Direct messages and
        // group messages belong under DIRECT MESSAGES, never CHANNELS.
        let unplacedChannels = channels.filter {
            !placedChannelIds.contains($0.id) && !isDirectMessageType($0)
        }
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
        let unplacedDMs = channels.filter {
            !placedChannelIds.contains($0.id) && isDirectMessageType($0)
        }
        if !unplacedDMs.isEmpty {
            if let dmIdx = sidebarCategories.firstIndex(where: { $0.id.contains("direct_messages") }) {
                var existingItems = sidebarCategories[dmIdx].items
                let inviteItem = existingItems.last(where: { $0.id == "invite-members" })
                if inviteItem != nil {
                    existingItems.removeLast()
                }
                for ch in unplacedDMs {
                    let isBot = isChannelBot(for: ch)
                    let targetId = (ch.type == "D") ? resolveDMTargetUserId(for: ch) : nil
                    if let tId = targetId {
                        fetchAvatarIfNeeded(for: tId)
                    }
                    let customImg = targetId.flatMap { userAvatarsById[$0] }
                    let item = createSidebarItem(
                        id: ch.id,
                        symbolName: ch.type == "G" ? "person.2.fill" : (isBot ? "cpu" : "person.fill"),
                        title: channelDisplayName(for: ch),
                        isSelectable: true,
                        isBotBadge: isBot,
                        showsCloseOnHover: true,
                        customImage: customImg
                    )
                    existingItems.append(item)
                }
                if let inviteItem = inviteItem {
                    existingItems.append(inviteItem)
                }
                sidebarCategories[dmIdx].items = existingItems
            }
        }

        rebuildFavoritesCategory()
        layoutLeftSidebar(topBarY: mainPanel.bounds.height)
        updateSidebarSelectionAppearance()
        updateSidebarBadges()
        loadUnreadState()
        fetchAvatarForUsernameIfNeeded("system-bot")
    }

    func sidebarCollapseStorageKey() -> String {
        "sidebarCollapsed:\(activeTeam?.id ?? "global")"
    }

    func savedSidebarCollapsedState(_ categoryId: String) -> Bool? {
        let states = UserDefaults.standard.dictionary(forKey: sidebarCollapseStorageKey()) as? [String: Bool]
        return states?[categoryId]
    }

    func setSidebarCollapsedState(_ collapsed: Bool, categoryId: String) {
        var states = UserDefaults.standard.dictionary(forKey: sidebarCollapseStorageKey()) as? [String: Bool] ?? [:]
        states[categoryId] = collapsed
        UserDefaults.standard.set(states, forKey: sidebarCollapseStorageKey())
    }

    func createSidebarCategory(
        id: String,
        title: String,
        showsAddButton: Bool,
        items: [SidebarItemView],
        isCollapsed: Bool = false
    ) -> SidebarCategoryView {
        let initiallyCollapsed = savedSidebarCollapsedState(id) ?? isCollapsed
        let mutedTint = Theme.shared.sidebarText.withAlphaComponent(0.64)
        let headerRow = RoundedEdgePanel()
        headerRow.cornerRadius = 0
        headerRow.color = .clear

        let chevronView = NSImageView()
        let chevSymbol = initiallyCollapsed ? "chevron.right" : "chevron.down"
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
            btn.cornerRadius = MMRadius.control
            btn.color = .clear
            btn.accessibilityTitle = "Add to \(title)"
            btn.accessibilityHelp = "Start direct message or add channel"
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

        headerRow.accessibilityTitle = "\(title) category"
        headerRow.accessibilityHelp = initiallyCollapsed ? "Expand category" : "Collapse category"
        headerRow.accessibilityRoleOverride = .disclosureTriangle
        headerRow.accessibilityValueString = initiallyCollapsed ? "Collapsed" : "Expanded"

        headerRow.onHoverChanged = { [weak chevronView, weak titleLabel] isHovered in
            chevronView?.contentTintColor = isHovered ? Theme.shared.sidebarText : mutedTint
            titleLabel?.textColor = isHovered ? Theme.shared.sidebarText : mutedTint
        }
        headerRow.onClick = { [weak self] in
            self?.toggleSidebarCategory(id)
        }
        headerRow.onRightClick = { [weak self] in
            self?.showSidebarCategoryMenu(id)
        }

        sidebarDoc.addSubview(headerRow)
        for item in items {
            sidebarDoc.addSubview(item.row)
        }

        return SidebarCategoryView(
            id: id,
            headerRow: headerRow,
            chevronView: chevronView,
            titleLabel: titleLabel,
            addButton: addBtn,
            isCollapsed: initiallyCollapsed,
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
        row.accessibilityTitle = title
        row.accessibilityHelp = isSelectable ? "Open \(title)" : title

        let badgePanel = RoundedEdgePanel()
        badgePanel.cornerRadius = MMRadius.card
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

        var closeButton: RoundedEdgePanel? = nil
        if showsCloseOnHover {
            let btn = RoundedEdgePanel()
            btn.cornerRadius = MMRadius.control
            btn.color = .clear
            btn.accessibilityTitle = "Close \(title)"
            btn.accessibilityHelp = "Close conversation"
            let xView = NSImageView()
            if let xImg = NSImage(systemSymbolName: "xmark", accessibilityDescription: "Close") {
                xView.image = xImg.withSymbolConfiguration(.init(pointSize: 9.5, weight: .bold))
                xView.contentTintColor = Theme.shared.sidebarText.withAlphaComponent(0.72)
            }
            xView.frame = NSRect(x: 3, y: 3, width: 12, height: 12)
            btn.addSubview(xView)
            btn.onHoverChanged = { [weak btn, weak xView] isHovered in
                btn?.color = isHovered ? Theme.shared.sidebarText.withAlphaComponent(0.16) : .clear
                btn?.setNeedsAppearanceUpdate()
                xView?.contentTintColor = isHovered ? Theme.shared.sidebarText : Theme.shared.sidebarText.withAlphaComponent(0.72)
            }
            btn.onClick = { [weak self] in
                self?.closeDirectChannel(channelId: id)
            }
            btn.isHidden = true
            row.addSubview(btn)
            closeButton = btn
        }

        row.onHoverChanged = { [weak self] _ in
            self?.updateSidebarSelectionAppearance()
        }
        if isSelectable, channelsById[id] != nil {
            row.onRightClick = { [weak self, weak row] in
                guard let self = self, let row = row else { return }
                self.showChannelContextMenu(channelId: id, from: row)
            }
        }
        row.onClick = { [weak self] in
            guard let self = self else { return }
            if id == "threads" {
                self.selectedSidebarItemId = "threads"
                self.updateSidebarSelectionAppearance()
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
            isBotBadge: isBotBadge,
            hasCustomAvatar: customImage != nil,
            row: row,
            leftBar: leftBar,
            iconView: iconView,
            label: label,
            hoverCloseView: closeButton,
            badgePanel: badgePanel,
            badgeLabel: badgeLabel
        )
    }

    func closeDirectChannel(channelId: String) {
        guard let channel = channelsById[channelId] else { return }
        guard let ws = webService, ws.isLogged() else { return }
        let userId = currentUser?.id ?? ws.currentUserId
        guard !userId.isEmpty else { return }

        Task { @MainActor [weak self] in
            guard let self = self else { return }
            do {
                try await ws.leaveChannel(channelId: channel.id, userId: userId)
                let pref: [[String: String]] = [[
                    "user_id": userId,
                    "category": channel.type == "G" ? "group_channel_show" : "direct_channel_show",
                    "name": (channel.type == "D" ? (self.resolveDMTargetUserId(for: channel) ?? channel.id) : channel.id),
                    "value": "false"
                ]]
                _ = try? await ws.saveUserPreferences(userId: userId, preferences: pref)

                self.channelsById.removeValue(forKey: channel.id)
                self.channelsByName.removeValue(forKey: channel.name.lowercased())
                self.channelsByName.removeValue(forKey: channel.display_name.lowercased())
                if let team = self.activeTeam,
                   let categories = try? await ws.fetchSidebarCategories(teamId: team.id) {
                    self.populateSidebarCategories(from: categories, channels: Array(self.channelsById.values))
                } else {
                    self.rebuildFavoritesCategory()
                    self.layoutLeftSidebar(topBarY: self.mainPanel.bounds.height)
                }
                if self.activeChannelId == channel.id || self.selectedSidebarItemId == channel.id {
                    let fallback = self.channelsByName["town-square"]
                        ?? self.channelsByName["town square"]
                        ?? self.channelsById.values.first
                    if let fallback = fallback {
                        self.selectedSidebarItemId = fallback.id
                        self.updateSidebarSelectionAppearance()
                        self.loadChannelPosts(forSidebarItemId: fallback.id)
                    }
                }
            } catch {
                NSLog("Failed to close direct channel \(channelId): \(error.localizedDescription)")
            }
        }
    }

    func toggleSidebarCategory(_ categoryId: String) {
        guard let idx = sidebarCategories.firstIndex(where: { $0.id == categoryId }) else { return }
        sidebarCategories[idx].isCollapsed.toggle()
        let collapsed = sidebarCategories[idx].isCollapsed
        setSidebarCollapsedState(collapsed, categoryId: categoryId)
        persistSidebarCategoryCollapsed(collapsed, categoryId: categoryId)
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
        let selectedBg = Theme.shared.sidebarHoverBg
        let hoverBg = Theme.shared.sidebarHoverBg
        let defaultText = Theme.shared.sidebarText.withAlphaComponent(0.64)
        let defaultIcon = Theme.shared.sidebarText.withAlphaComponent(0.64)

        for item in allItems {
            let isSelected = item.isSelectable && (item.id == selectedSidebarItemId)
            let isHovered = item.row.isHovered

            if isSelected {
                item.row.color = selectedBg
                item.label.font = MMFont.font(ofSize: 14, weight: .regular)
                item.label.textColor = Theme.shared.sidebarActiveColor
                if item.hasCustomAvatar {
                    item.iconView.contentTintColor = nil
                } else {
                    item.iconView.contentTintColor = Theme.shared.sidebarActiveColor
                }
            } else if isHovered {
                item.row.color = hoverBg
                item.label.font = MMFont.font(ofSize: 14, weight: .regular)
                item.label.textColor = Theme.shared.sidebarActiveColor
                if item.hasCustomAvatar {
                    item.iconView.contentTintColor = nil
                } else {
                    item.iconView.contentTintColor = Theme.shared.sidebarActiveColor
                }
            } else {
                let muted = item.id != "threads" && isChannelMuted(item.id)
                let unread = item.id == "threads" ? totalUnreadThreads : (unreadByChannel[item.id] ?? 0)
                let mentions = item.id == "threads" ? 0 : (mentionsByChannel[item.id] ?? 0)
                let hasUnread = (unread > 0 || mentions > 0) && !muted

                item.row.color = .clear
                if hasUnread {
                    item.label.font = MMFont.font(ofSize: 14, weight: .bold)
                    item.label.textColor = Theme.shared.sidebarUnreadText
                    if !item.hasCustomAvatar {
                        item.iconView.contentTintColor = Theme.shared.sidebarUnreadText
                    }
                } else {
                    item.label.font = MMFont.font(ofSize: 14, weight: .regular)
                    item.label.textColor = muted
                        ? Theme.shared.sidebarText.withAlphaComponent(0.42)
                        : defaultText
                    if item.hasCustomAvatar {
                        item.iconView.contentTintColor = nil
                    } else if item.isBotBadge {
                        item.iconView.contentTintColor = muted
                            ? Theme.shared.sidebarText.withAlphaComponent(0.42)
                            : Theme.shared.sidebarText.withAlphaComponent(0.85)
                    } else {
                        item.iconView.contentTintColor = muted
                            ? Theme.shared.sidebarText.withAlphaComponent(0.42)
                            : defaultIcon
                    }
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
        teamHeaderLabel.lineBreakMode = .byTruncatingTail
        teamHeaderLabel.maximumNumberOfLines = 1
        let textWidth = ceil(teamHeaderLabel.attributedStringValue.size().width)
        let maxLabelWidth: CGFloat = 168
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
        let teamsToDisplay = userTeams.isEmpty ? (activeTeam.map { [$0] } ?? []) : userTeams
        let maxVisibleTeamRows = 5
        let teamsCount = teamsToDisplay.count
        let visibleCount = min(teamsCount, maxVisibleTeamRows)
        let teamsListHeight: CGFloat = CGFloat(visibleCount) * rowHeight
        let actionRowHeight: CGFloat = 30
        let actionsCount: CGFloat = 6
        let separatorHeight: CGFloat = 1
        let menuWidth: CGFloat = 230
        let menuHeight: CGFloat = max(42, teamsListHeight + separatorHeight + 8 + (actionsCount * actionRowHeight) + 12)
        let menuX: CGFloat = 8
        let menuY = max(10, teamHeaderButton.frame.minY - menuHeight - 4)

        teamDropdownMenu.frame = NSRect(x: menuX, y: menuY, width: menuWidth, height: menuHeight)
        teamDropdownMenu.color = Theme.shared.centerBg
        teamDropdownMenu.cornerRadius = MMRadius.menu
        teamDropdownMenu.borderWidth = 1
        teamDropdownMenu.borderColor = Theme.shared.centerText.withAlphaComponent(0.16)
        teamDropdownMenu.shadowColor = .black
        teamDropdownMenu.shadowOpacity = 0.22
        teamDropdownMenu.shadowRadius = 12
        teamDropdownMenu.shadowOffset = CGSize(width: 0, height: -4)

        if teamsToDisplay.isEmpty {
            let emptyLabel = NSTextField(labelWithString: "No teams available")
            emptyLabel.font = MMFont.font(ofSize: 13, weight: .regular)
            emptyLabel.textColor = Theme.shared.centerTextMuted
            emptyLabel.frame = NSRect(x: 14, y: menuHeight - 34, width: menuWidth - 28, height: 20)
            teamDropdownMenu.addSubview(emptyLabel)
        } else {
            let scrollView = NSScrollView()
            scrollView.hasVerticalScroller = teamsCount > maxVisibleTeamRows
            scrollView.hasHorizontalScroller = false
            scrollView.autohidesScrollers = true
            scrollView.borderType = .noBorder
            scrollView.drawsBackground = false
            scrollView.frame = NSRect(x: 0, y: menuHeight - 6 - teamsListHeight, width: menuWidth, height: teamsListHeight)

            let totalTeamsHeight = max(teamsListHeight, CGFloat(teamsCount) * rowHeight)
            let docView = NSView(frame: NSRect(x: 0, y: 0, width: menuWidth, height: totalTeamsHeight))
            scrollView.documentView = docView
            teamDropdownMenu.addSubview(scrollView)

            var yPos = totalTeamsHeight - rowHeight
            for team in teamsToDisplay {
                let row = RoundedEdgePanel()
                row.frame = NSRect(x: 6, y: yPos, width: menuWidth - 12, height: rowHeight)
                row.cornerRadius = MMRadius.control
                row.color = .clear

                let isActive = team.id == activeTeam?.id
                let label = NSTextField(labelWithString: team.display_name.isEmpty ? team.name : team.display_name)
                label.font = MMFont.font(ofSize: 13.5, weight: isActive ? .bold : .medium)
                label.textColor = Theme.shared.centerText
                label.lineBreakMode = .byTruncatingTail
                label.maximumNumberOfLines = 1
                label.isEditable = false
                label.isSelectable = false
                let labelTrailingOffset: CGFloat = isActive ? 58 : 34
                label.frame = NSRect(x: 10, y: 7, width: menuWidth - 12 - 10 - labelTrailingOffset, height: 20)
                row.addSubview(label)

                let unread = teamUnreadById[team.id]
                let mentions = unread?.mention_count ?? 0
                let msgs = unread?.msg_count ?? 0
                if mentions > 0 {
                    let badge = RoundedEdgePanel()
                    badge.cornerRadius = MMRadius.tiny
                    badge.color = Theme.shared.buttonBg
                    let badgeLabel = NSTextField(labelWithString: mentions > 99 ? "99+" : "\(mentions)")
                    badgeLabel.font = MMFont.font(ofSize: 10.5, weight: .bold)
                    badgeLabel.textColor = Theme.shared.buttonColor
                    badgeLabel.alignment = .center
                    badgeLabel.isEditable = false
                    badgeLabel.isSelectable = false
                    let badgeWidth: CGFloat = mentions > 99 ? 28 : 20
                    let badgeX = isActive ? (menuWidth - 12 - 24 - badgeWidth - 4) : (menuWidth - 12 - badgeWidth - 8)
                    badge.frame = NSRect(x: badgeX, y: 8, width: badgeWidth, height: 17)
                    badgeLabel.frame = NSRect(x: 1, y: 1, width: badgeWidth - 2, height: 14)
                    badge.addSubview(badgeLabel)
                    row.addSubview(badge)
                } else if msgs > 0 {
                    let dot = RoundedEdgePanel()
                    dot.cornerRadius = 4
                    dot.color = Theme.shared.centerTextMuted
                    let dotX = isActive ? (menuWidth - 12 - 24 - 8 - 4) : (menuWidth - 12 - 8 - 8)
                    dot.frame = NSRect(x: dotX, y: 13, width: 8, height: 8)
                    row.addSubview(dot)
                }

                if isActive {
                    let checkView = NSImageView()
                    if let checkImg = NSImage(systemSymbolName: "checkmark", accessibilityDescription: "Active") {
                        checkView.image = checkImg.withSymbolConfiguration(.init(pointSize: 11, weight: .bold))
                        checkView.contentTintColor = Theme.shared.buttonBg
                    }
                    checkView.frame = NSRect(x: menuWidth - 36, y: 9, width: 16, height: 16)
                    row.addSubview(checkView)
                }

                row.accessibilityTitle = team.display_name.isEmpty ? team.name : team.display_name
                row.accessibilityRoleOverride = .menuItem
                row.accessibilityValueString = isActive ? "Active" : nil
                row.accessibilityHelp = "Switch to this team"

                row.onHoverChanged = { [weak row] isHovered in
                    row?.color = isHovered ? Theme.shared.centerText.withAlphaComponent(0.08) : .clear
                    row?.setNeedsAppearanceUpdate()
                }

                row.onClick = { [weak self] in
                    self?.switchActiveTeam(to: team)
                }

                docView.addSubview(row)
                yPos -= rowHeight
            }
        }

        // Divider
        let separator = RoundedEdgePanel()
        separator.color = Theme.shared.centerText.withAlphaComponent(0.12)
        separator.frame = NSRect(x: 10, y: menuHeight - 6 - teamsListHeight - 4, width: menuWidth - 20, height: 1)
        teamDropdownMenu.addSubview(separator)

        // Action entries: Invite People, Team Members, Team Settings, Create Team, Join Team, Leave Team
        let actionEntries: [(title: String, symbol: String, action: @MainActor (MainWindow) -> Void)] = [
            ("Invite People", "person.badge.plus", { $0.showTeamInviteDialog() }),
            ("Team Members", "person.2", { $0.showRightPanel(mode: .teamMembers) }),
            ("Team Settings", "gearshape", { $0.showTeamSettingsDialog() }),
            ("Create New Team", "plus.rectangle.on.rectangle", { $0.showCreateTeamDialog() }),
            ("Join another team", "plus.circle", { $0.showJoinTeamDialog() }),
            ("Leave Team", "rectangle.portrait.and.arrow.right", { $0.confirmLeaveTeam() }),
        ]

        var actionY = separator.frame.minY - 4 - actionRowHeight
        for entry in actionEntries {
            let row = RoundedEdgePanel()
            row.frame = NSRect(x: 6, y: actionY, width: menuWidth - 12, height: actionRowHeight)
            row.cornerRadius = MMRadius.control
            row.color = .clear

            let iconView = NSImageView()
            if let img = NSImage(systemSymbolName: entry.symbol, accessibilityDescription: entry.title) {
                iconView.image = img.withSymbolConfiguration(.init(pointSize: 11, weight: .medium))
                iconView.contentTintColor = Theme.shared.centerText.withAlphaComponent(0.75)
            }
            iconView.frame = NSRect(x: 10, y: 7, width: 16, height: 16)
            row.addSubview(iconView)

            let label = NSTextField(labelWithString: entry.title)
            label.font = MMFont.font(ofSize: 13, weight: .regular)
            label.textColor = Theme.shared.centerText
            label.isEditable = false
            label.isSelectable = false
            label.frame = NSRect(x: 32, y: 5, width: menuWidth - 44, height: 20)
            row.addSubview(label)

            row.accessibilityTitle = entry.title
            row.accessibilityRoleOverride = .menuItem
            row.accessibilityHelp = entry.title

            row.onHoverChanged = { [weak row, weak iconView] isHovered in
                row?.color = isHovered ? Theme.shared.centerText.withAlphaComponent(0.08) : .clear
                row?.setNeedsAppearanceUpdate()
                iconView?.contentTintColor = isHovered ? Theme.shared.centerText : Theme.shared.centerText.withAlphaComponent(0.75)
            }

            row.onClick = { [weak self] in
                guard let self = self else { return }
                self.setTeamMenuOpen(false)
                entry.action(self)
            }

            teamDropdownMenu.addSubview(row)
            actionY -= actionRowHeight
        }
    }

    func showJoinTeamDialog() {
        guard let ws = webService, ws.isLogged() else { return }
        let userId = currentUser?.id ?? ws.currentUserId
        guard !userId.isEmpty else { return }

        let alert = NSAlert()
        alert.messageText = "Join another team"
        alert.informativeText = "Enter the team URL name to join."
        alert.addButton(withTitle: "Join")
        alert.addButton(withTitle: "Cancel")

        let field = NSTextField(frame: NSRect(x: 0, y: 0, width: 280, height: 24))
        field.placeholderString = "Team name (e.g. engineering)"
        alert.accessoryView = field

        alert.beginSheetModal(for: self) { [weak self] response in
            guard let self = self, response == .alertFirstButtonReturn else { return }
            let input = field.stringValue.trimmingCharacters(in: .whitespacesAndNewlines).lowercased()
            guard !input.isEmpty else { return }
            Task { @MainActor [weak self] in
                guard let self = self else { return }
                do {
                    let team = try await ws.fetchTeamByName(input)
                    try await ws.addUserToTeam(teamId: team.id, userId: userId)
                    let teams = try await ws.fetchTeams()
                    self.userTeams = teams
                    self.switchActiveTeam(to: team)
                } catch {
                    self.showInfoAlert("Could not join team '\(input)': \(error.localizedDescription)")
                }
            }
        }
    }

    func confirmLeaveTeam() {
        guard let team = activeTeam else { return }
        guard let ws = webService, ws.isLogged() else { return }
        let userId = currentUser?.id ?? ws.currentUserId
        guard !userId.isEmpty else { return }

        let alert = NSAlert()
        alert.messageText = "Leave \(team.display_name.isEmpty ? team.name : team.display_name)?"
        alert.informativeText = "You will be removed from this team and its channels."
        alert.addButton(withTitle: "Leave Team")
        alert.addButton(withTitle: "Cancel")

        alert.beginSheetModal(for: self) { [weak self] response in
            guard let self = self, response == .alertFirstButtonReturn else { return }
            Task { @MainActor [weak self] in
                guard let self = self else { return }
                do {
                    try await ws.leaveTeam(teamId: team.id, userId: userId)
                    let teams = try await ws.fetchTeams()
                    self.userTeams = teams
                    if let nextTeam = teams.first(where: { $0.id != team.id }) ?? teams.first {
                        self.switchActiveTeam(to: nextTeam)
                    } else {
                        self.activeTeam = nil
                        self.channelsById.removeAll()
                        self.channelsByName.removeAll()
                        self.populateSidebarCategories(
                            from: MMSidebarCategoriesResponse(categories: [], order: []),
                            channels: []
                        )
                        self.teamHeaderLabel.stringValue = "No Team"
                        self.rebuildTeamMenu()
                        self.showInfoAlert("You have left the team.")
                    }
                } catch {
                    self.showInfoAlert("Could not leave team: \(error.localizedDescription)")
                }
            }
        }
    }

    func showTeamSettingsDialog() {
        guard let team = activeTeam, let ws = webService else { return }
        let alert = NSAlert()
        alert.messageText = "\(team.display_name.isEmpty ? team.name : team.display_name) Settings"
        alert.informativeText = "View and edit team details."
        alert.addButton(withTitle: "Save")
        alert.addButton(withTitle: "Cancel")

        let container = NSView(frame: NSRect(x: 0, y: 0, width: 320, height: 110))

        let nameLabel = NSTextField(labelWithString: "Team Name:")
        nameLabel.font = MMFont.font(ofSize: 11, weight: .semibold)
        nameLabel.textColor = Theme.shared.centerTextMuted
        nameLabel.frame = NSRect(x: 0, y: 90, width: 320, height: 16)
        container.addSubview(nameLabel)

        let nameField = NSTextField(frame: NSRect(x: 0, y: 66, width: 320, height: 22))
        nameField.stringValue = team.display_name
        nameField.font = MMFont.font(ofSize: 13)
        container.addSubview(nameField)

        let descLabel = NSTextField(labelWithString: "Team Description:")
        descLabel.font = MMFont.font(ofSize: 11, weight: .semibold)
        descLabel.textColor = Theme.shared.centerTextMuted
        descLabel.frame = NSRect(x: 0, y: 44, width: 320, height: 16)
        container.addSubview(descLabel)

        let descField = NSTextField(frame: NSRect(x: 0, y: 20, width: 320, height: 22))
        descField.stringValue = team.description ?? ""
        descField.font = MMFont.font(ofSize: 13)
        container.addSubview(descField)

        let urlLabel = NSTextField(labelWithString: "URL: /\(team.name)")
        urlLabel.font = MMFont.font(ofSize: 11)
        urlLabel.textColor = Theme.shared.centerTextMuted
        urlLabel.frame = NSRect(x: 0, y: 0, width: 320, height: 16)
        container.addSubview(urlLabel)

        alert.accessoryView = container

        alert.beginSheetModal(for: self) { [weak self] response in
            guard let self = self, response == .alertFirstButtonReturn else { return }
            let newDisplayName = nameField.stringValue.trimmingCharacters(in: .whitespacesAndNewlines)
            let newDescription = descField.stringValue.trimmingCharacters(in: .whitespacesAndNewlines)
            guard !newDisplayName.isEmpty else { return }

            Task { @MainActor [weak self] in
                guard let self = self else { return }
                do {
                    let updated = try await ws.updateTeam(
                        teamId: team.id,
                        displayName: newDisplayName,
                        description: newDescription
                    )
                    self.activeTeam = updated
                    if let idx = self.userTeams.firstIndex(where: { $0.id == updated.id }) {
                        self.userTeams[idx] = updated
                    }
                    self.updateTeamHeader(with: updated)
                    self.rebuildTeamMenu()
                    self.showInfoAlert("Team settings saved.")
                } catch {
                    self.showInfoAlert("Could not update team: \(error.localizedDescription)")
                }
            }
        }
    }

    func showTeamInviteDialog() {
        guard let team = activeTeam, let ws = webService else { return }
        let inviteUrlString = ws.teamInviteURL(team: team)?.absoluteString ?? ""

        let alert = NSAlert()
        alert.messageText = "Invite people to \(team.display_name)"
        alert.informativeText = "Share the invite link or send an email invitation."
        alert.addButton(withTitle: "Send Invite")
        alert.addButton(withTitle: "Copy Invite Link")
        alert.addButton(withTitle: "Cancel")

        let container = NSView(frame: NSRect(x: 0, y: 0, width: 320, height: 80))

        let linkLabel = NSTextField(labelWithString: "Team Invite Link:")
        linkLabel.font = MMFont.font(ofSize: 11, weight: .semibold)
        linkLabel.textColor = Theme.shared.centerTextMuted
        linkLabel.frame = NSRect(x: 0, y: 62, width: 320, height: 16)
        container.addSubview(linkLabel)

        let linkField = NSTextField(frame: NSRect(x: 0, y: 38, width: 320, height: 22))
        linkField.isEditable = false
        linkField.stringValue = inviteUrlString.isEmpty ? "No invite ID configured" : inviteUrlString
        linkField.font = MMFont.font(ofSize: 11)
        container.addSubview(linkField)

        let emailField = NSTextField(frame: NSRect(x: 0, y: 4, width: 320, height: 24))
        emailField.placeholderString = "Invite by email: name@example.com"
        container.addSubview(emailField)

        alert.accessoryView = container

        alert.beginSheetModal(for: self) { [weak self] response in
            guard let self = self else { return }
            if response == .alertFirstButtonReturn {
                let email = emailField.stringValue.trimmingCharacters(in: .whitespacesAndNewlines)
                guard email.contains("@"), email.contains(".") else {
                    self.showInfoAlert("Please enter a valid email address.")
                    return
                }
                Task { @MainActor [weak self] in
                    guard let self = self else { return }
                    do {
                        try await ws.sendTeamInvite(teamId: team.id, email: email)
                        self.showInfoAlert("Invitation sent to \(email).")
                    } catch {
                        self.showInfoAlert("Could not send invite: \(error.localizedDescription)")
                    }
                }
            } else if response == .alertSecondButtonReturn {
                if !inviteUrlString.isEmpty {
                    NSPasteboard.general.clearContents()
                    NSPasteboard.general.setString(inviteUrlString, forType: .string)
                    self.showInfoAlert("Invite link copied to clipboard.")
                } else {
                    self.showInfoAlert("No invite link available for this team.")
                }
            }
        }
    }

    func updateTeamHeader(with team: MMTeam) {
        if activeTeam?.id != team.id {
            invalidateDMUsers()
        }
        self.activeTeam = team
        self.teamHeaderLabel.stringValue = team.display_name.isEmpty ? team.name : team.display_name
        self.layoutTeamHeader()
    }

    func switchActiveTeam(to team: MMTeam) {
        guard let ws = webService else { return }
        if activeTeam?.id == team.id {
            setTeamMenuOpen(false)
            return
        }
        invalidateDMUsers()
        let previousTeam = activeTeam
        teamSwitchToken += 1
        let token = teamSwitchToken
        self.updateTeamHeader(with: team)
        self.setTeamMenuOpen(false)
        Task { @MainActor [weak self] in
            guard let self = self else { return }
            do {
                let channels = try await ws.fetchChannels(teamId: team.id)
                guard token == self.teamSwitchToken else { return }
                var allChannels = channels
                if let myChannels = try? await ws.fetchAllChannels() {
                    guard token == self.teamSwitchToken else { return }
                    var chMap: [String: MMChannel] = [:]
                    for c in channels { chMap[c.id] = c }
                    for c in myChannels where self.channelBelongsToTeam(c, teamId: team.id) {
                        chMap[c.id] = c
                    }
                    allChannels = Array(chMap.values)
                }
                guard token == self.teamSwitchToken else { return }
                self.channelsById.removeAll()
                self.channelsByName.removeAll()
                for ch in allChannels {
                    self.channelsById[ch.id] = ch
                    self.channelsByName[ch.name.lowercased()] = ch
                    self.channelsByName[ch.display_name.lowercased()] = ch
                }
                await self.preloadDMUsers(for: allChannels)
                guard token == self.teamSwitchToken else { return }
                if let categoriesResponse = try? await ws.fetchSidebarCategories(teamId: team.id) {
                    guard token == self.teamSwitchToken else { return }
                    self.populateSidebarCategories(from: categoriesResponse, channels: allChannels)
                }
                guard token == self.teamSwitchToken else { return }
                UserDefaults.standard.set(team.id, forKey: "lastTeamId")
                self.refreshServerTheme(teamId: team.id)
                let savedChannelId = UserDefaults.standard.string(forKey: "lastChannelId")
                let savedChannel = savedChannelId.flatMap { self.channelsById[$0] }
                let botCh = self.channelsByName["system-bot"]
                    ?? self.channelsByName["system bot"]
                    ?? allChannels.first(where: { self.isChannelBot(for: $0) })
                let defaultCh = (CommandLine.arguments.contains("--system-bot") ? botCh : nil)
                    ?? savedChannel
                    ?? self.channelsByName["town-square"]
                    ?? self.channelsByName["town square"]
                    ?? channels.first
                if let initialCh = defaultCh {
                    self.selectedSidebarItemId = initialCh.id
                    self.updateSidebarSelectionAppearance()
                    self.loadChannelPosts(forSidebarItemId: initialCh.id)
                }
            } catch {
                guard token == self.teamSwitchToken else { return }
                if let previousTeam = previousTeam {
                    self.updateTeamHeader(with: previousTeam)
                }
                self.showInfoAlert("Could not switch team: \(error.localizedDescription)")
            }
        }
    }

    func layoutLeftSidebar(topBarY: CGFloat) {
        // Matches the web client at >=1201px: 264pt sidebar starting 5pt from the
        // window edge, 32pt rows, 19/16pt horizontal padding.
        let sidebarX: CGFloat = 1
        let sidebarWidth: CGFloat = MMMetric.sidebarWidth

        // Row 1: Team header button + "+" button
        layoutTeamHeader(topBarY: topBarY)

        teamAddButton.frame = NSRect(x: sidebarX + 216, y: topBarY - 43.5, width: MMMetric.iconButtonRegular, height: MMMetric.iconButtonRegular)
        teamAddIconView.frame = NSRect(x: 7, y: 7, width: 18, height: 18)

        // Row 2: Filter button + "Find channel" pill
        filterChannelButton.frame = NSRect(x: sidebarX + 16, y: topBarY - 83, width: MMMetric.iconButtonSmall, height: MMMetric.iconButtonSmall)
        filterChannelIconView.frame = NSRect(x: 4, y: 4, width: 20, height: 20)
        filterMenu.frame = NSRect(x: sidebarX + 16, y: topBarY - 83 - 8 - 68, width: 180, height: 68)

        findChannelPanel.frame = NSRect(x: sidebarX + 48, y: topBarY - 83, width: 200, height: 28)
        findChannelIconView.frame = NSRect(x: 2, y: 5, width: 18, height: 18)
        findChannelLabel.frame = NSRect(x: 29, y: 4, width: 165, height: 20)

        let query = channelFilterQuery.lowercased()
        func matches(_ title: String) -> Bool {
            query.isEmpty || title.lowercased().contains(query)
        }
        func hasUnread(_ id: String) -> Bool {
            (unreadByChannel[id] ?? 0) > 0 || (mentionsByChannel[id] ?? 0) > 0
        }

        // Row 3: Scrollable navigation content below the pinned filter row.
        sidebarScroll.frame = NSRect(
            x: sidebarX,
            y: 0,
            width: sidebarWidth,
            height: max(0, topBarY - 96)
        )

        var currentY: CGFloat = 4
        var hasVisibleUnreadContent = false
        if let threads = threadsSidebarItem {
            if matches(threads.label.stringValue)
                && !sidebarFavoritesOnly
                && (!sidebarUnreadOnly || totalUnreadThreads > 0) {
                hasVisibleUnreadContent = hasVisibleUnreadContent || sidebarUnreadOnly
                threads.row.isHidden = false
                threads.row.frame = NSRect(x: sidebarX, y: currentY, width: sidebarWidth, height: 32)
                threads.leftBar.frame = NSRect(x: 0, y: 0, width: 4, height: 32)
                threads.iconView.frame = NSRect(x: 21, y: 7, width: 18, height: 18)
                threads.label.frame = NSRect(x: 49, y: 6, width: sidebarWidth - 64, height: 20)
                currentY += 32
            } else {
                threads.row.isHidden = true
            }
        }

        // Favorites branch (channels marked with the star)
        if sidebarEmptyStateLabel.superview == nil {
            sidebarEmptyStateLabel.font = MMFont.font(ofSize: 12)
            sidebarEmptyStateLabel.textColor = Theme.shared.sidebarTextMuted
            sidebarEmptyStateLabel.alignment = .left
            sidebarEmptyStateLabel.isEditable = false
            sidebarEmptyStateLabel.isSelectable = false
            sidebarDoc.addSubview(sidebarEmptyStateLabel)
        }
        sidebarEmptyStateLabel.isHidden = true
        if let favorites = favoritesCategory {
            let visibleFavorites = favorites.items.filter {
                matches($0.label.stringValue)
                    && (!sidebarUnreadOnly || hasUnread($0.id))
            }
            if !visibleFavorites.isEmpty || (query.isEmpty && !sidebarUnreadOnly) {
                if !visibleFavorites.isEmpty { hasVisibleUnreadContent = true }
                favorites.headerRow.isHidden = false
                favorites.headerRow.frame = NSRect(x: sidebarX, y: currentY, width: sidebarWidth, height: 32)
                favorites.chevronView.frame = NSRect(x: 1, y: 8, width: 16, height: 16)
                let chevron = isFavoritesCollapsed ? "chevron.right" : "chevron.down"
                if let img = NSImage(systemSymbolName: chevron, accessibilityDescription: "Favorites") {
                    favorites.chevronView.image = img.withSymbolConfiguration(.init(pointSize: 9, weight: .bold))
                }
                favorites.titleLabel.frame = NSRect(x: 17, y: 7, width: sidebarWidth - 60, height: 18)
                currentY += 32
                for item in favorites.items {
                    if !matches(item.label.stringValue)
                        || isFavoritesCollapsed
                        || (sidebarUnreadOnly && !hasUnread(item.id)) {
                        item.row.isHidden = true
                        continue
                    }
                    item.row.isHidden = false
                    item.row.frame = NSRect(x: sidebarX, y: currentY, width: sidebarWidth, height: 32)
                    item.leftBar.frame = NSRect(x: 0, y: 0, width: 4, height: 32)
                    item.iconView.frame = NSRect(x: 21, y: 7, width: 18, height: 18)
                    item.label.frame = NSRect(x: 49, y: 6, width: sidebarWidth - 74, height: 20)
                    item.hoverCloseView?.frame = NSRect(x: sidebarWidth - 28, y: 7, width: 18, height: 18)
                    currentY += 32
                }
                currentY += 8
            } else {
                favorites.headerRow.isHidden = true
                favorites.items.forEach { $0.row.isHidden = true }
            }
            if sidebarFavoritesOnly && visibleFavorites.isEmpty {
                sidebarEmptyStateLabel.stringValue = query.isEmpty ? "No favorite channels" : "No matching favorites"
                sidebarEmptyStateLabel.isHidden = false
                sidebarEmptyStateLabel.frame = NSRect(
                    x: sidebarX + 17,
                    y: currentY,
                    width: sidebarWidth - 34,
                    height: 18
                )
                currentY += 28
            }
        }

        // Categories & items (the server's own favorites group is replaced by
        // the locally derived FAVORITES branch above)
        for category in sidebarCategories where !category.id.lowercased().contains("favorites") && category.id != (serverFavoritesCategoryId ?? "") {
            let visibleItems = category.items.filter {
                matches($0.label.stringValue)
                    && !favoriteChannelIds.contains($0.id)
                    && (!sidebarUnreadOnly || hasUnread($0.id))
            }
            // Favorites-only and unread-only filters hide empty categories.
            if sidebarFavoritesOnly
                || (!query.isEmpty && visibleItems.isEmpty)
                || (sidebarUnreadOnly && visibleItems.isEmpty) {
                category.headerRow.isHidden = true
                category.items.forEach { $0.row.isHidden = true }
                continue
            }
            category.headerRow.isHidden = false
            if !visibleItems.isEmpty { hasVisibleUnreadContent = true }
            category.headerRow.frame = NSRect(x: sidebarX, y: currentY, width: sidebarWidth, height: 32)
            category.chevronView.frame = NSRect(x: 1, y: 8, width: 16, height: 16)
            category.titleLabel.frame = NSRect(x: 17, y: 7, width: sidebarWidth - 60, height: 18)
            category.addButton?.frame = NSRect(x: sidebarWidth - 32, y: 6, width: 20, height: 20)
            currentY += 32

            for item in category.items {
                if !matches(item.label.stringValue)
                    || favoriteChannelIds.contains(item.id)
                    || (sidebarFavoritesOnly && !favoriteChannelIds.contains(item.id))
                    || (sidebarUnreadOnly && !hasUnread(item.id)) {
                    item.row.isHidden = true
                } else if category.isCollapsed && item.id != selectedSidebarItemId {
                    item.row.isHidden = true
                } else {
                    item.row.isHidden = false
                    item.row.frame = NSRect(x: sidebarX, y: currentY, width: sidebarWidth, height: 32)
                    item.leftBar.frame = NSRect(x: 0, y: 0, width: 4, height: 32)
                    item.iconView.frame = NSRect(x: 21, y: 7, width: 18, height: 18)
                    item.label.frame = NSRect(x: 49, y: 6, width: sidebarWidth - 74, height: 20)
                    item.hoverCloseView?.frame = NSRect(x: sidebarWidth - 28, y: 7, width: 18, height: 18)
                    currentY += 32
                }
            }
            currentY += 8
        }

        if sidebarUnreadOnly && !hasVisibleUnreadContent {
            sidebarEmptyStateLabel.stringValue = query.isEmpty
                ? "No unread channels"
                : "No unread channels match your filter"
            sidebarEmptyStateLabel.isHidden = false
            sidebarEmptyStateLabel.frame = NSRect(
                x: sidebarX + 17,
                y: currentY,
                width: sidebarWidth - 34,
                height: 18
            )
            currentY += 28
        }

        sidebarDoc.frame = NSRect(
            x: 0,
            y: 0,
            width: sidebarWidth,
            height: max(currentY + 4, sidebarScroll.contentView.bounds.height)
        )
        if lastSidebarScrollSelection != selectedSidebarItemId {
            lastSidebarScrollSelection = selectedSidebarItemId
            scrollSidebarSelectionIntoView()
        }
    }

    func scrollSidebarSelectionIntoView() {
        let items = (threadsSidebarItem.map { [$0] } ?? [])
            + (favoritesCategory?.items ?? [])
            + sidebarCategories.flatMap { $0.items }
        guard let item = items.first(where: { $0.id == selectedSidebarItemId }),
              !item.row.isHidden
        else { return }
        let visible = sidebarScroll.contentView.bounds.insetBy(dx: 0, dy: -8)
        if !visible.contains(item.row.frame) {
            sidebarDoc.scrollToVisible(item.row.frame)
        }
    }
}
