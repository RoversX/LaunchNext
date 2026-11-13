import AppKit
import Foundation
import SwiftData

// This file is a template consumed by test-application-reconciliation.py.
// The discovery runtime and AppStore's scanner, layout, placeholder, and
// persistence methods are compiled unchanged. Unrelated UI/icon/cache behavior
// is adapted; source metadata uses a disposable UserDefaults suite per fixture.
// INSERT_PRODUCTION_DISCOVERY
// INSERT_PRODUCTION_MODELS

// INSERT_PRODUCTION_APP_INFO

// INSERT_PRODUCTION_SEARCH

extension AppInfo {
    init(name: String, url: URL) { self.init(name: name, icon: NSImage(size: .zero), url: url) }
}

enum PerformanceMode {
    case full, lean
    static let current = Self.lean
}

struct FolderInfo {
    var id = UUID().uuidString
    var name: String
    var apps: [AppInfo]
    var pinnedAppPaths: [String] = []
    var createdAt = Date()
}

struct MissingAppPlaceholder {
    var bundlePath: String
    var displayName: String
    var removableSource: String?
    var icon: NSImage { NSImage(size: .zero) }
}

enum LaunchpadItem {
    case app(AppInfo), folder(FolderInfo), empty(String), missingApp(MissingAppPlaceholder)

    // Production identity, which AppStore.rebuildItems compares.
    var id: String {
        switch self {
        case .app(let app): return "app_\(app.id)"
        case .folder(let folder): return "folder_\(folder.id)"
        case .empty(let token): return "empty_\(token)"
        case .missingApp(let placeholder): return "missing_\(placeholder.bundlePath)"
        }
    }
}

final class FolderIconBitmapCache {
    static let shared = FolderIconBitmapCache()
    func clear() {}
}

final class CacheAdapter {
    var isCacheValid = false
    func clearAllCaches() {}
    func generateCache(from: [AppInfo], items: [LaunchpadItem], itemsPerPage: Int, columns: Int, rows: Int) {}
    func preloadIcons(for: [String]) {}
    func smartPreloadIcons(for: [LaunchpadItem], currentPage: Int, itemsPerPage: Int) {}
}

final class ProbeStore {
    var systemApplicationSearchPaths: [String] = []
    var customAppSourcePaths: [String] = []
    var apps: [AppInfo] = [] {
        didSet { inventoryObserver?(apps) }
    }
    var inventoryObserver: (([AppInfo]) -> Void)?
    var folders: [FolderInfo] = []
    // As in AppStore, the layout and the hidden inventory feed the search index.
    var items: [LaunchpadItem] = [] {
        didSet { refreshSearchIndex() }
    }
    var hiddenApplicationInventory: [AppInfo] = [] {
        didSet { refreshSearchIndex() }
    }
    var showHiddenAppsInSearch = false
    var fuzzySearchEnabled = true
    var searchText = ""
    var searchQuery = ""
    let searchEngine = LaunchpadSearchEngine()
    var isInitialLoading = true {
        didSet { loadingObserver?(isInitialLoading) }
    }
    var loadingObserver: ((Bool) -> Void)?
    var hasPerformedInitialScan = false
    var hasAppliedOrderFromStore = true
    private var applicationReconciliationReasons: Set<ApplicationReconciliationReason> = []
    var applicationReconciliationInProgress = false {
        didSet {
            if applicationReconciliationInProgress && !oldValue { reconciliationStartCount += 1 }
        }
    }
    private(set) var reconciliationStartCount = 0
    var applicationReconciliationWorkItem: DispatchWorkItem?
    var lastSuccessfulApplicationReconciliationAt: Date?
    var needsReconciliationAfterExternalUninstall = false
    // Retained so --app-store can still execute pre-index source snapshots.
    private var unavailableApplicationDirectories = Set<String>()
    private var retainedUnscannedApplicationPaths = Set<String>()
    private var applicationDiscoveryIndex: ApplicationDiscoveryIndex
    private var applicationScanSnapshot: ApplicationDiscoverySnapshot?
    private let applicationDiscoveryDefaults: UserDefaults
    private var applicationReconciliationGeneration = 0
    private var applicationReconciliationRetryCount = 0
    private var resetLayoutAfterApplicationScan = false
    static let applicationReconciliationEventDebounce: TimeInterval = 1.0
    static let applicationReconciliationRetryDelays: [TimeInterval] = [1, 3]
    // INSERT_PRODUCTION_FALLBACK_INTERVAL
    let cacheManager = CacheAdapter()
    var itemsPerPage = 6
    var gridColumnsPerPage = 3
    var gridRowsPerPage = 2
    var currentPage = 0
    var openFolder: FolderInfo?
    var hiddenAppPaths = Set<String>()
    var customTitles: [String: String] = [:]
    var missingPlaceholders: [String: MissingAppPlaceholder] = [:]
    var modelContext: ModelContext?

    init(discoveryDefaults: UserDefaults) {
        applicationDiscoveryDefaults = discoveryDefaults
        applicationDiscoveryIndex = ApplicationDiscoveryIndex.load(from: discoveryDefaults)
    }

    // Keep the real hidden-path update logic without writing user preferences.
    private func persistHiddenApps(_ paths: Set<String>) {}

    var beforeMetadataRead: ((URL) -> Void)?
    var afterMetadataRead: ((URL) -> Void)?
    func appInfo(from url: URL, preferredName: String? = nil, includeCustomTitle: Bool = true) -> AppInfo {
        beforeMetadataRead?(url)
        let info = // INSERT_METADATA_CALL
        afterMetadataRead?(url)
        return info
    }
    // Runs on the scan queue after each production validation result.
    var afterApplicationValidation: ((URL) -> Void)?
    func isValidApp(at url: URL) -> Bool {
        let valid = productionIsValidApp(at: url)
        afterApplicationValidation?(url)
        return valid
    }
    func scheduleCustomTitleCacheRefresh() {}
    func triggerFolderUpdate() {}
    func triggerGridRefresh() {}
    func rescan() { requestApplicationReconciliation(reason: .explicit) }
    func fileSystemEventRescan() { requestApplicationReconciliation(reason: .fileSystemEvent) }
    // The real volume handler runs; fixtures install no FSEvents stream.
    func restartAutoRescan() {}
    func volumeDidChange(at url: URL, mounted: Bool) { handleVolumeEvent(at: url, isMount: mounted) }
    func staleRescan() { requestApplicationReconciliation(reason: .staleWindowFallback) }
    func sourceConfigurationDidChange() {
        // INSERT_SOURCE_CHANGE_CALL
    }
    func applyImportedLayout() {
        // INSERT_IMPORT_CALL
    }
    func presentWindowForTesting() {
        // AppStore calls are extracted in order from the real show-window
        // method and its notification observer. The fixture already has apps.
        // INSERT_WINDOW_SHOW_CALLS
    }
    func makeSuccessfulScanStale() {
        lastSuccessfulApplicationReconciliationAt = Date().addingTimeInterval(-Self.applicationReconciliationFallbackInterval - 1)
    }
    func finishFailedInitialScan() {
        applicationReconciliationInProgress = true
        finishApplicationReconciliation(reasons: [.initial], succeeded: false)
    }
    /// The hidden-app steps of AppStore.reloadPreferencesFromDefaults after a
    /// preference import: load the imported set, then prune the app list.
    func reloadImportedHiddenApps(_ paths: Set<String>) {
        hiddenAppPaths = paths
        pruneHiddenAppsFromAppList()
    }
    /// Types a query as the search field does, with the debounce already applied.
    func search(_ text: String) -> [LaunchpadItem] {
        searchText = text
        searchQuery = text
        return filteredItems
    }

    // LaunchpadView's search results, with its `appStore.` receiver removed.
    // INSERT_VIEW_FILTERED_ITEMS

    // INSERT_SEARCH_FALLBACKS

    // INSERT_SOURCE_LISTING_FALLBACK

    // INSERT_PRODUCTION_METHODS
}

struct TestFailure: Error, CustomStringConvertible {
    var description: String
}

struct TestSkip: Error, CustomStringConvertible {
    var description: String
}

func expect(_ condition: @autoclosure () -> Bool, _ message: String) throws {
    if !condition() { throw TestFailure(description: message) }
}

func finishScan(_ store: ProbeStore) throws {
    let deadline = Date().addingTimeInterval(15)
    while store.applicationReconciliationInProgress && Date() < deadline {
        _ = RunLoop.main.run(mode: .default, before: Date().addingTimeInterval(0.01))
    }
    try expect(!store.applicationReconciliationInProgress, "scan did not finish within 15 seconds")
    try expect(!store.isInitialLoading, "finished scan left the initial loading screen active")
}

struct SavedSlot: Equatable {
    var page: Int
    var position: Int
    var kind: String
    var app: String?
    var folderID: String?
    var folderName: String?
    var folderApps: [String]
    var pins: [String]
}

func savedLayout(_ store: ProbeStore) throws -> [SavedSlot] {
    let rows = try store.modelContext!.fetch(FetchDescriptor<PageEntryData>(
        sortBy: [SortDescriptor(\.pageIndex), SortDescriptor(\.position)]
    ))
    return rows.map {
        // A missing-app placeholder may change presentation while retaining the
        // same application and position; it must not remove the user's layout.
        SavedSlot(page: $0.pageIndex, position: $0.position,
                  kind: $0.kind == "missing" ? "app" : $0.kind,
                  app: $0.appPath, folderID: $0.folderId, folderName: $0.folderName,
                  folderApps: $0.appPaths, pins: $0.pinnedAppPaths ?? [])
    }
}

final class Fixture {
    let directory: URL
    let source: URL
    let restricted: URL
    let container: ModelContainer
    let customSource: Bool
    let defaultsSuiteName: String
    let discoveryDefaults: UserDefaults
    let fileManager = FileManager.default
    var originalLayout: [SavedSlot] = []
    var reportedUnavailablePaths: [String] = []

    init(root: URL, name: String, customSource: Bool = false) throws {
        directory = root.appendingPathComponent(name)
        source = directory.appendingPathComponent("Applications")
        restricted = source.appendingPathComponent("Restricted")
        self.customSource = customSource
        defaultsSuiteName = "test.launchnext.reconciliation." + UUID().uuidString
        discoveryDefaults = UserDefaults(suiteName: defaultsSuiteName)!
        let schema = Schema([PageEntryData.self, TopItemData.self])
        container = try ModelContainer(for: schema, configurations: [
            ModelConfiguration(schema: schema, isStoredInMemoryOnly: true)
        ])
        try createApp(source.appendingPathComponent("Visible.app"))
        try createApp(restricted.appendingPathComponent("SavedTop.app"))
        try createApp(restricted.appendingPathComponent("SavedFolder.app"))
    }

    func createApp(_ url: URL) throws {
        try fileManager.createDirectory(at: url.appendingPathComponent("Contents/MacOS"), withIntermediateDirectories: true)
        let plist: [String: Any] = [
            "CFBundleIdentifier": "test.reconciliation." + url.deletingPathExtension().lastPathComponent,
            "CFBundleName": url.deletingPathExtension().lastPathComponent,
            "CFBundlePackageType": "APPL"
        ]
        try PropertyListSerialization.data(fromPropertyList: plist, format: .xml, options: 0)
            .write(to: url.appendingPathComponent("Contents/Info.plist"))
    }

    func store(restarting: Bool = false) -> ProbeStore {
        // A restart reloads production-encoded metadata from this fixture's
        // private suite, rather than copying another store's in-memory index.
        let store = ProbeStore(discoveryDefaults: discoveryDefaults)
        store.modelContext = ModelContext(container)
        store.hasAppliedOrderFromStore = !restarting
        if customSource {
            store.customAppSourcePaths = [source.path]
        } else {
            store.systemApplicationSearchPaths = [source.path]
        }
        return store
    }

    func seedLayout() throws -> ProbeStore {
        let store = store()
        store.performInitialScanIfNeeded()
        try finishScan(store)
        try expect(store.apps.count == 3, "readable control must discover all three application bundles")
        guard let top = store.apps.first(where: { $0.name == "SavedTop" }),
              let member = store.apps.first(where: { $0.name == "SavedFolder" }),
              let visible = store.apps.first(where: { $0.name == "Visible" }) else {
            throw TestFailure(description: "readable scan returned unexpected fixture applications")
        }
        let folder = FolderInfo(name: "Saved Folder", apps: [member], pinnedAppPaths: [member.url.path])
        // AppStore.createFolder removes members from the top-level apps list.
        store.apps.removeAll { $0.url == member.url }
        store.folders = [folder]
        store.items = [.app(visible), .folder(folder), .app(top)]
        store.saveAllOrder()
        originalLayout = try savedLayout(store)
        try expect(originalLayout.count == 3, "seeded layout must have three persisted slots")
        return store
    }

    func denySubdirectory() throws {
        try fileManager.setAttributes([.posixPermissions: 0o000], ofItemAtPath: restricted.path)
        try expect(!fileManager.isReadableFile(atPath: restricted.path), "chmod fixture is still readable")
        try expect(!fileManager.fileExists(atPath: restricted.appendingPathComponent("SavedTop.app").path),
                   "chmod fixture must make child stat fail")
        var sawPermissionError = false
        if let entries = fileManager.enumerator(at: source, includingPropertiesForKeys: [.isDirectoryKey],
            options: [.skipsHiddenFiles, .skipsPackageDescendants], errorHandler: { url, error in
                let error = error as NSError
                if error.domain == NSCocoaErrorDomain && error.code == NSFileReadNoPermissionError {
                    sawPermissionError = true
                    self.reportedUnavailablePaths.append(url.path)
                }
                return true
            }) {
            for _ in entries {}
        }
        try expect(sawPermissionError, "fixture did not produce a real FileManager permission error")
    }

    func restorePermissions() {
        try? fileManager.setAttributes([.posixPermissions: 0o700], ofItemAtPath: source.path)
        try? fileManager.setAttributes([.posixPermissions: 0o700], ofItemAtPath: restricted.path)
        try? fileManager.setAttributes([.posixPermissions: 0o700],
                                       ofItemAtPath: directory.appendingPathComponent("ExternalTargets").path)
    }

    deinit {
        restorePermissions()
        discoveryDefaults.removePersistentDomain(forName: defaultsSuiteName)
        try? fileManager.removeItem(at: directory)
    }
}

func testColdUnreadableSource(_ root: URL) throws {
    let fixture = try Fixture(root: root, name: "cold-unreadable")
    defer { fixture.restorePermissions() }
    try fixture.denySubdirectory()
    let store = fixture.store()
    store.performInitialScanIfNeeded()
    try finishScan(store)
    try expect(store.apps.map(\.name) == ["Visible"], "unreadable subtree prevented accessible apps from loading")
}

