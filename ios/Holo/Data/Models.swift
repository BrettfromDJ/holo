import Foundation

// MARK: - Shapes the web API returns (camelCase JSON)

/// A card or sealed product, as the web app's API returns it.
struct Product: Codable, Identifiable, Hashable {
    let id: String
    var source: String?
    var externalId: String?
    var name: String
    var setName: String?
    var setId: String?
    var number: String?
    var rarity: String?
    var productType: String?
    /// "single" or "sealed".
    var kind: String
    var imageUrl: String?
    var tcgplayerId: Int?
    var tcgplayerUrl: String?
    var printings: [String]?

    var isSealed: Bool { kind == "sealed" }
    /// Online game code cards ("Code Card - Surging Sparks Booster Pack"): kept out of the app.
    var isCodeCard: Bool {
        "\(name) \(productType ?? "") \(rarity ?? "")".range(of: #"\bcode\s*card\b|\bonline code\b"#, options: [.regularExpression, .caseInsensitive]) != nil
    }
    var imageURL: URL? { imageUrl.flatMap(URL.init(string:)) }

    /// "Evolving Skies · #215/203"
    var subtitle: String {
        [setName, number.map { "#\($0)" }].compactMap { $0 }.joined(separator: " · ")
    }
}

/// A current price for one printing.
struct Price: Codable, Hashable {
    var productId: String
    var printing: String?
    var market: Double?
    var low: Double?
    var change24hPct: Double?
    var change7dPct: Double?
    var change30dPct: Double?
    var updatedAt: String?
    var status: String?
}

/// A search result: a product with its headline price.
struct SearchHit: Codable, Identifiable, Hashable {
    var product: Product
    var printing: String?
    var market: Double?
    var priceUpdatedAt: String?
    var gameName: String?

    var id: String { product.id }
}

struct PricePoint: Codable, Hashable, Identifiable {
    var date: String
    var price: Double
    var id: String { date }

    var day: Date { Format.isoDay.date(from: date) ?? Date() }
}

/// POST /api/catalog: the product, its prices and its history, saved to the shared catalog.
struct CatalogImport: Codable {
    var product: Product
    var prices: [Price]
    var history: [PricePoint]
}

// MARK: Scanning (/api/scan)

struct ScanGrade: Codable, Hashable {
    var company: String
    var grade: String
}

struct ScanRead: Codable, Hashable {
    /// "raw", "slab", "sealed" or "unknown".
    var kind: String
    var grade: ScanGrade?
}

struct ScanCandidate: Codable, Hashable {
    var product: Product
    var printing: String?
    var printings: [String]
    var market: Double?
    /// On a slab: the eBay sold price for the grade on its label.
    var slabMarket: Double?
    var score: Double

    /// What it's worth: a slab at its grade's price when known, else the card's market price.
    func value(for read: ScanRead?) -> Double? {
        if read?.kind == "slab", let slab = slabMarket { return slab }
        return market
    }
}

struct ScanResult: Codable, Hashable {
    /// "matched", "ambiguous", "retake", "not_found" or "unsupported".
    var status: String
    var message: String?
    var read: ScanRead?
    var candidates: [ScanCandidate]
    var scansRemaining: Int?
}

struct APIErrorBody: Codable {
    struct Inner: Codable {
        var code: String?
        var message: String?
    }
    var error: Inner?
}

// MARK: - Database rows (snake_case, read straight from Supabase)

struct ProductRow: Codable {
    var id: String
    var source: String
    var external_id: String
    var name: String
    var set_name: String?
    var set_id: String?
    var number: String?
    var rarity: String?
    var product_type: String?
    var kind: String
    var image_url: String?
    var tcgplayer_id: Int?
    var tcgplayer_url: String?
    var printings: [String]?

    var product: Product {
        Product(
            id: id, source: source, externalId: external_id, name: name, setName: set_name, setId: set_id,
            number: number, rarity: rarity, productType: product_type, kind: kind, imageUrl: image_url,
            tcgplayerId: tcgplayer_id, tcgplayerUrl: tcgplayer_url, printings: printings
        )
    }
}

struct PriceRow: Codable {
    var product_id: String
    /// "" is the default printing.
    var printing: String
    var market_price: Double?
    var low_price: Double?
    var change_24h_pct: Double?
    var change_7d_pct: Double?
    var change_30d_pct: Double?
    var source_updated_at: String?
    var status: String

    var price: Price {
        Price(
            productId: product_id, printing: printing.isEmpty ? nil : printing, market: market_price, low: low_price,
            change24hPct: change_24h_pct, change7dPct: change_7d_pct, change30dPct: change_30d_pct,
            updatedAt: source_updated_at, status: status
        )
    }
}

struct SnapshotRow: Codable {
    var product_id: String
    var printing: String
    var snapshot_date: String
    var market_price: Double
}

struct HoldingRow: Codable, Identifiable {
    var id: String
    var product_id: String
    var printing: String?
    var condition: String
    var grade_company: String?
    var grade: String?
    var manual_value: Double?
    var manual_value_date: String?

    var identity: HoldingIdentity {
        HoldingIdentity(productId: product_id, printing: printing, condition: condition, gradeCompany: grade_company, grade: grade)
    }
}

struct NewHoldingRow: Codable {
    var user_id: String
    var product_id: String
    var printing: String?
    var condition: String
    var grade_company: String?
    var grade: String?
}

struct TransactionRow: Codable {
    var id: String
    var holding_id: String
    var type: String
    var trade_date: String
    var quantity: Double
    var unit_price: Double
    var fees: Double
    var shipping: Double
    var tax: Double
    var source: String?
    var notes: String?
    var corrects_id: String?
    var created_at: String
}

struct NewTransactionRow: Codable {
    var user_id: String
    var holding_id: String
    var type: String
    var trade_date: String
    var quantity: Double
    var unit_price: Double
    var fees: Double
    var shipping: Double
    var tax: Double
    var source: String?
    var notes: String?
    var corrects_id: String?
}

struct ManualValueUpdate: Codable {
    var manual_value: Double?
    var manual_value_date: String?
}

// MARK: - Shared keys

/// Two units are interchangeable when product, printing, condition and grade all match.
struct HoldingIdentity: Hashable {
    var productId: String
    var printing: String?
    var condition: String
    var gradeCompany: String?
    var grade: String?

