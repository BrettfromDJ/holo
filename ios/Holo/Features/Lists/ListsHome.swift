import CoreImage.CIFilterBuiltins
import SwiftUI

/// Where a Lists link goes: one of your lists, or the built-in watchlist and wishlist.
enum ListRoute: Hashable {
    case list(String)
    case watchlist
    case wishlist
}

/// What a card on a list is worth, and your copy of it, worked out the same way everywhere.
@MainActor
struct ListItemInfo {
    var product: Product?
    /// Your copies of it (most valuable first); empty when you don't own it.
    var copies: [HoldingView]
    var market: Double?
    /// How many to count in totals: what you own, or one.
    var count: Double { max(1, copies.reduce(0) { $0 + $1.quantity }) }
    var copyLabel: String? {
        guard let top = copies.first else { return nil }
        return top.identity.gradeLabel ?? top.identity.condition
    }

    /// `owned`: your holdings by product id, built once per page (see `ownedIndex`), so a page
    /// with many cards doesn't search the whole collection once per card.
    init(_ productId: String, store: CollectionStore, groups: GroupsStore, owned: [String: [HoldingView]]? = nil) {
        product = store.products[productId] ?? groups.extraProducts[productId]
        let mine = owned.map { $0[productId] ?? [] } ?? store.allHoldings.filter { $0.identity.productId == productId }
        copies = mine.filter { $0.quantity > 0 }.sorted { ($0.price ?? -1) > ($1.price ?? -1) }
        market = copies.first?.price
            ?? store.marketPrice(productId, printing: product?.printings?.first)?.market
            ?? groups.extraMarket[productId]
    }
}

extension ListItemInfo {
    static func ownedIndex(_ store: CollectionStore) -> [String: [HoldingView]] {
        Dictionary(grouping: store.allHoldings, by: \.identity.productId)
    }
}

/// Name a list: its own small sheet, so typing redraws only the box (not the page behind it).
struct ListNameSheet: View {
    var title: String
    var initial = ""
    var action: String
    var onSave: (String) async throws -> Void
    @Environment(\.dismiss) private var dismiss
    @State private var text = ""
    @State private var saving = false
    @State private var error: String?
    @FocusState private var focused: Bool

    private var trimmed: String { String(text.trimmingCharacters(in: .whitespaces).prefix(40)) }

    var body: some View {
        VStack(alignment: .leading, spacing: 16) {
            HStack {
                Button("Cancel") { dismiss() }.font(.geist(16)).foregroundStyle(.white)
                Spacer()
                Text(title).font(.geist(17, .semibold)).foregroundStyle(.white)
                Spacer()
                Button(action) { save() }.font(.geist(16, .semibold))
                    .foregroundStyle(trimmed.isEmpty ? Theme.subtle : Theme.lime)
                    .disabled(trimmed.isEmpty || saving)
            }
            TextField("Favorite SIRs, For sale at the show…", text: $text)
                .font(.geist(17))
                .focused($focused)
                .submitLabel(.done)
                .onSubmit { save() }
                .padding(.horizontal, 14).frame(height: 50)
                .background(RoundedRectangle(cornerRadius: 14).fill(Color.white.opacity(0.08)))
            if let error { Text(error).font(.geist(13)).foregroundStyle(.white) }
            Spacer(minLength: 0)
        }
        .padding(20)
        .presentationDetents([.height(200)])
        .glassSheet()
        .onAppear {
            text = initial
            focused = true
        }
    }

    private func save() {
        let name = trimmed
        guard !name.isEmpty, !saving else { return }
        saving = true
        Task {
            do {
                try await onSave(name)
                dismiss()
            } catch {
                self.error = error.localizedDescription
                saving = false
            }
        }
    }
}

// MARK: - Lists home

/// Every list: your own (favorites, want lists, cards to sell at a show) and the built-in
/// watchlist and wishlist.
struct ListsHomeView: View {
    @Environment(CollectionStore.self) private var store
    @Environment(GroupsStore.self) private var groups
    @State private var naming = false
    /// A list just made: opened right away so you can add cards.
    @State private var opened: String?
    @State private var error: String?

    private let columns = [GridItem(.flexible(), spacing: 12), GridItem(.flexible(), spacing: 12)]

