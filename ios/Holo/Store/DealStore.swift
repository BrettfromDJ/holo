import Foundation
import Observation

/// The deal in progress, your default rates and closed deals. Kept in user_state under the
/// same keys as the website ("deal", "deal-rates", "deals"), so a deal started on one shows on the other.
@Observable
final class DealStore {
    var deal = DealState()
    var defaults = DealRates()
    var log: [DealRecord] = []
    var loaded = false
    var error: String?

    private var userId: String?
    private var saveTask: Task<Void, Never>?

    func reset() {
        saveTask?.cancel()
        deal = DealState()
        defaults = DealRates()
        log = []
        loaded = false
        userId = nil
    }

    @MainActor
    func load(userId: String) async {
        self.userId = userId
        do {
            deal = try await UserState.load("deal", as: DealState.self) ?? DealState()
            defaults = try await UserState.load("deal-rates", as: DealRates.self) ?? DealRates()
            log = try await UserState.load("deals", as: [DealRecord].self) ?? []
            error = nil
        } catch {
            self.error = error.localizedDescription
        }
        loaded = true
    }

    var rates: (in: Double, out: Double) { deal.rates(defaults) }

    // MARK: Editing (each change saves shortly after, so quick taps make one write)

    @MainActor
    func update(_ change: (inout DealState) -> Void) {
        change(&deal)
        scheduleSave()
    }

    @MainActor
    func add(_ item: DealItem, to side: DealSide) {
        update { d in
            func merge(_ items: inout [DealItem]) {
                if let i = items.firstIndex(where: { $0.key == item.key }) {
                    items[i].qty = min(items[i].qty + 1, items[i].maxQty ?? .max)
                } else {
                    items.append(item)
                }
            }
            if side == .incoming { merge(&d.incoming) } else { merge(&d.outgoing) }
        }
    }

    /// Screenshots (`-HoloDealDemo`): two items coming in from the catalog and one going out
    /// from the demo collection. Never saved: there's no account in demo mode.
    @MainActor
    func loadDemo(from store: CollectionStore) {
        var d = DealState()
        for slug in ["charizard-ex-151", "cz-etb"] {
            guard let item = DemoData.items.first(where: { $0.slug == slug }) else { continue }
            let p = DemoData.product(item)
            d.incoming.append(DealItem(key: "p:\(p.id)", product: p, printing: p.printings?.first, market: DemoData.series(item).last?.price, qty: slug == "cz-etb" ? 2 : 1))
        }
        if let h = store.holdings.first(where: { $0.identity.productId == "sample:umbreon-vmax-alt" }) ?? store.holdings.first, let p = h.product {
            d.outgoing.append(DealItem(key: "h:\(h.identity.key)", product: p, printing: h.identity.printing, market: h.price, holdingKey: h.identity.key, maxQty: Int(h.quantity)))
        }
        deal = d
    }

    @MainActor
    func setDefaults(_ rates: DealRates) {
        defaults = rates
        guard let userId else { return }
        Task { try? await UserState.save("deal-rates", rates, userId: userId) }
    }

    @MainActor
    private func scheduleSave() {
        saveTask?.cancel()
        let snapshot = deal
        let userId = userId
        saveTask = Task {
            try? await Task.sleep(nanoseconds: 600_000_000)
            guard !Task.isCancelled, let userId else { return }
            try? await UserState.save("deal", snapshot, userId: userId)
        }
    }

    // MARK: Closing

    /// Record everything in your inventory: sales for what goes out, purchases for what comes in
    /// (at what you gave for it, so later profit is measured from the deal). Then log it and start fresh.
    @MainActor
    func close(using store: CollectionStore) async throws -> DealTotals {
        let rates = self.rates
        let kind = deal.kind
        let totals = DealTotals(deal, rates: rates, cost: { cost(of: $0, in: store) })
        let note = "Show deal (\(kind.noun.lowercased()))"
        let today = Format.day()

        // A demo collection has no account to save to: the deal is just logged here and cleared.
        let saving = store.demo == nil
        for item in deal.outgoing where saving {
            guard let key = item.holdingKey, let h = store.holdings.first(where: { $0.identity.key == key }), let unit = item.unitPrice(side: rates.out) else { continue }
            try await store.sell(h.identity, quantity: Double(item.qty), unitPrice: unit, fees: 0, shipping: 0, date: today, source: "Card show", notes: note)
        }
        var purchases: [CollectionStore.Purchase] = []
        for item in deal.incoming {
            guard let unit = item.unitPrice(side: rates.in) else { continue }
            let held = item.holdingKey.flatMap { key in store.holdings.first { $0.identity.key == key } }?.identity
            purchases.append(CollectionStore.Purchase(
                product: item.product,
                printing: held?.printing ?? item.printing,
                condition: held?.condition ?? (item.product.isSealed ? "Sealed" : CardCondition.nearMint.rawValue),
                gradeCompany: held?.gradeCompany ?? item.grade?.company,
                grade: held?.grade ?? item.grade?.grade,
                quantity: Double(item.qty),
                unitPrice: unit,
                date: today,
                source: "Card show",
                notes: note
            ))
        }
        if saving, !purchases.isEmpty { try await store.add(purchases) }

        let lines: [DealRecord.Line] =
            deal.incoming.map { line($0, side: .incoming, rate: rates.in) } + deal.outgoing.map { line($0, side: .outgoing, rate: rates.out) }
        let record = DealRecord(
            id: UUID().uuidString.lowercased(), at: ISO8601DateFormatter.withFraction.string(from: Date()), kind: kind,
            inValue: totals.inValue, outValue: totals.outValue, balance: totals.balance, profit: totals.profit,
            equity: totals.equity, items: deal.incoming.count + deal.outgoing.count, lines: lines
        )
        log = Array(([record] + log).prefix(500))
        deal = DealState()
        saveTask?.cancel()
        if saving, let userId {
            try? await UserState.save("deals", log, userId: userId)
            try? await UserState.save("deal", deal, userId: userId)
        }
        return totals
    }

    private func line(_ item: DealItem, side: DealSide, rate: Double) -> DealRecord.Line {
        let p = item.product
        return DealRecord.Line(
            side: side,
            product: .init(id: p.id, name: p.name, imageUrl: p.imageUrl, kind: p.kind, setName: p.setName, productType: p.productType),
            qty: Double(item.qty),
            price: item.unitPrice(side: rate) ?? 0
        )
    }

    /// Your cost for an outgoing row: the oldest units first, like the sale will be recorded.
    func cost(of item: DealItem, in store: CollectionStore) -> Double? {
        guard let key = item.holdingKey, let h = store.holdings.first(where: { $0.identity.key == key }) else { return nil }
        return round2(h.fifoCost(Double(item.qty)))
    }
}
