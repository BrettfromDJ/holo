import Foundation
import Observation
import Supabase

/// Your collection, loaded from Supabase into the same shape the web app uses,
/// and the writes that change it (adding purchases).
@Observable
final class CollectionStore {
    enum Status: Equatable { case idle, loading, ready, failed(String) }

    var status: Status = .idle
    var products: [String: Product] = [:]
    var prices: [String: Price] = [:]
    var history: [String: [PricePoint]] = [:]
    var holdings: [HoldingView] = []
    var summary = PortfolioSummary()

    private var transactions: [Txn] = []
    private var holdingRows: [HoldingRow] = []
    private var manualValues: [String: Double] = [:]
    private var userId: String?

    private var db: SupabaseClient { Backend.shared.supabase }

    func reset() {
        status = .idle
        products = [:]
        prices = [:]
        history = [:]
        holdings = []
        summary = PortfolioSummary()
        transactions = []
        holdingRows = []
        manualValues = [:]
        userId = nil
    }

    // MARK: Loading

    /// Supabase returns at most 1,000 rows per request; page through larger sets.
    private func all<T: Decodable>(_ page: (Int, Int) async throws -> [T]) async throws -> [T] {
        var out: [T] = []
        var from = 0
        while true {
            let rows = try await page(from, from + 999)
            out.append(contentsOf: rows)
            if rows.count < 1000 { break }
            from += 1000
        }
        return out
    }

    @MainActor
    func load(userId: String) async {
        self.userId = userId
        if status != .ready { status = .loading }
        do {
            let holdingRows: [HoldingRow] = try await all { a, b in
                try await self.db.from("holdings").select().range(from: a, to: b).execute().value
            }
            let txRows: [TransactionRow] = try await all { a, b in
                try await self.db.from("transactions").select().order("created_at").range(from: a, to: b).execute().value
            }

            let byId = Dictionary(holdingRows.map { ($0.id, $0) }, uniquingKeysWith: { a, _ in a })
            let txns: [Txn] = txRows.compactMap { r in
                guard let h = byId[r.holding_id], let kind = Txn.Kind(rawValue: r.type) else { return nil }
                return Txn(
                    id: r.id, identity: h.identity, kind: kind, date: r.trade_date, quantity: r.quantity, unitPrice: r.unit_price,
                    fees: r.fees, shipping: r.shipping, tax: r.tax, correctsId: r.corrects_id, createdAt: r.created_at
                )
            }
            var manual: [String: Double] = [:]
            for h in holdingRows {
                if let v = h.manual_value, h.manual_value_date != nil { manual[h.identity.key] = v }
            }

            // Catalog rows for everything you hold, 200 ids at a time.
            let ids = Array(Set(holdingRows.map(\.product_id)))
            var products: [String: Product] = [:]
            var prices: [String: Price] = [:]
            var history: [String: [PricePoint]] = [:]
            for start in stride(from: 0, to: ids.count, by: 200) {
                let chunk = Array(ids[start..<min(start + 200, ids.count)])
                let productRows: [ProductRow] = try await all { a, b in
                    try await self.db.from("products").select().in("id", values: chunk).range(from: a, to: b).execute().value
                }
                let priceRows: [PriceRow] = try await all { a, b in
                    try await self.db.from("product_prices").select().in("product_id", values: chunk).range(from: a, to: b).execute().value
                }
                let snapRows: [SnapshotRow] = try await all { a, b in
                    try await self.db.from("price_snapshots").select("product_id,printing,snapshot_date,market_price")
                        .in("product_id", values: chunk).order("snapshot_date").range(from: a, to: b).execute().value
                }
                for p in productRows { products[p.id] = p.product }
                for p in priceRows { prices[priceKey(p.product_id, p.printing.isEmpty ? nil : p.printing)] = p.price }
                for s in snapRows {
                    history[priceKey(s.product_id, s.printing.isEmpty ? nil : s.printing), default: []].append(PricePoint(date: s.snapshot_date, price: s.market_price))
                }
            }

            self.holdingRows = holdingRows
            self.transactions = txns
            self.manualValues = manual
            self.products = products
            self.prices = prices
            self.history = history
            recompute()
            status = .ready
        } catch {
            status = .failed(error.localizedDescription)
        }
    }

    private func recompute() {
        holdings = Portfolio.holdings(transactions: transactions, products: products, prices: prices, manualValues: manualValues)
        let realized = Ledger(transactions).positions.values.reduce(0) { $0 + $1.realizedGain }
        summary = Portfolio.summary(holdings, realized: realized)
    }

    /// Copies you hold of one product.
    func holdings(for productId: String) -> [HoldingView] {
        holdings.filter { $0.identity.productId == productId }
    }

    /// The Near Mint market price for a product, from the catalog.
    func marketPrice(_ productId: String, printing: String?) -> Price? {
        prices[priceKey(productId, printing)]
    }

    // MARK: Writing

    struct Purchase {
        var product: Product
        var printing: String?
        var condition: String
        var gradeCompany: String?
        var grade: String?
        var quantity: Double
        var unitPrice: Double
        var date: String
        var source: String? = "ios"
    }

    /// Add a purchase: save the product to the catalog, find or create the holding, then log the transaction.
    @MainActor
    func add(_ purchases: [Purchase]) async throws {
        guard let userId else { throw HoloError.signedOut }
        var imported = Set<String>()
        for p in purchases {
            if !imported.contains(p.product.id) {
                let res = try await Backend.shared.api.importProduct(p.product, printing: p.printing)
                products[res.product.id] = res.product
                for price in res.prices { prices[priceKey(price.productId, price.printing)] = price }
                imported.insert(p.product.id)
            }
            let identity = HoldingIdentity(productId: p.product.id, printing: p.printing, condition: p.condition, gradeCompany: p.gradeCompany, grade: p.grade)
            let holding = try await holdingRow(for: identity, userId: userId)
            let row = NewTransactionRow(
                user_id: userId, holding_id: holding.id, type: "purchase", trade_date: p.date, quantity: p.quantity,
                unit_price: p.unitPrice, fees: 0, shipping: 0, tax: 0, source: p.source, notes: nil
            )
            let saved: TransactionRow = try await db.from("transactions").insert(row).select().single().execute().value
            transactions.append(Txn(
                id: saved.id, identity: identity, kind: .purchase, date: saved.trade_date, quantity: saved.quantity,
                unitPrice: saved.unit_price, createdAt: saved.created_at
            ))
        }
        recompute()
    }

    private func holdingRow(for identity: HoldingIdentity, userId: String) async throws -> HoldingRow {
        if let existing = holdingRows.first(where: { $0.identity.key == identity.key }) { return existing }
        let new = NewHoldingRow(
            user_id: userId, product_id: identity.productId, printing: identity.printing, condition: identity.condition,
            grade_company: identity.gradeCompany, grade: identity.grade
        )
        let row: HoldingRow = try await db.from("holdings").insert(new).select().single().execute().value
        holdingRows.append(row)
        return row
    }
}
