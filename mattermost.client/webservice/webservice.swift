//
//  webservice.swift
//  mattermost.client
//

import Foundation

/// Unified facade coordinating REST API requests, WebSocket real-time communication,
/// and file transfer operations.
/// All state and callbacks are main-actor isolated.
@MainActor
final class WebService: NSObject, APIClientProtocol, WebSocketClientProtocol, FileTransferProtocol {
    let apiClient: APIClient
    let webSocketClient: WebSocketClient
    let fileTransfer: FileTransfer

    // MARK: - Properties & Backward Compatibility

    var host: String {
        get { apiClient.host }
        set { apiClient.host = newValue }
    }

    var port: UInt16 {
        get { apiClient.port }
        set { apiClient.port = newValue }
    }

    var authToken: String {
        get { apiClient.authToken }
        set { apiClient.authToken = newValue }
    }

    var mHost: String {
        get { apiClient.host }
        set { apiClient.host = newValue }
    }

    var mPort: UInt16 {
        get { apiClient.port }
        set { apiClient.port = newValue }
    }

    var mToken: String {
        get { apiClient.authToken }
        set { apiClient.authToken = newValue }
    }

    var mConnected: Bool {
        get { apiClient.isLogged() }
        set {
            if !newValue {
                apiClient.authToken = ""
            }
        }
    }

    var currentUserId: String {
        get { apiClient.currentUserId }
        set { apiClient.currentUserId = newValue }
    }

    var isConnected: Bool {
        webSocketClient.isConnected
    }

    var isWebSocketConnected: Bool {
        webSocketClient.isConnected
    }

    var webSocketURL: URL? {
        apiClient.webSocketURL
    }

    // MARK: - WebSocket Callbacks

    var onWebSocketMessage: ((String) -> Void)? {
        get { webSocketClient.onWebSocketMessage }
        set { webSocketClient.onWebSocketMessage = newValue }
    }

    var onWebSocketStateChanged: ((Bool, String) -> Void)? {
        get { webSocketClient.onWebSocketStateChanged }
        set { webSocketClient.onWebSocketStateChanged = newValue }
    }

    var onWebSocketConnected: (() -> Void)? {
        get { webSocketClient.onWebSocketConnected }
        set { webSocketClient.onWebSocketConnected = newValue }
    }

    var onWebSocketDisconnected: ((Error?) -> Void)? {
        get { webSocketClient.onWebSocketDisconnected }
        set { webSocketClient.onWebSocketDisconnected = newValue }
    }

    var onWebSocketEvent: ((MMWebSocketEvent) -> Void)? {
        get { webSocketClient.onWebSocketEvent }
        set { webSocketClient.onWebSocketEvent = newValue }
    }

    var onPostReceived: ((MMPost, String?) -> Void)? {
        get { webSocketClient.onPostReceived }
        set { webSocketClient.onPostReceived = newValue }
    }

    var onStatusChanged: ((String, String) -> Void)? {
        get { webSocketClient.onStatusChanged }
        set { webSocketClient.onStatusChanged = newValue }
    }

    var onMultipleStatusesReceived: (([String: String]) -> Void)? {
        get { webSocketClient.onMultipleStatusesReceived }
        set { webSocketClient.onMultipleStatusesReceived = newValue }
    }

    var onUserTyping: ((String, String, String?) -> Void)? {
        get { webSocketClient.onUserTyping }
        set { webSocketClient.onUserTyping = newValue }
    }

    var onTeamUpdated: ((MMTeam) -> Void)? {
        get { webSocketClient.onTeamUpdated }
        set { webSocketClient.onTeamUpdated = newValue }
    }

    var onUserTeamsChanged: (() -> Void)? {
        get { webSocketClient.onUserTeamsChanged }
        set { webSocketClient.onUserTeamsChanged = newValue }
    }

    var onSidebarCategoriesUpdated: (() -> Void)? {
        get { webSocketClient.onSidebarCategoriesUpdated }
        set { webSocketClient.onSidebarCategoriesUpdated = newValue }
    }

