import AppKit
import QuartzCore

extension Notification.Name {
    static let launchpadFolderWillDissolve = Notification.Name("LaunchpadFolderWillDissolve")
}

@MainActor
final class FolderDissolveTransition {
    let folderID: String
    let slots: [String: Int]
    let iconRect: CGRect
    let previewImage: CGImage?
    let previewSide: CGFloat
    let plate = CALayer()
    let oldPositions: [String: CGPoint]
    let createdAt = CACurrentMediaTime()
    var startedAt: CFTimeInterval?
    var originalContainerZ: CGFloat?
    static let duration: CFTimeInterval = 0.24

    init(folder: FolderInfo, iconRect: CGRect, oldPositions: [String: CGPoint],
         previewImage: CGImage?, previewSide: CGFloat) {
        folderID = folder.id
        slots = Dictionary(folder.apps.enumerated().map { ($0.element.url.path, $0.offset) },
                           uniquingKeysWith: { first, _ in first })
        self.iconRect = iconRect
        self.previewImage = previewImage
        self.previewSide = previewSide
        self.oldPositions = oldPositions
    }

    /// Borrow the bitmap already on screen instead of decoding app artwork on
    /// the main thread. The normal asynchronous grid load replaces this tile.
    func previewTile(at slot: Int) -> CGImage? {
        guard let previewImage, previewSide.isFinite, previewSide > 0,
              let tile = FolderPreviewLayout.iconRect(at: slot, side: previewSide) else { return nil }
        let scaleX = CGFloat(previewImage.width) / previewSide
        let scaleY = CGFloat(previewImage.height) / previewSide
        let crop = CGRect(x: tile.minX * scaleX,
                          y: CGFloat(previewImage.height) - tile.maxY * scaleY,
                          width: tile.width * scaleX, height: tile.height * scaleY).integral
        return previewImage.cropping(to: crop)
    }
}

extension CAGridView {
    @objc func folderWillDissolve(_ notification: Notification) {
        guard let folder = notification.object as? FolderInfo else { return }
        beginFolderDissolve(folder)
    }

    func beginFolderDissolve(_ folder: FolderInfo) {
        finishFolderDissolve()
        guard animationsEnabled, window?.isVisible == true, !isHiddenOrHasHiddenAncestor,
              let root = layer, itemsPerPage > 0,
              let index = items.firstIndex(where: { $0.id == "folder_\(folder.id)" }),
              iconLayers.indices.contains(index / itemsPerPage),
              iconLayers[index / itemsPerPage].indices.contains(index % itemsPerPage) else { return }
        finishDragLanding()
        let cell = iconLayers[index / itemsPerPage][index % itemsPerPage]
        guard let icon = cell.sublayers?.first(where: { $0.name == "icon" }),
              let glass = cell.sublayers?.first(where: { $0.name == "glass" }) else { return }
        let rect = icon.convert(icon.bounds, to: root)
        guard rect.intersects(bounds) else { return }
        // Only remember visible neighbors, not every application in every page.
        var positions: [String: CGPoint] = [:]
        for (item, oldCell) in zip(items, iconLayers.flatMap({ $0 })) {
            if oldCell.convert(oldCell.bounds, to: root).intersects(bounds) {
                positions[item.id] = pageContainerLayer.convert(oldCell.position, to: root)
            }
        }
        let previewImage: CGImage?
        if let contents = icon.contents, CFGetTypeID(contents as CFTypeRef) == CGImage.typeID {
            previewImage = (contents as! CGImage)
        } else {
            previewImage = nil
        }
        let transition = FolderDissolveTransition(folder: folder, iconRect: rect, oldPositions: positions,
                                                 previewImage: previewImage,
                                                 previewSide: icon.bounds.width)
        transition.plate.bounds = CGRect(origin: .zero, size: rect.size)
        transition.plate.position = CGPoint(x: rect.midX, y: rect.midY)
        transition.plate.zPosition = 0.5
        let plate = CALayer()
        plate.name = "glass"
        plate.frame = glass.convert(glass.bounds, to: icon)
        plate.cornerRadius = glass.cornerRadius
        plate.backgroundColor = glass.backgroundColor
        plate.borderColor = glass.borderColor
        plate.borderWidth = glass.borderWidth
        transition.plate.addSublayer(plate)
        // The overlay expects a preview child; this backplate intentionally has
        // no bitmap. The real destination app layers provide all moving icons.
        let emptyPreview = CALayer()
        emptyPreview.name = "icon"
        emptyPreview.frame = transition.plate.bounds
        transition.plate.addSublayer(emptyPreview)
        folderDissolveTransition = transition
    }

    /// Repeated publications of the same dissolved layout must not replace the
    /// layers while they expand. Content/layout changes take the normal path.
    func preserveFolderDissolveLayers(previousItems: [LaunchpadItem]?) -> Bool {
        guard let transition = folderDissolveTransition, transition.startedAt != nil else { return false }
        if let previousItems, previousItems.count == items.count,
           zip(previousItems, items).allSatisfy({ $0.hasSameGridContent(as: $1) }) {
            return true
        }
        finishFolderDissolve()
        return false
    }