func testPreservedLayout(_ root: URL, custom: Bool) throws {
    let fixture = try Fixture(root: root, name: custom ? "custom-layout" : "builtin-layout", customSource: custom)
    defer { fixture.restorePermissions() }
    let store = try fixture.seedLayout()
    try fixture.denySubdirectory()
    store.rescan()
    try finishScan(store)
    let unavailableLayout = try savedLayout(store)
    try expect(unavailableLayout == fixture.originalLayout, "permission failure changed saved positions, folder members, or pins")

    fixture.restorePermissions()
    store.staleRescan()
    try finishScan(store)
    let restoredLayout = try savedLayout(store)
    try expect(restoredLayout == fixture.originalLayout, "stale-window recovery changed the saved layout")
    try expect(!store.items.contains { if case .missingApp = $0 { return true }; return false },
               "stale-window recovery left a missing placeholder for an accessible application")
}

func testRestartWhileUnreadable(_ root: URL) throws {
    let fixture = try Fixture(root: root, name: "restart-unreadable")
    defer { fixture.restorePermissions() }
    _ = try fixture.seedLayout()
    try fixture.denySubdirectory()
    let restarted = fixture.store(restarting: true)
    restarted.performInitialScanIfNeeded()
    try finishScan(restarted)
    let restartedLayout = try savedLayout(restarted)
    try expect(restartedLayout == fixture.originalLayout, "startup while unreadable erased persisted layout data")
    fixture.restorePermissions()
    restarted.staleRescan()
    try finishScan(restarted)
    let recoveredLayout = try savedLayout(restarted)
    try expect(recoveredLayout == fixture.originalLayout, "startup recovery did not preserve folder membership and positions")
    try expect(!restarted.items.contains { if case .missingApp = $0 { return true }; return false },
               "startup recovery left a missing placeholder for an accessible application")
}

func testLegacyRestartWhileUnreadable(_ root: URL) throws {
    let fixture = try Fixture(root: root, name: "legacy-restart-unreadable")
    defer { fixture.restorePermissions() }
    let original = try fixture.seedLayout()
    let context = original.modelContext!
    for row in try context.fetch(FetchDescriptor<PageEntryData>()) { context.delete(row) }
    for slot in fixture.originalLayout {
        if let path = slot.app {
            context.insert(TopItemData(appPath: path, orderIndex: slot.position))
        } else if let id = slot.folderID {
            context.insert(TopItemData(folderId: id, folderName: slot.folderName!,
                                       appPaths: slot.folderApps, orderIndex: slot.position))
        }
    }
    try context.save()
    try fixture.denySubdirectory()
    let restarted = fixture.store(restarting: true)
    restarted.performInitialScanIfNeeded()
    try finishScan(restarted)
    // Legacy TopItemData has no pin field; all other user-visible layout
    // information must survive migration while the source is unreadable.
    let expected = fixture.originalLayout.map { slot -> SavedSlot in
        var slot = slot
        slot.pins = []
        return slot
    }
    let rows = try savedLayout(restarted)
    try expect(rows == expected, "legacy startup discarded inaccessible applications or folder membership")
    fixture.restorePermissions()
    restarted.staleRescan()
    try finishScan(restarted)
    let recovered = try savedLayout(restarted)
    try expect(recovered == expected, "legacy startup recovery changed migrated positions or folders")
}

func testReportedPathAliases(_ root: URL) throws {
    let fixture = try Fixture(root: root, name: "reported-path-aliases")
    defer { fixture.restorePermissions() }
    let store = try fixture.seedLayout()
    let top = store.apps.first { $0.name == "SavedTop" }!
    let parent = top.url.deletingLastPathComponent()
    try fixture.denySubdirectory()
    // On macOS, error URLs under the temp directory commonly use /private/var
    // while resolvingSymlinksInPath() on scanned apps returns /var. Prove this
    // runtime exercises distinct spellings for the same actual directory.
    let hasDifferentSpelling = fixture.reportedUnavailablePaths.contains {
        $0 != parent.path && URL(fileURLWithPath: $0).resolvingSymlinksInPath() == parent.resolvingSymlinksInPath()
    }
    guard hasDifferentSpelling else {
        throw TestSkip(description: "Foundation returned identical error and app path spellings on this runtime")
    }
    store.rescan()
    try finishScan(store)
    try expect(store.apps.contains { $0.url == top.url }, "alternate error URL spelling removed an existing app from inventory")
    let rows = try savedLayout(store)
    try expect(rows == fixture.originalLayout, "alternate error URL spelling changed the persisted layout")
}

func testActualRemoval(_ root: URL) throws {
    let fixture = try Fixture(root: root, name: "real-removal")
    defer { fixture.restorePermissions() }
    let store = try fixture.seedLayout()
    try fixture.denySubdirectory()
    store.rescan()
    try finishScan(store)
    fixture.restorePermissions()
    try fixture.fileManager.removeItem(at: fixture.restricted)
    store.rescan()
    try finishScan(store)
    let rows = try savedLayout(store)
    let remaining = rows.compactMap(\.app) + rows.flatMap(\.folderApps) + rows.flatMap(\.pins)
    try expect(!remaining.contains { $0.contains("SavedTop.app") || $0.contains("SavedFolder.app") },
               "previously unavailable paths hid a real removal after access recovered")
}

func testUnavailableCustomRoot(_ root: URL) throws {
    let fixture = try Fixture(root: root, name: "unavailable-root", customSource: true)
    defer { fixture.restorePermissions() }
    let store = try fixture.seedLayout()
    try fixture.fileManager.setAttributes([.posixPermissions: 0o000], ofItemAtPath: fixture.source.path)
    store.rescan()
    try finishScan(store)
    let rows = try savedLayout(store)
    try expect(rows == fixture.originalLayout, "unavailable custom root changed its saved inventory")
}

func testFailedInitialCompletion(_ root: URL) throws {
    let fixture = try Fixture(root: root, name: "failed-completion")
    let store = fixture.store()
    store.finishFailedInitialScan()
    try expect(!store.isInitialLoading && !store.applicationReconciliationInProgress,
               "failed initial scan did not clear loading and single-flight state")
    try expect(store.lastSuccessfulApplicationReconciliationAt == nil, "failed scan recorded a successful timestamp")
    let rows = try savedLayout(store)
    try expect(rows.isEmpty, "failed completion wrote a replacement inventory")
}

func testFolderMetadataAfterFailedInitialScan(_ root: URL) throws {
    let fixture = try Fixture(root: root, name: "failed-initial-folder-recovery")
    defer { fixture.restorePermissions() }
    let original = fixture.store()
    original.performInitialScanIfNeeded()
    try finishScan(original)
    let names = Set(original.apps.map(\.name))
    let folder = FolderInfo(name: "All Apps", apps: original.apps,
                            pinnedAppPaths: original.apps.map { $0.url.path })
    original.folders = [folder]
    original.items = [.folder(folder)]
    original.apps = []
    original.saveAllOrder()
    let layout = try savedLayout(original)

    try fixture.denySubdirectory()
    let restarted = fixture.store(restarting: true)
    restarted.loadAllOrder()
    let deadline = Date().addingTimeInterval(15)
    while !restarted.hasAppliedOrderFromStore && Date() < deadline {
        _ = RunLoop.main.run(mode: .default, before: Date().addingTimeInterval(0.01))
    }
    try expect(restarted.hasAppliedOrderFromStore, "persisted layout did not finish loading")
    try expect(restarted.apps.isEmpty, "folder-only layout unexpectedly loaded top-level applications")
    // A root scan failure finishes before any successful availability snapshot.
    // Simulate that deterministic completion rather than a timing-dependent race.
    restarted.finishFailedInitialScan()
    fixture.restorePermissions()
    restarted.staleRescan()
    try finishScan(restarted)
    try expect(Set(restarted.folders.flatMap(\.apps).map(\.name)) == names,
               "first successful stale scan kept folder placeholder metadata after permissions recovered")
    let recoveredLayout = try savedLayout(restarted)
    try expect(recoveredLayout == layout, "first successful stale scan changed the folder-only layout")
}

func seedExternalApplicationLinks(_ fixture: Fixture) throws -> ProbeStore {
    let targets = fixture.directory.appendingPathComponent("ExternalTargets")
    for name in ["LinkedTop", "LinkedFolder"] {
        let target = targets.appendingPathComponent(name + ".app")
        try fixture.createApp(target)
        try fixture.fileManager.createSymbolicLink(
            at: fixture.restricted.appendingPathComponent(name + ".app"), withDestinationURL: target
        )
    }
    let store = fixture.store()
    store.performInitialScanIfNeeded()
    try finishScan(store)
    guard let linkedTop = store.apps.first(where: { $0.name == "LinkedTop" }),
          let linkedFolder = store.apps.first(where: { $0.name == "LinkedFolder" }),
          let savedTop = store.apps.first(where: { $0.name == "SavedTop" }),
          let savedFolder = store.apps.first(where: { $0.name == "SavedFolder" }),
          let visible = store.apps.first(where: { $0.name == "Visible" }) else {
        throw TestFailure(description: "readable control did not discover application symlinks")
    }
    for linked in [linkedTop, linkedFolder] {
        try expect(linked.url.path.hasPrefix(targets.resolvingSymlinksInPath().path + "/"),
                   "scanner must store the external target rather than the source symlink path")
        try expect(!linked.url.path.hasPrefix(fixture.source.resolvingSymlinksInPath().path + "/"),
                   "symlink fixture target must be outside configured application roots")
    }
    let folder = FolderInfo(name: "Mixed Folder", apps: [linkedFolder, savedFolder],
                            pinnedAppPaths: [linkedFolder.url.path])
    store.apps = [linkedTop, visible, savedTop]
    store.folders = [folder]
    store.items = [.app(linkedTop), .folder(folder), .app(visible), .app(savedTop)]
    store.saveAllOrder()
    fixture.originalLayout = try savedLayout(store)
    return store
}

func testExternalLinksWhileUnreadable(_ root: URL, restart: Bool) throws {
    let fixture = try Fixture(root: root, name: restart ? "external-links-restart" : "external-links-running")
    defer { fixture.restorePermissions() }
    let original = try seedExternalApplicationLinks(fixture)
    try fixture.denySubdirectory()
    let newApp = fixture.source.appendingPathComponent("NewAccessible.app")
    try fixture.createApp(newApp)
    for name in ["LinkedTop", "LinkedFolder"] {
        try expect(fixture.fileManager.fileExists(atPath: fixture.directory.appendingPathComponent("ExternalTargets/" + name + ".app").path),
                   "external target must remain readable when its source symlink is inaccessible")
    }
    let store = restart ? fixture.store(restarting: true) : original
    if restart {
        store.performInitialScanIfNeeded()
    } else {
        store.rescan()
    }
    try finishScan(store)
    let unavailable = try savedLayout(store)
    try expect(Array(unavailable.prefix(fixture.originalLayout.count)) == fixture.originalLayout,
               "unreadable symlink directory changed saved positions, folder members, or pins")
    try expect(store.apps.contains { $0.name == "NewAccessible" },
               "preserving unresolved symlink provenance blocked discovery of accessible new applications")
    try expect(unavailable.contains { $0.app?.hasSuffix("/NewAccessible.app") == true },
               "accessible new application was discovered but not added to the saved layout")
    try expect(store.apps.contains { $0.name == "LinkedTop" },
               "unreadable symlink directory removed the existing external target from inventory")

    fixture.restorePermissions()
    store.staleRescan()
    try finishScan(store)
    let recovered = try savedLayout(store)
    try expect(recovered == unavailable, "readable recovery moved linked applications or changed folder membership")
    try expect(!store.items.contains { if case .missingApp = $0 { return true }; return false },
               "readable recovery left a missing placeholder for a valid application link")
    try removeExternalLinksAndRescan(fixture, store: store)
}

func removeExternalLinksAndRescan(_ fixture: Fixture, store: ProbeStore) throws {
    for name in ["LinkedTop", "LinkedFolder"] {
        try fixture.fileManager.removeItem(at: fixture.restricted.appendingPathComponent(name + ".app"))
        try expect(fixture.fileManager.fileExists(atPath: fixture.directory.appendingPathComponent("ExternalTargets/" + name + ".app").path),
                   "unlink fixture must retain the real app outside every configured source")
    }
    store.rescan()
    try finishScan(store)
    let rows = try savedLayout(store)
    let retainedPaths = rows.compactMap(\.app) + rows.flatMap(\.folderApps) + rows.flatMap(\.pins)
    try expect(!retainedPaths.contains { $0.hasSuffix("/LinkedTop.app") || $0.hasSuffix("/LinkedFolder.app") },
               "complete readable scan retained applications whose source links were removed")
    try expect(!store.apps.contains { $0.name == "LinkedTop" || $0.name == "LinkedFolder" },
               "complete readable scan retained unlinked external applications in inventory")
    try expect(store.folders.first?.apps.map(\.name) == ["SavedFolder"],
               "link removal changed the unrelated folder member")
}

func testExternalLinkRemovalAfterCompleteScan(_ root: URL) throws {
    let fixture = try Fixture(root: root, name: "external-links-removed")
    defer { fixture.restorePermissions() }
    let store = try seedExternalApplicationLinks(fixture)
    try removeExternalLinksAndRescan(fixture, store: store)
}

func testReadableRemovalDuringPartialScan(_ root: URL) throws {
    let fixture = try Fixture(root: root, name: "readable-removal-during-partial-scan")
    defer { fixture.restorePermissions() }
    let store = try fixture.seedLayout()
    let originalFolder = fixture.originalLayout.first { $0.kind == "folder" }!
    try fixture.denySubdirectory()
    try fixture.fileManager.removeItem(at: fixture.source.appendingPathComponent("Visible.app"))
    store.rescan()
    try finishScan(store)
    let rows = try savedLayout(store)
    let paths = rows.compactMap(\.app) + rows.flatMap(\.folderApps)
    try expect(!paths.contains { $0.hasSuffix("/Visible.app") },
               "an unrelated unreadable subtree prevented cleanup of a deleted readable application")
    try expect(!store.apps.contains { $0.name == "Visible" },
               "partial scan retained a definitely deleted application in inventory")
    try expect(paths.contains { $0.hasSuffix("/SavedTop.app") },
               "deleting the readable app discarded the unrelated inaccessible app")
    guard let folder = rows.first(where: { $0.kind == "folder" }) else {
        throw TestFailure(description: "partial scan removed the unrelated saved folder")
    }
    try expect(folder.folderID == originalFolder.folderID && folder.folderApps == originalFolder.folderApps
               && folder.pins == originalFolder.pins,
               "partial scan removal changed the unrelated folder's members or pins")
}

func testLoadedItemOutsideAppInventory(_ root: URL) throws {
    let fixture = try Fixture(root: root, name: "loaded-item-outside-inventory")
    defer { fixture.restorePermissions() }
    let original = try seedExternalApplicationLinks(fixture)
    let store = fixture.store(restarting: true)
    store.apps = original.apps.filter { $0.name == "Visible" }
    try expect(!store.apps.isEmpty, "layout-load control requires an already populated application list")
    // This is the real import/load branch: loadOrderFromPageEntries only fills
    // apps from persisted top-level items when apps was initially empty.
    store.loadAllOrder()
    let deadline = Date().addingTimeInterval(15)
    while !store.hasAppliedOrderFromStore && Date() < deadline {
        _ = RunLoop.main.run(mode: .default, before: Date().addingTimeInterval(0.01))
    }
    try expect(store.hasAppliedOrderFromStore, "persisted imported layout did not finish loading")
    try expect(store.items.contains { if case .app(let app) = $0 { return app.name == "LinkedTop" }; return false },
               "persisted load did not reconstruct the top-level external application")
    try expect(!store.apps.contains { $0.name == "LinkedTop" },
               "test did not exercise the nonempty-apps branch of loadOrderFromPageEntries")

    try fixture.denySubdirectory()
    store.rescan()
    try finishScan(store)
    let rows = try savedLayout(store)
    try expect(rows == fixture.originalLayout,
               "partial scan discarded an imported top-level application present only in items")
    fixture.restorePermissions()
    store.staleRescan()
    try finishScan(store)
    let recovered = try savedLayout(store)
    try expect(recovered == fixture.originalLayout, "recovery changed the imported application layout")
}

