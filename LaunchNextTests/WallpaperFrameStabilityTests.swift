import CoreGraphics
import Foundation
import LaunchNextWallpaperCore
import XCTest

final class WallpaperFrameStabilityTests: XCTestCase {
    func testCaptureQuietPeriodCoalescesChangesWithoutDelayingOrdinaryOpens() {
        var period = WallpaperCaptureQuietPeriod<String>()
        period.observe("A", at: 0)
        XCTAssertEqual(period.delay(at: 0), 0)
        period.observe("A", at: 1)
        XCTAssertEqual(period.delay(at: 1), 0)
        period.observe("B", at: 2)
        XCTAssertEqual(period.delay(at: 2), 2)
        period.observe("C", at: 3)
        XCTAssertEqual(period.delay(at: 3), 2)
        period.observe("C", at: 4) // Reopening does not restart the wait.
        XCTAssertEqual(period.delay(at: 4), 1)
        XCTAssertEqual(period.delay(at: 5), 0)
        period.captureStarted()
        period.observe("C", at: 6)
        XCTAssertEqual(period.delay(at: 6), 0)
        period.observe("D", at: 7)
        XCTAssertEqual(period.delay(at: 7), 2)
    }

    func testCaptureQuietPeriodIsBoundedAndIndependentPerDisplay() {
        var first = WallpaperCaptureQuietPeriod<Int>()
        var second = WallpaperCaptureQuietPeriod<Int>()
        first.observe(0, at: 0)
        second.observe(0, at: 0)
        for tick in 1...7 { first.observe(tick, at: Double(tick)) }
        XCTAssertEqual(first.delay(at: 7), 0) // Six seconds since the first change.
        XCTAssertEqual(second.delay(at: 7), 0)
        first.captureStarted()
        first.observe(8, at: 8)
        XCTAssertEqual(first.delay(at: 8), 2)
    }

    func testDifferenceDiagnosticsMeasureSmallInteriorChangeWithoutChangingDecision() throws {
        let original = try image()
        let changed = try image(change: (8, 8, 1))
        let comparison = WallpaperFrameStability.compare(original, changed, collectDiagnostics: true)
        XCTAssertFalse(comparison.matches)
        let details = try XCTUnwrap(comparison.diagnostics)
        XCTAssertTrue(details.contains("reason=pixels first=16x16 second=16x16"))
        XCTAssertTrue(details.contains("changed=1 total=256"))
        XCTAssertTrue(details.contains("changedPct=0.39062"))
        XCTAssertTrue(details.contains("maxRGB=1 alphaChanged=0 edgeChanged=0 interiorChanged=1"))
        XCTAssertTrue(details.contains("rgbBins=1,0,0,0"))
        XCTAssertTrue(details.contains("regions=0,0,0,0,1,0,0,0,0"))
        XCTAssertEqual(comparison.matches, WallpaperFrameStability.matches(original, changed))
        XCTAssertNil(WallpaperFrameStability.compare(original, changed).diagnostics)
    }

    func testDifferenceDiagnosticsDistinguishDimensionsAlphaAndBoundary() throws {
        let original = try image()
        let dimensions = WallpaperFrameStability.compare(original, try image(width: 17), collectDiagnostics: true)
        XCTAssertFalse(dimensions.matches)
        XCTAssertEqual(dimensions.diagnostics, "reason=dimensions first=16x16 second=17x16")
        let alpha = WallpaperFrameStability.compare(original, try image(alpha: 254), collectDiagnostics: true)
        XCTAssertFalse(alpha.matches)
        XCTAssertTrue(try XCTUnwrap(alpha.diagnostics).contains("alphaChanged=256"))
        let boundary = WallpaperFrameStability.compare(original, try image(change: (5, 15, 5)), collectDiagnostics: true)
        XCTAssertFalse(boundary.matches)
        XCTAssertTrue(try XCTUnwrap(boundary.diagnostics).contains("edgeChanged=1 interiorChanged=0"))
        let tolerated = WallpaperFrameStability.compare(original, try image(change: (5, 15, 4)), collectDiagnostics: true)
        XCTAssertTrue(tolerated.matches)
        XCTAssertNil(tolerated.diagnostics)
    }

