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
            WelcomePage(
                title: "See what your collection is worth",
                line: "Every card you own, priced daily, with how it\u{00A0}has\u{00A0}moved.",
                graphicHeight: graphicHeight
            ) {
                WelcomeGrid()
            }
            .tag(0)
            WelcomePage(
                title: "Scan a card, know its price",
                line: "Point the camera at a card. Its name and price appear\u{00A0}on\u{00A0}it.",
                graphicHeight: graphicHeight
            ) {
                WelcomeScanLoop()
            }
            .tag(1)
            WelcomePage(
                title: "Make deals that add up",
                line: "Add what's coming in and going out. The cash and your profit are\u{00A0}worked\u{00A0}out.",
                graphicHeight: graphicHeight
            ) {
                WelcomeDeal()
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
                // Balanced lines (no lone word at the end), centred, sitting tight on each other.
                DisplayText(text: title, size: 32, lineGap: -0.07, alignment: .center)
                    .frame(maxWidth: .infinity)
                Text(line).font(.geist(16)).foregroundStyle(Theme.muted).multilineTextAlignment(.center)
                    .fixedSize(horizontal: false, vertical: true)
            }
            .padding(.horizontal, 32)
            .padding(.top, 22)
            Spacer(minLength: 0)
        }
    }
}

/// The app's lit grid (like Explore's) behind a page's picture: lime, blue and pink glows over
/// the faint grid, fading out top and bottom.
private struct WelcomeBackdrop: View {
    var body: some View {
        ZStack {
            GridPattern(step: 36, opacity: 0.05)
            RadialGradient(colors: [Theme.lime.opacity(0.22), .clear], center: UnitPoint(x: 0.2, y: 0.45), startRadius: 0, endRadius: 250)
            RadialGradient(colors: [Theme.planBlue.opacity(0.2), .clear], center: UnitPoint(x: 0.9, y: 0.6), startRadius: 0, endRadius: 230)
            RadialGradient(colors: [Theme.planPink.opacity(0.16), .clear], center: UnitPoint(x: 0.65, y: 0.1), startRadius: 0, endRadius: 200)
        }
        .mask(LinearGradient(colors: [.clear, .black, .black, .clear], startPoint: .top, endPoint: .bottom))
        .allowsHitTesting(false)
    }
}

// MARK: - Page 1: columns of cards drifting past, and what they're worth

/// Three full-bleed columns of demo cards (singles with real art only), each drifting on its
/// own: the outer two up, the middle one down, at slightly different speeds and out of step, so
/// the grid feels alive. Each column is its list of cards stacked three times and loops by one
/// list's height, so there's never a gap: one repeating offset animation per column, nothing
/// per frame. The bottom fades into the page, and a glass pill over it counts up the worth.
private struct WelcomeGrid: View {
    private static let gap: CGFloat = 8
    /// How long one column takes to travel one list's height, per column.
    private static let durations: [Double] = [22, 26, 24]
    /// Where each column starts in its loop (a share of one list's height), so they never line up.
    private static let phases: [CGFloat] = [0.15, 0.55, 0.35]
    /// The middle column drifts down; the others up.
    private static let down: [Bool] = [false, true, false]
    @State private var drift = false
    @Environment(\.accessibilityReduceMotion) private var reduceMotion

    /// Singles with card art, dealt round-robin into three columns.
    private static let columns: [[DemoData.Item]] = {
        let cards = DemoData.items.filter { !$0.sealed && $0.image != nil }
        var out: [[DemoData.Item]] = [[], [], []]
        for (i, item) in cards.enumerated() { out[i % 3].append(item) }
        return out
    }()

