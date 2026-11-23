import Charts
import SwiftUI

/// How the collection is allocated and how it has performed, like the website's Analytics page.
/// Percentages are time-weighted: buying and selling never count as performance.
struct AnalyticsView: View {
    @Environment(CollectionStore.self) private var store

    enum Span: String, CaseIterable {
        case month = "1M", quarter = "3M", year = "1Y", all = "ALL"
        var days: Int? { switch self { case .month: 30; case .quarter: 90; case .year: 365; case .all: nil } }
        var phrase: String { switch self { case .month: "past month"; case .quarter: "past 3 months"; case .year: "past year"; case .all: "all time" } }
    }
    enum Mode: String, CaseIterable { case value = "Value", ret = "Return", drawdown = "Drawdown" }
    enum SetSort { case value, ret }
    enum RankBy { case dollar, percent }

    private var today: String { Format.day() }

    var body: some View {
        let timeline = store.timeline
        let holdings = store.holdings
        let s = store.summary
        let risk = Analytics.risk(timeline)
        let total = s.gain + s.realized
        ScrollView {
            if holdings.isEmpty {
                EmptyPage(title: "No numbers yet", line: "Your numbers appear after your first card.", action: "Scan a card",
                          onAction: { Router.shared.scanRequest += 1 })
                    .padding(.top, 40)
            } else {
            // Lazy, like Home: the charts further down are only built as they scroll near, so the
            // page pushes in quickly.
            // Seven sections, each said once: the return and its chart, winners and losers, the
            // breakdown, month by month, how spread out it is, and the rarer measures folded away.
            LazyVStack(alignment: .leading, spacing: 44) {
                ValueLineHero(label: "Total return", value: total, points: []) {
                    HStack(spacing: 8) {
                        if s.totalCost > 0 { DeltaPill(ratio: total / s.totalCost, size: 13) }
                        Text("on \(Format.money(s.totalCost)) invested").font(.geist(13)).foregroundStyle(Theme.muted)
                    }
                } below: {
                    VStack(alignment: .leading, spacing: 18) {
                        // The one chart: its own view, so dragging redraws only the chart.
                        HistorySection(timeline: timeline)
                        HStack(spacing: 8) {
                            GlassStat(label: "Market only", value: Format.signedPercent(risk.totalReturn), tint: Theme.tone(risk.totalReturn))
                            // Realized opens Sales & taxes (every sale, ready for tax time).
                            NavigationLink(value: MorePage.sales) {
                                GlassStat(label: "Realized", value: Format.signedMoney(s.realized), tint: Theme.tone(s.realized), opens: true)
                            }
                            .buttonStyle(.plain)
                            GlassStat(label: "Invested", value: Format.money(s.totalCost))
                        }
                    }
                }
                WinnersLosers(holdings: holdings).reveal()
                Breakdown(holdings: holdings).reveal()
                ByMonth(timeline: timeline, risk: risk, activity: Array(Analytics.monthlyActivity(store.portfolioTransactions, today: today).suffix(12))).reveal()
                Diversification(c: Analytics.concentration(holdings), holdings: holdings).reveal()
                AdvancedStats(risk: risk, points: Analytics.returnVsTime(holdings, today: today))
                Text("Percentages are time-weighted, so buying and selling never count as gains. History starts \(timeline.first.map { $0.day.formatted(date: .abbreviated, time: .omitted) } ?? "—").")
                    .font(.geist(12)).foregroundStyle(Theme.subtle)
            }
            .padding(.horizontal, 16)
            .padding(.bottom, 120)
            }
        }
        .background(Theme.background)
        .replaysAnimations()
        .navigationBarTitleDisplayMode(.inline)
        .pageTitle("Analytics")
    }

}

/// Each set's value, share and return: one thin bar per row (inside Breakdown).
private struct SetRows: View {
    var holdings: [HoldingView]

    var body: some View {
        let rows = Analytics.bySet(holdings)
        let maxShare = max(rows.map(\.share).max() ?? 0, 0.0001)
        VStack(spacing: 0) {
            ForEach(Array(rows.enumerated()), id: \.element.id) { i, r in
                BreakdownRow(title: r.name, count: r.holdings, value: r.value, ret: r.ret,
                             line: "\(percent(r.share, 0)) of value · \(Format.signedMoney(r.gain))",
                             fraction: r.share / maxShare, delay: Double(min(i, 8)) * 0.05)
                if r.id != rows.last?.id { Rectangle().fill(Theme.border).frame(height: 1) }
            }
        }
    }
}

/// One row of the breakdown: name ×count, value and its return, one quiet line, a thin bar.
private struct BreakdownRow: View {
    var title: String
    var count: Int
    var value: Double
    var ret: Double?
    var line: String
    var fraction: Double
    var delay: Double

    var body: some View {
        VStack(alignment: .leading, spacing: 6) {
            HStack(alignment: .firstTextBaseline) {
                (Text(title).font(.geist(14, .medium)) + Text("  ×\(count)").font(.geist(12)).foregroundColor(Theme.subtle)).lineLimit(1)
                Spacer(minLength: 8)
                Text(Format.money(value)).font(.geist(14, .semibold)).monospacedDigit()
                if let ret, abs(ret) >= 0.0005 { DeltaPill(ratio: ret, size: 11) }
            }
            Text(line).font(.geist(12)).monospacedDigit().foregroundStyle(Theme.muted).lineLimit(1)
            GrowBar(fraction: fraction, color: (ret ?? 0) < 0 ? Theme.planPink : Theme.lime, height: 3, delay: delay)
                .padding(.top, 2)
        }
        .padding(.vertical, 12)
    }
}

