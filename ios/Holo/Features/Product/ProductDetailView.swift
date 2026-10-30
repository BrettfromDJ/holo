import Charts
import SwiftUI

/// One card or product, laid out like the website's product page: the picture, an Anton title
/// and price, changes, the action row, price history, eBay sales, what it's worth, your position,
/// purchase history and notes.
struct ProductDetailView: View {
    var productId: String
    @Environment(CollectionStore.self) private var store
    @State private var adding = false
    @State private var managing: HoldingView?
    @State private var selling: HoldingView?
    @State private var watching = false
    @State private var editing: Txn?
    @State private var deleting: Txn?
    @State private var error: String?

    private var product: Product? { store.products[productId] }
    private var owned: [HoldingView] { store.holdings(for: productId) }
    private var printing: String? { owned.first?.identity.printing ?? product?.printings?.first }
    private var price: Price? { store.marketPrice(productId, printing: printing) }

    var body: some View {
        ScrollView {
            // The website's spacing: 32 under the picture, 24 between the blocks, 32 above the
            // price history card and 24 between the cards after it.
            VStack(alignment: .leading, spacing: 0) {
                hero.padding(.top, 8)
                titleBlock.padding(.top, 32)
                actions.padding(.top, 24)
                PriceHistoryCard(productId: productId, printing: printing, owned: owned).padding(.top, 32)
                if productId.hasPrefix("tcgapi:") {
                    EbaySalesPanel(productId: productId, printing: printing, grade: owned.first(where: { $0.identity.isGraded })?.identity.gradeLabel)
                        .padding(.top, 24)
                }
                if let product, !product.isSealed, let nm = price?.market {
                    WorthPanel(productId: productId, printing: printing, nm: nm, owned: owned).padding(.top, 24)
                }
                if !owned.isEmpty {
                    position.padding(.top, 24)
                    history.padding(.top, 24)
                    notes
                }
                if let error { Text(error).font(.geist(14)).foregroundStyle(Theme.down) }
            }
            .padding(.horizontal, 16)
            .padding(.bottom, 40)
        }
        .background(Theme.background)
        .tabBarClearance()
        .navigationBarTitleDisplayMode(.inline)
        .sheet(item: $managing) { h in HoldingSheet(identity: h.identity) }
        .sheet(item: $selling) { h in SellSheet(holding: h) }
        .sheet(item: $editing) { t in EntryEditSheet(entry: t) }
        .sheet(isPresented: $adding) {
            if let product { AddPurchaseSheet(hit: SearchHit(product: product, printing: printing, market: price?.market)) }
        }
        .sheet(isPresented: $watching) {
            if let product { WatchSheet(product: product, printing: printing, market: price?.market) }
        }
        .confirmationDialog("Delete this entry?", isPresented: Binding(get: { deleting != nil }, set: { if !$0 { deleting = nil } }), titleVisibility: .visible) {
            Button("Delete", role: .destructive) {
                guard let t = deleting else { return }
                Task { await run { try await store.delete(t) } }
            }
        } message: {
            Text("Your totals update as if it never happened. The original stays in the record.")
        }
        // Cards you don't own aren't loaded with your collection: fetch them from the catalog.
        .task(id: productId) { await store.showCatalogProduct(productId) }
    }

    // MARK: Picture

    /// A single card bare at its own shape (260 wide), a slab in its frame, sealed in a square.
    @ViewBuilder private var hero: some View {
        Group {
            if let slab = owned.first(where: { $0.identity.isGraded }), owned.allSatisfy({ $0.identity.isGraded }) {
                HoldingArt(product: product, identity: slab.identity).frame(width: 260, height: 416)
            } else if product?.isSealed == false, product?.imageURL != nil {
                ProductImage(product: product, cornerRadius: 12).frame(width: 260, height: 363)
            } else {
                SealedWell(product: product, cornerRadius: 28, caption: true)
                    .aspectRatio(1, contentMode: .fit)
                    .frame(maxWidth: .infinity)
            }
        }
        .shadow(color: .black.opacity(0.5), radius: 24, y: 14)
        .frame(maxWidth: .infinity)
    }

