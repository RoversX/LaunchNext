import AppKit
import QuartzCore

extension CAGridView {
    // MARK: - Input Handling

    override var acceptsFirstResponder: Bool { true }

    override func becomeFirstResponder() -> Bool {
        // print("🎯 [CAGrid] becomeFirstResponder")
        return true
    }

    override func resignFirstResponder() -> Bool {
        // print("🎯 [CAGrid] resignFirstResponder")
        return true
    }

    // 确保视图接受第一次鼠标点击就能响应
    override func acceptsFirstMouse(for event: NSEvent?) -> Bool {
        return true
    }

    // 确保视图可以接收鼠标事件
    override func hitTest(_ point: NSPoint) -> NSView? {
        let result = frame.contains(point) ? self : nil
        return result
    }

    override func updateTrackingAreas() {
        super.updateTrackingAreas()
        if let existing = hoverTrackingArea {
            removeTrackingArea(existing)
        }
        let options: NSTrackingArea.Options = [.mouseMoved, .mouseEnteredAndExited, .activeInKeyWindow, .inVisibleRect]
        let area = NSTrackingArea(rect: bounds, options: options, owner: self, userInfo: nil)
        addTrackingArea(area)
        hoverTrackingArea = area
    }

    override func mouseMoved(with event: NSEvent) {
        guard hoverMagnificationEnabled else {
            clearHover()
            return
        }
        guard !isDraggingItem && !isPageDragging && !isDragging else {
            clearHover()
            return
        }
        let location = convert(event.locationInWindow, from: nil)
        if let (item, _) = itemAt(location), case .empty = item {
            updateHoverIndex(nil)
        } else if let (_, index) = itemAt(location) {
            updateHoverIndex(index)
        } else {
            updateHoverIndex(nil)
        }
    }

    override func mouseExited(with event: NSEvent) {
        clearHover()
    }

    override func viewDidChangeEffectiveAppearance() {
        super.viewDidChangeEffectiveAppearance()
        updateLabelColors()
        updateFolderGlassColors()
    }

    override func scrollWheel(with event: NSEvent) {
        // 当本地 monitor 存在时，避免双重处理
        if scrollEventMonitor != nil {
            return
        }
        guard isScrollEnabled else { return }
        handleScrollWheel(with: event)
    }

    func handleScrollWheel(with event: NSEvent) {
        // 优先使用水平滑动，如果没有则用垂直滑动（反向）
        let deltaX = event.scrollingDeltaX
        let deltaY = event.scrollingDeltaY
        let delta = abs(deltaX) > abs(deltaY) ? deltaX : -deltaY
        let baseline = max(AppStore.defaultScrollSensitivity, 0.0001)
        let sensitivityScale = CGFloat(max(scrollSensitivity, 0.0001) / baseline)
        let scaledDelta = delta * sensitivityScale
        let isPrecise = event.hasPreciseScrollingDeltas

        if !isPrecise {
            /*
            // 旧版滚轮跟手 + 定时器 snap 逻辑（保留注释，便于后续对比）
            wheelSnapTimer?.invalidate()

            // 累积滚动量
            wheelAccumulatedDelta += scaledDelta * 8  // 放大系数，让跟手效果更明显

            // 计算临时偏移（带橡皮筋效果）
            let pageStride = bounds.width + pageSpacing
            let baseOffset = -CGFloat(currentPage) * pageStride
            var newOffset = baseOffset + wheelAccumulatedDelta

            // 橡皮筋效果：边界阻力
            let minOffset = -CGFloat(pageCount - 1) * pageStride
            let maxOffset: CGFloat = 0
            if newOffset > maxOffset {
                let overscroll = newOffset - maxOffset
                newOffset = maxOffset + rubberBand(overscroll, limit: bounds.width * 0.15)
            } else if newOffset < minOffset {
                let overscroll = newOffset - minOffset
                newOffset = minOffset + rubberBand(overscroll, limit: bounds.width * 0.15)
            }

            // 更新显示
            scrollOffset = newOffset
            CATransaction.begin()
            CATransaction.setDisableActions(true)
            pageContainerLayer.transform = CATransform3DMakeTranslation(scrollOffset, 0, 0)
            CATransaction.commit()

            // 设置定时器，停止滚动后决定翻页或弹回
            wheelSnapTimer = Timer.scheduledTimer(withTimeInterval: wheelSnapDelay, repeats: false) { [weak self] _ in
                guard let self = self else { return }

                let threshold = self.bounds.width * 0.15  // 15% 触发翻页
                var targetPage = self.currentPage

                if self.wheelAccumulatedDelta < -threshold {
                    targetPage = self.currentPage + 1
                } else if self.wheelAccumulatedDelta > threshold {
                    targetPage = self.currentPage - 1
                }

                self.wheelAccumulatedDelta = 0
                self.navigateToPage(targetPage, animated: true)
            }
            */

            // 只优化普通滚轮，不改精准设备（触控板 / Magic Mouse）路径
            handleWheelPaging(with: scaledDelta)
            return
        }

        // 触控板滑动
        switch event.phase {
        case .began:
            isDragging = true
            isScrollAnimating = false
            dragStartOffset = scrollOffset
            accumulatedDelta = 0
            scrollVelocity = 0

        case .changed:
            accumulatedDelta += scaledDelta

            // 计算新的偏移量
            var newOffset = dragStartOffset + accumulatedDelta

            // 橡皮筋效果：在边界处添加阻力
            let pageStride = bounds.width + pageSpacing
            let minOffset = -CGFloat(pageCount - 1) * pageStride
            let maxOffset: CGFloat = 0

            if newOffset > maxOffset {
                // 超出左边界
                let overscroll = newOffset - maxOffset
                newOffset = maxOffset + rubberBand(overscroll, limit: bounds.width * 0.2)
            } else if newOffset < minOffset {
                // 超出右边界
                let overscroll = newOffset - minOffset
                newOffset = minOffset + rubberBand(overscroll, limit: bounds.width * 0.2)
            }

            scrollOffset = newOffset

            // 性能优化：使用 CATransaction 批量更新
            CATransaction.begin()
            CATransaction.setDisableActions(true)
            CATransaction.setAnimationDuration(0)
            pageContainerLayer.transform = CATransform3DMakeTranslation(scrollOffset, 0, 0)
            CATransaction.commit()

        case .ended, .cancelled:
            isDragging = false

            // 根据滑动距离和速度确定目标页面
            let velocity = (abs(deltaX) > abs(deltaY) ? deltaX : -deltaY) * sensitivityScale
            let threshold = (bounds.width + pageSpacing) * 0.15  // 15% 即可触发翻页
            let velocityThreshold: CGFloat = 30
            var targetPage = currentPage

            // 根据累计滑动方向决定翻页
            if accumulatedDelta < -threshold || velocity < -velocityThreshold {
                targetPage = currentPage + 1
            } else if accumulatedDelta > threshold || velocity > velocityThreshold {
                targetPage = currentPage - 1
            }

            navigateToPage(targetPage)

        default:
            break
        }
    }