func testInaccessibleExternalTargets(_ root: URL, restart: Bool) throws {
    let fixture = try Fixture(root: root, name: restart ? "inaccessible-targets-restart" : "inaccessible-targets-running")
    defer { fixture.restorePermissions() }
    let original = try seedExternalApplicationLinks(fixture)
    try fixture.denySubdirectory()
    let externalDirectory = fixture.directory.appendingPathComponent("ExternalTargets")
    try fixture.fileManager.setAttributes([.posixPermissions: 0o000], ofItemAtPath: externalDirectory.path)
    try expect(!fixture.fileManager.isReadableFile(atPath: externalDirectory.path),
               "external target directory is still readable")
    for name in ["LinkedTop", "LinkedFolder"] {
        var permissionDenied = false
        do {
            _ = try fixture.fileManager.attributesOfItem(atPath: externalDirectory.appendingPathComponent(name + ".app").path)
        } catch {
            let error = error as NSError
            permissionDenied = error.domain == NSCocoaErrorDomain && error.code == NSFileReadNoPermissionError
        }
        try expect(permissionDenied, "external target stat did not produce a real permission error")
    }
    let store = restart ? fixture.store(restarting: true) : original
    if restart {
        store.performInitialScanIfNeeded()
    } else {
        store.rescan()
    }
    try finishScan(store)
    let inaccessible = try savedLayout(store)
    try expect(inaccessible == fixture.originalLayout,
               "source and target permission errors discarded saved linked applications or folder pins")
    fixture.restorePermissions()
    store.staleRescan()
    try finishScan(store)
    let recovered = try savedLayout(store)
    try expect(recovered == fixture.originalLayout, "restoring both directory permissions changed saved layout")
    try expect(!store.items.contains { if case .missingApp = $0 { return true }; return false },
               "restoring external target access left a missing application placeholder")
    try expect(store.folders.first?.apps.map(\.name) == ["LinkedFolder", "SavedFolder"],
               "restoring external target access did not refresh folder metadata")

    // Permission failures are ambiguous; ENOENT is not. Retaining an inaccessible
    // target must not hide its genuine deletion during a later partial scan.
    try fixture.denySubdirectory()
    for name in ["LinkedTop", "LinkedFolder"] {
        try fixture.fileManager.removeItem(at: externalDirectory.appendingPathComponent(name + ".app"))
    }
    store.rescan()
    try finishScan(store)
    let afterDeletion = try savedLayout(store)
    let paths = afterDeletion.compactMap(\.app) + afterDeletion.flatMap(\.folderApps) + afterDeletion.flatMap(\.pins)
    try expect(!paths.contains { $0.hasSuffix("/LinkedTop.app") || $0.hasSuffix("/LinkedFolder.app") },
               "old permission-error protection retained an external target that was actually deleted")
}

func persistedApplicationPaths(_ rows: [SavedSlot]) -> [String] {
    rows.compactMap(\.app) + rows.flatMap(\.folderApps) + rows.flatMap(\.pins)
}

func testDeletedLinkDuringUnrelatedPartialScan(_ root: URL, offlineSource: Bool, openWindow: Bool = false) throws {
    let name = offlineSource ? "deleted-link-offline-source" : "deleted-link-unreadable-subtree"
    let fixture = try Fixture(root: root, name: name + (openWindow ? "-window-shown" : ""))
    defer { fixture.restorePermissions() }
    let target = fixture.directory.appendingPathComponent("ExternalTargets/External.app")
    try fixture.createApp(target)
    let link = fixture.source.appendingPathComponent("External.app")
    try fixture.fileManager.createSymbolicLink(at: link, withDestinationURL: target)
    let store = fixture.store()
    if offlineSource {
        store.customAppSourcePaths = [fixture.directory.appendingPathComponent("NotMounted/Apps").path]
    }
    store.performInitialScanIfNeeded()
    try finishScan(store)
    try expect(store.apps.contains { $0.name == "External" }, "readable control did not discover the external link")
    if !offlineSource { try fixture.denySubdirectory() }
    if openWindow {
        store.presentWindowForTesting()
        try finishScan(store)
    }
    try fixture.fileManager.removeItem(at: link)
    try expect(fixture.fileManager.fileExists(atPath: target.path), "unlink must leave the external app intact")
    // Repeated partial scans must not indefinitely protect a link whose own
    // source remained readable and reported its removal.
    for _ in 0..<2 {
        store.rescan()
        try finishScan(store)
    }
    let rows = try savedLayout(store)
    try expect(!store.apps.contains { $0.name == "External" },
               "unrelated unavailable source retained a deleted readable application link")
    try expect(!persistedApplicationPaths(rows).contains { $0.hasSuffix("/External.app") },
               "deleted readable link remained in the saved layout")
    try expect(store.apps.contains { $0.name == "SavedTop" },
               "removing a readable link discarded an unrelated existing application")
}

func testRemoveOrdinarySourceDuringPartialScan(_ root: URL, offlineSource: Bool) throws {
    let fixture = try Fixture(root: root, name: offlineSource ? "remove-ordinary-offline-source" : "remove-ordinary-unreadable-subtree")
    defer { fixture.restorePermissions() }
    let custom = fixture.directory.appendingPathComponent("RemovableB")
    try fixture.createApp(custom.appendingPathComponent("FromB.app"))
    let offline = fixture.directory.appendingPathComponent("NotMounted/Apps").path
    let store = fixture.store()
    store.customAppSourcePaths = offlineSource ? [offline, custom.path] : [custom.path]
    store.performInitialScanIfNeeded()
    try finishScan(store)
    guard let app = store.apps.first(where: { $0.name == "FromB" }) else {
        throw TestFailure(description: "ordinary source control did not discover FromB")
    }
    // Foundation may return /tmp for a configured /private/tmp path. Match the
    // inventory spelling here to isolate ordinary source removal from aliases.
    let sourcePath = app.url.deletingLastPathComponent().path
    store.customAppSourcePaths = offlineSource ? [offline, sourcePath] : [sourcePath]
    if !offlineSource {
        try fixture.denySubdirectory()
        store.rescan()
        try finishScan(store)
    }
    store.removeCustomAppSource(path: sourcePath)
    try expect(!store.apps.contains { $0.name == "FromB" },
               "real source removal API did not immediately remove its ordinary application")
    store.rescan()
    try finishScan(store)
    let rows = try savedLayout(store)
    try expect(!store.apps.contains { $0.name == "FromB" }
               && !persistedApplicationPaths(rows).contains { $0.hasSuffix("/FromB.app") },
               "partial reconciliation restored an application from a removed ordinary source")
}

func testRemoveLinkedSourceWithOfflineRoot(_ root: URL, openWindow: Bool = false) throws {
    let fixture = try Fixture(root: root, name: "remove-linked-source-offline-root" + (openWindow ? "-window-shown" : ""))
    defer { fixture.restorePermissions() }
    let custom = fixture.directory.appendingPathComponent("RemovableB")
    try fixture.fileManager.createDirectory(at: custom, withIntermediateDirectories: true)
    let target = fixture.directory.appendingPathComponent("ExternalTargets/FromBLink.app")
    try fixture.createApp(target)
    try fixture.fileManager.createSymbolicLink(at: custom.appendingPathComponent("FromBLink.app"), withDestinationURL: target)
    let store = fixture.store()
    store.customAppSourcePaths = [fixture.directory.appendingPathComponent("NotMounted/Apps").path, custom.path]
    store.performInitialScanIfNeeded()
    try finishScan(store)
    try expect(store.apps.contains { $0.name == "FromBLink" }, "linked source control did not discover its target")
    if openWindow {
        store.presentWindowForTesting()
        try finishScan(store)
    }
    store.removeCustomAppSource(path: custom.path)
    let immediate = try savedLayout(store)
    try expect(!store.apps.contains { $0.name == "FromBLink" }
               && !persistedApplicationPaths(immediate).contains { $0.hasSuffix("/FromBLink.app") },
               "removing a linked source did not immediately remove its external application")
    for _ in 0..<2 {
        store.rescan()
        try finishScan(store)
    }
    let rows = try savedLayout(store)
    try expect(!store.customAppSourcePaths.contains(custom.path), "real source removal API did not remove its configuration")
    try expect(!store.apps.contains { $0.name == "FromBLink" }
               && !persistedApplicationPaths(rows).contains { $0.hasSuffix("/FromBLink.app") },
               "offline root protected an external target after its actual source was removed")
}

func testDiscoveryOriginsSurviveRestart(_ root: URL, removeSource: Bool) throws {
    let fixture = try Fixture(root: root, name: removeSource ? "restart-remove-linked-source" : "restart-unlink-recorded-origin")
    defer { fixture.restorePermissions() }
    let source = fixture.directory.appendingPathComponent("CustomLinks")
    try fixture.fileManager.createDirectory(at: source, withIntermediateDirectories: true)
    let target = fixture.directory.appendingPathComponent("ExternalTargets/Recorded.app")
    try fixture.createApp(target)
    let link = source.appendingPathComponent("Recorded.app")
    try fixture.fileManager.createSymbolicLink(at: link, withDestinationURL: target)
    let configuredSources = [source.path, fixture.directory.appendingPathComponent("NotMounted/Apps").path]
    let original = fixture.store()
    original.customAppSourcePaths = configuredSources
    original.performInitialScanIfNeeded()
    try finishScan(original)
    try expect(original.apps.contains { $0.name == "Recorded" }, "restart control did not discover its linked application")
    let persistedIndex = ApplicationDiscoveryIndex.load(from: fixture.discoveryDefaults)
    let origins = persistedIndex.originsByTarget.first { $0.key.hasSuffix("/Recorded.app") }?.value
    try expect(origins?.contains { $0.entryPath.hasSuffix("/CustomLinks/Recorded.app") } == true,
               "successful scan did not persist the actual source entry for restart")

    if !removeSource { try fixture.fileManager.removeItem(at: link) }
    let restarted = fixture.store(restarting: true)
    restarted.customAppSourcePaths = configuredSources
    if removeSource {
        // Load the saved layout before the first scan: the removal must use
        // genuinely persisted origins, without a fresh scan repopulating them.
        restarted.loadAllOrder()
        let deadline = Date().addingTimeInterval(15)
        while !restarted.hasAppliedOrderFromStore && Date() < deadline {
            _ = RunLoop.main.run(mode: .default, before: Date().addingTimeInterval(0.01))
        }
        try expect(restarted.hasAppliedOrderFromStore, "restart did not finish loading the saved layout")
        try expect(restarted.apps.contains { $0.name == "Recorded" }, "restart did not reconstruct the linked application")
        restarted.removeCustomAppSource(path: source.path)
        let immediate = try savedLayout(restarted)
        try expect(!restarted.apps.contains { $0.name == "Recorded" }
                   && !persistedApplicationPaths(immediate).contains { $0.hasSuffix("/Recorded.app") },
                   "source removal before the first scan ignored persisted discovery origins")
    }
    restarted.performInitialScanIfNeeded()
    try finishScan(restarted)
    restarted.rescan()
    try finishScan(restarted)
    let rows = try savedLayout(restarted)
    try expect(!restarted.apps.contains { $0.name == "Recorded" }
               && !persistedApplicationPaths(rows).contains { $0.hasSuffix("/Recorded.app") },
               "restart forgot the real source and retained an orphaned external target")
}

func testSourceRemovalInvalidatesInFlightScan(_ root: URL) throws {
    let fixture = try Fixture(root: root, name: "in-flight-source-removal")
    defer { fixture.restorePermissions() }
    let custom = fixture.directory.appendingPathComponent("CustomSource")
    try fixture.createApp(custom.appendingPathComponent("InFlight.app"))
    let store = fixture.store()
    store.customAppSourcePaths = [custom.path]
    store.performInitialScanIfNeeded()
    try finishScan(store)
    try expect(store.apps.contains { $0.name == "InFlight" }, "in-flight control did not discover its application")
    store.rescan()
    try expect(store.applicationReconciliationInProgress, "old-source scan did not start")
    // The old scan has captured its sources, but its main-queue result cannot
    // apply until this synchronous removal and property-observer hook finish.
    store.removeCustomAppSource(path: custom.path)
    var reintroduced = false
    store.inventoryObserver = { apps in
        if apps.contains(where: { $0.name == "InFlight" }) { reintroduced = true }
    }
    store.sourceConfigurationDidChange()
    try finishScan(store)
    let rows = try savedLayout(store)
    try expect(!reintroduced, "an in-flight scan briefly restored an application from a removed source")
    try expect(!persistedApplicationPaths(rows).contains { $0.hasSuffix("/InFlight.app") },
               "an in-flight scan restored a removed source's persisted layout")
    let index = ApplicationDiscoveryIndex.load(from: fixture.discoveryDefaults)
    try expect(!index.originsByTarget.keys.contains { $0.hasSuffix("/InFlight.app") },
               "an in-flight scan rewrote removed discovery origins")
}

func testPersistedPathAliasRemovedBeforeFirstScan(_ root: URL) throws {
    let fixture = try Fixture(root: root, name: "restart-remove-persisted-alias")
    defer { fixture.restorePermissions() }
    let custom = fixture.directory.appendingPathComponent("CustomLinks")
    try fixture.fileManager.createDirectory(at: custom, withIntermediateDirectories: true)
    let target = fixture.directory.appendingPathComponent("ExternalTargets/Alias.app")
    try fixture.createApp(target)
    try fixture.fileManager.createSymbolicLink(at: custom.appendingPathComponent("Alias.app"), withDestinationURL: target)
    let original = fixture.store()
    original.customAppSourcePaths = [custom.path]
    original.performInitialScanIfNeeded()
    try finishScan(original)
    guard let app = original.apps.first(where: { $0.name == "Alias" }) else {
        throw TestFailure(description: "alias control did not discover the application")
    }
    let aliasPath: String
    if app.url.path.hasPrefix("/private/var/") || app.url.path.hasPrefix("/private/tmp/") {
        aliasPath = String(app.url.path.dropFirst("/private".count))
    } else if app.url.path.hasPrefix("/var/") || app.url.path.hasPrefix("/tmp/") {
        aliasPath = "/private" + app.url.path
    } else {
        throw TestSkip(description: "temporary directory has no /private path alias on this runtime")
    }
    try expect(fixture.fileManager.fileExists(atPath: aliasPath), "alternate saved path does not resolve to the fixture application")
    let aliasedApp = AppInfo(name: app.name, url: URL(fileURLWithPath: aliasPath))
    original.apps = original.apps.map { $0.name == "Alias" ? aliasedApp : $0 }
    original.items = original.items.map { item in
        if case .app(let existing) = item, existing.name == "Alias" { return .app(aliasedApp) }
        return item
    }
    original.saveAllOrder()
    original.rescan()
    try finishScan(original)
    let saved = try savedLayout(original)
    try expect(saved.contains { $0.app == aliasPath }, "scan replaced the saved path alias instead of preserving layout identity")
    let restarted = fixture.store(restarting: true)
    restarted.customAppSourcePaths = [custom.path]
    restarted.loadAllOrder()
    let deadline = Date().addingTimeInterval(15)
    while !restarted.hasAppliedOrderFromStore && Date() < deadline {
        _ = RunLoop.main.run(mode: .default, before: Date().addingTimeInterval(0.01))
    }
    try expect(restarted.hasAppliedOrderFromStore, "alias restart did not finish loading saved layout")
    restarted.removeCustomAppSource(path: custom.path)
    let removed = try savedLayout(restarted)
    try expect(!restarted.apps.contains { $0.name == "Alias" }
               && !persistedApplicationPaths(removed).contains(aliasPath),
               "source removal before the first scan ignored the persisted target mapping for a saved alias")
}