/// Winners & losers: your holdings that gained most or lost most, by dollars or percent, each
/// with a ⋯ for the card's quick actions. Replaces "Where it comes from", Best investments and
/// Underperformers (the same cards three times).
private struct WinnersLosers: View {
    var holdings: [HoldingView]
    enum Side: Hashable { case gains, losses }
    @State private var side = Side.gains
    @State private var rankBy = AnalyticsView.RankBy.dollar
    @State private var showAll = false

    var body: some View {
        let priced = holdings.filter { $0.gain != nil }
        let up = priced.filter { ($0.gain ?? 0) > 0 }.count
        let key = { (h: HoldingView) in rankBy == .dollar ? (h.gain ?? 0) : (h.gainRatio ?? 0) }
        let all = side == .gains
            ? priced.filter { ($0.gain ?? 0) > 0 }.sorted { key($0) > key($1) }
            : priced.filter { ($0.gain ?? 0) < 0 }.sorted { key($0) < key($1) }
        let items = showAll ? all : Array(all.prefix(5))
        VStack(alignment: .leading, spacing: 14) {
            MoreHeading(title: "Winners & losers", subtitle: priced.isEmpty ? nil : "\(up) of \(priced.count) in profit")
            HStack {
                ChipPicker(options: [(Side.gains, "Gains"), (.losses, "Losses")], selection: Binding(get: { side }, set: { side = $0; showAll = false })).fixedSize()
                Spacer(minLength: 8)
                ChipPicker(options: [(AnalyticsView.RankBy.dollar, "$"), (.percent, "%")], selection: $rankBy).fixedSize()
            }
            VStack(spacing: 0) {
                if items.isEmpty {
                    Text(side == .gains ? "No holdings are in profit yet." : "Nothing is below cost.")
                        .font(.geist(14)).foregroundStyle(Theme.muted).padding(.vertical, 16).frame(maxWidth: .infinity, alignment: .leading)
                }
                ForEach(Array(items.enumerated()), id: \.element.id) { i, h in
                    HStack(spacing: 4) {
                        CardLink(productId: h.identity.productId, identity: h.identity) {
                            HStack(spacing: 12) {
                                HoldingArt(product: h.product, identity: h.identity, cornerRadius: 3, caption: false).frame(width: 36, height: 50)
                                VStack(alignment: .leading, spacing: 2) {
                                    Text(h.product.map(ActionsSheet.shortName) ?? "Unknown").font(.geist(15, .medium)).foregroundStyle(.white).lineLimit(1)
                                    Text("\(Format.money(h.value)) value · \(Format.money(h.costBasis)) cost").font(.geist(12)).monospacedDigit().foregroundStyle(Theme.muted).lineLimit(1)
                                }
                                Spacer(minLength: 8)
                                Text(rankBy == .dollar ? Format.signedMoney(h.gain) : Format.signedPercent(h.gainRatio))
                                    .font(.geist(15, .semibold)).monospacedDigit().foregroundStyle(Theme.tone(h.gain)).fixedSize()
                            }
                            .contentShape(Rectangle())
                        }
                        .buttonStyle(.plain)
                        RowMoreButton(label: h.product?.name) { if let p = h.product { Router.shared.quickCard = p } }
                            .padding(.trailing, -10)
                    }
                    .padding(.vertical, 10)
                    .overlay(alignment: .top) {
                        if i > 0 { Rectangle().fill(Theme.border).frame(height: 1) }
                    }
                }
            }
            if all.count > 5 {
                Button(showAll ? "Show fewer" : "Show all \(all.count)") { showAll.toggle() }
                    .font(.geist(14, .medium)).foregroundStyle(Theme.muted)
            }
        }
    }
}

/// Breakdown: what you own by type, by set, or as a map of tiles, one chip row to switch.
private struct Breakdown: View {
    var holdings: [HoldingView]
    enum Kind: Hashable { case type, set, map }
    @State private var kind = Kind.type

    var body: some View {
        VStack(alignment: .leading, spacing: 14) {
            MoreHeading(title: "Breakdown", subtitle: nil)
            ChipPicker(options: [(Kind.type, "Type"), (.set, "Set"), (.map, "Map")], selection: $kind)
            switch kind {
            case .type: TypeBreakdown(groups: Analytics.byType(holdings))
            case .set: SetRows(holdings: holdings)
            case .map: CollectionMap(holdings: holdings)
            }
        }
    }
}

/// By month: each month's return as a grid, the money put in each month, and the best and
/// worst days and biggest drop as three small tiles.
private struct ByMonth: View {
    var timeline: [TimelinePoint]
    var risk: Analytics.Risk
    var activity: [Analytics.Month]

