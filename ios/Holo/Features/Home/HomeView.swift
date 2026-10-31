import Charts
import SwiftUI

/// Overview, like the website's: the hero worth, performance, key numbers, the star of the
/// collection, your shelf, where your value sits, movers and what you added recently.
struct HomeView: View {
    var onScan: () -> Void
    @Environment(CollectionStore.self) private var store
    @Environment(GroupsStore.self) private var groups
    @Environment(SessionModel.self) private var session
    @State private var account = false
    @State private var lists = false
    @State private var search = false
    @State private var recap = false
    /// What's pushed on Home (products by id, More pages); -HoloPage opens one for screenshots.
    @State private var path = NavigationPath()
    @State private var adding = false
    @State private var addSearch = false
    /// A moment worth a banner: a milestone reached, or prices just updated.
    @State private var banner: HomeBanner?
    @State private var bannerTick = 0

    var body: some View {
        NavigationStack(path: $path) {
            ScrollView {
                switch store.status {
                case .idle, .loading:
                    ProgressView().padding(.top, 160)
                case let .failed(message):
                    VStack(spacing: 12) {
                        Text("Couldn't load your collection").font(.geist(17, .semibold))
                        Text(message).font(.geist(14)).foregroundStyle(Theme.muted).multilineTextAlignment(.center)
                        Button("Try again") { Task { await reload() } }.buttonStyle(Button3D(kind: .dark, fullWidth: false))
                    }
                    .padding(32)
                case .ready:
                    if store.holdings.isEmpty { empty } else { content }
                }
            }
            .background(Theme.background)
            .imageMaxPixel(720)
            .replaysAnimations()
            .tabBarClearance()
            .refreshable { await refresh() }
            .overlay(alignment: .top) {
                if let banner {
                    BannerView(banner: banner)
                        .padding(.horizontal, 16)
                        .padding(.top, 8)
                        .transition(.move(edge: .top).combined(with: .opacity))
                        .onTapGesture { withAnimation(.spring) { self.banner = nil } }
                }
            }
            .sensoryFeedback(trigger: bannerTick) { _, _ in banner?.isMilestone == true ? .success : .impact(weight: .light) }
            // Milestone banners are off for now (they repeated); checkMilestones() is kept for later.
            .toolbar {
                ToolbarItemGroup(placement: .topBarTrailing) {
                    Button { lists = true } label: { Image(systemName: "heart") }.accessibilityLabel("Watchlist and wishlist")
                    Button { account = true } label: { Image(systemName: "gearshape") }.accessibilityLabel("Account")
                }
            }
            .toolbarBackground(.hidden, for: .navigationBar)
            .navigationBarTitleDisplayMode(.inline)
            .pageTitle("Overview")
            .navigationDestination(for: String.self) { ProductDetailView(productId: $0) }
            // Every page pushes by value, so links inside them (a card, Gains from Analytics) push
            // on top instead of jumping back.
            .navigationDestination(for: MasterSetRoute.self) { MasterSetDetailView(setId: $0.id, setName: $0.name) }
            .navigationDestination(for: MorePage.self) { p in
                switch p {
                case .analytics: AnalyticsView()
                case .gains: GainsView()
                case .grading: GradingView()
                case .masterSets: MasterSetsView()
                case .activity: ActivityView()
                }
            }
            .task {
                if Demo.isOn, path.isEmpty, !MorePage.opened, let p = Demo.value("-HoloPage").flatMap(MorePage.init(rawValue:)) {
                    MorePage.opened = true
                    try? await Task.sleep(nanoseconds: 600_000_000)
                    path.append(p)
                    // -HoloMasterSet: then open your biggest set's page.
                    if ProcessInfo.processInfo.arguments.contains("-HoloMasterSet"), let s = MasterSetDetailView.ownedSets(store.holdings).first {
                        try? await Task.sleep(nanoseconds: 400_000_000)
                        path.append(MasterSetRoute(id: s.id, name: s.name))
                    }
                }
            }
            .sheet(isPresented: $account) { SettingsView() }
            .sheet(isPresented: $lists) { ListsView() }
            .fullScreenCover(isPresented: $search) { SearchScreen() }
            .fullScreenCover(isPresented: $addSearch) { SearchScreen(mode: .add) }
            .fullScreenCover(isPresented: $recap) { WeeklyRecap(store: store) }
            .confirmationDialog("Add to your collection", isPresented: $adding) {
                Button("Scan cards") { onScan() }
                Button("Search and add") { addSearch = true }
            }
        }
    }

    private var content: some View {
        // Lazy: sections below the screen (charts, shelf, movers) are only built as they scroll
        // into view, so opening or coming back to Home is quick.
        LazyVStack(alignment: .leading, spacing: 44) {
            VStack(spacing: 18) {
                if let demo = store.demo {
                    // A reminder that this is a made-up collection (switch it in Account).
                    Button { account = true } label: {
                        HStack(spacing: 6) {
                            SkewTag(text: "Demo", color: Theme.planPink, textColor: .white)
                            Text("\(demo.title) · made-up prices, nothing is saved").font(.geist(12)).foregroundStyle(Theme.muted)
                            Image(systemName: "chevron.right").font(.system(size: 10, weight: .semibold)).foregroundStyle(Theme.subtle)
                        }
                    }
                    .buttonStyle(.plain)
                }
                if groups.selected != GroupsStore.all {
                    // The numbers below cover one portfolio (picked on Collection, or on the website).
                    Button { groups.select(GroupsStore.all, store: store) } label: {
                        HStack(spacing: 6) {
                            Image(systemName: "folder").font(.system(size: 11, weight: .semibold))
                            Text("Showing \(groups.name(of: groups.selected)) · show all").font(.geist(12))
                        }
                        .foregroundStyle(Theme.muted)
                    }
                    .buttonStyle(.plain)
                }
                MarketPulse(store: store)
                // Opens search with the keyboard already up.
                SearchFieldButton(prompt: "Search any card or sealed product") { search = true }
                    .padding(.horizontal, 16)
                Hero(store: store, onRecap: { recap = true }, onAdd: { Router.shared.addMenu = true })
            }
            PerformanceSection(store: store).padding(.horizontal, 16).reveal()
            MetricGrid(store: store, onReload: refresh).padding(.horizontal, 16).reveal()
            Spotlight(store: store).reveal()
            ShelfSection(holdings: store.holdings).reveal()
            ValueSplit(store: store).padding(.horizontal, 16).reveal()
            MoversSection(holdings: store.holdings).padding(.horizontal, 16).reveal()
            RecentSection(items: store.recentPurchases()).padding(.horizontal, 16).reveal()
            MoreSection().padding(.horizontal, 16).reveal()
        }
        .padding(.top, 4)
        .padding(.bottom, 40)
    }

    private var empty: some View {
        VStack(spacing: 16) {
            Image(systemName: "rectangle.stack.badge.plus").font(.system(size: 44)).foregroundStyle(Theme.lime)
            Text("Start your collection").font(.display(30))
            Text("Scan your cards to see what they're worth.").font(.geist(15)).foregroundStyle(Theme.muted).multilineTextAlignment(.center)
            Button { onScan() } label: { Label("Scan cards", systemImage: "viewfinder") }
                .buttonStyle(Button3D(kind: .lime))
        }
        .padding(32)
        .padding(.top, 60)
    }

    private func reload() async {
        if let kind = store.demo { store.loadDemo(kind); return }
        if case let .signedIn(userId, _) = session.state { await store.load(userId: userId) }
    }

    /// Pull to refresh: reload, then say what moved (the figures count to their new values).
    private func refresh() async {
        let before = Dictionary(store.holdings.map { ($0.identity.key, $0.price ?? 0) }, uniquingKeysWith: { a, _ in a })
        await reload()
        _ = before // The "Prices updated" banner is off for now; the numbers still count to their new values.
    }

    private func show(_ b: HomeBanner) {
        withAnimation(.spring(response: 0.45, dampingFraction: 0.8)) { banner = b }
        bannerTick += 1
        let id = b.id
        Task {
            try? await Task.sleep(for: .seconds(b.isMilestone ? 5 : 2.5))
            if banner?.id == id { withAnimation(.easeOut) { banner = nil } }
        }
    }

    /// Celebrates a new milestone once (shared with the website's "milestones-seen"). On the very
    /// first run only the best one shows, so an existing collection isn't greeted by a flood.
    private func checkMilestones() async {
        let reached = Milestones.reached(summary: store.summary, holdings: store.holdings)
        guard !reached.isEmpty else { return }
        let stored = (try? await UserState.load("milestones-seen", as: [String].self)) ?? nil
        let seen = Set(stored ?? [])
        let fresh = reached.filter { !seen.contains($0.id) }.sorted { $0.rank > $1.rank }
        guard !fresh.isEmpty else { return }
        if let best = fresh.first {
            show(HomeBanner(title: best.title, detail: best.detail, isMilestone: true))
        }
        if case let .signedIn(userId, _) = session.state {
            try? await UserState.save("milestones-seen", Array(seen.union(fresh.map(\.id))), userId: userId)
        }
    }
}