    var onReactionChanged: ((String) -> Void)? {
        get { webSocketClient.onReactionChanged }
        set { webSocketClient.onReactionChanged = newValue }
    }

    // MARK: - Initializers

    override init() {
        let api = APIClient()
        self.apiClient = api
        self.webSocketClient = WebSocketClient(apiClient: api)
        self.fileTransfer = FileTransfer(apiClient: api)
        super.init()
    }

    init(host: String, port: UInt16) {
        let api = APIClient(host: host, port: port)
        self.apiClient = api
        self.webSocketClient = WebSocketClient(apiClient: api)
        self.fileTransfer = FileTransfer(apiClient: api)
        super.init()
    }

    init(apiClient: APIClient, webSocketClient: WebSocketClient? = nil, fileTransfer: FileTransfer? = nil) {
        self.apiClient = apiClient
        self.webSocketClient = webSocketClient ?? WebSocketClient(apiClient: apiClient)
        self.fileTransfer = fileTransfer ?? FileTransfer(apiClient: apiClient)
        super.init()
    }

    // MARK: - Static Utilities

    static func isAuthenticationFailure(_ error: Error) -> Bool {
        APIClient.isAuthenticationFailure(error)
    }

    static func reconnectDelay(attempt: Int, jitter: Double = 0) -> TimeInterval {
        WebSocketClient.reconnectDelay(attempt: attempt, jitter: jitter)
    }

    static func sanitizedMultipartFilename(_ filename: String) -> String {
        FileTransfer.sanitizedMultipartFilename(filename)
    }

    static func sanitizedMultipartMimeType(_ mimeType: String) -> String {
        FileTransfer.sanitizedMultipartMimeType(mimeType)
    }

    static func multipartHeader(boundary: String, filename: String, mimeType: String) -> Data {
        FileTransfer.multipartHeader(boundary: boundary, filename: filename, mimeType: mimeType)
    }

    static func multipartFooter(boundary: String) -> Data {
        FileTransfer.multipartFooter(boundary: boundary)
    }

    static func multipartBody(boundary: String, filename: String, mimeType: String, data: Data) -> Data {
        FileTransfer.multipartBody(boundary: boundary, filename: filename, mimeType: mimeType, data: data)
    }

    static func writeMultipartFile(
        sourceURL: URL,
        destinationURL: URL,
        boundary: String,
        filename: String,
        mimeType: String
    ) throws {
        try FileTransfer.writeMultipartFile(
            sourceURL: sourceURL,
            destinationURL: destinationURL,
            boundary: boundary,
            filename: filename,
            mimeType: mimeType
        )
    }

    static func maxFileSize(fromClientConfig data: Data) -> Int64? {
        FileTransfer.maxFileSize(fromClientConfig: data)
    }

    @discardableResult
    static func decodeLogin(_ data: Data) -> MMUser? {
        APIClient.decodeLogin(data)
    }

    // MARK: - URL Building

    func token() -> String? {
        apiClient.token()
    }

    func isLogged() -> Bool {
        apiClient.isLogged()
    }

    func buildURL(path: String, queryItems: [URLQueryItem]? = nil, isWebSocket: Bool = false) -> URL? {
        apiClient.buildURL(path: path, queryItems: queryItems, isWebSocket: isWebSocket)
    }

    func teamInviteURL(team: MMTeam) -> URL? {
        apiClient.teamInviteURL(team: team)
    }

    // MARK: - Request Execution

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
        try apiClient.makeRequest(
            path: path,
            method: method,
            queryItems: queryItems,
            jsonBody: jsonBody,
            rawBody: rawBody,
            auth: auth,
            accept: accept,
            contentType: contentType
        )
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
        try await apiClient.performRequest(
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
        try await apiClient.performAuthenticatedRequest(
            path: path,
            method: method,
            queryItems: queryItems,
            body: body
        )
    }

    // MARK: - Authentication & Configuration

    @discardableResult
    func login(username: String, password: String, mfaToken: String? = nil) async throws -> MMUser {
        try await apiClient.login(username: username, password: password, mfaToken: mfaToken)
    }

