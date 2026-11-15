//
//  UpdateChecker.swift
//  mattermost.client
//
//  Lightweight, signed appcast and auto-update mechanism.
//  Parses Sparkle/RSS appcasts, compares semver and build versions,
//  and presents native user-facing update prompts.
//

import AppKit
import Foundation

public struct AppcastItem: Equatable, Sendable {
    public let version: String
    public let shortVersionString: String
    public let downloadURL: URL
    public let releaseNotesURL: URL?
    public let releaseNotesText: String?
    public let pubDate: Date?
    public let minimumSystemVersion: String?
    public let edSignature: String?
    public let dsaSignature: String?
    public let sha256: String?
    public let fileSize: Int64?

    public init(
        version: String,
        shortVersionString: String,
        downloadURL: URL,
        releaseNotesURL: URL? = nil,
        releaseNotesText: String? = nil,
        pubDate: Date? = nil,
        minimumSystemVersion: String? = nil,
        edSignature: String? = nil,
        dsaSignature: String? = nil,
        sha256: String? = nil,
        fileSize: Int64? = nil
    ) {
        self.version = version
        self.shortVersionString = shortVersionString
        self.downloadURL = downloadURL
        self.releaseNotesURL = releaseNotesURL
        self.releaseNotesText = releaseNotesText
        self.pubDate = pubDate
        self.minimumSystemVersion = minimumSystemVersion
        self.edSignature = edSignature
        self.dsaSignature = dsaSignature
        self.sha256 = sha256
        self.fileSize = fileSize
    }
}

public enum UpdateCheckResult: Equatable, Sendable {
    case updateAvailable(AppcastItem)
    case upToDate
    case error(String)
}

public final class AppcastParser: NSObject, XMLParserDelegate, @unchecked Sendable {
    private var items: [AppcastItem] = []
    private var currentElement = ""
    private var currentTitle = ""
    private var currentPubDate = ""
    private var currentReleaseNotesLink = ""
    private var currentDescription = ""
    private var currentMinSystem = ""
    private var inItem = false

    // Enclosure attributes
    private var enclosureURL: URL?
    private var enclosureVersion = ""
    private var enclosureShortVersion = ""
    private var enclosureEdSignature: String?
    private var enclosureDsaSignature: String?
    private var enclosureSha256: String?
    private var enclosureLength: Int64?

    nonisolated(unsafe) private static let rfc2822Formatter: DateFormatter = {
        let f = DateFormatter()
        f.locale = Locale(identifier: "en_US_POSIX")
        f.dateFormat = "EEE, dd MMM yyyy HH:mm:ss Z"
        return f
    }()

    nonisolated(unsafe) private static let iso8601Formatter: ISO8601DateFormatter = {
        let f = ISO8601DateFormatter()
        f.formatOptions = [.withInternetDateTime, .withFractionalSeconds]
        return f
    }()

    public static func parse(data: Data) throws -> [AppcastItem] {
        let parser = AppcastParser()
        let xmlParser = XMLParser(data: data)
        xmlParser.delegate = parser
        xmlParser.shouldProcessNamespaces = true
        xmlParser.shouldReportNamespacePrefixes = true
        guard xmlParser.parse() else {
            let err = xmlParser.parserError?.localizedDescription ?? "XML parse failed"
            throw NSError(domain: "AppcastParser", code: 1, userInfo: [NSLocalizedDescriptionKey: err])
        }
        return parser.items
    }

    public func parser(
        _ parser: XMLParser,
        didStartElement elementName: String,
        namespaceURI: String?,
        qualifiedName qName: String?,
        attributes attributeDict: [String: String] = [:]
    ) {
        let localName = elementName.lowercased()
        currentElement = localName

        if localName == "item" {
            inItem = true
            currentTitle = ""
            currentPubDate = ""
            currentReleaseNotesLink = ""
            currentDescription = ""
            currentMinSystem = ""
            enclosureURL = nil
            enclosureVersion = ""
            enclosureShortVersion = ""
            enclosureEdSignature = nil
            enclosureDsaSignature = nil
            enclosureSha256 = nil
            enclosureLength = nil
        } else if inItem && localName == "enclosure" {
            for (key, val) in attributeDict {
                let lowerKey = key.lowercased()
                if lowerKey == "url" {
                    enclosureURL = URL(string: val)
                } else if lowerKey.contains("shortversionstring") {
                    enclosureShortVersion = val
                } else if lowerKey.contains("version") {
                    enclosureVersion = val
                } else if lowerKey.contains("edsignature") {
                    enclosureEdSignature = val
                } else if lowerKey.contains("dsasignature") {
                    enclosureDsaSignature = val
                } else if lowerKey.contains("sha256") || lowerKey.contains("checksum") {
                    enclosureSha256 = val
                } else if lowerKey == "length" {
                    enclosureLength = Int64(val)
                }
            }
        }
    }

