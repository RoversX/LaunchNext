import CoreGraphics
import Foundation
import ImageIO
import LaunchNextWallpaperCore
import XCTest

final class WallpaperImageRendererTests: XCTestCase {
    func testSharpBudgetAdaptsToWindowAndCapsLargeDisplays() {
        let compact = CGSize(width: 800, height: 600)
        XCTAssertEqual(WallpaperImageRenderer.pixelBudget(for: compact, unfiltered: true), 480_000)
        XCTAssertEqual(WallpaperImageRenderer.pixelBudget(for: CGSize(width: 1600, height: 1200), unfiltered: true), 1_920_000)
        let large = CGSize(width: 6016, height: 3384)
        let budget = WallpaperImageRenderer.pixelBudget(for: large, unfiltered: true)
        XCTAssertEqual(budget, 4_000_000)
        let size = WallpaperImageRenderer.outputSize(for: large, maximumPixels: budget)
        XCTAssertLessThanOrEqual(size.width * size.height, 4_000_000)
        XCTAssertEqual(size.width / size.height, large.width / large.height, accuracy: 0.004)
        XCTAssertEqual(WallpaperImageRenderer.pixelBudget(for: large, unfiltered: false), 500_000)
        XCTAssertEqual(WallpaperImageRenderer.pixelBudget(for: .zero, unfiltered: true), 500_000)
    }

    func testSharpRenderingUsesRequestedBudgetWithoutChangingDefault() throws {
        let url = try writeImage(width: 2400, height: 1600)
        defer { try? FileManager.default.removeItem(at: url) }
        let size = CGSize(width: 2400, height: 1600)
        let fill = CGColor(gray: 0, alpha: 1)
        let sharp = try XCTUnwrap(WallpaperImageRenderer.render(url: url, displaySize: size,
            pixelSize: size, scaling: .fill, fillColor: fill, maximumPixels: 4_000_000))
        let blurred = try XCTUnwrap(WallpaperImageRenderer.render(url: url, displaySize: size,
            pixelSize: size, scaling: .fill, fillColor: fill))
        XCTAssertEqual(sharp.width, 2400)
        XCTAssertEqual(sharp.height, 1600)
        XCTAssertLessThanOrEqual(blurred.width * blurred.height, 500_000)
    }

    func testDesktopDescriptorUsesItsThumbnail() throws {
        let url = FileManager.default.temporaryDirectory.appendingPathComponent(UUID().uuidString + ".madesktop")
        defer { try? FileManager.default.removeItem(at: url) }
        let thumbnail = try writeImage(width: 100, height: 50)
        defer { try? FileManager.default.removeItem(at: thumbnail) }
        let data = try PropertyListSerialization.data(fromPropertyList: ["thumbnailPath": thumbnail.path],
                                                       format: .xml, options: 0)
        try data.write(to: url)
        let preview = try XCTUnwrap(WallpaperImageRenderer.previewImageURL(for: url))
        XCTAssertEqual(preview, thumbnail.standardizedFileURL)
        XCTAssertNotNil(render(preview, scaling: .fill))
    }

    func testPreviewRejectsRemoteAndMalformedDescriptors() throws {
        XCTAssertNil(WallpaperImageRenderer.previewImageURL(for: URL(string: "https://example.com/a.heic")!))
        let url = FileManager.default.temporaryDirectory.appendingPathComponent(UUID().uuidString + ".madesktop")
        defer { try? FileManager.default.removeItem(at: url) }
        for descriptor in [["thumbnailPath": "https://example.com/a.heic"], ["thumbnailPath": "relative.heic"], [:]] {
            try PropertyListSerialization.data(fromPropertyList: descriptor, format: .xml, options: 0).write(to: url)
            XCTAssertNil(WallpaperImageRenderer.previewImageURL(for: url))
        }
    }

