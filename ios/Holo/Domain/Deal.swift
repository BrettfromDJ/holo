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
    /// Whether what comes in is added to your collection unless you switch an item off (default on).
    var addIncoming: Bool?
    /// Whether items going out that aren't in Holo ask what you paid (default on).
    var askCost: Bool?
    /// What "Round up" rounds the cash up to the next multiple of, in dollars (one of
    /// `roundSteps`; nil or anything else is $5). Optional, so rates saved before it still load.
    var roundStep: Double?

    var addsIncoming: Bool { addIncoming ?? true }
    var asksCost: Bool { askCost ?? true }

    /// The steps "Round up" can round the cash to (deal settings), the same as the website's ROUND_STEPS.
    static let roundSteps: [Double] = [1, 5, 10, 25, 50, 100]
    static let defaultRoundStep: Double = 5
    /// The step the cash rounds up to: the saved one when it's one of the steps, else $5.
    var step: Double {
        guard let roundStep, Self.roundSteps.contains(roundStep) else { return Self.defaultRoundStep }
        return roundStep
    }
}

/// The cash rounded up to the next multiple of `step` dollars ($1,151.20 → $1,155 at $5), keeping
/// who pays whom (the sign). Nil when it's already on a multiple, or there's no cash. Same as the
/// website's roundedCash().
func roundedCash(_ balance: Double, step: Double = DealRates.defaultRoundStep) -> Double? {
    guard balance.isFinite, step.isFinite else { return nil }
    let cents = Int((abs(balance) * 100).rounded())
    let stepCents = Int((step * 100).rounded())
    guard cents > 0, stepCents > 0, cents % stepCents != 0 else { return nil }
    let r = Double((cents + stepCents - 1) / stepCents * stepCents) / 100
    return balance < 0 ? -r : r
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
    /// Coming in: false keeps it out of your collection (nil follows your deal settings).
    var track: Bool?
    /// Going out but not in Holo: what you paid per unit, if you said. With it the deal records
    /// the purchase and the sale; without it the line isn't tracked.
    var cost: Double?
    /// A line that isn't a catalog product ("Bulk lot"): a name and a price, never tracked.
    var custom: Bool?

    var id: String { key }
    var isCustom: Bool { custom == true }

    enum CodingKeys: String, CodingKey { case key, product, printing, market, qty, price, rate, grade, holdingKey, maxQty, track, cost, custom }

    init(key: String, product: Product, printing: String?, market: Double?, qty: Int = 1, price: Double? = nil, rate: Double? = nil, grade: ScanGrade? = nil, holdingKey: String? = nil, maxQty: Int? = nil, track: Bool? = nil, cost: Double? = nil, custom: Bool? = nil) {
        self.track = track
        self.cost = cost
        self.custom = custom
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
        track = try c.decodeIfPresent(Bool.self, forKey: .track)
        cost = try c.decodeIfPresent(Double.self, forKey: .cost)
        custom = try c.decodeIfPresent(Bool.self, forKey: .custom)
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
        try c.encodeIfPresent(track, forKey: .track)
        try c.encodeIfPresent(cost, forKey: .cost)
        try c.encodeIfPresent(custom, forKey: .custom)
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
    /// Your own notes on the deal; copied into the record when it closes.
    var notes: String?
    /// Cash the two of you settled on (signed like DealTotals.balance: positive, the customer pays
    /// you). While set, one side's prices are spread to reach it (see `agreed(rates:)`); nil
    /// follows the prices. Any renegotiation clears it (DealStore.update).
    var agreedCash: Double?

    enum CodingKeys: String, CodingKey {
        case incoming = "in"
        case outgoing = "out"
        case rateIn, rateOut, photos, notes, agreedCash
    }

    init() {}

    init(from decoder: Decoder) throws {
        let c = try decoder.container(keyedBy: CodingKeys.self)
        incoming = try c.decodeIfPresent([DealItem].self, forKey: .incoming) ?? []
        outgoing = try c.decodeIfPresent([DealItem].self, forKey: .outgoing) ?? []
        rateIn = try c.decodeIfPresent(Double.self, forKey: .rateIn)
        rateOut = try c.decodeIfPresent(Double.self, forKey: .rateOut)
        photos = try c.decodeIfPresent([String].self, forKey: .photos) ?? []
        notes = try c.decodeIfPresent(String.self, forKey: .notes)
        agreedCash = try c.decodeIfPresent(Double.self, forKey: .agreedCash)
    }

    func encode(to encoder: Encoder) throws {
        var c = encoder.container(keyedBy: CodingKeys.self)
        try c.encode(incoming, forKey: .incoming)
        try c.encode(outgoing, forKey: .outgoing)
        try c.encode(rateIn, forKey: .rateIn)
        try c.encode(rateOut, forKey: .rateOut)
        if !photos.isEmpty { try c.encode(photos, forKey: .photos) }
        if let notes, !notes.isEmpty { try c.encode(notes, forKey: .notes) }
        try c.encodeIfPresent(agreedCash, forKey: .agreedCash)
    }

    /// Anything worth keeping: items, photos or notes.
    var hasContent: Bool {
        kind != .empty || !photos.isEmpty || !(notes ?? "").trimmingCharacters(in: .whitespacesAndNewlines).isEmpty
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

/// A deal adjusted to its agreed cash (see DealState.agreed(rates:)).
struct AgreedDeal {
    /// The deal with the moved side's lines at their new price per unit.
    var deal: DealState
    /// The side whose prices moved; nil when nothing was adjusted.
    var side: DealSide?
    /// That side's priced total as a share of its market value (0.74 = 74% of market), when known.
    var share: Double?
}

extension DealState {
    /// The deal as it works out at the agreed cash (the website's agreedDeal). The difference from
    /// the normal cash is spread across the going-out lines (or, with nothing going out, the
    /// coming-in lines) in proportion to each line's total, never taking a line below $0 (then it
    /// gets as close as it can). Exact to the cent: any leftover cent goes on the biggest line.
    /// The stored deal is never changed; this is worked out each time.
    func agreed(rates: (in: Double, out: Double)) -> AgreedDeal {
        let none = AgreedDeal(deal: self, side: nil, share: nil)
        guard let agreedCash, agreedCash.isFinite, kind != .empty else { return none }
        let side: DealSide = outgoing.isEmpty ? .incoming : .outgoing
        let lines = side == .outgoing ? outgoing : incoming
        let r = side == .outgoing ? rates.out : rates.in
        let cents: [Int?] = lines.map { l in l.unitPrice(side: r).map { max(0, Int(($0 * Double(l.qty) * 100).rounded())) } }
        let priced = cents.indices.filter { cents[$0] != nil }
        guard let first = priced.first else { return none }
        let inValue = round2(incoming.reduce(0) { $0 + $1.total(side: rates.in) })
        let outValue = round2(outgoing.reduce(0) { $0 + $1.total(side: rates.out) })
        let balance = round2(outValue - inValue)
        let delta = Int(((agreedCash - balance) * 100).rounded())
        let current = priced.reduce(0) { $0 + (cents[$1] ?? 0) }
        let target = max(0, current + (side == .outgoing ? delta : -delta))
        // Each line's share of the move: its total, or an even split when every line is at $0.
        func weight(_ i: Int) -> Int { current > 0 ? (cents[i] ?? 0) : 1 }
        let totalWeight = priced.reduce(0) { $0 + weight($1) }
        var next: [Int: Int] = [:]
        for i in priced { next[i] = Int((Double(target) * Double(weight(i)) / Double(totalWeight) + 1e-6).rounded(.down)) }
        let biggest = priced.reduce(first) { weight($1) > weight($0) ? $1 : $0 }
        let spread = next.values.reduce(0, +)
        next[biggest, default: 0] += target - spread
        var adjusted = lines
        for (i, c) in next {
            adjusted[i].price = Double(c) / 100 / Double(adjusted[i].qty)
            adjusted[i].rate = nil
        }
        var marketCents = 0.0
        var marketPriced = 0
        for i in priced {
            guard let m = lines[i].market else { continue }
            marketCents += m * Double(lines[i].qty) * 100
            marketPriced += next[i] ?? 0
        }
        var d = self
        if side == .outgoing { d.outgoing = adjusted } else { d.incoming = adjusted }
        return AgreedDeal(deal: d, side: side, share: marketCents > 0 ? Double(marketPriced) / marketCents : nil)
    }

    /// The deal at its agreed cash, or as it is when none is set: what every total, the customer
    /// view and the closed deal's record use.
    func settled(rates: (in: Double, out: Double)) -> DealState { agreed(rates: rates).deal }

    /// Whether this deal was renegotiated from `before` (a side's % moved, a line's % or price or
    /// quantity changed, a line added or removed), which lets go of an agreed cash figure. The same
    /// as the website's renegotiates().
    func renegotiates(from before: DealState) -> Bool {
        func text(_ n: Double?) -> String { n.map { String($0) } ?? "-" }
        func sig(_ items: [DealItem]) -> [String] {
            items.map { item in [item.key, String(item.qty), text(item.price), text(item.rate)].joined(separator: "|") }
        }
        return rateIn != before.rateIn || rateOut != before.rateOut || sig(incoming) != sig(before.incoming) || sig(outgoing) != sig(before.outgoing)
    }
}

extension DealState {
    /// How far a side's % of market can go: the counter-offer slider's range (the website's RATE_RANGE).
    static let rateRange: ClosedRange<Double> = 0.4...1.2

    /// The side's % of market that brings the cash to `cash` (signed like DealTotals.balance): what
    /// goes out when anything does, else what comes in (the side `agreed(rates:)` moves). The cash
    /// is linear in that rate for the lines that follow it (typed prices and lines with their own %
    /// stay put), so it's solved exactly, then held to the slider's range. Nil when the deal is
    /// empty or no line follows the side's %. Same as the website's rateForCash().
    func rate(forCash cash: Double, rates: (in: Double, out: Double), range: ClosedRange<Double> = DealState.rateRange) -> (side: DealSide, rate: Double)? {
        guard cash.isFinite, kind != .empty else { return nil }
        let side: DealSide = outgoing.isEmpty ? .incoming : .outgoing
        let lines = side == .outgoing ? outgoing : incoming
        let sideRate = side == .outgoing ? rates.out : rates.in
        func follows(_ l: DealItem) -> Bool { l.price == nil && l.rate == nil && l.market != nil }
        let market = lines.reduce(0.0) { $0 + (follows($1) ? ($1.market ?? 0) * Double($1.qty) : 0) }
        guard market > 0 else { return nil }
        let fixed = lines.reduce(0.0) { $0 + (follows($1) ? 0 : $1.total(side: sideRate)) }
        let other = side == .outgoing
            ? incoming.reduce(0.0) { $0 + $1.total(side: rates.in) }
            : outgoing.reduce(0.0) { $0 + $1.total(side: rates.out) }
        // balance = out − in; only `market × rate` moves.
        let exact = side == .outgoing ? (cash + other - fixed) / market : (other - cash - fixed) / market
        let clamped = min(range.upperBound, max(range.lowerBound, exact))
        return (side, (clamped * 1_000_000).rounded() / 1_000_000)
    }

    /// The deal at a cash amount the two of you settled on (signed like DealTotals.balance): the
    /// side's slider moves to the rate that gets there (`rate(forCash:rates:)`), and the agreed cash
    /// is set to it as well, so it lands exactly to the cent even where the slider's range or fixed
    /// prices stop short (`agreed(rates:)` spreads the rest). `rates` are the rates each side is at
    /// now. Apply it straight to the deal (DealStore.setAgreedCash), not as an edit that
    /// renegotiates. Same as the website's withAgreedCash().
    func agreeing(cash: Double, rates: (in: Double, out: Double)) -> DealState {
        var d = self
        let amount = round2(cash)
        if let r = rate(forCash: amount, rates: rates) {
            if r.side == .outgoing { d.rateOut = r.rate } else { d.rateIn = r.rate }
        }
        d.agreedCash = amount
        return d
    }
}

/// The agreed cash for a typed amount: who pays whom stays as it is now (the sign of the balance);
/// when the cash is even, the customer pays you only if what goes out is worth more than what comes in.
func signedAgreedCash(_ amount: Double, totals: DealTotals) -> Double {
    let a = round2(abs(amount))
    let customerPays = abs(totals.balance) < 0.005 ? totals.outValue > totals.inValue : totals.balance > 0
    return customerPays ? a : -a
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
    /// Outgoing rows with no known cost (not in Holo and no "you paid"): their profit is unknown.
    var uncosted: Int
    /// What the deal leaves you ahead by: market value of what comes in, less your cost of what
    /// goes out, less cash you pay (plus cash you get). Profit + value gained; it doesn't depend on
    /// how the prices were split. Nil when anything going out has no known cost, or the deal is empty.
    var ahead: Double?

    /// `cost` gives your cost for an outgoing row (nil when unknown).
    init(_ deal: DealState, rates: (in: Double, out: Double), cost: (DealItem) -> Double?) {
        kind = deal.kind
        inValue = round2(deal.incoming.reduce(0) { $0 + $1.total(side: rates.in) })
        outValue = round2(deal.outgoing.reduce(0) { $0 + $1.total(side: rates.out) })
        let costed = deal.outgoing.compactMap { item in cost(item).map { (item, $0) } }
        let made: Double? = costed.isEmpty ? nil : round2(costed.reduce(0) { $0 + $1.0.total(side: rates.out) - $1.1 })
        let gained = round2(deal.incoming.reduce(0) { $0 + ($1.market ?? 0) * Double($1.qty) - $1.total(side: rates.in) })
        profit = made
        equity = gained
        belowCost = costed.filter { $0.0.total(side: rates.out) < $0.1 - 0.005 }.count
        let unknown = deal.outgoing.count - costed.count
        uncosted = unknown
        balance = round2(outValue - inValue)
        // A pure buy has no profit (ahead = value gained); a pure sell has no value gained (ahead = profit).
        ahead = (deal.kind == .empty || unknown > 0) ? nil : round2((made ?? 0) + gained)
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
        /// Not recorded in the collection (left out on purpose, not in Holo, or custom).
        var untracked: Bool? = nil
    }

    var id: String
    var at: String
    var kind: DealKind
    var inValue: Double
    var outValue: Double
    var balance: Double
    var profit: Double?
    var equity: Double
    /// How far ahead the deal left you (profit + value gained); nil when not every item had a cost.
    /// Missing on deals closed before it was recorded (see `aheadTotal`).
    var ahead: Double? = nil
    /// Items that went out with no known cost. Recorded alongside `ahead`, so a record with it
    /// knows its own ahead (nil there means unknown, not "work it out").
    var uncosted: Int? = nil
    var items: Int
    var lines: [Line]?
    /// Photos documenting the deal (storage paths, see DealPhotos).
    var photos: [String]? = nil
    /// Your notes on the deal (from the open deal, editable on the closed deal's page).
    var notes: String? = nil

    /// How far ahead this deal left you. Deals closed before it was recorded work it out from
    /// profit + value gained (a buy is all value gained); a newer one with it unknown stays unknown.
    var aheadTotal: Double? {
        if let ahead { return ahead }
        if uncosted != nil { return nil }
        if kind == .buy { return round2(equity) }
        guard let profit else { return nil }
        return round2(profit + (kind == .sell ? 0 : equity))
    }

    var date: Date { ISO8601DateFormatter.withFraction.date(from: at) ?? ISO8601DateFormatter().date(from: at) ?? Date() }
}

extension DealRecord {
    /// Words a deal of each kind answers to in the history search (the same as the website's).
    private var kindWords: String {
        switch kind {
        case .buy: return "buy buying bought"
        case .sell: return "sale sell selling sold"
        case .trade: return "trade trading traded"
        case .empty: return "deal"
        }
    }

    /// Whether this deal matches the history search: every word typed is found in one of its
    /// cards' names, its notes, or its kind ("buy", "sale", "trade"). An empty search matches all.
    func matches(search query: String) -> Bool {
        let words = query.lowercased().split(whereSeparator: { $0.isWhitespace }).map(String.init)
        guard !words.isEmpty else { return true }
        let names = (lines ?? []).map(\.product.name)
        let text = (names + [notes ?? "", kindWords]).joined(separator: " \n ").lowercased()
        return words.allSatisfy { text.contains($0) }
    }
}

/// A day's closed deals in numbers (the website's dealDayTotals): how many, cash in and out, net
/// cash, how far ahead (from the deals that know it) and sale profit (from those that have one).
struct DealDayTotals: Equatable {
    var deals: Int
    /// Cash customers paid you.
    var cashIn: Double
    /// Cash you paid customers.
    var cashOut: Double
    /// Cash in less cash out.
    var net: Double
    /// Nil when no deal that day knows it.
    var ahead: Double?
    /// Nil when no deal that day has one.
    var profit: Double?

    init(_ records: [DealRecord]) {
        deals = records.count
        cashIn = round2(records.reduce(0) { $0 + max(0, $1.balance) })
        cashOut = round2(records.reduce(0) { $0 + max(0, -$1.balance) })
        net = round2(cashIn - cashOut)
        let known = records.compactMap(\.aheadTotal)
        ahead = known.isEmpty ? nil : round2(known.reduce(0, +))
        let profits = records.compactMap(\.profit)
        profit = profits.isEmpty ? nil : round2(profits.reduce(0, +))
    }
}

/// A deal set aside to finish later (user_state "deals-parked", shared with the website).
struct ParkedDeal: Codable, Identifiable, Equatable {
    var id: String
    var name: String
    var savedAt: String
    var state: DealState

    var date: Date { ISO8601DateFormatter.withFraction.date(from: savedAt) ?? ISO8601DateFormatter().date(from: savedAt) ?? Date() }

    /// "Deal at 3:42 PM": the name a parked deal gets when you don't type one.
    static func defaultName(at date: Date = Date(), calendar: Calendar = .current) -> String {
        let h = calendar.component(.hour, from: date)
        let m = calendar.component(.minute, from: date)
        let hour = h % 12 == 0 ? 12 : h % 12
        return "Deal at \(hour):\(m < 10 ? "0" : "")\(m) \(h < 12 ? "AM" : "PM")"
    }
}

extension ISO8601DateFormatter {
    /// Matches JavaScript's toISOString(), e.g. 2026-10-30T12:00:00.000Z.
    static let withFraction: ISO8601DateFormatter = {
        let f = ISO8601DateFormatter()
        f.formatOptions = [.withInternetDateTime, .withFractionalSeconds]
        return f
    }()
}

/// The ahead headline: "You come out ahead" (an open deal) or "You came out ahead" (a closed one).
func dealAheadTitle(_ n: Double, past: Bool = false) -> String {
    if abs(n) < 0.005 { return past ? "You broke even" : "You break even" }
    return "You \(past ? "came" : "come") out \(n > 0 ? "ahead" : "behind")"
}

func round2(_ n: Double) -> Double { (n * 100).rounded() / 100 }
