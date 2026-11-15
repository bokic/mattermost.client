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
        if userSettings.integer(forKey: "port") > 0 {
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

    override func viewDidAppear() {
        super.viewDidAppear()
        guard let window = loginWindow ?? (self.view.window as? LoginWindow) else { return }
        if window.hostLabel.stringValue.isEmpty {
            window.makeFirstResponder(window.hostLabel)
        } else if window.usernameLabel.stringValue.isEmpty {
            window.makeFirstResponder(window.usernameLabel)
        } else {
            window.makeFirstResponder(window.passwordLabel)
        }
    }

    override func viewWillDisappear() {
        super.viewWillDisappear()
        // Credentials are stored only after a successful login (see
        // LoginWindow.connectButtonPressed); closing the window must not
        // overwrite the last working server/account with unvalidated input.
    }
}

class LoginWindow: NSWindow, NSTextFieldDelegate {
    var hostLabel: NSTextField!
    var portLabel: NSTextField!
    var usernameLabel: NSTextField!
    var passwordLabel: NSSecureTextField!
    var visiblePasswordField: NSTextField!
    var showPasswordButton: NSButton!
    var mfaField: NSTextField!
    var rememberPasswordButton: NSButton!
    var connectButton: NSButton!
    var ssoButton: NSButton!
    var errorLabel: NSTextField!
    var zoomController: WindowZoomController?

    private let cardPanel = RoundedEdgePanel()
    private var serverCaption: NSTextField!
    private var usernameCaption: NSTextField!
    private var passwordCaption: NSTextField!
    private var mfaCaption: NSTextField!
    private var ssoHintLabel: NSTextField!
    private var footerLabel: NSTextField!
    private var isBusy = false
    private var ssoProviders: [LoginSupport.SSOProvider] = []
    private var ssoWindow: NSWindow?
    private var ssoHost = ""
    private var ssoPort: UInt16 = 0

    private let contentWidth: CGFloat = 560
    private let contentHeight: CGFloat = 660

