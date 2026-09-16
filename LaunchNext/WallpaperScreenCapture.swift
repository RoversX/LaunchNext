import AppKit
import Combine
import LaunchNextWallpaperCore
import ScreenCaptureKit
import SwiftUI

extension Notification.Name {
    static let wallpaperCapturePermissionChanged = Notification.Name("wallpaperCapturePermissionChanged")
}

@MainActor
final class WallpaperCaptureAccess: ObservableObject {
    static let shared = WallpaperCaptureAccess()
    @Published private(set) var isGranted = CGPreflightScreenCaptureAccess()
    @Published private(set) var hasRequested = UserDefaults.standard.bool(forKey: "wallpaperCapturePermissionRequested")

    func refresh() {
        let granted = CGPreflightScreenCaptureAccess()
        guard granted != isGranted else { return }
        isGranted = granted
        NotificationCenter.default.post(name: .wallpaperCapturePermissionChanged, object: nil)
    }

    // Only explicit selection of the matching-wallpaper option requests access.
    func request() {
        hasRequested = true
        UserDefaults.standard.set(true, forKey: "wallpaperCapturePermissionRequested")
        _ = CGRequestScreenCaptureAccess()
        refresh()
    }

    func openSettings() {
        NSWorkspace.shared.open(URL(string: "x-apple.systempreferences:com.apple.preference.security?Privacy_ScreenCapture")!)
    }
}

enum WallpaperCaptureError: Error {
    case permissionRequired
    case wallpaperWindowUnavailable
}

/// Single-frame capture only. The caller owns retries, caching and cancellation.
@MainActor
enum WallpaperScreenCapture {
    static func capture(displayID: CGDirectDisplayID) async throws -> CGImage {
        WallpaperCaptureAccess.shared.refresh()
        guard WallpaperCaptureAccess.shared.isGranted else { throw WallpaperCaptureError.permissionRequired }
        do {
            return try await captureAuthorizedWallpaper(displayID: displayID)
        } catch {
            let captureError = error as NSError
            if captureError.domain == SCStreamErrorDomain,
               captureError.code == SCStreamError.Code.userDeclined.rawValue {
                // Access can be revoked between preflight and the capture call.
                // Do not run the transient-window retry loop after a denial.
                throw WallpaperCaptureError.permissionRequired
            }
            throw error
        }
    }

    private static func captureAuthorizedWallpaper(displayID: CGDirectDisplayID) async throws -> CGImage {
        try Task.checkCancellation()
        let displayBounds = CGDisplayBounds(displayID)
        guard displayBounds.width > 0, displayBounds.height > 0 else {
            throw WallpaperCaptureError.wallpaperWindowUnavailable
        }
        let content = try await SCShareableContent.excludingDesktopWindows(false, onScreenWindowsOnly: true)
        try Task.checkCancellation()
        let matches = content.windows.filter { window in
            let owner = window.owningApplication?.bundleIdentifier
            let title = (window.title ?? "").lowercased()
            guard (owner == "com.apple.WindowManager" && title == "wallpaper")
                    || (owner == "com.apple.dock" && title.hasPrefix("wallpaper")) else { return false }
            let intersection = window.frame.intersection(displayBounds)
            return !intersection.isNull
                && intersection.width * intersection.height / (displayBounds.width * displayBounds.height) >= 0.95
                && intersection.width * intersection.height / (window.frame.width * window.frame.height) >= 0.95
        }
        guard matches.count == 1, let window = matches.first else {
            throw WallpaperCaptureError.wallpaperWindowUnavailable
        }
        let filter = SCContentFilter(desktopIndependentWindow: window)
        let scale = CGFloat(filter.pointPixelScale)
        let size = WallpaperImageRenderer.outputSize(for: CGSize(
            width: filter.contentRect.width * scale, height: filter.contentRect.height * scale
        ))
        guard size.width > 0, size.height > 0 else { throw WallpaperCaptureError.wallpaperWindowUnavailable }
        let configuration = SCStreamConfiguration()
        configuration.width = Int(size.width)
        configuration.height = Int(size.height)
        configuration.preservesAspectRatio = true
        configuration.showsCursor = false
        configuration.capturesAudio = false
        configuration.captureMicrophone = false
        configuration.ignoreShadowsSingleWindow = true
        configuration.includeChildWindows = false
        let image = try await SCScreenshotManager.captureImage(contentFilter: filter, configuration: configuration)
        try Task.checkCancellation()
        return image
    }
}

/// Kept separate from SettingsView's large body so access checks stay scoped to this row.
struct WallpaperCapturePermissionView: View {
    @ObservedObject var appStore: AppStore
    @ObservedObject private var access = WallpaperCaptureAccess.shared
    @State private var staticImageIsReadable = false
    @State private var checkGeneration = 0

    var body: some View {
        VStack(alignment: .leading, spacing: 6) {
            HStack {
                Text(appStore.localized(staticImageIsReadable ? .wallpaperCaptureStatic :
                    (access.isGranted ? .wallpaperCaptureGranted : .wallpaperCaptureRequired)))
                    .foregroundStyle(.secondary)

            }
            if !staticImageIsReadable {
                Text(appStore.localized(.wallpaperCaptureHint))
                    .font(.caption)
                    .foregroundStyle(.secondary)
            }
        }
        .task(id: checkGeneration) {
            access.refresh()
            guard let screen = NSApp.keyWindow?.screen ?? NSScreen.main else { return }
            let readable = await BackgroundImageController.canReadStaticWallpaper(for: screen)
            guard !Task.isCancelled else { return }
            staticImageIsReadable = readable
        }
        .onReceive(NotificationCenter.default.publisher(for: NSApplication.didBecomeActiveNotification)) { _ in
            access.refresh()
            checkGeneration += 1
        }
        .onReceive(NSWorkspace.shared.notificationCenter.publisher(for: NSWorkspace.activeSpaceDidChangeNotification)) { _ in
            checkGeneration += 1
        }
        .onReceive(NotificationCenter.default.publisher(for: NSWindow.didChangeScreenNotification)) { _ in
            checkGeneration += 1
        }
    }
}
