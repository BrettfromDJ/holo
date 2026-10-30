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
