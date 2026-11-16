import SwiftUI

/// The new Home (a trial, see `Labs`): what's happening across the hobby, not your collection.
/// Trending and falling cards, hot sealed and booster boxes (from the prices Dexora stores,
/// sent with Explore's index), the newest set's chase cards, and sets just out and coming.
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
        if let trending = index.trending, !trending.isEmpty {
            section("Trending this week", "Singles rising most in 7 days") { MoverCarousel(hits: trending) }
        }
        if let next = upcoming.first {
            // The next set out, with its countdown and reminder (Explore's top card).
            CatalogHero(index: index, next: next)
        }
        if let chase, !chase.hits.isEmpty {
            section("Chasing in \(chase.set.name)", "The newest set's most valuable singles") {
                MoverCarousel(hits: chase.hits)
            } link: {
                NavigationLink(value: chase.set) { seeAll("Set") }
            }
        }
        if let hot = index.hotSealed, !hot.isEmpty {
            section("Hot sealed", "Sealed rising most in 7 days") { MoverCarousel(hits: hot, square: true) }
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
        if let drops = index.drops, !drops.isEmpty {
            section("Falling this week", "Singles down most in 7 days") { MoverCarousel(hits: drops) }
        }
        if let boxes = index.boosterBoxes, !boxes.isEmpty {
            VStack(alignment: .leading, spacing: 14) {
                PageHeader(title: "Booster boxes", subtitle: "Recent sets' boxes, by price", size: 22)
                BoosterBoxList(hits: Array(boxes.prefix(8))).surface(padding: nil)
            }
            .padding(.horizontal, 16)
            .reveal()
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
