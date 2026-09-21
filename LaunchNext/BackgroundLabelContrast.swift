import AppKit
import QuartzCore

/// A small sRGB copy of the already-loaded background, never a screen capture.
/// Does not retain the full-sized image after sampling.
final class BackgroundLabelContrast: Sendable {
    struct Shadow: Equatable, Sendable {
        let opacity: Float
        let radius: CGFloat
        let offset: CGFloat
        static let none = Shadow(opacity: 0, radius: 0, offset: 0)
    }

    struct Style: Equatable, Sendable {
        let usesWhiteText: Bool
        let shadow: Shadow
    }

    @MainActor
    static func applyLabelShadow(to layer: CALayer, style: Shadow) {
        layer.shadowColor = NSColor.black.cgColor
        layer.shadowRadius = style.radius
        // CA grid coordinates point up; SwiftUI's matching title shadow points down.
        layer.shadowOffset = CGSize(width: 0, height: -style.offset)
        layer.shadowOpacity = style.opacity
    }

    struct Tint: Equatable, Sendable {
        let red: Double
        let green: Double
        let blue: Double
        let alpha: Double
    }

    private let pixels: [UInt8]
    @MainActor private var cachedStyle: (dark: Bool, tints: [Tint], value: Style)?

    /// A synchronous, bounded cache for view construction. Unlike a SwiftUI
    /// onChange cache, this supplies the right style on the very first update.
    @MainActor func resolvedStyle(darkAppearance: Bool, tints: [Tint]) -> Style {
        if let cachedStyle, cachedStyle.dark == darkAppearance, cachedStyle.tints == tints {
            return cachedStyle.value
        }
        let value = style(darkAppearance: darkAppearance, tints: tints)
        cachedStyle = (darkAppearance, tints, value)
        return value
    }

    private static let side = 64
    // Prefer white on mixed wallpapers. Black is reserved for a broad, clearly
    // light background, rather than a mean lifted by a few bright highlights.
    private static let brightLuminanceThreshold = 0.45
    private static let minimumBrightFraction = 2.0 / 3.0

    private init(pixels: [UInt8]) {
        self.pixels = pixels
    }

    static func make(image: CGImage) -> BackgroundLabelContrast? {
        var pixels = [UInt8](repeating: 0, count: side * side * 4)
        let rendered = pixels.withUnsafeMutableBytes { bytes -> Bool in
            guard let space = CGColorSpace(name: CGColorSpace.sRGB),
                  let context = CGContext(data: bytes.baseAddress, width: side, height: side,
                    bitsPerComponent: 8, bytesPerRow: side * 4, space: space,
                    bitmapInfo: CGImageAlphaInfo.premultipliedLast.rawValue
                        | CGBitmapInfo.byteOrder32Big.rawValue) else { return false }
            context.interpolationQuality = .medium
            context.draw(image, in: CGRect(x: 0, y: 0, width: side, height: side))
            return true
        }
        guard rendered else { return nil }
        return BackgroundLabelContrast(pixels: pixels)
    }

    /// Choose one color for the entire grid from the whole image, independent
    /// of icon positions, pagination or window geometry.
    func usesWhiteText(darkAppearance: Bool, tints: [Tint]) -> Bool {
        style(darkAppearance: darkAppearance, tints: tints).usesWhiteText
    }

    func style(darkAppearance: Bool, tints: [Tint]) -> Style {
        func linear(_ value: Double) -> Double {
            value <= 0.04045 ? value / 12.92 : pow((value + 0.055) / 1.055, 2.4)
        }
        var brightPixels = 0
        var lowContrastPixels = 0
        for row in 0..<Self.side {
            for column in 0..<Self.side {
                let i = (row * Self.side + column) * 4
                let background = darkAppearance ? 0.0 : 1.0
                let uncovered = background * (1 - Double(pixels[i + 3]) / 255)
                var r = Double(pixels[i]) / 255 + uncovered
                var g = Double(pixels[i + 1]) / 255 + uncovered
                var b = Double(pixels[i + 2]) / 255 + uncovered
                for tint in tints {
                    r = r * (1 - tint.alpha) + tint.red * tint.alpha
                    g = g * (1 - tint.alpha) + tint.green * tint.alpha
                    b = b * (1 - tint.alpha) + tint.blue * tint.alpha
                }
                let luminance = 0.2126 * linear(r) + 0.7152 * linear(g) + 0.0722 * linear(b)
                if luminance >= Self.brightLuminanceThreshold { brightPixels += 1 }
                if luminance > 0.2 { lowContrastPixels += 1 }
            }
        }
        let count = Double(Self.side * Self.side)
        let white = Double(brightPixels) / count < Self.minimumBrightFraction
        guard white, lowContrastPixels > 0 else {
            return Style(usesWhiteText: white, shadow: .none)
        }
        // One bounded, neutral shadow for the entire wallpaper. Ramp up as
        // more of it has weak contrast with white text; do not follow icons.
        let strength = min(1, Double(lowContrastPixels) / count / 0.5)
        // Lift the middle of the range while preserving both endpoints and
        // the same maximum footprint. This remains monotonic across wallpapers.
        let adjustedStrength = strength + 0.8 * strength * (1 - strength)
        let shadow = Shadow(opacity: Float(0.3 + 0.5 * sqrt(adjustedStrength)),
                            radius: 0.8 + 0.7 * adjustedStrength, offset: 0.5)
        return Style(usesWhiteText: true, shadow: shadow)
    }
}
