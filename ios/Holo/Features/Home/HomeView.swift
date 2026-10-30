import Charts
import SwiftUI

/// Overview: what it's all worth, how that's moved, and what's moving today.
struct HomeView: View {
    var onScan: () -> Void
    @Environment(CollectionStore.self) private var store
    @Environment(SessionModel.self) private var session
    @State private var range = Range.month
    @State private var scrubbed: Date?
    @State private var account = false
    @State private var lists = false

    enum Range: String, CaseIterable {
        case week = "1W", month = "1M", quarter = "3M", year = "1Y", all = "All"

        var days: Int? {
            switch self {
            case .week: return 7
            case .month: return 30
            case .quarter: return 90
            case .year: return 365
            case .all: return nil
            }
        }
    }

    private var points: [TimelinePoint] {
        guard let days = range.days else { return store.timeline }
        return Array(store.timeline.suffix(days + 1))
    }

    /// The point under your finger, else today.
    private var shown: TimelinePoint? {
        guard let scrubbed else { return points.last }
        return points.min { abs($0.day.timeIntervalSince(scrubbed)) < abs($1.day.timeIntervalSince(scrubbed)) }
    }

    var body: some View {
        NavigationStack {
            ScrollView {
                switch store.status {
                case .idle, .loading:
                    ProgressView().padding(.top, 120)
                case let .failed(message):
                    VStack(spacing: 12) {
                        Text("Couldn't load your collection").font(.headline)
                        Text(message).font(.callout).foregroundStyle(Theme.muted).multilineTextAlignment(.center)
                        Button("Try again") { Task { await reload() } }
                    }
                    .padding(32)
                case .ready:
                    if store.holdings.isEmpty { empty } else { content }
                }
            }
            .background(Theme.background)
            .refreshable { await reload() }
            .navigationTitle("Holo")
            .toolbar {
                ToolbarItemGroup(placement: .topBarTrailing) {
                    Button { lists = true } label: { Image(systemName: "heart.text.square") }.accessibilityLabel("Watchlist and wishlist")
                    Button { account = true } label: { Image(systemName: "person.crop.circle") }.accessibilityLabel("Account")
                }
            }
            .navigationDestination(for: String.self) { ProductDetailView(productId: $0) }
            .sheet(isPresented: $account) { SettingsView() }
            .sheet(isPresented: $lists) { ListsView() }
        }
    }

    private var content: some View {
        let s = store.summary
        let first = points.first
        let change = (shown?.value ?? 0) - (first?.value ?? 0)
        let base = first?.value ?? 0
        return VStack(alignment: .leading, spacing: 22) {
            VStack(alignment: .leading, spacing: 4) {
                Text(scrubbed == nil ? "Your collection's worth" : (shown?.day.formatted(date: .abbreviated, time: .omitted) ?? ""))
                    .font(.caption.weight(.medium)).foregroundStyle(Theme.muted).textCase(.uppercase)
                Text(Format.money(scrubbed == nil ? s.value : shown?.value))
                    .font(.system(size: 46, weight: .heavy, design: .rounded))
                    .monospacedDigit()
                    .foregroundStyle(Theme.lime)
                    .minimumScaleFactor(0.6)
                    .lineLimit(1)
                    .contentTransition(.numericText())
                HStack(spacing: 6) {
                    Text(Format.signedMoney(change)).foregroundStyle(Theme.tone(change))
                    Text(base > 0 ? Format.signedPercent(change / base) : "").foregroundStyle(Theme.tone(change))
                    Text(range == .all ? "all time" : "past \(range.rawValue)").foregroundStyle(Theme.muted)
                }
                .font(.subheadline.weight(.semibold)).monospacedDigit()
            }

            if points.count > 1 {
                VStack(spacing: 10) {
                    Chart(points) { p in
                        AreaMark(x: .value("Day", p.day), y: .value("Value", p.value))
                            .foregroundStyle(LinearGradient(colors: [Theme.lime.opacity(0.28), Theme.lime.opacity(0)], startPoint: .top, endPoint: .bottom))
                            .interpolationMethod(.monotone)
                        LineMark(x: .value("Day", p.day), y: .value("Value", p.value))
                            .foregroundStyle(Theme.lime)
                            .interpolationMethod(.monotone)
                        if let shown, scrubbed != nil, shown.date == p.date {
                            RuleMark(x: .value("Day", p.day)).foregroundStyle(.white.opacity(0.35))
                            PointMark(x: .value("Day", p.day), y: .value("Value", p.value)).foregroundStyle(Theme.lime)
                        }
                    }
                    .chartXAxis(.hidden)
                    .chartYAxis(.hidden)
                    .chartXSelection(value: $scrubbed)
                    .frame(height: 190)

                    Picker("Range", selection: $range) {
                        ForEach(Range.allCases, id: \.self) { Text($0.rawValue) }
                    }
                    .pickerStyle(.segmented)
                }
            }

            HStack(spacing: 10) {
                stat("Today", Format.signedMoney(s.dayChange), Theme.tone(s.dayChange))
                stat("All time", Format.signedMoney(s.gain), Theme.tone(s.gain))
                stat("Invested", Format.moneyWhole(s.totalCost), .primary)
            }

            movers
            recent
        }
        .padding(.horizontal, 16)
        .padding(.bottom, 40)
    }