    var body: some View {
        GeometryReader { geo in
            let tileW = (geo.size.width - Self.gap * 2) / 3
            let tileH = tileW * 88 / 63
            HStack(alignment: .top, spacing: Self.gap) {
                ForEach(0 ..< 3, id: \.self) { i in
                    column(i, tileW: tileW, tileH: tileH)
                }
            }
            .frame(width: geo.size.width, height: geo.size.height, alignment: .top)
            .clipped()
        }
        // Small tiles: thumbnails, decoded off the main thread (30 tiles share 10 pictures).
        .imageMaxPixel(360)
        .mask(fade)
        .overlay(alignment: .bottom) { WelcomeWorthPill().padding(.bottom, 10) }
        .onAppear { if !reduceMotion { drift = true } }
        .accessibilityElement(children: .ignore)
        .accessibilityLabel("Columns of cards from a collection, worth \(Format.money(WelcomeWorthPill.worth)) today")
    }

    /// One column: its cards three times over, moving by one list's height and starting over.
    private func column(_ i: Int, tileW: CGFloat, tileH: CGFloat) -> some View {
        let items = Self.columns[i]
        let listH = CGFloat(items.count) * (tileH + Self.gap)
        let from = -listH * Self.phases[i]
        let to = Self.down[i] ? from + listH : from - listH
        return VStack(spacing: Self.gap) {
            ForEach(0 ..< 3, id: \.self) { _ in
                ForEach(items, id: \.slug) { item in
                    WelcomeTile(item: item).frame(width: tileW, height: tileH)
                }
            }
        }
        .frame(width: tileW, alignment: .top)
        // Going down starts a list higher so there's always card above the top edge.
        .offset(y: Self.down[i] ? (drift ? from : from - listH) : (drift ? to : from))
        .animation(reduceMotion ? nil : .linear(duration: Self.durations[i]).repeatForever(autoreverses: false), value: drift)
    }

    /// Solid over the top, fading to the page background over the bottom 40%.
    private var fade: some View {
        LinearGradient(
            stops: [
                Gradient.Stop(color: .black, location: 0),
                Gradient.Stop(color: .black, location: 0.6),
                Gradient.Stop(color: .clear, location: 1),
            ],
            startPoint: .top, endPoint: .bottom
        )
    }
}

/// One card of the grid.
private struct WelcomeTile: View {
    var item: DemoData.Item

    var body: some View {
        // A dark card-shaped well sits under the art, so a tile is never blank while its picture
        // is still arriving (the grid is the first thing a new person sees).
        RoundedRectangle(cornerRadius: 6, style: .continuous)
            .fill(Theme.well)
            .overlay(HoldingArt(product: DemoData.product(item), identity: nil, cornerRadius: 6, caption: false))
            .clipShape(RoundedRectangle(cornerRadius: 6, style: .continuous))
    }
}

/// The glass pill over the grid: "WORTH TODAY", the lime figure counting up, and a small lime
/// tag with today's move. Still, apart from the one count-up.
private struct WelcomeWorthPill: View {
    static let worth: Double = 3834.6

    var body: some View {
        HStack(spacing: 12) {
            VStack(alignment: .leading, spacing: 2) {
                MonoLabel(text: "Worth today")
                CountingText(value: Self.worth, format: { Format.money($0) }, duration: 1.4, delay: 0.3)
                    .font(.display(30)).tracking(-1).monospacedDigit()
                    .foregroundStyle(Theme.lime)
                    .lineLimit(1).minimumScaleFactor(0.7)
                    .displayTrim(30)
            }
            SkewTag(text: "+1.2% today", icon: "arrow.up.right")
        }
        .padding(.leading, 18)
        .padding(.trailing, 14)
        .padding(.vertical, 12)
        .liquidGlass(in: Capsule())
    }
}

// MARK: - Page 2: cards being scanned, one after another

/// Where one card's scan is in its 3.5s turn, from the clock (no state). Local time `u` runs
/// from -0.5 (sliding in from the right, during the previous card's exit) to 3.5: the brackets
/// snap on (0.45–0.95), the line sweeps and the edge glows (0.95–1.75), the pill pops (1.9),
/// the tick lands (2.05), a hold, then it slides out to the left (2.95–3.5).
private struct ScanPhase {
    static let cycle: Double = 3.5
    /// The still frame under Reduce Motion: the card landed, brackets and pill on it.
    static let still = ScanPhase(u: 2.6)
    var u: Double

