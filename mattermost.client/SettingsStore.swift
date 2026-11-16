//
//  SettingsStore.swift
//  mattermost.client
//

import Foundation

@MainActor
protocol SettingsStoreProtocol: AnyObject {
    var scope: StoreScope { get set }
    var schemaVersion: Int { get }

    var recentEmojis: [String] { get set }
    var recentReactions: [String] { get set }
    var recentSearches: [String] { get set }

    var customStatusText: String { get set }
    var customStatusEmoji: String { get set }
    var customStatusExpiresAt: Date? { get set }
    var recentCustomStatuses: [CustomStatusRecord] { get set }
    func saveRecentCustomStatus(emoji: String, text: String, durationIndex: Int)
    func clearCustomStatus()

    var rhsWidth: Double { get set }
    var lastTeamId: String? { get set }
    var lastChannelId: String? { get set }
    var loadRemoteImagesAutomatically: Bool { get set }
    var linkPreviewsEnabled: Bool { get set }
    var themeOverride: String? { get set }

    func collapsedCategories(for teamId: String) -> [String: Bool]
    func setCollapsedCategories(_ states: [String: Bool], for teamId: String)

    func scrollPosition(for channelId: String) -> ChannelScrollPosition?
    func setScrollPosition(_ position: ChannelScrollPosition?, for channelId: String)
    func allScrollPositions() -> [String: ChannelScrollPosition]

    func get<T: Decodable>(_ type: T.Type, forKey key: String) -> T?
    func set<T: Encodable>(_ value: T?, forKey key: String)
}

@MainActor
final class SettingsStore: SettingsStoreProtocol {
    static let shared = SettingsStore()
    static let currentSchemaVersion = 1

    private let defaults: UserDefaults
    private let encoder = JSONEncoder()
    private let decoder = JSONDecoder()

    var scope: StoreScope {
        didSet {
            if oldValue != scope {
                migrateIfNeeded()
            }
        }
    }

    var schemaVersion: Int {
        defaults.integer(forKey: scope.key("schema_version"))
    }

    init(scope: StoreScope = .global, defaults: UserDefaults = .standard) {
        self.scope = scope
        self.defaults = defaults
        migrateIfNeeded()
    }

    // MARK: - Schema Migration

    func migrateIfNeeded() {
        let versionKey = scope.key("schema_version")
        let storedVersion = defaults.integer(forKey: versionKey)
        guard storedVersion < Self.currentSchemaVersion else { return }

        // Migration from un-scoped legacy UserDefaults keys (v0 -> v1)
        if storedVersion == 0 && scope.isGlobal {
            // Emojis
            if let legacyEmojis = defaults.stringArray(forKey: "recentEmojis"), !legacyEmojis.isEmpty {
                defaults.set(legacyEmojis, forKey: scope.key("recentEmojis"))
            }
            // Reactions
            if let legacyReactions = defaults.stringArray(forKey: "recentReactions"), !legacyReactions.isEmpty {
                defaults.set(legacyReactions, forKey: scope.key("recentReactions"))
            }
            // Searches
            if let legacySearches = defaults.stringArray(forKey: "recentSearches"), !legacySearches.isEmpty {
                defaults.set(legacySearches, forKey: scope.key("recentSearches"))
            }
            // Custom Status
            if let legacyText = defaults.string(forKey: "customStatusText"), !legacyText.isEmpty {
                defaults.set(legacyText, forKey: scope.key("customStatusText"))
            }
            if let legacyEmoji = defaults.string(forKey: "customStatusEmoji"), !legacyEmoji.isEmpty {
                defaults.set(legacyEmoji, forKey: scope.key("customStatusEmoji"))
            }
            let legacyExpires = defaults.double(forKey: "customStatusExpiresAt")
            if legacyExpires > 0 {
                defaults.set(legacyExpires, forKey: scope.key("customStatusExpiresAt"))
            }
            // Recent Custom Statuses
            if let legacyStatuses = defaults.array(forKey: "recentCustomStatuses") as? [[String: Any]] {
                let records: [CustomStatusRecord] = legacyStatuses.compactMap { dict in
                    guard let text = dict["text"] as? String, !text.isEmpty else { return nil }
                    let emoji = (dict["emoji"] as? String) ?? ""
                    let duration = (dict["duration"] as? Int) ?? 0
                    return CustomStatusRecord(emoji: emoji, text: text, durationIndex: duration)
                }
                if let encoded = try? encoder.encode(records) {
                    defaults.set(encoded, forKey: scope.key("recentCustomStatuses"))
                }
            }
            // UI States
            let storedWidth = defaults.double(forKey: "rhsWidth")
            if storedWidth > 0 {
                defaults.set(storedWidth, forKey: scope.key("rhsWidth"))
            }
            if let team = defaults.string(forKey: "lastTeamId"), !team.isEmpty {
                defaults.set(team, forKey: scope.key("lastTeamId"))
            }
            if let channel = defaults.string(forKey: "lastChannelId"), !channel.isEmpty {
                defaults.set(channel, forKey: scope.key("lastChannelId"))
            }
            if let loadImages = defaults.object(forKey: "loadRemoteImagesAutomatically") as? Bool {
                defaults.set(loadImages, forKey: scope.key("loadRemoteImagesAutomatically"))
            }
            if let previews = defaults.object(forKey: "linkPreviewsEnabled") as? Bool {
                defaults.set(previews, forKey: scope.key("linkPreviewsEnabled"))
            }
            if let theme = defaults.string(forKey: "themeOverride"), !theme.isEmpty {
                defaults.set(theme, forKey: scope.key("themeOverride"))
            }
        }

        defaults.set(Self.currentSchemaVersion, forKey: versionKey)
    }

