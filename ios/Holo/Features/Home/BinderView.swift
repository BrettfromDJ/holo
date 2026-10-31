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
            VStack(alignment: .leading, spacing: 24) {
                MoreHero(label: "Singles in your binder", value: store.holdings.filter { $0.product?.isSealed == false }.reduce(0) { $0 + $1.quantity },
                         format: { "\(Int($0.rounded()))" }, tint: Theme.lime) {
                    Text("Page by page, set by set, with what's missing from each").font(.geist(14)).foregroundStyle(Theme.muted)
                }
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
        guard !setId.hasPrefix("sample"), store.demo == nil, !Demo.isOn else { failed[setId] = ""; return }
        do {
            let detail = try await Backend.shared.api.exploreSet(setId)
            if !detail.set.loaded { failed[setId] = "This set's card list loads in an upcoming daily catalog sync."; return }
            checklists[setId] = detail.products.filter { !$0.product.isSealed }
                .sorted { ($0.product.number ?? "~").localizedStandardCompare($1.product.number ?? "~") == .orderedAscending }
        } catch {
            failed[setId] = "Couldn't load this set's checklist."
        }
    }

    // MARK: Set tiles

    private func setTile(_ s: OwnedSet, active: Bool) -> some View {
        let list = checklists[s.id]
        let owned = list.map { l in Set(s.holdings.map(\.identity.productId)).filter { id in l.contains { $0.product.id == id } }.count } ?? s.holdings.count
        let ratio: Double? = (list?.isEmpty ?? true) ? nil : Double(owned) / Double(list!.count)
        return Button {
            selected = s.id
            page = 0
        } label: {
            HStack(spacing: 12) {
                CompletionRing(ratio: ratio)
                VStack(alignment: .leading, spacing: 2) {
                    Text(s.name).font(.geist(14, .semibold)).lineLimit(1)
                    Text("\(owned) / \(list.map { "\($0.count)" } ?? "?") cards").font(.geist(12)).monospacedDigit().foregroundStyle(Theme.muted)
                    if let ratio, ratio >= 1 { Text("Complete").font(.geist(11, .semibold)).foregroundStyle(Theme.up) }
                }
                .frame(width: 140, alignment: .leading)
            }
            .padding(12)
            .background(active ? Theme.surface2 : Theme.surface, in: RoundedRectangle(cornerRadius: 18, style: .continuous))
            .overlay(RoundedRectangle(cornerRadius: 18, style: .continuous).strokeBorder(active ? Theme.borderStrong : Theme.border))
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
        let hasList = checklists[set.id] != nil
        return VStack(alignment: .leading, spacing: 14) {
            VStack(alignment: .leading, spacing: 4) {
                DisplayText(text: set.name.uppercased(), size: 28)
                (Text("\(slots.count - missing.count) of \(hasList ? "\(slots.count)" : "?") collected")
                 + Text(hasList && !missingPriced.isEmpty ? " · complete it for about " : "")
                 + Text(hasList && !missingPriced.isEmpty ? Format.money(toComplete) : "").foregroundColor(.white))
                    .font(.geist(13)).monospacedDigit().foregroundStyle(Theme.muted)
            }
            ChipPicker(options: Show.allCases.map { ($0, $0.rawValue) }, selection: Binding(get: { show }, set: { show = $0; page = 0 }))
            if let error = failed[set.id], !error.isEmpty {
                Text("\(error) Showing the cards you own.").font(.geist(13)).foregroundStyle(Theme.muted)
                    .padding(12).frame(maxWidth: .infinity, alignment: .leading)
                    .background(Theme.surface, in: RoundedRectangle(cornerRadius: 12, style: .continuous))
            }

            VStack(spacing: 12) {
                // One sheet of nine pockets per page; swipe to turn.
                TabView(selection: Binding(get: { min(page, pages - 1) }, set: { page = $0 })) {
                    ForEach(0..<pages, id: \.self) { p in
                        sheet(Array(shown.dropFirst(p * Self.perPage).prefix(Self.perPage)))
                            .tag(p)
                    }
                }
                .tabViewStyle(.page(indexDisplayMode: .never))
                .aspectRatio(0.74, contentMode: .fit)
                HStack {
                    Button { withAnimation { page = max(0, page - 1) } } label: { Label("Prev", systemImage: "chevron.left") }
                        .disabled(page == 0)
                    Spacer()
                    Text("Page \(min(page, pages - 1) + 1) of \(pages)").font(.geist(12)).monospacedDigit().foregroundStyle(Theme.muted)
                    Spacer()
                    Button { withAnimation { page = min(pages - 1, page + 1) } } label: { Label("Next", systemImage: "chevron.right").labelStyle(TrailingIcon()) }
                        .disabled(page >= pages - 1)
                }
                .font(.geist(13, .medium))
                .foregroundStyle(.white)
            }
            .padding(12)
            .background(
                RoundedRectangle(cornerRadius: 26, style: .continuous)
                    .fill(LinearGradient(colors: [Color(hex: 0x1C1C20), Color(hex: 0x121214)], startPoint: .top, endPoint: .bottom))
            )
            .overlay(RoundedRectangle(cornerRadius: 26, style: .continuous).strokeBorder(Theme.borderStrong))

            if hasList, !missingPriced.isEmpty {
                VStack(alignment: .leading, spacing: 10) {
                    MoreHeading(title: "Most valuable missing", subtitle: "What it would take to finish \(set.name)")
                    ForEach(missingPriced.sorted { ($0.hit.market ?? 0) > ($1.hit.market ?? 0) }.prefix(8)) { s in
                        NavigationLink(value: s.hit.product.id) {
                            HStack(spacing: 12) {
                                ProductImage(product: s.hit.product, cornerRadius: 5).frame(width: 40, height: 56)
                                VStack(alignment: .leading, spacing: 2) {
                                    Text(s.hit.product.name).font(.geist(14, .medium)).lineLimit(1)
                                    Text([s.hit.product.number.map { "#\($0)" }, s.hit.product.rarity].compactMap { $0 }.joined(separator: " · "))
                                        .font(.geist(12)).foregroundStyle(Theme.muted).lineLimit(1)
                                }
                                Spacer(minLength: 8)
                                Text(Format.money(s.hit.market)).font(.geist(14, .semibold)).monospacedDigit()
                                Image(systemName: "plus").font(.system(size: 12, weight: .semibold)).foregroundStyle(Theme.subtle)
                            }
                            .padding(10)
                            .background(Theme.surface, in: RoundedRectangle(cornerRadius: 16, style: .continuous))
                        }
                        .buttonStyle(.plain)
                        .simultaneousGesture(TapGesture().onEnded { store.seed(s.hit) })
                    }
                }
                .padding(.top, 12)
            }
        }
    }

    /// A plastic sheet of nine pockets.
    private func sheet(_ chunk: [Slot]) -> some View {
        LazyVGrid(columns: Array(repeating: GridItem(.flexible(), spacing: 6), count: 3), spacing: 6) {
            ForEach(0..<Self.perPage, id: \.self) { i in
                if i < chunk.count {
                    let slot = chunk[i]
                    NavigationLink(value: slot.hit.product.id) { pocket(slot) }
                        .buttonStyle(.plain)
                        .popIn(delay: Double(i) * 0.04)
                        .simultaneousGesture(TapGesture().onEnded { if slot.holdings.isEmpty { store.seed(slot.hit) } })
                } else {
                    pocketShape.fill(Color.white.opacity(0.03)).aspectRatio(63 / 88, contentMode: .fit)
                }
            }
        }
        .padding(8)
        .background(RoundedRectangle(cornerRadius: 14, style: .continuous).fill(Color.white.opacity(0.03)))
    }

    private var pocketShape: RoundedRectangle { RoundedRectangle(cornerRadius: 8, style: .continuous) }

    @ViewBuilder private func pocket(_ slot: Slot) -> some View {
        if let h = slot.holdings.first {
            let qty = slot.holdings.reduce(0) { $0 + $1.quantity }
            HoldingArt(product: h.product, identity: h.identity, cornerRadius: 5, caption: false)
                .padding(4)
                .aspectRatio(63 / 88, contentMode: .fit)
                .background(pocketShape.fill(Color.white.opacity(0.05)))
                // The sleeve's glare over the card.
                .overlay(pocketShape.fill(LinearGradient(colors: [.white.opacity(0.10), .clear, .white.opacity(0.04)], startPoint: .topLeading, endPoint: .bottomTrailing)).allowsHitTesting(false))
                .overlay(alignment: .topTrailing) {
                    if qty > 1 {
                        Text("×\(Int(qty))").font(.geist(10, .semibold)).monospacedDigit()
                            .padding(.horizontal, 5).padding(.vertical, 1)
                            .background(.black.opacity(0.75), in: Capsule()).padding(6)
                    }
                }
                .overlay(alignment: .bottomLeading) {
                    if let label = h.label {
                        Text(label).font(.geist(10, .medium)).padding(.horizontal, 5).padding(.vertical, 1)
                            .background(.black.opacity(0.75), in: Capsule()).padding(6)
                    }
                }
        } else {
            ZStack {
                pocketShape.fill(Color.white.opacity(0.03))
                pocketShape.strokeBorder(Color.white.opacity(0.06))
                ProductImage(product: slot.hit.product, cornerRadius: 4)
                    .padding(6).grayscale(1).opacity(0.12)
                VStack(spacing: 3) {
                    Text("#\(slot.hit.product.number ?? "—")").font(.geist(11, .semibold)).monospacedDigit().foregroundStyle(Theme.subtle)
                    Text(slot.hit.product.name).font(.geist(10)).foregroundStyle(Theme.subtle).multilineTextAlignment(.center).lineLimit(2).padding(.horizontal, 4)
                    if let m = slot.hit.market { Text(Format.money(m)).font(.geist(10)).monospacedDigit().foregroundStyle(Theme.muted) }
                }
            }
            .aspectRatio(63 / 88, contentMode: .fit)
        }
    }
}

