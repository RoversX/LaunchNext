import AppKit
import SwiftUI
import QuartzCore
import Combine

/// One presentation per launcher. The grid and presentation host are borrowed,
/// not retained; closing releases the hosting view and transient preview layers.
@MainActor
final class CAFolderPresentationController: ObservableObject {
    weak var grid: CAGridView?
    weak var backdrop: CAFolderBackdropView?
    weak var host: CAFolderPresentationHost?

    func dismissImmediately() { host?.dismissImmediately() }
}

/// Scale one ancestor so the CA icons and native glass subviews stay together.
/// The grid keeps its normal layout and coordinate system throughout the motion.
@MainActor
final class CAFolderBackdropView: NSView {
    let grid: CAGridView
    private var depthPivotInWindow: CGPoint?

    convenience init() {
        self.init(grid: CAGridView(frame: .zero))
    }

    init(grid: CAGridView) {
        self.grid = grid
        super.init(frame: grid.frame)
        wantsLayer = true
        clipsToBounds = false
        addSubview(grid)
    }
    required init?(coder: NSCoder) { fatalError("init(coder:) has not been implemented") }

    override func layout() {
        super.layout()
        if grid.frame != bounds { grid.frame = bounds }
    }

    func setFolderDepth(_ recessed: Bool, duration: TimeInterval, pivotInWindow: CGPoint? = nil, motion: FolderPresentationMotion? = nil) {
        guard let layer else { return }
        if let pivotInWindow { depthPivotInWindow = pivotInWindow }
        let initial = (layer.presentation() ?? layer).sublayerTransform
        let scale: CGFloat = recessed ? 0.97 : 1
        let pivot = depthPivotInWindow.map { convert($0, from: nil) } ?? CGPoint(x: bounds.midX, y: bounds.midY)
        let anchor = CGPoint(x: bounds.minX + bounds.width * layer.anchorPoint.x,
                             y: bounds.minY + bounds.height * layer.anchorPoint.y)
        var target = CATransform3DMakeScale(scale, scale, 1)
        // AppKit layer anchors are not necessarily at the view's center.
        target.m41 = (pivot.x - anchor.x) * (1 - scale)
        target.m42 = (pivot.y - anchor.y) * (1 - scale)
        CATransaction.begin()
        CATransaction.setDisableActions(true)
        layer.sublayerTransform = target
        if let motion {
            layer.add(motion.animation(keyPath: "sublayerTransform", on: layer) {
                NSValue(caTransform3D: FolderPresentationMotion.transform(from: initial, to: target, fraction: $0))
            }, forKey: "folderPresentation.depth")
        } else {
            layer.removeAnimation(forKey: "folderPresentation.depth")
        }
        CATransaction.commit()
        if !recessed && duration == 0 { depthPivotInWindow = nil }
    }

    func presentedRect(forWindowRect rect: CGRect) -> CGRect {
        guard let layer else { return rect }
        let local = convert(rect, from: nil)
        let value = (layer.presentation() ?? layer).sublayerTransform
        let anchor = CGPoint(x: bounds.minX + bounds.width * layer.anchorPoint.x,
                             y: bounds.minY + bounds.height * layer.anchorPoint.y)
        return convert(CGRect(x: anchor.x + (local.minX - anchor.x) * value.m11 + value.m41,
                              y: anchor.y + (local.minY - anchor.y) * value.m22 + value.m42,
                              width: local.width * value.m11, height: local.height * value.m22), to: nil)
    }
}

@MainActor
final class CAFolderPresentationState {
    var allowsInteraction = false
    weak var grid: CAFolderGridView?
    var onLayout: (() -> Void)?
}

struct CAFolderOpeningSource {
    let iconRectInWindow: CGRect
    let plateRectInWindow: CGRect
    let preview: CGImage?
    let previewSide: CGFloat
    let paths: [String]

    func tileInWindow(for path: String) -> CGRect? {
        guard let index = paths.firstIndex(of: path),
              let tile = FolderPreviewLayout.iconRect(at: index, side: previewSide),
              previewSide > 0 else { return nil }
        let sx = iconRectInWindow.width / previewSide
        let sy = iconRectInWindow.height / previewSide
        return CGRect(x: iconRectInWindow.minX + tile.minX * sx,
                      y: iconRectInWindow.minY + tile.minY * sy,
                      width: tile.width * sx, height: tile.height * sy)
    }

