import Foundation
import AppKit
import Combine
import SwiftUI
import SwiftData
import UniformTypeIdentifiers
import Carbon
import Carbon.HIToolbox

enum AppearancePreference: String, CaseIterable, Identifiable {
    case system
    case light
    case dark

    var id: String { rawValue }

    var colorScheme: ColorScheme? {
        switch self {
        case .system: return nil
        case .light: return .light
        case .dark: return .dark
        }
    }

    var nsAppearance: NSAppearance.Name? {
        switch self {
        case .system: return nil
        case .light: return .aqua
        case .dark: return .darkAqua
        }
    }

    var localizationKey: LocalizationKey {
        switch self {
        case .system: return .appearanceModeFollowSystem
        case .light: return .appearanceModeLight
        case .dark: return .appearanceModeDark
        }
    }
}


private struct GitHubRelease: Decodable {
    let tagName: String
    let htmlUrl: URL
    let body: String?

    enum CodingKeys: String, CodingKey {
        case tagName = "tag_name"
        case htmlUrl = "html_url"
        case body
    }
}

private struct SemanticVersion: Comparable, Equatable {
    private let components: [Int]

    init?(_ rawValue: String) {
        let trimmed = rawValue.trimmingCharacters(in: .whitespacesAndNewlines)
        let lower = trimmed.lowercased()
        let withoutPrefix = lower.hasPrefix("v") ? String(trimmed.dropFirst()) : trimmed
        let sanitized = withoutPrefix.split(separator: "-", maxSplits: 1, omittingEmptySubsequences: true).first ?? withoutPrefix[...]
        let parts = sanitized.split(separator: ".").map { Int($0) ?? 0 }
        guard !parts.isEmpty else { return nil }
        components = parts
    }

    static func < (lhs: SemanticVersion, rhs: SemanticVersion) -> Bool {
        let count = max(lhs.components.count, rhs.components.count)
        for index in 0..<count {
            let left = index < lhs.components.count ? lhs.components[index] : 0
            let right = index < rhs.components.count ? rhs.components[index] : 0
            if left != right { return left < right }
        }
        return false
    }
}

final class AppStore: ObservableObject {
    enum UpdateState: Equatable {
        case idle
        case checking
        case upToDate(latest: String)
        case updateAvailable(UpdateRelease)
        case failed(String)
    }

    struct UpdateRelease: Equatable {
        let version: String
        let url: URL
        let notes: String?
    }

    enum BackgroundStyle: String, CaseIterable, Identifiable {
        case blur
        case glass

        var id: String { rawValue }

        var localizationKey: LocalizationKey {
            switch self {
            case .blur: return .backgroundStyleOptionBlur
            case .glass: return .backgroundStyleOptionGlass
            }
        }
    }

    enum IconLabelFontWeightOption: String, CaseIterable, Identifiable {
        case light
        case regular
        case medium
        case semibold
        case bold

        var id: String { rawValue }

        var fontWeight: Font.Weight {
            switch self {
            case .light: return .light
            case .regular: return .regular
            case .medium: return .medium
            case .semibold: return .semibold
            case .bold: return .bold
            }
        }

        var displayName: String {
            switch self {
            case .light: return "Light"
            case .regular: return "Regular"
            case .medium: return "Medium"
            case .semibold: return "Semibold"
            case .bold: return "Bold"
            }
        }
    }

    private static let customTitlesKey = "customAppTitles"
    private static let hiddenAppsKey = "hiddenAppBundlePaths"
    private static let gridColumnsKey = "gridColumnsPerPage"
    private static let gridRowsKey = "gridRowsPerPage"
    private static let columnSpacingKey = "gridColumnSpacing"
    private static let rowSpacingKey = "gridRowSpacing"
    private static let iconLabelFontWeightKey = "iconLabelFontWeight"
    private static let showQuickRefreshButtonKey = "showQuickRefreshButton"
    private static let rememberPageKey = "rememberLastPage"
    private static let rememberedPageIndexKey = "rememberedPageIndex"
    private static let globalHotKeyKey = "globalHotKeyConfiguration"
    private static let hoverMagnificationKey = "enableHoverMagnification"
    private static let hoverMagnificationScaleKey = "hoverMagnificationScale"
    private static let activePressEffectKey = "enableActivePressEffect"
    private static let activePressScaleKey = "activePressScale"
    private static let backgroundStyleKey = "launchpadBackgroundStyle"
    private static let gameControllerEnabledKey = "gameControllerEnabled"
    private static let soundEffectsEnabledKey = "soundEffectsEnabled"
    private static let soundLaunchpadOpenKey = "soundLaunchpadOpenSound"
    private static let soundLaunchpadCloseKey = "soundLaunchpadCloseSound"
    private static let soundNavigationKey = "soundNavigationSound"
    private static let voiceFeedbackEnabledKey = "voiceFeedbackEnabled"

    private static func loadHiddenApps() -> Set<String> {
        if let array = UserDefaults.standard.array(forKey: hiddenAppsKey) as? [String] {
            return Set(array)
        }
        return []
    }

    private static func loadBackgroundStyle() -> BackgroundStyle {
        if let raw = UserDefaults.standard.string(forKey: backgroundStyleKey),
           let style = BackgroundStyle(rawValue: raw) {
            return style
        }
        return .glass
    }

    private static let minColumnsPerPage = 4
    private static let maxColumnsPerPage = 10
    private static let minRowsPerPage = 3
    private static let maxRowsPerPage = 8
    private static let minColumnSpacing: Double = 8
    private static let maxColumnSpacing: Double = 50
    private static let minRowSpacing: Double = 6
    private static let maxRowSpacing: Double = 40
    static let defaultScrollSensitivity: Double = 0.2
    static var gridColumnRange: ClosedRange<Int> { minColumnsPerPage...maxColumnsPerPage }
    static var gridRowRange: ClosedRange<Int> { minRowsPerPage...maxRowsPerPage }
    static var columnSpacingRange: ClosedRange<Double> { minColumnSpacing...maxColumnSpacing }
    static var rowSpacingRange: ClosedRange<Double> { minRowSpacing...maxRowSpacing }
    static let hoverMagnificationRange: ClosedRange<Double> = 1.0...1.4
    private static let defaultHoverMagnificationScale: Double = 1.2
    static let activePressScaleRange: ClosedRange<Double> = 0.85...1.0
    private static let defaultActivePressScale: Double = 0.92
    static let folderPopoverWidthRange: ClosedRange<Double> = 0.6...0.95
    static let folderPopoverHeightRange: ClosedRange<Double> = 0.6...0.95
    private static let defaultFolderPopoverWidth: Double = 0.9
    private static let defaultFolderPopoverHeight: Double = 0.85
    private static let lastUpdateCheckKey = "lastUpdateCheckTimestamp"
    private static let automaticUpdateInterval: TimeInterval = 60 * 60 * 24
    private static let defaultLaunchpadOpenSound = "Submarine"
    private static let defaultLaunchpadCloseSound = "Glass"
    private static let defaultNavigationSound = "Tink"

    private var lastUpdateCheck: Date? {
        get {
            if let timestamp = UserDefaults.standard.object(forKey: Self.lastUpdateCheckKey) as? TimeInterval {
                return Date(timeIntervalSince1970: timestamp)
            }
            return nil
        }
        set {
            if let date = newValue {
                UserDefaults.standard.set(date.timeIntervalSince1970, forKey: Self.lastUpdateCheckKey)
            } else {
                UserDefaults.standard.removeObject(forKey: Self.lastUpdateCheckKey)
            }
        }
    }

    private static func normalizedSoundName(_ raw: String?, defaultValue: String) -> String {
        guard let raw else { return defaultValue }
        if raw.isEmpty { return "" }
        return SoundManager.isValidSystemSoundName(raw) ? raw : defaultValue
    }

    private lazy var notificationDelegate = UpdateNotificationDelegate(openHandler: { [weak self] url in
        self?.openReleaseURL(url)
    })

    struct HotKeyConfiguration: Equatable {
        let keyCode: UInt16
        let modifiersRawValue: NSEvent.ModifierFlags.RawValue

        init(keyCode: UInt16, modifierFlags: NSEvent.ModifierFlags) {
            self.keyCode = keyCode
            self.modifiersRawValue = modifierFlags.normalizedShortcutFlags.rawValue
        }

        init?(dictionary: [String: Any]) {
            guard let rawKeyCode = dictionary["keyCode"] as? Int,
                  let rawModifiers = dictionary["modifiers"] as? Int else {
                return nil
            }
            self.keyCode = UInt16(rawKeyCode)
            self.modifiersRawValue = NSEvent.ModifierFlags.RawValue(rawModifiers)
        }

        var modifierFlags: NSEvent.ModifierFlags {
            NSEvent.ModifierFlags(rawValue: modifiersRawValue).normalizedShortcutFlags
        }

        var dictionaryRepresentation: [String: Any] {
            ["keyCode": Int(keyCode), "modifiers": Int(modifiersRawValue)]
        }

        var carbonModifierFlags: UInt32 { modifierFlags.carbonFlags }
        var keyCodeUInt32: UInt32 { UInt32(keyCode) }

        var displayString: String {
            let modifierSymbols = modifierFlags.displaySymbols.joined()
            let keyName = HotKeyConfiguration.keyDisplayName(for: keyCode)
            return modifierSymbols + keyName
        }

        private static func keyDisplayName(for keyCode: UInt16) -> String {
            if let special = Self.specialKeyNames[keyCode] {
                return special
            }

            guard let layout = TISCopyCurrentKeyboardLayoutInputSource()?.takeRetainedValue(),
                  let rawPtr = TISGetInputSourceProperty(layout, kTISPropertyUnicodeKeyLayoutData) else {
                return String(format: "Key %d", keyCode)
            }

            let data = unsafeBitCast(rawPtr, to: CFData.self) as Data
            return data.withUnsafeBytes { ptr -> String in
                guard let layoutPtr = ptr.baseAddress?.assumingMemoryBound(to: UCKeyboardLayout.self) else {
                    return String(format: "Key %d", keyCode)
                }
                var keysDown: UInt32 = 0
                var chars: [UniChar] = Array(repeating: 0, count: 4)
                var length: Int = 0
                let error = UCKeyTranslate(layoutPtr,
                                           keyCode,
                                           UInt16(kUCKeyActionDisplay),
                                           0,
                                           UInt32(LMGetKbdType()),
                                           UInt32(kUCKeyTranslateNoDeadKeysBit),
                                           &keysDown,
                                           chars.count,
                                           &length,
                                           &chars)
                if error == noErr, length > 0 {
                    return String(utf16CodeUnits: chars, count: length).uppercased()
                }
                return fallbackName(for: keyCode)
            }
        }

        private static func fallbackName(for keyCode: UInt16) -> String {
            Self.specialKeyNames[keyCode] ?? String(format: "Key %d", keyCode)
        }

        private static let specialKeyNames: [UInt16: String] = [
            36: "Return",
            48: "Tab",
            49: "Space",
            51: "Delete",
            53: "Esc",
            122: "F1", 120: "F2", 99: "F3", 118: "F4", 96: "F5", 97: "F6", 98: "F7", 100: "F8",
            101: "F9", 109: "F10", 103: "F11", 111: "F12",
            123: "←",
            124: "→",
            125: "↓",
            126: "↑"
        ]
    }
    @Published var apps: [AppInfo] = []
    @Published var folders: [FolderInfo] = []
    @Published var items: [LaunchpadItem] = []
    @Published private(set) var hiddenAppPaths: Set<String> = AppStore.loadHiddenApps()

    private func persistHiddenApps(_ set: Set<String>) {
        let array = Array(set).sorted()
        UserDefaults.standard.set(array, forKey: Self.hiddenAppsKey)
    }

    private func updateHiddenAppPaths(_ changes: (inout Set<String>) -> Void) {
        var updated = hiddenAppPaths
        let original = updated
        changes(&updated)
        guard updated != original else { return }
        hiddenAppPaths = updated
        persistHiddenApps(updated)
    }

    @Published var launchpadBackgroundStyle: BackgroundStyle = AppStore.loadBackgroundStyle() {
        didSet {
            guard launchpadBackgroundStyle != oldValue else { return }
            UserDefaults.standard.set(launchpadBackgroundStyle.rawValue, forKey: Self.backgroundStyleKey)
        }
    }
    @Published var isSetting = false
    @Published var isInitialLoading = true
    @Published var currentPage = 0 {
        didSet {
            if currentPage < 0 { currentPage = 0; return }
            if rememberLastPage {
                UserDefaults.standard.set(currentPage, forKey: Self.rememberedPageIndexKey)
            }
        }
    }
    @Published var searchText: String = ""
    @Published private(set) var searchQuery: String = ""
    @Published var isStartOnLogin: Bool = false
    @Published var isFullscreenMode: Bool = false {
        didSet {
            UserDefaults.standard.set(isFullscreenMode, forKey: "isFullscreenMode")
            DispatchQueue.main.async { [weak self] in
                if let appDelegate = AppDelegate.shared {
                    appDelegate.updateWindowMode(isFullscreen: self?.isFullscreenMode ?? false)
                }
            }
            
            DispatchQueue.main.async { [weak self] in
                self?.triggerGridRefresh()
            }
        }
    }
    private static func clampColumns(_ value: Int) -> Int {
        min(max(value, minColumnsPerPage), maxColumnsPerPage)
    }

    private static func clampRows(_ value: Int) -> Int {
        min(max(value, minRowsPerPage), maxRowsPerPage)
    }

    private static func clampColumnSpacing(_ value: Double) -> Double {
        min(max(value, minColumnSpacing), maxColumnSpacing)
    }

    private static func clampRowSpacing(_ value: Double) -> Double {
        min(max(value, minRowSpacing), maxRowSpacing)
    }

    private static func clampFolderWidth(_ value: Double) -> Double {
        min(max(value, folderPopoverWidthRange.lowerBound), folderPopoverWidthRange.upperBound)
    }

    private static func clampFolderHeight(_ value: Double) -> Double {
        min(max(value, folderPopoverHeightRange.lowerBound), folderPopoverHeightRange.upperBound)
    }

    // 图标标题显示
    @Published var showLabels: Bool = {
        if UserDefaults.standard.object(forKey: "showLabels") == nil { return true }
        return UserDefaults.standard.bool(forKey: "showLabels")
    }() {
        didSet { UserDefaults.standard.set(showLabels, forKey: "showLabels") }
    }
    
    @Published var scrollSensitivity: Double {
        didSet {
            UserDefaults.standard.set(scrollSensitivity, forKey: "scrollSensitivity")
        }
    }

    @Published var gridColumnsPerPage: Int {
        didSet {
            let clamped = Self.clampColumns(gridColumnsPerPage)
            if gridColumnsPerPage != clamped {
                gridColumnsPerPage = clamped
                return
            }
            guard gridColumnsPerPage != oldValue else { return }
            UserDefaults.standard.set(gridColumnsPerPage, forKey: Self.gridColumnsKey)
            handleGridConfigurationChange()
        }
    }

    @Published var gridRowsPerPage: Int {
        didSet {
            let clamped = Self.clampRows(gridRowsPerPage)
            if gridRowsPerPage != clamped {
                gridRowsPerPage = clamped
                return
            }
            guard gridRowsPerPage != oldValue else { return }
            UserDefaults.standard.set(gridRowsPerPage, forKey: Self.gridRowsKey)
            handleGridConfigurationChange()
        }
    }

    @Published var iconColumnSpacing: Double {
        didSet {
            let clamped = Self.clampColumnSpacing(iconColumnSpacing)
            if iconColumnSpacing != clamped {
                iconColumnSpacing = clamped
                return
            }
            guard iconColumnSpacing != oldValue else { return }
            UserDefaults.standard.set(iconColumnSpacing, forKey: Self.columnSpacingKey)
            triggerGridRefresh()
        }
    }

