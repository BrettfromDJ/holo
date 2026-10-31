import SwiftUI

/// Set card lists, shared by the Master Sets list and each set's page, loaded once per session
/// from Holo's stored catalog (no TCG API requests).
@Observable
final class MasterSetsCache {
    static let shared = MasterSetsCache()
    var checklists: [String: [SearchHit]] = [:]
    var failed: Set<String> = []
}

/// One master set: every card in it, laid out like Collection. The cards you own are in full
/// color, the rest dimmed, with search, sorting and filters, and how close you are to the full
/// set up top.
struct MasterSetDetailView: View {
    var setId: String
    var setName: String
    @Environment(CollectionStore.self) private var store
    @State private var cache = MasterSetsCache.shared
    private var checklists: [String: [SearchHit]] { cache.checklists }
    @State private var show = Show.all
    @State private var sort = Sort.number
    @State private var query = ""
    /// The search as of a moment ago, so typing doesn't redraw the whole set on every key.
    @State private var settledQuery = ""
    @FocusState private var searchFocused: Bool

    enum Show: String, CaseIterable { case all = "All", owned = "Owned", missing = "Missing" }
    enum Sort: String, CaseIterable {
        case number = "Set number", priceHigh = "Price: high to low", priceLow = "Price: low to high", name = "Name", ownedFirst = "Owned first", missingFirst = "Missing first"
    }

    struct OwnedSet: Identifiable {
        var id: String
        var name: String
        var holdings: [HoldingView]
    }

    /// One card of the set: the catalog entry, and your copies of it (none when missing).
    struct Entry: Identifiable {
        var hit: SearchHit
        var holdings: [HoldingView]
        var id: String { hit.product.id }
        var owned: Bool { !holdings.isEmpty }
        var price: Double? { holdings.first?.price ?? hit.market }
    }

    /// Your singles from this set.
    private var current: OwnedSet {
        OwnedSet(id: setId, name: setName, holdings: store.holdings.filter { $0.product?.isSealed == false && $0.product?.setId == setId })
    }

    /// Sets you own singles from, most owned first.
    static func ownedSets(_ holdings: [HoldingView]) -> [OwnedSet] {
        var map: [String: OwnedSet] = [:]
        for h in holdings {
            guard let p = h.product, !p.isSealed, let setId = p.setId else { continue }
            map[setId, default: OwnedSet(id: setId, name: p.setName ?? setId, holdings: [])].holdings.append(h)
        }
        return map.values.sorted { $0.holdings.count != $1.holdings.count ? $0.holdings.count > $1.holdings.count : $0.name < $1.name }
    }

    private let columns = Array(repeating: GridItem(.flexible(), spacing: 10), count: 3)

    var body: some View {
        let current = self.current
        let entries = entries(for: current)
        ScrollView {
            VStack(alignment: .leading, spacing: 24) {
                // The top, like Collection's: on the same lit backdrop.
                progress(current, entries: entries)
                    .background(alignment: .top) {
                        DotBackdrop().padding(.horizontal, -16).padding(.top, -160).padding(.bottom, -40)
                    }
                controls(entries)
                grid(entries)
            }
            .padding(.horizontal, 16)
            .padding(.bottom, 120)
        }
        .background(Theme.background)
        .imageMaxPixel(400)
        .replaysAnimations()
        .scrollDismissesKeyboard(.immediately)
        .navigationBarTitleDisplayMode(.inline)
        .pageTitle(setName)
        .task(id: setId) { await Self.load([current], store: store) }
        .task(id: query) {
            if !query.isEmpty { try? await Task.sleep(nanoseconds: 250_000_000) }
            guard !Task.isCancelled else { return }
            settledQuery = query
        }
    }

    // MARK: Loading