    var body: some View {
        let months = Analytics.monthlyReturns(timeline)
        let short = { (d: String?) in d.flatMap { Format.isoDay.date(from: $0)?.formatted(.dateTime.month(.abbreviated).day()) } ?? "—" }
        VStack(alignment: .leading, spacing: 14) {
            MoreHeading(title: "By month", subtitle: months.isEmpty ? nil : "\(months.filter { $0.ret > 0 }.count) of \(months.count) months up")
            MonthlyHeatmap(months: months)
            HStack(spacing: 8) {
                GlassStat(label: "Best day", value: Format.signedMoney(risk.bestDay?.gain), tint: Theme.tone(risk.bestDay?.gain))
                GlassStat(label: "Worst day", value: Format.signedMoney(risk.worstDay?.gain), tint: Theme.tone(risk.worstDay?.gain))
                GlassStat(label: "Biggest drop", value: percent(risk.maxDrawdown, 1), tint: Theme.tone(risk.maxDrawdown))
            }
            if risk.bestDay != nil || risk.maxDrawdownTo != nil {
                Text("Best \(short(risk.bestDay?.date)) · worst \(short(risk.worstDay?.date))\(risk.maxDrawdownTo != nil ? " · drop \(short(risk.maxDrawdownFrom)) → \(short(risk.maxDrawdownTo))" : "")")
                    .font(.geist(12)).foregroundStyle(Theme.subtle).lineLimit(1).minimumScaleFactor(0.85)
            }
            if activity.contains(where: { $0.invested > 0 }) {
                VStack(alignment: .leading, spacing: 10) {
                    MonoLabel(text: "Invested each month")
                    GrowingBars(months: activity, highlight: nil)
                }
                .padding(.top, 10)
            }
        }
    }
}

/// Portfolio history: value, return or drawdown over a range, with a finger to read any day.
/// Holds its own range, mode and scrub position so the rest of Analytics doesn't redraw while
/// you drag.
private struct HistorySection: View {
    var timeline: [TimelinePoint]
    @State private var range = AnalyticsView.Span.year
    @State private var mode = AnalyticsView.Mode.value
    @State private var scrubbed: Date?
    /// The range worked out once per range or timeline change (not on every drag): dates read,
    /// returns and drawdowns computed, and long ranges thinned to about 180 points.
    @State private var prepared = Prepared()

    private typealias Span = AnalyticsView.Span
    private typealias Mode = AnalyticsView.Mode

    /// One day on the chart, with its date read once.
    struct Day: Identifiable {
        var id: Int
        var date: Date
        var value: Double
        var cost: Double
        var ret: Double
        var dd: Double
    }

    struct Prepared {
        var days: [Day] = []
        /// Days in the range before thinning.
        var count = 0
        var gain = 0.0
        var twr = 0.0
        var valueDomain: ClosedRange<Double> = 0 ... 1
        var retRange: (lo: Double, hi: Double) = (0, 0)
        var ddRange: (lo: Double, hi: Double) = (0, 0)
    }

    private var key: String {
        "\(range.rawValue)-\(timeline.count)-\(timeline.first?.date ?? "")-\(timeline.last?.date ?? "")-\(timeline.last?.value ?? 0)-\(timeline.last?.twrIndex ?? 0)"
    }

    private func prepare() {
        let slice: [TimelinePoint] = {
            guard let days = range.days, let start = Calendar.current.date(byAdding: .day, value: -days, to: Date()) else { return timeline }
            let from = Format.day(start)
            let s = timeline.filter { $0.date >= from }
            return s.isEmpty ? Array(timeline.suffix(1)) : s
        }()
        let base = slice.first?.twrIndex ?? 1
        let dd = Analytics.drawdowns(slice)
        let rets = slice.map { base > 0 ? $0.twrIndex / base - 1 : 0 }
        var p = Prepared()
        p.count = slice.count
        p.gain = slice.dropFirst().reduce(0) { $0 + $1.marketGain }
        p.twr = rets.last ?? 0
        p.valueDomain = ChartTicks.domain(slice.map(\.value) + slice.map(\.cost))
        p.retRange = (rets.min() ?? 0, rets.max() ?? 0)
        p.ddRange = (dd.min() ?? 0, dd.max() ?? 0)
        // Thin long ranges, keeping the highs and lows so the line still reaches them.
        let step = max(1, slice.count / 180)
        var keep = Set<Int>()
        if step > 1 {
            for arr in [slice.map(\.value), rets, dd] {
                if let i = arr.indices.min(by: { arr[$0] < arr[$1] }) { keep.insert(i) }
                if let i = arr.indices.max(by: { arr[$0] < arr[$1] }) { keep.insert(i) }
            }
        }
        p.days.reserveCapacity(slice.count / step + keep.count + 2)
        for i in slice.indices where i % step == 0 || i == slice.count - 1 || keep.contains(i) {
            let pt = slice[i]
            p.days.append(Day(id: i, date: pt.day, value: pt.value, cost: pt.cost, ret: rets[i], dd: dd[i]))
        }
        prepared = p
    }

    /// The day nearest the finger: a quick halving search over the sorted days.
    private var shown: Day? {
        let days = prepared.days
        guard let scrubbed, !days.isEmpty else { return nil }
        var lo = 0, hi = days.count - 1
        while lo < hi {
            let mid = (lo + hi) / 2
            if days[mid].date < scrubbed { lo = mid + 1 } else { hi = mid }
        }
        if lo > 0, abs(days[lo - 1].date.timeIntervalSince(scrubbed)) < abs(days[lo].date.timeIntervalSince(scrubbed)) { lo -= 1 }
        return days[lo]
    }

