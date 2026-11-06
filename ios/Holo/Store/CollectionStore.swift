import Foundation
import Observation
import Supabase

/// Your collection, watchlist and wishlist, loaded from Supabase into the same shape
/// the web app uses, and every write that changes them.
@Observable
final class CollectionStore {
    enum Status: Equatable { case idle, loading, ready, failed(String) }

    var status: Status = .idle
    /// True once this session's data came from the server; false while the collection on screen
    /// is the one saved on the phone last time (so milestones wait for fresh figures).
    private(set) var isFresh = false
    var products: [String: Product] = [:]
    var prices: [String: Price] = [:] { didSet { refreshedCache = nil } }
    var history: [String: [PricePoint]] = [:] { didSet { seriesCache = [:] } }
    /// What you hold in the selected portfolio (everything when none is picked).
    var holdings: [HoldingView] = []
    /// Everything you hold, whatever portfolio is selected (deals use these).
    var allHoldings: [HoldingView] = [] { didSet { indexHoldings() } }
    /// Which holdings the selected portfolio covers, by holding key; nil shows everything.
    /// Switching portfolios (a menu pick) updates holdings and totals at once and rebuilds the
    /// value-over-time history off the main thread right away, so the menu closes without a hitch.
    var holdingFilter: ((String) -> Bool)? { didSet { recompute(timelineSoon: true) } }

    /// Where each holding sits in `allHoldings`, by holding key and by product id, so the
    /// per-row lookups (the Owned sheet, card links, deal rows) don't scan every holding and
    /// build every key each time.
    @ObservationIgnored private var holdingIndex: [String: Int] = [:]
    @ObservationIgnored private var productIndex: [String: [Int]] = [:]

    private func indexHoldings() {
        var byKey: [String: Int] = [:]
        var byProduct: [String: [Int]] = [:]
        byKey.reserveCapacity(allHoldings.count)
        for (i, h) in allHoldings.enumerated() {
            let key = h.identity.key
            // The first match wins, like the `first(where:)` this replaces.
            if byKey[key] == nil { byKey[key] = i }
            byProduct[h.identity.productId, default: []].append(i)
        }
        holdingIndex = byKey
        productIndex = byProduct
    }
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
    /// The shared user_state keys (wishlist, release-reminders) read from the account this
    /// session. A missing row counts (it's just empty); a failed read doesn't, so an empty list
    /// shown after a failed read is never saved over the account.
    @ObservationIgnored private var syncedState: Set<String> = []

    /// The full log, corrections included.
    private(set) var transactions: [Txn] = [] { didSet { clearCaches() } }
    private var holdingRows: [HoldingRow] = []
    private var manualValues: [String: ManualValue] = [:]
    private(set) var userId: String?

    private var db: SupabaseClient { Backend.shared.supabase }
    private var today: String { Format.day() }

