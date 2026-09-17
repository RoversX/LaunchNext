import Foundation
import LaunchNextWallpaperCore
import XCTest

final class WallpaperAerialPreviewTests: XCTestCase {
    private var root: URL!
    private var aerials: URL { root.appendingPathComponent("Library/Application Support/com.apple.wallpaper/aerials") }
    private var system: URL { root.appendingPathComponent("system") }
    private var legacy: URL { root.appendingPathComponent("legacy") }

    override func setUpWithError() throws {
        root = FileManager.default.temporaryDirectory.appendingPathComponent(UUID().uuidString)
        try FileManager.default.createDirectory(at: root, withIntermediateDirectories: true)
    }

    override func tearDownWithError() throws {
        try FileManager.default.removeItem(at: root)
    }

    func testFamilyResolvesAllAppearanceAndOrientationVariants() throws {
        var assets: [[String: Any]] = []
        for appearance in ["light", "dark"] {
            for orientation in ["landscape", "portrait"] {
                let id = "\(appearance)-\(orientation)"
                assets.append(["id": id, "subcategories": ["FAMILY"],
                               "variant": ["appearance": appearance, "orientation": orientation]])
                try write(aerials.appendingPathComponent("videos/\(id).mov"))
            }
        }
        try manifest(assets)
        for dark in [false, true] {
            for portrait in [false, true] {
                XCTAssertEqual(resolve("FAMILY", dark: dark, portrait: portrait)?.lastPathComponent,
                               "\(dark ? "dark" : "light")-\(portrait ? "portrait" : "landscape").mov")
            }
        }
    }

    func testFamilyCompositeIsNeverUsedWhenVariantIsMissing() throws {
        try write(aerials.appendingPathComponent("thumbnails/FAMILY.png"))
        try manifest([["id": "LIGHT", "subcategories": ["FAMILY"],
                       "variant": ["appearance": "light", "orientation": "landscape"]]])
        try write(aerials.appendingPathComponent("videos/LIGHT.mov"))
        XCTAssertNil(resolve("FAMILY", dark: true))
    }

    func testDirectDownloadedVideoDoesNotRequireCatalog() throws {
        let url = aerials.appendingPathComponent("videos/DIRECT.mov")
        try write(url)
        XCTAssertEqual(resolve("DIRECT"), url)
    }

    func testLegacyVideoAndSystemCatalogThumbnailFallback() throws {
        let video = legacy.appendingPathComponent("4KSDR/DIRECT.mov")
        try write(video)
        XCTAssertEqual(resolve("DIRECT"), video)
        try FileManager.default.removeItem(at: video)
        try manifest([["id": "DIRECT"]], at: system.appendingPathComponent("entries.json"))
        let thumbnail = system.appendingPathComponent("DIRECT.png")
        try write(thumbnail)
        XCTAssertEqual(resolve("DIRECT"), thumbnail)
    }

    func testRejectsTraversalAndDoesNotUseRemoteURLs() throws {
        try manifest([["id": "REMOTE", "url-4K-SDR-240FPS": "https://example.com/video.mov"]])
        XCTAssertNil(resolve("REMOTE"))
        XCTAssertNil(resolve("../escape"))
        XCTAssertNil(resolve("/absolute"))
    }

    private func resolve(_ id: String, dark: Bool = false, portrait: Bool = false) -> URL? {
        WallpaperAerialPreview.localResource(assetID: id, isDark: dark, isPortrait: portrait,
            homeDirectory: root, systemResources: system, legacyDirectory: legacy)
    }

    private func manifest(_ assets: [[String: Any]], at url: URL? = nil) throws {
        try write(url ?? aerials.appendingPathComponent("manifest/entries.json"),
                  data: JSONSerialization.data(withJSONObject: ["assets": assets]))
    }

    private func write(_ url: URL, data: Data = Data([0])) throws {
        try FileManager.default.createDirectory(at: url.deletingLastPathComponent(), withIntermediateDirectories: true)
        try data.write(to: url)
    }
}
