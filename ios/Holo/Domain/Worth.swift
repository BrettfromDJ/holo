import Foundation

/// "What's it worth?" for one card in one condition or grade, with where the number came from.
/// Ported from the web app (src/lib/worth.ts and the grade curve in src/lib/graded.ts).
struct Worth: Hashable {
    enum Source: String { case market, sales, guide, estimate }

    var price: Double
    var source: Source
    /// Plain-language note on where the number came from.
    var detail: String
    var sold: Int?

    var isEstimate: Bool { source == .estimate }
}

enum WorthCalc {
    /// A median needs at least this many sales to stand on its own.
    static let minSales = 2

    /// A raw copy: Near Mint is the market price; other conditions use TCGplayer's price
    /// for that condition, then eBay sales in it, then a share of Near Mint.
    static func raw(nm: Double, condition: CardCondition, ebay: EbaySales?, conditions: [ConditionPrice], printing: String?) -> Worth {
        if condition == .nearMint { return Worth(price: nm, source: .market, detail: "TCGplayer market price, Near Mint") }
        let rows = conditions.filter { $0.condition == condition.rawValue && $0.price != nil }
        if let listed = rows.first(where: { $0.printing == printing }) ?? rows.first, let price = listed.price {
            return Worth(
                price: round2(price), source: .market,
                detail: listed.basis == "median" ? "TCGplayer \(condition.rawValue) listings · median of \(listed.samples)" : "Lowest TCGplayer \(condition.rawValue) listing"
            )
        }
        let sales = (ebay?.sales ?? []).filter { $0.grade == nil && $0.condition == condition.rawValue }.map(\.price).sorted()
        if sales.count >= minSales + 1 {
            let m = sales.count / 2
            let median = sales.count % 2 == 1 ? sales[m] : (sales[m - 1] + sales[m]) / 2
            return Worth(price: round2(median), source: .sales, detail: "Median of \(sales.count) \(condition.rawValue) eBay sales this month", sold: sales.count)
        }
        return Worth(price: round2(nm * condition.share), source: .estimate, detail: "Estimated at \(Int(condition.share * 100))% of Near Mint")
    }

    /// A graded copy: recent eBay sales for that exact grade, else the usual grade curve (always labeled an estimate).
    static func graded(productId: String, nm: Double, company: String, grade: String, ebay: EbaySales?) -> Worth {
        let label = "\(company) \(grade)"
        if let sold = ebay?.graded[label], sold.count >= minSales, let median = sold.median {
            return Worth(price: median, source: .sales, detail: "Median of \(sold.count) \(label) eBay sales this month", sold: sold.count)
        }
        return Worth(price: round2(nm * multiple(productId: productId, company: company, grade: grade)), source: .estimate, detail: "No recent sales · from the usual grade curve")
    }

    // MARK: Grade curve

    /// Typical multiple of the raw price, by grade (PSA scale).
    private static let gradeMultiple: [(Double, Double)] = [(10, 5.2), (9.5, 2.6), (9, 1.75), (8.5, 1.4), (8, 1.22), (7, 0.98), (6, 0.82), (5, 0.7), (0, 0.55)]
    /// How each company's slabs trade relative to PSA at the same grade.
    private static let companyFactor: [String: Double] = ["PSA": 1, "BGS": 1.05, "CGC": 0.72, "SGC": 0.7, "TAG": 0.66]

    /// Multiple of the raw price for this product and grade, stable per product (same as the web).
    static func multiple(productId: String, company: String, grade: String) -> Double {
        let n = Double(grade) ?? 0
        let c = company.uppercased()
        var base = gradeMultiple.first { n >= $0.0 }?.1 ?? 0.55
        if c == "BGS" && n >= 10 { base *= 1.8 }
        let factor = companyFactor[c] ?? 0.7
        let jitter = 0.82 + stableHash("\(productId)|\(c)|\(grade)") * 0.36
        return max(0.4, base * factor * jitter)
    }

    /// FNV-1a over UTF-16 code units, like the web's hash().
    static func stableHash(_ s: String) -> Double {
        var h: UInt32 = 2_166_136_261
        for unit in s.utf16 { h = (h ^ UInt32(unit)) &* 16_777_619 }
        return Double(h) / 4_294_967_295
    }

    /// Grades each company gives: whole grades, plus halves where they use them.
    static func grades(for company: String) -> [String] {
        let whole = (1...10).map(String.init)
        if company == "BGS" || company == "CGC" { return Array(whole.prefix(7)) + ["7.5", "8", "8.5", "9", "9.5", "10"] }
        return whole
    }
}

