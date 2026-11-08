import Foundation

/// Extras a list can have (stored in user_state `list-meta`, keyed by list id): for sale, a
/// percentage of market to ask, and prices set by hand. Same rules as src/lib/lists.ts.
struct ListMeta: Codable, Hashable {
    var forSale: Bool?
    /// Asking price as a share of market, e.g. 90 for 90%. nil means 100%.
    var askPercent: Double?
    /// Asking prices set by hand, by product id. They win over any percentage.
    var prices: [String: Double]?
    /// A percentage of market for one card, by product id. Wins over the list's percentage.
    var percents: [String: Double]?

    var isForSale: Bool { forSale == true }
}

enum ListPricing {
    static let metaKey = "list-meta"
    /// A share link for one list carries this title prefix, then the list id.
    static let sharePrefix = "list:"

    static func shareTitle(_ listId: String) -> String { sharePrefix + listId }

    /// What you're asking for one copy: your own price, else market × the card's percentage,
    /// else × the list's.
    static func asking(_ meta: ListMeta?, productId: String, market: Double?) -> Double? {
        if let own = meta?.prices?[productId], own >= 0 { return own }
        guard let market else { return nil }
        let pct = meta?.percents?[productId] ?? meta?.askPercent ?? 100
        return (market * pct).rounded() / 100
    }
}
