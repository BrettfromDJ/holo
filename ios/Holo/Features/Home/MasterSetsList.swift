import SwiftUI

/// Opens one master set's page (pushed on Home).
struct MasterSetRoute: Hashable {
    var id: String
    var name: String
}

/// Master Sets: a title, how many sets you've started and your
/// closest, three glass tiles, then every set as a full-width card with its art and progress. Your sets by default; switch to every set in the catalog. Tap one to see
/// every card in it.
struct MasterSetsView: View {
    @Environment(CollectionStore.self) private var store
    @State private var cache = MasterSetsCache.shared
    @State private var index: [ExploreSet] = []
    /// The catalog's set list has been asked for (loaded, or failed: then sets show your card).
    @State private var indexTried = false
    @State private var scope = Scope.mine
    @State private var sort = Sort.progress
    /// The search, handed over by the field a moment after typing stops (so typing doesn't
    /// rebuild the deck on every key).
    @State private var query = ""
    /// The search field, opened from the search icon at the top right.
    @State private var searching = false
    /// The brand shown (a game's slug from the catalog); Pokémon to start, remembered after.
    @AppStorage("master-sets-brand") private var brand = "pokemon"

    enum Scope: String, CaseIterable { case mine = "Your sets", all = "All sets" }
    enum Sort: String, CaseIterable { case progress = "Most complete", value = "Most valuable", newest = "Newest", name = "Name" }

    /// A set on the page: the catalog's entry (for art and release date) if found, and your progress.
    struct Row: Identifiable {
        var id: String
        var name: String
        var art: ExploreSet?
        var holdings: [HoldingView]
        var owned: Int
        var total: Int?
        var value: Double
        var ratio: Double? { total.map { $0 > 0 ? Double(owned) / Double($0) : 0 } }
    }

    /// Your sets in the chosen brand. A set the catalog doesn't know (a demo set, or before the
    /// list arrives) counts as Pokémon.
    private var owned: [MasterSetDetailView.OwnedSet] {
        memo.owned(store.holdings, index: index, brand: brand)
    }

    /// Remembers the catalog lookups and your sets, so a search (or any redraw) only filters;
    /// rebuilding them for thousands of sets on every keystroke froze the page.
    @State private var memo = MasterSetsMemo()

    /// Starts downloading the banners of your sets right away (the ones on screen first), at the
    /// size the page shows them, so they're there by the time each card is drawn.
    private func prefetchBanners() {
        let bySlug = Dictionary(index.map { ($0.slug, $0) }, uniquingKeysWith: { a, _ in a })
        let byName = Dictionary(index.map { ($0.name.lowercased(), $0) }, uniquingKeysWith: { a, _ in a })
        let urls = owned.compactMap { s in (bySlug[s.id] ?? byName[s.name.lowercased()])?.iconUrl.flatMap(URL.init(string:)) }
        for url in urls.prefix(12) where ImageCache.shared.cached(url, maxPixel: 600) == nil {
            Task.detached(priority: .userInitiated) { _ = await ImageCache.shared.load(url, maxPixel: 600) }
        }
    }

    /// Every brand in the catalog, Pokémon first, then by how many sets each has.
    private var brands: [(slug: String, name: String)] {
        var counts: [String: (name: String, n: Int)] = ["pokemon": ("Pokémon", 0)]
        for s in index { counts[s.gameSlug, default: (s.gameName, 0)].n += 1 }
        return counts.sorted { a, b in
            if a.key == "pokemon" { return true }
            if b.key == "pokemon" { return false }
            return a.value.n > b.value.n
        }.map { ($0.key, $0.value.name) }
    }

