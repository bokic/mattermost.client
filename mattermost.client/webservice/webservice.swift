//
//  main.swift
//  mattermost_ws_test
//
//  Created by Boris Barbulovski on 11.3.23.
//

import Foundation
import os

enum DebugLogLevel: Int, Comparable {
    case debug = 0
    case info
    case warning
    case error

    static func < (lhs: DebugLogLevel, rhs: DebugLogLevel) -> Bool {
        lhs.rawValue < rhs.rawValue
    }

    var label: String {
        switch self {
        case .debug: return "DEBUG"
        case .info: return "INFO"
        case .warning: return "WARN"
        case .error: return "ERROR"
        }
    }
}

enum DebugLog {
    static var logPath: String {
        (NSTemporaryDirectory() as NSString).appendingPathComponent("mattermost_debug.log")
    }

    static var logArchivePath: String { logPath + ".1" }

    /// Verbose file/stdout logging ships only in Debug builds or when explicitly
    /// requested with `--debug-log` / the `debugFileLogging` default. Release
    /// builds still emit warnings and errors through `Logger`.
    static let isVerboseLoggingEnabled: Bool = {
        #if DEBUG
            return true
        #else
            return CommandLine.arguments.contains("--debug-log")
                || UserDefaults.standard.bool(forKey: "debugFileLogging")
        #endif
    }()

    /// Raw payload logging is off unless explicitly requested at launch
    /// (`--debug-ws`) or via the `debugWebSocketLogging` default.
    /// The flag is mutable for tests, so guard it with a lock instead of leaving
    /// nonisolated shared mutable state behind.
    private static let sensitiveLoggingState = OSAllocatedUnfairLock(
        initialState:
            CommandLine.arguments.contains("--debug-ws")
            || UserDefaults.standard.bool(forKey: "debugWebSocketLogging")
    )

    static var isSensitiveLoggingEnabled: Bool {
        get { sensitiveLoggingState.withLock { $0 } }
        set { sensitiveLoggingState.withLock { $0 = newValue } }
    }

    private static let logger = Logger(
        subsystem: Bundle.main.bundleIdentifier ?? "mattermost.client", category: "App")
    private static let fileLock = NSLock()
    private static let maxLogBytes = 1_000_000

    /// Logs only when sensitive/frame logging is enabled.
    static func logSensitive(_ message: @autoclosure () -> String) {
        guard isSensitiveLoggingEnabled else { return }
        log(.debug, message())
    }

    static func log(_ message: @autoclosure () -> String) {
        log(.debug, message())
    }

    static func info(_ message: @autoclosure () -> String) {
        log(.info, message())
    }

    static func warning(_ message: @autoclosure () -> String) {
        log(.warning, message())
    }

    static func error(_ message: @autoclosure () -> String) {
        log(.error, message())
    }

    static func log(_ level: DebugLogLevel, _ message: String) {
        switch level {
        case .debug: logger.debug("\(message, privacy: .private)")
        case .info: logger.info("\(message, privacy: .private)")
        case .warning: logger.warning("\(message, privacy: .private)")
        case .error: logger.error("\(message, privacy: .private)")
        }

        guard shouldWriteToFile(level, verbose: isVerboseLoggingEnabled) else { return }

        let timestamp = ISO8601DateFormatter().string(from: Date())
        let line = "[\(timestamp)] [\(level.label)] \(message)\n"

        print("[STATUS_LOG] \(line)", terminator: "")
        fflush(stdout)
        NSLog("[STATUS_LOG] %@", "[\(level.label)] \(message)")

        guard let data = line.data(using: .utf8) else { return }
        fileLock.lock()
        defer { fileLock.unlock() }
        rotateIfNeeded()
        if let fileHandle = FileHandle(forWritingAtPath: logPath) {
            fileHandle.seekToEndOfFile()
            fileHandle.write(data)
            try? fileHandle.close()
        } else {
            try? data.write(to: URL(fileURLWithPath: logPath), options: .atomic)
        }
    }

    /// Release builds persist warnings/errors; verbose levels need an explicit opt-in.
    static func shouldWriteToFile(_ level: DebugLogLevel, verbose: Bool) -> Bool {
        verbose || level >= .warning
    }

    private static func rotateIfNeeded() {
        let manager = FileManager.default
        guard let attributes = try? manager.attributesOfItem(atPath: logPath),
            let size = attributes[.size] as? NSNumber,
            size.intValue > maxLogBytes
        else { return }

        try? manager.removeItem(atPath: logArchivePath)
        try? manager.moveItem(atPath: logPath, toPath: logArchivePath)
    }
}

enum WebServiceError: LocalizedError {
    case invalidHostname
    case invalidRequestBody
    case invalidResponse
    case invalidMimeType(String?)
    case httpStatus(code: Int, message: String?)
    case decodingError(Error)
    case networkError(Error)

    var errorDescription: String? {
        switch self {
        case .invalidHostname:
            return "Invalid hostname."
        case .invalidRequestBody:
            return "Failed to serialize request body."
        case .invalidResponse:
            return "No valid HTTP response received."
        case .invalidMimeType(let mime):
            return "Invalid MIME type: \(mime ?? "unknown")."
        case .httpStatus(let code, let message):
            if let message = message, !message.isEmpty {
                return "\(message) (HTTP \(code))"
            }
            return "Invalid status code: \(code)"
        case .decodingError(let error):
            return "Failed to decode server response: \(error.localizedDescription)"
        case .networkError(let error):
            return "Network error: \(error.localizedDescription)"
        }
    }
}

struct MMTeam: Codable {
    let id: String
    let create_at: Int64?
    let update_at: Int64?
    let delete_at: Int64?
    let display_name: String
    let name: String
    let description: String?
    let email: String?
    let type: String?
    let company_name: String?
    let allowed_domains: String?
    let invite_id: String?
    let allow_open_invite: Bool?
}

