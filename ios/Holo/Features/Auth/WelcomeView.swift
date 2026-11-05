import SwiftUI

/// The welcome, before sign-in: three swipeable pages (what the app does, in big moving
/// pictures made from the demo collection), then the ways in: Sign in with Apple, email, or the
/// demo without an account. Seen once; a signed-out app later opens on the sign-in form.
struct WelcomeView: View {
    /// A look from Account: the buttons close it and nothing is remembered.
    var preview = false
    /// "Continue with email": show the sign-in form.
    var onEmail: () -> Void
    /// "Try the demo": the made-up collection, no account.
    var onDemo: () -> Void
    @State private var page = 0
    @State private var error: String?
    @Environment(\.accessibilityReduceMotion) private var reduceMotion

    private let last = 2

    var body: some View {
        ZStack {
            Theme.background.ignoresSafeArea()
            GeometryReader { geo in
                // Each page's picture takes about the top half of the screen.
                let graphic = min(geo.size.height * 0.5, 430)
                VStack(spacing: 0) {
                    header
                    pages(graphicHeight: graphic)
                    dots
                    footer
                        .padding(.horizontal, 24)
                        .padding(.bottom, 12)
                }
                .frame(width: geo.size.width, height: geo.size.height)
            }
        }
        .foregroundStyle(.white)
    }

    private var header: some View {
        HStack {
            Text("Lucent").font(.geist(17, .semibold)).tracking(-0.3)
            Spacer()
            if page < last {
                Button("Skip") { go(to: last) }
                    .font(.geist(15, .medium)).foregroundStyle(Theme.muted)
                    .accessibilityIdentifier("welcome-skip")
            }
        }
        .padding(.horizontal, 24)
        .padding(.top, 12)
        .padding(.bottom, 8)
    }

    private func pages(graphicHeight: CGFloat) -> some View {
        TabView(selection: $page) {
            WelcomePage(title: "See what your collection is worth", line: "Every card and box you own, priced daily, with how it has moved.", graphicHeight: graphicHeight) {
                WelcomeGrid()
            }
            .tag(0)
            WelcomePage(title: "Scan a card, know its price", line: "Point the camera at a card and its name and market price appear on it.", graphicHeight: graphicHeight) {
                WelcomeScanLoop()
            }
            .tag(1)
            WelcomePage(title: "Watch it add up", line: "Prices update daily; gains and losses are worked out for you.", graphicHeight: graphicHeight) {
                WelcomeSum()
            }
            .tag(2)
        }
        .tabViewStyle(.page(indexDisplayMode: .never))
    }

    private var dots: some View {
        HStack(spacing: 6) {
            ForEach(0 ... last, id: \.self) { i in
                Capsule().fill(i == page ? Theme.lime : Color.white.opacity(0.18))
                    .frame(width: i == page ? 18 : 6, height: 6)
            }
        }
        .animation(reduceMotion ? nil : .snappy(duration: 0.25), value: page)
        .padding(.bottom, 18)
        .accessibilityHidden(true)
    }

    /// Continue on the first pages; the ways in on the last.
    @ViewBuilder private var footer: some View {
        if page < last {
            VStack(spacing: 14) {
                Button("Continue") { go(to: page + 1) }
                    .buttonStyle(Button3D(kind: .lime))
                    .accessibilityIdentifier("welcome-continue")
                // Same height as the last page's three rows, so the pages don't jump.
                Color.clear.frame(height: 50 + 14 + 22)
            }
        } else {
            VStack(spacing: 14) {
                if preview {
                    // Already signed in: a look-alike that just closes the preview.
                    Button { onEmail() } label: { Label("Sign in with Apple", systemImage: "apple.logo") }
                        .buttonStyle(Button3D(kind: .light))
                } else {
                    AppleSignInButton(onSuccess: { Onboarding.shared.welcomeSeen = true }) { message in error = message }
                }
                Button("Continue with email") {
                    if !preview { Onboarding.shared.welcomeSeen = true }
                    onEmail()
                }
                .buttonStyle(Button3D(kind: .dark))
                .accessibilityIdentifier("welcome-email")
                Button("Try the demo") {
                    if !preview { Onboarding.shared.welcomeSeen = true }
                    onDemo()
                }
                .font(.geist(15, .medium)).foregroundStyle(Theme.muted)
                .frame(height: 22)
                .accessibilityIdentifier("welcome-demo")
                if let error {
                    Text(error).font(.geist(13)).foregroundStyle(Theme.down).multilineTextAlignment(.center)
                }
            }
        }
    }

