import Foundation

/// Deal maker math, ported from the web app (src/lib/deal.ts). A deal has what comes in
/// (the customer hands you) and what goes out (you hand them), each valued at a share of
/// market unless a row's price was typed in. Cash settles the difference.

enum DealSide: String, Codable { case incoming = "in", outgoing = "out" }

enum DealKind: String, Codable {
    case buy, sell, trade, empty

    var label: String {
        switch self {
        case .buy: return "Buying"
        case .sell: return "Selling"
        case .trade: return "Trade"
        case .empty: return "New deal"
        }
    }

    /// The deal as a noun: "Close buy", "Sale recorded".
    var noun: String {
        switch self {
        case .buy: return "Buy"
        case .sell: return "Sale"
        case .trade: return "Trade"
        case .empty: return "Deal"
        }
    }
}

/// Default rates, as a share of market.
struct DealRates: Codable, Equatable {
    /// What you pay for items you buy outright.
    var buy: Double = 0.7
    /// What you credit for items taken in on trade.
    var trade: Double = 0.8
    /// What you charge for items going out.
    var sell: Double = 1
}

/// One row of a deal. Same JSON as the website's DealItem; unknowns are written as null.
struct DealItem: Codable, Identifiable, Hashable {
    var key: String
    var product: Product
    var printing: String?
    /// Market value per unit when added.
    var market: Double?
    var qty: Int
    /// Negotiated price per unit; nil means market × the rate.
    var price: Double?
    /// This row's own share of market, overriding the side's rate.
    var rate: Double?
    /// A slab's grade, for items coming in that aren't already held.
    var grade: ScanGrade?
    /// The holding this came from (its key), when it's from your inventory.
    var holdingKey: String?
    var maxQty: Int?

    var id: String { key }

    enum CodingKeys: String, CodingKey { case key, product, printing, market, qty, price, rate, grade, holdingKey, maxQty }

    init(key: String, product: Product, printing: String?, market: Double?, qty: Int = 1, price: Double? = nil, rate: Double? = nil, grade: ScanGrade? = nil, holdingKey: String? = nil, maxQty: Int? = nil) {
        self.key = key
        self.product = product
        self.printing = printing
        self.market = market
        self.qty = qty
        self.price = price
        self.rate = rate
        self.grade = grade
        self.holdingKey = holdingKey
        self.maxQty = maxQty
    }

    init(from decoder: Decoder) throws {
        let c = try decoder.container(keyedBy: CodingKeys.self)
        key = try c.decode(String.self, forKey: .key)
        product = try c.decode(Product.self, forKey: .product)
        printing = try c.decodeIfPresent(String.self, forKey: .printing)
        market = try c.decodeIfPresent(Double.self, forKey: .market)
        qty = Int(try c.decodeIfPresent(Double.self, forKey: .qty) ?? 1)
        price = try c.decodeIfPresent(Double.self, forKey: .price)
        rate = try c.decodeIfPresent(Double.self, forKey: .rate)
        grade = try c.decodeIfPresent(ScanGrade.self, forKey: .grade)
        holdingKey = try c.decodeIfPresent(String.self, forKey: .holdingKey)
        maxQty = (try c.decodeIfPresent(Double.self, forKey: .maxQty)).map { Int($0) }
    }

    func encode(to encoder: Encoder) throws {
        var c = encoder.container(keyedBy: CodingKeys.self)
        try c.encode(key, forKey: .key)
        try c.encode(product, forKey: .product)
        try c.encode(printing, forKey: .printing)
        // The website does math on these, so missing must be written as null, not left out.
        try c.encode(market, forKey: .market)
        try c.encode(qty, forKey: .qty)
        try c.encode(price, forKey: .price)
        try c.encodeIfPresent(rate, forKey: .rate)
        try c.encodeIfPresent(grade, forKey: .grade)
        try c.encodeIfPresent(holdingKey, forKey: .holdingKey)
        try c.encodeIfPresent(maxQty, forKey: .maxQty)
    }

    /// The share of market this row counts at.
    func rate(side: Double) -> Double { rate ?? side }

    /// Price per unit: the typed price, else market × the rate.
    func unitPrice(side: Double) -> Double? {
        if let price { return price }
        return market.map { round2($0 * rate(side: side)) }
    }

    func total(side: Double) -> Double { (unitPrice(side: side) ?? 0) * Double(qty) }
}

/// The deal in progress (user_state "deal", shared with the website).
struct DealState: Codable, Equatable {
    var incoming: [DealItem] = []
    var outgoing: [DealItem] = []
    /// Rates moved off the defaults for this deal; nil follows the presets.
    var rateIn: Double?
    var rateOut: Double?
    /// Photos documenting the deal (storage paths, see DealPhotos).
    var photos: [String] = []

