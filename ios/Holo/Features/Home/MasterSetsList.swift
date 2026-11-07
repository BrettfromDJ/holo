import SwiftUI

/// Opens one master set's page (pushed on Home).
struct MasterSetRoute: Hashable {
    var id: String
    var name: String
}

/// Master Sets: a title with a fan of your best cards, how many sets you've started and your
/// closest, three glass tiles, then every set as a full-width card with its art and progress. Your sets by default; switch to every set in the catalog. Tap one to see
/// every card in it.
struct MasterSetsView: View {
    @Environment(CollectionStore.self) private var store
    @State private var cache = MasterSetsCache.shared
    @State private var index: [ExploreSet] = []
    @State private var scope = Scope.mine
    @State private var sort = Sort.progress
    /// The search, handed over by the field a moment after typing stops (so typing doesn't
    /// rebuild the deck on every key).
    @State private var query = ""

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

    private var owned: [MasterSetDetailView.OwnedSet] { MasterSetDetailView.ownedSets(store.holdings) }

    private func rows(_ owned: [MasterSetDetailView.OwnedSet]) -> [Row] {
        let bySlug = Dictionary(index.map { ($0.slug, $0) }, uniquingKeysWith: { a, _ in a })
        let byName = Dictionary(index.map { ($0.name.lowercased(), $0) }, uniquingKeysWith: { a, _ in a })
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
            rows += index.filter { $0.loaded && !mine.contains($0.slug) && !mineNames.contains($0.name.lowercased()) }
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
                            NavigationLink(value: MasterSetRoute(id: r.id, name: r.name)) { SetBannerRow(row: r) }
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
            if index.isEmpty, let i = try? await Backend.shared.api.exploreIndex() { index = i.sets }
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
        // Your three most valuable cards across your sets, for the fan.
        var seen = Set<String>()
        let fanCards = owned.flatMap(\.holdings).sorted { ($0.value ?? 0) > ($1.value ?? 0) }.filter { seen.insert($0.identity.productId).inserted }
        return VStack(alignment: .leading, spacing: 16) {
            // The title in the page, with a fan of your best cards beside it.
            HStack(alignment: .center, spacing: 8) {
                VStack(alignment: .leading, spacing: 8) {
                    Text("Master Sets").font(.display(40)).tracking(-1.4).displayTrim(40)
                    Text("TRACK · COMPLETE · VALUE").font(.mono(11)).tracking(1.6).foregroundStyle(Theme.muted)
                }
                Spacer(minLength: 0)
                if !fanCards.isEmpty { HeroFan(holdings: Array(fanCards.prefix(3))) }
            }
            .padding(.top, 4)
            // How many sets you've started, and the one you're closest to finishing.
            VStack(alignment: .leading, spacing: 10) {
                HStack(alignment: .lastTextBaseline, spacing: 12) {
                    CountingText(value: Double(owned.count), format: { "\(Int($0.rounded()))" })
                        .font(.display(56)).tracking(-2.2).monospacedDigit().displayTrim(56)
                    Text(owned.count == 1 ? "Set started" : "Sets started").font(.display(24)).tracking(-0.6).displayTrim(24)
                }
                if let best, let ratio = best.ratio {
                    HStack(spacing: 8) {
                        Text("\(Int((ratio * 100).rounded()))%").font(.geist(13, .semibold)).monospacedDigit()
                            .foregroundStyle(Theme.ink)
                            .padding(.horizontal, 8).padding(.vertical, 3)
                            .background(Theme.lime, in: RoundedRectangle(cornerRadius: 6))
                        Text("of \(best.name), your closest").font(.geist(13)).foregroundStyle(Theme.muted).lineLimit(1)
                    }
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
                SettledSearchField(prompt: "Search sets", settled: $query, delay: 0.15)
                Menu {
                    Picker("Sort", selection: $sort) {
                        ForEach(Sort.allCases, id: \.self) { Text($0.rawValue).tag($0) }
                    }
                } label: { Image(systemName: "arrow.up.arrow.down") }
                    .menuStyle(.button)
                    .buttonStyle(IconButton3D(size: 46))
            }
            ChipPicker(options: Scope.allCases.map { ($0, $0.rawValue) }, selection: $scope)
        }
    }
}

/// One set as a full-width card in its own light: the set's banner art on the right, fading into
/// the card; the name, how many of how many, a lime progress bar and the % on the left. A finished
/// set is lit lime with a Complete tag.
struct SetBannerRow: View {
    var row: MasterSetsView.Row
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
                Text(subtitle).font(.geist(13)).monospacedDigit().foregroundStyle(Theme.muted).lineLimit(1)
                if let ratio = row.ratio, started {
                    HStack(spacing: 10) {
                        GrowBar(fraction: ratio, color: Theme.lime, height: 5, gradient: false)
                            .shadow(color: Theme.lime.opacity(0.6), radius: 5)
                        Text("\(Int((ratio * 100).rounded()))%").font(.geist(14, .semibold)).monospacedDigit()
                            .foregroundStyle(Theme.lime)
                    }
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
            shape.strokeBorder(LinearGradient(colors: [accent.opacity(0.95), accent.opacity(0.35), .white.opacity(0.08), accent.opacity(0.3)],
                                              startPoint: .topLeading, endPoint: .bottomTrailing), lineWidth: 1.5)
                .shadow(color: accent.opacity(0.55), radius: 10)
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
        } else if let cover = row.holdings.max(by: { ($0.value ?? 0) < ($1.value ?? 0) }) {
            // No banner (a demo set): your best card from it, tilted.
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

/// Three of your cards fanned out, leaning apart, for the top of Master Sets.
private struct HeroFan: View {
    var holdings: [HoldingView]

    var body: some View {
        let shown = Array(holdings.prefix(3))
        let mid = Double(shown.count - 1) / 2
        ZStack {
            ForEach(Array(shown.enumerated()), id: \.element.id) { i, h in
                HoldingArt(product: h.product, identity: h.identity, cornerRadius: 6, caption: false)
                    .frame(width: 74, height: 103)
                    .shadow(color: .black.opacity(0.55), radius: 10, y: 6)
                    .rotationEffect(.degrees((Double(i) - mid) * 12), anchor: .bottom)
                    .offset(x: CGFloat(Double(i) - mid) * 30)
                    .zIndex(Double(i))
            }
        }
        .frame(width: 160, height: 120)
        .background {
            RadialGradient(colors: [Theme.lime.opacity(0.22), .clear], center: .center, startRadius: 0, endRadius: 110)
                .allowsHitTesting(false)
        }
        .accessibilityHidden(true)
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