    @Published var iconRowSpacing: Double {
        didSet {
            let clamped = Self.clampRowSpacing(iconRowSpacing)
            if iconRowSpacing != clamped {
                iconRowSpacing = clamped
                return
            }
            guard iconRowSpacing != oldValue else { return }
            UserDefaults.standard.set(iconRowSpacing, forKey: Self.rowSpacingKey)
            triggerGridRefresh()
        }
    }

    @Published var enableDropPrediction: Bool = {
        if UserDefaults.standard.object(forKey: "enableDropPrediction") == nil { return true }
        return UserDefaults.standard.bool(forKey: "enableDropPrediction")
    }() {
        didSet { UserDefaults.standard.set(enableDropPrediction, forKey: "enableDropPrediction") }
    }

    @Published var enableAnimations: Bool = {
        if UserDefaults.standard.object(forKey: "enableAnimations") == nil { return true }
        return UserDefaults.standard.bool(forKey: "enableAnimations")
    }() {
        didSet { UserDefaults.standard.set(enableAnimations, forKey: "enableAnimations") }
    }

    @Published var enableHoverMagnification: Bool = {
        if UserDefaults.standard.object(forKey: AppStore.hoverMagnificationKey) == nil { return false }
        return UserDefaults.standard.bool(forKey: AppStore.hoverMagnificationKey)
    }() {
        didSet { UserDefaults.standard.set(enableHoverMagnification, forKey: Self.hoverMagnificationKey) }
    }

    @Published var hoverMagnificationScale: Double = {
        let defaults = UserDefaults.standard
        let stored = defaults.object(forKey: AppStore.hoverMagnificationScaleKey) as? Double
        let initial = stored ?? AppStore.defaultHoverMagnificationScale
        let clamped = min(max(initial, AppStore.hoverMagnificationRange.lowerBound), AppStore.hoverMagnificationRange.upperBound)
        if stored == nil || stored != clamped {
            defaults.set(clamped, forKey: AppStore.hoverMagnificationScaleKey)
        }
        return clamped
    }() {
        didSet {
            let clamped = min(max(hoverMagnificationScale, Self.hoverMagnificationRange.lowerBound), Self.hoverMagnificationRange.upperBound)
            if hoverMagnificationScale != clamped {
                hoverMagnificationScale = clamped
                return
            }
            UserDefaults.standard.set(hoverMagnificationScale, forKey: Self.hoverMagnificationScaleKey)
        }
    }

    @Published var enableActivePressEffect: Bool = {
        if UserDefaults.standard.object(forKey: AppStore.activePressEffectKey) == nil { return false }
        return UserDefaults.standard.bool(forKey: AppStore.activePressEffectKey)
    }() {
        didSet { UserDefaults.standard.set(enableActivePressEffect, forKey: Self.activePressEffectKey) }
    }

    @Published var activePressScale: Double = {
        let defaults = UserDefaults.standard
        let stored = defaults.object(forKey: AppStore.activePressScaleKey) as? Double
        let initial = stored ?? AppStore.defaultActivePressScale
        let clamped = min(max(initial, AppStore.activePressScaleRange.lowerBound), AppStore.activePressScaleRange.upperBound)
        if stored == nil || stored != clamped {
            defaults.set(clamped, forKey: AppStore.activePressScaleKey)
        }
        return clamped
    }() {
        didSet {
            let clamped = min(max(activePressScale, Self.activePressScaleRange.lowerBound), Self.activePressScaleRange.upperBound)
            if activePressScale != clamped {
                activePressScale = clamped
                return
            }
            UserDefaults.standard.set(activePressScale, forKey: Self.activePressScaleKey)
        }
    }

    @Published var iconLabelFontSize: Double = {
        let stored = UserDefaults.standard.double(forKey: "iconLabelFontSize")
        return stored == 0 ? 11.0 : stored
    }() {
        didSet {
            UserDefaults.standard.set(iconLabelFontSize, forKey: "iconLabelFontSize")
            triggerGridRefresh()
        }
    }

    @Published var iconLabelFontWeight: IconLabelFontWeightOption = {
        let defaults = UserDefaults.standard
        if let raw = defaults.string(forKey: AppStore.iconLabelFontWeightKey),
           let value = IconLabelFontWeightOption(rawValue: raw) {
            return value
        }
        return .medium
    }() {
        didSet {
            guard iconLabelFontWeight != oldValue else { return }
            UserDefaults.standard.set(iconLabelFontWeight.rawValue, forKey: AppStore.iconLabelFontWeightKey)
            triggerGridRefresh()
        }
    }

    var iconLabelFontWeightValue: Font.Weight {
        iconLabelFontWeight.fontWeight
    }

    @Published var showQuickRefreshButton: Bool = {
        if UserDefaults.standard.object(forKey: AppStore.showQuickRefreshButtonKey) == nil { return false }
        return UserDefaults.standard.bool(forKey: AppStore.showQuickRefreshButtonKey)
    }() {
        didSet {
            guard showQuickRefreshButton != oldValue else { return }
            UserDefaults.standard.set(showQuickRefreshButton, forKey: AppStore.showQuickRefreshButtonKey)
        }
    }

    // 更新检查相关属性
    @Published var updateState: UpdateState = .idle

    @Published var autoCheckForUpdates: Bool = {
        if UserDefaults.standard.object(forKey: "autoCheckForUpdates") == nil { return true }
        return UserDefaults.standard.bool(forKey: "autoCheckForUpdates")
    }() {
        didSet {
            UserDefaults.standard.set(autoCheckForUpdates, forKey: "autoCheckForUpdates")
            if autoCheckForUpdates {
                scheduleAutomaticUpdateCheck()
            } else {
                autoCheckTimer?.cancel()
                autoCheckTimer = nil
            }
        }
    }

    @Published var animationDuration: Double = {
        let stored = UserDefaults.standard.double(forKey: "animationDuration")
        return stored == 0 ? 0.3 : stored
    }() {
        didSet { UserDefaults.standard.set(animationDuration, forKey: "animationDuration") }
    }

    @Published var useLocalizedThirdPartyTitles: Bool = {
        if UserDefaults.standard.object(forKey: "useLocalizedThirdPartyTitles") == nil { return true }
        return UserDefaults.standard.bool(forKey: "useLocalizedThirdPartyTitles")
    }() {
        didSet {
            guard oldValue != useLocalizedThirdPartyTitles else { return }
            UserDefaults.standard.set(useLocalizedThirdPartyTitles, forKey: "useLocalizedThirdPartyTitles")
            DispatchQueue.main.async { [weak self] in
                self?.refresh()
            }
        }
    }

    @Published var showFPSOverlay: Bool = {
        if UserDefaults.standard.object(forKey: "showFPSOverlay") == nil { return false }
        return UserDefaults.standard.bool(forKey: "showFPSOverlay")
    }() {
        didSet { UserDefaults.standard.set(showFPSOverlay, forKey: "showFPSOverlay") }
    }

    @Published var gameControllerEnabled: Bool = {
        if UserDefaults.standard.object(forKey: AppStore.gameControllerEnabledKey) == nil { return false }
        return UserDefaults.standard.bool(forKey: AppStore.gameControllerEnabledKey)
    }() {
        didSet {
            guard oldValue != gameControllerEnabled else { return }
            UserDefaults.standard.set(gameControllerEnabled, forKey: AppStore.gameControllerEnabledKey)
        }
    }

    @Published var soundEffectsEnabled: Bool = {
        if UserDefaults.standard.object(forKey: AppStore.soundEffectsEnabledKey) == nil { return false }
        return UserDefaults.standard.bool(forKey: AppStore.soundEffectsEnabledKey)
    }() {
        didSet {
            guard oldValue != soundEffectsEnabled else { return }
            UserDefaults.standard.set(soundEffectsEnabled, forKey: AppStore.soundEffectsEnabledKey)
        }
    }

    @Published var soundLaunchpadOpenSound: String = {
        let stored = UserDefaults.standard.string(forKey: AppStore.soundLaunchpadOpenKey)
        return AppStore.normalizedSoundName(stored, defaultValue: AppStore.defaultLaunchpadOpenSound)
    }() {
        didSet {
            UserDefaults.standard.set(soundLaunchpadOpenSound, forKey: AppStore.soundLaunchpadOpenKey)
        }
    }

    @Published var soundLaunchpadCloseSound: String = {
        let stored = UserDefaults.standard.string(forKey: AppStore.soundLaunchpadCloseKey)
        return AppStore.normalizedSoundName(stored, defaultValue: AppStore.defaultLaunchpadCloseSound)
    }() {
        didSet {
            UserDefaults.standard.set(soundLaunchpadCloseSound, forKey: AppStore.soundLaunchpadCloseKey)
        }
    }

    @Published var soundNavigationSound: String = {
        let stored = UserDefaults.standard.string(forKey: AppStore.soundNavigationKey)
        return AppStore.normalizedSoundName(stored, defaultValue: AppStore.defaultNavigationSound)
    }() {
        didSet {
            UserDefaults.standard.set(soundNavigationSound, forKey: AppStore.soundNavigationKey)
        }
    }

    @Published var voiceFeedbackEnabled: Bool = {
        if UserDefaults.standard.object(forKey: AppStore.voiceFeedbackEnabledKey) == nil { return false }
        return UserDefaults.standard.bool(forKey: AppStore.voiceFeedbackEnabledKey)
    }() {
        didSet {
            guard oldValue != voiceFeedbackEnabled else { return }
            UserDefaults.standard.set(voiceFeedbackEnabled, forKey: AppStore.voiceFeedbackEnabledKey)
            if !voiceFeedbackEnabled {
                VoiceManager.shared.stop()
            }
        }
    }

    @Published var pageIndicatorOffset: Double = {
        if UserDefaults.standard.object(forKey: "pageIndicatorOffset") == nil { return 27.0 }
        return UserDefaults.standard.double(forKey: "pageIndicatorOffset")
    }() {
        didSet {
            UserDefaults.standard.set(pageIndicatorOffset, forKey: "pageIndicatorOffset")
        }
    }

    @Published var rememberLastPage: Bool = AppStore.defaultRememberSetting() {
        didSet {
            UserDefaults.standard.set(rememberLastPage, forKey: Self.rememberPageKey)
            if rememberLastPage {
                UserDefaults.standard.set(currentPage, forKey: Self.rememberedPageIndexKey)
            } else {
                UserDefaults.standard.removeObject(forKey: Self.rememberedPageIndexKey)
            }
        }
    }

    @Published var folderPopoverWidthFactor: Double = {
        let stored = UserDefaults.standard.double(forKey: "folderPopoverWidthFactor")
        if stored == 0 { return defaultFolderPopoverWidth }
        return clampFolderWidth(stored)
    }() {
        didSet {
            let clamped = AppStore.clampFolderWidth(folderPopoverWidthFactor)
            if folderPopoverWidthFactor != clamped {
                folderPopoverWidthFactor = clamped
                return
            }
            UserDefaults.standard.set(folderPopoverWidthFactor, forKey: "folderPopoverWidthFactor")
        }
    }

    @Published var folderPopoverHeightFactor: Double = {
        let stored = UserDefaults.standard.double(forKey: "folderPopoverHeightFactor")
        if stored == 0 { return defaultFolderPopoverHeight }
        return clampFolderHeight(stored)
    }() {
        didSet {
            let clamped = AppStore.clampFolderHeight(folderPopoverHeightFactor)
            if folderPopoverHeightFactor != clamped {
                folderPopoverHeightFactor = clamped
                return
            }
            UserDefaults.standard.set(folderPopoverHeightFactor, forKey: "folderPopoverHeightFactor")
        }
    }

    @Published var appearancePreference: AppearancePreference = {
        if let raw = UserDefaults.standard.string(forKey: "appearancePreference"),
           let pref = AppearancePreference(rawValue: raw) {
            return pref
        }
        return .system
    }() {
        didSet {
            guard oldValue != appearancePreference else { return }
            UserDefaults.standard.set(appearancePreference.rawValue, forKey: "appearancePreference")
        }
    }

    private static func defaultRememberSetting() -> Bool {
        if UserDefaults.standard.object(forKey: rememberPageKey) == nil { return false }
        return UserDefaults.standard.bool(forKey: rememberPageKey)
    }

    @Published var globalHotKey: HotKeyConfiguration? = AppStore.loadHotKeyConfiguration() ?? HotKeyConfiguration(keyCode: 118, modifierFlags: []) {
        didSet {
            persistHotKeyConfiguration()
            AppDelegate.shared?.updateGlobalHotKey(configuration: globalHotKey)
        }
    }

    @Published private(set) var currentAppIcon: NSImage {
        didSet { applyCurrentAppIcon() }
    }

    @Published private(set) var hasCustomAppIcon: Bool

    @Published var preferredLanguage: AppLanguage = {
        if let raw = UserDefaults.standard.string(forKey: "preferredLanguage"),
           let lang = AppLanguage(rawValue: raw) {
            return lang
        }
        return .system
    }() {
        didSet { UserDefaults.standard.set(preferredLanguage.rawValue, forKey: "preferredLanguage") }
    }

    @Published private(set) var customTitles: [String: String] = AppStore.loadCustomTitles() {
        didSet { persistCustomTitles() }
    }

    // 缓存管理器
    private let cacheManager = AppCacheManager.shared
    
    // 文件夹相关状态
    @Published var openFolder: FolderInfo? = nil
    @Published var isDragCreatingFolder = false
    @Published var folderCreationTarget: AppInfo? = nil
    @Published var openFolderActivatedByKeyboard: Bool = false
    @Published var isFolderNameEditing: Bool = false
    @Published var handoffDraggingApp: AppInfo? = nil
    @Published var handoffDragScreenLocation: CGPoint? = nil
    
    // 触发器
    @Published var folderUpdateTrigger: UUID = UUID()
    @Published var gridRefreshTrigger: UUID = UUID()
    
    var modelContext: ModelContext?

    // MARK: - Auto rescan (FSEvents)
    private var fsEventStream: FSEventStreamRef?
    private var pendingChangedAppPaths: Set<String> = []
    private var pendingForceFullScan: Bool = false
    private let fullRescanThreshold: Int = 50

    // 状态标记
    private var hasPerformedInitialScan: Bool = false
    private var cancellables: Set<AnyCancellable> = []
    private var hasAppliedOrderFromStore: Bool = false
    
    // 后台刷新队列与节流
    private let refreshQueue = DispatchQueue(label: "app.store.refresh", qos: .userInitiated)
    private var gridRefreshWorkItem: DispatchWorkItem?
    private var iconScaleWorkItem: DispatchWorkItem?
    private var rescanWorkItem: DispatchWorkItem?
    private var customTitleRefreshWorkItem: DispatchWorkItem?
    private let fsEventsQueue = DispatchQueue(label: "app.store.fsevents")
    private let customIconFileURL: URL
    private let defaultAppIcon: NSImage
    private var autoCheckTimer: DispatchSourceTimer?
    
    // 计算属性
    private var itemsPerPage: Int { gridColumnsPerPage * gridRowsPerPage }
    


    private let applicationSearchPaths: [String] = [
        "/Applications",
        "\(NSHomeDirectory())/Applications",
        "/System/Applications",
        "/System/Cryptexes/App/System/Applications"
    ]