    func previewTile(for path: String) -> CGImage? {
        guard let preview, let index = paths.firstIndex(of: path),
              let tile = FolderPreviewLayout.iconRect(at: index, side: previewSide),
              previewSide > 0 else { return nil }
        let sx = CGFloat(preview.width) / previewSide
        let sy = CGFloat(preview.height) / previewSide
        return preview.cropping(to: CGRect(x: tile.minX * sx,
            y: CGFloat(preview.height) - tile.maxY * sy,
            width: tile.width * sx, height: tile.height * sy).integral)
    }
}

extension CAGridView {
    private func presentationContainer(at index: Int) -> CALayer? {
        guard itemsPerPage > 0, index >= 0 else { return nil }
        return iconLayers[safe: index / itemsPerPage]?[safe: index % itemsPerPage]
    }

    func folderOpeningSource(id: String, atRest: Bool = false) -> CAFolderOpeningSource? {
        guard window != nil, let root = layer,
              let index = items.firstIndex(where: { $0.id == "folder_\(id)" }),
              case let .folder(folder) = items[index],
              let container = presentationContainer(at: index),
              let icon = container.sublayers?.first(where: { $0.name == "icon" }),
              let plate = container.sublayers?.first(where: { $0.name == "glass" }),
              icon.bounds.width > 0 else { return nil }
        let visualRoot = root.presentation() ?? root
        let visualIcon = icon.presentation() ?? icon
        let visualPlate = plate.presentation() ?? plate
        let rect = visualIcon.convert(visualIcon.bounds, to: visualRoot)
        guard rect.intersects(bounds), rect.width.isFinite, rect.height.isFinite else { return nil }
        let image: CGImage?
        if let contents = icon.contents, CFGetTypeID(contents as CFTypeRef) == CGImage.typeID {
            image = (contents as! CGImage)
        } else { image = nil }
        func windowRect(_ rect: CGRect) -> CGRect {
            let result = convert(rect, to: nil)
            guard !atRest, let backdrop = superview as? CAFolderBackdropView else { return result }
            return backdrop.presentedRect(forWindowRect: result)
        }
        return CAFolderOpeningSource(iconRectInWindow: windowRect(rect),
            plateRectInWindow: windowRect(visualPlate.convert(visualPlate.bounds, to: visualRoot)),
            preview: image, previewSide: icon.bounds.width,
            paths: folder.apps.prefix(9).map { $0.url.path })
    }

    func setPresentedFolderID(_ id: String?) {
        guard presentedFolderID != id else { return }
        CATransaction.begin()
        CATransaction.setDisableActions(true)
        for (index, item) in items.enumerated() {
            guard case let .folder(folder) = item,
                  folder.id == presentedFolderID || folder.id == id,
                  let container = presentationContainer(at: index) else { continue }
            container.opacity = folder.id == id ? 0 : 1
        }
        presentedFolderID = id
        syncFolderGlass()
        CATransaction.commit()
    }
}

struct CAFolderPresentation: NSViewRepresentable {
    @ObservedObject var appStore: AppStore
    let controller: CAFolderPresentationController
    let iconSize: CGFloat
    let onClose: () -> Void
    let onLaunchApp: (AppInfo) -> Void

    func makeNSView(context: Context) -> CAFolderPresentationHost {
        let host = CAFolderPresentationHost()
        host.controller = controller
        controller.host = host
        return host
    }

    func updateNSView(_ host: CAFolderPresentationHost, context: Context) {
        host.update(appStore: appStore, iconSize: iconSize, onClose: onClose, onLaunchApp: onLaunchApp)
    }

    static func dismantleNSView(_ host: CAFolderPresentationHost, coordinator: ()) {
        host.dismissImmediately()
    }
}

