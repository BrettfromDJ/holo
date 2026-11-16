import SwiftUI

/// The new Home (a trial, see `Labs`): what's happening across the hobby, not your collection.
/// The card of the week, the hottest and coldest movers, the top 10 risers, the newest set's
/// chase cards, hot sealed and sets just out and coming (from the prices Dexora stores, sent
/// with Explore's index).
/// One strip at the top for you: your collection's worth, tapping through to Collection.
struct MarketHomeView: View {
    @Environment(CollectionStore.self) private var store
    @State private var index: ExploreIndex?
    @State private var fresh = false
    /// The newest set's most valuable singles.
    @State private var chase: (set: ExploreSet, hits: [SearchHit])?
    @State private var path = NavigationPath()

    private var today: String { Format.day() }
    private var upcoming: [ExploreSet] {
        (index?.sets ?? []).filter { ($0.releaseDate ?? "") >= today }.sorted { ($0.releaseDate ?? "") < ($1.releaseDate ?? "") }
    }
    private var recent: [ExploreSet] {
        (index?.sets ?? []).filter { ($0.releaseDate ?? "") < today && $0.releaseDate != nil }.sorted { ($0.releaseDate ?? "") > ($1.releaseDate ?? "") }
    }

    var body: some View {
        NavigationStack(path: $path) {
            ScrollView {
                VStack(alignment: .leading, spacing: 40) {
                    VStack(alignment: .leading, spacing: 16) {
                        PageHeader(title: "What's happening", subtitle: "Prices and sets across the hobby this\u{00A0}week", size: 34)
                        if store.status == .ready, !store.holdings.isEmpty { YourCollectionStrip() }
                    }
                    .padding(.horizontal, 16)
                    .padding(.top, 8)
                    if let index {
                        sections(index)
                    } else {
                        // First visit only (later ones open on the saved copy): dim, still shapes.
                        VStack(alignment: .leading, spacing: 14) {
                            ForEach(0..<3, id: \.self) { _ in
                                RoundedRectangle(cornerRadius: 6).fill(Color.white.opacity(0.06)).frame(width: 160, height: 20)
                                HStack(spacing: 12) {
                                    ForEach(0..<3, id: \.self) { _ in
                                        RoundedRectangle(cornerRadius: 8).fill(Color.white.opacity(0.05)).frame(width: 96, height: 134)
                                    }
                                }
                            }
                        }
                        .padding(.horizontal, 16)
                    }
                }
                .padding(.bottom, 40)
            }
            .background(alignment: .top) {
                // The lit grid of the other tops, fading out down the page.
                GridPattern(step: 28, opacity: 0.05)
                    .frame(height: 420)
                    .mask(LinearGradient(colors: [.black, .clear], startPoint: .top, endPoint: .bottom))
                    .ignoresSafeArea(edges: .top)
            }
            .background(Theme.background)
            .tabTopReset("home", path: $path)
            .tabBarClearance()
            .imageMaxPixel(480)
            .refreshable { fresh = false; await load() }
            .pageTitle("Home")
            .navigationDestination(for: String.self) { ProductDetailView(productId: $0) }
            .navigationDestination(for: ExploreSet.self) { SetView(set: $0) }
            .navigationDestination(for: ExploreRoute.self) { _ in ReleaseCalendarView(sets: index?.sets ?? []) }
            .task { await load() }
        }
    }

