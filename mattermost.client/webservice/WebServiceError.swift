//
//  WebServiceError.swift
//  mattermost.client
//

import Foundation

enum WebServiceError: LocalizedError {
    case invalidHostname
    case invalidRequestBody
    case invalidResponse
    case invalidMimeType(String?)
    case httpStatus(code: Int, message: String?)
    case decodingError(Error)
    case networkError(Error)
    case fileTooLarge(size: Int64, limit: Int64)
    case fileReadError(Error)

    var errorDescription: String? {
        switch self {
        case .invalidHostname:
            return "Invalid hostname."
        case .invalidRequestBody:
            return "Failed to serialize request body."
        case .invalidResponse:
            return "No valid HTTP response received."
        case .invalidMimeType(let mime):
            return "Invalid MIME type: \(mime ?? "unknown")."
        case .httpStatus(let code, let message):
            if let message = message, !message.isEmpty {
                return "\(message) (HTTP \(code))"
            }
            return "Invalid status code: \(code)"
        case .decodingError(let error):
            return "Failed to decode server response: \(error.localizedDescription)"
        case .networkError(let error):
            return "Network error: \(error.localizedDescription)"
        case .fileTooLarge(let size, let limit):
            return
                "\(AttachmentUploadPolicy.formattedBytes(size)) exceeds the \(AttachmentUploadPolicy.formattedBytes(limit)) limit."
        case .fileReadError(let error):
            return "Could not read the file: \(error.localizedDescription)"
        }
    }
}