    var body: some View {
        let p = prepared
        let shown = self.shown
        return VStack(alignment: .leading, spacing: 12) {
            ChipPicker(options: Mode.allCases.map { ($0, $0.rawValue) }, selection: $mode)
            // What the chart says, or the day under your finger.
            Group {
                if let d = shown {
                    HStack(spacing: 6) {
                        switch mode {
                        case .value: Text(Format.money(d.value)).foregroundStyle(.white)
                        case .ret: Text(Format.signedPercent(d.ret)).foregroundStyle(Theme.tone(d.ret))
                        case .drawdown: Text(percent(d.dd, 1)).foregroundStyle(Theme.tone(d.dd))
                        }
                        Text(d.date.formatted(date: .abbreviated, time: .omitted)).foregroundStyle(Theme.muted)
                    }
                } else {
                    HStack(spacing: 6) {
                        Text(Format.signedMoney(p.gain)).foregroundStyle(Theme.tone(p.gain))
                        DeltaPill(ratio: p.twr, size: 13)
                        Text(range.phrase).foregroundStyle(Theme.muted)
                    }
                }
            }
            .font(.geist(15, .medium)).monospacedDigit().lineLimit(1).minimumScaleFactor(0.8)

            if p.count > 1 {
                chart(p, shown: shown)
            } else {
                Text("Not enough history yet.").font(.geist(14)).foregroundStyle(Theme.muted).padding(.vertical, 40).frame(maxWidth: .infinity)
            }
            // The range under the chart, like a stocks app; one quiet line on what it shows.
            ChipPicker(options: Span.allCases.map { ($0, $0 == .all ? "All" : $0.rawValue) }, selection: $range, fills: true)
            Text(caption).font(.geist(12)).foregroundStyle(Theme.subtle)
        }
        // Before the first frame, and again whenever the range or the history changes.
        .onChange(of: key, initial: true) { _, _ in prepare() }
    }

    private var caption: String {
        switch mode {
        case .value: return "Dashed: what you paid. Drag to read a day."
        case .ret: return "Price moves only; buying and selling don't count."
        case .drawdown: return "How far below its last high. 0% is a new high."
        }
    }

    private func y(_ d: Day) -> Double {
        switch mode {
        case .value: return d.value
        case .ret: return d.ret
        case .drawdown: return d.dd
        }
    }

    @ViewBuilder
    private func chart(_ p: Prepared, shown: Day?) -> some View {
        let tint: Color = mode == .value ? Theme.lime : mode == .drawdown ? Theme.down : p.twr >= 0 ? Theme.up : Theme.down
        let domain: ClosedRange<Double> = {
            if mode == .value { return p.valueDomain }
            let r = mode == .ret ? p.retRange : p.ddRange
            let lo = min(r.lo, 0)
            let hi = max(r.hi, 0)
            let pad = max((hi - lo) * 0.12, 0.01)
            return (lo - pad)...(mode == .drawdown ? pad : hi + pad)
        }()
        Chart {
            if mode != .value { RuleMark(y: .value("Zero", 0)).foregroundStyle(Theme.borderStrong) }
            ForEach(p.days) { d in
                if mode == .value {
                    LineMark(x: .value("Day", d.date), y: .value("Cost", d.cost), series: .value("Line", "Cost"))
                        .foregroundStyle(Theme.subtle).lineStyle(StrokeStyle(lineWidth: 1.5, dash: [4, 4]))
                }
                AreaMark(x: .value("Day", d.date), yStart: .value("Base", mode == .value ? domain.lowerBound : 0), yEnd: .value("Y", y(d)))
                    .foregroundStyle(LinearGradient(colors: [tint.opacity(0.28), tint.opacity(0)], startPoint: mode == .drawdown ? .bottom : .top, endPoint: mode == .drawdown ? .top : .bottom))
                    .interpolationMethod(.monotone)
                LineMark(x: .value("Day", d.date), y: .value("Y", y(d)), series: .value("Line", "Main"))
                    .foregroundStyle(tint).lineStyle(StrokeStyle(lineWidth: 2.5)).interpolationMethod(.monotone)
            }
            if let d = shown {
                RuleMark(x: .value("Day", d.date)).foregroundStyle(.white.opacity(0.3))
                PointMark(x: .value("Day", d.date), y: .value("Y", y(d))).foregroundStyle(tint).symbolSize(80)
            }
        }
        .chartXAxis(.hidden)
        .chartYScale(domain: domain)
        // Labels inside the plot, so the line runs to the right edge.
        .insideYAxis(label: { mode == .value ? ChartTicks.label($0) : percent($0, 0) })
        .chartXSelection(value: $scrubbed)
        .frame(height: 240)
        .drawIn(replay: "\(mode.rawValue)\(range.rawValue)")
        .sensoryFeedback(.selection, trigger: shown?.id)
    }

}

/// "12%" or "−3.4%", unsigned unless negative.
private func percent(_ r: Double, _ decimals: Int) -> String {
    let v = String(format: "%.\(decimals)f%%", abs(r) * 100)
    return r < -0.000_05 ? "−\(v)" : v
}

/// Monthly bars that rise from the floor when they scroll into view, the biggest in lime.
private struct GrowingBars: View {
    var months: [Analytics.Month]
    var highlight: String?
    @Environment(\.accessibilityReduceMotion) private var reduceMotion
    @State private var grown = false

