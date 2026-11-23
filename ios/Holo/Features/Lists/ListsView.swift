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
    /// How both lists are ordered (kept on the phone).
    @AppStorage("lists-sort") private var sortRaw = ListSort.recent.rawValue
    @State private var sorting = false
    private var sort: ListSort { ListSort(rawValue: sortRaw) ?? .recent }
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

                if !currentIds.isEmpty && !selecting { sortRow }

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
                // The target as a row, then Stop watching as the same pink button the Wishlist's
                // Remove from wishlist uses.
                [
                    [SheetAction(title: w.target_price == nil ? "Set a target price" : "Edit target price", icon: "scope") { editingWatch = w }],
                    [SheetAction(title: "Stop watching", icon: "eye.slash", destructive: true) {
                        Task { await run { try await store.removeWatch(w.id) } }
                    }],
                ]
            }
            .sheet(item: $editingWatch) { w in
                if let p = store.products[w.product_id] {
                    WatchSheet(product: p, printing: w.printing, market: store.listPrice(w.product_id, printing: w.printing)?.market, existing: w)
                }
            }
    }

    @ViewBuilder private var watchlist: some View {
        ForEach(sortedWatches) { w in
            let product = store.products[w.product_id]
            let price = store.listPrice(w.product_id, printing: w.printing)
            Group {
                if selecting {
                    selectRow(w.id) { ListRow(product: product, price: price?.market, change: price?.change24hPct, target: w.target_price) }
                } else {
                    // Tapping the row opens the card; a ⋯ (instead of the arrow) opens its actions:
                    // set or edit the target, stop watching. Holding the row does the same.
                    HStack(spacing: 4) {
                        ListRow(product: product, price: price?.market, change: price?.change24hPct, target: w.target_price)
                        RowMoreButton(label: product?.name) { heldWatch = w }
                    }
                    .background { NavigationLink(value: w.product_id) { EmptyView() }.opacity(0) }
                }
            }
            .listRowBackground(ListRowPanel())
            .listRowInsets(EdgeInsets(top: 14, leading: 30, bottom: 14, trailing: 28))
            .listRowSeparator(.hidden)
            // Press and hold for its actions (our own sheet; Apple's swipe buttons clashed:
            // square-cut row, lime Remove with white text).
            .highPriorityGesture(LongPressGesture(minimumDuration: 0.35).onEnded { _ in Haptics.tap(); heldWatch = w }, including: selecting ? .subviews : .all)
        }
    }

    @ViewBuilder private var wishlist: some View {
        let items = sortedWishes
        ForEach(items) { w in
                        let current = store.listPrice(w.product.id, printing: w.printing)?.market ?? w.price
                        Group {
                            if selecting {
                                selectRow(w.id) { ListRow(product: w.product, price: current, change: store.listPrice(w.product.id, printing: w.printing)?.change24hPct, target: w.target, addedPrice: w.addedPrice) }
                            } else {
                                // The ⋯ opens the card's quick actions (the same as holding it).
                                HStack(spacing: 4) {
                                    ListRow(product: w.product, price: current, change: store.listPrice(w.product.id, printing: w.printing)?.change24hPct, target: w.target, addedPrice: w.addedPrice)
                                    RowMoreButton(label: w.product.name) { Router.shared.quickCard = w.product }
                                }
                                .background { NavigationLink(value: w.product.id) { EmptyView() }.opacity(0) }
                                .highPriorityGesture(LongPressGesture(minimumDuration: 0.35).onEnded { _ in Haptics.tap(); Router.shared.quickCard = w.product })
                            }
                        }
                        .listRowBackground(ListRowPanel())
            .listRowInsets(EdgeInsets(top: 14, leading: 30, bottom: 14, trailing: 28))
            .listRowSeparator(.hidden)
                        // Holding the card opens its quick actions (wishlist on/off and more).
        }
    }

    // MARK: Sort

    private var sortedWatches: [WatchRow] {
        let rows = store.watchlist
        let price = { (w: WatchRow) in store.listPrice(w.product_id, printing: w.printing) }
        switch sort {
        case .recent: return rows.sorted { $0.created_at > $1.created_at }
        case .price: return rows.sorted { (price($0)?.market ?? -1) > (price($1)?.market ?? -1) }
        case .move: return rows.sorted { abs(price($0)?.change24hPct ?? 0) > abs(price($1)?.change24hPct ?? 0) }
        case .name: return rows.sorted { (store.products[$0.product_id]?.name ?? "") < (store.products[$1.product_id]?.name ?? "") }
        }
    }

    private var sortedWishes: [WishItem] {
        let rows = store.wishlist
        let now = { (w: WishItem) in store.listPrice(w.product.id, printing: w.printing)?.market ?? w.price }
        // Biggest move: since you added it when we know, else today's.
        let move = { (w: WishItem) -> Double in
            if let a = w.addedPrice, a > 0, let n = now(w) { return abs(n - a) / a * 100 }
            return abs(store.listPrice(w.product.id, printing: w.printing)?.change24hPct ?? 0)
        }
        switch sort {
        case .recent: return rows.sorted { $0.addedAt > $1.addedAt }
        case .price: return rows.sorted { (now($0) ?? -1) > (now($1) ?? -1) }
        case .move: return rows.sorted { move($0) > move($1) }
        case .name: return rows.sorted { $0.product.name < $1.product.name }
        }
    }

    /// "Sort: Recently added ⌄" on the right above the rows; opens our sheet.
    private var sortRow: some View {
        HStack {
            Spacer()
            Button { Haptics.tap(); sorting = true } label: {
                HStack(spacing: 5) {
                    Image(systemName: "arrow.up.arrow.down").font(.system(size: 11, weight: .semibold))
                    Text(sort.label).font(.geist(13, .medium))
                    Image(systemName: "chevron.down").font(.system(size: 9, weight: .bold))
                }
                .foregroundStyle(Theme.muted)
                .padding(.vertical, 6)
                .contentShape(Rectangle())
            }
            .buttonStyle(.borderless)
            .accessibilityLabel("Sort: \(sort.label)")
        }
        .listRowBackground(Color.clear)
        .listRowSeparator(.hidden)
        .listRowInsets(EdgeInsets(top: 0, leading: 16, bottom: 0, trailing: 20))
        .actionsSheet(isPresented: $sorting, title: "Sort by") {
            [ListSort.allCases.map { option in
                SheetAction(title: option.label, checked: option == sort) { sortRaw = option.rawValue }
            }]
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
                Group {
                    if chosen.isEmpty {
                        Text("Select cards").foregroundStyle(Theme.muted)
                            .frame(maxWidth: .infinity).frame(height: 50)
                            .background(Capsule().fill(Color.white.opacity(0.08)))
                    } else {
                        Text(which == .watchlist ? "Stop watching \(chosen.count)" : "Remove \(chosen.count)")
                            .frame(maxWidth: .infinity).frame(height: 50)
                            .dangerStyle(Capsule(), solid: true)
                    }
                }
                .font(.geist(16, .semibold))
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
/// How the Watchlist and Wishlist are ordered.
enum ListSort: String, CaseIterable {
    case recent, price, move, name
    var label: String {
        switch self {
        case .recent: "Recently added"
        case .price: "Price"
        case .move: "Biggest move"
        case .name: "Name"
        }
    }
}

/// A watched or wished-for card: bigger art, its name (without the number repeated), set and
/// number, the price and today's move (no pill when it hasn't moved), and one line under it: how
/// far it is from your target, or how much it's moved since you added it.
private struct ListRow: View {
    var product: Product?
    var price: Double?
    /// Today's change, in percent.
    var change: Double?
    var target: Double? = nil
    /// The price when it went on the wishlist.
    var addedPrice: Double? = nil

    var body: some View {
        HStack(spacing: 12) {
            ProductImage(product: product, cornerRadius: 5).frame(width: 48, height: 67)
            VStack(alignment: .leading, spacing: 3) {
                Text(title).font(.subheadline.weight(.medium)).lineLimit(1)
                Text(product?.subtitle ?? "").font(.caption).foregroundStyle(Theme.muted).lineLimit(1)
                detail.font(.caption).lineLimit(1).padding(.top, 1)
            }
            Spacer(minLength: 8)
            VStack(alignment: .trailing, spacing: 4) {
                Text(Format.money(price)).font(.subheadline.weight(.semibold)).monospacedDigit()
                if let change, abs(change) >= 0.05 {
                    DeltaPill(ratio: change / 100, size: 11)
                }
            }
        }
    }

    /// "Mega Darkrai ex - 116/084" → "Mega Darkrai ex" (the number is on the line under it).
    private var title: String {
        guard let name = product?.name else { return "Unknown" }
        if let n = product?.number, !n.isEmpty, name.hasSuffix(" - \(n)") { return String(name.dropLast(n.count + 3)) }
        return name
    }

    @ViewBuilder private var detail: some View {
        if let target {
            if let price, price <= target {
                // Reached: only the figure is coloured.
                HStack(spacing: 4) {
                    Image(systemName: "checkmark.circle.fill").foregroundStyle(Theme.lime)
                    Text("Target").foregroundStyle(Theme.muted)
                    Text(Format.money(target)).monospacedDigit().foregroundStyle(Theme.lime)
                    Text("reached").foregroundStyle(Theme.muted)
                }
            } else if let price, price > 0 {
                let away = (price - target) / price
                (Text("Target ").foregroundColor(Theme.muted)
                    + Text(Format.money(target)).foregroundColor(.white)
                    + Text(" · \(Int((away * 100).rounded()))% away").foregroundColor(Theme.muted))
                    .monospacedDigit()
            } else {
                (Text("Target ").foregroundColor(Theme.muted) + Text(Format.money(target)).foregroundColor(.white)).monospacedDigit()
            }
        } else if let addedPrice, addedPrice > 0, let price, abs(price - addedPrice) >= 0.01 {
            let d = price - addedPrice
            (Text(Format.signedMoney(d)).foregroundColor(Theme.tone(d)) + Text(" since added").foregroundColor(Theme.muted))
                .monospacedDigit()
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

/// A Watchlist / Wishlist row's panel: a little lighter than the page, with a faint light edge,
/// so each row reads as its own card on the dark background.
private struct ListRowPanel: View {
    var body: some View {
        let shape = RoundedRectangle(cornerRadius: 16, style: .continuous)
        shape.fill(Color(hex: 0x1A1A1D))
            .overlay(shape.strokeBorder(Color.white.opacity(0.07), lineWidth: 1))
            .padding(.horizontal, 16).padding(.vertical, 4)
    }
}