struct MMChannel: Codable {
    let id: String
    let create_at: Int64?
    let update_at: Int64?
    let delete_at: Int64?
    let team_id: String?
    let type: String
    let display_name: String
    let name: String
    let header: String?
    let purpose: String?
    let last_post_at: Int64?
    let total_msg_count: Int64?
    let creator_id: String?
}

struct MMSidebarCategory: Codable {
    let id: String
    let user_id: String?
    let team_id: String?
    let sort_order: Int?
    let sorting: String?
    let type: String
    let display_name: String
    let muted: Bool?
    let collapsed: Bool?
    let channel_ids: [String]
}

struct MMSidebarCategoriesResponse: Codable {
    let categories: [MMSidebarCategory]
    let order: [String]
}

struct MMFileInfo: Codable {
    let id: String
    let name: String?
    let `extension`: String?
    let mime_type: String?
    let size: Int64?
    let width: Int?
    let height: Int?
    // Present on file-search results but absent from post metadata.
    let user_id: String?
    let post_id: String?
    let channel_id: String?
    let create_at: Int64?
    let has_preview_image: Bool?
}

struct MMFileSearchResult: Decodable {
    let order: [String]
    let file_infos: [String: MMFileInfo]
    let next_file_info_id: String?
    let prev_file_info_id: String?
}

struct MMEmoji: Decodable {
    let id: String
    let name: String
    let creator_id: String?
}

struct MMReaction: Codable {
    let user_id: String?
    let post_id: String?
    let emoji_name: String?
    let create_at: Int64?
}

struct MMPostMetadata: Codable {
    let files: [MMFileInfo]?
    let reactions: [MMReaction]?
}

struct MMPost: Codable {
    let id: String
    let create_at: Int64
    let update_at: Int64?
    let edit_at: Int64?
    let delete_at: Int64?
    let is_pinned: Bool?
    let user_id: String
    let channel_id: String
    let root_id: String?
    let original_id: String?
    let message: String
    let type: String?
    var file_ids: [String]? = nil
    var metadata: MMPostMetadata? = nil
}

struct MMThreadParticipant: Decodable {
    let id: String?
    let username: String?
}

struct MMThread: Decodable {
    let id: String
    let reply_count: Int?
    let last_reply_at: Int64?
    let last_viewed_at: Int64?
    let participants: [MMThreadParticipant]?
    let post: MMPost?
}

struct MMThreadsResponse: Decodable {
    let threads: [MMThread]
    let total: Int?
    let total_unread_threads: Int?
    let total_unread_mentions: Int?
}

struct MMChannelMembership: Decodable {
    struct NotifyProps: Decodable {
        let desktop: String?
        let mark_unread: String?
        let ignore_channel_mentions: String?
    }

    let channel_id: String
    let msg_count: Int?
    let mention_count: Int?
    let last_viewed_at: Int64?
    let last_update_at: Int64?
    let notify_props: NotifyProps?
}

struct MMChannelMember: Decodable {
    let user_id: String
    let channel_id: String
    let roles: String?
}

struct MMPostList: Codable {
    let order: [String]
    let posts: [String: MMPost]
    let next_post_id: String?
    let prev_post_id: String?
    
    var chronologicalPosts: [MMPost] {
        return order.reversed().compactMap { posts[$0] }
    }
}

struct MMUserStatus: Codable {
    let user_id: String
    let status: String
    let manual: Bool?
    let last_activity_at: Int64?
    let active_channel: String?
    let dnd_end_time: Int64?
}

enum MMWebSocketEvent {
    case hello
    case posted(post: MMPost, senderName: String?, channelDisplayName: String?, channelName: String?, teamId: String?)
    case postEdited(post: MMPost)
    case postDeleted(postId: String, channelId: String)
    case postUnread(channelId: String)
    case channelViewed(channelId: String)
    case channelUpdated(channel: MMChannel)
    case channelMembershipChanged(channelId: String, userId: String)
    case preferencesChanged(userId: String)
    case threadUpdated(rootId: String)
    case emojiAdded
    case statusChange(userId: String, status: String)
    case userStatuses(statuses: [String: String])
    case typing(userId: String, channelId: String, parentId: String?)
    case updateTeam(team: MMTeam)
    case addedToTeam(teamId: String, userId: String)
    case leaveTeam(teamId: String, userId: String)
    case sidebarCategoriesUpdated
    case reactionChanged(postId: String)
    case other(event: String, data: [String: Any])
}

struct LoginWebService: Codable {
    let id: String
    let create_at: Int64?
    let update_at: Int64?
    let delete_at: Int64?
    let username: String
    let first_name: String?
    let last_name: String?
    let nickname: String?
    let email: String?
    let email_verified: Bool?
    let auth_service: String?
    let roles: String?
    let locale: String?
    let position: String?
    let is_bot: Bool?
    let last_password_update: Int64?
    let remote_id: String?
    let disable_welcome_email: Bool?
    
    let notify_props: Notify_Props?
    var props: [String: String]? = nil
    struct Notify_Props: Codable {
        let channel: String?
        let comments: String?
        let desktop: String?
        let desktop_sound: String?
        let desktop_threads: String?
        let email: String?
        let email_threads: String?
        let first_name: String?
        let mention_keys: String?
        let push: String?
        let push_status: String?
        let push_threads: String?
    }
    
    let timezone: TimeZone?
    struct TimeZone: Codable {
        let useAutomaticTimezone: String?
        let manualTimezone: String?
        let automaticTimezone: String?
    }
    
    let auth_data: String?
}

typealias webservice = WebService

/// All REST and WebSocket state (`mToken`, the socket task, ping/reconnect
/// timers and event callbacks) is main-actor isolated. Network work still runs
/// off the main thread inside URLSession; callbacks hop back explicitly.
@MainActor
final class WebService: NSObject {
    var mHost: String = ""
    var mPort: UInt16 = 0
    var mToken: String = ""
    var mConnected: Bool = false
    var currentUserId: String = UserDefaults.standard.string(forKey: "currentUserId") ?? ""
    private let logger = Logger(subsystem: Bundle.main.bundleIdentifier ?? "mattermost.client", category: "WebService")

