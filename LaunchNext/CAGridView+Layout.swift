import AppKit
import QuartzCore

extension CAGridView {
    // MARK: - Layer Management

    func rebuildLayers() {
        CATransaction.begin()
        CATransaction.setDisableActions(true)

        // 清除旧层
        for pageLayers in iconLayers {
            for layer in pageLayers {
                layer.removeFromSuperlayer()
            }
        }
        iconLayers.removeAll()

        guard !items.isEmpty else {
            CATransaction.commit()
            // print("⚠️ [CAGrid] rebuildLayers: no items")
            return
        }

        // 为每页创建图层
        let totalPages = pageCount
        // print("🔧 [CAGrid] rebuildLayers: \(items.count) items, \(totalPages) pages, \(itemsPerPage) per page")

        for pageIndex in 0..<totalPages {
            var pageLayers: [CALayer] = []
            let startIndex = pageIndex * itemsPerPage
            let endIndex = min(startIndex + itemsPerPage, items.count)

            for i in startIndex..<endIndex {
                let localIndex = i - startIndex
                let layer = createIconLayer(for: items[i], localIndex: localIndex, pageIndex: pageIndex)
                pageContainerLayer.addSublayer(layer)
                pageLayers.append(layer)
            }

            iconLayers.append(pageLayers)
        }

        CATransaction.commit()

        // Update layout if bounds are ready, otherwise layout() will handle it later
        if bounds.width > 0 && bounds.height > 0 {
            updateLayout()
        }

        // Navigate to current page (will be handled by layout() if bounds not ready)
        navigateToPage(currentPage, animated: false)
        logIfMismatch("rebuildLayers")
    }
    
    // Track if layout needs refresh after bounds become valid

    func createIconLayer(for item: LaunchpadItem, localIndex: Int, pageIndex: Int) -> CALayer {
        _ = localIndex
        _ = pageIndex
        let containerLayer = CALayer()
        containerLayer.masksToBounds = false
        containerLayer.drawsAsynchronously = true

        // For folders, add a glass background layer
        if case .folder = item {
            let glassLayer = CALayer()
            glassLayer.name = "glass"
            let glassStyle = currentFolderGlassStyle()
            glassLayer.backgroundColor = glassStyle.background.cgColor
            glassLayer.borderColor = glassStyle.border.cgColor
            glassLayer.borderWidth = 0.5
            glassLayer.masksToBounds = false
            // Subtle shadow
            glassLayer.shadowColor = NSColor.black.cgColor
            glassLayer.shadowOffset = glassStyle.shadowOffset
            glassLayer.shadowRadius = glassStyle.shadowRadius
            glassLayer.shadowOpacity = glassStyle.shadowOpacity
            containerLayer.addSublayer(glassLayer)
        }

        // Icon layer
        let iconLayer = CALayer()
        iconLayer.name = "icon"
        iconLayer.contentsGravity = .resizeAspect
        iconLayer.contentsScale = NSScreen.main?.backingScaleFactor ?? 2.0
        iconLayer.masksToBounds = false
        iconLayer.shouldRasterize = true
        iconLayer.rasterizationScale = NSScreen.main?.backingScaleFactor ?? 2.0
        iconLayer.drawsAsynchronously = true
        iconLayer.shadowOpacity = 0

        containerLayer.addSublayer(iconLayer)

        // 文字标签层 - 匹配原 SwiftUI 样式
        let textLayer = CATextLayer()
        textLayer.name = "label"
        textLayer.contentsScale = NSScreen.main?.backingScaleFactor ?? 2.0
        textLayer.fontSize = labelFontSize
        textLayer.font = NSFont.systemFont(ofSize: labelFontSize, weight: labelFontWeight)
        textLayer.isHidden = !showLabels
        textLayer.alignmentMode = .center
        textLayer.truncationMode = .end
        textLayer.isWrapped = false

        // 性能优化：栅格化文字层
        textLayer.shouldRasterize = true
        textLayer.rasterizationScale = NSScreen.main?.backingScaleFactor ?? 2.0

        // Match system label color for light/dark
        textLayer.foregroundColor = currentLabelColor().cgColor
        textLayer.shadowOpacity = 0

        // 设置文字内容
        switch item {
        case .app(let app):
            textLayer.string = app.name
        case .folder(let folder):
            textLayer.string = folder.name
        case .missingApp(let placeholder):
            textLayer.string = placeholder.displayName
        case .empty:
            textLayer.string = ""
        }

        containerLayer.addSublayer(textLayer)

        // 设置图标
        setIcon(for: iconLayer, item: item)

        if case .app = item {
            let checkboxLayer = CALayer()
            checkboxLayer.name = "batchSelectionCheckbox"
            checkboxLayer.isHidden = true
            checkboxLayer.cornerRadius = 8
            checkboxLayer.borderWidth = 1.25
            checkboxLayer.zPosition = 20
            checkboxLayer.contentsScale = NSScreen.main?.backingScaleFactor ?? 2.0

            let markLayer = CAShapeLayer()
            markLayer.name = "batchSelectionCheckboxMark"
            markLayer.fillColor = NSColor.clear.cgColor
            markLayer.strokeColor = NSColor.white.cgColor
            markLayer.lineCap = .round
            markLayer.lineJoin = .round
            markLayer.contentsScale = NSScreen.main?.backingScaleFactor ?? 2.0
            checkboxLayer.addSublayer(markLayer)
            containerLayer.addSublayer(checkboxLayer)
        }

        return containerLayer
    }

