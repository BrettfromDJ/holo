import SwiftUI

// Home's themed collections, like a streaming app's rows: "Skyridge holos", "Charizard through
// the years"… Rules over our own catalog, filled on the server (`src/lib/explore/themes.ts`,
// `/api/themes`). Each time the app opens, Home shows many, in a new mix that leans toward what
// you collect and away from what it showed last time. All one look: every card big in a row.

struct MarketTheme: Codable, Identifiable, Hashable {
    var id: String
    var title: String
    var blurb: String
    /// The server's look name (Home now shows every collection as one row style).
    var look: String
    var pokemon: [String]? = nil
    var era: String? = nil
    /// One of this week's new ideas (tagged New).
    var fresh: Bool? = nil
    /// In the launch lineup: comes up more often.
    var featured: Bool? = nil
    /// Cards picked by AI (art themes).
    var curated: Bool? = nil
    var hits: [SearchHit]
}

@Observable
final class ThemesModel {
    // Read once per launch (the view's init runs on every tab switch; @State keeps only the first).
    var all: [MarketTheme] = ThemesModel.launchSaved
    /// The few on Home this time, in order.
    var shown: [MarketTheme] = []
    /// Collection of the Day, at the top of Home: the same all day, a new one tomorrow.
    var daily: MarketTheme?
    /// The server has answered (or failed) at least once this launch: until then, a first open
    /// with nothing saved shows still placeholder rows where the collections go.
    var loaded = false

    /// A new mix each time the app opens (the same while it stays open).
    private static let launchSeed = UInt64.random(in: 1...UInt64.max)
    /// Whether Your next favorite joins this open's mix (about one in three).
    private static let showsNextFavorite = launchSeed % 3 == 0

    @MainActor
    func load(index: ExploreIndex?) async {
        if Demo.isOn {
            all = Self.stand(in: index)
            loaded = true
            return
        }
        defer { loaded = true }
        if let fresh = try? await Backend.shared.api.themes(), !fresh.isEmpty {
            all = fresh
            // Written off the main thread (it's a big file).
            Task.detached(priority: .utility) { Self.saved = fresh }
        } else if all.isEmpty {
            // Nothing from the server yet: themes made from the market lists stand in.
            all = Self.stand(in: index)
        }
    }

    /// Pick this visit's rows: favourites first in the draw (your Pokémon count three times, your
    /// era once more, the launch lineup a little more), and ones shown on the last couple of opens
    /// much less, so the mix keeps moving through every collection.
    @MainActor
    func pick(store: CollectionStore, index: ExploreIndex?, count: Int = 14) {
        let holdings = store.allHoldings
        let favourite = CollectorTaste.favourite(holdings)?.name.lowercased()
        var released: [String: String] = [:]
        for s in index?.sets ?? [] { if let d = s.releaseDate { released[s.name] = d } }
        let era = CollectorTaste.era(holdings, released: released)
        var pool = all.filter { $0.hits.count >= 3 }
        // Collection of the Day: drawn by the date (launch lineup three times as likely).
        var dayRng = SeededRandom(seed: UInt64(Self.dayNumber))
        daily = Self.draw(from: pool, using: &dayRng) { $0.featured == true ? 3 : 1 }
        pool.removeAll { $0.id == daily?.id }
        var rng = SeededRandom(seed: Self.launchSeed)
        let recent = Self.recentAtLaunch
        var out: [MarketTheme] = []
        while out.count < count, !pool.isEmpty {
            guard let chosen = Self.draw(from: pool, using: &rng, weight: { t in
                var w = 1.0
                if let favourite, t.pokemon?.contains(where: { $0.lowercased() == favourite }) == true { w += 2 }
                if let era, t.era == era { w += 0.5 }
                if t.fresh == true { w += 1 }
                if t.featured == true { w += 0.5 }
                if recent.contains(t.id) { w *= 0.15 }
                return w
            }) else { break }
            out.append(chosen)
            pool.removeAll { $0.id == chosen.id }
        }
        // Your next favorite (cards of the Pokémon you collect most) takes the last slot, but only
        // on about one open in three, so it isn't always there.
        if Self.showsNextFavorite, let mine = nextFavorite {
            if out.count >= count { out[out.count - 1] = mine } else { out.append(mine) }
        }
        shown = out
        Self.remember(out.map(\.id))
    }

