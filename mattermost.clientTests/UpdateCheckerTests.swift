//
//  UpdateCheckerTests.swift
//  mattermost.clientTests
//

import AppKit
import Foundation
import XCTest

#if canImport(mattermost_client)
    @testable import mattermost_client
#endif

final class UpdateMockURLProtocol: URLProtocol, @unchecked Sendable {
    nonisolated(unsafe) static var mockData: Data?
    nonisolated(unsafe) static var mockResponse: HTTPURLResponse?
    nonisolated(unsafe) static var mockError: Error?

    override class func canInit(with request: URLRequest) -> Bool {
        true
    }

    override class func canonicalRequest(for request: URLRequest) -> URLRequest {
        request
    }

    override func startLoading() {
        if let error = Self.mockError {
            client?.urlProtocol(self, didFailWithError: error)
            return
        }

        if let response = Self.mockResponse {
            client?.urlProtocol(self, didReceive: response, cacheStoragePolicy: .notAllowed)
        }

        if let data = Self.mockData {
            client?.urlProtocol(self, didLoad: data)
        }

        client?.urlProtocolDidFinishLoading(self)
    }

    override func stopLoading() {}
}

@MainActor
final class UpdateCheckerTests: XCTestCase {

    override func setUp() {
        super.setUp()
        UpdateMockURLProtocol.mockData = nil
        UpdateMockURLProtocol.mockResponse = nil
        UpdateMockURLProtocol.mockError = nil
    }

    override func tearDown() {
        super.tearDown()
        UpdateMockURLProtocol.mockData = nil
        UpdateMockURLProtocol.mockResponse = nil
        UpdateMockURLProtocol.mockError = nil
        UserDefaults.standard.removeObject(forKey: "skippedUpdateVersion")
        UserDefaults.standard.removeObject(forKey: "automaticallyChecksForUpdates")
        UserDefaults.standard.removeObject(forKey: "lastUpdateCheckDate")
    }

    private func makeMockSession() -> URLSession {
        let config = URLSessionConfiguration.ephemeral
        config.protocolClasses = [UpdateMockURLProtocol.self]
        return URLSession(configuration: config)
    }

    func testParseVersionComponents() {
        XCTAssertEqual(UpdateChecker.parseVersionComponents("0.8.0.48"), [0, 8, 0, 48])
        XCTAssertEqual(UpdateChecker.parseVersionComponents("v1.2.3"), [1, 2, 3])
        XCTAssertEqual(UpdateChecker.parseVersionComponents("V2.0"), [2, 0])
        XCTAssertEqual(UpdateChecker.parseVersionComponents("  0.9.0-beta1 "), [0, 9, 0])
    }

    func testCompareVersions() {
        XCTAssertEqual(UpdateChecker.compareVersions("0.9.0", "0.8.0.48"), .orderedDescending)
        XCTAssertEqual(UpdateChecker.compareVersions("0.8.0.48", "0.8.0.47"), .orderedDescending)
        XCTAssertEqual(UpdateChecker.compareVersions("0.8.0", "0.8.0"), .orderedSame)
        XCTAssertEqual(UpdateChecker.compareVersions("0.8.0", "0.8.0.1"), .orderedAscending)
        XCTAssertEqual(UpdateChecker.compareVersions("1.0.0", "0.99.99"), .orderedDescending)
        XCTAssertEqual(UpdateChecker.compareVersions("0.8", "0.8.0"), .orderedSame)
    }

    func testIsVersionNewerThan() {
        XCTAssertTrue(UpdateChecker.isVersion("0.9.0", newerThan: "0.8.0"))
        XCTAssertTrue(UpdateChecker.isVersion("0.8.0.50", newerThan: "0.8.0.48"))
        XCTAssertFalse(UpdateChecker.isVersion("0.8.0", newerThan: "0.8.0"))
        XCTAssertFalse(UpdateChecker.isVersion("0.8.0", newerThan: "0.9.0"))
        XCTAssertFalse(UpdateChecker.isVersion("0.8.0", newerThan: "0.8.0.1"))
        XCTAssertTrue(UpdateChecker.isVersion("0.8.0", newerThan: "Development"))
    }

