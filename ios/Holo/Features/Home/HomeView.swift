import Charts
import SwiftUI

/// Overview, like the website's: the hero worth, performance, key numbers, the star of the
/// collection, your shelf, where your value sits, movers and what you added recently.
struct HomeView: View {
    var onScan: () -> Void
    @Environment(CollectionStore.self) private var store
    @Environment(SessionModel.self) private var session
    @State private var account = false
    @State private var lists = false
    @State private var search = false
    @State private var recap = false
    @State private var adding = false
    @State private var addSearch = false
    /// A moment worth a banner: a milestone reached, or prices just updated.
    @State private var banner: HomeBanner?
    @State private var bannerTick = 0

    var body: some View {
        NavigationStack {
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
                MarketPulse(store: store)
                // Opens search with the keyboard already up.
                SearchFieldButton(prompt: "Search any card or sealed product") { search = true }
                    .padding(.horizontal, 16)
                Hero(store: store, onRecap: { recap = true }, onAdd: { adding = true })
            }
            PerformanceSection(store: store).padding(.horizontal, 16).reveal()
            MetricGrid(store: store, onReload: refresh).padding(.horizontal, 16).reveal()
            Spotlight(store: store).padding(.horizontal, 16).reveal()
            ShelfSection(holdings: store.holdings).reveal()
            ValueSplit(store: store).padding(.horizontal, 16).reveal()
            MoversSection(holdings: store.holdings).padding(.horizontal, 16).reveal()
            RecentSection(items: store.recentPurchases()).padding(.horizontal, 16).reveal()
        }
        .padding(.top, 4)
        .padding(.bottom, 40)
    }

    private var empty: some View {
        VStack(spacing: 16) {
            Image(systemName: "rectangle.stack.badge.plus").font(.system(size: 44)).foregroundStyle(Theme.lime)
            Text("START YOUR COLLECTION").font(.display(30))
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
            Text("Holo").font(.geist(19, .semibold))
        }
    }
}

// MARK: - Hero

/// Your most valuable pieces fanned out over a glowing grid, then the worth in giant lime Anton.
private struct Hero: View {
    var store: CollectionStore
    var onRecap: () -> Void
    var onAdd: () -> Void

    var body: some View {
        let s = store.summary
        let top = Array(store.holdings.filter { ($0.value ?? 0) > 0 }.prefix(5))
        VStack(spacing: 10) {
            CardFan(holdings: top).frame(height: 236)
            MonoLabel(text: "\(store.holdings.count) products · \(Int(s.items)) items")
            VStack(spacing: 6) {
                Text("YOUR COLLECTION'S WORTH").font(.display(30)).displayTrim(30)
                CountingText(value: s.value, format: { Format.money($0) })
                    .font(.display(66))
                    .monospacedDigit()
                    .foregroundStyle(Theme.lime)
                    .minimumScaleFactor(0.5)
                    .lineLimit(1)
                    .displayTrim(66)
                    .shadow(color: Theme.lime.opacity(0.45), radius: 24)
                    .padding(.horizontal, 16)
            }
            .padding(.vertical, 8)
            FlowPills(pills: [
                ("Today", Format.signedMoney(s.dayChange), Theme.tone(s.dayChange), Format.signedPercent(s.dayRatio)),
                ("All time", Format.signedMoney(s.gain), Theme.tone(s.gain), nil),
                ("Invested", Format.money(s.totalCost), Color.white, nil),
            ])
            .padding(.horizontal, 16)
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
            .padding(.horizontal, 16)
            .padding(.top, 18)
        }
        .padding(.vertical, 12)
        .background(HeroBackdrop())
    }
}

/// The dark grid with lime and pink glows behind the hero.
private struct HeroBackdrop: View {
    var body: some View {
        ZStack {
            GridPattern()
            RadialGradient(colors: [Theme.lime.opacity(0.22), .clear], center: UnitPoint(x: 0.3, y: 0.55), startRadius: 0, endRadius: 260)
            RadialGradient(colors: [Theme.planPink.opacity(0.16), .clear], center: UnitPoint(x: 0.85, y: 0.3), startRadius: 0, endRadius: 220)
        }
        .mask(LinearGradient(colors: [.clear, .black, .black, .clear], startPoint: .top, endPoint: .bottom))
    }
}

