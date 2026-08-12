import XCTest
import LaunchNextContextMenuCore

@MainActor
final class AppContextMenuTests: XCTestCase {
    private enum Token: Equatable {
        case action(AppContextMenuAction)
        case separator
    }

    func testSwiftUIAppMenuPreservesOptionalActionOrder() {
        let capabilities = AppContextMenuCapabilities(
            showQuarantineRemovalAction: true,
            canUseConfiguredUninstallTool: true
        )

        XCTAssertEqual(
            tokens(for: entries(target: .app(container: .mainGrid), surface: .swiftUIMainGrid, capabilities: capabilities)),
            [
                .action(.showInFinder),
                .action(.copyPath),
                .action(.removeQuarantine),
                .separator,
                .action(.hideApp),
                .separator,
                .action(.uninstallWithConfiguredTool)
            ]
        )
    }

    func testSwiftUIAppMenuOmitsDisabledOptionalActionsWithoutExtraSeparators() {
        XCTAssertEqual(
            tokens(for: entries(target: .app(container: .mainGrid), surface: .swiftUIMainGrid)),
            [
                .action(.showInFinder),
                .action(.copyPath),
                .separator,
                .action(.hideApp)
            ]
        )
    }

    func testCAMainGridBatchSelectionUsesCurrentMode() {
        var capabilities = AppContextMenuCapabilities(
            canUseConfiguredUninstallTool: true,
            allowsBatchSelection: true
        )

        XCTAssertEqual(
            tokens(for: entries(target: .app(container: .mainGrid), surface: .coreAnimationMainGrid, capabilities: capabilities)),
            [
                .action(.showInFinder),
                .action(.copyPath),
                .separator,
                .action(.hideApp),
                .separator,
                .action(.startBatchSelection),
                .separator,
                .action(.uninstallWithConfiguredTool)
            ]
        )

        capabilities.isBatchSelectionActive = true
        XCTAssertTrue(
            tokens(for: entries(target: .app(container: .mainGrid), surface: .coreAnimationMainGrid, capabilities: capabilities))
                .contains(.action(.finishBatchSelection))
        )
    }

    func testCAMainGridOmitsBatchSelectionWhenSearchDisablesIt() {
        let capabilities = AppContextMenuCapabilities(
            canUseConfiguredUninstallTool: true,
            allowsBatchSelection: false
        )

        XCTAssertEqual(
            tokens(for: entries(target: .app(container: .mainGrid), surface: .coreAnimationMainGrid, capabilities: capabilities)),
            [
                .action(.showInFinder),
                .action(.copyPath),
                .separator,
                .action(.hideApp),
                .separator,
                .action(.uninstallWithConfiguredTool)
            ]
        )
    }

    func testCAFolderGridShowsPinOrUnpinForCurrentState() {
        let capabilities = AppContextMenuCapabilities(
            showQuarantineRemovalAction: true,
            canUseConfiguredUninstallTool: true,
            folderQuickLaunchPinningEnabled: true
        )

        XCTAssertEqual(
            tokens(for: entries(
                target: .app(container: .folder(id: "folder", isPinned: false)),
                surface: .coreAnimationFolderGrid,
                capabilities: capabilities
            )),
            [
                .action(.showInFinder),
                .action(.copyPath),
                .action(.removeQuarantine),
                .separator,
                .action(.pinToFolderQuickLaunchTop),
                .separator,
                .action(.hideApp),
                .separator,
                .action(.uninstallWithConfiguredTool)
            ]
        )

        XCTAssertTrue(
            tokens(for: entries(
                target: .app(container: .folder(id: "folder", isPinned: true)),
                surface: .coreAnimationFolderGrid,
                capabilities: capabilities
            )).contains(.action(.unpinFromFolderQuickLaunchTop))
        )
    }

    func testSwiftUIFolderMenuDoesNotExposeCAQuickLaunch() {
        let capabilities = AppContextMenuCapabilities(
            folderQuickLaunchEnabled: true,
            quickLaunchApps: [
                .init(path: "/Applications/A.app", name: "A", isPinned: true)
            ]
        )

        XCTAssertEqual(
            tokens(for: entries(target: .folder, surface: .swiftUIMainGrid, capabilities: capabilities)),
            [
                .action(.renameFolder),
                .separator,
                .action(.dissolveFolder)
            ]
        )
    }

    func testCAFolderQuickLaunchGroupsPinnedAppsFirst() {
        let capabilities = AppContextMenuCapabilities(
            folderQuickLaunchEnabled: true,
            quickLaunchApps: [
                .init(path: "/Applications/B.app", name: "B", isPinned: false),
                .init(path: "/Applications/A.app", name: "A", isPinned: true),
                .init(path: "/Applications/C.app", name: "C", isPinned: false)
            ]
        )

        XCTAssertEqual(
            tokens(for: entries(target: .folder, surface: .coreAnimationMainGrid, capabilities: capabilities)),
            [
                .action(.launchFolderApp(path: "/Applications/A.app")),
                .separator,
                .action(.launchFolderApp(path: "/Applications/B.app")),
                .action(.launchFolderApp(path: "/Applications/C.app")),
                .separator,
                .action(.renameFolder),
                .separator,
                .action(.dissolveFolder)
            ]
        )
    }

