import AppKit
import AVFoundation
import Combine
import CoreGraphics
import Darwin
import ImageIO
import LaunchNextWallpaperCore
import QuartzCore
import SwiftUI
import UniformTypeIdentifiers

private actor WallpaperSnapshotWriter {
    func persist(
        using token: WallpaperSnapshotLifecycle.Token,
        lifecycle: WallpaperSnapshotLifecycle,
        operation: @Sendable () -> Void
    ) {
        guard lifecycle.permitsPersistence(using: token) else { return }
        operation()
    }

    func removeAll(
        using token: WallpaperSnapshotLifecycle.Token,
        lifecycle: WallpaperSnapshotLifecycle,
        retryDelays: [Duration],
        operation: @Sendable () -> Bool
    ) async -> Bool {
        for attempt in 0...retryDelays.count {
            // Re-enabling the feature supersedes this removal request. New
            // snapshots must not be deleted by an old disabled-state retry.
            guard lifecycle.permitsRemoval(using: token) else { return true }
            if operation() { return true }
            guard attempt < retryDelays.count else { return false }
            try? await Task.sleep(for: retryDelays[attempt])
        }
        return false
    }
}

@MainActor
final class BackgroundImageController: ObservableObject {
    enum RefreshReason {
        case windowShown
        case contextChanged
        case settingsChanged
    }

    struct Content {
        let image: CGImage
        let wallpaperIdentity: WallpaperIdentity?

        init(image: CGImage, wallpaperIdentity: WallpaperIdentity? = nil) {
            self.image = image
            self.wallpaperIdentity = wallpaperIdentity
        }
    }

    private enum CacheKey: Equatable {
        case custom(path: String, fileSize: Int, modificationTime: TimeInterval, targetMaxDimension: Int)
    }

    private enum RequestIdentity: Equatable {
        case desktop(displayID: CGDirectDisplayID)
        case preview(displayID: CGDirectDisplayID)
        case custom(path: String)
    }

    private struct ResolvedWallpaper: Sendable {
        let exactIdentity: WallpaperIdentity?
        let verifiedStaticURL: URL?

        nonisolated init(resolution: WallpaperIdentityResolution, verifiedStaticURL: URL?) {
            guard let identity = resolution.exactIdentity else {
                exactIdentity = nil
                self.verifiedStaticURL = nil
                return
            }
            // The image provider may itself contain multiple frames (e.g. HEIC).
            // Read metadata once, on the identity resolver's background task.
            if identity.kind == .staticImage, case let .image(url) = identity.source,
               WallpaperImageRenderer.hasMultipleImages(at: url) {
                exactIdentity = WallpaperIdentity(displayUUID: identity.displayUUID, provider: identity.provider,
                    configurationDigest: identity.configurationDigest, kind: .unknown, source: identity.source)
                self.verifiedStaticURL = nil
            } else {
                exactIdentity = identity
                self.verifiedStaticURL = verifiedStaticURL
            }
        }
    }

    private struct StaticLayout: Sendable {
        let scaling: WallpaperImageRenderer.Scaling
        let fillColor: CGColor
        let displaySize: CGSize
        let pixelSize: CGSize

        init?(screen: NSScreen) {
            guard let options = NSWorkspace.shared.desktopImageOptions(for: screen) else { return nil }
            let rawScaling = (options[.imageScaling] as? NSNumber)?.uintValue
                ?? NSImageScaling.scaleProportionallyUpOrDown.rawValue
            guard let imageScaling = NSImageScaling(rawValue: rawScaling) else { return nil }
            switch imageScaling {
            case .scaleProportionallyUpOrDown:
                scaling = (options[.allowClipping] as? NSNumber)?.boolValue == true ? .fill : .fit
            case .scaleAxesIndependently: scaling = .stretch
            case .scaleNone: scaling = .center
            default: return nil
            }
            fillColor = ((options[.fillColor] as? NSColor) ?? .black).cgColor
            displaySize = screen.frame.size
            pixelSize = CGSize(width: displaySize.width * screen.backingScaleFactor,
                               height: displaySize.height * screen.backingScaleFactor)
        }

        nonisolated func render(url: URL) -> CGImage? {
            WallpaperImageRenderer.render(url: url, displaySize: displaySize, pixelSize: pixelSize,
                                          scaling: scaling, fillColor: fillColor)
        }
    }

    private typealias CGWindowListCreateImageFunction = @convention(c) (
        CGRect,
        CGWindowListOption,
        CGWindowID,
        CGWindowImageOption
    ) -> Unmanaged<CGImage>?

    // The background is always viewed through a frosted material (liquid glass /
    // ultraThinMaterial), which discards high-frequency detail - captures and
    // decodes above ~0.5MP are indistinguishable through it and only cost
    // memory, PNG size, and encode time.
    nonisolated private static let maximumDecodedPixelCount = WallpaperImageRenderer.maximumPixelCount
    nonisolated private static let snapshotWriter = WallpaperSnapshotWriter()
    nonisolated private static let snapshotLifecycle = WallpaperSnapshotLifecycle()
    nonisolated private static let snapshotRemovalRetryDelays: [Duration] = [
        .milliseconds(250), .seconds(1)
    ]
    nonisolated private static let windowImageFunction: CGWindowListCreateImageFunction? = {
        guard let handle = dlopen(
            "/System/Library/Frameworks/CoreGraphics.framework/CoreGraphics",
            RTLD_LAZY
        ), let symbol = dlsym(handle, "CGWindowListCreateImage") else {
            return nil
        }
        return unsafeBitCast(symbol, to: CGWindowListCreateImageFunction.self)
    }()

