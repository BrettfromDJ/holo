import Foundation

/// Filters and sort for catalog search results, like the website's Explore search.
struct SearchFilters: Equatable {
    enum Kind: String, CaseIterable { case all = "Cards and sealed", single = "Cards only", sealed = "Sealed only" }
    enum Owned: String, CaseIterable { case any = "Owned or not", owned = "In my collection", notOwned = "Not in my collection" }
    enum Sort: String, CaseIterable { case match = "Best match", priceDesc = "Price: high to low", priceAsc = "Price: low to high", name = "Name" }

    var kind = Kind.all
    var language: String?
    var brand: String?
    var owned = Owned.any
    var watchlist = false
    var min: Double?
    var max: Double?
    var sort = Sort.match

    var activeCount: Int {
        [kind != .all, language != nil, brand != nil, owned != .any, watchlist, min != nil || max != nil].filter { $0 }.count
    }

    /// A catalog's language, from its name ("Pokemon Japan" is Japanese); catalogs without one are English.
    static func language(of gameName: String?) -> String {
        let g = (gameName ?? "").lowercased()
        if g.contains("japan") { return "Japanese" }
        if g.contains("chin") { return "Chinese" }
        if g.contains("korea") { return "Korean" }
        return "English"
    }

    /// The base brand without its language ("Pokemon Japan" → "Pokemon").
    static func brand(of gameName: String?) -> String? {
        guard let g = gameName, !g.isEmpty else { return nil }
        let stripped = g.replacingOccurrences(of: #"\s+(japan(ese)?|chinese|china|korea(n)?)$"#, with: "", options: [.regularExpression, .caseInsensitive])
        return stripped.isEmpty ? g : stripped
    }

    /// Each value present in the results with how many have it, most common first.
    static func facet(_ items: [SearchHit], _ key: (SearchHit) -> String?) -> [(value: String, count: Int)] {
        var counts: [String: Int] = [:]
        for i in items { if let v = key(i) { counts[v, default: 0] += 1 } }
        return counts.map { ($0.key, $0.value) }.sorted { $0.count != $1.count ? $0.count > $1.count : $0.value < $1.value }
    }

    func apply(_ items: [SearchHit], owned ownedIds: Set<String>, watched: Set<String>) -> [SearchHit] {
        let out = items.filter { i in
            if kind == .single && i.product.kind != "single" { return false }
            if kind == .sealed && i.product.kind != "sealed" { return false }
            if let language, SearchFilters.language(of: i.gameName) != language { return false }
            if let brand, SearchFilters.brand(of: i.gameName) != brand { return false }
            if owned == .owned && !ownedIds.contains(i.product.id) { return false }
            if owned == .notOwned && ownedIds.contains(i.product.id) { return false }
            if watchlist && !watched.contains(i.product.id) { return false }
            // A price range leaves out unpriced items.
            if min != nil || max != nil {
                guard let m = i.market else { return false }
                if let min, m < min { return false }
                if let max, m > max { return false }
            }
            return true
        }
        switch sort {
        case .match: return out
        case .name: return out.sorted { $0.product.name < $1.product.name }
        case .priceAsc: return out.sorted { ($0.market ?? .infinity) < ($1.market ?? .infinity) }
        case .priceDesc: return out.sorted { ($0.market.map { -$0 } ?? .infinity) < ($1.market.map { -$0 } ?? .infinity) }
        }
    }
}
