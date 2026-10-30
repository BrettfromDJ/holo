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
            .tabBarClearance()
            .refreshable { await reload() }
            .toolbar {
                ToolbarItem(placement: .topBarLeading) { BrandMark() }
                ToolbarItemGroup(placement: .topBarTrailing) {
                    Button { lists = true } label: { Image(systemName: "heart") }.accessibilityLabel("Watchlist and wishlist")
                    Button { account = true } label: { Image(systemName: "gearshape") }.accessibilityLabel("Account")
                }
            }
            .toolbarBackground(Theme.background, for: .navigationBar)
            .navigationBarTitleDisplayMode(.inline)
            .navigationDestination(for: String.self) { ProductDetailView(productId: $0) }
            .sheet(isPresented: $account) { SettingsView() }
            .sheet(isPresented: $lists) { ListsView() }
            .sheet(isPresented: $search) { ExploreView() }
        }
    }

    private var content: some View {
        VStack(alignment: .leading, spacing: 44) {
            VStack(spacing: 18) {
                Button { search = true } label: {
                    HStack(spacing: 10) {
                        Image(systemName: "magnifyingglass").font(.system(size: 18)).foregroundStyle(Theme.muted)
                        Text("Search any card or sealed product").font(.geist(16)).foregroundStyle(Theme.subtle)
                        Spacer()
                    }
                    .padding(.horizontal, 18)
                    .frame(height: 56)
                    .background(RoundedRectangle(cornerRadius: 16, style: .continuous).fill(Theme.surface))
                    .overlay(RoundedRectangle(cornerRadius: 16, style: .continuous).strokeBorder(Theme.border))
                }
                .buttonStyle(.plain)
                .padding(.horizontal, 16)
                Hero(store: store)
            }
            PerformanceSection(store: store).padding(.horizontal, 16)
            MetricGrid(store: store).padding(.horizontal, 16)
            Spotlight(store: store).padding(.horizontal, 16)
            ShelfSection(holdings: Array(store.holdings.prefix(10)))
            ValueSplit(store: store).padding(.horizontal, 16)
            MoversSection(holdings: store.holdings).padding(.horizontal, 16)
            RecentSection(items: store.recentPurchases()).padding(.horizontal, 16)
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
        if case let .signedIn(userId, _) = session.state { await store.load(userId: userId) }
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

    var body: some View {
        let s = store.summary
        let top = Array(store.holdings.filter { ($0.value ?? 0) > 0 }.prefix(5))
        VStack(spacing: 10) {
            CardFan(holdings: top).frame(height: 230)
            MonoLabel(text: "\(store.holdings.count) products · \(Int(s.items)) items")
            VStack(spacing: 6) {
                Text("YOUR COLLECTION'S WORTH").font(.display(30)).displayTrim(30)
                Text(Format.money(s.value))
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

/// Up to five pieces fanned like a hand of cards, the most valuable in front.
private struct CardFan: View {
    var holdings: [HoldingView]

    var body: some View {
        GeometryReader { geo in
            let w = min(132, geo.size.width / 3)
            ZStack {
                ForEach(Array(holdings.enumerated().reversed()), id: \.element.id) { i, h in
                    let side: CGFloat = i == 0 ? 0 : (i % 2 == 1 ? -1 : 1)
                    let step = CGFloat((i + 1) / 2)
                    NavigationLink(value: h.identity.productId) {
                        HoldingArt(product: h.product, identity: h.identity, cornerRadius: 10, caption: i == 0)
                            .frame(width: w, height: w * 88 / 63 + (h.identity.isGraded ? 34 : 0))
                            .shadow(color: .black.opacity(0.6), radius: 14, y: 10)
                    }
                    .buttonStyle(.plain)
                    .rotationEffect(.degrees(Double(side * step * 9)))
                    .offset(x: side * step * w * 0.62, y: step * 14)
                    .scaleEffect(i == 0 ? 1.06 : 1 - step * 0.06)
                    .zIndex(Double(10 - i))
                }
            }
            .frame(maxWidth: .infinity, maxHeight: .infinity)
        }
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
    @State private var showCost = false

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
            HStack {
                Button { showCost.toggle() } label: {
                    HStack(spacing: 6) {
                        Image(systemName: showCost ? "checkmark.square.fill" : "square").foregroundStyle(showCost ? Theme.lime : Theme.muted)
                        Text("Cost basis").foregroundStyle(Theme.muted)
                    }
                    .font(.geist(13, .medium))
                }
                .buttonStyle(.plain)
                Spacer()
                ChipPicker(options: Range.allCases.map { ($0, $0.rawValue) }, selection: $range)
                    .scaleEffect(0.86, anchor: .trailing)
            }
            if points.count > 1 {
                Chart {
                    ForEach(points) { p in
                        AreaMark(x: .value("Day", p.day), y: .value("Value", p.value))
                            .foregroundStyle(LinearGradient(colors: [Theme.lime.opacity(0.25), Theme.lime.opacity(0)], startPoint: .top, endPoint: .bottom))
                            .interpolationMethod(.monotone)
                        LineMark(x: .value("Day", p.day), y: .value("Value", p.value), series: .value("Line", "Value"))
                            .foregroundStyle(Theme.lime)
                            .lineStyle(StrokeStyle(lineWidth: 2.5))
                            .interpolationMethod(.monotone)
                        if showCost {
                            LineMark(x: .value("Day", p.day), y: .value("Cost", p.cost), series: .value("Line", "Cost"))
                                .foregroundStyle(.white.opacity(0.5))
                                .lineStyle(StrokeStyle(lineWidth: 1.2, dash: [4, 4]))
                        }
                    }
                    if let shown {
                        RuleMark(x: .value("Day", shown.day)).foregroundStyle(.white.opacity(0.3))
                        PointMark(x: .value("Day", shown.day), y: .value("Value", shown.value)).foregroundStyle(Theme.lime).symbolSize(70)
                    }
                }
                .chartXAxis(.hidden)
                .insideYAxis()
                .chartYScale(domain: .automatic(includesZero: false))
                .chartXSelection(value: $scrubbed)
                .frame(height: 230)
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

    var body: some View {
        let s = store.summary
        VStack(spacing: 12) {
            HStack(spacing: 12) {
                card("Invested", Format.money(s.totalCost), sub: "incl. fees & shipping", tint: Theme.azure, valueTint: .white)
                card("Unrealized", Format.signedMoney(s.gain), sub: "on what's priced", tint: Theme.lime, valueTint: Theme.tone(s.gain),
                     tag: s.gainRatio.map { (Format.signedPercent($0), Theme.lime, Theme.ink) })
            }
            HStack(spacing: 12) {
                card("Today", Format.signedMoney(s.dayChange), sub: nil, tint: Theme.lime, valueTint: Theme.tone(s.dayChange),
                     tag: s.dayRatio.map { (Format.signedPercent($0), Theme.lime, Theme.ink) })
                card("Collection", "\(Int(s.items)) items", sub: "\(store.holdings.count) products", tint: Theme.planBlue, valueTint: .white,
                     tag: ("\(store.holdings.count) SKUs", Theme.planBlue, Color.white))
            }
            HStack(spacing: 12) {
                Image(systemName: "wallet.pass").font(.system(size: 17)).foregroundStyle(Theme.muted)
                    .frame(width: 40, height: 40).background(RoundedRectangle(cornerRadius: 12).fill(Theme.surface2))
                VStack(alignment: .leading, spacing: 2) {
                    Text("Spent in \(Date().formatted(.dateTime.month(.wide)))").font(.geist(14)).foregroundStyle(Theme.muted)
                    Text(Format.money(store.spentThisMonth)).font(.geist(17, .semibold)).monospacedDigit()
                }
                Spacer()
            }
            .surface()
        }
    }

    private func card(_ label: String, _ value: String, sub: String?, tint: Color, valueTint: Color, tag: (String, Color, Color)? = nil) -> some View {
        VStack(alignment: .leading, spacing: 10) {
            HStack(spacing: 8) {
                CardLabel(text: label)
                if let tag { SkewTag(text: tag.0, color: tag.1, textColor: tag.2) }
            }
            Text(value).font(.display(30)).monospacedDigit().foregroundStyle(valueTint).lineLimit(1).minimumScaleFactor(0.6)
            if let sub { Text(sub).font(.geist(13)).foregroundStyle(Theme.muted) }
        }
        .frame(maxWidth: .infinity, minHeight: 104, alignment: .topLeading)
        .tinted(tint, border: false)
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
                MiniTile(holding: mover, tag: "Biggest move today", icon: "flame.fill", color: Theme.lime, value: mover.dayChange,
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

    var body: some View {
        NavigationLink(value: holding.identity.productId) {
            VStack(alignment: .leading, spacing: 14) {
                ZStack(alignment: .topTrailing) {
                    HoldingArt(product: holding.product, identity: holding.identity, cornerRadius: 12)
                        .frame(height: 230)
                        .frame(maxWidth: .infinity)
                        .shadow(color: .black.opacity(0.6), radius: 16, y: 10)
                    Text(Format.signedPercent(holding.gainRatio).replacingOccurrences(of: ".00", with: ""))
                        .font(.geist(15, .bold)).foregroundStyle(Theme.ink)
                        .padding(.horizontal, 12).padding(.vertical, 7)
                        .background(Capsule().fill(Theme.lime))
                        .shadow(color: Theme.lime.opacity(0.5), radius: 10)
                        .offset(x: -8, y: 8)
                }
                .overlay(alignment: .bottomLeading) {
                    if let label = holding.label {
                        Text(label).font(.geist(15, .semibold)).foregroundStyle(Theme.ink)
                            .padding(.horizontal, 12).padding(.vertical, 7)
                            .background(Capsule().fill(.white))
                            .offset(x: 30, y: -40)
                    }
                }
                SkewTag(text: "Star of the collection", icon: "sparkles")
                DisplayText(text: (holding.product?.name ?? "").uppercased(), size: 32)
                    .frame(maxWidth: .infinity, alignment: .leading)
                    .padding(.top, 4)
                Text([holding.product?.setName, holding.label].compactMap { $0 }.joined(separator: " · ")).font(.geist(15)).foregroundStyle(Theme.muted)
                Text(Format.signedMoney(holding.gain)).font(.display(48)).monospacedDigit().foregroundStyle(Theme.lime)
                HStack(spacing: 8) {
                    stat("Paid", Format.money(holding.costBasis), .white)
                    stat("Worth", Format.money(holding.value), .white)
                    stat("Return", Format.signedPercent(holding.gainRatio), Theme.tone(holding.gainRatio))
                }
                if series.count > 1 {
                    Sparkline(points: series, color: Theme.lime).frame(height: 60)
                    MonoLabel(text: "Last 90 days")
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
            MonoLabel(text: label)
            Text(value).font(.geist(16, .semibold)).monospacedDigit().foregroundStyle(tint).lineLimit(1).minimumScaleFactor(0.7)
        }
        .padding(12)
        .frame(maxWidth: .infinity, alignment: .leading)
        .background(RoundedRectangle(cornerRadius: 14).fill(Theme.surface.opacity(0.9)))
        .overlay(RoundedRectangle(cornerRadius: 14).strokeBorder(Theme.border))
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
        Chart {
            ForEach(points) { p in
                AreaMark(x: .value("Day", p.day), y: .value("Value", p.value))
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
        .chartYScale(domain: .automatic(includesZero: false))
    }
}

// MARK: - Shelf

/// Your most valuable pieces standing on a glass ledge, each with a price tag below.
private struct ShelfSection: View {
    var holdings: [HoldingView]

    var body: some View {
        VStack(alignment: .leading, spacing: 14) {
            PageHeader(title: "Your shelf", subtitle: "Your most valuable pieces", size: 30).padding(.horizontal, 16)
            ScrollView(.horizontal, showsIndicators: false) {
                HStack(alignment: .bottom, spacing: 18) {
                    ForEach(Array(holdings.enumerated()), id: \.element.id) { i, h in
                        NavigationLink(value: h.identity.productId) {
                            VStack(alignment: .leading, spacing: 0) {
                                // A fixed stage: cards stand tall, wide boxes sit low and wide,
                                // so one tall piece never pushes the whole row down.
                                HoldingArt(product: h.product, identity: h.identity, cornerRadius: 12)
                                    .frame(width: 170, height: 150, alignment: .bottom)
                                    .shadow(color: .black.opacity(0.6), radius: 10, y: 8)
                                    .padding(.horizontal, 6)
                                // The glass ledge.
                                RoundedRectangle(cornerRadius: 2)
                                    .fill(LinearGradient(colors: [.white.opacity(0.18), .white.opacity(0.03)], startPoint: .top, endPoint: .bottom))
                                    .frame(width: 182, height: 10)
                                    .shadow(color: .white.opacity(0.08), radius: 8, y: -4)
                                VStack(alignment: .leading, spacing: 6) {
                                    HStack(spacing: 6) {
                                        Text(String(format: "%02d", i + 1)).font(.mono(11)).foregroundStyle(Theme.muted)
                                        Text(h.product?.name ?? "").font(.geist(14, .medium)).lineLimit(1).foregroundStyle(.white)
                                    }
                                    HStack(spacing: 8) {
                                        Text(Format.money(h.value)).font(.display(19)).monospacedDigit().foregroundStyle(.white)
                                        DeltaPill(ratio: h.gainRatio, size: 12)
                                    }
                                }
                                .padding(12)
                                .frame(width: 182, alignment: .leading)
                                .surface(radius: 12, padding: nil)
                                .padding(.top, 10)
                            }
                        }
                        .buttonStyle(.plain)
                    }
                }
                .padding(.horizontal, 16)
            }
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
            // The split, as one bar.
            HStack(spacing: 3) {
                ForEach(groups, id: \.0) { c, items in
                    let share = items.reduce(0) { $0 + ($1.value ?? 0) } / total
                    if share > 0.001 {
                        HStack(spacing: 6) {
                            Text(c.rawValue.uppercased()).font(.display(15))
                            Text("\(Int((share * 100).rounded()))%").font(.display(15))
                        }
                        .foregroundStyle(c == .graded ? Theme.ink : .white)
                        .lineLimit(1).minimumScaleFactor(0.5)
                        .frame(maxWidth: .infinity, minHeight: 38)
                        .background(RoundedRectangle(cornerRadius: 8).fill(c.color))
                    }
                }
            }
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
                CardLabel(text: category.rawValue, color: category.color)
                SkewTag(text: "\(Int((value / total * 100).rounded()))% of value", color: category.color, textColor: category == .graded ? Theme.ink : .white)
            }
            Text(category.blurb).font(.geist(14)).foregroundStyle(Theme.muted)
            VStack(alignment: .leading, spacing: 10) {
                HStack(spacing: -24) {
                    ForEach(Array(items.prefix(3).enumerated()), id: \.element.id) { i, h in
                        HoldingArt(product: h.product, identity: h.identity, cornerRadius: 8, caption: false)
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

    var body: some View {
        VStack(alignment: .leading, spacing: 18) {
            PageHeader(title: "Recently added", size: 30)
            VStack(alignment: .leading, spacing: 0) {
                ForEach(Array(items.enumerated()), id: \.element.id) { i, item in
                    NavigationLink(value: item.entry.identity.productId) {
                        HStack(alignment: .top, spacing: 14) {
                            // The timeline: a line with a dot per entry, the newest lit.
                            VStack(spacing: 0) {
                                Circle()
                                    .strokeBorder(i == 0 ? Theme.lime : Theme.subtle, lineWidth: 2)
                                    .background(Circle().fill(i == 0 ? Theme.lime.opacity(0.35) : Theme.background))
                                    .frame(width: 14, height: 14)
                                    .padding(.top, 22)
                                Rectangle().fill(Theme.border).frame(width: 1).frame(maxHeight: .infinity)
                            }
                            .frame(width: 14)
                            HoldingArt(product: item.product, identity: item.entry.identity, cornerRadius: 8, caption: false)
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
                        .frame(minHeight: 92)
                    }
                    .buttonStyle(.plain)
                }
            }
        }
    }
}
