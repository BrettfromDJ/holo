import SwiftUI

/// Set card lists, shared by the Master Sets list and each set's page, loaded once per session
/// from Holo's stored catalog (no TCG API requests).
@Observable
final class MasterSetsCache {
    static let shared = MasterSetsCache()
    var checklists: [String: [SearchHit]] = [:]
    var failed: Set<String> = []
    /// Sets fetched fresh this session (the saved copy shows first, then this replaces it).
    var refreshed: Set<String> = []
    private var restored = false

    private static var file: URL? {
        FileManager.default.urls(for: .cachesDirectory, in: .userDomainMask).first?.appendingPathComponent("master-set-checklists.json")
    }

    /// The card lists saved last time, so percentages show at once on the next visit. Read and
    /// decoded off the main thread (it can be a few megabytes), then merged in.
    @MainActor func restore() async {
        guard !restored else { return }
        restored = true
        guard let file = Self.file else { return }
        let saved = await Task.detached(priority: .userInitiated) { () -> [String: [SearchHit]] in
            guard let data = try? Data(contentsOf: file) else { return [:] }
            return (try? JSONDecoder().decode([String: [SearchHit]].self, from: data)) ?? [:]
        }.value
        for (id, cards) in saved where checklists[id] == nil { checklists[id] = cards }
    }

    /// Keep the real sets' lists on the phone (never a demo's).
    func persist() {
        guard let file = Self.file else { return }
        let real = checklists.filter { refreshed.contains($0.key) }
        guard !real.isEmpty else { return }
        // Off the main thread; merged with what's saved, so sets not opened this session keep
        // their copy.
        Task.detached(priority: .utility) {
            var all = (try? Data(contentsOf: file)).flatMap { try? JSONDecoder().decode([String: [SearchHit]].self, from: $0) } ?? [:]
            all.merge(real) { _, new in new }
            if let data = try? JSONEncoder().encode(all) { try? data.write(to: file, options: .atomic) }
        }
    }
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
    /// The search as of a moment ago (the field keeps the live text), so typing doesn't redraw
    /// the whole set on every key.
    @State private var settledQuery = ""
    @Environment(\.accessibilityReduceMotion) private var reduceMotion
    /// The completed-set moment plays once per visit: the dial sweeps a full lime circle and the
    /// % pulses bright.
    @State private var celebrated = false
    /// The dial's fraction while it sweeps (nil: show the real one).
    @State private var sweep: Double?
    @State private var pulse = false

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

    /// The set's cards and your copies, worked out once per change (not on every search pause).
    @State private var memo = SetEntriesMemo()

