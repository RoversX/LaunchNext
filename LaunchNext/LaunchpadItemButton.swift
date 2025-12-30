import SwiftUI
import AppKit

struct LaunchpadItemButton: View {
    let item: LaunchpadItem
    let iconSize: CGFloat
    let labelWidth: CGFloat
    let isSelected: Bool
    let showLabel: Bool
    let labelFontSize: CGFloat
    let labelFontWeight: Font.Weight
    var shouldAllowHover: Bool = true
    var externalScale: CGFloat? = nil
    var hoverMagnificationEnabled: Bool = false
    var hoverMagnificationScale: CGFloat = 1.2
    var activePressEffectEnabled: Bool = false
    var activePressScale: CGFloat = 0.92
    let onTap: () -> Void
    let onDoubleClick: (() -> Void)?

    @State private var lastTapTime = Date.distantPast
    private let doubleTapThreshold: TimeInterval = 0.3

    init(item: LaunchpadItem,
         iconSize: CGFloat = 72,
         labelWidth: CGFloat = 80,
         isSelected: Bool = false,
         showLabel: Bool = true,
         labelFontSize: CGFloat = 11,
         labelFontWeight: Font.Weight = .medium,
         shouldAllowHover: Bool = true,
         externalScale: CGFloat? = nil,
         hoverMagnificationEnabled: Bool = false,
         hoverMagnificationScale: CGFloat = 1.2,
         activePressEffectEnabled: Bool = false,
         activePressScale: CGFloat = 0.92,
         onTap: @escaping () -> Void,
         onDoubleClick: (() -> Void)? = nil) {
        self.item = item
        self.iconSize = iconSize
        self.labelWidth = labelWidth
        self.isSelected = isSelected
        self.showLabel = showLabel
        self.labelFontSize = labelFontSize
        self.labelFontWeight = labelFontWeight
        self.shouldAllowHover = shouldAllowHover
        self.externalScale = externalScale
        self.hoverMagnificationEnabled = hoverMagnificationEnabled
        self.hoverMagnificationScale = hoverMagnificationScale
        self.activePressEffectEnabled = activePressEffectEnabled
        self.activePressScale = activePressScale
        self.onTap = onTap
        self.onDoubleClick = onDoubleClick
    }

    var body: some View {
        Button(action: handleTap) {
            LaunchpadItemButtonContent(
                item: item,
                iconSize: iconSize,
                labelWidth: labelWidth,
                isSelected: isSelected,
                showLabel: showLabel,
                labelFontSize: labelFontSize,
                labelFontWeight: labelFontWeight,
                shouldAllowHover: shouldAllowHover,
                externalScale: externalScale,
                hoverMagnificationEnabled: hoverMagnificationEnabled,
                hoverMagnificationScale: hoverMagnificationScale
            )
        }
        .buttonStyle(PressFeedbackButtonStyle(
            enabled: activePressEffectEnabled,
            pressScale: activePressScale,
            shouldAllowPressFeedback: shouldAllowHover
        ))
    }

    private func handleTap() {
        let now = Date()
        let timeSinceLastTap = now.timeIntervalSince(lastTapTime)

        if timeSinceLastTap <= doubleTapThreshold, let doubleClick = onDoubleClick {
            doubleClick()
        } else {
            onTap()
        }

        lastTapTime = now
    }
}

private struct LaunchpadItemButtonContent: View {
    let item: LaunchpadItem
    let iconSize: CGFloat
    let labelWidth: CGFloat
    let isSelected: Bool
    let showLabel: Bool
    let labelFontSize: CGFloat
    let labelFontWeight: Font.Weight
    let shouldAllowHover: Bool
    let externalScale: CGFloat?
    let hoverMagnificationEnabled: Bool
    let hoverMagnificationScale: CGFloat
    @State private var isHovered = false
    @State private var forceRefreshTrigger: UUID = UUID()

    private var isMissingItem: Bool {
        switch item {
        case .missingApp:
            return true
        case .app(let app):
            return !FileManager.default.fileExists(atPath: app.url.path)
        default:
            return false
        }
    }

