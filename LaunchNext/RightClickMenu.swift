import SwiftUI
import AppKit

// Shared right-click menu helpers for both SwiftUI and Core Animation renderers.

private func redMenuSymbolImage(named symbolName: String) -> NSImage? {
    guard let base = NSImage(systemSymbolName: symbolName, accessibilityDescription: nil) else { return nil }
    let configured = base.withSymbolConfiguration(NSImage.SymbolConfiguration(paletteColors: [.systemRed])) ?? base
    configured.isTemplate = false
    return configured
}

// Maps LaunchpadItem to AppInfo when a context menu action is app-specific.
extension LaunchpadItem {
    var contextMenuApp: AppInfo? {
        if case .app(let app) = self {
            return app
        }
        return nil
    }

    var contextMenuFolder: FolderInfo? {
        if case .folder(let folder) = self {
            return folder
        }
        return nil
    }
}

extension View {
    // Adds app-level context menu actions when the current tile is an app.
    @ViewBuilder
    func launchNextHideAppContextMenu(app: AppInfo?, folder: FolderInfo? = nil, appStore: AppStore) -> some View {
        if let app {
            contextMenu {
                Button {
                    if !appStore.showAppInFinder(app) {
                        NSSound.beep()
                    }
                } label: {
                    Label(appStore.localized(.contextMenuShowInFinder), systemImage: "folder")
                }

                Button {
                    if !appStore.copyAppPath(app) {
                        NSSound.beep()
                    }
                } label: {
                    Label(appStore.localized(.contextMenuCopyAppPath), systemImage: "doc.on.doc")
                }

                if appStore.showQuarantineRemovalAction {
                    Button {
                        appStore.requestQuarantineRemovalInTerminal(for: app)
                    } label: {
                        Label(appStore.localized(.contextMenuRemoveQuarantineInTerminal), systemImage: "terminal")
                    }
                }

                Divider()

                Button {
                    _ = appStore.hideApp(app)
                } label: {
                    Label(appStore.localized(.hiddenAppsAddButton), systemImage: "eye.slash")
                }

                if appStore.uninstallToolAppURL != nil {
                    Divider()
                    Button(role: .destructive) {
                        if !appStore.openConfiguredUninstallTool(for: app) {
                            NSSound.beep()
                        }
                    } label: {
                        HStack(spacing: 6) {
                            if let redTrash = redMenuSymbolImage(named: "trash") {
                                Image(nsImage: redTrash)
                                    .renderingMode(.original)
                            } else {
                                Image(systemName: "trash")
                                    .foregroundStyle(.red)
                            }
                            Text(appStore.localized(.contextMenuUninstallWithConfiguredTool))
                                .foregroundStyle(.red)
                        }
                    }
                }
            }
        } else if let folder {
            contextMenu {
                Button {
                    appStore.requestRenameFolder(folder)
                } label: {
                    Label(appStore.localized(.contextMenuRenameFolder), systemImage: "pencil")
                }

                Divider()

                Button(role: .destructive) {
                    _ = appStore.dissolveFolder(folder)
                } label: {
                    Label(appStore.localized(.contextMenuDissolveFolder), systemImage: "folder.badge.minus")
                }
            }
        } else {
            self
        }
    }
}

extension CAGridView {
    // AppKit path: build context menu manually for CA-rendered tiles.
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
        // Skip menu while dragging to avoid gesture conflicts.
        guard !isDraggingItem, !isPageDragging else { return nil }
        let location = convert(event.locationInWindow, from: nil)
        guard let (item, _) = itemAt(location) else { return nil }

