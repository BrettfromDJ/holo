import XCTest
@testable import Holo

/// The same cases as the web app's ledger tests, so both compute identical numbers.
final class LedgerTests: XCTestCase {
    private let card = HoldingIdentity(productId: "p1", printing: nil, condition: "Near Mint", gradeCompany: nil, grade: nil)

    private func tx(_ id: String, _ kind: Txn.Kind, _ date: String, _ qty: Double, _ price: Double, fees: Double = 0, corrects: String? = nil, at: String = "2026-01-01T00:00:00Z") -> Txn {
        Txn(id: id, identity: card, kind: kind, date: date, quantity: qty, unitPrice: price, fees: fees, correctsId: corrects, createdAt: at)
    }

    func testSalesConsumeOldestLotsFirst() {
        let ledger = Ledger([
            tx("a", .purchase, "2026-01-01", 2, 10),
            tx("b", .purchase, "2026-01-05", 1, 16),
            tx("c", .sale, "2026-02-01", 2, 20),
        ])
        let p = ledger.positions[card.key]!
        XCTAssertEqual(p.quantity, 1)
        XCTAssertEqual(p.costBasis, 16, accuracy: 0.0001)
        XCTAssertEqual(p.realizedGain, 20, accuracy: 0.0001) // 40 proceeds − 20 cost
    }

    func testFeesAreAddedToCost() {
        let p = Ledger([tx("a", .purchase, "2026-01-01", 2, 10, fees: 4)]).positions[card.key]!
        XCTAssertEqual(p.costBasis, 24, accuracy: 0.0001)
    }

    func testCorrectionsReplaceOrVoid() {
        let fixed = Ledger([
            tx("a", .purchase, "2026-01-01", 1, 10),
            tx("fix", .correction, "2026-01-01", 1, 12, corrects: "a", at: "2026-01-02T00:00:00Z"),
        ]).positions[card.key]!
        XCTAssertEqual(fixed.costBasis, 12, accuracy: 0.0001)

        let voided = Ledger([
            tx("a", .purchase, "2026-01-01", 1, 10),
            tx("void", .correction, "2026-01-01", 0, 0, corrects: "a", at: "2026-01-02T00:00:00Z"),
        ]).positions[card.key]
        XCTAssertEqual(voided?.quantity ?? 0, 0)
    }

    func testPlayedCopiesAreEstimatedFromNearMint() {
        let lp = HoldingIdentity(productId: "p1", printing: nil, condition: "Lightly Played", gradeCompany: nil, grade: nil)
        let txns = [Txn(id: "a", identity: lp, kind: .purchase, date: "2026-01-01", quantity: 1, unitPrice: 50, createdAt: "2026-01-01T00:00:00Z")]
        let prices = [priceKey("p1", nil): Price(productId: "p1", printing: nil, market: 100, status: "live")]
        let h = Portfolio.holdings(transactions: txns, products: [:], prices: prices, manualValues: [:]).first!
        XCTAssertEqual(h.price ?? 0, 85, accuracy: 0.0001)
        XCTAssertTrue(h.isConditionEstimate)
    }
}

/// Deal math matches the web app's (src/lib/deal.test.ts).
final class DealTests: XCTestCase {
    private let card = Product(id: "p1", name: "Card", kind: "single")

    func testRatesAndBalance() {
        var deal = DealState()
        deal.incoming = [DealItem(key: "a", product: card, printing: nil, market: 100)]
        deal.outgoing = [DealItem(key: "b", product: card, printing: nil, market: 50, holdingKey: "h")]
        let rates = deal.rates(DealRates())
        XCTAssertEqual(rates.in, 0.8) // a trade uses the trade-in rate
        let t = DealTotals(deal, rates: rates, cost: { _ in 20 })
        XCTAssertEqual(t.inValue, 80)
        XCTAssertEqual(t.outValue, 50)
        XCTAssertEqual(t.balance, -30)
        XCTAssertEqual(t.profit, 30)
        XCTAssertEqual(t.equity, 20)
    }

