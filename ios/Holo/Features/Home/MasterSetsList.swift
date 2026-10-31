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
                    LazyVGrid(columns: columns, alignment: .leading, spacing: 22) {
                        ForEach(Array(rows.enumerated()), id: \.element.id) { i, r in
                            NavigationLink(value: MasterSetRoute(id: r.id, name: r.name)) { tile(r) }
                                .buttonStyle(.plain)
                                .popIn(delay: Double(min(i, 8)) * 0.04)
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
        return VStack(alignment: .leading, spacing: 18) {
            VStack(alignment: .leading, spacing: 8) {
                MonoLabel(text: "Master sets")
                HStack(alignment: .lastTextBaseline, spacing: 10) {
                    CountingText(value: Double(owned.count), format: { "\(Int($0.rounded()))" })
                        .font(.display(56)).monospacedDigit().displayTrim(56)
                    Text(owned.count == 1 ? "SET STARTED" : "SETS STARTED").font(.display(24)).foregroundStyle(Theme.muted).displayTrim(24)
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