    override init(
        contentRect rect: NSRect,
        styleMask style: NSWindow.StyleMask,
        backing backingStoreType: NSWindow.BackingStoreType,
        defer flag: Bool
    ) {
        super.init(
            contentRect: rect,
            styleMask: style,
            backing: backingStoreType,
            defer: flag
        )

        self.isReleasedWhenClosed = false
        self.title = "Mattermost"
        self.styleMask = [.miniaturizable, .closable, .titled]
        self.contentViewController = LoginWindowViewController(loginWindow: self)
        self.setContentSize(NSSize(width: contentWidth, height: contentHeight))
        self.center()

        buildInterface()
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

    // MARK: - Interface

    private func buildInterface() {
        guard let contentView = contentView else { return }
        contentView.wantsLayer = true

        let logo = NSImageView()
        logo.image = NSImage(named: NSImage.Name("Mattermost Logo"))
            ?? NSImage(systemSymbolName: "bubble.left.and.bubble.right.fill", accessibilityDescription: nil)
        logo.imageScaling = .scaleProportionallyUpOrDown
        logo.frame = NSRect(x: 36, y: 606, width: 38, height: 38)
        contentView.addSubview(logo)

        let title = NSTextField(labelWithString: "Mattermost")
        title.font = MMFont.font(ofSize: 22, weight: .semibold)
        title.textColor = .labelColor
        title.frame = NSRect(x: 86, y: 616, width: 300, height: 26)
        contentView.addSubview(title)

        let subtitle = NSTextField(labelWithString: "Sign in to your workspace")
        subtitle.font = MMFont.font(ofSize: 12)
        subtitle.textColor = .secondaryLabelColor
        subtitle.frame = NSRect(x: 86, y: 596, width: 340, height: 16)
        contentView.addSubview(subtitle)

        cardPanel.color = .controlBackgroundColor
        cardPanel.cornerRadius = 14
        cardPanel.borderWidth = 1
        cardPanel.borderColor = .separatorColor
        cardPanel.frame = NSRect(x: 36, y: 170, width: 488, height: 420)
        contentView.addSubview(cardPanel)

        serverCaption = makeCaption("Server URL")
        serverCaption.frame = NSRect(x: 20, y: 376, width: 448, height: 16)
        cardPanel.addSubview(serverCaption)

        hostLabel = makeField(placeholder: "chat.example.com")
        hostLabel.delegate = self
        hostLabel.frame = NSRect(x: 20, y: 344, width: 324, height: 30)
        cardPanel.addSubview(hostLabel)

        portLabel = makeField(placeholder: "443")
        portLabel.delegate = self
        portLabel.frame = NSRect(x: 352, y: 344, width: 116, height: 30)
        portLabel.formatter = NumberFormatter()
        cardPanel.addSubview(portLabel)

        usernameCaption = makeCaption("Username or email")
        usernameCaption.frame = NSRect(x: 20, y: 306, width: 448, height: 16)
        cardPanel.addSubview(usernameCaption)

        usernameLabel = makeField(placeholder: "you@example.com")
        usernameLabel.delegate = self
        usernameLabel.frame = NSRect(x: 20, y: 274, width: 448, height: 30)
        cardPanel.addSubview(usernameLabel)

        passwordCaption = makeCaption("Password")
        passwordCaption.frame = NSRect(x: 20, y: 236, width: 448, height: 16)
        cardPanel.addSubview(passwordCaption)

        passwordLabel = NSSecureTextField()
        passwordLabel.placeholderString = "Password"
        passwordLabel.font = MMFont.font(ofSize: 13)
        passwordLabel.delegate = self
        passwordLabel.frame = NSRect(x: 20, y: 204, width: 412, height: 30)
        passwordLabel.target = self
        passwordLabel.action = #selector(connectButtonPressed)
        cardPanel.addSubview(passwordLabel)

        visiblePasswordField = makeField(placeholder: "Password")
        visiblePasswordField.delegate = self
        visiblePasswordField.frame = NSRect(x: 20, y: 204, width: 412, height: 30)
        visiblePasswordField.isHidden = true
        visiblePasswordField.target = self
        visiblePasswordField.action = #selector(connectButtonPressed)
        cardPanel.addSubview(visiblePasswordField)

        showPasswordButton = NSButton(
            image: NSImage(systemSymbolName: "eye", accessibilityDescription: "Show password")!,
            target: self,
            action: #selector(togglePasswordVisibility)
        )
        showPasswordButton.bezelStyle = .inline
        showPasswordButton.isBordered = false
        showPasswordButton.toolTip = "Show password"
        showPasswordButton.frame = NSRect(x: 440, y: 206, width: 28, height: 26)
        cardPanel.addSubview(showPasswordButton)

        mfaCaption = makeCaption("Authentication code")
        mfaCaption.frame = NSRect(x: 20, y: 166, width: 448, height: 16)
        mfaCaption.isHidden = true
        cardPanel.addSubview(mfaCaption)

        mfaField = makeField(placeholder: "6-digit code")
        mfaField.delegate = self
        mfaField.frame = NSRect(x: 20, y: 134, width: 448, height: 30)
        mfaField.isHidden = true
        mfaField.target = self
        mfaField.action = #selector(connectButtonPressed)
        cardPanel.addSubview(mfaField)

        errorLabel = NSTextField(labelWithString: "")
        errorLabel.frame = NSRect(x: 20, y: 92, width: 448, height: 34)
        errorLabel.font = MMFont.font(ofSize: 12)
        errorLabel.textColor = .systemRed
        errorLabel.maximumNumberOfLines = 2
        errorLabel.lineBreakMode = .byWordWrapping
        errorLabel.isEditable = false
        errorLabel.isSelectable = false
        cardPanel.addSubview(errorLabel)

        rememberPasswordButton = NSButton(
            checkboxWithTitle: L10n.string("Keep me signed in"),
            target: nil,
            action: nil
        )
        rememberPasswordButton.font = MMFont.font(ofSize: 12)
        rememberPasswordButton.frame = NSRect(x: 20, y: 64, width: 220, height: 22)
        cardPanel.addSubview(rememberPasswordButton)

        connectButton = NSButton(
            title: L10n.string("Sign in"),
            target: self,
            action: #selector(connectButtonPressed)
        )
        connectButton.bezelStyle = .rounded
        connectButton.bezelColor = .controlAccentColor
        connectButton.font = MMFont.font(ofSize: 14, weight: .semibold)
        connectButton.keyEquivalent = "\r"
        connectButton.frame = NSRect(x: 20, y: 18, width: 448, height: 36)
        cardPanel.addSubview(connectButton)

        ssoHintLabel = NSTextField(labelWithString: "or continue with")
        ssoHintLabel.font = MMFont.font(ofSize: 11)
        ssoHintLabel.textColor = .secondaryLabelColor
        ssoHintLabel.alignment = .center
        ssoHintLabel.frame = NSRect(x: 36, y: 142, width: 488, height: 16)
        contentView.addSubview(ssoHintLabel)

        ssoButton = NSButton(
            title: "Continue with single sign-on",
            target: self,
            action: #selector(ssoButtonPressed)
        )
        ssoButton.bezelStyle = .rounded
        ssoButton.font = MMFont.font(ofSize: 13, weight: .medium)
        ssoButton.frame = NSRect(x: 36, y: 100, width: 488, height: 36)
        contentView.addSubview(ssoButton)

        footerLabel = NSTextField(
            labelWithString: "Credentials stay in the macOS Keychain. Session tokens are never logged."
        )
        footerLabel.font = MMFont.font(ofSize: 11)
        footerLabel.textColor = .tertiaryLabelColor
        footerLabel.alignment = .center
        footerLabel.maximumNumberOfLines = 2
        footerLabel.lineBreakMode = .byWordWrapping
        footerLabel.frame = NSRect(x: 36, y: 48, width: 488, height: 32)
        contentView.addSubview(footerLabel)

        self.initialFirstResponder = hostLabel
    }

    private func makeCaption(_ text: String) -> NSTextField {
        let label = NSTextField(labelWithString: text)
        label.font = MMFont.font(ofSize: 11, weight: .semibold)
        label.textColor = .secondaryLabelColor
        label.isEditable = false
        label.isSelectable = false
        return label
    }

    private func makeField(placeholder: String) -> NSTextField {
        let field = NSTextField()
        field.placeholderString = placeholder
        field.font = MMFont.font(ofSize: 13)
        field.focusRingType = .default
        field.cell?.usesSingleLineMode = true
        return field
    }

    // MARK: - Password / MFA login

    private func setInputsEnabled(_ enabled: Bool) {
        isBusy = !enabled
        hostLabel.isEnabled = enabled
        portLabel.isEnabled = enabled
        usernameLabel.isEnabled = enabled
        passwordLabel.isEnabled = enabled
        visiblePasswordField.isEnabled = enabled
        showPasswordButton.isEnabled = enabled
        mfaField.isEnabled = enabled
        rememberPasswordButton.isEnabled = enabled
        connectButton.isEnabled = enabled
        ssoButton.isEnabled = enabled
        connectButton.title = enabled ? L10n.string("Sign in") : "Signing in…"
    }

    @objc func connectButtonPressed() {
        guard !isBusy else { return }
        self.makeFirstResponder(nil)
        errorLabel.stringValue = ""

        let host = hostLabel.stringValue.trimmingCharacters(in: .whitespacesAndNewlines)
        let port: UInt16 = portLabel.intValue > 0 ? UInt16(clamping: portLabel.intValue) : 0
        let username = usernameLabel.stringValue.trimmingCharacters(in: .whitespacesAndNewlines)
        let password = passwordLabel.isHidden
            ? visiblePasswordField.stringValue
            : passwordLabel.stringValue
        let mfaToken = mfaField.isHidden
            ? nil
            : mfaField.stringValue.trimmingCharacters(in: .whitespacesAndNewlines)

        guard !host.isEmpty, !username.isEmpty, !password.isEmpty else {
            errorLabel.stringValue = L10n.string("Please enter host, username, and password.")
            return
        }
        guard mfaField.isHidden || !(mfaToken ?? "").isEmpty else {
            errorLabel.stringValue = "Enter the code from your authenticator app."
            makeFirstResponder(mfaField)
            return
        }

        setInputsEnabled(false)
        let service = WebService(host: host, port: port)
        (NSApp.delegate as? AppDelegate)?.webService = service

        Task { @MainActor [weak self] in
            guard let self = self else { return }
            do {
                let user = try await service.login(
                    username: username,
                    password: password,
                    mfaToken: mfaToken
                )
                guard let token = service.token(), !token.isEmpty else {
                    self.setInputsEnabled(true)
                    self.errorLabel.stringValue =
                        L10n.string("The server did not return a session token. Check the server URL and try again.")
                    return
                }
                self.persistAndOpenMain(
                    host: host,
                    port: port,
                    username: user.username,
                    password: password,
                    token: token
                )
            } catch {
                self.setInputsEnabled(true)
                if LoginSupport.isMFARequired(error) {
                    if self.mfaField.isHidden {
                        self.showMFAField()
                    } else {
                        self.errorLabel.stringValue = "That authentication code was not accepted."
                        self.makeFirstResponder(self.mfaField)
                    }
                } else {
                    self.errorLabel.stringValue = error.localizedDescription
                }
            }
        }
    }

    @objc private func togglePasswordVisibility() {
        if passwordLabel.isHidden {
            passwordLabel.stringValue = visiblePasswordField.stringValue
            passwordLabel.isHidden = false
            visiblePasswordField.isHidden = true
            showPasswordButton.image = NSImage(
                systemSymbolName: "eye",
                accessibilityDescription: "Show password"
            )
            showPasswordButton.toolTip = "Show password"
            makeFirstResponder(passwordLabel)
        } else {
            visiblePasswordField.stringValue = passwordLabel.stringValue
            visiblePasswordField.isHidden = false
            passwordLabel.isHidden = true
            showPasswordButton.image = NSImage(
                systemSymbolName: "eye.slash",
                accessibilityDescription: "Hide password"
            )
            showPasswordButton.toolTip = "Hide password"
            makeFirstResponder(visiblePasswordField)
        }
    }

    func controlTextDidChange(_ notification: Notification) {
        if !errorLabel.stringValue.isEmpty {
            errorLabel.stringValue = ""
        }
    }

    func showMFAField() {
        mfaCaption.isHidden = false
        mfaField.isHidden = false
        errorLabel.stringValue =
            "Multi-factor authentication is required. Enter your authenticator code."
        makeFirstResponder(mfaField)
    }

    private func persistAndOpenMain(
        host: String,
        port: UInt16,
        username: String,
        password: String?,
        token: String
    ) {
        let settings = UserDefaults.standard
        settings.set(host, forKey: "host")
        if port > 0 {
            settings.set(Int(port), forKey: "port")
        } else {
            settings.removeObject(forKey: "port")
        }
        settings.set(username, forKey: "username")

        let rememberPassword = password != nil && rememberPasswordButton.state == .on
        settings.set(rememberPassword, forKey: "rememberPassword")
        if rememberPassword, let password = password {
            KeychainHelper.set(password, forKey: "password")
        } else {
            KeychainHelper.delete(forKey: "password")
        }
        KeychainHelper.set(token, forKey: "token")

        (NSApp.delegate as? AppDelegate)?.showMainWindow()
    }

    // MARK: - SSO / OAuth

    @objc func ssoButtonPressed() {
        guard !isBusy else { return }
        let host = hostLabel.stringValue.trimmingCharacters(in: .whitespacesAndNewlines)
        let port: UInt16 = portLabel.intValue > 0 ? UInt16(clamping: portLabel.intValue) : 0
        guard !host.isEmpty else {
            errorLabel.stringValue = L10n.string("Enter the server URL first.")
            makeFirstResponder(hostLabel)
            return
        }

        errorLabel.stringValue = ""
        setInputsEnabled(false)
        ssoButton.title = "Loading sign-in options…"

        Task { @MainActor [weak self] in
            guard let self = self else { return }
            let service = WebService(host: host, port: port)
            let data = await service.fetchClientConfigData()
            let providers = data.map(LoginSupport.providers(fromClientConfig:)) ?? []
            self.setInputsEnabled(true)
            self.ssoButton.title = "Continue with single sign-on"
            self.ssoProviders = providers

            guard !providers.isEmpty else {
                self.errorLabel.stringValue =
                    "No single sign-on providers are enabled for this server."
                return
            }
            if providers.count == 1 {
                self.presentSSO(provider: providers[0], host: host, port: port)
            } else {
                self.showSSOProviderMenu()
            }
        }
    }

    private func showSSOProviderMenu() {
        let menu = NSMenu()
        for provider in ssoProviders {
            let item = NSMenuItem(
                title: provider.title,
                action: #selector(ssoProviderSelected(_:)),
                keyEquivalent: ""
            )
            item.target = self
            item.representedObject = provider.id
            menu.addItem(item)
        }
        menu.popUp(
            positioning: nil,
            at: NSPoint(x: 0, y: ssoButton.bounds.height + 4),
            in: ssoButton
        )
    }

    @objc private func ssoProviderSelected(_ sender: NSMenuItem) {
        guard let id = sender.representedObject as? String,
              let provider = ssoProviders.first(where: { $0.id == id })
        else { return }
        let host = hostLabel.stringValue.trimmingCharacters(in: .whitespacesAndNewlines)
        let port: UInt16 = portLabel.intValue > 0 ? UInt16(clamping: portLabel.intValue) : 0
        presentSSO(provider: provider, host: host, port: port)
    }

    private func presentSSO(provider: LoginSupport.SSOProvider, host: String, port: UInt16) {
        guard let url = WebService(host: host, port: port).buildURL(path: provider.path) else {
            errorLabel.stringValue = "Could not build the single sign-on URL. Check the server URL."
            return
        }
        ssoHost = host
        ssoPort = port

        let controller = SSOLoginWebViewController(url: url, title: provider.title)
        controller.onResult = { [weak self] result in
            self?.handleSSOResult(result, provider: provider)
        }
        let window = NSWindow(contentViewController: controller)
        window.styleMask = [.titled, .closable]
        window.title = provider.title
        window.setContentSize(NSSize(width: 520, height: 660))
        window.delegate = controller
        ssoWindow = window
        beginSheet(window)
    }

    private func handleSSOResult(
        _ result: Result<String, Error>,
        provider: LoginSupport.SSOProvider
    ) {
        ssoWindow = nil
        setInputsEnabled(true)
        switch result {
        case .success(let token):
            completeSSOLogin(token: token, provider: provider)
        case .failure(let error):
            if error is CancellationError { return }
            errorLabel.stringValue = error.localizedDescription
        }
    }

    private func completeSSOLogin(token: String, provider: LoginSupport.SSOProvider) {
        setInputsEnabled(false)
        ssoButton.title = "Signing in with \(provider.title)…"
        let service = WebService(host: ssoHost, port: ssoPort)
        (NSApp.delegate as? AppDelegate)?.webService = service

        Task { @MainActor [weak self] in
            guard let self = self else { return }
            do {
                let user = try await service.loginWithSessionToken(token)
                self.persistAndOpenMain(
                    host: self.ssoHost,
                    port: self.ssoPort,
                    username: user.username,
                    password: nil,
                    token: token
                )
            } catch {
                self.setInputsEnabled(true)
                self.ssoButton.title = "Continue with single sign-on"
                self.errorLabel.stringValue =
                    "Single sign-on completed, but the session could not be verified: \(error.localizedDescription)"
            }
        }
    }
}
