import CoreGraphics
import Foundation
import ImageIO

/// Renders an identified static wallpaper into a display-shaped, bounded bitmap.
public enum WallpaperImageRenderer {
    public enum Scaling: Sendable {
        case fill, fit, stretch, center
    }

    public static let maximumPixelCount = 500_000
    public static let maximumUnfilteredPixelCount = 4_000_000

    public static func pixelBudget(for pixelSize: CGSize, unfiltered: Bool) -> Int {
        guard unfiltered else { return maximumPixelCount }
        let pixels = pixelSize.width * pixelSize.height
        guard pixels.isFinite, pixels > 0 else { return maximumPixelCount }
        return max(1, Int(min(pixels.rounded(.up), CGFloat(maximumUnfilteredPixelCount))))
    }

    /// Dynamic desktop descriptors expose a local thumbnail, not the current animation frame.
    public static func previewImageURL(for url: URL) -> URL? {
        guard url.isFileURL else { return nil }
        guard url.pathExtension.lowercased() == "madesktop" else { return url }
        guard let data = try? Data(contentsOf: url),
              let descriptor = try? PropertyListSerialization.propertyList(from: data, format: nil) as? [String: Any],
              let path = descriptor["thumbnailPath"] as? String, path.hasPrefix("/") else { return nil }
        return URL(fileURLWithPath: path).standardizedFileURL
    }

    public static func hasMultipleImages(at url: URL) -> Bool {
        guard let source = CGImageSourceCreateWithURL(url as CFURL, [kCGImageSourceShouldCache: false] as CFDictionary) else { return false }
        return CGImageSourceGetCount(source) > 1
    }

    /// Recognize only verified light/dark pairs, never solar or hourly desktops.
    /// Read metadata without decoding the full-sized images.
    public static func isAppearanceOnlyDesktop(configuredURL: URL, reportedURL: URL?) -> Bool {
        guard let reportedURL, reportedURL.isFileURL, configuredURL.isFileURL else { return false }
        if configuredURL.pathExtension.lowercased() == "madesktop" {
            guard let data = try? Data(contentsOf: configuredURL),
                  let descriptor = try? PropertyListSerialization.propertyList(from: data, format: nil) as? [String: Any],
                  descriptor["isDynamic"] as? Bool == true,
                  descriptor["isSolar"] as? Bool == false,
                  let asset = descriptor["mobileAssetID"] as? String,
                  reportedURL.deletingPathExtension().lastPathComponent == asset,
                  reportedURL.pathExtension.lowercased() == "heic" else { return false }
        } else if configuredURL.standardizedFileURL != reportedURL.standardizedFileURL {
            return false
        }
        guard let source = CGImageSourceCreateWithURL(reportedURL as CFURL,
                  [kCGImageSourceShouldCache: false] as CFDictionary),
              CGImageSourceGetCount(source) == 2,
              let metadata = CGImageSourceCopyMetadataAtIndex(source, 0, nil),
              let tags = CGImageMetadataCopyTags(metadata) as? [CGImageMetadataTag] else { return false }
        var appearanceData: Data?
        for tag in tags {
            guard CGImageMetadataTagCopyNamespace(tag) as String? == "http://ns.apple.com/namespace/1.0/" else { continue }
            // Unknown Apple scheduling metadata must not silently become cacheable.
            guard CGImageMetadataTagCopyName(tag) as String? == "apr",
                  let encoded = CGImageMetadataTagCopyValue(tag) as? String,
                  let data = Data(base64Encoded: encoded) else { return false }
            appearanceData = data
        }
        guard let appearanceData,
              let mapping = try? PropertyListSerialization.propertyList(from: appearanceData, format: nil) as? [String: Any],
              Set(mapping.keys) == ["l", "d"],
              let light = mapping["l"] as? Int, let dark = mapping["d"] as? Int else { return false }
        return Set([light, dark]) == [0, 1]
    }

