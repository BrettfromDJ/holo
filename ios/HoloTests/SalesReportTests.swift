import XCTest
@testable import Holo

/// The sales report must agree with the ledger's realized gains and split sales by purchase date.
final class SalesReportTests: XCTestCase {
    private let card = HoldingIdentity(productId: "p1", printing: nil, condition: "Near Mint", gradeCompany: nil, grade: nil)

    private func tx(_ id: String, _ kind: Txn.Kind, _ date: String, _ qty: Double, _ price: Double, fees: Double = 0, shipping: Double = 0) -> Txn {
        Txn(id: id, identity: card, kind: kind, date: date, quantity: qty, unitPrice: price, fees: fees, shipping: shipping, createdAt: "\(date)T00:00:00Z")
    }

    func testSaleSplitsAcrossPurchaseDatesOldestFirst() {
        let lines = SalesReport.lines([
            tx("a", .purchase, "2024-01-10", 1, 10),
            tx("b", .purchase, "2025-03-01", 1, 30),
            tx("s", .sale, "2025-06-01", 2, 50, fees: 10),
        ])
        XCTAssertEqual(lines.count, 2)
        let old = lines.first { $0.acquired == "2024-01-10" }!
        let new = lines.first { $0.acquired == "2025-03-01" }!
        XCTAssertEqual(old.proceeds, 45, accuracy: 0.0001) // (100 − 10) / 2
        XCTAssertEqual(old.cost, 10, accuracy: 0.0001)
        XCTAssertTrue(old.longTerm)
        XCTAssertEqual(new.cost, 30, accuracy: 0.0001)
        XCTAssertFalse(new.longTerm)
        let t = SalesReport.totals(lines)
        XCTAssertEqual(t.sales, 1)
        XCTAssertEqual(t.gain, 50, accuracy: 0.0001)
        XCTAssertEqual(t.longTermGain, 35, accuracy: 0.0001)
        XCTAssertEqual(t.shortTermGain, 15, accuracy: 0.0001)
    }

    func testTotalsMatchTheLedger() {
        let log = [
            tx("a", .purchase, "2025-01-01", 3, 20, shipping: 6),
            tx("w", .adjustment, "2025-02-01", -1, 0),
            tx("s1", .sale, "2025-05-01", 1, 40, fees: 4),
            tx("b", .purchase, "2025-06-01", 2, 25),
            tx("s2", .sale, "2026-01-02", 2, 31),
        ]
        let report = SalesReport.totals(SalesReport.lines(log)).gain
        // The ledger also counts the write-off as a loss; the report lists only sales.
        let ledger = Ledger(log).positions[card.key]!.realized.filter { $0.transactionId.hasPrefix("s") }.reduce(0) { $0 + $1.gain }
        XCTAssertEqual(report, ledger, accuracy: 0.0001)
    }

    func testOneYearIsShortTerm() {
        XCTAssertFalse(SalesReport.heldOverAYear(from: "2025-03-01", to: "2026-03-01"))
        XCTAssertTrue(SalesReport.heldOverAYear(from: "2025-03-01", to: "2026-03-02"))
    }

    func testCSVQuotesNames() {
        let lines = SalesReport.lines([tx("a", .purchase, "2025-01-01", 1, 10), tx("s", .sale, "2025-02-01", 1, 12)])
        let p = Product(id: "p1", source: "sample", name: "Box, \"sealed\"", productType: "Booster Box", kind: "sealed")
        let csv = SalesReport.csv(lines, products: ["p1": p])
        XCTAssertTrue(csv.contains("\"Box, \"\"sealed\"\"\""))
        XCTAssertTrue(csv.contains(",2025-01-01,2025-02-01,12.00,10.00,2.00,Short"))
    }
}
