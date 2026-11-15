//
//  Localization.swift
//  mattermost.client
//
//  Small localization facade. UI strings live in Localizable.xcstrings so they
//  can be translated without touching source code.
//

import Foundation

enum L10n {
    static func string(_ key: String, comment: String = "") -> String {
        NSLocalizedString(key, comment: comment)
    }

    static func format(_ key: String, _ arguments: CVarArg...) -> String {
        String(format: NSLocalizedString(key, comment: ""), arguments: arguments)
    }
}