    var body: some View {
        VStack(spacing: 8) {
            ZStack {
                let renderedIcon: NSImage = {
                    switch item {
                    case .app(let app):
                        if let cachedIcon = AppCacheManager.shared.getCachedIcon(for: app.url.path),
                           cachedIcon.size.width > 0,
                           cachedIcon.size.height > 0 {
                            return cachedIcon
                        }
                        let base = IconStore.shared.icon(for: app)
                        if FileManager.default.fileExists(atPath: app.url.path),
                           base.size.width > 0 && base.size.height > 0 {
                            return base
                        }
                        return MissingAppPlaceholder.defaultIcon
                    case .missingApp(let placeholder):
                        return placeholder.icon
                    case .folder(let folder):
                        return folder.icon(of: iconSize)
                    case .empty:
                        return item.icon
                    }
                }()
                let isFolderIcon: Bool = {
                    if case .folder = item { return true }
                    return false
                }()

                if isFolderIcon {
                    RoundedRectangle(cornerRadius: iconSize * 0.18)
                        .foregroundStyle(Color.clear)
                        .frame(width: iconSize * 0.8, height: iconSize * 0.8)
                        .liquidGlass(in: RoundedRectangle(cornerRadius: iconSize * 0.18))
                        .shadow(color: .black.opacity(0.12), radius: 1, x: 0, y: 0.5)
                }

                Image(nsImage: renderedIcon)
                    .resizable()
                    .interpolation(.high)
                    .antialiased(true)
                    .frame(width: iconSize, height: iconSize)
                    .opacity(isMissingItem ? 0.65 : 1.0)
                    .id(item.id + "_" + forceRefreshTrigger.uuidString)

                if isMissingItem {
                    Circle()
                        .fill(Color.orange.opacity(0.85))
                        .frame(width: iconSize * 0.22, height: iconSize * 0.22)
                        .overlay(
                            Image(systemName: "exclamationmark")
                                .font(.system(size: iconSize * 0.14, weight: .bold))
                                .foregroundStyle(Color.white)
                        )
                        .frame(maxWidth: .infinity, maxHeight: .infinity, alignment: .topTrailing)
                        .padding(iconSize * 0.1)
                        .allowsHitTesting(false)
                }
            }
            .scaleEffect(iconScale)
            .animation(LNAnimations.springFast, value: isSelected)
            .animation(LNAnimations.springFast, value: isHovered)

            if showLabel {
                Text(item.name)
                    .font(.system(size: labelFontSize, weight: labelFontWeight))
                    .lineLimit(1)
                    .multilineTextAlignment(.center)
                    .truncationMode(.tail)
                    .frame(width: labelWidth)
                    .foregroundStyle(isMissingItem ? Color.secondary : Color.primary)
            }
        }
        .padding(8)
        .onHover { hovering in
            guard shouldAllowHover else {
                if isHovered { isHovered = false }
                return
            }
            guard hoverMagnificationEnabled else {
                if isHovered { isHovered = false }
                return
            }
            if isHovered != hovering {
                withAnimation(LNAnimations.springFast) {
                    isHovered = hovering
                }
            }
        }
        .onChange(of: shouldAllowHover) { allow in
            if !allow {
                isHovered = false
            }
        }
        .onChange(of: hoverMagnificationEnabled) { enabled in
            if !enabled {
                isHovered = false
            }
        }
    }

    private var iconScale: CGFloat {
        if let externalScale {
            return externalScale
        }
        if isSelected {
            return 1.2
        }
        if hoverMagnificationEnabled && shouldAllowHover && isHovered {
            return hoverMagnificationScale
        }
        return 1.0
    }
}

private struct PressFeedbackButtonStyle: ButtonStyle {
    var enabled: Bool
    var pressScale: CGFloat
    var shouldAllowPressFeedback: Bool

    func makeBody(configuration: Configuration) -> some View {
        configuration.label
            .scaleEffect(scale(for: configuration))
            .animation(LNAnimations.springFast,
                       value: configuration.isPressed && enabled && shouldAllowPressFeedback)
    }

    private func scale(for configuration: Configuration) -> CGFloat {
        guard enabled, shouldAllowPressFeedback else { return 1.0 }
        let clamped = max(min(pressScale, 1.0), 0.5)
        return configuration.isPressed ? clamped : 1.0
    }
}
