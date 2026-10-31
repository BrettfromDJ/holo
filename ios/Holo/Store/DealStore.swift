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

    /// The signed-in account photos are stored under (nil keeps them on the phone, as in a demo).
    var accountId: String? { userId }

    /// Replace a closed deal's photos and save the history.
    @MainActor
    func setPhotos(_ photos: [String], forRecord id: String) {
        guard let i = log.firstIndex(where: { $0.id == id }) else { return }
        log[i].photos = photos.isEmpty ? nil : photos
        guard let userId else { return }
        let snapshot = log
        Task { try? await UserState.save("deals", snapshot, userId: userId) }
    }

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
        if let h = store.allHoldings.first(where: { $0.identity.productId == "sample:umbreon-vmax-alt" }) ?? store.allHoldings.first, let p = h.product {
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

        // A demo collection has no account: its entries stay on the phone (CollectionStore keeps
        // them in memory) and the deal history isn't saved.
        let saving = store.demo == nil
        for item in deal.outgoing {
            guard let unit = item.unitPrice(side: rates.out) else { continue }
            if let key = item.holdingKey, let h = store.allHoldings.first(where: { $0.identity.key == key }) {
                try await store.sell(h.identity, quantity: Double(item.qty), unitPrice: unit, fees: 0, shipping: 0, date: today, source: "Card show", notes: note)
            } else if !item.isCustom, let cost = item.cost {
                // Not in Holo, but you said what you paid: record that purchase, then the sale,
                // so your books (and this profit) come out right.
                let identity = HoldingIdentity(
                    productId: item.product.id, printing: item.printing,
                    condition: item.product.isSealed ? "Sealed" : CardCondition.nearMint.rawValue,
                    gradeCompany: item.grade?.company, grade: item.grade?.grade
                )
                try await store.add([CollectionStore.Purchase(
                    product: item.product, printing: item.printing, condition: identity.condition,
                    gradeCompany: identity.gradeCompany, grade: identity.grade, quantity: Double(item.qty), unitPrice: cost,
                    date: today, source: "Card show", notes: "Added from a deal"
                )])
                try await store.sell(identity, quantity: Double(item.qty), unitPrice: unit, fees: 0, shipping: 0, date: today, source: "Card show", notes: note)
            }
        }
        var purchases: [CollectionStore.Purchase] = []
        for item in deal.incoming where tracked(item, side: .incoming) {
            guard let unit = item.unitPrice(side: rates.in) else { continue }
            let held = item.holdingKey.flatMap { key in store.allHoldings.first { $0.identity.key == key } }?.identity
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
        if !purchases.isEmpty { try await store.add(purchases) }

        let lines: [DealRecord.Line] =
            deal.incoming.map { line($0, side: .incoming, rate: rates.in) } + deal.outgoing.map { line($0, side: .outgoing, rate: rates.out) }
        let record = DealRecord(
            id: UUID().uuidString.lowercased(), at: ISO8601DateFormatter.withFraction.string(from: Date()), kind: kind,
            inValue: totals.inValue, outValue: totals.outValue, balance: totals.balance, profit: totals.profit,
            equity: totals.equity, items: deal.incoming.count + deal.outgoing.count, lines: lines,
            photos: deal.photos.isEmpty ? nil : deal.photos
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
            price: item.unitPrice(side: rate) ?? 0,
            untracked: tracked(item, side: side) ? nil : true
        )
    }

    /// Your cost for an outgoing row: from your inventory the oldest units first, like the sale
    /// will be recorded; for something not in Holo, what you said you paid.
    func cost(of item: DealItem, in store: CollectionStore) -> Double? {
        if let key = item.holdingKey, let h = store.allHoldings.first(where: { $0.identity.key == key }) {
            return round2(h.fifoCost(Double(item.qty)))
        }
        return item.cost.map { round2($0 * Double(item.qty)) }
    }

    /// Whether closing records this line in your collection.
    func tracked(_ item: DealItem, side: DealSide) -> Bool {
        if item.isCustom { return false }
        if side == .incoming { return item.track ?? defaults.addsIncoming }
        return item.holdingKey != nil || item.cost != nil
    }

    /// What closing will do to your collection, for the closing sheet.
    func effects(_ deal: DealState) -> (adds: Int, sells: Int, untracked: Int) {
        let adds = deal.incoming.filter { tracked($0, side: .incoming) }.reduce(0) { $0 + $1.qty }
        let sells = deal.outgoing.filter { tracked($0, side: .outgoing) }.reduce(0) { $0 + $1.qty }
        let all = deal.incoming.reduce(0) { $0 + $1.qty } + deal.outgoing.reduce(0) { $0 + $1.qty }
        return (adds, sells, all - adds - sells)
    }
}
