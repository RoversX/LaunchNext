import AppKit
import XCTest

final class BackgroundLabelContrastTests: XCTestCase {
    @MainActor
    func testResolvedStyleImmediatelyTracksMaskAndAppearanceChanges() {
        let sample = BackgroundLabelContrast.make(image: image { _, _ in (255, 255, 255, 255) })!
        let original = sample.resolvedStyle(darkAppearance: false, tints: [])
        XCTAssertFalse(original.usesWhiteText)
        XCTAssertEqual(sample.resolvedStyle(darkAppearance: false, tints: []), original)
        let mask = [BackgroundLabelContrast.Tint(red: 0, green: 0, blue: 0, alpha: 0.9)]
        XCTAssertTrue(sample.resolvedStyle(darkAppearance: false, tints: mask).usesWhiteText)
        XCTAssertEqual(sample.resolvedStyle(darkAppearance: false, tints: []), original)

        let transparent = BackgroundLabelContrast.make(image: image { _, _ in (0, 0, 0, 0) })!
        XCTAssertFalse(transparent.resolvedStyle(darkAppearance: false, tints: []).usesWhiteText)
        XCTAssertTrue(transparent.resolvedStyle(darkAppearance: true, tints: []).usesWhiteText)
        XCTAssertFalse(transparent.resolvedStyle(darkAppearance: false, tints: []).usesWhiteText)
    }

    private func image(width: Int = 64, height: Int = 64,
                       pixel: (Int, Int) -> (UInt8, UInt8, UInt8, UInt8)) -> CGImage {
        var bytes: [UInt8] = []
        for y in 0..<height {
            for x in 0..<width {
                let p = pixel(x, y)
                bytes.append(contentsOf: [p.0, p.1, p.2, p.3])
            }
        }
        let provider = CGDataProvider(data: Data(bytes) as CFData)!
        return CGImage(width: width, height: height, bitsPerComponent: 8, bitsPerPixel: 32,
            bytesPerRow: width * 4, space: CGColorSpace(name: CGColorSpace.sRGB)!,
            bitmapInfo: CGBitmapInfo(rawValue: CGImageAlphaInfo.premultipliedLast.rawValue),
            provider: provider, decode: nil, shouldInterpolate: false, intent: .defaultIntent)!
    }

    func testBlackWallpaperUsesWhiteTextInLightAppearance() {
        let sample = BackgroundLabelContrast.make(image: image { _, _ in (0, 0, 0, 255) })!
        XCTAssertEqual(sample.usesWhiteText(darkAppearance: false, tints: []), true)
    }

    func testWhiteWallpaperUsesBlackTextInDarkAppearance() {
        let sample = BackgroundLabelContrast.make(image: image { _, _ in (255, 255, 255, 255) })!
        XCTAssertEqual(sample.usesWhiteText(darkAppearance: true, tints: []), false)
    }

    func testMixedWallpaperChoosesOneColorRegardlessOfSpatialArrangement() {
        let leftDark = BackgroundLabelContrast.make(image: image { x, _ in
            x < 32 ? (0, 0, 0, 255) : (255, 255, 255, 255)
        })!
        let topDark = BackgroundLabelContrast.make(image: image { _, y in
            y < 32 ? (0, 0, 0, 255) : (255, 255, 255, 255)
        })!
        let color = leftDark.usesWhiteText(darkAppearance: false, tints: [])
        XCTAssertTrue(color)
        XCTAssertEqual(topDark.usesWhiteText(darkAppearance: false, tints: []), color)
        XCTAssertEqual(leftDark.usesWhiteText(darkAppearance: true, tints: []), color)
    }

    func testMaskAndBackdropAreIncludedInContrast() {
        let sample = BackgroundLabelContrast.make(image: image { _, _ in (255, 255, 255, 255) })!
        XCTAssertEqual(sample.usesWhiteText(darkAppearance: false,
            tints: [.init(red: 0, green: 0, blue: 0, alpha: 0.8)]), true)
        XCTAssertEqual(sample.usesWhiteText(darkAppearance: false,
            tints: [.init(red: 0, green: 0, blue: 0, alpha: 0.8),
                    .init(red: 1, green: 1, blue: 1, alpha: 0.9)]), false)
    }