/// "Next ›": the icon after the title.
private struct TrailingIcon: LabelStyle {
    func makeBody(configuration: Configuration) -> some View {
        HStack(spacing: 4) { configuration.title; configuration.icon }
    }
}

/// How complete a set is: a lime ring that sweeps round when it appears, with the share inside.
private struct CompletionRing: View {
    var ratio: Double?
    @Environment(\.accessibilityReduceMotion) private var reduceMotion
    @State private var drawn = false

    var body: some View {
        ZStack {
            Circle().stroke(Theme.surface3, lineWidth: 5)
            Circle().trim(from: 0, to: (ratio ?? 0) * (drawn || reduceMotion ? 1 : 0))
                .stroke(Theme.lime, style: StrokeStyle(lineWidth: 5, lineCap: .round))
                .rotationEffect(.degrees(-90))
                .shadow(color: Theme.lime.opacity(0.5), radius: 4)
            Text(ratio.map { "\(Int(($0 * 100).rounded()))%" } ?? "—").font(.geist(11, .semibold)).monospacedDigit()
        }
        .frame(width: 50, height: 50)
        .onAppear {
            guard !reduceMotion, !drawn else { return }
            withAnimation(.easeOut(duration: 1.0).delay(0.2)) { drawn = true }
        }
        .onChange(of: ratio) { _, _ in
            guard !reduceMotion else { return }
            drawn = false
            withAnimation(.easeOut(duration: 1.0)) { drawn = true }
        }
    }
}
