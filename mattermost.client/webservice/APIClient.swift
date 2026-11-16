//
//  APIClient.swift
//  mattermost.client
//

import Foundation
import os

/// How a request should authenticate.
enum APIRequestAuth {
    case none
    case optionalToken
    case requiredToken
    case bearer(String)
}

@MainActor
protocol APIClientProtocol: AnyObject {
    var host: String { get set }
    var port: UInt16 { get set }
    var authToken: String { get set }
    var currentUserId: String { get set }
    var webSocketURL: URL? { get }

    func token() -> String?
    func isLogged() -> Bool
    func buildURL(path: String, queryItems: [URLQueryItem]?, isWebSocket: Bool) -> URL?
    func teamInviteURL(team: MMTeam) -> URL?

    func makeRequest(
        path: String,
        method: String,
        queryItems: [URLQueryItem]?,
        jsonBody: Any?,
        rawBody: Data?,
        auth: APIRequestAuth,
        accept: String?,
        contentType: String?
    ) throws -> URLRequest

    func performRequest(
        path: String,
        method: String,
        queryItems: [URLQueryItem]?,
        jsonBody: Any?,
        rawBody: Data?,
        auth: APIRequestAuth,
        accept: String?,
        contentType: String?,
        acceptableStatus: ClosedRange<Int>,
        requireJSONMime: Bool,
        logPayload: Bool
    ) async throws -> (Data, HTTPURLResponse)

    func performAuthenticatedRequest<T: Decodable>(
        path: String,
        method: String,
        queryItems: [URLQueryItem]?,
        body: Any?
    ) async throws -> T

    // Auth
    func login(username: String, password: String, mfaToken: String?) async throws -> MMUser
    func loginWithSessionToken(_ token: String) async throws -> MMUser
    func checkToken(token: String) async -> Bool
    func fetchClientConfigData() async -> Data?
    func fetchLinkMetadata(url: URL) async -> MMLinkMetadata?

    // Users
    func fetchCurrentUser() async throws -> MMUser
    func fetchUsersByIds(_ userIds: [String]) async throws -> [MMUser]
    func updateUserNotifyProps(userId: String, props: [String: String]) async throws
    func fetchUser(userId: String) async throws -> MMUser
    func fetchUserByUsername(_ username: String) async throws -> MMUser
    func fetchTeamUsers(teamId: String, page: Int, perPage: Int) async throws -> [MMUser]
    func createDirectChannel(userId: String) async throws -> MMChannel
    func createGroupChannel(userIds: [String]) async throws -> MMChannel
    func searchUsers(term: String, teamId: String?) async throws -> [MMUser]
    func fetchUserImage(userId: String) async throws -> Data
    func updateUserStatus(userId: String, status: String, dndEndTime: Int64?) async throws -> MMUserStatus
    func fetchUserStatuses(userIds: [String]) async throws -> [MMUserStatus]
    func fetchUserPreferences(userId: String) async throws -> [[String: String]]
    func deleteUserPreferences(userId: String, preferences: [[String: String]]) async throws
    func saveUserPreferences(userId: String, preferences: [[String: String]]) async throws
    func setCustomStatus(emoji: String, text: String, duration: String, expiresAt: String?) async throws
    func clearCustomStatus() async throws

    // Teams
    func fetchTeams() async throws -> [MMTeam]
    func createTeam(name: String, displayName: String) async throws -> MMTeam
    func sendTeamInvite(teamId: String, email: String) async throws
    func fetchTeamsUnread(userId: String) async throws -> [MMTeamUnread]
    func leaveTeam(teamId: String, userId: String) async throws
    func fetchTeamByName(_ name: String) async throws -> MMTeam
    func addUserToTeam(teamId: String, userId: String) async throws
    func removeUserFromTeam(teamId: String, userId: String) async throws
    func fetchTeamMembers(teamId: String, page: Int, perPage: Int) async throws -> [MMTeamMember]
    func fetchTeamMember(teamId: String, userId: String) async throws -> MMTeamMember
    func updateTeamMemberRoles(teamId: String, userId: String, roles: String) async throws
    func updateTeam(
        teamId: String, displayName: String, description: String?, companyName: String?, allowedDomains: String?,
        allowOpenInvite: Bool?
    ) async throws -> MMTeam

    // Channels
    func fetchChannels(teamId: String) async throws -> [MMChannel]
    func fetchAllChannels() async throws -> [MMChannel]
    func fetchPublicChannels(teamId: String, page: Int, perPage: Int) async throws -> [MMChannel]
    func fetchPrivateChannels(teamId: String, page: Int, perPage: Int) async throws -> [MMChannel]
    func requestToJoinChannel(channelId: String) async throws
    func leaveChannel(channelId: String, userId: String) async throws
    func joinChannel(channelId: String, userId: String) async throws
    func fetchChannelMembers(channelId: String, page: Int, perPage: Int) async throws -> [MMChannelMember]
    func fetchChannelMemberships(userId: String, teamId: String, page: Int, perPage: Int) async throws
        -> [MMChannelMembership]
    func updateChannelNotifyProps(channelId: String, userId: String, props: [String: String]) async throws
    func markAllChannelsRead(userId: String, teamId: String) async throws
    func markChannelUnread(userId: String, channelId: String, postId: String) async throws
    func markChannelViewed(channelId: String) async throws -> Int64?

