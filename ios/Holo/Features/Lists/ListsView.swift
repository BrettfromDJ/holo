import SwiftUI

/// Cards you're watching for a price, and cards you want to own. Both sync with the website.
struct ListsView: View {
    enum Which: String, CaseIterable { case watchlist = "Watchlist", wishlist = "Wishlist" }

    @Environment(CollectionStore.self) private var store
    @State private var which = Which.watchlist
    @State private var editingWatch: WatchRow?
    @State private var error: String?

    var body: some View {
        NavigationStack {
            List {
                Picker("List", selection: $which) {
                    ForEach(Which.allCases, id: \.self) { Text($0.rawValue) }
                }
                .pickerStyle(.segmented)
                .listRowBackground(Color.clear)
                .listRowInsets(EdgeInsets(top: 4, leading: 0, bottom: 8, trailing: 0))

                if let error { Text(error).foregroundStyle(Theme.down) }

                switch which {
                case .watchlist: watchlist
                case .wishlist: wishlist
                }
            }
            .scrollContentBackground(.hidden)
            .background(Theme.background)
            .navigationTitle("Lists")
            .navigationDestination(for: String.self) { ProductDetailView(productId: $0) }
            .sheet(item: $editingWatch) { w in
                if let p = store.products[w.product_id] {
                    WatchSheet(product: p, printing: w.printing, market: store.marketPrice(w.product_id, printing: w.printing)?.market, existing: w)
                }
            }
        }
    }

    @ViewBuilder private var watchlist: some View {
        if store.watchlist.isEmpty {
            empty("Watch a card's price", "Open any card and tap Watch price. Set a target to see when it drops to what you'd pay.")
        }
        ForEach(store.watchlist) { w in
            let product = store.products[w.product_id]
            let market = store.marketPrice(w.product_id, printing: w.printing)?.market
            NavigationLink(value: w.product_id) {
                ListRow(product: product, price: market, target: w.target_price, change: store.marketPrice(w.product_id, printing: w.printing)?.change24hPct)
            }
            .listRowBackground(Theme.surface)
            .swipeActions {
                Button("Remove", role: .destructive) { Task { await run { try await store.removeWatch(w.id) } } }
                Button("Target") { editingWatch = w }.tint(Theme.surface3)
            }
        }
    }

    @ViewBuilder private var wishlist: some View {
        if store.wishlist.isEmpty {
            empty("Your wishlist is empty", "Open any card and tap Wishlist to keep track of what you want next.")
        }
        ForEach(WishItem.Priority.allCases, id: \.self) { priority in
            let items = store.wishlist.filter { $0.priority == priority }
            if !items.isEmpty {
                Section(priority.label) {
                    ForEach(items) { w in
                        let current = store.marketPrice(w.product.id, printing: w.printing)?.market ?? w.price
                        NavigationLink(value: w.product.id) {
                            ListRow(product: w.product, price: current, target: w.target, change: nil)
                        }
                        .listRowBackground(Theme.surface)
                        .swipeActions {
                            Button("Remove", role: .destructive) { Task { await run { try await store.removeWish(w.id) } } }
                        }
                        .contextMenu {
                            ForEach(WishItem.Priority.allCases, id: \.self) { p in
                                Button(p.label) { Task { await run { try await store.updateWish(w.id, priority: p) } } }
                            }
                        }
                    }
                }
            }
        }
    }

    private func empty(_ title: String, _ body: String) -> some View {
        VStack(alignment: .leading, spacing: 6) {
            Text(title).font(.headline)
            Text(body).font(.callout).foregroundStyle(Theme.muted)
        }
        .padding(.vertical, 8)
        .listRowBackground(Color.clear)
    }

    private func run(_ work: () async throws -> Void) async {
        do {
            error = nil
            try await work()
        } catch {
            self.error = error.localizedDescription
        }
    }
}

extension WishItem.Priority {
    var label: String {
        switch self {
        case .grail: return "Grails"
        case .want: return "Want"
        case .maybe: return "Maybe"
        }
    }
}

/// A watched or wished-for card: price now, and how far it is from your target.
private struct ListRow: View {
    var product: Product?
    var price: Double?
    var target: Double?
    var change: Double?

    var body: some View {
        HStack(spacing: 12) {
            ProductImage(product: product, cornerRadius: 5).frame(width: 40, height: 56)
            VStack(alignment: .leading, spacing: 2) {
                Text(product?.name ?? "Unknown").font(.subheadline.weight(.medium)).lineLimit(1)
                Text(product?.subtitle ?? "").font(.caption).foregroundStyle(Theme.muted).lineLimit(1)
                if let target {
                    let hit = (price ?? .infinity) <= target
                    HStack(spacing: 4) {
                        Text("Target").foregroundStyle(Theme.muted)
                        Text(Format.money(target)).monospacedDigit().foregroundStyle(hit ? Theme.up : .primary)
                        if hit { Text("· hit").foregroundStyle(Theme.muted) }
                    }
                    .font(.caption)
                }
            }
            Spacer()
            VStack(alignment: .trailing, spacing: 2) {
                Text(Format.money(price)).font(.subheadline.weight(.semibold)).monospacedDigit()
                if let change {
                    Text(Format.signedPercent(change / 100)).font(.caption.weight(.medium)).monospacedDigit().foregroundStyle(Theme.tone(change))
                }
            }
        }
    }
}

/// Watch a card's price, with an optional target.
struct WatchSheet: View {
    var product: Product
    var printing: String?
    var market: Double?
    var existing: WatchRow?
    @Environment(\.dismiss) private var dismiss
    @Environment(CollectionStore.self) private var store
    @State private var target = ""
    @State private var saving = false
    @State private var error: String?

    var body: some View {
        NavigationStack {
            Form {
                Section {
                    LabeledContent("Market now") { Text(Format.money(market)).monospacedDigit() }
                    MoneyField(title: "Target price", text: $target, hint: "Optional")
                } footer: {
                    Text("The watchlist shows when it drops to your target.")
                }
                if let error { Section { Text(error).foregroundStyle(Theme.down) } }
            }
            .scrollContentBackground(.hidden)
            .background(Theme.background)
            .navigationTitle(existing == nil ? "Watch price" : "Target price")
            .navigationBarTitleDisplayMode(.inline)
            .toolbar {
                ToolbarItem(placement: .cancellationAction) { Button("Cancel") { dismiss() } }
                ToolbarItem(placement: .confirmationAction) { Button("Save") { Task { await save() } }.disabled(saving) }
            }
            .onAppear {
                if let t = existing?.target_price { target = String(format: "%.2f", t) }
            }
        }
        .presentationDetents([.medium])
    }

    private func save() async {
        saving = true
        error = nil
        defer { saving = false }
        do {
            if let existing {
                try await store.setWatchTarget(existing.id, MoneyField.value(target))
            } else {
                try await store.addWatch(product, printing: printing, target: MoneyField.value(target))
            }
            dismiss()
        } catch {
            self.error = error.localizedDescription
        }
    }
}
