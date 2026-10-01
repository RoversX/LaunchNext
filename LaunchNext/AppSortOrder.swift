import Foundation

/// How the top-level grid is ordered. `.myArrangement` shows the user's persisted
/// arrangement; other modes only reorder what is displayed and never write back
/// into `AppStore.items`, so switching back restores the arrangement exactly.
enum AppSortMode: String, CaseIterable, Identifiable {
    // Raw value predates the "My arrangement" label; kept so saved preferences still load.
    case myArrangement = "custom"
    case alphabetical
    case recentlyUsed

    var id: String { rawValue }
}

/// Where an item lands in a sorted grid.
enum AppSortRank: Equatable {
    case used(Date, name: String)
    case unused(name: String)
    /// Kept, but after every app and folder (e.g. missing-app placeholders).
    case trailing
    /// Dropped from the sorted grid (e.g. empty layout slots).
    case omitted
}

/// Pure ordering math, compiled directly into the test target alongside
/// GridReorderPlan.swift, so it must not depend on AppStore or AppKit.
enum AppSortOrder {
    /// Used items newest first, then unused items A–Z, then trailing items in
    /// their original order. Ties keep their original relative order. Ranking
    /// every item `.unused` gives a plain A–Z order.
    static func sorted<Item>(_ items: [Item], rank: (Item) -> AppSortRank) -> [Item] {
        var used: [(offset: Int, date: Date, name: String, item: Item)] = []
        var unused: [(offset: Int, name: String, item: Item)] = []
        var trailing: [Item] = []

        for (offset, item) in items.enumerated() {
            switch rank(item) {
            case .used(let date, let name): used.append((offset, date, name, item))
            case .unused(let name): unused.append((offset, name, item))
            case .trailing: trailing.append(item)
            case .omitted: break
            }
        }

        used.sort { lhs, rhs in
            if lhs.date != rhs.date { return lhs.date > rhs.date }
            let byName = lhs.name.localizedCaseInsensitiveCompare(rhs.name)
            if byName != .orderedSame { return byName == .orderedAscending }
            return lhs.offset < rhs.offset
        }
        unused.sort { lhs, rhs in
            let byName = lhs.name.localizedCaseInsensitiveCompare(rhs.name)
            if byName != .orderedSame { return byName == .orderedAscending }
            return lhs.offset < rhs.offset
        }

        return used.map(\.item) + unused.map(\.item) + trailing
    }

    /// An app ranks by its own last use; a folder by the newest use of any app
    /// inside it. Nothing used ranks as unused.
    static func rank(name: String, lastUses: [Date?]) -> AppSortRank {
        lastUses.compactMap { $0 }.max().map { .used($0, name: name) } ?? .unused(name: name)
    }

    /// Normalised key so launch-notification bundle URLs match scanned app URLs.
    static func usageKey(for url: URL) -> String {
        url.standardizedFileURL.resolvingSymlinksInPath().path
    }
}