    init() {
        if UserDefaults.standard.object(forKey: "isFullscreenMode") == nil {
            self.isFullscreenMode = true // 新用户默认 Classic (Fullscreen)
            UserDefaults.standard.set(true, forKey: "isFullscreenMode")
        } else {
            self.isFullscreenMode = UserDefaults.standard.bool(forKey: "isFullscreenMode")
        }
        let defaults = UserDefaults.standard

        let shouldRememberPage = defaults.object(forKey: Self.rememberPageKey) == nil ? false : defaults.bool(forKey: Self.rememberPageKey)
        let savedPageIndex = defaults.object(forKey: Self.rememberedPageIndexKey) as? Int

        let storedSensitivity = defaults.double(forKey: "scrollSensitivity")
        self.scrollSensitivity = storedSensitivity == 0 ? Self.defaultScrollSensitivity : storedSensitivity

        let storedColumns = defaults.object(forKey: Self.gridColumnsKey) as? Int ?? 7
        let clampedColumns = Self.clampColumns(storedColumns)
        self.gridColumnsPerPage = clampedColumns
        defaults.set(clampedColumns, forKey: Self.gridColumnsKey)

        let storedRows = defaults.object(forKey: Self.gridRowsKey) as? Int ?? 5
        let clampedRows = Self.clampRows(storedRows)
        self.gridRowsPerPage = clampedRows
        defaults.set(clampedRows, forKey: Self.gridRowsKey)

        let storedColumnSpacing = defaults.object(forKey: Self.columnSpacingKey) as? Double ?? 20.0
        let clampedColumnSpacing = Self.clampColumnSpacing(storedColumnSpacing)
        self.iconColumnSpacing = clampedColumnSpacing
        defaults.set(clampedColumnSpacing, forKey: Self.columnSpacingKey)

        let storedRowSpacing = defaults.object(forKey: Self.rowSpacingKey) as? Double ?? 14.0
        let clampedRowSpacing = Self.clampRowSpacing(storedRowSpacing)
        self.iconRowSpacing = clampedRowSpacing
        defaults.set(clampedRowSpacing, forKey: Self.rowSpacingKey)
        // 读取图标缩放默认值
        if let v = UserDefaults.standard.object(forKey: "iconScale") as? Double {
            self.iconScale = v
        }
        if UserDefaults.standard.object(forKey: "enableDropPrediction") == nil {
            UserDefaults.standard.set(true, forKey: "enableDropPrediction")
        }
        if UserDefaults.standard.object(forKey: "useLocalizedThirdPartyTitles") == nil {
            UserDefaults.standard.set(true, forKey: "useLocalizedThirdPartyTitles")
        }
        if UserDefaults.standard.object(forKey: "enableAnimations") == nil {
            UserDefaults.standard.set(true, forKey: "enableAnimations")
        }
        if UserDefaults.standard.object(forKey: "iconLabelFontSize") == nil {
            UserDefaults.standard.set(11.0, forKey: "iconLabelFontSize")
        }
        if UserDefaults.standard.object(forKey: AppStore.iconLabelFontWeightKey) == nil {
            UserDefaults.standard.set(IconLabelFontWeightOption.medium.rawValue, forKey: AppStore.iconLabelFontWeightKey)
        }
        if UserDefaults.standard.object(forKey: "animationDuration") == nil {
            UserDefaults.standard.set(0.3, forKey: "animationDuration")
        }
        if UserDefaults.standard.object(forKey: "showFPSOverlay") == nil {
            UserDefaults.standard.set(false, forKey: "showFPSOverlay")
        }
        if defaults.object(forKey: "pageIndicatorOffset") == nil {
            defaults.set(27.0, forKey: "pageIndicatorOffset")
        }

        let storedDuration = UserDefaults.standard.double(forKey: "animationDuration")
        self.animationDuration = storedDuration == 0 ? 0.3 : storedDuration
        self.enableAnimations = UserDefaults.standard.object(forKey: "enableAnimations") as? Bool ?? true
        self.customIconFileURL = AppStore.customIconFileURL

        let fallbackIcon = (NSApplication.shared.applicationIconImage?.copy() as? NSImage) ?? NSImage(size: NSSize(width: 512, height: 512))
        self.defaultAppIcon = fallbackIcon
        if let storedIcon = AppStore.loadStoredAppIcon(from: customIconFileURL) {
            self.hasCustomAppIcon = true
            self.currentAppIcon = storedIcon
        } else {
            self.hasCustomAppIcon = false
            self.currentAppIcon = fallbackIcon
        }
        applyCurrentAppIcon()

        $searchText
            .debounce(for: .milliseconds(500), scheduler: DispatchQueue.main)
            .removeDuplicates()
            .sink { [weak self] value in
                self?.searchQuery = value
            }
            .store(in: &cancellables)

        searchQuery = searchText

        scheduleAutomaticUpdateCheck()

        self.rememberLastPage = shouldRememberPage
        if shouldRememberPage, let savedPageIndex {
            self.currentPage = max(0, savedPageIndex)
        }
    }

    private static func loadCustomTitles() -> [String: String] {
        guard let raw = UserDefaults.standard.dictionary(forKey: AppStore.customTitlesKey) else {
            return [:]
        }

        var result: [String: String] = [:]
        for (key, value) in raw {
            guard let stringValue = value as? String else { continue }
            let trimmed = stringValue.trimmingCharacters(in: .whitespacesAndNewlines)
            if !trimmed.isEmpty {
                result[key] = trimmed
            }
        }
        return result
    }

    private static func loadHotKeyConfiguration() -> HotKeyConfiguration? {
        guard let dict = UserDefaults.standard.dictionary(forKey: globalHotKeyKey) else { return nil }
        return HotKeyConfiguration(dictionary: dict)
    }

    private func persistCustomTitles() {
        let sanitized = customTitles.reduce(into: [String: String]()) { partialResult, entry in
            let trimmed = entry.value.trimmingCharacters(in: .whitespacesAndNewlines)
            if !trimmed.isEmpty {
                partialResult[entry.key] = trimmed
            }
        }

        if sanitized.isEmpty {
            UserDefaults.standard.removeObject(forKey: AppStore.customTitlesKey)
        } else {
            UserDefaults.standard.set(sanitized, forKey: AppStore.customTitlesKey)
        }
    }

    private func persistHotKeyConfiguration() {
        let defaults = UserDefaults.standard
        if let config = globalHotKey {
            defaults.set(config.dictionaryRepresentation, forKey: Self.globalHotKeyKey)
        } else {
            defaults.removeObject(forKey: Self.globalHotKeyKey)
        }
    }


    // 图标缩放（相对于格子）：默认 0.95，范围建议 0.8~1.1
    @Published var iconScale: Double = 0.95 {
        didSet {
            UserDefaults.standard.set(iconScale, forKey: "iconScale")
            iconScaleWorkItem?.cancel()
            let work = DispatchWorkItem { [weak self] in self?.triggerGridRefresh() }
            iconScaleWorkItem = work
            DispatchQueue.main.asyncAfter(deadline: .now() + 0.08, execute: work)
        }
    }

    func configure(modelContext: ModelContext) {
        self.modelContext = modelContext
        
        // 立即尝试加载持久化数据（如果已有数据）——不要过早设置标记，等待加载完成时设置
        if !hasAppliedOrderFromStore {
            loadAllOrder()
        }
        
        $apps
            .map { !$0.isEmpty }
            .removeDuplicates()
            .filter { $0 }
            .sink { [weak self] _ in
                guard let self else { return }
                if !self.hasAppliedOrderFromStore {
                    self.loadAllOrder()
                }
            }
            .store(in: &cancellables)
        
        // 监听items变化，自动保存排序
        $items
            .debounce(for: .seconds(0.5), scheduler: DispatchQueue.main)
            .sink { [weak self] _ in
                guard let self = self, !self.items.isEmpty else { return }
                // 延迟保存，避免频繁保存
                DispatchQueue.main.asyncAfter(deadline: .now() + 0.1) {
                    self.saveAllOrder()
                }
            }
            .store(in: &cancellables)
    }

    // MARK: - Order Persistence
    func applyOrderAndFolders() {
        self.loadAllOrder()
    }

    // MARK: - Initial scan (once)
    func performInitialScanIfNeeded() {
        // 先尝试加载持久化数据，避免被扫描覆盖（不提前设置标记）
        if !hasAppliedOrderFromStore {
            loadAllOrder()
        }
        
        // 然后进行扫描，但保持现有顺序
        hasPerformedInitialScan = true
        scanApplicationsWithOrderPreservation()
        
        // 扫描完成后生成缓存
        DispatchQueue.main.asyncAfter(deadline: .now() + 0.1) { [weak self] in
            self?.generateCacheAfterScan()
        }
    }

    func scanApplications(loadPersistedOrder: Bool = true) {
        DispatchQueue.global(qos: .userInitiated).async {
            var found: [AppInfo] = []
            var seenPaths = Set<String>()

            for path in self.applicationSearchPaths {
                let url = URL(fileURLWithPath: path)
                
                if let enumerator = FileManager.default.enumerator(
                    at: url,
                    includingPropertiesForKeys: [.isDirectoryKey],
                    options: [.skipsHiddenFiles, .skipsPackageDescendants]
                ) {
                    for case let item as URL in enumerator {
                        let resolved = item.resolvingSymlinksInPath()
                        guard resolved.pathExtension == "app",
                              self.isValidApp(at: resolved),
                              !self.isInsideAnotherApp(resolved) else { continue }
                        if !seenPaths.contains(resolved.path) {
                            seenPaths.insert(resolved.path)
                            found.append(self.appInfo(from: resolved))
                        }
                    }
                }
            }

            let sorted = found.sorted { $0.name.localizedCaseInsensitiveCompare($1.name) == .orderedAscending }
            DispatchQueue.main.async {
                self.apps = sorted
                self.pruneHiddenAppsFromAppList()
                if loadPersistedOrder {
                    self.rebuildItems()
                    self.loadAllOrder()
                } else {
                    self.items = self.filteredItemsRemovingHidden(from: sorted.map { .app($0) })
                    self.saveAllOrder()
                }
                
                // 扫描完成后生成缓存
                self.generateCacheAfterScan()
            }
        }
    }
    
    /// 智能扫描应用：保持现有排序，新增应用放到最后，缺失应用移除，自动页面内补位
    func scanApplicationsWithOrderPreservation() {
        DispatchQueue.global(qos: .userInitiated).async {
            var found: [AppInfo] = []
            var seenPaths = Set<String>()

            // 使用并发队列加速扫描
            let scanQueue = DispatchQueue(label: "app.scan", attributes: .concurrent)
            let group = DispatchGroup()
            let lock = NSLock()
            
            // 扫描所有应用
            for path in self.applicationSearchPaths {
                group.enter()
                scanQueue.async {
                    let url = URL(fileURLWithPath: path)
                    
                    if let enumerator = FileManager.default.enumerator(
                        at: url,
                        includingPropertiesForKeys: [.isDirectoryKey],
                        options: [.skipsHiddenFiles, .skipsPackageDescendants]
                    ) {
                        var localFound: [AppInfo] = []
                        var localSeenPaths = Set<String>()
                        
                        for case let item as URL in enumerator {
                            let resolved = item.resolvingSymlinksInPath()
                            guard resolved.pathExtension == "app",
                                  self.isValidApp(at: resolved),
                                  !self.isInsideAnotherApp(resolved) else { continue }
                            if !localSeenPaths.contains(resolved.path) {
                                localSeenPaths.insert(resolved.path)
                                localFound.append(self.appInfo(from: resolved))
                            }
                        }
                        
                        // 线程安全地合并结果
                        lock.lock()
                        found.append(contentsOf: localFound)
                        seenPaths.formUnion(localSeenPaths)
                        lock.unlock()
                    }
                    group.leave()
                }
            }
            
            group.wait()
            
            // 去重和排序 - 使用更安全的方法
            var uniqueApps: [AppInfo] = []
            var uniqueSeenPaths = Set<String>()
            
            for app in found {
                if !uniqueSeenPaths.contains(app.url.path) {
                    uniqueSeenPaths.insert(app.url.path)
                    uniqueApps.append(app)
                }
            }
            
            // 保持现有应用的顺序，只对新增应用按名称排序
            var newApps: [AppInfo] = []
            var existingAppPaths = Set<String>()
            let refreshedMap = Dictionary(uniqueKeysWithValues: uniqueApps.map { ($0.url.path, $0) })

            for app in self.apps {
                guard let refreshed = refreshedMap[app.url.path] else { continue }
                newApps.append(refreshed)
                existingAppPaths.insert(app.url.path)
            }

            let newAppPaths = uniqueApps.filter { !existingAppPaths.contains($0.url.path) }
            let sortedNewApps = newAppPaths.sorted { $0.name.localizedCaseInsensitiveCompare($1.name) == .orderedAscending }
            newApps.append(contentsOf: sortedNewApps)
            
            DispatchQueue.main.async {
                self.processScannedApplications(newApps)
                
                // 扫描完成后生成缓存
                self.generateCacheAfterScan()
            }
        }
    }
    
    /// 手动触发完全重新扫描（用于设置中的手动刷新）
    func forceFullRescan() {
        // 清除缓存
        cacheManager.clearAllCaches()
        
        hasPerformedInitialScan = false
        scanApplicationsWithOrderPreservation()
    }
    
    /// 处理扫描到的应用，智能匹配现有排序
    private func processScannedApplications(_ newApps: [AppInfo]) {
        // 保存当前 items 的顺序和结构
        let currentItems = self.items
        
        // 创建新应用列表，但保持现有顺序
        var updatedApps: [AppInfo] = []
        var newAppsToAdd: [AppInfo] = []
        let freshMap: [String: AppInfo] = Dictionary(uniqueKeysWithValues: newApps.map { ($0.url.path, $0) })
        
        // 第一步：保持现有顺序，同时用最新扫描结果刷新应用信息
        for app in self.apps {
            if let refreshed = freshMap[app.url.path] {
                updatedApps.append(refreshed)
            } else {
                // 应用已删除，从所有相关位置移除
                self.removeDeletedApp(app)
            }
        }
        
        // 同步更新文件夹中的应用对象，确保名称/图标及时刷新
        for folderIndex in folders.indices {
            let refreshedApps = folders[folderIndex].apps.compactMap { freshMap[$0.url.path] }
            if refreshedApps.isEmpty {
                folders[folderIndex].apps.removeAll()
            } else if refreshedApps.count != folders[folderIndex].apps.count {
                folders[folderIndex].apps = refreshedApps
            } else {
                folders[folderIndex].apps = refreshedApps
            }
        }
        folders.removeAll { $0.apps.isEmpty }
        
        // 第二步：找出新增的应用（顺序保持与扫描结果一致）
        let existingPaths = Set(updatedApps.map { $0.url.path })
        for newApp in newApps where !existingPaths.contains(newApp.url.path) {
            newAppsToAdd.append(newApp)
        }

        // 第三步：将新增应用添加到末尾，保持现有应用顺序不变
        updatedApps.append(contentsOf: newAppsToAdd)

        // 更新应用列表
        self.apps = updatedApps
        pruneHiddenAppsFromAppList()
        
        // 第四步：智能重建项目列表，保持用户排序
        self.smartRebuildItemsWithOrderPreservation(currentItems: currentItems, newApps: newAppsToAdd)
        
        // 第五步：自动页面内补位
        self.compactItemsWithinPages()
        
        // 第六步：保存新的顺序
        self.saveAllOrder()
        
        // 触发界面更新
        self.triggerFolderUpdate()
        self.triggerGridRefresh()
    }
    