    func testTypedPriceWinsAndUnknownMarketIsUnpriced() {
        var item = DealItem(key: "a", product: card, printing: nil, market: nil)
        XCTAssertNil(item.unitPrice(side: 0.7))
        item.price = 12
        XCTAssertEqual(item.unitPrice(side: 0.7), 12)
    }

    func testDealJSONMatchesTheWebsite() throws {
        var deal = DealState()
        deal.incoming = [DealItem(key: "a", product: card, printing: nil, market: nil)]
        let json = String(data: try JSONEncoder().encode(deal), encoding: .utf8)!
        XCTAssertTrue(json.contains("\"in\""))
        XCTAssertTrue(json.contains("\"market\":null"))
        let back = try JSONDecoder().decode(DealState.self, from: Data(json.utf8))
        XCTAssertEqual(back.incoming.count, 1)
    }
}

/// Gain attribution matches the web app's (src/lib/finance/attribution.ts).
final class GainsTests: XCTestCase {
    private func id(_ p: String) -> HoldingIdentity { HoldingIdentity(productId: p, printing: nil, condition: "Near Mint", gradeCompany: nil, grade: nil) }

    func testStepsSumToTotalGainsFirst() {
        let txns = [
            Txn(id: "a", identity: id("up"), kind: .purchase, date: "2026-01-01", quantity: 1, unitPrice: 10, createdAt: "2026-01-01T00:00:00Z"),
            Txn(id: "b", identity: id("down"), kind: .purchase, date: "2026-01-01", quantity: 1, unitPrice: 50, createdAt: "2026-01-01T00:00:00Z"),
            Txn(id: "c", identity: id("sold"), kind: .purchase, date: "2026-01-01", quantity: 1, unitPrice: 5, createdAt: "2026-01-01T00:00:00Z"),
            Txn(id: "d", identity: id("sold"), kind: .sale, date: "2026-02-01", quantity: 1, unitPrice: 25, createdAt: "2026-02-01T00:00:00Z"),
        ]
        let prices = [priceKey("up", nil): Price(productId: "up", printing: nil, market: 40, status: "live"),
                      priceKey("down", nil): Price(productId: "down", printing: nil, market: 30, status: "live")]
        let products = ["up": Product(id: "up", name: "Up", kind: "single"), "down": Product(id: "down", name: "Down", kind: "single"), "sold": Product(id: "sold", name: "Sold", kind: "single")]
        let holdings = Portfolio.holdings(transactions: txns, products: products, prices: prices, manualValues: [:])

        let un = Gains.attribute(holdings: holdings, transactions: txns, products: products, mode: .unrealized, group: .product)
        XCTAssertEqual(un.steps.map(\.key), ["up", "down"])
        XCTAssertEqual(un.total, 10, accuracy: 0.0001) // +30 − 20
        XCTAssertEqual(un.steps.last!.end, un.total, accuracy: 0.0001)

        let all = Gains.attribute(holdings: holdings, transactions: txns, products: products, mode: .all, group: .product)
        XCTAssertEqual(all.total, 30, accuracy: 0.0001) // + 20 realized
        XCTAssertEqual(all.winners, 2)
        XCTAssertEqual(all.losers, 1)
    }
}

final class TreemapTests: XCTestCase {
    func testTilesFillTheAreaInProportion() {
        let rects = Treemap.squarify([6, 6, 4, 3, 2, 2, 1], in: CGRect(x: 0, y: 0, width: 600, height: 400))
        XCTAssertEqual(rects.count, 7)
        let area = rects.reduce(0) { $0 + $1.width * $1.height }
        XCTAssertEqual(Double(area), 240_000, accuracy: 1)
        XCTAssertEqual(Double(rects[0].width * rects[0].height), 240_000 * 6 / 24, accuracy: 1)
        for r in rects { XCTAssertTrue(CGRect(x: 0, y: 0, width: 600, height: 400).insetBy(dx: -0.5, dy: -0.5).contains(r)) }
    }
}
