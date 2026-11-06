import SwiftUI

/// "Your week in Lucent": story-style slides about the last seven days, like the website's recap.
/// Tap the right two thirds to go on, the left third to go back; hold to pause. Each slide
/// moves on by itself after a few seconds.
struct WeeklyRecap: View {
    var store: CollectionStore
    @Environment(\.dismiss) private var dismiss
    @Environment(\.accessibilityReduceMotion) private var reduceMotion
    @State private var index = 0
    @State private var paused = false
    @State private var progress: CGFloat = 0

    private static let slideSeconds: Double = 5.5

    /// The slides, built once when the recap opens. Building them replays the ledger, and the
    /// progress bar redraws this view about 20 times a second, so they must not be rebuilt in
    /// `body`.
    @State private var built: [Slide]?
    private var slides: [Slide] { built ?? Slide.build(store) }

    var body: some View {
        let all = slides
        let slide = all[min(index, all.count - 1)]
        ZStack(alignment: .top) {
            slide.background.ignoresSafeArea()
            // A full-bleed moving picture behind the text, on slides that have one.
            if let backdrop = slide.backdrop {
                backdrop.id(slide.key + "-backdrop").ignoresSafeArea().transition(.opacity)
            }
            VStack(alignment: .leading, spacing: 0) {
                // Progress bars, one per slide.
                HStack(spacing: 6) {
                    ForEach(all.indices, id: \.self) { n in
                        GeometryReader { geo in
                            Capsule().fill(.white.opacity(0.25))
                                .overlay(alignment: .leading) {
                                    Capsule().fill(.white)
                                        .frame(width: geo.size.width * (n < index ? 1 : n > index ? 0 : progress))
                                }
                        }
                        .frame(height: 3)
                    }
                }
                HStack {
                    Spacer()
                    Button { dismiss() } label: {
                        Image(systemName: "xmark").font(.system(size: 17, weight: .semibold)).foregroundStyle(.white.opacity(0.8))
                            .frame(width: 40, height: 40)
                    }
                    .accessibilityLabel("Close recap")
                }
                slide.content
                    .id(slide.key)
                    .transition(.asymmetric(insertion: .move(edge: .bottom).combined(with: .opacity), removal: .opacity))
                    .frame(maxHeight: .infinity)
            }
            .padding(.horizontal, 28)
            .padding(.top, 12)
            .padding(.bottom, 20)
        }
        .contentShape(Rectangle())
        .gesture(
            DragGesture(minimumDistance: 0)
                .onChanged { _ in paused = true }
                .onEnded { value in
                    paused = false
                    // A tap (not a hold-and-drag) moves between slides.
                    guard abs(value.translation.width) < 12, abs(value.translation.height) < 12 else {
                        if value.translation.height > 120 { dismiss() }
                        return
                    }
                    let width = UIScreen.main.bounds.width
                    if value.location.x < width * 0.33 {
                        go(index - 1, of: all.count)
                    } else if index >= all.count - 1 {
                        // Tapping on from the last slide closes the recap.
                        dismiss()
                    } else {
                        go(index + 1, of: all.count)
                    }
                }
        )
        .onAppear { if built == nil { built = all } }
        .task(id: index) {
            // Fill this slide's bar, then move on (the last slide waits).
            progress = 0
            let steps = 110
            for _ in 0 ..< steps {
                try? await Task.sleep(for: .seconds(Self.slideSeconds / Double(steps)))
                if Task.isCancelled { return }
                if !paused { progress += 1 / CGFloat(steps) }
                if progress >= 1 { break }
            }
            let count = slides.count
            if index < count - 1 { go(index + 1, of: count) }
        }
        // A light tap as each slide opens.
        .sensoryFeedback(.impact(weight: .light), trigger: index)
        .statusBarHidden()
    }

    private func go(_ n: Int, of count: Int) {
        guard n >= 0, n < count else { return }
        // Snappy, so tapping through feels instant.
        withAnimation(reduceMotion ? nil : .spring(response: 0.32, dampingFraction: 0.86)) { index = n }
    }
}

private struct Slide {
    var key: String
    var background: RadialGradient
    var content: AnyView
    var backdrop: AnyView? = nil

