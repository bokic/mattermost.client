//
//  MainWindow+Menus.swift
//  mattermost.client
//
//  Split from MainWindow.swift.
//

import AppKit
import Foundation
import UniformTypeIdentifiers

extension MainWindow {

    func toggleProductSwitcherMenu() {
        if !isProductMenuOpen {
            setTeamMenuOpen(false)
            setSearchPopoverOpen(false)
            setHelpMenuOpen(false)
            setStatusMenuOpen(false)
        }
        setProductSwitcherMenuOpen(!isProductMenuOpen)
    }

    func setProductSwitcherMenuOpen(_ open: Bool) {
        guard isProductMenuOpen != open else { return }
        isProductMenuOpen = open
        productSwitcherMenu.isHidden = !open
        updateProductSwitcherAppearance()
    }

    func toggleHelpMenu() {
        if !isHelpMenuOpen {
            setTeamMenuOpen(false)
            setProductSwitcherMenuOpen(false)
            setSearchPopoverOpen(false)
            setStatusMenuOpen(false)
        }
        setHelpMenuOpen(!isHelpMenuOpen)
    }

    func setHelpMenuOpen(_ open: Bool) {
        guard isHelpMenuOpen != open else { return }
        isHelpMenuOpen = open
        helpMenu.isHidden = !open
        updateHelpButtonAppearance()
    }

    func toggleStatusMenu() {
        if !isStatusMenuOpen {
            setTeamMenuOpen(false)
            setProductSwitcherMenuOpen(false)
            setSearchPopoverOpen(false)
            setHelpMenuOpen(false)
        }
        DebugLog.log("toggleStatusMenu, will set to: \(!isStatusMenuOpen)")
        setStatusMenuOpen(!isStatusMenuOpen)
    }

    func setStatusMenuOpen(_ open: Bool) {
        guard isStatusMenuOpen != open else { return }
        DebugLog.log("setStatusMenuOpen: \(open)")
        isStatusMenuOpen = open
        statusMenu.isHidden = !open
        if !open {
            setDndSubMenuOpen(false)
        }
        updateAvatarButtonAppearance()
    }

    func toggleTeamMenu() {
        setTeamMenuOpen(!isTeamMenuOpen)
    }

    func setTeamMenuOpen(_ open: Bool) {
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

    func setDndSubMenuOpen(_ open: Bool) {
        guard isDndSubMenuOpen != open else { return }
        isDndSubMenuOpen = open
        dndSubMenu.isHidden = !open
        let rowHoverBg = Theme.shared.centerHover
        if let dndRow = dndStatusRow {
            dndRow.color = (open || dndRow.isHovered) ? rowHoverBg : .clear
            dndRow.setNeedsAppearanceUpdate()
        }
    }

    func scheduleDndHoverCheck() {
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

    func setupProductSwitcherMenu() {
        let menuWidth: CGFloat = 220
        let brandBlue = Theme.shared.buttonBg
        let darkText = Theme.shared.centerText
        let mutedIcon = Theme.shared.centerTextMuted
        let rowHoverBg = Theme.shared.centerHover
        let dividerColor = Theme.shared.divider

        productSwitcherMenu.color = Theme.shared.centerBg
        productSwitcherMenu.cornerRadius = MMRadius.menu
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
            font: MMFont.font(ofSize: 13, weight: .semibold),
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
                font: MMFont.font(ofSize: 13, weight: .regular),
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
        footerBadgePanel.cornerRadius = MMRadius.tiny

        let footerBadgeLabel = NSTextField(labelWithString: "TEAM EDITION")
        footerBadgeLabel.font = MMFont.font(ofSize: 8, weight: .bold)
        footerBadgeLabel.textColor = Theme.shared.centerTextMuted
        footerBadgeLabel.alignment = .center

        let footerBadgeText = footerBadgeLabel.stringValue.isEmpty ? "TEAM EDITION" : footerBadgeLabel.stringValue
        let footerFont = footerBadgeLabel.font ?? MMFont.font(ofSize: 8, weight: .bold)
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
                .font: MMFont.font(ofSize: 11),
                .foregroundColor: mutedIcon
            ]
        )
        footerText.append(NSAttributedString(
            string: "unsupported",
            attributes: [
                .font: MMFont.font(ofSize: 11),
                .foregroundColor: brandBlue,
                .underlineStyle: NSUnderlineStyle.single.rawValue
            ]
        ))
        footerText.append(NSAttributedString(
            string: " edition of\nMattermost.",
            attributes: [
                .font: MMFont.font(ofSize: 11),
                .foregroundColor: mutedIcon
            ]
        ))

        let footerLabel = NSTextField(labelWithAttributedString: footerText)
        footerLabel.maximumNumberOfLines = 2
        footerLabel.frame = NSRect(x: 16, y: 12, width: menuWidth - 32, height: 30)
        productSwitcherMenu.addSubview(footerLabel)

        contentView?.addSubview(productSwitcherMenu)
    }

