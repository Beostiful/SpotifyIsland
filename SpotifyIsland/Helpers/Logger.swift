import Foundation
import os

/// Logs to both os_log and a file for reliable diagnostics.
enum AppLog {
    private static let logger = Logger(subsystem: "com.spotifyisland", category: "app")
    private static let logFile: URL = {
        let dir = FileManager.default.homeDirectoryForCurrentUser
            .appendingPathComponent(".config/spotifyisland")
        try? FileManager.default.createDirectory(at: dir, withIntermediateDirectories: true)
        return dir.appendingPathComponent("debug.log")
    }()

    static func info(_ message: String) {
        logger.info("\(message, privacy: .public)")
        writeToFile("[INFO] \(message)")
    }

    static func error(_ message: String) {
        logger.error("\(message, privacy: .public)")
        writeToFile("[ERROR] \(message)")
    }

    private static func writeToFile(_ message: String) {
        let timestamp = ISO8601DateFormatter().string(from: Date())
        let line = "\(timestamp) \(message)\n"
        if let data = line.data(using: .utf8) {
            if FileManager.default.fileExists(atPath: logFile.path) {
                if let handle = try? FileHandle(forWritingTo: logFile) {
                    handle.seekToEndOfFile()
                    handle.write(data)
                    handle.closeFile()
                }
            } else {
                try? data.write(to: logFile)
            }
        }
    }
}