    func setIcon(for layer: CALayer, item: LaunchpadItem) {
        switch item {
        case .app(let app):
            let path = app.url.path
            layer.setValue(path, forKey: "iconPath")
            if let cgImage = getCachedIcon(for: app.url.path) {
                layer.contents = cgImage
            } else {
                // 异步加载 - 直接从系统获取图标
                DispatchQueue.global(qos: .userInitiated).async { [weak self, weak layer] in
                    guard let self = self, let layer = layer else { return }
                    guard layer.value(forKey: "iconPath") as? String == path else { return }
                    // 使用 IconStore 获取图标（CA 模式走 Next Engine 逻辑）
                    let icon = IconStore.shared.icon(forPath: path)
                    if let cgImage = self.loadIcon(for: path, icon: icon) {
                        DispatchQueue.main.async {
                            guard layer.value(forKey: "iconPath") as? String == path else { return }
                            CATransaction.begin()
                            CATransaction.setDisableActions(true)
                            layer.contents = cgImage
                            CATransaction.commit()
                        }
                    }
                }
            }
        case .folder(let folder):
            // 异步加载文件夹图标
            let folderIconSize = iconSize
            let previewScale = folderPreviewScale
            DispatchQueue.global(qos: .userInitiated).async { [weak layer] in
                let icon = folder.icon(of: folderIconSize, scale: previewScale)
                if let cgImage = icon.cgImage(forProposedRect: nil, context: nil, hints: nil) {
                    DispatchQueue.main.async {
                        CATransaction.begin()
                        CATransaction.setDisableActions(true)
                        layer?.contents = cgImage
                        CATransaction.commit()
                    }
                }
            }
        case .missingApp(let placeholder):
            if let cgImage = placeholder.icon.cgImage(forProposedRect: nil, context: nil, hints: nil) {
                layer.contents = cgImage
            }
        case .empty:
            layer.contents = nil
        }
    }

    func getCachedIcon(for path: String) -> CGImage? {
        iconCacheLock.lock()
        defer { iconCacheLock.unlock() }
        return iconCache[path]
    }

    func loadIcon(for path: String, icon: NSImage) -> CGImage? {
        iconCacheLock.lock()
        if let cached = iconCache[path] {
            iconCacheLock.unlock()
            return cached
        }
        iconCacheLock.unlock()

        // 渲染为 CGImage
        let size = NSSize(width: iconSize * 2, height: iconSize * 2) // Retina
        let image = NSImage(size: size)
        image.lockFocus()
        icon.draw(in: NSRect(origin: .zero, size: size))
        image.unlockFocus()

        guard let cgImage = image.cgImage(forProposedRect: nil, context: nil, hints: nil) else {
            return nil
        }

        iconCacheLock.lock()
        iconCache[path] = cgImage
        iconCacheLock.unlock()

        return cgImage
    }

