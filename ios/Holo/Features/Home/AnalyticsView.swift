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
        ScrollView {
            VStack(alignment: .leading, spacing: 20) {
                PageHeader(title: "Analytics", subtitle: "How your collection is allocated and how it has performed.")
                NavigationLink { GainsView() } label: {
                    Text("Gains breakdown →").font(.geist(14, .medium)).foregroundStyle(Theme.muted)
                }
                .buttonStyle(.plain)

                kpis(risk: risk, summary: s, holdings: holdings)
                history(timeline)
                MonthlyHeatmap(months: Analytics.monthlyReturns(timeline))
                ReturnVsTime(points: Analytics.returnVsTime(holdings, today: today))
                TypeBreakdown(groups: Analytics.byType(holdings))
                Diversification(c: Analytics.concentration(holdings), holdings: holdings)
                VStack(alignment: .leading, spacing: 14) {
                    title("Allocation", "Exposure by market value")
                    AllocationBar(holdings: holdings, total: s.value)
                }
                .surface(radius: 22, padding: 18)
                activity
                sets(holdings)
                rank("Best investments", best: true, holdings: holdings, empty: "No holdings are in profit yet.")
                rank("Underperformers", best: false, holdings: holdings, empty: "Nothing is below cost. Nice.")
                Text("Performance percentages are time-weighted: daily market returns are chained so that purchases and sales never count as gains. History starts \(timeline.first.map { $0.day.formatted(date: .abbreviated, time: .omitted) } ?? "—").")
                    .font(.geist(12)).foregroundStyle(Theme.subtle)
            }
            .padding(.horizontal, 16)
            .padding(.bottom, 120)
        }
        .background(Theme.background)
        .navigationBarTitleDisplayMode(.inline)
        .pageTitle("Analytics")
    }

    // MARK: KPIs

    private func kpis(risk: Analytics.Risk, summary s: PortfolioSummary, holdings: [HoldingView]) -> some View {
        let total = s.gain + s.realized
        let priced = holdings.filter { $0.gain != nil }
        let winRate = priced.isEmpty ? nil : Double(priced.filter { ($0.gain ?? 0) > 0 }.count) / Double(priced.count)
        let sales = store.portfolioTransactions.filter { $0.kind == .sale }.count
        let short = { (d: String?) in d.flatMap { Format.isoDay.date(from: $0)?.formatted(.dateTime.month(.abbreviated).day()) } ?? "—" }
        let items: [(String, String, Color, String, Color)] = [
            ("Total return", Format.signedMoney(total), Theme.tone(total), s.totalCost > 0 ? "\(Format.signedPercent(total / s.totalCost)) on \(Format.money(s.totalCost)) invested" : "—", Theme.lime),
            ("Time-weighted", Format.signedPercent(risk.totalReturn), Theme.tone(risk.totalReturn), risk.annualized.map { "\(Format.signedPercent($0)) a year" } ?? "Market moves only", Theme.planBlue),
            ("Max drawdown", percent(risk.maxDrawdown, 1), Theme.tone(risk.maxDrawdown), risk.maxDrawdownTo != nil ? "\(short(risk.maxDrawdownFrom)) → \(short(risk.maxDrawdownTo))" : "No dips yet", Theme.planPink),
            ("Volatility", risk.volatility.map { percent($0, 0) } ?? "—", .white, "Annualized swing in value", Theme.planBlue),
            ("Best day", Format.signedMoney(risk.bestDay?.gain), Theme.tone(risk.bestDay?.gain), short(risk.bestDay?.date), Theme.lime),
            ("Worst day", Format.signedMoney(risk.worstDay?.gain), Theme.tone(risk.worstDay?.gain), short(risk.worstDay?.date), Theme.planPink),
            ("In profit", winRate.map { percent($0, 0) } ?? "—", .white, "of \(holdings.count) holdings\(risk.upDays.map { " · \(percent($0, 0)) up days" } ?? "")", Theme.planBlue),
            ("Realized", Format.signedMoney(s.realized), Theme.tone(s.realized), "\(sales) sale\(sales == 1 ? "" : "s") & write-offs", Theme.lime),
        ]
        return LazyVGrid(columns: [GridItem(.flexible(), spacing: 12), GridItem(.flexible(), spacing: 12)], spacing: 12) {
            ForEach(items, id: \.0) { label, value, tint, sub, glow in
                VStack(alignment: .leading, spacing: 0) {
                    Text(label.uppercased()).font(.display(14)).tracking(0.3).foregroundStyle(.white.opacity(0.85)).lineLimit(1).displayTrim(14)
                    Text(value).font(.display(26)).monospacedDigit().foregroundStyle(tint).lineLimit(1).minimumScaleFactor(0.6).displayTrim(26).padding(.top, 14)
                    Text(sub).font(.geist(12)).foregroundStyle(Theme.muted).lineLimit(1).minimumScaleFactor(0.85).padding(.top, 8)
                }
                .frame(maxWidth: .infinity, alignment: .leading)
                .tinted(glow, radius: 20, border: false)
            }
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
        let gain = slice.dropFirst().reduce(0) { $0 + $1.marketGain }
        let twr = base > 0 ? (slice.last?.twrIndex ?? base) / base - 1 : 0
        return VStack(alignment: .leading, spacing: 14) {
            VStack(alignment: .leading, spacing: 4) {
                Text("Portfolio history").font(.geist(17, .semibold))
                (Text(Format.signedMoney(gain)).foregroundColor(Theme.tone(gain)) + Text(" (\(Format.signedPercent(twr)))").foregroundColor(Theme.tone(twr)) + Text(" market performance · \(range.phrase)").foregroundColor(Theme.muted))
                    .font(.geist(13)).monospacedDigit()
            }
            ScrollView(.horizontal, showsIndicators: false) {
                HStack(spacing: 8) {
                    ChipPicker(options: Mode.allCases.map { ($0, $0.rawValue) }, selection: $mode)
                    ChipPicker(options: Span.allCases.map { ($0, $0.rawValue) }, selection: $range)
                }
            }
            .scrollClipDisabled()
            if slice.count > 1 {
                switch mode {
                case .value:
                    HStack(spacing: 16) {
                        legend(.white, "Market value", dashed: false)
                        legend(Theme.subtle, "Cost basis (priced holdings)", dashed: true)
                    }
                    let domain = ChartTicks.domain(slice.map(\.value) + slice.map(\.cost))
                    Chart {
                        ForEach(slice) { p in
                            LineMark(x: .value("Day", p.day), y: .value("Cost", p.cost), series: .value("Line", "Cost"))
                                .foregroundStyle(Theme.subtle).lineStyle(StrokeStyle(lineWidth: 1.5, dash: [4, 4]))
                            LineMark(x: .value("Day", p.day), y: .value("Value", p.value), series: .value("Line", "Value"))
                                .foregroundStyle(.white).lineStyle(StrokeStyle(lineWidth: 2)).interpolationMethod(.monotone)
                        }
                    }
                    .chartXAxis(.hidden)
                    .insideYAxis()
                    .chartYScale(domain: domain)
                    .frame(height: 230)
                    Text("Unrealized gain / loss").font(.geist(12, .medium)).foregroundStyle(Theme.muted).padding(.top, 6)
                    let up = (slice.last.map { $0.value - $0.cost } ?? 0) >= 0
                    Chart {
                        RuleMark(y: .value("Zero", 0)).foregroundStyle(Theme.borderStrong)
                        ForEach(slice) { p in
                            AreaMark(x: .value("Day", p.day), y: .value("Gain", p.value - p.cost))
                                .foregroundStyle((up ? Theme.up : Theme.down).opacity(0.18)).interpolationMethod(.monotone)
                            LineMark(x: .value("Day", p.day), y: .value("Gain", p.value - p.cost))
                                .foregroundStyle(up ? Theme.up : Theme.down).lineStyle(StrokeStyle(lineWidth: 1.5)).interpolationMethod(.monotone)
                        }
                    }
                    .chartXAxis(.hidden)
                    .insideYAxis(count: 3)
                    .frame(height: 110)
                case .ret, .drawdown:
                    Text(mode == .ret ? "Time-weighted return over the range: market moves only, so buying and selling don't count." : "How far below its previous high the collection's return has been. 0% is a new high.")
                        .font(.geist(12)).foregroundStyle(Theme.muted)
                    let values = mode == .ret ? slice.map { base > 0 ? $0.twrIndex / base - 1 : 0 } : dd
                    let tint = mode == .drawdown ? Theme.down : (values.last ?? 0) >= 0 ? Theme.up : Theme.down
                    Chart {
                        RuleMark(y: .value("Zero", 0)).foregroundStyle(Theme.borderStrong)
                        ForEach(Array(slice.enumerated()), id: \.offset) { i, p in
                            AreaMark(x: .value("Day", p.day), y: .value("Return", values[i]))
                                .foregroundStyle(tint.opacity(0.18)).interpolationMethod(.monotone)
                            LineMark(x: .value("Day", p.day), y: .value("Return", values[i]))
                                .foregroundStyle(tint).lineStyle(StrokeStyle(lineWidth: 2)).interpolationMethod(.monotone)
                        }
                    }
                    .chartXAxis(.hidden)
                    .chartYAxis {
                        AxisMarks(position: .trailing, values: .automatic(desiredCount: 4)) { v in
                            AxisGridLine().foregroundStyle(Color.white.opacity(0.05))
                            AxisValueLabel { if let d = v.as(Double.self) { Text(percent(d, 0)).font(.geist(11)).foregroundStyle(Theme.subtle) } }
                        }
                    }
                    .frame(height: 260)
                }
            } else {
                Text("Not enough history yet.").font(.geist(14)).foregroundStyle(Theme.muted).padding(.vertical, 40).frame(maxWidth: .infinity)
            }
        }
        .surface(radius: 22, padding: 18)
    }

    private func legend(_ color: Color, _ label: String, dashed: Bool) -> some View {
        HStack(spacing: 6) {
            Path { p in p.move(to: .zero); p.addLine(to: CGPoint(x: 16, y: 0)) }
                .stroke(color, style: StrokeStyle(lineWidth: 2, dash: dashed ? [3, 3] : []))
                .frame(width: 16, height: 2)
            Text(label).font(.geist(12)).foregroundStyle(Theme.muted)
        }
    }

    // MARK: Investment activity

    private var activity: some View {
        let months = Array(Analytics.monthlyActivity(store.portfolioTransactions, today: today).suffix(18))
        return VStack(alignment: .leading, spacing: 14) {
            title("Investment activity", "Money invested per month, incl. fees")
            Chart(months) { m in
                BarMark(x: .value("Month", m.date, unit: .month), y: .value("Invested", m.invested))
                    .foregroundStyle(Theme.planBlue)
                    .cornerRadius(4)
            }
            .chartXAxis {
                AxisMarks(values: .stride(by: .month, count: max(1, months.count / 6))) { _ in
                    AxisValueLabel(format: .dateTime.month(.abbreviated), centered: true).font(.geist(11)).foregroundStyle(Theme.subtle)
                }
            }
            .insideYAxis(count: 3)
            .frame(height: 200)
        }
        .surface(radius: 22, padding: 18)
    }

    // MARK: Sets

    private func sets(_ holdings: [HoldingView]) -> some View {
        let rows = setSort == .value ? Analytics.bySet(holdings) : Analytics.bySet(holdings).sorted { ($0.ret ?? -.infinity) > ($1.ret ?? -.infinity) }
        let maxShare = max(rows.map(\.share).max() ?? 0, 0.0001)
        return VStack(alignment: .leading, spacing: 12) {
            HStack {
                Text("Performance by set").font(.geist(17, .semibold))
                Spacer()
                ChipPicker(options: [(SetSort.value, "Value"), (.ret, "Return")], selection: $setSort).scaleEffect(0.85, anchor: .trailing)
            }
            ForEach(rows) { r in
                VStack(alignment: .leading, spacing: 8) {
                    HStack(alignment: .firstTextBaseline) {
                        VStack(alignment: .leading, spacing: 2) {
                            Text(r.name).font(.geist(14, .medium)).lineLimit(1)
                            Text("\(r.holdings) holding\(r.holdings == 1 ? "" : "s")").font(.geist(12)).foregroundStyle(Theme.muted)
                        }
                        Spacer(minLength: 8)
                        VStack(alignment: .trailing, spacing: 2) {
                            Text(Format.money(r.value)).font(.geist(14, .medium)).monospacedDigit()
                            HStack(spacing: 6) {
                                Text(Format.signedMoney(r.gain)).foregroundStyle(Theme.tone(r.gain))
                                Text(Format.signedPercent(r.ret)).foregroundStyle(Theme.tone(r.ret))
                            }
                            .font(.geist(12)).monospacedDigit()
                        }
                    }
                    HStack(spacing: 8) {
                        GeometryReader { geo in
                            ZStack(alignment: .leading) {
                                Capsule().fill(Theme.surface2)
                                Capsule().fill(Theme.planBlue).frame(width: geo.size.width * r.share / maxShare)
                            }
                        }
                        .frame(height: 6)
                        Text(percent(r.share, 0)).font(.geist(12)).monospacedDigit().foregroundStyle(Theme.muted).frame(width: 38, alignment: .trailing)
                    }
                }
                .padding(.vertical, 6)
                if r.id != rows.last?.id { Rectangle().fill(Theme.border).frame(height: 1) }
            }
        }
        .surface(radius: 22, padding: 18)
    }

    // MARK: Best and worst

    private func rank(_ heading: String, best: Bool, holdings: [HoldingView], empty: String) -> some View {
        let key = { (h: HoldingView) in rankBy == .dollar ? (h.gain ?? 0) : (h.gainRatio ?? 0) }
        let priced = holdings.filter { $0.gain != nil }
        let items = best
            ? Array(priced.filter { ($0.gain ?? 0) > 0 }.sorted { key($0) > key($1) }.prefix(5))
            : Array(priced.filter { ($0.gain ?? 0) < 0 }.sorted { key($0) < key($1) }.prefix(5))
        return VStack(alignment: .leading, spacing: 10) {
            HStack {
                Text(heading).font(.geist(17, .semibold))
                Spacer()
                ChipPicker(options: [(RankBy.dollar, "$"), (.percent, "%")], selection: $rankBy).scaleEffect(0.85, anchor: .trailing)
            }
            if items.isEmpty {
                Text(empty).font(.geist(14)).foregroundStyle(Theme.muted).padding(.vertical, 8)
            }
            ForEach(items) { h in
                NavigationLink(value: h.identity.productId) {
                    MiniRow(holding: h, trailing: rankBy == .dollar ? Format.signedMoney(h.gain) : Format.signedPercent(h.gainRatio), tint: Theme.tone(h.gain))
                }
                .buttonStyle(.plain)
            }
        }
        .surface(radius: 22, padding: 18)
    }

    private func title(_ t: String, _ sub: String) -> some View {
        VStack(alignment: .leading, spacing: 4) {
            Text(t).font(.geist(17, .semibold))
            Text(sub).font(.geist(13)).foregroundStyle(Theme.muted)
        }
    }
}

