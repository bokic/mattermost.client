//
//  MainWindow+People.swift
//  mattermost.client
//
//  Split from MainWindow.swift.
//

import AppKit
import Foundation
import UniformTypeIdentifiers

@objc(MMCustomStatusItem)
final class CustomStatusItem: NSObject {
    let emoji: String
    let text: String
    let durationIndex: Int

    init(emoji: String, text: String, durationIndex: Int) {
        self.emoji = emoji
        self.text = text
        self.durationIndex = durationIndex
        super.init()
    }
}

struct QuickEmojiOption {
    let name: String
    let glyph: String
    let label: String
}

@MainActor
final class CustomStatusDialogHelper: NSObject {
    weak var mainWindow: MainWindow?
    weak var emojiField: NSTextField?
    weak var textField: NSTextField?
    weak var durationPopup: NSPopUpButton?
    weak var suggestionsPopup: NSPopUpButton?
    weak var emojiPopup: NSPopUpButton?
    weak var datePicker: NSDatePicker?

    @objc func emojiSelected(_ sender: AnyObject) {
        let menuItem: NSMenuItem?
        if let popup = sender as? NSPopUpButton {
            menuItem = popup.selectedItem
        } else if let item = sender as? NSMenuItem {
            menuItem = item
        } else {
            menuItem = nil
        }
        guard let glyph = menuItem?.representedObject as? String, !glyph.isEmpty else { return }
        emojiField?.stringValue = glyph
        emojiPopup?.selectItem(at: 0)
    }

    @objc func suggestionSelected(_ sender: AnyObject) {
        let menuItem: NSMenuItem?
        if let popup = sender as? NSPopUpButton {
            menuItem = popup.selectedItem
        } else if let item = sender as? NSMenuItem {
            menuItem = item
        } else {
            menuItem = nil
        }
        guard let item = menuItem?.representedObject as? CustomStatusItem else { return }
        let glyph = mainWindow?.emojiGlyph(for: item.emoji) ?? item.emoji
        emojiField?.stringValue = glyph.isEmpty ? item.emoji : glyph
        textField?.stringValue = item.text
        if let durationPopup = durationPopup {
            let maxIdx = durationPopup.numberOfItems - 1
            let validIdx = max(0, min(item.durationIndex, maxIdx))
            durationPopup.selectItem(at: validIdx)
            datePicker?.isHidden = (validIdx != 6)
        }
        suggestionsPopup?.selectItem(at: 0)
    }

    @objc func durationChanged(_ sender: NSPopUpButton) {
        datePicker?.isHidden = (sender.indexOfSelectedItem != 6)
    }
}

extension MainWindow {

