import Charts
import SwiftUI

/// Home: what's happening across the hobby, not your collection (that's on Collection).
/// The card of the week, the hottest and coldest movers, the top 10 risers, the newest set's
/// chase cards, hot sealed and sets just out and coming (from the prices Dexora stores, sent
/// with Explore's index).
/// One strip at the top for you: your collection's worth, tapping through to Collection.
struct MarketHomeView: View {
    @Environment(CollectionStore.self) private var store
    /// Home's market lists: the copy saved last time (read as the app started), then fresh.
    @State private var index: ExploreIndex? = SavedExplore.preloaded
    /// "Today in the hobby" and why the highlighted cards moved (written daily by Claude).
    @State private var insights: MarketInsights? = MarketInsights.saved
    /// For you: picks from your collection (Because you collect…, Finish your sets).
    @State private var forYou = ForYouModel()
    /// How each era's market moved (Rising by era), kept on the phone between visits.
    @State private var eraSummaries: [EraSummary] = (UserDefaults.standard.data(forKey: "era-summaries")).flatMap { try? JSONDecoder().decode([EraSummary].self, from: $0) } ?? []
    /// Themed collections: a new few each time the app opens.
    @State private var themes = ThemesModel()
    @State private var fresh = false
    /// The newest set's most valuable singles.
    @State private var chase: (set: ExploreSet, hits: [SearchHit])?
    @State private var path = NavigationPath()
    /// The top-right menu of every main place in the app (as Overview had), and what it opens.
    @State private var menuOpen = false
    @State private var account = false
    @State private var recap = false
    @Environment(\.accessibilityReduceMotion) private var reduceMotion

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
                // Lazy: sections further down (and their pictures) load as you reach them, so the
                // Top 10 near the top isn't waiting in line behind pictures you can't see yet.
                LazyVStack(alignment: .leading, spacing: 32) {
                    // Straight in: your collection in one line, then the card of the day (no big
                    // heading taking the top of the screen).
                    if store.status == .ready, !store.holdings.isEmpty {
                        // 10pt above Card of the day, the same gap as between the three tiles
                        // under it (the page's sections are 32 apart).
                        // A little room under its chart, so Card of the day doesn't cut the chart's bottom off.
                        YourCollectionStrip().padding(.horizontal, 16).padding(.bottom, -10)
                    }
                    // Today in the hobby: three stories to swipe (the paragraph when there are none).
                    if let index, let stories = storiesToShow(index), !stories.isEmpty {
                        HobbyStories(stories: stories, cards: Self.cardsById(index))
                            // Closer to what follows than the page's usual section gap.
                            .padding(.bottom, -20)
                    } else if let briefing = insights?.briefing, index != nil {
                        HobbyBriefing(text: briefing).padding(.horizontal, 16).padding(.bottom, -18)
                    }
                    if let index {
                        sections(index)
                    } else {
                        // First visit only (later ones open on the saved copy): the name on the lit
                        // grid, still. No spinner, no grey boxes.
                        HomeLoading()
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
            .sparkRefresh { fresh = false; await load() }
            // Inline: a large-title bar left a tall empty band under "Home".
            .navigationBarTitleDisplayMode(.inline)
            .pageTitle("Home")
            .navigationDestination(for: String.self) { ProductDetailView(productId: $0) }
            // The menu's pages, pushed here (links inside them push on top).
            .navigationDestination(for: MorePage.self) { p in
                switch p {
                case .analytics, .gains:
                    ProOnly(reason: .analytics, title: "Analytics", line: "Gains with cost basis, realised and unrealised, your best and worst buys, and a tax export.", icon: "chart.pie") { AnalyticsView() }
                case .grading:
                    ProOnly(reason: .grading, title: "Grading", line: "Whether a card is worth grading, your submissions, costs and the return on each.", icon: "checkmark.seal") { GradingView() }
                case .masterSets: MasterSetsView()
                case .activity: ActivityView()
                case .sales: SalesView()
                case .lists: ListsHomeView()
                }
            }
            .navigationDestination(for: MarketTheme.self) { ThemePage(theme: $0) }
            .navigationDestination(for: MasterSetRoute.self) { MasterSetDetailView(setId: $0.id, setName: $0.name) }
            .navigationDestination(for: ListRoute.self) { route in
                switch route {
                case let .list(id): ListDetailView(listId: id)
                case .watchlist: ListsView(which: .watchlist, embedded: true)
                case .wishlist: ListsView(which: .wishlist, embedded: true)
                }
            }
            .toolbar {
                ToolbarItem(placement: .topBarTrailing) {
                    Button { setMenu(!menuOpen) } label: { Image(systemName: menuOpen ? "xmark" : "line.3.horizontal") }
                        .accessibilityLabel(menuOpen ? "Close menu" : "Menu")
                }
            }
            .overlay(alignment: .topTrailing) {
                if menuOpen {
                    ZStack(alignment: .topTrailing) {
                        // Tap anywhere else to close.
                        Color.black.opacity(0.35).ignoresSafeArea()
                            .contentShape(Rectangle())
                            .onTapGesture { setMenu(false) }
                        PlacesMenu(go: go)
                            .padding(.trailing, 12)
                            .padding(.top, 4)
                            .transition(.scale(scale: 0.92, anchor: .topTrailing).combined(with: .opacity))
                    }
                    .transition(.opacity)
                }
            }
            .onDisappear { if menuOpen { setMenu(false, animated: false) } }
            .sheet(isPresented: $account) { SettingsView() }
            // From a tapped notification ("sets nearly done"): Master Sets, on Home.
            .onChange(of: Router.shared.masterSetsRequest) { _, _ in path.append(MorePage.masterSets) }
            .fullScreenCover(isPresented: $recap) { WeeklyRecap(store: store) }
            .navigationDestination(for: ExploreSet.self) { SetView(set: $0) }
            .navigationDestination(for: ExploreRoute.self) { _ in ReleaseCalendarView(sets: index?.sets ?? []) }
            .task { await load() }
            // For you, worked out again when your collection changes.
            .task(id: "\(store.allHoldings.count)|\(store.status == .ready)|\(index != nil)") { await forYou.load(store: store, index: index) }
            .task(id: index != nil) {
                await themes.load(index: index)
                themes.pick(store: store, index: index)
            }
            // Your favourite Pokémon and era steer the mix once your collection is in.
            .onChange(of: store.allHoldings.count) { themes.pick(store: store, index: index) }
            .onChange(of: forYou.picks.map(\.id)) { themes.setNextFavorite(taste: forYou.taste, picks: forYou.picks) }
        }
    }

