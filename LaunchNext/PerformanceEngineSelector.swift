import SwiftUI

/// Two discrete engine choices with a static, machined-metal finish.
/// The dials are buttons, not continuous controls; no timer drives their highlights.
struct PerformanceEngineSelector: View {
    @Binding var selection: PerformanceMode
    let nextTitle: String
    let legacyTitle: String
    let nextDescription: String
    let legacyDescription: String
    let restartHint: String

    static let accent = Color.accentColor

    var body: some View {
        HStack(spacing: 12) {
            choice(.lean, title: nextTitle, description: nextDescription)
            choice(.full, title: legacyTitle, description: legacyDescription)
        }
        .fixedSize(horizontal: false, vertical: true)
    }

    private func choice(_ mode: PerformanceMode, title: String, description: String) -> some View {
        let selected = selection == mode
        return Button {
            selection = mode
        } label: {
            HStack(spacing: 12) {
                MetalEngineDial(isSelected: selected)
                    // Scale the complete dial so its bevel and pointer keep
                    // their proportions, while reserving only the smaller size.
                    .frame(width: 112, height: 112)
                    .scaleEffect(0.5)
                    .frame(width: 56, height: 56)
                VStack(alignment: .leading, spacing: 5) {
                    HStack(spacing: 8) {
                        Text(title)
                            .font(.headline)
                            .foregroundStyle(.primary)
                            .fixedSize(horizontal: false, vertical: true)
                        Circle()
                            .fill(selected ? Self.accent : Color.secondary.opacity(0.35))
                            .frame(width: 6, height: 6)
                            .shadow(color: selected ? Self.accent.opacity(0.5) : .clear, radius: 3)
                    }
                    Text(description)
                        .font(.caption)
                        .foregroundStyle(.secondary)
                        .fixedSize(horizontal: false, vertical: true)
                }
                .frame(maxWidth: .infinity, alignment: .leading)
            }
            .multilineTextAlignment(.leading)
            .padding(12)
            .frame(maxWidth: .infinity, maxHeight: .infinity)
            .background(PerformanceMetalSurface(emphasized: selected))
            .contentShape(RoundedRectangle(cornerRadius: 14, style: .continuous))
        }
        .buttonStyle(EngineChoiceButtonStyle())
        .accessibilityElement(children: .ignore)
        .accessibilityLabel(title)
        .accessibilityHint(description + " " + restartHint)
        .accessibilityAddTraits(selected ? .isSelected : [])
        .help(restartHint)
    }
}

struct PerformanceMetalSurface: View {
    var emphasized = false
    @Environment(\.colorScheme) private var colorScheme

    var body: some View {
        let dark = colorScheme == .dark
        let shape = RoundedRectangle(cornerRadius: 14, style: .continuous)
        shape.fill(LinearGradient(
            colors: dark
                ? [Color(white: 0.20), Color(white: 0.13)]
                : [Color(white: 0.96), Color(white: 0.86)],
            startPoint: .topLeading, endPoint: .bottomTrailing
        ))
        .overlay {
            shape.strokeBorder(LinearGradient(
                colors: emphasized
                    ? [PerformanceEngineSelector.accent.opacity(0.7), PerformanceEngineSelector.accent.opacity(0.18)]
                    : [Color.white.opacity(dark ? 0.22 : 0.8), Color.black.opacity(0.13)],
                startPoint: .topLeading, endPoint: .bottomTrailing
            ), lineWidth: 0.75)
        }
    }
}

private struct MetalEngineDial: View {
    let isSelected: Bool

    private var steel: [Color] {
        [Color(white: 0.72), Color(white: 0.30), Color(white: 0.16),
         Color(white: 0.54), Color(white: 0.76), Color(white: 0.27),
         Color(white: 0.17), Color(white: 0.55), Color(white: 0.72)]
    }

    var body: some View {
        ZStack {
            Circle().fill(Color(white: 0.09))
                .overlay { Circle().strokeBorder(Color.white.opacity(0.12), lineWidth: 1) }
            Circle().trim(from: 0, to: 0.75)
                .stroke(Color.black.opacity(0.65), style: StrokeStyle(lineWidth: 4, lineCap: .round))
                .rotationEffect(.degrees(135))
                .padding(4)
            if isSelected {
                Circle().trim(from: 0, to: 0.75)
                    .stroke(LinearGradient(colors: [PerformanceEngineSelector.accent.opacity(0.65),
                                                    PerformanceEngineSelector.accent, PerformanceEngineSelector.accent.opacity(0.8)],
                                           startPoint: .topLeading, endPoint: .bottomTrailing),
                            style: StrokeStyle(lineWidth: 3, lineCap: .round))
                    .rotationEffect(.degrees(135))
                    .padding(4)
            }
            Circle().fill(AngularGradient(colors: steel, center: .center, startAngle: .degrees(-30), endAngle: .degrees(330)))
                .overlay { Circle().strokeBorder(Color.black.opacity(0.8), lineWidth: 2) }
                .padding(10)
                .shadow(color: .black.opacity(0.45), radius: 3, y: 3)
            Circle().fill(AngularGradient(colors: steel.reversed(), center: .center))
                .overlay {
                    // A few concentric hairlines suggest machining without a
                    // texture bitmap, a blur pass, or an animated drawing loop.
                    Canvas { context, size in
                        for inset in stride(from: CGFloat(3), through: size.width / 2, by: 3) {
                            let rect = CGRect(origin: .zero, size: size).insetBy(dx: inset, dy: inset)
                            guard rect.width > 0 else { continue }
                            context.stroke(Path(ellipseIn: rect), with: .color(.white.opacity(0.045)), lineWidth: 0.5)
                        }
                    }
                    .clipShape(Circle())
                }
                .overlay { Circle().strokeBorder(Color.white.opacity(0.4), lineWidth: 0.75) }
                .padding(15)
            Capsule().fill(Color.white.opacity(0.85))
                .frame(width: 2, height: 9)
                .offset(y: -32)
                .rotationEffect(.degrees(isSelected ? -40 : 40))
        }
        .accessibilityHidden(true)
    }
}

private struct EngineChoiceButtonStyle: ButtonStyle {
    @Environment(\.accessibilityReduceMotion) private var reduceMotion

    func makeBody(configuration: Configuration) -> some View {
        configuration.label
            .scaleEffect(configuration.isPressed ? 0.98 : 1)
            .brightness(configuration.isPressed ? -0.035 : 0)
            .animation(reduceMotion ? nil : .easeOut(duration: 0.12), value: configuration.isPressed)
    }
}
