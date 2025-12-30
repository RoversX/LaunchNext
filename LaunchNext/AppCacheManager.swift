import Foundation
import AppKit
import Combine

/// 应用缓存管理器 - 负责缓存应用图标、应用信息和网格布局数据以提高性能
final class AppCacheManager: ObservableObject {
    static let shared = AppCacheManager()
    
    // MARK: - 缓存存储
    private var iconCache: [String: NSImage] = [:]
    private var appInfoCache: [String: AppInfo] = [:]
    private var gridLayoutCache: [String: Any] = [:]
    private let cacheLock = NSLock()
    
    // MARK: - 缓存配置
    private let maxIconCacheSize = 200
    private let maxAppInfoCacheSize = 300
    private var iconCacheOrder: [String] = [] // 改为可变数组，实现真正的LRU
    
    // MARK: - 缓存状态
    @Published var isCacheValid = false
    @Published var lastCacheUpdate = Date.distantPast
    @Published var cacheSize: Int = 0
    // MARK: - 缓存键生成
    private let cacheKeyGenerator = CacheKeyGenerator()

    private init() {}

    private var isLeanMode: Bool {
        PerformanceMode.current == .lean
    }
    // MARK: - 公共接口
    
    /// 生成应用缓存 - 在应用启动或扫描后调用
    func generateCache(from apps: [AppInfo],
                       items: [LaunchpadItem],
                       itemsPerPage: Int,
                       columns: Int,
                       rows: Int) {
        DispatchQueue.global(qos: .userInitiated).async { [weak self] in
            guard let self = self else { return }
            
            // 清空旧缓存
            self.clearAllCaches()
            
            // 收集所有需要缓存的应用，包括文件夹内的应用
            var allApps: [AppInfo] = []
            allApps.append(contentsOf: apps)
            
            // 从items中提取文件夹内的应用
            for item in items {
                if case let .folder(folder) = item {
                    allApps.append(contentsOf: folder.apps)
                }
            }
            
            // 去重，避免重复缓存同一个应用
            var uniqueApps: [AppInfo] = []
            var seenPaths = Set<String>()
            for app in allApps {
                if !seenPaths.contains(app.url.path) {
                    seenPaths.insert(app.url.path)
                    uniqueApps.append(app)
                }
            }
            
            // 缓存应用信息
            self.cacheAppInfos(uniqueApps)
            
            // 缓存应用图标
            if !self.isLeanMode {
                self.cacheAppIcons(uniqueApps)
            }
            
            // 缓存网格布局数据
            self.cacheGridLayout(items,
                                 itemsPerPage: itemsPerPage,
                                 columns: columns,
                                 rows: rows)
            
            DispatchQueue.main.async {
                self.isCacheValid = true
                self.lastCacheUpdate = Date()
                self.calculateCacheSize()
        
            }
        }
    }
    
    /// 获取缓存的应用图标
    func getCachedIcon(for appPath: String) -> NSImage? {
        if isLeanMode {
            return nil
        }
        let key = cacheKeyGenerator.generateIconKey(for: appPath)
        
        cacheLock.lock()
        defer { cacheLock.unlock() }
        if let icon = iconCache[key] {
            if let index = iconCacheOrder.firstIndex(of: key) {
                iconCacheOrder.remove(at: index)
                iconCacheOrder.append(key)
            }
            return icon
        } else {
            return nil
        }
    }
    
    /// 获取缓存的应用信息
    func getCachedAppInfo(for appPath: String) -> AppInfo? {
        let key = cacheKeyGenerator.generateAppInfoKey(for: appPath)
        return appInfoCache[key]
    }
    
    /// 获取缓存的网格布局数据
    func getCachedGridLayout(for layoutKey: String) -> Any? {
        let key = cacheKeyGenerator.generateGridLayoutKey(for: layoutKey)
        return gridLayoutCache[key]
    }
    