/// eBay summary for a printing: the matching one, else the first.
func summaryFor(_ rows: [EbaySummary]?, printing: String?) -> EbaySummary? {
    guard let rows else { return nil }
    return rows.first { $0.printing == printing } ?? rows.first
}

/// Whether a raw card is worth grading, ported from the website's `gradingOutlook` (src/lib/graded.ts).
enum Grading {
    /// Raw cards below this price rarely cover the cost of grading.
    static let minRaw = 15.0

    struct Costs: Codable, Hashable {
        /// Grading fee per card.
        var fee = 25.0
        /// Shipping and insurance per card, both ways.
        var shipping = 12.0
    }

    enum Source { case sales, estimate }

    struct Outlook {
        var raw: Double
        var cost: Double
        var psa10: Double
        var psa9: Double
        /// Profit over selling raw if it comes back a PSA 10, after costs.
        var upside10: Double
        /// Profit over selling raw at a PSA 9 (negative means a 9 loses money).
        var upside9: Double
        /// PSA 10 sales per year.
        var psa10Sales: Double
        /// Upside at a 10, discounted when PSA 10s rarely sell. Used for ranking.
        var score: Double
        var source: Source
    }

    /// PSA 10 and 9 prices from eBay when they've sold, else the usual grade curve (an estimate).
    static func outlook(productId: String, raw: Double, costs: Costs, summary: EbaySummary?) -> Outlook {
        let cost = costs.fee + costs.shipping
        let curve10 = (raw * WorthCalc.multiple(productId: productId, company: "PSA", grade: "10") * 100).rounded() / 100
        let curve9 = (raw * WorthCalc.multiple(productId: productId, company: "PSA", grade: "9") * 100).rounded() / 100
        let g10 = summary?.graded["PSA 10"]
        let g9 = summary?.graded["PSA 9"]
        let sold10 = g10?.median ?? g10?.lastPrice
        let sold9 = g9?.median ?? g9?.lastPrice
        let psa10 = sold10 ?? curve10
        let psa9 = sold9 ?? curve9
        let perYear = summary != nil ? Double(g10?.count ?? 0) * 12 : salesPerYear(productId: productId, grade: ("PSA", "10"), raw: raw)
        let upside10 = psa10 - raw - cost
        return Outlook(raw: raw, cost: cost, psa10: psa10, psa9: psa9, upside10: upside10, upside9: psa9 - raw - cost,
                       psa10Sales: perYear, score: upside10 * weight(perYear),
                       source: sold10 != nil && sold9 != nil ? .sales : .estimate)
    }

    /// The website's estimate of copies sold per year when there are no sales figures.
    static func salesPerYear(productId: String, grade: (company: String, grade: String)?, raw: Double?) -> Double {
        let price = raw ?? 50
        let base: Double = price < 20 ? 420 : price < 100 ? 220 : price < 500 ? 90 : 34
        var factor = 1.0
        if let grade {
            let n = Double(grade.grade) ?? 0
            factor = grade.company.uppercased() == "PSA" ? (n >= 10 ? 0.14 : n >= 9 ? 0.3 : n >= 8 ? 0.2 : 0.1) : n >= 10 ? 0.05 : 0.08
        }
        let jitter = 0.4 + WorthCalc.stableHash("\(productId)|\(grade.map { "\($0.company) \($0.grade)" } ?? "raw")|sales") * 1.2
        return max(1, (base * factor * jitter).rounded())
    }

    /// "Easy to sell", "Sells steadily" or "Hard to sell": weekly, monthly, or less.
    static func liquidity(_ perYear: Double) -> String {
        perYear >= 52 ? "Easy to sell" : perYear >= 12 ? "Sells steadily" : "Hard to sell"
    }

    static func weight(_ perYear: Double) -> Double { perYear >= 52 ? 1 : perYear >= 12 ? 0.8 : 0.4 }
}

extension Grading {
    /// Where to check a certification number, like the website's certLookupUrl. Companies
    /// without a direct link get their lookup page.
    static func certLookupURL(company: String, cert: String) -> String {
        let c = cert.trimmingCharacters(in: .whitespaces).addingPercentEncoding(withAllowedCharacters: .urlPathAllowed) ?? cert
        switch company.uppercased() {
        case "PSA": return "https://www.psacard.com/cert/\(c)"
        case "CGC": return "https://www.cgccards.com/certlookup/\(c)/"
        case "BGS": return "https://www.beckett.com/grading/card-lookup"
        case "SGC": return "https://gosgc.com/cert-code-lookup"
        case "TAG": return "https://my.taggrading.com/card/\(c)"
        default:
            let q = "\(company) cert \(cert)".addingPercentEncoding(withAllowedCharacters: .urlQueryAllowed) ?? ""
            return "https://www.google.com/search?q=\(q)"
        }
    }
}
