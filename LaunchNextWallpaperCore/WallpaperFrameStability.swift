import CoreGraphics
import Foundation

/// Confirms a paused system wallpaper without requiring byte-identical edge pixels.
/// macOS 27 single-window captures can vary by a few levels at the bitmap boundary.
public enum WallpaperFrameStability {
    public static let confirmationInterval: TimeInterval = 2
    public static let maximumConfirmations = 4
    public static let requiredStableComparisons = 2

    public static func supportsReuse(for identity: WallpaperIdentity) -> Bool {
        // Time-of-day desktops and arbitrary screen-saver extensions can change
        // without a Space, configuration or unlock event. Keep capturing those.
        identity.provider == "default" || identity.provider == "com.apple.wallpaper.choice.aerials"
    }

    public static func matches(_ first: CGImage, _ second: CGImage) -> Bool {
        guard first.width == second.width, first.height == second.height,
              first.width > 4, first.height > 4,
              first.width * first.height <= WallpaperImageRenderer.maximumUnfilteredPixelCount else { return false }
        // Keep confirmation work bounded even when the displayed frame is sharp.
        let size = WallpaperImageRenderer.outputSize(for: CGSize(width: first.width, height: first.height))
        let width = Int(size.width), height = Int(size.height)
        guard let a = pixels(first, size: size), let b = pixels(second, size: size) else { return false }
        for y in 0..<height {
            for x in 0..<width {
                let offset = (y * width + x) * 4
                guard a[offset + 3] == b[offset + 3] else { return false }
                let edge = x < 2 || y < 2 || x >= width - 2 || y >= height - 2
                for channel in 0..<3 {
                    if abs(Int(a[offset + channel]) - Int(b[offset + channel])) > (edge ? 4 : 0) {
                        return false
                    }
                }
            }
        }
        return true
    }

    private static func pixels(_ image: CGImage, size: CGSize) -> [UInt8]? {
        let width = Int(size.width), height = Int(size.height)
        var bytes = [UInt8](repeating: 0, count: width * height * 4)
        let rendered = bytes.withUnsafeMutableBytes { buffer -> Bool in
            guard let space = CGColorSpace(name: CGColorSpace.sRGB),
                  let context = CGContext(data: buffer.baseAddress, width: width, height: height,
                    bitsPerComponent: 8, bytesPerRow: width * 4, space: space,
                    bitmapInfo: CGBitmapInfo.byteOrder32Big.rawValue | CGImageAlphaInfo.premultipliedLast.rawValue)
            else { return false }
            context.setBlendMode(.copy)
            context.draw(image, in: CGRect(origin: .zero, size: size))
            return true
        }
        return rendered ? bytes : nil
    }
}

/// A context change discards this value. Hiding a window preserves the last
/// sample, but never promotes a single sample or a fallback to a settled frame.
public struct WallpaperSettlingState: Sendable {
    public private(set) var stableComparisons = 0
    public var isSettled: Bool { stableComparisons >= WallpaperFrameStability.requiredStableComparisons }

    public init() {}

    public mutating func observe(matchesPrevious: Bool) {
        stableComparisons = matchesPrevious ? stableComparisons + 1 : 0
    }
}
