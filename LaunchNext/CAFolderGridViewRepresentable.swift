import AppKit
import SwiftUI
import LaunchNextContextMenuCore

struct CAFolderGridViewRepresentable: NSViewRepresentable {
    @ObservedObject var appStore: AppStore
    @Binding var folder: FolderInfo
    @Binding var currentPage: Int
    @Binding var pageCount: Int
    @Binding var verticalScrollOffset: CGFloat
    var iconSize: CGFloat
    var verticalHeaderHeight: CGFloat
    var onClose: () -> Void
    var onLaunchApp: (AppInfo) -> Void

    func makeNSView(context: Context) -> CAFolderGridView {
        let view = CAFolderGridView(frame: .zero)
        configure(view)
        wireCallbacks(view)
        view.apps = folder.apps
        return view
    }

    func updateNSView(_ nsView: CAFolderGridView, context: Context) {
        configure(nsView)
        if nsView.apps != folder.apps {
            nsView.apps = folder.apps
        }
        if appStore.folderLayoutMode == .paged, nsView.displayedPage != currentPage {
            nsView.setDisplayedPage(currentPage, animated: appStore.enableAnimations)
        }
    }

    private func configure(_ view: CAFolderGridView) {
        view.layoutMode = appStore.folderLayoutMode
        view.iconSize = iconSize
        view.labelFontSize = CGFloat(appStore.iconLabelFontSize)
        view.labelFontWeight = nsFontWeight(for: appStore.iconLabelFontWeight)
        view.showLabels = appStore.showLabels
        view.hoverMagnificationEnabled = appStore.enableHoverMagnification
        view.hoverMagnificationScale = CGFloat(appStore.hoverMagnificationScale)
        view.activePressEffectEnabled = appStore.enableActivePressEffect
        view.activePressScale = CGFloat(appStore.activePressScale)
        view.animationsEnabled = appStore.enableAnimations
        view.animationDuration = appStore.animationDuration
        view.isLayoutLocked = appStore.isLayoutLocked
        view.scrollSensitivity = appStore.scrollSensitivity
        view.reverseWheelPagingDirection = appStore.reverseWheelPagingDirection
        view.reverseWheelVerticalDirection = appStore.reverseWheelVerticalDirection
        view.trackpadVerticalDirection = appStore.trackpadVerticalDirection
        view.verticalHeaderHeight = verticalHeaderHeight
        view.contextMenuFolderID = folder.id
        let store = appStore
        let folderID = folder.id
        view.contextMenuConfiguration = AppContextMenuConfiguration(
            localize: { [weak store] key in store?.localized(key.localizationKey) ?? key.localizationKey.rawValue },
            showQuarantineRemovalAction: appStore.showQuarantineRemovalAction,
            canUseConfiguredUninstallTool: appStore.uninstallToolAppURL != nil,
            folderQuickLaunchPinningEnabled: appStore.useCAGridRenderer && appStore.folderQuickLaunchEnabled,
            isOpenFolderAppPinned: { [weak store] app in
                store?.isFolderQuickLaunchAppPinned(app, inFolderID: folderID) ?? false
            }
        )
    }

    private func wireCallbacks(_ view: CAFolderGridView) {
        let currentPageBinding = $currentPage
        let pageCountBinding = $pageCount
        let verticalScrollOffsetBinding = $verticalScrollOffset
        view.onOpenApp = { app in
            DispatchQueue.main.async {
                onLaunchApp(app)
            }
        }
        view.onClose = {
            DispatchQueue.main.async {
                onClose()
            }
        }
        view.onPageStateChanged = { page, count in
            DispatchQueue.main.async {
                if currentPageBinding.wrappedValue != page {
                    currentPageBinding.wrappedValue = page
                }
                if pageCountBinding.wrappedValue != count {
                    pageCountBinding.wrappedValue = count
                }
            }
        }
        view.onVerticalScrollOffsetChanged = { offset in
            DispatchQueue.main.async {
                if abs(verticalScrollOffsetBinding.wrappedValue - offset) > 0.5 {
                    verticalScrollOffsetBinding.wrappedValue = offset
                }
            }
        }
        view.onReorderApps = { from, to in
            DispatchQueue.main.async {
                _ = appStore.reorderAppInFolder(folderID: folder.id, from: from, to: to)
            }
        }
        view.onDragAppOut = { app in
            DispatchQueue.main.async {
                appStore.handoffDraggingApp = app
                appStore.handoffDragScreenLocation = NSEvent.mouseLocation
                appStore.removeAppFromFolder(app, folder: folder)
                withAnimation(LNAnimations.springFast) {
                    onClose()
                }
            }
        }
        view.onContextMenuAction = { route in
            DispatchQueue.main.async {
                performAppContextMenuRoute(route, appStore: appStore)
            }
        }
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
}