/// Up to five pieces fanned like a hand of cards, the most valuable in front, each bobbing
/// gently out of step with the others, like the website's hero.
private struct CardFan: View {
    var holdings: [HoldingView]

    @Environment(\.accessibilityReduceMotion) private var reduceMotion
    @State private var onScreen = true

    var body: some View {
        // One clock drives every piece's bob, computed fresh each frame, so a picture that
        // finishes loading mid-animation moves with its frame instead of lagging behind it
        // (a looping withAnimation only animates what existed when it started).
        TimelineView(.animation(minimumInterval: 1 / 30, paused: reduceMotion || !onScreen)) { context in
            let t = context.date.timeIntervalSinceReferenceDate
            fan(t: reduceMotion ? 0 : t)
        }
        // The clock stops while the fan is scrolled away or another tab is showing.
        .onVisibilityChange { onScreen = $0 }
    }

    private func fan(t: Double) -> some View {
        ZStack(alignment: .top) {
            ForEach(Array(holdings.prefix(5).enumerated()).reversed(), id: \.element.id) { pair in
                FanPiece(holding: pair.element, index: pair.offset, time: t)
                    .zIndex(Double(10 - pair.offset))
            }
        }
        .frame(maxWidth: .infinity, alignment: .top)
    }
}

/// One piece of the hero fan at its slot, bobbing with the shared clock.
private struct FanPiece: View {
    var holding: HoldingView
    var index: Int
    var time: Double

    /// The website's fan: sideways step (in card widths), tilt, drop, and scale per position.
    private static let steps: [CGFloat] = [0, -1, 1, -2, 2]
    private static let tilts: [Double] = [0, -9, 9, -17, 17]
    private static let drops: [CGFloat] = [0, 18, 18, 46, 46]
    private static let scales: [CGFloat] = [1, 0.86, 0.86, 0.74, 0.74]
    private static let width: CGFloat = 126
    private static let height: CGFloat = 176

    /// Up 9pt and back every 5.5s, each piece 1.1s out of step.
    private var bob: CGFloat {
        guard time != 0 else { return 0 }
        let phase: Double = (time + Double(index) * 1.1) / 5.5 * 2 * Double.pi
        return CGFloat(-4.5 * (1 - cos(phase)))
    }

    private var isCard: Bool { holding.product?.isSealed == false && holding.product?.imageURL != nil && !holding.identity.isGraded }

    private var art: some View {
        HoldingArt(product: holding.product, identity: holding.identity, cornerRadius: 6, caption: index == 0)
            .frame(width: Self.width, height: Self.height)
            .shadow(color: .black.opacity(0.55), radius: 13, y: 18)
    }

    var body: some View {
        let anchor = UnitPoint(x: 0.5, y: 0.9)
        let x: CGFloat = Self.steps[index] * Self.width * 0.26
        let y: CGFloat = Self.drops[index] + bob
        NavigationLink(value: holding.identity.productId) {
            if index == 0 {
                art.tiltCard(12, foil: isCard, cornerRadius: 6)
            } else {
                art
            }
        }
        .buttonStyle(.plain)
        .scaleEffect(Self.scales[index], anchor: anchor)
        .rotationEffect(.degrees(Self.tilts[index]), anchor: anchor)
        .offset(x: x, y: y)
    }
}

/// Stat pills that wrap onto a second line when they don't fit.
private struct FlowPills: View {
    var pills: [(String, String, Color, String?)]

    var body: some View {
        ViewThatFits {
            HStack(spacing: 8) { ForEach(pills.indices, id: \.self) { pill(pills[$0]) } }
            VStack(spacing: 8) {
                HStack(spacing: 8) { ForEach(pills.indices.prefix(2), id: \.self) { pill(pills[$0]) } }
                HStack(spacing: 8) { ForEach(pills.indices.dropFirst(2), id: \.self) { pill(pills[$0]) } }
            }
        }
    }

