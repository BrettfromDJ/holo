import Foundation

struct TimelinePoint: Identifiable, Hashable {
    var date: String
    /// Market value of everything held that day (priced items only).
    var value: Double
    /// What those priced items cost.
    var cost: Double

    var id: String { date }
    var day: Date { Format.isoDay.date(from: date) ?? Date() }
}

/// The collection's value day by day, replaying the ledger like the web app's timeline.
enum Timeline {
    /// A stored price is carried forward at most this many days, then treated as unknown.
    static let maxCarryDays = 10

    static func compute(
        transactions: [Txn],
        prices: [String: Price],
        history: [String: [PricePoint]],
        manualValues: [String: ManualValue],
        ebayGraded: [String: Double] = [:],
        today: String
    ) -> [TimelinePoint] {
        let txs = Ledger.effective(transactions).filter { $0.date <= today }
        guard let first = txs.first?.date else { return [] }
        var ledger = Ledger()
        var idx = 0
        var out: [TimelinePoint] = []

        for day in days(from: first, to: today) {
            while idx < txs.count, txs[idx].date <= day {
                ledger.apply(txs[idx])
                idx += 1
            }
            var value = 0.0
            var cost = 0.0
            for pos in ledger.positions.values {
                let q = pos.quantity
                guard q > 1e-9, let price = price(pos.identity, on: day, today: today, prices: prices, history: history, manual: manualValues, ebay: ebayGraded) else { continue }
                value += q * price
                cost += pos.costBasis
            }
            out.append(TimelinePoint(date: day, value: value, cost: cost))
        }
        return out
    }

    /// Per-unit price of a position on a day, or nil when unknown.
    static func price(
        _ id: HoldingIdentity, on day: String, today: String,
        prices: [String: Price], history: [String: [PricePoint]], manual: [String: ManualValue], ebay: [String: Double] = [:]
    ) -> Double? {
        let key = priceKey(id.productId, id.printing)
        if id.isGraded {
            if let m = manual[id.key], m.date <= day { return m.value }
            // An eBay-priced slab follows the raw card's trend, scaled to its price today (as on the web).
            guard manual[id.key] == nil, let slab = ebay[id.key] else { return nil }
            if day >= today { return slab }
            guard let rawNow = prices[key]?.market, rawNow > 0, let pts = history[key], let p = lastAtOrBefore(pts, day),
                  daysBetween(p.date, day) <= maxCarryDays else { return nil }
            return p.price * slab / rawNow
        }
        var nm: Double?
        if day >= today, let p = prices[key], let market = p.market, p.status != "unavailable" {
            nm = market
        } else if let pts = history[key], let p = lastAtOrBefore(pts, day), daysBetween(p.date, day) <= maxCarryDays {
            nm = p.price
        }
        return nm.map { $0 * CardCondition.share(for: id.condition) }
    }

    private static func lastAtOrBefore(_ pts: [PricePoint], _ day: String) -> PricePoint? {
        var lo = 0
        var hi = pts.count - 1
        var found: PricePoint?
        while lo <= hi {
            let mid = (lo + hi) / 2
            if pts[mid].date <= day {
                found = pts[mid]
                lo = mid + 1
            } else {
                hi = mid - 1
            }
        }
        return found
    }

    private static let calendar = Calendar(identifier: .gregorian)

    static func daysBetween(_ a: String, _ b: String) -> Int {
        guard let da = Format.isoDay.date(from: a), let db = Format.isoDay.date(from: b) else { return .max }
        return calendar.dateComponents([.day], from: da, to: db).day ?? .max
    }

    static func days(from start: String, to end: String) -> [String] {
        guard var d = Format.isoDay.date(from: start), let last = Format.isoDay.date(from: end) else { return [] }
        var out: [String] = []
        while d <= last {
            out.append(Format.isoDay.string(from: d))
            guard let next = calendar.date(byAdding: .day, value: 1, to: d) else { break }
            d = next
        }
        return out
    }
}