    /// The collections shown on the last couple of opens (read once, when the app starts).
    private static let recentAtLaunch = Set(UserDefaults.standard.stringArray(forKey: "themes-recent") ?? [])
    /// Last open's alone, to carry into the next open's "recent".
    private static let lastAtLaunch = UserDefaults.standard.stringArray(forKey: "themes-last") ?? []
    private static func remember(_ ids: [String]) {
        UserDefaults.standard.set(ids, forKey: "themes-last")
        UserDefaults.standard.set(Array(Set(ids + lastAtLaunch)), forKey: "themes-recent")
    }

    /// For one of Home's tabs: every collection cut down to that kind of card, keeping those with
    /// enough left (the day's mix first, then the rest), at most 14.
    func filtered(_ f: HomeFilter) -> [MarketTheme] {
        var ordered = shown
        if let daily { ordered.insert(daily, at: 0) }
        let seen = Set(ordered.map(\.id))
        ordered += all.filter { !seen.contains($0.id) }
        var out: [MarketTheme] = []
        for t in ordered {
            var t = t
            t.hits = t.hits.filter(f.fits)
            if t.hits.count >= 4 { out.append(t) }
            if out.count >= 14 { break }
        }
        return out
    }

    /// Your next favorite: cards of the Pokémon you own most of that you don't have yet.
    var nextFavorite: MarketTheme?

    /// From For you's picks, once they're in (swapped into the last slot, not reshuffling the rest).
    @MainActor
    func setNextFavorite(taste: (name: String, count: Int)?, picks: [SearchHit]) {
        guard let taste, picks.count >= 3 else { return }
        let theme = MarketTheme(id: "your-next-favorite", title: "Your next favorite", blurb: "You collect \(taste.name). Here are some you don't have\u{00A0}yet.",
                                look: "fan", pokemon: [taste.name], hits: picks)
        guard nextFavorite?.hits.map(\.id) != theme.hits.map(\.id) else { return }
        nextFavorite = theme
        guard Self.showsNextFavorite else { return }
        if let i = shown.firstIndex(where: { $0.id == theme.id }) { shown[i] = theme }
        else if !shown.isEmpty { shown[shown.count - 1] = theme }
    }

    private static var dayNumber: Int { Int(Date().timeIntervalSince1970 / 86_400) + 1 }

    /// One weighted pick.
    private static func draw(from list: [MarketTheme], using rng: inout SeededRandom, weight: (MarketTheme) -> Double) -> MarketTheme? {
        guard !list.isEmpty else { return nil }
        let weights = list.map(weight)
        var roll = Double.random(in: 0..<weights.reduce(0, +), using: &rng)
        for (t, w) in zip(list, weights) {
            if roll < w { return t }
            roll -= w
        }
        return list.last
    }

    // MARK: Saved on the phone

    private static let launchSaved: [MarketTheme] = saved

    private static var file: URL { FileManager.default.urls(for: .cachesDirectory, in: .userDomainMask)[0].appendingPathComponent("market-themes.json") }

    static var saved: [MarketTheme] {
        get {
            let list = (try? Data(contentsOf: file)).flatMap { try? JSONDecoder().decode([MarketTheme].self, from: $0) } ?? []
            return list.map { t in var t = t; t.hits.removeAll { $0.product.isOversized }; return t }
        }
        set { try? JSONEncoder().encode(newValue).write(to: file, options: .atomic) }
    }

    /// Themes made from Home's own market lists, for the demo and until the server's arrive.
    static func stand(in index: ExploreIndex?) -> [MarketTheme] {
        guard let index else { return [] }
        let trending = index.trending ?? [], eras = index.eras ?? MarketEras()
        var everything: [SearchHit] = trending
        everything += index.today ?? []
        everything += eras.modern
        everything += eras.midEra
        everything += eras.vintage
        var seen = Set<String>()
        let unique = everything.filter { $0.market != nil && seen.insert($0.product.id).inserted }
        var bySet: [String: SearchHit] = [:]
        for h in unique.sorted(by: { ($0.market ?? 0) > ($1.market ?? 0) }) where h.releaseDate != nil {
            let key = h.product.setName ?? h.product.id
            if bySet[key] == nil { bySet[key] = h }
        }
        let timeline = bySet.values.sorted { ($0.releaseDate ?? "") < ($1.releaseDate ?? "") }
        return [
            MarketTheme(id: "stand-grails", title: "Modern grails", blurb: "The priciest modern cards rising this week.", look: "billboard", era: "modern", featured: true,
                        hits: eras.modern.sorted { ($0.market ?? 0) > ($1.market ?? 0) }),
            MarketTheme(id: "stand-vintage", title: "Vintage on the move", blurb: "Wizards-era cards climbing this week.", look: "fan", era: "vintage", hits: eras.vintage),
            MarketTheme(id: "stand-years", title: "Through the years", blurb: "One standout from each set, oldest first.", look: "timeline", hits: timeline),
            MarketTheme(id: "stand-wall", title: "This week's wall", blurb: "Everything rising, side by side.", look: "mosaic", hits: trending),
            MarketTheme(id: "stand-mid", title: "Mid-era spotlight", blurb: "Diamond & Pearl to XY's biggest riser.", look: "spotlight", era: "midEra", hits: eras.midEra),
        ].filter { $0.hits.count >= 3 }
    }
}

