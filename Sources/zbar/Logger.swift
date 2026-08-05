import Foundation

/// Lightweight rolling logger. Appends timestamped lines to
/// `~/Library/Logs/zbar/zbar.log` and trims the file once it grows past a cap so
/// it never balloons. Safe to call from any thread.
enum Log {
    static let directory: URL = {
        let url = FileManager.default.homeDirectoryForCurrentUser
            .appendingPathComponent("Library/Logs/zbar", isDirectory: true)
        try? FileManager.default.createDirectory(at: url, withIntermediateDirectories: true)
        return url
    }()

    static let fileURL = directory.appendingPathComponent("zbar.log")

    private static let queue = DispatchQueue(label: "dev.talles.zbar.log")
    private static let maxBytes = 2_000_000
    private static let trimToBytes = 1_000_000

    private static let stampFormatter: DateFormatter = {
        let formatter = DateFormatter()
        formatter.dateFormat = "yyyy-MM-dd HH:mm:ss"
        return formatter
    }()

    static func info(_ message: String) { write("INFO", message) }
    static func error(_ message: String) { write("ERROR", message) }

    private static func write(_ level: String, _ message: String) {
        let line = "\(stampFormatter.string(from: Date())) [\(level)] \(message)\n"
        queue.async {
            append(Data(line.utf8))
            rollIfNeeded()
        }
    }

    private static func append(_ data: Data) {
        let fm = FileManager.default
        if !fm.fileExists(atPath: fileURL.path) {
            try? data.write(to: fileURL)
        } else if let handle = try? FileHandle(forWritingTo: fileURL) {
            defer { try? handle.close() }
            _ = try? handle.seekToEnd()
            try? handle.write(contentsOf: data)
        }
    }

    private static func rollIfNeeded() {
        guard
            let size = try? FileManager.default.attributesOfItem(atPath: fileURL.path)[.size] as? Int,
            size > maxBytes,
            let data = try? Data(contentsOf: fileURL)
        else { return }

        let tail = data.suffix(trimToBytes)
        // Drop the (likely partial) first line so the file starts clean.
        if let newline = tail.firstIndex(of: 0x0A) {
            try? Data(tail[tail.index(after: newline)...]).write(to: fileURL)
        } else {
            try? Data(tail).write(to: fileURL)
        }
    }
}
