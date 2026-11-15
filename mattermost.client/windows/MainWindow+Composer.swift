//
//  MainWindow+Composer.swift
//  mattermost.client
//
//  Split from MainWindow.swift.
//

import AppKit
import Foundation
import UniformTypeIdentifiers

extension MainWindow {

    func setupEmojiPanel() {
        emojiPanel.color = Theme.shared.centerBg
        emojiPanel.cornerRadius = MMRadius.control
        emojiPanel.borderWidth = 1
        emojiPanel.borderColor = Theme.shared.centerText.withAlphaComponent(0.2)
        emojiPanel.shadowColor = .black
        emojiPanel.shadowOpacity = 0.12
        emojiPanel.shadowRadius = 24
        emojiPanel.shadowOffset = CGSize(width: 0, height: -8)
        emojiPanel.clipContentToBounds = true
        emojiPanel.isHidden = true
        let emojiAppearance = NSAppearance(named: Theme.shared.isDark ? .darkAqua : .aqua)
        emojiPanel.appearance = emojiAppearance

        emojiSearchField.placeholderString = "Search"
        emojiSearchField.font = MMFont.font(ofSize: 13)
        emojiSearchField.delegate = self
        emojiSearchField.sendsSearchStringImmediately = true
        emojiSearchField.appearance = emojiAppearance
        emojiPanel.addSubview(emojiSearchField)

        emojiCategoryBar.frame = NSRect(x: 0, y: 366, width: 350, height: 28)
        emojiPanel.addSubview(emojiCategoryBar)

        emojiScroll.drawsBackground = false
        emojiScroll.hasVerticalScroller = true
        emojiScroll.autohidesScrollers = true
        emojiScroll.documentView = emojiDoc
        emojiScroll.frame = NSRect(x: 0, y: 0, width: 350, height: 358)
        emojiPanel.addSubview(emojiScroll)

        recentEmojiNames = UserDefaults.standard.stringArray(forKey: "recentEmojis") ?? []
        buildEmojiCategoryBar()
        emojiPanel.frame = NSRect(x: 0, y: 0, width: 350, height: 440)
    }

    func buildEmojiCategoryBar() {
        emojiCategoryBar.subviews.forEach { $0.removeFromSuperview() }
        emojiCategoryBarButtons.removeAll()

        let titles = EmojiCatalog.categories.filter { category in
            if category.title == "Recent" { return !recentEmojiNames.isEmpty }
            if category.title == "Custom" { return !customEmojiEntries.isEmpty }
            return true
        }

        let buttonSize: CGFloat = 24
        let gap: CGFloat = 4
        let margin: CGFloat = 10
        var x = margin
        for category in titles {
            let button = RoundedEdgePanel()
            button.cornerRadius = MMRadius.control
            button.color = .clear
            button.frame = NSRect(x: x, y: 2, width: buttonSize, height: buttonSize)
            let icon = NSImageView()
            if let image = NSImage(systemSymbolName: category.symbol, accessibilityDescription: category.title) {
                icon.image = image.withSymbolConfiguration(.init(pointSize: 12, weight: .medium))
            }
            icon.frame = NSRect(x: 5, y: 5, width: 14, height: 14)
            button.addSubview(icon)
            let title = category.title
            button.onClick = { [weak self] in
                guard let self = self else { return }
                self.emojiSelectedCategory = title
                self.updateEmojiCategorySelection()
                self.renderEmojiGrid()
            }
            button.onHoverChanged = { [weak self, weak button] isHovered in
                guard let self = self, let button = button else { return }
                if self.emojiSelectedCategory != title, isHovered {
                    button.color = Theme.shared.centerText.withAlphaComponent(0.06)
                } else if self.emojiSelectedCategory != title {
                    button.color = .clear
                }
                button.setNeedsAppearanceUpdate()
            }
            emojiCategoryBar.addSubview(button)
            emojiCategoryBarButtons[title] = button
            x += buttonSize + gap
        }

        if !titles.contains(where: { $0.title == emojiSelectedCategory }) {
            emojiSelectedCategory = titles.first?.title ?? "Smileys & Emotion"
        }
        updateEmojiCategorySelection()
    }

    func updateEmojiCategorySelection() {
        let selectedBlue = Theme.shared.buttonBg
        let idle = Theme.shared.centerText.withAlphaComponent(0.64)
        for (title, button) in emojiCategoryBarButtons {
            let isSelected = title == emojiSelectedCategory
            button.color = isSelected
                ? Theme.shared.buttonBg.withAlphaComponent(0.08)
                : .clear
            button.subviews.compactMap { $0 as? NSImageView }.forEach {
                $0.contentTintColor = isSelected ? selectedBlue : idle
            }
            button.setNeedsAppearanceUpdate()
        }
    }

    func emojiEntriesForSelection() -> (title: String, entries: [EmojiEntry]) {
        let query = emojiSearchField.stringValue.trimmingCharacters(in: .whitespacesAndNewlines).lowercased()
        if !query.isEmpty {
            let all = EmojiCatalog.entries + customEmojiEntries
            return ("Search Results", all.filter { $0.name.lowercased().contains(query) })
        }
        switch emojiSelectedCategory {
        case "Recent":
            let entries = recentEmojiNames.compactMap { name in
                EmojiCatalog.entriesByName[name] ?? customEmojiEntries.first(where: { $0.name == name })
            }
            return ("Recent", entries)
        case "Custom":
            return ("Custom", customEmojiEntries)
        default:
            return (emojiSelectedCategory, EmojiCatalog.entries.filter { $0.category == emojiSelectedCategory })
        }
    }

