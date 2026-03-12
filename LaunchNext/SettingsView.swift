import SwiftUI
import AppKit
import UniformTypeIdentifiers
import SwiftData
import MachO
import Darwin

struct SettingsView: View {
    @ObservedObject var appStore: AppStore
    @ObservedObject private var controllerManager = ControllerInputManager.shared
    @Environment(\.colorScheme) private var colorScheme
    private enum ShortcutTarget {
        case launchpad
        // case aiOverlay
    }
    private enum LayoutModePreviewScope: CaseIterable, Identifiable {
        case fullscreen
        case compact

        var id: String {
            switch self {
            case .fullscreen: return "fullscreen"
            case .compact: return "compact"
            }
        }

        var localizationKey: LocalizationKey {
            switch self {
            case .fullscreen: return .layoutModeScopeFullscreen
            case .compact: return .layoutModeScopeCompact
            }
        }

        var appStoreMode: AppStore.AppearanceLayoutMode {
            switch self {
            case .fullscreen: return .fullscreen
            case .compact: return .compact
            }
        }
    }
    @State private var showResetConfirm = false
    @State private var selectedSection: SettingsSection = .general
    @State private var titleSearch: String = ""
    @State private var hasHiddenAppEntries: Bool = false
    @State private var hasNotHiddenAppEntries: Bool = false
    @State private var hiddenSearch: String = ""
    @State private var notHiddenSearch: String = ""
    @State private var hiddenSearchDebounceID: Int = 0
    @State private var notHiddenSearchDebounceID: Int = 0
    @State private var hasHiddenAppEntriesSearchResult: Bool = false
    @State private var hasNotHiddenAppEntriesSearchResult: Bool = false
    @State private var cachedHiddenAppEntries: [AppEntry] = []
    @State private var cachedNotHiddenAppEntries: [AppEntry] = []
    @State private var showHiddenApps = true
    @State private var showNotHiddenApps = false
    @State private var hiddenVisibleLimit: Int = 10
    @State private var notHiddenVisibleLimit: Int = 10
    private let listPageSize = 10
    @State private var editingDrafts: [String: String] = [:]
    @State private var editingEntries: Set<String> = []
    @State private var iconImportError: String? = nil
    @State private var showAppSourcesResetDialog = false
    @State private var showCleanupCommand = false
    @State private var cleanupCommandCopied = false
    @State private var backupRootPath: String = UserDefaults.standard.string(forKey: "backupRootDirectory") ?? ""
    @State private var backupRefreshToken = UUID()
    @State private var selectedBackupIDs: Set<String> = []
    @State private var showPerformanceRestartPrompt = false
    @State private var capturingShortcutTarget: ShortcutTarget? = nil
    @State private var shortcutCaptureMonitor: Any?
    @State private var pendingShortcut: AppStore.HotKeyConfiguration?
    @State private var cachedAllAppEntries: [AppEntry] = []
    @State private var allAppsVisibleLimit: Int = 10
    @State private var allAppsSearch: String = ""
    @State private var allAppsSearchDebounceID: Int = 0
    @State private var hasAllAppEntries:Bool = false
    @State private var hasAllAppEntriesSearchResult: Bool = false
    @State private var showOnlyEditedTittleApps: Bool = true
    @State private var showCLIInfoPopover = false
    @State private var showCLIRemoveInfoPopover = false
    @State private var showCLIFullPathCommand = false
    @State private var copiedCLICommand: String? = nil
    @State private var cliCommandActionMessage: String? = nil
    @State private var layoutModePreviewScope: LayoutModePreviewScope = .fullscreen
    @State private var lastUpdatesTabRefreshAt: Date? = nil
    private let dockDragSelectableSides: [AppStore.DockDragSide] = [.bottom, .left, .right]

    // Sidebar sizing presets
    private var sidebarIconFrame: CGFloat {
        switch appStore.sidebarIconPreset {
        case .large: return 26
        case .medium: return 24
        }
    }

    private var sidebarIconFontSize: CGFloat {
        switch appStore.sidebarIconPreset {
        case .large: return 13
        case .medium: return 12
        }
    }

    private var sidebarRowVerticalPadding: CGFloat {
        switch appStore.sidebarIconPreset {
        case .large: return 2
        case .medium: return 1
        }
    }

    private var sidebarHeaderIconFrame: CGFloat {
        return 36
    }

    private var sidebarHeaderCornerRadius: CGFloat {
        switch appStore.sidebarIconPreset {
        case .large: return 3
        case .medium: return 3
        }
    }

    var body: some View {
        ZStack(alignment: .topTrailing) {
            NavigationSplitView {
                List(selection: $selectedSection) {
                    HStack(alignment: .center, spacing: 2) {
                        Image(nsImage: NSApplication.shared.applicationIconImage)
                            .resizable()
                            .interpolation(.high)
                            .antialiased(true)
                            .frame(width: sidebarHeaderIconFrame, height: sidebarHeaderIconFrame)
                            .cornerRadius(sidebarHeaderCornerRadius)

                        VStack(alignment: .leading, spacing: 2) {
                            Text(appStore.localized(.appTitle))
                                .font(.headline.weight(.semibold))
                            Text("\(appStore.localized(.versionPrefix))\(getVersion(fallback: appStore.localized(.versionFallback)))")
                                .font(.caption)
                                .foregroundStyle(.secondary)
                        }
                    }
                    .padding(.bottom, 10)
                    .listRowInsets(EdgeInsets(top: 0, leading: -4, bottom: 15, trailing: 10))
                    .listRowSeparator(.hidden)
                    .listRowBackground(Color.clear)

                    ForEach(SettingsSection.allCases) { section in
                        HStack(spacing: 8) {
                            RoundedRectangle(cornerRadius: 8, style: .continuous)
                                .fill(section.iconGradient)
                                .overlay {
                                    RoundedRectangle(cornerRadius: 8, style: .continuous)
                                        .fill(Color.black.opacity(0.06))
                                        .blendMode(.multiply)
                                }
                                .overlay {
                                    RoundedRectangle(cornerRadius: 8, style: .continuous)
                                        .fill(
                                            LinearGradient(
                                                colors: [
                                                    .white.opacity(0.45),
                                                    .white.opacity(0.08),
                                                    .clear
                                                ],
                                                startPoint: .topLeading,
                                                endPoint: .bottomTrailing
                                            )
                                        )
                                        .blendMode(.screen)
                                }
                                .overlay {
                                    RoundedRectangle(cornerRadius: 8, style: .continuous)
                                        .stroke(.white.opacity(0.22), lineWidth: 0.5)
                                        .blendMode(.screen)
                                }
                                .overlay(
                                    Image(systemName: section.iconName)
                                        .font(.system(size: sidebarIconFontSize, weight: .semibold))
                                        .foregroundStyle(.white)
                                )
                                .frame(width: sidebarIconFrame, height: sidebarIconFrame)
                                .liquidGlass()
                                .shadow(color: .black.opacity(0.12), radius: 4, x: 0, y: 1)

                            Text(appStore.localized(section.localizationKey))
                                .font(.system(size: 13.5, weight: .regular))
                        }
                        .padding(.vertical, sidebarRowVerticalPadding)
                        .tag(section)
                    }
                }
                .listStyle(.sidebar)
                .scrollContentBackground(.hidden)
                .background(.ultraThinMaterial)
                .navigationSplitViewColumnWidth(min: 180, ideal: 205, max: 250)
            } detail: {
                detailView(for: selectedSection)
                    .frame(maxWidth: .infinity, maxHeight: .infinity)
            }
            .frame(maxWidth: .infinity, maxHeight: .infinity)
            .background(.ultraThinMaterial)

            Button {
                appStore.stopAccessibilityPolling()
                appStore.isSetting = false
            } label: {
                Image(systemName: "xmark")
                    .font(.title2.bold())
                    .foregroundStyle(.secondary)
                    .padding(8)
                    .background(
                        Circle()
                            .fill(.ultraThinMaterial)
                            .liquidGlass()
                            .shadow(color: .black.opacity(0.12), radius: 6, x: 0, y: 2)
                    )
            }
            .buttonStyle(.plain)
            .padding(.top, 12)
            .padding(.trailing, 16)
        }
        .frame(minWidth: 820, minHeight: 640)
        .alert(appStore.localized(.customIconTitle), isPresented: Binding(get: { iconImportError != nil }, set: { if !$0 { iconImportError = nil } })) {
            Button(appStore.localized(.okButton), role: .cancel) { iconImportError = nil }
        } message: {
            Text(iconImportError ?? "")
        }
        // .onChange(of: appStore.isAIEnabled) { enabled in
        //     if !enabled && isCapturingShortcut(.aiOverlay) {
        //         stopShortcutCapture(cancel: true)
        //     }
        // }
        .onDisappear {
            stopShortcutCapture(cancel: false)
        }
        .onChange(of: appStore.isFullscreenMode) { _, _ in
            guard selectedSection == .appearance else { return }
            syncLayoutModePreviewScopeToRuntime()
        }
        .onChange(of: selectedSection) { _, newSection in
            guard newSection == .updates else { return }
            guard appStore.updateState != .checking else { return }

            let now = Date()
            if let lastRefresh = lastUpdatesTabRefreshAt,
               now.timeIntervalSince(lastRefresh) < 300 {
                return
            }

            lastUpdatesTabRefreshAt = now
            appStore.checkForUpdates()
        }
    }

    private var systemVersionText: String {
        let v = ProcessInfo.processInfo.operatingSystemVersion
        return String(format: appStore.localized(.aboutInfoMacOSValueFormat),
                      v.majorVersion, v.minorVersion, v.patchVersion)
    }

    private var chipText: String {
        var size: size_t = 0
        sysctlbyname("machdep.cpu.brand_string", nil, &size, nil, 0)
        var nameBuffer = [CChar](repeating: 0, count: Int(size))
        if sysctlbyname("machdep.cpu.brand_string", &nameBuffer, &size, nil, 0) == 0 {
            return String(cString: nameBuffer)
        }
        return appStore.localized(.aboutInfoUnknownChip)
    }

    private var displayResolutionText: String {
        guard let screen = NSScreen.main else { return appStore.localized(.aboutInfoUnknownDisplay) }
        let scale = screen.backingScaleFactor
        let size = screen.frame.size
        let width = Int(size.width * scale)
        let height = Int(size.height * scale)
        return "\(width)×\(height)"
    }

    private var displayNameText: String {
        if let name = NSScreen.main?.localizedName, !name.isEmpty {
            return name
        }
        return appStore.localized(.aboutInfoDisplayGeneric)
    }

private func getVersion(fallback: String) -> String {
    Bundle.main.infoDictionary?["CFBundleShortVersionString"] as? String ?? fallback
}

private var selectedAppearanceLayoutMode: AppStore.AppearanceLayoutMode {
    layoutModePreviewScope.appStoreMode
}

private var selectedScopePerDisplayEnabled: Bool {
    appStore.scopedPageIndicatorPerDisplayEnabled(for: selectedAppearanceLayoutMode)
}

private func syncLayoutModePreviewScopeToRuntime() {
    let target: LayoutModePreviewScope = appStore.isFullscreenMode ? .fullscreen : .compact
    guard layoutModePreviewScope != target else { return }
    layoutModePreviewScope = target
}

private func scopedIconScaleBinding() -> Binding<Double> {
    Binding(
        get: { appStore.scopedIconScale(for: selectedAppearanceLayoutMode) },
        set: { appStore.setScopedIconScale($0, for: selectedAppearanceLayoutMode) }
    )
}

private func scopedIconLabelFontSizeBinding() -> Binding<Double> {
    Binding(
        get: { appStore.scopedIconLabelFontSize(for: selectedAppearanceLayoutMode) },
        set: { appStore.setScopedIconLabelFontSize($0, for: selectedAppearanceLayoutMode) }
    )
}

private func scopedFolderDropZoneScaleBinding() -> Binding<Double> {
    Binding(
        get: { appStore.scopedFolderDropZoneScale(for: selectedAppearanceLayoutMode) },
        set: { appStore.setScopedFolderDropZoneScale($0, for: selectedAppearanceLayoutMode) }
    )
}

private func scopedPageIndicatorOffsetBinding() -> Binding<Double> {
    Binding(
        get: { appStore.scopedPageIndicatorOffset(for: selectedAppearanceLayoutMode) },
        set: { appStore.setScopedPageIndicatorOffset($0, for: selectedAppearanceLayoutMode) }
    )
}

private func scopedPageIndicatorTopPaddingBinding() -> Binding<Double> {
    Binding(
        get: { appStore.scopedPageIndicatorTopPadding(for: selectedAppearanceLayoutMode) },
        set: { appStore.setScopedPageIndicatorTopPadding($0, for: selectedAppearanceLayoutMode) }
    )
}

private func scopedPerDisplayIndicatorBinding() -> Binding<Bool> {
    Binding(
        get: { appStore.scopedPageIndicatorPerDisplayEnabled(for: selectedAppearanceLayoutMode) },
        set: { appStore.setScopedPageIndicatorPerDisplayEnabled($0, for: selectedAppearanceLayoutMode) }
    )
}

private var dockDragSideBinding: Binding<AppStore.DockDragSide> {
    Binding(
        get: { appStore.dockDragSide },
        set: { newValue in
            guard appStore.dockDragSide != newValue else { return }
            DispatchQueue.main.async {
                appStore.dockDragSide = newValue
            }
        }
    )
}

private var dockDragTriggerDistanceBinding: Binding<Double> {
    Binding(
        get: { appStore.dockDragTriggerDistance },
        set: { newValue in
            let clamped = min(max(newValue, AppStore.dockDragTriggerDistanceRange.lowerBound),
                              AppStore.dockDragTriggerDistanceRange.upperBound)
            guard appStore.dockDragTriggerDistance != clamped else { return }
            DispatchQueue.main.async {
                appStore.dockDragTriggerDistance = clamped
            }
        }
    )
}

private var hotCornerPositionBinding: Binding<AppStore.HotCornerPosition> {
    Binding(
        get: { appStore.hotCornerPosition },
        set: { newValue in
            guard appStore.hotCornerPosition != newValue else { return }
            DispatchQueue.main.async {
                appStore.hotCornerPosition = newValue
            }
        }
    )
}

private var hotCornerTriggerDelayBinding: Binding<Double> {
    Binding(
        get: { appStore.hotCornerTriggerDelay },
        set: { newValue in
            let clamped = min(max(newValue, AppStore.hotCornerTriggerDelayRange.lowerBound),
                              AppStore.hotCornerTriggerDelayRange.upperBound)
            guard appStore.hotCornerTriggerDelay != clamped else { return }
            DispatchQueue.main.async {
                appStore.hotCornerTriggerDelay = clamped
            }
        }
    )
}

private var hotCornerHitboxSizeBinding: Binding<Double> {
    Binding(
        get: { appStore.hotCornerHitboxSize },
        set: { newValue in
            let clamped = min(max(newValue, AppStore.hotCornerHitboxSizeRange.lowerBound),
                              AppStore.hotCornerHitboxSizeRange.upperBound)
            guard appStore.hotCornerHitboxSize != clamped else { return }
            DispatchQueue.main.async {
                appStore.hotCornerHitboxSize = clamped
            }
        }
    )
}

private var hotCornerToggleWhenOpenBinding: Binding<Bool> {
    Binding(
        get: { appStore.hotCornerToggleWhenOpen },
        set: { newValue in
            guard appStore.hotCornerToggleWhenOpen != newValue else { return }
            DispatchQueue.main.async {
                appStore.hotCornerToggleWhenOpen = newValue
            }
        }
    )
}

// Experimental gesture bindings.
// These async wrappers keep Settings updates out of the current SwiftUI update pass.
// If gesture support is removed later, delete these bindings together with the
// gesture card below, the AppStore gesture fields, LaunchpadApp gesture wiring,
// and LaunchNext/Gesture/.
private var gestureEnabledBinding: Binding<Bool> {
    Binding(
        get: { appStore.gestureEnabled },
        set: { newValue in
            guard appStore.gestureEnabled != newValue else { return }
            DispatchQueue.main.async {
                appStore.gestureEnabled = newValue
            }
        }
    )
}

private var gestureCloseOnPinchOutBinding: Binding<Bool> {
    Binding(
        get: { appStore.gestureCloseOnPinchOut },
        set: { newValue in
            guard appStore.gestureCloseOnPinchOut != newValue else { return }
            DispatchQueue.main.async {
                appStore.gestureCloseOnPinchOut = newValue
            }
        }
    )
}

private var gestureTapActionBinding: Binding<AppStore.GestureTapAction> {
    Binding(
        get: { appStore.gestureTapAction },
        set: { newValue in
            guard appStore.gestureTapAction != newValue else { return }
            DispatchQueue.main.async {
                appStore.gestureTapAction = newValue
            }
        }
    )
}

private func layoutModeScopeControl(width: CGFloat = 130) -> some View {
    let outerShape = Capsule(style: .continuous)

    return HStack(spacing: 3) {
        ForEach(LayoutModePreviewScope.allCases) { scope in
            Button {
                withAnimation(.easeInOut(duration: 0.12)) {
                    layoutModePreviewScope = scope
                }
            } label: {
                Text(appStore.localized(scope.localizationKey))
                    .font(.system(size: 9, weight: .semibold))
                    .foregroundStyle(layoutModePreviewScope == scope ? Color.primary : Color.secondary.opacity(0.9))
                    .lineLimit(1)
                    .minimumScaleFactor(0.72)
                    .frame(maxWidth: .infinity, minHeight: 18)
                    .background {
                        if layoutModePreviewScope == scope {
                            Capsule(style: .continuous)
                                .fill(
                                    colorScheme == .dark
                                    ? Color.white.opacity(0.12)
                                    : Color.white.opacity(0.34)
                                )
                                .liquidGlass(in: Capsule(style: .continuous))
                                .overlay(
                                    Capsule(style: .continuous)
                                        .stroke(Color.white.opacity(colorScheme == .dark ? 0.10 : 0.30), lineWidth: 0.5)
                                )
                        }
                    }
                    .contentShape(Rectangle())
            }
            .buttonStyle(.plain)
            .frame(maxWidth: .infinity)
            .contentShape(Rectangle())
        }
    }
    .padding(2)
    .frame(width: width, height: 24)
    .background {
        outerShape
            .fill(Color.white.opacity(colorScheme == .dark ? 0.03 : 0.10))
            .liquidGlass(in: outerShape)
    }
    .overlay {
        outerShape
            .stroke(Color.white.opacity(colorScheme == .dark ? 0.05 : 0.16), lineWidth: 0.6)
    }
}

private enum SettingsSection: String, CaseIterable, Identifiable {
    case general
    case appearance
    case performance
    case titles
    case appSources
    case hiddenApps
    case uninstall
    case shortcuts
    case backup
    case development
    // case aiOverlay
    case sound
    case gameController
    case updates
    case about

    var id: String { rawValue }

    var iconName: String {
        switch self {
        case .general: return "gearshape"
        case .shortcuts: return "keyboard"
        case .appSources: return "externaldrive"
        case .gameController: return "gamecontroller"
        case .sound: return "speaker.wave.2"
        case .appearance: return "paintbrush"
        case .performance: return "speedometer"
        case .titles: return "text.badge.plus"
        case .hiddenApps: return "eye.slash"
        case .uninstall: return "trash"
        case .backup: return "clock.arrow.trianglehead.counterclockwise.rotate.90"
        case .development: return "hammer"
        // case .aiOverlay: return "sparkles"
        case .updates: return "arrow.down.circle"
        case .about: return "info.circle"
        }
    }

    var iconGradient: LinearGradient {
        let colors: [Color]
        switch self {
        case .general:
            colors = [Color(red: 0.12, green: 0.52, blue: 0.96), Color(red: 0.22, green: 0.72, blue: 0.94)]
        case .shortcuts:
            colors = [Color(red: 0.22, green: 0.31, blue: 0.43), Color(red: 0.33, green: 0.55, blue: 0.72)]
        case .appSources:
            colors = [Color(nsColor: .systemGray), Color(nsColor: .lightGray)]
        case .sound:
            colors = [Color(red: 0.92, green: 0.12, blue: 0.12), Color(red: 0.99, green: 0.30, blue: 0.30)]
        case .gameController:
            colors = [Color(red: 0.46, green: 0.34, blue: 0.97), Color(red: 0.31, green: 0.54, blue: 0.99)]
        case .appearance:
            colors = [Color(red: 0.73, green: 0.25, blue: 0.96), Color(red: 0.98, green: 0.43, blue: 0.80)]
        case .performance:
            colors = [Color(red: 0.02, green: 0.70, blue: 0.46), Color(red: 0.31, green: 0.93, blue: 0.69)]
        case .titles:
            colors = [Color(red: 0.95, green: 0.37, blue: 0.32), Color(red: 0.98, green: 0.55, blue: 0.44)]
        case .hiddenApps:
            colors = [Color(red: 0.29, green: 0.39, blue: 0.96), Color(red: 0.11, green: 0.67, blue: 0.91)]
        case .uninstall:
            colors = [Color(red: 0.94, green: 0.22, blue: 0.27), Color(red: 0.78, green: 0.04, blue: 0.18)]
        case .backup:
            colors = [Color(red: 0.12, green: 0.80, blue: 0.46), Color(red: 0.10, green: 0.62, blue: 0.34)]
        case .development:
            colors = [Color(red: 0.98, green: 0.58, blue: 0.16), Color(red: 0.96, green: 0.20, blue: 0.24)]
        // case .aiOverlay:
        //     colors = [Color(red: 0.39, green: 0.33, blue: 0.98), Color(red: 0.59, green: 0.73, blue: 0.99)]
        case .updates:
            colors = [Color(red: 0.22, green: 0.78, blue: 0.55), Color(red: 0.10, green: 0.62, blue: 0.91)]
        case .about:
            colors = [Color(red: 0.54, green: 0.55, blue: 0.70), Color(red: 0.42, green: 0.44, blue: 0.60)]
        }
        return LinearGradient(gradient: Gradient(colors: colors), startPoint: .topLeading, endPoint: .bottomTrailing)
    }

    var localizationKey: LocalizationKey {
        switch self {
        case .general: return .settingsSectionGeneral
        case .shortcuts: return .globalShortcutTitle
        case .appSources: return .settingsSectionAppSources
        case .sound: return .settingsSectionSound
        case .gameController: return .settingsSectionGameController
        case .appearance: return .settingsSectionAppearance
        case .performance: return .settingsSectionPerformance
        case .titles: return .settingsSectionTitles
        case .hiddenApps: return .settingsSectionHiddenApps
        case .uninstall: return .settingsSectionUninstall
        case .backup: return .settingsSectionBackup
        case .development: return .settingsSectionDevelopment
        // case .aiOverlay: return .settingsSectionAIOverlay
        case .updates: return .settingsSectionUpdates
        case .about: return .settingsSectionAbout
        }
    }
}

    @ViewBuilder
    private func detailView(for section: SettingsSection) -> some View {
        GeometryReader { proxy in
            ZStack(alignment: .top) {
                Rectangle()
                    .fill(.ultraThinMaterial)
                    .frame(height: 160)
                    .mask(
                        LinearGradient(
                            gradient: Gradient(colors: [Color.white.opacity(1), Color.white.opacity(0)]),
                            startPoint: .top,
                            endPoint: .bottom
                        )
                    )
                    .allowsHitTesting(false)

                VStack(alignment: .leading, spacing: 16) {
                    Text(appStore.localized(section.localizationKey))
                        .font(.title3.bold())

                    ScrollView(showsIndicators: false) {
                        scrollContent(for: section)
                    }
                    .scrollDisabled(section == .about)
                    .frame(maxWidth: .infinity, maxHeight: .infinity)
                    .scrollBounceBehavior(.basedOnSize)
                }
                .padding(.horizontal, 24)
                .padding(.top, 16)
                .frame(width: proxy.size.width, height: proxy.size.height, alignment: .topLeading)
            }
            .background(.ultraThinMaterial)
            .overlay(alignment: .bottom) {
                if section == .updates {
                    updatesFloatingBar
                        .padding(.horizontal, 24)
                        .padding(.bottom, 16)
                }
            }
        }
    }

    @ViewBuilder
    private func scrollContent(for section: SettingsSection) -> some View {
        if section == .appearance {
            appearanceSection
            .padding(.top, 12)
            .frame(maxWidth: .infinity, alignment: .leading)
        } else {
            VStack(alignment: .leading, spacing: 24) {
                content(for: section)
                Spacer(minLength: 0)
            }
            .padding(.top, 12)
            .padding(.bottom, section == .updates ? 92 : 0)
            .frame(maxWidth: .infinity, alignment: .leading)
        }
    }

    @ViewBuilder
    private func content(for section: SettingsSection) -> some View {
        switch section {
        case .general:
            generalSection
        case .appearance:
            appearanceSection
        case .performance:
            performanceSection
        case .titles:
            titlesSection
        case .appSources:
            appSourcesSection
        case .hiddenApps:
            hiddenAppsSection
        case .uninstall:
            uninstallSection
        case .shortcuts:
            shortcutsSection
        case .backup:
            backupSection
        case .development:
            developmentSection
        // case .aiOverlay:
        //     aiOverlaySection
        case .sound:
            soundSection
        case .gameController:
            gameControllerSection
        case .updates:
            updatesSection
        case .about:
            aboutSection
        }
    }