    var body: some View {
        let current = self.current
        let entries = memo.entries(current, checklist: checklists[current.id]) { self.entries(for: current) }
        let complete = checklists[current.id] != nil && !entries.isEmpty && entries.allSatisfy(\.owned)
        let ownedCount: Int = entries.reduce(0) { $0 + ($1.owned ? 1 : 0) }
        let ownedValue: Double = current.holdings.reduce(0.0) { $0 + ($1.value ?? 0) }
        let missingValue: Double = entries.reduce(0.0) { $0 + ($1.owned ? 0 : ($1.hit.market ?? 0)) }
        // Missing cards with no price yet: the total covers the rest and says how many are left out.
        let unpriced: Int = entries.reduce(0) { $0 + (!$1.owned && $1.hit.market == nil ? 1 : 0) }
        ScrollView {
            VStack(alignment: .leading, spacing: 24) {
                // The top, like Collection's: on the same lit backdrop. Its own equatable view, so
                // a chip, the sort or the search doesn't redraw the dial and the strip.
                SetProgressHeader(
                    known: checklists[current.id] != nil,
                    total: entries.count,
                    owned: ownedCount,
                    ownedValue: ownedValue,
                    missingValue: missingValue,
                    unpriced: unpriced,
                    strip: entries.map(\.owned),
                    sweep: sweep,
                    pulse: pulse
                )
                .equatable()
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
        // The lit grid runs up under the clear top bar; the set's name sits centered in the bar.
        .scrollClipDisabled()
        .navigationBarTitleDisplayMode(.inline)
        .pageTitle(setName)
        .onChange(of: complete, initial: true) { _, done in if done { celebrate() } }
        .sensoryFeedback(.success, trigger: celebrated) { _, now in now }
        .task(id: setId) {
            await Self.load([current], store: store)
            // The catalog fetches a set's prices just after the first look: when the cards you're
            // missing came back without prices, ask again a little later (once a visit).
            guard store.demo == nil, !Demo.isOn, let list = checklists[setId] else { return }
            let mine = Set(current.holdings.map(\.identity.productId))
            let missing = list.filter { !mine.contains($0.product.id) }
            guard !missing.isEmpty, missing.filter({ $0.market == nil }).count * 2 > missing.count else { return }
            try? await Task.sleep(nanoseconds: 12_000_000_000)
            guard !Task.isCancelled else { return }
            cache.refreshed.remove(setId)
            await Self.load([current], store: store)
        }
    }

    // MARK: Loading

    /// These sets' card lists at once (a few small requests to Holo's own catalog), kept for the
    /// session so the list's progress and each set's page share them.
    @MainActor
    static func load(_ sets: [OwnedSet], store: CollectionStore) async {
        let cache = MasterSetsCache.shared
        let demo = store.demo != nil || Demo.isOn
        // Real sets: show the saved lists straight away, then fetch each fresh once a session.
        if !demo { await cache.restore() }
        let todo = sets.filter { demo ? cache.checklists[$0.id] == nil && !cache.failed.contains($0.id) : !cache.refreshed.contains($0.id) && !cache.failed.contains($0.id) }
        guard !todo.isEmpty else { return }
        if demo {
            // Demo sets: the real set from the catalog when it's there (free, Holo's own catalog),
            // with the demo copies in their numbered places; numbered empty slots otherwise.
            let index = try? await Backend.shared.api.exploreIndex()
            for s in todo {
                if let real = index?.sets.first(where: { $0.loaded && Self.sameSetName($0.name, s.name) }),
                   let detail = try? await Backend.shared.api.exploreSet(real.slug) {
                    var cards = detail.products.filter { !$0.product.isSealed }
                        .sorted { ($0.product.number ?? "~").localizedStandardCompare($1.product.number ?? "~") == .orderedAscending }
                    for h in s.holdings {
                        guard let p = h.product, let n = Self.leadingNumber(p.number),
                              let i = cards.firstIndex(where: { Self.leadingNumber($0.product.number) == n }) else { continue }
                        cards[i] = SearchHit(product: p, printing: h.identity.printing, market: h.price ?? cards[i].market)
                    }
                    if !cards.isEmpty { cache.checklists[s.id] = cards; continue }
                }
                cache.checklists[s.id] = sampleChecklist(s)
            }
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
                if let cards, !cards.isEmpty {
                    cache.checklists[id] = cards
                    cache.refreshed.insert(id)
                } else if cache.checklists[id] == nil {
                    cache.failed.insert(id)
                } else {
                    cache.refreshed.insert(id) // Offline: keep the saved list for this session.
                }
            }
        }
        cache.persist()
    }

    /// "SV: Scarlet & Violet 151" and "Scarlet & Violet—151" are the same set: compared without a
    /// code prefix, punctuation or case.
    static func sameSetName(_ a: String, _ b: String) -> Bool {
        func key(_ s: String) -> String {
            s.lowercased()
                .replacingOccurrences(of: #"^[a-z]{1,6}\d*(\.\d+)?\s*:\s*"#, with: "", options: .regularExpression)
                .replacingOccurrences(of: #"[^a-z0-9]+"#, with: " ", options: .regularExpression)
                .trimmingCharacters(in: .whitespaces)
        }
        return key(a) == key(b)
    }

    /// "025/165" → 25.
    static func leadingNumber(_ s: String?) -> Int? {
        s.flatMap { Int($0.prefix { $0.isNumber }) }
    }

    /// Demo sets aren't in the catalog: numbered empty slots around the cards you own (like the
    /// website's sample checklists), never invented names.
    private static let sampleSizes: [String: Int] = [
        "evolving skies": 237, "scarlet & violet—151": 207, "surging sparks": 252, "lost origin": 247,
        "base set": 102, "obsidian flames": 230, "silver tempest": 245, "fusion strike": 284, "crown zenith": 230,
        "paldean fates": 245, "prismatic evolutions": 180,
    ]

    /// pokemontcg.io set codes for the demo sets, so a missing card shows its real art (faded),
    /// like the catalog's cards do for a real collection.
    private static let sampleArtCodes: [String: String] = [
        "evolving skies": "swsh7", "scarlet & violet—151": "sv3pt5", "surging sparks": "sv8", "lost origin": "swsh11",
        "base set": "base1", "obsidian flames": "sv3", "silver tempest": "swsh12", "fusion strike": "swsh8",
        "crown zenith": "swsh12pt5", "paldean fates": "sv4pt5", "prismatic evolutions": "sv8pt5",
    ]

    private static func sampleChecklist(_ s: OwnedSet) -> [SearchHit] {
        let size = sampleSizes[s.name.lowercased()] ?? max(60, s.holdings.count * 12)
        let code = sampleArtCodes[s.name.lowercased()]
        var cards: [SearchHit] = (1...size).map { n in
            var p = Product(id: "sample-slot:\(s.id):\(n)", name: "#\(n)", setName: s.name, setId: s.id, number: String(n), kind: "single")
            if let code { p.imageUrl = "https://images.pokemontcg.io/\(code)/\(n).png" }
            return SearchHit(product: p, market: nil)
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

    /// The completed-set moment, once per visit: a success tap, the dial sweeping from empty to a
    /// full lime circle and the % pulsing bright. Under Reduce Motion, just the tap.
    private func celebrate() {
        guard !celebrated else { return }
        celebrated = true
        guard !reduceMotion else { return }
        sweep = 0
        Task { @MainActor in
            // Let the empty dial draw before it sweeps.
            try? await Task.sleep(nanoseconds: 60_000_000)
            withAnimation(.timingCurve(0.45, 0, 0.2, 1, duration: 1.1)) { sweep = 1 }
            try? await Task.sleep(nanoseconds: 900_000_000)
            withAnimation(.spring(response: 0.25, dampingFraction: 0.6)) { pulse = true }
            try? await Task.sleep(nanoseconds: 260_000_000)
            withAnimation(.easeOut(duration: 0.6)) { pulse = false }
            try? await Task.sleep(nanoseconds: 700_000_000)
            sweep = nil
        }
    }

    // MARK: Search, sort, filter

    private func controls(_ entries: [Entry]) -> some View {
        let ownedCount = entries.filter(\.owned).count
        return VStack(alignment: .leading, spacing: 12) {
            HStack(spacing: 10) {
                SettledSearchField(prompt: "Search this set", settled: $settledQuery, delay: 0.3)
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
                            CardLink(productId: e.hit.product.id) { CardCell(entry: e) }
                                .buttonStyle(.plain)
                                .simultaneousGesture(TapGesture().onEnded { if !e.owned { store.seed(e.hit) } })
                        }
                    }
                }
            }
        }
    }
}

/// The top of a set's page: the % in glowing dot-matrix digits, the dial, two tiles and every
/// card as a tick. Equatable on plain values, so it only redraws when they change.
private struct SetProgressHeader: View, Equatable {
    var known: Bool
    var total: Int
    var owned: Int
    var ownedValue: Double
    var missingValue: Double
    /// Missing cards with no price yet.
    var unpriced: Int = 0
    var strip: [Bool]
    /// The dial's fraction while it sweeps (nil: show the real one).
    var sweep: Double?
    var pulse: Bool

    var body: some View {
        let ratio = total > 0 ? Double(owned) / Double(total) : 0
        let pct = Int((ratio * 100).rounded())
        // The set's page opens on the lit grid: the % in glowing lime digits, a dial of
        // how much you own, two tiles, then every card in the set as one tick.
        VStack(spacing: 18) {
            if known, total > 0, owned >= total {
                SkewTag(text: "Set complete", icon: "checkmark")
            }
            if known {
                // The % sits inside the dial, so the top stays compact.
                ZStack {
                    GlowPie(fraction: sweep ?? ratio)
                        .shadow(color: Theme.lime.opacity(0.25), radius: 24)
                    VStack(spacing: 4) {
                        Text("COMPLETE").font(.mono(10)).tracking(1.4).foregroundStyle(Theme.muted)
                        HStack(alignment: .top, spacing: 3) {
                            Text("\(pct)").font(.display(48)).tracking(-1.6).monospacedDigit()
                                .foregroundStyle(Theme.lime)
                                .displayTrim(48)
                                .shadow(color: Theme.lime.opacity(0.55), radius: 12)
                                // A completed set lights up once: brighter and a touch bigger, then back.
                                .brightness(pulse ? 0.35 : 0)
                                .scaleEffect(pulse ? 1.08 : 1)
                            Text("%").font(.geist(15)).foregroundStyle(Theme.lime)
                        }
                        Text("\(owned) of \(total)").font(.geist(13)).monospacedDigit().foregroundStyle(Theme.muted)
                    }
                }
                .frame(width: 260, height: 260)
                .accessibilityElement(children: .ignore)
                .accessibilityLabel("\(pct)% complete, \(owned) of \(total) cards")
            } else {
                VStack(spacing: 6) {
                    Text("CARDS OWNED").font(.mono(11)).tracking(1.6).foregroundStyle(Theme.muted)
                    Text("\(owned)").font(.display(56)).tracking(-1.8).monospacedDigit()
                        .foregroundStyle(Theme.lime)
                        .displayTrim(56)
                        .shadow(color: Theme.lime.opacity(0.55), radius: 16)
                    Text("full list not in Dexora\u{00A0}yet").font(.geist(13)).foregroundStyle(Theme.muted)
                }
            }
            // No money figures here: the dial and the card grid say it all.
        }
        .foregroundStyle(.white)
        .padding(.horizontal, 16)
        .padding(.top, 4)
        .padding(.bottom, 8)
        .frame(maxWidth: .infinity)
        // The dotted backdrop of the other pages behind the top, running up under the clear bar.
        .background(alignment: .top) {
            DotBackdrop().padding(.top, -200).padding(.bottom, -60)
        }
        .padding(.horizontal, -16)
    }

    /// A tile on the set's lit grid.
    private func heroTile(label: String, value: String, dim: Bool = false, note: String? = nil) -> some View {
        VStack(alignment: .leading, spacing: 6) {
            Text(label.uppercased()).font(.mono(10)).tracking(1.2).foregroundStyle(Theme.muted)
            Text(value).font(.geist(dim ? 17 : 24, .semibold)).tracking(-0.8).monospacedDigit()
                .foregroundStyle(dim ? Theme.muted : .white)
                .lineLimit(1).minimumScaleFactor(0.6)
            if let note { Text(note).font(.geist(12)).monospacedDigit().foregroundStyle(Theme.muted).lineLimit(1) }
        }
        .padding(.horizontal, 14).padding(.vertical, 12)
        // Both tiles the same height, whatever their figure.
        .frame(maxWidth: .infinity, maxHeight: .infinity, alignment: .topLeading)
        .liquidGlass(in: RoundedRectangle(cornerRadius: 20, style: .continuous))
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
                            // In color, faded, so the cards you have still stand out.
                            .opacity(0.32)
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
                            Image(systemName: "checkmark").font(.system(size: 9, weight: .medium))
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

/// A search field that keeps its own text and hands the page the search a moment after typing
/// stops (at once when cleared), so typing redraws only the field, not the page on every key.
struct SettledSearchField: View {
    var prompt: String
    @Binding var settled: String
    /// How long to wait after the last key.
    var delay: Double = 0.25
    @State private var text = ""
    @FocusState private var focused: Bool

    var body: some View {
        HoloSearchField(text: $text, prompt: prompt, focus: $focused)
            .task(id: text) {
                if !text.isEmpty, delay > 0 { try? await Task.sleep(nanoseconds: UInt64(delay * 1_000_000_000)) }
                guard !Task.isCancelled, settled != text else { return }
                settled = text
            }
    }
}

/// Remembers a set page's card list by what it's built from (a plain object: no redraws).
final class SetEntriesMemo {
    private var key: String?
    private var value: [MasterSetDetailView.Entry] = []

    func entries(_ set: MasterSetDetailView.OwnedSet, checklist: [SearchHit]?, build: () -> [MasterSetDetailView.Entry]) -> [MasterSetDetailView.Entry] {
        var worth = 0.0
        for h in set.holdings { worth += h.value ?? 0 }
        let k = "\(set.id)|\(set.holdings.count)|\(worth)|\(checklist?.count ?? -1)|\(checklist?.first?.product.id ?? "")"
        if k == key { return value }
        key = k
        value = build()
        return value
    }
}