    private func rows(_ owned: [MasterSetDetailView.OwnedSet]) -> [Row] {
        let (bySlug, byName) = memo.lookups(index)
        func row(_ s: MasterSetDetailView.OwnedSet) -> Row {
            let list = cache.checklists[s.id]
            let ids = Set(s.holdings.map(\.identity.productId))
            let have = list.map { l in ids.intersection(l.map(\.product.id)).count } ?? ids.count
            return Row(id: s.id, name: s.name, art: bySlug[s.id] ?? byName[s.name.lowercased()], holdings: s.holdings,
                       owned: have, total: list?.count, value: s.holdings.reduce(0) { $0 + ($1.value ?? 0) })
        }
        var rows = owned.map(row)
        if scope == .all {
            let mine = Set(rows.map(\.id))
            let mineNames = Set(rows.map { $0.name.lowercased() })
            rows += index.filter { $0.loaded && $0.gameSlug == brand && !mine.contains($0.slug) && !mineNames.contains($0.name.lowercased()) }
                .map { Row(id: $0.slug, name: $0.name, art: $0, holdings: [], owned: 0, total: nil, value: 0) }
        }
        let q = query.trimmingCharacters(in: .whitespaces).lowercased()
        if !q.isEmpty { rows = rows.filter { $0.name.lowercased().contains(q) } }
        switch sort {
        case .progress: return rows.sorted { ($0.ratio ?? -1, $0.owned) > ($1.ratio ?? -1, $1.owned) }
        case .value: return rows.sorted { $0.value > $1.value }
        case .newest: return rows.sorted { ($0.art?.releaseDate ?? "") > ($1.art?.releaseDate ?? "") }
        case .name: return rows.sorted { $0.name < $1.name }
        }
    }

    var body: some View {
        let owned = self.owned
        let rows = self.rows(owned)
        ScrollView {
            VStack(alignment: .leading, spacing: 24) {
                header(owned, rows: rows)
                // The brand and Your / All stay put even when this brand has none of your sets,
                // so you can always switch back (they used to vanish behind the empty message).
                controls
                if owned.isEmpty, scope == .mine {
                    EmptyPage(title: "No \(brandName) sets yet", line: "Add a few cards and your sets appear here.", action: "Scan a card",
                              onAction: { Router.shared.scanRequest += 1 }, link: "Browse all sets", onLink: { scope = .all }, symbol: "square.grid.3x3")
                        // Centred in the room left under the titles and chips.
                        .containerRelativeFrame(.vertical, alignment: .center) { h, _ in h * 0.6 }
                } else {
                    // Every set as a tile, two across, like Explore's brand page: the set's banner art,
                    // then its name and how far along you are. Tap one to open the set.
                    LazyVGrid(columns: [GridItem(.flexible(), spacing: 14, alignment: .top), GridItem(.flexible(), spacing: 14, alignment: .top)],
                              alignment: .leading, spacing: 20) {
                        ForEach(rows) { r in
                            NavigationLink(value: MasterSetRoute(id: r.id, name: r.name)) { MasterSetTile(row: r, catalogReady: indexTried) }
                                .buttonStyle(.plain)
                        }
                    }
                    .environment(\.imageFadesIn, false)
                    // Results swap in place as you type (tiles don't fly about).
                    .animation(nil, value: query)
                    if rows.isEmpty {
                        Text("Nothing matches.").font(.geist(15)).foregroundStyle(Theme.muted).frame(maxWidth: .infinity).padding(.vertical, 30)
                    }
                }
            }
            .padding(.horizontal, 16)
            .padding(.bottom, 120)
        }
        .background(Theme.background)
        .imageMaxPixel(600)
        .replaysAnimations()
        .scrollDismissesKeyboard(.immediately)
        .navigationBarTitleDisplayMode(.inline)
        // The title is in the page (big, with the card fan), so the bar stays clear.
        .toolbarBackground(.hidden, for: .navigationBar)
        // The page's name in the bar; the big titles are the games.
        .pageTitle("Master Sets")
        // Search sits behind an icon at the top right; the field opens under the stats.
        .toolbar {
            ToolbarItem(placement: .topBarTrailing) {
                Button {
                    Haptics.tap()
                    withAnimation(.easeInOut(duration: 0.18)) { searching.toggle() }
                    if !searching { query = "" }
                } label: {
                    Image(systemName: searching ? "xmark" : "magnifyingglass")
                }
                .accessibilityLabel(searching ? "Close search" : "Search sets")
            }
        }
        .clearTopEdge()
        .task {
            // The set list saved last time first (art starts loading at once), then the fresh one.
            if index.isEmpty {
                let saved = await Task.detached(priority: .userInitiated) { SavedSets.load() }.value
                if !saved.isEmpty { index = saved; indexTried = true; prefetchBanners() }
            }
            if let i = try? await Backend.shared.api.exploreIndex() { index = i.sets; prefetchBanners() }
            indexTried = true
        }
        .task(id: owned.map(\.id).joined(separator: ",")) { await MasterSetDetailView.load(owned, store: store) }
    }

