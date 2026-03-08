import AppKit
import SwiftUI

// MARK: - SwiftUI Wrapper

struct CAGridViewRepresentable: NSViewRepresentable {
    @ObservedObject var appStore: AppStore
    var items: [LaunchpadItem]  // 支持传入过滤后的 items
    var iconSize: CGFloat
    var columnSpacing: CGFloat
    var rowSpacing: CGFloat
    var contentInsets: NSEdgeInsets
    var pageSpacing: CGFloat
    var onOpenApp: ((AppInfo) -> Void)?
    var onOpenFolder: ((FolderInfo) -> Void)?
    var externalDragSourceIndex: Int?
    var externalDragHoverIndex: Int?
    var selectedIndex: Int?

    // 监听这些触发器来强制刷新
    var gridRefreshTrigger: UUID { appStore.gridRefreshTrigger }
    var folderUpdateTrigger: UUID { appStore.folderUpdateTrigger }
    var iconCacheRefreshTrigger: UUID { appStore.iconCacheRefreshTrigger }

    func makeNSView(context: Context) -> CAGridView {
        let view = CAGridView(frame: .zero)

        // Initialize configuration
        view.columns = appStore.gridColumnsPerPage
        view.rows = appStore.gridRowsPerPage
        view.iconSize = iconSize
        view.columnSpacing = columnSpacing
        view.rowSpacing = rowSpacing
        view.contentInsets = contentInsets
        view.pageSpacing = pageSpacing
        view.labelFontSize = CGFloat(appStore.iconLabelFontSize)
        view.labelFontWeight = nsFontWeight(for: appStore.iconLabelFontWeight)
        view.showLabels = appStore.showLabels
        view.isLayoutLocked = appStore.isLayoutLocked
        view.folderDropZoneScale = CGFloat(appStore.folderDropZoneScale)
        let preferredScale = nsViewScale(for: view)
        view.folderPreviewScale = appStore.enableHighResFolderPreviews ? preferredScale : 1
        view.enableIconPreload = false
        view.scrollSensitivity = appStore.scrollSensitivity
        view.reverseWheelPagingDirection = appStore.reverseWheelPagingDirection
        view.hoverMagnificationEnabled = appStore.enableHoverMagnification
        view.hoverMagnificationScale = CGFloat(appStore.hoverMagnificationScale)
        view.activePressEffectEnabled = appStore.enableActivePressEffect
        view.activePressScale = CGFloat(appStore.activePressScale)
        view.animationsEnabled = appStore.enableAnimations
        view.animationDuration = appStore.animationDuration
        view.hideAppMenuTitle = appStore.localized(.hiddenAppsAddButton)
        view.dissolveFolderMenuTitle = appStore.localized(.contextMenuDissolveFolder)
        view.uninstallWithToolMenuTitle = appStore.localized(.contextMenuUninstallWithConfiguredTool)
        view.batchSelectAppsMenuTitle = appStore.localized(.contextMenuBatchSelectApps)
        view.finishBatchSelectionMenuTitle = appStore.localized(.contextMenuFinishBatchSelection)
        view.canUseConfiguredUninstallTool = appStore.uninstallToolAppURL != nil
        view.allowsBatchSelectionMode = appStore.searchQuery.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty
        
        // Set current page BEFORE items to ensure correct initial position
        view.setInitialPage(appStore.currentPage)
        view.items = items

        view.onItemClicked = { item, index in
            // 单击打开应用或文件夹
            switch item {
            case .app(let app):
                onOpenApp?(app)
                AppDelegate.shared?.hideWindow()
                DispatchQueue.main.asyncAfter(deadline: .now() + 0.05) {
                    NSWorkspace.shared.open(app.url)
                }
            case .folder(let folder):
                onOpenFolder?(folder)
            case .missingApp:
                // 丢失的应用，不处理
                break
            case .empty:
                // 空白位置，不做任何操作（和真实Launchpad一致）
                // 只有点击网格外的空白区域才关闭窗口
                break
            }
        }

        view.onItemDoubleClicked = { item, index in
            // 双击也处理（兼容）
        }

        view.onPageChanged = { page in
            DispatchQueue.main.async {
                if appStore.currentPage != page {
                    appStore.currentPage = page
                }
            }
        }

        view.onFPSUpdate = { fps in
            // 可以在这里更新 FPS 显示
        }

        view.onEmptyAreaClicked = {
            // 点击空白区域关闭窗口
            AppDelegate.shared?.hideWindow()
        }

        view.onHideApp = { app in
            DispatchQueue.main.async {
                _ = appStore.hideApp(app)
            }
        }
        view.onDissolveFolder = { folder in
            DispatchQueue.main.async {
                _ = appStore.dissolveFolder(folder)
            }
        }
        view.onUninstallWithTool = { app in
            DispatchQueue.main.async {
                if !appStore.openConfiguredUninstallTool(for: app) {
                    NSSound.beep()
                }
            }
        }

        // 拖拽创建文件夹
        view.onCreateFolder = { dragApp, targetApp, insertAt in
            DispatchQueue.main.async {
                _ = appStore.createFolder(with: [dragApp, targetApp], insertAt: insertAt)
            }
        }

        // 拖拽移入文件夹
        view.onMoveToFolder = { app, folder in
            DispatchQueue.main.async {
                appStore.addAppToFolder(app, folder: folder)
            }
        }

        // Drag reorder
        view.onReorderItems = { fromIndex, toIndex in
            DispatchQueue.main.async {
                guard fromIndex < appStore.items.count else { return }
                let itemsPerPage = appStore.gridColumnsPerPage * appStore.gridRowsPerPage
                let sourcePage = fromIndex / itemsPerPage
                let targetPage = toIndex / itemsPerPage
                
                if sourcePage == targetPage {
                    // Same page: use simple swap logic
                    let pageStart = sourcePage * itemsPerPage
                    let pageEnd = min(pageStart + itemsPerPage, appStore.items.count)
                    var newItems = appStore.items
                    var pageSlice = Array(newItems[pageStart..<pageEnd])
                    let localFrom = fromIndex - pageStart
                    let localTo = min(toIndex - pageStart, pageSlice.count - 1)
                    
                    if localFrom != localTo && localFrom < pageSlice.count && localTo < pageSlice.count {
                        let moving = pageSlice.remove(at: localFrom)
                        pageSlice.insert(moving, at: localTo)
                        newItems.replaceSubrange(pageStart..<pageEnd, with: pageSlice)
                        appStore.items = newItems
                    }
                    appStore.triggerGridRefresh()
                    appStore.saveAllOrder()
                    
                    // Compact after same-page drag
                    DispatchQueue.main.asyncAfter(deadline: .now() + 0.1) {
                        appStore.compactItemsWithinPages()
                    }
                } else {
                    // Cross-page: use cascade insert logic
                let item = appStore.items[fromIndex]
                appStore.moveItemAcrossPagesWithCascade(item: item, to: toIndex)
                }
            }
        }

        view.onReorderAppBatch = { appPathsOrdered, toIndex in
            DispatchQueue.main.async {
                appStore.moveSelectedAppsAcrossPagesWithCascade(appPathsOrdered: appPathsOrdered, to: toIndex)
            }
        }

        // 请求创建新页面（拖拽到右边缘时）
        view.onRequestNewPage = {
            DispatchQueue.main.async {
                let itemsPerPage = appStore.gridColumnsPerPage * appStore.gridRowsPerPage
                let currentPageCount = (appStore.items.count + itemsPerPage - 1) / itemsPerPage
                let neededItems = (currentPageCount + 1) * itemsPerPage - appStore.items.count
                for _ in 0..<neededItems {
                    appStore.items.append(.empty(UUID().uuidString))
                }
            }
        }

        return view
    }