    private func handleWheelPaging(with scaledDelta: CGFloat) {
        guard scaledDelta != 0 else { return }

        let direction = scaledDelta > 0 ? 1 : -1
        let effectiveDirection = reverseWheelPagingDirection ? -direction : direction
        if wheelLastDirection != direction {
            wheelAccumulatedDelta = 0
        }
        wheelLastDirection = direction
        wheelAccumulatedDelta += abs(scaledDelta)

        // 固定阈值，灵敏度变化已反映在 scaledDelta
        let threshold: CGFloat = 2.0
        guard wheelAccumulatedDelta >= threshold else { return }

        let now = Date()
        if let last = wheelLastFlipAt, now.timeIntervalSince(last) < wheelFlipCooldown {
            return
        }

        // Keep existing CA direction semantics by default; optional override flips wheel-only paging.
        let targetPage = effectiveDirection > 0 ? currentPage - 1 : currentPage + 1
        wheelLastFlipAt = now
        wheelAccumulatedDelta = 0
        navigateToPage(targetPage, animated: true)
    }

    func rubberBand(_ offset: CGFloat, limit: CGFloat) -> CGFloat {
        let factor: CGFloat = 0.5
        let absOffset = abs(offset)
        let scaled = (factor * absOffset * limit) / (absOffset + limit)
        return offset >= 0 ? scaled : -scaled
    }

    override func mouseDown(with event: NSEvent) {
        // 确保成为第一响应者，这样后续的滚轮事件才能被接收
        window?.makeFirstResponder(self)

        let location = convert(event.locationInWindow, from: nil)
        // print("🖱️ [CAGrid] mouseDown at \(location)")

        if let (item, index) = itemAt(location) {
            // print("🖱️ [CAGrid] Hit item: \(item.name) at index \(index)")
            if event.clickCount == 1 {
                // 添加点击效果动画
                pressedIndex = index
                animatePress(at: index, pressed: true)
                dragStartPoint = location

                // 启动长按计时器（用于开始拖拽）
                // 注意：必须添加到 .common 模式，否则在鼠标追踪期间不会触发
                longPressTimer?.invalidate()
                let timer = Timer(timeInterval: longPressDuration, repeats: false) { [weak self] _ in
                    self?.startDragging(item: item, index: index, at: location)
                }
                RunLoop.main.add(timer, forMode: .common)
                longPressTimer = timer
            }
        } else {
            // 点击空白区域 - 开始页面拖拽模式
            // print("🖱️ [CAGrid] Hit empty area, starting page drag")
            isPageDragging = true
            pageDragStartX = location.x
            pageDragStartOffset = scrollOffset
            dragStartPoint = location
        }
    }

    override func mouseDragged(with event: NSEvent) {
        let location = convert(event.locationInWindow, from: nil)

        // 页面拖拽模式
        if isPageDragging {
            let deltaX = location.x - pageDragStartX
            var newOffset = pageDragStartOffset + deltaX

            // 橡皮筋效果 - 在边界处添加阻力
            let pageStride = bounds.width + pageSpacing
            let minOffset = -CGFloat(pageCount - 1) * pageStride
            let maxOffset: CGFloat = 0

            if newOffset > maxOffset {
                let overscroll = newOffset - maxOffset
                newOffset = maxOffset + rubberBand(overscroll, limit: bounds.width * 0.3)
            } else if newOffset < minOffset {
                let overscroll = newOffset - minOffset
                newOffset = minOffset + rubberBand(overscroll, limit: bounds.width * 0.3)
            }

            scrollOffset = newOffset

            CATransaction.begin()
            CATransaction.setDisableActions(true)
            pageContainerLayer.transform = CATransform3DMakeTranslation(scrollOffset, 0, 0)
            CATransaction.commit()
            return
        }

        // Check if moved enough distance to start dragging
        if !isDraggingItem, let idx = pressedIndex {
            if isLayoutLocked { return }
            let distance = hypot(location.x - dragStartPoint.x, location.y - dragStartPoint.y)
            if distance > 10 {
                // 取消长按计时器，立即开始拖拽
                longPressTimer?.invalidate()
                longPressTimer = nil
                if let item = items[safe: idx] {
                    startDragging(item: item, index: idx, at: location)
                }
            }
        }

        // 更新拖拽位置
        if isDraggingItem {
            updateDragging(at: location)
        }
    }

    override func mouseUp(with event: NSEvent) {
        let location = convert(event.locationInWindow, from: nil)

        // 取消长按计时器
        longPressTimer?.invalidate()
        longPressTimer = nil

        // 结束页面拖拽
        if isPageDragging {
            isPageDragging = false

            let totalDrag = location.x - pageDragStartX
            let threshold = (bounds.width + pageSpacing) * 0.15  // 15% 即可触发翻页

            var targetPage = currentPage
            if totalDrag < -threshold {
                // 向左拖 -> 下一页
                targetPage = min(currentPage + 1, pageCount - 1)
            } else if totalDrag > threshold {
                // 向右拖 -> 上一页
                targetPage = max(currentPage - 1, 0)
            }

            // 如果没有实际拖动（只是点击），则关闭窗口
            if abs(totalDrag) < 5 {
                onEmptyAreaClicked?()
                return
            }

            navigateToPage(targetPage, animated: true)
            return
        }

        if isDraggingItem {
            // 结束拖拽
            endDragging(at: location)
        } else if let idx = pressedIndex {
            // 恢复点击效果
            pressedIndex = nil
            animatePress(at: idx, pressed: false)

            // 检查是否在同一个 item 上释放
            if let (item, index) = itemAt(location), index == idx {
                if isBatchSelectionMode {
                    if case .app(let app) = item {
                        toggleBatchSelection(forAppPath: app.url.path)
                    }
                } else {
                    // 延迟一点点再触发，让动画效果更明显
                    DispatchQueue.main.asyncAfter(deadline: .now() + 0.05) { [weak self] in
                        self?.onItemClicked?(item, index)
                    }
                }
            }
        }
    }


    func animatePress(at index: Int, pressed: Bool) {
        _ = pressed
        let pageIndex = index / itemsPerPage
        let localIndex = index % itemsPerPage

        guard pageIndex < iconLayers.count, localIndex < iconLayers[pageIndex].count else { return }

        applyScaleForIndex(index, animated: true)
    }