func testDirectoryAliasPermissionPreservesLayout(_ root: URL) throws {
    let fixture = try Fixture(root: root, name: "directory-alias-permission-layout")
    defer { fixture.restorePermissions() }
    let store = try seedExternalApplicationLinks(fixture)
    let hidden = fixture.directory.appendingPathComponent("HiddenAliasParent")
    try fixture.fileManager.createDirectory(at: hidden, withIntermediateDirectories: true)
    defer { try? fixture.fileManager.setAttributes([.posixPermissions: 0o700], ofItemAtPath: hidden.path) }
    let aliasDirectory = hidden.appendingPathComponent("Alias")
    try fixture.fileManager.createSymbolicLink(at: aliasDirectory,
        withDestinationURL: fixture.directory.appendingPathComponent("ExternalTargets"))
    func aliased(_ app: AppInfo) -> AppInfo {
        guard app.name == "LinkedTop" || app.name == "LinkedFolder" else { return app }
        return AppInfo(name: app.name, url: aliasDirectory.appendingPathComponent(app.url.lastPathComponent))
    }
    store.apps = store.apps.map(aliased)
    store.folders = store.folders.map { folder in
        var copy = folder
        copy.apps = folder.apps.map(aliased)
        copy.pinnedAppPaths = [aliasDirectory.appendingPathComponent("LinkedFolder.app").path]
        return copy
    }
    store.items = store.items.map { item in
        switch item {
        case .app(let app): return .app(aliased(app))
        case .folder(let folder): return .folder(store.folders.first { $0.id == folder.id }!)
        default: return item
        }
    }
    store.saveAllOrder()
    store.rescan()
    try finishScan(store)
    let expected = try savedLayout(store)
    let topPath = aliasDirectory.appendingPathComponent("LinkedTop.app").path
    let memberPath = aliasDirectory.appendingPathComponent("LinkedFolder.app").path
    try expect(expected.contains { $0.app == topPath }
               && expected.contains { $0.folderApps.contains(memberPath) && $0.pins == [memberPath] },
               "directory-alias control did not preserve aliased top-level, folder, and pin paths")
    let persisted = ApplicationDiscoveryIndex.load(from: fixture.discoveryDefaults)
    try expect(persisted.targetsByPath[memberPath] != nil,
               "readable alias scan did not persist its canonical target mapping")
    try fixture.fileManager.setAttributes([.posixPermissions: 0o000], ofItemAtPath: hidden.path)
    var permissionDenied = false
    do {
        _ = try fixture.fileManager.attributesOfItem(atPath: memberPath)
    } catch {
        let error = error as NSError
        permissionDenied = error.domain == NSCocoaErrorDomain && error.code == NSFileReadNoPermissionError
    }
    try expect(permissionDenied, "directory-alias fixture did not produce a real permission error")
    try expect(fixture.fileManager.isReadableFile(atPath: fixture.restricted.path),
               "the target's independent discovery source must remain readable")
    store.rescan()
    try finishScan(store)
    let first = try savedLayout(store)
    store.rescan()
    try finishScan(store)
    let second = try savedLayout(store)
    try fixture.fileManager.setAttributes([.posixPermissions: 0o700], ofItemAtPath: hidden.path)
    store.rescan()
    try finishScan(store)
    let recovered = try savedLayout(store)
    try expect(first == expected && second == expected,
               "denied directory alias lost a saved slot, folder member, or pin despite a readable canonical source")
    try expect(recovered == expected, "directory-alias recovery changed the saved layout")
    try expect(store.folders.first?.apps.map(\.name) == ["LinkedFolder", "SavedFolder"],
               "directory-alias recovery failed to restore member metadata")
}

func testImportSupersedesInFlightReset(_ root: URL) throws {
    let fixture = try Fixture(root: root, name: "import-during-reset-scan")
    defer { fixture.restorePermissions() }
    let store = try fixture.seedLayout()
    let visible = store.apps.first { $0.name == "Visible" }!
    let top = store.apps.first { $0.name == "SavedTop" }!
    let member = store.folders.flatMap(\.apps).first { $0.name == "SavedFolder" }!
    store.scanApplications(loadPersistedOrder: false)
    try expect(store.applicationReconciliationInProgress, "reset scan did not start before import")
    // Match import's real sequence: replace persisted rows, then apply them
    // while the old reset result is still waiting for its main-queue callback.
    let context = store.modelContext!
    for row in try context.fetch(FetchDescriptor<PageEntryData>()) { context.delete(row) }
    let importedID = UUID().uuidString
    context.insert(PageEntryData(slotId: "page-0-pos-0", pageIndex: 0, position: 0, kind: "folder",
        folderId: importedID, folderName: "Imported Folder", appPaths: [top.url.path, member.url.path],
        pinnedAppPaths: [member.url.path]))
    context.insert(PageEntryData(slotId: "page-0-pos-1", pageIndex: 0, position: 1, kind: "app", appPath: visible.url.path))
    try context.save()
    let expected = try savedLayout(store)
    store.applyImportedLayout()
    try expect(store.folders.first?.id == importedID, "import did not apply its new folder before the reset result")
    try finishScan(store)
    let first = try savedLayout(store)
    store.rescan()
    try finishScan(store)
    let second = try savedLayout(store)
    try expect(first == expected && second == expected,
               "stale reset intent erased the imported folder, membership, pins, or positions")
}

func testSharedTargetSurvivesOneSourceRemoval(_ root: URL, targetInsideSource: Bool) throws {
    let fixture = try Fixture(root: root, name: targetInsideSource ? "shared-target-inside-removed-source" : "shared-target-source-removal")
    defer { fixture.restorePermissions() }
    let sources = ["SourceA", "SourceB"].map { fixture.directory.appendingPathComponent($0) }
    let target = targetInsideSource ? sources[0].appendingPathComponent("Shared.app")
        : fixture.directory.appendingPathComponent("ExternalTargets/Shared.app")
    try fixture.createApp(target)
    for source in sources {
        try fixture.fileManager.createDirectory(at: source, withIntermediateDirectories: true)
        if targetInsideSource && source == sources[0] { continue }
        try fixture.fileManager.createSymbolicLink(at: source.appendingPathComponent("Shared.app"), withDestinationURL: target)
    }
    let store = fixture.store()
    store.customAppSourcePaths = sources.map(\.path) + [fixture.directory.appendingPathComponent("NotMounted/Apps").path]
    store.performInitialScanIfNeeded()
    try finishScan(store)
    try expect(store.apps.filter { $0.name == "Shared" }.count == 1, "shared target was not deduplicated")
    let original = try savedLayout(store)
    store.removeCustomAppSource(path: sources[0].path)
    let immediate = try savedLayout(store)
    try expect(store.apps.filter { $0.name == "Shared" }.count == 1 && immediate == original,
               "source removal immediately discarded a target still reachable through another source")
    store.rescan()
    try finishScan(store)
    let afterRemoval = try savedLayout(store)
    try expect(store.apps.filter { $0.name == "Shared" }.count == 1 && afterRemoval == original,
               "removing one source discarded or moved a target still reachable through another source")
}

func testLegacyLayoutWithoutDiscoveryIndex(_ root: URL, inaccessibleTarget: Bool) throws {
    let fixture = try Fixture(root: root, name: inaccessibleTarget ? "legacy-index-missing-target-inaccessible" : "legacy-index-missing-source-inaccessible")
    defer { fixture.restorePermissions() }
    _ = try seedExternalApplicationLinks(fixture)
    // Existing installations have layout rows but no discovery-index key.
    fixture.discoveryDefaults.removeObject(forKey: ApplicationDiscoveryIndex.defaultsKey)
    try fixture.denySubdirectory()
    if inaccessibleTarget {
        try fixture.fileManager.setAttributes([.posixPermissions: 0o000],
            ofItemAtPath: fixture.directory.appendingPathComponent("ExternalTargets").path)
    }
    let restarted = fixture.store(restarting: true)
    restarted.performInitialScanIfNeeded()
    try finishScan(restarted)
    let partial = try savedLayout(restarted)
    fixture.restorePermissions()
    restarted.rescan()
    try finishScan(restarted)
    let recovered = try savedLayout(restarted)
    try expect(partial == fixture.originalLayout,
               "upgrading a layout without discovery metadata discarded inaccessible linked applications")
    try expect(recovered == fixture.originalLayout, "legacy discovery-index migration changed layout on recovery")
    let persisted = ApplicationDiscoveryIndex.load(from: fixture.discoveryDefaults)
    try expect(persisted.originsByTarget.keys.contains { $0.hasSuffix("/LinkedFolder.app") },
               "legacy recovery did not persist newly learned discovery origins")
}

func testExplicitRemovalOverridesLegacyPendingSource(_ root: URL) throws {
    let fixture = try Fixture(root: root, name: "legacy-partial-source-migration")
    defer { fixture.restorePermissions() }
    let sourceB = fixture.directory.appendingPathComponent("SourceB")
    try fixture.fileManager.createDirectory(at: sourceB, withIntermediateDirectories: true)
    let target = fixture.directory.appendingPathComponent("ExternalTargets/SharedLegacy.app")
    try fixture.createApp(target)
    let linkA = fixture.restricted.appendingPathComponent("SharedLegacy.app")
    try fixture.fileManager.createSymbolicLink(at: linkA, withDestinationURL: target)
    try fixture.fileManager.createSymbolicLink(at: sourceB.appendingPathComponent("SharedLegacy.app"), withDestinationURL: target)
    let original = fixture.store()
    original.customAppSourcePaths = [sourceB.path]
    original.performInitialScanIfNeeded()
    try finishScan(original)
    try expect(original.apps.contains { $0.name == "SharedLegacy" }, "legacy shared-target control did not discover the app")
    fixture.discoveryDefaults.removeObject(forKey: ApplicationDiscoveryIndex.defaultsKey)
    try fixture.denySubdirectory()
    let restarted = fixture.store(restarting: true)
    restarted.customAppSourcePaths = [sourceB.path]
    restarted.performInitialScanIfNeeded()
    try finishScan(restarted)
    restarted.removeCustomAppSource(path: sourceB.path)
    let immediate = try savedLayout(restarted)
    try expect(!restarted.apps.contains { $0.name == "SharedLegacy" }
               && !persistedApplicationPaths(immediate).contains { $0.hasSuffix("/SharedLegacy.app") },
               "an unresolved legacy candidate overrode explicit removal of the last confirmed source")
    restarted.rescan()
    try finishScan(restarted)
    let stillPartial = try savedLayout(restarted)
    try expect(!persistedApplicationPaths(stillPartial).contains { $0.hasSuffix("/SharedLegacy.app") },
               "a partial scan restored an app explicitly removed with its confirmed source")
    fixture.restorePermissions()
    restarted.rescan()
    try finishScan(restarted)
    let rediscovered = try savedLayout(restarted)
    try expect(restarted.apps.contains { $0.name == "SharedLegacy" }
               && persistedApplicationPaths(rediscovered).contains { $0.hasSuffix("/SharedLegacy.app") },
               "recovering the other source did not rediscover its actual surviving link")
    try fixture.fileManager.removeItem(at: linkA)
    restarted.rescan()
    try finishScan(restarted)
    let removed = try savedLayout(restarted)
    try expect(!persistedApplicationPaths(removed).contains { $0.hasSuffix("/SharedLegacy.app") },
               "completed legacy migration continued retaining a deleted discovery link")
}

func testLegacySourceRemovalDuringPermanentPartialScan(_ root: URL, linked: Bool) throws {
    let fixture = try Fixture(root: root, name: linked ? "legacy-remove-linked-source-partial" : "legacy-remove-ordinary-source-partial")
    defer { fixture.restorePermissions() }
    let sourceB = fixture.directory.appendingPathComponent("SourceB")
    try fixture.fileManager.createDirectory(at: sourceB, withIntermediateDirectories: true)
    let target = linked ? fixture.directory.appendingPathComponent("ExternalTargets/FromB.app")
        : sourceB.appendingPathComponent("FromB.app")
    try fixture.createApp(target)
    if linked {
        try fixture.fileManager.createSymbolicLink(at: sourceB.appendingPathComponent("FromB.app"), withDestinationURL: target)
    }
    // Use a consistent source spelling so this control isolates pending legacy
    // candidates from /private versus non-/private path aliases.
    let sourcePath = sourceB.resolvingSymlinksInPath().path
    let original = fixture.store()
    original.customAppSourcePaths = [sourcePath]
    original.performInitialScanIfNeeded()
    try finishScan(original)
    try expect(original.apps.contains { $0.name == "FromB" }, "legacy source-removal control did not discover FromB")
    fixture.discoveryDefaults.removeObject(forKey: ApplicationDiscoveryIndex.defaultsKey)
    try fixture.denySubdirectory()
    let upgraded = fixture.store(restarting: true)
    upgraded.customAppSourcePaths = [sourcePath]
    upgraded.performInitialScanIfNeeded()
    try finishScan(upgraded)
    let index = ApplicationDiscoveryIndex.load(from: fixture.discoveryDefaults)
    guard let indexedTarget = index.originsByTarget.keys.first(where: { $0.hasSuffix("/FromB.app") }) else {
        throw TestFailure(description: "partial upgrade did not learn the readable source's origin")
    }
    try expect(index.originsByTarget[indexedTarget]?.contains { $0.sourcePath == sourcePath } == true
               && index.unresolvedLegacySources[indexedTarget]?.isEmpty == false,
               "fixture must combine a confirmed SourceB origin with unresolved legacy candidates")
    func expectRemoved(_ store: ProbeStore, phase: String) throws {
        let rows = try savedLayout(store)
        try expect(!store.apps.contains { $0.name == "FromB" }
                   && !persistedApplicationPaths(rows).contains { $0.hasSuffix("/FromB.app") },
                   "explicit source removal did not stay effective \(phase)")
    }
    upgraded.removeCustomAppSource(path: sourcePath)
    try expectRemoved(upgraded, phase: "immediately")
    for _ in 0..<3 {
        upgraded.rescan()
        try finishScan(upgraded)
        try expectRemoved(upgraded, phase: "during repeated partial scans")
    }
    let restarted = fixture.store(restarting: true)
    restarted.performInitialScanIfNeeded()
    try finishScan(restarted)
    try expectRemoved(restarted, phase: "after restart with the other subtree still unreadable")
}