    // MARK: Title, price and changes

    private var titleBlock: some View {
        VStack(alignment: .leading, spacing: 0) {
            HStack(spacing: 8) {
                Badge(text: product?.isSealed == true ? (product?.productType ?? "Sealed") : "Card", filled: true)
                if let rarity = product?.rarity { Badge(text: rarity) }
            }
            DisplayText(text: (product?.name ?? "Loading…").uppercased(), size: 34)
                .frame(maxWidth: .infinity, alignment: .leading)
                .padding(.top, 12)
            Text([product?.setName, product?.number.map { "#\($0)" }, printing == "Normal" ? nil : printing].compactMap { $0 }.joined(separator: " · "))
                .font(.geist(15)).foregroundStyle(Theme.muted)
                .padding(.top, 6)
            Text(Format.money(price?.market)).font(.display(52)).monospacedDigit().displayTrim(52).padding(.top, 24)
            // The headline is the Near Mint (ungraded) price; copies you own that differ are listed here.
            let differing = owned.filter { $0.identity.isGraded || $0.isConditionEstimate }
            if !differing.isEmpty {
                HStack(spacing: 8) {
                    Text(owned.contains(where: { $0.identity.isGraded }) ? "Ungraded price." : "Near Mint price.").foregroundStyle(Theme.muted)
                    ForEach(differing) { h in
                        HStack(spacing: 4) {
                            Text("Your").foregroundStyle(Theme.muted)
                            Tag(text: h.label ?? "", tint: h.identity.isGraded ? .white : (CardCondition(rawValue: h.identity.condition)?.tint ?? .white))
                            Text((h.isConditionEstimate ? "≈ " : "") + Format.money(h.price)).fontWeight(.semibold)
                        }
                    }
                }
                .font(.geist(13)).monospacedDigit()
                .padding(.top, 8)
            }
            HStack(spacing: 8) {
                change("24h", price?.change24hPct)
                change("7d", price?.change7dPct)
                change("30d", price?.change30dPct)
            }
            .padding(.top, 12)
            Text(price == nil ? "No market price available. Not counted as $0." : "Market price via TCG API" + (price?.updatedAt.flatMap(relative).map { " · updated \($0)" } ?? ""))
                .font(.geist(12)).foregroundStyle(Theme.subtle)
                .padding(.top, 12)
        }
    }

    private func change(_ label: String, _ pct: Double?) -> some View {
        HStack(spacing: 6) {
            Text(label).foregroundStyle(Theme.subtle)
            Text(Format.signedPercent(pct.map { $0 / 100 })).fontWeight(.semibold).monospacedDigit().foregroundStyle(Theme.tone(pct))
        }
        .font(.geist(13))
        .padding(.horizontal, 10)
        .padding(.vertical, 4)
        .background(Capsule().fill(Theme.surface))
    }

    private func relative(_ iso: String) -> String? {
        let f = ISO8601DateFormatter()
        f.formatOptions = [.withInternetDateTime, .withFractionalSeconds]
        guard let d = f.date(from: iso) ?? ISO8601DateFormatter().date(from: iso) else { return nil }
        let minutes = Int((Date().timeIntervalSince(d) / 60).rounded())
        if minutes < 1 { return "just now" }
        if minutes < 60 { return "\(minutes)m ago" }
        let hours = Int((Double(minutes) / 60).rounded())
        if hours < 24 { return "\(hours)h ago" }
        return "\(Int((Double(hours) / 24).rounded()))d ago"
    }

    // MARK: The action row

