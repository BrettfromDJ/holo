import XCTest
@testable import Holo

/// Same cases as src/lib/sealed-art.test.ts.
final class SealedArtTests: XCTestCase {
    private func s(_ name: String, _ set: String?, single: Bool = false) -> String? {
        SealedArt.path(name: name, setName: set, single: single)
    }

    func testMatchesSealedProductsByName() {
        XCTAssertEqual(s("Delta Reign Elite Trainer Box", "ME03: Delta Reign"), "/products/pokemon/delta-reign/delta-reign-elite-trainer-box.webp")
        XCTAssertEqual(s("Delta Reign Build & Battle Box", "Delta Reign"), "/products/pokemon/delta-reign/delta-reign-build-and-battle-box.webp")
        XCTAssertEqual(s("Brilliant Stars Booster Box", "SWSH09: Brilliant Stars"), "/products/pokemon/brilliant-stars/brilliant-stars-booster-box.webp")
        XCTAssertEqual(s("Arceus V Figure Collection", "SWSH09: Brilliant Stars"), "/products/pokemon/brilliant-stars/arceus-v-figure-collection.webp")
    }

    func testPrefersTheLongestListedName() {
        XCTAssertEqual(s("Delta Reign Elite Trainer Box Case", "Delta Reign"), "/products/pokemon/delta-reign/delta-reign-elite-trainer-box-case.webp")
        XCTAssertEqual(s("Surging Sparks Booster Box Case", "SV08: Surging Sparks"), "/products/pokemon/surging-sparks/surging-sparks-booster-box-case.webp")
    }

    func testMatchesWithoutBracketedNotes() {
        XCTAssertEqual(s("Surging Sparks Booster Bundle", "SV08: Surging Sparks"), "/products/pokemon/surging-sparks/surging-sparks-booster-bundle-retail.webp")
    }

    func testPicksTheSetNamedLast() {
        XCTAssertEqual(s("Mega Evolution: Delta Reign Booster Box", "Mega Evolution—Delta Reign"), "/products/pokemon/delta-reign/delta-reign-booster-box.webp")
        XCTAssertEqual(s("Mega Evolution Booster Box", "ME01: Mega Evolution"), "/products/pokemon/mega-evolution/mega-evolution-booster-box.webp")
        XCTAssertEqual(s("Scarlet & Violet 151 Booster Bundle", "SV: Scarlet & Violet 151"), "/products/pokemon/151/151-booster-bundle.webp")
        XCTAssertEqual(s("Scarlet & Violet Booster Box", "SV01: Scarlet & Violet Base Set"), "/products/pokemon/scarlet-and-violet-base-set/scarlet-and-violet-booster-box.webp")
    }

    func testLeavesSinglesAndOtherSetsAlone() {
        XCTAssertNil(s("Rayquaza ex", "Delta Reign", single: true))
        XCTAssertNil(s("Base Set Booster Box", "Base Set"))
    }
}
