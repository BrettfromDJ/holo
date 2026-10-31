import Charts
import SwiftUI

/// One card or product, laid out like the website's product page: the picture, an Anton title
/// and price, changes, the action row, price history, eBay sales, what it's worth, your position,
/// purchase history and notes.
struct ProductDetailView: View {
    var productId: String
    @Environment(CollectionStore.self) private var store
    @Environment(GroupsStore.self) private var groups
    @Environment(GradingStore.self) private var grading
    @State private var certFor: HoldingView?
    @State private var bumperFor: HoldingView?
    @State private var adding = false
    @State private var naming = false
    @State private var newShelf = ""
    @State private var managing: HoldingView?
    @State private var selling: HoldingView?
    @State private var whatIf: HoldingView?
    @State private var watching = false
    @State private var editing: Txn?
    @State private var deleting: Txn?
    @State private var showHidden = false
    @State private var error: String?

    private var product: Product? { store.products[productId] }
    private var owned: [HoldingView] { store.holdings(for: productId) }
    /// The printing on show: the one you picked (or tapped in search / a set), else the one you
    /// own, else the first priced one.
    @State private var chosenPrinting: String?
    private var printing: String? { chosenPrinting ?? owned.first?.identity.printing ?? product?.printings?.first }
    /// Printings to switch between (only when there's more than one).
    private var printings: [String] {
        var list = product?.printings ?? []
        for h in owned { if let p = h.identity.printing, !list.contains(p) { list.append(p) } }
        return list
    }
    private var price: Price? { store.marketPrice(productId, printing: printing) }
    /// The price history, oldest first.
    private var hist: [PricePoint] { (store.history[priceKey(productId, printing)] ?? []).sorted { $0.date < $1.date } }
    /// The current price, or, for products without one, the latest point in its price history.
    private var headline: Double? { price?.market ?? hist.last?.price }

    /// The change over `days` from the price history, for products without a current price.
    private func histChange(_ days: Int) -> Double? {
        guard let last = hist.last, let lastDay = Format.isoDay.date(from: last.date),
              let cutoff = Calendar.current.date(byAdding: .day, value: -days, to: lastDay) else { return nil }
        let cut = Format.day(cutoff)
        guard let base = hist.last(where: { $0.date <= cut }), base.price > 0 else { return nil }
        return (last.price - base.price) / base.price * 100
    }