func testRemovingUnconfirmedCandidateDoesNotRemoveLegacyApp(_ root: URL) throws {
    let fixture = try Fixture(root: root, name: "legacy-remove-unconfirmed-candidate")
    defer { fixture.restorePermissions() }
    let target = fixture.directory.appendingPathComponent("ExternalTargets/Unresolved.app")
    try fixture.createApp(target)
    try fixture.fileManager.createSymbolicLink(at: fixture.restricted.appendingPathComponent("Unresolved.app"), withDestinationURL: target)
    let unconfirmedSource = fixture.directory.appendingPathComponent("OfflineCandidate/Apps").path
    let original = fixture.store()
    original.customAppSourcePaths = [unconfirmedSource]
    original.performInitialScanIfNeeded()
    try finishScan(original)
    try expect(original.apps.contains { $0.name == "Unresolved" }, "unconfirmed-source control did not discover its real source")
    fixture.discoveryDefaults.removeObject(forKey: ApplicationDiscoveryIndex.defaultsKey)
    try fixture.denySubdirectory()
    let upgraded = fixture.store(restarting: true)
    upgraded.customAppSourcePaths = [unconfirmedSource]
    upgraded.performInitialScanIfNeeded()
    try finishScan(upgraded)
    let index = ApplicationDiscoveryIndex.load(from: fixture.discoveryDefaults)
    guard let indexedTarget = index.unresolvedLegacySources.keys.first(where: { $0.hasSuffix("/Unresolved.app") }) else {
        throw TestFailure(description: "legacy fixture did not retain unresolved source candidates")
    }
    try expect((index.originsByTarget[indexedTarget] ?? []).isEmpty
               && index.unresolvedLegacySources[indexedTarget]?.contains(unconfirmedSource) == true
               && !indexedTarget.hasPrefix(unconfirmedSource + "/"),
               "candidate removal requires no confirmed origin or path ownership")
    let expected = try savedLayout(upgraded)
    upgraded.removeCustomAppSource(path: unconfirmedSource)
    let immediate = try savedLayout(upgraded)
    try expect(immediate == expected, "removing a mere legacy candidate removed an unrelated app")
    for _ in 0..<3 {
        upgraded.rescan()
        try finishScan(upgraded)
    }
    let restarted = fixture.store(restarting: true)
    restarted.performInitialScanIfNeeded()
    try finishScan(restarted)
    let afterRestart = try savedLayout(restarted)
    try expect(restarted.apps.contains { $0.name == "Unresolved" } && afterRestart == expected,
               "removing an unconfirmed candidate lost an app protected by another unreadable source")
}

func testOnlyExternalTargetsInaccessible(_ root: URL, restart: Bool) throws {
    let fixture = try Fixture(root: root, name: restart ? "target-only-restarted" : "target-only-running")
    defer { fixture.restorePermissions() }
    let original = try seedExternalApplicationLinks(fixture)
    let external = fixture.directory.appendingPathComponent("ExternalTargets")
    try fixture.fileManager.setAttributes([.posixPermissions: 0o000], ofItemAtPath: external.path)
    try expect(fixture.fileManager.isReadableFile(atPath: fixture.restricted.path),
               "target-only permission test requires a readable source directory")
    var targetPermissionDenied = false
    do {
        _ = try fixture.fileManager.attributesOfItem(atPath: external.appendingPathComponent("LinkedTop.app").path)
    } catch {
        let error = error as NSError
        targetPermissionDenied = error.domain == NSCocoaErrorDomain && error.code == NSFileReadNoPermissionError
    }
    try expect(targetPermissionDenied, "external target did not produce a real permission error")
    let store = restart ? fixture.store(restarting: true) : original
    if restart { store.performInitialScanIfNeeded() } else { store.rescan() }
    try finishScan(store)
    let first = try savedLayout(store)
    store.rescan()
    try finishScan(store)
    let second = try savedLayout(store)
    fixture.restorePermissions()
    store.rescan()
    try finishScan(store)
    let recovered = try savedLayout(store)
    try expect(first == fixture.originalLayout, "target-only permission error discarded a folder member, pin, or top-level item")
    try expect(second == fixture.originalLayout, "second target-only permission scan discarded retained layout or placeholders")
    try expect(recovered == fixture.originalLayout, "restoring target access did not recover original folder membership and pins")
    try expect(store.folders.first?.apps.map(\.name) == ["LinkedFolder", "SavedFolder"],
               "target-only recovery did not refresh folder application names")
}

func testColdFolderPlaceholderNames(_ root: URL, legacy: Bool) throws {
    let fixture = try Fixture(root: root, name: legacy ? "legacy-cold-placeholder-names" : "page-cold-placeholder-names")
    defer { fixture.restorePermissions() }
    let original = try fixture.seedLayout()
    if legacy {
        let context = original.modelContext!
        for row in try context.fetch(FetchDescriptor<PageEntryData>()) { context.delete(row) }
        for slot in fixture.originalLayout {
            if let path = slot.app {
                context.insert(TopItemData(appPath: path, orderIndex: slot.position))
            } else if let id = slot.folderID {
                context.insert(TopItemData(folderId: id, folderName: slot.folderName!,
                                           appPaths: slot.folderApps, orderIndex: slot.position))
            }
        }
        try context.save()
    }
    try fixture.denySubdirectory()
    let store = fixture.store(restarting: true)
    store.performInitialScanIfNeeded()
    try finishScan(store)
    try expect(store.folders.flatMap(\.apps).map(\.name) == ["SavedFolder"],
               "cold folder placeholder inherited the folder name instead of the application name")
    try expect(store.folders.flatMap(\.apps).map { $0.url.lastPathComponent } == ["SavedFolder.app"],
               "cold name handling replaced or removed the persisted folder member")
}

func testRecentWindowShowPreservesDiscovery(_ root: URL) throws {
    let fixture = try Fixture(root: root, name: "recent-window-show-preserves-discovery")
    defer { fixture.restorePermissions() }
    let store = try seedExternalApplicationLinks(fixture)
    let indexBefore = ApplicationDiscoveryIndex.load(from: fixture.discoveryDefaults)
    try expect(!indexBefore.originsByTarget.isEmpty, "window-show control has no persisted origins")
    let startsBefore = store.reconciliationStartCount
    store.presentWindowForTesting()
    try finishScan(store)
    let indexAfter = ApplicationDiscoveryIndex.load(from: fixture.discoveryDefaults)
    let layoutAfter = try savedLayout(store)
    try expect(store.reconciliationStartCount == startsBefore,
               "showing a window after a recent successful scan started another scan")
    try expect(indexAfter == indexBefore,
               "showing a window cleared or changed persisted discovery origins, aliases, or names")
    try expect(layoutAfter == fixture.originalLayout, "showing a window changed the saved layout")
}

func testStaleWindowShowStartsOneScan(_ root: URL) throws {
    let fixture = try Fixture(root: root, name: "stale-window-show-single-scan")
    defer { fixture.restorePermissions() }
    let store = try fixture.seedLayout()
    let startsBefore = store.reconciliationStartCount
    store.makeSuccessfulScanStale()
    store.presentWindowForTesting()
    try finishScan(store)
    let layoutAfter = try savedLayout(store)
    try expect(store.reconciliationStartCount == startsBefore + 1,
               "showing a stale window did not perform exactly one reconciliation")
    try expect(layoutAfter == fixture.originalLayout, "stale-window reconciliation changed the saved layout")
}

func testWindowShowDoesNotRestartInFlightScan(_ root: URL) throws {
    let fixture = try Fixture(root: root, name: "window-show-during-scan")
    defer { fixture.restorePermissions() }
    let store = try fixture.seedLayout()
    store.rescan()
    try expect(store.applicationReconciliationInProgress, "window-show control did not start its pending scan")
    let startsBeforeShow = store.reconciliationStartCount
    // Its main-queue callback cannot run until both real window-show call sites
    // finish, so an accidental load/generation change deterministically causes
    // the unwanted second reconciliation rather than relying on scan timing.
    store.presentWindowForTesting()
    try finishScan(store)
    let layoutAfter = try savedLayout(store)
    try expect(store.reconciliationStartCount == startsBeforeShow,
               "showing a window invalidated or restarted an already-running scan")
    try expect(layoutAfter == fixture.originalLayout, "window show during a scan changed the saved layout")
}

func testTitleChangeDuringScan(_ root: URL, initial: String, replacement: String,
                               afterMetadata: Bool = true, inFolder: Bool = false,
                               alias: Bool = false, expectedName: String? = nil) throws {
    let fixture = try Fixture(root: root, name: UUID().uuidString)
    let store = try fixture.seedLayout()
    let original = inFolder ? store.folders[0].apps[0] : store.apps.first { $0.name == "Visible" }!
    var app = original
    if alias {
        let url = fixture.directory.appendingPathComponent("LayoutAlias.app")
        try fixture.fileManager.createSymbolicLink(at: url, withDestinationURL: original.url)
        app = AppInfo(name: original.name, url: url)
        store.apps = store.apps.map { $0.url == original.url ? app : $0 }
        store.items = store.items.map {
            if case .app(let value) = $0, value.url == original.url { return .app(app) }
            return $0
        }
    }
    store.setCustomTitle(initial, for: app)
    let expected = expectedName ?? (replacement.isEmpty ? original.name : replacement)
    let targetPath = original.url.resolvingSymlinksInPath().path
    let reached = DispatchSemaphore(value: 0)
    let resume = DispatchSemaphore(value: 0)
    let gate: (URL) -> Void = { url in
        guard !Thread.isMainThread, url.resolvingSymlinksInPath().path == targetPath else { return }
        reached.signal()
        _ = resume.wait(timeout: .now() + 15)
    }
    if afterMetadata { store.afterMetadataRead = gate } else { store.beforeMetadataRead = gate }
    defer { resume.signal() }
    let starts = store.reconciliationStartCount
    store.rescan()
    try expect(reached.wait(timeout: .now() + 10) == .success, "scan did not reach metadata gate")
    store.setCustomTitle(replacement, for: app)
    if let expectedName {
        let renamed = (store.apps + store.folders.flatMap(\.apps)).first { $0.url == app.url }
        try expect(renamed?.name == expectedName, "immediate rename did not display the expected name")
    }
    resume.signal()
    try finishScan(store)
    store.beforeMetadataRead = nil
    store.afterMetadataRead = nil

    let inventory = store.apps + store.folders.flatMap(\.apps)
    let displayed = store.items.flatMap { item -> [AppInfo] in
        switch item {
        case .app(let app): return [app]
        case .folder(let folder): return folder.apps
        default: return []
        }
    }
    try expect(inventory.filter { $0.url == app.url }.allSatisfy { $0.name == expected }
               && displayed.contains { $0.url == app.url && $0.name == expected },
               "scan overwrote the latest title in the inventory or grid")
    try expect(store.customTitles[app.url.path] == (replacement.isEmpty ? nil : replacement),
               "scan changed the custom-title setting")
    let index = ApplicationDiscoveryIndex.load(from: fixture.discoveryDefaults)
    try expect(index.displayNames[targetPath] == expected, "discovery index persisted a stale display name")
    try expect(store.reconciliationStartCount == starts + 1, "a rename unnecessarily restarted inventory discovery")
}

func testSourceReplacedByFile(_ root: URL, custom: Bool) throws {
    let fixture = try Fixture(root: root, name: custom ? "custom-source-became-file" : "builtin-source-became-file",
                              customSource: custom)
    defer { fixture.restorePermissions() }
    let store = try fixture.seedLayout()
    let moved = fixture.directory.appendingPathComponent("Applications.moved")
    try fixture.fileManager.moveItem(at: fixture.source, to: moved)
    // Enumerating a file reports ENOTDIR at the source root. That must not read
    // as a complete source that no longer contains any applications.
    try Data("not a directory".utf8).write(to: fixture.source)
    for _ in 0..<2 {
        store.rescan()
        try finishScan(store)
        let rows = try savedLayout(store)
        try expect(rows == fixture.originalLayout,
                   "a file in place of the source directory discarded saved positions, folder members, or pins")
    }
    try fixture.fileManager.removeItem(at: fixture.source)
    try fixture.fileManager.moveItem(at: moved, to: fixture.source)
    store.rescan()
    try finishScan(store)
    let recovered = try savedLayout(store)
    try expect(recovered == fixture.originalLayout, "restoring the source directory changed the saved layout")
    try expect(!store.items.contains { if case .missingApp = $0 { return true }; return false },
               "restoring the source directory left a missing placeholder")
}

func testLinkReplacingAppDuringScan(_ root: URL) throws {
    let fixture = try Fixture(root: root, name: "link-replaces-app-during-scan")
    defer { fixture.restorePermissions() }
    let store = try fixture.seedLayout()
    // A second source holds an application that is not in the saved layout.
    let laterSource = fixture.directory.appendingPathComponent("LaterSource")
    let fresh = laterSource.appendingPathComponent("Fresh.app")
    try fixture.createApp(fresh)
    store.customAppSourcePaths = [laterSource.path]
    let visible = store.apps.first { $0.name == "Visible" }!
    let link = fixture.source.appendingPathComponent("Visible.app")
    var replaced = false
    // Enumeration has just validated Visible.app as its own target. Replacing it
    // with a link now makes its saved path resolve to Fresh.app, so two targets
    // claim the same saved layout path.
    store.afterApplicationValidation = { url in
        guard !replaced, url.lastPathComponent == "Visible.app" else { return }
        replaced = true
        try? FileManager.default.removeItem(at: link)
        try? FileManager.default.createSymbolicLink(at: link, withDestinationURL: fresh)
    }
    store.rescan()
    try finishScan(store)
    store.afterApplicationValidation = nil
    try expect(replaced, "fixture did not replace the application during the scan")
    let rows = try savedLayout(store)
    try expect(store.apps.contains { $0.url.path == visible.url.path }
               && store.apps.contains { $0.url.lastPathComponent == "Fresh.app" },
               "a layout path claimed by two targets merged them into one application")
    try expect(Array(rows.prefix(fixture.originalLayout.count)) == fixture.originalLayout
               && persistedApplicationPaths(rows).contains { $0.hasSuffix("/Fresh.app") },
               "a layout path claimed by two targets moved saved items or lost the new application")

    // The next scan sees a consistent link, so the saved slot now represents Fresh.app.
    store.rescan()
    try finishScan(store)
    let settled = try savedLayout(store)
    let freshEntries = store.apps.filter { $0.url.resolvingSymlinksInPath().lastPathComponent == "Fresh.app" }
    try expect(freshEntries.map(\.url.path) == [visible.url.path],
               "a consistent link did not represent its target once, at the saved path")
    try expect(Array(settled.prefix(fixture.originalLayout.count)) == fixture.originalLayout
               && !persistedApplicationPaths(settled).contains { $0.hasSuffix("/Fresh.app") },
               "resolving the link changed saved positions or kept a duplicate entry")
}

