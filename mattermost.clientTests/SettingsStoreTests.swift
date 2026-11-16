//
//  SettingsStoreTests.swift
//  mattermost.clientTests
//

import XCTest
@testable import mattermost_client

@MainActor
final class SettingsStoreTests: XCTestCase {

    private func makeStore(scope: StoreScope = .global) -> (SettingsStore, UserDefaults, String) {
        let suite = "SettingsStoreTests.\(UUID().uuidString)"
        let defaults = UserDefaults(suiteName: suite)!
        let store = SettingsStore(scope: scope, defaults: defaults)
        return (store, defaults, suite)
    }

    func testStoreScopeKeyGeneration() {
        let global = StoreScope.global
        XCTAssertEqual(global.key("testKey"), "mm.global.testKey")

        let scoped = StoreScope(server: "https://chat.example.com:8065/", userId: "user_abc")
        XCTAssertEqual(scoped.server, "chat.example.com")
        XCTAssertEqual(scoped.userId, "user_abc")
        XCTAssertEqual(scoped.key("recentSearches"), "mm.chat_example_com.user_abc.recentSearches")

        let scopedEmpty = StoreScope(server: "", userId: "")
        XCTAssertTrue(scopedEmpty.isGlobal)
        XCTAssertEqual(scopedEmpty.key("test"), "mm.global.test")
    }

    func testMigrationFromLegacyDefaults() {
        let suite = "SettingsStoreTests.Migration.\(UUID().uuidString)"
        let testDefaults = UserDefaults(suiteName: suite)!
        defer { testDefaults.removePersistentDomain(forName: suite) }

        testDefaults.set(["smile", "wave"], forKey: "recentEmojis")
        testDefaults.set(["+1", "heart"], forKey: "recentReactions")
        testDefaults.set(["query1", "query2"], forKey: "recentSearches")
        testDefaults.set("In a meeting", forKey: "customStatusText")
        testDefaults.set("calendar", forKey: "customStatusEmoji")
        testDefaults.set(420.0, forKey: "rhsWidth")
        testDefaults.set(false, forKey: "loadRemoteImagesAutomatically")
        testDefaults.set(true, forKey: "linkPreviewsEnabled")

        let store = SettingsStore(scope: .global, defaults: testDefaults)

        XCTAssertEqual(store.recentEmojis, ["smile", "wave"])
        XCTAssertEqual(store.recentReactions, ["+1", "heart"])
        XCTAssertEqual(store.recentSearches, ["query1", "query2"])
        XCTAssertEqual(store.customStatusText, "In a meeting")
        XCTAssertEqual(store.customStatusEmoji, "calendar")
        XCTAssertEqual(store.rhsWidth, 420.0)
        XCTAssertFalse(store.loadRemoteImagesAutomatically)
        XCTAssertTrue(store.linkPreviewsEnabled)
        XCTAssertEqual(store.schemaVersion, SettingsStore.currentSchemaVersion)
    }

    func testScopeIsolation() {
        let (store, defaults, suite) = makeStore(scope: StoreScope(server: "serverA", userId: "userA"))
        defer { defaults.removePersistentDomain(forName: suite) }

        store.recentSearches = ["searchA"]
        store.rhsWidth = 450.0

        store.scope = StoreScope(server: "serverB", userId: "userB")
        XCTAssertEqual(store.recentSearches, [])
        XCTAssertEqual(store.rhsWidth, 380.0)

        store.recentSearches = ["searchB"]
        store.rhsWidth = 320.0

        store.scope = StoreScope(server: "serverA", userId: "userA")
        XCTAssertEqual(store.recentSearches, ["searchA"])
        XCTAssertEqual(store.rhsWidth, 450.0)
    }