    var body: some View {
        Chart(months) { m in
            BarMark(x: .value("Month", m.date, unit: .month), y: .value("Invested", m.invested * (grown || reduceMotion ? 1 : 0.02)))
                .foregroundStyle(highlight == nil || m.month == highlight ? Theme.lime : Theme.planBlue)
                .cornerRadius(4)
        }
        .chartYScale(domain: 0...max(1, (months.map(\.invested).max() ?? 1) * 1.1))
        .chartXAxis {
            AxisMarks(values: .stride(by: .month, count: 2)) { _ in
                AxisValueLabel(format: .dateTime.month(.abbreviated), centered: true).font(.geist(11)).foregroundStyle(Theme.subtle)
            }
        }
        .chartYAxis {
            AxisMarks(position: .trailing, values: .automatic(desiredCount: 3)) { v in
                AxisGridLine().foregroundStyle(Color.white.opacity(0.05))
                AxisValueLabel { if let d = v.as(Double.self) { Text(ChartTicks.label(d)).font(.geist(11)).foregroundStyle(Theme.subtle) } }
            }
        }
        .frame(height: 190)
        .onFirstVisible { grow() }
        .onReplay {
            grown = false
            grow()
        }
    }

    private func grow() {
        guard !reduceMotion else { return }
        withAnimation(.spring(response: 0.9, dampingFraction: 0.8).delay(0.2)) { grown = true }
    }
}

/// Each month's time-weighted return as a colored cell: two rows of six per year, so a year
/// fits the screen. Cells pop in one after another.
private struct MonthlyHeatmap: View {
    var months: [Analytics.MonthReturn]
    private static let names = ["Jan", "Feb", "Mar", "Apr", "May", "Jun", "Jul", "Aug", "Sep", "Oct", "Nov", "Dec"]

    var body: some View {
        if let best = months.max(by: { $0.ret < $1.ret }), let worst = months.min(by: { $0.ret < $1.ret }) {
            let years = Set(months.map(\.year)).sorted(by: >)
            let positive = months.filter { $0.ret > 0 }.count
            let _ = (best, worst, positive)
            VStack(alignment: .leading, spacing: 16) {
                VStack(alignment: .leading, spacing: 18) {
                    ForEach(years, id: \.self) { y in
                        let row = months.filter { $0.year == y }
                        let yearRet = row.reduce(1.0) { $0 * (1 + $1.ret) } - 1
                        VStack(alignment: .leading, spacing: 8) {
                            HStack {
                                Text(String(y)).font(.display(20)).tracking(-0.5).displayTrim(20)
                                Spacer()
                                DeltaPill(ratio: yearRet, size: 12)
                            }
                            // Only months since you started (and up to now): no year of empty boxes.
                            let first = row.map(\.month).min() ?? 0
                            let last = y == years.first ? (row.map(\.month).max() ?? 11) : 11
                            let span = y == years.last ? first...last : 0...last
                            LazyVGrid(columns: Array(repeating: GridItem(.flexible(), spacing: 5), count: 6), spacing: 5) {
                                ForEach(Array(span), id: \.self) { i in
                                    cell(i, row.first { $0.month == i })
                                        .popIn(delay: Double(i) * 0.03)
                                }
                            }
                        }
                    }
                }
                .surface(radius: 16, padding: 16)
            }
        }
    }

    private func extreme(_ label: String, _ m: Analytics.MonthReturn) -> some View {
        VStack(alignment: .leading, spacing: 4) {
            MonoLabel(text: label)
            Text(Format.signedPercent(m.ret)).font(.display(24)).tracking(-0.6).monospacedDigit().foregroundStyle(Theme.tone(m.ret)).displayTrim(24)
            Text("\(Self.names[m.month]) \(String(m.year))").font(.geist(12)).foregroundStyle(Theme.muted)
        }
        .frame(maxWidth: .infinity, alignment: .leading)
        .surface(radius: 16)
    }

    private func cell(_ i: Int, _ m: Analytics.MonthReturn?) -> some View {
        VStack(spacing: 2) {
            Text(Self.names[i].uppercased()).font(.mono(9)).opacity(0.7)
            Text(m.map { Format.signedPercent($0.ret) } ?? "").font(.geist(11, .semibold)).monospacedDigit()
                .lineLimit(1).minimumScaleFactor(0.6)
        }
        // Dark text on lime, white on pink and on empty months.
        .foregroundStyle(m.map { $0.ret >= 0 && heat($0.ret) > 0.45 ? Theme.ink : .white } ?? Theme.subtle)
        .frame(maxWidth: .infinity)
        .frame(height: 44)
        .background(
            RoundedRectangle(cornerRadius: 8, style: .continuous)
                .fill(m.map { ($0.ret >= 0 ? Theme.lime : Theme.planPink).opacity(heat($0.ret)) } ?? Color.white.opacity(0.03))
        )
    }

    /// Stronger color for bigger moves; square root so small moves still show.
    private func heat(_ ret: Double) -> Double {
        let t = min(1, abs(ret) / 0.12).squareRoot()
        return 0.14 + t * 0.86
    }
}

/// Each holding's return against how long you've held it.
private struct ReturnVsTime: View {
    var points: [Analytics.HeldPoint]
    /// The dot you tapped, shown by name under the chart.
    @State private var selected: String?

    var body: some View {
        if !points.isEmpty {
            let avg = Analytics.averageHoldDays(points)
            VStack(alignment: .leading, spacing: 16) {
                VStack(alignment: .leading, spacing: 12) {
                    Text("Return vs. time held").font(.geist(15, .semibold)).foregroundStyle(.white)
                    if let avg {
                        HStack(alignment: .firstTextBaseline, spacing: 6) {
                            CountingText(value: avg, format: { "\(Int($0.rounded()))" })
                                .font(.display(34)).tracking(-0.9).monospacedDigit().displayTrim(34)
                            Text("days, average hold").font(.geist(14)).foregroundStyle(Theme.muted)
                        }
                    }
                    // Room around the edges so the biggest dots and the axis labels aren't cut off.
                    let maxDays = Double(points.map(\.days).max() ?? 1)
                    let lo = min(points.map(\.ret).min() ?? 0, 0)
                    let hi = max(points.map(\.ret).max() ?? 0, 0)
                    let pad = max((hi - lo) * 0.18, 0.1)
                    plot(maxDays: maxDays, lo: lo, hi: hi, pad: pad)
                    if let p = points.first(where: { $0.id == selected }) { selectedCard(p) }
                }
                .surface(radius: 16, padding: 16)
            }
        }
    }

