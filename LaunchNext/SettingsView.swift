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
    @State private var showResetConfirm = false
    @State private var selectedSection: SettingsSection = .general
    @State private var titleSearch: String = ""
    @State private var hasHiddenAppEntries: Bool = false
    @State private var hasNotHiddenAppEntries: Bool = false
    @State private var hiddenSearch: String = ""
    @State private var notHiddenSearch: String = ""
    @State private var hasHiddenAppEntriesSearchResult: Bool = false
    @State private var hasNotHiddenAppEntriesSearchResult: Bool = false
    @State private var cachedHiddenAppEntries: [AppEntry] = []
    @State private var cachedNotHiddenAppEntries: [AppEntry] = []
    @State private var showHiddenApps = true
    @State private var showNotHiddenApps = false
    @State private var editingDrafts: [String: String] = [:]
    @State private var editingEntries: Set<String> = []
    @State private var iconImportError: String? = nil
    @State private var showAppSourcesResetDialog = false
    @State private var showUpdateNotes = false
    @State private var showCleanupCommand = false
    @State private var cleanupCommandCopied = false
    @State private var backupRootPath: String = UserDefaults.standard.string(forKey: "backupRootDirectory") ?? ""
    @State private var backupRefreshToken = UUID()
    @State private var selectedBackupIDs: Set<String> = []
    @State private var showPerformanceRestartPrompt = false
    @State private var capturingShortcutTarget: ShortcutTarget? = nil
    @State private var shortcutCaptureMonitor: Any?
    @State private var pendingShortcut: AppStore.HotKeyConfiguration?

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
                    .padding(.bottom, 17)
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

