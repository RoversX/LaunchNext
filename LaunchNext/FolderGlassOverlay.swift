import AppKit
import QuartzCore

/// Native glass over a layer-rendered grid. Input remains owned by the grid.
/// A bounded group of nearby backplates stays stable during swipes.
/// Preview bitmaps are shared with CA.
@MainActor
final class FolderGlassOverlay: NSView {
    @MainActor
    private final class Entry {
        let source: CALayer
        let icon: CALayer
        let glass = NSGlassEffectView()
        let preview = CALayer()
        let previewHost: NSView?
        var isCreation: Bool { previewHost != nil }

        init(source: CALayer, icon: CALayer) {
            self.source = source
            self.icon = icon
            previewHost = source.name == "creationGlass" ? NSView() : nil
            previewHost?.wantsLayer = true
            glass.style = .clear
            let content = NSView()
            content.wantsLayer = true
            // A creation target stays full-sized while only its backplate grows.
            // Keep its shared bitmap outside the glass content clipping bounds.
            if let previewHost {
                previewHost.layer?.addSublayer(preview)
            } else {
                content.layer?.addSublayer(preview)
            }
            preview.contentsGravity = .resizeAspect
            glass.contentView = content
            source.isHidden = true
            icon.isHidden = true
        }

        func remove() {
            glass.isHidden = true
            source.isHidden = false
            icon.isHidden = false
            glass.removeFromSuperview()
            previewHost?.removeFromSuperview()
        }

        func updatePreviewContents() {
            if (preview.contents as AnyObject?) !== (icon.contents as AnyObject?) {
                preview.contents = icon.contents
            }
            if preview.contentsScale != icon.contentsScale {
                preview.contentsScale = icon.contentsScale
            }
        }
    }

    private let canvas = NSView()
    private let pageCanvas = NSView()
    private let pageEffects = NSGlassEffectContainerView()
    private let dragEffects = NSGlassEffectContainerView()
    private var entries: [ObjectIdentifier: Entry] = [:]
    // At most the active target and one outgoing creation preview.
    private var creationEntries: [Entry] = []
    private var lastContainers: [CALayer] = []
    private weak var lastPage: CALayer?
    private weak var lastRoot: CALayer?
    private var lastViewport: CGRect = .null
    private var lastPageFrame: CGRect = .null
    private var lastBaseX: CGFloat = .nan
    var activeGlassCount: Int { entries.values.filter { !$0.glass.isHidden }.count }

    override init(frame: NSRect) {
        super.init(frame: frame)
        wantsLayer = true
        // Translate the complete material subtree, including AppKit's generated
        // glass and the preview. AppKit owns the view layer's transform and may
        // reset it during initial layout; its sublayerTransform remains ours.
        pageEffects.wantsLayer = true
        pageEffects.spacing = 0
        pageEffects.contentView = pageCanvas
        addSubview(pageEffects)
        dragEffects.wantsLayer = true
        dragEffects.isHidden = true
        dragEffects.spacing = 0
        dragEffects.contentView = canvas
        addSubview(dragEffects)
    }

    required init?(coder: NSCoder) { fatalError("init(coder:) has not been implemented") }

    override func hitTest(_ point: NSPoint) -> NSView? { nil }

    /// Async preview completion must reach glass even while the grid is idle.
    /// Updating this bitmap does not require another page/geometry traversal.
    func updatePreviewContents(for icon: CALayer) {
        guard let entry = entries.values.first(where: { $0.icon === icon }) else { return }
        CATransaction.begin()
        CATransaction.setDisableActions(true)
        entry.updatePreviewContents()
        CATransaction.commit()
    }

    /// End the native drag visual in the same event as its CA source. Hiding
    /// the whole group also suppresses any material transition on child removal.
    func removeDraggingGlass(for container: CALayer) {
        CATransaction.begin()
        CATransaction.setDisableActions(true)
        dragEffects.isHidden = true
        for key in Array(entries.keys) where entries[key]?.source.superlayer === container {
            entries.removeValue(forKey: key)?.remove()
        }
        creationEntries.removeAll { $0.previewHost?.superview == nil }
        lastContainers.removeAll()
        CATransaction.commit()
    }