    private func pill(_ p: (String, String, Color, String?)) -> some View {
        StatPill(label: p.0, value: p.1, tint: p.2, extra: p.3)
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
        let last = shown?.value ?? points.last?.value ?? 0
        let change = last - first
        VStack(alignment: .leading, spacing: 12) {
            PageHeader(title: "Performance", size: 30)
            Text(shown.map { "\($0.day.formatted(date: .abbreviated, time: .omitted)) · \(Format.money($0.value))" } ?? "Drag across the chart to see any day")
                .font(.geist(15)).foregroundStyle(Theme.muted)
            HStack(spacing: 6) {
                Text(Format.signedMoney(change)).foregroundStyle(Theme.tone(change))
                if first > 0 { Text("(\(Format.signedPercent(change / first)))").foregroundStyle(Theme.tone(change)) }
                Text(range.phrase).foregroundStyle(Theme.muted)
            }
            .font(.geist(16, .medium)).monospacedDigit()
            ChipPicker(options: Range.allCases.map { ($0, $0.rawValue) }, selection: $range)
            if points.count > 1 {
                let domain = ChartTicks.domain(points.map(\.value))
                Chart {
                    ForEach(points) { p in
                        AreaMark(x: .value("Day", p.day), yStart: .value("Floor", domain.lowerBound), yEnd: .value("Value", p.value))
                            .foregroundStyle(LinearGradient(colors: [Theme.lime.opacity(0.25), Theme.lime.opacity(0)], startPoint: .top, endPoint: .bottom))
                            .interpolationMethod(.monotone)
                        LineMark(x: .value("Day", p.day), y: .value("Value", p.value), series: .value("Line", "Value"))
                            .foregroundStyle(Theme.lime)
                            .lineStyle(StrokeStyle(lineWidth: 2.5))
                            .interpolationMethod(.monotone)
                    }
                    if let shown {
                        RuleMark(x: .value("Day", shown.day)).foregroundStyle(.white.opacity(0.3))
                        PointMark(x: .value("Day", shown.day), y: .value("Value", shown.value)).foregroundStyle(Theme.lime).symbolSize(70)
                    }
                }
                .chartXAxis(.hidden)
                .insideYAxis()
                .chartYScale(domain: domain)
                .chartXSelection(value: $scrubbed)
                .frame(height: 230)
                .drawIn(replay: range)
                // A light tick for each day you scrub across; a firmer one on the range's high and low.
                .sensoryFeedback(trigger: shown?.date) { _, new in
                    guard let new, let point = points.first(where: { $0.date == new }) else { return nil }
                    let values = points.map(\.value)
                    if point.value == values.max() || point.value == values.min() { return .impact(weight: .medium, intensity: 0.9) }
                    return .selection
                }
                if let end = points.last {
                    Text("Daily closing values · \(Format.money(end.value)) on \(end.day.formatted(date: .abbreviated, time: .omitted))")
                        .font(.geist(12)).foregroundStyle(Theme.muted)
                        .frame(maxWidth: .infinity, alignment: .trailing)
                }
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
        VStack(spacing: 12) {
            HStack(spacing: 12) {
                MetricCard(label: "Invested", amount: s.totalCost, format: { Format.money($0) }, valueTint: .white, sub: "incl. fees & shipping", tint: Theme.azure)
                NavigationLink {
                    GainsView()
                } label: {
                    MetricCard(label: "Unrealized", amount: s.gain, format: { Format.signedMoney($0) }, valueTint: Theme.tone(s.gain), sub: "breakdown →",
                               tint: s.gain >= 0 ? Theme.lime : Theme.planPink,
                               tag: s.gainRatio.map { (pct($0, decimals: 0), s.gain >= 0 ? Theme.lime : Theme.planPink, s.gain >= 0 ? Theme.ink : .white) })
                }
                .buttonStyle(.plain)
            }
            HStack(spacing: 12) {
                MetricCard(label: "Today", amount: s.dayChange, format: { Format.signedMoney($0) }, valueTint: Theme.tone(s.dayChange), sub: nil,
                           tint: s.dayChange >= 0 ? Theme.lime : Theme.planPink,
                           tag: s.dayRatio.map { (pct($0, decimals: 2), s.dayChange >= 0 ? Theme.lime : Theme.planPink, s.dayChange >= 0 ? Theme.ink : .white) })
                Button {
                    Router.shared.tabRequest = "collection"
                } label: {
                    MetricCard(label: "Collection", amount: s.items, format: { "\(Int($0.rounded())) items" }, valueTint: .white, sub: "\(store.holdings.count) products",
                               tint: Theme.planBlue, tag: ("\(store.holdings.count) SKUs", Theme.planBlue, .white))
                }
                .buttonStyle(.plain)
            }
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

/// The website's metric card: an Anton label with its slanted tag on the right, the figure in
/// Anton, a note under it, on the dark surface with a faint colored top edge.
private struct MetricCard: View {
    var label: String
    /// The figure, counted up when the card appears.
    var amount: Double
    var format: (Double) -> String
    var valueTint: Color
    var sub: String?
    var tint: Color
    var tag: (String, Color, Color)?

    var body: some View {
        let shape = RoundedRectangle(cornerRadius: 22, style: .continuous)
        VStack(alignment: .leading, spacing: 0) {
            HStack(alignment: .center, spacing: 8) {
                Text(label.uppercased()).font(.display(15)).tracking(0.3).foregroundStyle(.white.opacity(0.85))
                    .lineLimit(1).minimumScaleFactor(0.8).displayTrim(15)
                Spacer(minLength: 4)
                if let tag { SkewTag(text: tag.0, color: tag.1, textColor: tag.2) }
            }
            CountingText(value: amount, format: format).font(.display(28)).monospacedDigit().foregroundStyle(valueTint)
                .lineLimit(1).minimumScaleFactor(0.6).displayTrim(28)
                .flashOnAppear(valueTint == .white ? .clear : valueTint)
                .padding(.top, 16)
            if let sub {
                Text(sub).font(.geist(12)).foregroundStyle(Theme.muted).lineLimit(1).padding(.top, 8)
            }
        }
        .padding(.horizontal, 20)
        .padding(.vertical, 16)
        .frame(maxWidth: .infinity, minHeight: 104, alignment: .topLeading)
        .background(
            ZStack {
                shape.fill(Theme.surface)
                shape.fill(LinearGradient(colors: [.white.opacity(0.035), .clear], startPoint: .top, endPoint: UnitPoint(x: 0.5, y: 0.45)))
            }
        )
        .overlay(shape.strokeBorder(LinearGradient(colors: [tint.opacity(0.35), .clear], startPoint: .top, endPoint: UnitPoint(x: 0.5, y: 0.2)), lineWidth: 1))
        .contentShape(shape)
    }
}

/// Spent this month against an optional monthly budget, with a bar, like the website.
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
        let tone = over ? Theme.down : near ? Color(hex: 0xF5B544) : Color.white
        VStack(alignment: .leading, spacing: 12) {
            HStack(spacing: 12) {
                Image(systemName: "wallet.bifold").font(.system(size: 15)).foregroundStyle(Theme.muted)
                    .frame(width: 36, height: 36).background(RoundedRectangle(cornerRadius: 12).fill(Theme.surface2))
                VStack(alignment: .leading, spacing: 2) {
                    Text("Spent in \(Date().formatted(.dateTime.month(.wide)))").font(.geist(12, .medium)).foregroundStyle(Theme.muted)
                    HStack(spacing: 4) {
                        Text(Format.money(spent)).font(.geist(15, .semibold))
                        if let budget { Text("of \(Format.money(budget))").font(.geist(15)).foregroundStyle(Theme.muted) }
                    }
                    .monospacedDigit().lineLimit(1).minimumScaleFactor(0.8)
                }
                Spacer(minLength: 8)
                // Edit sits in the card's top-right corner.
                Button {
                    draft = budget.map { String(format: "%.0f", $0) } ?? ""
                    editing = true
                } label: {
                    if budget != nil { Label("Edit", systemImage: "pencil") } else { Text("Set budget") }
                }
                .buttonStyle(Button3D(kind: .dark, fullWidth: false, height: 34))
            }
            if let remaining {
                (Text(Format.money(abs(remaining))).fontWeight(.medium).foregroundStyle(tone)
                    + Text(over ? " over budget" : " left").foregroundStyle(Theme.muted))
                    .font(.geist(13)).monospacedDigit()
            }
            if let used {
                GeometryReader { geo in
                    Capsule().fill(Theme.surface2)
                        .overlay(alignment: .leading) {
                            Capsule().fill(tone).frame(width: geo.size.width * min(1, used))
                        }
                }
                .frame(height: 6)
                let projected = projection(spent)
                if !over, spent > 0, let budget, projected > budget {
                    Text("At this pace you'll spend about \(Format.money(projected)) this month.").font(.geist(12)).foregroundStyle(Theme.subtle)
                }
            }
            if let error { Text(error).font(.geist(12)).foregroundStyle(Theme.down) }
        }
        .padding(.horizontal, 20)
        .padding(.vertical, 16)
        .frame(maxWidth: .infinity, alignment: .leading)
        .surface(radius: 22, padding: nil)
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

/// The star (biggest gain) in a neon frame, the biggest move today, and the one most below what you paid.
private struct Spotlight: View {
    var store: CollectionStore

    var body: some View {
        let holdings = store.holdings
        let star = holdings.filter { ($0.gain ?? 0) > 0 }.max { ($0.gain ?? 0) < ($1.gain ?? 0) }
        let mover = holdings.filter { ($0.dayChange ?? 0) != 0 && $0.id != star?.id }.max { abs($0.dayChange ?? 0) < abs($1.dayChange ?? 0) }
        let laggard = holdings.filter { ($0.gainRatio ?? 0) < 0 }.min { ($0.gainRatio ?? 0) < ($1.gainRatio ?? 0) }
        VStack(spacing: 14) {
            if let star { StarCard(holding: star, series: store.series(star.identity)) }
            if let mover {
                // The card takes the move's color: lime up, pink down, never red on lime.
                MiniTile(holding: mover, tag: "Biggest move today", icon: "flame.fill", color: (mover.dayChange ?? 0) < 0 ? Theme.planPink : Theme.lime, value: mover.dayChange,
                         line: Text(Format.signedPercent((mover.change24hPct ?? 0) / 100)).foregroundStyle(Theme.tone(mover.dayChange)) + Text(" today").foregroundStyle(Theme.muted),
                         series: store.series(mover.identity, days: 30))
            }
            if let laggard {
                MiniTile(holding: laggard, tag: "Below what you paid", icon: "arrow.down.right", color: Theme.planPink, value: laggard.gain,
                         line: Text(Format.signedPercent(laggard.gainRatio)).foregroundStyle(Theme.down) + Text(" vs what you paid").foregroundStyle(Theme.muted),
                         series: store.series(laggard.identity, days: 30), baseline: laggard.avgCost)
            }
        }
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
            VStack(alignment: .leading, spacing: 0) {
                // The website's stage: the piece centered, a soft floor shadow, a floating % chip.
                HoldingArt(product: holding.product, identity: holding.identity, cornerRadius: 12)
                    .frame(width: artSize.width, height: artSize.height)
                    .tiltCard(14, foil: holding.product?.isSealed == false && !holding.identity.isGraded, cornerRadius: 12)
                    .background(alignment: .bottom) {
                        Ellipse().fill(.black.opacity(0.6)).frame(width: artSize.width * 0.76, height: 30).blur(radius: 14).offset(y: 16)
                    }
                    .overlay(alignment: .topTrailing) {
                        if let r = holding.gainRatio {
                            Text(Format.signedPercent(r).replacingOccurrences(of: #"\.\d+%"#, with: "%", options: .regularExpression))
                                .font(.display(15)).foregroundStyle(Theme.ink)
                                .padding(.horizontal, 12).padding(.vertical, 6)
                                .background(Capsule().fill(Theme.lime))
                                .shadow(color: Theme.lime.opacity(0.6), radius: 12, y: 6)
                                .offset(x: 16, y: artSize.height * 0.08)
                        }
                    }
                    .frame(maxWidth: .infinity)
                SkewTag(text: "Star of the collection", icon: "sparkles").padding(.top, 28)
                DisplayText(text: (holding.product?.name ?? "").uppercased(), size: 30)
                    .frame(maxWidth: .infinity, alignment: .leading)
                    .padding(.top, 16)
                Text([holding.product?.setName, holding.label].compactMap { $0 }.joined(separator: " · "))
                    .font(.geist(13)).foregroundStyle(Theme.muted).lineLimit(1)
                    .padding(.top, 8)
                CountingText(value: holding.gain ?? 0, format: { Format.signedMoney($0) }).font(.display(40)).monospacedDigit().foregroundStyle(Theme.lime)
                    .displayTrim(40)
                    .padding(.top, 24)
                HStack(spacing: 8) {
                    stat("Paid", Format.money(holding.costBasis), .white)
                    stat("Worth", Format.money(holding.value), .white)
                    stat("Return", Format.signedPercent(holding.gainRatio), Theme.tone(holding.gainRatio))
                }
                .padding(.top, 24)
                if series.count > 1 {
                    Sparkline(points: series, color: Theme.lime).frame(height: 52).padding(.top, 24)
                    Text("LAST 90 DAYS").font(.mono(10)).tracking(0.6).foregroundStyle(Theme.subtle).padding(.top, 4)
                }
            }
            .padding(20)
            .background(
                ZStack {
                    RoundedRectangle(cornerRadius: 24, style: .continuous).fill(Color(hex: 0x050505))
                    GridPattern(step: 28, opacity: 0.06)
                        .mask(RadialGradient(colors: [.black, .black.opacity(0.25)], center: .top, startRadius: 0, endRadius: 520))
                    RadialGradient(colors: [Theme.lime.opacity(0.16), .clear], center: UnitPoint(x: 0.5, y: 0.25), startRadius: 0, endRadius: 320)
                }
                .clipShape(RoundedRectangle(cornerRadius: 24, style: .continuous))
            )
            .overlay(ElectricBorder(radius: 24))
            .shadow(color: Theme.lime.opacity(0.25), radius: 22)
        }
        .buttonStyle(.plain)
    }

    private func stat(_ label: String, _ value: String, _ tint: Color) -> some View {
        VStack(alignment: .leading, spacing: 4) {
            Text(label.uppercased()).font(.mono(10, .medium)).tracking(0.6).foregroundStyle(Theme.subtle)
            Text(value).font(.geist(14, .semibold)).monospacedDigit().foregroundStyle(tint).lineLimit(1).minimumScaleFactor(0.7)
        }
        .padding(.horizontal, 12)
        .padding(.vertical, 10)
        .frame(maxWidth: .infinity, alignment: .leading)
        .background(RoundedRectangle(cornerRadius: 12).fill(Theme.background.opacity(0.4)))
        .overlay(RoundedRectangle(cornerRadius: 12).strokeBorder(.white.opacity(0.06)))
    }
}

private struct MiniTile: View {
    var holding: HoldingView
    var tag: String
    var icon: String
    var color: Color
    var value: Double?
    var line: Text
    var series: [TimelinePoint]
    var baseline: Double?

    var body: some View {
        NavigationLink(value: holding.identity.productId) {
            VStack(alignment: .leading, spacing: 14) {
                SkewTag(text: tag, color: color, textColor: color == Theme.lime ? Theme.ink : .white, icon: icon)
                HStack(spacing: 14) {
                    HoldingArt(product: holding.product, identity: holding.identity, cornerRadius: 8, caption: false)
                        .frame(width: 64, height: 80)
                    VStack(alignment: .leading, spacing: 4) {
                        Text(holding.product?.name ?? "").font(.geist(16, .medium)).lineLimit(1).foregroundStyle(.white)
                        Text(Format.signedMoney(value)).font(.display(28)).monospacedDigit().foregroundStyle(Theme.tone(value))
                        line.font(.geist(13, .medium)).monospacedDigit()
                    }
                    Spacer(minLength: 0)
                }
                if series.count > 1 {
                    Sparkline(points: series, color: color == Theme.lime ? Theme.lime : Theme.down, baseline: baseline).frame(height: 34)
                }
            }
            .tinted(color)
        }
        .buttonStyle(.plain)
    }
}

/// A tiny price line, optionally with a dashed line at what you paid.
struct Sparkline: View {
    var points: [TimelinePoint]
    var color: Color
    var baseline: Double?

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
        .drawIn(duration: 1.0)
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

    var body: some View {
        let value = items.reduce(0) { $0 + ($1.value ?? 0) }
        let cost = items.filter { $0.value != nil }.reduce(0) { $0 + $1.costBasis }
        let best = items.filter { $0.gainRatio != nil }.max { ($0.gainRatio ?? 0) < ($1.gainRatio ?? 0) }
        let count = items.reduce(0) { $0 + $1.quantity }
        VStack(alignment: .leading, spacing: 12) {
            HStack(spacing: 10) {
                Text(category.rawValue.uppercased()).font(.display(34)).displayTrim(34)
                SkewTag(text: "\(Int((value / total * 100).rounded()))% of value", color: category.color, textColor: category == .graded ? Theme.ink : .white)
            }
            Text(category.blurb).font(.geist(14)).foregroundStyle(Theme.muted)
            VStack(alignment: .leading, spacing: 10) {
                HStack(spacing: -24) {
                    ForEach(Array(items.prefix(3).enumerated()), id: \.element.id) { i, h in
                        HoldingArt(product: h.product, identity: h.identity, cornerRadius: 3, caption: false)
                            .frame(width: 70, height: 96)
                            .rotationEffect(.degrees(Double(i - 1) * 8))
                            .zIndex(i == 1 ? 1 : 0)
                    }
                }
                .frame(maxWidth: .infinity)
                .padding(.vertical, 8)
                Label("\(items.count) products, \(Int(count)) items", systemImage: "equal").font(.geist(13)).foregroundStyle(Theme.muted)
                if let best {
                    HStack(spacing: 6) {
                        Image(systemName: "chart.line.uptrend.xyaxis").font(.caption2)
                        Text("Best: \(best.product?.name ?? "")").lineLimit(1)
                        Text(Format.signedPercent(best.gainRatio)).foregroundStyle(Theme.tone(best.gainRatio)).fontWeight(.semibold)
                    }
                    .font(.geist(13)).foregroundStyle(Theme.muted)
                }
            }
            .padding(14)
            .background(RoundedRectangle(cornerRadius: 16).fill(Theme.background.opacity(0.55)))
            Text(Format.money(value)).font(.display(44)).monospacedDigit()
            Button {
                Router.shared.collectionCategory = category
                Router.shared.tabRequest = "collection"
            } label: { HStack { Text("View \(category.rawValue.lowercased())"); Image(systemName: "arrow.right") } }
                .buttonStyle(Button3D(kind: category.button))
            HStack(spacing: 4) {
                Text(Format.signedMoney(value - cost)).foregroundStyle(Theme.tone(value - cost)).fontWeight(.semibold)
                Text("on what you paid").foregroundStyle(Theme.muted)
            }
            .font(.geist(14)).monospacedDigit()
            .frame(maxWidth: .infinity)
        }
        .tinted(category.color)
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
            group("Gainers", up, tag: Theme.lime, all: $allUp)
            group("Losers", down, tag: Theme.planPink, all: $allDown)
        }
    }

    @ViewBuilder private func group(_ title: String, _ rows: [(HoldingView, Double)], tag: Color, all: Binding<Bool>) -> some View {
        if !rows.isEmpty {
            VStack(alignment: .leading, spacing: 12) {
                HStack(spacing: 10) {
                    CardLabel(text: title, color: tag)
                    SkewTag(text: "\(rows.count)", color: tag, textColor: tag == Theme.lime ? Theme.ink : .white)
                }
                ForEach(Array(rows.prefix(all.wrappedValue ? 20 : 3)), id: \.0.id) { h, pct in
                    NavigationLink(value: h.identity.productId) {
                        HStack(spacing: 12) {
                            HoldingArt(product: h.product, identity: h.identity, cornerRadius: 6, caption: false).frame(width: 36, height: 48)
                            VStack(alignment: .leading, spacing: 2) {
                                Text(h.product?.name ?? "").font(.geist(15, .medium)).lineLimit(1).foregroundStyle(.white)
                                Text([Format.money(h.price), h.quantity > 1 ? "×\(Int(h.quantity))" : nil, h.label].compactMap { $0 }.joined(separator: " · "))
                                    .font(.geist(13)).foregroundStyle(Theme.muted).monospacedDigit()
                            }
                            Spacer()
                            VStack(alignment: .trailing, spacing: 2) {
                                Text(Format.signedPercent(pct / 100)).font(.geist(15, .semibold)).foregroundStyle(Theme.tone(pct))
                                Text(Format.signedMoney((h.value ?? 0) - (h.value ?? 0) / (1 + pct / 100))).font(.geist(13)).foregroundStyle(Theme.muted)
                            }
                            .monospacedDigit()
                        }
                    }
                    .buttonStyle(.plain)
                }
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
                                VStack(alignment: .trailing, spacing: 3) {
                                    Text(Format.money(item.value)).font(.display(19)).monospacedDigit().foregroundStyle(.white)
                                    Text(Format.signedPercent(item.change)).font(.geist(13, .medium)).monospacedDigit().foregroundStyle(Theme.tone(item.change))
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
                RoundedRectangle(cornerRadius: 18, style: .continuous).fill(Theme.lime)
                    .shadow(color: Theme.lime.opacity(glow ? 0.8 : 0.3), radius: glow ? 24 : 10)
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