    var body: some View {
        ScrollView {
            VStack(alignment: .leading, spacing: 28) {
                HStack(alignment: .firstTextBaseline) {
                    VStack(alignment: .leading, spacing: 4) {
                        DisplayText(text: "Lists", size: 40)
                        Text("Favorites, want lists and cards to sell").font(.geist(14)).foregroundStyle(Theme.muted)
                    }
                    Spacer()
                    Button {
                        Haptics.tap()
                        naming = true
                    } label: {
                        Label("New", systemImage: "plus").font(.geist(14, .semibold)).foregroundStyle(Theme.ink)
                            .padding(.horizontal, 14).frame(height: 36)
                            .background(Capsule().fill(Theme.lime))
                    }
                    .buttonStyle(.plain)
                }
                if let error { Text(error).font(.geist(13)).foregroundStyle(Theme.down) }

                if groups.shelves.isEmpty {
                    VStack(alignment: .leading, spacing: 6) {
                        Text("No lists yet").font(.geist(17, .semibold))
                        Text("Make one for your favorite illustration rares, a want list, or the cards you're taking to a show to sell. You can share any list as a link.")
                            .font(.geist(14)).foregroundStyle(Theme.muted)
                    }
                    .frame(maxWidth: .infinity, alignment: .leading)
                    .surface(radius: 18, padding: 16)
                } else {
                    LazyVGrid(columns: columns, spacing: 12) {
                        let owned = ListItemInfo.ownedIndex(store)
                        ForEach(groups.shelves) { list in
                            NavigationLink(value: ListRoute.list(list.id)) { ListTile(list: list, owned: owned) }
                                .buttonStyle(.plain)
                        }
                    }
                }

                VStack(alignment: .leading, spacing: 12) {
                    MoreHeading(title: "Tracking", subtitle: nil)
                    // Even rows: the card's edge sits as far from each row as the rows sit from
                    // each other, and the line between them starts under the text.
                    VStack(spacing: 0) {
                        trackRow(.watchlist, "Watchlist", "Prices you're watching", icon: "eye", count: store.watchlist.count)
                        Rectangle().fill(Color.white.opacity(0.06)).frame(height: 1).padding(.leading, 48)
                        trackRow(.wishlist, "Wishlist", "Cards you want next", icon: "heart", count: store.wishlist.count)
                    }
                    .padding(.horizontal, 14)
                    .surface(radius: 18, padding: nil)
                }
            }
            .padding(.horizontal, 16)
            .padding(.top, 8)
            .padding(.bottom, 120)
        }
        .background(Theme.background)
        .navigationBarTitleDisplayMode(.inline)
        .pageTitle("Lists")
        .task { await groups.loadExtras(groups.shelves.flatMap(\.product_ids), known: store.products) }
        .sheet(isPresented: $naming) {
            ListNameSheet(title: "New list", action: "Create") { name in
                let list = try await groups.createShelf(name)
                DispatchQueue.main.asyncAfter(deadline: .now() + 0.35) { opened = list.id }
            }
        }
        .navigationDestination(item: $opened) { ListDetailView(listId: $0) }
    }

    private func trackRow(_ route: ListRoute, _ title: String, _ sub: String, icon: String, count: Int) -> some View {
        NavigationLink(value: route) {
            HStack(spacing: 12) {
                Image(systemName: icon).font(.system(size: 15, weight: .semibold)).foregroundStyle(Theme.lime)
                    .frame(width: 36, height: 36).background(Circle().fill(Theme.lime.opacity(0.12)))
                VStack(alignment: .leading, spacing: 1) {
                    Text(title).font(.geist(15, .semibold)).foregroundStyle(.white)
                    Text(sub).font(.geist(12)).foregroundStyle(Theme.muted)
                }
                Spacer()
                Text("\(count)").font(.geist(15, .semibold)).monospacedDigit().foregroundStyle(count == 0 ? Theme.muted : .white)
                Image(systemName: "chevron.right").font(.system(size: 12, weight: .semibold)).foregroundStyle(Theme.subtle)
            }
            .padding(.vertical, 12)
            .contentShape(Rectangle())
        }
        .buttonStyle(.plain)
    }
}

/// A list on the Lists page: its cards fanned in a dark well, then its name, count and worth.
/// An empty list shows three dashed card outlines with a plus, inviting you in.
private struct ListTile: View {
    var list: GroupsStore.Shelf
    var owned: [String: [HoldingView]]
    @Environment(CollectionStore.self) private var store
    @Environment(GroupsStore.self) private var groups

    /// The well's solid black (and the empty placeholders', so they match).
    static let wellColor = Color(red: 0.07, green: 0.07, blue: 0.08)

    private static func worth(_ infos: [ListItemInfo]) -> Double {
        var total: Double = 0
        for info in infos { total += (info.market ?? 0) * info.count }
        return total
    }

