import Foundation
import AppKit
import SwiftData

struct FolderInfo: Identifiable, Equatable {
    let id: String
    var name: String
    var apps: [AppInfo]
    let createdAt: Date
    
    init(id: String = UUID().uuidString, name: String = "Untitled", apps: [AppInfo] = [], createdAt: Date = Date()) {
        self.id = id
        self.name = name
        self.apps = apps
        self.createdAt = createdAt
    }
    
    var folderIcon: NSImage {
        // 使用缓存生成文件夹图标，避免重复渲染
        let icon = icon(of: 72)
        return icon
    }

    func icon(of side: CGFloat) -> NSImage {
        let normalizedSide = max(16, side)
        let cacheKey = folderPreviewCacheKey(for: normalizedSide)
        if let cached = FolderPreviewCache.shared.image(forKey: cacheKey) {
            return cached
        }
        let icon = renderFolderIcon(side: normalizedSide)
        FolderPreviewCache.shared.store(icon, forKey: cacheKey)
        return icon
    }

    private func renderFolderIcon(side: CGFloat) -> NSImage {
        let size = NSSize(width: side, height: side)
        let image = NSImage(size: size)
        image.lockFocus()
        defer { image.unlockFocus() }

        if let ctx = NSGraphicsContext.current {
            ctx.imageInterpolation = .high
            ctx.shouldAntialias = true
        }

        let rect = NSRect(origin: .zero, size: size)

        let outerInset = round(side * 0.12)
        let contentRect = rect.insetBy(dx: outerInset, dy: outerInset)
        let innerInset = round(contentRect.width * 0.08)
        let innerRect = contentRect.insetBy(dx: innerInset, dy: innerInset)

        // 外层缩略图：3x3 马赛克
        let cols = 3
        let rows = 3
        let spacing = max(1, round(innerRect.width * 0.02))
        let tileW = floor((innerRect.width - CGFloat(cols - 1) * spacing) / CGFloat(cols))
        let tileH = floor((innerRect.height - CGFloat(rows - 1) * spacing) / CGFloat(rows))
        let tile = min(tileW, tileH)
        let totalW = CGFloat(cols) * tile + CGFloat(cols - 1) * spacing
        let totalH = CGFloat(rows) * tile + CGFloat(rows - 1) * spacing
        let startX = innerRect.minX + (innerRect.width - totalW) / 2
        let startYTop = innerRect.maxY - (innerRect.height - totalH) / 2

        for (index, app) in apps.prefix(cols * rows).enumerated() {
            let row = index / cols
            let col = index % cols
            let x = startX + CGFloat(col) * (tile + spacing)
            let y = startYTop - CGFloat(row + 1) * tile - CGFloat(row) * spacing
            let iconRect = NSRect(x: x, y: y, width: tile, height: tile)
            
            // 图标兜底：若应用图标尺寸为0，回退到系统文件图标
            let iconToDraw: NSImage = {
                let baseIcon = IconStore.shared.icon(for: app)
                if baseIcon.size.width > 0 && baseIcon.size.height > 0 {
                    return baseIcon
                }
                return NSWorkspace.shared.icon(forFile: app.url.path)
            }()
            iconToDraw.draw(in: iconRect)
        }

        return image
    }

    private func folderPreviewCacheKey(for side: CGFloat) -> String {
        var hasher = Hasher()
        hasher.combine(id)
        for app in apps {
            hasher.combine(app.url.path)
        }
        let contentHash = hasher.finalize()
        let sizeKey = Int(side.rounded())
        return "folderPreview_\(id)_\(sizeKey)_\(contentHash)"
    }
    
    static func == (lhs: FolderInfo, rhs: FolderInfo) -> Bool {
        lhs.id == rhs.id
    }
}

enum LaunchpadItem: Identifiable, Equatable {
    case app(AppInfo)
    case folder(FolderInfo)
    case empty(String)
    case missingApp(MissingAppPlaceholder)
    
    var id: String {
        switch self {
        case .app(let app):
            return "app_\(app.id)"
        case .folder(let folder):
            return "folder_\(folder.id)"
        case .empty(let token):
            return "empty_\(token)"
        case .missingApp(let placeholder):
            return "missing_\(placeholder.bundlePath)"
        }
    }
    
    var name: String {
        switch self {
        case .app(let app):
            return app.name
        case .folder(let folder):
            return folder.name
        case .empty:
            return ""
        case .missingApp(let placeholder):
            return placeholder.displayName
        }
    }

    var icon: NSImage {
        switch self {
        case .app(let app):
            return app.icon
        case .folder(let folder):
            let icon = folder.folderIcon
            return icon
        case .empty:
            // 透明占位
            return NSImage(size: .zero)
        case .missingApp(let placeholder):
            return placeholder.icon
        }
    }

    // 方便判断：若为 .app 返回 AppInfo，否则为 nil
    var appInfoIfApp: AppInfo? {
        if case let .app(app) = self { return app }
        return nil
    }
    
