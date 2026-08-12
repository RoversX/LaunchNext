import SwiftUI
import AppKit
import LaunchNextContextMenuCore

private func redMenuSymbolImage(named symbolName: String) -> NSImage? {
    guard let base = NSImage(systemSymbolName: symbolName, accessibilityDescription: nil) else { return nil }
    let configured = base.withSymbolConfiguration(NSImage.SymbolConfiguration(paletteColors: [.systemRed])) ?? base
    configured.isTemplate = false
    return configured
}

extension LaunchpadItem {
    var contextMenuApp: AppInfo? {
        if case .app(let app) = self { return app }
        return nil
    }

    var contextMenuFolder: FolderInfo? {
        if case .folder(let folder) = self { return folder }
        return nil
    }
}

private struct SwiftUIContextMenuContent: View {
    let entries: [AppContextMenuEntry]
    let configuration: AppContextMenuConfiguration
    let runtimeTarget: AppContextMenuRuntimeTarget
    let appStore: AppStore

    var body: some View {
        ForEach(Array(entries.enumerated()), id: \.offset) { _, entry in
            switch entry {
            case .separator:
                Divider()
            case .action(let item), .quickLaunch(let item):
                menuButton(for: item)
            }
        }
    }

    @ViewBuilder
    private func menuButton(for item: AppContextMenuItem) -> some View {
        if item.role == .destructive {
            Button(role: .destructive) {
                perform(item.action)
            } label: {
                destructiveLabel(for: item)
            }
        } else {
            Button {
                perform(item.action)
            } label: {
                if let symbolName = item.symbolName {
                    Label(configuration.title(for: item.title), systemImage: symbolName)
                } else {
                    Text(configuration.title(for: item.title))
                }
            }
        }
    }

    @ViewBuilder
    private func destructiveLabel(for item: AppContextMenuItem) -> some View {
        if item.action == .uninstallWithConfiguredTool,
           let symbolName = item.symbolName,
           let redSymbol = redMenuSymbolImage(named: symbolName) {
            HStack(spacing: 6) {
                Image(nsImage: redSymbol)
                    .renderingMode(.original)
                Text(configuration.title(for: item.title))
                    .foregroundStyle(.red)
            }
        } else if let symbolName = item.symbolName {
            Label(configuration.title(for: item.title), systemImage: symbolName)
        } else {
            Text(configuration.title(for: item.title))
        }
    }

    private func perform(_ action: AppContextMenuAction) {
        guard let route = AppContextMenuRouter.route(action: action, target: runtimeTarget) else {
            assertionFailure("Unsupported context menu action for target")
            return
        }
        performAppContextMenuRoute(route, appStore: appStore)
    }
}

extension View {
    @ViewBuilder
    func launchNextHideAppContextMenu(app: AppInfo?, folder: FolderInfo? = nil, appStore: AppStore) -> some View {
        let configuration = AppContextMenuConfiguration(
            localize: { appStore.localized($0.localizationKey) },
            showQuarantineRemovalAction: appStore.showQuarantineRemovalAction,
            canUseConfiguredUninstallTool: appStore.uninstallToolAppURL != nil
        )

        if let app {
            let target = AppContextMenuTarget.app(container: .mainGrid)
            let entries = AppContextMenuBuilder.entries(
                for: target,
                surface: .swiftUIMainGrid,
                capabilities: configuration.capabilities(for: target)
            )
            contextMenu {
                SwiftUIContextMenuContent(
                    entries: entries,
                    configuration: configuration,
                    runtimeTarget: .app(app, folderID: nil),
                    appStore: appStore
                )
            }
        } else if let folder {
            let target = AppContextMenuTarget.folder
            let entries = AppContextMenuBuilder.entries(
                for: target,
                surface: .swiftUIMainGrid,
                capabilities: configuration.capabilities(for: target, folder: folder)
            )
            contextMenu {
                SwiftUIContextMenuContent(
                    entries: entries,
                    configuration: configuration,
                    runtimeTarget: .folder(folder),
                    appStore: appStore
                )
            }
        } else {
            self
        }
    }
}

private final class AppContextMenuInvocationBox: NSObject {
    let invocation: AppContextMenuInvocation

    init(action: AppContextMenuAction, target: AppContextMenuRuntimeTarget) {
        invocation = AppContextMenuInvocation(action: action, target: target)
    }
}

