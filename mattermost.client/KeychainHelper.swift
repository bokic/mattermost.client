//
//  KeychainHelper.swift
//  mattermost.client
//
//  Stores the bearer token and account password in the macOS Keychain using a
//  generic-password item scoped to this application. Values written by older
//  builds to UserDefaults are migrated automatically the first time they are
//  read, and the plaintext copies are removed.
//

import Foundation
import Security

enum KeychainHelper {
    /// Service name that scopes items to this application.
    private static let service = "com.bbarbulovski.mattermost-client.credentials"

    /// Legacy plaintext keys written by earlier builds.
    private static let legacyPrefix = "auth_"

    static func set(_ value: String, forKey account: String) {
        guard !value.isEmpty else {
            delete(forKey: account)
            return
        }

        let data = Data(value.utf8)
        let query: [String: Any] = [
            kSecClass as String: kSecClassGenericPassword,
            kSecAttrService as String: service,
            kSecAttrAccount as String: account
        ]

        let attributes: [String: Any] = [
            kSecValueData as String: data,
            kSecAttrAccessible as String: kSecAttrAccessibleAfterFirstUnlock
        ]

        var status = SecItemUpdate(query as CFDictionary, attributes as CFDictionary)
        if status == errSecItemNotFound {
            var addQuery = query
            addQuery[kSecValueData as String] = data
            addQuery[kSecAttrAccessible as String] = kSecAttrAccessibleAfterFirstUnlock
            status = SecItemAdd(addQuery as CFDictionary, nil)
        }

        if status == errSecSuccess {
            // Only drop the plaintext copy once the Keychain write succeeded.
            UserDefaults.standard.removeObject(forKey: legacyPrefix + account)
            UserDefaults.standard.removeObject(forKey: account)
        } else {
            NSLog("KeychainHelper: failed to store \(account) (status \(status))")
        }
    }

    static func get(forKey account: String) -> String? {
        let query: [String: Any] = [
            kSecClass as String: kSecClassGenericPassword,
            kSecAttrService as String: service,
            kSecAttrAccount as String: account,
            kSecReturnData as String: true,
            kSecMatchLimit as String: kSecMatchLimitOne
        ]

        var result: AnyObject?
        let status = SecItemCopyMatching(query as CFDictionary, &result)
        if status == errSecSuccess,
           let data = result as? Data,
           let value = String(data: data, encoding: .utf8),
           !value.isEmpty {
            return value
        }

        // Migrate values left by builds that wrote to UserDefaults in plaintext.
        for legacyKey in [legacyPrefix + account, account] {
            if let legacy = UserDefaults.standard.string(forKey: legacyKey), !legacy.isEmpty {
                set(legacy, forKey: account)
                return legacy
            }
        }

        if status != errSecItemNotFound {
            NSLog("KeychainHelper: failed to read \(account) (status \(status))")
        }
        return nil
    }

    /// Moves any plaintext credentials written by older builds into the Keychain.
    static func migrateLegacyCredentials() {
        for account in ["token", "password"] {
            for legacyKey in [legacyPrefix + account, account] {
                if let legacy = UserDefaults.standard.string(forKey: legacyKey), !legacy.isEmpty {
                    set(legacy, forKey: account)
                    break
                }
            }
        }
    }
    
    static func delete(forKey account: String) {
        let query: [String: Any] = [
            kSecClass as String: kSecClassGenericPassword,
            kSecAttrService as String: service,
            kSecAttrAccount as String: account
        ]
        SecItemDelete(query as CFDictionary)

        UserDefaults.standard.removeObject(forKey: legacyPrefix + account)
        UserDefaults.standard.removeObject(forKey: account)
    }
}