    func testRevalidationRequiresPreviouslySettledAndMatchingPixels() {
        var previous = WallpaperSettlingState()
        XCTAssertFalse(previous.revalidated(matchesPrevious: true).isSettled)
        previous.observe(matchesPrevious: true)
        XCTAssertEqual(previous.revalidated(matchesPrevious: true).stableComparisons, 0)
        previous.observe(matchesPrevious: true)
        XCTAssertTrue(previous.revalidated(matchesPrevious: true).isSettled)

        var changed = previous.revalidated(matchesPrevious: false)
        XCTAssertEqual(changed.stableComparisons, 0)
        changed.observe(matchesPrevious: true)
        XCTAssertFalse(changed.isSettled)
        changed.observe(matchesPrevious: true)
        XCTAssertTrue(changed.isSettled)
    }

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

    func testOnlyVerifiedAppearanceDynamicProviderCanOptIntoReuse() {
        XCTAssertTrue(WallpaperFrameStability.supportsReuse(for: identity("com.apple.wallpaper.choice.dynamic"), appearanceOnly: true))
        XCTAssertFalse(WallpaperFrameStability.supportsReuse(for: identity("com.apple.wallpaper.choice.dynamic")))
        XCTAssertFalse(WallpaperFrameStability.supportsReuse(for: identity("third.party"), appearanceOnly: true))
        XCTAssertFalse(WallpaperFrameStability.supportsReuse(for: identity("com.apple.wallpaper.choice.screen-saver"), appearanceOnly: true))
    }

    func testAppearanceChangeInvalidatesOnlyAppearanceDependentContext() {
        let light = WallpaperFrameStability.reuseContextVersion("configuration", appearanceOnly: true, systemIsDark: false)
        let dark = WallpaperFrameStability.reuseContextVersion("configuration", appearanceOnly: true, systemIsDark: true)
        XCTAssertNotEqual(light, dark)
        XCTAssertEqual(light, WallpaperFrameStability.reuseContextVersion("configuration", appearanceOnly: true, systemIsDark: false))
        XCTAssertNotEqual(light, WallpaperFrameStability.reuseContextVersion("changed", appearanceOnly: true, systemIsDark: false))
        XCTAssertEqual(WallpaperFrameStability.reuseContextVersion("configuration", appearanceOnly: false, systemIsDark: true), "configuration")
        XCTAssertNil(WallpaperFrameStability.reuseContextVersion(nil, appearanceOnly: true, systemIsDark: true))
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

    func testContextDiagnosticsIsolateTimestampFromContentChanges() {
        let desktop: [String: Any] = ["Content": ["Choices": [["Provider": "default"]]],
                                     "LastUse": Date(timeIntervalSince1970: 1), "LastSet": Date(timeIntervalSince1970: 1)]
        func components(_ value: [String: Any]) -> [String: String] {
            WallpaperIdentityResolver.desktopContextComponents(displayUUID: "A",
                store: ["Displays": ["A": ["Desktop": value, "Idle": ["private": "ignored"]]]])
        }
        let before = components(desktop)
        var updated = desktop
        updated["LastUse"] = Date(timeIntervalSince1970: 2)
        let after = components(updated)
        XCTAssertEqual(Set(before.keys).union(after.keys).filter { before[$0] != after[$0] }, ["Desktop.LastUse"])
        updated["Content"] = ["Choices": [["Provider": "different"]]]
        XCTAssertNotEqual(after["Desktop.Content"], components(updated)["Desktop.Content"])
        XCTAssertEqual(after["Desktop.LastUse"], components(updated)["Desktop.LastUse"])
        XCTAssertFalse(before.keys.contains { $0.contains("Idle") || $0.contains("private") })
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