    /// The dots, the zero line and the axes; tap near a dot to name it.
    private func plot(maxDays: Double, lo: Double, hi: Double, pad: Double) -> some View {
        Chart {
            ForEach(points) { p in
                PointMark(x: .value("Days held", Double(p.days)), y: .value("Return", p.ret))
                    .foregroundStyle(dotColor(p))
                    .symbolSize(30 + min(260, p.value / 4))
            }
            RuleMark(y: .value("Zero", 0)).foregroundStyle(Theme.borderStrong)
        }
        .chartXScale(domain: (-maxDays * 0.08)...(maxDays * 1.08 + 1))
        .chartYScale(domain: (lo - pad)...(hi + pad))
        .chartXAxis {
            AxisMarks(values: .automatic(desiredCount: 4)) { v in
                AxisValueLabel { if let d = v.as(Double.self), d >= 0 { Text("\(Int(d))d").font(.geist(11)).foregroundStyle(Theme.subtle) } }
            }
        }
        .chartYAxis {
            AxisMarks(position: .trailing, values: .automatic(desiredCount: 4)) { v in
                AxisGridLine().foregroundStyle(Color.white.opacity(0.05))
                AxisValueLabel { if let d = v.as(Double.self) { Text(percent(d, 0)).font(.geist(11)).foregroundStyle(Theme.subtle) } }
            }
        }
        .chartOverlay { proxy in
            GeometryReader { geo in
                Rectangle().fill(.clear).contentShape(Rectangle())
                    .onTapGesture { location in pick(at: location, proxy: proxy, origin: proxy.plotFrame.map { geo[$0].origin } ?? .zero) }
            }
        }
        .frame(height: 220)
        .drawIn(duration: 1.0)
    }

    private func dotColor(_ p: Analytics.HeldPoint) -> Color {
        let base = p.ret >= 0 ? Theme.up : Theme.down
        return base.opacity(selected == nil || selected == p.id ? 0.9 : 0.3)
    }

    /// The nearest dot to a tap, if it's close; tapping it again clears it.
    private func pick(at location: CGPoint, proxy: ChartProxy, origin: CGPoint) {
        var best: (id: String, distance: CGFloat)?
        for p in points {
            guard let pos = proxy.position(for: (Double(p.days), p.ret)) else { continue }
            let dx: CGFloat = pos.x + origin.x - location.x
            let dy: CGFloat = pos.y + origin.y - location.y
            let d: CGFloat = (dx * dx + dy * dy).squareRoot()
            if best == nil || d < best!.distance { best = (p.id, d) }
        }
        Haptics.tap()
        let next: String? = best.flatMap { $0.distance < 36 && $0.id != selected ? $0.id : nil }
        withAnimation(.snappy(duration: 0.2)) { selected = next }
    }

    private func selectedCard(_ p: Analytics.HeldPoint) -> some View {
        HStack(spacing: 10) {
            VStack(alignment: .leading, spacing: 2) {
                Text(p.name).font(.geist(14, .semibold)).foregroundStyle(.white).lineLimit(1)
                Text("Held \(p.days) days · \(Format.money(p.value))").font(.geist(12)).monospacedDigit().foregroundStyle(Theme.muted)
            }
            Spacer(minLength: 8)
            DeltaPill(ratio: p.ret, size: 13)
        }
        .padding(12)
        .background(RoundedRectangle(cornerRadius: 12, style: .continuous).fill(Color.white.opacity(0.06)))
        .transition(.opacity)
    }
}

/// Value by product type (inside Breakdown): one thin bar per row.
private struct TypeBreakdown: View {
    var groups: [Analytics.Group]

    var body: some View {
        if !groups.isEmpty {
            let total = max(groups.reduce(0) { $0 + $1.value }, 1)
            let maxValue = max(groups.map(\.value).max() ?? 1, 1)
            VStack(spacing: 0) {
                ForEach(Array(groups.enumerated()), id: \.element.id) { i, g in
                    BreakdownRow(title: g.name, count: g.count, value: g.value, ret: g.ret,
                                 line: "\(Int((g.value / total * 100).rounded()))% of value · paid \(Format.money(g.cost))",
                                 fraction: g.value / maxValue, delay: Double(i) * 0.06)
                    if g.id != groups.last?.id { Rectangle().fill(Theme.border).frame(height: 1) }
                }
            }
        }
    }
}

/// How spread out the value is: the top five holdings' shares and the "effective" count.
private struct Diversification: View {
    var c: Analytics.Concentration
    var holdings: [HoldingView]

