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

    @objc private func handleHideAppFromContextMenu(_ sender: NSMenuItem) {
        guard let app = contextMenuTargetApp else { return }
        onHideApp?(app)
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
