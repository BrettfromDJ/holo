import Foundation

struct TimelinePoint: Identifiable, Hashable {
    var date: String
    /// Market value of everything held that day (priced items only).
    var value: Double
    /// What those priced items cost.
    var cost: Double
    /// Mark-to-market change on units held at the previous close (buying and selling excluded).
    var marketGain: Double = 0
    /// The day's return: marketGain over the previous value of those units.
    var dailyReturn: Double = 0
    /// Daily returns chained from 1, so buying and selling never count as performance.
    var twrIndex: Double = 1

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
        conditionShares: [String: Double] = [:],
        today: String
    ) -> [TimelinePoint] {
        let txs = Ledger.effective(transactions).filter { $0.date <= today }
        guard let first = txs.first?.date else { return [] }
        var ledger = Ledger()
        var idx = 0
        var out: [TimelinePoint] = []
        var prevQty: [String: Double] = [:]
        var prevPrice: [String: Double] = [:]
        var twr = 1.0

        for day in days(from: first, to: today) {
            while idx < txs.count, txs[idx].date <= day {
                ledger.apply(txs[idx])
                idx += 1
            }
            var value = 0.0
            var cost = 0.0
            var gain = 0.0
            var denom = 0.0
            var curQty: [String: Double] = [:]
            var curPrice: [String: Double] = [:]
            for (key, pos) in ledger.positions {
                let q = pos.quantity
                let qPrev = prevQty[key] ?? 0
                guard q > 1e-9 || qPrev > 1e-9 else { continue }
                let p = price(pos.identity, on: day, today: today, prices: prices, history: history, manual: manualValues, ebay: ebayGraded, shares: conditionShares)
                if q > 1e-9 {
                    curQty[key] = q
                    if let p {
                        value += q * p
                        cost += pos.costBasis
                    }
                }
                if let p {
                    curPrice[key] = p
                    if qPrev > 1e-9, let pPrev = prevPrice[key] {
                        gain += qPrev * (p - pPrev)
                        denom += qPrev * pPrev
                    }
                }
            }
            let ret = denom > 0 ? gain / denom : 0
            twr *= 1 + ret
            out.append(TimelinePoint(date: day, value: value, cost: cost, marketGain: gain, dailyReturn: ret, twrIndex: twr))
            prevQty = curQty
            prevPrice = curPrice
        }
        return out
    }

    /// Per-unit price of a position on a day, or nil when unknown.
    static func price(
        _ id: HoldingIdentity, on day: String, today: String,
        prices: [String: Price], history: [String: [PricePoint]], manual: [String: ManualValue], ebay: [String: Double] = [:],
        shares: [String: Double] = [:]
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
        return nm.map { $0 * CardCondition.share(for: id, measured: shares) }
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