    func reset() {
        // Signed out: the collection saved on the phone goes too.
        SnapshotFile.deleteAll()
        status = .idle
        isFresh = false
        monthlyBudget = nil
        products = [:]
        prices = [:]
        history = [:]
        holdings = []
        allHoldings = []
        summary = PortfolioSummary()
        timeline = []
        watchlist = []
        wishlist = []
        reminders = []
        syncedState = []
        ebayGraded = [:]
        transactions = []
        holdingRows = []
        manualValues = [:]
        conditionShares = [:]
        userId = nil
        // A history rebuild still running for the old account is dropped when it lands.
        timelineGeneration += 1
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

    /// Loads your collection. On launch it opens at once on the collection saved on the phone
    /// last time (if any), then the fresh data replaces it as it arrives: holdings, the log,
    /// products and current prices first, then the price history (the biggest part) for the
    /// charts. The value-over-time chart is worked out off the main thread, so the screen shows
    /// first and the chart fills a moment later.
    @MainActor
    func load(userId: String) async {
        let wasDemo = demo != nil
        let sameAccount = self.userId == userId
        self.userId = userId
        if !sameAccount { syncedState = [] }
        demo = nil
        // Whether this account's collection is on screen (an earlier load, or the saved copy).
        var showing = status == .ready && !wasDemo && sameAccount
        if !showing {
            isFresh = false
            if let saved = await SnapshotFile.read(userId: userId) {
                // Signed out or switched to a demo while reading: drop it.
                guard self.userId == userId, demo == nil else { return }
                apply(saved)
                recompute(timelineSoon: true)
                status = .ready
                showing = true
            }
        }
        // A demo or another account's collection on screen is hidden until this one arrives.
        if !showing { status = .loading }
        do {
            // Everything that doesn't depend on anything else is fetched side by side.
            struct PrefRow: Decodable { var monthly_budget: Double? }
            async let holdingsLoad: [HoldingRow] = self.all { a, b in
                try await self.db.from("holdings").select().range(from: a, to: b).execute().value
            }
            async let txLoad: [TransactionRow] = self.all { a, b in
                try await self.db.from("transactions").select().order("created_at").range(from: a, to: b).execute().value
            }
            async let watchLoad: [WatchRow] = self.all { a, b in
                try await self.db.from("watchlist_items").select().order("created_at").range(from: a, to: b).execute().value
            }
            // A missing wishlist is just empty; don't fail the whole load over it. A failed read
            // keeps what's on screen and leaves the key unsynced (saves then merge or refuse).
            async let wishLoad: Result<[WishItem]?, Error> = Self.loadState("wishlist", as: [WishItem].self)
            async let reminderLoad: Result<[String]?, Error> = Self.loadState("release-reminders", as: [String].self)
            // An older database without the budget column just means no budget.
            async let prefLoad: [PrefRow]? = try? await self.db.from("user_preferences").select("monthly_budget").execute().value
            let holdingRows = try await holdingsLoad
            let txRows = try await txLoad
            let watchRows = try await watchLoad

            let byId = Dictionary(holdingRows.map { ($0.id, $0) }, uniquingKeysWith: { a, _ in a })
            let txns: [Txn] = txRows.compactMap { r in
                guard let h = byId[r.holding_id] else { return nil }
                return Self.txn(r, identity: h.identity)
            }
            var manual: [String: ManualValue] = [:]
            for h in holdingRows {
                if let v = h.manual_value, let d = h.manual_value_date { manual[h.identity.key] = ManualValue(value: v, date: d) }
            }

            // Catalog rows and current prices for everything you hold or watch, 200 ids at a
            // time, every batch at once. The price history comes after (below).
            let ids = Array(Set(holdingRows.map(\.product_id) + watchRows.map(\.product_id)))
            let chunks = Self.chunks(ids)
            var products: [String: Product] = [:]
            var prices: [String: Price] = [:]
            let batches = try await withThrowingTaskGroup(of: ([ProductRow], [PriceRow]).self) { group in
                for chunk in chunks {
                    group.addTask {
                        async let productRows: [ProductRow] = self.all { a, b in
                            try await self.db.from("products").select().in("id", values: chunk).range(from: a, to: b).execute().value
                        }
                        async let priceRows: [PriceRow] = self.all { a, b in
                            try await self.db.from("product_prices").select().in("product_id", values: chunk).range(from: a, to: b).execute().value
                        }
                        return try await (productRows, priceRows)
                    }
                }
                var results: [([ProductRow], [PriceRow])] = []
                for try await batch in group { results.append(batch) }
                return results
            }
            for (productRows, priceRows) in batches {
                for p in productRows { products[p.id] = p.product }
                for p in priceRows { prices[priceKey(p.product_id, p.printing.isEmpty ? nil : p.printing)] = p.price }
            }
            let wishes = await wishLoad
            let reminderList = await reminderLoad
            let prefs = await prefLoad
            // Signed out or switched to a demo meanwhile: this data isn't wanted any more.
            guard self.userId == userId, demo == nil else { return }

            self.holdingRows = holdingRows
            self.transactions = txns
            self.manualValues = manual
            self.products = products
            self.prices = prices
            self.watchlist = watchRows
            if case .success(let list) = wishes {
                self.wishlist = list ?? []
                syncedState.insert("wishlist")
            }
            if case .success(let list) = reminderList {
                self.reminders = Set(list ?? [])
                syncedState.insert("release-reminders")
            }
            self.monthlyBudget = prefs?.first?.monthly_budget
            // The history on hand (the saved copy's, or the last load's) stays until the new one lands.
            recompute(timelineSoon: true)
            status = .ready
            isFresh = true

            // The price history, the largest part, last; it rebuilds the chart when it lands.
            let historyLoad = Task { @MainActor in
                guard let fresh = try? await self.fetchHistory(ids) else { return }
                guard self.userId == userId, self.demo == nil else { return }
                var merged = self.history
                for (key, points) in fresh { merged[key] = points }
                self.history = merged
                self.rebuildTimeline(after: 0)
            }
            await loadSlabPrices()
            await loadConditionShares()
            await historyLoad.value
            // Signed out or switched account meanwhile: don't save a mix under the new account.
            guard self.userId == userId, demo == nil else { return }
            saveSnapshot()
        } catch {
            // Signed out (the load was cancelled) or switched to a demo: nothing to show.
            guard self.userId == userId, demo == nil else { return }
            // Keep showing what's on screen (offline, or a refresh that failed); only an empty
            // screen turns into the error.
            if !showing { status = .failed(error.localizedDescription) }
        }
    }

    /// Reads one user_state key without throwing: `.success(nil)` is a missing row (empty),
    /// `.failure` a read that didn't work.
    private static func loadState<T: Decodable>(_ key: String, as type: T.Type) async -> Result<T?, Error> {
        do { return .success(try await UserState.load(key, as: type)) } catch { return .failure(error) }
    }

    /// Ids in batches of 200 (the most a request's id list is given).
    private static func chunks(_ ids: [String]) -> [[String]] {
        stride(from: 0, to: ids.count, by: 200).map { Array(ids[$0..<min($0 + 200, ids.count)]) }
    }

    /// Every stored daily price for these products, one per day, in order. Runs off the main thread.
    private func fetchHistory(_ ids: [String]) async throws -> [String: [PricePoint]] {
        let chunks = Self.chunks(ids)
        let batches = try await withThrowingTaskGroup(of: [SnapshotRow].self) { group in
            for chunk in chunks {
                group.addTask {
                    let rows: [SnapshotRow] = try await self.all { a, b in
                        try await self.db.from("price_snapshots").select("product_id,printing,snapshot_date,market_price")
                            .in("product_id", values: chunk).order("snapshot_date").range(from: a, to: b).execute().value
                    }
                    return rows
                }
            }
            var results: [[SnapshotRow]] = []
            for try await batch in group { results.append(batch) }
            return results
        }
        var history: [String: [PricePoint]] = [:]
        for rows in batches {
            for s in rows {
                history[priceKey(s.product_id, s.printing.isEmpty ? nil : s.printing), default: []].append(PricePoint(date: s.snapshot_date, price: s.market_price))
            }
        }
        // One price per day, in order: duplicate snapshots made the charts' fill fold back.
        for (key, pts) in history { history[key] = Self.onePerDay(pts) }
        return history
    }

    /// Shows the collection saved on the phone last time.
    @MainActor
    private func apply(_ s: CollectionSnapshot) {
        holdingRows = s.holdingRows
        manualValues = s.manualValues
        products = s.products
        prices = s.prices
        history = s.history
        ebayGraded = s.ebayGraded
        conditionShares = s.conditionShares
        watchlist = s.watchlist
        wishlist = s.wishlist
        reminders = Set(s.reminders)
        monthlyBudget = s.monthlyBudget
        transactions = s.transactions
    }

    /// Saves the collection on the phone (in the background) for the next launch to open on.
    /// Never in a demo.
    @MainActor
    private func saveSnapshot() {
        guard demo == nil, !Demo.isOn, isFresh, let userId else { return }
        SnapshotFile.write(CollectionSnapshot(
            userId: userId, savedAt: Date(), holdingRows: holdingRows, transactions: transactions,
            manualValues: manualValues, products: products, prices: prices, history: history,
            ebayGraded: ebayGraded, conditionShares: conditionShares, watchlist: watchlist,
            wishlist: wishlist, reminders: Array(reminders).sorted(), monthlyBudget: monthlyBudget
        ))
    }

    /// Sorts a price history by day and keeps the last price for each day.
    static func onePerDay(_ points: [PricePoint]) -> [PricePoint] {
        var byDay: [String: PricePoint] = [:]
        for p in points { byDay[p.date] = p }
        return byDay.values.sorted { $0.date < $1.date }
    }

    private static func txn(_ r: TransactionRow, identity: HoldingIdentity) -> Txn? {
        guard let kind = Txn.Kind(rawValue: r.type) else { return nil }
        return Txn(
            id: r.id, identity: identity, kind: kind, date: r.trade_date, quantity: r.quantity, unitPrice: r.unit_price,
            fees: r.fees, shipping: r.shipping, tax: r.tax, correctsId: r.corrects_id, createdAt: r.created_at,
            source: r.source, notes: r.notes
        )
    }

    @ObservationIgnored private var timelinePending = false
    /// Goes up with each history rebuild, so an older rebuild that finishes late is dropped.
    @ObservationIgnored private var timelineGeneration = 0

    /// Holdings and totals update at once (screens read them right after a change). The
    /// value-over-time history is the expensive part, so several changes in a row (a deal closing
    /// many items) rebuild it once, just after the last one.
    /// The log for the selected portfolio.
    var portfolioTransactions: [Txn] {
        guard let holdingFilter else { return transactions }
        return transactions.filter { holdingFilter($0.identity.key) }
    }

    // Worked out once per change, not on every redraw (Home, the card page and Collection read
    // these many times a second while scrolling or animating).
    @ObservationIgnored private var effectiveCache: [Txn]?
    @ObservationIgnored private var editedCache: Set<String>?
    @ObservationIgnored private var seriesCache: [String: [TimelinePoint]] = [:]
    @ObservationIgnored private var recentCache: [Int: [RecentPurchase]] = [:]
    /// Each position's entries, newest first, by holding key (built in one pass).
    @ObservationIgnored private var entriesCache: [String: [Txn]]?
    /// The newest price refresh (parsing every price's date is slow; Collection reads it on
    /// every redraw). Outer nil: not worked out yet.
    @ObservationIgnored private var refreshedCache: Date??
    @ObservationIgnored private var spentCache: (month: String, value: Double)?

    /// The log with corrections applied (cached).
    var effectiveTransactions: [Txn] {
        if let effectiveCache { return effectiveCache }
        let e = Ledger.effective(transactions)
        effectiveCache = e
        return e
    }

    private func clearCaches() {
        effectiveCache = nil
        editedCache = nil
        seriesCache = [:]
        recentCache = [:]
        entriesCache = nil
        spentCache = nil
    }

    private func recompute(timelineNow: Bool = false, timelineSoon: Bool = false) {
        clearCaches()
        allHoldings = Portfolio.holdings(transactions: transactions, products: products, prices: prices, manualValues: manualValues, ebayGraded: ebayGraded, conditionShares: conditionShares)
        holdings = holdingFilter.map { f in allHoldings.filter { f($0.identity.key) } } ?? allHoldings
        let realized = Ledger(portfolioTransactions).positions.values.reduce(0) { $0 + $1.realizedGain }
        summary = Portfolio.summary(holdings, realized: realized)
        if timelineNow {
            timelineGeneration += 1
            timeline = Timeline.compute(transactions: portfolioTransactions, prices: prices, history: history, manualValues: manualValues, ebayGraded: ebayGraded, conditionShares: conditionShares, today: today)
            return
        }
        if timelineSoon {
            rebuildTimeline(after: 0)
            return
        }
        guard !timelinePending else { return }
        timelinePending = true
        // Long enough to catch the next write of a batch (they each wait on the network, and
        // loading brings prices, played-card prices and slab prices one after another).
        rebuildTimeline(after: 400_000_000)
    }

    /// The day-by-day replay is the heavy part: do it off the main thread so scrolling, menus
    /// and animations don't stutter while it runs.
    private func rebuildTimeline(after delay: UInt64) {
        Task { @MainActor in
            if delay > 0 {
                try? await Task.sleep(nanoseconds: delay)
                self.timelinePending = false
            }
            self.timelineGeneration += 1
            let generation = self.timelineGeneration
            let (txns, prices, history, manual, ebay, shares, today) = (self.portfolioTransactions, self.prices, self.history, self.manualValues, self.ebayGraded, self.conditionShares, self.today)
            let result = await Task.detached(priority: .userInitiated) {
                Timeline.compute(transactions: txns, prices: prices, history: history, manualValues: manual, ebayGraded: ebay, conditionShares: shares, today: today)
            }.value
            // A newer rebuild started meanwhile: it has newer data and lands after this one.
            guard generation == self.timelineGeneration else { return }
            self.timeline = result
        }
    }

    /// What each played condition really sells for, as a share of Near Mint, per card you hold
    /// played (keyed by CardCondition.measuredKey). Empty until loaded; estimates fill the gap.
    var conditionShares: [String: Double] = [:]

    /// Load TCGplayer's per-condition prices for every card you hold in a played condition (cached
    /// a day on the server), and value those copies from them instead of a fixed share.
    @MainActor
    private func loadConditionShares() async {
        let played = allHoldings.filter { !$0.identity.isGraded && $0.identity.productId.hasPrefix("tcgapi:")
            && $0.identity.condition != CardCondition.nearMint.rawValue && $0.identity.condition != "Sealed" }
        guard !played.isEmpty else { return }
        var found: [String: Double] = [:]
        for h in played {
            let key = CardCondition.measuredKey(h.identity.productId, h.identity.printing, h.identity.condition)
            guard found[key] == nil else { continue }
            guard let rows = try? await Backend.shared.api.conditionPrices(h.identity.productId, printing: h.identity.printing) else { continue }
            for (condition, share) in CardCondition.measuredShares(rows, printing: h.identity.printing) {
                found[CardCondition.measuredKey(h.identity.productId, h.identity.printing, condition)] = share
            }
        }
        guard !found.isEmpty else { return }
        conditionShares = found
        recompute()
    }

    /// Price your slabs for their exact grade, like the website: the 30-day eBay median when that
    /// grade sold at least 3 times, else PriceCharting's value, else the last eBay sale. A CGC 10
    /// is priced as a Pristine 10 or a Gem Mint 10 (`Pristine.slabPrice`); also called when a
    /// slab's Pristine mark changes.
    @MainActor
    func loadSlabPrices() async {
        let graded = allHoldings.filter { $0.identity.isGraded && $0.identity.productId.hasPrefix("tcgapi:") }
        guard !graded.isEmpty else { return }
        let ids = Array(Set(graded.map(\.identity.productId)))
        async let ebayLoad = try? await Backend.shared.api.ebaySummaries(ids)
        async let pcLoad = try? await Backend.shared.api.gradedValues(ids)
        let summaries = await ebayLoad ?? [:]
        let pc = await pcLoad ?? [:]
        var found: [String: Double] = [:]
        for h in graded {
            guard let label = h.identity.gradeLabel, let company = h.identity.gradeCompany, let grade = h.identity.grade else { continue }
            let stats = summaryFor(summaries[h.identity.productId], printing: h.identity.printing)?.graded[label]
            // A CGC 10 that has sold: its listings (shared cache) tell Pristine 10s from Gem Mint 10s.
            var sales: EbaySales?
            if Pristine.isCGCTen(company: company, grade: grade), stats != nil {
                sales = (try? await EbaySalesCache.sales(h.identity.productId, printing: h.identity.printing)) ?? nil
            }
            if let price = Pristine.slabPrice(company: company, grade: grade, pristine: Pristine.marked.contains(h.identity.key),
                                              summary: stats, sales: sales, guide: pc[h.identity.productId]?.value(company: company, grade: grade)) {
                found[h.identity.key] = price
            }
        }
        guard !found.isEmpty else { return }
        ebayGraded = demo == nil ? found : ebayGraded.merging(found) { _, new in new }
        recompute()
    }

    /// Bring a catalog product (one you don't own) in for its page: details, prices and history.
    @MainActor
    func showCatalogProduct(_ id: String) async {
        // Once per product per session, even if a search result already put it in `products`
        // (that's just one printing's price; this brings every printing and its history).
        let owned = !holdings(for: id).isEmpty
        guard !owned, !catalogLoaded.contains(id), let res = try? await Backend.shared.api.catalogProduct(id) else { return }
        catalogLoaded.insert(id)
        let printings = products[id]?.printings
        products[id] = res.product
        if res.product.printings == nil { products[id]?.printings = printings }
        for p in res.prices { prices[priceKey(p.productId, p.printing)] = p }
        for (key, pts) in res.history where history[key] == nil { history[key] = Self.onePerDay(pts) }
    }

    /// Fill in a product's price history when Holo only has a little of it (cards you don't own
    /// or watch have none). Asked for once per product per session; the server only spends a
    /// TCG API call the first time anyone asks, then keeps it for everyone.
    @ObservationIgnored private var historyAsked: Set<String> = []

    enum HistoryLoad: Equatable { case loading, failed(String), note(String) }
    /// What's happening with a price history being fetched, by price key, for the chart to show.
    var historyLoad: [String: HistoryLoad] = [:]

    @MainActor
    func loadFullHistory(_ id: String, printing: String?, retry: Bool = false) async {
        // Prices are shared by everyone, so this works in a demo collection too; only the
        // screenshot demo (no server) skips it.
        guard !Demo.isOn, id.hasPrefix("tcgapi:") else { return }
        let key = priceKey(id, printing)
        let have = history[key] ?? []
        // Already reaches back two months: nothing to fetch.
        if let first = have.first?.date, let start = Format.isoDay.date(from: first),
           start <= Calendar.current.date(byAdding: .day, value: -60, to: Date()) ?? Date() { return }
        guard retry || !historyAsked.contains(key) else { return }
        historyAsked.insert(key)
        historyLoad[key] = .loading
        do {
            let res = try await Backend.shared.api.priceHistory(id, printing: printing)
            if !res.available {
                historyLoad[key] = .note(res.reason ?? "Price history isn't available right now.")
                return
            }
            guard !res.points.isEmpty else {
                historyLoad[key] = .note("No price history is available for this product yet.")
                return
            }
            historyLoad[key] = nil
            history[key] = Self.onePerDay((history[key] ?? []) + res.points)
        } catch {
            historyLoad[key] = .failed(error.localizedDescription)
            return
        }
        // It may change what your collection was worth on past days.
        if !holdings(for: id).isEmpty { recompute() }
    }

    /// Keep a search result's product and price so its page opens instantly, even if it isn't stored yet.
    @ObservationIgnored private var catalogLoaded: Set<String> = []
    /// The printing you tapped in search or a set, for its page to open on (taken once).
    @ObservationIgnored private var openPrinting: [String: String] = [:]

    func takeOpenPrinting(_ id: String) -> String? { openPrinting.removeValue(forKey: id) }

    /// The printing a card page should open on next (a scan's chosen printing).
    func setOpenPrinting(_ printing: String?, for id: String) {
        if let printing { openPrinting[id] = printing } else { openPrinting.removeValue(forKey: id) }
    }

    func seed(_ hit: SearchHit) {
        if let p = hit.printing { openPrinting[hit.product.id] = p }
        if products[hit.product.id] == nil { products[hit.product.id] = hit.product }
        let key = priceKey(hit.product.id, hit.printing)
        if prices[key] == nil, let market = hit.market {
            prices[key] = Price(productId: hit.product.id, printing: hit.printing, market: market, status: "live")
        }
    }

    /// One position's value per unit over the last `days` days (for sparklines).
    func series(_ identity: HoldingIdentity, days: Int = 90) -> [TimelinePoint] {
        let key = "\(identity.key)#\(days)"
        if let hit = seriesCache[key] { return hit }
        let today = Format.day()
        let start = Format.day(Calendar.current.date(byAdding: .day, value: -days, to: Date()) ?? Date())
        let points = Timeline.days(from: start, to: today).compactMap { day in
            Timeline.price(identity, on: day, today: today, prices: prices, history: history, manual: manualValues, ebay: ebayGraded)
                .map { TimelinePoint(date: day, value: $0, cost: 0) }
        }
        seriesCache[key] = points
        return points
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
        if let hit = recentCache[limit] { return hit }
        let unit = Dictionary(holdings.map { ($0.identity.key, $0.price) }, uniquingKeysWith: { a, _ in a })
        let list = effectiveTransactions
            .filter { $0.kind == .purchase }
            .sorted { $0.date != $1.date ? $0.date > $1.date : $0.createdAt > $1.createdAt }
            .prefix(limit)
            .map { t in
                let price = unit[t.identity.key] ?? nil
                return RecentPurchase(entry: t, product: products[t.identity.productId], value: price.map { $0 * t.quantity })
            }
        let result = Array(list)
        recentCache[limit] = result
        return result
    }

    /// Fills the store with the made-up demo collection (see DemoData), for screenshots.
    /// The demo collection on screen, or nil when it's your real one. Nothing is saved in a demo.
    private(set) var demo: DemoKind?

    /// The demo's cards matched to the real catalog: the real product, printing, price and
    /// history, by demo slug. Filled once per session when there's a server (not in screenshots).
    @ObservationIgnored private var realDemo: [String: DemoData.Real] = [:]
    @ObservationIgnored private var realizing = false
    /// Each demo card's made-up id → its real catalog id and printing, so a sheet opened just
    /// before the switch follows the card.
    @ObservationIgnored private var demoAlias: [String: (id: String, printing: String?)] = [:]

    /// The holding as it is now: a demo card that has just switched to its real catalog card
    /// is found under its new id.
    func current(_ identity: HoldingIdentity) -> HoldingIdentity {
        guard holding(identity) == nil else { return identity }
        // A copy whose details you just changed (condition, grade, printing): follow it.
        if let moved = renamed[identity.key], moved.key != identity.key { return current(moved) }
        guard let real = demoAlias[identity.productId] else { return identity }
        var i = identity
        i.productId = real.id
        i.printing = real.printing
        return i
    }

    func loadDemo(_ kind: DemoKind = .mixed) {
        demo = kind
        var products: [String: Product] = [:]
        var prices: [String: Price] = [:]
        var history: [String: [PricePoint]] = [:]
        let now = ISO8601DateFormatter().string(from: Date().addingTimeInterval(-3 * 3600))
        var realIds: [String: (id: String, printing: String?)] = [:]
        for item in DemoData.items {
            // The real card, with its real prices, when we've matched it.
            if let r = realDemo[item.slug] {
                products[r.product.id] = r.product
                for (key, price) in r.prices { prices[key] = price }
                for (key, pts) in r.history { history[key] = pts }
                realIds[item.slug] = (r.product.id, r.printing)
                continue
            }
            let p = DemoData.product(item)
            let printing = p.printings?.first
            let pts = DemoData.series(item)
            func change(_ back: Int) -> Double? {
                guard pts.count > back, let last = pts.last?.price else { return nil }
                let then = pts[pts.count - 1 - back].price
                return then > 0 ? (last - then) / then * 100 : nil
            }
            products[p.id] = p
            prices[priceKey(p.id, printing)] = Price(productId: p.id, printing: printing, market: pts.last?.price, low: nil,
                                                     change24hPct: change(1), change7dPct: change(7), change30dPct: change(30),
                                                     updatedAt: now, status: "fresh")
            history[priceKey(p.id, printing)] = pts
        }
        var txns: [Txn] = []
        for (n, lot) in DemoData.lots(kind).enumerated() {
            let (slug, daysAgo, qty, unit, condition, company, grade) = lot
            let id = realIds[slug]?.id ?? "sample:\(slug)"
            let printing: String? = realIds[slug] != nil ? realIds[slug]!.printing : products[id]?.printings?.first
            let date = Format.day(Calendar.current.date(byAdding: .day, value: -daysAgo, to: Date()) ?? Date())
            txns.append(Txn(id: "demo-\(n)", identity: HoldingIdentity(productId: id, printing: printing, condition: condition, gradeCompany: company, grade: grade),
                            kind: .purchase, date: date, quantity: qty, unitPrice: unit, shipping: 4, createdAt: "\(date)T12:00:00Z",
                            source: n % 3 == 0 ? "Card show" : "TCGplayer"))
        }
        // Slabs are priced like recent eBay sales for their grade would put them.
        var graded: [String: Double] = [:]
        let multiple: [String: Double] = ["PSA 10": 3.2, "PSA 9": 1.6, "CGC 9.5": 1.8, "BGS 9.5": 2.1]
        for t in txns {
            guard let label = t.identity.gradeLabel, let m = multiple[label],
                  let market = prices[priceKey(t.identity.productId, t.identity.printing)]?.market else { continue }
            graded[t.identity.key] = (market * m * 100).rounded() / 100
        }
        self.products = products
        self.prices = prices
        self.history = history
        self.transactions = txns
        self.holdingRows = []
        self.manualValues = [:]
        self.ebayGraded = graded
        self.watchlist = []
        self.wishlist = []
        self.monthlyBudget = 500
        for (slug, r) in realIds { demoAlias["sample:\(slug)"] = r }
        recompute(timelineNow: true)
        // When the demo's cards were matched before, wait for their real data rather than
        // showing made-up figures that then jump.
        let waitForReal = realDemo.isEmpty && !Demo.isOn && AppConfig.isConfigured && DemoData.hasMatches
        status = waitForReal ? .loading : .ready
        if realDemo.isEmpty {
            Task { await realizeDemo(kind) }
        } else {
            Task { await loadSlabPrices(); await loadConditionShares() }
        }
    }

    /// Match the demo's cards to the real catalog (stored catalog search and tables: no TCG API
    /// calls; the match is kept on the phone), then show the demo again with real prices, price
    /// history, graded and condition prices. Only the quantities and what was paid stay made up.
    @MainActor
    private func realizeDemo(_ kind: DemoKind) async {
        guard !Demo.isOn, AppConfig.isConfigured, !realizing else { return }
        realizing = true
        defer {
            realizing = false
            // If the real data didn't come, show the made-up demo rather than wait forever.
            if status == .loading, demo == kind { status = .ready }
        }
        let matches = await DemoData.matchReal()
        guard !matches.isEmpty else { return }
        let ids = Array(Set(matches.values.map { $0.id }))
        do {
            async let productRows: [ProductRow] = try await db.from("products").select().in("id", values: ids).execute().value
            async let priceRows: [PriceRow] = try await db.from("product_prices").select().in("product_id", values: ids).execute().value
            async let snapRows: [SnapshotRow] = self.all { a, b in
                try await self.db.from("price_snapshots").select("product_id,printing,snapshot_date,market_price")
                    .in("product_id", values: ids).order("snapshot_date").range(from: a, to: b).execute().value
            }
            let (pRows, prRows, sRows) = try await (productRows, priceRows, snapRows)
            let byId = Dictionary(pRows.map { ($0.id, $0.product) }, uniquingKeysWith: { a, _ in a })
            var real: [String: DemoData.Real] = [:]
            for (slug, m) in matches {
                guard let product = byId[m.id] else { continue }
                var r = DemoData.Real(product: product, printing: m.printing)
                for p in prRows where p.product_id == m.id { r.prices[priceKey(p.product_id, p.printing.isEmpty ? nil : p.printing)] = p.price }
                for s in sRows where s.product_id == m.id {
                    r.history[priceKey(s.product_id, s.printing.isEmpty ? nil : s.printing), default: []].append(PricePoint(date: s.snapshot_date, price: s.market_price))
                }
                for (key, pts) in r.history { r.history[key] = Self.onePerDay(pts) }
                // Only use a match that has a price for its printing.
                guard r.prices[priceKey(m.id, m.printing)]?.market != nil else { continue }
                real[slug] = r
            }
            guard !real.isEmpty, demo == kind else { return }
            realDemo = real
            loadDemo(kind)
            // The demo's purchases go back up to two years: fill in each card's longer history
            // (the server fetches it once for everyone, then keeps it).
            for r in real.values { await loadFullHistory(r.product.id, printing: r.printing) }
        } catch {
            return
        }
    }

    /// The newest price refresh across everything you hold.
    var pricesRefreshedAt: Date? {
        // Read `prices` first so a view showing this still updates when prices change.
        let prices = self.prices
        if let hit = refreshedCache { return hit }
        let latest = Self.newestRefresh(prices)
        refreshedCache = .some(latest)
        return latest
    }

    private static func newestRefresh(_ prices: [String: Price]) -> Date? {
        let f = ISO8601DateFormatter()
        f.formatOptions = [.withInternetDateTime, .withFractionalSeconds]
        let plain = ISO8601DateFormatter()
        return prices.values.compactMap { $0.updatedAt }.compactMap { f.date(from: $0) ?? plain.date(from: $0) }.max()
    }

    /// Sets (or with nil, removes) the monthly budget, like the website.
    func setMonthlyBudget(_ value: Double?) async throws {
        // In a demo (or signed out) nothing is saved, but the change still shows, like the
        // rest of the demo.
        guard demo == nil, !Demo.isOn, let userId else {
            monthlyBudget = value
            return
        }
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
        // Shown at once; put back if the save fails.
        let before = monthlyBudget
        monthlyBudget = value
        do {
            if value == nil {
                // Removing: clear the column on your row outright (an upsert carrying a null
                // could leave the old budget in place).
                try await db.from("user_preferences").update(["monthly_budget": AnyJSON.null]).eq("user_id", value: userId).execute()
            } else {
                try await db.from("user_preferences").upsert(Row(user_id: userId, monthly_budget: value)).execute()
            }
        } catch {
            monthlyBudget = before
            throw error
        }
        await MainActor.run { saveSnapshot() }
    }

    /// What you spent on purchases this calendar month.
    var spentThisMonth: Double {
        // Reading `transactions` keeps views showing this updating when the log changes.
        _ = transactions
        let month = String(Format.day().prefix(7))
        if let hit = spentCache, hit.month == month { return hit.value }
        let value = effectiveTransactions.filter { $0.kind == .purchase && $0.date.hasPrefix(month) }.reduce(0) { $0 + $1.acquisitionCost }
        spentCache = (month, value)
        return value
    }

    // MARK: Writing: release reminders

    @MainActor
    func setReminder(_ set: ExploreSet, on: Bool) async throws {
        // A demo keeps it on the phone only.
        if demo != nil || Demo.isOn {
            if on { reminders.insert(set.slug) } else { reminders.remove(set.slug) }
            return
        }
        guard let userId else { throw HoloError.signedOut }
        // Start from the account's current list (the website may have changed it, and the list
        // on screen may be a saved copy after a failed read), so nothing is overwritten. If it
        // can't be read, don't save at all.
        var next: Set<String>
        do {
            next = Set(try await UserState.load("release-reminders", as: [String].self) ?? [])
        } catch {
            throw HoloError.server(code: nil, message: "Couldn't reach your account. Try again.")
        }
        guard self.userId == userId, demo == nil else { return }
        syncedState.insert("release-reminders")
        if on { next.insert(set.slug) } else { next.remove(set.slug) }
        try await UserState.save("release-reminders", Array(next).sorted(), userId: userId)
        reminders = next
        if on { await Notifications.scheduleRelease(set) } else { Notifications.cancelRelease(set.slug) }
    }

    // MARK: Reading

    /// Copies you hold of one product.
    func holdings(for productId: String) -> [HoldingView] {
        // Reading `allHoldings` keeps views that call this updating when holdings change.
        let all = allHoldings
        guard let at = productIndex[productId] else { return [] }
        return at.compactMap { $0 < all.count ? all[$0] : nil }
    }

    func holding(_ identity: HoldingIdentity) -> HoldingView? { holding(key: identity.key) }

    /// The copy with this holding key (any portfolio), found without a scan.
    func holding(key: String) -> HoldingView? {
        let all = allHoldings
        guard let i = holdingIndex[key], i < all.count, all[i].identity.key == key else { return nil }
        return all[i]
    }

    /// The Near Mint market price for a product, from the catalog.
    func marketPrice(_ productId: String, printing: String?) -> Price? {
        prices[priceKey(productId, printing)]
    }

    /// One position's entries as they count now (edits applied, deleted ones gone), newest first.
    func entries(for identity: HoldingIdentity) -> [Txn] {
        // Reading `transactions` keeps views that call this updating when the log changes.
        _ = transactions
        if entriesCache == nil {
            var byKey: [String: [Txn]] = [:]
            for t in effectiveTransactions { byKey[t.identity.key, default: []].append(t) }
            entriesCache = byKey.mapValues { Array($0.reversed()) }
        }
        return entriesCache?[identity.key] ?? []
    }

    func manualValue(_ identity: HoldingIdentity) -> ManualValue? { manualValues[identity.key] }

    /// The audit trail the history hides, newest first: deleted entries and the records that
    /// edited or deleted them (the website's "Show deleted & edit records").
    func hiddenEntries(productId: String) -> [Txn] {
        let mine = transactions.filter { $0.identity.productId == productId }
        let shown = Set(Ledger.effective(mine).map(\.id))
        return mine.filter { $0.kind == .correction || !shown.contains($0.id) }.sorted { $0.createdAt > $1.createdAt }
    }

    /// Whether an entry has been corrected since it was first recorded.
    func wasEdited(_ t: Txn) -> Bool {
        if editedCache == nil { editedCache = Set(transactions.compactMap { $0.kind == .correction ? $0.correctsId : nil }) }
        return editedCache?.contains(t.id) == true
    }

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
        /// Totals for the whole purchase, kept as their own lines (they count toward its cost).
        var shipping: Double = 0
        var tax: Double = 0
        var fees: Double = 0
    }