        switch item {
        case .app(let app):
            // Keep the target app so action handler can execute hide.
            contextMenuTargetApp = app
            contextMenuTargetFolder = nil
            let menu = NSMenu(title: "")
            let showInFinderItem = NSMenuItem(
                title: showInFinderMenuTitle,
                action: #selector(handleShowAppInFinderFromContextMenu(_:)),
                keyEquivalent: ""
            )
            showInFinderItem.image = NSImage(systemSymbolName: "folder", accessibilityDescription: nil)
            showInFinderItem.target = self
            menu.addItem(showInFinderItem)

            let copyPathItem = NSMenuItem(
                title: copyAppPathMenuTitle,
                action: #selector(handleCopyAppPathFromContextMenu(_:)),
                keyEquivalent: ""
            )
            copyPathItem.image = NSImage(systemSymbolName: "doc.on.doc", accessibilityDescription: nil)
            copyPathItem.target = self
            menu.addItem(copyPathItem)

            if showQuarantineRemovalAction {
                let quarantineItem = NSMenuItem(
                    title: removeQuarantineMenuTitle,
                    action: #selector(handleRemoveQuarantineFromContextMenu(_:)),
                    keyEquivalent: ""
                )
                quarantineItem.image = NSImage(systemSymbolName: "terminal", accessibilityDescription: nil)
                quarantineItem.target = self
                menu.addItem(quarantineItem)
            }

            menu.addItem(NSMenuItem.separator())

            let hideItem = NSMenuItem(
                title: hideAppMenuTitle,
                action: #selector(handleHideAppFromContextMenu(_:)),
                keyEquivalent: ""
            )
            hideItem.image = NSImage(systemSymbolName: "eye.slash", accessibilityDescription: nil)
            hideItem.target = self
            menu.addItem(hideItem)

            if allowsBatchSelectionMode {
                menu.addItem(NSMenuItem.separator())
                let batchMenuTitle = isBatchSelectionMode ? finishBatchSelectionMenuTitle : batchSelectAppsMenuTitle
                let batchMenuAction = isBatchSelectionMode ? #selector(handleFinishBatchSelectionFromContextMenu(_:)) : #selector(handleStartBatchSelectionFromContextMenu(_:))
                let batchItem = NSMenuItem(
                    title: batchMenuTitle,
                    action: batchMenuAction,
                    keyEquivalent: ""
                )
                batchItem.image = NSImage(systemSymbolName: isBatchSelectionMode ? "checkmark.circle" : "checklist", accessibilityDescription: nil)
                batchItem.target = self
                menu.addItem(batchItem)
            }

            if canUseConfiguredUninstallTool {
                menu.addItem(NSMenuItem.separator())
                let uninstallItem = NSMenuItem(
                    title: uninstallWithToolMenuTitle,
                    action: #selector(handleUninstallWithToolFromContextMenu(_:)),
                    keyEquivalent: ""
                )
                uninstallItem.attributedTitle = NSAttributedString(
                    string: uninstallWithToolMenuTitle,
                    attributes: [.foregroundColor: NSColor.systemRed]
                )
                uninstallItem.image = redMenuSymbolImage(named: "trash")
                uninstallItem.target = self
                menu.addItem(uninstallItem)
            }
            return menu
        case .folder(let folder):
            contextMenuTargetApp = nil
            contextMenuTargetFolder = folder
            let menu = NSMenu(title: "")

            if folderQuickLaunchEnabled, !folder.apps.isEmpty {
                let quickLaunchApps = folderQuickLaunchAppsSorter?(folder) ?? folder.apps
                let pinnedApps = quickLaunchApps.filter {
                    isFolderQuickLaunchAppPinned?(folder, $0) ?? false
                }
                let unpinnedApps = quickLaunchApps.filter {
                    !(isFolderQuickLaunchAppPinned?(folder, $0) ?? false)
                }

                func addQuickLaunchItem(for app: AppInfo, pinned: Bool) {
                    let appItem = NSMenuItem(
                        title: app.name,
                        action: #selector(handleFolderQuickLaunchFromContextMenu(_:)),
                        keyEquivalent: ""
                    )
                    appItem.representedObject = app
                    if pinned {
                        appItem.image = NSImage(
                            systemSymbolName: "pin.fill",
                            accessibilityDescription: app.name
                        )
                    }
                    appItem.target = self
                    menu.addItem(appItem)
                }

                pinnedApps.forEach { addQuickLaunchItem(for: $0, pinned: true) }
                if !pinnedApps.isEmpty, !unpinnedApps.isEmpty {
                    menu.addItem(NSMenuItem.separator())
                }
                unpinnedApps.forEach { addQuickLaunchItem(for: $0, pinned: false) }
                menu.addItem(NSMenuItem.separator())
            }

            let renameItem = NSMenuItem(
                title: renameFolderMenuTitle,
                action: #selector(handleRenameFolderFromContextMenu(_:)),
                keyEquivalent: ""
            )
            renameItem.image = NSImage(systemSymbolName: "pencil", accessibilityDescription: nil)
            renameItem.target = self
            menu.addItem(renameItem)

            menu.addItem(NSMenuItem.separator())

            let dissolveItem = NSMenuItem(
                title: dissolveFolderMenuTitle,
                action: #selector(handleDissolveFolderFromContextMenu(_:)),
                keyEquivalent: ""
            )
            dissolveItem.attributedTitle = NSAttributedString(
                string: dissolveFolderMenuTitle,
                attributes: [.foregroundColor: NSColor.systemRed]
            )
            dissolveItem.image = redMenuSymbolImage(named: "folder.badge.minus")
            dissolveItem.target = self
            menu.addItem(dissolveItem)
            return menu
        default:
            contextMenuTargetApp = nil
            contextMenuTargetFolder = nil
            return nil
        }
    }

    @objc private func handleShowAppInFinderFromContextMenu(_ sender: NSMenuItem) {
        guard let app = contextMenuTargetApp else { return }
        onShowAppInFinder?(app)
        contextMenuTargetApp = nil
        contextMenuTargetFolder = nil
    }

    @objc private func handleCopyAppPathFromContextMenu(_ sender: NSMenuItem) {
        guard let app = contextMenuTargetApp else { return }
        onCopyAppPath?(app)
        contextMenuTargetApp = nil
        contextMenuTargetFolder = nil
    }

    @objc private func handleRemoveQuarantineFromContextMenu(_ sender: NSMenuItem) {
        guard let app = contextMenuTargetApp else { return }
        onRemoveQuarantineInTerminal?(app)
        contextMenuTargetApp = nil
        contextMenuTargetFolder = nil
    }

    @objc private func handleHideAppFromContextMenu(_ sender: NSMenuItem) {
        guard let app = contextMenuTargetApp else { return }
        onHideApp?(app)
        contextMenuTargetApp = nil
        contextMenuTargetFolder = nil
    }

    @objc private func handleFolderQuickLaunchFromContextMenu(_ sender: NSMenuItem) {
        guard let app = sender.representedObject as? AppInfo else { return }
        onFolderQuickLaunchApp?(app)
        contextMenuTargetApp = nil
        contextMenuTargetFolder = nil
    }

    @objc private func handleRenameFolderFromContextMenu(_ sender: NSMenuItem) {
        guard let folder = contextMenuTargetFolder else { return }
        onRenameFolder?(folder)
        contextMenuTargetApp = nil
        contextMenuTargetFolder = nil
    }

    @objc private func handleDissolveFolderFromContextMenu(_ sender: NSMenuItem) {
        guard let folder = contextMenuTargetFolder else { return }
        onDissolveFolder?(folder)
        contextMenuTargetApp = nil
        contextMenuTargetFolder = nil
    }

    @objc private func handleUninstallWithToolFromContextMenu(_ sender: NSMenuItem) {
        guard let app = contextMenuTargetApp else { return }
        onUninstallWithTool?(app)
        contextMenuTargetApp = nil
        contextMenuTargetFolder = nil
    }

    @objc private func handleStartBatchSelectionFromContextMenu(_ sender: NSMenuItem) {
        enableBatchSelectionMode()
        contextMenuTargetApp = nil
        contextMenuTargetFolder = nil
    }

    @objc private func handleFinishBatchSelectionFromContextMenu(_ sender: NSMenuItem) {
        disableBatchSelectionMode()
        contextMenuTargetApp = nil
        contextMenuTargetFolder = nil
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
        guard let index = contextMenuItemIndex(at: location), apps.indices.contains(index) else {
            contextMenuTargetApp = nil
            return nil
        }
        let app = apps[index]
        contextMenuTargetApp = app

        let menu = NSMenu(title: "")
        let showInFinderItem = NSMenuItem(
            title: showInFinderMenuTitle,
            action: #selector(handleFolderShowAppInFinderFromContextMenu(_:)),
            keyEquivalent: ""
        )
        showInFinderItem.image = NSImage(systemSymbolName: "folder", accessibilityDescription: nil)
        showInFinderItem.target = self
        menu.addItem(showInFinderItem)

        let copyPathItem = NSMenuItem(
            title: copyAppPathMenuTitle,
            action: #selector(handleFolderCopyAppPathFromContextMenu(_:)),
            keyEquivalent: ""
        )
        copyPathItem.image = NSImage(systemSymbolName: "doc.on.doc", accessibilityDescription: nil)
        copyPathItem.target = self
        menu.addItem(copyPathItem)

        if showQuarantineRemovalAction {
            let quarantineItem = NSMenuItem(
                title: removeQuarantineMenuTitle,
                action: #selector(handleFolderRemoveQuarantineFromContextMenu(_:)),
                keyEquivalent: ""
            )
            quarantineItem.image = NSImage(systemSymbolName: "terminal", accessibilityDescription: nil)
            quarantineItem.target = self
            menu.addItem(quarantineItem)
        }

        if folderQuickLaunchPinningEnabled {
            menu.addItem(NSMenuItem.separator())
            let isPinned = isFolderQuickLaunchAppPinned?(app) ?? false
            let pinItem = NSMenuItem(
                title: isPinned ? unpinFromFolderQuickLaunchTopMenuTitle : pinToFolderQuickLaunchTopMenuTitle,
                action: #selector(handleFolderQuickLaunchPinFromContextMenu(_:)),
                keyEquivalent: ""
            )
            pinItem.image = NSImage(
                systemSymbolName: isPinned ? "pin.slash" : "pin",
                accessibilityDescription: nil
            )
            pinItem.target = self
            menu.addItem(pinItem)
        }

        menu.addItem(NSMenuItem.separator())

        let hideItem = NSMenuItem(
            title: hideAppMenuTitle,
            action: #selector(handleFolderHideAppFromContextMenu(_:)),
            keyEquivalent: ""
        )
        hideItem.image = NSImage(systemSymbolName: "eye.slash", accessibilityDescription: nil)
        hideItem.target = self
        menu.addItem(hideItem)

        if canUseConfiguredUninstallTool {
            menu.addItem(NSMenuItem.separator())
            let uninstallItem = NSMenuItem(
                title: uninstallWithToolMenuTitle,
                action: #selector(handleFolderUninstallWithToolFromContextMenu(_:)),
                keyEquivalent: ""
            )
            uninstallItem.attributedTitle = NSAttributedString(
                string: uninstallWithToolMenuTitle,
                attributes: [.foregroundColor: NSColor.systemRed]
            )
            uninstallItem.image = redMenuSymbolImage(named: "trash")
            uninstallItem.target = self
            menu.addItem(uninstallItem)
        }
        return menu
    }

    @objc private func handleFolderShowAppInFinderFromContextMenu(_ sender: NSMenuItem) {
        guard let app = contextMenuTargetApp else { return }
        onShowAppInFinder?(app)
        contextMenuTargetApp = nil
    }

    @objc private func handleFolderCopyAppPathFromContextMenu(_ sender: NSMenuItem) {
        guard let app = contextMenuTargetApp else { return }
        onCopyAppPath?(app)
        contextMenuTargetApp = nil
    }

    @objc private func handleFolderRemoveQuarantineFromContextMenu(_ sender: NSMenuItem) {
        guard let app = contextMenuTargetApp else { return }
        onRemoveQuarantineInTerminal?(app)
        contextMenuTargetApp = nil
    }

    @objc private func handleFolderHideAppFromContextMenu(_ sender: NSMenuItem) {
        guard let app = contextMenuTargetApp else { return }
        onHideApp?(app)
        contextMenuTargetApp = nil
    }

    @objc private func handleFolderQuickLaunchPinFromContextMenu(_ sender: NSMenuItem) {
        guard let app = contextMenuTargetApp else { return }
        let isPinned = isFolderQuickLaunchAppPinned?(app) ?? false
        onSetFolderQuickLaunchAppPinned?(app, !isPinned)
        contextMenuTargetApp = nil
    }

    @objc private func handleFolderUninstallWithToolFromContextMenu(_ sender: NSMenuItem) {
        guard let app = contextMenuTargetApp else { return }
        onUninstallWithTool?(app)
        contextMenuTargetApp = nil
    }
}