private enum SettingsSection: String, CaseIterable, Identifiable {
    case general
    case appearance
    case performance
    case titles
    case appSources
    case hiddenApps
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
        case .appSources: return "externaldrive"
        case .gameController: return "gamecontroller"
        case .sound: return "speaker.wave.2"
        case .appearance: return "paintbrush"
        case .performance: return "speedometer"
        case .titles: return "text.badge.plus"
        case .hiddenApps: return "eye.slash"
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
        case .appSources: return .settingsSectionAppSources
        case .sound: return .settingsSectionSound
        case .gameController: return .settingsSectionGameController
        case .appearance: return .settingsSectionAppearance
        case .performance: return .settingsSectionPerformance
        case .titles: return .settingsSectionTitles
        case .hiddenApps: return .settingsSectionHiddenApps
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
                        VStack(alignment: .leading, spacing: 24) {
                            content(for: section)
                            Spacer(minLength: 0)
                        }
                        .padding(.vertical, 12)
                        .frame(maxWidth: .infinity, alignment: .leading)
                    }
                    .scrollDisabled(section == .about || section == .general)
                    .frame(maxWidth: .infinity, maxHeight: .infinity)
                    .scrollBounceBehavior(.basedOnSize)
                }
                .padding(.horizontal, 24)
                .padding(.vertical, 16)
                .frame(width: proxy.size.width, height: proxy.size.height, alignment: .topLeading)
            }
            .background(.ultraThinMaterial)
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
            // ignore for now
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
                    HStack(spacing: 8) {
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
        .onChange(of: appStore.performanceMode) { _ in
            showPerformanceRestartPrompt = true
        }
        .alert(appStore.localized(.performanceModeRestartTitle), isPresented: $showPerformanceRestartPrompt) {
            Button(appStore.localized(.okButton), role: .cancel) {}
        } message: {
            Text(appStore.localized(.performanceModeRestartMessage))
        }
    }

    private var titlesSection: some View {
        VStack(alignment: .leading, spacing: 16) {
            HStack {
                Button {
                    presentCustomTitlePicker()
                } label: {
                    Label(appStore.localized(.customTitleAddButton), systemImage: "plus")
                }
                Spacer()
            }

            let allEntries = customTitleEntries
            let filtered = filteredCustomTitleEntries

            if allEntries.isEmpty {
                customTitleEmptyState
            } else {
                Text(appStore.localized(.customTitleHint))
                    .font(.footnote)
                    .foregroundStyle(.secondary)

                TextField("", text: $titleSearch, prompt: Text(appStore.localized(.renameSearchPlaceholder)))
                    .textFieldStyle(.roundedBorder)

                if filtered.isEmpty {
                    Text(appStore.localized(.customTitleNoResults))
                        .font(.callout)
                        .foregroundStyle(.secondary)
                        .frame(maxWidth: .infinity, minHeight: 120, alignment: .center)
                } else {
                    VStack(spacing: 12) {
                        ForEach(filtered) { entry in
                            customTitleRow(for: entry)
                        }
                    }
                }
            }
        }
    }

    private var hiddenAppsSection: some View {
        return LazyVStack(alignment: .leading, spacing: 16) {
            DisclosureGroup(isExpanded: $showHiddenApps) {
                LazyVStack(alignment: .leading, spacing: 16){
                    if hasHiddenAppEntries {
                        Text(appStore.localized(.hiddenAppsHint))
                            .font(.footnote)
                            .foregroundStyle(.secondary)
                        
                        TextField("", text: $hiddenSearch, prompt: Text(appStore.localized(.hiddenAppsSearchPlaceholder)))
                            .textFieldStyle(.roundedBorder)
                        
                        if hasHiddenAppEntriesSearchResult {
                            LazyVStack(spacing: 12) {
                                ForEach(cachedHiddenAppEntries) { entry in
                                    hiddenAppRow(for: entry)
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
                        
                        if hasNotHiddenAppEntriesSearchResult{
                            LazyVStack(spacing: 12) {
                                ForEach(cachedNotHiddenAppEntries){ entry in
                                    notHiddenAppRow(for: entry)
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
        .onAppear(perform: updateCachedAllAppEntries)
        .onChange(of: hiddenSearch.count, initial: false, updateCachedHiddenAppEntries)
        .onChange(of: notHiddenSearch.count, initial: false, updateCachedNotHiddenAppEntries)
        .onChange(of: appStore.apps, initial: false, updateCachedAllAppEntries)
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
        appStore.apps
            .map { info in
                let path = info.url.path
                let defaultName = appStore.defaultDisplayName(for: path)
                return AppEntry(id: path, appInfo: info, defaultName: defaultName)
            }
            .sorted { lhs, rhs in
                lhs.appInfo.name.localizedCaseInsensitiveCompare(rhs.appInfo.name) == .orderedAscending
            }
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
        let hiddenAppEntries = hiddenAppEntries
        hasHiddenAppEntries = !hiddenAppEntries.isEmpty
        let filteredHiddenAppEntries = filter(hiddenAppEntries, by: hiddenSearch)
        hasHiddenAppEntriesSearchResult = !filteredHiddenAppEntries.isEmpty
        cachedHiddenAppEntries.append(contentsOf: filteredHiddenAppEntries)
    }
    
    private func updateCachedNotHiddenAppEntries() {
        cachedNotHiddenAppEntries.removeAll()
        let notHiddenAppEntries = notHiddenAppEntries
        hasNotHiddenAppEntries = !notHiddenAppEntries.isEmpty
        let filteredNotHiddenAppEntries = filter(notHiddenAppEntries, by: notHiddenSearch)
        hasNotHiddenAppEntriesSearchResult = !filteredNotHiddenAppEntries.isEmpty
        cachedNotHiddenAppEntries.append(contentsOf: filteredNotHiddenAppEntries)
    }
    
    private func updateCachedAllAppEntries() {
        updateCachedHiddenAppEntries()
        updateCachedNotHiddenAppEntries()
    }

    private var customTitleEntries: [CustomTitleEntry] {
        appStore.customTitles
            .map { (path, _) in
                let info = appStore.appInfoForCustomTitle(path: path)
                let defaultName = appStore.defaultDisplayName(for: path)
                return CustomTitleEntry(id: path, appInfo: info, defaultName: defaultName)
            }
            .sorted { lhs, rhs in
                lhs.appInfo.name.localizedCaseInsensitiveCompare(rhs.appInfo.name) == .orderedAscending
            }
    }

    private var filteredCustomTitleEntries: [CustomTitleEntry] {
        let base = customTitleEntries
        let trimmed = titleSearch.trimmingCharacters(in: .whitespacesAndNewlines)
        guard !trimmed.isEmpty else { return base }
        let query = trimmed.lowercased()
        return base.filter { entry in
            let custom = entry.appInfo.name.lowercased()
            if custom.contains(query) { return true }
            if entry.defaultName.lowercased().contains(query) { return true }
            if entry.id.lowercased().contains(query) { return true }
            return false
        }
    }

    private var customTitleEmptyState: some View {
        VStack(alignment: .leading, spacing: 12) {
            Text(appStore.localized(.customTitleEmptyTitle))
                .font(.headline)
            Text(appStore.localized(.customTitleEmptySubtitle))
                .font(.footnote)
                .foregroundStyle(.secondary)

            Button {
                presentCustomTitlePicker()
            } label: {
                Label(appStore.localized(.customTitleAddButton), systemImage: "plus")
            }
        }
        .padding(20)
        .frame(maxWidth: .infinity, alignment: .leading)
        .liquidGlass(in: RoundedRectangle(cornerRadius: 18, style: .continuous))
    }

    @ViewBuilder
    private func customTitleRow(for entry: CustomTitleEntry) -> some View {
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

                HStack(spacing: 10) {
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
                                Text(appStore.localized(.customTitleDelete))
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
                                Text(appStore.localized(.customTitleDelete))
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
    
    private func findApps(in rootURL: URL) -> [URL] {
        var result: [URL] = []
        let fm = FileManager.default
        let keys: [URLResourceKey] = [.isDirectoryKey, .isPackageKey, .contentTypeKey]
        
        guard let enumerator = fm.enumerator(
            at: rootURL,
            includingPropertiesForKeys: keys,
            options: [.skipsHiddenFiles, .skipsPackageDescendants]
        ) else {
            return []
        }
        
        for case let url as URL in enumerator {
            if let type = try? url.resourceValues(forKeys: [.contentTypeKey]).contentType,
               type.conforms(to: .applicationBundle) {
                result.append(url)
                (enumerator as? FileManager.DirectoryEnumerator)?.skipDescendants()
            } else if url.pathExtension.lowercased() == "app" {
                result.append(url)
                (enumerator as? FileManager.DirectoryEnumerator)?.skipDescendants()
            }
        }
        return result
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

    private struct CustomTitleEntry: Identifiable {
        let id: String
        let appInfo: AppInfo
        let defaultName: String
    }

    private func beginEditing(_ entry: CustomTitleEntry) {
        editingEntries.insert(entry.id)
        editingDrafts[entry.id] = appStore.customTitles[entry.id] ?? entry.appInfo.name
    }

    private func cancelEditing(_ entry: CustomTitleEntry) {
        editingEntries.remove(entry.id)
        editingDrafts.removeValue(forKey: entry.id)
    }

    private func saveCustomTitle(_ entry: CustomTitleEntry) {
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

    private func removeCustomTitle(_ entry: CustomTitleEntry) {
        appStore.clearCustomTitle(for: entry.appInfo)
        editingEntries.remove(entry.id)
        editingDrafts.removeValue(forKey: entry.id)
    }

    private static let modifierOnlyKeyCodes: Set<UInt16> = [55, 54, 58, 61, 56, 60, 59, 62, 57]

    private func startShortcutCapture(for target: ShortcutTarget) {
        stopShortcutCapture(cancel: false)
        pendingShortcut = nil
        capturingShortcutTarget = target
        shortcutCaptureMonitor = NSEvent.addLocalMonitorForEvents(matching: [.keyDown]) { event in
            handleShortcutCapture(event: event)
        }
    }

    private func stopShortcutCapture(cancel: Bool) {
        if let monitor = shortcutCaptureMonitor {
            NSEvent.removeMonitor(monitor)
            shortcutCaptureMonitor = nil
        }
        if cancel {
            pendingShortcut = nil
            if capturingShortcutTarget != nil { NSSound.beep() }
        }
        capturingShortcutTarget = nil
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
                .glassEffect(.clear, in: Capsule())
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
        .glassEffect(.regular, in: RoundedRectangle(cornerRadius: 20, style: .continuous))
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
            HStack {
                Text(appStore.localized(.launchAtLoginTitle))
                    .font(.subheadline.weight(.semibold))
                Spacer()
                Toggle("", isOn: $appStore.isStartOnLogin)
                    .labelsHidden()
                    .toggleStyle(.switch)
                    .disabled(!appStore.canConfigureStartOnLogin)
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
                    Text(appStore.localized(.showQuickRefreshButton))
                        .font(.subheadline.weight(.semibold))
                    Spacer()
                    Toggle("", isOn: $appStore.showQuickRefreshButton)
                        .labelsHidden()
                        .toggleStyle(.switch)
                }
                .frame(maxWidth: .infinity, alignment: .leading)
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

        let offlineIDs = appStore.pageIndicatorOverrides.keys
            .filter { !connectedIDs.contains($0) }
            .sorted()

        for id in offlineIDs {
            entries.append(IndicatorScreenEntry(id: id,
                                                name: "Offline Display",
                                                sizeText: "ID \(id)",
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
            get: { appStore.pageIndicatorOverride(for: screenID) != nil },
            set: { isCustom in
                scheduleIndicatorOverrideUpdate {
                    if isCustom {
                        appStore.applyIndicatorDefaults(to: screenID)
                    } else {
                        appStore.setPageIndicatorOverride(nil, for: screenID)
                    }
                }
            }
        )
    }

    private func indicatorOffsetBinding(for screenID: String) -> Binding<Double> {
        Binding(
            get: { appStore.pageIndicatorOverride(for: screenID)?.offset ?? appStore.pageIndicatorOffset },
            set: { newValue in
                scheduleIndicatorOverrideUpdate {
                    let current = appStore.pageIndicatorOverride(for: screenID)
                        ?? AppStore.PageIndicatorOverride(offset: appStore.pageIndicatorOffset,
                                                          topPadding: appStore.pageIndicatorTopPadding)
                    appStore.setPageIndicatorOverride(AppStore.PageIndicatorOverride(offset: newValue,
                                                                                    topPadding: current.topPadding),
                                                      for: screenID)
                }
            }
        )
    }

    private func indicatorTopPaddingBinding(for screenID: String) -> Binding<Double> {
        Binding(
            get: { appStore.pageIndicatorOverride(for: screenID)?.topPadding ?? appStore.pageIndicatorTopPadding },
            set: { newValue in
                scheduleIndicatorOverrideUpdate {
                    let current = appStore.pageIndicatorOverride(for: screenID)
                        ?? AppStore.PageIndicatorOverride(offset: appStore.pageIndicatorOffset,
                                                          topPadding: appStore.pageIndicatorTopPadding)
                    appStore.setPageIndicatorOverride(AppStore.PageIndicatorOverride(offset: current.offset,
                                                                                    topPadding: newValue),
                                                      for: screenID)
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
        let offsetValue = appStore.pageIndicatorOverride(for: entry.id)?.offset ?? appStore.pageIndicatorOffset
        let topPaddingValue = appStore.pageIndicatorOverride(for: entry.id)?.topPadding ?? appStore.pageIndicatorTopPadding

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
                    Text("Offline")
                        .font(.caption)
                        .foregroundStyle(.secondary)
                }
                Picker("", selection: useCustom) {
                    Text("Default").tag(false)
                    Text("Custom").tag(true)
                }
                .pickerStyle(.segmented)
                .frame(width: 160)
            }

            if useCustom.wrappedValue {
                VStack(alignment: .leading, spacing: 8) {
                    HStack {
                        Text("Indicator offset")
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
                        Text("Indicator top padding")
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

    private var appearanceSection: some View {
        VStack(alignment: .leading, spacing: 24) {
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

                HStack {
                    Text("Background mask")
                    Spacer()
                    Toggle("", isOn: $appStore.backgroundMaskEnabled)
                        .labelsHidden()
                        .toggleStyle(.switch)
                }

                if appStore.backgroundMaskEnabled {
                    VStack(alignment: .leading, spacing: 8) {
                        ColorPicker("Light appearance mask", selection: backgroundMaskColorBinding(isDark: false), supportsOpacity: true)
                        ColorPicker("Dark appearance mask", selection: backgroundMaskColorBinding(isDark: true), supportsOpacity: true)
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

            }

            Divider()

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
                    Text(appStore.localized(.iconSize))
                        .font(.headline)
                    Slider(value: $appStore.iconScale, in: 0.8...1.1)
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

                VStack(alignment: .leading, spacing: 8) {
                    Text(appStore.localized(.globalShortcutTitle))
                        .font(.headline)
                    HStack(spacing: 12) {
                        Button {
                            if isCapturingShortcut(.launchpad) {
                                stopShortcutCapture(cancel: true)
                            } else {
                                startShortcutCapture(for: .launchpad)
                            }
                        } label: {
                            Text(isCapturingShortcut(.launchpad) ? appStore.localized(.cancel) : appStore.localized(.shortcutSetButton))
                        }

                        Button(appStore.localized(.shortcutSaveButton)) {
                            savePendingShortcut()
                        }
                        .disabled(!(isCapturingShortcut(.launchpad) && pendingShortcut != nil))

                        Button(appStore.localized(.shortcutClearButton)) {
                            if isCapturingShortcut(.launchpad) {
                                stopShortcutCapture(cancel: false)
                                pendingShortcut = nil
                            }
                            appStore.clearGlobalHotKey()
                        }
                        .disabled(!isCapturingShortcut(.launchpad) && appStore.globalHotKey == nil)
                    }

                    Text(shortcutStatusText(for: .launchpad))
                        .font(.callout)
                        .foregroundStyle(.secondary)
                }

                VStack(alignment: .leading, spacing: 8) {
                    Text(appStore.localized(.labelFontSize))
                        .font(.headline)
                    Slider(value: $appStore.iconLabelFontSize, in: 9...16, step: 0.5)
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
                    Text(String(format: appStore.localized(.folderDropZoneSizeWithDefault), AppStore.defaultFolderDropZoneScale))
                    Slider(value: $appStore.folderDropZoneScale,
                           in: AppStore.folderDropZoneScaleRange,
                           step: 0.05)
                    HStack {
                        Text(String(format: "%.1fx", AppStore.folderDropZoneScaleRange.lowerBound))
                            .font(.footnote)
                            .foregroundStyle(.secondary)
                        Spacer()
                        Text(String(format: "%.2fx", appStore.folderDropZoneScale))
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
                    Text(appStore.localized(.pageIndicatorOffsetLabel))
                        .font(.headline)
                    Slider(value: $appStore.pageIndicatorOffset, in: 0...80)
                    HStack {
                        Text("0").font(.footnote)
                        Spacer()
                        Text(String(format: "%.0f", appStore.pageIndicatorOffset)).font(.footnote)
                        Spacer()
                        Text("80").font(.footnote)
                    }
                }
                .disabled(appStore.pageIndicatorPerDisplayEnabled)

                VStack(alignment: .leading, spacing: 8) {
                    Text(appStore.localized(.pageIndicatorTopPaddingLabel))
                        .font(.headline)
                    Slider(value: $appStore.pageIndicatorTopPadding,
                           in: AppStore.pageIndicatorTopPaddingRange)
                    HStack {
                        Text(String(format: "%.0f", AppStore.pageIndicatorTopPaddingRange.lowerBound)).font(.footnote)
                        Spacer()
                        Text(String(format: "%.0f", appStore.pageIndicatorTopPadding)).font(.footnote)
                        Spacer()
                        Text(String(format: "%.0f", AppStore.pageIndicatorTopPaddingRange.upperBound)).font(.footnote)
                    }
                }
                .disabled(appStore.pageIndicatorPerDisplayEnabled)

                VStack(alignment: .leading, spacing: 8) {
                    Button {
                        appStore.pageIndicatorPerDisplayEnabled.toggle()
                    } label: {
                        HStack(spacing: 8) {
                            Text("Per-display indicator position")
                                .font(.headline)
                            Spacer()
                            Toggle("", isOn: $appStore.pageIndicatorPerDisplayEnabled)
                                .labelsHidden()
                                .toggleStyle(.switch)
                                .allowsHitTesting(false)
                        }
                        .frame(maxWidth: .infinity, alignment: .leading)
                        .contentShape(Rectangle())
                    }
                    .buttonStyle(PressFeedbackRowButtonStyle(enabled: true, pressScale: 0.98))
                    Text("Use different values for each display.")
                        .font(.footnote)
                        .foregroundStyle(.secondary)

                    if appStore.pageIndicatorPerDisplayEnabled {
                        HStack {
                            Button("Apply defaults to current display") {
                                if let screenID = currentIndicatorScreenID {
                                    appStore.applyIndicatorDefaults(to: screenID)
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
            // Ignore errors or surface a user-facing message if desired
        }
    }

    private func exportDataFolder(to destParent: URL) throws {
        let sourceDir = try supportDirectoryURL()
        let formatter = DateFormatter()
        formatter.locale = Locale(identifier: "en_US_POSIX")
        formatter.dateFormat = "yyyy-MM-dd'_'HH.mm.ss"
        let folderName = "LaunchNext_" + formatter.string(from: Date()) + ".launchnext"
        let destDir = destParent.appendingPathComponent(folderName, isDirectory: true)
        try copyDirectory(from: sourceDir, to: destDir)
        exportPreferences(to: destDir)
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
                    keys.insert("useLocalizedThirdPartyTitles")
                    keys.insert("enableDropPrediction")
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
                    keys.insert("pageIndicatorOffset")
                    keys.insert(AppStore.pageIndicatorTopPaddingKey)
                    keys.insert(AppStore.pageIndicatorPerDisplayEnabledKey)
                    keys.insert(AppStore.pageIndicatorPerDisplayOverridesKey)
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
        try fm.copyItem(at: src, to: dst)
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
                    HStack {
                        Image(systemName: "party.popper.fill")
                            .foregroundStyle(.orange)
                        Text(appStore.localized(.updateAvailable))
                            .font(.subheadline.weight(.medium))
                    }

                    Text(appStore.localized(.newVersion) + " \(release.version)")
                        .font(.footnote)
                        .foregroundStyle(.secondary)

                    if let notes = release.notes, !notes.isEmpty {
                        Text(linkifiedText(notes))
                            .font(.footnote)
                            .foregroundStyle(.secondary)
                            .lineLimit(3)
                            .frame(maxHeight: updateNotesPreviewMaxHeight)
                            .clipped()
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

            if showUpdateNotes, let notes = availableNotes, !notes.isEmpty {
                Text(linkifiedText(notes))
                    .font(.callout)
                    .foregroundStyle(.secondary)
                    .frame(maxWidth: .infinity, alignment: .leading)
                    .textSelection(.enabled)
            }

            HStack(spacing: 12) {
                updateControlButton(
                    title: appStore.updateState == .idle
                        ? appStore.localized(.checkForUpdatesButton)
                        : appStore.localized(.updatesRefreshButton),
                    systemImage: "arrow.clockwise",
                    isPrimary: true
                ) {
                    appStore.checkForUpdates()
                }
                .disabled(appStore.updateState == .checking)

                Spacer(minLength: 0)

                if let release = availableRelease {
                    updateControlButton(
                        title: appStore.localized(.downloadUpdate),
                        systemImage: "arrow.down.circle"
                    ) {
                        appStore.launchUpdater(for: release)
                    }
                }

                if let notes = availableNotes, !notes.isEmpty {
                    Button {
                        showUpdateNotes.toggle()
                    } label: {
                        Image(systemName: showUpdateNotes ? "arrow.down.right.and.arrow.up.left" : "arrow.up.left.and.arrow.down.right")
                    }
                    .buttonStyle(.plain)
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

    private func updateControlButton(title: String, systemImage: String, isPrimary: Bool = false, action: @escaping () -> Void) -> some View {
        Button(action: action) {
            Label(title, systemImage: systemImage)
                .font(.subheadline.weight(.semibold))
                .padding(.horizontal, 16)
                .padding(.vertical, 8)
                .frame(minWidth: 160)
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

    private var updateNotesPreviewMaxHeight: CGFloat {
        let size = NSFont.systemFontSize(for: .small)
        return size * 1.2 * 3
    }

    private func linkifiedText(_ source: String) -> AttributedString {
        var attributed = AttributedString(source)
        guard let detector = try? NSDataDetector(types: NSTextCheckingResult.CheckingType.link.rawValue) else {
            return attributed
        }
        detector.enumerateMatches(in: source, options: [], range: NSRange(location: 0, length: (source as NSString).length)) { match, _, _ in
            guard let match, let url = match.url,
                  let range = Range(match.range, in: source),
                  let attrRange = Range(range, in: attributed) else { return }
            attributed[attrRange].link = url
            attributed[attrRange].foregroundColor = .accentColor
        }
        return attributed
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
