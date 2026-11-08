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

    init(_ productId: String, store: CollectionStore, groups: GroupsStore) {
        product = store.products[productId] ?? groups.extraProducts[productId]
        copies = store.allHoldings.filter { $0.identity.productId == productId && $0.quantity > 0 }.sorted { ($0.price ?? -1) > ($1.price ?? -1) }
        market = copies.first?.price
            ?? store.marketPrice(productId, printing: product?.printings?.first)?.market
            ?? groups.extraMarket[productId]
    }
}

// MARK: - Lists home

/// Every list: your own (favorites, want lists, cards to sell at a show) and the built-in
/// watchlist and wishlist.
struct ListsHomeView: View {
    @Environment(CollectionStore.self) private var store
    @Environment(GroupsStore.self) private var groups
    @State private var naming = false
    @State private var newName = ""
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
                        newName = ""
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
                        ForEach(groups.shelves) { list in
                            NavigationLink(value: ListRoute.list(list.id)) { ListTile(list: list) }
                                .buttonStyle(.plain)
                        }
                    }
                }

                VStack(alignment: .leading, spacing: 12) {
                    MoreHeading(title: "Tracking", subtitle: nil)
                    VStack(spacing: 0) {
                        trackRow(.watchlist, "Watchlist", "Prices you're watching", icon: "eye", count: store.watchlist.count)
                        Rectangle().fill(Color.white.opacity(0.06)).frame(height: 1)
                        trackRow(.wishlist, "Wishlist", "Cards you want next", icon: "heart", count: store.wishlist.count)
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
        .pageTitle("Lists")
        .task { await groups.loadExtras(groups.shelves.flatMap(\.product_ids), known: store.products) }
        .alert("New list", isPresented: $naming) {
            TextField("Favorite SIRs, For sale at the show…", text: $newName)
            Button("Cancel", role: .cancel) {}
            Button("Create") {
                let name = String(newName.trimmingCharacters(in: .whitespaces).prefix(40))
                guard !name.isEmpty else { return }
                Task {
                    do { _ = try await groups.createShelf(name) } catch { self.error = error.localizedDescription }
                }
            }
        }
    }

    private func trackRow(_ route: ListRoute, _ title: String, _ sub: String, icon: String, count: Int) -> some View {
        NavigationLink(value: route) {
            HStack(spacing: 12) {
                Image(systemName: icon).font(.system(size: 16, weight: .semibold)).foregroundStyle(Theme.lime)
                    .frame(width: 36, height: 36).background(Circle().fill(Theme.lime.opacity(0.12)))
                VStack(alignment: .leading, spacing: 2) {
                    Text(title).font(.geist(15, .semibold)).foregroundStyle(.white)
                    Text(sub).font(.geist(12)).foregroundStyle(Theme.muted)
                }
                Spacer()
                Text("\(count)").font(.geist(15, .semibold)).monospacedDigit().foregroundStyle(.white)
                Image(systemName: "chevron.right").font(.system(size: 12, weight: .semibold)).foregroundStyle(Theme.subtle)
            }
            .padding(.vertical, 8)
            .contentShape(Rectangle())
        }
        .buttonStyle(.plain)
    }
}

/// A list on the Lists page: up to three of its cards fanned out, its name, count and worth.
private struct ListTile: View {
    var list: GroupsStore.Shelf
    @Environment(CollectionStore.self) private var store
    @Environment(GroupsStore.self) private var groups