    @Published private(set) var content: Content?

    private var activeCacheKey: CacheKey?
    private var activeWallpaperIdentity: WallpaperIdentity?
    private var requestIdentity: RequestIdentity?
    private var loadTask: Task<Void, Never>?
    private var loadGeneration = 0
    private var isWindowVisible = false
    private var desktopContextIsDirty = true
    private var backgroundIsEnabled = true
    // Last frame published for each display. Lets a display switch paint the
    // right wallpaper synchronously instead of showing the previous display's
    // image (or black) for the ~0.5s the capture pipeline needs on a busy
    // main thread. A few frames at <=0.5MP each; cleared when the feature is
    // turned off or the view disappears.
    private var lastDesktopFrameByDisplay: [CGDirectDisplayID: Content] = [:]

    func refresh(
        for screen: NSScreen?,
        enabled: Bool,
        source: AppStore.BackgroundImageSource,
        customImagePath: String,
        reason: RefreshReason
    ) {
        switch reason {
        case .windowShown:
            guard !isWindowVisible else { return }
            isWindowVisible = true
        case .contextChanged:
            desktopContextIsDirty = true
        case .settingsChanged:
            break
        }

        guard enabled else {
            let removalToken = Self.snapshotLifecycle.transition(to: false)
            guard backgroundIsEnabled else { return }
            backgroundIsEnabled = false
            disableBackground(using: removalToken)
            return
        }
        Self.snapshotLifecycle.transition(to: true)
        backgroundIsEnabled = true

        guard let screen, let displayID = Self.displayID(for: screen) else {
            clearContentAndRequest()
            return
        }

        // Drop warm frames for displays that are no longer connected, so an
        // unplugged monitor's frame (and any stale reused display ID) does not
        // sit in memory indefinitely.
        if !lastDesktopFrameByDisplay.isEmpty {
            let connected = Set(NSScreen.screens.compactMap { Self.displayID(for: $0) })
            lastDesktopFrameByDisplay = lastDesktopFrameByDisplay.filter { connected.contains($0.key) }
        }

        let targetMaxDimension = max(
            1,
            Int(max(
                screen.frame.width * screen.backingScaleFactor,
                screen.frame.height * screen.backingScaleFactor
            ).rounded(.up))
        )

        switch source {
        case .desktopPreview:
            let request = RequestIdentity.preview(displayID: displayID)
            let changed = requestIdentity != request
            prepare(for: request)
            if changed { content = nil }
            guard isWindowVisible else { return }
            refreshPreview(displayID: displayID, desktopImageURL: NSWorkspace.shared.desktopImageURL(for: screen),
                           layout: StaticLayout(screen: screen), reason: reason, targetMaxDimension: targetMaxDimension)
        case .desktopWallpaper:
            let identity = RequestIdentity.desktop(displayID: displayID)
            let identityChanged = requestIdentity != identity
            prepare(for: identity)
            if identityChanged, let warmFrame = lastDesktopFrameByDisplay[displayID] {
                // Instant first paint: this display's last known frame goes up
                // synchronously; the capture below replaces it when ready.
                content = warmFrame
            }
            guard isWindowVisible else { return }
            let desktopImageURL = NSWorkspace.shared.desktopImageURL(for: screen)
            refreshDesktop(
                displayID: displayID,
                desktopImageURL: desktopImageURL,
                staticLayout: StaticLayout(screen: screen),
                reason: reason,
                targetMaxDimension: targetMaxDimension
            )
        case .customImage:
            let path = customImagePath.trimmingCharacters(in: .whitespacesAndNewlines)
            guard !path.isEmpty else {
                clearContent(for: .custom(path: ""))
                return
            }
            let normalizedPath = URL(fileURLWithPath: path).standardizedFileURL.path
            let identity = RequestIdentity.custom(path: normalizedPath)
            prepare(for: identity)
            guard isWindowVisible else { return }
            refreshCustom(
                path: normalizedPath,
                targetMaxDimension: targetMaxDimension
            )
        }
    }

    func windowDidHide() {
        guard isWindowVisible else { return }
        isWindowVisible = false
        loadTask?.cancel()
        loadTask = nil
        loadGeneration += 1
    }

    func clear() {
        loadTask?.cancel()
        loadTask = nil
        loadGeneration += 1
        isWindowVisible = false
        desktopContextIsDirty = true
        requestIdentity = nil
        activeCacheKey = nil
        activeWallpaperIdentity = nil
        lastDesktopFrameByDisplay.removeAll()
        content = nil
    }