    private var actions: some View {
        HStack(spacing: 6) {
            Button { adding = true } label: { Label(owned.isEmpty ? "Add to collection" : "Add more", systemImage: "plus") }
                .buttonStyle(Button3D(kind: .light, fullWidth: false, height: 36))
            if !owned.isEmpty {
                if owned.count == 1 {
                    Button { selling = owned.first } label: { Image(systemName: "tag") }.buttonStyle(IconButton3D(size: 36)).accessibilityLabel("Sell")
                } else {
                    Menu {
                        ForEach(owned) { h in Button("\(h.label ?? "Near Mint") ×\(Int(h.quantity))") { selling = h } }
                    } label: { Image(systemName: "tag") }
                        .menuStyle(.button).buttonStyle(IconButton3D(size: 36)).accessibilityLabel("Sell")
                }
            }
            let watch = store.watch(for: productId)
            Button {
                if let watch { Task { await run { try await store.removeWatch(watch.id) } } } else { watching = true }
            } label: { Image(systemName: watch == nil ? "eye" : "eye.fill") }
                .buttonStyle(IconButton3D(size: 36, active: watch != nil))
                .accessibilityLabel(watch == nil ? "Watch price" : "Stop watching")
            let wish = store.wish(for: productId)
            Button {
                guard let product else { return }
                Task { await run { if let wish { try await store.removeWish(wish.id) } else { try await store.addWish(product, printing: printing, price: price?.market) } } }
            } label: { Image(systemName: wish == nil ? "heart" : "heart.fill") }
                .buttonStyle(IconButton3D(size: 36, active: wish != nil))
                .accessibilityLabel(wish == nil ? "Add to wishlist" : "Remove from wishlist")
            if let url = product?.tcgplayerUrl.flatMap(URL.init(string:)) {
                Link(destination: url) { Image(systemName: "arrow.up.right.square") }.buttonStyle(IconButton3D(size: 36)).accessibilityLabel("View on TCGplayer")
            }
        }
    }

    // MARK: Your position

    private var position: some View {
        let qty = owned.reduce(0) { $0 + $1.quantity }
        let value = owned.reduce(0) { $0 + ($1.value ?? 0) }
        let cost = owned.reduce(0) { $0 + $1.costBasis }
        let pricedCost = owned.filter { $0.value != nil }.reduce(0) { $0 + $1.costBasis }
        let gain = value - pricedCost
        let realized = owned.reduce(0) { $0 + $1.realizedGain }
        return VStack(alignment: .leading, spacing: 0) {
            PageHeader(title: "Your position", size: 22).padding(.bottom, 16)
            LazyVGrid(columns: [GridItem(.flexible(), spacing: 24, alignment: .leading), GridItem(.flexible(), alignment: .leading)], spacing: 20) {
                stat("Quantity", qty.formatted(), .white)
                stat("Holding value", Format.money(value), .white)
                stat("Cost basis", Format.money(cost), .white)
                stat("Average cost", Format.money(qty > 0 ? cost / qty : nil), .white)
                stat("Unrealized", Format.signedMoney(gain) + (pricedCost > 0 ? " (\(Format.signedPercent(gain / pricedCost)))" : ""), Theme.tone(gain))
                stat("Realized", Format.money(realized), realized == 0 ? Theme.muted : Theme.tone(realized))
            }
            Rectangle().fill(Theme.border).frame(height: 1).padding(.top, 24)
            ForEach(Array(owned.enumerated()), id: \.element.id) { i, h in
                if i > 0 { Rectangle().fill(Theme.border).frame(height: 1) }
                Button { managing = h } label: {
                    HStack(spacing: 12) {
                        VStack(alignment: .leading, spacing: 2) {
                            Text("\(Int(h.quantity)) × \(h.label ?? (product?.isSealed == true ? "Sealed" : "Near Mint"))").font(.geist(14, .medium))
                            Text("\(h.lots.count) open lot\(h.lots.count == 1 ? "" : "s") · avg \(Format.money(h.avgCost))").font(.geist(12)).foregroundStyle(Theme.muted).monospacedDigit()
                        }
                        Spacer()
                        Text(Format.signedMoney(h.gain) + " (\(Format.signedPercent(h.gainRatio)))").font(.geist(13)).monospacedDigit().foregroundStyle(Theme.tone(h.gain))
                        Image(systemName: "ellipsis").font(.system(size: 13)).foregroundStyle(Theme.muted)
                    }
                    .padding(.vertical, 14)
                    .contentShape(Rectangle())
                }
                .buttonStyle(.plain)
            }
        }
        .surface(padding: 20)
    }