    func testEmptyQuickLaunchListDoesNotCreateLeadingSeparator() {
        let capabilities = AppContextMenuCapabilities(folderQuickLaunchEnabled: true)

        XCTAssertEqual(
            tokens(for: entries(target: .folder, surface: .coreAnimationMainGrid, capabilities: capabilities)),
            [
                .action(.renameFolder),
                .separator,
                .action(.dissolveFolder)
            ]
        )
    }

    func testMenuMetadataMatchesExistingPresentation() throws {
        let capabilities = AppContextMenuCapabilities(
            showQuarantineRemovalAction: true,
            canUseConfiguredUninstallTool: true,
            allowsBatchSelection: true,
            folderQuickLaunchPinningEnabled: true
        )
        let appEntries = entries(
            target: .app(container: .folder(id: "folder", isPinned: false)),
            surface: .coreAnimationFolderGrid,
            capabilities: capabilities
        ) + entries(
            target: .app(container: .mainGrid),
            surface: .coreAnimationMainGrid,
            capabilities: capabilities
        )
        let folderEntries = entries(target: .folder, surface: .swiftUIMainGrid)

        let expectedMetadata: [AppContextMenuAction: (AppContextMenuTitle, String, AppContextMenuRole)] = [
            .showInFinder: (.localized(.showInFinder), "folder", .normal),
            .copyPath: (.localized(.copyAppPath), "doc.on.doc", .normal),
            .removeQuarantine: (.localized(.removeQuarantineInTerminal), "terminal", .normal),
            .hideApp: (.localized(.hideApp), "eye.slash", .normal),
            .uninstallWithConfiguredTool: (.localized(.uninstallWithConfiguredTool), "trash", .destructive),
            .startBatchSelection: (.localized(.batchSelectApps), "checklist", .normal),
            .pinToFolderQuickLaunchTop: (.localized(.pinToFolderQuickLaunchTop), "pin", .normal),
            .renameFolder: (.localized(.renameFolder), "pencil", .normal),
            .dissolveFolder: (.localized(.dissolveFolder), "folder.badge.minus", .destructive)
        ]

        for (action, metadata) in expectedMetadata {
            let descriptor = try XCTUnwrap(item(with: action, in: appEntries + folderEntries))
            XCTAssertEqual(descriptor.title, metadata.0, "Unexpected title for \(action)")
            XCTAssertEqual(descriptor.symbolName, metadata.1, "Unexpected symbol for \(action)")
            XCTAssertEqual(descriptor.role, metadata.2, "Unexpected role for \(action)")
        }

        var activeBatchCapabilities = capabilities
        activeBatchCapabilities.isBatchSelectionActive = true
        let finish = try XCTUnwrap(item(
            with: .finishBatchSelection,
            in: entries(
                target: .app(container: .mainGrid),
                surface: .coreAnimationMainGrid,
                capabilities: activeBatchCapabilities
            )
        ))
        XCTAssertEqual(finish.title, .localized(.finishBatchSelection))
        XCTAssertEqual(finish.symbolName, "checkmark.circle")
        XCTAssertEqual(finish.role, .normal)

        let unpin = try XCTUnwrap(item(
            with: .unpinFromFolderQuickLaunchTop,
            in: entries(
                target: .app(container: .folder(id: "folder", isPinned: true)),
                surface: .coreAnimationFolderGrid,
                capabilities: capabilities
            )
        ))
        XCTAssertEqual(unpin.title, .localized(.unpinFromFolderQuickLaunchTop))
        XCTAssertEqual(unpin.symbolName, "pin.slash")
        XCTAssertEqual(unpin.role, .normal)

        let quickLaunchCapabilities = AppContextMenuCapabilities(
            folderQuickLaunchEnabled: true,
            quickLaunchApps: [.init(path: "/Applications/A.app", name: "A", isPinned: true)]
        )
        let quickLaunch = try XCTUnwrap(item(
            with: .launchFolderApp(path: "/Applications/A.app"),
            in: entries(
                target: .folder,
                surface: .coreAnimationMainGrid,
                capabilities: quickLaunchCapabilities
            )
        ))
        XCTAssertEqual(quickLaunch.title, .verbatim("A"))
        XCTAssertEqual(quickLaunch.symbolName, "pin.fill")
        XCTAssertEqual(quickLaunch.role, .normal)
    }