/// "12%" or "−3.4%", unsigned unless negative.
private func percent(_ r: Double, _ decimals: Int) -> String {
    let v = String(format: "%.\(decimals)f%%", abs(r) * 100)
    return r < -0.000_05 ? "−\(v)" : v
}

/// Each month's time-weighted return as a colored cell, a row per year.
private struct MonthlyHeatmap: View {
    var months: [Analytics.MonthReturn]
    private static let names = ["Jan", "Feb", "Mar", "Apr", "May", "Jun", "Jul", "Aug", "Sep", "Oct", "Nov", "Dec"]

    var body: some View {
        if let best = months.max(by: { $0.ret < $1.ret }), let worst = months.min(by: { $0.ret < $1.ret }) {
            let years = Set(months.map(\.year)).sorted(by: >)
            let positive = months.filter { $0.ret > 0 }.count
            VStack(alignment: .leading, spacing: 14) {
                VStack(alignment: .leading, spacing: 4) {
                    Text("Monthly returns").font(.geist(17, .semibold))
                    Text("\(positive) of \(months.count) months up · best \(Self.names[best.month]) \(String(best.year)) (\(Format.signedPercent(best.ret))), worst \(Self.names[worst.month]) \(String(worst.year)) (\(Format.signedPercent(worst.ret)))")
                        .font(.geist(13)).foregroundStyle(Theme.muted)
                }
                ScrollView(.horizontal, showsIndicators: false) {
                    Grid(horizontalSpacing: 4, verticalSpacing: 4) {
                        GridRow {
                            Color.clear.frame(width: 36, height: 1)
                            ForEach(Self.names, id: \.self) { Text($0.uppercased()).font(.mono(10)).foregroundStyle(Theme.subtle) }
                            Text("YEAR").font(.mono(10)).foregroundStyle(Theme.subtle)
                        }
                        ForEach(years, id: \.self) { y in
                            let row = months.filter { $0.year == y }
                            let yearRet = row.reduce(1.0) { $0 * (1 + $1.ret) } - 1
                            GridRow {
                                Text(String(y)).font(.geist(12, .medium)).foregroundStyle(Theme.muted).frame(width: 36, alignment: .leading)
                                ForEach(0..<12, id: \.self) { i in
                                    let m = row.first { $0.month == i }
                                    Text(m.map { Format.signedPercent($0.ret) } ?? "")
                                        .font(.geist(10, .medium)).monospacedDigit().lineLimit(1).minimumScaleFactor(0.7)
                                        .foregroundStyle(m.map { $0.ret >= 0 ? Theme.ink : .white } ?? .clear)
                                        .frame(width: 52, height: 38)
                                        .background(m.map { heat($0.ret) } ?? .clear, in: RoundedRectangle(cornerRadius: 6, style: .continuous))
                                }
                                Text(Format.signedPercent(yearRet)).font(.geist(12, .semibold)).monospacedDigit().foregroundStyle(Theme.tone(yearRet))
                                    .frame(width: 60, height: 38)
                                    .background(Theme.surface2, in: RoundedRectangle(cornerRadius: 6, style: .continuous))
                            }
                        }
                    }
                }
                .scrollClipDisabled()
            }
            .surface(radius: 22, padding: 18)
        }
    }

