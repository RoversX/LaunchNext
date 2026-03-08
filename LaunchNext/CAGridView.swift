import AppKit
import QuartzCore
import Combine
import SwiftUI

// MARK: - Safe Array Subscript
extension Array {
    subscript(safe index: Int) -> Element? {
        return indices.contains(index) ? self[index] : nil
    }
}

// MARK: - Core Animation Grid View
/// 使用 Core Animation 实现的高性能网格视图，支持 120Hz ProMotion
final class CAGridView: NSView, CALayerDelegate {

    // MARK: - Properties

    var displayLink: CADisplayLink?
    var containerLayer: CALayer!
    var pageContainerLayer: CALayer!
    var iconLayers: [[CALayer]] = []  // [page][item]

    // 网格配置
    var columns: Int = 7 { didSet { rebuildLayers() } }
    var rows: Int = 5 { didSet { rebuildLayers() } }
    var iconSize: CGFloat = 72 {
        didSet {
            guard iconSize != oldValue else { return }
            clearIconCache()
            updateLayout()
        }
    }
    var columnSpacing: CGFloat = 24 { didSet { updateLayout() } }
    var rowSpacing: CGFloat = 36 { didSet { updateLayout() } }
    var labelFontSize: CGFloat = 12 { didSet { rebuildLayers() } }  // 默认 12pt，比原来大一点
    var labelFontWeight: NSFont.Weight = .medium { didSet { updateLabelFonts() } }
    var showLabels: Bool = true { didSet { updateLabelVisibility() } }
    var isLayoutLocked: Bool = false
    var folderDropZoneScale: CGFloat = CGFloat(AppStore.defaultFolderDropZoneScale)
    var folderPreviewScale: CGFloat = 1
    var contentInsets: NSEdgeInsets = NSEdgeInsets(top: 0, left: 0, bottom: 0, right: 0) { didSet { updateLayout() } }
    var pageSpacing: CGFloat = 0 { didSet { updateLayout() } }

    // Data source
    var items: [LaunchpadItem] = [] {
        didSet {
            needsLayoutRefresh = true
            syncBatchSelectionWithItems()
            rebuildLayers()
            if enableIconPreload {
                preloadIcons()
            }
        }
    }
    var needsLayoutRefresh = true

    // 分页
    var currentPage: Int = 0
    var itemsPerPage: Int { columns * rows }
    var pageCount: Int { max(1, (items.count + itemsPerPage - 1) / itemsPerPage) }

    // 滚动状态
    var scrollOffset: CGFloat = 0
    var targetScrollOffset: CGFloat = 0
    var scrollVelocity: CGFloat = 0
    var isScrollAnimating = false
    var scrollSensitivity: Double = AppStore.defaultScrollSensitivity
    var reverseWheelPagingDirection: Bool = false
    var animationsEnabled: Bool = true
    var animationDuration: Double = 0.3
    var scrollAnimationStartTime: CFTimeInterval = 0
    var scrollAnimationStartOffset: CGFloat = 0
    var hoverMagnificationEnabled: Bool = false {
        didSet {
            if !hoverMagnificationEnabled {
                clearHover()
            }
        }
    }
    var hoverMagnificationScale: CGFloat = 1.2
    var activePressEffectEnabled: Bool = false
    var activePressScale: CGFloat = 0.92
    var isDragging = false
    var dragStartOffset: CGFloat = 0
    var accumulatedDelta: CGFloat = 0

    // 性能监控
    var lastFrameTime: CFAbsoluteTime = 0
    var frameCount: Int = 0
    var currentFPS: Double = 120
    var frameTimes: [Double] = []

    // 图标缓存
    var iconCache: [String: CGImage] = [:]
    let iconCacheLock = NSLock()
    var enableIconPreload: Bool = false

