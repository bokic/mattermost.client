//
//  MainWindow+LinkPreviews.swift
//  mattermost.client
//
//  Opt-in Open Graph link previews for timeline messages.
//

import AppKit
import Foundation

extension MainWindow {

    func ensureLinkPreview(for url: URL) {
        guard linkPreviewsEnabled else { return }
        let key = url.absoluteString
        guard linkPreviewsByURL[key] == nil,
            !linkPreviewLoading.contains(key),
            !linkPreviewFailures.contains(key)
        else { return }

        linkPreviewLoading.insert(key)
        Task { @MainActor [weak self] in
            guard let self = self else { return }
            var preview: LinkPreviewMetadata?
            if let metadata = await self.webService?.fetchLinkMetadata(url: url) {
                let title = metadata.title?.trimmingCharacters(in: .whitespacesAndNewlines) ?? ""
                let description = metadata.description?.trimmingCharacters(in: .whitespacesAndNewlines) ?? ""
                if !title.isEmpty || !description.isEmpty {
                    preview = LinkPreviewMetadata(
                        url: url,
                        title: title,
                        description: description,
                        imageURL: metadata.image_url.flatMap(URL.init(string:)),
                        siteName: metadata.site_name ?? url.host ?? ""
                    )
                }
            }
            if preview == nil {
                preview = await LinkPreviewService.fetch(url: url)
            }

            self.linkPreviewLoading.remove(key)
            guard let preview = preview else {
                self.linkPreviewFailures.insert(key)
                return
            }
            if self.linkPreviewsByURL.count > 100 {
                self.linkPreviewsByURL.removeAll(keepingCapacity: true)
            }
            self.linkPreviewsByURL[key] = preview
            self.rebuildTimelineContent(scrollToBottom: false)
            if self.isRightPanelVisible && self.rightPanelMode == .thread {
                self.renderThreadPanel(scrollToBottom: false)
            }
        }
    }

    func linkPreviewCardHeight(for preview: LinkPreviewMetadata) -> CGFloat {
        (loadRemoteImagesAutomatically && preview.imageURL != nil) ? 104 : 78
    }

    func createLinkPreviewCard(for preview: LinkPreviewMetadata, maxWidth: CGFloat) -> NSView {
        let hasImage = loadRemoteImagesAutomatically && preview.imageURL != nil
        let card = RoundedEdgePanel()
        card.identifier = NSUserInterfaceItemIdentifier("linkPreview_\(preview.url.absoluteString)")
        card.cornerRadius = MMRadius.control
        card.color = Theme.shared.centerHoverSubtle
        card.borderWidth = 1
        card.borderColor = Theme.shared.divider
        card.frame = NSRect(x: 0, y: 0, width: maxWidth, height: linkPreviewCardHeight(for: preview))

        let textWidth = max(100, maxWidth - (hasImage ? 100 : 16))
        let siteLabel = NSTextField(labelWithString: preview.siteName.uppercased())
        siteLabel.font = MMFont.font(ofSize: 10, weight: .semibold)
        siteLabel.textColor = Theme.shared.centerTextMuted
        siteLabel.isEditable = false
        siteLabel.isSelectable = false
        siteLabel.lineBreakMode = .byTruncatingTail
        let siteY = card.frame.height - (hasImage ? 26 : 18)
        siteLabel.frame = NSRect(x: 12, y: siteY, width: textWidth, height: 14)
        card.addSubview(siteLabel)

        if !preview.title.isEmpty {
            let title = NSTextField(labelWithString: preview.title)
            title.font = MMFont.font(ofSize: 13, weight: .semibold)
            title.textColor = Theme.shared.centerText
            title.isEditable = false
            title.isSelectable = false
            title.lineBreakMode = .byTruncatingTail
            let titleY = card.frame.height - (hasImage ? 48 : 38)
            title.frame = NSRect(x: 12, y: titleY, width: textWidth, height: 18)
            card.addSubview(title)
        }

        if !preview.description.isEmpty {
            let description = NSTextField(wrappingLabelWithString: preview.description)
            description.font = MMFont.font(ofSize: 11)
            description.textColor = Theme.shared.centerTextMuted
            description.isEditable = false
            description.isSelectable = false
            description.maximumNumberOfLines = 2
            description.lineBreakMode = .byTruncatingTail
            description.frame = NSRect(
                x: 12,
                y: 12,
                width: textWidth,
                height: hasImage ? 34 : 24
            )
            card.addSubview(description)
        }

        if let imageURL = preview.imageURL, hasImage {
            let imagePanel = RoundedEdgePanel()
            imagePanel.cornerRadius = MMRadius.tiny
            imagePanel.clipContentToBounds = true
            imagePanel.color = Theme.shared.centerHover
            imagePanel.frame = NSRect(
                x: maxWidth - 80,
                y: (card.frame.height - 72) / 2,
                width: 68,
                height: 72
            )
            let imageView = NSImageView(frame: NSRect(origin: .zero, size: imagePanel.frame.size))
            imageView.imageScaling = .scaleProportionallyUpOrDown
            imagePanel.addSubview(imageView)
            card.addSubview(imagePanel)

            let key = imageURL.absoluteString
            if let cached = linkPreviewImages[key] {
                imageView.image = cached
            } else if !linkPreviewImageLoading.contains(key) {
                linkPreviewImageLoading.insert(key)
                Task { @MainActor [weak imageView] in
                    defer { self.linkPreviewImageLoading.remove(key) }
                    if let data = await LinkPreviewService.fetchImageData(url: imageURL),
                        let image = NSImage(data: data)
                    {
                        self.linkPreviewImages[key] = image
                        imageView?.image = image
                    }
                }
            }
        }

        card.onHoverChanged = { [weak card] isHovered in
            card?.color =
                isHovered
                ? Theme.shared.centerHover
                : Theme.shared.centerHoverSubtle
            card?.setNeedsAppearanceUpdate()
        }
        card.onClick = {
            NSWorkspace.shared.open(preview.url)
        }
        card.accessibilityTitle = preview.title.isEmpty ? preview.url.absoluteString : preview.title
        card.accessibilityHelp = "Open link preview"
        return card
    }
}