    func renderEmojiGrid() {
        let width = max(emojiScroll.bounds.width, 350)
        emojiDoc.subviews.forEach { $0.removeFromSuperview() }

        let selection = emojiEntriesForSelection()
        let header = NSTextField(labelWithString: selection.title.uppercased())
        header.font = MMFont.font(ofSize: 12, weight: .semibold)
        header.textColor = Theme.shared.centerText.withAlphaComponent(0.48)
        header.isEditable = false
        header.isSelectable = false
        header.frame = NSRect(x: 12, y: 0, width: max(0, width - 24), height: 36)
        emojiDoc.addSubview(header)

        if selection.entries.isEmpty {
            let label = NSTextField(labelWithString: "No emoji found")
            label.font = MMFont.font(ofSize: 13)
            label.textColor = Theme.shared.centerTextMuted
            label.alignment = .center
            label.isEditable = false
            label.isSelectable = false
            label.frame = NSRect(x: 12, y: 56, width: max(0, width - 24), height: 20)
            emojiDoc.addSubview(label)
            emojiDoc.frame = NSRect(x: 0, y: 0, width: width, height: 100)
            return
        }

        let columns = 9
        let cell: CGFloat = 36
        let margin: CGFloat = 12
        for (index, entry) in selection.entries.enumerated() {
            let column = index % columns
            let row = index / columns
            let button = RoundedEdgePanel()
            button.cornerRadius = MMRadius.tiny
            button.color = .clear
            button.frame = NSRect(
                x: margin + CGFloat(column) * cell,
                y: 36 + CGFloat(row) * cell,
                width: cell,
                height: cell
            )
            if entry.isCustom {
                if let id = entry.emojiId, let image = customEmojiImages[id] {
                    let imageView = NSImageView(frame: NSRect(x: 7, y: 7, width: 22, height: 22))
                    imageView.image = image
                    imageView.imageScaling = .scaleProportionallyUpOrDown
                    button.addSubview(imageView)
                } else {
                    let placeholder = NSTextField(labelWithString: "🖼️")
                    placeholder.font = MMFont.font(ofSize: 18)
                    placeholder.alignment = .center
                    placeholder.isEditable = false
                    placeholder.isSelectable = false
                    placeholder.frame = NSRect(x: 0, y: 7, width: cell, height: 22)
                    button.addSubview(placeholder)
                }
            } else {
                let label = NSTextField(labelWithString: entry.glyph)
                label.font = MMFont.font(ofSize: 22)
                label.alignment = .center
                label.isEditable = false
                label.isSelectable = false
                label.frame = NSRect(x: 0, y: 6, width: cell, height: 26)
                button.addSubview(label)
            }
            button.onHoverChanged = { [weak button] isHovered in
                button?.color = isHovered
                    ? Theme.shared.centerText.withAlphaComponent(0.16)
                    : .clear
                button?.setNeedsAppearanceUpdate()
            }
            button.onClick = { [weak self] in
                self?.selectEmoji(entry)
            }
            emojiDoc.addSubview(button)
        }

        let rows = (selection.entries.count + columns - 1) / columns
        emojiDoc.frame = NSRect(x: 0, y: 0, width: width, height: CGFloat(rows) * cell + 44)
        emojiScroll.contentView.scroll(to: .zero)
        emojiScroll.reflectScrolledClipView(emojiScroll.contentView)
    }

    func selectEmoji(_ entry: EmojiEntry) {
        recentEmojiNames.removeAll { $0 == entry.name }
        recentEmojiNames.insert(entry.name, at: 0)
        if recentEmojiNames.count > 18 {
            recentEmojiNames.removeLast(recentEmojiNames.count - 18)
        }
        UserDefaults.standard.set(recentEmojiNames, forKey: "recentEmojis")

        if entry.isCustom {
            insertEmoji(":\(entry.name):")
        } else {
            insertEmoji(entry.glyph)
        }
    }

    func loadCustomEmojis() {
        guard !isCustomEmojiLoaded,
              let ws = webService, ws.isLogged() else { return }
        isCustomEmojiLoaded = true
        Task { @MainActor [weak self] in
            guard let self = self else { return }
            guard let emojis = try? await ws.fetchCustomEmojis() else {
                self.isCustomEmojiLoaded = false
                return
            }
            var entries: [EmojiEntry] = []
            for emoji in emojis {
                let entry = EmojiEntry(
                    name: emoji.name,
                    glyph: ":\(emoji.name):",
                    category: "Custom",
                    isCustom: true,
                    emojiId: emoji.id
                )
                entries.append(entry)
                if let data = try? await ws.fetchEmojiImage(emojiId: emoji.id),
                   let image = NSImage(data: data) {
                    self.customEmojiImages[emoji.id] = image
                }
            }
            self.customEmojiEntries = entries.sorted {
                $0.name.localizedCaseInsensitiveCompare($1.name) == .orderedAscending
            }
            if self.isEmojiPanelOpen {
                self.buildEmojiCategoryBar()
                self.renderEmojiGrid()
            }
            if !self.customEmojiEntries.isEmpty {
                if self.isRightPanelVisible && self.rightPanelMode == .thread {
                    self.renderThreadPanel()
                }
                self.rebuildTimelineContent()
            }
        }
    }

    func toggleEmojiPanel() {
        if isEmojiPanelOpen {
            closeEmojiPanel()
            return
        }
        guard !activeChannelId.isEmpty else { return }
        let buttonFrame = chatEntryPanel.convert(composerEmojiButton.frame, to: chatPanel)
        let width: CGFloat = 350
        let height: CGFloat = 440
        let x = min(max(8, buttonFrame.midX - width / 2), max(8, chatPanel.bounds.width - width - 8))
        let y = min(chatEntryPanel.frame.maxY + 8, chatPanel.bounds.height - height - 8)
        emojiPanel.frame = NSRect(x: x, y: y, width: width, height: height)
        emojiSearchField.stringValue = ""
        emojiSearchField.frame = NSRect(x: 12, y: height - 44, width: width - 24, height: 26)
        emojiScroll.frame = NSRect(x: 0, y: 0, width: width, height: height - 82)
        emojiCategoryBar.frame = NSRect(x: 0, y: height - 74, width: width, height: 28)
        emojiPanel.removeFromSuperview()
        chatPanel.addSubview(emojiPanel)
        emojiPanel.isHidden = false
        isEmojiPanelOpen = true
        if emojiSelectedCategory == "Recent" && recentEmojiNames.isEmpty {
            emojiSelectedCategory = "Smileys & Emotion"
        }
        buildEmojiCategoryBar()
        renderEmojiGrid()
        loadCustomEmojis()
        makeFirstResponder(emojiSearchField)
    }

    func closeEmojiPanel() {
        emojiPanel.isHidden = true
        isEmojiPanelOpen = false
        emojiSearchField.stringValue = ""
    }

    func insertEmoji(_ emoji: String) {
        closeCompletion()
        let range = entryView.selectedRange()
        entryView.insertText(emoji, replacementRange: range)
        entryView.needsDisplay = true
        updateComposerSendState()
        closeEmojiPanel()
        makeFirstResponder(entryView)
    }