    private static func clamp(_ x: Double) -> Double { min(max(x, 0), 1) }
    /// Ease out (cubic).
    private static func ease(_ x: Double) -> Double {
        let c = clamp(x)
        return 1 - pow(1 - c, 3)
    }
    /// Ease out with a touch of overshoot, like a spring settling.
    private static func back(_ x: Double) -> Double {
        let c = clamp(x) - 1
        return 1 + 2.4 * c * c * c + 1.4 * c * c
    }

    /// Where the card is across the page: 1 = a page to the right, 0 = in place, -1 = a page left.
    var slide: Double {
        if u < 0 { return 1 - Self.back((u + 0.5) / 0.5) }
        if u > 2.95 { return -Self.ease((u - 2.95) / 0.55) }
        return 0
    }
    /// 0 wide and off the card, 1 tight on it.
    var snap: Double { Self.ease((u - 0.45) / 0.5) }
    var brackets: Double { min(Self.ease((u - 0.45) / 0.12), leaving) }
    /// How far down the card the scan line is, while it sweeps.
    var sweep: Double? {
        guard u >= 0.95, u <= 1.75 else { return nil }
        return (u - 0.95) / 0.8
    }
    /// The lime edge: up as the line sweeps, gone again once the tick has landed.
    var glow: Double { min(Self.ease((u - 1.0) / 0.5), 1 - Self.ease((u - 2.0) / 0.6)) }
    var pill: Double { Self.ease((u - 1.9) / 0.3) }
    var tick: Double { Self.ease((u - 2.05) / 0.3) }
    /// The read's overlays fade as the card leaves.
    var leaving: Double { 1 - Self.ease((u - 2.95) / 0.3) }
    /// The card itself is drawn while it's anywhere on the page.
    var onPage: Bool { u > -0.5 && u < 3.5 }
}

/// What the scanner reads off one demo card.
private struct ScanCard {
    var item: DemoData.Item
    var name: String

    var number: String {
        let n = item.number ?? ""
        let short = n.split(separator: "/").first.map(String.init) ?? n
        return "#" + short
    }

    /// The cards that take turns, with the short names the pill shows.
    static let all: [ScanCard] = {
        let picks: [(String, String)] = [
            ("pikachu-ex-ss", "Pikachu ex"), ("umbreon-vmax-alt", "Umbreon VMAX"),
            ("charizard-ex-151", "Charizard ex"), ("rayquaza-vmax-alt", "Rayquaza VMAX"),
        ]
        var out: [ScanCard] = []
        for pick in picks {
            if let item = DemoData.items.first(where: { $0.slug == pick.0 }) {
                out.append(ScanCard(item: item, name: pick.1))
            }
        }
        return out
    }()
}

/// The app's lit backdrop, a soft lime glow on the floor, and demo cards sliding through the
/// scanner one after another, each read on loop: a card slides in from the right, the brackets
/// snap to it, the line sweeps, its name and price pop up, the tick lands, then it slides out
/// to the left as the next arrives. One timeline; a handful of views moved by offsets and
/// opacities only.
private struct WelcomeScanLoop: View {
    @Environment(\.accessibilityReduceMotion) private var reduceMotion

    var body: some View {
        GeometryReader { geo in
            let card = Self.cardRect(in: geo.size)
            ZStack(alignment: .topLeading) {
                WelcomeBackdrop()
                Ellipse()
                    .fill(Theme.lime.opacity(0.28))
                    .frame(width: card.width * 1.5, height: card.height * 0.5)
                    .blur(radius: 40)
                    .position(x: card.midX, y: card.maxY + 4)
                if reduceMotion {
                    ScanStage(now: ScanPhase.still.u, card: card, size: geo.size)
                } else {
                    TimelineView(.animation) { context in
                        ScanStage(now: context.date.timeIntervalSinceReferenceDate, card: card, size: geo.size)
                    }
                }
            }
            .frame(width: geo.size.width, height: geo.size.height)
            .clipped()
        }
        .accessibilityElement(children: .ignore)
        .accessibilityLabel("Cards being scanned one after another, each with its name and price")
    }

