import Charts
import SwiftUI

// Shared pieces for the More pages (Analytics, Gains, Grading, Binder), so they share Home's
// energy: a big hero number on a grid, dark stat tiles that count up, bars that grow in
// and Anton section headings.

/// The top of a More page: a mono label, a big Anton number that counts up and glows, a line
/// under it, on Home's grid with lime and pink glows.
struct MoreHero<Below: View>: View {
    var label: String
    var value: Double
    var format: (Double) -> String
    var tint: Color
    @ViewBuilder var below: Below

    var body: some View {
        VStack(alignment: .leading, spacing: 12) {
            MonoLabel(text: label)
            CountingText(value: value, format: format)
                .font(.display(64)).monospacedDigit()
                .foregroundStyle(tint)
                .lineLimit(1).minimumScaleFactor(0.5)
                .displayTrim(64)
            below
        }
        .frame(maxWidth: .infinity, alignment: .leading)
        .padding(.vertical, 18)
        .background {
            ZStack {
                GridPattern()
                RadialGradient(colors: [Theme.planBlue.opacity(0.14), .clear], center: UnitPoint(x: 0.85, y: 0.35), startRadius: 0, endRadius: 150)
            }
            // Soft on every side, so the glow never shows an edge wherever it's cut off.
            .mask(EllipticalGradient(colors: [.black, .black.opacity(0.6), .clear], center: .center, startRadiusFraction: 0, endRadiusFraction: 0.5))
            .allowsHitTesting(false)
        }
    }
}

/// An Anton heading with a muted line under it, like Home's section titles.
struct MoreHeading: View {
    var title: String
    var subtitle: String?

    var body: some View {
        VStack(alignment: .leading, spacing: 6) {
            DisplayText(text: title.uppercased(), size: 26)
            if let subtitle { Text(subtitle).font(.geist(14)).foregroundStyle(Theme.muted) }
        }
        .frame(maxWidth: .infinity, alignment: .leading)
    }
}

/// A dark tile with an Anton figure that counts up, like Home's metric cards.
struct CountTile: View {
    var label: String
    var value: Double?
    var format: (Double) -> String
    var valueTint: Color = .white
    var sub: String
    var glow: Color
    var tag: String? = nil

    var body: some View {
        VStack(alignment: .leading, spacing: 0) {
            HStack(spacing: 6) {
                Text(label.uppercased()).font(.display(14)).tracking(0.3).foregroundStyle(.white.opacity(0.85))
                    .lineLimit(1).minimumScaleFactor(0.75).displayTrim(14)
                Spacer(minLength: 0)
                if let tag { SkewTag(text: tag, color: glow, textColor: glow == Theme.lime ? Theme.ink : .white) }
            }
            Group {
                if let value {
                    CountingText(value: value, format: format)
                } else {
                    Text("—")
                }
            }
            .font(.display(26)).monospacedDigit().foregroundStyle(valueTint)
            .lineLimit(1).minimumScaleFactor(0.55).displayTrim(26)
            .padding(.top, 14)
            Text(sub).font(.geist(12)).foregroundStyle(Theme.muted).lineLimit(2).minimumScaleFactor(0.85)
                .fixedSize(horizontal: false, vertical: true)
                .padding(.top, 8)
        }
        .frame(maxWidth: .infinity, minHeight: 92, alignment: .topLeading)
        .surface(radius: 20)
    }
}

/// A capsule that grows to `fraction` of the width the first time it scrolls into view (and
/// again when the page comes back), with its glow.
struct GrowBar: View {
    var fraction: Double
    var color: Color
    var height: CGFloat = 8
    var delay: Double = 0
    var gradient = true
    @Environment(\.accessibilityReduceMotion) private var reduceMotion
    @State private var grown = false

