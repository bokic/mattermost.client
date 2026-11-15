//
//  MainWindow+ChannelContextMenu.swift
//  mattermost.client
//
//  Right-click actions for sidebar channel rows.
//

import AppKit

extension MainWindow {

    func showChannelContextMenu(channelId: String, from view: NSView) {
        guard channelsById[channelId] != nil else { return }
        let menu = NSMenu()
        let muted = isChannelMuted(channelId)
        let favorite = favoriteChannelIds.contains(channelId)
        let unread = (unreadByChannel[channelId] ?? 0) > 0
            || (mentionsByChannel[channelId] ?? 0) > 0

        func add(_ title: String, _ action: Selector, _ id: String? = nil, state: NSControl.StateValue = .off) {
            let item = NSMenuItem(title: title, action: action, keyEquivalent: "")
            item.target = self
            item.representedObject = id
            item.state = state
            menu.addItem(item)
        }

        add("View Info", #selector(contextViewChannelInfo(_:)), channelId)
        add("Pinned Posts", #selector(contextShowPinned(_:)), channelId)
        add("Files", #selector(contextShowFiles(_:)), channelId)
        menu.addItem(.separator())
        if unread {
            add("Mark as Read", #selector(contextMarkRead(_:)), channelId)
        } else {
            add("Mark as Unread", #selector(contextMarkUnread(_:)), channelId)
        }
        add("Mark All as Read", #selector(contextMarkAllRead))

        let notifications = NSMenuItem(title: "Notifications", action: nil, keyEquivalent: "")
        let submenu = NSMenu()
        let current = channelDesktopNotificationByChannel[channelId] ?? "default"
        let mutedItem = NSMenuItem(
            title: muted ? "Unmute Channel" : "Mute Channel",
            action: #selector(contextToggleMute(_:)),
            keyEquivalent: ""
        )
        mutedItem.target = self
        mutedItem.representedObject = channelId
        submenu.addItem(mutedItem)
        submenu.addItem(.separator())

        let preferences: [(String, String)] = [
            ("default", "All messages"),
            ("mention", "Mentions only"),
            ("none", "Never"),
        ]
        for (value, title) in preferences {
            let item = NSMenuItem(
                title: title,
                action: #selector(contextSetNotificationPreference(_:)),
                keyEquivalent: ""
            )
            item.target = self
            item.representedObject = [channelId, value]
            item.state = current == value ? .on : .off
            submenu.addItem(item)
        }
        notifications.submenu = submenu
        menu.addItem(notifications)

        add(
            favorite ? "Remove from Favorites" : "Add to Favorites",
            #selector(contextToggleFavorite(_:)),
            channelId
        )
        add("Copy Link", #selector(contextCopyLink(_:)), channelId)
        menu.addItem(.separator())
        add("Leave Channel", #selector(contextLeaveChannel(_:)), channelId)

        menu.popUp(
            positioning: nil,
            at: NSPoint(x: 24, y: 4),
            in: view
        )
    }

    @objc private func contextViewChannelInfo(_ sender: NSMenuItem) {
        guard let id = sender.representedObject as? String else { return }
        openChannel(withId: id)
        showRightPanel(mode: .channelInfo)
    }

    @objc private func contextShowPinned(_ sender: NSMenuItem) {
        guard let id = sender.representedObject as? String else { return }
        openChannel(withId: id)
        showRightPanel(mode: .pinned)
    }

    @objc private func contextShowFiles(_ sender: NSMenuItem) {
        guard let id = sender.representedObject as? String else { return }
        openChannel(withId: id)
        showRightPanel(mode: .files)
    }

    @objc private func contextMarkRead(_ sender: NSMenuItem) {
        guard let id = sender.representedObject as? String else { return }
        unreadByChannel[id] = 0
        mentionsByChannel[id] = 0
        lastViewedAtByChannel[id] = Int64(Date().timeIntervalSince1970 * 1000)
        (NSApp.delegate as? AppDelegate)?.markChannelRead(id)
        updateSidebarBadges()
    }

    @objc private func contextMarkUnread(_ sender: NSMenuItem) {
        guard let id = sender.representedObject as? String,
              let ws = webService, ws.isLogged()
        else { return }
        let userId = currentUser?.id ?? ws.currentUserId
        guard !userId.isEmpty else { return }
        Task { @MainActor [weak self] in
            guard let self = self else { return }
            guard let list = try? await ws.fetchChannelPosts(channelId: id, perPage: 1),
                  let post = list.order.compactMap({ list.posts[$0] }).first
            else { return }
            do {
                try await ws.markChannelUnread(userId: userId, channelId: id, postId: post.id)
                self.unreadByChannel[id, default: 0] = max(1, self.unreadByChannel[id] ?? 0)
                self.updateSidebarBadges()
            } catch {
                self.showInfoAlert("Could not mark the channel unread: \(error.localizedDescription)")
            }
        }
    }

    @objc private func contextMarkAllRead() {
        markAllChannelsRead()
    }

    @objc private func contextToggleFavorite(_ sender: NSMenuItem) {
        guard let id = sender.representedObject as? String else { return }
        setChannelFavorite(!favoriteChannelIds.contains(id), channelId: id)
    }

    @objc private func contextCopyLink(_ sender: NSMenuItem) {
        guard let id = sender.representedObject as? String,
              let channel = channelsById[id]
        else { return }
        let teamName = activeTeam?.name ?? ""
        let path = "/\(teamName)/channels/\(channel.name)"
        let url = webService?.buildURL(path: path)?.absoluteString ?? path
        NSPasteboard.general.clearContents()
        NSPasteboard.general.setString(url, forType: .string)
    }

    @objc private func contextLeaveChannel(_ sender: NSMenuItem) {
        guard let id = sender.representedObject as? String,
              let channel = channelsById[id]
        else { return }
        let alert = NSAlert()
        alert.messageText = "Leave \(channelDisplayName(for: channel))?"
        alert.informativeText = "You will stop receiving messages from this channel."
        alert.addButton(withTitle: "Leave")
        alert.addButton(withTitle: "Cancel")
        alert.beginSheetModal(for: self) { [weak self] response in
            guard response == .alertFirstButtonReturn else { return }
            self?.leaveChannel(channel)
        }
    }

    @objc private func contextToggleMute(_ sender: NSMenuItem) {
        guard let id = sender.representedObject as? String else { return }
        let muted = isChannelMuted(id)
        setChannelNotificationPreference(
            channelId: id,
            desktop: muted ? "default" : "none"
        )
    }

    @objc private func contextSetNotificationPreference(_ sender: NSMenuItem) {
        guard let values = sender.representedObject as? [String],
              values.count == 2
        else { return }
        setChannelNotificationPreference(channelId: values[0], desktop: values[1])
    }

    func setChannelNotificationPreference(channelId: String, desktop: String) {
        guard let ws = webService, ws.isLogged() else { return }
        let userId = currentUser?.id ?? ws.currentUserId
        guard !userId.isEmpty else { return }
        let previous = channelDesktopNotificationByChannel[channelId]
        let wasMuted = isChannelMuted(channelId)
        channelDesktopNotificationByChannel[channelId] = desktop
        if desktop == "none" {
            mutedChannelIds.insert(channelId)
        } else {
            mutedChannelIds.remove(channelId)
        }
        updateSidebarSelectionAppearance()
        updateSidebarBadges()

        Task { @MainActor [weak self] in
            guard let self = self else { return }
            do {
                try await ws.updateChannelNotifyProps(
                    channelId: channelId,
                    userId: userId,
                    props: [
                        "desktop": desktop,
                        "mark_unread": desktop == "none" ? "mention" : "all",
                    ]
                )
            } catch {
                if let previous = previous {
                    self.channelDesktopNotificationByChannel[channelId] = previous
                } else {
                    self.channelDesktopNotificationByChannel.removeValue(forKey: channelId)
                }
                if wasMuted {
                    self.mutedChannelIds.insert(channelId)
                } else {
                    self.mutedChannelIds.remove(channelId)
                }
                self.updateSidebarSelectionAppearance()
                self.updateSidebarBadges()
                self.showInfoAlert("Could not update notifications: \(error.localizedDescription)")
            }
        }
    }
}