    // 回调
    var onItemClicked: ((LaunchpadItem, Int) -> Void)?
    var onItemDoubleClicked: ((LaunchpadItem, Int) -> Void)?
    var onPageChanged: ((Int) -> Void)?
    var onFPSUpdate: ((Double) -> Void)?
    var onEmptyAreaClicked: (() -> Void)?
    var onHideApp: ((AppInfo) -> Void)?
    var onDissolveFolder: ((FolderInfo) -> Void)?
    var onUninstallWithTool: ((AppInfo) -> Void)?
    var onCreateFolder: ((AppInfo, AppInfo, Int) -> Void)?  // (拖拽的app, 目标app, 位置)
    var onMoveToFolder: ((AppInfo, FolderInfo) -> Void)?    // 移动到已有文件夹
    var onReorderItems: ((Int, Int) -> Void)?               // 重新排序 (fromIndex, toIndex)
    var onReorderAppBatch: (([String], Int) -> Void)?       // 批量重排（按路径顺序）
    var onRequestNewPage: (() -> Void)?                     // 请求创建新页面
    var hideAppMenuTitle: String = "Hide application"
    var dissolveFolderMenuTitle: String = "Dissolve folder"
    var uninstallWithToolMenuTitle: String = "Uninstall with configured tool"
    var batchSelectAppsMenuTitle: String = "Batch Select Apps"
    var finishBatchSelectionMenuTitle: String = "Finish Batch Selection"
    var canUseConfiguredUninstallTool: Bool = false
    var contextMenuTargetApp: AppInfo?
    var contextMenuTargetFolder: FolderInfo?
    var allowsBatchSelectionMode: Bool = true {
        didSet {
            if !allowsBatchSelectionMode {
                disableBatchSelectionMode()
            }
        }
    }
    var isBatchSelectionMode = false
    var batchSelectedAppPathsOrdered: [String] = []
    var batchSelectedAppPathSet: Set<String> = []
    var batchDraggingAppPathsOrdered: [String] = []
    var batchHiddenCompanionIndices: [Int] = []

    // 拖拽状态
    var isDraggingItem = false
    var draggingIndex: Int?
    var draggingItem: LaunchpadItem?
    var draggingLayer: CALayer?
    var dragStartPoint: CGPoint = .zero
    var dragCurrentPoint: CGPoint = .zero
    var dropTargetIndex: Int?
    var longPressTimer: Timer?
    let longPressDuration: TimeInterval = 0.5
    var pressedIndex: Int?

    // 跨页拖拽
    var edgeDragTimer: Timer?
    let edgeDragThreshold: CGFloat = 60  // 边缘检测区域宽度
    let edgeDragDelay: TimeInterval = 0.4  // 触发翻页延迟

    // Live reorder during drag
    var currentHoverIndex: Int?
    var pendingHoverIndex: Int?
    var originalIconPositions: [Int: CGPoint] = [:]
    var hoverUpdateTimer: Timer?
    let hoverUpdateDelay: TimeInterval = 0.15  // Delay before updating icon positions

    // 鼠标拖拽翻页
    var isPageDragging = false
    var pageDragStartX: CGFloat = 0
    var pageDragStartOffset: CGFloat = 0

    // 事件监听器
    var scrollEventMonitor: Any?
    var wasWindowVisible = false  // 跟踪窗口可见状态
    
    // 鼠标滚轮分页状态（仅用于非精准滚动设备）
    var wheelAccumulatedDelta: CGFloat = 0
    var wheelLastDirection: Int = 0
    var wheelLastFlipAt: Date?
    let wheelFlipCooldown: TimeInterval = 0.15
    // Legacy reference:
    // var wheelSnapTimer: Timer?
    // let wheelSnapDelay: TimeInterval = 0.15  // 停止滚动后多久触发 snap
    let debugScrollMismatch = false
    var externalDragActive = false
    var hoveredIndex: Int?
    var selectedIndex: Int?
    var hoverTrackingArea: NSTrackingArea?
    var isScrollEnabled: Bool = true

