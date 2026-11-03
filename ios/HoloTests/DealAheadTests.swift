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

    // MARK: Parked deals and history (the same cases as src/lib/deal.test.ts)

    private func record(kind: DealKind, balance: Double, profit: Double? = nil, equity: Double = 0, ahead: Double? = nil, uncosted: Int? = nil, notes: String? = nil, names: [String] = []) -> DealRecord {
        let lines = names.map { name in
            DealRecord.Line(side: .incoming, product: DealRecord.Line.Item(id: name, name: name, imageUrl: nil, kind: "single", setName: nil, productType: nil), qty: 1, price: 1, untracked: nil)
        }
        return DealRecord(id: UUID().uuidString, at: "2026-11-02T15:00:00.000Z", kind: kind, inValue: 0, outValue: 0, balance: balance,
                          profit: profit, equity: equity, ahead: ahead, uncosted: uncosted, items: lines.count, lines: lines, photos: nil, notes: notes)
    }

    func testParkedDealNameIsTheTime() {
        var cal = Calendar(identifier: .gregorian)
        cal.timeZone = TimeZone(identifier: "UTC")!
        func at(_ h: Int, _ m: Int) -> Date { cal.date(from: DateComponents(year: 2026, month: 11, day: 2, hour: h, minute: m))! }
        XCTAssertEqual(ParkedDeal.defaultName(at: at(15, 42), calendar: cal), "Deal at 3:42 PM")
        XCTAssertEqual(ParkedDeal.defaultName(at: at(0, 5), calendar: cal), "Deal at 12:05 AM")
        XCTAssertEqual(ParkedDeal.defaultName(at: at(12, 0), calendar: cal), "Deal at 12:00 PM")
    }

    func testDayTotals() {
        let t = DealDayTotals([
            record(kind: .sell, balance: 120, profit: 40, ahead: 40, uncosted: 0),
            record(kind: .buy, balance: -70, equity: 30, ahead: 30, uncosted: 0),
            record(kind: .trade, balance: 25, profit: 10, equity: 5, ahead: nil, uncosted: 1),
        ])
        XCTAssertEqual(t.deals, 3)
        XCTAssertEqual(t.cashIn, 145)
        XCTAssertEqual(t.cashOut, 70)
        XCTAssertEqual(t.net, 75)
        XCTAssertEqual(t.ahead, 70)
        XCTAssertEqual(t.profit, 50)
        let unknown = DealDayTotals([record(kind: .trade, balance: 0, uncosted: 2)])
        XCTAssertNil(unknown.ahead)
        XCTAssertNil(unknown.profit)
    }

    func testHistorySearch() {
        let r = record(kind: .sell, balance: 0, notes: "Paid by Venmo", names: ["Charizard ex", "Umbreon VMAX"])
        XCTAssertTrue(r.matches(search: ""))
        XCTAssertTrue(r.matches(search: "charizard"))
        XCTAssertTrue(r.matches(search: "venmo"))
        XCTAssertTrue(r.matches(search: "sale umbreon"))
        XCTAssertFalse(r.matches(search: "trade"))
        XCTAssertFalse(r.matches(search: "pikachu"))
    }

    func testOldDealsDecodeWithoutNotes() throws {
        let json = #"{"in":[],"out":[],"rateIn":null,"rateOut":null}"#.data(using: .utf8)!
        let d = try JSONDecoder().decode(DealState.self, from: json)
        XCTAssertNil(d.notes)
        XCTAssertFalse(d.hasContent)
        var withNotes = d
        withNotes.notes = "Venmo"
        let round = try JSONDecoder().decode(DealState.self, from: JSONEncoder().encode(withNotes))
        XCTAssertEqual(round.notes, "Venmo")
        XCTAssertTrue(round.hasContent)
    }

    // MARK: Agreed cash (the same cases as src/lib/deal.test.ts)

    private func settle(_ incoming: [DealItem], _ outgoing: [DealItem], rates: (in: Double, out: Double), agreed: Double?) -> (AgreedDeal, DealTotals) {
        var d = DealState()
        d.incoming = incoming
        d.outgoing = outgoing
        d.agreedCash = agreed
        let a = d.agreed(rates: rates)
        return (a, totals(a.deal, rates: rates))
    }

    func testNothingAgreedLeavesTheDealAlone() {
        let (a, t) = settle([], [item("a", market: 100)], rates: (0.7, 1), agreed: nil)
        XCTAssertNil(a.side)
        XCTAssertNil(a.deal.outgoing[0].price)
        XCTAssertEqual(t.balance, 100)
        XCTAssertNil(settle([], [], rates: (0.7, 1), agreed: 50).0.side)
    }

    func testSaleSpreadsAcrossWhatGoesOut() {
        let (a, t) = settle([], [item("a", market: 100), item("b", market: 50)], rates: (0.7, 1), agreed: 120)
        XCTAssertEqual(a.side, .outgoing)
        XCTAssertEqual(a.deal.outgoing.map(\.price), [80, 40])
        XCTAssertEqual(t.balance, 120)
        XCTAssertEqual(a.share ?? 0, 0.8, accuracy: 0.0001)
    }

    func testBuyMovesWhatComesInExactToTheCent() {
        let (a, t) = settle([item("a", market: 100), item("b", market: 30)], [], rates: (0.7, 1), agreed: -100)
        XCTAssertEqual(a.side, .incoming)
        XCTAssertEqual(a.deal.incoming[0].price ?? 0, 76.93, accuracy: 0.000001)
        XCTAssertEqual(a.deal.incoming[1].price ?? 0, 23.07, accuracy: 0.000001)
        XCTAssertEqual(t.balance, -100)
        XCTAssertEqual(t.inValue, 100)
    }

    func testLeftoverCentGoesOnTheBiggestLine() {
        let (a, t) = settle([], [item("a", market: 10), item("b", market: 10), item("c", market: 10)], rates: (0.7, 1), agreed: 25)
        XCTAssertEqual(a.deal.outgoing[0].price ?? 0, 8.34, accuracy: 0.000001)
        XCTAssertEqual(a.deal.outgoing[1].price ?? 0, 8.33, accuracy: 0.000001)
        XCTAssertEqual(a.deal.outgoing[2].price ?? 0, 8.33, accuracy: 0.000001)
        XCTAssertEqual(t.balance, 25)
    }

    func testSeveralCopiesPricedPerUnit() {
        let (a, t) = settle([], [item("a", market: 10, qty: 3)], rates: (0.7, 1), agreed: 25)
        XCTAssertEqual((a.deal.outgoing[0].price ?? 0) * 3, 25, accuracy: 0.0000001)
        XCTAssertEqual(t.balance, 25)
    }

    func testNeverBelowZero() {
        let (a, t) = settle([item("a", market: 100)], [item("b", market: 50)], rates: (0.8, 1), agreed: -120)
        XCTAssertEqual(a.deal.outgoing[0].price, 0)
        XCTAssertEqual(t.balance, -80)
    }

    func testAheadMovesByTheCash() {
        let base = totals({ var d = DealState(); d.incoming = [item("a", market: 100)]; d.outgoing = [item("b", market: 100, cost: 60)]; return d }(), rates: (0.8, 1))
        let (_, t) = settle([item("a", market: 100)], [item("b", market: 100, cost: 60)], rates: (0.8, 1), agreed: 0)
        XCTAssertEqual(base.balance, 20)
        XCTAssertEqual(t.balance, 0)
        XCTAssertEqual(t.profit, 20)
        XCTAssertEqual(t.ahead, (base.ahead ?? 0) - 20)
        XCTAssertEqual(t.ahead, 100 - 60 + 0)
    }

    func testUnpricedLinesStayAsTheyAre() {
        let (a, _) = settle([], [item("a", market: nil), item("b", market: 40)], rates: (0.7, 1), agreed: 30)
        XCTAssertNil(a.deal.outgoing[0].price)
        XCTAssertEqual(a.deal.outgoing[1].price, 30)
        XCTAssertEqual(a.share ?? 0, 0.75, accuracy: 0.0001)
    }

    func testTypedAmountKeepsWhoPaysWhom() {
        func t(_ inV: Double, _ outV: Double) -> DealTotals {
            var d = DealState()
            if inV > 0 { d.incoming = [item("a", market: inV, price: inV)] }
            if outV > 0 { d.outgoing = [item("b", market: outV, price: outV)] }
            return totals(d, rates: (1, 1))
        }
        XCTAssertEqual(signedAgreedCash(50, totals: t(0, 42)), 50)
        XCTAssertEqual(signedAgreedCash(50, totals: t(42, 0)), -50)
        XCTAssertEqual(signedAgreedCash(50, totals: t(10, 10)), -50)
    }

    func testRenegotiating() {
        var base = DealState()
        base.incoming = [item("a", market: 10)]
        var r = base; r.rateIn = 0.75
        XCTAssertTrue(r.renegotiates(from: base))
        var q = base; q.incoming[0].qty = 2
        XCTAssertTrue(q.renegotiates(from: base))
        var p = base; p.incoming[0].price = 12
        XCTAssertTrue(p.renegotiates(from: base))
        var l = base; l.incoming[0].rate = 0.9
        XCTAssertTrue(l.renegotiates(from: base))
        var removed = base; removed.incoming = []
        XCTAssertTrue(removed.renegotiates(from: base))
        var added = base; added.outgoing = [item("b", market: 5)]
        XCTAssertTrue(added.renegotiates(from: base))
        // Notes, photos and tracking don't count.
        var n = base; n.notes = "Venmo"; n.incoming[0].track = false
        XCTAssertFalse(n.renegotiates(from: base))
    }

    func testAgreedCashRoundTripsAndOldDealsLoad() throws {
        let old = try JSONDecoder().decode(DealState.self, from: Data(#"{"in":[],"out":[],"rateIn":null,"rateOut":null}"#.utf8))
        XCTAssertNil(old.agreedCash)
        var d = DealState()
        d.agreedCash = -85
        let back = try JSONDecoder().decode(DealState.self, from: JSONEncoder().encode(d))
        XCTAssertEqual(back.agreedCash, -85)
        let web = try JSONDecoder().decode(DealState.self, from: Data(#"{"in":[],"out":[],"rateIn":null,"rateOut":null,"agreedCash":120}"#.utf8))
        XCTAssertEqual(web.agreedCash, 120)
    }
}
