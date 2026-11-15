import Cocoa
import os
import UserNotifications

@MainActor
final class AppDelegate: NSObject, NSApplicationDelegate, @preconcurrency UNUserNotificationCenterDelegate {
    var mainWindow: MainWindow!
    var loginWindow: LoginWindow!
    var statusBarItem: NSStatusItem!
    var statusBarMenu: NSMenu!
    var webService = webservice()
    private weak var zoomPercentMenuItem: NSMenuItem?
    private var zoomGestureStartFactor: CGFloat?
    private var zoomGestureMagnification: CGFloat = 0
    private var zoomGestureMonitor: Any?
    private var unreadCounts: [String: Int] = [:]
    private var notificationIds: [String: [String]] = [:]
    
    func applicationDidFinishLaunching(_ aNotification: Notification) {
        DebugLog.info("AppDelegate: applicationDidFinishLaunching. Log path: \(DebugLog.logPath)")
        KeychainHelper.migrateLegacyCredentials()
        DebugLog.info("Credentials: \(KeychainHelper.usesDebugCredentialStore ? "debug UserDefaults store (plaintext)" : "macOS Keychain")")
        setupMainMenu()
        installZoomGestureMonitor()
        DistributedNotificationCenter.default().addObserver(
            forName: Notification.Name("AppleInterfaceThemeChangedNotification"),
            object: nil,
            queue: .main
        ) { [weak self] _ in
            guard ThemeManager.shared.usesSystemAppearance else { return }
            ThemeManager.shared.reapply()
            self?.mainWindow?.refreshServerTheme(teamId: self?.mainWindow?.activeTeam?.id)
        }
        NSWorkspace.shared.notificationCenter.addObserver(
            self,
            selector: #selector(systemDidWake),
            name: NSWorkspace.didWakeNotification,
            object: nil
        )
        
        let statusBar = NSStatusBar.system
        statusBarItem = statusBar.statusItem(withLength: NSStatusItem.variableLength)
        let icon = NSImage(named: NSImage.Name("MenuIcon16"))
        icon?.isTemplate = true
        statusBarItem.button?.image = icon
        statusBarItem.button?.imagePosition = .imageLeft
        configureNotifications()
        statusBarItem.button?.target = self
        statusBarItem.button?.action = #selector(AppDelegate.statusBarButtonClicked(_:))
        statusBarItem.button?.sendAction(on: [.leftMouseUp, .rightMouseUp])
        
        statusBarMenu = NSMenu(title: "Cap Status Bar Menu")
        
        statusBarMenu.addItem(
            withTitle: "Quit app",
            action: #selector(AppDelegate.quitApp),
            keyEquivalent: "")
        
        startAuthentication()
    }

    func applicationShouldHandleReopen(_ sender: NSApplication, hasVisibleWindows flag: Bool) -> Bool {
        guard !flag else { return true }
        if mainWindow != nil {
            showMainWindow()
        } else if let loginWindow = loginWindow {
            loginWindow.makeKeyAndOrderFront(nil)
        }
        return true
    }
    
    /// Reads credentials off the main thread: Keychain access can block while the
    /// system shows an authorization prompt, which must not stall app launch.
    /// The password item is only read when the cached token is missing or invalid,
    /// so a valid session never triggers an unnecessary Keychain prompt.
    private func startAuthentication() {
        let userSettings = UserDefaults.standard
        let host = userSettings.string(forKey: "host")
        let port = UInt16(userSettings.integer(forKey: "port"))
        
        Task.detached { [weak self] in
            let token = KeychainHelper.get(forKey: "token")
            await MainActor.run { [weak self] in
                guard let self = self else { return }
                if let host = host, !host.isEmpty, let token = token, !token.isEmpty {
                    DebugLog.info("Checking saved session token")
                    self.webService = WebService(host: host, port: port)
                    Task { @MainActor in
                        let isValid = await self.webService.checkToken(token: token)
                        if isValid {
                            DebugLog.info("Saved session token is valid")
                            self.showMainWindow()
                        } else {
                            DebugLog.info("Saved session token was rejected")
                            self.loginWithStoredPassword(host: host, port: port)
                        }
                    }
                } else {
                    self.loginWithStoredPassword(host: host, port: port)
                }
            }
        }
    }