    @discardableResult
    func loginWithSessionToken(_ token: String) async throws -> MMUser {
        try await apiClient.loginWithSessionToken(token)
    }

    func fetchClientConfigData() async -> Data? {
        await apiClient.fetchClientConfigData()
    }

    func fetchLinkMetadata(url: URL) async -> MMLinkMetadata? {
        await apiClient.fetchLinkMetadata(url: url)
    }

    func checkToken(token: String) async -> Bool {
        await apiClient.checkToken(token: token)
    }

    // MARK: - Users

    func fetchCurrentUser() async throws -> MMUser {
        try await apiClient.fetchCurrentUser()
    }

    func fetchUsersByIds(_ userIds: [String]) async throws -> [MMUser] {
        try await apiClient.fetchUsersByIds(userIds)
    }

    func updateUserNotifyProps(userId: String, props: [String: String]) async throws {
        try await apiClient.updateUserNotifyProps(userId: userId, props: props)
    }

    func fetchUser(userId: String) async throws -> MMUser {
        try await apiClient.fetchUser(userId: userId)
    }

    func fetchUserByUsername(_ username: String) async throws -> MMUser {
        try await apiClient.fetchUserByUsername(username)
    }

    func fetchTeamUsers(teamId: String, page: Int = 0, perPage: Int = 100) async throws -> [MMUser] {
        try await apiClient.fetchTeamUsers(teamId: teamId, page: page, perPage: perPage)
    }

    func createDirectChannel(userId: String) async throws -> MMChannel {
        try await apiClient.createDirectChannel(userId: userId)
    }

    func createGroupChannel(userIds: [String]) async throws -> MMChannel {
        try await apiClient.createGroupChannel(userIds: userIds)
    }

    func searchUsers(term: String, teamId: String? = nil) async throws -> [MMUser] {
        try await apiClient.searchUsers(term: term, teamId: teamId)
    }

    func fetchUserImage(userId: String) async throws -> Data {
        try await apiClient.fetchUserImage(userId: userId)
    }

    @discardableResult
    func updateUserStatus(userId: String = "", status: String, dndEndTime: Int64? = nil) async throws -> MMUserStatus {
        try await apiClient.updateUserStatus(userId: userId, status: status, dndEndTime: dndEndTime)
    }

    func fetchUserStatuses(userIds: [String]) async throws -> [MMUserStatus] {
        try await apiClient.fetchUserStatuses(userIds: userIds)
    }

    func fetchUserPreferences(userId: String) async throws -> [[String: String]] {
        try await apiClient.fetchUserPreferences(userId: userId)
    }

    func deleteUserPreferences(userId: String, preferences: [[String: String]]) async throws {
        try await apiClient.deleteUserPreferences(userId: userId, preferences: preferences)
    }

    func saveUserPreferences(userId: String, preferences: [[String: String]]) async throws {
        try await apiClient.saveUserPreferences(userId: userId, preferences: preferences)
    }

    func setCustomStatus(emoji: String, text: String, duration: String, expiresAt: String?) async throws {
        try await apiClient.setCustomStatus(emoji: emoji, text: text, duration: duration, expiresAt: expiresAt)
    }

    func clearCustomStatus() async throws {
        try await apiClient.clearCustomStatus()
    }

    // MARK: - Teams

    func fetchTeams() async throws -> [MMTeam] {
        try await apiClient.fetchTeams()
    }

    func createTeam(name: String, displayName: String) async throws -> MMTeam {
        try await apiClient.createTeam(name: name, displayName: displayName)
    }

    func sendTeamInvite(teamId: String, email: String) async throws {
        try await apiClient.sendTeamInvite(teamId: teamId, email: email)
    }

    func fetchTeamsUnread(userId: String) async throws -> [MMTeamUnread] {
        try await apiClient.fetchTeamsUnread(userId: userId)
    }

    func leaveTeam(teamId: String, userId: String) async throws {
        try await apiClient.leaveTeam(teamId: teamId, userId: userId)
    }