    /// 移除已删除的应用
    private func removeDeletedApp(_ deletedApp: AppInfo) {
        // 从文件夹中移除
        for folderIndex in self.folders.indices {
            self.folders[folderIndex].apps.removeAll { $0 == deletedApp }
        }
        
        // 清理空文件夹
        self.folders.removeAll { $0.apps.isEmpty }
        
        // 从顶层项目中移除，替换为空槽位
        for itemIndex in self.items.indices {
            if case let .app(app) = self.items[itemIndex], app == deletedApp {
                self.items[itemIndex] = .empty(UUID().uuidString)
            }
        }
    }
    
    
    /// 严格保持现有顺序的重建方法
    private func rebuildItemsWithStrictOrderPreservation(currentItems: [LaunchpadItem]) {
        
        var newItems: [LaunchpadItem] = []
        let appsInFolders = Set(self.folders.flatMap { $0.apps })
        
        // 严格保持现有项目的顺序和位置
        for (_, item) in currentItems.enumerated() {
            switch item {
            case .folder(let folder):
                // 检查文件夹是否仍然存在
                if self.folders.contains(where: { $0.id == folder.id }) {
                    // 更新文件夹引用，保持原有位置
                    if let updatedFolder = self.folders.first(where: { $0.id == folder.id }) {
                        newItems.append(.folder(updatedFolder))
                    } else {
                        // 文件夹被删除，保持空槽位
                        newItems.append(.empty(UUID().uuidString))
                    }
                } else {
                    // 文件夹被删除，保持空槽位
                    newItems.append(.empty(UUID().uuidString))
                }
                
            case .app(let app):
                // 检查应用是否仍然存在
                if self.apps.contains(where: { $0.url.path == app.url.path }) {
                    if !appsInFolders.contains(app) {
                        // 应用仍然存在且不在文件夹中，保持原有位置
                        newItems.append(.app(app))
                    } else {
                        // 应用现在在文件夹中，保持空槽位
                        newItems.append(.empty(UUID().uuidString))
                    }
                } else {
                    // 应用已删除，保持空槽位
                    newItems.append(.empty(UUID().uuidString))
                }
                
            case .empty(let token):
                // 保持空槽位，维持页面布局
                newItems.append(.empty(token))
            }
        }
        
        // 添加新增的自由应用（不在任何文件夹中）到最后一页的最后面
        let existingAppPaths = Set(newItems.compactMap { item in
            if case let .app(app) = item { return app.url.path } else { return nil }
        })
        
        let newFreeApps = self.apps.filter { app in
            !appsInFolders.contains(app) && !existingAppPaths.contains(app.url.path)
        }
        
        if !newFreeApps.isEmpty {
            var pendingApps = newFreeApps
            let itemsPerPage = self.itemsPerPage

            if newItems.count > 0 {
                let lastPageStart = ((newItems.count - 1) / itemsPerPage) * itemsPerPage
                let lastPageIndices = Array(lastPageStart..<newItems.count)
                let emptyIndices = lastPageIndices.filter { index in
                    if case .empty = newItems[index] { return true }
                    return false
                }
                let fillCount = min(pendingApps.count, emptyIndices.count)
                for i in 0..<fillCount {
                    newItems[emptyIndices[i]] = .app(pendingApps.removeFirst())
                }
            }

            if !pendingApps.isEmpty {
                let remainder = newItems.count % itemsPerPage
                if remainder != 0 {
                    let fillCount = min(itemsPerPage - remainder, pendingApps.count)
                    for _ in 0..<fillCount {
                        newItems.append(.app(pendingApps.removeFirst()))
                    }
                }

                while !pendingApps.isEmpty {
                    for _ in 0..<itemsPerPage {
                        if pendingApps.isEmpty {
                            newItems.append(.empty(UUID().uuidString))
                        } else {
                            newItems.append(.app(pendingApps.removeFirst()))
                        }
                    }
                }
            }
        }

        self.items = filteredItemsRemovingHidden(from: newItems)
    }
    
    /// 智能重建项目列表，保持用户排序
    private func smartRebuildItemsWithOrderPreservation(currentItems: [LaunchpadItem], newApps: [AppInfo]) {
        
        // 保存当前的持久化数据，但不立即加载（避免覆盖现有顺序）
        let hasPersistedData = self.hasPersistedOrderData()
        
        if hasPersistedData {
            
            // 智能合并现有顺序和持久化数据
            self.mergeCurrentOrderWithPersistedData(currentItems: currentItems, newApps: newApps, loadPersistedFolders: true)
        } else {
            
            // 没有持久化数据时，直接基于当前顺序合并
            self.mergeCurrentOrderWithPersistedData(currentItems: currentItems, newApps: newApps, loadPersistedFolders: false)
        }
        
    }
    
    /// 检查是否有持久化数据
    private func hasPersistedOrderData() -> Bool {
        guard let modelContext = self.modelContext else { return false }
        
        do {
            let pageEntries = try modelContext.fetch(FetchDescriptor<PageEntryData>())
            let topItems = try modelContext.fetch(FetchDescriptor<TopItemData>())
            return !pageEntries.isEmpty || !topItems.isEmpty
        } catch {
            return false
        }
    }
    
    /// 智能合并现有顺序和持久化数据
    private func mergeCurrentOrderWithPersistedData(currentItems: [LaunchpadItem], newApps: [AppInfo], loadPersistedFolders: Bool = true) {
        
        // 保存当前的项目顺序
        let currentOrder = currentItems
        
        // 加载持久化数据，但只更新文件夹信息
        if loadPersistedFolders {
            self.loadFoldersFromPersistedData()
        }
        
        // 重建项目列表，严格保持现有顺序
        var newItems: [LaunchpadItem] = []
        let appsInFolders = Set(self.folders.flatMap { $0.apps })
        let refreshedAppsByPath = Dictionary(uniqueKeysWithValues: self.apps.map { ($0.url.path, $0) })

        // 第一步：处理现有项目，保持顺序
        for (_, item) in currentOrder.enumerated() {
            switch item {
            case .folder(let folder):
                // 检查文件夹是否仍然存在
                if self.folders.contains(where: { $0.id == folder.id }) {
                    // 更新文件夹引用，保持原有位置
                    if let updatedFolder = self.folders.first(where: { $0.id == folder.id }) {
                        newItems.append(.folder(updatedFolder))
                    } else {
                        // 文件夹被删除，保持空槽位
                        newItems.append(.empty(UUID().uuidString))
                    }
                } else {
                    // 文件夹被删除，保持空槽位
                    newItems.append(.empty(UUID().uuidString))
                }
                
            case .app(let app):
                // 检查应用是否仍然存在
                if self.apps.contains(where: { $0.url.path == app.url.path }) {
                    if !appsInFolders.contains(app) {
                        // 应用仍然存在且不在文件夹中，更新为最新信息
                        let updatedApp = refreshedAppsByPath[app.url.path] ?? app
                        newItems.append(.app(updatedApp))
                    } else {
                        // 应用现在在文件夹中，保持空槽位
                        newItems.append(.empty(UUID().uuidString))
                    }
                } else {
                    // 应用已删除，保持空槽位
                    newItems.append(.empty(UUID().uuidString))
                }
                
            case .empty(let token):
                // 保持空槽位，维持页面布局
                newItems.append(.empty(token))
            }
        }
        
        // 第二步：添加新增的自由应用（不在任何文件夹中）到最后一页的最后面
        let existingAppPaths = Set(newItems.compactMap { item in
            if case let .app(app) = item { return app.url.path } else { return nil }
        })
        
        let newFreeApps = self.apps.filter { app in
            !appsInFolders.contains(app) && !existingAppPaths.contains(app.url.path)
        }
        
        if !newFreeApps.isEmpty {
            var pendingApps = newFreeApps
            let itemsPerPage = self.itemsPerPage

            if newItems.count > 0 {
                let lastPageStart = ((newItems.count - 1) / itemsPerPage) * itemsPerPage
                let lastPageIndices = Array(lastPageStart..<newItems.count)
                let emptyIndices = lastPageIndices.filter { index in
                    if case .empty = newItems[index] { return true }
                    return false
                }
                let fillCount = min(pendingApps.count, emptyIndices.count)
                for i in 0..<fillCount {
                    newItems[emptyIndices[i]] = .app(pendingApps.removeFirst())
                }
            }

            if !pendingApps.isEmpty {
                let remainder = newItems.count % itemsPerPage
                if remainder != 0 {
                    let fillCount = min(itemsPerPage - remainder, pendingApps.count)
                    for _ in 0..<fillCount {
                        newItems.append(.app(pendingApps.removeFirst()))
                    }
                }

                while !pendingApps.isEmpty {
                    for _ in 0..<itemsPerPage {
                        if pendingApps.isEmpty {
                            newItems.append(.empty(UUID().uuidString))
                        } else {
                            newItems.append(.app(pendingApps.removeFirst()))
                        }
                    }
                }
            }
        }
        
        self.items = filteredItemsRemovingHidden(from: newItems)

    }
    
    /// 只加载文件夹信息，不重建项目顺序
    private func loadFoldersFromPersistedData() {
        guard let modelContext = self.modelContext else { return }
        
        do {
            // 尝试从新的"页-槽位"模型读取文件夹信息
            let saved = try modelContext.fetch(FetchDescriptor<PageEntryData>(
                sortBy: [SortDescriptor(\.pageIndex, order: .forward), SortDescriptor(\.position, order: .forward)]
            ))
            
            if !saved.isEmpty {
                // 构建文件夹
                var folderMap: [String: FolderInfo] = [:]
                var foldersInOrder: [FolderInfo] = []
                
                for row in saved where row.kind == "folder" {
                    guard let fid = row.folderId else { continue }
                    if folderMap[fid] != nil { continue }
                    
                    let folderApps: [AppInfo] = row.appPaths.compactMap { path in
                        if let existing = apps.first(where: { $0.url.path == path }) {
                            return existing
                        }
                        let url = URL(fileURLWithPath: path)
                        guard FileManager.default.fileExists(atPath: url.path) else { return nil }
                        return self.appInfo(from: url)
                    }
                    
                    let folder = FolderInfo(id: fid, name: row.folderName ?? "Untitled", apps: folderApps, createdAt: row.createdAt)
                    folderMap[fid] = folder
                    foldersInOrder.append(folder)
                }
                
                self.folders = self.sanitizedFolders(foldersInOrder)
            }
        } catch {
        }
    }

    deinit {
        autoCheckTimer?.cancel()
        stopAutoRescan()
    }

    // MARK: - FSEvents wiring
    func startAutoRescan() {
        guard fsEventStream == nil else { return }

        let pathsToWatch: [String] = applicationSearchPaths
        var context = FSEventStreamContext(
            version: 0,
            info: UnsafeMutableRawPointer(Unmanaged.passUnretained(self).toOpaque()),
            retain: nil,
            release: nil,
            copyDescription: nil
        )

        let callback: FSEventStreamCallback = { (_, clientInfo, numEvents, eventPaths, eventFlags, _) in
            guard let info = clientInfo else { return }
            let appStore = Unmanaged<AppStore>.fromOpaque(info).takeUnretainedValue()

            guard numEvents > 0 else {
                appStore.handleFSEvents(paths: [], flagsPointer: eventFlags, count: 0)
                return
            }

            // With kFSEventStreamCreateFlagUseCFTypes, eventPaths is a CFArray of CFString
            let cfArray = Unmanaged<CFArray>.fromOpaque(eventPaths).takeUnretainedValue()
            let nsArray = cfArray as NSArray
            guard let pathsArray = nsArray as? [String] else { return }

            appStore.handleFSEvents(paths: pathsArray, flagsPointer: eventFlags, count: numEvents)
        }

        let flags = FSEventStreamCreateFlags(kFSEventStreamCreateFlagFileEvents | kFSEventStreamCreateFlagNoDefer | kFSEventStreamCreateFlagUseCFTypes)
        let latency: CFTimeInterval = 0.0

        guard let stream = FSEventStreamCreate(
            kCFAllocatorDefault,
            callback,
            &context,
            pathsToWatch as CFArray,
            FSEventStreamEventId(kFSEventStreamEventIdSinceNow),
            latency,
            flags
        ) else {
            return
        }

        fsEventStream = stream
        FSEventStreamSetDispatchQueue(stream, fsEventsQueue)
        FSEventStreamStart(stream)
    }

    func stopAutoRescan() {
        guard let stream = fsEventStream else { return }
        FSEventStreamStop(stream)
        FSEventStreamInvalidate(stream)
        FSEventStreamRelease(stream)
        fsEventStream = nil
    }

    private func handleFSEvents(paths: [String], flagsPointer: UnsafePointer<FSEventStreamEventFlags>?, count: Int) {
        let maxCount = min(paths.count, count)
        var localForceFull = false
        
        for i in 0..<maxCount {
            let rawPath = paths[i]
            let flags = flagsPointer?[i] ?? 0

            let created = (flags & FSEventStreamEventFlags(kFSEventStreamEventFlagItemCreated)) != 0
            let removed = (flags & FSEventStreamEventFlags(kFSEventStreamEventFlagItemRemoved)) != 0
            let renamed = (flags & FSEventStreamEventFlags(kFSEventStreamEventFlagItemRenamed)) != 0
            let modified = (flags & FSEventStreamEventFlags(kFSEventStreamEventFlagItemModified)) != 0
            let isDir = (flags & FSEventStreamEventFlags(kFSEventStreamEventFlagItemIsDir)) != 0

            if isDir && (created || removed || renamed), applicationSearchPaths.contains(where: { rawPath.hasPrefix($0) }) {
                localForceFull = true
                break
            }

            guard let appBundlePath = self.canonicalAppBundlePath(for: rawPath) else { continue }
            if created || removed || renamed || modified {
                pendingChangedAppPaths.insert(appBundlePath)
            }
        }

        if localForceFull { pendingForceFullScan = true }
        scheduleRescan()
    }

    private func scheduleRescan() {
        // 轻微防抖，避免频繁FSEvents触发造成主线程压力
        rescanWorkItem?.cancel()
        let work = DispatchWorkItem { [weak self] in self?.performImmediateRefresh() }
        rescanWorkItem = work
        DispatchQueue.main.asyncAfter(deadline: .now() + 0.2, execute: work)
    }

    private func performImmediateRefresh() {
        if pendingForceFullScan || pendingChangedAppPaths.count > fullRescanThreshold {
            pendingForceFullScan = false
            pendingChangedAppPaths.removeAll()
            scanApplications()
            return
        }
        
        let changed = pendingChangedAppPaths
        pendingChangedAppPaths.removeAll()
        
        if !changed.isEmpty {
            applyIncrementalChanges(for: changed)
        }
    }


    private func applyIncrementalChanges(for changedPaths: Set<String>) {
        guard !changedPaths.isEmpty else { return }
        
        // 将磁盘与图标解析放到后台，主线程仅应用结果，减少卡顿
        let snapshotApps = self.apps
        refreshQueue.async { [weak self] in
            guard let self else { return }
            
            enum PendingChange {
                case insert(AppInfo)
                case update(AppInfo)
                case remove(String) // path
            }
            var changes: [PendingChange] = []
            var pathToIndex: [String: Int] = [:]
            for (idx, app) in snapshotApps.enumerated() { pathToIndex[app.url.path] = idx }
            
            for path in changedPaths {
                let url = URL(fileURLWithPath: path).resolvingSymlinksInPath()
                let exists = FileManager.default.fileExists(atPath: url.path)
                let valid = exists && self.isValidApp(at: url) && !self.isInsideAnotherApp(url)
                if valid {
                    let info = self.appInfo(from: url)
                    if pathToIndex[url.path] != nil {
                        changes.append(.update(info))
                    } else {
                        changes.append(.insert(info))
                    }
                } else {
                    changes.append(.remove(url.path))
                }
            }
            
            DispatchQueue.main.async { [weak self] in
                guard let self else { return }
                
                // 应用删除
                if changes.contains(where: { if case .remove = $0 { return true } else { return false } }) {
                    var indicesToRemove: [Int] = []
                    var map: [String: Int] = [:]
                    for (idx, app) in self.apps.enumerated() { map[app.url.path] = idx }
                    for change in changes {
                        if case .remove(let path) = change, let idx = map[path] {
                            indicesToRemove.append(idx)
                        }
                    }
                    for idx in indicesToRemove.sorted(by: >) {
                        let removed = self.apps.remove(at: idx)
                        for fIdx in self.folders.indices { self.folders[fIdx].apps.removeAll { $0 == removed } }
                        if !self.items.isEmpty {
                            for i in 0..<self.items.count {
                                if case let .app(a) = self.items[i], a == removed { self.items[i] = .empty(UUID().uuidString) }
                            }
                        }
                    }
                    self.compactItemsWithinPages()
                    self.rebuildItems()
                }
                
                // 应用更新
                let updates: [AppInfo] = changes.compactMap { if case .update(let info) = $0 { return info } else { return nil } }
                if !updates.isEmpty {
                    var map: [String: Int] = [:]
                    for (idx, app) in self.apps.enumerated() { map[app.url.path] = idx }
                    for info in updates {
                        if let idx = map[info.url.path], self.apps.indices.contains(idx) { self.apps[idx] = info }
                        for fIdx in self.folders.indices {
                            for aIdx in self.folders[fIdx].apps.indices where self.folders[fIdx].apps[aIdx].url.path == info.url.path {
                                self.folders[fIdx].apps[aIdx] = info
                            }
                        }
                        for iIdx in self.items.indices {
                            if case .app(let a) = self.items[iIdx], a.url.path == info.url.path { self.items[iIdx] = .app(info) }
                        }
                    }
                    self.rebuildItems()
                }
                
                // 新增应用
                let inserts: [AppInfo] = changes.compactMap { if case .insert(let info) = $0 { return info } else { return nil } }
                if !inserts.isEmpty {
                    self.apps.append(contentsOf: inserts)
                    self.apps.sort { $0.name.localizedCaseInsensitiveCompare($1.name) == .orderedAscending }
                    self.rebuildItems()
                }
                
                // 刷新与持久化
                self.triggerFolderUpdate()
                self.triggerGridRefresh()
                self.saveAllOrder()
                self.updateCacheAfterChanges()
            }
        }
    }

