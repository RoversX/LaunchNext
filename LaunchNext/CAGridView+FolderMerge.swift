import AppKit
import QuartzCore

@MainActor
final class FolderMergeLanding {
    let sourcePath: String
    let targetPath: String?
    let targetID: String
    let container = CALayer()
    let icon = CALayer()
    let glass = CALayer()
    let originalTarget: CALayer
    let iconBounds: CGRect
    let createdAt = CACurrentMediaTime()
    var startedAt: CFTimeInterval?
    var neighborPositions: [String: CGPoint] = [:]
    var neighborMotionStartedAt: CFTimeInterval?
    static let duration: CFTimeInterval = 0.24
    static let maximumDuration: CFTimeInterval = 0.8

    init(sourcePath: String, targetPath: String?, targetID: String,
         originalTarget: CALayer, iconBounds: CGRect) {
        self.sourcePath = sourcePath
        self.targetPath = targetPath
        self.targetID = targetID
        self.originalTarget = originalTarget
        self.iconBounds = iconBounds
    }

    func matches(_ item: LaunchpadItem) -> Bool {
        guard case .folder(let folder) = item,
              folder.apps.contains(where: { $0.url.path == sourcePath }) else { return false }
        if let targetPath { return folder.apps.contains { $0.url.path == targetPath } }
        return item.id == targetID
    }
}

extension CAGridView {
    func isFolderMergeDestination(_ item: LaunchpadItem) -> Bool {
        folderMergeLanding?.matches(item) == true
    }

    /// Retain only the participating bitmaps. The model may rebuild the grid,
    /// but cannot replace these visuals halfway through the merge.
    func beginFolderMergeLanding(itemID: String, targetID: String) -> Bool {
        guard let parent = draggingLayer?.superlayer,
              let source = items.first(where: { $0.id == itemID })?.appInfoIfApp,
              let index = items.firstIndex(where: { $0.id == targetID }), itemsPerPage > 0,
              iconLayers.indices.contains(index / itemsPerPage),
              iconLayers[index / itemsPerPage].indices.contains(index % itemsPerPage) else { return false }
        let targetItem = items[index]
        let target = iconLayers[index / itemsPerPage][index % itemsPerPage]
        guard let icon = target.sublayers?.first(where: { $0.name == "icon" }), icon.contents != nil,
              let glass = target.sublayers?.first(where: { $0.name == "glass" || $0.name == "creationGlass" }) else { return false }
        let merge = FolderMergeLanding(sourcePath: source.url.path,
                                       targetPath: targetItem.appInfoIfApp?.url.path,
                                       targetID: targetID, originalTarget: target, iconBounds: icon.bounds)
        CATransaction.begin()
        CATransaction.setDisableActions(true)
        beginDragLanding(itemID: itemID, waitingForRevision: nil)
        dragLanding?.mergeTarget = icon.convert(icon.bounds, to: parent)
        dragLanding?.mergeTargetID = targetID
        merge.container.bounds = icon.bounds
        let rect = icon.convert(icon.bounds, to: parent)
        merge.container.position = CGPoint(x: rect.midX, y: rect.midY)
        merge.container.zPosition = 900
        merge.icon.name = "icon"
        merge.icon.frame = icon.bounds
        merge.icon.contents = icon.contents
        merge.icon.contentsScale = icon.contentsScale
        merge.icon.contentsGravity = .resizeAspect
        // A separate native preview host keeps the moving app above the glass.
        merge.glass.name = merge.targetPath == nil ? "glass" : "creationGlass"
        if let shownGlass = glass.presentation(), let shownIcon = icon.presentation() {
            merge.glass.frame = shownGlass.convert(shownGlass.bounds, to: shownIcon)
        } else {
            merge.glass.frame = glass.convert(glass.bounds, to: icon)
        }
        merge.glass.backgroundColor = glass.backgroundColor
        merge.glass.borderColor = glass.borderColor
        merge.glass.borderWidth = glass.borderWidth
        merge.glass.cornerRadius = merge.glass.bounds.width * 0.25
        merge.container.addSublayer(merge.glass)
        merge.container.addSublayer(merge.icon)
        parent.addSublayer(merge.container)
        folderMergeLanding = merge
        removeFolderCreationHighlight(sync: false)
        target.removeAnimation(forKey: "opacity")
        target.opacity = 0
        syncFolderGlass()
        CATransaction.commit()
        return true
    }

