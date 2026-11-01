import Foundation

/// "Sells fast": how easy a card (or one grade of it) is to sell, 0 to 100, from this month's
/// eBay sales we already have. Four parts: how many sold (30 a month is full marks), how close the
/// prices were (the middle half's spread against the median), how recently one sold, and how
/// rarely buyers talked the price down. Same math as the website's `sellSpeed`
/// (src/lib/liquidity.ts); `LiquidityTests` checks the same cases.
enum Liquidity {
    enum Tier: String {
        case fast = "Sells fast"
        case steady = "Sells steady"
        case slow = "Slow to sell"

        /// Filled segments of the 3-segment meter.
        var segments: Int {
            switch self {
            case .fast: return 3
            case .steady: return 2
            case .slow: return 1
            }
        }
    }

    struct Score: Hashable {
        /// 0–100.
        var score: Int
        var tier: Tier
        /// How many sold this month for this grade (or ungraded).
        var sold: Int
    }

    static let note = "Based on this month's eBay sales: how many sold, how close the prices were, how recently, and how often buyers talked the price down."

    static func tier(_ score: Int) -> Tier {
        score >= 70 ? .fast : score >= 40 ? .steady : .slow
    }

    /// Linear-interpolated quantile of sorted numbers (q from 0 to 1), like the website's.
    static func quantile(_ sorted: [Double], _ q: Double) -> Double {
        let pos = Double(sorted.count - 1) * q
        let lo = Int(pos.rounded(.down))
        let hi = Int(pos.rounded(.up))
        return sorted[lo] + (sorted[hi] - sorted[lo]) * (pos - Double(lo))
    }

    private static let utc: Calendar = {
        var c = Calendar(identifier: .gregorian)
        c.timeZone = TimeZone(identifier: "UTC")!
        return c
    }()

    /// Calendar days between two ISO dates (or timestamps; only the date part is read).
    static func dayGap(_ from: String, _ to: String) -> Int? {
        func day(_ s: String) -> Date? {
            let parts = s.prefix(10).split(separator: "-").compactMap { Int($0) }
            guard parts.count == 3 else { return nil }
            return utc.date(from: DateComponents(year: parts[0], month: parts[1], day: parts[2]))
        }
        guard let a = day(from), let b = day(to) else { return nil }
        return Int((b.timeIntervalSince(a) / 86_400).rounded())
    }

    private static func clamp01(_ x: Double) -> Double { min(1, max(0, x)) }

    /// The score for one grade label ("PSA 10"), or ungraded copies when `grade` is nil. Nil when
    /// there isn't enough to go on (fewer than 2 sold and fewer than 2 sales listed).
    /// A CGC 10 comes in two kinds: pass `pristine` (or the label "CGC Pristine 10" / "CGC Gem
    /// Mint 10") to score a Pristine 10 on sales whose title says pristine only, and a Gem Mint 10
    /// on the rest. Without it, "CGC 10" scores every CGC 10 sale.
    static func score(_ ebay: EbaySales?, grade: String?, today: String, pristine: Bool? = nil) -> Score? {
        guard let ebay else { return nil }
        var label = grade
        if grade == Pristine.cgcTen, let pristine { label = pristine ? Pristine.pristineLabel : Pristine.gemMintLabel }
        let stats: EbayStats?
        let sales: [EbaySale]
        if let label {
            stats = Pristine.stats(ebay, label: label)
            sales = Pristine.sales(ebay, label: label)
        } else {
            stats = ebay.ungraded
            sales = ebay.sales.filter { $0.grade == nil }
        }
        let count = stats?.count ?? 0
        if count < 2 && sales.count < 2 { return nil }

        // Volume: 30 sales a month is full marks.
        let v = min(1, log(1 + Double(count)) / log(1 + 30))

        // Tightness: the middle half's spread against the median.
        var t = 0.5
        let prices = sales.map(\.price).sorted()
        if prices.count >= 3 {
            let median = quantile(prices, 0.5)
            if median > 0 {
                let spread = (quantile(prices, 0.75) - quantile(prices, 0.25)) / median
                t = clamp01(1 - spread / 0.6)
            }
        }

        // Recency: days since the latest sale; a month or more counts for nothing.
        var newest = stats?.lastSold
        if newest == nil || newest?.isEmpty == true {
            newest = sales.map(\.soldDate).max()
        }
        let days = newest.flatMap { dayGap($0, today) }
        let r = days.map { clamp01(1 - Double(max(0, $0)) / 30) } ?? 0

        // Discount: the share of sales that were best offers well under the asking price.
        let talkedDown = sales.filter { s in
            guard s.bestOffer, let list = s.listPrice else { return false }
            return s.price < 0.95 * list
        }.count
        let b = sales.isEmpty ? 1 : 1 - Double(talkedDown) / Double(sales.count)

        let raw = 100 * (0.5 * v + 0.25 * t + 0.15 * r + 0.1 * b)
        let score = Int(raw.rounded())
        return Score(score: score, tier: tier(score), sold: count)
    }
}