    /// These sets' card lists at once (a few small requests to Holo's own catalog), kept for the
    /// session so the list's progress and each set's page share them.
    @MainActor
    static func load(_ sets: [OwnedSet], store: CollectionStore) async {
        let cache = MasterSetsCache.shared
        let todo = sets.filter { cache.checklists[$0.id] == nil && !cache.failed.contains($0.id) }
        guard !todo.isEmpty else { return }
        if store.demo != nil || Demo.isOn {
            for s in todo { cache.checklists[s.id] = sampleChecklist(s) }
            return
        }
        await withTaskGroup(of: (String, [SearchHit]?).self) { group in
            for s in todo {
                group.addTask {
                    guard let detail = try? await Backend.shared.api.exploreSet(s.id), detail.set.loaded else { return (s.id, nil) }
                    let cards = detail.products.filter { !$0.product.isSealed }
                        .sorted { ($0.product.number ?? "~").localizedStandardCompare($1.product.number ?? "~") == .orderedAscending }
                    return (s.id, cards)
                }
            }
            for await (id, cards) in group {
                if let cards, !cards.isEmpty { cache.checklists[id] = cards } else { cache.failed.insert(id) }
            }
        }
    }

    /// Demo sets aren't in the catalog: numbered empty slots around the cards you own (like the
    /// website's sample checklists), never invented names.
    private static let sampleSizes: [String: Int] = [
        "evolving skies": 237, "scarlet & violet—151": 207, "surging sparks": 252, "lost origin": 247,
        "base set": 102, "obsidian flames": 230, "silver tempest": 245, "fusion strike": 284, "crown zenith": 230,
        "paldean fates": 245, "prismatic evolutions": 180,
    ]

    private static func sampleChecklist(_ s: OwnedSet) -> [SearchHit] {
        let size = sampleSizes[s.name.lowercased()] ?? max(60, s.holdings.count * 12)
        var cards: [SearchHit] = (1...size).map { n in
            SearchHit(product: Product(id: "sample-slot:\(s.id):\(n)", name: "#\(n)", setName: s.name, setId: s.id, number: String(n), kind: "single"), market: nil)
        }
        for h in s.holdings {
            guard let p = h.product, let n = p.number.flatMap({ Int($0.prefix { $0.isNumber }) }), n >= 1, n <= size else { continue }
            cards[n - 1] = SearchHit(product: p, printing: h.identity.printing, market: h.price)
        }
        return cards
    }

    private func entries(for set: OwnedSet) -> [Entry] {
        var byProduct: [String: [HoldingView]] = [:]
        for h in set.holdings { byProduct[h.identity.productId, default: []].append(h) }
        let own = { (hs: [HoldingView]) in Entry(hit: SearchHit(product: hs[0].product!, printing: hs[0].identity.printing, market: hs[0].price), holdings: hs) }
        guard let list = checklists[set.id] else {
            return byProduct.values.map(own).sorted { ($0.hit.product.number ?? "~").localizedStandardCompare($1.hit.product.number ?? "~") == .orderedAscending }
        }
        let listed = Set(list.map(\.product.id))
        // Owned cards the list doesn't include (promos) go at the end.
        return list.map { Entry(hit: $0, holdings: byProduct[$0.product.id] ?? []) } + byProduct.filter { !listed.contains($0.key) }.values.map(own)
    }

    // MARK: Progress

