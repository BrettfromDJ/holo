import XCTest
@testable import Holo

/// The same cases as src/lib/lists.test.ts.
final class ListPricingTests: XCTestCase {
    func testOwnPriceFirstThenPercentOfMarket() {
        let meta = ListMeta(forSale: true, askPercent: 90, prices: ["a": 50])
        XCTAssertEqual(ListPricing.asking(meta, productId: "a", market: 100), 50)
        XCTAssertEqual(ListPricing.asking(meta, productId: "b", market: 100), 90)
        XCTAssertEqual(ListPricing.asking(meta, productId: "b", market: 33.33), 30)
        XCTAssertNil(ListPricing.asking(meta, productId: "b", market: nil))
        XCTAssertEqual(ListPricing.asking(nil, productId: "b", market: 12.34), 12.34)
    }

    func testCardPercentBeatsListPercent() {
        let meta = ListMeta(forSale: true, askPercent: 90, prices: ["a": 50], percents: ["a": 70, "c": 80])
        XCTAssertEqual(ListPricing.asking(meta, productId: "a", market: 100), 50)
        XCTAssertEqual(ListPricing.asking(meta, productId: "c", market: 100), 80)
        XCTAssertEqual(ListPricing.asking(meta, productId: "d", market: 100), 90)
    }

    func testShareTitle() {
        XCTAssertEqual(ListPricing.shareTitle("abc"), "list:abc")
    }
}