    // MARK: - Drag and Drop

    func startDragging(item: LaunchpadItem, index: Int, at point: CGPoint) {
        guard !isLayoutLocked else { return }
        if isBatchSelectionMode {
            guard case .app(let app) = item else { return }
            let dragPath = app.url.path
            let orderedBatch = orderedBatchDragPaths(leadingAppPath: dragPath)
            guard !orderedBatch.isEmpty else { return }
            batchDraggingAppPathsOrdered = orderedBatch
            batchHiddenCompanionIndices = orderedBatch
                .compactMap { globalIndex(forAppPath: $0) }
                .filter { $0 != index }
        } else {
            // Allow dragging apps and folders in normal mode.
            switch item {
            case .app, .folder:
                break
            case .empty, .missingApp:
                return
            }
            batchDraggingAppPathsOrdered.removeAll()
            batchHiddenCompanionIndices.removeAll()
        }

        isDraggingItem = true
        draggingIndex = index
        draggingItem = item
        dragCurrentPoint = point

        // 恢复按压效果
        if let idx = pressedIndex {
            animatePress(at: idx, pressed: false)
            pressedIndex = nil
        }

        // 隐藏原图标
        let pageIndex = index / itemsPerPage
        let localIndex = index % itemsPerPage
        if pageIndex < iconLayers.count, localIndex < iconLayers[pageIndex].count {
            iconLayers[pageIndex][localIndex].opacity = 0
        }
        if !batchHiddenCompanionIndices.isEmpty {
            for companionIndex in batchHiddenCompanionIndices {
                setOpacity(0, forGlobalIndex: companionIndex)
            }
        }

        // 创建拖拽图层
        createDraggingLayer(for: item, at: point)

        if isBatchDragging {
            pendingHoverIndex = gridPositionAt(point)
            applyIconPositionUpdate()
        }

        // print("🎯 [CAGrid] Started dragging: \(item.name) at index \(index)")
    }

    func createDraggingLayer(for item: LaunchpadItem, at point: CGPoint) {
        let actualIconSize = iconSize
        let scale = NSScreen.main?.backingScaleFactor ?? 2.0
        
        // Container for dragging (holds glass + icon for folders)
        let container = CALayer()
        container.frame = CGRect(x: point.x - actualIconSize / 2, y: point.y - actualIconSize / 2,
                            width: actualIconSize, height: actualIconSize)
        container.transform = CATransform3DMakeScale(1.1, 1.1, 1.0)
        container.zPosition = 1000

        // For folders, add glass background
        if case .folder = item {
            let glassSize = actualIconSize * 0.8
            let glassOffset = (actualIconSize - glassSize) / 2
            let glassLayer = CALayer()
            glassLayer.frame = CGRect(x: glassOffset, y: glassOffset, width: glassSize, height: glassSize)
            glassLayer.backgroundColor = NSColor.white.withAlphaComponent(0.08).cgColor
            glassLayer.borderColor = NSColor.white.withAlphaComponent(0.2).cgColor
            glassLayer.borderWidth = 0.5
            glassLayer.cornerRadius = glassSize * 0.25
            glassLayer.shadowColor = NSColor.black.cgColor
            glassLayer.shadowOffset = CGSize(width: 0, height: -1)
            glassLayer.shadowRadius = 3
            glassLayer.shadowOpacity = 0.15
            container.addSublayer(glassLayer)
        }

        // Icon layer
        let iconLayer = CALayer()
        iconLayer.frame = CGRect(x: 0, y: 0, width: actualIconSize, height: actualIconSize)
        iconLayer.contentsScale = scale
        iconLayer.contentsGravity = .resizeAspect
        iconLayer.shadowOpacity = 0

        // Set icon content with high resolution
        if case .app(let app) = item {
            let icon = IconStore.shared.icon(forPath: app.url.path)
            let renderSize = NSSize(width: actualIconSize * scale, height: actualIconSize * scale)
            let renderedImage = NSImage(size: renderSize)
            renderedImage.lockFocus()
            icon.draw(in: NSRect(origin: .zero, size: renderSize))
            renderedImage.unlockFocus()
            if let cgImage = renderedImage.cgImage(forProposedRect: nil, context: nil, hints: nil) {
                iconLayer.contents = cgImage
            }
        } else if case .folder(let folder) = item {
            let icon = folder.icon(of: actualIconSize, scale: folderPreviewScale)
            let renderSize = NSSize(width: actualIconSize * scale, height: actualIconSize * scale)
            let renderedImage = NSImage(size: renderSize)
            renderedImage.lockFocus()
            icon.draw(in: NSRect(origin: .zero, size: renderSize))
            renderedImage.unlockFocus()
            if let cgImage = renderedImage.cgImage(forProposedRect: nil, context: nil, hints: nil) {
                iconLayer.contents = cgImage
            }
        }

        container.addSublayer(iconLayer)

        if case .app = item, batchDraggingAppPathsOrdered.count > 1 {
            addBatchDragCountBadge(to: container, count: batchDraggingAppPathsOrdered.count)
        }

        containerLayer.addSublayer(container)
        draggingLayer = container
    }

    func addBatchDragCountBadge(to container: CALayer, count: Int) {
        let badgeSize: CGFloat = 22
        let badge = CALayer()
        badge.name = "batchDragCountBadge"
        badge.frame = CGRect(x: container.bounds.width - badgeSize * 0.9,
                             y: container.bounds.height - badgeSize * 0.95,
                             width: badgeSize,
                             height: badgeSize)
        badge.cornerRadius = badgeSize * 0.5
        badge.backgroundColor = NSColor.systemBlue.cgColor
        badge.borderColor = NSColor.white.withAlphaComponent(0.85).cgColor
        badge.borderWidth = 1
        badge.zPosition = 40

        let text = CATextLayer()
        text.string = "\(count)"
        text.alignmentMode = .center
        text.font = NSFont.systemFont(ofSize: 11, weight: .bold)
        text.fontSize = 11
        text.foregroundColor = NSColor.white.cgColor
        text.contentsScale = NSScreen.main?.backingScaleFactor ?? 2
        text.frame = CGRect(x: 0, y: 4, width: badgeSize, height: badgeSize - 6)
        badge.addSublayer(text)
        container.addSublayer(badge)
    }

