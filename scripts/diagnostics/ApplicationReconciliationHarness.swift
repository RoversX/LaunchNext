import AppKit
import Foundation
import SwiftData

// This file is a template consumed by test-application-reconciliation.py.
// Scanner, layout, placeholder, and persistence methods are extracted unchanged
// from AppStore.swift. Only unrelated UI/icon/cache behavior is adapted below.
// INSERT_PRODUCTION_MODELS

struct AppInfo: Hashable {
    var name: String
    var icon = NSImage(size: .zero)
    var url: URL
    static func == (lhs: AppInfo, rhs: AppInfo) -> Bool { lhs.url == rhs.url }
    func hash(into hasher: inout Hasher) { hasher.combine(url.path) }
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
    var apps: [AppInfo] = []
    var folders: [FolderInfo] = []
    var items: [LaunchpadItem] = []
    var isInitialLoading = true
    var hasPerformedInitialScan = false
    var hasAppliedOrderFromStore = true
    private var applicationReconciliationReasons: Set<ApplicationReconciliationReason> = []
    var applicationReconciliationInProgress = false
    var applicationReconciliationWorkItem: DispatchWorkItem?
    var lastSuccessfulApplicationReconciliationAt: Date?
    var needsReconciliationAfterExternalUninstall = false
    private var unavailableApplicationDirectories = Set<String>()
    private var retainedUnscannedApplicationPaths = Set<String>()
    static let applicationReconciliationEventDebounce: TimeInterval = 1.0
    let cacheManager = CacheAdapter()
    var itemsPerPage = 6
    var gridColumnsPerPage = 3
    var gridRowsPerPage = 2
    var currentPage = 0
    var openFolder: FolderInfo?
    var hiddenAppPaths = Set<String>()
    var missingPlaceholders: [String: MissingAppPlaceholder] = [:]
    var modelContext: ModelContext?

    func appInfo(from url: URL, preferredName: String? = nil) -> AppInfo {
        AppInfo(name: preferredName ?? url.deletingPathExtension().lastPathComponent, url: url)
    }
    func triggerFolderUpdate() {}
    func triggerGridRefresh() {}
    func rescan() { requestApplicationReconciliation(reason: .explicit) }
    func staleRescan() { requestApplicationReconciliation(reason: .staleWindowFallback) }
    func finishFailedInitialScan() {
        applicationReconciliationInProgress = true
        finishApplicationReconciliation(reasons: [.initial], succeeded: false)
    }

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
    let fileManager = FileManager.default
    var originalLayout: [SavedSlot] = []
    var reportedUnavailablePaths: [String] = []

    init(root: URL, name: String, customSource: Bool = false) throws {
        directory = root.appendingPathComponent(name)
        source = directory.appendingPathComponent("Applications")
        restricted = source.appendingPathComponent("Restricted")
        self.customSource = customSource
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
        let store = ProbeStore()
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

let root = URL(fileURLWithPath: CommandLine.arguments[1])
try FileManager.default.createDirectory(at: root, withIntermediateDirectories: true)
let tests: [(String, (URL) throws -> Void)] = [
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
    ("source and target permission errors preserve restarted layout", { try testInaccessibleExternalTargets($0, restart: true) })
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
