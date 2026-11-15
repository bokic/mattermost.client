//
//  SSOLoginWebView.swift
//  mattermost.client
//
//  In-app browser used for SAML and OAuth sign-in. It watches for the
//  Mattermost session cookie (or a token query item) and hands the token back to
//  the login window.
//

import AppKit
import WebKit

@MainActor
final class SSOLoginWebViewController: NSViewController, WKNavigationDelegate, NSWindowDelegate {
    private let loginURL: URL
    private let providerTitle: String
    private var webView: WKWebView!
    private var completed = false

    var onResult: ((Result<String, Error>) -> Void)?

    init(url: URL, title: String) {
        self.loginURL = url
        self.providerTitle = title
        super.init(nibName: nil, bundle: nil)
    }

    required init?(coder: NSCoder) {
        nil
    }

    override func loadView() {
        let container = NSView(frame: NSRect(x: 0, y: 0, width: 520, height: 660))
        container.wantsLayer = true

        let configuration = WKWebViewConfiguration()
        configuration.websiteDataStore = .nonPersistent()
        webView = WKWebView(frame: container.bounds, configuration: configuration)
        webView.autoresizingMask = [.width, .height]
        webView.navigationDelegate = self
        container.addSubview(webView)
        self.view = container
    }

    override func viewDidLoad() {
        super.viewDidLoad()
        view.window?.title = providerTitle
        webView.load(URLRequest(url: loginURL))
    }

    func webView(_ webView: WKWebView, didFinish navigation: WKNavigation!) {
        checkForSession()
    }

    func webView(
        _ webView: WKWebView,
        didFail navigation: WKNavigation!,
        withError error: Error
    ) {
        finish(.failure(error))
    }

    func webView(
        _ webView: WKWebView,
        didFailProvisionalNavigation navigation: WKNavigation!,
        withError error: Error
    ) {
        finish(.failure(error))
    }

    func windowWillClose(_ notification: Notification) {
        guard !completed else { return }
        completed = true
        onResult?(.failure(CancellationError()))
    }

    private func checkForSession() {
        guard !completed else { return }
        if let url = webView.url, let token = LoginSupport.token(fromRedirectURL: url) {
            finish(.success(token))
            return
        }
        webView.configuration.websiteDataStore.httpCookieStore.getAllCookies { [weak self] cookies in
            guard let self = self else { return }
            if let token = LoginSupport.token(from: cookies) {
                Task { @MainActor in
                    self.finish(.success(token))
                }
            }
        }
    }

    private func finish(_ result: Result<String, Error>) {
        guard !completed else { return }
        completed = true
        if let window = view.window, let parent = window.sheetParent {
            parent.endSheet(window)
        }
        onResult?(result)
    }
}