/// Waits for the current scan and every retry it schedules.
func settleScans(_ store: ProbeStore) throws {
    let deadline = Date().addingTimeInterval(20)
    while (store.applicationReconciliationInProgress || store.applicationReconciliationWorkItem != nil)
            && Date() < deadline {
        _ = RunLoop.main.run(mode: .default, before: Date().addingTimeInterval(0.01))
    }
    try expect(!store.applicationReconciliationInProgress && store.applicationReconciliationWorkItem == nil,
               "scan retries did not settle within 20 seconds")
}

/// saveAllOrder replaces every row, so unchanged identifiers mean no rewrite.
func layoutRowIDs(_ store: ProbeStore) throws -> Set<PersistentIdentifier> {
    Set(try store.modelContext!.fetch(FetchDescriptor<PageEntryData>()).map(\.persistentModelID))
}

func testPersistentRetryableError(_ root: URL, restart: Bool) throws {
    let fixture = try Fixture(root: root, name: restart ? "persistent-retry-restart" : "persistent-retry-stale-window")
    defer { fixture.restorePermissions() }
    let seeded = try fixture.seedLayout()
    // A name longer than NAME_MAX makes every stat of this link's target fail
    // with ENAMETOOLONG. It is a deterministic non-permission error, so the
    // scanner retries it like EIO or ETIMEDOUT from a network volume.
    let unreachable = fixture.directory.appendingPathComponent(String(repeating: "u", count: 300) + ".app")
    let link = fixture.source.appendingPathComponent("Unreachable.app").path
    try fixture.fileManager.createSymbolicLink(atPath: link, withDestinationPath: unreachable.path)
    let store: ProbeStore
    if restart {
        store = fixture.store(restarting: true)
        store.performInitialScanIfNeeded()
    } else {
        store = seeded
        store.makeSuccessfulScanStale()
        store.presentWindowForTesting()
    }
    try finishScan(store)
    try expect(store.applicationReconciliationWorkItem != nil, "a retryable scan error did not schedule a retry")
    let rows = try layoutRowIDs(store)
    let starts = store.reconciliationStartCount

    try settleScans(store)
    let rowsAfterRetries = try layoutRowIDs(store)
    try expect(store.reconciliationStartCount == starts + 2, "retries for a persistent error were not bounded at two")
    try expect(rowsAfterRetries == rows, "retrying a partial scan rewrote an unchanged saved layout")

    store.presentWindowForTesting()
    try settleScans(store)
    let rowsAfterWindowShow = try layoutRowIDs(store)
    try expect(store.reconciliationStartCount == starts + 2,
               "showing the window rescanned soon after a partial scan was applied")
    try expect(rowsAfterWindowShow == rows, "showing the window rewrote an unchanged saved layout")

    // The retries are spent, so a later trigger costs one scan, not three.
    store.fileSystemEventRescan()
    try settleScans(store)
    try expect(store.reconciliationStartCount == starts + 3,
               "a file-system event during a persistent error started another round of retries")
    let layout = try savedLayout(store)
    try expect(layout == fixture.originalLayout, "a persistent retryable error changed the saved layout")

    // Waiting for another retry round is slow, so check recovery once: a
    // complete scan restores the retry budget for the next transient error.
    guard !restart else { return }
    try fixture.fileManager.removeItem(atPath: link)
    store.fileSystemEventRescan()
    try settleScans(store)
    try fixture.fileManager.createSymbolicLink(atPath: link, withDestinationPath: unreachable.path)
    let startsBeforeNewError = store.reconciliationStartCount
    store.fileSystemEventRescan()
    try settleScans(store)
    try expect(store.reconciliationStartCount == startsBeforeNewError + 3,
               "a complete scan did not restore retries for a new transient error")
}

func testSupersededScanKeepsReasons(_ root: URL) throws {
    let fixture = try Fixture(root: root, name: "superseded-scan-keeps-reasons")
    defer { fixture.restorePermissions() }
    let store = try fixture.seedLayout()
    // The external uninstaller flow sets this before the window returns.
    store.needsReconciliationAfterExternalUninstall = true
    store.presentWindowForTesting()
    try expect(store.applicationReconciliationInProgress, "returning from an uninstaller did not start a scan")
    // The scan's main-queue result cannot apply before this synchronous change.
    store.sourceConfigurationDidChange()
    try finishScan(store)
    try expect(!store.needsReconciliationAfterExternalUninstall,
               "the rerun of a superseded scan dropped its uninstaller check")
    let starts = store.reconciliationStartCount
    store.presentWindowForTesting()
    try finishScan(store)
    try expect(store.reconciliationStartCount == starts, "the next window show repeated the uninstaller scan")
}

func testSupersededInitialScanKeepsLoading(_ root: URL) throws {
    let fixture = try Fixture(root: root, name: "superseded-initial-scan-loading")
    defer { fixture.restorePermissions() }
    let store = fixture.store()
    var appsWhenLoadingEnded: Int?
    store.loadingObserver = { [unowned store] loading in
        if !loading && appsWhenLoadingEnded == nil { appsWhenLoadingEnded = store.apps.count }
    }
    store.performInitialScanIfNeeded()
    try expect(store.applicationReconciliationInProgress, "initial scan did not start")
    store.sourceConfigurationDidChange()
    try finishScan(store)
    try expect(appsWhenLoadingEnded == 3,
               "the loading screen ended on a superseded scan, before any applications were applied")
}

func testDisplayNamesFollowIndexedTargets(_ root: URL) throws {
    let fixture = try Fixture(root: root, name: "display-names-follow-index")
    defer { fixture.restorePermissions() }
    let store = try fixture.seedLayout()
    func names() -> [String: String] { ApplicationDiscoveryIndex.load(from: fixture.discoveryDefaults).displayNames }
    try expect(names().keys.contains { $0.hasSuffix("/Visible.app") }, "control scan did not record a display name")
    try fixture.denySubdirectory()
    try fixture.fileManager.removeItem(at: fixture.source.appendingPathComponent("Visible.app"))
    // The first scan removes the app from the layout; the next forgets it.
    for _ in 0..<2 {
        store.rescan()
        try finishScan(store)
    }
    let remaining = names()
    try expect(!remaining.keys.contains { $0.hasSuffix("/Visible.app") },
               "a deleted application kept its display name indefinitely")
    try expect(remaining.contains { $0.key.hasSuffix("/SavedTop.app") && $0.value == "SavedTop" },
               "pruning dropped the name of an application protected by an unreadable directory")
}

func testLinkedSourceRoot(_ root: URL) throws {
    let fixture = try Fixture(root: root, name: "linked-source-root")
    defer { fixture.restorePermissions() }
    let realDirectory = fixture.directory.appendingPathComponent("RealDirectory")
    try fixture.createApp(realDirectory.appendingPathComponent("BehindLink.app"))
    let linkedRoot = fixture.directory.appendingPathComponent("LinkedRoot")
    try fixture.fileManager.createSymbolicLink(at: linkedRoot, withDestinationURL: realDirectory)
    let store = fixture.store()
    store.customAppSourcePaths = [linkedRoot.path]
    store.performInitialScanIfNeeded()
    try finishScan(store)
    try expect(store.apps.contains { $0.name == "BehindLink" }, "a source whose root is a link discovered none of its apps")
    try expect(store.applicationReconciliationWorkItem == nil, "a readable linked source root scheduled a retry")
    try fixture.fileManager.removeItem(at: realDirectory.appendingPathComponent("BehindLink.app"))
    store.rescan()
    try finishScan(store)
    try expect(!store.apps.contains { $0.name == "BehindLink" }, "a linked source root did not report a removed app")
}

func testSourceListingMatchesRemoval(_ root: URL) throws {
    let fixture = try Fixture(root: root, name: "source-listing-matches-removal")
    defer { fixture.restorePermissions() }
    // One source only links to its app; another source is itself a link.
    let linkSource = fixture.directory.appendingPathComponent("LinkSource")
    try fixture.fileManager.createDirectory(at: linkSource, withIntermediateDirectories: true)
    let target = fixture.directory.appendingPathComponent("ExternalTargets/Linked.app")
    try fixture.createApp(target)
    try fixture.fileManager.createSymbolicLink(at: linkSource.appendingPathComponent("Linked.app"), withDestinationURL: target)
    let realDirectory = fixture.directory.appendingPathComponent("RealDirectory")
    try fixture.createApp(realDirectory.appendingPathComponent("BehindLink.app"))
    let linkedRoot = fixture.directory.appendingPathComponent("LinkedRoot")
    try fixture.fileManager.createSymbolicLink(at: linkedRoot, withDestinationURL: realDirectory)
    let store = fixture.store()
    store.customAppSourcePaths = [linkSource.path, linkedRoot.path]
    store.performInitialScanIfNeeded()
    try finishScan(store)
    guard let linked = store.apps.first(where: { $0.name == "Linked" }),
          let behind = store.apps.first(where: { $0.name == "BehindLink" }),
          let visible = store.apps.first(where: { $0.name == "Visible" }) else {
        throw TestFailure(description: "source listing control did not discover its applications")
    }
    try expect(store.isApplication(atPath: linked.url.path, providedBySource: linkSource.path),
               "Settings omitted an app that its source discovered through a link")
    try expect(store.isApplication(atPath: behind.url.path, providedBySource: linkedRoot.path),
               "Settings omitted an app from a source whose root is a link")
    try expect(!store.isApplication(atPath: visible.url.path, providedBySource: linkSource.path)
               && !store.isApplication(atPath: linked.url.path, providedBySource: linkedRoot.path),
               "Settings listed an app under a source that did not provide it")
    store.removeCustomAppSource(path: linkSource.path)
    try expect(!store.apps.contains { $0.name == "Linked" } && store.apps.contains { $0.name == "BehindLink" },
               "source removal disagreed with the apps Settings listed for it")
}

/// Waits for a scan that the code under test schedules on its own, then for it to finish.
func waitForScheduledScan(_ store: ProbeStore, after starts: Int) throws {
    let deadline = Date().addingTimeInterval(10)
    while store.reconciliationStartCount == starts && Date() < deadline {
        _ = RunLoop.main.run(mode: .default, before: Date().addingTimeInterval(0.01))
    }
    try expect(store.reconciliationStartCount > starts, "the volume event did not start a scan")
    try finishScan(store)
}

/// A disposable real volume: a moved directory cannot establish whether the
/// scanner distinguishes an unmounted volume from a deleted local directory.
final class TestDiskVolume {
    let image: URL
    let mountPoint: URL
    private var mounted = false

    /// Every test disk has the same volume name, as two drives named Untitled do.
    init(in directory: URL, name: String = "Volume", mountPoint: URL? = nil) throws {
        image = directory.appendingPathComponent(name + ".dmg")
        self.mountPoint = mountPoint ?? directory.appendingPathComponent("Drive")
        try Self.run(["create", "-size", "32m", "-fs", "HFS+", "-volname", "LaunchNextTest", image.path])
        try attach()
    }

    /// The UUID of the disk now mounted at the mount point. A fresh URL avoids
    /// resource values cached before a different disk was mounted there.
    var uuid: String? {
        try? URL(fileURLWithPath: mountPoint.path).resourceValues(forKeys: [.volumeUUIDStringKey]).volumeUUIDString
    }

    private static func run(_ arguments: [String]) throws {
        let process = Process()
        process.executableURL = URL(fileURLWithPath: "/usr/bin/hdiutil")
        process.arguments = arguments
        let output = Pipe()
        process.standardOutput = output
        process.standardError = output
        try process.run()
        let data = output.fileHandleForReading.readDataToEndOfFile()
        process.waitUntilExit()
        guard process.terminationStatus == 0 else {
            throw TestFailure(description: "hdiutil failed: " + String(decoding: data, as: UTF8.self))
        }
    }

    func attach() throws {
        try FileManager.default.createDirectory(at: mountPoint, withIntermediateDirectories: true)
        try Self.run(["attach", "-nobrowse", "-noautoopen", "-mountpoint", mountPoint.path, image.path])
        mounted = true
    }

    func detach() throws {
        guard mounted else { return }
        try Self.run(["detach", mountPoint.path])
        mounted = false
    }

    deinit { try? detach() }
}

func testDeletedLinkedAppDirectory(_ root: URL) throws {
    let fixture = try Fixture(root: root, name: "deleted-linked-app-directory")
    let parent = fixture.directory.appendingPathComponent("LocalTools/Tool")
    for name in ["LinkedTop", "LinkedMember"] {
        let target = parent.appendingPathComponent(name + ".app")
        try fixture.createApp(target)
        try fixture.fileManager.createSymbolicLink(at: fixture.source.appendingPathComponent(name + ".app"),
                                                   withDestinationURL: target)
    }
    let volume = try parent.resourceValues(forKeys: [.volumeURLKey]).volume!
    let store = fixture.store()
    store.performInitialScanIfNeeded()
    try finishScan(store)
    let top = store.apps.first { $0.name == "LinkedTop" }!
    let member = store.apps.first { $0.name == "LinkedMember" }!
    let visible = store.apps.first { $0.name == "Visible" }!
    let folder = FolderInfo(name: "Tools", apps: [member, visible], pinnedAppPaths: [member.url.path])
    store.apps.removeAll { $0.url == member.url || $0.url == visible.url }
    store.folders = [folder]
    store.items = [.folder(folder), .app(top)]
    store.saveAllOrder()

    try fixture.fileManager.removeItem(at: parent)
    let mounted = fixture.fileManager.mountedVolumeURLs(includingResourceValuesForKeys: nil) ?? []
    try expect(mounted.contains { $0.standardizedFileURL == volume.standardizedFileURL },
               "the control volume must remain mounted after deleting the parent folder")
    for pass in 0..<3 {
        let current = pass == 2 ? fixture.store(restarting: true) : store
        if pass == 2 { current.performInitialScanIfNeeded() } else { current.rescan() }
        try finishScan(current)
        let rows = try savedLayout(current)
        try expect(!persistedApplicationPaths(rows).contains {
            $0.hasSuffix("/LinkedTop.app") || $0.hasSuffix("/LinkedMember.app")
        }, "a deleted local folder was treated as an unmounted volume")
        try expect(!current.items.contains { if case .missingApp = $0 { return true }; return false },
                   "a deleted local folder left a permanent missing-app placeholder")
        try expect(current.folders.first?.apps.map(\.name) == ["Visible"]
                   && current.folders.first?.pinnedAppPaths.isEmpty == true,
                   "deleting a linked member lost an unrelated app or retained a stale pin")
    }
}

