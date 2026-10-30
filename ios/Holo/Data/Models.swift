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