    func updateDragging(at point: CGPoint) {
        dragCurrentPoint = point

        // Update dragging layer position
        CATransaction.begin()
        CATransaction.setDisableActions(true)
        let actualIconSize = iconSize
        draggingLayer?.frame = CGRect(x: point.x - actualIconSize / 2, y: point.y - actualIconSize / 2,
                                      width: actualIconSize, height: actualIconSize)
        CATransaction.commit()

        // Check edge drag for page flip
        checkEdgeDrag(at: point)

        let dragPage = draggingIndex.map { $0 / itemsPerPage }
        let isCrossPage = dragPage != nil && dragPage != currentPage

        if isBatchDragging {
            if let hoverIndex = gridPositionAt(point), hoverIndex != draggingIndex {
                clearDropTargetHighlight()
                updateIconPositionsForDrag(hoverIndex: hoverIndex)
            } else {
                clearDropTargetHighlight()
                updateIconPositionsForDrag(hoverIndex: nil)
            }
            return
        }

        if let hoverIndex = gridPositionAt(point), hoverIndex != draggingIndex {
            if hoverIndex < items.count {
                let targetItem = items[hoverIndex]
                let inCenterArea = isPointInFolderDropZone(point, targetIndex: hoverIndex)

                switch targetItem {
                case .folder:
                    if case .app = draggingItem, inCenterArea {
                        // Hovering over folder center - highlight for move into folder
                        highlightDropTarget(at: hoverIndex)
                        updateIconPositionsForDrag(hoverIndex: isCrossPage ? hoverIndex : nil)
                    } else {
                        clearDropTargetHighlight()
                        updateIconPositionsForDrag(hoverIndex: hoverIndex)
                    }
                case .app:
                    if case .app = draggingItem, inCenterArea {
                        // App over app center - create folder
                        highlightDropTarget(at: hoverIndex)
                        updateIconPositionsForDrag(hoverIndex: isCrossPage ? hoverIndex : nil)
                    } else {
                        clearDropTargetHighlight()
                        updateIconPositionsForDrag(hoverIndex: hoverIndex)
                    }
                case .missingApp, .empty:
                    clearDropTargetHighlight()
                    updateIconPositionsForDrag(hoverIndex: hoverIndex)
                }
            } else {
                clearDropTargetHighlight()
                updateIconPositionsForDrag(hoverIndex: hoverIndex)
            }
        } else {
            clearDropTargetHighlight()
            updateIconPositionsForDrag(hoverIndex: nil)
        }
    }
    
    func updateIconPositionsForDrag(hoverIndex: Int?) {
        guard draggingIndex != nil else { return }
        
        // Skip if same as pending or current
        if hoverIndex == pendingHoverIndex { return }
        
        // Store pending hover index
        pendingHoverIndex = hoverIndex
        
        // Cancel previous timer
        hoverUpdateTimer?.invalidate()
        
        // Schedule delayed update to prevent jittering during fast movement
        hoverUpdateTimer = Timer.scheduledTimer(withTimeInterval: hoverUpdateDelay, repeats: false) { [weak self] _ in
            self?.applyIconPositionUpdate()
        }
    }
    
    func applyIconPositionUpdate() {
        guard let dragIndex = draggingIndex else { return }
        
        let hoverIndex = pendingHoverIndex
        
        // Batch mode always recomputes compaction so selected gaps are closed immediately.
        if !isBatchDragging, hoverIndex == currentHoverIndex { return }
        currentHoverIndex = hoverIndex
        
        // Get current page icons only
        let pageIndex = currentPage
        guard pageIndex < iconLayers.count else { return }
        let pageLayers = iconLayers[pageIndex]
        let pageStart = pageIndex * itemsPerPage

        ensureOriginalPositionsForCurrentPage(pageLayers: pageLayers, pageStart: pageStart)
        
        if isBatchDragging {
            applyBatchCompactedPositions(pageLayers: pageLayers, pageStart: pageStart, dragIndex: dragIndex)
            return
        }
        
        // Calculate positions with item shifted - smooth spring-like animation
        CATransaction.begin()
        CATransaction.setAnimationDuration(0.45)
        CATransaction.setAnimationTimingFunction(CAMediaTimingFunction(controlPoints: 0.25, 1.0, 0.35, 1.0))
        
        for (localIndex, layer) in pageLayers.enumerated() {
            let globalIndex = pageStart + localIndex
            
            // Skip the dragging item's original layer - hide it completely
            if globalIndex == dragIndex {
                layer.opacity = 0
                continue
            }
            
            guard let originalPos = originalIconPositions[globalIndex] else { continue }
            
            var targetPos = originalPos
            
            if let hover = hoverIndex {
                let hoverLocalIndex = hover - pageStart
                let dragLocalIndex = dragIndex - pageStart
                let dragInThisPage = dragIndex >= pageStart && dragIndex < pageStart + itemsPerPage
                
                // Only affect items on current page
                if hover >= pageStart && hover < pageStart + itemsPerPage {
                    
                    if dragInThisPage {
                        if dragLocalIndex < hoverLocalIndex {
                            // Dragging forward: items between drag and hover shift left
                            if localIndex > dragLocalIndex && localIndex <= hoverLocalIndex {
                                if let prevPos = originalIconPositions[pageStart + localIndex - 1] {
                                    targetPos = prevPos
                                }
                            }
                        } else if dragLocalIndex > hoverLocalIndex {
                            // Dragging backward: items between hover and drag shift right
                            if localIndex >= hoverLocalIndex && localIndex < dragLocalIndex {
                                if let nextPos = originalIconPositions[pageStart + localIndex + 1] {
                                    targetPos = nextPos
                                }
                            }
                        }
                    } else {
                        // Dragging from another page: create a gap on the hover page by shifting items to the right.
                        if localIndex >= hoverLocalIndex {
                            let targetGlobalIndex = pageStart + localIndex + 1
                            targetPos = gridCenterForGlobalIndex(targetGlobalIndex)
                        }
                    }
                }
            }
            
            layer.position = targetPos
        }
        
        CATransaction.commit()
    }

