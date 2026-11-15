//
//  AttachmentUploads.swift
//  mattermost.client
//
//  Shared logic for composer attachment uploads: size limits, byte formatting
//  and progress calculation. Keeping this pure makes the upload UI testable.
//

import Foundation

enum AttachmentUploadPolicy {
    /// Mattermost's default Team Edition limit (50 MB). Used until the server's
    /// `/config/client` response provides its configured `FileSettings.MaxFileSize`.
    static let fallbackLimitBytes: Int64 = 50 * 1024 * 1024

    static let chunkSize = 1 * 1024 * 1024

    /// `MaxFileSize` values equal to or below zero mean "no server-side limit".
    static func resolvedLimit(serverValue: Int64?) -> Int64 {
        guard let serverValue = serverValue else { return fallbackLimitBytes }
        return serverValue > 0 ? serverValue : Int64.max
    }

    static func exceedsLimit(size: Int64, limit: Int64) -> Bool {
        limit != Int64.max && size > limit
    }

    static func progress(sent: Int64, total: Int64) -> Double {
        guard total > 0 else { return 0 }
        return min(1, max(0, Double(sent) / Double(total)))
    }

    static func formattedBytes(_ bytes: Int64) -> String {
        ByteCountFormatter.string(fromByteCount: bytes, countStyle: .file)
    }
}
