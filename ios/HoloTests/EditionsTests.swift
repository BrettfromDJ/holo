import XCTest
@testable import Holo

/// Old sets split by edition (the website's src/lib/editions.test.ts, kept in step).
final class EditionsTests: XCTestCase {
    func testKnowsTheOldSets() {
        XCTAssertTrue(Editions.isEditionSet("Base Set"))
        XCTAssertTrue(Editions.isEditionSet("Neo Destiny"))
        XCTAssertFalse(Editions.isEditionSet("Base Set 2"))
        XCTAssertFalse(Editions.isEditionSet("Base Set (Shadowless)"))
    }

    func testNamesAndSlugs() {
        XCTAssertEqual(Editions.name("Base Set", .firstEdition), "Base Set 1st Edition")
        XCTAssertEqual(Editions.name("Jungle", .unlimited), "Jungle Unlimited")
        XCTAssertEqual(Editions.slug("base-set", .unlimited), "base-set--unlimited")
        XCTAssertEqual(Editions.of(printing: "1st Edition Holofoil"), .firstEdition)
        XCTAssertEqual(Editions.of(printing: "Unlimited Holofoil"), .unlimited)
        XCTAssertEqual(Editions.of(printing: nil), .unlimited)
    }
}
