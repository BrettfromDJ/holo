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

    /// Our own photos of the Unlimited prints, served by the website at
    /// /cards/pokemon/<dir>/<number>.webp (the catalog's pictures for these sets are the 1st
    /// Edition scans). Same list as the website's unlimited-art-manifest.json; keep in step.
    private static let unlimitedArt: [String: (dir: String, numbers: Set<Int>)] = [
        "base set": (dir: "base-set-unlimited", numbers: [1, 2, 3, 4, 5, 6, 7, 9, 10, 11, 12, 13, 14, 15, 16, 17, 18, 19, 20, 21, 22, 23, 24, 25, 26, 27, 28, 29, 30, 31, 32, 33, 34, 35, 36, 37, 38, 39, 40, 41, 42, 43, 44, 45, 46, 47, 48, 49, 50, 51, 52, 53, 54, 55, 56, 57, 58, 59, 60, 61, 62, 63, 64, 65, 66, 67, 68, 69, 70, 71, 72, 73, 74, 75, 76, 77, 78, 79, 80, 81, 82, 83, 84, 85, 86, 87, 88, 89, 90, 91, 92, 93, 94, 95, 96, 97, 98, 99, 100, 101, 102]),
        "fossil": (dir: "fossil-unlimited", numbers: [1, 2, 3, 4, 5, 6, 7, 8, 9, 10, 11, 12, 13, 14, 15, 16, 17, 18, 19, 20, 21, 22, 23, 24, 25, 26, 27, 28, 29, 30, 31, 32, 33, 34, 35, 36, 37, 38, 39, 40, 41, 42, 43, 44, 45, 46, 47, 48, 49, 50, 51, 52, 53, 54, 55, 56, 57, 58, 59, 60, 61, 62]),
        "jungle": (dir: "jungle-unlimited", numbers: [1, 2, 3, 4, 5, 6, 7, 8, 9, 10, 11, 12, 13, 14, 15, 16, 17, 18, 19, 20, 21, 22, 23, 24, 25, 26, 27, 28, 29, 30, 31, 32, 33, 34, 35, 36, 37, 38, 39, 40, 41, 42, 43, 44, 45, 46, 47, 48, 49, 50, 51, 52, 53, 54, 55, 56, 57, 58, 59, 60, 61, 62, 63, 64]),
        "team rocket": (dir: "team-rocket-unlimited", numbers: [1, 2, 3, 4, 5, 6, 7, 8, 9, 10, 11, 12, 13, 14, 15, 16, 17, 18, 19, 20, 21, 22, 23, 24, 25, 26, 27, 28, 29, 30, 31, 32, 33, 34, 35, 36, 37, 38, 39, 40, 41, 42, 43, 44, 45, 46, 47, 48, 49, 50, 51, 52, 53, 54, 55, 56, 57, 58, 59, 60, 61, 62, 63, 64, 65, 66, 67, 68, 69, 70, 71, 72, 73, 74, 75, 76, 77, 78, 79, 80, 81, 82, 83]),
        "gym heroes": (dir: "gym-heroes-unlimited", numbers: [1, 2, 3, 4, 5, 6, 7, 8, 9, 10, 11, 12, 13, 14, 15, 16, 17, 18, 19, 20, 21, 22, 23, 24, 25, 26, 27, 28, 29, 30, 31, 32, 33, 34, 35, 36, 37, 38, 39, 40, 41, 42, 43, 44, 45, 46, 47, 48, 49, 50, 51, 52, 53, 54, 55, 56, 57, 58, 59, 60, 61, 62, 63, 64, 65, 66, 67, 68, 69, 70, 71, 72, 73, 74, 75, 76, 77, 78, 79, 80, 81, 82, 83, 84, 85, 86, 87, 88, 89, 90, 91, 92, 93, 94, 95, 96, 97, 98, 99, 100, 101, 102, 103, 104, 105, 106, 107, 108, 109, 110, 111, 112, 113, 114, 115, 116, 117, 118, 119, 120, 121, 122, 123, 124, 125, 126, 127, 128, 129, 130, 131, 132]),
        "gym challenge": (dir: "gym-challenge-unlimited", numbers: [1, 2, 3, 4, 5, 6, 7, 8, 9, 10, 11, 12, 13, 14, 15, 16, 17, 18, 19, 20, 21, 22, 23, 24, 25, 26, 27, 28, 29, 30, 31, 32, 33, 34, 35, 36, 37, 38, 39, 40, 41, 42, 43, 44, 45, 46, 47, 48, 49, 50, 51, 52, 53, 54, 55, 56, 57, 58, 59, 60, 61, 62, 63, 64, 65, 66, 67, 68, 69, 70, 71, 72, 73, 74, 75, 76, 77, 78, 79, 80, 81, 82, 83, 84, 85, 86, 87, 88, 89, 90, 91, 92, 93, 94, 95, 96, 97, 98, 99, 100, 101, 102, 103, 104, 105, 106, 107, 108, 109, 110, 111, 112, 113, 114, 115, 116, 117, 118, 119, 120, 121, 122, 123, 124, 125, 126, 127, 128, 129, 130, 131, 132]),
        "neo genesis": (dir: "neo-genesis-unlimited", numbers: [1, 2, 3, 4, 5, 6, 7, 8, 9, 10, 11, 12, 13, 14, 15, 16, 17, 18, 19, 20, 21, 22, 23, 24, 25, 26, 27, 28, 29, 30, 31, 32, 33, 34, 35, 36, 37, 38, 39, 40, 41, 42, 43, 44, 45, 46, 47, 48, 49, 50, 51, 52, 53, 54, 55, 56, 57, 58, 59, 60, 61, 62, 63, 64, 65, 66, 67, 68, 69, 70, 71, 72, 73, 74, 75, 76, 77, 78, 79, 80, 81, 82, 83, 84, 85, 86, 87, 88, 89, 90, 91, 92, 93, 94, 95, 96, 97, 98, 99, 100, 101, 102, 103, 104, 105, 106, 107, 108, 109, 110, 111]),
        "neo discovery": (dir: "neo-discovery-unlimited", numbers: [1, 2, 3, 4, 5, 6, 7, 8, 9, 10, 11, 12, 13, 14, 15, 16, 17, 18, 19, 20, 21, 22, 23, 24, 25, 26, 27, 28, 29, 30, 31, 32, 33, 34, 35, 36, 37, 38, 39, 40, 41, 42, 43, 44, 45, 46, 47, 48, 49, 50, 51, 52, 53, 54, 55, 56, 57, 58, 59, 60, 61, 62, 63, 64, 65, 66, 67, 68, 69, 70, 71, 72, 73, 74, 75]),
    ]

    /// Our Unlimited photo for a card, or nil.
    static func unlimitedImage(setName: String?, number: String?) -> String? {
        guard let key = setName?.folding(options: [.caseInsensitive, .diacriticInsensitive], locale: nil).trimmingCharacters(in: .whitespaces),
              let entry = unlimitedArt[key],
              let digits = number?.trimmingCharacters(in: .whitespaces).drop(while: { $0 == "#" }).prefix(while: \.isNumber),
              let n = Int(digits), entry.numbers.contains(n) else { return nil }
        return AppConfig.apiBaseURL.appendingPathComponent("cards/pokemon/\(entry.dir)/\(n).webp").absoluteString
    }

    /// A card shown as one printing: our Unlimited photo when that printing is the Unlimited one.
    static func art(_ product: Product?, printing: String?) -> Product? {
        // Only when the printing is known: no printing means we can't tell which edition it is.
        guard var p = product, let printing, !printing.trimmingCharacters(in: .whitespaces).isEmpty,
              !p.isSealed, p.id.hasPrefix("tcgapi:"), of(printing: printing) == .unlimited,
              let url = unlimitedImage(setName: p.setName, number: p.number) else { return product }
        p.imageUrl = url
        return p
    }
}