    var body: some View {
        let top = Array(holdings.filter { ($0.value ?? 0) > 0 }.sorted { ($0.value ?? 0) > ($1.value ?? 0) }.prefix(5))
        let total = holdings.reduce(0) { $0 + ($1.value ?? 0) }
        if total > 0 {
            let effective = max(1, Int(c.effective.rounded()))
            let label = c.top1 > 0.4 ? "Concentrated" : c.top5 > 0.75 ? "Top-heavy" : "Well spread"
            VStack(alignment: .leading, spacing: 16) {
                MoreHeading(title: "Diversification", subtitle: nil)
                VStack(alignment: .leading, spacing: 14) {
                    HStack(alignment: .center, spacing: 14) {
                        CountingText(value: Double(effective), format: { "\(Int($0.rounded()))" })
                            // Lighter tracking and a little room on the right: tight tracking shaved the
                            // last digit's edge.
                            .font(.display(54)).tracking(-1.2).monospacedDigit().foregroundStyle(Theme.lime).displayTrim(54)
                            .fixedSize().padding(.trailing, 4)
                        VStack(alignment: .leading, spacing: 3) {
                            Text(label).font(.geist(15, .semibold)).foregroundStyle(.white)
                            Text("Your \(holdings.count) holdings act like \(effective) of equal\u{00A0}size").font(.geist(13)).foregroundStyle(Theme.muted)
                        }
                    }
                    // The top five's shares side by side, sweeping in from the left.
                    GeometryReader { geo in
                        HStack(spacing: 2) {
                            ForEach(Array(top.enumerated()), id: \.offset) { i, h in
                                Rectangle().fill(Theme.planBlue.opacity(0.95 - Double(i) * 0.15))
                                    .frame(width: max(4, geo.size.width * (h.value ?? 0) / total - 2))
                            }
                            Spacer(minLength: 0)
                        }
                        .background(Theme.surface2)
                        .clipShape(Capsule())
                    }
                    .frame(height: 12)
                    .drawIn(duration: 1.0)
                    ForEach(Array(top.enumerated()), id: \.offset) { i, h in
                        CardLink(productId: h.identity.productId, identity: h.identity) {
                            HStack(spacing: 10) {
                                RoundedRectangle(cornerRadius: 3).fill(Theme.planBlue.opacity(0.95 - Double(i) * 0.15)).frame(width: 10, height: 10)
                                Text(h.product?.name ?? "Unknown").font(.geist(13)).lineLimit(1)
                                Spacer(minLength: 8)
                                Text(percent((h.value ?? 0) / total, 1)).font(.geist(13, .semibold)).monospacedDigit()
                            }
                        }
                        .buttonStyle(.plain)
                    }
                    Rectangle().fill(Theme.border).frame(height: 1)
                    HStack {
                        stat("Top holding", c.top1)
                        stat("Top 5", c.top5)
                    }
                }
                .surface(radius: 16, padding: 16)
            }
        }
    }

    private func stat(_ label: String, _ value: Double) -> some View {
        VStack(alignment: .leading, spacing: 4) {
            MonoLabel(text: label, color: Theme.subtle)
            CountingText(value: value, format: { percent($0, 0) }).font(.display(22)).tracking(-0.6).monospacedDigit().displayTrim(22)
        }
        .frame(maxWidth: .infinity, alignment: .leading)
    }
}

/// Each holding as a tile, sized by value and tinted by its return (lime up, pink down), like
/// the website's collection map. Tap a tile to open it.
private struct CollectionMap: View {
    var holdings: [HoldingView]

    /// Gains this big show at full strength; losses (which stop at −100%) at −50%.
    private static let gainCap = 2.0
    private static let lossCap = 0.5

    var body: some View {
        let items = Array(holdings.filter { ($0.value ?? 0) > 0 }.sorted { ($0.value ?? 0) > ($1.value ?? 0) }.prefix(40))
        if !items.isEmpty {
            VStack(alignment: .leading, spacing: 16) {
                VStack(alignment: .trailing, spacing: 12) {
                    GeometryReader { geo in
                        let rects = Treemap.squarify(items.map { $0.value ?? 0 }, in: CGRect(origin: .zero, size: geo.size))
                        ZStack(alignment: .topLeading) {
                            ForEach(Array(zip(items, rects).enumerated()), id: \.offset) { i, pair in
                                let (h, r) = pair
                                CardLink(productId: h.identity.productId, identity: h.identity) { tile(h, size: r.size) }
                                    .buttonStyle(.plain)
                                    .frame(width: max(0, r.width - 3), height: max(0, r.height - 3))
                                    .offset(x: r.minX, y: r.minY)
                                    .popIn(delay: Double(min(i, 20)) * 0.025)
                            }
                        }
                    }
                    .frame(height: 360)
                    HStack(spacing: 8) {
                        Text("−50%").font(.geist(11)).monospacedDigit().foregroundStyle(Theme.subtle)
                        Capsule()
                            .fill(LinearGradient(colors: [Self.heat(-Self.lossCap), Self.heat(0), Self.heat(Self.gainCap)], startPoint: .leading, endPoint: .trailing))
                            .frame(maxWidth: .infinity).frame(height: 8)
                        Text("+200%").font(.geist(11)).monospacedDigit().foregroundStyle(Theme.subtle)
                    }
                }
                .padding(.top, 4)
            }
        }
    }

