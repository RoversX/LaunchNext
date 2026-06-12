import AppKit
import QuartzCore

final class CAFolderGridView: NSView {
    private enum ScrollAxisLock {
        case undecided
        case horizontal
        case vertical
    }

    var apps: [AppInfo] = [] {
        didSet { rebuildLayers() }
    }
    var layoutMode: AppStore.FolderLayoutMode = .paged {
        didSet {
            guard layoutMode != oldValue else { return }
            updateLayerClipping()
            currentPage = min(currentPage, max(pageCount - 1, 0))
            verticalOffset = 0
            horizontalOffset = pageOffset(for: currentPage, metrics: makeMetrics())
            targetHorizontalOffset = horizontalOffset
            updateLayout(animated: false)
        }
    }
    var iconSize: CGFloat = 72 {
        didSet {
            guard iconSize != oldValue else { return }
            clearIconCache()
            rebuildLayers()
        }
    }
    var labelFontSize: CGFloat = 12 {
        didSet {
            guard labelFontSize != oldValue else { return }
            updateLabelFonts()
            updateLayout(animated: false)
        }
    }
    var labelFontWeight: NSFont.Weight = .medium {
        didSet {
            guard labelFontWeight != oldValue else { return }
            updateLabelFonts()
        }
    }
    var showLabels: Bool = true {
        didSet {
            guard showLabels != oldValue else { return }
            updateLabelVisibility()
            updateLayout(animated: false)
        }
    }
    var hoverMagnificationEnabled: Bool = false {
        didSet {
            guard hoverMagnificationEnabled != oldValue else { return }
            if !hoverMagnificationEnabled { updateHoverIndex(nil) }
        }
    }
    var hoverMagnificationScale: CGFloat = 1.2
    var activePressEffectEnabled: Bool = false
    var activePressScale: CGFloat = 0.92
    var animationsEnabled: Bool = true
    var animationDuration: Double = 0.3
    var isLayoutLocked: Bool = false
    var scrollSensitivity: Double = AppStore.defaultScrollSensitivity
    var reverseWheelPagingDirection: Bool = false
    var verticalHeaderHeight: CGFloat = 0 {
        didSet {
            guard verticalHeaderHeight != oldValue else { return }
            updateLayout(animated: false)
        }
    }

    var showInFinderMenuTitle: String = "Show in Finder"
    var copyAppPathMenuTitle: String = "Copy App Path"
    var hideAppMenuTitle: String = "Hide application"
    var uninstallWithToolMenuTitle: String = "Uninstall with configured tool"
    var canUseConfiguredUninstallTool: Bool = false
    var contextMenuTargetApp: AppInfo?

    var onOpenApp: ((AppInfo) -> Void)?
    var onReorderApps: ((Int, Int) -> Void)?
    var onDragAppOut: ((AppInfo) -> Void)?
    var onShowAppInFinder: ((AppInfo) -> Void)?
    var onCopyAppPath: ((AppInfo) -> Void)?
    var onHideApp: ((AppInfo) -> Void)?
    var onUninstallWithTool: ((AppInfo) -> Void)?
    var onClose: (() -> Void)?
    var onPageStateChanged: ((Int, Int) -> Void)?
    var onVerticalScrollOffsetChanged: ((CGFloat) -> Void)?

    private let baseContentInsets = NSEdgeInsets(top: 12, left: 12, bottom: 12, right: 12)
    private var contentInsets: NSEdgeInsets {
        var insets = baseContentInsets
        if layoutMode == .vertical {
            insets.top += verticalHeaderHeight
        }
        return insets
    }
    private let columnSpacing: CGFloat = 22
    private let rowSpacing: CGFloat = 18
    private let dragOutInset: CGFloat = -14
    private let pageFlipEdgeWidth: CGFloat = 60
    private let pageFlipDelay: TimeInterval = 0.4

    private var contentLayer = CALayer()
    private var displayLink: CADisplayLink?
    private var appLayers: [CALayer] = []
    private var itemFrames: [CGRect] = []
    private var iconCache: [String: CGImage] = [:]
    private let iconCacheLock = NSLock()
    private var hoverTrackingArea: NSTrackingArea?
    private var currentPage = 0
    private var horizontalOffset: CGFloat = 0
    private var targetHorizontalOffset: CGFloat = 0
    private var verticalOffset: CGFloat = 0
    private var pageCount: Int {
        let metrics = makeMetrics()
        return max(1, (apps.count + metrics.itemsPerPage - 1) / metrics.itemsPerPage)
    }
    private var selectedIndex: Int?
    private var hoveredIndex: Int?
    private var pressedIndex: Int?
    private var dragStartPoint: CGPoint = .zero
    private var draggingIndex: Int?
    private var draggingApp: AppInfo?
    private var draggingLayer: CALayer?
    private var isDraggingItem = false
    private var dragCurrentPoint: CGPoint = .zero
    private var edgeDragTimer: Timer?
    private var edgeDragDirection: Int?
    private var edgeDragRequiresReentry = false
    private var pendingDragUpdateAfterPageAnimation = false
    private var isPageScrollDragging = false
    private var isPageScrollAnimating = false
    private var pageScrollStartOffset: CGFloat = 0
    private var pageScrollAccumulatedDelta: CGFloat = 0
    private var pageScrollSnapWorkItem: DispatchWorkItem?
    private var wheelAccumulatedDelta: CGFloat = 0
    private var wheelLastDirection = 0
    private var wheelLastFlipAt: Date?
    private let wheelFlipCooldown: TimeInterval = 0.15
    private var automaticScrollAxis: ScrollAxisLock = .undecided
    private var automaticScrollAccumulatedX: CGFloat = 0
    private var automaticScrollAccumulatedY: CGFloat = 0
    private let automaticScrollAxisThreshold: CGFloat = 10
    private let automaticScrollAxisDominance: CGFloat = 1.4
    private var currentHoverIndex: Int?
    private var lastReportedPage: Int?
    private var lastReportedPageCount: Int?
    private var lastReportedVerticalOffset: CGFloat?

    var displayedPage: Int { currentPage }
    var displayedPageCount: Int { pageCount }

    func setDisplayedPage(_ page: Int, animated: Bool) {
        navigateToPage(page, animated: animated)
    }

    override init(frame frameRect: NSRect) {
        super.init(frame: frameRect)
        setup()
    }

    required init?(coder: NSCoder) {
        super.init(coder: coder)
        setup()
    }

    deinit {
        if let tracking = hoverTrackingArea {
            removeTrackingArea(tracking)
        }
        displayLink?.invalidate()
        edgeDragTimer?.invalidate()
        pageScrollSnapWorkItem?.cancel()
    }

    private func setup() {
        wantsLayer = true
        updateLayerClipping()
        contentLayer.masksToBounds = false
        layer?.addSublayer(contentLayer)
    }

