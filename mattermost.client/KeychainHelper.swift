//
//  KeychainHelper.swift
//  mattermost.client
//

import Foundation

/// Stores persistent credentials and tokens without triggering macOS Keychain system authorization dialogs.
/// Under App Sandbox, preferences are isolated to the app's private container directory.
enum KeychainHelper {
    private static let keyPrefix = "auth_"

    static func set(_ value: String, forKey account: String) {
        let storageKey = keyPrefix + account
        guard !value.isEmpty else {
            delete(forKey: account)
            return
        }
        UserDefaults.standard.set(value, forKey: storageKey)
        // Clean up any legacy un-prefixed key
        if UserDefaults.standard.object(forKey: account) != nil {
            UserDefaults.standard.removeObject(forKey: account)
        }
    }

    static func get(forKey account: String) -> String? {
        let storageKey = keyPrefix + account
        if let value = UserDefaults.standard.string(forKey: storageKey), !value.isEmpty {
            return value
        }
        // Fallback: check legacy un-prefixed key in UserDefaults
        if let legacy = UserDefaults.standard.string(forKey: account), !legacy.isEmpty {
            set(legacy, forKey: account)
            return legacy
        }
        return nil
    }

    static func delete(forKey account: String) {
        UserDefaults.standard.removeObject(forKey: keyPrefix + account)
        UserDefaults.standard.removeObject(forKey: account)
    }
}