    func updateCompletion() {
        guard entryView.selectedRange().length == 0,
              let trigger = detectCompletionTrigger() else {
            closeCompletion()
            return
        }

        var items: [CompletionItem] = []
        switch trigger.kind {
        case .user:
            ensureCompletionUsers()
            let query = trigger.query.lowercased()
            var seen = Set<String>()
            let candidates = completionUsers.isEmpty ? Array(usersById.values) : completionUsers
            items = candidates
                .filter { user in
                    guard seen.insert(user.id).inserted else { return false }
                    let full = [user.first_name, user.last_name].compactMap { $0 }.joined(separator: " ").lowercased()
                    return query.isEmpty
                        || user.username.lowercased().contains(query)
                        || full.contains(query)
                }
                .sorted { lhs, rhs in
                    let lhsPrefix = lhs.username.lowercased().hasPrefix(query)
                    let rhsPrefix = rhs.username.lowercased().hasPrefix(query)
                    if lhsPrefix != rhsPrefix { return lhsPrefix }
                    return lhs.username.localizedCaseInsensitiveCompare(rhs.username) == .orderedAscending
                }
                .map { user in
                    let full = [user.first_name, user.last_name].compactMap { $0 }.joined(separator: " ")
                    return CompletionItem(
                        kind: .user,
                        title: "@" + user.username,
                        subtitle: full,
                        insertText: "@" + user.username + " ",
                        glyph: nil
                    )
                }
        case .channel:
            let query = trigger.query.lowercased()
            items = channelsById.values
                .filter { $0.type == "O" || $0.type == "P" || $0.type == "G" }
                .filter { channel in
                    query.isEmpty
                        || channel.name.lowercased().contains(query)
                        || channel.display_name.lowercased().contains(query)
                }
                .sorted { $0.display_name.localizedCaseInsensitiveCompare($1.display_name) == .orderedAscending }
                .map { channel in
                    CompletionItem(
                        kind: .channel,
                        title: "~" + (channel.type == "G" ? channel.display_name : channel.name),
                        subtitle: channel.display_name,
                        insertText: "~" + channel.name + " ",
                        glyph: nil
                    )
                }
        case .emoji:
            let query = trigger.query.lowercased()
            items = (EmojiCatalog.entries + customEmojiEntries)
                .filter { query.isEmpty || $0.name.lowercased().contains(query) }
                .sorted { lhs, rhs in
                    let lhsPrefix = lhs.name.lowercased().hasPrefix(query)
                    let rhsPrefix = rhs.name.lowercased().hasPrefix(query)
                    if lhsPrefix != rhsPrefix { return lhsPrefix }
                    return lhs.name.localizedCaseInsensitiveCompare(rhs.name) == .orderedAscending
                }
                .map { entry in
                    CompletionItem(
                        kind: .emoji,
                        title: ":" + entry.name + ":",
                        subtitle: "",
                        insertText: ":" + entry.name + ": ",
                        glyph: entry.isCustom ? "🖼️" : entry.glyph
                    )
                }
        }

        guard !items.isEmpty else {
            closeCompletion()
            return
        }

        let sameSelection = isCompletionVisible
            && completionKind == trigger.kind
            && completionRange == trigger.range
            && completionItems.count == min(items.count, 8)
        completionKind = trigger.kind
        completionRange = trigger.range
        completionItems = Array(items.prefix(8))
        if !sameSelection {
            completionSelectedIndex = 0
        }
        completionSelectedIndex = min(completionSelectedIndex, max(0, completionItems.count - 1))
        renderCompletionPanel()
    }