    static func == (lhs: LaunchpadItem, rhs: LaunchpadItem) -> Bool {
        lhs.id == rhs.id
    }
}

// MARK: - 统一持久化模型（顶层项：应用或文件夹）
@Model
final class TopItemData {
    // 统一主键：对于应用可使用 appPath，对于文件夹使用 folderId
    @Attribute(.unique) var id: String
    var kind: String                 // "app" or "folder"
    var orderIndex: Int              // 顶层混合顺序索引
    // 应用字段
    var appPath: String?
    // 文件夹字段
    var folderName: String?
    var appPaths: [String]           // 文件夹内的应用顺序
    // 时间戳
    var createdAt: Date
    var updatedAt: Date

    // 文件夹构造
    init(folderId: String,
         folderName: String,
         appPaths: [String],
         orderIndex: Int,
         createdAt: Date = Date(),
         updatedAt: Date = Date()) {
        self.id = folderId
        self.kind = "folder"
        self.orderIndex = orderIndex
        self.appPath = nil
        self.folderName = folderName
        self.appPaths = appPaths
        self.createdAt = createdAt
        self.updatedAt = updatedAt
    }

    // 应用构造
    init(appPath: String,
         orderIndex: Int,
         createdAt: Date = Date(),
         updatedAt: Date = Date()) {
        self.id = appPath
        self.kind = "app"
        self.orderIndex = orderIndex
        self.appPath = appPath
        self.folderName = nil
        self.appPaths = []
        self.createdAt = createdAt
        self.updatedAt = updatedAt
    }

    // 空槽位构造
    init(emptyId: String,
         orderIndex: Int,
         createdAt: Date = Date(),
         updatedAt: Date = Date()) {
        self.id = emptyId
        self.kind = "empty"
        self.orderIndex = orderIndex
        self.appPath = nil
        self.folderName = nil
        self.appPaths = []
        self.createdAt = createdAt
        self.updatedAt = updatedAt
    }
}

// MARK: - 每页独立排序持久化模型（按“页-槽位”存储）
@Model
final class PageEntryData {
    // 槽位唯一键：例如 "page-0-pos-3"
    @Attribute(.unique) var slotId: String
    var pageIndex: Int
    var position: Int
    var kind: String          // "app" | "folder" | "empty" | "missing"
    // app 条目
    var appPath: String?
    var appDisplayName: String?
    // folder 条目
    var folderId: String?
    var folderName: String?
    var appPaths: [String]
    // removable source 记录该缺失应用来自哪个可移除目录，便于清理
    var removableSource: String?
    // 时间戳
    var createdAt: Date
    var updatedAt: Date

    init(slotId: String,
         pageIndex: Int,
         position: Int,
         kind: String,
         appPath: String? = nil,
         folderId: String? = nil,
         folderName: String? = nil,
         appPaths: [String] = [],
         appDisplayName: String? = nil,
         removableSource: String? = nil,
         createdAt: Date = Date(),
         updatedAt: Date = Date()) {
        self.slotId = slotId
        self.pageIndex = pageIndex
        self.position = position
        self.kind = kind
        self.appPath = appPath
        self.folderId = folderId
        self.folderName = folderName
        self.appPaths = appPaths
        self.appDisplayName = appDisplayName
        self.removableSource = removableSource
        self.createdAt = createdAt
        self.updatedAt = updatedAt
    }
}

struct MissingAppPlaceholder: Equatable, Hashable, Identifiable {
    let bundlePath: String
    let displayName: String
    let removableSource: String?
    var id: String { bundlePath }
    var icon: NSImage { Self.defaultIcon }

    static let defaultIcon: NSImage = {
        let dimension: CGFloat = 256
        let size = NSSize(width: dimension, height: dimension)
        let image = NSImage(size: size)
        image.lockFocus()

        let rect = NSRect(origin: .zero, size: size)
        let backgroundPath = NSBezierPath(roundedRect: rect,
                                          xRadius: dimension * 0.18,
                                          yRadius: dimension * 0.18)
        NSColor.controlBackgroundColor.withAlphaComponent(0.92).setFill()
        backgroundPath.fill()

        let inset = dimension * 0.12
        let strokeRect = rect.insetBy(dx: inset, dy: inset)
        let dashPath = NSBezierPath(roundedRect: strokeRect,
                                    xRadius: strokeRect.width * 0.18,
                                    yRadius: strokeRect.height * 0.18)
        let pattern: [CGFloat] = [dimension * 0.16, dimension * 0.10]
        pattern.withUnsafeBufferPointer { buffer in
            dashPath.setLineDash(buffer.baseAddress, count: pattern.count, phase: 0)
        }
        dashPath.lineWidth = max(1, dimension * 0.05)
        NSColor.quaternaryLabelColor.setStroke()
        dashPath.stroke()

        image.unlockFocus()
        image.isTemplate = false
        return image
    }()
}
