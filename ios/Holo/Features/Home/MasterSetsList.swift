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
                if owned.isEmpty, scope == .mine {
                    EmptyPage(title: "No sets yet", line: "Add a few cards and your sets appear here.", action: "Scan a card",
                              onAction: { Router.shared.scanRequest += 1 }, link: "Browse all sets", onLink: { scope = .all })
                } else {
                    controls
                    // Every set as a full-width card in its own light. Tap one to open the set.
                    LazyVStack(spacing: 14) {
                        ForEach(rows) { r in
                            NavigationLink(value: MasterSetRoute(id: r.id, name: r.name)) { SetBannerRow(row: r, catalogReady: indexTried) }
                                .buttonStyle(.plain)
                        }
                    }
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

    private func header(_ owned: [MasterSetDetailView.OwnedSet], rows all: [Row]) -> some View {
        let rows = all.filter { !$0.holdings.isEmpty }
        let complete = rows.filter { ($0.ratio ?? 0) >= 1 }.count
        let best = rows.filter { $0.ratio != nil }.max { ($0.ratio ?? 0) < ($1.ratio ?? 0) }
        let cards = owned.reduce(0) { $0 + Set($1.holdings.map(\.identity.productId)).count }
        let worth = owned.reduce(0) { $0 + $1.holdings.reduce(0) { $0 + ($1.value ?? 0) } }
        return VStack(alignment: .leading, spacing: 16) {
            // The title in the page.
            Text("Master Sets").font(.display(40)).tracking(-1.4).displayTrim(40)
                .padding(.top, 4)
            // How many sets you've started, and the one you're closest to finishing.
            // Two halves on one line: the count on the left, your closest set (a lime ring with
            // its % inside, and its name) on the right, split by a thin rule.
            HStack(alignment: .center, spacing: 16) {
                VStack(alignment: .leading, spacing: 2) {
                    CountingText(value: Double(owned.count), format: { "\(Int($0.rounded()))" })
                        .font(.display(48)).tracking(-1.8).monospacedDigit().displayTrim(48)
                    Text(owned.count == 1 ? "Set started" : "Sets started").font(.geist(13)).foregroundStyle(Theme.muted)
                }
                .fixedSize()
                Rectangle().fill(Color.white.opacity(0.12)).frame(width: 1, height: 60)
                if let best, let ratio = best.ratio {
                    HStack(spacing: 12) {
                        ZStack {
                            Circle().stroke(Color.white.opacity(0.14), lineWidth: 5)
                            Circle().trim(from: 0, to: max(0.02, min(ratio, 1)))
                                .stroke(Theme.lime, style: StrokeStyle(lineWidth: 5, lineCap: .round))
                                .rotationEffect(.degrees(-90))
                            Text("\(Int((ratio * 100).rounded()))%").font(.geist(13, .semibold)).monospacedDigit()
                        }
                        .frame(width: 56, height: 56)
                        VStack(alignment: .leading, spacing: 3) {
                            MonoLabel(text: "Closest")
                            Text(best.name).font(.geist(14, .semibold)).lineLimit(2).fixedSize(horizontal: false, vertical: true)
                        }
                    }
                    .frame(maxWidth: .infinity, alignment: .leading)
                } else {
                    Text("Add cards from a set to see how close you\u{00A0}are.").font(.geist(13)).foregroundStyle(Theme.muted)
                        .frame(maxWidth: .infinity, alignment: .leading)
                }
            }
            .padding(18)
            .frame(maxWidth: .infinity, alignment: .leading)
            .liquidGlass(in: RoundedRectangle(cornerRadius: 24, style: .continuous))
            .overlay(RoundedRectangle(cornerRadius: 24, style: .continuous).strokeBorder(Theme.lime.opacity(0.25)))
            HStack(spacing: 8) {
                IconStat(icon: "rectangle.portrait.on.rectangle.portrait", label: "Cards", value: "\(cards)")
                IconStat(icon: "checkmark.circle", label: "Complete", value: "\(complete)")
                IconStat(icon: "chart.line.uptrend.xyaxis", label: "Worth", value: Format.money(worth))
            }
        }
        .background(alignment: .top) {
            DotBackdrop().padding(.horizontal, -16).padding(.top, -160).padding(.bottom, -40)
        }
    }

    private var controls: some View {
        VStack(alignment: .leading, spacing: 12) {
            HStack(spacing: 10) {
                SettledSearchField(prompt: "Search sets", settled: $query, delay: 0.3)
                Menu {
                    Picker("Sort", selection: $sort) {
                        ForEach(Sort.allCases, id: \.self) { Text($0.rawValue).tag($0) }
                    }
                } label: { Image(systemName: "arrow.up.arrow.down") }
                    .menuStyle(.button)
                    .buttonStyle(IconButton3D(size: 46))
            }
            HStack(spacing: 10) {
                ChipPicker(options: Scope.allCases.map { ($0, $0.rawValue) }, selection: $scope)
                Spacer(minLength: 0)
                brandMenu
            }
        }
    }

    /// Which brand's sets to show: a glass pill with the brand's name.
    private var brandMenu: some View {
        let list = brands
        let name = list.first { $0.slug == brand }?.name ?? "Pokémon"
        return Menu {
            Picker("Brand", selection: $brand) {
                ForEach(list, id: \.slug) { Text($0.name).tag($0.slug) }
            }
        } label: {
            HStack(spacing: 6) {
                Text(name).font(.geist(14, .semibold)).lineLimit(1)
                Image(systemName: "chevron.down").font(.system(size: 11, weight: .semibold))
            }
            .foregroundStyle(.white)
            .padding(.horizontal, 16)
            .frame(height: 44)
            .contentShape(Capsule())
        }
        .menuStyle(.button)
        .buttonStyle(.plain)
        .background { Color.clear.liquidGlass(in: Capsule()).allowsHitTesting(false) }
        .accessibilityLabel("Brand: \(name)")
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
                // "2 of 208 cards · 1%": the % beside the count, clear of the artwork.
                HStack(spacing: 6) {
                    Text(subtitle).font(.geist(13)).monospacedDigit().foregroundStyle(Theme.muted).lineLimit(1)
                    if let ratio = row.ratio, started {
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
        // A glowing edge in the set's own color, bright at the top left and fading round the card
        // (lime when finished); the glow is the edge's still shadow.
        .overlay {
            let accent = isComplete ? Theme.lime : SetGlow.accent(for: row.id)
            ZStack {
                // The glow as a wide faint band inside the edge (no shadow, cheap while scrolling).
                shape.strokeBorder(LinearGradient(colors: [accent.opacity(0.28), accent.opacity(0.08), .clear, accent.opacity(0.08)],
                                                  startPoint: .topLeading, endPoint: .bottomTrailing), lineWidth: 8)
                shape.strokeBorder(LinearGradient(colors: [accent.opacity(0.95), accent.opacity(0.35), .white.opacity(0.08), accent.opacity(0.3)],
                                                  startPoint: .topLeading, endPoint: .bottomTrailing), lineWidth: 1.5)
            }
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
