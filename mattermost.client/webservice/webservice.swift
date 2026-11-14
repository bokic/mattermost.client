//
//  main.swift
//  mattermost_ws_test
//
//  Created by Boris Barbulovski on 11.3.23.
//

import Foundation
import os

enum DebugLog {
    static var logPath: String {
        return (NSTemporaryDirectory() as NSString).appendingPathComponent("mattermost_debug.log")
    }
    
    static func log(_ message: String) {
        let ts = ISO8601DateFormatter().string(from: Date())
        let line = "[\(ts)] \(message)\n"
        print("[STATUS_LOG] \(line)", terminator: "")
        fflush(stdout)
        NSLog("[STATUS_LOG] %@", message)
        
        if let data = line.data(using: .utf8) {
            let path = logPath
            if let fileHandle = FileHandle(forWritingAtPath: path) {
                fileHandle.seekToEndOfFile()
                fileHandle.write(data)
                try? fileHandle.close()
            } else {
                try? data.write(to: URL(fileURLWithPath: path), options: .atomic)
            }
        }
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
    case statusChange(userId: String, status: String)
    case userStatuses(statuses: [String: String])
    case typing(userId: String, channelId: String, parentId: String?)
    case updateTeam(team: MMTeam)
    case addedToTeam(teamId: String, userId: String)
    case leaveTeam(teamId: String, userId: String)
    case sidebarCategoriesUpdated
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

final class WebService: NSObject {
    var mHost: String = ""
    var mPort: UInt16 = 8065
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
        
        if !cleanHost.contains("://") {
            cleanHost = "http://" + cleanHost
        }
        
        guard var components = URLComponents(string: cleanHost),
              let host = components.host, !host.isEmpty else {
            return nil
        }
        
        if isWebSocket {
            components.scheme = (components.scheme == "https" || components.scheme == "wss") ? "wss" : "ws"
        }
        if mPort > 0 {
            components.port = Int(mPort)
        }
        components.path = path
        if let queryItems = queryItems, !queryItems.isEmpty {
            components.queryItems = queryItems
        }
        return components.url
    }
    
    private func performAuthenticatedRequest<T: Decodable>(
        path: String,
        method: String = "GET",
        queryItems: [URLQueryItem]? = nil,
        body: Any? = nil
    ) async throws -> T {
        guard let url = buildURL(path: path, queryItems: queryItems) else {
            throw WebServiceError.invalidHostname
        }
        
        var request = URLRequest(url: url)
        request.httpMethod = method
        request.setValue("Bearer " + mToken, forHTTPHeaderField: "Authorization")
        request.setValue("application/json", forHTTPHeaderField: "Accept")
        
        if let body = body {
            do {
                request.httpBody = try JSONSerialization.data(withJSONObject: body)
                request.setValue("application/json", forHTTPHeaderField: "Content-Type")
            } catch {
                throw WebServiceError.invalidRequestBody
            }
        }
        
        if path.contains("status") {
            DebugLog.log("HTTP \(method) \(path) sending body=\(String(describing: body))")
        }
        
        let data: Data
        let response: URLResponse
        do {
            (data, response) = try await URLSession.shared.data(for: request)
        } catch {
            if path.contains("status") {
                DebugLog.log("HTTP \(method) \(path) network error: \(error.localizedDescription)")
            }
            throw WebServiceError.networkError(error)
        }
        
        guard let httpResponse = response as? HTTPURLResponse else {
            throw WebServiceError.invalidResponse
        }
        
        if path.contains("status") {
            DebugLog.log("HTTP \(method) \(path) status=\(httpResponse.statusCode), body=\(String(decoding: data, as: UTF8.self))")
        }
        
        guard (200...299).contains(httpResponse.statusCode) else {
            var serverMsg: String?
            if let json = try? JSONSerialization.jsonObject(with: data) as? [String: Any],
               let msg = json["message"] as? String, !msg.isEmpty {
                serverMsg = msg
            }
            throw WebServiceError.httpStatus(code: httpResponse.statusCode, message: serverMsg)
        }
        
        do {
            return try JSONDecoder().decode(T.self, from: data)
        } catch {
            throw WebServiceError.decodingError(error)
        }
    }
    
    @discardableResult
    func login(username: String, password: String) async throws -> LoginWebService {
        let jsonObject: [String: String] = [
            "login_id": username,
            "password": password
        ]
        
        let jsonRequestBody: Data
        do {
            jsonRequestBody = try JSONSerialization.data(withJSONObject: jsonObject)
        } catch {
            throw WebServiceError.invalidRequestBody
        }
        
        guard let url = buildURL(path: "/api/v4/users/login") else {
            throw WebServiceError.invalidHostname
        }
        
        var request = URLRequest(url: url)
        request.httpMethod = "POST"
        request.setValue("application/json", forHTTPHeaderField: "Content-Type")
        request.httpBody = jsonRequestBody

        let data: Data
        let response: URLResponse
        do {
            (data, response) = try await URLSession.shared.data(for: request)
        } catch {
            throw WebServiceError.networkError(error)
        }
        
        guard let httpResponse = response as? HTTPURLResponse else {
            throw WebServiceError.invalidResponse
        }
        
        guard httpResponse.statusCode == 200 else {
            var serverMsg: String?
            if let json = try? JSONSerialization.jsonObject(with: data) as? [String: Any],
               let msg = json["message"] as? String, !msg.isEmpty {
                serverMsg = msg
            }
            throw WebServiceError.httpStatus(code: httpResponse.statusCode, message: serverMsg)
        }
        
        updateToken(token: httpResponse.value(forHTTPHeaderField: "Token") ?? "")
        
        guard response.mimeType == "application/json" else {
            throw WebServiceError.invalidMimeType(response.mimeType)
        }
        
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
        guard let url = buildURL(path: "/api/v4/users/me") else {
            return false
        }
        
        var request = URLRequest(url: url)
        request.httpMethod = "GET"
        request.setValue("Bearer " + token, forHTTPHeaderField: "Authorization")

        do {
            let (data, response) = try await URLSession.shared.data(for: request)
            guard let httpResponse = response as? HTTPURLResponse else {
                logger.error("httpResponse == nil")
                return false
            }

            guard response.mimeType == "application/json" else {
                logger.error("mimeType: \(response.mimeType ?? "Unknown")")
                return false
            }
            
            guard httpResponse.statusCode == 200 else {
                logger.error("statusCode: \(httpResponse.statusCode), data: \(String(decoding: data, as: UTF8.self))")
                return false
            }

            updateToken(token: token)
            if let user = try? JSONDecoder().decode(LoginWebService.self, from: data) {
                self.currentUserId = user.id
                UserDefaults.standard.set(user.id, forKey: "currentUserId")
            }
            logger.info("checkToken succeeded")
            return true
        } catch {
            logger.error("Error: \(error.localizedDescription)")
            return false
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
    
    func fetchUserByUsername(_ username: String) async throws -> LoginWebService {
        return try await performAuthenticatedRequest(path: "/api/v4/users/username/\(username)")
    }
    
    func fetchUserImage(userId: String) async throws -> Data {
        guard !userId.isEmpty else {
            throw WebServiceError.invalidRequestBody
        }
        guard let url = buildURL(path: "/api/v4/users/\(userId)/image") else {
            throw WebServiceError.invalidHostname
        }
        
        var request = URLRequest(url: url)
        request.httpMethod = "GET"
        if !mToken.isEmpty {
            request.setValue("Bearer " + mToken, forHTTPHeaderField: "Authorization")
        }
        
        let data: Data
        let response: URLResponse
        do {
            (data, response) = try await URLSession.shared.data(for: request)
        } catch {
            throw WebServiceError.networkError(error)
        }
        
        guard let httpResponse = response as? HTTPURLResponse else {
            throw WebServiceError.invalidResponse
        }
        
        guard (200...299).contains(httpResponse.statusCode) else {
            var serverMsg: String?
            if let json = try? JSONSerialization.jsonObject(with: data) as? [String: Any],
               let msg = json["message"] as? String, !msg.isEmpty {
                serverMsg = msg
            }
            throw WebServiceError.httpStatus(code: httpResponse.statusCode, message: serverMsg)
        }
        
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
        guard let url = buildURL(path: "/api/v4/users/\(userId)/preferences") else {
            throw WebServiceError.invalidHostname
        }
        var request = URLRequest(url: url)
        request.httpMethod = "DELETE"
        request.setValue("Bearer " + mToken, forHTTPHeaderField: "Authorization")
        request.setValue("application/json", forHTTPHeaderField: "Content-Type")
        request.httpBody = try JSONSerialization.data(withJSONObject: preferences)
        let (_, response) = try await URLSession.shared.data(for: request)
        guard let http = response as? HTTPURLResponse, (200...299).contains(http.statusCode) else {
            throw WebServiceError.invalidResponse
        }
    }
    
    func saveUserPreferences(userId: String, preferences: [[String: String]]) async throws {
        let _: [[String: String]] = try await performAuthenticatedRequest(
            path: "/api/v4/users/\(userId)/preferences",
            method: "PUT",
            body: preferences
        )
    }
    
    func fetchChannelMembers(channelId: String, page: Int = 0, perPage: Int = 60) async throws -> [MMChannelMember] {
        // Decoded loosely because member objects carry many optional fields.
        guard let url = buildURL(path: "/api/v4/channels/\(channelId)/members", queryItems: [
            URLQueryItem(name: "page", value: String(page)),
            URLQueryItem(name: "per_page", value: String(perPage))
        ]) else { throw WebServiceError.invalidHostname }
        var request = URLRequest(url: url)
        request.setValue("Bearer " + mToken, forHTTPHeaderField: "Authorization")
        request.setValue("application/json", forHTTPHeaderField: "Accept")
        let (data, response) = try await URLSession.shared.data(for: request)
        guard let http = response as? HTTPURLResponse, (200...299).contains(http.statusCode) else {
            throw WebServiceError.invalidResponse
        }
        let decoder = JSONDecoder()
        return try decoder.decode([MMChannelMember].self, from: data)
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
    
    func fetchChannelPosts(channelId: String, page: Int = 0, perPage: Int = 60) async throws -> MMPostList {
        let queryItems = [
            URLQueryItem(name: "page", value: String(page)),
            URLQueryItem(name: "per_page", value: String(perPage))
        ]
        return try await performAuthenticatedRequest(
            path: "/api/v4/channels/\(channelId)/posts",
            queryItems: queryItems
        )
    }
    
    @discardableResult
    func createPost(channelId: String, message: String, rootId: String? = nil) async throws -> MMPost {
        var payload: [String: Any] = [
            "channel_id": channelId,
            "message": message
        ]
        if let rootId = rootId, !rootId.isEmpty {
            payload["root_id"] = rootId
        }
        return try await performAuthenticatedRequest(
            path: "/api/v4/posts",
            method: "POST",
            body: payload
        )
    }
    
    // MARK: - WebSocket Logic
    
    private var webSocketTask: URLSessionWebSocketTask?
    private var wsSequence: Int = 1
    private var pingTimer: Timer?
    private var reconnectTimer: Timer?
    
    // Callbacks for WebSocket events
    var onWebSocketMessage: ((String) -> Void)?
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
        
        webSocketTask = URLSession.shared.webSocketTask(with: request)
        webSocketTask?.resume()
        
        receiveWebSocketMessage()
        sendWebSocketAuthentication(token: mToken)
        startPingTimer()
    }
    
    func disconnectWebSocket() {
        stopPingTimer()
        reconnectTimer?.invalidate()
        reconnectTimer = nil
        webSocketTask?.cancel(with: .goingAway, reason: nil)
        webSocketTask = nil
    }
    
    private func startPingTimer() {
        stopPingTimer()
        DispatchQueue.main.async { [weak self] in
            self?.pingTimer = Timer.scheduledTimer(withTimeInterval: 25.0, repeats: true) { [weak self] _ in
                guard let self = self, let task = self.webSocketTask, task.state == .running else { return }
                task.sendPing { [weak self] error in
                    if let error = error {
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
        
        DispatchQueue.main.async { [weak self] in
            self?.reconnectTimer = Timer.scheduledTimer(withTimeInterval: 3.0, repeats: false) { [weak self] _ in
                self?.reconnectTimer = nil
                self?.connectWebSocket()
            }
        }
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
                DebugLog.log("WS SEND [seq=\(currentSeq)]: action=\(action) payload=\(jsonString)")
                let wsMessage = URLSessionWebSocketTask.Message.string(jsonString)
                webSocketTask?.send(wsMessage) { [weak self] error in
                    if let error = error {
                        DebugLog.log("WS SEND ERROR [seq=\(currentSeq)]: \(error.localizedDescription)")
                        self?.logger.error("WebSocket send error: \(error.localizedDescription)")
                    }
                }
            }
        } catch {
            DebugLog.log("WS SEND SERIALIZATION ERROR for action=\(action)")
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
    
    private func receiveWebSocketMessage() {
        webSocketTask?.receive { [weak self] result in
            guard let self = self else { return }
            
            switch result {
            case .failure(let error):
                DebugLog.log("WS RECV FAILURE: \(error.localizedDescription)")
                self.logger.error("WebSocket receive error: \(error.localizedDescription)")
                DispatchQueue.main.async {
                    self.onWebSocketDisconnected?(error)
                }
                self.scheduleReconnect()
            case .success(let message):
                switch message {
                case .string(let text):
                    DebugLog.log("WS RECV: \(text)")
                    NSLog("WebSocket message: \(text)")
                    self.handleIncomingWebSocketMessage(text)
                case .data(let data):
                    if let text = String(data: data, encoding: .utf8) {
                        DebugLog.log("WS RECV: \(text)")
                        NSLog("WebSocket data: \(text)")
                        self.handleIncomingWebSocketMessage(text)
                    }
                @unknown default:
                    break
                }
                
                if self.webSocketTask != nil {
                    self.receiveWebSocketMessage()
                }
            }
        }
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
                    if let postJSONString = eventData["post"] as? String,
                       let postData = postJSONString.data(using: .utf8),
                       let post = try? JSONDecoder().decode(MMPost.self, from: postData) {
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
            DebugLog.log("WS DISPATCH EVENT: \(event)")
        } else if !didConnect {
            DebugLog.log("WS UNPARSED MSG: \(text)")
        }
        
        DispatchQueue.main.async { [weak self] in
            guard let self = self else { return }
            if didConnect {
                self.onWebSocketConnected?()
                self.requestStatuses()
            }
            if let event = parsedEvent {
                self.onWebSocketEvent?(event)
                switch event {
                case .hello:
                    break
                case .posted(let post, let senderName, _, _, _):
                    self.onPostReceived?(post, senderName)
                case .statusChange(let userId, let status):
                    self.onStatusChanged?(userId, status)
                case .userStatuses(let statuses):
                    self.onMultipleStatusesReceived?(statuses)
                    for (userId, status) in statuses {
                        self.onStatusChanged?(userId, status)
                    }
                case .typing(let userId, let channelId, let parentId):
                    self.onUserTyping?(userId, channelId, parentId)
                case .updateTeam(let team):
                    self.onTeamUpdated?(team)
                case .addedToTeam, .leaveTeam:
                    self.onUserTeamsChanged?()
                case .sidebarCategoriesUpdated:
                    self.onSidebarCategoriesUpdated?()
                case .other:
                    break
                }
            }
            self.onWebSocketMessage?(text)
        }
    }
}
