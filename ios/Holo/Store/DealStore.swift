import Foundation
import Observation

/// The deal in progress, your default rates, closed deals and parked deals. Kept in user_state
/// under the same keys as the website ("deal", "deal-rates", "deals", "deals-parked"), so a deal
/// started on one shows on the other.
@Observable
final class DealStore {
    var deal = DealState()
    var defaults = DealRates()
    var log: [DealRecord] = []
    /// Deals set aside to finish later, newest first.
    var parked: [ParkedDeal] = []
    var loaded = false
    var error: String?

    private var userId: String?
    private var saveTask: Task<Void, Never>?
    /// The account's closed and parked deals loaded. A list that failed to load is read again
    /// (and merged with what's here) before it's saved, so a bad connection never empties it.
    @ObservationIgnored private var logSynced = false
    @ObservationIgnored private var parkedSynced = false

    func reset() {
        saveTask?.cancel()
        deal = DealState()
        defaults = DealRates()
        log = []
        parked = []
        loaded = false
        userId = nil
        logSynced = false
        parkedSynced = false
    }

    @MainActor
    func load(userId: String) async {
        self.userId = userId
        // Each key on its own: "no saved value yet" loads as empty, a failed load leaves that key
        // unsynced (see logSynced) instead of looking like an empty list.
        var failure: Error?
        do { deal = try await UserState.load("deal", as: DealState.self) ?? DealState() } catch { failure = error }
        do { defaults = try await UserState.load("deal-rates", as: DealRates.self) ?? DealRates() } catch { failure = error }
        do { log = try await UserState.load("deals", as: [DealRecord].self) ?? []; logSynced = true } catch { failure = error }
        do { parked = try await UserState.load("deals-parked", as: [ParkedDeal].self) ?? []; parkedSynced = true } catch { failure = error }
        self.error = failure?.localizedDescription
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
        Task { await saveLog() }
    }

    /// Replace a closed deal's notes and save the history.
    @MainActor
    func setNotes(_ notes: String, forRecord id: String) {
        guard let i = log.firstIndex(where: { $0.id == id }) else { return }
        let text = notes.trimmingCharacters(in: .whitespacesAndNewlines)
        guard (log[i].notes ?? "") != text else { return }
        log[i].notes = text.isEmpty ? nil : text
        Task { await saveLog() }
    }

    /// Save the closed deals. If the account's list didn't load, read it first and keep both.
    @MainActor
    private func saveLog() async {
        guard let userId else { return }
        if !logSynced {
            do {
                let remote = try await UserState.load("deals", as: [DealRecord].self) ?? []
                let mine = Set(log.map(\.id))
                log = Array((log + remote.filter { !mine.contains($0.id) }).sorted { $0.at > $1.at }.prefix(500))
                logSynced = true
            } catch { return }
        }
        try? await UserState.save("deals", log, userId: userId)
    }

    // MARK: Parked deals

    /// Parked deals are saved to the account only when signed in with your own collection (not a demo).
    private var savesParked: Bool { userId != nil && !Demo.isOn && DemoKind.selected == nil }

    /// Set the open deal aside (photos and notes go with it) and start a fresh one.
    @MainActor
    func park(name: String) {
        guard deal.hasContent else { return }
        let text = name.trimmingCharacters(in: .whitespacesAndNewlines)
        parked.insert(parkedEntry(deal, name: text), at: 0)
        update { $0 = DealState() }
        Task { await saveParked() }
    }

    /// Pick a parked deal back up. An open deal is parked first (the list asks before this runs).
    @MainActor
    func resume(_ entry: ParkedDeal) {
        var list = parked.filter { $0.id != entry.id }
        if deal.hasContent { list.insert(parkedEntry(deal, name: ""), at: 0) }
        parked = list
        // Straight in, agreed cash and all (not through `update`, which would read it as a renegotiation).
        deal = entry.state
        scheduleSave()
        Task { await saveParked() }
    }

    /// Throw a parked deal away, with its photos.
    @MainActor
    func deleteParked(_ entry: ParkedDeal) {
        parked.removeAll { $0.id == entry.id }
        let photos = entry.state.photos
        Task {
            for p in photos { await DealPhotos.delete(p) }
        }
        Task { await saveParked() }
    }

    private func parkedEntry(_ state: DealState, name: String) -> ParkedDeal {
        ParkedDeal(id: UUID().uuidString.lowercased(), name: name.isEmpty ? ParkedDeal.defaultName() : name,
                   savedAt: ISO8601DateFormatter.withFraction.string(from: Date()), state: state)
    }

    /// Save the parked list. If the account's list didn't load, read it first and keep both.
    @MainActor
    private func saveParked() async {
        guard savesParked, let userId else { return }
        if !parkedSynced {
            do {
                let remote = try await UserState.load("deals-parked", as: [ParkedDeal].self) ?? []
                let mine = Set(parked.map(\.id))
                parked += remote.filter { !mine.contains($0.id) }
                parkedSynced = true
            } catch { return }
        }
        try? await UserState.save("deals-parked", parked, userId: userId)
    }

    // MARK: Editing (each change saves shortly after, so quick taps make one write)