    func testCustomStatusExpiration() {
        let (store, defaults, suite) = makeStore(scope: .global)
        defer { defaults.removePersistentDomain(forName: suite) }

        let pastDate = Date().addingTimeInterval(-60)
        store.customStatusText = "Expired Status"
        store.customStatusEmoji = "hourglass"
        store.customStatusExpiresAt = pastDate

        XCTAssertEqual(store.customStatusText, "")
        XCTAssertEqual(store.customStatusEmoji, "")
        XCTAssertNil(store.customStatusExpiresAt)

        let futureDate = Date().addingTimeInterval(3600)
        store.customStatusText = "Active Status"
        store.customStatusEmoji = "rocket"
        store.customStatusExpiresAt = futureDate

        XCTAssertEqual(store.customStatusText, "Active Status")
        XCTAssertEqual(store.customStatusEmoji, "rocket")
        XCTAssertNotNil(store.customStatusExpiresAt)

        store.clearCustomStatus()
        XCTAssertEqual(store.customStatusText, "")
        XCTAssertEqual(store.customStatusEmoji, "")
        XCTAssertNil(store.customStatusExpiresAt)
    }

    func testRecentCustomStatusesDeduplicationAndCap() {
        let (store, defaults, suite) = makeStore(scope: .global)
        defer { defaults.removePersistentDomain(forName: suite) }

        store.saveRecentCustomStatus(emoji: "1️⃣", text: "Status 1", durationIndex: 1)
        store.saveRecentCustomStatus(emoji: "2️⃣", text: "Status 2", durationIndex: 2)
        store.saveRecentCustomStatus(emoji: "3️⃣", text: "Status 3", durationIndex: 3)
        store.saveRecentCustomStatus(emoji: "4️⃣", text: "Status 4", durationIndex: 4)
        store.saveRecentCustomStatus(emoji: "5️⃣", text: "Status 5", durationIndex: 5)
        store.saveRecentCustomStatus(emoji: "6️⃣", text: "Status 6", durationIndex: 6)

        let list = store.recentCustomStatuses
        XCTAssertEqual(list.count, 5)
        XCTAssertEqual(list.first?.text, "Status 6")
        XCTAssertFalse(list.contains(where: { $0.text == "Status 1" }))

        // Re-saving Status 3 moves it to front
        store.saveRecentCustomStatus(emoji: "🎯", text: "Status 3", durationIndex: 1)
        let updated = store.recentCustomStatuses
        XCTAssertEqual(updated.count, 5)
        XCTAssertEqual(updated.first?.text, "Status 3")
        XCTAssertEqual(updated.first?.emoji, "🎯")
    }

    func testScrollPositionPersistence() {
        let (store, defaults, suite) = makeStore(scope: StoreScope(server: "serverA", userId: "userA"))
        defer { defaults.removePersistentDomain(forName: suite) }

        let pos1 = ChannelScrollPosition(postId: "post99", offset: 128.5)
        store.setScrollPosition(pos1, for: "chan1")

        let retrieved = store.scrollPosition(for: "chan1")
        XCTAssertNotNil(retrieved)
        XCTAssertEqual(retrieved?.postId, "post99")
        XCTAssertEqual(retrieved?.offset, 128.5)

        let all = store.allScrollPositions()
        XCTAssertEqual(all["chan1"]?.offset, 128.5)

        store.setScrollPosition(nil, for: "chan1")
        XCTAssertNil(store.scrollPosition(for: "chan1"))
    }

    func testCollapsedCategories() {
        let (store, defaults, suite) = makeStore(scope: StoreScope(server: "server1", userId: "user1"))
        defer { defaults.removePersistentDomain(forName: suite) }

        let initial = store.collapsedCategories(for: "teamA")
        XCTAssertTrue(initial.isEmpty)

        store.setCollapsedCategories(["channels": true, "dms": false], for: "teamA")
        let updated = store.collapsedCategories(for: "teamA")
        XCTAssertEqual(updated["channels"], true)
        XCTAssertEqual(updated["dms"], false)
    }

    func testGenericCodableGetAndSet() {
        let (store, defaults, suite) = makeStore(scope: .global)
        defer { defaults.removePersistentDomain(forName: suite) }

        struct MyConfig: Codable, Equatable {
            let name: String
            let count: Int
        }

        let config = MyConfig(name: "Test", count: 42)
        store.set(config, forKey: "custom_config")

        let retrieved = store.get(MyConfig.self, forKey: "custom_config")
        XCTAssertEqual(retrieved, config)

        store.set(Optional<MyConfig>.none, forKey: "custom_config")
        XCTAssertNil(store.get(MyConfig.self, forKey: "custom_config"))
    }
}
