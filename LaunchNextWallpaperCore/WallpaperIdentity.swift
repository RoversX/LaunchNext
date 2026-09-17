import CryptoKit
import Foundation

public enum WallpaperKind: Sendable, Equatable, Hashable {
    case staticImage
    case animated
    case unknown
}

public enum WallpaperSource: Sendable, Equatable, Hashable {
    case image(URL)
    case aerial(assetID: String)
    case unavailable
}

public struct WallpaperIdentity: Sendable, Equatable, Hashable {
    public let displayUUID: String
    public let provider: String
    public let configurationDigest: String
    public let kind: WallpaperKind
    public let source: WallpaperSource

    public init(
        displayUUID: String,
        provider: String,
        configurationDigest: String,
        kind: WallpaperKind,
        source: WallpaperSource
    ) {
        self.displayUUID = displayUUID
        self.provider = provider
        self.configurationDigest = configurationDigest
        self.kind = kind
        self.source = source
    }

    public var cacheFileStem: String {
        "\(displayUUID)-\(configurationDigest)"
    }
}

public enum WallpaperIdentityResolution: Sendable, Equatable {
    case exact(WallpaperIdentity)
    case ambiguous
    case unavailable

    public var exactIdentity: WallpaperIdentity? {
        guard case let .exact(identity) = self else { return nil }
        return identity
    }
}

public enum WallpaperIdentityResolver {
    private static let imageProvider = "com.apple.wallpaper.choice.image"
    private static let aerialProvider = "com.apple.wallpaper.choice.aerials"
    private static let dynamicProvider = "com.apple.wallpaper.choice.dynamic"

    /// Approximate, file-only preview of the configured wallpaper. This is not
    /// evidence of the frame currently on screen and must not key an exact capture.
    public static func resolvePreview(
        displayUUID: String, store: [String: Any], currentDesktopImageURL: URL? = nil
    ) -> WallpaperIdentity? {
        let configured = resolve(displayUUID: displayUUID, store: store,
                                 allowUnverifiedDesktopImageURL: false)
        switch configured {
        case .exact(let identity): return identity
        case .ambiguous:
            return resolve(displayUUID: displayUUID, store: store,
                           currentDesktopImageURL: currentDesktopImageURL,
                           allowUnverifiedDesktopImageURL: false).exactIdentity
        case .unavailable:
            return resolve(displayUUID: displayUUID, store: store,
                           currentDesktopImageURL: currentDesktopImageURL).exactIdentity
        }
    }

    /// Includes LastUse/LastSet as well as the current choice. The identity alone
    /// intentionally omits these and cannot invalidate a paused video frame.
    public static func desktopContextVersion(displayUUID: String, store: [String: Any]) -> String? {
        guard let entry = entry(for: displayUUID, displays: store["Displays"] as? [String: Any],
                                defaultEntry: store["SystemDefault"]),
              entry["Desktop"] != nil || entry["Linked"] != nil else { return nil }
        var context = entry
        context.removeValue(forKey: "Idle")
        func canonical(_ value: Any) -> Any {
            if let dictionary = value as? [String: Any] { return dictionary.mapValues { canonical($0) } }
            if let array = value as? [Any] { return array.map { canonical($0) } }
            if let data = value as? Data { return data.base64EncodedString() }
            if let date = value as? Date { return date.timeIntervalSince1970 }
            return value
        }
        guard let data = try? JSONSerialization.data(withJSONObject: canonical(context), options: .sortedKeys)
        else { return nil }
        return digest(components: [data])
    }

    public static func resolve(
        displayUUID: String,
        store: [String: Any],
        currentDesktopImageURL: URL? = nil,
        allowUnverifiedDesktopImageURL: Bool = true
    ) -> WallpaperIdentityResolution {
        let rootEntry = entry(
            for: displayUUID,
            displays: store["Displays"] as? [String: Any],
            defaultEntry: store["SystemDefault"]
        )
        // store["Spaces"] is deliberately ignored. macOS never prunes it - a real
        // machine accumulates hundreds of stale entries that disagree with each
        // other - and there is no public API to identify the current Space, so no
        // entry in it is identifiable. The root Displays[uuid] entry carries
        // LastSet/LastUse and is the authoritative "most recently set wallpaper
        // for this display".
        let uniqueCandidates = unique(candidates(in: rootEntry, displayUUID: displayUUID))

        if uniqueCandidates.count == 1, let identity = uniqueCandidates.first {
            guard identity.kind == .staticImage, let currentDesktopImageURL else {
                return .exact(identity)
            }
            let normalizedURL = currentDesktopImageURL.standardizedFileURL
            if case let .image(configuredURL) = identity.source,
               configuredURL.standardizedFileURL == normalizedURL {
                return .exact(identity)
            }
            // Recent macOS versions can return DefaultDesktop.heic even when
            // another wallpaper is selected. A URL alone is not proof of identity.
            guard allowUnverifiedDesktopImageURL else { return .ambiguous }
            return .exact(identityForDesktopImageURL(normalizedURL, displayUUID: displayUUID))
        }

        if let currentDesktopImageURL {
            let imageCandidates = uniqueCandidates.filter { $0.kind == .staticImage }
            let normalizedURL = currentDesktopImageURL.standardizedFileURL
            let matchingCandidates = unique(imageCandidates.filter { identity in
                guard case let .image(url) = identity.source else { return false }
                return url.standardizedFileURL == normalizedURL
            })
            if matchingCandidates.count == 1, let identity = matchingCandidates.first {
                return .exact(identity)
            }

            if uniqueCandidates.isEmpty && allowUnverifiedDesktopImageURL {
                return .exact(identityForDesktopImageURL(normalizedURL, displayUUID: displayUUID))
            }
        }

        return uniqueCandidates.isEmpty ? .unavailable : .ambiguous
    }

