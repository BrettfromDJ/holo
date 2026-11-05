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
    /// The search, handed over by the field a moment after typing stops (so typing doesn't
    /// rebuild the deck on every key).
    @State private var query = ""
    /// How far the page is pulled down past the top; only the deck reads it.
    @State private var fan = DeckFan()

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
                header(owned, rows: rows)
                if owned.isEmpty, scope == .mine {
                    EmptyPage(title: "No sets yet", line: "Add a few cards and your sets appear here.", action: "Scan a card",
                              onAction: { Router.shared.scanRequest += 1 }, link: "Browse all sets", onLink: { scope = .all })
                } else {
                    controls
                    // A deck of set cards, each overlapping the one above so you see its name and
                    // progress; the last one shows in full. Tap one to open the set.
                    // Pulling down at the top fans the deck open a little.
                    SetDeck(rows: rows, fan: fan)
                    if rows.isEmpty {
                        Text("Nothing matches.").font(.geist(15)).foregroundStyle(Theme.muted).frame(maxWidth: .infinity).padding(.vertical, 30)
                    }
                }
            }
            .padding(.horizontal, 16)
            .padding(.bottom, 120)
            .background(alignment: .top) { DeckPullReader(fan: fan) }
        }
        .coordinateSpace(.named(DeckPullReader.space))
        .modifier(DeckPullTracker(fan: fan))
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

    private func header(_ owned: [MasterSetDetailView.OwnedSet], rows all: [Row]) -> some View {
        let rows = all.filter { !$0.holdings.isEmpty }
        let complete = rows.filter { ($0.ratio ?? 0) >= 1 }.count
        let best = rows.filter { $0.ratio != nil }.max { ($0.ratio ?? 0) < ($1.ratio ?? 0) }
        let cards = owned.reduce(0) { $0 + Set($1.holdings.map(\.identity.productId)).count }
        return VStack(alignment: .leading, spacing: 18) {
            VStack(alignment: .leading, spacing: 8) {
                MonoLabel(text: "Master sets")
                HStack(alignment: .lastTextBaseline, spacing: 10) {
                    CountingText(value: Double(owned.count), format: { "\(Int($0.rounded()))" })
                        .font(.display(56)).tracking(-2.2).monospacedDigit().displayTrim(56)
                    Text(owned.count == 1 ? "Set started" : "Sets started").font(.display(24)).tracking(-0.6).foregroundStyle(Theme.muted).displayTrim(24)
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
            .padding(.top, 8)
            HStack(spacing: 8) {
                GlassStat(label: "Cards", value: "\(cards)")
                GlassStat(label: "Complete", value: "\(complete)")
                GlassStat(label: "Worth", value: Format.money(owned.reduce(0) { $0 + $1.holdings.reduce(0) { $0 + ($1.value ?? 0) } }))
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

    // MARK: A set

    /// The set's banner art like Explore's, with your progress: a lime ring and %, then the
    /// name, how many of how many, and a thin progress bar.
    private func tile(_ r: Row) -> some View {
        let shape = RoundedRectangle(cornerRadius: 16, style: .continuous)
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
                            Circle().stroke(Color.white.opacity(0.2), lineWidth: 3)
                            Circle().trim(from: 0, to: ratio).stroke(Theme.lime, style: StrokeStyle(lineWidth: 3, lineCap: .round)).rotationEffect(.degrees(-90))
                        }
                        .frame(width: 16, height: 16)
                        Text("\(Int((ratio * 100).rounded()))%").font(.geist(12, .bold)).monospacedDigit()
                    }
                    .padding(.horizontal, 8).padding(.vertical, 5)
                    .background(.black.opacity(0.6), in: Capsule())
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
                GrowBar(fraction: ratio, color: Theme.lime, height: 4, gradient: false)
            }
        }
    }
}

/// One set in the Master Sets deck: a tall card on the lit grid with a lime, blue or pink glow of
/// its own. The top shows the name, how many of how many and the % in dot-matrix digits (what
/// you see while it's overlapped); the last card also shows its art and a lime tick bar.
struct SetDeckCard: View {
    var row: MasterSetsView.Row
    static let height: CGFloat = 196
    static let overlap: CGFloat = 70

    /// Every card of the set owned (and the full list known).
    private var isComplete: Bool {
        guard let total = row.total, total > 0, !row.holdings.isEmpty else { return false }
        return row.owned >= total
    }

