import CoreGraphics
import Foundation

/// Confirms a paused system wallpaper without requiring byte-identical edge pixels.
/// macOS 27 single-window captures can vary by a few levels at the bitmap boundary.
public enum WallpaperFrameStability {
    public static let confirmationInterval: TimeInterval = 2
    public static let maximumConfirmations = 4
    public static let requiredStableComparisons = 2

    public static func supportsReuse(for identity: WallpaperIdentity, appearanceOnly: Bool = false) -> Bool {
        // Time-of-day desktops and arbitrary screen-saver extensions can change
        // without a Space, configuration or unlock event. Keep capturing those.
        identity.provider == "default" || identity.provider == "com.apple.wallpaper.choice.aerials"
            || (identity.provider == "com.apple.wallpaper.choice.image" && identity.kind == .staticImage)
            || (identity.provider == "com.apple.wallpaper.choice.dynamic" && appearanceOnly)
    }

    public static func reuseContextVersion(_ version: String?, appearanceOnly: Bool, systemIsDark: Bool) -> String? {
        version.map { appearanceOnly ? "\($0):appearance=\(systemIsDark ? "dark" : "light")" : $0 }
    }

    public struct Comparison: Sendable {
        public let matches: Bool
        /// Aggregate measurements only; never pixels, paths or image data.
        public let diagnostics: String?
    }

    public static func matches(_ first: CGImage, _ second: CGImage) -> Bool {
        compare(first, second).matches
    }

    public static func compare(_ first: CGImage, _ second: CGImage,
                               collectDiagnostics: Bool = false) -> Comparison {
        let dimensions = "first=\(first.width)x\(first.height) second=\(second.width)x\(second.height)"
        func rejected(_ reason: String) -> Comparison {
            Comparison(matches: false, diagnostics: collectDiagnostics ? "reason=\(reason) \(dimensions)" : nil)
        }
        guard first.width == second.width, first.height == second.height else { return rejected("dimensions") }
        guard first.width > 4, first.height > 4,
              first.width <= WallpaperImageRenderer.maximumUnfilteredPixelCount / first.height
        else { return rejected("unsupportedSize") }
        // Render only once at the existing bounded comparison resolution. Only
        // failed comparisons opt into an additional scan of these same buffers.
        let size = WallpaperImageRenderer.outputSize(for: CGSize(width: first.width, height: first.height))
        let width = Int(size.width), height = Int(size.height)
        guard let a = pixels(first, size: size), let b = pixels(second, size: size) else { return rejected("renderFailed") }
        var matched = true
        var failureX = 0, failureY = 0
        scan: for y in 0..<height {
            for x in 0..<width {
                let offset = (y * width + x) * 4
                if a[offset + 3] != b[offset + 3] {
                    matched = false; failureX = x; failureY = y; break scan
                }
                let edge = x < 2 || y < 2 || x >= width - 2 || y >= height - 2
                for channel in 0..<3 {
                    if abs(Int(a[offset + channel]) - Int(b[offset + channel])) > (edge ? 4 : 0) {
                        matched = false
                        failureX = x; failureY = y
                        break scan
                    }
                }
            }
        }
        guard !matched, collectDiagnostics else { return Comparison(matches: matched, diagnostics: nil) }
        let offset = (failureY * width + failureX) * 4
        let firstDelta = (0..<4).map { abs(Int(a[offset + $0]) - Int(b[offset + $0])) }
        let firstFailure = "firstFailure=\(failureX),\(failureY) firstDeltaRGBA=\(firstDelta.map(String.init).joined(separator: ","))"
        let measurements = differenceSummary(a, b, width: width, height: height)
        return Comparison(matches: false, diagnostics: "reason=pixels \(dimensions) \(firstFailure) \(measurements)")
    }

