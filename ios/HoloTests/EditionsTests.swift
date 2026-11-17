import XCTest
@testable import Holo

/// Old sets split by edition (the website's src/lib/editions.test.ts, kept in step).
final class EditionsTests: XCTestCase {
    func testOrderedPutsUnlimitedFirst() {
        XCTAssertEqual(Editions.ordered(["1st Edition Holofoil", "Unlimited Holofoil"]), ["Unlimited Holofoil", "1st Edition Holofoil"])
        XCTAssertEqual(Editions.ordered(["1st Edition", "Unlimited", "Reverse Holofoil"]), ["Unlimited", "Reverse Holofoil", "1st Edition"])
        XCTAssertEqual(Editions.ordered(["Normal", "Holofoil"]), ["Normal", "Holofoil"])
    }

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

    func testUnlimitedPhotosForUnlimitedCopiesOnly() {
        XCTAssertNotNil(Editions.unlimitedImage(setName: "Base Set", number: "4/102"))
        XCTAssertNil(Editions.unlimitedImage(setName: "Base Set", number: "8/102"))
        XCTAssertNotNil(Editions.unlimitedImage(setName: "Jungle", number: "60/64"))
        XCTAssertNotNil(Editions.unlimitedImage(setName: "Fossil", number: "15/62"))
        XCTAssertNotNil(Editions.unlimitedImage(setName: "Team Rocket", number: "83/82"))
        XCTAssertNotNil(Editions.unlimitedImage(setName: "Neo Destiny", number: "113/105"))
    }

    func testBaseSetFirstEditionUsesStampedScan() {
        XCTAssertEqual(Editions.firstEditionImage(setName: "Base Set", number: "4/102"), "https://images.pokemontcg.io/base1/4_hires.png")
        XCTAssertNil(Editions.firstEditionImage(setName: "Jungle", number: "60/64"))
    }
}
