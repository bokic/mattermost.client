import Cocoa
import os

final class AppDelegate: NSObject, NSApplicationDelegate {
    var mainWindow: MainWindow!
    var loginWindow: LoginWindow!
    var statusBarItem: NSStatusItem!
    var statusBarMenu: NSMenu!
    var webService = webservice()
    private weak var zoomPercentMenuItem: NSMenuItem?
    private var zoomGestureStartFactor: CGFloat?
    private var zoomGestureMagnification: CGFloat = 0
    private var zoomGestureMonitor: Any?
    
    func applicationDidFinishLaunching(_ aNotification: Notification) {
        DebugLog.log("AppDelegate: applicationDidFinishLaunching. Log path: \(DebugLog.logPath)")
        setupMainMenu()
        installZoomGestureMonitor()
        
        let statusBar = NSStatusBar.system
        statusBarItem = statusBar.statusItem(withLength: NSStatusItem.squareLength)
        let icon = NSImage(named: NSImage.Name("MenuIcon16"))
        icon?.isTemplate = true
        statusBarItem.button?.image = icon
        statusBarItem.button?.target = self
        statusBarItem.button?.action = #selector(AppDelegate.statusBarButtonClicked(_:))
        statusBarItem.button?.sendAction(on: [.leftMouseUp, .rightMouseUp])
        
        statusBarMenu = NSMenu(title: "Cap Status Bar Menu")
        
        statusBarMenu.addItem(
            withTitle: "Quit app",
            action: #selector(AppDelegate.quitApp),
            keyEquivalent: "")
        
        let userSettings = UserDefaults.standard
        
        let host = userSettings.string(forKey: "host")
        let port = UInt16(userSettings.integer(forKey: "port"))
        let token = KeychainHelper.get(forKey: "token")

        if let host = host, !host.isEmpty, port > 0, let token = token, !token.isEmpty {
            NSLog("Calling checkToken webservice: \(host):\(port)")
            webService = WebService(host: host, port: port)
            Task { @MainActor in
                let isValid = await webService.checkToken(token: token)
                let logger = Logger()
                logger.info("called checkTokenResult(\(isValid))")
                if isValid {
                    NSLog("Token is valid, showing main window")
                    showMainWindow()
                } else {
                    NSLog("Token is invalid, trying login")
                    tryLoginWithStoredCredentials()
                }
            }
        } else {
            tryLoginWithStoredCredentials()
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
        let userSettings = UserDefaults.standard

        let host = userSettings.string(forKey: "host")
        let port = UInt16(userSettings.integer(forKey: "port"))
        let username = userSettings.string(forKey: "username")
        let password = KeychainHelper.get(forKey: "password")

        if let host = host, !host.isEmpty, port > 0, let username = username, !username.isEmpty, let password = password, !password.isEmpty {
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
    
    func showMainWindow() {
        loginWindow?.close()
        loginWindow = nil
        // Default to the web client's viewport (1440x783), clamped to the screen.
        // A previously saved window frame (autosave) takes precedence on restore.
        let visible = NSScreen.main?.visibleFrame.size ?? NSSize(width: 1440, height: 900)
        let defaultWidth = min(1440, visible.width)
        let defaultHeight = min(783, max(480, visible.height - 28))
        mainWindow = MainWindow(
            contentRect: NSRect(x: 0, y: 0, width: defaultWidth, height: defaultHeight),
            styleMask: [.miniaturizable, .closable, .resizable, .titled],
            backing: .buffered, defer: false)
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