    func applyBatchCompactedPositions(pageLayers: [CALayer], pageStart: Int, dragIndex: Int) {
        let pageEnd = pageStart + pageLayers.count
        let removedIndices = Set(batchHiddenCompanionIndices + [dragIndex]).filter { $0 >= pageStart && $0 < pageEnd }
        let removedLocals = Set(removedIndices.map { $0 - pageStart })

        var nonEmptyLocals: [Int] = []
        var emptyLocals: [Int] = []
        for localIndex in 0..<pageLayers.count {
            guard !removedLocals.contains(localIndex) else { continue }
            let globalIndex = pageStart + localIndex
            if globalIndex < items.count, case .empty = items[globalIndex] {
                emptyLocals.append(localIndex)
            } else {
                nonEmptyLocals.append(localIndex)
            }
        }
        let compactedLocals = nonEmptyLocals + emptyLocals

        CATransaction.begin()
        CATransaction.setAnimationDuration(0.25)
        CATransaction.setAnimationTimingFunction(CAMediaTimingFunction(controlPoints: 0.25, 0.9, 0.35, 1.0))

        for (targetLocalIndex, sourceLocalIndex) in compactedLocals.enumerated() {
            let layer = pageLayers[sourceLocalIndex]
            let targetGlobalIndex = pageStart + targetLocalIndex
            let targetPosition = originalIconPositions[targetGlobalIndex] ?? gridCenterForGlobalIndex(targetGlobalIndex)
            layer.position = targetPosition
            layer.opacity = 1
        }

        for removedLocalIndex in removedLocals {
            pageLayers[removedLocalIndex].opacity = 0
        }

        CATransaction.commit()
    }

    func gridCenterForGlobalIndex(_ globalIndex: Int) -> CGPoint {
        guard bounds.width > 0, bounds.height > 0 else { return .zero }

        let pageWidth = bounds.width
        let pageHeight = bounds.height
        let pageStride = pageWidth + pageSpacing
        let pageIndex = max(0, globalIndex / itemsPerPage)
        let localIndex = max(0, globalIndex % itemsPerPage)

        let availableWidth = max(0, pageWidth - contentInsets.left - contentInsets.right)
        let availableHeight = max(0, pageHeight - contentInsets.top - contentInsets.bottom)
        let totalColumnSpacing = columnSpacing * CGFloat(max(columns - 1, 0))
        let totalRowSpacing = rowSpacing * CGFloat(max(rows - 1, 0))
        let usableWidth = max(0, availableWidth - totalColumnSpacing)
        let usableHeight = max(0, availableHeight - totalRowSpacing)
        let cellWidth = usableWidth / CGFloat(max(columns, 1))
        let cellHeight = usableHeight / CGFloat(max(rows, 1))
        let strideX = cellWidth + columnSpacing

        let col = localIndex % columns
        let row = localIndex / columns

        let cellOriginX = contentInsets.left + CGFloat(col) * strideX
        let cellOriginY = pageHeight - contentInsets.top - CGFloat(row + 1) * cellHeight - CGFloat(row) * rowSpacing

        let actualIconSize = iconSize
        let labelHeight: CGFloat = labelFontSize + 8
        let labelTopSpacing: CGFloat = 6
        let totalHeight = actualIconSize + labelTopSpacing + labelHeight

        let containerX = CGFloat(pageIndex) * pageStride + cellOriginX
        let containerY = cellOriginY + (cellHeight - totalHeight) / 2
        return CGPoint(x: containerX + cellWidth / 2, y: containerY + totalHeight / 2)
    }
    
    func resetIconPositions() {
        // Cancel pending update timer
        hoverUpdateTimer?.invalidate()
        hoverUpdateTimer = nil
        pendingHoverIndex = nil
        
        guard !originalIconPositions.isEmpty else { 
            // Even if we never captured original positions, make sure the hidden drag source is restored
            if let dragIndex = draggingIndex {
                let pageIndex = dragIndex / itemsPerPage
                let localIndex = dragIndex % itemsPerPage
                if pageIndex < iconLayers.count, localIndex < iconLayers[pageIndex].count {
                    iconLayers[pageIndex][localIndex].opacity = 1.0
                }
            }
            currentHoverIndex = nil
            return 
        }
        
        CATransaction.begin()
        CATransaction.setAnimationDuration(0.3)
        CATransaction.setAnimationTimingFunction(CAMediaTimingFunction(controlPoints: 0.25, 0.1, 0.25, 1.0))
        
        for (pageIndex, pageLayers) in iconLayers.enumerated() {
            let pageStart = pageIndex * itemsPerPage
            for (localIndex, layer) in pageLayers.enumerated() {
                let globalIndex = pageStart + localIndex
                if let originalPos = originalIconPositions[globalIndex] {
                    layer.position = originalPos
                }
                layer.opacity = 1.0
            }
        }
        
        CATransaction.commit()
        
        originalIconPositions.removeAll()
        currentHoverIndex = nil
    }

    func updateHoverIndex(_ newIndex: Int?) {
        guard hoveredIndex != newIndex else { return }
        let old = hoveredIndex
        hoveredIndex = newIndex
        if let old = old {
            applyScaleForIndex(old, animated: true)
        }
        if let newIndex = newIndex {
            applyScaleForIndex(newIndex, animated: true)
        }
    }

    func clearHover() {
        updateHoverIndex(nil)
    }

    func updateLabelFonts() {
        CATransaction.begin()
        CATransaction.setDisableActions(true)
        for pageLayers in iconLayers {
            for containerLayer in pageLayers {
                if let textLayer = containerLayer.sublayers?.first(where: { $0.name == "label" }) as? CATextLayer {
                    textLayer.font = NSFont.systemFont(ofSize: labelFontSize, weight: labelFontWeight)
                    textLayer.fontSize = labelFontSize
                }
            }
        }
        CATransaction.commit()
    }

    func updateLabelVisibility() {
        CATransaction.begin()
        CATransaction.setDisableActions(true)
        for pageLayers in iconLayers {
            for containerLayer in pageLayers {
                if let textLayer = containerLayer.sublayers?.first(where: { $0.name == "label" }) as? CATextLayer {
                    textLayer.isHidden = !showLabels
                }
            }
        }
        CATransaction.commit()
        updateLayout()
    }

    func updateLabelColors() {
        let resolvedColor = currentLabelColor().cgColor
        CATransaction.begin()
        CATransaction.setDisableActions(true)
        for pageLayers in iconLayers {
            for containerLayer in pageLayers {
                if let textLayer = containerLayer.sublayers?.first(where: { $0.name == "label" }) as? CATextLayer {
                    textLayer.foregroundColor = resolvedColor
                }
            }
        }
        CATransaction.commit()
    }

    func updateFolderGlassColors() {
        let colors = currentFolderGlassStyle()
        CATransaction.begin()
        CATransaction.setDisableActions(true)
        for pageLayers in iconLayers {
            for containerLayer in pageLayers {
                if let glassLayer = containerLayer.sublayers?.first(where: { $0.name == "glass" }) {
                    glassLayer.backgroundColor = colors.background.cgColor
                    glassLayer.borderColor = colors.border.cgColor
                    glassLayer.shadowOffset = colors.shadowOffset
                    glassLayer.shadowRadius = colors.shadowRadius
                    glassLayer.shadowOpacity = colors.shadowOpacity
                }
            }
        }
        CATransaction.commit()
    }