    var body: some View {
        ScrollView {
            // The website's spacing: 32 under the picture, 24 between the blocks, 32 above the
            // price history card and 24 between the cards after it.
            VStack(alignment: .leading, spacing: 0) {
                hero.padding(.top, 8)
                titleBlock.padding(.top, 12)
                actions.padding(.top, 24)
                PriceHistoryCard(productId: productId, printing: printing, owned: owned).padding(.top, 32)
                if productId.hasPrefix("tcgapi:") {
                    EbaySalesPanel(productId: productId, printing: printing, grade: owned.first(where: { $0.identity.isGraded })?.identity.gradeLabel)
                        .padding(.top, 24)
                }
                // Real graded values (PriceCharting), for singles.
                if productId.hasPrefix("tcgapi:"), product?.isSealed == false {
                    GradedPricesPanel(productId: productId, printing: printing, nm: price?.market, owned: owned.compactMap { h in
                        guard let c = h.identity.gradeCompany, let g = h.identity.grade else { return nil }
                        return (company: c, grade: g)
                    })
                    .padding(.top, 24)
                }
                if let product, !product.isSealed, let nm = price?.market {
                    WorthPanel(productId: productId, printing: printing, nm: nm, owned: owned).padding(.top, 24)
                }
                if !owned.isEmpty {
                    position.padding(.top, 24)
                    slabTools
                    history.padding(.top, 24)
                    notes
                }
                if let error { Text(error).font(.geist(14)).foregroundStyle(Theme.down) }
            }
            .padding(.horizontal, 16)
            .padding(.bottom, 40)
        }
        .background(Theme.background)
        // A card page shows its picture full size, even when opened from a list of thumbnails.
        .environment(\.imageMaxPixel, nil)
        .replaysAnimations()
        .tabBarClearance()
        .navigationBarTitleDisplayMode(.inline)
        // The type and rarity pills sit at the top center, where a page title would go.
        .toolbar {
            ToolbarItem(placement: .principal) {
                HStack(spacing: 8) {
                    Badge(text: product?.isSealed == true ? (product?.productType ?? "Sealed") : "Card", filled: true)
                    if let rarity = product?.rarity { RarityBadge(rarity: rarity) }
                }
                .fixedSize()
            }
            // Share the card's page on the website.
            ToolbarItem(placement: .topBarTrailing) {
                if let url = webURL {
                    ShareLink(item: url, subject: Text(product?.name ?? "Card"), message: Text(shareText)) {
                        Image(systemName: "square.and.arrow.up")
                    }
                    .accessibilityLabel("Share")
                }
            }
        }
        .sheet(item: $managing) { h in HoldingSheet(identity: h.identity) }
        .sheet(item: $selling) { h in SellSheet(holding: h) }
        .sheet(item: $whatIf) { h in SellCalculatorSheet(holding: h) }
        .sheet(item: $certFor) { h in CertSheet(holding: h) }
        .sheet(item: $bumperFor) { h in BumperSheet(holding: h) }
        // Screenshots: -HoloWhatIf opens the calculator for the first copy you own.
        .task {
            if Demo.isOn, ProcessInfo.processInfo.arguments.contains("-HoloWhatIf"), whatIf == nil {
                try? await Task.sleep(nanoseconds: 800_000_000)
                whatIf = owned.first
            }
        }
        .sheet(item: $editing) { t in EntryEditSheet(entry: t) }
        .sheet(isPresented: $adding) {
            if let product { AddPurchaseSheet(hit: SearchHit(product: product, printing: printing, market: headline)) }
        }
        .sheet(isPresented: $watching) {
            if let product { WatchSheet(product: product, printing: printing, market: headline) }
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
        .task(id: productId) {
            if chosenPrinting == nil { chosenPrinting = store.takeOpenPrinting(productId) }
            await store.showCatalogProduct(productId)
            // Then the full price history, if Holo doesn't have it yet (like the website).
            await store.loadFullHistory(productId, printing: printing)
        }
    }

    // MARK: Picture

    /// A single card bare at its own shape (260 wide), a slab in its frame, sealed in a square.
    private var webURL: URL? {
        let id = productId.addingPercentEncoding(withAllowedCharacters: .urlPathAllowed.subtracting(CharacterSet(charactersIn: ":"))) ?? productId
        return URL(string: "product/\(id)", relativeTo: AppConfig.apiBaseURL)?.absoluteURL
    }

    private var shareText: String {
        [product?.name, headline.map { Format.money($0) }].compactMap { $0 }.joined(separator: " · ")
    }

    /// Above the piece: the set and number, and whether (and how many) you own.
    private var stageHeader: some View {
        let owns = owned.reduce(0) { $0 + $1.quantity }
        let line = [product?.setName, product?.number.map { "#\($0)" }].compactMap { $0 }.joined(separator: " · ")
        return VStack(spacing: 10) {
            if !line.isEmpty { MonoLabel(text: line) }
            if owns > 0 {
                SkewTag(text: "In your collection" + (owns > 1 ? " ×\(Int(owns))" : ""), icon: "checkmark")
            }
        }
        .frame(maxWidth: .infinity)
    }

    /// The piece on a lit stage: the grid and glows behind it (lime when it's up over the month,
    /// pink when it's down), leaning with the phone like a real card in the light.
    @ViewBuilder private var hero: some View {
        let mood = (price?.change30dPct ?? 0) < 0 ? Theme.planPink : Theme.lime
        VStack(spacing: 22) {
            stageHeader
            piece
        }
        .padding(.top, 20)
        .padding(.bottom, 36)
        .frame(maxWidth: .infinity)
        .background { ProductStage(mood: mood).padding(.horizontal, -16) }
        .modifier(Entrance())
    }

    @ViewBuilder private var piece: some View {
        Group {
            if let slab = owned.first(where: { $0.identity.isGraded }), owned.allSatisfy({ $0.identity.isGraded }) {
                HoloCard(foil: false, textured: false, cornerRadius: 18) {
                    HoldingArt(product: product, identity: slab.identity)
                }
                .frame(width: 250, height: 400)
            } else if product?.isSealed == false, product?.imageURL != nil {
                HoloCard(foil: product?.isFoil == true, textured: false, cornerRadius: 12) {
                    ProductImage(product: product, cornerRadius: 0).frame(width: 260, height: 363)
                }
            } else {
                HoloCard(foil: false, textured: false, cornerRadius: 28) {
                    SealedWell(product: product, cornerRadius: 28, caption: true).frame(width: 280, height: 280)
                }
            }
        }
        .frame(maxWidth: .infinity)
    }

    // MARK: Title, price and changes

    private var titleBlock: some View {
        VStack(alignment: .leading, spacing: 0) {
            DisplayText(text: (product?.name ?? "Loading…").uppercased(), size: 34)
                .frame(maxWidth: .infinity, alignment: .leading)
            Text([product?.setName, product?.number.map { "#\($0)" }, printings.count > 1 || printing == "Normal" ? nil : printing].compactMap { $0 }.joined(separator: " · "))
                .font(.geist(15)).foregroundStyle(Theme.muted)
                .padding(.top, 6)
            // Different printings sell for different prices: switch between them.
            if printings.count > 1 {
                ScrollView(.horizontal, showsIndicators: false) {
                    ChipPicker(options: printings.map { ($0, $0) }, selection: Binding(get: { printing ?? "" }, set: { p in
                        withAnimation(.snappy) { chosenPrinting = p }
                        UISelectionFeedbackGenerator().selectionChanged()
                        Task { await store.loadFullHistory(productId, printing: p) }
                    }))
                }
                .scrollClipDisabled()
                .padding(.top, 14)
            }
            Group {
                if let market = headline {
                    CountingText(value: market, format: { Format.money($0) })
                } else {
                    Text(Format.money(nil))
                }
            }
            .font(.display(52)).monospacedDigit().displayTrim(52).padding(.top, 24)
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
                change("24h", price?.change24hPct ?? histChange(1)).modifier(PopIn(delay: 0.35))
                change("7d", price?.change7dPct ?? histChange(7)).modifier(PopIn(delay: 0.45))
                change("30d", price?.change30dPct ?? histChange(30)).modifier(PopIn(delay: 0.55))
            }
            .padding(.top, 12)
            Text(price != nil
                 ? (price?.source == "pricecharting" ? "Ungraded price via PriceCharting (no TCGplayer price)" : "Market price via TCG API")
                    + (price?.updatedAt.flatMap(relative).map { " · updated \($0)" } ?? "")
                 : (hist.last.map { "Last market price \($0.day.formatted(date: .abbreviated, time: .omitted)) · no current price yet" } ?? "No market price available. Not counted as $0."))
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
                // What if I sell? (like the website), then record a sale.
                if owned.count == 1 {
                    Button { whatIf = owned.first } label: { Image(systemName: "plus.forwardslash.minus") }.buttonStyle(IconButton3D(size: 36)).accessibilityLabel("What if I sell?")
                } else {
                    Menu {
                        ForEach(owned) { h in Button("\(h.label ?? "Near Mint") ×\(Int(h.quantity))") { whatIf = h } }
                    } label: { Image(systemName: "plus.forwardslash.minus") }
                        .menuStyle(.button).buttonStyle(IconButton3D(size: 36)).accessibilityLabel("What if I sell?")
                }
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
            groupsMenu
        }
        .alert("New shelf", isPresented: $naming) {
            TextField("Grails, For sale…", text: $newShelf)
            Button("Cancel", role: .cancel) { newShelf = "" }
            Button("Create") {
                let name = String(newShelf.trimmingCharacters(in: .whitespaces).prefix(40))
                newShelf = ""
                guard !name.isEmpty else { return }
                Task { await run { _ = try await groups.createShelf(name, productIds: [productId]) } }
            }
        } message: {
            Text("Shelves group products however you like, and show as filters on Collection.")
        }
    }

