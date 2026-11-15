//
//  ImageRenderingTests.swift
//  mattermost.clientTests
//

import AppKit
import XCTest

#if canImport(mattermost_client)
    @testable import mattermost_client
#endif

@MainActor
final class ImageRenderingTests: XCTestCase {

    func testMarkdownImageWithoutExtensionBecomesInlineImage() {
        let window = makeWindow()
        defer { window.close() }
        let parsed = window.parseGiphyInMessage(
            "Look ![alt](https://example.com/image?id=42)"
        )
        XCTAssertEqual(parsed.gifURLs, ["https://example.com/image?id=42"])
        XCTAssertEqual(parsed.text, "Look")
    }

    func testGiphyPageLinksStayLinksButDirectMediaBecomesImage() {
        let window = makeWindow()
        defer { window.close() }
        let page = window.parseGiphyInMessage("https://giphy.com/gifs/example-123")
        XCTAssertTrue(page.gifURLs.isEmpty)
        XCTAssertTrue(page.text.contains("giphy.com/gifs/example-123"))

        let media = window.parseGiphyInMessage(
            "https://media.giphy.com/media/abc/giphy.gif"
        )
        XCTAssertEqual(media.gifURLs, ["https://media.giphy.com/media/abc/giphy.gif"])
    }

    func testMultipleImageAttachmentsUseAGrid() {
        let window = makeWindow()
        defer { window.close() }
        let files = (0..<3).map { index in
            MMFileInfo(
                id: "file\(index)",
                name: "image\(index).png",
                extension: "png",
                mime_type: "image/png",
                size: 100,
                width: nil,
                height: nil,
                user_id: "user",
                post_id: "post",
                channel_id: "channel",
                create_at: 1,
                has_preview_image: true
            )
        }
        let (view, height) = window.createAttachmentsView(files, maxWidth: 600)
        XCTAssertEqual(view.subviews.count, 3)
        XCTAssertGreaterThan(height, 0)
        let frames = view.subviews.map(\.frame).sorted { $0.minY < $1.minY }
        XCTAssertEqual(frames[0].minY, frames[1].minY, accuracy: 0.5)
        XCTAssertGreaterThan(frames[2].minY, frames[0].minY)

        for subview in view.subviews {
            XCTAssertEqual(findImageView(in: subview)?.animates, true)
        }
    }

    func testLightboxZoomEnablesCanvasScrollingAndReleasesImage() {
        let window = makeWindow()
        defer { window.close() }
        window.setContentSize(NSSize(width: 1000, height: 700))
        window.updateViews()

        let image = NSImage(size: NSSize(width: 1200, height: 800))
        window.showLightbox(image: image, filename: "large.png")
        window.lightboxScale = 2
        window.layoutLightboxImage()
        XCTAssertGreaterThan(window.lightboxCanvas.frame.width, window.lightboxScrollView.frame.width)
        XCTAssertNotNil(window.lightboxImageView.image)

        window.closeLightbox()
        XCTAssertNil(window.lightboxImageView.image)
        XCTAssertNil(window.lightboxFile)
    }

    private func findImageView(in view: NSView) -> NSImageView? {
        if let imageView = view as? NSImageView { return imageView }
        for subview in view.subviews {
            if let found = findImageView(in: subview) { return found }
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
