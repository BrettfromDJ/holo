import Charts
import SwiftUI

/// Home: what's happening across the hobby, not your collection (that's on Collection).
/// The card of the week, the hottest and coldest movers, the top 10 risers, the newest set's
/// chase cards, hot sealed and sets just out and coming (from the prices Dexora stores, sent
/// with Explore's index).
/// One strip at the top for you: your collection's worth, tapping through to Collection.
struct MarketHomeView: View {
    @Environment(CollectionStore.self) private var store
    /// Cards on Home grow into their card page when tapped (iOS 18 and later).
    @Namespace private var cardZoom
    /// Home's market lists: the copy saved last time (read as the app started), then fresh.
    @State private var index: ExploreIndex? = SavedExplore.preloaded
    /// "Today in the hobby" and why the highlighted cards moved (written daily by Claude).
    @State private var insights: MarketInsights? = MarketInsights.launchSaved
    /// For you: picks from your collection (Because you collect…, Finish your sets).
    @State private var forYou = ForYouModel()
    /// How each era's market moved (Rising by era), kept on the phone between visits.
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
                    // (Today in the hobby was removed: the owner's call.)
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
            .environment(\.cardZoom, cardZoom)
            .background(Theme.background)
            .tabTopReset("home", path: $path)
            .tabBarClearance()
            .imageMaxPixel(480)
            .sparkRefresh { fresh = false; await load() }
            // Inline: a large-title bar left a tall empty band under "Home".
            .navigationBarTitleDisplayMode(.inline)
            .pageTitle("Home")
            .navigationDestination(for: String.self) { ProductDetailView(productId: $0).zoomTransition(id: $0, in: cardZoom) }
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
        // Themed collections between the market's own lists, each a plain row of big cards.
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
        themeRows(shown, 11..<max(11, shown.count))
        // Your lists last, as rows like the collections.
        if !Demo.isOn { HomeListRows() }
        // (A Cooling off row here repeated the Cooling off tile at the top: removed.)
    }

    /// Some of this open's collections, by position.
    @ViewBuilder private func themeRows(_ shown: [MarketTheme], _ range: Range<Int>) -> some View {
        let r = range.clamped(to: 0..<shown.count)
        ForEach(Array(r), id: \.self) { i in
            ThemeSection(theme: shown[i]).id(shown[i].id)
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

/// The top of Home: today's biggest riser as a clean poster, like a streaming app's featured
/// title: the card big on its own blurred art, its name, one line (what it is, its set, its move)
/// and two buttons. Without today's movers the week's top riser stands in, and without any market
/// moves the newest set's top pull.
private struct CardOfTheDay: View {
    enum Kind { case day, week, topPull(String) }
    var hit: SearchHit
    var kind: Kind
    /// (Kept for the call sites; the clean poster shows no AI line or fun fact.)
    var reason: String? = nil
    var fact: String? = nil
    @Environment(CollectionStore.self) private var store
    @State private var saving = false

    var body: some View {
        let p = hit.pictured
        let pct: Double? = switch kind { case .day: hit.change24hPct; case .week: hit.change7dPct; case .topPull: nil }
        let tag: String = switch kind { case .day: "Card of the day"; case .week: "Card of the week"; case .topPull: "Top pull" }
        let down = (pct ?? 0) < 0
        let tone = down ? Theme.planPink : Theme.lime
        let shape = RoundedRectangle(cornerRadius: 24, style: .continuous)
        VStack(spacing: 0) {
            // The card, big, on a soft glow of its move's color.
            MarketLink(hit: hit) {
                ProductImage(product: p, cornerRadius: 12, large: true)
                    .cardZoomSource(p.id)
                    .frame(width: 236, height: 330)
                    .shadow(color: .black.opacity(0.6), radius: 24, y: 14)
                    .frame(maxWidth: .infinity)
                    .padding(.top, 30)
                    .padding(.bottom, 24)
                    .background {
                        RadialGradient(colors: [tone.opacity(0.3), .clear], center: .center, startRadius: 0, endRadius: 200)
                            .allowsHitTesting(false)
                    }
                    .contentShape(Rectangle())
            }
            VStack(spacing: 10) {
                Text(p.name.noWidow).font(.display(30)).tracking(-1).foregroundStyle(.white)
                    .multilineTextAlignment(.center).lineLimit(2).minimumScaleFactor(0.8)
                // One quiet line, like a film's genres: what it is · its set · its move.
                (Text(tag).font(.geist(14, .semibold)).foregroundStyle(.white)
                 + Text(meta(p)).font(.geist(14)).foregroundStyle(Theme.muted)
                 + Text(pct.map { "  \u{2022}  " + Format.signedPercent($0 / 100) } ?? "").font(.geist(14, .semibold)).foregroundStyle(tone))
                    .multilineTextAlignment(.center)
                    .lineLimit(2)
                HStack(spacing: 10) {
                    // A navigation link can lose its button style inside Home's list, so the
                    // light 3D button is drawn into the label itself.
                    MarketLink(hit: hit) {
                        HStack(spacing: 8) {
                            Image(systemName: "rectangle.portrait.on.rectangle.portrait.angled.fill").font(.system(size: 15, weight: .semibold))
                            Text("View card")
                        }
                        .font(.geist(16, .semibold))
                        .foregroundStyle(Theme.ink)
                        .frame(maxWidth: .infinity, minHeight: 48)
                        .background {
                            let r = RoundedRectangle(cornerRadius: 14, style: .continuous)
                            ZStack {
                                r.fill(Color(hex: 0x8A8A8E)).offset(y: 3)
                                r.fill(Color(hex: 0xF5F5F7))
                                r.fill(LinearGradient(colors: [.white.opacity(0.5), .clear], startPoint: .top, endPoint: .center))
                            }
                            .shadow(color: .black.opacity(0.5), radius: 9, y: 6)
                        }
                        .offset(y: -1)
                        .contentShape(Rectangle())
                    }
                    .buttonStyle(.plain)
                    wishButton(p)
                }
                .padding(.top, 8)
            }
            .padding(.horizontal, 18)
            .padding(.bottom, 18)
        }
        .frame(maxWidth: .infinity)
        .background { backdrop(p, shape: shape) }
        .clipShape(shape)
        .overlay(shape.strokeBorder(Color.white.opacity(0.12), lineWidth: 1))
    }

    private func meta(_ p: Product) -> String {
        guard let set = p.setName, !set.isEmpty else { return "" }
        return "  \u{2022}  " + set
    }

    /// Wishlist: "+ Wishlist", or "On wishlist" once it's there (tap again to take it off).
    private func wishButton(_ p: Product) -> some View {
        let wish = store.wish(for: hit.product.id)
        return Button {
            guard !saving, !Demo.isOn else { return }
            Haptics.tap()
            saving = true
            Task {
                if let wish { try? await store.removeWish(wish.id) } else { try? await store.addWish(hit.product, printing: hit.printing, price: hit.market) }
                saving = false
            }
        } label: {
            HStack(spacing: 8) {
                Image(systemName: wish == nil ? "plus" : "checkmark").font(.system(size: 15, weight: .bold))
                Text(wish == nil ? "Wishlist" : "On wishlist")
            }
            .frame(maxWidth: .infinity)
        }
        .buttonStyle(Button3D(kind: .dark, height: 48))
    }

    /// The card's own art, blown up and blurred, filling the panel, darker toward the bottom so
    /// the text reads.
    private func backdrop(_ p: Product, shape: RoundedRectangle) -> some View {
        ZStack {
            shape.fill(Color(hex: 0x080808))
            CachedImage(url: p.imageURL) { img in img.resizable().scaledToFill() } placeholder: { Color.clear }
                .environment(\.imageFadesIn, false)
                .scaleEffect(1.4)
                .blur(radius: 40, opaque: true)
                .opacity(0.45)
                .drawingGroup()
            LinearGradient(colors: [.black.opacity(0.05), .black.opacity(0.5), .black.opacity(0.92)], startPoint: .top, endPoint: .bottom)
        }
        .allowsHitTesting(false)
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

/// The top 10 risers like a streaming app's Top 10: each card, the same size as every other row's,
/// standing in front of its rank in a huge outlined numeral; the price and the week's rise on its
/// glass pill. No boxes, no text under the cards.
private struct TopTenRow: View {
    var hits: [SearchHit]

    var body: some View {
        ScrollView(.horizontal, showsIndicators: false) {
            LazyHStack(alignment: .bottom, spacing: 14) {
                ForEach(Array(hits.enumerated()), id: \.element.id) { i, hit in
                    MarketLink(hit: hit) {
                        HStack(alignment: .bottom, spacing: i + 1 >= 10 ? -34 : -26) {
                            RankNumeral(rank: i + 1)
                            Poster(product: hit.pictured, price: hit.market, change: hit.change7dPct)
                                // The shadow from a plain card shape behind it, not over the glass pill.
                                .background(RoundedRectangle(cornerRadius: 8, style: .continuous).fill(.black).shadow(color: .black.opacity(0.6), radius: 10, x: -4, y: 4))
                        }
                    }
                    .buttonStyle(.plain)
                }
            }
            .padding(.horizontal, 16)
        }
        .frame(height: Poster.height + 4)
    }
}

/// A rank in huge numerals: dark inside, a thin light outline (a few offset copies make the
/// outline; drawn once, nothing animates).
private struct RankNumeral: View {
    var rank: Int

    var body: some View {
        let text = Text("\(rank)").font(.display(180)).tracking(-12)
        ZStack {
            ForEach(0..<8, id: \.self) { k in
                let a = Double(k) * .pi / 4
                text.foregroundStyle(Color.white.opacity(0.55)).offset(x: cos(a) * 1.5, y: sin(a) * 1.5)
            }
            text.foregroundStyle(Theme.background)
        }
        .fixedSize()
        // The numeral's empty space under its baseline drops below the row, flush with the card.
        .offset(y: 20)
        .frame(height: Poster.height, alignment: .bottom)
        .clipped()
        .accessibilityLabel("Number \(rank)")
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
                SetArt(set: set).opacity(0.45).blur(radius: 14).drawingGroup()
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
