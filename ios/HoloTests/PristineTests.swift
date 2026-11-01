import XCTest
@testable import Holo

/// CGC Pristine 10 and Gem Mint 10: the same inputs and expected outputs as the website's
/// src/lib/pristine.test.ts.
final class PristineTests: XCTestCase {
    private let asOf = "2026-10-30"
    private let today = "2026-11-01"

    private func sale(_ price: Double, _ soldDate: String, _ title: String, grade: String? = "CGC 10") -> EbaySale {
        EbaySale(soldDate: soldDate, price: price, bestOffer: false, listPrice: nil, grade: grade, condition: nil, title: title, url: "")
    }

    private func stats(_ median: Double?, _ count: Int, _ lastPrice: Double?, _ lastSold: String?) -> EbayStats {
        EbayStats(median: median, count: count, lastPrice: lastPrice, lastSold: lastSold)
    }

    /// Five CGC 10s this month (two say pristine), an older Pristine, and a PSA 10 whose title happens to say pristine.
    private func ebay(_ sales: [EbaySale]? = nil) -> EbaySales {
        EbaySales(
            printing: nil,
            ungraded: stats(100, 8, 100, asOf),
            graded: ["CGC 10": stats(1000, 5, 1500, "2026-10-28"), "PSA 10": stats(2000, 1, 2000, "2026-10-26")],
            sales: sales ?? [
                sale(1500, "2026-10-28", "Charizard CGC Pristine 10"),
                sale(2000, "2026-10-26", "Charizard PSA 10 pristine condition", grade: "PSA 10"),
                sale(900, "2026-10-25", "Charizard CGC 10 Gem Mint"),
                sale(1700, "2026-10-20", "CHARIZARD cgc PRISTINE 10 gold label"),
                sale(1000, "2026-10-18", "Charizard CGC 10"),
                sale(950, "2026-10-10", "CGC Gem Mint 10 Charizard"),
                sale(1400, "2026-09-15", "Charizard CGC pristine 10"),
            ],
            asOf: asOf
        )
    }

    private let pc = GradedValues(ungraded: 100, grades: ["CGC 10": 800], updatedAt: "2026-10-30")

    func testTellsThemApartByTitle() {
        XCTAssertEqual(Pristine.pristinePremium, 1.6)
        XCTAssertTrue(Pristine.isPristineTitle("Charizard CGC Pristine 10"))
        XCTAssertTrue(Pristine.isPristineTitle("CHARIZARD cgc PRISTINE 10"))
        XCTAssertFalse(Pristine.isPristineTitle("Charizard CGC 10 Gem Mint"))
        XCTAssertTrue(Pristine.isCGCTen(company: "cgc", grade: "10"))
        XCTAssertFalse(Pristine.isCGCTen(company: "CGC", grade: "9.5"))
        XCTAssertFalse(Pristine.isCGCTen(company: "PSA", grade: "10"))
        XCTAssertEqual(Pristine.label(company: "CGC", grade: "10", pristine: true), Pristine.pristineLabel)
        XCTAssertEqual(Pristine.label(company: "CGC", grade: "10", pristine: false), Pristine.gemMintLabel)
        XCTAssertEqual(Pristine.label(company: "PSA", grade: "10", pristine: true), "PSA 10")
    }

    func testSplitsCGCTenSales() {
        XCTAssertEqual(Pristine.stats(ebay(), label: Pristine.pristineLabel), stats(1600, 2, 1500, "2026-10-28"))
        XCTAssertEqual(Pristine.stats(ebay(), label: Pristine.gemMintLabel), stats(950, 3, 900, "2026-10-25"))
        XCTAssertEqual(Pristine.stats(ebay(), label: "CGC 10"), stats(1000, 5, 1500, "2026-10-28"))
        XCTAssertEqual(Pristine.stats(ebay(), label: "PSA 10")?.median, 2000)
        XCTAssertEqual(Pristine.sales(ebay(), label: Pristine.pristineLabel).map(\.price), [1500, 1700, 1400])
        XCTAssertEqual(Pristine.sales(ebay(), label: Pristine.gemMintLabel).map(\.price), [900, 1000, 950])
    }

    func testGemMintKeepsEbayFiguresWithoutPristineListings() {
        let e = ebay([sale(900, "2026-10-25", "Charizard CGC 10"), sale(1000, "2026-10-18", "Charizard CGC 10 Gem Mint")])
        XCTAssertEqual(Pristine.stats(e, label: Pristine.gemMintLabel), stats(1000, 5, 1500, "2026-10-28"))
        XCTAssertNil(Pristine.stats(e, label: Pristine.pristineLabel))
        let old = ebay([sale(900, "2026-10-25", "Charizard CGC 10"), sale(1400, "2026-09-15", "Charizard CGC pristine 10")])
        XCTAssertEqual(Pristine.stats(old, label: Pristine.pristineLabel), stats(nil, 0, 1400, "2026-09-15"))
        XCTAssertEqual(Pristine.stats(old, label: Pristine.gemMintLabel), stats(900, 1, 900, "2026-10-25"))
    }