    func testCaptureSizeStaysWithinBudgetAndPreservesAspect() {
        let size = WallpaperImageRenderer.outputSize(for: CGSize(width: 3840, height: 2160))
        XCTAssertLessThanOrEqual(size.width * size.height, 500_000)
        XCTAssertEqual(size.width / size.height, 16.0 / 9, accuracy: 0.004)
        XCTAssertEqual(WallpaperImageRenderer.outputSize(for: .zero), .zero)
    }

    func testFitPreservesLetterboxColorAndFillCoversDisplay() throws {
        let url = try writeImage(width: 100, height: 50)
        defer { try? FileManager.default.removeItem(at: url) }
        let fit = try XCTUnwrap(render(url, scaling: .fit))
        XCTAssertEqual(pixel(fit, x: 50, y: 5), [0, 255, 0, 255])
        XCTAssertEqual(pixel(fit, x: 50, y: 50), [255, 0, 0, 255])
        let fill = try XCTUnwrap(render(url, scaling: .fill))
        XCTAssertEqual(pixel(fill, x: 50, y: 5), [255, 0, 0, 255])
    }

    func testCenteredImageIsNotStretched() throws {
        let url = try writeImage(width: 20, height: 10)
        defer { try? FileManager.default.removeItem(at: url) }
        let image = try XCTUnwrap(render(url, scaling: .center))
        XCTAssertEqual(pixel(image, x: 10, y: 10), [0, 255, 0, 255])
        XCTAssertEqual(pixel(image, x: 50, y: 50), [255, 0, 0, 255])
    }

    func testMultiFrameImageDoesNotSilentlyUseFirstFrame() throws {
        let url = try writeImage(width: 20, height: 10, count: 2)
        defer { try? FileManager.default.removeItem(at: url) }
        XCTAssertNil(render(url, scaling: .fill))
    }

    private func render(_ url: URL, scaling: WallpaperImageRenderer.Scaling) -> CGImage? {
        WallpaperImageRenderer.render(url: url, displaySize: CGSize(width: 100, height: 100),
            pixelSize: CGSize(width: 100, height: 100), scaling: scaling,
            fillColor: CGColor(colorSpace: CGColorSpace(name: CGColorSpace.sRGB)!, components: [0, 1, 0, 1])!)
    }

    private func writeImage(width: Int, height: Int, count: Int = 1) throws -> URL {
        let context = try XCTUnwrap(CGContext(data: nil, width: width, height: height, bitsPerComponent: 8,
            bytesPerRow: width * 4, space: CGColorSpace(name: CGColorSpace.sRGB)!,
            bitmapInfo: CGImageAlphaInfo.premultipliedLast.rawValue))
        context.setFillColor(CGColor(colorSpace: CGColorSpace(name: CGColorSpace.sRGB)!, components: [1, 0, 0, 1])!)
        context.fill(CGRect(x: 0, y: 0, width: width, height: height))
        let image = try XCTUnwrap(context.makeImage())
        let url = FileManager.default.temporaryDirectory.appendingPathComponent(UUID().uuidString)
        let destination = try XCTUnwrap(CGImageDestinationCreateWithURL(url as CFURL,
            (count == 1 ? "public.png" : "com.compuserve.gif") as CFString, count, nil))
        for _ in 0..<count { CGImageDestinationAddImage(destination, image, nil) }
        XCTAssertTrue(CGImageDestinationFinalize(destination))
        return url
    }

    private func pixel(_ image: CGImage, x: Int, y: Int) -> [UInt8] {
        var bytes = [UInt8](repeating: 0, count: image.width * image.height * 4)
        bytes.withUnsafeMutableBytes { b in
            let context = CGContext(data: b.baseAddress, width: image.width, height: image.height,
                bitsPerComponent: 8, bytesPerRow: image.width * 4, space: CGColorSpace(name: CGColorSpace.sRGB)!,
                bitmapInfo: CGImageAlphaInfo.premultipliedLast.rawValue)!
            context.draw(image, in: CGRect(x: 0, y: 0, width: image.width, height: image.height))
        }
        let offset = (y * image.width + x) * 4
        return Array(bytes[offset..<(offset + 4)])
    }
}