private func makeAppKitContextMenu(
    entries: [AppContextMenuEntry],
    configuration: AppContextMenuConfiguration,
    runtimeTarget: AppContextMenuRuntimeTarget,
    handlerTarget: AnyObject,
    action: Selector
) -> NSMenu {
    let menu = NSMenu(title: "")
    for entry in entries {
        switch entry {
        case .separator:
            menu.addItem(.separator())
        case .action(let descriptor), .quickLaunch(let descriptor):
            let title = configuration.title(for: descriptor.title)
            let item = NSMenuItem(title: title, action: action, keyEquivalent: "")
            item.target = handlerTarget
            item.representedObject = AppContextMenuInvocationBox(
                action: descriptor.action,
                target: runtimeTarget
            )
            if let symbolName = descriptor.symbolName {
                item.image = descriptor.role == .destructive
                    ? redMenuSymbolImage(named: symbolName)
                    : NSImage(systemSymbolName: symbolName, accessibilityDescription: title)
            }
            if descriptor.role == .destructive {
                item.attributedTitle = NSAttributedString(
                    string: title,
                    attributes: [.foregroundColor: NSColor.systemRed]
                )
            }
            menu.addItem(item)
        }
    }
    return menu
}

extension CAGridView {
    override func rightMouseDown(with event: NSEvent) {
        guard let menu = contextMenu(for: event) else {
            super.rightMouseDown(with: event)
            return
        }
        isContextMenuTracking = true
        defer { isContextMenuTracking = false }
        NSMenu.popUpContextMenu(menu, with: event, for: self)
    }

    override func menu(for event: NSEvent) -> NSMenu? {
        contextMenu(for: event)
    }

    private func contextMenu(for event: NSEvent) -> NSMenu? {
        guard !isDraggingItem, !isPageDragging else { return nil }
        let location = convert(event.locationInWindow, from: nil)
        guard let (item, _) = itemAt(location) else { return nil }

        let target: AppContextMenuTarget
        let runtimeTarget: AppContextMenuRuntimeTarget
        let folder: FolderInfo?
        switch item {
        case .app(let app):
            target = .app(container: .mainGrid)
            runtimeTarget = .app(app, folderID: nil)
            folder = nil
        case .folder(let selectedFolder):
            target = .folder
            runtimeTarget = .folder(selectedFolder)
            folder = selectedFolder
        default:
            return nil
        }

        let capabilities = contextMenuConfiguration.capabilities(
            for: target,
            folder: folder,
            isBatchSelectionActive: isBatchSelectionMode
        )
        let entries = AppContextMenuBuilder.entries(
            for: target,
            surface: .coreAnimationMainGrid,
            capabilities: capabilities
        )
        return makeAppKitContextMenu(
            entries: entries,
            configuration: contextMenuConfiguration,
            runtimeTarget: runtimeTarget,
            handlerTarget: self,
            action: #selector(handleContextMenuAction(_:))
        )
    }

    @objc private func handleContextMenuAction(_ sender: NSMenuItem) {
        guard let invocation = sender.representedObject as? AppContextMenuInvocationBox,
              let route = invocation.invocation.route else { return }
        switch route {
        case .startBatchSelection:
            enableBatchSelectionMode()
        case .finishBatchSelection:
            disableBatchSelectionMode()
        default:
            if let onContextMenuAction {
                onContextMenuAction(route)
            }
        }
    }
}

extension CAFolderGridView {
    override func rightMouseDown(with event: NSEvent) {
        guard let menu = folderContextMenu(for: event) else {
            super.rightMouseDown(with: event)
            return
        }
        isContextMenuTracking = true
        defer { isContextMenuTracking = false }
        NSMenu.popUpContextMenu(menu, with: event, for: self)
    }

    override func menu(for event: NSEvent) -> NSMenu? {
        folderContextMenu(for: event)
    }

    private func folderContextMenu(for event: NSEvent) -> NSMenu? {
        let location = convert(event.locationInWindow, from: nil)
        guard let index = contextMenuItemIndex(at: location), apps.indices.contains(index) else { return nil }

        let app = apps[index]
        let isPinned = contextMenuConfiguration.isOpenFolderAppPinned(app)
        let target = AppContextMenuTarget.app(
            container: .folder(id: contextMenuFolderID, isPinned: isPinned)
        )
        let entries = AppContextMenuBuilder.entries(
            for: target,
            surface: .coreAnimationFolderGrid,
            capabilities: contextMenuConfiguration.capabilities(for: target)
        )
        return makeAppKitContextMenu(
            entries: entries,
            configuration: contextMenuConfiguration,
            runtimeTarget: .app(app, folderID: contextMenuFolderID),
            handlerTarget: self,
            action: #selector(handleContextMenuAction(_:))
        )
    }

    @objc private func handleContextMenuAction(_ sender: NSMenuItem) {
        guard let invocation = sender.representedObject as? AppContextMenuInvocationBox,
              let route = invocation.invocation.route else { return }
        if let onContextMenuAction {
            onContextMenuAction(route)
        }
    }
}