func testLinkedAppsOnUnpluggedDrive(_ root: URL) throws {
    let fixture = try Fixture(root: root, name: "linked-apps-on-unplugged-drive")
    defer { fixture.restorePermissions() }
    let volume = try TestDiskVolume(in: fixture.directory)
    defer { try? volume.detach() }
    let drive = volume.mountPoint
    let tools = drive.appendingPathComponent("Tools")
    for name in ["OnDriveTop", "OnDriveMember"] {
        let app = tools.appendingPathComponent(name + ".app")
        try fixture.createApp(app)
        try fixture.fileManager.createSymbolicLink(at: fixture.source.appendingPathComponent(name + ".app"),
                                                   withDestinationURL: app)
    }
    var store = fixture.store()
    store.performInitialScanIfNeeded()
    try finishScan(store)
    guard let top = store.apps.first(where: { $0.name == "OnDriveTop" }),
          let member = store.apps.first(where: { $0.name == "OnDriveMember" }),
          let visible = store.apps.first(where: { $0.name == "Visible" }) else {
        throw TestFailure(description: "drive control did not discover its linked applications")
    }
    let folder = FolderInfo(name: "Tools", apps: [member, visible])
    store.apps.removeAll { $0.url == member.url || $0.url == visible.url }
    store.folders = [folder]
    store.items = [.folder(folder), .app(top)] + store.apps.filter { $0.url != top.url }.map { .app($0) }
    store.saveAllOrder()
    let original = try savedLayout(store)

    try volume.detach()
    var starts = store.reconciliationStartCount
    store.volumeDidChange(at: drive, mounted: false)
    try waitForScheduledScan(store, after: starts)
    let whileUnplugged = try savedLayout(store)
    try expect(whileUnplugged == original, "unplugging a drive discarded the positions of linked apps on it")

    // The volume is mounted outside /Volumes. Its recorded location must survive
    // a restart even though the mount point directory still exists while offline.
    store = fixture.store(restarting: true)
    store.performInitialScanIfNeeded()
    try finishScan(store)
    let afterRestart = try savedLayout(store)
    try expect(afterRestart == original, "restarting while the volume is offline discarded linked apps")

    try volume.attach()
    starts = store.reconciliationStartCount
    store.volumeDidChange(at: drive, mounted: true)
    try waitForScheduledScan(store, after: starts)
    let replugged = try savedLayout(store)
    try expect(replugged == original
               && !store.items.contains { if case .missingApp = $0 { return true }; return false }
               && store.folders.first?.apps.map(\.name) == ["OnDriveMember", "Visible"],
               "replugging the drive did not restore its linked apps in place")

    // While the drive stays connected, a deleted app is a real removal.
    try fixture.fileManager.removeItem(at: tools.appendingPathComponent("OnDriveTop.app"))
    store.rescan()
    try finishScan(store)
    let rows = try savedLayout(store)
    try expect(!persistedApplicationPaths(rows).contains { $0.hasSuffix("/OnDriveTop.app") },
               "an app deleted from a connected drive kept its slot")
    try fixture.fileManager.removeItem(at: tools)
    store.rescan()
    try finishScan(store)
    let afterFolderDeletion = try savedLayout(store)
    try expect(!persistedApplicationPaths(afterFolderDeletion).contains { $0.hasSuffix("/OnDriveMember.app") },
               "a folder deleted from a mounted external volume kept its linked app")
    try volume.detach()
}

func testSameNamedDriveAtSamePath(_ root: URL) throws {
    let fixture = try Fixture(root: root, name: "same-named-drive-at-same-path")
    defer { fixture.restorePermissions() }
    let volume = try TestDiskVolume(in: fixture.directory)
    defer { try? volume.detach() }
    let drive = volume.mountPoint
    let app = drive.appendingPathComponent("Tools/OnDrive.app")
    try fixture.createApp(app)
    try fixture.fileManager.createSymbolicLink(at: fixture.source.appendingPathComponent("OnDrive.app"),
                                               withDestinationURL: app)
    var store = fixture.store()
    store.performInitialScanIfNeeded()
    try finishScan(store)
    guard let onDrive = store.apps.first(where: { $0.name == "OnDrive" }),
          let visible = store.apps.first(where: { $0.name == "Visible" }) else {
        throw TestFailure(description: "same-named drive control did not discover its linked application")
    }
    let folder = FolderInfo(name: "Tools", apps: [onDrive, visible])
    store.apps.removeAll { $0.url == onDrive.url || $0.url == visible.url }
    store.folders = [folder]
    store.items = [.folder(folder)] + store.apps.map { .app($0) }
    store.saveAllOrder()
    let original = try savedLayout(store)
    let originalUUID = volume.uuid

    // A different disk with the same name takes the drive's mount point. The
    // app is absent there, but it was not deleted from its own disk.
    try volume.detach()
    let other = try TestDiskVolume(in: fixture.directory, name: "Other", mountPoint: drive)
    defer { try? other.detach() }
    try expect(originalUUID != nil && other.uuid != nil && other.uuid != originalUUID,
               "the two test disks must have distinct volume UUIDs")
    var starts = store.reconciliationStartCount
    store.volumeDidChange(at: drive, mounted: true)
    try waitForScheduledScan(store, after: starts)
    let whileSwapped = try savedLayout(store)
    try expect(whileSwapped == original,
               "a different drive at the same path discarded the position of a linked app")

    store = fixture.store(restarting: true)
    store.performInitialScanIfNeeded()
    try finishScan(store)
    let afterRestart = try savedLayout(store)
    try expect(afterRestart == original,
               "restarting with a different drive at the same path discarded a linked app")

    try other.detach()
    try volume.attach()
    starts = store.reconciliationStartCount
    store.volumeDidChange(at: drive, mounted: true)
    try waitForScheduledScan(store, after: starts)
    let returned = try savedLayout(store)
    try expect(returned == original
               && !store.items.contains { if case .missingApp = $0 { return true }; return false }
               && store.folders.first?.apps.map(\.name) == ["OnDrive", "Visible"],
               "returning the original drive did not restore its linked app in place")
    try volume.detach()
}

// MARK: - Hidden apps in search

/// Every application path an item list shows, including folder members.
func appPaths(_ items: [LaunchpadItem]) -> [String] {
    items.flatMap { item -> [String] in
        switch item {
        case .app(let app): return [app.url.path]
        case .folder(let folder): return folder.apps.map(\.url.path)
        case .missingApp(let placeholder): return [placeholder.bundlePath]
        case .empty: return []
        }
    }
}

func occurrences(of app: AppInfo, in items: [LaunchpadItem]) -> Int {
    appPaths(items).filter { $0 == app.url.path }.count
}

/// Scans Visible, SavedTop, SavedFolder, Tool and Member, puts Member and
/// SavedFolder in a folder the way createFolder leaves them, then hides Tool.
func seedHiddenSearch(_ fixture: Fixture) throws -> (store: ProbeStore, tool: AppInfo) {
    try fixture.createApp(fixture.source.appendingPathComponent("Tool.app"))
    try fixture.createApp(fixture.source.appendingPathComponent("Member.app"))
    let store = fixture.store()
    store.performInitialScanIfNeeded()
    try finishScan(store)
    guard let tool = store.apps.first(where: { $0.name == "Tool" }),
          let member = store.apps.first(where: { $0.name == "Member" }),
          let savedFolder = store.apps.first(where: { $0.name == "SavedFolder" }) else {
        throw TestFailure(description: "hidden-search fixture did not discover its applications")
    }
    let folder = FolderInfo(name: "Folder", apps: [member, savedFolder])
    store.apps.removeAll { $0.url == member.url || $0.url == savedFolder.url }
    store.folders = [folder]
    store.items = store.apps.map { .app($0) } + [.folder(folder)]
    store.saveAllOrder()
    try expect(store.hideApp(atPath: tool.url.path), "hiding the fixture app failed")
    return (store, tool)
}

func testHiddenAppsStayOutOfSearchByDefault(_ root: URL) throws {
    let fixture = try Fixture(root: root, name: "hidden-search-default")
    let (store, tool) = try seedHiddenSearch(fixture)
    try expect(occurrences(of: tool, in: store.items) == 0 && !store.apps.contains(tool),
               "hiding an app left it in the grid")
    try expect(store.hiddenApplicationInventory.map(\.url) == [tool.url],
               "hiding an app did not keep its metadata for search")
    try expect(occurrences(of: tool, in: store.search("Tool")) == 0,
               "a hidden app appeared in search while the option was off")
    try expect(appPaths(store.search("")) == appPaths(store.items),
               "an empty search did not show the grid unchanged")
}

func testHiddenAppsAppearOnlyForSearchText(_ root: URL) throws {
    let fixture = try Fixture(root: root, name: "hidden-search-text")
    let (store, tool) = try seedHiddenSearch(fixture)
    store.showHiddenAppsInSearch = true
    try expect(occurrences(of: tool, in: store.search("Tool")) == 1,
               "an enabled search did not find the hidden app exactly once")
    try expect(occurrences(of: tool, in: store.items) == 0, "searching put the hidden app back in the grid")
    for blank in ["", "   "] {
        try expect(appPaths(store.search(blank)) == appPaths(store.items),
                   "a blank search (\(blank.count) spaces) showed more than the grid")
    }
    // Clearing the field removes hidden results before the debounced query follows.
    store.searchText = ""
    store.searchQuery = "Tool"
    try expect(occurrences(of: tool, in: store.filteredItems) == 0,
               "a cleared field kept showing the hidden app until the search delay passed")
    store.fuzzySearchEnabled = false
    try expect(occurrences(of: tool, in: store.search("oo")) == 1,
               "substring search did not find the hidden app")
    store.fuzzySearchEnabled = true
    for enabled in [false, true, false] { store.showHiddenAppsInSearch = enabled }
    try expect(occurrences(of: tool, in: store.search("Tool")) == 0,
               "turning the option off left the hidden app in the results")
    store.showHiddenAppsInSearch = true
    try expect(occurrences(of: tool, in: store.search("Tool")) == 1,
               "turning the option back on did not restore the hidden result")
}

func testHiddenSearchFollowsHideUnhideAndRescans(_ root: URL) throws {
    let fixture = try Fixture(root: root, name: "hidden-search-lifecycle")
    let (store, tool) = try seedHiddenSearch(fixture)
    store.showHiddenAppsInSearch = true

    store.unhideApp(path: tool.url.path)
    try expect(store.hiddenApplicationInventory.isEmpty, "unhiding left a search-only entry behind")
    try expect(occurrences(of: tool, in: store.items) == 1, "unhiding did not return the app to the grid")
    try expect(occurrences(of: tool, in: store.search("Tool")) == 1,
               "an unhidden app appeared more than once in search")

    try expect(store.hideApp(atPath: tool.url.path), "hiding the app again failed")
    try expect(occurrences(of: tool, in: store.items) == 0
               && occurrences(of: tool, in: store.search("Tool")) == 1,
               "hiding during a search did not move the app from the grid to search only")

    store.rescan()
    try finishScan(store)
    try expect(occurrences(of: tool, in: store.items) == 0
               && occurrences(of: tool, in: store.search("Tool")) == 1,
               "a rescan changed where the hidden app appears")

    // Nothing is cached on disk: a restart offers the app again after its first scan.
    let restarted = fixture.store(restarting: true)
    restarted.hiddenAppPaths = store.hiddenAppPaths
    restarted.showHiddenAppsInSearch = true
    restarted.performInitialScanIfNeeded()
    try expect(occurrences(of: tool, in: restarted.search("Tool")) == 0,
               "a restart offered a hidden app before scanning confirmed it")
    try finishScan(restarted)
    try expect(occurrences(of: tool, in: restarted.items) == 0
               && occurrences(of: tool, in: restarted.search("Tool")) == 1,
               "after a restart the hidden app was not search-only")
}

func testHiddenFolderMemberSearch(_ root: URL) throws {
    let fixture = try Fixture(root: root, name: "hidden-search-folder-member")
    let (store, _) = try seedHiddenSearch(fixture)
    store.showHiddenAppsInSearch = true
    guard let member = store.folders.first?.apps.first(where: { $0.name == "Member" }) else {
        throw TestFailure(description: "fixture folder lost its member")
    }
    try expect(store.hideApp(atPath: member.url.path), "hiding a folder member failed")
    try expect(store.folders.first?.apps.map(\.name) == ["SavedFolder"]
               && occurrences(of: member, in: store.items) == 0,
               "the hidden member stayed in its folder")
    try expect(occurrences(of: member, in: store.search("Member")) == 1,
               "a hidden folder member was not found exactly once")
    store.rescan()
    try finishScan(store)
    try expect(occurrences(of: member, in: store.items) == 0
               && occurrences(of: member, in: store.search("Member")) == 1,
               "a rescan returned the hidden member to its folder or duplicated it")
}

func testLinkedHiddenAppAppearsOnce(_ root: URL) throws {
    let fixture = try Fixture(root: root, name: "hidden-search-linked")
    // The target is in its own source and also linked from the main source.
    let targets = fixture.directory.appendingPathComponent("LinkedTargets")
    let target = targets.appendingPathComponent("Linked.app")
    try fixture.createApp(target)
    try fixture.fileManager.createSymbolicLink(at: fixture.source.appendingPathComponent("Linked.app"),
                                               withDestinationURL: target)
    let store = fixture.store()
    store.customAppSourcePaths = [targets.path]
    store.performInitialScanIfNeeded()
    try finishScan(store)
    let linked = store.apps.filter { $0.name == "Linked" }
    try expect(linked.count == 1, "two sources made the linked app appear \(linked.count) times")
    store.items = store.apps.map { .app($0) }
    try expect(store.hideApp(atPath: linked[0].url.path), "hiding the linked app failed")
    store.showHiddenAppsInSearch = true
    try expect(store.search("Linked").filter { if case .app(let app) = $0 { return app.name == "Linked" }; return false }.count == 1,
               "the hidden linked app was not found exactly once")
    store.rescan()
    try finishScan(store)
    try expect(store.search("Linked").filter { if case .app(let app) = $0 { return app.name == "Linked" }; return false }.count == 1,
               "a rescan duplicated the hidden linked app")
}

func testUninstalledHiddenAppLeavesSearch(_ root: URL) throws {
    let fixture = try Fixture(root: root, name: "hidden-search-uninstalled")
    let (store, tool) = try seedHiddenSearch(fixture)
    store.showHiddenAppsInSearch = true
    try fixture.fileManager.removeItem(at: tool.url)
    store.fileSystemEventRescan()
    try finishScan(store)
    try expect(store.hiddenApplicationInventory.isEmpty && occurrences(of: tool, in: store.search("Tool")) == 0,
               "an uninstalled hidden app stayed a launchable search result")
}

func testRemovedSourceTakesHiddenAppsFromSearch(_ root: URL) throws {
    let fixture = try Fixture(root: root, name: "hidden-search-removed-source", customSource: true)
    let (store, tool) = try seedHiddenSearch(fixture)
    store.showHiddenAppsInSearch = true
    store.removeCustomAppSource(path: fixture.source.path)
    try expect(occurrences(of: tool, in: store.search("Tool")) == 0,
               "removing a source left its hidden app in search until the next scan")
    store.sourceConfigurationDidChange()
    try finishScan(store)
    try expect(store.hiddenApplicationInventory.isEmpty && occurrences(of: tool, in: store.search("Tool")) == 0,
               "the rescan after removing a source restored its hidden app")
    try expect(store.hiddenAppPaths.contains(tool.url.path),
               "removing a source changed which apps are hidden")
}

