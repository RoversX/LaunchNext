import XCTest

// AppSortOrder.swift is compiled into this target directly through an explicit
// entry in the test target's Sources build phase in project.pbxproj, so these cover
// the production ordering rather than a copy of it.
final class AppSortOrderTests: XCTestCase {

    private enum Item: Equatable {
        case app(String, used: TimeInterval?)
        case folder(String, appsUsed: [TimeInterval?])
        case missing(String)
        case empty

        var label: String {
            switch self {
            case .app(let name, _), .folder(let name, _), .missing(let name): return name
            case .empty: return "_"
            }
        }
    }

    private func rank(_ item: Item) -> AppSortRank {
        switch item {
        case .app(let name, let used):
            return AppSortOrder.rank(name: name, lastUses: [used.map(Date.init(timeIntervalSince1970:))])
        case .folder(let name, let appsUsed):
            return AppSortOrder.rank(name: name, lastUses: appsUsed.map { $0.map(Date.init(timeIntervalSince1970:)) })
        case .missing:
            return .trailing
        case .empty:
            return .omitted
        }
    }

    private func sortedLabels(_ items: [Item]) -> [String] {
        AppSortOrder.sorted(items, rank: rank).map(\.label)
    }

    func testMostRecentlyUsedComesFirst() {
        XCTAssertEqual(sortedLabels([.app("A", used: 100), .app("B", used: 300), .app("C", used: 200)]),
                       ["B", "C", "A"])
    }

    func testNeverUsedAppsFollowUsedAppsAlphabetically() {
        XCTAssertEqual(sortedLabels([.app("zeta", used: nil), .app("Old", used: 1), .app("alpha", used: nil)]),
                       ["Old", "alpha", "zeta"])
    }

    func testEqualDatesFallBackToName() {
        XCTAssertEqual(sortedLabels([.app("Beta", used: 5), .app("alpha", used: 5)]), ["alpha", "Beta"])
    }

    func testFolderRanksByItsNewestApp() {
        let items: [Item] = [.app("Mail", used: 200), .folder("Tools", appsUsed: [nil, 500, 50]), .app("Notes", used: 300)]
        XCTAssertEqual(sortedLabels(items), ["Tools", "Notes", "Mail"])
    }

    func testFolderWithNoUsedAppsIsUnused() {
        XCTAssertEqual(sortedLabels([.folder("Games", appsUsed: [nil, nil]), .app("Maps", used: 1)]),
                       ["Maps", "Games"])
    }

    func testEmptySlotsAreDroppedAndMissingAppsGoLastInOriginalOrder() {
        let items: [Item] = [.missing("Gone2"), .empty, .app("A", used: nil), .empty, .missing("Gone1"), .app("B", used: 9)]
        XCTAssertEqual(sortedLabels(items), ["B", "A", "Gone2", "Gone1"])
    }

    func testRankingEverythingUnusedGivesPlainAlphabeticalOrder() {
        let items: [Item] = [.app("zeta", used: nil), .empty, .folder("Games", appsUsed: [nil]), .missing("Gone"), .app("Alpha", used: nil)]
        XCTAssertEqual(sortedLabels(items), ["Alpha", "Games", "zeta", "Gone"])
    }

    func testUsageKeyNormalisesEquivalentPaths() {
        XCTAssertEqual(AppSortOrder.usageKey(for: URL(fileURLWithPath: "/Applications/./Utilities/../Safari.app")),
                       AppSortOrder.usageKey(for: URL(fileURLWithPath: "/Applications/Safari.app")))
    }
}
