//
//  ChatViewModel.swift
//  mattermost.client
//
//  Owns the live workspace data that the window renders: the authenticated user,
//  teams/channels/members, channel posts and read-state. REST and WebSocket code
//  updates this model (currently through MainWindow's live-data extension) and the
//  views read it through MainWindow's forwarding properties.
//

import Foundation

@MainActor
final class ChatViewModel {
    var webService: WebService?
    var isWebSocketConnected = false

    var currentUser: LoginWebService?
    var userTeams: [MMTeam] = []
    var activeTeam: MMTeam?
    var activeChannelId: String = ""

    var channelsById: [String: MMChannel] = [:]
    var channelsByName: [String: MMChannel] = [:]
    var usersById: [String: LoginWebService] = [:]
    var usersByUsername: [String: LoginWebService] = [:]
    var userStatusById: [String: String] = [:]
    var currentUserStatus: String = "online"

    var currentChannelPosts: [MMPost] = []
    var isLoadingOlderPosts = false
    var didLoadAllHistory = false
    var pendingJumpPostId: String?

    var membershipsByChannel: [String: MMChannelMembership] = [:]
    var unreadByChannel: [String: Int] = [:]
    var mentionsByChannel: [String: Int] = [:]
    var lastViewedAtByChannel: [String: Int64] = [:]
    var dndEndTimeByUser: [String: Int64] = [:]

    var threadItems: [MMThread] = []
    var threadPosts: [MMPost] = []
    var threadRootId: String = ""
}