    private func stat(_ label: String, _ value: String, _ tint: Color) -> some View {
        VStack(alignment: .leading, spacing: 4) {
            Text(label).font(.geist(12)).foregroundStyle(Theme.muted)
            Text(value).font(.geist(17, .semibold)).monospacedDigit().foregroundStyle(tint).lineLimit(1).minimumScaleFactor(0.7)
        }
    }

    // MARK: Purchase history and notes

    private var entries: [Txn] { owned.flatMap { store.entries(for: $0.identity) }.sorted { $0.date > $1.date } }

    private var history: some View {
        VStack(alignment: .leading, spacing: 0) {
            PageHeader(title: "Purchase history", size: 22).padding(.bottom, 16)
            ForEach(entries, id: \.id) { t in
                HStack(spacing: 12) {
                    VStack(alignment: .leading, spacing: 2) {
                        HStack(spacing: 4) {
                            Text(t.kind == .sale ? "Sale" : "Purchase").font(.geist(14, .medium))
                            Text("· \(Int(abs(t.quantity))) × \(Format.money(t.unitPrice))").font(.geist(14)).foregroundStyle(Theme.muted).monospacedDigit()
                            if store.wasEdited(t) { Tag(text: "Edited", tint: Theme.muted).padding(.leading, 4) }
                        }
                        .lineLimit(1)
                        Text([Format.isoDay.date(from: t.date)?.formatted(date: .abbreviated, time: .omitted), t.source].compactMap { $0 }.joined(separator: " · "))
                            .font(.geist(12)).foregroundStyle(Theme.muted).lineLimit(1)
                    }
                    Spacer(minLength: 0)
                    Text((t.kind == .sale ? "+" : "") + Format.money(t.kind == .sale ? t.saleProceeds : t.acquisitionCost)).font(.geist(14)).monospacedDigit()
                    Menu {
                        Button { editing = t } label: { Label("Edit", systemImage: "pencil") }
                        Button(role: .destructive) { deleting = t } label: { Label("Delete", systemImage: "trash") }
                    } label: {
                        Image(systemName: "ellipsis").font(.system(size: 13)).foregroundStyle(Theme.muted).frame(width: 28, height: 24)
                    }
                }
                .padding(.vertical, 12)
                if t.id != entries.last?.id { Rectangle().fill(Theme.border).frame(height: 1) }
            }
        }
        .surface(padding: 20)
    }