    func testValuesACGCTenSlab() {
        let gem = Pristine.stats(ebay(), label: Pristine.gemMintLabel)
        let pri = Pristine.stats(ebay(), label: Pristine.pristineLabel)
        XCTAssertEqual(Pristine.cgcTenValue(gem: gem, pristineStats: pri, guide: 800, pristine: false)?.value, 950)
        XCTAssertEqual(Pristine.cgcTenValue(gem: gem, pristineStats: pri, guide: 800, pristine: true)?.value, 1600)
        let onePri = stats(1500, 1, 1500, "2026-10-28")
        XCTAssertEqual(Pristine.cgcTenValue(gem: gem, pristineStats: onePri, guide: 800, pristine: true)?.value, 1520)
        let oneGem = stats(900, 1, 900, "2026-10-25")
        XCTAssertEqual(Pristine.cgcTenValue(gem: oneGem, pristineStats: onePri, guide: 800, pristine: false)?.value, 800)
        XCTAssertEqual(Pristine.cgcTenValue(gem: oneGem, pristineStats: onePri, guide: 800, pristine: true)?.value, 1280)
        XCTAssertEqual(Pristine.cgcTenValue(gem: oneGem, pristineStats: nil, guide: nil, pristine: false)?.value, 900)
        XCTAssertEqual(Pristine.cgcTenValue(gem: oneGem, pristineStats: nil, guide: nil, pristine: true)?.value, 1440)
        XCTAssertEqual(Pristine.cgcTenValue(gem: nil, pristineStats: stats(nil, 0, 1400, "2026-09-15"), guide: nil, pristine: true)?.value, 1400)
        XCTAssertNil(Pristine.cgcTenValue(gem: nil, pristineStats: nil, guide: nil, pristine: true))
        XCTAssertNil(Pristine.cgcTenValue(gem: nil, pristineStats: nil, guide: nil, pristine: false))
    }

    func testSlabPriceForTheCollection() {
        let summary = ebay().graded["CGC 10"]
        XCTAssertEqual(Pristine.slabPrice(company: "CGC", grade: "10", pristine: true, summary: summary, sales: ebay(), guide: 800), 1600)
        XCTAssertEqual(Pristine.slabPrice(company: "CGC", grade: "10", pristine: false, summary: summary, sales: ebay(), guide: 800), 950)
        // Listings didn't load: eBay's CGC 10 figures stand for the Gem Mint, and the Pristine is × 1.6.
        XCTAssertEqual(Pristine.slabPrice(company: "CGC", grade: "10", pristine: false, summary: summary, sales: nil, guide: 800), 1000)
        XCTAssertEqual(Pristine.slabPrice(company: "CGC", grade: "10", pristine: true, summary: summary, sales: nil, guide: 800), 1600)
        // Other grades keep the old rule: 3 sales for the median, else the guide.
        XCTAssertEqual(Pristine.slabPrice(company: "PSA", grade: "10", pristine: false, summary: stats(600, 2, 610, nil), sales: nil, guide: 700), 700)
        XCTAssertEqual(Pristine.slabPrice(company: "PSA", grade: "10", pristine: false, summary: stats(600, 3, 610, nil), sales: nil, guide: 700), 600)
    }

    func testGradedPricesRowsAndLookup() {
        func price(_ e: EbaySales?, _ values: GradedValues?, _ nm: Double?, pristine: Bool = false) -> Double? {
            GradedPricesPanel.price(company: "CGC", grade: "10", values: values, ebay: e, nm: nm, productId: "p", pristine: pristine)?.value
        }
        XCTAssertEqual(price(ebay(), pc, 100), 950)
        XCTAssertEqual(price(ebay(), pc, 100, pristine: true), 1600)
        let one = ebay([sale(1500, "2026-10-28", "Charizard CGC Pristine 10"), sale(900, "2026-10-25", "CGC 10"), sale(1000, "2026-10-18", "CGC 10")])
        XCTAssertEqual(price(one, pc, 100), 950)
        XCTAssertEqual(price(one, pc, 100, pristine: true), 1520)
        if case .premium? = GradedPricesPanel.price(company: "CGC", grade: "10", values: pc, ebay: one, nm: 100, productId: "p", pristine: true)?.source {} else {
            XCTFail("a Pristine from too few sales is an estimate")
        }
        XCTAssertEqual(price(nil, pc, 100), 800)
        XCTAssertEqual(price(nil, pc, 100, pristine: true), 1280)
        let curve = (100 * WorthCalc.multiple(productId: "p", company: "CGC", grade: "10") * 100).rounded() / 100
        XCTAssertEqual(price(nil, nil, 100), curve)
        XCTAssertEqual(price(nil, nil, 100, pristine: true), (curve * 1.6 * 100).rounded() / 100)
        XCTAssertNil(price(nil, nil, nil, pristine: true))
        XCTAssertEqual(GradedPricesPanel.lookupGrades("CGC"), ["Pristine 10", "10", "9.5", "9", "8.5", "8", "7.5", "7", "6", "5"])
        XCTAssertEqual(GradedPricesPanel.lookupGrades("PSA"), ["10", "9", "8", "7", "6", "5"])
        XCTAssertEqual(GradedPricesPanel.gradeTitle(company: "CGC", grade: "10"), "Gem Mint 10")
    }

    func testSellsFastOnOneKind() {
        XCTAssertEqual(Liquidity.score(ebay(), grade: "CGC 10", today: today, pristine: true), Liquidity.Score(score: 60, tier: .steady, sold: 2))
        XCTAssertEqual(Liquidity.score(ebay(), grade: "CGC 10", today: today, pristine: false), Liquidity.Score(score: 64, tier: .steady, sold: 3))
        XCTAssertEqual(Liquidity.score(ebay(), grade: Pristine.pristineLabel, today: today), Liquidity.score(ebay(), grade: "CGC 10", today: today, pristine: true))
        // Without it, every CGC 10 sale, as before.
        XCTAssertEqual(Liquidity.score(ebay(), grade: "CGC 10", today: today), Liquidity.Score(score: 56, tier: .steady, sold: 5))
        let one = ebay([sale(1500, "2026-10-28", "Charizard CGC Pristine 10"), sale(900, "2026-10-25", "CGC 10")])
        XCTAssertNil(Liquidity.score(one, grade: "CGC 10", today: today, pristine: true))
    }
}