    /// Loads the stored password off the main thread and then attempts a login.
    private func loginWithStoredPassword(host: String?, port: UInt16) {
        Task.detached { [weak self] in
            let password = KeychainHelper.get(forKey: "password")
            await MainActor.run { [weak self] in
                self?.loginWithStoredCredentials(host: host, port: port, password: password)
            }
        }
    }
    
    // MARK: - Zoom Gestures
    
    /// Pinch-to-zoom on the trackpad and Command+scroll wheel change the UI zoom,
    /// matching browser behaviour.
    private func installZoomGestureMonitor() {
        zoomGestureMonitor = NSEvent.addLocalMonitorForEvents(matching: [.magnify, .scrollWheel]) { [weak self] event in
            guard let self = self else { return event }
            return self.handleZoomGesture(event)
        }
    }
    
    private func handleZoomGesture(_ event: NSEvent) -> NSEvent? {
        guard let eventWindow = event.window,
              eventWindow === mainWindow || eventWindow === loginWindow else { return event }
        
        if event.type == .magnify {
            switch event.phase {
            case .began:
                zoomGestureStartFactor = ZoomManager.shared.currentZoomFactor
                zoomGestureMagnification = 0
            case .ended, .cancelled:
                zoomGestureStartFactor = nil
                zoomGestureMagnification = 0
            default:
                if zoomGestureStartFactor == nil {
                    zoomGestureStartFactor = ZoomManager.shared.currentZoomFactor
                    zoomGestureMagnification = 0
                }
                zoomGestureMagnification += event.magnification
                if let base = zoomGestureStartFactor, zoomGestureMagnification != 0 {
                    ZoomManager.shared.setZoomFactor(base * (1 + zoomGestureMagnification))
                }
            }
            return nil
        }
        
        if event.type == .scrollWheel, event.modifierFlags.contains(.command) {
            let delta = event.scrollingDeltaY
            guard abs(delta) > 0.01 else { return nil }
            // Precise trackpad deltas are small and frequent; wheel notches are coarse.
            let step = event.hasPreciseScrollingDeltas ? delta * 0.004 : delta * 0.05
            ZoomManager.shared.setZoomFactor(ZoomManager.shared.currentZoomFactor * (1 + step))
            return nil
        }
        
        return event
    }
    
    func tryLoginWithStoredCredentials() {
        loginWithStoredPassword(
            host: UserDefaults.standard.string(forKey: "host"),
            port: UInt16(UserDefaults.standard.integer(forKey: "port"))
        )
    }
    
    private func loginWithStoredCredentials(host: String?, port: UInt16, password: String?) {
        let userSettings = UserDefaults.standard
        let username = userSettings.string(forKey: "username")

        if let host = host, !host.isEmpty, let username = username, !username.isEmpty, let password = password, !password.isEmpty {
            DebugLog.info("Attempting password login")
            webService = WebService(host: host, port: port)
            Task { @MainActor in
                do {
                    _ = try await webService.login(username: username, password: password)
                    if let token = webService.token() {
                        KeychainHelper.set(token, forKey: "token")
                    }
                    DebugLog.info("Password login succeeded")
                    showMainWindow()
                } catch {
                    let message = error.localizedDescription
                    DebugLog.error("Password login failed: \(message)")
                    showLoginWindow()
                    loginWindow?.errorLabel.stringValue = message
                }
            }
        } else {
            DebugLog.info("No saved credentials; showing login window")
            showLoginWindow()
        }
    }

    // MARK: - Unread badges & notifications
    
    private func configureNotifications() {
        let center = UNUserNotificationCenter.current()
        center.delegate = self
        center.requestAuthorization(options: [.alert, .sound, .badge]) { granted, error in
            if let error = error {
                DebugLog.error("Notification authorization failed: \(error.localizedDescription)")
            } else if !granted {
                DebugLog.warning("Notification authorization was denied")
            }
        }
    }
    
