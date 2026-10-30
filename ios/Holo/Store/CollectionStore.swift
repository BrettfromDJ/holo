import Foundation
import Observation
import Supabase

/// Your collection, watchlist and wishlist, loaded from Supabase into the same shape
/// the web app uses, and every write that changes them.
@Observable
final class CollectionStore {
    enum Status: Equatable { case idle, loading, ready, failed(String) }

    var status: Status = .idle
    var products: [String: Product] = [:]
    var prices: [String: Price] = [:]
    var history: [String: [PricePoint]] = [:]
    var holdings: [HoldingView] = []
    var summary = PortfolioSummary()
    var timeline: [TimelinePoint] = []
    var watchlist: [WatchRow] = []
    var wishlist: [WishItem] = []
    /// Slugs of sets you want a reminder for (shared with the website's "release-reminders").
    var reminders: Set<String> = []
    /// Slab prices from recent eBay sales, by holding key.
    var ebayGraded: [String: Double] = [:]
    /// Your monthly spending budget (user_preferences.monthly_budget, shared with the website).
    var monthlyBudget: Double?

    /// The full log, corrections included.
    private(set) var transactions: [Txn] = []
    private var holdingRows: [HoldingRow] = []
    private var manualValues: [String: ManualValue] = [:]
    private(set) var userId: String?

    private var db: SupabaseClient { Backend.shared.supabase }
    private var today: String { Format.day() }

