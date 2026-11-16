//
//  DebugLog.swift
//  mattermost.client
//

import Foundation
import os

enum DebugLogLevel: Int, Comparable {
    case debug = 0
    case info
    case warning
    case error

    static func < (lhs: DebugLogLevel, rhs: DebugLogLevel) -> Bool {
        lhs.rawValue < rhs.rawValue
    }

    var label: String {
        switch self {
        case .debug: return "DEBUG"
        case .info: return "INFO"
        case .warning: return "WARN"
        case .error: return "ERROR"
        }
    }
}

enum DebugLog {
    static var logPath: String {
        (NSTemporaryDirectory() as NSString).appendingPathComponent("mattermost_debug.log")
    }

    static var logArchivePath: String { logPath + ".1" }

    /// Verbose file/stdout logging ships only in Debug builds or when explicitly
    /// requested with `--debug-log` / the `debugFileLogging` default. Release
    /// builds still emit warnings and errors through `Logger`.
    static let isVerboseLoggingEnabled: Bool = {
        #if DEBUG
            return true
        #else
            return CommandLine.arguments.contains("--debug-log")
                || UserDefaults.standard.bool(forKey: "debugFileLogging")
        #endif
    }()

    /// Raw payload logging is off unless explicitly requested at launch
    /// (`--debug-ws`) or via the `debugWebSocketLogging` default.
    /// The flag is mutable for tests, so guard it with a lock instead of leaving
    /// nonisolated shared mutable state behind.
    private static let sensitiveLoggingState = OSAllocatedUnfairLock(
        initialState:
            CommandLine.arguments.contains("--debug-ws")
            || UserDefaults.standard.bool(forKey: "debugWebSocketLogging")
    )

    static var isSensitiveLoggingEnabled: Bool {
        get { sensitiveLoggingState.withLock { $0 } }
        set { sensitiveLoggingState.withLock { $0 = newValue } }
    }

    private static let logger = Logger(
        subsystem: Bundle.main.bundleIdentifier ?? "mattermost.client", category: "App")
    private static let fileLock = NSLock()
    private static let maxLogBytes = 1_000_000

    /// Logs only when sensitive/frame logging is enabled.
    static func logSensitive(_ message: @autoclosure () -> String) {
        guard isSensitiveLoggingEnabled else { return }
        log(.debug, message())
    }

    static func log(_ message: @autoclosure () -> String) {
        log(.debug, message())
    }

    static func info(_ message: @autoclosure () -> String) {
        log(.info, message())
    }

    static func warning(_ message: @autoclosure () -> String) {
        log(.warning, message())
    }

    static func error(_ message: @autoclosure () -> String) {
        log(.error, message())
    }

    static func log(_ level: DebugLogLevel, _ message: String) {
        switch level {
        case .debug: logger.debug("\(message, privacy: .private)")
        case .info: logger.info("\(message, privacy: .private)")
        case .warning: logger.warning("\(message, privacy: .private)")
        case .error: logger.error("\(message, privacy: .private)")
        }

        guard shouldWriteToFile(level, verbose: isVerboseLoggingEnabled) else { return }

        let timestamp = ISO8601DateFormatter().string(from: Date())
        let line = "[\(timestamp)] [\(level.label)] \(message)\n"

        print("[STATUS_LOG] \(line)", terminator: "")
        fflush(stdout)
        NSLog("[STATUS_LOG] %@", "[\(level.label)] \(message)")

        guard let data = line.data(using: .utf8) else { return }
        fileLock.lock()
        defer { fileLock.unlock() }
        rotateIfNeeded()
        if let fileHandle = FileHandle(forWritingAtPath: logPath) {
            fileHandle.seekToEndOfFile()
            fileHandle.write(data)
            try? fileHandle.close()
        } else {
            try? data.write(to: URL(fileURLWithPath: logPath), options: .atomic)
        }
    }

    /// Release builds persist warnings/errors; verbose levels need an explicit opt-in.
    static func shouldWriteToFile(_ level: DebugLogLevel, verbose: Bool) -> Bool {
        verbose || level >= .warning
    }

    private static func rotateIfNeeded() {
        let manager = FileManager.default
        guard let attributes = try? manager.attributesOfItem(atPath: logPath),
            let size = attributes[.size] as? NSNumber,
            size.intValue > maxLogBytes
        else { return }

        try? manager.removeItem(atPath: logArchivePath)
        try? manager.moveItem(atPath: logPath, toPath: logArchivePath)
    }
}