    public func parser(_ parser: XMLParser, foundCharacters string: String) {
        guard inItem else { return }
        switch currentElement {
        case "title":
            currentTitle += string
        case "pubdate":
            currentPubDate += string
        case "releasenoteslink":
            currentReleaseNotesLink += string
        case "description":
            currentDescription += string
        case "minimumsystemversion":
            currentMinSystem += string
        default:
            break
        }
    }

    public func parser(_ parser: XMLParser, foundCDATA CDATABlock: Data) {
        guard inItem else { return }
        if let string = String(data: CDATABlock, encoding: .utf8) {
            if currentElement == "description" {
                currentDescription += string
            }
        }
    }

    public func parser(
        _ parser: XMLParser,
        didEndElement elementName: String,
        namespaceURI: String?,
        qualifiedName qName: String?
    ) {
        let localName = elementName.lowercased()
        if localName == "item" {
            inItem = false
            guard let downloadURL = enclosureURL else { return }

            let cleanTitle = currentTitle.trimmingCharacters(in: .whitespacesAndNewlines)
            let version = enclosureVersion.isEmpty ? cleanTitle : enclosureVersion.trimmingCharacters(in: .whitespacesAndNewlines)
            let shortVersion = enclosureShortVersion.isEmpty ? version : enclosureShortVersion.trimmingCharacters(in: .whitespacesAndNewlines)
            let dateStr = currentPubDate.trimmingCharacters(in: .whitespacesAndNewlines)
            let pubDate = Self.rfc2822Formatter.date(from: dateStr) ?? Self.iso8601Formatter.date(from: dateStr)
            let cleanLink = currentReleaseNotesLink.trimmingCharacters(in: .whitespacesAndNewlines)
            let releaseNotesURL = cleanLink.isEmpty ? nil : URL(string: cleanLink)
            let cleanDesc = currentDescription.trimmingCharacters(in: .whitespacesAndNewlines)
            let notesText = cleanDesc.isEmpty ? nil : cleanDesc
            let minSys = currentMinSystem.trimmingCharacters(in: .whitespacesAndNewlines)

            let item = AppcastItem(
                version: version,
                shortVersionString: shortVersion,
                downloadURL: downloadURL,
                releaseNotesURL: releaseNotesURL,
                releaseNotesText: notesText,
                pubDate: pubDate,
                minimumSystemVersion: minSys.isEmpty ? nil : minSys,
                edSignature: enclosureEdSignature,
                dsaSignature: enclosureDsaSignature,
                sha256: enclosureSha256,
                fileSize: enclosureLength
            )
            items.append(item)
        }
    }
}

@MainActor
public final class UpdateChecker: NSObject {
    public static let shared = UpdateChecker()

    public static let defaultFeedURL = URL(
        string: "https://raw.githubusercontent.com/bokic/mattermost.client/main/appcast.xml"
    )!

    public var feedURL: URL {
        if let custom = UserDefaults.standard.string(forKey: "customUpdateFeedURL"),
            let url = URL(string: custom)
        {
            return url
        }
        if let infoFeed = Bundle.main.object(forInfoDictionaryKey: "SUFeedURL") as? String,
            let url = URL(string: infoFeed)
        {
            return url
        }
        return Self.defaultFeedURL
    }

    public var skippedUpdateVersion: String? {
        get { UserDefaults.standard.string(forKey: "skippedUpdateVersion") }
        set { UserDefaults.standard.set(newValue, forKey: "skippedUpdateVersion") }
    }

    public var automaticallyChecksForUpdates: Bool {
        get {
            if UserDefaults.standard.object(forKey: "automaticallyChecksForUpdates") == nil {
                return true
            }
            return UserDefaults.standard.bool(forKey: "automaticallyChecksForUpdates")
        }
        set { UserDefaults.standard.set(newValue, forKey: "automaticallyChecksForUpdates") }
    }

    public var lastUpdateCheckDate: Date? {
        get { UserDefaults.standard.object(forKey: "lastUpdateCheckDate") as? Date }
        set { UserDefaults.standard.set(newValue, forKey: "lastUpdateCheckDate") }
    }

    public static func parseVersionComponents(_ string: String) -> [Int] {
        let clean = string.trimmingCharacters(in: .whitespacesAndNewlines)
            .trimmingCharacters(in: CharacterSet(charactersIn: "vV"))
        let parts = clean.split(separator: ".")
        return parts.compactMap { part in
            let digits = part.prefix(while: { $0.isNumber })
            return Int(digits)
        }
    }

    public static func compareVersions(_ v1: String, _ v2: String) -> ComparisonResult {
        let comps1 = parseVersionComponents(v1)
        let comps2 = parseVersionComponents(v2)
        let maxLen = max(comps1.count, comps2.count)
        for i in 0..<maxLen {
            let c1 = i < comps1.count ? comps1[i] : 0
            let c2 = i < comps2.count ? comps2[i] : 0
            if c1 < c2 { return .orderedAscending }
            if c1 > c2 { return .orderedDescending }
        }
        return .orderedSame
    }