/// The same shuffle while the app stays open.
struct SeededRandom: RandomNumberGenerator {
    var state: UInt64
    init(seed: UInt64) { state = seed }
    mutating func next() -> UInt64 {
        state &+= 0x9E3779B97F4A7C15
        var z = state
        z = (z ^ (z >> 30)) &* 0xBF58476D1CE4E5B9
        z = (z ^ (z >> 27)) &* 0x94D049BB133111EB
        return z ^ (z >> 31)
    }
}

// MARK: A theme on Home

/// One collection on Home, like a streaming app's row: its title, then every card in it big in a
/// row you swipe (no separate page). Every row looks the same.
struct ThemeSection: View {
    var theme: MarketTheme

    var body: some View {
        VStack(alignment: .leading, spacing: 12) {
            RowTitle(title: theme.title, fresh: theme.fresh == true)
                .padding(.horizontal, 16)
            PosterRow(hits: theme.hits)
                .cardSequence(theme.hits.map(\.product.id))
        }
        .reveal()
    }
}

/// A row's title: no line under it, no arrow (the row itself holds every card).
struct RowTitle: View {
    var title: String
    var fresh = false

    var body: some View {
        HStack(spacing: 8) {
            Text(title).font(.display(22)).tracking(22 * -0.03).foregroundStyle(.white).lineLimit(1).minimumScaleFactor(0.8).displayTrim(22)
            if fresh { SkewTag(text: "New") }
            Spacer(minLength: 0)
        }
        .contentShape(Rectangle())
    }
}

private func price(_ hit: SearchHit) -> String { Format.money(hit.market) }


/// Every card, big, all one size, in a row you swipe; each with its price on a small tag.
private struct PosterRow: View {
    var hits: [SearchHit]

    var body: some View {
        ScrollView(.horizontal, showsIndicators: false) {
            LazyHStack(spacing: 10) {
                ForEach(hits) { hit in
                    MarketLink(hit: hit) { Poster(product: hit.pictured, price: hit.market) }
                }
            }
            .padding(.horizontal, 16)
        }
        .frame(height: Poster.height)
    }
}

/// One card in a row: big art with its price on a small Liquid Glass pill at the bottom, the
/// card's art blurred behind it (frosted on older iOS).
struct Poster: View {
    var product: Product
    var price: Double?
    /// A move to show beside the price (Top 10's rise), as a stored percent (12.5 = +12.5%).
    var change: Double? = nil
    static let width: CGFloat = 150
    static let height: CGFloat = 209

    var body: some View {
        ProductImage(product: product, cornerRadius: 8)
            .frame(width: Self.width, height: Self.height)
            // The card page grows out of this picture (on Home).
            .cardZoomSource(product.id)
            .overlay(alignment: .bottomLeading) {
                if let price {
                    HStack(spacing: 6) {
                        Text(Format.money(price)).foregroundStyle(.white)
                        if let change {
                            Text(Format.signedPercent(change / 100)).foregroundStyle(change >= 0 ? Theme.lime : Theme.planPink)
                        }
                    }
                    .font(.geist(13, .semibold)).monospacedDigit().lineLimit(1)
                    .shadow(color: .black.opacity(0.35), radius: 2, y: 1)
                        .padding(.horizontal, 9).padding(.vertical, 5)
                        .pillOnArt(in: Capsule())
                        .padding(8)
                }
            }
    }
}

// MARK: Your lists, at the bottom of Home