    @ViewBuilder private func sections(_ index: ExploreIndex) -> some View {
        let upcoming = self.upcoming
        let recent = self.recent
        let trending = index.trending ?? []
        let drops = index.drops ?? []
        // The week's top riser gets the big stage; the next riser and the biggest faller face off.
        if let star = trending.first {
            CardOfTheWeek(hit: star).padding(.horizontal, 16).reveal()
        }
        if trending.count > 1 || !drops.isEmpty {
            HStack(spacing: 10) {
                if trending.count > 1 { HotColdTile(hit: trending[1], hot: true) }
                if let cold = drops.first { HotColdTile(hit: cold, hot: false) }
            }
            .padding(.horizontal, 16)
            .reveal()
        }
        if trending.count > 2 {
            section("Top 10 this week", "Singles rising most in 7 days") { TopTenRow(hits: Array(trending.prefix(10))) }
        }
        if let next = upcoming.first {
            // The next set out, with its countdown and reminder (Explore's top card).
            CatalogHero(index: index, next: next)
        }
        if let chase, !chase.hits.isEmpty {
            NavigationLink(value: chase.set) { SetShowcase(set: chase.set, hits: Array(chase.hits.prefix(5))) }
                .buttonStyle(.plain)
                .padding(.horizontal, 16)
                .reveal()
        }
        if let hot = index.hotSealed, !hot.isEmpty {
            section("Hot sealed", "Sealed rising most in 7 days") { HotSealedRow(hits: Array(hot.prefix(10))) }
        }
        if !recent.isEmpty {
            section("Just released", "The newest sets") { SetCarousel(sets: Array(recent.prefix(10)), upcoming: false) }
        }
        if upcoming.count > 1 {
            section("Coming soon", "New sets on the way") {
                SetCarousel(sets: Array(upcoming.dropFirst().prefix(10)), upcoming: true)
            } link: {
                NavigationLink(value: ExploreRoute.calendar) { seeAll("Calendar") }
            }
        }
        if drops.count > 1 {
            section("Cooling off", "Singles down most in 7 days") { MoverCarousel(hits: Array(drops.dropFirst().prefix(10))) }
        }
    }

    private func section<C: View>(_ title: String, _ subtitle: String, @ViewBuilder content: () -> C) -> some View {
        section(title, subtitle, content: content) { EmptyView() }
    }

    private func section<C: View, L: View>(_ title: String, _ subtitle: String, @ViewBuilder content: () -> C, @ViewBuilder link: () -> L) -> some View {
        VStack(alignment: .leading, spacing: 14) {
            HStack(alignment: .lastTextBaseline) {
                PageHeader(title: title, subtitle: subtitle, size: 22)
                Spacer(minLength: 8)
                link()
            }
            .padding(.horizontal, 16)
            content()
        }
        .reveal()
    }

    private func seeAll(_ title: String) -> some View {
        HStack(spacing: 4) { Text(title); Image(systemName: "arrow.right").font(.system(size: 12, weight: .semibold)) }
            .font(.geist(13, .medium)).foregroundStyle(Theme.muted)
    }

    private func load() async {
        guard !fresh else { return }
        if Demo.isOn {
            if index == nil { index = DemoData.exploreIndex }
        } else {
            if index == nil, let saved = await Task.detached(priority: .userInitiated, operation: { SavedExplore.load() }).value { index = saved }
            if let loaded = try? await Backend.shared.api.exploreIndex() { index = loaded; fresh = true }
        }
        await loadChase()
    }

    /// The newest released set's ten most valuable singles (one request to our own server).
    private func loadChase() async {
        guard let newest = recent.first(where: { $0.loaded }) ?? recent.first else { return }
        let detail = Demo.isOn ? DemoData.exploreSet(newest.slug) : try? await Backend.shared.api.exploreSet(newest.slug)
        guard let detail else { return }
        let singles = detail.products.filter { !$0.product.isSealed && $0.market != nil && !SetView.looksSealed($0.product) }
        chase = (detail.set, Array(singles.sorted { ($0.market ?? 0) > ($1.market ?? 0) }.prefix(10)))
    }
}

/// Your collection in one line on Home: its worth and today's move, tapping through to Collection.
private struct YourCollectionStrip: View {
    @Environment(CollectionStore.self) private var store