    private func updateLayerClipping() {
        layer?.masksToBounds = false
    }

    override var acceptsFirstResponder: Bool { true }

    override func acceptsFirstMouse(for event: NSEvent?) -> Bool { true }

    override func layout() {
        super.layout()
        if layoutMode == .paged, !isPageScrollDragging, !isPageScrollAnimating, !isDraggingItem {
            let metrics = makeMetrics()
            horizontalOffset = pageOffset(for: currentPage, metrics: metrics)
            targetHorizontalOffset = horizontalOffset
        }
        updateLayout(animated: false)
    }

    override func updateTrackingAreas() {
        super.updateTrackingAreas()
        if let tracking = hoverTrackingArea {
            removeTrackingArea(tracking)
        }
        let options: NSTrackingArea.Options = [.mouseMoved, .mouseEnteredAndExited, .activeInKeyWindow, .inVisibleRect]
        let tracking = NSTrackingArea(rect: bounds, options: options, owner: self, userInfo: nil)
        addTrackingArea(tracking)
        hoverTrackingArea = tracking
    }

    override func viewDidMoveToWindow() {
        super.viewDidMoveToWindow()
        window?.acceptsMouseMovedEvents = true
        if window != nil {
            setupDisplayLinkIfNeeded()
        } else {
            displayLink?.invalidate()
            displayLink = nil
        }
        DispatchQueue.main.async { [weak self] in
            guard let self, let window = self.window else { return }
            window.makeFirstResponder(self)
        }
    }