    var isGraded: Bool { gradeCompany != nil && grade != nil }
    var gradeLabel: String? { isGraded ? "\(gradeCompany!) \(grade!)" : nil }

    /// Same as the web app's holdingKey().
    var key: String { [productId, printing ?? "", condition, gradeLabel ?? ""].joined(separator: "|") }
}

/// Same as the web app's priceKey().
func priceKey(_ productId: String, _ printing: String?) -> String { "\(productId)|\(printing ?? "")" }

/// Raw conditions, with the share of Near Mint a copy is estimated at (as on the web).
enum CardCondition: String, CaseIterable, Identifiable {
    case nearMint = "Near Mint"
    case lightlyPlayed = "Lightly Played"
    case moderatelyPlayed = "Moderately Played"
    case heavilyPlayed = "Heavily Played"
    case damaged = "Damaged"

    var id: String { rawValue }

    var short: String {
        switch self {
        case .nearMint: return "NM"
        case .lightlyPlayed: return "LP"
        case .moderatelyPlayed: return "MP"
        case .heavilyPlayed: return "HP"
        case .damaged: return "DMG"
        }
    }

    var share: Double {
        switch self {
        case .nearMint: return 1
        case .lightlyPlayed: return 0.85
        case .moderatelyPlayed: return 0.7
        case .heavilyPlayed: return 0.5
        case .damaged: return 0.35
        }
    }

    /// Sealed and unknown conditions count at full price.
    static func share(for condition: String) -> Double {
        CardCondition(rawValue: condition)?.share ?? 1
    }
}

let gradingCompanies = ["PSA", "BGS", "CGC", "SGC", "TAG"]

// MARK: - Watchlist, wishlist and per-user state

struct WatchRow: Codable, Identifiable {
    var id: String
    var product_id: String
    var printing: String?
    var target_price: Double?
    var notes: String?
    var created_at: String
}

struct NewWatchRow: Codable {
    var user_id: String
    var product_id: String
    var printing: String?
    var target_price: Double?
}

struct WatchTargetUpdate: Codable {
    var target_price: Double?
}

/// A wishlist entry, stored as JSON in user_state ("wishlist"), shared with the website.
struct WishItem: Codable, Identifiable, Hashable {
    enum Priority: String, Codable, CaseIterable { case grail, want, maybe }

    var id: String
    var product: Product
    var printing: String?
    var priority: Priority
    /// Price you'd happily pay.
    var target: Double?
    /// Latest known market price.
    var price: Double?
    var addedAt: String
}

/// One row of user_state: a JSON value per key, per user.
struct UserStateRow<Value: Codable>: Codable {
    var user_id: String
    var key: String
    var value: Value
    var updated_at: String
}

struct UserStateValue<Value: Decodable>: Decodable {
    var value: Value
}

// MARK: - Explore (/api/explore)

struct ExploreGame: Codable, Identifiable, Hashable {
    var slug: String
    var name: String
    var logoUrl: String?
    var sets: Int
    var loadedSets: Int
    var cardCount: Int?
    var id: String { slug }
}

struct ExploreSet: Codable, Identifiable, Hashable {
    var slug: String
    var gameSlug: String
    var gameName: String
    var name: String
    /// yyyy-MM-dd
    var releaseDate: String?
    var imageUrl: String?
    var iconUrl: String?
    var productCount: Int?
    /// False until the daily catalog sync has loaded this set's products.
    var loaded: Bool
    var id: String { slug }

    var release: Date? { releaseDate.flatMap { Format.isoDay.date(from: String($0.prefix(10))) } }
}

struct ExploreIndex: Codable {
    var games: [ExploreGame]
    var sets: [ExploreSet]
}

struct ExploreSetDetail: Codable {
    var set: ExploreSet
    var products: [SearchHit]
}

/// GET /api/explore/products/:id — a catalog product with its prices and history, by printing key.
struct CatalogProduct: Codable {
    var product: Product
    var prices: [Price]
    var history: [String: [PricePoint]]
}

// MARK: - eBay and condition prices

struct EbayStats: Codable, Hashable {
    var median: Double?
    var count: Int
    var lastPrice: Double?
    var lastSold: String?
}

struct EbaySale: Codable, Hashable, Identifiable {
    var soldDate: String
    var price: Double
    var bestOffer: Bool
    var listPrice: Double?
    /// "PSA 10", or nil when ungraded.
    var grade: String?
    /// Condition from the title, ungraded sales only.
    var condition: String?
    var title: String
    var url: String
    var id: String { url + soldDate + String(price) }
}

struct EbaySales: Codable, Hashable {
    var printing: String?
    var ungraded: EbayStats
    var graded: [String: EbayStats]
    var sales: [EbaySale]
    var asOf: String
}

struct EbaySummary: Codable, Hashable {
    var printing: String?
    var ungraded: EbayStats
    var graded: [String: EbayStats]
    var asOf: String
}

/// A TCGplayer price for one condition, from live listings.
struct ConditionPrice: Codable, Hashable {
    var printing: String?
    var condition: String
    var price: Double?
    /// "median" (of 3+ listings) or "lowest".
    var basis: String
    var samples: Int
}
