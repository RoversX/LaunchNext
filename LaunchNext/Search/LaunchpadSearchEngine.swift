import Foundation

struct LaunchpadSearchEngine {
    private let matcher = FuzzyMatcher()

    func filter(items: [LaunchpadItem], query: String, fuzzyEnabled: Bool) -> [LaunchpadItem] {
        let trimmedQuery = query.trimmingCharacters(in: .whitespacesAndNewlines)
        guard !trimmedQuery.isEmpty else { return items }

        if fuzzyEnabled {
            return fuzzyFilter(items: items, query: trimmedQuery)
        }
        return containsFilter(items: items, query: trimmedQuery)
    }

    private func fuzzyFilter(items: [LaunchpadItem], query: String) -> [LaunchpadItem] {
        var candidates: [Candidate] = []
        var seenApps = Set<String>()

        for (itemIndex, item) in items.enumerated() {
            switch item {
            case .app(let app):
                if let score = matcher.score(query: query, entry: SearchIndexEntry(displayName: app.name)),
                   seenApps.insert(app.url.path).inserted {
                    candidates.append(Candidate(item: .app(app), score: score, primaryOrder: itemIndex, secondaryOrder: 0))
                }
            case .missingApp(let placeholder):
                if let score = matcher.score(query: query, entry: SearchIndexEntry(displayName: placeholder.displayName)) {
                    candidates.append(Candidate(item: .missingApp(placeholder), score: score, primaryOrder: itemIndex, secondaryOrder: 0))
                }
            case .folder(let folder):
                for (nestedIndex, app) in folder.apps.enumerated() {
                    if let score = matcher.score(query: query, entry: SearchIndexEntry(displayName: app.name)),
                       seenApps.insert(app.url.path).inserted {
                        candidates.append(Candidate(item: .app(app), score: score, primaryOrder: itemIndex, secondaryOrder: nestedIndex))
                    }
                }
            case .empty:
                break
            }
        }

        return candidates
            .sorted {
                if $0.score != $1.score { return $0.score > $1.score }
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
}

private struct Candidate {
    let item: LaunchpadItem
    let score: Int
    let primaryOrder: Int
    let secondaryOrder: Int
}