    /// Shelves this product is on, and which portfolio your copies are in (shared with the website).
    private var groupsMenu: some View {
        Menu {
            Section("Shelves") {
                ForEach(groups.shelves) { shelf in
                    Button {
                        Task { await run { try await groups.toggle(shelf.id, productId: productId) } }
                    } label: {
                        if shelf.product_ids.contains(productId) { Label(shelf.name, systemImage: "checkmark") } else { Text(shelf.name) }
                    }
                }
                Button { naming = true } label: { Label("New shelf…", systemImage: "plus") }
            }
            if !owned.isEmpty, !groups.portfolios.isEmpty {
                let current = groups.portfolioOf(owned[0].identity.key)
                Section("Portfolio") {
                    ForEach([GroupsStore.main] + groups.portfolios.map(\.id), id: \.self) { id in
                        Button {
                            Task { await run { for h in owned { try await groups.move(h.identity.key, to: id, store: store) } } }
                        } label: {
                            if current == id { Label(groups.name(of: id), systemImage: "checkmark") } else { Text(groups.name(of: id)) }
                        }
                    }
                }
            }
        } label: {
            Image(systemName: "ellipsis")
        }
        .menuStyle(.button)
        .buttonStyle(IconButton3D(size: 36))
        .accessibilityLabel("Shelves and portfolio")
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

    // MARK: Slabs: cert number and bumper

    /// For each graded copy you own: its cert number (with a lookup link) and its bumper.
    @ViewBuilder private var slabTools: some View {
        let slabs = owned.filter(\.identity.isGraded)
        if !slabs.isEmpty {
            VStack(alignment: .leading, spacing: 14) {
                PageHeader(title: slabs.count == 1 ? "Your slab" : "Your slabs", size: 22)
                ForEach(slabs) { h in
                    let cert = grading.certs[h.identity.key]
                    let bumper = Bumper.byId(grading.bumpers[h.identity.key])
                    VStack(alignment: .leading, spacing: 10) {
                        if slabs.count > 1 { MonoLabel(text: h.identity.gradeLabel ?? "Slab") }
                        HStack(spacing: 10) {
                            VStack(alignment: .leading, spacing: 3) {
                                Text("Cert number").font(.geist(12)).foregroundStyle(Theme.muted)
                                Text(cert ?? "Not added").font(.mono(15, .medium)).foregroundStyle(cert == nil ? Theme.subtle : .white)
                            }
                            Spacer()
                            if let cert, let company = h.identity.gradeCompany, let url = URL(string: Grading.certLookupURL(company: company, cert: cert)) {
                                Link(destination: url) { Label("Look up", systemImage: "arrow.up.right.square") }
                                    .buttonStyle(Button3D(kind: .dark, fullWidth: false, height: 36))
                            }
                            Button(cert == nil ? "Add" : "Edit") { certFor = h }
                                .buttonStyle(Button3D(kind: .dark, fullWidth: false, height: 36))
                        }
                        Rectangle().fill(Theme.border).frame(height: 1)
                        Button { bumperFor = h } label: {
                            HStack(spacing: 10) {
                                Circle().fill(bumper?.fill ?? LinearGradient(colors: [.clear], startPoint: .top, endPoint: .bottom))
                                    .overlay(Circle().strokeBorder(.white.opacity(0.2)))
                                    .overlay { if bumper == nil { Image(systemName: "plus").font(.system(size: 10, weight: .bold)).foregroundStyle(Theme.muted) } }
                                    .frame(width: 22, height: 22)
                                VStack(alignment: .leading, spacing: 2) {
                                    Text("Bumper").font(.geist(12)).foregroundStyle(Theme.muted)
                                    Text(bumper?.name ?? "Add a bumper").font(.geist(15, .medium))
                                }
                                Spacer()
                                Image(systemName: "chevron.right").font(.system(size: 12, weight: .semibold)).foregroundStyle(Theme.subtle)
                            }
                            .contentShape(Rectangle())
                        }
                        .buttonStyle(.plain)
                    }
                    .surface(padding: 16)
                }
            }
            .padding(.top, 24)
        }
    }

    // MARK: Purchase history and notes

    private var entries: [Txn] { owned.flatMap { store.entries(for: $0.identity) }.sorted { $0.date > $1.date } }

    private var history: some View {
        let entries = self.entries
        return VStack(alignment: .leading, spacing: 0) {
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
            if entries.isEmpty {
                Text("No active entries.").font(.geist(14)).foregroundStyle(Theme.muted).padding(.vertical, 4)
            }
            let hidden = store.hiddenEntries(productId: productId)
            if !hidden.isEmpty {
                Rectangle().fill(Theme.border).frame(height: 1).padding(.top, 8)
                Button("\(showHidden ? "Hide" : "Show") deleted & edit records (\(hidden.count))") { showHidden.toggle() }
                    .font(.geist(12, .medium)).foregroundStyle(Theme.subtle)
                    .padding(.top, 12)
                if showHidden {
                    VStack(alignment: .leading, spacing: 6) {
                        ForEach(hidden, id: \.id) { t in
                            Text(hiddenLine(t)).font(.geist(12)).monospacedDigit().foregroundStyle(Theme.subtle)
                        }
                    }
                    .padding(.top, 8)
                }
            }
        }
        .surface(padding: 20)
    }

    private func hiddenLine(_ t: Txn) -> String {
        let when = ISO8601DateFormatter().date(from: t.createdAt)?.formatted(date: .abbreviated, time: .omitted) ?? String(t.createdAt.prefix(10))
        if t.kind == .correction {
            let note = t.notes.flatMap { ["Deleted", "Edited", "Voided", "Corrected"].contains($0) || $0.isEmpty ? nil : " · \($0)" } ?? ""
            return "\(t.quantity == 0 ? "Deleted" : "Edited") an entry · \(when)\(note)"
        }
        let kind = t.kind == .adjustment ? "Adjustment" : t.kind.rawValue.capitalized
        return "\(kind) · \(Int(abs(t.quantity))) × \(Format.money(t.unitPrice)) (deleted) · \(when)"
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
                let domain = ChartTicks.domain(points.map(\.price) + buys.map(\.unitPrice))
                Chart {
                    ForEach(points) { p in
                        AreaMark(x: .value("Day", p.day), yStart: .value("Floor", domain.lowerBound), yEnd: .value("Price", p.price))
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
                .chartYScale(domain: domain)
                .drawIn(replay: range)
                .frame(height: 220)
                .padding(.top, 12)
            } else {
                let load = store.historyLoad[priceKey(productId, printing)]
                VStack(spacing: 8) {
                    if load == .loading {
                        HStack(spacing: 8) {
                            ProgressView().controlSize(.small).tint(Theme.muted)
                            Text("Loading price history…").font(.geist(13, .medium))
                        }
                    } else {
                        if case let .note(note) = load {
                            Text(note).font(.geist(13, .medium)).multilineTextAlignment(.center)
                        } else {
                            Text("Not enough price history yet").font(.geist(13, .medium))
                        }
                        Text("Holo stores a daily snapshot for products you own or watch, so this chart fills in over time. Missing days are never filled with estimates.")
                            .font(.geist(13)).foregroundStyle(Theme.muted).multilineTextAlignment(.center)
                        if case let .failed(message) = load {
                            Text(message).font(.geist(12)).foregroundStyle(Theme.warn).multilineTextAlignment(.center)
                            Button("Try again") { Task { await store.loadFullHistory(productId, printing: printing, retry: true) } }
                                .buttonStyle(Button3D(kind: .dark, fullWidth: false, height: 36))
                        }
                    }
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

/// The lit stage behind a product: the website's faint grid with a glow in the product's mood
/// and a pink one opposite, fading out at the top and bottom.
private struct ProductStage: View {
    var mood: Color
    @Environment(\.accessibilityReduceMotion) private var reduceMotion
    @State private var breathe = false

    var body: some View {
        ZStack {
            GridPattern(step: 36, opacity: 0.055)
            // A bright core right behind the piece, then a wide wash, so it reads as light.
            RadialGradient(colors: [mood.opacity(breathe ? 0.75 : 0.6), mood.opacity(0.25), .clear], center: UnitPoint(x: 0.5, y: 0.5), startRadius: 0, endRadius: 190)
                .blur(radius: 20)
            RadialGradient(colors: [mood.opacity(breathe ? 0.32 : 0.24), .clear], center: UnitPoint(x: 0.5, y: 0.5), startRadius: 0, endRadius: 320)
            RadialGradient(colors: [Theme.planPink.opacity(0.28), .clear], center: UnitPoint(x: 0.9, y: 0.2), startRadius: 0, endRadius: 220)
            RadialGradient(colors: [Theme.planBlue.opacity(0.26), .clear], center: UnitPoint(x: 0.1, y: 0.85), startRadius: 0, endRadius: 220)
        }
        .mask(LinearGradient(stops: [.init(color: .clear, location: 0), .init(color: .black, location: 0.2),
                                     .init(color: .black, location: 0.8), .init(color: .clear, location: 1)],
                             startPoint: .top, endPoint: .bottom))
        .allowsHitTesting(false)
        .onAppear {
            guard !reduceMotion else { return }
            withAnimation(.easeInOut(duration: 3).repeatForever(autoreverses: true)) { breathe = true }
        }
    }
}

/// The piece rises into place with a little spring when the page opens.
private struct Entrance: ViewModifier {
    @Environment(\.accessibilityReduceMotion) private var reduceMotion
    @State private var shown = false

    func body(content: Content) -> some View {
        content
            .opacity(shown || reduceMotion ? 1 : 0)
            .scaleEffect(shown || reduceMotion ? 1 : 0.9)
            .offset(y: shown || reduceMotion ? 0 : 24)
            .onAppear { withAnimation(.spring(response: 0.6, dampingFraction: 0.75)) { shown = true } }
            .onReplay {
                guard !reduceMotion else { return }
                shown = false
                withAnimation(.spring(response: 0.6, dampingFraction: 0.75).delay(0.05)) { shown = true }
            }
    }
}

/// A small piece that pops in after a delay.
private struct PopIn: ViewModifier {
    var delay: Double
    @Environment(\.accessibilityReduceMotion) private var reduceMotion
    @State private var shown = false

    func body(content: Content) -> some View {
        content
            .opacity(shown || reduceMotion ? 1 : 0)
            .scaleEffect(shown || reduceMotion ? 1 : 0.7)
            .onAppear { withAnimation(.spring(response: 0.4, dampingFraction: 0.6).delay(delay)) { shown = true } }
            .onReplay {
                guard !reduceMotion else { return }
                shown = false
                withAnimation(.spring(response: 0.4, dampingFraction: 0.6).delay(delay)) { shown = true }
            }
    }
}
