import Foundation

/// Collection analytics, ported from the website's `src/lib/finance/analytics.ts` and the
/// grouping helpers in `portfolio.ts`. Every return is time-weighted (built from `twrIndex`),
/// so buying and selling never show up as performance.
enum Analytics {
    struct Risk {
        var totalReturn = 0.0
        var annualized: Double?
        var volatility: Double?
        var maxDrawdown = 0.0
        var maxDrawdownFrom: String?
        var maxDrawdownTo: String?
        var currentDrawdown = 0.0
        var bestDay: (date: String, gain: Double)?
        var worstDay: (date: String, gain: Double)?
        var upDays: Double?
    }

    static func risk(_ points: [TimelinePoint]) -> Risk {
        guard points.count >= 2, let first = points.first, let last = points.last else { return Risk() }
        var r = Risk()
        r.totalReturn = first.twrIndex > 0 ? last.twrIndex / first.twrIndex - 1 : 0
        let days = Timeline.daysBetween(first.date, last.date)
        r.annualized = days >= 90 ? pow(1 + r.totalReturn, 365 / Double(days)) - 1 : nil

        let rets = points.dropFirst().map(\.dailyReturn)
        let mean = rets.reduce(0, +) / Double(rets.count)
        let variance = rets.reduce(0) { $0 + ($1 - mean) * ($1 - mean) } / Double(max(1, rets.count - 1))
        r.volatility = rets.count >= 20 ? variance.squareRoot() * Double(365).squareRoot() : nil

        var peak = first.twrIndex
        var peakDate = first.date
        for p in points {
            if p.twrIndex > peak { peak = p.twrIndex; peakDate = p.date }
            let dd = peak > 0 ? p.twrIndex / peak - 1 : 0
            if dd < r.maxDrawdown { r.maxDrawdown = dd; r.maxDrawdownFrom = peakDate; r.maxDrawdownTo = p.date }
        }
        r.currentDrawdown = peak > 0 ? last.twrIndex / peak - 1 : 0

        var up = 0
        var moved = 0
        for p in points.dropFirst() where abs(p.marketGain) >= 0.005 {
            moved += 1
            if p.marketGain > 0 { up += 1 }
            if r.bestDay == nil || p.marketGain > r.bestDay!.gain { r.bestDay = (p.date, p.marketGain) }
            if r.worstDay == nil || p.marketGain < r.worstDay!.gain { r.worstDay = (p.date, p.marketGain) }
        }
        r.upDays = moved > 0 ? Double(up) / Double(moved) : nil
        return r
    }

    /// How far below its running high the return index is on each day.
    static func drawdowns(_ points: [TimelinePoint]) -> [Double] {
        var peak = 0.0
        return points.map { p in
            peak = max(peak, p.twrIndex)
            return peak > 0 ? p.twrIndex / peak - 1 : 0
        }
    }

    struct MonthReturn: Identifiable {
        var year: Int
        /// 0-11
        var month: Int
        var ret: Double
        var gain: Double
        var id: String { "\(year)-\(month)" }
    }

    /// The return for each calendar month in the history (partial first and last months included).
    static func monthlyReturns(_ points: [TimelinePoint]) -> [MonthReturn] {
        var out: [MonthReturn] = []
        var start: TimelinePoint?
        var prevEnd: TimelinePoint?
        var gain = 0.0
        var key = ""
        func flush(_ end: TimelinePoint) {
            guard let base = prevEnd ?? start else { return }
            out.append(MonthReturn(year: Int(key.prefix(4)) ?? 0, month: (Int(key.dropFirst(5).prefix(2)) ?? 1) - 1,
                                   ret: base.twrIndex > 0 ? end.twrIndex / base.twrIndex - 1 : 0, gain: gain))
        }
        for (i, p) in points.enumerated() {
            let k = String(p.date.prefix(7))
            if k != key {
                if start != nil {
                    flush(points[i - 1])
                    prevEnd = points[i - 1]
                }
                key = k
                start = p
                gain = 0
            }
            if i > 0 { gain += p.marketGain }
        }
        if start != nil, let last = points.last { flush(last) }
        return out
    }

    struct Concentration {
        var top1 = 0.0
        var top5 = 0.0
        /// How many equal holdings this behaves like (1 / Σ share²).
        var effective = 0.0
    }

    static func concentration(_ holdings: [HoldingView]) -> Concentration {
        let values = holdings.compactMap(\.value).filter { $0 > 0 }.sorted(by: >)
        let total = values.reduce(0, +)
        guard total > 0 else { return Concentration() }
        let shares = values.map { $0 / total }
        return Concentration(top1: shares[0], top5: shares.prefix(5).reduce(0, +), effective: 1 / shares.reduce(0) { $0 + $1 * $1 })
    }