    private func setupDisplayLinkIfNeeded() {
        guard displayLink == nil, let window else { return }
        displayLink = window.displayLink(target: self, selector: #selector(displayLinkFired(_:)))
        displayLink?.preferredFrameRateRange = CAFrameRateRange(minimum: 60, maximum: 120, preferred: 120)
        displayLink?.add(to: .main, forMode: .common)
    }

    @objc private func displayLinkFired(_ link: CADisplayLink) {
        guard isPageScrollAnimating else { return }
        updatePageScrollAnimation()
    }

    func updateSelection(_ index: Int?, animated: Bool = true) {
        let clamped = index.flatMap { apps.indices.contains($0) ? $0 : nil }
        guard selectedIndex != clamped else { return }
        let old = selectedIndex
        selectedIndex = clamped
        if let old { applyScale(at: old, animated: animated) }
        if let clamped { applyScale(at: clamped, animated: animated) }
        ensureSelectionVisible()
    }

    func clearIconCache() {
        iconCacheLock.lock()
        iconCache.removeAll()
        iconCacheLock.unlock()
    }

    private struct Metrics {
        var columns: Int
        var rows: Int
        var itemsPerPage: Int
        var cellWidth: CGFloat
        var cellHeight: CGFloat
        var contentHeight: CGFloat
        var totalItemHeight: CGFloat
        var labelHeight: CGFloat
        var labelTopSpacing: CGFloat
        var pageStride: CGFloat
    }

    private func makeMetrics() -> Metrics {
        let width = max(bounds.width, 1)
        let height = max(bounds.height, 1)
        let availableWidth = max(1, width - contentInsets.left - contentInsets.right)
        let availableHeight = max(1, height - contentInsets.top - contentInsets.bottom)
        let labelHeight: CGFloat = showLabels ? labelFontSize + 8 : 0
        let labelTopSpacing: CGFloat = showLabels ? 6 : 0
        let totalItemHeight = iconSize + labelTopSpacing + labelHeight
        let minCellWidth = max(iconSize + 18, iconSize * 1.32)
        let minCellHeight = max(totalItemHeight + 12, iconSize * 1.28)
        let columns = max(1, min(8, Int((availableWidth + columnSpacing) / (minCellWidth + columnSpacing))))
        let usableWidth = max(1, availableWidth - CGFloat(columns - 1) * columnSpacing)
        let cellWidth = usableWidth / CGFloat(columns)

        if layoutMode == .paged {
            let rows = max(1, min(5, Int((availableHeight + rowSpacing) / (minCellHeight + rowSpacing))))
            let usableHeight = max(1, availableHeight - CGFloat(rows - 1) * rowSpacing)
            let cellHeight = usableHeight / CGFloat(rows)
            return Metrics(columns: columns,
                           rows: rows,
                           itemsPerPage: max(1, columns * rows),
                           cellWidth: cellWidth,
                           cellHeight: cellHeight,
                           contentHeight: height,
                           totalItemHeight: totalItemHeight,
                           labelHeight: labelHeight,
                           labelTopSpacing: labelTopSpacing,
                           pageStride: width)
        }

        let rows = max(1, Int(ceil(Double(apps.count) / Double(max(columns, 1)))))
        let cellHeight = minCellHeight
        let contentHeight = contentInsets.top + contentInsets.bottom + CGFloat(rows) * cellHeight + CGFloat(max(rows - 1, 0)) * rowSpacing
        return Metrics(columns: columns,
                       rows: rows,
                       itemsPerPage: max(1, columns * max(rows, 1)),
                       cellWidth: cellWidth,
                       cellHeight: cellHeight,
                       contentHeight: max(height, contentHeight),
                       totalItemHeight: totalItemHeight,
                       labelHeight: labelHeight,
                       labelTopSpacing: labelTopSpacing,
                       pageStride: width)
    }

    private func rebuildLayers() {
        appLayers.forEach { $0.removeFromSuperlayer() }
        appLayers = apps.map { makeAppLayer(for: $0) }
        appLayers.forEach { contentLayer.addSublayer($0) }
        if selectedIndex.map({ !apps.indices.contains($0) }) ?? false {
            selectedIndex = apps.indices.first
        }
        updateLayout(animated: false)
    }

    private func makeAppLayer(for app: AppInfo) -> CALayer {
        let container = CALayer()
        container.masksToBounds = false
        container.contentsScale = backingScale

        let iconLayer = CALayer()
        iconLayer.name = "icon"
        iconLayer.contentsGravity = .resizeAspect
        iconLayer.contentsScale = backingScale
        iconLayer.masksToBounds = false
        iconLayer.shouldRasterize = true
        iconLayer.rasterizationScale = backingScale
        container.addSublayer(iconLayer)

        let textLayer = CATextLayer()
        textLayer.name = "label"
        textLayer.contentsScale = backingScale
        textLayer.alignmentMode = .center
        textLayer.truncationMode = .end
        textLayer.isWrapped = false
        textLayer.fontSize = labelFontSize
        textLayer.font = NSFont.systemFont(ofSize: labelFontSize, weight: labelFontWeight)
        textLayer.foregroundColor = currentLabelColor().cgColor
        textLayer.string = app.name
        textLayer.shouldRasterize = true
        textLayer.rasterizationScale = backingScale
        textLayer.isHidden = !showLabels
        container.addSublayer(textLayer)

        let warningLayer = CATextLayer()
        warningLayer.name = "missingWarning"
        warningLayer.contentsScale = backingScale
        warningLayer.alignmentMode = .center
        warningLayer.fontSize = max(10, iconSize * 0.13)
        warningLayer.font = NSFont.systemFont(ofSize: max(10, iconSize * 0.13), weight: .bold)
        warningLayer.foregroundColor = NSColor.white.cgColor
        warningLayer.backgroundColor = NSColor.systemOrange.cgColor
        warningLayer.cornerRadius = max(7, iconSize * 0.11)
        warningLayer.masksToBounds = true
        warningLayer.string = "!"
        warningLayer.isHidden = FileManager.default.fileExists(atPath: app.url.path)
        container.addSublayer(warningLayer)

        setIcon(for: iconLayer, app: app)
        return container
    }

    private var backingScale: CGFloat {
        window?.backingScaleFactor ?? NSScreen.main?.backingScaleFactor ?? 2
    }

    private func updateLayout(animated: Bool) {
        guard bounds.width > 0, bounds.height > 0 else { return }
        let metrics = makeMetrics()
        currentPage = min(currentPage, max(pageCount - 1, 0))
        if layoutMode == .paged {
            targetHorizontalOffset = clampHorizontalOffset(pageOffset(for: currentPage, metrics: metrics), metrics: metrics)
            horizontalOffset = clampHorizontalOffset(horizontalOffset, metrics: metrics)
            if !isPageScrollDragging, !isPageScrollAnimating, !isDraggingItem {
                horizontalOffset = targetHorizontalOffset
            }
            verticalOffset = 0
        } else {
            horizontalOffset = 0
            targetHorizontalOffset = 0
            verticalOffset = clampVerticalOffset(verticalOffset, metrics: metrics)
        }

        CATransaction.begin()
        CATransaction.setDisableActions(true)
        CATransaction.setAnimationDuration(0)
        CATransaction.setAnimationTimingFunction(CAMediaTimingFunction(name: .easeOut))

        if layoutMode == .paged {
            let totalWidth = CGFloat(max(pageCount, 1)) * metrics.pageStride
            // Keep frame updates out of a transformed coordinate space; otherwise CA can leave the page container a few percent off.
            contentLayer.transform = CATransform3DIdentity
            contentLayer.frame = CGRect(x: 0, y: 0, width: totalWidth, height: bounds.height)
            contentLayer.transform = CATransform3DMakeTranslation(horizontalOffset, 0, 0)
        } else {
            contentLayer.transform = CATransform3DIdentity
            contentLayer.frame = bounds
        }

        itemFrames = Array(repeating: .zero, count: apps.count)
        for (index, layer) in appLayers.enumerated() {
            guard index < apps.count else { continue }
            let frame = frameForItem(at: index, metrics: metrics)
            itemFrames[index] = visibleFrame(frame)
            layer.transform = CATransform3DIdentity
            layer.frame = frame
            layoutSublayers(of: layer, metrics: metrics)
            layer.opacity = draggingIndex == index ? 0 : 1
        }
        CATransaction.commit()
        notifyPageStateChanged()
        notifyVerticalScrollOffsetChanged()
    }

    private func frameForItem(at index: Int, metrics: Metrics) -> CGRect {
        frameForGridSlot(at: index, metrics: metrics)
    }

    private func frameForGridSlot(at index: Int, metrics: Metrics) -> CGRect {
        let pageIndex: Int
        let localIndex: Int
        let xOffset: CGFloat
        if layoutMode == .paged {
            pageIndex = index / metrics.itemsPerPage
            localIndex = index % metrics.itemsPerPage
            xOffset = CGFloat(pageIndex) * metrics.pageStride
        } else {
            pageIndex = 0
            localIndex = index
            xOffset = 0
        }
        _ = pageIndex
        let col = localIndex % metrics.columns
        let row = localIndex / metrics.columns
        let x = contentInsets.left + xOffset + CGFloat(col) * (metrics.cellWidth + columnSpacing)
        let topBasedY = bounds.height - contentInsets.top - CGFloat(row + 1) * metrics.cellHeight - CGFloat(row) * rowSpacing
        let y = topBasedY + (metrics.cellHeight - metrics.totalItemHeight) / 2 - (layoutMode == .vertical ? verticalOffset : 0)
        return CGRect(x: x, y: y, width: metrics.cellWidth, height: metrics.totalItemHeight)
    }

    private func visibleFrame(_ frame: CGRect) -> CGRect {
        layoutMode == .paged ? frame.offsetBy(dx: horizontalOffset, dy: 0) : frame
    }

    private func pageOffset(for page: Int, metrics: Metrics) -> CGFloat {
        -CGFloat(page) * metrics.pageStride
    }

    private func clampHorizontalOffset(_ value: CGFloat, metrics: Metrics) -> CGFloat {
        let minOffset = -CGFloat(max(pageCount - 1, 0)) * metrics.pageStride
        return min(0, max(minOffset, value))
    }

    private func layoutSublayers(of layer: CALayer, metrics: Metrics) {
        layer.transform = CATransform3DIdentity
        let iconX = (metrics.cellWidth - iconSize) / 2
        let iconY = metrics.labelHeight + metrics.labelTopSpacing
        let iconFrame = CGRect(x: iconX, y: iconY, width: iconSize, height: iconSize)
        if let iconLayer = layer.sublayers?.first(where: { $0.name == "icon" }) {
            iconLayer.transform = CATransform3DIdentity
            iconLayer.frame = iconFrame
        }
        if let textLayer = layer.sublayers?.first(where: { $0.name == "label" }) as? CATextLayer {
            textLayer.isHidden = !showLabels
            textLayer.frame = CGRect(x: 4, y: 0, width: metrics.cellWidth - 8, height: metrics.labelHeight)
        }
        if let warningLayer = layer.sublayers?.first(where: { $0.name == "missingWarning" }) as? CATextLayer {
            let side = max(14, iconSize * 0.22)
            warningLayer.frame = CGRect(x: iconFrame.maxX - side - iconSize * 0.05,
                                        y: iconFrame.maxY - side - iconSize * 0.05,
                                        width: side,
                                        height: side)
            warningLayer.cornerRadius = side / 2
        }
        if let index = appLayers.firstIndex(of: layer) {
            applyScale(at: index, animated: false)
        }
    }

    private func setIcon(for layer: CALayer, app: AppInfo) {
        let path = app.url.path
        let scale = backingScale
        let side = iconSize
        let expectedKey = iconCacheKey(for: path, scale: scale)
        layer.setValue(expectedKey, forKey: "iconCacheKey")
        if let cached = cachedIcon(for: path) {
            layer.contents = cached
            return
        }
        layer.contents = nil
        DispatchQueue.global(qos: .userInitiated).async { [weak self, weak layer] in
            guard let self, let layer else { return }
            guard layer.value(forKey: "iconCacheKey") as? String == expectedKey else { return }
            let icon: NSImage
            if FileManager.default.fileExists(atPath: path) {
                icon = IconStore.shared.icon(forPath: path)
            } else {
                icon = MissingAppPlaceholder.defaultIcon
            }
            guard let cgImage = self.renderIcon(icon, key: expectedKey, side: side, scale: scale) else { return }
            DispatchQueue.main.async {
                guard layer.value(forKey: "iconCacheKey") as? String == expectedKey else { return }
                CATransaction.begin()
                CATransaction.setDisableActions(true)
                layer.contents = cgImage
                CATransaction.commit()
            }
        }
    }

    private func cachedIcon(for path: String) -> CGImage? {
        let key = iconCacheKey(for: path, scale: backingScale)
        iconCacheLock.lock()
        defer { iconCacheLock.unlock() }
        return iconCache[key]
    }

    private func iconCacheKey(for path: String, scale: CGFloat) -> String {
        "\(path)#\(Int(iconSize.rounded()))#\(Int((scale * 100).rounded()))"
    }

    private func renderIcon(_ icon: NSImage, key: String, side: CGFloat, scale: CGFloat) -> CGImage? {
        iconCacheLock.lock()
        if let cached = iconCache[key] {
            iconCacheLock.unlock()
            return cached
        }
        iconCacheLock.unlock()

        let pixelSide = max(16, Int((side * scale).rounded()))
        let image = NSImage(size: NSSize(width: pixelSide, height: pixelSide))
        image.lockFocus()
        NSGraphicsContext.current?.imageInterpolation = .high
        icon.draw(in: NSRect(x: 0, y: 0, width: pixelSide, height: pixelSide))
        image.unlockFocus()
        guard let cgImage = image.cgImage(forProposedRect: nil, context: nil, hints: nil) else { return nil }

        iconCacheLock.lock()
        iconCache[key] = cgImage
        iconCacheLock.unlock()
        return cgImage
    }

    private func updateLabelFonts() {
        for layer in appLayers {
            if let text = layer.sublayers?.first(where: { $0.name == "label" }) as? CATextLayer {
                text.fontSize = labelFontSize
                text.font = NSFont.systemFont(ofSize: labelFontSize, weight: labelFontWeight)
            }
        }
    }

    private func updateLabelVisibility() {
        for layer in appLayers {
            if let text = layer.sublayers?.first(where: { $0.name == "label" }) as? CATextLayer {
                text.isHidden = !showLabels
            }
        }
    }

    private func updateLabelColors() {
        let resolvedColor = currentLabelColor().cgColor
        CATransaction.begin()
        CATransaction.setDisableActions(true)
        for layer in appLayers {
            if let text = layer.sublayers?.first(where: { $0.name == "label" }) as? CATextLayer {
                text.foregroundColor = resolvedColor
            }
        }
        CATransaction.commit()
    }

    private func currentLabelColor() -> NSColor {
        let match = effectiveAppearance.bestMatch(from: [.darkAqua, .aqua])
        return match == .darkAqua ? .white : .black
    }

    override func viewDidChangeEffectiveAppearance() {
        super.viewDidChangeEffectiveAppearance()
        updateLabelColors()
    }

    override func mouseMoved(with event: NSEvent) {
        guard hoverMagnificationEnabled, !isDraggingItem else {
            updateHoverIndex(nil)
            return
        }
        let point = convert(event.locationInWindow, from: nil)
        updateHoverIndex(itemIndex(at: point))
    }

    override func mouseExited(with event: NSEvent) {
        updateHoverIndex(nil)
    }

    override func mouseDown(with event: NSEvent) {
        window?.makeFirstResponder(self)
        let point = convert(event.locationInWindow, from: nil)
        guard let index = itemIndex(at: point) else { return }
        pressedIndex = index
        dragStartPoint = point
        applyScale(at: index, animated: true)
    }

    override func mouseDragged(with event: NSEvent) {
        let point = convert(event.locationInWindow, from: nil)
        if !isDraggingItem, let pressedIndex {
            guard !isLayoutLocked else { return }
            let distance = hypot(point.x - dragStartPoint.x, point.y - dragStartPoint.y)
            if distance > 10, apps.indices.contains(pressedIndex) {
                startDragging(at: pressedIndex, point: point)
            }
        }
        if isDraggingItem {
            updateDragging(at: point)
        }
    }

    override func mouseUp(with event: NSEvent) {
        let point = convert(event.locationInWindow, from: nil)
        if isDraggingItem {
            finishDragging(at: point)
            return
        }
        if let index = pressedIndex {
            pressedIndex = nil
            applyScale(at: index, animated: true)
            if itemIndex(at: point) == index, apps.indices.contains(index) {
                let app = apps[index]
                if FileManager.default.fileExists(atPath: app.url.path) {
                    onOpenApp?(app)
                } else {
                    NSSound.beep()
                }
            }
        }
    }

    override func scrollWheel(with event: NSEvent) {
        if layoutMode == .paged {
            handlePagedScroll(event)
        } else {
            handleVerticalScroll(event)
        }
    }

    override func keyDown(with event: NSEvent) {
        if event.keyCode == 53 {
            onClose?()
            return
        }
        guard !apps.isEmpty else {
            super.keyDown(with: event)
            return
        }
        if selectedIndex == nil { updateSelection(0, animated: true) }
        guard let selectedIndex else { return }

        switch event.keyCode {
        case 36:
            let app = apps[selectedIndex]
            if FileManager.default.fileExists(atPath: app.url.path) {
                onOpenApp?(app)
            } else {
                NSSound.beep()
            }
        case 123:
            updateSelection(max(0, selectedIndex - 1), animated: true)
        case 124:
            updateSelection(min(apps.count - 1, selectedIndex + 1), animated: true)
        case 125:
            updateSelection(min(apps.count - 1, selectedIndex + makeMetrics().columns), animated: true)
        case 126:
            updateSelection(max(0, selectedIndex - makeMetrics().columns), animated: true)
        default:
            super.keyDown(with: event)
        }
    }

    private func handlePagedScroll(_ event: NSEvent) {
        let axes = resolvedPagedAxes(for: event)
        let deltaX = axes.x
        let deltaY = axes.y
        let isContinuousGesture = isContinuousScrollGesture(event)
        if event.phase.contains(.began) {
            resetAutomaticScrollAxis()
        }

        guard let dominant = scaledPageDelta(deltaX: deltaX,
                                            deltaY: deltaY,
                                            isContinuousGesture: isContinuousGesture) else {
            if event.phase.contains(.ended) || event.phase.contains(.cancelled) {
                resetAutomaticScrollAxis()
            }
            return
        }

        if !isContinuousGesture {
            if dominant != 0 {
                handleWheelPaging(with: dominant)
            }
            return
        }

        let phase = event.phase
        let momentumPhase = event.momentumPhase
        let phaseLessScroll = phase.isEmpty && momentumPhase.isEmpty
        let ended = phase.contains(.ended)
            || phase.contains(.cancelled)
            || momentumPhase.contains(.ended)
            || momentumPhase.contains(.cancelled)

        if phase.contains(.began) {
            beginPageScroll()
        }

        if (phase.contains(.changed) || phaseLessScroll), dominant != 0 {
            if !isPageScrollDragging {
                beginPageScroll()
            }

            updatePageScroll(by: dominant)

            if phaseLessScroll {
                schedulePageScrollSnap(velocity: dominant)
            }
        }

        if ended {
            finishPageScroll(velocity: dominant)
            resetAutomaticScrollAxis()
        }
    }

    private func schedulePageScrollSnap(velocity: CGFloat) {
        pageScrollSnapWorkItem?.cancel()
        let workItem = DispatchWorkItem { [weak self] in
            self?.finishPageScroll(velocity: velocity)
        }
        pageScrollSnapWorkItem = workItem
        DispatchQueue.main.asyncAfter(deadline: .now() + 0.12, execute: workItem)
    }

    private func resetAutomaticScrollAxis() {
        automaticScrollAxis = .undecided
        automaticScrollAccumulatedX = 0
        automaticScrollAccumulatedY = 0
    }

    private func lockedAutomaticPagedDelta(deltaX: CGFloat, deltaY: CGFloat, isContinuousGesture: Bool) -> CGFloat? {
        guard isContinuousGesture else {
            return -deltaY
        }

        automaticScrollAccumulatedX += deltaX
        automaticScrollAccumulatedY += deltaY

        if automaticScrollAxis == .undecided {
            let x = abs(automaticScrollAccumulatedX)
            let y = abs(automaticScrollAccumulatedY)
            if x >= automaticScrollAxisThreshold,
               x >= y * automaticScrollAxisDominance {
                automaticScrollAxis = .horizontal
                let initialDelta = automaticScrollAccumulatedX
                automaticScrollAccumulatedX = 0
                automaticScrollAccumulatedY = 0
                return initialDelta
            } else if y >= automaticScrollAxisThreshold * 2,
                      y >= x * (automaticScrollAxisDominance + 0.5) {
                automaticScrollAxis = .vertical
            } else {
                return nil
            }
        }

        switch automaticScrollAxis {
        case .horizontal:
            return deltaX
        case .vertical:
            return nil
        case .undecided:
            return nil
        }
    }

    private func isContinuousScrollGesture(_ event: NSEvent) -> Bool {
        !event.phase.isEmpty || !event.momentumPhase.isEmpty
    }

    private func resolvedPagedAxes(for event: NSEvent) -> (x: CGFloat, y: CGFloat) {
        if isContinuousScrollGesture(event) {
            return (event.scrollingDeltaX, event.scrollingDeltaY)
        }

        let deltaX = event.deltaX != 0 ? event.deltaX : event.scrollingDeltaX
        let deltaY = event.deltaY != 0 ? event.deltaY : event.scrollingDeltaY
        return (deltaX, deltaY)
    }

    private func scaledPageDelta(deltaX: CGFloat, deltaY: CGFloat, isContinuousGesture: Bool) -> CGFloat? {
        guard let rawDelta = lockedAutomaticPagedDelta(deltaX: deltaX,
                                                       deltaY: deltaY,
                                                       isContinuousGesture: isContinuousGesture) else { return nil }
        let baseline = max(AppStore.defaultScrollSensitivity, 0.0001)
        let sensitivityScale = CGFloat(max(scrollSensitivity, 0.0001) / baseline)
        return rawDelta * sensitivityScale
    }

    private func handleWheelPaging(with scaledDelta: CGFloat) {
        let direction = scaledDelta > 0 ? 1 : -1
        let effectiveDirection = reverseWheelPagingDirection ? -direction : direction
        if wheelLastDirection != direction {
            wheelAccumulatedDelta = 0
        }
        wheelLastDirection = direction
        wheelAccumulatedDelta += abs(scaledDelta)

        let threshold: CGFloat = 2.0
        guard wheelAccumulatedDelta >= threshold else { return }

        let now = Date()
        if let last = wheelLastFlipAt, now.timeIntervalSince(last) < wheelFlipCooldown {
            return
        }

        let targetPage = effectiveDirection > 0 ? currentPage - 1 : currentPage + 1
        wheelLastFlipAt = now
        wheelAccumulatedDelta = 0
        if targetPage < 0 || targetPage >= pageCount {
            animatePageBoundaryNudge(toward: targetPage)
            return
        }
        navigateToPage(targetPage, animated: true)
    }

    private func beginPageScroll() {
        pageScrollSnapWorkItem?.cancel()
        isPageScrollAnimating = false
        isPageScrollDragging = true
        pageScrollStartOffset = horizontalOffset
        pageScrollAccumulatedDelta = 0
    }

    private func updatePageScroll(by delta: CGFloat) {
        isPageScrollAnimating = false
        pageScrollAccumulatedDelta += delta
        let metrics = makeMetrics()
        let minOffset = pageOffset(for: max(pageCount - 1, 0), metrics: metrics)
        let maxOffset: CGFloat = 0
        var newOffset = pageScrollStartOffset + pageScrollAccumulatedDelta

        if newOffset > maxOffset {
            newOffset = maxOffset + rubberBand(newOffset - maxOffset, limit: bounds.width * 0.2)
        } else if newOffset < minOffset {
            newOffset = minOffset + rubberBand(newOffset - minOffset, limit: bounds.width * 0.2)
        }

        horizontalOffset = newOffset
        applyHorizontalOffset()
    }

    private func finishPageScroll(velocity: CGFloat) {
        pageScrollSnapWorkItem?.cancel()
        guard isPageScrollDragging else {
            if !isPageScrollAnimating {
                snapToNearestPage(animated: true)
            }
            return
        }
        isPageScrollDragging = false

        let metrics = makeMetrics()
        let pageStride = max(metrics.pageStride, 1)
        let threshold = pageStride * 0.15
        let velocityThreshold: CGFloat = 30
        var targetPage = Int(round(-horizontalOffset / pageStride))

        if pageScrollAccumulatedDelta < -threshold || velocity < -velocityThreshold {
            targetPage = max(targetPage, currentPage + 1)
        } else if pageScrollAccumulatedDelta > threshold || velocity > velocityThreshold {
            targetPage = min(targetPage, currentPage - 1)
        } else {
            targetPage = currentPage
        }

        pageScrollAccumulatedDelta = 0
        navigateToPage(targetPage, animated: true)
    }

    private func snapToNearestPage(animated: Bool) {
        let metrics = makeMetrics()
        let pageStride = max(metrics.pageStride, 1)
        let nearestPage = Int(round(-horizontalOffset / pageStride))
        navigateToPage(nearestPage, animated: animated)
    }

    private func handleVerticalScroll(_ event: NSEvent) {
        let metrics = makeMetrics()
        let raw = resolvedPagedAxes(for: event).y
        let baseline = max(AppStore.defaultScrollSensitivity, 0.0001)
        let sensitivityScale = CGFloat(max(scrollSensitivity, 0.0001) / baseline)
        var delta = (isContinuousScrollGesture(event) ? raw : -raw) * sensitivityScale
        if reverseWheelPagingDirection {
            delta = -delta
        }
        verticalOffset = clampVerticalOffset(verticalOffset - delta, metrics: metrics)
        updateLayout(animated: false)
    }

    private func navigateToPage(_ page: Int, animated: Bool) {
        let target = min(max(0, page), max(pageCount - 1, 0))
        let metrics = makeMetrics()
        let resolvedOffset = clampHorizontalOffset(pageOffset(for: target, metrics: metrics), metrics: metrics)
        if animated, page != target, layoutMode == .paged, abs(horizontalOffset - resolvedOffset) <= 0.5 {
            animatePageBoundaryNudge(toward: page)
            return
        }
        currentPage = target
        targetHorizontalOffset = resolvedOffset
        wheelAccumulatedDelta = 0
        wheelLastDirection = 0
        resetAutomaticScrollAxis()
        let needsAnimation = animated && animationsEnabled && abs(horizontalOffset - targetHorizontalOffset) > 0.5
        if needsAnimation {
            setupDisplayLinkIfNeeded()
            isPageScrollAnimating = true
        } else {
            isPageScrollAnimating = false
            horizontalOffset = targetHorizontalOffset
        }
        applyHorizontalOffset()
        notifyPageStateChanged()
    }

    private func animatePageBoundaryNudge(toward requestedPage: Int) {
        guard layoutMode == .paged, pageCount > 0, !isPageScrollDragging else { return }
        let metrics = makeMetrics()
        let page = min(max(0, currentPage), max(pageCount - 1, 0))
        let baseOffset = clampHorizontalOffset(pageOffset(for: page, metrics: metrics), metrics: metrics)
        let direction: CGFloat = requestedPage < 0 ? 1 : -1
        let rawNudge = min(max(bounds.width * 0.08, 18), 44)
        horizontalOffset = baseOffset + direction * rawNudge
        targetHorizontalOffset = baseOffset
        currentPage = page
        isPageScrollAnimating = animationsEnabled

        if animationsEnabled {
            setupDisplayLinkIfNeeded()
        } else {
            horizontalOffset = targetHorizontalOffset
            isPageScrollAnimating = false
        }

        applyHorizontalOffset()
        notifyPageStateChanged()
    }

    private func notifyPageStateChanged() {
        guard bounds.width > 0, bounds.height > 0 else { return }
        let count = pageCount
        let page = min(max(0, currentPage), max(count - 1, 0))
        guard lastReportedPage != page || lastReportedPageCount != count else { return }
        lastReportedPage = page
        lastReportedPageCount = count
        onPageStateChanged?(page, count)
    }

    private func notifyVerticalScrollOffsetChanged() {
        let offset = layoutMode == .vertical ? max(0, -verticalOffset) : 0
        guard lastReportedVerticalOffset.map({ abs($0 - offset) > 0.5 }) ?? true else { return }
        lastReportedVerticalOffset = offset
        onVerticalScrollOffsetChanged?(offset)
    }

    private func updatePageScrollAnimation() {
        let metrics = makeMetrics()
        targetHorizontalOffset = clampHorizontalOffset(pageOffset(for: currentPage, metrics: metrics), metrics: metrics)
        if !animationsEnabled {
            horizontalOffset = targetHorizontalOffset
            isPageScrollAnimating = false
        } else {
            let diff = targetHorizontalOffset - horizontalOffset
            if abs(diff) > 0.5 {
                horizontalOffset += diff * 0.18
            } else {
                horizontalOffset = targetHorizontalOffset
                isPageScrollAnimating = false
            }
        }
        applyHorizontalOffset()

        if !isPageScrollAnimating, pendingDragUpdateAfterPageAnimation {
            pendingDragUpdateAfterPageAnimation = false
            if isDraggingItem {
                DispatchQueue.main.async { [weak self] in
                    guard let self, self.isDraggingItem else { return }
                    self.updateDragging(at: self.dragCurrentPoint)
                }
            }
        }
    }

    private func applyHorizontalOffset() {
        CATransaction.begin()
        CATransaction.setDisableActions(true)
        CATransaction.setAnimationDuration(0)
        contentLayer.transform = layoutMode == .paged ? CATransform3DMakeTranslation(horizontalOffset, 0, 0) : CATransform3DIdentity
        CATransaction.commit()
        updateVisibleItemFrames()
    }

    private func updateVisibleItemFrames() {
        guard layoutMode == .paged else { return }
        for (index, layer) in appLayers.enumerated() where itemFrames.indices.contains(index) {
            itemFrames[index] = visibleFrame(layer.frame)
        }
    }

    private func clampVerticalOffset(_ value: CGFloat, metrics: Metrics) -> CGFloat {
        let minOffset = min(0, bounds.height - metrics.contentHeight)
        return min(0, max(minOffset, value))
    }

    private func rubberBand(_ offset: CGFloat, limit: CGFloat) -> CGFloat {
        let factor: CGFloat = 0.5
        let absOffset = abs(offset)
        let scaled = (factor * absOffset * limit) / (absOffset + limit)
        return offset >= 0 ? scaled : -scaled
    }

    private func itemIndex(at point: CGPoint) -> Int? {
        for (index, frame) in itemFrames.enumerated() where frame.contains(point) {
            return index
        }
        return nil
    }

    func contextMenuItemIndex(at point: CGPoint) -> Int? {
        itemIndex(at: point)
    }

    private func gridIndex(at point: CGPoint) -> Int? {
        guard bounds.width > 0, bounds.height > 0 else { return nil }
        let metrics = makeMetrics()
        if layoutMode == .paged {
            guard !isPageScrollAnimating else { return nil }
            let page = min(max(0, currentPage), max(pageCount - 1, 0))
            let localX = point.x - contentInsets.left
            let localY = bounds.height - point.y - contentInsets.top
            guard localX >= 0, localY >= 0 else { return nil }
            let col = Int(localX / (metrics.cellWidth + columnSpacing))
            let row = Int(localY / (metrics.cellHeight + rowSpacing))
            guard col >= 0, col < metrics.columns, row >= 0, row < metrics.rows else { return nil }
            return min(apps.count, page * metrics.itemsPerPage + row * metrics.columns + col)
        }

        let localX = point.x - contentInsets.left
        let localY = bounds.height - point.y - verticalOffset - contentInsets.top
        guard localX >= 0, localY >= 0 else { return nil }
        let col = Int(localX / (metrics.cellWidth + columnSpacing))
        let row = Int(localY / (metrics.cellHeight + rowSpacing))
        guard col >= 0, col < metrics.columns, row >= 0 else { return nil }
        return min(apps.count, row * metrics.columns + col)
    }

    private func startDragging(at index: Int, point: CGPoint) {
        guard apps.indices.contains(index) else { return }
        isDraggingItem = true
        draggingIndex = index
        draggingApp = apps[index]
        currentHoverIndex = nil
        pressedIndex = nil
        appLayers[index].opacity = 0
        draggingLayer = makeDraggingLayer(for: apps[index], at: point)
        if let draggingLayer { layer?.addSublayer(draggingLayer) }
    }

    private func makeDraggingLayer(for app: AppInfo, at point: CGPoint) -> CALayer {
        let container = CALayer()
        container.frame = CGRect(x: point.x - iconSize / 2, y: point.y - iconSize / 2, width: iconSize, height: iconSize)
        container.transform = CATransform3DMakeScale(1.08, 1.08, 1)
        container.shadowColor = NSColor.black.cgColor
        container.shadowOpacity = 0.18
        container.shadowRadius = 10
        container.shadowOffset = CGSize(width: 0, height: -3)
        let iconLayer = CALayer()
        iconLayer.contentsGravity = .resizeAspect
        iconLayer.contentsScale = backingScale
        iconLayer.frame = container.bounds
        if let cached = cachedIcon(for: app.url.path) {
            iconLayer.contents = cached
        }
        container.addSublayer(iconLayer)
        setIcon(for: iconLayer, app: app)
        return container
    }

    private func updateDragging(at point: CGPoint) {
        dragCurrentPoint = point
        CATransaction.begin()
        CATransaction.setDisableActions(true)
        draggingLayer?.frame = CGRect(x: point.x - iconSize / 2, y: point.y - iconSize / 2, width: iconSize, height: iconSize)
        CATransaction.commit()

        if point.x < dragOutInset || point.y < dragOutInset || point.x > bounds.width - dragOutInset || point.y > bounds.height - dragOutInset {
            if let app = draggingApp {
                cancelDragging(restoreSource: false)
                onDragAppOut?(app)
            }
            return
        }

        if layoutMode == .paged {
            let edgeDirection: Int?
            if point.x < pageFlipEdgeWidth {
                edgeDirection = -1
            } else if point.x > bounds.width - pageFlipEdgeWidth {
                edgeDirection = 1
            } else {
                edgeDirection = nil
            }

            if let edgeDirection {
                if !edgeDragRequiresReentry {
                    startEdgeFlipTimer(direction: edgeDirection)
                }
            } else {
                edgeDragRequiresReentry = false
                cancelEdgeFlipTimer()
            }
            guard !isPageScrollAnimating else { return }
        }

        let hoverIndex = gridIndex(at: point)
        updateReorderPreview(targetIndex: hoverIndex == draggingIndex ? nil : hoverIndex)
    }

    private func startEdgeFlipTimer(direction: Int) {
        guard layoutMode == .paged, !isPageScrollAnimating else { return }
        let targetPage = currentPage + direction
        guard targetPage >= 0, targetPage < pageCount else {
            cancelEdgeFlipTimer()
            return
        }
        if edgeDragDirection == direction, edgeDragTimer != nil { return }
        cancelEdgeFlipTimer()
        edgeDragDirection = direction
        let timer = Timer(timeInterval: pageFlipDelay, repeats: false) { [weak self] _ in
            guard let self else { return }
            self.edgeDragTimer = nil
            self.edgeDragDirection = nil
            guard self.isDraggingItem else { return }
            let nextPage = self.currentPage + direction
            guard nextPage >= 0, nextPage < self.pageCount else { return }
            self.resetReorderPreview(animated: false)
            self.currentHoverIndex = nil
            self.edgeDragRequiresReentry = true
            self.pendingDragUpdateAfterPageAnimation = true
            self.navigateToPage(nextPage, animated: true)
            if !self.isPageScrollAnimating {
                self.pendingDragUpdateAfterPageAnimation = false
                DispatchQueue.main.async { [weak self] in
                    guard let self, self.isDraggingItem else { return }
                    self.updateDragging(at: self.dragCurrentPoint)
                }
            }
        }
        RunLoop.main.add(timer, forMode: .common)
        edgeDragTimer = timer
    }

    private func cancelEdgeFlipTimer() {
        edgeDragTimer?.invalidate()
        edgeDragTimer = nil
        edgeDragDirection = nil
    }

    private func finishDragging(at point: CGPoint) {
        guard let source = draggingIndex else {
            cancelDragging()
            return
        }
        finishPageAnimationImmediatelyIfNeeded()
        let target = currentHoverIndex ?? gridIndex(at: point) ?? source
        let clampedTarget = min(max(0, target), apps.count)
        let shouldReorder = source != clampedTarget
        if shouldReorder {
            finishDraggingAfterReorder()
            onReorderApps?(source, clampedTarget)
        } else {
            cancelDragging(restoreSource: true, animated: true)
        }
    }

    private func finishDraggingAfterReorder() {
        cancelEdgeFlipTimer()
        edgeDragRequiresReentry = false
        pendingDragUpdateAfterPageAnimation = false
        draggingLayer?.removeFromSuperlayer()
        draggingLayer = nil
        isDraggingItem = false
        currentHoverIndex = nil

        DispatchQueue.main.async { [weak self] in
            guard let self else { return }
            self.draggingIndex = nil
            self.draggingApp = nil
        }
    }

    private func cancelDragging(restoreSource: Bool = true, animated: Bool = true) {
        cancelEdgeFlipTimer()
        edgeDragRequiresReentry = false
        pendingDragUpdateAfterPageAnimation = false
        resetReorderPreview(animated: animated)
        if restoreSource, let index = draggingIndex, appLayers.indices.contains(index) {
            appLayers[index].opacity = 1
        }
        draggingLayer?.removeFromSuperlayer()
        draggingLayer = nil
        draggingIndex = nil
        draggingApp = nil
        isDraggingItem = false
        currentHoverIndex = nil
    }

    private func finishPageAnimationImmediatelyIfNeeded() {
        guard layoutMode == .paged, isPageScrollAnimating else { return }
        pageScrollSnapWorkItem?.cancel()
        pendingDragUpdateAfterPageAnimation = false
        isPageScrollAnimating = false
        horizontalOffset = targetHorizontalOffset
        applyHorizontalOffset()
    }

    private func updateReorderPreview(targetIndex: Int?) {
        guard let source = draggingIndex, apps.indices.contains(source) else { return }
        let clampedTarget = targetIndex.map { min(max(0, $0), apps.count) }
        guard currentHoverIndex != clampedTarget else { return }
        currentHoverIndex = clampedTarget

        let metrics = makeMetrics()
        if layoutMode == .paged {
            updatePagedReorderPreview(source: source, target: clampedTarget, metrics: metrics)
        } else {
            updateVerticalReorderPreview(source: source, target: clampedTarget, metrics: metrics)
        }
    }

    private func updatePagedReorderPreview(source: Int, target: Int?, metrics: Metrics) {
        let pageStart = currentPage * metrics.itemsPerPage
        let pageEnd = min(pageStart + metrics.itemsPerPage, apps.count)
        guard pageStart < pageEnd else { return }
        let sourceInCurrentPage = source >= pageStart && source < pageEnd
        let hoverLocalIndex: Int? = {
            guard let target, target >= pageStart, target <= pageEnd else { return nil }
            return min(max(0, target - pageStart), max(0, pageEnd - pageStart))
        }()

        CATransaction.begin()
        CATransaction.setAnimationDuration(animationsEnabled ? 0.28 : 0)
        CATransaction.setAnimationTimingFunction(CAMediaTimingFunction(controlPoints: 0.25, 1.0, 0.35, 1.0))

        for index in apps.indices {
            guard appLayers.indices.contains(index) else { continue }
            let layer = appLayers[index]
            if index == source {
                layer.opacity = 0
                continue
            }

            guard index >= pageStart, index < pageEnd else {
                layer.opacity = 1
                continue
            }

            let localIndex = index - pageStart
            var visualIndex = index
            if let hoverLocalIndex {
                if sourceInCurrentPage {
                    let sourceLocalIndex = source - pageStart
                    if sourceLocalIndex < hoverLocalIndex,
                       localIndex > sourceLocalIndex,
                       localIndex <= hoverLocalIndex {
                        visualIndex = index - 1
                    } else if sourceLocalIndex > hoverLocalIndex,
                              localIndex >= hoverLocalIndex,
                              localIndex < sourceLocalIndex {
                        visualIndex = index + 1
                    }
                } else if localIndex >= hoverLocalIndex {
                    visualIndex = index + 1
                }
            }

            let frame = frameForGridSlot(at: visualIndex, metrics: metrics)
            layer.transform = CATransform3DIdentity
            layer.frame = frame
            if itemFrames.indices.contains(index) {
                itemFrames[index] = visibleFrame(frame)
            }
            layoutSublayers(of: layer, metrics: metrics)
            layer.opacity = 1
        }

        CATransaction.commit()
    }

    private func updateVerticalReorderPreview(source: Int, target: Int?, metrics: Metrics) {
        let visualOrder = visualOrderForDrag(source: source, target: target)

        CATransaction.begin()
        CATransaction.setAnimationDuration(animationsEnabled ? 0.28 : 0)
        CATransaction.setAnimationTimingFunction(CAMediaTimingFunction(controlPoints: 0.25, 1.0, 0.35, 1.0))

        for index in apps.indices {
            guard appLayers.indices.contains(index) else { continue }
            let layer = appLayers[index]
            if index == source {
                layer.opacity = 0
                continue
            }
            guard let visualIndex = visualOrder.firstIndex(of: index) else { continue }
            let frame = frameForGridSlot(at: visualIndex, metrics: metrics)
            layer.transform = CATransform3DIdentity
            layer.frame = frame
            if itemFrames.indices.contains(index) {
                itemFrames[index] = visibleFrame(frame)
            }
            layoutSublayers(of: layer, metrics: metrics)
            layer.opacity = 1
        }

        CATransaction.commit()
    }

    private func visualOrderForDrag(source: Int, target: Int?) -> [Int] {
        var order = Array(apps.indices)
        guard order.indices.contains(source) else { return order }
        let moving = order.remove(at: source)
        if let target {
            order.insert(moving, at: min(max(0, target), order.count))
        } else {
            order.insert(moving, at: source)
        }
        return order
    }

    private func resetReorderPreview(animated: Bool) {
        guard !appLayers.isEmpty else { return }
        let metrics = makeMetrics()

        CATransaction.begin()
        CATransaction.setDisableActions(!animated)
        CATransaction.setAnimationDuration(animated && animationsEnabled ? 0.2 : 0)
        CATransaction.setAnimationTimingFunction(CAMediaTimingFunction(name: .easeOut))

        itemFrames = Array(repeating: .zero, count: apps.count)
        for index in apps.indices {
            guard appLayers.indices.contains(index) else { continue }
            let frame = frameForGridSlot(at: index, metrics: metrics)
            itemFrames[index] = visibleFrame(frame)
            appLayers[index].transform = CATransform3DIdentity
            appLayers[index].frame = frame
            layoutSublayers(of: appLayers[index], metrics: metrics)
        }

        CATransaction.commit()
    }

    private func ensureSelectionVisible() {
        guard let selectedIndex else { return }
        if layoutMode == .paged {
            let metrics = makeMetrics()
            let page = selectedIndex / metrics.itemsPerPage
            if page != currentPage {
                navigateToPage(page, animated: true)
            }
            return
        }
        guard itemFrames.indices.contains(selectedIndex) else { return }
        let frame = itemFrames[selectedIndex]
        let metrics = makeMetrics()
        if frame.minY < contentInsets.bottom {
            verticalOffset -= contentInsets.bottom - frame.minY
        } else if frame.maxY > bounds.height - contentInsets.top {
            verticalOffset += frame.maxY - (bounds.height - contentInsets.top)
        }
        verticalOffset = clampVerticalOffset(verticalOffset, metrics: metrics)
        updateLayout(animated: true)
    }

    private func updateHoverIndex(_ index: Int?) {
        guard hoveredIndex != index else { return }
        let old = hoveredIndex
        hoveredIndex = index
        if let old { applyScale(at: old, animated: true) }
        if let index { applyScale(at: index, animated: true) }
    }

    private func applyScale(at index: Int, animated: Bool) {
        guard appLayers.indices.contains(index) else { return }
        let layer = appLayers[index]
        var iconScale: CGFloat = 1
        if selectedIndex == index {
            iconScale = 1.16
        } else if hoverMagnificationEnabled && hoveredIndex == index {
            iconScale = hoverMagnificationScale
        }
        let pressScale: CGFloat = (activePressEffectEnabled && pressedIndex == index) ? activePressScale : 1
        CATransaction.begin()
        CATransaction.setDisableActions(!animated)
        CATransaction.setAnimationDuration(animated ? 0.12 : 0)
        CATransaction.setAnimationTimingFunction(CAMediaTimingFunction(name: .easeOut))
        layer.transform = CATransform3DMakeScale(pressScale, pressScale, 1)
        if let icon = layer.sublayers?.first(where: { $0.name == "icon" }) {
            icon.transform = CATransform3DMakeScale(iconScale, iconScale, 1)
        }
        CATransaction.commit()
    }
}
