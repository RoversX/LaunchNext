import AppKit
import CoreGraphics
import Darwin

enum WallpaperImageProvider {
    private typealias CGWindowListCreateImageFn = @convention(c) (CGRect, CGWindowListOption, CGWindowID, CGWindowImageOption) -> Unmanaged<CGImage>?

    private static let windowImageFunction: CGWindowListCreateImageFn? = {
        guard let handle = dlopen("/System/Library/Frameworks/CoreGraphics.framework/CoreGraphics", RTLD_NOW),
              let symbol = dlsym(handle, "CGWindowListCreateImage") else {
            return nil
        }
        return unsafeBitCast(symbol, to: CGWindowListCreateImageFn.self)
    }()

    static func image(for screen: NSScreen) -> NSImage? {
        preferredImage(
            workspaceImage: { desktopImage(for: screen) },
            capturedImage: { captureDesktopWallpaper(for: screen) }
        )
    }

    static func preferredImage(workspaceImage: () -> NSImage?,
                               capturedImage: () -> NSImage?) -> NSImage? {
        workspaceImage() ?? capturedImage()
    }

    private static func desktopImage(for screen: NSScreen) -> NSImage? {
        guard let url = NSWorkspace.shared.desktopImageURL(for: screen),
              let image = NSImage(contentsOf: url) else {
            return nil
        }
        image.size = screen.frame.size
        return image
    }

    private static func captureDesktopWallpaper(for screen: NSScreen) -> NSImage? {
        let frame = screen.frame
        let windowInfo = CGWindowListCopyWindowInfo([.optionOnScreenOnly], kCGNullWindowID) as? [[String: Any]] ?? []

        let targetWindowID: CGWindowID? = windowInfo.first(where: { info in
            let owner = info[kCGWindowOwnerName as String] as? String ?? ""
            let name = info[kCGWindowName as String] as? String ?? ""
            guard owner == "WindowManager", name == "Wallpaper" else { return false }
            guard let bounds = info[kCGWindowBounds as String] as? [String: Any],
                  let x = bounds["X"] as? CGFloat,
                  let y = bounds["Y"] as? CGFloat,
                  let width = bounds["Width"] as? CGFloat,
                  let height = bounds["Height"] as? CGFloat else { return false }
            return CGRect(x: x, y: y, width: width, height: height).intersects(frame)
        }).flatMap { info in
            info[kCGWindowNumber as String] as? CGWindowID
        }

        guard let targetWindowID,
              let cgImage = windowImageFunction?(CGRect.null,
                                                  .optionIncludingWindow,
                                                  targetWindowID,
                                                  [.boundsIgnoreFraming, .bestResolution])?.takeRetainedValue() else {
            return nil
        }

        return NSImage(cgImage: cgImage, size: frame.size)
    }
}