    // Sidebar Categories
    func fetchSidebarCategories(teamId: String) async throws -> MMSidebarCategoriesResponse
    func createSidebarCategory(teamId: String, displayName: String, userId: String) async throws -> MMSidebarCategory
    func updateSidebarCategory(
        teamId: String, userId: String, categoryId: String, displayName: String?, collapsed: Bool?, muted: Bool?
    ) async throws -> MMSidebarCategory
    func deleteSidebarCategory(teamId: String, userId: String, categoryId: String) async throws
    func updateSidebarCategoryOrder(teamId: String, userId: String, categoryIds: [String]) async throws
    func addChannelToSidebarCategory(teamId: String, userId: String, categoryId: String, channelId: String) async throws
    func removeChannelFromSidebarCategory(teamId: String, userId: String, categoryId: String, channelId: String)
        async throws

    // Posts
    func fetchChannelPosts(channelId: String, page: Int, perPage: Int, before: String?) async throws -> MMPostList
    func searchPosts(teamId: String, terms: String, page: Int, perPage: Int) async throws -> MMPostList
    func fetchPinnedPosts(channelId: String) async throws -> MMPostList
    func fetchFlaggedPosts(userId: String, teamId: String, page: Int, perPage: Int) async throws -> MMPostList
    func createPost(channelId: String, message: String, rootId: String?, fileIds: [String]) async throws -> MMPost
    func patchPost(postId: String, message: String) async throws -> MMPost
    func fetchPost(postId: String) async throws -> MMPost
    func fetchPostThread(postId: String) async throws -> MMPostList
    func pinPost(postId: String) async throws
    func unpinPost(postId: String) async throws
    func savePost(userId: String, postId: String) async throws
    func unsavePost(userId: String, postId: String) async throws
    func deletePost(postId: String) async throws

    // Reactions
    func addReaction(userId: String, postId: String, emojiName: String) async throws -> MMReaction
    func removeReaction(userId: String, postId: String, emojiName: String) async throws

    // Threads
    func fetchThreads(userId: String, teamId: String, perPage: Int) async throws -> [MMThread]
    func fetchThreadsPage(userId: String, teamId: String, page: Int, perPage: Int) async throws -> MMThreadsResponse
    func markThreadRead(teamId: String, threadId: String) async throws

    // Emojis
    func fetchCustomEmojis(page: Int, perPage: Int) async throws -> [MMEmoji]
    func fetchEmojiImage(emojiId: String) async throws -> Data

    // Plugins
    func fetchActivePluginIds() async throws -> [String]
}

extension APIClientProtocol {
    func buildURL(path: String, queryItems: [URLQueryItem]? = nil) -> URL? {
        buildURL(path: path, queryItems: queryItems, isWebSocket: false)
    }

    func performRequest(
        path: String,
        method: String = "GET",
        queryItems: [URLQueryItem]? = nil,
        jsonBody: Any? = nil,
        rawBody: Data? = nil,
        auth: APIRequestAuth = .requiredToken,
        accept: String? = "application/json",
        contentType: String? = nil,
        acceptableStatus: ClosedRange<Int> = 200...299,
        requireJSONMime: Bool = false,
        logPayload: Bool = true
    ) async throws -> (Data, HTTPURLResponse) {
        try await performRequest(
            path: path,
            method: method,
            queryItems: queryItems,
            jsonBody: jsonBody,
            rawBody: rawBody,
            auth: auth,
            accept: accept,
            contentType: contentType,
            acceptableStatus: acceptableStatus,
            requireJSONMime: requireJSONMime,
            logPayload: logPayload
        )
    }

    func performAuthenticatedRequest<T: Decodable>(
        path: String,
        method: String = "GET",
        queryItems: [URLQueryItem]? = nil,
        body: Any? = nil
    ) async throws -> T {
        try await performAuthenticatedRequest(path: path, method: method, queryItems: queryItems, body: body)
    }
}

@MainActor
class APIClient: APIClientProtocol {
    var host: String = ""
    var port: UInt16 = 0
    var authToken: String = ""
    var currentUserId: String = UserDefaults.standard.string(forKey: "currentUserId") ?? ""
    private let logger = Logger(subsystem: Bundle.main.bundleIdentifier ?? "mattermost.client", category: "APIClient")
    private let session: URLSession

    init(host: String = "", port: UInt16 = 0, session: URLSession = .shared) {
        self.host = host
        self.port = port
        self.session = session
    }

    func token() -> String? {
        return authToken.isEmpty ? nil : authToken
    }

    func isLogged() -> Bool {
        return !authToken.isEmpty
    }

    var webSocketURL: URL? {
        buildURL(path: "/api/v4/websocket", isWebSocket: true)
    }

    func buildURL(path: String, queryItems: [URLQueryItem]? = nil, isWebSocket: Bool = false) -> URL? {
        var cleanHost = host.trimmingCharacters(in: .whitespacesAndNewlines)
        while cleanHost.hasSuffix("/") {
            cleanHost.removeLast()
        }
        guard !cleanHost.isEmpty else { return nil }

        // HTTPS is the default. Cleartext HTTP must be opted into explicitly by
        // typing an http:// host (and is limited to local networks by ATS).
        if !cleanHost.contains("://") {
            cleanHost = "https://" + cleanHost
        }

        guard var components = URLComponents(string: cleanHost),
            let hostName = components.host, !hostName.isEmpty,
            let scheme = components.scheme?.lowercased(),
            scheme == "http" || scheme == "https"
        else {
            return nil
        }

        if isWebSocket {
            components.scheme = scheme == "https" ? "wss" : "ws"
        }
        // Prefer a port embedded in the host; otherwise use the configured port.
        // With no configured port the scheme default applies (443/80).
        if components.port == nil, port > 0 {
            components.port = Int(port)
        }
        // Preserve a reverse-proxy/subpath deployment (https://host/mattermost)
        // instead of replacing it with the API path.
        var basePath = components.path
        if basePath.hasSuffix("/") { basePath.removeLast() }
        let normalizedPath = path.hasPrefix("/") ? path : "/" + path
        components.path = basePath + normalizedPath
        if let queryItems = queryItems, !queryItems.isEmpty {
            components.queryItems = queryItems
        }
        return components.url
    }

