//
//  WebSocketClient.swift
//  mattermost.client
//

import Foundation
import os

@MainActor
protocol WebSocketClientProtocol: AnyObject {
    var isConnected: Bool { get }

    var onWebSocketMessage: ((String) -> Void)? { get set }
    var onWebSocketStateChanged: ((Bool, String) -> Void)? { get set }
    var onWebSocketConnected: (() -> Void)? { get set }
    var onWebSocketDisconnected: ((Error?) -> Void)? { get set }
    var onWebSocketEvent: ((MMWebSocketEvent) -> Void)? { get set }
    var onPostReceived: ((MMPost, String?) -> Void)? { get set }
    var onStatusChanged: ((String, String) -> Void)? { get set }
    var onMultipleStatusesReceived: (([String: String]) -> Void)? { get set }
    var onUserTyping: ((String, String, String?) -> Void)? { get set }
    var onTeamUpdated: ((MMTeam) -> Void)? { get set }
    var onUserTeamsChanged: (() -> Void)? { get set }
    var onSidebarCategoriesUpdated: (() -> Void)? { get set }
    var onReactionChanged: ((String) -> Void)? { get set }

    func connectWebSocket()
    func disconnectWebSocket()
    func reconnectIfNeeded()
    func sendWebSocketMessage(action: String, data: [String: Any])
    func requestStatuses()
    func requestStatusesByIds(_ userIds: [String])
    func sendUserTyping(channelId: String, parentId: String)
    func parseWebSocketMessage(_ text: String) -> (didConnect: Bool, event: MMWebSocketEvent?)
}

@MainActor
class WebSocketClient: WebSocketClientProtocol {
    private let urlProvider: @MainActor () -> URL?
    private let tokenProvider: @MainActor () -> String?
    private let isLoggedProvider: @MainActor () -> Bool

    private let logger = Logger(
        subsystem: Bundle.main.bundleIdentifier ?? "mattermost.client", category: "WebSocketClient")
    private var webSocketTask: URLSessionWebSocketTask?
    private var wsSequence: Int = 1
    private var pingTimer: Timer?
    private var reconnectTimer: Timer?
    private var reconnectAttempts = 0

    private(set) var isConnected = false

    // Callbacks for WebSocket events
    var onWebSocketMessage: ((String) -> Void)?
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

    init(
        urlProvider: @escaping @MainActor () -> URL?,
        tokenProvider: @escaping @MainActor () -> String?,
        isLoggedProvider: @escaping @MainActor () -> Bool
    ) {
        self.urlProvider = urlProvider
        self.tokenProvider = tokenProvider
        self.isLoggedProvider = isLoggedProvider
    }

    convenience init(apiClient: APIClientProtocol) {
        self.init(
            urlProvider: { apiClient.webSocketURL },
            tokenProvider: { apiClient.token() },
            isLoggedProvider: { apiClient.isLogged() }
        )
    }

    static func reconnectDelay(attempt: Int, jitter: Double = 0) -> TimeInterval {
        min(30.0, pow(2.0, Double(max(0, attempt)))) + jitter
    }

    private func notifySocketState(_ connected: Bool, _ message: String) {
        DebugLog.info("WS STATE notify connected=\(connected) msg=\(message)")
        isConnected = connected
        DispatchQueue.main.async { [weak self] in
            self?.onWebSocketStateChanged?(connected, message)
        }
    }

    func connectWebSocket() {
        guard let token = tokenProvider(), !token.isEmpty else { return }

        guard let url = urlProvider() else {
            logger.error("Invalid WebSocket URL")
            return
        }

        disconnectWebSocket()
        wsSequence = 1

        var request = URLRequest(url: url)
        request.setValue("Bearer " + token, forHTTPHeaderField: "Authorization")

        let task = URLSession.shared.webSocketTask(with: request)
        webSocketTask = task
        task.resume()
        notifySocketState(false, "Connecting to Mattermost…")

        receiveWebSocketMessage(from: task)
        sendWebSocketAuthentication(token: token)
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
        guard isLoggedProvider(), reconnectTimer == nil else { return }
        stopPingTimer()
        webSocketTask?.cancel(with: .goingAway, reason: nil)
        webSocketTask = nil

        // Exponential backoff with jitter: 1s, 2s, 4s … capped at 30s.
        let delay = Self.reconnectDelay(
            attempt: reconnectAttempts,
            jitter: Double.random(in: 0...1)
        )
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
        guard isLoggedProvider() else { return }
        if let task = webSocketTask, task.state == .running { return }
        reconnectTimer?.invalidate()
        reconnectTimer = nil
        connectWebSocket()
    }