    var body: some View {
        let s = store.summary
        Button { Router.shared.tabRequest = "collection" } label: {
            HStack(spacing: 10) {
                VStack(alignment: .leading, spacing: 2) {
                    MonoLabel(text: "Your collection")
                    Text(Format.money(s.value)).font(.display(22)).tracking(-0.6).monospacedDigit().foregroundStyle(.white)
                }
                Spacer(minLength: 8)
                VStack(alignment: .trailing, spacing: 2) {
                    MonoLabel(text: "Today")
                    Text(Format.signedMoney(s.dayChange)).font(.geist(15, .semibold)).monospacedDigit().foregroundStyle(Theme.tone(s.dayChange))
                }
                Image(systemName: "chevron.right").font(.system(size: 13, weight: .semibold)).foregroundStyle(Theme.muted)
            }
            .padding(.horizontal, 16).padding(.vertical, 12)
            .liquidGlass(in: RoundedRectangle(cornerRadius: 18, style: .continuous))
        }
        .buttonStyle(.plain)
    }
}

// MARK: - The highlight pieces

/// A stored percent change (12.5 = +12.5%) as signed text, lime up and pink down.
private func pctText(_ pct: Double?) -> String { pct.map { Format.signedPercent($0 / 100) } ?? "—" }
private func pctTint(_ pct: Double?) -> Color { (pct ?? 0) >= 0 ? Theme.lime : Theme.planPink }

/// The week's top riser on the big stage: the card drifting and shining with sparks behind it,
/// its rise in huge figures, inside the electric border of the set page's No. 1 chase.
private struct CardOfTheWeek: View {
    var hit: SearchHit

    var body: some View {
        let p = hit.pictured
        let shape = RoundedRectangle(cornerRadius: 28, style: .continuous)
        MarketLink(hit: hit) {
            VStack(spacing: 18) {
                SkewTag(text: "Card of the week", icon: "flame.fill")
                HoloCard(foil: p.isFoil, textured: false, cornerRadius: 10) {
                    ProductImage(product: p, cornerRadius: 10, large: true).frame(width: 190, height: 265)
                }
                .drifting()
                .notTiltable()
                .frame(width: 190, height: 265)
                VStack(spacing: 6) {
                    Text(p.name.noWidow).font(.display(24)).tracking(-0.6).multilineTextAlignment(.center).lineLimit(2)
                    Text([p.setName, p.rarity].compactMap { $0 }.joined(separator: " · ")).font(.geist(13)).foregroundStyle(Theme.muted).lineLimit(1)
                }
                HStack(alignment: .firstTextBaseline, spacing: 14) {
                    Text(Format.money(hit.market)).font(.display(40)).tracking(-1.4).monospacedDigit().displayTrim(40)
                    VStack(alignment: .leading, spacing: 0) {
                        Text(pctText(hit.change7dPct)).font(.display(26)).tracking(-0.6).monospacedDigit().foregroundStyle(pctTint(hit.change7dPct))
                            .shadow(color: pctTint(hit.change7dPct).opacity(0.5), radius: 10)
                        Text("THIS WEEK").font(.mono(10)).tracking(1.2).foregroundStyle(Theme.subtle)
                    }
                }
            }
            .foregroundStyle(.white)
            .padding(.vertical, 26).padding(.horizontal, 18)
            .frame(maxWidth: .infinity)
            .background {
                ZStack {
                    shape.fill(Color(hex: 0x070707))
                    GridPattern(step: 28, opacity: 0.07)
                    RadialGradient(colors: [Theme.lime.opacity(0.28), .clear], center: UnitPoint(x: 0.5, y: 0.36), startRadius: 0, endRadius: 260)
                    RadialGradient(colors: [Theme.planPink.opacity(0.16), .clear], center: .bottomTrailing, startRadius: 0, endRadius: 220)
                    ChaseSparks()
                }
                .clipShape(shape)
            }
            .shadow(color: Theme.lime.opacity(0.18), radius: 22)
            .overlay(ElectricBorder(radius: 28))
        }
    }
}

/// Hot (the next riser, in fire) or cold (the biggest faller, in ice): the card tilted on a
/// glow of its color, the change big underneath.
private struct HotColdTile: View {
    var hit: SearchHit
    var hot: Bool

