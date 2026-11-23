import SwiftUI

/// Cards you're watching for a price, and cards you want to own. Both sync with the website.
struct ListsView: View {
    enum Which: String, CaseIterable { case watchlist = "Watchlist", wishlist = "Wishlist" }

    @Environment(CollectionStore.self) private var store
    @State private var which: Which
    @State private var editingWatch: WatchRow?
    /// A held watchlist row: its actions in our sheet.
    @State private var heldWatch: WatchRow?
    /// Select mode: tick rows, then remove them all at once.
    @State private var selecting = false
    @State private var chosen: Set<String> = []
    @State private var error: String?
    /// Pushed inside another page's navigation (Lists), not shown as its own sheet.
    var embedded = false

    init(which: Which = .watchlist, embedded: Bool = false) {
        _which = State(initialValue: which)
        self.embedded = embedded
    }

    var body: some View {
        if embedded { page } else { NavigationStack { page.navigationDestination(for: String.self) { ProductDetailView(productId: $0) } } }
    }

    private var page: some View {
            List {
                if !embedded {
                    Picker("List", selection: $which) {
                        ForEach(Which.allCases, id: \.self) { Text($0.rawValue) }
                    }
                    .pickerStyle(.segmented)
                    .listRowBackground(Color.clear)
                    .listRowInsets(EdgeInsets(top: 4, leading: 0, bottom: 8, trailing: 0))
                }

                if let error { Text(error).foregroundStyle(Theme.down) }

                switch which {
                case .watchlist: watchlist
                case .wishlist: wishlist
                }
            }
            // Plain rows, each its own panel with a 16pt corner (the grouped list's sections
            // rounded much more than our other panels).
            .listStyle(.plain)
            // The first row starts just under the title (no tall gap above the list).
            .contentMargins(.top, 4, for: .scrollContent)
            .scrollContentBackground(.hidden)
            .background(Theme.background)
            .overlay { emptyState }
            // Prices for cards added to either list since the collection loaded.
            .task(id: store.watchlist.count + store.wishlist.count) {
                await store.loadListPrices(store.watchlist.map(\.product_id) + store.wishlist.map(\.product.id))
            }
            .navigationBarTitleDisplayMode(.inline)
            .pageTitle(which.rawValue)
            // Select (or Done) at the top right, while there's anything to select.
            .toolbar {
                ToolbarItem(placement: .topBarTrailing) {
                    if !currentIds.isEmpty || selecting {
                        Button(selecting ? "Done" : "Select") { setSelecting(!selecting) }
                            .font(.geist(15, .semibold))
                    }
                }
            }
            // The select bar takes the tab bar's place.
            .safeAreaInset(edge: .bottom, spacing: 0) {
                if selecting { selectBar.padding(.horizontal, 16).padding(.bottom, 8).transition(.move(edge: .bottom).combined(with: .opacity)) }
            }
            .animation(.snappy(duration: 0.25), value: selecting)
            .onChange(of: which) { setSelecting(false) }
            .onDisappear { if selecting { setSelecting(false) } }
            .actionsSheet(item: $heldWatch, title: { store.products[$0.product_id]?.name }, product: { store.products[$0.product_id] }) { w in
                [[
                    SheetAction(title: w.target_price == nil ? "Set target" : "Edit target", icon: "scope") { editingWatch = w },
                    SheetAction(title: "Stop watching", icon: "eye.slash", destructive: true) {
                        Task { await run { try await store.removeWatch(w.id) } }
                    },
                ]]
            }
            .sheet(item: $editingWatch) { w in
                if let p = store.products[w.product_id] {
                    WatchSheet(product: p, printing: w.printing, market: store.listPrice(w.product_id, printing: w.printing)?.market, existing: w)
                }
            }
    }

    @ViewBuilder private var watchlist: some View {
        ForEach(store.watchlist) { w in
            let product = store.products[w.product_id]
            let price = store.listPrice(w.product_id, printing: w.printing)
            Group {
                if selecting {
                    selectRow(w.id) { ListRow(product: product, price: price?.market, target: w.target_price, change: price?.change24hPct) }
                } else {
                    NavigationLink(value: w.product_id) {
                        ListRow(product: product, price: price?.market, target: w.target_price, change: price?.change24hPct)
                    }
                }
            }
            .listRowBackground(RoundedRectangle(cornerRadius: 16, style: .continuous).fill(Theme.surface).padding(.horizontal, 16).padding(.vertical, 4))
            .listRowInsets(EdgeInsets(top: 14, leading: 30, bottom: 14, trailing: 28))
            .listRowSeparator(.hidden)
            // Press and hold for its actions (our own sheet; Apple's swipe buttons clashed:
            // square-cut row, lime Remove with white text).
            .highPriorityGesture(LongPressGesture(minimumDuration: 0.35).onEnded { _ in Haptics.tap(); heldWatch = w }, including: selecting ? .subviews : .all)
        }
    }

    @ViewBuilder private var wishlist: some View {
        ForEach(WishItem.Priority.allCases, id: \.self) { priority in
            let items = store.wishlist.filter { $0.priority == priority }
            if !items.isEmpty {
                Section(priority.label) {
                    ForEach(items) { w in
                        let current = store.listPrice(w.product.id, printing: w.printing)?.market ?? w.price
                        Group {
                            if selecting {
                                selectRow(w.id) { ListRow(product: w.product, price: current, target: w.target, change: nil) }
                            } else {
                                CardLink(productId: w.product.id, product: w.product) {
                                    ListRow(product: w.product, price: current, target: w.target, change: nil)
                                }
                            }
                        }
                        .listRowBackground(RoundedRectangle(cornerRadius: 16, style: .continuous).fill(Theme.surface).padding(.horizontal, 16).padding(.vertical, 4))
            .listRowInsets(EdgeInsets(top: 14, leading: 30, bottom: 14, trailing: 28))
            .listRowSeparator(.hidden)
                        // Holding the card opens its quick actions (wishlist on/off and more).
                    }
                }
            }
        }
    }

