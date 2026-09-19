import Foundation

/// Temporary, always-on diagnostics for the local wallpaper investigation.
/// Callers pass only event names, counters and booleans, never paths or image data.
@MainActor
enum WallpaperDiagnostics {
    private static let session = String(UUID().uuidString.prefix(8))
    private static var sequence = 0
    private static let queue = DispatchQueue(label: "com.roversx.launchnext.wallpaper-diagnostics", qos: .utility)
    private static let directory = FileManager.default.homeDirectoryForCurrentUser
        .appendingPathComponent("Library/Logs/LaunchNext", isDirectory: true)

    static func record(_ event: String) {
        sequence += 1
        let line = "\(Date().timeIntervalSince1970) session=\(session) seq=\(sequence) \(event)\n"
        let directory = directory
        queue.async { append(line, directory: directory) }
    }

    nonisolated private static func append(_ line: String, directory: URL) {
        let manager = FileManager.default
        let current = directory.appendingPathComponent("wallpaper-diagnostics.log")
        let previous = directory.appendingPathComponent("wallpaper-diagnostics.previous.log")
        do {
            try manager.createDirectory(at: directory, withIntermediateDirectories: true)
            let size = (try? manager.attributesOfItem(atPath: current.path)[.size] as? NSNumber)?.intValue ?? 0
            // Keep at most two ~512 KB files; no unbounded in-memory log buffer.
            if size >= 512 * 1024 {
                if manager.fileExists(atPath: previous.path) { try manager.removeItem(at: previous) }
                try manager.moveItem(at: current, to: previous)
            }
            if !manager.fileExists(atPath: current.path) {
                manager.createFile(atPath: current.path, contents: nil, attributes: [.posixPermissions: 0o600])
            }
            let handle = try FileHandle(forWritingTo: current)
            defer { try? handle.close() }
            try handle.seekToEnd()
            try handle.write(contentsOf: Data(line.utf8))
        } catch {
            // Diagnostics must never interrupt wallpaper loading.
        }
    }
}
