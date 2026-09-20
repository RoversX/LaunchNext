import QuartzCore

/// A bounded Hermite trajectory. Retargeting carries position and velocity;
/// monotonic Bezier legs run in CA, with no application-side display-link work.
struct FolderPresentationMotion {
    let start: CGFloat
    let target: CGFloat
    let initialVelocity: CGFloat
    let startTime: CFTimeInterval
    let duration: TimeInterval
    let fractions: [CGFloat]
    let keyTimes: [NSNumber]
    let timingFunctions: [CAMediaTimingFunction]

    init(start: CGFloat, target: CGFloat, velocity: CGFloat = 0,
         startTime: CFTimeInterval, baseDuration: TimeInterval) {
        self.start = min(1, max(0, start))
        self.target = target
        self.startTime = startTime
        var velocity = velocity
        if abs(target - self.start) < 0.000001 { velocity = 0 }
        if (self.start <= 0 && velocity < 0) || (self.start >= 1 && velocity > 0) { velocity = 0 }
        self.initialVelocity = velocity
        var duration = baseDuration * Double(max(0.25, sqrt(abs(target - self.start))))
        // Keep the Bezier control point inside [0, 1]. This bounds the whole
        // curve while allowing a short continuation in the old direction.
        if velocity > 0 { duration = min(duration, Double(3 * (1 - self.start) / velocity)) }
        if velocity < 0 { duration = min(duration, Double(3 * self.start / -velocity)) }
        self.duration = max(0.0001, duration)
        let delta = target - self.start
        let tangent = velocity * self.duration
        // Split exactly where velocity reaches zero. Each leg is monotonic,
        // so CA's timing function can represent the cubic without clamping an
        // out-of-range timing control point or approximating it at frame steps.
        let divisor = 6 * delta - 3 * tangent
        let turn = abs(divisor) > 1e-12 ? -tangent / divisor : -1
        let times: [CGFloat] = turn > 0 && turn < 1 ? [0, turn, 1] : [0, 1]
        func displacement(_ t: CGFloat) -> CGFloat {
            delta * t * t * (3 - 2 * t) + tangent * t * (1 - t) * (1 - t)
        }
        func derivative(_ t: CGFloat) -> CGFloat {
            delta * 6 * t * (1 - t) + tangent * (1 - 4 * t + 3 * t * t)
        }
        self.keyTimes = times.map { NSNumber(value: Double($0)) }
        self.fractions = times.map { abs(delta) > 0.000001 ? displacement($0) / delta : $0 }
        self.timingFunctions = zip(times, times.dropFirst()).map { a, b in
            let distance = displacement(b) - displacement(a)
            let first = abs(distance) > 1e-12 ? derivative(a) * (b - a) / distance / 3 : 0
            let second = abs(distance) > 1e-12 ? 1 - derivative(b) * (b - a) / distance / 3 : 1
            return CAMediaTimingFunction(controlPoints: 1 / 3, Float(first), 2 / 3, Float(second))
        }

    }

    func position(at time: CFTimeInterval) -> CGFloat {
        let t = CGFloat(min(1, max(0, (time - startTime) / duration)))
        return start + (target - start) * t * t * (3 - 2 * t)
            + initialVelocity * duration * t * (1 - t) * (1 - t)
    }

    func velocity(at time: CFTimeInterval) -> CGFloat {
        guard time >= startTime, time < startTime + duration else { return 0 }
        let t = CGFloat((time - startTime) / duration)
        return (target - start) * 6 * t * (1 - t) / duration
            + initialVelocity * (1 - 4 * t + 3 * t * t)
    }

    func animation(keyPath: String, on layer: CALayer, value: (CGFloat) -> Any) -> CAKeyframeAnimation {
        let animation = CAKeyframeAnimation(keyPath: keyPath)
        animation.values = fractions.map(value)
        animation.keyTimes = keyTimes
        // Linear interpolation of values within a leg; its timing function
        // supplies the nonlinear velocity curve, including smooth reversals.
        animation.calculationMode = .linear
        animation.timingFunctions = timingFunctions
        animation.duration = duration
        animation.beginTime = layer.convertTime(startTime, from: nil)
        animation.fillMode = .both
        animation.isRemovedOnCompletion = false
        return animation
    }

    static func rect(from a: CGRect, to b: CGRect, fraction t: CGFloat) -> CGRect {
        CGRect(x: a.minX + (b.minX - a.minX) * t, y: a.minY + (b.minY - a.minY) * t,
               width: a.width + (b.width - a.width) * t, height: a.height + (b.height - a.height) * t)
    }

    static func transform(from a: CATransform3D, to b: CATransform3D, fraction t: CGFloat) -> CATransform3D {
        var result = CATransform3DIdentity
        result.m11 = a.m11 + (b.m11 - a.m11) * t
        result.m22 = a.m22 + (b.m22 - a.m22) * t
        result.m41 = a.m41 + (b.m41 - a.m41) * t
        result.m42 = a.m42 + (b.m42 - a.m42) * t
        return result
    }
}
