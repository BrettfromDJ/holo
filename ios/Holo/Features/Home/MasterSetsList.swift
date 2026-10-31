import SwiftUI

/// Opens one master set's page (pushed on Home).
struct MasterSetRoute: Hashable {
    var id: String
    var name: String
}

/// Master Sets: the sets you collect as tiles with their artwork and your progress, like
/// Explore's set grid. Your sets by default; switch to every set in the catalog. Tap one to see
/// every card in it.
struct MasterSetsView: View {
    @Environment(CollectionStore.self) private var store
    @State private var cache = MasterSetsCache.shared
    @State private var index: [ExploreSet] = []
    @State private var scope = Scope.mine
    @State private var sort = Sort.progress
    @State private var query = ""
    @FocusState private var searchFocused: Bool

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

    private let columns = [GridItem(.flexible(), spacing: 14), GridItem(.flexible(), spacing: 14)]

    var body: some View {
        let owned = self.owned
        let rows = self.rows(owned)
        ScrollView {
            VStack(alignment: .leading, spacing: 24) {
                header(owned)
                if owned.isEmpty, scope == .mine {
                    VStack(spacing: 10) {
                        Image(systemName: "square.grid.3x3").font(.system(size: 36)).foregroundStyle(Theme.subtle)
                        Text("No singles yet").font(.geist(15, .medium))
                        Text("Add a single card and its set appears here, with every card in it and how close you are to the full set.")
                            .font(.geist(13)).foregroundStyle(Theme.muted).multilineTextAlignment(.center)
                    }
                    .frame(maxWidth: .infinity).padding(.vertical, 50)
                } else {
                    controls
                    // A deck of glowing set cards, each overlapping the one above so you see its
                    // name and progress; the last one shows in full. Tap one to open the set.
                    LazyVStack(spacing: -SetDeckCard.overlap) {
                        ForEach(Array(rows.enumerated()), id: \.element.id) { i, r in
                            NavigationLink(value: MasterSetRoute(id: r.id, name: r.name)) {
                                SetDeckCard(row: r)
                            }
                            .buttonStyle(.plain)
                            .zIndex(Double(i))
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
        .pageTitle("Master Sets")
        .task {
            if index.isEmpty, let i = try? await Backend.shared.api.exploreIndex() { index = i.sets }
        }
        .task(id: owned.map(\.id).joined(separator: ",")) { await MasterSetDetailView.load(owned, store: store) }
    }

    // MARK: Top

    private func header(_ owned: [MasterSetDetailView.OwnedSet]) -> some View {
        let rows = self.rows(owned).filter { !$0.holdings.isEmpty }
        let complete = rows.filter { ($0.ratio ?? 0) >= 1 }.count
        let best = rows.filter { $0.ratio != nil }.max { ($0.ratio ?? 0) < ($1.ratio ?? 0) }
        let cards = owned.reduce(0) { $0 + Set($1.holdings.map(\.identity.productId)).count }
        let worth = owned.reduce(0.0) { $0 + $1.holdings.reduce(0.0) { $0 + ($1.value ?? 0) } }
        return VStack(alignment: .leading, spacing: 10) {
            GlowCard(palette: .gold, padding: 20) {
                HStack(alignment: .center, spacing: 12) {
                    VStack(alignment: .leading, spacing: 0) {
                        GlowLabel(text: "Master sets", secondary: owned.count == 1 ? "set started" : "sets started")
                        Spacer(minLength: 24)
                        CountingText(value: Double(owned.count), format: { "\(Int($0.rounded()))" })
                            .font(.geist(60, .regular)).tracking(-2.4).monospacedDigit().lineLimit(1)
                        if let best, best.ratio != nil {
                            Text("\(best.name), your closest").font(.geist(13, .medium)).opacity(0.8).lineLimit(1)
                                .padding(.top, 2)
                        }
                    }
                    Spacer(minLength: 0)
                    if let best, let ratio = best.ratio {
                        // The closest set's progress: a thin ring with the % as LED dots.
                        ZStack {
                            GlowRing(fraction: ratio, label: "")
                            DotMatrixText(text: "\(Int((ratio * 100).rounded()))%", dot: 2.6)
                        }
                        .frame(width: 104, height: 104)
                    }
                }
                .frame(minHeight: 132)
            }
            HStack(spacing: 10) {
                MoreGlowTile(label: "Cards", palette: .sky, height: 84) {
                    DotMatrixText(text: "\(cards)", dot: 3)
                }
                MoreGlowTile(label: "Complete", palette: .rose, height: 84) {
                    DotMatrixText(text: "\(complete)", dot: 3)
                }
                MoreGlowTile(label: "Worth", palette: .aqua, height: 84) {
                    MoreGlowValue(text: GlowFigure.text(worth, signed: false, cents: false), size: 22)
                }
            }
        }
    }

    private var controls: some View {
        VStack(alignment: .leading, spacing: 12) {
            HStack(spacing: 10) {
                HoloSearchField(text: $query, prompt: "Search sets", focus: $searchFocused)
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

    // MARK: A set

    /// The set's banner art like Explore's, with your progress: a ring and % on the set's own glow, then the
    /// name, how many of how many, and a thin progress bar.
    private func tile(_ r: Row) -> some View {
        let shape = RoundedRectangle(cornerRadius: 16, style: .continuous)
        // Each set keeps its own glow colors for its progress.
        let glow = GlowPalette.forProduct(r.id)
        return VStack(alignment: .leading, spacing: 9) {
            Group {
                if let art = r.art {
                    SetArt(set: art)
                } else if let cover = r.holdings.max(by: { ($0.value ?? 0) < ($1.value ?? 0) }) {
                    // Not in the catalog index (a demo set): your best card from it.
                    ZStack {
                        Theme.well
                        HoldingArt(product: cover.product, identity: cover.identity, cornerRadius: 4, caption: false).padding(10)
                    }
                } else {
                    Theme.well
                }
            }
            .aspectRatio(3.0 / 2.0, contentMode: .fit)
            .clipShape(shape)
            .overlay(shape.strokeBorder(Theme.border))
            .overlay(alignment: .bottomLeading) {
                if let ratio = r.ratio, !r.holdings.isEmpty {
                    HStack(spacing: 6) {
                        ZStack {
                            Circle().stroke(Color.white.opacity(0.3), lineWidth: 1.5)
                            Circle().trim(from: 0, to: ratio).stroke(Color.white, style: StrokeStyle(lineWidth: 2, lineCap: .round)).rotationEffect(.degrees(-90))
                        }
                        .frame(width: 15, height: 15)
                        Text("\(Int((ratio * 100).rounded()))%").font(.geist(12, .semibold)).monospacedDigit()
                    }
                    .foregroundStyle(.white)
                    .padding(.horizontal, 8).padding(.vertical, 5)
                    .background(glow.chipGradient, in: Capsule())
                    .overlay(Capsule().strokeBorder(.white.opacity(0.15)))
                    .padding(8)
                } else if r.holdings.isEmpty {
                    Text("Not started").font(.geist(11, .semibold)).foregroundStyle(Theme.muted)
                        .padding(.horizontal, 8).padding(.vertical, 4)
                        .background(.black.opacity(0.6), in: Capsule())
                        .padding(8)
                }
            }
            VStack(alignment: .leading, spacing: 3) {
                Text(r.name).font(.geist(14, .medium)).lineLimit(1)
                Text(r.total.map { "\(r.owned) of \($0) cards" } ?? (r.holdings.isEmpty ? (r.art?.release?.formatted(.dateTime.month(.abbreviated).year()) ?? " ") : "\(r.owned) card\(r.owned == 1 ? "" : "s")"))
                    .font(.geist(12)).monospacedDigit().foregroundStyle(Theme.muted).lineLimit(1)
            }
            if let ratio = r.ratio, !r.holdings.isEmpty {
                GrowBar(fraction: ratio, color: glow.chipAccent, height: 4)
            }
        }
    }
}

/// One set in the Master Sets deck: a tall glowing card in the set's own colors. The top shows
/// the name, how many of how many, and the % in dot-matrix digits (what you see while it's
/// overlapped); the rest, seen on the last card or while scrolling past, has the art and a bar.
struct SetDeckCard: View {
    var row: MasterSetsView.Row
    static let height: CGFloat = 196
    static let overlap: CGFloat = 70

    var body: some View {
        let shape = RoundedRectangle(cornerRadius: 30, style: .continuous)
        let palette = GlowPalette.forProduct(row.id)
        VStack(alignment: .leading, spacing: 0) {
            HStack(alignment: .top, spacing: 10) {
                VStack(alignment: .leading, spacing: 4) {
                    Text(row.name).font(.geist(22, .semibold)).lineLimit(1).minimumScaleFactor(0.7)
                    Text(row.total.map { "\(row.owned) of \($0) cards" } ?? (row.holdings.isEmpty ? "Not started" : "\(row.owned) card\(row.owned == 1 ? "" : "s")"))
                        .font(.geist(13)).monospacedDigit().opacity(0.75)
                }
                Spacer(minLength: 8)
                if let ratio = row.ratio, !row.holdings.isEmpty {
                    HStack(alignment: .top, spacing: 2) {
                        DotMatrixText(text: "\(Int((ratio * 100).rounded()))", dot: 3.4)
                        Text("%").font(.geist(12)).opacity(0.7)
                    }
                }
            }
            Spacer(minLength: 0)
            HStack(alignment: .bottom) {
                if let ratio = row.ratio, !row.holdings.isEmpty {
                    GlowTicks(fraction: ratio).frame(height: 20).frame(maxWidth: 180)
                }
                Spacer()
            }
        }
        .padding(20)
        .frame(height: Self.height)
        .frame(maxWidth: .infinity, alignment: .leading)
        .foregroundStyle(.white)
        .background {
            ZStack(alignment: .bottomTrailing) {
                GlowFill(palette: palette)
                art
                    .frame(width: 150, height: 100)
                    .clipShape(RoundedRectangle(cornerRadius: 10, style: .continuous))
                    .opacity(0.55)
                    .rotationEffect(.degrees(-6))
                    .offset(x: 16, y: 10)
            }
        }
        .clipShape(shape)
        .overlay(shape.strokeBorder(.white.opacity(0.12)))
        .shadow(color: .black.opacity(0.55), radius: 10, y: -4)
    }

    @ViewBuilder private var art: some View {
        if let art = row.art {
            SetArt(set: art)
        } else if let cover = row.holdings.max(by: { ($0.value ?? 0) < ($1.value ?? 0) }) {
            HoldingArt(product: cover.product, identity: cover.identity, cornerRadius: 4, caption: false)
        } else {
            Color.clear
        }
    }
}