    // MARK: - Emojis & Reactions

    var recentEmojis: [String] {
        get {
            if let scoped = defaults.stringArray(forKey: scope.key("recentEmojis")) {
                return scoped
            }
            if scope.isGlobal {
                return defaults.stringArray(forKey: "recentEmojis") ?? []
            }
            return []
        }
        set {
            defaults.set(newValue, forKey: scope.key("recentEmojis"))
            if scope.isGlobal {
                defaults.set(newValue, forKey: "recentEmojis")
            }
        }
    }

    var recentReactions: [String] {
        get {
            if let scoped = defaults.stringArray(forKey: scope.key("recentReactions")) {
                return scoped
            }
            if scope.isGlobal {
                return defaults.stringArray(forKey: "recentReactions") ?? []
            }
            return []
        }
        set {
            defaults.set(newValue, forKey: scope.key("recentReactions"))
            if scope.isGlobal {
                defaults.set(newValue, forKey: "recentReactions")
            }
        }
    }

    var recentSearches: [String] {
        get {
            if let scoped = defaults.stringArray(forKey: scope.key("recentSearches")) {
                return scoped
            }
            if scope.isGlobal {
                return defaults.stringArray(forKey: "recentSearches") ?? []
            }
            return []
        }
        set {
            defaults.set(newValue, forKey: scope.key("recentSearches"))
            if scope.isGlobal {
                defaults.set(newValue, forKey: "recentSearches")
            }
        }
    }

    // MARK: - Custom Status

    var customStatusExpiresAt: Date? {
        get {
            let scopedTimestamp = defaults.double(forKey: scope.key("customStatusExpiresAt"))
            let timestamp: Double
            if scopedTimestamp > 0 {
                timestamp = scopedTimestamp
            } else if scope.isGlobal {
                timestamp = defaults.double(forKey: "customStatusExpiresAt")
            } else {
                timestamp = 0
            }
            guard timestamp > 0 else { return nil }
            let date = Date(timeIntervalSince1970: timestamp)
            if date <= Date() {
                clearCustomStatus()
                return nil
            }
            return date
        }
        set {
            if let date = newValue {
                defaults.set(date.timeIntervalSince1970, forKey: scope.key("customStatusExpiresAt"))
                if scope.isGlobal {
                    defaults.set(date.timeIntervalSince1970, forKey: "customStatusExpiresAt")
                }
            } else {
                defaults.removeObject(forKey: scope.key("customStatusExpiresAt"))
                if scope.isGlobal {
                    defaults.removeObject(forKey: "customStatusExpiresAt")
                }
            }
        }
    }