    /// Save products to the shared catalog before they can be held or watched, and keep their prices.
    @MainActor
    func ensureInCatalog(_ product: Product, printing: String?) async throws {
        guard products[product.id] == nil else { return }
        // A demo collection keeps everything on the phone.
        if demo != nil {
            products[product.id] = product
            return
        }
        let res = try await Backend.shared.api.importProduct(product, printing: printing)
        products[res.product.id] = res.product
        for price in res.prices { prices[priceKey(price.productId, price.printing)] = price }
        if !res.history.isEmpty { history[priceKey(res.product.id, printing ?? res.prices.first?.printing)] = Self.onePerDay(res.history) }
    }

    /// Add purchases: save each product to the catalog, find or create its holding, log the transaction.
    @MainActor
    func add(_ purchases: [Purchase]) async throws {
        for p in purchases {
            try await ensureInCatalog(p.product, printing: p.printing)
            let identity = HoldingIdentity(productId: p.product.id, printing: p.printing, condition: p.condition, gradeCompany: p.gradeCompany, grade: p.grade)
            try await log(identity: identity, type: "purchase", date: p.date, quantity: p.quantity, unitPrice: p.unitPrice,
                          fees: p.fees, shipping: p.shipping, tax: p.tax, source: p.source, notes: p.notes)
        }
        recompute()
    }

