import AppKit
import QuartzCore

struct DragLanding {
    let itemID: String
    let waitingForRevision: Int?
    let createdAt: CFTimeInterval
    let predictedIndex: Int?
    let predictedPageOffset: CGFloat?
    var fromPosition: CGPoint
    var fromScale: CGFloat
    var startedAt: CFTimeInterval
    var segmentDuration: CFTimeInterval = duration
    var target: CGRect?
    var mergeTarget: CGRect? = nil
    var mergeTargetID: String? = nil
    var reorderResolved = false
    static let duration: CFTimeInterval = 0.18
    // Retargeting may extend individual segments, but never the whole handoff.
    static let maximumDuration: CFTimeInterval = 0.5
}

extension CAGridView {
    func beginDragLanding(itemID: String, waitingForRevision: Int?, predictedIndex: Int? = nil,
                          predictedPageOffset: CGFloat? = nil) {
        guard let preview = draggingLayer else { return }
        let now = CACurrentMediaTime()
        dragLanding = DragLanding(itemID: itemID, waitingForRevision: waitingForRevision,
                                  createdAt: now, predictedIndex: predictedIndex,
                                  predictedPageOffset: predictedPageOffset,
                                  fromPosition: preview.position,
                                  fromScale: preview.transform.m11, startedAt: now)
        hideDragLandingDestination()
    }

    func beginMergeLanding(itemID: String, targetID: String) -> Bool {
        if beginFolderMergeLanding(itemID: itemID, targetID: targetID) { return true }
        guard let parent = draggingLayer?.superlayer,
              let target = gridContainer(for: targetID),
              let icon = target.sublayers?.first(where: { $0.name == "icon" }) else { return false }
        let rect = icon.convert(icon.bounds, to: parent)
        beginDragLanding(itemID: itemID, waitingForRevision: nil)
        dragLanding?.mergeTarget = rect
        dragLanding?.mergeTargetID = targetID
        return dragLanding != nil
    }

    private func dragLandingDestination() -> CALayer? {
        guard let landing = dragLanding else { return nil }
        return gridContainer(for: landing.itemID)
    }

    private func gridContainer(for itemID: String) -> CALayer? {
        guard let index = items.firstIndex(where: { $0.id == itemID }),
              itemsPerPage > 0 else { return nil }
        let page = index / itemsPerPage
        let local = index % itemsPerPage
        guard page < iconLayers.count, local < iconLayers[page].count else { return nil }
        return iconLayers[page][local]
    }

    func hideDragLandingDestination() {
        guard let destination = dragLandingDestination() else { return }
        CATransaction.begin()
        CATransaction.setDisableActions(true)
        destination.removeAnimation(forKey: "opacity")
        destination.opacity = 0
        CATransaction.commit()
    }

    /// Sample using the grid's existing display link. Both native glass and its
    /// CA preview read these same model coordinates, with no extra bitmap work.
    func updateDragLanding(at now: CFTimeInterval) {
        if updateFolderMergeLanding(at: now) { return }
        guard var landing = dragLanding else { return }
        guard now - landing.createdAt < DragLanding.maximumDuration else {
            finishDragLanding()
            return
        }
        guard window?.isVisible == true, !isHiddenOrHasHiddenAncestor,
              let preview = draggingLayer, let parent = preview.superlayer else {
            finishDragLanding()
            return
        }
        let isMerging = landing.mergeTarget != nil
        let sourceIndex = items.firstIndex(where: { $0.id == landing.itemID })
        // An unrelated refresh can increment the revision before the reorder
        // arrives. Keep the final planned target until the source reaches it.
        let reorderPending = landing.waitingForRevision != nil && !landing.reorderResolved
            && (landing.waitingForRevision == itemsRevision
                || (landing.predictedIndex != nil && sourceIndex != landing.predictedIndex))
        if !reorderPending || now - landing.createdAt >= 0.25 { landing.reorderResolved = true }
        let awaitingModel = (isMerging ? items.contains(where: { $0.id == landing.itemID })
                             : reorderPending)
            && now - landing.createdAt < 0.25
        guard preview.bounds.width > 0 else {
            finishDragLanding()
            return
        }
        var target: CGRect
        if let mergeTarget = landing.mergeTarget {
            let liveIcon = landing.mergeTargetID.flatMap { gridContainer(for: $0) }?
                .sublayers?.first(where: { $0.name == "icon" })
            let rect = liveIcon.map { $0.convert($0.bounds, to: parent) } ?? mergeTarget
            target = rect.insetBy(dx: rect.width * 0.35, dy: rect.height * 0.35)
        } else if let destination = dragLandingDestination(),
                  let icon = destination.sublayers?.first(where: { $0.name == "icon" }) {
            target = icon.convert(icon.bounds, to: parent)
            if awaitingModel, let index = landing.predictedIndex {
                // The old source is still hidden in its original cell. Translate
                // its icon rect to the proposed cell, including the label offset.
                let center = gridCenterForGlobalIndex(index)
                let delta = CGPoint(x: center.x - destination.position.x,
                                    y: center.y - destination.position.y)
                let rect = icon.convert(icon.bounds, to: pageContainerLayer)
                    .offsetBy(dx: delta.x, dy: delta.y)
                target = pageContainerLayer.convert(rect, to: parent)
                if let pageOffset = landing.predictedPageOffset {
                    // Empty-page removal may clamp the displayed page, too.
                    target = target.offsetBy(dx: pageOffset - pageContainerLayer.transform.m41, dy: 0)
                }
            }
        } else {
            finishDragLanding()
            return
        }
        if let previousTarget = landing.target, previousTarget != target {
            // Correct a changed/compacted destination from the current point
            // on the old trajectory, never by jumping to a new interpolation.
            let previousProgress = min(1, max(0, (now - landing.startedAt) / landing.segmentDuration))
            let eased = CGFloat(1 - pow(1 - previousProgress, 3))
            landing.fromPosition.x += (previousTarget.midX - landing.fromPosition.x) * eased
            landing.fromPosition.y += (previousTarget.midY - landing.fromPosition.y) * eased
            landing.fromScale += (previousTarget.width / preview.bounds.width - landing.fromScale) * eased
            landing.startedAt = now
            landing.segmentDuration = max(0.08, landing.createdAt + DragLanding.duration - now)
        }
        landing.target = target
        dragLanding = landing
        let progress = min(1, max(0, (now - landing.startedAt) / landing.segmentDuration))
        let eased = CGFloat(1 - pow(1 - progress, 3))
        let targetPosition = CGPoint(x: target.midX, y: target.midY)
        let targetScale = target.width / preview.bounds.width
        CATransaction.begin()
        CATransaction.setDisableActions(true)
        preview.position = CGPoint(x: landing.fromPosition.x + (targetPosition.x - landing.fromPosition.x) * eased,
                                   y: landing.fromPosition.y + (targetPosition.y - landing.fromPosition.y) * eased)
        let scale = landing.fromScale + (targetScale - landing.fromScale) * eased
        preview.transform = CATransform3DMakeScale(scale, scale, 1)
        if isMerging {
            let fadeProgress = min(1, max(0, (now - landing.createdAt) / DragLanding.duration))
            preview.opacity = Float(pow(1 - fadeProgress, 3))
        }
        if progress >= 1 && !awaitingModel {
            finishDragLanding()
        } else {
            syncFolderGlass(geometryChanged: false)
        }
        CATransaction.commit()
    }

