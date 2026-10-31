import Charts
import SwiftUI

// Shared pieces for the More pages (Analytics, Gains, Grading, Master Sets), so they share Home's
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
            .frame(height: 24)
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
            Text(sub).font(.geist(12)).foregroundStyle(Theme.muted).lineLimit(1).minimumScaleFactor(0.8)
                .padding(.top, 8)
        }
        // One fixed size for every tile, tag or not.
        .frame(maxWidth: .infinity, alignment: .topLeading)
        .frame(height: 96, alignment: .top)
        .surface(radius: 16)
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

/// Analytics: laid out like the top of Collection: label, the big total return, a line under it,
/// the last six months drawing in, then whatever goes below (glass tiles), on the same lit grid.
struct ValueLineHero<Line: View, Below: View>: View {
    var label: String
    var value: Double
    var points: [TimelinePoint]
    @ViewBuilder var line: Line
    @ViewBuilder var below: Below

    var body: some View {
        let recent = Array(points.suffix(180))
        let change = (recent.last?.value ?? 0) - (recent.first?.value ?? 0)
        VStack(alignment: .leading, spacing: 18) {
            VStack(alignment: .leading, spacing: 8) {
                MonoLabel(text: label)
                CountingText(value: value, format: { Format.signedMoney($0) })
                    .font(.display(56)).monospacedDigit().foregroundStyle(value >= 0 ? Theme.lime : Theme.planPink)
                    .lineLimit(1).minimumScaleFactor(0.5).displayTrim(56)
                line
            }
            .padding(.top, 8)
            if recent.count > 1 {
                VStack(alignment: .leading, spacing: 6) {
                    Sparkline(points: recent, color: change < 0 ? Theme.planPink : Theme.lime).frame(height: 54)
                    HStack {
                        MonoLabel(text: "Last 6 months")
                        Spacer()
                        Text(Format.signedMoney(change)).font(.geist(12, .semibold)).monospacedDigit().foregroundStyle(Theme.tone(change))
                    }
                }
            }
            below
        }
        .background(alignment: .top) {
            DotBackdrop().padding(.horizontal, -16).padding(.top, -160).padding(.bottom, -40)
        }
    }
}

/// Gains: what's pulling up against what's pulling down, as a tug of war that grows out from
/// the middle, with the three biggest movers underneath.
struct TugOfWarHero: View {
    var label: String
    var hint: String
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
            // Laid out like the top of Collection: label, big figure, a line under it.
            VStack(alignment: .leading, spacing: 8) {
                MonoLabel(text: label)
                CountingText(value: total, format: { Format.signedMoney($0) })
                    .font(.display(56)).monospacedDigit().foregroundStyle(total >= 0 ? Theme.lime : Theme.planPink)
                    .lineLimit(1).minimumScaleFactor(0.5).displayTrim(56)
                Text(hint).font(.geist(13)).foregroundStyle(Theme.muted)
            }
            .padding(.top, 8)
            VStack(spacing: 14) {
                // The same bar as Allocation: two thin capsules with a gap, growing in.
                GeometryReader { geo in
                    let g = pulled || reduceMotion ? 1.0 : 0.0
                    let usable = geo.size.width - (losses < 0 && gains > 0 ? 3 : 0)
                    HStack(spacing: 3) {
                        if gains > 0 {
                            Capsule().fill(Theme.lime)
                                .frame(width: max(6, usable * up * g))
                                .shadow(color: Theme.lime.opacity(0.5), radius: 6)
                        }
                        if losses < 0 {
                            Capsule().fill(Theme.planPink)
                                .frame(width: max(6, usable * (1 - up) * g))
                                .shadow(color: Theme.planPink.opacity(0.5), radius: 6)
                        }
                    }
                }
                .frame(height: 10)
                // Glass stat tiles, like Collection's.
                HStack(spacing: 8) {
                    GlassStat(label: "Pulling up", value: Format.signedMoney(gains), tint: gains > 0 ? Theme.up : .white)
                    GlassStat(label: "Pulling down", value: Format.signedMoney(losses), tint: losses < 0 ? Theme.down : .white)
                }
            }
            if !leaders.isEmpty {
                HStack(spacing: 10) {
                    ForEach(Array(leaders.prefix(3).enumerated()), id: \.element.id) { i, r in
                        VStack(alignment: .leading, spacing: 6) {
                            HoldingArt(product: r.product, identity: r.identity, cornerRadius: 3, caption: false)
                                .frame(height: 74)
                                .frame(maxWidth: .infinity)
                            Text(r.label).font(.geist(11)).foregroundStyle(Theme.muted).lineLimit(1)
                            Text(Format.signedMoney(r.gain)).font(.geist(13, .semibold)).monospacedDigit().foregroundStyle(Theme.tone(r.gain))
                        }
                        .padding(10)
                        .frame(maxWidth: .infinity, alignment: .leading)
                        .background(Theme.surface, in: RoundedRectangle(cornerRadius: 12, style: .continuous))
                        .overlay(RoundedRectangle(cornerRadius: 12, style: .continuous).strokeBorder(Theme.border))
                        .popIn(delay: 0.3 + Double(i) * 0.1)
                    }
                }
            }
        }
        .background(alignment: .top) {
            DotBackdrop().padding(.horizontal, -16).padding(.top, -160).padding(.bottom, -40)
        }
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