/// The logo and wordmark, top left.
struct BrandMark: View {
    var body: some View {
        HStack(spacing: 8) {
            Image(systemName: "circle.circle")
                .font(.system(size: 17, weight: .bold))
                .foregroundStyle(Theme.ink)
                .frame(width: 30, height: 30)
                .background(RoundedRectangle(cornerRadius: 8).fill(Color(hex: 0xF5F5F7)))
            Text("Lucent").font(.geist(19, .semibold))
        }
    }
}

// MARK: - Hero

/// Lucent's Overview top: a glowing card with your collection's worth (green-teal when you're up
/// overall, pink-orange when down), its all-time change and a dial showing where today sits in
/// the last 30 days; then Today and Invested as smaller glow tiles.
private struct Hero: View {
    var store: CollectionStore
    var onRecap: () -> Void
    var onAdd: () -> Void

    /// The last 30 days' low and high, and where today sits between them.
    private var range: (low: Double, high: Double, at: Double)? {
        let recent = store.timeline.suffix(31).map(\.value).filter { $0 > 0 }
        guard let low = recent.min(), let high = recent.max(), high > low, let now = recent.last else { return nil }
        return (low, high, (now - low) / (high - low))
    }

    var body: some View {
        let s = store.summary
        VStack(spacing: 10) {
            GlowCard(palette: .tone(s.gain), padding: 20) {
                VStack(alignment: .leading, spacing: 0) {
                    HStack(alignment: .top) {
                        GlowLabel(text: "Your collection")
                        Spacer()
                        GlowLabel(text: "\(Int(s.items)) items")
                    }
                    GlowFigure(value: s.value, size: 60).padding(.top, 16)
                    HStack(spacing: 8) {
                        if let r = s.gainRatio { GlowPill(text: (r < 0 ? "▼ " : "▲ ") + Format.signedPercent(abs(r)).replacingOccurrences(of: "+", with: "")) }
                        Text("\(Format.signedMoney(s.gain)) all time").font(.geist(13, .medium)).monospacedDigit()
                    }
                    .padding(.top, 12)
                    if let range {
                        GlowDial(fraction: range.at, low: Format.moneyWhole(range.low), high: Format.moneyWhole(range.high), caption: "30-day range")
                            .frame(height: 150)
                            .padding(.top, 26)
                            .padding(.horizontal, 12)
                    }
                }
            }
            HStack(spacing: 10) {
                GlowCard(palette: .tone(s.dayChange), padding: 16) {
                    VStack(alignment: .leading, spacing: 0) {
                        GlowLabel(text: "Today")
                        Spacer(minLength: 34)
                        GlowFigure(value: s.dayChange, size: 34, signed: true, cents: false)
                        Text(Format.signedPercent(s.dayRatio)).font(.geist(13)).monospacedDigit().opacity(0.75).padding(.top, 2)
                    }
                    .frame(height: 112, alignment: .topLeading)
                }
                GlowCard(palette: .violet, padding: 16) {
                    VStack(alignment: .leading, spacing: 0) {
                        GlowLabel(text: "Invested")
                        Spacer(minLength: 34)
                        GlowFigure(value: s.totalCost, size: 34, cents: false)
                        Text("across \(store.holdings.count) products").font(.geist(13)).opacity(0.75).padding(.top, 2)
                    }
                    .frame(height: 112, alignment: .topLeading)
                }
            }
            // The website's floating action bar: your week's recap and the lime add button.
            // Widths split 1 : 1.4 like the website, on one line each.
            GeometryReader { geo in
                let week = (geo.size.width - 8) / 2.4
                HStack(spacing: 8) {
                    Button(action: onRecap) { Label("Your week", systemImage: "play.fill").lineLimit(1) }
                        .buttonStyle(Button3D(kind: .dark, height: 48))
                        .frame(width: week)
                    Button(action: onAdd) { Label("Add to Collection", systemImage: "plus").lineLimit(1) }
                        .buttonStyle(Button3D(kind: .lime, height: 48))
                }
            }
            .frame(height: 48)
            // The buttons rise 1pt and their 3D edge drops 3pt, so 9 above and 10 below
            // leaves the same 8pt visible gap at the top and the bottom.
            .padding(.horizontal, 8)
            .padding(.top, 9)
            .padding(.bottom, 10)
            .liquidGlass(in: RoundedRectangle(cornerRadius: 22, style: .continuous))
            .shadow(color: .black.opacity(0.5), radius: 24, y: 12)
            .padding(.top, 8)
        }
        .padding(.horizontal, 14)
        .padding(.vertical, 12)
    }
}

// MARK: - Performance

private struct PerformanceSection: View {
    var store: CollectionStore
    @State private var range = Range.month
    @State private var scrubbed: Date?

    enum Range: String, CaseIterable {
        case day = "1D", week = "1W", month = "1M", quarter = "3M", year = "1Y", all = "ALL"

        var days: Int? {
            switch self {
            case .day: return 1
            case .week: return 7
            case .month: return 30
            case .quarter: return 90
            case .year: return 365
            case .all: return nil
            }
        }

        var phrase: String {
            switch self {
            case .day: return "Today"
            case .week: return "Past week"
            case .month: return "Past month"
            case .quarter: return "Past 3 months"
            case .year: return "Past year"
            case .all: return "All time"
            }
        }
    }

    private var points: [TimelinePoint] {
        guard let days = range.days else { return store.timeline }
        return Array(store.timeline.suffix(days + 1))
    }

    private var shown: TimelinePoint? {
        guard let scrubbed else { return nil }
        return points.min { abs($0.day.timeIntervalSince(scrubbed)) < abs($1.day.timeIntervalSince(scrubbed)) }
    }

    var body: some View {
        let first = points.first?.value ?? 0
        let end = points.last?.value ?? 0
        let last = shown?.value ?? end
        let change = last - first
        // The card's color follows the whole range (not the scrubbed day), so it doesn't flip
        // while you drag.
        let palette: GlowPalette = (end - first) < 0 ? .down : .gold
        let shape = RoundedRectangle(cornerRadius: 28, style: .continuous)
        VStack(alignment: .leading, spacing: 14) {
            PageHeader(title: "Performance", size: 30)
            VStack(alignment: .leading, spacing: 0) {
                GlowLabel(text: shown.map { $0.day.formatted(date: .abbreviated, time: .omitted) } ?? range.phrase,
                          secondary: shown == nil ? "Drag across the chart to see any day" : "Closing value")
                Text(Format.money(last))
                    .font(.geist(44)).tracking(-1.8).monospacedDigit()
                    .lineLimit(1).minimumScaleFactor(0.5)
                    .padding(.top, 14)
                HStack(spacing: 8) {
                    if first > 0 {
                        GlowPill(text: (change < 0 ? "▼ " : "▲ ") + Format.signedPercent(abs(change / first)).replacingOccurrences(of: "+", with: ""))
                    }
                    Text(Format.signedMoney(change)).font(.geist(13, .medium)).monospacedDigit()
                }
                .padding(.top, 10)
                if points.count > 1 {
                    let values = points.map(\.value)
                    let domain = ChartTicks.domain(values)
                    Chart {
                        ForEach(points) { p in
                            AreaMark(x: .value("Day", p.day), yStart: .value("Floor", domain.lowerBound), yEnd: .value("Value", p.value))
                                .foregroundStyle(LinearGradient(colors: [Color.white.opacity(0.28), Color.white.opacity(0)], startPoint: .top, endPoint: .bottom))
                                .interpolationMethod(.monotone)
                            LineMark(x: .value("Day", p.day), y: .value("Value", p.value), series: .value("Line", "Value"))
                                .foregroundStyle(Color.white)
                                .lineStyle(StrokeStyle(lineWidth: 2))
                                .interpolationMethod(.monotone)
                        }
                        if let shown {
                            RuleMark(x: .value("Day", shown.day))
                                .foregroundStyle(Color.white.opacity(0.6))
                                .lineStyle(StrokeStyle(lineWidth: 1, dash: [1.5, 4]))
                            PointMark(x: .value("Day", shown.day), y: .value("Value", shown.value))
                                .foregroundStyle(Color(hex: 0xFFF36A))
                                .symbolSize(70)
                        }
                    }
                    .chartXAxis(.hidden)
                    .chartYAxis(.hidden)
                    .chartYScale(domain: domain)
                    .chartXSelection(value: $scrubbed)
                    .frame(height: 190)
                    .drawIn(replay: range)
                    // A light tick for each day you scrub across; a firmer one on the range's high and low.
                    .sensoryFeedback(trigger: shown?.date) { _, new in
                        guard let new, let point = points.first(where: { $0.date == new }) else { return nil }
                        if point.value == values.max() || point.value == values.min() { return .impact(weight: .medium, intensity: 0.9) }
                        return .selection
                    }
                    .padding(.top, 18)
                    HStack {
                        Text("LOW \(Format.moneyWhole(values.min()))")
                        Spacer()
                        Text("HIGH \(Format.moneyWhole(values.max()))")
                    }
                    .font(.mono(10)).tracking(1.2).opacity(0.7)
                    .padding(.top, 8)
                }
            }
            .padding(18)
            .frame(maxWidth: .infinity, alignment: .leading)
            .foregroundStyle(palette.ink)
            // Equatable, so scrubbing (which redraws this view) never redraws the light.
            .background { HomeStaticGlow(palette: palette).equatable() }
            .clipShape(shape)
            .overlay(shape.strokeBorder(.white.opacity(0.08)))
            ChipPicker(options: Range.allCases.map { ($0, $0.rawValue) }, selection: $range)
            if let end = points.last, points.count > 1 {
                Text("Daily closing values · \(Format.money(end.value)) on \(end.day.formatted(date: .abbreviated, time: .omitted))")
                    .font(.geist(12)).foregroundStyle(Theme.muted)
                    .frame(maxWidth: .infinity, alignment: .trailing)
            }
        }
    }
}

