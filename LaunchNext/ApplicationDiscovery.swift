import Foundation

nonisolated enum ApplicationPath {
    static func standardized(_ path: String) -> String {
        URL(fileURLWithPath: path).standardized.path
    }

    /// Both arguments are already standardized. This comparison performs no I/O.
    static func isPath(_ path: String, within directory: String) -> Bool {
        path == directory || path.hasPrefix(directory.hasSuffix("/") ? directory : directory + "/")
    }
}

nonisolated struct ApplicationDiscoveryOrigin: Codable, Hashable, Sendable {
    var sourcePath: String
    var entryPath: String
    var sourceRootPath: String? = nil
}

nonisolated struct ApplicationDiscoveryIndex: Codable, Equatable, Sendable {
    static let defaultsKey = "applicationDiscoveryIndex.v1"

    var originsByTarget: [String: Set<ApplicationDiscoveryOrigin>] = [:]
    var unresolvedLegacySources: [String: Set<String>] = [:]
    var displayNames: [String: String] = [:]
    var targetsByPath: [String: String] = [:]

    private enum CodingKeys: String, CodingKey {
        case originsByTarget, unresolvedLegacySources, displayNames, targetsByPath
    }

    static func load(from defaults: UserDefaults) -> Self {
        guard let data = defaults.data(forKey: defaultsKey),
              let index = try? JSONDecoder().decode(Self.self, from: data) else { return Self() }
        return index
    }

    func save(to defaults: UserDefaults) {
        guard let data = try? JSONEncoder().encode(self) else { return }
        defaults.set(data, forKey: Self.defaultsKey)
    }
}

extension ApplicationDiscoveryIndex {
    nonisolated init(from decoder: Decoder) throws {
        let values = try decoder.container(keyedBy: CodingKeys.self)
        originsByTarget = try values.decodeIfPresent([String: Set<ApplicationDiscoveryOrigin>].self, forKey: .originsByTarget) ?? [:]
        unresolvedLegacySources = try values.decodeIfPresent([String: Set<String>].self, forKey: .unresolvedLegacySources) ?? [:]
        displayNames = try values.decodeIfPresent([String: String].self, forKey: .displayNames) ?? [:]
        targetsByPath = try values.decodeIfPresent([String: String].self, forKey: .targetsByPath) ?? [:]
    }
}

nonisolated struct ApplicationDiscoverySnapshot: Sendable {
    var applicationURLs: [URL]
    var availablePaths: Set<String>
    var unavailablePaths: Set<String>
    var index: ApplicationDiscoveryIndex
    var shouldRetry: Bool
    var canonicalPathsBySavedPath: [String: String]
}

