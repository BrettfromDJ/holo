import SwiftUI

/// Your singles, page by page, and what's missing from each set, like the website's Binder.
/// The set's card list comes from Holo's stored catalog (no TCG API requests).
struct BinderView: View {
    @Environment(CollectionStore.self) private var store
    @State private var selected: String?
    @State private var checklists: [String: [SearchHit]] = [:]
    @State private var failed: [String: String] = [:]
    @State private var show = Show.all
    @State private var page = 0

    enum Show: String, CaseIterable { case all = "All", owned = "Owned", missing = "Missing" }

    struct OwnedSet: Identifiable {
        var id: String
        var name: String
        var holdings: [HoldingView]
        /// The most valuable card you own from the set, for its tile.
        var cover: HoldingView? { holdings.max { ($0.value ?? 0) < ($1.value ?? 0) } }
        var count: Double { holdings.reduce(0) { $0 + $1.quantity } }
    }

    struct Slot: Identifiable {
        var hit: SearchHit
        var holdings: [HoldingView]
        var id: String { hit.product.id }
    }

    private static let perPage = 9

    /// Sets you own singles from, most owned first.
    private var sets: [OwnedSet] {
        var map: [String: OwnedSet] = [:]
        for h in store.holdings {
            guard let p = h.product, !p.isSealed, let setId = p.setId else { continue }
            map[setId, default: OwnedSet(id: setId, name: p.setName ?? setId, holdings: [])].holdings.append(h)
        }
        return map.values.sorted { $0.holdings.count != $1.holdings.count ? $0.holdings.count > $1.holdings.count : $0.name < $1.name }
    }

    var body: some View {
        let sets = self.sets
        let current = sets.first { $0.id == selected } ?? sets.first
        ScrollView {
            VStack(alignment: .leading, spacing: 28) {
                header(sets)
                if sets.isEmpty {
                    VStack(spacing: 10) {
                        Image(systemName: "book.closed").font(.system(size: 36)).foregroundStyle(Theme.subtle)
                        Text("No singles yet").font(.geist(15, .medium))
                        Text("Add a single card and its set appears here as a binder, with empty pockets for the cards you don't own yet.")
                            .font(.geist(13)).foregroundStyle(Theme.muted).multilineTextAlignment(.center)
                    }
                    .frame(maxWidth: .infinity).padding(.vertical, 60)
                } else {
                    ScrollView(.horizontal, showsIndicators: false) {
                        HStack(spacing: 10) {
                            ForEach(sets) { s in setTile(s, active: s.id == current?.id) }
                        }
                    }
                    .scrollClipDisabled()
                    if let current { book(current) }
                }
            }
            .padding(.horizontal, 16)
            .padding(.bottom, 120)
        }
        .background(Theme.background)
        .replaysAnimations()
        .sensoryFeedback(.impact(weight: .light), trigger: page)
        .navigationBarTitleDisplayMode(.inline)
        .pageTitle("Binder")
        .task(id: current?.id) {
            guard let current else { return }
            await load(current.id)
            // Open on the first page that holds a card you own.
            let slots = visible(slotsFor(current))
            if let first = slots.firstIndex(where: { !$0.holdings.isEmpty }) { page = first / Self.perPage }
        }
    }

    private func load(_ setId: String) async {
        guard checklists[setId] == nil, failed[setId] == nil else { return }
        // Demo sets aren't in the catalog: they show the cards you own.
        guard store.demo == nil, !Demo.isOn else { failed[setId] = ""; return }
        do {
            let detail = try await Backend.shared.api.exploreSet(setId)
            if !detail.set.loaded { failed[setId] = "This set's card list loads in an upcoming daily catalog sync."; return }
            checklists[setId] = detail.products.filter { !$0.product.isSealed }
                .sorted { ($0.product.number ?? "~").localizedStandardCompare($1.product.number ?? "~") == .orderedAscending }
        } catch {
            failed[setId] = "Couldn't load this set's checklist."
        }
    }

    // MARK: Top

    private func header(_ sets: [OwnedSet]) -> some View {
        let count = sets.reduce(0) { $0 + $1.count }
        return VStack(alignment: .leading, spacing: 10) {
            MonoLabel(text: "Your binder")
            HStack(alignment: .lastTextBaseline, spacing: 10) {
                CountingText(value: count, format: { "\(Int($0.rounded()))" })
                    .font(.display(64)).monospacedDigit().displayTrim(64)
                Text("single\(count == 1 ? "" : "s") across \(sets.count) set\(sets.count == 1 ? "" : "s")")
                    .font(.geist(16, .medium)).foregroundStyle(Theme.muted)
            }
        }
        .padding(.top, 8)
    }

    // MARK: Set tiles

    private func ownedCount(_ s: OwnedSet) -> (owned: Int, total: Int?) {
        guard let list = checklists[s.id], !list.isEmpty else { return (Set(s.holdings.map(\.identity.productId)).count, nil) }
        let ids = Set(list.map(\.product.id))
        return (Set(s.holdings.map(\.identity.productId)).filter { ids.contains($0) }.count, list.count)
    }