@MainActor
final class CAFolderPresentationHost: NSView {
    weak var controller: CAFolderPresentationController?
    private var hosting: NSHostingView<FolderView>?
    private var glass: NSGlassEffectView?
    private var glassContainer: NSView?
    private var glassClipContainer: NSView?
    private var animationStage: NSView?
    private var glassMask: CAShapeLayer?
    private var state: CAFolderPresentationState?
    private var source: CAFolderOpeningSource?
    private var folderID: String?
    private var completion: DispatchWorkItem?
    private var transitionGeneration = 0
    private var preparationTimeout: DispatchWorkItem?
    private var reopeningGlassFrame: CGRect?
    private var openingScheduled = false
    private var phase: Phase = .closed
    private var duration: TimeInterval = 0.24
    private var motionEnabled = true
    private var motion: FolderPresentationMotion?
    private var onRequestReopen: ((String) -> Bool)?
    private var onRequestClose: (() -> Void)?
    private weak var forwardedMouseTarget: NSView?
    private var fullscreen = true
    private var widthFactor: CGFloat = 0.7
    private var heightFactor: CGFloat = 0.7
    private enum Phase { case closed, preparing, opening, open, closing }

    override init(frame: NSRect) {
        super.init(frame: frame)
        wantsLayer = true
        clipsToBounds = false
    }
    convenience init() { self.init(frame: .zero) }
    required init?(coder: NSCoder) { fatalError("init(coder:) has not been implemented") }

    override func hitTest(_ point: NSPoint) -> NSView? {
        guard phase != .closed, let hosting else { return nil }
        let local = convert(point, from: superview)
        if phase != .open { return bounds.contains(local) ? self : nil }
        guard hosting.frame.contains(local) else { return bounds.contains(local) ? self : nil }
        return super.hitTest(point)
    }

    override func acceptsFirstMouse(for event: NSEvent?) -> Bool { true }

    override func mouseDown(with event: NSEvent) {
        forwardedMouseTarget = nil
        if phase == .closing, let id = folderID, let grid = controller?.grid,
           let (item, _) = grid.itemAt(grid.convert(event.locationInWindow, from: nil)),
           item.id == "folder_\(id)", onRequestReopen?(id) == true {
            reverseClosing()
            startOpeningIfReady(allowUnreadyIcons: true)
            return
        }
        if phase == .closing || phase == .closed {
            // AppKit may send a subsequent multi-click to the previous receiver
            // even after hitTest starts returning the background grid.
            // A new gesture must not be swallowed by the outgoing presentation.
            // Finish the transform before hit testing the destination control.
            let content = window?.contentView
            dismissImmediately()
            if let content, let target = content.hitTest(content.convert(event.locationInWindow, from: nil)),
               target !== self, !target.isDescendant(of: self) {
                forwardedMouseTarget = target
                target.mouseDown(with: event)
            }
            return
        }
        let point = convert(event.locationInWindow, from: nil)
        if phase == .preparing || !presentedGlassFrame.contains(point) {
            onRequestClose?()
        }
    }

    override func mouseDragged(with event: NSEvent) {
        forwardedMouseTarget?.mouseDragged(with: event)
    }

    override func mouseUp(with event: NSEvent) {
        let target = forwardedMouseTarget
        forwardedMouseTarget = nil
        target?.mouseUp(with: event)
    }

    override func layout() {
        super.layout()
        guard let hosting else { return }
        let target = panelRect
        if hosting.frame != target {
            // A resize changes the destination geometry: finish an opening, or
            // remove a closing panel, rather than leave old CA paths running.
            if phase == .closing { dismissImmediately(); return }
            if phase == .opening { finishOpening() }
            hosting.frame = target
            if phase == .open { layoutGlass() }
        }
        if phase == .preparing {
            hosting.layoutSubtreeIfNeeded()
            scheduleOpeningIfReady()
        }
    }

    private var panelRect: CGRect {
        let horizontal = min(fullscreen ? max(bounds.width * 0.15, 120) : 32, bounds.width / 2)
        let vertical = min(fullscreen ? max(bounds.height * 0.15, 120) : 32, bounds.height / 2)
        let maxWidth = max(0, bounds.width - horizontal * 2)
        let maxHeight = max(0, bounds.height - vertical * 2)
        let width = max(min(bounds.width * widthFactor, maxWidth), min(fullscreen ? 520 : 560, maxWidth))
        let height = max(min(bounds.height * heightFactor, maxHeight), min(420, maxHeight))
        return CGRect(x: (bounds.width - width) / 2, y: (bounds.height - height) / 2, width: width, height: height)
    }