    func teamInviteURL(team: MMTeam) -> URL? {
        guard let inviteId = team.invite_id, !inviteId.isEmpty else { return nil }
        return buildURL(
            path: "/signup_user_complete/",
            queryItems: [URLQueryItem(name: "id", value: inviteId)]
        )
    }

    /// Builds a URLRequest for the REST API with shared auth/header/body handling.
    func makeRequest(
        path: String,
        method: String = "GET",
        queryItems: [URLQueryItem]? = nil,
        jsonBody: Any? = nil,
        rawBody: Data? = nil,
        auth: APIRequestAuth = .requiredToken,
        accept: String? = "application/json",
        contentType: String? = nil
    ) throws -> URLRequest {
        guard let url = buildURL(path: path, queryItems: queryItems) else {
            throw WebServiceError.invalidHostname
        }

        var request = URLRequest(url: url)
        request.httpMethod = method

        let requestAuthToken: String?
        switch auth {
        case .none:
            requestAuthToken = nil
        case .optionalToken:
            requestAuthToken = authToken.isEmpty ? nil : authToken
        case .requiredToken:
            requestAuthToken = authToken
        case .bearer(let value):
            requestAuthToken = value
        }
        if let requestAuthToken = requestAuthToken, !requestAuthToken.isEmpty {
            request.setValue("Bearer " + requestAuthToken, forHTTPHeaderField: "Authorization")
        }
        if let accept = accept {
            request.setValue(accept, forHTTPHeaderField: "Accept")
        }
        if let contentType = contentType {
            request.setValue(contentType, forHTTPHeaderField: "Content-Type")
        }
        if let jsonBody = jsonBody {
            do {
                request.httpBody = try JSONSerialization.data(withJSONObject: jsonBody)
                if contentType == nil {
                    request.setValue("application/json", forHTTPHeaderField: "Content-Type")
                }
            } catch {
                throw WebServiceError.invalidRequestBody
            }
        } else if let rawBody = rawBody {
            request.httpBody = rawBody
        }
        return request
    }

    static func isAuthenticationFailure(_ error: Error) -> Bool {
        guard let wsError = error as? WebServiceError,
            case .httpStatus(let code, _) = wsError
        else { return false }
        return code == 401 || code == 403
    }

    @discardableResult
    static func decodeLogin(_ data: Data) -> MMUser? {
        try? JSONDecoder().decode(MMUser.self, from: data)
    }

    func performRequest(
        path: String,
        method: String = "GET",
        queryItems: [URLQueryItem]? = nil,
        jsonBody: Any? = nil,
        rawBody: Data? = nil,
        auth: APIRequestAuth = .requiredToken,
        accept: String? = "application/json",
        contentType: String? = nil,
        acceptableStatus: ClosedRange<Int> = 200...299,
        requireJSONMime: Bool = false,
        logPayload: Bool = true
    ) async throws -> (Data, HTTPURLResponse) {
        let request = try makeRequest(
            path: path,
            method: method,
            queryItems: queryItems,
            jsonBody: jsonBody,
            rawBody: rawBody,
            auth: auth,
            accept: accept,
            contentType: contentType
        )

        let logStatusPath = logPayload && path.contains("status")
        if logStatusPath {
            DebugLog.logSensitive("HTTP \(method) \(path) sending body=\(String(describing: jsonBody))")
        }

        let data: Data
        let response: URLResponse
        do {
            (data, response) = try await session.data(for: request)
        } catch {
            if logStatusPath {
                DebugLog.error("HTTP \(method) \(path) network error: \(error.localizedDescription)")
            }
            throw WebServiceError.networkError(error)
        }

        guard let httpResponse = response as? HTTPURLResponse else {
            throw WebServiceError.invalidResponse
        }

        if logStatusPath {
            DebugLog.logSensitive(
                "HTTP \(method) \(path) status=\(httpResponse.statusCode), body=\(String(decoding: data, as: UTF8.self))"
            )
        }

        guard acceptableStatus.contains(httpResponse.statusCode) else {
            var serverMsg: String?
            if let json = try? JSONSerialization.jsonObject(with: data) as? [String: Any],
                let msg = json["message"] as? String, !msg.isEmpty
            {
                serverMsg = msg
            }
            throw WebServiceError.httpStatus(code: httpResponse.statusCode, message: serverMsg)
        }

        if requireJSONMime, response.mimeType != "application/json" {
            throw WebServiceError.invalidMimeType(response.mimeType)
        }

        return (data, httpResponse)
    }

    func performAuthenticatedRequest<T: Decodable>(
        path: String,
        method: String = "GET",
        queryItems: [URLQueryItem]? = nil,
        body: Any? = nil
    ) async throws -> T {
        let (data, _) = try await performRequest(
            path: path,
            method: method,
            queryItems: queryItems,
            jsonBody: body
        )
        do {
            return try JSONDecoder().decode(T.self, from: data)
        } catch {
            throw WebServiceError.decodingError(error)
        }
    }