    func logIfMismatch(_ tag: String, appPage: Int? = nil) {
        guard debugScrollMismatch else { return }
        guard bounds.width > 0 else { return }
        let pageStride = bounds.width + pageSpacing
        let expectedOffset = -CGFloat(currentPage) * pageStride
        let transformOffset = pageContainerLayer.transform.m41
        let offsetMismatch = abs(scrollOffset - expectedOffset) > 0.5
        let transformMismatch = abs(transformOffset - scrollOffset) > 0.5
        guard offsetMismatch || transformMismatch else { return }
        let appInfo = appPage.map { ", appPage=\($0)" } ?? ""
        // print("⚠️ [CAGrid #\(instanceId)] \(tag) mismatch: currentPage=\(currentPage)\(appInfo), scroll=\(scrollOffset), expected=\(expectedOffset), transform=\(transformOffset), boundsW=\(bounds.width), pageSpacing=\(pageSpacing)")
    }

    // 实例追踪
    private static var instanceCounter = 0
    let instanceId: Int

    // MARK: - Initialization

    override init(frame frameRect: NSRect) {
        CAGridView.instanceCounter += 1
        self.instanceId = CAGridView.instanceCounter
        super.init(frame: frameRect)
        setup()
    }

    required init?(coder: NSCoder) {
        CAGridView.instanceCounter += 1
        self.instanceId = CAGridView.instanceCounter
        super.init(coder: coder)
        setup()
    }

    deinit {
        // print("💀 [CAGrid #\(instanceId)] deinit - instance being destroyed!")
        displayLink?.invalidate()
        removeScrollEventMonitor()
        NotificationCenter.default.removeObserver(self)
    }