    private func canonicalAppBundlePath(for rawPath: String) -> String? {
        guard let range = rawPath.range(of: ".app") else { return nil }
        let end = rawPath.index(range.lowerBound, offsetBy: 4)
        let bundlePath = String(rawPath[..<end])
        return bundlePath
    }

    private func isInsideAnotherApp(_ url: URL) -> Bool {
        let appCount = url.pathComponents.filter { $0.hasSuffix(".app") }.count
        return appCount > 1
    }

    private func isValidApp(at url: URL) -> Bool {
        FileManager.default.fileExists(atPath: url.path) &&
        NSWorkspace.shared.isFilePackage(atPath: url.path)
    }

    private func appInfo(from url: URL, preferredName: String? = nil) -> AppInfo {
        AppInfo.from(url: url, preferredName: preferredName, customTitle: customTitles[url.path])
    }
    
    // MARK: - 文件夹管理
    func createFolder(with apps: [AppInfo], name: String = "Untitled") -> FolderInfo {
        return createFolder(with: apps, name: name, insertAt: nil)
    }

    func createFolder(with apps: [AppInfo], name: String = "Untitled", insertAt insertIndex: Int?) -> FolderInfo {
        let folder = FolderInfo(name: name, apps: apps)
        folders.append(folder)

        // 从应用列表中移除已添加到文件夹的应用（顶层 apps）
        for app in apps {
            if let index = self.apps.firstIndex(of: app) {
                self.apps.remove(at: index)
            }
        }

        // 在当前 items 中：将这些 app 的顶层条目替换为空槽，并在目标位置放置文件夹，保持总长度不变
        var newItems = self.items
        // 找出这些 app 的位置
        var indices: [Int] = []
        for (idx, item) in newItems.enumerated() {
            if case let .app(a) = item, apps.contains(a) { indices.append(idx) }
            if indices.count == apps.count { break }
        }
        // 将涉及的 app 槽位先置空
        for idx in indices { newItems[idx] = .empty(UUID().uuidString) }
        // 选择放置文件夹的位置：优先 insertIndex，否则用最小索引；夹紧范围并用替换而非插入
        let baseIndex = indices.min() ?? min(newItems.count - 1, max(0, insertIndex ?? (newItems.count - 1)))
        let desiredIndex = insertIndex ?? baseIndex
        let safeIndex = min(max(0, desiredIndex), max(0, newItems.count - 1))
        if newItems.isEmpty {
            newItems = [.folder(folder)]
        } else {
            newItems[safeIndex] = .folder(folder)
        }
        self.items = filteredItemsRemovingHidden(from: newItems)
        // 单页内自动补位：将该页内的空槽移到页尾
        compactItemsWithinPages()

        // 触发文件夹更新，通知所有相关视图刷新图标
        DispatchQueue.main.async { [weak self] in
            self?.triggerFolderUpdate()
        }
        
        // 触发网格视图刷新，确保界面立即更新
        triggerGridRefresh()
        
        // 刷新缓存，确保搜索时能找到新创建文件夹内的应用
        refreshCacheAfterFolderOperation()

        saveAllOrder()
        return folder
    }
    
    func addAppToFolder(_ app: AppInfo, folder: FolderInfo) {
        guard let folderIndex = folders.firstIndex(of: folder) else { return }
        
        
        // 创建新的FolderInfo实例，确保SwiftUI能够检测到变化
        var updatedFolder = folders[folderIndex]
        updatedFolder.apps.append(app)
        folders[folderIndex] = updatedFolder
        
        
        // 从应用列表中移除
        if let appIndex = apps.firstIndex(of: app) {
            apps.remove(at: appIndex)
        }
        
        // 顶层将该 app 槽位置为 empty（保持页独立）
        if let pos = items.firstIndex(of: .app(app)) {
            items[pos] = .empty(UUID().uuidString)
            // 单页内自动补位
            compactItemsWithinPages()
        } else {
            // 若未找到则回退到重建
            rebuildItems()
        }
        
        // 确保 items 中对应的文件夹条目也更新为最新内容，便于搜索立即可见
        for idx in items.indices {
            if case .folder(let f) = items[idx], f.id == updatedFolder.id {
                items[idx] = .folder(updatedFolder)
            }
        }
        
        // 立即触发文件夹更新，通知所有相关视图刷新图标和名称
        triggerFolderUpdate()
        
        // 触发网格视图刷新，确保界面立即更新
        triggerGridRefresh()
        
        // 刷新缓存，确保搜索时能找到新添加的应用
        refreshCacheAfterFolderOperation()
        
        saveAllOrder()
    }
    
    func removeAppFromFolder(_ app: AppInfo, folder: FolderInfo) {
        guard let folderIndex = folders.firstIndex(of: folder) else { return }
        
        
        // 创建新的FolderInfo实例，确保SwiftUI能够检测到变化
        var updatedFolder = folders[folderIndex]
        updatedFolder.apps.removeAll { $0 == app }
        
        
        // 如果文件夹空了，删除文件夹
        if updatedFolder.apps.isEmpty {
            folders.remove(at: folderIndex)
        } else {
            // 更新文件夹
            folders[folderIndex] = updatedFolder
        }
        
        // 同步更新 items 中的该文件夹条目，避免界面继续引用旧的文件夹内容
        for idx in items.indices {
            if case .folder(let f) = items[idx], f.id == folder.id {
                if updatedFolder.apps.isEmpty {
                    // 文件夹已空并被删除，则将该位置标记为空槽，等待后续补位
                    items[idx] = .empty(UUID().uuidString)
                } else {
                    items[idx] = .folder(updatedFolder)
                }
            }
        }
        
        // 将应用重新添加到应用列表
        apps.append(app)
        apps.sort { $0.name.localizedCaseInsensitiveCompare($1.name) == .orderedAscending }
        
        // 尝试将该应用直接放入 items 的第一个空槽，避免出现临时空白格
        if let emptyIndex = items.firstIndex(where: { if case .empty = $0 { return true } else { return false } }) {
            items[emptyIndex] = .app(app)
        }
        
        // 立即触发文件夹更新，通知所有相关视图刷新图标和名称
        triggerFolderUpdate()
        
        // 触发网格视图刷新，确保界面立即更新
        triggerGridRefresh()
        
        // 不要调用 rebuildItems()，因为它会将应用移动到末尾
        // 直接进行页面内压缩，保持应用在第一页的位置
        compactItemsWithinPages()
        
        // 刷新缓存，确保搜索时能找到从文件夹移除的应用（在重建之后刷新）
        refreshCacheAfterFolderOperation()
        
        saveAllOrder()
    }
    
    func renameFolder(_ folder: FolderInfo, newName: String) {
        guard let index = folders.firstIndex(of: folder) else { return }
        
        
        // 创建新的FolderInfo实例，确保SwiftUI能够检测到变化
        var updatedFolder = folders[index]
        updatedFolder.name = newName
        folders[index] = updatedFolder
        
        // 同步更新 items 中的该文件夹条目，避免主网格继续显示旧名称
        for idx in items.indices {
            if case .folder(let f) = items[idx], f.id == updatedFolder.id {
                items[idx] = .folder(updatedFolder)
            }
        }
        
        
        // 立即触发文件夹更新，通知所有相关视图刷新
        triggerFolderUpdate()
        
        // 触发网格视图刷新，确保界面立即更新
        triggerGridRefresh()
        
        // 刷新缓存，确保搜索功能正常工作
        refreshCacheAfterFolderOperation()
        
        rebuildItems()
        saveAllOrder()
    }
    
    // 一键重置布局：完全重新扫描应用，删除所有文件夹、排序和empty填充
    func resetLayout() {
        // 关闭打开的文件夹
        openFolder = nil
        
        // 清空所有文件夹和排序数据
        folders.removeAll()
        
        // 清除所有持久化的排序数据
        clearAllPersistedData()
        
        // 清除缓存
        cacheManager.clearAllCaches()
        
        // 重置扫描标记，强制重新扫描
        hasPerformedInitialScan = false
        
        // 清空当前项目列表
        items.removeAll()
        
        // 重新扫描应用，不加载持久化数据
        scanApplications(loadPersistedOrder: false)
        
        // 重置到第一页
        currentPage = 0
        
        // 触发文件夹更新，通知所有相关视图刷新
        triggerFolderUpdate()
        
        // 触发网格视图刷新，确保界面立即更新
        triggerGridRefresh()
        
        // 扫描完成后刷新缓存
        DispatchQueue.main.asyncAfter(deadline: .now() + 0.5) { [weak self] in
            self?.refreshCacheAfterFolderOperation()
        }
    }
    
    /// 单页内自动补位：将每页的 .empty 槽位移动到该页尾部，保持非空项的相对顺序
    func compactItemsWithinPages() {
        guard !items.isEmpty else { return }
        let itemsPerPage = self.itemsPerPage // 使用计算属性
        var result: [LaunchpadItem] = []
        result.reserveCapacity(items.count)
        var index = 0
        while index < items.count {
            let end = min(index + itemsPerPage, items.count)
            let pageSlice = Array(items[index..<end])
            let nonEmpty = pageSlice.filter { if case .empty = $0 { return false } else { return true } }
            let emptyCount = pageSlice.count - nonEmpty.count
            
            // 先添加非空项目，保持原有顺序
            result.append(contentsOf: nonEmpty)
            
            // 再添加empty项目到页面末尾
            if emptyCount > 0 {
                var empties: [LaunchpadItem] = []
                empties.reserveCapacity(emptyCount)
                for _ in 0..<emptyCount { empties.append(.empty(UUID().uuidString)) }
                result.append(contentsOf: empties)
            }
            
            index = end
        }
        items = filteredItemsRemovingHidden(from: result)
    }

    // MARK: - 跨页拖拽：级联插入（满页则将最后一个推入下一页）
    func moveItemAcrossPagesWithCascade(item: LaunchpadItem, to targetIndex: Int) {
        guard items.indices.contains(targetIndex) || targetIndex == items.count else {
            return
        }
        guard let source = items.firstIndex(of: item) else { return }
        var result = items
        // 源位置置空，保持长度
        result[source] = .empty(UUID().uuidString)
        // 执行级联插入
        result = cascadeInsert(into: result, item: item, at: targetIndex)
        items = filteredItemsRemovingHidden(from: result)
        
        // 每次拖拽结束后都进行压缩，确保每页的empty项目移动到页面末尾
        let targetPage = targetIndex / itemsPerPage
        let currentPages = (items.count + itemsPerPage - 1) / itemsPerPage
        
        if targetPage == currentPages - 1 {
            // 拖拽到新页面，延迟压缩以确保应用位置稳定
            DispatchQueue.main.asyncAfter(deadline: .now() + 0.5) {
                self.compactItemsWithinPages()
                self.triggerGridRefresh()
            }
        } else {
            // 拖拽到现有页面，立即压缩
            compactItemsWithinPages()
        }
        
        // 触发网格视图刷新，确保界面立即更新
        triggerGridRefresh()
        
        saveAllOrder()
    }

    private func cascadeInsert(into array: [LaunchpadItem], item: LaunchpadItem, at targetIndex: Int) -> [LaunchpadItem] {
        var result = array
        let p = self.itemsPerPage // 使用计算属性

        // 确保长度填充为整页，便于处理
        if result.count % p != 0 {
            let remain = p - (result.count % p)
            for _ in 0..<remain { result.append(.empty(UUID().uuidString)) }
        }

        var currentPage = max(0, targetIndex / p)
        var localIndex = max(0, min(targetIndex - currentPage * p, p - 1))
        var carry: LaunchpadItem? = item

        while let moving = carry {
            let pageStart = currentPage * p
            let pageEnd = pageStart + p
            if result.count < pageEnd {
                let need = pageEnd - result.count
                for _ in 0..<need { result.append(.empty(UUID().uuidString)) }
            }
            var slice = Array(result[pageStart..<pageEnd])
            
            // 确保插入位置在有效范围内
            let safeLocalIndex = max(0, min(localIndex, slice.count))
            slice.insert(moving, at: safeLocalIndex)
            
            var spilled: LaunchpadItem? = nil
            if slice.count > p {
                spilled = slice.removeLast()
            }
            result.replaceSubrange(pageStart..<pageEnd, with: slice)
            if let s = spilled, case .empty = s {
                // 溢出为空：结束
                carry = nil
            } else if let s = spilled {
                // 溢出非空：推到下一页页首
                carry = s
                currentPage += 1
                localIndex = 0
                // 若到最后超过长度，填充下一页
                let nextEnd = (currentPage + 1) * p
                if result.count < nextEnd {
                    let need = nextEnd - result.count
                    for _ in 0..<need { result.append(.empty(UUID().uuidString)) }
                }
            } else {
                carry = nil
            }
        }
        return result
    }
    
    func rebuildItems() {
        // 增加防抖和优化检查
        let currentItemsCount = items.count
        let appsInFolders: Set<AppInfo> = Set(folders.flatMap { $0.apps })
        let folderById: [String: FolderInfo] = Dictionary(uniqueKeysWithValues: folders.map { ($0.id, $0) })

        var newItems: [LaunchpadItem] = []
        newItems.reserveCapacity(currentItemsCount + 10) // 预分配容量
        var seenAppPaths = Set<String>()
        var seenFolderIds = Set<String>()
        seenAppPaths.reserveCapacity(apps.count)
        seenFolderIds.reserveCapacity(folders.count)

        for item in items {
            switch item {
            case .folder(let folder):
                if let updated = folderById[folder.id] {
                    newItems.append(.folder(updated))
                    seenFolderIds.insert(updated.id)
                }
                // 若该文件夹已被删除，则跳过（不再保留）
            case .app(let app):
                // 如果 app 已进入某个文件夹，则从顶层移除；否则保留其原有位置
                if !appsInFolders.contains(app) {
                    newItems.append(.app(app))
                    seenAppPaths.insert(app.url.path)
                }
            case .empty(let token):
                // 保留 empty 作为占位，维持每页独立
                newItems.append(.empty(token))
            }
        }

        // 追加遗漏的自由应用（未在顶层出现，但也不在任何文件夹中）
        let missingFreeApps = apps.filter { !appsInFolders.contains($0) && !seenAppPaths.contains($0.url.path) }
        newItems.append(contentsOf: missingFreeApps.map { .app($0) })

        // 注意：不要自动把缺失的文件夹追加到末尾，
        // 以免在加载持久化顺序后，因增量更新触发重建时把文件夹推到最后一页。

        // 只有在实际变化时才更新items
        if newItems.count != items.count || !newItems.elementsEqual(items, by: { $0.id == $1.id }) {
            items = filteredItemsRemovingHidden(from: newItems)
        }
    }
    