    @discardableResult
    func login(username: String, password: String, mfaToken: String? = nil) async throws -> MMUser {
        var body: [String: Any] = [
            "login_id": username,
            "password": password,
        ]
        if let mfaToken = mfaToken, !mfaToken.isEmpty {
            body["token"] = mfaToken
        }
        let (data, response) = try await performRequest(
            path: "/api/v4/users/login",
            method: "POST",
            jsonBody: body,
            auth: .none,
            acceptableStatus: 200...200,
            requireJSONMime: true,
            logPayload: false
        )

        self.authToken = response.value(forHTTPHeaderField: "Token") ?? ""

        do {
            let user = try JSONDecoder().decode(MMUser.self, from: data)
            self.currentUserId = user.id
            UserDefaults.standard.set(user.id, forKey: "currentUserId")
            return user
        } catch {
            throw WebServiceError.decodingError(error)
        }
    }

    @discardableResult
    func loginWithSessionToken(_ token: String) async throws -> MMUser {
        self.authToken = token
        do {
            let user: MMUser = try await performAuthenticatedRequest(path: "/api/v4/users/me")
            self.currentUserId = user.id
            UserDefaults.standard.set(user.id, forKey: "currentUserId")
            return user
        } catch {
            self.authToken = ""
            throw error
        }
    }

    func fetchClientConfigData() async -> Data? {
        try? await performRequest(
            path: "/api/v4/config/client",
            queryItems: [URLQueryItem(name: "format", value: "old")],
            auth: .none,
            accept: "application/json",
            logPayload: false
        ).0
    }

    func fetchLinkMetadata(url: URL) async -> MMLinkMetadata? {
        guard
            let (data, _) = try? await performRequest(
                path: "/api/v4/link_metadata",
                method: "POST",
                jsonBody: ["url": url.absoluteString],
                accept: "application/json",
                logPayload: false
            )
        else { return nil }
        return try? JSONDecoder().decode(MMLinkMetadata.self, from: data)
    }

    func checkToken(token: String) async -> Bool {
        do {
            let (data, _) = try await performRequest(
                path: "/api/v4/users/me",
                auth: .bearer(token),
                acceptableStatus: 200...200,
                requireJSONMime: true,
                logPayload: false
            )
            self.authToken = token
            if let user = try? JSONDecoder().decode(MMUser.self, from: data) {
                self.currentUserId = user.id
                UserDefaults.standard.set(user.id, forKey: "currentUserId")
            }
            logger.info("checkToken succeeded")
            return true
        } catch {
            logger.error("checkToken failed: \(error.localizedDescription)")
            if Self.isAuthenticationFailure(error) {
                return false
            }
            // Offline/DNS/timeout/5xx must not destroy the session. Keep the
            // token and let the workspace open in its reconnecting state.
            self.authToken = token
            return true
        }
    }

    // MARK: - Users

    func fetchCurrentUser() async throws -> MMUser {
        let user: MMUser = try await performAuthenticatedRequest(path: "/api/v4/users/me")
        self.currentUserId = user.id
        UserDefaults.standard.set(user.id, forKey: "currentUserId")
        return user
    }

    func fetchUsersByIds(_ userIds: [String]) async throws -> [MMUser] {
        guard !userIds.isEmpty else { return [] }
        return try await performAuthenticatedRequest(
            path: "/api/v4/users/ids",
            method: "POST",
            body: userIds
        )
    }

    func updateUserNotifyProps(userId: String, props: [String: String]) async throws {
        _ = try await performRequest(
            path: "/api/v4/users/\(userId)/notify_props",
            method: "PUT",
            jsonBody: props,
            accept: "application/json"
        )
    }

    private func encodedPathComponent(_ value: String) -> String {
        var allowed = CharacterSet.urlPathAllowed
        allowed.remove(charactersIn: "/?#")
        return value.addingPercentEncoding(withAllowedCharacters: allowed) ?? value
    }

    func fetchUser(userId: String) async throws -> MMUser {
        return try await performAuthenticatedRequest(path: "/api/v4/users/\(encodedPathComponent(userId))")
    }

    func fetchUserByUsername(_ username: String) async throws -> MMUser {
        return try await performAuthenticatedRequest(path: "/api/v4/users/username/\(encodedPathComponent(username))")
    }

    func fetchTeamUsers(teamId: String, page: Int = 0, perPage: Int = 100) async throws -> [MMUser] {
        return try await performAuthenticatedRequest(
            path: "/api/v4/users",
            queryItems: [
                URLQueryItem(name: "in_team", value: teamId),
                URLQueryItem(name: "page", value: String(page)),
                URLQueryItem(name: "per_page", value: String(perPage)),
                URLQueryItem(name: "active", value: "true"),
            ]
        )
    }

    func createDirectChannel(userId: String) async throws -> MMChannel {
        let myId =
            currentUserId.isEmpty
            ? (UserDefaults.standard.string(forKey: "currentUserId") ?? "")
            : currentUserId
        return try await performAuthenticatedRequest(
            path: "/api/v4/channels/direct",
            method: "POST",
            body: [myId, userId]
        )
    }

