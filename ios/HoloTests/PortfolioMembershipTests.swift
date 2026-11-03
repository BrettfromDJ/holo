import XCTest
@testable import Holo

/// Move, Copy and who's in which portfolio: the same cases as the website's
/// src/lib/portfolios.test.ts.
final class PortfolioMembershipTests: XCTestCase {
    private typealias M = PortfolioMembership

    private func base() -> M.State {
        M.State(portfolios: [M.Group(id: "resale", keys: ["b"]), M.Group(id: "kids", keys: ["c"])], main: [])
    }

    func testHoldingsInNoPortfolioAreInMain() {
        let m = base()
        XCTAssertEqual(M.members(m, "a"), ["main"])
        XCTAssertEqual(M.members(m, "b"), ["resale"])
        XCTAssertTrue(M.isIn(m, "a", "main"))
        XCTAssertFalse(M.isIn(m, "b", "main"))
        XCTAssertTrue(M.isIn(m, "b", "all"))
    }

    func testCopyFromMainKeepsItInMain() {
        let c = M.copy(base(), ["a"], to: "resale")
        XCTAssertEqual(c.next.portfolios[0].keys, ["b", "a"])
        XCTAssertEqual(c.next.main, ["a"])
        XCTAssertEqual(c.changed, ["resale"])
        XCTAssertEqual(c.mainAdd, ["a"])
        XCTAssertEqual(M.members(c.next, "a"), ["main", "resale"])
    }

    func testCopyBetweenNamedPortfolios() {
        let c = M.copy(base(), ["b"], to: "kids")
        XCTAssertEqual(M.members(c.next, "b"), ["resale", "kids"])
        XCTAssertEqual(c.next.main, [])
    }

    func testCopyToMain() {
        let c = M.copy(base(), ["b"], to: "main")
        XCTAssertEqual(c.next.main, ["b"])
        XCTAssertEqual(M.members(c.next, "b"), ["main", "resale"])
        // Already in Main: nothing to write.
        let again = M.copy(c.next, ["a"], to: "main")
        XCTAssertEqual(again.changed, [])
        XCTAssertEqual(again.mainAdd, [])
    }

    func testMoveLeavesItOnlyThere() {
        let copied = M.copy(M.copy(base(), ["b"], to: "kids").next, ["b"], to: "main").next
        XCTAssertEqual(M.members(copied, "b"), ["main", "resale", "kids"])
        let c = M.move(copied, ["b"], to: "kids")
        XCTAssertEqual(M.members(c.next, "b"), ["kids"])
        XCTAssertEqual(c.changed, ["resale"])
        XCTAssertEqual(c.mainRemove, ["b"])
    }

    func testMoveToMain() {
        let copied = M.copy(base(), ["a"], to: "resale").next
        let c = M.move(copied, ["a", "c"], to: "main")
        XCTAssertEqual(c.next.portfolios.map(\.keys), [["b"], []])
        XCTAssertEqual(c.next.main, [])
        XCTAssertEqual(M.members(c.next, "a"), ["main"])
        XCTAssertEqual(M.members(c.next, "c"), ["main"])
    }

    func testFilters() {
        let m = M.copy(base(), ["a"], to: "resale").next
        let keys = ["a", "b", "c", "d"]
        XCTAssertNil(M.filter(m, selected: "all"))
        XCTAssertEqual(keys.filter(M.filter(m, selected: "main")!), ["a", "d"])
        XCTAssertEqual(keys.filter(M.filter(m, selected: "resale")!), ["a", "b"])
        XCTAssertEqual(keys.filter(M.filter(m, selected: "kids")!), ["c"])
        XCTAssertEqual(keys.filter(M.filter(m, selected: "gone")!), [])
    }

    func testMergesMainListChanges() {
        XCTAssertEqual(M.applyMainChange(["x", "a"], add: ["a", "b"], remove: ["x"]), ["a", "b"])
    }
}