    // MARK: - 持久化：每页独立排序（新）+ 兼容旧版
    func loadAllOrder() {
        guard let modelContext else {
            print("LaunchNext: ModelContext is nil, cannot load persisted order")
            return
        }
        
        print("LaunchNext: Attempting to load persisted order data...")
        
        // 优先尝试从新的"页-槽位"模型读取
        if loadOrderFromPageEntries(using: modelContext) {
            print("LaunchNext: Successfully loaded order from PageEntryData")
            return
        }
        
        print("LaunchNext: PageEntryData not found, trying legacy TopItemData...")
        // 回退：旧版全局顺序模型
        loadOrderFromLegacyTopItems(using: modelContext)
        print("LaunchNext: Finished loading order from legacy data")
    }

    private func loadOrderFromPageEntries(using modelContext: ModelContext) -> Bool {
        do {
            let descriptor = FetchDescriptor<PageEntryData>(
                sortBy: [SortDescriptor(\.pageIndex, order: .forward), SortDescriptor(\.position, order: .forward)]
            )
            let saved = try modelContext.fetch(descriptor)
            guard !saved.isEmpty else { return false }

            // 构建文件夹：按首次出现顺序
            var folderMap: [String: FolderInfo] = [:]
            var foldersInOrder: [FolderInfo] = []

            // 先收集所有 folder 的 appPaths，避免重复构建
            for row in saved where row.kind == "folder" {
                guard let fid = row.folderId else { continue }
                if folderMap[fid] != nil { continue }

                let folderApps: [AppInfo] = row.appPaths.compactMap { path in
                    if let existing = apps.first(where: { $0.url.path == path }) {
                        return existing
                    }
                    let url = URL(fileURLWithPath: path)
                    guard FileManager.default.fileExists(atPath: url.path) else { return nil }
                    return self.appInfo(from: url)
                }
                let folder = FolderInfo(id: fid, name: row.folderName ?? "Untitled", apps: folderApps, createdAt: row.createdAt)
                folderMap[fid] = folder
                foldersInOrder.append(folder)
            }

            let folderAppPathSet: Set<String> = Set(foldersInOrder.flatMap { $0.apps.map { $0.url.path } })

            // 合成顶层 items（按页与位置的顺序；保留 empty 以维持每页独立槽位）
            var combined: [LaunchpadItem] = []
            combined.reserveCapacity(saved.count)
            for row in saved {
                switch row.kind {
                case "folder":
                    if let fid = row.folderId, let folder = folderMap[fid] {
                        combined.append(.folder(folder))
                    }
                case "app":
                    if let path = row.appPath, !folderAppPathSet.contains(path) {
                        if let existing = apps.first(where: { $0.url.path == path }) {
                            combined.append(.app(existing))
                        } else {
                            let url = URL(fileURLWithPath: path)
                            if FileManager.default.fileExists(atPath: url.path) {
                                combined.append(.app(self.appInfo(from: url)))
                            }
                        }
                    }
                case "empty":
                    combined.append(.empty(row.slotId))
                default:
                    break
                }
            }

            DispatchQueue.main.async {
                self.folders = self.sanitizedFolders(foldersInOrder)
                if !combined.isEmpty {
                    self.items = self.filteredItemsRemovingHidden(from: combined)
                    // 如果应用列表为空，从持久化数据中恢复应用列表
                    if self.apps.isEmpty {
                        let freeApps: [AppInfo] = combined.compactMap { if case let .app(a) = $0 { return a } else { return nil } }
                        self.apps = freeApps
                        self.pruneHiddenAppsFromAppList()
                    }
                }
                self.hasAppliedOrderFromStore = true
            }
            return true
        } catch {
            return false
        }
    }

    private func loadOrderFromLegacyTopItems(using modelContext: ModelContext) {
        do {
            let descriptor = FetchDescriptor<TopItemData>(sortBy: [SortDescriptor(\.orderIndex, order: .forward)])
            let saved = try modelContext.fetch(descriptor)
            guard !saved.isEmpty else { return }

            var folderMap: [String: FolderInfo] = [:]
            var foldersInOrder: [FolderInfo] = []
            let folderAppPathSet: Set<String> = Set(saved.filter { $0.kind == "folder" }.flatMap { $0.appPaths })
            for row in saved where row.kind == "folder" {
                let folderApps: [AppInfo] = row.appPaths.compactMap { path in
                    if let existing = apps.first(where: { $0.url.path == path }) { return existing }
                    let url = URL(fileURLWithPath: path)
                    guard FileManager.default.fileExists(atPath: url.path) else { return nil }
                    return self.appInfo(from: url)
                }
                let folder = FolderInfo(id: row.id, name: row.folderName ?? "Untitled", apps: folderApps, createdAt: row.createdAt)
                folderMap[row.id] = folder
                foldersInOrder.append(folder)
            }

            var combined: [LaunchpadItem] = saved.sorted { $0.orderIndex < $1.orderIndex }.compactMap { row in
                if row.kind == "folder" { return folderMap[row.id].map { .folder($0) } }
                if row.kind == "empty" { return .empty(row.id) }
                if row.kind == "app", let path = row.appPath {
                    if folderAppPathSet.contains(path) { return nil }
                    if let existing = apps.first(where: { $0.url.path == path }) { return .app(existing) }
                    let url = URL(fileURLWithPath: path)
                    guard FileManager.default.fileExists(atPath: url.path) else { return nil }
                    return .app(self.appInfo(from: url))
                }
                return nil
            }

            let appsInFolders = Set(foldersInOrder.flatMap { $0.apps })
            let appsInCombined: Set<AppInfo> = Set(combined.compactMap { if case let .app(a) = $0 { return a } else { return nil } })
            let missingFreeApps = apps
                .filter { !appsInFolders.contains($0) && !appsInCombined.contains($0) }
                .map { LaunchpadItem.app($0) }
            combined.append(contentsOf: missingFreeApps)

            DispatchQueue.main.async {
                self.folders = self.sanitizedFolders(foldersInOrder)
                if !combined.isEmpty {
                    self.items = self.filteredItemsRemovingHidden(from: combined)
                    // 如果应用列表为空，从持久化数据中恢复应用列表
                    if self.apps.isEmpty {
                        let freeAppsAfterLoad: [AppInfo] = combined.compactMap { if case let .app(a) = $0 { return a } else { return nil } }
                        self.apps = freeAppsAfterLoad
                        self.pruneHiddenAppsFromAppList()
                    }
                }
                self.hasAppliedOrderFromStore = true
            }
        } catch {
            // ignore
        }
    }

    func saveAllOrder() {
        guard let modelContext else {
            print("LaunchNext: ModelContext is nil, cannot save order")
            return
        }
        guard !items.isEmpty else {
            print("LaunchNext: Items list is empty, skipping save")
            return
        }

        print("LaunchNext: Saving order data for \(items.count) items...")
        
        // 写入新模型：按页-槽位
        do {
            let existing = try modelContext.fetch(FetchDescriptor<PageEntryData>())
            print("LaunchNext: Found \(existing.count) existing entries, clearing...")
            for row in existing { modelContext.delete(row) }

            // 构建 folders 查找表
            let folderById: [String: FolderInfo] = Dictionary(uniqueKeysWithValues: folders.map { ($0.id, $0) })
            let itemsPerPage = self.itemsPerPage // 使用计算属性

            for (idx, item) in items.enumerated() {
                let pageIndex = idx / itemsPerPage
                let position = idx % itemsPerPage
                let slotId = "page-\(pageIndex)-pos-\(position)"
                switch item {
                case .folder(let folder):
                    let authoritativeFolder = folderById[folder.id] ?? folder
                    let row = PageEntryData(
                        slotId: slotId,
                        pageIndex: pageIndex,
                        position: position,
                        kind: "folder",
                        folderId: authoritativeFolder.id,
                        folderName: authoritativeFolder.name,
                        appPaths: authoritativeFolder.apps.map { $0.url.path }
                    )
                    modelContext.insert(row)
                case .app(let app):
                    let row = PageEntryData(
                        slotId: slotId,
                        pageIndex: pageIndex,
                        position: position,
                        kind: "app",
                        appPath: app.url.path
                    )
                    modelContext.insert(row)
                case .empty:
                    let row = PageEntryData(
                        slotId: slotId,
                        pageIndex: pageIndex,
                        position: position,
                        kind: "empty"
                    )
                    modelContext.insert(row)
                }
            }
            try modelContext.save()
            print("LaunchNext: Successfully saved order data")
            
            // 清理旧版表，避免占用空间（忽略错误）
            do {
                let legacy = try modelContext.fetch(FetchDescriptor<TopItemData>())
                for row in legacy { modelContext.delete(row) }
                try? modelContext.save()
            } catch { }
        } catch {
            print("LaunchNext: Error saving order data: \(error)")
        }
    }

    // 触发文件夹更新，通知所有相关视图刷新图标
    private func triggerFolderUpdate() {
        folderUpdateTrigger = UUID()
    }
    
    // 触发网格视图刷新，用于拖拽操作后的界面更新
    func triggerGridRefresh() {
        clampCurrentPageWithinBounds()
        gridRefreshTrigger = UUID()
    }
    
    
    // 清除所有持久化的排序和文件夹数据
    private func clearAllPersistedData() {
        guard let modelContext else { return }
        
        do {
            // 清除新的页-槽位数据
            let pageEntries = try modelContext.fetch(FetchDescriptor<PageEntryData>())
            for entry in pageEntries {
                modelContext.delete(entry)
            }
            
            // 清除旧版的全局顺序数据
            let legacyEntries = try modelContext.fetch(FetchDescriptor<TopItemData>())
            for entry in legacyEntries {
                modelContext.delete(entry)
            }
            
            // 保存更改
            try modelContext.save()
        } catch {
            // 忽略错误，确保重置流程继续进行
        }
    }

    private func clampCurrentPageWithinBounds() {
        let perPage = max(itemsPerPage, 1)
        let maxPageIndex = items.isEmpty ? 0 : max(0, (items.count - 1) / perPage)
        if currentPage > maxPageIndex {
            currentPage = maxPageIndex
        }
    }

    // MARK: - 拖拽时自动创建新页
    private var pendingNewPage: (pageIndex: Int, itemCount: Int)? = nil
    
    func createNewPageForDrag() -> Bool {
        let itemsPerPage = self.itemsPerPage
        let currentPages = (items.count + itemsPerPage - 1) / itemsPerPage
        let newPageIndex = currentPages
        
        // 为新页添加empty占位符
        for _ in 0..<itemsPerPage {
            items.append(.empty(UUID().uuidString))
        }
        
        // 记录待处理的新页信息
        pendingNewPage = (pageIndex: newPageIndex, itemCount: itemsPerPage)
        
        // 触发网格视图刷新
        triggerGridRefresh()
        
        return true
    }
    
    func cleanupUnusedNewPage() {
        guard let pending = pendingNewPage else { return }
        
        // 检查新页是否被使用（是否有非empty项目）
        let pageStart = pending.pageIndex * pending.itemCount
        let pageEnd = min(pageStart + pending.itemCount, items.count)
        
        if pageStart < items.count {
            let pageSlice = Array(items[pageStart..<pageEnd])
            let hasNonEmptyItems = pageSlice.contains { item in
                if case .empty = item { return false } else { return true }
            }
            
            if !hasNonEmptyItems {
                // 新页没有被使用，删除它
                items.removeSubrange(pageStart..<pageEnd)
                
                // 触发网格视图刷新
                triggerGridRefresh()
            }
        }
        
        // 清除待处理信息
        pendingNewPage = nil
    }

    // MARK: - 自动删除空白页面
    /// 自动删除空白页面：删除全部都是empty填充的页面
    func removeEmptyPages() {
        guard !items.isEmpty else { return }
        let itemsPerPage = self.itemsPerPage
        
        var newItems: [LaunchpadItem] = []
        var index = 0
        
        while index < items.count {
            let end = min(index + itemsPerPage, items.count)
            let pageSlice = Array(items[index..<end])
            
            // 检查当前页是否全部都是empty
            let isEmptyPage = pageSlice.allSatisfy { item in
                if case .empty = item { return true } else { return false }
            }
            
            // 如果不是空白页面，保留该页内容
            if !isEmptyPage {
                newItems.append(contentsOf: pageSlice)
            }
            // 如果是空白页面，跳过不添加
            
            index = end
        }
        
        // 只有在实际删除了空白页面时才更新items
        if newItems.count != items.count {
            items = filteredItemsRemovingHidden(from: newItems)
            
            // 删除空白页面后，确保当前页索引在有效范围内
            let maxPageIndex = max(0, (items.count - 1) / itemsPerPage)
            if currentPage > maxPageIndex {
                currentPage = maxPageIndex
            }
            
            // 触发网格视图刷新
            triggerGridRefresh()
        }
    }

    private func handleGridConfigurationChange() {
        DispatchQueue.main.async { [weak self] in
            guard let self else { return }
            self.compactItemsWithinPages()
            self.removeEmptyPages()
            self.cleanupUnusedNewPage()
            let maxPageIndex = max(0, (self.items.count - 1) / max(self.itemsPerPage, 1))
            if self.currentPage > maxPageIndex {
                self.currentPage = maxPageIndex
            }
            self.triggerGridRefresh()
            self.cacheManager.refreshCache(from: self.apps,
                                           items: self.items,
                                           itemsPerPage: self.itemsPerPage,
                                           columns: self.gridColumnsPerPage,
                                           rows: self.gridRowsPerPage)
            if self.rememberLastPage {
                UserDefaults.standard.set(self.currentPage, forKey: Self.rememberedPageIndexKey)
            }
            self.saveAllOrder()
        }
    }
    
    // MARK: - 导出应用排序功能
    /// 导出应用排序为JSON格式
    func exportAppOrderAsJSON() -> String? {
        let exportData = buildExportData()
        
        do {
            let jsonData = try JSONSerialization.data(withJSONObject: exportData, options: [.prettyPrinted, .sortedKeys])
            return String(data: jsonData, encoding: .utf8)
        } catch {
            return nil
        }
    }
    
    /// 构建导出数据
    private func buildExportData() -> [String: Any] {
        var pages: [[String: Any]] = []
        let itemsPerPage = self.itemsPerPage
        
        for (index, item) in items.enumerated() {
            let pageIndex = index / itemsPerPage
            let position = index % itemsPerPage
            
            var itemData: [String: Any] = [
                "pageIndex": pageIndex,
                "position": position,
                "kind": itemKind(for: item),
                "name": item.name,
                "path": itemPath(for: item),
                "folderApps": []
            ]
            
            // 如果是文件夹，添加文件夹内的应用信息
            if case let .folder(folder) = item {
                itemData["folderApps"] = folder.apps.map { $0.name }
                itemData["folderAppPaths"] = folder.apps.map { $0.url.path }
            }
            
            pages.append(itemData)
        }
        
        return [
            "exportDate": ISO8601DateFormatter().string(from: Date()),
            "totalPages": (items.count + itemsPerPage - 1) / itemsPerPage,
            "totalItems": items.count,
            "fullscreenMode": isFullscreenMode,
            "pages": pages
        ]
    }
    
    /// 获取项目类型描述
    private func itemKind(for item: LaunchpadItem) -> String {
        switch item {
        case .app:
            return "应用"
        case .folder:
            return "文件夹"
        case .empty:
            return "空槽位"
        }
    }
    
    /// 获取项目路径
    private func itemPath(for item: LaunchpadItem) -> String {
        switch item {
        case let .app(app):
            return app.url.path
        case let .folder(folder):
            return "文件夹: \(folder.name)"
        case .empty:
            return "空槽位"
        }
    }
    
    /// 使用系统文件保存对话框保存导出文件
    func saveExportFileWithDialog(content: String, filename: String, fileExtension: String, fileType: String) -> Bool {
        let savePanel = NSSavePanel()
        savePanel.title = "保存导出文件"
        savePanel.nameFieldStringValue = filename
        savePanel.allowedContentTypes = [UTType(filenameExtension: fileExtension) ?? .plainText]
        savePanel.canCreateDirectories = true
        savePanel.isExtensionHidden = false
        
        // 设置默认保存位置为桌面
        if let desktopURL = FileManager.default.urls(for: .desktopDirectory, in: .userDomainMask).first {
            savePanel.directoryURL = desktopURL
        }
        
        let response = savePanel.runModal()
        if response == .OK, let url = savePanel.url {
            do {
                try content.write(to: url, atomically: true, encoding: .utf8)
                return true
            } catch {
                return false
            }
        }
        return false
    }
    