/// Grading: laid out like the top of Collection (label, big figure, a line under it, glass
/// tiles) with your three best slabs dealt into a fan beside the figure, on the same lit grid.
struct SlabFanHero<Line: View, Below: View>: View {
    var slabs: [HoldingView]
    var value: Double
    @ViewBuilder var line: Line
    @ViewBuilder var below: Below
    @Environment(\.accessibilityReduceMotion) private var reduceMotion
    @State private var dealt = false

    var body: some View {
        let top = Array(slabs.prefix(3))
        VStack(alignment: .leading, spacing: 18) {
            VStack(alignment: .leading, spacing: 8) {
                MonoLabel(text: slabs.isEmpty ? "No slabs yet" : "Your slabs are worth")
                CountingText(value: value, format: { Format.money($0) })
                    .font(.display(56)).monospacedDigit().lineLimit(1).minimumScaleFactor(0.5)
                    .displayTrim(56)
                    .shadow(color: .white.opacity(0.12), radius: 18)
                line
            }
            .padding(.top, 8)
            if !top.isEmpty {
                ZStack {
                    // Back to front: second-best left, third right, the best in the middle.
                    ForEach(order(top.count), id: \.self) { i in
                        let angle: Double = top.count == 1 ? 0 : i == 0 ? 0 : i == 1 ? -12 : 12
                        let x: CGFloat = top.count == 1 ? 0 : i == 0 ? 0 : i == 1 ? -84 : 84
                        HoldingArt(product: top[i].product, identity: top[i].identity, caption: false)
                            .frame(width: 112, height: 176)
                            .rotationEffect(.degrees(dealt || reduceMotion ? angle : 0), anchor: .bottom)
                            .offset(x: dealt || reduceMotion ? x : 0, y: dealt || reduceMotion ? (i == 0 ? -4 : 8) : 50)
                            .opacity(dealt || reduceMotion ? 1 : 0)
                            .zIndex(i == 0 ? 2 : 1)
                    }
                }
                .frame(height: 200)
                .frame(maxWidth: .infinity)
            }
            below
        }
        .background(alignment: .top) {
            DotBackdrop().padding(.horizontal, -16).padding(.top, -160).padding(.bottom, -40)
        }
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

/// A small glass tile: mono label over a figure, like Collection's stat tiles.
struct GlassStat: View {
    var label: String
    var value: String
    var tint: Color = .white
    @Environment(\.onGlassSheet) private var onGlass

    var body: some View {
        VStack(alignment: .leading, spacing: 4) {
            MonoLabel(text: label).lineLimit(1).minimumScaleFactor(0.6)
            Text(value).font(.geist(15, .semibold)).monospacedDigit().foregroundStyle(tint).lineLimit(1).minimumScaleFactor(0.7)
        }
        .padding(.horizontal, 12)
        .padding(.vertical, 10)
        // One height for every tile in a row.
        .frame(maxWidth: .infinity, minHeight: 58, maxHeight: 58, alignment: .leading)
        .modifier(StatBackground(onGlass: onGlass))
    }
}

// MARK: - Dotted backdrop

/// The lit backdrop for the More pages: Collection's lime, pink and blue glows over a field of
/// fine dots instead of the grid, fading out toward the content.
struct DotBackdrop: View {
    var body: some View {
        ZStack {
            DotField()
            RadialGradient(colors: [Theme.lime.opacity(0.2), .clear], center: UnitPoint(x: 0.2, y: 0.42), startRadius: 0, endRadius: 260)
            RadialGradient(colors: [Theme.planPink.opacity(0.16), .clear], center: UnitPoint(x: 0.85, y: 0.2), startRadius: 0, endRadius: 220)
            RadialGradient(colors: [Theme.planBlue.opacity(0.16), .clear], center: UnitPoint(x: 0.75, y: 0.72), startRadius: 0, endRadius: 220)
        }
        .mask(LinearGradient(stops: [.init(color: .black, location: 0), .init(color: .black, location: 0.7), .init(color: .clear, location: 1)],
                             startPoint: .top, endPoint: .bottom))
        .allowsHitTesting(false)
    }
}

/// Tiny dots on an even spacing, each slowly brightening and fading at its own pace, so the
/// field shimmers. One Canvas redrawn about 12 times a second, paused off screen; still with
/// Reduce Motion.
struct DotField: View {
    var spacing: CGFloat = 9
    var radius: CGFloat = 0.75
    @Environment(\.accessibilityReduceMotion) private var reduceMotion
    @State private var onScreen = true

    var body: some View {
        TimelineView(.animation(minimumInterval: 1 / 12, paused: reduceMotion || !onScreen)) { context in
            let t = reduceMotion ? 0 : context.date.timeIntervalSinceReferenceDate
            Canvas { ctx, size in
                let cols = Int(size.width / spacing) + 1
                let rows = Int(size.height / spacing) + 1
                // Dots grouped into a few brightness levels, so each frame fills 8 paths, not thousands.
                var levels = Array(repeating: Path(), count: 8)
                for row in 0..<rows {
                    for col in 0..<cols {
                        // A fixed random phase and pace per dot (a cheap hash of its place).
                        let seed = Double((col &* 73_856_093) ^ (row &* 19_349_663)) .truncatingRemainder(dividingBy: 1000) / 1000
                        let pace = 0.35 + abs(seed) * 0.9
                        let wave = 0.5 + 0.5 * sin(t * pace + abs(seed) * 40)
                        let level = min(7, Int(wave * wave * 8))
                        let p = CGPoint(x: CGFloat(col) * spacing + spacing / 2, y: CGFloat(row) * spacing + spacing / 2)
                        levels[level].addEllipse(in: CGRect(x: p.x - radius, y: p.y - radius, width: radius * 2, height: radius * 2))
                    }
                }
                for (i, path) in levels.enumerated() {
                    ctx.fill(path, with: .color(.white.opacity(0.04 + Double(i) / 7 * 0.32)))
                }
            }
        }
        .onVisibilityChange { onScreen = $0 }
    }
}

/// Glass on a page; a faint fill on a glass sheet (glass on glass turns blotchy).
private struct StatBackground: ViewModifier {
    var onGlass: Bool
    func body(content: Content) -> some View {
        if onGlass { content.sheetPanel(radius: 14) } else { content.liquidGlass(in: RoundedRectangle(cornerRadius: 14, style: .continuous)) }
    }
}