    var body: some View {
        GeometryReader { geo in
            ZStack(alignment: .leading) {
                Capsule().fill(Theme.surface2)
                Capsule()
                    .fill(gradient ? AnyShapeStyle(LinearGradient(colors: [color.opacity(0.5), color], startPoint: .leading, endPoint: .trailing)) : AnyShapeStyle(color))
                    .frame(width: max(height, geo.size.width * max(0, min(1, fraction))) * (grown || reduceMotion ? 1 : 0.001))
            }
        }
        .frame(height: height)
        .onFirstVisible { grow() }
        .onReplay {
            grown = false
            grow()
        }
    }

    private func grow() {
        guard !reduceMotion else { return }
        withAnimation(.spring(response: 0.9, dampingFraction: 0.82).delay(0.15 + delay)) { grown = true }
    }
}

/// A view that pops in (scale and fade) after `delay` the first time it's visible, for staggered
/// grids of tiles and heatmap cells.
struct PopInOnce: ViewModifier {
    var delay: Double
    @Environment(\.accessibilityReduceMotion) private var reduceMotion
    @State private var shown = false

    func body(content: Content) -> some View {
        content
            .scaleEffect(shown || reduceMotion ? 1 : 0.6)
            .opacity(shown || reduceMotion ? 1 : 0)
            .onFirstVisible {
                guard !shown else { return }
                withAnimation(.spring(response: 0.5, dampingFraction: 0.7).delay(delay)) { shown = true }
            }
            .onReplay {
                guard !reduceMotion else { return }
                shown = false
                withAnimation(.spring(response: 0.5, dampingFraction: 0.7).delay(delay)) { shown = true }
            }
    }
}

extension View {
    func popIn(delay: Double = 0) -> some View { modifier(PopInOnce(delay: delay)) }
}

// MARK: - Page tops (each More page opens differently)

/// Analytics: the big total return over your value line for the last six months, drawing in.
struct ValueLineHero<Below: View>: View {
    var label: String
    var value: Double
    var points: [TimelinePoint]
    @ViewBuilder var below: Below

    var body: some View {
        let tone = value >= 0 ? Theme.lime : Theme.planPink
        let recent = Array(points.suffix(180))
        VStack(alignment: .leading, spacing: 10) {
            MonoLabel(text: label)
            CountingText(value: value, format: { Format.signedMoney($0) })
                .font(.display(60)).monospacedDigit().foregroundStyle(tone)
                .lineLimit(1).minimumScaleFactor(0.5).displayTrim(60)
            if recent.count > 1 {
                let lo = recent.map(\.value).min() ?? 0
                let hi = recent.map(\.value).max() ?? 1
                Chart(recent) { p in
                    AreaMark(x: .value("Day", p.day), yStart: .value("Floor", lo - (hi - lo) * 0.15), yEnd: .value("Value", p.value))
                        .foregroundStyle(LinearGradient(colors: [tone.opacity(0.25), tone.opacity(0)], startPoint: .top, endPoint: .bottom))
                        .interpolationMethod(.monotone)
                    LineMark(x: .value("Day", p.day), y: .value("Value", p.value))
                        .foregroundStyle(tone).lineStyle(StrokeStyle(lineWidth: 2.5)).interpolationMethod(.monotone)
                }
                .chartXAxis(.hidden)
                .chartYAxis(.hidden)
                .chartYScale(domain: (lo - (hi - lo) * 0.15)...(hi + (hi - lo) * 0.05 + 0.01))
                .frame(height: 120)
                .padding(.horizontal, -16)
                .drawIn(duration: 1.4)
                HStack {
                    Text("6 months ago").font(.mono(10)).foregroundStyle(Theme.subtle)
                    Spacer()
                    Text("Now \(Format.money(recent.last?.value ?? 0))").font(.mono(10)).foregroundStyle(Theme.subtle)
                }
            }
            below.padding(.top, 6)
        }
        .padding(.top, 8)
    }
}

/// Gains: what's pulling up against what's pulling down, as a tug of war that grows out from
/// the middle, with the three biggest movers underneath.
struct TugOfWarHero: View {
    var label: String
    var total: Double
    var gains: Double
    var losses: Double
    var leaders: [Gains.Row]
    @Environment(\.accessibilityReduceMotion) private var reduceMotion
    @State private var pulled = false