    var customStatusText: String {
        get {
            if let expires = customStatusExpiresAt, expires <= Date() {
                return ""
            }
            if let scoped = defaults.string(forKey: scope.key("customStatusText")) {
                return scoped
            }
            if scope.isGlobal {
                return defaults.string(forKey: "customStatusText") ?? ""
            }
            return ""
        }
        set {
            defaults.set(newValue, forKey: scope.key("customStatusText"))
            if scope.isGlobal {
                defaults.set(newValue, forKey: "customStatusText")
            }
        }
    }

    var customStatusEmoji: String {
        get {
            if let expires = customStatusExpiresAt, expires <= Date() {
                return ""
            }
            if let scoped = defaults.string(forKey: scope.key("customStatusEmoji")) {
                return scoped
            }
            if scope.isGlobal {
                return defaults.string(forKey: "customStatusEmoji") ?? ""
            }
            return ""
        }
        set {
            defaults.set(newValue, forKey: scope.key("customStatusEmoji"))
            if scope.isGlobal {
                defaults.set(newValue, forKey: "customStatusEmoji")
            }
        }
    }

    func clearCustomStatus() {
        defaults.removeObject(forKey: scope.key("customStatusText"))
        defaults.removeObject(forKey: scope.key("customStatusEmoji"))
        defaults.removeObject(forKey: scope.key("customStatusExpiresAt"))
        defaults.removeObject(forKey: "customStatusText")
        defaults.removeObject(forKey: "customStatusEmoji")
        defaults.removeObject(forKey: "customStatusExpiresAt")
    }

    var recentCustomStatuses: [CustomStatusRecord] {
        get {
            if scope.isGlobal && defaults.object(forKey: "recentCustomStatuses") == nil {
                defaults.removeObject(forKey: scope.key("recentCustomStatuses"))
                return []
            }
            if let data = defaults.data(forKey: scope.key("recentCustomStatuses")),
               let records = try? decoder.decode([CustomStatusRecord].self, from: data) {
                return records
            }
            if scope.isGlobal, let legacy = defaults.array(forKey: "recentCustomStatuses") as? [[String: Any]] {
                return legacy.compactMap { dict in
                    guard let text = dict["text"] as? String, !text.isEmpty else { return nil }
                    let emoji = (dict["emoji"] as? String) ?? ""
                    let duration = (dict["duration"] as? Int) ?? 0
                    return CustomStatusRecord(emoji: emoji, text: text, durationIndex: duration)
                }
            }
            return []
        }
        set {
            if let encoded = try? encoder.encode(newValue) {
                defaults.set(encoded, forKey: scope.key("recentCustomStatuses"))
            }
            if scope.isGlobal {
                let dicts = newValue.map { ["emoji": $0.emoji, "text": $0.text, "duration": $0.durationIndex] }
                defaults.set(dicts, forKey: "recentCustomStatuses")
            }
        }
    }

    func saveRecentCustomStatus(emoji: String, text: String, durationIndex: Int) {
        let trimmedText = text.trimmingCharacters(in: .whitespacesAndNewlines)
        guard !trimmedText.isEmpty else { return }
        var list = recentCustomStatuses
        list.removeAll { $0.text.lowercased() == trimmedText.lowercased() }
        list.insert(CustomStatusRecord(emoji: emoji, text: trimmedText, durationIndex: durationIndex), at: 0)
        if list.count > 5 {
            list = Array(list.prefix(5))
        }
        recentCustomStatuses = list
    }

    // MARK: - UI State

    var rhsWidth: Double {
        get {
            let scoped = defaults.double(forKey: scope.key("rhsWidth"))
            if scoped > 0 { return scoped }
            if scope.isGlobal {
                let legacy = defaults.double(forKey: "rhsWidth")
                if legacy > 0 { return legacy }
            }
            return 380.0
        }
        set {
            defaults.set(newValue, forKey: scope.key("rhsWidth"))
            if scope.isGlobal {
                defaults.set(newValue, forKey: "rhsWidth")
            }
        }
    }

    var lastTeamId: String? {
        get {
            if let scoped = defaults.string(forKey: scope.key("lastTeamId")) {
                return scoped
            }
            if scope.isGlobal {
                return defaults.string(forKey: "lastTeamId")
            }
            return nil
        }
        set {
            defaults.set(newValue, forKey: scope.key("lastTeamId"))
            if scope.isGlobal {
                defaults.set(newValue, forKey: "lastTeamId")
            }
        }
    }