    private var currentIds: [String] { which == .watchlist ? store.watchlist.map(\.id) : store.wishlist.map(\.id) }

    private func setSelecting(_ on: Bool) {
        selecting = on
        chosen = []
        Router.shared.tabBarHidden = on
    }

    /// A row in select mode: a round check, then the row; tapping ticks it.
    private func selectRow<Content: View>(_ id: String, @ViewBuilder content: () -> Content) -> some View {
        let on = chosen.contains(id)
        return Button {
            if on { chosen.remove(id) } else { chosen.insert(id) }
        } label: {
            HStack(spacing: 12) {
                Image(systemName: on ? "checkmark.circle.fill" : "circle")
                    .font(.system(size: 22, weight: .medium))
                    .foregroundStyle(on ? Theme.lime : Theme.subtle)
                content()
            }
            .contentShape(Rectangle())
        }
        .buttonStyle(.plain)
        .sensoryFeedback(.selection, trigger: on)
    }

    /// How many are ticked, Select all, and remove them.
    private var selectBar: some View {
        let all = currentIds
        let allOn = !all.isEmpty && chosen.count == all.count
        return HStack(spacing: 10) {
            Button(allOn ? "Clear" : "Select all") { chosen = allOn ? [] : Set(all) }
                .font(.geist(15, .semibold)).foregroundStyle(.white)
                .padding(.horizontal, 16).frame(height: 50)
                .liquidGlass(in: Capsule(), interactive: true)
                .buttonStyle(.plain)
            Button {
                let ids = chosen
                let watch = which == .watchlist
                setSelecting(false)
                Task { await run { if watch { try await store.removeWatches(ids) } else { try await store.removeWishes(ids) } } }
            } label: {
                Text(chosen.isEmpty ? "Select cards" : (which == .watchlist ? "Stop watching \(chosen.count)" : "Remove \(chosen.count)"))
                    .font(.geist(16, .semibold)).foregroundStyle(.white)
                    .frame(maxWidth: .infinity).frame(height: 50)
                    .background(Capsule().fill(chosen.isEmpty ? Color.white.opacity(0.08) : Theme.planPink))
            }
            .buttonStyle(.plain)
            .disabled(chosen.isEmpty)
        }
        .padding(8)
        .liquidGlass(in: Capsule())
    }

    /// The page with nothing on it yet: an icon in a glass circle, a heading and one line, centred
    /// in the middle of the screen, and a way to go and find cards.
    @ViewBuilder private var emptyState: some View {
        let watch = which == .watchlist
        if watch ? store.watchlist.isEmpty : store.wishlist.isEmpty {
            VStack(spacing: 14) {
                Image(systemName: watch ? "eye" : "heart")
                    .font(.system(size: 26, weight: .medium)).foregroundStyle(.white)
                    .frame(width: 72, height: 72)
                    .liquidGlass(in: Circle())
                    .padding(.bottom, 6)
                Text(watch ? "Watch a card's price" : "Your wishlist is empty")
                    .font(.display(24)).tracking(-0.6).foregroundStyle(.white)
                Text(watch ? "Open any card and tap Watch price. Set a target and you'll hear when it drops to what you'd\u{00A0}pay."
                           : "Open any card and tap Add to wishlist to keep track of what you want\u{00A0}next.")
                    .font(.geist(15)).foregroundStyle(Theme.muted)
                    .multilineTextAlignment(.center)
                    .frame(maxWidth: 300)
                Button { Haptics.tap(); Router.shared.tabRequest = "explore" } label: {
                    Text("Explore cards").font(.geist(15, .semibold)).foregroundStyle(.white)
                        .padding(.horizontal, 22).frame(height: 44)
                        .liquidGlass(in: Capsule(), interactive: true)
                }
                .buttonStyle(.plain)
                .padding(.top, 10)
            }
            .padding(.horizontal, 32)
            .frame(maxWidth: .infinity, maxHeight: .infinity)
            // A little above the middle, which reads as centred with the tab bar below.
            .padding(.bottom, 80)
        }
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
                    DeltaPill(ratio: change / 100, size: 11)
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

    var body: some View { sheetBody.glassSheet() }

    @ViewBuilder private var sheetBody: some View {
        NavigationStack {
            GlassForm {
                Section {
                    LabeledContent("Market now") { Text(Format.money(market)).monospacedDigit() }
                    MoneyField(title: "Target price", text: $target, hint: "Optional")
                } footer: {
                    Text("With a target, you get a notification when the daily price check finds it at or below\u{00A0}it.").font(.geist(13)).foregroundStyle(Theme.muted)
                }
                if let error { Section { Text(error).foregroundStyle(Theme.down) } }
            }
            .scrollContentBackground(.hidden)
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
            // A target means you'll want to hear when it's hit.
            if MoneyField.value(target) != nil { await PushRegistration.enable() }
            dismiss()
        } catch {
            self.error = error.localizedDescription
        }
    }
}
