import Foundation
import AppKit
import CoreServices

struct AppInfo: Identifiable, Equatable, Hashable {
    let name: String
    let icon: NSImage
    let url: URL

    static let transparentPlaceholderIcon: NSImage = {
        let size = NSSize(width: 1, height: 1)
        let image = NSImage(size: size)
        image.lockFocus()
        NSColor.clear.setFill()
        NSBezierPath(rect: NSRect(origin: .zero, size: size)).fill()
        image.unlockFocus()
        image.isTemplate = false
        return image
    }()

    // 使用应用路径作为稳定唯一标识
    var id: String { url.path }

    static func == (lhs: AppInfo, rhs: AppInfo) -> Bool {
        lhs.url == rhs.url
    }

    func hash(into hasher: inout Hasher) {
        hasher.combine(url.path)
    }

    // MARK: - 创建 AppInfo
    static func from(url: URL, preferredName: String? = nil, customTitle: String? = nil, loadIcon: Bool = true) -> AppInfo {
        let fallbackName = normalizeCandidate(url.deletingPathExtension().lastPathComponent)
        let bundle = Bundle(url: url)
        let localizedName = localizedAppName(for: url,
                                             preferredName: preferredName,
                                             fallbackName: fallbackName,
                                             bundle: bundle)
        let englishName = englishAppName(preferredName: preferredName,
                                         fallbackName: fallbackName,
                                         bundle: bundle)

        let shouldUseLocalized = shouldUseLocalizedTitles()
        let chosenName = shouldUseLocalized ? localizedName : englishName
        let icon: NSImage
        if loadIcon {
            icon = NSWorkspace.shared.icon(forFile: url.path)
        } else {
            icon = transparentPlaceholderIcon
        }

        if let override = customTitle.flatMap({ title -> String? in
            let normalized = normalizeCandidate(title)
            return normalized.isEmpty ? nil : normalized
        }) {
            return AppInfo(name: override, icon: icon, url: url)
        }

        return AppInfo(name: chosenName, icon: icon, url: url)
    }

    // MARK: - 获取本地化应用名
    private static func localizedAppName(for url: URL,
                                         preferredName: String?,
                                         fallbackName: String,
                                         bundle: Bundle?) -> String {
        var resolvedName: String? = nil

        func consider(_ rawValue: String?, source: String) {
            guard let rawValue = rawValue else {
                return
            }
            let normalized = normalizeCandidate(rawValue)
            if normalized.isEmpty {
                return
            }
            guard resolvedName == nil else { return }
            if normalized != fallbackName {
                resolvedName = normalized
            }
        }

        if let bundle {
            consider(bundlePreferredDisplayName(bundle), source: "BundlePreferredDisplayName")
        }

        return resolvedName ?? fallbackName
    }

    private static func englishAppName(preferredName: String?,
                                       fallbackName: String,
                                       bundle: Bundle?) -> String {
        var candidates: [String] = []

        if let bundle {
            let englishLocales = ["en", "en-US", "en-GB"]
            for locale in englishLocales {
                if let path = bundle.path(forResource: "InfoPlist",
                                           ofType: "strings",
                                           inDirectory: nil,
                                           forLocalization: locale),
                   let dict = NSDictionary(contentsOfFile: path) as? [String: String] {
                    for key in ["CFBundleDisplayName", "CFBundleName"] {
                        if let value = dict[key], !value.isEmpty {
                            candidates.append(value)
                        }
                    }
                }
            }

            for key in ["CFBundleDisplayName", "CFBundleName"] {
                if let value = bundle.infoDictionary?[key] as? String, !value.isEmpty {
                    candidates.append(value)
                }
            }
        }

        if let preferredName, !preferredName.isEmpty {
            candidates.append(preferredName)
        }

        for raw in candidates {
            let normalized = normalizeCandidate(raw)
            if !normalized.isEmpty {
                return normalized
            }
        }

        return fallbackName
    }

    private static func shouldUseLocalizedTitles() -> Bool {
        let defaults = UserDefaults.standard
        if defaults.object(forKey: "useLocalizedThirdPartyTitles") == nil {
            return true
        }
        return defaults.bool(forKey: "useLocalizedThirdPartyTitles")
    }

    private static func normalizeCandidate(_ value: String) -> String {
        var trimmed = value.trimmingCharacters(in: .whitespacesAndNewlines)
        if trimmed.lowercased().hasSuffix(".app") {
            trimmed = String(trimmed.dropLast(4))
        }
        return trimmed
    }

    private static func bundlePreferredDisplayName(_ bundle: Bundle) -> String? {
        let preferredLocales = Bundle.preferredLocalizations(from: bundle.localizations, forPreferences: userPreferredLanguages())
        if let chosen = preferredLocales.first,
           let lprojPath = bundle.path(forResource: chosen, ofType: "lproj"),
           let localizedBundle = Bundle(path: lprojPath),
           let stringsPath = localizedBundle.path(forResource: "InfoPlist", ofType: "strings"),
           let dict = NSDictionary(contentsOfFile: stringsPath) as? [String: String] {
            if let displayName = dict["CFBundleDisplayName"], !displayName.isEmpty {
                return displayName
            }
            if let bundleName = dict["CFBundleName"], !bundleName.isEmpty {
                return bundleName
            }
        }

        if let localizedInfo = bundle.localizedInfoDictionary {
            if let displayName = localizedInfo["CFBundleDisplayName"] as? String, !displayName.isEmpty {
                return displayName
            }
            if let bundleName = localizedInfo["CFBundleName"] as? String, !bundleName.isEmpty {
                return bundleName
            }
        }

        return nil
    }

    private static func userPreferredLanguages() -> [String] {
        if let languages = UserDefaults.standard.array(forKey: "AppleLanguages") as? [String], !languages.isEmpty {
            return languages
        }
        return Locale.preferredLanguages
    }
}