    private static func differenceSummary(_ a: [UInt8], _ b: [UInt8], width: Int, height: Int) -> String {
        var changed = 0, edgeChanged = 0, alphaChanged = 0, rgbTotal = 0, maxRGB = 0
        var bins = [Int](repeating: 0, count: 4) // Pixel maximum: 1, 2...4, 5...16, 17...255.
        var regions = [Int](repeating: 0, count: 9) // Row-major 3x3 in comparison-buffer coordinates.
        var minX = width, minY = height, maxX = -1, maxY = -1
        // Diagnostic estimates only: bound the extra work even in Debug builds.
        // The full acceptance scan above still checks every pixel as before.
        let step = max(1, Int(ceil(sqrt(Double(width * height) / 16_384))))
        for y in stride(from: 0, to: height, by: step) {
            for x in stride(from: 0, to: width, by: step) {
                let offset = (y * width + x) * 4
                var delta = 0
                for channel in 0..<3 {
                    let difference = abs(Int(a[offset + channel]) - Int(b[offset + channel]))
                    delta = max(delta, difference)
                    rgbTotal += difference
                }
                maxRGB = max(maxRGB, delta)
                let alphaDiffers = a[offset + 3] != b[offset + 3]
                if alphaDiffers { alphaChanged += 1 }
                guard delta > 0 || alphaDiffers else { continue }
                changed += 1
                if x < 2 || y < 2 || x >= width - 2 || y >= height - 2 { edgeChanged += 1 }
                if delta > 0 { bins[delta == 1 ? 0 : delta <= 4 ? 1 : delta <= 16 ? 2 : 3] += 1 }
                regions[min(2, y * 3 / height) * 3 + min(2, x * 3 / width)] += 1
                minX = min(minX, x); minY = min(minY, y)
                maxX = max(maxX, x); maxY = max(maxY, y)
            }
        }
        let total = ((width + step - 1) / step) * ((height + step - 1) / step)
        let percent = Double(changed) * 100 / Double(total)
        let meanRGB = Double(rgbTotal) / Double(total * 3)
        let numbers = String(format: "changedPct=%.5f meanRGB=%.5f", locale: Locale(identifier: "en_US_POSIX"), percent, meanRGB)
        return "sample=\(width)x\(height) step=\(step) changed=\(changed) total=\(total) \(numbers) maxRGB=\(maxRGB) alphaChanged=\(alphaChanged) edgeChanged=\(edgeChanged) interiorChanged=\(changed - edgeChanged) rgbBins=\(bins.map(String.init).joined(separator: ",")) regions=\(regions.map(String.init).joined(separator: ",")) bbox=\(minX),\(minY),\(maxX),\(maxY)"
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

/// Hiding preserves confirmation progress. A new context starts fresh unless
/// a live sample revalidates an already-settled frame of the same wallpaper.
public struct WallpaperSettlingState: Sendable {
    public private(set) var stableComparisons = 0
    public var isSettled: Bool { stableComparisons >= WallpaperFrameStability.requiredStableComparisons }

    public init() {}

    public func revalidated(matchesPrevious: Bool) -> Self {
        isSettled && matchesPrevious ? self : Self()
    }

    public mutating func observe(matchesPrevious: Bool) {
        stableComparisons = matchesPrevious ? stableComparisons + 1 : 0
    }
}

/// Coalesces observed configuration changes without delaying first use or cache
/// hits. A bounded wait avoids starving capture if metadata changes continuously.
public struct WallpaperCaptureQuietPeriod<Context: Equatable> {
    public static var quietInterval: TimeInterval { 2 }
    public static var maximumWait: TimeInterval { 6 }
    private var lastContext: Context?
    private var firstChange: TimeInterval?
    private var lastChange: TimeInterval?

    public init() {}

    public mutating func observe(_ context: Context, at time: TimeInterval) {
        defer { lastContext = context }
        guard let previous = lastContext, previous != context else { return }
        if firstChange == nil { firstChange = time }
        lastChange = time
    }

    public func delay(at time: TimeInterval) -> TimeInterval {
        guard let firstChange, let lastChange else { return 0 }
        return max(0, min(lastChange + Self.quietInterval, firstChange + Self.maximumWait) - time)
    }

    public mutating func captureStarted() {
        firstChange = nil
        lastChange = nil
    }
}