    private func prepare(for identity: RequestIdentity) {
        guard requestIdentity != identity else { return }
        loadTask?.cancel()
        loadTask = nil
        loadGeneration += 1
        if case .preview = requestIdentity { content = nil }
        requestIdentity = identity
        activeCacheKey = nil
        activeWallpaperIdentity = nil
        desktopContextIsDirty = true
        // content is deliberately kept: switching display or source used to blank
        // the background here, showing black until the new capture landed. The
        // stale image stays visible while loading. If all attempts fail, only
        // content matching the requested wallpaper may remain visible.
    }

    private func clearContent(for identity: RequestIdentity) {
        loadTask?.cancel()
        loadTask = nil
        loadGeneration += 1
        requestIdentity = identity
        activeCacheKey = nil
        activeWallpaperIdentity = nil
        content = nil
    }

    private func clearContentAndRequest() {
        loadTask?.cancel()
        loadTask = nil
        loadGeneration += 1
        requestIdentity = nil
        activeCacheKey = nil
        activeWallpaperIdentity = nil
        lastDesktopFrameByDisplay.removeAll()
        desktopContextIsDirty = true
        content = nil
    }

    private func disableBackground(using removalToken: WallpaperSnapshotLifecycle.Token) {
        clearContentAndRequest()
        Task {
            let removedOrSuperseded = await Self.snapshotWriter.removeAll(
                using: removalToken,
                lifecycle: Self.snapshotLifecycle,
                retryDelays: Self.snapshotRemovalRetryDelays
            ) {
                Self.removeAllPersistentSnapshots()
            }
            if !removedOrSuperseded {
                NSLog("[LaunchNext] Failed to remove wallpaper snapshot cache after retries")
            }
        }
    }

    // Retry delays used when the wallpaper snapshot window is unavailable,
    // e.g. while a video/animated wallpaper is actively playing. The system
    // recreates the snapshot window shortly after the video pauses.
    nonisolated private static let desktopSnapshotRetryDelays: [Duration] = [
        .milliseconds(600), .milliseconds(1200), .milliseconds(2400), .milliseconds(4800)
    ]

    /// File-only preview. Never captures windows or reads/writes the live snapshot cache.
    private func refreshPreview(
        displayID: CGDirectDisplayID, desktopImageURL: URL?, layout: StaticLayout?,
        reason: RefreshReason, targetMaxDimension: Int
    ) {
        loadTask?.cancel()
        loadGeneration += 1
        let generation = loadGeneration
        loadTask = Task { [weak self] in
            guard let self else { return }
            defer { if generation == self.loadGeneration { self.loadTask = nil } }
            let identity = await Task.detached(priority: .userInitiated) {
                Self.resolveWallpaperIdentity(displayID: displayID, desktopImageURL: desktopImageURL).exactIdentity
            }.value
            guard !Task.isCancelled, generation == self.loadGeneration, self.isWindowVisible else { return }
            guard let identity else {
                self.content = nil
                self.activeWallpaperIdentity = nil
                return
            }
            if reason == .windowShown, !self.desktopContextIsDirty,
               self.activeWallpaperIdentity == identity, self.content != nil { return }
            let image = await Task.detached(priority: .userInitiated) { () -> CGImage? in
                switch identity.source {
                case let .image(url):
                    guard let previewURL = WallpaperImageRenderer.previewImageURL(for: url) else { return nil }
                    if let layout, let rendered = layout.render(url: previewURL) { return rendered }
                    return Self.decodeCustomImage(at: previewURL, targetMaxDimension: targetMaxDimension)
                case let .aerial(assetID):
                    guard !assetID.contains("/"), !assetID.contains("..") else { return nil }
                    let url = FileManager.default.homeDirectoryForCurrentUser.appendingPathComponent(
                        "Library/Application Support/com.apple.wallpaper/aerials/videos/\(assetID).mov")
                    guard let frame = await Self.firstVideoFrame(at: url, targetMaxDimension: 1000) else { return nil }
                    return Self.downsampleCapturedImageIfNeeded(frame)
                case .unavailable:
                    return nil
                }
            }.value
            guard !Task.isCancelled, generation == self.loadGeneration, self.isWindowVisible,
                  let screen = NSScreen.screens.first(where: { Self.displayID(for: $0) == displayID }) else { return }
            let currentURL = NSWorkspace.shared.desktopImageURL(for: screen)
            let current = await Task.detached(priority: .utility) {
                Self.resolveWallpaperIdentity(displayID: displayID, desktopImageURL: currentURL).exactIdentity
            }.value
            guard !Task.isCancelled, generation == self.loadGeneration, self.isWindowVisible else { return }
            guard current == identity else {
                self.content = nil
                self.activeWallpaperIdentity = nil
                return
            }
            self.content = image.map { Content(image: $0, wallpaperIdentity: identity) }
            self.activeWallpaperIdentity = image == nil ? nil : identity
            self.desktopContextIsDirty = false
        }
    }

