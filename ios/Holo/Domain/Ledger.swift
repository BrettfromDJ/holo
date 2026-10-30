import Foundation

/// One entry in the append-only log. Mirrors the web app's `Transaction`.
struct Txn: Hashable {
    enum Kind: String { case purchase, sale, adjustment, correction }

    var id: String
    var identity: HoldingIdentity
    var kind: Kind
    /// yyyy-MM-dd
    var date: String
    var quantity: Double
    var unitPrice: Double
    var fees: Double = 0
    var shipping: Double = 0
    var tax: Double = 0
    var correctsId: String?
    /// ISO timestamp; breaks ties between same-day entries.
    var createdAt: String

    /// Loaded cost of a purchase (or positive adjustment), extras included.
    var acquisitionCost: Double { abs(quantity) * unitPrice + fees + shipping + tax }
    /// Net proceeds of a sale after its costs.
    var saleProceeds: Double { quantity * unitPrice - fees - shipping - tax }
}

/// Units bought together at one cost.
struct Lot: Hashable {
    var transactionId: String
    var date: String
    var quantity: Double
    /// Fully loaded cost per unit.
    var unitCost: Double
}

struct RealizedEntry: Hashable {
    var transactionId: String
    var date: String
    var quantity: Double
    var proceeds: Double
    var costBasis: Double
    var gain: Double
}

struct Position {
    var identity: HoldingIdentity
    var lots: [Lot] = []
    var realized: [RealizedEntry] = []
    var totalPurchased: Double = 0
    var firstAcquired: String?
    var lastAcquired: String?

    var quantity: Double { lots.reduce(0) { $0 + $1.quantity } }
    var costBasis: Double { lots.reduce(0) { $0 + $1.quantity * $1.unitCost } }
    var realizedGain: Double { realized.reduce(0) { $0 + $1.gain } }
}

/// Turns the transaction log into FIFO lots, exactly like the web app's ledger
/// (src/lib/finance/ledger.ts), so both show the same cost basis and gains.
struct Ledger {
    private(set) var positions: [String: Position] = [:]
    private static let eps = 1e-9

    init(_ transactions: [Txn], asOf: String? = nil) {
        for t in Ledger.effective(transactions) {
            if let asOf, t.date > asOf { break }
            apply(t)
        }
    }

    /// Resolve corrections: the latest correction for an entry replaces its economics; quantity 0 voids it.
    static func effective(_ all: [Txn]) -> [Txn] {
        let byId = Dictionary(all.map { ($0.id, $0) }, uniquingKeysWith: { a, _ in a })
        func rootOf(_ id: String) -> String {
            var cur = byId[id]
            var seen = Set<String>()
            while let c = cur, c.kind == .correction, let target = c.correctsId, !seen.contains(c.id) {
                seen.insert(c.id)
                guard let next = byId[target] else { break }
                cur = next
            }
            return cur?.id ?? id
        }

        var latest: [String: Txn] = [:]
        for t in all where t.kind == .correction {
            guard let target = t.correctsId else { continue }
            let root = rootOf(target)
            if let prev = latest[root], prev.createdAt > t.createdAt { continue }
            latest[root] = t
        }

        var out: [Txn] = []
        for t in all where t.kind != .correction {
            guard let c = latest[t.id] else {
                out.append(t)
                continue
            }
            if c.quantity == 0 { continue }
            var e = t
            e.date = c.date
            e.quantity = t.kind == .adjustment ? c.quantity : abs(c.quantity)
            e.unitPrice = c.unitPrice
            e.fees = c.fees
            e.shipping = c.shipping
            e.tax = c.tax
            out.append(e)
        }
        return out.sorted(by: Ledger.replayOrder)
    }

    /// Date order; on the same day acquisitions come before disposals; then entry order.
    static func replayOrder(_ a: Txn, _ b: Txn) -> Bool {
        if a.date != b.date { return a.date < b.date }
        func rank(_ t: Txn) -> Int { t.kind == .purchase || (t.kind == .adjustment && t.quantity > 0) ? 0 : 1 }
        if rank(a) != rank(b) { return rank(a) < rank(b) }
        return a.createdAt < b.createdAt
    }

    private mutating func apply(_ t: Txn) {
        let key = t.identity.key
        var p = positions[key] ?? Position(identity: t.identity)

        func acquire(_ qty: Double, _ cost: Double) {
            p.lots.append(Lot(transactionId: t.id, date: t.date, quantity: qty, unitCost: qty > 0 ? cost / qty : 0))
            if p.firstAcquired == nil || t.date < p.firstAcquired! { p.firstAcquired = t.date }
            if p.lastAcquired == nil || t.date > p.lastAcquired! { p.lastAcquired = t.date }
        }

        func consume(_ qty: Double) -> (taken: Double, cost: Double) {
            var remaining = qty
            var cost = 0.0
            for i in p.lots.indices {
                if remaining <= Ledger.eps { break }
                let take = min(p.lots[i].quantity, remaining)
                p.lots[i].quantity -= take
                remaining -= take
                cost += take * p.lots[i].unitCost
            }
            p.lots.removeAll { $0.quantity <= Ledger.eps }
            return (qty - remaining, cost)
        }

        switch t.kind {
        case .purchase:
            guard t.quantity > 0 else { break }
            let cost = t.acquisitionCost
            acquire(t.quantity, cost)
            p.totalPurchased += cost
        case .sale:
            guard t.quantity > 0 else { break }
            let (taken, cost) = consume(t.quantity)
            guard taken > Ledger.eps else { break }
            // Pro-rate proceeds if the sale was more than was held.
            let proceeds = t.saleProceeds * (taken / t.quantity)
            p.realized.append(RealizedEntry(transactionId: t.id, date: t.date, quantity: taken, proceeds: proceeds, costBasis: cost, gain: proceeds - cost))
        case .adjustment:
            if t.quantity > 0 {
                let cost = t.acquisitionCost
                acquire(t.quantity, cost)
                p.totalPurchased += cost
            } else if t.quantity < 0 {
                let (taken, cost) = consume(-t.quantity)
                guard taken > Ledger.eps else { break }
                p.realized.append(RealizedEntry(transactionId: t.id, date: t.date, quantity: taken, proceeds: 0, costBasis: cost, gain: -cost))
            }
        case .correction:
            break
        }
        positions[key] = p
    }
}
