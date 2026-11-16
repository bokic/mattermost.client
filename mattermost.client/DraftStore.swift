//
//  DraftStore.swift
//  mattermost.client
//

import Foundation

@MainActor
protocol DraftStoreProtocol: AnyObject {
    var scope: StoreScope { get set }
    var schemaVersion: Int { get }

    // Channel Drafts
    func channelDraft(for channelId: String) -> ComposerDraft?
    func saveChannelDraft(_ draft: ComposerDraft, for channelId: String)
    func removeChannelDraft(for channelId: String)
    func allChannelDrafts() -> [String: ComposerDraft]
    func clearAllChannelDrafts()

    // Thread Drafts
    func threadDraft(for rootId: String) -> String?
    func saveThreadDraft(_ text: String, for rootId: String)
    func removeThreadDraft(for rootId: String)
    func allThreadDrafts() -> [String: String]
    func clearAllThreadDrafts()
}

@MainActor
final class DraftStore: DraftStoreProtocol {
    static let shared = DraftStore()
    static let currentSchemaVersion = 1

    private let defaults: UserDefaults
    private let encoder = JSONEncoder()
    private let decoder = JSONDecoder()

    private var cachedChannelDrafts: [String: ComposerDraft] = [:]
    private var cachedThreadDrafts: [String: String] = [:]

    var scope: StoreScope {
        didSet {
            if oldValue != scope {
                reload()
            }
        }
    }

    var schemaVersion: Int {
        defaults.integer(forKey: scope.key("drafts_schema_version"))
    }

    init(scope: StoreScope = .global, defaults: UserDefaults = .standard) {
        self.scope = scope
        self.defaults = defaults
        reload()
    }

    private func reload() {
        // Load channel drafts
        if let data = defaults.data(forKey: scope.key("channelDrafts")),
            let drafts = try? decoder.decode([String: ComposerDraft].self, from: data)
        {
            cachedChannelDrafts = drafts
        } else {
            cachedChannelDrafts = [:]
        }

        // Load thread drafts
        if let data = defaults.data(forKey: scope.key("threadDrafts")),
            let drafts = try? decoder.decode([String: String].self, from: data)
        {
            cachedThreadDrafts = drafts
        } else {
            cachedThreadDrafts = [:]
        }

        let versionKey = scope.key("drafts_schema_version")
        if defaults.integer(forKey: versionKey) < Self.currentSchemaVersion {
            defaults.set(Self.currentSchemaVersion, forKey: versionKey)
        }
    }

    private func persistChannelDrafts() {
        if cachedChannelDrafts.isEmpty {
            defaults.removeObject(forKey: scope.key("channelDrafts"))
        } else if let data = try? encoder.encode(cachedChannelDrafts) {
            defaults.set(data, forKey: scope.key("channelDrafts"))
        }
    }

    private func persistThreadDrafts() {
        if cachedThreadDrafts.isEmpty {
            defaults.removeObject(forKey: scope.key("threadDrafts"))
        } else if let data = try? encoder.encode(cachedThreadDrafts) {
            defaults.set(data, forKey: scope.key("threadDrafts"))
        }
    }

    // MARK: - Channel Drafts

    func channelDraft(for channelId: String) -> ComposerDraft? {
        guard !channelId.isEmpty else { return nil }
        return cachedChannelDrafts[channelId]
    }

    func saveChannelDraft(_ draft: ComposerDraft, for channelId: String) {
        guard !channelId.isEmpty else { return }
        if draft.isEmpty {
            removeChannelDraft(for: channelId)
        } else {
            cachedChannelDrafts[channelId] = draft
            persistChannelDrafts()
        }
    }

    func removeChannelDraft(for channelId: String) {
        guard !channelId.isEmpty else { return }
        cachedChannelDrafts.removeValue(forKey: channelId)
        persistChannelDrafts()
    }

    func allChannelDrafts() -> [String: ComposerDraft] {
        cachedChannelDrafts
    }

    func clearAllChannelDrafts() {
        cachedChannelDrafts.removeAll()
        persistChannelDrafts()
    }

    // MARK: - Thread Drafts

    func threadDraft(for rootId: String) -> String? {
        guard !rootId.isEmpty else { return nil }
        return cachedThreadDrafts[rootId]
    }

    func saveThreadDraft(_ text: String, for rootId: String) {
        guard !rootId.isEmpty else { return }
        let trimmed = text.trimmingCharacters(in: .whitespacesAndNewlines)
        if trimmed.isEmpty {
            removeThreadDraft(for: rootId)
        } else {
            cachedThreadDrafts[rootId] = text
            persistThreadDrafts()
        }
    }

    func removeThreadDraft(for rootId: String) {
        guard !rootId.isEmpty else { return }
        cachedThreadDrafts.removeValue(forKey: rootId)
        persistThreadDrafts()
    }

    func allThreadDrafts() -> [String: String] {
        cachedThreadDrafts
    }

    func clearAllThreadDrafts() {
        cachedThreadDrafts.removeAll()
        persistThreadDrafts()
    }
}
