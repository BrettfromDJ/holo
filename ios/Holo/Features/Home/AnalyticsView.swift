import Charts
import SwiftUI

/// How the collection is allocated and how it has performed, like the website's Analytics page.
/// Percentages are time-weighted: buying and selling never count as performance.
struct AnalyticsView: View {
    @Environment(CollectionStore.self) private var store
    @State private var range = Span.year
    @State private var mode = Mode.value
    @State private var setSort = SetSort.value
    @State private var rankBy = RankBy.dollar
    @State private var scrubbed: Date?

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
            VStack(alignment: .leading, spacing: 40) {
                ValueLineHero(label: "Total return", value: total, points: timeline) {
                    VStack(alignment: .leading, spacing: 14) {
                        if s.totalCost > 0 {
                            HStack(spacing: 8) {
                                DeltaPill(ratio: total / s.totalCost, size: 13)
                                Text("on \(Format.money(s.totalCost)) invested").font(.geist(14)).foregroundStyle(Theme.muted)
                            }
                        }
                        NavigationLink(value: MorePage.gains) {
                            Label("Where it comes from", systemImage: "chart.bar.xaxis").lineLimit(1)
                        }
                        .buttonStyle(Button3D(kind: .dark, fullWidth: false, height: 40))
                    }
                }
                kpis(risk: risk, summary: s, holdings: holdings)
                history(timeline).reveal()
                CollectionMap(holdings: holdings).reveal()
                MonthlyHeatmap(months: Analytics.monthlyReturns(timeline)).reveal()
                ReturnVsTime(points: Analytics.returnVsTime(holdings, today: today)).reveal()
                TypeBreakdown(groups: Analytics.byType(holdings)).reveal()
                Diversification(c: Analytics.concentration(holdings), holdings: holdings).reveal()
                VStack(alignment: .leading, spacing: 16) {
                    MoreHeading(title: "Allocation", subtitle: "Exposure by market value")
                    AllocationBar(holdings: holdings, total: s.value)
                }
                .reveal()
                activity.reveal()
                sets(holdings).reveal()
                rank("Best investments", best: true, holdings: holdings, empty: "No holdings are in profit yet.").reveal()
                rank("Underperformers", best: false, holdings: holdings, empty: "Nothing is below cost. Nice.").reveal()
                Text("Performance percentages are time-weighted: daily market returns are chained so that purchases and sales never count as gains. History starts \(timeline.first.map { $0.day.formatted(date: .abbreviated, time: .omitted) } ?? "—").")
                    .font(.geist(12)).foregroundStyle(Theme.subtle)
            }
            .padding(.horizontal, 16)
            .padding(.bottom, 120)
        }
        .background(Theme.background)
        .replaysAnimations()
        .navigationBarTitleDisplayMode(.inline)
        .pageTitle("Analytics")
    }

    // MARK: Key numbers

    private func kpis(risk: Analytics.Risk, summary s: PortfolioSummary, holdings: [HoldingView]) -> some View {
        let priced = holdings.filter { $0.gain != nil }
        let winRate = priced.isEmpty ? nil : Double(priced.filter { ($0.gain ?? 0) > 0 }.count) / Double(priced.count)
        let sales = store.portfolioTransactions.filter { $0.kind == .sale }.count
        let short = { (d: String?) in d.flatMap { Format.isoDay.date(from: $0)?.formatted(.dateTime.month(.abbreviated).day()) } ?? "—" }
        let glow = { (v: Double?) in (v ?? 0) < 0 ? Theme.planPink : Theme.lime }
        return LazyVGrid(columns: [GridItem(.flexible(), spacing: 12), GridItem(.flexible(), spacing: 12)], spacing: 12) {
            CountTile(label: "Time-weighted", value: risk.totalReturn, format: { Format.signedPercent($0) }, valueTint: Theme.tone(risk.totalReturn),
                      sub: risk.annualized.map { "\(Format.signedPercent($0)) a year" } ?? "Market moves only", glow: glow(risk.totalReturn))
                .popIn(delay: 0.05)
            CountTile(label: "Max drawdown", value: risk.maxDrawdown, format: { percent($0, 1) }, valueTint: Theme.tone(risk.maxDrawdown),
                      sub: risk.maxDrawdownTo != nil ? "\(short(risk.maxDrawdownFrom)) → \(short(risk.maxDrawdownTo))" : "No dips yet", glow: Theme.planPink)
                .popIn(delay: 0.1)
            CountTile(label: "Best day", value: risk.bestDay?.gain, format: { Format.signedMoney($0) }, valueTint: Theme.tone(risk.bestDay?.gain),
                      sub: short(risk.bestDay?.date), glow: Theme.lime)
                .popIn(delay: 0.15)
            CountTile(label: "Worst day", value: risk.worstDay?.gain, format: { Format.signedMoney($0) }, valueTint: Theme.tone(risk.worstDay?.gain),
                      sub: short(risk.worstDay?.date), glow: Theme.planPink)
                .popIn(delay: 0.2)
            CountTile(label: "In profit", value: winRate, format: { percent($0, 0) }, sub: "of \(holdings.count) holdings", glow: Theme.planBlue)
                .popIn(delay: 0.25)
            CountTile(label: "Up days", value: risk.upDays, format: { percent($0, 0) }, sub: "Days the market moved your way", glow: Theme.planBlue)
                .popIn(delay: 0.3)
            CountTile(label: "Volatility", value: risk.volatility, format: { percent($0, 0) }, sub: "Annualized swing in value", glow: Theme.planBlue)
                .popIn(delay: 0.35)
            CountTile(label: "Realized", value: s.realized, format: { Format.signedMoney($0) }, valueTint: Theme.tone(s.realized),
                      sub: "\(sales) sale\(sales == 1 ? "" : "s") & write-offs", glow: glow(s.realized))
                .popIn(delay: 0.4)
        }
    }

    // MARK: Portfolio history

    private func history(_ timeline: [TimelinePoint]) -> some View {
        let slice: [TimelinePoint] = {
            guard let days = range.days, let start = Calendar.current.date(byAdding: .day, value: -days, to: Date()) else { return timeline }
            let from = Format.day(start)
            let s = timeline.filter { $0.date >= from }
            return s.isEmpty ? Array(timeline.suffix(1)) : s
        }()
        let base = slice.first?.twrIndex ?? 1
        let dd = Analytics.drawdowns(slice)
        let rets = slice.map { base > 0 ? $0.twrIndex / base - 1 : 0 }
        let gain = slice.dropFirst().reduce(0) { $0 + $1.marketGain }
        let twr = rets.last ?? 0
        let shownIndex = scrubbed.flatMap { d in slice.firstIndex { Calendar.current.isDate($0.day, inSameDayAs: d) } }
        return VStack(alignment: .leading, spacing: 16) {
            HStack(alignment: .center) {
                MoreHeading(title: "Portfolio history", subtitle: nil)
                Menu {
                    Picker("Range", selection: $range) {
                        ForEach(Span.allCases, id: \.self) { Text($0.rawValue).tag($0) }
                    }
                } label: {
                    HStack(spacing: 5) {
                        Text(range.rawValue).font(.geist(14, .semibold))
                        Image(systemName: "chevron.down").font(.system(size: 10, weight: .bold))
                    }
                    .foregroundStyle(.white)
                    .padding(.horizontal, 14).frame(height: 36)
                    .liquidGlass(in: Capsule())
                }
            }
            // What the chart says, or the day under your finger.
            Group {
                if let i = shownIndex {
                    let p = slice[i]
                    HStack(spacing: 6) {
                        switch mode {
                        case .value: Text(Format.money(p.value)).foregroundStyle(.white)
                        case .ret: Text(Format.signedPercent(rets[i])).foregroundStyle(Theme.tone(rets[i]))
                        case .drawdown: Text(percent(dd[i], 1)).foregroundStyle(Theme.tone(dd[i]))
                        }
                        Text(p.day.formatted(date: .abbreviated, time: .omitted)).foregroundStyle(Theme.muted)
                    }
                } else {
                    HStack(spacing: 6) {
                        Text(Format.signedMoney(gain)).foregroundStyle(Theme.tone(gain))
                        Text("(\(Format.signedPercent(twr)))").foregroundStyle(Theme.tone(twr))
                        Text(range.phrase).foregroundStyle(Theme.muted)
                    }
                }
            }
            .font(.geist(15, .medium)).monospacedDigit().lineLimit(1).minimumScaleFactor(0.8)

            VStack(alignment: .leading, spacing: 14) {
                ChipPicker(options: Mode.allCases.map { ($0, $0.rawValue) }, selection: $mode)
                if slice.count > 1 {
                    chart(slice, rets: rets, dd: dd, shownIndex: shownIndex)
                    Text(caption).font(.geist(12)).foregroundStyle(Theme.muted)
                } else {
                    Text("Not enough history yet.").font(.geist(14)).foregroundStyle(Theme.muted).padding(.vertical, 40).frame(maxWidth: .infinity)
                }
            }
            .surface(radius: 16, padding: 16)
        }
    }

    private var caption: String {
        switch mode {
        case .value: return "White: market value. Dashed: what the priced items cost. Drag to see a day."
        case .ret: return "Time-weighted return: market moves only, so buying and selling don't count."
        case .drawdown: return "How far below its previous high the collection's return has been. 0% is a new high."
        }
    }

    @ViewBuilder
    private func chart(_ slice: [TimelinePoint], rets: [Double], dd: [Double], shownIndex: Int?) -> some View {
        let values: [Double] = mode == .value ? slice.map(\.value) : mode == .ret ? rets : dd
        let tint: Color = mode == .value ? Theme.lime : mode == .drawdown ? Theme.down : (rets.last ?? 0) >= 0 ? Theme.up : Theme.down
        let domain: ClosedRange<Double> = {
            if mode == .value { return ChartTicks.domain(slice.map(\.value) + slice.map(\.cost)) }
            let lo = min(values.min() ?? 0, 0)
            let hi = max(values.max() ?? 0, 0)
            let pad = max((hi - lo) * 0.12, 0.01)
            return (lo - pad)...(mode == .drawdown ? pad : hi + pad)
        }()
        Chart {
            if mode != .value { RuleMark(y: .value("Zero", 0)).foregroundStyle(Theme.borderStrong) }
            ForEach(Array(slice.enumerated()), id: \.offset) { i, p in
                if mode == .value {
                    LineMark(x: .value("Day", p.day), y: .value("Cost", p.cost), series: .value("Line", "Cost"))
                        .foregroundStyle(Theme.subtle).lineStyle(StrokeStyle(lineWidth: 1.5, dash: [4, 4]))
                }
                AreaMark(x: .value("Day", p.day), yStart: .value("Base", mode == .value ? domain.lowerBound : 0), yEnd: .value("Y", values[i]))
                    .foregroundStyle(LinearGradient(colors: [tint.opacity(0.28), tint.opacity(0)], startPoint: mode == .drawdown ? .bottom : .top, endPoint: mode == .drawdown ? .top : .bottom))
                    .interpolationMethod(.monotone)
                LineMark(x: .value("Day", p.day), y: .value("Y", values[i]), series: .value("Line", "Main"))
                    .foregroundStyle(tint).lineStyle(StrokeStyle(lineWidth: 2.5)).interpolationMethod(.monotone)
            }
            if let i = shownIndex {
                RuleMark(x: .value("Day", slice[i].day)).foregroundStyle(.white.opacity(0.3))
                PointMark(x: .value("Day", slice[i].day), y: .value("Y", values[i])).foregroundStyle(tint).symbolSize(80)
            }
        }
        .chartXAxis(.hidden)
        .chartYScale(domain: domain)
        // Labels inside the plot, so the line runs to the right edge.
        .insideYAxis(label: { mode == .value ? ChartTicks.label($0) : percent($0, 0) })
        .chartXSelection(value: $scrubbed)
        .frame(height: 240)
        .drawIn(replay: "\(mode.rawValue)\(range.rawValue)")
        .sensoryFeedback(.selection, trigger: shownIndex)
    }

    // MARK: Investment activity

    private var activity: some View {
        let months = Array(Analytics.monthlyActivity(store.portfolioTransactions, today: today).suffix(12))
        let biggest = months.max { $0.invested < $1.invested }
        return VStack(alignment: .leading, spacing: 16) {
            MoreHeading(title: "Investment activity", subtitle: "Money invested per month, incl. fees")
            VStack(alignment: .leading, spacing: 12) {
                if let biggest, biggest.invested > 0 {
                    (Text("Biggest month: ").foregroundColor(Theme.muted)
                     + Text(biggest.date.formatted(.dateTime.month(.wide).year())).foregroundColor(.white)
                     + Text(" · ").foregroundColor(Theme.muted)
                     + Text(Format.money(biggest.invested)).foregroundColor(.white))
                        .font(.geist(13, .medium)).monospacedDigit()
                }
                GrowingBars(months: months, highlight: biggest?.month)
            }
            .surface(radius: 16, padding: 16)
        }
    }

    // MARK: Sets

    private func sets(_ holdings: [HoldingView]) -> some View {
        let rows = setSort == .value ? Analytics.bySet(holdings) : Analytics.bySet(holdings).sorted { ($0.ret ?? -.infinity) > ($1.ret ?? -.infinity) }
        let maxShare = max(rows.map(\.share).max() ?? 0, 0.0001)
        return VStack(alignment: .leading, spacing: 16) {
            MoreHeading(title: "Performance by set", subtitle: "Share of your value, and how each set has done")
            ChipPicker(options: [(SetSort.value, "By value"), (.ret, "By return")], selection: $setSort)
            VStack(spacing: 0) {
                ForEach(Array(rows.enumerated()), id: \.element.id) { i, r in
                    VStack(alignment: .leading, spacing: 8) {
                        HStack(alignment: .firstTextBaseline) {
                            VStack(alignment: .leading, spacing: 2) {
                                Text(r.name).font(.geist(14, .medium)).lineLimit(1)
                                Text("\(r.holdings) holding\(r.holdings == 1 ? "" : "s") · \(percent(r.share, 0)) of value").font(.geist(12)).foregroundStyle(Theme.muted)
                            }
                            Spacer(minLength: 8)
                            VStack(alignment: .trailing, spacing: 2) {
                                Text(Format.money(r.value)).font(.geist(14, .semibold)).monospacedDigit()
                                Text("\(Format.signedMoney(r.gain)) · \(Format.signedPercent(r.ret))").font(.geist(12)).monospacedDigit().foregroundStyle(Theme.tone(r.gain))
                            }
                        }
                        GrowBar(fraction: r.share / maxShare, color: (r.ret ?? 0) < 0 ? Theme.planPink : Theme.planBlue, height: 6, delay: Double(min(i, 8)) * 0.05)
                    }
                    .padding(.vertical, 12)
                    if r.id != rows.last?.id { Rectangle().fill(Theme.border).frame(height: 1) }
                }
            }
            .surface(radius: 16, padding: 16)
        }
    }

    // MARK: Best and worst

    private func rank(_ heading: String, best: Bool, holdings: [HoldingView], empty: String) -> some View {
        let key = { (h: HoldingView) in rankBy == .dollar ? (h.gain ?? 0) : (h.gainRatio ?? 0) }
        let priced = holdings.filter { $0.gain != nil }
        let items = best
            ? Array(priced.filter { ($0.gain ?? 0) > 0 }.sorted { key($0) > key($1) }.prefix(5))
            : Array(priced.filter { ($0.gain ?? 0) < 0 }.sorted { key($0) < key($1) }.prefix(5))
        return VStack(alignment: .leading, spacing: 16) {
            HStack(alignment: .center) {
                MoreHeading(title: heading, subtitle: nil)
                ChipPicker(options: [(RankBy.dollar, "$"), (.percent, "%")], selection: $rankBy).fixedSize()
            }
            VStack(spacing: 0) {
                if items.isEmpty {
                    Text(empty).font(.geist(14)).foregroundStyle(Theme.muted).padding(.vertical, 8).frame(maxWidth: .infinity, alignment: .leading)
                }
                ForEach(Array(items.enumerated()), id: \.element.id) { i, h in
                    NavigationLink(value: h.identity.productId) {
                        HStack(spacing: 10) {
                            Text(String(format: "%02d", i + 1)).font(.mono(12)).foregroundStyle(Theme.subtle).frame(width: 20)
                            MiniRow(holding: h, trailing: rankBy == .dollar ? Format.signedMoney(h.gain) : Format.signedPercent(h.gainRatio), tint: Theme.tone(h.gain))
                        }
                        .padding(.vertical, 8)
                    }
                    .buttonStyle(.plain)
                    .popIn(delay: Double(i) * 0.06)
                }
            }
            .surface(radius: 16, padding: 14)
        }
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
                .foregroundStyle(m.month == highlight ? Theme.lime : Theme.planBlue)
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
            VStack(alignment: .leading, spacing: 16) {
                MoreHeading(title: "Monthly returns", subtitle: "\(positive) of \(months.count) months up")
                HStack(spacing: 10) {
                    extreme("Best", best)
                    extreme("Worst", worst)
                }
                VStack(alignment: .leading, spacing: 18) {
                    ForEach(years, id: \.self) { y in
                        let row = months.filter { $0.year == y }
                        let yearRet = row.reduce(1.0) { $0 * (1 + $1.ret) } - 1
                        VStack(alignment: .leading, spacing: 8) {
                            HStack {
                                Text(String(y)).font(.display(20)).displayTrim(20)
                                Spacer()
                                DeltaPill(ratio: yearRet, size: 12)
                            }
                            LazyVGrid(columns: Array(repeating: GridItem(.flexible(), spacing: 5), count: 6), spacing: 5) {
                                ForEach(0..<12, id: \.self) { i in
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
            Text(Format.signedPercent(m.ret)).font(.display(24)).monospacedDigit().foregroundStyle(Theme.tone(m.ret)).displayTrim(24)
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

    var body: some View {
        if !points.isEmpty {
            let avg = Analytics.averageHoldDays(points)
            VStack(alignment: .leading, spacing: 16) {
                MoreHeading(title: "Return vs. time held", subtitle: "Each dot is a holding, sized by value")
                VStack(alignment: .leading, spacing: 12) {
                    if let avg {
                        HStack(alignment: .firstTextBaseline, spacing: 6) {
                            CountingText(value: avg, format: { "\(Int($0.rounded()))" })
                                .font(.display(34)).monospacedDigit().displayTrim(34)
                            Text("days, average hold").font(.geist(14)).foregroundStyle(Theme.muted)
                        }
                    }
                    // Room around the edges so the biggest dots and the axis labels aren't cut off.
                    let maxDays = Double(points.map(\.days).max() ?? 1)
                    let lo = min(points.map(\.ret).min() ?? 0, 0)
                    let hi = max(points.map(\.ret).max() ?? 0, 0)
                    let pad = max((hi - lo) * 0.18, 0.1)
                    Chart(points) { p in
                        PointMark(x: .value("Days held", Double(p.days)), y: .value("Return", p.ret))
                            .foregroundStyle((p.ret >= 0 ? Theme.up : Theme.down).opacity(0.85))
                            .symbolSize(30 + min(260, p.value / 4))
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
                    .frame(height: 220)
                    .drawIn(duration: 1.0)
                }
                .surface(radius: 16, padding: 16)
            }
        }
    }
}

/// Value by product type, with what you paid as a faint bar over it so the gap is the gain.
private struct TypeBreakdown: View {
    var groups: [Analytics.Group]

    var body: some View {
        if !groups.isEmpty {
            let top = max(groups.map(\.value).max() ?? 1, 1)
            VStack(alignment: .leading, spacing: 16) {
                MoreHeading(title: "By product type", subtitle: "Where the value sits, and how each type has done")
                VStack(alignment: .leading, spacing: 16) {
                    ForEach(Array(groups.enumerated()), id: \.element.id) { i, g in
                        VStack(alignment: .leading, spacing: 7) {
                            HStack(alignment: .firstTextBaseline) {
                                (Text(g.name).font(.geist(14, .medium)) + Text("  ×\(g.count)").font(.geist(12)).foregroundColor(Theme.subtle)).lineLimit(1)
                                Spacer(minLength: 8)
                                Text(Format.money(g.value)).font(.geist(14, .semibold)).monospacedDigit()
                                Text(Format.signedPercent(g.ret)).font(.geist(12)).monospacedDigit().foregroundStyle(Theme.tone(g.ret))
                            }
                            GrowBar(fraction: g.value / top, color: (g.ret ?? 0) < 0 ? Theme.planPink : Theme.planBlue, height: 9, delay: Double(i) * 0.06)
                                .overlay(alignment: .leading) {
                                    GeometryReader { geo in
                                        Capsule().strokeBorder(Color.white.opacity(0.55), style: StrokeStyle(lineWidth: 1, dash: [3, 3]))
                                            .frame(width: max(9, geo.size.width * min(g.cost, top) / top))
                                    }
                                }
                        }
                    }
                    Text("Bar: what it's worth. Dashed outline: what you paid.").font(.geist(12)).foregroundStyle(Theme.subtle)
                }
                .surface(radius: 16, padding: 16)
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
                            .font(.display(54)).monospacedDigit().foregroundStyle(Theme.lime).displayTrim(54)
                        VStack(alignment: .leading, spacing: 4) {
                            SkewTag(text: label.uppercased(), color: Theme.planBlue, textColor: .white)
                            Text("Your \(holdings.count) holdings behave like \(effective) equally sized ones").font(.geist(13)).foregroundStyle(Theme.muted)
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
                        NavigationLink(value: h.identity.productId) {
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
            CountingText(value: value, format: { percent($0, 0) }).font(.display(22)).monospacedDigit().displayTrim(22)
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
                MoreHeading(title: "Collection map", subtitle: "Each tile is a holding, sized by value and tinted by its return. Tap one to open it.")
                VStack(alignment: .trailing, spacing: 12) {
                    GeometryReader { geo in
                        let rects = Treemap.squarify(items.map { $0.value ?? 0 }, in: CGRect(origin: .zero, size: geo.size))
                        ZStack(alignment: .topLeading) {
                            ForEach(Array(zip(items, rects).enumerated()), id: \.offset) { i, pair in
                                let (h, r) = pair
                                NavigationLink(value: h.identity.productId) { tile(h, size: r.size) }
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
                            .frame(width: 120, height: 8)
                        Text("+200%").font(.geist(11)).monospacedDigit().foregroundStyle(Theme.subtle)
                    }
                }
                .surface(radius: 16, padding: 14)
            }
        }
    }

    private func tile(_ h: HoldingView, size: CGSize) -> some View {
        let showName = size.width > 70 && size.height > 40
        let showValue = size.width > 70 && size.height > 60
        return RoundedRectangle(cornerRadius: 6, style: .continuous)
            .fill(h.gainRatio.map { Self.heat($0) } ?? Theme.surface2)
            .overlay(alignment: .topLeading) {
                if showName {
                    VStack(alignment: .leading, spacing: 0) {
                        Text(h.product?.name ?? "Unknown").font(.geist(12, .medium)).lineLimit(2)
                        Spacer(minLength: 0)
                        if showValue {
                            HStack(spacing: 6) {
                                Text(Format.money(h.value)).font(.geist(12, .semibold)).monospacedDigit()
                                Text(Format.signedPercent(h.gainRatio)).font(.geist(11)).monospacedDigit().opacity(0.8)
                            }
                            .lineLimit(1).minimumScaleFactor(0.7)
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