    private static func entry(
        for displayUUID: String,
        displays: [String: Any]?,
        defaultEntry: Any?
    ) -> [String: Any]? {
        (displays?[displayUUID] as? [String: Any]) ?? (defaultEntry as? [String: Any])
    }

    private static func candidates(
        in entry: [String: Any]?,
        displayUUID: String
    ) -> [WallpaperIdentity] {
        guard let desktop = (entry?["Desktop"] ?? entry?["Linked"]) as? [String: Any],
              let content = desktop["Content"] as? [String: Any],
              let choices = content["Choices"] as? [[String: Any]],
              !choices.isEmpty else {
            return []
        }

        let encodedOptions = content["EncodedOptionValues"] as? Data ?? Data()
        return choices.compactMap { choice in
            guard let provider = choice["Provider"] as? String else { return nil }
            let configuration = choice["Configuration"] as? Data ?? Data()
            let filesData = binaryPropertyListData(choice["Files"])
            let parsedConfiguration = propertyListDictionary(configuration)
            let source = wallpaperSource(
                provider: provider,
                configuration: parsedConfiguration
            )
            let digest = digest(components: [
                Data(provider.utf8),
                configuration,
                encodedOptions,
                filesData,
                sourceVersionData(source)
            ])
            let kind = wallpaperKind(for: provider)
            return WallpaperIdentity(
                displayUUID: displayUUID,
                provider: provider,
                configurationDigest: digest,
                kind: kind,
                source: source
            )
        }
    }

    private static func sourceVersionData(_ source: WallpaperSource) -> Data {
        guard case let .image(url) = source else { return Data() }
        let values = try? url.resourceValues(forKeys: [.fileSizeKey, .contentModificationDateKey])
        let version = "\(values?.fileSize ?? 0):\(values?.contentModificationDate?.timeIntervalSince1970 ?? 0)"
        return Data(version.utf8)
    }

    private static func wallpaperKind(for provider: String) -> WallpaperKind {
        switch provider {
        case imageProvider:
            return .staticImage
        case aerialProvider, dynamicProvider, "com.apple.wallpaper.choice.screen-saver":
            return .animated
        default:
            return .unknown
        }
    }

    private static func wallpaperSource(
        provider: String,
        configuration: [String: Any]
    ) -> WallpaperSource {
        switch provider {
        case imageProvider, dynamicProvider:
            guard let urlInfo = configuration["url"] as? [String: Any],
                  let rawURL = urlInfo["relative"] as? String else {
                return .unavailable
            }
            if let url = URL(string: rawURL), url.scheme != nil {
                guard url.isFileURL else { return .unavailable }
                return .image(url.standardizedFileURL)
            }
            return .image(URL(fileURLWithPath: rawURL).standardizedFileURL)
        case aerialProvider:
            guard let assetID = configuration["assetID"] as? String, !assetID.isEmpty else {
                return .unavailable
            }
            return .aerial(assetID: assetID)
        default:
            return .unavailable
        }
    }

    private static func identityForDesktopImageURL(
        _ url: URL,
        displayUUID: String
    ) -> WallpaperIdentity {
        let values = try? url.resourceValues(forKeys: [.fileSizeKey, .contentModificationDateKey])
        let metadata = "\(values?.fileSize ?? 0):\(values?.contentModificationDate?.timeIntervalSince1970 ?? 0)"
        return WallpaperIdentity(
            displayUUID: displayUUID,
            provider: imageProvider,
            configurationDigest: digest(components: [Data(url.path.utf8), Data(metadata.utf8)]),
            kind: .staticImage,
            source: .image(url)
        )
    }

    private static func unique(_ identities: [WallpaperIdentity]) -> [WallpaperIdentity] {
        Array(Set(identities)).sorted {
            if $0.provider != $1.provider { return $0.provider < $1.provider }
            return $0.configurationDigest < $1.configurationDigest
        }
    }

    private static func propertyListDictionary(_ data: Data) -> [String: Any] {
        guard !data.isEmpty,
              let dictionary = try? PropertyListSerialization.propertyList(
                  from: data,
                  options: [],
                  format: nil
              ) as? [String: Any] else {
            return [:]
        }
        return dictionary
    }

    private static func binaryPropertyListData(_ value: Any?) -> Data {
        guard let value,
              PropertyListSerialization.propertyList(value, isValidFor: .binary),
              let data = try? PropertyListSerialization.data(
                  fromPropertyList: value,
                  format: .binary,
                  options: 0
              ) else {
            return Data()
        }
        return data
    }

    private static func digest(components: [Data]) -> String {
        var hasher = SHA256()
        for component in components {
            hasher.update(data: component)
            hasher.update(data: Data([0]))
        }
        return hasher.finalize().map { String(format: "%02x", $0) }.joined()
    }
}

public enum WallpaperRefreshAction: Sendable, Equatable {
    case reuse
    case capture
}

public enum WallpaperRefreshPolicy {
    public static func windowShown(
        kind: WallpaperKind?,
        hasMatchingContent: Bool,
        hasSettledCapture: Bool = false
    ) -> WallpaperRefreshAction {
        (hasMatchingContent && (kind == .staticImage || (kind != nil && hasSettledCapture))) ? .reuse : .capture
    }
}