    func setupHelpMenu() {
        let menuWidth: CGFloat = 204
        let brandBlue = Theme.shared.buttonBg
        let darkText = Theme.shared.centerText
        let mutedIcon = Theme.shared.centerTextMuted
        let rowHoverBg = Theme.shared.centerHover
        let dividerColor = Theme.shared.divider

        helpMenu.color = Theme.shared.centerBg
        helpMenu.cornerRadius = MMRadius.menu
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
                font: MMFont.font(ofSize: 13, weight: .regular),
                textColor: darkText,
                hoverBg: rowHoverBg,
                showsCheckmark: false,
                checkmarkColor: brandBlue
            )
            helpMenu.addSubview(row)
        }

        contentView?.addSubview(helpMenu)
    }

    func setupStatusMenu() {
        let menuWidth: CGFloat = 248
        let brandBlue = Theme.shared.buttonBg
        let darkText = Theme.shared.centerText
        let mutedIcon = Theme.shared.centerTextMuted
        let rowHoverBg = Theme.shared.centerHover
        let dividerColor = Theme.shared.divider

        statusMenu.color = Theme.shared.centerBg
        statusMenu.cornerRadius = MMRadius.menu
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
        headerAvatar.cornerRadius = MMRadius.large
        headerAvatar.color = NSColor(red: 156 / 255, green: 171 / 255, blue: 36 / 255, alpha: 1.0)

        let rawUsername = UserDefaults.standard.string(forKey: "username") ?? "boris"
        let cleanUsername = rawUsername.isEmpty ? "boris" : rawUsername
        let initial = cleanUsername.first.map { String($0).uppercased() } ?? "B"

        let headerAvatarLabel = NSTextField(labelWithString: initial)
        headerAvatarLabel.font = MMFont.font(ofSize: 13, weight: .semibold)
        headerAvatarLabel.textColor = .white
        headerAvatarLabel.alignment = .center
        headerAvatarLabel.frame = NSRect(x: 0, y: 5, width: 28, height: 18)
        headerAvatar.addSubview(headerAvatarLabel)
        headerRow.addSubview(headerAvatar)

        let menuDot = RoundedEdgePanel()
        menuDot.frame = NSRect(x: 34, y: 11, width: 10, height: 10)
        menuDot.cornerRadius = 5
        menuDot.color = statusColor(for: currentUserStatus)
        menuDot.borderWidth = 1.5
        menuDot.borderColor = Theme.shared.centerBg
        headerRow.addSubview(menuDot)
        menuAvatarStatusDot = menuDot

        let usernameLabel = NSTextField(labelWithString: "@\(cleanUsername)")
        usernameLabel.font = MMFont.font(ofSize: 13, weight: .semibold)
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
            font: MMFont.font(ofSize: 13, weight: .regular),
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
        customStatusRow.onClick = { [weak self] in
            self?.setStatusMenuOpen(false)
            self?.showCustomStatusDialog()
        }
        customStatusMenuRow = customStatusRow
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
            (0, "checkmark.circle.fill", Theme.shared.onlineIndicator, "Online", nil, 216, 34, false),
            (1, "clock.fill", Theme.shared.awayIndicator, "Away", nil, 182, 34, false),
            (2, "minus.circle.fill", Theme.shared.dndIndicator, "Do not disturb", "Disables all notifications", 136, 46, true),
            (3, "circle", Theme.shared.centerTextPlaceholder, "Offline", nil, 102, 34, false)
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
            titleLabel.font = MMFont.font(ofSize: 13, weight: .regular)
            titleLabel.textColor = darkText
            let titleY: CGFloat = cfg.subtitle != nil ? 21 : (cfg.height - 18) / 2
            titleLabel.frame = NSRect(x: 42, y: titleY, width: menuWidth - 80, height: 18)
            row.addSubview(titleLabel)

            if let subtitle = cfg.subtitle {
                let subLabel = NSTextField(labelWithString: subtitle)
                subLabel.font = MMFont.font(ofSize: 11, weight: .regular)
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
            font: MMFont.font(ofSize: 13, weight: .regular),
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
            font: MMFont.font(ofSize: 13, weight: .regular),
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
        logoutRow.onClick = { [weak self] in
            self?.setStatusMenuOpen(false)
            (NSApp.delegate as? AppDelegate)?.logout()
        }
        statusMenu.addSubview(logoutRow)

        contentView?.addSubview(statusMenu)
        setupDndSubMenu()
        updateCustomStatusUI()
    }

    func setupDndSubMenu() {
        let subWidth: CGFloat = 212
        let darkText = Theme.shared.centerText
        let mutedText = Theme.shared.centerTextMuted
        let rowHoverBg = Theme.shared.centerHover
        let dividerColor = Theme.shared.divider

        dndSubMenu.color = Theme.shared.centerBg
        dndSubMenu.cornerRadius = MMRadius.menu
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
        headerLabel.font = MMFont.font(ofSize: 11.5, weight: .semibold)
        headerLabel.textColor = mutedText
        headerLabel.frame = NSRect(x: 20, y: 201, width: subWidth - 36, height: 18)
        dndSubMenu.addSubview(headerLabel)

        let tomorrowDayString: String = {
            let tomorrow = Calendar.current.date(byAdding: .day, value: 1, to: Date()) ?? Date()
            return "\(Self.localizedShortWeekdayFormatter.string(from: tomorrow)), 9:00 AM"
        }()

        let rows: [(title: String, rightText: String?, y: CGFloat, height: CGFloat, durationSeconds: TimeInterval?)] = [
            ("Don't clear", nil, 167, 30, nil),
            ("30 mins", nil, 137, 30, 30 * 60),
            ("1 hour", nil, 107, 30, 60 * 60),
            ("2 hours", nil, 77, 30, 120 * 60),
            ("Tomorrow", tomorrowDayString, 47, 30, nil),
            ("Choose date and time", nil, 6, 32, nil)
        ]

        for item in rows {
            let row = RoundedEdgePanel()
            row.frame = NSRect(x: 0, y: item.y, width: subWidth, height: item.height)
            row.cornerRadius = 0
            row.color = .clear

            let titleLabel = NSTextField(labelWithString: item.title)
            titleLabel.font = MMFont.font(ofSize: 13, weight: .regular)
            titleLabel.textColor = darkText
            titleLabel.frame = NSRect(x: 20, y: (item.height - 18) / 2, width: item.rightText != nil ? 90 : (subWidth - 36), height: 18)
            row.addSubview(titleLabel)

            if let rightText = item.rightText {
                let rightLabel = NSTextField(labelWithString: rightText)
                rightLabel.font = MMFont.font(ofSize: 12, weight: .regular)
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
                var dndEndMs: Int64? = nil
                if let dur = item.durationSeconds {
                    dndEndMs = Int64((Date().timeIntervalSince1970 + dur) * 1000)
                } else if item.title == "Tomorrow" {
                    let tomorrow = Calendar.current.date(byAdding: .day, value: 1, to: Date()) ?? Date()
                    var comp = Calendar.current.dateComponents([.year, .month, .day], from: tomorrow)
                    comp.hour = 9
                    comp.minute = 0
                    comp.second = 0
                    if let d = Calendar.current.date(from: comp) {
                        dndEndMs = Int64(d.timeIntervalSince1970 * 1000)
                    }
                }
                self?.selectUserStatus(2, dndEndTime: dndEndMs)
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

    func createMenuRow(
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

    func setupFilterMenu() {
        let dividerColor = Theme.shared.divider
        let textColor = Theme.shared.centerText

        filterMenu.color = Theme.shared.centerBg
        filterMenu.cornerRadius = MMRadius.menu
        filterMenu.borderWidth = 1
        filterMenu.borderColor = dividerColor
        filterMenu.shadowColor = .black
        filterMenu.shadowOpacity = 0.18
        filterMenu.shadowRadius = 10
        filterMenu.shadowOffset = CGSize(width: 0, height: -4)
        filterMenu.isHidden = true

        let makeRow: (String, CGFloat, Bool) -> (RoundedEdgePanel, NSImageView) = { [weak self] title, y, favorites in
            let row = RoundedEdgePanel()
            row.frame = NSRect(x: 6, y: y, width: 168, height: 28)
            row.cornerRadius = MMRadius.control
            row.color = .clear
            let label = NSTextField(labelWithString: title)
            label.font = MMFont.font(ofSize: 13)
            label.textColor = textColor
            label.isEditable = false
            label.isSelectable = false
            label.frame = NSRect(x: 10, y: 5, width: 120, height: 18)
            row.addSubview(label)
            let check = NSImageView()
            if let image = NSImage(systemSymbolName: "checkmark", accessibilityDescription: "Selected") {
                check.image = image.withSymbolConfiguration(.init(pointSize: 11, weight: .bold))
                check.contentTintColor = Theme.shared.buttonBg
            }
            check.frame = NSRect(x: 146, y: 7, width: 14, height: 14)
            row.addSubview(check)
            row.onHoverChanged = { [weak row] isHovered in
                row?.color = isHovered
                    ? Theme.shared.centerHover
                    : .clear
                row?.setNeedsAppearanceUpdate()
            }
            row.onClick = { [weak self] in
                guard let self = self else { return }
                self.sidebarFavoritesOnly = favorites
                self.setFilterMenuOpen(false)
                self.updateFilterMenuAppearance()
                self.layoutLeftSidebar(topBarY: self.mainPanel.bounds.height)
            }
            return (row, check)
        }

        let all = makeRow("All channels", 36, false)
        filterMenu.addSubview(all.0)
        filterAllCheck = all.1
        let favorites = makeRow("Favorites", 6, true)
        filterMenu.addSubview(favorites.0)
        filterFavoritesCheck = favorites.1

        mainPanel.addSubview(filterMenu)
        updateFilterMenuAppearance()
    }

    func setFilterMenuOpen(_ open: Bool) {
        isFilterMenuOpen = open
        filterMenu.isHidden = !open
    }

    func updateFilterMenuAppearance() {
        filterAllCheck?.isHidden = sidebarFavoritesOnly
        filterFavoritesCheck?.isHidden = !sidebarFavoritesOnly
    }

    func setupChannelMenu() {
        channelMenu.color = Theme.shared.centerBg
        channelMenu.cornerRadius = MMRadius.menu
        channelMenu.borderWidth = 1
        channelMenu.borderColor = Theme.shared.divider
        channelMenu.shadowColor = .black
        channelMenu.shadowOpacity = 0.18
        channelMenu.shadowRadius = 12
        channelMenu.shadowOffset = CGSize(width: 0, height: -4)
        channelMenu.isHidden = true
        chatPanel.addSubview(channelMenu)
    }

    func toggleChannelMenu() {
        if isChannelMenuOpen {
            closeChannelMenu()
        } else {
            showChannelMenu()
        }
    }

    func closeChannelMenu() {
        channelMenu.isHidden = true
        isChannelMenuOpen = false
    }

    func wireDMCategoryAddButton(_ category: SidebarCategoryView) {
        category.addButton?.onClick = { [weak self, weak addButton = category.addButton] in
            self?.toggleDMPicker(anchor: addButton)
        }
    }

    func setupDMPicker() {
        let dividerColor = Theme.shared.divider
        dmPickerPanel.color = Theme.shared.centerBg
        dmPickerPanel.cornerRadius = MMRadius.panel
        dmPickerPanel.borderWidth = 1
        dmPickerPanel.borderColor = dividerColor
        dmPickerPanel.shadowColor = .black
        dmPickerPanel.shadowOpacity = 0.18
        dmPickerPanel.shadowRadius = 12
        dmPickerPanel.shadowOffset = CGSize(width: 0, height: -4)
        dmPickerPanel.isHidden = true
        let dmAppearance = NSAppearance(named: Theme.shared.isDark ? .darkAqua : .aqua)
        dmPickerPanel.appearance = dmAppearance
        dmSearchField.appearance = dmAppearance

        dmSearchField.placeholderString = "Search for a user"
        dmSearchField.font = MMFont.font(ofSize: 13)
        dmSearchField.delegate = self
        dmSearchField.sendsSearchStringImmediately = true
        dmPickerPanel.addSubview(dmSearchField)

        dmScroll.drawsBackground = false
        dmScroll.hasVerticalScroller = true
        dmScroll.autohidesScrollers = true
        dmScroll.documentView = dmDoc
        dmPickerPanel.addSubview(dmScroll)

        contentView?.addSubview(dmPickerPanel)
    }

    func toggleDMPicker(anchor: NSView?) {
        if isDMPickerOpen {
            closeDMPicker()
            return
        }
        guard let ws = webService, ws.isLogged(),
              activeTeam != nil, let contentView = contentView else {
            showInfoAlert("Sign in to start a direct message.")
            return
        }

        let anchorRect: NSRect
        if let anchor = anchor {
            anchorRect = anchor.convert(anchor.bounds, to: contentView)
        } else {
            anchorRect = NSRect(x: 280, y: contentView.bounds.midY, width: 1, height: 1)
        }
        dmAnchorFrame = anchorRect

        let width: CGFloat = 300
        let height = min(360, max(220, contentView.bounds.height - 140))
        var x = anchorRect.maxX + 8
        var y = anchorRect.midY - height / 2
        if x + width > contentView.bounds.width - 8 {
            x = max(8, anchorRect.minX - width - 8)
        }
        y = min(max(8, y), contentView.bounds.height - height - 8)
        dmPickerPanel.frame = NSRect(x: x, y: y, width: width, height: height)
        dmSearchField.frame = NSRect(x: 12, y: height - 46, width: width - 24, height: 26)
        dmScroll.frame = NSRect(x: 0, y: 0, width: width, height: height - 58)
        dmSearchField.stringValue = ""
        dmPickerPanel.isHidden = false
        contentView.addSubview(dmPickerPanel)
        isDMPickerOpen = true

        if dmUsers.isEmpty {
            loadDMUsers()
        } else {
            renderDMUsers()
        }
        makeFirstResponder(dmSearchField)
    }

    func closeDMPicker() {
        dmPickerPanel.isHidden = true
        isDMPickerOpen = false
        dmSearchField.stringValue = ""
    }

    func loadDMUsers() {
        guard let ws = webService, ws.isLogged(),
              let team = activeTeam else { return }
        Task { @MainActor [weak self] in
            guard let self = self else { return }
            guard let users = try? await ws.fetchTeamUsers(teamId: team.id) else {
                self.dmUsers = []
                self.renderDMUsers(empty: "Could not load users")
                return
            }
            let myId = self.currentUser?.id ?? ws.currentUserId
            for user in users {
                self.usersById[user.id] = user
                self.usersByUsername[user.username.lowercased()] = user
                self.fetchAvatarIfNeeded(for: user.id)
            }
            self.dmUsers = users
                .filter { $0.id != myId }
                .sorted { $0.username.localizedCaseInsensitiveCompare($1.username) == .orderedAscending }
            self.renderDMUsers()
        }
    }

    func renderDMUsers(empty: String = "No users found") {
        let width = dmScroll.bounds.width
        dmDoc.subviews.forEach { $0.removeFromSuperview() }

        let query = dmSearchField.stringValue.trimmingCharacters(in: .whitespacesAndNewlines).lowercased()
        let filtered = dmUsers.filter { user in
            guard !query.isEmpty else { return true }
            let haystack = [
                user.username,
                user.first_name ?? "",
                user.last_name ?? "",
                user.nickname ?? ""
            ].joined(separator: " ").lowercased()
            return haystack.contains(query)
        }

        var y: CGFloat = 6
        if filtered.isEmpty {
            let label = NSTextField(labelWithString: empty)
            label.font = MMFont.font(ofSize: 13)
            label.textColor = Theme.shared.centerTextMuted
            label.alignment = .center
            label.isEditable = false
            label.isSelectable = false
            label.frame = NSRect(x: 12, y: 18, width: max(0, width - 24), height: 20)
            dmDoc.addSubview(label)
            dmDoc.frame = NSRect(x: 0, y: 0, width: width, height: 60)
            return
        }

        let palette = MMPalette.avatarColors

        for user in filtered {
            let row = RoundedEdgePanel()
            row.cornerRadius = MMRadius.control
            row.color = .clear
            row.frame = NSRect(x: 6, y: y, width: max(0, width - 12), height: 44)

            let avatarPanel = RoundedEdgePanel()
            avatarPanel.cornerRadius = MMRadius.large
            avatarPanel.clipContentToBounds = true
            avatarPanel.frame = NSRect(x: 8, y: 8, width: 28, height: 28)
            if let avatar = userAvatarsById[user.id] {
                avatarPanel.color = .clear
                let imageView = NSImageView(frame: NSRect(origin: .zero, size: avatarPanel.frame.size))
                imageView.image = avatar
                imageView.imageScaling = .scaleProportionallyUpOrDown
                avatarPanel.addSubview(imageView)
            } else {
                avatarPanel.color = palette[abs(user.username.hashValue) % palette.count]
                let initial = user.username.first.map { String($0).uppercased() } ?? "U"
                let initialLabel = NSTextField(labelWithString: initial)
                initialLabel.font = MMFont.font(ofSize: 12, weight: .semibold)
                initialLabel.textColor = .white
                initialLabel.alignment = .center
                initialLabel.isEditable = false
                initialLabel.isSelectable = false
                initialLabel.frame = NSRect(x: 0, y: 5, width: 28, height: 18)
                avatarPanel.addSubview(initialLabel)
            }
            row.addSubview(avatarPanel)

            let name = NSTextField(labelWithString: user.username)
            name.font = MMFont.font(ofSize: 13, weight: .semibold)
            name.textColor = Theme.shared.centerText
            name.isEditable = false
            name.isSelectable = false
            name.frame = NSRect(x: 44, y: 5, width: max(0, width - 70), height: 17)
            row.addSubview(name)

            let fullName = [user.first_name, user.last_name].compactMap { $0 }.joined(separator: " ")
            if !fullName.isEmpty {
                let subtitle = NSTextField(labelWithString: fullName)
                subtitle.font = MMFont.font(ofSize: 11)
                subtitle.textColor = Theme.shared.centerTextMuted
                subtitle.isEditable = false
                subtitle.isSelectable = false
                subtitle.frame = NSRect(x: 44, y: 22, width: max(0, width - 70), height: 15)
                row.addSubview(subtitle)
            }

            row.onHoverChanged = { [weak row] isHovered in
                row?.color = isHovered
                    ? Theme.shared.centerHover
                    : .clear
                row?.setNeedsAppearanceUpdate()
            }
            row.onClick = { [weak self] in
                self?.startDirectMessage(with: user)
            }
            dmDoc.addSubview(row)
            y += 48
        }

        dmDoc.frame = NSRect(x: 0, y: 0, width: width, height: max(y + 6, 1))
    }

    func startDirectMessage(with user: LoginWebService) {
        guard let ws = webService, ws.isLogged(),
              let team = activeTeam else { return }
        Task { @MainActor [weak self] in
            guard let self = self else { return }
            do {
                let channel = try await ws.createDirectChannel(userId: user.id)
                self.usersById[user.id] = user
                self.channelsById[channel.id] = channel
                self.channelsByName[channel.name.lowercased()] = channel
                if let categories = try? await ws.fetchSidebarCategories(teamId: team.id) {
                    self.populateSidebarCategories(from: categories, channels: Array(self.channelsById.values))
                }
                self.closeDMPicker()
                self.selectedSidebarItemId = channel.id
                self.updateSidebarSelectionAppearance()
                self.loadChannelPosts(forSidebarItemId: channel.id)
            } catch {
                self.showInfoAlert("Could not start a direct message: \(error.localizedDescription)")
            }
        }
    }

    func showChannelMenu() {
        guard !activeChannelId.isEmpty, channelsById[activeChannelId] != nil else { return }
        let favoriteTitle = isChannelFavorited ? "Remove from Favorites" : "Add to Favorites"
        let rows: [(symbol: String, title: String, action: () -> Void)] = [
            ("info.circle", "View Info", { [weak self] in
                self?.closeChannelMenu()
                self?.showRightPanel(mode: .members)
            }),
            ("pin", "Pinned Posts", { [weak self] in
                self?.closeChannelMenu()
                self?.showRightPanel(mode: .pinned)
            }),
            ("doc.text", "Files", { [weak self] in
                self?.closeChannelMenu()
                self?.showRightPanel(mode: .files)
            }),
            (isChannelFavorited ? "star.slash" : "star", favoriteTitle, { [weak self] in
                guard let self = self else { return }
                self.closeChannelMenu()
                self.setChannelFavorite(!self.isChannelFavorited, channelId: self.activeChannelId)
            }),
            ("link", "Copy Link", { [weak self] in
                guard let self = self else { return }
                self.closeChannelMenu()
                self.copyChannelLink()
            }),
            ("rectangle.portrait.and.arrow.right", "Leave Channel", { [weak self] in
                self?.closeChannelMenu()
                self?.confirmLeaveChannel()
            })
        ]

        channelMenu.subviews.forEach { $0.removeFromSuperview() }

        let rowHeight: CGFloat = 32
        let width: CGFloat = 230
        let height = CGFloat(rows.count) * rowHeight + 8
        var x = channelTitleButton.frame.minX
        x = min(max(8, x), chatPanel.bounds.width - width - 8)
        var y = channelTitleButton.frame.minY - height - 4
        if y < 8 { y = channelTitleButton.frame.maxY + 4 }
        channelMenu.frame = NSRect(x: x, y: y, width: width, height: height)

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
            channelMenu.addSubview(row)
        }

        channelMenu.isHidden = false
        channelMenu.superview?.addSubview(channelMenu)
        isChannelMenuOpen = true
    }

    func copyChannelLink() {
        guard let channel = channelsById[activeChannelId] else { return }
        var host = UserDefaults.standard.string(forKey: "host") ?? ""
        let port = UserDefaults.standard.integer(forKey: "port")
        if port > 0 && !host.hasSuffix(":\(port)") {
            host += ":\(port)"
        }
        let teamName = activeTeam?.name ?? ""
        let url = "\(host)/\(teamName)/channels/\(channel.name)"
        NSPasteboard.general.clearContents()
        NSPasteboard.general.setString(url, forType: .string)
        composerHelpLabel.stringValue = "Link copied"
        DispatchQueue.main.asyncAfter(deadline: .now() + 2) { [weak self] in
            self?.composerHelpLabel.stringValue = "Help"
        }
    }

    func confirmLeaveChannel() {
        guard let channel = channelsById[activeChannelId] else { return }
        let alert = NSAlert()
        alert.messageText = "Leave \(channelDisplayName(for: channel))?"
        alert.informativeText = "You will stop receiving messages from this channel."
        alert.addButton(withTitle: "Leave")
        alert.addButton(withTitle: "Cancel")
        alert.beginSheetModal(for: self) { [weak self] response in
            guard let self = self, response == .alertFirstButtonReturn else { return }
            self.leaveChannel(channel)
        }
    }

    func leaveChannel(_ channel: MMChannel) {
        guard let ws = webService, ws.isLogged(),
              let team = activeTeam else { return }
        let userId = currentUser?.id ?? ws.currentUserId
        guard !userId.isEmpty else { return }
        Task { @MainActor [weak self] in
            guard let self = self else { return }
            do {
                try await ws.leaveChannel(channelId: channel.id, userId: userId)
                self.channelsById.removeValue(forKey: channel.id)
                self.channelsByName.removeValue(forKey: channel.name.lowercased())
                self.channelsByName.removeValue(forKey: channel.display_name.lowercased())
                if let categories = try? await ws.fetchSidebarCategories(teamId: team.id) {
                    self.populateSidebarCategories(from: categories, channels: Array(self.channelsById.values))
                }
                if self.activeChannelId == channel.id,
                   let fallback = self.channelsByName["town-square"] ?? self.channelsById.values.first {
                    self.selectedSidebarItemId = fallback.id
                    self.updateSidebarSelectionAppearance()
                    self.loadChannelPosts(forSidebarItemId: fallback.id)
                }
            } catch {
                self.showInfoAlert("Could not leave channel: \(error.localizedDescription)")
            }
        }
    }

    func showInviteDialog() {
        guard let team = activeTeam else { return }
        let alert = NSAlert()
        alert.messageText = "Invite people to \(team.display_name)"
        alert.informativeText = "Send an email invitation to join this team."
        alert.addButton(withTitle: "Send Invite")
        alert.addButton(withTitle: "Cancel")

        let field = NSTextField(frame: NSRect(x: 0, y: 0, width: 280, height: 24))
        field.placeholderString = "name@example.com"
        alert.accessoryView = field
        alert.beginSheetModal(for: self) { [weak self] response in
            guard let self = self, response == .alertFirstButtonReturn else { return }
            let email = field.stringValue.trimmingCharacters(in: .whitespacesAndNewlines)
            guard email.contains("@"), email.contains(".") else {
                self.showInfoAlert("Enter a valid email address.")
                return
            }
            guard let ws = self.webService else { return }
            Task { @MainActor in
                do {
                    try await ws.sendTeamInvite(teamId: team.id, email: email)
                    self.showInfoAlert("Invitation sent to \(email).")
                } catch {
                    self.showInfoAlert("Could not send invite: \(error.localizedDescription)")
                }
            }
        }
    }

    func showCreateTeamDialog() {
        let alert = NSAlert()
        alert.messageText = "Create a team"
        alert.informativeText = "Teams group channels and members."
        alert.addButton(withTitle: "Create")
        alert.addButton(withTitle: "Cancel")

        let container = NSView(frame: NSRect(x: 0, y: 0, width: 280, height: 56))
        let displayField = NSTextField(frame: NSRect(x: 0, y: 30, width: 280, height: 24))
        displayField.placeholderString = "Display name (e.g. Engineering)"
        let nameField = NSTextField(frame: NSRect(x: 0, y: 0, width: 280, height: 24))
        nameField.placeholderString = "URL name (e.g. engineering)"
        container.addSubview(displayField)
        container.addSubview(nameField)
        alert.accessoryView = container

        alert.beginSheetModal(for: self) { [weak self] response in
            guard let self = self, response == .alertFirstButtonReturn else { return }
            var displayName = displayField.stringValue.trimmingCharacters(in: .whitespacesAndNewlines)
            var name = nameField.stringValue.trimmingCharacters(in: .whitespacesAndNewlines).lowercased()
            if displayName.isEmpty { displayName = name }
            if name.isEmpty {
                name = displayName.lowercased()
                    .replacingOccurrences(of: " ", with: "-")
                    .filter { $0.isLetter || $0.isNumber || $0 == "-" }
            }
            guard !name.isEmpty else {
                self.showInfoAlert("Enter a team name.")
                return
            }
            guard let ws = self.webService else { return }
            Task { @MainActor in
                do {
                    let team = try await ws.createTeam(name: name, displayName: displayName)
                    if let teams = try? await ws.fetchTeams() {
                        self.userTeams = teams
                    }
                    self.switchActiveTeam(to: team)
                } catch {
                    self.showInfoAlert("Could not create team: \(error.localizedDescription)")
                }
            }
        }
    }

    func showInfoAlert(_ message: String) {
        let alert = NSAlert()
        alert.messageText = "Mattermost"
        alert.informativeText = message
        alert.addButton(withTitle: "OK")
        alert.beginSheetModal(for: self)
    }
}