    // MARK: Top

    /// The games as big titles (no totals line: fewer layers above the sets).
    /// The search field takes the game titles' place (a quick cross-fade, same height), so
    /// nothing below moves when search opens or closes; the top-right ✕ closes it.
    private func header(_ owned: [MasterSetDetailView.OwnedSet], rows all: [Row]) -> some View {
        ZStack(alignment: .leading) {
            if searching {
                SettledSearchField(prompt: "Search \(brandName) sets", settled: $query, delay: 0.3, autoFocus: true)
                    .transition(.opacity)
            } else {
                gameTitles.transition(.opacity)
            }
        }
        .frame(height: 48)
        .padding(.top, 4)
    }

    private var controls: some View {
        VStack(alignment: .leading, spacing: 12) {
            // One row: Your sets / All sets, and sort at the end, all the same height (the brand
            // sits by the title).
            HStack(spacing: 8) {
                ChipPicker(options: Scope.allCases.map { ($0, $0.rawValue) }, selection: $scope)
                    .fixedSize()
                Spacer(minLength: 0)
                // Nothing to sort on an empty page.
                if !(scope == .mine && owned.isEmpty) {
                Menu {
                    Picker("Sort", selection: $sort) {
                        ForEach(Sort.allCases, id: \.self) { Text($0.rawValue).tag($0) }
                    }
                } label: {
                    Image(systemName: "arrow.up.arrow.down").font(.system(size: 15, weight: .semibold)).foregroundStyle(.white)
                        .frame(width: 38, height: 38)
                        .contentShape(Circle())
                }
                .menuStyle(.button)
                .buttonStyle(.plain)
                .background { Color.clear.liquidGlass(in: Circle()).allowsHitTesting(false) }
                .accessibilityLabel("Sort")
                }
            }
        }
    }

    private var brandName: String { Self.shortName(brands.first { $0.slug == brand }?.name ?? "Pokémon") }

    /// "Magic: The Gathering" → "Magic", "Disney Lorcana" → "Lorcana", "One Piece Card Game" →
    /// "One Piece".
    static func shortName(_ name: String) -> String {
        // The catalog's names aren't consistent ("YuGiOh", "Pokemon Japan"): the usual ones by hand.
        let key = name.lowercased().filter { $0.isLetter }
        let known: [String: String] = [
            "pokemon": "Pokémon", "pokémon": "Pokémon", "pokemonjapan": "Pokémon Japan", "pokémonjapan": "Pokémon Japan",
            "yugioh": "Yu-Gi-Oh!", "magicthegathering": "Magic", "onepiececardgame": "One Piece", "onepiece": "One Piece",
            "disneylorcana": "Lorcana", "lorcana": "Lorcana", "dragonballsuperfusionworld": "Dragon Ball", "fleshandblood": "Flesh and Blood",
            "digimoncardgame": "Digimon", "starwarsunlimited": "Star Wars", "weissschwarz": "Weiss Schwarz",
        ]
        if let k = known[key] { return k }
        var n = name
        for cut in [": The Gathering", " Trading Card Game", " Card Game", " TCG", " CCG"] {
            if let r = n.range(of: cut, options: [.caseInsensitive, .backwards]) { n.removeSubrange(r) }
        }
        if n.hasPrefix("Disney ") { n.removeFirst(7) }
        return n.trimmingCharacters(in: .whitespaces)
    }

