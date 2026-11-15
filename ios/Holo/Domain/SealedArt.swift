import Foundation

/// Our own photos of sealed products (backgrounds removed), served by the website from
/// `public/products/<dir>/<file>.webp`. The same list as `src/lib/sealed-art-manifest.json`
/// (keep both in step) and the same matching as `src/lib/sealed-art.ts`: a product gets one when
/// its set (or its name) names the set and its name, without the set's name, matches a listed
/// product exactly, else the longest listed name inside it.
enum SealedArt {
    struct Entry {
        var set: String
        var dir: String
        var products: [String: String]
    }

    static let entries: [Entry] = [
        Entry(set: "Delta Reign", dir: "pokemon/delta-reign", products: [
            "3 Pack Blister [Seel]": "3-pack-blister-seel",
            "Booster Box Case": "booster-box-case",
            "Booster Box": "booster-box",
            "Booster Bundle Case": "booster-bundle-case",
            "Booster Bundle": "booster-bundle",
            "Booster Pack Art Bundle [Set of 4]": "booster-pack-art-bundle-set-of-4",
            "Booster Pack": "booster-pack",
            "Build & Battle Box": "build-and-battle-box",
            "Elite Trainer Box Case": "elite-trainer-box-case",
            "Elite Trainer Box": "elite-trainer-box",
            "Pokemon Center Elite Trainer Box (Exclusive)": "pokemon-center-elite-trainer-box-exclusive",
            "Pokemon Center Elite Trainer Box Case (Exclusive)": "pokemon-center-elite-trainer-box-case-exclusive",
            "Premium Checklane Blister [Ampharos Line]": "premium-checklane-blister-ampharos-line",
            "Premium Checklane Blister [Delphox Line]": "premium-checklane-blister-delphox-line",
            "Single Pack Blister (Target Exclusive) [Keldeo]": "single-pack-blister-target-exclusive-keldeo",
            "Single Pack Blister (Target Exclusive) [Xerneas]": "single-pack-blister-target-exclusive-xerneas",
            "Single Pack Blister [Spritzee]": "single-pack-blister-spritzee",
            "Sleeved Booster Case": "sleeved-booster-case",
            "Sleeved Booster Pack Art Bundle [Set of 4]": "sleeved-booster-pack-art-bundle-set-of-4",
            "Sleeved Booster Pack": "sleeved-booster-pack",
        ]),
    ]

    /// Lowercase words only: "Build & Battle Box" → "build and battle box".
    static func words(_ s: String) -> String {
        s.lowercased()
            .replacingOccurrences(of: "é", with: "e")
            .replacingOccurrences(of: "&", with: " and ")
            .replacingOccurrences(of: #"[^a-z0-9]+"#, with: " ", options: .regularExpression)
            .trimmingCharacters(in: .whitespaces)
    }

    private static func has(_ hay: String, _ needle: String) -> Bool { " \(hay) ".contains(" \(needle) ") }

    /// Worked out once per product name and set.
    nonisolated(unsafe) private static var cache: [String: String?] = [:]
    private static let lock = NSLock()

    /// The photo's path on the website ("/products/pokemon/delta-reign/booster-box.webp"), or nil.
    static func path(name: String, setName: String?, single: Bool) -> String? {
        guard !single else { return nil }
        let key = "\(name)|\(setName ?? "")"
        lock.lock(); if let hit = cache[key] { lock.unlock(); return hit }; lock.unlock()
        let found = match(name: name, setName: setName)
        lock.lock(); cache[key] = found; lock.unlock()
        return found
    }

    private static func match(name rawName: String, setName rawSet: String?) -> String? {
        let name = words(rawName), setName = words(rawSet ?? "")
        for entry in entries {
            let set = words(entry.set)
            guard has(setName, set) || has(name, set) else { continue }
            // The product part: the name without the set's name, the series or a code ("ME03").
            var rest = " \(name) ".replacingOccurrences(of: " \(set) ", with: " ").replacingOccurrences(of: " mega evolution ", with: " ")
            rest = rest.replacingOccurrences(of: #" me\d+[a-z]? "#, with: " ", options: .regularExpression).trimmingCharacters(in: .whitespaces)
            // Each listed name, and the same without its bracketed notes.
            let keys = entry.products.keys.flatMap { k in
                [(k, words(k)), (k, words(k.replacingOccurrences(of: #"\([^)]*\)|\[[^\]]*\]"#, with: " ", options: .regularExpression)))]
            }
            let pick = keys.first { $0.1 == rest } ?? keys.filter { has(rest, $0.1) }.max { $0.1.count < $1.1.count }
            if let pick, let file = entry.products[pick.0] { return "/products/\(entry.dir)/\(file).webp" }
        }
        return nil
    }

    static func url(_ p: Product) -> URL? {
        path(name: p.name, setName: p.setName, single: !p.isSealed).map { AppConfig.apiBaseURL.appendingPathComponent(String($0.dropFirst())) }
    }
}
