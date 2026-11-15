//
//  MainWindow+Timeline.swift
//  mattermost.client
//
//  Split from MainWindow.swift.
//

import AppKit
import Foundation
import UniformTypeIdentifiers

extension MainWindow {

    func createNewMessagesDivider(width: CGFloat) -> NSView {
        let container = TimelineFlippedView()
        container.frame = NSRect(x: 0, y: 0, width: width, height: 34)
        // Web `.NotificationSeparator`: 50% orange rule behind a white pill with
        // 13pt regular orange text and 13pt horizontal padding.
        let orange = MMPalette.newMessages
        let lineColor = MMPalette.newMessagesLine

        let line = RoundedEdgePanel()
        line.cornerRadius = 0
        line.color = lineColor
        line.frame = NSRect(x: 20, y: 16, width: max(0, width - 40), height: 1)
        container.addSubview(line)

        let font = MMFont.font(ofSize: 13)
        let text = "New Messages"
        let textSize = (text as NSString).size(withAttributes: [.font: font])
        let textW = ceil(textSize.width)
        let textH = ceil(textSize.height)
        let pillW = textW + 26
        let pillH: CGFloat = 26
        let pill = RoundedEdgePanel()
        pill.color = Theme.shared.centerBg
        pill.cornerRadius = pillH / 2
        pill.frame = NSRect(x: (width - pillW) / 2, y: 4, width: pillW, height: pillH)
        let label = NSTextField(labelWithString: text)
        label.font = font
        label.textColor = orange
        label.alignment = .center
        label.isEditable = false
        label.isSelectable = false
        label.frame = NSRect(x: 0, y: (pillH - textH) / 2, width: pillW, height: textH)
        pill.addSubview(label)
        container.addSubview(pill)
        return container
    }

    func setupNewMessagesPill() {
        newMessagesPill.color = Theme.shared.buttonBg
        newMessagesPill.cornerRadius = MMRadius.control
        newMessagesPill.isHidden = true
        newMessagesPill.onClick = { [weak self] in
            self?.jumpToNewMessages()
        }

        newMessagesPillIcon.image = NSImage(systemSymbolName: "arrow.down", accessibilityDescription: "Jump to new messages")?
            .withSymbolConfiguration(.init(pointSize: 12, weight: .bold))
        newMessagesPillIcon.contentTintColor = .white
        newMessagesPill.addSubview(newMessagesPillIcon)

        newMessagesPillLabel.font = MMFont.font(ofSize: 13, weight: .bold)
        newMessagesPillLabel.textColor = .white
        newMessagesPillLabel.isEditable = false
        newMessagesPillLabel.isSelectable = false
        newMessagesPill.addSubview(newMessagesPillLabel)

        chatPanel.addSubview(newMessagesPill)
    }

    func jumpToNewMessages() {
        guard let divider = newMessagesDividerView else { return }
        let clip = timelineScrollView.contentView
        let maxY = max(0, timelineDocView.frame.height - clip.bounds.height)
        let target = min(maxY, max(0, divider.frame.minY - 16))
        clip.scroll(to: NSPoint(x: 0, y: target))
        timelineScrollView.reflectScrolledClipView(clip)
        updateNewMessagesDividerState()
    }

    func layoutNewMessagesPill() {
        let listRight = isRightPanelVisible ? rightPanel.frame.minX : chatPanel.bounds.width
        let availableWidth = max(0, listRight - 30)
        guard availableWidth > 20 else { return }
        let font = newMessagesPillLabel.font ?? MMFont.font(ofSize: 13, weight: .bold)
        let textW = ceil((newMessagesPillLabel.stringValue as NSString).size(withAttributes: [.font: font]).width)
        let groupW = 16 + 6 + textW
        // Size the pill to its contents instead of spanning the whole timeline:
        // a full-width strip swallows clicks in a large part of the message area.
        let pillW = min(availableWidth, groupW + 24)
        newMessagesPill.frame = NSRect(
            x: 15 + (availableWidth - pillW) / 2,
            y: newMessagesPill.frame.minY,
            width: pillW,
            height: 32
        )
        let startX = max(8, (pillW - groupW) / 2)
        newMessagesPillIcon.frame = NSRect(x: startX, y: 8, width: 16, height: 16)
        newMessagesPillLabel.frame = NSRect(x: startX + 22, y: 8, width: textW + 2, height: 16)
    }

    func updateNewMessagesDividerState() {
        guard let divider = newMessagesDividerView, !divider.isHidden else {
            newMessagesPill.isHidden = true
            return
        }
        let visible = timelineScrollView.contentView.bounds
        let isAbove = divider.frame.maxY < visible.minY
        let isBelow = divider.frame.minY > visible.maxY

        if newMessagesDividerArmed && isAbove {
            divider.isHidden = true
            newMessagesDividerView = nil
            newMessagesDividerPostId = nil
            newMessagesCount = 0
            newMessagesPill.isHidden = true
            return
        }

        if isBelow, newMessagesCount > 0 {
            let noun = newMessagesCount == 1 ? "message" : "messages"
            newMessagesPillLabel.stringValue = "\(newMessagesCount) new \(noun)"
            layoutNewMessagesPill()
            newMessagesPill.isHidden = false
        } else {
            newMessagesPill.isHidden = true
        }
    }