    var body: some View {
        let sum = max(gains + abs(losses), 0.01)
        let up = gains / sum
        VStack(alignment: .leading, spacing: 16) {
            VStack(alignment: .leading, spacing: 10) {
                MonoLabel(text: label)
                CountingText(value: total, format: { Format.signedMoney($0) })
                    .font(.display(60)).monospacedDigit().foregroundStyle(total >= 0 ? Theme.lime : Theme.planPink)
                    .lineLimit(1).minimumScaleFactor(0.5).displayTrim(60)
            }
            VStack(spacing: 14) {
                GeometryReader { geo in
                    let w = geo.size.width
                    let split = min(max(w * up, 6), w - 6)
                    let g = pulled || reduceMotion ? 1.0 : 0.0
                    ZStack(alignment: .leading) {
                        Capsule().fill(Theme.surface2)
                        // Gains pull left from the split; losses pull right.
                        Capsule().fill(Theme.lime)
                            .frame(width: max(0, split - 2) * g)
                            .offset(x: split - 2 - max(0, split - 2) * g)
                        Capsule().fill(Theme.planPink)
                            .frame(width: max(0, w - split - 2) * g)
                            .offset(x: split + 2)
                        Rectangle().fill(.white).frame(width: 2, height: 24).offset(x: split - 1)
                    }
                }
                .frame(height: 18)
                HStack {
                    VStack(alignment: .leading, spacing: 2) {
                        Text(Format.signedMoney(gains)).font(.display(20)).monospacedDigit().foregroundStyle(Theme.lime).displayTrim(20)
                        MonoLabel(text: "Pulling up")
                    }
                    Spacer()
                    VStack(alignment: .trailing, spacing: 2) {
                        Text(Format.signedMoney(losses)).font(.display(20)).monospacedDigit().foregroundStyle(Theme.planPink).displayTrim(20)
                        MonoLabel(text: "Pulling down")
                    }
                }
            }
            if !leaders.isEmpty {
                HStack(spacing: 10) {
                    ForEach(Array(leaders.prefix(3).enumerated()), id: \.element.id) { i, r in
                        VStack(alignment: .leading, spacing: 6) {
                            HoldingArt(product: r.product, identity: r.identity, cornerRadius: 6, caption: false)
                                .frame(height: 74)
                                .frame(maxWidth: .infinity)
                            Text(r.label).font(.geist(11)).foregroundStyle(Theme.muted).lineLimit(1)
                            Text(Format.signedMoney(r.gain)).font(.geist(13, .semibold)).monospacedDigit().foregroundStyle(Theme.tone(r.gain))
                        }
                        .padding(10)
                        .frame(maxWidth: .infinity, alignment: .leading)
                        .background(Theme.surface, in: RoundedRectangle(cornerRadius: 16, style: .continuous))
                        .overlay(RoundedRectangle(cornerRadius: 16, style: .continuous).strokeBorder(Theme.border))
                        .popIn(delay: 0.3 + Double(i) * 0.1)
                    }
                }
            }
        }
        .padding(.top, 8)
        .onAppear { pull() }
        .onReplay {
            pulled = false
            pull()
        }
    }

    private func pull() {
        guard !reduceMotion else { return }
        withAnimation(.spring(response: 1.0, dampingFraction: 0.7).delay(0.2)) { pulled = true }
    }
}

/// Grading: your three best slabs fanned out like a hand, rising in, with their value below.
struct SlabFanHero: View {
    var slabs: [HoldingView]
    var value: Double
    @Environment(\.accessibilityReduceMotion) private var reduceMotion
    @State private var dealt = false