    func update(appStore: AppStore, iconSize: CGFloat, onClose: @escaping () -> Void,
                onLaunchApp: @escaping (AppInfo) -> Void) {
        onRequestClose = {
            if !appStore.isFolderNameEditing { onClose() }
        }
        onRequestReopen = { id in
            guard let folder = appStore.folders.first(where: { $0.id == id }) else { return false }
            appStore.openFolderActivatedByKeyboard = false
            appStore.openFolder = folder
            return true
        }
        motionEnabled = appStore.enableAnimations && !NSWorkspace.shared.accessibilityDisplayShouldReduceMotion
        guard let folder = appStore.openFolder else {
            // An ongoing drag is handed directly to the main grid; retaining a
            // closing panel would cover that grid and duplicate the dragged app.
            if appStore.handoffDraggingApp != nil { dismissImmediately() }
            else { close() }
            return
        }
        fullscreen = appStore.isFullscreenMode
        widthFactor = fullscreen ? 0.7 : CGFloat(appStore.folderPopoverWidthFactor)
        heightFactor = fullscreen ? 0.7 : CGFloat(appStore.folderPopoverHeightFactor)
        let needsNewContent = folderID != folder.id || hosting == nil
        if needsNewContent {
            dismissImmediately()
            folderID = folder.id
            state = CAFolderPresentationState()
            source = controller?.grid?.folderOpeningSource(id: folder.id)
            phase = .preparing
        } else if phase == .closing {
            reverseClosing()
        }
        guard let state else { return }
        let binding = Binding<FolderInfo>(get: {
            appStore.folders.first(where: { $0.id == folder.id }) ?? folder
        }, set: { value in
            if let index = appStore.folders.firstIndex(where: { $0.id == folder.id }) {
                appStore.folders[index] = value
            }
        })
        let root = FolderView(appStore: appStore, folder: binding, preferredIconSize: iconSize,
                              presentationState: state, onClose: onClose, onLaunchApp: onLaunchApp)
        if let hosting { hosting.rootView = root }
        else {
            // Keep the clipping mask outside the transformed material subtree.
            let clip = NSView(frame: bounds)
            clip.wantsLayer = true
            clip.clipsToBounds = false
            glassClipContainer = clip
            addSubview(clip)
            let container = NSView(frame: bounds)
            container.wantsLayer = true
            container.clipsToBounds = false
            glassContainer = container
            clip.addSubview(container)
            let glass = NSGlassEffectView(frame: container.bounds)
            glass.style = .regular
            glass.cornerRadius = 30
            self.glass = glass
            container.addSubview(glass)
            let hosting = NSHostingView(rootView: root)
            hosting.wantsLayer = true
            hosting.clipsToBounds = false
            hosting.frame = panelRect
            self.hosting = hosting
            addSubview(hosting)
        }
        state.onLayout = { [weak self] in self?.scheduleOpeningIfReady() }
        if phase == .preparing {
            // Keep real content alive during preparation; opacity does not stop
            // layout or icon loading. No fixed delay gates the ready callback.
            if reopeningGlassFrame == nil {
                hosting?.alphaValue = 0
                glass?.alphaValue = 0
            }
            if preparationTimeout == nil {
                let timeout = DispatchWorkItem { [weak self] in
                    self?.startOpeningIfReady(allowUnreadyIcons: true)
                    if self?.phase == .preparing { self?.finishOpening() }
                }
                preparationTimeout = timeout
                DispatchQueue.main.asyncAfter(deadline: .now() + 0.2, execute: timeout)
            }
        }
        needsLayout = true
    }

    private func reverseClosing() {
        transitionGeneration += 1
        completion?.cancel(); completion = nil
        reopeningGlassFrame = presentedGlassFrame
        phase = .preparing
    }

    private func scheduleOpeningIfReady() {
        guard phase == .preparing, !openingScheduled else { return }
        openingScheduled = true
        // Start after AppKit/SwiftUI has finished the layout transaction.
        DispatchQueue.main.async { [weak self] in
            guard let self else { return }
            self.openingScheduled = false
            self.startOpeningIfReady()
        }
    }