    private var gameTitles: some View {
        ScrollViewReader { proxy in
            ScrollView(.horizontal, showsIndicators: false) {
                HStack(alignment: .firstTextBaseline, spacing: 20) {
                    ForEach(brands, id: \.slug) { b in
                        let on = b.slug == brand
                        Button { if !on { Haptics.tap(); brand = b.slug } } label: {
                            Text(Self.shortName(b.name)).font(.display(32)).tracking(32 * -0.03)
                                .foregroundStyle(on ? Color.white : Theme.subtle)
                                .displayTrim(32)
                                .fixedSize()
                                .contentShape(Rectangle())
                        }
                        .buttonStyle(.plain)
                        .accessibilityAddTraits(on ? .isSelected : [])
                        .id(b.slug)
                    }
                }
                .padding(.trailing, 44)
            }
            .fadeTrailingEdge()
            .sensoryFeedback(.selection, trigger: brand)
            // The game you're on is always in view (the list of games arrives after the page).
            .task(id: brands.map(\.slug).joined()) { proxy.scrollTo(brand, anchor: .leading) }
            .onChange(of: brand) { _, b in withAnimation(.snappy) { proxy.scrollTo(b, anchor: .center) } }
        }
    }

}

/// One set as a full-width card in its own light: the set's banner art on the right, fading into
/// the card; the name, how many of how many, a lime progress bar and the % on the left. A finished
/// set is lit lime with a Complete tag.
struct SetBannerRow: View {
    var row: MasterSetsView.Row
    /// The catalog's set list has arrived. Until then the art stays empty rather than showing
    /// your card in its place and swapping it for the banner a moment later.
    var catalogReady = true
    static let height: CGFloat = 132

    private var isComplete: Bool {
        guard let total = row.total, total > 0, !row.holdings.isEmpty else { return false }
        return row.owned >= total
    }

    var body: some View {
        let shape = RoundedRectangle(cornerRadius: 26, style: .continuous)
        let started = !row.holdings.isEmpty
        HStack(alignment: .center, spacing: 0) {
            VStack(alignment: .leading, spacing: 6) {
                if isComplete { SkewTag(text: "Complete", icon: "checkmark") }
                Text(row.name).font(.display(21)).tracking(-0.5).lineLimit(2).minimumScaleFactor(0.8)
                    .fixedSize(horizontal: false, vertical: true)
                // "40 of 208 cards · 19%": the % beside the count, clear of the artwork. Under 10%
                // only the count ("2 of 208 cards"; "1%" says little).
                HStack(spacing: 6) {
                    Text(subtitle).font(.geist(13)).monospacedDigit().foregroundStyle(Theme.muted).lineLimit(1)
                    if let ratio = row.ratio, started, ratio >= 0.1 {
                        Text("·").font(.geist(13)).foregroundStyle(Theme.muted)
                        Text("\(Int((ratio * 100).rounded()))%").font(.geist(13, .semibold)).monospacedDigit()
                            .foregroundStyle(Theme.lime)
                    }
                }
                if let ratio = row.ratio, started {
                    GrowBar(fraction: ratio, color: Theme.lime, height: 5, gradient: false)
                        .padding(.top, 4)
                }
            }
            .frame(maxWidth: .infinity, alignment: .leading)
            Spacer(minLength: 120)
        }
        .padding(.horizontal, 20)
        .frame(height: Self.height)
        .foregroundStyle(.white)
        .background {
            ZStack(alignment: .trailing) {
                SetGlow(id: row.id)
                // The set's art on the right, fading into the card toward the text.
                art
                    .frame(width: 230)
                    .clipped()
                    .mask(LinearGradient(stops: [.init(color: .clear, location: 0), .init(color: .black.opacity(0.9), location: 0.45), .init(color: .black, location: 1)],
                                         startPoint: .leading, endPoint: .trailing))
                if isComplete {
                    RadialGradient(colors: [Theme.lime.opacity(0.28), .clear], center: .topLeading, startRadius: 0, endRadius: 260)
                }
            }
        }
        .clipShape(shape)
        // A fine edge in the set's own color, brightest at the top left and fading round the card
        // (lime when finished). No wide inner band: it read as a thick stroke.
        .overlay {
            let accent = isComplete ? Theme.lime : SetGlow.accent(for: row.id)
            shape.strokeBorder(LinearGradient(colors: [accent.opacity(0.6), accent.opacity(0.18), .white.opacity(0.06), accent.opacity(0.14)],
                                              startPoint: .topLeading, endPoint: .bottomTrailing), lineWidth: 1)
                .allowsHitTesting(false)
        }
        .contentShape(shape)
    }