    func testRouterMapsEveryActionToTheExpectedBusinessRoute() {
        typealias Target = AppContextMenuRuntimeTarget<String, String>
        typealias Route = AppContextMenuRoute<String, String>

        let appTarget = Target.app("Example", folderID: "folder-id")
        let folderTarget = Target.folder("Folder")
        let cases: [(AppContextMenuAction, Target, Route)] = [
            (.showInFinder, appTarget, .showInFinder("Example")),
            (.copyPath, appTarget, .copyPath("Example")),
            (.removeQuarantine, appTarget, .removeQuarantine("Example")),
            (.hideApp, appTarget, .hideApp("Example")),
            (.uninstallWithConfiguredTool, appTarget, .uninstallWithConfiguredTool("Example")),
            (.startBatchSelection, appTarget, .startBatchSelection),
            (.finishBatchSelection, appTarget, .finishBatchSelection),
            (.pinToFolderQuickLaunchTop, appTarget, .pinToFolderQuickLaunchTop("Example", folderID: "folder-id")),
            (.unpinFromFolderQuickLaunchTop, appTarget, .unpinFromFolderQuickLaunchTop("Example", folderID: "folder-id")),
            (.launchFolderApp(path: "/Applications/Example.app"), folderTarget, .launchFolderApp(path: "/Applications/Example.app", folder: "Folder")),
            (.renameFolder, folderTarget, .renameFolder("Folder")),
            (.dissolveFolder, folderTarget, .dissolveFolder("Folder"))
        ]

        let handler = RouteHandlerSpy()
        for (action, target, expectedRoute) in cases {
            let invocation = AppContextMenuInvocation(action: action, target: target)
            XCTAssertTrue(invocation.dispatch(to: handler), "Route was rejected for \(action)")
            XCTAssertEqual(handler.routes.removeLast(), expectedRoute, "Unexpected route for \(action)")
        }
        XCTAssertTrue(handler.routes.isEmpty)
    }

    func testRouterRejectsMismatchedTargetsAndMissingFolderID() {
        typealias Target = AppContextMenuRuntimeTarget<String, String>

        XCTAssertNil(AppContextMenuRouter.route(action: .showInFinder, target: Target.folder("Folder")))
        XCTAssertNil(AppContextMenuRouter.route(
            action: .pinToFolderQuickLaunchTop,
            target: Target.app("Example", folderID: nil)
        ))
        XCTAssertNil(AppContextMenuRouter.route(
            action: .renameFolder,
            target: Target.app("Example", folderID: nil)
        ))
    }

    private func entries(
        target: AppContextMenuTarget,
        surface: AppContextMenuSurface,
        capabilities: AppContextMenuCapabilities? = nil
    ) -> [AppContextMenuEntry] {
        AppContextMenuBuilder.entries(
            for: target,
            surface: surface,
            capabilities: capabilities ?? AppContextMenuCapabilities()
        )
    }

    private func tokens(for entries: [AppContextMenuEntry]) -> [Token] {
        entries.map { entry in
            switch entry {
            case .separator:
                return .separator
            case .action(let item), .quickLaunch(let item):
                return .action(item.action)
            }
        }
    }

    private func item(
        with action: AppContextMenuAction,
        in entries: [AppContextMenuEntry]
    ) -> AppContextMenuItem? {
        entries.compactMap(\.item).first { $0.action == action }
    }

    private final class RouteHandlerSpy: AppContextMenuRouteHandling {
        var routes: [AppContextMenuRoute<String, String>] = []

        func showInFinder(_ app: String) {
            routes.append(.showInFinder(app))
        }

        func copyPath(_ app: String) {
            routes.append(.copyPath(app))
        }

        func removeQuarantine(_ app: String) {
            routes.append(.removeQuarantine(app))
        }

        func hideApp(_ app: String) {
            routes.append(.hideApp(app))
        }

        func uninstallWithConfiguredTool(_ app: String) {
            routes.append(.uninstallWithConfiguredTool(app))
        }

        func startBatchSelection() {
            routes.append(.startBatchSelection)
        }

        func finishBatchSelection() {
            routes.append(.finishBatchSelection)
        }

        func pinToFolderQuickLaunchTop(_ app: String, folderID: String) {
            routes.append(.pinToFolderQuickLaunchTop(app, folderID: folderID))
        }

        func unpinFromFolderQuickLaunchTop(_ app: String, folderID: String) {
            routes.append(.unpinFromFolderQuickLaunchTop(app, folderID: folderID))
        }

        func launchFolderApp(path: String, folder: String) {
            routes.append(.launchFolderApp(path: path, folder: folder))
        }

        func renameFolder(_ folder: String) {
            routes.append(.renameFolder(folder))
        }

        func dissolveFolder(_ folder: String) {
            routes.append(.dissolveFolder(folder))
        }
    }
}