// MARK: - Metric cards

private struct MetricGrid: View {
    var store: CollectionStore
    var onReload: () async -> Void

    var body: some View {
        let s = store.summary
        let whole: (Double) -> String = { GlowFigure.text($0, signed: true, cents: false) }
        let months = Array(Analytics.monthlyActivity(store.portfolioTransactions, today: Format.day()).suffix(10)).map(\.invested)
        let recent = Array(store.timeline.suffix(21)).map(\.value)
        let worths = Array(store.holdings.compactMap(\.value).prefix(18))
        VStack(spacing: 10) {
            // Lucent tiles: a tall one beside two squares, then a wide one, each with its own
            // little graphic and its own colors.
            GlowTallRow {
                NavigationLink(value: MorePage.gains) {
                    GlowTile(label: "Unrealized", note: "Tap for the breakdown", value: whole(s.gain),
                             palette: s.gain < 0 ? .rimRose : .rimTeal, shape: .tall,
                             badge: s.gainRatio.map { pct($0, decimals: 0) }) {
                        GlowSun(fraction: min(abs(s.gainRatio ?? 0), 1)).frame(height: 120)
                    }
                }
                .buttonStyle(.plain)
            } a: {
                GlowTile(label: "Today", value: whole(s.dayChange),
                         palette: s.dayChange < 0 ? .down : .citrus, badge: s.dayRatio.map { pct($0, decimals: 2) }) {
                    GlowLine(values: recent).frame(height: 34)
                }
            } b: {
                GlowTile(label: "Invested", note: "by month", value: Format.moneyWhole(s.totalCost), palette: .rimViolet) {
                    GlowBars(values: months).frame(height: 34)
                }
            }
            Button {
                Router.shared.tabRequest = "collection"
            } label: {
                GlowTile(label: "Collection", note: "\(store.holdings.count) products · each dot one of them", palette: .rimAmber, shape: .wide) {
                    HStack(alignment: .center, spacing: 16) {
                        DotMatrixText(text: "\(Int(s.items.rounded()))", dot: 5)
                        VStack(alignment: .leading, spacing: 6) {
                            Text("items").font(.geist(13)).opacity(0.7)
                            GlowDotRow(values: worths).frame(height: 14)
                        }
                    }
                }
            }
            .buttonStyle(.plain)
            BudgetCard(store: store)
            PriceFreshness(refreshedAt: store.pricesRefreshedAt, onReload: onReload)
        }
    }

    /// "+10%" or "−0.99%", like the website's tags.
    private func pct(_ r: Double, decimals: Int) -> String {
        let v = String(format: "%.\(decimals)f%%", abs(r) * 100)
        return r < 0 ? "−\(v)" : "+\(v)"
    }
}

/// A Lucent glow tile: the mono label (with a pill on the right), the figure counting up in thin
/// Geist, and a short note under it. Every tile is the same height so the grid lines up.
private struct MetricCard: View {
    var label: String
    /// The figure, counted up when the card appears.
    var amount: Double
    var format: (Double) -> String
    var sub: String?
    var palette: GlowPalette
    var tag: String? = nil

    var body: some View {
        GlowCard(palette: palette, radius: 26, padding: 16) {
            VStack(alignment: .leading, spacing: 0) {
                HStack(alignment: .top, spacing: 6) {
                    GlowLabel(text: label).lineLimit(1)
                    Spacer(minLength: 4)
                    if let tag { GlowPill(text: tag) }
                }
                Spacer(minLength: 14)
                CountingText(value: amount, format: format)
                    .font(.geist(30)).tracking(-1.2).monospacedDigit()
                    .lineLimit(1).minimumScaleFactor(0.55)
                Text(sub ?? " ").font(.geist(12)).opacity(0.75).lineLimit(1).padding(.top, 4)
            }
            .frame(height: 112, alignment: .topLeading)
        }
        .contentShape(RoundedRectangle(cornerRadius: 26, style: .continuous))
    }
}

/// Spent this month against an optional monthly budget, on a glow card: indigo while you're
/// fine, flame when you're close, pink when you're over. The tick bar shows how much is used.
private struct BudgetCard: View {
    var store: CollectionStore
    @State private var editing = false
    @State private var draft = ""
    @State private var error: String?

    var body: some View {
        let spent = store.spentThisMonth
        let budget = store.monthlyBudget
        let remaining = budget.map { $0 - spent }
        let used = budget.flatMap { $0 > 0 ? spent / $0 : nil }
        let over = (remaining ?? 0) < 0
        let near = !over && (used ?? 0) >= 0.85
        let palette: GlowPalette = over ? .down : near ? .flame : .indigo
        GlowCard(palette: palette, radius: 26, padding: 18) {
            VStack(alignment: .leading, spacing: 0) {
                HStack(alignment: .top, spacing: 8) {
                    GlowLabel(text: "Spent in \(Date().formatted(.dateTime.month(.wide)))",
                              secondary: budget.map { "of \(Format.moneyWhole($0)) budget" } ?? "No monthly budget yet")
                    Spacer(minLength: 8)
                    // Edit sits in the card's top-right corner.
                    Button {
                        draft = budget.map { String(format: "%.0f", $0) } ?? ""
                        editing = true
                    } label: {
                        if budget != nil { Label("Edit", systemImage: "pencil") } else { Text("Set budget") }
                    }
                    .buttonStyle(HomeGlowButton())
                }
                GlowFigure(value: spent, size: 40).padding(.top, 18)
                if let remaining {
                    Text(over ? "\(Format.money(abs(remaining))) over budget" : "\(Format.money(remaining)) left")
                        .font(.geist(13, .medium)).monospacedDigit().opacity(0.85)
                        .padding(.top, 4)
                }
                if let used {
                    GlowTicks(fraction: min(used, 1)).frame(height: 22).padding(.top, 16)
                    let projected = projection(spent)
                    if !over, spent > 0, let budget, projected > budget {
                        Text("At this pace you'll spend about \(Format.money(projected)) this month.")
                            .font(.geist(12)).opacity(0.75)
                            .padding(.top, 10)
                    }
                }
                if let error { Text(error).font(.geist(12)).padding(.top, 10) }
            }
        }
        .alert("Monthly budget", isPresented: $editing) {
            TextField("500", text: $draft).keyboardType(.decimalPad)
            Button("Save") { save(Double(draft.filter { "0123456789.".contains($0) })) }
            if budget != nil { Button("Remove", role: .destructive) { save(nil) } }
            Button("Cancel", role: .cancel) {}
        } message: {
            Text("How much you want to spend on cards each month.")
        }
    }

    private func projection(_ spent: Double) -> Double {
        let cal = Calendar.current
        let day = cal.component(.day, from: Date())
        let days = cal.range(of: .day, in: .month, for: Date())?.count ?? 30
        return spent / Double(max(day, 1)) * Double(days)
    }

