import AppKit

/// Decides when the pointer starts a new visit to a hot corner.
///
/// A visit starts when the pointer enters a corner's hitbox. Until it triggers,
/// the pointer must stay in the hitbox, so passing through the corner never
/// fires. Once it has triggered, the visit lasts until the pointer leaves a
/// larger area around the hitbox, so jitter at the hitbox edge never counts as
/// leaving and entering again. Each visit triggers at most once.
struct HotCornerTracker {
    struct Corner {
        let hitbox: CGRect
        /// The frame of the screen the corner belongs to.
        let screenFrame: CGRect
    }

    enum Action: Equatable {
        case ignore
        /// The visit ended; drop any pending trigger.
        case cancel
        /// A visit started; trigger after `delay` if `mayTrigger(visit:)` still allows it.
        case schedule(visit: Int, delay: TimeInterval)
    }

    /// How far beyond the hitbox the pointer must travel to end a visit that has triggered.
    static let exitMargin: CGFloat = 20
    /// The shortest time between two triggers. A visit that starts sooner waits
    /// for it. Slightly longer than the default 0.25 s window fade, because a
    /// trigger that lands mid-fade is dropped.
    static let cooldown: TimeInterval = 0.3

    private struct Visit {
        let number: Int
        let hitbox: CGRect
        let exitArea: CGRect
        var hasTriggered = false
    }

    private var visit: Visit?
    private var visitCount = 0
    private var cooldownEnd = -TimeInterval.infinity

    /// `now` is a monotonic time in seconds, such as `ProcessInfo.systemUptime`.
    /// `corners` is only read when no visit holds the pointer.
    mutating func pointerMoved(to point: CGPoint,
                               at now: TimeInterval,
                               triggerDelay: TimeInterval,
                               corners: () -> [Corner]) -> Action {
        var action = Action.ignore
        if let visit {
            let area = visit.hasTriggered ? visit.exitArea : visit.hitbox
            if Self.rect(area, contains: point) { return .ignore }
            self.visit = nil
            action = .cancel
        }
        guard let corner = corners().first(where: { Self.rect($0.hitbox, contains: point) }) else {
            return action
        }
        visitCount += 1
        // The exit area stays on the corner's screen, so moving onto a
        // neighbouring display always ends the visit.
        let exitArea = corner.hitbox
            .insetBy(dx: -Self.exitMargin, dy: -Self.exitMargin)
            .intersection(corner.screenFrame)
        visit = Visit(number: visitCount, hitbox: corner.hitbox, exitArea: exitArea)
        return .schedule(visit: visitCount, delay: max(triggerDelay, cooldownEnd - now, 0))
    }

    /// Whether a trigger scheduled for this visit may still fire.
    func mayTrigger(visit number: Int) -> Bool {
        visit?.number == number && visit?.hasTriggered == false
    }

    mutating func didTrigger(visit number: Int, at now: TimeInterval) {
        guard visit?.number == number else { return }
        visit?.hasTriggered = true
        cooldownEnd = now + Self.cooldown
    }

    mutating func reset() {
        visit = nil
    }

    /// Uses AppKit's pointer rule: a pointer at the top edge of a screen
    /// reports y == frame.maxY and belongs to that screen, while x == maxX and
    /// y == minY belong to the neighbouring one. CGRect.contains gets the top
    /// edge wrong.
    static func rect(_ rect: CGRect, contains point: CGPoint) -> Bool {
        NSMouseInRect(point, rect, false)
    }
}
