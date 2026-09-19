import LaunchNextWallpaperCore
import XCTest

final class WallpaperCacheBudgetTests: XCTestCase {
    func testThreeSharpDisplaysFitAndFourthEvictsLeastRecentlyUsed() {
        let costs: [UInt32: Int] = [1: 16_000_000, 2: 16_000_000, 3: 16_000_000, 4: 16_000_000]
        XCTAssertEqual(WallpaperCacheBudget.retainedDisplays(mostRecentFirst: [2, 1],
            bytesByDisplay: costs, currentDisplay: 2, unfiltered: true), [1, 2])
        XCTAssertEqual(WallpaperCacheBudget.retainedDisplays(mostRecentFirst: [3, 2, 1],
            bytesByDisplay: costs, currentDisplay: 3, unfiltered: true), [1, 2, 3])
        XCTAssertEqual(WallpaperCacheBudget.retainedDisplays(mostRecentFirst: [1, 3, 2],
            bytesByDisplay: costs, currentDisplay: 1, unfiltered: true), [1, 2, 3])
        XCTAssertEqual(WallpaperCacheBudget.retainedDisplays(mostRecentFirst: [4, 1, 3, 2],
            bytesByDisplay: costs, currentDisplay: 4, unfiltered: true), [1, 3, 4])
    }

    func testActualBytesCanEvictSecondDisplayBeforeCountLimit() {
        XCTAssertEqual(WallpaperCacheBudget.retainedDisplays(mostRecentFirst: [1, 2],
            bytesByDisplay: [1: 36_000_000, 2: 16_000_000], currentDisplay: 1, unfiltered: true), [1])
    }

    func testOversizedCurrentImageIsPreservedWithoutOtherFrames() {
        XCTAssertEqual(WallpaperCacheBudget.retainedDisplays(mostRecentFirst: [2, 1],
            bytesByDisplay: [1: 60_000_000, 2: 2_000_000], currentDisplay: 1, unfiltered: true), [1])
    }

    func testMaterialModeKeepsEightSmallFrames() {
        let ids = Array(UInt32(1)...UInt32(9))
        let costs = Dictionary(uniqueKeysWithValues: ids.map { ($0, 2_000_000) })
        XCTAssertEqual(WallpaperCacheBudget.retainedDisplays(mostRecentFirst: ids,
            bytesByDisplay: costs, currentDisplay: 1, unfiltered: false), Set(ids.prefix(8)))
    }

    func testMissingDisplaysAndDuplicateVisitsDoNotConsumeBudget() {
        XCTAssertEqual(WallpaperCacheBudget.retainedDisplays(mostRecentFirst: [1, 1, 2, 3],
            bytesByDisplay: [1: 16_000_000, 3: 16_000_000], currentDisplay: 1, unfiltered: true), [1, 3])
    }
}
