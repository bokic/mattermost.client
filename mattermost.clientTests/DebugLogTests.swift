//
//  DebugLogTests.swift
//  mattermost.clientTests
//

import XCTest

#if canImport(mattermost_client)
    @testable import mattermost_client
#endif

@MainActor
final class DebugLogTests: XCTestCase {

    func testSensitiveLoggingIsGated() throws {
        let path = DebugLog.logPath
        try? FileManager.default.removeItem(atPath: path)

        DebugLog.isSensitiveLoggingEnabled = false
        DebugLog.logSensitive("PAYLOAD_SECRET_MARKER")
        let disabledContents = (try? String(contentsOfFile: path, encoding: .utf8)) ?? ""
        XCTAssertFalse(disabledContents.contains("PAYLOAD_SECRET_MARKER"))

        DebugLog.isSensitiveLoggingEnabled = true
        DebugLog.logSensitive("PAYLOAD_SECRET_MARKER")
        let enabledContents = (try? String(contentsOfFile: path, encoding: .utf8)) ?? ""
        XCTAssertTrue(enabledContents.contains("PAYLOAD_SECRET_MARKER"))
    }

    func testLevelFilteringForReleasePersistence() {
        XCTAssertFalse(DebugLog.shouldWriteToFile(.debug, verbose: false))
        XCTAssertFalse(DebugLog.shouldWriteToFile(.info, verbose: false))
        XCTAssertTrue(DebugLog.shouldWriteToFile(.warning, verbose: false))
        XCTAssertTrue(DebugLog.shouldWriteToFile(.error, verbose: false))

        XCTAssertTrue(DebugLog.shouldWriteToFile(.debug, verbose: true))
        XCTAssertTrue(DebugLog.shouldWriteToFile(.info, verbose: true))
    }

    func testErrorLevelIncludesLabel() throws {
        let path = DebugLog.logPath
        try? FileManager.default.removeItem(atPath: path)

        DebugLog.error("ERROR_MARKER")
        let contents = (try? String(contentsOfFile: path, encoding: .utf8)) ?? ""
        XCTAssertTrue(contents.contains("[ERROR]"))
        XCTAssertTrue(contents.contains("ERROR_MARKER"))
    }

    func testLogRotationKeepsOneArchive() throws {
        let path = DebugLog.logPath
        let archive = DebugLog.logArchivePath
        let manager = FileManager.default
        try? manager.removeItem(atPath: path)
        try? manager.removeItem(atPath: archive)

        DebugLog.log(String(repeating: "x", count: 1_000_050))
        DebugLog.log("trigger rotation")

        XCTAssertTrue(manager.fileExists(atPath: archive))
        let archived = (try? String(contentsOfFile: archive, encoding: .utf8)) ?? ""
        XCTAssertTrue(archived.contains("trigger rotation") == false)
        XCTAssertFalse(manager.fileExists(atPath: archive + ".2"))

        try? manager.removeItem(atPath: path)
        try? manager.removeItem(atPath: archive)
    }
}