    func createGroupChannel(userIds: [String]) async throws -> MMChannel {
        let myId =
            currentUserId.isEmpty
            ? (UserDefaults.standard.string(forKey: "currentUserId") ?? "")
            : currentUserId
        var allIds = userIds
        if !myId.isEmpty && !allIds.contains(myId) {
            allIds.append(myId)
        }
        return try await performAuthenticatedRequest(
            path: "/api/v4/channels/group",
            method: "POST",
            body: allIds
        )
    }

    func searchUsers(term: String, teamId: String? = nil) async throws -> [MMUser] {
        var body: [String: Any] = [
            "term": term,
            "allow_inactive": false,
        ]
        if let teamId = teamId, !teamId.isEmpty {
            body["team_id"] = teamId
            body["in_team_id"] = teamId
        }
        return try await performAuthenticatedRequest(
            path: "/api/v4/users/search",
            method: "POST",
            body: body
        )
    }

    func fetchUserImage(userId: String) async throws -> Data {
        guard !userId.isEmpty else {
            throw WebServiceError.invalidRequestBody
        }
        let (data, _) = try await performRequest(
            path: "/api/v4/users/\(userId)/image",
            auth: .optionalToken,
            accept: nil,
            logPayload: false
        )
        return data
    }

    @discardableResult
    func updateUserStatus(userId: String = "", status: String, dndEndTime: Int64? = nil) async throws -> MMUserStatus {
        var resolvedUserId = userId
        if resolvedUserId.isEmpty || resolvedUserId == "me" || resolvedUserId == "usr" || resolvedUserId == "sample_usr"
        {
            if !currentUserId.isEmpty {
                resolvedUserId = currentUserId
            } else if let savedId = UserDefaults.standard.string(forKey: "currentUserId"), !savedId.isEmpty {
                resolvedUserId = savedId
            } else {
                let me = try await fetchCurrentUser()
                resolvedUserId = me.id
            }
        }
        guard !resolvedUserId.isEmpty else {
            throw WebServiceError.invalidRequestBody
        }
        var payload: [String: Any] = [
            "user_id": resolvedUserId,
            "status": status,
        ]
        if let dndEndTime = dndEndTime {
            let seconds = dndEndTime > 10_000_000_000 ? (dndEndTime / 1000) : dndEndTime
            payload["dnd_end_time"] = seconds
        }
        return try await performAuthenticatedRequest(
            path: "/api/v4/users/\(resolvedUserId)/status",
            method: "PUT",
            body: payload
        )
    }

    func fetchUserStatuses(userIds: [String]) async throws -> [MMUserStatus] {
        guard !userIds.isEmpty else { return [] }
        return try await performAuthenticatedRequest(
            path: "/api/v4/users/status/ids",
            method: "POST",
            body: userIds
        )
    }

    func fetchUserPreferences(userId: String) async throws -> [[String: String]] {
        return try await performAuthenticatedRequest(path: "/api/v4/users/\(userId)/preferences")
    }

    func deleteUserPreferences(userId: String, preferences: [[String: String]]) async throws {
        do {
            _ = try await performRequest(
                path: "/api/v4/users/\(userId)/preferences/delete",
                method: "POST",
                jsonBody: preferences
            )
            return
        } catch let error as WebServiceError {
            guard case .httpStatus = error else { throw error }
        }

        _ = try await performRequest(
            path: "/api/v4/users/\(userId)/preferences",
            method: "DELETE",
            jsonBody: preferences
        )
    }

    func saveUserPreferences(userId: String, preferences: [[String: String]]) async throws {
        let _: [[String: String]] = try await performAuthenticatedRequest(
            path: "/api/v4/users/\(userId)/preferences",
            method: "PUT",
            body: preferences
        )
    }

    func setCustomStatus(emoji: String, text: String, duration: String, expiresAt: String?) async throws {
        var body: [String: Any] = [
            "emoji": emoji,
            "text": text,
            "duration": duration,
        ]
        if let expiresAt = expiresAt {
            body["expires_at"] = expiresAt
        }
        struct StatusResponse: Decodable { let status: String? }
        let _: StatusResponse = try await performAuthenticatedRequest(
            path: "/api/v4/users/me/status/custom",
            method: "PUT",
            body: body
        )
    }

    func clearCustomStatus() async throws {
        _ = try await performRequest(
            path: "/api/v4/users/me/status/custom",
            method: "DELETE",
            accept: nil
        )
    }

    // MARK: - Teams

    func fetchTeams() async throws -> [MMTeam] {
        return try await performAuthenticatedRequest(path: "/api/v4/users/me/teams")
    }

    func createTeam(name: String, displayName: String) async throws -> MMTeam {
        return try await performAuthenticatedRequest(
            path: "/api/v4/teams",
            method: "POST",
            body: ["name": name, "display_name": displayName, "type": "O"]
        )
    }

    func sendTeamInvite(teamId: String, email: String) async throws {
        _ = try await performRequest(
            path: "/api/v4/teams/\(teamId)/invite/email",
            method: "POST",
            jsonBody: ["user_email": email]
        )
    }

    func fetchTeamsUnread(userId: String) async throws -> [MMTeamUnread] {
        return try await performAuthenticatedRequest(path: "/api/v4/users/\(userId)/teams/unread")
    }

    func leaveTeam(teamId: String, userId: String) async throws {
        struct StatusResponse: Decodable { let status: String? }
        let _: StatusResponse = try await performAuthenticatedRequest(
            path: "/api/v4/teams/\(teamId)/members/\(userId)",
            method: "DELETE"
        )
    }