    /// Records an unread message for a channel, updates the menu-bar/dock badges
    /// and optionally posts a macOS notification.
    func noteIncomingMessage(
        channelId: String,
        channelName: String,
        author: String,
        body: String,
        notify: Bool = true,
        sound: Bool = true,
        postId: String? = nil,
        rootId: String? = nil
    ) {
        guard !channelId.isEmpty else { return }
        unreadCounts[channelId, default: 0] += 1
        updateUnreadIndicators()
        if notify {
            postNotification(
                channelId: channelId,
                channelName: channelName,
                author: author,
                body: body,
                sound: sound,
                postId: postId,
                rootId: rootId
            )
        }
    }
    
    /// Replaces the in-memory unread map with server-backed membership counts so
    /// the Dock/menu-bar badge survives relaunch and stays in sync with the sidebar.
    func syncUnreadCounts(_ counts: [String: Int]) {
        unreadCounts = counts.filter { $0.value > 0 }
        updateUnreadIndicators()
    }

    /// Clears the unread state (and delivered notifications) for one channel.
    func markChannelRead(_ channelId: String) {
        guard unreadCounts.removeValue(forKey: channelId) != nil else { return }
        if let ids = notificationIds.removeValue(forKey: channelId), !ids.isEmpty {
            UNUserNotificationCenter.current().removeDeliveredNotifications(withIdentifiers: ids)
        }
        updateUnreadIndicators()
    }
    
    var totalUnreadCount: Int {
        unreadCounts.values.reduce(0, +)
    }
    
    private func updateUnreadIndicators() {
        let total = totalUnreadCount
        if total > 0 {
            statusBarItem.button?.attributedTitle = NSAttributedString(
                string: " •",
                attributes: [
                    .foregroundColor: NSColor.systemBlue,
                    .font: NSFont.systemFont(ofSize: 14, weight: .bold)
                ]
            )
            statusBarItem.button?.toolTip = "\(total) unread message\(total == 1 ? "" : "s")"
            NSApp.dockTile.badgeLabel = total > 99 ? "99+" : "\(total)"
        } else {
            statusBarItem.button?.attributedTitle = NSAttributedString(string: "")
            statusBarItem.button?.toolTip = "Mattermost"
            NSApp.dockTile.badgeLabel = ""
        }
    }
    
    private func postNotification(
        channelId: String,
        channelName: String,
        author: String,
        body: String,
        sound: Bool,
        postId: String? = nil,
        rootId: String? = nil
    ) {
        let content = UNMutableNotificationContent()
        content.title = channelName.isEmpty ? "Mattermost" : channelName
        content.subtitle = author
        content.body = body
        content.sound = sound ? .default : nil
        content.threadIdentifier = channelId
        var userInfo: [String: String] = ["channelId": channelId]
        if let postId = postId, !postId.isEmpty { userInfo["postId"] = postId }
        if let rootId = rootId, !rootId.isEmpty { userInfo["rootId"] = rootId }
        content.userInfo = userInfo
        
        let identifier = UUID().uuidString
        notificationIds[channelId, default: []].append(identifier)
        let request = UNNotificationRequest(identifier: identifier, content: content, trigger: nil)
        UNUserNotificationCenter.current().add(request) { error in
            if let error = error {
                DebugLog.error("Failed to post notification: \(error.localizedDescription)")
            }
        }
    }
    
    func userNotificationCenter(
        _ center: UNUserNotificationCenter,
        willPresent notification: UNNotification,
        withCompletionHandler completionHandler: @escaping (UNNotificationPresentationOptions) -> Void
    ) {
        var options: UNNotificationPresentationOptions = [.banner, .list]
        if notification.request.content.sound != nil { options.insert(.sound) }
        completionHandler(options)
    }
    
    func userNotificationCenter(
        _ center: UNUserNotificationCenter,
        didReceive response: UNNotificationResponse,
        withCompletionHandler completionHandler: @escaping () -> Void
    ) {
        if let channelId = response.notification.request.content.userInfo["channelId"] as? String {
            let postId = response.notification.request.content.userInfo["postId"] as? String
            let rootId = response.notification.request.content.userInfo["rootId"] as? String
            DispatchQueue.main.async {
                NSApp.activate(ignoringOtherApps: true)
                guard let mainWindow = self.mainWindow else { return }
                mainWindow.openChannel(withId: channelId)
                if let rootId = rootId, !rootId.isEmpty {
                    Task { @MainActor in
                        guard let post = try? await self.webService.fetchPost(postId: rootId) else { return }
                        self.mainWindow?.showThread(for: post)
                    }
                } else if let postId = postId, !postId.isEmpty {
                    mainWindow.pendingJumpPostId = postId
                }
            }
        }
        completionHandler()
    }
    
