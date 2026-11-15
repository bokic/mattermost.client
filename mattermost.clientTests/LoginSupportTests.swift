//
//  LoginSupportTests.swift
//  mattermost.clientTests
//

import XCTest

#if canImport(mattermost_client)
    @testable import mattermost_client
#endif

final class LoginSupportTests: XCTestCase {

    func testProvidersReadEnabledSAMLAndOAuthServices() throws {
        let config = """
            {
              "SamlSettings": {"Enable": true},
              "GitLabSettings": {"Enable": true},
              "GoogleSettings": {"Enable": false},
              "Office365Settings": {"Enable": true},
              "OpenIdConnectSettings": {"Enable": true, "ButtonText": "Company SSO"}
            }
            """
        let providers = LoginSupport.providers(fromClientConfig: Data(config.utf8))
        XCTAssertEqual(providers.map(\.id), ["saml", "gitlab", "office365", "openid"])
        XCTAssertEqual(providers.last?.title, "Company SSO")
        XCTAssertEqual(providers.first?.path, "/saml/login")
    }

    func testProvidersIgnoreDisabledAndMalformedConfig() {
        XCTAssertTrue(
            LoginSupport.providers(
                fromClientConfig: Data(#"{"SamlSettings":{"Enable":false}}"#.utf8)
            ).isEmpty
        )
        XCTAssertTrue(LoginSupport.providers(fromClientConfig: Data("not json".utf8)).isEmpty)
    }

    func testMFARequiredDetection() {
        let mfa = NSError(
            domain: "test",
            code: 401,
            userInfo: [NSLocalizedDescriptionKey: "Multi-factor authentication is required"]
        )
        let ordinary = NSError(
            domain: "test",
            code: 401,
            userInfo: [NSLocalizedDescriptionKey: "Invalid username or password"]
        )
        XCTAssertTrue(LoginSupport.isMFARequired(mfa))
        XCTAssertFalse(LoginSupport.isMFARequired(ordinary))
    }

    func testTokenFromRedirectURL() throws {
        XCTAssertEqual(
            LoginSupport.token(fromRedirectURL: URL(string: "mattermost://callback?token=abc123")!),
            "abc123"
        )
        XCTAssertEqual(
            LoginSupport.token(fromRedirectURL: URL(string: "https://chat.example.com/landing?MMAUTHTOKEN=xyz")!),
            "xyz"
        )
        XCTAssertNil(LoginSupport.token(fromRedirectURL: URL(string: "https://chat.example.com/landing")!))
    }

    func testTokenFromCookies() throws {
        let auth = try XCTUnwrap(
            HTTPCookie(properties: [
                .name: "MMAUTHTOKEN",
                .value: "cookie-token",
                .domain: "chat.example.com",
                .path: "/",
            ])
        )
        XCTAssertEqual(LoginSupport.token(from: [auth]), "cookie-token")

        let unrelated = try XCTUnwrap(
            HTTPCookie(properties: [
                .name: "MMUSERID",
                .value: "user-id",
                .domain: "chat.example.com",
                .path: "/",
            ])
        )
        XCTAssertNil(LoginSupport.token(from: [unrelated]))
    }

    // MARK: - Server Discovery Tests

    func testExtractDomainFromEmail() {
        XCTAssertEqual(LoginSupport.extractDomain(fromEmail: "alice@company.com"), "company.com")
        XCTAssertEqual(LoginSupport.extractDomain(fromEmail: "  Bob.Smith+tag@Sub.Domain.Org  "), "sub.domain.org")
        XCTAssertNil(LoginSupport.extractDomain(fromEmail: "not-an-email"))
        XCTAssertNil(LoginSupport.extractDomain(fromEmail: "@domain.com"))
        XCTAssertNil(LoginSupport.extractDomain(fromEmail: "user@"))
        XCTAssertNil(LoginSupport.extractDomain(fromEmail: "user@nodot"))
        XCTAssertNil(LoginSupport.extractDomain(fromEmail: ""))
    }

    func testIsPublicWebmail() {
        XCTAssertTrue(LoginSupport.isPublicWebmail(domain: "gmail.com"))
        XCTAssertTrue(LoginSupport.isPublicWebmail(domain: "yahoo.com"))
        XCTAssertTrue(LoginSupport.isPublicWebmail(domain: "Outlook.Com"))
        XCTAssertTrue(LoginSupport.isPublicWebmail(domain: "icloud.com"))
        XCTAssertFalse(LoginSupport.isPublicWebmail(domain: "company.com"))
        XCTAssertFalse(LoginSupport.isPublicWebmail(domain: "chat.corp.internal"))
    }

    func testCandidateServerURLs() {
        let urls = LoginSupport.candidateServerURLs(forDomain: "acme.com")
        let strings = urls.map(\.absoluteString)
        XCTAssertTrue(strings.contains("https://chat.acme.com"))
        XCTAssertTrue(strings.contains("https://mattermost.acme.com"))
        XCTAssertTrue(strings.contains("https://mm.acme.com"))
        XCTAssertTrue(strings.contains("https://acme.com"))
        XCTAssertTrue(strings.contains("https://acme.com/mattermost"))

        let chatURLs = LoginSupport.candidateServerURLs(forDomain: "chat.acme.com")
        let chatStrings = chatURLs.map(\.absoluteString)
        XCTAssertFalse(chatStrings.contains("https://chat.chat.acme.com"))
        XCTAssertTrue(chatStrings.contains("https://chat.acme.com"))
    }

    func testDiscoverServerSucceedsWithMockSession() async {
        let config = URLSessionConfiguration.ephemeral
        config.protocolClasses = [MockURLProtocol.self]
        let session = URLSession(configuration: config)

        MockURLProtocol.responseProvider = { request in
            guard let url = request.url else { return nil }
            if url.host == "chat.acme.com" && url.path == "/api/v4/system/ping" {
                let response = HTTPURLResponse(url: url, statusCode: 200, httpVersion: nil, headerFields: ["Content-Type": "application/json"])!
                return (response, Data(#"{"status":"OK"}"#.utf8))
            }
            if url.host == "chat.acme.com" && url.path == "/api/v4/config/client" {
                let response = HTTPURLResponse(url: url, statusCode: 200, httpVersion: nil, headerFields: ["Content-Type": "application/json"])!
                return (response, Data(#"{"SiteName":"Acme Workspace"}"#.utf8))
            }
            let notFound = HTTPURLResponse(url: url, statusCode: 404, httpVersion: nil, headerFields: nil)!
            return (notFound, Data())
        }

        let discovered = await LoginSupport.discoverServer(forEmail: "alice@acme.com", session: session)
        XCTAssertNotNil(discovered)
        XCTAssertEqual(discovered?.host, "chat.acme.com")
        XCTAssertEqual(discovered?.siteName, "Acme Workspace")
        XCTAssertEqual(discovered?.port, 443)
    }

    func testDiscoverServerReturnsNilForPublicWebmail() async {
        let discovered = await LoginSupport.discoverServer(forEmail: "bob@gmail.com")
        XCTAssertNil(discovered)
    }

    private final class MockURLProtocol: URLProtocol, @unchecked Sendable {
        nonisolated(unsafe) static var responseProvider: (@Sendable (URLRequest) -> (HTTPURLResponse, Data)?)?

        override class func canInit(with request: URLRequest) -> Bool { true }
        override class func canonicalRequest(for request: URLRequest) -> URLRequest { request }

        override func startLoading() {
            guard let handler = Self.responseProvider,
                  let (response, data) = handler(request) else {
                client?.urlProtocol(self, didFailWithError: URLError(.badServerResponse))
                return
            }
            client?.urlProtocol(self, didReceive: response, cacheStoragePolicy: .notAllowed)
            client?.urlProtocol(self, didLoad: data)
            client?.urlProtocolDidFinishLoading(self)
        }

        override func stopLoading() {}
    }
}