    func updateNSView(_ nsView: CAGridView, context: Context) {
        // print("🔄 [CAGrid #\(nsView.debugInstanceId)] updateNSView, window=\(nsView.window != nil), isVisible=\(nsView.window?.isVisible ?? false)")
        // 确保滚轮事件监听器已安装（窗口重新显示时需要）
        nsView.ensureScrollMonitorInstalled()

        // 更新配置
        let configChanged = nsView.columns != appStore.gridColumnsPerPage ||
                            nsView.rows != appStore.gridRowsPerPage ||
                            nsView.iconSize != iconSize ||
                            nsView.columnSpacing != columnSpacing ||
                            nsView.rowSpacing != rowSpacing ||
                            nsView.contentInsets.top != contentInsets.top ||
                            nsView.contentInsets.left != contentInsets.left ||
                            nsView.contentInsets.bottom != contentInsets.bottom ||
                            nsView.contentInsets.right != contentInsets.right ||
                            nsView.pageSpacing != pageSpacing ||
                            nsView.labelFontSize != CGFloat(appStore.iconLabelFontSize) ||
                            nsView.labelFontWeight != nsFontWeight(for: appStore.iconLabelFontWeight) ||
                            nsView.showLabels != appStore.showLabels ||
                            nsView.isLayoutLocked != appStore.isLayoutLocked ||
                            nsView.folderDropZoneScale != CGFloat(appStore.folderDropZoneScale) ||
                            nsView.folderPreviewScale != (appStore.enableHighResFolderPreviews ? nsViewScale(for: nsView) : 1)

        if configChanged {
            nsView.columns = appStore.gridColumnsPerPage
            nsView.rows = appStore.gridRowsPerPage
            nsView.iconSize = iconSize
            nsView.columnSpacing = columnSpacing
            nsView.rowSpacing = rowSpacing
            nsView.contentInsets = contentInsets
            nsView.pageSpacing = pageSpacing
            nsView.labelFontSize = CGFloat(appStore.iconLabelFontSize)
            nsView.labelFontWeight = nsFontWeight(for: appStore.iconLabelFontWeight)
            nsView.showLabels = appStore.showLabels
            nsView.isLayoutLocked = appStore.isLayoutLocked
            nsView.folderDropZoneScale = CGFloat(appStore.folderDropZoneScale)
            let preferredScale = nsViewScale(for: nsView)
            nsView.folderPreviewScale = appStore.enableHighResFolderPreviews ? preferredScale : 1
        }
        nsView.scrollSensitivity = appStore.scrollSensitivity
        nsView.enableIconPreload = false
        nsView.scrollSensitivity = appStore.scrollSensitivity
        nsView.reverseWheelPagingDirection = appStore.reverseWheelPagingDirection
        nsView.hoverMagnificationEnabled = appStore.enableHoverMagnification
        nsView.hoverMagnificationScale = CGFloat(appStore.hoverMagnificationScale)
        nsView.activePressEffectEnabled = appStore.enableActivePressEffect
        nsView.activePressScale = CGFloat(appStore.activePressScale)
        nsView.animationsEnabled = appStore.enableAnimations
        nsView.animationDuration = appStore.animationDuration
        nsView.isScrollEnabled = appStore.openFolder == nil && !appStore.isSetting
        nsView.hideAppMenuTitle = appStore.localized(.hiddenAppsAddButton)
        nsView.dissolveFolderMenuTitle = appStore.localized(.contextMenuDissolveFolder)
        nsView.uninstallWithToolMenuTitle = appStore.localized(.contextMenuUninstallWithConfiguredTool)
        nsView.batchSelectAppsMenuTitle = appStore.localized(.contextMenuBatchSelectApps)
        nsView.finishBatchSelectionMenuTitle = appStore.localized(.contextMenuFinishBatchSelection)
        nsView.canUseConfiguredUninstallTool = appStore.uninstallToolAppURL != nil
        nsView.allowsBatchSelectionMode = appStore.searchQuery.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty

        // 检查刷新触发器是否变化（文件夹创建/修改会触发）
        let triggerChanged = context.coordinator.lastGridRefreshTrigger != gridRefreshTrigger ||
                             context.coordinator.lastFolderUpdateTrigger != folderUpdateTrigger

        if context.coordinator.lastIconCacheRefreshTrigger != iconCacheRefreshTrigger {
            context.coordinator.lastIconCacheRefreshTrigger = iconCacheRefreshTrigger
            nsView.clearIconCache()
            nsView.items = items
        }

        var didUpdateItems = false
        if triggerChanged {
            context.coordinator.lastGridRefreshTrigger = gridRefreshTrigger
            context.coordinator.lastFolderUpdateTrigger = folderUpdateTrigger
            // print("🔄 [CAGrid] Trigger changed, forcing refresh")
            nsView.items = items
            didUpdateItems = true
        } else if itemsChanged(nsView.items, items) {
            // 更新 items - 始终检查完整变化（包括文件夹名称等）
            // print("🔄 [CAGrid] Updating items: \(nsView.items.count) -> \(items.count)")
            nsView.items = items
            didUpdateItems = true
        }

        let maxPageIndex = max(nsView.pageCount - 1, 0)
        if appStore.currentPage > maxPageIndex {
            nsView.navigateToPage(maxPageIndex, animated: false)
            DispatchQueue.main.async {
                if appStore.currentPage > maxPageIndex {
                    appStore.currentPage = maxPageIndex
                }
            }
        }

        // 同步页面
        if nsView.currentPage != appStore.currentPage {
            // print("📄 [CAGrid] Page sync: \(nsView.currentPage) -> \(appStore.currentPage)")
            nsView.navigateToPage(appStore.currentPage, animated: appStore.enableAnimations)
        }

        if didUpdateItems {
            nsView.forceSyncPageTransformIfNeeded()
        } else {
            nsView.snapToCurrentPageIfNeeded()
        }

        let safeSelectedIndex: Int? = {
            guard let selectedIndex else { return nil }
            return items.indices.contains(selectedIndex) ? selectedIndex : nil
        }()
        nsView.updateSelection(safeSelectedIndex, animated: true)
        nsView.updateExternalDragState(sourceIndex: externalDragSourceIndex,
                                       hoverIndex: externalDragHoverIndex)
        nsView.logIfMismatch("updateNSView", appPage: appStore.currentPage)
    }

