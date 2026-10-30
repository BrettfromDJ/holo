import SwiftUI

/// Every brand, set, sealed product and single in the catalog, upcoming releases, and search with filters.
struct ExploreView: View {
    @Environment(CollectionStore.self) private var store
    @State private var index: ExploreIndex?
    @State private var failed: String?
    @State private var query = ""
    @State private var results: [SearchHit] = []
    @State private var searching = false
    @State private var filters = SearchFilters()
    @State private var path = NavigationPath()

    private var today: String { Format.day() }
    private var upcoming: [ExploreSet] {
        (index?.sets ?? []).filter { ($0.releaseDate ?? "") >= today }.sorted { ($0.releaseDate ?? "") < ($1.releaseDate ?? "") }
    }

    private var recent: [ExploreSet] {
        (index?.sets ?? []).filter { ($0.releaseDate ?? "") < today }.sorted { ($0.releaseDate ?? "") > ($1.releaseDate ?? "") }
    }

    var body: some View {
        NavigationStack(path: $path) {
            Group {
                if query.trimmingCharacters(in: .whitespaces).count >= 2 {
                    List { searchResults }
                        .scrollContentBackground(.hidden)
                } else {
                    ScrollView { landing }
                }
            }
            .background(Theme.background)
            .replaysAnimations()
            .tabBarClearance()
            .navigationBarTitleDisplayMode(.inline)
            .pageTitle("Explore")
            .searchable(text: $query, placement: .navigationBarDrawer(displayMode: .always), prompt: "Search cards and sealed, any brand")
            .task { await loadIndex() }
            .task(id: query) { await search() }
            .navigationDestination(for: ExploreGame.self) { g in BrandView(game: g, sets: (index?.sets ?? []).filter { $0.gameSlug == g.slug }) }
            .navigationDestination(for: ExploreSet.self) { SetView(set: $0) }
            .navigationDestination(for: String.self) { ProductDetailView(productId: $0) }
            .navigationDestination(for: ExploreRoute.self) { _ in ReleaseCalendarView(sets: index?.sets ?? []) }
        }
    }

    // MARK: The landing page

    @ViewBuilder private var landing: some View {
        if let failed {
            Text(failed).font(.geist(14)).foregroundStyle(Theme.muted).padding(32)
        } else if let index {
            VStack(alignment: .leading, spacing: 40) {
                CatalogHero(index: index, next: upcoming.first)
                if upcoming.count > 1 {
                    VStack(alignment: .leading, spacing: 14) {
                        HStack(alignment: .lastTextBaseline) {
                            PageHeader(title: "Coming soon", subtitle: "New sets on the way", size: 22)
                            Spacer()
                            NavigationLink(value: ExploreRoute.calendar) {
                                HStack(spacing: 4) { Text("Calendar"); Image(systemName: "arrow.right").font(.system(size: 12, weight: .semibold)) }
                                    .font(.geist(13, .medium)).foregroundStyle(Theme.muted)
                            }
                        }
                        .padding(.horizontal, 16)
                        SetCarousel(sets: Array(upcoming.dropFirst().prefix(12)), upcoming: true)
                    }
                    .reveal()
                }
                if !recent.isEmpty {
                    VStack(alignment: .leading, spacing: 14) {
                        PageHeader(title: "Just released", subtitle: "The newest sets in the catalog", size: 22).padding(.horizontal, 16)
                        SetCarousel(sets: Array(recent.prefix(12)), upcoming: false)
                    }
                    .reveal()
                }
                VStack(alignment: .leading, spacing: 14) {
                    PageHeader(title: "Brands", subtitle: "Every game in the catalog", size: 22)
                    LazyVGrid(columns: [GridItem(.flexible(), spacing: 12), GridItem(.flexible(), spacing: 12)], spacing: 12) {
                        ForEach(Array(index.games.enumerated()), id: \.element.id) { i, g in
                            NavigationLink(value: g) { BrandCard(game: g, tint: BrandCard.tints[i % BrandCard.tints.count]) }
                                .buttonStyle(.plain)
                        }
                    }
                }
                .padding(.horizontal, 16)
                .reveal()
            }
            .padding(.bottom, 40)
        } else {
            ProgressView().padding(.top, 160).frame(maxWidth: .infinity)
        }
    }

    @ViewBuilder private var searchResults: some View {
        let owned = Set(store.holdings.map(\.identity.productId))
        let watched = Set(store.watchlist.map(\.product_id))
        let shown = filters.apply(results, owned: owned, watched: watched)
        Section {
            FilterBar(items: results, filters: $filters)
                .listRowInsets(EdgeInsets(top: 4, leading: 0, bottom: 4, trailing: 0))
                .listRowBackground(Color.clear)
            if searching && results.isEmpty {
                ProgressView().frame(maxWidth: .infinity)
            } else if results.isEmpty {
                Text("Nothing found. Try the set name or card number too.").foregroundStyle(Theme.muted)
            } else if shown.isEmpty {
                Button("No results match these filters. Clear filters") { filters = SearchFilters(sort: filters.sort) }
                    .foregroundStyle(Theme.muted)
            }
            ForEach(shown) { hit in
                NavigationLink(value: hit.product.id) { SearchRow(hit: hit) }
                    .simultaneousGesture(TapGesture().onEnded { store.seed(hit) })
            }
        } header: {
            if !results.isEmpty {
                Text(shown.count == results.count ? "\(results.count) results" : "\(shown.count) of \(results.count) results")
            }
        }
    }

    private func loadIndex() async {
        guard index == nil else { return }
        if Demo.isOn {
            // Screenshots: a made-up catalog, and `-HoloExplore calendar|brand:<slug>|set:<slug>`
            // opens a page in it.
            let demo = DemoData.exploreIndex
            index = demo
            let open = (Demo.value("-HoloExplore") ?? "").split(separator: ":", maxSplits: 1).map(String.init)
            if open.first == "calendar" {
                path.append(ExploreRoute.calendar)
            } else if open.count == 2, open[0] == "brand", let g = demo.games.first(where: { $0.slug == open[1] }) {
                path.append(g)
            } else if open.count == 2, open[0] == "set", let s = demo.sets.first(where: { $0.slug == open[1] }) {
                path.append(s)
            }
            return
        }
        do {
            index = try await Backend.shared.api.exploreIndex()
        } catch {
            failed = error.localizedDescription
        }
    }

