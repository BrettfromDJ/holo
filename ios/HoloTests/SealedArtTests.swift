import XCTest
@testable import Holo

/// Same cases as src/lib/sealed-art.test.ts.
final class SealedArtTests: XCTestCase {
    private func path(_ name: String, _ set: String?, single: Bool = false) -> String? {
        SealedArt.path(name: name, setName: set, single: single)
    }

    func testMatchesSealedProductsByName() {
        XCTAssertEqual(path("Delta Reign Elite Trainer Box", "ME03: Delta Reign"), "/products/pokemon/delta-reign/elite-trainer-box.webp")
        XCTAssertEqual(path("Delta Reign Booster Pack", "Delta Reign"), "/products/pokemon/delta-reign/booster-pack.webp")
        XCTAssertEqual(path("Delta Reign Build & Battle Box", "Delta Reign"), "/products/pokemon/delta-reign/build-and-battle-box.webp")
        XCTAssertEqual(path("Delta Reign 3 Pack Blister [Seel]", "Delta Reign"), "/products/pokemon/delta-reign/3-pack-blister-seel.webp")
    }

    func testPrefersTheLongestListedName() {
        XCTAssertEqual(path("Delta Reign Elite Trainer Box Case", "Delta Reign"), "/products/pokemon/delta-reign/elite-trainer-box-case.webp")
        XCTAssertEqual(path("Mega Evolution: Delta Reign Pokemon Center Elite Trainer Box", "Delta Reign"), "/products/pokemon/delta-reign/pokemon-center-elite-trainer-box-exclusive.webp")
        XCTAssertEqual(path("Delta Reign Sleeved Booster Pack Art Bundle", "Delta Reign"), "/products/pokemon/delta-reign/sleeved-booster-pack-art-bundle-set-of-4.webp")
    }

    func testLeavesSinglesAndOtherSetsAlone() {
        XCTAssertNil(path("Rayquaza ex", "Delta Reign", single: true))
        XCTAssertNil(path("Surging Sparks Booster Box", "Surging Sparks"))
    }
}
