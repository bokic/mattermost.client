//
//  SearchSupportTests.swift
//  mattermost.clientTests
//

import AppKit
import XCTest

#if canImport(mattermost_client)
    @testable import mattermost_client
#endif

final class SearchSupportTests: XCTestCase {

    func testTokenizeKeepsQuotedPhrasesAndDropsQuotes() {
        XCTAssertEqual(
            SearchSupport.tokenize(#"deploy "release notes" from:alice"#),
            ["deploy", "release notes", "from:alice"]
        )
    }

    func testHighlightTermsExcludeFilterScopes() {
        XCTAssertEqual(
            SearchSupport.highlightTerms("deploy in:town-square from:@alice release"),
            ["deploy", "release"]
        )
    }

    func testHighlightRangesAreCaseInsensitiveAndRepeated() {
        let ranges = SearchSupport.highlightRanges(in: "Deploy deploy DEPLOY", query: "deploy")
        XCTAssertEqual(ranges.count, 3)
        XCTAssertEqual(ranges.map { ($0 as NSRange).location }, [0, 7, 14])
    }

    func testHighlightRangesIgnoreEmptyQueries() {
        XCTAssertTrue(SearchSupport.highlightRanges(in: "anything", query: " ").isEmpty)
    }

    func testAttributedSnippetMarksHighlightedTerms() {
        let attributed = SearchSupport.attributedSnippet(
            "deploy the deploy script",
            query: "deploy",
            font: NSFont.systemFont(ofSize: 12),
            textColor: .labelColor,
            highlightColor: .textColor
        )
        XCTAssertEqual(attributed.string, "deploy the deploy script")
        var highlighted = 0
        attributed.enumerateAttribute(
            .backgroundColor,
            in: NSRange(location: 0, length: attributed.length)
        ) { value, _, _ in
            if value != nil { highlighted += 1 }
        }
        XCTAssertEqual(highlighted, 2)
    }

    func testFilterInsertionProducesValidScopes() {
        let date = Calendar.current.date(from: DateComponents(year: 2000, month: 1, day: 2, hour: 12))!
        XCTAssertEqual(SearchSupport.filterInsertion(for: "From:", channelName: nil), "from:")
        XCTAssertEqual(
            SearchSupport.filterInsertion(for: "In:", channelName: "town-square"),
            "in:town-square "
        )
        XCTAssertEqual(SearchSupport.filterInsertion(for: "In:", channelName: nil), "in:")
        XCTAssertEqual(
            SearchSupport.filterInsertion(for: "On:", channelName: nil, date: date),
            "on:2000-01-02 "
        )
        XCTAssertEqual(
            SearchSupport.filterInsertion(for: "Before:", channelName: nil, date: date),
            "before:2000-01-02 "
        )
        XCTAssertEqual(
            SearchSupport.filterInsertion(for: "After:", channelName: nil, date: date),
            "after:2000-01-02 "
        )
        XCTAssertNil(SearchSupport.filterInsertion(for: "Unknown:", channelName: nil))
    }
}
