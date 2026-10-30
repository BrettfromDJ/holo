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