    var body: some View {
        let meta = groups.meta(list.id)
        let infos = list.product_ids.map { ListItemInfo($0, store: store, groups: groups, owned: owned) }
        let total = Self.worth(infos)
        let shown = Array(infos.filter { $0.product != nil }.sorted { ($0.market ?? 0) > ($1.market ?? 0) }.prefix(3))
        let count = list.product_ids.count
        VStack(alignment: .leading, spacing: 12) {
            ZStack {
                if shown.isEmpty { emptyFan } else { fan(shown) }
            }
            .frame(maxWidth: .infinity)
            .frame(height: 112)
            .background(RoundedRectangle(cornerRadius: 14, style: .continuous).fill(Self.wellColor))
            .clipShape(RoundedRectangle(cornerRadius: 14, style: .continuous))
            .overlay(alignment: .topLeading) {
                if meta.isForSale {
                    Text("For sale").font(.geist(10, .semibold)).foregroundStyle(Theme.ink)
                        .padding(.horizontal, 7).padding(.vertical, 3)
                        .background(Capsule().fill(Theme.lime))
                        .padding(8)
                }
            }
            VStack(alignment: .leading, spacing: 2) {
                Text(list.name).font(.geist(15, .semibold)).foregroundStyle(.white).lineLimit(1)
                Group {
                    if count == 0 {
                        Text("Empty · tap to add")
                    } else {
                        Text("\(count) card\(count == 1 ? "" : "s") · \(Format.money(total))").monospacedDigit()
                    }
                }
                .font(.geist(12)).foregroundStyle(Theme.muted).lineLimit(1)
            }
            .padding(.horizontal, 4)
        }
        .padding(8)
        .frame(maxWidth: .infinity, alignment: .leading)
        .liquidGlass(in: RoundedRectangle(cornerRadius: 20, style: .continuous))
        .contentShape(RoundedRectangle(cornerRadius: 20, style: .continuous))
    }

    private func fan(_ shown: [ListItemInfo]) -> some View {
        let mid = Double(shown.count - 1) / 2
        return ZStack {
            ForEach(Array(shown.enumerated()), id: \.offset) { i, info in
                ProductImage(product: info.product, cornerRadius: 4)
                    .frame(width: 58, height: 80)
                    .shadow(color: .black.opacity(0.5), radius: 6, y: 3)
                    .rotationEffect(.degrees((Double(i) - mid) * 10), anchor: .bottom)
                    .offset(x: (Double(i) - mid) * 30, y: 6)
                    .zIndex(-abs(Double(i) - mid))
            }
        }
    }

    private var emptyFan: some View {
        ZStack {
            // Tilted about their centres, so the fan sits in the middle of the well; solid in the
            // well's black, so the cards behind don't show through. The middle one is in front.
            ForEach(0..<3, id: \.self) { i in
                let shape = RoundedRectangle(cornerRadius: 6, style: .continuous)
                shape.fill(Self.wellColor)
                    .overlay(shape.strokeBorder(Color.white.opacity(0.22), style: StrokeStyle(lineWidth: 1, dash: [4, 4])))
                    .frame(width: 54, height: 74)
                    .rotationEffect(.degrees(Double(i - 1) * 10))
                    .offset(x: Double(i - 1) * 28)
                    .zIndex(i == 1 ? 1 : 0)
            }
            Image(systemName: "plus").font(.system(size: 18, weight: .semibold)).foregroundStyle(Theme.lime)
                .frame(width: 36, height: 36)
                .background(Circle().fill(Self.wellColor))
                .overlay(Circle().strokeBorder(Theme.lime.opacity(0.4), lineWidth: 1))
                .zIndex(2)
        }
    }
}

// MARK: - One list

/// One list: its cards, what they're worth, and for a list you're selling, your asking prices.
struct ListDetailView: View {
    var listId: String
    @Environment(CollectionStore.self) private var store
    @Environment(GroupsStore.self) private var groups
    @Environment(\.dismiss) private var dismiss
    @State private var adding = false
    @State private var sharing = false
    @State private var renaming = false
    @State private var deleting = false
    /// The card whose price is being set.
    @State private var pricing: String?
    @State private var error: String?

    private static let percents: [Double] = [100, 95, 90, 85, 80, 75, 70]

    var body: some View {
        if let list = groups.shelves.first(where: { $0.id == listId }) {
            page(list)
        } else {
            Text("This list was deleted.").font(.geist(15)).foregroundStyle(Theme.muted)
                .frame(maxWidth: .infinity, maxHeight: .infinity).background(Theme.background)
        }
    }

