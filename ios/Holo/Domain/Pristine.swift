import Foundation

/// CGC 10s come in two kinds: Pristine 10 (the gold label) and Gem Mint 10. eBay files both under
/// "CGC 10", so the two are told apart by the listing's title: one that says "pristine" (any case)
/// is a Pristine 10, the rest are Gem Mint 10s. A slab is marked Pristine per holding
/// (`slab-pristine`, `GradingStore.pristine`). Same as the website's src/lib/pristine.ts;
/// `PristineTests` checks the same cases.
enum Pristine {
    /// What a Pristine 10 usually sells for against a Gem Mint 10 of the same card.
    static let pristinePremium = 1.6

    static let cgcTen = "CGC 10"
    static let pristineLabel = "CGC Pristine 10"
    static let gemMintLabel = "CGC Gem Mint 10"

    /// Sales this far back (days before the eBay data's `asOf`) count toward the count and median.
    static let windowDays = 30

    /// The holding keys marked Pristine, kept here by `GradingStore` so the collection's slab
    /// prices (`CollectionStore.loadSlabPrices`) can read them.
    static var marked: Set<String> = []

    static func isPristineTitle(_ title: String) -> Bool {
        title.range(of: "pristine", options: .caseInsensitive) != nil
    }

    /// A CGC 10 (only those can be Pristine).
    static func isCGCTen(company: String?, grade: String?) -> Bool {
        (company ?? "").uppercased() == "CGC" && (Double(grade ?? "") ?? 0) >= 10
    }

    /// The label a slab's sales are read under: "CGC Pristine 10" or "CGC Gem Mint 10" for a CGC 10, else "PSA 10" and so on.
    static func label(company: String, grade: String, pristine: Bool) -> String {
        guard isCGCTen(company: company, grade: grade) else { return "\(company) \(grade)" }
        return pristine ? pristineLabel : gemMintLabel
    }

    /// CGC 10 sales of one kind, in the order listed (newest first).
    static func cgcTenSales(_ ebay: EbaySales, pristine: Bool) -> [EbaySale] {
        ebay.sales.filter { $0.grade == cgcTen && isPristineTitle($0.title) == pristine }
    }

    /// Figures for a set of sales, like eBay's own: the count and median of the last 30 days
    /// (before `asOf`), and the latest sale whenever it was. Nil when there are no sales at all.
    static func stats(of sales: [EbaySale], asOf: String) -> EbayStats? {
        guard var newest = sales.first else { return nil }
        let recent = sales.filter { s in
            guard let gap = Liquidity.dayGap(s.soldDate, asOf) else { return true }
            return gap <= windowDays
        }
        let prices = recent.map(\.price).sorted()
        var median: Double?
        if !prices.isEmpty {
            let m = prices.count / 2
            let mid = prices.count % 2 == 1 ? prices[m] : (prices[m - 1] + prices[m]) / 2
            median = (mid * 100).rounded() / 100
        }
        for s in sales where s.soldDate > newest.soldDate { newest = s }
        return EbayStats(median: median, count: recent.count, lastPrice: newest.price, lastSold: newest.soldDate)
    }

    /// eBay figures under a label. "CGC Pristine 10" is the CGC 10 sales whose title says
    /// pristine; "CGC Gem Mint 10" is the rest (when no listing says pristine, that's every CGC
    /// 10 sale, so eBay's own "CGC 10" figures stand). Any other label is eBay's own figures.
    static func stats(_ ebay: EbaySales?, label: String) -> EbayStats? {
        guard let ebay else { return nil }
        if label == pristineLabel { return stats(of: cgcTenSales(ebay, pristine: true), asOf: ebay.asOf) }
        if label == gemMintLabel {
            if !ebay.sales.contains(where: { $0.grade == cgcTen && isPristineTitle($0.title) }) { return ebay.graded[cgcTen] }
            return stats(of: cgcTenSales(ebay, pristine: false), asOf: ebay.asOf)
        }
        return ebay.graded[label]
    }

    /// The listings under a label (the two CGC 10 kinds split by title, as `stats(_:label:)`).
    static func sales(_ ebay: EbaySales, label: String) -> [EbaySale] {
        if label == pristineLabel { return cgcTenSales(ebay, pristine: true) }
        if label == gemMintLabel { return cgcTenSales(ebay, pristine: false) }
        return ebay.sales.filter { $0.grade == label }
    }

    enum Basis { case sales, premium, other }

    /// What a CGC 10 in your collection is worth.
    /// - Gem Mint 10: the median of its sales when there are at least 2 (`WorthCalc.minSales`),
    ///   else the price guide (PriceCharting's one "CGC 10" price, read as a Gem Mint 10), else
    ///   its median or last sale.
    /// - Pristine 10: the median of Pristine sales when there are at least 2, else the Gem Mint
    ///   10's value × `pristinePremium`, else the Pristine median or last sale.
    /// Nil when nothing prices it. Same as the website's `cgcTenValue`.
    static func cgcTenValue(gem: EbayStats?, pristineStats: EbayStats?, guide: Double?, pristine: Bool) -> (value: Double, basis: Basis)? {
        var gemValue: (value: Double, basis: Basis)?
        if let gem, gem.count >= WorthCalc.minSales, let median = gem.median {
            gemValue = (value: median, basis: .sales)
        } else if let guide {
            gemValue = (value: guide, basis: .other)
        } else if let v = gem?.median ?? gem?.lastPrice {
            gemValue = (value: v, basis: .other)
        }
        guard pristine else { return gemValue }
        if let p = pristineStats, p.count >= WorthCalc.minSales, let median = p.median { return (value: median, basis: .sales) }
        if let gemValue { return (value: (gemValue.value * pristinePremium * 100).rounded() / 100, basis: .premium) }
        if let last = pristineStats?.median ?? pristineStats?.lastPrice { return (value: last, basis: .other) }
        return nil
    }

    /// A slab's price for the collection, like the website's `withEbayGradedPrices`. Most grades:
    /// the eBay median when that grade sold at least 3 times, else PriceCharting, else the median
    /// or last sale. A CGC 10 is priced by `cgcTenValue` from `sales` (the full listings, which
    /// tell Pristine from Gem Mint); without them, eBay's "CGC 10" figures stand for the Gem Mint.
    static func slabPrice(company: String, grade: String, pristine: Bool, summary: EbayStats?, sales: EbaySales?, guide: Double?) -> Double? {
        if isCGCTen(company: company, grade: grade) {
            let gem: EbayStats? = sales != nil ? stats(sales, label: gemMintLabel) : summary
            let own: EbayStats? = stats(sales, label: pristineLabel)
            return cgcTenValue(gem: gem, pristineStats: own, guide: guide, pristine: pristine)?.value
        }
        let steady = (summary?.count ?? 0) >= 3 ? summary?.median : nil
        return steady ?? guide ?? summary?.median ?? summary?.lastPrice
    }
}