    private func tile(_ h: HoldingView, size: CGSize) -> some View {
        // Text only where it fits whole: small tiles stay plain (tap to open), so no names split
        // mid-word and no prices cut down to a lone "$".
        let showName = size.width >= 96 && size.height >= 52
        let showValue = size.width >= 124 && size.height >= 84
        return RoundedRectangle(cornerRadius: 6, style: .continuous)
            .fill(h.gainRatio.map { Self.heat($0) } ?? Theme.surface2)
            .overlay(alignment: .topLeading) {
                if showName {
                    VStack(alignment: .leading, spacing: 0) {
                        Text(h.product?.name ?? "Unknown").font(.geist(12, .medium)).lineLimit(2).truncationMode(.tail)
                            .minimumScaleFactor(0.9)
                        Spacer(minLength: 0)
                        if showValue {
                            HStack(spacing: 6) {
                                Text(Format.money(h.value)).font(.geist(12, .semibold)).monospacedDigit().fixedSize()
                                DeltaPill(ratio: h.gainRatio, size: 10)
                            }
                            .lineLimit(1)
                        }
                    }
                    .foregroundStyle(.white)
                    .padding(8)
                }
            }
            .contentShape(Rectangle())
    }

    /// The website's mapHeat: up or down mixed into the dark surface, stronger for bigger
    /// moves (square root, so small moves still show).
    static func heat(_ ret: Double) -> Color {
        let cap = ret >= 0 ? gainCap : lossCap
        let t = min(1, abs(ret) / cap).squareRoot()
        let strength = 0.08 + t * (0.5 - 0.08)
        let target: (Double, Double, Double) = ret >= 0 ? (0xD4, 0xFF, 0x3A) : (0xFF, 0x3D, 0x7F)
        let base: (Double, Double, Double) = (0x1A, 0x1A, 0x1D)
        func mix(_ a: Double, _ b: Double) -> Double { (b + (a - b) * strength) / 255 }
        return Color(red: mix(target.0, base.0), green: mix(target.1, base.1), blue: mix(target.2, base.2))
    }
}

/// Squarified treemap layout: rectangles for values (largest first), as square as possible.
enum Treemap {
    static func squarify(_ values: [Double], in rect: CGRect) -> [CGRect] {
        let total = values.reduce(0, +)
        guard total > 0, rect.width > 0, rect.height > 0 else { return values.map { _ in .zero } }
        let scale = Double(rect.width * rect.height) / total
        var areas = values.map { $0 * scale }[...]
        var out: [CGRect] = []
        var r = rect
        func worst(_ row: [Double], _ side: Double) -> Double {
            let sum = row.reduce(0, +)
            guard let mx = row.max(), let mn = row.min(), sum > 0, mn > 0 else { return .infinity }
            return max(side * side * mx / (sum * sum), sum * sum / (side * side * mn))
        }
        while !areas.isEmpty {
            let side = Double(min(r.width, r.height))
            var row: [Double] = []
            for a in areas {
                if row.isEmpty || worst(row + [a], side) <= worst(row, side) { row.append(a) } else { break }
            }
            areas = areas.dropFirst(row.count)
            let sum = row.reduce(0, +)
            if r.width >= r.height {
                // A column down the left.
                let w = CGFloat(sum / Double(r.height))
                var y = r.minY
                for a in row {
                    let h = CGFloat(a) / w
                    out.append(CGRect(x: r.minX, y: y, width: w, height: h))
                    y += h
                }
                r = CGRect(x: r.minX + w, y: r.minY, width: max(0, r.width - w), height: r.height)
            } else {
                // A row along the top.
                let h = CGFloat(sum / Double(r.width))
                var x = r.minX
                for a in row {
                    let w = CGFloat(a) / h
                    out.append(CGRect(x: x, y: r.minY, width: w, height: h))
                    x += w
                }
                r = CGRect(x: r.minX, y: r.minY + h, width: r.width, height: max(0, r.height - h))
            }
        }
        return out
    }
}

/// The rarer measures, closed until you open them: how often the market moved your way and
/// how much the value swings.
private struct AdvancedStats: View {
    var risk: Analytics.Risk
    var points: [Analytics.HeldPoint]
    @State private var open = false

    var body: some View {
        VStack(alignment: .leading, spacing: 14) {
            Button {
                Haptics.tap()
                withAnimation(.snappy(duration: 0.25)) { open.toggle() }
            } label: {
                HStack {
                    MoreHeading(title: "Advanced", subtitle: "Time held, up days and volatility")
                    Image(systemName: "chevron.down").font(.system(size: 14, weight: .semibold)).foregroundStyle(Theme.muted)
                        .rotationEffect(.degrees(open ? 180 : 0))
                }
                .contentShape(Rectangle())
            }
            .buttonStyle(.plain)
            if open {
                VStack(spacing: 12) {
                    ReturnVsTime(points: points)
                    row("Up days", risk.upDays.map { "\(Int(($0 * 100).rounded()))%" } ?? "—",
                        "The share of days your collection's market value went up.")
                    row("Volatility", risk.volatility.map { "\(Int(($0 * 100).rounded()))%" } ?? "—",
                        "How much the value swings, scaled to a year. Higher means bumpier.")
                }
                .transition(.opacity)
            }
        }
    }

    private func row(_ title: String, _ value: String, _ note: String) -> some View {
        HStack(alignment: .top, spacing: 12) {
            VStack(alignment: .leading, spacing: 3) {
                Text(title).font(.geist(15, .semibold)).foregroundStyle(.white)
                Text(note).font(.geist(12)).foregroundStyle(Theme.muted).fixedSize(horizontal: false, vertical: true)
            }
            Spacer(minLength: 8)
            Text(value).font(.display(22)).monospacedDigit().foregroundStyle(.white)
        }
        .surface(radius: 16, padding: 14)
    }
}