    private func startOpeningIfReady(allowUnreadyIcons: Bool = false) {
        guard phase == .preparing else { return }
        // Apply SwiftUI's acknowledged page-indicator layout before measuring
        // destinations. Bitmap readiness alone does not imply stable geometry.
        hosting?.layoutSubtreeIfNeeded()
        guard phase == .preparing, window != nil, panelRect.width > 0, panelRect.height > 0,
              let grid = state?.grid, grid.window === window, grid.bounds.width > 0, grid.bounds.height > 0,
              grid.isPresentationLayoutReady,
              let hosting, let glass else { return }
        let iconsReady = grid.prepareFolderPresentation(from: source)
        guard iconsReady || allowUnreadyIcons else { return }
        let animated = motionEnabled && source != nil
        let start = reopeningGlassFrame != nil ? presentedGlassFrame
            : source.map { convert($0.plateRectInWindow, from: nil) } ?? panelRect
        let nextMotion = animated ? makeMotion(from: start, opening: true) : nil
        motion = nextMotion
        duration = nextMotion?.duration ?? 0
        phase = .opening
        preparationTimeout?.cancel(); preparationTimeout = nil
        beginTransitionCompletion { $0.finishOpening() }
        hosting.clipsToBounds = true
        hosting.layer?.cornerRadius = 30
        hosting.layer?.masksToBounds = true
        glass.alphaValue = 1
        let pivot = source.map { CGPoint(x: $0.plateRectInWindow.midX, y: $0.plateRectInWindow.midY) }
        controller?.backdrop?.setFolderDepth(animated, duration: duration, pivotInWindow: pivot, motion: nextMotion)
        controller?.grid?.setPresentedFolderID(folderID)
        grid.animateFolderPresentation(from: source, opening: true, duration: duration,
                                       in: ensureAnimationStage(), motion: nextMotion)
        if animated {
            animateGlass(from: start, to: panelRect)
        } else { layoutGlass() }
        reopeningGlassFrame = nil
        if animated { animateChrome(opening: true) }
        else { hosting.alphaValue = 1 }
        CATransaction.commit()
        if !animated { finishOpening() }
    }

    private func animateGlass(from start: CGRect, to end: CGRect) {
        layoutGlass()
        guard let layer = glassContainer?.layer, let clipLayer = glassClipContainer?.layer,
              panelRect.width > 0, panelRect.height > 0 else { return }
        let anchor = CGPoint(x: layer.bounds.minX + layer.bounds.width * layer.anchorPoint.x,
                             y: layer.bounds.minY + layer.bounds.height * layer.anchorPoint.y)
        func transform(for rect: CGRect) -> CATransform3D {
            var value = CATransform3DIdentity
            value.m11 = rect.width / panelRect.width
            value.m22 = rect.height / panelRect.height
            // sublayerTransform scales around the parent's anchor, not (0, 0).
            value.m41 = rect.minX - panelRect.minX * value.m11 - anchor.x * (1 - value.m11)
            value.m42 = rect.minY - panelRect.minY * value.m22 - anchor.y * (1 - value.m22)
            return value
        }
        // Animate the material subtree, not NSGlassEffectView's frame, which
        // AppKit can overwrite during layout. No per-frame Swift work is needed.
        guard let motion else { return }
        let animation = motion.animation(keyPath: "sublayerTransform", on: layer) {
            NSValue(caTransform3D: transform(for: FolderPresentationMotion.rect(from: start, to: end, fraction: $0)))
        }
        CATransaction.begin()
        CATransaction.setDisableActions(true)
        let mask = glassMask ?? CAShapeLayer()
        let oldPath = mask.presentation()?.path
        mask.frame = bounds
        let compact = source.map { convert($0.plateRectInWindow, from: nil) } ?? start
        let compactRadius = min(30, min(compact.width, compact.height) * 0.25)
        func path(for rect: CGRect) -> CGPath {
            let range = panelRect.width - compact.width
            let progress = abs(range) > 0.001 ? min(1, max(0, (rect.width - compact.width) / range)) : 1
            let radius = compactRadius + (30 - compactRadius) * progress
            return CGPath(roundedRect: rect, cornerWidth: radius, cornerHeight: radius, transform: nil)
        }
        let rounding = motion.animation(keyPath: "path", on: clipLayer) { fraction in
            if fraction == 0, let oldPath { return oldPath }
            return path(for: FolderPresentationMotion.rect(from: start, to: end, fraction: fraction))
        }
        mask.path = path(for: end)
        mask.add(rounding, forKey: "folderPresentation.rounding")
        clipLayer.mask = mask
        glassMask = mask
        layer.sublayerTransform = transform(for: end)
        layer.add(animation, forKey: "folderPresentation.glass")
        CATransaction.commit()
    }

