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

    private var today: String { Format.day() }
    private var upcoming: [ExploreSet] {
        (index?.sets ?? []).filter { ($0.releaseDate ?? "") >= today }.sorted { ($0.releaseDate ?? "") < ($1.releaseDate ?? "") }
    }

    private var recent: [ExploreSet] {
        (index?.sets ?? []).filter { ($0.releaseDate ?? "") < today }.sorted { ($0.releaseDate ?? "") > ($1.releaseDate ?? "") }
    }

    var body: some View {
        NavigationStack {
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
                            PageHeader(title: "Coming soon", subtitle: "New sets on the way", size: 30)
                            Spacer()
                            NavigationLink { ReleaseCalendarView(sets: index.sets) } label: {
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
                        PageHeader(title: "Just released", subtitle: "The newest sets in the catalog", size: 30).padding(.horizontal, 16)
                        SetCarousel(sets: Array(recent.prefix(12)), upcoming: false)
                    }
                    .reveal()
                }
                VStack(alignment: .leading, spacing: 14) {
                    PageHeader(title: "Brands", subtitle: "Every game in the catalog", size: 30)
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

/// One brand's sets, newest first, by year.
private struct BrandView: View {
    var game: ExploreGame
    var sets: [ExploreSet]

    private var years: [(year: String, sets: [ExploreSet])] {
        let grouped = Dictionary(grouping: sets) { String(($0.releaseDate ?? "Undated").prefix(4)) }
        return grouped.keys.sorted(by: >).map { ($0, grouped[$0]!.sorted { ($0.releaseDate ?? "") > ($1.releaseDate ?? "") }) }
    }

    var body: some View {
        List {
            ForEach(years, id: \.year) { group in
                Section(group.year) {
                    ForEach(group.sets) { s in
                        NavigationLink(value: s) { ReleaseRow(set: s) }
                    }
                }
            }
        }
        .scrollContentBackground(.hidden)
        .background(Theme.background)
        .tabBarClearance()
        .navigationTitle(game.name)
    }
}

/// A set's products, most valuable first.
private struct SetView: View {
    var set: ExploreSet
    @Environment(CollectionStore.self) private var store
    @State private var products: [SearchHit] = []
    @State private var loading = true
    @State private var kind = 0

    private let columns = [GridItem(.flexible(), spacing: 12), GridItem(.flexible(), spacing: 12), GridItem(.flexible(), spacing: 12)]
    private var shown: [SearchHit] {
        let list = products.filter { kind == 0 ? true : (kind == 1 ? !$0.product.isSealed : $0.product.isSealed) }
        return list.sorted { ($0.market ?? -1) > ($1.market ?? -1) }
    }

    var body: some View {
        ScrollView {
            VStack(alignment: .leading, spacing: 14) {
                ReleaseRow(set: set)
                Picker("", selection: $kind) {
                    Text("All").tag(0)
                    Text("Cards").tag(1)
                    Text("Sealed").tag(2)
                }
                .pickerStyle(.segmented)
                if loading {
                    ProgressView().frame(maxWidth: .infinity).padding(.top, 40)
                } else if !set.loaded || products.isEmpty {
                    Text("This set's cards aren't in the catalog yet. It fills in a few sets a day.").foregroundStyle(Theme.muted)
                }
                LazyVGrid(columns: columns, spacing: 16) {
                    ForEach(shown) { hit in
                        NavigationLink(value: hit.product.id) {
                            VStack(alignment: .leading, spacing: 4) {
                                ProductImage(product: hit.product, cornerRadius: 6).aspectRatio(5.0 / 7.0, contentMode: .fit)
                                Text(hit.product.name).font(.caption.weight(.medium)).lineLimit(1).foregroundStyle(.primary)
                                Text(Format.money(hit.market)).font(.caption.weight(.bold)).monospacedDigit().foregroundStyle(.primary)
                            }
                        }
                        .buttonStyle(.plain)
                        .simultaneousGesture(TapGesture().onEnded { store.seed(hit) })
                    }
                }
            }
            .padding(16)
        }
        .background(Theme.background)
        .tabBarClearance()
        .navigationTitle(set.name)
        .navigationBarTitleDisplayMode(.inline)
        .task {
            defer { loading = false }
            products = (try? await Backend.shared.api.exploreSet(set.slug))?.products ?? []
        }
    }
}

/// Upcoming sets by month, plus the last 30 days of releases.
struct ReleaseCalendarView: View {
    var sets: [ExploreSet]

    private var today: String { Format.day() }
    private var months: [(month: String, sets: [ExploreSet])] {
        let up = sets.filter { ($0.releaseDate ?? "") >= today }
        let grouped = Dictionary(grouping: up) { String(($0.releaseDate ?? "").prefix(7)) }
        return grouped.keys.sorted().map { ($0, grouped[$0]!.sorted { ($0.releaseDate ?? "") < ($1.releaseDate ?? "") }) }
    }
    private var recent: [ExploreSet] {
        let since = Format.day(Calendar.current.date(byAdding: .day, value: -30, to: Date()) ?? Date())
        return sets.filter { let d = $0.releaseDate ?? ""; return d < today && d >= since }.sorted { ($0.releaseDate ?? "") > ($1.releaseDate ?? "") }
    }

    var body: some View {
        List {
            if months.isEmpty { Text("No upcoming releases in the catalog yet.").foregroundStyle(Theme.muted) }
            ForEach(months, id: \.month) { group in
                Section(monthTitle(group.month)) {
                    ForEach(group.sets) { s in NavigationLink(value: s) { ReleaseRow(set: s) } }
                }
            }
            if !recent.isEmpty {
                Section("Out in the last 30 days") {
                    ForEach(recent) { s in NavigationLink(value: s) { ReleaseRow(set: s) } }
                }
            }
        }
        .scrollContentBackground(.hidden)
        .background(Theme.background)
        .tabBarClearance()
        .navigationTitle("Release calendar")
    }

    private func monthTitle(_ ym: String) -> String {
        Format.isoDay.date(from: ym + "-01")?.formatted(.dateTime.month(.wide).year()) ?? ym
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
                stat("Brands", Double(index.games.count))
                stat("Sets", Double(index.sets.count))
                stat("Cards", Double(cards))
            }
            if let next { NextRelease(set: next) }
        }
        .padding(.horizontal, 16)
        .padding(.top, 8)
        .background(alignment: .top) {
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

    private func stat(_ label: String, _ value: Double) -> some View {
        VStack(alignment: .leading, spacing: 4) {
            MonoLabel(text: label)
            CountingText(value: value, format: { $0 >= 10_000 ? String(format: "%.0fK", $0 / 1000) : Int($0.rounded()).formatted() })
                .font(.display(28)).monospacedDigit().lineLimit(1).minimumScaleFactor(0.7).displayTrim(28)
        }
        .padding(.horizontal, 14)
        .padding(.vertical, 12)
        .frame(maxWidth: .infinity, alignment: .leading)
        .liquidGlass(in: RoundedRectangle(cornerRadius: 16, style: .continuous))
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
                    Text(set.name.uppercased()).font(.display(24)).lineLimit(2).displayTrim(24).foregroundStyle(.white)
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
                VStack(spacing: 2) {
                    CountingText(value: Double(days), format: { "\(Int($0.rounded()))" })
                        .font(.display(64)).monospacedDigit().foregroundStyle(Theme.lime).displayTrim(64)
                        .shadow(color: Theme.lime.opacity(0.5), radius: 16)
                    MonoLabel(text: days == 1 ? "day" : "days")
                }
            }
            .padding(18)
            .background {
                ZStack {
                    RoundedRectangle(cornerRadius: 22, style: .continuous).fill(Color(hex: 0x070707))
                    if let url = (set.imageUrl ?? set.iconUrl).flatMap(URL.init(string:)) {
                        CachedImage(url: url) { img in img.resizable().scaledToFit() } placeholder: { Color.clear }
                            .frame(width: 180)
                            .opacity(0.18)
                            .frame(maxWidth: .infinity, maxHeight: .infinity, alignment: .trailing)
                            .clipped()
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
    @Environment(CollectionStore.self) private var store

    private var days: Int? {
        guard let d = set.release else { return nil }
        return Calendar.current.dateComponents([.day], from: Calendar.current.startOfDay(for: Date()), to: d).day
    }

    var body: some View {
        VStack(alignment: .leading, spacing: 10) {
            ZStack(alignment: .topLeading) {
                RoundedRectangle(cornerRadius: 16, style: .continuous).fill(Theme.well)
                CachedImage(url: (set.imageUrl ?? set.iconUrl).flatMap(URL.init(string:))) { img in
                    img.resizable().scaledToFit().padding(14)
                } placeholder: {
                    Image(systemName: "square.stack.3d.up").font(.system(size: 28)).foregroundStyle(Theme.lime.opacity(0.7))
                        .frame(maxWidth: .infinity, maxHeight: .infinity)
                }
                if upcoming, let days {
                    SkewTag(text: days <= 0 ? "Out today" : "In \(days) day\(days == 1 ? "" : "s")",
                            color: days <= 7 ? Theme.lime : Theme.planBlue, textColor: days <= 7 ? Theme.ink : .white)
                        .padding(10)
                }
                if upcoming, store.reminders.contains(set.slug) {
                    Image(systemName: "bell.fill").font(.system(size: 11, weight: .bold)).foregroundStyle(Theme.ink)
                        .frame(width: 24, height: 24).background(Circle().fill(Theme.lime))
                        .frame(maxWidth: .infinity, maxHeight: .infinity, alignment: .topTrailing)
                        .padding(8)
                }
            }
            .frame(width: 170, height: 120)
            .overlay(RoundedRectangle(cornerRadius: 16, style: .continuous).strokeBorder(Theme.border))
            VStack(alignment: .leading, spacing: 2) {
                Text(set.name).font(.geist(14, .medium)).lineLimit(1).foregroundStyle(.white)
                Text([set.gameName, set.release?.formatted(.dateTime.month(.abbreviated).day().year())].compactMap { $0 }.joined(separator: " · "))
                    .font(.geist(12)).foregroundStyle(Theme.muted).lineLimit(1)
            }
            .frame(width: 170, alignment: .leading)
        }
    }
}

/// A brand as a tinted card: its logo, name, and how many sets and cards it has.
private struct BrandCard: View {
    var game: ExploreGame
    var tint: Color

    static let tints: [Color] = [Theme.lime, Theme.planPink, Theme.planBlue, Theme.azure]

    var body: some View {
        VStack(alignment: .leading, spacing: 12) {
            CachedImage(url: game.logoUrl.flatMap(URL.init(string:))) { img in img.resizable().scaledToFit() } placeholder: {
                Text(game.name.prefix(1).uppercased()).font(.display(26)).foregroundStyle(tint)
            }
            .frame(height: 40, alignment: .leading)
            .frame(maxWidth: .infinity, alignment: .leading)
            VStack(alignment: .leading, spacing: 3) {
                Text(game.name).font(.geist(15, .semibold)).lineLimit(1).foregroundStyle(.white)
                Text("\(game.sets) sets" + (game.cardCount.map { " · \($0.formatted()) cards" } ?? ""))
                    .font(.geist(12)).foregroundStyle(Theme.muted).monospacedDigit().lineLimit(1).minimumScaleFactor(0.8)
            }
        }
        .padding(14)
        .frame(maxWidth: .infinity, minHeight: 116, alignment: .topLeading)
        .tinted(tint)
    }
}