    private func page(_ list: GroupsStore.Shelf) -> some View {
        let meta = groups.meta(listId)
        let owned = ListItemInfo.ownedIndex(store)
        let items = list.product_ids.map { ($0, ListItemInfo($0, store: store, groups: groups, owned: owned)) }
        let totals = Self.totals(items, meta: meta)
        let marketTotal = totals.market
        let askTotal = totals.asking
        let cards = totals.cards
        return ScrollView {
            VStack(alignment: .leading, spacing: 24) {
                VStack(alignment: .leading, spacing: 8) {
                    DisplayText(text: list.name, size: 34)
                    if meta.isForSale {
                        Text(Format.money(askTotal)).font(.display(44)).tracking(-1.2).monospacedDigit().foregroundStyle(Theme.lime)
                            .lineLimit(1).minimumScaleFactor(0.6)
                        Text("Asking for \(cards) card\(cards == 1 ? "" : "s") · \(Format.money(marketTotal)) at market")
                            .font(.geist(14)).monospacedDigit().foregroundStyle(Theme.muted)
                    } else {
                        Text("\(cards) card\(cards == 1 ? "" : "s") · \(Format.money(marketTotal)) at market")
                            .font(.geist(14)).monospacedDigit().foregroundStyle(Theme.muted)
                    }
                }
                actions
                if let error { Text(error).font(.geist(13)).foregroundStyle(Theme.down) }
                saleCard(meta)
                if items.isEmpty {
                    VStack(alignment: .leading, spacing: 6) {
                        Text("Nothing on this list yet").font(.geist(17, .semibold))
                        Text("Add cards from your collection or anywhere in the catalog. You don't have to own them.")
                            .font(.geist(14)).foregroundStyle(Theme.muted)
                    }
                    .frame(maxWidth: .infinity, alignment: .leading)
                    .surface(radius: 18, padding: 16)
                } else {
                    VStack(spacing: 0) {
                        ForEach(Array(items.enumerated()), id: \.offset) { i, item in
                            if i > 0 { Rectangle().fill(Color.white.opacity(0.06)).frame(height: 1) }
                            row(item.0, item.1, meta: meta)
                        }
                    }
                    .surface(radius: 18, padding: 14)
                }
            }
            .padding(.horizontal, 16)
            .padding(.top, 8)
            .padding(.bottom, 120)
        }
        .background(Theme.background)
        .navigationBarTitleDisplayMode(.inline)
        .pageTitle("List")
        .task { await groups.loadExtras(list.product_ids, known: store.products) }
        .sheet(isPresented: $adding) { ListAddSheet(listId: listId) }
        .sheet(isPresented: $sharing) { ListShareSheet(listId: listId, name: list.name, forSale: meta.isForSale) }
        .sheet(isPresented: $renaming) {
            ListNameSheet(title: "Rename list", initial: list.name, action: "Save") { name in
                try await groups.renameShelf(listId, to: name)
            }
        }
        .confirmationDialog("Delete \(list.name)?", isPresented: $deleting, titleVisibility: .visible) {
            Button("Delete list", role: .destructive) {
                Task {
                    do {
                        try? await groups.stopSharing(listId)
                        try await groups.removeShelf(listId)
                        dismiss()
                    } catch { self.error = error.localizedDescription }
                }
            }
        } message: {
            Text("The list goes, and its share link stops working. Your cards stay in your collection.")
        }
        .sheet(isPresented: Binding(get: { pricing != nil }, set: { if !$0 { pricing = nil } })) {
            if let id = pricing {
                let info = ListItemInfo(id, store: store, groups: groups)
                ListItemPriceSheet(listId: listId, productId: id, product: info.product, market: info.market)
            }
        }
    }

    private static func totals(_ items: [(String, ListItemInfo)], meta: ListMeta) -> (market: Double, asking: Double, cards: Int) {
        var market: Double = 0
        var asking: Double = 0
        var cards: Double = 0
        for (id, info) in items {
            let n = info.count
            market += (info.market ?? 0) * n
            asking += (ListPricing.asking(meta, productId: id, market: info.market) ?? 0) * n
            cards += n
        }
        return (market, asking, Int(cards))
    }