    private func refreshDesktop(
        displayID: CGDirectDisplayID,
        desktopImageURL: URL?,
        staticLayout: StaticLayout?,
        reason: RefreshReason,
        targetMaxDimension: Int
    ) {
        loadTask?.cancel()
        loadGeneration += 1
        let generation = loadGeneration
        loadTask = Task { [weak self] in
            defer {
                if let self, generation == self.loadGeneration {
                    self.loadTask = nil
                }
            }
            guard let self else { return }

            let resolution = await Task.detached(priority: .userInitiated) {
                Self.resolveWallpaperIdentity(
                    displayID: displayID,
                    desktopImageURL: desktopImageURL
                )
            }.value

            guard !Task.isCancelled,
                  generation == self.loadGeneration,
                  self.isWindowVisible else { return }

            let identity = resolution.exactIdentity
            let hasMatchingContent = identity != nil
                && self.activeWallpaperIdentity == identity
                && self.content != nil
            let shouldForce = reason != .windowShown || self.desktopContextIsDirty
            let action = shouldForce
                ? WallpaperRefreshAction.capture
                : WallpaperRefreshPolicy.windowShown(
                    kind: identity?.kind,
                    hasMatchingContent: hasMatchingContent
                )
            if action == .reuse {
                return
            }

            // The previous image stays on screen until a new one is ready: only
            // stop treating it as a match for the current wallpaper.
            if self.activeWallpaperIdentity != identity {
                self.activeWallpaperIdentity = nil
            }

            // Direct reading is only valid for a confirmed, single-image source.
            // The renderer reproduces the desktop's scaling and letterboxing.
            if let url = resolution.verifiedStaticURL, let staticLayout {
                let image = await Task.detached(priority: .userInitiated) {
                    staticLayout.render(url: url)
                }.value
                if let image, await self.publishDesktopImage(
                    image, identity: identity, displayID: displayID, generation: generation,
                    requiresStableIdentity: true
                ) { return }
            }

            // Bounded retry loop: attempt the live snapshot; when it is not
            // available, publish a fallback frame once and keep retrying for a
            // few seconds so the true frozen frame replaces the fallback as
            // soon as the system exposes it again.
            var publishedFallback = false
            for attempt in 0...Self.desktopSnapshotRetryDelays.count {
                guard !Task.isCancelled,
                      generation == self.loadGeneration,
                      self.isWindowVisible else { return }

                var permissionRequired = false
                let image: CGImage?
                if #available(macOS 27, *) {
                    do {
                        image = try await WallpaperScreenCapture.capture(displayID: displayID)
                    } catch WallpaperCaptureError.permissionRequired {
                        permissionRequired = true
                        image = nil
                    } catch {
                        image = nil
                    }
                } else {
                    image = await Task.detached(priority: .userInitiated) { () -> CGImage? in
                        autoreleasepool {
                            guard let windowID = Self.findDesktopWallpaperWindow(for: displayID),
                                  let captured = Self.capture(windowID: windowID) else { return nil }
                            return Self.downsampleCapturedImageIfNeeded(captured)
                        }
                    }.value
                }

                guard !Task.isCancelled, generation == self.loadGeneration, self.isWindowVisible else { return }
                if let image, await self.publishDesktopImage(
                    image, identity: identity, displayID: displayID, generation: generation
                ) { return }

                if !publishedFallback {
                    let fallback: CGImage?
                    if let identity {
                        fallback = await Task.detached(priority: .userInitiated) {
                            await Self.loadExactFallbackImage(
                                for: identity,
                                targetMaxDimension: targetMaxDimension
                            )
                        }.value
                    } else {
                        fallback = nil
                    }

                    guard !Task.isCancelled,
                          generation == self.loadGeneration,
                          self.isWindowVisible else { return }
                    if let fallback {
                        // Deliberately does not set activeWallpaperIdentity: a fallback
                        // is not a live capture, so hasMatchingContent stays false and
                        // the next window show retries the real capture instead of
                        // reusing this image.
                        let published = Content(image: fallback, wallpaperIdentity: identity)
                        self.content = published
                        self.lastDesktopFrameByDisplay[displayID] = published
                        self.desktopContextIsDirty = false
                    }
                    publishedFallback = true
                }

                guard !permissionRequired, attempt < Self.desktopSnapshotRetryDelays.count else {
                    self.retainMatchingDesktopContent(for: identity, displayID: displayID)
                    return
                }
                try? await Task.sleep(for: Self.desktopSnapshotRetryDelays[attempt])
            }
        }
    }

    private func retainMatchingDesktopContent(for identity: WallpaperIdentity?, displayID: CGDirectDisplayID) {
        // Unknown identity is not a match, even if the cached frame is also
        // unidentified. Evict it so a later display switch cannot restore it.
        if identity == nil || lastDesktopFrameByDisplay[displayID]?.wallpaperIdentity != identity {
            lastDesktopFrameByDisplay.removeValue(forKey: displayID)
        }
        guard let identity, content?.wallpaperIdentity == identity else {
            content = lastDesktopFrameByDisplay[displayID]
            activeWallpaperIdentity = nil
            desktopContextIsDirty = true
            return
        }
    }

    private func publishDesktopImage(
        _ image: CGImage, identity: WallpaperIdentity?, displayID: CGDirectDisplayID,
        generation: Int, requiresStableIdentity: Bool = false
    ) async -> Bool {
        guard !Task.isCancelled, generation == loadGeneration, isWindowVisible,
              let screen = NSScreen.screens.first(where: { Self.displayID(for: $0) == displayID }) else { return false }
        let currentURL = NSWorkspace.shared.desktopImageURL(for: screen)
        let confirmed = await Task.detached(priority: .utility) {
            Self.resolveWallpaperIdentity(displayID: displayID, desktopImageURL: currentURL).exactIdentity
        }.value
        guard !Task.isCancelled, generation == loadGeneration, isWindowVisible else { return false }
        let stableIdentity = confirmed == identity ? identity : nil
        guard !requiresStableIdentity || stableIdentity != nil else { return false }
        let published = Content(image: image, wallpaperIdentity: stableIdentity)
        activeWallpaperIdentity = stableIdentity
        content = published
        lastDesktopFrameByDisplay[displayID] = published
        desktopContextIsDirty = false
        if let stableIdentity {
            let token = Self.snapshotLifecycle.currentToken()
            await Self.snapshotWriter.persist(using: token, lifecycle: Self.snapshotLifecycle) {
                Self.persistSnapshot(image, for: stableIdentity)
            }
        }
        return true
    }

    static func canReadStaticWallpaper(for screen: NSScreen) async -> Bool {
        guard let displayID = displayID(for: screen), let layout = StaticLayout(screen: screen) else { return false }
        let url = NSWorkspace.shared.desktopImageURL(for: screen)
        return await Task.detached(priority: .utility) {
            guard let source = Self.resolveWallpaperIdentity(displayID: displayID, desktopImageURL: url).verifiedStaticURL else { return false }
            return layout.render(url: source) != nil
        }.value
    }

    private func refreshCustom(path: String, targetMaxDimension: Int) {
        loadTask?.cancel()
        loadGeneration += 1
        let generation = loadGeneration
        loadTask = Task { [weak self] in
            defer {
                if let self, generation == self.loadGeneration {
                    self.loadTask = nil
                }
            }

            let cacheKey = await Task.detached(priority: .userInitiated) {
                let url = URL(fileURLWithPath: path)
                guard FileManager.default.isReadableFile(atPath: path) else { return CacheKey?.none }
                let values = try? url.resourceValues(forKeys: [.fileSizeKey, .contentModificationDateKey])
                return CacheKey.custom(
                    path: path,
                    fileSize: values?.fileSize ?? 0,
                    modificationTime: values?.contentModificationDate?.timeIntervalSince1970 ?? 0,
                    targetMaxDimension: targetMaxDimension
                )
            }.value

            guard let self, !Task.isCancelled, generation == self.loadGeneration else { return }
            guard let cacheKey else {
                self.activeCacheKey = nil
                self.content = nil
                return
            }
            if self.activeCacheKey == cacheKey, self.content != nil {
                return
            }

            let image = await Task.detached(priority: .userInitiated) {
                autoreleasepool {
                    Self.decodeCustomImage(
                        at: URL(fileURLWithPath: path),
                        targetMaxDimension: targetMaxDimension
                    )
                }
            }.value

            guard !Task.isCancelled, generation == self.loadGeneration else { return }
            guard let image else {
                self.activeCacheKey = nil
                self.content = nil
                return
            }

            self.activeCacheKey = cacheKey
            self.content = Content(image: image)
        }
    }

    private static func displayID(for screen: NSScreen) -> CGDirectDisplayID? {
        guard let number = screen.deviceDescription[NSDeviceDescriptionKey("NSScreenNumber")] as? NSNumber else {
            return nil
        }
        return CGDirectDisplayID(number.uint32Value)
    }

    nonisolated private static func findDesktopWallpaperWindow(
        for displayID: CGDirectDisplayID
    ) -> CGWindowID? {
        let displayBounds = CGDisplayBounds(displayID)
        guard displayBounds.width > 0, displayBounds.height > 0 else { return nil }

        let windows = CGWindowListCopyWindowInfo(.optionOnScreenOnly, kCGNullWindowID)
            as? [[String: Any]] ?? []

        return windows.compactMap { info -> (windowID: CGWindowID, score: CGFloat)? in
            let owner = info[kCGWindowOwnerName as String] as? String ?? ""
            let name = info[kCGWindowName as String] as? String ?? ""
            let normalizedName = name.lowercased()
            let isWallpaperWindow = (owner == "WindowManager" && normalizedName == "wallpaper")
                || (owner == "Dock" && normalizedName.hasPrefix("wallpaper"))
            guard isWallpaperWindow,
                  let windowIDNumber = info[kCGWindowNumber as String] as? NSNumber,
                  let bounds = windowBounds(from: info[kCGWindowBounds as String]) else {
                return nil
            }

            let intersection = bounds.intersection(displayBounds)
            guard !intersection.isNull, intersection.width > 0, intersection.height > 0 else { return nil }
            let displayArea = displayBounds.width * displayBounds.height
            let score = (intersection.width * intersection.height) / displayArea
            guard score >= 0.5 else { return nil }

            return (CGWindowID(windowIDNumber.uint32Value), score)
        }
        .max(by: { $0.score < $1.score })?
        .windowID
    }

    nonisolated private static func windowBounds(from value: Any?) -> CGRect? {
        guard let dictionary = value as? [String: Any],
              let x = (dictionary["X"] as? NSNumber)?.doubleValue,
              let y = (dictionary["Y"] as? NSNumber)?.doubleValue,
              let width = (dictionary["Width"] as? NSNumber)?.doubleValue,
              let height = (dictionary["Height"] as? NSNumber)?.doubleValue else {
            return nil
        }
        return CGRect(x: x, y: y, width: width, height: height)
    }

    nonisolated private static func capture(windowID: CGWindowID) -> CGImage? {
        windowImageFunction?(
            .null,
            .optionIncludingWindow,
            windowID,
            [.boundsIgnoreFraming, .nominalResolution]
        )?.takeRetainedValue()
    }

    nonisolated private static func downsampleCapturedImageIfNeeded(_ image: CGImage) -> CGImage? {
        let pixelCount = image.width * image.height
        guard pixelCount > maximumDecodedPixelCount else { return image }

        let scale = sqrt(Double(maximumDecodedPixelCount) / Double(pixelCount))
        let width = max(1, Int((Double(image.width) * scale).rounded(.down)))
        let height = max(1, Int((Double(image.height) * scale).rounded(.down)))
        let colorSpace = image.colorSpace ?? CGColorSpace(name: CGColorSpace.sRGB)!
        guard let context = CGContext(
            data: nil,
            width: width,
            height: height,
            bitsPerComponent: 8,
            bytesPerRow: 0,
            space: colorSpace,
            bitmapInfo: CGImageAlphaInfo.premultipliedLast.rawValue
        ) else {
            return nil
        }

        context.interpolationQuality = .high
        context.draw(image, in: CGRect(x: 0, y: 0, width: width, height: height))
        return context.makeImage()
    }

    nonisolated private static func decodeCustomImage(
        at url: URL,
        targetMaxDimension: Int
    ) -> CGImage? {
        let sourceOptions = [kCGImageSourceShouldCache: false] as CFDictionary
        guard let source = CGImageSourceCreateWithURL(url as CFURL, sourceOptions),
              let properties = CGImageSourceCopyPropertiesAtIndex(source, 0, nil) as? [CFString: Any],
              let width = (properties[kCGImagePropertyPixelWidth] as? NSNumber)?.doubleValue,
              let height = (properties[kCGImagePropertyPixelHeight] as? NSNumber)?.doubleValue,
              width > 0,
              height > 0 else {
            return nil
        }

        let sourceMaxDimension = max(width, height)
        let dimensionScale = min(1, Double(targetMaxDimension) / sourceMaxDimension)
        let pixelScale = min(1, sqrt(Double(maximumDecodedPixelCount) / (width * height)))
        let thumbnailMaxDimension = max(
            1,
            Int((sourceMaxDimension * min(dimensionScale, pixelScale)).rounded(.down))
        )
        let thumbnailOptions: [CFString: Any] = [
            kCGImageSourceCreateThumbnailFromImageAlways: true,
            kCGImageSourceCreateThumbnailWithTransform: true,
            kCGImageSourceThumbnailMaxPixelSize: thumbnailMaxDimension,
            kCGImageSourceShouldCacheImmediately: true
        ]
        return CGImageSourceCreateThumbnailAtIndex(source, 0, thumbnailOptions as CFDictionary)
    }

    // MARK: - Identity-bound wallpaper fallbacks

    nonisolated private static func resolveWallpaperIdentity(
        displayID: CGDirectDisplayID,
        desktopImageURL: URL?
    ) -> ResolvedWallpaper {
        guard let uuidRef = CGDisplayCreateUUIDFromDisplayID(displayID)?.takeRetainedValue() else {
            return ResolvedWallpaper(resolution: .unavailable, verifiedStaticURL: nil)
        }
        let displayUUID = CFUUIDCreateString(nil, uuidRef) as String
        let storeURL = FileManager.default.homeDirectoryForCurrentUser.appendingPathComponent(
            "Library/Application Support/com.apple.wallpaper/Store/Index.plist"
        )
        let store: [String: Any]
        if let data = try? Data(contentsOf: storeURL),
           let root = try? PropertyListSerialization.propertyList(
               from: data,
               options: [],
               format: nil
           ) as? [String: Any] {
            store = root
        } else {
            store = [:]
        }
        let verified = WallpaperIdentityResolver.resolve(
            displayUUID: displayUUID,
            store: store,
            currentDesktopImageURL: desktopImageURL,
            allowUnverifiedDesktopImageURL: false
        )
        let staticURL: URL?
        if let identity = verified.exactIdentity, identity.kind == .staticImage,
           case let .image(url) = identity.source, url == desktopImageURL?.standardizedFileURL {
            staticURL = url
        } else { staticURL = nil }
        if #available(macOS 27, *) {
            return ResolvedWallpaper(resolution: verified, verifiedStaticURL: staticURL)
        }
        return ResolvedWallpaper(resolution: WallpaperIdentityResolver.resolve(
            displayUUID: displayUUID, store: store, currentDesktopImageURL: desktopImageURL
        ), verifiedStaticURL: staticURL)
    }

    nonisolated private static func loadExactFallbackImage(
        for identity: WallpaperIdentity,
        targetMaxDimension: Int
    ) async -> CGImage? {
        if let cached = loadPersistentSnapshot(
            for: identity,
            targetMaxDimension: targetMaxDimension
        ) {
            return cached
        }

        switch identity.source {
        case let .image(url):
            // Preserve the macOS 26 fallback when the store or wallpaper window
            // is temporarily unavailable. macOS 27 requires verified rendering.
            if #available(macOS 27, *) { return nil }
            return decodeCustomImage(at: url, targetMaxDimension: targetMaxDimension)
        case let .aerial(assetID):
            if #available(macOS 27, *) { return nil }
            let videoURL = FileManager.default.homeDirectoryForCurrentUser.appendingPathComponent(
                "Library/Application Support/com.apple.wallpaper/aerials/videos/\(assetID).mov"
            )
            return await firstVideoFrame(at: videoURL, targetMaxDimension: targetMaxDimension)
        case .unavailable:
            return nil
        }
    }

    nonisolated private static func snapshotDirectoryURL() -> URL? {
        guard let caches = try? FileManager.default.url(
            for: .cachesDirectory,
            in: .userDomainMask,
            appropriateFor: nil,
            create: true
        ) else {
            return nil
        }
        return caches
            .appendingPathComponent("com.roversx.launchnext", isDirectory: true)
            .appendingPathComponent("WallpaperSnapshots", isDirectory: true)
    }

    nonisolated private static func snapshotURL(for identity: WallpaperIdentity) -> URL? {
        // Do not reuse gray captures left by CGWindowListCreateImage on macOS 27.
        let prefix: String
        if #available(macOS 27, *) { prefix = "sck-" } else { prefix = "" }
        return snapshotDirectoryURL()?.appendingPathComponent("\(prefix)\(identity.cacheFileStem).png")
    }

    nonisolated private static func loadPersistentSnapshot(
        for identity: WallpaperIdentity,
        targetMaxDimension: Int
    ) -> CGImage? {
        guard let url = snapshotURL(for: identity),
              FileManager.default.isReadableFile(atPath: url.path) else {
            return nil
        }
        return decodeCustomImage(at: url, targetMaxDimension: targetMaxDimension)
    }

    nonisolated private static func persistSnapshot(
        _ image: CGImage,
        for identity: WallpaperIdentity
    ) {
        guard let directory = snapshotDirectoryURL(),
              let destinationURL = snapshotURL(for: identity) else { return }

        let fileManager = FileManager.default
        // The file name is the wallpaper identity digest, so an existing file
        // already holds a frame for exactly this wallpaper. A static image can
        // never produce a different frame, so rewriting it is pure waste. An
        // animated wallpaper yields a new frame on every capture, so its cached
        // fallback is refreshed on the keep-alive cadence (at most once a day)
        // instead of paying a PNG encode on every window show.
        if fileManager.isReadableFile(atPath: destinationURL.path) {
            let modified = (try? destinationURL.resourceValues(forKeys: [.contentModificationDateKey]))?
                .contentModificationDate ?? .distantPast
            let stale = Date().timeIntervalSince(modified) > snapshotKeepAliveInterval
            if identity.kind == .staticImage || !stale {
                keepSnapshotAliveAndExpireStale(current: destinationURL, in: directory)
                return
            }
            // Animated and a day old: fall through and overwrite with this frame.
        }
        let temporaryURL = directory.appendingPathComponent(".\(UUID().uuidString).tmp")
        do {
            try fileManager.createDirectory(
                at: directory,
                withIntermediateDirectories: true,
                attributes: [.posixPermissions: 0o700]
            )
            try fileManager.setAttributes(
                [.posixPermissions: 0o700],
                ofItemAtPath: directory.path
            )
            guard let destination = CGImageDestinationCreateWithURL(
                temporaryURL as CFURL,
                UTType.png.identifier as CFString,
                1,
                nil
            ) else { return }
            CGImageDestinationAddImage(destination, image, nil)
            guard CGImageDestinationFinalize(destination) else {
                try? fileManager.removeItem(at: temporaryURL)
                return
            }
            try fileManager.setAttributes(
                [.posixPermissions: 0o600],
                ofItemAtPath: temporaryURL.path
            )
            if fileManager.fileExists(atPath: destinationURL.path) {
                _ = try fileManager.replaceItemAt(destinationURL, withItemAt: temporaryURL)
            } else {
                try fileManager.moveItem(at: temporaryURL, to: destinationURL)
            }
            pruneSnapshots(in: directory, keeping: destinationURL, displayUUID: identity.displayUUID)
        } catch {
            try? fileManager.removeItem(at: temporaryURL)
            return
        }
    }

    // The SKIP guard above means a cached file's modification date never moves
    // on its own, so mtime alone cannot distinguish "in daily use" from "display
    // unplugged months ago". Keep-alive: whenever a snapshot is confirmed
    // current, refresh its modification date at most once a day; expiry: any
    // snapshot not confirmed for 30 days - e.g. a display that never came back -
    // is deleted in the same pass.
    nonisolated private static let snapshotKeepAliveInterval: TimeInterval = 24 * 60 * 60
    nonisolated private static let snapshotExpiryInterval: TimeInterval = 30 * 24 * 60 * 60

    nonisolated private static func keepSnapshotAliveAndExpireStale(
        current destinationURL: URL,
        in directory: URL
    ) {
        let fileManager = FileManager.default
        let now = Date()
        let modified = (try? destinationURL.resourceValues(forKeys: [.contentModificationDateKey]))?
            .contentModificationDate ?? .distantPast
        guard now.timeIntervalSince(modified) > snapshotKeepAliveInterval else { return }
        try? fileManager.setAttributes(
            [.modificationDate: now],
            ofItemAtPath: destinationURL.path
        )
        guard let files = try? fileManager.contentsOfDirectory(
            at: directory,
            includingPropertiesForKeys: [.contentModificationDateKey],
            options: [.skipsHiddenFiles]
        ) else { return }
        for file in files where file.pathExtension.lowercased() == "png" {
            let fileModified = (try? file.resourceValues(forKeys: [.contentModificationDateKey]))?
                .contentModificationDate ?? .distantPast
            if now.timeIntervalSince(fileModified) > snapshotExpiryInterval {
                try? fileManager.removeItem(at: file)
            }
        }
    }

    nonisolated private static func pruneSnapshots(
        in directory: URL,
        keeping destinationURL: URL,
        displayUUID: String
    ) {
        let fileManager = FileManager.default
        guard let files = try? fileManager.contentsOfDirectory(
            at: directory,
            includingPropertiesForKeys: [.contentModificationDateKey],
            options: [.skipsHiddenFiles]
        ) else { return }

        let pngFiles = files.filter { $0.pathExtension.lowercased() == "png" }
        for file in pngFiles where file != destinationURL
            && (file.lastPathComponent.hasPrefix("\(displayUUID)-")
                || file.lastPathComponent.hasPrefix("sck-\(displayUUID)-")) {
            try? fileManager.removeItem(at: file)
        }

        let remaining = (try? fileManager.contentsOfDirectory(
            at: directory,
            includingPropertiesForKeys: [.contentModificationDateKey],
            options: [.skipsHiddenFiles]
        ))?.filter { $0.pathExtension.lowercased() == "png" } ?? []
        let newestFirst = remaining.sorted {
            let lhs = (try? $0.resourceValues(forKeys: [.contentModificationDateKey]))?.contentModificationDate
                ?? .distantPast
            let rhs = (try? $1.resourceValues(forKeys: [.contentModificationDateKey]))?.contentModificationDate
                ?? .distantPast
            return lhs > rhs
        }
        let now = Date()
        for (index, file) in newestFirst.enumerated() {
            let modified = (try? file.resourceValues(forKeys: [.contentModificationDateKey]))?
                .contentModificationDate ?? .distantPast
            if index >= 8 || now.timeIntervalSince(modified) > snapshotExpiryInterval {
                try? fileManager.removeItem(at: file)
            }
        }
    }

    nonisolated private static func removeAllPersistentSnapshots() -> Bool {
        guard let directory = snapshotDirectoryURL() else { return false }
        let fileManager = FileManager.default
        guard fileManager.fileExists(atPath: directory.path) else { return true }
        do {
            try fileManager.removeItem(at: directory)
        } catch {
            return !fileManager.fileExists(atPath: directory.path)
        }
        return !fileManager.fileExists(atPath: directory.path)
    }

    nonisolated private static func firstVideoFrame(
        at url: URL,
        targetMaxDimension: Int
    ) async -> CGImage? {
        guard FileManager.default.isReadableFile(atPath: url.path) else { return nil }
        let generator = AVAssetImageGenerator(asset: AVURLAsset(url: url))
        generator.appliesPreferredTrackTransform = true
        generator.maximumSize = CGSize(width: targetMaxDimension, height: targetMaxDimension)
        return try? await generator.image(at: .zero).image
    }
}

final class BackgroundImageLayerView: NSView {
    override init(frame frameRect: NSRect) {
        super.init(frame: frameRect)
        wantsLayer = true
        layer?.masksToBounds = true
        layer?.contentsGravity = .resizeAspectFill
        layer?.magnificationFilter = .linear
        layer?.minificationFilter = .trilinear
        layer?.backgroundColor = NSColor.clear.cgColor
    }

    required init?(coder: NSCoder) {
        nil
    }

    deinit {
        layer?.contents = nil
    }
}

struct LaunchpadBackgroundImageView: NSViewRepresentable {
    let image: CGImage?

    func makeNSView(context: Context) -> BackgroundImageLayerView {
        BackgroundImageLayerView(frame: .zero)
    }

    func updateNSView(_ nsView: BackgroundImageLayerView, context: Context) {
        CATransaction.begin()
        CATransaction.setDisableActions(true)
        nsView.layer?.contents = image
        CATransaction.commit()
    }

    static func dismantleNSView(_ nsView: BackgroundImageLayerView, coordinator: Void) {
        CATransaction.begin()
        CATransaction.setDisableActions(true)
        nsView.layer?.contents = nil
        CATransaction.commit()
    }
}
