//
//  main.swift
//  mattermost_ws_test
//
//  Created by Boris Barbulovski on 11.3.23.
//

import Foundation
import os

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

struct MMPostList: Codable {
    let order: [String]
    let posts: [String: MMPost]
    let next_post_id: String?
    let prev_post_id: String?
    
    var chronologicalPosts: [MMPost] {
        return order.reversed().compactMap { posts[$0] }
    }
}

enum MMWebSocketEvent {
    case posted(post: MMPost, senderName: String?, channelDisplayName: String?, channelName: String?, teamId: String?)
    case statusChange(userId: String, status: String)
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
            return try JSONDecoder().decode(LoginWebService.self, from: data)
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
            logger.info("checkToken succeeded")
            return true
        } catch {
            logger.error("Error: \(error.localizedDescription)")
            return false
        }
    }
    
    // MARK: - Users, Teams, Channels, Categories & Posts REST API
    
    func fetchCurrentUser() async throws -> LoginWebService {
        return try await performAuthenticatedRequest(path: "/api/v4/users/me")
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
    
    // Callbacks for WebSocket events
    var onWebSocketMessage: ((String) -> Void)?
    var onWebSocketConnected: (() -> Void)?
    var onWebSocketDisconnected: ((Error?) -> Void)?
    var onWebSocketEvent: ((MMWebSocketEvent) -> Void)?
    var onPostReceived: ((MMPost, String?) -> Void)?
    var onStatusChanged: ((String, String) -> Void)?
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
        
        webSocketTask = URLSession.shared.webSocketTask(with: url)
        webSocketTask?.resume()
        
        receiveWebSocketMessage()
        sendWebSocketAuthentication(token: mToken)
    }
    
    func disconnectWebSocket() {
        webSocketTask?.cancel(with: .goingAway, reason: nil)
        webSocketTask = nil
    }
    
    func sendWebSocketMessage(action: String, data: [String: Any]) {
        let message: [String: Any] = [
            "seq": wsSequence,
            "action": action,
            "data": data
        ]
        wsSequence += 1
        
        do {
            let jsonData = try JSONSerialization.data(withJSONObject: message)
            if let jsonString = String(data: jsonData, encoding: .utf8) {
                let wsMessage = URLSessionWebSocketTask.Message.string(jsonString)
                webSocketTask?.send(wsMessage) { [weak self] error in
                    if let error = error {
                        self?.logger.error("WebSocket send error: \(error.localizedDescription)")
                    }
                }
            }
        } catch {
            logger.error("Failed to serialize WebSocket message")
        }
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
                DispatchQueue.main.async {
                    self.onWebSocketDisconnected?(error)
                }
            case .success(let message):
                switch message {
                case .string(let text):
                    NSLog("WebSocket message: \(text)")
                    self.handleIncomingWebSocketMessage(text)
                case .data(let data):
                    NSLog("WebSocket data: \(data)")
                    if let text = String(data: data, encoding: .utf8) {
                        self.handleIncomingWebSocketMessage(text)
                    }
                @unknown default:
                    break
                }
                
                if self.webSocketTask?.state == .running {
                    // Continue receiving
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
            if let status = json["status"] as? String, status == "OK",
               let seqReply = json["seq_reply"] as? Int, seqReply == 1 {
                didConnect = true
            }
            
            if let eventName = json["event"] as? String {
                let eventData = (json["data"] as? [String: Any]) ?? [:]
                let broadcast = (json["broadcast"] as? [String: Any]) ?? [:]
                
                switch eventName {
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
        
        DispatchQueue.main.async { [weak self] in
            guard let self = self else { return }
            if didConnect {
                self.onWebSocketConnected?()
            }
            if let event = parsedEvent {
                self.onWebSocketEvent?(event)
                switch event {
                case .posted(let post, let senderName, _, _, _):
                    self.onPostReceived?(post, senderName)
                case .statusChange(let userId, let status):
                    self.onStatusChanged?(userId, status)
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
