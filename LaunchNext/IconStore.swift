import Foundation
import AppKit

final class IconStore {
    static let shared = IconStore()

    private let cache = NSCache<NSString, NSImage>()

    private init() {
        cache.countLimit = 200
    }

    func icon(for app: AppInfo) -> NSImage {
        if PerformanceMode.current == .full {
            return app.icon
        }
        return icon(forPath: app.url.path)
    }

    func icon(forPath path: String) -> NSImage {
        let key = path as NSString
        if let cached = cache.object(forKey: key) {
            return cached
        }
        let icon = NSWorkspace.shared.icon(forFile: path)
        cache.setObject(icon, forKey: key)
        return icon
    }

    func clear() {
        cache.removeAllObjects()
    }
}

final class FolderPreviewCache {
    static let shared = FolderPreviewCache()

    private let cache = NSCache<NSString, NSImage>()

    private init() {
        cache.countLimit = 120
    }

    func image(forKey key: String) -> NSImage? {
        cache.object(forKey: key as NSString)
    }

    func store(_ image: NSImage, forKey key: String) {
        cache.setObject(image, forKey: key as NSString)
    }

    func clear() {
        cache.removeAllObjects()
    }
}