    private func save(_ value: Double?) {
        let v = value.flatMap { $0 > 0 ? ($0 * 100).rounded() / 100 : nil }
        Task {
            do {
                error = nil
                try await store.setMonthlyBudget(v)
            } catch {
                self.error = "Couldn't save your budget: \(error.localizedDescription)"
            }
        }
    }
}

/// "Prices from TCG API · refreshed 1d ago · updates daily · Refresh", like the website.
private struct PriceFreshness: View {
    var refreshedAt: Date?
    var onReload: () async -> Void
    @State private var refreshing = false

    var body: some View {
        HStack(spacing: 12) {
            Text("Prices from TCG API · refreshed \(ago) · updates daily").lineLimit(2)
            Button {
                refreshing = true
                Task { await onReload(); refreshing = false }
            } label: {
                HStack(spacing: 4) {
                    Image(systemName: "arrow.clockwise").font(.system(size: 11, weight: .semibold))
                        .rotationEffect(.degrees(refreshing ? 360 : 0))
                        .animation(refreshing ? .linear(duration: 0.8).repeatForever(autoreverses: false) : .default, value: refreshing)
                    Text("Refresh").fontWeight(.medium)
                }
                .foregroundStyle(Theme.muted)
            }
            .buttonStyle(.plain)
            .disabled(refreshing)
        }
        .font(.geist(12))
        .foregroundStyle(Theme.subtle)
        .frame(maxWidth: .infinity, alignment: .leading)
    }

    private var ago: String {
        guard let d = refreshedAt else { return "never" }
        let minutes = Int((Date().timeIntervalSince(d) / 60).rounded())
        if minutes < 1 { return "just now" }
        if minutes < 60 { return "\(minutes)m ago" }
        let hours = Int((Double(minutes) / 60).rounded())
        if hours < 24 { return "\(hours)h ago" }
        return "\(Int((Double(hours) / 24).rounded()))d ago"
    }
}

// MARK: - Spotlight

/// The star (biggest gain) on a glow card in its own colors, the biggest move today, and the one
/// most below what you paid.
private struct Spotlight: View {
    var store: CollectionStore
    @State private var current: String?

    var body: some View {
        let cards = Self.cards(store)
        if !cards.isEmpty {
            VStack(spacing: 14) {
                // Lucent: big glowing cards you swipe through, the centered one full size and its
                // neighbours peeking at the edges; dots show where you are.
                ScrollView(.horizontal, showsIndicators: false) {
                    LazyHStack(spacing: 12) {
                        ForEach(cards) { card in
                            SpotCard(card: card)
                                .containerRelativeFrame(.horizontal)
                                .scrollTransition(.interactive, axis: .horizontal) { view, phase in
                                    view.scaleEffect(phase.isIdentity ? 1 : 0.9).opacity(phase.isIdentity ? 1 : 0.55)
                                }
                                .id(card.id)
                        }
                    }
                    .scrollTargetLayout()
                }
                .scrollTargetBehavior(.viewAligned)
                .contentMargins(.horizontal, 44, for: .scrollContent)
                .scrollPosition(id: $current)
                .frame(height: SpotCard.height)
                .sensoryFeedback(.selection, trigger: current)
                HStack(spacing: 6) {
                    ForEach(cards) { card in
                        Capsule()
                            .fill(.white.opacity(card.id == (current ?? cards.first?.id) ? 0.95 : 0.25))
                            .frame(width: card.id == (current ?? cards.first?.id) ? 16 : 6, height: 6)
                    }
                }
                .animation(.snappy, value: current)
            }
        }
    }

    /// The cards, in order: your star, today's biggest move, the one below what you paid, your
    /// best return, the closest master set and a grading pick. Each one only when it exists.
    static func cards(_ store: CollectionStore) -> [SpotCard.Model] {
        let holdings = store.holdings
        var out: [SpotCard.Model] = []
        var used = Set<String>()
        func add(_ m: SpotCard.Model?) { if let m { out.append(m) } }

        if let star = holdings.filter({ ($0.gain ?? 0) > 0 }).max(by: { ($0.gain ?? 0) < ($1.gain ?? 0) }) {
            used.insert(star.id)
            add(.init(id: "star", kicker: "Your star", holding: star, palette: .forProduct(star.identity.productId),
                      value: GlowFigure.text(star.gain ?? 0, signed: true, cents: false), note: "\(Format.signedPercent(star.gainRatio)) on what you paid",
                      line: store.series(star.identity, days: 90).map(\.value), link: .product(star.identity.productId)))
        }
        if let mover = holdings.filter({ ($0.dayChange ?? 0) != 0 && !used.contains($0.id) }).max(by: { abs($0.dayChange ?? 0) < abs($1.dayChange ?? 0) }) {
            used.insert(mover.id)
            add(.init(id: "mover", kicker: "Biggest move today", holding: mover, palette: (mover.dayChange ?? 0) < 0 ? .down : .rimTeal,
                      value: GlowFigure.text(mover.dayChange ?? 0, signed: true, cents: false), note: "\(Format.signedPercent((mover.change24hPct ?? 0) / 100)) today",
                      line: store.series(mover.identity, days: 30).map(\.value), link: .product(mover.identity.productId)))
        }
        if let lag = holdings.filter({ ($0.gainRatio ?? 0) < 0 && !used.contains($0.id) }).min(by: { ($0.gainRatio ?? 0) < ($1.gainRatio ?? 0) }) {
            used.insert(lag.id)
            add(.init(id: "lag", kicker: "Below what you paid", holding: lag, palette: .rimRose,
                      value: GlowFigure.text(lag.gain ?? 0, signed: true, cents: false), note: "\(Format.signedPercent(lag.gainRatio)) vs what you paid",
                      line: store.series(lag.identity, days: 30).map(\.value), link: .product(lag.identity.productId)))
        }
        if let best = holdings.filter({ ($0.gainRatio ?? 0) > 0 && !used.contains($0.id) }).max(by: { ($0.gainRatio ?? 0) < ($1.gainRatio ?? 0) }) {
            used.insert(best.id)
            add(.init(id: "best", kicker: "Best return", holding: best, palette: .citrus,
                      value: Format.signedPercent(best.gainRatio), note: "\(Format.signedMoney(best.gain)) on \(Format.moneyWhole(best.costBasis))",
                      line: store.series(best.identity, days: 90).map(\.value), link: .product(best.identity.productId)))
        }
        if let set = MasterSetDetailView.ownedSets(holdings).first {
            let list = MasterSetsCache.shared.checklists[set.id]
            let ids = Set(set.holdings.map(\.identity.productId))
            let have = list.map { l in ids.intersection(l.map(\.product.id)).count } ?? ids.count
            let ratio = list.map { $0.isEmpty ? 0 : Double(have) / Double($0.count) }
            let cover = set.holdings.max { ($0.value ?? 0) < ($1.value ?? 0) }
            add(.init(id: "set", kicker: "Master set", holding: cover, title: set.name, palette: .rimForProduct(set.id),
                      value: ratio.map { "\(Int(($0 * 100).rounded()))%" } ?? "\(have) cards",
                      note: list.map { "\(have) of \($0.count) cards" } ?? "Tap to see every card",
                      pie: ratio, link: .set(MasterSetRoute(id: set.id, name: set.name))))
        }
        if let pick = holdings.filter({ !$0.identity.isGraded && $0.product?.isSealed == false && !used.contains($0.id) && ($0.price ?? 0) >= 20 })
            .max(by: { ($0.price ?? 0) < ($1.price ?? 0) }), let raw = pick.price {
            let ten = raw * WorthCalc.multiple(productId: pick.identity.productId, company: "PSA", grade: "10")
            add(.init(id: "grade", kicker: "Worth grading?", holding: pick, palette: .rimAmber,
                      value: "≈ " + Format.moneyWhole(ten), note: "as a PSA 10 · \(Format.moneyWhole(raw)) raw",
                      line: [], link: .page(.grading)))
        }
        return out
    }
}

/// One big card in the Overview spotlight carousel. Every card is the same size.
private struct SpotCard: View {
    enum Link: Hashable { case product(String), set(MasterSetRoute), page(MorePage) }

    struct Model: Identifiable {
        var id: String
        var kicker: String
        var holding: HoldingView?
        var title: String? = nil
        var palette: GlowPalette
        var value: String
        var note: String
        var line: [Double] = []
        var pie: Double? = nil
        var link: Link
    }

    var card: Model
    static let height: CGFloat = 430

    var body: some View {
        switch card.link {
        case let .product(id): NavigationLink(value: id) { face }.buttonStyle(.plain)
        case let .set(route): NavigationLink(value: route) { face }.buttonStyle(.plain)
        case let .page(page): NavigationLink(value: page) { face }.buttonStyle(.plain)
        }
    }