    func fetchTeamByName(_ name: String) async throws -> MMTeam {
        return try await performAuthenticatedRequest(path: "/api/v4/teams/name/\(name)")
    }

    func addUserToTeam(teamId: String, userId: String) async throws {
        _ = try await performRequest(
            path: "/api/v4/teams/\(teamId)/members",
            method: "POST",
            jsonBody: ["team_id": teamId, "user_id": userId]
        )
    }

    func removeUserFromTeam(teamId: String, userId: String) async throws {
        try await leaveTeam(teamId: teamId, userId: userId)
    }

    func fetchTeamMembers(
        teamId: String,
        page: Int = 0,
        perPage: Int = TimelinePager.pageSize
    ) async throws -> [MMTeamMember] {
        return try await performAuthenticatedRequest(
            path: "/api/v4/teams/\(teamId)/members",
            queryItems: [
                URLQueryItem(name: "page", value: String(page)),
                URLQueryItem(name: "per_page", value: String(perPage)),
            ]
        )
    }

    func fetchTeamMember(teamId: String, userId: String) async throws -> MMTeamMember {
        return try await performAuthenticatedRequest(
            path: "/api/v4/teams/\(teamId)/members/\(userId)"
        )
    }

    func updateTeamMemberRoles(teamId: String, userId: String, roles: String) async throws {
        struct StatusResponse: Decodable { let status: String? }
        let _: StatusResponse = try await performAuthenticatedRequest(
            path: "/api/v4/teams/\(teamId)/members/\(userId)/roles",
            method: "PUT",
            body: ["roles": roles]
        )
    }

    func updateTeam(
        teamId: String,
        displayName: String,
        description: String? = nil,
        companyName: String? = nil,
        allowedDomains: String? = nil,
        allowOpenInvite: Bool? = nil
    ) async throws -> MMTeam {
        var body: [String: Any] = [
            "id": teamId,
            "display_name": displayName,
        ]
        if let description = description { body["description"] = description }
        if let companyName = companyName { body["company_name"] = companyName }
        if let allowedDomains = allowedDomains { body["allowed_domains"] = allowedDomains }
        if let allowOpenInvite = allowOpenInvite { body["allow_open_invite"] = allowOpenInvite }
        return try await performAuthenticatedRequest(
            path: "/api/v4/teams/\(teamId)",
            method: "PUT",
            body: body
        )
    }

    // MARK: - Channels

    func fetchChannels(teamId: String) async throws -> [MMChannel] {
        return try await performAuthenticatedRequest(path: "/api/v4/users/me/teams/\(teamId)/channels")
    }

    func fetchAllChannels() async throws -> [MMChannel] {
        return try await performAuthenticatedRequest(path: "/api/v4/users/me/channels")
    }

    func fetchPublicChannels(teamId: String, page: Int = 0, perPage: Int = 100) async throws -> [MMChannel] {
        return try await performAuthenticatedRequest(
            path: "/api/v4/teams/\(teamId)/channels",
            queryItems: [
                URLQueryItem(name: "page", value: String(page)),
                URLQueryItem(name: "per_page", value: String(perPage)),
            ]
        )
    }

    func fetchPrivateChannels(teamId: String, page: Int = 0, perPage: Int = 100) async throws -> [MMChannel] {
        return try await performAuthenticatedRequest(
            path: "/api/v4/teams/\(teamId)/channels/private",
            queryItems: [
                URLQueryItem(name: "page", value: String(page)),
                URLQueryItem(name: "per_page", value: String(perPage)),
            ]
        )
    }

    func requestToJoinChannel(channelId: String) async throws {
        do {
            _ = try await performRequest(
                path: "/api/v4/channels/\(channelId)/join_request",
                method: "POST"
            )
        } catch {
            let myId =
                currentUserId.isEmpty
                ? (UserDefaults.standard.string(forKey: "currentUserId") ?? "")
                : currentUserId
            _ = try await joinChannel(channelId: channelId, userId: myId)
        }
    }

    func leaveChannel(channelId: String, userId: String) async throws {
        _ = try await performRequest(
            path: "/api/v4/channels/\(channelId)/members/\(userId)",
            method: "DELETE",
            accept: nil
        )
    }

    func joinChannel(channelId: String, userId: String) async throws {
        let _: MMChannelMember = try await performAuthenticatedRequest(
            path: "/api/v4/channels/\(channelId)/members",
            method: "POST",
            body: ["user_id": userId]
        )
    }

    func fetchChannelMembers(channelId: String, page: Int = 0, perPage: Int = TimelinePager.pageSize) async throws
        -> [MMChannelMember]
    {
        let (data, _) = try await performRequest(
            path: "/api/v4/channels/\(channelId)/members",
            queryItems: [
                URLQueryItem(name: "page", value: String(page)),
                URLQueryItem(name: "per_page", value: String(perPage)),
            ]
        )
        return try JSONDecoder().decode([MMChannelMember].self, from: data)
    }

    func fetchChannelMemberships(userId: String, teamId: String, page: Int = 0, perPage: Int = 200) async throws
        -> [MMChannelMembership]
    {
        return try await performAuthenticatedRequest(
            path: "/api/v4/users/\(userId)/teams/\(teamId)/channels/members",
            queryItems: [
                URLQueryItem(name: "page", value: String(page)),
                URLQueryItem(name: "per_page", value: String(perPage)),
            ]
        )
    }