    func currentLabelColor() -> NSColor {
        let match = effectiveAppearance.bestMatch(from: [.darkAqua, .aqua])
        return match == .darkAqua ? .white : .black
    }

    func isPointInFolderDropZone(_ point: CGPoint, targetIndex: Int) -> Bool {
        guard let center = iconCenter(for: targetIndex) else { return false }
        let size = iconSize * folderDropZoneScale
        let rect = CGRect(x: center.x - size / 2,
                          y: center.y - size / 2,
                          width: size,
                          height: size)
        return rect.contains(point)
    }

    func iconCenter(for index: Int) -> CGPoint? {
        guard bounds.width > 0, bounds.height > 0 else { return nil }
        let pageIndex = index / itemsPerPage
        let localIndex = index % itemsPerPage
        guard pageIndex >= 0 && pageIndex < pageCount else { return nil }

        let pageWidth = bounds.width
        let pageHeight = bounds.height
        let pageStride = pageWidth + pageSpacing

        let availableWidth = max(0, pageWidth - contentInsets.left - contentInsets.right)
        let availableHeight = max(0, pageHeight - contentInsets.top - contentInsets.bottom)
        let totalColumnSpacing = columnSpacing * CGFloat(max(columns - 1, 0))
        let totalRowSpacing = rowSpacing * CGFloat(max(rows - 1, 0))
        let usableWidth = max(0, availableWidth - totalColumnSpacing)
        let usableHeight = max(0, availableHeight - totalRowSpacing)
        let cellWidth = usableWidth / CGFloat(max(columns, 1))
        let cellHeight = usableHeight / CGFloat(max(rows, 1))
        let strideX = cellWidth + columnSpacing

        let col = localIndex % columns
        let row = localIndex / columns

        let cellOriginX = contentInsets.left + CGFloat(col) * strideX
        let cellOriginY = pageHeight - contentInsets.top - CGFloat(row + 1) * cellHeight - CGFloat(row) * rowSpacing

        let labelHeight: CGFloat = showLabels ? (labelFontSize + 8) : 0
        let labelTopSpacing: CGFloat = showLabels ? 6 : 0
        let totalHeight = iconSize + labelTopSpacing + labelHeight

        let containerX = CGFloat(pageIndex) * pageStride + cellOriginX
        let containerY = cellOriginY + (cellHeight - totalHeight) / 2

        let iconX = containerX + (cellWidth - iconSize) / 2
        let iconY = containerY + labelHeight + labelTopSpacing

        let centerX = iconX + iconSize / 2 + scrollOffset
        let centerY = iconY + iconSize / 2
        return CGPoint(x: centerX, y: centerY)
    }

    func currentFolderGlassStyle() -> (background: NSColor, border: NSColor, shadowOpacity: Float, shadowRadius: CGFloat, shadowOffset: CGSize) {
        let match = effectiveAppearance.bestMatch(from: [.darkAqua, .aqua])
        if match == .darkAqua {
            return (NSColor.white.withAlphaComponent(0.08),
                    NSColor.white.withAlphaComponent(0.2),
                    0.15,
                    3,
                    CGSize(width: 0, height: -1))
        }
        return (NSColor.white.withAlphaComponent(0.7),
                NSColor.white.withAlphaComponent(0.75),
                0.2,
                4,
                CGSize(width: 0, height: -1))
    }

    func applyScaleForIndex(_ index: Int, animated: Bool) {
        let pageIndex = index / itemsPerPage
        let localIndex = index % itemsPerPage
        guard pageIndex < iconLayers.count, localIndex < iconLayers[pageIndex].count else { return }

        let containerLayer = iconLayers[pageIndex][localIndex]

        let pressScale: CGFloat = (pressedIndex == index && activePressEffectEnabled) ? CGFloat(activePressScale) : 1.0

        let selectionScale: CGFloat = 1.2
        var iconScale: CGFloat = 1.0
        if dropTargetIndex == index {
            iconScale = 1.1
        } else if selectedIndex == index {
            iconScale = selectionScale
        } else if hoverMagnificationEnabled, hoveredIndex == index {
            iconScale = hoverMagnificationScale
        }

        CATransaction.begin()
        CATransaction.setAnimationDuration(animated ? 0.12 : 0)
        CATransaction.setAnimationTimingFunction(CAMediaTimingFunction(name: .easeOut))
        containerLayer.transform = CATransform3DMakeScale(pressScale, pressScale, 1.0)

        if let iconLayer = containerLayer.sublayers?.first(where: { $0.name == "icon" }) {
            iconLayer.transform = CATransform3DMakeScale(iconScale, iconScale, 1.0)
        }
        if let glassLayer = containerLayer.sublayers?.first(where: { $0.name == "glass" }) {
            glassLayer.transform = CATransform3DMakeScale(iconScale, iconScale, 1.0)
        }
        CATransaction.commit()
    }

    func updateSelection(_ index: Int?, animated: Bool = true) {
        let clampedIndex: Int? = {
            guard let index else { return nil }
            guard index >= 0, index < items.count else { return nil }
            if case .empty = items[index] { return nil }
            return index
        }()

        guard selectedIndex != clampedIndex else { return }
        let old = selectedIndex
        selectedIndex = clampedIndex
        if let old = old { applyScaleForIndex(old, animated: animated) }
        if let newIndex = selectedIndex { applyScaleForIndex(newIndex, animated: animated) }
    }

    func updateExternalDragState(sourceIndex: Int?, hoverIndex: Int?) {
        // Avoid interfering with native CA drag.
        guard !isDraggingItem else { return }
        guard bounds.width > 0, bounds.height > 0 else { return }

        if let sourceIndex = sourceIndex {
            if !externalDragActive || draggingIndex != sourceIndex {
                externalDragActive = true
                draggingIndex = sourceIndex

                let pageIndex = sourceIndex / itemsPerPage
                let localIndex = sourceIndex % itemsPerPage
                if pageIndex < iconLayers.count, localIndex < iconLayers[pageIndex].count {
                    iconLayers[pageIndex][localIndex].opacity = 0
                }
            }
            updateIconPositionsForDrag(hoverIndex: hoverIndex)
        } else if externalDragActive {
            externalDragActive = false
            draggingIndex = nil
            resetIconPositions()
        }
    }

    func ensureOriginalPositionsForCurrentPage(pageLayers: [CALayer], pageStart: Int) {
        // If we already captured positions for this page, keep them.
        var hasAny = false
        for localIndex in 0..<pageLayers.count {
            let globalIndex = pageStart + localIndex
            if originalIconPositions[globalIndex] != nil {
                hasAny = true
                break
            }
        }
        guard !hasAny else { return }

        for (localIndex, layer) in pageLayers.enumerated() {
            let globalIndex = pageStart + localIndex
            originalIconPositions[globalIndex] = layer.position
        }
    }

