import XCTest

// GridReorderPlan.swift is compiled into this target directly through an explicit
// entry in the test target's Sources build phase in project.pbxproj, so these cover the
// production algorithm rather than a copy of it. Migrated from the former
// scripts/diagnostics/GridReorderProbe.swift.
final class GridReorderPlanTests: XCTestCase {

    // MARK: - Helpers

    private func describe(_ occupied: [Bool], _ from: Int, _ to: Int, _ perPage: Int) -> String {
        "occupied=\(occupied.map { $0 ? "1" : "0" }.joined()) from=\(from) to=\(to) perPage=\(perPage)"
    }

    private func makePlan(_ occupied: [Bool], from: Int, to: Int, perPage: Int,
                          file: StaticString = #filePath, line: UInt = #line) throws -> GridReorderPlan {
        try XCTUnwrap(GridReorderPlan.make(occupied: occupied, from: from, to: to,
                                           itemsPerPage: perPage,
                                           cascading: from / perPage != to / perPage),
                      "expected a plan for \(describe(occupied, from, to, perPage))",
                      file: file, line: line)
    }

    /// Source indices of the items that were actually occupied, in final order.
    private func filledSources(_ plan: GridReorderPlan, _ occupied: [Bool]) -> [Int] {
        plan.slots.compactMap { $0 }.filter { occupied[$0] }
    }

    // MARK: - Compaction

    func testTrailingPlaceholdersCompactBeforeLandingTarget() throws {
        let occupied = [true, true, true, false, false, false]
        let plan = try makePlan(occupied, from: 0, to: 5, perPage: 6)
        XCTAssertEqual(filledSources(plan, occupied), [1, 2, 0],
                       "trailing placeholders must be compacted before the first landing target")
        XCTAssertEqual(plan.destinationIndex, 2,
                       "the landing target must be the compacted slot, not the requested index")
    }

    func testInteriorHolesDoNotCauseSecondMove() throws {
        let occupied = [false, true, false, true, true, false]
        let plan = try makePlan(occupied, from: 4, to: 2, perPage: 6)
        XCTAssertEqual(filledSources(plan, occupied), [1, 4, 3],
                       "holes before the requested slot must not cause a second move")
        XCTAssertEqual(plan.destinationIndex, 1)
    }

    // MARK: - Cascade

    func testForwardCascadeAcrossPages() throws {
        let occupied = [Bool](repeating: true, count: 6)
        let plan = try makePlan(occupied, from: 0, to: 4, perPage: 3)
        XCTAssertEqual(plan.slots, [1, 2, nil, 3, 0, 4, 5, nil, nil])
        XCTAssertEqual(plan.destinationIndex, 4)
    }

    func testBackwardCascadeWithinExistingPages() throws {
        let occupied = [Bool](repeating: true, count: 6)
        let plan = try makePlan(occupied, from: 5, to: 1, perPage: 3)
        XCTAssertEqual(plan.slots, [0, 5, 1, 2, 3, 4])
    }

    // MARK: - Page creation and removal

    func testMoveOntoNewTrailingPage() throws {
        let occupied = [Bool](repeating: true, count: 6)
        let plan = try makePlan(occupied, from: 1, to: 6, perPage: 3)
        XCTAssertEqual(plan.slots, [0, 2, nil, 3, 4, 5, 1, nil, nil])
        XCTAssertEqual(plan.destinationIndex, 6)
    }

    func testEmptiedSourcePageIsRemovedInTheSamePlan() throws {
        let occupied = [true, false, false, true, false, false]
        let plan = try makePlan(occupied, from: 0, to: 5, perPage: 3)
        XCTAssertEqual(plan.slots, [3, 0, 4],
                       "empty source page removal must be included in the landing prediction")
        XCTAssertEqual(plan.slots.count, 3, "the emptied page must not survive as padding")
        XCTAssertEqual(plan.destinationIndex, 1)
    }

    func testSingleItemGrid() throws {
        let plan = try makePlan([true], from: 0, to: 1, perPage: 1)
        XCTAssertEqual(plan.slots, [0])
        XCTAssertEqual(plan.destinationIndex, 0)
    }

    // MARK: - Rejected input

    func testRejectsUnoccupiedSource() {
        XCTAssertNil(GridReorderPlan.make(occupied: [false], from: 0, to: 0,
                                          itemsPerPage: 1, cascading: false),
                     "an empty source slot has nothing to move")
    }

    func testRejectsNonPositivePageSize() {
        XCTAssertNil(GridReorderPlan.make(occupied: [true], from: 0, to: 0,
                                          itemsPerPage: 0, cascading: false),
                     "itemsPerPage must be positive")
    }

    // MARK: - Exhaustive small grids

    // Every occupancy mask for 1...8 slots, every page size 1...4, every
    // occupied source and every target. Failures are collected rather than
    // asserted per case so the first offending inputs are reported together.
    func testExhaustiveSmallGridsPreserveMembershipOrderAndCompaction() {
        var failures: [String] = []
        var checked = 0
        let failureLimit = 10

        outer: for count in 1...8 {
            for mask in 1..<(1 << count) {
                let occupied = (0..<count).map { mask & (1 << $0) != 0 }
                let expected = (0..<count).filter { occupied[$0] }
                for perPage in 1...4 {
                    for from in 0..<count where occupied[from] {
                        for to in 0...count {
                            let cascading = from / perPage != to / perPage
                            guard let plan = GridReorderPlan.make(occupied: occupied, from: from, to: to,
                                                                  itemsPerPage: perPage,
                                                                  cascading: cascading) else {
                                failures.append("no plan: \(describe(occupied, from, to, perPage))")
                                if failures.count >= failureLimit { break outer }
                                continue
                            }
                            checked += 1
                            let context = describe(occupied, from, to, perPage)
                            let result = filledSources(plan, occupied)

                            if result.sorted() != expected {
                                failures.append("lost or duplicated an item (\(result) vs \(expected)): \(context)")
                            }
                            if result.filter({ $0 != from }) != expected.filter({ $0 != from }) {
                                failures.append("other items changed relative order (\(result)): \(context)")
                            }
                            if plan.slots.indices.contains(plan.destinationIndex) == false
                                || plan.slots[plan.destinationIndex] != from {
                                failures.append("destinationIndex \(plan.destinationIndex) does not hold the moved item: \(context)")
                            }

                            for start in stride(from: 0, to: plan.slots.count, by: perPage) {
                                let page = plan.slots[start..<min(start + perPage, plan.slots.count)]
                                var sawEmpty = false
                                for slot in page {
                                    if let slot, occupied[slot] {
                                        if sawEmpty {
                                            failures.append("a filled slot follows an empty one on page \(start / perPage): \(context)")
                                            break
                                        }
                                    } else {
                                        sawEmpty = true
                                    }
                                }
                                if cascading && !page.contains(where: { $0.map { occupied[$0] } ?? false }) {
                                    failures.append("a fully empty page survived at \(start / perPage): \(context)")
                                }
                            }

                            if failures.count >= failureLimit { break outer }
                        }
                    }
                }
            }
        }

        XCTAssertTrue(failures.isEmpty,
                      "\(failures.count) failing case(s):\n" + failures.joined(separator: "\n"))
        XCTAssertGreaterThan(checked, 30_000,
                             "the exhaustive sweep should cover tens of thousands of moves, got \(checked)")
    }
}