    enum CodingKeys: String, CodingKey {
        case incoming = "in"
        case outgoing = "out"
        case rateIn, rateOut, photos
    }

    init() {}

    init(from decoder: Decoder) throws {
        let c = try decoder.container(keyedBy: CodingKeys.self)
        incoming = try c.decodeIfPresent([DealItem].self, forKey: .incoming) ?? []
        outgoing = try c.decodeIfPresent([DealItem].self, forKey: .outgoing) ?? []
        rateIn = try c.decodeIfPresent(Double.self, forKey: .rateIn)
        rateOut = try c.decodeIfPresent(Double.self, forKey: .rateOut)
        photos = try c.decodeIfPresent([String].self, forKey: .photos) ?? []
    }

    func encode(to encoder: Encoder) throws {
        var c = encoder.container(keyedBy: CodingKeys.self)
        try c.encode(incoming, forKey: .incoming)
        try c.encode(outgoing, forKey: .outgoing)
        try c.encode(rateIn, forKey: .rateIn)
        try c.encode(rateOut, forKey: .rateOut)
        if !photos.isEmpty { try c.encode(photos, forKey: .photos) }
    }

    var kind: DealKind {
        switch (incoming.isEmpty, outgoing.isEmpty) {
        case (false, false): return .trade
        case (false, true): return .buy
        case (true, false): return .sell
        case (true, true): return .empty
        }
    }

    /// The rate each side is at: this deal's own, else the default for this kind of deal.
    func rates(_ defaults: DealRates) -> (in: Double, out: Double) {
        (rateIn ?? (kind == .trade ? defaults.trade : defaults.buy), rateOut ?? defaults.sell)
    }
}

struct DealTotals {
    var kind: DealKind
    /// What the incoming items count for.
    var inValue: Double
    /// What the outgoing items count for.
    var outValue: Double
    /// Positive: the customer pays you. Negative: you pay the customer.
    var balance: Double
    /// Profit on what goes out, against your cost. Nil when no cost is known.
    var profit: Double?
    /// Market value of what comes in, less what you're giving for it.
    var equity: Double
    /// Outgoing rows priced below your cost.
    var belowCost: Int

    /// `cost` gives your cost for an outgoing row (nil when unknown).
    init(_ deal: DealState, rates: (in: Double, out: Double), cost: (DealItem) -> Double?) {
        kind = deal.kind
        inValue = round2(deal.incoming.reduce(0) { $0 + $1.total(side: rates.in) })
        outValue = round2(deal.outgoing.reduce(0) { $0 + $1.total(side: rates.out) })
        let costed = deal.outgoing.compactMap { item in cost(item).map { (item, $0) } }
        profit = costed.isEmpty ? nil : round2(costed.reduce(0) { $0 + $1.0.total(side: rates.out) - $1.1 })
        equity = round2(deal.incoming.reduce(0) { $0 + ($1.market ?? 0) * Double($1.qty) - $1.total(side: rates.in) })
        belowCost = costed.filter { $0.0.total(side: rates.out) < $0.1 - 0.005 }.count
        balance = round2(outValue - inValue)
    }
}

/// A closed deal, for the history (user_state "deals", shared with the website).
struct DealRecord: Codable, Identifiable, Hashable {
    struct Line: Codable, Hashable {
        struct Item: Codable, Hashable {
            var id: String
            var name: String
            var imageUrl: String?
            var kind: String
            var setName: String?
            var productType: String?
        }

        var side: DealSide
        var product: Item
        var qty: Double
        /// Price per unit it went at.
        var price: Double
    }

    var id: String
    var at: String
    var kind: DealKind
    var inValue: Double
    var outValue: Double
    var balance: Double
    var profit: Double?
    var equity: Double
    var items: Int
    var lines: [Line]?
    /// Photos documenting the deal (storage paths, see DealPhotos).
    var photos: [String]? = nil

    var date: Date { ISO8601DateFormatter.withFraction.date(from: at) ?? ISO8601DateFormatter().date(from: at) ?? Date() }
}

extension ISO8601DateFormatter {
    /// Matches JavaScript's toISOString(), e.g. 2026-10-30T12:00:00.000Z.
    static let withFraction: ISO8601DateFormatter = {
        let f = ISO8601DateFormatter()
        f.formatOptions = [.withInternetDateTime, .withFractionalSeconds]
        return f
    }()
}

func round2(_ n: Double) -> Double { (n * 100).rounded() / 100 }
