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
                    NSLog("Calling checkToken webservice: \(host):\(port)")
                    self.webService = WebService(host: host, port: port)
                    Task { @MainActor in
                        let isValid = await self.webService.checkToken(token: token)
                        if isValid {
                            NSLog("Token is valid, showing main window")
                            self.showMainWindow()
                        } else {
                            NSLog("Token is invalid, trying login")
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
        guard event.window != nil else { return event }
        
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
            NSLog("Calling login webservice: \(username)@\(host):\(port)")
            webService = WebService(host: host, port: port)
            Task { @MainActor in
                do {
                    _ = try await webService.login(username: username, password: password)
                    if let token = webService.token() {
                        KeychainHelper.set(token, forKey: "token")
                    }
                    NSLog("Login successful, showing main window")
                    showMainWindow()
                } catch {
                    let message = error.localizedDescription
                    NSLog("Login failed: \(message)")
                    showLoginWindow()
                    loginWindow?.errorLabel.stringValue = message
                }
            }
        } else {
            NSLog("No credentials found, showing login window")
            showLoginWindow()
        }
    }

    @objc func websocketConnected(isConnected: NSNumber) {
        let isConnected = isConnected.boolValue
        let logger = Logger()
        
        logger.info("called websocketConnected(\(isConnected))")
    }
    
    // MARK: - Unread badges & notifications
    
    private func configureNotifications() {
        let center = UNUserNotificationCenter.current()
        center.delegate = self
        center.requestAuthorization(options: [.alert, .sound, .badge]) { granted, error in
            if let error = error {
                NSLog("Notification authorization failed: \(error.localizedDescription)")
            } else if !granted {
                NSLog("Notification authorization was denied")
            }
        }
    }
    
    /// Records an unread message for a channel, updates the menu-bar/dock badges
    /// and posts a macOS notification.
    func noteIncomingMessage(channelId: String, channelName: String, author: String, body: String) {
        guard !channelId.isEmpty else { return }
        unreadCounts[channelId, default: 0] += 1
        updateUnreadIndicators()
        postNotification(channelId: channelId, channelName: channelName, author: author, body: body)
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
    
    private func postNotification(channelId: String, channelName: String, author: String, body: String) {
        let content = UNMutableNotificationContent()
        content.title = channelName.isEmpty ? "Mattermost" : channelName
        content.subtitle = author
        content.body = body
        content.sound = .default
        content.threadIdentifier = channelId
        content.userInfo = ["channelId": channelId]
        
        let identifier = UUID().uuidString
        notificationIds[channelId, default: []].append(identifier)
        let request = UNNotificationRequest(identifier: identifier, content: content, trigger: nil)
        UNUserNotificationCenter.current().add(request) { error in
            if let error = error {
                NSLog("Failed to post notification: \(error.localizedDescription)")
            }
        }
    }
    
    func userNotificationCenter(
        _ center: UNUserNotificationCenter,
        willPresent notification: UNNotification,
        withCompletionHandler completionHandler: @escaping (UNNotificationPresentationOptions) -> Void
    ) {
        completionHandler([.banner, .sound, .list])
    }
    
    func userNotificationCenter(
        _ center: UNUserNotificationCenter,
        didReceive response: UNNotificationResponse,
        withCompletionHandler completionHandler: @escaping () -> Void
    ) {
        if let channelId = response.notification.request.content.userInfo["channelId"] as? String {
            DispatchQueue.main.async {
                NSApp.activate(ignoringOtherApps: true)
                self.mainWindow?.openChannel(withId: channelId)
            }
        }
        completionHandler()
    }
    
    func showMainWindow() {
        guard mainWindow == nil else {
            createMainWindow()
            return
        }
        let service = webService
        Task { @MainActor [weak self] in
            guard let self = self else { return }
            var teamId: String?
            if let me = try? await service.fetchCurrentUser(),
               let preferences = try? await service.fetchUserPreferences(userId: me.id) {
                if let teams = try? await service.fetchTeams() {
                    teamId = teams.first?.id
                }
                ThemeManager.shared.apply(preferences: preferences, teamId: teamId)
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
        UserDefaults.standard.removeObject(forKey: "username")
        UserDefaults.standard.removeObject(forKey: "currentUserId")
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
        
        NSApp.mainMenu = mainMenu
        NSApp.windowsMenu = windowMenu
        
        NotificationCenter.default.addObserver(self, selector: #selector(zoomFactorChangedNotification(_:)), name: .zoomFactorDidChange, object: nil)
    }
    
    @objc private func systemDidWake() {
        webService.reconnectIfNeeded()
    }
    
    @objc func focusGlobalSearch() {
        mainWindow?.focusGlobalSearch()
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
