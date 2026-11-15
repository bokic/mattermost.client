//
//  Localization.swift
//  mattermost.client
//
//  Localization facade. UI strings live in Localizable.xcstrings so they
//  can be translated without touching source code.
//

import Foundation

public enum L10n {
    public static let bundle: Bundle = {
        #if SWIFT_PACKAGE
            return Bundle.module
        #else
            return Bundle(for: MainWindow.self)
        #endif
    }()

    public nonisolated(unsafe) static var overrideLocale: String?

    public static func string(_ key: String, comment: String = "") -> String {
        if let locale = overrideLocale,
            let path = bundle.path(forResource: locale, ofType: "lproj"),
            let locBundle = Bundle(path: path)
        {
            return locBundle.localizedString(forKey: key, value: key, table: nil)
        }
        return NSLocalizedString(key, bundle: bundle, comment: comment)
    }

    public static func format(_ key: String, _ arguments: CVarArg...) -> String {
        let formatString = string(key)
        return String(format: formatString, arguments: arguments)
    }

    public static func localizedString(for key: String, locale: String) -> String {
        if let path = bundle.path(forResource: locale, ofType: "lproj"),
            let locBundle = Bundle(path: path)
        {
            return locBundle.localizedString(forKey: key, value: key, table: nil)
        }
        return string(key)
    }

    public static var availableLocales: [String] {
        bundle.localizations
    }
}
