//
//  SearchSupport.swift
//  mattermost.client
//
//  Pure helpers for global search: query tokenization, highlighting and the
//  filter-pill scopes. Keeping this separate makes the search UI testable.
//

import AppKit

enum SearchSupport {
    static let filterPrefixes = ["from:", "in:", "on:", "before:", "after:"]

    /// Splits a query into words, keeping quoted phrases together.
    static func tokenize(_ query: String) -> [String] {
        var tokens: [String] = []
        var current = ""
        var inQuotes = false
        for character in query {
            if character == "\"" {
                inQuotes.toggle()
                continue
            }
            if character.isWhitespace && !inQuotes {
                if !current.isEmpty {
                    tokens.append(current)
                    current = ""
                }
            } else {
                current.append(character)
            }
        }
        if !current.isEmpty {
            tokens.append(current)
        }
        return tokens
    }

    /// The free-text terms that should be highlighted. Filter scopes such as
    /// `in:town-square` are intentionally excluded.
    static func highlightTerms(_ query: String) -> [String] {
        tokenize(query).filter { token in
            !token.isEmpty && !filterPrefixes.contains { token.lowercased().hasPrefix($0) }
        }
    }

    static func highlightRanges(in text: String, query: String) -> [NSRange] {
        let terms = highlightTerms(query)
        guard !terms.isEmpty else { return [] }
        let nsText = text as NSString
        var ranges: [NSRange] = []
        for term in terms {
            var searchRange = NSRange(location: 0, length: nsText.length)
            while searchRange.length > 0 {
                let found = nsText.range(
                    of: term,
                    options: [.caseInsensitive, .diacriticInsensitive],
                    range: searchRange
                )
                if found.location == NSNotFound { break }
                ranges.append(found)
                let next = NSMaxRange(found)
                guard next < nsText.length else { break }
                searchRange = NSRange(location: next, length: nsText.length - next)
            }
        }
        return ranges
    }

    static func attributedSnippet(
        _ text: String,
        query: String,
        font: NSFont,
        textColor: NSColor,
        highlightColor: NSColor
    ) -> NSAttributedString {
        let attributed = NSMutableAttributedString(
            string: text,
            attributes: [.font: font, .foregroundColor: textColor]
        )
        for range in highlightRanges(in: text, query: query) {
            attributed.addAttributes(
                [
                    .backgroundColor: NSColor.systemYellow.withAlphaComponent(0.35),
                    .foregroundColor: highlightColor,
                ],
                range: range
            )
        }
        return attributed
    }

    /// Returns the text a filter pill should insert into the search field.
    static func filterInsertion(for pill: String, channelName: String?, date: Date = Date()) -> String? {
        switch pill {
        case "From:":
            return "from:"
        case "In:":
            if let channelName = channelName, !channelName.isEmpty {
                return "in:\(channelName) "
            }
            return "in:"
        case "On:":
            return "on:\(dateString(date)) "
        case "Before:":
            return "before:\(dateString(date)) "
        case "After:":
            return "after:\(dateString(date)) "
        default:
            return nil
        }
    }

    private static func dateString(_ date: Date) -> String {
        let formatter = DateFormatter()
        formatter.locale = Locale(identifier: "en_US_POSIX")
        formatter.calendar = Calendar(identifier: .gregorian)
        formatter.dateFormat = "yyyy-MM-dd"
        return formatter.string(from: date)
    }
}