    func updateChannelNotifyProps(
        channelId: String,
        userId: String,
        props: [String: String]
    ) async throws {
        _ = try await performRequest(
            path: "/api/v4/channels/\(channelId)/members/\(userId)/notify_props",
            method: "PUT",
            jsonBody: props,
            accept: nil
        )
    }

    func markAllChannelsRead(userId: String, teamId: String) async throws {
        _ = try await performRequest(
            path: "/api/v4/users/\(userId)/teams/\(teamId)/read",
            method: "PUT",
            jsonBody: [String: String](),
            accept: nil
        )
    }

    func markChannelUnread(userId: String, channelId: String, postId: String) async throws {
        _ = try await performRequest(
            path: "/api/v4/users/\(userId)/channels/\(channelId)/posts/\(postId)/unread",
            method: "POST",
            jsonBody: [String: String](),
            accept: nil
        )
    }

    func markChannelViewed(channelId: String) async throws -> Int64? {
        struct ViewResponse: Decodable { let last_viewed_at_times: [String: Int64]? }
        let response: ViewResponse = try await performAuthenticatedRequest(
            path: "/api/v4/channels/members/me/view",
            method: "POST",
            body: ["channel_id": channelId, "collapsed_threads_supported": true]
        )
        return response.last_viewed_at_times?[channelId]
    }

    // MARK: - Sidebar Categories

    func fetchSidebarCategories(teamId: String) async throws -> MMSidebarCategoriesResponse {
        return try await performAuthenticatedRequest(path: "/api/v4/users/me/teams/\(teamId)/channels/categories")
    }

    func createSidebarCategory(
        teamId: String,
        displayName: String,
        userId: String
    ) async throws -> MMSidebarCategory {
        try await performAuthenticatedRequest(
            path: "/api/v4/users/\(userId)/teams/\(teamId)/channels/categories",
            method: "POST",
            body: [
                "display_name": displayName,
                "user_id": userId,
                "team_id": teamId,
                "type": "custom",
            ]
        )
    }

    func updateSidebarCategory(
        teamId: String,
        userId: String,
        categoryId: String,
        displayName: String? = nil,
        collapsed: Bool? = nil,
        muted: Bool? = nil
    ) async throws -> MMSidebarCategory {
        var body: [String: Any] = [:]
        if let displayName = displayName { body["display_name"] = displayName }
        if let collapsed = collapsed { body["collapsed"] = collapsed }
        if let muted = muted { body["muted"] = muted }
        return try await performAuthenticatedRequest(
            path: "/api/v4/users/\(userId)/teams/\(teamId)/channels/categories/\(categoryId)",
            method: "PUT",
            body: body
        )
    }

    func deleteSidebarCategory(
        teamId: String,
        userId: String,
        categoryId: String
    ) async throws {
        struct StatusResponse: Decodable { let status: String? }
        let _: StatusResponse = try await performAuthenticatedRequest(
            path: "/api/v4/users/\(userId)/teams/\(teamId)/channels/categories/\(categoryId)",
            method: "DELETE"
        )
    }

    func updateSidebarCategoryOrder(
        teamId: String,
        userId: String,
        categoryIds: [String]
    ) async throws {
        _ = try await performRequest(
            path: "/api/v4/users/\(userId)/teams/\(teamId)/channels/categories/order",
            method: "PUT",
            jsonBody: categoryIds,
            accept: nil
        )
    }

    func addChannelToSidebarCategory(
        teamId: String,
        userId: String,
        categoryId: String,
        channelId: String
    ) async throws {
        _ = try await performRequest(
            path: "/api/v4/users/\(userId)/teams/\(teamId)/channels/categories/\(categoryId)/channels",
            method: "POST",
            jsonBody: ["channel_id": channelId],
            accept: nil
        )
    }

    func removeChannelFromSidebarCategory(
        teamId: String,
        userId: String,
        categoryId: String,
        channelId: String
    ) async throws {
        _ = try await performRequest(
            path: "/api/v4/users/\(userId)/teams/\(teamId)/channels/categories/\(categoryId)/channels/\(channelId)",
            method: "DELETE",
            accept: nil
        )
    }

    // MARK: - Posts

    func fetchChannelPosts(
        channelId: String, page: Int = 0, perPage: Int = TimelinePager.pageSize, before: String? = nil
    ) async throws -> MMPostList {
        var queryItems = [
            URLQueryItem(name: "page", value: String(page)),
            URLQueryItem(name: "per_page", value: String(perPage)),
        ]
        if let before = before, !before.isEmpty {
            queryItems.append(URLQueryItem(name: "before", value: before))
        }
        return try await performAuthenticatedRequest(
            path: "/api/v4/channels/\(channelId)/posts",
            queryItems: queryItems
        )
    }

    func searchPosts(teamId: String, terms: String, page: Int = 0, perPage: Int = 50) async throws -> MMPostList {
        let body: [String: Any] = [
            "terms": terms,
            "is_or_search": false,
            "page": page,
            "per_page": perPage,
        ]
        return try await performAuthenticatedRequest(
            path: "/api/v4/teams/\(teamId)/posts/search",
            method: "POST",
            body: body
        )
    }

    func fetchPinnedPosts(channelId: String) async throws -> MMPostList {
        return try await performAuthenticatedRequest(path: "/api/v4/channels/\(channelId)/pinned")
    }

    func fetchFlaggedPosts(userId: String, teamId: String, page: Int = 0, perPage: Int = TimelinePager.pageSize)
        async throws -> MMPostList
    {
        return try await performAuthenticatedRequest(
            path: "/api/v4/users/\(userId)/posts/flagged",
            queryItems: [
                URLQueryItem(name: "team_id", value: teamId),
                URLQueryItem(name: "page", value: String(page)),
                URLQueryItem(name: "per_page", value: String(perPage)),
            ]
        )
    }