    /// Record a sale. Proceeds are price × quantity less fees and shipping; cost comes off the oldest units first.
    @MainActor
    func sell(_ identity: HoldingIdentity, quantity: Double, unitPrice: Double, fees: Double, shipping: Double, date: String, source: String? = "ios", notes: String? = nil, offerUndo: Bool = true) async throws {
        try await log(identity: identity, type: "sale", date: date, quantity: quantity, unitPrice: unitPrice, fees: fees, shipping: shipping, source: source, notes: notes)
        recompute()
        // Undo for a few seconds: voids the sale just recorded.
        if offerUndo, let sale = transactions.last(where: { $0.kind == .sale && $0.identity == identity }) {
            Router.shared.undo = UndoItem(message: "Sale recorded") { [weak self] in
                guard let self else { return }
                try? await self.log(identity: sale.identity, type: "correction", date: sale.date, quantity: 0, unitPrice: 0, correctsId: sale.id)
                self.recompute()
            }
        }
    }

    /// Change an entry. Recorded as a correction, never by editing the original, so history stays intact.
    @MainActor
    func correct(_ entry: Txn, date: String, quantity: Double, unitPrice: Double, fees: Double, shipping: Double) async throws {
        try await log(identity: entry.identity, type: "correction", date: date, quantity: quantity, unitPrice: unitPrice, fees: fees, shipping: shipping, tax: entry.tax, correctsId: entry.id)
        recompute()
    }