    func fetchTeamByName(_ name: String) async throws -> MMTeam {
        try await apiClient.fetchTeamByName(name)
    }

    func addUserToTeam(teamId: String, userId: String) async throws {
        try await apiClient.addUserToTeam(teamId: teamId, userId: userId)
    }

    func removeUserFromTeam(teamId: String, userId: String) async throws {
        try await apiClient.removeUserFromTeam(teamId: teamId, userId: userId)
    }

    func fetchTeamMembers(teamId: String, page: Int = 0, perPage: Int = 60) async throws -> [MMTeamMember] {
        try await apiClient.fetchTeamMembers(teamId: teamId, page: page, perPage: perPage)
    }

    func fetchTeamMember(teamId: String, userId: String) async throws -> MMTeamMember {
        try await apiClient.fetchTeamMember(teamId: teamId, userId: userId)
    }

    func updateTeamMemberRoles(teamId: String, userId: String, roles: String) async throws {
        try await apiClient.updateTeamMemberRoles(teamId: teamId, userId: userId, roles: roles)
    }

    func updateTeam(
        teamId: String,
        displayName: String,
        description: String? = nil,
        companyName: String? = nil,
        allowedDomains: String? = nil,
        allowOpenInvite: Bool? = nil
    ) async throws -> MMTeam {
        try await apiClient.updateTeam(
            teamId: teamId,
            displayName: displayName,
            description: description,
            companyName: companyName,
            allowedDomains: allowedDomains,
            allowOpenInvite: allowOpenInvite
        )
    }

    // MARK: - Channels

    func fetchChannels(teamId: String) async throws -> [MMChannel] {
        try await apiClient.fetchChannels(teamId: teamId)
    }

    func fetchAllChannels() async throws -> [MMChannel] {
        try await apiClient.fetchAllChannels()
    }

    func fetchPublicChannels(teamId: String, page: Int = 0, perPage: Int = 100) async throws -> [MMChannel] {
        try await apiClient.fetchPublicChannels(teamId: teamId, page: page, perPage: perPage)
    }

    func fetchPrivateChannels(teamId: String, page: Int = 0, perPage: Int = 100) async throws -> [MMChannel] {
        try await apiClient.fetchPrivateChannels(teamId: teamId, page: page, perPage: perPage)
    }

    func requestToJoinChannel(channelId: String) async throws {
        try await apiClient.requestToJoinChannel(channelId: channelId)
    }

    func leaveChannel(channelId: String, userId: String) async throws {
        try await apiClient.leaveChannel(channelId: channelId, userId: userId)
    }

    func joinChannel(channelId: String, userId: String) async throws {
        try await apiClient.joinChannel(channelId: channelId, userId: userId)
    }

    func fetchChannelMembers(channelId: String, page: Int = 0, perPage: Int = 60) async throws -> [MMChannelMember] {
        try await apiClient.fetchChannelMembers(channelId: channelId, page: page, perPage: perPage)
    }

    func fetchChannelMemberships(userId: String, teamId: String, page: Int = 0, perPage: Int = 200) async throws
        -> [MMChannelMembership]
    {
        try await apiClient.fetchChannelMemberships(userId: userId, teamId: teamId, page: page, perPage: perPage)
    }

    func updateChannelNotifyProps(channelId: String, userId: String, props: [String: String]) async throws {
        try await apiClient.updateChannelNotifyProps(channelId: channelId, userId: userId, props: props)
    }

    func markAllChannelsRead(userId: String, teamId: String) async throws {
        try await apiClient.markAllChannelsRead(userId: userId, teamId: teamId)
    }

    func markChannelUnread(userId: String, channelId: String, postId: String) async throws {
        try await apiClient.markChannelUnread(userId: userId, channelId: channelId, postId: postId)
    }

    func markChannelViewed(channelId: String) async throws -> Int64? {
        try await apiClient.markChannelViewed(channelId: channelId)
    }

    // MARK: - Sidebar Categories

    func fetchSidebarCategories(teamId: String) async throws -> MMSidebarCategoriesResponse {
        try await apiClient.fetchSidebarCategories(teamId: teamId)
    }