    var lastChannelId: String? {
        get {
            if let scoped = defaults.string(forKey: scope.key("lastChannelId")) {
                return scoped
            }
            if scope.isGlobal {
                return defaults.string(forKey: "lastChannelId")
            }
            return nil
        }
        set {
            defaults.set(newValue, forKey: scope.key("lastChannelId"))
            if scope.isGlobal {
                defaults.set(newValue, forKey: "lastChannelId")
            }
        }
    }

    var loadRemoteImagesAutomatically: Bool {
        get {
            if let scoped = defaults.object(forKey: scope.key("loadRemoteImagesAutomatically")) as? Bool {
                return scoped
            }
            if scope.isGlobal, let legacy = defaults.object(forKey: "loadRemoteImagesAutomatically") as? Bool {
                return legacy
            }
            return true
        }
        set {
            defaults.set(newValue, forKey: scope.key("loadRemoteImagesAutomatically"))
            if scope.isGlobal {
                defaults.set(newValue, forKey: "loadRemoteImagesAutomatically")
            }
        }
    }

    var linkPreviewsEnabled: Bool {
        get {
            if let scoped = defaults.object(forKey: scope.key("linkPreviewsEnabled")) as? Bool {
                return scoped
            }
            if scope.isGlobal {
                return defaults.bool(forKey: "linkPreviewsEnabled")
            }
            return true
        }
        set {
            defaults.set(newValue, forKey: scope.key("linkPreviewsEnabled"))
            if scope.isGlobal {
                defaults.set(newValue, forKey: "linkPreviewsEnabled")
            }
        }
    }

    var themeOverride: String? {
        get {
            if let scoped = defaults.string(forKey: scope.key("themeOverride")) {
                return scoped
            }
            if scope.isGlobal {
                return defaults.string(forKey: "themeOverride")
            }
            return nil
        }
        set {
            defaults.set(newValue, forKey: scope.key("themeOverride"))
            if scope.isGlobal {
                defaults.set(newValue, forKey: "themeOverride")
            }
        }
    }

    // MARK: - Collapsed Categories

    func collapsedCategories(for teamId: String) -> [String: Bool] {
        let key = scope.key("collapsedCategories_\(teamId)")
        if let states = defaults.dictionary(forKey: key) as? [String: Bool] {
            return states
        }
        if scope.isGlobal {
            let legacyKey = "sidebarCollapsedCategories_\(teamId)"
            return (defaults.dictionary(forKey: legacyKey) as? [String: Bool]) ?? [:]
        }
        return [:]
    }

    func setCollapsedCategories(_ states: [String: Bool], for teamId: String) {
        let key = scope.key("collapsedCategories_\(teamId)")
        defaults.set(states, forKey: key)
        if scope.isGlobal {
            let legacyKey = "sidebarCollapsedCategories_\(teamId)"
            defaults.set(states, forKey: legacyKey)
        }
    }

    // MARK: - Scroll Positions

    func scrollPosition(for channelId: String) -> ChannelScrollPosition? {
        allScrollPositions()[channelId]
    }

    func setScrollPosition(_ position: ChannelScrollPosition?, for channelId: String) {
        var positions = allScrollPositions()
        if let position = position {
            positions[channelId] = position
        } else {
            positions.removeValue(forKey: channelId)
        }
        if let encoded = try? encoder.encode(positions) {
            defaults.set(encoded, forKey: scope.key("scrollPositions"))
        }
    }

    func allScrollPositions() -> [String: ChannelScrollPosition] {
        guard let data = defaults.data(forKey: scope.key("scrollPositions")),
              let positions = try? decoder.decode([String: ChannelScrollPosition].self, from: data) else {
            return [:]
        }
        return positions
    }

    // MARK: - Generic Codable Storage

    func get<T: Decodable>(_ type: T.Type, forKey key: String) -> T? {
        guard let data = defaults.data(forKey: scope.key(key)) else { return nil }
        return try? decoder.decode(type, from: data)
    }

    func set<T: Encodable>(_ value: T?, forKey key: String) {
        if let value = value, let data = try? encoder.encode(value) {
            defaults.set(data, forKey: scope.key(key))
        } else {
            defaults.removeObject(forKey: scope.key(key))
        }
    }
}