    private var face: some View {
        let shape = RoundedRectangle(cornerRadius: 32, style: .continuous)
        return VStack(alignment: .leading, spacing: 0) {
            Text(card.kicker).font(.geist(15, .semibold))
            Text(card.title ?? card.holding?.product?.name ?? "").font(.geist(12)).opacity(0.7).lineLimit(1)
            Spacer(minLength: 10)
            ZStack {
                if let pie = card.pie {
                    GlowPie(fraction: pie).frame(width: 130)
                } else if let h = card.holding {
                    HoldingArt(product: h.product, identity: h.identity, cornerRadius: 8, caption: false)
                        .frame(width: 128, height: 178)
                        .shadow(color: .black.opacity(0.45), radius: 14, y: 8)
                }
            }
            .frame(maxWidth: .infinity)
            Spacer(minLength: 10)
            Text(card.value).font(.geist(40)).tracking(-1.6).monospacedDigit().lineLimit(1).minimumScaleFactor(0.5)
            Text(card.note).font(.geist(13)).opacity(0.75).lineLimit(1).padding(.top, 2)
            if card.line.count > 1 {
                GlowLine(values: card.line).frame(height: 36).padding(.top, 10)
            } else {
                GlowTicks(fraction: card.pie ?? 0.7).frame(height: 18).padding(.top, 12)
            }
        }
        .padding(20)
        .frame(height: Self.height)
        .frame(maxWidth: .infinity, alignment: .leading)
        .foregroundStyle(card.palette.ink)
        .background { GlowFill(palette: card.palette) }
        .clipShape(shape)
        .overlay(shape.strokeBorder(.white.opacity(0.1)))
    }
}

private struct StarCard: View {
    var holding: HoldingView
    var series: [TimelinePoint]

    /// Sealed sits in a square well, a card at its own shape, a slab in its frame.
    private var artSize: CGSize {
        if holding.identity.isGraded { return CGSize(width: 150, height: 240) }
        if holding.product?.isSealed == false, holding.product?.imageURL != nil { return CGSize(width: 150, height: 209) }
        return CGSize(width: 150, height: 150)
    }

