import SwiftUI

/// Pick what's coming in (your inventory or anything in the catalog) or going out (only what you own).
struct DealPickerSheet: View {
    var side: DealSide
    @Environment(\.dismiss) private var dismiss
    @Environment(CollectionStore.self) private var store
    @Environment(DealStore.self) private var deals
    @State private var query = ""
    @State private var results: [SearchHit] = []
    @State private var searching = false
    @State private var added: Set<String> = []

    private var owned: [HoldingView] {
        let q = query.trimmingCharacters(in: .whitespaces).lowercased()
        let all = store.holdings.filter { $0.product != nil }
        guard !q.isEmpty else { return Array(all.prefix(40)) }
        return all.filter { h in
            let p = h.product!
            return p.name.lowercased().contains(q) || (p.setName ?? "").lowercased().contains(q) || (p.number ?? "").lowercased().contains(q)
        }
    }

    var body: some View {
        NavigationStack {
            List {
                Section(side == .outgoing ? "Your inventory" : "In your inventory") {
                    if owned.isEmpty { Text("Nothing matches.").foregroundStyle(Theme.muted) }
                    ForEach(owned) { h in
                        Button { addHolding(h) } label: {
                            HStack {
                                MiniRow(holding: h, trailing: Format.money(h.price), tint: .primary)
                                if side == .outgoing { Text("×\(Int(h.quantity))").font(.caption).foregroundStyle(Theme.muted) }
                                if added.contains(h.id) { Image(systemName: "checkmark").foregroundStyle(Theme.lime) }
                            }
                        }
                        .buttonStyle(.plain)
                    }
                }
                if side == .incoming && query.count >= 2 {
                    Section("Catalog") {
                        if searching && results.isEmpty { ProgressView() }
                        ForEach(results) { hit in
                            Button { addHit(hit) } label: {
                                HStack {
                                    SearchRow(hit: hit)
                                    if added.contains(hit.id) { Image(systemName: "checkmark").foregroundStyle(Theme.lime) }
                                }
                            }
                            .buttonStyle(.plain)
                        }
                    }
                }
            }
            .scrollContentBackground(.hidden)
            .background(Theme.background)
            .searchable(text: $query, placement: .navigationBarDrawer(displayMode: .always), prompt: side == .incoming ? "Search any card or product" : "Search your inventory")
            .navigationTitle(side == .incoming ? "Coming in" : "Going out")
            .navigationBarTitleDisplayMode(.inline)
            .toolbar { ToolbarItem(placement: .confirmationAction) { Button("Done") { dismiss() } } }
            .task(id: query) { await search() }
        }
    }

    private func addHolding(_ h: HoldingView) {
        guard let p = h.product else { return }
        let item = DealItem(
            key: "h:\(h.identity.key)", product: p, printing: h.identity.printing, market: h.price,
            holdingKey: h.identity.key, maxQty: side == .outgoing ? Int(h.quantity) : nil
        )
        deals.add(item, to: side)
        added.insert(h.id)
        UIImpactFeedbackGenerator(style: .light).impactOccurred()
    }

    private func addHit(_ hit: SearchHit) {
        deals.add(DealItem(key: "p:\(hit.product.id):\(hit.printing ?? ""):", product: hit.product, printing: hit.printing, market: hit.market), to: .incoming)
        added.insert(hit.id)
        UIImpactFeedbackGenerator(style: .light).impactOccurred()
    }

    private func search() async {
        guard side == .incoming else { return }
        let q = query.trimmingCharacters(in: .whitespaces)
        guard q.count >= 2 else {
            results = []
            return
        }
        try? await Task.sleep(nanoseconds: 350_000_000)
        guard !Task.isCancelled else { return }
        searching = true
        defer { searching = false }
        if let hits = try? await Backend.shared.api.search(q), !Task.isCancelled { results = hits }
    }
}

/// The rates new deals start at.
struct DealRatesSheet: View {
    @Environment(\.dismiss) private var dismiss
    @Environment(DealStore.self) private var deals
    @State private var rates = DealRates()

    var body: some View {
        NavigationStack {
            Form {
                rate("Buying", "What you pay for cards you buy", \.buy)
                rate("Trade-in", "What you credit for cards taken in on trade", \.trade)
                rate("Selling", "What you charge for cards going out", \.sell)
            }
            .scrollContentBackground(.hidden)
            .background(Theme.background)
            .navigationTitle("Default rates")
            .navigationBarTitleDisplayMode(.inline)
            .toolbar {
                ToolbarItem(placement: .cancellationAction) { Button("Cancel") { dismiss() } }
                ToolbarItem(placement: .confirmationAction) {
                    Button("Save") {
                        deals.setDefaults(rates)
                        dismiss()
                    }
                }
            }
            .onAppear { rates = deals.defaults }
        }
        .presentationDetents([.medium, .large])
    }