    private var gameControllerSection: some View {
        VStack(alignment: .leading, spacing: 18) {
            // Experimental gesture UI.
            // Remove this card together with the gesture AppStore fields,
            // LaunchpadApp gesture wiring, and LaunchNext/Gesture/ if the
            // low-level multitouch feature is removed later.
            VStack(alignment: .leading, spacing: 12) {
                Text(appStore.localized(.gameControllerPlaceholderTitle))
                    .font(.headline.weight(.semibold))

                Toggle(isOn: $appStore.gameControllerEnabled) {
                    Text(appStore.localized(.gameControllerToggleTitle))
                        .font(.subheadline.weight(.semibold))
                }
                .toggleStyle(.switch)

                Toggle(isOn: $appStore.gameControllerMenuTogglesLaunchpad) {
                    Text(appStore.localized(.gameControllerMenuToggleTitle))
                        .font(.subheadline.weight(.semibold))
                }
                .toggleStyle(.switch)
                .disabled(!appStore.gameControllerEnabled)
                .opacity(appStore.gameControllerEnabled ? 1 : 0.5)

                Text(appStore.localized(.gameControllerMenuToggleSubtitle))
                    .font(.footnote)
                    .foregroundStyle(.secondary)
                    .opacity(appStore.gameControllerEnabled ? 1 : 0.6)

                VStack(alignment: .leading, spacing: 6) {
                    Text(gameControllerStatusText)
                        .font(.callout.weight(.medium))
                        .foregroundStyle(.primary)

                    Text(appStore.localized(.gameControllerPlaceholderSubtitle))
                        .font(.footnote)
                        .foregroundStyle(.secondary)
                }
            }
            .padding(18)
            .frame(maxWidth: .infinity, alignment: .leading)
            .background(
                RoundedRectangle(cornerRadius: 18, style: .continuous)
                    .fill(Color(nsColor: .quaternarySystemFill))
            )

            VStack(alignment: .leading, spacing: 8) {
                Text(appStore.localized(.gameControllerQuickGuideTitle))
                    .font(.footnote.weight(.semibold))

                VStack(alignment: .leading, spacing: 6) {
                    guideRow(icon: "dpad", text: appStore.localized(.gameControllerQuickGuideDirection))
                    guideRow(icon: "a.circle.fill", text: appStore.localized(.gameControllerQuickGuideSelect))
                    guideRow(icon: "b.circle.fill", text: appStore.localized(.gameControllerQuickGuideCancel))
                    if appStore.gameControllerMenuTogglesLaunchpad {
                        guideRow(icon: "line.3.horizontal", text: appStore.localized(.gameControllerQuickGuideMenuToggle))
                    }
                }
            }
        }
    }

    private func guideRow(icon: String, text: String) -> some View {
        HStack(alignment: .center, spacing: 10) {
            Image(systemName: icon)
                .font(.subheadline.weight(.semibold))
                .symbolRenderingMode(.monochrome)
                .foregroundStyle(Color.accentColor)
                .frame(width: 18)

            Text(text)
                .font(.footnote)
                .foregroundStyle(.secondary)
        }
    }

    private var gameControllerStatusText: String {
        if !appStore.gameControllerEnabled {
            return appStore.localized(.gameControllerStatusDisabled)
        }

        let names = controllerManager.connectedControllerNames
        guard !names.isEmpty else {
            return appStore.localized(.gameControllerStatusNoController)
        }

        let joined = names.joined(separator: ", ")
        return String(format: appStore.localized(.gameControllerStatusConnectedFormat), joined)
    }

    private var soundSection: some View {
        VStack(alignment: .leading, spacing: 18) {
            Toggle(isOn: $appStore.soundEffectsEnabled) {
                Text(appStore.localized(.soundToggleTitle))
                    .font(.subheadline.weight(.semibold))
            }
            .toggleStyle(.switch)

            Text(appStore.localized(.soundToggleDescription))
                .font(.footnote)
                .foregroundStyle(.secondary)

            VStack(alignment: .leading, spacing: 12) {
                soundPickerRow(title: .soundEventLaunchpadOpen, binding: $appStore.soundLaunchpadOpenSound)
                soundPickerRow(title: .soundEventLaunchpadClose, binding: $appStore.soundLaunchpadCloseSound)
                soundPickerRow(title: .soundEventNavigation, binding: $appStore.soundNavigationSound)
            }

            Divider()

            Toggle(isOn: $appStore.voiceFeedbackEnabled) {
                Text(appStore.localized(.voiceToggleTitle))
                    .font(.subheadline.weight(.semibold))
            }
            .toggleStyle(.switch)

            Text(appStore.localized(.voiceToggleDescription))
                .font(.footnote)
                .foregroundStyle(.secondary)

            Text(appStore.localized(.voiceNoteMutualExclusive))
                .font(.caption)
                .foregroundStyle(.secondary)
        }
        .padding(20)
        .frame(maxWidth: .infinity, alignment: .leading)
        .background(
            RoundedRectangle(cornerRadius: 18, style: .continuous)
                .fill(Color(nsColor: .quaternarySystemFill))
        )
    }

    private func soundPickerRow(title: LocalizationKey, binding: Binding<String>) -> some View {
        HStack(alignment: .center, spacing: 12) {
            Text(appStore.localized(title))
                .font(.subheadline.weight(.semibold))

            Spacer(minLength: 24)

            Picker("", selection: binding) {
                Text(appStore.localized(.soundOptionNone)).tag("")
                ForEach(SoundManager.systemSoundOptions) { option in
                    Text(option.displayName).tag(option.id)
                }
            }
            .labelsHidden()
            .frame(minWidth: 140)

            Button(appStore.localized(.soundPreviewButton)) {
                SoundManager.shared.preview(systemSoundNamed: binding.wrappedValue)
            }
            .disabled(binding.wrappedValue.isEmpty)
        }
        .padding(12)
        .background(
            RoundedRectangle(cornerRadius: 12, style: .continuous)
                .fill(Color(nsColor: .windowBackgroundColor))
        )
    }

    private var backupSection: some View {
        VStack(alignment: .leading, spacing: 12) {
            Text(appStore.localized(.backupPlaceholderTitle))
                .font(.headline)

            HStack(spacing: 12) {
                updateControlButton(
                    title: appStore.localized(.backupChooseFolderButton),
                    systemImage: "folder"
                ) {
                    chooseBackupFolder()
                }

                updateControlButton(
                    title: appStore.localized(.backupCreateButton),
                    systemImage: "tray.and.arrow.down",
                    isPrimary: true
                ) {
                    createBackupInSelectedFolder()
                }
                .disabled(backupRootURL == nil)

                updateControlButton(
                    title: appStore.localized(.backupDeleteSelectedButton),
                    systemImage: "trash"
                ) {
                    deleteSelectedBackups()
                }
                .disabled(selectedBackupIDs.isEmpty)
            }

            DisclosureGroup(isExpanded: $showCleanupCommand) {
                VStack(alignment: .leading, spacing: 8) {
                    Text(appStore.localized(.backupCleanupIntroPrimary))
                        .font(.callout)
                        .foregroundStyle(.secondary)

                    Text(appStore.localized(.backupCleanupIntroSecondary))
                        .font(.callout)
                        .foregroundStyle(.secondary)

                    Text(appStore.localized(.backupCleanupWarning))
                        .font(.callout.weight(.semibold))
                        .foregroundStyle(.secondary)

                    Text(appStore.localized(.backupCleanupInstruction))
                        .font(.callout)
                        .foregroundStyle(.secondary)

                    HStack {
                        Spacer()
                        Button {
                            copyCleanupCommand()
                        } label: {
                            Label(cleanupCommandCopied
                                  ? appStore.localized(.backupCleanupCopiedLabel)
                                  : appStore.localized(.backupCleanupCopyButton),
                                  systemImage: cleanupCommandCopied ? "checkmark" : "doc.on.doc")
                        }
                        .buttonStyle(.bordered)
                    }

                    Text(dataStoreCleanupCommand)
                        .font(.system(.footnote, design: .monospaced))
                        .textSelection(.enabled)
                        .padding(10)
                        .frame(maxWidth: .infinity, alignment: .leading)
                        .background(
                            RoundedRectangle(cornerRadius: 8, style: .continuous)
                                .fill(Color(nsColor: .windowBackgroundColor))
                        )

                    Text(appStore.localized(.backupCleanupCommandDetails))
                        .font(.callout)
                        .foregroundStyle(.secondary)
                }
            } label: {
                Label(appStore.localized(.backupCleanupDisclosureTitle), systemImage: "wand.and.stars")
                    .font(.callout.weight(.semibold))
            }

            if let backupRootURL {
                Text(backupRootURL.path)
                    .font(.footnote)
                    .foregroundStyle(.secondary)
                    .lineLimit(1)
            } else {
                Text(appStore.localized(.backupNoFolderSelected))
                    .font(.footnote)
                    .foregroundStyle(.secondary)
            }

            if backupEntries.isEmpty {
                Text(appStore.localized(.backupNoBackupsFound))
                    .font(.footnote)
                    .foregroundStyle(.secondary)
            } else {
                VStack(spacing: 0) {
                    ForEach(Array(backupEntries.enumerated()), id: \.element.id) { index, entry in
                        HStack {
                            Toggle("", isOn: selectionBinding(for: entry.id))
                                .labelsHidden()
                                .toggleStyle(.checkbox)

                            VStack(alignment: .leading, spacing: 2) {
                                Text(entry.displayDate)
                                    .font(.callout.weight(.semibold))
                                Text(entry.displaySize)
                                    .font(.caption)
                                    .foregroundStyle(.secondary)
                            }
                            Spacer()
                            Button(appStore.localized(.backupImportButton)) {
                                importDataFolder(from: entry.url)
                            }
                            .buttonStyle(.bordered)

                            Button(appStore.localized(.backupDeleteButton)) {
                                deleteBackup(entry)
                            }
                            .buttonStyle(.bordered)
                            .tint(.red)
                        }
                        .padding(.horizontal, 12)
                        .padding(.vertical, 10)

                        if index < backupEntries.count - 1 {
                            Divider()
                        }
                    }
                }
                .background(
                    RoundedRectangle(cornerRadius: 12, style: .continuous)
                        .fill(Color(nsColor: .windowBackgroundColor))
                )

                Text(appStore.localized(.backupEstimatedSizeHint))
                    .font(.caption)
                    .foregroundStyle(.secondary)
                    .padding(.top, 6)
            }
        }
    }

    private var backupRootURL: URL? {
        guard !backupRootPath.isEmpty else { return nil }
        return URL(fileURLWithPath: backupRootPath, isDirectory: true)
    }

    private var backupEntries: [BackupEntry] {
        _ = backupRefreshToken
        guard let root = backupRootURL else { return [] }
        let fm = FileManager.default
        guard let contents = try? fm.contentsOfDirectory(at: root, includingPropertiesForKeys: [.isDirectoryKey], options: [.skipsHiddenFiles]) else {
            return []
        }

        let formatter = DateFormatter()
        formatter.locale = Locale(identifier: "en_US_POSIX")
        formatter.dateFormat = "yyyy-MM-dd'_'HH.mm.ss"

        var entries: [BackupEntry] = []
        for url in contents {
            let name = url.lastPathComponent
            guard name.hasPrefix("LaunchNext_"), name.hasSuffix(".launchnext") else { continue }
            let isDirectory = (try? url.resourceValues(forKeys: [.isDirectoryKey]).isDirectory) ?? false
            guard isDirectory else { continue }
            let storeURL = url.appendingPathComponent("Data.store")
            guard fm.fileExists(atPath: storeURL.path) else { continue }
            let rawDate = name
                .replacingOccurrences(of: "LaunchNext_", with: "")
                .replacingOccurrences(of: ".launchnext", with: "")
            guard let date = formatter.date(from: rawDate) else { continue }
            let size = dataStoreSize(at: url)
            entries.append(BackupEntry(id: url.path, url: url, date: date, sizeBytes: size))
        }

        return entries.sorted { $0.date > $1.date }
    }

    private struct BackupEntry: Identifiable {
        let id: String
        let url: URL
        let date: Date
        let sizeBytes: Int64

        var displayDate: String {
            let formatter = DateFormatter()
            formatter.locale = .current
            formatter.dateStyle = .medium
            formatter.timeStyle = .short
            return formatter.string(from: date)
        }

        var displaySize: String {
            let formatter = ByteCountFormatter()
            formatter.countStyle = .file
            return formatter.string(fromByteCount: sizeBytes)
        }
    }

    private func dataStoreSize(at url: URL) -> Int64 {
        let storeURL = url.appendingPathComponent("Data.store")
        guard let attributes = try? FileManager.default.attributesOfItem(atPath: storeURL.path),
              let size = attributes[.size] as? NSNumber else {
            return 0
        }
        return size.int64Value
    }

    private var dataStoreCleanupCommand: String {
        let dataStorePath: String
        if let supportURL = try? supportDirectoryURL() {
            dataStorePath = supportURL.appendingPathComponent("Data.store").path
        } else {
            let home = FileManager.default.homeDirectoryForCurrentUser.path
            dataStorePath = "\(home)/Library/Application Support/LaunchNext/Data.store"
        }
        let escapedPath = dataStorePath.replacingOccurrences(of: "\"", with: "\\\"")
        return """
        DB="\(escapedPath)"
        sqlite3 "$DB" <<'SQL'
        PRAGMA wal_checkpoint(FULL);
        DELETE FROM ACHANGE;
        VACUUM;
        SQL
        """
    }

    private func copyCleanupCommand() {
        let pasteboard = NSPasteboard.general
        pasteboard.clearContents()
        pasteboard.setString(dataStoreCleanupCommand, forType: .string)
        cleanupCommandCopied = true
        DispatchQueue.main.asyncAfter(deadline: .now() + 1.2) {
            cleanupCommandCopied = false
        }
    }

    private func chooseBackupFolder() {
        let panel = NSOpenPanel()
        panel.canChooseFiles = false
        panel.canChooseDirectories = true
        panel.canCreateDirectories = true
        panel.allowsMultipleSelection = false
        panel.prompt = appStore.localized(.chooseButton)
        if panel.runModal() == .OK, let url = panel.url {
            backupRootPath = url.path
            UserDefaults.standard.set(backupRootPath, forKey: "backupRootDirectory")
            backupRefreshToken = UUID()
            selectedBackupIDs.removeAll()
        }
    }

    private func createBackupInSelectedFolder() {
        guard let destParent = backupRootURL else { return }
        do {
            try exportDataFolder(to: destParent)
            backupRefreshToken = UUID()
        } catch {
            showBackupExportError(error)
        }
    }

    private func selectionBinding(for id: String) -> Binding<Bool> {
        Binding(
            get: { selectedBackupIDs.contains(id) },
            set: { isSelected in
                if isSelected {
                    selectedBackupIDs.insert(id)
                } else {
                    selectedBackupIDs.remove(id)
                }
            }
        )
    }

    private func deleteSelectedBackups() {
        let targets = backupEntries.filter { selectedBackupIDs.contains($0.id) }
        guard !targets.isEmpty else { return }

        let alert = NSAlert()
        alert.messageText = appStore.localized(.backupDeleteMultipleTitle)
        alert.informativeText = String(format: appStore.localized(.backupDeleteMultipleMessageFormat), targets.count)
        alert.alertStyle = .warning
        let deleteButton = alert.addButton(withTitle: appStore.localized(.backupDeleteButton))
        if #available(macOS 11.0, *) {
            deleteButton.hasDestructiveAction = true
        }
        alert.addButton(withTitle: appStore.localized(.cancel))

        let handler: (NSApplication.ModalResponse) -> Void = { response in
            guard response == .alertFirstButtonReturn else { return }
            for entry in targets {
                try? FileManager.default.removeItem(at: entry.url)
            }
            selectedBackupIDs.removeAll()
            backupRefreshToken = UUID()
        }

