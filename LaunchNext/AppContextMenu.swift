import AppKit
import LaunchNextContextMenuCore

typealias AppContextMenuRuntimeTarget = LaunchNextContextMenuCore.AppContextMenuRuntimeTarget<AppInfo, FolderInfo>
typealias AppContextMenuRoute = LaunchNextContextMenuCore.AppContextMenuRoute<AppInfo, FolderInfo>
typealias AppContextMenuInvocation = LaunchNextContextMenuCore.AppContextMenuInvocation<AppInfo, FolderInfo>

extension AppContextMenuTitleKey {
    var localizationKey: LocalizationKey {
        switch self {
        case .showInFinder:
            return .contextMenuShowInFinder
        case .copyAppPath:
            return .contextMenuCopyAppPath
        case .removeQuarantineInTerminal:
            return .contextMenuRemoveQuarantineInTerminal
        case .hideApp:
            return .hiddenAppsAddButton
        case .uninstallWithConfiguredTool:
            return .contextMenuUninstallWithConfiguredTool
        case .batchSelectApps:
            return .contextMenuBatchSelectApps
        case .finishBatchSelection:
            return .contextMenuFinishBatchSelection
        case .pinToFolderQuickLaunchTop:
            return .contextMenuPinToFolderQuickLaunchTop
        case .unpinFromFolderQuickLaunchTop:
            return .contextMenuUnpinFromFolderQuickLaunchTop
        case .renameFolder:
            return .contextMenuRenameFolder
        case .dissolveFolder:
            return .contextMenuDissolveFolder
        }
    }
}

struct AppContextMenuConfiguration {
    var localize: (AppContextMenuTitleKey) -> String = { $0.localizationKey.rawValue }
    var showQuarantineRemovalAction = false
    var canUseConfiguredUninstallTool = false
    var allowsBatchSelection = false
    var folderQuickLaunchEnabled = false
    var folderQuickLaunchPinningEnabled = false
    var orderedFolderQuickLaunchApps: (FolderInfo) -> [AppInfo] = { $0.apps }
    var isFolderQuickLaunchAppPinned: (FolderInfo, AppInfo) -> Bool = { folder, app in
        folder.pinnedAppPaths.contains(app.url.standardizedFileURL.path)
    }
    var isOpenFolderAppPinned: (AppInfo) -> Bool = { _ in false }

    func capabilities(
        for target: AppContextMenuTarget,
        folder: FolderInfo? = nil,
        isBatchSelectionActive: Bool = false
    ) -> AppContextMenuCapabilities {
        var capabilities = AppContextMenuCapabilities(
            showQuarantineRemovalAction: showQuarantineRemovalAction,
            canUseConfiguredUninstallTool: canUseConfiguredUninstallTool,
            allowsBatchSelection: allowsBatchSelection,
            isBatchSelectionActive: isBatchSelectionActive,
            folderQuickLaunchEnabled: folderQuickLaunchEnabled,
            folderQuickLaunchPinningEnabled: folderQuickLaunchPinningEnabled
        )

        if target == .folder, folderQuickLaunchEnabled, let folder {
            capabilities.quickLaunchApps = orderedFolderQuickLaunchApps(folder).map { app in
                AppContextMenuQuickLaunchApp(
                    path: app.url.path,
                    name: app.name,
                    isPinned: isFolderQuickLaunchAppPinned(folder, app)
                )
            }
        }
        return capabilities
    }

    func title(for title: AppContextMenuTitle) -> String {
        switch title {
        case .localized(let key):
            return localize(key)
        case .verbatim(let title):
            return title
        }
    }
}

@MainActor
private final class LaunchNextContextMenuRouteHandler: AppContextMenuRouteHandling {
    private let appStore: AppStore
    private let launchApp: ((AppInfo) -> Void)?

    init(appStore: AppStore, launchApp: ((AppInfo) -> Void)?) {
        self.appStore = appStore
        self.launchApp = launchApp
    }

    func showInFinder(_ app: AppInfo) {
        if !appStore.showAppInFinder(app) { NSSound.beep() }
    }

    func copyPath(_ app: AppInfo) {
        if !appStore.copyAppPath(app) { NSSound.beep() }
    }

    func removeQuarantine(_ app: AppInfo) {
        appStore.requestQuarantineRemovalInTerminal(for: app)
    }

    func hideApp(_ app: AppInfo) {
        _ = appStore.hideApp(app)
    }

    func uninstallWithConfiguredTool(_ app: AppInfo) {
        if !appStore.openConfiguredUninstallTool(for: app) { NSSound.beep() }
    }

    func startBatchSelection() {
        assertionFailure("Batch-selection routes must be handled by CAGridView")
    }

    func finishBatchSelection() {
        assertionFailure("Batch-selection routes must be handled by CAGridView")
    }

    func pinToFolderQuickLaunchTop(_ app: AppInfo, folderID: String) {
        _ = appStore.setFolderQuickLaunchAppPinned(true, app: app, inFolderID: folderID)
    }

    func unpinFromFolderQuickLaunchTop(_ app: AppInfo, folderID: String) {
        _ = appStore.setFolderQuickLaunchAppPinned(false, app: app, inFolderID: folderID)
    }

    func launchFolderApp(path: String, folder: FolderInfo) {
        guard let app = folder.apps.first(where: { $0.url.path == path }), let launchApp else {
            NSSound.beep()
            return
        }
        launchApp(app)
    }

    func renameFolder(_ folder: FolderInfo) {
        appStore.requestRenameFolder(folder)
    }

    func dissolveFolder(_ folder: FolderInfo) {
        _ = appStore.dissolveFolder(folder)
    }
}

@MainActor
func performAppContextMenuRoute(
    _ route: AppContextMenuRoute,
    appStore: AppStore,
    launchApp: ((AppInfo) -> Void)? = nil
) {
    let handler = LaunchNextContextMenuRouteHandler(appStore: appStore, launchApp: launchApp)
    AppContextMenuRouter.dispatch(route: route, to: handler)
}
