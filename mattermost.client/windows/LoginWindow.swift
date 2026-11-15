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
        nil
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
        let remember = userSettings.bool(forKey: "rememberPassword")
        window.rememberPasswordButton.state = remember ? .on : .off

        guard remember else { return }
        // Keychain reads can block on the main thread while the system prompts.
        Task.detached {
            let password = KeychainHelper.get(forKey: "password")
            await MainActor.run { [weak window] in
                window?.passwordLabel.stringValue = password ?? ""
            }
        }
    }
    
    override func viewWillDisappear() {
        super.viewWillDisappear()
        // Credentials are stored only after a successful login (see
        // LoginWindow.connectButtonPressed); closing the window must not
        // overwrite the last working server/account with unvalidated input.
    }
}

class LoginWindow: NSWindow {
    var hostLabel: NSTextField!
    var portLabel: NSTextField!
    var usernameLabel: NSTextField!
    var passwordLabel: NSSecureTextField!
    var rememberPasswordButton: NSButton!
    var connectButton: NSButton!
    var errorLabel: NSTextField!
    var zoomController: WindowZoomController?

    override init(contentRect rect: NSRect, styleMask style: NSWindow.StyleMask, backing backingStoreType: NSWindow.BackingStoreType, defer flag: Bool) {
        super.init(contentRect: rect, styleMask: style, backing: backingStoreType, defer: flag)
        
        self.isReleasedWhenClosed = false
        self.title = L10n.string("Login")

        hostLabel = NSTextField()
        hostLabel.frame = .init(x: 20, y: 20, width: 300, height: 30)
        hostLabel.placeholderString = L10n.string("Server URL")

        portLabel = NSTextField()
        portLabel.frame = .init(x: 20, y: 50, width: 300, height: 30)
        portLabel.placeholderString = "443"
        portLabel.formatter = NumberFormatter()

        usernameLabel = NSTextField()
        usernameLabel.frame = .init(x: 20, y: 80, width: 300, height: 30)
        usernameLabel.placeholderString = L10n.string("Username")

        passwordLabel = NSSecureTextField()
        passwordLabel.frame = .init(x: 20, y: 110, width: 300, height: 30)
        passwordLabel.placeholderString = L10n.string("Password")
        
        errorLabel = NSTextField(labelWithString: "")
        errorLabel.frame = .init(x: 20, y: 150, width: 580, height: 40)
        errorLabel.textColor = .systemRed
        errorLabel.maximumNumberOfLines = 2
        errorLabel.lineBreakMode = .byWordWrapping

        connectButton = NSButton()
        connectButton.title = L10n.string("Connect")
        connectButton.frame = .init(x: 20, y: 200, width: 80, height: 30)
        connectButton.target = self
        connectButton.action = #selector(connectButtonPressed)
        connectButton.keyEquivalent = "\r"

        rememberPasswordButton = NSButton(checkboxWithTitle: L10n.string("Keep me signed in"), target: nil, action: nil)
        rememberPasswordButton.frame = .init(x: 112, y: 204, width: 190, height: 24)
        rememberPasswordButton.state = .off

        self.contentViewController = LoginWindowViewController(loginWindow: self)
        self.setContentSize(NSSize(width: rect.width, height: rect.height))
        self.center()
        
        contentView?.addSubview(hostLabel)
        contentView?.addSubview(portLabel)
        contentView?.addSubview(usernameLabel)
        contentView?.addSubview(passwordLabel)
        contentView?.addSubview(errorLabel)
        contentView?.addSubview(connectButton)
        contentView?.addSubview(rememberPasswordButton)

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

        guard !host.isEmpty, !username.isEmpty, !password.isEmpty else {
            setInputsEnabled(true)
            errorLabel.stringValue = L10n.string("Please enter host, username, and password.")
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
                guard let token = service.token(), !token.isEmpty else {
                    self.setInputsEnabled(true)
                    self.errorLabel.stringValue = L10n.string("The server did not return a session token. Check the server URL and try again.")
                    return
                }
                // Persist only validated credentials, so a typo cannot replace
                // the last working account.
                userSettings.set(host, forKey: "host")
                if port > 0 {
                    userSettings.set(Int(port), forKey: "port")
                } else {
                    userSettings.removeObject(forKey: "port")
                }
                userSettings.set(username, forKey: "username")
                let rememberPassword = self.rememberPasswordButton.state == .on
                userSettings.set(rememberPassword, forKey: "rememberPassword")
                if rememberPassword {
                    KeychainHelper.set(password, forKey: "password")
                } else {
                    // Token-only session: the password is not retained.
                    KeychainHelper.delete(forKey: "password")
                }
                KeychainHelper.set(token, forKey: "token")
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