    private func search() async {
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

/// A row of filter menus over search results; options come from the results themselves.
private struct FilterBar: View {
    var items: [SearchHit]
    @Binding var filters: SearchFilters
    @State private var pricing = false

    var body: some View {
        ScrollView(.horizontal, showsIndicators: false) {
            HStack(spacing: 8) {
                menu(filters.kind == .all ? "Type" : (filters.kind == .single ? "Cards" : "Sealed"), on: filters.kind != .all) {
                    ForEach(SearchFilters.Kind.allCases, id: \.self) { k in Button(k.rawValue) { filters.kind = k } }
                }
                let languages = SearchFilters.facet(items) { SearchFilters.language(of: $0.gameName) }
                menu(filters.language ?? "Language", on: filters.language != nil) {
                    Button("Any language") { filters.language = nil }
                    ForEach(languages, id: \.value) { l in Button("\(l.value) (\(l.count))") { filters.language = l.value } }
                }
                let brands = SearchFilters.facet(items) { SearchFilters.brand(of: $0.gameName) }
                if brands.count > 1 || filters.brand != nil {
                    menu(filters.brand ?? "Brand", on: filters.brand != nil) {
                        Button("Every brand") { filters.brand = nil }
                        ForEach(brands, id: \.value) { b in Button("\(b.value) (\(b.count))") { filters.brand = b.value } }
                    }
                }
                menu(filters.owned == .owned ? "Owned" : (filters.owned == .notOwned ? "Not owned" : "Owned"), on: filters.owned != .any) {
                    ForEach(SearchFilters.Owned.allCases, id: \.self) { o in Button(o.rawValue) { filters.owned = o } }
                }
                chip("Watchlist", icon: "eye", on: filters.watchlist) { filters.watchlist.toggle() }
                chip(priceLabel, icon: nil, on: filters.min != nil || filters.max != nil) { pricing = true }
                menu(filters.sort.rawValue, on: false, icon: "arrow.up.arrow.down") {
                    ForEach(SearchFilters.Sort.allCases, id: \.self) { s in Button(s.rawValue) { filters.sort = s } }
                }
                if filters.activeCount > 0 {
                    chip("Clear", icon: "xmark", on: false) { filters = SearchFilters(sort: filters.sort) }
                }
            }
            .padding(.horizontal, 16)
        }
        .sheet(isPresented: $pricing) { PriceRangeSheet(filters: $filters) }
    }

    private var priceLabel: String {
        guard filters.min != nil || filters.max != nil else { return "Price" }
        return "\(filters.min.map { Format.moneyWhole($0) } ?? "$0")–\(filters.max.map { Format.moneyWhole($0) } ?? "any")"
    }

    private func menu<Content: View>(_ title: String, on: Bool, icon: String? = nil, @ViewBuilder content: () -> Content) -> some View {
        Menu { content() } label: { chipLabel(title, icon: icon ?? "chevron.down", on: on, trailingIcon: icon == nil) }
    }

    private func chip(_ title: String, icon: String?, on: Bool, action: @escaping () -> Void) -> some View {
        Button(action: action) { chipLabel(title, icon: icon, on: on, trailingIcon: false) }
    }

    private func chipLabel(_ title: String, icon: String?, on: Bool, trailingIcon: Bool) -> some View {
        HStack(spacing: 5) {
            if let icon, !trailingIcon { Image(systemName: icon).font(.caption2.weight(.bold)) }
            Text(title).monospacedDigit()
            if let icon, trailingIcon { Image(systemName: icon).font(.caption2.weight(.bold)) }
        }
        .font(.footnote.weight(.medium))
        .padding(.horizontal, 12)
        .frame(height: 34)
        .background(on ? Color.white : Theme.surface2, in: Capsule())
        .foregroundStyle(on ? Theme.ink : .primary)
    }
}

private struct PriceRangeSheet: View {
    @Binding var filters: SearchFilters
    @Environment(\.dismiss) private var dismiss
    @State private var min = ""
    @State private var max = ""

    var body: some View {
        NavigationStack {
            Form {
                MoneyField(title: "Minimum", text: $min, hint: "Any")
                MoneyField(title: "Maximum", text: $max, hint: "Any")
                Section { Text("Items without a price are left out when a range is set.").font(.footnote).foregroundStyle(Theme.muted) }
            }
            .navigationTitle("Price range")
            .navigationBarTitleDisplayMode(.inline)
            .toolbar {
                ToolbarItem(placement: .cancellationAction) { Button("Clear") { filters.min = nil; filters.max = nil; dismiss() } }
                ToolbarItem(placement: .confirmationAction) {
                    Button("Apply") {
                        filters.min = MoneyField.value(min)
                        filters.max = MoneyField.value(max)
                        dismiss()
                    }
                }
            }
            .onAppear {
                min = filters.min.map { String(format: "%.0f", $0) } ?? ""
                max = filters.max.map { String(format: "%.0f", $0) } ?? ""
            }
        }
        .presentationDetents([.medium])
    }
}

/// A set with its release date and a reminder bell.
struct ReleaseRow: View {
    var set: ExploreSet
    @Environment(CollectionStore.self) private var store
    @State private var busy = false

    var body: some View {
        HStack(spacing: 12) {
            CachedImage(url: (set.iconUrl ?? set.imageUrl).flatMap(URL.init(string:))) { img in img.resizable().scaledToFit() } placeholder: {
                RoundedRectangle(cornerRadius: 6).fill(Theme.surface2)
            }
            .frame(width: 40, height: 40)
            VStack(alignment: .leading, spacing: 2) {
                Text(set.name).font(.subheadline.weight(.medium)).lineLimit(1)
                Text([set.gameName, set.release?.formatted(date: .abbreviated, time: .omitted)].compactMap { $0 }.joined(separator: " · "))
                    .font(.caption).foregroundStyle(Theme.muted)
            }
            Spacer()
            if (set.releaseDate ?? "") >= Format.day() {
                let on = store.reminders.contains(set.slug)
                Button {
                    busy = true
                    Task {
                        try? await store.setReminder(set, on: !on)
                        busy = false
                    }
                } label: {
                    Image(systemName: on ? "bell.fill" : "bell").foregroundStyle(on ? Theme.lime : Theme.muted)
                }
                .buttonStyle(.borderless)
                .disabled(busy)
                .accessibilityLabel(on ? "Turn off reminder" : "Remind me on release day")
            }
        }
    }
}

// MARK: - A brand's page

/// One brand: its logo and counts over a lit grid, its next release, then every set as a tile,
/// newest first, by year (like the website's brand page).
private struct BrandView: View {
    var game: ExploreGame
    var sets: [ExploreSet]
    @State private var loadedOnly = false

    private var today: String { Format.day() }
    private var years: [(year: String, sets: [ExploreSet])] {
        let shown = loadedOnly ? sets.filter(\.loaded) : sets
        let grouped = Dictionary(grouping: shown) { $0.releaseDate.map { String($0.prefix(4)) } ?? "Undated" }
        return grouped.keys
            .sorted { a, b in a == "Undated" ? false : (b == "Undated" ? true : a > b) }
            .map { ($0, grouped[$0]!.sorted { ($0.releaseDate ?? "") > ($1.releaseDate ?? "") }) }
    }

    private var next: ExploreSet? {
        sets.filter { ($0.releaseDate ?? "") >= today }.min { ($0.releaseDate ?? "") < ($1.releaseDate ?? "") }
    }

    var body: some View {
        ScrollView {
            VStack(alignment: .leading, spacing: 36) {
                hero
                VStack(alignment: .leading, spacing: 30) {
                    ChipPicker(options: [(false, "All sets"), (true, "Loaded")], selection: $loadedOnly)
                    ForEach(years, id: \.year) { group in
                        VStack(alignment: .leading, spacing: 14) {
                            SectionCount(title: group.year, count: group.sets.count, noun: "set")
                            LazyVGrid(columns: twoColumns, alignment: .leading, spacing: 20) {
                                ForEach(group.sets) { s in
                                    NavigationLink(value: s) {
                                        SetTile(set: s, upcoming: (s.releaseDate ?? "") >= today, width: nil, showGame: false)
                                    }
                                    .buttonStyle(.plain)
                                }
                            }
                        }
                        .reveal()
                    }
                }
                .padding(.horizontal, 16)
            }
            .padding(.bottom, 40)
        }
        .background(Theme.background)
        .replaysAnimations()
        .tabBarClearance()
        .navigationBarTitleDisplayMode(.inline)
        .pageTitle(game.name)
    }

    private var hero: some View {
        VStack(alignment: .leading, spacing: 22) {
            HStack(spacing: 16) {
                CachedImage(url: game.logoUrl.flatMap(URL.init(string:))) { img in
                    img.resizable().scaledToFit().shadow(color: .black.opacity(0.5), radius: 9, y: 8)
                } placeholder: {
                    Text(game.name.prefix(1).uppercased()).font(.display(40)).foregroundStyle(Theme.lime)
                }
                .frame(width: 110, height: 64)
                VStack(alignment: .leading, spacing: 6) {
                    MonoLabel(text: "Brand")
                    DisplayText(text: game.name.uppercased(), size: 30).frame(maxWidth: .infinity, alignment: .leading)
                }
            }
            HStack(spacing: 8) {
                StatTile(label: "Sets", value: Double(game.sets))
                StatTile(label: "Loaded", value: Double(game.loadedSets))
                StatTile(label: "Cards", value: Double(game.cardCount ?? 0))
            }
            if let next { NextRelease(set: next) }
        }
        .padding(.horizontal, 16)
        .padding(.top, 8)
        .background(alignment: .top) { ExploreBackdrop() }
    }
}

// MARK: - A set's page

/// A set's page, like the website's: its banner and name over a lit grid (with a countdown and
/// bell before release), its size and value counting up, how much of it you own, its chase
/// cards, the best sealed value per pack, then every product under Singles and Sealed tabs with
/// a sort. Cards and sealed share one card-shaped frame so the grid lines up.
private struct SetView: View {
    var set: ExploreSet
    @Environment(CollectionStore.self) private var store
    @State private var detail: ExploreSetDetail?
    @State private var failed = false
    @State private var tab = SetTab.singles
    @State private var sort = Sort.price

    enum SetTab { case singles, sealed }

    enum Sort: String, CaseIterable {
        case price = "Price: high to low"
        case perPack = "Price per pack: low to high"
        case number = "Collector number"
        case name = "Name"
    }

    private var info: ExploreSet { detail?.set ?? set }
    private var products: [SearchHit] { detail?.products ?? [] }
    private var singles: [SearchHit] { products.filter { !$0.product.isSealed } }
    private var sealed: [SearchHit] { products.filter(\.product.isSealed) }
    private var ownedIds: Set<String> { Set(store.holdings.map(\.identity.productId)) }
    private var ownedCount: Int { products.filter { ownedIds.contains($0.product.id) }.count }

    private func perPack(_ hit: SearchHit) -> Double? {
        Packs.perPack(hit.market, Packs.count(hit.product, gameSlug: info.gameSlug))
    }

    private var list: [SearchHit] {
        let items = tab == .singles ? singles : sealed
        let by: Sort = tab == .singles && sort == .perPack ? .price : sort
        switch by {
        case .price: return items.sorted { ($0.market ?? -1) > ($1.market ?? -1) }
        case .perPack: return items.sorted { (perPack($0) ?? .infinity) < (perPack($1) ?? .infinity) }
        case .number:
            return items.sorted { a, b in
                guard let x = a.product.number else { return false }
                guard let y = b.product.number else { return true }
                return x.localizedStandardCompare(y) == .orderedAscending
            }
        case .name: return items.sorted { $0.product.name.localizedStandardCompare($1.product.name) == .orderedAscending }
        }
    }

    var body: some View {
        ScrollView {
            LazyVStack(alignment: .leading, spacing: 0, pinnedViews: [.sectionHeaders]) {
                SetHero(set: info, productCount: products.count, ownedCount: ownedCount,
                        updatedAt: products.compactMap(\.priceUpdatedAt).max())
                    .padding(.bottom, 30)
                if detail == nil && !failed {
                    SkeletonGrid()
                } else if products.isEmpty {
                    emptyNote
                } else {
                    VStack(alignment: .leading, spacing: 36) {
                        HStack(spacing: 8) {
                            StatTile(label: "Singles", value: Double(singles.count))
                            StatTile(label: "Sealed", value: Double(sealed.count))
                            StatTile(label: "Set value", value: singles.compactMap(\.market).reduce(0, +), money: true)
                        }
                        .padding(.horizontal, 16)
                        if ownedCount > 0 {
                            OwnedProgress(owned: ownedCount, total: products.count).padding(.horizontal, 16).reveal()
                        }
                        chase
                        packs
                    }
                    .padding(.bottom, 36)
                    Section {
                        grid
                    } header: {
                        controls
                    }
                }
            }
            .padding(.bottom, 40)
        }
        .background(Theme.background)
        .replaysAnimations()
        .tabBarClearance()
        .navigationBarTitleDisplayMode(.inline)
        .pageTitle(info.gameName)
        .task { await load() }
    }

    private func load() async {
        guard detail == nil else { return }
        if Demo.isOn {
            detail = DemoData.exploreSet(set.slug) ?? ExploreSetDetail(set: set, products: [])
        } else {
            do { detail = try await Backend.shared.api.exploreSet(set.slug) } catch { failed = true }
        }
        // Open on whichever tab has products.
        if singles.isEmpty && !sealed.isEmpty { tab = .sealed }
    }

    private var emptyNote: some View {
        VStack(alignment: .leading, spacing: 8) {
            Text(failed ? "Couldn't load this set" : "Not in the catalog yet").font(.geist(16, .semibold))
            Text(failed ? "Check your connection and try again."
                 : (info.releaseDate ?? "") >= Format.day()
                 ? "Its cards and sealed products show up here once the set is out."
                 : "The catalog fills in a few sets a day. Check back soon.")
                .font(.geist(14)).foregroundStyle(Theme.muted)
        }
        .padding(18)
        .frame(maxWidth: .infinity, alignment: .leading)
        .background(RoundedRectangle(cornerRadius: 20, style: .continuous).fill(Theme.surface))
        .overlay(RoundedRectangle(cornerRadius: 20, style: .continuous).strokeBorder(Theme.border))
        .padding(.horizontal, 16)
    }

    // MARK: Chase cards

    @ViewBuilder private var chase: some View {
        // Cards only: the catalog sometimes files a box or pack as a single, so leave out
        // anything named or typed like sealed product too.
        let top = Array(singles.filter { $0.market != nil && !Self.looksSealed($0.product) }.sorted { ($0.market ?? 0) > ($1.market ?? 0) }.prefix(10))
        if let first = top.first {
            VStack(alignment: .leading, spacing: 14) {
                PageHeader(title: "Chase cards", subtitle: "The most valuable singles in this set", size: 22).padding(.horizontal, 16)
                link(first) { TopChase(hit: first, owned: ownedIds.contains(first.product.id)) }
                    .padding(.horizontal, 16)
                if top.count > 1 {
                    ScrollView(.horizontal, showsIndicators: false) {
                        HStack(alignment: .top, spacing: 12) {
                            ForEach(Array(top.dropFirst().enumerated()), id: \.element.id) { i, hit in
                                link(hit) { ChaseTile(hit: hit, rank: i + 2) }
                            }
                        }
                        .padding(.horizontal, 16)
                        .padding(.vertical, 4)
                    }
                }
            }
            .reveal()
        }
    }

    private static func looksSealed(_ p: Product) -> Bool {
        let text = "\(p.name) \(p.productType ?? "")".lowercased()
        return text.range(of: #"\b(booster|box|bundle|pack|tin|collection|display|case|blister|deck|kit|trainer box|etb|starter)\b"#,
                          options: .regularExpression) != nil
    }

    // MARK: Best value per pack

    @ViewBuilder private var packs: some View {
        let priced = sealed.compactMap { h in perPack(h).map { (hit: h, per: $0) } }.sorted { $0.per < $1.per }
        if !priced.isEmpty {
            VStack(alignment: .leading, spacing: 14) {
                PageHeader(title: "Best value", subtitle: "Sealed by price per pack", size: 22).padding(.horizontal, 16)
                ScrollView(.horizontal, showsIndicators: false) {
                    HStack(alignment: .top, spacing: 12) {
                        ForEach(Array(priced.prefix(8).enumerated()), id: \.element.hit.id) { i, item in
                            link(item.hit) { PackTile(hit: item.hit, perPack: item.per, best: i == 0) }
                        }
                    }
                    .padding(.horizontal, 16)
                    .padding(.vertical, 4)
                }
            }
            .reveal()
        }
    }

    // MARK: Every product

    private var controls: some View {
        HStack(spacing: 10) {
            HStack(spacing: 2) {
                Chip(title: "Singles", selected: tab == .singles, count: singles.count) { pick(.singles) }
                Chip(title: "Sealed", selected: tab == .sealed, count: sealed.count) { pick(.sealed) }
            }
            .padding(4)
            .liquidGlass(in: Capsule())
            Spacer(minLength: 0)
            Menu {
                Picker("Sort", selection: $sort) {
                    ForEach(Sort.allCases.filter { tab == .sealed || $0 != .perPack }, id: \.self) { Text($0.rawValue).tag($0) }
                }
            } label: {
                Image(systemName: "arrow.up.arrow.down")
                    .font(.system(size: 15, weight: .semibold))
                    .foregroundStyle(.white)
                    .frame(width: 44, height: 44)
                    .liquidGlass(in: Circle())
            }
            .accessibilityLabel("Sort")
        }
        .padding(.horizontal, 16)
        .padding(.vertical, 8)
    }

    private func pick(_ t: SetTab) {
        withAnimation(.snappy(duration: 0.3)) { tab = t }
    }

    private var grid: some View {
        let shown = list
        let by: Sort = tab == .singles && sort == .perPack ? .price : sort
        return VStack(alignment: .leading, spacing: 14) {
            MonoLabel(text: "\(shown.count) \(tab == .singles ? "singles" : "sealed") · \(by.rawValue)")
            if shown.isEmpty {
                Text(tab == .singles ? "No singles in this set." : "No sealed products in this set.")
                    .font(.geist(14)).foregroundStyle(Theme.muted)
                    .frame(maxWidth: .infinity).padding(.vertical, 50)
            }
            LazyVGrid(columns: twoColumns, alignment: .leading, spacing: 28) {
                ForEach(shown) { hit in
                    link(hit) {
                        SetProductTile(hit: hit, owned: ownedIds.contains(hit.product.id), perPack: tab == .sealed ? perPack(hit) : nil)
                    }
                }
            }
        }
        .padding(.horizontal, 16)
        .padding(.top, 8)
        .id(tab)
        .transition(.opacity)
    }

    private func link<Content: View>(_ hit: SearchHit, @ViewBuilder label: () -> Content) -> some View {
        NavigationLink(value: hit.product.id) { label() }
            .buttonStyle(.plain)
            .simultaneousGesture(TapGesture().onEnded { store.seed(hit) })
    }
}

/// The top of a set's page: the banner, the name, what's in it, and a countdown before release.
private struct SetHero: View {
    var set: ExploreSet
    var productCount: Int
    var ownedCount: Int
    var updatedAt: String?

    private var upcoming: Bool { (set.releaseDate ?? "") >= Format.day() }

    private var meta: String {
        let date = set.release?.formatted(date: .abbreviated, time: .omitted)
        return [
            date.map { upcoming ? "Out \($0)" : "Released \($0)" },
            productCount > 0 ? "\(productCount) products" : nil,
            ownedCount > 0 ? "\(ownedCount) owned" : nil,
            agoText(updatedAt).map { "prices from \($0)" },
        ].compactMap { $0 }.joined(separator: " · ")
    }

    var body: some View {
        VStack(alignment: .leading, spacing: 20) {
            art
            VStack(alignment: .leading, spacing: 8) {
                MonoLabel(text: set.gameName)
                DisplayText(text: set.name.uppercased(), size: 34).frame(maxWidth: .infinity, alignment: .leading)
                Text(meta).font(.geist(13)).foregroundStyle(Theme.muted).monospacedDigit()
            }
            if upcoming { ReleaseCountdown(set: set) }
        }
        .padding(.horizontal, 16)
        .padding(.top, 8)
        .background(alignment: .top) { ExploreBackdrop() }
    }

    @ViewBuilder private var art: some View {
        let shape = RoundedRectangle(cornerRadius: 22, style: .continuous)
        if let banner = set.iconUrl.flatMap(URL.init(string:)) {
            // Sized to the frame, not the picture: the banner fills it and is cut at its edges.
            Color.clear
                .aspectRatio(3.0 / 2.0, contentMode: .fit)
                .overlay { CachedImage(url: banner) { img in img.resizable().scaledToFill() } placeholder: { Theme.well } }
                .clipShape(shape)
                .overlay(ElectricBorder(radius: 22))
                .shadow(color: Theme.lime.opacity(0.22), radius: 22)
                .tiltCard(4, cornerRadius: 22)
        } else if let sample = set.imageUrl.flatMap(URL.init(string:)) {
            ZStack {
                shape.fill(Theme.well)
                CachedImage(url: sample) { img in img.resizable().scaledToFit() } placeholder: { Color.clear }
                    .padding(28)
            }
            .frame(height: 180)
            .overlay(shape.strokeBorder(Theme.border))
        }
    }
}

/// Days to release in big lime numbers, with the reminder bell.
private struct ReleaseCountdown: View {
    var set: ExploreSet
    @Environment(CollectionStore.self) private var store
    @State private var busy = false

    private var days: Int {
        guard let d = set.release else { return 0 }
        return max(0, Calendar.current.dateComponents([.day], from: Calendar.current.startOfDay(for: Date()), to: d).day ?? 0)
    }

    var body: some View {
        let on = store.reminders.contains(set.slug)
        HStack(spacing: 14) {
            VStack(alignment: .leading, spacing: 6) {
                MonoLabel(text: days == 0 ? "Out" : "Out in")
                HStack(alignment: .firstTextBaseline, spacing: 6) {
                    CountingText(value: Double(days), format: { "\(Int($0.rounded()))" })
                        .font(.display(44)).monospacedDigit().foregroundStyle(Theme.lime).displayTrim(44)
                        .shadow(color: Theme.lime.opacity(0.45), radius: 12)
                        .fixedSize()
                    Text(days == 0 ? "today" : (days == 1 ? "day" : "days")).font(.geist(14)).foregroundStyle(Theme.muted)
                }
            }
            Spacer(minLength: 0)
            Button {
                busy = true
                Task { try? await store.setReminder(set, on: !on); busy = false }
            } label: {
                Label(on ? "Reminder on" : "Remind me", systemImage: on ? "bell.fill" : "bell")
            }
            .buttonStyle(Button3D(kind: on ? .lime : .dark, fullWidth: false, height: 40))
            .disabled(busy)
        }
        .padding(16)
        .liquidGlass(in: RoundedRectangle(cornerRadius: 20, style: .continuous))
    }
}

/// "You own 3 of 212": a lime bar that fills in.
private struct OwnedProgress: View {
    var owned: Int
    var total: Int
    @Environment(\.accessibilityReduceMotion) private var reduceMotion
    @State private var filled = false

    var body: some View {
        let ratio = total > 0 ? Double(owned) / Double(total) : 0
        VStack(alignment: .leading, spacing: 12) {
            HStack(alignment: .lastTextBaseline) {
                VStack(alignment: .leading, spacing: 6) {
                    MonoLabel(text: "You own")
                    HStack(alignment: .firstTextBaseline, spacing: 6) {
                        CountingText(value: Double(owned), format: { "\(Int($0.rounded()))" })
                            .font(.display(34)).monospacedDigit().foregroundStyle(Theme.lime).displayTrim(34).fixedSize()
                        Text("of \(total) products").font(.geist(14)).foregroundStyle(Theme.muted)
                    }
                }
                Spacer()
                Text(ratio < 0.01 ? "<1%" : "\(Int((ratio * 100).rounded()))%").font(.geist(15, .semibold)).monospacedDigit()
            }
            GeometryReader { geo in
                ZStack(alignment: .leading) {
                    Capsule().fill(Color.white.opacity(0.08))
                    Capsule().fill(Theme.lime)
                        .frame(width: max(8, geo.size.width * (filled ? ratio : 0)))
                        .shadow(color: Theme.lime.opacity(0.5), radius: 6)
                }
            }
            .frame(height: 8)
        }
        .padding(18)
        .background(RoundedRectangle(cornerRadius: 20, style: .continuous).fill(Theme.surface))
        .overlay(RoundedRectangle(cornerRadius: 20, style: .continuous).strokeBorder(Theme.border))
        .onAppear { fill() }
        .onReplay { filled = false; fill() }
    }

    private func fill() {
        if reduceMotion { filled = true } else { withAnimation(.spring(duration: 1.1).delay(0.15)) { filled = true } }
    }
}

/// The set's most valuable card, big, leaning with the phone and catching the light if it's foil.
private struct TopChase: View {
    var hit: SearchHit
    var owned: Bool

    var body: some View {
        let p = hit.product
        let shape = RoundedRectangle(cornerRadius: 22, style: .continuous)
        HStack(alignment: .center, spacing: 18) {
            ProductImage(product: p, cornerRadius: 7)
                .frame(width: 120, height: 168)
                .tiltCard(9, foil: p.isFoil, cornerRadius: 7)
                .shadow(color: .black.opacity(0.5), radius: 12, y: 8)
            VStack(alignment: .leading, spacing: 10) {
                HStack(spacing: 6) {
                    SkewTag(text: "No. 1 chase", icon: "flame.fill")
                    if owned { SkewTag(text: "Owned", color: Theme.planBlue, textColor: .white) }
                }
                Text(p.name).font(.geist(17, .semibold)).foregroundStyle(.white).lineLimit(3).multilineTextAlignment(.leading)
                if let r = p.rarity { RarityBadge(rarity: r) }
                CountingText(value: hit.market ?? 0, format: { Format.money($0) })
                    .font(.display(34)).monospacedDigit().foregroundStyle(.white)
                    .lineLimit(1).minimumScaleFactor(0.6).displayTrim(34)
            }
            Spacer(minLength: 0)
        }
        .padding(18)
        .background {
            ZStack {
                shape.fill(Color(hex: 0x070707))
                GridPattern(step: 28, opacity: 0.06)
                RadialGradient(colors: [Theme.lime.opacity(0.2), .clear], center: UnitPoint(x: 0.15, y: 0.5), startRadius: 0, endRadius: 200)
            }
            .clipShape(shape)
        }
        .overlay(ElectricBorder(radius: 22))
        .shadow(color: Theme.lime.opacity(0.18), radius: 18)
    }
}

/// A chase card in the row under the top one, with its rank.
private struct ChaseTile: View {
    var hit: SearchHit
    var rank: Int

    var body: some View {
        VStack(alignment: .leading, spacing: 8) {
            ProductImage(product: hit.product, cornerRadius: 6)
                .frame(width: 118, height: 165)
                .overlay(alignment: .topLeading) {
                    Text("#\(rank)").font(.display(15)).foregroundStyle(Theme.ink)
                        .padding(.horizontal, 7).padding(.vertical, 2)
                        .background(Parallelogram(inset: 4).fill(Theme.lime))
                        .padding(6)
                }
            Text(hit.product.name).font(.geist(13, .medium)).foregroundStyle(.white).lineLimit(1)
            Text(Format.money(hit.market)).font(.display(17)).monospacedDigit().foregroundStyle(.white)
        }
        .frame(width: 118, alignment: .leading)
    }
}

/// A sealed product with its price per pack.
private struct PackTile: View {
    var hit: SearchHit
    var perPack: Double
    var best: Bool

    var body: some View {
        VStack(alignment: .leading, spacing: 8) {
            SealedWell(product: hit.product, cornerRadius: 18, caption: true)
                .frame(width: 140, height: 140)
                .overlay(alignment: .topLeading) { if best { SkewTag(text: "Best value", icon: "bolt.fill").padding(8) } }
            Text(hit.product.name).font(.geist(13, .medium)).foregroundStyle(.white).lineLimit(2).multilineTextAlignment(.leading)
                .frame(height: 34, alignment: .topLeading)
            HStack(alignment: .firstTextBaseline, spacing: 5) {
                Text(Format.money(perPack)).font(.display(19)).monospacedDigit().foregroundStyle(Theme.lime)
                Text("/pack").font(.geist(12)).foregroundStyle(Theme.muted)
            }
            Text(Format.money(hit.market)).font(.geist(12)).monospacedDigit().foregroundStyle(Theme.muted)
        }
        .frame(width: 140, alignment: .leading)
    }
}

/// A product in a set's grid, like the website's tile: cards and sealed share one tall,
/// card-shaped frame (sealed sits in a dark well), then the name, number and rarity, and price.
private struct SetProductTile: View {
    var hit: SearchHit
    var owned: Bool
    var perPack: Double?

    var body: some View {
        let p = hit.product
        let rarity = p.rarity.flatMap { $0.isEmpty || $0.lowercased() == "none" ? nil : $0 }
        let sub = [p.number.map { "#\($0)" }, rarity ?? (p.isSealed ? p.productType : nil)].compactMap { $0 }.joined(separator: " · ")
        VStack(alignment: .leading, spacing: 0) {
            Color.clear
                .aspectRatio(5.0 / 7.0, contentMode: .fit)
                .overlay(alignment: .bottom) {
                    if p.isSealed || p.imageURL == nil {
                        SealedWell(product: p, cornerRadius: 14, caption: true)
                    } else {
                        ProductImage(product: p, cornerRadius: 8).aspectRatio(63.0 / 88.0, contentMode: .fit)
                    }
                }
                .overlay(alignment: .topLeading) {
                    if owned {
                        HStack(spacing: 4) {
                            Image(systemName: "checkmark").font(.system(size: 9, weight: .black))
                            Text("Owned").font(.geist(11, .semibold))
                        }
                        .foregroundStyle(.white)
                        .padding(.horizontal, 8)
                        .padding(.vertical, 4)
                        .liquidGlass(in: Capsule())
                        .padding(8)
                    }
                }
            Text(p.name).font(.geist(13, .medium)).foregroundStyle(.white).lineLimit(2).multilineTextAlignment(.leading)
                .padding(.top, 10)
            if !sub.isEmpty {
                Text(sub).font(.geist(12)).foregroundStyle(Theme.muted).lineLimit(1).padding(.top, 2)
            }
            HStack(alignment: .firstTextBaseline, spacing: 6) {
                if let m = hit.market {
                    Text(Format.money(m)).font(.display(19)).monospacedDigit().foregroundStyle(.white)
                } else {
                    Text("No price").font(.geist(13)).foregroundStyle(Theme.subtle)
                }
                if let perPack { Text("\(Format.money(perPack))/pack").font(.geist(12)).foregroundStyle(Theme.muted) }
            }
            .lineLimit(1)
            .padding(.top, 6)
        }
        .frame(maxWidth: .infinity, alignment: .leading)
    }
}

/// Card-shaped placeholders that breathe while a set loads.
private struct SkeletonGrid: View {
    @Environment(\.accessibilityReduceMotion) private var reduceMotion
    @State private var dim = false

    var body: some View {
        LazyVGrid(columns: twoColumns, spacing: 28) {
            ForEach(0 ..< 6, id: \.self) { _ in
                RoundedRectangle(cornerRadius: 14, style: .continuous).fill(Theme.well).aspectRatio(5.0 / 7.0, contentMode: .fit)
            }
        }
        .padding(.horizontal, 16)
        .opacity(dim ? 0.45 : 1)
        .onAppear {
            guard !reduceMotion else { return }
            withAnimation(.easeInOut(duration: 0.9).repeatForever(autoreverses: true)) { dim = true }
        }
    }
}

// MARK: - Release calendar

/// Upcoming sets by month, plus the last 30 days of releases: counts and the next release up
/// top, then a row per set with its date, art, a countdown tag and a reminder bell.
struct ReleaseCalendarView: View {
    var sets: [ExploreSet]
    @Environment(CollectionStore.self) private var store

    private var today: String { Format.day() }
    private var upcoming: [ExploreSet] {
        sets.filter { ($0.releaseDate ?? "") >= today }.sorted { ($0.releaseDate ?? "") < ($1.releaseDate ?? "") }
    }

    private var months: [(month: String, sets: [ExploreSet])] {
        let grouped = Dictionary(grouping: upcoming) { String(($0.releaseDate ?? "").prefix(7)) }
        return grouped.keys.sorted().map { ($0, grouped[$0]!) }
    }

    private var recent: [ExploreSet] {
        let since = Format.day(Calendar.current.date(byAdding: .day, value: -30, to: Date()) ?? Date())
        return sets.filter { let d = $0.releaseDate ?? ""; return d < today && d >= since }.sorted { ($0.releaseDate ?? "") > ($1.releaseDate ?? "") }
    }

    var body: some View {
        let soon = Format.day(Calendar.current.date(byAdding: .day, value: 30, to: Date()) ?? Date())
        ScrollView {
            VStack(alignment: .leading, spacing: 36) {
                VStack(alignment: .leading, spacing: 22) {
                    HStack(spacing: 8) {
                        StatTile(label: "Upcoming", value: Double(upcoming.count))
                        StatTile(label: "Next 30 days", value: Double(upcoming.filter { ($0.releaseDate ?? "") <= soon }.count))
                        StatTile(label: "Reminders", value: Double(upcoming.filter { store.reminders.contains($0.slug) }.count), tint: Theme.lime)
                    }
                    if let next = upcoming.first { NextRelease(set: next) }
                }
                .padding(.horizontal, 16)
                .padding(.top, 8)
                .background(alignment: .top) { ExploreBackdrop() }
                if upcoming.isEmpty {
                    Text("No upcoming releases in the catalog yet.").font(.geist(14)).foregroundStyle(Theme.muted).padding(.horizontal, 16)
                }
                ForEach(months, id: \.month) { group in
                    section(monthTitle(group.month), group.sets, upcoming: true)
                }
                if !recent.isEmpty {
                    section("Out in the last 30 days", recent, upcoming: false)
                }
            }
            .padding(.bottom, 40)
        }
        .background(Theme.background)
        .replaysAnimations()
        .tabBarClearance()
        .navigationBarTitleDisplayMode(.inline)
        .pageTitle("Release calendar")
    }

    private func section(_ title: String, _ sets: [ExploreSet], upcoming: Bool) -> some View {
        VStack(alignment: .leading, spacing: 12) {
            SectionCount(title: title, count: sets.count, noun: "set")
            VStack(spacing: 10) {
                ForEach(sets) { s in
                    NavigationLink(value: s) { CalendarRow(set: s, upcoming: upcoming) }.buttonStyle(.plain)
                }
            }
        }
        .padding(.horizontal, 16)
        .reveal()
    }

    private func monthTitle(_ ym: String) -> String {
        Format.isoDay.date(from: ym + "-01")?.formatted(.dateTime.month(.wide).year()) ?? ym
    }
}

/// One set on the calendar: a date block, its art, its name and countdown, and a bell.
private struct CalendarRow: View {
    var set: ExploreSet
    var upcoming: Bool
    @Environment(CollectionStore.self) private var store
    @State private var busy = false

    private var days: Int? {
        guard let d = set.release else { return nil }
        return Calendar.current.dateComponents([.day], from: Calendar.current.startOfDay(for: Date()), to: d).day
    }

    var body: some View {
        let on = store.reminders.contains(set.slug)
        let shape = RoundedRectangle(cornerRadius: 18, style: .continuous)
        HStack(spacing: 12) {
            VStack(spacing: 4) {
                MonoLabel(text: set.release?.formatted(.dateTime.month(.abbreviated)) ?? "TBA")
                Text(set.release?.formatted(.dateTime.day()) ?? "–")
                    .font(.display(26)).monospacedDigit().displayTrim(26)
                    .foregroundStyle(upcoming && (days ?? 99) <= 7 ? Theme.lime : .white)
            }
            .frame(width: 50, height: 60)
            .background(RoundedRectangle(cornerRadius: 14, style: .continuous).fill(Theme.well))
            SetArt(set: set)
                .frame(width: 78, height: 52)
                .clipShape(RoundedRectangle(cornerRadius: 10, style: .continuous))
            VStack(alignment: .leading, spacing: 5) {
                Text(set.name).font(.geist(15, .semibold)).foregroundStyle(.white).lineLimit(2).multilineTextAlignment(.leading)
                if upcoming, let days {
                    SkewTag(text: days <= 0 ? "Out today" : "In \(days) day\(days == 1 ? "" : "s")",
                            color: days <= 7 ? Theme.lime : Theme.planBlue, textColor: days <= 7 ? Theme.ink : .white)
                } else {
                    Text(set.gameName).font(.geist(12)).foregroundStyle(Theme.muted).lineLimit(1)
                }
            }
            Spacer(minLength: 0)
            if upcoming {
                Button {
                    busy = true
                    Task { try? await store.setReminder(set, on: !on); busy = false }
                } label: {
                    Image(systemName: on ? "bell.fill" : "bell")
                        .font(.system(size: 14, weight: .semibold))
                        .foregroundStyle(on ? Theme.ink : Theme.muted)
                        .frame(width: 38, height: 38)
                        .background(Circle().fill(on ? Theme.lime : Color.white.opacity(0.06)))
                }
                .buttonStyle(.plain)
                .disabled(busy)
                .accessibilityLabel(on ? "Turn off reminder" : "Remind me on release day")
            }
        }
        .padding(10)
        .background(shape.fill(Theme.surface))
        .overlay(shape.strokeBorder(Theme.border))
    }
}

// MARK: - Shared Explore pieces

private let twoColumns = [GridItem(.flexible(), spacing: 14, alignment: .top), GridItem(.flexible(), spacing: 14, alignment: .top)]

/// The routes Explore pushes besides brands, sets and products.
enum ExploreRoute: Hashable { case calendar }

/// "2025  4 SETS": a section title in Anton with a mono count.
private struct SectionCount: View {
    var title: String
    var count: Int
    var noun: String

    var body: some View {
        HStack(alignment: .firstTextBaseline, spacing: 10) {
            Text(title.uppercased()).font(.display(24)).monospacedDigit().lineLimit(1).minimumScaleFactor(0.8)
            MonoLabel(text: "\(count) \(noun)\(count == 1 ? "" : "s")")
            Spacer(minLength: 0)
        }
    }
}

/// A glass tile with a mono label and a number that counts up.
private struct StatTile: View {
    var label: String
    var value: Double
    var money = false
    var tint: Color = .white

    var body: some View {
        VStack(alignment: .leading, spacing: 4) {
            MonoLabel(text: label).lineLimit(1).minimumScaleFactor(0.8)
            CountingText(value: value, format: { money ? Self.money($0) : Self.count($0) })
                .font(.display(28)).monospacedDigit().foregroundStyle(tint)
                .lineLimit(1).minimumScaleFactor(0.6).displayTrim(28)
        }
        .padding(.horizontal, 14)
        .padding(.vertical, 12)
        .frame(maxWidth: .infinity, alignment: .leading)
        .liquidGlass(in: RoundedRectangle(cornerRadius: 16, style: .continuous))
    }

    static func count(_ v: Double) -> String { v >= 10_000 ? String(format: "%.0fK", v / 1000) : Int(v.rounded()).formatted() }
    static func money(_ v: Double) -> String { v >= 100_000 ? "$" + String(format: "%.0fK", v / 1000) : Format.moneyWhole(v) }
}

/// The lit grid and soft glows behind the top of each Explore page.
private struct ExploreBackdrop: View {
    var body: some View {
        ZStack {
            GridPattern(step: 36, opacity: 0.05)
            RadialGradient(colors: [Theme.lime.opacity(0.22), .clear], center: UnitPoint(x: 0.2, y: 0.3), startRadius: 0, endRadius: 260)
            RadialGradient(colors: [Theme.planBlue.opacity(0.22), .clear], center: UnitPoint(x: 0.9, y: 0.55), startRadius: 0, endRadius: 240)
            RadialGradient(colors: [Theme.planPink.opacity(0.16), .clear], center: UnitPoint(x: 0.6, y: 0.05), startRadius: 0, endRadius: 200)
        }
        .mask(LinearGradient(stops: [.init(color: .black, location: 0), .init(color: .black, location: 0.7), .init(color: .clear, location: 1)],
                             startPoint: .top, endPoint: .bottom))
        .padding(.top, -160)
        .padding(.bottom, -40)
        .allowsHitTesting(false)
    }
}

/// A set's art filling its frame: the banner, else a sample product on a dark well, else its name.
private struct SetArt: View {
    var set: ExploreSet

    private var icon: some View {
        Image(systemName: "square.stack.3d.up").font(.system(size: 22)).foregroundStyle(Theme.lime.opacity(0.6))
    }

    var body: some View {
        ZStack {
            Theme.well
            if let banner = set.iconUrl.flatMap(URL.init(string:)) {
                Color.clear
                    .overlay { CachedImage(url: banner) { img in img.resizable().scaledToFill() } placeholder: { icon } }
                    .clipped()
            } else if let sample = set.imageUrl.flatMap(URL.init(string:)) {
                CachedImage(url: sample) { img in img.resizable().scaledToFit() } placeholder: { icon }
                    .padding(12)
            } else {
                Text(set.name).font(.geist(12, .semibold)).foregroundStyle(Theme.subtle).multilineTextAlignment(.center)
                    .lineLimit(3).padding(8)
            }
        }
    }
}

/// "3h ago" from an ISO timestamp.
private func agoText(_ iso: String?) -> String? {
    guard let iso else { return nil }
    let f = ISO8601DateFormatter()
    f.formatOptions = [.withInternetDateTime, .withFractionalSeconds]
    guard let date = f.date(from: iso) ?? ISO8601DateFormatter().date(from: iso) else { return nil }
    let minutes = max(0, Int(Date().timeIntervalSince(date) / 60))
    if minutes < 60 { return "\(minutes)m ago" }
    let hours = minutes / 60
    if hours < 24 { return "\(hours)h ago" }
    return "\(Int((Double(hours) / 24).rounded()))d ago"
}

/// How many booster packs a sealed product holds, from its name or its type's standard
/// contents (a port of the website's lib/packs.ts).
enum Packs {
    private static let words: [String: Int] = ["one": 1, "two": 2, "three": 3, "four": 4, "five": 5, "six": 6, "seven": 7,
                                               "eight": 8, "nine": 9, "ten": 10, "twelve": 12]
    /// Booster box contents differ by game.
    private static let boxPacks: [String: Int] = ["pokemon": 36, "pokemon-japan": 30, "magic": 36, "yugioh": 24, "onepiece": 24, "lorcana": 24]

    private static func franchise(_ slug: String?) -> String? {
        guard let s = slug?.lowercased() else { return nil }
        if s.contains("pokemon") { return s.contains("japan") ? "pokemon-japan" : "pokemon" }
        if s.contains("magic") { return "magic" }
        if s.range(of: "yu-?gi-?oh", options: .regularExpression) != nil { return "yugioh" }
        if s.range(of: "one-?piece", options: .regularExpression) != nil { return "onepiece" }
        if s.contains("lorcana") { return "lorcana" }
        return nil
    }

    static func count(_ product: Product, gameSlug: String?) -> Int? {
        guard product.isSealed else { return nil }
        let name = product.name.lowercased()
            .replacingOccurrences(of: #"\([^)]*\b(case|lot|set of)\b[^)]*\)"#, with: " ", options: .regularExpression)
        func has(_ pattern: String) -> Bool { name.range(of: pattern, options: .regularExpression) != nil }
        // Cases and multi-box lots would need a box count too; leave them out.
        if has(#"\bcase\b|\blot\b|\bx\s?\d+\b|\d+\s?x\b"#) { return nil }
        if let r = name.range(of: #"\b(\d{1,2}|one|two|three|four|five|six|seven|eight|nine|ten|twelve)[\s-]*(?:booster[\s-]*)?packs?\b"#,
                              options: .regularExpression) {
            let token = name[r].split(whereSeparator: { $0 == " " || $0 == "-" }).first.map(String.init) ?? ""
            if let n = words[token] ?? Int(token), n > 0 { return n }
        }
        if has(#"\b(single|sleeved)? ?booster pack\b|\bsleeved booster\b"#) && !has("box|bundle|display|blister") { return 1 }
        if has(#"elite trainer box|\betb\b"#) { return 9 }
        if has("booster bundle") { return 6 }
        if has("collector booster (box|display)") { return 12 }
        if has("set booster (box|display)") { return 30 }
        if has("(play|draft) booster (box|display)") { return 36 }
        if has("booster (box|display)"), let key = franchise(gameSlug), let n = boxPacks[key] { return n }
        return nil
    }

    static func perPack(_ price: Double?, _ count: Int?) -> Double? {
        guard let price, let count else { return nil }
        return price / Double(count)
    }
}

// MARK: - Explore landing pieces

/// The top of Explore: the catalog's size counting up over a lit grid, and the next release as
/// a big card with a countdown and its reminder bell.
private struct CatalogHero: View {
    var index: ExploreIndex
    var next: ExploreSet?

    var body: some View {
        let cards = index.games.compactMap(\.cardCount).reduce(0, +)
        VStack(alignment: .leading, spacing: 22) {
            HStack(spacing: 8) {
                StatTile(label: "Brands", value: Double(index.games.count))
                StatTile(label: "Sets", value: Double(index.sets.count))
                StatTile(label: "Cards", value: Double(cards))
            }
            if let next { NextRelease(set: next) }
        }
        .padding(.horizontal, 16)
        .padding(.top, 8)
        .background(alignment: .top) { ExploreBackdrop() }
    }
}

/// The next set to come out: its art, name and date, a big day countdown in lime, and a bell.
private struct NextRelease: View {
    var set: ExploreSet
    @Environment(CollectionStore.self) private var store
    @State private var busy = false

    private var days: Int {
        guard let d = set.release else { return 0 }
        return max(0, Calendar.current.dateComponents([.day], from: Calendar.current.startOfDay(for: Date()), to: d).day ?? 0)
    }

    var body: some View {
        let on = store.reminders.contains(set.slug)
        NavigationLink(value: set) {
            HStack(alignment: .center, spacing: 16) {
                VStack(alignment: .leading, spacing: 10) {
                    SkewTag(text: "Next release", icon: "sparkles")
                    DisplayText(text: set.name.uppercased(), size: 24)
                        .frame(maxWidth: .infinity, alignment: .leading)
                    Text([set.gameName, set.release?.formatted(date: .abbreviated, time: .omitted)].compactMap { $0 }.joined(separator: " · "))
                        .font(.geist(13)).foregroundStyle(Theme.muted).lineLimit(1)
                    Button {
                        busy = true
                        Task { try? await store.setReminder(set, on: !on); busy = false }
                    } label: {
                        Label(on ? "Reminder on" : "Remind me", systemImage: on ? "bell.fill" : "bell")
                    }
                    .buttonStyle(Button3D(kind: on ? .lime : .dark, fullWidth: false, height: 36))
                    .disabled(busy)
                }
                Spacer(minLength: 0)
                VStack(spacing: 6) {
                    CountingText(value: Double(days), format: { "\(Int($0.rounded()))" })
                        .font(.display(60)).monospacedDigit().foregroundStyle(Theme.lime).displayTrim(60)
                        .shadow(color: Theme.lime.opacity(0.5), radius: 16)
                        .fixedSize()
                    MonoLabel(text: days == 0 ? "today" : (days == 1 ? "day" : "days"))
                }
                .frame(minWidth: 70)
                .padding(.trailing, 6)
            }
            .padding(.vertical, 18)
            .padding(.leading, 18)
            .padding(.trailing, 20)
            .background {
                ZStack {
                    RoundedRectangle(cornerRadius: 22, style: .continuous).fill(Color(hex: 0x070707))
                    if let url = (set.iconUrl ?? set.imageUrl).flatMap(URL.init(string:)) {
                        // The set's banner, faded in from the right behind the countdown.
                        // Sized to the card, not the picture: the picture fills it and is cut at its edges.
                        Color.clear
                            .overlay { CachedImage(url: url) { img in img.resizable().scaledToFill() } placeholder: { Color.clear } }
                            .clipped()
                            .opacity(0.22)
                            .mask(LinearGradient(colors: [.clear, .black], startPoint: .leading, endPoint: .trailing))
                    }
                    RadialGradient(colors: [Theme.lime.opacity(0.16), .clear], center: .trailing, startRadius: 0, endRadius: 220)
                }
                .clipShape(RoundedRectangle(cornerRadius: 22, style: .continuous))
            }
            .overlay(ElectricBorder(radius: 22))
            .shadow(color: Theme.lime.opacity(0.2), radius: 18)
        }
        .buttonStyle(.plain)
    }
}

/// A sideways row of sets as tiles: the set's art on a dark well, its name, the date, and for
/// upcoming sets an "in N days" tag and a reminder bell.
private struct SetCarousel: View {
    var sets: [ExploreSet]
    var upcoming: Bool

    var body: some View {
        ScrollView(.horizontal, showsIndicators: false) {
            HStack(alignment: .top, spacing: 12) {
                ForEach(sets) { s in
                    NavigationLink(value: s) { SetTile(set: s, upcoming: upcoming) }.buttonStyle(.plain)
                }
            }
            .padding(.horizontal, 16)
            .padding(.vertical, 4)
        }
    }
}

private struct SetTile: View {
    var set: ExploreSet
    var upcoming: Bool
    /// Fixed for carousels; nil fills a grid column.
    var width: CGFloat? = 170
    /// The brand under the name (carousels); the brand page shows the product count instead.
    var showGame = true
    @Environment(CollectionStore.self) private var store

    private var days: Int? {
        guard let d = set.release else { return nil }
        return Calendar.current.dateComponents([.day], from: Calendar.current.startOfDay(for: Date()), to: d).day
    }

    private var subtitle: String {
        let date = set.release?.formatted(.dateTime.month(.abbreviated).day().year())
        if showGame { return [set.gameName, date].compactMap { $0 }.joined(separator: " · ") }
        let count = set.loaded ? set.productCount.flatMap { $0 > 0 ? "\($0) products" : nil } : nil
        return [date ?? "Undated", count].compactMap { $0 }.joined(separator: " · ")
    }

    var body: some View {
        let shape = RoundedRectangle(cornerRadius: 16, style: .continuous)
        VStack(alignment: .leading, spacing: 10) {
            // The set's banner art (TCG API's set icon) fills the frame; without one, a sample
            // product sits centered.
            SetArt(set: set)
                .aspectRatio(3.0 / 2.0, contentMode: .fit)
                .overlay(alignment: .topLeading) {
                    if upcoming, let days {
                        SkewTag(text: days <= 0 ? "Out today" : "In \(days) day\(days == 1 ? "" : "s")",
                                color: days <= 7 ? Theme.lime : Theme.planBlue, textColor: days <= 7 ? Theme.ink : .white)
                            .padding(10)
                    }
                }
                .overlay(alignment: .topTrailing) {
                    if upcoming, store.reminders.contains(set.slug) {
                        Image(systemName: "bell.fill").font(.system(size: 11, weight: .bold)).foregroundStyle(Theme.ink)
                            .frame(width: 24, height: 24).background(Circle().fill(Theme.lime))
                            .padding(8)
                    }
                }
                .clipShape(shape)
                .overlay(shape.strokeBorder(Theme.border))
            VStack(alignment: .leading, spacing: 2) {
                Text(set.name).font(.geist(14, .medium)).lineLimit(1).foregroundStyle(.white)
                Text(subtitle).font(.geist(12)).foregroundStyle(Theme.muted).lineLimit(1).monospacedDigit()
            }
            .frame(maxWidth: .infinity, alignment: .leading)
        }
        .frame(width: width)
    }
}

/// A brand as a tinted card: its logo, name, and how many sets and cards it has.
private struct BrandCard: View {
    var game: ExploreGame
    var tint: Color

    static let tints: [Color] = [Theme.lime, Theme.planPink, Theme.planBlue, Theme.azure]

    var body: some View {
        VStack(alignment: .center, spacing: 12) {
            CachedImage(url: game.logoUrl.flatMap(URL.init(string:))) { img in
                img.resizable().scaledToFit().shadow(color: .black.opacity(0.5), radius: 9, y: 8)
            } placeholder: {
                Text(game.name.prefix(1).uppercased()).font(.display(26)).foregroundStyle(tint)
            }
            .frame(height: 44)
            .frame(maxWidth: .infinity)
            VStack(alignment: .center, spacing: 3) {
                Text(game.name).font(.geist(15, .semibold)).lineLimit(1).minimumScaleFactor(0.85).foregroundStyle(.white)
                Text("\(game.sets) sets" + (game.cardCount.map { " · \($0.formatted()) cards" } ?? ""))
                    .font(.geist(12)).foregroundStyle(Theme.muted).monospacedDigit().lineLimit(1).minimumScaleFactor(0.8)
            }
        }
        .padding(14)
        .frame(maxWidth: .infinity, minHeight: 124, alignment: .center)
        .tinted(tint)
    }
}