    func startFolderDissolveIfReady() {
        guard let transition = folderDissolveTransition, transition.startedAt == nil,
              !items.contains(where: { $0.id == "folder_\(transition.folderID)" }),
              let root = layer else { return }
        let now = CACurrentMediaTime()
        transition.startedAt = now
        CATransaction.begin()
        CATransaction.setDisableActions(true)
        transition.originalContainerZ = containerLayer.zPosition
        // Actual app layers expand above the native material, without copying
        // them into a second set of floating preview layers.
        containerLayer.zPosition = max(2, containerLayer.zPosition)
        root.addSublayer(transition.plate)
        for (item, cell) in zip(items, iconLayers.flatMap({ $0 })) {
            guard let icon = cell.sublayers?.first(where: { $0.name == "icon" }),
                  icon.convert(icon.bounds, to: root).intersects(bounds) else { continue }
            if case .app(let app) = item, let slot = transition.slots[app.url.path] {
                if icon.contents == nil {
                    icon.contents = transition.previewTile(at: slot)
                }
                let tile = FolderPreviewLayout.iconRect(at: slot, side: transition.iconRect.width)
                let startRect = tile.map {
                    $0.offsetBy(dx: transition.iconRect.minX, dy: transition.iconRect.minY)
                } ?? transition.iconRect.insetBy(dx: transition.iconRect.width * 0.42,
                                                 dy: transition.iconRect.height * 0.42)
                let startCenter = root.convert(CGPoint(x: startRect.midX, y: startRect.midY), to: pageContainerLayer)
                let offset = CGPoint(x: icon.position.x - cell.bounds.midX,
                                     y: icon.position.y - cell.bounds.midY)
                let move = CABasicAnimation(keyPath: "position")
                move.fromValue = NSValue(point: CGPoint(x: startCenter.x - offset.x, y: startCenter.y - offset.y))
                move.toValue = NSValue(point: cell.position)
                addDissolveAnimation(move, to: cell, key: "dissolvePosition")
                let grow = CABasicAnimation(keyPath: "transform.scale")
                grow.fromValue = startRect.width / max(1, icon.bounds.width)
                grow.toValue = 1
                addDissolveAnimation(grow, to: icon, key: "dissolveScale")
                if tile == nil { addDissolveFade(to: icon, from: 0, to: 1) }
                if let label = cell.sublayers?.first(where: { $0.name == "label" }) {
                    let fade = CAKeyframeAnimation(keyPath: "opacity")
                    fade.values = [0, 0, 1]; fade.keyTimes = [0, 0.6, 1]
                    addDissolveAnimation(fade, to: label, key: "dissolveOpacity")
                }
            } else if let oldPosition = transition.oldPositions[item.id] {
                let move = CABasicAnimation(keyPath: "position")
                move.fromValue = NSValue(point: root.convert(oldPosition, to: pageContainerLayer))
                move.toValue = NSValue(point: cell.position)
                if oldPosition != pageContainerLayer.convert(cell.position, to: root) {
                    addDissolveAnimation(move, to: cell, key: "dissolvePosition")
                }
            }
        }
        let shrink = CABasicAnimation(keyPath: "transform.scale")
        shrink.fromValue = 1; shrink.toValue = 0.15
        // This temporary plate keeps its initial model geometry until removal.
        // Before its first presentation frame exists, native glass must see the
        // full-size plate, not the final small size (which would flash back up).
        addDissolveAnimation(shrink, to: transition.plate, key: "dissolveScale")
        addDissolveFade(to: transition.plate, from: 1, to: 0.01)
        syncFolderGlass()
        CATransaction.commit()
    }

    private func addDissolveAnimation(_ animation: CAAnimation, to layer: CALayer, key: String) {
        animation.duration = FolderDissolveTransition.duration
        animation.fillMode = .forwards
        animation.isRemovedOnCompletion = false
        animation.timingFunction = CAMediaTimingFunction(name: .easeInEaseOut)
        layer.add(animation, forKey: key)
    }

    private func addDissolveFade(to layer: CALayer, from: Float, to: Float) {
        let fade = CABasicAnimation(keyPath: "opacity")
        fade.fromValue = from; fade.toValue = to
        addDissolveAnimation(fade, to: layer, key: "dissolveOpacity")
    }

    func updateFolderDissolve(at now: CFTimeInterval) {
        guard let transition = folderDissolveTransition else { return }
        guard window?.isVisible == true, !isHiddenOrHasHiddenAncestor,
              now - transition.createdAt < 0.8 else { finishFolderDissolve(); return }
        if let start = transition.startedAt {
            if now - start >= FolderDissolveTransition.duration { finishFolderDissolve() }
            else { syncFolderGlass() }
        }
    }

    func finishFolderDissolve() {
        guard let transition = folderDissolveTransition else { return }
        CATransaction.begin()
        CATransaction.setDisableActions(true)
        for cell in iconLayers.flatMap({ $0 }) {
            cell.removeAnimation(forKey: "dissolvePosition")
            for child in cell.sublayers ?? [] {
                child.removeAnimation(forKey: "dissolveScale")
                child.removeAnimation(forKey: "dissolveOpacity")
            }
        }
        if let originalZ = transition.originalContainerZ { containerLayer.zPosition = originalZ }
        folderGlassOverlay?.removeDraggingGlass(for: transition.plate)
        transition.plate.removeFromSuperlayer()
        folderDissolveTransition = nil
        syncFolderGlass()
        CATransaction.commit()
    }
}
