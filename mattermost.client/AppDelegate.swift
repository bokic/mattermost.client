import Cocoa
import os

final class AppDelegate: NSObject, NSApplicationDelegate {
    var mainWindow: MainWindow!
    var loginWindow: LoginWindow!
    var statusBarItem: NSStatusItem!
    var statusBarMenu: NSMenu!
    var webService = webservice()
    private weak var zoomPercentMenuItem: NSMenuItem?
    
    func applicationDidFinishLaunching(_ aNotification: Notification) {
        setupMainMenu()
        
        let statusBar = NSStatusBar.system
        statusBarItem = statusBar.statusItem(withLength: NSStatusItem.squareLength)
        statusBarItem.button?.image = NSImage(named: NSImage.Name("MenuIcon16"))
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
        mainWindow = MainWindow(
            contentRect: NSRect(x: 0, y: 0, width: 1200, height: 800),
            styleMask: [.miniaturizable, .closable, .resizable, .titled],
            backing: .buffered, defer: false)
        webService.connectWebSocket()
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