    // MARK: - 缓存管理
    
    /// 扫描完成后生成缓存
    private func generateCacheAfterScan() {
        
        // 检查缓存是否有效
        if !cacheManager.isCacheValid {
            // 生成新的缓存
            cacheManager.generateCache(from: apps,
                                      items: items,
                                      itemsPerPage: itemsPerPage,
                                      columns: gridColumnsPerPage,
                                      rows: gridRowsPerPage)
        } else {
            // 缓存有效，但可以预加载图标
            let appPaths = apps.map { $0.url.path }
            cacheManager.preloadIcons(for: appPaths)
        }

        cacheManager.smartPreloadIcons(for: items, currentPage: currentPage, itemsPerPage: itemsPerPage)

        if isInitialLoading {
            isInitialLoading = false
        }
    }
    
    /// 手动刷新（模拟全新启动的完整流程）
    func refresh() {
        print("LaunchNext: Manual refresh triggered")
        
        // 清除缓存，确保图标与搜索索引重新生成
        cacheManager.clearAllCaches()

        // 重置界面与状态，使之接近"首次启动"
        openFolder = nil
        currentPage = 0
        if !searchText.isEmpty { searchText = "" }

        // 不要重置 hasAppliedOrderFromStore，保持布局数据
        hasPerformedInitialScan = true

        // 执行与首次启动相同的扫描路径（保持现有顺序，新增在末尾）
        scanApplicationsWithOrderPreservation()

        // 扫描完成后生成缓存
        DispatchQueue.main.asyncAfter(deadline: .now() + 0.1) { [weak self] in
            guard let self else { return }
            self.generateCacheAfterScan()
        }

        // 强制界面刷新
        triggerFolderUpdate()
        triggerGridRefresh()
    }
    
    /// 清除缓存
    func clearCache() {
        cacheManager.clearAllCaches()
    }
    
    /// 获取缓存统计信息
    var cacheStatistics: CacheStatistics {
        return cacheManager.cacheStatistics
    }
    
    /// 增量更新后更新缓存
    private func updateCacheAfterChanges() {
        // 检查缓存是否需要更新
        if !cacheManager.isCacheValid {
            // 缓存无效，重新生成
            cacheManager.generateCache(from: apps,
                                      items: items,
                                      itemsPerPage: itemsPerPage,
                                      columns: gridColumnsPerPage,
                                      rows: gridRowsPerPage)
        } else {
            // 缓存有效，只更新变化的部分
            let changedAppPaths = apps.map { $0.url.path }
            cacheManager.preloadIcons(for: changedAppPaths)
        }
    }

    private var resolvedLanguage: AppLanguage {
        preferredLanguage == .system ? AppLanguage.resolveSystemDefault() : preferredLanguage
    }

    func localized(_ key: LocalizationKey) -> String {
        LocalizationManager.shared.localized(key, language: resolvedLanguage)
    }

    func localizedLanguageName(for language: AppLanguage) -> String {
        LocalizationManager.shared.languageDisplayName(for: language, displayLanguage: resolvedLanguage)
    }

    // MARK: - Hidden Apps

    @discardableResult
    func hideApp(_ app: AppInfo) -> Bool {
        hideApp(atPath: app.url.path)
    }

    @discardableResult
    func hideApp(at url: URL) -> Bool {
        let resolved = url.resolvingSymlinksInPath()
        guard resolved.pathExtension.caseInsensitiveCompare("app") == .orderedSame else { return false }
        guard FileManager.default.fileExists(atPath: resolved.path) else { return false }
        return hideApp(atPath: resolved.path)
    }

    @discardableResult
    func hideApp(atPath path: String) -> Bool {
        var didInsert = false
        updateHiddenAppPaths { set in
            if !set.contains(path) {
                set.insert(path)
                didInsert = true
            }
        }
        guard didInsert else { return false }

        removeHiddenAppMetadata(forPath: path)
        items = filteredItemsRemovingHidden(from: items)
        folders = sanitizedFolders(folders)
        applyHiddenFilteringToOpenFolder()
        compactItemsWithinPages()
        removeEmptyPages()
        triggerFolderUpdate()
        triggerGridRefresh()
        updateCacheAfterChanges()
        saveAllOrder()
        return true
    }

    func unhideApp(path: String) {
        var didRemove = false
        updateHiddenAppPaths { set in
            if set.remove(path) != nil {
                didRemove = true
            }
        }
        guard didRemove else { return }

        guard FileManager.default.fileExists(atPath: path) else {
            triggerFolderUpdate()
            triggerGridRefresh()
            return
        }

        let url = URL(fileURLWithPath: path)
        let info = appInfo(from: url)
        if !apps.contains(info) {
            apps.append(info)
            apps.sort { $0.name.localizedCaseInsensitiveCompare($1.name) == .orderedAscending }
        }

        rebuildItems()
        folders = sanitizedFolders(folders)
        applyHiddenFilteringToOpenFolder()
        compactItemsWithinPages()
        triggerFolderUpdate()
        triggerGridRefresh()
        updateCacheAfterChanges()
        saveAllOrder()
    }

    private func removeHiddenAppMetadata(forPath path: String) {
        if let index = apps.firstIndex(where: { $0.url.path == path }) {
            apps.remove(at: index)
        }
    }

    private func pruneHiddenAppsFromAppList() {
        guard !hiddenAppPaths.isEmpty else { return }
        apps.removeAll { hiddenAppPaths.contains($0.url.path) }
    }

    private func applyHiddenFilteringToOpenFolder() {
        guard let folder = openFolder else { return }
        let filtered = filteredFolderRemovingHidden(from: folder)
        if filtered.apps.count != folder.apps.count {
            openFolder = filtered
        }
    }

    private func sanitizedFolders(_ input: [FolderInfo]) -> [FolderInfo] {
        guard !hiddenAppPaths.isEmpty else { return input }
        let hidden = hiddenAppPaths
        var result: [FolderInfo] = []
        result.reserveCapacity(input.count)
        var didChange = false
        for folder in input {
            let filtered = filteredFolderRemovingHidden(from: folder, hidden: hidden)
            if filtered.apps.count != folder.apps.count {
                didChange = true
            }
            result.append(filtered)
        }
        return didChange ? result : input
    }

    private func filteredItemsRemovingHidden(from input: [LaunchpadItem]) -> [LaunchpadItem] {
        guard !hiddenAppPaths.isEmpty else { return input }
        let hidden = hiddenAppPaths
        var result: [LaunchpadItem] = []
        result.reserveCapacity(input.count)
        var didChange = false
        for item in input {
            switch item {
            case .app(let app):
                if hidden.contains(app.url.path) {
                    didChange = true
                    continue
                }
                result.append(.app(app))
            case .folder(let folder):
                let filteredFolder = filteredFolderRemovingHidden(from: folder, hidden: hidden)
                if filteredFolder.apps.count != folder.apps.count {
                    didChange = true
                }
                result.append(.folder(filteredFolder))
            case .empty:
                result.append(item)
            }
        }
        return didChange ? result : input
    }

    private func filteredFolderRemovingHidden(from folder: FolderInfo) -> FolderInfo {
        filteredFolderRemovingHidden(from: folder, hidden: hiddenAppPaths)
    }

    private func filteredFolderRemovingHidden(from folder: FolderInfo, hidden: Set<String>) -> FolderInfo {
        guard !hidden.isEmpty else { return folder }
        let filteredApps = folder.apps.filter { !hidden.contains($0.url.path) }
        if filteredApps.count == folder.apps.count {
            return folder
        }
        var copy = folder
        copy.apps = filteredApps
        return copy
    }

    // MARK: - Custom Titles

    func customTitle(for app: AppInfo) -> String {
        customTitles[app.url.path] ?? ""
    }

    func setCustomTitle(_ rawValue: String, for app: AppInfo) {
        let key = app.url.path
        let trimmed = rawValue.trimmingCharacters(in: .whitespacesAndNewlines)

        if trimmed.isEmpty {
            if customTitles[key] != nil {
                var updated = customTitles
                updated.removeValue(forKey: key)
                customTitles = updated
                applyCustomTitleOverride(for: app.url, title: nil)
            }
            return
        }

        if customTitles[key] == trimmed { return }

        var updated = customTitles
        updated[key] = trimmed
        customTitles = updated
        applyCustomTitleOverride(for: app.url, title: trimmed)
    }

    func clearCustomTitle(for app: AppInfo) {
        setCustomTitle("", for: app)
    }

    func appInfoForCustomTitle(path: String) -> AppInfo {
        if let existing = apps.first(where: { $0.url.path == path }) {
            return existing
        }

        let url = URL(fileURLWithPath: path)
        if FileManager.default.fileExists(atPath: url.path) {
            return AppInfo.from(url: url, customTitle: customTitles[path])
        }

        let fallbackName = customTitles[path] ?? url.deletingPathExtension().lastPathComponent
        let icon = NSWorkspace.shared.icon(forFile: url.path)
        return AppInfo(name: fallbackName, icon: icon, url: url)
    }

    func defaultDisplayName(for path: String) -> String {
        let url = URL(fileURLWithPath: path)
        guard FileManager.default.fileExists(atPath: url.path) else {
            return url.deletingPathExtension().lastPathComponent
        }
        return AppInfo.from(url: url, customTitle: nil).name
    }

    @discardableResult
    func ensureCustomTitleEntry(for url: URL) -> AppInfo? {
        let resolved = url.resolvingSymlinksInPath()
        guard resolved.pathExtension.lowercased() == "app" else { return nil }
        guard FileManager.default.fileExists(atPath: resolved.path) else { return nil }

        let info = appInfo(from: resolved)
        if customTitles[resolved.path] == nil {
            setCustomTitle(info.name, for: info)
        } else {
            applyCustomTitleOverride(for: resolved, title: customTitles[resolved.path])
        }
        return info
    }

    private func applyCustomTitleOverride(for url: URL, title: String?) {
        let info = AppInfo.from(url: url, customTitle: title)
        var changed = false

        if let index = apps.firstIndex(where: { $0.url == url }) {
            apps[index] = info
            changed = true
        }

        for folderIndex in folders.indices {
            var folder = folders[folderIndex]
            var folderChanged = false
            for appIndex in folder.apps.indices where folder.apps[appIndex].url == url {
                folder.apps[appIndex] = info
                folderChanged = true
            }
            if folderChanged {
                folders[folderIndex] = folder
                changed = true
            }
        }

        for itemIndex in items.indices {
            switch items[itemIndex] {
            case .app(let app) where app.url == url:
                items[itemIndex] = .app(info)
                changed = true
            case .app:
                break
            case .folder(var folder):
                var folderChanged = false
                for appIndex in folder.apps.indices where folder.apps[appIndex].url == url {
                    folder.apps[appIndex] = info
                    folderChanged = true
                }
                if folderChanged {
                    items[itemIndex] = .folder(folder)
                    changed = true
                }
            case .folder:
                break
            case .empty:
                break
            }
        }

        if changed {
            triggerFolderUpdate()
            triggerGridRefresh()
            scheduleCustomTitleCacheRefresh()
        }
    }

    private func scheduleCustomTitleCacheRefresh() {
        customTitleRefreshWorkItem?.cancel()
        let work = DispatchWorkItem { [weak self] in
            guard let self else { return }
            self.cacheManager.refreshCache(from: self.apps,
                                           items: self.items,
                                           itemsPerPage: self.itemsPerPage,
                                           columns: self.gridColumnsPerPage,
                                           rows: self.gridRowsPerPage)
        }
        customTitleRefreshWorkItem = work
        DispatchQueue.main.asyncAfter(deadline: .now() + 0.25, execute: work)
    }

    func setCustomAppIcon(from url: URL) -> Bool {
        guard let image = NSImage(contentsOf: url),
              let normalized = AppStore.normalizedIconImage(from: image),
              let data = AppStore.pngData(from: normalized) else {
            return false
        }
        do {
            try data.write(to: customIconFileURL, options: .atomic)
            hasCustomAppIcon = true
            currentAppIcon = normalized
            return true
        } catch {
            return false
        }
    }

    func resetCustomAppIcon() {
        try? FileManager.default.removeItem(at: customIconFileURL)
        hasCustomAppIcon = false
        currentAppIcon = defaultAppIcon
    }

    private func applyCurrentAppIcon() {
        let icon = currentAppIcon
        let bundlePath = Bundle.main.bundlePath
        let hasCustomIconFile = FileManager.default.fileExists(atPath: customIconFileURL.path)
        DispatchQueue.main.async {
            let application = NSApplication.shared
            application.applicationIconImage = icon
            application.dockTile.display()

            let workspace = NSWorkspace.shared
            let success: Bool
            if hasCustomIconFile {
                success = workspace.setIcon(icon, forFile: bundlePath, options: [])
            } else {
                success = workspace.setIcon(nil, forFile: bundlePath, options: [])
            }

            if success {
                workspace.noteFileSystemChanged(bundlePath)
            } else {
                NSLog("LaunchNext: Failed to update application bundle icon at %@", bundlePath)
            }
        }
    }

    private static func loadStoredAppIcon(from url: URL) -> NSImage? {
        guard FileManager.default.fileExists(atPath: url.path),
              let data = try? Data(contentsOf: url),
              let image = NSImage(data: data) else { return nil }
        return image
    }

    private static func normalizedIconImage(from image: NSImage, size: CGFloat = 512) -> NSImage? {
        let targetSize = NSSize(width: size, height: size)
        guard image.size.width > 0, image.size.height > 0 else { return nil }
        let scale = min(targetSize.width / image.size.width, targetSize.height / image.size.height)
        let scaledSize = NSSize(width: image.size.width * scale, height: image.size.height * scale)
        let drawRect = NSRect(x: (targetSize.width - scaledSize.width) / 2,
                              y: (targetSize.height - scaledSize.height) / 2,
                              width: scaledSize.width,
                              height: scaledSize.height)

        let output = NSImage(size: targetSize)
        output.lockFocus()
        NSColor.clear.setFill()
        NSBezierPath(rect: NSRect(origin: .zero, size: targetSize)).fill()
        let sourceRect = NSRect(origin: .zero, size: image.size)
        let hints: [NSImageRep.HintKey: Any] = [.interpolation: NSImageInterpolation.high.rawValue]
        image.draw(in: drawRect, from: sourceRect, operation: .sourceOver, fraction: 1.0, respectFlipped: false, hints: hints)
        output.unlockFocus()
        return output
    }

    private static func pngData(from image: NSImage) -> Data? {
        guard let tiff = image.tiffRepresentation,
              let rep = NSBitmapImageRep(data: tiff) else { return nil }
        rep.size = image.size
        return rep.representation(using: .png, properties: [:])
    }

    private static func ensureAppSupportDirectory() -> URL {
        let fm = FileManager.default
        if let base = try? fm.url(for: .applicationSupportDirectory, in: .userDomainMask, appropriateFor: nil, create: true) {
            let dir = base.appendingPathComponent("LaunchNext", isDirectory: true)
            if !fm.fileExists(atPath: dir.path) {
                try? fm.createDirectory(at: dir, withIntermediateDirectories: true)
            }
            return dir
        }
        return URL(fileURLWithPath: NSTemporaryDirectory(), isDirectory: true)
    }

    private static var customIconFileURL: URL {
        ensureAppSupportDirectory().appendingPathComponent("CustomAppIcon.png", isDirectory: false)
    }