    /// A card back from the grader, like the website: the raw units leave at their cost (no gain
    /// or loss) and the slab comes in at that same cost plus the grading fee and shipping.
    @MainActor
    func moveToSlab(raw: HoldingIdentity, company: String, grade: String, quantity: Double, fee: Double, shipping: Double, date: String) async throws {
        let held = holding(raw)
        let qty = min(quantity, held?.quantity ?? quantity)
        let unit = qty > 0 ? (held?.fifoCost(qty) ?? 0) / qty : 0
        let note = "Graded by \(company): \(company) \(grade)"
        if held != nil, qty > 0 {
            try await log(identity: raw, type: "sale", date: date, quantity: qty, unitPrice: unit, source: "Grading", notes: "\(note) — moved to a slab")
        }
        let slab = HoldingIdentity(productId: raw.productId, printing: raw.printing, condition: "Near Mint", gradeCompany: company, grade: grade)
        try await log(identity: slab, type: "purchase", date: date, quantity: qty, unitPrice: unit, fees: fee * qty, shipping: shipping * qty, source: "Grading", notes: note)
        recompute()
    }

    /// Copies whose details were changed this session, old key → new identity (so an open
    /// sheet follows the copy).
    @ObservationIgnored private var renamed: [String: HoldingIdentity] = [:]

