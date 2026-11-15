//
//  WebServiceErrorTests.swift
//  mattermost.clientTests
//

import XCTest

#if canImport(mattermost_client)
    @testable import mattermost_client
#endif

final class WebServiceErrorTests: XCTestCase {

    func testHTTPStatusIncludesServerMessage() {
        let error = WebServiceError.httpStatus(code: 403, message: "Not enough permissions")
        XCTAssertEqual(error.errorDescription, "Not enough permissions (HTTP 403)")
    }

    func testHTTPStatusWithoutMessageUsesCode() {
        let error = WebServiceError.httpStatus(code: 500, message: nil)
        XCTAssertEqual(error.errorDescription, "Invalid status code: 500")
    }

    func testInvalidMimeTypeDescription() {
        XCTAssertEqual(
            WebServiceError.invalidMimeType("text/plain").errorDescription,
            "Invalid MIME type: text/plain."
        )
        XCTAssertEqual(
            WebServiceError.invalidMimeType(nil).errorDescription,
            "Invalid MIME type: unknown."
        )
    }

    func testSimpleDescriptions() {
        XCTAssertEqual(WebServiceError.invalidHostname.errorDescription, "Invalid hostname.")
        XCTAssertEqual(WebServiceError.invalidRequestBody.errorDescription, "Failed to serialize request body.")
        XCTAssertEqual(WebServiceError.invalidResponse.errorDescription, "No valid HTTP response received.")
    }

    func testWrappedErrorsKeepDescription() {
        let decoding = WebServiceError.decodingError(
            NSError(domain: "test", code: 1, userInfo: [NSLocalizedDescriptionKey: "bad json"]))
        XCTAssertEqual(decoding.errorDescription, "Failed to decode server response: bad json")

        let network = WebServiceError.networkError(
            NSError(domain: "test", code: 2, userInfo: [NSLocalizedDescriptionKey: "offline"]))
        XCTAssertEqual(network.errorDescription, "Network error: offline")
    }
}
