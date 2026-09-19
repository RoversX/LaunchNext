import AppKit
import Combine

/// Observes desktop changes, never screen pixels. Kept alive for either system
/// wallpaper source, including while the launcher is hidden.
@MainActor
final class WallpaperContextMonitor {
    private var subscriptions: Set<AnyCancellable> = []
    private var suspendedReasons: Set<String> = []
    private var storeStamp: String?
    private var sourceStamp: String?
    private var sourceURL: URL?
    private let changed: (Bool) -> Void

    var isSuspended: Bool { !suspendedReasons.isEmpty }

    init(changed: @escaping (Bool) -> Void) {
        self.changed = changed
        storeStamp = Self.stamp(Self.storeURL)
        let workspace = NSWorkspace.shared.notificationCenter
        for (start, end, reason) in [
            (NSWorkspace.willSleepNotification, NSWorkspace.didWakeNotification, "sleep"),
            (NSWorkspace.screensDidSleepNotification, NSWorkspace.screensDidWakeNotification, "screens"),
            (NSWorkspace.sessionDidResignActiveNotification, NSWorkspace.sessionDidBecomeActiveNotification, "session")
        ] {
            observe(workspace, start, suspend: true, reason: reason)
            observe(workspace, end, suspend: false, reason: reason)
        }
        // Space changes are delivered by LaunchpadView, where the target screen
        // is known. Do not subscribe twice and restart the same capture twice.
        observe(NotificationCenter.default, NSApplication.didChangeScreenParametersNotification)
        observe(workspace, NSWorkspace.didLaunchApplicationNotification)
        observe(workspace, NSWorkspace.didTerminateApplicationNotification)
        let distributed = DistributedNotificationCenter.default()
        for (start, end, reason) in [
            ("com.apple.screenIsLocked", "com.apple.screenIsUnlocked", "lock"),
            ("com.apple.screensaver.didstart", "com.apple.screensaver.didstop", "saver")
        ] {
            observe(distributed, Notification.Name(start), suspend: true, reason: reason)
            observe(distributed, Notification.Name(end), suspend: false, reason: reason)
        }
        observe(distributed, Notification.Name("AppleInterfaceThemeChangedNotification"))
        observe(distributed, Notification.Name("com.apple.desktop"))
        // Only two stat calls, no image decoding, window enumeration or capture.
        // Check the current identity/context again before every cache reuse, so
        // a change between timer ticks is still detected when opening the app.
        Timer.publish(every: 2, tolerance: 0.5, on: .main, in: .common).autoconnect()
            .sink { [weak self] _ in self?.checkFiles() }
            .store(in: &subscriptions)
    }

    func watchSource(_ url: URL?) {
        guard sourceURL != url else { return }
        sourceURL = url
        sourceStamp = url.flatMap(Self.stamp)
    }

    private static var storeURL: URL {
        FileManager.default.homeDirectoryForCurrentUser.appendingPathComponent(
            "Library/Application Support/com.apple.wallpaper/Store/Index.plist")
    }

    private static func stamp(_ url: URL) -> String? {
        guard let attributes = try? FileManager.default.attributesOfItem(atPath: url.path) else { return nil }
        let modified = (attributes[.modificationDate] as? Date)?.timeIntervalSince1970 ?? 0
        return "\(modified):\(attributes[.size] ?? 0):\(attributes[.systemFileNumber] ?? 0)"
    }

    private func checkFiles() {
        let store = Self.stamp(Self.storeURL)
        let source = sourceURL.flatMap(Self.stamp)
        guard store != storeStamp || source != sourceStamp else { return }
        WallpaperDiagnostics.record("context.files storeChanged=\(store != storeStamp) sourceChanged=\(source != sourceStamp)")
        storeStamp = store
        sourceStamp = source
        // A store write may concern another display or historical Space. Let
        // the controller compare its display's context before invalidating.
        changed(false)
    }

    private func observe(_ center: NotificationCenter, _ name: Notification.Name,
                         suspend: Bool? = nil, reason: String = "") {
        center.publisher(for: name).receive(on: RunLoop.main)
            .sink { [weak self] notification in
                guard let self else { return }
                if name == NSWorkspace.didLaunchApplicationNotification || name == NSWorkspace.didTerminateApplicationNotification {
                    guard let app = notification.userInfo?[NSWorkspace.applicationUserInfoKey] as? NSRunningApplication,
                          ["com.apple.WindowManager", "com.apple.dock"].contains(app.bundleIdentifier ?? "") else { return }
                }
                if let suspend {
                    if suspend { self.suspendedReasons.insert(reason) }
                    else { self.suspendedReasons.remove(reason) }
                }
                WallpaperDiagnostics.record("context.notification name=\(name.rawValue) suspended=\(self.isSuspended)")
                // These notifications can describe another display/Space, or
                // repeat without changing wallpaper pixels. Validate the full
                // capture context instead of discarding every display's cache.
                let needsValidation = name == NSApplication.didChangeScreenParametersNotification
                    || name.rawValue == "com.apple.desktop"
                self.changed(!needsValidation)
            }
            .store(in: &subscriptions)
    }
}
