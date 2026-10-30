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

/// Closed deals, newest first, by day with the day's cash and profit.
struct DealHistorySheet: View {
    @Environment(\.dismiss) private var dismiss
    @Environment(DealStore.self) private var deals

    private var days: [(day: String, records: [DealRecord])] {
        let grouped = Dictionary(grouping: deals.log) { Format.day($0.date) }
        return grouped.keys.sorted(by: >).map { ($0, grouped[$0]!.sorted { $0.at > $1.at }) }
    }

    var body: some View {
        NavigationStack {
            List {
                if deals.log.isEmpty {
                    Text("Closed deals show up here.").foregroundStyle(Theme.muted)
                }
                ForEach(days, id: \.day) { group in
                    Section {
                        ForEach(group.records) { r in DealRecordRow(record: r) }
                    } header: {
                        HStack {
                            Text(Format.isoDay.date(from: group.day)?.formatted(date: .abbreviated, time: .omitted) ?? group.day)
                            Spacer()
                            let cash = group.records.reduce(0) { $0 + $1.balance }
                            let profit = group.records.compactMap(\.profit).reduce(0, +)
                            Text("Cash \(Format.signedMoney(cash))").monospacedDigit()
                            Text("· Profit").foregroundStyle(Theme.muted)
                            Text(Format.signedMoney(profit)).monospacedDigit().foregroundStyle(Theme.tone(profit))
                        }
                    }
                }
            }
            .scrollContentBackground(.hidden)
            .background(Theme.background)
            .navigationTitle("Closed deals")
            .navigationBarTitleDisplayMode(.inline)
            .toolbar { ToolbarItem(placement: .confirmationAction) { Button("Done") { dismiss() } } }
        }
    }
}

private struct DealRecordRow: View {
    var record: DealRecord
    @State private var open = false

    var body: some View {
        VStack(alignment: .leading, spacing: 8) {
            Button { withAnimation { open.toggle() } } label: {
                HStack {
                    VStack(alignment: .leading, spacing: 2) {
                        Text(record.kind.noun).font(.subheadline.weight(.semibold))
                        Text("\(record.items) item\(record.items == 1 ? "" : "s") · \(record.date.formatted(date: .omitted, time: .shortened))")
                            .font(.caption).foregroundStyle(Theme.muted)
                    }
                    Spacer()
                    VStack(alignment: .trailing, spacing: 2) {
                        Text(record.balance >= 0 ? "Received \(Format.money(record.balance))" : "Paid \(Format.money(-record.balance))")
                            .font(.subheadline.weight(.semibold)).monospacedDigit()
                        if let profit = record.profit {
                            Text(Format.signedMoney(profit)).font(.caption.weight(.medium)).monospacedDigit().foregroundStyle(Theme.tone(profit))
                        }
                    }
                }
                .contentShape(Rectangle())
            }
            .buttonStyle(.plain)
            if open, let lines = record.lines {
                ForEach(Array(lines.enumerated()), id: \.offset) { _, line in
                    HStack {
                        Image(systemName: line.side == .incoming ? "arrow.down.left" : "arrow.up.right").font(.caption).foregroundStyle(Theme.muted)
                        Text("\(Int(line.qty))× \(line.product.name)").font(.caption).lineLimit(1)
                        Spacer()
                        Text(Format.money(line.price * line.qty)).font(.caption).monospacedDigit()
                    }
                }
            }
        }
    }
}