    /// A model reorder rebuilds page layers while the lifted folder is landing.
    /// Keep that native view alive so its material does not disappear/reappear.
    func resetPageGlass(keeping container: CALayer, alsoKeeping additional: CALayer? = nil) {
        for key in Array(entries.keys) where entries[key]?.source.superlayer !== container
            && (additional == nil || entries[key]?.source.superlayer !== additional) {
            entries.removeValue(forKey: key)?.remove()
        }
        creationEntries.removeAll { $0.previewHost?.superview == nil }
        lastContainers.removeAll()
        lastPage = nil
    }

    func reset() {
        dragEffects.isHidden = true
        for entry in entries.values { entry.remove() }
        entries.removeAll()
        creationEntries.removeAll()
        lastContainers.removeAll()
        lastPage = nil
        lastRoot = nil
        lastViewport = .null
    }

    /// Read presentation geometry only while CA is animating it. The page offset
    /// is supplied separately so a just-applied scroll never lags by one frame.
    func sync(containers: [CALayer], root: CALayer, page: CALayer, viewport: CGRect, geometryChanged: Bool = true) {
        CATransaction.begin()
        CATransaction.setDisableActions(true)
        defer { CATransaction.commit() }
        let pageOrigin = page.convert(CGPoint.zero, to: root)
        // Bound the native effect surface even when the launcher has many pages.
        // Rebase at viewport boundaries, not on every scroll tick.
        let viewportWidth = max(1, viewport.width)
        let baseX = max(0, floor(-pageOrigin.x / viewportWidth) - 1) * viewportWidth
        let pageFrame = CGRect(x: 0, y: 0,
                               width: min(page.bounds.width, viewportWidth * 3 + 32),
                               height: page.bounds.height)
        if pageEffects.frame != pageFrame {
            pageEffects.layer?.sublayerTransform = CATransform3DIdentity
            pageEffects.frame = pageFrame
        }
        let translation = CATransform3DMakeTranslation(pageOrigin.x + baseX, pageOrigin.y, 0)
        if let layer = pageEffects.layer, !CATransform3DEqualToTransform(layer.sublayerTransform, translation) {
            layer.sublayerTransform = translation
        }
        if dragEffects.frame != viewport { dragEffects.frame = viewport }
        // AppKit material can composite over custom content layers. Put the
        // creation icon in a sibling view above the complete material group.
        // Even a pure page translation must carry this single preview along.
        for entry in creationEntries {
            guard let host = entry.previewHost else { continue }
            if host.frame != viewport { host.frame = viewport }
            let previewTranslation = entry.source.superlayer?.superlayer === page
                ? translation : CATransform3DIdentity
            if let layer = host.layer, !CATransform3DEqualToTransform(layer.sublayerTransform, previewTranslation) {
                layer.sublayerTransform = previewTranslation
            }
        }
        // Pure paging only translates the complete native material subtree. Rebuild
        // geometry on layout/animation changes, a new nearby batch, or rebasing.
        let reusePageGeometry = !geometryChanged && lastPage === page && lastRoot === root
            && lastViewport == viewport && lastPageFrame == pageFrame && lastBaseX == baseX
            && lastContainers.count == containers.count
            && zip(lastContainers, containers).allSatisfy { $0 === $1 }
        lastContainers = containers
        lastPage = page
        lastRoot = root
        lastViewport = viewport
        lastPageFrame = pageFrame
        lastBaseX = baseX
        // During a plain drag, the page stays unchanged. Only synchronize the
        // root-attached dragged icon; page animations explicitly invalidate reuse.
        let changedContainers = reusePageGeometry
            ? containers.filter { $0.superlayer !== page } : containers
        if reusePageGeometry && changedContainers.isEmpty { return }
        var retained: Set<ObjectIdentifier> = reusePageGeometry
            ? Set(entries.compactMap { $0.value.source.superlayer?.superlayer === page ? $0.key : nil })
            : []
        for container in changedContainers {
            guard container.opacity > 0, !container.isHidden,
                  let children = container.sublayers,
                  let source = children.first(where: { $0.name == "glass" || $0.name == "creationGlass" }),
                  let icon = children.first(where: { $0.name == "icon" }) else { continue }
            let inPage = container.superlayer === page
            let destination = inPage ? page : root
            let glassRect = Self.rect(source, in: destination).offsetBy(dx: inPage ? -baseX : 0, dy: 0)
            let key = ObjectIdentifier(source)
            retained.insert(key)
            guard glassRect.width > 0, glassRect.height > 0,
                  glassRect.intersects((inPage ? pageFrame : viewport).insetBy(dx: -16, dy: -16)) else {
                // Cull at stable group boundaries instead of hiding/showing each
                // column as it crosses the viewport during a swipe.
                if let entry = entries[key] {
                    if !entry.glass.isHidden { entry.glass.isHidden = true }
                    entry.previewHost?.isHidden = true
                    if source.isHidden { source.isHidden = false }
                    if icon.isHidden { icon.isHidden = false }
                }
                continue
            }
            let entry: Entry
            if let existing = entries[key] {
                entry = existing
            } else {
                entry = Entry(source: source, icon: icon)
                entries[key] = entry
                (inPage ? pageCanvas : canvas).addSubview(entry.glass)
                if let host = entry.previewHost {
                    creationEntries.append(entry)
                    addSubview(host)
                    host.frame = viewport
                    host.layer?.zPosition = 2
                    host.layer?.sublayerTransform = inPage ? translation : CATransform3DIdentity
                }
            }
            if entry.glass.isHidden { entry.glass.isHidden = false }
            entry.previewHost?.isHidden = false
            if !inPage, dragEffects.isHidden { dragEffects.isHidden = false }
            if !source.isHidden { source.isHidden = true }
            if !icon.isHidden { icon.isHidden = true }
            let opacity = CGFloat((container.animationKeys()?.isEmpty == false
                ? container.presentation()?.opacity : nil) ?? container.opacity)
            if entry.glass.alphaValue != opacity { entry.glass.alphaValue = opacity }
            let parent = inPage ? pageCanvas : canvas
            if entry.glass.superview !== parent { parent.addSubview(entry.glass) }
            if entry.glass.frame != glassRect { entry.glass.frame = glassRect }
            let radius = glassRect.width * 0.25
            if entry.glass.cornerRadius != radius { entry.glass.cornerRadius = radius }
            if entry.glass.layer?.zPosition != container.zPosition {
                entry.glass.layer?.zPosition = container.zPosition
            }
            if entry.isCreation {
                entry.preview.opacity = Float(opacity)
            }
            let iconRect = Self.rect(icon, in: destination).offsetBy(
                dx: (inPage ? -baseX : 0) - (entry.isCreation ? 0 : glassRect.minX),
                dy: entry.isCreation ? 0 : -glassRect.minY)
            if entry.preview.frame != iconRect { entry.preview.frame = iconRect }
            entry.updatePreviewContents()
        }
        for key in Array(entries.keys) where !retained.contains(key) {
            entries.removeValue(forKey: key)?.remove()
        }
        creationEntries.removeAll { $0.previewHost?.superview == nil }
    }

    private static func rect(_ source: CALayer, in destination: CALayer) -> CGRect {
        var node: CALayer? = source
        var animating = false
        while let current = node, current !== destination {
            if !(current.animationKeys() ?? []).isEmpty { animating = true; break }
            node = current.superlayer
        }
        if animating, let presented = source.presentation(), let target = destination.presentation() {
            return presented.convert(presented.bounds, to: target)
        }
        return source.convert(source.bounds, to: destination)
    }
}