    func testBrightHighlightsDoNotSwitchDarkWallpaperToBlackText() {
        let sample = BackgroundLabelContrast.make(image: image { x, _ in
            x < 16 ? (255, 255, 255, 255) : (50, 50, 50, 255)
        })!
        XCTAssertTrue(sample.usesWhiteText(darkAppearance: false, tints: []))
    }

    func testPredominantlyBrightWallpaperStillUsesBlackText() {
        let sample = BackgroundLabelContrast.make(image: image { x, _ in
            x < 48 ? (230, 230, 230, 255) : (50, 50, 50, 255)
        })!
        XCTAssertFalse(sample.usesWhiteText(darkAppearance: true, tints: []))
    }

    func testMediumGrayPrefersWhiteButLightGrayUsesBlack() {
        let medium = BackgroundLabelContrast.make(image: image { _, _ in (160, 160, 160, 255) })!
        let light = BackgroundLabelContrast.make(image: image { _, _ in (220, 220, 220, 255) })!
        XCTAssertTrue(medium.usesWhiteText(darkAppearance: false, tints: []))
        XCTAssertFalse(light.usesWhiteText(darkAppearance: true, tints: []))
    }

    func testTransparentImageUsesAppearanceAsUnderlyingColor() {
        let sample = BackgroundLabelContrast.make(image: image { _, _ in (0, 0, 0, 0) })!
        XCTAssertEqual(sample.usesWhiteText(darkAppearance: false, tints: []), false)
        XCTAssertEqual(sample.usesWhiteText(darkAppearance: true, tints: []), true)
    }

    func testDarkAndPredominantlyLightImagesNeedNoShadow() {
        for value: UInt8 in [0, 50, 230, 255] {
            let sample = BackgroundLabelContrast.make(image: image { _, _ in (value, value, value, 255) })!
            XCTAssertEqual(sample.style(darkAppearance: false, tints: []).shadow, .none)
        }
    }

    func testShadowStrengthGrowsWithLowContrastAreaAndStaysBounded() {
        var previousOpacity: Float = 0
        var previousRadius: CGFloat = 0
        for brightColumns in [4, 16, 32, 40] {
            let sample = BackgroundLabelContrast.make(image: image { x, _ in
                x < brightColumns ? (255, 255, 255, 255) : (0, 0, 0, 255)
            })!
            let style = sample.style(darkAppearance: false, tints: [])
            XCTAssertTrue(style.usesWhiteText)
            XCTAssertGreaterThanOrEqual(style.shadow.opacity, previousOpacity)
            XCTAssertGreaterThanOrEqual(style.shadow.radius, previousRadius)
            XCTAssertLessThanOrEqual(style.shadow.opacity, 0.8)
            XCTAssertLessThanOrEqual(style.shadow.radius, 1.5)
            XCTAssertEqual(style.shadow.offset, 0.5)
            previousOpacity = style.shadow.opacity
            previousRadius = style.shadow.radius
        }
        XCTAssertEqual(previousOpacity, 0.8)
        XCTAssertEqual(previousRadius, 1.5)
    }

    func testDarkMaskRemovesUnnecessaryShadowWithoutChangingWhiteText() {
        let sample = BackgroundLabelContrast.make(image: image { x, _ in
            x < 32 ? (255, 255, 255, 255) : (0, 0, 0, 255)
        })!
        let unmasked = sample.style(darkAppearance: false, tints: [])
        let masked = sample.style(darkAppearance: false,
            tints: [.init(red: 0, green: 0, blue: 0, alpha: 0.8)])
        XCTAssertTrue(unmasked.usesWhiteText && masked.usesWhiteText)
        XCTAssertGreaterThan(unmasked.shadow.opacity, 0.65)
        XCTAssertEqual(masked.shadow, .none)
    }

}
