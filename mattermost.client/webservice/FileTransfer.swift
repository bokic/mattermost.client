//
//  FileTransfer.swift
//  mattermost.client
//

import Foundation

/// Bridges `URLSession` upload progress callbacks onto a small sendable closure.
final class UploadProgressObserver: NSObject, URLSessionTaskDelegate, @unchecked Sendable {
    private let onProgress: @Sendable (Int64, Int64) -> Void

    init(onProgress: @escaping @Sendable (Int64, Int64) -> Void) {
        self.onProgress = onProgress
    }

    func urlSession(
        _ session: URLSession,
        task: URLSessionTask,
        didSendBodyData bytesSent: Int64,
        totalBytesSent: Int64,
        totalBytesExpectedToSend: Int64
    ) {
        onProgress(totalBytesSent, totalBytesExpectedToSend)
    }
}

@MainActor
protocol FileTransferProtocol: AnyObject {
    func uploadFile(channelId: String, data: Data, filename: String, mimeType: String) async throws -> String
    func uploadFile(
        channelId: String,
        fileURL: URL,
        filename: String,
        mimeType: String,
        maxBytes: Int64?,
        progress: (@Sendable (Double) -> Void)?
    ) async throws -> String
    func fetchFileData(fileId: String, preview: Bool) async throws -> Data
    func fetchMaxFileSize() async -> Int64?
    func searchChannelFiles(teamId: String, channelId: String, page: Int, perPage: Int) async throws -> [MMFileInfo]
    func searchTeamFiles(teamId: String, terms: String, page: Int, perPage: Int) async throws -> [MMFileInfo]
}

extension FileTransferProtocol {
    func uploadFile(
        channelId: String,
        fileURL: URL,
        filename: String,
        mimeType: String,
        maxBytes: Int64? = nil,
        progress: (@Sendable (Double) -> Void)? = nil
    ) async throws -> String {
        try await uploadFile(
            channelId: channelId,
            fileURL: fileURL,
            filename: filename,
            mimeType: mimeType,
            maxBytes: maxBytes,
            progress: progress
        )
    }

    func fetchFileData(fileId: String) async throws -> Data {
        try await fetchFileData(fileId: fileId, preview: false)
    }

    func searchChannelFiles(teamId: String, channelId: String, page: Int = 0, perPage: Int = 60) async throws
        -> [MMFileInfo]
    {
        try await searchChannelFiles(teamId: teamId, channelId: channelId, page: page, perPage: perPage)
    }

    func searchTeamFiles(teamId: String, terms: String, page: Int = 0, perPage: Int = 60) async throws -> [MMFileInfo] {
        try await searchTeamFiles(teamId: teamId, terms: terms, page: page, perPage: perPage)
    }
}

@MainActor
class FileTransfer: FileTransferProtocol {
    private let apiClient: APIClientProtocol

    init(apiClient: APIClientProtocol) {
        self.apiClient = apiClient
    }

    static func sanitizedMultipartFilename(_ filename: String) -> String {
        (filename as NSString).lastPathComponent
            .components(separatedBy: CharacterSet(charactersIn: "\r\n\"\\"))
            .joined(separator: "_")
    }

    static func sanitizedMultipartMimeType(_ mimeType: String) -> String {
        mimeType
            .components(separatedBy: CharacterSet(charactersIn: "\r\n"))
            .joined(separator: " ")
    }

    static func multipartHeader(boundary: String, filename: String, mimeType: String) -> Data {
        let safeFilename = sanitizedMultipartFilename(filename)
        let safeMimeType = sanitizedMultipartMimeType(mimeType)
        var header = Data()
        func append(_ text: String) { header.append(Data(text.utf8)) }
        append("--\(boundary)\r\n")
        append("Content-Disposition: form-data; name=\"files\"; filename=\"\(safeFilename)\"\r\n")
        append("Content-Type: \(safeMimeType)\r\n\r\n")
        return header
    }

    static func multipartFooter(boundary: String) -> Data {
        Data("\r\n--\(boundary)--\r\n".utf8)
    }

    static func multipartBody(
        boundary: String,
        filename: String,
        mimeType: String,
        data: Data
    ) -> Data {
        var body = multipartHeader(boundary: boundary, filename: filename, mimeType: mimeType)
        body.append(data)
        body.append(multipartFooter(boundary: boundary))
        return body
    }