    /// Start after the updated model/layout is available. Explicit CA animations
    /// continue in the compositor if a subsequent publication stalls the main thread.
    func updateFolderMergeLanding(at now: CFTimeInterval) -> Bool {
        guard let merge = folderMergeLanding else { return false }
        guard dragLanding != nil, window?.isVisible == true, !isHiddenOrHasHiddenAncestor,
              let preview = draggingLayer, let parent = preview.superlayer,
              now - merge.createdAt < FolderMergeLanding.maximumDuration else {
            finishDragLanding()
            return true
        }
        guard let index = items.firstIndex(where: merge.matches), itemsPerPage > 0,
              iconLayers.indices.contains(index / itemsPerPage),
              iconLayers[index / itemsPerPage].indices.contains(index % itemsPerPage),
              case .folder(let folder) = items[index] else {
            if now - merge.createdAt >= 0.3 { finishDragLanding() }
            return true
        }
        let destination = iconLayers[index / itemsPerPage][index % itemsPerPage]
        guard let icon = destination.sublayers?.first(where: { $0.name == "icon" }) else {
            finishDragLanding()
            return true
        }
        destination.opacity = 0
        if merge.startedAt == nil {
            let rect = icon.convert(icon.bounds, to: parent)
            // These are temporary visuals. Abort the handoff rather than write
            // non-finite transforms if a layout is invalidated during the drop.
            guard rect.origin.x.isFinite, rect.origin.y.isFinite,
                  rect.width.isFinite, rect.width > 0, rect.height.isFinite, rect.height > 0,
                  merge.iconBounds.width.isFinite, merge.iconBounds.width > 0,
                  merge.glass.bounds.width.isFinite, merge.glass.bounds.width > 0,
                  merge.icon.bounds.width.isFinite, merge.icon.bounds.width > 0,
                  preview.bounds.width.isFinite, preview.bounds.width > 0 else {
                finishDragLanding()
                return true
            }
            merge.startedAt = now
            CATransaction.begin()
            CATransaction.setDisableActions(true)
            animateMergeLayer(merge.container, position: CGPoint(x: rect.midX, y: rect.midY),
                              scale: rect.width / merge.iconBounds.width)
            // The hover plate is slightly larger; settle to the real folder size.
            let plateSide = merge.iconBounds.width * 0.8
            animateMergeLayer(merge.glass,
                              position: CGPoint(x: merge.iconBounds.midX, y: merge.iconBounds.midY),
                              scale: plateSide / merge.glass.bounds.width)
            if let targetPath = merge.targetPath,
               let slot = folder.apps.firstIndex(where: { $0.url.path == targetPath }),
               let tile = FolderPreviewLayout.iconRect(at: slot, side: merge.iconBounds.width) {
                animateMergeLayer(merge.icon, position: CGPoint(x: tile.midX, y: tile.midY),
                                  scale: tile.width / merge.icon.bounds.width)
            }
            let slot = folder.apps.firstIndex { $0.url.path == merge.sourcePath } ?? 9
            let tile = FolderPreviewLayout.iconRect(at: slot, side: rect.width)
            let landingRect = tile.map { $0.offsetBy(dx: rect.minX, dy: rect.minY) }
                ?? rect.insetBy(dx: rect.width * 0.4, dy: rect.height * 0.4)
            animateMergeLayer(preview, position: CGPoint(x: landingRect.midX, y: landingRect.midY),
                              scale: landingRect.width / preview.bounds.width)
            // Visible slots stay opaque until the exact preview handoff. Overflow
            // apps disappear only near the end, after travelling into the folder.
            if tile == nil {
                let fade = CAKeyframeAnimation(keyPath: "opacity")
                fade.values = [1, 1, 0]
                fade.keyTimes = [0, 0.7, 1]
                fade.duration = FolderMergeLanding.duration
                preview.opacity = 0
                preview.add(fade, forKey: "mergeOpacity")
            }
            syncFolderGlass()
            CATransaction.commit()
        }
        if let start = merge.startedAt, now - start >= FolderMergeLanding.duration,
           icon.value(forKey: "folderPreviewReady") as? Bool == true {
            finishDragLanding()
        } else {
            // Only while merging; no extra idle timer or persistent bitmap cache.
            syncFolderGlass()
        }
        return true
    }