    private func rate(_ title: String, _ hint: String, _ key: WritableKeyPath<DealRates, Double>) -> some View {
        Section {
            HStack {
                Text(title)
                Spacer()
                Text("\(Int((rates[keyPath: key] * 100).rounded()))%").monospacedDigit().bold()
            }
            Slider(value: Binding(get: { rates[keyPath: key] }, set: { rates[keyPath: key] = ($0 * 100).rounded() / 100 }), in: 0.3...1.5, step: 0.01)
        } footer: {
            Text("\(hint), as a share of market.")
        }
    }
}

/// Before a deal closes: who pays whom in big numbers, what changes hands on each side, the
/// profit, and one lime button. Recording happens here, so a problem shows right on the sheet,
/// and it ends on a confirmation with what was recorded.
struct DealCloseSheet: View {
    @Environment(\.dismiss) private var dismiss
    @Environment(CollectionStore.self) private var store
    @Environment(DealStore.self) private var deals
    /// The deal as it was when the sheet opened (closing clears the live one).
    @State private var deal: DealState
    @State private var rates: (in: Double, out: Double)
    @State private var phase = Phase.review
    @State private var error: String?

    enum Phase { case review, recording, done }

    init() {
        _deal = State(initialValue: DealState())
        _rates = State(initialValue: (0, 0))
    }

    private var totals: DealTotals { DealTotals(deal, rates: rates, cost: { deals.cost(of: $0, in: store) }) }

    var body: some View {
        let t = totals
        let b = t.balance
        VStack(alignment: .leading, spacing: 0) {
            Capsule().fill(Color.white.opacity(0.2)).frame(width: 40, height: 5).frame(maxWidth: .infinity).padding(.top, 8)
            ScrollView {
                VStack(alignment: .leading, spacing: 22) {
                    if phase == .done {
                        doneView(t)
                    } else {
                        VStack(alignment: .leading, spacing: 8) {
                            SkewTag(text: t.kind.label)
                            DisplayText(text: "CLOSE THIS \(t.kind.noun.uppercased())?", size: 30)
                                .frame(maxWidth: .infinity, alignment: .leading)
                        }
                        // Who pays whom, big enough to turn the phone around.
                        VStack(alignment: .leading, spacing: 8) {
                            MonoLabel(text: abs(b) < 0.005 ? "Even trade" : (b > 0 ? "Customer pays you" : "You pay the customer"))
                            Text(Format.money(abs(b))).font(.display(56)).monospacedDigit().displayTrim(56)
                                .lineLimit(1).minimumScaleFactor(0.5)
                        }
                        .padding(18)
                        .frame(maxWidth: .infinity, alignment: .leading)
                        .liquidGlass(in: RoundedRectangle(cornerRadius: 22, style: .continuous))
                        if !deal.incoming.isEmpty { sideRow(.incoming, deal.incoming, t.inValue) }
                        if !deal.outgoing.isEmpty { sideRow(.outgoing, deal.outgoing, t.outValue) }
                        HStack(spacing: 8) {
                            if let profit = t.profit { pill("Profit", Format.signedMoney(profit), Theme.tone(profit)) }
                            if deal.kind != .sell, t.inValue > 0 { pill("Equity in", Format.signedMoney(t.equity), Theme.tone(t.equity)) }
                        }
                        Text(store.demo != nil
                             ? "This is a demo collection, so nothing is saved: closing just clears the deal."
                             : "Sales and purchases are added to your collection, and the deal goes in your history.")
                            .font(.geist(13)).foregroundStyle(Theme.muted)
                        if let error {
                            Label(error, systemImage: "exclamationmark.triangle.fill")
                                .font(.geist(13, .medium)).foregroundStyle(Theme.warn)
                        }
                    }
                }
                .padding(.horizontal, 20)
                .padding(.top, 14)
                .padding(.bottom, 16)
            }
            VStack(spacing: 8) {
                if phase == .done {
                    Button("Done") { dismiss() }.buttonStyle(Button3D(kind: .lime))
                } else {
                    Button { Task { await close() } } label: {
                        HStack(spacing: 8) {
                            if phase == .recording { ProgressView().tint(Theme.ink) }
                            Text(phase == .recording ? "Recording…" : "Close \(t.kind.noun.lowercased())")
                        }
                    }
                    .buttonStyle(Button3D(kind: .lime))
                    .disabled(phase == .recording)
                    Button("Keep editing") { dismiss() }
                        .buttonStyle(Button3D(kind: .dark))
                        .disabled(phase == .recording)
                }
            }
            .padding(.horizontal, 20)
            .padding(.bottom, 12)
        }
        .background(Theme.background)
        .presentationDetents([.large])
        .presentationDragIndicator(.hidden)
        .interactiveDismissDisabled(phase == .recording)
        .onAppear {
            deal = deals.deal
            rates = deals.rates
        }
    }

