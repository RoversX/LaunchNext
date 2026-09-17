import XCTest
import CoreGraphics

// The production geometry source is also compiled into this test target.
final class CompactWindowLayoutTests: XCTestCase {
    private let minimum = CGSize(width: 800, height: 600)

    func testUltrawideMatchesSameHeightStandardDisplay() {
        let standard = CompactWindowLayout.frame(in: CGRect(x: 0, y: 0, width: 2560, height: 1440), minimum: minimum)
        let ultrawide = CompactWindowLayout.frame(in: CGRect(x: 0, y: 0, width: 5120, height: 1440), minimum: minimum)
        XCTAssertEqual(standard.size, CGSize(width: 1024, height: 768))
        XCTAssertEqual(ultrawide.size, standard.size)
    }

    func testOrdinaryDisplaysKeepExistingSizeWhenUncapped() {
        for size in [CGSize(width: 1440, height: 900), CGSize(width: 2560, height: 1600)] {
            let frame = CompactWindowLayout.frame(in: CGRect(origin: .zero, size: size), minimum: minimum)
            let oldWidth = max(size.width * 0.4, 800)
            XCTAssertEqual(frame.width, oldWidth)
            XCTAssertEqual(frame.height, oldWidth * 0.75)
        }
    }

    func testSmallAndPortraitDisplaysFitAndStayCentered() {
        for size in [CGSize(width: 640, height: 480), CGSize(width: 1280, height: 500),
                     CGSize(width: 600, height: 1200), CGSize(width: 5120, height: 1390)] {
            let available = CGRect(origin: CGPoint(x: -3200, y: 48), size: size)
            let frame = CompactWindowLayout.frame(in: available, minimum: minimum)
            let limit = CompactWindowLayout.minimumSize(in: available, preferred: minimum)
            XCTAssertLessThanOrEqual(frame.width, size.width)
            XCTAssertLessThanOrEqual(frame.height, size.height)
            XCTAssertEqual(frame.midX, available.midX, accuracy: 0.001)
            XCTAssertEqual(frame.midY, available.midY, accuracy: 0.001)
            XCTAssertEqual(frame.width / frame.height, 4.0 / 3.0, accuracy: 0.001)
            XCTAssertLessThanOrEqual(limit.width, frame.width)
            XCTAssertLessThanOrEqual(limit.height, frame.height)
        }
    }

    func testMinimumRecoversAfterMovingFromSmallDisplay() {
        let small = CGRect(x: 0, y: 0, width: 640, height: 480)
        XCTAssertEqual(CompactWindowLayout.minimumSize(in: small, preferred: minimum), small.size)
        let large = CGRect(x: 640, y: 0, width: 2560, height: 1440)
        XCTAssertEqual(CompactWindowLayout.minimumSize(in: large, preferred: minimum), minimum)
    }

    func testCustomLimitsKeepAspectRatioAndUseTighterDimension() {
        let screen = CGRect(x: 0, y: 0, width: 5120, height: 1440)
        let widthOnly = CompactWindowLayout.frame(in: screen, minimum: minimum, maximumWidth: 900)
        XCTAssertEqual(widthOnly.size, CGSize(width: 900, height: 675))
        let heightOnly = CompactWindowLayout.frame(in: screen, minimum: minimum, maximumHeight: 660)
        XCTAssertEqual(heightOnly.size, CGSize(width: 880, height: 660))
        let both = CompactWindowLayout.frame(in: screen, minimum: minimum, maximumWidth: 900, maximumHeight: 660)
        XCTAssertEqual(both.size, heightOnly.size)
    }

    func testLargeLimitsDoNotEnlargeAutomaticSizeAndZeroRestoresIt() {
        let screen = CGRect(x: 0, y: 0, width: 5120, height: 1440)
        for limits in [(0, 0), (2000, 2000), (-1, -1)] {
            let frame = CompactWindowLayout.frame(in: screen, minimum: minimum,
                                                 maximumWidth: limits.0, maximumHeight: limits.1)
            XCTAssertEqual(frame.size, CGSize(width: 1024, height: 768))
        }
    }

    func testCustomLimitsRespectNormalMinimumAndSmallScreens() {
        XCTAssertEqual(CompactWindowLayout.normalizedMaximumWidth(1), 800)
        XCTAssertEqual(CompactWindowLayout.normalizedMaximumHeight(1), 600)
        XCTAssertEqual(CompactWindowLayout.normalizedMaximumWidth(-1), 0)
        XCTAssertEqual(CompactWindowLayout.normalizedMaximumHeight(0), 0)
        let screen = CGRect(x: 0, y: 0, width: 640, height: 480)
        let frame = CompactWindowLayout.frame(in: screen, minimum: minimum, maximumWidth: 800, maximumHeight: 600)
        XCTAssertEqual(frame.size, screen.size)
    }
}
