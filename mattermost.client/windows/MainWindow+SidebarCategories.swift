//
//  MainWindow+SidebarCategories.swift
//  mattermost.client
//
//  Create, rename, delete and reorder Mattermost sidebar categories.
//

import AppKit

extension MainWindow {

    func isCustomSidebarCategory(_ categoryId: String) -> Bool {
        let normalized = categoryId.lowercased()
        return normalized != "favorites"
            && normalized != "channels"
            && normalized != "direct_messages"
            && !normalized.contains("favorites")
    }

    func currentCategoryUserId() -> String? {
        let id = currentUser?.id ?? webService?.currentUserId ?? ""
        return id.isEmpty ? nil : id
    }

    func refreshSidebarCategories() {
        guard let ws = webService, ws.isLogged(), let team = activeTeam else { return }
        Task { @MainActor [weak self] in
            guard let self = self else { return }
            guard let categories = try? await ws.fetchSidebarCategories(teamId: team.id) else { return }
            self.populateSidebarCategories(
                from: categories,
                channels: Array(self.channelsById.values)
            )
        }
    }

    func showSidebarCategoryMenu(_ categoryId: String) {
        guard let category = sidebarCategories.first(where: { $0.id == categoryId }) else { return }
        let menu = NSMenu()

        let newItem = NSMenuItem(
            title: "New Category…",
            action: #selector(createSidebarCategoryMenuSelected),
            keyEquivalent: ""
        )
        newItem.target = self
        menu.addItem(newItem)

        if isCustomSidebarCategory(categoryId) {
            menu.addItem(.separator())

            let rename = NSMenuItem(
                title: "Rename Category…",
                action: #selector(renameSidebarCategoryMenuSelected(_:)),
                keyEquivalent: ""
            )
            rename.target = self
            rename.representedObject = categoryId
            menu.addItem(rename)

            let addChannel = NSMenuItem(
                title: "Add Channel…",
                action: #selector(addChannelToCategoryMenuSelected(_:)),
                keyEquivalent: ""
            )
            addChannel.target = self
            addChannel.representedObject = categoryId
            menu.addItem(addChannel)

            menu.addItem(.separator())

            let moveUp = NSMenuItem(
                title: "Move Category Up",
                action: #selector(moveSidebarCategoryUp(_:)),
                keyEquivalent: ""
            )
            moveUp.target = self
            moveUp.representedObject = categoryId
            menu.addItem(moveUp)

            let moveDown = NSMenuItem(
                title: "Move Category Down",
                action: #selector(moveSidebarCategoryDown(_:)),
                keyEquivalent: ""
            )
            moveDown.target = self
            moveDown.representedObject = categoryId
            menu.addItem(moveDown)

            menu.addItem(.separator())
            let delete = NSMenuItem(
                title: "Delete Category",
                action: #selector(deleteSidebarCategoryMenuSelected(_:)),
                keyEquivalent: ""
            )
            delete.target = self
            delete.representedObject = categoryId
            menu.addItem(delete)
        }

        menu.popUp(
            positioning: nil,
            at: NSPoint(x: 20, y: category.headerRow.bounds.height + 2),
            in: category.headerRow
        )
    }

    @objc private func createSidebarCategoryMenuSelected() {
        createSidebarCategoryInteractive()
    }

    func createSidebarCategoryInteractive() {
        guard let ws = webService, ws.isLogged(),
            let team = activeTeam,
            let userId = currentCategoryUserId()
        else { return }
        let alert = NSAlert()
        alert.messageText = "New category"
        alert.informativeText = "Create a custom sidebar category."
        alert.addButton(withTitle: "Create")
        alert.addButton(withTitle: "Cancel")
        let field = NSTextField(frame: NSRect(x: 0, y: 0, width: 280, height: 24))
        field.placeholderString = "Category name"
        alert.accessoryView = field
        alert.beginSheetModal(for: self) { [weak self] response in
            guard response == .alertFirstButtonReturn else { return }
            let name = field.stringValue.trimmingCharacters(in: .whitespacesAndNewlines)
            guard !name.isEmpty else { return }
            Task { @MainActor [weak self] in
                guard let self = self else { return }
                do {
                    _ = try await ws.createSidebarCategory(
                        teamId: team.id,
                        displayName: name,
                        userId: userId
                    )
                    self.refreshSidebarCategories()
                } catch {
                    self.showInfoAlert("Could not create the category: \(error.localizedDescription)")
                }
            }
        }
    }

