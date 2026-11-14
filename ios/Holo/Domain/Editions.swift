import Foundation

/// Old English Pokémon sets printed twice, 1st Edition and Unlimited. The catalog lists each as
/// one set with both versions of every card; we show them as two sets ("Base Set 1st Edition",
/// "Base Set Unlimited"), each priced and tracked on its own. The halves share the catalog set's
/// slug plus "--1st-edition" or "--unlimited". Same as the website's `src/lib/editions.ts`.
enum Editions {
    enum Edition: String { case firstEdition = "1st-edition", unlimited }

    private static let sets: Set<String> = [
        "base set", "jungle", "fossil", "team rocket", "gym heroes", "gym challenge",
        "neo genesis", "neo discovery", "neo revelation", "neo destiny",
    ]

    /// An English catalog set printed in both editions (by its set name).
    static func isEditionSet(_ name: String?) -> Bool {
        guard let name else { return false }
        return sets.contains(name.folding(options: [.caseInsensitive, .diacriticInsensitive], locale: nil).trimmingCharacters(in: .whitespaces))
    }

    static func slug(_ slug: String, _ edition: Edition) -> String { "\(slug)--\(edition.rawValue)" }

    static func name(_ name: String, _ edition: Edition) -> String {
        "\(name) \(edition == .firstEdition ? "1st Edition" : "Unlimited")"
    }

    /// Which half a copy belongs to, from its printing ("1st Edition Holofoil").
    static func of(printing: String?) -> Edition {
        (printing ?? "").range(of: #"1st\s*edition"#, options: [.regularExpression, .caseInsensitive]) != nil ? .firstEdition : .unlimited
    }

    /// The Master Sets set a copy belongs to: its edition's half for the old sets, else its set.
    static func masterSet(for h: HoldingView) -> (id: String, name: String)? {
        guard let p = h.product, !p.isSealed, let setId = p.setId else { return nil }
        guard p.id.hasPrefix("tcgapi:"), isEditionSet(p.setName) else { return (setId, p.setName ?? setId) }
        let e = of(printing: h.identity.printing)
        return (slug(setId, e), name(p.setName ?? setId, e))
    }
}
