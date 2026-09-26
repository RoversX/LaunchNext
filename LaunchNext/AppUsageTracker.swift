import AppKit
import Combine
import CoreServices

/// Remembers when each app was last opened, from any launcher, to drive the
/// Recently Used sort. Launches seen while LaunchNext runs are recorded
/// directly; Spotlight's last-used date fills in everything else.
///
/// Not observable on purpose: AppStore decides when new usage may reorder the
/// grid, so a launch elsewhere never re-renders LaunchNext.
final class AppUsageTracker {
    static let lastUsedDatesKey = "appLastUsedDates"
    private static let spotlightRefreshInterval: TimeInterval = 60

    private(set) var lastUsed: [String: Date]

    private let defaults: UserDefaults
    private var subscriptions: Set<AnyCancellable> = []
    private var usageKeys: [String: String] = [:]
    private var persistWorkItem: DispatchWorkItem?
    private var spotlightRefreshGeneration = 0
    private var lastSpotlightRefreshAt: Date?

    init(defaults: UserDefaults = .standard) {
        self.defaults = defaults
        let stored = defaults.dictionary(forKey: Self.lastUsedDatesKey) as? [String: Double] ?? [:]
        lastUsed = stored.mapValues { Date(timeIntervalSince1970: $0) }

        NSWorkspace.shared.notificationCenter
            .publisher(for: NSWorkspace.didLaunchApplicationNotification)
            .receive(on: RunLoop.main)
            .sink { [weak self] notification in
                // Helpers, agents and XPC services are not apps the user opened.
                guard let app = notification.userInfo?[NSWorkspace.applicationUserInfoKey] as? NSRunningApplication,
                      app.activationPolicy == .regular,
                      app.bundleIdentifier != Bundle.main.bundleIdentifier,
                      let url = app.bundleURL else { return }
                self?.recordUse(of: url)
            }
            .store(in: &subscriptions)
    }

    func recordUse(of url: URL, at date: Date = Date()) {
        let key = usageKey(for: url)
        if let existing = lastUsed[key], existing >= date { return }
        lastUsed[key] = date
        schedulePersist()
    }

    /// Merges Spotlight's last-used dates for `urls` (newer date wins), then calls
    /// `completion`. Skipped when the last refresh was under a minute ago unless
    /// `force` is set. Apps that are not passed in keep their history, since they
    /// may only be hidden or on a volume that is not mounted.
    func refreshSpotlightDates(for urls: [URL], force: Bool = false, completion: @escaping () -> Void) {
        if !force, let last = lastSpotlightRefreshAt,
           Date().timeIntervalSince(last) < Self.spotlightRefreshInterval { return }
        lastSpotlightRefreshAt = Date()
        spotlightRefreshGeneration += 1
        let generation = spotlightRefreshGeneration
        var keyedURLs: [String: URL] = [:]
        for url in urls { keyedURLs[usageKey(for: url)] = url }
        Task.detached(priority: .utility) {
            let spotlightDates = Self.spotlightLastUsedDates(for: keyedURLs)
            await MainActor.run { [weak self] in
                guard let self, generation == self.spotlightRefreshGeneration else { return }
                self.merge(spotlightDates)
                completion()
            }
        }
    }

    func usageKey(for url: URL) -> String {
        if let cached = usageKeys[url.path] { return cached }
        let key = AppSortOrder.usageKey(for: url)
        usageKeys[url.path] = key
        return key
    }

    private func merge(_ spotlightDates: [String: Date]) {
        var changed = false
        for (key, date) in spotlightDates where lastUsed[key].map({ $0 < date }) ?? true {
            lastUsed[key] = date
            changed = true
        }
        if changed { schedulePersist() }
    }

    private func schedulePersist() {
        persistWorkItem?.cancel()
        let work = DispatchWorkItem { [weak self] in
            guard let self else { return }
            self.defaults.set(self.lastUsed.mapValues(\.timeIntervalSince1970), forKey: Self.lastUsedDatesKey)
        }
        persistWorkItem = work
        DispatchQueue.main.asyncAfter(deadline: .now() + 1, execute: work)
    }

    nonisolated private static func spotlightLastUsedDates(for keyedURLs: [String: URL]) -> [String: Date] {
        var dates: [String: Date] = [:]
        for (key, url) in keyedURLs {
            guard let item = MDItemCreateWithURL(kCFAllocatorDefault, url as CFURL),
                  let date = MDItemCopyAttribute(item, kMDItemLastUsedDate) as? Date else { continue }
            dates[key] = date
        }
        return dates
    }
}
