import Foundation
import Combine

final class LaunchpadSearchEngine: ObservableObject {
    @Published private(set) var indexRevision: UInt = 0

    private let matcher = FuzzyMatcher()
    private let indexQueue = DispatchQueue(
        label: "com.roversx.LaunchNext.search-index",
        qos: .utility
    )
    private let indexLock = NSLock()
    private var indexGeneration: UInt = 0
    private var inventoryNames: Set<String> = []
    private var entriesByName: [String: SearchIndexEntry] = [:]

    func updateIndex(for items: [LaunchpadItem]) {
        let names = Self.uniqueDisplayNames(in: items)
        var pendingEntries: [SearchIndexEntry] = []
        let generation: UInt

        indexLock.lock()
        guard names != inventoryNames else {
            indexLock.unlock()
            return
        }

        indexGeneration &+= 1
        generation = indexGeneration

        var nextEntries: [String: SearchIndexEntry] = [:]
        nextEntries.reserveCapacity(names.count)

        for name in names {
            let entry = entriesByName[name] ?? SearchIndexEntry(displayName: name)
            nextEntries[name] = entry
            if !entry.isTransliterationPrepared {
                pendingEntries.append(entry)
            }
        }

        inventoryNames = names
        entriesByName = nextEntries
        indexLock.unlock()

        guard !pendingEntries.isEmpty else { return }

        indexQueue.async { [weak self] in
            guard let self else { return }
            var enrichedEntries: [String: SearchIndexEntry] = [:]
            enrichedEntries.reserveCapacity(pendingEntries.count)

            for entry in pendingEntries {
                guard self.isCurrentGeneration(generation) else { return }
                enrichedEntries[entry.displayName] = autoreleasepool {
                    entry.preparingTransliteration()
                }
            }

            DispatchQueue.main.async { [weak self] in
                self?.apply(enrichedEntries, generation: generation)
            }
        }
    }

    /// `searchOnlyItems` are ranked by the same rules as `items` and lose only
    /// ties to them. A blank query returns `items` unchanged as the grid.
    func filter(items: [LaunchpadItem],
                searchOnlyItems: [LaunchpadItem] = [],
                query: String,
                fuzzyEnabled: Bool) -> [LaunchpadItem] {
        let trimmedQuery = query.trimmingCharacters(in: .whitespacesAndNewlines)
        guard !trimmedQuery.isEmpty else { return items }

        let candidates = searchOnlyItems.isEmpty ? items : items + searchOnlyItems
        if fuzzyEnabled {
            return fuzzyFilter(items: candidates, query: trimmedQuery)
        }
        return containsFilter(items: candidates, query: trimmedQuery)
    }

    private func fuzzyFilter(items: [LaunchpadItem], query: String) -> [LaunchpadItem] {
        var candidates: [Candidate] = []
        var seenApps = Set<String>()
        let entries = indexSnapshot()

        for (itemIndex, item) in items.enumerated() {
            switch item {
            case .app(let app):
                if let match = matcher.score(query: query, entry: entry(for: app.name, in: entries)),
                   seenApps.insert(app.url.path).inserted {
                    candidates.append(Candidate(item: .app(app),
                                                match: match,
                                                primaryOrder: itemIndex,
                                                secondaryOrder: 0))
                }
            case .missingApp(let placeholder):
                if let match = matcher.score(
                    query: query,
                    entry: entry(for: placeholder.displayName, in: entries)
                ) {
                    candidates.append(Candidate(item: .missingApp(placeholder),
                                                match: match,
                                                primaryOrder: itemIndex,
                                                secondaryOrder: 0))
                }
            case .folder(let folder):
                for (nestedIndex, app) in folder.apps.enumerated() {
                    if let match = matcher.score(query: query, entry: entry(for: app.name, in: entries)),
                       seenApps.insert(app.url.path).inserted {
                        candidates.append(Candidate(item: .app(app),
                                                    match: match,
                                                    primaryOrder: itemIndex,
                                                    secondaryOrder: nestedIndex))
                    }
                }
            case .empty:
                break
            }
        }

        return candidates
            .sorted {
                if $0.match.source.rawValue != $1.match.source.rawValue {
                    return $0.match.source.rawValue > $1.match.source.rawValue
                }
                if $0.match.score != $1.match.score {
                    return $0.match.score > $1.match.score
                }
                if $0.primaryOrder != $1.primaryOrder { return $0.primaryOrder < $1.primaryOrder }
                return $0.secondaryOrder < $1.secondaryOrder
            }
            .map(\.item)
    }

    private func containsFilter(items: [LaunchpadItem], query: String) -> [LaunchpadItem] {
        var result: [LaunchpadItem] = []
        var seenApps = Set<String>()

        for item in items {
            switch item {
            case .app(let app):
                if app.name.localizedCaseInsensitiveContains(query), seenApps.insert(app.url.path).inserted {
                    result.append(.app(app))
                }
            case .missingApp(let placeholder):
                if placeholder.displayName.localizedCaseInsensitiveContains(query),
                   seenApps.insert(placeholder.bundlePath).inserted {
                    result.append(.missingApp(placeholder))
                }
            case .folder(let folder):
                for app in folder.apps where app.name.localizedCaseInsensitiveContains(query) {
                    if seenApps.insert(app.url.path).inserted {
                        result.append(.app(app))
                    }
                }
            case .empty:
                break
            }
        }

        return result
    }

    private func indexSnapshot() -> [String: SearchIndexEntry] {
        indexLock.lock()
        defer { indexLock.unlock() }
        return entriesByName
    }

    private func entry(for displayName: String,
                       in snapshot: [String: SearchIndexEntry]) -> SearchIndexEntry {
        snapshot[displayName] ?? SearchIndexEntry(displayName: displayName)
    }

    private func isCurrentGeneration(_ generation: UInt) -> Bool {
        indexLock.lock()
        defer { indexLock.unlock() }
        return generation == indexGeneration
    }

    private func apply(_ enrichedEntries: [String: SearchIndexEntry],
                       generation: UInt) {
        indexLock.lock()
        guard generation == indexGeneration else {
            indexLock.unlock()
            return
        }

        for (name, entry) in enrichedEntries where inventoryNames.contains(name) {
            entriesByName[name] = entry
        }
        indexLock.unlock()

        indexRevision &+= 1
    }

    private static func uniqueDisplayNames(in items: [LaunchpadItem]) -> Set<String> {
        var names = Set<String>()
        for item in items {
            switch item {
            case .app(let app):
                names.insert(app.name)
            case .folder(let folder):
                names.formUnion(folder.apps.map(\.name))
            case .missingApp(let placeholder):
                names.insert(placeholder.displayName)
            case .empty:
                break
            }
        }
        return names
    }
}

private struct Candidate {
    let item: LaunchpadItem
    let match: SearchMatch
    let primaryOrder: Int
    let secondaryOrder: Int
}