    /// Stronger color for bigger moves; square root so small moves still show.
    private func heat(_ ret: Double) -> Color {
        let t = (min(1, abs(ret) / 0.15)).squareRoot()
        let strength = 0.08 + t * (0.55 - 0.08)
        return (ret >= 0 ? Theme.up : Theme.down).opacity(strength * 1.6 > 1 ? 1 : strength * 1.6)
    }
}

/// Each holding's return against how long you've held it.
private struct ReturnVsTime: View {
    var points: [Analytics.HeldPoint]

    var body: some View {
        if !points.isEmpty {
            let avg = Analytics.averageHoldDays(points)
            VStack(alignment: .leading, spacing: 14) {
                VStack(alignment: .leading, spacing: 4) {
                    Text("Return vs. time held").font(.geist(17, .semibold))
                    Text(avg.map { "Average hold \(Int($0.rounded())) days, weighted by value" } ?? "Each dot is a holding")
                        .font(.geist(13)).foregroundStyle(Theme.muted)
                }
                Chart(points) { p in
                    PointMark(x: .value("Days held", p.days), y: .value("Return", p.ret))
                        .foregroundStyle((p.ret >= 0 ? Theme.up : Theme.down).opacity(0.85))
                        .symbolSize(30 + min(200, p.value / 5))
                    RuleMark(y: .value("Zero", 0)).foregroundStyle(Theme.borderStrong)
                }
                .chartXAxis {
                    AxisMarks(values: .automatic(desiredCount: 4)) { v in
                        AxisValueLabel { if let d = v.as(Int.self) { Text("\(d)d").font(.geist(11)).foregroundStyle(Theme.subtle) } }
                    }
                }
                .chartYAxis {
                    AxisMarks(position: .trailing, values: .automatic(desiredCount: 4)) { v in
                        AxisGridLine().foregroundStyle(Color.white.opacity(0.05))
                        AxisValueLabel { if let d = v.as(Double.self) { Text(percent(d, 0)).font(.geist(11)).foregroundStyle(Theme.subtle) } }
                    }
                }
                .frame(height: 220)
            }
            .surface(radius: 22, padding: 18)
        }
    }
}