    /// Streams a file into a temporary multipart body so uploads do not have to
    /// hold the whole attachment in memory. The caller owns `destinationURL`.
    static func writeMultipartFile(
        sourceURL: URL,
        destinationURL: URL,
        boundary: String,
        filename: String,
        mimeType: String
    ) throws {
        let manager = FileManager.default
        guard manager.createFile(atPath: destinationURL.path, contents: nil) else {
            throw WebServiceError.fileReadError(
                CocoaError(.fileWriteUnknown, userInfo: [NSFilePathErrorKey: destinationURL.path])
            )
        }
        let output = try FileHandle(forWritingTo: destinationURL)
        defer { try? output.close() }
        try output.write(
            contentsOf: multipartHeader(boundary: boundary, filename: filename, mimeType: mimeType)
        )

        let input = try FileHandle(forReadingFrom: sourceURL)
        defer { try? input.close() }
        while let chunk = try input.read(upToCount: AttachmentUploadPolicy.chunkSize), !chunk.isEmpty {
            try output.write(contentsOf: chunk)
        }
        try output.write(contentsOf: multipartFooter(boundary: boundary))
    }

    /// Reads the server-configured attachment limit from `/config/client`.
    /// Mattermost exposes it as `FileSettings.MaxFileSize` in the old config format.
    static func maxFileSize(fromClientConfig data: Data) -> Int64? {
        guard let json = try? JSONSerialization.jsonObject(with: data) as? [String: Any] else {
            return nil
        }
        let candidates: [Any?] = [
            (json["FileSettings"] as? [String: Any])?["MaxFileSize"],
            json["MaxFileSize"],
        ]
        for candidate in candidates {
            if let number = candidate as? NSNumber {
                let value = number.int64Value
                return value == 0 ? 0 : max(0, value)
            }
        }
        return nil
    }

    static func fileId(fromUploadResponse data: Data) throws -> String {
        struct UploadResponse: Decodable {
            struct FileInfo: Decodable { let id: String }
            let file_infos: [FileInfo]
        }
        let decoded: UploadResponse
        do {
            decoded = try JSONDecoder().decode(UploadResponse.self, from: data)
        } catch {
            throw WebServiceError.decodingError(error)
        }
        guard let fileId = decoded.file_infos.first?.id else {
            throw WebServiceError.invalidResponse
        }
        return fileId
    }

    /// Fetches the server's attachment size limit. Returns `nil` when the
    /// endpoint is unavailable so callers can fall back to the default limit.
    func fetchMaxFileSize() async -> Int64? {
        guard
            let (data, _) = try? await apiClient.performRequest(
                path: "/api/v4/config/client",
                method: "GET",
                queryItems: [URLQueryItem(name: "format", value: "old")],
                jsonBody: nil,
                rawBody: nil,
                auth: .optionalToken,
                accept: "application/json",
                contentType: nil,
                acceptableStatus: 200...299,
                requireJSONMime: false,
                logPayload: false
            )
        else { return nil }
        return Self.maxFileSize(fromClientConfig: data)
    }

    func uploadFile(channelId: String, data: Data, filename: String, mimeType: String) async throws -> String {
        let boundary = "Boundary-\(UUID().uuidString)"
        let body = Self.multipartBody(
            boundary: boundary,
            filename: filename,
            mimeType: mimeType,
            data: data
        )
        let (responseData, _) = try await apiClient.performRequest(
            path: "/api/v4/files",
            method: "POST",
            queryItems: [URLQueryItem(name: "channel_id", value: channelId)],
            jsonBody: nil,
            rawBody: body,
            auth: .requiredToken,
            accept: "application/json",
            contentType: "multipart/form-data; boundary=\(boundary)",
            acceptableStatus: 200...299,
            requireJSONMime: false,
            logPayload: true
        )
        return try Self.fileId(fromUploadResponse: responseData)
    }

