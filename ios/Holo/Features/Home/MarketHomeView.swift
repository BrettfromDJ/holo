import SwiftUI

/// Home: what's happening across the hobby, not your collection (that's on Collection).
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
                VStack(alignment: .leading, spacing: 32) {
                    // Straight in: your collection in one line, then the card of the day (no big
                    // heading taking the top of the screen).
                    if store.status == .ready, !store.holdings.isEmpty {
                        // 10pt above Card of the day, the same gap as between the three tiles
                        // under it (the page's sections are 32 apart).
                        YourCollectionStrip().padding(.horizontal, 16).padding(.bottom, -22)
                    }
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
        VStack(spacing: 10) {
            if let star = index.today?.first {
                CardOfTheDay(hit: star, kind: .day)
            } else if let star = trending.first {
                CardOfTheDay(hit: star, kind: .week)
            } else if let chase, let top = chase.hits.first {
                // No market moves to show: the newest set's top pull takes the stage instead.
                CardOfTheDay(hit: top, kind: .topPull(chase.set.name))
            }
            if !trending.isEmpty || !drops.isEmpty {
                HStack(spacing: 10) {
                    // The week's top risers (after Card of the day's, when that's the week's too) and
                    // the biggest fallers, five each, cycling.
                    let risers = Array((index.today?.first == nil ? Array(trending.dropFirst()) : trending).prefix(5))
                    if !risers.isEmpty { HotColdTile(hits: risers, hot: true) }
                    if !drops.isEmpty { HotColdTile(hits: Array(drops.prefix(5)), hot: false) }
                }
            }
        }
        .padding(.horizontal, 16)
        if trending.count > 2 {
            section(icon: "trophy.fill", "Top 10 this week", "Singles rising most in 7 days") {
                TopTenRow(hits: Array(trending.prefix(10))).cardSequence(trending.prefix(10).map(\.product.id))
            }
        }
            let modern = index.eras?.modern ?? [], midEra = index.eras?.midEra ?? [], vintage = index.eras?.vintage ?? []
            // One color card per era, like Collection's sealed and singles boxes: modern in lime,
            // mid-era in blue, vintage in pink. An era with no risers this week says so.
            section(icon: "hourglass", "Rising by era", "This week's risers, from modern to vintage") {
                // Side by side, swiped one at a time; the next card peeks in at the edge.
                ScrollView(.horizontal, showsIndicators: false) {
                    HStack(alignment: .top, spacing: 12) {
                        // Made-up risers stand in for an era with none yet (marked Sample).
                        EraCard(era: .modern, hits: modern.isEmpty ? EraCard.sample(.modern) : modern, sample: modern.isEmpty)
                        EraCard(era: .midEra, hits: midEra.isEmpty ? EraCard.sample(.midEra) : midEra, sample: midEra.isEmpty)
                        EraCard(era: .vintage, hits: vintage)
                    }
                    .scrollTargetLayout()
                }
                .contentMargins(.horizontal, 16, for: .scrollContent)
                .scrollTargetBehavior(.viewAligned)
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
            section(icon: "shippingbox.fill", "Hot sealed", "Sealed rising most in 7 days") { HotSealedRow(hits: Array(hot.prefix(10))) }
        }
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
        if drops.count > 5 {
            section(icon: "snowflake", "Cooling off", "Singles down most in 7 days") { MoverCarousel(hits: Array(drops.dropFirst(5).prefix(10))) }
        }
    }

    private func section<C: View>(icon: String, _ title: String, _ subtitle: String, @ViewBuilder content: () -> C) -> some View {
        section(icon: icon, title, subtitle, content: content) { EmptyView() }
    }

    private func section<C: View, L: View>(icon: String, _ title: String, _ subtitle: String, @ViewBuilder content: () -> C, @ViewBuilder link: () -> L) -> some View {
        VStack(alignment: .leading, spacing: 14) {
            HStack(alignment: .lastTextBaseline) {
                // The title with a small, quiet icon beside it, then the line under it.
                VStack(alignment: .leading, spacing: 6) {
                    HStack(alignment: .firstTextBaseline, spacing: 8) {
                        // Quiet: white made see-through (Theme.subtle), never lime or a grey color.
                        Image(systemName: icon).font(.system(size: 16, weight: .medium)).foregroundStyle(Theme.subtle)
                        Text(title).font(.display(22)).tracking(22 * -0.03).lineLimit(1).minimumScaleFactor(0.8).displayTrim(22)
                    }
                    Text(subtitle.noWidow).font(.geist(15)).foregroundStyle(Theme.muted)
                }
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
        // The last 30 days (as Collection's header): its line, colored by whether it's up.
        let month = Array(store.timeline.suffix(31))
        let monthChange = (month.last?.value ?? 0) - (month.first?.value ?? 0)
        let tint = monthChange < 0 ? Theme.planPink : Theme.lime
        Button { Router.shared.tabRequest = "collection-summary" } label: {
            VStack(alignment: .leading, spacing: 10) {
                HStack {
                    MonoLabel(text: "Your collection")
                    Spacer(minLength: 8)
                    Text("\(Int(s.items)) items").font(.mono(10)).tracking(0.8).foregroundStyle(Theme.subtle)
                    Image(systemName: "chevron.right").font(.system(size: 11, weight: .semibold)).foregroundStyle(Theme.muted)
                }
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
                // Fades to nothing inside its own frame (radius under the height), widened sideways:
                // no edge at the top.
                RadialGradient(colors: [tint.opacity(0.14), .clear], center: .bottom, startRadius: 0, endRadius: 150)
                    .frame(height: 170)
                    .scaleEffect(x: 1.8, y: 1, anchor: .bottom)
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
    private var daily: Bool { if case .day = kind { return true } else { return false } }

    var body: some View {
        let p = hit.pictured
        let pct: Double? = switch kind { case .day: hit.change24hPct; case .week: hit.change7dPct; case .topPull: nil }
        let tag: String = switch kind { case .day: "Card of the day"; case .week: "Card of the week"; case .topPull: "Top pull" }
        let shape = RoundedRectangle(cornerRadius: 22, style: .continuous)
        // A wide tile in the style of Heating up / Cooling off under it: the card on the left with
        // its rays, glow and sparks, the details on the right; the electric border round it all.
        MarketLink(hit: hit) {
            HStack(alignment: .center, spacing: 16) {
                ZStack {
                    // A soft floor of light under the card.
                    // A gradient that fades to nothing inside its own square, squashed flat: no
                    // edge to cut it off (a filled oval showed its rim).
                    RadialGradient(colors: [Theme.lime.opacity(0.45), Theme.lime.opacity(0.12), .clear], center: .center, startRadius: 0, endRadius: 80)
                        .frame(width: 160, height: 160)
                        .scaleEffect(x: 1, y: 0.22)
                        .offset(y: 86)
                        .allowsHitTesting(false)
                    HoloCard(foil: p.isFoil, textured: false, cornerRadius: 8) {
                        ProductImage(product: p, cornerRadius: 8, large: true).frame(width: 118, height: 165)
                    }
                    .drifting()
                    .notTiltable()
                    .frame(width: 118, height: 165)
                }
                .frame(width: 130, height: 190)
                // The rays behind the card, as a background so they never widen the page.
                .background { LightRays().frame(width: 420, height: 420) }
                VStack(alignment: .leading, spacing: 8) {
                    SkewTag(text: tag, icon: "flame.fill")
                    Text(p.name).font(.display(20)).tracking(-0.5).lineLimit(2).minimumScaleFactor(0.85)
                    Text([p.setName, p.rarity].compactMap { $0 }.joined(separator: " · ")).font(.geist(12)).foregroundStyle(Theme.muted).lineLimit(1)
                    Spacer(minLength: 0)
                    if pct != nil {
                        Text(Format.money(hit.market)).font(.display(22)).tracking(-0.6).monospacedDigit().lineLimit(1).minimumScaleFactor(0.7)
                    }
                    // The rise (or, for a top pull, its price) on the lime ribbon, ink on lime.
                    HStack(alignment: .firstTextBaseline, spacing: 5) {
                        Image(systemName: pct == nil ? "crown.fill" : "arrow.up.right").font(.system(size: 13, weight: .heavy))
                        Text(pct == nil ? Format.money(hit.market) : pctText(pct)).font(.display(20)).tracking(-0.5).monospacedDigit().lineLimit(1)
                        Text(pct == nil ? "TOP PULL" : daily ? "TODAY" : "WEEK").font(.mono(9)).tracking(1)
                    }
                    .foregroundStyle(Theme.ink)
                    .padding(.horizontal, 10).padding(.vertical, 4)
                    .background(Theme.lime, in: RoundedRectangle(cornerRadius: 5, style: .continuous))
                    .rotationEffect(.degrees(-3))
                    .shadow(color: Theme.lime.opacity(0.5), radius: 12)
                    .fixedSize()
                }
                .frame(maxWidth: .infinity, alignment: .leading)
                // The price and ribbon sit a little up from the bottom border.
                .padding(.top, 4)
                .padding(.bottom, 14)
            }
            .foregroundStyle(.white)
            .padding(14)
            .frame(maxWidth: .infinity, alignment: .leading)
            .background {
                ZStack {
                    shape.fill(Color(hex: 0x060606))
                    GridPattern(step: 24, opacity: 0.07)
                    RadialGradient(colors: [Theme.lime.opacity(0.3), .clear], center: UnitPoint(x: 0.22, y: 0.5), startRadius: 0, endRadius: 190)
                    RadialGradient(colors: [Theme.planPink.opacity(0.16), .clear], center: .topTrailing, startRadius: 0, endRadius: 200)
                    RadialGradient(colors: [Theme.planBlue.opacity(0.18), .clear], center: .bottomTrailing, startRadius: 0, endRadius: 200)
                    ChaseSparks()
                }
            }
            // Everything inside (the rays too) stays within the rounded tile.
            .clipShape(shape)
            .shadow(color: Theme.lime.opacity(0.2), radius: 20)
            .overlay(ElectricBorder(radius: 22))
        }
    }
}

/// Slow light rays fanning out from behind the card: one turning gradient (a single rotation
/// animation, only while on screen; still under Reduce Motion).
private struct LightRays: View {
    @Environment(\.accessibilityReduceMotion) private var reduceMotion
    @State private var turned = false

    var body: some View {
        AngularGradient(gradient: Gradient(stops: (0 ..< 24).map { i in
            .init(color: i % 2 == 0 ? Theme.lime.opacity(0.16) : .clear, location: Double(i) / 23)
        }), center: .center)
        // Fades out in a circle inside its square (whatever size it's given), so turning never
        // shows the square's edges or corners.
        .mask(GeometryReader { geo in
            RadialGradient(colors: [.black, .clear], center: .center, startRadius: 20, endRadius: min(geo.size.width, geo.size.height) / 2)
        })
        .rotationEffect(.degrees(turned ? 360 : 0))
        .allowsHitTesting(false)
        .onVisibilityChange { on in
            guard !reduceMotion else { return }
            if on {
                withAnimation(.linear(duration: 60).repeatForever(autoreverses: false)) { turned = true }
            } else {
                stopLoop { turned = false }
            }
        }
    }
}

/// Embers rising (fire) or snow falling (ice), the week recap's particles, only while on screen.
private struct TileParticles: View {
    var hot: Bool
    @Environment(\.accessibilityReduceMotion) private var reduceMotion
    @State private var onScreen = true

    var body: some View {
        TimelineView(.animation(minimumInterval: 1.0 / 30, paused: reduceMotion || !onScreen)) { context in
            RecapParticles(theme: hot ? .fire : .ice, time: reduceMotion ? 3 : context.date.timeIntervalSinceReferenceDate)
        }
        .allowsHitTesting(false)
        .onVisibilityChange { visible in if visible != onScreen { onScreen = visible } }
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
            HStack(alignment: .top, spacing: 18) {
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
                                    // No. 1: lime sparks rising behind it and a small lime crown on its
                                    // corner, both outside its layout so it sits level with the rest.
                                    .background {
                                        if i == 0 {
                                            MoteParticles(style: .sparks, color: Theme.lime, count: 12)
                                                .frame(width: 130, height: 170)
                                                .offset(y: -12)
                                        }
                                    }
                                    .overlay(alignment: .topLeading) {
                                        if i == 0 {
                                            Image(systemName: "crown.fill")
                                                .font(.system(size: 15, weight: .bold))
                                                .foregroundStyle(Theme.ink)
                                                .frame(width: 28, height: 28)
                                                .background(Circle().fill(Theme.lime))
                                                .rotationEffect(.degrees(-14))
                                                .offset(x: -9, y: -10)
                                        }
                                    }
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
        guard let id = realIds[p.id] else { return }
        if let hit = realHits[p.id] { store.seed(hit) }
        Router.shared.product = id
    }

    @MainActor
    private static func resolve(_ p: Product) async -> String? {
        if let id = realIds[p.id] { return id }
        let base = p.name.components(separatedBy: " (").first ?? p.name
        let number = p.number?.components(separatedBy: "/").first
        let query = [base, p.setName].compactMap { $0 }.joined(separator: " ")
        guard let hits = try? await Backend.shared.api.search(query), !hits.isEmpty else { return nil }
        let match = hits.first { h in
            guard let number, let n = h.product.number else { return false }
            return n.components(separatedBy: "/").first == number
        } ?? hits.first
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
            Text(era.blurb).font(.geist(14)).foregroundStyle(Theme.muted)
            if top.isEmpty {
                Text("No big movers in this era this\u{00A0}week.")
                    .font(.geist(14)).foregroundStyle(Theme.muted)
                    .frame(maxWidth: .infinity, minHeight: 80)
            } else {
                VStack(spacing: 0) {
                    fan(Array(top.prefix(3)))
                        .frame(maxWidth: .infinity)
                        .padding(.vertical, 10)
                    ForEach(Array(top.enumerated()), id: \.element.id) { i, hit in
                        if i > 0 { Divider().overlay(Color.white.opacity(0.06)) }
                        link(hit) { row(i + 1, hit) }
                    }
                }
                // Straight on the card's color (no dark panel behind the cards).
            }
        }
        // The era's own particles behind everything: lime sparks rising (modern), blue motes
        // drifting (mid-era), pink dust falling and twinkling (vintage).
        .background {
            MoteParticles(style: era == .modern ? .sparks : (era == .midEra ? .motes : .dust), color: era.color, count: 18)
                .opacity(0.8)
                .padding(-16)
                .clipShape(RoundedRectangle(cornerRadius: 20, style: .continuous))
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
