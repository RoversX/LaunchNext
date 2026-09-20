import XCTest
import QuartzCore

// The production trajectory is compiled into this test target.
final class FolderPresentationMotionTests: XCTestCase {
    func testRetargetPreservesPositionAndVelocity() {
        let opening = FolderPresentationMotion(start: 0, target: 1, startTime: 0, baseDuration: 0.24)
        let time = 0.09
        let position = opening.position(at: time), velocity = opening.velocity(at: time)
        let closing = FolderPresentationMotion(start: position, target: 0, velocity: velocity,
                                               startTime: time, baseDuration: 0.28)
        XCTAssertEqual(closing.position(at: time), position, accuracy: 1e-10)
        XCTAssertEqual(closing.velocity(at: time), velocity, accuracy: 1e-10)
        XCTAssertGreaterThan(closing.position(at: time + 0.001), position,
                             "motion must decelerate before reversing")
        let againTime = time + closing.duration * 0.65
        let reopening = FolderPresentationMotion(start: closing.position(at: againTime), target: 1,
            velocity: closing.velocity(at: againTime), startTime: againTime, baseDuration: 0.24)
        XCTAssertLessThan(reopening.initialVelocity, 0)
        XCTAssertEqual(reopening.velocity(at: againTime), closing.velocity(at: againTime), accuracy: 1e-10)
        XCTAssertEqual(reopening.position(at: againTime + reopening.duration), 1, accuracy: 1e-10)
        XCTAssertEqual(reopening.velocity(at: againTime + reopening.duration), 0)
    }

    func testRepeatedReversalsStayBoundedAndKeyframesFollowTheTrajectory() {
        var motion = FolderPresentationMotion(start: 0, target: 1, startTime: 0, baseDuration: 0.24)
        for iteration in 0..<200 {
            let time = motion.startTime + motion.duration * CGFloat((iteration % 8) + 1) / 10
            let target: CGFloat = iteration.isMultiple(of: 2) ? 0 : 1
            motion = FolderPresentationMotion(start: motion.position(at: time), target: target,
                velocity: motion.velocity(at: time), startTime: time, baseDuration: target == 0 ? 0.28 : 0.24)
            for i in 0...100 {
                let p = motion.position(at: time + motion.duration * Double(i) / 100)
                XCTAssertGreaterThanOrEqual(p, -1e-9)
                XCTAssertLessThanOrEqual(p, 1 + 1e-9)
            }
            for (fraction, keyTime) in zip(motion.fractions, motion.keyTimes) {
                XCTAssertEqual(motion.start + (motion.target - motion.start) * fraction,
                    motion.position(at: time + motion.duration * keyTime.doubleValue), accuracy: 1e-8)
            }
            XCTAssertLessThanOrEqual(motion.fractions.count, 3)
            for function in motion.timingFunctions {
                for index in [1, 2] {
                    var point = [Float](repeating: 0, count: 2)
                    function.getControlPoint(at: index, values: &point)
                    XCTAssertGreaterThanOrEqual(point[1], -1e-6)
                    XCTAssertLessThanOrEqual(point[1], 1 + 1e-6)
                }
            }
        }
    }

    func testNativeBezierLegsMatchTheTrajectoryBetweenKeyframes() {
        for velocity: CGFloat in [-5, 0, 5] {
            for target: CGFloat in [0, 1] {
                let motion = FolderPresentationMotion(start: 0.4, target: target, velocity: velocity,
                                                      startTime: 0, baseDuration: 0.24)
                for (index, function) in motion.timingFunctions.enumerated() {
                    var a = [Float](repeating: 0, count: 2), b = a
                    function.getControlPoint(at: 1, values: &a)
                    function.getControlPoint(at: 2, values: &b)
                    let begin = motion.keyTimes[index].doubleValue
                    let end = motion.keyTimes[index + 1].doubleValue
                    let p = motion.fractions[index], q = motion.fractions[index + 1]
                    for step in 0...20 {
                        let t = CGFloat(step) / 20
                        let eased = 3 * (1 - t) * (1 - t) * t * CGFloat(a[1])
                            + 3 * (1 - t) * t * t * CGFloat(b[1]) + t * t * t
                        let rendered = motion.start + (motion.target - motion.start) * (p + (q - p) * eased)
                        let analytic = motion.position(at: motion.duration * (begin + (end - begin) * t))
                        XCTAssertEqual(rendered, analytic, accuracy: 1e-6)
                    }
                }
            }
        }
    }

    func testOpeningAndClosingUseMirroredEaseInOut() {
        let opening = FolderPresentationMotion(start: 0, target: 1, startTime: 0, baseDuration: 0.24)
        let closing = FolderPresentationMotion(start: 1, target: 0, startTime: 0, baseDuration: 0.28)
        XCTAssertGreaterThan(closing.duration, opening.duration)
        for fraction: Double in [0, 0.1, 0.25, 0.5, 0.75, 0.9, 1] {
            let time = fraction * opening.duration
            XCTAssertEqual(opening.position(at: time), 1 - closing.position(at: fraction * closing.duration), accuracy: 1e-9)
        }
        XCTAssertLessThan(opening.position(at: opening.duration * 0.25), 0.25)
        XCTAssertGreaterThan(opening.position(at: opening.duration * 0.75), 0.75)
        XCTAssertEqual(opening.velocity(at: 0), 0)
        XCTAssertEqual(closing.velocity(at: 0), 0)
    }

    func testCompletedMotionHasNoResidualVelocity() {
        let motion = FolderPresentationMotion(start: 1, target: 0, startTime: 10, baseDuration: 0.28)
        XCTAssertEqual(motion.duration, 0.28, accuracy: 1e-9)
        XCTAssertEqual(motion.position(at: 11), 0)
        XCTAssertEqual(motion.velocity(at: 11), 0)
    }
}