    func showMainWindow() {
        guard mainWindow == nil else {
            if let window = mainWindow {
                if window.isMiniaturized { window.deminiaturize(nil) }
                window.makeKeyAndOrderFront(nil)
            }
            return
        }
        let service = webService
        Task { @MainActor [weak self] in
            guard let self = self else { return }
            var teamId: String?
            if let me = try? await service.fetchCurrentUser(),
               let preferences = try? await service.fetchUserPreferences(userId: me.id) {
                if let teams = try? await service.fetchTeams() {
                    let savedTeamId = UserDefaults.standard.string(forKey: "lastTeamId")
                    teamId = teams.first(where: { $0.id == savedTeamId })?.id ?? teams.first?.id
                }
                ThemeManager.shared.apply(preferences: preferences, teamId: teamId)
                if ThemeManager.shared.usesSystemAppearance {
                    NSApp.appearance = nil
                } else {
                    NSApp.appearance = NSAppearance(named: ThemeManager.shared.theme.isDark ? .darkAqua : .aqua)
                }
            }
            self.createMainWindow()
        }
    }

    private func createMainWindow() {
        guard mainWindow == nil else { return }
        loginWindow?.close()
        loginWindow = nil
        // Default to the web client's viewport (1440x783), clamped to the screen.
        // A previously saved window frame (autosave) takes precedence on restore.
        let visible = NSScreen.main?.visibleFrame.size ?? NSSize(width: 1440, height: 900)
        let defaultWidth = min(1440, visible.width)
        let defaultHeight = min(783, max(480, visible.height - 28))
        let window = MainWindow(
            contentRect: NSRect(x: 0, y: 0, width: defaultWidth, height: defaultHeight),
            styleMask: [.miniaturizable, .closable, .resizable, .titled],
            backing: .buffered, defer: false)
        mainWindow = window
        window.start(with: webService)
        webService.connectWebSocket()
    }
    
    /// Clears stored credentials and returns to the login screen.
    func logout() {
        webService.disconnectWebSocket()
        KeychainHelper.delete(forKey: "token")
        KeychainHelper.delete(forKey: "password")
        let defaults = UserDefaults.standard
        for key in [
            "username", "currentUserId", "lastTeamId", "lastChannelId",
            "customStatusEmoji", "customStatusText", "customStatusExpiresAt",
            "recentEmojis", "rememberPassword"
        ] {
            defaults.removeObject(forKey: key)
        }
        unreadCounts.removeAll()
        notificationIds.removeAll()
        UNUserNotificationCenter.current().removeAllDeliveredNotifications()
        updateUnreadIndicators()
        mainWindow?.close()
        mainWindow = nil
        showLoginWindow()
    }
    
    func showLoginWindow() {
        mainWindow?.close()
        mainWindow = nil
        loginWindow = LoginWindow(
            contentRect: NSRect(x: 0, y: 0, width: 640, height: 480),
            styleMask: [.miniaturizable, .closable, .resizable, .titled],
            backing: .buffered, defer: false)
    }
    
    @objc func statusBarButtonClicked(_ sender: NSStatusBarButton) {
        if let event = NSApp.currentEvent,
           event.type == .rightMouseUp || event.modifierFlags.contains(.control) {
            statusBarItem.menu = statusBarMenu
            statusBarItem.button?.performClick(nil)
            statusBarItem.menu = nil
            return
        }
        
        toggleMainWindow()
    }
    
    func toggleMainWindow() {
        guard let window = mainWindow ?? loginWindow else { return }
        
        if window.isVisible && !window.isMiniaturized {
            window.orderOut(nil)
        } else {
            if window.isMiniaturized {
                window.deminiaturize(nil)
            }
            NSApp.activate(ignoringOtherApps: true)
            window.makeKeyAndOrderFront(nil)
        }
    }
    
    @objc func quitApp() {
        if let monitor = zoomGestureMonitor {
            NSEvent.removeMonitor(monitor)
            zoomGestureMonitor = nil
        }
        app.terminate(self)
    }
    