    /// Fix a copy's details (condition, grade, printing) and keep its history: the holding row
    /// is updated in place; if you already have a copy with the new details, its entries move
    /// there and the two become one.
    @MainActor
    func changeDetails(_ old: HoldingIdentity, to new: HoldingIdentity) async throws {
        guard old.key != new.key else { return }
        if demo == nil {
            guard userId != nil else { throw HoloError.signedOut }
            guard let row = holdingRows.first(where: { $0.identity.key == old.key }) else { return }
            if let target = holdingRows.first(where: { $0.identity.key == new.key }) {
                try await db.from("transactions").update(HoldingMove(holding_id: target.id)).eq("holding_id", value: row.id).execute()
            } else {
                let details = HoldingDetails(printing: new.printing, condition: new.condition, grade_company: new.gradeCompany, grade: new.grade)
                try await db.from("holdings").update(details).eq("id", value: row.id).execute()
                if let i = holdingRows.firstIndex(where: { $0.id == row.id }) {
                    holdingRows[i].printing = new.printing
                    holdingRows[i].condition = new.condition
                    holdingRows[i].grade_company = new.gradeCompany
                    holdingRows[i].grade = new.grade
                }
            }
        }
        for i in transactions.indices where transactions[i].identity.key == old.key { transactions[i].identity = new }
        if let value = manualValues.removeValue(forKey: old.key), manualValues[new.key] == nil { manualValues[new.key] = value }
        renamed[old.key] = new
        recompute()
    }

