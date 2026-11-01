import XCTest
@testable import Holo

/// Milestone banners: one at most, never a repeat, never one at or below a level already seen.
final class MilestoneTests: XCTestCase {
    private func m(_ id: String, rank: Int) -> Milestones.Milestone {
        Milestones.Milestone(id: id, title: id, detail: nil, rank: rank)
    }

    func testLevelSplitsAtTheLastColon() {
        XCTAssertEqual(Milestones.level("value:10000")?.kind, "value")
        XCTAssertEqual(Milestones.level("value:10000")?.step, 10_000)
        XCTAssertEqual(Milestones.level("gain:tcgapi:1|Holofoil|Near Mint:2")?.kind, "gain:tcgapi:1|Holofoil|Near Mint")
        XCTAssertNil(Milestones.level("nonsense"))
    }

    func testNothingNewShowsNothing() {
        let r = Milestones.pick([m("value:10000", rank: 5)], seen: ["value:10000"])
        XCTAssertNil(r.show)
        XCTAssertTrue(r.record.isEmpty)
    }

    func testShowsTheHighestNewOne() {
        let r = Milestones.pick([m("value:5000", rank: 4), m("value:10000", rank: 5), m("items:50", rank: 2)], seen: [])
        XCTAssertEqual(r.show?.id, "value:10000")
        XCTAssertEqual(Set(r.record), ["value:5000", "value:10000", "items:50"])
    }

    func testNeverShowsALevelBelowOneAlreadySeen() {
        // $10k was celebrated (maybe on the website); passing $5k is recorded but not shown.
        let r = Milestones.pick([m("value:5000", rank: 4)], seen: ["value:10000"])
        XCTAssertNil(r.show)
        XCTAssertEqual(r.record, ["value:5000"])
    }
}
