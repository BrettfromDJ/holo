import Foundation

/// The owner's own valuation of a graded slab, from a date on.
struct ManualValue: Hashable {
    var value: Double
    var date: String
}

/// One position as the app shows it: what you hold, what it cost, what it's worth.
struct HoldingView: Identifiable, Hashable {
    var identity: HoldingIdentity
    var product: Product?
    var quantity: Double
    var costBasis: Double
    var realizedGain: Double
    /// Per-unit price; nil when unknown (never counted as zero).
    var price: Double?
    /// True when the price is estimated from Near Mint for a played copy.
    var isConditionEstimate: Bool
    /// True when the price is the owner's own valuation (graded slabs).
    var isManual: Bool
    var change24hPct: Double?
    var change7dPct: Double?
    var change30dPct: Double?
    var lastAcquired: String?
    /// Units still held, oldest first (what a sale consumes).
    var lots: [Lot] = []
    var firstAcquired: String?

    var id: String { identity.key }
    var value: Double? { price.map { $0 * quantity } }
    var gain: Double? { value.map { $0 - costBasis } }
    var gainRatio: Double? {
        guard let g = gain, costBasis > 0 else { return nil }
        return g / costBasis
    }
    var avgCost: Double { quantity > 0 ? costBasis / quantity : 0 }

    /// Cost of the oldest `qty` units: what selling that many would take off the books.
    func fifoCost(_ qty: Double) -> Double {
        var remaining = qty
        var cost = 0.0
        for lot in lots where remaining > 0 {
            let take = min(lot.quantity, remaining)
            cost += take * lot.unitCost
            remaining -= take
        }
        return cost
    }

    /// "Lightly Played", "PSA 10", or nil for Near Mint / sealed.
    var label: String? {
        if let g = identity.gradeLabel { return g }
        if identity.condition == "Near Mint" || identity.condition == "Sealed" { return nil }
        return identity.condition
    }

    /// Market-driven change since yesterday, from the source's 24h move.
    var dayChange: Double? {
        guard let v = value, let pct = change24hPct, !isManual else { return nil }
        let factor = 1 + pct / 100
        guard factor > 0 else { return nil }
        return v - v / factor
    }
}

struct PortfolioSummary {
    var value: Double = 0
    /// Cost of the holdings that have a price (pairs with `value`).
    var pricedCost: Double = 0
    var totalCost: Double = 0
    var dayChange: Double = 0
    var realized: Double = 0
    var unpriced: Int = 0
    var items: Double = 0

    var gain: Double { value - pricedCost }
    var gainRatio: Double? { pricedCost > 0 ? gain / pricedCost : nil }
    var dayRatio: Double? {
        let before = value - dayChange
        return before > 0 ? dayChange / before : nil
    }
}

enum Portfolio {
    /// Value every open position. Raw copies use the Near Mint market price,
    /// times their condition's share when played (marked as an estimate);
    /// graded copies use the owner's value, else recent eBay sales for the grade.
    static func holdings(
        transactions: [Txn],
        products: [String: Product],
        prices: [String: Price],
        manualValues: [String: ManualValue],
        ebayGraded: [String: Double] = [:],
        conditionShares: [String: Double] = [:]
    ) -> [HoldingView] {
        let ledger = Ledger(transactions)
        return ledger.positions.values.compactMap { pos -> HoldingView? in
            let qty = pos.quantity
            guard qty > 1e-9 else { return nil }
            let id = pos.identity
            var price: Double?
            var estimate = false
            var manual = false
            var change: Double?
            var change7: Double?
            var change30: Double?
            if id.isGraded {
                // Your own value wins; else the median of recent eBay sales for that exact grade.
                if let m = manualValues[id.key] {
                    price = m.value
                    manual = true
                } else if let e = ebayGraded[id.key] {
                    price = e
                }
            } else if let p = prices[priceKey(id.productId, id.printing)], let market = p.market, p.status != "unavailable" {
                let share = CardCondition.share(for: id, measured: conditionShares)
                price = (market * share * 100).rounded() / 100
                estimate = share < 1
                change = p.change24hPct
                change7 = p.change7dPct
                change30 = p.change30dPct
            }
            return HoldingView(
                identity: id, product: products[id.productId], quantity: qty, costBasis: pos.costBasis,
                realizedGain: pos.realizedGain, price: price, isConditionEstimate: estimate, isManual: manual,
                change24hPct: change, change7dPct: change7, change30dPct: change30, lastAcquired: pos.lastAcquired, lots: pos.lots, firstAcquired: pos.firstAcquired
            )
        }
        .sorted { ($0.value ?? -1) > ($1.value ?? -1) }
    }

    static func summary(_ holdings: [HoldingView], realized: Double) -> PortfolioSummary {
        var s = PortfolioSummary()
        s.realized = realized
        for h in holdings {
            s.totalCost += h.costBasis
            s.items += h.quantity
            if let v = h.value {
                s.value += v
                s.pricedCost += h.costBasis
                s.dayChange += h.dayChange ?? 0
            } else {
                s.unpriced += 1
            }
        }
        return s
    }
}
