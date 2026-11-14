import CoreGraphics
import XCTest

// HotCornerTracker.swift is compiled into this target through an explicit entry
// in the test target's Sources build phase, so these cover the production rules.
@MainActor
final class HotCornerTrackerTests: XCTestCase {
    // A 1000 x 800 screen with a 50-point top-left hitbox, in AppKit coordinates.
    private let screen = CGRect(x: 0, y: 0, width: 1000, height: 800)
    private lazy var corner = HotCornerTracker.Corner(hitbox: CGRect(x: 0, y: 750, width: 50, height: 50),
                                                      screenFrame: screen)
    private let delay: TimeInterval = 0.1

    private func move(_ tracker: inout HotCornerTracker,
                      to point: CGPoint,
                      at seconds: TimeInterval,
                      corners: [HotCornerTracker.Corner]? = nil) -> HotCornerTracker.Action {
        let corners = corners ?? [corner]
        return tracker.pointerMoved(to: point, at: seconds, triggerDelay: delay, corners: { corners })
    }

    /// Enters the corner at time 0 and lets the scheduled trigger fire.
    private func triggeredTracker() -> HotCornerTracker {
        var tracker = HotCornerTracker()
        guard case .schedule(let visit, _) = move(&tracker, to: CGPoint(x: 10, y: 790), at: 0) else {
            XCTFail("entering the corner did not schedule a trigger")
            return tracker
        }
        tracker.didTrigger(visit: visit, at: delay)
        return tracker
    }

    func testEnteringTheCornerSchedulesAfterTheTriggerDelay() {
        var tracker = HotCornerTracker()
        XCTAssertEqual(move(&tracker, to: CGPoint(x: 500, y: 400), at: 0), .ignore)
        XCTAssertEqual(move(&tracker, to: CGPoint(x: 10, y: 790), at: 0), .schedule(visit: 1, delay: delay))
        XCTAssertTrue(tracker.mayTrigger(visit: 1))
    }

    func testPointerPinnedToTheTopEdgeIsInsideTheCorner() {
        // Pushed against the top of the screen, the pointer reports y == maxY.
        var tracker = HotCornerTracker()
        XCTAssertEqual(move(&tracker, to: CGPoint(x: 0, y: 800), at: 0), .schedule(visit: 1, delay: delay))
    }

    func testLeavingTheHitboxBeforeTheTriggerCancelsIt() {
        // Resting just outside the hitbox, inside the exit margin, is not
        // staying in the corner, so the pending trigger must not fire.
        var tracker = HotCornerTracker()
        _ = move(&tracker, to: CGPoint(x: 10, y: 790), at: 0)
        XCTAssertEqual(move(&tracker, to: CGPoint(x: 65, y: 790), at: 0.05), .cancel)
        XCTAssertFalse(tracker.mayTrigger(visit: 1))
    }

    func testJitteringAfterTheTriggerStaysOneVisit() {
        var tracker = triggeredTracker()
        // Moving inside the hitbox, then just past its edge and back, is one visit.
        for (x, y) in [(20.0, 780.0), (53.0, 790.0), (40.0, 746.0), (30.0, 790.0)] {
            XCTAssertEqual(move(&tracker, to: CGPoint(x: x, y: y), at: 1), .ignore, "(\(x), \(y)) started a new visit")
        }
        XCTAssertFalse(tracker.mayTrigger(visit: 1), "a visit triggers at most once")
    }

    func testLeavingBeyondTheMarginThenReenteringTriggersAgain() {
        var tracker = triggeredTracker()
        XCTAssertEqual(move(&tracker, to: CGPoint(x: 200, y: 600), at: 1), .cancel)
        XCTAssertEqual(move(&tracker, to: CGPoint(x: 5, y: 795), at: 1.2), .schedule(visit: 2, delay: delay))
    }

    func testReenteringDuringTheCooldownWaitsForItInsteadOfBeingLost() {
        var tracker = HotCornerTracker()
        _ = move(&tracker, to: CGPoint(x: 10, y: 790), at: 0)
        tracker.didTrigger(visit: 1, at: 0)
        _ = move(&tracker, to: CGPoint(x: 300, y: 500), at: 0.05)
        guard case .schedule(let visit, let wait) = move(&tracker, to: CGPoint(x: 10, y: 790), at: 0.1) else {
            return XCTFail("re-entering during the cooldown did not schedule a trigger")
        }
        XCTAssertEqual(visit, 2)
        XCTAssertEqual(wait, HotCornerTracker.cooldown - 0.1, accuracy: 0.0001,
                       "the trigger must wait exactly for the rest of the cooldown")
    }

    func testExitMarginDoesNotReachTheNeighbouringScreen() {
        // Screen B sits right of screen A; both use a top-right corner.
        let screenB = CGRect(x: 1000, y: 0, width: 1000, height: 800)
        let corners = [
            HotCornerTracker.Corner(hitbox: CGRect(x: 950, y: 750, width: 50, height: 50), screenFrame: screen),
            HotCornerTracker.Corner(hitbox: CGRect(x: 1950, y: 750, width: 50, height: 50), screenFrame: screenB),
        ]
        var tracker = HotCornerTracker()
        XCTAssertEqual(move(&tracker, to: CGPoint(x: 990, y: 790), at: 0, corners: corners),
                       .schedule(visit: 1, delay: delay))
        tracker.didTrigger(visit: 1, at: delay)
        XCTAssertEqual(move(&tracker, to: CGPoint(x: 995, y: 790), at: 1, corners: corners), .ignore)
        // x == 1000 is screen B's first column, so the visit to A's corner ends.
        XCTAssertEqual(move(&tracker, to: CGPoint(x: 1000, y: 790), at: 1, corners: corners), .cancel)
        XCTAssertEqual(move(&tracker, to: CGPoint(x: 990, y: 790), at: 2, corners: corners),
                       .schedule(visit: 2, delay: delay))
    }

    func testTriggerForAnEndedVisitDoesNothing() {
        var tracker = HotCornerTracker()
        _ = move(&tracker, to: CGPoint(x: 10, y: 790), at: 0)
        _ = move(&tracker, to: CGPoint(x: 400, y: 400), at: 0.05)
        tracker.didTrigger(visit: 1, at: 0.1)
        // A late trigger for the old visit must not start a cooldown.
        XCTAssertEqual(move(&tracker, to: CGPoint(x: 10, y: 790), at: 0.15), .schedule(visit: 2, delay: delay))
    }

    func testResetEndsTheVisit() {
        var tracker = HotCornerTracker()
        _ = move(&tracker, to: CGPoint(x: 10, y: 790), at: 0)
        tracker.reset()
        XCTAssertFalse(tracker.mayTrigger(visit: 1))
        XCTAssertEqual(move(&tracker, to: CGPoint(x: 10, y: 790), at: 1), .schedule(visit: 2, delay: delay))
    }
}