    /// 预加载应用图标到缓存
    func preloadIcons(for appPaths: [String]) {
        if isLeanMode {
            return
        }
        DispatchQueue.global(qos: .utility).async { [weak self] in
            guard let self = self else { return }
            
            for path in appPaths {
                if self.getCachedIcon(for: path) == nil {
                    let icon = NSWorkspace.shared.icon(forFile: path)
                    let key = self.cacheKeyGenerator.generateIconKey(for: path)
                    self.cacheLock.lock()
                    self.iconCache[key] = icon
                    self.iconCacheOrder.append(key)
                    if self.iconCache.count > self.maxIconCacheSize {
                        if let oldestKey = self.iconCacheOrder.first {
                            self.iconCache.removeValue(forKey: oldestKey)
                            self.iconCacheOrder.removeFirst()
                        }
                    }
                    self.cacheLock.unlock()
                }
            }
            
            DispatchQueue.main.async {
                self.calculateCacheSize()
            }
        }
    }
    
    /// 智能预加载：预加载当前页面和相邻页面的图标
    func smartPreloadIcons(for items: [LaunchpadItem], currentPage: Int, itemsPerPage: Int) {
        if isLeanMode {
            return
        }
        let startIndex = max(0, (currentPage - 1) * itemsPerPage)
        let endIndex = min(items.count, (currentPage + 2) * itemsPerPage)
        
        let relevantItems = Array(items[startIndex..<endIndex])
        let appPaths = relevantItems.compactMap { item -> String? in
            if case let .app(app) = item {
                return app.url.path
            }
            return nil
        }
        
        preloadIcons(for: appPaths)
    }
    
    /// 清除所有缓存
    func clearAllCaches() {
        cacheLock.lock()
        iconCache.removeAll()
        appInfoCache.removeAll()
        gridLayoutCache.removeAll()
        iconCacheOrder.removeAll()
        cacheLock.unlock()
        
        DispatchQueue.main.async {
            self.isCacheValid = false
            self.cacheSize = 0
        }
    }
    
    /// 清除过期缓存
    func clearExpiredCache() {
        let now = Date()
        let cacheAgeThreshold: TimeInterval = 24 * 60 * 60 // 24小时
        
        if now.timeIntervalSince(lastCacheUpdate) > cacheAgeThreshold {
            clearAllCaches()
        }
    }
    
    /// 手动刷新缓存
    func refreshCache(from apps: [AppInfo],
                      items: [LaunchpadItem],
                      itemsPerPage: Int,
                      columns: Int,
                      rows: Int) {
        // 收集所有需要缓存的应用，包括文件夹内的应用
        var allApps: [AppInfo] = []
        allApps.append(contentsOf: apps)
        
        // 从items中提取文件夹内的应用
        for item in items {
            if case let .folder(folder) = item {
                allApps.append(contentsOf: folder.apps)
            }
        }
        
        // 去重，避免重复缓存同一个应用
        var uniqueApps: [AppInfo] = []
        var seenPaths = Set<String>()
        for app in allApps {
            if !seenPaths.contains(app.url.path) {
                seenPaths.insert(app.url.path)
                uniqueApps.append(app)
            }
        }
        
        generateCache(from: uniqueApps,
                      items: items,
                      itemsPerPage: itemsPerPage,
                      columns: columns,
                      rows: rows)
    }
    
    // MARK: - 私有方法
    
    private func cacheAppInfos(_ apps: [AppInfo]) {
        cacheLock.lock()
        for app in apps {
            let key = cacheKeyGenerator.generateAppInfoKey(for: app.url.path)
            appInfoCache[key] = app
        }
        cacheLock.unlock()
    }
    
    private func cacheAppIcons(_ apps: [AppInfo]) {
        if isLeanMode {
            return
        }
        cacheLock.lock()
        for app in apps {
            let key = cacheKeyGenerator.generateIconKey(for: app.url.path)
            if let existingIndex = iconCacheOrder.firstIndex(of: key) {
                iconCacheOrder.remove(at: existingIndex)
            }
            iconCache[key] = app.icon
            iconCacheOrder.append(key)
            if iconCache.count > maxIconCacheSize {
                if let oldestKey = iconCacheOrder.first {
                    iconCache.removeValue(forKey: oldestKey)
                    iconCacheOrder.removeFirst()
                }
            }
        }
        cacheLock.unlock()
    }
    