    var body: some View {
        let shape = RoundedRectangle(cornerRadius: 28, style: .continuous)
        VStack(alignment: .leading, spacing: 0) {
            HStack(alignment: .top, spacing: 10) {
                VStack(alignment: .leading, spacing: 4) {
                    Text(row.name).font(.geist(22, .semibold)).lineLimit(1).minimumScaleFactor(0.7)
                    HStack(spacing: 8) {
                        Text(row.total.map { "\(row.owned) of \($0) cards" } ?? (row.holdings.isEmpty ? "Not started" : "\(row.owned) card\(row.owned == 1 ? "" : "s")"))
                            .font(.geist(13)).monospacedDigit().foregroundStyle(Theme.muted)
                        if isComplete {
                            Text("Complete")
                                .font(.geist(11, .semibold))
                                .foregroundStyle(Theme.ink)
                                .padding(.horizontal, 7).padding(.vertical, 2)
                                .background(Theme.lime, in: Capsule())
                        }
                    }
                }
                Spacer(minLength: 8)
                if let ratio = row.ratio, !row.holdings.isEmpty {
                    HStack(alignment: .top, spacing: 2) {
                        DotMatrixText(text: "\(Int((ratio * 100).rounded()))", dot: 3.4, color: Theme.lime)
                            .shadow(color: Theme.lime.opacity(0.5), radius: 8)
                        Text("%").font(.geist(12)).foregroundStyle(Theme.lime)
                    }
                }
            }
            Spacer(minLength: 0)
            if let ratio = row.ratio, !row.holdings.isEmpty {
                GrowBar(fraction: ratio, color: Theme.lime, height: 4).frame(maxWidth: 200)
            }
        }
        .padding(20)
        .frame(height: Self.height)
        .frame(maxWidth: .infinity, alignment: .leading)
        .foregroundStyle(.white)
        .background {
            ZStack(alignment: .bottomTrailing) {
                SetGlow(id: row.id)
                art
                    .frame(width: 150, height: 100)
                    .clipShape(RoundedRectangle(cornerRadius: 10, style: .continuous))
                    .opacity(0.6)
                    .rotationEffect(.degrees(-6))
                    .offset(x: 16, y: 10)
            }
        }
        .clipShape(shape)
        .overlay(shape.strokeBorder(Theme.border))
        .shadow(color: .black.opacity(0.6), radius: 10, y: -4)
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

// MARK: - Pulling the deck open

/// How far the Master Sets page is pulled down past its top. A reference, so only the deck
/// (which reads it) redraws while you pull, not the whole page.
@Observable
final class DeckFan {
    /// Points pulled past the top (0 when not pulling).
    var pull: CGFloat = 0
    /// Where the top of the content sits at rest (the fallback reader's baseline).
    @ObservationIgnored var rest: CGFloat?

    func set(_ value: CGFloat) {
        let v = max(0, value.rounded())
        if v != pull { pull = v }
    }
}

/// The deck of set cards. Pulling down at the top shrinks the overlap a little, in step with the
/// pull, so the deck fans open; it closes again as the page springs back. Only the spacing changes.
private struct SetDeck: View {
    var rows: [MasterSetsView.Row]
    var fan: DeckFan

    var body: some View {
        // Up to 40 points more of each card shows at a full pull.
        let opening = min(fan.pull, 140) * 0.28
        LazyVStack(spacing: -SetDeckCard.overlap + opening) {
            ForEach(Array(rows.enumerated()), id: \.element.id) { i, r in
                NavigationLink(value: MasterSetRoute(id: r.id, name: r.name)) {
                    SetDeckCard(row: r)
                }
                .buttonStyle(.plain)
                .zIndex(Double(i))
            }
        }
    }
}

/// Reads the pull on iOS 18 straight from the scroll view (fires only when the value changes).
private struct DeckPullTracker: ViewModifier {
    var fan: DeckFan

    @ViewBuilder func body(content: Content) -> some View {
        if #available(iOS 18, *) {
            content.onScrollGeometryChange(for: CGFloat.self) { geo in
                max(0, -(geo.contentOffset.y + geo.contentInsets.top)).rounded()
            } action: { _, pull in
                fan.set(pull)
            }
        } else {
            content
        }
    }
}

/// Reads the pull on iOS 17: where the top of the content sits in the scroll view, against
/// where it sat when the page appeared.
private struct DeckPullReader: View {
    static let space = "masterSetsScroll"
    var fan: DeckFan

    var body: some View {
        if #available(iOS 18, *) {
            Color.clear
        } else {
            GeometryReader { geo in
                let y = geo.frame(in: .named(Self.space)).minY
                Color.clear
                    .onAppear { if fan.rest == nil { fan.rest = y } }
                    .onChange(of: y) { _, new in
                        guard let rest = fan.rest else { return }
                        fan.set(new - rest)
                    }
            }
        }
    }
}