    /// The card, about 72% of the page's width (less on a short screen), a touch below centre
    /// so the pill above it fits.
    private static func cardRect(in size: CGSize) -> CGRect {
        var h = size.width * 0.72 * 88 / 63
        h = min(h, size.height * 0.76)
        let w = h * 63 / 88
        let x = (size.width - w) / 2
        let y = (size.height - h) / 2 + 16
        return CGRect(x: x, y: y, width: w, height: h)
    }
}

/// The scanner at one moment: the card whose turn it is, and the next one on its way in.
private struct ScanStage: View {
    /// Seconds (any clock); under Reduce Motion, the still frame's local time.
    var now: Double
    var card: CGRect
    var size: CGSize

    var body: some View {
        let cards = ScanCard.all
        let count = max(cards.count, 1)
        let cycle = ScanPhase.cycle
        let turn = Int(floor(now / cycle))
        let local = now - Double(turn) * cycle
        let current = ((turn % count) + count) % count
        let next = (current + 1) % count
        ZStack(alignment: .topLeading) {
            if !cards.isEmpty {
                ScanTurn(read: cards[current], phase: ScanPhase(u: local), card: card, size: size)
                if cards.count > 1 {
                    ScanTurn(read: cards[next], phase: ScanPhase(u: local - cycle), card: card, size: size)
                }
            }
        }
        .frame(width: size.width, height: size.height)
    }
}

/// One card's turn in the scanner: the card, then its read (brackets, line, glow, pill, tick),
/// all moved together as it slides in and out.
private struct ScanTurn: View {
    var read: ScanCard
    var phase: ScanPhase
    var card: CGRect
    var size: CGSize

    var body: some View {
        if phase.onPage {
            ZStack(alignment: .topLeading) {
                HoldingArt(product: DemoData.product(read.item), identity: nil, cornerRadius: 10, caption: false)
                    .frame(width: card.width, height: card.height)
                    .offset(x: card.minX, y: card.minY)
                ScanOverlays(read: read, phase: phase, card: card, size: size)
            }
            .frame(width: size.width, height: size.height)
            .offset(x: CGFloat(phase.slide) * size.width)
        }
    }
}

/// The scanner's read over the card at one moment: brackets, scan line, edge glow, pill and tick.
private struct ScanOverlays: View {
    var read: ScanCard
    var phase: ScanPhase
    var card: CGRect
    var size: CGSize

    var body: some View {
        let snap = phase.snap
        let inset = CGFloat(30 - 22 * snap)
        let dx = CGFloat(14 * (1 - snap))
        let dy = CGFloat(-10 * (1 - snap))
        let box = card.insetBy(dx: -inset, dy: -inset).offsetBy(dx: dx, dy: dy)
        ZStack(alignment: .topLeading) {
            ScanLineClip(card: card, sweep: phase.sweep)
            RoundedRectangle(cornerRadius: 10, style: .continuous)
                .strokeBorder(Theme.lime, lineWidth: 2)
                .frame(width: card.width, height: card.height)
                .offset(x: card.minX, y: card.minY)
                .opacity(0.9 * phase.glow)
            RoundedRectangle(cornerRadius: 10, style: .continuous)
                .fill(Theme.lime)
                .frame(width: card.width, height: card.height)
                .offset(x: card.minX, y: card.minY)
                .opacity(0.1 * phase.glow)
            CornerBracketsShape(rect: box, arm: 26)
                .stroke(Theme.lime, style: StrokeStyle(lineWidth: 4, lineCap: .round, lineJoin: .round))
                .opacity(phase.brackets)
            ScanPill(read: read)
                .scaleEffect(0.85 + 0.15 * phase.pill)
                .opacity(phase.pill)
                .position(x: card.midX, y: card.minY - 28)
            ScanTick()
                .scaleEffect(1.6 - 0.6 * phase.tick)
                .opacity(phase.tick)
                .position(x: card.maxX - 10, y: card.minY + 10)
        }
        .frame(width: size.width, height: size.height)
    }
}