    /// Take copies out without a sale (opened, lost, gave away, damaged): an adjustment with a
    /// negative quantity, like the website's "Remove". Their cost is written off, so it counts
    /// as a loss in your gains. Undo voids it.
    @MainActor
    func remove(_ identity: HoldingIdentity, quantity: Double, reason: String, date: String) async throws {
        try await log(identity: identity, type: "adjustment", date: date, quantity: -abs(quantity), unitPrice: 0, source: "ios", notes: reason)
        recompute()
        if let entry = transactions.last(where: { $0.kind == .adjustment && $0.identity == identity }) {
            Router.shared.undo = UndoItem(message: "Removed \(Int(abs(quantity))) · \(reason.lowercased())") { [weak self] in
                guard let self else { return }
                try? await self.log(identity: entry.identity, type: "correction", date: entry.date, quantity: 0, unitPrice: 0, correctsId: entry.id)
                self.recompute()
            }
        }
    }

    /// Delete a copy from your collection as if you'd never added it: every entry for it is
    /// voided (corrections, so the record is kept), and it leaves your value, cost and gains.
    /// Undo restores every entry.
    @MainActor
    func deleteCopy(_ identity: HoldingIdentity) async throws {
        let live = entries(for: identity)
        for t in live {
            try await log(identity: t.identity, type: "correction", date: t.date, quantity: 0, unitPrice: 0, correctsId: t.id)
        }
        recompute()
        Router.shared.undo = UndoItem(message: "Deleted from your collection") { [weak self] in
            guard let self else { return }
            for t in live {
                try? await self.log(identity: t.identity, type: "correction", date: t.date, quantity: t.quantity, unitPrice: t.unitPrice,
                                    fees: t.fees, shipping: t.shipping, tax: t.tax, correctsId: t.id)
            }
            self.recompute()
        }
    }