/// Value by product type, with what you paid underneath so the gap is the gain.
private struct TypeBreakdown: View {
    var groups: [Analytics.Group]

    var body: some View {
        if !groups.isEmpty {
            let top = max(groups.map(\.value).max() ?? 1, 1)
            VStack(alignment: .leading, spacing: 14) {
                VStack(alignment: .leading, spacing: 4) {
                    Text("By product type").font(.geist(17, .semibold))
                    Text("Where the value sits, and how each type has done").font(.geist(13)).foregroundStyle(Theme.muted)
                }
                ForEach(groups) { g in
                    VStack(alignment: .leading, spacing: 6) {
                        HStack(alignment: .firstTextBaseline) {
                            (Text(g.name).font(.geist(13, .medium)) + Text(" · \(g.count)").font(.geist(12)).foregroundColor(Theme.subtle)).lineLimit(1)
                            Spacer(minLength: 8)
                            Text(Format.money(g.value)).font(.geist(13)).monospacedDigit()
                            Text(Format.signedPercent(g.ret)).font(.geist(12)).monospacedDigit().foregroundStyle(Theme.tone(g.ret))
                        }
                        GeometryReader { geo in
                            ZStack(alignment: .leading) {
                                Capsule().fill(Theme.surface2)
                                Capsule().fill(Color.white.opacity(0.15)).frame(width: geo.size.width * min(g.cost, top) / top)
                                Capsule().fill(LinearGradient(colors: [Theme.planBlue.opacity(0.45), Theme.planBlue], startPoint: .leading, endPoint: .trailing))
                                    .frame(width: geo.size.width * g.value / top)
                            }
                        }
                        .frame(height: 8)
                    }
                }
                Text("Faint bar: what you paid. Bright bar: what it's worth.").font(.geist(12)).foregroundStyle(Theme.subtle)
            }
            .surface(radius: 22, padding: 18)
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
            VStack(alignment: .leading, spacing: 14) {
                VStack(alignment: .leading, spacing: 4) {
                    Text("Diversification").font(.geist(17, .semibold))
                    Text("\(label): your \(holdings.count) holdings behave like \(effective) equally sized ones").font(.geist(13)).foregroundStyle(Theme.muted)
                }
                GeometryReader { geo in
                    HStack(spacing: 1) {
                        ForEach(Array(top.enumerated()), id: \.offset) { i, h in
                            Rectangle().fill(Theme.planBlue.opacity(0.9 - Double(i) * 0.14)).frame(width: geo.size.width * (h.value ?? 0) / total)
                        }
                        Spacer(minLength: 0)
                    }
                    .background(Theme.surface2)
                    .clipShape(Capsule())
                }
                .frame(height: 12)
                ForEach(Array(top.enumerated()), id: \.offset) { i, h in
                    NavigationLink(value: h.identity.productId) {
                        HStack(spacing: 8) {
                            RoundedRectangle(cornerRadius: 2).fill(Theme.planBlue.opacity(0.9 - Double(i) * 0.14)).frame(width: 10, height: 10)
                            Text(h.product?.name ?? "Unknown").font(.geist(13)).lineLimit(1)
                            Spacer(minLength: 8)
                            Text(percent((h.value ?? 0) / total, 1)).font(.geist(13)).monospacedDigit().foregroundStyle(Theme.muted)
                        }
                    }
                    .buttonStyle(.plain)
                }
                Rectangle().fill(Theme.border).frame(height: 1)
                HStack {
                    stat("Top holding", percent(c.top1, 0))
                    stat("Top 5", percent(c.top5, 0))
                    stat("Effective", "\(effective)")
                }
            }
            .surface(radius: 22, padding: 18)
        }
    }

    private func stat(_ label: String, _ value: String) -> some View {
        VStack(alignment: .leading, spacing: 4) {
            MonoLabel(text: label, color: Theme.subtle)
            Text(value).font(.geist(17, .semibold)).monospacedDigit()
        }
        .frame(maxWidth: .infinity, alignment: .leading)
    }
}