        if let window = NSApp.keyWindow ?? NSApp.mainWindow {
            alert.beginSheetModal(for: window, completionHandler: handler)
        } else {
            handler(alert.runModal())
        }
    }

    private func deleteBackup(_ entry: BackupEntry) {
        let alert = NSAlert()
        alert.messageText = appStore.localized(.backupDeleteSingleTitle)
        alert.informativeText = appStore.localized(.backupDeleteSingleMessage)
        alert.alertStyle = .warning
        let deleteButton = alert.addButton(withTitle: appStore.localized(.backupDeleteButton))
        if #available(macOS 11.0, *) {
            deleteButton.hasDestructiveAction = true
        }
        alert.addButton(withTitle: appStore.localized(.cancel))

        let handler: (NSApplication.ModalResponse) -> Void = { response in
            guard response == .alertFirstButtonReturn else { return }
            do {
                try FileManager.default.removeItem(at: entry.url)
                backupRefreshToken = UUID()
            } catch {
                // ignore for now
            }
        }

        if let window = NSApp.keyWindow ?? NSApp.mainWindow {
            alert.beginSheetModal(for: window, completionHandler: handler)
        } else {
            handler(alert.runModal())
        }
    }

    private var developmentSection: some View {
        VStack(alignment: .leading, spacing: 12) {
            Text(appStore.localized(.developmentPlaceholderTitle))
                .font(.headline)
            Text(appStore.localized(.developmentPlaceholderSubtitle))
                .font(.footnote)
                .foregroundStyle(.secondary)

            updateControlButton(
                title: appStore.localized(.developmentForceOnboardingButton),
                systemImage: "rectangle.stack.badge.play",
                isPrimary: true
            ) {
                appStore.forceShowOnboarding()
            }
            .disabled(!appStore.isFullscreenMode)
            .opacity(appStore.isFullscreenMode ? 1 : 0.45)
            Text(appStore.localized(.developmentForceOnboardingHint))
                .font(.caption)
                .foregroundStyle(.secondary)

            updateControlButton(
                title: "Test update notification",
                systemImage: "bell.badge"
            ) {
                appStore.sendTestUpdateNotification()
            }

            VStack(alignment: .leading, spacing: 8) {
                Text("Screenshot background")
                    .font(.headline)

                updateControlButton(
                    title: "Pure White",
                    systemImage: "sun.max.fill"
                ) {
                    appStore.developmentBackgroundOverride = .solidWhite
                }

                updateControlButton(
                    title: "Pure Black",
                    systemImage: "moon.fill"
                ) {
                    appStore.developmentBackgroundOverride = .solidBlack
                }

                updateControlButton(
                    title: "Clear",
                    systemImage: "arrow.counterclockwise"
                ) {
                    appStore.developmentBackgroundOverride = .none
                }

                Text("Development-only preview override, not persisted.")
                    .font(.caption)
                    .foregroundStyle(.secondary)
            }

            HStack(spacing: 6) {
                Image(systemName: "memorychip")
                Text(currentMemoryUsageString())
            }
            .font(.caption.monospacedDigit())
            .foregroundStyle(.secondary)

            Toggle(appStore.localized(.showFPSOverlay), isOn: $appStore.showFPSOverlay)
                .toggleStyle(.switch)
            Text(appStore.localized(.showFPSOverlayDisclaimer))
                .font(.caption)
                .foregroundStyle(.secondary)
            Text(appStore.localized(.showFPSOverlayWarning))
                .font(.caption)
                .foregroundStyle(.secondary)

            Divider()

            VStack(alignment: .leading, spacing: 8) {
                Text(appStore.localized(.importLegacy))
                    .font(.headline)
                Button { importLegacyArchive() } label: {
                    Label(appStore.localized(.importLegacy), systemImage: "clock.arrow.circlepath")
                }
                Text(appStore.localized(.importTip))
                    .font(.footnote)
                    .foregroundStyle(.secondary)
            }

            Divider()

            Text(appStore.localized(.modifiedFrom))
                .font(.footnote)
                .foregroundStyle(.secondary)
        }
    }

    // private var aiOverlaySection: some View {
    //     VStack(alignment: .leading, spacing: 20) {
    //         Toggle(isOn: $appStore.isAIEnabled) {
    //             Text(appStore.localized(.aiFeatureToggleTitle))
    //                 .font(.headline)
    //         }
    //         .toggleStyle(.switch)
    //
    //         Text("AI features are experimental. It’s recommended to keep them off unless you’re testing.")
    //             .font(.footnote)
    //             .foregroundStyle(.secondary)
    //
    //         Text(appStore.localized(.aiOverlayShortcutHint))
    //             .font(.footnote)
    //             .foregroundStyle(.secondary)
    //
    //         Button {
    //             appStore.presentAIOverlayPreview()
    //         } label: {
    //             Label(appStore.localized(.aiOverlayPreviewButtonLabel), systemImage: "sparkles")
    //                 .font(.headline)
    //                 .frame(maxWidth: .infinity)
    //                 .padding(.vertical, 6)
    //         }
    //         .buttonStyle(.borderedProminent)
    //         .tint(Color.accentColor)
    //         .disabled(!appStore.isAIEnabled)
    //     }
    //     .frame(maxWidth: .infinity, alignment: .leading)
    // }

    private var performanceSection: some View {
        let stats = appStore.cacheStatistics
        let isLeanMode = appStore.performanceMode == .lean
        let canUseCAGrid = appStore.performanceMode == .lean

        return VStack(alignment: .leading, spacing: 10) {
            VStack(alignment: .leading, spacing: 8) {
                Text(appStore.localized(.performanceModeTitle))
                    .font(.title3.weight(.semibold))
                Text(appStore.localized(.performanceModeSubtitle))
                    .font(.callout)
                    .foregroundStyle(.secondary)

                performanceModePicker()

                Text(appStore.localized(isLeanMode ? .performanceModeDescriptionLean : .performanceModeDescriptionFull))
                    .font(.footnote)
                    .foregroundStyle(.secondary)

                Divider()

                HStack(alignment: .center, spacing: 10) {
                    HStack(alignment: .top, spacing: 8) {
                        Text(appStore.localized(.performanceRendererBadge))
                            .font(.caption2.weight(.semibold))
                            .foregroundStyle(Color.accentColor)
                            .padding(.horizontal, 6)
                            .padding(.vertical, 2)
                            .background(Color.accentColor.opacity(0.15), in: Capsule())
                        Text(appStore.localized(.performanceRendererTitle))
                            .font(.headline)
                    }
                    Spacer()
                    Toggle("", isOn: $appStore.useCAGridRenderer)
                        .labelsHidden()
                        .toggleStyle(.switch)
                        .disabled(!canUseCAGrid)
                }
                .opacity(canUseCAGrid ? 1 : 0.5)

                if !canUseCAGrid {
                    Text(appStore.localized(.performanceRendererSubtitle))
                        .font(.footnote)
                        .foregroundStyle(.secondary)
                }

                if appStore.useCAGridRenderer {
                    Text(appStore.localized(.performanceRendererWarning))
                        .font(.footnote)
                        .foregroundStyle(Color.accentColor)
                }

                if !appStore.useCAGridRenderer {
                    Text(appStore.localized(.performanceRendererRecommendation))
                        .font(.caption)
                        .foregroundStyle(Color.accentColor)
                }
            }
            .padding(10)
            .frame(maxWidth: .infinity, alignment: .leading)
            .liquidGlass(in: RoundedRectangle(cornerRadius: 16, style: .continuous))

            VStack(alignment: .leading, spacing: 8) {
                HStack(spacing: 8) {
                    Text(appStore.localized(.performanceCacheTitle))
                        .font(.title3.weight(.semibold))
                    Spacer()
                    if isLeanMode {
                        leanModeBadge()
                    }
                    cacheStatusBadge(isValid: stats.isCacheValid)
                }

                Text("\(appStore.localized(.performanceCacheLastUpdateLabel)): \(formattedCacheUpdate(stats.lastUpdate))")
                    .font(.footnote)
                    .foregroundStyle(.secondary)

                if isLeanMode {
                    Text(appStore.localized(.performanceCacheLeanHint))
                        .font(.footnote)
                        .foregroundStyle(.secondary)
                }

                LazyVGrid(columns: [GridItem(.flexible()), GridItem(.flexible())], spacing: 8) {
                    cacheCountRow(title: appStore.localized(.performanceCacheIconLabel),
                                  valueText: isLeanMode ? appStore.localized(.performanceCacheIconsDisabled) : "\(stats.iconCacheSize)")
                    cacheCountRow(title: appStore.localized(.performanceCacheAppInfoLabel),
                                  valueText: "\(stats.appInfoCacheSize)")
                    cacheCountRow(title: appStore.localized(.performanceCacheGridLabel),
                                  valueText: "\(stats.gridLayoutCacheSize)")
                    cacheCountRow(title: appStore.localized(.performanceCacheTotalLabel),
                                  valueText: "\(stats.totalCacheSize)")
                }

                Button {
                    appStore.clearCache()
                    IconStore.shared.clear()
                    FolderPreviewCache.shared.clear()
                } label: {
                    Label(appStore.localized(.performanceCacheClearButton), systemImage: "trash")
                        .font(.footnote.weight(.semibold))
                        .frame(maxWidth: .infinity)
                        .padding(.vertical, 6)
                }
                .buttonStyle(.bordered)
            }
            .padding(10)
            .frame(maxWidth: .infinity, alignment: .leading)
            .liquidGlass(in: RoundedRectangle(cornerRadius: 16, style: .continuous))
        }
        .onChange(of: appStore.performanceMode) { _, _ in
            showPerformanceRestartPrompt = true
        }
        .alert(appStore.localized(.performanceModeRestartTitle), isPresented: $showPerformanceRestartPrompt) {
            Button(appStore.localized(.okButton), role: .cancel) {}
        } message: {
            Text(appStore.localized(.performanceModeRestartMessage))
        }
    }

    private var hiddenAppsSection: some View {
        return LazyVStack(alignment: .leading, spacing: 16) {
            HStack {
                Button {
                    presentHiddenAppPicker()
                } label: {
                    Label(appStore.localized(.hiddenAppsAddButton), systemImage: "eye.slash")
                }
                Spacer()
            }

            DisclosureGroup(isExpanded: $showHiddenApps) {
                LazyVStack(alignment: .leading, spacing: 16){
                    if hasHiddenAppEntries {
                        Text(appStore.localized(.hiddenAppsHint))
                            .font(.footnote)
                            .foregroundStyle(.secondary)
                        
                        TextField("", text: $hiddenSearch, prompt: Text(appStore.localized(.hiddenAppsSearchPlaceholder)))
                            .textFieldStyle(.roundedBorder)
                            .padding(3)
                        
                        if hasHiddenAppEntriesSearchResult {
                            LazyVStack(spacing: 12) {
                                ForEach(cachedHiddenAppEntries.prefix(hiddenVisibleLimit)) { entry in
                                    hiddenAppRow(for: entry)
                                }
                                if cachedHiddenAppEntries.count > hiddenVisibleLimit {
                                    Button(appStore.localized(.loadMore)) {
                                        hiddenVisibleLimit = min(hiddenVisibleLimit + listPageSize,
                                                                 cachedHiddenAppEntries.count)
                                    }
                                    .buttonStyle(.bordered)
                                }
                            }
                        } else {
                            Text(appStore.localized(.customTitleNoResults))
                                .font(.callout)
                                .foregroundStyle(.secondary)
                                .frame(maxWidth: .infinity, minHeight: 120, alignment: .center)
                        }
                    } else {
                        hiddenAppsEmptyState
                    }
                }
            } label: {
                Label(appStore.localized(.settingsSectionHiddenApps), systemImage: "eye.slash")
                    .font(.headline)
            }
                
            DisclosureGroup(isExpanded: $showNotHiddenApps) {
                LazyVStack(alignment: .leading, spacing: 16){
                    if hasNotHiddenAppEntries{
                        Spacer()
                        Text(appStore.localized(.notHiddenAppsHint))
                            .font(.footnote)
                            .foregroundStyle(.secondary)
                        
                        TextField("", text: $notHiddenSearch, prompt: Text(appStore.localized(.notHiddenAppsSearchPlaceholder)))
                            .textFieldStyle(.roundedBorder)
                            .padding(3)
                        
                        if hasNotHiddenAppEntriesSearchResult{
                            LazyVStack(spacing: 12) {
                                ForEach(cachedNotHiddenAppEntries.prefix(notHiddenVisibleLimit)) { entry in
                                    notHiddenAppRow(for: entry)
                                }
                                if cachedNotHiddenAppEntries.count > notHiddenVisibleLimit {
                                    Button(appStore.localized(.loadMore)) {
                                        notHiddenVisibleLimit = min(notHiddenVisibleLimit + listPageSize,
                                                                    cachedNotHiddenAppEntries.count)
                                    }
                                    .buttonStyle(.bordered)
                                }
                            }
                        } else {
                            Text(appStore.localized(.customTitleNoResults))
                                .font(.callout)
                                .foregroundStyle(.secondary)
                                .frame(maxWidth: .infinity, minHeight: 120, alignment: .center)
                        }
                    }
                }
            } label: {
                Label(appStore.localized(.notHiddenAppsTitle), systemImage: "eye")
                    .font(.headline)
            }
                
        }
        .onAppear(perform: updateCachedHiddenAndNotHiddenAppEntries)
        .onChange(of: hiddenSearch, initial: false) { _, _ in
            hiddenVisibleLimit = listPageSize
            scheduleHiddenSearchUpdate()
        }
        .onChange(of: notHiddenSearch, initial: false) { _, _ in
            notHiddenVisibleLimit = listPageSize
            if showNotHiddenApps {
                scheduleNotHiddenSearchUpdate()
            }
        }
        .onChange(of: showNotHiddenApps, initial: false) { _, isExpanded in
            if isExpanded {
                notHiddenVisibleLimit = listPageSize
                updateCachedNotHiddenAppEntries()
            }
        }
        .onChange(of: appStore.apps, initial: false, updateCachedHiddenAndNotHiddenAppEntries)
        .onChange(of: appStore.folders, initial: false, updateCachedHiddenAndNotHiddenAppEntries)
        .onChange(of: appStore.hiddenAppPaths, initial: false, updateCachedHiddenAndNotHiddenAppEntries)
    }

    private var hiddenAppEntries: [AppEntry] {
        appStore.hiddenAppPaths
            .map { path in
                let info = appStore.appInfoForCustomTitle(path: path)
                let defaultName = appStore.defaultDisplayName(for: path)
                return AppEntry(id: path, appInfo: info, defaultName: defaultName)
            }
            .sorted { lhs, rhs in
                lhs.appInfo.name.localizedCaseInsensitiveCompare(rhs.appInfo.name) == .orderedAscending
            }
    }
    
    private var notHiddenAppEntries: [AppEntry] {
        visibleNonHiddenApps
            .map { info in
                let path = info.url.path
                let defaultName = appStore.defaultDisplayName(for: path)
                return AppEntry(id: path, appInfo: info, defaultName: defaultName)
            }
            .sorted { lhs, rhs in
                lhs.appInfo.name.localizedCaseInsensitiveCompare(rhs.appInfo.name) == .orderedAscending
            }
    }

    private var visibleNonHiddenApps: [AppInfo] {
        var dedupedByPath: [String: AppInfo] = [:]
        for app in appStore.apps {
            dedupedByPath[standardizePath(app.url.path)] = app
        }
        for folder in appStore.folders {
            for app in folder.apps {
                let key = standardizePath(app.url.path)
                if dedupedByPath[key] == nil {
                    dedupedByPath[key] = app
                }
            }
        }
        return Array(dedupedByPath.values)
    }
    
    private func matches(_ entry: AppEntry, query: String) -> Bool {
        let options: String.CompareOptions = [
            .caseInsensitive,
            .diacriticInsensitive,
            .widthInsensitive
        ]
            
        return entry.appInfo.name.range(of: query, options: options) != nil
            || entry.defaultName.range(of: query, options: options) != nil
            || entry.id.range(of: query, options: options) != nil
    }
    
    private func filter(_ base: [AppEntry], by rawQuery: String) -> [AppEntry] {
        let query = rawQuery.trimmingCharacters(in: .whitespacesAndNewlines)
        guard !query.isEmpty else { return base }
        return base.filter { entry in
            matches(entry, query: query)
        }
    }

    private var hiddenAppsEmptyState: some View {
        VStack(alignment: .leading, spacing: 12) {
            Text(appStore.localized(.hiddenAppsEmptyTitle))
                .font(.headline)
        }
        .padding(20)
        .frame(maxWidth: .infinity, alignment: .leading)
        .liquidGlass(in: RoundedRectangle(cornerRadius: 18, style: .continuous))
    }

    private func hiddenAppRow(for entry: AppEntry) -> some View {
        HStack(alignment: .center, spacing: 12) {
            Image(nsImage: IconStore.shared.icon(for: entry.appInfo))
                .resizable()
                .aspectRatio(contentMode: .fit)
                .frame(width: 40, height: 40)
                .cornerRadius(10)

            VStack(alignment: .leading, spacing: 4) {
                Text(entry.appInfo.name)
                    .font(.callout.weight(.semibold))
                Text(entry.defaultName)
                    .font(.caption)
                    .foregroundStyle(.secondary)
                Text(entry.id)
                    .font(.caption2)
                    .foregroundStyle(.tertiary)
                    .lineLimit(1)
            }

            Spacer()

            Button {
                appStore.unhideApp(path: entry.id)
            } label: {
                Text(appStore.localized(.hiddenAppsRemoveButton))
            }
            .buttonStyle(.bordered)
        }
        .padding(14)
        .liquidGlass(in: RoundedRectangle(cornerRadius: 16, style: .continuous))
        .frame(maxWidth: .infinity, alignment: .leading)
    }
    
    private func notHiddenAppRow(for entry: AppEntry) -> some View {
        HStack(alignment: .center, spacing: 12) {
            Image(nsImage: IconStore.shared.icon(for: entry.appInfo))
                .resizable()
                .aspectRatio(contentMode: .fit)
                .frame(width: 40, height: 40)
                .cornerRadius(10)
            
            VStack(alignment: .leading, spacing: 4) {
                Text(entry.appInfo.name)
                    .font(.callout.weight(.semibold))
                Text(entry.defaultName)
                    .font(.callout)
                    .foregroundStyle(.secondary)
                Text(entry.id)
                    .font(.caption2)
                    .foregroundStyle(.tertiary)
                    .lineLimit(1)
            }
            
            Spacer()
            
            Button {
                appStore.hideApp(atPath: entry.id)
            } label: {
                Text(appStore.localized(.hiddenAppsAddButton))
            }
            .buttonStyle(.bordered)
        }
        .padding(14)
        .liquidGlass(in: RoundedRectangle(cornerRadius: 16, style: .continuous))
        .frame(maxWidth: .infinity, alignment: .leading)
    }

    private struct AppEntry: Identifiable {
        let id: String
        let appInfo: AppInfo
        let defaultName: String
    }
    
    private func updateCachedHiddenAppEntries() {
        cachedHiddenAppEntries.removeAll()
        hasHiddenAppEntries = !hiddenAppEntries.isEmpty
        let filteredHiddenAppEntries = filter(hiddenAppEntries, by: hiddenSearch)
        hasHiddenAppEntriesSearchResult = !filteredHiddenAppEntries.isEmpty
        cachedHiddenAppEntries.append(contentsOf: filteredHiddenAppEntries)
    }
    
    private func updateCachedNotHiddenAppEntries() {
        guard showNotHiddenApps else {
            cachedNotHiddenAppEntries.removeAll()
            hasNotHiddenAppEntries = false
            hasNotHiddenAppEntriesSearchResult = false
            return
        }

        cachedNotHiddenAppEntries.removeAll()
        hasNotHiddenAppEntries = !notHiddenAppEntries.isEmpty
        let filteredNotHiddenAppEntries = filter(notHiddenAppEntries, by: notHiddenSearch)
        hasNotHiddenAppEntriesSearchResult = !filteredNotHiddenAppEntries.isEmpty
        cachedNotHiddenAppEntries.append(contentsOf: filteredNotHiddenAppEntries)
    }
    
    private func updateCachedHiddenAndNotHiddenAppEntries() {
        updateCachedHiddenAppEntries()
        updateCachedNotHiddenAppEntries()
    }

    private func scheduleHiddenSearchUpdate() {
        hiddenSearchDebounceID += 1
        let token = hiddenSearchDebounceID
        DispatchQueue.main.asyncAfter(deadline: .now() + 0.3) {
            if hiddenSearchDebounceID == token {
                updateCachedHiddenAppEntries()
            }
        }
    }

    private func scheduleNotHiddenSearchUpdate() {
        notHiddenSearchDebounceID += 1
        let token = notHiddenSearchDebounceID
        DispatchQueue.main.asyncAfter(deadline: .now() + 0.3) {
            if notHiddenSearchDebounceID == token {
                updateCachedNotHiddenAppEntries()
            }
        }
    }

    private var uninstallSection: some View {
        let rawPath = appStore.uninstallToolAppPath.trimmingCharacters(in: .whitespacesAndNewlines)
        let toolURL = appStore.uninstallToolAppURL
        let hasSelection = !rawPath.isEmpty
        let isMissing = appStore.uninstallToolConfiguredButMissing
        let fallbackName = rawPath.isEmpty ? "" : URL(fileURLWithPath: rawPath).deletingPathExtension().lastPathComponent
        let displayName = toolURL == nil ? fallbackName : appStore.uninstallToolAppDisplayName

        return VStack(alignment: .leading, spacing: 14) {
            VStack(alignment: .leading, spacing: 12) {
                VStack(alignment: .leading, spacing: 5) {
                    Label(appStore.localized(.settingsSectionUninstall), systemImage: "trash.fill")
                        .font(.headline)
                    Text(appStore.localized(.uninstallSectionDescription))
                        .font(.footnote)
                        .foregroundStyle(.secondary)
                        .fixedSize(horizontal: false, vertical: true)
                }

                HStack(alignment: .top, spacing: 14) {
                    ZStack {
                        RoundedRectangle(cornerRadius: 16, style: .continuous)
                            .fill(
                                LinearGradient(
                                    colors: [Color.red.opacity(0.14), Color.orange.opacity(0.10)],
                                    startPoint: .topLeading,
                                    endPoint: .bottomTrailing
                                )
                            )

                        Image(nsImage: appStore.uninstallToolAppIcon)
                            .resizable()
                            .interpolation(.high)
                            .antialiased(true)
                            .frame(width: 38, height: 38)
                            .cornerRadius(10)
                    }
                    .frame(width: 56, height: 56)

                    VStack(alignment: .leading, spacing: 6) {
                        HStack(alignment: .firstTextBaseline, spacing: 8) {
                            Text(hasSelection ? (displayName.isEmpty ? rawPath : displayName) : appStore.localized(.uninstallToolNotConfigured))
                                .font(.headline)
                                .lineLimit(1)

                            Spacer(minLength: 0)

                            uninstallToolStatusBadge(isMissing: isMissing, hasSelection: hasSelection)
                        }

                        if hasSelection {
                            if !rawPath.isEmpty {
                                Text(rawPath)
                                    .font(.caption)
                                    .foregroundStyle(.secondary)
                                    .lineLimit(2)
                                    .textSelection(.enabled)
                            }

                            HStack(spacing: 8) {
                                if !appStore.uninstallToolBundleIdentifier.isEmpty {
                                    uninstallToolMetaPill(appStore.uninstallToolBundleIdentifier, systemImage: "number")
                                }
                                if !appStore.uninstallToolVersionText.isEmpty {
                                    uninstallToolMetaPill(appStore.uninstallToolVersionText, systemImage: "tag")
                                }
                            }
                        } else {
                            Text(appStore.localized(.uninstallToolPathLabel))
                                .font(.caption)
                                .foregroundStyle(.secondary)
                        }

                        if isMissing {
                            Text(appStore.localized(.uninstallToolMissing))
                                .font(.caption)
                                .foregroundStyle(.red)
                                .fixedSize(horizontal: false, vertical: true)
                        }
                    }
                }
                .padding(14)
                .background(
                    RoundedRectangle(cornerRadius: 16, style: .continuous)
                        .fill(Color.red.opacity(colorScheme == .dark ? 0.10 : 0.07))
                )
                .overlay(
                    RoundedRectangle(cornerRadius: 16, style: .continuous)
                        .stroke(Color.red.opacity(colorScheme == .dark ? 0.22 : 0.18), lineWidth: 1)
                )

                HStack(spacing: 10) {
                    Button {
                        presentUninstallToolPicker()
                    } label: {
                        Label(appStore.localized(.uninstallToolChooseButton), systemImage: "plus.circle.fill")
                            .frame(maxWidth: .infinity)
                    }
                    .buttonStyle(.borderedProminent)

                    Button {
                        if !appStore.openConfiguredUninstallTool() {
                            NSSound.beep()
                        }
                    } label: {
                        Label(appStore.localized(.uninstallToolOpenButton), systemImage: "arrow.up.forward.app")
                            .frame(maxWidth: .infinity)
                    }
                    .buttonStyle(.bordered)
                    .disabled(appStore.uninstallToolAppURL == nil)

                    Button(role: .destructive) {
                        _ = appStore.setUninstallToolApplication(url: nil)
                    } label: {
                        Label(appStore.localized(.uninstallToolClearButton), systemImage: "trash")
                            .frame(maxWidth: .infinity)
                    }
                    .buttonStyle(.bordered)
                    .disabled(!hasSelection)
                }
            }
            .padding(16)
            .frame(maxWidth: .infinity, alignment: .leading)
            .liquidGlass(in: RoundedRectangle(cornerRadius: 16, style: .continuous))

        }
    }

    private func uninstallToolStatusBadge(isMissing: Bool, hasSelection: Bool) -> some View {
        let title: String
        let symbol: String
        let fillColor: Color
        let foreground: Color

        if isMissing {
            title = appStore.localized(.uninstallToolMissing)
            symbol = "exclamationmark.triangle.fill"
            fillColor = Color.red.opacity(colorScheme == .dark ? 0.22 : 0.14)
            foreground = .red
        } else if hasSelection {
            title = appStore.localized(.uninstallToolOpenButton)
            symbol = "checkmark.circle.fill"
            fillColor = Color.green.opacity(colorScheme == .dark ? 0.20 : 0.12)
            foreground = .green
        } else {
            title = appStore.localized(.uninstallToolChooseButton)
            symbol = "circle.dashed"
            fillColor = Color.primary.opacity(colorScheme == .dark ? 0.16 : 0.08)
            foreground = .secondary
        }

        return Label(title, systemImage: symbol)
            .font(.caption.weight(.semibold))
            .lineLimit(1)
            .padding(.horizontal, 10)
            .padding(.vertical, 6)
            .background(fillColor, in: Capsule())
            .foregroundStyle(foreground)
    }

    private func uninstallToolMetaPill(_ text: String, systemImage: String) -> some View {
        return Label(text, systemImage: systemImage)
            .font(.caption)
            .lineLimit(1)
            .padding(.horizontal, 8)
            .padding(.vertical, 5)
            .background(Color.primary.opacity(colorScheme == .dark ? 0.12 : 0.06), in: Capsule())
            .foregroundStyle(.secondary)
    }
    
    private var titlesSection: some View {
        LazyVStack(alignment: .leading, spacing: 16){
            HStack {
                Button {
                    presentCustomTitlePicker()
                } label: {
                    Label(appStore.localized(.customTitleAddFromFolder), systemImage: "plus")
                }
                Spacer()
            }

            Text(appStore.localized(.customTitleHint))
                .font(.footnote)
                .foregroundStyle(.secondary)
            
            HStack(){
                Text(appStore.localized(.customTitleOnly))
                    .font(.callout)
                    .frame(maxWidth: .infinity, alignment: .leading)
                Toggle("", isOn: $showOnlyEditedTittleApps)
                    .labelsHidden()
                    .toggleStyle(.switch)
                    .disabled(appStore.customTitles.isEmpty)
                    .onChange(of: appStore.customTitles.isEmpty, initial: true) { _, isEmply in
                        if isEmply {
                            showOnlyEditedTittleApps = false
                        }
                    }
            }

            if hasAllAppEntries{
                TextField("", text: $allAppsSearch, prompt: Text(appStore.localized(.renameSearchPlaceholder)))
                    .textFieldStyle(.roundedBorder)
                    .padding(3)
                
                if hasAllAppEntriesSearchResult{
                    let visibleEntries: [AppEntry] = showOnlyEditedTittleApps
                        ? cachedAllAppEntries
                        : Array(cachedAllAppEntries.prefix(allAppsVisibleLimit))
                    LazyVStack(spacing: 12) {
                        ForEach(visibleEntries){ entry in
                            customTitleRow(for: entry)
                        }
                        if !showOnlyEditedTittleApps && cachedAllAppEntries.count > allAppsVisibleLimit {
                            Button(appStore.localized(.loadMore)) {
                                allAppsVisibleLimit = min(allAppsVisibleLimit + listPageSize,
                                                          cachedAllAppEntries.count)
                            }
                            .buttonStyle(.bordered)
                        }
                    }
                } else {
                    Text(appStore.localized(.customTitleNoResults))
                        .font(.callout)
                        .foregroundStyle(.secondary)
                        .frame(maxWidth: .infinity, minHeight: 120, alignment: .center)
                }
            }
        }
        .onAppear(perform: updateCachedAllAppEntries)
        .onChange(of: allAppsSearch, initial: false) { _, _ in
            allAppsVisibleLimit = listPageSize
            scheduleAllAppsSearchUpdate()
        }
        .onChange(of: showOnlyEditedTittleApps, initial: false) { _, _ in
            allAppsVisibleLimit = listPageSize
            updateCachedAllAppEntries()
        }
        .onChange(of: appStore.customTitles, initial: false, updateCachedAllAppEntries)
        .onChange(of: appStore.apps, initial: false, updateCachedAllAppEntries)
        .onChange(of: appStore.folders, initial: false, updateCachedAllAppEntries)
        .onChange(of: appStore.hiddenAppPaths, initial: false, updateCachedAllAppEntries)
    }
    
    private var customTitleEntries: [AppEntry] {
        appStore.customTitles
            .map { (path, _) in
                let info = appStore.appInfoForCustomTitle(path: path)
                let defaultName = appStore.defaultDisplayName(for: path)
                return AppEntry(id: path, appInfo: info, defaultName: defaultName)
            }
            .sorted { lhs, rhs in
                lhs.appInfo.name.localizedCaseInsensitiveCompare(rhs.appInfo.name) == .orderedAscending
            }
    }
    
    private var allAppEntries: [AppEntry] {
        var allEntries: [AppEntry] = []
        allEntries.append(contentsOf: notHiddenAppEntries)
        allEntries.append(contentsOf: hiddenAppEntries)
        allEntries.sort { lhs, rhs in
            lhs.appInfo.name.localizedCaseInsensitiveCompare(rhs.appInfo.name) == .orderedAscending
        }
        return allEntries
    }
    
    private func updateCachedAllAppEntries() {
        cachedAllAppEntries.removeAll()
        
        if (showOnlyEditedTittleApps){
            hasAllAppEntries = !customTitleEntries.isEmpty
            let filteredCustomTitleEntries = filter(customTitleEntries, by: allAppsSearch)
            hasAllAppEntriesSearchResult = !filteredCustomTitleEntries.isEmpty
            cachedAllAppEntries.append(contentsOf: filteredCustomTitleEntries)
        } else {
            hasAllAppEntries = !allAppEntries.isEmpty
            let filteredAllAppEntries = filter(allAppEntries, by: allAppsSearch)
            hasAllAppEntriesSearchResult = !filteredAllAppEntries.isEmpty
            cachedAllAppEntries.append(contentsOf: filteredAllAppEntries)
        }
    }

    private func scheduleAllAppsSearchUpdate() {
        allAppsSearchDebounceID += 1
        let token = allAppsSearchDebounceID
        DispatchQueue.main.asyncAfter(deadline: .now() + 0.3) {
            if allAppsSearchDebounceID == token {
                updateCachedAllAppEntries()
            }
        }
    }

    @ViewBuilder
    private func customTitleRow(for entry: AppEntry) -> some View {
        let isEditing = editingEntries.contains(entry.id)
        let currentDraft = editingDrafts[entry.id] ?? appStore.customTitles[entry.id] ?? entry.appInfo.name
        let trimmedDraft = currentDraft.trimmingCharacters(in: .whitespacesAndNewlines)
        let originalValue = appStore.customTitles[entry.id] ?? entry.defaultName
        let draftBinding = Binding(
            get: { editingDrafts[entry.id] ?? appStore.customTitles[entry.id] ?? entry.appInfo.name },
            set: { editingDrafts[entry.id] = $0 }
        )

        VStack(alignment: .leading, spacing: 10) {
            HStack(alignment: .center, spacing: 12) {
                Image(nsImage: IconStore.shared.icon(for: entry.appInfo))
                    .resizable()
                    .aspectRatio(contentMode: .fit)
                    .frame(width: 40, height: 40)
                    .cornerRadius(10)

                VStack(alignment: .leading, spacing: 4) {
                    Text(entry.appInfo.name)
                        .font(.callout.weight(.semibold))
                    Text(String(format: appStore.localized(.customTitleDefaultFormat), entry.defaultName))
                        .font(.caption)
                        .foregroundStyle(.secondary)
                }

                Spacer()

                VStack(alignment: .trailing, spacing: 10) {
                    if isEditing {
                        Button(appStore.localized(.customTitleSave)) {
                            saveCustomTitle(entry)
                        }
                        .buttonStyle(.borderedProminent)
                        .disabled(trimmedDraft.isEmpty || trimmedDraft == originalValue)
                        Button(appStore.localized(.customTitleCancel)) {
                            cancelEditing(entry)
                        }
                        .buttonStyle(.bordered)

                        if !(appStore.customTitles[entry.id]?.isEmpty ?? true) {
                            Button(role: .destructive) {
                                removeCustomTitle(entry)
                            } label: {
                                Text(appStore.localized(.customTitleReset))
                            }
                            .buttonStyle(.bordered)
                        }

                    } else {
                        Button(appStore.localized(.customTitleEdit)) {
                            beginEditing(entry)
                        }
                        .buttonStyle(.bordered)

                        if !(appStore.customTitles[entry.id]?.isEmpty ?? true) {
                            Button(role: .destructive) {
                                removeCustomTitle(entry)
                            } label: {
                                Text(appStore.localized(.customTitleReset))
                            }
                            .buttonStyle(.bordered)
                        }
                    }
                }
            }

            if isEditing {
                TextField("", text: draftBinding, prompt: Text(appStore.localized(.customTitlePlaceholder)))
                    .textFieldStyle(.roundedBorder)
            }
        }
        .padding(14)
        .liquidGlass(in: RoundedRectangle(cornerRadius: 16, style: .continuous))
        .frame(maxWidth: .infinity, alignment: .leading)
    }

    private func presentHiddenAppPicker() {
        let panel = NSOpenPanel()
        panel.canChooseFiles = true
        panel.canChooseDirectories = false
        panel.allowsMultipleSelection = true
        panel.allowedContentTypes = [.applicationBundle]
        panel.prompt = appStore.localized(.hiddenAppsAddButton)
        panel.title = appStore.localized(.hiddenAppsAddButton)

        if panel.runModal() == .OK {
            if !appStore.hideApps(at: panel.urls) {
                NSSound.beep()
            }
        }
    }

    private func presentUninstallToolPicker() {
        let panel = NSOpenPanel()
        panel.canChooseFiles = true
        panel.canChooseDirectories = false
        panel.allowsMultipleSelection = false
        panel.allowedContentTypes = [.applicationBundle]
        panel.title = appStore.localized(.uninstallToolPanelTitle)
        panel.prompt = appStore.localized(.uninstallToolChooseButton)

        if panel.runModal() == .OK, let url = panel.url {
            if !appStore.setUninstallToolApplication(url: url) {
                NSSound.beep()
            }
        }
    }

    private func presentCustomTitlePicker() {
        let panel = NSOpenPanel()
        panel.canChooseFiles = true
        panel.canChooseDirectories = false
        panel.allowsMultipleSelection = false
        panel.allowedContentTypes = [.applicationBundle]
        panel.title = appStore.localized(.customTitleAddButton)
        panel.message = appStore.localized(.customTitlePickerMessage)
        panel.prompt = appStore.localized(.chooseButton)

        if panel.runModal() == .OK, let url = panel.url, let info = appStore.ensureCustomTitleEntry(for: url) {
            let path = info.url.path
            editingEntries.insert(path)
            editingDrafts[path] = appStore.customTitles[path] ?? info.name
            if !showOnlyEditedTittleApps {
                showOnlyEditedTittleApps = true
                allAppsSearch = ""
            }
        }
    }

    private func presentAppIconPicker() {
        let panel = NSOpenPanel()
        panel.canChooseFiles = true
        panel.canChooseDirectories = false
        panel.allowsMultipleSelection = false
        panel.allowedContentTypes = [.icns, .png, .jpeg, .tiff]
        panel.prompt = appStore.localized(.customIconChoose)
        panel.title = appStore.localized(.customIconTitle)

        if panel.runModal() == .OK, let url = panel.url {
            if !appStore.setCustomAppIcon(from: url) {
                iconImportError = appStore.localized(.customIconError)
            }
        }
    }

    private func presentAppSourcePicker() {
        let panel = NSOpenPanel()
        panel.canChooseFiles = false
        panel.canChooseDirectories = true
        panel.allowsMultipleSelection = true
        panel.prompt = appStore.localized(.chooseButton)

        if panel.runModal() == .OK {
            var addedAny = false
            for url in panel.urls {
                if appStore.addCustomAppSource(path: url.path) {
                    addedAny = true
                }
            }
            if !addedAny && !panel.urls.isEmpty {
                NSSound.beep()
            }
        }
    }

    private func pathExists(_ path: String) -> Bool {
        var isDir: ObjCBool = false
        return FileManager.default.fileExists(atPath: path, isDirectory: &isDir) && isDir.boolValue
    }

    private func displayName(for path: String) -> String {
        let url = URL(fileURLWithPath: path)
        let name = url.lastPathComponent
        return name.isEmpty ? path : name
    }

    @ViewBuilder
    private func appSourceRow(icon: String, path: String, isAvailable: Bool, @ViewBuilder accessory: () -> some View) -> some View {
        HStack(alignment: .center, spacing: 12) {
            Image(systemName: icon)
                .font(.system(size: 18, weight: .semibold))
                .foregroundStyle(.secondary)
                .frame(width: 24, alignment: .center)

            VStack(alignment: .leading, spacing: 2) {
                HStack(spacing: 8) {
                    Text(displayName(for: path))
                        .font(.body)
                    if !isAvailable {
                        Text(appStore.localized(.scanSourcesMissingBadge))
                            .font(.caption.weight(.semibold))
                            .foregroundStyle(Color.orange)
                            .padding(.horizontal, 8)
                            .padding(.vertical, 2)
                            .background(Capsule().fill(Color.orange.opacity(0.18)))
                    }
                }
                Text(path)
                    .font(.footnote)
                    .foregroundStyle(.secondary)
            }

            Spacer(minLength: 12)
            accessory()
        }
        .padding(.vertical, 8)
        .padding(.horizontal, 12)
        .background(
            RoundedRectangle(cornerRadius: 12, style: .continuous)
                .fill(Color.secondary.opacity(0.08))
        )
    }