    private static func glow(_ hex: UInt32, _ mid: UInt32, at: UnitPoint) -> RadialGradient {
        RadialGradient(colors: [Color(hex: hex), Color(hex: mid), Color(hex: 0x0B0B0C)], center: at, startRadius: 0, endRadius: 620)
    }

    static func build(_ store: CollectionStore) -> [Slide] {
        let today = Date()
        let from = Format.day(Calendar.current.date(byAdding: .day, value: -7, to: today) ?? today)
        let week = store.timeline.filter { $0.date >= from }
        // Market moves alone: the change in value less what new buys added at cost.
        let gain: Double = {
            guard let a = week.first, let b = week.last else { return 0 }
            return (b.value - a.value) - (b.cost - a.cost)
        }()
        let ratio: Double? = week.first.map { $0.value > 0 ? gain / $0.value : nil } ?? nil
        // Each card's move over the week. A graded copy is priced from eBay sales and carries no
        // weekly change, so fall back to the card's own price feed: its 7-day change, else the
        // change worked out from its price history.
        func weekMove(_ h: HoldingView) -> Double? {
            if let c = h.change7dPct { return c }
            let key = priceKey(h.identity.productId, h.identity.printing)
            if let c = store.prices[key]?.change7dPct { return c }
            guard let pts = store.history[key], let last = pts.last?.price,
                  let then = pts.last(where: { $0.date <= from })?.price, then > 0 else { return nil }
            return (last - then) / then * 100
        }
        let moves: [(holding: HoldingView, pct: Double)] = store.holdings.compactMap { h in
            guard h.product != nil, let m = weekMove(h) else { return nil }
            return (h, m)
        }
        let top = moves.max { $0.pct < $1.pct }
        let bottom = moves.min { $0.pct < $1.pct }
        let gainer = top?.holding
        let loser = bottom?.holding
        let gainerPct: Double = top?.pct ?? 0
        let loserPct: Double = bottom?.pct ?? 0
        let buys = Ledger.effective(store.transactions).filter { $0.kind == .purchase && $0.date > from && $0.date <= Format.day(today) }
        let spent = buys.reduce(0) { $0 + $1.acquisitionCost }
        let units = buys.reduce(0) { $0 + $1.quantity }
        let best = store.holdings.filter { $0.gainRatio != nil && $0.product != nil }.max { ($0.gainRatio ?? 0) < ($1.gainRatio ?? 0) }
        let s = store.summary

        var slides: [Slide] = []
        let range = "\(shortDate(Calendar.current.date(byAdding: .day, value: -6, to: today) ?? today)) – \(shortDate(today))"
        slides.append(Slide(key: "intro", background: glow(0x5B3DF5, 0x1B1240, at: UnitPoint(x: 0.2, y: 0)), content: AnyView(
            VStack(alignment: .leading, spacing: 0) {
                Kicker(text: "Your week in Lucent")
                Text(range).font(.geist(14)).foregroundStyle(.white.opacity(0.7)).padding(.top, 8)
                // The week's value, drawing across the page; today pings at the end.
                RecapWeekChart(values: week.map(\.value), days: week.map(\.date), up: gain >= 0)
                    .frame(maxHeight: .infinity)
                    .padding(.vertical, 28)
                Text("Your collection \(gain >= 0 ? "grew" : "slipped")").font(.geist(18, .medium)).foregroundStyle(.white.opacity(0.8))
                Big(value: gain, format: { Format.signedMoney($0) }, color: gain >= 0 ? Theme.lime : Color(hex: 0xFF8AB3))
                Text("\(Format.signedPercent(ratio)) from market moves alone · now \(Format.money(s.value))")
                    .font(.geist(15)).monospacedDigit().foregroundStyle(.white.opacity(0.7)).padding(.top, 8)
            }
        )))
        if let gainer, gainerPct > 0 {
            slides.append(Slide(key: "gainer", background: glow(0xFF5A1F, 0x3D1206, at: UnitPoint(x: 0.5, y: 1)), content: AnyView(
                HeroSlide(kicker: "Hottest this week", holding: gainer, drifts: true, glow: Color(hex: 0xFF7A1A), theme: .fire) {
                    Big(value: gainerPct / 100, format: { Format.signedPercent($0) }, color: Theme.lime)
                    Text("Now \(Format.money(gainer.price)) each").font(.geist(14)).monospacedDigit().foregroundStyle(.white.opacity(0.7)).padding(.top, 4)
                }
            )))
        }
        // The coldest: the card that fell most, or, when nothing fell, the one that rose least
        // (as long as it isn't also the hottest).
        if let loser, loserPct < 0 || (moves.count > 1 && loser.identity != gainer?.identity && loserPct < gainerPct) {
            slides.append(Slide(key: "loser", background: glow(0x38BDF8, 0x0B2A3D, at: UnitPoint(x: 0.5, y: 0)), content: AnyView(
                HeroSlide(kicker: "Coldest this week", holding: loser, drifts: true, glow: Color(hex: 0x7DD3FC), theme: .ice) {
                    Big(value: loserPct / 100, format: { Format.signedPercent($0) }, color: loserPct < 0 ? Color(hex: 0xFF8AB3) : Theme.lime)
                    Text("Now \(Format.money(loser.price)) each.\(loserPct < 0 ? " Buying opportunity?" : " The slowest mover this week.")").font(.geist(14)).monospacedDigit().foregroundStyle(.white.opacity(0.7)).padding(.top, 4)
                }
            )))
        }
        slides.append(Slide(key: "spent", background: glow(0xF59E0B, 0x3D2606, at: UnitPoint(x: 0.5, y: 0)), content: AnyView(
            VStack(alignment: .leading, spacing: 0) {
                Kicker(text: "Shopping")
                if spent > 0 {
                    RecapBuysFan(buys: Array(buys.prefix(5)).map { RecapBuy(product: store.products[$0.identity.productId], identity: $0.identity, cost: $0.acquisitionCost) })
                        .frame(maxWidth: .infinity, maxHeight: .infinity)
                } else {
                    Spacer()
                }
                if spent > 0 {
                    Text("You picked up").font(.geist(18, .medium)).foregroundStyle(.white.opacity(0.8))
                    Big(value: units, format: { "\(Int($0.rounded())) item\(units == 1 ? "" : "s")" }, color: .white)
                    Text("\(Format.money(spent)) spent, fees included").font(.geist(15)).monospacedDigit().foregroundStyle(.white.opacity(0.7)).padding(.top, 8)
                } else {
                    Big(text: "$0 spent", color: .white)
                    Text("No new buys this week.").font(.geist(18)).foregroundStyle(.white.opacity(0.8)).padding(.top, 12)
                }
            }
        )))
        if let best, (best.gainRatio ?? 0) > 0 {
            slides.append(Slide(key: "best", background: glow(0xEC4899, 0x3D0D26, at: UnitPoint(x: 0.5, y: 0)), content: AnyView(
                HeroSlide(kicker: "Best buy you've ever made", holding: best, drifts: true) {
                    // A gain: lime (pink is only for what's down).
                    Big(value: best.gainRatio ?? 0, format: { Format.signedPercent($0) }, color: Theme.lime)
                    HStack(spacing: 8) {
                        Text("Paid \(Format.money(best.costBasis))").foregroundStyle(.white.opacity(0.75))
                        Image(systemName: "arrow.right").font(.system(size: 11, weight: .bold)).foregroundStyle(.white.opacity(0.6))
                        Text("worth \(Format.money(best.value))").foregroundStyle(.white)
                    }
                    .font(.geist(14, .semibold)).monospacedDigit()
                    .padding(.horizontal, 14).frame(height: 36)
                    .liquidGlass(in: Capsule())
                    .padding(.top, 10)
                }
            )))
        }
        let pieces = store.holdings.filter { $0.product?.imageURL != nil }.map { RecapBuy(product: $0.product, identity: $0.identity, cost: 0) }
        slides.append(Slide(key: "outro", background: glow(0x3B82F6, 0x0C1D3D, at: UnitPoint(x: 0.5, y: 1)), content: AnyView(
            VStack(alignment: .leading, spacing: 0) {
                Kicker(text: "That's a wrap")
                Spacer()
                VStack(alignment: .leading, spacing: 0) {
                    Text("Your collection is worth").font(.geist(18, .medium)).foregroundStyle(.white.opacity(0.85))
                    Big(value: s.value, format: { Format.money($0) }, color: .white)
                    Text("\(Int(s.items)) items · \(Format.signedMoney(s.gain)) (\(Format.signedPercent(s.gainRatio))) all time")
                        .font(.geist(15)).monospacedDigit().foregroundStyle(.white.opacity(0.75)).padding(.top, 8)
                }
                .padding(20)
                .frame(maxWidth: .infinity, alignment: .leading)
                .liquidGlass(in: RoundedRectangle(cornerRadius: 26, style: .continuous))
                Text("See you next week.").font(.geist(13)).foregroundStyle(.white.opacity(0.6)).padding(.top, 16)
            }
        ), backdrop: pieces.isEmpty ? nil : AnyView(RecapGrid(pieces: pieces))))
        return slides
    }