    private func sideRow(_ side: DealSide, _ items: [DealItem], _ value: Double) -> some View {
        let incoming = side == .incoming
        let count = items.reduce(0) { $0 + $1.qty }
        return HStack(spacing: 12) {
            Image(systemName: incoming ? "arrow.down.left" : "arrow.up.right")
                .font(.system(size: 14, weight: .bold))
                .foregroundStyle(incoming ? Theme.lime : Theme.planPink)
                .frame(width: 30, height: 30)
                .background(Circle().fill(Color.white.opacity(0.06)))
            VStack(alignment: .leading, spacing: 6) {
                HStack {
                    Text(incoming ? "Coming in" : "Going out").font(.geist(15, .semibold))
                    Text("\(count) item\(count == 1 ? "" : "s")").font(.geist(13)).foregroundStyle(Theme.muted)
                    Spacer()
                    Text(Format.money(value)).font(.geist(15, .semibold)).monospacedDigit()
                }
                // The items themselves, overlapping like a hand of cards.
                HStack(spacing: -10) {
                    ForEach(items.prefix(8)) { i in
                        HoldingArt(product: i.product, identity: nil, cornerRadius: 3, caption: false)
                            .frame(width: 34, height: 48)
                            .shadow(color: .black.opacity(0.5), radius: 4, x: 2)
                    }
                    if items.count > 8 {
                        Text("+\(items.count - 8)").font(.geist(12, .semibold)).foregroundStyle(Theme.muted).padding(.leading, 16)
                    }
                }
            }
        }
        .padding(14)
        .background(RoundedRectangle(cornerRadius: 18, style: .continuous).fill(Theme.surface))
        .overlay(RoundedRectangle(cornerRadius: 18, style: .continuous).strokeBorder(Theme.border))
    }

    private func pill(_ label: String, _ value: String, _ tint: Color) -> some View {
        HStack(spacing: 8) {
            MonoLabel(text: label)
            Text(value).font(.geist(15, .semibold)).monospacedDigit().foregroundStyle(tint)
        }
        .lineLimit(1)
        .padding(.horizontal, 14)
        .frame(height: 38)
        .liquidGlass(in: Capsule())
    }

    private func doneView(_ t: DealTotals) -> some View {
        VStack(spacing: 14) {
            Image(systemName: "checkmark")
                .font(.system(size: 30, weight: .black))
                .foregroundStyle(Theme.ink)
                .frame(width: 72, height: 72)
                .background(Circle().fill(Theme.lime))
                .shadow(color: Theme.lime.opacity(0.5), radius: 18)
                .transition(.scale.combined(with: .opacity))
            DisplayText(text: "\(t.kind.noun.uppercased()) RECORDED", size: 30)
            if let profit = t.profit {
                HStack(spacing: 6) {
                    Text("Profit").foregroundStyle(Theme.muted)
                    Text(Format.signedMoney(profit)).foregroundStyle(Theme.tone(profit))
                }
                .font(.geist(16, .semibold)).monospacedDigit()
            }
            Text(store.demo != nil ? "Demo collection: nothing was saved." : "It's in your collection and in Closed deals.")
                .font(.geist(13)).foregroundStyle(Theme.muted)
        }
        .frame(maxWidth: .infinity)
        .padding(.top, 60)
    }

    private func close() async {
        error = nil
        phase = .recording
        do {
            _ = try await deals.close(using: store)
            UINotificationFeedbackGenerator().notificationOccurred(.success)
            withAnimation(.spring(duration: 0.45)) { phase = .done }
        } catch {
            UINotificationFeedbackGenerator().notificationOccurred(.error)
            self.error = "Couldn't record it: \(error.localizedDescription)"
            phase = .review
        }
    }
}