/// The scan line kept inside the card's shape while it sweeps: it comes in over the top edge
/// and leaves past the bottom.
private struct ScanLineClip: View {
    var card: CGRect
    var sweep: Double?

    var body: some View {
        ZStack(alignment: .top) {
            Color.clear
            if let s = sweep {
                ScanLine(width: card.width)
                    .offset(y: CGFloat(s) * (card.height + 48) - 48)
            }
        }
        .frame(width: card.width, height: card.height, alignment: .top)
        .clipShape(RoundedRectangle(cornerRadius: 10, style: .continuous))
        .offset(x: card.minX, y: card.minY)
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

/// The lime scan line with a soft trail above it (gradients, not shadows: cheap per frame).
private struct ScanLine: View {
    var width: CGFloat

    var body: some View {
        VStack(spacing: 0) {
            LinearGradient(colors: [.clear, Theme.lime.opacity(0.45)], startPoint: .top, endPoint: .bottom)
                .frame(height: 44)
            Rectangle().fill(Theme.lime).frame(height: 2)
            LinearGradient(colors: [Theme.lime.opacity(0.25), .clear], startPoint: .top, endPoint: .bottom)
                .frame(height: 6)
        }
        .frame(width: width)
    }
}

/// The live read: name, number and price in a dark pill.
private struct ScanPill: View {
    var read: ScanCard

    var body: some View {
        HStack(spacing: 6) {
            Text(read.name).font(.geist(13, .semibold)).foregroundStyle(.white)
            Text(read.number).font(.mono(11)).foregroundStyle(Theme.muted)
            Text(Format.money(read.item.now)).font(.geist(13, .bold)).monospacedDigit().foregroundStyle(.white)
        }
        .lineLimit(1)
        .fixedSize()
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

// MARK: - Page 3: a deal, worked out

/// The lit backdrop, a lime glow, and a lime deal card that explains a trade, on loop: the
/// card appears with its Trade tag, what's coming in and going out slide in, the cash counts
/// up and the dark "You come out ahead" pill springs in. Loops every 6s: one periodic tick
/// gives a new phase, which rebuilds the card so its entrances play again.
private struct WelcomeDeal: View {
    private static let start = Date()
    @Environment(\.accessibilityReduceMotion) private var reduceMotion

    var body: some View {
        ZStack {
            WelcomeBackdrop()
            Ellipse()
                .fill(Theme.lime.opacity(0.26))
                .frame(width: 300, height: 150)
                .blur(radius: 50)
                .offset(y: 70)
            if reduceMotion {
                DealCard(animated: false)
            } else {
                TimelineView(.periodic(from: Self.start, by: 6)) { context in
                    let phase = Int(context.date.timeIntervalSince(Self.start) / 6 + 0.5)
                    DealCard(animated: true).id(phase)
                }
            }
        }
        .accessibilityElement(children: .ignore)
        .accessibilityLabel("A trade: Umbreon VMAX coming in, Charizard ex going out, the customer pays you \(Format.money(DealCard.cash)) and you come out ahead by \(Format.moneyWhole(DealCard.ahead))")
    }
}

/// One side of the deal: a card's thumbnail, name and price.
private struct DealLine {
    var slug: String
    var name: String
    var price: Double

    var item: DemoData.Item? { DemoData.items.first { $0.slug == slug } }
}

/// The lime deal card. Ink text on lime (never pink on lime); the pill is ink with lime numbers.
private struct DealCard: View {
    var animated: Bool

    static let coming = DealLine(slug: "umbreon-vmax-alt", name: "Umbreon VMAX", price: 1537)
    static let going = DealLine(slug: "charizard-ex-151", name: "Charizard ex", price: 371)
    static let cash: Double = 1166
    static let ahead: Double = 212

    var body: some View {
        VStack(alignment: .leading, spacing: 14) {
            DealReveal(delay: 0.1, animated: animated) {
                SkewTag(text: "Trade", color: Theme.ink, textColor: Theme.lime, icon: "arrow.left.arrow.right")
            }
            DealReveal(delay: 0.5, animated: animated) {
                DealRow(label: "Coming in", line: Self.coming)
            }
            DealReveal(delay: 0.9, animated: animated) {
                DealRow(label: "Going out", line: Self.going)
            }
            Rectangle().fill(Theme.ink.opacity(0.14)).frame(height: 1).padding(.vertical, 2)
            DealCash(delay: 1.4, animated: animated)
        }
        .padding(.horizontal, 22)
        .padding(.vertical, 20)
        .frame(maxWidth: .infinity, alignment: .leading)
        .background(RoundedRectangle(cornerRadius: 28, style: .continuous).fill(Theme.lime))
        .overlay(RoundedRectangle(cornerRadius: 28, style: .continuous).strokeBorder(Color.white.opacity(0.35), lineWidth: 1))
        .foregroundStyle(Theme.ink)
        .padding(.horizontal, 24)
    }
}

/// Something on the card sliding in from the right after its delay (or already there).
private struct DealReveal<Content: View>: View {
    var delay: Double
    var animated: Bool
    @ViewBuilder var content: Content
    @State private var shown = false

    var body: some View {
        content
            .opacity(shown || !animated ? 1 : 0)
            .offset(x: shown || !animated ? 0 : 28)
            .onAppear {
                guard animated, !shown else { return }
                withAnimation(.easeOut(duration: 0.45).delay(delay)) { shown = true }
            }
    }
}

/// One side of the deal: its label, the card's thumbnail, name and price.
private struct DealRow: View {
    var label: String
    var line: DealLine

    var body: some View {
        VStack(alignment: .leading, spacing: 6) {
            MonoLabel(text: label, color: Theme.ink.opacity(0.6))
            HStack(spacing: 10) {
                if let item = line.item {
                    HoldingArt(product: DemoData.product(item), identity: nil, cornerRadius: 3, caption: false)
                        .frame(width: 26, height: 36)
                }
                Text(line.name).font(.geist(16, .semibold))
                Spacer()
                Text(Format.moneyWhole(line.price)).font(.geist(16, .semibold)).monospacedDigit()
            }
        }
    }
}

/// The cash counting up, then the dark "You come out ahead" pill springing in under it.
private struct DealCash: View {
    var delay: Double
    var animated: Bool
    @State private var shown = false
    @State private var landed = false

    var body: some View {
        VStack(alignment: .leading, spacing: 12) {
            VStack(alignment: .leading, spacing: 2) {
                MonoLabel(text: "Customer pays you", color: Theme.ink.opacity(0.6))
                CountingText(value: DealCard.cash, format: { Format.money($0) }, duration: 1.3, delay: animated ? delay : 0)
                    .font(.display(48)).tracking(-1.8).monospacedDigit()
                    .lineLimit(1).minimumScaleFactor(0.7)
                    .displayTrim(48)
            }
            .opacity(shown || !animated ? 1 : 0)
            DealAheadPill()
                .scaleEffect(landed || !animated ? 1 : 1.4)
                .opacity(landed || !animated ? 1 : 0)
        }
        .onAppear {
            guard animated, !shown else { return }
            withAnimation(.easeOut(duration: 0.4).delay(delay)) { shown = true }
            withAnimation(.spring(response: 0.35, dampingFraction: 0.55).delay(delay + 1.5)) { landed = true }
        }
    }
}

/// The dark pill: an arrow, "You come out ahead" and the lime figure.
private struct DealAheadPill: View {
    var body: some View {
        HStack(spacing: 6) {
            Image(systemName: "arrow.up.right").font(.system(size: 11, weight: .bold)).foregroundStyle(Theme.lime)
            Text("You come out ahead").font(.geist(13, .semibold)).foregroundStyle(.white)
            Text("+" + Format.moneyWhole(DealCard.ahead)).font(.geist(13, .bold)).monospacedDigit().foregroundStyle(Theme.lime)
        }
        .lineLimit(1)
        .fixedSize()
        .padding(.horizontal, 14)
        .frame(height: 32)
        .background(Capsule().fill(Theme.ink))
    }
}