    private static func shortDate(_ d: Date) -> String { d.formatted(.dateTime.month(.abbreviated).day()) }
}

private struct Kicker: View {
    var text: String
    var body: some View {
        Text(text.uppercased()).font(.mono(12, .medium)).tracking(0.7).foregroundStyle(.white.opacity(0.6))
    }
}

private struct Big: View {
    var text: String? = nil
    /// A figure that counts up as the slide opens (instead of `text`).
    var value: Double? = nil
    var format: (Double) -> String = { "\($0)" }
    var color: Color

    var body: some View {
        Group {
            if let value {
                CountingText(value: value, format: format, duration: 1.2, delay: 0.25)
            } else {
                Text(text ?? "")
            }
        }
        .font(.geist(46, .semibold)).tracking(-1.8).monospacedDigit().foregroundStyle(color)
        .lineLimit(1).minimumScaleFactor(0.5)
        // Sits close under the line above it (the figure's own line height trimmed).
        .padding(.top, -2)
        .padding(.bottom, -4)
    }
}

/// A slide about one product: kicker, the piece, then its name and numbers.
private struct HeroSlide<Numbers: View>: View {
    var kicker: String
    var holding: HoldingView
    /// Tilts slowly with light sweeping across, like the card page.
    var drifts = false
    /// The glow behind a drifting card: lime for gains, pink for a drop.
    var glow: Color = Theme.lime
    /// Fire (embers) or ice (snow and frost) around the card.
    var theme: RecapTheme = .plain
    @ViewBuilder var numbers: Numbers

