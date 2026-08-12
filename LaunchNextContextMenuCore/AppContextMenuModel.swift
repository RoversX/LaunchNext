public enum AppContextMenuSurface: Equatable {
    case swiftUIMainGrid
    case coreAnimationMainGrid
    case coreAnimationFolderGrid
}

public enum AppContextMenuAppContainer: Equatable {
    case mainGrid
    case folder(id: String, isPinned: Bool)
}

public enum AppContextMenuTarget: Equatable {
    case app(container: AppContextMenuAppContainer)
    case folder
}

public enum AppContextMenuAction: Hashable {
    case showInFinder
    case copyPath
    case removeQuarantine
    case hideApp
    case uninstallWithConfiguredTool
    case startBatchSelection
    case finishBatchSelection
    case pinToFolderQuickLaunchTop
    case unpinFromFolderQuickLaunchTop
    case launchFolderApp(path: String)
    case renameFolder
    case dissolveFolder
}

public enum AppContextMenuTitleKey: Equatable {
    case showInFinder
    case copyAppPath
    case removeQuarantineInTerminal
    case hideApp
    case uninstallWithConfiguredTool
    case batchSelectApps
    case finishBatchSelection
    case pinToFolderQuickLaunchTop
    case unpinFromFolderQuickLaunchTop
    case renameFolder
    case dissolveFolder
}

public enum AppContextMenuTitle: Equatable {
    case localized(AppContextMenuTitleKey)
    case verbatim(String)
}

public enum AppContextMenuRole: Equatable {
    case normal
    case destructive
}

public struct AppContextMenuItem: Equatable {
    public let action: AppContextMenuAction
    public let title: AppContextMenuTitle
    public let symbolName: String?
    public let role: AppContextMenuRole

    init(
        action: AppContextMenuAction,
        title: AppContextMenuTitle,
        symbolName: String?,
        role: AppContextMenuRole
    ) {
        self.action = action
        self.title = title
        self.symbolName = symbolName
        self.role = role
    }
}

public enum AppContextMenuEntry: Equatable {
    case action(AppContextMenuItem)
    case quickLaunch(AppContextMenuItem)
    case separator

    public var item: AppContextMenuItem? {
        switch self {
        case .action(let item), .quickLaunch(let item):
            return item
        case .separator:
            return nil
        }
    }
}

public struct AppContextMenuQuickLaunchApp: Equatable {
    public let path: String
    public let name: String
    public let isPinned: Bool

    public init(path: String, name: String, isPinned: Bool) {
        self.path = path
        self.name = name
        self.isPinned = isPinned
    }
}

public struct AppContextMenuCapabilities: Equatable {
    public var showQuarantineRemovalAction: Bool
    public var canUseConfiguredUninstallTool: Bool
    public var allowsBatchSelection: Bool
    public var isBatchSelectionActive: Bool
    public var folderQuickLaunchEnabled: Bool
    public var folderQuickLaunchPinningEnabled: Bool
    public var quickLaunchApps: [AppContextMenuQuickLaunchApp]

    public init(
        showQuarantineRemovalAction: Bool = false,
        canUseConfiguredUninstallTool: Bool = false,
        allowsBatchSelection: Bool = false,
        isBatchSelectionActive: Bool = false,
        folderQuickLaunchEnabled: Bool = false,
        folderQuickLaunchPinningEnabled: Bool = false,
        quickLaunchApps: [AppContextMenuQuickLaunchApp] = []
    ) {
        self.showQuarantineRemovalAction = showQuarantineRemovalAction
        self.canUseConfiguredUninstallTool = canUseConfiguredUninstallTool
        self.allowsBatchSelection = allowsBatchSelection
        self.isBatchSelectionActive = isBatchSelectionActive
        self.folderQuickLaunchEnabled = folderQuickLaunchEnabled
        self.folderQuickLaunchPinningEnabled = folderQuickLaunchPinningEnabled
        self.quickLaunchApps = quickLaunchApps
    }
}

public enum AppContextMenuBuilder {
    public static func entries(
        for target: AppContextMenuTarget,
        surface: AppContextMenuSurface,
        capabilities: AppContextMenuCapabilities
    ) -> [AppContextMenuEntry] {
        let entries: [AppContextMenuEntry]
        switch target {
        case .app(let container):
            entries = appEntries(container: container, surface: surface, capabilities: capabilities)
        case .folder:
            entries = folderEntries(surface: surface, capabilities: capabilities)
        }
        return normalized(entries)
    }

