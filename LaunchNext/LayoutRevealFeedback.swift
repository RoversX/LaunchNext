import AppKit
import QuartzCore

/// A visual acknowledgement of navigation, independent of mouse/selection state.
enum LayoutRevealFeedback {
    static let animationKey = "layoutReveal.press"
    static let duration: TimeInterval = 0.22

    struct PageMotion {
        let id = UUID()
        let from: CGFloat
        let to: CGFloat
        let pageStride: CGFloat
        let startedAt = CACurrentMediaTime()
        let duration: TimeInterval
    }

    static func pageDuration(distance: Int) -> TimeInterval {
        0.5 + Double(min(4, max(0, distance - 1))) * 0.08
    }

    @discardableResult
    static func animate(on layer: CALayer, pressScale: CGFloat, enabled: Bool) -> Bool {
        guard enabled, !NSWorkspace.shared.accessibilityDisplayShouldReduceMotion else { return false }
        let scale = pressScale.isFinite ? min(0.98, max(0.8, pressScale)) : 0.92
        let animation = CAKeyframeAnimation(keyPath: "transform.scale")
        animation.values = [1, scale, 1]
        animation.keyTimes = [0, 0.35, 1]
        animation.timingFunctions = [CAMediaTimingFunction(name: .easeOut),
                                     CAMediaTimingFunction(name: .easeInEaseOut)]
        animation.duration = duration
        // Keep the model transform untouched; CA removes the transient effect.
        layer.add(animation, forKey: animationKey)
        return true
    }
}

extension CAGridView {
    /// Reads existing layers only; decoding stays on the normal asynchronous path.
    func revealIconsAreReady(from firstPage: Int, through lastPage: Int) -> Bool {
        guard itemsPerPage > 0, bounds.width > 0, bounds.height > 0 else { return false }
        let first = max(0, min(firstPage, lastPage))
        let last = min(pageCount - 1, max(firstPage, lastPage))
        guard first <= last else { return false }
        for page in first...last {
            for index in (page * itemsPerPage)..<min((page + 1) * itemsPerPage, items.count) {
                if case .empty = items[index] { continue }
                guard let container = presentationContainer(at: index), container.bounds.width > 0,
                      container.sublayers?.first(where: { $0.name == "icon" })?.contents != nil else { return false }
            }
        }
        return true
    }
}
