import Foundation

/// Gain attribution, ported from the website's `src/lib/finance/attribution.ts`: break a gain
/// total down into the products (or sets, or types) it comes from, as waterfall steps that sum
/// exactly to the total. Unrealized gains come from holdings with a market price; realized gains
/// come from sales and write-offs.
enum Gains {
    enum Mode: String, CaseIterable { case unrealized, realized, all }
    enum Group: String, CaseIterable { case product, set, category }

    struct Row: Identifiable, Hashable {
        var key: String
        var label: String
        /// A product for the picture (product and set grouping).
        var product: Product?
        var identity: HoldingIdentity?
        var category: HoldingCategory?
        var gain: Double = 0
        var unrealized: Double = 0
        var realized: Double = 0
        var value: Double = 0
        var costBasis: Double = 0
        var quantity: Double = 0
        /// Rows folded into the "others" step.
        var members: Int?
        var start: Double = 0
        var end: Double = 0
        var id: String { key }
    }

    struct Attribution {
        var steps: [Row] = []
        var total: Double = 0
        var gains: Double = 0
        var losses: Double = 0
        var winners = 0
        var losers = 0
        var topThreeShare: Double?
        var unpriced = 0
        /// Rows before folding into "others".
        var count = 0
    }

    static func attribute(holdings: [HoldingView], transactions: [Txn], products: [String: Product], mode: Mode, group: Group, maxRows: Int? = nil) -> Attribution {
        var rows: [String: Row] = [:]
        func add(productId: String, identity: HoldingIdentity?, category: HoldingCategory, _ change: (inout Row) -> Void) {
            let product = products[productId]
            let key: String
            let label: String
            switch group {
            case .product: key = productId; label = product?.name ?? "Unknown product"
            case .set: key = product?.setName ?? "—"; label = product?.setName ?? "Unknown set"
            case .category: key = category.rawValue; label = category.rawValue
            }
            var row = rows[key] ?? Row(key: key, label: label, product: group == .category ? nil : product,
                                       identity: group == .product ? identity : nil,
                                       category: group == .set ? nil : category)
            change(&row)
            rows[key] = row
        }

        var unpriced = 0
        if mode != .realized {
            for h in holdings {
                guard let value = h.value, let gain = h.gain else { unpriced += 1; continue }
                add(productId: h.identity.productId, identity: h.identity, category: h.category) {
                    $0.unrealized += gain
                    $0.value += value
                    $0.costBasis += h.costBasis
                    $0.quantity += h.quantity
                }
            }
        }
        if mode != .unrealized {
            for pos in Ledger(transactions).positions.values where !pos.realized.isEmpty {
                let product = products[pos.identity.productId]
                let category: HoldingCategory = pos.identity.isGraded ? .graded : product?.isSealed == true ? .sealed : .singles
                add(productId: pos.identity.productId, identity: pos.identity, category: category) { $0.realized += pos.realizedGain }
            }
        }

        let all = rows.values.map { r -> Row in var r = r; r.gain = r.unrealized + r.realized; return r }
            .filter { abs($0.gain) >= 0.005 }

        // Keep the biggest movers; fold the long tail into one "others" step,
        // always keeping the biggest losers in view so losses aren't hidden.
        var shown = all
        var other: Row?
        if let maxRows, all.count > maxRows {
            let keepLosers = Array(all.filter { $0.gain < 0 }.sorted { $0.gain < $1.gain }.prefix(min(3, maxRows - 1)))
            let keep = Set(keepLosers.map(\.key))
            let byImpact = all.filter { !keep.contains($0.key) }.sorted { abs($0.gain) > abs($1.gain) }
            let slots = maxRows - 1 - keepLosers.count
            shown = Array(byImpact.prefix(slots)) + keepLosers
            let rest = byImpact.dropFirst(slots)
            var o = Row(key: "__other", label: "\(rest.count) others", members: rest.count)
            for r in rest {
                o.gain += r.gain; o.unrealized += r.unrealized; o.realized += r.realized
                o.value += r.value; o.costBasis += r.costBasis; o.quantity += r.quantity
            }
            other = o
        }

        // Waterfall order: gains (largest first) climb, then losses (largest first) fall.
        var ordered = shown.filter { $0.gain > 0 }.sorted { $0.gain > $1.gain } + shown.filter { $0.gain < 0 }.sorted { $0.gain < $1.gain }
        if let other, abs(other.gain) >= 0.005 { ordered.append(other) }
        var running = 0.0
        let steps = ordered.map { r -> Row in
            var r = r
            r.start = running
            running += r.gain
            r.end = running
            return r
        }

        let positives = all.filter { $0.gain > 0 }.sorted { $0.gain > $1.gain }
        let gains = positives.reduce(0) { $0 + $1.gain }
        let losses = all.filter { $0.gain < 0 }.reduce(0) { $0 + $1.gain }
        return Attribution(
            steps: steps, total: gains + losses, gains: gains, losses: losses,
            winners: positives.count, losers: all.count - positives.count,
            topThreeShare: gains > 0 ? positives.prefix(3).reduce(0) { $0 + $1.gain } / gains : nil,
            unpriced: unpriced, count: all.count
        )
    }
}
