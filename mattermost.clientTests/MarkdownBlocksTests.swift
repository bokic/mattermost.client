//
//  MarkdownBlocksTests.swift
//  mattermost.clientTests
//

import XCTest

#if canImport(mattermost_client)
    @testable import mattermost_client
#endif

final class MarkdownBlocksTests: XCTestCase {

    func testParsesHeadingsListsQuotesAndRules() {
        let blocks = MarkdownBlockParser.parse(
            """
            # Heading
            ## Subheading
            - bullet
              - nested
            1. first
            2.
            > quoted
            ---
            """
        )
        XCTAssertEqual(blocks[0], .heading(level: 1, text: "Heading"))
        XCTAssertEqual(blocks[1], .heading(level: 2, text: "Subheading"))
        XCTAssertEqual(blocks[2], .bullet(text: "bullet", depth: 0))
        XCTAssertEqual(blocks[3], .bullet(text: "nested", depth: 1))
        XCTAssertEqual(blocks[4], .ordered(number: 1, text: "first", depth: 0))
        XCTAssertEqual(blocks[5], .ordered(number: 2, text: "", depth: 0))
        XCTAssertEqual(blocks[6], .blockquote("quoted"))
        XCTAssertEqual(blocks[7], .horizontalRule)
    }

    func testParsesFencedCodeWithLanguage() {
        let blocks = MarkdownBlockParser.parse(
            """
            before
            ```swift
            let value = 1
            print(value)
            ```
            after
            """
        )
        XCTAssertEqual(blocks.count, 3)
        XCTAssertEqual(blocks[0], .paragraph("before"))
        XCTAssertEqual(
            blocks[1],
            .code(language: "swift", text: "let value = 1\nprint(value)")
        )
        XCTAssertEqual(blocks[2], .paragraph("after"))
    }

    func testParsesTables() {
        let blocks = MarkdownBlockParser.parse(
            """
            | Name | Value |
            | --- | :---: |
            | one | 1 |
            | two | 2 |
            """
        )
        XCTAssertEqual(blocks.count, 1)
        guard case .table(let headers, let rows) = blocks[0] else {
            return XCTFail("Expected table")
        }
        XCTAssertEqual(headers, ["Name", "Value"])
        XCTAssertEqual(rows, [["one", "1"], ["two", "2"]])
    }

    func testParagraphStopsAtNextBlock() {
        let blocks = MarkdownBlockParser.parse(
            """
            line one
            line two
            - list item
            """
        )
        XCTAssertEqual(blocks[0], .paragraph("line one\nline two"))
        XCTAssertEqual(blocks[1], .bullet(text: "list item", depth: 0))
    }

    func testSyntaxHighlighterFindsCodeTokens() {
        let code = "let value = \"hello\" // comment\nreturn 42"
        let highlights = MarkdownSyntaxHighlighter.highlights(in: code, language: "swift")
        func has(_ kind: MarkdownSyntaxHighlighter.TokenKind) -> Bool {
            highlights.contains { $0.1 == kind }
        }
        XCTAssertTrue(has(.keyword))
        XCTAssertTrue(has(.string))
        XCTAssertTrue(has(.comment))
        XCTAssertTrue(has(.number))
    }

    func testBundledEmojiCatalogIsComplete() {
        XCTAssertGreaterThan(EmojiCatalog.entries.count, 1500)
        XCTAssertEqual(EmojiCatalog.entriesByName["thumbsup"]?.glyph, "👍")
        XCTAssertNotNil(EmojiCatalog.entriesByName["rocket"])
    }
}