    // MARK: - 边缘翻页检测
    func checkEdgeDrag(at point: CGPoint) {
        let leftEdge = point.x < edgeDragThreshold
        let rightEdge = point.x > bounds.width - edgeDragThreshold

        if leftEdge && currentPage > 0 {
            // 左边缘 - 翻到上一页
            startEdgeDragTimer(direction: -1)
        } else if rightEdge {
            // 右边缘 - 翻到下一页（可能创建新页）
            startEdgeDragTimer(direction: 1)
        } else {
            // 离开边缘区域 - 取消计时器
            cancelEdgeDragTimer()
        }
    }

    func startEdgeDragTimer(direction: Int) {
        // 如果已有相同方向的计时器，不重复创建
        if edgeDragTimer != nil { return }

        let timer = Timer(timeInterval: edgeDragDelay, repeats: false) { [weak self] _ in
            guard let self = self else { return }
            let targetPage = self.currentPage + direction

            // 检查是否需要创建新页面
            if direction > 0 && targetPage >= self.pageCount {
                // 通知创建新页面
                self.onRequestNewPage?()
            }

            self.navigateToPage(targetPage, animated: true)
            self.edgeDragTimer = nil

            // 翻页后继续检测
            DispatchQueue.main.asyncAfter(deadline: .now() + 0.2) { [weak self] in
                guard let self = self, self.isDraggingItem else { return }
                self.checkEdgeDrag(at: self.dragCurrentPoint)
            }
        }
        RunLoop.main.add(timer, forMode: .common)
        edgeDragTimer = timer
    }

    func cancelEdgeDragTimer() {
        edgeDragTimer?.invalidate()
        edgeDragTimer = nil
    }

    func hardSnapToCurrentPage() {
        guard bounds.width > 0 else { return }
        resetScrollInteractionState()
        isScrollAnimating = false
        scrollAnimationStartTime = 0
        let expectedOffset = -CGFloat(currentPage) * (bounds.width + pageSpacing)
        scrollOffset = expectedOffset
        targetScrollOffset = expectedOffset
        CATransaction.begin()
        CATransaction.setDisableActions(true)
        CATransaction.setAnimationDuration(0)
        pageContainerLayer.transform = CATransform3DMakeTranslation(scrollOffset, 0, 0)
        CATransaction.commit()
    }

    func resetScrollInteractionState() {
        isDragging = false
        accumulatedDelta = 0
        wheelAccumulatedDelta = 0
        wheelLastDirection = 0
        wheelLastFlipAt = nil
    }

    /// 计算点击位置对应的网格位置（即使是空白区域）
    func gridPositionAt(_ point: CGPoint) -> Int? {
        let pageWidth = bounds.width
        let pageHeight = bounds.height
        let adjustedX = point.x - scrollOffset

        // 计算点击的页面
        let pageStride = pageWidth + pageSpacing
        let pageIndex = Int(floor(adjustedX / pageStride))
        guard pageIndex >= 0 else { return nil }
        // 允许拖拽到最后一页之后（会创建新页）
        let effectivePageIndex = min(pageIndex, max(0, pageCount - 1))

        let availableWidth = max(0, pageWidth - contentInsets.left - contentInsets.right)
        let availableHeight = max(0, pageHeight - contentInsets.top - contentInsets.bottom)
        let totalColumnSpacing = columnSpacing * CGFloat(max(columns - 1, 0))
        let totalRowSpacing = rowSpacing * CGFloat(max(rows - 1, 0))
        let usableWidth = max(0, availableWidth - totalColumnSpacing)
        let usableHeight = max(0, availableHeight - totalRowSpacing)
        let cellWidth = usableWidth / CGFloat(max(columns, 1))
        let cellHeight = usableHeight / CGFloat(max(rows, 1))
        let strideX = cellWidth + columnSpacing
        let strideY = cellHeight + rowSpacing

        // 计算点击位置相对于当前页的坐标
        let pageX = adjustedX - CGFloat(effectivePageIndex) * pageStride
        guard pageX >= 0, pageX <= pageWidth else { return nil }
        let localX = pageX - contentInsets.left
        let localY = pageHeight - point.y - contentInsets.top

        // 钳制到有效范围
        let clampedX = max(0, min(localX, availableWidth - 1))
        let clampedY = max(0, min(localY, availableHeight - 1))

        let col = Int(clampedX / strideX)
        let row = Int(clampedY / strideY)

        let clampedCol = max(0, min(col, columns - 1))
        let clampedRow = max(0, min(row, rows - 1))

        let localIndex = clampedRow * columns + clampedCol
        let globalIndex = effectivePageIndex * itemsPerPage + localIndex

        return globalIndex
    }

    func highlightDropTarget(at index: Int) {
        // 清除之前的高亮
        if let oldTarget = dropTargetIndex, oldTarget != index {
            dropTargetIndex = nil
            applyScaleForIndex(oldTarget, animated: true)
        }

        dropTargetIndex = index
        applyScaleForIndex(index, animated: true)
    }

    func clearDropTargetHighlight() {
        if let target = dropTargetIndex {
            dropTargetIndex = nil
            applyScaleForIndex(target, animated: true)
        }
    }

    func setHighlight(at index: Int, highlighted _: Bool) {
        applyScaleForIndex(index, animated: true)
    }

