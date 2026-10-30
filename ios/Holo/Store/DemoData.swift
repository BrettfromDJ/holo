import Foundation

/// A made-up collection for screenshots and trying the app without an account: launch with
/// `-HoloDemo`. Prices are fictional, like the website's demo mode, and nothing is saved.
enum DemoData {
    struct Item {
        var slug: String
        var name: String
        var set: String
        var type: String
        var sealed: Bool
        var start: Double
        var now: Double
        var image: String?
        var number: String? = nil
        var rarity: String? = nil
    }

    static let items: [Item] = [
        Item(slug: "es-bb", name: "Evolving Skies Booster Box", set: "Evolving Skies", type: "Booster Box", sealed: true, start: 640, now: 1184.5, image: local("es-bb")),
        Item(slug: "cel-upc", name: "Celebrations Ultra Premium Collection", set: "Celebrations", type: "Ultra Premium Collection", sealed: true, start: 210, now: 338.6, image: local("cel-upc")),
        Item(slug: "151-upc", name: "Scarlet & Violet—151 Ultra Premium Collection", set: "Scarlet & Violet—151", type: "Ultra Premium Collection", sealed: true, start: 118, now: 212.3, image: local("151-upc")),
        Item(slug: "ss-bb", name: "Surging Sparks Booster Box", set: "Surging Sparks", type: "Booster Box", sealed: true, start: 152, now: 214.9, image: local("ss-bb")),
        Item(slug: "pe-etb", name: "Prismatic Evolutions Elite Trainer Box", set: "Prismatic Evolutions", type: "Elite Trainer Box", sealed: true, start: 142, now: 118.75, image: local("pe-etb")),
        Item(slug: "cz-etb", name: "Crown Zenith Elite Trainer Box", set: "Crown Zenith", type: "Elite Trainer Box", sealed: true, start: 58, now: 96.2, image: local("cz-etb")),
        Item(slug: "pf-tin", name: "Paldean Fates Tin", set: "Paldean Fates", type: "Tin", sealed: true, start: 27, now: 29.85, image: local("pf-tin")),
        Item(slug: "jt-pack", name: "Journey Together Booster Pack", set: "Journey Together", type: "Booster Pack", sealed: true, start: 5.4, now: 4.62, image: local("jt-pack")),
        Item(slug: "umbreon-vmax-alt", name: "Umbreon VMAX (Alternate Full Art)", set: "Evolving Skies", type: "Cards", sealed: false, start: 520, now: 1392, image: card("swsh7", "215"), number: "215/203", rarity: "Secret Rare"),
        Item(slug: "charizard-ex-151", name: "Charizard ex - 199/165", set: "Scarlet & Violet—151", type: "Cards", sealed: false, start: 118, now: 104.25, image: card("sv3pt5", "199"), number: "199/165", rarity: "Special Illustration Rare"),
        Item(slug: "pikachu-ex-ss", name: "Pikachu ex - 238/191", set: "Surging Sparks", type: "Cards", sealed: false, start: 285, now: 371.5, image: card("sv8", "238"), number: "238/191", rarity: "Special Illustration Rare"),
        Item(slug: "charizard-base", name: "Charizard (Base Set)", set: "Base Set", type: "Cards", sealed: false, start: 520, now: 455, image: card("base1", "4"), number: "4/102", rarity: "Holo Rare"),
        Item(slug: "giratina-v-alt", name: "Giratina V (Alternate Full Art)", set: "Lost Origin", type: "Cards", sealed: false, start: 215, now: 318.4, image: card("swsh11", "186"), number: "186/196", rarity: "Ultra Rare"),
    ]

    /// (slug, days ago, quantity, unit price, condition, grade company, grade)
    static let lots: [(String, Int, Double, Double, String, String?, String?)] = [
        ("es-bb", 640, 2, 655, "Near Mint", nil, nil),
        ("cel-upc", 520, 1, 215, "Near Mint", nil, nil),
        ("151-upc", 300, 1, 120, "Near Mint", nil, nil),
        ("ss-bb", 120, 1, 160, "Near Mint", nil, nil),
        ("pe-etb", 90, 3, 140, "Near Mint", nil, nil),
        ("cz-etb", 400, 2, 60, "Near Mint", nil, nil),
        ("pf-tin", 200, 4, 26, "Near Mint", nil, nil),
        ("jt-pack", 5, 12, 5.5, "Near Mint", nil, nil),
        ("umbreon-vmax-alt", 600, 1, 540, "Near Mint", nil, nil),
        ("charizard-ex-151", 40, 1, 115, "Near Mint", nil, nil),
        ("pikachu-ex-ss", 3, 1, 330, "Near Mint", "PSA", "10"),
        ("charizard-base", 700, 1, 480, "Lightly Played", nil, nil),
        ("giratina-v-alt", 1, 1, 300, "Near Mint", nil, nil),
    ]

    static func product(_ i: Item) -> Product {
        Product(id: "sample:\(i.slug)", source: "sample", externalId: i.slug, name: i.name, setName: i.set,
                setId: i.set.lowercased(), number: i.number, rarity: i.rarity, productType: i.type,
                kind: i.sealed ? "sealed" : "single", imageUrl: i.image, tcgplayerId: nil, tcgplayerUrl: nil,
                printings: [i.sealed ? "Normal" : "Holofoil"])
    }

    /// A repeatable wandering price path from `start` to `now` over `days`.
    static func series(_ i: Item, days: Int = 760) -> [PricePoint] {
        var seed = UInt64(abs(i.slug.hashValueStable)) | 1
        func rand() -> Double {
            seed = seed &* 6364136223846793005 &+ 1442695040888963407
            return Double(seed >> 11) / Double(1 << 53)
        }
        var walk: [Double] = [0]
        for _ in 1 ... days { walk.append(walk.last! + (rand() - 0.5) * 0.03) }
        let a = log(i.start), b = log(i.now)
        let today = Date()
        return (0 ... days).map { d in
            let t = Double(d) / Double(days)
            let price = exp(a + t * (b - a) + walk[d] - t * walk[days])
            let date = Calendar.current.date(byAdding: .day, value: d - days, to: today) ?? today
            return PricePoint(date: Format.day(date), price: (price * 100).rounded() / 100)
        }
    }

    private static func local(_ name: String) -> String? { Bundle.main.url(forResource: name, withExtension: "jpg")?.absoluteString }
    private static func card(_ set: String, _ num: String) -> String { "https://images.pokemontcg.io/\(set)/\(num)_hires.png" }
}

private extension String {
    /// FNV-1a, so the made-up prices are the same on every launch.
    var hashValueStable: Int {
        var h: UInt64 = 1469598103934665603
        for b in utf8 { h = (h ^ UInt64(b)) &* 1099511628211 }
        return Int(truncatingIfNeeded: h >> 1)
    }
}
