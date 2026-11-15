//
//  MarkdownRenderingTests.swift
//  mattermost.clientTests
//

import AppKit
import XCTest

#if canImport(mattermost_client)
    @testable import mattermost_client
#endif

@MainActor
final class MarkdownRenderingTests: XCTestCase {

    func testFormattedMessageRendersBlocksAndCodeChrome() {
        let window = makeWindow()
        defer { window.close() }
        let message = """
            # Heading

            - bullet
            1. ordered

            > quoted

            ```swift
            let value = 1
            ```

            | Name | Value |
            | --- | --- |
            | one | 1 |
            """
        let rendered = window.formattedMessage(
            message,
            font: .systemFont(ofSize: 14),
            color: .labelColor
        )
        XCTAssertTrue(rendered.string.contains("Heading"))
        XCTAssertTrue(rendered.string.contains("•  bullet"))
        XCTAssertTrue(rendered.string.contains("1.  ordered"))
        XCTAssertTrue(rendered.string.contains("▎ quoted"))
        XCTAssertTrue(rendered.string.contains("SWIFT"))
        XCTAssertTrue(rendered.string.contains("Copy"))
        XCTAssertTrue(rendered.string.contains("Name │ Value"))
        XCTAssertTrue(rendered.string.contains("one  │ 1"))

        var copyLinkFound = false
        rendered.enumerateAttribute(
            .link,
            in: NSRange(location: 0, length: rendered.length)
        ) { value, _, _ in
            if let url = value as? URL, url.scheme == "mattermost-copy-code" {
                copyLinkFound = true
            }
        }
        XCTAssertTrue(copyLinkFound)
    }

    func testInlineCodeSkipsMentionsChannelsAndEmoji() {
        let window = makeWindow()
        defer { window.close() }
        let rendered = window.formattedMessage(
            "`@alice ~town-square :smile:` and @bob",
            font: .systemFont(ofSize: 14),
            color: .labelColor
        )
        XCTAssertTrue(rendered.string.contains("@alice ~town-square :smile:"))
        XCTAssertFalse(rendered.string.contains("😄"))
    }

    private func makeWindow() -> MainWindow {
        MainWindow(
            contentRect: NSRect(x: 0, y: 0, width: 1000, height: 700),
            styleMask: [.titled, .resizable],
            backing: .buffered,
            defer: true
        )
    }
}