    private var presentedGlassFrame: CGRect {
        guard let material = glass?.layer, let root = layer else { return panelRect }
        // Ask CA for actual geometry, including anchor points and ancestor transforms.
        if let visual = material.presentation(), let visualRoot = root.presentation() {
            return visual.convert(visual.bounds, to: visualRoot)
        }
        return material.convert(material.bounds, to: root)
    }

    private func layoutGlass() {
        glassClipContainer?.frame = bounds
        glassContainer?.frame = bounds
        glass?.frame = panelRect
    }

    private func ensureAnimationStage() -> NSView {
        if let animationStage { return animationStage }
        let stage = NSView(frame: bounds)
        stage.wantsLayer = true
        stage.clipsToBounds = false
        addSubview(stage)
        animationStage = stage
        return stage
    }

    private func finishOpening() {
        guard phase != .closed, phase != .closing else { return }
        transitionGeneration += 1
        completion?.cancel(); completion = nil
        preparationTimeout?.cancel(); preparationTimeout = nil
        CATransaction.begin()
        CATransaction.setDisableActions(true)
        defer { CATransaction.commit() }
        phase = .open
        motion = nil
        hosting?.layer?.removeAnimation(forKey: "folderPresentation.chrome")
        hosting?.alphaValue = 1
        hosting?.clipsToBounds = true
        hosting?.layer?.cornerRadius = 30
        hosting?.layer?.masksToBounds = true
        glass?.alphaValue = 1
        glassContainer?.layer?.removeAnimation(forKey: "folderPresentation.glass")
        glassContainer?.layer?.sublayerTransform = CATransform3DIdentity
        layoutGlass()
        revealShadowAfterOpening()
        state?.allowsInteraction = true
        controller?.backdrop?.setFolderDepth(duration > 0 && source != nil, duration: 0)
        state?.grid?.finishFolderPresentation()
        animationStage?.removeFromSuperview(); animationStage = nil
        controller?.grid?.setPresentedFolderID(folderID)
    }

    /// Keep the material opaque while revealing only the area outside the card.
    /// This preserves AppKit's shadow rather than drawing a second one.
    private func revealShadowAfterOpening() {
        guard let clipLayer = glassClipContainer?.layer else { return }
        let shouldAnimate = motionEnabled && duration > 0 && glassMask != nil
        glassMask = nil
        guard shouldAnimate else {
            clipLayer.mask = nil
            return
        }
        let mask = CALayer()
        mask.frame = bounds
        let cardPath = CGPath(roundedRect: panelRect, cornerWidth: 30, cornerHeight: 30, transform: nil)
        let card = CAShapeLayer()
        card.path = cardPath
        card.fillColor = NSColor.black.cgColor
        mask.addSublayer(card)

        let outside = CAShapeLayer()
        let path = CGMutablePath()
        path.addRect(bounds)
        path.addPath(cardPath)
        outside.path = path
        outside.fillRule = .evenOdd
        outside.fillColor = NSColor.black.cgColor
        mask.addSublayer(outside)
        clipLayer.mask = mask

        CATransaction.begin()
        CATransaction.setDisableActions(true)
        CATransaction.setCompletionBlock { [weak clipLayer, weak mask] in
            DispatchQueue.main.async {
                // Closing or reopening may already have installed another mask.
                guard let clipLayer, let mask, clipLayer.mask === mask else { return }
                CATransaction.begin()
                CATransaction.setDisableActions(true)
                clipLayer.mask = nil
                CATransaction.commit()
            }
        }
        let fade = CABasicAnimation(keyPath: "opacity")
        fade.fromValue = Float(0)
        fade.toValue = Float(1)
        fade.duration = 0.16
        fade.timingFunction = CAMediaTimingFunction(name: .easeOut)
        outside.add(fade, forKey: "folderPresentation.shadowReveal")
        CATransaction.commit()
    }