/// A hidden app on an unplugged drive cannot open, so it leaves search until
/// the drive returns, and never enters the grid.
func testOfflineHiddenAppLeavesSearchUntilDriveReturns(_ root: URL) throws {
    let fixture = try Fixture(root: root, name: "hidden-search-offline-drive")
    defer { fixture.restorePermissions() }
    let volume = try TestDiskVolume(in: fixture.directory)
    defer { try? volume.detach() }
    let drive = volume.mountPoint
    for name in ["OnDrive", "LaterHidden"] {
        let target = drive.appendingPathComponent("Tools/\(name).app")
        try fixture.createApp(target)
        try fixture.fileManager.createSymbolicLink(at: fixture.source.appendingPathComponent("\(name).app"),
                                                   withDestinationURL: target)
    }
    let store = fixture.store()
    store.performInitialScanIfNeeded()
    try finishScan(store)
    guard let onDrive = store.apps.first(where: { $0.name == "OnDrive" }),
          let laterHidden = store.apps.first(where: { $0.name == "LaterHidden" }) else {
        throw TestFailure(description: "drive control did not discover its linked applications")
    }
    store.items = store.apps.map { .app($0) }
    store.saveAllOrder()
    try expect(store.hideApp(atPath: onDrive.url.path), "hiding the drive app failed")
    store.showHiddenAppsInSearch = true
    try expect(occurrences(of: onDrive, in: store.search("OnDrive")) == 1, "the hidden drive app was not searchable")

    try volume.detach()
    var starts = store.reconciliationStartCount
    store.volumeDidChange(at: drive, mounted: false)
    try waitForScheduledScan(store, after: starts)
    try expect(occurrences(of: onDrive, in: store.search("OnDrive")) == 0,
               "an offline hidden app stayed a launchable search result")
    try expect(occurrences(of: onDrive, in: store.items) == 0, "an offline hidden app entered the grid")
    // Hiding an app whose drive is unplugged must not offer it in search either.
    try expect(store.hideApp(atPath: laterHidden.url.path), "hiding an offline app failed")
    try expect(occurrences(of: laterHidden, in: store.search("LaterHidden")) == 0,
               "an app hidden while its drive was unplugged became a launchable search result")

    try volume.attach()
    starts = store.reconciliationStartCount
    store.volumeDidChange(at: drive, mounted: true)
    try waitForScheduledScan(store, after: starts)
    for app in [onDrive, laterHidden] {
        try expect(occurrences(of: app, in: store.search(app.name)) == 1
                   && occurrences(of: app, in: store.items) == 0,
                   "the returning drive did not restore \(app.name) to search only")
    }
    try volume.detach()
}

/// Pinyin matching needs the background index, so hidden apps must be indexed.
func testHiddenAppsKeepTransliteratedSearch(_ root: URL) throws {
    let fixture = try Fixture(root: root, name: "hidden-search-transliteration")
    try fixture.createApp(fixture.source.appendingPathComponent("微信测试.app"))
    let store = fixture.store()
    store.performInitialScanIfNeeded()
    try finishScan(store)
    guard let app = store.apps.first(where: { $0.name == "微信测试" }) else {
        throw TestFailure(description: "transliteration fixture did not discover its application")
    }
    store.items = store.apps.map { .app($0) }
    try expect(store.hideApp(atPath: app.url.path), "hiding the CJK-named app failed")
    store.showHiddenAppsInSearch = true
    let deadline = Date().addingTimeInterval(10)
    while occurrences(of: app, in: store.search("weixin")) == 0 && Date() < deadline {
        _ = RunLoop.main.run(mode: .default, before: Date().addingTimeInterval(0.01))
    }
    try expect(occurrences(of: app, in: store.search("weixin")) == 1,
               "pinyin did not find the hidden app because the index left it out")
}

func testImportedHiddenAppsUpdateSearch(_ root: URL) throws {
    let fixture = try Fixture(root: root, name: "hidden-search-import")
    let (store, tool) = try seedHiddenSearch(fixture)
    store.showHiddenAppsInSearch = true
    guard let visible = store.apps.first(where: { $0.name == "Visible" }) else {
        throw TestFailure(description: "fixture lost its visible app")
    }
    // The imported preferences unhide Tool and hide Visible.
    store.reloadImportedHiddenApps([visible.url.path])
    try expect(store.hiddenApplicationInventory.map(\.url) == [visible.url],
               "an import did not replace the hidden apps search offers")
    // An import refreshes the library, which returns Tool to the grid.
    store.rescan()
    try finishScan(store)
    try expect(occurrences(of: tool, in: store.items) == 1 && occurrences(of: tool, in: store.search("Tool")) == 1,
               "the app the import unhid did not return to the grid exactly once")
    try expect(occurrences(of: visible, in: store.items) == 0
               && occurrences(of: visible, in: store.search("Visible")) == 1,
               "the app the import hid was not search-only")
}

func testRenamedHiddenAppSearchesByNewName(_ root: URL) throws {
    let fixture = try Fixture(root: root, name: "hidden-search-rename")
    let (store, tool) = try seedHiddenSearch(fixture)
    store.showHiddenAppsInSearch = true
    store.setCustomTitle("Wrench", for: tool)
    try expect(occurrences(of: tool, in: store.search("Wrench")) == 1,
               "renaming a hidden app did not update its search name")
    store.rescan()
    try finishScan(store)
    try expect(occurrences(of: tool, in: store.search("Wrench")) == 1
               && occurrences(of: tool, in: store.items) == 0,
               "a rescan lost the hidden app's new name")
}

let root = URL(fileURLWithPath: CommandLine.arguments[1])
try FileManager.default.createDirectory(at: root, withIntermediateDirectories: true)
let tests: [(String, (URL) throws -> Void)] = [
    ("rename before metadata read survives scan", { try testTitleChangeDuringScan($0, initial: "Old", replacement: "New", afterMetadata: false) }),
    ("rename after metadata read survives scan", { try testTitleChangeDuringScan($0, initial: "Old", replacement: "New") }),
    ("clearing title during scan restores default name", { try testTitleChangeDuringScan($0, initial: "Old", replacement: "") }),
    ("new title after metadata read survives scan", { try testTitleChangeDuringScan($0, initial: "", replacement: "New") }),
    ("folder member rename survives scan", { try testTitleChangeDuringScan($0, initial: "Old", replacement: "New", inFolder: true) }),
    ("saved alias rename updates canonical discovery name", { try testTitleChangeDuringScan($0, initial: "Old", replacement: "New", alias: true) }),
    ("clearing saved alias title restores target default", { try testTitleChangeDuringScan($0, initial: "Old", replacement: "", alias: true) }),
    ("app suffix stays normalized after scan", { try testTitleChangeDuringScan($0, initial: "Old", replacement: "Notes.app", expectedName: "Notes") }),
    ("uppercase app suffix stays normalized in a folder", { try testTitleChangeDuringScan($0, initial: "Old", replacement: "Notes.APP", inFolder: true, expectedName: "Notes") }),
    ("suffix-only title falls back to the default", { try testTitleChangeDuringScan($0, initial: "Old", replacement: ".app", expectedName: "Visible") }),
    ("cold launch skips unreadable subtree", testColdUnreadableSource),
    ("built-in source preserves layout and recovers", { try testPreservedLayout($0, custom: false) }),
    ("custom source preserves layout and recovers", { try testPreservedLayout($0, custom: true) }),
    ("restart loads persisted layout while unreadable", testRestartWhileUnreadable),
    ("legacy restart preserves inaccessible applications", testLegacyRestartWhileUnreadable),
    ("distinct error and inventory path spellings match", testReportedPathAliases),
    ("real removals are reconciled after access recovers", testActualRemoval),
    ("unavailable custom root preserves inventory", testUnavailableCustomRoot),
    ("failed initial scan clears loading state", testFailedInitialCompletion),
    ("first successful stale scan refreshes folder placeholders", testFolderMetadataAfterFailedInitialScan),
    ("unreadable app links preserve layout and allow discoveries", { try testExternalLinksWhileUnreadable($0, restart: false) }),
    ("restart preserves external app links in unreadable directories", { try testExternalLinksWhileUnreadable($0, restart: true) }),
    ("complete scan removes apps after source links are deleted", testExternalLinkRemovalAfterCompleteScan),
    ("partial scan still cleans up deleted readable applications", testReadableRemovalDuringPartialScan),
    ("partial scan preserves imported items outside app inventory", testLoadedItemOutsideAppInventory),
    ("source and target permission errors preserve running layout", { try testInaccessibleExternalTargets($0, restart: false) }),
    ("source and target permission errors preserve restarted layout", { try testInaccessibleExternalTargets($0, restart: true) }),
    ("offline source does not retain deleted readable links", { try testDeletedLinkDuringUnrelatedPartialScan($0, offlineSource: true) }),
    ("unreadable subtree does not retain deleted readable links", { try testDeletedLinkDuringUnrelatedPartialScan($0, offlineSource: false) }),
    ("real API removes ordinary source alongside offline source", { try testRemoveOrdinarySourceDuringPartialScan($0, offlineSource: true) }),
    ("real API removes ordinary source alongside unreadable subtree", { try testRemoveOrdinarySourceDuringPartialScan($0, offlineSource: false) }),
    ("real API removes linked source alongside offline source", { try testRemoveLinkedSourceWithOfflineRoot($0) }),
    ("restart uses persisted origins to remove a deleted link", { try testDiscoveryOriginsSurviveRestart($0, removeSource: false) }),
    ("restart removes a source before scanning by using persisted origins", { try testDiscoveryOriginsSurviveRestart($0, removeSource: true) }),
    ("source removal invalidates an in-flight scan", testSourceRemovalInvalidatesInFlightScan),
    ("restart removes a persisted path alias before its first scan", testPersistedPathAliasRemovedBeforeFirstScan),
    ("directory-alias permission failure preserves saved layout and recovery", testDirectoryAliasPermissionPreservesLayout),
    ("import supersedes an in-flight reset without losing its layout", testImportSupersedesInFlightReset),
    ("shared target survives removal of one source", { try testSharedTargetSurvivesOneSourceRemoval($0, targetInsideSource: false) }),
    ("target inside removed source survives through another source", { try testSharedTargetSurvivesOneSourceRemoval($0, targetInsideSource: true) }),
    ("legacy layout without discovery index survives source permission error", { try testLegacyLayoutWithoutDiscoveryIndex($0, inaccessibleTarget: false) }),
    ("legacy layout without discovery index survives target permission error", { try testLegacyLayoutWithoutDiscoveryIndex($0, inaccessibleTarget: true) }),
    ("explicit source removal overrides unresolved legacy candidates", testExplicitRemovalOverridesLegacyPendingSource),
    ("legacy ordinary source removal survives partial scans and restart", { try testLegacySourceRemovalDuringPermanentPartialScan($0, linked: false) }),
    ("legacy linked source removal survives partial scans and restart", { try testLegacySourceRemovalDuringPermanentPartialScan($0, linked: true) }),
    ("removing an unconfirmed legacy candidate does not remove an unrelated app", testRemovingUnconfirmedCandidateDoesNotRemoveLegacyApp),
    ("target-only permission error preserves running layout and recovery", { try testOnlyExternalTargetsInaccessible($0, restart: false) }),
    ("target-only permission error preserves restarted layout and recovery", { try testOnlyExternalTargetsInaccessible($0, restart: true) }),
    ("page entries preserve application names in cold folder placeholders", { try testColdFolderPlaceholderNames($0, legacy: false) }),
    ("legacy entries preserve application names in cold folder placeholders", { try testColdFolderPlaceholderNames($0, legacy: true) }),
    ("window show preserves unlink cleanup alongside offline source", { try testDeletedLinkDuringUnrelatedPartialScan($0, offlineSource: true, openWindow: true) }),
    ("window show preserves unlink cleanup alongside unreadable subtree", { try testDeletedLinkDuringUnrelatedPartialScan($0, offlineSource: false, openWindow: true) }),
    ("window show preserves real API removal of an external linked target", { try testRemoveLinkedSourceWithOfflineRoot($0, openWindow: true) }),
    ("recent window show preserves discovery without starting a scan", testRecentWindowShowPreservesDiscovery),
    ("stale window show starts exactly one scan", testStaleWindowShowStartsOneScan),
    ("window show does not restart an in-flight scan", testWindowShowDoesNotRestartInFlightScan),
    ("custom source replaced by a file preserves layout and recovers", { try testSourceReplacedByFile($0, custom: true) }),
    ("built-in source replaced by a file preserves layout and recovers", { try testSourceReplacedByFile($0, custom: false) }),
    ("link replacing an app during a scan keeps both applications", testLinkReplacingAppDuringScan),
    ("persistent retryable error after restart does not rescan or rewrite layout", { try testPersistentRetryableError($0, restart: true) }),
    ("persistent retryable error on stale window show does not rescan or rewrite layout", { try testPersistentRetryableError($0, restart: false) }),
    ("superseded scan reruns with its own reasons", testSupersededScanKeepsReasons),
    ("superseded initial scan keeps the loading screen", testSupersededInitialScanKeepsLoading),
    ("display names follow indexed applications", testDisplayNamesFollowIndexedTargets),
    ("source whose root is a link discovers and removes its apps", testLinkedSourceRoot),
    ("source app listing follows discovery links like removal", testSourceListingMatchesRemoval),
    ("deleted linked app directory is removed on a mounted volume", testDeletedLinkedAppDirectory),
    ("linked apps keep their positions while their drive is unplugged", testLinkedAppsOnUnpluggedDrive),
    ("linked apps keep their positions when another drive mounts at their path", testSameNamedDriveAtSamePath),
    ("hidden apps stay out of the grid and of search by default", testHiddenAppsStayOutOfSearchByDefault),
    ("enabled search offers hidden apps only for search text", testHiddenAppsAppearOnlyForSearchText),
    ("hidden search results follow hide, unhide, rescan and restart", testHiddenSearchFollowsHideUnhideAndRescans),
    ("hidden folder member is searchable once and leaves its folder", testHiddenFolderMemberSearch),
    ("hidden app reached through a link and a source appears once", testLinkedHiddenAppAppearsOnce),
    ("uninstalled hidden app leaves search", testUninstalledHiddenAppLeavesSearch),
    ("removing a source takes its hidden apps out of search", testRemovedSourceTakesHiddenAppsFromSearch),
    ("hidden app on an unplugged drive leaves search until it returns", testOfflineHiddenAppLeavesSearchUntilDriveReturns),
    ("hidden apps keep pinyin search through the index", testHiddenAppsKeepTransliteratedSearch),
    ("imported hidden apps update search", testImportedHiddenAppsUpdateSearch),
    ("renamed hidden app is found by its new name", testRenamedHiddenAppSearchesByNewName)
]
var failures = 0
var skipped = 0
for (name, test) in tests {
    do {
        try test(root)
        print("PASS \(name)")
    } catch let reason as TestSkip {
        skipped += 1
        print("SKIP \(name): \(reason)")
    } catch {
        failures += 1
        print("FAIL \(name): \(error)")
    }
}
print("SUMMARY \(tests.count - failures - skipped)/\(tests.count) checks passed; \(skipped) skipped")
exit(failures == 0 ? 0 : 1)