    func makeCoordinator() -> Coordinator {
        Coordinator()
    }

    private func nsFontWeight(for option: AppStore.IconLabelFontWeightOption) -> NSFont.Weight {
        switch option {
        case .light: return .light
        case .regular: return .regular
        case .medium: return .medium
        case .semibold: return .semibold
        case .bold: return .bold
        }
    }

    private func nsViewScale(for view: NSView) -> CGFloat {
        if let scale = view.window?.backingScaleFactor {
            return scale
        }
        return NSScreen.main?.backingScaleFactor ?? 1
    }

    class Coordinator {
        var lastGridRefreshTrigger: UUID = UUID()
        var lastFolderUpdateTrigger: UUID = UUID()
        var lastIconCacheRefreshTrigger: UUID = UUID()
    }

    // 检查 items 是否变化（完整比较所有 item 的 id 和名称）
    private func itemsChanged(_ old: [LaunchpadItem], _ new: [LaunchpadItem]) -> Bool {
        guard old.count == new.count else { return true }
        guard !old.isEmpty else { return !new.isEmpty }

        // 完整比较每个 item
        for i in 0..<old.count {
            let oldItem = old[i]
            let newItem = new[i]

            // 比较 id
            if oldItem.id != newItem.id { return true }

            // 比较名称（文件夹改名后需要刷新）
            if oldItem.name != newItem.name { return true }

            // 对于文件夹，还要比较内部应用数量
            if case .folder(let oldFolder) = oldItem, case .folder(let newFolder) = newItem {
                if oldFolder.apps.count != newFolder.apps.count { return true }
            }
        }

        return false
    }
}

// MARK: - Preview

#if DEBUG
struct CAGridViewRepresentable_Previews: PreviewProvider {
    static var previews: some View {
        CAGridViewRepresentable(appStore: AppStore(),
                                items: [],
                                iconSize: 72,
                                columnSpacing: 20,
                                rowSpacing: 14,
                                contentInsets: NSEdgeInsets(top: 0, left: 0, bottom: 0, right: 0),
                                pageSpacing: 80,
                                externalDragSourceIndex: nil,
                                externalDragHoverIndex: nil)
            .frame(width: 1200, height: 800)
    }
}
#endif