    func setup() {
        wantsLayer = true
        layerContentsRedrawPolicy = .onSetNeedsDisplay

        // 创建容器层
        containerLayer = CALayer()
        containerLayer.frame = bounds
        containerLayer.masksToBounds = false  // 不裁剪，让滑动时内容可以超出边界
        layer?.addSublayer(containerLayer)

        // 页面容器层（用于整体偏移）
        pageContainerLayer = CALayer()
        pageContainerLayer.frame = bounds
        containerLayer.addSublayer(pageContainerLayer)

        // 禁用隐式动画
        CATransaction.begin()
        CATransaction.setDisableActions(true)
        CATransaction.commit()

        // 在初始化时就注册 launchpad 窗口通知（确保始终能接收）
        NotificationCenter.default.addObserver(self, selector: #selector(launchpadWindowDidShow(_:)), name: .launchpadWindowShown, object: nil)
        NotificationCenter.default.addObserver(self, selector: #selector(launchpadWindowDidHide(_:)), name: .launchpadWindowHidden, object: nil)
        // 监听应用激活事件（作为备用方案）
        NotificationCenter.default.addObserver(self, selector: #selector(appDidBecomeActive(_:)), name: NSApplication.didBecomeActiveNotification, object: nil)

        // print("✅ [CAGrid #\(instanceId)] Core Animation grid initialized")
    }

    func makeFirstResponderIfAvailable() {
        guard let win = window else { return }
        if win.firstResponder == nil || win.firstResponder === self {
            win.makeFirstResponder(self)
        }
    }

    override func viewDidMoveToWindow() {
        super.viewDidMoveToWindow()
        if let window = window {
            window.acceptsMouseMovedEvents = true
            setupDisplayLink()
            // 始终安装滚轮事件监听器（更可靠）
            setupScrollEventMonitor()
            // 确保视图成为第一响应者
            DispatchQueue.main.async { [weak self] in
                self?.makeFirstResponderIfAvailable()
            }
            // print("✅ [CAGrid #\(instanceId)] View moved to window, scroll monitor installed")

            // 监听窗口显示/隐藏事件
            NotificationCenter.default.removeObserver(self, name: NSWindow.didBecomeKeyNotification, object: nil)
            NotificationCenter.default.removeObserver(self, name: NSWindow.didBecomeMainNotification, object: nil)
            NotificationCenter.default.removeObserver(self, name: NSWindow.didChangeOcclusionStateNotification, object: nil)

            NotificationCenter.default.addObserver(self, selector: #selector(windowDidActivate(_:)), name: NSWindow.didBecomeKeyNotification, object: window)
            NotificationCenter.default.addObserver(self, selector: #selector(windowDidActivate(_:)), name: NSWindow.didBecomeMainNotification, object: window)
            NotificationCenter.default.addObserver(self, selector: #selector(windowOcclusionChanged(_:)), name: NSWindow.didChangeOcclusionStateNotification, object: window)
            // launchpad 窗口通知在 setup() 中注册，这里不需要重复注册
        } else {
            // 视图从窗口移除时清理窗口相关的事件监听器
            // 注意：launchpad 窗口通知不在这里移除，因为它们在 setup() 中注册
            removeScrollEventMonitor()
            NotificationCenter.default.removeObserver(self, name: NSWindow.didBecomeKeyNotification, object: nil)
            NotificationCenter.default.removeObserver(self, name: NSWindow.didBecomeMainNotification, object: nil)
            NotificationCenter.default.removeObserver(self, name: NSWindow.didChangeOcclusionStateNotification, object: nil)
        }
    }

    @objc func windowDidActivate(_ notification: Notification) {
        // print("🪟 [CAGrid] Window activated, making first responder")
        makeFirstResponderIfAvailable()
    }

    @objc func windowOcclusionChanged(_ notification: Notification) {
        guard let window = window else { return }
        if window.occlusionState.contains(.visible) {
            // print("🪟 [CAGrid] Window became visible, making first responder")
            makeFirstResponderIfAvailable()
        }
    }

    @objc func launchpadWindowDidShow(_ notification: Notification) {
        // 只有有窗口的实例才响应
        guard let window = window else {
            // print("⚠️ [CAGrid #\(instanceId)] Launchpad window shown - but no window, ignoring")
            return
        }
        // print("🚀 [CAGrid #\(instanceId)] Launchpad window shown, hasMonitor=\(scrollEventMonitor != nil)")

        // 立即安装滚轮事件监听器（如果没有）
        if scrollEventMonitor == nil {
            // print("🔄 [CAGrid #\(instanceId)] Reinstalling scroll monitor on window show")
            setupScrollEventMonitor()
        }

        // 确保成为第一响应者
        makeFirstResponderIfAvailable()

        // 延迟再次确认（防止其他组件抢占）
        DispatchQueue.main.asyncAfter(deadline: .now() + 0.1) { [weak self] in
            guard let self = self, let win = self.window else { return }
            // print("🔄 [CAGrid #\(self.instanceId)] Delayed check, isFirstResponder=\(win.firstResponder === self), hasMonitor=\(self.scrollEventMonitor != nil)")
            self.makeFirstResponderIfAvailable()
            // 确保滚轮监听器存在
            if self.scrollEventMonitor == nil {
                self.setupScrollEventMonitor()
            }
        }
    }

    @objc func launchpadWindowDidHide(_ notification: Notification) {
        // 只有有窗口的实例才响应
        guard window != nil else {
            // print("⚠️ [CAGrid #\(instanceId)] Window hidden - but no window, ignoring")
            return
        }
        // print("🚀 [CAGrid #\(instanceId)] Window hidden, hasMonitor=\(scrollEventMonitor != nil)")
        // 不再移除监听器 - 让它保持活跃，这样窗口重新显示时就能立即使用
        // removeScrollEventMonitor()
        wasWindowVisible = false
    }

    @objc func appDidBecomeActive(_ notification: Notification) {
        // 应用激活时检查是否需要安装滚轮监听器
        // print("🔔 [CAGrid #\(instanceId)] App became active notification received, window=\(window != nil), isVisible=\(window?.isVisible ?? false)")
        guard let window = window else {
            // print("🔔 [CAGrid #\(instanceId)] App became active - no window")
            return
        }

        // 立即尝试重新安装滚轮监听器（不管窗口是否可见）
        // 因为窗口可能正在动画中，isVisible 可能还是 false
        // print("🔔 [CAGrid #\(instanceId)] Reinstalling scroll monitor immediately on app activate")
        setupScrollEventMonitor()
        makeFirstResponderIfAvailable()

        // 延迟再次检查，确保滚轮监听器存在
        DispatchQueue.main.asyncAfter(deadline: .now() + 0.2) { [weak self] in
            guard let self = self, let win = self.window else { return }
            // print("🔔 [CAGrid #\(self.instanceId)] Delayed check: isVisible=\(win.isVisible), scrollMonitor=\(self.scrollEventMonitor != nil)")
            if self.scrollEventMonitor == nil {
                // print("🔄 [CAGrid #\(self.instanceId)] App became active (delayed), reinstalling scroll monitor")
                self.setupScrollEventMonitor()
            }
            self.makeFirstResponderIfAvailable()
        }
    }

    func setupScrollEventMonitor() {
        // 移除旧的监听器
        removeScrollEventMonitor()

        // 确保有窗口才设置监听器（可见性在事件处理时动态检查）
        guard window != nil else {
            // print("⚠️ [CAGrid #\(instanceId)] setupScrollEventMonitor: no window, skipping")
            return
        }

        let myInstanceId = self.instanceId

        scrollEventMonitor = NSEvent.addLocalMonitorForEvents(matching: .scrollWheel) { [weak self] event in
            guard let self = self else { return event }
            guard self.isScrollEnabled else { return event }
            guard let window = self.window else { return event }
            
            // 只在窗口可见且是 key window 时处理
            guard window.isVisible && window.isKeyWindow else { return event }
            
            // 检查事件是否在视图范围内
            let locationInWindow = event.locationInWindow
            let locationInView = self.convert(locationInWindow, from: nil)
            guard self.bounds.contains(locationInView) else { return event }
            
            self.handleScrollWheel(with: event)
            // 消费事件，不再传递，防止双重处理
            return nil
        }
        // print("✅ [CAGrid #\(instanceId)] Scroll event monitor installed")
    }

    func removeScrollEventMonitor() {
        if let monitor = scrollEventMonitor {
            // print("🗑️ [CAGrid #\(instanceId)] Removing scroll event monitor")
            NSEvent.removeMonitor(monitor)
            scrollEventMonitor = nil
        }
    }

    // MARK: - Display Link (120Hz)

    func setupDisplayLink() {
        displayLink?.invalidate()

        guard let window = window else {
            DispatchQueue.main.asyncAfter(deadline: .now() + 0.1) { [weak self] in
                self?.setupDisplayLink()
            }
            return
        }

        displayLink = window.displayLink(target: self, selector: #selector(displayLinkFired(_:)))
        displayLink?.preferredFrameRateRange = CAFrameRateRange(minimum: 60, maximum: 120, preferred: 120)
        displayLink?.add(to: .main, forMode: .common)

        // print("✅ [CAGrid] DisplayLink configured for 120Hz")
    }

    @objc func displayLinkFired(_ link: CADisplayLink) {
        // 只在动画时才更新
        guard isScrollAnimating || isDraggingItem else {
            // 空闲时重置帧计数
            if frameCount > 0 {
                frameCount = 0
                lastFrameTime = 0
            }
            return
        }

        // 计算实时帧率（仅在动画时）
        let now = CFAbsoluteTimeGetCurrent()
        if lastFrameTime > 0 {
            let delta = now - lastFrameTime
            let instantFPS = 1.0 / delta
            // 使用滑动窗口平均，减少数组操作
            if frameTimes.count >= 30 {
                frameTimes.removeFirst()
            }
            frameTimes.append(instantFPS)
            currentFPS = frameTimes.reduce(0, +) / Double(frameTimes.count)
        }
        lastFrameTime = now

        frameCount += 1
        // 每 60 帧输出一次（约 0.5 秒）
        if frameCount % 60 == 0 {
            onFPSUpdate?(currentFPS)
            // print("🎮 [CAGrid] Avg FPS: \(String(format: "%.1f", currentFPS))")
        }

        // 更新滚动动画
        if isScrollAnimating {
            updateScrollAnimation()
        }
    }

    // MARK: - Scroll Animation

    func updateScrollAnimation() {
        if !animationsEnabled {
            scrollOffset = targetScrollOffset
            scrollVelocity = 0
            isScrollAnimating = false
        } else {
            let diff = targetScrollOffset - scrollOffset
            let snapThreshold: CGFloat = 0.5
            if abs(diff) > snapThreshold {
                // 非时间控制：指数收敛，距离越远移动越快
                let t: CGFloat = 0.18
                scrollOffset += diff * t
            } else {
                scrollOffset = targetScrollOffset
                scrollVelocity = 0
                isScrollAnimating = false
            }
        }

        // 更新页面容器位置 - 使用最小开销的方式
        CATransaction.begin()
        CATransaction.setDisableActions(true)
        CATransaction.setAnimationDuration(0)
        pageContainerLayer.transform = CATransform3DMakeTranslation(scrollOffset, 0, 0)
        CATransaction.commit()
    }

    func easeOutSoft(_ t: CGFloat) -> CGFloat {
        // Damped spring: soft ease-out with a subtle bounce (about ~2% overshoot).
        return springEaseOut(t, damping: 0.78, frequency: 1.4)
    }

    func springEaseOut(_ t: CGFloat, damping: CGFloat, frequency: CGFloat) -> CGFloat {
        let clamped = max(0, min(1, t))
        if clamped == 0 { return 0 }
        if clamped == 1 { return 1 }

        let dampingRatio = max(0, min(1, damping))
        let omega = 2 * CGFloat.pi * max(0.1, frequency)
        if dampingRatio >= 1 {
            return 1 - exp(-omega * clamped)
        }

        let omegaD = omega * sqrt(1 - dampingRatio * dampingRatio)
        let expTerm = exp(-dampingRatio * omega * clamped)
        let cosTerm = cos(omegaD * clamped)
        let sinTerm = sin(omegaD * clamped)
        let coeff = dampingRatio / sqrt(1 - dampingRatio * dampingRatio)
        return 1 - expTerm * (cosTerm + coeff * sinTerm)
    }

    func easeOutBack(_ t: CGFloat, overshoot: CGFloat) -> CGFloat {
        let clamped = max(0, min(1, t))
        let s = max(0, overshoot)
        let t1 = clamped - 1
        return 1 + (s + 1) * t1 * t1 * t1 + s * t1 * t1
    }

    func cubicBezier(_ x: CGFloat, c1: CGPoint, c2: CGPoint) -> CGFloat {
        let clamped = max(0, min(1, x))
        let t = solveBezierT(forX: clamped, c1x: c1.x, c2x: c2.x)
        return cubicBezierValue(t, c1: c1.y, c2: c2.y)
    }

    func cubicBezierValue(_ t: CGFloat, c1: CGFloat, c2: CGFloat) -> CGFloat {
        let oneMinusT = 1 - t
        return 3 * oneMinusT * oneMinusT * t * c1
            + 3 * oneMinusT * t * t * c2
            + t * t * t
    }

    func cubicBezierDerivative(_ t: CGFloat, c1: CGFloat, c2: CGFloat) -> CGFloat {
        let oneMinusT = 1 - t
        return 3 * oneMinusT * oneMinusT * c1
            + 6 * oneMinusT * t * (c2 - c1)
            + 3 * t * t * (1 - c2)
    }

    func solveBezierT(forX x: CGFloat, c1x: CGFloat, c2x: CGFloat) -> CGFloat {
        var t = x
        for _ in 0..<5 {
            let xAtT = cubicBezierValue(t, c1: c1x, c2: c2x)
            let dx = xAtT - x
            if abs(dx) < 1e-4 { return t }
            let d = cubicBezierDerivative(t, c1: c1x, c2: c2x)
            if abs(d) < 1e-5 { break }
            t -= dx / d
            if t < 0 || t > 1 { break }
        }
        var low: CGFloat = 0
        var high: CGFloat = 1
        for _ in 0..<8 {
            let mid = (low + high) * 0.5
            let xAtMid = cubicBezierValue(mid, c1: c1x, c2: c2x)
            if xAtMid < x {
                low = mid
            } else {
                high = mid
            }
        }
        return (low + high) * 0.5
    }
    
    // Set initial page before items are set to ensure correct positioning
    func setInitialPage(_ page: Int) {
        currentPage = max(0, page)
    }

    func navigateToPage(_ page: Int, animated: Bool = true) {
        let newPage = max(0, min(pageCount - 1, page))
        let pageChanged = newPage != currentPage
        currentPage = newPage

        // 如果 bounds 还没准备好，只更新 currentPage，实际滚动交给 layout() 处理
        guard bounds.width > 0 else {
            if pageChanged {
                onPageChanged?(currentPage)
            }
            return
        }

        let pageStride = bounds.width + pageSpacing
        targetScrollOffset = -CGFloat(currentPage) * pageStride

        // 检查是否需要动画（包括弹回原位的情况）
        let needsAnimation = animated && abs(scrollOffset - targetScrollOffset) > 0.5
        
        if needsAnimation && animationsEnabled {
            isScrollAnimating = true
        } else {
            // 立即跳转
            isScrollAnimating = false
            scrollOffset = targetScrollOffset
            CATransaction.begin()
            CATransaction.setDisableActions(true)
            pageContainerLayer.transform = CATransform3DMakeTranslation(scrollOffset, 0, 0)
            CATransaction.commit()
        }

        if pageChanged {
            onPageChanged?(currentPage)
        }
        logIfMismatch("navigateToPage")
    }

    // MARK: - Public Methods

    var isBatchDragging: Bool { !batchDraggingAppPathsOrdered.isEmpty }

    func enableBatchSelectionMode() {
        guard allowsBatchSelectionMode else {
            NSSound.beep()
            return
        }
        isBatchSelectionMode = true
        syncBatchSelectionWithItems()
        refreshBatchSelectionUI()
    }

    func disableBatchSelectionMode() {
        if isDraggingItem && isBatchDragging {
            cancelDragging()
        }
        let hadState = isBatchSelectionMode ||
            !batchSelectedAppPathsOrdered.isEmpty ||
            !batchDraggingAppPathsOrdered.isEmpty
        isBatchSelectionMode = false
        batchSelectedAppPathsOrdered.removeAll()
        batchSelectedAppPathSet.removeAll()
        batchDraggingAppPathsOrdered.removeAll()
        restoreBatchHiddenCompanionLayers()
        if hadState {
            refreshBatchSelectionUI()
        }
    }

    func toggleBatchSelection(forAppPath path: String) {
        guard isBatchSelectionMode else { return }
        if batchSelectedAppPathSet.contains(path) {
            batchSelectedAppPathSet.remove(path)
            batchSelectedAppPathsOrdered.removeAll { $0 == path }
        } else {
            batchSelectedAppPathSet.insert(path)
            batchSelectedAppPathsOrdered.append(path)
        }
        refreshBatchSelectionUI()
    }

    func orderedBatchDragPaths(leadingAppPath path: String) -> [String] {
        guard batchSelectedAppPathSet.contains(path) else { return [] }
        var ordered: [String] = [path]
        ordered.append(contentsOf: batchSelectedAppPathsOrdered.filter { $0 != path })
        return ordered
    }

    func appPath(at index: Int) -> String? {
        guard items.indices.contains(index), case .app(let app) = items[index] else { return nil }
        return app.url.path
    }

    func syncBatchSelectionWithItems() {
        guard isBatchSelectionMode else { return }
        let currentPaths = Set(items.compactMap { item -> String? in
            guard case .app(let app) = item else { return nil }
            return app.url.path
        })
        let oldCount = batchSelectedAppPathSet.count
        batchSelectedAppPathSet = batchSelectedAppPathSet.intersection(currentPaths)
        batchSelectedAppPathsOrdered = batchSelectedAppPathsOrdered.filter { batchSelectedAppPathSet.contains($0) }
        if batchSelectedAppPathSet.count != oldCount {
            refreshBatchSelectionUI()
        }
    }

    func globalIndex(forAppPath path: String) -> Int? {
        for (index, item) in items.enumerated() {
            if case .app(let app) = item, app.url.path == path {
                return index
            }
        }
        return nil
    }

    func setOpacity(_ opacity: Float, forGlobalIndex index: Int) {
        let pageIndex = index / itemsPerPage
        let localIndex = index % itemsPerPage
        guard pageIndex < iconLayers.count, localIndex < iconLayers[pageIndex].count else { return }
        iconLayers[pageIndex][localIndex].opacity = opacity
    }

    func restoreBatchHiddenCompanionLayers() {
        guard !batchHiddenCompanionIndices.isEmpty else { return }
        for index in batchHiddenCompanionIndices {
            setOpacity(1.0, forGlobalIndex: index)
        }
        batchHiddenCompanionIndices.removeAll()
        batchDraggingAppPathsOrdered.removeAll()
    }

    func clearIconCache() {
        iconCacheLock.lock()
        iconCache.removeAll()
        iconCacheLock.unlock()
    }

    func refreshLayout() {
        rebuildLayers()
    }

    func snapToCurrentPageIfNeeded() {
        // 如果用户正在拖拽或动画正在进行，不要强制 snap
        guard !isDragging && !isScrollAnimating && !isPageDragging else { return }
        guard bounds.width > 0 else { return }
        
        let expectedOffset = -CGFloat(currentPage) * (bounds.width + pageSpacing)
        let transformOffset = pageContainerLayer.transform.m41
        let needsOffsetSync = abs(scrollOffset - expectedOffset) > 0.5
        let needsTransformSync = abs(transformOffset - scrollOffset) > 0.5
        guard needsOffsetSync || needsTransformSync else { return }

        if needsOffsetSync {
            scrollOffset = expectedOffset
            targetScrollOffset = expectedOffset
        }

        CATransaction.begin()
        CATransaction.setDisableActions(true)
        CATransaction.setAnimationDuration(0)
        pageContainerLayer.transform = CATransform3DMakeTranslation(scrollOffset, 0, 0)
        CATransaction.commit()
    }

    func forceSyncPageTransformIfNeeded() {
        guard bounds.width > 0 else { return }
        let pageStride = bounds.width + pageSpacing
        let expectedOffset = -CGFloat(currentPage) * pageStride
        if abs(scrollOffset - expectedOffset) > 0.5 {
            scrollOffset = expectedOffset
            targetScrollOffset = expectedOffset
        }
        let transformOffset = pageContainerLayer.transform.m41
        guard abs(transformOffset - scrollOffset) > 0.5 else { return }
        CATransaction.begin()
        CATransaction.setDisableActions(true)
        CATransaction.setAnimationDuration(0)
        pageContainerLayer.transform = CATransform3DMakeTranslation(scrollOffset, 0, 0)
        CATransaction.commit()
    }

    /// 确保滚轮事件监听器已安装（供外部调用）
    func ensureScrollMonitorInstalled() {
        guard let window = window else {
            // print("⚠️ [CAGrid #\(instanceId)] ensureScrollMonitorInstalled: no window")
            return
        }

        // 只要有窗口且没有监听器就安装（可见性在事件处理时检查）
        if scrollEventMonitor == nil {
            // print("🔄 [CAGrid #\(instanceId)] ensureScrollMonitorInstalled: monitor missing, installing")
            setupScrollEventMonitor()
            makeFirstResponderIfAvailable()
        }
    }

    /// 获取实例ID（用于调试）
    var debugInstanceId: Int { instanceId }
}
