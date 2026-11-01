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

    var body: some View {
        let current = self.current
        let entries = entries(for: current)
        let complete = checklists[current.id] != nil && !entries.isEmpty && entries.allSatisfy(\.owned)
        let ownedCount: Int = entries.reduce(0) { $0 + ($1.owned ? 1 : 0) }
        let ownedValue: Double = current.holdings.reduce(0.0) { $0 + ($1.value ?? 0) }
        let missingValue: Double = entries.reduce(0.0) { $0 + ($1.owned ? 0 : ($1.hit.market ?? 0)) }
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
        .task(id: setId) { await Self.load([current], store: store) }
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
                SettledSearchField(prompt: "Search this set", settled: $settledQuery)
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
    var strip: [Bool]
    /// The dial's fraction while it sweeps (nil: show the real one).
    var sweep: Double?
    var pulse: Bool

    var body: some View {
        let ratio = total > 0 ? Double(owned) / Double(total) : 0
        let pct = Int((ratio * 100).rounded())
        // The set's page opens on the lit grid: the % in glowing lime dot-matrix digits, a dial of
        // how much you own, two tiles, then every card in the set as one tick.
        VStack(spacing: 18) {
            VStack(spacing: 6) {
                Text(known ? "COMPLETE" : "CARDS OWNED").font(.mono(11)).tracking(1.6).foregroundStyle(Theme.muted)
                HStack(alignment: .top, spacing: 4) {
                    DotMatrixText(text: known ? "\(pct)" : "\(owned)", dot: 6.5, color: Theme.lime)
                        .shadow(color: Theme.lime.opacity(0.55), radius: 16)
                        // A completed set lights up once: brighter and a touch bigger, then back.
                        .brightness(pulse ? 0.35 : 0)
                        .scaleEffect(pulse ? 1.08 : 1)
                    if known { Text("%").font(.geist(16)).foregroundStyle(Theme.lime) }
                }
                Text(known ? "\(owned) of \(total) cards" : "full list not in Lucent yet").font(.geist(13)).foregroundStyle(Theme.muted)
            }
            if known {
                GlowPie(fraction: sweep ?? ratio).frame(width: 180).padding(.vertical, 10)
                    .shadow(color: Theme.lime.opacity(0.25), radius: 24)
                HStack(spacing: 10) {
                    heroTile(label: "You own", sub: "worth") {
                        HStack(alignment: .center, spacing: 10) {
                            GlowRing(fraction: ratio, label: "").frame(width: 38, height: 38).foregroundStyle(Theme.lime)
                            Text(Format.moneyWhole(ownedValue)).font(.geist(24, .semibold)).tracking(-0.8).monospacedDigit()
                                .lineLimit(1).minimumScaleFactor(0.6)
                        }
                    }
                    heroTile(label: "To finish", sub: "\(total - owned) missing") {
                        VStack(alignment: .leading, spacing: 10) {
                            Text(missingValue > 0 ? Format.moneyWhole(missingValue) : "—").font(.geist(24, .semibold)).tracking(-0.8).monospacedDigit()
                                .lineLimit(1).minimumScaleFactor(0.6)
                            GlowTicks(fraction: ratio).frame(height: 16)
                        }
                    }
                }
                // Every card in the set as one tick, lit if you own it, sweeping in left to right.
                SetStrip(owned: strip)
            }
        }
        .foregroundStyle(.white)
        .padding(.horizontal, 16)
        .padding(.top, 8)
        .padding(.bottom, 22)
        .frame(maxWidth: .infinity)
        // The dotted backdrop of the other pages behind the top, running up under the clear bar.
        .background(alignment: .top) {
            DotBackdrop().padding(.top, -200).padding(.bottom, -60)
        }
        .padding(.horizontal, -16)
    }

    /// A tile on the set's lit grid.
    private func heroTile<C: View>(label: String, sub: String, @ViewBuilder content: () -> C) -> some View {
        VStack(alignment: .leading, spacing: 0) {
            Text(label).font(.geist(13, .semibold))
            Text(sub).font(.geist(11)).foregroundStyle(Theme.muted)
            Spacer(minLength: 14)
            content()
        }
        .padding(14)
        .frame(maxWidth: .infinity, minHeight: 128, alignment: .topLeading)
        .liquidGlass(in: RoundedRectangle(cornerRadius: 22, style: .continuous))
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
        let rows = (owned.count + perRow - 1) / perRow
        // One Canvas instead of a view per card (a set can have 250+), drawn the same: rows of
        // equal ticks 2pt apart, 3pt between rows.
        Canvas { ctx, size in
            let gap: CGFloat = 2
            let w = (size.width - gap * CGFloat(perRow - 1)) / CGFloat(perRow)
            guard w > 0 else { return }
            var lit = Path()
            var dim = Path()
            for (i, on) in owned.enumerated() {
                let rect = CGRect(x: CGFloat(i % perRow) * (w + gap), y: CGFloat(i / perRow) * 15, width: w, height: 12)
                if on { lit.addRoundedRect(in: rect, cornerSize: CGSize(width: 1.5, height: 1.5), style: .circular) } else { dim.addRoundedRect(in: rect, cornerSize: CGSize(width: 1.5, height: 1.5), style: .circular) }
            }
            ctx.fill(dim, with: .color(Color.white.opacity(0.13)))
            ctx.fill(lit, with: .color(Theme.lime))
        }
        .frame(height: rows > 0 ? CGFloat(rows) * 12 + CGFloat(rows - 1) * 3 : 0)
        .drawIn(duration: 1.2)
        .accessibilityElement()
        .accessibilityLabel("\(owned.filter { $0 }.count) of \(owned.count) cards owned")
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