    private var subtitle: String {
        if let total = row.total { return "\(row.owned) of \(total) cards" }
        if row.holdings.isEmpty { return row.art?.release?.formatted(.dateTime.month(.abbreviated).year()) ?? "Not started" }
        return "\(row.owned) card\(row.owned == 1 ? "" : "s")"
    }

    @ViewBuilder private var art: some View {
        if let banner = row.art?.iconUrl.flatMap(URL.init(string:)) {
            CachedImage(url: banner) { img in img.resizable().scaledToFill() } placeholder: { Color.clear }
                .overlay { SetLogoOverlay(url: row.art?.logoUrl) }
                .environment(\.imageFadesIn, false)
        } else if catalogReady, let cover = row.holdings.max(by: { ($0.value ?? 0) < ($1.value ?? 0) }) {
            // No banner (a demo set, or one the catalog lacks): your best card from it, tilted.
            HoldingArt(product: cover.product, identity: cover.identity, cornerRadius: 5, caption: false)
                .frame(width: 78, height: 108)
                .rotationEffect(.degrees(8))
                .offset(x: -24, y: 6)
                .frame(maxWidth: .infinity, alignment: .trailing)
        } else if let sample = row.art?.imageUrl.flatMap(URL.init(string:)) {
            CachedImage(url: sample) { img in img.resizable().scaledToFit() } placeholder: { Color.clear }
                .padding(18)
        } else {
            Color.clear
        }
    }
}

/// A glass tile with a small icon beside its label, and the figure under them.
private struct IconStat: View {
    var icon: String
    var label: String
    var value: String

    var body: some View {
        VStack(alignment: .leading, spacing: 8) {
            HStack(spacing: 6) {
                Image(systemName: icon).font(.system(size: 13, weight: .medium)).foregroundStyle(.white)
                MonoLabel(text: label).lineLimit(1).minimumScaleFactor(0.6)
            }
            Text(value).font(.display(22)).tracking(-0.6).monospacedDigit().lineLimit(1).minimumScaleFactor(0.5)
        }
        .padding(.horizontal, 12)
        .padding(.vertical, 12)
        .frame(maxWidth: .infinity, alignment: .leading)
        .liquidGlass(in: RoundedRectangle(cornerRadius: 18, style: .continuous))
    }
}

/// Master Sets' remembered work: the catalog lookups (rebuilt only when the set list changes)
/// and your sets in the chosen brand (only when your holdings, the list or the brand change).
/// A plain object, so filling it while drawing never asks for another redraw.
final class MasterSetsMemo {
    private var indexCount = -1
    private var bySlug: [String: ExploreSet] = [:]
    private var byName: [String: ExploreSet] = [:]
    private var ownedKey: String?
    private var ownedValue: [MasterSetDetailView.OwnedSet] = []

