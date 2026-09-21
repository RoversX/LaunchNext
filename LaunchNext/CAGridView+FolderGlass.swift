import AppKit
import QuartzCore

extension CAGridView {
    func resetFolderGlass() {
        guard let overlay = folderGlassOverlay else { return }
        CATransaction.begin()
        CATransaction.setDisableActions(true)
        overlay.reset()
        overlay.removeFromSuperview()
        folderGlassOverlay = nil
        folderGlassAnimationDeadline = 0
        CATransaction.commit()
    }

    func animateFolderGlass() {
        guard usesLiquidGlassFolders else { return }
        // Covers the grid's longest (0.45 s) reorder animation. No extra timer
        // or display link: the existing link samples only during transitions.
        folderGlassAnimationDeadline = CACurrentMediaTime() + 0.5
        syncFolderGlass()
    }

    func syncFolderGlass(geometryChanged: Bool = true) {
        guard usesLiquidGlassFolders, window?.isVisible == true, !isHiddenOrHasHiddenAncestor,
              let root = layer, bounds.width > 0, bounds.height > 0 else {
            resetFolderGlass()
            return
        }
        let stride = bounds.width + pageSpacing
        guard stride > 0 else { return }
        let first = max(0, Int(floor(-scrollOffset / stride)) - 1)
        let last = min(iconLayers.count - 1, Int(ceil((-scrollOffset + bounds.width) / stride)))
        var visible: [CALayer] = []
        if first <= last {
            for index in first...last { visible.append(contentsOf: iconLayers[index]) }
        }
        if let draggingLayer { visible.append(draggingLayer) }
        if let merge = folderMergeLanding { visible.append(merge.container) }
        if let dissolve = folderDissolveTransition, dissolve.startedAt != nil { visible.append(dissolve.plate) }
        // Avoid allocating even the effect container when the visible pages
        // contain no folders. sync also removes records that left the viewport.
        guard folderGlassOverlay != nil || visible.contains(where: {
            $0.sublayers?.contains(where: { $0.name == "glass" || $0.name == "creationGlass" }) == true
        }) else { return }
        let overlay: FolderGlassOverlay
        if let existing = folderGlassOverlay {
            overlay = existing
        } else {
            overlay = FolderGlassOverlay(frame: bounds)
            addSubview(overlay)
            overlay.layer?.zPosition = 1
            folderGlassOverlay = overlay
        }
        if overlay.frame != bounds { overlay.frame = bounds }
        let handoffContainer = folderGlassHandoff == nil ? nil : items.firstIndex(where: {
            if case let .folder(folder) = $0 { return folder.id == presentedFolderID }
            return false
        }).flatMap { presentationContainer(at: $0) }
        overlay.sync(containers: visible, root: root, page: pageContainerLayer, viewport: bounds,
                     handoffContainer: handoffContainer, handoff: folderGlassHandoff,
                     geometryChanged: geometryChanged
                        || CACurrentMediaTime() < folderGlassAnimationDeadline)
    }
}