    var body: some View {
        NavigationLink(value: holding.identity.productId) {
            GlowCard(palette: .forProduct(holding.identity.productId), radius: 28, padding: 20) {
                VStack(alignment: .leading, spacing: 0) {
                    GlowLabel(text: "Star of the collection", secondary: "Your biggest gain")
                    // The piece centered, a soft floor shadow, a floating % pill.
                    HoldingArt(product: holding.product, identity: holding.identity, cornerRadius: 12)
                        .frame(width: artSize.width, height: artSize.height)
                        .tiltCard(14, foil: holding.product?.isSealed == false && !holding.identity.isGraded, cornerRadius: 12)
                        .background(alignment: .bottom) {
                            Ellipse().fill(.black.opacity(0.45)).frame(width: artSize.width * 0.76, height: 30).blur(radius: 14).offset(y: 16)
                        }
                        .overlay(alignment: .topTrailing) {
                            if let r = holding.gainRatio {
                                GlowPill(text: "▲ " + Format.signedPercent(abs(r)).replacingOccurrences(of: "+", with: "").replacingOccurrences(of: #"\.\d+%"#, with: "%", options: .regularExpression))
                                    .offset(x: 16, y: artSize.height * 0.08)
                            }
                        }
                        .frame(maxWidth: .infinity)
                        .padding(.top, 24)
                    Text(holding.product?.name ?? "").font(.geist(22, .semibold)).lineLimit(2)
                        .padding(.top, 30)
                    Text([holding.product?.setName, holding.label].compactMap { $0 }.joined(separator: " · "))
                        .font(.geist(13)).opacity(0.75).lineLimit(1)
                        .padding(.top, 4)
                    GlowFigure(value: holding.gain ?? 0, size: 52, signed: true, cents: false)
                        .padding(.top, 18)
                    HStack(spacing: 8) {
                        stat("Paid", Format.money(holding.costBasis))
                        stat("Worth", Format.money(holding.value))
                        stat("Return", Format.signedPercent(holding.gainRatio))
                    }
                    .padding(.top, 18)
                    if series.count > 1 {
                        Sparkline(points: series, color: .white).frame(height: 52).padding(.top, 20)
                        Text("LAST 90 DAYS").font(.mono(10)).tracking(1.2).opacity(0.7).padding(.top, 6)
                    }
                }
            }
        }
        .buttonStyle(.plain)
    }

    private func stat(_ label: String, _ value: String) -> some View {
        VStack(alignment: .leading, spacing: 4) {
            Text(label.uppercased()).font(.mono(10)).tracking(1.2).opacity(0.7)
            Text(value).font(.geist(14, .semibold)).monospacedDigit().lineLimit(1).minimumScaleFactor(0.7)
        }
        .padding(.horizontal, 12)
        .padding(.vertical, 10)
        .frame(maxWidth: .infinity, alignment: .leading)
        .background(.black.opacity(0.22), in: RoundedRectangle(cornerRadius: 12, style: .continuous))
    }
}

private struct MiniTile: View {
    var holding: HoldingView
    var tag: String
    var icon: String
    var palette: GlowPalette
    var value: Double?
    var line: String
    var series: [TimelinePoint]
    var baseline: Double?

    var body: some View {
        NavigationLink(value: holding.identity.productId) {
            GlowCard(palette: palette, radius: 26, padding: 16) {
                VStack(alignment: .leading, spacing: 14) {
                    HStack(alignment: .top) {
                        GlowLabel(text: tag)
                        Spacer(minLength: 8)
                        Image(systemName: icon).font(.system(size: 13, weight: .semibold)).opacity(0.85)
                    }
                    HStack(spacing: 14) {
                        HoldingArt(product: holding.product, identity: holding.identity, cornerRadius: 8, caption: false)
                            .frame(width: 64, height: 80)
                            .shadow(color: .black.opacity(0.35), radius: 8, y: 4)
                        VStack(alignment: .leading, spacing: 4) {
                            Text(holding.product?.name ?? "").font(.geist(16, .medium)).lineLimit(1)
                            Text(Format.signedMoney(value)).font(.geist(30)).tracking(-1.2).monospacedDigit()
                                .lineLimit(1).minimumScaleFactor(0.6)
                            Text(line).font(.geist(13, .medium)).monospacedDigit().opacity(0.8)
                        }
                        Spacer(minLength: 0)
                    }
                    if series.count > 1 {
                        Sparkline(points: series, color: .white, baseline: baseline).frame(height: 34)
                    }
                }
            }
        }
        .buttonStyle(.plain)
    }
}

/// A tiny price line, optionally with a dashed line at what you paid.
struct Sparkline: View {
    var points: [TimelinePoint]
    var color: Color
    var baseline: Double? = nil
    /// Wait before drawing in (e.g. until a sheet has slid up).
    var delay: Double = 0

    var body: some View {
        let domain = ChartTicks.domain(points.map(\.value) + (baseline.map { [$0] } ?? []))
        Chart {
            ForEach(points) { p in
                AreaMark(x: .value("Day", p.day), yStart: .value("Floor", domain.lowerBound), yEnd: .value("Value", p.value))
                    .foregroundStyle(LinearGradient(colors: [color.opacity(0.22), .clear], startPoint: .top, endPoint: .bottom))
                    .interpolationMethod(.monotone)
                LineMark(x: .value("Day", p.day), y: .value("Value", p.value)).foregroundStyle(color).interpolationMethod(.monotone)
            }
            if let baseline {
                RuleMark(y: .value("Paid", baseline)).foregroundStyle(.white.opacity(0.35)).lineStyle(StrokeStyle(lineWidth: 1, dash: [4, 4]))
            }
        }
        .chartXAxis(.hidden)
        .chartYAxis(.hidden)
        .chartYScale(domain: domain)
        .drawIn(duration: 1.0, delay: delay)
    }
}

// MARK: - Shelf

/// Your most valuable pieces standing on a glass ledge, each with a price tag below.
private struct ShelfSection: View {
    var holdings: [HoldingView]

    /// Item and stage sizes, as on the website's phone layout.
    static let itemWidth: CGFloat = 150
    static let stageHeight: CGFloat = 200
    static let topPad: CGFloat = 24

    private var items: [HoldingView] {
        Array(holdings.filter { $0.value != nil }.sorted { ($0.value ?? 0) > ($1.value ?? 0) }.prefix(14))
    }

    var body: some View {
        VStack(alignment: .leading, spacing: 16) {
            HStack(alignment: .lastTextBaseline) {
                PageHeader(title: "Your shelf", subtitle: "Your most valuable pieces", size: 30)
                Spacer()
                Button {
                    Router.shared.tabRequest = "collection"
                } label: {
                    HStack(spacing: 4) { Text("See all"); Image(systemName: "arrow.right").font(.system(size: 12, weight: .semibold)) }
                        .font(.geist(13, .medium)).foregroundStyle(Theme.muted)
                }
                .buttonStyle(.plain)
            }
            .padding(.horizontal, 16)

            // No box: the shelf runs edge to edge and fades into the page on every side.
            ScrollView(.horizontal, showsIndicators: false) {
                HStack(alignment: .top, spacing: 24) {
                    ForEach(Array(items.enumerated()), id: \.element.id) { i, h in
                        ShelfItem(holding: h, rank: i + 1)
                    }
                }
                .padding(.horizontal, 24)
                .padding(.top, Self.topPad)
                .padding(.bottom, 16)
                // The ledge runs the full length of the scroll, right where the pieces stand.
                .background(alignment: .topLeading) {
                    VStack(spacing: 0) {
                        Rectangle()
                            .fill(LinearGradient(colors: [.white.opacity(0.22), .white.opacity(0.08)], startPoint: .top, endPoint: .bottom))
                            .overlay(alignment: .top) { Rectangle().fill(.white.opacity(0.4)).frame(height: 1) }
                            .frame(height: 12)
                        Rectangle().fill(.white.opacity(0.05)).frame(height: 8)
                        LinearGradient(colors: [.black.opacity(0.35), .clear], startPoint: .top, endPoint: .bottom).frame(height: 40)
                    }
                    .padding(.top, Self.topPad + Self.stageHeight)
                    .allowsHitTesting(false)
                }
            }
            // Pieces fade out at the edges as they scroll away.
            .mask(LinearGradient(stops: [.init(color: .clear, location: 0), .init(color: .black, location: 0.05),
                                         .init(color: .black, location: 0.95), .init(color: .clear, location: 1)],
                                 startPoint: .leading, endPoint: .trailing))
            // Soft light from above, falling away to the page background.
            .background(
                RadialGradient(colors: [.white.opacity(0.06), .clear], center: UnitPoint(x: 0.5, y: 0.45), startRadius: 0, endRadius: 300)
                    .mask(LinearGradient(stops: [.init(color: .clear, location: 0), .init(color: .black, location: 0.3),
                                                 .init(color: .black, location: 0.7), .init(color: .clear, location: 1)],
                                         startPoint: .top, endPoint: .bottom))
                    .allowsHitTesting(false)
            )
        }
    }
}

/// One piece standing on the shelf under its own spotlight, with its price tag hanging below.
private struct ShelfItem: View {
    var holding: HoldingView
    var rank: Int

    private var isCard: Bool { holding.product?.isSealed == false && holding.product?.imageURL != nil && !holding.identity.isGraded }

    var body: some View {
        NavigationLink(value: holding.identity.productId) {
            VStack(alignment: .leading, spacing: 0) {
                ZStack(alignment: .bottom) {
                    // Spotlight from above.
                    RadialGradient(colors: [.white.opacity(0.08), .clear], center: UnitPoint(x: 0.5, y: 0.35), startRadius: 0, endRadius: 110)
                        .frame(width: 220, height: 240)
                        .offset(y: -24)
                        .frame(width: ShelfSection.itemWidth, height: ShelfSection.stageHeight, alignment: .top)
                        .allowsHitTesting(false)
                    // Contact shadow where it meets the ledge.
                    Ellipse().fill(.black.opacity(0.6)).frame(width: ShelfSection.itemWidth * 0.7, height: 12).blur(radius: 6).offset(y: 6)
                    art
                }
                .frame(width: ShelfSection.itemWidth, height: ShelfSection.stageHeight, alignment: .bottom)
                .overlay(alignment: .topTrailing) {
                    if holding.quantity > 1 {
                        Text("×\(Int(holding.quantity))").font(.geist(11, .semibold)).monospacedDigit()
                            .padding(.horizontal, 8).padding(.vertical, 2)
                            .background(Capsule().fill(Theme.background.opacity(0.8)))
                            .overlay(Capsule().strokeBorder(Theme.border))
                    }
                }

                // The price tag, hanging under the ledge.
                VStack(alignment: .leading, spacing: 4) {
                    HStack(alignment: .firstTextBaseline, spacing: 6) {
                        Text(String(format: "%02d", rank)).font(.mono(10, .medium)).foregroundStyle(Theme.subtle)
                        Text(holding.product?.name ?? "").font(.geist(13, .medium)).lineLimit(1).foregroundStyle(.white)
                    }
                    HStack(spacing: 8) {
                        Text(Format.money(holding.value)).font(.display(17)).monospacedDigit().foregroundStyle(.white)
                            .lineLimit(1).minimumScaleFactor(0.7)
                        Spacer(minLength: 0)
                        DeltaPill(ratio: holding.gainRatio, size: 12)
                    }
                }
                .padding(.horizontal, 12)
                .padding(.vertical, 10)
                .frame(width: ShelfSection.itemWidth, alignment: .leading)
                .background(RoundedRectangle(cornerRadius: 8).fill(Theme.background.opacity(0.6)))
                .overlay(RoundedRectangle(cornerRadius: 8).strokeBorder(Theme.border))
                .padding(.top, 26)
            }
        }
        .buttonStyle(.plain)
    }

    /// Cards stand at 82% of the stage; sealed and slabs fill it, all resting on the ledge.
    @ViewBuilder private var art: some View {
        if holding.identity.isGraded {
            HoldingArt(product: holding.product, identity: holding.identity, caption: false)
                .frame(width: ShelfSection.itemWidth, height: ShelfSection.stageHeight, alignment: .bottom)
        } else if isCard {
            ProductImage(product: holding.product, cornerRadius: 5)
                .frame(width: ShelfSection.itemWidth, height: ShelfSection.stageHeight * 0.82, alignment: .bottom)
                .shadow(color: .black.opacity(0.45), radius: 12, y: 8)
        } else {
            ProductImage(product: holding.product, cornerRadius: 10)
                .frame(width: ShelfSection.itemWidth, height: ShelfSection.stageHeight, alignment: .bottom)
        }
    }
}

// MARK: - Where your value sits

private struct ValueSplit: View {
    var store: CollectionStore

    var body: some View {
        let total = max(store.summary.value, 0.01)
        let groups = HoldingCategory.allCases.map { c in (c, store.holdings.filter { $0.category == c }) }.filter { !$0.1.isEmpty }
        VStack(alignment: .leading, spacing: 16) {
            PageHeader(title: "Where your value sits", subtitle: "Sealed, singles and slabs, side by side", size: 30)
            // The split: the same bar as Collection's, sized by share.
            AllocationBar(holdings: store.holdings, total: store.summary.value)
            ForEach(groups, id: \.0) { c, items in CategoryCard(category: c, items: items, total: total) }
        }
    }
}

private struct CategoryCard: View {
    var category: HoldingCategory
    var items: [HoldingView]
    var total: Double

    /// Each kind gets its own light, so the three cards read as different things.
    private var palette: GlowPalette {
        switch category {
        case .sealed: return .ocean
        case .singles: return .flame
        case .graded: return .citrus
        }
    }

    var body: some View {
        let value = items.reduce(0) { $0 + ($1.value ?? 0) }
        let cost = items.filter { $0.value != nil }.reduce(0) { $0 + $1.costBasis }
        let best = items.filter { $0.gainRatio != nil }.max { ($0.gainRatio ?? 0) < ($1.gainRatio ?? 0) }
        let count = items.reduce(0) { $0 + $1.quantity }
        let share = value / total
        GlowCard(palette: palette, radius: 28, padding: 18) {
            VStack(alignment: .leading, spacing: 0) {
                HStack(alignment: .top, spacing: 8) {
                    GlowLabel(text: category.rawValue, secondary: "\(items.count) products · \(Int(count)) items")
                    Spacer(minLength: 8)
                    GlowRing(fraction: share, label: "\(Int((share * 100).rounded()))%")
                        .frame(width: 72, height: 72)
                }
                Text(category.blurb).font(.geist(14)).opacity(0.8).padding(.top, 8)
                HStack(spacing: -24) {
                    ForEach(Array(items.prefix(3).enumerated()), id: \.element.id) { i, h in
                        HoldingArt(product: h.product, identity: h.identity, cornerRadius: 3, caption: false)
                            .frame(width: 70, height: 96)
                            .shadow(color: .black.opacity(0.3), radius: 6, y: 3)
                            .rotationEffect(.degrees(Double(i - 1) * 8))
                            .zIndex(i == 1 ? 1 : 0)
                    }
                }
                .frame(maxWidth: .infinity)
                .padding(.vertical, 20)
                GlowFigure(value: value, size: 48, cents: false)
                HStack(spacing: 8) {
                    GlowPill(text: Format.signedMoney(value - cost))
                    Text("on what you paid").font(.geist(13)).opacity(0.8)
                }
                .padding(.top, 8)
                if let best {
                    HStack(spacing: 6) {
                        Image(systemName: "chart.line.uptrend.xyaxis").font(.caption2)
                        Text("Best: \(best.product?.name ?? "")").lineLimit(1)
                        Text(Format.signedPercent(best.gainRatio)).fontWeight(.semibold)
                    }
                    .font(.geist(13)).opacity(0.85)
                    .padding(.top, 14)
                }
                Button {
                    Router.shared.collectionCategory = category
                    Router.shared.tabRequest = "collection"
                } label: {
                    HStack {
                        Text("View \(category.rawValue.lowercased())")
                        Spacer()
                        Image(systemName: "arrow.right")
                    }
                }
                .buttonStyle(HomeGlowButton(height: 44))
                .padding(.top, 18)
            }
        }
    }
}

// MARK: - Movers

private struct MoversSection: View {
    var holdings: [HoldingView]
    @State private var period = Period.day
    @State private var allUp = false
    @State private var allDown = false

    enum Period: String, CaseIterable { case day = "1D", week = "7D", month = "30D" }

    private func move(_ h: HoldingView) -> Double? {
        switch period {
        case .day: return h.change24hPct
        case .week: return h.change7dPct
        case .month: return h.change30dPct
        }
    }

    var body: some View {
        let moving = holdings.compactMap { h in move(h).map { (h, $0) } }.filter { $0.1 != 0 }
        let up = moving.filter { $0.1 > 0 }.sorted { $0.1 > $1.1 }
        let down = moving.filter { $0.1 < 0 }.sorted { $0.1 < $1.1 }
        VStack(alignment: .leading, spacing: 18) {
            HStack {
                PageHeader(title: "Movers", size: 30)
                Spacer()
                ChipPicker(options: Period.allCases.map { ($0, $0.rawValue) }, selection: $period).scaleEffect(0.86, anchor: .trailing)
            }
            group("Gainers", up, isUp: true, all: $allUp)
            group("Losers", down, isUp: false, all: $allDown)
        }
    }

    /// Rows stay on the dark surface so a long list reads easily; the light is only in the small
    /// chips (the count and each row's move).
    @ViewBuilder private func group(_ title: String, _ rows: [(HoldingView, Double)], isUp: Bool, all: Binding<Bool>) -> some View {
        if !rows.isEmpty {
            let chip: GlowPalette = isUp ? .homeChipUp : .down
            VStack(alignment: .leading, spacing: 12) {
                HStack(spacing: 10) {
                    Text(title.uppercased()).font(.mono(11)).tracking(1.4).foregroundStyle(Theme.muted)
                    HomeGlowChip(text: "\(rows.count)", palette: chip)
                }
                VStack(spacing: 0) {
                    ForEach(Array(rows.prefix(all.wrappedValue ? 20 : 3)), id: \.0.id) { h, pct in
                        NavigationLink(value: h.identity.productId) {
                            HStack(spacing: 12) {
                                HoldingArt(product: h.product, identity: h.identity, cornerRadius: 6, caption: false).frame(width: 36, height: 48)
                                VStack(alignment: .leading, spacing: 2) {
                                    Text(h.product?.name ?? "").font(.geist(15, .medium)).lineLimit(1).foregroundStyle(.white)
                                    Text([Format.money(h.price), h.quantity > 1 ? "×\(Int(h.quantity))" : nil, h.label].compactMap { $0 }.joined(separator: " · "))
                                        .font(.geist(13)).foregroundStyle(Theme.muted).monospacedDigit().lineLimit(1)
                                }
                                Spacer(minLength: 8)
                                VStack(alignment: .trailing, spacing: 4) {
                                    HomeGlowChip(text: Format.signedPercent(pct / 100), palette: chip)
                                    Text(Format.signedMoney((h.value ?? 0) - (h.value ?? 0) / (1 + pct / 100))).font(.geist(12)).foregroundStyle(Theme.muted)
                                }
                                .monospacedDigit()
                            }
                            .padding(.horizontal, 12)
                            .padding(.vertical, 10)
                            .contentShape(Rectangle())
                        }
                        .buttonStyle(.plain)
                    }
                }
                .surface(radius: 22, padding: 4)
                if rows.count > 3 {
                    Button(all.wrappedValue ? "Show fewer" : "Show all \(rows.count)") { withAnimation { all.wrappedValue.toggle() } }
                        .font(.geist(14, .medium)).foregroundStyle(Theme.muted)
                }
            }
        }
    }
}

// MARK: - Recently added

private struct RecentSection: View {
    var items: [CollectionStore.RecentPurchase]
    @Environment(\.accessibilityReduceMotion) private var reduceMotion
    @State private var shown = false
    @State private var pulse = false

    var body: some View {
        VStack(alignment: .leading, spacing: 18) {
            PageHeader(title: "Recently added", size: 30)
            VStack(alignment: .leading, spacing: 0) {
                ForEach(Array(items.enumerated()), id: \.element.id) { i, item in
                    let delay = Double(i) * 0.12
                    NavigationLink(value: item.entry.identity.productId) {
                        HStack(alignment: .top, spacing: 14) {
                            // The timeline: the line draws down entry by entry, each dot pops in as
                            // it's reached, and the newest keeps a soft lime pulse.
                            VStack(spacing: 0) {
                                ZStack {
                                    if i == 0 {
                                        Circle().stroke(Theme.lime.opacity(0.6), lineWidth: 1.5)
                                            .frame(width: 14, height: 14)
                                            .scaleEffect(pulse ? 2.2 : 1)
                                            .opacity(pulse ? 0 : 0.9)
                                    }
                                    Circle()
                                        .strokeBorder(i == 0 ? Theme.lime : Theme.subtle, lineWidth: 2)
                                        .background(Circle().fill(i == 0 ? Theme.lime.opacity(0.35) : Theme.background))
                                        .frame(width: 14, height: 14)
                                        .scaleEffect(shown ? 1 : 0.2)
                                        .animation(.spring(response: 0.4, dampingFraction: 0.55).delay(delay), value: shown)
                                }
                                .padding(.top, 22)
                                Rectangle().fill(i == 0 ? Theme.lime.opacity(0.5) : Theme.border).frame(width: i == 0 ? 1.5 : 1)
                                    .frame(maxHeight: .infinity)
                                    .scaleEffect(x: 1, y: shown ? 1 : 0, anchor: .top)
                                    .animation(.easeOut(duration: 0.35).delay(delay + 0.08), value: shown)
                            }
                            .frame(width: 14)
                            Group {
                                HoldingArt(product: item.product, identity: item.entry.identity, cornerRadius: 4, caption: false)
                                    .frame(width: 48, height: 64)
                                    .padding(.top, 10)
                                VStack(alignment: .leading, spacing: 3) {
                                    MonoLabel(text: Format.isoDay.date(from: item.entry.date)?.formatted(.dateTime.month(.abbreviated).day().year()) ?? item.entry.date)
                                    Text(item.product?.name ?? "").font(.geist(16, .medium)).lineLimit(1).foregroundStyle(.white)
                                    Text("\(Int(item.entry.quantity)) × \(Format.money(item.entry.unitPrice)) paid").font(.geist(13)).foregroundStyle(Theme.muted)
                                }
                                .padding(.top, 10)
                                Spacer(minLength: 4)
                                VStack(alignment: .trailing, spacing: 5) {
                                    Text(Format.money(item.value)).font(.geist(18)).tracking(-0.4).monospacedDigit().foregroundStyle(.white)
                                    if item.change != nil {
                                        HomeGlowChip(text: Format.signedPercent(item.change), palette: (item.change ?? 0) < 0 ? .down : .homeChipUp)
                                    }
                                }
                                .padding(.top, 12)
                            }
                            .opacity(shown ? 1 : 0)
                            .offset(x: shown ? 0 : 24)
                            .animation(.spring(response: 0.5, dampingFraction: 0.85).delay(delay + 0.04), value: shown)
                        }
                        .frame(minHeight: 92)
                    }
                    .buttonStyle(.plain)
                }
            }
            .onFirstVisible { shown = true }
            .onReplay {
                guard shown, !reduceMotion else { return }
                shown = false
                DispatchQueue.main.async { shown = true }
            }
            .onAppear {
                if reduceMotion { shown = true; return }
                withAnimation(.easeOut(duration: 1.6).repeatForever(autoreverses: false)) { pulse = true }
            }
        }
    }
}

// MARK: - Banners and milestones

struct HomeBanner: Equatable {
    var id = UUID()
    var title: String
    var detail: String?
    var isMilestone: Bool
}

/// A slim card that drops in from the top: lime with a glow for milestones, glass for updates.
private struct BannerView: View {
    var banner: HomeBanner
    @State private var glow = false

    var body: some View {
        HStack(spacing: 12) {
            Image(systemName: banner.isMilestone ? "sparkles" : "arrow.triangle.2.circlepath")
                .font(.system(size: 16, weight: .bold))
                .foregroundStyle(banner.isMilestone ? Theme.ink : Theme.lime)
            VStack(alignment: .leading, spacing: 2) {
                Text(banner.isMilestone ? banner.title.uppercased() : banner.title)
                    .font(banner.isMilestone ? .display(17) : .geist(14, .semibold))
                    .foregroundStyle(banner.isMilestone ? Theme.ink : .white)
                    .lineLimit(2)
                if let detail = banner.detail {
                    Text(detail).font(.geist(12)).foregroundStyle(banner.isMilestone ? Theme.ink.opacity(0.7) : Theme.muted).lineLimit(2)
                }
            }
            Spacer(minLength: 0)
        }
        .padding(.horizontal, 16)
        .padding(.vertical, 12)
        .background {
            if banner.isMilestone {
                RoundedRectangle(cornerRadius: 18, style: .continuous).fill(Theme.holo)
                    .shadow(color: Theme.holoGlow.opacity(glow ? 0.8 : 0.3), radius: glow ? 24 : 10)
            } else {
                Color.clear.liquidGlass(in: RoundedRectangle(cornerRadius: 18, style: .continuous))
            }
        }
        .onAppear {
            guard banner.isMilestone else { return }
            withAnimation(.easeOut(duration: 0.35)) { glow = true }
            withAnimation(.easeIn(duration: 0.8).delay(0.4)) { glow = false }
        }
    }
}

/// The website's milestones: value steps, item counts, and holdings that doubled or more.
enum Milestones {
    struct Milestone { var id: String; var title: String; var detail: String?; var rank: Int }

    private static let valueSteps: [Double] = [500, 1_000, 2_500, 5_000, 10_000, 25_000, 50_000, 100_000, 250_000, 500_000, 1_000_000]
    private static let itemSteps: [Double] = [10, 25, 50, 100, 250, 500, 1_000]
    private static let gainSteps: [(Double, String)] = [
        (1, "has doubled since you bought it"), (2, "has tripled since you bought it"),
        (4, "is up 5× since you bought it"), (9, "is up 10× since you bought it"),
    ]

    static func reached(summary: PortfolioSummary, holdings: [HoldingView]) -> [Milestone] {
        var out: [Milestone] = []
        for (i, step) in valueSteps.enumerated() where summary.value >= step {
            out.append(Milestone(id: "value:\(Int(step))", title: "Your collection just passed \(Format.money(step).replacingOccurrences(of: ".00", with: ""))",
                                 detail: "Now worth \(Format.money(summary.value)).", rank: 100 + i))
        }
        for (i, step) in itemSteps.enumerated() where summary.items >= step {
            out.append(Milestone(id: "items:\(Int(step))", title: "\(Int(step)) items in your collection", detail: nil, rank: 50 + i))
        }
        for h in holdings where !h.identity.isGraded {
            guard let r = h.gainRatio, let name = h.product?.name else { continue }
            for (i, step) in gainSteps.enumerated() where r >= step.0 {
                let short = name.replacingOccurrences(of: #"\s*\(.*?\)\s*"#, with: " ", options: .regularExpression).trimmingCharacters(in: .whitespaces)
                out.append(Milestone(id: "gain:\(h.identity.key):\(Int(step.0))", title: "\(short) \(step.1)",
                                     detail: "Paid \(Format.money(h.costBasis)) · worth \(Format.money(h.value))", rank: 80 + i))
            }
        }
        return out
    }
}

enum MorePage: String, Hashable, Identifiable {
    case analytics, gains, grading, activity
    case masterSets = "master-sets"
    var id: String { rawValue }
    static var opened = false
}

/// The website's other pages: analytics, the gains breakdown, grading and master sets. Each icon
/// sits on its own small square of light.
private struct MoreSection: View {
    var body: some View {
        VStack(alignment: .leading, spacing: 14) {
            Text("MORE").font(.mono(11)).tracking(1.4).foregroundStyle(Theme.muted)
            VStack(spacing: 0) {
                row(0, "Analytics", "Returns, drawdowns, sets and types", icon: "chart.xyaxis.line", page: .analytics)
                Rectangle().fill(Theme.border).frame(height: 1).padding(.leading, 60)
                row(1, "Gains", "Which products your gains come from", icon: "chart.bar.xaxis", page: .gains)
                Rectangle().fill(Theme.border).frame(height: 1).padding(.leading, 60)
                row(2, "Grading", "Your slabs, cards at the grader, what's worth sending", icon: "checkmark.seal", page: .grading)
                Rectangle().fill(Theme.border).frame(height: 1).padding(.leading, 60)
                row(3, "Master sets", "Every card in your sets, and how close you are", icon: "square.grid.3x3.fill", page: .masterSets)
                Rectangle().fill(Theme.border).frame(height: 1).padding(.leading, 60)
                row(4, "Activity", "Every purchase, sale and adjustment", icon: "list.bullet.rectangle", page: .activity)
            }
            .surface(radius: 22, padding: 4)
        }
    }

    private func row(_ i: Int, _ title: String, _ sub: String, icon: String, page: MorePage) -> some View {
        let shape = RoundedRectangle(cornerRadius: 12, style: .continuous)
        return NavigationLink(value: page) {
            HStack(spacing: 12) {
                Image(systemName: icon).font(.system(size: 16, weight: .semibold)).foregroundStyle(.white)
                    .frame(width: 40, height: 40)
                    .background { GlowFill(palette: .mixed(i)) }
                    .clipShape(shape)
                    .overlay(shape.strokeBorder(.white.opacity(0.08)))
                VStack(alignment: .leading, spacing: 2) {
                    Text(title).font(.geist(15, .semibold))
                    Text(sub).font(.geist(13)).foregroundStyle(Theme.muted).lineLimit(1)
                }
                Spacer(minLength: 8)
                Image(systemName: "chevron.right").font(.system(size: 12, weight: .semibold)).foregroundStyle(Theme.subtle)
            }
            .padding(12)
            .contentShape(Rectangle())
        }
        .buttonStyle(.plain)
    }
}

// MARK: - Lucent helpers (this file only)

private extension GlowPalette {
    /// A darker green-teal for small chips: the `.up` card's pale core would wash out white text
    /// at chip size.
    static let homeChipUp = GlowPalette(base: Color(hex: 0x0B3A2A), blobs: [
        Blob(color: Color(hex: 0x19D38A), x: 0.2, y: 0.3, size: 0.9),
        Blob(color: Color(hex: 0x2A7BFF), x: 0.95, y: 0.8, size: 0.7),
    ])

    /// Up or down, with the palette for each picked by the caller (so tiles about different
    /// things don't all glow the same teal).
    static func homeToned(_ value: Double?, up: GlowPalette, down: GlowPalette) -> GlowPalette {
        (value ?? 0) < 0 ? down : up
    }
}

/// A small capsule of light around a figure in a list ("+4.2%").
private struct HomeGlowChip: View {
    var text: String
    var palette: GlowPalette

    var body: some View {
        Text(text).font(.geist(13, .semibold)).monospacedDigit().lineLimit(1)
            .foregroundStyle(palette.ink)
            .padding(.horizontal, 10).padding(.vertical, 4)
            .background { GlowFill(palette: palette) }
            .clipShape(Capsule())
    }
}

/// The light of a glow card that only redraws when its palette changes.
private struct HomeStaticGlow: View, Equatable {
    var palette: GlowPalette
    var body: some View { GlowFill(palette: palette) }
}

/// A dark translucent capsule button for glow cards.
private struct HomeGlowButton: ButtonStyle {
    var height: CGFloat = 36

    func makeBody(configuration: Configuration) -> some View {
        configuration.label
            .font(.geist(14, .semibold))
            .lineLimit(1)
            .padding(.horizontal, 14)
            .frame(height: height)
            .background(.black.opacity(configuration.isPressed ? 0.4 : 0.28), in: Capsule())
            .scaleEffect(configuration.isPressed ? 0.97 : 1)
            .animation(.easeOut(duration: 0.15), value: configuration.isPressed)
    }
}