    func isBotAccount(_ user: MMUser?) -> Bool {
        guard let user = user else { return false }
        if user.is_bot == true { return true }
        let roles = (user.roles ?? "").lowercased()
            .split(whereSeparator: { $0 == " " || $0 == "," })
            .map(String.init)
        return roles.contains("bot")
    }

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
            return Theme.shared.centerTextPlaceholder
        }
    }

    func statusString(for index: Int) -> String {
        switch index {
        case 0: return "online"
        case 1: return "away"
        case 2: return "dnd"
        case 3: return "offline"
        default: return "offline"
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
        default: return 3
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

    static let presetCustomStatuses: [CustomStatusItem] = [
        CustomStatusItem(emoji: "speech_balloon", text: "Working remotely", durationIndex: 4),
        CustomStatusItem(emoji: "calendar", text: "In a meeting", durationIndex: 2),
        CustomStatusItem(emoji: "face_with_thermometer", text: "Out sick", durationIndex: 4),
        CustomStatusItem(emoji: "beach_umbrella", text: "On vacation", durationIndex: 5),
        CustomStatusItem(emoji: "car", text: "Commuting", durationIndex: 1),
    ]

    static let quickEmojiOptions: [QuickEmojiOption] = [
        QuickEmojiOption(name: "speech_balloon", glyph: "💬", label: "💬 Working remotely"),
        QuickEmojiOption(name: "calendar", glyph: "📅", label: "📅 In a meeting"),
        QuickEmojiOption(name: "beach_umbrella", glyph: "🌴", label: "🌴 Vacation"),
        QuickEmojiOption(name: "face_with_thermometer", glyph: "🤒", label: "🤒 Out sick"),
        QuickEmojiOption(name: "car", glyph: "🚗", label: "🚗 Commuting"),
        QuickEmojiOption(name: "house", glyph: "🏠", label: "🏠 Working from home"),
        QuickEmojiOption(name: "coffee", glyph: "☕️", label: "☕️ Coffee break"),
        QuickEmojiOption(name: "hamburger", glyph: "🍔", label: "🍔 Lunch"),
        QuickEmojiOption(name: "dart", glyph: "🎯", label: "🎯 Focused"),
        QuickEmojiOption(name: "rocket", glyph: "🚀", label: "🚀 Launching"),
        QuickEmojiOption(name: "bulb", glyph: "💡", label: "💡 Ideating"),
        QuickEmojiOption(name: "alarm_clock", glyph: "⏰", label: "⏰ Busy"),
        QuickEmojiOption(name: "headphones", glyph: "🎧", label: "🎧 Listening"),
        QuickEmojiOption(name: "computer", glyph: "💻", label: "💻 Coding"),
        QuickEmojiOption(name: "airplane", glyph: "✈️", label: "✈️ Traveling"),
        QuickEmojiOption(name: "shushing_face", glyph: "🤫", label: "🤫 Deep focus"),
        QuickEmojiOption(name: "slightly_smiling_face", glyph: "🙂", label: "🙂 Available"),
    ]

    func normalizeCustomStatusEmoji(_ raw: String) -> String {
        let trimmed = raw.trimmingCharacters(in: .whitespacesAndNewlines)
        let withoutColons = trimmed.hasPrefix(":") && trimmed.hasSuffix(":") && trimmed.count > 2
            ? String(trimmed.dropFirst().dropLast())
            : trimmed
        if let entry = EmojiCatalog.entries.first(where: { $0.glyph == withoutColons }) {
            return entry.name
        }
        return withoutColons
    }

    func durationLabel(for index: Int) -> String {
        switch index {
        case 1: return L10n.string("30 minutes")
        case 2: return L10n.string("1 hour")
        case 3: return L10n.string("4 hours")
        case 4: return L10n.string("Today")
        case 5: return L10n.string("This week")
        case 6: return "Custom date and time"
        default: return L10n.string("Don't clear")
        }
    }

    func recentCustomStatuses() -> [CustomStatusItem] {
        return settingsStore.recentCustomStatuses.map {
            CustomStatusItem(emoji: $0.emoji, text: $0.text, durationIndex: $0.durationIndex)
        }
    }

    func saveRecentCustomStatus(emoji: String, text: String, durationIndex: Int) {
        settingsStore.saveRecentCustomStatus(emoji: emoji, text: text, durationIndex: durationIndex)
    }

    func applyServerCustomStatus(from user: MMUser) {
        guard let raw = user.props?["customStatus"],
              !raw.isEmpty,
              raw != "{}",
              let data = raw.data(using: .utf8),
              let json = try? JSONSerialization.jsonObject(with: data) as? [String: Any] else {
            clearLocalCustomStatus()
            return
        }
        let text = ((json["text"] as? String) ?? "").trimmingCharacters(in: .whitespacesAndNewlines)
        let emoji = ((json["emoji"] as? String) ?? "").trimmingCharacters(in: .whitespacesAndNewlines)
        if text.isEmpty && emoji.isEmpty {
            clearLocalCustomStatus()
            return
        }
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

    func refreshCustomStatus() {
        guard let ws = webService, ws.isLogged() else { return }
        Task { @MainActor [weak self] in
            guard let self = self else { return }
            do {
                let me = try await ws.fetchCurrentUser()
                self.currentUser = me
                self.applyServerCustomStatus(from: me)
            } catch {
                DebugLog.warning("refreshCustomStatus failed: \(error)")
            }
        }
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
        alert.messageText = L10n.string("Set a custom status")
        alert.informativeText = L10n.string("Let people know what you are up to.")
        alert.addButton(withTitle: L10n.string("Set status"))
        alert.addButton(withTitle: L10n.string("Clear"))
        alert.addButton(withTitle: L10n.string("Cancel"))

        let container = NSView(frame: NSRect(x: 0, y: 0, width: 320, height: 146))

        let helper = CustomStatusDialogHelper()
        helper.mainWindow = self
        self.customStatusDialogHelper = helper

        let emojiPopup = NSPopUpButton(frame: NSRect(x: 0, y: 116, width: 44, height: 26), pullsDown: true)
        let emojiMenu = NSMenu()
        let emojiHeader = NSMenuItem(title: "😀", action: nil, keyEquivalent: "")
        emojiMenu.addItem(emojiHeader)
        for opt in Self.quickEmojiOptions {
            let item = NSMenuItem(
                title: opt.label,
                action: #selector(CustomStatusDialogHelper.emojiSelected(_:)),
                keyEquivalent: ""
            )
            item.target = helper
            item.representedObject = opt.glyph
            emojiMenu.addItem(item)
        }
        emojiPopup.menu = emojiMenu
        emojiPopup.target = helper
        emojiPopup.action = #selector(CustomStatusDialogHelper.emojiSelected(_:))

        let emojiField = NSTextField(frame: NSRect(x: 48, y: 116, width: 44, height: 24))
        emojiField.placeholderString = "🙂"
        emojiField.stringValue = customStatusEmoji.isEmpty ? "" : emojiGlyph(for: customStatusEmoji)

        let textField = NSTextField(frame: NSRect(x: 96, y: 116, width: 224, height: 24))
        textField.placeholderString = L10n.string("What is your status?")
        textField.stringValue = customStatusText

        let suggestionsPopup = NSPopUpButton(frame: NSRect(x: 0, y: 78, width: 320, height: 26), pullsDown: true)
        let suggestionsMenu = NSMenu()
        let suggestionsHeader = NSMenuItem(title: L10n.string("Suggestions & recent statuses…"), action: nil, keyEquivalent: "")
        suggestionsMenu.addItem(suggestionsHeader)
        for preset in Self.presetCustomStatuses {
            let glyph = emojiGlyph(for: preset.emoji)
            let item = NSMenuItem(
                title: "\(glyph)  \(preset.text) — \(durationLabel(for: preset.durationIndex))",
                action: #selector(CustomStatusDialogHelper.suggestionSelected(_:)),
                keyEquivalent: ""
            )
            item.target = helper
            item.representedObject = preset
            suggestionsMenu.addItem(item)
        }
        let recents = recentCustomStatuses()
        if !recents.isEmpty {
            suggestionsMenu.addItem(NSMenuItem.separator())
            let recentsHeader = NSMenuItem(title: L10n.string("Recent statuses"), action: nil, keyEquivalent: "")
            recentsHeader.isEnabled = false
            suggestionsMenu.addItem(recentsHeader)
            for recent in recents {
                let glyph = emojiGlyph(for: recent.emoji)
                let item = NSMenuItem(
                    title: "\(glyph)  \(recent.text) — \(durationLabel(for: recent.durationIndex))",
                    action: #selector(CustomStatusDialogHelper.suggestionSelected(_:)),
                    keyEquivalent: ""
                )
                item.target = helper
                item.representedObject = recent
                suggestionsMenu.addItem(item)
            }
        }
        suggestionsPopup.menu = suggestionsMenu
        suggestionsPopup.target = helper
        suggestionsPopup.action = #selector(CustomStatusDialogHelper.suggestionSelected(_:))

        let durationPopup = NSPopUpButton(frame: NSRect(x: 0, y: 40, width: 320, height: 26), pullsDown: false)
        durationPopup.addItems(withTitles: [
            L10n.string("Don't clear"),
            L10n.string("30 minutes"),
            L10n.string("1 hour"),
            L10n.string("4 hours"),
            L10n.string("Today"),
            L10n.string("This week"),
            "Custom date and time…",
        ])
        durationPopup.target = helper
        durationPopup.action = #selector(CustomStatusDialogHelper.durationChanged(_:))

        let datePicker = NSDatePicker(frame: NSRect(x: 0, y: 2, width: 320, height: 28))
        datePicker.datePickerStyle = .textFieldAndStepper
        datePicker.datePickerElements = [.yearMonthDay, .hourMinute]
        datePicker.minDate = Date()

        if let expiry = customStatusExpiresAt, expiry > Date() {
            durationPopup.selectItem(at: 6)
            datePicker.dateValue = expiry
            datePicker.isHidden = false
        } else {
            durationPopup.selectItem(at: 0)
            datePicker.dateValue = Date().addingTimeInterval(3600)
            datePicker.isHidden = true
        }

        helper.emojiField = emojiField
        helper.textField = textField
        helper.durationPopup = durationPopup
        helper.suggestionsPopup = suggestionsPopup
        helper.emojiPopup = emojiPopup
        helper.datePicker = datePicker

        container.addSubview(emojiPopup)
        container.addSubview(emojiField)
        container.addSubview(textField)
        container.addSubview(suggestionsPopup)
        container.addSubview(durationPopup)
        container.addSubview(datePicker)
        alert.accessoryView = container

        alert.beginSheetModal(for: self) { [weak self] response in
            guard let self = self else { return }
            self.customStatusDialogHelper = nil
            if response == .alertFirstButtonReturn {
                let customDate = (durationPopup.indexOfSelectedItem == 6) ? datePicker.dateValue : nil
                self.applyCustomStatus(
                    emoji: emojiField.stringValue.trimmingCharacters(in: .whitespacesAndNewlines),
                    text: textField.stringValue.trimmingCharacters(in: .whitespacesAndNewlines),
                    durationIndex: durationPopup.indexOfSelectedItem,
                    customDate: customDate
                )
            } else if response == .alertSecondButtonReturn {
                self.unsetCustomStatus()
            }
        }
    }

    func applyCustomStatus(emoji: String, text: String, durationIndex: Int, customDate: Date? = nil) {
        guard !text.isEmpty else {
            unsetCustomStatus()
            return
        }
        let normalizedEmoji = normalizeCustomStatusEmoji(emoji)
        let durations = ["", "thirty_minutes", "one_hour", "four_hours", "today", "this_week", "date_and_time"]
        let index = max(0, min(durationIndex, durations.count - 1))
        let targetDate = customStatusTargetDate(for: index, customDate: customDate)
        let expiresAt = customStatusExpiry(for: index, customDate: customDate)
        guard let ws = webService else {
            customStatusEmoji = normalizedEmoji
            customStatusText = text
            customStatusExpiresAt = targetDate
            UserDefaults.standard.set(normalizedEmoji, forKey: "customStatusEmoji")
            UserDefaults.standard.set(text, forKey: "customStatusText")
            if let targetDate = targetDate {
                UserDefaults.standard.set(targetDate.timeIntervalSince1970, forKey: "customStatusExpiresAt")
            } else {
                UserDefaults.standard.removeObject(forKey: "customStatusExpiresAt")
            }
            saveRecentCustomStatus(emoji: normalizedEmoji, text: text, durationIndex: index)
            updateCustomStatusUI()
            return
        }

        Task { @MainActor [weak self] in
            guard let self = self else { return }
            do {
                try await ws.setCustomStatus(
                    emoji: normalizedEmoji,
                    text: text,
                    duration: durations[index],
                    expiresAt: expiresAt
                )
                self.customStatusEmoji = normalizedEmoji
                self.customStatusText = text
                self.customStatusExpiresAt = targetDate
                UserDefaults.standard.set(normalizedEmoji, forKey: "customStatusEmoji")
                UserDefaults.standard.set(text, forKey: "customStatusText")
                if let targetDate = targetDate {
                    UserDefaults.standard.set(targetDate.timeIntervalSince1970, forKey: "customStatusExpiresAt")
                } else {
                    UserDefaults.standard.removeObject(forKey: "customStatusExpiresAt")
                }
                self.saveRecentCustomStatus(emoji: normalizedEmoji, text: text, durationIndex: index)
                self.updateCustomStatusUI()
            } catch {
                self.showInfoAlert("Could not set custom status: \(error.localizedDescription)")
            }
        }
    }

    func unsetCustomStatus() {
        guard let ws = webService else {
            clearLocalCustomStatus()
            return
        }
        Task { @MainActor [weak self] in
            guard let self = self else { return }
            do {
                try await ws.clearCustomStatus()
                self.clearLocalCustomStatus()
            } catch {
                self.showInfoAlert("Could not clear custom status: \(error.localizedDescription)")
            }
        }
    }

    func clearLocalCustomStatus() {
        settingsStore.clearCustomStatus()
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

    func customStatusTargetDate(for index: Int, customDate: Date? = nil) -> Date? {
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
        case 6:
            return customDate
        default:
            return nil
        }
    }

    func customStatusExpiry(for index: Int, customDate: Date? = nil) -> String? {
        guard let date = customStatusTargetDate(for: index, customDate: customDate) else { return nil }
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
            applyCurrentUserStatus(status)
        }

        var candidateDots: [RoundedEdgePanel] = []
        candidateDots.append(contentsOf: statusDots(for: userId))
        if isForCurrent {
            candidateDots.append(contentsOf: statusDots(for: "statusDot_currentUser"))
            if let currentId = currentUser?.id, currentId != userId {
                candidateDots.append(contentsOf: statusDots(for: currentId))
            }
        }

        var seen = Set<ObjectIdentifier>()
        var updatedCount = 0
        for dotPanel in candidateDots {
            guard seen.insert(ObjectIdentifier(dotPanel)).inserted, dotPanel.superview != nil else { continue }
            dotPanel.color = color
            dotPanel.setNeedsAppearanceUpdate()
            updateStatusCheck(in: dotPanel, status: status)
            updatedCount += 1
        }
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

        // 1b. Profile popover avatar if open for this user
        if isProfilePopoverOpen && activeProfileUserId == userId {
            updateProfilePopoverAvatar(image: image)
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

        // 4. Message rows: update the existing avatar views in place instead of
        // rebuilding the whole timeline for every avatar completion.
        updateTimelineAvatar(userId: userId, image: image)
    }

    func refreshUserStatuses(forceRest: Bool = false) {
        guard let ws = webService, ws.isLogged() else { return }
        if ws.isWebSocketConnected && !forceRest {
            DebugLog.log("refreshUserStatuses: WS connected, requesting via WS get_statuses")
            ws.requestStatuses()
            return
        }
        batchFetchUserStatusesViaREST(force: forceRest)
    }

    func batchFetchUserStatusesViaREST(userIds: [String]? = nil, force: Bool = false) {
        guard let ws = webService, ws.isLogged() else { return }
        guard !isFetchingStatusesViaREST else {
            DebugLog.log("batchFetchUserStatusesViaREST: already in progress, skipping")
            return
        }

        let now = Date()
        if !force && now.timeIntervalSince(lastRESTStatusPollTime) < 30.0 {
            DebugLog.log("batchFetchUserStatusesViaREST: throttled, skipping")
            return
        }

        let targetIds: [String]
        if let userIds = userIds {
            targetIds = Array(Set(userIds.filter { isLikelyMattermostId($0) }))
        } else {
            targetIds = Array(Set(usersById.keys.filter { isLikelyMattermostId($0) }))
        }

        guard !targetIds.isEmpty else { return }

        isFetchingStatusesViaREST = true
        lastRESTStatusPollTime = now
        DebugLog.log("batchFetchUserStatusesViaREST: fetching REST statuses for \(targetIds.count) users")

        Task { @MainActor [weak self] in
            defer { self?.isFetchingStatusesViaREST = false }
            guard let self = self, let ws = self.webService else { return }

            let batchSize = 100
            for startIdx in stride(from: 0, to: targetIds.count, by: batchSize) {
                let endIdx = min(startIdx + batchSize, targetIds.count)
                let chunk = Array(targetIds[startIdx..<endIdx])
                do {
                    let statuses = try await ws.fetchUserStatuses(userIds: chunk)
                    DebugLog.log("batchFetchUserStatusesViaREST: received \(statuses.count) statuses")
                    for st in statuses {
                        if let end = st.dnd_end_time, end > 0 {
                            self.dndEndTimeByUser[st.user_id] = end
                        }
                        let status = self.normalizedStatus(st.status, dndEndTime: st.dnd_end_time)
                        let oldStatus = self.userStatusById[st.user_id]
                        self.userStatusById[st.user_id] = status
                        if oldStatus != status {
                            self.updateChatWidgetUserStatus(userId: st.user_id, status: status)
                            if st.user_id == self.currentUser?.id {
                                self.applyCurrentUserStatus(status)
                            }
                        }
                    }
                } catch {
                    DebugLog.error("batchFetchUserStatusesViaREST chunk error: \(error)")
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
        let unknownTargetIds = allTargetIds.filter { self.userStatusById[$0] == nil }
        if !unknownTargetIds.isEmpty {
            if ws.isWebSocketConnected {
                ws.requestStatusesByIds(unknownTargetIds)
            } else if let statuses = try? await ws.fetchUserStatuses(userIds: unknownTargetIds) {
                for st in statuses {
                    if let end = st.dnd_end_time, end > 0 {
                        self.dndEndTimeByUser[st.user_id] = end
                    }
                    let status = self.normalizedStatus(st.status, dndEndTime: st.dnd_end_time)
                    let oldStatus = self.userStatusById[st.user_id]
                    self.userStatusById[st.user_id] = status
                    if oldStatus != status {
                        self.updateChatWidgetUserStatus(userId: st.user_id, status: status)
                    }
                }
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

    // MARK: - User Profile View

    func setupProfilePopover() {
        profilePopoverPanel.color = Theme.shared.centerBg
        profilePopoverPanel.cornerRadius = MMRadius.panel
        profilePopoverPanel.borderWidth = 1
        profilePopoverPanel.borderColor = Theme.shared.divider
        profilePopoverPanel.shadowColor = .black
        profilePopoverPanel.shadowOpacity = 0.22
        profilePopoverPanel.shadowRadius = 14
        profilePopoverPanel.shadowOffset = CGSize(width: 0, height: -4)
        profilePopoverPanel.isHidden = true
        profilePopoverPanel.appearance = NSAppearance(named: Theme.shared.isDark ? .darkAqua : .aqua)
        contentView?.addSubview(profilePopoverPanel)
    }

    func showUserProfile(user: MMUser, from sourceView: NSView? = nil) {
        if isProfilePopoverOpen && activeProfileUserId == user.id {
            closeProfilePopover()
            return
        }
        if isStatusMenuOpen { setStatusMenuOpen(false) }
        if isProductMenuOpen { setProductSwitcherMenuOpen(false) }
        if isHelpMenuOpen { setHelpMenuOpen(false) }
        if isTeamMenuOpen { setTeamMenuOpen(false) }
        if isChannelMenuOpen { closeChannelMenu() }
        if isDMPickerOpen { closeDMPicker() }

        if profilePopoverPanel.superview == nil {
            setupProfilePopover()
        }

        activeProfileUserId = user.id
        renderUserProfileContent(for: user)
        positionProfilePopover(from: sourceView)

        profilePopoverPanel.isHidden = false
        contentView?.addSubview(profilePopoverPanel)
        isProfilePopoverOpen = true
    }

    func showUserProfile(userId: String, from sourceView: NSView? = nil) {
        if let user = usersById[userId] {
            showUserProfile(user: user, from: sourceView)
            return
        }
        guard let ws = webService, ws.isLogged() else { return }
        Task { @MainActor [weak self] in
            guard let self = self else { return }
            do {
                let user = try await ws.fetchUser(userId: userId)
                self.usersById[user.id] = user
                self.usersByUsername[user.username.lowercased()] = user
                self.showUserProfile(user: user, from: sourceView)
            } catch {
                DebugLog.warning("Could not fetch user for profile: \(error)")
            }
        }
    }

    func closeProfilePopover() {
        guard isProfilePopoverOpen else { return }
        profilePopoverPanel.isHidden = true
        isProfilePopoverOpen = false
        activeProfileUserId = nil
        profileAnchorFrame = .zero
    }

    func updateProfilePopoverAvatar(image: NSImage) {
        for subview in profilePopoverPanel.subviews {
            if let circle = subview as? RoundedEdgePanel, circle.bounds.width == 60 {
                circle.color = .clear
                circle.subviews.forEach { $0.removeFromSuperview() }
                let iv = NSImageView(frame: circle.bounds)
                iv.image = image
                iv.imageScaling = .scaleProportionallyUpOrDown
                circle.addSubview(iv)
                circle.setNeedsAppearanceUpdate()
                break
            }
        }
    }

    func positionProfilePopover(from sourceView: NSView?) {
        guard let contentView = contentView else { return }
        let panelWidth = profilePopoverPanel.frame.width
        let panelHeight = profilePopoverPanel.frame.height
        let containerBounds = contentView.bounds
        let margin: CGFloat = 12

        if let sourceView = sourceView, sourceView.window != nil {
            let anchorInWindow = sourceView.convert(sourceView.bounds, to: nil)
            let anchor = contentView.convert(anchorInWindow, from: nil)
            profileAnchorFrame = anchor

            var x: CGFloat
            if anchor.maxX + panelWidth + margin <= containerBounds.maxX {
                x = anchor.maxX + 8
            } else if anchor.minX - panelWidth - 8 >= margin {
                x = anchor.minX - panelWidth - 8
            } else {
                x = min(max(margin, anchor.midX - panelWidth / 2), containerBounds.maxX - panelWidth - margin)
            }

            var y: CGFloat
            if anchor.maxY - panelHeight >= margin {
                y = anchor.maxY - panelHeight
            } else {
                y = min(max(margin, anchor.minY), containerBounds.maxY - panelHeight - margin)
            }

            x = min(max(margin, x), containerBounds.maxX - panelWidth - margin)
            y = min(max(margin, y), containerBounds.maxY - panelHeight - margin)
            profilePopoverPanel.frame = NSRect(x: x, y: y, width: panelWidth, height: panelHeight)
        } else {
            profileAnchorFrame = .zero
            let x = round((containerBounds.width - panelWidth) / 2)
            let y = round((containerBounds.height - panelHeight) / 2)
            profilePopoverPanel.frame = NSRect(x: max(margin, x), y: max(margin, y), width: panelWidth, height: panelHeight)
        }
    }

    func renderUserProfileContent(for user: MMUser) {
        profilePopoverPanel.subviews.forEach { $0.removeFromSuperview() }

        let width: CGFloat = 320
        let padding: CGFloat = 16

        // 1. Close button (xmark) in upper right
        let closeButton = RoundedEdgePanel()
        closeButton.cornerRadius = 11
        closeButton.color = .clear
        let closeSize: CGFloat = 22
        let closeIcon = NSImageView(frame: NSRect(x: 4, y: 4, width: 14, height: 14))
        if let xmarkImg = NSImage(systemSymbolName: "xmark", accessibilityDescription: "Close") {
            closeIcon.image = xmarkImg.withSymbolConfiguration(.init(pointSize: 11, weight: .semibold))
            closeIcon.contentTintColor = Theme.shared.centerTextMuted
        }
        closeButton.addSubview(closeIcon)
        closeButton.onHoverChanged = { [weak closeButton] isHovered in
            closeButton?.color = isHovered ? Theme.shared.centerHover : .clear
            closeButton?.setNeedsAppearanceUpdate()
        }
        closeButton.onClick = { [weak self] in
            self?.closeProfilePopover()
        }
        closeButton.accessibilityTitle = "Close"
        profilePopoverPanel.addSubview(closeButton)

        // 2. Avatar
        let avatarSize: CGFloat = 60
        let avatarCircle = RoundedEdgePanel()
        avatarCircle.cornerRadius = avatarSize / 2
        avatarCircle.color = MMPalette.avatarColor(for: user.id.isEmpty ? user.username : user.id)
        avatarCircle.frame = NSRect(x: padding, y: 0, width: avatarSize, height: avatarSize)

        if let cachedImg = userAvatarsById[user.id] {
            avatarCircle.color = .clear
            let iv = NSImageView(frame: avatarCircle.bounds)
            iv.image = cachedImg
            iv.imageScaling = .scaleProportionallyUpOrDown
            avatarCircle.addSubview(iv)
        } else {
            let initial = (user.first_name?.first ?? user.username.first).map { String($0).uppercased() } ?? "U"
            let initialLabel = NSTextField(labelWithString: initial)
            initialLabel.font = MMFont.font(ofSize: 22, weight: .semibold)
            initialLabel.textColor = .white
            initialLabel.alignment = .center
            initialLabel.isEditable = false
            initialLabel.isSelectable = false
            initialLabel.frame = NSRect(x: 0, y: (avatarSize - 28) / 2, width: avatarSize, height: 28)
            avatarCircle.addSubview(initialLabel)
            fetchAvatarIfNeeded(for: user.id)
        }
        profilePopoverPanel.addSubview(avatarCircle)

        // 3. Presence dot on avatar
        let isCurrent = (user.id == currentUser?.id || user.id == "usr" || user.id == "sample_usr")
        let statStr = isCurrent ? currentUserStatus : (userStatusById[user.id] ?? "offline")
        let dotColor = statusColor(for: statStr)
        let presenceDot = RoundedEdgePanel()
        presenceDot.cornerRadius = 8
        presenceDot.color = dotColor
        presenceDot.borderColor = Theme.shared.centerBg
        presenceDot.borderWidth = 2
        presenceDot.frame = NSRect(x: padding + avatarSize - 16, y: 0, width: 16, height: 16)
        updateStatusCheck(in: presenceDot, status: statStr)
        registerStatusDot(presenceDot, for: user.id)
        if isCurrent {
            registerStatusDot(presenceDot, for: "statusDot_currentUser")
        }
        profilePopoverPanel.addSubview(presenceDot)

        // 4. Header text (Full name, @username, badge)
        let fullName = [user.first_name, user.last_name]
            .compactMap { $0?.trimmingCharacters(in: .whitespacesAndNewlines) }
            .filter { !$0.isEmpty }
            .joined(separator: " ")
        let displayName = fullName.isEmpty ? user.username : fullName

        let nameLabel = NSTextField(labelWithString: displayName)
        nameLabel.font = MMFont.font(ofSize: 16, weight: .bold)
        nameLabel.textColor = Theme.shared.centerText
        nameLabel.lineBreakMode = .byTruncatingTail
        nameLabel.isEditable = false
        nameLabel.isSelectable = true
        profilePopoverPanel.addSubview(nameLabel)

        let usernameLabel = NSTextField(labelWithString: "@\(user.username)")
        usernameLabel.font = MMFont.font(ofSize: 13, weight: .regular)
        usernameLabel.textColor = Theme.shared.centerTextMuted
        usernameLabel.lineBreakMode = .byTruncatingTail
        usernameLabel.isEditable = false
        usernameLabel.isSelectable = true
        profilePopoverPanel.addSubview(usernameLabel)

        var roleBadge: RoundedEdgePanel? = nil
        if let roleTitle = displayRoleName(for: user) {
            let badge = RoundedEdgePanel()
            badge.cornerRadius = 4
            badge.color = Theme.shared.centerText.withAlphaComponent(0.08)
            let badgeLabel = NSTextField(labelWithString: roleTitle)
            let bFont = MMFont.font(ofSize: 10, weight: .bold)
            badgeLabel.font = bFont
            badgeLabel.textColor = Theme.shared.centerTextMuted
            badgeLabel.alignment = .center
            badgeLabel.isEditable = false
            badgeLabel.isSelectable = false
            let badgeWidth = (roleTitle as NSString).size(withAttributes: [.font: bFont]).width + 10
            badge.frame = NSRect(x: 0, y: 0, width: ceil(badgeWidth), height: 16)
            badgeLabel.frame = NSRect(x: 0, y: 1, width: badge.frame.width, height: 14)
            badge.addSubview(badgeLabel)
            roleBadge = badge
            profilePopoverPanel.addSubview(badge)
        }

        // Info items list
        var infoItems: [(icon: String, text: String)] = []

        if let custom = userCustomStatus(for: user) {
            let glyph = custom.emoji.isEmpty ? "💬" : (MainWindow.emojiGlyphs[custom.emoji] ?? emojiGlyph(for: custom.emoji))
            let text = [glyph, custom.text].filter { !$0.isEmpty }.joined(separator: " ")
            infoItems.append(("quote.bubble", text))
        }
        let statusTitle = statStr.capitalized
        infoItems.append(("circle.fill", statusTitle))

        if let position = user.position?.trimmingCharacters(in: .whitespacesAndNewlines), !position.isEmpty {
            infoItems.append(("briefcase", position))
        }

        if let nickname = user.nickname?.trimmingCharacters(in: .whitespacesAndNewlines), !nickname.isEmpty {
            infoItems.append(("person.text.rectangle", nickname))
        }

        if let email = user.email?.trimmingCharacters(in: .whitespacesAndNewlines), !email.isEmpty {
            infoItems.append(("envelope", email))
        }

        if let localTime = Self.formattedLocalTime(for: user.timezone) {
            infoItems.append(("clock", "Local time: \(localTime.timeString) (\(localTime.tzName))"))
        }

        // Bottom Action buttons
        let buttonY = padding
        let buttonWidth = (width - padding * 2 - 8) / 2
        let buttonHeight: CGFloat = 32

        // "Message" button
        let messageBtn = RoundedEdgePanel()
        messageBtn.cornerRadius = MMRadius.control
        messageBtn.color = Theme.shared.buttonBg
        messageBtn.frame = NSRect(x: padding, y: buttonY, width: buttonWidth, height: buttonHeight)
        let msgLabel = NSTextField(labelWithString: "Message")
        msgLabel.font = MMFont.font(ofSize: 13, weight: .semibold)
        msgLabel.textColor = .white
        msgLabel.alignment = .center
        msgLabel.isEditable = false
        msgLabel.isSelectable = false
        msgLabel.frame = NSRect(x: 4, y: 7, width: buttonWidth - 8, height: 18)
        messageBtn.addSubview(msgLabel)
        messageBtn.onHoverChanged = { [weak messageBtn] isHovered in
            messageBtn?.color = isHovered ? Theme.shared.buttonBg.withAlphaComponent(0.85) : Theme.shared.buttonBg
            messageBtn?.setNeedsAppearanceUpdate()
        }
        messageBtn.onClick = { [weak self] in
            guard let self = self else { return }
            self.closeProfilePopover()
            self.startDirectMessage(with: user)
        }
        messageBtn.accessibilityTitle = "Message"
        profilePopoverPanel.addSubview(messageBtn)

        // "Copy username" button
        let copyBtn = RoundedEdgePanel()
        copyBtn.cornerRadius = MMRadius.control
        copyBtn.color = Theme.shared.centerText.withAlphaComponent(0.06)
        copyBtn.borderColor = Theme.shared.divider
        copyBtn.borderWidth = 1
        copyBtn.frame = NSRect(x: padding + buttonWidth + 8, y: buttonY, width: buttonWidth, height: buttonHeight)
        let copyLabel = NSTextField(labelWithString: "Copy username")
        copyLabel.font = MMFont.font(ofSize: 12, weight: .medium)
        copyLabel.textColor = Theme.shared.centerText
        copyLabel.alignment = .center
        copyLabel.isEditable = false
        copyLabel.isSelectable = false
        copyLabel.frame = NSRect(x: 4, y: 7, width: buttonWidth - 8, height: 18)
        copyBtn.addSubview(copyLabel)
        copyBtn.onHoverChanged = { [weak copyBtn] isHovered in
            copyBtn?.color = isHovered ? Theme.shared.centerHover : Theme.shared.centerText.withAlphaComponent(0.06)
            copyBtn?.setNeedsAppearanceUpdate()
        }
        copyBtn.onClick = { [weak self, weak copyLabel] in
            guard let self = self else { return }
            _ = self
            let pasteboard = NSPasteboard.general
            pasteboard.clearContents()
            pasteboard.setString("@\(user.username)", forType: .string)
            copyLabel?.stringValue = "Copied!"
            DispatchQueue.main.asyncAfter(deadline: .now() + 1.5) { [weak copyLabel] in
                copyLabel?.stringValue = "Copy username"
            }
        }
        copyBtn.accessibilityTitle = "Copy username"
        profilePopoverPanel.addSubview(copyBtn)

        var curY = buttonY + buttonHeight + 14

        // Divider above buttons
        let bottomDivider = RoundedEdgePanel()
        bottomDivider.cornerRadius = 0
        bottomDivider.color = Theme.shared.divider
        bottomDivider.frame = NSRect(x: padding, y: curY, width: width - padding * 2, height: 1)
        profilePopoverPanel.addSubview(bottomDivider)
        curY += 10

        // Info rows (bottom to top)
        for item in infoItems.reversed() {
            let rowView = NSView(frame: NSRect(x: padding, y: curY, width: width - padding * 2, height: 22))
            let iconView = NSImageView(frame: NSRect(x: 0, y: 3, width: 16, height: 16))
            if item.icon == "circle.fill" {
                if let dotImg = NSImage(systemSymbolName: "circle.fill", accessibilityDescription: nil) {
                    iconView.image = dotImg.withSymbolConfiguration(.init(pointSize: 9, weight: .bold))
                    iconView.contentTintColor = dotColor
                }
            } else if let img = NSImage(systemSymbolName: item.icon, accessibilityDescription: nil) {
                iconView.image = img.withSymbolConfiguration(.init(pointSize: 12, weight: .regular))
                iconView.contentTintColor = Theme.shared.centerTextMuted
            }
            rowView.addSubview(iconView)

            let label = NSTextField(labelWithString: item.text)
            label.font = MMFont.font(ofSize: 12.5)
            label.textColor = Theme.shared.centerText
            label.lineBreakMode = .byTruncatingTail
            label.isEditable = false
            label.isSelectable = true
            label.frame = NSRect(x: 24, y: 2, width: width - padding * 2 - 24, height: 18)
            rowView.addSubview(label)

            profilePopoverPanel.addSubview(rowView)
            curY += 24
        }

        curY += 4

        // Divider above info rows
        let topDivider = RoundedEdgePanel()
        topDivider.cornerRadius = 0
        topDivider.color = Theme.shared.divider
        topDivider.frame = NSRect(x: padding, y: curY, width: width - padding * 2, height: 1)
        profilePopoverPanel.addSubview(topDivider)
        curY += 14

        // Header section positioning
        let headerY = curY
        let textX = padding + avatarSize + 12
        let textWidth = width - textX - padding - closeSize

        avatarCircle.frame.origin.y = headerY + (60 - avatarSize) / 2
        presenceDot.frame.origin.y = avatarCircle.frame.origin.y - 1

        let nameSize = (displayName as NSString).size(withAttributes: [.font: nameLabel.font!])
        let badgeWidth = roleBadge?.frame.width ?? 0
        let availableNameW = badgeWidth > 0 ? textWidth - badgeWidth - 6 : textWidth
        let nameW = min(ceil(nameSize.width), availableNameW)

        nameLabel.frame = NSRect(x: textX, y: headerY + 34, width: nameW, height: 20)
        if let badge = roleBadge {
            badge.frame.origin = CGPoint(x: textX + nameW + 6, y: headerY + 36)
        }
        usernameLabel.frame = NSRect(x: textX, y: headerY + 12, width: textWidth, height: 18)

        let totalHeight = headerY + 64 + padding
        closeButton.frame = NSRect(x: width - padding - closeSize + 4, y: totalHeight - padding - closeSize + 4, width: closeSize, height: closeSize)

        profilePopoverPanel.frame = NSRect(x: 0, y: 0, width: width, height: totalHeight)
    }

    static func formattedLocalTime(for timezone: MMUser.MMTimeZone?) -> (timeString: String, tzName: String)? {
        guard let tz = timezone else { return nil }
        let tzIdentifier: String? = {
            if tz.useAutomaticTimezone == "true", let auto = tz.automaticTimezone, !auto.isEmpty {
                return auto
            }
            if let manual = tz.manualTimezone, !manual.isEmpty {
                return manual
            }
            if let auto = tz.automaticTimezone, !auto.isEmpty {
                return auto
            }
            return nil
        }()
        guard let id = tzIdentifier, !id.isEmpty, let timeZone = TimeZone(identifier: id) else { return nil }
        let formatter = DateFormatter()
        formatter.timeZone = timeZone
        formatter.dateFormat = "h:mm a"
        let timeString = formatter.string(from: Date())
        let tzName = timeZone.abbreviation() ?? id
        return (timeString, tzName)
    }

    func displayRoleName(for user: MMUser) -> String? {
        if isBotAccount(user) { return "BOT" }
        let roles = (user.roles ?? "").lowercased()
        if roles.contains("system_admin") { return "SYSTEM ADMIN" }
        if roles.contains("team_admin") { return "TEAM ADMIN" }
        if roles.contains("channel_admin") { return "CHANNEL ADMIN" }
        if roles.contains("guest") { return "GUEST" }
        return nil
    }

    func userCustomStatus(for user: MMUser) -> (emoji: String, text: String)? {
        if user.id == currentUser?.id || user.id == "usr" || user.id == "sample_usr" {
            if let expiry = customStatusExpiresAt, expiry <= Date() {
                return nil
            }
            if !customStatusText.isEmpty || !customStatusEmoji.isEmpty {
                return (customStatusEmoji, customStatusText)
            }
        }
        guard let raw = user.props?["customStatus"],
              let data = raw.data(using: .utf8),
              let json = try? JSONSerialization.jsonObject(with: data) as? [String: Any] else {
            return nil
        }
        let text = (json["text"] as? String) ?? ""
        let emoji = (json["emoji"] as? String) ?? ""
        if let expiresAtString = json["expires_at"] as? String,
           let expiresAt = ISO8601DateFormatter().date(from: expiresAtString),
           expiresAt <= Date() {
            return nil
        }
        if text.isEmpty && emoji.isEmpty { return nil }
        return (emoji, text)
    }
}
