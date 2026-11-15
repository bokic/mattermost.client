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
        emojiPanel.cornerRadius = 4
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
            button.cornerRadius = 4
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
            button.cornerRadius = 3
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
            if !self.customEmojiImages.isEmpty {
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
                .filter { $0.type == "O" || $0.type == "P" }
                .filter { channel in
                    query.isEmpty
                        || channel.name.lowercased().contains(query)
                        || channel.display_name.lowercased().contains(query)
                }
                .sorted { $0.display_name.localizedCaseInsensitiveCompare($1.display_name) == .orderedAscending }
                .map { channel in
                    CompletionItem(
                        kind: .channel,
                        title: "#" + channel.name,
                        subtitle: channel.display_name,
                        insertText: "#" + channel.name + " ",
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
            row.cornerRadius = 4
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
                avatar.cornerRadius = 10
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

    func uploadFiles(_ urls: [URL]) {
        let files = urls.filter { !$0.hasDirectoryPath }
        guard !files.isEmpty,
              !activeChannelId.isEmpty,
              let ws = webService else { return }
        let channelId = activeChannelId
        composerHelpLabel.stringValue = files.count == 1 ? "Uploading…" : "Uploading \(files.count) files…"

        Task { @MainActor [weak self] in
            guard let self = self else { return }
            var uploaded: [PendingAttachment] = []
            for url in files {
                let accessed = url.startAccessingSecurityScopedResource()
                let data = try? Data(contentsOf: url)
                if accessed { url.stopAccessingSecurityScopedResource() }
                guard let data = data else { continue }
                let mime = UTType(filenameExtension: url.pathExtension)?.preferredMIMEType ?? "application/octet-stream"
                if let fileId = try? await ws.uploadFile(
                    channelId: channelId,
                    data: data,
                    filename: url.lastPathComponent,
                    mimeType: mime
                ) {
                    uploaded.append(PendingAttachment(id: fileId, name: url.lastPathComponent, size: Int64(data.count)))
                }
            }
            guard !uploaded.isEmpty else {
                self.composerHelpLabel.stringValue = "Upload failed"
                DispatchQueue.main.asyncAfter(deadline: .now() + 4) { [weak self] in
                    self?.composerHelpLabel.stringValue = "Help"
                }
                return
            }
            self.pendingAttachments.append(contentsOf: uploaded)
            self.layoutRightChatPanel()
            self.renderPendingAttachments()
            self.scrollTimelineToBottom()
            self.updateComposerSendState()
            self.composerHelpLabel.stringValue = "Attached \(self.pendingAttachments.count) file\(self.pendingAttachments.count == 1 ? "" : "s")"
        }
    }

    func renderPendingAttachments() {
        composerAttachmentTray.subviews.forEach { $0.removeFromSuperview() }
        composerAttachmentTray.isHidden = pendingAttachments.isEmpty
        guard !pendingAttachments.isEmpty else { return }

        let trayWidth = max(composerAttachmentTray.bounds.width, 200)
        let chipW: CGFloat = 168
        let chipH: CGFloat = 24
        let gap: CGFloat = 6
        let maxVisible = max(1, Int((trayWidth + gap) / (chipW + gap)))
        var x: CGFloat = 0

        for attachment in pendingAttachments.prefix(maxVisible) {
            let chip = RoundedEdgePanel()
            chip.cornerRadius = 4
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
            remove.cornerRadius = 3
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
        }

        if pendingAttachments.count > maxVisible {
            let more = NSTextField(labelWithString: "+\(pendingAttachments.count - maxVisible)")
            more.font = MMFont.font(ofSize: 11, weight: .semibold)
            more.textColor = Theme.shared.centerTextMuted
            more.isEditable = false
            more.isSelectable = false
            more.frame = NSRect(x: x + 2, y: 7, width: 32, height: 14)
            composerAttachmentTray.addSubview(more)
        }
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
        let hasText = !entryView.string.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty
            || !pendingAttachments.isEmpty
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
        entryView.string = ""
        entryView.needsDisplay = true
        updateComposerSendState()
        composerHelpLabel.stringValue = editingId != nil ? "Saving edit…" : "Sending…"

        Task { @MainActor [weak self] in
            guard let self = self, let ws = webService else { return }
            do {
                if let editingId = editingId {
                    let updated = try await ws.patchPost(postId: editingId, message: message)
                    self.editingPostId = nil
                    self.applyUpdatedPost(updated)
                } else {
                    let post = try await ws.createPost(
                        channelId: channelId,
                        message: message,
                        fileIds: fileIds
                    )
                    if self.activeChannelId == channelId {
                        self.currentChannelPosts.append(post)
                        self.rebuildTimelineContent(scrollToBottom: true)
                    }
                    if !fileIds.isEmpty {
                        self.pendingAttachments.removeAll()
                        self.renderPendingAttachments()
                        self.layoutRightChatPanel()
                        self.scrollTimelineToBottom()
                    }
                }
                self.composerHelpLabel.stringValue = "Help"
            } catch {
                self.editingPostId = editingId
                self.composerHelpLabel.stringValue = editingId != nil ? "Edit failed" : "Message failed to send"
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
            guard let self = self, let ws = webService else { return }
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
        guard (notification.object as? NSTextField) === findChannelLabel else { return }
        channelFilterQuery = findChannelLabel.stringValue.trimmingCharacters(in: .whitespacesAndNewlines)
        layoutLeftSidebar(topBarY: mainPanel.bounds.height)
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
