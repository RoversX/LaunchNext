import AppKit
import QuartzCore

@MainActor
final class FolderCreationHighlight {
    let backplate = CALayer()
    let container: CALayer
    let icon: CALayer
    var startedAt = CACurrentMediaTime()
    var fromScale: CGFloat = 0.15
    var toScale: CGFloat = 1
    var scale: CGFloat = 0.15
    var holdUntil: CFTimeInterval?
    var isExiting = false
    static let duration: CFTimeInterval = 0.18

    init(container: CALayer, icon: CALayer) {
        self.container = container
        self.icon = icon
        backplate.name = "creationGlass"
    }

    func enter(at now: CFTimeInterval) {
        fromScale = scale
        toScale = 1
        isExiting = false
        startedAt = now
        holdUntil = nil
    }

    func exit(at now: CFTimeInterval) {
        guard !isExiting else { return }
        fromScale = scale
        // Reverse the entrance all the way to its initial size. Ease-in keeps
        // the visible rim from disappearing behind the app in the first frames.
        toScale = 0.15
        isExiting = true
        startedAt = now
        holdUntil = nil
    }
}

extension CAGridView {
    /// The preview is keyed by item ID, while its old index and layers can be
    /// invalidated by a model publication. Restore visuals without changing the
    /// pending drop operation or restarting the entrance animation.
    func restoreMergePreviewAfterRebuild(previousCreationHighlight: FolderCreationHighlight?) {
        guard case .merge(let targetID) = dragDropPreview else { return }
        dropTargetIndex = nil
        guard let index = items.firstIndex(where: { $0.id == targetID }) else {
            dragDropPreview = .none
            return
        }
        switch items[index] {
        case .app:
            highlightDropTarget(at: index)
            if let old = previousCreationHighlight, let current = folderCreationHighlight {
                current.startedAt = old.startedAt
                current.fromScale = old.fromScale
                current.toScale = old.toScale
                current.scale = old.scale
                current.holdUntil = old.holdUntil
                current.isExiting = old.isExiting
                updateFolderCreationHighlight(at: CACurrentMediaTime())
            }
        case .folder:
            highlightDropTarget(at: index)
        case .empty, .missingApp:
            dragDropPreview = .none
        }
    }

    func showFolderCreationHighlight(at index: Int) {
        guard itemsPerPage > 0, index >= 0,
              iconLayers.indices.contains(index / itemsPerPage),
              iconLayers[index / itemsPerPage].indices.contains(index % itemsPerPage) else { return }
        let container = iconLayers[index / itemsPerPage][index % itemsPerPage]
        guard let icon = container.sublayers?.first(where: { $0.name == "icon" }) else { return }
        let now = CACurrentMediaTime()
        if let current = folderCreationHighlight, current.container === container {
            if current.isExiting || current.holdUntil != nil { current.enter(at: now) }
            return
        }
        // Re-entry can reuse an outgoing view instead of replacing its material.
        let reused = retiringFolderCreationHighlight?.container === container
            ? retiringFolderCreationHighlight : nil
        if reused != nil { retiringFolderCreationHighlight = nil }
        CATransaction.begin()
        CATransaction.setDisableActions(true)
        if let current = folderCreationHighlight {
            retiringFolderCreationHighlight?.backplate.removeFromSuperlayer()
            current.exit(at: now)
            retiringFolderCreationHighlight = current
        }
        let highlight = reused ?? FolderCreationHighlight(container: container, icon: icon)
        if reused != nil {
            highlight.enter(at: now)
        } else {
            let style = currentFolderGlassStyle()
            highlight.backplate.backgroundColor = style.background.cgColor
            highlight.backplate.borderColor = style.border.cgColor
            highlight.backplate.borderWidth = 0.5
            container.insertSublayer(highlight.backplate, below: icon)
        }
        folderCreationHighlight = highlight
        // A replacement may begin at the same sampled scale, but still needs
        // its view registered and the oldest outgoing view released.
        if !updateFolderCreationHighlight(at: now) { syncFolderGlass() }
        CATransaction.commit()
    }

    func hideFolderCreationHighlight(preservingForDrop: Bool = false) {
        guard let highlight = folderCreationHighlight else { return }
        if preservingForDrop {
            highlight.holdUntil = CACurrentMediaTime() + 0.5
        } else {
            highlight.exit(at: CACurrentMediaTime())
        }
    }

    func removeFolderCreationHighlight(sync: Bool = true) {
        guard folderCreationHighlight != nil || retiringFolderCreationHighlight != nil else { return }
        CATransaction.begin()
        CATransaction.setDisableActions(true)
        folderCreationHighlight?.backplate.removeFromSuperlayer()
        retiringFolderCreationHighlight?.backplate.removeFromSuperlayer()
        folderCreationHighlight = nil
        retiringFolderCreationHighlight = nil
        if sync { syncFolderGlass() }
        CATransaction.commit()
    }

    /// One active target and at most one outgoing target, advanced together on
    /// the existing display link. No per-target timers or bitmap caches.
    @discardableResult
    func updateFolderCreationHighlight(at now: CFTimeInterval) -> Bool {
        guard folderCreationHighlight != nil || retiringFolderCreationHighlight != nil else { return false }
        guard window?.isVisible == true, !isHiddenOrHasHiddenAncestor else {
            removeFolderCreationHighlight()
            return true
        }
        var changed = false
        CATransaction.begin()
        CATransaction.setDisableActions(true)
        for highlight in [folderCreationHighlight, retiringFolderCreationHighlight].compactMap({ $0 }) {
            if let deadline = highlight.holdUntil, now >= deadline { highlight.exit(at: now) }
            let progress = min(1, max(0, (now - highlight.startedAt) / FolderCreationHighlight.duration))
            if highlight.container.superlayer !== pageContainerLayer || (progress == 1 && highlight.isExiting) {
                highlight.backplate.removeFromSuperlayer()
                if folderCreationHighlight === highlight { folderCreationHighlight = nil }
                if retiringFolderCreationHighlight === highlight { retiringFolderCreationHighlight = nil }
                changed = true
                continue
            }
            let eased = highlight.isExiting
                ? pow(progress, 3)
                : 1 - pow(1 - progress, 3)
            let scale = highlight.fromScale + (highlight.toScale - highlight.fromScale) * CGFloat(eased)
            let side = min(highlight.icon.bounds.width, highlight.icon.bounds.height) * 0.9
            let center = highlight.icon.position
            let plate = highlight.backplate
            guard plate.bounds.width != side || plate.position != center || plate.transform.m11 != scale else { continue }
            plate.bounds = CGRect(x: 0, y: 0, width: side, height: side)
            plate.position = center
            plate.cornerRadius = side * 0.25
            plate.transform = CATransform3DMakeScale(scale, scale, 1)
            highlight.scale = scale
            changed = true
        }
        if changed { syncFolderGlass() }
        CATransaction.commit()
        return changed
    }
}
