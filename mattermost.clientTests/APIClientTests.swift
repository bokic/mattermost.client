//
//  APIClientTests.swift
//  mattermost.clientTests
//

import XCTest

#if canImport(mattermost_client)
    @testable import mattermost_client
#endif

@MainActor
final class APIClientTests: XCTestCase {

    // MARK: - URL Building

    func testBuildURLWithPortAndPath() {
        let client = APIClient(host: "chat.example.com", port: 8065)
        let url = client.buildURL(path: "/api/v4/users/me")
        XCTAssertEqual(url?.absoluteString, "https://chat.example.com:8065/api/v4/users/me")
    }

    func testBuildURLSubpathPreservation() {
        let client = APIClient(host: "https://chat.example.com/mattermost", port: 0)
        let url = client.buildURL(path: "/api/v4/users/me")
        XCTAssertEqual(url?.absoluteString, "https://chat.example.com/mattermost/api/v4/users/me")
    }

    func testBuildWebSocketURL() {
        let client = APIClient(host: "https://chat.example.com", port: 443)
        XCTAssertEqual(client.webSocketURL?.absoluteString, "wss://chat.example.com:443/api/v4/websocket")

        let insecureClient = APIClient(host: "http://chat.example.com", port: 8065)
        XCTAssertEqual(insecureClient.webSocketURL?.absoluteString, "ws://chat.example.com:8065/api/v4/websocket")
    }

    func testBuildURLQueryItems() {
        let client = APIClient(host: "chat.example.com", port: 8065)
        let url = client.buildURL(
            path: "/api/v4/posts",
            queryItems: [
                URLQueryItem(name: "page", value: "1"),
                URLQueryItem(name: "per_page", value: "30"),
            ])
        XCTAssertEqual(url?.absoluteString, "https://chat.example.com:8065/api/v4/posts?page=1&per_page=30")
    }

    func testTeamInviteURL() {
        let client = APIClient(host: "chat.example.com", port: 8065)
        let team = MMTeam(
            id: "team1",
            create_at: 0,
            update_at: 0,
            delete_at: 0,
            display_name: "Team",
            name: "team",
            description: nil,
            email: nil,
            type: "O",
            company_name: nil,
            allowed_domains: nil,
            invite_id: "invite_xyz",
            allow_open_invite: true
        )
        let inviteURL = client.teamInviteURL(team: team)
        XCTAssertEqual(inviteURL?.absoluteString, "https://chat.example.com:8065/signup_user_complete/?id=invite_xyz")
    }

    // MARK: - Request Building

    func testMakeRequestSetsAuthorizationAndHeaders() throws {
        let client = APIClient(host: "chat.example.com", port: 8065)
        client.authToken = "secret-token-123"

        let request = try client.makeRequest(
            path: "/api/v4/users/me",
            method: "POST",
            jsonBody: ["key": "value"],
            auth: .requiredToken
        )

        XCTAssertEqual(request.httpMethod, "POST")
        XCTAssertEqual(request.value(forHTTPHeaderField: "Authorization"), "Bearer secret-token-123")
        XCTAssertEqual(request.value(forHTTPHeaderField: "Content-Type"), "application/json")
        XCTAssertEqual(request.value(forHTTPHeaderField: "Accept"), "application/json")
        XCTAssertNotNil(request.httpBody)
    }

    func testMakeRequestBearerOverride() throws {
        let client = APIClient(host: "chat.example.com", port: 8065)
        client.authToken = "default-token"

        let request = try client.makeRequest(
            path: "/api/v4/users/me",
            auth: .bearer("custom-token-xyz")
        )

        XCTAssertEqual(request.value(forHTTPHeaderField: "Authorization"), "Bearer custom-token-xyz")
    }

    func testMakeRequestNoAuth() throws {
        let client = APIClient(host: "chat.example.com", port: 8065)
        client.authToken = "default-token"

        let request = try client.makeRequest(
            path: "/api/v4/config/client",
            auth: .none
        )

        XCTAssertNil(request.value(forHTTPHeaderField: "Authorization"))
    }

    // MARK: - Auth Helpers

    func testIsAuthenticationFailure() {
        XCTAssertTrue(APIClient.isAuthenticationFailure(WebServiceError.httpStatus(code: 401, message: nil)))
        XCTAssertTrue(APIClient.isAuthenticationFailure(WebServiceError.httpStatus(code: 403, message: nil)))
        XCTAssertFalse(APIClient.isAuthenticationFailure(WebServiceError.httpStatus(code: 404, message: nil)))
        XCTAssertFalse(APIClient.isAuthenticationFailure(WebServiceError.invalidHostname))
    }

    func testDecodeLogin() {
        let json = """
            {
                "id": "u1",
                "username": "alice"
            }
            """.data(using: .utf8)!
        let user = APIClient.decodeLogin(json)
        XCTAssertEqual(user?.id, "u1")
        XCTAssertEqual(user?.username, "alice")
    }

    func testTokenAndLoggedState() {
        let client = APIClient(host: "chat.example.com", port: 8065)
        XCTAssertFalse(client.isLogged())
        XCTAssertNil(client.token())

        client.authToken = "tok123"
        XCTAssertTrue(client.isLogged())
        XCTAssertEqual(client.token(), "tok123")
    }
}
