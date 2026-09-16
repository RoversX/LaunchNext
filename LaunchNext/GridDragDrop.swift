import QuartzCore

/// The operation currently shown by the grid, also consumed on mouse-up.
enum GridDropPreview: Equatable {
    case none
    case insert(index: Int)
    case merge(targetID: String)

    static func insertion(index: Int, sourceIndex: Int, itemCount: Int, itemsPerPage: Int) -> Self {
        guard index >= 0, sourceIndex >= 0, sourceIndex < itemCount, itemsPerPage > 0 else { return .none }
        // Match the owner's same-page insertion clamp, rather than animating
        // toward an empty trailing cell that the model will never occupy.
        let samePage = index / itemsPerPage == sourceIndex / itemsPerPage
        let pageEnd = min((sourceIndex / itemsPerPage + 1) * itemsPerPage, itemCount)
        let destination = samePage ? min(index, pageEnd - 1) : min(index, itemCount)
        return destination == sourceIndex ? .none : .insert(index: destination)
    }
}

enum GridLayerMotion {
    static let duration: CFTimeInterval = 0.18
    static let hoverDuration: CFTimeInterval = 0.45

    /// Retarget from the visible position. An unchanged destination preserves
    /// its animation, including when SwiftUI publishes the same order twice.
    static func move(_ layer: CALayer, to position: CGPoint,
                     from visiblePosition: CGPoint? = nil, duringHover: Bool = false) {
        guard layer.position != position else { return }
        let from = visiblePosition ?? layer.presentation()?.position ?? layer.position
        CATransaction.begin()
        CATransaction.setDisableActions(true)
        layer.position = position
        layer.removeAnimation(forKey: "position")
        if from != position {
            let animation = CABasicAnimation(keyPath: "position")
            animation.fromValue = NSValue(point: from)
            animation.toValue = NSValue(point: position)
            animation.duration = duringHover ? hoverDuration : duration
            animation.timingFunction = duringHover
                ? CAMediaTimingFunction(controlPoints: 0.25, 1.0, 0.35, 1.0)
                : CAMediaTimingFunction(name: .easeOut)
            layer.add(animation, forKey: "position")
        }
        CATransaction.commit()
    }
}
