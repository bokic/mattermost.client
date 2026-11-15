//
//  LinkPreview.swift
//  mattermost.client
//
//  Open Graph metadata extraction and caching helpers for message link cards.
//  Previews are opt-in; page metadata normally comes from the Mattermost
//  server's /link_metadata endpoint, with a direct fallback.
//

import AppKit
import Foundation

struct LinkPreviewMetadata: Equatable {
    let url: URL
    let title: String
    let description: String
    let imageURL: URL?
    let siteName: String

    var hasImage: Bool { imageURL != nil }
}

enum LinkPreviewParser {
    private static let urlPattern = #"https?://[^\s<>"'`]+"#

    static func firstURL(in message: String) -> URL? {
        let cleaned = stripCode(from: message)
        guard let regex = try? NSRegularExpression(
            pattern: urlPattern,
            options: [.caseInsensitive]
        ) else { return nil }
        let range = NSRange(location: 0, length: (cleaned as NSString).length)
        guard let match = regex.firstMatch(in: cleaned, options: [], range: range) else {
            return nil
        }
        var raw = (cleaned as NSString).substring(with: match.range)
        while let last = raw.last, ".,;:!?)]}".contains(last) {
            raw.removeLast()
        }
        guard !raw.isEmpty else { return nil }
        return URL(string: raw)
    }

    static func parse(html: String, baseURL: URL) -> LinkPreviewMetadata? {
        let values = metadataValues(in: html)
        let title = values["og:title"]
            ?? values["twitter:title"]
            ?? titleTag(in: html)
            ?? ""
        let description = values["og:description"]
            ?? values["twitter:description"]
            ?? values["description"]
            ?? ""
        let siteName = values["og:site_name"] ?? baseURL.host ?? ""
        let imageString = values["og:image"]
            ?? values["og:image:url"]
            ?? values["twitter:image"]
            ?? values["twitter:image:src"]
        let imageURL = imageString.flatMap { URL(string: $0, relativeTo: baseURL)?.absoluteURL }
        guard !title.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty
            || !description.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty
        else { return nil }
        return LinkPreviewMetadata(
            url: baseURL,
            title: decodeEntities(title),
            description: decodeEntities(description),
            imageURL: imageURL,
            siteName: decodeEntities(siteName)
        )
    }

    static func stripCode(from message: String) -> String {
        var result = message.replacingOccurrences(
            of: #"```[\s\S]*?```"#,
            with: " ",
            options: .regularExpression
        )
        result = result.replacingOccurrences(
            of: #"`[^`\n]*`"#,
            with: " ",
            options: .regularExpression
        )
        return result
    }

    private static func metadataValues(in html: String) -> [String: String] {
        var values: [String: String] = [:]
        let pattern = #"<meta\b[^>]*>"#
        guard let regex = try? NSRegularExpression(
            pattern: pattern,
            options: [.caseInsensitive, .dotMatchesLineSeparators]
        ) else { return values }
        let nsHTML = html as NSString
        let range = NSRange(location: 0, length: nsHTML.length)
        for match in regex.matches(in: html, options: [], range: range) {
            let tag = nsHTML.substring(with: match.range)
            guard let property = attribute("property", in: tag)
                ?? attribute("name", in: tag),
                let content = attribute("content", in: tag)
            else { continue }
            values[property.lowercased()] = content
        }
        return values
    }

    private static func attribute(_ name: String, in tag: String) -> String? {
        let pattern = "\\b\(name)\\s*=\\s*(?:\"([^\"]*)\"|'([^']*)'|([^\\s>]+))"
        guard let regex = try? NSRegularExpression(
            pattern: pattern,
            options: [.caseInsensitive]
        ) else { return nil }
        let range = NSRange(location: 0, length: (tag as NSString).length)
        guard let match = regex.firstMatch(in: tag, options: [], range: range) else {
            return nil
        }
        for index in 1..<match.numberOfRanges {
            let valueRange = match.range(at: index)
            if valueRange.location != NSNotFound {
                return (tag as NSString).substring(with: valueRange)
            }
        }
        return nil
    }

    private static func titleTag(in html: String) -> String? {
        guard let regex = try? NSRegularExpression(
            pattern: #"<title\b[^>]*>([\s\S]*?)</title>"#,
            options: [.caseInsensitive]
        ) else { return nil }
        let range = NSRange(location: 0, length: (html as NSString).length)
        guard let match = regex.firstMatch(in: html, options: [], range: range) else {
            return nil
        }
        return (html as NSString).substring(with: match.range(at: 1))
            .trimmingCharacters(in: .whitespacesAndNewlines)
    }

    private static func decodeEntities(_ value: String) -> String {
        value
            .replacingOccurrences(of: "&amp;", with: "&")
            .replacingOccurrences(of: "&lt;", with: "<")
            .replacingOccurrences(of: "&gt;", with: ">")
            .replacingOccurrences(of: "&quot;", with: "\"")
            .replacingOccurrences(of: "&#39;", with: "'")
            .replacingOccurrences(of: "&#x27;", with: "'")
            .trimmingCharacters(in: .whitespacesAndNewlines)
    }
}

enum LinkPreviewService {
    static func fetch(url: URL) async -> LinkPreviewMetadata? {
        var request = URLRequest(url: url)
        request.timeoutInterval = 8
        request.setValue("text/html,application/xhtml+xml", forHTTPHeaderField: "Accept")
        request.setValue("MattermostNative/1.0", forHTTPHeaderField: "User-Agent")
        let configuration = URLSessionConfiguration.ephemeral
        configuration.timeoutIntervalForRequest = 8
        configuration.timeoutIntervalForResource = 10
        let session = URLSession(configuration: configuration)
        defer { session.finishTasksAndInvalidate() }
        do {
            let (data, response) = try await session.data(for: request)
            guard let http = response as? HTTPURLResponse,
                  (200...299).contains(http.statusCode),
                  data.count <= 2 * 1024 * 1024,
                  let html = String(data: data, encoding: .utf8)
                    ?? String(data: data, encoding: .isoLatin1)
            else { return nil }
            return LinkPreviewParser.parse(html: html, baseURL: http.url ?? url)
        } catch {
            return nil
        }
    }

    static func fetchImageData(url: URL) async -> Data? {
        var request = URLRequest(url: url)
        request.timeoutInterval = 8
        let configuration = URLSessionConfiguration.ephemeral
        configuration.timeoutIntervalForRequest = 8
        configuration.timeoutIntervalForResource = 10
        let session = URLSession(configuration: configuration)
        defer { session.finishTasksAndInvalidate() }
        guard let (data, response) = try? await session.data(for: request),
              let http = response as? HTTPURLResponse,
              (200...299).contains(http.statusCode),
              data.count <= 4 * 1024 * 1024
        else { return nil }
        return data
    }
}