    func captureFolderMergeNeighbors(previousItems: [LaunchpadItem]?) {
        guard let merge = folderMergeLanding, let root = layer else { return }
        merge.neighborPositions.removeAll(keepingCapacity: true)
        for (item, cell) in zip(previousItems ?? items, iconLayers.flatMap({ $0 })) {
            guard cell.opacity > 0, item.id != merge.targetID,
                  cell.convert(cell.bounds, to: root).intersects(bounds) else { continue }
            let point = cell.presentation()?.position ?? cell.position
            merge.neighborPositions[item.id] = pageContainerLayer.convert(point, to: root)
        }
    }

    func animateFolderMergeNeighbors() {
        guard let merge = folderMergeLanding, let root = layer,
              items.contains(where: merge.matches) else { return }
        let now = CACurrentMediaTime()
        let start = merge.neighborMotionStartedAt ?? now
        merge.neighborMotionStartedAt = start
        let remaining = max(0, FolderMergeLanding.duration - (now - start))
        guard remaining > 0 else { return }
        CATransaction.begin()
        CATransaction.setDisableActions(true)
        for (item, cell) in zip(items, iconLayers.flatMap({ $0 })) {
            guard !merge.matches(item), let point = merge.neighborPositions[item.id],
                  cell.convert(cell.bounds, to: root).intersects(bounds) else { continue }
            let from = root.convert(point, to: pageContainerLayer)
            guard from != cell.position else { continue }
            let move = CABasicAnimation(keyPath: "position")
            move.fromValue = NSValue(point: from)
            move.toValue = NSValue(point: cell.position)
            move.duration = remaining
            move.timingFunction = CAMediaTimingFunction(name: .easeInEaseOut)
            cell.add(move, forKey: "mergeNeighborPosition")
        }
        CATransaction.commit()
    }

    private func animateMergeLayer(_ layer: CALayer, position: CGPoint, scale: CGFloat) {
        let visible = layer.presentation() ?? layer
        let move = CABasicAnimation(keyPath: "position")
        move.fromValue = NSValue(point: visible.position)
        move.toValue = NSValue(point: position)
        let shrink = CABasicAnimation(keyPath: "transform")
        shrink.fromValue = NSValue(caTransform3D: visible.transform)
        let transform = CATransform3DMakeScale(scale, scale, 1)
        shrink.toValue = NSValue(caTransform3D: transform)
        for animation in [move, shrink] {
            animation.duration = FolderMergeLanding.duration
            animation.timingFunction = CAMediaTimingFunction(name: .easeInEaseOut)
        }
        layer.position = position
        layer.transform = transform
        layer.add(move, forKey: "mergePosition")
        layer.add(shrink, forKey: "mergeTransform")
    }

    func finishFolderMergeLanding() {
        guard let merge = folderMergeLanding else { return }
        // Also restores a rejected/no-op merge whose old target is still present.
        merge.originalTarget.opacity = 1
        for cell in iconLayers.flatMap({ $0 }) { cell.removeAnimation(forKey: "mergeNeighborPosition") }
        for (index, item) in items.enumerated()
            where merge.matches(item) || item.appInfoIfApp?.url.path == merge.sourcePath {
            if itemsPerPage > 0, iconLayers.indices.contains(index / itemsPerPage),
               iconLayers[index / itemsPerPage].indices.contains(index % itemsPerPage) {
                iconLayers[index / itemsPerPage][index % itemsPerPage].opacity = 1
            }
        }
        folderGlassOverlay?.removeDraggingGlass(for: merge.container)
        merge.container.removeFromSuperlayer()
        folderMergeLanding = nil
    }
}
