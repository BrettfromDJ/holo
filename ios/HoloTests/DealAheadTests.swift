import XCTest
@testable import Holo

/// How far ahead a deal leaves you, the same cases as the web app's (src/lib/deal.test.ts).
final class DealAheadTests: XCTestCase {
    private let card = Product(id: "p1", name: "Card", kind: "single")

    private func item(_ key: String, market: Double?, qty: Int = 1, price: Double? = nil, cost: Double? = nil) -> DealItem {
        DealItem(key: key, product: card, printing: nil, market: market, qty: qty, price: price, cost: cost)
    }

    /// Costs as the store gives them: per row, what you paid × quantity (nil when unknown).
    private func totals(_ deal: DealState, rates: (in: Double, out: Double)) -> DealTotals {
        DealTotals(deal, rates: rates, cost: { i in i.cost.map { round2($0 * Double(i.qty)) } })
    }

    func testAheadIsProfitPlusValueGained() {
        // In: $1,000 market credited at 80% ($800). Out: a $1,000 card that cost $600.
        var deal = DealState()
        deal.incoming = [item("a", market: 1000)]
        deal.outgoing = [item("b", market: 1000, cost: 600)]
        let t = totals(deal, rates: (0.8, 1))
        XCTAssertEqual(t.profit, 400)
        XCTAssertEqual(t.equity, 200)
        XCTAssertEqual(t.ahead, 600)
        // Market in − cost out + cash received.
        XCTAssertEqual(t.ahead, 1000 - 600 + t.balance)
    }

    func testAheadDoesNotDependOnHowPricesWereSplit() {
        var a = DealState()
        a.incoming = [item("a", market: 1000)]
        a.outgoing = [item("b", market: 1000, cost: 600)]
        var b = DealState()
        // Same cash, both sides marked up by $150.
        b.incoming = [item("a", market: 1000, price: 950)]
        b.outgoing = [item("b", market: 1000, price: 1150, cost: 600)]
        let ta = totals(a, rates: (0.8, 1))
        let tb = totals(b, rates: (0.8, 1))
        XCTAssertEqual(tb.balance, ta.balance)
        XCTAssertEqual(tb.ahead, ta.ahead)
    }

    func testPureBuyIsValueGainedAndPureSellIsProfit() {
        var buy = DealState()
        buy.incoming = [item("a", market: 50, qty: 3)]
        let tb = totals(buy, rates: (0.7, 1))
        XCTAssertEqual(tb.ahead, tb.equity)
        XCTAssertEqual(tb.ahead, 45)

        var sell = DealState()
        // The web test gives the line's cost ($100 for both); here it's per unit, as DealItem.cost is.
        sell.outgoing = [item("b", market: 100, qty: 2, price: 40, cost: 50)]
        let ts = totals(sell, rates: (0.7, 1))
        XCTAssertEqual(ts.ahead, ts.profit)
        XCTAssertEqual(ts.ahead, -20)
    }

    func testUnknownWhileAnythingGoingOutHasNoCost() {
        var deal = DealState()
        deal.incoming = [item("a", market: 200)]
        deal.outgoing = [item("b", market: 250, cost: 180), item("c", market: 30)]
        let t = totals(deal, rates: (0.8, 1))
        XCTAssertEqual(t.uncosted, 1)
        XCTAssertNil(t.ahead)
        XCTAssertNil(totals(DealState(), rates: (0.7, 1)).ahead)
    }

    func testHeadline() {
        XCTAssertEqual(dealAheadTitle(58), "You come out ahead")
        XCTAssertEqual(dealAheadTitle(-20, past: true), "You came out behind")
        XCTAssertEqual(dealAheadTitle(0, past: true), "You broke even")
    }

    private func record(_ kind: DealKind, profit: Double?, equity: Double, ahead: Double? = nil, uncosted: Int? = nil) -> DealRecord {
        DealRecord(id: "r", at: "2026-11-01T12:00:00.000Z", kind: kind, inValue: 0, outValue: 0, balance: 0,
                   profit: profit, equity: equity, ahead: ahead, uncosted: uncosted, items: 1, lines: nil)
    }

    func testRecordAhead() {
        XCTAssertEqual(record(.trade, profit: 971, equity: 730, ahead: 1701, uncosted: 0).aheadTotal, 1701)
        // Recorded as unknown stays unknown, even with a partial profit.
        XCTAssertNil(record(.trade, profit: 70, equity: 40, ahead: nil, uncosted: 1).aheadTotal)
        // Old records: profit + value gained; a buy is all value gained.
        XCTAssertEqual(record(.trade, profit: 971, equity: 730).aheadTotal, 1701)
        XCTAssertEqual(record(.buy, profit: nil, equity: 45).aheadTotal, 45)
        XCTAssertEqual(record(.sell, profit: -20, equity: 0).aheadTotal, -20)
        XCTAssertNil(record(.trade, profit: nil, equity: 40).aheadTotal)
    }

    func testRecordJSONMatchesTheWebsite() throws {
        // A record closed on the website: ahead written as null when unknown.
        let json = #"{"id":"r","at":"2026-11-01T12:00:00.000Z","kind":"trade","inValue":800,"outValue":500,"balance":-300,"profit":null,"equity":200,"ahead":null,"uncosted":1,"items":2}"#
        let r = try JSONDecoder().decode(DealRecord.self, from: Data(json.utf8))
        XCTAssertNil(r.ahead)
        XCTAssertEqual(r.uncosted, 1)
        XCTAssertNil(r.aheadTotal)
    }
}