    private func progress(_ set: OwnedSet, entries: [Entry]) -> some View {
        let total = entries.count
        let owned = entries.filter(\.owned).count
        let ratio = total > 0 ? Double(owned) / Double(total) : 0
        let known = checklists[set.id] != nil
        let missingValue = entries.filter { !$0.owned }.compactMap(\.hit.market).reduce(0, +)
        let ownedValue = entries.flatMap(\.holdings).reduce(0) { $0 + ($1.value ?? 0) }
        return VStack(alignment: .leading, spacing: 18) {
            // Laid out like the top of Collection: label, big figure, a line under it.
            VStack(alignment: .leading, spacing: 8) {
                MonoLabel(text: set.name)
                CountingText(value: known ? ratio * 100 : Double(owned), format: { known ? "\(Int($0.rounded()))%" : "\(Int($0.rounded()))" })
                    .font(.display(56)).monospacedDigit().lineLimit(1).minimumScaleFactor(0.5)
                    .displayTrim(56)
                    .shadow(color: .white.opacity(0.12), radius: 18)
                HStack(spacing: 8) {
                    if known {
                        Text("\(owned) of \(total)").font(.geist(13, .semibold)).monospacedDigit()
                            .foregroundStyle(Theme.ink)
                            .padding(.horizontal, 8).padding(.vertical, 3)
                            .background(Theme.lime, in: RoundedRectangle(cornerRadius: 6))
                        Text("cards collected").font(.geist(13)).foregroundStyle(Theme.muted)
                    } else {
                        Text("cards owned · full list not in Holo yet").font(.geist(13)).foregroundStyle(Theme.muted)
                    }
                }
            }
            .padding(.top, 8)
            if known {
                // Every card in the set as one tick, lit if you own it, sweeping in left to right.
                SetStrip(owned: entries.map(\.owned))
                HStack(spacing: 8) {
                    GlassStat(label: "You own", value: Format.money(ownedValue))
                    GlassStat(label: "To finish", value: missingValue > 0 ? Format.money(missingValue) : "—")
                    GlassStat(label: "Missing", value: "\(total - owned)")
                }
            }
        }
    }

    // MARK: Search, sort, filter

    private func controls(_ entries: [Entry]) -> some View {
        let ownedCount = entries.filter(\.owned).count
        return VStack(alignment: .leading, spacing: 12) {
            HStack(spacing: 10) {
                HoloSearchField(text: $query, prompt: "Search this set", focus: $searchFocused)
                Menu {
                    Picker("Sort", selection: $sort) {
                        ForEach(Sort.allCases, id: \.self) { Text($0.rawValue).tag($0) }
                    }
                } label: {
                    Image(systemName: "arrow.up.arrow.down")
                }
                .menuStyle(.button)
                .buttonStyle(IconButton3D(size: 46))
            }
            HStack(spacing: 2) {
                Chip(title: "All", selected: show == .all, count: entries.count) { show = .all }
                Chip(title: "Owned", selected: show == .owned, count: ownedCount) { show = .owned }
                Chip(title: "Missing", selected: show == .missing, count: entries.count - ownedCount) { show = .missing }
            }
            .padding(4)
            .liquidGlass(in: Capsule())
            if sort != .number {
                Text("Sorted by \(sort.rawValue.lowercased())").font(.geist(13)).foregroundStyle(Theme.muted)
            }
        }
    }

    private func shown(_ entries: [Entry]) -> [Entry] {
        let q = settledQuery.trimmingCharacters(in: .whitespaces).lowercased()
        let filtered = entries.filter { e in
            (show == .all || (show == .owned) == e.owned) &&
                (q.isEmpty || e.hit.product.name.lowercased().contains(q) || (e.hit.product.number ?? "").lowercased().contains(q))
        }
        switch sort {
        case .number: return filtered
        case .priceHigh: return filtered.sorted { ($0.price ?? -1) > ($1.price ?? -1) }
        case .priceLow: return filtered.sorted { ($0.price ?? .infinity) < ($1.price ?? .infinity) }
        case .name: return filtered.sorted { $0.hit.product.name < $1.hit.product.name }
        case .ownedFirst: return filtered.filter(\.owned) + filtered.filter { !$0.owned }
        case .missingFirst: return filtered.filter { !$0.owned } + filtered.filter(\.owned)
        }
    }

    // MARK: Grid

    private func grid(_ entries: [Entry]) -> some View {
        let list = shown(entries)
        return Group {
            if list.isEmpty {
                Text(show == .owned ? "None owned yet." : show == .missing ? "Nothing missing. Set complete." : "Nothing matches.")
                    .font(.geist(15)).foregroundStyle(Theme.muted).frame(maxWidth: .infinity).padding(.vertical, 40)
            } else {
                LazyVGrid(columns: columns, spacing: 18) {
                    ForEach(list) { e in
                        if e.hit.product.id.hasPrefix("sample-slot:") {
                            CardCell(entry: e)
                        } else {
                            NavigationLink(value: e.hit.product.id) { CardCell(entry: e) }
                                .buttonStyle(.plain)
                                .simultaneousGesture(TapGesture().onEnded { if !e.owned { store.seed(e.hit) } })
                        }
                    }
                }
            }
        }
    }
}

