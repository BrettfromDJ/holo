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
                    if value.location.x < width * 0.33 { go(index - 1, of: all.count) } else { go(index + 1, of: all.count) }
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
        let moved = store.holdings.filter { $0.change7dPct != nil && $0.product != nil }
        let gainer = moved.max { ($0.change7dPct ?? 0) < ($1.change7dPct ?? 0) }
        let loser = moved.min { ($0.change7dPct ?? 0) < ($1.change7dPct ?? 0) }
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
                Big(text: Format.signedMoney(gain), color: gain >= 0 ? Theme.lime : Color(hex: 0xFF8AB3))
                Text("\(Format.signedPercent(ratio)) from market moves alone · now \(Format.money(s.value))")
                    .font(.geist(15)).monospacedDigit().foregroundStyle(.white.opacity(0.7)).padding(.top, 8)
            }
        )))
        if let gainer, (gainer.change7dPct ?? 0) > 0 {
            slides.append(Slide(key: "gainer", background: glow(0x8FAE00, 0x2A3600, at: UnitPoint(x: 0.8, y: 0)), content: AnyView(
                HeroSlide(kicker: "Hottest this week", holding: gainer, drifts: true) {
                    Big(text: Format.signedPercent((gainer.change7dPct ?? 0) / 100), color: Theme.lime)
                    Text("Now \(Format.money(gainer.price)) each").font(.geist(14)).monospacedDigit().foregroundStyle(.white.opacity(0.7)).padding(.top, 4)
                }
            )))
        }
        if let loser, (loser.change7dPct ?? 0) < 0 {
            slides.append(Slide(key: "loser", background: glow(0xE0306F, 0x3D0A1F, at: UnitPoint(x: 0.2, y: 0)), content: AnyView(
                HeroSlide(kicker: "Cooled off", holding: loser) {
                    Big(text: Format.signedPercent((loser.change7dPct ?? 0) / 100), color: Color(hex: 0xFF8AB3))
                    Text("Now \(Format.money(loser.price)) each. Buying opportunity?").font(.geist(14)).monospacedDigit().foregroundStyle(.white.opacity(0.7)).padding(.top, 4)
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
                    Big(text: "\(Int(units)) item\(units == 1 ? "" : "s")", color: .white)
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
                    Big(text: Format.signedPercent(best.gainRatio), color: Theme.lime)
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
                    Big(text: Format.money(s.value), color: .white)
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
    var text: String
    var color: Color
    var body: some View {
        Text(text).font(.geist(46, .semibold)).tracking(-1.8).monospacedDigit().foregroundStyle(color)
            .lineLimit(1).minimumScaleFactor(0.5).padding(.top, 12)
    }
}

/// A slide about one product: kicker, the piece, then its name and numbers.
private struct HeroSlide<Numbers: View>: View {
    var kicker: String
    var holding: HoldingView
    /// Tilts slowly with light sweeping across, like the card page.
    var drifts = false
    @ViewBuilder var numbers: Numbers

    var body: some View {
        VStack(alignment: .leading, spacing: 0) {
            Kicker(text: kicker)
            Group {
                if drifts {
                    RecapDriftCard(holding: holding)
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
        VStack(spacing: 22) {
            ZStack {
                ForEach(0 ..< n, id: \.self) { i in
                    let mid = Double(n - 1) / 2
                    let angle: Double = (Double(i) - mid) * (small ? 9 : 12)
                    let x = CGFloat(Double(i) - mid) * (small ? 46 : 70)
                    HoldingArt(product: buys[i].product, identity: buys[i].identity, cornerRadius: 10, caption: false)
                        .frame(width: 150, height: 210)
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
private struct RecapDriftCard: View {
    var holding: HoldingView
    @Environment(\.accessibilityReduceMotion) private var reduceMotion

    var body: some View {
        TimelineView(.animation(minimumInterval: nil, paused: reduceMotion)) { context in
            let c = reduceMotion ? 0 : context.date.timeIntervalSinceReferenceDate
            let tiltX: Double = sin(c * 0.6) * 8
            let tiltY: Double = cos(c * 0.45) * 11
            let sweep = CGFloat(sin(c * 0.6))
            HoldingArt(product: holding.product, identity: holding.identity, cornerRadius: 16, caption: false)
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
                .background {
                    RadialGradient(colors: [Theme.lime.opacity(0.22), .clear], center: .center, startRadius: 40, endRadius: 200)
                        .padding(-40)
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
