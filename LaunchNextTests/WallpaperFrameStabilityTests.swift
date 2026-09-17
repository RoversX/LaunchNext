import CoreGraphics
import Foundation
import LaunchNextWallpaperCore
import XCTest

final class WallpaperFrameStabilityTests: XCTestCase {
    func testSharpFramesCanSettleButVisibleMovementDoesNot() throws {
        let original = try largeImage()
        XCTAssertTrue(WallpaperFrameStability.matches(original, original))
        XCTAssertFalse(WallpaperFrameStability.matches(original, try largeImage(moved: true)))
        let oversized = try largeImage(width: 2500)
        XCTAssertFalse(WallpaperFrameStability.matches(oversized, oversized))
    }

    private func largeImage(width: Int = 2000, moved: Bool = false) throws -> CGImage {
        let context = try XCTUnwrap(CGContext(data: nil, width: width, height: 2000,
            bitsPerComponent: 8, bytesPerRow: 0, space: CGColorSpace(name: CGColorSpace.sRGB)!,
            bitmapInfo: CGImageAlphaInfo.premultipliedLast.rawValue))
        context.setFillColor(CGColor(gray: 0.3, alpha: 1))
        context.fill(CGRect(x: 0, y: 0, width: width, height: 2000))
        context.setFillColor(CGColor(gray: 0.8, alpha: 1))
        context.fill(CGRect(x: moved ? 1001 : 1000, y: 800, width: 300, height: 300))
        return try XCTUnwrap(context.makeImage())
    }

    func testAllowsOnlySmallBoundaryVariation() throws {
        let original = try image()
        XCTAssertTrue(WallpaperFrameStability.matches(original, original))
        XCTAssertTrue(WallpaperFrameStability.matches(original, try image(change: (5, 15, 4))))
        XCTAssertFalse(WallpaperFrameStability.matches(original, try image(change: (5, 15, 5))))
        XCTAssertFalse(WallpaperFrameStability.matches(original, try image(change: (5, 5, 1))))
    }

    func testRejectsDifferentDimensionsAndAlpha() throws {
        let original = try image()
        XCTAssertFalse(WallpaperFrameStability.matches(original, try image(width: 17)))
        XCTAssertFalse(WallpaperFrameStability.matches(original, try image(alpha: 254)))
    }

    func testMovementResetsConsecutiveConfirmationAndNewContextStartsUnconfirmed() {
        var state = WallpaperSettlingState()
        XCTAssertFalse(state.isSettled)
        state.observe(matchesPrevious: true)
        XCTAssertFalse(state.isSettled)
        state.observe(matchesPrevious: false)
        XCTAssertEqual(state.stableComparisons, 0)
        state.observe(matchesPrevious: true)
        XCTAssertFalse(state.isSettled)
        state.observe(matchesPrevious: true)
        XCTAssertTrue(state.isSettled)
        XCTAssertFalse(WallpaperSettlingState().isSettled)
    }

    func testUnknownAndTimeOfDayProvidersDoNotReusePausedSamples() {
        for provider in ["com.apple.wallpaper.choice.dynamic", "com.apple.wallpaper.choice.screen-saver", "third.party", "com.apple.wallpaper.choice.image"] {
            XCTAssertFalse(WallpaperFrameStability.supportsReuse(for: identity(provider)))
        }
        XCTAssertTrue(WallpaperFrameStability.supportsReuse(for: identity("default")))
        XCTAssertTrue(WallpaperFrameStability.supportsReuse(for: identity("com.apple.wallpaper.choice.aerials")))
    }

    func testReuseRequiresBothIdentityMatchAndSettledCapture() {
        XCTAssertEqual(WallpaperRefreshPolicy.windowShown(kind: .unknown, hasMatchingContent: true, hasSettledCapture: true), .reuse)
        XCTAssertEqual(WallpaperRefreshPolicy.windowShown(kind: .animated, hasMatchingContent: true, hasSettledCapture: false), .capture)
        XCTAssertEqual(WallpaperRefreshPolicy.windowShown(kind: .animated, hasMatchingContent: false, hasSettledCapture: true), .capture)
        XCTAssertEqual(WallpaperRefreshPolicy.windowShown(kind: nil, hasMatchingContent: true, hasSettledCapture: true), .capture)
    }

    func testContextIncludesLastUseButNotHistoricalSpacesOrAnotherDisplay() throws {
        let entry: [String: Any] = ["Linked": ["Content": ["Choices": [["Provider": "default", "Configuration": Data([1, 2])]]], "LastUse": Date(timeIntervalSince1970: 1)]]
        var store: [String: Any] = ["Displays": ["A": entry, "B": entry], "Spaces": ["old": entry]]
        let first = try XCTUnwrap(WallpaperIdentityResolver.desktopContextVersion(displayUUID: "A", store: store))
        store["Spaces"] = ["different": entry]
        store["Displays"] = ["A": entry, "B": ["Linked": ["LastUse": Date()]]]
        XCTAssertEqual(WallpaperIdentityResolver.desktopContextVersion(displayUUID: "A", store: store), first)
        var changed = entry
        var linked = try XCTUnwrap(changed["Linked"] as? [String: Any])
        linked["LastUse"] = Date(timeIntervalSince1970: 2)
        changed["Linked"] = linked
        store["Displays"] = ["A": changed]
        XCTAssertNotEqual(WallpaperIdentityResolver.desktopContextVersion(displayUUID: "A", store: store), first)
        XCTAssertNil(WallpaperIdentityResolver.desktopContextVersion(displayUUID: "A", store: [:]))
    }

    private func identity(_ provider: String) -> WallpaperIdentity {
        WallpaperIdentity(displayUUID: "display", provider: provider, configurationDigest: "config", kind: .unknown, source: .unavailable)
    }

    private func image(width: Int = 16, alpha: UInt8 = 255, change: (Int, Int, UInt8)? = nil) throws -> CGImage {
        var bytes = [UInt8](repeating: 0, count: width * 16 * 4)
        for pixel in 0..<(width * 16) {
            bytes[pixel * 4] = 64
            bytes[pixel * 4 + 1] = 80
            bytes[pixel * 4 + 2] = 96
            bytes[pixel * 4 + 3] = alpha
        }
        if let (x, y, delta) = change { bytes[(y * width + x) * 4] += delta }
        return try XCTUnwrap(CGImage(width: width, height: 16, bitsPerComponent: 8, bitsPerPixel: 32,
            bytesPerRow: width * 4, space: CGColorSpace(name: CGColorSpace.sRGB)!,
            bitmapInfo: CGBitmapInfo(rawValue: CGBitmapInfo.byteOrder32Big.rawValue | CGImageAlphaInfo.premultipliedLast.rawValue),
            provider: CGDataProvider(data: Data(bytes) as CFData)!, decode: nil, shouldInterpolate: false, intent: .defaultIntent))
    }
}
