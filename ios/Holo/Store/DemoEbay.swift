import Foundation

/// Sample eBay sold listings for demo products (`sample:` ids), made up on the phone so demos
/// show eBay sales and the "Sells fast" meter without a request. Ported from the website's
/// `sampleEbaySales` (src/lib/ebay-sample.ts): ungraded copies around the market price, graded
/// copies on the usual premiums and sales pace. The same card gets the same sales every time.
enum DemoEbay {
    /// Grades sample sales are made for, like the website's LADDER.
    private static let ladder: [(company: String, grade: String)] = [("PSA", "10"), ("PSA", "9"), ("PSA", "8"), ("BGS", "9.5"), ("CGC", "10"), ("SGC", "10")]

    /// Conditions sold, weighted toward Near Mint, with each one's share of the market price.
    private static let conditions: [(String, Double)] = [
        ("Mint", 1.08), ("Near Mint", 1), ("Near Mint", 1), ("Near Mint", 1), ("Near Mint", 1), ("Near Mint", 1),
        ("Near Mint", 1), ("Near Mint", 1), ("Lightly Played", 0.82), ("Lightly Played", 0.82),
        ("Moderately Played", 0.66), ("Heavily Played", 0.5), ("Damaged", 0.35),
    ]

    /// Seeded random numbers (mulberry32, like the website), so a card's sales are stable.
    private struct Seeded {
        var a: UInt32
        init(_ seed: String) {
            var h: UInt32 = 2_166_136_261
            for unit in seed.utf16 { h = (h ^ UInt32(unit)) &* 16_777_619 }
            a = h
        }
        mutating func next() -> Double {
            a = a &+ 0x6D2B_79F5
            var t = a
            t = (t ^ (t >> 15)) &* (t | 1)
            t ^= t &+ ((t ^ (t >> 7)) &* (t | 61))
            return Double(t ^ (t >> 14)) / 4_294_967_296
        }
    }

    /// Typical sales a year for a card (or one grade of it), like the website's sampleSalesPerYear.
    private static func salesPerYear(_ productId: String, grade: (company: String, grade: String)?, raw: Double) -> Double {
        let base: Double = raw < 20 ? 420 : raw < 100 ? 220 : raw < 500 ? 90 : 34
        var factor = 1.0
        var label = "raw"
        if let grade {
            let n = Double(grade.grade) ?? 0
            factor = grade.company == "PSA" ? (n >= 10 ? 0.14 : n >= 9 ? 0.3 : n >= 8 ? 0.2 : 0.1) : (n >= 10 ? 0.05 : 0.08)
            label = "\(grade.company) \(grade.grade)"
        }
        let jitter = 0.4 + WorthCalc.stableHash("\(productId)|\(label)|sales") * 1.2
        return max(1, (base * factor * jitter).rounded())
    }

    private static let utcDay: DateFormatter = {
        let f = DateFormatter()
        f.calendar = Calendar(identifier: .gregorian)
        f.locale = Locale(identifier: "en_US_POSIX")
        f.timeZone = TimeZone(identifier: "UTC")
        f.dateFormat = "yyyy-MM-dd"
        return f
    }()

    private static func round2(_ x: Double) -> Double { (x * 100).rounded() / 100 }

    private static func median(_ xs: [Double]) -> Double? {
        guard !xs.isEmpty else { return nil }
        let s = xs.sorted()
        let m = s.count / 2
        return round2(s.count % 2 == 1 ? s[m] : (s[m - 1] + s[m]) / 2)
    }

    private static func stats(_ sales: [EbaySale]) -> EbayStats {
        EbayStats(median: median(sales.map(\.price)), count: sales.count, lastPrice: sales.first?.price, lastSold: sales.first?.soldDate)
    }

    static func sales(productId: String, name: String, printing: String?, market: Double?, today: String = Format.day()) -> EbaySales? {
        guard let market, market > 0 else { return nil }
        var rand = Seeded("\(productId)|\(printing ?? "")|ebay")
        let start = utcDay.date(from: today) ?? Date()
        func search(_ extra: String) -> String {
            var c = URLComponents(string: "https://www.ebay.com/sch/i.html")
            c?.queryItems = [URLQueryItem(name: "_nkw", value: "\(name) \(extra)".trimmingCharacters(in: .whitespaces)), URLQueryItem(name: "LH_Sold", value: "1"), URLQueryItem(name: "LH_Complete", value: "1")]
            return c?.url?.absoluteString ?? "https://www.ebay.com"
        }
        func make(_ grade: (company: String, grade: String)?, count: Int, center: Double) -> [EbaySale] {
            (0..<count).map { _ in
                let pick = grade == nil ? conditions[min(conditions.count - 1, Int(rand.next() * Double(conditions.count)))] : ("", 1.0)
                let price = round2(center * pick.1 * (0.86 + rand.next() * 0.26))
                let bestOffer = rand.next() < 0.22
                let label = grade.map { "\($0.company) \($0.grade)" }
                let listPrice: Double? = bestOffer ? round2(price * (1.08 + rand.next() * 0.18)) : nil
                let back = Int(rand.next() * 30)
                let day = Calendar(identifier: .gregorian).date(byAdding: .day, value: -back, to: start) ?? start
                let condition: String? = grade == nil ? pick.0 : nil
                let title = [label, name, printing.flatMap { $0 == "Normal" ? nil : $0 }, condition.map { $0 == "Near Mint" ? "NM" : $0 }]
                    .compactMap { $0 }.joined(separator: " ")
                return EbaySale(soldDate: utcDay.string(from: day), price: price, bestOffer: bestOffer, listPrice: listPrice,
                                grade: label, condition: condition, title: title, url: search(label ?? ""))
            }
        }
        let byNewest: (EbaySale, EbaySale) -> Bool = { $0.soldDate > $1.soldDate }

        let rawCount = max(6, min(40, Int((salesPerYear(productId, grade: nil, raw: market) / 12 * 1.6).rounded())))
        let ungraded = make(nil, count: rawCount, center: market).sorted(by: byNewest)
        var graded: [String: EbayStats] = [:]
        var all = ungraded
        for g in ladder {
            let pace = salesPerYear(productId, grade: g, raw: market) / 12 * (1 + rand.next() * 1.2)
            let count = min(25, max(g.company == "PSA" ? 2 : 0, Int(pace.rounded())))
            guard count > 0 else { continue }
            let center = market * WorthCalc.multiple(productId: productId, company: g.company, grade: g.grade)
            let sales = make(g, count: count, center: center).sorted(by: byNewest)
            graded["\(g.company) \(g.grade)"] = stats(sales)
            all += sales
        }
        return EbaySales(printing: printing, ungraded: stats(ungraded), graded: graded, sales: all.sorted(by: byNewest), asOf: today)
    }
}