    private var actions: some View {
        HStack(spacing: 10) {
            Button {
                Haptics.tap()
                adding = true
            } label: {
                Label("Add cards", systemImage: "plus").font(.geist(15, .semibold)).foregroundStyle(.white)
                    .frame(maxWidth: .infinity).frame(height: 46)
                    .liquidGlass(in: Capsule())
            }
            .buttonStyle(.plain)
            Button {
                Haptics.tap()
                sharing = true
            } label: {
                Label("Share", systemImage: "square.and.arrow.up").font(.geist(15, .semibold)).foregroundStyle(Theme.ink)
                    .frame(maxWidth: .infinity).frame(height: 46)
                    .background(Capsule().fill(Theme.lime))
            }
            .buttonStyle(.plain)
            // Rename and delete: a full-size button in the page, not a small icon in the top bar.
            Menu {
                Button { renaming = true } label: { Label("Rename", systemImage: "pencil") }
                Button(role: .destructive) { deleting = true } label: { Label("Delete list", systemImage: "trash") }
            } label: {
                Image(systemName: "ellipsis").font(.system(size: 17, weight: .semibold)).foregroundStyle(.white)
                    .frame(width: 46, height: 46)
                    .liquidGlass(in: Circle())
                    .contentShape(Circle())
            }
            .accessibilityLabel("More")
        }
    }

    /// For sale: on or off, and how much of market to ask.
    private func saleCard(_ meta: ListMeta) -> some View {
        VStack(alignment: .leading, spacing: 14) {
            Toggle(isOn: Binding(get: { meta.isForSale }, set: { on in
                Haptics.tap()
                run { try await groups.updateMeta(listId) { $0.forSale = on } }
            })) {
                VStack(alignment: .leading, spacing: 2) {
                    Text("For sale").font(.geist(15, .semibold)).foregroundStyle(.white)
                    Text("Show asking prices on this list and its link").font(.geist(12)).foregroundStyle(Theme.muted)
                }
            }
            if meta.isForSale {
                VStack(alignment: .leading, spacing: 8) {
                    MonoLabel(text: "Asking, of market")
                    ChipPicker(options: Self.percents.map { ($0, "\(Int($0))%") },
                               selection: Binding(get: { meta.askPercent ?? 100 }, set: { pct in
                                   run { try await groups.updateMeta(listId) { $0.askPercent = pct == 100 ? nil : pct } }
                               }), scrolls: true)
                    Text("Tap a card's price to give it its own % or a set price.").font(.geist(12)).foregroundStyle(Theme.subtle)
                }
            }
        }
        .surface(radius: 18, padding: 16)
    }

    private func row(_ productId: String, _ info: ListItemInfo, meta: ListMeta) -> some View {
        let asking = ListPricing.asking(meta, productId: productId, market: info.market)
        // Priced on its own (a typed price or its own %), not by the list's %.
        let own = meta.prices?[productId] != nil || meta.percents?[productId] != nil
        return HStack(spacing: 12) {
            CardLink(productId: productId, identity: info.copies.first?.identity) {
                HStack(spacing: 12) {
                    ProductImage(product: info.product, cornerRadius: 4).frame(width: 44, height: 62)
                    VStack(alignment: .leading, spacing: 3) {
                        Text(info.product?.name ?? "Loading…").font(.geist(14, .semibold)).foregroundStyle(.white).lineLimit(2)
                        Text(detail(info)).font(.geist(12)).foregroundStyle(Theme.muted).lineLimit(1)
                    }
                    Spacer(minLength: 4)
                }
                .contentShape(Rectangle())
            }
            .buttonStyle(.plain)
            if meta.isForSale {
                Button {
                    Haptics.tap()
                    pricing = productId
                } label: {
                    VStack(alignment: .trailing, spacing: 2) {
                        Text(Format.money(asking)).font(.geist(15, .semibold)).monospacedDigit().foregroundStyle(.white)
                            .padding(.horizontal, 8).padding(.vertical, 3)
                            .background(RoundedRectangle(cornerRadius: 8).strokeBorder(own ? Theme.lime : Color.white.opacity(0.16), lineWidth: 1))
                        Text("market \(Format.money(info.market))").font(.geist(11)).monospacedDigit().foregroundStyle(Theme.muted)
                    }
                }
                .buttonStyle(.plain)
                .accessibilityLabel("Asking \(Format.money(asking)). Change price")
            } else {
                Text(Format.money(info.market)).font(.geist(15, .semibold)).monospacedDigit().foregroundStyle(.white)
            }
            Menu {
                if meta.isForSale {
                    Button { pricing = productId } label: { Label("Set its price", systemImage: "tag") }
                }
                Button(role: .destructive) {
                    Haptics.remove()
                    run { try await groups.removeMany(listId, productIds: [productId]) }
                } label: { Label("Remove from list", systemImage: "minus.circle") }
            } label: {
                Image(systemName: "ellipsis").font(.system(size: 14, weight: .semibold)).foregroundStyle(Theme.muted)
                    .frame(width: 36, height: 44).contentShape(Rectangle())
            }
        }
        .padding(.vertical, 8)
    }