    /// A set: its best card, its name and how many you have. Only the chosen one is filled.
    private func setTile(_ s: OwnedSet, active: Bool) -> some View {
        let (owned, total) = ownedCount(s)
        return Button {
            selected = s.id
            page = 0
        } label: {
            HStack(spacing: 10) {
                HoldingArt(product: s.cover?.product, identity: s.cover?.identity, cornerRadius: 3, caption: false)
                    .frame(width: 30, height: 42)
                VStack(alignment: .leading, spacing: 3) {
                    Text(s.name).font(.geist(14, .semibold)).lineLimit(1)
                    Text(total.map { "\(owned) of \($0)" } ?? "\(owned) card\(owned == 1 ? "" : "s")")
                        .font(.geist(12)).monospacedDigit().foregroundStyle(Theme.muted)
                }
                .frame(maxWidth: 150, alignment: .leading)
            }
            .padding(.horizontal, 10).padding(.vertical, 8)
            .background(active ? Theme.surface2 : .clear, in: RoundedRectangle(cornerRadius: 12, style: .continuous))
            .overlay(RoundedRectangle(cornerRadius: 12, style: .continuous).strokeBorder(active ? Theme.borderStrong : Theme.border))
        }
        .buttonStyle(.plain)
    }

    // MARK: The book

    private func slotsFor(_ set: OwnedSet) -> [Slot] {
        var byProduct: [String: [HoldingView]] = [:]
        for h in set.holdings { byProduct[h.identity.productId, default: []].append(h) }
        let own = { (hs: [HoldingView]) in Slot(hit: SearchHit(product: hs[0].product!, printing: hs[0].identity.printing, market: hs[0].price), holdings: hs) }
        guard let list = checklists[set.id] else {
            return byProduct.values.map(own).sorted { ($0.hit.product.number ?? "~").localizedStandardCompare($1.hit.product.number ?? "~") == .orderedAscending }
        }
        let listed = Set(list.map(\.product.id))
        // Owned cards the checklist doesn't list (promos) go at the end.
        return list.map { Slot(hit: $0, holdings: byProduct[$0.product.id] ?? []) } + byProduct.filter { !listed.contains($0.key) }.values.map(own)
    }

    private func visible(_ slots: [Slot]) -> [Slot] {
        switch show {
        case .all: return slots
        case .owned: return slots.filter { !$0.holdings.isEmpty }
        case .missing: return slots.filter { $0.holdings.isEmpty }
        }
    }