    /// Every edit to the open deal goes through here. A change that renegotiates it (a side's %,
    /// a line's % or price or quantity, a line added or removed) lets go of an agreed cash figure,
    /// so the sliders and prices always move the deal again.
    @MainActor
    func update(_ change: (inout DealState) -> Void) {
        let before = deal
        change(&deal)
        if deal.agreedCash != nil, deal.agreedCash == before.agreedCash, deal.renegotiates(from: before) {
            deal.agreedCash = nil
        }
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
        // `-HoloDealMany`: a big deal, to see the customer view's tiles shrink.
        if ProcessInfo.processInfo.arguments.contains("-HoloDealMany") {
            for item in DemoData.items.prefix(12) where !d.incoming.contains(where: { $0.product.id == DemoData.product(item).id }) {
                let p = DemoData.product(item)
                d.incoming.append(DealItem(key: "p:\(p.id)", product: p, printing: p.printings?.first, market: DemoData.series(item).last?.price))
            }
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
        // At the agreed cash, when there is one: the record's prices add up to it.
        let settled = deal.settled(rates: rates)
        let kind = settled.kind
        let totals = DealTotals(settled, rates: rates, cost: { cost(of: $0, in: store) })
        let note = "Show deal (\(kind.noun.lowercased()))"
        let today = Format.day()

        // A demo collection has no account: its entries stay on the phone (CollectionStore keeps
        // them in memory) and the deal history isn't saved.
        let saving = store.demo == nil
        for item in settled.outgoing {
            guard let unit = item.unitPrice(side: rates.out) else { continue }
            if let key = item.holdingKey, let h = store.holding(key: key) {
                try await store.sell(h.identity, quantity: Double(item.qty), unitPrice: unit, fees: 0, shipping: 0, date: today, source: "Card show", notes: note, offerUndo: false)
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
                try await store.sell(identity, quantity: Double(item.qty), unitPrice: unit, fees: 0, shipping: 0, date: today, source: "Card show", notes: note, offerUndo: false)
            }
        }
        var purchases: [CollectionStore.Purchase] = []
        for item in settled.incoming where tracked(item, side: .incoming) {
            guard let unit = item.unitPrice(side: rates.in) else { continue }
            let held = item.holdingKey.flatMap { store.holding(key: $0) }?.identity
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

        let notes = (deal.notes ?? "").trimmingCharacters(in: .whitespacesAndNewlines)
        let lines: [DealRecord.Line] =
            settled.incoming.map { line($0, side: .incoming, rate: rates.in) } + settled.outgoing.map { line($0, side: .outgoing, rate: rates.out) }
        let record = DealRecord(
            id: UUID().uuidString.lowercased(), at: ISO8601DateFormatter.withFraction.string(from: Date()), kind: kind,
            inValue: totals.inValue, outValue: totals.outValue, balance: totals.balance, profit: totals.profit,
            equity: totals.equity, ahead: totals.ahead, uncosted: totals.uncosted,
            items: deal.incoming.count + deal.outgoing.count, lines: lines,
            photos: deal.photos.isEmpty ? nil : deal.photos,
            notes: notes.isEmpty ? nil : notes
        )
        log = Array(([record] + log).prefix(500))
        deal = DealState()
        saveTask?.cancel()
        if saving, let userId {
            await saveLog()
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
        if let key = item.holdingKey, let h = store.holding(key: key) {
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

    /// A card scanned into the deal (from the Deal tab's scanners or the main scanner while a
    /// deal is open): coming in, it's priced from your copy if you own one; going out, it uses
    /// your copy, or goes in marked "not in Lucent".
    @MainActor
    func addScanned(_ c: ScanCandidate, read: ScanRead?, to side: DealSide, store: CollectionStore) -> (ok: Bool, note: String) {
        let grade = read?.kind == "slab" ? read?.grade : nil
        let sameGrade: (HoldingIdentity) -> Bool = { $0.gradeCompany == grade?.company && $0.grade == grade?.grade }
        if side == .incoming {
            if let h = store.allHoldings.first(where: { $0.identity.productId == c.product.id && $0.identity.printing == c.printing && sameGrade($0.identity) }), let p = h.product {
                add(DealItem(key: "h:\(h.identity.key)", product: p, printing: h.identity.printing, market: h.price ?? c.market, holdingKey: h.identity.key), to: .incoming)
            } else {
                let gradeLabel = grade.map { "\($0.company) \($0.grade)" } ?? ""
                add(DealItem(key: "p:\(c.product.id):\(c.printing ?? ""):\(gradeLabel)", product: c.product, printing: c.printing, market: c.value(for: read), grade: grade), to: .incoming)
            }
            return (true, "Added to coming in")
        }
        let owned = store.allHoldings.filter { $0.identity.productId == c.product.id }
        guard let h = owned.first(where: { $0.identity.printing == c.printing && sameGrade($0.identity) }) ?? owned.first, let p = h.product else {
            // Not in Holo: it still goes in the deal, marked so, with an optional "you paid".
            let gradeLabel = grade.map { "\($0.company) \($0.grade)" } ?? ""
            add(DealItem(key: "p:\(c.product.id):\(c.printing ?? ""):\(gradeLabel)", product: c.product, printing: c.printing, market: c.value(for: read), grade: grade), to: .outgoing)
            return (true, "Added · not in Lucent")
        }
        add(DealItem(key: "h:\(h.identity.key)", product: p, printing: h.identity.printing, market: h.price, holdingKey: h.identity.key, maxQty: Int(h.quantity)), to: .outgoing)
        return (true, "Added to going out")
    }
}
