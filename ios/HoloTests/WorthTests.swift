import XCTest
@testable import Holo

/// What a raw copy is worth by condition (the website's src/lib/worth.test.ts, kept in step).
final class WorthTests: XCTestCase {
    func testPSATenStaysAboveOtherCompaniesTens() {
        for id in ["p1", "p2", "sv-rayquaza", "base-charizard", "x9"] {
            func at(_ c: String) -> Double { WorthCalc.multiple(productId: id, company: c, grade: "10") }
            XCTAssertGreaterThan(at("PSA"), at("BGS"))
            XCTAssertGreaterThan(at("BGS"), at("CGC"))
            XCTAssertGreaterThan(at("CGC"), at("SGC"))
        }
    }

    func testNearMintIsMarketAndOthersAreEstimates() {
        XCTAssertEqual(WorthCalc.raw(nm: 100, condition: .nearMint, ebay: nil, conditions: [], printing: nil).price, 100)
        let lp = WorthCalc.raw(nm: 100, condition: .lightlyPlayed, ebay: nil, conditions: [], printing: nil)
        XCTAssertEqual(lp.price, 85)
        XCTAssertEqual(lp.source, .estimate)
        XCTAssertEqual(lp.detail, "Estimated at 85% of Near Mint")
    }

    func testUsesTCGplayerConditionPriceFirst() {
        let rows = [ConditionPrice(printing: "Holofoil", condition: "Lightly Played", price: 91.5, basis: "median", samples: 6)]
        let lp = WorthCalc.raw(nm: 100, condition: .lightlyPlayed, ebay: nil, conditions: rows, printing: "Holofoil")
        XCTAssertEqual(lp.price, 91.5)
        XCTAssertEqual(lp.source, .market)
        XCTAssertEqual(lp.detail, "TCGplayer Lightly Played listings · median of 6")
    }

    func testNeverPricesAPlayedCopyAboveNearMint() {
        // Asks on an older card sit above what Near Mint copies sell for: the share estimate wins.
        let rows = [ConditionPrice(printing: "Holofoil", condition: "Lightly Played", price: 209.98, basis: "median", samples: 7)]
        let lp = WorthCalc.raw(nm: 127.47, condition: .lightlyPlayed, ebay: nil, conditions: rows, printing: "Holofoil")
        XCTAssertEqual(lp.price, 108.35)
        XCTAssertEqual(lp.source, .estimate)
        XCTAssertEqual(lp.detail, "Estimated at 85% of Near Mint · listings ran above Near Mint")
    }
}
