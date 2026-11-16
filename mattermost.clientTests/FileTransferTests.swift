//
//  FileTransferTests.swift
//  mattermost.clientTests
//

import XCTest

#if canImport(mattermost_client)
    @testable import mattermost_client
#endif

@MainActor
final class FileTransferTests: XCTestCase {

    // MARK: - Multipart Formatting

    func testSanitizedMultipartFilenameStripsControlCharacters() {
        let dirty = "/path/to/evil\r\nfilename\"test\\.png"
        let clean = FileTransfer.sanitizedMultipartFilename(dirty)
        XCTAssertEqual(clean, "evil__filename_test_.png")
    }

    func testSanitizedMultipartMimeTypeStripsNewlines() {
        let dirty = "image/png\r\nX-Injected: header"
        let clean = FileTransfer.sanitizedMultipartMimeType(dirty)
        XCTAssertEqual(clean, "image/png  X-Injected: header")
    }

    func testMultipartHeaderAndFooter() {
        let header = FileTransfer.multipartHeader(
            boundary: "BOUND",
            filename: "photo.jpg",
            mimeType: "image/jpeg"
        )
        let headerText = String(decoding: header, as: UTF8.self)
        XCTAssertTrue(headerText.contains("--BOUND\r\n"))
        XCTAssertTrue(headerText.contains("filename=\"photo.jpg\""))
        XCTAssertTrue(headerText.contains("Content-Type: image/jpeg\r\n\r\n"))

        let footer = FileTransfer.multipartFooter(boundary: "BOUND")
        let footerText = String(decoding: footer, as: UTF8.self)
        XCTAssertEqual(footerText, "\r\n--BOUND--\r\n")
    }

    func testMultipartBodyCombinesParts() {
        let body = FileTransfer.multipartBody(
            boundary: "BOUND",
            filename: "test.txt",
            mimeType: "text/plain",
            data: Data("hello file".utf8)
        )
        let bodyText = String(decoding: body, as: UTF8.self)
        XCTAssertTrue(bodyText.hasPrefix("--BOUND\r\n"))
        XCTAssertTrue(bodyText.contains("hello file"))
        XCTAssertTrue(bodyText.hasSuffix("\r\n--BOUND--\r\n"))
    }

    // MARK: - Disk Streaming

    func testWriteMultipartFileStreamsToDisk() throws {
        let tempDir = FileManager.default.temporaryDirectory
        let sourceURL = tempDir.appendingPathComponent("source-\(UUID().uuidString).txt")
        let destURL = tempDir.appendingPathComponent("dest-\(UUID().uuidString).txt")
        defer {
            try? FileManager.default.removeItem(at: sourceURL)
            try? FileManager.default.removeItem(at: destURL)
        }

        let testContent = "streaming chunked content for testing file upload"
        try testContent.write(to: sourceURL, atomically: true, encoding: .utf8)

        try FileTransfer.writeMultipartFile(
            sourceURL: sourceURL,
            destinationURL: destURL,
            boundary: "BOUND-STREAM",
            filename: "doc.txt",
            mimeType: "text/plain"
        )

        let writtenData = try Data(contentsOf: destURL)
        let writtenText = String(decoding: writtenData, as: UTF8.self)
        XCTAssertTrue(writtenText.contains("filename=\"doc.txt\""))
        XCTAssertTrue(writtenText.contains(testContent))
        XCTAssertTrue(writtenText.hasSuffix("\r\n--BOUND-STREAM--\r\n"))
    }

    // MARK: - Client Config Limit Parsing

    func testMaxFileSizeFromClientConfig() {
        let nestedJson = """
            {
                "FileSettings": {
                    "MaxFileSize": 52428800
                }
            }
            """.data(using: .utf8)!
        XCTAssertEqual(FileTransfer.maxFileSize(fromClientConfig: nestedJson), 52_428_800)

        let flatJson = """
            {
                "MaxFileSize": 10485760
            }
            """.data(using: .utf8)!
        XCTAssertEqual(FileTransfer.maxFileSize(fromClientConfig: flatJson), 10_485_760)

        let zeroJson = """
            {
                "MaxFileSize": 0
            }
            """.data(using: .utf8)!
        XCTAssertEqual(FileTransfer.maxFileSize(fromClientConfig: zeroJson), 0)

        let invalidJson = "not json".data(using: .utf8)!
        XCTAssertNil(FileTransfer.maxFileSize(fromClientConfig: invalidJson))
    }

    // MARK: - FileId Decoding

    func testFileIdFromUploadResponse() throws {
        let json = """
            {
                "file_infos": [
                    { "id": "file_abc123" }
                ]
            }
            """.data(using: .utf8)!
        let fileId = try FileTransfer.fileId(fromUploadResponse: json)
        XCTAssertEqual(fileId, "file_abc123")
    }

    func testFileIdThrowsOnEmptyList() {
        let json = """
            {
                "file_infos": []
            }
            """.data(using: .utf8)!
        XCTAssertThrowsError(try FileTransfer.fileId(fromUploadResponse: json))
    }
}