/// Synchronous filesystem work. The caller runs this scanner on a background queue.
nonisolated enum ApplicationDiscoveryScanner {
    private enum PathState {
        case present
        case missing
        case inaccessible(retry: Bool)
    }

    private enum TargetState {
        case valid
        case missing
        case invalid
        case inaccessible
    }

    private struct SourceState {
        var root: String
        var unavailablePrefixes: Set<String> = []
        var seenEntries: Set<String> = []
        var offline = false

        var isComplete: Bool { unavailablePrefixes.isEmpty && !offline }
        func protects(_ entry: String) -> Bool {
            unavailablePrefixes.contains(root)
                || unavailablePrefixes.contains { ApplicationPath.isPath(entry, within: $0) }
        }
    }

    static func scan(
        sourcePaths: [String],
        customSourcePaths: Set<String>,
        savedPaths: Set<String>,
        previousIndex: ApplicationDiscoveryIndex,
        isValidApplication: (URL) -> Bool
    ) -> ApplicationDiscoverySnapshot {
        let manager = FileManager.default
        let configuredSources = Set(sourcePaths.map(ApplicationPath.standardized))
        let customSources = Set(customSourcePaths.map(ApplicationPath.standardized))
        var sources: [String: SourceState] = [:]
        var observedOrigins: [String: Set<ApplicationDiscoveryOrigin>] = [:]
        var targetStates: [String: TargetState] = [:]
        var shouldRetry = false

        func targetState(_ target: String) -> TargetState {
            if let cached = targetStates[target] { return cached }
            let state: TargetState
            switch pathState(target, manager: manager) {
            case .missing:
                state = .missing
            case .inaccessible(let retry):
                shouldRetry = shouldRetry || retry
                state = .inaccessible
            case .present:
                state = isValidApplication(URL(fileURLWithPath: target)) ? .valid : .invalid
            }
            targetStates[target] = state
            return state
        }

        for source in configuredSources.sorted() {
            let root = resolvedPath(source, manager: manager)
            var state = SourceState(root: root)
            switch pathState(root, manager: manager) {
            case .missing:
                if customSources.contains(source) {
                    state.offline = true
                    state.unavailablePrefixes.insert(root)
                }
                sources[source] = state
                continue
            case .inaccessible(let retry):
                state.unavailablePrefixes.insert(root)
                shouldRetry = shouldRetry || retry
                sources[source] = state
                continue
            case .present:
                break
            }

            let sourceEntry = entryPath(URL(fileURLWithPath: source), manager: manager)
            let enumerator = manager.enumerator(
                at: URL(fileURLWithPath: source),
                includingPropertiesForKeys: [.isDirectoryKey, .isSymbolicLinkKey],
                options: [.skipsHiddenFiles, .skipsPackageDescendants],
                errorHandler: { errorURL, error in
                    switch classify(error) {
                    case .missing:
                        // A directory removed during enumeration is evidence of deletion.
                        // The root recheck below distinguishes a disappearing volume.
                        break
                    case .inaccessible(let retry):
                        let failedEntry = entryPath(errorURL, manager: manager)
                        // Error locations use the same entry coordinates as origins.
                        // Only a source-root error maps to its resolved root directory.
                        let prefix = failedEntry == sourceEntry || failedEntry == root ? root : failedEntry
                        state.unavailablePrefixes.insert(prefix)
                        shouldRetry = shouldRetry || retry
                    case .present:
                        break
                    }
                    return true
                }
            )
            if let enumerator {
                for case let entryURL as URL in enumerator {
                    // Resolve parent aliases, but retain the discovery link itself.
                    let entry = entryPath(entryURL, manager: manager)
                    state.seenEntries.insert(entry)
                    let target = resolvedPath(entry, manager: manager)
                    let targetURL = URL(fileURLWithPath: target)
                    guard targetURL.pathExtension == "app",
                          targetURL.pathComponents.filter({ $0.hasSuffix(".app") }).count == 1 else { continue }

                    // Record every source edge before coalescing applications by target.
                    switch targetState(target) {
                    case .valid, .inaccessible:
                        observedOrigins[target, default: []].insert(
                            ApplicationDiscoveryOrigin(sourcePath: source, entryPath: entry, sourceRootPath: root)
                        )
                    case .missing, .invalid:
                        break
                    }
                }
            } else {
                state.unavailablePrefixes.insert(root)
                shouldRetry = true
            }

            // A volume can disappear after some of its entries have been seen.
            // Its whole source is then unknown, including intermediate ENOENTs.
            switch pathState(root, manager: manager) {
            case .missing:
                state.unavailablePrefixes.insert(root)
                state.offline = customSources.contains(source)
                if !state.offline { shouldRetry = true }
            case .inaccessible(let retry):
                state.unavailablePrefixes.insert(root)
                shouldRetry = shouldRetry || retry
            case .present:
                break
            }
            // Validation may have raced the same disappearance. Recheck affected
            // targets after the root/coverage result is known.
            for target in Array(targetStates.keys) where state.unavailablePrefixes.contains(where: {
                ApplicationPath.isPath(target, within: $0)
            }) {
                targetStates.removeValue(forKey: target)
            }
            sources[source] = state
        }

        var canonicalPathsBySavedPath: [String: String] = [:]
        var aliasesByTarget: [String: Set<String>] = [:]
        var inaccessibleAliases = Set<String>()
        for raw in savedPaths {
            let standardized = ApplicationPath.standardized(raw)
            let target: String
            if case .inaccessible(let retry) = pathState(standardized, manager: manager) {
                // A denied parent may hide a directory symlink used by the saved
                // spelling. Its prior mapping remains usable until access returns.
                target = previousIndex.targetsByPath[raw]
                    ?? previousIndex.targetsByPath[standardized]
                    ?? resolvedPath(standardized, manager: manager)
                inaccessibleAliases.formUnion([raw, standardized])
                shouldRetry = shouldRetry || retry
            } else {
                target = resolvedPath(standardized, manager: manager)
            }
            canonicalPathsBySavedPath[raw] = target
            canonicalPathsBySavedPath[standardized] = target
            aliasesByTarget[target, default: []].formUnion([raw, standardized])
        }

        var index = ApplicationDiscoveryIndex(displayNames: previousIndex.displayNames)
        index.originsByTarget = observedOrigins
        for (target, origins) in previousIndex.originsByTarget {
            for origin in origins {
                guard let source = sources[origin.sourcePath],
                      (!source.seenEntries.contains(origin.entryPath)
                        || source.unavailablePrefixes.contains(source.root)),
                      source.protects(origin.entryPath) else { continue }
                index.originsByTarget[target, default: []].insert(origin)
            }
            // Empty entries mark known identities while a saved layout still contains
            // them. Deleting an origin must never turn it into an unknown legacy app.
            if aliasesByTarget[target] != nil && index.originsByTarget[target] == nil {
                index.originsByTarget[target] = []
            }
        }

        let incompleteSources = Set(sources.compactMap { $0.value.isComplete ? nil : $0.key })
        for (target, pending) in previousIndex.unresolvedLegacySources {
            let remaining = pending.intersection(incompleteSources)
            if !remaining.isEmpty {
                index.unresolvedLegacySources[target] = remaining
            } else if aliasesByTarget[target] != nil && index.originsByTarget[target] == nil {
                index.originsByTarget[target] = []
            }
        }
        if !incompleteSources.isEmpty {
            for target in aliasesByTarget.keys
            where previousIndex.originsByTarget[target] == nil
                && previousIndex.unresolvedLegacySources[target] == nil {
                // An old layout has no provenance. Remember exactly which sources
                // have not been checked yet, even if another source found this app.
                index.unresolvedLegacySources[target] = incompleteSources
            }
        }

        func isMissingInsideOfflineSource(_ target: String, origins: Set<ApplicationDiscoveryOrigin>, pending: Set<String>) -> Bool {
            let candidates = pending.union(origins.map(\.sourcePath))
            return candidates.contains { source in
                guard let state = sources[source], state.offline else { return false }
                return ApplicationPath.isPath(target, within: state.root)
                    || origins.contains { origin in
                        guard origin.sourcePath == source else { return false }
                        if let originalRoot = origin.sourceRootPath {
                            return ApplicationPath.isPath(target, within: originalRoot)
                        }
                        return origin.entryPath == target
                    }
            }
        }

        var available = Set<String>()
        var unavailable = Set<String>()
        let targets = Set(index.originsByTarget.keys).union(index.unresolvedLegacySources.keys)
        for target in targets {
            let origins = index.originsByTarget[target] ?? []
            let pending = index.unresolvedLegacySources[target] ?? []
            guard !origins.isEmpty || !pending.isEmpty else { continue }
            switch targetState(target) {
            case .valid:
                available.insert(target)
            case .inaccessible:
                unavailable.insert(target)
            case .missing where isMissingInsideOfflineSource(target, origins: origins, pending: pending):
                unavailable.insert(target)
            case .missing, .invalid:
                // A missing external target is a real removal even if its discovery
                // link is currently hidden by a different unreadable directory.
                index.originsByTarget[target] = aliasesByTarget[target] == nil ? nil : []
                index.unresolvedLegacySources.removeValue(forKey: target)
            }
        }

        let applicationURLs = available.sorted().map { URL(fileURLWithPath: $0) }
        let indexedTargets = Set(index.originsByTarget.keys).union(index.unresolvedLegacySources.keys)
        index.targetsByPath = previousIndex.targetsByPath.filter { indexedTargets.contains($0.value) }
        for (target, aliases) in aliasesByTarget {
            if available.contains(target) {
                available.formUnion(aliases.subtracting(inaccessibleAliases))
                unavailable.formUnion(aliases.intersection(inaccessibleAliases))
            }
            if unavailable.contains(target) { unavailable.formUnion(aliases) }
            if indexedTargets.contains(target) {
                for alias in aliases { index.targetsByPath[alias] = target }
            }
        }
        unavailable.subtract(available)
        return ApplicationDiscoverySnapshot(
            applicationURLs: applicationURLs,
            availablePaths: available,
            unavailablePaths: unavailable,
            index: index,
            shouldRetry: shouldRetry,
            canonicalPathsBySavedPath: canonicalPathsBySavedPath
        )
    }

    private static func pathState(_ path: String, manager: FileManager) -> PathState {
        do {
            _ = try manager.attributesOfItem(atPath: path)
            return .present
        } catch {
            return classify(error)
        }
    }

    private static func classify(_ error: Error) -> PathState {
        var current: NSError? = error as NSError
        var permissionDenied = false
        var visited = Set<ObjectIdentifier>()
        while let value = current, visited.insert(ObjectIdentifier(value)).inserted {
            if value.domain == NSPOSIXErrorDomain {
                if value.code == Int(POSIXErrorCode.ENOENT.rawValue)
                    || value.code == Int(POSIXErrorCode.ENOTDIR.rawValue) { return .missing }
                if value.code == Int(POSIXErrorCode.EACCES.rawValue)
                    || value.code == Int(POSIXErrorCode.EPERM.rawValue) { permissionDenied = true }
            }
            if value.domain == NSCocoaErrorDomain {
                if value.code == NSFileNoSuchFileError || value.code == NSFileReadNoSuchFileError { return .missing }
                if value.code == NSFileReadNoPermissionError { permissionDenied = true }
            }
            current = value.userInfo[NSUnderlyingErrorKey] as? NSError
        }
        return .inaccessible(retry: !permissionDenied)
    }

    private static func entryPath(_ url: URL, manager: FileManager) -> String {
        let parent = resolvedPath(url.deletingLastPathComponent().path, manager: manager)
        return URL(fileURLWithPath: parent).appendingPathComponent(url.lastPathComponent).standardized.path
    }

    private static func resolvedPath(_ path: String, manager: FileManager) -> String {
        var url = URL(fileURLWithPath: path).standardizedFileURL
        var visited = Set<String>()
        // Reading the link explicitly preserves its target identity when Foundation
        // cannot stat a destination below a permission-denied parent directory.
        for _ in 0..<40 {
            let parent = url.deletingLastPathComponent().resolvingSymlinksInPath()
            url = parent.appendingPathComponent(url.lastPathComponent).standardizedFileURL
            guard visited.insert(url.path).inserted,
                  let destination = try? manager.destinationOfSymbolicLink(atPath: url.path) else {
                let resolved = url.resolvingSymlinksInPath().standardizedFileURL.path
                return resolveExistingAncestor(of: resolved, manager: manager)
            }
            if destination.hasPrefix("/") {
                url = URL(fileURLWithPath: destination).standardizedFileURL
            } else {
                url = url.deletingLastPathComponent().appendingPathComponent(destination).standardizedFileURL
            }
        }
        return url.path
    }

    private static func resolveExistingAncestor(of path: String, manager: FileManager) -> String {
        var url = URL(fileURLWithPath: path)
        var suffix: [String] = []
        while url.path != "/" {
            switch pathState(url.path, manager: manager) {
            case .present:
                guard !suffix.isEmpty else { return path }
                var result = url.resolvingSymlinksInPath().standardizedFileURL
                for component in suffix.reversed() { result.appendPathComponent(component) }
                return result.path
            case .inaccessible:
                return path
            case .missing:
                // Foundation may stop resolving aliases such as /private/tmp when
                // a suffix disappears. Resolve only the existing ancestor; a deleted
                // directory symlink must not be replaced with its historical target.
                suffix.append(url.lastPathComponent)
                url.deleteLastPathComponent()
            }
        }
        return path
    }
}