    @ViewBuilder private var notes: some View {
        let withNotes = entries.filter { !($0.notes ?? "").isEmpty }
        if !withNotes.isEmpty {
            VStack(alignment: .leading, spacing: 12) {
                PageHeader(title: "Notes", size: 22).padding(.bottom, 4)
                ForEach(withNotes, id: \.id) { t in
                    VStack(alignment: .leading, spacing: 2) {
                        Text(t.notes ?? "").font(.geist(14))
                        Text(Format.isoDay.date(from: t.date)?.formatted(date: .abbreviated, time: .omitted) ?? t.date).font(.geist(12)).foregroundStyle(Theme.subtle)
                    }
                }
            }
            .surface(padding: 20)
            .padding(.top, 24)
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

/// A small outlined (or filled) badge: "Card", "Ultra Rare".
struct Badge: View {
    var text: String
    var filled = false

    var body: some View {
        Text(text)
            .font(.geist(12, .medium))
            .foregroundStyle(Theme.muted)
            .lineLimit(1)
            .padding(.horizontal, 9)
            .frame(height: 22)
            .background(Capsule().fill(filled ? Theme.surface2 : .clear))
            .overlay(Capsule().strokeBorder(filled ? .clear : Theme.borderStrong))
    }
}

/// Market price history with ranges, and your purchases marked on the line.
private struct PriceHistoryCard: View {
    var productId: String
    var printing: String?
    var owned: [HoldingView]
    @Environment(CollectionStore.self) private var store
    @State private var range = 90

    private var all: [PricePoint] { store.history[priceKey(productId, printing)] ?? [] }
    private var points: [PricePoint] {
        guard range > 0, let last = all.last?.day else { return all }
        let since = Calendar.current.date(byAdding: .day, value: -range, to: last) ?? last
        return all.filter { $0.day >= since }
    }
    private var buys: [Txn] {
        guard let first = points.first?.date else { return [] }
        return owned.flatMap { store.entries(for: $0.identity) }.filter { $0.kind == .purchase && $0.date >= first }
    }

    var body: some View {
        VStack(alignment: .leading, spacing: 0) {
            Text("Market price history").font(.geist(15, .semibold))
            Group {
                if let first = points.first, let last = points.last {
                    let diff = last.price - first.price
                    HStack(spacing: 4) {
                        Text(Format.money(last.price)).fontWeight(.medium)
                        Text("\(Format.signedMoney(diff)) (\(Format.signedPercent(first.price > 0 ? diff / first.price : nil)))").foregroundStyle(Theme.tone(diff))
                        Text("since \(first.day.formatted(date: .abbreviated, time: .omitted))").foregroundStyle(Theme.muted)
                    }
                    .lineLimit(1).minimumScaleFactor(0.7)
                } else {
                    Text("No history").foregroundStyle(Theme.muted)
                }
            }
            .font(.geist(13)).monospacedDigit()
            .padding(.top, 4)
            ChipPicker(options: [(30, "1M"), (90, "3M"), (365, "1Y"), (0, "ALL")], selection: $range)
                .scaleEffect(0.86, anchor: .leading)
                .padding(.top, 12)
            if points.count > 1 {
                Chart {
                    ForEach(points) { p in
                        AreaMark(x: .value("Day", p.day), y: .value("Price", p.price))
                            .foregroundStyle(LinearGradient(colors: [Theme.lime.opacity(0.22), .clear], startPoint: .top, endPoint: .bottom))
                            .interpolationMethod(.monotone)
                        LineMark(x: .value("Day", p.day), y: .value("Price", p.price))
                            .foregroundStyle(Theme.lime)
                            .lineStyle(StrokeStyle(lineWidth: 2.2))
                            .interpolationMethod(.monotone)
                    }
                    ForEach(buys, id: \.id) { b in
                        PointMark(x: .value("Day", Format.isoDay.date(from: b.date) ?? Date()), y: .value("Price", b.unitPrice))
                            .foregroundStyle(.white)
                            .symbolSize(50)
                    }
                }
                .chartXAxis(.hidden)
                .insideYAxis()
                .chartYScale(domain: .automatic(includesZero: false))
                .frame(height: 220)
                .padding(.top, 12)
            } else {
                VStack(spacing: 4) {
                    Text("Not enough price history yet").font(.geist(13, .medium))
                    Text("Holo stores a daily snapshot for products you own or watch, so this chart fills in over time. Missing days are never filled with estimates.")
                        .font(.geist(13)).foregroundStyle(Theme.muted).multilineTextAlignment(.center)
                }
                .padding(.horizontal, 24)
                .frame(maxWidth: .infinity, minHeight: 220)
                .overlay(RoundedRectangle(cornerRadius: 16).strokeBorder(Theme.border, style: StrokeStyle(lineWidth: 1, dash: [4, 4])))
                .padding(.top, 16)
            }
            HStack(spacing: 6) {
                if !buys.isEmpty {
                    Circle().fill(.white).frame(width: 8, height: 8)
                    Text("Your purchases").foregroundStyle(Theme.muted).padding(.trailing, 6)
                }
                Text("\(all.count) daily observation\(all.count == 1 ? "" : "s") · gaps are shown as-is, never interpolated").foregroundStyle(Theme.subtle)
            }
            .font(.geist(11))
            .padding(.top, 8)
        }
        .surface(padding: 20)
    }
}
