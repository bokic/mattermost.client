//
//  LinkPreviewTests.swift
//  mattermost.clientTests
//

import AppKit
import XCTest

#if canImport(mattermost_client)
    @testable import mattermost_client
#endif

@MainActor
final class LinkPreviewTests: XCTestCase {

    func testFindsFirstURLAndSkipsCode() {
        XCTAssertEqual(
            LinkPreviewParser.firstURL(in: "See https://example.com/docs.")?.absoluteString,
            "https://example.com/docs"
        )
        XCTAssertEqual(
            LinkPreviewParser.firstURL(
                in: "`https://inline.example.com` https://real.example.com"
            )?.absoluteString,
            "https://real.example.com"
        )
        XCTAssertNil(
            LinkPreviewParser.firstURL(in: "```\nhttps://code.example.com\n```")
        )
    }

    func testParsesOpenGraphMetadata() throws {
        let html = """
            <html><head>
            <meta property="og:title" content="Release &amp; Notes">
            <meta property="og:description" content="What changed">
            <meta property="og:site_name" content="Example">
            <meta property="og:image" content="/preview.png">
            </head></html>
            """
        let preview = try XCTUnwrap(
            LinkPreviewParser.parse(
                html: html,
                baseURL: URL(string: "https://example.com/blog")!
            )
        )
        XCTAssertEqual(preview.title, "Release & Notes")
        XCTAssertEqual(preview.description, "What changed")
        XCTAssertEqual(preview.siteName, "Example")
        XCTAssertEqual(preview.imageURL?.absoluteString, "https://example.com/preview.png")
    }

    func testFallsBackToTitleAndDescriptionMeta() throws {
        let html = """
            <html><head>
            <title>Plain title</title>
            <meta name="description" content="Plain description">
            </head></html>
            """
        let preview = try XCTUnwrap(
            LinkPreviewParser.parse(
                html: html,
                baseURL: URL(string: "https://example.com")!
            )
        )
        XCTAssertEqual(preview.title, "Plain title")
        XCTAssertEqual(preview.description, "Plain description")
    }

    func testEmptyMetadataReturnsNil() {
        XCTAssertNil(
            LinkPreviewParser.parse(
                html: "<html><head></head><body>No metadata</body></html>",
                baseURL: URL(string: "https://example.com")!
            )
        )
    }

    func testServerLinkMetadataDecodes() throws {
        let json = """
            {
              "url": "https://example.com",
              "title": "Example",
              "description": "A site",
              "image_url": "https://example.com/image.png",
              "site_name": "Example"
            }
            """
        let metadata = try JSONDecoder().decode(MMLinkMetadata.self, from: Data(json.utf8))
        XCTAssertEqual(metadata.title, "Example")
        XCTAssertEqual(metadata.image_url, "https://example.com/image.png")
    }

    func testCachedPreviewRendersACardOnRootPost() {
        let window = makeWindow()
        defer { window.close() }
        let url = URL(string: "https://example.com/article")!
        window.linkPreviewsEnabled = true
        window.linkPreviewsByURL[url.absoluteString] = LinkPreviewMetadata(
            url: url,
            title: "Example article",
            description: "Preview text",
            imageURL: nil,
            siteName: "Example"
        )
        let post = MMPost(
            id: "preview",
            create_at: 1,
            update_at: nil,
            edit_at: nil,
            delete_at: nil,
            is_pinned: nil,
            user_id: "user",
            channel_id: "channel",
            root_id: nil,
            original_id: nil,
            message: "Read https://example.com/article",
            type: nil
        )
        let (row, _) = window.createPostRow(post: post, width: 900, timeStr: "12:00")
        XCTAssertNotNil(findPreview(in: row, url: url))
    }

    private func findPreview(in view: NSView, url: URL) -> NSView? {
        if view.identifier?.rawValue == "linkPreview_\(url.absoluteString)" { return view }
        for subview in view.subviews {
            if let found = findPreview(in: subview, url: url) { return found }
        }
        return nil
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