    /// 文件夹操作后刷新缓存，确保搜索功能正常工作
    private func refreshCacheAfterFolderOperation() {
        // 直接刷新缓存，确保包含所有应用（包括文件夹内的应用）
        cacheManager.refreshCache(from: apps,
                                  items: items,
                                  itemsPerPage: itemsPerPage,
                                  columns: gridColumnsPerPage,
                                  rows: gridRowsPerPage)
        
        // 清空搜索文本，确保搜索状态重置
        // 这样可以避免搜索时显示过时的结果
        if !searchText.isEmpty {
            DispatchQueue.main.asyncAfter(deadline: .now() + 0.1) { [weak self] in
                self?.searchText = ""
            }
        }
    }

    func setGlobalHotKey(keyCode: UInt16, modifierFlags: NSEvent.ModifierFlags) {
        let normalized = modifierFlags.normalizedShortcutFlags
        let configuration = HotKeyConfiguration(keyCode: keyCode, modifierFlags: normalized)
        if globalHotKey != configuration {
            globalHotKey = configuration
        }
    }

    func clearGlobalHotKey() {
        if globalHotKey != nil {
            globalHotKey = nil
        }
    }

    func persistCurrentPageIfNeeded() {
        guard rememberLastPage else { return }
        UserDefaults.standard.set(currentPage, forKey: Self.rememberedPageIndexKey)
    }

    func hotKeyDisplayText(nonePlaceholder: String) -> String {
        guard let config = globalHotKey else { return nonePlaceholder }
        let base = config.displayString
        if config.modifierFlags.isEmpty {
            return base + " • " + localized(.shortcutNoModifierWarning)
        }
        return base
    }

    func syncGlobalHotKeyRegistration() {
        AppDelegate.shared?.updateGlobalHotKey(configuration: globalHotKey)
    }
    
    // MARK: - 导入应用排序功能
    /// 从JSON数据导入应用排序
    func importAppOrderFromJSON(_ jsonData: Data) -> Bool {
        do {
            let importData = try JSONSerialization.jsonObject(with: jsonData, options: [])
            return processImportedData(importData)
        } catch {
            return false
        }
    }

    /// 从原生 macOS Launchpad 导入布局
    func importFromNativeLaunchpad() async -> (success: Bool, message: String) {
        guard let modelContext = self.modelContext else {
            return (false, "数据存储未初始化")
        }

        do {
            let importer = NativeLaunchpadImporter(modelContext: modelContext)
            let result = try importer.importFromNativeLaunchpad()

            // 导入成功后刷新应用数据
            DispatchQueue.main.async { [weak self] in
                self?.performInitialScanIfNeeded()
                // 新版使用 SwiftData 的统一加载入口
                self?.loadAllOrder()
                self?.triggerGridRefresh()
            }

            return (true, result.summary)
        } catch {
            return (false, "导入失败: \(error.localizedDescription)")
        }
    }

    /// 从旧版归档（.lmy/.zip 或直接 db）导入
    func importFromLegacyLaunchpadArchive(url: URL) async -> (success: Bool, message: String) {
        guard let modelContext = self.modelContext else {
            return (false, "数据存储未初始化")
        }

        do {
            let importer = NativeLaunchpadImporter(modelContext: modelContext)
            let result = try importer.importFromLegacyArchive(at: url)

            // 导入成功后刷新应用数据
            DispatchQueue.main.async { [weak self] in
                self?.performInitialScanIfNeeded()
                self?.loadAllOrder()
                self?.triggerGridRefresh()
            }

            return (true, result.summary)
        } catch {
            return (false, "导入失败: \(error.localizedDescription)")
        }
    }

    /// 处理导入的数据并重建应用布局
    private func processImportedData(_ importData: Any) -> Bool {
        guard let data = importData as? [String: Any],
              let pagesData = data["pages"] as? [[String: Any]] else {
            return false
        }
        
        // 构建应用路径到应用对象的映射
        let appPathMap = Dictionary(uniqueKeysWithValues: apps.map { ($0.url.path, $0) })
        
        // 重建items数组
        var newItems: [LaunchpadItem] = []
        var importedFolders: [FolderInfo] = []
        
        // 处理每一页的数据
        for pageData in pagesData {
            guard let kind = pageData["kind"] as? String,
                  let name = pageData["name"] as? String else { continue }
            
            switch kind {
            case "应用":
                if let path = pageData["path"] as? String,
                   let app = appPathMap[path] {
                    newItems.append(.app(app))
                } else {
                    // 应用缺失，添加空槽位
                    newItems.append(.empty(UUID().uuidString))
                }
                
            case "文件夹":
                if let folderApps = pageData["folderApps"] as? [String],
                   let folderAppPaths = pageData["folderAppPaths"] as? [String] {
                    // 重建文件夹 - 优先使用应用路径来匹配，确保准确性
                    let folderAppsList = folderAppPaths.compactMap { appPath in
                        // 通过应用路径匹配，这是最准确的方式
                        if let app = apps.first(where: { $0.url.path == appPath }) {
                            return app
                        }
                        // 如果路径匹配失败，尝试通过名称匹配（备用方案）
                        if let appName = folderApps.first(where: { _ in true }), // 获取对应的应用名称
                           let app = apps.first(where: { $0.name == appName }) {
                            return app
                        }
                        return nil
                    }
                    
                    if !folderAppsList.isEmpty {
                        // 尝试从现有文件夹中查找匹配的，保持ID一致
                        let existingFolder = self.folders.first { existingFolder in
                            existingFolder.name == name &&
                            existingFolder.apps.count == folderAppsList.count &&
                            existingFolder.apps.allSatisfy { app in
                                folderAppsList.contains { $0.id == app.id }
                            }
                        }
                        
                        if let existing = existingFolder {
                            // 使用现有文件夹，保持ID一致
                            importedFolders.append(existing)
                            newItems.append(.folder(existing))
                        } else {
                            // 创建新文件夹
                            let folder = FolderInfo(name: name, apps: folderAppsList)
                            importedFolders.append(folder)
                            newItems.append(.folder(folder))
                        }
                    } else {
                        // 文件夹为空，添加空槽位
                        newItems.append(.empty(UUID().uuidString))
                    }
                } else if let folderApps = pageData["folderApps"] as? [String] {
                    // 兼容旧版本：只有应用名称，没有路径信息
                    let folderAppsList = folderApps.compactMap { appName in
                        apps.first { $0.name == appName }
                    }
                    
                    if !folderAppsList.isEmpty {
                        // 尝试从现有文件夹中查找匹配的，保持ID一致
                        let existingFolder = self.folders.first { existingFolder in
                            existingFolder.name == name &&
                            existingFolder.apps.count == folderAppsList.count &&
                            existingFolder.apps.allSatisfy { app in
                                folderAppsList.contains { $0.id == app.id }
                            }
                        }
                        
                        if let existing = existingFolder {
                            // 使用现有文件夹，保持ID一致
                            importedFolders.append(existing)
                            newItems.append(.folder(existing))
                        } else {
                            // 创建新文件夹
                            let folder = FolderInfo(name: name, apps: folderAppsList)
                            importedFolders.append(folder)
                            newItems.append(.folder(folder))
                        }
                    } else {
                        // 文件夹为空，添加空槽位
                        newItems.append(.empty(UUID().uuidString))
                    }
                } else {
                    // 文件夹数据无效，添加空槽位
                    newItems.append(.empty(UUID().uuidString))
                }
                
            case "空槽位":
                newItems.append(.empty(UUID().uuidString))
                
            default:
                // 未知类型，添加空槽位
                newItems.append(.empty(UUID().uuidString))
            }
        }
        
        // 处理多出来的应用（放到最后一页）
        let usedApps = Set(newItems.compactMap { item in
            if case let .app(app) = item { return app }
            return nil
        })
        
        let usedAppsInFolders = Set(importedFolders.flatMap { $0.apps })
        let allUsedApps = usedApps.union(usedAppsInFolders)
        
        let unusedApps = apps.filter { !allUsedApps.contains($0) }
        
        if !unusedApps.isEmpty {
            // 计算需要添加的空槽位数量
            let itemsPerPage = self.itemsPerPage
            let currentPages = (newItems.count + itemsPerPage - 1) / itemsPerPage
            let lastPageStart = currentPages * itemsPerPage
            let lastPageEnd = lastPageStart + itemsPerPage
            
            // 确保最后一页有足够的空间
            while newItems.count < lastPageEnd {
                newItems.append(.empty(UUID().uuidString))
            }
            
            // 将未使用的应用添加到最后一页
            for (index, app) in unusedApps.enumerated() {
                let insertIndex = lastPageStart + index
                if insertIndex < newItems.count {
                    newItems[insertIndex] = .app(app)
                } else {
                    newItems.append(.app(app))
                }
            }
            
            // 确保最后一页也是完整的
            let finalPageCount = newItems.count
            let finalPages = (finalPageCount + itemsPerPage - 1) / itemsPerPage
            let finalLastPageStart = (finalPages - 1) * itemsPerPage
            let finalLastPageEnd = finalLastPageStart + itemsPerPage
            
            // 如果最后一页不完整，添加空槽位
            while newItems.count < finalLastPageEnd {
                newItems.append(.empty(UUID().uuidString))
            }
        }
        
        // 验证导入的数据结构
        
        // 更新应用状态
        DispatchQueue.main.async {
            
            // 设置新的数据
            self.folders = self.sanitizedFolders(importedFolders)
            self.items = self.filteredItemsRemovingHidden(from: newItems)
            
            
            // 强制触发界面更新
            self.triggerFolderUpdate()
            self.triggerGridRefresh()
            
            // 保存新的布局
            self.saveAllOrder()
            
            
            // 暂时不调用页面补齐，保持导入的原始顺序
            // 如果需要补齐，可以在用户手动操作后触发
        }
        
        return true
    }
    
    /// 验证导入数据的完整性
    func validateImportData(_ jsonData: Data) -> (isValid: Bool, message: String) {
        do {
            let importData = try JSONSerialization.jsonObject(with: jsonData, options: [])
            guard let data = importData as? [String: Any] else {
                return (false, "数据格式无效")
            }
            
            guard let pagesData = data["pages"] as? [[String: Any]] else {
                return (false, "缺少页面数据")
            }
            
            let totalPages = data["totalPages"] as? Int ?? 0
            let totalItems = data["totalItems"] as? Int ?? 0
            
            if pagesData.isEmpty {
                return (false, "没有找到应用数据")
            }
            
            return (true, "数据验证通过，共\(totalPages)页，\(totalItems)个项目")
        } catch {
            return (false, "JSON解析失败: \(error.localizedDescription)")
        }
    }

    // MARK: - 更新检查功能

    private func scheduleAutomaticUpdateCheck() {
        autoCheckTimer?.cancel()
        autoCheckTimer = nil

        guard autoCheckForUpdates else { return }

        performAutomaticUpdateCheckIfNeeded()

        let timer = DispatchSource.makeTimerSource(queue: DispatchQueue.main)
        timer.schedule(deadline: .now() + Self.automaticUpdateInterval,
                       repeating: Self.automaticUpdateInterval)
        timer.setEventHandler { [weak self] in
            self?.performAutomaticUpdateCheckIfNeeded()
        }
        timer.activate()
        autoCheckTimer = timer
    }

    private func performAutomaticUpdateCheckIfNeeded() {
        guard autoCheckForUpdates else { return }
        let now = Date()
        if let last = lastUpdateCheck, now.timeIntervalSince(last) < Self.automaticUpdateInterval {
            return
        }
        checkForUpdates()
    }

    func checkForUpdates() {
        guard updateState != .checking else { return }

        lastUpdateCheck = Date()
        updateState = .checking

        Task {
            do {
                let currentVersion = getCurrentVersion()
                let latestRelease = try await fetchLatestRelease()

                await MainActor.run {
                    if let current = SemanticVersion(currentVersion),
                       let latest = SemanticVersion(latestRelease.tagName) {
                        if latest > current {
                            let release = UpdateRelease(
                                version: latestRelease.tagName,
                                url: latestRelease.htmlUrl,
                                notes: latestRelease.body
                            )
                            updateState = .updateAvailable(release)
                            presentUpdateAlert(for: release)
                        } else {
                            updateState = .upToDate(latest: latestRelease.tagName)
                        }
                    } else {
                        updateState = .failed(localized(.versionParseError))
                        presentUpdateFailureAlert(localized(.versionParseError))
                    }
                }
            } catch {
                await MainActor.run {
                    let message = error.localizedDescription
                    updateState = .failed(message)
                    presentUpdateFailureAlert(message)
                }
            }
        }
    }

    private func getCurrentVersion() -> String {
        return Bundle.main.infoDictionary?["CFBundleShortVersionString"] as? String ?? "0.0.0"
    }

    private func fetchLatestRelease() async throws -> GitHubRelease {
        let url = URL(string: "https://api.github.com/repos/RoversX/LaunchNext/releases/latest")!
        let (data, response) = try await URLSession.shared.data(from: url)

        guard let httpResponse = response as? HTTPURLResponse,
              httpResponse.statusCode == 200 else {
            throw URLError(.badServerResponse)
        }

        return try JSONDecoder().decode(GitHubRelease.self, from: data)
    }

    @MainActor
    private func presentUpdateAlert(for release: UpdateRelease) {
        let notification = NSUserNotification()
        notification.title = localized(.updateAvailable)
        notification.informativeText = "\(localized(.newVersion)) \(release.version)"
        notification.hasActionButton = true
        notification.actionButtonTitle = localized(.downloadUpdate)
        notification.otherButtonTitle = localized(.cancel)
        notification.userInfo = ["releaseURL": release.url.absoluteString]

        NSUserNotificationCenter.default.delegate = notificationDelegate
        NSUserNotificationCenter.default.deliver(notification)
    }

    @MainActor
    private func presentUpdateFailureAlert(_ message: String) {
        let notification = NSUserNotification()
        notification.title = localized(.updateCheckFailed)
        notification.informativeText = message

        NSUserNotificationCenter.default.delegate = notificationDelegate
        NSUserNotificationCenter.default.deliver(notification)
    }

func openReleaseURL(_ url: URL) {
    NSWorkspace.shared.open(url)
}
}

private final class UpdateNotificationDelegate: NSObject, NSUserNotificationCenterDelegate {
    private let openHandler: (URL) -> Void

    init(openHandler: @escaping (URL) -> Void) {
        self.openHandler = openHandler
    }

    func userNotificationCenter(_ center: NSUserNotificationCenter, shouldPresent notification: NSUserNotification) -> Bool {
        true
    }

    func userNotificationCenter(_ center: NSUserNotificationCenter, didActivate notification: NSUserNotification) {
        guard notification.activationType == .actionButtonClicked,
              let urlString = notification.userInfo?["releaseURL"] as? String,
              let url = URL(string: urlString) else {
            return
        }
        openHandler(url)
    }
}

#if DEBUG
extension AppStore {
    func simulateUpdateAvailable() {
        let dummy = UpdateRelease(
            version: "999.0.0",
            url: URL(string: "https://github.com/RoversX/LaunchNext/releases/latest")!,
            notes: ""
        )
        updateState = .updateAvailable(dummy)
        presentUpdateAlert(for: dummy)
    }

    func simulateUpdateFailure() {
        let message = "模拟更新失败。"
        updateState = .failed(message)
        presentUpdateFailureAlert(message)
    }
}
#endif

extension NSEvent.ModifierFlags {
    static let shortcutComponents: NSEvent.ModifierFlags = [.command, .option, .control, .shift]

    var normalizedShortcutFlags: NSEvent.ModifierFlags {
        intersection(.deviceIndependentFlagsMask).intersection(Self.shortcutComponents)
    }

    var carbonFlags: UInt32 {
        var value: UInt32 = 0
        if contains(.command) { value |= UInt32(cmdKey) }
        if contains(.option) { value |= UInt32(optionKey) }
        if contains(.control) { value |= UInt32(controlKey) }
        if contains(.shift) { value |= UInt32(shiftKey) }
        return value
    }

    var displaySymbols: [String] {
        var symbols: [String] = []
        if contains(.control) { symbols.append("⌃") }
        if contains(.option) { symbols.append("⌥") }
        if contains(.shift) { symbols.append("⇧") }
        if contains(.command) { symbols.append("⌘") }
        return symbols
    }
}
