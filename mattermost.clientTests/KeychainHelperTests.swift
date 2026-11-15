//
//  KeychainHelperTests.swift
//  mattermost.clientTests
//

import XCTest

#if canImport(mattermost_client)
    @testable import mattermost_client
#endif

@MainActor
final class KeychainHelperTests: XCTestCase {

    /// Debug builds must never touch the Keychain: the app is ad-hoc signed during
    /// development, so every rebuild changes its signature and would trigger a
    /// login-keychain authorization prompt.
    func testDebugBuildUsesPlaintextStoreWithoutKeychain() {
        #if DEBUG
            XCTAssertTrue(KeychainHelper.usesDebugCredentialStore)

            let account = "unitTest.\(UUID().uuidString)"
            KeychainHelper.set("secret-token", forKey: account)
            XCTAssertEqual(
                UserDefaults.standard.string(forKey: KeychainHelper.debugStorePrefix + account),
                "secret-token"
            )
            XCTAssertEqual(KeychainHelper.get(forKey: account), "secret-token")

            KeychainHelper.delete(forKey: account)
            XCTAssertNil(KeychainHelper.get(forKey: account))
            XCTAssertNil(UserDefaults.standard.string(forKey: KeychainHelper.debugStorePrefix + account))
        #endif
    }

    func testLegacyPlaintextMigratesToActiveStore() {
        #if DEBUG
            let account = "unitTest.\(UUID().uuidString)"
            UserDefaults.standard.set("legacy-value", forKey: "auth_" + account)

            XCTAssertEqual(KeychainHelper.get(forKey: account), "legacy-value")
            XCTAssertEqual(
                UserDefaults.standard.string(forKey: KeychainHelper.debugStorePrefix + account),
                "legacy-value"
            )
            XCTAssertNil(UserDefaults.standard.string(forKey: "auth_" + account))

            KeychainHelper.delete(forKey: account)
        #endif
    }
}