    func preloadIcons() {
        guard enableIconPreload else { return }
        DispatchQueue.global(qos: .userInitiated).async { [weak self] in
            guard let self = self else { return }
            for item in self.items {
                if case .app(let app) = item {
                    let icon = IconStore.shared.icon(forPath: app.url.path)
                    _ = self.loadIcon(for: app.url.path, icon: icon)
                }
            }
            // print("✅ [CAGrid] Icons preloaded")
        }
    }

    // MARK: - Layout

    func updateLayout() {
        guard bounds.width > 0, bounds.height > 0 else { return }

        CATransaction.begin()
        CATransaction.setDisableActions(true)

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

        let actualIconSize = iconSize
        let labelHeight: CGFloat = showLabels ? (labelFontSize + 8) : 0
        let labelTopSpacing: CGFloat = showLabels ? 6 : 0

        for (pageIndex, pageLayers) in iconLayers.enumerated() {
            for (localIndex, containerLayer) in pageLayers.enumerated() {
                let col = localIndex % columns
                let row = localIndex / columns

                let cellOriginX = contentInsets.left + CGFloat(col) * strideX
                let cellOriginY = pageHeight - contentInsets.top - CGFloat(row + 1) * cellHeight - CGFloat(row) * rowSpacing

                let totalHeight = actualIconSize + labelTopSpacing + labelHeight
                let containerX = CGFloat(pageIndex) * pageStride + cellOriginX
                let containerY = cellOriginY + (cellHeight - totalHeight) / 2

                containerLayer.frame = CGRect(x: containerX, y: containerY, width: cellWidth, height: totalHeight)

                if let iconLayer = containerLayer.sublayers?.first(where: { $0.name == "icon" }) {
                    let iconX = (cellWidth - actualIconSize) / 2
                    let iconY = labelHeight + labelTopSpacing
                    let iconFrame = CGRect(x: iconX, y: iconY, width: actualIconSize, height: actualIconSize)
                    iconLayer.frame = iconFrame

                    if let checkboxLayer = containerLayer.sublayers?.first(where: { $0.name == "batchSelectionCheckbox" }) {
                        let checkboxSize = max(16, min(22, actualIconSize * 0.28))
                        let edgeInset = max(2.5, min(5.0, actualIconSize * 0.055))
                        let checkboxX = iconFrame.maxX - checkboxSize - edgeInset
                        let checkboxY = iconFrame.maxY - checkboxSize - edgeInset
                        checkboxLayer.frame = CGRect(x: checkboxX, y: checkboxY, width: checkboxSize, height: checkboxSize)
                        checkboxLayer.cornerRadius = checkboxSize * 0.5
                        if let markLayer = checkboxLayer.sublayers?.first(where: { $0.name == "batchSelectionCheckboxMark" }) as? CAShapeLayer {
                            markLayer.frame = checkboxLayer.bounds
                            markLayer.lineWidth = max(1.7, checkboxSize * 0.14)
                            markLayer.path = checkboxMarkPath(in: checkboxLayer.bounds)
                        }
                    }
                }
                
                // Update glass background for folders
                if let glassLayer = containerLayer.sublayers?.first(where: { $0.name == "glass" }) {
                    let glassSize = actualIconSize * 0.8
                    let glassX = (cellWidth - glassSize) / 2
                    let glassY = labelHeight + labelTopSpacing + (actualIconSize - glassSize) / 2
                    glassLayer.frame = CGRect(x: glassX, y: glassY, width: glassSize, height: glassSize)
                    glassLayer.cornerRadius = glassSize * 0.25  // Larger corner radius
                }

                if let textLayer = containerLayer.sublayers?.first(where: { $0.name == "label" }) as? CATextLayer {
                    let labelWidth = cellWidth - 8
                    textLayer.isHidden = !showLabels
                    textLayer.frame = CGRect(x: 4, y: 0, width: labelWidth, height: labelHeight)
                }
            }
        }

        let totalWidth = pageWidth * CGFloat(max(1, pageCount)) + pageSpacing * CGFloat(max(pageCount - 1, 0))
        // Avoid setting frame on a transformed layer; reset to identity, update frame, then re-apply translation.
        // This prevents visual/data misalignment caused by frame updates under non-identity transforms.
        pageContainerLayer.transform = CATransform3DIdentity
        pageContainerLayer.frame = CGRect(x: 0, y: 0, width: totalWidth, height: bounds.height)
        pageContainerLayer.transform = CATransform3DMakeTranslation(scrollOffset, 0, 0)
        refreshBatchSelectionUI()

        CATransaction.commit()

        logIfMismatch("updateLayout")
        // print("📐 [CAGrid] Layout: \(columns)x\(rows), iconSize=\(actualIconSize), cell=\(cellWidth)x\(cellHeight)")
    }