    private func close() {
        guard phase != .closed, phase != .closing else { return }
        guard phase != .preparing, motionEnabled, window?.isVisible == true,
              let id = folderID, let destination = controller?.grid?.folderOpeningSource(id: id, atRest: true),
              let grid = state?.grid else { dismissImmediately(); return }
        let start = presentedGlassFrame
        let end = convert(destination.plateRectInWindow, from: nil)
        source = destination
        let nextMotion = makeMotion(from: start, opening: false)
        motion = nextMotion
        duration = nextMotion.duration
        phase = .closing
        state?.allowsInteraction = false
        completion?.cancel()
        preparationTimeout?.cancel(); preparationTimeout = nil
        source = destination
        beginTransitionCompletion { $0.dismissImmediately() }
        controller?.backdrop?.setFolderDepth(false, duration: duration, motion: nextMotion)
        grid.animateFolderPresentation(from: destination, opening: false, duration: duration,
                                       in: ensureAnimationStage(), motion: nextMotion)
        animateChrome(opening: false)
        animateGlass(from: start, to: end)
        CATransaction.commit()
    }

    private func makeMotion(from current: CGRect, opening: Bool) -> FolderPresentationMotion {
        let now = CACurrentMediaTime()
        let compact = source.map { convert($0.plateRectInWindow, from: nil) } ?? panelRect
        let range = panelRect.width - compact.width
        let progress = abs(range) > 0.001 ? (current.width - compact.width) / range : (opening ? 0 : 1)
        return FolderPresentationMotion(start: progress, target: opening ? 1 : 0,
            velocity: motion?.velocity(at: now) ?? 0, startTime: now, baseDuration: opening ? 0.24 : 0.28)
    }

    /// The host only contains labels/title while the shared icon proxies animate
    /// above it. The relative delay uses the same timeline as the geometry.
    private func animateChrome(opening: Bool) {
        guard let hosting, let layer = hosting.layer else { return }
        let opacity = layer.presentation()?.opacity ?? layer.opacity
        let fade = CABasicAnimation(keyPath: "opacity")
        fade.fromValue = opacity
        fade.toValue = opening ? Float(1) : Float(0)
        fade.beginTime = opening ? duration * 0.7 : 0
        fade.duration = duration * (opening ? 0.3 : 0.4)
        fade.fillMode = .both
        fade.timingFunction = CAMediaTimingFunction(name: .easeOut)
        let group = CAAnimationGroup()
        group.animations = [fade]
        group.duration = duration
        if let motion { group.beginTime = layer.convertTime(motion.startTime, from: nil) }
        group.fillMode = .both
        group.isRemovedOnCompletion = false
        hosting.alphaValue = opening ? 1 : 0
        layer.add(group, forKey: "folderPresentation.chrome")
    }

    /// Finish only after CA completes; interruptions invalidate callbacks.
    private func beginTransitionCompletion(action: @escaping (CAFolderPresentationHost) -> Void) {
        completion?.cancel()
        transitionGeneration += 1
        let generation = transitionGeneration
        let finish = { [weak self] in
            guard let self, self.transitionGeneration == generation else { return }
            action(self)
        }
        CATransaction.begin()
        CATransaction.setDisableActions(true)
        CATransaction.setCompletionBlock {
            // Completion may run while AppKit is flushing a layout transaction.
            DispatchQueue.main.async(execute: finish)
        }
        // Bound lifetime if a window disappears before the compositor completes.
        let watchdog = DispatchWorkItem(block: finish)
        completion = watchdog
        DispatchQueue.main.asyncAfter(deadline: .now() + duration + 1, execute: watchdog)
    }

    func dismissImmediately() {
        transitionGeneration += 1
        CATransaction.begin()
        CATransaction.setDisableActions(true)
        defer { CATransaction.commit() }
        completion?.cancel(); completion = nil
        preparationTimeout?.cancel(); preparationTimeout = nil
        reopeningGlassFrame = nil
        state?.onLayout = nil
        state?.grid?.finishFolderPresentation()
        animationStage?.removeFromSuperview(); animationStage = nil
        if let window, let responder = window.firstResponder as? NSView,
           let hosting, responder.isDescendant(of: hosting) {
            window.makeFirstResponder(controller?.grid)
        }
        hosting?.removeFromSuperview(); hosting = nil
        glass?.removeFromSuperview(); glass = nil
        glassContainer?.removeFromSuperview(); glassContainer = nil
        glassClipContainer?.removeFromSuperview(); glassClipContainer = nil
        glassMask = nil
        state = nil
        source = nil
        folderID = nil
        phase = .closed
        motion = nil
        controller?.backdrop?.setFolderDepth(false, duration: 0)
        controller?.grid?.setPresentedFolderID(nil)
    }
}