    func createSidebarCategory(teamId: String, displayName: String, userId: String) async throws -> MMSidebarCategory {
        try await apiClient.createSidebarCategory(teamId: teamId, displayName: displayName, userId: userId)
    }

    func updateSidebarCategory(
        teamId: String,
        userId: String,
        categoryId: String,
        displayName: String? = nil,
        collapsed: Bool? = nil,
        muted: Bool? = nil
    ) async throws -> MMSidebarCategory {
        try await apiClient.updateSidebarCategory(
            teamId: teamId,
            userId: userId,
            categoryId: categoryId,
            displayName: displayName,
            collapsed: collapsed,
            muted: muted
        )
    }

    func deleteSidebarCategory(teamId: String, userId: String, categoryId: String) async throws {
        try await apiClient.deleteSidebarCategory(teamId: teamId, userId: userId, categoryId: categoryId)
    }

    func updateSidebarCategoryOrder(teamId: String, userId: String, categoryIds: [String]) async throws {
        try await apiClient.updateSidebarCategoryOrder(teamId: teamId, userId: userId, categoryIds: categoryIds)
    }

    func addChannelToSidebarCategory(teamId: String, userId: String, categoryId: String, channelId: String) async throws
    {
        try await apiClient.addChannelToSidebarCategory(
            teamId: teamId, userId: userId, categoryId: categoryId, channelId: channelId)
    }

    func removeChannelFromSidebarCategory(teamId: String, userId: String, categoryId: String, channelId: String)
        async throws
    {
        try await apiClient.removeChannelFromSidebarCategory(
            teamId: teamId, userId: userId, categoryId: categoryId, channelId: channelId)
    }

    // MARK: - Posts

    func fetchChannelPosts(
        channelId: String, page: Int = 0, perPage: Int = TimelinePager.pageSize, before: String? = nil
    ) async throws -> MMPostList {
        try await apiClient.fetchChannelPosts(channelId: channelId, page: page, perPage: perPage, before: before)
    }

    func searchPosts(teamId: String, terms: String, page: Int = 0, perPage: Int = 50) async throws -> MMPostList {
        try await apiClient.searchPosts(teamId: teamId, terms: terms, page: page, perPage: perPage)
    }

    func fetchPinnedPosts(channelId: String) async throws -> MMPostList {
        try await apiClient.fetchPinnedPosts(channelId: channelId)
    }

    func fetchFlaggedPosts(userId: String, teamId: String, page: Int = 0, perPage: Int = 60) async throws -> MMPostList
    {
        try await apiClient.fetchFlaggedPosts(userId: userId, teamId: teamId, page: page, perPage: perPage)
    }

    @discardableResult
    func createPost(channelId: String, message: String, rootId: String? = nil, fileIds: [String] = []) async throws
        -> MMPost
    {
        try await apiClient.createPost(channelId: channelId, message: message, rootId: rootId, fileIds: fileIds)
    }

    @discardableResult
    func patchPost(postId: String, message: String) async throws -> MMPost {
        try await apiClient.patchPost(postId: postId, message: message)
    }

    func fetchPost(postId: String) async throws -> MMPost {
        try await apiClient.fetchPost(postId: postId)
    }

    func fetchPostThread(postId: String) async throws -> MMPostList {
        try await apiClient.fetchPostThread(postId: postId)
    }

    func pinPost(postId: String) async throws {
        try await apiClient.pinPost(postId: postId)
    }

    func unpinPost(postId: String) async throws {
        try await apiClient.unpinPost(postId: postId)
    }

    func savePost(userId: String, postId: String) async throws {
        try await apiClient.savePost(userId: userId, postId: postId)
    }

    func unsavePost(userId: String, postId: String) async throws {
        try await apiClient.unsavePost(userId: userId, postId: postId)
    }

    func deletePost(postId: String) async throws {
        try await apiClient.deletePost(postId: postId)
    }

    // MARK: - Reactions