    /// Called on arrival, new input, and window teardown. No delayed completion
    /// can accidentally remove a subsequent drag's layer.
    func finishDragLanding() {
        guard dragLanding != nil || folderMergeLanding != nil else { return }
        CATransaction.begin()
        CATransaction.setDisableActions(true)
        let destination = dragLandingDestination()
        finishFolderMergeLanding()
        dragLanding = nil
        removeDraggingVisuals()
        destination?.removeAnimation(forKey: "opacity")
        destination?.opacity = 1
        syncFolderGlass()
        CATransaction.commit()
    }
    /// A drop normally changes ordering only. Keep CA and native glass objects
    /// alive instead of rebuilding every page on each model/refresh publication.
    func reuseLayersDuringLanding(previousItems: [LaunchpadItem]) -> Bool {
        guard dragLanding != nil, itemsPerPage > 0, !items.isEmpty,
              previousItems.count == items.count else { return false }
        let layers = iconLayers.flatMap { $0 }
        let oldIDs = previousItems.map(\.id)
        let newIDs = items.map(\.id)
        guard layers.count == previousItems.count,
              Set(oldIDs).count == oldIDs.count,
              Set(newIDs) == Set(oldIDs) else { return false }
        let previousByID = Dictionary(uniqueKeysWithValues: previousItems.map { ($0.id, $0) })
        guard items.allSatisfy({ item in
            previousByID[item.id].map { item.hasSameGridContent(as: $0) } == true
        }) else { return false }
        let byID = Dictionary(uniqueKeysWithValues: zip(oldIDs, layers))
        let positions = Dictionary(uniqueKeysWithValues: layers.map {
            (ObjectIdentifier($0), (model: $0.position, visible: $0.presentation()?.position ?? $0.position))
        })
        CATransaction.begin()
        CATransaction.setDisableActions(true)
        iconLayers = stride(from: 0, to: items.count, by: itemsPerPage).map { start in
            items[start..<min(start + itemsPerPage, items.count)].map { byID[$0.id]! }
        }
        for (index, item) in items.enumerated() {
            let container = iconLayers[index / itemsPerPage][index % itemsPerPage]
            container.removeAnimation(forKey: "opacity")
            container.opacity = item.id == dragLanding?.itemID || isFolderMergeDestination(item) ? 0 : 1
            container.transform = CATransform3DIdentity
            if let label = container.sublayers?.first(where: { $0.name == "label" }) as? CATextLayer {
                label.string = item.name
            }
            for child in container.sublayers ?? [] where child.name == "icon" || child.name == "glass" {
                child.transform = CATransform3DIdentity
            }
            // Content is unchanged: retain the bitmap and any pending load.
            // Changed content takes the normal rebuild path above instead.
        }
        updateLayout()
        for container in layers {
            guard let previous = positions[ObjectIdentifier(container)] else { continue }
            if container.opacity == 0 {
                container.removeAnimation(forKey: "position")
            } else if previous.model != container.position {
                let destination = container.position
                container.position = previous.model
                GridLayerMotion.move(container, to: destination, from: previous.visible)
            }
        }
        for index in Set([selectedIndex, hoveredIndex, pressedIndex, dropTargetIndex].compactMap { $0 }) {
            applyScaleForIndex(index, animated: false)
        }
        animateFolderGlass()
        CATransaction.commit()
        return true
    }

}