    private func go(to next: Int) {
        withAnimation(reduceMotion ? nil : .snappy(duration: 0.3)) { page = min(max(next, 0), last) }
    }
}

/// One welcome page: the picture up top (edge to edge, about half the screen), then the
/// heading and one line.
private struct WelcomePage<Picture: View>: View {
    var title: String
    var line: String
    var graphicHeight: CGFloat
    @ViewBuilder var picture: Picture

    var body: some View {
        VStack(spacing: 0) {
            picture
                .frame(maxWidth: .infinity)
                .frame(height: graphicHeight)
                .clipped()
            VStack(spacing: 10) {
                // Centered, so a plain balanced-ish Text rather than the left-flowing DisplayText.
                Text(title).font(.display(32)).tracking(-1).multilineTextAlignment(.center)
                    .fixedSize(horizontal: false, vertical: true)
                Text(line).font(.geist(15)).foregroundStyle(Theme.muted).multilineTextAlignment(.center)
                    .fixedSize(horizontal: false, vertical: true)
            }
            .padding(.horizontal, 32)
            .padding(.top, 22)
            Spacer(minLength: 0)
        }
    }
}

/// The faint grid with a lime and a pink glow behind a page's picture, fading out top and bottom.
private struct WelcomeBackdrop: View {
    var body: some View {
        ZStack {
            GridPattern()
            RadialGradient(colors: [Theme.lime.opacity(0.2), .clear], center: UnitPoint(x: 0.3, y: 0.55), startRadius: 0, endRadius: 240)
            RadialGradient(colors: [Theme.planPink.opacity(0.14), .clear], center: UnitPoint(x: 0.85, y: 0.3), startRadius: 0, endRadius: 200)
        }
        .mask(LinearGradient(colors: [.clear, .black, .black, .clear], startPoint: .top, endPoint: .bottom))
        .allowsHitTesting(false)
    }
}

// MARK: - Page 1: a grid of cards, fading to black

/// Three columns of demo cards and a couple of sealed wells, edge to edge, the bottom fading
/// into the page. The whole grid drifts slowly up and back (one repeating offset animation).
private struct WelcomeGrid: View {
    private static let slugs = [
        "umbreon-vmax-alt", "es-bb", "pikachu-ex-ss",
        "charizard-ex-151", "giratina-v-alt", "rayquaza-vmax-alt",
        "lugia-v-alt", "cel-upc", "gengar-vmax-alt",
        "charizard-base", "espeon-vmax-alt", "mew-ex-gold",
    ]
    private static let gap: CGFloat = 8
    @State private var drift = false
    @Environment(\.accessibilityReduceMotion) private var reduceMotion

    private var rows: [[DemoData.Item]] {
        let items = Self.slugs.compactMap { slug in DemoData.items.first { $0.slug == slug } }
        var out: [[DemoData.Item]] = []
        var i = 0
        while i < items.count {
            let end = min(i + 3, items.count)
            out.append(Array(items[i ..< end]))
            i = end
        }
        return out
    }

    var body: some View {
        GeometryReader { geo in
            let tileW = (geo.size.width - Self.gap * 2) / 3
            let tileH = tileW * 88 / 63
            VStack(spacing: Self.gap) {
                ForEach(Array(rows.enumerated()), id: \.offset) { _, row in
                    HStack(spacing: Self.gap) {
                        ForEach(row, id: \.slug) { item in
                            WelcomeTile(item: item)
                                .frame(width: tileW, height: tileH)
                        }
                    }
                }
            }
            .frame(width: geo.size.width, alignment: .top)
            .offset(y: drift ? -34 : -10)
        }
        .animation(reduceMotion ? nil : .linear(duration: 14).repeatForever(autoreverses: true), value: drift)
        .mask(fade)
        .onAppear { if !reduceMotion { drift = true } }
        .accessibilityElement(children: .ignore)
        .accessibilityLabel("A grid of cards and boxes from a collection")
    }

