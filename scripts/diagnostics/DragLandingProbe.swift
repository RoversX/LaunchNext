import AppKit
import QuartzCore

struct LaunchpadItem {
    let id: String
    var name: String { id }
    var contentVersion = 0
    func hasSameGridContent(as other: Self) -> Bool { id == other.id && contentVersion == other.contentVersion }
}

// Minimal host for the production landing extension and glass overlay. This
// checks actual CA geometry/lifecycle, not the app's model-reordering callback.
@MainActor
final class CAGridView: NSView {
    typealias Item = LaunchpadItem
    var items: [Item] = []
    var itemsRevision = 0
    var selectedIndex: Int?
    var hoveredIndex: Int?
    var pressedIndex: Int?
    var dropTargetIndex: Int?
    let itemsPerPage = 2
    var iconLayers: [[CALayer]] = []
    let pageContainerLayer = CALayer()
    var draggingLayer: CALayer?
    var dragLanding: DragLanding?
    var overlay: FolderGlassOverlay?

    override init(frame: NSRect) {
        super.init(frame: frame)
        wantsLayer = true
        pageContainerLayer.frame = CGRect(x: 0, y: 0, width: frame.width * 2, height: frame.height)
        layer!.addSublayer(pageContainerLayer)
    }
    required init?(coder: NSCoder) { fatalError() }

    func syncFolderGlass(geometryChanged: Bool = true) {
        overlay?.sync(containers: iconLayers.flatMap { $0 } + (draggingLayer.map { [$0] } ?? []),
                      root: layer!, page: pageContainerLayer, viewport: bounds,
                      geometryChanged: geometryChanged)
    }

    func animateFolderGlass() { syncFolderGlass() }

    func removeDraggingVisuals() {
        if let draggingLayer {
            overlay?.removeDraggingGlass(for: draggingLayer)
            draggingLayer.removeFromSuperlayer()
        }
        draggingLayer = nil
    }

    func gridCenterForGlobalIndex(_ index: Int) -> CGPoint {
        CGPoint(x: 130 + CGFloat(index % 2) * 190 + CGFloat(index / 2) * bounds.width, y: 150)
    }
    func applyScaleForIndex(_ index: Int, animated: Bool) {}
    func updateLayout() {
        for (index, cell) in iconLayers.flatMap({ $0 }).enumerated() {
            cell.position = gridCenterForGlobalIndex(index)
        }
        syncFolderGlass()
    }

    func rebuild(_ ids: [String]) {
        CATransaction.begin()
        CATransaction.setDisableActions(true)
        if let draggingLayer { overlay?.resetPageGlass(keeping: draggingLayer) }
        iconLayers.flatMap { $0 }.forEach { $0.removeFromSuperlayer() }
        items = ids.map { Item(id: $0) }
        itemsRevision += 1
        iconLayers = []
        for (index, id) in ids.enumerated() {
            if index % itemsPerPage == 0 { iconLayers.append([]) }
            let cell = makeIcon(at: CGPoint(x: 130 + CGFloat(index % 2) * 190 + CGFloat(index / 2) * bounds.width,
                                           y: 150))
            // Cell includes a label margin; the icon's center differs from the
            // cell center, just as in the real grid.
            cell.bounds.size.height = 130
            if id == dragLanding?.itemID { cell.opacity = 0 }
            pageContainerLayer.addSublayer(cell)
            iconLayers[iconLayers.count - 1].append(cell)
        }
        syncFolderGlass()
        CATransaction.commit()
    }

    func lift(_ id: String) -> CALayer {
        let index = items.firstIndex { $0.id == id }!
        let source = iconLayers[index / 2][index % 2]
        source.opacity = 0
        let drag = makeIcon(at: CGPoint(x: 250, y: 250))
        drag.transform = CATransform3DMakeScale(1.1, 1.1, 1)
        drag.zPosition = 1000
        layer!.addSublayer(drag)
        draggingLayer = drag
        syncFolderGlass()
        return drag
    }