    @discardableResult
    func createPost(channelId: String, message: String, rootId: String? = nil, fileIds: [String] = []) async throws
        -> MMPost
    {
        var payload: [String: Any] = [
            "channel_id": channelId,
            "message": message,
        ]
        if let rootId = rootId, !rootId.isEmpty {
            payload["root_id"] = rootId
        }
        if !fileIds.isEmpty {
            payload["file_ids"] = fileIds
        }
        return try await performAuthenticatedRequest(
            path: "/api/v4/posts",
            method: "POST",
            body: payload
        )
    }

    @discardableResult
    func patchPost(postId: String, message: String) async throws -> MMPost {
        return try await performAuthenticatedRequest(
            path: "/api/v4/posts/\(postId)/patch",
            method: "PUT",
            body: ["message": message]
        )
    }

    func fetchPost(postId: String) async throws -> MMPost {
        return try await performAuthenticatedRequest(path: "/api/v4/posts/\(postId)")
    }

    func fetchPostThread(postId: String) async throws -> MMPostList {
        return try await performAuthenticatedRequest(path: "/api/v4/posts/\(postId)/thread")
    }

    func pinPost(postId: String) async throws {
        struct StatusResponse: Decodable { let status: String? }
        let _: StatusResponse = try await performAuthenticatedRequest(
            path: "/api/v4/posts/\(postId)/pin",
            method: "POST"
        )
    }

    func unpinPost(postId: String) async throws {
        struct StatusResponse: Decodable { let status: String? }
        let _: StatusResponse = try await performAuthenticatedRequest(
            path: "/api/v4/posts/\(postId)/unpin",
            method: "POST"
        )
    }

    func savePost(userId: String, postId: String) async throws {
        _ = try await performRequest(
            path: "/api/v4/users/\(userId)/posts/\(postId)/flag",
            method: "POST",
            accept: nil
        )
    }

    func unsavePost(userId: String, postId: String) async throws {
        _ = try await performRequest(
            path: "/api/v4/users/\(userId)/posts/\(postId)/flag",
            method: "DELETE",
            accept: nil
        )
    }

    func deletePost(postId: String) async throws {
        struct StatusResponse: Decodable { let status: String? }
        let _: StatusResponse = try await performAuthenticatedRequest(
            path: "/api/v4/posts/\(postId)",
            method: "DELETE"
        )
    }

    // MARK: - Reactions

    @discardableResult
    func addReaction(userId: String, postId: String, emojiName: String) async throws -> MMReaction {
        return try await performAuthenticatedRequest(
            path: "/api/v4/reactions",
            method: "POST",
            body: [
                "user_id": userId,
                "post_id": postId,
                "emoji_name": emojiName,
                "create_at": 0,
            ]
        )
    }

    func removeReaction(userId: String, postId: String, emojiName: String) async throws {
        struct StatusResponse: Decodable { let status: String? }
        let _: StatusResponse = try await performAuthenticatedRequest(
            path: "/api/v4/users/\(userId)/posts/\(postId)/reactions/\(encodedPathComponent(emojiName))",
            method: "DELETE"
        )
    }

    // MARK: - Threads

    func fetchThreads(userId: String, teamId: String, perPage: Int = TimelinePager.pageSize) async throws -> [MMThread]
    {
        try await fetchThreadsPage(userId: userId, teamId: teamId, perPage: perPage).threads
    }

    func fetchThreadsPage(userId: String, teamId: String, page: Int = 0, perPage: Int = TimelinePager.pageSize)
        async throws
        -> MMThreadsResponse
    {
        try await performAuthenticatedRequest(
            path: "/api/v4/users/\(userId)/teams/\(teamId)/threads",
            queryItems: [
                URLQueryItem(name: "page", value: String(page)),
                URLQueryItem(name: "per_page", value: String(perPage)),
            ]
        )
    }

    func markThreadRead(teamId: String, threadId: String) async throws {
        _ = try await performRequest(
            path: "/api/v4/users/me/teams/\(teamId)/threads/\(threadId)/read",
            method: "PUT",
            jsonBody: [String: String](),
            accept: nil
        )
    }

    // MARK: - Emojis

    func fetchCustomEmojis(page: Int = 0, perPage: Int = 200) async throws -> [MMEmoji] {
        return try await performAuthenticatedRequest(
            path: "/api/v4/emoji",
            queryItems: [
                URLQueryItem(name: "page", value: String(page)),
                URLQueryItem(name: "per_page", value: String(perPage)),
                URLQueryItem(name: "sort", value: "name"),
            ]
        )
    }

    func fetchEmojiImage(emojiId: String) async throws -> Data {
        let (data, _) = try await performRequest(
            path: "/api/v4/emoji/\(emojiId)/image",
            accept: nil,
            logPayload: false
        )
        return data
    }

    // MARK: - Plugins

    func fetchActivePluginIds() async throws -> [String] {
        struct PluginsResponse: Decodable {
            struct Plugin: Decodable { let id: String }
            let active: [Plugin]
        }
        let response: PluginsResponse = try await performAuthenticatedRequest(
            path: "/api/v4/plugins",
            queryItems: [URLQueryItem(name: "filter", value: "activated")]
        )
        return response.active.map { $0.id }
    }
}