    struct Group: Identifiable {
        var name: String
        var value = 0.0
        var cost = 0.0
        var count = 0
        var gain: Double { value - cost }
        var ret: Double? { cost > 0 ? (value - cost) / cost : nil }
        var id: String { name }
    }

    /// Value and unrealized return by product type (Booster Box, Elite Trainer Box, Card…).
    static func byType(_ holdings: [HoldingView]) -> [Group] {
        var groups: [String: Group] = [:]
        for h in holdings {
            guard let v = h.value, let p = h.product else { continue }
            let name = h.identity.isGraded ? "Graded card" : category(p)
            var g = groups[name] ?? Group(name: name)
            g.value += v
            g.cost += h.costBasis
            g.count += 1
            groups[name] = g
        }
        return groups.values.sorted { $0.value > $1.value }
    }

    struct SetRow: Identifiable {
        var name: String
        var value = 0.0
        var cost = 0.0
        var holdings = 0
        var share = 0.0
        var gain: Double { value - cost }
        var ret: Double? { cost > 0 ? gain / cost : nil }
        var id: String { name }
    }

    static func bySet(_ holdings: [HoldingView]) -> [SetRow] {
        let total = holdings.reduce(0) { $0 + ($1.value ?? 0) }
        var rows: [String: SetRow] = [:]
        for h in holdings {
            let name = h.product?.setName ?? "Unknown set"
            var r = rows[name] ?? SetRow(name: name)
            r.holdings += 1
            if let v = h.value { r.value += v; r.cost += h.costBasis }
            rows[name] = r
        }
        return rows.values.map { r in var r = r; r.share = total > 0 ? r.value / total : 0; return r }.sorted { $0.value > $1.value }
    }

    struct Month: Identifiable {
        /// yyyy-MM
        var month: String
        var invested = 0.0
        var proceeds = 0.0
        var id: String { month }
        var date: Date { Format.isoDay.date(from: month + "-01") ?? Date() }
    }

    /// Money invested (and taken from sales) each month, with empty months filled in.
    static func monthlyActivity(_ transactions: [Txn], today: String) -> [Month] {
        var map: [String: Month] = [:]
        for t in Ledger.effective(transactions) where t.date <= today {
            let m = String(t.date.prefix(7))
            var row = map[m] ?? Month(month: m)
            if t.kind == .purchase || (t.kind == .adjustment && t.quantity > 0) { row.invested += t.acquisitionCost }
            if t.kind == .sale { row.proceeds += t.saleProceeds }
            map[m] = row
        }
        guard let firstKey = map.keys.min(), var y = Int(firstKey.prefix(4)), var mo = Int(firstKey.suffix(2)) else { return [] }
        let last = String(today.prefix(7))
        var out: [Month] = []
        while true {
            let key = String(format: "%04d-%02d", y, mo)
            out.append(map[key] ?? Month(month: key))
            if key >= last || out.count > 600 { break }
            mo += 1
            if mo > 12 { mo = 1; y += 1 }
        }
        return out
    }

    struct HeldPoint: Identifiable {
        var key: String
        var name: String
        var days: Int
        var ret: Double
        var value: Double
        var id: String { key }
    }

    /// Each priced holding's return against how long it has been held.
    static func returnVsTime(_ holdings: [HoldingView], today: String) -> [HeldPoint] {
        holdings.compactMap { h in
            guard let r = h.gainRatio, let v = h.value, let first = h.firstAcquired else { return nil }
            return HeldPoint(key: h.id, name: h.product?.name ?? "Unknown", days: max(0, Timeline.daysBetween(first, today)), ret: r, value: v)
        }
    }

    /// Average days held, weighted by current value.
    static func averageHoldDays(_ points: [HeldPoint]) -> Double? {
        let total = points.reduce(0) { $0 + $1.value }
        return total > 0 ? points.reduce(0) { $0 + Double($1.days) * $1.value } / total : nil
    }

    private static let rules: [(String, String)] = [
        (#"ultra[- ]premium collection|\bupc\b"#, "Ultra Premium Collection"),
        (#"elite trainer box|\betb\b"#, "Elite Trainer Box"),
        (#"booster bundle"#, "Booster Bundle"),
        (#"booster box|booster display|display box"#, "Booster Box"),
        (#"\btin\b"#, "Tin"),
        (#"collection|premium box|box set|\bbox\b"#, "Collection Box"),
        (#"booster pack|sleeved booster|\bblister\b|\bpack\b"#, "Booster Pack"),
    ]

    /// The website's display category (`categoryOf` in src/lib/catalog.ts).
    static func category(_ p: Product) -> String {
        if p.kind == "single" { return "Card" }
        let haystack = "\(p.productType ?? "") \(p.name)"
        for (re, cat) in rules where haystack.range(of: re, options: [.regularExpression, .caseInsensitive]) != nil { return cat }
        return "Other Sealed"
    }
}
