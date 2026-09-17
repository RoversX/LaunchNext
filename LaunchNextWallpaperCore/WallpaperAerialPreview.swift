import Foundation

/// Resolves downloaded resources only; never downloads or captures the desktop.
public enum WallpaperAerialPreview {
    public static func localResource(
        assetID: String, isDark: Bool, isPortrait: Bool,
        homeDirectory: URL = FileManager.default.homeDirectoryForCurrentUser,
        systemResources: URL = URL(fileURLWithPath: "/System/Library/ExtensionKit/Extensions/WallpaperAerialsExtension.appex/Contents/Resources"),
        legacyDirectory: URL = URL(fileURLWithPath: "/Library/Application Support/com.apple.idleassetsd/Customer")
    ) -> URL? {
        guard isSafeIdentifier(assetID) else { return nil }
        let aerials = homeDirectory.appendingPathComponent("Library/Application Support/com.apple.wallpaper/aerials")
        func readable(_ url: URL) -> URL? {
            FileManager.default.isReadableFile(atPath: url.path) ? url : nil
        }
        func video(_ id: String) -> URL? {
            if let url = readable(aerials.appendingPathComponent("videos/\(id).mov")) { return url }
            for format in ["4KSDR240FPS", "4KSDR", "4KHDR", "2KSDR", "2KHDR", "2KAVC"] {
                if let url = readable(legacyDirectory.appendingPathComponent("\(format)/\(id).mov")) { return url }
            }
            return nil
        }
        if let url = video(assetID) { return url }

        for manifest in [aerials.appendingPathComponent("manifest/entries.json"),
                         systemResources.appendingPathComponent("entries.json")] {
            guard let data = try? Data(contentsOf: manifest),
                  let catalog = try? JSONSerialization.jsonObject(with: data) as? [String: Any],
                  let assets = catalog["assets"] as? [[String: Any]] else { continue }
            // Dynamic aerial choices may contain a family ID, not a video ID.
            // The family's gallery thumbnail combines light and dark images;
            // only use the matching individual asset, never that composite.
            let matches = assets.filter { asset in
                if asset["id"] as? String == assetID { return true }
                guard (asset["subcategories"] as? [String])?.contains(assetID) == true,
                      let variant = asset["variant"] as? [String: Any] else { return false }
                return variant["appearance"] as? String == (isDark ? "dark" : "light")
                    && variant["orientation"] as? String == (isPortrait ? "portrait" : "landscape")
            }
            guard matches.count == 1, let id = matches.first?["id"] as? String,
                  isSafeIdentifier(id) else { continue }
            if let url = video(id) { return url }
            for root in [aerials.appendingPathComponent("thumbnails"), systemResources] {
                if let url = readable(root.appendingPathComponent("\(id).png")) { return url }
            }
        }
        return nil
    }

    private static func isSafeIdentifier(_ value: String) -> Bool {
        !value.isEmpty && value.utf8.allSatisfy {
            (48...57).contains($0) || (65...90).contains($0) || (97...122).contains($0) || $0 == 45 || $0 == 95
        }
    }
}