    /// Solid over the top, fading to the page background over the bottom 45%.
    private var fade: some View {
        LinearGradient(
            stops: [
                Gradient.Stop(color: .black, location: 0),
                Gradient.Stop(color: .black, location: 0.55),
                Gradient.Stop(color: .clear, location: 1),
            ],
            startPoint: .top, endPoint: .bottom
        )
    }
}

/// One tile of the grid: a card, or a sealed product in its card-shaped well.
private struct WelcomeTile: View {
    var item: DemoData.Item

    var body: some View {
        HoldingArt(product: DemoData.product(item), identity: nil, cornerRadius: 6, caption: false)
    }
}

// MARK: - Page 2: a card being scanned

/// Where the scan loop is at a moment in its 3.2s cycle, worked out from the clock (no state):
/// the brackets snap tight (0–0.6s), the line sweeps (0.6–1.6s), the pill pops in (1.8s) and
/// the tick lands (1.95s), a hold, then everything fades (2.8–3.1s) and it starts over.
private struct ScanPhase {
    static let cycle: Double = 3.2
    /// The still frame under Reduce Motion: everything landed.
    static let still = ScanPhase(t: 2.4)
    var t: Double

    private static func ease(_ x: Double) -> Double {
        let c = min(max(x, 0), 1)
        return 1 - pow(1 - c, 3)
    }

    /// 0 wide and off, 1 tight on the card.
    var snap: Double { Self.ease(t / 0.6) }
    /// Brackets show as soon as the cycle starts and fade with the rest.
    var brackets: Double { min(Self.ease(t / 0.12), fade) }
    /// How far down the card the scan line is, while it sweeps.
    var sweep: Double? {
        guard t >= 0.6, t <= 1.6 else { return nil }
        return (t - 0.6) / 1.0
    }
    var pill: Double { Self.ease((t - 1.8) / 0.3) }
    var tick: Double { Self.ease((t - 1.95) / 0.3) }
    /// 1 until the hold ends, then down to 0.
    var fade: Double { 1 - Self.ease((t - 2.8) / 0.3) }
}

/// A tall dark viewfinder with one demo card in it and the scanner's read playing on loop.
/// The card sits outside the timeline so only the overlays redraw each frame.
private struct WelcomeScanLoop: View {
    @Environment(\.accessibilityReduceMotion) private var reduceMotion

    private var item: DemoData.Item? { DemoData.items.first { $0.slug == "pikachu-ex-ss" } }

    var body: some View {
        GeometryReader { geo in
            let panel = CGSize(width: geo.size.width - 48, height: geo.size.height - 8)
            let card = Self.cardRect(in: panel)
            ZStack(alignment: .topLeading) {
                RoundedRectangle(cornerRadius: 28, style: .continuous)
                    .fill(Color.black)
                    .overlay(RoundedRectangle(cornerRadius: 28, style: .continuous).strokeBorder(Color.white.opacity(0.08), lineWidth: 1))
                if let item {
                    HoldingArt(product: DemoData.product(item), identity: nil, cornerRadius: 8, caption: false)
                        .frame(width: card.width, height: card.height)
                        .shadow(color: .black.opacity(0.5), radius: 14, y: 10)
                        .offset(x: card.minX, y: card.minY)
                }
                if reduceMotion {
                    ScanOverlays(phase: .still, card: card, size: panel, price: item?.now ?? 0)
                } else {
                    TimelineView(.animation) { context in
                        let t = context.date.timeIntervalSinceReferenceDate.truncatingRemainder(dividingBy: ScanPhase.cycle)
                        ScanOverlays(phase: ScanPhase(t: t), card: card, size: panel, price: item?.now ?? 0)
                    }
                }
            }
            .frame(width: panel.width, height: panel.height)
            .position(x: geo.size.width / 2, y: geo.size.height / 2)
        }
        .accessibilityElement(children: .ignore)
        .accessibilityLabel("A card being scanned, with its name and price")
    }

    /// The card, about 64% of the panel's width (less on a short screen), a touch below centre
    /// so the pill above it fits.
    private static func cardRect(in panel: CGSize) -> CGRect {
        var h = panel.width * 0.64 * 88 / 63
        h = min(h, panel.height * 0.7)
        let w = h * 63 / 88
        let x = (panel.width - w) / 2
        let y = (panel.height - h) / 2 + 14
        return CGRect(x: x, y: y, width: w, height: h)
    }
}