    var body: some View {
        let meta = groups.meta(list.id)
        let infos = list.product_ids.map { ListItemInfo($0, store: store, groups: groups) }
        let total = infos.reduce(0) { $0 + ($1.market ?? 0) * $1.count }
        let shown = Array(infos.filter { $0.product != nil }.sorted { ($0.market ?? 0) > ($1.market ?? 0) }.prefix(3))
        let mid = Double(max(shown.count - 1, 0)) / 2
        VStack(alignment: .leading, spacing: 10) {
            ZStack {
                if shown.isEmpty {
                    RoundedRectangle(cornerRadius: 6).fill(Color.white.opacity(0.06)).frame(width: 52, height: 72)
                }
                ForEach(Array(shown.enumerated()), id: \.offset) { i, info in
                    ProductImage(product: info.product, cornerRadius: 4)
                        .frame(width: 52, height: 72)
                        .rotationEffect(.degrees((Double(i) - mid) * 9), anchor: .bottom)
                        .offset(x: (Double(i) - mid) * 26)
                        .zIndex(-abs(Double(i) - mid))
                }
            }
            .frame(maxWidth: .infinity)
            .frame(height: 86)
            .overlay(alignment: .topTrailing) {
                if meta.isForSale {
                    Text("For sale").font(.geist(10, .semibold)).foregroundStyle(Theme.ink)
                        .padding(.horizontal, 7).padding(.vertical, 3)
                        .background(Capsule().fill(Theme.lime))
                }
            }
            VStack(alignment: .leading, spacing: 3) {
                Text(list.name).font(.geist(15, .semibold)).foregroundStyle(.white).lineLimit(2, reservesSpace: true)
                Text("\(list.product_ids.count) card\(list.product_ids.count == 1 ? "" : "s") · \(Format.money(total))")
                    .font(.geist(12)).monospacedDigit().foregroundStyle(Theme.muted).lineLimit(1)
            }
        }
        .padding(12)
        .frame(maxWidth: .infinity, alignment: .leading)
        .liquidGlass(in: RoundedRectangle(cornerRadius: 18, style: .continuous))
        .contentShape(RoundedRectangle(cornerRadius: 18, style: .continuous))
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
    @State private var name = ""
    @State private var pricing: String?
    @State private var priceText = ""
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
        let items = list.product_ids.map { ($0, ListItemInfo($0, store: store, groups: groups)) }
        let marketTotal = items.reduce(0) { $0 + ($1.1.market ?? 0) * $1.1.count }
        let askTotal = items.reduce(0) { $0 + (ListPricing.asking(meta, productId: $1.0, market: $1.1.market) ?? 0) * $1.1.count }
        let cards = Int(items.reduce(0) { $0 + $1.1.count })
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
                        ForEach(Array(items.enumerated()), id: \.element.0) { i, item in
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
        .pageTitle(list.name)
        .toolbar {
            ToolbarItem(placement: .topBarTrailing) {
                Menu {
                    Button { name = list.name; renaming = true } label: { Label("Rename", systemImage: "pencil") }
                    Button(role: .destructive) { deleting = true } label: { Label("Delete list", systemImage: "trash") }
                } label: { Image(systemName: "ellipsis") }
            }
        }
        .task { await groups.loadExtras(list.product_ids, known: store.products) }
        .sheet(isPresented: $adding) { ListAddSheet(listId: listId) }
        .sheet(isPresented: $sharing) { ListShareSheet(listId: listId, name: list.name, forSale: meta.isForSale) }
        .alert("Rename list", isPresented: $renaming) {
            TextField("Name", text: $name)
            Button("Cancel", role: .cancel) {}
            Button("Save") {
                let value = String(name.trimmingCharacters(in: .whitespaces).prefix(40))
                guard !value.isEmpty else { return }
                run { try await groups.renameShelf(listId, to: value) }
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
        .alert("Your price", isPresented: Binding(get: { pricing != nil }, set: { if !$0 { pricing = nil } })) {
            TextField("0.00", text: $priceText).keyboardType(.decimalPad)
            Button("Cancel", role: .cancel) {}
            Button("Use the list's %") {
                guard let id = pricing else { return }
                run { try await groups.updateMeta(listId) { $0.prices?[id] = nil } }
            }
            Button("Save") {
                guard let id = pricing, let value = MoneyField.value(priceText) else { return }
                run { try await groups.updateMeta(listId) { m in var p = m.prices ?? [:]; p[id] = value; m.prices = p } }
            }
        } message: {
            Text("What you're asking for one copy. Leave it to the list's percentage of market if you like.")
        }
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
                    Text("Tap a card's price to set your own.").font(.geist(12)).foregroundStyle(Theme.subtle)
                }
            }
        }
        .surface(radius: 18, padding: 16)
    }

    private func row(_ productId: String, _ info: ListItemInfo, meta: ListMeta) -> some View {
        let asking = ListPricing.asking(meta, productId: productId, market: info.market)
        let own = meta.prices?[productId] != nil
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
                    priceText = asking.map { String(format: "%.2f", $0) } ?? ""
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
                    Button { priceText = asking.map { String(format: "%.2f", $0) } ?? ""; pricing = productId } label: { Label("Set your price", systemImage: "tag") }
                }
                Button(role: .destructive) {
                    Haptics.remove()
                    run { try await groups.removeMany(listId, productIds: [productId]) }
                } label: { Label("Remove from list", systemImage: "minus.circle") }
            } label: {
                Image(systemName: "ellipsis").font(.system(size: 14, weight: .semibold)).foregroundStyle(Theme.muted)
                    .frame(width: 28, height: 44).contentShape(Rectangle())
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