    /// Streams a file from disk as a multipart upload and reports progress.
    /// The file is copied to a temporary multipart body so a large attachment
    /// never has to be held in memory.
    func uploadFile(
        channelId: String,
        fileURL: URL,
        filename: String,
        mimeType: String,
        maxBytes: Int64? = nil,
        progress: (@Sendable (Double) -> Void)? = nil
    ) async throws -> String {
        let size =
            (try? fileURL.resourceValues(forKeys: [.fileSizeKey]))?.fileSize.map(Int64.init)
            ?? 0
        if let maxBytes = maxBytes, AttachmentUploadPolicy.exceedsLimit(size: size, limit: maxBytes) {
            throw WebServiceError.fileTooLarge(size: size, limit: maxBytes)
        }

        let boundary = "Boundary-\(UUID().uuidString)"
        let multipartURL = FileManager.default.temporaryDirectory
            .appendingPathComponent("mattermost-upload-\(UUID().uuidString)")
        defer { try? FileManager.default.removeItem(at: multipartURL) }
        do {
            try Self.writeMultipartFile(
                sourceURL: fileURL,
                destinationURL: multipartURL,
                boundary: boundary,
                filename: filename,
                mimeType: mimeType
            )
        } catch let error as WebServiceError {
            throw error
        } catch {
            throw WebServiceError.fileReadError(error)
        }

        let request = try apiClient.makeRequest(
            path: "/api/v4/files",
            method: "POST",
            queryItems: [URLQueryItem(name: "channel_id", value: channelId)],
            jsonBody: nil,
            rawBody: nil,
            auth: .requiredToken,
            accept: "application/json",
            contentType: "multipart/form-data; boundary=\(boundary)"
        )

        let observer = UploadProgressObserver { sent, total in
            guard total > 0 else { return }
            progress?(AttachmentUploadPolicy.progress(sent: sent, total: total))
        }
        let configuration = URLSessionConfiguration.ephemeral
        let session = URLSession(configuration: configuration, delegate: observer, delegateQueue: nil)
        defer { session.finishTasksAndInvalidate() }

        let data: Data
        let response: URLResponse
        do {
            (data, response) = try await session.upload(for: request, fromFile: multipartURL)
        } catch is CancellationError {
            throw CancellationError()
        } catch let error as URLError where error.code == .cancelled {
            throw CancellationError()
        } catch {
            throw WebServiceError.networkError(error)
        }

        guard let httpResponse = response as? HTTPURLResponse else {
            throw WebServiceError.invalidResponse
        }
        guard (200...299).contains(httpResponse.statusCode) else {
            var serverMsg: String?
            if let json = try? JSONSerialization.jsonObject(with: data) as? [String: Any],
                let msg = json["message"] as? String, !msg.isEmpty
            {
                serverMsg = msg
            }
            throw WebServiceError.httpStatus(code: httpResponse.statusCode, message: serverMsg)
        }
        progress?(1)
        return try Self.fileId(fromUploadResponse: data)
    }

    func fetchFileData(fileId: String, preview: Bool = false) async throws -> Data {
        let path = preview ? "/api/v4/files/\(fileId)/preview" : "/api/v4/files/\(fileId)"
        let (data, _) = try await apiClient.performRequest(
            path: path,
            method: "GET",
            queryItems: nil,
            jsonBody: nil,
            rawBody: nil,
            auth: .requiredToken,
            accept: nil,
            contentType: nil,
            acceptableStatus: 200...299,
            requireJSONMime: false,
            logPayload: false
        )
        return data
    }

    /// Recent files in a channel, using the same search the web RHS uses.
    func searchChannelFiles(teamId: String, channelId: String, page: Int = 0, perPage: Int = 60) async throws
        -> [MMFileInfo]
    {
        let result: MMFileSearchResult = try await apiClient.performAuthenticatedRequest(
            path: "/api/v4/teams/\(teamId)/files/search",
            method: "POST",
            queryItems: nil,
            body: [
                "terms": "channel:\(channelId)",
                "is_or_search": false,
                "page": page,
                "per_page": perPage,
                "time_zone_offset": 0,
            ]
        )
        return result.order.compactMap { result.file_infos[$0] }
    }

    /// Searches files across the whole team (the global Search → Files tab).
    func searchTeamFiles(teamId: String, terms: String, page: Int = 0, perPage: Int = 60) async throws -> [MMFileInfo] {
        let result: MMFileSearchResult = try await apiClient.performAuthenticatedRequest(
            path: "/api/v4/teams/\(teamId)/files/search",
            method: "POST",
            queryItems: nil,
            body: [
                "terms": terms,
                "is_or_search": false,
                "page": page,
                "per_page": perPage,
                "time_zone_offset": 0,
            ]
        )
        return result.order.compactMap { result.file_infos[$0] }
    }
}