    @ViewBuilder private func sections(_ index: ExploreIndex) -> some View {
        let upcoming = self.upcoming
        let recent = self.recent
        let trending = index.trending ?? []
        let drops = index.drops ?? []
        // Today's top riser gets the big stage (the week's, until today's movers arrive); the
        // week's top riser and the biggest faller face off under it.
        // The three highlights as one group, 10pt apart every way (the same gap as between the
        // two small tiles), not the page's wider section spacing.
        // Card of the day leads Home, big and on its own.
        Group {
            if let star = index.today?.first {
                CardOfTheDay(hit: star, kind: .day, reason: insights?.reasons[star.product.id], fact: Self.fact(for: star, insights))
            } else if let star = trending.first {
                CardOfTheDay(hit: star, kind: .week, reason: insights?.reasons[star.product.id], fact: Self.fact(for: star, insights))
            } else if let chase, let top = chase.hits.first {
                // No market moves to show: the newest set's top pull takes the stage instead.
                CardOfTheDay(hit: top, kind: .topPull(chase.set.name))
            }
        }
        .padding(.horizontal, 16)
        // Then Collection of the Day.
        if let daily = themes.daily { DailyDiscovery(theme: daily) }
        // Heating up and Cooling off, side by side.
        if !trending.isEmpty || !drops.isEmpty {
            HStack(spacing: 10) {
                // The week's top risers (after Card of the day's, when that's the week's too) and
                // the biggest fallers, five each, cycling.
                let risers = Array((index.today?.first == nil ? Array(trending.dropFirst()) : trending).prefix(5))
                if !risers.isEmpty { HotColdTile(hits: risers, hot: true) }
                if !drops.isEmpty { HotColdTile(hits: Array(drops.prefix(5)), hot: false) }
            }
            .padding(.horizontal, 16)
        }
        // Themed collections between the market's own lists: rows of big cards, a spotlight
        // every fourth row.
        let shown = themes.shown
        themeRows(shown, 0..<3)
        if trending.count > 2 {
            section(icon: "trophy.fill", "Top 10 this week", "Singles rising most in 7 days") {
                TopTenRow(hits: Array(trending.prefix(10))).cardSequence(trending.prefix(10).map(\.product.id))
            }
        }
        themeRows(shown, 3..<5)
        // For you: your sets to finish and your week's budget.
        if forYou.hasContent {
            ForYouSection(model: forYou)
        }
            let modern = index.eras?.modern ?? [], midEra = index.eras?.midEra ?? [], vintage = index.eras?.vintage ?? []
            // One color card per era, like Collection's sealed and singles boxes: modern in lime,
            // mid-era in blue, vintage in pink. An era with no risers this week says so.
            let summaries = Demo.isOn ? EraSummaryCard.demo(index) : eraSummaries
            section(icon: "hourglass", "By era", summaries.isEmpty ? "This week's risers, from modern to vintage" : "How each era's market moved, and its biggest moves") {
                // Side by side, swiped one at a time; the next card peeks in at the edge.
                ScrollView(.horizontal, showsIndicators: false) {
                    HStack(alignment: .top, spacing: 12) {
                      if !summaries.isEmpty {
                        // Each era's whole market: its typical change, up and down, biggest moves.
                        ForEach(["modern", "midEra", "vintage"], id: \.self) { key in
                            if let sum = summaries.first(where: { $0.era == key }) { EraSummaryCard(summary: sum) }
                        }
                        // (The row below sizes to its tallest card; the others stretch to match.)
                      } else {
                        // Made-up risers stand in for an era with none yet (marked Sample).
                        // An era the server sent no risers for is filled with real risers of that era from
                        // Home's other lists (so every card opens its page); made-up samples only if none.
                        let m = modern.isEmpty ? Self.risers(in: "modern", index) : modern
                        let d = midEra.isEmpty ? Self.risers(in: "midEra", index) : midEra
                        let v = vintage.isEmpty ? Self.risers(in: "vintage", index) : vintage
                        EraCard(era: .modern, hits: m.isEmpty ? EraCard.sample(.modern) : m, sample: m.isEmpty)
                        EraCard(era: .midEra, hits: d.isEmpty ? EraCard.sample(.midEra) : d, sample: d.isEmpty)
                        EraCard(era: .vintage, hits: v)
                      }
                    }
                    // Every era card as tall as the fullest one, and no taller.
                    .fixedSize(horizontal: false, vertical: true)
                    .scrollTargetLayout()
                }
                .contentMargins(.horizontal, 16, for: .scrollContent)
                .scrollTargetBehavior(.viewAligned)
            }
        themeRows(shown, 5..<8)
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
            section(icon: "shippingbox.fill", "Hot sealed", "Sealed rising most in 7 days") { HotSealedRow(hits: Array(hot.prefix(10))) }
        }
        themeRows(shown, 8..<11)
        if !recent.isEmpty {
            section(icon: "calendar", "Just released", "The newest sets") { SetCarousel(sets: Array(recent.prefix(10)), upcoming: false) }
        }
        if upcoming.count > 1 {
            section(icon: "calendar.badge.clock", "Coming soon", "New sets on the way") {
                SetCarousel(sets: Array(upcoming.dropFirst().prefix(10)), upcoming: true)
            } link: {
                NavigationLink(value: ExploreRoute.calendar) { seeAll("Calendar") }
            }
        }
        themeRows(shown, 11..<shown.count)
        // Your lists last, as rows like the collections.
        if !Demo.isOn { HomeListRows() }
        // (A Cooling off row here repeated the Cooling off tile at the top: removed.)
    }

    /// Some of this open's collections, by position (every fourth is a spotlight).
    @ViewBuilder private func themeRows(_ shown: [MarketTheme], _ range: Range<Int>) -> some View {
        let r = range.clamped(to: 0..<shown.count)
        ForEach(Array(r), id: \.self) { i in
            ThemeSection(theme: shown[i], spotlight: i % 4 == 3).id(shown[i].id)
        }
    }

    private func section<C: View>(icon: String, _ title: String, _ subtitle: String, @ViewBuilder content: () -> C) -> some View {
        section(icon: icon, title, subtitle, content: content) { EmptyView() }
    }

    private func section<C: View, L: View>(icon: String, _ title: String, _ subtitle: String, @ViewBuilder content: () -> C, @ViewBuilder link: () -> L) -> some View {
        VStack(alignment: .leading, spacing: 14) {
            HStack(alignment: .lastTextBaseline) {
                // Just the title, like the collection rows (no icon, no line under it).
                Text(title).font(.display(22)).tracking(22 * -0.03).lineLimit(1).minimumScaleFactor(0.8).displayTrim(22)
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

    private func setMenu(_ open: Bool, animated: Bool = true) {
        guard open != menuOpen else { return }
        if open { SheetCover.shared.opened() } else { SheetCover.shared.closed() }
        if animated, !reduceMotion {
            withAnimation(.snappy(duration: 0.22)) { menuOpen = open }
        } else {
            var t = Transaction()
            t.disablesAnimations = true
            withTransaction(t) { menuOpen = open }
        }
    }

    /// A place picked in the menu: the menu goes at once, then the page opens.
    private func go(_ place: PlacesMenu.Place) {
        setMenu(false, animated: false)
        switch place {
        case .collection: Router.shared.tabRequest = "collection"
        case .explore: Router.shared.tabRequest = "explore"
        case .deal: Router.shared.tabRequest = "deal"
        case .recap: DispatchQueue.main.asyncAfter(deadline: .now() + 0.2) { recap = true }
        case .analytics: path.append(MorePage.analytics)
        case .grading: path.append(MorePage.grading)
        case .masterSets: path.append(MorePage.masterSets)
        case .activity: path.append(MorePage.activity)
        case .sales: path.append(MorePage.sales)
        case .lists: path.append(MorePage.lists)
        case .account: account = true
        }
    }

    private func load() async {
        guard !fresh else { return }
        if Demo.isOn {
            if index == nil { index = DemoData.exploreIndex }
            insights = .demo
        } else {
            if index == nil, let saved = await Task.detached(priority: .userInitiated, operation: { SavedExplore.load() }).value { index = saved }
            if let loaded = try? await Backend.shared.api.exploreIndex() { index = loaded; fresh = true }
            // The day's insights (saved on the server, so this is quick); kept on the phone too.
            if let fetched = try? await Backend.shared.api.marketInsights() {
                if fetched.briefing != nil || insights?.day != fetched.day { insights = fetched; MarketInsights.saved = fetched }
            }
            if let eras = try? await Backend.shared.api.eraSummaries(), eras.contains(where: { $0.tracked > 0 }) {
                eraSummaries = eras
                UserDefaults.standard.set(try? JSONEncoder().encode(eras), forKey: "era-summaries")
            }
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

/// "Today in the hobby": two or three sentences on what's moving, written daily by Claude from
/// Dexora's own prices. Quiet: a small label with a spark, then the text; no box.
extension MarketHomeView {
    /// Card of the day's "Did you know?" (a made-up one in demos and screenshots).
    static func fact(for star: SearchHit, _ insights: MarketInsights?) -> String? {
        if let f = insights?.facts?[star.product.id], !f.isEmpty { return f }
        return Demo.isOn ? "Ken Sugimori, who drew many of the earliest cards, also designed most of the original 151 Pokémon." : nil
    }

    /// This week's risers from one era, out of Home's other lists (by each card's set date).
    static func risers(in era: String, _ index: ExploreIndex) -> [SearchHit] {
        var released: [String: String] = [:]
        for s in index.sets { if let d = s.releaseDate { released[s.name] = d } }
        var pool: [SearchHit] = index.trending ?? []
        pool += index.today ?? []
        var seen = Set<String>()
        let fits = pool.filter { h in
            guard (h.change7dPct ?? 0) > 0, !h.product.isSealed, seen.insert(h.product.id).inserted else { return false }
            return MarketEras.era(of: h.releaseDate ?? h.product.setName.flatMap { released[$0] }) == era
        }
        return Array(fits.sorted { ($0.change7dPct ?? 0) > ($1.change7dPct ?? 0) }.prefix(5))
    }

    /// Today's stories; a demo makes three from its own market lists.
    func storiesToShow(_ index: ExploreIndex) -> [MarketStory]? {
        if let stories = insights?.stories, !stories.isEmpty { return stories }
        guard Demo.isOn else { return nil }
        var out: [MarketStory] = []
        if let a = index.trending?.first { out.append(MarketStory(headline: "\(a.product.name) leads the week", stat: Self.percent(a.change7dPct), tone: "up", cardId: a.product.id)) }
        if let b = index.eras?.vintage.first { out.append(MarketStory(headline: "Vintage is waking up", stat: Self.percent(b.change7dPct), tone: "up", cardId: b.product.id)) }
        if let c = index.drops?.first { out.append(MarketStory(headline: "\(c.product.name) cools off", stat: Self.percent(c.change7dPct), tone: "down", cardId: c.product.id)) }
        return out
    }

    static func percent(_ v: Double?) -> String {
        guard let v else { return "—" }
        return "\(v >= 0 ? "+" : "−")\(Int(abs(v).rounded()))%"
    }

    /// Every card in Home's market lists, by id (for the stories' pictures and links).
    static func cardsById(_ index: ExploreIndex) -> [String: SearchHit] {
        var out: [String: SearchHit] = [:]
        var all: [SearchHit] = index.trending ?? []
        all += index.today ?? []
        all += index.drops ?? []
        all += index.hotSealed ?? []
        all += index.eras?.modern ?? []
        all += index.eras?.midEra ?? []
        all += index.eras?.vintage ?? []
        for h in all where out[h.product.id] == nil { out[h.product.id] = h }
        return out
    }
}

/// Today in the hobby as a stack of notifications: the front one in full, the next two peeking
/// out under it, a little smaller. Every few seconds the front one slides back behind the others
/// and the next comes forward, round and round; a swipe steps it by hand. Each is a short
/// headline, one figure and the card it's about (tapping the front one opens that card).
private struct HobbyStories: View {
    var stories: [MarketStory]
    var cards: [String: SearchHit]
    @State private var page = 0
    @State private var drag: CGFloat = 0
    @Environment(\.accessibilityReduceMotion) private var reduceMotion
    private let dwell: Double = 5

    var body: some View {
        VStack(alignment: .leading, spacing: 10) {
            MonoLabel(text: "Today in the hobby")
                .padding(.horizontal, 16)
            ZStack(alignment: .top) {
                ForEach(Array(stories.enumerated()), id: \.offset) { i, story in
                    layered(story, depth: depth(of: i))
                }
            }
            .padding(.bottom, CGFloat(min(stories.count, 3) - 1) * 11)
            .padding(.horizontal, 16)
            // Alongside the page's scrolling: only a sideways swipe moves the stack.
            .simultaneousGesture(
                DragGesture(minimumDistance: 14)
                    .onChanged { g in
                        guard abs(g.translation.width) > abs(g.translation.height) else { return }
                        drag = g.translation.width * 0.6
                    }
                    .onEnded { g in
                        let sideways = abs(g.translation.width) > abs(g.translation.height) * 1.4
                        let step = !sideways ? 0 : g.translation.width < -50 ? 1 : g.translation.width > 50 ? -1 : 0
                        withAnimation(.spring(response: 0.45, dampingFraction: 0.85)) {
                            drag = 0
                            page = (page + step + stories.count) % stories.count
                        }
                    }
            )
        }
        .task(id: page) { await advance() }
    }

    /// How far behind the front a story sits (0 is the front).
    private func depth(of i: Int) -> Int { (i - page + stories.count) % stories.count }

    /// Behind the front one: a step smaller, lower and dimmer each.
    private func layered(_ story: MarketStory, depth: Int) -> some View {
        let d = CGFloat(depth)
        let fade: Double = depth == 0 ? 1 : (depth == 1 ? 0.7 : (depth == 2 ? 0.4 : 0))
        let x: CGFloat = depth == 0 ? drag : 0
        return notification(story, front: depth == 0)
            .scaleEffect(1 - d * 0.05, anchor: .top)
            .offset(x: x, y: d * 11)
            .opacity(fade)
            .zIndex(-Double(depth))
            .allowsHitTesting(depth == 0)
    }

    private func advance() async {
        guard !reduceMotion, stories.count > 1 else { return }
        try? await Task.sleep(for: .seconds(dwell))
        guard !Task.isCancelled else { return }
        withAnimation(.spring(response: 0.55, dampingFraction: 0.86)) { page = (page + 1) % stories.count }
    }

    /// A capital first letter, whatever the AI sent.
    static func sentenceCase(_ s: String) -> String { s.prefix(1).uppercased() + s.dropFirst() }

    @ViewBuilder private func notification(_ story: MarketStory, front: Bool) -> some View {
        let hit = story.cardId.flatMap { cards[$0] }
        let tone: Color = story.tone == "down" ? Theme.planPink : (story.tone == "up" ? Theme.lime : Color.white)
        let card = notificationBody(story, hit: hit, tone: tone)
        if let hit, front {
            MarketLink(hit: hit) { card }
        } else {
            card
        }
    }

    private func notificationBody(_ story: MarketStory, hit: SearchHit?, tone: Color) -> some View {
        HStack(alignment: .center, spacing: 12) {
            VStack(alignment: .leading, spacing: 6) {
                // Like a notification's top line: the app, and when.
                HStack(spacing: 6) {
                    Image(systemName: "sparkles").font(.system(size: 9, weight: .bold)).foregroundStyle(Theme.ink)
                        .frame(width: 18, height: 18)
                        .background(RoundedRectangle(cornerRadius: 5, style: .continuous).fill(Theme.lime))
                    Text("Dexora").font(.geist(12, .semibold)).foregroundStyle(.white)
                    Text("Today").font(.geist(12)).foregroundStyle(Theme.subtle)
                }
                Text(Self.sentenceCase(story.headline).noWidow).font(.geist(16, .semibold)).foregroundStyle(.white)
                    .lineLimit(2).fixedSize(horizontal: false, vertical: true)
                Text(story.stat).font(.display(22)).tracking(-0.6).monospacedDigit().foregroundStyle(tone).lineLimit(1)
            }
            Spacer(minLength: 0)
            if let hit {
                ProductImage(product: hit.pictured, cornerRadius: 5).frame(width: 52, height: 72)
            }
        }
        .padding(14)
        .frame(maxWidth: .infinity, alignment: .leading)
        .frame(height: 118)
        // Dark like the page's other panels (glass read too light here), with a faint edge.
        .background(RoundedRectangle(cornerRadius: 22, style: .continuous).fill(Theme.surface))
        .overlay(RoundedRectangle(cornerRadius: 22, style: .continuous).strokeBorder(Theme.border))
    }
}

/// Home before its lists arrive (a first launch): Dexora's name with a soft lime glow, still.
private struct HomeLoading: View {
    var body: some View {
        VStack(spacing: 10) {
            Text("Dexora").font(.display(44)).tracking(-1.6).foregroundStyle(.white)
            Text("Getting today's market\u{00A0}ready").font(.geist(14)).foregroundStyle(Theme.muted)
        }
        .frame(maxWidth: .infinity)
        .padding(.top, 140)
        .background {
            RadialGradient(colors: [Theme.lime.opacity(0.18), .clear], center: .center, startRadius: 0, endRadius: 180)
                .frame(width: 360, height: 360)
                .padding(.top, 140)
                .allowsHitTesting(false)
        }
        .accessibilityElement(children: .combine)
    }
}

private struct HobbyBriefing: View {
    var text: String

    var body: some View {
        VStack(alignment: .leading, spacing: 8) {
            HStack(spacing: 6) {
                Image(systemName: "sparkles").font(.system(size: 11, weight: .semibold)).foregroundStyle(Theme.lime)
                MonoLabel(text: "Today in the hobby")
            }
            Text(text.noWidow).font(.geist(15)).foregroundStyle(.white)
                .fixedSize(horizontal: false, vertical: true)
        }
        .frame(maxWidth: .infinity, alignment: .leading)
        .accessibilityElement(children: .combine)
    }
}

/// Your collection in one line on Home: its worth and today's move, tapping through to Collection.
private struct YourCollectionStrip: View {
    @Environment(CollectionStore.self) private var store

    var body: some View {
        let s = store.summary
        // The last 30 days (as Collection's header): its line, colored by whether it's up.
        let month = Array(store.timeline.suffix(31))
        let monthChange = (month.last?.value ?? 0) - (month.first?.value ?? 0)
        let tint = monthChange < 0 ? Theme.planPink : Theme.lime
        Button { Router.shared.tabRequest = "collection-summary" } label: {
            VStack(alignment: .leading, spacing: 10) {
                MonoLabel(text: "Your collection")
                // The worth big, today under it; the month's change on the right.
                HStack(alignment: .lastTextBaseline, spacing: 12) {
                    VStack(alignment: .leading, spacing: 6) {
                        Text(Format.money(s.value)).font(.display(36)).tracking(-1.2).monospacedDigit().foregroundStyle(.white)
                            .lineLimit(1).minimumScaleFactor(0.7)
                        HStack(spacing: 6) {
                            DeltaPill(ratio: s.dayRatio, size: 11)
                            Text(Format.signedMoney(s.dayChange)).font(.geist(13, .semibold)).monospacedDigit().foregroundStyle(Theme.tone(s.dayChange))
                            Text("today").font(.geist(13)).foregroundStyle(Theme.muted)
                        }
                        .lineLimit(1)
                    }
                    .layoutPriority(1)
                    Spacer(minLength: 0)
                    if month.count > 1 {
                        VStack(alignment: .trailing, spacing: 2) {
                            Text(Format.signedMoney(monthChange)).font(.geist(15, .semibold)).monospacedDigit().foregroundStyle(Theme.tone(monthChange))
                            Text("past 30 days").font(.geist(12)).foregroundStyle(Theme.muted)
                        }
                        .lineLimit(1)
                    }
                }
                // The month as a wide chart across the screen, fading out at both edges.
                if month.count > 1 {
                    Sparkline(points: month, color: tint)
                        .frame(height: 70)
                        .padding(.horizontal, -16)
                        .mask(LinearGradient(stops: [.init(color: .clear, location: 0), .init(color: .black, location: 0.08),
                                                     .init(color: .black, location: 0.92), .init(color: .clear, location: 1)],
                                             startPoint: .leading, endPoint: .trailing))
                        .padding(.top, 4)
                }
            }
            // No box: straight on the page, lined up with the tiles' edges, with a faint glow of
            // the month's color behind the chart.
            .padding(.vertical, 6)
            .background(alignment: .bottom) {
                // Centred behind the chart and fading to nothing inside its own frame on every side
                // (radius half the height), widened sideways: no hard edge at the top or bottom.
                RadialGradient(colors: [tint.opacity(0.16), .clear], center: .center, startRadius: 0, endRadius: 80)
                    .frame(height: 160)
                    .scaleEffect(x: 2.2, y: 1, anchor: .center)
                    .allowsHitTesting(false)
            }
            .contentShape(Rectangle())
        }
        .buttonStyle(.plain)
    }
}

// MARK: - The highlight pieces

/// A stored percent change (12.5 = +12.5%) as signed text, lime up and pink down.
private func pctText(_ pct: Double?) -> String { pct.map { Format.signedPercent($0 / 100) } ?? "—" }
private func pctTint(_ pct: Double?) -> Color { (pct ?? 0) >= 0 ? Theme.lime : Theme.planPink }

/// The top of Home: today's biggest riser, as a wide tile matching Heating up / Cooling off
/// under it. Light rays turn slowly behind the card, sparks rise, the card drifts and shines,
/// and its rise sits on a lime ribbon; inside the electric border of the set page's No. 1 chase. Without today's movers the week's top riser stands in,
/// and without any market moves the newest set's top pull.
private struct CardOfTheDay: View {
    enum Kind { case day, week, topPull(String) }
    var hit: SearchHit
    var kind: Kind
    /// Why it moved, in a line (from the daily insights), when there is one.
    var reason: String? = nil
    /// "Did you know?": one fun fact about the card (from the daily insights), when there is one.
    var fact: String? = nil
    @Environment(CollectionStore.self) private var store
    private var daily: Bool { if case .day = kind { return true } else { return false } }

    /// The card's last week of prices, for the small chart (loaded from our own server).
    private var week: [PricePoint] {
        let all = store.sortedHistory(priceKey(hit.product.id, hit.printing))
        guard let last = all.last?.day, let start = Calendar.current.date(byAdding: .day, value: -7, to: last) else { return [] }
        return all.filter { $0.day >= start }
    }

    /// The week's chart only when it really moved (a flat line or a single day says nothing).
    private var chartPoints: [PricePoint]? {
        let w = week
        guard w.count >= 3, let lo = w.map(\.price).min(), let hi = w.map(\.price).max(), lo > 0, (hi - lo) / lo > 0.01 else { return nil }
        return w
    }

    var body: some View {
        let p = hit.pictured
        let pct: Double? = switch kind { case .day: hit.change24hPct; case .week: hit.change7dPct; case .topPull: nil }
        let tag: String = switch kind { case .day: "Card of the day"; case .week: "Card of the week"; case .topPull: "Top pull" }
        let down = (pct ?? 0) < 0
        let tone = down ? Theme.planPink : Theme.lime
        let shape = RoundedRectangle(cornerRadius: 28, style: .continuous)
        MarketLink(hit: hit) {
            VStack(spacing: 18) {
                HStack {
                    SkewTag(text: tag, icon: "flame.fill")
                    Spacer(minLength: 8)
                    if daily { NextCardCountdown() }
                }
                hero(p, tone: tone)
                // The name and set, centred under the card.
                VStack(spacing: 6) {
                    Text(p.name.noWidow).font(.display(30)).tracking(-1).multilineTextAlignment(.center).lineLimit(2).minimumScaleFactor(0.8)
                    Text([p.setName, p.rarity].compactMap { $0 }.joined(separator: " · ")).font(.geist(13)).foregroundStyle(Theme.muted).lineLimit(1)
                }
                // The price big, the move on its ribbon beside it.
                HStack(alignment: .center, spacing: 12) {
                    Text(Format.money(hit.market)).font(.display(44)).tracking(-1.6).monospacedDigit().lineLimit(1).minimumScaleFactor(0.7)
                    if let pct { MoveRibbon(pct: pct, label: daily ? "TODAY" : "WEEK", tone: tone, down: down) }
                }
                // Today, the week and the month as three glass tiles, as far apart as the rows.
                HStack(spacing: 18) {
                    stat("Today", hit.change24hPct)
                    stat("7 days", hit.change7dPct)
                    stat("30 days", hit.change30dPct)
                }
                if let points = chartPoints { WeekLine(points: points, tone: tone) }
                if let fact, !fact.isEmpty, !fact.contains("tcgapi:") { DidYouKnow(text: fact) }
            }
            .foregroundStyle(.white)
            .padding(18)
            .frame(maxWidth: .infinity)
            .background { backdrop(p, tone: tone, shape: shape) }
            .clipShape(shape)
            .shadow(color: tone.opacity(0.25), radius: 28)
            .overlay(ElectricBorder(radius: 28, color: tone))
        }
        // Its week of prices for the chart (free: our own catalog, once per card).
        .task(id: hit.product.id) { await store.showCatalogProduct(hit.product.id) }
    }

    /// The card big in the middle: its rays behind, a pool of light under it, the holo shine on it.
    private func hero(_ p: Product, tone: Color) -> some View {
        ZStack {
            RadialGradient(colors: [tone.opacity(0.55), tone.opacity(0.12), .clear], center: .center, startRadius: 0, endRadius: 130)
                .frame(width: 260, height: 260)
                .scaleEffect(x: 1, y: 0.2)
                .offset(y: 152)
                .allowsHitTesting(false)
            HoloCard(foil: true, textured: false, cornerRadius: 12) {
                ProductImage(product: p, cornerRadius: 12, large: true).frame(width: 214, height: 299)
            }
            .drifting()
            .notTiltable()
            .frame(width: 214, height: 299)
            .shadow(color: .black.opacity(0.6), radius: 24, y: 16)
        }
        .frame(maxWidth: .infinity)
        .frame(height: 320)
        .background { LightRays().frame(width: 600, height: 600) }
    }

    /// The card's own art, blown up and blurred, filling the panel, darkened toward the bottom
    /// so the text reads; the grid and a glow of the move's color over it.
    private func backdrop(_ p: Product, tone: Color, shape: RoundedRectangle) -> some View {
        ZStack {
            shape.fill(Color(hex: 0x060606))
            CachedImage(url: p.imageURL) { img in img.resizable().scaledToFill() } placeholder: { Color.clear }
                .environment(\.imageFadesIn, false)
                .scaleEffect(1.4)
                .blur(radius: 40, opaque: true)
                .opacity(0.5)
                .drawingGroup()
            LinearGradient(colors: [.black.opacity(0.1), .black.opacity(0.55), .black.opacity(0.9)], startPoint: .top, endPoint: .bottom)
            GridPattern(step: 24, opacity: 0.06)
            RadialGradient(colors: [tone.opacity(0.28), .clear], center: UnitPoint(x: 0.5, y: 0.3), startRadius: 0, endRadius: 260)
        }
        .allowsHitTesting(false)
    }

    private func stat(_ label: String, _ pct: Double?) -> some View {
        VStack(spacing: 3) {
            MonoLabel(text: label)
            Text(pctText(pct)).font(.display(17)).tracking(-0.4).monospacedDigit()
                .foregroundStyle(pct == nil ? Theme.subtle : pctTint(pct))
        }
        .frame(maxWidth: .infinity)
        .padding(.vertical, 10)
        .liquidGlass(in: RoundedRectangle(cornerRadius: 14, style: .continuous))
    }
}

/// Card of the day's fun fact: a small glass box with a lime spark and "Did you know?".
private struct DidYouKnow: View {
    var text: String

    var body: some View {
        VStack(alignment: .leading, spacing: 6) {
            HStack(spacing: 6) {
                Image(systemName: "sparkle").font(.system(size: 11, weight: .bold)).foregroundStyle(Theme.lime)
                MonoLabel(text: "Did you know?")
            }
            Text(text.noWidow).font(.geist(14)).foregroundStyle(.white.opacity(0.9))
                .fixedSize(horizontal: false, vertical: true)
        }
        .padding(14)
        .frame(maxWidth: .infinity, alignment: .leading)
        .liquidGlass(in: RoundedRectangle(cornerRadius: 16, style: .continuous))
    }
}

/// The move on a tilted ribbon: ink on lime up, white on pink down (never pink on lime).
private struct MoveRibbon: View {
    var pct: Double
    var label: String
    var tone: Color
    var down: Bool

    var body: some View {
        HStack(alignment: .firstTextBaseline, spacing: 5) {
            Image(systemName: down ? "arrow.down.right" : "arrow.up.right").font(.system(size: 13, weight: .heavy))
            Text(pctText(pct)).font(.display(20)).tracking(-0.5).monospacedDigit().lineLimit(1)
            Text(label).font(.mono(9)).tracking(1)
        }
        .foregroundStyle(down ? Color.white : Theme.ink)
        .padding(.horizontal, 10).padding(.vertical, 5)
        .background(tone, in: RoundedRectangle(cornerRadius: 6, style: .continuous))
        .rotationEffect(.degrees(-3))
        .shadow(color: tone.opacity(0.5), radius: 12)
        .fixedSize()
    }
}

/// Tomorrow's card in hours and minutes, read off the clock once a minute (no animation).
private struct NextCardCountdown: View {
    var body: some View {
        TimelineView(.everyMinute) { context in
            let mins = Self.minutesToNextCard(from: context.date)
            Text("Next card in \(mins / 60)h \(mins % 60)m").font(.mono(10)).tracking(1).foregroundStyle(Theme.muted).monospacedDigit()
        }
    }

    /// Minutes until midnight UTC, when the next card of the day is picked.
    static func minutesToNextCard(from now: Date) -> Int {
        var utc = Calendar(identifier: .gregorian)
        utc.timeZone = TimeZone(identifier: "UTC") ?? .current
        let tomorrow = utc.startOfDay(for: utc.date(byAdding: .day, value: 1, to: now) ?? now)
        return max(0, Int(tomorrow.timeIntervalSince(now) / 60))
    }
}

/// The card's last week as a small line in its move's color, its first and last price under it.
private struct WeekLine: View {
    var points: [PricePoint]
    var tone: Color

    var body: some View {
        VStack(alignment: .leading, spacing: 6) {
            MonoLabel(text: "Past 7 days")
            Chart(points) { pt in
                AreaMark(x: .value("Day", pt.day), y: .value("Price", pt.price))
                    .foregroundStyle(LinearGradient(colors: [tone.opacity(0.25), .clear], startPoint: .top, endPoint: .bottom))
                    .interpolationMethod(.monotone)
                LineMark(x: .value("Day", pt.day), y: .value("Price", pt.price))
                    .foregroundStyle(tone)
                    .lineStyle(StrokeStyle(lineWidth: 2, lineCap: .round))
                    .interpolationMethod(.monotone)
            }
            .chartXAxis(.hidden)
            .chartYAxis(.hidden)
            .chartYScale(domain: .automatic(includesZero: false))
            .frame(height: 56)
        }
    }
}

/// Slow light rays fanning out from behind the card: one turning gradient (a single rotation
/// animation, only while on screen; still under Reduce Motion).
private struct LightRays: View {
    @Environment(\.accessibilityReduceMotion) private var reduceMotion
    @State private var onScreen = true

    var body: some View {
        // The turn is read off the clock (one turn a minute), so it never speeds up: a looping
        // animation restarted as the page came and went could stack and spin fast for a moment.
        TimelineView(.animation(minimumInterval: 1.0 / 30, paused: reduceMotion || !onScreen)) { context in
            rays.rotationEffect(.degrees(reduceMotion ? 0 : (context.date.timeIntervalSinceReferenceDate * 6).truncatingRemainder(dividingBy: 360)))
        }
        .allowsHitTesting(false)
        .onVisibilityChange { on in if on != onScreen { onScreen = on } }
    }

    private var rays: some View {
        AngularGradient(gradient: Gradient(stops: (0 ..< 24).map { i in
            .init(color: i % 2 == 0 ? Theme.lime.opacity(0.16) : .clear, location: Double(i) / 23)
        }), center: .center)
        // Fades out in a circle inside its square (whatever size it's given), so turning never
        // shows the square's edges or corners.
        .mask(GeometryReader { geo in
            RadialGradient(colors: [.black, .clear], center: .center, startRadius: 20, endRadius: min(geo.size.width, geo.size.height) / 2)
        })
    }
}

/// Embers rising (fire) or snow falling (ice), the week recap's particles, only while on screen.
private struct TileParticles: View {
    var hot: Bool

    var body: some View {
        // iOS's own particles: smooth at the screen's full rate, no work per frame here.
        ParticleEmitter(kind: hot ? .embers : .snow)
    }
}

/// Hot (the week's top riser, in fire) or cold (the biggest faller, in ice): the card tilted on
/// a glow of its color with embers or snow around it, the change big underneath.
private struct HotColdTile: View {
    /// The cards it cycles through, about four seconds each (one stays still).
    var hits: [SearchHit]
    var hot: Bool
    @State private var index = 0
    @State private var onScreen = true
    @Environment(\.accessibilityReduceMotion) private var reduceMotion

    var body: some View {
        let glow = hot ? Color(hex: 0xFF7A1A) : Color(hex: 0x7DD3FC)
        let shape = RoundedRectangle(cornerRadius: 22, style: .continuous)
        let hit = hits[index % max(hits.count, 1)]
        MarketLink(hit: hit) {
            VStack(alignment: .leading, spacing: 10) {
                HStack(spacing: 5) {
                    Image(systemName: hot ? "flame.fill" : "snowflake").font(.system(size: 11, weight: .bold)).foregroundStyle(glow)
                    Text(hot ? "HEATING UP" : "COOLING OFF").font(.mono(10)).tracking(1.2).foregroundStyle(.white.opacity(0.8))
                    Spacer(minLength: 4)
                    // Which card of the set is showing.
                    if hits.count > 1 {
                        HStack(spacing: 3) {
                            ForEach(0 ..< hits.count, id: \.self) { i in
                                Circle().fill(i == index % hits.count ? glow : Color.white.opacity(0.25)).frame(width: 4, height: 4)
                            }
                        }
                    }
                }
                // The card and its figures change together, fading through.
                VStack(alignment: .leading, spacing: 10) {
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
                            .lineLimit(1).fixedSize()
                    }
                }
                .id(hit.id)
                .transition(.opacity)
            }
            .foregroundStyle(.white)
            .padding(14)
            .frame(maxWidth: .infinity, alignment: .leading)
            .background {
                ZStack {
                    shape.fill(Color(hex: 0x080808))
                    RadialGradient(colors: [glow.opacity(0.32), .clear], center: UnitPoint(x: 0.5, y: 0.42), startRadius: 0, endRadius: 130)
                    TileParticles(hot: hot)
                }
                .clipShape(shape)
            }
            .overlay(shape.strokeBorder(glow.opacity(0.35), lineWidth: 1))
        }
        .onVisibilityChange { visible in if visible != onScreen { onScreen = visible } }
        // Cycles only while on screen; the cold tile starts half a beat later so the two
        // don't change at the same moment.
        .task(id: onScreen && hits.count > 1) {
            guard onScreen, hits.count > 1 else { return }
            try? await Task.sleep(for: .seconds(hot ? 4 : 6))
            while !Task.isCancelled {
                withAnimation(reduceMotion ? nil : .easeInOut(duration: 0.45)) { index += 1 }
                try? await Task.sleep(for: .seconds(4))
            }
        }
    }
}

/// The top 10 risers, each card standing in front of its rank in huge numerals.
private struct TopTenRow: View {
    var hits: [SearchHit]
    /// The big rank numbers rise in, one after another, the first time the row is seen.
    @State private var revealed = false
    @Environment(\.accessibilityReduceMotion) private var reduceMotion

    var body: some View {
        ScrollView(.horizontal, showsIndicators: false) {
            HStack(alignment: .top, spacing: 10) {
                ForEach(Array(hits.enumerated()), id: \.element.id) { i, hit in
                    MarketLink(hit: hit) {
                        VStack(alignment: .leading, spacing: 8) {
                            ZStack(alignment: .bottomLeading) {
                                Text("\(i + 1)")
                                    .font(.display(130)).tracking(-8)
                                    .foregroundStyle(LinearGradient(colors: [.white.opacity(0.22), .white.opacity(0.04)], startPoint: .top, endPoint: .bottom))
                                    .offset(x: -6, y: revealed ? 22 : 60)
                                    .opacity(revealed ? 1 : 0)
                                    .animation(.spring(response: 0.55, dampingFraction: 0.8).delay(Double(i) * 0.07), value: revealed)
                                ProductImage(product: hit.pictured, cornerRadius: 6)
                                    .frame(width: 100, height: 140)
                                    .shadow(color: .black.opacity(0.6), radius: 10, y: 6)
                                .padding(.leading, i + 1 >= 10 ? 70 : 46)
                            }
                            .frame(height: 150, alignment: .bottomLeading)
                            // One line each, never wrapping: name, price, then the rise.
                            VStack(alignment: .leading, spacing: 2) {
                                Text(hit.product.name).font(.geist(13, .medium)).lineLimit(1)
                                Text(Format.money(hit.market)).font(.display(16)).tracking(-0.3).monospacedDigit()
                                    .lineLimit(1).minimumScaleFactor(0.7)
                                Text(pctText(hit.change7dPct)).font(.geist(12, .semibold)).monospacedDigit().foregroundStyle(pctTint(hit.change7dPct))
                                    .lineLimit(1)
                            }
                            .padding(.leading, i + 1 >= 10 ? 70 : 46)
                            .frame(width: (i + 1 >= 10 ? 70 : 46) + 100, alignment: .leading)
                        }
                        .foregroundStyle(.white)
                        // Each in its own black box with a faint edge; the big number stays inside it.
                        .padding(.horizontal, 14)
                        .padding(.top, 14)
                        .padding(.bottom, 14)
                        .background(RoundedRectangle(cornerRadius: 20, style: .continuous).fill(Color.black))
                        .clipShape(RoundedRectangle(cornerRadius: 20, style: .continuous))
                        .overlay(RoundedRectangle(cornerRadius: 20, style: .continuous).strokeBorder(Color.white.opacity(0.07)))
                    }
                }
            }
            .padding(.horizontal, 16)
            .padding(.vertical, 4)
            .padding(.top, 10)
        }
        // The crown and No. 1's sparks reach above the row: not cut off at its top.
        .scrollClipDisabled()
        .onVisibilityChange { on in
            guard on, !revealed else { return }
            if reduceMotion { var t = Transaction(); t.disablesAnimations = true; withTransaction(t) { revealed = true } } else { revealed = true }
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
                            Text(Format.money(hit.market)).font(.display(17)).tracking(-0.4).monospacedDigit().lineLimit(1)
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

// MARK: - Rising by era

/// One era's market at a glance: its typical change this week (or today, until a week of prices is
/// kept), how many cards went up and down with a thin bar, then its biggest moves (shown only
/// when there are some). Every era card is the same height. The card turns pink when the era is down.
private struct EraSummaryCard: View, Equatable {
    var summary: EraSummary

    private var era: EraCard.Era { summary.era == "modern" ? .modern : summary.era == "midEra" ? .midEra : .vintage }

    var body: some View {
        let down = summary.median < 0
        let tint = down ? Theme.planPink : era.color
        VStack(alignment: .leading, spacing: 14) {
            HStack(alignment: .firstTextBaseline) {
                Text(era.title).font(.display(30)).tracking(-0.8).displayTrim(30)
                Spacer(minLength: 8)
                MonoLabel(text: summary.window == "7d" ? "This week" : "Today")
            }
            VStack(alignment: .leading, spacing: 4) {
                Text(Format.signedPercent(summary.median / 100)).font(.display(48)).tracking(-1.6).monospacedDigit()
                    .foregroundStyle(down ? Theme.planPink : summary.median > 0 ? Theme.lime : .white)
                    .displayTrim(48)
                Text("Typical change across \(summary.tracked.formatted()) cards").font(.geist(13)).foregroundStyle(Theme.muted)
            }
            // How widely it moved: up, unchanged and down as one thin bar.
            VStack(alignment: .leading, spacing: 8) {
                GeometryReader { geo in
                    let total = max(1, summary.up + summary.flat + summary.down)
                    HStack(spacing: 2) {
                        Capsule().fill(Theme.lime).frame(width: max(summary.up > 0 ? 4 : 0, geo.size.width * Double(summary.up) / Double(total)))
                        Capsule().fill(Color.white.opacity(0.15))
                        Capsule().fill(Theme.planPink).frame(width: max(summary.down > 0 ? 4 : 0, geo.size.width * Double(summary.down) / Double(total)))
                    }
                }
                .frame(height: 6)
                // In the bar's order: up on the left, steady in the middle, down on the right.
                HStack(spacing: 10) {
                    (Text("\(summary.up.formatted())").foregroundColor(Theme.lime) + Text(" up").foregroundColor(Theme.muted))
                    Spacer(minLength: 0)
                    (Text("\(summary.flat.formatted())").foregroundColor(.white) + Text(" steady").foregroundColor(Theme.muted))
                    Spacer(minLength: 0)
                    (Text("\(summary.down.formatted())").foregroundColor(Theme.planPink) + Text(" down").foregroundColor(Theme.muted))
                }
                .font(.geist(13)).monospacedDigit()
            }
            if !summary.moves.isEmpty {
                VStack(alignment: .leading, spacing: 0) {
                    MonoLabel(text: "Biggest moves").padding(.bottom, 6)
                    ForEach(Array(summary.moves.enumerated()), id: \.element.id) { i, move in
                        if i > 0 { Divider().overlay(Color.white.opacity(0.06)) }
                        MarketLink(hit: move.hit) {
                            HStack(spacing: 10) {
                                ProductImage(product: move.hit.pictured, cornerRadius: 2).frame(width: 30, height: 42)
                                VStack(alignment: .leading, spacing: 2) {
                                    Text(move.hit.product.name).font(.geist(14, .medium)).foregroundStyle(.white).lineLimit(1)
                                    Text(move.hit.product.setName ?? "").font(.geist(12)).foregroundStyle(Theme.muted).lineLimit(1)
                                }
                                Spacer(minLength: 8)
                                VStack(alignment: .trailing, spacing: 2) {
                                    Text(Format.money(move.hit.market)).font(.display(15)).tracking(-0.3).monospacedDigit().foregroundStyle(.white)
                                    ChangeText(pct: move.changePct)
                                }
                            }
                            .padding(.vertical, 8)
                            .contentShape(Rectangle())
                        }
                    }
                }
                .cardSequence(summary.moves.map(\.id))
            }
        }
        // As tall as the fullest era (the row lines them up), never a fixed height with dead space.
        .frame(maxHeight: .infinity, alignment: .top)
        .tinted(tint)
        .containerRelativeFrame(.horizontal) { width, _ in width - 32 - 28 }
    }

    /// Made-up summaries from the demo's own lists (demos and screenshots).
    static func demo(_ index: ExploreIndex) -> [EraSummary] {
        let e = index.eras ?? MarketEras()
        func make(_ key: String, _ hits: [SearchHit], _ median: Double, _ up: Int, _ down: Int, _ flat: Int) -> EraSummary {
            EraSummary(era: key, window: "7d", median: median, up: up, down: down, flat: flat, tracked: up + down + flat,
                       moves: hits.prefix(3).map { EraMove(hit: $0, changePct: $0.change7dPct ?? 0) })
        }
        return [make("modern", e.modern, 1.8, 1240, 610, 2210), make("midEra", e.midEra, -0.6, 310, 420, 1180), make("vintage", e.vintage, 2.4, 412, 188, 640)]
    }
}


/// One era's card on Home, in the style of Collection's sealed / singles / graded boxes: the era's
/// name and its average rise on a tag, the years it covers, its three biggest risers fanned out,
/// then its top five as rows (each opens its card page). Eras as in `eraOf` / `MarketEras.era`.
private struct EraCard: View, Equatable {
    @Environment(CollectionStore.self) private var store
    enum Era {
        case modern, midEra, vintage

        var title: String {
            switch self {
            case .modern: return "Modern"
            case .midEra: return "Mid-era"
            case .vintage: return "Vintage"
            }
        }

        var blurb: String {
            switch self {
            case .modern: return "Sun & Moon on, 2017 to now"
            case .midEra: return "Diamond & Pearl to XY, 2007 to 2016"
            case .vintage: return "WotC and EX, before 2007"
            }
        }

        var color: Color {
            switch self {
            case .modern: return Theme.lime
            case .midEra: return Theme.planBlue
            case .vintage: return Theme.planPink
            }
        }

        var tagText: Color { self == .modern ? Theme.ink : .white }
    }

    var era: Era
    var hits: [SearchHit]
    /// Made-up risers until the real ones arrive: tagged Sample; tapping one opens the real card.
    var sample = false

    static func == (a: Self, b: Self) -> Bool { a.era == b.era && a.hits == b.hits && a.sample == b.sample }

    /// Placeholder risers for an era (real cards and pictures, made-up prices and rises).
    static func sample(_ era: Era) -> [SearchHit] {
        let rows: [(String, String, String, String, String, Double, Double)]
        switch era {
        case .modern:
            rows = [
                ("swsh7", "215", "Umbreon VMAX (Alternate Full Art)", "Evolving Skies", "215/203", 1392, 14.2),
                ("sv8", "238", "Pikachu ex - 238/191", "Surging Sparks", "238/191", 371.5, 11.8),
                ("swsh7", "218", "Rayquaza VMAX (Alternate Full Art)", "Evolving Skies", "218/203", 548, 9.6),
                ("swsh8", "270", "Espeon VMAX (Alternate Art Secret)", "Fusion Strike", "270/264", 512, 7.3),
                ("swsh11", "186", "Giratina V (Alternate Full Art)", "Lost Origin", "186/196", 318.4, 5.9),
            ]
        case .midEra:
            rows = [
                ("xy2", "100", "Charizard EX (Full Art)", "Flashfire", "100/106", 286, 12.4),
                ("xy12", "11", "Charizard", "Evolutions", "11/108", 64.5, 9.1),
                ("g1", "11", "Charizard", "Generations", "11/83", 48.2, 7.7),
                ("xy12", "13", "M Charizard EX", "Evolutions", "13/108", 41.9, 6.2),
                ("xy2", "12", "Charizard EX", "Flashfire", "12/106", 38.6, 4.8),
            ]
        case .vintage:
            rows = []
        }
        return rows.map { set, num, name, setName, number, price, rise in
            let product = Product(id: "sample:era-\(set)-\(num)", source: "sample", externalId: "\(set)-\(num)", name: name, setName: setName,
                                  setId: set, number: number, rarity: nil, productType: "Cards", kind: "single",
                                  imageUrl: "https://images.pokemontcg.io/\(set)/\(num)_hires.png", tcgplayerId: nil, tcgplayerUrl: nil,
                                  printings: ["Holofoil"])
            return SearchHit(product: product, market: price, change7dPct: rise)
        }
    }

    /// A riser that opens its card page. A sample card is looked up in Dexora's own catalog by
    /// its name, number and set (free, no paid calls), and its real page opens.
    @ViewBuilder private func link<L: View>(_ hit: SearchHit, @ViewBuilder _ label: () -> L) -> some View {
        if sample {
            Button { Task { await Self.openReal(hit.product, store: store) } } label: { label() }
                .buttonStyle(.plain)
        } else {
            MarketLink(hit: hit, label: label)
        }
    }

    /// Sample cards' real catalog ids, looked up once (when the card first shows), so a tap
    /// opens the page at once instead of searching first.
    @MainActor private static var realIds: [String: String] = [:]
    /// The real cards found, handed to the store before their page opens (so it shows at once,
    /// with its price, instead of fetching the card first).
    @MainActor private static var realHits: [String: SearchHit] = [:]

    @MainActor
    private static func openReal(_ p: Product, store: CollectionStore) async {
        Haptics.tap()
        if realIds[p.id] == nil { _ = await resolve(p) }
        // Never a dead tap: if the card can't be found, open search instead.
        guard let id = realIds[p.id] else {
            Router.shared.searchRequest += 1
            return
        }
        if let hit = realHits[p.id] { store.seed(hit) }
        Router.shared.product = id
    }

    @MainActor
    private static func resolve(_ p: Product) async -> String? {
        if let id = realIds[p.id] { return id }
        let base = p.name.components(separatedBy: " (").first ?? p.name
        let number = p.number?.components(separatedBy: "/").first
        // Name and set first, then the name alone (the catalog's set names carry codes like
        // "SWSH07: Evolving Skies" that a plain set name may not match).
        var hits: [SearchHit] = []
        for query in [[base, p.setName].compactMap { $0 }.joined(separator: " "), base] {
            if let found = try? await Backend.shared.api.search(query), !found.isEmpty { hits = found; break }
        }
        guard !hits.isEmpty else { return nil }
        let sameNumber = { (h: SearchHit) -> Bool in
            guard let number, let n = h.product.number else { return false }
            return n.components(separatedBy: "/").first == number
        }
        let sameSet = { (h: SearchHit) -> Bool in
            guard let set = p.setName, let s = h.product.setName else { return false }
            return s.localizedCaseInsensitiveContains(set)
        }
        let match = hits.first { sameNumber($0) && sameSet($0) } ?? hits.first(where: sameNumber) ?? hits.first(where: sameSet) ?? hits.first
        if let match {
            realIds[p.id] = match.product.id
            realHits[p.id] = match
        }
        return match?.product.id
    }

    /// Looks up every sample card's real id in the background (all at once), ready for a tap.
    @MainActor
    static func prefetch(_ hits: [SearchHit]) async {
        await withTaskGroup(of: Void.self) { group in
            for h in hits where realIds[h.product.id] == nil {
                group.addTask { @MainActor in _ = await resolve(h.product) }
            }
        }
    }

    var body: some View {
        let top = Array(hits.prefix(5))
        let rises = top.compactMap(\.change7dPct)
        let average = rises.isEmpty ? nil : rises.reduce(0, +) / Double(rises.count)
        VStack(alignment: .leading, spacing: 12) {
            HStack(spacing: 10) {
                Text(era.title).font(.display(30)).tracking(-0.8).displayTrim(30)
                if let average {
                    SkewTag(text: String(format: "%+.1f%% avg", average), color: era.color, textColor: era.tagText)
                }
                if sample {
                    Text("SAMPLE").font(.mono(10)).tracking(1.2).foregroundStyle(Theme.subtle)
                }
            }
            if top.isEmpty {
                Text("No big movers in this era this\u{00A0}week.")
                    .font(.geist(14)).foregroundStyle(Theme.muted)
                    .frame(maxWidth: .infinity, minHeight: 80)
            } else {
                VStack(spacing: 0) {
                    fan(Array(top.prefix(3)))
                        .frame(maxWidth: .infinity)
                        .padding(.top, 10)
                        .padding(.bottom, 22)
                    ForEach(Array(top.enumerated()), id: \.element.id) { i, hit in
                        if i > 0 { Divider().overlay(Color.white.opacity(0.06)) }
                        link(hit) { row(i + 1, hit) }
                    }
                }
                // Straight on the card's color (no dark panel behind the cards), with a little room
                // under the list.
                .padding(.bottom, 8)
            }
        }
        .tinted(era.color)
        .cardSequence(sample ? [] : top.map(\.product.id))
        // Sample cards: their real pages looked up now, so tapping one opens at once.
        .task(id: sample) { if sample { await Self.prefetch(top) } }
        // Most of the screen, so the next era peeks in.
        .containerRelativeFrame(.horizontal) { width, _ in width - 32 - 28 }
    }

    /// The three biggest risers fanned out from the middle (the first in front), each opening its page.
    private func fan(_ shown: [SearchHit]) -> some View {
        let mid = Double(shown.count - 1) / 2
        let order = shown.count == 3 ? [1, 0, 2] : Array(0 ..< shown.count)
        return HStack(spacing: -26) {
            ForEach(order, id: \.self) { k in
                let hit = shown[k]
                let i = Double(order.firstIndex(of: k) ?? 0)
                link(hit) {
                    ProductImage(product: hit.pictured, cornerRadius: 4)
                        .frame(width: 84, height: 117)
                        .shadow(color: .black.opacity(0.4), radius: 8, y: 5)
                }
                .rotationEffect(.degrees((i - mid) * 9), anchor: .bottom)
                .offset(y: abs(i - mid) * 6)
                .zIndex(k == 0 ? 2 : 0)
            }
        }
    }

    /// One riser: its place, small art, name and set, then price and its week's rise.
    private func row(_ place: Int, _ hit: SearchHit) -> some View {
        HStack(spacing: 10) {
            Text("\(place)").font(.mono(11)).foregroundStyle(Theme.subtle).frame(width: 14, alignment: .leading)
            ProductImage(product: hit.pictured, cornerRadius: 2).frame(width: 30, height: 42)
            VStack(alignment: .leading, spacing: 2) {
                Text(hit.product.name).font(.geist(14, .medium)).foregroundStyle(.white).lineLimit(1)
                if let set = hit.product.setName {
                    Text(set).font(.geist(12)).foregroundStyle(Theme.muted).lineLimit(1)
                }
            }
            Spacer(minLength: 8)
            VStack(alignment: .trailing, spacing: 2) {
                Text(Format.money(hit.market)).font(.display(15)).tracking(-0.3).monospacedDigit().foregroundStyle(.white)
                ChangeText(pct: hit.change7dPct)
            }
        }
        .padding(.vertical, 8)
        .contentShape(Rectangle())
    }
}