/// One card of a master set: in full color with a lime check if you own it, dimmed if not.
private struct CardCell: View {
    var entry: MasterSetDetailView.Entry

    var body: some View {
        VStack(alignment: .leading, spacing: 4) {
            Color.clear
                .aspectRatio(63 / 88, contentMode: .fit)
                .overlay {
                    if let h = entry.holdings.first {
                        HoldingArt(product: h.product, identity: h.identity, cornerRadius: 5, caption: false)
                    } else if entry.hit.product.imageURL != nil {
                        ProductImage(product: entry.hit.product, cornerRadius: 5)
                            .grayscale(1).opacity(0.28)
                    } else {
                        RoundedRectangle(cornerRadius: 6, style: .continuous)
                            .strokeBorder(Color.white.opacity(0.12), style: StrokeStyle(lineWidth: 1, dash: [4, 4]))
                            .overlay(Text("#\(entry.hit.product.number ?? "—")").font(.mono(11)).foregroundStyle(Theme.subtle))
                    }
                }
                .overlay(alignment: .topTrailing) {
                    if entry.owned {
                        let qty = entry.holdings.reduce(0) { $0 + $1.quantity }
                        HStack(spacing: 3) {
                            Image(systemName: "checkmark").font(.system(size: 9, weight: .heavy))
                            if qty > 1 { Text("×\(Int(qty))").font(.geist(10, .bold)).monospacedDigit() }
                        }
                        .foregroundStyle(Theme.ink)
                        .padding(.horizontal, qty > 1 ? 6 : 0)
                        .frame(minWidth: 20, minHeight: 20)
                        .background(Theme.lime, in: Capsule())
                        .padding(5)
                    }
                }
            if !entry.hit.product.id.hasPrefix("sample-slot:") {
                Text(entry.hit.product.name).font(.geist(12, .medium)).lineLimit(1)
                    .foregroundStyle(entry.owned ? .white : Theme.muted)
            }
            // Numbered empty slots already show their number inside; real cards show it here.
            if !entry.hit.product.id.hasPrefix("sample-slot:") || entry.owned {
            HStack(spacing: 4) {
                Text("#\(entry.hit.product.number ?? "—")").font(.mono(10)).foregroundStyle(Theme.subtle).lineLimit(1)
                Spacer(minLength: 2)
                if let p = entry.price {
                    Text(Format.money(p)).font(.geist(11, .semibold)).monospacedDigit().foregroundStyle(entry.owned ? .white : Theme.muted).lineLimit(1)
                }
            }
            }
        }
    }
}

/// The whole set as a strip of ticks, one per card, lime where you own it. It sweeps in
/// left to right the first time it appears.
private struct SetStrip: View {
    var owned: [Bool]

    var body: some View {
        let perRow = owned.count > 120 ? 40 : owned.count > 60 ? 30 : 20
        let rows = stride(from: 0, to: owned.count, by: perRow).map { Array(owned[$0..<min($0 + perRow, owned.count)]) }
        VStack(alignment: .leading, spacing: 3) {
            ForEach(Array(rows.enumerated()), id: \.offset) { _, row in
                HStack(spacing: 2) {
                    ForEach(Array(row.enumerated()), id: \.offset) { _, on in
                        RoundedRectangle(cornerRadius: 1.5).fill(on ? Theme.lime : Color.white.opacity(0.13))
                            .frame(height: 12)
                    }
                    if row.count < perRow {
                        ForEach(0..<(perRow - row.count), id: \.self) { _ in Color.clear.frame(height: 12) }
                    }
                }
            }
        }
        .drawIn(duration: 1.2)
        .accessibilityElement()
        .accessibilityLabel("\(owned.filter { $0 }.count) of \(owned.count) cards owned")
    }
}