    func refreshBatchSelectionUI() {
        CATransaction.begin()
        CATransaction.setDisableActions(true)

        for (pageIndex, pageLayers) in iconLayers.enumerated() {
            let pageStart = pageIndex * itemsPerPage
            for (localIndex, containerLayer) in pageLayers.enumerated() {
                let globalIndex = pageStart + localIndex
                guard items.indices.contains(globalIndex),
                      case .app(let app) = items[globalIndex],
                      let checkboxLayer = containerLayer.sublayers?.first(where: { $0.name == "batchSelectionCheckbox" }) else {
                    continue
                }
                let isSelected = batchSelectedAppPathSet.contains(app.url.path)
                checkboxLayer.isHidden = !isBatchSelectionMode
                if isSelected {
                    checkboxLayer.backgroundColor = NSColor.systemBlue.cgColor
                    checkboxLayer.borderColor = NSColor.systemBlue.withAlphaComponent(0.95).cgColor
                } else {
                    checkboxLayer.backgroundColor = NSColor.white.withAlphaComponent(0.88).cgColor
                    checkboxLayer.borderColor = NSColor.black.withAlphaComponent(0.35).cgColor
                }
                if let markLayer = checkboxLayer.sublayers?.first(where: { $0.name == "batchSelectionCheckboxMark" }) as? CAShapeLayer {
                    markLayer.isHidden = !isSelected
                    markLayer.strokeColor = NSColor.white.cgColor
                }
            }
        }

        CATransaction.commit()
    }

    func checkboxMarkPath(in bounds: CGRect) -> CGPath {
        let path = CGMutablePath()
        let start = CGPoint(x: bounds.minX + bounds.width * 0.24, y: bounds.minY + bounds.height * 0.50)
        let mid = CGPoint(x: bounds.minX + bounds.width * 0.44, y: bounds.minY + bounds.height * 0.30)
        let end = CGPoint(x: bounds.minX + bounds.width * 0.76, y: bounds.minY + bounds.height * 0.66)
        path.move(to: start)
        path.addLine(to: mid)
        path.addLine(to: end)
        return path
    }

    override func viewWillDraw() {
        super.viewWillDraw()
        // 确保视图是第一响应者和滚轮监听器已安装
        if window != nil {
            makeFirstResponderIfAvailable()
            // 确保滚轮监听器存在
            if scrollEventMonitor == nil {
                setupScrollEventMonitor()
            }
        }
    }

    override func layout() {
        super.layout()

        guard bounds.width > 0, bounds.height > 0 else { return }

        CATransaction.begin()
        CATransaction.setDisableActions(true)
        containerLayer.frame = bounds
        CATransaction.commit()

        // Force layout update, especially important when bounds become valid after items were set
        updateLayout()
        needsLayoutRefresh = false

        // Clamp currentPage to valid range after items/pageCount might have changed
        let validPage = max(0, min(pageCount - 1, currentPage))
        if validPage != currentPage {
            currentPage = validPage
        }

        // Reposition to current page without animation
        let pageStride = bounds.width + pageSpacing
        scrollOffset = -CGFloat(currentPage) * pageStride
        targetScrollOffset = scrollOffset
        isScrollAnimating = false

        CATransaction.begin()
        CATransaction.setDisableActions(true)
        pageContainerLayer.transform = CATransform3DMakeTranslation(scrollOffset, 0, 0)
        CATransaction.commit()
        logIfMismatch("layout")
    }

}