    private func detail(_ info: ListItemInfo) -> String {
        var parts: [String] = []
        if let set = info.product?.setName { parts.append(set) }
        if let label = info.copyLabel {
            let n = Int(info.copies.reduce(0) { $0 + $1.quantity })
            parts.append(n > 1 ? "\(label) ×\(n)" : label)
        } else if info.product != nil {
            parts.append("Not in your collection")
        }
        return parts.joined(separator: " · ")
    }

    private func run(_ work: @escaping () async throws -> Void) {
        Task {
            do {
                error = nil
                try await work()
            } catch {
                self.error = error.localizedDescription
            }
        }
    }
}

// MARK: - One card's price

/// A card's asking price on a list you're selling: the list's %, its own %, or a set price.
struct ListItemPriceSheet: View {
    var listId: String
    var productId: String
    var product: Product?
    var market: Double?
    @Environment(\.dismiss) private var dismiss
    @Environment(GroupsStore.self) private var groups
    /// 0 follows the list's percentage.
    @State private var percent: Double = 0
    @State private var priceText = ""
    @State private var error: String?
    @FocusState private var typing: Bool

    private static let percents: [Double] = [0, 100, 95, 90, 85, 80, 75, 70, 65, 60]

    private var meta: ListMeta { groups.meta(listId) }
    private var typed: Double? { MoneyField.value(priceText) }
    private var listPercent: Double { meta.askPercent ?? 100 }

    private var asking: Double? {
        if let typed { return typed }
        guard let market else { return nil }
        return (market * (percent == 0 ? listPercent : percent)).rounded() / 100
    }

    var body: some View { sheetBody.presentationDetents([.medium, .large]).glassSheet() }

    private var sheetBody: some View {
        ScrollView {
            VStack(alignment: .leading, spacing: 22) {
                HStack {
                    Button("Cancel") { dismiss() }.font(.geist(16)).foregroundStyle(.white)
                    Spacer()
                    Text("Your price").font(.geist(17, .semibold)).foregroundStyle(.white)
                    Spacer()
                    Button("Save") { save() }.font(.geist(16, .semibold)).foregroundStyle(Theme.lime)
                }
                HStack(spacing: 12) {
                    ProductImage(product: product, cornerRadius: 4).frame(width: 44, height: 62)
                    VStack(alignment: .leading, spacing: 3) {
                        Text(product?.name ?? "Card").font(.geist(15, .semibold)).foregroundStyle(.white).lineLimit(2)
                        Text("Market \(Format.money(market))").font(.geist(13)).monospacedDigit().foregroundStyle(Theme.muted)
                    }
                    Spacer(minLength: 0)
                }
                VStack(alignment: .leading, spacing: 4) {
                    MonoLabel(text: "Asking")
                    Text(Format.money(asking)).font(.display(44)).tracking(-1.2).monospacedDigit().foregroundStyle(.white)
                        .contentTransition(.numericText())
                        .animation(.snappy, value: asking)
                }
                VStack(alignment: .leading, spacing: 8) {
                    MonoLabel(text: "Percentage of market")
                    ChipPicker(options: Self.percents.map { ($0, $0 == 0 ? "List \(Int(listPercent))%" : "\(Int($0))%") },
                               selection: Binding(get: { typed == nil ? percent : -1 }, set: { pct in
                                   Haptics.tap()
                                   percent = pct
                                   priceText = ""
                                   typing = false
                               }), scrolls: true)
                }
                VStack(alignment: .leading, spacing: 8) {
                    MonoLabel(text: "Or a set price")
                    HStack {
                        Text("$").foregroundStyle(Theme.muted)
                        TextField("0.00", text: $priceText).keyboardType(.decimalPad).focused($typing).monospacedDigit()
                    }
                    .font(.geist(17))
                    .padding(.horizontal, 14).frame(height: 48)
                    .background(RoundedRectangle(cornerRadius: 14).fill(Color.white.opacity(0.06)))
                    .overlay(RoundedRectangle(cornerRadius: 14).strokeBorder(typed != nil ? Theme.lime : Color.white.opacity(0.08), lineWidth: 1))
                }
                if let error { Text(error).font(.geist(13)).foregroundStyle(.white) }
            }
            .padding(20)
        }
        .onAppear {
            percent = meta.percents?[productId] ?? 0
            if let own = meta.prices?[productId] { priceText = String(format: "%.2f", own) }
        }
    }

