//
//  LoginWindow.swift
//  mattermost.client
//
//  Created by Boris Barbulovski on 31.10.24.
//

import Cocoa

private class LoginWindowViewController: NSViewController {
    weak var loginWindow: LoginWindow?

    init(loginWindow: LoginWindow) {
        self.loginWindow = loginWindow
        super.init(nibName: nil, bundle: nil)
    }

    required init?(coder: NSCoder) {
        fatalError("init(coder:) has not been implemented")
    }

    override func loadView() {
        self.view = NSView()
    }

    override func viewWillAppear() {
        super.viewWillAppear()

        let userSettings = UserDefaults.standard
        guard let window = loginWindow ?? (self.view.window as? LoginWindow) else { return }
        window.hostLabel.stringValue = userSettings.string(forKey: "host") ?? ""
        if (userSettings.integer(forKey: "port") > 0) {
            window.portLabel.intValue = Int32(userSettings.integer(forKey: "port"))
        }
        window.usernameLabel.stringValue = userSettings.string(forKey: "username") ?? ""
        window.passwordLabel.stringValue = KeychainHelper.get(forKey: "password") ?? ""
    }
    
    override func viewWillDisappear() {
        super.viewWillDisappear()
        
        let userSettings = UserDefaults.standard
        guard let window = loginWindow ?? (self.view.window as? LoginWindow) else { return }
        userSettings.set(window.hostLabel.stringValue, forKey: "host")
        if (window.portLabel.intValue > 0) {
            userSettings.set(window.portLabel.intValue, forKey: "port")
        }
        userSettings.set(window.usernameLabel.stringValue, forKey: "username")
        KeychainHelper.set(window.passwordLabel.stringValue, forKey: "password")
    }
}

class LoginWindow: NSWindow {
    var hostLabel: NSTextField!
    var portLabel: NSTextField!
    var usernameLabel: NSTextField!
    var passwordLabel: NSSecureTextField!
    var connectButton: NSButton!
    var errorLabel: NSTextField!
    var zoomController: WindowZoomController?

    override init(contentRect rect: NSRect, styleMask style: NSWindow.StyleMask, backing backingStoreType: NSWindow.BackingStoreType, defer flag: Bool) {
        super.init(contentRect: rect, styleMask: style, backing: backingStoreType, defer: flag)
        
        self.isReleasedWhenClosed = false
        self.title = "Login"

        hostLabel = NSTextField()
        hostLabel.frame = .init(x: 20, y: 20, width: 300, height: 30)
        hostLabel.placeholderString = "https://mattermost.example.com (http:// only for local servers)"

        portLabel = NSTextField()
        portLabel.frame = .init(x: 20, y: 50, width: 300, height: 30)
        portLabel.placeholderString = "443"
        portLabel.formatter = NumberFormatter()

        usernameLabel = NSTextField()
        usernameLabel.frame = .init(x: 20, y: 80, width: 300, height: 30)
        usernameLabel.placeholderString = "{username}"

        passwordLabel = NSSecureTextField()
        passwordLabel.frame = .init(x: 20, y: 110, width: 300, height: 30)
        passwordLabel.placeholderString = "{password}"
        
        errorLabel = NSTextField(labelWithString: "")
        errorLabel.frame = .init(x: 20, y: 150, width: 580, height: 40)
        errorLabel.textColor = .systemRed
        errorLabel.maximumNumberOfLines = 2
        errorLabel.lineBreakMode = .byWordWrapping

        connectButton = NSButton()
        connectButton.title = "Connect"
        connectButton.frame = .init(x: 20, y: 200, width: 80, height: 30)
        connectButton.target = self
        connectButton.action = #selector(connectButtonPressed)

        self.contentViewController = LoginWindowViewController(loginWindow: self)
        self.setContentSize(NSSize(width: rect.width, height: rect.height))
        self.center()
        
        contentView?.addSubview(hostLabel)
        contentView?.addSubview(portLabel)
        contentView?.addSubview(usernameLabel)
        contentView?.addSubview(passwordLabel)
        contentView?.addSubview(errorLabel)
        contentView?.addSubview(connectButton)

        zoomController = WindowZoomController(window: self)
        zoomController?.applyCurrentZoom()
        self.makeKeyAndOrderFront(nil)
    }
    
    override func performKeyEquivalent(with event: NSEvent) -> Bool {
        if zoomController?.handleKeyEquivalent(event) == true {
            return true
        }
        return super.performKeyEquivalent(with: event)
    }
    
    private func setInputsEnabled(_ enabled: Bool) {
        hostLabel.isEnabled = enabled
        portLabel.isEnabled = enabled
        usernameLabel.isEnabled = enabled
        passwordLabel.isEnabled = enabled
        connectButton.isEnabled = enabled
    }
    
    @objc func connectButtonPressed() {
        self.makeFirstResponder(nil)

        // Disable widgets.
        setInputsEnabled(false)
        errorLabel.stringValue = ""

        // Save input to settings.
        let host = hostLabel.stringValue.trimmingCharacters(in: .whitespacesAndNewlines)
        // 0 lets WebService pick the scheme default (443 for https, 80 for http).
        let port: UInt16 = portLabel.intValue > 0 ? UInt16(clamping: portLabel.intValue) : 0
        let username = usernameLabel.stringValue.trimmingCharacters(in: .whitespacesAndNewlines)
        let password = passwordLabel.stringValue

        let userSettings = UserDefaults.standard
        userSettings.set(host, forKey: "host")
        userSettings.set(Int(port), forKey: "port")
        userSettings.set(username, forKey: "username")
        KeychainHelper.set(password, forKey: "password")

        guard !host.isEmpty, !username.isEmpty, !password.isEmpty else {
            setInputsEnabled(true)
            errorLabel.stringValue = "Please enter host, username, and password."
            return
        }

        // Try to connect.
        let appDelegate = NSApp.delegate as? AppDelegate
        let service = WebService(host: host, port: port)
        appDelegate?.webService = service

        Task { @MainActor [weak self] in
            guard let self = self else { return }
            do {
                _ = try await service.login(username: username, password: password)
                // exit window on success
                if let token = service.token() {
                    KeychainHelper.set(token, forKey: "token")
                }
                appDelegate?.showMainWindow()
            } catch {
                // if fail:
                // * enable input
                // * show error message.
                self.setInputsEnabled(true)
                self.errorLabel.stringValue = error.localizedDescription
            }
        }
    }
    
}