    @objc private func renameSidebarCategoryMenuSelected(_ sender: NSMenuItem) {
        guard let categoryId = sender.representedObject as? String else { return }
        renameSidebarCategoryInteractive(categoryId)
    }

    func renameSidebarCategoryInteractive(_ categoryId: String) {
        guard let ws = webService, ws.isLogged(),
            let team = activeTeam,
            let userId = currentCategoryUserId()
        else { return }
        let alert = NSAlert()
        alert.messageText = "Rename category"
        alert.addButton(withTitle: "Rename")
        alert.addButton(withTitle: "Cancel")
        let field = NSTextField(frame: NSRect(x: 0, y: 0, width: 280, height: 24))
        field.stringValue =
            sidebarCategories
            .first(where: { $0.id == categoryId })?
            .titleLabel.stringValue ?? ""
        alert.accessoryView = field
        alert.beginSheetModal(for: self) { [weak self] response in
            guard response == .alertFirstButtonReturn else { return }
            let name = field.stringValue.trimmingCharacters(in: .whitespacesAndNewlines)
            guard !name.isEmpty else { return }
            Task { @MainActor [weak self] in
                guard let self = self else { return }
                do {
                    _ = try await ws.updateSidebarCategory(
                        teamId: team.id,
                        userId: userId,
                        categoryId: categoryId,
                        displayName: name
                    )
                    self.refreshSidebarCategories()
                } catch {
                    self.showInfoAlert("Could not rename the category: \(error.localizedDescription)")
                }
            }
        }
    }

    @objc private func deleteSidebarCategoryMenuSelected(_ sender: NSMenuItem) {
        guard let categoryId = sender.representedObject as? String,
            let ws = webService, ws.isLogged(),
            let team = activeTeam,
            let userId = currentCategoryUserId()
        else { return }
        let alert = NSAlert()
        alert.messageText = "Delete category?"
        alert.informativeText = "Channels in this category remain in the sidebar."
        alert.addButton(withTitle: "Delete")
        alert.addButton(withTitle: "Cancel")
        alert.beginSheetModal(for: self) { [weak self] response in
            guard response == .alertFirstButtonReturn else { return }
            Task { @MainActor [weak self] in
                guard let self = self else { return }
                do {
                    try await ws.deleteSidebarCategory(
                        teamId: team.id,
                        userId: userId,
                        categoryId: categoryId
                    )
                    self.refreshSidebarCategories()
                } catch {
                    self.showInfoAlert("Could not delete the category: \(error.localizedDescription)")
                }
            }
        }
    }

    @objc private func moveSidebarCategoryUp(_ sender: NSMenuItem) {
        guard let categoryId = sender.representedObject as? String else { return }
        moveSidebarCategory(categoryId, offset: -1)
    }

    @objc private func moveSidebarCategoryDown(_ sender: NSMenuItem) {
        guard let categoryId = sender.representedObject as? String else { return }
        moveSidebarCategory(categoryId, offset: 1)
    }

