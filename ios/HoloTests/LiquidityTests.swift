import XCTest
@testable import Holo

/// "Sells fast": the same inputs and expected scores as the website's src/lib/liquidity.test.ts.
final class LiquidityTests: XCTestCase {
    private let today = "2026-11-01"

    private func sale(_ price: Double, _ soldDate: String, grade: String? = nil, listPrice: Double? = nil) -> EbaySale {
        EbaySale(soldDate: soldDate, price: price, bestOffer: listPrice != nil, listPrice: listPrice, grade: grade, condition: nil, title: "", url: "")
    }

    private func stats(_ count: Int, _ lastSold: String?) -> EbayStats {
        EbayStats(median: nil, count: count, lastPrice: nil, lastSold: lastSold)
    }

    private func ebay(_ ungraded: EbayStats, _ sales: [EbaySale], graded: [String: EbayStats] = [:]) -> EbaySales {
        EbaySales(printing: nil, ungraded: ungraded, graded: graded, sales: sales, asOf: today)
    }

    /// 30 sold, ten sales within a few dollars of each other, the latest today.
    private func busy() -> EbaySales {
        let prices: [Double] = [100, 102, 98, 101, 99, 100, 103, 97, 100, 101]
        return ebay(stats(30, "2026-11-01"), prices.enumerated().map { i, p in sale(p, i == 0 ? "2026-11-01" : "2026-10-25") })
    }

    func testQuantilesInterpolate() {
        XCTAssertEqual(Liquidity.quantile([10, 20, 30, 40], 0.5), 25)
        XCTAssertEqual(Liquidity.quantile([10, 20, 30, 40], 0.25), 17.5)
        XCTAssertEqual(Liquidity.quantile([10, 20, 30, 40], 0.75), 32.5)
    }

    func testBusyTightCardSellsFast() {
        XCTAssertEqual(Liquidity.score(busy(), grade: nil, today: today), Liquidity.Score(score: 99, tier: .fast, sold: 30))
    }

    func testMediumCardSellsSteady() {
        let e = ebay(stats(6, "2026-10-22"), [
            sale(80, "2026-10-22"), sale(100, "2026-10-18"), sale(90, "2026-10-15"),
            sale(110, "2026-10-12"), sale(95, "2026-10-08", listPrice: 120), sale(105, "2026-10-04"),
        ])
        XCTAssertEqual(Liquidity.score(e, grade: nil, today: today), Liquidity.Score(score: 66, tier: .steady, sold: 6))
    }

    func testRareScatteredCardIsSlowToSell() {
        let e = ebay(stats(2, "2026-10-07"), [sale(40, "2026-10-07"), sale(90, "2026-10-03", listPrice: 120)])
        XCTAssertEqual(Liquidity.score(e, grade: nil, today: today), Liquidity.Score(score: 36, tier: .slow, sold: 2))
    }

    func testNotEnoughSalesGivesNothing() {
        XCTAssertNil(Liquidity.score(ebay(stats(1, "2026-10-30"), [sale(50, "2026-10-30")]), grade: nil, today: today))
        XCTAssertNil(Liquidity.score(ebay(stats(0, nil), []), grade: nil, today: today))
        XCTAssertNil(Liquidity.score(nil, grade: nil, today: today))
        // A grade that never sold.
        XCTAssertNil(Liquidity.score(busy(), grade: "PSA 10", today: today))
    }

    func testGradeUsesOnlyItsOwnStatsAndSales() {
        var e = busy()
        e.graded = ["PSA 10": stats(3, "2026-10-21")]
        e.sales += [
            sale(500, "2026-10-21", grade: "PSA 10"), sale(650, "2026-10-14", grade: "PSA 10"),
            sale(420, "2026-10-06", grade: "PSA 10"), sale(900, "2026-10-28", grade: "PSA 9"),
        ]
        XCTAssertEqual(Liquidity.score(e, grade: "PSA 10", today: today), Liquidity.Score(score: 55, tier: .steady, sold: 3))
        // Ungraded is unchanged by the slab sales.
        XCTAssertEqual(Liquidity.score(e, grade: nil, today: today)?.score, 99)
    }

    func testTalkingThePriceDownLowersTheScore() {
        var e = busy()
        // Half the sales were best offers well under the asking price; one was within 5% (doesn't count).
        e.sales = e.sales.enumerated().map { i, original in
            var c = original
            if i < 5 {
                c.bestOffer = true
                c.listPrice = c.price * 1.25
            } else if i == 5 {
                c.bestOffer = true
                c.listPrice = c.price * 1.02
            }
            return c
        }
        XCTAssertEqual(Liquidity.score(e, grade: nil, today: today), Liquidity.Score(score: 94, tier: .fast, sold: 30))
    }

    func testTiersSplitAt70And40() {
        XCTAssertEqual(Liquidity.tier(70), .fast)
        XCTAssertEqual(Liquidity.tier(69), .steady)
        XCTAssertEqual(Liquidity.tier(40), .steady)
        XCTAssertEqual(Liquidity.tier(39), .slow)
    }
}