    private static func appEntries(
        container: AppContextMenuAppContainer,
        surface: AppContextMenuSurface,
        capabilities: AppContextMenuCapabilities
    ) -> [AppContextMenuEntry] {
        var entries: [AppContextMenuEntry] = [
            item(.showInFinder, .showInFinder, symbol: "folder"),
            item(.copyPath, .copyAppPath, symbol: "doc.on.doc")
        ]

        if capabilities.showQuarantineRemovalAction {
            entries.append(item(.removeQuarantine, .removeQuarantineInTerminal, symbol: "terminal"))
        }

        if case .folder(_, let isPinned) = container,
           surface == .coreAnimationFolderGrid,
           capabilities.folderQuickLaunchPinningEnabled {
            entries.append(.separator)
            entries.append(
                isPinned
                    ? item(.unpinFromFolderQuickLaunchTop, .unpinFromFolderQuickLaunchTop, symbol: "pin.slash")
                    : item(.pinToFolderQuickLaunchTop, .pinToFolderQuickLaunchTop, symbol: "pin")
            )
        }

        entries.append(.separator)
        entries.append(item(.hideApp, .hideApp, symbol: "eye.slash"))

        if surface == .coreAnimationMainGrid, capabilities.allowsBatchSelection {
            entries.append(.separator)
            entries.append(
                capabilities.isBatchSelectionActive
                    ? item(.finishBatchSelection, .finishBatchSelection, symbol: "checkmark.circle")
                    : item(.startBatchSelection, .batchSelectApps, symbol: "checklist")
            )
        }

        if capabilities.canUseConfiguredUninstallTool {
            entries.append(.separator)
            entries.append(
                item(
                    .uninstallWithConfiguredTool,
                    .uninstallWithConfiguredTool,
                    symbol: "trash",
                    role: .destructive
                )
            )
        }
        return entries
    }

    private static func folderEntries(
        surface: AppContextMenuSurface,
        capabilities: AppContextMenuCapabilities
    ) -> [AppContextMenuEntry] {
        var entries: [AppContextMenuEntry] = []

        if surface == .coreAnimationMainGrid, capabilities.folderQuickLaunchEnabled {
            let pinnedApps = capabilities.quickLaunchApps.filter(\.isPinned)
            let unpinnedApps = capabilities.quickLaunchApps.filter { !$0.isPinned }
            entries.append(contentsOf: pinnedApps.map { quickLaunchItem($0) })
            if !pinnedApps.isEmpty, !unpinnedApps.isEmpty {
                entries.append(.separator)
            }
            entries.append(contentsOf: unpinnedApps.map { quickLaunchItem($0) })
            if !capabilities.quickLaunchApps.isEmpty {
                entries.append(.separator)
            }
        }

        entries.append(item(.renameFolder, .renameFolder, symbol: "pencil"))
        entries.append(.separator)
        entries.append(
            item(
                .dissolveFolder,
                .dissolveFolder,
                symbol: "folder.badge.minus",
                role: .destructive
            )
        )
        return entries
    }

    private static func quickLaunchItem(_ app: AppContextMenuQuickLaunchApp) -> AppContextMenuEntry {
        .quickLaunch(
            AppContextMenuItem(
                action: .launchFolderApp(path: app.path),
                title: .verbatim(app.name),
                symbolName: app.isPinned ? "pin.fill" : nil,
                role: .normal
            )
        )
    }

    private static func item(
        _ action: AppContextMenuAction,
        _ titleKey: AppContextMenuTitleKey,
        symbol: String,
        role: AppContextMenuRole = .normal
    ) -> AppContextMenuEntry {
        .action(
            AppContextMenuItem(
                action: action,
                title: .localized(titleKey),
                symbolName: symbol,
                role: role
            )
        )
    }

    private static func normalized(_ entries: [AppContextMenuEntry]) -> [AppContextMenuEntry] {
        var result: [AppContextMenuEntry] = []
        for entry in entries {
            if entry == .separator, result.isEmpty || result.last == .separator {
                continue
            }
            result.append(entry)
        }
        if result.last == .separator {
            result.removeLast()
        }
        return result
    }
}

public enum AppContextMenuRuntimeTarget<App, Folder> {
    case app(App, folderID: String?)
    case folder(Folder)
}

extension AppContextMenuRuntimeTarget: Equatable where App: Equatable, Folder: Equatable {}

public enum AppContextMenuRoute<App, Folder> {
    case showInFinder(App)
    case copyPath(App)
    case removeQuarantine(App)
    case hideApp(App)
    case uninstallWithConfiguredTool(App)
    case startBatchSelection
    case finishBatchSelection
    case pinToFolderQuickLaunchTop(App, folderID: String)
    case unpinFromFolderQuickLaunchTop(App, folderID: String)
    case launchFolderApp(path: String, folder: Folder)
    case renameFolder(Folder)
    case dissolveFolder(Folder)
}

extension AppContextMenuRoute: Equatable where App: Equatable, Folder: Equatable {}