    private func makeIcon(at position: CGPoint) -> CALayer {
        let container = CALayer()
        container.bounds = CGRect(x: 0, y: 0, width: 100, height: 100)
        container.position = position
        let glass = CALayer()
        glass.name = "glass"
        glass.frame = CGRect(x: 10, y: 10, width: 80, height: 80)
        glass.backgroundColor = NSColor.gray.cgColor
        let icon = CALayer()
        icon.name = "icon"
        icon.frame = container.bounds
        container.addSublayer(glass)
        container.addSublayer(icon)
        return container
    }
}

@main
struct DragLandingProbe {
    @MainActor static func main() {
        let app = NSApplication.shared
        app.setActivationPolicy(.accessory)
        let window = NSWindow(contentRect: CGRect(x: 120, y: 120, width: 520, height: 380),
                              styleMask: [.titled], backing: .buffered, defer: false)
        window.title = "LaunchNext · Drag landing checks"
        let grid = CAGridView(frame: CGRect(x: 0, y: 0, width: 520, height: 380))
        window.contentView = grid
        window.orderFrontRegardless()
        DispatchQueue.main.asyncAfter(deadline: .now() + 0.15) {
            for glass in [false, true] {
                if glass {
                    let overlay = FolderGlassOverlay(frame: grid.bounds)
                    grid.addSubview(overlay)
                    grid.overlay = overlay
                }
                CATransaction.begin()
                CATransaction.setDisableActions(true)
                grid.rebuild(["folder", "app", "other"])
                let drag = grid.lift("folder")
                let source = grid.iconLayers[0][0]
                grid.beginDragLanding(itemID: "folder", waitingForRevision: nil)
                let t = grid.dragLanding!.createdAt
                grid.updateDragLanding(at: t)
                precondition(drag.position == CGPoint(x: 250, y: 250))
                precondition(source.opacity == 0)
                grid.updateDragLanding(at: t + 0.09)
                let icon = source.sublayers!.first { $0.name == "icon" }!
                let target = icon.convert(icon.bounds, to: grid.layer!)
                precondition(drag.position.x > target.midX && drag.position.x < 250)
                precondition(drag.transform.m11 > 1 && drag.transform.m11 < 1.1)
                precondition(source.opacity == 0 && grid.draggingLayer === drag)
                grid.updateDragLanding(at: t + 0.19)
                precondition(abs(drag.position.x - target.midX) < 0.001)
                precondition(abs(drag.position.y - target.midY) < 0.001, "land on icon, not label/cell center")
                precondition(grid.dragLanding == nil && grid.draggingLayer == nil && source.opacity == 1)

                let reorderedDrag = grid.lift("folder")
                grid.beginDragLanding(itemID: "folder", waitingForRevision: grid.itemsRevision, predictedIndex: 2)
                let reorderTime = grid.dragLanding!.createdAt
                grid.pageContainerLayer.transform = CATransform3DMakeTranslation(-520, 0, 0)
                grid.syncFolderGlass()
                let initialPosition = reorderedDrag.position
                grid.updateDragLanding(at: reorderTime)
                grid.updateDragLanding(at: reorderTime + 1.0 / 60)
                precondition(reorderedDrag.position != initialPosition, "reorder must move on the first frame, before model publication")
                precondition(reorderedDrag.transform.m11 < 1.1, "reorder must shrink immediately")
                let plannedTarget = grid.dragLanding!.target
                grid.itemsRevision += 1 // refresh publishes the old order first
                grid.updateDragLanding(at: reorderTime + 0.03)
                precondition(grid.dragLanding!.target == plannedTarget
                             && grid.dragLanding!.startedAt == reorderTime,
                             "unrelated publication must not redirect the preview to the old cell")
                // AppKit may not have created the native backing layer yet.
                let dragGlass = grid.overlay.map { nativeViews($0).first { abs($0.frame.width - 80 * reorderedDrag.transform.m11) < 0.001 }! }
                let oldItems = grid.items
                let oldLayers = grid.iconLayers.flatMap { $0 }
                grid.items = [CAGridView.Item(id: "app"), CAGridView.Item(id: "other"), CAGridView.Item(id: "folder")]
                grid.itemsRevision += 1
                precondition(grid.reuseLayersDuringLanding(previousItems: oldItems))
                precondition(grid.iconLayers[1][0] === oldLayers[0], "reorder must reuse source layer")
                precondition(grid.iconLayers[0][0] === oldLayers[1], "neighbor layer must survive")
                let neighborMove = oldLayers[1].animation(forKey: "position") as? CABasicAnimation
                precondition(neighborMove != nil, "reused neighbors must animate to their new cells")
                precondition(neighborMove!.duration == GridLayerMotion.duration)
                let stableItems = grid.items
                grid.items[0].contentVersion += 1
                precondition(!grid.reuseLayersDuringLanding(previousItems: stableItems), "changed content must rebuild")
                grid.items = stableItems
                grid.pageContainerLayer.transform = CATransform3DMakeTranslation(-520, 0, 0)
                grid.syncFolderGlass()
                if let dragGlass {
                    precondition(nativeViews(grid.overlay!).contains { $0 === dragGlass }, "rebuild must retain native drag material")
                }
                precondition(grid.iconLayers[1][0].opacity == 0 && grid.iconLayers[0][0].opacity == 1)
                grid.updateDragLanding(at: reorderTime + 0.11)
                precondition(grid.dragLanding!.startedAt == reorderTime, "correct prediction must not restart animation")
                grid.updateDragLanding(at: reorderTime + 0.14)
                // A second layout/compaction replaces the cell during landing.
                let beforeCorrection = reorderedDrag.position
                grid.rebuild(["app", "folder", "other"])
                grid.updateDragLanding(at: reorderTime + 0.14)
                precondition(abs(reorderedDrag.position.x - beforeCorrection.x) < 0.001
                    && abs(reorderedDrag.position.y - beforeCorrection.y) < 0.001,
                    "retarget must be continuous at the same time")
                grid.updateDragLanding(at: reorderTime + 0.31)
                let finalIcon = grid.iconLayers[0][1].sublayers!.first { $0.name == "icon" }!
                let finalRect = finalIcon.convert(finalIcon.bounds, to: grid.layer!)
                precondition(abs(reorderedDrag.position.x - finalRect.midX) < 0.001)
                precondition(grid.iconLayers[0][1].opacity == 1 && grid.dragLanding == nil)

                _ = grid.lift("folder")
                grid.beginDragLanding(itemID: "folder", waitingForRevision: nil)
                grid.finishDragLanding() // next input or hide
                let nextDrag = grid.lift("folder")
                grid.updateDragLanding(at: CACurrentMediaTime() + 1)
                precondition(grid.draggingLayer === nextDrag, "old completion must not remove a new drag")
                grid.removeDraggingVisuals()

                _ = grid.lift("folder")
                grid.beginDragLanding(itemID: "folder", waitingForRevision: grid.itemsRevision)
                let rejectedTime = grid.dragLanding!.createdAt
                grid.updateDragLanding(at: rejectedTime + 0.3)
                grid.updateDragLanding(at: rejectedTime + 0.5)
                precondition(grid.dragLanding == nil, "unpublished reorder must not leave an infinite preview")

                _ = grid.lift("folder")
                grid.beginDragLanding(itemID: "folder", waitingForRevision: nil)
                grid.rebuild(["app", "other"])
                grid.updateDragLanding(at: CACurrentMediaTime())
                precondition(grid.dragLanding == nil && grid.draggingLayer == nil, "removed item must release landing")
                grid.pageContainerLayer.transform = CATransform3DIdentity
                grid.rebuild(["app", "folder"])
                let mergeDrag = grid.lift("app")
                precondition(grid.beginMergeLanding(itemID: "app", targetID: "folder"))
                let mergeTime = grid.dragLanding!.createdAt
                grid.updateDragLanding(at: mergeTime + 0.04)
                precondition(grid.iconLayers[0][0].opacity == 0, "merge must not flash the old source")
                let fadingOpacity = mergeDrag.opacity
                grid.rebuild(["folder"])
                grid.updateDragLanding(at: mergeTime + 0.07)
                precondition(grid.draggingLayer === mergeDrag && grid.dragLanding != nil,
                             "removing merged source must retain its visual until arrival")
                precondition(mergeDrag.opacity <= fadingOpacity, "moving target must not restart fading")
                grid.updateDragLanding(at: mergeTime + 0.35)
                precondition(grid.dragLanding == nil && grid.draggingLayer == nil)
                precondition(grid.iconLayers[0][0].opacity == 1)

                grid.rebuild(["app", "target"])
                _ = grid.lift("app")
                precondition(grid.beginMergeLanding(itemID: "app", targetID: "target"))
                let creationTime = grid.dragLanding!.createdAt
                grid.rebuild(["new-folder"])
                grid.updateDragLanding(at: creationTime + 0.08)
                precondition(grid.dragLanding != nil, "new folder must use snapshotted target after replacement")
                grid.updateDragLanding(at: creationTime + 0.3)
                precondition(grid.dragLanding == nil)

                grid.rebuild(["app", "folder"])
                _ = grid.lift("app")
                precondition(grid.beginMergeLanding(itemID: "app", targetID: "folder"))
                let rejectedMergeTime = grid.dragLanding!.createdAt
                grid.updateDragLanding(at: rejectedMergeTime + 0.3)
                precondition(grid.dragLanding == nil && grid.iconLayers[0][0].opacity == 1,
                             "rejected merge must restore source with bounded cleanup")

                grid.rebuild(["folder", "empty", "app", "empty2"])
                grid.pageContainerLayer.transform = CATransform3DMakeTranslation(-520, 0, 0)
                _ = grid.lift("folder")
                grid.beginDragLanding(itemID: "folder", waitingForRevision: grid.itemsRevision,
                                      predictedIndex: 1, predictedPageOffset: 0)
                let compactTime = grid.dragLanding!.createdAt
                grid.updateDragLanding(at: compactTime + 0.03)
                let compactTarget = grid.dragLanding!.target
                grid.rebuild(["app", "folder"])
                grid.pageContainerLayer.transform = CATransform3DIdentity
                grid.updateDragLanding(at: compactTime + 0.06)
                precondition(grid.dragLanding!.target == compactTarget
                             && grid.dragLanding!.startedAt == compactTime,
                             "compaction/page removal must not introduce a second landing target")
                grid.updateDragLanding(at: compactTime + 0.19)
                precondition(grid.dragLanding == nil && grid.iconLayers[0][1].opacity == 1)

                // Continuous layout/target changes must not extend the entire
                // landing indefinitely, even though each segment is retargeted.
                for merging in [false, true] {
                    grid.rebuild(["folder", "app"])
                    let boundedDrag = grid.lift("folder")
                    if merging {
                        precondition(grid.beginMergeLanding(itemID: "folder", targetID: "app"))
                    } else {
                        grid.beginDragLanding(itemID: "folder", waitingForRevision: nil)
                    }
                    let boundedStart = grid.dragLanding!.createdAt
                    let targetCell = grid.iconLayers[0][merging ? 1 : 0]
                    for frame in 1...59 {
                        targetCell.position.x += 0.1
                        grid.updateDragLanding(at: boundedStart + Double(frame) / 120)
                    }
                    precondition(grid.dragLanding != nil, "test must keep retargeting until near the deadline")
                    targetCell.position.x += 0.1
                    grid.updateDragLanding(at: boundedStart + DragLanding.maximumDuration + 0.001)
                    precondition(grid.dragLanding == nil && grid.draggingLayer == nil)
                    precondition(boundedDrag.superlayer == nil && grid.iconLayers[0][0].opacity == 1,
                                 "absolute deadline must remove the preview and restore any surviving source")
                }
                grid.pageContainerLayer.transform = CATransform3DIdentity
                grid.overlay?.reset()
                grid.overlay?.removeFromSuperview()
                grid.overlay = nil
                CATransaction.commit()
            }
            print("PASS: classic/glass landing, continuous move/scale, label-aware target, immediate pre-publication movement, layer reuse, smooth retarget, cross-page coordinates, second rebuild, native material retention, interruption/new drag, bounded fallback, removed item, merge source hiding/removal, moving merge target, new-folder target replacement, rejected merge cleanup, absolute deadline under continuous retargeting")
            app.terminate(nil)
        }
        app.run()
    }

    @MainActor private static func nativeViews(_ view: NSView) -> [NSGlassEffectView] {
        (view as? NSGlassEffectView).map { [$0] } ?? view.subviews.flatMap { nativeViews($0) }
    }
}