    var body: some View {
        let top = Array(slabs.prefix(3))
        VStack(spacing: 14) {
            if !top.isEmpty {
                ZStack {
                    // Back to front: second-best left, third right, the best in the middle.
                    ForEach(order(top.count), id: \.self) { i in
                        let angle: Double = top.count == 1 ? 0 : i == 0 ? 0 : i == 1 ? -14 : 14
                        let x: CGFloat = top.count == 1 ? 0 : i == 0 ? 0 : i == 1 ? -92 : 92
                        HoldingArt(product: top[i].product, identity: top[i].identity, caption: false)
                            .frame(width: 128, height: 200)
                            .rotationEffect(.degrees(dealt || reduceMotion ? angle : 0), anchor: .bottom)
                            .offset(x: dealt || reduceMotion ? x : 0, y: dealt || reduceMotion ? (i == 0 ? -6 : 10) : 60)
                            .opacity(dealt || reduceMotion ? 1 : 0)
                            .zIndex(i == 0 ? 2 : 1)
                    }
                }
                .frame(height: 230)
                .frame(maxWidth: .infinity)
            }
            VStack(spacing: 6) {
                MonoLabel(text: slabs.isEmpty ? "No slabs yet" : "Your slabs are worth")
                CountingText(value: value, format: { Format.money($0) })
                    .font(.display(56)).monospacedDigit().foregroundStyle(.white)
                    .lineLimit(1).minimumScaleFactor(0.5).displayTrim(56)
            }
            .frame(maxWidth: .infinity)
        }
        .padding(.top, 8)
        .onAppear { deal() }
        .onReplay {
            dealt = false
            deal()
        }
    }

    private func order(_ n: Int) -> [Int] { n == 1 ? [0] : n == 2 ? [1, 0] : [1, 2, 0] }

    private func deal() {
        guard !reduceMotion else { return }
        withAnimation(.spring(response: 0.8, dampingFraction: 0.72).delay(0.15)) { dealt = true }
    }
}

/// Binder: a page of your cards lying open at an angle, with how many singles you have.
struct BinderPageHero: View {
    var cards: [HoldingView]
    var count: Double
    var sets: Int
    @Environment(\.accessibilityReduceMotion) private var reduceMotion
    @State private var opened = false

    var body: some View {
        VStack(alignment: .leading, spacing: 18) {
            HStack(alignment: .bottom) {
                VStack(alignment: .leading, spacing: 8) {
                    MonoLabel(text: "Singles in your binder")
                    CountingText(value: count, format: { "\(Int($0.rounded()))" })
                        .font(.display(64)).monospacedDigit().displayTrim(64)
                }
                Spacer()
                VStack(alignment: .trailing, spacing: 4) {
                    Text("\(sets)").font(.display(30)).monospacedDigit().foregroundStyle(Theme.lime).displayTrim(30)
                    MonoLabel(text: sets == 1 ? "Set" : "Sets")
                }
            }
            // Eight pockets, the page tipped back as if lying open on a table.
            LazyVGrid(columns: Array(repeating: GridItem(.flexible(), spacing: 6), count: 4), spacing: 6) {
                ForEach(0..<8, id: \.self) { i in
                    ZStack {
                        RoundedRectangle(cornerRadius: 6, style: .continuous).fill(Color.white.opacity(0.04))
                        if i < cards.count {
                            HoldingArt(product: cards[i].product, identity: cards[i].identity, cornerRadius: 4, caption: false).padding(3)
                        }
                    }
                    .aspectRatio(63 / 88, contentMode: .fit)
                }
            }
            .padding(10)
            .background(
                RoundedRectangle(cornerRadius: 16, style: .continuous)
                    .fill(LinearGradient(colors: [Color(hex: 0x1C1C20), Color(hex: 0x121214)], startPoint: .top, endPoint: .bottom))
            )
            .overlay(RoundedRectangle(cornerRadius: 16, style: .continuous).strokeBorder(Theme.borderStrong))
            .padding(.horizontal, 12)
            .rotation3DEffect(.degrees(opened || reduceMotion ? 22 : 75), axis: (x: 1, y: 0, z: 0), anchor: .bottom, perspective: 0.6)
            .opacity(opened || reduceMotion ? 1 : 0)
        }
        .padding(.top, 8)
        .onAppear { open() }
        .onReplay {
            opened = false
            open()
        }
    }

    private func open() {
        guard !reduceMotion else { return }
        withAnimation(.spring(response: 1.0, dampingFraction: 0.8).delay(0.1)) { opened = true }
    }
}