//    private struct CustomTitleEntry: Identifiable {
//        let id: String
//        let appInfo: AppInfo
//        let defaultName: String
//    }

    private func beginEditing(_ entry: AppEntry) {
        editingEntries.insert(entry.id)
        editingDrafts[entry.id] = appStore.customTitles[entry.id] ?? entry.appInfo.name
    }

    private func cancelEditing(_ entry: AppEntry) {
        editingEntries.remove(entry.id)
        editingDrafts.removeValue(forKey: entry.id)
    }

    private func saveCustomTitle(_ entry: AppEntry) {
        let draft = (editingDrafts[entry.id] ?? appStore.customTitles[entry.id] ?? entry.appInfo.name)
            .trimmingCharacters(in: .whitespacesAndNewlines)
        guard !draft.isEmpty else { return }
        let original = appStore.customTitles[entry.id] ?? entry.defaultName
        if draft == original {
            editingEntries.remove(entry.id)
            editingDrafts.removeValue(forKey: entry.id)
            return
        }
        appStore.setCustomTitle(draft, for: entry.appInfo)
        editingEntries.remove(entry.id)
        editingDrafts.removeValue(forKey: entry.id)
    }

    private func removeCustomTitle(_ entry: AppEntry) {
        appStore.clearCustomTitle(for: entry.appInfo)
        editingEntries.remove(entry.id)
        editingDrafts.removeValue(forKey: entry.id)
    }

    private static let modifierOnlyKeyCodes: Set<UInt16> = [55, 54, 58, 61, 56, 60, 59, 62, 57]

    private func startShortcutCapture(for target: ShortcutTarget) {
        stopShortcutCapture(cancel: false)
        pendingShortcut = nil
        capturingShortcutTarget = target
        if target == .launchpad {
            // Temporarily disable active hotkey while user is recording a new one.
            AppDelegate.shared?.updateGlobalHotKey(configuration: nil)
        }
        shortcutCaptureMonitor = NSEvent.addLocalMonitorForEvents(matching: [.keyDown]) { event in
            handleShortcutCapture(event: event)
        }
    }

    private func stopShortcutCapture(cancel: Bool) {
        let hadCaptureTarget = capturingShortcutTarget
        if let monitor = shortcutCaptureMonitor {
            NSEvent.removeMonitor(monitor)
            shortcutCaptureMonitor = nil
        }
        if cancel {
            pendingShortcut = nil
            if capturingShortcutTarget != nil { NSSound.beep() }
        }
        capturingShortcutTarget = nil
        if hadCaptureTarget == .launchpad {
            appStore.syncGlobalHotKeyRegistration()
        }
    }

    private func handleShortcutCapture(event: NSEvent) -> NSEvent? {
        let normalizedFlags = event.modifierFlags.normalizedShortcutFlags

        if event.keyCode == 53 && normalizedFlags.isEmpty {
            stopShortcutCapture(cancel: true)
            return nil
        }

        guard !normalizedFlags.isEmpty, !Self.modifierOnlyKeyCodes.contains(event.keyCode) else {
            NSSound.beep()
            return nil
        }

        pendingShortcut = AppStore.HotKeyConfiguration(keyCode: event.keyCode, modifierFlags: normalizedFlags)
        return nil
    }

    private func savePendingShortcut() {
        guard let shortcut = pendingShortcut, let target = capturingShortcutTarget else { return }
        switch target {
        case .launchpad:
            appStore.setGlobalHotKey(keyCode: shortcut.keyCode, modifierFlags: shortcut.modifierFlags)
        // case .aiOverlay:
        //     appStore.setAIOverlayHotKey(keyCode: shortcut.keyCode, modifierFlags: shortcut.modifierFlags)
        }
        pendingShortcut = nil
        stopShortcutCapture(cancel: false)
    }

    private func shortcutStatusText(for target: ShortcutTarget) -> String {
        if capturingShortcutTarget == target {
            if let shortcut = pendingShortcut {
                let base = shortcut.displayString
                if shortcut.modifierFlags.isEmpty {
                    return base + " • " + appStore.localized(.shortcutNoModifierWarning)
                }
                return base
            }
            return appStore.localized(.shortcutCapturePrompt)
        }
        let placeholder = appStore.localized(.shortcutNotSet)
        switch target {
        case .launchpad:
            return appStore.hotKeyDisplayText(nonePlaceholder: placeholder)
        // case .aiOverlay:
        //     return appStore.aiOverlayHotKeyDisplayText(nonePlaceholder: placeholder)
        }
    }

    private func isCapturingShortcut(_ target: ShortcutTarget) -> Bool {
        capturingShortcutTarget == target
    }

    @ViewBuilder
    private var headlineGlass: some View {
        PressableGlassTitle(text: appStore.localized(.appTitle))
    }

    private struct PressableGlassTitle: View {
        let text: String

        @GestureState private var isPressed = false
        @State private var bounce = false

        private var scale: CGFloat {
            if isPressed { return 0.97 }
            if bounce { return 1.01 }
            return 1.0
        }

        private var shadowOpacity: Double {
            isPressed ? 0.18 : 0.0
        }

        private var shadowRadius: CGFloat {
            isPressed ? 8 : 0
        }

        private var shadowOffsetY: CGFloat {
            isPressed ? 4 : 0
        }

        var body: some View {
            let label = Text(text)
                .font(.largeTitle.weight(.semibold))
                .foregroundStyle(.white)
                .padding(.horizontal, 18)
                .padding(.vertical, 10)

            label
                .liquidGlass(.clear, in: Capsule())
                .clipShape(Capsule())
                .shadow(color: Color.black.opacity(shadowOpacity), radius: shadowRadius, x: 0, y: shadowOffsetY)
                .scaleEffect(scale)
                .contentShape(Capsule())
                .gesture(pressGesture)
                .animation(.easeOut(duration: 0.12), value: isPressed)
                .animation(.spring(response: 0.26, dampingFraction: 0.62), value: bounce)
        }

        private var pressGesture: some Gesture {
            DragGesture(minimumDistance: 0)
                .onChanged { _ in
                    if bounce { bounce = false }
                }
                .updating($isPressed) { _, state, _ in
                    state = true
                }
                .onEnded { _ in
                    bounce = true
                    DispatchQueue.main.asyncAfter(deadline: .now() + 0.12) {
                        bounce = false
                    }
                }
        }
    }


    private var aboutSection: some View {
        VStack(alignment: .leading, spacing: 16) {
            ZStack(alignment: .center) {
                Image("AboutBackground")
                    .resizable()
                    .interpolation(.high)
                    .aspectRatio(16.0/9.0, contentMode: .fill)
                    .frame(maxWidth: .infinity)
                    .clipped()

                VStack(spacing: 12) {
                    headlineGlass

                    Text(String(format: appStore.localized(.versionLabelFormat),
                                getVersion(fallback: appStore.localized(.versionFallback))))
                        .font(.title2.weight(.semibold))
                        .foregroundStyle(.white)

                    Text(appStore.localized(.backgroundHint))
                        .font(.footnote)
                        .foregroundStyle(.white.opacity(0.85))
                }
                .multilineTextAlignment(.center)
                .padding(.horizontal, 20)
                .padding(.vertical, 18)
            }
            .frame(maxWidth: .infinity)
            .frame(minHeight: 180, maxHeight: 200)
            .clipShape(RoundedRectangle(cornerRadius: 18, style: .continuous))
            .overlay(
                RoundedRectangle(cornerRadius: 18, style: .continuous)
                    .stroke(Color.white.opacity(0.18), lineWidth: 1.4)
            )
            .padding(.bottom, 12)

            HStack(alignment: .bottom, spacing: 12) {
                TicTacToeBoard()
                    .frame(width: 130)

                infoCard
            }

            Spacer()

            HStack(spacing: 12) {
                glassButton(title: appStore.localized(.aboutProjectLink), systemImage: "arrow.up.right.square") {
                    if let url = URL(string: "https://github.com/RoversX/LaunchNext") {
                        NSWorkspace.shared.open(url)
                    }
                }
                glassButton(title: appStore.localized(.aboutReportBug), systemImage: "exclamationmark.bubble") {
                    if let url = URL(string: "https://github.com/RoversX/LaunchNext/issues") {
                        NSWorkspace.shared.open(url)
                    }
                }
                glassButton(title: appStore.localized(.aboutContribute), systemImage: "hands.sparkles") {
                    if let url = URL(string: "https://github.com/RoversX/LaunchNext") {
                        NSWorkspace.shared.open(url)
                    }
                }
                glassButton(title: appStore.localized(.aboutBlog), systemImage: "globe") {
                    if let url = URL(string: "https://blog.closex.org") {
                        NSWorkspace.shared.open(url)
                    }
                }
            }
            .frame(maxWidth: .infinity)
        }
        .frame(maxWidth: .infinity, minHeight: 550, alignment: .top)
        .frame(maxHeight: .infinity, alignment: .top)
    }

    @ViewBuilder
    private var infoCard: some View {
        let cardFill = colorScheme == .light ? Color.white : Color.white.opacity(0.05)
        VStack(alignment: .leading, spacing: 10) {
            Text(appStore.localized(.aboutInfoSystemTitle))
                .font(.headline.weight(.semibold))
            infoRow(label: appStore.localized(.aboutInfoMacOSLabel), value: systemVersionText)

            Divider()

            Text(appStore.localized(.aboutInfoProcessorTitle))
                .font(.headline.weight(.semibold))
            infoRow(label: appStore.localized(.aboutInfoChipLabel), value: chipText)

            Divider()

            Text(appStore.localized(.aboutInfoDisplayTitle))
                .font(.headline.weight(.semibold))
            infoRow(label: displayNameText, value: displayResolutionText)
        }
        .padding(14)
        .background(
            RoundedRectangle(cornerRadius: 14, style: .continuous)
                .fill(cardFill)
        )
        .overlay(
            RoundedRectangle(cornerRadius: 14, style: .continuous)
                .stroke(Color.white.opacity(0.08), lineWidth: 1)
        )
    }

    @ViewBuilder
    private func infoRow(label: String, value: String) -> some View {
        HStack {
            Text(label)
                .foregroundStyle(.primary)
            Spacer()
            Text(value)
                .foregroundStyle(.secondary)
        }
        .font(.subheadline)
    }

    @ViewBuilder
    private func glassButton(title: String, systemImage: String, action: @escaping () -> Void) -> some View {
        Button(action: action) {
            Label(title, systemImage: systemImage)
                .font(.subheadline.weight(.medium))
                .padding(.horizontal, 14)
                .padding(.vertical, 8)
                .frame(maxWidth: .infinity)
        }
        .buttonStyle(.plain)
        .liquidGlass(in: RoundedRectangle(cornerRadius: 20, style: .continuous))
    }

    // MARK: - Inline Games
    private struct TicTacToeBoard: View {
        private enum Mark: String {
            case x = "X", o = "O", empty = ""
        }

        @State private var cells: [Mark] = Array(repeating: .empty, count: 9)
        @State private var isPlayerTurn: Bool = true
        @State private var statusText: String = "Your turn"
        @State private var gameOver: Bool = false

        var body: some View {
            VStack(spacing: 12) {
                LazyVGrid(columns: Array(repeating: GridItem(.flexible(), spacing: 6), count: 3), spacing: 6) {
                    ForEach(0..<9) { index in
                        ZStack {
                            RoundedRectangle(cornerRadius: 12, style: .continuous)
                                .fill(Color.secondary.opacity(0.12))
                            Text(cells[index].rawValue)
                                .font(.system(size: 28, weight: .bold))
                        }
                        .aspectRatio(1, contentMode: .fit)
                        .onTapGesture {
                            guard !gameOver, isPlayerTurn, cells[index] == .empty else { return }
                            makeMove(at: index, mark: .x)
                            DispatchQueue.main.asyncAfter(deadline: .now() + 0.3) {
                                aiTurn()
                            }
                        }
                    }
                }
                Text(statusText)
                    .font(.footnote)
                    .foregroundStyle(.secondary)

                Button(action: resetGame) {
                    Label("Reset", systemImage: "arrow.counterclockwise")
                }
                .buttonStyle(.bordered)
            }
        }

        private func makeMove(at index: Int, mark: Mark) {
            cells[index] = mark
            if let winner = evaluateWinner() {
                statusText = winner == .x ? "You win!" : "AI wins!"
                gameOver = true
            } else if !cells.contains(.empty) {
                statusText = "Draw"
                gameOver = true
            } else {
                isPlayerTurn.toggle()
                statusText = isPlayerTurn ? "Your turn" : "AI thinking..."
            }
        }

        private func aiTurn() {
            guard !gameOver else { return }
            guard !isPlayerTurn else { return }

            let emptyCells = cells.enumerated().filter { $0.element == .empty }.map { $0.offset }
            guard let choice = emptyCells.randomElement() else { return }
            makeMove(at: choice, mark: .o)
        }

        private func evaluateWinner() -> Mark? {
            let lines = [
                [0,1,2],[3,4,5],[6,7,8],
                [0,3,6],[1,4,7],[2,5,8],
                [0,4,8],[2,4,6]
            ]
            for line in lines {
                let marks = line.map { cells[$0] }
                if marks.allSatisfy({ $0 == .x }) { return .x }
                if marks.allSatisfy({ $0 == .o }) { return .o }
            }
            return nil
        }

        private func resetGame() {
            cells = Array(repeating: .empty, count: 9)
            isPlayerTurn = true
            statusText = "Your turn"
            gameOver = false
        }
    }

    private func currentMemoryUsageValue() -> String {
        var info = task_vm_info_data_t()
        var count = mach_msg_type_number_t(MemoryLayout<task_vm_info_data_t>.size) / 4
        let kern = withUnsafeMutablePointer(to: &info) { pointer -> kern_return_t in
            pointer.withMemoryRebound(to: integer_t.self, capacity: Int(count)) {
                task_info(mach_task_self_, task_flavor_t(TASK_VM_INFO), $0, &count)
            }
        }

        guard kern == KERN_SUCCESS else { return "--" }

        let usedBytes = info.phys_footprint
        let formatter = ByteCountFormatter()
        formatter.allowedUnits = [.useMB, .useGB]
        formatter.countStyle = .memory
        return formatter.string(fromByteCount: Int64(usedBytes))
    }

    private func currentMemoryUsageString() -> String {
        "Memory: \(currentMemoryUsageValue())"
    }

    private func formattedCacheUpdate(_ date: Date) -> String {
        if date == .distantPast {
            return appStore.localized(.performanceCacheNever)
        }
        let formatter = DateFormatter()
        formatter.dateStyle = .short
        formatter.timeStyle = .short
        return formatter.string(from: date)
    }

    private func performanceModePicker() -> some View {
        HStack(spacing: 6) {
            performanceModeButton(mode: .lean, title: appStore.localized(.performanceModeLean))
            performanceModeButton(mode: .full, title: appStore.localized(.performanceModeFull))
        }
        .padding(6)
        .frame(maxWidth: .infinity)
        .background(
            RoundedRectangle(cornerRadius: 12, style: .continuous)
                .fill(Color(nsColor: .quaternarySystemFill))
        )
    }

    private func performanceModeButton(mode: PerformanceMode, title: String) -> some View {
        let isSelected = appStore.performanceMode == mode
        return Button {
            withAnimation(.easeInOut(duration: 0.15)) {
                appStore.performanceMode = mode
            }
        } label: {
            Text(title)
                .font(.callout.weight(.semibold))
                .foregroundStyle(isSelected ? Color.accentColor : Color.primary)
                .frame(maxWidth: .infinity)
                .padding(.vertical, 6)
                .background(
                    Capsule(style: .continuous)
                        .fill(isSelected ? Color.accentColor.opacity(0.18) : Color.clear)
                )
                .overlay(
                    Capsule(style: .continuous)
                        .stroke(isSelected ? Color.accentColor.opacity(0.45) : Color.clear, lineWidth: 1)
                )
        }
        .buttonStyle(.plain)
        .frame(maxWidth: .infinity)
        .contentShape(Rectangle())
    }

    private func cacheStatusBadge(isValid: Bool) -> some View {
        let title = appStore.localized(isValid ? .performanceCacheStatusValid : .performanceCacheStatusInvalid)
        let color = isValid ? Color.green : Color.orange
        return Text(title)
            .font(.caption2.weight(.semibold))
            .foregroundStyle(color)
            .padding(.horizontal, 8)
            .padding(.vertical, 4)
            .background(
                Capsule(style: .continuous)
                    .fill(color.opacity(0.16))
            )
    }

    private func leanModeBadge() -> some View {
        Text(appStore.localized(.performanceModeLean))
            .font(.caption2.weight(.semibold))
            .foregroundStyle(Color.green)
            .padding(.horizontal, 8)
            .padding(.vertical, 4)
            .background(
                Capsule(style: .continuous)
                    .fill(Color.green.opacity(0.16))
            )
    }

    private func cacheCountRow(title: String, valueText: String) -> some View {
        HStack(spacing: 8) {
            Text(title)
                .font(.callout)
                .foregroundStyle(.secondary)
            Spacer()
            Text(valueText)
                .font(.callout.weight(.semibold).monospacedDigit())
                .foregroundStyle(.primary)
        }
        .padding(.horizontal, 10)
        .padding(.vertical, 8)
        .frame(maxWidth: .infinity, alignment: .leading)
        .background(
            RoundedRectangle(cornerRadius: 12, style: .continuous)
                .fill(Color(nsColor: .quaternarySystemFill))
        )
    }

    private var generalSection: some View {
        VStack(alignment: .leading, spacing: 24) {
            appearanceModeCard

            loginLayoutCard
                .padding(.top, -10)

            Text(appStore.localized(.lockLayoutDescription))
                .font(.footnote)
                .foregroundStyle(.secondary)
                .padding(.top, -20)

            applicationIconCard
                .padding(.top, -15)

            dataManagementCard
                .padding(.top, -10)

            Text(appStore.localized(.importTip))
                .font(.footnote)
                .foregroundStyle(.secondary)
                .padding(.top, -15)

            HStack {
                Button { appStore.refresh() } label: {
                    Label(appStore.localized(.refresh), systemImage: "arrow.clockwise")
                }
                Spacer()
                Button {
                    showResetConfirm = true
                } label: {
                    Label(appStore.localized(.resetLayout), systemImage: "arrow.counterclockwise")
                        .foregroundStyle(Color.red)
                }
                .alert(appStore.localized(.resetAlertTitle), isPresented: $showResetConfirm) {
                    Button(appStore.localized(.resetConfirm), role: .destructive) { appStore.resetLayout() }
                    Button(appStore.localized(.cancel), role: .cancel) {}
                } message: {
                    Text(appStore.localized(.resetAlertMessage))
                }
                Button {
                    AppDelegate.shared?.quitWithFade()
                } label: {
                    Label(appStore.localized(.quit), systemImage: "xmark.circle")
                        .foregroundStyle(Color.red)
                }
            }
        }
    }

    private var loginLayoutCard: some View {
        VStack(alignment: .leading, spacing: 12) {
            HStack(alignment: .center, spacing: 24) {
                HStack {
                    Text(appStore.localized(.launchAtLoginTitle))
                        .font(.subheadline.weight(.semibold))
                    Spacer()
                    Toggle("", isOn: $appStore.isStartOnLogin)
                        .labelsHidden()
                        .toggleStyle(.switch)
                        .disabled(!appStore.canConfigureStartOnLogin)
                }
                .frame(maxWidth: .infinity, alignment: .leading)

                HStack {
                    Text(appStore.localized(.showQuickRefreshButton))
                        .font(.subheadline.weight(.semibold))
                    Spacer()
                    Toggle("", isOn: $appStore.showQuickRefreshButton)
                        .labelsHidden()
                        .toggleStyle(.switch)
                }
                .frame(maxWidth: .infinity, alignment: .leading)
            }

            Divider()

            HStack(alignment: .center, spacing: 24) {
                HStack {
                    Text(appStore.localized(.lockLayoutTitle))
                        .font(.subheadline.weight(.semibold))
                    Spacer()
                    Toggle("", isOn: $appStore.isLayoutLocked)
                        .labelsHidden()
                        .toggleStyle(.switch)
                }
                .frame(maxWidth: .infinity, alignment: .leading)

                HStack {
                    Text(appStore.localized(.developmentEnableCLICodeTitle))
                        .font(.subheadline.weight(.semibold))
                    Button {
                        if !showCLIInfoPopover {
                            copiedCLICommand = nil
                            cliCommandActionMessage = nil
                            showCLIRemoveInfoPopover = false
                            showCLIFullPathCommand = false
                        }
                        showCLIInfoPopover.toggle()
                    } label: {
                        Image(systemName: "info.circle")
                            .font(.subheadline.weight(.regular))
                            .foregroundStyle(.secondary)
                    }
                    .buttonStyle(.plain)
                    .popover(isPresented: $showCLIInfoPopover, arrowEdge: .top) {
                        VStack(alignment: .leading, spacing: 8) {
                            Text(appStore.localized(.commandLineInterfaceHelpTitle))
                                .font(.headline)
                            Text(appStore.localized(.commandLineInterfaceHelpBody))
                                .font(.footnote)
                                .foregroundStyle(.secondary)
                                .fixedSize(horizontal: false, vertical: true)
                            Text(appStore.localized(.commandLineInterfaceAgentHint))
                                .font(.caption)
                                .foregroundStyle(.secondary)
                                .fixedSize(horizontal: false, vertical: true)
                            Divider()
                            cliCommandRow("LaunchNext --cli help")
                            cliCommandRow("LaunchNext --tui")
                            DisclosureGroup(
                                isExpanded: $showCLIFullPathCommand,
                                content: {
                                    cliCommandRow("/Applications/LaunchNext.app/Contents/MacOS/LaunchNext --tui")
                                        .padding(.top, 4)
                                },
                                label: {
                                    Text(appStore.localized(.commandLineInterfaceShowFullPathCommand))
                                        .font(.caption)
                                        .foregroundStyle(.secondary)
                                }
                            )
                            Divider()
                            HStack(spacing: 8) {
                                Button(role: .destructive) {
                                    if appStore.developmentEnableCLICode {
                                        appStore.developmentEnableCLICode = false
                                        cliCommandActionMessage = appStore.localized(.commandLineInterfaceRemoveCommandDone)
                                    } else {
                                        let removed = appStore.removeInstalledCLICommand()
                                        cliCommandActionMessage = removed
                                            ? appStore.localized(.commandLineInterfaceRemoveCommandDone)
                                            : appStore.localized(.commandLineInterfaceRemoveCommandMissing)
                                    }
                                } label: {
                                    Label(appStore.localized(.commandLineInterfaceRemoveCommandButton), systemImage: "trash")
                                }
                                .buttonStyle(.bordered)

                                Button {
                                    showCLIRemoveInfoPopover.toggle()
                                } label: {
                                    Image(systemName: "info.circle")
                                        .foregroundStyle(.secondary)
                                }
                                .buttonStyle(.plain)
                                .popover(isPresented: $showCLIRemoveInfoPopover, arrowEdge: .bottom) {
                                    VStack(alignment: .leading, spacing: 8) {
                                        Text(appStore.localized(.commandLineInterfaceRemoveCommandInfoTitle))
                                            .font(.headline)
                                        Text(appStore.localized(.commandLineInterfaceRemoveCommandInfoBody))
                                            .font(.footnote)
                                            .foregroundStyle(.secondary)
                                            .fixedSize(horizontal: false, vertical: true)
                                            .textSelection(.enabled)
                                    }
                                    .padding(12)
                                    .frame(width: 390, alignment: .leading)
                                }
                            }
                            if let cliCommandActionMessage {
                                Text(cliCommandActionMessage)
                                    .font(.caption)
                                    .foregroundStyle(.secondary)
                            }
                        }
                        .padding(12)
                        .frame(width: 360, alignment: .leading)
                    }
                    Spacer()
                    Toggle("", isOn: $appStore.developmentEnableCLICode)
                        .labelsHidden()
                        .toggleStyle(.switch)
                }
                .frame(maxWidth: .infinity, alignment: .leading)
            }

            Divider()

            HStack(alignment: .center, spacing: 24) {
                VStack(alignment: .leading, spacing: 4) {
                    HStack {
                        Text(appStore.localized(.kioskModeTitle))
                            .font(.subheadline.weight(.semibold))
                        Spacer()
                        Toggle("", isOn: $appStore.kioskMode)
                            .labelsHidden()
                            .toggleStyle(.switch)
                    }
                    Text(appStore.localized(.kioskModeDescription))
                        .font(.footnote)
                        .foregroundStyle(.secondary)
                }
                .frame(maxWidth: .infinity, alignment: .leading)

                VStack(alignment: .leading, spacing: 4) {
                    HStack {
                        Text(appStore.localized(.autoFullscreenTitle))
                            .font(.subheadline.weight(.semibold))
                        Spacer()
                        Toggle("", isOn: $appStore.autoFullscreen)
                            .labelsHidden()
                            .toggleStyle(.switch)
                            .onAppear {
                                appStore.startAccessibilityPolling()
                            }
                            .onDisappear {
                                appStore.stopAccessibilityPolling()
                            }
                            .onChange(of: appStore.autoFullscreen) { newValue in
                                if newValue && !appStore.isAccessibilityTrusted() {
                                    appStore.autoFullscreen = false
                                    appStore.promptAccessibilityPermission()
                                }
                            }
                    }
                    Text(appStore.localized(.autoFullscreenDescription))
                        .font(.footnote)
                        .foregroundStyle(.secondary)
                }
                .frame(maxWidth: .infinity, alignment: .leading)
            }

            Divider()

            HStack(alignment: .center, spacing: 24) {
                VStack(alignment: .leading, spacing: 4) {
                    HStack {
                        Text(appStore.localized(.showInDockTitle))
                            .font(.subheadline.weight(.semibold))
                        Spacer()
                        Toggle("", isOn: $appStore.showInDock)
                            .labelsHidden()
                            .toggleStyle(.switch)
                    }
                    Text(appStore.localized(.showInDockDescription))
                        .font(.footnote)
                        .foregroundStyle(.secondary)
                }
                .frame(maxWidth: .infinity, alignment: .leading)

                Spacer().frame(maxWidth: .infinity)
            }
        }
        .padding(12)
        .frame(maxWidth: .infinity, alignment: .leading)
        .background(
            RoundedRectangle(cornerRadius: 16, style: .continuous)
                .fill(Color(nsColor: .windowBackgroundColor))
        )
    }

    private var applicationIconCard: some View {
        HStack(alignment: .top, spacing: 16) {
            VStack(alignment: .leading, spacing: 4) {
                Text(appStore.localized(.customIconTitle))
                    .font(.headline)
                let hint = appStore.localized(.customIconHint)
                Text(twoLineHint(hint))
                    .font(.footnote)
                    .foregroundStyle(.secondary)
                    .lineLimit(2)
            }

            Spacer(minLength: 8)

            HStack(alignment: .center, spacing: 12) {
                VStack(alignment: .trailing, spacing: 8) {
                    Button {
                        presentAppIconPicker()
                    } label: {
                        Label(appStore.localized(.customIconChoose), systemImage: "checkmark.circle")
                    }
                    .buttonStyle(.bordered)

                    Button {
                        appStore.resetCustomAppIcon()
                    } label: {
                        Label(appStore.localized(.customIconReset), systemImage: "arrow.counterclockwise")
                    }
                    .buttonStyle(.bordered)
                    .tint(.red)
                    .disabled(!appStore.hasCustomAppIcon)
                }

                Image(nsImage: appStore.currentAppIcon)
                    .resizable()
                    .aspectRatio(contentMode: .fit)
                    .frame(width: 66, height: 66)
                    .cornerRadius(12)
            }
        }
        .padding(12)
        .frame(maxWidth: .infinity, alignment: .leading)
        .background(
            RoundedRectangle(cornerRadius: 16, style: .continuous)
                .fill(Color(nsColor: .windowBackgroundColor))
        )
    }

    @ViewBuilder
    private func cliCommandRow(_ command: String) -> some View {
        HStack(spacing: 8) {
            Text(command)
                .font(.system(size: 12, weight: .regular, design: .monospaced))
                .lineLimit(2)
                .truncationMode(.middle)
                .textSelection(.enabled)
            Spacer(minLength: 6)
            Button {
                copyCLICommand(command)
            } label: {
                Image(systemName: copiedCLICommand == command ? "checkmark.circle.fill" : "doc.on.doc")
                    .foregroundStyle(copiedCLICommand == command ? Color.green : Color.secondary)
            }
            .buttonStyle(.plain)
            .help(appStore.localized(.backupCleanupCopyButton))
        }
    }

    private func copyCLICommand(_ command: String) {
        let pasteboard = NSPasteboard.general
        pasteboard.clearContents()
        pasteboard.setString(command, forType: .string)
        copiedCLICommand = command
        DispatchQueue.main.asyncAfter(deadline: .now() + 1.2) {
            if copiedCLICommand == command {
                copiedCLICommand = nil
            }
        }
    }

    private var dataManagementCard: some View {
        VStack(alignment: .leading, spacing: 10) {
            HStack(alignment: .center) {
                Text(appStore.localized(.dataManagementTitle))
                    .font(.headline)
                Spacer()
                HStack(spacing: 10) {
                    Button { exportDataFolder() } label: {
                        Text(appStore.localized(.exportData))
                    }
                    .buttonStyle(.bordered)

                    Button { importDataFolder() } label: {
                        Text(appStore.localized(.importData))
                    }
                    .buttonStyle(.bordered)
                }
            }

            HStack(spacing: 10) {
                Button { importFromLaunchpad() } label: {
                    Label(appStore.localized(.importSystem), systemImage: "square.and.arrow.down.on.square")
                }
                .buttonStyle(.bordered)
                .help(appStore.localized(.importTip))

                Button {
                    applyMacOS26PresetLayout()
                } label: {
                    Label(appStore.localized(.layoutPresetApplyButton), systemImage: "square.grid.3x3.topleft.filled")
                }
                .buttonStyle(.bordered)
            }
        }
        .padding(12)
        .frame(maxWidth: .infinity, alignment: .leading)
        .background(
            RoundedRectangle(cornerRadius: 16, style: .continuous)
                .fill(Color(nsColor: .windowBackgroundColor))
        )
    }

    private func twoLineHint(_ text: String) -> String {
        let separators = [". ", "。", "！", "？", "；", ";", "，", ",", "、"]
        for sep in separators {
            if let range = text.range(of: sep) {
                let before = text[..<range.upperBound]
                let after = text[range.upperBound...].trimmingCharacters(in: .whitespaces)
                if after.isEmpty {
                    return String(before)
                }
                return String(before) + "\n" + after
            }
        }

        let words = text.split(separator: " ")
        if words.count >= 2 {
            let mid = words.count / 2
            let first = words[..<mid].joined(separator: " ")
            let second = words[mid...].joined(separator: " ")
            return first + "\n" + second
        }

        return text
    }

    @ViewBuilder
    private var appearanceModeCard: some View {
        VStack(alignment: .leading, spacing: 10) {
            HStack(alignment: .top, spacing: 10) {
                Text(appStore.localized(.appearanceModeTitle))
                    .font(.headline)
                    .frame(minWidth: 90, alignment: .leading)

                Spacer(minLength: 8)

                HStack(spacing: 16) {
                    appearanceOptionCard(
                        title: appStore.localized(.appearanceModeFollowSystem),
                        imageName: "AppearanceAuto",
                        mode: .system
                    )
                    appearanceOptionCard(
                        title: appStore.localized(.appearanceModeLight),
                        imageName: "AppearanceLight",
                        mode: .light
                    )
                    appearanceOptionCard(
                        title: appStore.localized(.appearanceModeDark),
                        imageName: "AppearanceDark",
                        mode: .dark
                    )
                }
                .frame(maxWidth: .infinity, alignment: .trailing)
            }

            Divider()

            languageRow
        }
        .padding(10)
        .frame(maxWidth: .infinity, alignment: .leading)
        .background(
            RoundedRectangle(cornerRadius: 16, style: .continuous)
                .fill(Color(nsColor: .windowBackgroundColor))
        )
    }

    private func appearanceOptionCard(title: String, imageName: String, mode: AppearancePreference) -> some View {
        let isSelected = appStore.appearancePreference == mode
        return Button {
            appStore.appearancePreference = mode
        } label: {
            VStack(spacing: 2) {
                Image(imageName)
                    .resizable()
                    .scaledToFit()
                    .frame(width: 60)
                    .clipShape(RoundedRectangle(cornerRadius: 5, style: .continuous))
                    .overlay(
                        RoundedRectangle(cornerRadius: 5, style: .continuous)
                            .stroke(isSelected ? Color.accentColor : Color.primary.opacity(0.08), lineWidth: isSelected ? 2 : 1)
                    )
                Text(title)
                    .font(.caption.weight(.semibold))
                    .foregroundStyle(.primary)
            }
            .frame(minWidth: 52, alignment: .leading)
        }
        .buttonStyle(.plain)
    }

    @ViewBuilder
    private var languageRow: some View {
        HStack(alignment: .center, spacing: 12) {
            Text(appStore.localized(.languagePickerTitle))
                .font(.headline)
                .frame(minWidth: 90, alignment: .leading)
            Spacer()
            Picker("", selection: $appStore.preferredLanguage) {
                ForEach(AppLanguage.allCases) { language in
                    Text(appStore.localizedLanguageName(for: language)).tag(language)
                }
            }
            .labelsHidden()
            .pickerStyle(.menu)
            .frame(width: 180, alignment: .trailing)
        }
        .frame(maxWidth: .infinity, alignment: .leading)
    }

    private var appSourcesSection: some View {
        VStack(alignment: .leading, spacing: 20) {
            VStack(alignment: .leading, spacing: 8) {
                Text(appStore.localized(.scanSourcesIntroTitle))
                    .font(.headline)
                Text(appStore.localized(.scanSourcesIntroDescription))
                    .font(.callout)
                    .foregroundStyle(.secondary)
            }

            VStack(alignment: .leading, spacing: 12) {
                Text(appStore.localized(.scanSourcesDefaultListTitle))
                    .font(.subheadline.weight(.semibold))
                ForEach(appStore.builtinAppSourcePaths, id: \.self) { path in
                    appSourceRow(icon: "internaldrive", path: path, isAvailable: true, accessory: { EmptyView() })
                }
            }

            VStack(alignment: .leading, spacing: 12) {
                HStack(spacing: 12) {
                    Text(appStore.localized(.scanSourcesCustomListTitle))
                        .font(.subheadline.weight(.semibold))
                    Spacer()
                    Button {
                        presentAppSourcePicker()
                    } label: {
                        Label(appStore.localized(.scanSourcesAddButton), systemImage: "plus.circle")
                    }
                    .buttonStyle(.borderless)

                    Button {
                        showAppSourcesResetDialog = true
                    } label: {
                        Label(appStore.localized(.scanSourcesResetButton), systemImage: "arrow.counterclockwise")
                    }
                    .buttonStyle(.borderless)
                    .disabled(appStore.customAppSourcePaths.isEmpty)
                }

                if appStore.customAppSourcePaths.isEmpty {
                    Text(appStore.localized(.scanSourcesEmptyHint))
                        .font(.footnote)
                        .foregroundStyle(.secondary)
                        .padding(.horizontal, 4)
                } else {
                    ForEach(appStore.customAppSourcePaths, id: \.self) { path in
                        VStack(alignment: .leading, spacing: 6) {
                            HStack {
                                appSourceRow(icon: "folder", path: path, isAvailable: pathExists(path)) {
                                    HStack(spacing: 10) {
                                        Button {
                                            toggleExpandedSource(path)
                                        } label: {
                                            // Image(systemName: expandedSource == standardizePath(path) ? "chevron.down.circle" : "chevron.right.circle")
                                            //     .foregroundStyle(.secondary)
                                            Image(systemName: "ellipsis.circle")
                                                .foregroundStyle(.secondary)
                                        }
                                        .buttonStyle(.borderless)

                                        Button {
                                            appStore.removeCustomAppSource(path: path)
                                        } label: {
                                            Image(systemName: "minus.circle.fill")
                                                .foregroundStyle(Color.red)
                                        }
                                        .buttonStyle(.borderless)
                                    }
                                }
                            }

                            if expandedSource == standardizePath(path) {
                                let apps = appsForSource(path)
                                VStack(alignment: .leading, spacing: 8) {
                                    if apps.isEmpty {
                                        Text(appStore.localized(.scanSourcesEmptyHint))
                                            .font(.footnote)
                                            .foregroundStyle(.secondary)
                                            .padding(.horizontal, 4)
                                    } else {
                                        ScrollView {
                                            LazyVStack(alignment: .leading, spacing: 8) {
                                                ForEach(apps, id: \.path) { app in
                                                    HStack(spacing: 8) {
                                                        Image(nsImage: app.icon)
                                                            .resizable()
                                                            .interpolation(.high)
                                                            .antialiased(true)
                                                            .frame(width: 24, height: 24)
                                                            .cornerRadius(5)
                                VStack(alignment: .leading, spacing: 2) {
                                    Text(app.name)
                                        .font(.callout)
                                                                .lineLimit(1)
                                                            Text(app.path)
                                                                .font(.caption2)
                                                                .foregroundStyle(.secondary)
                                                                .lineLimit(1)
                                                        }
                                Spacer()
                                Button(role: .destructive) {
                                    removeAppFromLayout(app.path)
                                                        } label: {
                                                            Image(systemName: "trash")
                                                                .foregroundStyle(Color.red)
                                                        }
                                                        .buttonStyle(.borderless)
                                                    }
                                                    .padding(.horizontal, 6)
                                                }
                                            }
                                            .padding(.vertical, 6)
                                        }
                                        .frame(maxHeight: 220)
                                    }
                                }
                                .padding(.horizontal, 8)
                                .padding(.vertical, 6)
                                .background(
                                    RoundedRectangle(cornerRadius: 10, style: .continuous)
                                        .fill(Color.secondary.opacity(0.08))
                                )
                            }
                        }
                    }
                }
            }
        }
        .confirmationDialog(appStore.localized(.scanSourcesResetButton), isPresented: $showAppSourcesResetDialog, titleVisibility: .visible) {
            Button(appStore.localized(.scanSourcesResetButton), role: .destructive) {
                appStore.resetCustomAppSources()
            }
            Button(appStore.localized(.cancel), role: .cancel) {}
        }
    }

    // MARK: - Helpers
    private struct SourceApp {
        let name: String
        let path: String
        let icon: NSImage
    }

    private func appsForSource(_ sourcePath: String) -> [SourceApp] {
        let normalizedSource = standardizePath(sourcePath)
        let prefix = normalizedSource.hasSuffix("/") ? normalizedSource : normalizedSource + "/"
        var apps: [SourceApp] = []
        var seen: Set<String> = []

        func consider(name: String, path: String, icon: NSImage) {
            let normalized = standardizePath(path)
            guard normalized == normalizedSource || normalized.hasPrefix(prefix) else { return }
            if seen.insert(normalized).inserted {
                apps.append(SourceApp(name: name, path: normalized, icon: icon))
            }
        }

        for item in appStore.items {
            switch item {
            case .app(let app):
                consider(name: app.name, path: app.url.path, icon: IconStore.shared.icon(for: app))
            case .missingApp(let placeholder):
                consider(name: placeholder.displayName, path: placeholder.bundlePath, icon: placeholder.icon)
            case .folder(let folder):
                for app in folder.apps {
                    consider(name: app.name, path: app.url.path, icon: IconStore.shared.icon(for: app))
                }
            case .empty:
                break
            }
        }

        return apps.sorted { $0.name.localizedCaseInsensitiveCompare($1.name) == .orderedAscending }
    }

    private func standardizePath(_ path: String) -> String {
        URL(fileURLWithPath: path).standardized.path
    }

    private struct IndicatorScreenEntry: Identifiable {
        let id: String
        let name: String
        let sizeText: String
        let isConnected: Bool
    }

    private var currentIndicatorScreenID: String? {
        let screen = NSApp.keyWindow?.screen ?? NSScreen.main
        return screen.map { AppStore.screenIdentifier(for: $0) }
    }

    private var indicatorScreenEntries: [IndicatorScreenEntry] {
        let connectedScreens = NSScreen.screens
        var entries: [IndicatorScreenEntry] = []
        var connectedIDs = Set<String>()

        for screen in connectedScreens {
            let id = AppStore.screenIdentifier(for: screen)
            connectedIDs.insert(id)
            entries.append(IndicatorScreenEntry(id: id,
                                                name: screen.localizedName,
                                                sizeText: screenSizeText(screen),
                                                isConnected: true))
        }

        let offlineIDs = appStore.scopedPageIndicatorOverrides(for: selectedAppearanceLayoutMode).keys
            .filter { !connectedIDs.contains($0) }
            .sorted()

        for id in offlineIDs {
            entries.append(IndicatorScreenEntry(id: id,
                                                name: appStore.localized(.indicatorOfflineDisplay),
                                                sizeText: String(format: appStore.localized(.indicatorScreenIDFormat), id),
                                                isConnected: false))
        }

        return entries
    }

    private func screenSizeText(_ screen: NSScreen) -> String {
        let width = Int(screen.frame.width.rounded())
        let height = Int(screen.frame.height.rounded())
        return "\(width)×\(height)"
    }

    private func indicatorCustomBinding(for screenID: String) -> Binding<Bool> {
        Binding(
            get: { appStore.scopedPageIndicatorOverride(for: screenID, mode: selectedAppearanceLayoutMode) != nil },
            set: { isCustom in
                scheduleIndicatorOverrideUpdate {
                    if isCustom {
                        appStore.applyIndicatorDefaults(to: screenID, mode: selectedAppearanceLayoutMode)
                    } else {
                        appStore.setScopedPageIndicatorOverride(nil, for: screenID, mode: selectedAppearanceLayoutMode)
                    }
                }
            }
        )
    }

    private func indicatorOffsetBinding(for screenID: String) -> Binding<Double> {
        Binding(
            get: {
                appStore.scopedPageIndicatorOverride(for: screenID, mode: selectedAppearanceLayoutMode)?.offset
                ?? appStore.scopedPageIndicatorOffset(for: selectedAppearanceLayoutMode)
            },
            set: { newValue in
                scheduleIndicatorOverrideUpdate {
                    let current = appStore.scopedPageIndicatorOverride(for: screenID, mode: selectedAppearanceLayoutMode)
                        ?? AppStore.PageIndicatorOverride(offset: appStore.scopedPageIndicatorOffset(for: selectedAppearanceLayoutMode),
                                                          topPadding: appStore.scopedPageIndicatorTopPadding(for: selectedAppearanceLayoutMode))
                    appStore.setScopedPageIndicatorOverride(AppStore.PageIndicatorOverride(offset: newValue,
                                                                                           topPadding: current.topPadding),
                                                            for: screenID,
                                                            mode: selectedAppearanceLayoutMode)
                }
            }
        )
    }

    private func indicatorTopPaddingBinding(for screenID: String) -> Binding<Double> {
        Binding(
            get: {
                appStore.scopedPageIndicatorOverride(for: screenID, mode: selectedAppearanceLayoutMode)?.topPadding
                ?? appStore.scopedPageIndicatorTopPadding(for: selectedAppearanceLayoutMode)
            },
            set: { newValue in
                scheduleIndicatorOverrideUpdate {
                    let current = appStore.scopedPageIndicatorOverride(for: screenID, mode: selectedAppearanceLayoutMode)
                        ?? AppStore.PageIndicatorOverride(offset: appStore.scopedPageIndicatorOffset(for: selectedAppearanceLayoutMode),
                                                          topPadding: appStore.scopedPageIndicatorTopPadding(for: selectedAppearanceLayoutMode))
                    appStore.setScopedPageIndicatorOverride(AppStore.PageIndicatorOverride(offset: current.offset,
                                                                                           topPadding: newValue),
                                                            for: screenID,
                                                            mode: selectedAppearanceLayoutMode)
                }
            }
        )
    }

    private func scheduleIndicatorOverrideUpdate(_ action: @escaping () -> Void) {
        DispatchQueue.main.async(execute: action)
    }

    private func backgroundMaskColorBinding(isDark: Bool) -> Binding<Color> {
        Binding(
            get: {
                let rgba = isDark ? appStore.backgroundMaskDarkColor : appStore.backgroundMaskLightColor
                return rgba.color
            },
            set: { newValue in
                let updated = AppStore.RGBAColor(newValue)
                let current = isDark ? appStore.backgroundMaskDarkColor : appStore.backgroundMaskLightColor
                guard current != updated else { return }
                if isDark {
                    appStore.backgroundMaskDarkColor = updated
                } else {
                    appStore.backgroundMaskLightColor = updated
                }
            }
        )
    }

    private struct PressFeedbackRowButtonStyle: ButtonStyle {
        var enabled: Bool
        var pressScale: CGFloat

        func makeBody(configuration: Configuration) -> some View {
            configuration.label
                .scaleEffect(scale(for: configuration))
                .animation(LNAnimations.springFast,
                           value: configuration.isPressed && enabled)
        }

        private func scale(for configuration: Configuration) -> CGFloat {
            guard enabled else { return 1.0 }
            let clamped = max(min(pressScale, 1.0), 0.5)
            return configuration.isPressed ? clamped : 1.0
        }
    }

    @ViewBuilder
    private func indicatorOverrideCard(for entry: IndicatorScreenEntry) -> some View {
        let useCustom = indicatorCustomBinding(for: entry.id)
        let offsetValue = appStore.scopedPageIndicatorOverride(for: entry.id, mode: selectedAppearanceLayoutMode)?.offset
            ?? appStore.scopedPageIndicatorOffset(for: selectedAppearanceLayoutMode)
        let topPaddingValue = appStore.scopedPageIndicatorOverride(for: entry.id, mode: selectedAppearanceLayoutMode)?.topPadding
            ?? appStore.scopedPageIndicatorTopPadding(for: selectedAppearanceLayoutMode)

        VStack(alignment: .leading, spacing: 8) {
            HStack(alignment: .center, spacing: 12) {
                VStack(alignment: .leading, spacing: 2) {
                    Text(entry.name)
                        .font(.subheadline.weight(.semibold))
                    Text(entry.sizeText)
                        .font(.caption)
                        .foregroundStyle(.secondary)
                }
                Spacer()
                if !entry.isConnected {
                    Text(appStore.localized(.indicatorOfflineBadge))
                        .font(.caption)
                        .foregroundStyle(.secondary)
                }
                Picker("", selection: useCustom) {
                    Text(appStore.localized(.defaultOption)).tag(false)
                    Text(appStore.localized(.customOption)).tag(true)
                }
                .pickerStyle(.segmented)
                .frame(width: 160)
            }

            if useCustom.wrappedValue {
                VStack(alignment: .leading, spacing: 8) {
                    HStack {
                        Text(appStore.localized(.pageIndicatorOffsetLabel))
                            .font(.caption)
                        Spacer()
                        Text(String(format: "%.0f", offsetValue))
                            .font(.caption.monospacedDigit())
                            .foregroundStyle(.secondary)
                    }
                    Slider(value: indicatorOffsetBinding(for: entry.id), in: 0...80)

                    HStack {
                        Text("0").font(.footnote)
                        Spacer()
                        Text(String(format: "%.0f", offsetValue)).font(.footnote.monospacedDigit())
                        Spacer()
                        Text("80").font(.footnote)
                    }

                    HStack {
                        Text(appStore.localized(.pageIndicatorTopPaddingLabel))
                            .font(.caption)
                        Spacer()
                        Text(String(format: "%.0f", topPaddingValue))
                            .font(.caption.monospacedDigit())
                            .foregroundStyle(.secondary)
                    }
                    Slider(value: indicatorTopPaddingBinding(for: entry.id),
                           in: AppStore.pageIndicatorTopPaddingRange)
                }
            }
        }
        .padding(10)
        .frame(maxWidth: .infinity, alignment: .leading)
        .background(
            RoundedRectangle(cornerRadius: 12, style: .continuous)
                .fill(Color.secondary.opacity(0.08))
        )
    }
    
    @State private var expandedSource: String? = nil
    
    private func toggleExpandedSource(_ path: String) {
        withAnimation(.easeInOut(duration: 0.2)) {
            let normalized = standardizePath(path)
            expandedSource = (expandedSource == normalized) ? nil : normalized
        }
    }

    private func removeAppFromLayout(_ rawPath: String) {
        let normalized = standardizePath(rawPath)
        // Replace matching top-level items with empty placeholders.
        var updatedItems = appStore.items
        for idx in updatedItems.indices {
            switch updatedItems[idx] {
            case .app(let app) where standardizePath(app.url.path) == normalized:
                updatedItems[idx] = .empty(UUID().uuidString)
            case .missingApp(let placeholder) where standardizePath(placeholder.bundlePath) == normalized:
                updatedItems[idx] = .empty(UUID().uuidString)
            case .folder(var folder):
                let originalCount = folder.apps.count
                folder.apps.removeAll { standardizePath($0.url.path) == normalized }
                if folder.apps.count != originalCount {
                    if folder.apps.isEmpty {
                        updatedItems[idx] = .empty(UUID().uuidString)
                    } else {
                        updatedItems[idx] = .folder(folder)
                    }
                }
            default:
                break
            }
        }
        appStore.items = updatedItems

        // Sync cleanup in the folders list.
        for idx in appStore.folders.indices {
            appStore.folders[idx].apps.removeAll { standardizePath($0.url.path) == normalized }
        }
        // Cleanup in the apps list.
        appStore.apps.removeAll { standardizePath($0.url.path) == normalized }

        appStore.compactItemsWithinPages()
        appStore.removeEmptyPages()
        appStore.folderUpdateTrigger = UUID()
        appStore.gridRefreshTrigger = UUID()
        appStore.saveAllOrder()
    }

    private var shortcutsSection: some View {
        let isCapturing = isCapturingShortcut(.launchpad)
        let canSave = isCapturing && pendingShortcut != nil
        let canClear = isCapturing || appStore.globalHotKey != nil

        return VStack(alignment: .leading, spacing: 16) {
            VStack(alignment: .leading, spacing: 12) {
                HStack(alignment: .top, spacing: 16) {
                    VStack(alignment: .leading, spacing: 6) {
                        Label("LaunchNext", systemImage: "keyboard")
                            .font(.headline)
                        Text(appStore.localized(.globalShortcutDescription))
                            .font(.footnote)
                            .foregroundStyle(.secondary)

                        if isCapturing {
                            Text(appStore.localized(.shortcutCapturePrompt))
                                .font(.caption)
                                .foregroundStyle(.secondary)
                        }
                    }

                    Spacer()

                    VStack(alignment: .trailing, spacing: 6) {
                        Text(shortcutStatusText(for: .launchpad))
                            .font(.system(size: 13, weight: .medium, design: .monospaced))
                            .textSelection(.enabled)
                            .foregroundStyle(.primary)
                            .padding(.horizontal, 10)
                            .padding(.vertical, 6)
                            .background(Color.accentColor.opacity(colorScheme == .dark ? 0.18 : 0.12), in: Capsule())

                        if isCapturing {
                            Text(appStore.localized(.shortcutListening))
                                .font(.caption.weight(.semibold))
                                .foregroundStyle(.secondary)
                        }
                    }
                }

                HStack(spacing: 12) {
                    Button {
                        if isCapturing {
                            stopShortcutCapture(cancel: true)
                        } else {
                            startShortcutCapture(for: .launchpad)
                        }
                    } label: {
                        Label(isCapturing ? appStore.localized(.cancel) : appStore.localized(.shortcutSetButton),
                              systemImage: isCapturing ? "xmark.circle" : "keyboard")
                    }
                    .buttonStyle(.borderedProminent)

                    Button(appStore.localized(.shortcutSaveButton)) {
                        savePendingShortcut()
                    }
                    .buttonStyle(.bordered)
                    .disabled(!canSave)

                    Button(appStore.localized(.shortcutClearButton), role: .destructive) {
                        if isCapturing {
                            stopShortcutCapture(cancel: false)
                            pendingShortcut = nil
                        }
                        appStore.clearGlobalHotKey()
                    }
                    .buttonStyle(.bordered)
                    .disabled(!canClear)

                    Spacer(minLength: 0)
                }
            }
            .padding(16)
            .frame(maxWidth: .infinity, alignment: .leading)
            .liquidGlass(in: RoundedRectangle(cornerRadius: 16, style: .continuous))

            VStack(alignment: .leading, spacing: 12) {
                HStack(alignment: .top, spacing: 16) {
                    VStack(alignment: .leading, spacing: 6) {
                        Label(appStore.localized(.dockDragSectionTitle), systemImage: "dock.rectangle")
                            .font(.headline)
                        Text(appStore.localized(.dockDragSectionDescription))
                            .font(.footnote)
                            .foregroundStyle(.secondary)
                    }
                    Spacer(minLength: 12)
                    dockDragPreview
                }

                HStack {
                    Text(appStore.localized(.dockDragEnabledTitle))
                    Spacer()
                    Toggle("", isOn: dockDragEnabledBinding)
                        .labelsHidden()
                        .toggleStyle(.switch)
                }

                VStack(alignment: .leading, spacing: 10) {
                    HStack {
                        Text(appStore.localized(.dockDragSideTitle))
                            .foregroundStyle(.secondary)
                        Spacer()
                        Text(appStore.localized(appStore.dockDragSide.localizationKey))
                            .font(.caption.weight(.semibold))
                            .foregroundStyle(.secondary)
                            .padding(.horizontal, 9)
                            .padding(.vertical, 4)
                            .background(Color.accentColor.opacity(colorScheme == .dark ? 0.2 : 0.12), in: Capsule())
                    }

                    HStack(spacing: 8) {
                        ForEach(dockDragSelectableSides) { side in
                            dockDragSideButton(for: side)
                        }
                    }
                    .disabled(!appStore.dockDragEnabled)
                    .opacity(appStore.dockDragEnabled ? 1 : 0.45)

                    VStack(alignment: .leading, spacing: 6) {
                        HStack {
                            Text(appStore.localized(.dockDragTriggerDistanceTitle))
                                .foregroundStyle(.secondary)
                            Spacer()
                            Text("\(Int(appStore.dockDragTriggerDistance)) px")
                                .font(.footnote.monospacedDigit())
                                .foregroundStyle(.secondary)
                        }

                        Slider(value: dockDragTriggerDistanceBinding,
                               in: AppStore.dockDragTriggerDistanceRange,
                               step: 1)
                        .disabled(!appStore.dockDragEnabled)
                        .opacity(appStore.dockDragEnabled ? 1 : 0.45)

                        HStack {
                            Text("\(Int(AppStore.dockDragTriggerDistanceRange.lowerBound))")
                            Spacer()
                            Text("\(Int(AppStore.dockDragTriggerDistanceRange.upperBound))")
                        }
                        .font(.caption2.monospacedDigit())
                        .foregroundStyle(.tertiary)
                        .opacity(appStore.dockDragEnabled ? 1 : 0.45)
                    }
                }
            }
            .padding(16)
            .frame(maxWidth: .infinity, alignment: .leading)
            .liquidGlass(in: RoundedRectangle(cornerRadius: 16, style: .continuous))

            VStack(alignment: .leading, spacing: 12) {
                HStack(alignment: .top, spacing: 16) {
                    VStack(alignment: .leading, spacing: 6) {
                        Label(appStore.localized(.hotCornerSectionTitle), systemImage: "cursorarrow.motionlines")
                            .font(.headline)
                        Text(appStore.localized(.hotCornerSectionDescription))
                            .font(.footnote)
                            .foregroundStyle(.secondary)
                    }
                    Spacer(minLength: 12)
                    hotCornerPreview
                }

                HStack {
                    Text(appStore.localized(.hotCornerEnabledTitle))
                    Spacer()
                    Toggle("", isOn: hotCornerEnabledBinding)
                        .labelsHidden()
                        .toggleStyle(.switch)
                }

                HStack {
                    Text(appStore.localized(.hotCornerToggleWhenOpenTitle))
                    Spacer()
                    Toggle("", isOn: hotCornerToggleWhenOpenBinding)
                        .labelsHidden()
                        .toggleStyle(.switch)
                }
                .disabled(!appStore.hotCornerEnabled)
                .opacity(appStore.hotCornerEnabled ? 1 : 0.45)

                VStack(alignment: .leading, spacing: 10) {
                    HStack {
                        Text(appStore.localized(.hotCornerPositionTitle))
                            .foregroundStyle(.secondary)
                        Spacer()
                        Text(appStore.localized(appStore.hotCornerPosition.localizationKey))
                            .font(.caption.weight(.semibold))
                            .foregroundStyle(.secondary)
                            .padding(.horizontal, 9)
                            .padding(.vertical, 4)
                            .background(Color.accentColor.opacity(colorScheme == .dark ? 0.2 : 0.12), in: Capsule())
                    }

                    VStack(spacing: 8) {
                        HStack(spacing: 8) {
                            hotCornerPositionButton(for: .topLeft)
                            hotCornerPositionButton(for: .topRight)
                        }
                        HStack(spacing: 8) {
                            hotCornerPositionButton(for: .bottomLeft)
                            hotCornerPositionButton(for: .bottomRight)
                        }
                    }
                    .disabled(!appStore.hotCornerEnabled)
                    .opacity(appStore.hotCornerEnabled ? 1 : 0.45)

                    VStack(alignment: .leading, spacing: 6) {
                        HStack {
                            Text(appStore.localized(.hotCornerTriggerDelayTitle))
                                .foregroundStyle(.secondary)
                            Spacer()
                            Text("\(Int((appStore.hotCornerTriggerDelay * 1000).rounded())) ms")
                                .font(.footnote.monospacedDigit())
                                .foregroundStyle(.secondary)
                        }

                        Slider(value: hotCornerTriggerDelayBinding,
                               in: AppStore.hotCornerTriggerDelayRange,
                               step: 0.05)
                        .disabled(!appStore.hotCornerEnabled)
                        .opacity(appStore.hotCornerEnabled ? 1 : 0.45)
                    }

                    VStack(alignment: .leading, spacing: 6) {
                        HStack {
                            Text(appStore.localized(.hotCornerHitboxSizeTitle))
                                .foregroundStyle(.secondary)
                            Spacer()
                            Text("\(Int(appStore.hotCornerHitboxSize.rounded())) px")
                                .font(.footnote.monospacedDigit())
                                .foregroundStyle(.secondary)
                        }

                        Slider(value: hotCornerHitboxSizeBinding,
                               in: AppStore.hotCornerHitboxSizeRange,
                               step: 1)
                        .disabled(!appStore.hotCornerEnabled)
                        .opacity(appStore.hotCornerEnabled ? 1 : 0.45)

                        HStack {
                            Text("\(Int(AppStore.hotCornerHitboxSizeRange.lowerBound))")
                            Spacer()
                            Text("\(Int(AppStore.hotCornerHitboxSizeRange.upperBound))")
                        }
                        .font(.caption2.monospacedDigit())
                        .foregroundStyle(.tertiary)
                        .opacity(appStore.hotCornerEnabled ? 1 : 0.45)
                    }
                }
            }
            .padding(16)
            .frame(maxWidth: .infinity, alignment: .leading)
            .liquidGlass(in: RoundedRectangle(cornerRadius: 16, style: .continuous))

            VStack(alignment: .leading, spacing: 12) {
                HStack(alignment: .top, spacing: 16) {
                    VStack(alignment: .leading, spacing: 6) {
                        Label(appStore.localized(.gestureSectionTitle), systemImage: "hand.raised")
                            .font(.headline)
                        Text(appStore.localized(.gestureSectionDescription))
                            .font(.footnote)
                            .foregroundStyle(.secondary)
                    }

                    Spacer(minLength: 12)
                    gesturePreview
                }

                HStack {
                    Text(appStore.localized(.gestureEnabledTitle))
                    Spacer()
                    Toggle("", isOn: gestureEnabledBinding)
                        .labelsHidden()
                        .toggleStyle(.switch)
                }

                HStack {
                    Text(appStore.localized(.gestureCloseOnPinchOutTitle))
                    Spacer()
                    Toggle("", isOn: gestureCloseOnPinchOutBinding)
                        .labelsHidden()
                        .toggleStyle(.switch)
                }
                .disabled(!appStore.gestureEnabled)
                .opacity(appStore.gestureEnabled ? 1 : 0.45)

                VStack(alignment: .leading, spacing: 10) {
                    HStack(alignment: .firstTextBaseline, spacing: 12) {
                        Text(appStore.localized(.gestureTapActionTitle))
                        Spacer()
                        Text(appStore.localized(appStore.gestureTapAction.localizationKey))
                            .font(.footnote.weight(.semibold))
                            .foregroundStyle(.secondary)
                    }

                    HStack(spacing: 8) {
                        ForEach(AppStore.GestureTapAction.allCases) { action in
                            gestureTapActionButton(for: action)
                        }
                    }
                }

                VStack(alignment: .leading, spacing: 8) {
                    Text(appStore.localized(.gestureSystemHintTitle))
                        .font(.footnote.weight(.semibold))
                    Text(appStore.localized(.gestureSystemHintBody))
                        .font(.caption)
                        .foregroundStyle(.secondary)
                        .fixedSize(horizontal: false, vertical: true)
                }
                .padding(12)
                .frame(maxWidth: .infinity, alignment: .leading)
                .background(Color.accentColor.opacity(colorScheme == .dark ? 0.14 : 0.08), in: RoundedRectangle(cornerRadius: 12, style: .continuous))
            }
            .padding(16)
            .frame(maxWidth: .infinity, alignment: .leading)
            .liquidGlass(in: RoundedRectangle(cornerRadius: 16, style: .continuous))
        }
    }

    private var dockDragPreview: some View {
        ZStack {
            RoundedRectangle(cornerRadius: 18, style: .continuous)
                .fill(Color(nsColor: .windowBackgroundColor).opacity(colorScheme == .dark ? 0.28 : 0.82))
                .overlay(
                    RoundedRectangle(cornerRadius: 18, style: .continuous)
                        .stroke(Color.primary.opacity(0.08), lineWidth: 1)
                )

            RoundedRectangle(cornerRadius: 12, style: .continuous)
                .fill(Color.primary.opacity(colorScheme == .dark ? 0.08 : 0.05))
                .overlay(
                    RoundedRectangle(cornerRadius: 12, style: .continuous)
                        .stroke(Color.primary.opacity(0.08), lineWidth: 1)
                )
                .padding(16)
                .overlay(dockDragPreviewHighlight.padding(16))
        }
        .frame(width: 118, height: 82)
    }

    @ViewBuilder
    private var dockDragPreviewHighlight: some View {
        if !appStore.dockDragEnabled {
            Image(systemName: "slash.circle")
                .font(.system(size: 24, weight: .semibold))
                .foregroundStyle(.secondary)
        } else {
            switch appStore.dockDragSide {
            case .disabled:
                EmptyView()
            case .bottom:
                VStack {
                    Spacer()
                    RoundedRectangle(cornerRadius: 3, style: .continuous)
                        .fill(Color.accentColor.opacity(0.95))
                        .frame(width: 54, height: 6)
                        .padding(.bottom, 4)
                }
            case .left:
                HStack {
                    RoundedRectangle(cornerRadius: 3, style: .continuous)
                        .fill(Color.accentColor.opacity(0.95))
                        .frame(width: 6, height: 34)
                        .padding(.leading, 4)
                    Spacer()
                }
            case .right:
                HStack {
                    Spacer()
                    RoundedRectangle(cornerRadius: 3, style: .continuous)
                        .fill(Color.accentColor.opacity(0.95))
                        .frame(width: 6, height: 34)
                        .padding(.trailing, 4)
                }
            }
        }
    }

    private var dockDragEnabledBinding: Binding<Bool> {
        Binding(
            get: { appStore.dockDragEnabled },
            set: { newValue in
                guard appStore.dockDragEnabled != newValue else { return }
                DispatchQueue.main.async {
                    appStore.dockDragEnabled = newValue
                }
            }
        )
    }

    private var hotCornerEnabledBinding: Binding<Bool> {
        Binding(
            get: { appStore.hotCornerEnabled },
            set: { newValue in
                guard appStore.hotCornerEnabled != newValue else { return }
                DispatchQueue.main.async {
                    appStore.hotCornerEnabled = newValue
                }
            }
        )
    }

    private func dockDragSideButton(for side: AppStore.DockDragSide) -> some View {
        let isSelected = appStore.dockDragSide == side

        return Button {
            dockDragSideBinding.wrappedValue = side
        } label: {
            HStack(spacing: 6) {
                Image(systemName: dockDragSideSymbol(for: side))
                    .font(.caption.weight(.semibold))
                Text(appStore.localized(side.localizationKey))
                    .font(.subheadline.weight(.semibold))
                    .lineLimit(1)
            }
            .frame(maxWidth: .infinity, alignment: .leading)
            .padding(.horizontal, 12)
            .padding(.vertical, 11)
            .background(
                RoundedRectangle(cornerRadius: 14, style: .continuous)
                    .fill(isSelected ? Color.accentColor.opacity(colorScheme == .dark ? 0.18 : 0.12)
                                     : Color(nsColor: .windowBackgroundColor).opacity(colorScheme == .dark ? 0.25 : 0.75))
            )
            .overlay(
                RoundedRectangle(cornerRadius: 14, style: .continuous)
                    .stroke(isSelected ? Color.accentColor.opacity(0.65) : Color.primary.opacity(0.08), lineWidth: 1)
            )
        }
        .buttonStyle(.plain)
    }

    private func gestureTapActionButton(for action: AppStore.GestureTapAction) -> some View {
        let isSelected = appStore.gestureTapAction == action

        return Button {
            gestureTapActionBinding.wrappedValue = action
        } label: {
            HStack(spacing: 6) {
                Image(systemName: gestureTapActionSymbol(for: action))
                    .font(.caption.weight(.semibold))
                Text(appStore.localized(action.localizationKey))
                    .font(.subheadline.weight(.semibold))
                    .lineLimit(1)
            }
            .frame(maxWidth: .infinity, alignment: .leading)
            .padding(.horizontal, 12)
            .padding(.vertical, 11)
            .background(
                RoundedRectangle(cornerRadius: 14, style: .continuous)
                    .fill(isSelected ? Color.accentColor.opacity(colorScheme == .dark ? 0.18 : 0.12)
                                     : Color(nsColor: .windowBackgroundColor).opacity(colorScheme == .dark ? 0.25 : 0.75))
            )
            .overlay(
                RoundedRectangle(cornerRadius: 14, style: .continuous)
                    .stroke(isSelected ? Color.accentColor.opacity(0.65) : Color.primary.opacity(0.08), lineWidth: 1)
            )
        }
        .buttonStyle(.plain)
    }

    private func dockDragSideSymbol(for side: AppStore.DockDragSide) -> String {
        switch side {
        case .disabled: return "nosign"
        case .bottom: return "arrow.down.to.line"
        case .left: return "arrow.left.to.line"
        case .right: return "arrow.right.to.line"
        }
    }

    private func gestureTapActionSymbol(for action: AppStore.GestureTapAction) -> String {
        switch action {
        case .off: return "nosign"
        case .open: return "arrow.up.forward.app"
        case .toggle: return "arrow.triangle.2.circlepath"
        }
    }

    private var hotCornerPreview: some View {
        ZStack {
            RoundedRectangle(cornerRadius: 18, style: .continuous)
                .fill(Color(nsColor: .windowBackgroundColor).opacity(colorScheme == .dark ? 0.28 : 0.82))
                .overlay(
                    RoundedRectangle(cornerRadius: 18, style: .continuous)
                        .stroke(Color.primary.opacity(0.08), lineWidth: 1)
                )

            RoundedRectangle(cornerRadius: 12, style: .continuous)
                .fill(Color.primary.opacity(colorScheme == .dark ? 0.08 : 0.05))
                .overlay(
                    RoundedRectangle(cornerRadius: 12, style: .continuous)
                        .stroke(Color.primary.opacity(0.08), lineWidth: 1)
                )
                .padding(16)
                .overlay(hotCornerPreviewHighlight.padding(16))
        }
        .frame(width: 118, height: 82)
    }

    private var gesturePreview: some View {
        ZStack {
            RoundedRectangle(cornerRadius: 18, style: .continuous)
                .fill(Color(nsColor: .windowBackgroundColor).opacity(colorScheme == .dark ? 0.28 : 0.82))
                .overlay(
                    RoundedRectangle(cornerRadius: 18, style: .continuous)
                        .stroke(Color.primary.opacity(0.08), lineWidth: 1)
                )

            RoundedRectangle(cornerRadius: 12, style: .continuous)
                .fill(Color.primary.opacity(colorScheme == .dark ? 0.08 : 0.05))
                .overlay(
                    RoundedRectangle(cornerRadius: 12, style: .continuous)
                        .stroke(Color.primary.opacity(0.08), lineWidth: 1)
                )
                .padding(16)
                .overlay(gesturePreviewHighlight.padding(16))
        }
        .frame(width: 118, height: 82)
    }

    @ViewBuilder
    private var gesturePreviewHighlight: some View {
        if !appStore.gestureEnabled && appStore.gestureTapAction == .off {
            Image(systemName: "slash.circle")
                .font(.system(size: 24, weight: .semibold))
                .foregroundStyle(.secondary)
        } else {
            GeometryReader { proxy in
                let center = CGPoint(x: proxy.size.width / 2, y: proxy.size.height / 2)
                let points = [
                    CGPoint(x: center.x - 22, y: center.y - 12),
                    CGPoint(x: center.x + 22, y: center.y - 12),
                    CGPoint(x: center.x - 22, y: center.y + 12),
                    CGPoint(x: center.x + 22, y: center.y + 12)
                ]

                ForEach(Array(points.enumerated()), id: \.offset) { _, point in
                    Circle()
                        .fill(Color.accentColor.opacity(0.95))
                        .frame(width: 10, height: 10)
                        .position(point)
                }

                if appStore.gestureEnabled {
                    ForEach(Array(points.enumerated()), id: \.offset) { _, point in
                        Path { path in
                            path.move(to: point)
                            path.addLine(to: CGPoint(
                                x: center.x + ((point.x - center.x) * 0.42),
                                y: center.y + ((point.y - center.y) * 0.42)
                            ))
                        }
                        .stroke(Color.accentColor.opacity(0.45), style: StrokeStyle(lineWidth: 2, lineCap: .round))
                    }
                }

                Circle()
                    .fill(Color.accentColor.opacity(appStore.gestureTapAction != .off ? 0.22 : 0.16))
                    .frame(width: appStore.gestureTapAction != .off ? 26 : 18, height: appStore.gestureTapAction != .off ? 26 : 18)
                    .position(center)

                if appStore.gestureTapAction != .off {
                    Circle()
                        .stroke(Color.accentColor.opacity(0.55), lineWidth: 2)
                        .frame(width: 34, height: 34)
                        .position(center)
                }
            }
        }
    }

    @ViewBuilder
    private var hotCornerPreviewHighlight: some View {
        if !appStore.hotCornerEnabled {
            Image(systemName: "slash.circle")
                .font(.system(size: 24, weight: .semibold))
                .foregroundStyle(.secondary)
        } else {
            GeometryReader { proxy in
                let markerSize: CGFloat = 12
                let inset: CGFloat = 4

                Circle()
                    .fill(Color.accentColor.opacity(0.95))
                    .frame(width: markerSize, height: markerSize)
                    .position(hotCornerPreviewPoint(in: proxy.size, inset: inset))
            }
        }
    }

    private func hotCornerPreviewPoint(in size: CGSize, inset: CGFloat) -> CGPoint {
        switch appStore.hotCornerPosition {
        case .topLeft:
            return CGPoint(x: inset + 6, y: inset + 6)
        case .topRight:
            return CGPoint(x: size.width - inset - 6, y: inset + 6)
        case .bottomLeft:
            return CGPoint(x: inset + 6, y: size.height - inset - 6)
        case .bottomRight:
            return CGPoint(x: size.width - inset - 6, y: size.height - inset - 6)
        }
    }

    private func hotCornerPositionButton(for position: AppStore.HotCornerPosition) -> some View {
        let isSelected = appStore.hotCornerPosition == position

        return Button {
            hotCornerPositionBinding.wrappedValue = position
        } label: {
            HStack(spacing: 6) {
                Image(systemName: hotCornerPositionSymbol(for: position))
                    .font(.caption.weight(.semibold))
                Text(appStore.localized(position.localizationKey))
                    .font(.subheadline.weight(.semibold))
                    .lineLimit(1)
            }
            .frame(maxWidth: .infinity, alignment: .leading)
            .padding(.horizontal, 12)
            .padding(.vertical, 11)
            .background(
                RoundedRectangle(cornerRadius: 14, style: .continuous)
                    .fill(isSelected ? Color.accentColor.opacity(colorScheme == .dark ? 0.18 : 0.12)
                                     : Color(nsColor: .windowBackgroundColor).opacity(colorScheme == .dark ? 0.25 : 0.75))
            )
            .overlay(
                RoundedRectangle(cornerRadius: 14, style: .continuous)
                    .stroke(isSelected ? Color.accentColor.opacity(0.65) : Color.primary.opacity(0.08), lineWidth: 1)
            )
        }
        .buttonStyle(.plain)
    }

    private func hotCornerPositionSymbol(for position: AppStore.HotCornerPosition) -> String {
        switch position {
        case .topLeft: return "arrow.up.left"
        case .topRight: return "arrow.up.right"
        case .bottomLeft: return "arrow.down.left"
        case .bottomRight: return "arrow.down.right"
        }
    }

    private var appearanceSection: some View {
        LazyVStack(alignment: .leading, spacing: 0) {
            appearancePrimarySection
            Divider()
                .padding(.vertical, 24)
            appearanceSecondarySection
            appearanceTertiarySection
                .padding(.top, 16)
            appearanceQuaternarySection
                .padding(.top, 16)
        }
        .onAppear {
            syncLayoutModePreviewScopeToRuntime()
        }
    }

    private var appearancePrimarySection: some View {
        VStack(alignment: .leading, spacing: 16) {
            HStack {
                Text(appStore.localized(.classicMode))
                Spacer()
                Toggle("", isOn: $appStore.isFullscreenMode)
                    .labelsHidden()
                    .toggleStyle(.switch)
            }

            HStack {
                Text(appStore.localized(.showLabels))
                Spacer()
                Toggle("", isOn: $appStore.showLabels)
                    .labelsHidden()
                    .toggleStyle(.switch)
            }

            HStack {
                Text(appStore.localized(.useLocalizedThirdPartyTitles))
                Spacer()
                Toggle("", isOn: $appStore.useLocalizedThirdPartyTitles)
                    .labelsHidden()
                    .toggleStyle(.switch)
            }

            HStack {
                Text(appStore.localized(.predictDrop))
                Spacer()
                Toggle("", isOn: $appStore.enableDropPrediction)
                    .labelsHidden()
                    .toggleStyle(.switch)
            }
            .disabled(appStore.useCAGridRenderer)
            .opacity(appStore.useCAGridRenderer ? 0.5 : 1)

            HStack {
                Text(appStore.localized(.enableAnimations))
                Spacer()
                Toggle("", isOn: $appStore.enableAnimations)
                    .labelsHidden()
                    .toggleStyle(.switch)
            }

            HStack {
                Text(appStore.localized(.followScrollPagingTitle))
                Spacer()
                Toggle("", isOn: $appStore.followScrollPagingEnabled)
                    .labelsHidden()
                    .toggleStyle(.switch)
            }
            .disabled(appStore.useCAGridRenderer)
            .opacity(appStore.useCAGridRenderer ? 0.5 : 1)

            HStack {
                Text(appStore.localized(.reverseWheelPagingTitle))
                Spacer()
                Toggle("", isOn: $appStore.reverseWheelPagingDirection)
                    .labelsHidden()
                    .toggleStyle(.switch)
            }

            HStack {
                Text(appStore.localized(.hideDockOption))
                Spacer()
                Toggle("", isOn: $appStore.hideDock)
                    .labelsHidden()
                    .toggleStyle(.switch)
            }

            HStack {
                Text(appStore.localized(.rememberPageTitle))
                Spacer()
                Toggle("", isOn: $appStore.rememberLastPage)
                    .labelsHidden()
                    .toggleStyle(.switch)
            }

            HStack {
                Text(appStore.localized(.hoverMagnification))
                Spacer()
                Toggle("", isOn: $appStore.enableHoverMagnification)
                    .labelsHidden()
                    .toggleStyle(.switch)
            }

            HStack {
                Text(appStore.localized(.activePressEffect))
                Spacer()
                Toggle("", isOn: $appStore.enableActivePressEffect)
                    .labelsHidden()
                    .toggleStyle(.switch)
            }

            VStack(alignment: .leading, spacing: 6) {
                HStack {
                    Text(appStore.localized(.folderPreviewHighResTitle))
                    Spacer()
                    Toggle("", isOn: $appStore.enableHighResFolderPreviews)
                        .labelsHidden()
                        .toggleStyle(.switch)
                }
                Text(appStore.localized(.folderPreviewHighResHint))
                    .font(.footnote)
                    .foregroundStyle(.secondary)
            }

            HStack {
                Text(appStore.localized(.windowOpenAnimationTitle))
                Spacer()
                Toggle("", isOn: $appStore.enableWindowOpenAnimation)
                    .labelsHidden()
                    .toggleStyle(.switch)
            }

            HStack {
                Text(appStore.localized(.backgroundMaskTitle))
                Spacer()
                Toggle("", isOn: $appStore.backgroundMaskEnabled)
                    .labelsHidden()
                    .toggleStyle(.switch)
            }

            if appStore.backgroundMaskEnabled {
                VStack(alignment: .leading, spacing: 8) {
                    ColorPicker(appStore.localized(.backgroundMaskLightLabel), selection: backgroundMaskColorBinding(isDark: false), supportsOpacity: true)
                    ColorPicker(appStore.localized(.backgroundMaskDarkLabel), selection: backgroundMaskColorBinding(isDark: true), supportsOpacity: true)
                }
            }

            VStack(alignment: .leading, spacing: 8) {
                Text(appStore.localized(.backgroundStyleTitle))
                    .font(.headline)
                Picker("", selection: $appStore.launchpadBackgroundStyle) {
                    ForEach(AppStore.BackgroundStyle.allCases) { style in
                        Text(appStore.localized(style.localizationKey)).tag(style)
                    }
                }
                .pickerStyle(.segmented)
                .labelsHidden()
            }

            if #available(macOS 26.0, iOS 26.0, *) {
                let useGlass = appStore.launchpadBackgroundStyle == .glass
                let shape = RoundedRectangle(cornerRadius: 14, style: .continuous)

                ZStack {
                    Image("AboutBackground")
                        .resizable()
                        .interpolation(.high)
                        .aspectRatio(contentMode: .fill)

                    HStack(spacing: 16) {
                        glassPreviewCard(label: "Regular", icon: "app.fill", style: .regular, useGlass: useGlass, shape: shape)
                        glassPreviewCard(label: "Clear", icon: "app.fill", style: .clear, useGlass: useGlass, shape: shape)
                        glassPreviewCard(label: "Identity", icon: "app.fill", style: .identity, useGlass: useGlass, shape: shape)
                    }
                    .padding(20)
                }
                .frame(height: 140)
                .clipShape(RoundedRectangle(cornerRadius: 16, style: .continuous))
                .overlay(
                    RoundedRectangle(cornerRadius: 16, style: .continuous)
                        .stroke(Color.white.opacity(0.18), lineWidth: 1.4)
                )
                .allowsHitTesting(false)
            }
        }
    }

    private var appearanceSecondarySection: some View {
        VStack(alignment: .leading, spacing: 16) {
            VStack(alignment: .leading, spacing: 8) {
                let durationEnabled = appStore.enableAnimations && !appStore.useCAGridRenderer
                Text(appStore.localized(.animationDurationLabel))
                    .font(.headline)
                Slider(value: $appStore.animationDuration, in: 0.1...1.0, step: 0.05)
                    .disabled(!durationEnabled)
                    .opacity(durationEnabled ? 1 : 0.5)
                HStack {
                    Text("0.1s").font(.footnote)
                    Spacer()
                    Text(String(format: "%.2fs", appStore.animationDuration))
                        .font(.footnote)
                    Spacer()
                    Text("1.0s").font(.footnote)
                }
                .foregroundStyle(durationEnabled ? .primary : .secondary)
                .opacity(durationEnabled ? 1 : 0.6)
            }

            VStack(alignment: .leading, spacing: 8) {
                Text(appStore.localized(.iconLabelFontWeight))
                    .font(.headline)
                Picker("", selection: $appStore.iconLabelFontWeight) {
                    ForEach(AppStore.IconLabelFontWeightOption.allCases) { option in
                        Text(option.displayName).tag(option)
                    }
                }
                .pickerStyle(.menu)
                .labelsHidden()
            }

            VStack(alignment: .leading, spacing: 8) {
                Text(appStore.localized(.sidebarIconSizeTitle))
                    .font(.headline)
                Picker("", selection: $appStore.sidebarIconPreset) {
                    Text(appStore.localized(.sidebarIconSizeLarge)).tag(AppStore.SidebarIconPreset.large)
                    Text(appStore.localized(.sidebarIconSizeMedium)).tag(AppStore.SidebarIconPreset.medium)
                }
                .pickerStyle(.menu)
                .labelsHidden()
            }

            VStack(alignment: .leading, spacing: 8) {
                HStack(spacing: 12) {
                    Text(appStore.localized(.iconSize))
                        .font(.headline)
                    Spacer()
                    layoutModeScopeControl()
                }
                Slider(value: scopedIconScaleBinding(), in: 0.8...1.1)
                HStack {
                    Text(appStore.localized(.smaller)).font(.footnote)
                    Spacer()
                    Text(appStore.localized(.larger)).font(.footnote)
                }
            }

            VStack(alignment: .leading, spacing: 8) {
                HStack {
                    Text(appStore.localized(.folderWindowWidth))
                        .font(.headline)
                    Spacer()
                    Text(String(format: "%.0f%%", appStore.folderPopoverWidthFactor * 100))
                        .font(.subheadline)
                        .foregroundStyle(.secondary)
                }
                Slider(value: $appStore.folderPopoverWidthFactor,
                       in: AppStore.folderPopoverWidthRange)
                    .disabled(appStore.isFullscreenMode)
                HStack {
                    Text(String(format: "%.0f%%", AppStore.folderPopoverWidthRange.lowerBound * 100))
                        .font(.footnote)
                    Spacer()
                    Text(String(format: "%.0f%%", AppStore.folderPopoverWidthRange.upperBound * 100))
                        .font(.footnote)
                }
            }

            VStack(alignment: .leading, spacing: 8) {
                HStack {
                    Text(appStore.localized(.folderWindowHeight))
                        .font(.headline)
                    Spacer()
                    Text(String(format: "%.0f%%", appStore.folderPopoverHeightFactor * 100))
                        .font(.subheadline)
                        .foregroundStyle(.secondary)
                }
                Slider(value: $appStore.folderPopoverHeightFactor,
                       in: AppStore.folderPopoverHeightRange)
                    .disabled(appStore.isFullscreenMode)
                HStack {
                    Text(String(format: "%.0f%%", AppStore.folderPopoverHeightRange.lowerBound * 100))
                        .font(.footnote)
                    Spacer()
                    Text(String(format: "%.0f%%", AppStore.folderPopoverHeightRange.upperBound * 100))
                        .font(.footnote)
                }
            }

            Text(appStore.localized(.folderWindowSizeHint))
                .font(.footnote)
                .foregroundStyle(.secondary)
                .fixedSize(horizontal: false, vertical: true)
        }
    }

    private var appearanceTertiarySection: some View {
        VStack(alignment: .leading, spacing: 16) {
            VStack(alignment: .leading, spacing: 8) {
                Text(appStore.localized(.hoverMagnificationScale))
                    .font(.headline)
                Slider(value: $appStore.hoverMagnificationScale,
                       in: AppStore.hoverMagnificationRange)
                    .disabled(!appStore.enableHoverMagnification)
                HStack {
                    Text(String(format: "%.2fx", AppStore.hoverMagnificationRange.lowerBound))
                        .font(.footnote)
                    Spacer()
                    Text(String(format: "%.2fx", appStore.hoverMagnificationScale))
                        .font(.footnote)
                        .foregroundStyle(.secondary)
                    Spacer()
                    Text(String(format: "%.2fx", AppStore.hoverMagnificationRange.upperBound))
                        .font(.footnote)
                }
            }

            VStack(alignment: .leading, spacing: 8) {
                Text(appStore.localized(.activePressScale))
                    .font(.headline)
                Slider(value: $appStore.activePressScale,
                       in: AppStore.activePressScaleRange)
                    .disabled(!appStore.enableActivePressEffect)
                HStack {
                    Text(String(format: "%.2fx", AppStore.activePressScaleRange.lowerBound))
                        .font(.footnote)
                    Spacer()
                    Text(String(format: "%.2fx", appStore.activePressScale))
                        .font(.footnote)
                        .foregroundStyle(.secondary)
                    Spacer()
                    Text(String(format: "%.2fx", AppStore.activePressScaleRange.upperBound))
                        .font(.footnote)
                }
            }

            VStack(alignment: .leading, spacing: 8) {
                HStack {
                    Text(appStore.localized(.iconsPerRow))
                        .font(.headline)
                    Spacer()
                    Stepper(value: $appStore.gridColumnsPerPage, in: AppStore.gridColumnRange) {
                        Text("\(appStore.gridColumnsPerPage)")
                            .font(.callout.monospacedDigit())
                    }
                    .controlSize(.small)
                }
            }

            VStack(alignment: .leading, spacing: 8) {
                HStack {
                    Text(appStore.localized(.rowsPerPage))
                        .font(.headline)
                    Spacer()
                    Stepper(value: $appStore.gridRowsPerPage, in: AppStore.gridRowRange) {
                        Text("\(appStore.gridRowsPerPage)")
                            .font(.callout.monospacedDigit())
                    }
                    .controlSize(.small)
                }
            }

            VStack(alignment: .leading, spacing: 8) {
                HStack {
                    Text(appStore.localized(.iconHorizontalSpacing))
                        .font(.headline)
                    Spacer()
                    Text("\(Int(appStore.iconColumnSpacing)) pt")
                        .font(.callout.monospacedDigit())
                        .foregroundStyle(.secondary)
                }
                Slider(value: $appStore.iconColumnSpacing,
                       in: AppStore.columnSpacingRange,
                       step: 1)
            }

            VStack(alignment: .leading, spacing: 8) {
                HStack {
                    Text(appStore.localized(.iconVerticalSpacing))
                        .font(.headline)
                    Spacer()
                    Text("\(Int(appStore.iconRowSpacing)) pt")
                        .font(.callout.monospacedDigit())
                        .foregroundStyle(.secondary)
                }
                Slider(value: $appStore.iconRowSpacing,
                       in: AppStore.rowSpacingRange,
                       step: 1)
            }

            VStack(alignment: .leading, spacing: 4) {
                Text(appStore.localized(.gridSizeChangeWarning))
                Text(appStore.localized(.pageIndicatorHint))
                    .foregroundStyle(.tertiary)
            }
            .font(.footnote)
            .foregroundStyle(.secondary)
            .padding(.top, 2)
        }
    }

    private var appearanceQuaternarySection: some View {
        VStack(alignment: .leading, spacing: 16) {
            VStack(alignment: .leading, spacing: 8) {
                HStack {
                    Text(appStore.localized(.labelFontSize))
                        .font(.headline)
                    Spacer()
                    layoutModeScopeControl()
                }
                Slider(value: scopedIconLabelFontSizeBinding(), in: 9...16, step: 0.5)
                HStack {
                    Text("9pt").font(.footnote)
                    Spacer()
                    Text("16pt").font(.footnote)
                }
            }

            VStack(alignment: .leading, spacing: 8) {
                Text(appStore.localized(.scrollSensitivity))
                    .font(.headline)
                Slider(value: $appStore.scrollSensitivity, in: 0.01...0.99)
                HStack {
                    Text(appStore.localized(.low)).font(.footnote)
                    Spacer()
                    Text(appStore.localized(.high)).font(.footnote)
                }
            }

            VStack(alignment: .leading, spacing: 8) {
                HStack {
                    Text(String(format: appStore.localized(.folderDropZoneSizeWithDefault), AppStore.defaultFolderDropZoneScale))
                    Spacer()
                    layoutModeScopeControl()
                }
                Slider(value: scopedFolderDropZoneScaleBinding(),
                       in: AppStore.folderDropZoneScaleRange,
                       step: 0.05)
                HStack {
                    Text(String(format: "%.1fx", AppStore.folderDropZoneScaleRange.lowerBound))
                        .font(.footnote)
                        .foregroundStyle(.secondary)
                    Spacer()
                    Text(String(format: "%.2fx", appStore.scopedFolderDropZoneScale(for: selectedAppearanceLayoutMode)))
                        .font(.footnote.monospacedDigit())
                    Spacer()
                    Text(String(format: "%.1fx", AppStore.folderDropZoneScaleRange.upperBound))
                        .font(.footnote)
                        .foregroundStyle(.secondary)
                }
                Text(appStore.localized(.folderDropZoneSizeHint))
                    .font(.footnote)
                    .foregroundStyle(.secondary)
            }

            VStack(alignment: .leading, spacing: 8) {
                HStack {
                    Text(appStore.localized(.pageIndicatorOffsetLabel))
                        .font(.headline)
                    Spacer()
                    if !selectedScopePerDisplayEnabled {
                        layoutModeScopeControl()
                    }
                }
                Slider(value: scopedPageIndicatorOffsetBinding(), in: 0...80)
                HStack {
                    Text("0").font(.footnote)
                    Spacer()
                    Text(String(format: "%.0f", appStore.scopedPageIndicatorOffset(for: selectedAppearanceLayoutMode))).font(.footnote)
                    Spacer()
                    Text("80").font(.footnote)
                }
            }
            .disabled(selectedScopePerDisplayEnabled)

            VStack(alignment: .leading, spacing: 8) {
                HStack {
                    Text(appStore.localized(.pageIndicatorTopPaddingLabel))
                        .font(.headline)
                    Spacer()
                    if !selectedScopePerDisplayEnabled {
                        layoutModeScopeControl()
                    }
                }
                Slider(value: scopedPageIndicatorTopPaddingBinding(),
                       in: AppStore.pageIndicatorTopPaddingRange)
                HStack {
                    Text(String(format: "%.0f", AppStore.pageIndicatorTopPaddingRange.lowerBound)).font(.footnote)
                    Spacer()
                    Text(String(format: "%.0f", appStore.scopedPageIndicatorTopPadding(for: selectedAppearanceLayoutMode))).font(.footnote)
                    Spacer()
                    Text(String(format: "%.0f", AppStore.pageIndicatorTopPaddingRange.upperBound)).font(.footnote)
                }
            }
            .disabled(selectedScopePerDisplayEnabled)

            VStack(alignment: .leading, spacing: 8) {
                let perDisplayBinding = scopedPerDisplayIndicatorBinding()
                Button {
                    perDisplayBinding.wrappedValue.toggle()
                } label: {
                    HStack(spacing: 8) {
                        Text(appStore.localized(.perDisplayIndicatorPositionTitle))
                            .font(.headline)
                        Spacer()
                        layoutModeScopeControl(width: 116)
                        Toggle("", isOn: perDisplayBinding)
                            .labelsHidden()
                            .toggleStyle(.switch)
                            .allowsHitTesting(false)
                    }
                    .frame(maxWidth: .infinity, alignment: .leading)
                    .contentShape(Rectangle())
                }
                .buttonStyle(PressFeedbackRowButtonStyle(enabled: true, pressScale: 0.98))
                Text(appStore.localized(.perDisplayIndicatorPositionDescription))
                    .font(.footnote)
                    .foregroundStyle(.secondary)

                if selectedScopePerDisplayEnabled {
                    HStack {
                        Button(appStore.localized(.applyDefaultsToCurrentDisplay)) {
                            if let screenID = currentIndicatorScreenID {
                                appStore.applyIndicatorDefaults(to: screenID, mode: selectedAppearanceLayoutMode)
                            }
                        }
                        .buttonStyle(.bordered)
                        Spacer()
                    }

                    VStack(alignment: .leading, spacing: 10) {
                        ForEach(indicatorScreenEntries) { entry in
                            indicatorOverrideCard(for: entry)
                        }
                    }
                }
            }
        }
        .padding(.bottom, 20)
    }

    @ViewBuilder
    private func glassPreviewCard(label: String, icon: String, style: LiquidGlassStyle, useGlass: Bool, shape: some Shape) -> some View {
        let content = VStack(spacing: 8) {
            Image(systemName: icon)
                .font(.title)
            Text(label)
                .font(.subheadline.weight(.medium))
        }
        .foregroundStyle(.white)
        .frame(maxWidth: .infinity)
        .padding(.vertical, 18)

        if useGlass, #available(macOS 26.0, iOS 26.0, *) {
            switch style {
            case .regular:
                content.glassEffect(.regular, in: shape)
            case .clear:
                content.glassEffect(.clear, in: shape)
            case .identity:
                content.glassEffect(.identity, in: shape)
            }
        } else {
            switch style {
            case .regular:
                content.background(.regularMaterial, in: shape)
            case .clear:
                content.background(.ultraThinMaterial, in: shape)
            case .identity:
                content
            }
        }
    }

    // MARK: - Export / Import Application Support Data
    private func supportDirectoryURL() throws -> URL {
        let fm = FileManager.default
        let appSupport = try fm.url(for: .applicationSupportDirectory, in: .userDomainMask, appropriateFor: nil, create: true)
        let dir = appSupport.appendingPathComponent("LaunchNext", isDirectory: true)
        if !fm.fileExists(atPath: dir.path) {
            try fm.createDirectory(at: dir, withIntermediateDirectories: true)
        }
        return dir
    }

    private func exportDataFolder() {
        do {
            let panel = NSOpenPanel()
            panel.canChooseFiles = false
            panel.canChooseDirectories = true
            panel.canCreateDirectories = true
            panel.allowsMultipleSelection = false
            panel.prompt = appStore.localized(.chooseButton)
            panel.message = appStore.localized(.exportPanelMessage)
            if panel.runModal() == .OK, let destParent = panel.url {
                try exportDataFolder(to: destParent)
            }
        } catch {
            showBackupExportError(error)
        }
    }

    private func exportDataFolder(to destParent: URL) throws {
        let sourceDir = try supportDirectoryURL()
        let formatter = DateFormatter()
        formatter.locale = Locale(identifier: "en_US_POSIX")
        formatter.dateFormat = "yyyy-MM-dd'_'HH.mm.ss"
        let folderName = "LaunchNext_" + formatter.string(from: Date()) + ".launchnext"
        let destDir = destParent.appendingPathComponent(folderName, isDirectory: true)
        let fm = FileManager.default

        func performExport() throws {
            try copyDirectory(from: sourceDir, to: destDir)
            exportPreferences(to: destDir)
            guard backupExportLooksComplete(destDir) else {
                throw NSError(domain: "LaunchNextBackup",
                              code: 1,
                              userInfo: [NSLocalizedDescriptionKey: "Backup export is incomplete."])
            }
        }

        do {
            try performExport()
        } catch {
            try? fm.removeItem(at: destDir)

            guard removeLegacyBackupSocketIfNeeded() else {
                throw error
            }

            do {
                try performExport()
            } catch {
                try? fm.removeItem(at: destDir)
                throw error
            }
        }
    }

    private func importDataFolder() {
        let panel = NSOpenPanel()
        panel.canChooseFiles = false
        panel.canChooseDirectories = true
        panel.canCreateDirectories = false
        panel.allowsMultipleSelection = false
        panel.prompt = appStore.localized(.importPrompt)
        panel.message = appStore.localized(.importPanelMessage)
        if panel.runModal() == .OK, let srcDir = panel.url {
            importDataFolder(from: srcDir)
        }
    }

    private func importDataFolder(from srcDir: URL) {
        do {
            // Validate this is a valid export folder
            guard isValidExportFolder(srcDir) else { return }

            func performImport(importData: Bool, importPrefs: Bool, allowedPrefKeys: Set<String>) throws {
                let destDir = try supportDirectoryURL()
                if importData {
                    if srcDir.standardizedFileURL != destDir.standardizedFileURL {
                        try replaceDirectory(with: srcDir, at: destDir)
                        appStore.applyOrderAndFolders()
                        appStore.refresh()
                    }
                }
                if importPrefs {
                    importPreferences(from: srcDir, allowedKeys: allowedPrefKeys.isEmpty ? nil : allowedPrefKeys)
                    appStore.reloadPreferencesFromDefaults()
                    appStore.refresh()
                }
            }

            // Ask user what to import (attach as sheet to stay on the same screen)
            let alert = NSAlert()
            alert.messageText = appStore.localized(.importPrompt)
            alert.informativeText = appStore.localized(.importPanelMessage)
            alert.icon = NSApplication.shared.applicationIconImage
            alert.addButton(withTitle: appStore.localized(.importPrompt)) // Confirm
            alert.addButton(withTitle: appStore.localized(.cancel))      // Cancel

            let content = NSView(frame: NSRect(x: 0, y: 0, width: 1, height: 1))

            func makeCheckbox(_ title: String, state: NSControl.StateValue = .on) -> NSButton {
                let button = NSButton(checkboxWithTitle: title, target: nil, action: nil)
                button.state = state
                button.allowsMixedState = false
                button.setContentCompressionResistancePriority(.defaultLow, for: .horizontal)
                button.cell?.wraps = true
                button.cell?.lineBreakMode = .byWordWrapping
                return button
            }

            let dataCheckbox = makeCheckbox("Layout & data")
            let generalCheckbox = makeCheckbox(appStore.localized(.settingsSectionGeneral))
            let appearanceCheckbox = makeCheckbox(appStore.localized(.settingsSectionAppearance))
            let sourcesCheckbox = makeCheckbox(appStore.localized(.settingsSectionAppSources))
            let hiddenCheckbox = makeCheckbox(appStore.localized(.settingsSectionHiddenApps))
            let titlesCheckbox = makeCheckbox(appStore.localized(.settingsSectionTitles))

            let stack = NSStackView(views: [
                dataCheckbox,
                generalCheckbox,
                appearanceCheckbox,
                sourcesCheckbox,
                hiddenCheckbox,
                titlesCheckbox
            ])
            stack.orientation = .vertical
            stack.alignment = .leading
            stack.spacing = 6
            stack.translatesAutoresizingMaskIntoConstraints = false
            content.addSubview(stack)

            NSLayoutConstraint.activate([
                stack.leadingAnchor.constraint(equalTo: content.leadingAnchor, constant: 4),
                stack.trailingAnchor.constraint(lessThanOrEqualTo: content.trailingAnchor, constant: -8),
                stack.topAnchor.constraint(equalTo: content.topAnchor, constant: 4),
                stack.bottomAnchor.constraint(lessThanOrEqualTo: content.bottomAnchor)
            ])

            // Size to fit content (min width 320, min height 160)
            let fitting = stack.fittingSize
            let minWidth: CGFloat = 320
            let minHeight: CGFloat = 160
            content.setFrameSize(NSSize(width: max(minWidth, fitting.width + 16),
                                        height: max(minHeight, fitting.height + 12)))

            alert.accessoryView = content

            func selectedPrefKeys() -> Set<String> {
                var keys = Set<String>()
                if generalCheckbox.state == .on {
                    keys.insert("preferredLanguage")
                    keys.insert("appearancePreference")
                    keys.insert("isStartOnLogin")
                    keys.insert(AppStore.showQuickRefreshButtonKey)
                    keys.insert(AppStore.lockLayoutKey)
                    keys.insert("kioskMode")
                    keys.insert("autoFullscreen")
                    keys.insert("showInDock")
                    keys.insert(AppStore.uninstallToolAppPathKey)
                    keys.insert(AppStore.dockDragSideKey)
                    keys.insert(AppStore.dockDragTriggerDistanceKey)
                    keys.insert(AppStore.hotCornerEnabledKey)
                    keys.insert(AppStore.hotCornerPositionKey)
                    keys.insert(AppStore.hotCornerTriggerDelayKey)
                    keys.insert(AppStore.hotCornerHitboxSizeKey)
                    keys.insert(AppStore.hotCornerToggleWhenOpenKey)
                    // Experimental gesture backup keys. Remove these together
                    // with the gesture feature if low-level multitouch support
                    // is dropped later.
                    keys.insert(AppStore.gestureEnabledKey)
                    keys.insert(AppStore.gestureCloseOnPinchOutKey)
                    keys.insert(AppStore.gestureTapActionKey)
                }
                if appearanceCheckbox.state == .on {
                    keys.insert(AppStore.sidebarIconPresetKey)
                    keys.insert(AppStore.backgroundStyleKey)
                    keys.insert(AppStore.backgroundMaskEnabledKey)
                    keys.insert(AppStore.backgroundMaskLightKey)
                    keys.insert(AppStore.backgroundMaskDarkKey)
                    keys.insert("scrollSensitivity")
                    keys.insert("isFullscreenMode")
                    keys.insert("showLabels")
                    keys.insert("hideDock")
                    keys.insert("enableAnimations")
                    keys.insert(AppStore.windowOpenAnimationKey)
                    keys.insert("useLocalizedThirdPartyTitles")
                    keys.insert("enableDropPrediction")
                    keys.insert(AppStore.reverseWheelPagingKey)
                    keys.insert(AppStore.rememberPageKey)
                    keys.insert(AppStore.rememberedPageIndexKey)
                    keys.insert("iconScale")
                    keys.insert("iconLabelFontSize")
                    keys.insert(AppStore.iconLabelFontWeightKey)
                    keys.insert("gridColumnsPerPage")
                    keys.insert("gridRowsPerPage")
                    keys.insert("gridColumnSpacing")
                    keys.insert("gridRowSpacing")
                    keys.insert("folderDropZoneScale")
                    keys.insert(AppStore.folderPreviewHighResKey)
                    keys.insert("pageIndicatorOffset")
                    keys.insert(AppStore.pageIndicatorTopPaddingKey)
                    keys.insert(AppStore.pageIndicatorPerDisplayEnabledKey)
                    keys.insert(AppStore.pageIndicatorPerDisplayOverridesKey)
                    keys.insert(AppStore.dualModeAppearanceSettingsKey)
                    keys.insert(AppStore.dockDragEnabledKey)
                    keys.insert("folderPopoverWidthFactor")
                    keys.insert("folderPopoverHeightFactor")
                    keys.insert(AppStore.hoverMagnificationKey)
                    keys.insert(AppStore.hoverMagnificationScaleKey)
                    keys.insert(AppStore.activePressEffectKey)
                    keys.insert(AppStore.activePressScaleKey)
                    keys.insert("animationDuration")
                    keys.insert("globalHotKeyConfiguration")
                    keys.insert(AppStore.useCAGridRendererKey)
                    keys.insert("showFPSOverlay")
                    keys.insert("gameControllerEnabled")
                    keys.insert(AppStore.gameControllerMenuToggleKey)
                }
                if hiddenCheckbox.state == .on {
                    keys.insert(AppStore.hiddenAppsKey)
                }
                if sourcesCheckbox.state == .on {
                    keys.insert(AppStore.customAppSourcesKey)
                }
                if titlesCheckbox.state == .on {
                    keys.insert(AppStore.customTitlesKey)
                }
                return keys
            }

            if let window = NSApp.keyWindow ?? NSApp.mainWindow {
                alert.beginSheetModal(for: window) { response in
                    guard response == .alertFirstButtonReturn else { return }
                    let importData = dataCheckbox.state == .on
                    let keys = selectedPrefKeys()
                    let importPrefs = !keys.isEmpty
                    do {
                        try performImport(importData: importData, importPrefs: importPrefs, allowedPrefKeys: keys)
                    } catch {
                        // Ignore failed import
                    }
                }
            } else {
                let response = alert.runModal()
                guard response == .alertFirstButtonReturn else { return }
                let importData = dataCheckbox.state == .on
                let keys = selectedPrefKeys()
                let importPrefs = !keys.isEmpty
                try performImport(importData: importData, importPrefs: importPrefs, allowedPrefKeys: keys)
            }
        } catch {
            // Ignore errors or surface a user-facing message if desired
        }
    }

    // MARK: - Preferences export/import
    private var currentPrefsDomain: String {
        Bundle.main.bundleIdentifier ?? "LaunchNextAppStore"
    }

    private func exportPreferences(to folder: URL) {
        let fm = FileManager.default
        if !fm.fileExists(atPath: folder.path) {
            try? fm.createDirectory(at: folder, withIntermediateDirectories: true)
        }

        let domain = currentPrefsDomain
        guard let dict = UserDefaults.standard.persistentDomain(forName: domain), !dict.isEmpty else { return }
        let url = folder.appendingPathComponent("\(domain).plist")
        do {
            let data = try PropertyListSerialization.data(fromPropertyList: dict, format: .xml, options: 0)
            try data.write(to: url)
        } catch {
            // ignore failure
        }
    }

    private func importPreferences(from folder: URL, allowedKeys: Set<String>? = nil) {
        let domain = currentPrefsDomain
        let url = folder.appendingPathComponent("\(domain).plist")
        guard FileManager.default.fileExists(atPath: url.path) else { return }
        do {
            let data = try Data(contentsOf: url)
            guard var incoming = try PropertyListSerialization.propertyList(from: data, options: [], format: nil) as? [String: Any] else { return }

            if let allowedKeys, !allowedKeys.isEmpty {
                incoming = incoming.filter { allowedKeys.contains($0.key) }
            }
            guard !incoming.isEmpty else { return }

            // Merge with existing prefs to avoid wiping unselected keys
            var current = UserDefaults.standard.persistentDomain(forName: domain) ?? [:]
            incoming.forEach { current[$0.key] = $0.value }
            UserDefaults.standard.setPersistentDomain(current, forName: domain)
        } catch {
            // ignore failed domain restore
        }
        UserDefaults.standard.synchronize()
    }

    private func copyDirectory(from src: URL, to dst: URL) throws {
        let fm = FileManager.default
        if fm.fileExists(atPath: dst.path) {
            try fm.removeItem(at: dst)
        }
        try fm.createDirectory(at: dst, withIntermediateDirectories: true)
        copyDirectoryMetadata(from: src, to: dst)

        guard let enumerator = fm.enumerator(at: src,
                                             includingPropertiesForKeys: [.isDirectoryKey, .isSymbolicLinkKey],
                                             options: [],
                                             errorHandler: { _, _ in true }) else {
            throw NSError(domain: "LaunchNextBackup",
                          code: 2,
                          userInfo: [NSLocalizedDescriptionKey: "Failed to enumerate backup source directory."])
        }

        for case let itemURL as URL in enumerator {
            if isSocketFile(at: itemURL) {
                continue
            }

            let relativePath = itemURL.path.replacingOccurrences(of: src.path + "/", with: "")
            let targetURL = dst.appendingPathComponent(relativePath, isDirectory: false)
            let values = try itemURL.resourceValues(forKeys: [.isDirectoryKey, .isSymbolicLinkKey])

            if values.isDirectory == true {
                try fm.createDirectory(at: targetURL, withIntermediateDirectories: true)
                copyDirectoryMetadata(from: itemURL, to: targetURL)
                continue
            }

            let parentDirectory = targetURL.deletingLastPathComponent()
            if !fm.fileExists(atPath: parentDirectory.path) {
                try fm.createDirectory(at: parentDirectory, withIntermediateDirectories: true)
            }

            if fm.fileExists(atPath: targetURL.path) {
                try fm.removeItem(at: targetURL)
            }

            if values.isSymbolicLink == true {
                let destination = try fm.destinationOfSymbolicLink(atPath: itemURL.path)
                try fm.createSymbolicLink(atPath: targetURL.path, withDestinationPath: destination)
            } else {
                try fm.copyItem(at: itemURL, to: targetURL)
            }
        }
    }

    private func copyDirectoryMetadata(from src: URL, to dst: URL) {
        copyExtendedAttributes(from: src, to: dst)

        let fm = FileManager.default
        guard let attributes = try? fm.attributesOfItem(atPath: src.path) else { return }

        var copied: [FileAttributeKey: Any] = [:]
        if let permissions = attributes[.posixPermissions] {
            copied[.posixPermissions] = permissions
        }
        if let immutability = attributes[.immutable] {
            copied[.immutable] = immutability
        }

        if !copied.isEmpty {
            try? fm.setAttributes(copied, ofItemAtPath: dst.path)
        }
    }

    private func copyExtendedAttributes(from src: URL, to dst: URL) {
        let options: Int32 = 0

        src.path.withCString { srcPath in
            dst.path.withCString { dstPath in
                let size = listxattr(srcPath, nil, 0, options)
                guard size > 0 else { return }

                var nameBuffer = [CChar](repeating: 0, count: size)
                let readSize = listxattr(srcPath, &nameBuffer, nameBuffer.count, options)
                guard readSize > 0 else { return }

                var index = 0
                while index < Int(readSize) {
                    let name = nameBuffer.withUnsafeBufferPointer { buffer -> String in
                        String(cString: buffer.baseAddress!.advanced(by: index))
                    }

                    let valueSize = getxattr(srcPath, name, nil, 0, 0, options)
                    if valueSize >= 0 {
                        var valueBuffer = [UInt8](repeating: 0, count: valueSize)
                        let actualSize = getxattr(srcPath, name, &valueBuffer, valueBuffer.count, 0, options)
                        if actualSize >= 0 {
                            valueBuffer.withUnsafeBytes { rawBuffer in
                                _ = setxattr(dstPath, name, rawBuffer.baseAddress, actualSize, 0, options)
                            }
                        }
                    }

                    index += name.utf8.count + 1
                }
            }
        }
    }

    private func replaceDirectory(with src: URL, at dst: URL) throws {
        let fm = FileManager.default
        // Ensure parent directory exists
        let parent = dst.deletingLastPathComponent()
        if !fm.fileExists(atPath: parent.path) {
            try fm.createDirectory(at: parent, withIntermediateDirectories: true)
        }
        if fm.fileExists(atPath: dst.path) {
            try fm.removeItem(at: dst)
        }
        try fm.copyItem(at: src, to: dst)
    }

    private func backupExportLooksComplete(_ folder: URL) -> Bool {
        let fm = FileManager.default
        let requiredFiles = [
            folder.appendingPathComponent("Data.store"),
            folder.appendingPathComponent("LaunchNext.plist")
        ]
        return requiredFiles.allSatisfy { fm.fileExists(atPath: $0.path) }
    }

    private func removeLegacyBackupSocketIfNeeded() -> Bool {
        guard let legacySocketURL = try? supportDirectoryURL().appendingPathComponent(LaunchNextCLIIPCConfig.socketFileName, isDirectory: false) as URL else {
            return false
        }
        guard isSocketFile(at: legacySocketURL) else { return false }
        do {
            try FileManager.default.removeItem(at: legacySocketURL)
            return true
        } catch {
            return false
        }
    }

    private func isSocketFile(at url: URL) -> Bool {
        var fileStat = stat()
        let result = url.path.withCString { path in
            Darwin.lstat(path, &fileStat)
        }
        guard result == 0 else { return false }
        return (fileStat.st_mode & S_IFMT) == S_IFSOCK
    }

    private func showBackupExportError(_ error: Error) {
        let alert = NSAlert()
        alert.messageText = "Backup Failed"
        let message = (error as NSError).localizedDescription.trimmingCharacters(in: .whitespacesAndNewlines)
        alert.informativeText = message.isEmpty ? "LaunchNext could not create a complete backup." : message
        alert.alertStyle = .warning
        alert.addButton(withTitle: appStore.localized(.okButton))

        if let window = NSApp.keyWindow ?? NSApp.mainWindow {
            alert.beginSheetModal(for: window)
        } else {
            alert.runModal()
        }
    }

    private func isValidExportFolder(_ folder: URL) -> Bool {
        let fm = FileManager.default
        let storeURL = folder.appendingPathComponent("Data.store")
        guard fm.fileExists(atPath: storeURL.path) else { return false }
        // Try opening the store and verify it contains layout data
        do {
            let config = ModelConfiguration(url: storeURL)
            let container = try ModelContainer(for: TopItemData.self, PageEntryData.self, configurations: config)
            let ctx = container.mainContext
            let pageEntries = try ctx.fetch(FetchDescriptor<PageEntryData>())
            if !pageEntries.isEmpty { return true }
            let legacyEntries = try ctx.fetch(FetchDescriptor<TopItemData>())
            return !legacyEntries.isEmpty
        } catch {
            return false
        }
    }

    private func importFromLaunchpad() {
        Task {
            let result = await appStore.importFromNativeLaunchpad()

            DispatchQueue.main.async {
                let alert = NSAlert()
                if result.success {
                    alert.messageText = appStore.localized(.importSuccessfulTitle)
                    alert.informativeText = result.message
                    alert.alertStyle = .informational
                } else {
                    alert.messageText = appStore.localized(.importFailedTitle)
                    alert.informativeText = result.message
                    alert.alertStyle = .warning
                }
                alert.addButton(withTitle: appStore.localized(.okButton))
                alert.runModal()
            }
        }
    }

    private func applyMacOS26PresetLayout() {
        let success = appStore.applyMacOS26PresetLayout()

        let alert = NSAlert()
        if success {
            alert.messageText = appStore.localized(.layoutPresetAppliedTitle)
            alert.informativeText = appStore.localized(.layoutPresetAppliedMessage)
            alert.alertStyle = .informational
        } else {
            alert.messageText = appStore.localized(.importFailedTitle)
            alert.informativeText = appStore.localized(.layoutPresetApplyFailedMessage)
            alert.alertStyle = .warning
        }
        alert.addButton(withTitle: appStore.localized(.okButton))
        alert.runModal()
    }

    private func importLegacyArchive() {
        let panel = NSOpenPanel()
        panel.canChooseFiles = true
        panel.canChooseDirectories = false
        panel.canCreateDirectories = false
        panel.allowsMultipleSelection = false
        panel.allowedContentTypes = ["lmy", "zip", "db"].compactMap { UTType(filenameExtension: $0) }
        panel.prompt = appStore.localized(.importPrompt)
        panel.message = appStore.localized(.legacyArchivePanelMessage)

        if panel.runModal() == .OK, let url = panel.url {
            Task {
                let result = await appStore.importFromLegacyLaunchpadArchive(url: url)
                DispatchQueue.main.async {
                    let alert = NSAlert()
                    if result.success {
                        alert.messageText = appStore.localized(.importSuccessfulTitle)
                        alert.informativeText = result.message
                        alert.alertStyle = .informational
                    } else {
                        alert.messageText = appStore.localized(.importFailedTitle)
                        alert.informativeText = result.message
                        alert.alertStyle = .warning
                    }
                    alert.addButton(withTitle: appStore.localized(.okButton))
                    alert.runModal()
                }
            }
        }
    }

    // MARK: - Update Check Section
    private var updatesSection: some View {
        return VStack(alignment: .leading, spacing: 16) {
            updatesHero

            updatesControlCard

            updatesStatusCard

            updateControlButton(
                title: appStore.localized(.openUpdaterConfig),
                systemImage: "doc.text"
            ) {
                appStore.openUpdaterConfigFile()
            }
        }
    }

    private var updatesStatusCard: some View {
        VStack(alignment: .leading, spacing: 10) {
            let availableRelease: AppStore.UpdateRelease? = {
                if case .updateAvailable(let release) = appStore.updateState { return release }
                return nil
            }()
            let availableNotes: String? = {
                if case .updateAvailable(let release) = appStore.updateState {
                    return release.notes
                }
                return nil
            }()
            let availableNotesModel: MarkdownRenderModel = {
                guard let availableNotes, !availableNotes.isEmpty else { return .empty }
                return SimpleMarkdownParser.parse(availableNotes)
            }()

            Text(appStore.localized(.checkForUpdates))
                .font(.headline)

            switch appStore.updateState {
            case .idle:
                EmptyView()

            case .checking:
                HStack {
                    ProgressView()
                        .scaleEffect(0.8)
                    Text(appStore.localized(.checkingForUpdates))
                        .foregroundStyle(.secondary)
                }

            case .upToDate:
                HStack {
                    Image(systemName: "checkmark.circle.fill")
                        .foregroundStyle(.green)
                    Text(appStore.localized(.upToDate))
                        .foregroundStyle(.secondary)
                }

            case .updateAvailable(let release):
                VStack(alignment: .leading, spacing: 8) {
                    HStack(alignment: .firstTextBaseline, spacing: 10) {
                        Label(appStore.localized(.updateAvailable), systemImage: "party.popper.fill")
                            .font(.subheadline.weight(.semibold))
                            .foregroundStyle(.orange)

                        Text(appStore.localized(.newVersion) + " \(release.version)")
                            .font(.footnote.weight(.medium))
                            .foregroundStyle(.secondary)

                        Spacer(minLength: 0)
                    }

                    if !availableNotesModel.blocks.isEmpty {
                        VStack(alignment: .leading, spacing: 8) {
                            Text("Release Notes")
                                .font(.caption.weight(.semibold))
                                .foregroundStyle(.secondary)

                            ReleaseNotesMarkdownView(model: availableNotesModel, mode: .full)
                        }
                        .padding(12)
                        .frame(maxWidth: .infinity, alignment: .leading)
                        .background(
                            RoundedRectangle(cornerRadius: 12, style: .continuous)
                                .fill(Color.primary.opacity(0.04))
                        )
                    }
                }

            case .failed(let error):
                VStack(alignment: .leading, spacing: 8) {
                    HStack {
                        Image(systemName: "exclamationmark.triangle.fill")
                            .foregroundStyle(.red)
                        Text(appStore.localized(.updateCheckFailed))
                            .font(.subheadline.weight(.medium))
                    }

                    Text(error)
                        .font(.footnote)
                        .foregroundStyle(.secondary)
                }
            }

        }
        .padding(12)
        .frame(maxWidth: .infinity, alignment: .leading)
        .background(
            RoundedRectangle(cornerRadius: 16, style: .continuous)
                .fill(Color(nsColor: .windowBackgroundColor))
        )
    }

    private var updatesFloatingBar: some View {
        let floatingBarShape = Capsule(style: .continuous)
        return HStack(spacing: 12) {
            updateControlButton(
                title: appStore.updateState == .idle
                    ? appStore.localized(.checkForUpdatesButton)
                    : appStore.localized(.updatesRefreshButton),
                systemImage: "arrow.clockwise",
                isPrimary: true,
                minWidth: 136
            ) {
                appStore.checkForUpdates()
            }
            .disabled(appStore.updateState == .checking)

            if let release = currentAvailableRelease {
                updateControlButton(
                    title: appStore.localized(.downloadUpdate),
                    systemImage: "arrow.down.circle",
                    minWidth: 136
                ) {
                    appStore.launchUpdater(for: release)
                }
            }
        }
        .padding(.horizontal, 14)
        .padding(.vertical, 12)
        .modifier(ClearGlassBackground(shape: floatingBarShape))
        .overlay(
            floatingBarShape
                .stroke(Color.primary.opacity(0.08), lineWidth: 1)
        )
        .shadow(color: Color.black.opacity(0.08), radius: 18, x: 0, y: 8)
    }

    private struct ClearGlassBackground<S: Shape>: ViewModifier {
        let shape: S

        @ViewBuilder
        func body(content: Content) -> some View {
            if #available(macOS 26.0, iOS 18.0, *) {
                content
                    .glassEffect(.clear, in: shape)
            } else {
                content
                    .background(.ultraThinMaterial, in: shape)
            }
        }
    }

    private var currentAvailableRelease: AppStore.UpdateRelease? {
        if case .updateAvailable(let release) = appStore.updateState {
            return release
        }
        return nil
    }

    private var updatesControlCard: some View {
        VStack(alignment: .leading, spacing: 10) {
            HStack {
                Text(appStore.localized(.autoCheckForUpdates))
                    .font(.subheadline)
                Spacer()
                Toggle("", isOn: $appStore.autoCheckForUpdates)
                    .labelsHidden()
                    .toggleStyle(.switch)
            }
        }
        .padding(12)
        .frame(maxWidth: .infinity, alignment: .leading)
        .background(
            RoundedRectangle(cornerRadius: 16, style: .continuous)
                .fill(Color(nsColor: .windowBackgroundColor))
        )
    }

    private func updateControlButton(title: String, systemImage: String, isPrimary: Bool = false, minWidth: CGFloat = 160, action: @escaping () -> Void) -> some View {
        Button(action: action) {
            Label(title, systemImage: systemImage)
                .font(.subheadline.weight(.semibold))
                .padding(.horizontal, 16)
                .padding(.vertical, 8)
                .frame(minWidth: minWidth)
        }
        .buttonStyle(.plain)
        .background(
            Capsule()
                .fill(isPrimary ? Color.accentColor.opacity(0.16) : Color(nsColor: .windowBackgroundColor))
        )
        .overlay(
            Capsule()
                .stroke(isPrimary ? Color.accentColor.opacity(0.6) : Color.primary.opacity(0.08), lineWidth: 1)
        )
    }

    private var updatesHero: some View {
        let statusText: String = {
            switch appStore.updateState {
            case .updateAvailable:
                return appStore.localized(.updatesHeroUpdateAvailable)
            case .upToDate:
                return appStore.localized(.updatesHeroUpToDate)
            default:
                return String(format: appStore.localized(.versionLabelFormat),
                              getVersion(fallback: appStore.localized(.versionFallback)))
            }
        }()

        return ZStack(alignment: .center) {
            Image("AboutBackground")
                .resizable()
                .interpolation(.high)
                .aspectRatio(16.0/9.0, contentMode: .fill)
                .frame(maxWidth: .infinity)
                .clipped()

            VStack(spacing: 12) {
                headlineGlass

                Text(statusText)
                    .font(.title2.weight(.semibold))
                    .foregroundStyle(.white.opacity(0.85))
                    .padding(.top, 6)
            }
            .multilineTextAlignment(.center)
            .padding(.horizontal, 20)
            .padding(.vertical, 18)
        }
        .frame(maxWidth: .infinity)
        .frame(minHeight: 180, maxHeight: 200)
        .clipShape(RoundedRectangle(cornerRadius: 18, style: .continuous))
        .overlay(
            RoundedRectangle(cornerRadius: 18, style: .continuous)
                .stroke(Color.white.opacity(0.18), lineWidth: 1.4)
        )
        .padding(.bottom, 12)
    }
}