/// The scanner's read over the card at one moment: brackets, scan line, pill and tick.
private struct ScanOverlays: View {
    var phase: ScanPhase
    var card: CGRect
    var size: CGSize
    var price: Double

    var body: some View {
        let snap = phase.snap
        let inset = CGFloat(30 - 24 * snap)
        let dx = CGFloat(14 * (1 - snap))
        let dy = CGFloat(-10 * (1 - snap))
        let box = card.insetBy(dx: -inset, dy: -inset).offsetBy(dx: dx, dy: dy)
        ZStack(alignment: .topLeading) {
            CornerBracketsShape(rect: box, arm: 26)
                .stroke(Theme.lime, style: StrokeStyle(lineWidth: 4, lineCap: .round, lineJoin: .round))
                .opacity(phase.brackets)
            if let s = phase.sweep {
                ScanLine(width: card.width + 16)
                    .offset(x: card.minX - 8, y: card.minY + CGFloat(s) * card.height - 24)
            }
            ScanPill(price: price)
                .scaleEffect(0.85 + 0.15 * phase.pill)
                .opacity(phase.pill * phase.fade)
                .position(x: card.midX, y: card.minY - 26)
            ScanTick()
                .scaleEffect(1.6 - 0.6 * phase.tick)
                .opacity(phase.tick * phase.fade)
                .position(x: card.maxX - 10, y: card.minY + 10)
        }
        .frame(width: size.width, height: size.height)
    }
}

/// Four L-shaped corner marks around a rectangle, like the scanner's guide.
private struct CornerBracketsShape: Shape {
    var rect: CGRect
    var arm: CGFloat

    func path(in _: CGRect) -> Path {
        var p = Path()
        let r = rect
        p.move(to: CGPoint(x: r.minX, y: r.minY + arm))
        p.addLine(to: CGPoint(x: r.minX, y: r.minY))
        p.addLine(to: CGPoint(x: r.minX + arm, y: r.minY))
        p.move(to: CGPoint(x: r.maxX - arm, y: r.minY))
        p.addLine(to: CGPoint(x: r.maxX, y: r.minY))
        p.addLine(to: CGPoint(x: r.maxX, y: r.minY + arm))
        p.move(to: CGPoint(x: r.maxX, y: r.maxY - arm))
        p.addLine(to: CGPoint(x: r.maxX, y: r.maxY))
        p.addLine(to: CGPoint(x: r.maxX - arm, y: r.maxY))
        p.move(to: CGPoint(x: r.minX + arm, y: r.maxY))
        p.addLine(to: CGPoint(x: r.minX, y: r.maxY))
        p.addLine(to: CGPoint(x: r.minX, y: r.maxY - arm))
        return p
    }
}

/// The lime scan line with a soft trail above it (a gradient, not a shadow: cheap per frame).
private struct ScanLine: View {
    var width: CGFloat

    var body: some View {
        VStack(spacing: 0) {
            LinearGradient(colors: [.clear, Theme.lime.opacity(0.35)], startPoint: .top, endPoint: .bottom)
                .frame(height: 22)
            Rectangle().fill(Theme.lime).frame(height: 2)
        }
        .frame(width: width)
    }
}

/// The live read: name, number and price in a dark pill.
private struct ScanPill: View {
    var price: Double

    var body: some View {
        HStack(spacing: 6) {
            Text("Pikachu ex").font(.geist(13, .semibold)).foregroundStyle(.white)
            Text("#238").font(.mono(11)).foregroundStyle(Theme.muted)
            Text(Format.money(price)).font(.geist(13, .bold)).monospacedDigit().foregroundStyle(.white)
        }
        .padding(.horizontal, 12)
        .frame(height: 30)
        .background(Capsule().fill(Color.black.opacity(0.72)))
        .overlay(Capsule().strokeBorder(Color.white.opacity(0.14), lineWidth: 1))
    }
}

/// The small lime tick that lands on a recognised card.
private struct ScanTick: View {
    var body: some View {
        Image(systemName: "checkmark")
            .font(.system(size: 13, weight: .bold))
            .foregroundStyle(Theme.ink)
            .frame(width: 28, height: 28)
            .background(Circle().fill(Theme.lime))
    }
}

// MARK: - Page 3: numbers adding up

private struct SumLine {
    var name: String
    var price: Double
}