    func sendWebSocketMessage(action: String, data: [String: Any]) {
        let message: [String: Any] = [
            "seq": wsSequence,
            "action": action,
            "data": data,
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
                "parent_id": parentId,
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
            let postData = postJSONString.data(using: .utf8)
        {
            return try? JSONDecoder().decode(MMPost.self, from: postData)
        }
        if let postDict = value as? [String: Any],
            let postData = try? JSONSerialization.data(withJSONObject: postDict)
        {
            return try? JSONDecoder().decode(MMPost.self, from: postData)
        }
        return nil
    }

    func parseWebSocketMessage(_ text: String) -> (didConnect: Bool, event: MMWebSocketEvent?) {
        var didConnect = false
        var parsedEvent: MMWebSocketEvent?

        if let data = text.data(using: .utf8),
            let json = try? JSONSerialization.jsonObject(with: data) as? [String: Any]
        {

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
                    let dict = try? JSONSerialization.jsonObject(with: strData) as? [String: Any]
                {
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
                    let postId =
                        deletedPost?.id
                        ?? (eventData["post_id"] as? String)
                        ?? (broadcast["post_id"] as? String)
                        ?? ""
                    let channelId =
                        deletedPost?.channel_id
                        ?? (broadcast["channel_id"] as? String)
                        ?? (eventData["channel_id"] as? String)
                        ?? ""
                    if !postId.isEmpty {
                        parsedEvent = .postDeleted(postId: postId, channelId: channelId)
                    }
                case "post_unread":
                    let channelId =
                        (eventData["channel_id"] as? String)
                        ?? (broadcast["channel_id"] as? String)
                        ?? ""
                    if !channelId.isEmpty {
                        parsedEvent = .postUnread(channelId: channelId)
                    }
                case "user_added", "user_removed":
                    let userId =
                        (eventData["user_id"] as? String)
                        ?? (broadcast["user_id"] as? String)
                        ?? ""
                    let channelId =
                        (broadcast["channel_id"] as? String)
                        ?? (eventData["channel_id"] as? String)
                        ?? ""
                    if !userId.isEmpty {
                        parsedEvent = .channelMembershipChanged(channelId: channelId, userId: userId)
                    }
                case "emoji_added":
                    parsedEvent = .emojiAdded
                case "channel_viewed":
                    let channelId =
                        (eventData["channel_id"] as? String)
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
                        let channel = try? JSONDecoder().decode(MMChannel.self, from: channelData)
                    {
                        parsedEvent = .channelUpdated(channel: channel)
                    } else if let channelDict = eventData["channel"] as? [String: Any],
                        let channelData = try? JSONSerialization.data(withJSONObject: channelDict),
                        let channel = try? JSONDecoder().decode(MMChannel.self, from: channelData)
                    {
                        parsedEvent = .channelUpdated(channel: channel)
                    }
                case "preferences_changed":
                    let userId =
                        (eventData["user_id"] as? String)
                        ?? (broadcast["user_id"] as? String)
                        ?? ""
                    if !userId.isEmpty {
                        parsedEvent = .preferencesChanged(userId: userId)
                    }
                case "thread_updated":
                    let rootId =
                        (eventData["thread_id"] as? String)
                        ?? (eventData["root_id"] as? String)
                        ?? (broadcast["thread_id"] as? String)
                        ?? ""
                    if !rootId.isEmpty {
                        let replyCount =
                            (eventData["reply_count"] as? NSNumber)?.intValue
                            ?? (eventData["reply_count"] as? String).flatMap(Int.init)
                            ?? (eventData["reply_count"] as? Int)
                        parsedEvent = .threadUpdated(rootId: rootId, replyCount: replyCount)
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
                        let team = try? JSONDecoder().decode(MMTeam.self, from: teamData)
                    {
                        parsedEvent = .updateTeam(team: team)
                    } else if let teamDict = eventData["team"] as? [String: Any],
                        let teamData = try? JSONSerialization.data(withJSONObject: teamDict),
                        let team = try? JSONDecoder().decode(MMTeam.self, from: teamData)
                    {
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
                case "sidebar_category_updated", "sidebar_category_created", "sidebar_category_deleted",
                    "sidebar_category_order_updated":
                    parsedEvent = .sidebarCategoriesUpdated
                case "reaction_added", "reaction_removed":
                    var postId = (eventData["post_id"] as? String) ?? ""
                    if postId.isEmpty {
                        if let reactionString = eventData["reaction"] as? String,
                            let reactionData = reactionString.data(using: .utf8),
                            let object = try? JSONSerialization.jsonObject(with: reactionData),
                            let reaction = object as? [String: Any],
                            let parsedPostId = reaction["post_id"] as? String
                        {
                            postId = parsedPostId
                        } else if let reaction = eventData["reaction"] as? [String: Any],
                            let parsedPostId = reaction["post_id"] as? String
                        {
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
