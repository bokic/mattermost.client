//
//  AttachmentUploadTests.swift
//  mattermost.clientTests
//

import XCTest

#if canImport(mattermost_client)
    @testable import mattermost_client
#endif

@MainActor
final class AttachmentUploadTests: XCTestCase {

    func testResolvedLimitFallsBackWhenServerValueIsMissing() {
        XCTAssertEqual(
            AttachmentUploadPolicy.resolvedLimit(serverValue: nil),
            AttachmentUploadPolicy.fallbackLimitBytes
        )
    }

    func testResolvedLimitUsesServerValueAndTreatsZeroAsUnlimited() {
        XCTAssertEqual(AttachmentUploadPolicy.resolvedLimit(serverValue: 12_345), 12_345)
        XCTAssertEqual(AttachmentUploadPolicy.resolvedLimit(serverValue: 0), Int64.max)
        XCTAssertEqual(AttachmentUploadPolicy.resolvedLimit(serverValue: -1), Int64.max)
    }

    func testExceedsLimitIgnoresUnlimitedValue() {
        XCTAssertFalse(AttachmentUploadPolicy.exceedsLimit(size: 10_000, limit: Int64.max))
        XCTAssertFalse(AttachmentUploadPolicy.exceedsLimit(size: 100, limit: 100))
        XCTAssertTrue(AttachmentUploadPolicy.exceedsLimit(size: 101, limit: 100))
    }

    func testProgressIsClamped() {
        XCTAssertEqual(AttachmentUploadPolicy.progress(sent: 0, total: 0), 0)
        XCTAssertEqual(AttachmentUploadPolicy.progress(sent: 50, total: 100), 0.5)
        XCTAssertEqual(AttachmentUploadPolicy.progress(sent: 150, total: 100), 1)
        XCTAssertEqual(AttachmentUploadPolicy.progress(sent: -10, total: 100), 0)
    }

    func testMaxFileSizeReadsOldClientConfigShape() throws {
        let data = Data(
            """
            {"FileSettings":{"MaxFileSize":1234567,"EnableFileAttachments":true}}
            """.utf8
        )
        XCTAssertEqual(WebService.maxFileSize(fromClientConfig: data), 1_234_567)
    }

    func testMaxFileSizeReadsTopLevelShapeAndZero() throws {
        XCTAssertEqual(
            WebService.maxFileSize(fromClientConfig: Data(#"{"MaxFileSize":0}"#.utf8)),
            0
        )
        XCTAssertNil(WebService.maxFileSize(fromClientConfig: Data("not json".utf8)))
    }

    func testMultipartHeaderSanitizesFilenameAndMimeType() {
        let header = WebService.multipartHeader(
            boundary: "Boundary-test",
            filename: "../../evil\r\nX-Injected: yes\".png",
            mimeType: "image/png\r\nX-Injected: yes"
        )
        let text = String(decoding: header, as: UTF8.self)
        XCTAssertTrue(text.contains("filename=\"evil__X-Injected: yes_.png\""))
        XCTAssertFalse(text.contains("\r\nX-Injected: yes"))
        XCTAssertTrue(text.contains("Content-Type: image/png  X-Injected: yes"))
    }

    func testWriteMultipartFileStreamsSourceWithoutCorruptingIt() throws {
        let directory = FileManager.default.temporaryDirectory
            .appendingPathComponent("attachment-upload-tests-\(UUID().uuidString)")
        try FileManager.default.createDirectory(at: directory, withIntermediateDirectories: true)
        defer { try? FileManager.default.removeItem(at: directory) }

        let source = directory.appendingPathComponent("payload.bin")
        let sourceData = Data(repeating: 0x5A, count: 2 * 1024 * 1024 + 17)
        try sourceData.write(to: source)
        let destination = directory.appendingPathComponent("multipart.bin")

        try WebService.writeMultipartFile(
            sourceURL: source,
            destinationURL: destination,
            boundary: "Boundary-stream",
            filename: "payload.bin",
            mimeType: "application/octet-stream"
        )

        let body = try Data(contentsOf: destination)
        let header = WebService.multipartHeader(
            boundary: "Boundary-stream",
            filename: "payload.bin",
            mimeType: "application/octet-stream"
        )
        let footer = WebService.multipartFooter(boundary: "Boundary-stream")
        XCTAssertTrue(body.starts(with: header))
        XCTAssertEqual(Data(body.suffix(footer.count)), footer)
        XCTAssertEqual(body.count, header.count + sourceData.count + footer.count)
        let payload = body.dropFirst(header.count).dropLast(footer.count)
        XCTAssertEqual(Data(payload), sourceData)
    }

    func testUploadRejectsOversizedFileBeforeNetworkRequest() async throws {
        let directory = FileManager.default.temporaryDirectory
            .appendingPathComponent("attachment-limit-tests-\(UUID().uuidString)")
        try FileManager.default.createDirectory(at: directory, withIntermediateDirectories: true)
        defer { try? FileManager.default.removeItem(at: directory) }
        let source = directory.appendingPathComponent("large.bin")
        try Data(repeating: 0x01, count: 1024).write(to: source)

        let ws = WebService(host: "chat.example.com", port: 8065)
        do {
            _ = try await ws.uploadFile(
                channelId: "channel",
                fileURL: source,
                filename: "large.bin",
                mimeType: "application/octet-stream",
                maxBytes: 100
            )
            XCTFail("Expected the upload to be rejected")
        } catch let error as WebServiceError {
            guard case .fileTooLarge(let size, let limit) = error else {
                return XCTFail("Unexpected error: \(error)")
            }
            XCTAssertEqual(size, 1024)
            XCTAssertEqual(limit, 100)
        }
    }
}