    func endDragging(at point: CGPoint) {
        guard let dragIndex = draggingIndex, let dragItem = draggingItem else {
            cancelDragging()
            return
        }

        // Save current hover position before clearing
        let savedHoverIndex = currentHoverIndex

        // Clear highlights and reset
        clearDropTargetHighlight()
        cancelEdgeDragTimer()

        // Calculate target position
        let targetPosition = gridPositionAt(point)

        // Track if we're doing a reorder (so we don't reset positions unnecessarily)
        var didReorder = false

        if isBatchDragging {
            if let insertIndex = savedHoverIndex ?? targetPosition {
                let clampedIndex = max(0, min(insertIndex, items.count))
                let singleDragNoop = batchDraggingAppPathsOrdered.count == 1 && clampedIndex == dragIndex
                if !singleDragNoop {
                    onReorderAppBatch?(batchDraggingAppPathsOrdered, clampedIndex)
                    didReorder = true
                }
            }
        } else {
            // 检查是否拖到另一个item上
            if let (targetItem, targetIndex) = itemAt(point), targetIndex != dragIndex {
                // print("🎯 [CAGrid] Dropped on item: \(targetItem.name) at index \(targetIndex)")
                // 拖拽到另一个 item 上
                if case .app(let dragApp) = dragItem {
                    switch targetItem {
                    case .app(let targetApp):
                        // 两个应用 -> 创建文件夹
                        // print("📁 [CAGrid] Creating folder: \(dragApp.name) + \(targetApp.name)")
                        onCreateFolder?(dragApp, targetApp, targetIndex)
                        cancelDragging()
                        return
                    case .folder(let folder):
                        // 拖到文件夹 -> 移入文件夹
                        // print("📂 [CAGrid] Moving to folder: \(dragApp.name) -> \(folder.name)")
                        onMoveToFolder?(dragApp, folder)
                        cancelDragging()
                        return
                    case .empty, .missingApp:
                        // 空白格子或丢失的应用 -> 当作重排序处理
                        // print("🔄 [CAGrid] Dropped on empty/missing, reordering: \(dragIndex) -> \(targetIndex)")
                        onReorderItems?(dragIndex, targetIndex)
                        didReorder = true
                    }
                }
            }

            // Reorder to empty area - use saved hover position or calculated position
            if !didReorder, let insertIndex = savedHoverIndex ?? targetPosition, insertIndex != dragIndex {
                onReorderItems?(dragIndex, insertIndex)
                didReorder = true
            }
        }

        // If we did a reorder, data will update and rebuild layers
        // Delay clearing dragging state to avoid visual glitches during rebuild
        if didReorder {
            // Save drag index before clearing
            let savedDragIndex = draggingIndex
            
            // Remove dragging layer immediately
            draggingLayer?.removeFromSuperlayer()
            draggingLayer = nil
            
            // Clear dragging flags immediately
            isDraggingItem = false
            dropTargetIndex = nil
            
            // Cancel pending updates
            hoverUpdateTimer?.invalidate()
            hoverUpdateTimer = nil
            pendingHoverIndex = nil
            currentHoverIndex = nil
            
            // Delay clearing other state to let data update complete
            DispatchQueue.main.async { [weak self] in
                guard let self = self else { return }
                self.draggingIndex = nil
                self.draggingItem = nil
                self.originalIconPositions.removeAll()
                
                // Restore opacity of dragged item (if layers still exist)
                if let dragIndex = savedDragIndex {
                    let pageIndex = dragIndex / self.itemsPerPage
                    let localIndex = dragIndex % self.itemsPerPage
                    if pageIndex < self.iconLayers.count, localIndex < self.iconLayers[pageIndex].count {
                        self.iconLayers[pageIndex][localIndex].opacity = 1.0
                    }
                }
                self.restoreBatchHiddenCompanionLayers()
                if self.isBatchSelectionMode {
                    self.disableBatchSelectionMode()
                }
                self.forceSyncPageTransformIfNeeded()
            }
        } else {
            // No reorder happened, reset positions to original
            cancelDragging()
        }
        hardSnapToCurrentPage()
        logIfMismatch("endDragging")
    }

    func cancelDragging() {
        // Reset icon positions to original
        resetIconPositions()

        // Remove dragging layer
        draggingLayer?.removeFromSuperlayer()
        draggingLayer = nil

        isDraggingItem = false
        draggingIndex = nil
        draggingItem = nil
        dropTargetIndex = nil
        restoreBatchHiddenCompanionLayers()
        hardSnapToCurrentPage()
        logIfMismatch("cancelDragging")
    }

    func itemAt(_ point: CGPoint) -> (LaunchpadItem, Int)? {
        let pageWidth = bounds.width
        let pageHeight = bounds.height
        let adjustedX = point.x - scrollOffset

        // 计算点击的页面
        let pageStride = pageWidth + pageSpacing
        let pageIndex = Int(floor(adjustedX / pageStride))
        guard pageIndex >= 0 && pageIndex < pageCount else { return nil }

        let availableWidth = max(0, pageWidth - contentInsets.left - contentInsets.right)
        let availableHeight = max(0, pageHeight - contentInsets.top - contentInsets.bottom)
        let totalColumnSpacing = columnSpacing * CGFloat(max(columns - 1, 0))
        let totalRowSpacing = rowSpacing * CGFloat(max(rows - 1, 0))
        let usableWidth = max(0, availableWidth - totalColumnSpacing)
        let usableHeight = max(0, availableHeight - totalRowSpacing)
        let cellWidth = usableWidth / CGFloat(max(columns, 1))
        let cellHeight = usableHeight / CGFloat(max(rows, 1))
        let strideX = cellWidth + columnSpacing
        let strideY = cellHeight + rowSpacing

        // 计算点击位置相对于当前页的坐标
        let pageX = adjustedX - CGFloat(pageIndex) * pageStride
        guard pageX >= 0, pageX <= pageWidth else { return nil }
        let localX = pageX - contentInsets.left
        let localY = pageHeight - point.y - contentInsets.top

        guard localX >= 0, localY >= 0 else { return nil }
        guard localX < availableWidth, localY < availableHeight else { return nil }

        let col = Int(localX / strideX)
        let row = Int(localY / strideY)

        guard col >= 0, col < columns, row >= 0, row < rows else { return nil }

        let cellOriginX = CGFloat(col) * strideX
        let cellOriginY = CGFloat(row) * strideY
        let cellLocalX = localX - cellOriginX
        let cellLocalY = localY - cellOriginY

        guard cellLocalX >= 0, cellLocalX <= cellWidth else { return nil }
        guard cellLocalY >= 0, cellLocalY <= cellHeight else { return nil }

        let localIndex = row * columns + col
        let globalIndex = pageIndex * itemsPerPage + localIndex

        guard globalIndex < items.count else { return nil }

        // 检查是否点击在图标+标签区域内（不是单元格的空白部分）
        let actualIconSize = iconSize
        let labelHeight: CGFloat = showLabels ? (labelFontSize + 8) : 0
        let labelTopSpacing: CGFloat = showLabels ? 6 : 0
        let totalItemHeight = actualIconSize + labelTopSpacing + labelHeight

        // 图标+标签区域居中于单元格
        let itemStartX = (cellWidth - actualIconSize) / 2
        let itemEndX = itemStartX + actualIconSize
        let itemStartY = (cellHeight - totalItemHeight) / 2
        let itemEndY = itemStartY + totalItemHeight

        // 检查是否在图标+标签区域内
        guard cellLocalX >= itemStartX && cellLocalX <= itemEndX else { return nil }
        guard cellLocalY >= itemStartY && cellLocalY <= itemEndY else { return nil }

        return (items[globalIndex], globalIndex)
    }

}