    // MARK: - Main Menu & Zoom Actions
    
    private func setupMainMenu() {
        let mainMenu = NSMenu()
        
        // App Menu
        let appMenuItem = NSMenuItem()
        mainMenu.addItem(appMenuItem)
        let appMenu = NSMenu()
        appMenuItem.submenu = appMenu
        appMenu.addItem(withTitle: "About Mattermost", action: #selector(NSApplication.orderFrontStandardAboutPanel(_:)), keyEquivalent: "")
        appMenu.addItem(NSMenuItem.separator())
        let preferencesItem = NSMenuItem(title: "Settings…", action: #selector(AppDelegate.showPreferences), keyEquivalent: ",")
        preferencesItem.target = self
        appMenu.addItem(preferencesItem)
        appMenu.addItem(NSMenuItem.separator())
        let servicesItem = NSMenuItem(title: "Services", action: nil, keyEquivalent: "")
        let servicesMenu = NSMenu(title: "Services")
        servicesItem.submenu = servicesMenu
        appMenu.addItem(servicesItem)
        NSApp.servicesMenu = servicesMenu
        appMenu.addItem(NSMenuItem.separator())
        appMenu.addItem(withTitle: "Hide Mattermost", action: #selector(NSApplication.hide(_:)), keyEquivalent: "h")
        let hideOthers = NSMenuItem(title: "Hide Others", action: #selector(NSApplication.hideOtherApplications(_:)), keyEquivalent: "h")
        hideOthers.keyEquivalentModifierMask = [.command, .option]
        appMenu.addItem(hideOthers)
        appMenu.addItem(withTitle: "Show All", action: #selector(NSApplication.unhideAllApplications(_:)), keyEquivalent: "")
        appMenu.addItem(NSMenuItem.separator())
        appMenu.addItem(withTitle: "Quit Mattermost", action: #selector(AppDelegate.quitApp), keyEquivalent: "q")
        
        // Edit Menu (Standard text editing shortcuts)
        let editMenuItem = NSMenuItem()
        mainMenu.addItem(editMenuItem)
        let editMenu = NSMenu(title: "Edit")
        editMenuItem.submenu = editMenu
        editMenu.addItem(withTitle: "Undo", action: #selector(UndoManager.undo), keyEquivalent: "z")
        editMenu.addItem(withTitle: "Redo", action: #selector(UndoManager.redo), keyEquivalent: "Z")
        editMenu.addItem(NSMenuItem.separator())
        editMenu.addItem(withTitle: "Cut", action: #selector(NSText.cut(_:)), keyEquivalent: "x")
        editMenu.addItem(withTitle: "Copy", action: #selector(NSText.copy(_:)), keyEquivalent: "c")
        editMenu.addItem(withTitle: "Paste", action: #selector(NSText.paste(_:)), keyEquivalent: "v")
        editMenu.addItem(withTitle: "Select All", action: #selector(NSText.selectAll(_:)), keyEquivalent: "a")
        editMenu.addItem(NSMenuItem.separator())

        let searchItem = NSMenuItem(title: "Search", action: #selector(AppDelegate.focusGlobalSearch), keyEquivalent: "k")
        searchItem.target = self
        searchItem.keyEquivalentModifierMask = [.command]
        editMenu.addItem(searchItem)

        let findChannelItem = NSMenuItem(title: "Find in Channel", action: #selector(AppDelegate.focusChannelSearch), keyEquivalent: "f")
        findChannelItem.target = self
        findChannelItem.keyEquivalentModifierMask = [.command]
        editMenu.addItem(findChannelItem)
        
        // View Menu (Zoom In, Zoom Out, Actual Size)
        let viewMenuItem = NSMenuItem()
        mainMenu.addItem(viewMenuItem)
        let viewMenu = NSMenu(title: "View")
        viewMenuItem.submenu = viewMenu
        
        let zoomInItem = NSMenuItem(title: "Zoom In", action: #selector(AppDelegate.zoomInAction), keyEquivalent: "=")
        zoomInItem.keyEquivalentModifierMask = [.command]
        
        let zoomInShiftItem = NSMenuItem(title: "Zoom In", action: #selector(AppDelegate.zoomInAction), keyEquivalent: "+")
        zoomInShiftItem.keyEquivalentModifierMask = [.command]
        zoomInShiftItem.isAlternate = true
        
        let zoomOutItem = NSMenuItem(title: "Zoom Out", action: #selector(AppDelegate.zoomOutAction), keyEquivalent: "-")
        zoomOutItem.keyEquivalentModifierMask = [.command]
        
        let actualSizeItem = NSMenuItem(title: "Actual Size", action: #selector(AppDelegate.zoomActualSizeAction), keyEquivalent: "0")
        actualSizeItem.keyEquivalentModifierMask = [.command]
        
        let currentPct = Int(round(ZoomManager.shared.currentZoomFactor * 100))
        let zoomStatusItem = NSMenuItem(title: "Zoom: \(currentPct)%", action: nil, keyEquivalent: "")
        zoomStatusItem.isEnabled = false
        self.zoomPercentMenuItem = zoomStatusItem
        
        viewMenu.addItem(zoomInItem)
        viewMenu.addItem(zoomInShiftItem)
        viewMenu.addItem(zoomOutItem)
        viewMenu.addItem(NSMenuItem.separator())
        viewMenu.addItem(actualSizeItem)
        viewMenu.addItem(NSMenuItem.separator())
        viewMenu.addItem(zoomStatusItem)
        
        // Window Menu
        let windowMenuItem = NSMenuItem()
        mainMenu.addItem(windowMenuItem)
        let windowMenu = NSMenu(title: "Window")
        windowMenuItem.submenu = windowMenu
        windowMenu.addItem(withTitle: "Minimize", action: #selector(NSWindow.miniaturize(_:)), keyEquivalent: "m")
        windowMenu.addItem(withTitle: "Zoom", action: #selector(NSWindow.performZoom(_:)), keyEquivalent: "")
        windowMenu.addItem(NSMenuItem.separator())
        windowMenu.addItem(withTitle: "Close", action: #selector(NSWindow.performClose(_:)), keyEquivalent: "w")

        // Help Menu
        let helpMenuItem = NSMenuItem()
        mainMenu.addItem(helpMenuItem)
        let helpMenu = NSMenu(title: "Help")
        helpMenuItem.submenu = helpMenu
        let docsItem = NSMenuItem(title: "Mattermost Help", action: #selector(AppDelegate.openHelp), keyEquivalent: "?")
        docsItem.target = self
        helpMenu.addItem(docsItem)

        NSApp.mainMenu = mainMenu
        NSApp.windowsMenu = windowMenu
        NSApp.helpMenu = helpMenu
        
        NotificationCenter.default.addObserver(self, selector: #selector(zoomFactorChangedNotification(_:)), name: .zoomFactorDidChange, object: nil)
    }
    
    @objc private func systemDidWake() {
        webService.reconnectIfNeeded()
    }
    
    @objc func focusGlobalSearch() {
        mainWindow?.focusGlobalSearch()
    }

    @objc func showPreferences() {
        if let mainWindow = mainWindow {
            NSApp.activate(ignoringOtherApps: true)
            mainWindow.makeKeyAndOrderFront(nil)
            mainWindow.showRightPanel(mode: .settings)
        } else if let loginWindow = loginWindow {
            NSApp.activate(ignoringOtherApps: true)
            loginWindow.makeKeyAndOrderFront(nil)
        }
    }

    @objc func openHelp() {
        if let url = URL(string: "https://docs.mattermost.com/") {
            NSWorkspace.shared.open(url)
        }
    }

    @objc func focusChannelSearch() {
        mainWindow?.focusChannelSearch()
    }

    @objc func zoomInAction() {
        ZoomManager.shared.zoomIn()
    }
    
    @objc func zoomOutAction() {
        ZoomManager.shared.zoomOut()
    }
    
    @objc func zoomActualSizeAction() {
        ZoomManager.shared.resetZoom()
    }
    
    @objc private func zoomFactorChangedNotification(_ notification: Notification) {
        let pct = Int(round(ZoomManager.shared.currentZoomFactor * 100))
        zoomPercentMenuItem?.title = "Zoom: \(pct)%"
    }
}