/// A dark glass panel where five holdings slide in one after another, the total counts up to
/// their sum and a lime gain tag lands. Loops every 5s: one periodic tick gives a new phase,
/// which rebuilds the panel so its entrances play again.
private struct WelcomeSum: View {
    private static let start = Date()
    @Environment(\.accessibilityReduceMotion) private var reduceMotion

    var body: some View {
        ZStack {
            WelcomeBackdrop()
            if reduceMotion {
                SumPanel(animated: false)
            } else {
                TimelineView(.periodic(from: Self.start, by: 5)) { context in
                    let phase = Int(context.date.timeIntervalSince(Self.start) / 5 + 0.5)
                    SumPanel(animated: true).id(phase)
                }
            }
        }
        .accessibilityElement(children: .ignore)
        .accessibilityLabel("Five holdings adding up to \(Format.money(SumPanel.total)), up 12.4% this month")
    }
}

private struct SumPanel: View {
    var animated: Bool

    static let lines: [SumLine] = [
        SumLine(name: "Umbreon VMAX", price: 1537),
        SumLine(name: "Charizard ex", price: 371),
        SumLine(name: "Booster box", price: 154),
        SumLine(name: "Giratina V", price: 318),
        SumLine(name: "Lugia V", price: 262),
    ]
    static let total: Double = lines.reduce(0.0) { $0 + $1.price }
    /// Each line lands this long after the one before.
    static let step: Double = 0.3

    var body: some View {
        VStack(alignment: .leading, spacing: 10) {
            ForEach(Array(Self.lines.enumerated()), id: \.offset) { i, line in
                SumRow(line: line, delay: Double(i) * Self.step, animated: animated)
            }
            Rectangle().fill(Color.white.opacity(0.12)).frame(height: 1).padding(.vertical, 4)
            SumTotal(delay: Double(Self.lines.count) * Self.step + 0.1, animated: animated)
        }
        .padding(.horizontal, 22)
        .padding(.vertical, 20)
        .frame(maxWidth: .infinity)
        .liquidGlass(in: RoundedRectangle(cornerRadius: 28, style: .continuous))
        .padding(.horizontal, 24)
    }
}

/// One holding's line, sliding in from the right after its delay.
private struct SumRow: View {
    var line: SumLine
    var delay: Double
    var animated: Bool
    @State private var shown: Bool

    init(line: SumLine, delay: Double, animated: Bool) {
        self.line = line
        self.delay = delay
        self.animated = animated
        _shown = State(initialValue: !animated)
    }

    var body: some View {
        HStack {
            Text(line.name).font(.geist(16, .medium))
            Spacer()
            Text(Format.money(line.price)).font(.geist(16, .semibold)).monospacedDigit()
        }
        .opacity(shown ? 1 : 0)
        .offset(x: shown ? 0 : 28)
        .onAppear {
            guard animated, !shown else { return }
            withAnimation(.easeOut(duration: 0.45).delay(delay)) { shown = true }
        }
    }
}

/// The total counting up to the sum, then the gain tag landing beside it.
private struct SumTotal: View {
    var delay: Double
    var animated: Bool
    @State private var shown: Bool
    @State private var tagged: Bool

    init(delay: Double, animated: Bool) {
        self.delay = delay
        self.animated = animated
        _shown = State(initialValue: !animated)
        _tagged = State(initialValue: !animated)
    }

    var body: some View {
        HStack(alignment: .lastTextBaseline) {
            VStack(alignment: .leading, spacing: 2) {
                MonoLabel(text: "Worth today")
                CountingText(value: SumPanel.total, format: { Format.money($0) }, duration: 1.3, delay: animated ? delay : 0)
                    .font(.display(40)).tracking(-1.4).monospacedDigit()
                    .foregroundStyle(Theme.lime)
                    .lineLimit(1).minimumScaleFactor(0.7)
                    .displayTrim(40)
            }
            .opacity(shown ? 1 : 0)
            Spacer()
            SkewTag(text: "+12.4% this month")
                .scaleEffect(tagged ? 1 : 1.5)
                .opacity(tagged ? 1 : 0)
        }
        .onAppear {
            guard animated, !shown else { return }
            withAnimation(.easeOut(duration: 0.4).delay(delay)) { shown = true }
            withAnimation(.spring(response: 0.35, dampingFraction: 0.6).delay(delay + 1.4)) { tagged = true }
        }
    }
}
