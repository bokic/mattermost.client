//
//  AppVersion.swift
//  mattermost.client
//
//  Build version display. `build.sh` sets CFBundleShortVersionString from the
//  nearest git tag plus the number of commits since that tag (for example
//  "0.8.0.1"), so the main window title identifies the exact build.
//

import Foundation

enum AppVersion {
    static func title(base: String, version: String?) -> String {
        guard let version = version, !version.isEmpty else { return base }
        return "\(base) \(version)"
    }

    static var windowTitle: String {
        let version = Bundle.main.object(forInfoDictionaryKey: "CFBundleShortVersionString") as? String
        return title(base: "Mattermost", version: version)
    }
}