    private func save() {
        let price = typed
        let pct = percent
        Task {
            do {
                try await groups.updateMeta(listId) { m in
                    var prices = m.prices ?? [:]
                    var percents = m.percents ?? [:]
                    prices[productId] = price
                    percents[productId] = price == nil && pct != 0 ? pct : nil
                    m.prices = prices
                    m.percents = percents
                }
                Haptics.tap()
                dismiss()
            } catch { self.error = error.localizedDescription }
        }
    }
}

// MARK: - Add cards

/// Put cards on a list: from your collection, or anything in the catalog.
struct ListAddSheet: View {
    var listId: String
    @Environment(\.dismiss) private var dismiss
    @Environment(CollectionStore.self) private var store
    @Environment(GroupsStore.self) private var groups
    @State private var query = ""
    @State private var results: [SearchHit] = []
    @State private var searching = false
    @State private var error: String?
    @FocusState private var focused: Bool

    private var onList: Set<String> { Set(groups.shelves.first { $0.id == listId }?.product_ids ?? []) }

    /// Your collection, one row per product, filtered by the search.
    private var owned: [HoldingView] {
        let q = query.trimmingCharacters(in: .whitespaces).lowercased()
        var seen = Set<String>()
        let all = store.allHoldings.filter { $0.product != nil }.sorted { ($0.value ?? 0) > ($1.value ?? 0) }
            .filter { seen.insert($0.identity.productId).inserted }
        guard !q.isEmpty else { return Array(all.prefix(60)) }
        return all.filter { h in
            let p = h.product!
            return p.name.lowercased().contains(q) || (p.setName ?? "").lowercased().contains(q) || (p.number ?? "").lowercased().contains(q)
        }
    }

    var body: some View { sheetBody.presentationDetents([.fraction(0.93)]).glassSheet() }

    @ViewBuilder private var sheetBody: some View {
        let owned = self.owned
        let onList = self.onList
        NavigationStack {
            GlassList {
                if let error { Text(error).foregroundStyle(Theme.down) }
                if query.count >= 2 {
                    Section("Catalog") {
                        if !searching && results.isEmpty { Text("Nothing found.").foregroundStyle(Theme.muted) }
                        ForEach(results) { hit in
                            Button { add(hit) } label: {
                                HStack {
                                    SearchRow(hit: hit)
                                    mark(onList.contains(hit.product.id))
                                }
                            }
                            .buttonStyle(.plain)
                        }
                    }
                }
                Section("Your collection") {
                    if owned.isEmpty { Text("Nothing matches.").foregroundStyle(Theme.muted) }
                    ForEach(owned) { h in
                        Button { toggle(h.identity.productId) } label: {
                            HStack {
                                MiniRow(holding: h, trailing: Format.money(h.price), tint: .white)
                                mark(onList.contains(h.identity.productId))
                            }
                        }
                        .buttonStyle(.plain)
                    }
                }
            }
            .scrollContentBackground(.hidden)
            .contentMargins(.top, 0, for: .scrollContent)
            .imageMaxPixel(360)
            .safeAreaInset(edge: .top, spacing: 0) {
                HoloSearchField(text: $query, prompt: "Search your cards or any card", focus: $focused, loading: searching)
                    .padding(.horizontal, 16).padding(.vertical, 8)
            }
            .scrollDismissesKeyboard(.immediately)
            .navigationTitle("Add cards")
            .navigationBarTitleDisplayMode(.inline)
            .toolbar { ToolbarItem(placement: .confirmationAction) { Button("Done") { dismiss() } } }
            .task(id: query) { await search() }
        }
    }

    private func mark(_ on: Bool) -> some View {
        Image(systemName: on ? "checkmark.circle.fill" : "plus.circle")
            .font(.system(size: 20))
            .foregroundStyle(on ? Theme.lime : Color.white.opacity(0.3))
    }

    private func toggle(_ productId: String) {
        Haptics.tap()
        Task {
            do {
                if onList.contains(productId) {
                    try await groups.removeMany(listId, productIds: [productId])
                } else {
                    try await groups.addMany(listId, productIds: [productId])
                }
            } catch { self.error = error.localizedDescription }
        }
    }