    func layoutHeroSubviews(heroW: CGFloat) {
        let isBot = isCurrentChannelBot()
        let currentCh = activeChannelId.isEmpty ? nil : channelsById[activeChannelId]
        let isDM = (currentCh?.type == "D" || currentCh?.type == "G") || isBot
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
            heroIllustrationCircle.color = Theme.shared.centerHover
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

    func createDateSeparator(dateStr: String, width: CGFloat) -> NSView {
        let container = TimelineFlippedView()
        let dividerColor = Theme.shared.centerText.withAlphaComponent(0.16)
        let separatorText = Theme.shared.centerText

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
        pill.color = Theme.shared.centerBg
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

    func createFallbackAnimatedGif() -> NSImage? {
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

    func parseGiphyInMessage(_ message: String) -> ParsedGiphyMessage {
        var text = message
        var gifURLs: [String] = []

        func isGiphyOrGifURL(_ urlStr: String) -> Bool {
            guard let url = URL(string: urlStr) else { return false }
            let host = (url.host ?? "").lowercased()
            let path = url.path.lowercased()
            if host.contains("giphy.com") || host.contains("gph.is") { return true }
            let imageExtensions = [".gif", ".webp", ".png", ".jpg", ".jpeg", ".bmp"]
            if imageExtensions.contains(where: { path.hasSuffix($0) }) { return true }
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

    func pixelSize(of image: NSImage) -> NSSize {
        if let rep = image.representations.max(by: {
            ($0.pixelsWide * $0.pixelsHigh) < ($1.pixelsWide * $1.pixelsHigh)
        }), rep.pixelsWide > 0, rep.pixelsHigh > 0 {
            return NSSize(width: rep.pixelsWide, height: rep.pixelsHigh)
        }
        return image.size
    }

    func fitImageSize(natural: NSSize, maxWidth: CGFloat, maxHeight: CGFloat) -> NSSize {
        guard natural.width > 0, natural.height > 0 else {
            return NSSize(width: min(240, maxWidth), height: min(160, maxHeight))
        }
        var width = min(natural.width, maxWidth)
        var height = width * natural.height / natural.width
        if height > maxHeight {
            height = maxHeight
            width = height * natural.width / natural.height
        }
        return NSSize(width: max(1, floor(width)), height: max(1, floor(height)))
    }

    func createInlineImageView(urlString: String, maxWidth: CGFloat, authorId: String? = nil) -> (NSView, CGFloat) {
        let maxHeight: CGFloat = 350
        guard loadRemoteImagesAutomatically else {
            let container = RoundedEdgePanel()
            container.cornerRadius = MMRadius.control
            container.color = Theme.shared.centerHover
            container.frame = NSRect(x: 0, y: 0, width: min(maxWidth, 320), height: 32)
            let label = NSTextField(labelWithString: "Remote image (loading disabled)")
            label.font = MMFont.font(ofSize: 12)
            label.textColor = Theme.shared.centerTextMuted
            label.isEditable = false
            label.isSelectable = false
            label.frame = NSRect(x: 10, y: 6, width: container.frame.width - 20, height: 18)
            container.addSubview(label)
            return (container, 32)
        }
        var naturalSize = inlineImageSizeCache[urlString] ?? NSSize(width: 240, height: 160)

        // Use a disk-cached frame to establish the natural size before the network fetch.
        var cachedImage: NSImage?
        let cacheDir = FileManager.default.urls(for: .cachesDirectory, in: .userDomainMask).first?
            .appendingPathComponent("mattermost.client/giphy", isDirectory: true)
        if let dir = cacheDir {
            let sampleFile = dir.appendingPathComponent("sample_giphy.gif")
            let filename = TimelineCacheKey.stable(urlString) + ".gif"
            let diskURL = dir.appendingPathComponent(filename)
            let checkURL = (urlString.contains("ICOgUNjpvO0PC") && FileManager.default.fileExists(atPath: sampleFile.path)) ? sampleFile : diskURL
            if let data = try? Data(contentsOf: checkURL), let image = NSImage(data: data) {
                cachedImage = image
                let pixels = pixelSize(of: image)
                if inlineImageSizeCache[urlString] == nil, pixels.width > 0, pixels.height > 0 {
                    naturalSize = pixels
                }
            }
        }

        let displaySize = fitImageSize(natural: naturalSize, maxWidth: maxWidth, maxHeight: maxHeight)
        let container = RoundedEdgePanel()
        container.cornerRadius = MMRadius.control
        container.color = .clear
        container.clipContentToBounds = true
        container.frame = NSRect(x: 0, y: 0, width: displaySize.width, height: displaySize.height)

        let imageView = NSImageView(frame: NSRect(origin: .zero, size: displaySize))
        imageView.animates = true
        imageView.imageScaling = .scaleProportionallyUpOrDown
        imageView.imageAlignment = .alignLeft
        imageView.wantsLayer = true
        imageView.layer?.cornerRadius = MMRadius.control
        imageView.layer?.masksToBounds = true
        imageView.image = cachedImage
        container.addSubview(imageView)

        container.onClick = { [weak self, weak imageView] in
            let name = URL(string: urlString)?.lastPathComponent ?? "Image"
            self?.showLightbox(image: imageView?.image, remoteURL: urlString, filename: name, authorId: authorId)
        }

        loadGiphyAnimatedImage(from: urlString) { [weak self, weak container, weak imageView] image in
            guard let self = self, let image = image else { return }
            imageView?.image = image
            let pixels = self.pixelSize(of: image)
            guard pixels.width > 0, pixels.height > 0 else { return }
            let wasUncached = self.inlineImageSizeCache[urlString] == nil
            self.inlineImageSizeCache[urlString] = pixels
            let fitted = self.fitImageSize(natural: pixels, maxWidth: maxWidth, maxHeight: maxHeight)
            if abs(fitted.width - displaySize.width) > 1 || abs(fitted.height - displaySize.height) > 1 {
                container?.frame.size = fitted
                imageView?.frame = NSRect(origin: .zero, size: fitted)
                if wasUncached {
                    self.scheduleImageRelayout()
                }
            }
        }

        return (container, displaySize.height)
    }

    func scheduleImageRelayout() {
        guard !isRelayoutScheduled else { return }
        isRelayoutScheduled = true
        DispatchQueue.main.async { [weak self] in
            guard let self = self else { return }
            self.isRelayoutScheduled = false
            if self.isRightPanelVisible && self.rightPanelMode == .thread {
                self.renderThreadPanel()
            }
            self.rebuildTimelineContent()
        }
    }

    func loadGiphyAnimatedImage(from urlString: String, completion: @escaping @MainActor @Sendable (NSImage?) -> Void) {
        let cacheDir = FileManager.default.urls(for: .cachesDirectory, in: .userDomainMask).first?.appendingPathComponent("mattermost.client/giphy", isDirectory: true)
        if let dir = cacheDir {
            try? FileManager.default.createDirectory(at: dir, withIntermediateDirectories: true)
            let sampleFile = dir.appendingPathComponent("sample_giphy.gif")
            if urlString.contains("ICOgUNjpvO0PC"), let data = try? Data(contentsOf: sampleFile), let img = NSImage(data: data) {
                completion(img)
                return
            }
            let filename = TimelineCacheKey.stable(urlString) + ".gif"
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

        URLSession.shared.dataTask(with: request) { data, _, _ in
            let responseData = data
            let maxBytes = 20 * 1024 * 1024
            if let data = responseData, let dir = cacheDir, data.count <= maxBytes {
                let filename = TimelineCacheKey.stable(urlString) + ".gif"
                let diskURL = dir.appendingPathComponent(filename)
                try? data.write(to: diskURL)
                Self.pruneGiphyCache(dir, keeping: 200)
            }
            Task { @MainActor in
                if let data = responseData, data.count <= maxBytes, let image = NSImage(data: data) {
                    completion(image)
                } else {
                    completion(self.createFallbackAnimatedGif())
                }
            }
        }.resume()
    }

    nonisolated static func pruneGiphyCache(_ directory: URL, keeping limit: Int) {
        let fm = FileManager.default
        guard let files = try? fm.contentsOfDirectory(
            at: directory,
            includingPropertiesForKeys: [.contentModificationDateKey],
            options: [.skipsHiddenFiles]
        ) else { return }
        let gifs = files.filter { $0.pathExtension.lowercased() == "gif" }
        guard gifs.count > limit else { return }
        let sorted = gifs.sorted {
            let lhs = (try? $0.resourceValues(forKeys: [.contentModificationDateKey]))?.contentModificationDate ?? .distantPast
            let rhs = (try? $1.resourceValues(forKeys: [.contentModificationDateKey]))?.contentModificationDate ?? .distantPast
            return lhs < rhs
        }
        for file in sorted.prefix(gifs.count - limit) {
            try? fm.removeItem(at: file)
        }
    }

    func appendEditedIndicator(to attributedString: NSMutableAttributedString, font: NSFont, editDate: Date?) {
        let editFont = MMFont.font(ofSize: max(10, font.pointSize - 2))
        let editColor = Theme.shared.centerTextPlaceholder

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
            tooltipAttrs[.toolTip] = "Edited at \(Self.localizedTimeFormatter.string(from: date))"
        } else {
            tooltipAttrs[.toolTip] = "Edited"
        }

        attributedString.append(NSAttributedString(attachment: att))
        attributedString.append(NSAttributedString(string: " Edited", attributes: tooltipAttrs))
    }

    func addReactionChips(for post: MMPost, to row: NSView, x: CGFloat, y: CGFloat) -> CGFloat {
        let groups = groupedReactions(post)
        guard !groups.isEmpty else { return 0 }

        let blue = Theme.shared.buttonBg
        let centerColor = Theme.shared.centerText
        let chipY = y + 4
        var chipX = x
        let emojiW: CGFloat = 16
        let countFont = MMFont.font(ofSize: 11, weight: .semibold)

        for (emoji, count) in groups {
            let reacted = currentUserReacted(post, emoji: emoji)
            let glyph = emojiGlyph(for: emoji)
            let countText = String(count)
            let countW = ceil((countText as NSString).size(withAttributes: [.font: countFont]).width)
            let spacing: CGFloat = 2
            let chipW = max(28, ceil(5 + emojiW + spacing + countW + 5))

            let chip = RoundedEdgePanel()
            chip.cornerRadius = MMRadius.control
            chip.color = reacted
                ? Theme.shared.buttonBg.withAlphaComponent(0.08)
                : Theme.shared.centerText.withAlphaComponent(0.08)
            chip.borderWidth = 1
            chip.borderColor = reacted ? blue : .clear
            chip.frame = NSRect(x: chipX, y: chipY, width: chipW, height: 24)

            let emojiLabel = NSTextField(labelWithString: glyph)
            emojiLabel.font = MMFont.font(ofSize: 15)
            emojiLabel.textColor = reacted ? blue : centerColor.withAlphaComponent(0.75)
            emojiLabel.alignment = .center
            emojiLabel.isEditable = false
            emojiLabel.isSelectable = false
            emojiLabel.frame = NSRect(x: 5, y: 3, width: emojiW, height: 18)
            chip.addSubview(emojiLabel)

            var chipCountLabel: NSTextField?
            if !countText.isEmpty {
                let countLabel = NSTextField(labelWithString: countText)
                countLabel.font = countFont
                countLabel.textColor = reacted ? blue : centerColor.withAlphaComponent(0.75)
                countLabel.isEditable = false
                countLabel.isSelectable = false
                countLabel.frame = NSRect(x: 5 + emojiW + spacing, y: 5, width: countW + 1, height: 16)
                chip.addSubview(countLabel)
                chipCountLabel = countLabel
            }

            let postId = post.id
            let emojiName = emoji
            chip.onHoverChanged = { [weak chip, weak emojiLabel, weak chipCountLabel] isHovered in
                // `.Reaction:hover` uses the post background for both states; reacted
                // chips keep their blue border and text.
                guard let chip = chip else { return }
                let idleFill = reacted
                    ? Theme.shared.buttonBg.withAlphaComponent(0.08)
                    : Theme.shared.centerText.withAlphaComponent(0.08)
                chip.color = isHovered ? Theme.shared.centerBg : idleFill
                chip.borderColor = reacted
                    ? blue
                    : (isHovered ? Theme.shared.centerText.withAlphaComponent(0.16) : .clear)
                emojiLabel?.textColor = reacted ? blue : centerColor.withAlphaComponent(0.75)
                chipCountLabel?.textColor = reacted ? blue : centerColor.withAlphaComponent(0.75)
                chip.setNeedsAppearanceUpdate()
            }
            chip.onClick = { [weak self] in
                self?.toggleReaction(postId: postId, emojiName: emojiName)
            }
            row.addSubview(chip)
            chipX += chipW + 4
        }

        // The add-reaction chip only exists when a post already has reactions, and
        // is revealed while the row is hovered (`.post:hover .Reaction__add`).
        let addChip = RoundedEdgePanel()
        addChip.cornerRadius = MMRadius.control
        addChip.color = Theme.shared.centerText.withAlphaComponent(0.08)
        addChip.borderWidth = 1
        addChip.borderColor = .clear
        addChip.frame = NSRect(x: chipX, y: chipY, width: 28, height: 24)
        let plus = NSTextField(labelWithString: "+")
        plus.font = MMFont.font(ofSize: 17, weight: .medium)
        plus.textColor = centerColor.withAlphaComponent(0.75)
        plus.alignment = .center
        plus.isEditable = false
        plus.isSelectable = false
        plus.frame = NSRect(x: 0, y: 2, width: 28, height: 20)
        addChip.addSubview(plus)
        addChip.onHoverChanged = { [weak addChip] isHovered in
            addChip?.color = isHovered
                ? Theme.shared.centerText.withAlphaComponent(0.12)
                : Theme.shared.centerText.withAlphaComponent(0.08)
            addChip?.setNeedsAppearanceUpdate()
        }
        addChip.onClick = { [weak self, weak addChip] in
            guard let self = self, let addChip = addChip else { return }
            self.showReactionPicker(for: post, anchor: addChip)
        }
        addChip.isHidden = true
        row.addSubview(addChip)
        (row as? TimelineRowView)?.reactionAddChip = addChip

        return 32
    }

    func addHoverToolbar(for post: MMPost, to row: NSView, width: CGFloat, compact: Bool = false) -> RoundedEdgePanel {
        let toolbar = RoundedEdgePanel()
        toolbar.cornerRadius = MMRadius.control
        toolbar.color = Theme.shared.centerBg
        toolbar.borderWidth = 1
        toolbar.borderColor = Theme.shared.centerText.withAlphaComponent(0.2)
        toolbar.shadowColor = .black
        toolbar.shadowOpacity = 0.08
        toolbar.shadowRadius = 3
        toolbar.shadowOffset = CGSize(width: 0, height: -2)

        let buttonSize: CGFloat = compact ? 24 : 28
        let toolbarHeight: CGFloat = compact ? 24 : 38
        let toolbarWidth = buttonSize * 3 + (compact ? 4 : 8)
        let inset: CGFloat = compact ? 2 : 4
        toolbar.frame = NSRect(
            x: width - toolbarWidth,
            y: compact ? 0 : 4,
            width: toolbarWidth,
            height: toolbarHeight
        )
        toolbar.isHidden = true

        let postRef = post
        let entries: [(symbol: String, label: String, action: () -> Void)] = [
            ("face.smiling", "Add Reaction", { [weak self, weak toolbar] in
                guard let self = self, let toolbar = toolbar else { return }
                self.showReactionPicker(for: postRef, anchorRect: self.postToolbarAnchor(toolbar))
            }),
            ("arrowshape.turn.up.left", "Reply", { [weak self] in
                self?.showThread(for: postRef)
            }),
            ("ellipsis", "More", { [weak self, weak toolbar] in
                guard let self = self, let toolbar = toolbar else { return }
                self.showPostActionMenu(for: postRef, anchorRect: self.postToolbarAnchor(toolbar))
            })
        ]

        for (index, entry) in entries.enumerated() {
            let button = RoundedEdgePanel()
            button.cornerRadius = MMRadius.control
            button.color = .clear
            button.frame = NSRect(
                x: inset + CGFloat(index) * buttonSize,
                y: inset,
                width: buttonSize,
                height: buttonSize
            )

            let icon = NSImageView()
            if let image = NSImage(systemSymbolName: entry.symbol, accessibilityDescription: entry.label) {
                icon.image = image.withSymbolConfiguration(.init(pointSize: compact ? 13 : 15, weight: .regular))
                icon.contentTintColor = Theme.shared.centerText.withAlphaComponent(0.64)
            }
            let iconInset: CGFloat = compact ? 5 : 6
            icon.frame = NSRect(x: iconInset, y: iconInset, width: 16, height: 16)
            button.addSubview(icon)
            button.onHoverChanged = { [weak button, weak icon] isHovered in
                button?.color = isHovered
                    ? Theme.shared.centerText.withAlphaComponent(0.08)
                    : .clear
                icon?.contentTintColor = Theme.shared.centerText.withAlphaComponent(isHovered ? 0.8 : 0.64)
                button?.setNeedsAppearanceUpdate()
            }
            button.onClick = entry.action
            toolbar.addSubview(button)
        }

        row.addSubview(toolbar)
        return toolbar
    }

    func postToolbarAnchor(_ toolbar: RoundedEdgePanel) -> NSRect {
        guard let button = toolbar.subviews.compactMap({ $0 as? RoundedEdgePanel }).last else {
            return toolbar.convert(toolbar.bounds, to: chatPanel)
        }
        return button.convert(button.bounds, to: chatPanel)
    }

    func frameInChat(_ view: NSView) -> NSRect {
        return view.convert(view.bounds, to: chatPanel)
    }

    func currentUserReacted(_ post: MMPost, emoji: String) -> Bool {
        guard let myId = currentUserId(), !myId.isEmpty else { return false }
        return (post.metadata?.reactions ?? []).contains {
            $0.user_id == myId && $0.emoji_name == emoji
        }
    }

    func currentUserId() -> String? {
        if let id = currentUser?.id, !id.isEmpty { return id }
        let id = webService?.currentUserId ?? ""
        return id.isEmpty ? nil : id
    }

    func toggleReaction(postId: String, emojiName: String) {
        guard let ws = webService, ws.isLogged(),
              let userId = currentUserId() else { return }
        let post = currentChannelPosts.first(where: { $0.id == postId })
            ?? threadPosts.first(where: { $0.id == postId })
        guard let post = post else { return }
        let reacted = currentUserReacted(post, emoji: emojiName)

        Task { @MainActor [weak self] in
            guard let self = self else { return }
            do {
                if reacted {
                    try await ws.removeReaction(userId: userId, postId: postId, emojiName: emojiName)
                } else {
                    try await ws.addReaction(userId: userId, postId: postId, emojiName: emojiName)
                }
                if let updated = try? await ws.fetchPost(postId: postId) {
                    self.applyUpdatedPost(updated)
                }
            } catch {
                NSLog("Reaction update failed: \(error.localizedDescription)")
            }
        }
    }

    func applyUpdatedPost(_ post: MMPost) {
        let wasInTimeline = currentChannelPosts.contains { $0.id == post.id }
        if let index = currentChannelPosts.firstIndex(where: { $0.id == post.id }) {
            currentChannelPosts[index] = post
        }
        if let index = threadPosts.firstIndex(where: { $0.id == post.id }) {
            threadPosts[index] = post
        }
        if wasInTimeline {
            rebuildTimelineContent(scrollToBottom: false)
        }
        guard isRightPanelVisible else { return }
        switch rightPanelMode {
        case .thread:
            renderThreadPanel()
        case .pinned:
            loadPinnedPosts()
        case .mentions:
            loadMentions()
        case .saved:
            loadSavedPosts()
        case .threads:
            loadThreads()
        default:
            break
        }
    }

    func setupPostInteractionPanels() {
        reactionPickerPanel.color = Theme.shared.centerBg
        reactionPickerPanel.cornerRadius = MMRadius.menu
        reactionPickerPanel.borderWidth = 1
        reactionPickerPanel.borderColor = Theme.shared.centerText.withAlphaComponent(0.2)
        reactionPickerPanel.shadowColor = .black
        reactionPickerPanel.shadowOpacity = 0.12
        reactionPickerPanel.shadowRadius = 8
        reactionPickerPanel.shadowOffset = CGSize(width: 0, height: -2)
        reactionPickerPanel.isHidden = true
        chatPanel.addSubview(reactionPickerPanel)

        postActionMenu.color = Theme.shared.centerBg
        postActionMenu.cornerRadius = MMRadius.menu
        postActionMenu.borderWidth = 1
        postActionMenu.borderColor = Theme.shared.centerText.withAlphaComponent(0.2)
        postActionMenu.shadowColor = .black
        postActionMenu.shadowOpacity = 0.12
        postActionMenu.shadowRadius = 8
        postActionMenu.shadowOffset = CGSize(width: 0, height: -2)
        postActionMenu.isHidden = true
        chatPanel.addSubview(postActionMenu)
    }

    func setupLightbox() {
        lightboxOverlay.color = .clear
        lightboxOverlay.cornerRadius = 0
        lightboxOverlay.clipContentToBounds = true
        lightboxOverlay.isHidden = true

        lightboxHeaderPanel.cornerRadius = 0
        lightboxHeaderPanel.color = .black
        lightboxOverlay.addSubview(lightboxHeaderPanel)

        lightboxZoomBar.cornerRadius = 0
        lightboxZoomBar.color = MMPalette.lightboxChrome
        lightboxOverlay.addSubview(lightboxZoomBar)

        lightboxContentPanel.cornerRadius = 0
        lightboxContentPanel.color = NSColor.black.withAlphaComponent(0.9)
        lightboxContentPanel.clipContentToBounds = true
        lightboxContentPanel.onClick = { [weak self] in
            self?.closeLightbox()
        }
        lightboxOverlay.addSubview(lightboxContentPanel)

        lightboxAvatarPanel.cornerRadius = 20
        lightboxAvatarPanel.color = Theme.shared.buttonBg
        lightboxAvatarPanel.clipContentToBounds = true
        lightboxAvatarView.imageScaling = .scaleProportionallyUpOrDown
        lightboxAvatarView.frame = NSRect(x: 0, y: 0, width: MMMetric.lightboxButton, height: MMMetric.lightboxButton)
        lightboxAvatarPanel.addSubview(lightboxAvatarView)
        lightboxHeaderPanel.addSubview(lightboxAvatarPanel)

        lightboxTitleLabel.font = MMFont.font(ofSize: 16, weight: .semibold)
        lightboxTitleLabel.textColor = .white
        lightboxTitleLabel.lineBreakMode = .byTruncatingMiddle
        lightboxTitleLabel.isEditable = false
        lightboxTitleLabel.isSelectable = false
        lightboxHeaderPanel.addSubview(lightboxTitleLabel)

        lightboxSubtitleLabel.font = MMFont.font(ofSize: 14)
        lightboxSubtitleLabel.textColor = NSColor.white.withAlphaComponent(0.75)
        lightboxSubtitleLabel.lineBreakMode = .byTruncatingTail
        lightboxSubtitleLabel.isEditable = false
        lightboxSubtitleLabel.isSelectable = false
        lightboxHeaderPanel.addSubview(lightboxSubtitleLabel)

        configureLightboxButton(
            lightboxDownloadButton,
            symbol: "arrow.down.to.line",
            description: "Download",
            action: { [weak self] in self?.downloadFromLightbox() }
        )
        configureLightboxButton(
            lightboxCloseButton,
            symbol: "xmark",
            description: "Close",
            action: { [weak self] in self?.closeLightbox() }
        )
        configureLightboxButton(
            lightboxZoomOutButton,
            symbol: "minus",
            description: "Zoom out",
            size: 28,
            action: { [weak self] in self?.adjustLightboxZoom(by: -0.25) }
        )
        configureLightboxButton(
            lightboxZoomFitButton,
            symbol: "minus.magnifyingglass",
            description: "Fit to window",
            size: 28,
            action: { [weak self] in self?.resetLightboxZoom() }
        )
        configureLightboxButton(
            lightboxZoomInButton,
            symbol: "plus",
            description: "Zoom in",
            size: 28,
            action: { [weak self] in self?.adjustLightboxZoom(by: 0.25) }
        )
        lightboxHeaderPanel.addSubview(lightboxDownloadButton)
        lightboxHeaderPanel.addSubview(lightboxCloseButton)
        lightboxZoomBar.addSubview(lightboxZoomOutButton)
        lightboxZoomBar.addSubview(lightboxZoomFitButton)
        lightboxZoomBar.addSubview(lightboxZoomInButton)

        lightboxImageView.imageScaling = .scaleProportionallyUpOrDown
        lightboxImageView.imageAlignment = .alignCenter
        lightboxImageView.animates = true
        lightboxImageView.wantsLayer = true
        lightboxImageView.layer?.cornerRadius = MMRadius.panel
        lightboxImageView.layer?.masksToBounds = true
        lightboxContentPanel.addSubview(lightboxImageView)
    }

    func configureLightboxButton(
        _ button: RoundedEdgePanel,
        symbol: String,
        description: String,
        size: CGFloat = 40,
        action: @escaping () -> Void
    ) {
        button.cornerRadius = MMRadius.control
        button.color = .clear
        let icon = NSImageView()
        if let image = NSImage(systemSymbolName: symbol, accessibilityDescription: description) {
            icon.image = image.withSymbolConfiguration(.init(pointSize: 16, weight: .medium))
            icon.contentTintColor = .white
        }
        let inset = (size - 16) / 2
        icon.frame = NSRect(x: inset, y: inset, width: 16, height: 16)
        button.addSubview(icon)
        button.onHoverChanged = { [weak button] isHovered in
            button?.color = NSColor.white.withAlphaComponent(isHovered ? 0.12 : 0.0)
            button?.setNeedsAppearanceUpdate()
        }
        button.onClick = action
    }

    func showLightbox(
        image: NSImage?,
        file: MMFileInfo? = nil,
        remoteURL: String? = nil,
        filename: String,
        authorId: String? = nil
    ) {
        guard let contentView = contentView else { return }

        lightboxFile = file
        lightboxRemoteURL = remoteURL
        lightboxScale = 1
        lightboxTitleLabel.stringValue = filename
        let resolvedAuthorId = authorId ?? file?.user_id
        let author = resolvedAuthorId.flatMap { usersById[$0]?.username }
            ?? currentUser?.username
            ?? UserDefaults.standard.string(forKey: "username")
            ?? ""
        let channel = channelsById[activeChannelId].map { channelDisplayName(for: $0) } ?? ""
        if !author.isEmpty && !channel.isEmpty {
            lightboxSubtitleLabel.stringValue = "\(author) Shared In ~\(channel)"
        } else if !channel.isEmpty {
            lightboxSubtitleLabel.stringValue = "Shared In ~\(channel)"
        } else {
            lightboxSubtitleLabel.stringValue = ""
        }

        if let avatar = resolvedAuthorId.flatMap({ userAvatarsById[$0] }) {
            lightboxAvatarView.image = avatar
        } else {
            lightboxAvatarView.image = nil
        }

        lightboxImageView.image = image
        lightboxNaturalSize = image.map { pixelSize(of: $0) } ?? .zero
        lightboxLoadToken = UUID()
        let token = lightboxLoadToken

        if let file = file, let ws = webService {
            Task { @MainActor [weak self] in
                guard let self = self, self.lightboxLoadToken == token,
                      let data = try? await ws.fetchFileData(fileId: file.id),
                      let full = NSImage(data: data) else { return }
                self.lightboxImageView.image = full
                self.lightboxNaturalSize = self.pixelSize(of: full)
                self.layoutLightboxImage()
            }
        } else if let remoteURL = remoteURL, let url = URL(string: remoteURL) {
            var request = URLRequest(url: url, cachePolicy: .returnCacheDataElseLoad, timeoutInterval: 20)
            request.setValue("Mozilla/5.0 (Macintosh; Intel Mac OS X 10_15_7) AppleWebKit/537.36", forHTTPHeaderField: "User-Agent")
            URLSession.shared.dataTask(with: request) { data, _, _ in
                guard let data = data else { return }
                Task { @MainActor in
                    guard self.lightboxLoadToken == token,
                          let full = NSImage(data: data) else { return }
                    self.lightboxImageView.image = full
                    self.lightboxNaturalSize = self.pixelSize(of: full)
                    self.layoutLightboxImage()
                }
            }.resume()
        }

        if lightboxOverlay.superview !== contentView {
            lightboxOverlay.removeFromSuperview()
            contentView.addSubview(lightboxOverlay)
        } else {
            contentView.addSubview(lightboxOverlay)
        }
        lightboxOverlay.isHidden = false
        isLightboxVisible = true
        layoutLightbox()

        if lightboxKeyMonitor == nil {
            lightboxKeyMonitor = NSEvent.addLocalMonitorForEvents(matching: .keyDown) { [weak self] event in
                guard let self = self, self.isLightboxVisible else { return event }
                if event.keyCode == 53 {
                    self.closeLightbox()
                    return nil
                }
                return event
            }
        }
    }

    func closeLightbox() {
        lightboxOverlay.isHidden = true
        lightboxOverlay.removeFromSuperview()
        isLightboxVisible = false
        lightboxLoadToken = UUID()
        if let monitor = lightboxKeyMonitor {
            NSEvent.removeMonitor(monitor)
            lightboxKeyMonitor = nil
        }
    }

    func adjustLightboxZoom(by delta: CGFloat) {
        lightboxScale = min(3, max(0.25, lightboxScale + delta))
        layoutLightboxImage()
    }

    func resetLightboxZoom() {
        lightboxScale = 1
        layoutLightboxImage()
    }

    func layoutLightbox() {
        guard let contentView = contentView, isLightboxVisible else { return }
        let bounds = contentView.bounds
        let width = bounds.width
        let height = bounds.height
        let headerH: CGFloat = 72
        let zoomH: CGFloat = 40

        lightboxOverlay.frame = bounds
        lightboxHeaderPanel.frame = NSRect(x: 0, y: height - headerH, width: width, height: headerH)
        lightboxZoomBar.frame = NSRect(x: 0, y: height - headerH - zoomH, width: width, height: zoomH)
        lightboxContentPanel.frame = NSRect(x: 0, y: 0, width: width, height: max(0, height - headerH - zoomH))

        lightboxAvatarPanel.frame = NSRect(x: 16, y: 16, width: MMMetric.lightboxButton, height: MMMetric.lightboxButton)
        lightboxAvatarView.frame = NSRect(x: 0, y: 0, width: MMMetric.lightboxButton, height: MMMetric.lightboxButton)
        lightboxTitleLabel.frame = NSRect(x: 68, y: headerH - 16 - 24, width: max(40, width - 68 - 120), height: 24)
        lightboxSubtitleLabel.frame = NSRect(x: 68, y: headerH - 40 - 20, width: max(40, width - 68 - 120), height: 20)
        lightboxCloseButton.frame = NSRect(x: width - 16 - MMMetric.lightboxButton, y: 18, width: MMMetric.lightboxButton, height: MMMetric.lightboxButton)
        lightboxDownloadButton.frame = NSRect(x: lightboxCloseButton.frame.minX - 8 - MMMetric.lightboxButton, y: 18, width: MMMetric.lightboxButton, height: MMMetric.lightboxButton)

        let zoomButtonSize: CGFloat = 28
        let zoomGap: CGFloat = 12
        let zoomTotal = zoomButtonSize * 3 + zoomGap * 2
        let zoomStartX = (width - zoomTotal) / 2
        let zoomY = (zoomH - zoomButtonSize) / 2
        lightboxZoomOutButton.frame = NSRect(x: zoomStartX, y: zoomY, width: zoomButtonSize, height: zoomButtonSize)
        lightboxZoomFitButton.frame = NSRect(x: zoomStartX + zoomButtonSize + zoomGap, y: zoomY, width: zoomButtonSize, height: zoomButtonSize)
        lightboxZoomInButton.frame = NSRect(x: zoomStartX + (zoomButtonSize + zoomGap) * 2, y: zoomY, width: zoomButtonSize, height: zoomButtonSize)

        layoutLightboxImage()
    }

    func layoutLightboxImage() {
        guard isLightboxVisible else { return }
        let stage = lightboxContentPanel.bounds
        let padding: CGFloat = 48
        let maxW = max(1, stage.width - padding * 2)
        let maxH = max(1, stage.height - padding * 2)
        guard lightboxNaturalSize.width > 0, lightboxNaturalSize.height > 0 else {
            lightboxImageView.frame = .zero
            return
        }
        let fitted = fitImageSize(natural: lightboxNaturalSize, maxWidth: maxW, maxHeight: maxH)
        let width = fitted.width * lightboxScale
        let height = fitted.height * lightboxScale
        lightboxImageView.frame = NSRect(
            x: (stage.width - width) / 2,
            y: (stage.height - height) / 2,
            width: width,
            height: height
        )
    }

    func downloadFromLightbox() {
        if let file = lightboxFile {
            downloadAttachment(file)
        } else if let remoteURL = lightboxRemoteURL, let url = URL(string: remoteURL) {
            let name = url.lastPathComponent.isEmpty ? "image" : url.lastPathComponent
            URLSession.shared.dataTask(with: url) { data, _, _ in
                guard let data = data else { return }
                Task { @MainActor in
                    self.saveFileData(data, suggestedName: name)
                }
            }.resume()
        }
    }

    func showReactionPicker(for post: MMPost, anchor: NSView) {
        showReactionPicker(for: post, anchorRect: frameInChat(anchor))
    }

    func showReactionPicker(for post: MMPost, anchorRect: NSRect) {
        guard !activeChannelId.isEmpty else { return }
        closePostActionMenu()
        reactionPickerPostId = post.id
        reactionPickerAnchorInChat = anchorRect

        let columns = 8
        let cell: CGFloat = 28
        let gap: CGFloat = 4
        let margin: CGFloat = 8
        let rows = (Self.quickReactions.count + columns - 1) / columns
        let width = margin * 2 + CGFloat(columns) * cell + CGFloat(columns - 1) * gap
        let height = margin * 2 + CGFloat(rows) * cell + CGFloat(rows - 1) * gap

        reactionPickerPanel.subviews.forEach { $0.removeFromSuperview() }

        for (index, emoji) in Self.quickReactions.enumerated() {
            let column = index % columns
            let row = index / columns
            let button = RoundedEdgePanel()
            button.cornerRadius = MMRadius.control
            button.color = .clear
            button.frame = NSRect(
                x: margin + CGFloat(column) * (cell + gap),
                y: margin + CGFloat(rows - 1 - row) * (cell + gap),
                width: cell,
                height: cell
            )
            let label = NSTextField(labelWithString: emoji.glyph)
            label.font = MMFont.font(ofSize: 18)
            label.alignment = .center
            label.isEditable = false
            label.isSelectable = false
            label.frame = NSRect(x: 0, y: 4, width: cell, height: 22)
            button.addSubview(label)
            button.onHoverChanged = { [weak button] isHovered in
                button?.color = isHovered
                    ? Theme.shared.centerText.withAlphaComponent(0.08)
                    : .clear
                button?.setNeedsAppearanceUpdate()
            }
            let emojiName = emoji.name
            button.onClick = { [weak self] in
                guard let self = self else { return }
                self.closeReactionPicker()
                self.toggleReaction(postId: self.reactionPickerPostId, emojiName: emojiName)
            }
            reactionPickerPanel.addSubview(button)
        }

        let chatW = chatPanel.bounds.width
        let chatH = chatPanel.bounds.height
        var x = anchorRect.midX - width / 2
        x = min(max(8, x), max(8, chatW - width - 8))
        var y = anchorRect.minY - height - 6
        if y < 8 {
            y = anchorRect.maxY + 6
        }
        y = min(max(8, y), max(8, chatH - height - 8))
        reactionPickerPanel.frame = NSRect(x: x, y: y, width: width, height: height)
        reactionPickerPanel.isHidden = false
        reactionPickerPanel.superview?.addSubview(reactionPickerPanel)
        isReactionPickerOpen = true
    }

    func closeReactionPicker() {
        reactionPickerPanel.isHidden = true
        isReactionPickerOpen = false
    }

    func showPostActionMenu(for post: MMPost, anchor: NSView) {
        showPostActionMenu(for: post, anchorRect: frameInChat(anchor))
    }

    func showPostActionMenu(for post: MMPost, anchorRect: NSRect) {
        closeReactionPicker()
        postActionMenuPost = post
        postActionMenuAnchorInChat = anchorRect

        let myId = currentUserId()
        let isMine = !post.user_id.isEmpty && post.user_id == myId
        let canEdit = isMine && (post.delete_at ?? 0) == 0
        var rows: [(symbol: String, title: String, action: () -> Void)] = [
            ("arrowshape.turn.up.left", "Reply", { [weak self] in
                self?.closePostActionMenu()
                self?.showThread(for: post)
            }),
            ("link", "Copy Link", { [weak self] in
                self?.closePostActionMenu()
                self?.copyPostLink(post)
            }),
            (self.savedPostIds.contains(post.id) ? "bookmark.slash" : "bookmark",
             self.savedPostIds.contains(post.id) ? "Unsave" : "Save", { [weak self] in
                self?.closePostActionMenu()
                self?.toggleSaved(post)
            })
        ]
        if canEdit {
            rows.append((post.is_pinned == true ? "pin.slash" : "pin", post.is_pinned == true ? "Unpin from Channel" : "Pin to Channel", { [weak self] in
                self?.closePostActionMenu()
                self?.togglePin(post)
            }))
            rows.append(("trash", "Delete", { [weak self] in
                self?.closePostActionMenu()
                self?.confirmDeletePost(post)
            }))
        }

        postActionMenu.subviews.forEach { $0.removeFromSuperview() }

        let rowHeight: CGFloat = 32
        let width: CGFloat = 210
        let height = CGFloat(rows.count) * rowHeight + 8
        let chatW = chatPanel.bounds.width
        let chatH = chatPanel.bounds.height
        var x = anchorRect.minX
        x = min(max(8, x), max(8, chatW - width - 8))
        var y = anchorRect.minY - height - 4
        if y < 8 {
            y = min(anchorRect.maxY + 4, chatH - height - 8)
        }
        postActionMenu.frame = NSRect(x: x, y: max(8, y), width: width, height: height)

        let textColor = Theme.shared.centerText
        let iconColor = Theme.shared.centerTextMuted
        for (index, item) in rows.enumerated() {
            let row = RoundedEdgePanel()
            row.cornerRadius = MMRadius.control
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
                    ? Theme.shared.centerHover
                    : .clear
                row?.setNeedsAppearanceUpdate()
            }
            row.onClick = item.action
            postActionMenu.addSubview(row)
        }

        postActionMenu.isHidden = false
        postActionMenu.superview?.addSubview(postActionMenu)
        isPostActionMenuOpen = true
    }

    func closePostActionMenu() {
        postActionMenu.isHidden = true
        isPostActionMenuOpen = false
    }

    func copyPostLink(_ post: MMPost) {
        let teamName = activeTeam?.name ?? ""
        let path = "/\(teamName)/pl/\(post.id)"
        let url: String
        if let built = webService?.buildURL(path: path) {
            url = built.absoluteString
        } else {
            var host = UserDefaults.standard.string(forKey: "host") ?? ""
            let port = UserDefaults.standard.integer(forKey: "port")
            if !host.contains("://") { host = "https://" + host }
            if port > 0 && !host.hasSuffix(":\(port)") { host += ":\(port)" }
            url = host + path
        }
        NSPasteboard.general.clearContents()
        NSPasteboard.general.setString(url, forType: .string)
        composerHelpLabel.stringValue = "Link copied"
        DispatchQueue.main.asyncAfter(deadline: .now() + 2) { [weak self] in
            guard let self = self, self.composerHelpLabel.stringValue == "Link copied" else { return }
            self.composerHelpLabel.stringValue = self.defaultComposerStatusText()
        }
    }

    func toggleSaved(_ post: MMPost) {
        guard let ws = webService, ws.isLogged() else { return }
        let userId = currentUser?.id ?? ws.currentUserId
        guard !userId.isEmpty else { return }
        let shouldSave = !savedPostIds.contains(post.id)
        if shouldSave {
            savedPostIds.insert(post.id)
        } else {
            savedPostIds.remove(post.id)
        }
        if isRightPanelVisible && rightPanelMode == .saved {
            loadSavedPosts()
        }
        Task { @MainActor [weak self] in
            do {
                if shouldSave {
                    try await ws.savePost(userId: userId, postId: post.id)
                } else {
                    try await ws.unsavePost(userId: userId, postId: post.id)
                }
            } catch {
                guard let self = self else { return }
                if shouldSave {
                    self.savedPostIds.remove(post.id)
                } else {
                    self.savedPostIds.insert(post.id)
                }
                self.showInfoAlert("Could not update the saved state: \(error.localizedDescription)")
            }
        }
    }

    func togglePin(_ post: MMPost) {
        guard let ws = webService, ws.isLogged() else { return }
        let shouldPin = post.is_pinned != true
        Task { @MainActor [weak self] in
            guard let self = self else { return }
            do {
                if shouldPin {
                    try await ws.pinPost(postId: post.id)
                } else {
                    try await ws.unpinPost(postId: post.id)
                }
                if let updated = try? await ws.fetchPost(postId: post.id) {
                    self.applyUpdatedPost(updated)
                }
            } catch {
                NSLog("Pin update failed: \(error.localizedDescription)")
            }
        }
    }

    func confirmDeletePost(_ post: MMPost) {
        guard let ws = webService, ws.isLogged() else { return }
        let alert = NSAlert()
        alert.messageText = "Delete this message?"
        alert.informativeText = "This will remove the message for everyone in the channel."
        alert.addButton(withTitle: "Delete")
        alert.addButton(withTitle: "Cancel")
        alert.beginSheetModal(for: self) { [weak self] response in
            guard let self = self, response == .alertFirstButtonReturn else { return }
            Task { @MainActor [weak self] in
                guard let self = self else { return }
                do {
                    try await ws.deletePost(postId: post.id)
                    self.currentChannelPosts.removeAll { $0.id == post.id }
                    self.threadPosts.removeAll { $0.id == post.id }
                    if self.isRightPanelVisible && self.rightPanelMode == .thread {
                        self.renderThreadPanel()
                    } else {
                        self.rebuildTimelineContent()
                    }
                } catch {
                    NSLog("Delete post failed: \(error.localizedDescription)")
                }
            }
        }
    }

    func emojiGlyph(for name: String) -> String {
        if let entry = EmojiCatalog.entriesByName[name.lowercased()] { return entry.glyph }
        if let glyph = Self.emojiGlyphs[name.lowercased()] { return glyph }
        // Already a unicode emoji?
        if name.unicodeScalars.contains(where: { $0.properties.isEmojiPresentation }) { return name }
        return ":" + name + ":"
    }

    func groupedReactions(_ post: MMPost) -> [(String, Int)] {
        let reactions = post.metadata?.reactions ?? []
        var counts: [String: Int] = [:]
        for reaction in reactions {
            guard let name = reaction.emoji_name, !name.isEmpty else { continue }
            counts[name, default: 0] += 1
        }
        return counts.sorted { $0.key < $1.key }.map { ($0.key, $0.value) }
    }

    func fileExtensionLabel(for file: MMFileInfo) -> String {
        if let ext = file.extension, !ext.isEmpty { return ext.uppercased() }
        let pathExt = ((file.name ?? "") as NSString).pathExtension
        if !pathExt.isEmpty { return pathExt.uppercased() }
        if let mime = file.mime_type, let subtype = mime.split(separator: "/").last, !subtype.isEmpty {
            return String(subtype).uppercased()
        }
        return "FILE"
    }

    func formatFileSize(_ bytes: Int64?) -> String {
        guard let bytes = bytes, bytes >= 0 else { return "" }
        if bytes < 1024 { return "\(bytes)B" }
        let kb = Double(bytes) / 1024
        if kb < 1024 { return String(format: kb < 10 ? "%.1fKB" : "%.0fKB", kb) }
        let mb = kb / 1024
        if mb < 1024 { return String(format: mb < 10 ? "%.1fMB" : "%.0fMB", mb) }
        return String(format: "%.1fGB", mb / 1024)
    }

    func createImageAttachmentView(_ file: MMFileInfo, maxWidth: CGFloat) -> (NSView, CGFloat) {
        let maxW = min(maxWidth, 700)
        let maxH: CGFloat = 350
        var natural = NSSize.zero
        if let width = file.width, let height = file.height, width > 0, height > 0 {
            natural = NSSize(width: CGFloat(width), height: CGFloat(height))
        }
        if let cached = attachmentSizeCache[file.id] {
            natural = cached
        }
        let placeholder = NSSize(width: min(400, maxW), height: min(240, maxH))
        let displaySize = fitImageSize(
            natural: natural == .zero ? placeholder : natural,
            maxWidth: maxW,
            maxHeight: maxH
        )

        let container = RoundedEdgePanel()
        container.cornerRadius = MMRadius.panel
        container.color = .clear
        container.borderWidth = 1
        container.borderColor = Theme.shared.centerText.withAlphaComponent(0.16)
        container.frame = NSRect(x: 0, y: 0, width: displaySize.width, height: displaySize.height)

        let imageView = NSImageView()
        imageView.imageScaling = .scaleProportionallyUpOrDown
        imageView.imageAlignment = .alignLeft
        imageView.frame = NSRect(x: 1, y: 1, width: displaySize.width - 2, height: displaySize.height - 2)
        imageView.wantsLayer = true
        imageView.layer?.cornerRadius = 7
        imageView.layer?.masksToBounds = true
        container.addSubview(imageView)

        // Download affordance shown on hover (`.image-preview-utility-buttons-container`).
        let download = RoundedEdgePanel()
        download.cornerRadius = MMRadius.control
        download.color = Theme.shared.centerBg
        download.borderWidth = 1
        download.borderColor = Theme.shared.centerText.withAlphaComponent(0.16)
        download.shadowColor = .black
        download.shadowOpacity = 0.08
        download.shadowRadius = 3
        download.shadowOffset = CGSize(width: 0, height: -2)
        download.frame = NSRect(x: displaySize.width - 8 - MMMetric.iconButtonSmall, y: displaySize.height - 8 - MMMetric.iconButtonSmall, width: MMMetric.iconButtonSmall, height: MMMetric.iconButtonSmall)
        download.isHidden = true
        let downloadIcon = NSImageView()
        if let image = NSImage(systemSymbolName: "arrow.down.to.line", accessibilityDescription: "Download") {
            downloadIcon.image = image.withSymbolConfiguration(.init(pointSize: 13, weight: .medium))
            downloadIcon.contentTintColor = Theme.shared.centerText.withAlphaComponent(0.75)
        }
        downloadIcon.frame = NSRect(x: 7, y: 7, width: 14, height: 14)
        download.addSubview(downloadIcon)
        download.onClick = { [weak self] in
            self?.downloadAttachment(file)
        }
        container.addSubview(download)

        container.onHoverChanged = { [weak container, weak download] isHovered in
            download?.isHidden = !isHovered
            container?.borderColor = isHovered
                ? Theme.shared.centerText.withAlphaComponent(0.3)
                : Theme.shared.centerText.withAlphaComponent(0.16)
            container?.setNeedsAppearanceUpdate()
        }
        container.onClick = { [weak self, weak imageView] in
            self?.showLightbox(image: imageView?.image, file: file, filename: file.name ?? "Image", authorId: file.user_id)
        }

        if let ws = webService {
            Task { @MainActor [weak self, weak container, weak imageView] in
                guard let data = try? await ws.fetchFileData(fileId: file.id, preview: true),
                      let image = NSImage(data: data) else { return }
                imageView?.image = image
                let pixels = self?.pixelSize(of: image) ?? image.size
                guard natural == .zero, pixels.width > 0, pixels.height > 0 else { return }
                self?.attachmentSizeCache[file.id] = pixels
                let fitted = self?.fitImageSize(natural: pixels, maxWidth: maxW, maxHeight: maxH)
                    ?? displaySize
                container?.frame.size = fitted
                imageView?.frame = NSRect(x: 1, y: 1, width: fitted.width - 2, height: fitted.height - 2)
                download.frame.origin = NSPoint(
                    x: fitted.width - 8 - 28,
                    y: fitted.height - 8 - 28
                )
                self?.scheduleImageRelayout()
            }
        }

        return (container, displaySize.height)
    }

    func createFileAttachmentCard(_ file: MMFileInfo, maxWidth: CGFloat) -> NSView {
        let cardW = min(320, maxWidth)
        let cardH: CGFloat = 64
        let card = FlippedEdgePanel()
        card.cornerRadius = MMRadius.control
        card.color = Theme.shared.centerBg
        card.borderWidth = 1
        card.borderColor = Theme.shared.centerText.withAlphaComponent(0.16)
        card.frame = NSRect(x: 0, y: 0, width: cardW, height: cardH)
        card.onHoverChanged = { [weak card] isHovered in
            card?.color = isHovered
                ? Theme.shared.centerHoverSubtle
                : Theme.shared.centerBg
            card?.setNeedsAppearanceUpdate()
        }
        card.onClick = { [weak self] in
            self?.openAttachment(file)
        }

        let icon = FileTypeIconView(frame: NSRect(x: 1, y: 1, width: 63, height: cardH - 2))
        icon.fileExtension = fileExtensionLabel(for: file)
        card.addSubview(icon)

        let detailsLeft: CGFloat = 64
        let nameWidth = min(151, max(60, cardW - detailsLeft - 40))
        let name = NSTextField(labelWithString: file.name ?? file.id)
        name.font = MMFont.font(ofSize: 12, weight: .semibold)
        name.textColor = Theme.shared.centerText
        name.lineBreakMode = .byTruncatingMiddle
        name.isEditable = false
        name.isSelectable = false
        name.frame = NSRect(x: detailsLeft, y: 13, width: nameWidth, height: 17)
        card.addSubview(name)

        let typeText = fileExtensionLabel(for: file)
        let typeLabel = NSTextField(labelWithString: typeText)
        typeLabel.font = MMFont.font(ofSize: 12)
        typeLabel.textColor = Theme.shared.centerText
        typeLabel.isEditable = false
        typeLabel.isSelectable = false
        typeLabel.frame = NSRect(x: detailsLeft, y: 33, width: 60, height: 17)
        card.addSubview(typeLabel)

        let typeWidth = ceil((typeText as NSString).size(withAttributes: [.font: MMFont.font(ofSize: 12)]).width)
        let sizeText = formatFileSize(file.size)
        let sizeLabel = NSTextField(labelWithString: sizeText)
        sizeLabel.font = MMFont.font(ofSize: 12)
        sizeLabel.textColor = Theme.shared.centerText
        sizeLabel.isEditable = false
        sizeLabel.isSelectable = false
        sizeLabel.frame = NSRect(x: detailsLeft + typeWidth + 4, y: 33, width: 70, height: 17)
        card.addSubview(sizeLabel)

        let downloadButton = RoundedEdgePanel()
        downloadButton.cornerRadius = MMRadius.control
        downloadButton.color = .clear
        downloadButton.frame = NSRect(x: cardW - 45, y: 16, width: MMMetric.iconButtonRegular, height: MMMetric.iconButtonRegular)
        let downloadIcon = NSImageView()
        if let image = NSImage(systemSymbolName: "arrow.down.to.line", accessibilityDescription: "Download") {
            downloadIcon.image = image.withSymbolConfiguration(.init(pointSize: 14, weight: .medium))
            downloadIcon.contentTintColor = Theme.shared.centerText.withAlphaComponent(0.64)
        }
        downloadIcon.frame = NSRect(x: 8, y: 8, width: 16, height: 16)
        downloadButton.addSubview(downloadIcon)
        downloadButton.onHoverChanged = { [weak downloadButton] isHovered in
            downloadButton?.color = isHovered
                ? Theme.shared.centerText.withAlphaComponent(0.08)
                : .clear
            downloadButton?.setNeedsAppearanceUpdate()
        }
        downloadButton.onClick = { [weak self] in
            self?.downloadAttachment(file)
        }
        card.addSubview(downloadButton)

        return card
    }

    func createAttachmentsView(_ files: [MMFileInfo], maxWidth: CGFloat) -> (NSView, CGFloat) {
        let container = TimelineFlippedView(frame: NSRect(x: 0, y: 0, width: maxWidth, height: 1))
        let images = files.filter { ($0.mime_type ?? "").hasPrefix("image/") }
        let others = files.filter { !($0.mime_type ?? "").hasPrefix("image/") }

        var y: CGFloat = 0
        for file in images {
            let (view, height) = createImageAttachmentView(file, maxWidth: maxWidth)
            view.frame.origin = NSPoint(x: 0, y: y)
            container.addSubview(view)
            y += height + 5
        }

        if !others.isEmpty {
            let cardW = min(320, maxWidth)
            var x: CGFloat = 0
            var rowHeight: CGFloat = 0
            for file in others {
                if x > 0 && x + cardW > maxWidth {
                    x = 0
                    y += rowHeight + 8
                    rowHeight = 0
                }
                let card = createFileAttachmentCard(file, maxWidth: maxWidth)
                card.frame.origin = NSPoint(x: x, y: y)
                container.addSubview(card)
                x += cardW + 12
                rowHeight = max(rowHeight, 64)
            }
            y += rowHeight
        }

        let height = max(y, 1)
        container.frame = NSRect(x: 0, y: 0, width: maxWidth, height: height)
        return (container, height)
    }

    /// Removes path separators, control characters and traversal components from a
    /// server-supplied filename before it is written to disk.
    func sanitizedAttachmentFilename(_ raw: String, fallback: String) -> String {
        let lastComponent = (raw as NSString).lastPathComponent
        let withoutControlCharacters = String(
            lastComponent.unicodeScalars.filter { !CharacterSet.controlCharacters.contains($0) }
                .map(Character.init)
        )
        let cleaned = withoutControlCharacters
            .replacingOccurrences(of: ":", with: "_")
            .trimmingCharacters(in: .whitespacesAndNewlines)
        guard !cleaned.isEmpty, cleaned != ".", cleaned != ".." else { return fallback }
        return String(cleaned.prefix(200))
    }

    func pruneAttachmentTempFiles() {
        let fm = FileManager.default
        let dir = fm.temporaryDirectory.appendingPathComponent("mattermost.client", isDirectory: true)
        guard let entries = try? fm.contentsOfDirectory(
            at: dir,
            includingPropertiesForKeys: [.contentModificationDateKey],
            options: [.skipsHiddenFiles]
        ) else { return }
        let cutoff = Date().addingTimeInterval(-24 * 60 * 60)
        for entry in entries {
            guard let values = try? entry.resourceValues(forKeys: [.contentModificationDateKey]),
                  let modified = values.contentModificationDate,
                  modified < cutoff else { continue }
            try? fm.removeItem(at: entry)
        }
    }

    func presentAttachmentError(_ message: String) {
        let alert = NSAlert()
        alert.alertStyle = .warning
        alert.messageText = "Could not save the file"
        alert.informativeText = message
        alert.addButton(withTitle: "OK")
        if isVisible {
            alert.beginSheetModal(for: self)
        } else {
            alert.runModal()
        }
    }

    func openAttachment(_ file: MMFileInfo) {
        guard let ws = webService else { return }
        Task { @MainActor [weak self] in
            guard let self = self else { return }
            do {
                let data = try await ws.fetchFileData(fileId: file.id)
                let name = self.sanitizedAttachmentFilename(file.name ?? file.id, fallback: file.id)
                // A per-file directory prevents same-named downloads from clobbering
                // each other while the original app is still viewing them.
                let dir = FileManager.default.temporaryDirectory
                    .appendingPathComponent("mattermost.client", isDirectory: true)
                    .appendingPathComponent(UUID().uuidString, isDirectory: true)
                try FileManager.default.createDirectory(at: dir, withIntermediateDirectories: true)
                let url = dir.appendingPathComponent(name)
                try data.write(to: url, options: .atomic)
                self.pruneAttachmentTempFiles()
                NSWorkspace.shared.open(url)
            } catch {
                self.presentAttachmentError(error.localizedDescription)
            }
        }
    }

    func downloadAttachment(_ file: MMFileInfo) {
        guard let ws = webService else { return }
        Task { @MainActor [weak self] in
            guard let self = self else { return }
            do {
                let data = try await ws.fetchFileData(fileId: file.id)
                self.saveFileData(data, suggestedName: file.name ?? file.id)
            } catch {
                self.presentAttachmentError(error.localizedDescription)
            }
        }
    }

    func saveFileData(_ data: Data, suggestedName: String) {
        let panel = NSSavePanel()
        panel.nameFieldStringValue = sanitizedAttachmentFilename(suggestedName, fallback: "attachment")
        panel.canCreateDirectories = true
        panel.beginSheetModal(for: self) { [weak self] response in
            guard response == .OK, let url = panel.url else { return }
            do {
                try data.write(to: url, options: .atomic)
            } catch {
                self?.presentAttachmentError(error.localizedDescription)
            }
        }
    }

    func createPendingOutgoingRow(_ pending: PendingOutgoingPost, width: CGFloat) -> (NSView, CGFloat) {
        let row = RoundedEdgePanel()
        row.identifier = NSUserInterfaceItemIdentifier("pendingRow_\(pending.id)")
        row.cornerRadius = 0
        row.color = .clear
        row.frame = NSRect(x: 0, y: 0, width: width, height: 58)

        let avatarCircle = RoundedEdgePanel()
        avatarCircle.cornerRadius = 16
        avatarCircle.clipContentToBounds = true
        avatarCircle.frame = NSRect(x: 37, y: 14, width: MMMetric.avatarInline, height: MMMetric.avatarInline)
        if let avatar = userAvatarsById[currentUser?.id ?? ""] {
            avatarCircle.color = .clear
            let imageView = NSImageView(frame: NSRect(origin: .zero, size: avatarCircle.frame.size))
            imageView.image = avatar
            imageView.imageScaling = .scaleProportionallyUpOrDown
            avatarCircle.addSubview(imageView)
        } else {
            let userId = currentUser?.id ?? "pending"
            avatarCircle.color = MMPalette.avatarColor(for: userId)
            let initial = (currentUser?.username.first).map { String($0).uppercased() } ?? "Y"
            let label = NSTextField(labelWithString: initial)
            label.font = MMFont.font(ofSize: 14, weight: .semibold)
            label.textColor = .white
            label.alignment = .center
            label.isEditable = false
            label.isSelectable = false
            label.frame = NSRect(x: 0, y: 7, width: 32, height: 18)
            avatarCircle.addSubview(label)
        }
        row.addSubview(avatarCircle)

        let name = NSTextField(labelWithString: currentUser?.username ?? "You")
        name.font = MMFont.font(ofSize: 14, weight: .bold)
        name.textColor = Theme.shared.centerText
        name.isEditable = false
        name.isSelectable = false
        name.frame = NSRect(x: 79, y: 30, width: max(80, width - 210), height: 18)
        row.addSubview(name)

        let statusText: String
        let statusColor: NSColor
        switch pending.status {
        case .sending:
            statusText = "Sending…"
            statusColor = Theme.shared.centerTextMuted
        case .failed:
            statusText = "Failed to send"
            statusColor = .systemRed
        }
        let status = NSTextField(labelWithString: statusText)
        status.font = MMFont.font(ofSize: 11, weight: .semibold)
        status.textColor = statusColor
        status.isEditable = false
        status.isSelectable = false
        status.frame = NSRect(x: 79, y: 8, width: 140, height: 16)
        row.addSubview(status)

        let body = NSTextField(labelWithString: pending.message)
        body.font = MMFont.font(ofSize: 14)
        body.textColor = Theme.shared.centerText.withAlphaComponent(0.75)
        body.lineBreakMode = .byTruncatingTail
        body.isEditable = false
        body.isSelectable = false
        body.frame = NSRect(x: 79, y: 14, width: max(80, width - 100), height: 18)
        row.addSubview(body)

        if case .failed = pending.status {
            let deleteButton = RoundedEdgePanel()
            deleteButton.cornerRadius = MMRadius.control
            deleteButton.color = .clear
            deleteButton.frame = NSRect(x: width - 64, y: 8, width: 56, height: 20)
            let deleteLabel = NSTextField(labelWithString: "Delete")
            deleteLabel.font = MMFont.font(ofSize: 11, weight: .semibold)
            deleteLabel.textColor = Theme.shared.centerTextMuted
            deleteLabel.alignment = .center
            deleteLabel.isEditable = false
            deleteLabel.isSelectable = false
            deleteLabel.frame = NSRect(x: 0, y: 2, width: 56, height: 16)
            deleteButton.addSubview(deleteLabel)
            deleteButton.onClick = { [weak self] in
                self?.deletePendingPost(id: pending.id)
            }
            row.addSubview(deleteButton)

            let retryButton = RoundedEdgePanel()
            retryButton.cornerRadius = MMRadius.control
            retryButton.color = .clear
            retryButton.frame = NSRect(x: width - 118, y: 8, width: 48, height: 20)
            let retryLabel = NSTextField(labelWithString: "Retry")
            retryLabel.font = MMFont.font(ofSize: 11, weight: .semibold)
            retryLabel.textColor = Theme.shared.buttonBg
            retryLabel.alignment = .center
            retryLabel.isEditable = false
            retryLabel.isSelectable = false
            retryLabel.frame = NSRect(x: 0, y: 2, width: 48, height: 16)
            retryButton.addSubview(retryLabel)
            retryButton.onClick = { [weak self] in
                self?.retryPendingPost(id: pending.id)
            }
            row.addSubview(retryButton)
        }

        return (row, 58)
    }

    @discardableResult
    func appendRenderedPostRow(_ post: MMPost, wasNearBottom: Bool) -> Bool {
        guard pendingOutgoingPosts.allSatisfy({ $0.channelId != activeChannelId }) else { return false }
        guard currentChannelPosts.last?.id == post.id,
              let previousPost = currentChannelPosts.dropLast().last else { return false }
        let chatW = isRightPanelVisible ? rightPanel.frame.minX : chatPanel.bounds.width
        let chatH = chatPanel.bounds.height
        let composerTop = 24 + composerTotalHeight
        let scrollH = max(0, chatH - 56 - (connectionBanner.isHidden ? 0 : 26) - composerTop)
        let previousHeight = timelineDocView.frame.height
        var insertionY = max(16, previousHeight - 16)
        let postDate = Date(timeIntervalSince1970: TimeInterval(post.create_at) / 1000.0)
        let previousDate = Date(timeIntervalSince1970: TimeInterval(previousPost.create_at) / 1000.0)
        let calendar = Calendar.current

        if calendar.startOfDay(for: postDate) != calendar.startOfDay(for: previousDate) {
            let separator = createDateSeparator(
                dateStr: TimelineDateSeparator.string(for: postDate),
                width: chatW
            )
            separator.frame.origin.y = insertionY
            timelineDocView.addSubview(separator)
            insertionY += 34
        }

        if !wasNearBottom, newMessagesDividerPostId == post.id {
            let divider = createNewMessagesDivider(width: chatW)
            divider.frame.origin.y = insertionY
            timelineDocView.addSubview(divider)
            newMessagesDividerView = divider
            insertionY += 40
        }

        let isSystem = (post.type?.hasPrefix("system_") ?? false)
            || (usersById[post.user_id]?.username == "System")
        let previousWasSystem = (previousPost.type?.hasPrefix("system_") ?? false)
            || (usersById[previousPost.user_id]?.username == "System")
        let withinGroupingWindow = (post.create_at - previousPost.create_at) <= 5 * 60 * 1000
        let isConsecutive = !isSystem && !previousWasSystem
            && post.user_id == previousPost.user_id
            && !post.user_id.isEmpty && withinGroupingWindow
        let (row, rowHeight) = createPostRow(
            post: post,
            width: chatW,
            timeStr: Self.localizedTimeFormatter.string(from: postDate),
            isConsecutive: isConsecutive
        )
        row.frame.origin = NSPoint(x: 0, y: insertionY)
        timelineDocView.addSubview(row)
        let newHeight = max(scrollH, insertionY + rowHeight + (isConsecutive ? 2 : 4) + 16)
        timelineDocView.frame = NSRect(
            x: 0,
            y: 0,
            width: chatW,
            height: max(previousHeight, newHeight)
        )

        updateTimelineHoverState()
        updateNewMessagesDividerState()
        if wasNearBottom {
            scrollTimelineToBottom()
        }
        return true
    }

    func updateTimelineAvatar(userId: String, image: NSImage) {
        guard !userId.isEmpty else { return }
        let identifier = "avatar_\(userId)"
        func update(_ view: NSView) {
            if view.identifier?.rawValue == identifier,
               let panel = view as? RoundedEdgePanel {
                panel.color = .clear
                panel.subviews.forEach { $0.removeFromSuperview() }
                let imageView = NSImageView(frame: NSRect(origin: .zero, size: panel.frame.size))
                imageView.image = image
                imageView.imageScaling = .scaleProportionallyUpOrDown
                panel.addSubview(imageView)
                panel.setNeedsAppearanceUpdate()
                return
            }
            view.subviews.forEach(update)
        }
        update(timelineDocView)
    }

    func createPostRow(post: MMPost, width: CGFloat, timeStr: String, isConsecutive: Bool = false) -> (NSView, CGFloat) {
        let row = TimelineRowView()
        row.identifier = NSUserInterfaceItemIdentifier("postRow_\(post.id)")
        row.cornerRadius = 0
        row.color = .clear

        let darkText = Theme.shared.centerText
        let mutedText = Theme.shared.centerTextMuted
        let lightPlaceholder = Theme.shared.centerTextPlaceholder
        let hoverBg = Theme.shared.centerHover
        let msgHoverBg = Theme.shared.centerHoverSubtle
        let dividerColor = Theme.shared.divider

        let isSystem = (post.type?.hasPrefix("system_") ?? false) || (usersById[post.user_id]?.username == "System")

        // Parse message for text & Giphy GIF URLs
        let rawMessage = post.message.isEmpty ? (isSystem ? "System update" : "") : post.message
        let parsed = parseGiphyInMessage(rawMessage)
        let isDeleted = (post.delete_at ?? 0) > 0
        let bodyText = isDeleted ? "This message was deleted." : parsed.text
        let gifURLs = isDeleted ? [] : parsed.gifURLs
        let hasBodyText = !bodyText.isEmpty
        let isEdited = !isDeleted && (post.edit_at != nil && post.edit_at! > 0)
        let editDate = isEdited ? Date(timeIntervalSince1970: TimeInterval(post.edit_at!) / 1000.0) : nil

        let bodyFont = MMFont.font(ofSize: 14)
        let bodyMaxW = max(100, width - 79 - 8)

        let formattedBody: NSAttributedString
        if hasBodyText {
            let bodyColor = isDeleted
                ? Theme.shared.centerTextMuted.withAlphaComponent(0.9)
                : Theme.shared.centerText.withAlphaComponent(0.75)
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
                    .foregroundColor: Theme.shared.buttonBg,
                    .underlineStyle: NSUnderlineStyle.single.rawValue,
                    .cursor: NSCursor.pointingHand
                ]
                bodyView.textStorage?.setAttributedString(formattedBody)
                row.addSubview(bodyView)
                contentY += bodyH + 6
            }

            for gifURL in gifURLs {
                let (giphyView, gifH) = createInlineImageView(urlString: gifURL, maxWidth: bodyMaxW, authorId: post.user_id)
                giphyView.frame.origin = CGPoint(x: 79, y: contentY)
                row.addSubview(giphyView)
                contentY += gifH + 6
            }

            if !isDeleted {
                let files = post.metadata?.files ?? []
                if !files.isEmpty {
                    let (attachmentView, fileH) = createAttachmentsView(files, maxWidth: bodyMaxW)
                    attachmentView.frame.origin = CGPoint(x: 79, y: contentY)
                    row.addSubview(attachmentView)
                    contentY += fileH + 2
                }
            }
            contentY += addReactionChips(for: post, to: row, x: 79, y: contentY)

            let totalRowH = max(24, contentY)
            row.frame = NSRect(x: 0, y: 0, width: width, height: totalRowH)

            let toolbar = (isSystem || isDeleted)
                ? nil
                : addHoverToolbar(for: post, to: row, width: width, compact: true)

            row.onHoverChanged = { [weak row, weak hoverTimeLabel, weak toolbar] isHovered in
                row?.color = isHovered ? msgHoverBg : .clear
                row?.setNeedsAppearanceUpdate()
                hoverTimeLabel?.isHidden = !isHovered
                toolbar?.isHidden = !isHovered
                row?.reactionAddChip?.isHidden = !isHovered
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
                         (userObj?.roles?.lowercased().contains("bot") ?? false) ||
                         (userObj?.is_bot ?? false))

        // Post header/body metrics mirror the web client:
        // 16pt top padding, 32pt avatar at 37pt, text column at 79pt, 14pt bottom padding.
        let topPad: CGFloat = 16
        let bottomPad: CGFloat = 14
        let headerH: CGFloat = 20
        let avatarSize: CGFloat = 32
        let contentX: CGFloat = 79

        // Inline images and file attachments are created first so the row height is known.
        var gifViews: [(NSView, CGFloat)] = []
        for gifURL in gifURLs {
            let (giphyView, gifH) = createInlineImageView(urlString: gifURL, maxWidth: bodyMaxW, authorId: post.user_id)
            gifViews.append((giphyView, gifH))
        }

        var attachmentsView: NSView?
        var attachmentsHeight: CGFloat = 0
        if !isDeleted {
            let files = post.metadata?.files ?? []
            if !files.isEmpty {
                let created = createAttachmentsView(files, maxWidth: bodyMaxW)
                attachmentsView = created.0
                attachmentsHeight = created.1
            }
        }
        let reactionGroups = groupedReactions(post)
        let reactionsHeight: CGFloat = reactionGroups.isEmpty ? 0 : 34

        var stackHeight: CGFloat = 0
        if hasDisplayableText { stackHeight += bodyH + 3 }
        for (_, gifH) in gifViews { stackHeight += gifH + 6 }
        if attachmentsView != nil { stackHeight += attachmentsHeight + 2 }
        stackHeight += reactionsHeight

        let totalRowH = topPad + headerH + stackHeight + bottomPad
        row.frame = NSRect(x: 0, y: 0, width: width, height: totalRowH)
        // Rows use a flipped (top-down) coordinate system.
        let headerTopY = topPad

        // Avatar circle
        let avatarCircle = RoundedEdgePanel()
        avatarCircle.identifier = NSUserInterfaceItemIdentifier("avatar_\(post.user_id)")
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
            avatarCircle.color = MMPalette.avatarColor(for: post.user_id.isEmpty ? authorName : post.user_id)

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
            statusPromptPill.cornerRadius = MMRadius.control
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
        timeLabel.textColor = Theme.shared.centerText.withAlphaComponent(0.75)
        timeLabel.isEditable = false
        timeLabel.isSelectable = false
        let timeSize = (timeStr as NSString).size(withAttributes: [.font: timeFont])
        let timeW = ceil(timeSize.width) + 4
        let timeH = max(17, ceil(timeSize.height))
        timeLabel.frame = NSRect(x: headerRightX, y: headerTopY + (headerH - timeH) / 2, width: timeW, height: timeH)
        row.addSubview(timeLabel)

        if post.is_pinned == true {
            let pinView = NSImageView()
            if let pinImage = NSImage(systemSymbolName: "pin.fill", accessibilityDescription: "Pinned") {
                pinView.image = pinImage.withSymbolConfiguration(.init(pointSize: 10, weight: .semibold))
                pinView.contentTintColor = Theme.shared.awayIndicator
            }
            pinView.frame = NSRect(x: timeLabel.frame.maxX + 6, y: headerTopY + 5, width: 13, height: 13)
            row.addSubview(pinView)
        }

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
                .foregroundColor: Theme.shared.linkColor,
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

        if let attachmentsView = attachmentsView {
            attachmentsView.frame.origin = CGPoint(x: contentX, y: stackTop)
            row.addSubview(attachmentsView)
            stackTop += attachmentsHeight + 2
        }

        if !reactionGroups.isEmpty {
            _ = addReactionChips(for: post, to: row, x: contentX, y: stackTop)
            stackTop += reactionsHeight
        }

        if !isSystem && !isBotUser {
            let usrDot = RoundedEdgePanel()
            if isCurrentUser {
                usrDot.identifier = NSUserInterfaceItemIdentifier("statusDot_currentUser")
            } else {
                usrDot.identifier = NSUserInterfaceItemIdentifier("statusDot_\(post.user_id)")
            }
            let dotSize: CGFloat = 12
            let stat = isCurrentUser ? currentUserStatus : (userStatusById[post.user_id] ?? "offline")
            usrDot.frame = NSRect(x: 57, y: topPad + avatarSize - dotSize, width: dotSize, height: dotSize)
            usrDot.cornerRadius = dotSize / 2
            usrDot.color = statusColor(for: stat)
            usrDot.borderWidth = 1.5
            usrDot.borderColor = Theme.shared.centerBg
            row.addSubview(usrDot)
            updateStatusCheck(in: usrDot, status: stat)
        }

        let toolbar = (isSystem || isDeleted)
            ? nil
            : addHoverToolbar(for: post, to: row, width: width)
        row.onHoverChanged = { [weak row, weak toolbar] isHovered in
            row?.color = isHovered ? msgHoverBg : .clear
            row?.setNeedsAppearanceUpdate()
            toolbar?.isHidden = !isHovered
            row?.reactionAddChip?.isHidden = !isHovered
        }
        return (row, totalRowH)
    }

    func textView(_ textView: NSTextView, clickedOnLink link: Any, at charIndex: Int) -> Bool {
        if let url = link as? URL, url.scheme == "mattermost-channel" {
            let name = (url.host ?? "").lowercased()
            if let channel = channelsByName[name] ?? channelsByName[name.replacingOccurrences(of: "-", with: " ")] {
                openChannel(withId: channel.id)
                return true
            }
            return true
        }
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

    func preprocessMarkdownLine(_ line: String) -> String {
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

    func preprocessMarkdown(_ message: String) -> String {
        let lines = message.components(separatedBy: "\n")
        return lines.map { preprocessMarkdownLine($0) }.joined(separator: "\n")
    }

    func formattedMessage(_ message: String, font: NSFont, color: NSColor) -> NSAttributedString {
        let result = NSMutableAttributedString()
        var codeRanges: [NSRange] = []
        let paragraphStyle = NSMutableParagraphStyle()
        paragraphStyle.lineBreakMode = .byWordWrapping
        let codeColor = Theme.shared.centerText.withAlphaComponent(0.08)

        // Render fenced code blocks verbatim; everything else goes through the
        // inline Markdown pipeline.
        for segment in splitCodeBlocks(message) {
            if segment.isCode {
                let start = result.length
                let attrs: [NSAttributedString.Key: Any] = [
                    .font: NSFont.monospacedSystemFont(ofSize: max(11, font.pointSize - 0.5), weight: .regular),
                    .foregroundColor: color,
                    .backgroundColor: codeColor,
                    .paragraphStyle: paragraphStyle
                ]
                result.append(NSAttributedString(string: segment.text, attributes: attrs))
                codeRanges.append(NSRange(location: start, length: result.length - start))
            } else {
                result.append(inlineMarkdown(segment.text, font: font, color: color))
            }
        }

        applyInlineEnhancements(to: result, codeRanges: codeRanges, font: font)
        return result
    }

    func splitCodeBlocks(_ message: String) -> [(text: String, isCode: Bool)] {
        var segments: [(String, Bool)] = []
        var buffer = ""
        var inCode = false
        for line in message.components(separatedBy: "\n") {
            if line.trimmingCharacters(in: .whitespaces).hasPrefix("```") {
                if inCode {
                    segments.append((buffer, true))
                    buffer = ""
                    inCode = false
                } else {
                    if !buffer.isEmpty { segments.append((buffer, false)) }
                    buffer = ""
                    inCode = true
                }
                continue
            }
            buffer += line + "\n"
        }
        if !buffer.isEmpty {
            let trimmed = buffer.trimmingCharacters(in: .newlines)
            if !trimmed.isEmpty { segments.append((trimmed, inCode)) }
        }
        return segments
    }

    func inlineMarkdown(_ message: String, font: NSFont, color: NSColor) -> NSAttributedString {
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

        let brandBlue = Theme.shared.buttonBg
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

            if isCode {
                attrs[.backgroundColor] = Theme.shared.centerText.withAlphaComponent(0.08)
            }

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

    func applyInlineEnhancements(to result: NSMutableAttributedString, codeRanges: [NSRange], font: NSFont) {
        let brandBlue = Theme.shared.buttonBg
        let mentionBg = Theme.shared.buttonBg.withAlphaComponent(0.10)
        let string = result.string as NSString
        let fullRange = NSRange(location: 0, length: string.length)

        func isCode(_ range: NSRange) -> Bool {
            codeRanges.contains { NSIntersectionRange($0, range).length > 0 }
        }

        // @mentions
        if let regex = try? NSRegularExpression(pattern: #"(?<![\w@])@([A-Za-z0-9._-]+)"#) {
            for match in regex.matches(in: result.string, options: [], range: fullRange) where !isCode(match.range) {
                result.addAttributes([
                    .foregroundColor: brandBlue,
                    .backgroundColor: mentionBg
                ], range: match.range)
            }
        }

        // ~channel and #channel links
        if let regex = try? NSRegularExpression(pattern: #"(?<![\w])[~#]([A-Za-z0-9][A-Za-z0-9_-]+)"#) {
            for match in regex.matches(in: result.string, options: [], range: fullRange) where !isCode(match.range) {
                let name = string.substring(with: match.range(at: 1)).lowercased()
                guard channelsByName[name] != nil || channelsByName[name.replacingOccurrences(of: "-", with: " ")] != nil else { continue }
                result.addAttributes([
                    .foregroundColor: brandBlue,
                    .link: URL(string: "mattermost-channel://\(name)") as Any,
                    .underlineStyle: NSUnderlineStyle.single.rawValue
                ], range: match.range)
            }
        }

        // :emoji: shortcodes (replacement changes lengths, so run last and backwards)
        if let regex = try? NSRegularExpression(pattern: #":[a-zA-Z0-9_+\-]+:"#) {
            let matches = regex.matches(in: result.string, options: [], range: fullRange)
            for match in matches.reversed() where !isCode(match.range) {
                let token = (result.string as NSString).substring(with: match.range)
                let name = String(token.dropFirst().dropLast())
                if let entry = customEmojiEntries.first(where: { $0.name.lowercased() == name.lowercased() }),
                   let id = entry.emojiId,
                   let image = customEmojiImages[id] {
                    let attachment = NSTextAttachment()
                    attachment.image = image
                    attachment.bounds = NSRect(x: 0, y: -3, width: 18, height: 18)
                    result.replaceCharacters(in: match.range, with: NSAttributedString(attachment: attachment))
                    continue
                }
                let glyph = emojiGlyph(for: name)
                guard glyph != ":" + name + ":" else { continue }
                result.replaceCharacters(in: match.range, with: glyph)
            }
        }
    }

    func resolveFont(from base: NSFont, isBold: Bool, isItalic: Bool, isCode: Bool) -> NSFont {
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

    func createBotBadge() -> RoundedEdgePanel {
        let badge = RoundedEdgePanel()
        badge.cornerRadius = MMRadius.control
        badge.color = Theme.shared.centerText.withAlphaComponent(0.12)
        let label = NSTextField(labelWithString: "BOT")
        label.font = MMFont.font(ofSize: 9.5, weight: .bold)
        label.textColor = Theme.shared.centerText.withAlphaComponent(0.75)
        label.alignment = .center
        label.isEditable = false
        label.isSelectable = false
        label.frame = NSRect(x: 0, y: 1, width: 32, height: 14)
        badge.addSubview(label)
        return badge
    }

    func rebuildTimelineContent(scrollToBottom: Bool = false) {
        let fullChatW = chatPanel.bounds.width
        let chatW = isRightPanelVisible ? rightPanel.frame.minX : fullChatW
        let chatH = chatPanel.bounds.height
        // Keep in sync with layoutRightChatPanel(): 56pt header, 50/90pt composer.
        let headerH: CGFloat = 56
        let headerY = chatH - headerH
        let composerH: CGFloat = composerTotalHeight
        let composerTop = 24 + composerH
        let scrollH = max(0, headerY - (connectionBanner.isHidden ? 0 : 26) - composerTop)
        timelineScrollView.frame = NSRect(x: 0, y: composerTop, width: chatW, height: scrollH)

        timelineDocView.subviews.forEach { $0.removeFromSuperview() }
        newMessagesDividerView = nil

        var currentY: CGFloat = 16

        // 1. Welcome Hero — only for an empty channel, not above every feed.
        let heroW: CGFloat = min(chatW - 40, 480)
        let heroH: CGFloat = 216
        let showHero = currentChannelPosts.isEmpty && !CommandLine.arguments.contains("--demo")
        if showHero {
            timelineHeroContainer.frame = NSRect(x: (chatW - heroW) / 2, y: currentY, width: heroW, height: heroH)
            timelineHeroContainer.isHidden = false
            layoutHeroSubviews(heroW: heroW)
            timelineDocView.addSubview(timelineHeroContainer)
            currentY += heroH + 16
        } else {
            timelineHeroContainer.isHidden = true
            timelineHeroContainer.removeFromSuperview()
        }

        // 2. Posts and Date Separators (localized)

        var postsToRender = currentChannelPosts.filter { ($0.root_id ?? "").isEmpty }
        if postsToRender.isEmpty && !(webService?.isLogged() ?? false) && CommandLine.arguments.contains("--demo") {
            let nowMs = Int64(Date().timeIntervalSince1970 * 1000)
            if userStatusById["sarah"] == nil {
                userStatusById["sarah"] = "away"
            }
            if usersById["sarah"] == nil {
                usersById["sarah"] = MMUser(
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

        if !didLoadAllHistory && !postsToRender.isEmpty {
            let loadRow = RoundedEdgePanel()
            loadRow.cornerRadius = MMRadius.control
            loadRow.color = .clear
            loadRow.frame = NSRect(x: 0, y: currentY, width: chatW, height: 32)
            let loadLabel = NSTextField(labelWithString: isLoadingOlderPosts ? "Loading older messages…" : "Load older messages")
            loadLabel.font = MMFont.font(ofSize: 12, weight: .semibold)
            loadLabel.textColor = Theme.shared.centerTextMuted
            loadLabel.alignment = .center
            loadLabel.isEditable = false
            loadLabel.isSelectable = false
            loadLabel.frame = NSRect(x: 0, y: 7, width: chatW, height: 18)
            loadRow.addSubview(loadLabel)
            loadRow.onHoverChanged = { [weak loadRow] isHovered in
                loadRow?.color = isHovered
                    ? Theme.shared.centerHover
                    : .clear
                loadRow?.setNeedsAppearanceUpdate()
            }
            loadRow.onClick = { [weak self] in
                self?.loadOlderPosts()
            }
            timelineDocView.addSubview(loadRow)
            currentY += 40
        }

        var lastDateKey: Date? = nil
        var lastUserId: String? = nil
        var lastWasSystem = false
        var lastPostTimestamp: Int64 = 0
        for post in postsToRender {
            let postDate = Date(timeIntervalSince1970: TimeInterval(post.create_at) / 1000.0)
            let dateStr = TimelineDateSeparator.string(for: postDate)
            let dateKey = Calendar.current.startOfDay(for: postDate)
            let isSystem = (post.type?.hasPrefix("system_") ?? false) || (usersById[post.user_id]?.username == "System")
            if lastDateKey != dateKey {
                lastDateKey = dateKey
                lastUserId = nil
                lastWasSystem = false
                let sepView = createDateSeparator(dateStr: dateStr, width: chatW)
                sepView.frame.origin.y = currentY
                timelineDocView.addSubview(sepView)
                currentY += 24 + 10
            }

            if post.id == newMessagesDividerPostId {
                let dividerView = createNewMessagesDivider(width: chatW)
                dividerView.frame.origin.y = currentY
                timelineDocView.addSubview(dividerView)
                newMessagesDividerView = dividerView
                currentY += 40
            }

            // Group with the previous post only when it is the same author and
            // within five minutes (matching the web client).
            let withinGroupingWindow = (post.create_at - lastPostTimestamp) <= 5 * 60 * 1000
            let isConsecutive = (!isSystem && !lastWasSystem && post.user_id == lastUserId
                && !post.user_id.isEmpty && withinGroupingWindow)
            let (rowView, rowH) = createPostRow(post: post, width: chatW, timeStr: Self.localizedTimeFormatter.string(from: postDate), isConsecutive: isConsecutive)
            rowView.frame.origin.y = currentY
            timelineDocView.addSubview(rowView)
            currentY += rowH + (isConsecutive ? 2 : 4)

            lastUserId = post.user_id
            lastWasSystem = isSystem
            lastPostTimestamp = post.create_at
        }

        for pending in pendingOutgoingPosts where pending.channelId == activeChannelId {
            let (pendingRow, pendingHeight) = createPendingOutgoingRow(pending, width: chatW)
            pendingRow.frame.origin.y = currentY
            timelineDocView.addSubview(pendingRow)
            currentY += pendingHeight + 4
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
                self.updateTimelineHoverState()
                self.updateNewMessagesDividerState()
            }
        } else {
            // Rebuilds replace the row views, so restore the hover state under the
            // pointer (toolbar visibility) once the new layout is in place.
            DispatchQueue.main.async { [weak self] in
                self?.updateTimelineHoverState()
                self?.updateNewMessagesDividerState()
            }
        }
    }

    func scrollTimelineToBottom() {
        let maxY = max(0, timelineDocView.frame.height - timelineScrollView.contentView.bounds.height)
        timelineScrollView.contentView.scroll(to: NSPoint(x: 0, y: maxY))
        timelineScrollView.reflectScrolledClipView(timelineScrollView.contentView)
        updateNewMessagesDividerState()
    }

    func saveChannelScrollPosition(for channelId: String) {
        guard !channelId.isEmpty else { return }
        let top = timelineScrollView.contentView.bounds.minY
        let row = timelineDocView.subviews.compactMap { view -> (id: String, y: CGFloat)? in
            guard let identifier = view.identifier?.rawValue,
                  identifier.hasPrefix("postRow_") else { return nil }
            return (String(identifier.dropFirst("postRow_".count)), view.frame.minY)
        }.last(where: { $0.y <= top + 8 }) ?? timelineDocView.subviews.compactMap { view -> (id: String, y: CGFloat)? in
            guard let identifier = view.identifier?.rawValue,
                  identifier.hasPrefix("postRow_") else { return nil }
            return (String(identifier.dropFirst("postRow_".count)), view.frame.minY)
        }.min(by: { $0.y < $1.y })
        guard let row = row else { return }
        channelScrollPositions[channelId] = ChannelScrollPosition(postId: row.id, offset: top - row.y)
    }

    @discardableResult
    func restoreChannelScrollPosition(for channelId: String) -> Bool {
        guard let saved = channelScrollPositions[channelId],
              let row = timelineDocView.subviews.first(where: {
                  $0.identifier?.rawValue == "postRow_\(saved.postId)"
              }) else { return false }
        let clip = timelineScrollView.contentView
        let maxY = max(0, timelineDocView.frame.height - clip.bounds.height)
        let target = min(maxY, max(0, row.frame.minY + saved.offset))
        clip.scroll(to: NSPoint(x: 0, y: target))
        timelineScrollView.reflectScrolledClipView(clip)
        updateTimelineHoverState()
        updateNewMessagesDividerState()
        return true
    }
}
