//
//  MainWindow+People.swift
//  mattermost.client
//
//  Split from MainWindow.swift.
//

import AppKit
import Foundation
import UniformTypeIdentifiers

extension MainWindow {

    func statusColor(for status: String) -> NSColor {
        switch status.lowercased() {
        case "online":
            return Theme.shared.onlineIndicator
        case "away":
            return Theme.shared.awayIndicator
        case "dnd":
            return Theme.shared.dndIndicator
        case "offline":
            return Theme.shared.centerTextPlaceholder
        default:
            return Theme.shared.onlineIndicator
        }
    }

    func statusString(for index: Int) -> String {
        switch index {
        case 0: return "online"
        case 1: return "away"
        case 2: return "dnd"
        case 3: return "offline"
        default: return "online"
        }
    }

    func updateStatusCheck(in dot: RoundedEdgePanel, status: String) {
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

    func indexForStatus(_ status: String) -> Int {
        switch status.lowercased() {
        case "online": return 0
        case "away": return 1
        case "dnd": return 2
        case "offline": return 3
        default: return 0
        }
    }

    func selectUserStatus(_ index: Int, dndEndTime: Int64? = nil) {
        let previousStatus = currentUserStatus
        let previousUserId = currentUser?.id ?? ""
        let previousDndEndTime = previousUserId.isEmpty ? nil : dndEndTimeByUser[previousUserId]
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

        if let ws = webService, ws.isLogged() {
            let targetUserId = currentUser?.id ?? ws.currentUserId
            DebugLog.log("selectUserStatus: index=\(index), statStr=\(statStr), targetUserId=\(targetUserId), dndEndTime=\(String(describing: dndEndTime))")
            Task { @MainActor [weak self] in
                do {
                    let updated = try await ws.updateUserStatus(userId: targetUserId, status: statStr, dndEndTime: dndEndTime)
                    DebugLog.log("Successfully updated user status on backend for \(targetUserId) to \(updated.status)")
                } catch {
                    DebugLog.error("Failed to update user status on server: \(error)")
                    guard let self = self else { return }
                    // Roll the optimistic UI back; otherwise it diverges from the server.
                    self.applyCurrentUserStatus(previousStatus)
                    if let previousUserId = previousUserId.isEmpty ? nil : previousUserId {
                        if let previousDndEndTime = previousDndEndTime {
                            self.dndEndTimeByUser[previousUserId] = previousDndEndTime
                        } else {
                            self.dndEndTimeByUser.removeValue(forKey: previousUserId)
                        }
                        self.userStatusById[previousUserId] = previousStatus
                    }
                    self.showInfoAlert("Could not update your status: \(error.localizedDescription)")
                }
            }
        } else {
            DebugLog.warning("selectUserStatus: ws is not logged or nil!")
        }
    }

    func desktopNotificationMode() -> String {
        currentUser?.notify_props?.desktop?.lowercased() ?? "all"
    }

    func desktopNotificationModeLabel() -> String {
        switch desktopNotificationMode() {
        case "none": return "Off"
        case "mention": return "Only mentions"
        default: return "All messages"
        }
    }

    func desktopSoundsEnabled() -> Bool {
        currentUser?.notify_props?.desktop_sound?.lowercased() != "false"
    }

    func updateDesktopNotificationPreferences(_ props: [String: String]) {
        guard let ws = webService, ws.isLogged() else { return }
        let userId = currentUser?.id ?? ws.currentUserId
        guard !userId.isEmpty else { return }
        Task { @MainActor [weak self] in
            guard let self = self else { return }
            do {
                try await ws.updateUserNotifyProps(userId: userId, props: props)
                self.currentUser = try? await ws.fetchCurrentUser()
                self.loadSettingsPanel()
            } catch {
                self.showInfoAlert("Could not update notification settings: \(error.localizedDescription)")
            }
        }
    }

    func cycleDesktopNotificationMode() {
        let next: String
        switch desktopNotificationMode() {
        case "all": next = "mention"
        case "mention": next = "none"
        default: next = "all"
        }
        updateDesktopNotificationPreferences(["desktop": next])
    }

    func toggleDesktopNotificationSound() {
        updateDesktopNotificationPreferences(["desktop_sound": desktopSoundsEnabled() ? "false" : "true"])
    }

    func applyServerCustomStatus(from user: MMUser) {
        guard let raw = user.props?["customStatus"],
              let data = raw.data(using: .utf8),
              let json = try? JSONSerialization.jsonObject(with: data) as? [String: Any] else {
            return
        }
        let text = (json["text"] as? String) ?? ""
        let emoji = (json["emoji"] as? String) ?? ""
        let expiresAtString = json["expires_at"] as? String
        let expiresAt = expiresAtString.flatMap { ISO8601DateFormatter().date(from: $0) }
        if let expiresAt = expiresAt, expiresAt <= Date() {
            clearLocalCustomStatus()
            return
        }
        customStatusText = text
        customStatusEmoji = emoji
        customStatusExpiresAt = expiresAt
        UserDefaults.standard.set(text, forKey: "customStatusText")
        UserDefaults.standard.set(emoji, forKey: "customStatusEmoji")
        if let expiresAt = expiresAt {
            UserDefaults.standard.set(expiresAt.timeIntervalSince1970, forKey: "customStatusExpiresAt")
        } else {
            UserDefaults.standard.removeObject(forKey: "customStatusExpiresAt")
        }
        updateCustomStatusUI()
    }

    func updateCustomStatusUI() {
        guard let row = customStatusMenuRow else { return }
        let label = row.subviews.compactMap { $0 as? NSTextField }.first
        if customStatusText.isEmpty {
            label?.stringValue = "Set custom status"
        } else {
            let glyph = customStatusEmoji.isEmpty ? "" : emojiGlyph(for: customStatusEmoji) + " "
            label?.stringValue = glyph + customStatusText
        }
    }

    func showCustomStatusDialog() {
        let alert = NSAlert()
        alert.messageText = "Set a custom status"
        alert.informativeText = "Let people know what you are up to."
        alert.addButton(withTitle: "Set status")
        alert.addButton(withTitle: "Clear")
        alert.addButton(withTitle: "Cancel")

        let container = NSView(frame: NSRect(x: 0, y: 0, width: 320, height: 92))
        let emojiField = NSTextField(frame: NSRect(x: 0, y: 62, width: 56, height: 24))
        emojiField.placeholderString = "🙂"
        emojiField.stringValue = customStatusEmoji
        let textField = NSTextField(frame: NSRect(x: 64, y: 62, width: 256, height: 24))
        textField.placeholderString = "Status"
        textField.stringValue = customStatusText
        let durationPopup = NSPopUpButton(frame: NSRect(x: 0, y: 24, width: 320, height: 26), pullsDown: false)
        durationPopup.addItems(withTitles: ["Don't clear", "30 minutes", "1 hour", "4 hours", "Today", "This week"])
        container.addSubview(emojiField)
        container.addSubview(textField)
        container.addSubview(durationPopup)
        alert.accessoryView = container

        alert.beginSheetModal(for: self) { [weak self] response in
            guard let self = self else { return }
            if response == .alertFirstButtonReturn {
                self.applyCustomStatus(
                    emoji: emojiField.stringValue.trimmingCharacters(in: .whitespacesAndNewlines),
                    text: textField.stringValue.trimmingCharacters(in: .whitespacesAndNewlines),
                    durationIndex: durationPopup.indexOfSelectedItem
                )
            } else if response == .alertSecondButtonReturn {
                self.unsetCustomStatus()
            }
        }
    }

    func applyCustomStatus(emoji: String, text: String, durationIndex: Int) {
        guard !text.isEmpty else {
            unsetCustomStatus()
            return
        }
        // "" is the server's "don't clear" value; the old `dont_clear` value was
        // rejected by Mattermost and made most custom statuses fail.
        let durations = ["", "thirty_minutes", "one_hour", "four_hours", "today", "this_week"]
        let index = max(0, min(durationIndex, durations.count - 1))
        let targetDate = customStatusTargetDate(for: index)
        let expiresAt = customStatusExpiry(for: index)
        guard let ws = webService else { return }

        Task { @MainActor [weak self] in
            guard let self = self else { return }
            do {
                try await ws.setCustomStatus(emoji: emoji, text: text, duration: durations[index], expiresAt: expiresAt)
                self.customStatusEmoji = emoji
                self.customStatusText = text
                self.customStatusExpiresAt = targetDate
                UserDefaults.standard.set(emoji, forKey: "customStatusEmoji")
                UserDefaults.standard.set(text, forKey: "customStatusText")
                if let targetDate = targetDate {
                    UserDefaults.standard.set(targetDate.timeIntervalSince1970, forKey: "customStatusExpiresAt")
                } else {
                    UserDefaults.standard.removeObject(forKey: "customStatusExpiresAt")
                }
                self.updateCustomStatusUI()
            } catch {
                self.showInfoAlert("Could not set custom status: \(error.localizedDescription)")
            }
        }
    }

    func unsetCustomStatus() {
        guard let ws = webService else { return }
        Task { @MainActor [weak self] in
            guard let self = self else { return }
            _ = try? await ws.clearCustomStatus()
            self.clearLocalCustomStatus()
        }
    }

    func clearLocalCustomStatus() {
        customStatusEmoji = ""
        customStatusText = ""
        customStatusExpiresAt = nil
        UserDefaults.standard.removeObject(forKey: "customStatusEmoji")
        UserDefaults.standard.removeObject(forKey: "customStatusText")
        UserDefaults.standard.removeObject(forKey: "customStatusExpiresAt")
        updateCustomStatusUI()
    }

    /// Clears a local custom status after its server expiry has passed. The
    /// server also expires it; this keeps the menu pill from showing stale text.
    func clearExpiredCustomStatusIfNeeded() {
        guard let expiry = customStatusExpiresAt, expiry <= Date() else { return }
        let text = customStatusText
        clearLocalCustomStatus()
        guard !text.isEmpty, let ws = webService, ws.isLogged() else { return }
        Task { @MainActor in
            _ = try? await ws.clearCustomStatus()
        }
    }

    func customStatusTargetDate(for index: Int) -> Date? {
        let now = Date()
        let calendar = Calendar.current
        switch index {
        case 1: return now.addingTimeInterval(30 * 60)
        case 2: return now.addingTimeInterval(60 * 60)
        case 3: return now.addingTimeInterval(4 * 60 * 60)
        case 4:
            let start = calendar.startOfDay(for: now)
            return calendar.date(byAdding: .day, value: 1, to: start)?.addingTimeInterval(-1)
        case 5:
            // Mattermost's "this week" ends at the end of the current week
            // (Sunday 23:59:59), not seven days from now.
            let start = calendar.startOfDay(for: now)
            let weekday = calendar.component(.weekday, from: start)
            let daysUntilSunday = (8 - weekday) % 7
            return calendar.date(byAdding: .day, value: daysUntilSunday, to: start)?
                .addingTimeInterval(24 * 60 * 60 - 1)
        default:
            return nil
        }
    }

    func customStatusExpiry(for index: Int) -> String? {
        guard let date = customStatusTargetDate(for: index) else { return nil }
        let formatter = ISO8601DateFormatter()
        formatter.formatOptions = [.withInternetDateTime]
        return formatter.string(from: date)
    }

    func normalizedStatus(_ status: String, dndEndTime: Int64?) -> String {
        guard status.lowercased() == "dnd", let end = dndEndTime, end > 0 else { return status }
        // Mattermost returns `dnd_end_time` in seconds, not milliseconds.
        let nowSeconds = Int64(Date().timeIntervalSince1970)
        return end <= nowSeconds ? "online" : status
    }

    func normalizedStatusForKnownUser(_ status: String, userId: String) -> String {
        normalizedStatus(status, dndEndTime: dndEndTimeByUser[userId])
    }

    func applyCurrentUserStatus(_ status: String) {
        currentUserStatus = status
        let idx = indexForStatus(status)
        selectedStatusIndex = idx
        for (i, checkView) in statusCheckViews.enumerated() {
            checkView.isHidden = (i != idx)
        }
        let color = statusColor(for: status)
        statusDotPanel.color = color
        statusDotPanel.setNeedsAppearanceUpdate()
        updateStatusCheck(in: statusDotPanel, status: status)
        menuAvatarStatusDot?.color = color
        menuAvatarStatusDot?.setNeedsAppearanceUpdate()
    }

    func updateChatWidgetUserStatus(userId: String, status: String) {
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

    func fetchAvatarIfNeeded(for userId: String) {
        guard !userId.isEmpty, userAvatarsById[userId] == nil, userAvatarFetchTasks[userId] == nil else { return }
        guard let ws = webService, ws.isLogged() else { return }

        userAvatarFetchTasks[userId] = Task { @MainActor [weak self] in
            defer { self?.userAvatarFetchTasks.removeValue(forKey: userId) }
            do {
                let data = try await ws.fetchUserImage(userId: userId)
                if let img = NSImage(data: data) {
                    self?.userAvatarsById[userId] = img
                    self?.onAvatarLoaded(userId: userId, image: img)
                }
            } catch {
                DebugLog.warning("Failed to fetch user image for \(userId): \(error.localizedDescription)")
            }
        }
    }

    func fetchAvatarForUsernameIfNeeded(_ username: String) {
        let norm = username.lowercased()
        if let u = usersByUsername[norm] {
            fetchAvatarIfNeeded(for: u.id)
            return
        }
        guard let ws = webService, ws.isLogged() else { return }
        Task { @MainActor [weak self] in
            guard let self = self else { return }
            if let user = try? await ws.fetchUserByUsername(norm) {
                self.usersById[user.id] = user
                self.usersByUsername[norm] = user
                self.fetchAvatarIfNeeded(for: user.id)
            }
        }
    }

    func onAvatarLoaded(userId: String, image: NSImage) {
        // 1. Top bar current user profile image
        if let currentId = currentUser?.id, currentId == userId {
            avatarImageView.image = image
            avatarImageView.isHidden = false
            avatarLabel.isHidden = true
            avatarPanel.color = .clear
            avatarPanel.setNeedsAppearanceUpdate()
        }

        // 2. Sidebar items representing this user
        for catIndex in sidebarCategories.indices {
            for itemIndex in sidebarCategories[catIndex].items.indices {
                var item = sidebarCategories[catIndex].items[itemIndex]
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
                    sidebarCategories[catIndex].items[itemIndex] = item
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

    func refreshUserStatuses() {
        guard let ws = webService, ws.isLogged() else { return }
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
                        guard let self = self else { continue }
                        if let end = st.dnd_end_time, end > 0 {
                            self.dndEndTimeByUser[st.user_id] = end
                        }
                        let status = self.normalizedStatus(st.status, dndEndTime: st.dnd_end_time)
                        self.userStatusById[st.user_id] = status
                        self.updateChatWidgetUserStatus(userId: st.user_id, status: status)
                        if st.user_id == self.currentUser?.id, status != st.status {
                            self.applyCurrentUserStatus(status)
                        }
                    }
                } catch {
                    DebugLog.error("refreshUserStatuses REST fetch error: \(error)")
                }
            }
        }
    }

    func preloadDMUsers(for channels: [MMChannel]) async {
        guard let ws = webService, ws.isLogged() else { return }
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
                if let end = st.dnd_end_time, end > 0 {
                    self.dndEndTimeByUser[st.user_id] = end
                }
                let status = self.normalizedStatus(st.status, dndEndTime: st.dnd_end_time)
                self.userStatusById[st.user_id] = status
                self.updateChatWidgetUserStatus(userId: st.user_id, status: status)
            }
        }
        for ch in dmChannels {
            if let targetId = resolveDMTargetUserId(for: ch), let u = usersById[targetId] {
                channelsByName[u.username.lowercased()] = ch
                channelsByName[u.id] = ch
            }
        }
    }

    func refreshSidebarDMTitles() {
        for catIndex in sidebarCategories.indices {
            for itemIndex in sidebarCategories[catIndex].items.indices {
                var item = sidebarCategories[catIndex].items[itemIndex]
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
                sidebarCategories[catIndex].items[itemIndex] = item
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
}
