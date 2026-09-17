import SwiftUI

/// One hover material for the entire row; dot contrast does not require reading
/// the wallpaper or adding a per-frame update to the grid.
struct LaunchpadPageIndicator: View {
    let pageCount: Int
    let currentPage: Int
    let isActive: Bool
    let onSelect: (Int) -> Void

    @Environment(\.accessibilityReduceMotion) private var reduceMotion
    @Environment(\.accessibilityReduceTransparency) private var reduceTransparency
    @State private var isHovered = false

    private var showsHover: Bool { isHovered && isActive }

    var body: some View {
        HStack(spacing: 0) {
            ForEach(0..<max(0, pageCount), id: \.self) { index in
                Button {
                    onSelect(index)
                } label: {
                    Circle()
                        .fill(Color.primary
                            .opacity(currentPage == index ? 1 : (showsHover ? 0.75 : 0.55)))
                        .frame(width: 8, height: 8)
                        .frame(width: 16, height: 28)
                        .contentShape(Rectangle())
                }
                .buttonStyle(.plain)
                .focusable(false)
                .accessibilityLabel(Text(verbatim: (index + 1).formatted()))
                .accessibilityAddTraits(currentPage == index ? .isSelected : [])
            }
        }
        .padding(.horizontal, 10)
        .background {
            if showsHover {
                hoverBackground
                    .allowsHitTesting(false)
                    .transition(.opacity)
            }
        }
        .contentShape(Capsule())
        .onHover { inside in
            withAnimation(reduceMotion ? nil : .easeOut(duration: 0.14)) {
                isHovered = inside && isActive
            }
        }
        .onChange(of: isActive) { _, active in
            if !active { isHovered = false }
        }
        .onDisappear { isHovered = false }
        .allowsHitTesting(isActive)
        // Reserve the full hit area even at zero indicator padding. Hovering
        // changes only the material, never the grid layout or button geometry.
        .frame(height: 28)
    }

    @ViewBuilder
    private var hoverBackground: some View {
        if reduceTransparency {
            Capsule().fill(Color(nsColor: .windowBackgroundColor))
        } else {
            Capsule()
                .fill(.clear)
                .glassEffect(.regular, in: Capsule())
        }
    }
}