    func detectCompletionTrigger() -> CompletionTrigger? {
        let selection = entryView.selectedRange()
        guard selection.length == 0 else { return nil }
        let caret = selection.location
        let text = entryView.string as NSString
        guard caret >= 0, caret <= text.length else { return nil }
        let prefix = text.substring(to: caret)

        let specifications: [(CompletionKind, String)] = [
            (.user, #"(?<![\w@])@([A-Za-z0-9._-]*)$"#),
            (.channel, #"(?<![\w])[#~]([A-Za-z0-9._-]*)$"#),
            (.emoji, #"(?<![\w:]):([A-Za-z0-9_+\-]+)$"#)
        ]
        let range = NSRange(location: 0, length: caret)
        for (kind, pattern) in specifications {
            guard let regex = try? NSRegularExpression(pattern: pattern) else { continue }
            guard let match = regex.firstMatch(in: prefix, options: [], range: range) else { continue }
            let query = (prefix as NSString).substring(with: match.range(at: 1))
            return CompletionTrigger(kind: kind, query: query, range: match.range)
        }
        return nil
    }

    func ensureCompletionUsers() {
        guard let ws = webService, ws.isLogged(),
              let team = activeTeam,
              completionUsersTeamId != team.id,
              !completionUsersLoading else { return }
        completionUsersLoading = true
        Task { @MainActor [weak self] in
            guard let self = self else { return }
            let users = (try? await ws.fetchTeamUsers(teamId: team.id)) ?? []
            self.completionUsersLoading = false
            guard !users.isEmpty else { return }
            self.completionUsers = users
            self.completionUsersTeamId = team.id
            for user in users {
                self.usersById[user.id] = user
                self.usersByUsername[user.username.lowercased()] = user
            }
            if self.isCompletionVisible {
                self.updateCompletion()
            }
        }
    }

    func renderCompletionPanel() {
        completionPanel.subviews.forEach { $0.removeFromSuperview() }
        completionRowViews.removeAll()

        let width: CGFloat = 300
        let rowHeight: CGFloat = 36
        let height = CGFloat(completionItems.count) * rowHeight + 8
        let rightLimit = isRightPanelVisible ? rightPanel.frame.minX : chatPanel.bounds.width
        let x = min(
            max(8, chatEntryPanel.frame.minX + 14),
            max(8, rightLimit - width - 8)
        )
        let y = min(
            max(8, chatEntryPanel.frame.maxY + 6),
            max(8, chatPanel.bounds.height - height - 8)
        )
        completionPanel.frame = NSRect(x: x, y: y, width: width, height: height)

        let textColor = Theme.shared.centerText
        let muted = Theme.shared.centerTextMuted
        let selectedBg = Theme.shared.buttonBg.withAlphaComponent(0.08)

        for (index, item) in completionItems.enumerated() {
            let row = RoundedEdgePanel()
            row.cornerRadius = MMRadius.control
            row.color = index == completionSelectedIndex ? selectedBg : .clear
            row.frame = NSRect(
                x: 4,
                y: height - 4 - CGFloat(index + 1) * rowHeight,
                width: width - 8,
                height: rowHeight
            )

            var titleX: CGFloat = 12
            switch item.kind {
            case .user:
                let avatar = RoundedEdgePanel()
                avatar.cornerRadius = MMRadius.card
                avatar.clipContentToBounds = true
                avatar.frame = NSRect(x: 8, y: 8, width: 20, height: 20)
                let user = usersByUsername[item.title.dropFirst().lowercased()]
                if let user = user, let image = userAvatarsById[user.id] {
                    avatar.color = .clear
                    let imageView = NSImageView(frame: NSRect(origin: .zero, size: avatar.frame.size))
                    imageView.image = image
                    imageView.imageScaling = .scaleProportionallyUpOrDown
                    avatar.addSubview(imageView)
                } else {
                    avatar.color = Theme.shared.buttonBg
                    let initial = item.title.dropFirst().first.map { String($0).uppercased() } ?? "U"
                    let label = NSTextField(labelWithString: initial)
                    label.font = MMFont.font(ofSize: 10, weight: .semibold)
                    label.textColor = .white
                    label.alignment = .center
                    label.isEditable = false
                    label.isSelectable = false
                    label.frame = NSRect(x: 0, y: 3, width: 20, height: 14)
                    avatar.addSubview(label)
                }
                row.addSubview(avatar)
                titleX = 36
            case .channel:
                let hash = NSTextField(labelWithString: "#")
                hash.font = MMFont.font(ofSize: 15, weight: .semibold)
                hash.textColor = muted
                hash.isEditable = false
                hash.isSelectable = false
                hash.frame = NSRect(x: 10, y: 8, width: 18, height: 20)
                row.addSubview(hash)
                titleX = 32
            case .emoji:
                let glyph = NSTextField(labelWithString: item.glyph ?? "🙂")
                glyph.font = MMFont.font(ofSize: 18)
                glyph.alignment = .center
                glyph.isEditable = false
                glyph.isSelectable = false
                glyph.frame = NSRect(x: 8, y: 7, width: 24, height: 22)
                row.addSubview(glyph)
                titleX = 38
            }

            let title = NSTextField(labelWithString: item.title)
            title.font = MMFont.font(ofSize: 13, weight: .semibold)
            title.textColor = textColor
            title.lineBreakMode = .byTruncatingTail
            title.isEditable = false
            title.isSelectable = false
            title.frame = NSRect(
                x: titleX,
                y: item.subtitle.isEmpty ? 9 : 5,
                width: width - titleX - 16,
                height: 17
            )
            row.addSubview(title)

            if !item.subtitle.isEmpty {
                let subtitle = NSTextField(labelWithString: item.subtitle)
                subtitle.font = MMFont.font(ofSize: 11)
                subtitle.textColor = muted
                subtitle.lineBreakMode = .byTruncatingTail
                subtitle.isEditable = false
                subtitle.isSelectable = false
                subtitle.frame = NSRect(x: titleX, y: 21, width: width - titleX - 16, height: 14)
                row.addSubview(subtitle)
            }

            let rowIndex = index
            row.onHoverChanged = { [weak self, weak row] isHovered in
                guard let self = self, let row = row else { return }
                if rowIndex != self.completionSelectedIndex {
                    row.color = isHovered ? Theme.shared.centerHover : .clear
                    row.setNeedsAppearanceUpdate()
                }
            }
            row.onClick = { [weak self] in
                self?.acceptCompletion(at: rowIndex)
            }
            completionPanel.addSubview(row)
            completionRowViews.append(row)
        }

        completionPanel.isHidden = false
        isCompletionVisible = true
        chatPanel.addSubview(completionPanel)
    }

    func updateCompletionRows() {
        let selectedBg = Theme.shared.buttonBg.withAlphaComponent(0.08)
        for (index, row) in completionRowViews.enumerated() {
            row.color = index == completionSelectedIndex ? selectedBg : .clear
            row.setNeedsAppearanceUpdate()
        }
    }

    func moveCompletionSelection(by delta: Int) -> Bool {
        guard isCompletionVisible, !completionItems.isEmpty else { return false }
        completionSelectedIndex = (completionSelectedIndex + delta + completionItems.count) % completionItems.count
        updateCompletionRows()
        return true
    }

    func acceptCompletion(at index: Int) {
        guard isCompletionVisible, completionItems.indices.contains(index) else { return }
        let item = completionItems[index]
        let length = (entryView.string as NSString).length
        guard NSMaxRange(completionRange) <= length else {
            closeCompletion()
            return
        }

        if item.kind == .emoji {
            let name = item.insertText.trimmingCharacters(in: CharacterSet(charactersIn: ": "))
            recentEmojiNames.removeAll { $0 == name }
            recentEmojiNames.insert(name, at: 0)
            if recentEmojiNames.count > 18 {
                recentEmojiNames.removeLast(recentEmojiNames.count - 18)
            }
            UserDefaults.standard.set(recentEmojiNames, forKey: "recentEmojis")
        }

        entryView.insertText(item.insertText, replacementRange: completionRange)
        closeCompletion()
        updateComposerSendState()
        makeFirstResponder(entryView)
    }

    func closeCompletion() {
        guard isCompletionVisible || !completionPanel.isHidden else { return }
        completionPanel.isHidden = true
        completionPanel.subviews.forEach { $0.removeFromSuperview() }
        completionRowViews.removeAll()
        completionItems.removeAll()
        completionRange = NSRange(location: 0, length: 0)
        completionSelectedIndex = 0
        isCompletionVisible = false
    }

    func attachFiles() {
        guard !activeChannelId.isEmpty else { return }
        let panel = NSOpenPanel()
        panel.allowsMultipleSelection = true
        panel.canChooseDirectories = false
        panel.canChooseFiles = true
        panel.beginSheetModal(for: self) { [weak self] response in
            guard response == .OK, let self = self else { return }
            self.uploadFiles(panel.urls)
        }
    }

    func loadAttachmentSizeLimit() {
        guard let ws = webService else { return }
        Task { @MainActor [weak self] in
            guard let self = self, let serverLimit = await ws.fetchMaxFileSize() else { return }
            self.attachmentSizeLimit = AttachmentUploadPolicy.resolvedLimit(serverValue: serverLimit)
        }
    }

    func uploadFiles(_ urls: [URL]) {
        let files = urls.filter { !$0.hasDirectoryPath }
        guard !files.isEmpty,
              !activeChannelId.isEmpty,
              webService != nil else { return }
        let channelId = activeChannelId
        let limit = attachmentSizeLimit
        var rejected: [String] = []

        for url in files {
            let values = try? url.resourceValues(forKeys: [.fileSizeKey])
            let size = values?.fileSize.map(Int64.init) ?? 0
            let name = url.lastPathComponent
            if AttachmentUploadPolicy.exceedsLimit(size: size, limit: limit) {
                rejected.append(
                    "\(name) is \(AttachmentUploadPolicy.formattedBytes(size)); the limit is \(AttachmentUploadPolicy.formattedBytes(limit))."
                )
                continue
            }
            let mime = UTType(filenameExtension: url.pathExtension)?.preferredMIMEType
                ?? "application/octet-stream"
            enqueueUpload(
                ActiveAttachmentUpload(
                    id: UUID(),
                    channelId: channelId,
                    name: name,
                    size: size,
                    mimeType: mime,
                    source: .file(url),
                    state: .queued
                )
            )
        }
        if !rejected.isEmpty {
            composerHelpLabel.stringValue = rejected.joined(separator: " ")
        }
    }

    func uploadPastedImage(_ data: Data, filename: String) {
        guard !activeChannelId.isEmpty, webService != nil else { return }
        let limit = attachmentSizeLimit
        guard !AttachmentUploadPolicy.exceedsLimit(size: Int64(data.count), limit: limit) else {
            composerHelpLabel.stringValue =
                "The pasted image is \(AttachmentUploadPolicy.formattedBytes(Int64(data.count))); the limit is \(AttachmentUploadPolicy.formattedBytes(limit))."
            return
        }
        enqueueUpload(
            ActiveAttachmentUpload(
                id: UUID(),
                channelId: activeChannelId,
                name: filename,
                size: Int64(data.count),
                mimeType: "image/png",
                source: .data(data),
                state: .queued
            )
        )
    }

    private func enqueueUpload(_ upload: ActiveAttachmentUpload) {
        activeAttachmentUploads.removeAll { $0.id == upload.id }
        var upload = upload
        upload.state = .queued
        activeAttachmentUploads.append(upload)
        if activeChannelId == upload.channelId {
            composerHelpLabel.stringValue = "Uploading \(upload.name)…"
        }
        renderPendingAttachments()
        layoutRightChatPanel()
        updateComposerSendState()
        pumpAttachmentUploads()
    }

    private func pumpAttachmentUploads() {
        let available = maxConcurrentAttachmentUploads - attachmentUploadTasks.count
        guard available > 0 else { return }
        let queuedIds = activeAttachmentUploads.filter(\.isQueued).map(\.id).prefix(available)
        for id in queuedIds {
            guard let index = activeAttachmentUploads.firstIndex(where: { $0.id == id }) else { continue }
            var upload = activeAttachmentUploads[index]
            upload.state = .uploading(progress: 0)
            activeAttachmentUploads[index] = upload
            startUpload(upload)
        }
    }

    private func startUpload(_ upload: ActiveAttachmentUpload) {
        guard let ws = webService else { return }
        let limit = attachmentSizeLimit
        let task = Task { @MainActor [weak self] in
            guard let self = self else { return }
            do {
                let fileId: String
                switch upload.source {
                case .file(let url):
                    let accessed = url.startAccessingSecurityScopedResource()
                    defer { if accessed { url.stopAccessingSecurityScopedResource() } }
                    fileId = try await ws.uploadFile(
                        channelId: upload.channelId,
                        fileURL: url,
                        filename: upload.name,
                        mimeType: upload.mimeType,
                        maxBytes: limit
                    ) { [weak self] fraction in
                        Task { @MainActor [weak self] in
                            self?.updateUploadProgress(id: upload.id, progress: fraction)
                        }
                    }
                case .data(let data):
                    fileId = try await ws.uploadFile(
                        channelId: upload.channelId,
                        data: data,
                        filename: upload.name,
                        mimeType: upload.mimeType
                    )
                    self.updateUploadProgress(id: upload.id, progress: 1)
                }
                self.finishUpload(id: upload.id, fileId: fileId)
            } catch is CancellationError {
                self.removeUpload(id: upload.id)
            } catch {
                self.failUpload(id: upload.id, message: error.localizedDescription)
            }
        }
        attachmentUploadTasks[upload.id] = task
    }

    private func updateUploadProgress(id: UUID, progress: Double) {
        guard let index = activeAttachmentUploads.firstIndex(where: { $0.id == id }),
              case .uploading = activeAttachmentUploads[index].state
        else { return }
        guard abs(activeAttachmentUploads[index].currentProgress - progress) >= 0.01 || progress >= 1
        else { return }
        activeAttachmentUploads[index].state = .uploading(progress: progress)
        renderPendingAttachments()
    }

    private func finishUpload(id: UUID, fileId: String) {
        guard let upload = activeAttachmentUploads.first(where: { $0.id == id }) else { return }
        activeAttachmentUploads.removeAll { $0.id == id }
        attachmentUploadTasks.removeValue(forKey: id)
        addPendingAttachment(
            PendingAttachment(id: fileId, name: upload.name, size: upload.size),
            to: upload.channelId
        )
        if activeChannelId == upload.channelId {
            composerHelpLabel.stringValue = pendingAttachments.isEmpty
                ? defaultComposerStatusText()
                : "Attached \(pendingAttachments.count) file\(pendingAttachments.count == 1 ? "" : "s")"
        }
        renderPendingAttachments()
        layoutRightChatPanel()
        updateComposerSendState()
        pumpAttachmentUploads()
    }

    private func failUpload(id: UUID, message: String) {
        guard let index = activeAttachmentUploads.firstIndex(where: { $0.id == id }) else { return }
        let upload = activeAttachmentUploads[index]
        activeAttachmentUploads[index].state = .failed(message: message)
        attachmentUploadTasks.removeValue(forKey: id)
        if activeChannelId == upload.channelId {
            composerHelpLabel.stringValue = "\(upload.name): \(message)"
        }
        renderPendingAttachments()
        layoutRightChatPanel()
        updateComposerSendState()
        pumpAttachmentUploads()
    }

    private func addPendingAttachment(_ attachment: PendingAttachment, to channelId: String) {
        if activeChannelId == channelId {
            pendingAttachments.append(attachment)
            renderPendingAttachments()
            layoutRightChatPanel()
            scrollTimelineToBottom()
            updateComposerSendState()
        } else if var draft = composerDraftsByChannelId[channelId] {
            draft.attachments.append(attachment)
            composerDraftsByChannelId[channelId] = draft
        } else {
            composerDraftsByChannelId[channelId] = ComposerDraft(
                text: "",
                attachments: [attachment],
                editingPostId: nil
            )
        }
    }

    func retryUpload(id: UUID) {
        guard let index = activeAttachmentUploads.firstIndex(where: { $0.id == id }),
              !activeAttachmentUploads[index].isInProgress
        else { return }
        activeAttachmentUploads[index].state = .queued
        renderPendingAttachments()
        pumpAttachmentUploads()
    }

    func cancelUpload(id: UUID) {
        attachmentUploadTasks[id]?.cancel()
        attachmentUploadTasks.removeValue(forKey: id)
        removeUpload(id: id)
    }

    private func removeUpload(id: UUID) {
        activeAttachmentUploads.removeAll { $0.id == id }
        attachmentUploadTasks.removeValue(forKey: id)
        renderPendingAttachments()
        layoutRightChatPanel()
        updateComposerSendState()
        pumpAttachmentUploads()
    }

    func renderPendingAttachments() {
        composerAttachmentTray.subviews.forEach { $0.removeFromSuperview() }
        let uploads = activeAttachmentUploads.filter { $0.channelId == activeChannelId }
        let total = uploads.count + pendingAttachments.count
        composerAttachmentTray.isHidden = total == 0
        guard total > 0 else { return }

        let trayWidth = max(composerAttachmentTray.bounds.width, 200)
        let chipW: CGFloat = 168
        let chipH: CGFloat = 24
        let gap: CGFloat = 6
        let maxVisible = max(1, Int((trayWidth + gap) / (chipW + gap)))
        var x: CGFloat = 0
        var rendered = 0

        for upload in uploads.prefix(maxVisible) {
            renderUploadChip(upload, frame: NSRect(x: x, y: 2, width: chipW, height: chipH))
            x += chipW + gap
            rendered += 1
        }

        for attachment in pendingAttachments.prefix(max(0, maxVisible - rendered)) {
            let chip = RoundedEdgePanel()
            chip.cornerRadius = MMRadius.control
            chip.color = Theme.shared.centerHover
            chip.borderWidth = 1
            chip.borderColor = Theme.shared.divider
            chip.frame = NSRect(x: x, y: 2, width: chipW, height: chipH)

            let icon = NSImageView()
            if let image = NSImage(systemSymbolName: "doc.fill", accessibilityDescription: attachment.name) {
                icon.image = image.withSymbolConfiguration(.init(pointSize: 11, weight: .regular))
                icon.contentTintColor = Theme.shared.centerTextMuted
            }
            icon.frame = NSRect(x: 7, y: 6, width: 12, height: 12)
            chip.addSubview(icon)

            let name = NSTextField(labelWithString: attachment.name)
            name.font = MMFont.font(ofSize: 11)
            name.textColor = Theme.shared.centerText
            name.lineBreakMode = .byTruncatingMiddle
            name.isEditable = false
            name.isSelectable = false
            name.frame = NSRect(x: 24, y: 5, width: chipW - 50, height: 14)
            chip.addSubview(name)

            let remove = RoundedEdgePanel()
            remove.cornerRadius = MMRadius.tiny
            remove.color = .clear
            remove.frame = NSRect(x: chipW - 22, y: 4, width: 16, height: 16)
            let xIcon = NSImageView()
            if let image = NSImage(systemSymbolName: "xmark", accessibilityDescription: "Remove attachment") {
                xIcon.image = image.withSymbolConfiguration(.init(pointSize: 8, weight: .bold))
                xIcon.contentTintColor = Theme.shared.centerTextMuted
            }
            xIcon.frame = NSRect(x: 4, y: 4, width: 8, height: 8)
            remove.addSubview(xIcon)
            let attachmentId = attachment.id
            remove.onClick = { [weak self] in
                self?.removePendingAttachment(id: attachmentId)
            }
            chip.addSubview(remove)

            composerAttachmentTray.addSubview(chip)
            x += chipW + gap
            rendered += 1
        }

        if total > maxVisible {
            let more = NSTextField(labelWithString: "+\(total - maxVisible)")
            more.font = MMFont.font(ofSize: 11, weight: .semibold)
            more.textColor = Theme.shared.centerTextMuted
            more.isEditable = false
            more.isSelectable = false
            more.frame = NSRect(x: x + 2, y: 7, width: 32, height: 14)
            composerAttachmentTray.addSubview(more)
        }
    }

    private func renderUploadChip(_ upload: ActiveAttachmentUpload, frame: NSRect) {
        let chip = RoundedEdgePanel()
        chip.cornerRadius = MMRadius.control
        chip.color = Theme.shared.centerHover
        chip.borderWidth = 1

        let progress: Double
        let failed: Bool
        switch upload.state {
        case .queued:
            progress = 0
            failed = false
        case .uploading(let value):
            progress = value
            failed = false
        case .failed(let message):
            progress = 0
            failed = true
            chip.borderColor = NSColor.systemRed.withAlphaComponent(0.7)
            chip.toolTip = message
        }
        if !failed {
            chip.borderColor = Theme.shared.divider
        }
        chip.frame = frame

        let icon = NSImageView()
        let symbol = failed ? "exclamationmark.triangle.fill" : "arrow.up.circle.fill"
        if let image = NSImage(systemSymbolName: symbol, accessibilityDescription: upload.name) {
            icon.image = image.withSymbolConfiguration(.init(pointSize: 11, weight: .regular))
            icon.contentTintColor = failed ? .systemRed : Theme.shared.centerTextMuted
        }
        icon.frame = NSRect(x: 7, y: 6, width: 12, height: 12)
        chip.addSubview(icon)

        let title: String
        if failed {
            title = "\(upload.name) — failed"
        } else if upload.isQueued {
            title = "\(upload.name) — queued"
        } else if progress >= 1 {
            title = "\(upload.name) — finishing…"
        } else {
            title = "\(upload.name) — \(Int(progress * 100))%"
        }
        let name = NSTextField(labelWithString: title)
        name.font = MMFont.font(ofSize: 11)
        name.textColor = failed ? .systemRed : Theme.shared.centerText
        name.lineBreakMode = .byTruncatingMiddle
        name.isEditable = false
        name.isSelectable = false
        name.frame = NSRect(x: 24, y: 5, width: frame.width - (failed ? 66 : 50), height: 14)
        chip.addSubview(name)

        if !failed && progress > 0 && progress < 1 {
            let bar = RoundedEdgePanel()
            bar.cornerRadius = 1
            bar.color = Theme.shared.buttonBg
            let barWidth = max(1, (frame.width - 12) * progress)
            bar.frame = NSRect(x: 6, y: 1, width: barWidth, height: 2)
            chip.addSubview(bar)
        }

        if failed {
            let retry = RoundedEdgePanel()
            retry.cornerRadius = MMRadius.tiny
            retry.color = .clear
            retry.frame = NSRect(x: frame.width - 40, y: 4, width: 16, height: 16)
            let retryIcon = NSImageView()
            if let image = NSImage(systemSymbolName: "arrow.clockwise", accessibilityDescription: "Retry upload") {
                retryIcon.image = image.withSymbolConfiguration(.init(pointSize: 9, weight: .semibold))
                retryIcon.contentTintColor = Theme.shared.centerTextMuted
            }
            retryIcon.frame = NSRect(x: 4, y: 4, width: 9, height: 9)
            retry.addSubview(retryIcon)
            let uploadId = upload.id
            retry.onClick = { [weak self] in
                self?.retryUpload(id: uploadId)
            }
            chip.addSubview(retry)
        }

        let remove = RoundedEdgePanel()
        remove.cornerRadius = MMRadius.tiny
        remove.color = .clear
        remove.frame = NSRect(x: frame.width - 22, y: 4, width: 16, height: 16)
        let xIcon = NSImageView()
        let accessibility = failed ? "Remove failed upload" : "Cancel upload"
        if let image = NSImage(systemSymbolName: "xmark", accessibilityDescription: accessibility) {
            xIcon.image = image.withSymbolConfiguration(.init(pointSize: 8, weight: .bold))
            xIcon.contentTintColor = Theme.shared.centerTextMuted
        }
        xIcon.frame = NSRect(x: 4, y: 4, width: 8, height: 8)
        remove.addSubview(xIcon)
        let uploadId = upload.id
        remove.onClick = { [weak self] in
            self?.cancelUpload(id: uploadId)
        }
        chip.addSubview(remove)

        composerAttachmentTray.addSubview(chip)
    }

    func removePendingAttachment(id: String) {
        pendingAttachments.removeAll { $0.id == id }
        renderPendingAttachments()
        layoutRightChatPanel()
        scrollTimelineToBottom()
        updateComposerSendState()
        composerHelpLabel.stringValue = pendingAttachments.isEmpty
            ? "Help"
            : "Attached \(pendingAttachments.count) file\(pendingAttachments.count == 1 ? "" : "s")"
    }

    func clearPendingAttachments() {
        guard !pendingAttachments.isEmpty else { return }
        pendingAttachments.removeAll()
        composerAttachmentTray.subviews.forEach { $0.removeFromSuperview() }
        composerAttachmentTray.isHidden = true
        updateComposerSendState()
        layoutRightChatPanel()
    }

    // MARK: - Per-channel drafts

    func saveComposerDraft(for channelId: String) {
        guard !channelId.isEmpty else { return }
        let draft = ComposerDraft(
            text: entryView.string,
            attachments: pendingAttachments,
            editingPostId: editingPostId
        )
        if draft.text.isEmpty && draft.attachments.isEmpty && draft.editingPostId == nil {
            composerDraftsByChannelId.removeValue(forKey: channelId)
        } else {
            composerDraftsByChannelId[channelId] = draft
        }
    }

    func restoreComposerDraft(for channelId: String) {
        let draft = composerDraftsByChannelId[channelId]
        editingPostId = draft?.editingPostId
        entryView.string = draft?.text ?? ""
        entryView.needsDisplay = true
        pendingAttachments = draft?.attachments ?? []
        renderPendingAttachments()
        updateComposerSendState()
        if editingPostId != nil {
            composerHelpLabel.stringValue = "Editing • Esc to cancel"
        } else if pendingAttachments.isEmpty {
            composerHelpLabel.stringValue = "Help"
        } else {
            composerHelpLabel.stringValue = "Attached \(pendingAttachments.count) file\(pendingAttachments.count == 1 ? "" : "s")"
        }
        layoutRightChatPanel()
    }

    func clearComposerDraft(for channelId: String) {
        guard !channelId.isEmpty else { return }
        composerDraftsByChannelId.removeValue(forKey: channelId)
    }

    // MARK: - Per-thread drafts

    /// The status that should be visible when no ephemeral message (typing,
    /// uploading, sending, …) is occupying the composer help label.
    func defaultComposerStatusText() -> String {
        if editingPostId != nil { return "Editing • Esc to cancel" }
        if !pendingAttachments.isEmpty {
            return "Attached \(pendingAttachments.count) file\(pendingAttachments.count == 1 ? "" : "s")"
        }
        return "Help"
    }

    func saveThreadDraft() {
        guard !threadRootId.isEmpty else { return }
        let text = threadReplyField.stringValue
        if text.isEmpty {
            threadDraftsByRootId.removeValue(forKey: threadRootId)
        } else {
            threadDraftsByRootId[threadRootId] = text
        }
    }

    func restoreThreadDraft() {
        threadReplyField.stringValue = threadDraftsByRootId[threadRootId] ?? ""
        threadPlaceholderLabel.isHidden = !threadReplyField.stringValue.isEmpty
    }

    func clearThreadDraft(for rootId: String) {
        guard !rootId.isEmpty else { return }
        threadDraftsByRootId.removeValue(forKey: rootId)
    }

    func setComposerDropHighlight(_ active: Bool) {
        chatEntryPanel.color = active
            ? Theme.shared.buttonBg
            : Theme.shared.centerText.withAlphaComponent(0.16)
        chatEntryPanel.setNeedsAppearanceUpdate()
        if active {
            composerHelpLabel.stringValue = "Drop files to attach"
        } else if pendingAttachments.isEmpty {
            composerHelpLabel.stringValue = "Help"
        } else {
            composerHelpLabel.stringValue = "Attached \(pendingAttachments.count) file\(pendingAttachments.count == 1 ? "" : "s")"
        }
    }

    func applyComposerToolbarVisibility() {
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

    func toggleComposerToolbar() {
        isComposerToolbarVisible.toggle()
        applyComposerToolbarVisibility()
        layoutRightChatPanel()
        rebuildTimelineContent(scrollToBottom: true)
    }

    func updateComposerSendState() {
        let hasActiveUpload = activeAttachmentUploads.contains {
            $0.channelId == activeChannelId && $0.isInProgress
        }
        let hasText =
            (!entryView.string.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty
                || !pendingAttachments.isEmpty)
            && !hasActiveUpload
        guard hasText != composerSendEnabled else { return }
        composerSendEnabled = hasText
        if hasText {
            composerSendButton.color = Theme.shared.buttonBg
            composerSendIconView?.contentTintColor = .white
        } else {
            composerSendButton.color = Theme.shared.centerText.withAlphaComponent(0.08)
            composerSendIconView?.contentTintColor = Theme.shared.centerText.withAlphaComponent(0.32)
        }
        composerSendButton.setNeedsAppearanceUpdate()
    }

    func startEditingLastMessage() -> Bool {
        guard editingPostId == nil, pendingAttachments.isEmpty else { return false }
        closeCompletion()
        let myId = currentUser?.id ?? webService?.currentUserId ?? ""
        guard !myId.isEmpty else { return false }
        guard let post = currentChannelPosts.last(where: {
            $0.user_id == myId
                && ($0.delete_at ?? 0) == 0
                && !($0.type?.hasPrefix("system_") ?? false)
        }) else { return false }

        editingPostId = post.id
        entryView.string = post.message
        entryView.needsDisplay = true
        updateComposerSendState()
        composerHelpLabel.stringValue = "Editing • Esc to cancel"
        makeFirstResponder(entryView)
        entryView.setSelectedRange(NSRange(location: (post.message as NSString).length, length: 0))
        return true
    }

    func cancelEditing() -> Bool {
        guard editingPostId != nil else { return false }
        closeCompletion()
        editingPostId = nil
        entryView.string = ""
        entryView.needsDisplay = true
        updateComposerSendState()
        composerHelpLabel.stringValue = "Help"
        return true
    }

    func sendComposerMessage() {
        let message = entryView.string.trimmingCharacters(in: .whitespacesAndNewlines)
        let fileIds = pendingAttachments.map { $0.id }
        guard !message.isEmpty || !fileIds.isEmpty, !activeChannelId.isEmpty else { return }
        let channelId = activeChannelId
        let editingId = editingPostId

        if editingId != nil && !fileIds.isEmpty {
            composerHelpLabel.stringValue = "Remove attachments to edit"
            return
        }

        closeCompletion()

        if let editingId = editingId {
            entryView.string = ""
            entryView.needsDisplay = true
            updateComposerSendState()
            composerHelpLabel.stringValue = "Saving edit…"
            Task { @MainActor [weak self] in
                guard let self = self, let ws = self.webService else { return }
                do {
                    let updated = try await ws.patchPost(postId: editingId, message: message)
                    if self.activeChannelId == channelId {
                        self.editingPostId = nil
                        self.applyUpdatedPost(updated)
                        self.composerHelpLabel.stringValue = self.defaultComposerStatusText()
                    }
                    self.clearComposerDraft(for: channelId)
                } catch {
                    if self.activeChannelId == channelId {
                        self.composerHelpLabel.stringValue = "Edit failed"
                        if self.entryView.string.isEmpty {
                            self.entryView.string = message
                            self.updateComposerSendState()
                        }
                        DispatchQueue.main.asyncAfter(deadline: .now() + 4) { [weak self] in
                            guard let self = self, self.activeChannelId == channelId else { return }
                            self.composerHelpLabel.stringValue = self.defaultComposerStatusText()
                        }
                    } else {
                        var draft = self.composerDraftsByChannelId[channelId]
                            ?? ComposerDraft(text: "", attachments: [], editingPostId: editingId)
                        if draft.text.isEmpty { draft.text = message }
                        draft.editingPostId = editingId
                        self.composerDraftsByChannelId[channelId] = draft
                    }
                    NSLog("Failed to save edit: \(error.localizedDescription)")
                }
            }
            return
        }

        // Optimistic send: show the post immediately with a sending state and
        // keep it retryable if the request fails.
        let clip = timelineScrollView.contentView
        let wasNearBottom = clip.bounds.maxY >= (timelineDocView.frame.height - 40)
        let pending = PendingOutgoingPost(
            id: UUID().uuidString,
            channelId: channelId,
            message: message,
            fileIds: fileIds,
            status: .sending
        )
        pendingOutgoingPosts.append(pending)
        entryView.string = ""
        entryView.needsDisplay = true
        pendingAttachments.removeAll()
        renderPendingAttachments()
        updateComposerSendState()
        clearComposerDraft(for: channelId)
        composerHelpLabel.stringValue = "Sending…"
        layoutRightChatPanel()
        rebuildTimelineContent(scrollToBottom: wasNearBottom)
        sendPendingPost(id: pending.id)
    }

    func sendPendingPost(id: String) {
        guard let index = pendingOutgoingPosts.firstIndex(where: { $0.id == id }),
              let ws = webService else { return }
        let pending = pendingOutgoingPosts[index]
        pendingOutgoingPosts[index].status = .sending
        if pending.channelId == activeChannelId {
            rebuildTimelineContent(scrollToBottom: false)
        }
        Task { @MainActor [weak self] in
            guard let self = self else { return }
            do {
                let post = try await ws.createPost(
                    channelId: pending.channelId,
                    message: pending.message,
                    fileIds: pending.fileIds
                )
                self.pendingOutgoingPosts.removeAll { $0.id == id }
                if self.activeChannelId == pending.channelId {
                    if !self.currentChannelPosts.contains(where: { $0.id == post.id }) {
                        self.currentChannelPosts.append(post)
                    }
                    self.composerHelpLabel.stringValue = self.defaultComposerStatusText()
                    self.rebuildTimelineContent(scrollToBottom: true)
                }
            } catch {
                if let failedIndex = self.pendingOutgoingPosts.firstIndex(where: { $0.id == id }) {
                    self.pendingOutgoingPosts[failedIndex].status = .failed(error.localizedDescription)
                }
                if self.activeChannelId == pending.channelId {
                    self.composerHelpLabel.stringValue = L10n.string("Message failed to send")
                    self.rebuildTimelineContent(scrollToBottom: false)
                }
                NSLog("Failed to send post: \(error.localizedDescription)")
            }
        }
    }

    func retryPendingPost(id: String) {
        guard let index = pendingOutgoingPosts.firstIndex(where: { $0.id == id }) else { return }
        if case .sending = pendingOutgoingPosts[index].status { return }
        pendingOutgoingPosts[index].status = .sending
        sendPendingPost(id: id)
    }

    func deletePendingPost(id: String) {
        pendingOutgoingPosts.removeAll { $0.id == id }
        rebuildTimelineContent(scrollToBottom: false)
    }

    func controlTextDidChange(_ notification: Notification) {
        if (notification.object as? NSTextField) === emojiSearchField {
            renderEmojiGrid()
            return
        }
        if (notification.object as? NSTextField) === dmSearchField {
            renderDMUsers()
            return
        }
        if (notification.object as? NSTextField) === threadReplyField {
            threadPlaceholderLabel.isHidden = !threadReplyField.stringValue.isEmpty
            return
        }
        if (notification.object as? NSTextField) === searchPopoverInputLabel {
            if searchPopoverInputLabel.stringValue.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty {
                showRecentSearchesIfNeeded()
            } else {
                hideRecentSearches()
            }
            return
        }
        guard (notification.object as? NSTextField) === findChannelLabel else { return }
        channelFilterQuery = findChannelLabel.stringValue.trimmingCharacters(in: .whitespacesAndNewlines)
        layoutLeftSidebar(topBarY: mainPanel.bounds.height)
    }

    func applyComposerFormat(_ symbol: String) {
        guard activeChannelId.isEmpty == false else { return }
        makeFirstResponder(entryView)
        let range = entryView.selectedRange()
        let text = entryView.string as NSString
        let selected = range.location <= text.length && range.location + range.length <= text.length
            ? text.substring(with: range)
            : ""
        let prefix: String
        let suffix: String
        switch symbol {
        case "bold":
            prefix = "**"; suffix = "**"
        case "italic":
            prefix = "_"; suffix = "_"
        case "strikethrough":
            prefix = "~~"; suffix = "~~"
        case "link":
            prefix = "["; suffix = "](https://)"
        case "chevron.left.forwardslash.chevron.right":
            prefix = "`"; suffix = "`"
        case "text.quote":
            prefix = "> "; suffix = ""
        case "list.bullet":
            prefix = "- "; suffix = ""
        case "list.number":
            prefix = "1. "; suffix = ""
        case "number":
            prefix = "# "; suffix = ""
        default:
            return
        }
        entryView.insertText(prefix + selected + suffix, replacementRange: range)
        let selectedLocation = range.location + (prefix as NSString).length
        entryView.setSelectedRange(NSRange(location: selectedLocation, length: (selected as NSString).length))
        updateComposerSendState()
    }

    func sendTypingIfNeeded() {
        guard !entryView.string.isEmpty, !activeChannelId.isEmpty else { return }
        if let last = lastTypingSentAt, Date().timeIntervalSince(last) < 1.5 { return }
        lastTypingSentAt = Date()
        webService?.sendUserTyping(channelId: activeChannelId)
    }

    func textDidChange(_ notification: Notification) {
        guard (notification.object as? NSTextView) === entryView else { return }
        entryView.needsDisplay = true
        updateComposerSendState()
        sendTypingIfNeeded()
        updateCompletion()
    }

    func textViewDidChangeSelection(_ notification: Notification) {
        guard (notification.object as? NSTextView) === entryView else { return }
        updateCompletion()
    }

    func textView(_ textView: NSTextView, doCommandBy commandSelector: Selector) -> Bool {
        guard textView === entryView else { return false }
        if isCompletionVisible {
            if commandSelector == #selector(NSResponder.moveUp(_:)) {
                return moveCompletionSelection(by: -1)
            }
            if commandSelector == #selector(NSResponder.moveDown(_:)) {
                return moveCompletionSelection(by: 1)
            }
            if commandSelector == #selector(NSResponder.insertNewline(_:)) {
                acceptCompletion(at: completionSelectedIndex)
                return true
            }
            if commandSelector == #selector(NSResponder.insertTab(_:)) {
                acceptCompletion(at: completionSelectedIndex)
                return true
            }
            if commandSelector == #selector(NSResponder.cancelOperation(_:)) {
                closeCompletion()
                return true
            }
        }
        if commandSelector == #selector(NSResponder.insertNewline(_:)) {
            // Shift+Return inserts a newline; Return sends.
            if NSApp.currentEvent?.modifierFlags.contains(.shift) == true { return false }
            sendComposerMessage()
            return true
        }
        if commandSelector == #selector(NSResponder.moveUp(_:)) {
            let shiftHeld = NSApp.currentEvent?.modifierFlags.contains(.shift) ?? false
            if !shiftHeld,
               editingPostId == nil,
               entryView.string.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty {
                return startEditingLastMessage()
            }
            return false
        }
        return false
    }
}