    var body: some View {
        VStack(alignment: .leading, spacing: 0) {
            HStack(spacing: 6) {
                if theme != .plain {
                    Image(systemName: theme == .fire ? "flame.fill" : "snowflake")
                        .font(.system(size: 12, weight: .semibold))
                        .foregroundStyle(theme == .fire ? Color(hex: 0xFFB020) : Color(hex: 0xBAE6FD))
                }
                Kicker(text: kicker)
            }
            Group {
                if drifts {
                    RecapDriftCard(holding: holding, glow: glow, theme: theme)
                } else {
                    HoldingArt(product: holding.product, identity: holding.identity, cornerRadius: 16)
                        .shadow(color: .black.opacity(0.5), radius: 24, y: 14)
                }
            }
            .frame(maxWidth: 280, maxHeight: 380)
            // The biggest picture of the card, decoded at full size (as on the card page).
            .environment(\.imageMaxPixel, nil)
            .environment(\.largeProductImages, true)
            .frame(maxWidth: .infinity, maxHeight: .infinity)
            .padding(.vertical, 20)
            Text(shortName(holding.product?.name ?? "")).font(.geist(20, .semibold)).foregroundStyle(.white).lineLimit(2)
            numbers
        }
    }

    private func shortName(_ name: String) -> String {
        name.replacingOccurrences(of: #"\s*\(.*?\)\s*"#, with: " ", options: .regularExpression)
            .replacingOccurrences(of: #"\s+-\s+\d+/\d+$"#, with: "", options: .regularExpression)
            .trimmingCharacters(in: .whitespaces)
    }
}

// MARK: - Pictures for the slides

/// The week's value as a big line drawing across the slide (lime up, pink down), the days
/// under it and a dot pinging on today. Draws once when the slide opens.
private struct RecapWeekChart: View {
    var values: [Double]
    var days: [String]
    var up: Bool
    @State private var drawn: CGFloat = 0
    @State private var ping = false
    @Environment(\.accessibilityReduceMotion) private var reduceMotion

    var body: some View {
        let color = up ? Theme.lime : Color(hex: 0xFF8AB3)
        VStack(spacing: 10) {
            GeometryReader { geo in
                let pts = points(in: geo.size)
                ZStack(alignment: .topLeading) {
                    ForEach(0 ..< 4, id: \.self) { k in
                        Rectangle().fill(Color.white.opacity(0.06)).frame(height: 1)
                            .offset(y: geo.size.height * CGFloat(k) / 3)
                    }
                    if pts.count > 1 {
                        Path { p in
                            p.move(to: CGPoint(x: pts[0].x, y: geo.size.height))
                            for pt in pts { p.addLine(to: pt) }
                            p.addLine(to: CGPoint(x: pts[pts.count - 1].x, y: geo.size.height))
                            p.closeSubpath()
                        }
                        .fill(LinearGradient(colors: [color.opacity(0.28), color.opacity(0)], startPoint: .top, endPoint: .bottom))
                        .mask(alignment: .leading) { Rectangle().frame(width: geo.size.width * drawn) }
                        Path { p in
                            p.move(to: pts[0])
                            for pt in pts.dropFirst() { p.addLine(to: pt) }
                        }
                        .trim(from: 0, to: drawn)
                        .stroke(color, style: StrokeStyle(lineWidth: 3.5, lineCap: .round, lineJoin: .round))
                        if let last = pts.last {
                            Circle().stroke(color, lineWidth: 2).frame(width: ping ? 34 : 10, height: ping ? 34 : 10)
                                .opacity(ping ? 0 : 1).position(last)
                            Circle().fill(color).frame(width: 11, height: 11).position(last).opacity(drawn >= 1 ? 1 : 0)
                        }
                    }
                }
            }
            HStack {
                ForEach(Array(days.enumerated()), id: \.offset) { _, d in
                    Text(weekday(d)).font(.mono(10)).foregroundStyle(.white.opacity(0.55)).frame(maxWidth: .infinity)
                }
            }
        }
        .onAppear {
            if reduceMotion { drawn = 1; return }
            withAnimation(.easeOut(duration: 1.3).delay(0.2)) { drawn = 1 }
            withAnimation(.easeOut(duration: 1.0).delay(1.5)) { ping = true }
        }
        .accessibilityHidden(true)
    }

    private func points(in size: CGSize) -> [CGPoint] {
        guard values.count > 1, let lo = values.min(), let hi = values.max() else { return [] }
        let span = max(hi - lo, 1)
        let step = size.width / CGFloat(values.count - 1)
        return values.enumerated().map { i, v in
            CGPoint(x: CGFloat(i) * step, y: size.height * 0.9 - CGFloat((v - lo) / span) * size.height * 0.8)
        }
    }

    private func weekday(_ day: String) -> String {
        let f = DateFormatter()
        f.dateFormat = "yyyy-MM-dd"
        guard let d = f.date(from: day) else { return "" }
        return d.formatted(.dateTime.weekday(.abbreviated))
    }
}

/// Something bought (or held): its product, which copy, and what it cost.
private struct RecapBuy {
    var product: Product?
    var identity: HoldingIdentity
    var cost: Double
}

/// What you bought this week as a fan, dropping in one by one, each with its price on glass.
private struct RecapBuysFan: View {
    var buys: [RecapBuy]
    @State private var shown = false
    @Environment(\.accessibilityReduceMotion) private var reduceMotion

    var body: some View {
        let n = buys.count
        let small = n > 3
        // Bigger when there are fewer: one purchase is as big as the other slides' cards.
        let w: CGFloat = n <= 1 ? 250 : (n == 2 ? 190 : (n == 3 ? 165 : 140))
        let spread: CGFloat = n == 2 ? 92 : (n == 3 ? 74 : 46)
        let tilt: Double = n == 2 ? 10 : (small ? 9 : 12)
        VStack(spacing: 22) {
            ZStack {
                ForEach(0 ..< n, id: \.self) { i in
                    let mid = Double(n - 1) / 2
                    let angle: Double = (Double(i) - mid) * tilt
                    let x = CGFloat(Double(i) - mid) * spread
                    HoldingArt(product: buys[i].product, identity: buys[i].identity, cornerRadius: 10, caption: false)
                        .frame(width: w, height: w * 1.4)
                        .shadow(color: .black.opacity(0.5), radius: 16, y: 10)
                        .rotationEffect(.degrees(angle), anchor: .bottom)
                        .offset(x: x, y: shown ? 0 : -60)
                        .opacity(shown ? 1 : 0)
                        .animation(reduceMotion ? nil : .spring(response: 0.5, dampingFraction: 0.75).delay(0.15 + Double(i) * 0.12), value: shown)
                }
            }
            // What each cost, in the same order, straight and side by side under the fan.
            HStack(spacing: 6) {
                ForEach(0 ..< n, id: \.self) { i in
                    Text(Format.money(buys[i].cost)).font(.geist(small ? 11 : 13, .semibold)).monospacedDigit()
                        .lineLimit(1).fixedSize()
                        .padding(.horizontal, small ? 8 : 12).frame(height: small ? 26 : 30)
                        .liquidGlass(in: Capsule())
                }
            }
            .opacity(shown ? 1 : 0)
            .animation(reduceMotion ? nil : .easeOut(duration: 0.4).delay(0.3 + Double(n) * 0.12), value: shown)
        }
        // The biggest picture of each, decoded at full size.
        .environment(\.imageMaxPixel, nil)
        .environment(\.largeProductImages, true)
        .onAppear { shown = true }
    }
}

/// A card that tilts slowly with a band of light sweeping across it and a soft lime glow
/// behind it, like the card page. Still under Reduce Motion.
/// What surrounds a drifting card: nothing, fire or ice.
enum RecapTheme { case plain, fire, ice }

private struct RecapDriftCard: View {
    var holding: HoldingView
    var glow: Color = Theme.lime
    var theme: RecapTheme = .plain
    @Environment(\.accessibilityReduceMotion) private var reduceMotion

    var body: some View {
        TimelineView(.animation(minimumInterval: nil, paused: reduceMotion)) { context in
            let c = reduceMotion ? 0 : context.date.timeIntervalSinceReferenceDate
            let tiltX: Double = sin(c * 0.6) * 8
            let tiltY: Double = cos(c * 0.45) * 11
            let sweep = CGFloat(sin(c * 0.6))
            // Fire flickers its glow; ice holds steady.
            let flicker: Double = theme == .fire ? 0.85 + 0.12 * sin(c * 9) + 0.08 * sin(c * 13.7) : 1
            HoldingArt(product: holding.product, identity: holding.identity, cornerRadius: 16, caption: false)
                .overlay { themeSkin(c) }
                .overlay {
                    GeometryReader { geo in
                        LinearGradient(colors: [.clear, .white.opacity(0.32), .clear], startPoint: .leading, endPoint: .trailing)
                            .frame(width: geo.size.width * 0.5, height: geo.size.height * 1.4)
                            .rotationEffect(.degrees(25))
                            .position(x: geo.size.width / 2 + sweep * geo.size.width * 0.7, y: geo.size.height / 2)
                    }
                    .blendMode(.plusLighter)
                    .clipShape(RoundedRectangle(cornerRadius: 16, style: .continuous))
                    .allowsHitTesting(false)
                }
                .rotation3DEffect(.degrees(tiltX), axis: (x: 1, y: 0, z: 0), perspective: 0.5)
                .rotation3DEffect(.degrees(tiltY), axis: (x: 0, y: 1, z: 0), perspective: 0.5)
                // A soft lime glow sized from the card, fading to nothing within its own frame (just
                // past the card's edge), so nothing cuts it off.
                .background {
                    GeometryReader { geo in
                        let w = geo.size.width
                        RadialGradient(colors: [glow.opacity((theme == .plain ? 0.22 : 0.4) * flicker), glow.opacity(0.1 * flicker), .clear], center: .center,
                                       startRadius: w * 0.25, endRadius: w * 0.5 + 28)
                            .frame(width: w + 60, height: geo.size.height + 60)
                            .position(x: w / 2, y: geo.size.height / 2)
                    }
                    .allowsHitTesting(false)
                }
                // Embers rising or snow falling around the card (drawn in one canvas, past its edges).
                .overlay {
                    if theme != .plain, !reduceMotion {
                        RecapParticles(theme: theme, time: c)
                            .padding(-70)
                            .allowsHitTesting(false)
                    }
                }
        }
    }

    /// What the theme does to the card itself: heat glowing up from the bottom edge, or frost
    /// creeping in from the corners with a cold rim.
    @ViewBuilder private func themeSkin(_ c: Double) -> some View {
        let shape = RoundedRectangle(cornerRadius: 16, style: .continuous)
        switch theme {
        case .fire:
            LinearGradient(colors: [.clear, Color(hex: 0xFF6A1A).opacity(0.18 + 0.08 * sin(c * 8)), Color(hex: 0xFFB020).opacity(0.38)],
                           startPoint: UnitPoint(x: 0.5, y: 0.55), endPoint: .bottom)
                .blendMode(.plusLighter)
                .clipShape(shape)
                .allowsHitTesting(false)
        case .ice:
            ZStack {
                RadialGradient(colors: [Color.white.opacity(0.45), .clear], center: .topLeading, startRadius: 0, endRadius: 130)
                RadialGradient(colors: [Color(hex: 0xBAE6FD).opacity(0.4), .clear], center: .bottomTrailing, startRadius: 0, endRadius: 150)
                shape.strokeBorder(LinearGradient(colors: [.white.opacity(0.85), Color(hex: 0x7DD3FC).opacity(0.5), .white.opacity(0.7)], startPoint: .topLeading, endPoint: .bottomTrailing), lineWidth: 2.5)
            }
            .clipShape(shape)
            .allowsHitTesting(false)
        case .plain:
            EmptyView()
        }
    }
}

/// Fire: embers rising and swaying, glowing yellow to red as they climb and fade. Ice: snow
/// drifting down, and a few glints twinkling around the card. All worked out from the clock.
private struct RecapParticles: View {
    var theme: RecapTheme
    var time: Double

    var body: some View {
        Canvas { ctx, size in
            func r(_ i: Int, _ k: Double) -> Double {
                let v = sin(Double(i) * 12.9898 + k * 78.233) * 43758.5453
                return v - floor(v)
            }
            func frac(_ v: Double) -> Double { v - floor(v) }
            if theme == .fire {
                for i in 0 ..< 30 {
                    let p = frac(time * (0.14 + 0.18 * r(i, 2)) + r(i, 3))
                    let x = size.width * (0.12 + 0.76 * r(i, 1)) + CGFloat(sin(time * 2.2 + Double(i)) * 12 * p)
                    let y = size.height * CGFloat(1 - p)
                    let rad = CGFloat(1.4 + 2.6 * r(i, 4)) * CGFloat(1 - p * 0.5)
                    let a = sin(Double.pi * p)
                    let color = Color(hue: 0.02 + 0.11 * (1 - p), saturation: 1, brightness: 1)
                    ctx.fill(Path(ellipseIn: CGRect(x: x - rad * 3, y: y - rad * 3, width: rad * 6, height: rad * 6)), with: .color(color.opacity(0.18 * a)))
                    ctx.fill(Path(ellipseIn: CGRect(x: x - rad, y: y - rad, width: rad * 2, height: rad * 2)), with: .color(color.opacity(a)))
                }
            } else {
                for i in 0 ..< 36 {
                    let p = frac(time * (0.05 + 0.07 * r(i, 2)) + r(i, 3))
                    let x = size.width * CGFloat(r(i, 1)) + CGFloat(sin(time * 0.8 + Double(i)) * 14)
                    let y = size.height * CGFloat(p)
                    let rad = CGFloat(1 + 2 * r(i, 4))
                    let a = 0.85 * sin(Double.pi * p)
                    ctx.fill(Path(ellipseIn: CGRect(x: x - rad, y: y - rad, width: rad * 2, height: rad * 2)), with: .color(.white.opacity(a)))
                }
                // Glints: four-pointed sparkles near the card's edges, each flashing in turn.
                let spots: [CGPoint] = [CGPoint(x: 0.28, y: 0.22), CGPoint(x: 0.76, y: 0.3), CGPoint(x: 0.3, y: 0.74), CGPoint(x: 0.72, y: 0.8), CGPoint(x: 0.5, y: 0.17), CGPoint(x: 0.5, y: 0.86)]
                for (i, spot) in spots.enumerated() {
                    let s = max(0, sin(time * 1.3 + Double(i) * 1.7))
                    let k = CGFloat(pow(s, 6)) * 9
                    guard k > 0.3 else { continue }
                    let cx = size.width * spot.x, cy = size.height * spot.y
                    var star = Path()
                    star.move(to: CGPoint(x: cx, y: cy - k)); star.addLine(to: CGPoint(x: cx + k * 0.18, y: cy))
                    star.addLine(to: CGPoint(x: cx, y: cy + k)); star.addLine(to: CGPoint(x: cx - k * 0.18, y: cy)); star.closeSubpath()
                    star.move(to: CGPoint(x: cx - k, y: cy)); star.addLine(to: CGPoint(x: cx, y: cy + k * 0.18))
                    star.addLine(to: CGPoint(x: cx + k, y: cy)); star.addLine(to: CGPoint(x: cx, y: cy - k * 0.18)); star.closeSubpath()
                    ctx.fill(star, with: .color(.white.opacity(0.95)))
                }
            }
        }
    }
}

/// Your collection as tilted columns of cards drifting behind the last slide (like the
/// walkthrough's Master Sets page), fading out toward the bottom where the total sits.
private struct RecapGrid: View {
    var pieces: [RecapBuy]
    private static let start = Date()
    @Environment(\.accessibilityReduceMotion) private var reduceMotion

    var body: some View {
        GeometryReader { geo in
            let cols = 4
            let gap: CGFloat = 8
            let span = geo.size.width * 1.4
            let w = (span - gap * CGFloat(cols - 1)) / CGFloat(cols)
            let h = w * 88 / 63
            let perCol = max(4, Int(ceil(Double(pieces.count) / Double(cols))))
            let listH = CGFloat(perCol) * (h + gap)
            TimelineView(.animation(minimumInterval: nil, paused: reduceMotion)) { context in
                let clock = reduceMotion ? 0 : context.date.timeIntervalSince(Self.start)
                HStack(alignment: .top, spacing: gap) {
                    ForEach(0 ..< cols, id: \.self) { c in
                        let speed: Double = [28, 23, 31, 26][c]
                        let progress = CGFloat((Double(c) * 0.27 + clock / speed).truncatingRemainder(dividingBy: 1))
                        let y: CGFloat = c % 2 == 1 ? -listH + listH * progress : -listH * progress
                        VStack(spacing: gap) {
                            ForEach(0 ..< perCol * 3, id: \.self) { k in
                                let piece = pieces[(c * perCol + k % perCol) % pieces.count]
                                HoldingArt(product: piece.product, identity: piece.identity, cornerRadius: 6, caption: false)
                                    .frame(width: w, height: h)
                            }
                        }
                        .offset(y: y)
                    }
                }
                .frame(width: span, height: geo.size.height * 1.5, alignment: .top)
            }
            .rotationEffect(.degrees(10))
            .frame(width: geo.size.width, height: geo.size.height)
            .clipped()
            .opacity(0.85)
            .mask(LinearGradient(stops: [.init(color: .black, location: 0), .init(color: .black, location: 0.45), .init(color: .clear, location: 0.85)],
                                 startPoint: .top, endPoint: .bottom))
        }
        // Small tiles: thumbnails big enough to stay sharp at this size, light enough to drift.
        .imageMaxPixel(600)
        .allowsHitTesting(false)
    }
}