    func testAppcastXMLParsing() throws {
        let xmlString = """
        <?xml version="1.0" encoding="utf-8"?>
        <rss version="2.0" xmlns:sparkle="http://www.andymatuschak.org/xml-namespaces/sparkle">
          <channel>
            <title>Mattermost Updates</title>
            <item>
              <title>Version 0.9.0</title>
              <pubDate>Sun, 15 Nov 2026 22:00:00 +0000</pubDate>
              <sparkle:releaseNotesLink>https://github.com/bokic/mattermost.client/releases/tag/v0.9.0</sparkle:releaseNotesLink>
              <sparkle:minimumSystemVersion>15.0</sparkle:minimumSystemVersion>
              <enclosure url="https://example.com/mattermost-0.9.0.dmg"
                         sparkle:version="0.9.0"
                         sparkle:shortVersionString="0.9.0"
                         sparkle:sha256="abc123def456"
                         length="33554432"
                         type="application/octet-stream" />
            </item>
          </channel>
        </rss>
        """

        let data = xmlString.data(using: .utf8)!
        let items = try AppcastParser.parse(data: data)

        XCTAssertEqual(items.count, 1)
        let item = items[0]
        XCTAssertEqual(item.version, "0.9.0")
        XCTAssertEqual(item.shortVersionString, "0.9.0")
        XCTAssertEqual(item.downloadURL.absoluteString, "https://example.com/mattermost-0.9.0.dmg")
        XCTAssertEqual(item.releaseNotesURL?.absoluteString, "https://github.com/bokic/mattermost.client/releases/tag/v0.9.0")
        XCTAssertEqual(item.minimumSystemVersion, "15.0")
        XCTAssertEqual(item.sha256, "abc123def456")
        XCTAssertEqual(item.fileSize, 33554432)
        XCTAssertNotNil(item.pubDate)
    }

    func testCheckFeedDetectsUpdateAvailable() async {
        let xmlString = """
        <?xml version="1.0" encoding="utf-8"?>
        <rss version="2.0" xmlns:sparkle="http://www.andymatuschak.org/xml-namespaces/sparkle">
          <channel>
            <item>
              <title>Version 1.0.0</title>
              <enclosure url="https://example.com/mattermost-1.0.0.dmg"
                         sparkle:version="1.0.0"
                         sparkle:shortVersionString="1.0.0"
                         length="34000000"
                         type="application/octet-stream" />
            </item>
          </channel>
        </rss>
        """

        let url = URL(string: "https://example.com/appcast.xml")!
        UpdateMockURLProtocol.mockData = xmlString.data(using: .utf8)
        UpdateMockURLProtocol.mockResponse = HTTPURLResponse(
            url: url,
            statusCode: 200,
            httpVersion: nil,
            headerFields: ["Content-Type": "application/xml"]
        )

        let session = makeMockSession()
        let result = await UpdateChecker.shared.checkFeed(
            url: url,
            currentVersion: "0.8.0",
            session: session
        )

        switch result {
        case .updateAvailable(let item):
            XCTAssertEqual(item.version, "1.0.0")
            XCTAssertEqual(item.downloadURL.absoluteString, "https://example.com/mattermost-1.0.0.dmg")
        default:
            XCTFail("Expected updateAvailable, got \(result)")
        }
    }

    func testCheckFeedReportsUpToDateWhenCurrentIsNewer() async {
        let xmlString = """
        <?xml version="1.0" encoding="utf-8"?>
        <rss version="2.0" xmlns:sparkle="http://www.andymatuschak.org/xml-namespaces/sparkle">
          <channel>
            <item>
              <title>Version 0.8.0</title>
              <enclosure url="https://example.com/mattermost-0.8.0.dmg"
                         sparkle:version="0.8.0"
                         sparkle:shortVersionString="0.8.0"
                         length="30000000"
                         type="application/octet-stream" />
            </item>
          </channel>
        </rss>
        """

        let url = URL(string: "https://example.com/appcast.xml")!
        UpdateMockURLProtocol.mockData = xmlString.data(using: .utf8)
        UpdateMockURLProtocol.mockResponse = HTTPURLResponse(
            url: url,
            statusCode: 200,
            httpVersion: nil,
            headerFields: ["Content-Type": "application/xml"]
        )

        let session = makeMockSession()
        let result = await UpdateChecker.shared.checkFeed(
            url: url,
            currentVersion: "0.9.0",
            session: session
        )

        XCTAssertEqual(result, .upToDate)
    }

    func testCheckFeedHandlesNetworkError() async {
        let url = URL(string: "https://example.com/appcast.xml")!
        UpdateMockURLProtocol.mockError = NSError(
            domain: NSURLErrorDomain,
            code: NSURLErrorNotConnectedToInternet,
            userInfo: [NSLocalizedDescriptionKey: "The Internet connection appears to be offline."]
        )

        let session = makeMockSession()
        let result = await UpdateChecker.shared.checkFeed(
            url: url,
            currentVersion: "0.8.0",
            session: session
        )

        switch result {
        case .error(let msg):
            XCTAssertTrue(msg.contains("Internet connection") || msg.contains("offline"))
        default:
            XCTFail("Expected error, got \(result)")
        }
    }

    func testSkippedVersionAndAutoCheckPreferences() {
        let checker = UpdateChecker.shared

        XCTAssertNil(checker.skippedUpdateVersion)
        checker.skippedUpdateVersion = "1.0.0"
        XCTAssertEqual(checker.skippedUpdateVersion, "1.0.0")

        XCTAssertTrue(checker.automaticallyChecksForUpdates)
        checker.automaticallyChecksForUpdates = false
        XCTAssertFalse(checker.automaticallyChecksForUpdates)
    }
}