    private func cacheGridLayout(_ items: [LaunchpadItem],
                                 itemsPerPage: Int,
                                 columns: Int,
                                 rows: Int) {
        // 缓存网格布局相关的计算数据
        let layoutData = GridLayoutCacheData(
            totalItems: items.count,
            itemsPerPage: itemsPerPage,
            columns: columns,
            rows: rows,
            pageCount: (items.count + max(itemsPerPage, 1) - 1) / max(itemsPerPage, 1)
        )
        let pageInfo = calculatePageInfo(for: items, itemsPerPage: itemsPerPage)
        let key = cacheKeyGenerator.generateGridLayoutKey(for: "main")
        let pageKey = cacheKeyGenerator.generateGridLayoutKey(for: "pages")
        cacheLock.lock()
        gridLayoutCache[key] = layoutData
        gridLayoutCache[pageKey] = pageInfo
        cacheLock.unlock()
        
    }
    
    /// 计算页面信息
    private func calculatePageInfo(for items: [LaunchpadItem], itemsPerPage: Int) -> [PageInfo] {
        let sanitizedItemsPerPage = max(itemsPerPage, 1)
        let pageCount = (items.count + sanitizedItemsPerPage - 1) / sanitizedItemsPerPage

        var pages: [PageInfo] = []

        for pageIndex in 0..<pageCount {
            let startIndex = pageIndex * sanitizedItemsPerPage
            let endIndex = min(startIndex + sanitizedItemsPerPage, items.count)
            let pageItems = Array(items[startIndex..<endIndex])
            
            let appCount = pageItems.filter { if case .app = $0 { return true } else { return false } }.count
            let folderCount = pageItems.filter { if case .folder = $0 { return true } else { return false } }.count
            let emptyCount = pageItems.filter { if case .empty = $0 { return true } else { return false } }.count
            
            let pageInfo = PageInfo(
                pageIndex: pageIndex,
                startIndex: startIndex,
                endIndex: endIndex,
                appCount: appCount,
                folderCount: folderCount,
                emptyCount: emptyCount
            )
            
            pages.append(pageInfo)
        }
        
        return pages
    }
    
    private func calculateCacheSize() {
        cacheLock.lock()
        let iconSize = iconCache.count
        let appInfoSize = appInfoCache.count
        let gridLayoutSize = gridLayoutCache.count
        cacheLock.unlock()
        cacheSize = iconSize + appInfoSize + gridLayoutSize
    }

    
    /// 获取性能统计
    var performanceStats: PerformanceStats {
        return PerformanceStats(cacheSize: cacheSize)
    }
}

// MARK: - 缓存键生成器

private struct CacheKeyGenerator {
    func generateIconKey(for appPath: String) -> String {
        return "icon_\(appPath.hashValue)"
    }
    
    func generateAppInfoKey(for appPath: String) -> String {
        return "appinfo_\(appPath.hashValue)"
    }
    
    func generateGridLayoutKey(for layoutKey: String) -> String {
        return "grid_\(layoutKey.hashValue)"
    }
}

// MARK: - 网格布局缓存数据结构

private struct GridLayoutCacheData {
    let totalItems: Int
    let itemsPerPage: Int
    let columns: Int
    let rows: Int
    let pageCount: Int
}

private struct PageInfo {
    let pageIndex: Int
    let startIndex: Int
    let endIndex: Int
    let appCount: Int
    let folderCount: Int
    let emptyCount: Int
}

// MARK: - 缓存统计信息

extension AppCacheManager {
    var cacheStatistics: CacheStatistics {
        return CacheStatistics(
            iconCacheSize: iconCache.count,
            appInfoCacheSize: appInfoCache.count,
            gridLayoutCacheSize: gridLayoutCache.count,
            totalCacheSize: cacheSize,
            isCacheValid: isCacheValid,
            lastUpdate: lastCacheUpdate
        )
    }
}

struct CacheStatistics {
    let iconCacheSize: Int
    let appInfoCacheSize: Int
    let gridLayoutCacheSize: Int
    let totalCacheSize: Int
    let isCacheValid: Bool
    let lastUpdate: Date
}

struct PerformanceStats {
    let cacheSize: Int
}