    func lookups(_ index: [ExploreSet]) -> ([String: ExploreSet], [String: ExploreSet]) {
        if index.count != indexCount {
            indexCount = index.count
            bySlug = Dictionary(index.map { ($0.slug, $0) }, uniquingKeysWith: { a, _ in a })
            byName = Dictionary(index.map { ($0.name.lowercased(), $0) }, uniquingKeysWith: { a, _ in a })
            ownedKey = nil
        }
        return (bySlug, byName)
    }

    func owned(_ holdings: [HoldingView], index: [ExploreSet], brand: String) -> [MasterSetDetailView.OwnedSet] {
        let (slugs, names) = lookups(index)
        var worth = 0.0
        for h in holdings { worth += h.value ?? 0 }
        let key = "\(brand)|\(holdings.count)|\(worth)|\(index.count)"
        if key == ownedKey { return ownedValue }
        ownedKey = key
        ownedValue = MasterSetDetailView.ownedSets(holdings).filter { s in
            ((slugs[s.id] ?? names[s.name.lowercased()])?.gameSlug ?? "pokemon") == brand
        }
        return ownedValue
    }
}

/// A set on Master Sets as a grid tile, the same look as Explore's brand page (`SetTile`): the
/// set's banner art in a rounded 3:2 frame, then its name and "8 of 102 · 8%" with a thin lime
/// bar. A finished set gets a lime Complete tag on its art.
struct MasterSetTile: View {
    var row: MasterSetsView.Row
    var catalogReady = true

    private var started: Bool { !row.holdings.isEmpty }
    private var isComplete: Bool {
        guard let total = row.total, total > 0, started else { return false }
        return row.owned >= total
    }

    var body: some View {
        let shape = RoundedRectangle(cornerRadius: 16, style: .continuous)
        VStack(alignment: .leading, spacing: 10) {
            art
                .aspectRatio(3.0 / 2.0, contentMode: .fit)
                .overlay(alignment: .topLeading) {
                    if isComplete { SkewTag(text: "Complete", icon: "checkmark").padding(10) }
                }
                .clipShape(shape)
                .overlay(shape.strokeBorder(isComplete ? Theme.lime.opacity(0.6) : Theme.border))
            VStack(alignment: .leading, spacing: 4) {
                Text(row.name).font(.geist(14, .medium)).lineLimit(1).foregroundStyle(.white)
                HStack(spacing: 5) {
                    Text(subtitle).font(.geist(12)).monospacedDigit().foregroundStyle(Theme.muted).lineLimit(1)
                    if let ratio = row.ratio, started, ratio >= 0.01 {
                        Text("· \(Int((ratio * 100).rounded()))%").font(.geist(12, .semibold)).monospacedDigit().foregroundStyle(Theme.lime)
                    }
                }
                if let ratio = row.ratio, started {
                    GrowBar(fraction: ratio, color: Theme.lime, height: 3, gradient: false).padding(.top, 3)
                }
            }
            .frame(maxWidth: .infinity, alignment: .leading)
        }
    }

    private var subtitle: String {
        if let total = row.total { return started ? "\(row.owned) of \(total)" : "\(total) cards" }
        if !started { return row.art?.release?.formatted(.dateTime.month(.abbreviated).year()) ?? "Not started" }
        return "\(row.owned) card\(row.owned == 1 ? "" : "s")"
    }

    @ViewBuilder private var art: some View {
        if let set = row.art {
            SetArt(set: set)
        } else {
            // No catalog entry (a demo set): your best card from it on the set's glow.
            ZStack {
                SetGlow(id: row.id)
                if catalogReady, let cover = row.holdings.max(by: { ($0.value ?? 0) < ($1.value ?? 0) }) {
                    HoldingArt(product: cover.product, identity: cover.identity, cornerRadius: 4, caption: false)
                        .frame(width: 58, height: 80)
                        .rotationEffect(.degrees(6))
                }
            }
        }
    }
}