    var body: some View {
        let glow = hot ? Color(hex: 0xFF7A1A) : Color(hex: 0x7DD3FC)
        let shape = RoundedRectangle(cornerRadius: 22, style: .continuous)
        MarketLink(hit: hit) {
            VStack(alignment: .leading, spacing: 10) {
                HStack(spacing: 5) {
                    Image(systemName: hot ? "flame.fill" : "snowflake").font(.system(size: 11, weight: .bold)).foregroundStyle(glow)
                    Text(hot ? "HEATING UP" : "COOLING OFF").font(.mono(10)).tracking(1.2).foregroundStyle(.white.opacity(0.8))
                }
                ProductImage(product: hit.pictured, cornerRadius: 6)
                    .frame(width: 84, height: 117)
                    .rotationEffect(.degrees(hot ? -6 : 6))
                    .shadow(color: glow.opacity(0.55), radius: 16)
                    .frame(maxWidth: .infinity)
                    .padding(.vertical, 4)
                Text(hit.product.name).font(.geist(13, .medium)).lineLimit(1)
                HStack(alignment: .firstTextBaseline) {
                    Text(Format.money(hit.market)).font(.display(17)).tracking(-0.4).monospacedDigit().lineLimit(1).minimumScaleFactor(0.7)
                    Spacer(minLength: 4)
                    Text(pctText(hit.change7dPct)).font(.display(17)).tracking(-0.4).monospacedDigit().foregroundStyle(pctTint(hit.change7dPct))
                }
            }
            .foregroundStyle(.white)
            .padding(14)
            .frame(maxWidth: .infinity, alignment: .leading)
            .background {
                ZStack {
                    shape.fill(Color(hex: 0x080808))
                    RadialGradient(colors: [glow.opacity(0.32), .clear], center: UnitPoint(x: 0.5, y: 0.42), startRadius: 0, endRadius: 130)
                }
                .clipShape(shape)
            }
            .overlay(shape.strokeBorder(glow.opacity(0.35), lineWidth: 1))
        }
    }
}

/// The top 10 risers, each card standing in front of its rank in huge numerals.
private struct TopTenRow: View {
    var hits: [SearchHit]

    var body: some View {
        ScrollView(.horizontal, showsIndicators: false) {
            HStack(alignment: .top, spacing: 18) {
                ForEach(Array(hits.enumerated()), id: \.element.id) { i, hit in
                    MarketLink(hit: hit) {
                        VStack(alignment: .leading, spacing: 8) {
                            ZStack(alignment: .bottomLeading) {
                                Text("\(i + 1)")
                                    .font(.display(130)).tracking(-8)
                                    .foregroundStyle(LinearGradient(colors: [.white.opacity(0.22), .white.opacity(0.04)], startPoint: .top, endPoint: .bottom))
                                    .offset(x: -6, y: 22)
                                ProductImage(product: hit.pictured, cornerRadius: 6)
                                    .frame(width: 100, height: 140)
                                    .shadow(color: .black.opacity(0.6), radius: 10, y: 6)
                                    .padding(.leading, i + 1 >= 10 ? 70 : 46)
                            }
                            .frame(height: 150, alignment: .bottomLeading)
                            VStack(alignment: .leading, spacing: 2) {
                                Text(hit.product.name).font(.geist(13, .medium)).lineLimit(1)
                                HStack(spacing: 6) {
                                    Text(Format.money(hit.market)).font(.display(15)).tracking(-0.3).monospacedDigit()
                                    Text(pctText(hit.change7dPct)).font(.geist(12, .semibold)).monospacedDigit().foregroundStyle(pctTint(hit.change7dPct))
                                }
                            }
                            .padding(.leading, i + 1 >= 10 ? 70 : 46)
                            .frame(width: (i + 1 >= 10 ? 70 : 46) + 100, alignment: .leading)
                        }
                        .foregroundStyle(.white)
                    }
                }
            }
            .padding(.horizontal, 16)
            .padding(.vertical, 4)
        }
    }
}

/// The newest set on stage: its art behind, its chase cards fanned out in front, and the top
/// pull's price. Opens the set.
private struct SetShowcase: View {
    var set: ExploreSet
    var hits: [SearchHit]

