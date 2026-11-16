//
//  StoreScope.swift
//  mattermost.client
//

import Foundation

/// Defines the per-server and per-user scope for local persistence.
struct StoreScope: Equatable, Hashable, Sendable, Codable {
    let server: String
    let userId: String

    static let global = StoreScope(server: "", userId: "")

    init(server: String = "", userId: String = "") {
        var cleanServer = server.trimmingCharacters(in: .whitespacesAndNewlines).lowercased()
        if cleanServer.contains("://"), let host = URL(string: cleanServer)?.host {
            cleanServer = host
        } else if cleanServer.contains("://"), let host = cleanServer.components(separatedBy: "://").last {
            cleanServer = host
        }
        while cleanServer.hasSuffix("/") {
            cleanServer.removeLast()
        }
        self.server = cleanServer
        self.userId = userId.trimmingCharacters(in: .whitespacesAndNewlines)
    }

    var isGlobal: Bool {
        server.isEmpty && userId.isEmpty
    }

    /// Generates a namespaced key for this scope.
    func key(_ base: String) -> String {
        if isGlobal {
            return "mm.global.\(base)"
        }
        let safeServer = server.isEmpty ? "default" : server.replacingOccurrences(of: ".", with: "_")
        let safeUser = userId.isEmpty ? "anonymous" : userId
        return "mm.\(safeServer).\(safeUser).\(base)"
    }
}

/// Represents an attachment in the composer before it is uploaded or sent.
struct PendingAttachment: Codable, Equatable, Sendable {
    let id: String
    let name: String
    let size: Int64?

    init(id: String, name: String, size: Int64? = nil) {
        self.id = id
        self.name = name
        self.size = size
    }
}

/// Composer state kept per channel/conversation.
struct ComposerDraft: Codable, Equatable, Sendable {
    var text: String
    var attachments: [PendingAttachment]
    var editingPostId: String?
    var updatedAt: Date

    init(
        text: String,
        attachments: [PendingAttachment] = [],
        editingPostId: String? = nil,
        updatedAt: Date = Date()
    ) {
        self.text = text
        self.attachments = attachments
        self.editingPostId = editingPostId
        self.updatedAt = updatedAt
    }

    var isEmpty: Bool {
        text.isEmpty && attachments.isEmpty && editingPostId == nil
    }
}

/// Scroll offset in a channel timeline relative to a specific post.
struct ChannelScrollPosition: Codable, Equatable, Sendable {
    var postId: String
    var offset: CGFloat

    init(postId: String, offset: CGFloat) {
        self.postId = postId
        self.offset = offset
    }
}

/// A custom status record with text, emoji and optional expiry.
struct CustomStatusRecord: Codable, Equatable, Sendable {
    var emoji: String
    var text: String
    var expiresAt: Date?
    var durationIndex: Int

    init(emoji: String, text: String, expiresAt: Date? = nil, durationIndex: Int = 0) {
        self.emoji = emoji
        self.text = text
        self.expiresAt = expiresAt
        self.durationIndex = durationIndex
    }

    var isExpired: Bool {
        guard let expiresAt = expiresAt else { return false }
        return expiresAt <= Date()
    }
}