    override init() {
        super.init()
    }
    
    init(host: String, port: UInt16) {
        super.init()
        
        self.mHost = host
        self.mPort = port
    }

    func token() -> String? {
        return mToken
    }
    
    private func updateToken(token: String) {
        mToken = token
        mConnected = !mToken.isEmpty
    }
    
    func isLogged() -> Bool {
        return !mToken.isEmpty
    }
    
    func buildURL(path: String, queryItems: [URLQueryItem]? = nil, isWebSocket: Bool = false) -> URL? {
        var cleanHost = mHost.trimmingCharacters(in: .whitespacesAndNewlines)
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
              let host = components.host, !host.isEmpty,
              let scheme = components.scheme?.lowercased(),
              scheme == "http" || scheme == "https" else {
            return nil
        }
        
        if isWebSocket {
            components.scheme = scheme == "https" ? "wss" : "ws"
        }
        // Prefer a port embedded in the host; otherwise use the configured port.
        // With no configured port the scheme default applies (443/80).
        if components.port == nil, mPort > 0 {
            components.port = Int(mPort)
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
    
    /// How a request should authenticate.
    private enum RequestAuth {
        case none
        case optionalToken
        case requiredToken
        case bearer(String)
    }

    /// Builds a URLRequest for the REST API with shared auth/header/body handling.
    private func makeRequest(
        path: String,
        method: String = "GET",
        queryItems: [URLQueryItem]? = nil,
        jsonBody: Any? = nil,
        rawBody: Data? = nil,
        auth: RequestAuth = .requiredToken,
        accept: String? = "application/json",
        contentType: String? = nil
    ) throws -> URLRequest {
        guard let url = buildURL(path: path, queryItems: queryItems) else {
            throw WebServiceError.invalidHostname
        }

        var request = URLRequest(url: url)
        request.httpMethod = method

        let token: String?
        switch auth {
        case .none:
            token = nil
        case .optionalToken:
            token = mToken.isEmpty ? nil : mToken
        case .requiredToken:
            token = mToken
        case .bearer(let value):
            token = value
        }
        if let token = token, !token.isEmpty {
            request.setValue("Bearer " + token, forHTTPHeaderField: "Authorization")
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

    /// Runs a request and applies the shared network/status/error handling.
    private func performRequest(
        path: String,
        method: String = "GET",
        queryItems: [URLQueryItem]? = nil,
        jsonBody: Any? = nil,
        rawBody: Data? = nil,
        auth: RequestAuth = .requiredToken,
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
            (data, response) = try await URLSession.shared.data(for: request)
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
            DebugLog.logSensitive("HTTP \(method) \(path) status=\(httpResponse.statusCode), body=\(String(decoding: data, as: UTF8.self))")
        }

        guard acceptableStatus.contains(httpResponse.statusCode) else {
            var serverMsg: String?
            if let json = try? JSONSerialization.jsonObject(with: data) as? [String: Any],
               let msg = json["message"] as? String, !msg.isEmpty {
                serverMsg = msg
            }
            throw WebServiceError.httpStatus(code: httpResponse.statusCode, message: serverMsg)
        }

        if requireJSONMime, response.mimeType != "application/json" {
            throw WebServiceError.invalidMimeType(response.mimeType)
        }

        return (data, httpResponse)
    }

    private func performAuthenticatedRequest<T: Decodable>(
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
    func login(username: String, password: String) async throws -> LoginWebService {
        let (data, response) = try await performRequest(
            path: "/api/v4/users/login",
            method: "POST",
            jsonBody: ["login_id": username, "password": password],
            auth: .none,
            acceptableStatus: 200...200,
            requireJSONMime: true,
            logPayload: false
        )

        updateToken(token: response.value(forHTTPHeaderField: "Token") ?? "")

        do {
            let user = try JSONDecoder().decode(LoginWebService.self, from: data)
            self.currentUserId = user.id
            UserDefaults.standard.set(user.id, forKey: "currentUserId")
            return user
        } catch {
            throw WebServiceError.decodingError(error)
        }
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
            updateToken(token: token)
            if let user = try? JSONDecoder().decode(LoginWebService.self, from: data) {
                self.currentUserId = user.id
                UserDefaults.standard.set(user.id, forKey: "currentUserId")
            }
            logger.info("checkToken succeeded")
            return true
        } catch {
            logger.error("checkToken failed: \(error.localizedDescription)")
            if let wsError = error as? WebServiceError,
               case .httpStatus(let code, _) = wsError,
               code == 401 || code == 403 {
                return false
            }
            // Offline/DNS/timeout/5xx must not destroy the session. Keep the
            // token and let the workspace open in its reconnecting state.
            updateToken(token: token)
            return true
        }
    }

    // MARK: - Users, Teams, Channels, Categories & Posts REST API
    
    func fetchCurrentUser() async throws -> LoginWebService {
        let user: LoginWebService = try await performAuthenticatedRequest(path: "/api/v4/users/me")
        self.currentUserId = user.id
        UserDefaults.standard.set(user.id, forKey: "currentUserId")
        return user
    }
    
    func fetchUsersByIds(_ userIds: [String]) async throws -> [LoginWebService] {
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

    func fetchUserByUsername(_ username: String) async throws -> LoginWebService {
        return try await performAuthenticatedRequest(path: "/api/v4/users/username/\(encodedPathComponent(username))")
    }

    /// Team members used by the Direct Message picker.
    func fetchTeamUsers(teamId: String, page: Int = 0, perPage: Int = 100) async throws -> [LoginWebService] {
        return try await performAuthenticatedRequest(
            path: "/api/v4/users",
            queryItems: [
                URLQueryItem(name: "in_team", value: teamId),
                URLQueryItem(name: "page", value: String(page)),
                URLQueryItem(name: "per_page", value: String(perPage)),
                URLQueryItem(name: "active", value: "true")
            ]
        )
    }

    /// Creates (or returns) the direct channel between the current user and `userId`.
    func createDirectChannel(userId: String) async throws -> MMChannel {
        let myId = currentUserId.isEmpty
            ? (UserDefaults.standard.string(forKey: "currentUserId") ?? "")
            : currentUserId
        return try await performAuthenticatedRequest(
            path: "/api/v4/channels/direct",
            method: "POST",
            body: [myId, userId]
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
        if resolvedUserId.isEmpty || resolvedUserId == "me" || resolvedUserId == "usr" || resolvedUserId == "sample_usr" {
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
            "status": status
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
    
    func fetchTeams() async throws -> [MMTeam] {
        return try await performAuthenticatedRequest(path: "/api/v4/users/me/teams")
    }
    
    func fetchChannels(teamId: String) async throws -> [MMChannel] {
        return try await performAuthenticatedRequest(path: "/api/v4/users/me/teams/\(teamId)/channels")
    }
    
    func fetchAllChannels() async throws -> [MMChannel] {
        return try await performAuthenticatedRequest(path: "/api/v4/users/me/channels")
    }
    
    func fetchSidebarCategories(teamId: String) async throws -> MMSidebarCategoriesResponse {
        return try await performAuthenticatedRequest(path: "/api/v4/users/me/teams/\(teamId)/channels/categories")
    }
    
    func searchPosts(teamId: String, terms: String, page: Int = 0, perPage: Int = 50) async throws -> MMPostList {
        let body: [String: Any] = [
            "terms": terms,
            "is_or_search": false,
            "page": page,
            "per_page": perPage
        ]
        return try await performAuthenticatedRequest(
            path: "/api/v4/teams/\(teamId)/posts/search",
            method: "POST",
            body: body
        )
    }
    
    func fetchUserPreferences(userId: String) async throws -> [[String: String]] {
        return try await performAuthenticatedRequest(path: "/api/v4/users/\(userId)/preferences")
    }
    
    func deleteUserPreferences(userId: String, preferences: [[String: String]]) async throws {
        // Newer servers expose POST /preferences/delete; older ones accept a
        // DELETE against /preferences with the same body.
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
    
    func leaveChannel(channelId: String, userId: String) async throws {
        _ = try await performRequest(
            path: "/api/v4/channels/\(channelId)/members/\(userId)",
            method: "DELETE",
            accept: nil
        )
    }
    
    func fetchChannelMembers(channelId: String, page: Int = 0, perPage: Int = 60) async throws -> [MMChannelMember] {
        // Decoded loosely because member objects carry many optional fields.
        let (data, _) = try await performRequest(
            path: "/api/v4/channels/\(channelId)/members",
            queryItems: [
                URLQueryItem(name: "page", value: String(page)),
                URLQueryItem(name: "per_page", value: String(perPage))
            ]
        )
        return try JSONDecoder().decode([MMChannelMember].self, from: data)
    }
    
    func fetchPinnedPosts(channelId: String) async throws -> MMPostList {
        return try await performAuthenticatedRequest(path: "/api/v4/channels/\(channelId)/pinned")
    }
    
    func joinChannel(channelId: String, userId: String) async throws {
        let _: MMChannelMember = try await performAuthenticatedRequest(
            path: "/api/v4/channels/\(channelId)/members",
            method: "POST",
            body: ["user_id": userId]
        )
    }
    
    func fetchFlaggedPosts(userId: String, teamId: String, page: Int = 0, perPage: Int = 60) async throws -> MMPostList {
        return try await performAuthenticatedRequest(
            path: "/api/v4/users/\(userId)/posts/flagged",
            queryItems: [
                URLQueryItem(name: "team_id", value: teamId),
                URLQueryItem(name: "page", value: String(page)),
                URLQueryItem(name: "per_page", value: String(perPage))
            ]
        )
    }
    
    func setCustomStatus(emoji: String, text: String, duration: String, expiresAt: String?) async throws {
        var body: [String: Any] = [
            "emoji": emoji,
            "text": text,
            "duration": duration
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

    /// Marks every channel in a team as read for the current user.
    func markAllChannelsRead(userId: String, teamId: String) async throws {
        _ = try await performRequest(
            path: "/api/v4/users/\(userId)/teams/\(teamId)/read",
            method: "PUT",
            jsonBody: [String: String](),
            accept: nil
        )
    }

    /// Marks a channel unread from a specific post for the current user.
    func markChannelUnread(userId: String, channelId: String, postId: String) async throws {
        _ = try await performRequest(
            path: "/api/v4/users/\(userId)/channels/\(channelId)/posts/\(postId)/unread",
            method: "POST",
            jsonBody: [String: String](),
            accept: nil
        )
    }
    
    func fetchChannelMemberships(userId: String, teamId: String, page: Int = 0, perPage: Int = 200) async throws -> [MMChannelMembership] {
        return try await performAuthenticatedRequest(
            path: "/api/v4/users/\(userId)/teams/\(teamId)/channels/members",
            queryItems: [
                URLQueryItem(name: "page", value: String(page)),
                URLQueryItem(name: "per_page", value: String(perPage))
            ]
        )
    }
    
    /// Marks a channel as viewed; returns the server's new last_viewed_at.
    func markChannelViewed(channelId: String) async throws -> Int64? {
        struct ViewResponse: Decodable { let last_viewed_at_times: [String: Int64]? }
        let response: ViewResponse = try await performAuthenticatedRequest(
            path: "/api/v4/channels/members/me/view",
            method: "POST",
            body: ["channel_id": channelId, "collapsed_threads_supported": true]
        )
        return response.last_viewed_at_times?[channelId]
    }
    
    func fetchFileData(fileId: String, preview: Bool = false) async throws -> Data {
        let path = preview ? "/api/v4/files/\(fileId)/preview" : "/api/v4/files/\(fileId)"
        let (data, _) = try await performRequest(path: path, accept: nil, logPayload: false)
        return data
    }
    
    func fetchPublicChannels(teamId: String, page: Int = 0, perPage: Int = 100) async throws -> [MMChannel] {
        return try await performAuthenticatedRequest(
            path: "/api/v4/teams/\(teamId)/channels",
            queryItems: [
                URLQueryItem(name: "page", value: String(page)),
                URLQueryItem(name: "per_page", value: String(perPage))
            ]
        )
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
    
    func uploadFile(channelId: String, data: Data, filename: String, mimeType: String) async throws -> String {
        let boundary = "Boundary-\(UUID().uuidString)"
        // Multipart headers cannot contain quotes/CR/LF; sanitize server-visible
        // filenames so they cannot break out of the header.
        let safeFilename = (filename as NSString).lastPathComponent
            .components(separatedBy: CharacterSet(charactersIn: "\r\n\"\\"))
            .joined(separator: "_")
        let safeMimeType = mimeType.components(separatedBy: CharacterSet(charactersIn: "\r\n"))
            .joined(separator: " ")
        var body = Data()
        func append(_ text: String) { body.append(Data(text.utf8)) }
        append("--\(boundary)\r\n")
        append("Content-Disposition: form-data; name=\"files\"; filename=\"\(safeFilename)\"\r\n")
        append("Content-Type: \(safeMimeType)\r\n\r\n")
        body.append(data)
        append("\r\n--\(boundary)--\r\n")
        
        struct UploadResponse: Decodable {
            struct FileInfo: Decodable { let id: String }
            let file_infos: [FileInfo]
        }
        let (responseData, _) = try await performRequest(
            path: "/api/v4/files",
            method: "POST",
            queryItems: [URLQueryItem(name: "channel_id", value: channelId)],
            rawBody: body,
            contentType: "multipart/form-data; boundary=\(boundary)"
        )
        let decoded = try JSONDecoder().decode(UploadResponse.self, from: responseData)
        guard let fileId = decoded.file_infos.first?.id else {
            throw WebServiceError.invalidResponse
        }
        return fileId
    }
    
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
    
    func fetchThreads(userId: String, teamId: String, perPage: Int = 60) async throws -> [MMThread] {
        try await fetchThreadsPage(userId: userId, teamId: teamId, perPage: perPage).threads
    }

    func fetchThreadsPage(userId: String, teamId: String, page: Int = 0, perPage: Int = 60) async throws -> MMThreadsResponse {
        try await performAuthenticatedRequest(
            path: "/api/v4/users/\(userId)/teams/\(teamId)/threads",
            queryItems: [
                URLQueryItem(name: "page", value: String(page)),
                URLQueryItem(name: "per_page", value: String(perPage))
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
    
    func fetchChannelPosts(channelId: String, page: Int = 0, perPage: Int = TimelinePager.pageSize, before: String? = nil) async throws -> MMPostList {
        var queryItems = [
            URLQueryItem(name: "page", value: String(page)),
            URLQueryItem(name: "per_page", value: String(perPage))
        ]
        if let before = before, !before.isEmpty {
            queryItems.append(URLQueryItem(name: "before", value: before))
        }
        return try await performAuthenticatedRequest(
            path: "/api/v4/channels/\(channelId)/posts",
            queryItems: queryItems
        )
    }
    
    @discardableResult
    func createPost(channelId: String, message: String, rootId: String? = nil, fileIds: [String] = []) async throws -> MMPost {
        var payload: [String: Any] = [
            "channel_id": channelId,
            "message": message
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

    /// Returns the root post plus every reply of a thread.
    func fetchPostThread(postId: String) async throws -> MMPostList {
        return try await performAuthenticatedRequest(path: "/api/v4/posts/\(postId)/thread")
    }

    /// Recent files in a channel, using the same search the web RHS uses.
    func searchChannelFiles(teamId: String, channelId: String, page: Int = 0, perPage: Int = 60) async throws -> [MMFileInfo] {
        let result: MMFileSearchResult = try await performAuthenticatedRequest(
            path: "/api/v4/teams/\(teamId)/files/search",
            method: "POST",
            body: [
                "terms": "channel:\(channelId)",
                "is_or_search": false,
                "page": page,
                "per_page": perPage,
                "time_zone_offset": 0
            ]
        )
        return result.order.compactMap { result.file_infos[$0] }
    }

    /// Searches files across the whole team (the global Search → Files tab).
    func searchTeamFiles(teamId: String, terms: String, page: Int = 0, perPage: Int = 60) async throws -> [MMFileInfo] {
        let result: MMFileSearchResult = try await performAuthenticatedRequest(
            path: "/api/v4/teams/\(teamId)/files/search",
            method: "POST",
            body: [
                "terms": terms,
                "is_or_search": false,
                "page": page,
                "per_page": perPage,
                "time_zone_offset": 0
            ]
        )
        return result.order.compactMap { result.file_infos[$0] }
    }

    /// Custom emoji uploaded to the server.
    func fetchCustomEmojis(page: Int = 0, perPage: Int = 200) async throws -> [MMEmoji] {
        return try await performAuthenticatedRequest(
            path: "/api/v4/emoji",
            queryItems: [
                URLQueryItem(name: "page", value: String(page)),
                URLQueryItem(name: "per_page", value: String(perPage)),
                URLQueryItem(name: "sort", value: "name")
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
                "create_at": 0
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

    // MARK: - Post actions

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
    
    // MARK: - WebSocket Logic
    
    private var webSocketTask: URLSessionWebSocketTask?
    private var wsSequence: Int = 1
    private var pingTimer: Timer?
    private var reconnectTimer: Timer?
    private var reconnectAttempts = 0
    
    // Callbacks for WebSocket events
    var onWebSocketMessage: ((String) -> Void)?
    private(set) var isWebSocketConnected = false
    var onWebSocketStateChanged: ((Bool, String) -> Void)?
    var onWebSocketConnected: (() -> Void)?
    var onWebSocketDisconnected: ((Error?) -> Void)?
    var onWebSocketEvent: ((MMWebSocketEvent) -> Void)?
    var onPostReceived: ((MMPost, String?) -> Void)?
    var onStatusChanged: ((String, String) -> Void)?
    var onMultipleStatusesReceived: (([String: String]) -> Void)?
    var onUserTyping: ((String, String, String?) -> Void)?
    var onTeamUpdated: ((MMTeam) -> Void)?
    var onUserTeamsChanged: (() -> Void)?
    var onSidebarCategoriesUpdated: (() -> Void)?
    var onReactionChanged: ((String) -> Void)?
    
    private func notifySocketState(_ connected: Bool, _ message: String) {
        DebugLog.info("WS STATE notify connected=\(connected) msg=\(message)")
        isWebSocketConnected = connected
        DispatchQueue.main.async { [weak self] in
            self?.onWebSocketStateChanged?(connected, message)
        }
    }
    
    func connectWebSocket() {
        guard !mToken.isEmpty else { return }
        
        guard let url = buildURL(path: "/api/v4/websocket", isWebSocket: true) else {
            logger.error("Invalid WebSocket URL")
            return
        }
        
        disconnectWebSocket()
        wsSequence = 1
        
        var request = URLRequest(url: url)
        request.setValue("Bearer " + mToken, forHTTPHeaderField: "Authorization")
        
        let task = URLSession.shared.webSocketTask(with: request)
        webSocketTask = task
        task.resume()
        notifySocketState(false, "Connecting to Mattermost…")
        
        receiveWebSocketMessage(from: task)
        sendWebSocketAuthentication(token: mToken)
        startPingTimer()
    }
    
    func disconnectWebSocket() {
        stopPingTimer()
        reconnectTimer?.invalidate()
        reconnectTimer = nil
        webSocketTask?.cancel(with: .goingAway, reason: nil)
        webSocketTask = nil
        notifySocketState(false, "Disconnected from Mattermost")
    }
    
    private func startPingTimer() {
        stopPingTimer()
        pingTimer = Timer.scheduledTimer(withTimeInterval: 25.0, repeats: true) { [weak self] _ in
            MainActor.assumeIsolated {
                guard let self = self, let task = self.webSocketTask, task.state == .running else { return }
                task.sendPing { [weak self] error in
                    guard let error = error else { return }
                    Task { @MainActor in
                        self?.logger.error("WebSocket ping failed: \(error.localizedDescription)")
                        self?.scheduleReconnect()
                    }
                }
            }
        }
    }
    
    private func stopPingTimer() {
        pingTimer?.invalidate()
        pingTimer = nil
    }
    
    private func scheduleReconnect() {
        guard isLogged(), reconnectTimer == nil else { return }
        stopPingTimer()
        webSocketTask?.cancel(with: .goingAway, reason: nil)
        webSocketTask = nil
        
        // Exponential backoff with jitter: 1s, 2s, 4s … capped at 30s.
        let delay = min(30.0, pow(2.0, Double(reconnectAttempts))) + Double.random(in: 0...1)
        reconnectAttempts += 1
        DebugLog.warning("WS RECONNECT in \(String(format: "%.1f", delay))s (attempt \(reconnectAttempts))")
        
        reconnectTimer = Timer.scheduledTimer(withTimeInterval: delay, repeats: false) { [weak self] _ in
            MainActor.assumeIsolated {
                guard let self = self else { return }
                self.reconnectTimer = nil
                self.connectWebSocket()
            }
        }
    }
    
    /// Reconnects immediately when the machine wakes or the network returns.
    func reconnectIfNeeded() {
        guard isLogged() else { return }
        if let task = webSocketTask, task.state == .running { return }
        reconnectTimer?.invalidate()
        reconnectTimer = nil
        connectWebSocket()
    }
    
    func sendWebSocketMessage(action: String, data: [String: Any]) {
        let message: [String: Any] = [
            "seq": wsSequence,
            "action": action,
            "data": data
        ]
        let currentSeq = wsSequence
        wsSequence += 1
        
        do {
            let jsonData = try JSONSerialization.data(withJSONObject: message)
            if let jsonString = String(data: jsonData, encoding: .utf8) {
                DebugLog.logSensitive("WS SEND [seq=\(currentSeq)]: action=\(action) payload=\(jsonString)")
                let wsMessage = URLSessionWebSocketTask.Message.string(jsonString)
                webSocketTask?.send(wsMessage) { [weak self] error in
                    if let error = error {
                        DebugLog.error("WS SEND ERROR [seq=\(currentSeq)]: \(error.localizedDescription)")
                        self?.logger.error("WebSocket send error: \(error.localizedDescription)")
                    }
                }
            }
        } catch {
            DebugLog.error("WS SEND SERIALIZATION ERROR for action=\(action)")
            logger.error("Failed to serialize WebSocket message")
        }
    }
    
    func requestStatuses() {
        sendWebSocketMessage(action: "get_statuses", data: [:])
    }
    
    func requestStatusesByIds(_ userIds: [String]) {
        guard !userIds.isEmpty else { return }
        sendWebSocketMessage(action: "get_statuses_by_ids", data: ["user_ids": userIds])
    }
    
    func sendUserTyping(channelId: String, parentId: String = "") {
        sendWebSocketMessage(
            action: "user_typing",
            data: [
                "channel_id": channelId,
                "parent_id": parentId
            ]
        )
    }
    
    private func sendWebSocketAuthentication(token: String) {
        sendWebSocketMessage(action: "authentication_challenge", data: ["token": token])
    }
    
    private nonisolated func receiveWebSocketMessage(from task: URLSessionWebSocketTask) {
        task.receive { result in
            // URLSession delivers this on a background queue, so hand the
            // Sendable text/error back to the main actor before touching state.
            switch result {
            case .failure(let error):
                Task { @MainActor in
                    self.handleWebSocketFailure(error, task: task)
                }
            case .success(let message):
                let text: String?
                switch message {
                case .string(let value):
                    text = value
                case .data(let data):
                    text = String(data: data, encoding: .utf8)
                @unknown default:
                    text = nil
                }
                Task { @MainActor in
                    self.handleWebSocketText(text, task: task)
                }
            }
        }
    }

    private func handleWebSocketText(_ text: String?, task: URLSessionWebSocketTask) {
        guard task === webSocketTask else { return }
        if let text = text {
            DebugLog.logSensitive("WS RECV: \(text)")
            handleIncomingWebSocketMessage(text)
        }
        if webSocketTask != nil {
            receiveWebSocketMessage(from: task)
        }
    }

    private func handleWebSocketFailure(_ error: Error, task: URLSessionWebSocketTask) {
        guard task === webSocketTask else { return }
        DebugLog.error("WS RECV FAILURE: \(error.localizedDescription)")
        logger.error("WebSocket receive error: \(error.localizedDescription)")
        onWebSocketDisconnected?(error)
        notifySocketState(false, "Reconnecting to Mattermost…")
        scheduleReconnect()
    }
    
    private func decodeWebSocketPost(_ value: Any?) -> MMPost? {
        if let postJSONString = value as? String,
           let postData = postJSONString.data(using: .utf8) {
            return try? JSONDecoder().decode(MMPost.self, from: postData)
        }
        if let postDict = value as? [String: Any],
           let postData = try? JSONSerialization.data(withJSONObject: postDict) {
            return try? JSONDecoder().decode(MMPost.self, from: postData)
        }
        return nil
    }

    func parseWebSocketMessage(_ text: String) -> (didConnect: Bool, event: MMWebSocketEvent?) {
        var didConnect = false
        var parsedEvent: MMWebSocketEvent?
        
        if let data = text.data(using: .utf8),
           let json = try? JSONSerialization.jsonObject(with: data) as? [String: Any] {
            
            if let status = json["status"] as? String, status == "OK" {
                if let seqReply = json["seq_reply"] as? Int, seqReply == 1 {
                    didConnect = true
                }
                if let statuses = json["data"] as? [String: String] {
                    parsedEvent = .userStatuses(statuses: statuses)
                } else if let statusesDict = json["data"] as? [String: Any] {
                    var strStatuses: [String: String] = [:]
                    for (k, v) in statusesDict {
                        if let s = v as? String {
                            strStatuses[k] = s
                        }
                    }
                    if !strStatuses.isEmpty {
                        parsedEvent = .userStatuses(statuses: strStatuses)
                    }
                }
            }
            
            if let eventName = json["event"] as? String {
                if eventName == "hello" {
                    didConnect = true
                    parsedEvent = .hello
                }
                
                var eventData: [String: Any] = [:]
                if let dict = json["data"] as? [String: Any] {
                    eventData = dict
                } else if let str = json["data"] as? String,
                          let strData = str.data(using: .utf8),
                          let dict = try? JSONSerialization.jsonObject(with: strData) as? [String: Any] {
                    eventData = dict
                }
                
                let broadcast = (json["broadcast"] as? [String: Any]) ?? [:]
                
                switch eventName {
                case "hello":
                    parsedEvent = .hello
                case "posted":
                    if let post = decodeWebSocketPost(eventData["post"]) {
                        let senderName = eventData["sender_name"] as? String
                        let channelDisplayName = eventData["channel_display_name"] as? String
                        let channelName = eventData["channel_name"] as? String
                        let teamId = (eventData["team_id"] as? String) ?? (broadcast["team_id"] as? String)
                        parsedEvent = .posted(
                            post: post,
                            senderName: senderName,
                            channelDisplayName: channelDisplayName,
                            channelName: channelName,
                            teamId: teamId
                        )
                    }
                case "post_edited":
                    if let post = decodeWebSocketPost(eventData["post"]) {
                        parsedEvent = .postEdited(post: post)
                    }
                case "post_deleted", "post_deleted_by_admin":
                    let deletedPost = decodeWebSocketPost(eventData["post"])
                    let postId = deletedPost?.id
                        ?? (eventData["post_id"] as? String)
                        ?? (broadcast["post_id"] as? String)
                        ?? ""
                    let channelId = deletedPost?.channel_id
                        ?? (broadcast["channel_id"] as? String)
                        ?? (eventData["channel_id"] as? String)
                        ?? ""
                    if !postId.isEmpty {
                        parsedEvent = .postDeleted(postId: postId, channelId: channelId)
                    }
                case "post_unread":
                    let channelId = (eventData["channel_id"] as? String)
                        ?? (broadcast["channel_id"] as? String)
                        ?? ""
                    if !channelId.isEmpty {
                        parsedEvent = .postUnread(channelId: channelId)
                    }
                case "user_added", "user_removed":
                    let userId = (eventData["user_id"] as? String)
                        ?? (broadcast["user_id"] as? String)
                        ?? ""
                    let channelId = (broadcast["channel_id"] as? String)
                        ?? (eventData["channel_id"] as? String)
                        ?? ""
                    if !userId.isEmpty {
                        parsedEvent = .channelMembershipChanged(channelId: channelId, userId: userId)
                    }
                case "emoji_added":
                    parsedEvent = .emojiAdded
                case "channel_viewed":
                    let channelId = (eventData["channel_id"] as? String)
                        ?? (broadcast["channel_id"] as? String)
                        ?? ""
                    if !channelId.isEmpty {
                        parsedEvent = .channelViewed(channelId: channelId)
                    }
                case "multiple_channels_viewed":
                    let channelIds = (eventData["channel_ids"] as? [String]) ?? []
                    if let first = channelIds.first {
                        parsedEvent = .channelViewed(channelId: first)
                        for channelId in channelIds.dropFirst() {
                            onWebSocketEvent?(.channelViewed(channelId: channelId))
                        }
                    }
                case "channel_updated":
                    if let channelJSONString = eventData["channel"] as? String,
                       let channelData = channelJSONString.data(using: .utf8),
                       let channel = try? JSONDecoder().decode(MMChannel.self, from: channelData) {
                        parsedEvent = .channelUpdated(channel: channel)
                    } else if let channelDict = eventData["channel"] as? [String: Any],
                              let channelData = try? JSONSerialization.data(withJSONObject: channelDict),
                              let channel = try? JSONDecoder().decode(MMChannel.self, from: channelData) {
                        parsedEvent = .channelUpdated(channel: channel)
                    }
                case "preferences_changed":
                    let userId = (eventData["user_id"] as? String)
                        ?? (broadcast["user_id"] as? String)
                        ?? ""
                    if !userId.isEmpty {
                        parsedEvent = .preferencesChanged(userId: userId)
                    }
                case "thread_updated":
                    let rootId = (eventData["thread_id"] as? String)
                        ?? (eventData["root_id"] as? String)
                        ?? (broadcast["thread_id"] as? String)
                        ?? ""
                    if !rootId.isEmpty {
                        parsedEvent = .threadUpdated(rootId: rootId)
                    }
                case "status_change":
                    let userId = (eventData["user_id"] as? String) ?? (broadcast["user_id"] as? String) ?? ""
                    let status = (eventData["status"] as? String) ?? ""
                    if !userId.isEmpty && !status.isEmpty {
                        parsedEvent = .statusChange(userId: userId, status: status)
                    }
                case "typing":
                    let userId = (eventData["user_id"] as? String) ?? (broadcast["user_id"] as? String) ?? ""
                    let channelId = (broadcast["channel_id"] as? String) ?? (eventData["channel_id"] as? String) ?? ""
                    let parentId = eventData["parent_id"] as? String
                    if !userId.isEmpty && !channelId.isEmpty {
                        parsedEvent = .typing(userId: userId, channelId: channelId, parentId: parentId)
                    }
                case "update_team":
                    if let teamJSONString = eventData["team"] as? String,
                       let teamData = teamJSONString.data(using: .utf8),
                       let team = try? JSONDecoder().decode(MMTeam.self, from: teamData) {
                        parsedEvent = .updateTeam(team: team)
                    } else if let teamDict = eventData["team"] as? [String: Any],
                              let teamData = try? JSONSerialization.data(withJSONObject: teamDict),
                              let team = try? JSONDecoder().decode(MMTeam.self, from: teamData) {
                        parsedEvent = .updateTeam(team: team)
                    }
                case "added_to_team":
                    let teamId = (eventData["team_id"] as? String) ?? (broadcast["team_id"] as? String) ?? ""
                    let userId = (eventData["user_id"] as? String) ?? (broadcast["user_id"] as? String) ?? ""
                    parsedEvent = .addedToTeam(teamId: teamId, userId: userId)
                case "leave_team":
                    let teamId = (eventData["team_id"] as? String) ?? (broadcast["team_id"] as? String) ?? ""
                    let userId = (eventData["user_id"] as? String) ?? (broadcast["user_id"] as? String) ?? ""
                    parsedEvent = .leaveTeam(teamId: teamId, userId: userId)
                case "sidebar_category_updated", "sidebar_category_created", "sidebar_category_deleted", "sidebar_category_order_updated":
                    parsedEvent = .sidebarCategoriesUpdated
                case "reaction_added", "reaction_removed":
                    var postId = (eventData["post_id"] as? String) ?? ""
                    if postId.isEmpty {
                        if let reactionString = eventData["reaction"] as? String,
                           let reactionData = reactionString.data(using: .utf8),
                           let object = try? JSONSerialization.jsonObject(with: reactionData),
                           let reaction = object as? [String: Any],
                           let parsedPostId = reaction["post_id"] as? String {
                            postId = parsedPostId
                        } else if let reaction = eventData["reaction"] as? [String: Any],
                                  let parsedPostId = reaction["post_id"] as? String {
                            postId = parsedPostId
                        }
                    }
                    if postId.isEmpty {
                        postId = (broadcast["post_id"] as? String) ?? ""
                    }
                    if !postId.isEmpty {
                        parsedEvent = .reactionChanged(postId: postId)
                    }
                default:
                    parsedEvent = .other(event: eventName, data: eventData)
                }
            }
        }
        return (didConnect, parsedEvent)
    }
    
    private func handleIncomingWebSocketMessage(_ text: String) {
        let (didConnect, parsedEvent) = parseWebSocketMessage(text)
        if let event = parsedEvent {
            DebugLog.logSensitive("WS DISPATCH EVENT: \(event)")
        } else if !didConnect {
            DebugLog.warning("WS UNPARSED MSG: \(text)")
        }
        
        if didConnect {
            reconnectAttempts = 0
            notifySocketState(true, "Connected")
            onWebSocketConnected?()
            requestStatuses()
        }
        if let event = parsedEvent {
            onWebSocketEvent?(event)
            switch event {
            case .hello:
                break
            case .posted(let post, let senderName, _, _, _):
                onPostReceived?(post, senderName)
            case .statusChange(let userId, let status):
                onStatusChanged?(userId, status)
            case .userStatuses(let statuses):
                onMultipleStatusesReceived?(statuses)
                for (userId, status) in statuses {
                    onStatusChanged?(userId, status)
                }
            case .typing(let userId, let channelId, let parentId):
                onUserTyping?(userId, channelId, parentId)
            case .updateTeam(let team):
                onTeamUpdated?(team)
            case .addedToTeam, .leaveTeam:
                onUserTeamsChanged?()
            case .sidebarCategoriesUpdated:
                onSidebarCategoriesUpdated?()
            case .reactionChanged(let postId):
                onReactionChanged?(postId)
            case .postEdited, .postDeleted, .postUnread, .channelViewed, .channelUpdated,
                 .channelMembershipChanged, .preferencesChanged, .threadUpdated, .emojiAdded:
                break
            case .other:
                break
            }
        }
        onWebSocketMessage?(text)
    }
}
