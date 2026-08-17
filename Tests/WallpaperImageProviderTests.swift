import AppKit

@main
struct WallpaperImageProviderTests {
    static func main() {
        testWorkspaceImageIsPreferred()
        testCaptureFallbackIsUsedWhenWorkspaceImageIsUnavailable()
        testCurrentScreenResolvesWallpaperImage()
        print("WallpaperImageProviderTests passed")
    }

    private static func testWorkspaceImageIsPreferred() {
        let workspaceImage = NSImage(size: NSSize(width: 1, height: 1))
        var captured = false

        let result = WallpaperImageProvider.preferredImage(
            workspaceImage: { workspaceImage },
            capturedImage: {
                captured = true
                return NSImage(size: NSSize(width: 2, height: 2))
            }
        )

        precondition(result === workspaceImage)
        precondition(!captured)
    }

    private static func testCaptureFallbackIsUsedWhenWorkspaceImageIsUnavailable() {
        let capturedImage = NSImage(size: NSSize(width: 2, height: 2))

        let result = WallpaperImageProvider.preferredImage(
            workspaceImage: { nil },
            capturedImage: { capturedImage }
        )

        precondition(result === capturedImage)
    }

    private static func testCurrentScreenResolvesWallpaperImage() {
        guard let screen = NSScreen.main else {
            preconditionFailure("Expected a main screen")
        }

        guard let image = WallpaperImageProvider.image(for: screen) else {
            preconditionFailure("Expected a wallpaper image for the main screen")
        }
        precondition(image.size == screen.frame.size)
    }
}
