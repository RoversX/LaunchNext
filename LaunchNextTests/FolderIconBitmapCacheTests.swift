import AppKit
import XCTest

// Compiles the production cache directly into this test target.
final class FolderIconBitmapCacheTests: XCTestCase {
    private func bitmap(_ side: Int = 16) -> CGImage {
        CGContext(data: nil, width: side, height: side, bitsPerComponent: 8, bytesPerRow: side * 4,
                  space: CGColorSpaceCreateDeviceRGB(), bitmapInfo: CGImageAlphaInfo.premultipliedLast.rawValue)!.makeImage()!
    }
    private func key(_ path: String, scale: CGFloat = 1, appearance: String = "light") -> FolderIconBitmapCache.Key {
        .init(path: path, side: 16, scale: scale, appearance: appearance)
    }

    func testReuseAndSeparateScaleAppearanceAndSource() {
        let cache = FolderIconBitmapCache(observesMemoryPressure: false)
        let source = NSImage(size: NSSize(width: 16, height: 16))
        let request = cache.request(for: key("app"))
        let image = bitmap()
        cache.insert(image, for: request, source: source)
        XCTAssertTrue(cache.image(for: request, source: source) === image)
        XCTAssertNil(cache.image(for: cache.request(for: key("app", scale: 2)), source: source))
        XCTAssertNil(cache.image(for: cache.request(for: key("app", appearance: "dark")), source: source))
        let changed = NSImage(size: source.size)
        XCTAssertNil(cache.image(for: request, source: changed))
    }

    func testStrictByteBudgetEvictsLeastRecentlyUsed() {
        let image = bitmap()
        let cost = image.bytesPerRow * image.height
        let cache = FolderIconBitmapCache(byteLimit: cost * 2, observesMemoryPressure: false)
        let source = NSImage(size: .zero)
        let a = cache.request(for: key("a")), b = cache.request(for: key("b")), c = cache.request(for: key("c"))
        cache.insert(image, for: a, source: source)
        cache.insert(image, for: b, source: source)
        XCTAssertNotNil(cache.image(for: a, source: source))
        cache.insert(image, for: c, source: source)
        XCTAssertNil(cache.image(for: b, source: source))
        XCTAssertNotNil(cache.image(for: a, source: source))
        XCTAssertNotNil(cache.image(for: c, source: source))
        cache.insert(bitmap(64), for: b, source: source)
        XCTAssertNil(cache.image(for: b, source: source), "one oversized image must not exceed the budget")
    }

    func testClearRejectsInFlightOldGeneration() {
        let cache = FolderIconBitmapCache(observesMemoryPressure: false)
        let source = NSImage(size: .zero)
        let old = cache.request(for: key("app"))
        cache.insert(bitmap(), for: old, source: source)
        cache.clear()
        XCTAssertFalse(cache.isCurrent(old))
        cache.insert(bitmap(), for: old, source: source)
        let current = cache.request(for: key("app"))
        XCTAssertNil(cache.image(for: current, source: source))
        cache.insert(bitmap(), for: current, source: source)
        XCTAssertNotNil(cache.image(for: current, source: source))
    }

    func testCacheDoesNotRetainOriginalNSImage() {
        let cache = FolderIconBitmapCache(observesMemoryPressure: false)
        var source: NSImage? = NSImage(size: .zero)
        weak var original = source
        cache.insert(bitmap(), for: cache.request(for: key("app")), source: source!)
        source = nil
        XCTAssertNil(original)
    }
}