@MainActor
public protocol AppContextMenuRouteHandling: AnyObject {
    associatedtype App
    associatedtype Folder

    func showInFinder(_ app: App)
    func copyPath(_ app: App)
    func removeQuarantine(_ app: App)
    func hideApp(_ app: App)
    func uninstallWithConfiguredTool(_ app: App)
    func startBatchSelection()
    func finishBatchSelection()
    func pinToFolderQuickLaunchTop(_ app: App, folderID: String)
    func unpinFromFolderQuickLaunchTop(_ app: App, folderID: String)
    func launchFolderApp(path: String, folder: Folder)
    func renameFolder(_ folder: Folder)
    func dissolveFolder(_ folder: Folder)
}

public enum AppContextMenuRouter {
    public static func route<App, Folder>(
        action: AppContextMenuAction,
        target: AppContextMenuRuntimeTarget<App, Folder>
    ) -> AppContextMenuRoute<App, Folder>? {
        switch (action, target) {
        case (.showInFinder, .app(let app, _)):
            return .showInFinder(app)
        case (.copyPath, .app(let app, _)):
            return .copyPath(app)
        case (.removeQuarantine, .app(let app, _)):
            return .removeQuarantine(app)
        case (.hideApp, .app(let app, _)):
            return .hideApp(app)
        case (.uninstallWithConfiguredTool, .app(let app, _)):
            return .uninstallWithConfiguredTool(app)
        case (.startBatchSelection, .app):
            return .startBatchSelection
        case (.finishBatchSelection, .app):
            return .finishBatchSelection
        case (.pinToFolderQuickLaunchTop, .app(let app, let folderID)):
            guard let folderID else { return nil }
            return .pinToFolderQuickLaunchTop(app, folderID: folderID)
        case (.unpinFromFolderQuickLaunchTop, .app(let app, let folderID)):
            guard let folderID else { return nil }
            return .unpinFromFolderQuickLaunchTop(app, folderID: folderID)
        case (.launchFolderApp(let path), .folder(let folder)):
            return .launchFolderApp(path: path, folder: folder)
        case (.renameFolder, .folder(let folder)):
            return .renameFolder(folder)
        case (.dissolveFolder, .folder(let folder)):
            return .dissolveFolder(folder)
        default:
            return nil
        }
    }

    @MainActor
    @discardableResult
    public static func dispatch<Handler: AppContextMenuRouteHandling>(
        action: AppContextMenuAction,
        target: AppContextMenuRuntimeTarget<Handler.App, Handler.Folder>,
        to handler: Handler
    ) -> Bool {
        guard let route = route(action: action, target: target) else { return false }
        dispatch(route: route, to: handler)
        return true
    }

    @MainActor
    public static func dispatch<Handler: AppContextMenuRouteHandling>(
        route: AppContextMenuRoute<Handler.App, Handler.Folder>,
        to handler: Handler
    ) {
        switch route {
        case .showInFinder(let app):
            handler.showInFinder(app)
        case .copyPath(let app):
            handler.copyPath(app)
        case .removeQuarantine(let app):
            handler.removeQuarantine(app)
        case .hideApp(let app):
            handler.hideApp(app)
        case .uninstallWithConfiguredTool(let app):
            handler.uninstallWithConfiguredTool(app)
        case .startBatchSelection:
            handler.startBatchSelection()
        case .finishBatchSelection:
            handler.finishBatchSelection()
        case .pinToFolderQuickLaunchTop(let app, let folderID):
            handler.pinToFolderQuickLaunchTop(app, folderID: folderID)
        case .unpinFromFolderQuickLaunchTop(let app, let folderID):
            handler.unpinFromFolderQuickLaunchTop(app, folderID: folderID)
        case .launchFolderApp(let path, let folder):
            handler.launchFolderApp(path: path, folder: folder)
        case .renameFolder(let folder):
            handler.renameFolder(folder)
        case .dissolveFolder(let folder):
            handler.dissolveFolder(folder)
        }
    }
}

public struct AppContextMenuInvocation<App, Folder> {
    public let action: AppContextMenuAction
    public let target: AppContextMenuRuntimeTarget<App, Folder>

    public init(
        action: AppContextMenuAction,
        target: AppContextMenuRuntimeTarget<App, Folder>
    ) {
        self.action = action
        self.target = target
    }

    public var route: AppContextMenuRoute<App, Folder>? {
        AppContextMenuRouter.route(action: action, target: target)
    }

    @MainActor
    @discardableResult
    public func dispatch<Handler: AppContextMenuRouteHandling>(to handler: Handler) -> Bool
    where Handler.App == App, Handler.Folder == Folder {
        AppContextMenuRouter.dispatch(action: action, target: target, to: handler)
    }
}

extension AppContextMenuInvocation: Equatable where App: Equatable, Folder: Equatable {}