    func reset() {
        status = .idle
        products = [:]
        prices = [:]
        history = [:]
        holdings = []
        summary = PortfolioSummary()
        timeline = []
        watchlist = []
        wishlist = []
        reminders = []
        ebayGraded = [:]
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
            let watchRows: [WatchRow] = try await all { a, b in
                try await self.db.from("watchlist_items").select().order("created_at").range(from: a, to: b).execute().value
            }

            let byId = Dictionary(holdingRows.map { ($0.id, $0) }, uniquingKeysWith: { a, _ in a })
            let txns: [Txn] = txRows.compactMap { r in
                guard let h = byId[r.holding_id] else { return nil }
                return Self.txn(r, identity: h.identity)
            }
            var manual: [String: ManualValue] = [:]
            for h in holdingRows {
                if let v = h.manual_value, let d = h.manual_value_date { manual[h.identity.key] = ManualValue(value: v, date: d) }
            }

            // Catalog rows for everything you hold or watch, 200 ids at a time.
            let ids = Array(Set(holdingRows.map(\.product_id) + watchRows.map(\.product_id)))
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
            // A missing wishlist is just empty; don't fail the whole load over it.
            let wishes = (try? await UserState.load("wishlist", as: [WishItem].self)) ?? nil

            self.holdingRows = holdingRows
            self.transactions = txns
            self.manualValues = manual
            self.products = products
            self.prices = prices
            self.history = history
            self.watchlist = watchRows
            self.wishlist = wishes ?? []
            self.reminders = Set(((try? await UserState.load("release-reminders", as: [String].self)) ?? nil) ?? [])
            // An older database without the budget column just means no budget.
            struct PrefRow: Decodable { var monthly_budget: Double? }
            let prefs: [PrefRow]? = try? await db.from("user_preferences").select("monthly_budget").execute().value
            self.monthlyBudget = prefs?.first?.monthly_budget
            recompute()
            status = .ready
            await loadSlabPrices()
        } catch {
            status = .failed(error.localizedDescription)
        }
    }

    private static func txn(_ r: TransactionRow, identity: HoldingIdentity) -> Txn? {
        guard let kind = Txn.Kind(rawValue: r.type) else { return nil }
        return Txn(
            id: r.id, identity: identity, kind: kind, date: r.trade_date, quantity: r.quantity, unitPrice: r.unit_price,
            fees: r.fees, shipping: r.shipping, tax: r.tax, correctsId: r.corrects_id, createdAt: r.created_at,
            source: r.source, notes: r.notes
        )
    }

    private func recompute() {
        holdings = Portfolio.holdings(transactions: transactions, products: products, prices: prices, manualValues: manualValues, ebayGraded: ebayGraded)
        let realized = Ledger(transactions).positions.values.reduce(0) { $0 + $1.realizedGain }
        summary = Portfolio.summary(holdings, realized: realized)
        timeline = Timeline.compute(transactions: transactions, prices: prices, history: history, manualValues: manualValues, ebayGraded: ebayGraded, today: today)
    }

    /// Price your slabs from recent eBay sales for their exact grade: one request for all of them.
    @MainActor
    private func loadSlabPrices() async {
        let graded = holdings.filter { $0.identity.isGraded && $0.identity.productId.hasPrefix("tcgapi:") }
        guard !graded.isEmpty, let summaries = try? await Backend.shared.api.ebaySummaries(Array(Set(graded.map(\.identity.productId)))) else { return }
        var found: [String: Double] = [:]
        for h in graded {
            let s = summaryFor(summaries[h.identity.productId], printing: h.identity.printing)
            if let label = h.identity.gradeLabel, let stats = s?.graded[label], let price = stats.median ?? stats.lastPrice {
                found[h.identity.key] = price
            }
        }
        guard !found.isEmpty else { return }
        ebayGraded = found
        recompute()
    }

    /// Bring a catalog product (one you don't own) in for its page: details, prices and history.
    @MainActor
    func showCatalogProduct(_ id: String) async {
        guard products[id] == nil, let res = try? await Backend.shared.api.catalogProduct(id) else { return }
        products[id] = res.product
        for p in res.prices { prices[priceKey(p.productId, p.printing)] = p }
        for (key, pts) in res.history where history[key] == nil { history[key] = pts }
    }

    /// Keep a search result's product and price so its page opens instantly, even if it isn't stored yet.
    func seed(_ hit: SearchHit) {
        if products[hit.product.id] == nil { products[hit.product.id] = hit.product }
        let key = priceKey(hit.product.id, hit.printing)
        if prices[key] == nil, let market = hit.market {
            prices[key] = Price(productId: hit.product.id, printing: hit.printing, market: market, status: "live")
        }
    }

    /// One position's value per unit over the last `days` days (for sparklines).
    func series(_ identity: HoldingIdentity, days: Int = 90) -> [TimelinePoint] {
        let today = Format.day()
        let start = Format.day(Calendar.current.date(byAdding: .day, value: -days, to: Date()) ?? Date())
        return Timeline.days(from: start, to: today).compactMap { day in
            Timeline.price(identity, on: day, today: today, prices: prices, history: history, manual: manualValues, ebay: ebayGraded)
                .map { TimelinePoint(date: day, value: $0, cost: 0) }
        }
    }

    /// Recent purchases, newest first, with what they're worth now.
    struct RecentPurchase: Identifiable {
        var entry: Txn
        var product: Product?
        var value: Double?
        var id: String { entry.id }
        var cost: Double { entry.acquisitionCost }
        var change: Double? { value.map { cost > 0 ? ($0 - cost) / cost : 0 } }
    }

    func recentPurchases(_ limit: Int = 6) -> [RecentPurchase] {
        let unit = Dictionary(holdings.map { ($0.identity.key, $0.price) }, uniquingKeysWith: { a, _ in a })
        return Ledger.effective(transactions)
            .filter { $0.kind == .purchase }
            .sorted { $0.date != $1.date ? $0.date > $1.date : $0.createdAt > $1.createdAt }
            .prefix(limit)
            .map { t in
                let price = unit[t.identity.key] ?? nil
                return RecentPurchase(entry: t, product: products[t.identity.productId], value: price.map { $0 * t.quantity })
            }
    }

    /// The newest price refresh across everything you hold.
    var pricesRefreshedAt: Date? {
        let f = ISO8601DateFormatter()
        f.formatOptions = [.withInternetDateTime, .withFractionalSeconds]
        let plain = ISO8601DateFormatter()
        return prices.values.compactMap { $0.updatedAt }.compactMap { f.date(from: $0) ?? plain.date(from: $0) }.max()
    }

    /// Sets (or with nil, removes) the monthly budget, like the website.
    func setMonthlyBudget(_ value: Double?) async throws {
        guard let userId else { return }
        struct Row: Encodable {
            var user_id: String
            var monthly_budget: Double?
            enum CodingKeys: String, CodingKey { case user_id, monthly_budget }
            // Write null explicitly so removing the budget clears it.
            func encode(to encoder: Encoder) throws {
                var c = encoder.container(keyedBy: CodingKeys.self)
                try c.encode(user_id, forKey: .user_id)
                try c.encode(monthly_budget, forKey: .monthly_budget)
            }
        }
        try await db.from("user_preferences").upsert(Row(user_id: userId, monthly_budget: value)).execute()
        monthlyBudget = value
    }

    /// What you spent on purchases this calendar month.
    var spentThisMonth: Double {
        let month = String(Format.day().prefix(7))
        return Ledger.effective(transactions).filter { $0.kind == .purchase && $0.date.hasPrefix(month) }.reduce(0) { $0 + $1.acquisitionCost }
    }

    // MARK: Writing: release reminders

    @MainActor
    func setReminder(_ set: ExploreSet, on: Bool) async throws {
        guard let userId else { throw HoloError.signedOut }
        var next = reminders
        if on { next.insert(set.slug) } else { next.remove(set.slug) }
        try await UserState.save("release-reminders", Array(next).sorted(), userId: userId)
        reminders = next
        if on { await Notifications.scheduleRelease(set) } else { Notifications.cancelRelease(set.slug) }
    }

    // MARK: Reading

    /// Copies you hold of one product.
    func holdings(for productId: String) -> [HoldingView] {
        holdings.filter { $0.identity.productId == productId }
    }

    func holding(_ identity: HoldingIdentity) -> HoldingView? {
        holdings.first { $0.identity.key == identity.key }
    }

    /// The Near Mint market price for a product, from the catalog.
    func marketPrice(_ productId: String, printing: String?) -> Price? {
        prices[priceKey(productId, printing)]
    }

    /// One position's entries as they count now (edits applied, deleted ones gone), newest first.
    func entries(for identity: HoldingIdentity) -> [Txn] {
        Array(Ledger.effective(transactions).filter { $0.identity.key == identity.key }.reversed())
    }

    func manualValue(_ identity: HoldingIdentity) -> ManualValue? { manualValues[identity.key] }

    /// Whether an entry has been corrected since it was first recorded.
    func wasEdited(_ t: Txn) -> Bool { transactions.contains { $0.kind == .correction && $0.correctsId == t.id } }

    func watch(for productId: String) -> WatchRow? { watchlist.first { $0.product_id == productId } }
    func wish(for productId: String) -> WishItem? { wishlist.first { $0.product.id == productId } }

    // MARK: Writing: purchases and sales

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
        var notes: String?
    }

    /// Save products to the shared catalog before they can be held or watched, and keep their prices.
    @MainActor
    func ensureInCatalog(_ product: Product, printing: String?) async throws {
        guard products[product.id] == nil else { return }
        let res = try await Backend.shared.api.importProduct(product, printing: printing)
        products[res.product.id] = res.product
        for price in res.prices { prices[priceKey(price.productId, price.printing)] = price }
        if !res.history.isEmpty { history[priceKey(res.product.id, printing ?? res.prices.first?.printing)] = res.history }
    }

    /// Add purchases: save each product to the catalog, find or create its holding, log the transaction.
    @MainActor
    func add(_ purchases: [Purchase]) async throws {
        for p in purchases {
            try await ensureInCatalog(p.product, printing: p.printing)
            let identity = HoldingIdentity(productId: p.product.id, printing: p.printing, condition: p.condition, gradeCompany: p.gradeCompany, grade: p.grade)
            try await log(identity: identity, type: "purchase", date: p.date, quantity: p.quantity, unitPrice: p.unitPrice, source: p.source, notes: p.notes)
        }
        recompute()
    }

    /// Record a sale. Proceeds are price × quantity less fees and shipping; cost comes off the oldest units first.
    @MainActor
    func sell(_ identity: HoldingIdentity, quantity: Double, unitPrice: Double, fees: Double, shipping: Double, date: String, source: String? = "ios", notes: String? = nil) async throws {
        try await log(identity: identity, type: "sale", date: date, quantity: quantity, unitPrice: unitPrice, fees: fees, shipping: shipping, source: source, notes: notes)
        recompute()
    }

    /// Change an entry. Recorded as a correction, never by editing the original, so history stays intact.
    @MainActor
    func correct(_ entry: Txn, date: String, quantity: Double, unitPrice: Double, fees: Double, shipping: Double) async throws {
        try await log(identity: entry.identity, type: "correction", date: date, quantity: quantity, unitPrice: unitPrice, fees: fees, shipping: shipping, tax: entry.tax, correctsId: entry.id)
        recompute()
    }

    /// Delete an entry: a correction with quantity 0 voids it.
    @MainActor
    func delete(_ entry: Txn) async throws {
        try await log(identity: entry.identity, type: "correction", date: entry.date, quantity: 0, unitPrice: 0, correctsId: entry.id)
        recompute()
    }

    @MainActor
    private func log(
        identity: HoldingIdentity, type: String, date: String, quantity: Double, unitPrice: Double,
        fees: Double = 0, shipping: Double = 0, tax: Double = 0, source: String? = nil, notes: String? = nil, correctsId: String? = nil
    ) async throws {
        guard let userId else { throw HoloError.signedOut }
        let holding = try await holdingRow(for: identity, userId: userId)
        let row = NewTransactionRow(
            user_id: userId, holding_id: holding.id, type: type, trade_date: date, quantity: quantity, unit_price: unitPrice,
            fees: fees, shipping: shipping, tax: tax, source: source, notes: notes, corrects_id: correctsId
        )
        let saved: TransactionRow = try await db.from("transactions").insert(row).select().single().execute().value
        if let t = Self.txn(saved, identity: identity) { transactions.append(t) }
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

    /// Your own value for a graded slab (nil clears it).
    @MainActor
    func setManualValue(_ identity: HoldingIdentity, _ value: Double?) async throws {
        guard let row = holdingRows.first(where: { $0.identity.key == identity.key }) else { return }
        let update = ManualValueUpdate(manual_value: value, manual_value_date: value == nil ? nil : today)
        try await db.from("holdings").update(update).eq("id", value: row.id).execute()
        if let value { manualValues[identity.key] = ManualValue(value: value, date: today) } else { manualValues[identity.key] = nil }
        recompute()
    }

    // MARK: Writing: watchlist

    @MainActor
    func addWatch(_ product: Product, printing: String?, target: Double?) async throws {
        guard let userId else { throw HoloError.signedOut }
        try await ensureInCatalog(product, printing: printing)
        let row: WatchRow = try await db.from("watchlist_items")
            .insert(NewWatchRow(user_id: userId, product_id: product.id, printing: printing, target_price: target))
            .select().single().execute().value
        watchlist.append(row)
    }

    @MainActor
    func setWatchTarget(_ id: String, _ target: Double?) async throws {
        try await db.from("watchlist_items").update(WatchTargetUpdate(target_price: target)).eq("id", value: id).execute()
        if let i = watchlist.firstIndex(where: { $0.id == id }) { watchlist[i].target_price = target }
    }

    @MainActor
    func removeWatch(_ id: String) async throws {
        try await db.from("watchlist_items").delete().eq("id", value: id).execute()
        watchlist.removeAll { $0.id == id }
    }

    // MARK: Writing: wishlist (shared JSON with the website)

    @MainActor
    func addWish(_ product: Product, printing: String?, price: Double?, priority: WishItem.Priority = .want) async throws {
        guard !wishlist.contains(where: { $0.product.id == product.id }) else { return }
        var next = wishlist
        next.append(WishItem(id: UUID().uuidString.lowercased(), product: product, printing: printing, priority: priority, target: nil, price: price, addedAt: ISO8601DateFormatter().string(from: Date())))
        try await saveWishlist(next)
    }

    @MainActor
    func updateWish(_ id: String, priority: WishItem.Priority? = nil, target: Double?? = nil) async throws {
        var next = wishlist
        guard let i = next.firstIndex(where: { $0.id == id }) else { return }
        if let priority { next[i].priority = priority }
        if let target { next[i].target = target }
        try await saveWishlist(next)
    }

    @MainActor
    func removeWish(_ id: String) async throws {
        try await saveWishlist(wishlist.filter { $0.id != id })
    }

    @MainActor
    private func saveWishlist(_ items: [WishItem]) async throws {
        guard let userId else { throw HoloError.signedOut }
        // Pick up changes made on the website since loading, so neither side overwrites the other's additions.
        if let remote = try? await UserState.load("wishlist", as: [WishItem].self) {
            let known = Set(wishlist.map(\.id))
            let addedElsewhere = remote.filter { !known.contains($0.id) }
            try await UserState.save("wishlist", items + addedElsewhere, userId: userId)
            wishlist = items + addedElsewhere
        } else {
            try await UserState.save("wishlist", items, userId: userId)
            wishlist = items
        }
    }
}