    private func book(_ set: OwnedSet) -> some View {
        let slots = slotsFor(set)
        let shown = visible(slots)
        let pages = max(1, Int((Double(shown.count) / Double(Self.perPage)).rounded(.up)))
        let missing = slots.filter { $0.holdings.isEmpty }
        let missingPriced = missing.filter { $0.hit.market != nil }
        let toComplete = missingPriced.reduce(0) { $0 + ($1.hit.market ?? 0) }
        let (owned, total) = ownedCount(set)
        return VStack(alignment: .leading, spacing: 18) {
            VStack(alignment: .leading, spacing: 10) {
                DisplayText(text: set.name.uppercased(), size: 30)
                if let total {
                    HStack(alignment: .firstTextBaseline) {
                        (Text("\(owned)").foregroundColor(.white).fontWeight(.semibold) + Text(" of \(total) collected").foregroundColor(Theme.muted))
                        Spacer()
                        Text("\(Int((Double(owned) / Double(max(total, 1)) * 100).rounded()))%").font(.geist(14, .semibold)).monospacedDigit().foregroundStyle(Theme.lime)
                    }
                    .font(.geist(14)).monospacedDigit()
                    GrowBar(fraction: Double(owned) / Double(max(total, 1)), color: Theme.lime, height: 6, gradient: false)
                    if !missingPriced.isEmpty {
                        (Text("Complete it for about ").foregroundColor(Theme.muted) + Text(Format.money(toComplete)).foregroundColor(.white))
                            .font(.geist(13)).monospacedDigit()
                    }
                } else {
                    Text("\(owned) card\(owned == 1 ? "" : "s") you own").font(.geist(14)).foregroundStyle(Theme.muted)
                }
            }
            if total != nil {
                ChipPicker(options: Show.allCases.map { ($0, $0.rawValue) }, selection: Binding(get: { show }, set: { show = $0; page = 0 }))
            }
            if let error = failed[set.id], !error.isEmpty {
                Text("\(error) Showing the cards you own.").font(.geist(13)).foregroundStyle(Theme.muted)
            }

            // Nine pockets a page; swipe to turn.
            VStack(spacing: 14) {
                TabView(selection: Binding(get: { min(page, pages - 1) }, set: { page = $0 })) {
                    ForEach(0..<pages, id: \.self) { p in
                        sheet(Array(shown.dropFirst(p * Self.perPage).prefix(Self.perPage)))
                            .tag(p)
                    }
                }
                .tabViewStyle(.page(indexDisplayMode: .never))
                .aspectRatio(0.71, contentMode: .fit)
                if pages > 1 {
                    HStack(spacing: 6) {
                        ForEach(0..<min(pages, 12), id: \.self) { p in
                            Capsule().fill(p == min(page, pages - 1) ? Color.white : Theme.surface3)
                                .frame(width: p == min(page, pages - 1) ? 18 : 6, height: 6)
                        }
                        if pages > 12 { Text("+\(pages - 12)").font(.geist(11)).foregroundStyle(Theme.subtle) }
                    }
                    .animation(.spring(response: 0.35, dampingFraction: 0.8), value: page)
                    .frame(maxWidth: .infinity)
                }
            }

            if total != nil, !missingPriced.isEmpty {
                VStack(alignment: .leading, spacing: 14) {
                    MoreHeading(title: "Most valuable missing", subtitle: "What it would take to finish \(set.name)")
                    VStack(spacing: 0) {
                        ForEach(missingPriced.sorted { ($0.hit.market ?? 0) > ($1.hit.market ?? 0) }.prefix(8)) { s in
                            NavigationLink(value: s.hit.product.id) {
                                HStack(spacing: 12) {
                                    ProductImage(product: s.hit.product, cornerRadius: 3).frame(width: 36, height: 50)
                                    VStack(alignment: .leading, spacing: 2) {
                                        Text(s.hit.product.name).font(.geist(14, .medium)).lineLimit(1)
                                        Text([s.hit.product.number.map { "#\($0)" }, s.hit.product.rarity].compactMap { $0 }.joined(separator: " · "))
                                            .font(.geist(12)).foregroundStyle(Theme.muted).lineLimit(1)
                                    }
                                    Spacer(minLength: 8)
                                    Text(Format.money(s.hit.market)).font(.geist(14, .semibold)).monospacedDigit()
                                    Image(systemName: "chevron.right").font(.system(size: 11, weight: .semibold)).foregroundStyle(Theme.subtle)
                                }
                                .padding(.vertical, 8)
                                .contentShape(Rectangle())
                            }
                            .buttonStyle(.plain)
                            .simultaneousGesture(TapGesture().onEnded { store.seed(s.hit) })
                        }
                    }
                    .surface(radius: 16, padding: 14)
                }
                .padding(.top, 8)
            }
        }
    }

    /// A page of nine pockets.
    private func sheet(_ chunk: [Slot]) -> some View {
        LazyVGrid(columns: Array(repeating: GridItem(.flexible(), spacing: 8), count: 3), spacing: 8) {
            ForEach(0..<Self.perPage, id: \.self) { i in
                if i < chunk.count {
                    let slot = chunk[i]
                    NavigationLink(value: slot.hit.product.id) { pocket(slot) }
                        .buttonStyle(.plain)
                        .simultaneousGesture(TapGesture().onEnded { if slot.holdings.isEmpty { store.seed(slot.hit) } })
                        .popIn(delay: Double(i) * 0.03)
                } else {
                    Color.clear.aspectRatio(63 / 88, contentMode: .fit)
                }
            }
        }
    }

    @ViewBuilder private func pocket(_ slot: Slot) -> some View {
        if let h = slot.holdings.first {
            let qty = slot.holdings.reduce(0) { $0 + $1.quantity }
            Color.clear
                .aspectRatio(63 / 88, contentMode: .fit)
                .overlay { HoldingArt(product: h.product, identity: h.identity, cornerRadius: 4, caption: false) }
                .overlay(alignment: .bottomTrailing) {
                    if qty > 1 {
                        Text("×\(Int(qty))").font(.geist(11, .semibold)).monospacedDigit()
                            .padding(.horizontal, 6).padding(.vertical, 2)
                            .background(Theme.background.opacity(0.85), in: Capsule())
                            .padding(5)
                    }
                }
        } else {
            // An empty pocket: a faint outline with the card's number, its picture barely there.
            ZStack {
                RoundedRectangle(cornerRadius: 6, style: .continuous)
                    .strokeBorder(Color.white.opacity(0.1), style: StrokeStyle(lineWidth: 1, dash: [4, 4]))
                ProductImage(product: slot.hit.product, cornerRadius: 4)
                    .padding(8).grayscale(1).opacity(0.08)
                VStack(spacing: 4) {
                    Text("#\(slot.hit.product.number ?? "—")").font(.mono(11)).foregroundStyle(Theme.subtle)
                    if let m = slot.hit.market { Text(Format.money(m)).font(.geist(11)).monospacedDigit().foregroundStyle(Theme.muted) }
                }
            }
            .aspectRatio(63 / 88, contentMode: .fit)
        }
    }
}