    private func add(_ hit: SearchHit) {
        Haptics.tap()
        if onList.contains(hit.product.id) { return toggle(hit.product.id) }
        groups.remember(hit.product, market: hit.market)
        Task {
            do {
                // Into the catalog first, so the list (and its link) can find it later.
                try await store.ensureInCatalog(hit.product, printing: hit.printing)
                try await groups.addMany(listId, productIds: [hit.product.id])
            } catch { self.error = error.localizedDescription }
        }
    }

    private func search() async {
        let q = query.trimmingCharacters(in: .whitespaces)
        guard q.count >= 2 else { results = []; return }
        try? await Task.sleep(nanoseconds: 350_000_000)
        guard !Task.isCancelled else { return }
        searching = true
        defer { searching = false }
        if let hits = try? await Backend.shared.api.search(q), !Task.isCancelled { results = hits }
    }
}

// MARK: - Share

/// A list's link and QR code: a vendor scans it and sees the cards, conditions and prices on a
/// web page (no sign-in), never what you paid. The link can be turned off.
struct ListShareSheet: View {
    var listId: String
    var name: String
    var forSale: Bool
    @Environment(\.dismiss) private var dismiss
    @Environment(GroupsStore.self) private var groups
    @State private var url: URL?
    @State private var error: String?
    @State private var copied = false

    var body: some View { sheetBody.presentationDetents([.fraction(0.93)]).glassSheet() }

    private var sheetBody: some View {
        ScrollView {
            VStack(spacing: 20) {
                HStack {
                    Text("Share list").font(.geist(17, .semibold)).foregroundStyle(.white)
                    Spacer()
                    Button("Done") { dismiss() }.font(.geist(16, .semibold)).foregroundStyle(Theme.lime)
                }
                VStack(spacing: 6) {
                    DisplayText(text: name, size: 26)
                    Text(forSale ? "Show this to a vendor. They see each card, its condition, market price and your asking price. Never what you paid."
                                 : "Anyone with the link sees the cards on this list and their market prices. Never what you paid.")
                        .font(.geist(14)).foregroundStyle(Theme.muted).multilineTextAlignment(.center)
                }
                ZStack {
                    RoundedRectangle(cornerRadius: 24, style: .continuous).fill(.white)
                    if let url, let qr = Self.qr(url.absoluteString) {
                        Image(uiImage: qr).interpolation(.none).resizable().scaledToFit().padding(18)
                    }
                }
                .frame(width: 240, height: 240)
                .opacity(url == nil ? 0.15 : 1)
                if let error {
                    Text(error).font(.geist(14)).foregroundStyle(.white).multilineTextAlignment(.center)
                }
                if let url {
                    Text(url.absoluteString).font(.mono(12)).foregroundStyle(Theme.muted).lineLimit(1).truncationMode(.middle)
                    ShareLink(item: url, subject: Text(name), message: Text(name)) {
                        Label("Send link", systemImage: "square.and.arrow.up").font(.geist(16, .semibold)).foregroundStyle(Theme.ink)
                            .frame(maxWidth: .infinity).frame(height: 52).background(Capsule().fill(Theme.lime))
                    }
                    .buttonStyle(.plain)
                    Button {
                        UIPasteboard.general.url = url
                        Haptics.tap()
                        copied = true
                    } label: {
                        Label(copied ? "Copied" : "Copy link", systemImage: copied ? "checkmark" : "doc.on.doc")
                            .font(.geist(16, .semibold)).foregroundStyle(.white)
                            .frame(maxWidth: .infinity).frame(height: 52).liquidGlass(in: Capsule())
                    }
                    .buttonStyle(.plain)
                    Button {
                        Haptics.remove()
                        Task {
                            do {
                                try await groups.stopSharing(listId)
                                dismiss()
                            } catch { self.error = error.localizedDescription }
                        }
                    } label: {
                        Text("Stop sharing").font(.geist(15, .semibold)).foregroundStyle(Theme.muted)
                            .frame(maxWidth: .infinity).frame(height: 44)
                    }
                    .buttonStyle(.plain)
                }
            }
            .padding(20)
        }
        .task {
            do { url = try await groups.share(listId) } catch { self.error = error.localizedDescription }
        }
    }

    private static func qr(_ text: String) -> UIImage? {
        let filter = CIFilter.qrCodeGenerator()
        filter.message = Data(text.utf8)
        filter.correctionLevel = "M"
        guard let output = filter.outputImage?.transformed(by: CGAffineTransform(scaleX: 10, y: 10)),
              let cg = CIContext().createCGImage(output, from: output.extent) else { return nil }
        return UIImage(cgImage: cg)
    }
}