    @discardableResult
    func addReaction(userId: String, postId: String, emojiName: String) async throws -> MMReaction {
        try await apiClient.addReaction(userId: userId, postId: postId, emojiName: emojiName)
    }

    func removeReaction(userId: String, postId: String, emojiName: String) async throws {
        try await apiClient.removeReaction(userId: userId, postId: postId, emojiName: emojiName)
    }

    // MARK: - Threads

    func fetchThreads(userId: String, teamId: String, perPage: Int = 60) async throws -> [MMThread] {
        try await apiClient.fetchThreads(userId: userId, teamId: teamId, perPage: perPage)
    }

    func fetchThreadsPage(userId: String, teamId: String, page: Int = 0, perPage: Int = 60) async throws
        -> MMThreadsResponse
    {
        try await apiClient.fetchThreadsPage(userId: userId, teamId: teamId, page: page, perPage: perPage)
    }

    func markThreadRead(teamId: String, threadId: String) async throws {
        try await apiClient.markThreadRead(teamId: teamId, threadId: threadId)
    }

    // MARK: - Custom Emojis

    func fetchCustomEmojis(page: Int = 0, perPage: Int = 200) async throws -> [MMEmoji] {
        try await apiClient.fetchCustomEmojis(page: page, perPage: perPage)
    }

    func fetchEmojiImage(emojiId: String) async throws -> Data {
        try await apiClient.fetchEmojiImage(emojiId: emojiId)
    }

    // MARK: - Plugins

    func fetchActivePluginIds() async throws -> [String] {
        try await apiClient.fetchActivePluginIds()
    }

    // MARK: - File Transfer

    func fetchMaxFileSize() async -> Int64? {
        await fileTransfer.fetchMaxFileSize()
    }

    func uploadFile(channelId: String, data: Data, filename: String, mimeType: String) async throws -> String {
        try await fileTransfer.uploadFile(channelId: channelId, data: data, filename: filename, mimeType: mimeType)
    }

    func uploadFile(
        channelId: String,
        fileURL: URL,
        filename: String,
        mimeType: String,
        maxBytes: Int64? = nil,
        progress: (@Sendable (Double) -> Void)? = nil
    ) async throws -> String {
        try await fileTransfer.uploadFile(
            channelId: channelId,
            fileURL: fileURL,
            filename: filename,
            mimeType: mimeType,
            maxBytes: maxBytes,
            progress: progress
        )
    }

    func fetchFileData(fileId: String, preview: Bool = false) async throws -> Data {
        try await fileTransfer.fetchFileData(fileId: fileId, preview: preview)
    }

    func searchChannelFiles(teamId: String, channelId: String, page: Int = 0, perPage: Int = 60) async throws
        -> [MMFileInfo]
    {
        try await fileTransfer.searchChannelFiles(teamId: teamId, channelId: channelId, page: page, perPage: perPage)
    }

    func searchTeamFiles(teamId: String, terms: String, page: Int = 0, perPage: Int = 60) async throws -> [MMFileInfo] {
        try await fileTransfer.searchTeamFiles(teamId: teamId, terms: terms, page: page, perPage: perPage)
    }

    // MARK: - WebSocket Logic

    func connectWebSocket() {
        webSocketClient.connectWebSocket()
    }

    func disconnectWebSocket() {
        webSocketClient.disconnectWebSocket()
    }

    func reconnectIfNeeded() {
        webSocketClient.reconnectIfNeeded()
    }

    func sendWebSocketMessage(action: String, data: [String: Any]) {
        webSocketClient.sendWebSocketMessage(action: action, data: data)
    }

    func requestStatuses() {
        webSocketClient.requestStatuses()
    }

    func requestStatusesByIds(_ userIds: [String]) {
        webSocketClient.requestStatusesByIds(userIds)
    }

    func sendUserTyping(channelId: String, parentId: String = "") {
        webSocketClient.sendUserTyping(channelId: channelId, parentId: parentId)
    }

    func parseWebSocketMessage(_ text: String) -> (didConnect: Bool, event: MMWebSocketEvent?) {
        webSocketClient.parseWebSocketMessage(text)
    }
}