    /// Delete several copies at once (Collection's select mode), the same way as `deleteCopy`,
    /// with one Undo that restores them all.
    @MainActor
    func deleteCopies(_ identities: [HoldingIdentity]) async throws {
        // Every copy's entries, gathered before any are voided.
        let live = identities.flatMap { entries(for: $0) }
        guard !live.isEmpty else { return }
        var done: [Txn] = []
        defer {
            recompute()
            if !done.isEmpty {
                let restore = done
                let n = identities.count
                Router.shared.undo = UndoItem(message: "Deleted \(n) item\(n == 1 ? "" : "s")") { [weak self] in
                    guard let self else { return }
                    for t in restore {
                        try? await self.log(identity: t.identity, type: "correction", date: t.date, quantity: t.quantity, unitPrice: t.unitPrice,
                                            fees: t.fees, shipping: t.shipping, tax: t.tax, correctsId: t.id)
                    }
                    self.recompute()
                }
            }
        }
        for t in live {
            try await log(identity: t.identity, type: "correction", date: t.date, quantity: 0, unitPrice: 0, correctsId: t.id)
            done.append(t)
        }
    }

    /// Delete an entry: a correction with quantity 0 voids it. Offers Undo for a few seconds,
    /// which restores it with another correction carrying its values (history stays intact).
    @MainActor
    func delete(_ entry: Txn) async throws {
        try await log(identity: entry.identity, type: "correction", date: entry.date, quantity: 0, unitPrice: 0, correctsId: entry.id)
        recompute()
        Router.shared.undo = UndoItem(message: "Entry deleted") { [weak self] in
            try? await self?.correct(entry, date: entry.date, quantity: entry.quantity, unitPrice: entry.unitPrice, fees: entry.fees, shipping: entry.shipping)
        }
    }

    @MainActor
    private func log(
        identity: HoldingIdentity, type: String, date: String, quantity: Double, unitPrice: Double,
        fees: Double = 0, shipping: Double = 0, tax: Double = 0, source: String? = nil, notes: String? = nil, correctsId: String? = nil
    ) async throws {
        // A demo collection isn't saved anywhere: the entry is kept on the phone until you leave
        // the demo, so adding, selling and deals all work while you try things out.
        if demo != nil {
            transactions.append(Txn(
                id: "demo-\(UUID().uuidString.lowercased())", identity: identity, kind: Txn.Kind(rawValue: type) ?? .purchase, date: date,
                quantity: quantity, unitPrice: unitPrice, fees: fees, shipping: shipping, tax: tax, correctsId: correctsId,
                createdAt: ISO8601DateFormatter().string(from: Date()), source: source, notes: notes
            ))
            return
        }
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
        // Show the change at once (the heart fills on tap); the save follows. A demo keeps it on
        // the phone only. If the save fails, the list goes back and the error shows.
        let before = wishlist
        wishlist = items
        guard demo == nil, let userId else { return }
        do {
            try await persistWishlist(items, known: before, userId: userId)
        } catch {
            wishlist = before
            throw error
        }
    }

    @MainActor
    private func persistWishlist(_ items: [WishItem], known before: [WishItem], userId: String) async throws {
        // Pick up changes made on the website since loading, so neither side overwrites the other's additions.
        let remote: [WishItem]
        do {
            remote = try await UserState.load("wishlist", as: [WishItem].self) ?? []
        } catch {
            // Never read from the account this session: what's on screen may be a saved copy or
            // empty, so saving it could wipe the account's list. Refuse instead.
            guard syncedState.contains("wishlist") else {
                throw HoloError.server(code: nil, message: "Couldn't reach your account. Try again.")
            }
            try await UserState.save("wishlist", items, userId: userId)
            wishlist = items
            return
        }
        syncedState.insert("wishlist")
        // Anything this phone already knew about (including ones just removed) isn't new.
        let known = Set(before.map(\.id)).union(items.map(\.id))
        let addedElsewhere = remote.filter { !known.contains($0.id) }
        try await UserState.save("wishlist", items + addedElsewhere, userId: userId)
        wishlist = items + addedElsewhere
    }
}

extension CollectionStore {
    /// How a copy you hold moved over the last `days` (1, 7 or 30), in percent. A graded copy is
    /// priced from eBay sales and carries no change of its own, so it falls back to the card's
    /// own price feed, then to the change worked out from the card's price history.
    func move(_ h: HoldingView, days: Int) -> Double? {
        let own: Double? = days <= 1 ? h.change24hPct : (days <= 7 ? h.change7dPct : h.change30dPct)
        if let own { return own }
        let key = priceKey(h.identity.productId, h.identity.printing)
        if let p = prices[key] {
            let feed: Double? = days <= 1 ? p.change24hPct : (days <= 7 ? p.change7dPct : p.change30dPct)
            if let feed { return feed }
        }
        guard let pts = history[key], let last = pts.last?.price,
              let since = Calendar.current.date(byAdding: .day, value: -days, to: Date()) else { return nil }
        let from = Format.day(since)
        guard let then = pts.last(where: { $0.date <= from })?.price, then > 0 else { return nil }
        return (last - then) / then * 100
    }
}