/// Each of your lists as a row like the collections above, every card in it.
struct HomeListRows: View {
    @Environment(CollectionStore.self) private var store
    @Environment(GroupsStore.self) private var groups

    var body: some View {
        let lists = groups.shelves.filter { !$0.product_ids.isEmpty }
        ForEach(lists) { list in
            let ids = list.product_ids
            VStack(alignment: .leading, spacing: 12) {
                RowTitle(title: list.name)
                    .padding(.horizontal, 16)
                ScrollView(.horizontal, showsIndicators: false) {
                    LazyHStack(spacing: 10) {
                        ForEach(ids, id: \.self) { id in
                            if let product = store.products[id] ?? groups.extraProducts[id] {
                                CardLink(productId: id, product: product) {
                                    Poster(product: product, price: ListItemInfo(id, store: store, groups: groups).market)
                                }
                            }
                        }
                    }
                    .padding(.horizontal, 16)
                }
                .frame(height: Poster.height)
                .cardSequence(ids)
            }
            .reveal()
        }
        .task(id: groups.shelves.count) {
            await groups.loadExtras(groups.shelves.flatMap(\.product_ids), known: store.products)
        }
    }
}

// MARK: Collection of the Day

/// Collection of the Day: the day's collection as the same row as the others, its title led by
/// "Today's discovery".
struct DailyDiscovery: View {
    var theme: MarketTheme

    var body: some View {
        VStack(alignment: .leading, spacing: 12) {
            VStack(alignment: .leading, spacing: 4) {
                MonoLabel(text: "Today's discovery").foregroundStyle(Theme.lime)
                RowTitle(title: theme.title)
            }
            .padding(.horizontal, 16)
            PosterRow(hits: theme.hits)
                .cardSequence(theme.hits.map(\.product.id))
        }
    }
}

// MARK: A theme's own page

struct ThemePage: View {
    var theme: MarketTheme

    var body: some View {
        ScrollView {
            VStack(alignment: .leading, spacing: 20) {
                VStack(alignment: .leading, spacing: 8) {
                    if theme.fresh == true { SkewTag(text: "New this week") }
                    Text(theme.title.noWidow).font(.display(34)).tracking(-1.1).foregroundStyle(.white)
                    Text(theme.blurb.noWidow).font(.geist(15)).foregroundStyle(Theme.muted)
                    Text("\(theme.hits.count) cards").font(.mono(11)).foregroundStyle(Theme.subtle).padding(.top, 2)
                }
                LazyVGrid(columns: Array(repeating: GridItem(.flexible(), spacing: 12), count: 3), alignment: .leading, spacing: 18) {
                    ForEach(theme.hits) { hit in
                        MarketLink(hit: hit) {
                            VStack(alignment: .leading, spacing: 5) {
                                ProductImage(product: hit.pictured, cornerRadius: 5).aspectRatio(63 / 88, contentMode: .fit)
                                Text(hit.product.name).font(.geist(12, .medium)).foregroundStyle(.white).lineLimit(1)
                                Text(hit.product.setName ?? "").font(.geist(11)).foregroundStyle(Theme.muted).lineLimit(1)
                                Text(price(hit)).font(.geist(13, .semibold)).monospacedDigit().foregroundStyle(.white)
                            }
                            .contentShape(Rectangle())
                        }
                    }
                }
                .cardSequence(theme.hits.map(\.product.id))
            }
            .padding(.horizontal, 16)
            .padding(.top, 8)
            .padding(.bottom, 40)
            // The collection's top card, blown up and blurred behind the title, fading into the page.
            .background(alignment: .top) {
                if let url = theme.hits.first?.pictured.imageURL { ArtBackdrop(url: url, blur: 40) }
            }
        }
        .background(Theme.background)
        .tabBarClearance()
        .navigationBarTitleDisplayMode(.inline)
    }
}

// MARK: Home's tabs

/// Home's tabs: All, or only one era's cards in every row (same cut-offs as `MarketEras`).
enum HomeFilter: String, CaseIterable, Hashable {
    case all = "All", modern = "Modern", midEra = "Mid era", vintage = "Vintage"

    func fits(_ hit: SearchHit) -> Bool {
        switch self {
        case .all: return true
        case .modern: return MarketEras.era(of: hit.releaseDate) == "modern"
        case .midEra: return MarketEras.era(of: hit.releaseDate) == "midEra"
        case .vintage: return MarketEras.era(of: hit.releaseDate) == "vintage"
        }
    }
}