    public static func outputSize(for size: CGSize, maximumPixels: Int = maximumPixelCount) -> CGSize {
        guard size.width.isFinite, size.height.isFinite, size.width > 0, size.height > 0,
              maximumPixels > 0 else { return .zero }
        let scale = min(1, sqrt(CGFloat(maximumPixels) / (size.width * size.height)))
        return CGSize(width: max(1, floor(size.width * scale)), height: max(1, floor(size.height * scale)))
    }

    public static func imageRect(source: CGSize, display: CGSize, scaling: Scaling) -> CGRect {
        guard source.width > 0, source.height > 0, display.width > 0, display.height > 0 else { return .zero }
        let size: CGSize
        switch scaling {
        case .stretch: size = display
        case .center: size = source
        case .fill, .fit:
            let x = display.width / source.width, y = display.height / source.height
            let scale = scaling == .fill ? max(x, y) : min(x, y)
            size = CGSize(width: source.width * scale, height: source.height * scale)
        }
        return CGRect(x: (display.width - size.width) / 2, y: (display.height - size.height) / 2,
                      width: size.width, height: size.height)
    }

    public static func render(
        url: URL, displaySize: CGSize, pixelSize: CGSize, scaling: Scaling, fillColor: CGColor,
        maximumPixels: Int = maximumPixelCount
    ) -> CGImage? {
        guard url.isFileURL, FileManager.default.isReadableFile(atPath: url.path),
              let source = CGImageSourceCreateWithURL(url as CFURL, [kCGImageSourceShouldCache: false] as CFDictionary),
              CGImageSourceGetCount(source) == 1,
              let properties = CGImageSourceCopyPropertiesAtIndex(source, 0, nil) as? [CFString: Any],
              let width = (properties[kCGImagePropertyPixelWidth] as? NSNumber)?.doubleValue,
              let height = (properties[kCGImagePropertyPixelHeight] as? NSNumber)?.doubleValue,
              width > 0, height > 0 else { return nil }

        // Multi-image HEIC/GIF files can represent changing wallpaper content;
        // selecting their first image would not establish the current frame.
        let decodedSize = outputSize(for: CGSize(width: width, height: height), maximumPixels: maximumPixels)
        let options: [CFString: Any] = [
            kCGImageSourceCreateThumbnailFromImageAlways: true,
            kCGImageSourceCreateThumbnailWithTransform: true,
            kCGImageSourceThumbnailMaxPixelSize: Int(max(decodedSize.width, decodedSize.height)),
            kCGImageSourceShouldCacheImmediately: true
        ]
        guard let image = CGImageSourceCreateThumbnailAtIndex(source, 0, options as CFDictionary) else { return nil }
        let output = outputSize(for: pixelSize, maximumPixels: maximumPixels)
        guard output.width > 0, output.height > 0, displaySize.width > 0, displaySize.height > 0,
              let context = CGContext(data: nil, width: Int(output.width), height: Int(output.height),
                                      bitsPerComponent: 8, bytesPerRow: 0,
                                      space: CGColorSpace(name: CGColorSpace.sRGB)!,
                                      bitmapInfo: CGImageAlphaInfo.premultipliedLast.rawValue) else { return nil }
        context.setFillColor(fillColor)
        context.fill(CGRect(origin: .zero, size: output))
        context.scaleBy(x: output.width / displaySize.width, y: output.height / displaySize.height)
        let orientation = (properties[kCGImagePropertyOrientation] as? NSNumber)?.intValue ?? 1
        let swapsAxes = (5...8).contains(orientation)
        let dpiX = max(1, (properties[kCGImagePropertyDPIWidth] as? NSNumber)?.doubleValue ?? 72)
        let dpiY = max(1, (properties[kCGImagePropertyDPIHeight] as? NSNumber)?.doubleValue ?? 72)
        let sourceSize = swapsAxes
            ? CGSize(width: height * 72 / dpiY, height: width * 72 / dpiX)
            : CGSize(width: width * 72 / dpiX, height: height * 72 / dpiY)
        context.interpolationQuality = .high
        context.draw(image, in: imageRect(source: sourceSize, display: displaySize, scaling: scaling))
        return context.makeImage()
    }
}
