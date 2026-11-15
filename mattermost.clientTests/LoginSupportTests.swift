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
}