    func moveSidebarCategory(_ categoryId: String, offset: Int) {
        guard let ws = webService, ws.isLogged(),
            let team = activeTeam,
            let userId = currentCategoryUserId()
        else { return }
        let displayedIds =
            sidebarCategories
            .map(\.id)
            .filter { !$0.lowercased().contains("favorites") }
        guard let displayedIndex = displayedIds.firstIndex(of: categoryId) else { return }
        let targetDisplayedIndex = displayedIndex + offset
        guard displayedIds.indices.contains(targetDisplayedIndex) else { return }
        let targetId = displayedIds[targetDisplayedIndex]
        guard let sourceIndex = sidebarCategoryOrderIds.firstIndex(of: categoryId),
            let targetIndex = sidebarCategoryOrderIds.firstIndex(of: targetId)
        else { return }
        var order = sidebarCategoryOrderIds
        order.swapAt(sourceIndex, targetIndex)
        sidebarCategoryOrderIds = order
        Task { @MainActor [weak self] in
            guard let self = self else { return }
            do {
                try await ws.updateSidebarCategoryOrder(
                    teamId: team.id,
                    userId: userId,
                    categoryIds: order
                )
                self.refreshSidebarCategories()
            } catch {
                self.showInfoAlert("Could not reorder categories: \(error.localizedDescription)")
                self.refreshSidebarCategories()
            }
        }
    }

    func wireCategoryAddChannelButton(_ category: SidebarCategoryView) {
        guard let button = category.addButton else { return }
        button.onClick = { [weak self, weak button] in
            guard let self = self, let button = button else { return }
            self.showAddChannelMenu(categoryId: category.id, anchor: button)
        }
        button.accessibilityTitle = "Add channel to category"
    }

    @objc private func addChannelToCategoryMenuSelected(_ sender: NSMenuItem) {
        guard let categoryId = sender.representedObject as? String else { return }
        showAddChannelMenu(categoryId: categoryId, anchor: nil)
    }

    func showAddChannelMenu(categoryId: String, anchor: NSView?) {
        guard let category = sidebarCategories.first(where: { $0.id == categoryId })
        else { return }
        let existing = Set(category.items.map(\.id))
        let candidates = channelsById.values
            .filter { !existing.contains($0.id) }
            .sorted {
                channelDisplayName(for: $0)
                    .localizedCaseInsensitiveCompare(channelDisplayName(for: $1)) == .orderedAscending
            }
        guard !candidates.isEmpty else { return }

        let menu = NSMenu()
        for channel in candidates {
            let item = NSMenuItem(
                title: channelDisplayName(for: channel),
                action: #selector(addChannelChoiceSelected(_:)),
                keyEquivalent: ""
            )
            item.target = self
            item.representedObject = [categoryId, channel.id]
            menu.addItem(item)
        }
        if let anchor = anchor {
            menu.popUp(
                positioning: nil,
                at: NSPoint(x: 0, y: anchor.bounds.height + 2),
                in: anchor
            )
        } else if let header = category.headerRow.window {
            let point = category.headerRow.convert(
                NSPoint(x: category.headerRow.bounds.width - 12, y: 4),
                to: nil
            )
            let screenPoint = header.convertPoint(toScreen: point)
            menu.popUp(positioning: nil, at: screenPoint, in: nil)
        }
    }

    @objc private func addChannelChoiceSelected(_ sender: NSMenuItem) {
        guard let ids = sender.representedObject as? [String],
            ids.count == 2,
            let ws = webService, ws.isLogged(),
            let team = activeTeam,
            let userId = currentCategoryUserId()
        else { return }
        let categoryId = ids[0]
        let channelId = ids[1]
        Task { @MainActor [weak self] in
            guard let self = self else { return }
            do {
                try await ws.addChannelToSidebarCategory(
                    teamId: team.id,
                    userId: userId,
                    categoryId: categoryId,
                    channelId: channelId
                )
                self.refreshSidebarCategories()
            } catch {
                self.showInfoAlert("Could not add the channel: \(error.localizedDescription)")
            }
        }
    }

    func persistSidebarCategoryCollapsed(_ collapsed: Bool, categoryId: String) {
        guard let ws = webService, ws.isLogged(),
            let team = activeTeam,
            let userId = currentCategoryUserId()
        else { return }
        Task { @MainActor in
            _ = try? await ws.updateSidebarCategory(
                teamId: team.id,
                userId: userId,
                categoryId: categoryId,
                collapsed: collapsed
            )
        }
    }
}
