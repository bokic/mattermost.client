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
}