    private func stat(_ label: String, _ value: String, _ tint: Color) -> some View {
        VStack(alignment: .leading, spacing: 3) {
            Text(label).font(.caption2.weight(.medium)).foregroundStyle(Theme.muted).textCase(.uppercase)
            Text(value).font(.subheadline.weight(.semibold)).monospacedDigit().foregroundStyle(tint).lineLimit(1).minimumScaleFactor(0.7)
        }
        .padding(12)
        .frame(maxWidth: .infinity, alignment: .leading)
        .background(Theme.surface, in: RoundedRectangle(cornerRadius: 14, style: .continuous))
    }

    @ViewBuilder private var movers: some View {
        let moving = store.holdings.filter { ($0.change24hPct ?? 0) != 0 }
        let up = moving.filter { ($0.change24hPct ?? 0) > 0 }.sorted { ($0.change24hPct ?? 0) > ($1.change24hPct ?? 0) }.prefix(4)
        let down = moving.filter { ($0.change24hPct ?? 0) < 0 }.sorted { ($0.change24hPct ?? 0) < ($1.change24hPct ?? 0) }.prefix(4)
        if !up.isEmpty || !down.isEmpty {
            Panel {
                VStack(alignment: .leading, spacing: 12) {
                    Text("Moving today").font(.headline)
                    ForEach(Array(up) + Array(down)) { h in
                        NavigationLink(value: h.identity.productId) { MiniRow(holding: h, trailing: Format.signedPercent((h.change24hPct ?? 0) / 100), tint: Theme.tone(h.change24hPct)) }
                            .buttonStyle(.plain)
                    }
                }
            }
        }
    }

    @ViewBuilder private var recent: some View {
        let latest = store.holdings.sorted { ($0.lastAcquired ?? "") > ($1.lastAcquired ?? "") }.prefix(5)
        if !latest.isEmpty {
            Panel {
                VStack(alignment: .leading, spacing: 12) {
                    Text("Recently added").font(.headline)
                    ForEach(Array(latest)) { h in
                        NavigationLink(value: h.identity.productId) { MiniRow(holding: h, trailing: (h.isConditionEstimate ? "≈ " : "") + Format.money(h.value), tint: .primary) }
                            .buttonStyle(.plain)
                    }
                }
            }
        }
    }

    private var empty: some View {
        VStack(spacing: 14) {
            Image(systemName: "rectangle.stack.badge.plus").font(.system(size: 44)).foregroundStyle(Theme.lime)
            Text("Start your collection").font(.title3.bold())
            Text("Scan your cards to see what they're worth.").foregroundStyle(Theme.muted).multilineTextAlignment(.center)
            Button { onScan() } label: { Label("Scan cards", systemImage: "viewfinder") }
                .buttonStyle(LimeButtonStyle())
        }
        .padding(32)
        .padding(.top, 60)
    }

    private func reload() async {
        if case let .signedIn(userId, _) = session.state { await store.load(userId: userId) }
    }
}

struct MiniRow: View {
    var holding: HoldingView
    var trailing: String
    var tint: Color

    var body: some View {
        HStack(spacing: 12) {
            ProductImage(product: holding.product, cornerRadius: 4).frame(width: 34, height: 48)
            VStack(alignment: .leading, spacing: 2) {
                Text(holding.product?.name ?? "Unknown").font(.subheadline.weight(.medium)).lineLimit(1)
                Text([holding.label, holding.product?.setName].compactMap { $0 }.joined(separator: " · ")).font(.caption).foregroundStyle(Theme.muted).lineLimit(1)
            }
            Spacer()
            Text(trailing).font(.subheadline.weight(.semibold)).monospacedDigit().foregroundStyle(tint)
        }
        .contentShape(Rectangle())
    }
}