    var body: some View {
        let shape = RoundedRectangle(cornerRadius: 26, style: .continuous)
        VStack(alignment: .leading, spacing: 16) {
            VStack(alignment: .leading, spacing: 6) {
                SkewTag(text: "Newest set", color: Theme.planBlue, textColor: .white, icon: "sparkles")
                Text("Chasing in \(set.name)").font(.display(26)).tracking(-0.7).lineLimit(2)
                if let top = hits.first {
                    Text("Top pull \(Format.money(top.market)) · \(top.product.name)").font(.geist(13)).foregroundStyle(.white.opacity(0.75)).lineLimit(1)
                }
            }
            // The chase cards in a fan, the top pull in the middle and highest.
            ZStack {
                let order = fanOrder
                ForEach(Array(order.enumerated()), id: \.offset) { slot, item in
                    let mid = Double(order.count - 1) / 2
                    let offset = Double(slot) - mid
                    ProductImage(product: item.hit.pictured, cornerRadius: 6)
                        .frame(width: 92, height: 128)
                        .shadow(color: .black.opacity(0.55), radius: 10, y: 6)
                        .rotationEffect(.degrees(offset * 9), anchor: .bottom)
                        .offset(x: offset * 46, y: abs(offset) * 10 - (item.rank == 0 ? 10 : 0))
                        .zIndex(item.rank == 0 ? 10 : 5 - abs(offset))
                }
            }
            .frame(maxWidth: .infinity)
            .frame(height: 170)
            HStack(spacing: 6) {
                Text("See the set").font(.geist(14, .semibold))
                Image(systemName: "arrow.right").font(.system(size: 12, weight: .semibold))
            }
            .foregroundStyle(Theme.lime)
        }
        .foregroundStyle(.white)
        .padding(20)
        .frame(maxWidth: .infinity, alignment: .leading)
        .background {
            ZStack {
                shape.fill(Color(hex: 0x070707))
                SetArt(set: set).opacity(0.45).blur(radius: 14)
                LinearGradient(colors: [Color.black.opacity(0.75), Color.black.opacity(0.35), Color.black.opacity(0.8)], startPoint: .top, endPoint: .bottom)
                RadialGradient(colors: [Theme.planBlue.opacity(0.28), .clear], center: UnitPoint(x: 0.5, y: 0.7), startRadius: 0, endRadius: 220)
            }
            .clipShape(shape)
        }
        .overlay(shape.strokeBorder(Color.white.opacity(0.1), lineWidth: 1))
    }

    /// Ranks laid out so the top pull sits in the middle: 3, 1, 0, 2, 4 for five cards.
    private var fanOrder: [(rank: Int, hit: SearchHit)] {
        let ranked = Array(hits.enumerated()).map { (rank: $0.offset, hit: $0.element) }
        var left: [(rank: Int, hit: SearchHit)] = [], right: [(rank: Int, hit: SearchHit)] = []
        for item in ranked.dropFirst() { if item.rank % 2 == 1 { left.insert(item, at: 0) } else { right.append(item) } }
        return left + Array(ranked.prefix(1)) + right
    }
}

/// Hot sealed, big: each product standing in its well with its rise as a lime tag.
private struct HotSealedRow: View {
    var hits: [SearchHit]

    var body: some View {
        ScrollView(.horizontal, showsIndicators: false) {
            HStack(alignment: .top, spacing: 12) {
                ForEach(hits) { hit in
                    MarketLink(hit: hit) {
                        VStack(alignment: .leading, spacing: 8) {
                            SealedWell(product: hit.product, cornerRadius: 22, caption: false)
                                .frame(width: 160, height: 160)
                                .overlay(alignment: .topLeading) {
                                    if let pct = hit.change7dPct, pct > 0 {
                                        SkewTag(text: pctText(pct), icon: "arrow.up.right").padding(10)
                                    }
                                }
                            Text(hit.product.name).font(.geist(13, .medium)).lineLimit(2).frame(width: 160, alignment: .leading)
                            Text(Format.money(hit.market)).font(.display(17)).tracking(-0.4).monospacedDigit()
                        }
                        .foregroundStyle(.white)
                    }
                }
            }
            .padding(.horizontal, 16)
            .padding(.vertical, 4)
        }
    }
}
