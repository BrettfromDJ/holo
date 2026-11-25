import Foundation

/// Every English Pokémon single, kept on the phone (`/api/scan/index`, refreshed daily), so once
/// the scanner reads a card's name and number it finds the card here in milliseconds instead of
/// asking the server (that round trip was most of a scan's time). Cards not in it yet (a set out
/// today) still go to the server lookup. Prices aren't in it: the scan's price fills in a moment
/// later, as before (`ScanModel.prefetch`).
final class ScanCatalog: @unchecked Sendable {
    static let shared = ScanCatalog()

    private struct Card {
        var product: Product
        /// The card number's first part in canonical form ("074/131" → "74", "TG05" → "TG5").
        var key: String
        var lowerName: String
    }

    private let lock = NSLock()
    private var cards: [Card] = []
    private var byNumber: [String: [Int]] = [:]
    private var loading = false

    /// Whether the list is on the phone and read.
    var isReady: Bool { lock.lock(); defer { lock.unlock() }; return !cards.isEmpty }

    private var file: URL {
        FileManager.default.urls(for: .cachesDirectory, in: .userDomainMask)[0].appendingPathComponent("scan-catalog-v1.json")
    }

    /// Reads the saved list (once per launch), then fetches a fresh one when it's a day old or
    /// missing. Off the main thread; safe to call again (it does nothing while busy or ready).
    func prepare() {
        lock.lock()
        if loading { lock.unlock(); return }
        loading = true
        let empty = cards.isEmpty
        lock.unlock()
        Task.detached(priority: .utility) { [self] in
            defer { lock.lock(); loading = false; lock.unlock() }
            if empty, let data = try? Data(contentsOf: file) { install(data) }
            let age = (try? file.resourceValues(forKeys: [.contentModificationDateKey]).contentModificationDate).map { Date().timeIntervalSince($0) }
            guard age == nil || age! > 20 * 3600 || !isReady else { return }
            guard let data = try? await Backend.shared.api.scanIndex(), install(data) else { return }
            try? data.write(to: file, options: .atomic)
        }
    }

    /// Singles with the read number's first part (any set total: the caller checks it), and,
    /// when a name was read, singles whose name starts with it. Nil when the list isn't ready.
    func hits(for reading: OnDeviceScan.Reading) -> [SearchHit]? {
        lock.lock(); defer { lock.unlock() }
        guard !cards.isEmpty else { return nil }
        var picked: [Int] = []
        if !reading.number.isEmpty, let first = reading.number.split(separator: "/").first {
            picked += byNumber[Self.key(String(first))] ?? []
        }
        if let name = reading.name?.lowercased(), name.count >= 3 {
            var n = 0
            for (i, c) in cards.enumerated() where c.lowerName.hasPrefix(name) {
                picked.append(i)
                n += 1
                if n >= 60 { break }
            }
        }
        var seen = Set<Int>()
        return picked.filter { seen.insert($0).inserted }.map { SearchHit(product: cards[$0].product) }
    }

    /// Unpacks the server's list (see `/api/scan/index`); false when it can't be read.
    @discardableResult
    private func install(_ data: Data) -> Bool {
        struct Packed: Decodable {
            var v: Int
            var sets: [[String]]
            var dirs: [String]
            var rarities: [String]
            var printings: [String]
            var cards: [[Field]]
        }
        enum Field: Decodable {
            case s(String), i(Int)
            init(from decoder: Decoder) throws {
                let c = try decoder.singleValueContainer()
                if let i = try? c.decode(Int.self) { self = .i(i) } else { self = .s(try c.decode(String.self)) }
            }
            var string: String { if case let .s(s) = self { return s }; if case let .i(i) = self { return String(i) }; return "" }
            var int: Int { if case let .i(i) = self { return i }; return Int(string) ?? 0 }
        }
        guard let packed = try? JSONDecoder().decode(Packed.self, from: data), packed.v == 1, !packed.cards.isEmpty else { return false }
        var list: [Card] = []
        list.reserveCapacity(packed.cards.count)
        var index: [String: [Int]] = [:]
        for row in packed.cards where row.count >= 8 {
            let set = packed.sets.indices.contains(row[3].int) ? packed.sets[row[3].int] : []
            let dir = packed.dirs.indices.contains(row[4].int) ? packed.dirs[row[4].int] : ""
            let file = row[5].string
            let rarity = packed.rarities.indices.contains(row[6].int) ? packed.rarities[row[6].int] : ""
            let printings = packed.printings.indices.contains(row[7].int) ? packed.printings[row[7].int] : ""
            let number = row[2].string
            let product = Product(
                id: "tcgapi:" + row[0].string, source: "tcgapi", externalId: row[0].string, name: row[1].string,
                setName: set.count > 1 ? set[1] : nil, setId: set.first, number: number.isEmpty ? nil : number,
                rarity: rarity.isEmpty ? nil : rarity, productType: nil, kind: "single",
                imageUrl: file.isEmpty ? nil : dir + file, tcgplayerId: nil, tcgplayerUrl: nil,
                printings: printings.isEmpty ? [] : printings.components(separatedBy: "|"))
            let key = number.split(separator: "/").first.map { Self.key(String($0)) } ?? ""
            if !key.isEmpty { index[key, default: []].append(list.count) }
            list.append(Card(product: product, key: key, lowerName: product.name.lowercased()))
        }
        guard !list.isEmpty else { return false }
        lock.lock()
        cards = list
        byNumber = index
        lock.unlock()
        return true
    }

    /// "074" → "74", "TG05" → "TG5", "#215" → "215" (as `OnDeviceScan.sameNumber` compares).
    static func key(_ part: String) -> String {
        let p = part.uppercased().replacingOccurrences(of: "#", with: "")
        let letters = p.prefix { $0.isLetter }
        let digits = p.drop { $0.isLetter }.drop { $0 == "0" }
        return String(letters) + (digits.isEmpty ? "0" : String(digits))
    }
}