    public static func isVersion(_ candidate: String, newerThan current: String) -> Bool {
        if current.lowercased() == "development" {
            let candidateComps = parseVersionComponents(candidate)
            return !candidateComps.isEmpty
        }
        return compareVersions(candidate, current) == .orderedDescending
    }

    public func checkFeed(
        url: URL? = nil,
        currentVersion: String = AppVersion.versionString,
        session: URLSession = .shared
    ) async -> UpdateCheckResult {
        let targetURL = url ?? feedURL
        do {
            let (data, response) = try await session.data(from: targetURL)
            if let http = response as? HTTPURLResponse, http.statusCode >= 400 {
                return .error("Server returned status \(http.statusCode)")
            }

            let items = try AppcastParser.parse(data: data)
            lastUpdateCheckDate = Date()

            // Find newest candidate supported by current macOS
            let systemVersion = ProcessInfo.processInfo.operatingSystemVersion
            let currentSysString = "\(systemVersion.majorVersion).\(systemVersion.minorVersion)"

            var newestCandidate: AppcastItem?
            for item in items {
                if let minSys = item.minimumSystemVersion, !minSys.isEmpty {
                    if Self.compareVersions(minSys, currentSysString) == .orderedDescending {
                        continue
                    }
                }

                if Self.isVersion(item.version, newerThan: currentVersion) {
                    if let existing = newestCandidate {
                        if Self.compareVersions(item.version, existing.version) == .orderedDescending {
                            newestCandidate = item
                        }
                    } else {
                        newestCandidate = item
                    }
                }
            }

            if let update = newestCandidate {
                return .updateAvailable(update)
            } else {
                return .upToDate
            }
        } catch {
            return .error(error.localizedDescription)
        }
    }

    public func checkForUpdates(
        userInitiated: Bool = true,
        presentingWindow: NSWindow? = nil
    ) {
        if !userInitiated {
            guard automaticallyChecksForUpdates else { return }
            if let last = lastUpdateCheckDate, Date().timeIntervalSince(last) < 24 * 3600 {
                return
            }
        }

        Task { @MainActor [weak self] in
            guard let self = self else { return }
            let currentVer = AppVersion.versionString
            let result = await self.checkFeed(currentVersion: currentVer)

            switch result {
            case .updateAvailable(let item):
                if !userInitiated && item.version == self.skippedUpdateVersion {
                    return
                }
                self.presentUpdateAvailableAlert(item: item, currentVersion: currentVer, window: presentingWindow)

            case .upToDate:
                if userInitiated {
                    self.presentUpToDateAlert(currentVersion: currentVer, window: presentingWindow)
                }

            case .error(let message):
                if userInitiated {
                    self.presentErrorAlert(message: message, window: presentingWindow)
                }
            }
        }
    }

    private func presentUpdateAvailableAlert(item: AppcastItem, currentVersion: String, window: NSWindow?) {
        let alert = NSAlert()
        alert.messageText = L10n.string("A new version of Mattermost is available!")
        let informative = L10n.format(
            "Mattermost %@ is now available (you have %@). Would you like to download it now?",
            item.shortVersionString,
            currentVersion
        )
        alert.informativeText = informative
        alert.addButton(withTitle: L10n.string("Download Update"))
        alert.addButton(withTitle: L10n.string("Remind Me Later"))
        alert.addButton(withTitle: L10n.string("Skip This Version"))

        let handleResponse: (NSApplication.ModalResponse) -> Void = { [weak self] response in
            if response == .alertFirstButtonReturn {
                NSWorkspace.shared.open(item.downloadURL)
            } else if response == .alertThirdButtonReturn {
                self?.skippedUpdateVersion = item.version
            }
        }

        if let win = window ?? NSApp.mainWindow ?? NSApp.keyWindow {
            alert.beginSheetModal(for: win, completionHandler: handleResponse)
        } else {
            let resp = alert.runModal()
            handleResponse(resp)
        }
    }

    private func presentUpToDateAlert(currentVersion: String, window: NSWindow?) {
        let alert = NSAlert()
        alert.messageText = L10n.string("You're up to date!")
        alert.informativeText = L10n.format(
            "Mattermost %@ is currently the newest version.",
            currentVersion
        )
        alert.addButton(withTitle: L10n.string("OK"))
        if let win = window ?? NSApp.mainWindow ?? NSApp.keyWindow {
            alert.beginSheetModal(for: win, completionHandler: nil)
        } else {
            alert.runModal()
        }
    }

    private func presentErrorAlert(message: String, window: NSWindow?) {
        let alert = NSAlert()
        alert.alertStyle = .warning
        alert.messageText = L10n.string("Update Check Failed")
        alert.informativeText = L10n.format("Could not check for updates: %@", message)
        alert.addButton(withTitle: L10n.string("OK"))
        if let win = window ?? NSApp.mainWindow ?? NSApp.keyWindow {
            alert.beginSheetModal(for: win, completionHandler: nil)
        } else {
            alert.runModal()
        }
    }
}
