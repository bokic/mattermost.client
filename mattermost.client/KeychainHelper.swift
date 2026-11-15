//
//  KeychainHelper.swift
//  mattermost.client
//
//  Stores the bearer token and account password.
//
//  Release builds use generic-password items in the macOS Keychain scoped to this
//  application. Debug builds use UserDefaults instead: rebuilding an ad-hoc or
//  development-signed app changes its code signature, which makes macOS ask for the
//  login-keychain password on every launch. Plaintext storage keeps the developer
//  loop prompt-free and never ships in a release build (`#if DEBUG`).
//

import Foundation
import Security

enum KeychainHelper {
    /// Service name that scopes Keychain items to this application.
    private static let service = "com.bbarbulovski.mattermost-client.credentials"

    /// Legacy plaintext keys written by earlier builds.
    private static let legacyPrefix = "auth_"

    /// Debug-build preference prefix for plaintext credentials.
    static let debugStorePrefix = "debugCredential."

    /// True when credentials are stored in UserDefaults rather than the Keychain.
    static var usesDebugCredentialStore: Bool {
        #if DEBUG
        return true
        #else
        return false
        #endif
    }

    static func set(_ value: String, forKey account: String) {
        guard !value.isEmpty else {
            delete(forKey: account)
            return
        }

        #if DEBUG
        UserDefaults.standard.set(value, forKey: debugStorePrefix + account)
        // Only drop the plaintext copies once the debug store accepted the value.
        UserDefaults.standard.removeObject(forKey: legacyPrefix + account)
        UserDefaults.standard.removeObject(forKey: account)
        #else
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
        #endif
    }

    static func get(forKey account: String) -> String? {
        #if DEBUG
        if let value = UserDefaults.standard.string(forKey: debugStorePrefix + account), !value.isEmpty {
            return value
        }
        #else
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
        #endif

        // Migrate values left by builds that wrote to UserDefaults in plaintext.
        for legacyKey in [legacyPrefix + account, account] {
            if let legacy = UserDefaults.standard.string(forKey: legacyKey), !legacy.isEmpty {
                set(legacy, forKey: account)
                return legacy
            }
        }

        #if !DEBUG
        if status != errSecItemNotFound {
            NSLog("KeychainHelper: failed to read \(account) (status \(status))")
        }
        #endif
        return nil
    }

    /// Moves any plaintext credentials written by older builds into the active store.
    static func migrateLegacyCredentials() {
        #if !DEBUG
        // Debug builds may have left plaintext values behind; release builds never
        // read them, so remove them for hygiene.
        for account in ["token", "password"] {
            UserDefaults.standard.removeObject(forKey: debugStorePrefix + account)
        }
        #endif

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
        #if !DEBUG
        let query: [String: Any] = [
            kSecClass as String: kSecClassGenericPassword,
            kSecAttrService as String: service,
            kSecAttrAccount as String: account
        ]
        SecItemDelete(query as CFDictionary)
        #endif

        UserDefaults.standard.removeObject(forKey: debugStorePrefix + account)
        UserDefaults.standard.removeObject(forKey: legacyPrefix + account)
        UserDefaults.standard.removeObject(forKey: account)
    }
}
