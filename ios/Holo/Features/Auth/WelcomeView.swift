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
            // The lit grid and glows run full bleed behind every page (never clipped), fading
            // to the page's black where the heading and buttons sit.
            WelcomeBackdrop().ignoresSafeArea()
            GeometryReader { geo in
                // Each page's picture takes about the top half of the screen, running right up
                // under the status bar.
                let graphic = min(geo.size.height * 0.52, 480)
                VStack(spacing: 0) {
                    pages(graphicHeight: graphic)
                    dots
                    footer
                        .padding(.horizontal, 24)
                        .padding(.bottom, 12)
                }
                .frame(width: geo.size.width, height: geo.size.height)
            }
            .ignoresSafeArea(edges: .top)
        }
        .foregroundStyle(.white)
        // The grid's card pictures start downloading the moment the welcome appears (small, 10
        // pictures shared by 30 tiles), so the first page fills in as fast as the network allows.
        .task {
            let urls = DemoData.items.filter { !$0.sealed && $0.image != nil }.compactMap { WelcomeTile.product($0).imageURL }
            await withTaskGroup(of: Void.self) { group in
                for url in urls { group.addTask { _ = await ImageCache.shared.load(url) } }
            }
        }
    }

    private func pages(graphicHeight: CGFloat) -> some View {
        TabView(selection: $page) {
            WelcomePage(
                title: "See what your collection is worth",
                line: "Every card you own, priced daily,\nwith how it\u{00A0}has\u{00A0}moved.",
                graphicHeight: graphicHeight
            ) {
                // The page slider gives each page the status bar's inset again; the grid runs up
                // through it to the top edge of the screen, cards cut off by the edge as they drift.
                WelcomeGrid().ignoresSafeArea(edges: .top)
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
                title: "Deals, made easier",
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
            // Sits at the bottom of the screen, like the last page's buttons.
            VStack(spacing: 14) {
                Button("Continue") { go(to: page + 1) }
                    .buttonStyle(Button3D(kind: .lime))
                    .accessibilityIdentifier("welcome-continue")
                // Plain text under Continue, centred, like "Try the demo" on the last page.
                Button("Skip") { go(to: last) }
                    .font(.geist(15, .medium)).foregroundStyle(Theme.muted)
                    .frame(maxWidth: .infinity)
                    .frame(height: 22)
                    .accessibilityIdentifier("welcome-skip")
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
            // Not clipped: glows under the pictures run softly into the page.
            // The picture takes whatever room the text leaves, so the text sits just above
            // the dots instead of leaving a gap under it.
            picture
                .frame(maxWidth: .infinity)
                .frame(minHeight: graphicHeight, maxHeight: .infinity)
            VStack(spacing: 10) {
                // Balanced lines (no lone word at the end), centred, sitting tight on each other.
                DisplayText(text: title, size: 32, lineGap: -0.07, alignment: .center)
                    .frame(maxWidth: .infinity)
                Text(line).font(.geist(16)).foregroundStyle(Theme.muted).multilineTextAlignment(.center)
                    .fixedSize(horizontal: false, vertical: true)
            }
            .padding(.horizontal, 32)
            .padding(.top, 22)
            .padding(.bottom, 28)
        }
    }
}

/// The app's lit grid (like Explore's) behind every page: lime, blue and pink glows over the
/// faint grid, full bleed and unfaded (a fade behind the heading read as a dark band).
private struct WelcomeBackdrop: View {
    var body: some View {
        ZStack {
            GridPattern(step: 36, opacity: 0.05)
            RadialGradient(colors: [Theme.lime.opacity(0.22), .clear], center: UnitPoint(x: 0.2, y: 0.45), startRadius: 0, endRadius: 250)
            RadialGradient(colors: [Theme.planBlue.opacity(0.2), .clear], center: UnitPoint(x: 0.9, y: 0.6), startRadius: 0, endRadius: 230)
            RadialGradient(colors: [Theme.planPink.opacity(0.16), .clear], center: UnitPoint(x: 0.65, y: 0.1), startRadius: 0, endRadius: 200)
        }
        .allowsHitTesting(false)
    }
}

// MARK: - Page 1: columns of cards drifting past, and what they're worth

/// Three full-bleed columns of demo cards (singles with real art only), each drifting on its
/// own: the outer two up, the middle one down, at slightly different speeds and out of step, so
/// the grid feels alive. Each column is its list of cards stacked three times and loops by one
/// list's height, so there's never a gap. The drift is read off the clock (like the scanner
/// page), so each frame only moves three offsets; nothing is laid out again. The bottom fades
/// into the page, and a glass pill over it counts up the worth.
private struct WelcomeGrid: View {
    private static let gap: CGFloat = 8
    /// How long one column takes to travel one list's height, per column.
    private static let durations: [Double] = [22, 26, 24]
    /// Where each column starts in its loop (a share of one list's height), so they never line up.
    private static let phases: [Double] = [0.15, 0.55, 0.35]
    /// The middle column drifts down; the others up.
    private static let down: [Bool] = [false, true, false]
    private static let start = Date()
    /// The grid's lean, in degrees, and how much it's enlarged to still fill the screen.
    private static let tilt: Double = -8
    private static let tiltScale: CGFloat = 1.3
    /// The card pictures, held by the grid itself and handed to the tiles.
    @State private var images: [String: UIImage] = Self.cachedImages()
    @Environment(\.accessibilityReduceMotion) private var reduceMotion

    static func url(_ item: DemoData.Item) -> URL? { WelcomeTile.product(item).imageURL }

    private static func cachedImages() -> [String: UIImage] {
        var out: [String: UIImage] = [:]
        for item in columns.joined() { if let u = url(item), let img = ImageCache.shared.cached(u) { out[item.slug] = img } }
        return out
    }

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
            Group {
                if reduceMotion {
                    columns(at: 0, tileW: tileW, tileH: tileH)
                } else {
                    TimelineView(.animation) { context in
                        columns(at: context.date.timeIntervalSince(Self.start), tileW: tileW, tileH: tileH)
                    }
                }
            }
            .frame(width: geo.size.width, height: geo.size.height, alignment: .top)
            // Tilted, like cards spread across a table: a still turn (enlarged so no corner of
            // the screen goes bare), so the drift inside costs no more than before.
            .scaleEffect(Self.tiltScale)
            .rotationEffect(.degrees(Self.tilt))
            .frame(width: geo.size.width, height: geo.size.height)
            .clipped()
        }
        .mask(fade)
        // A soft dark shade at the top, so the clock reads over the cards.
        .overlay(alignment: .top) {
            LinearGradient(colors: [.black.opacity(0.7), .black.opacity(0.35), .clear], startPoint: .top, endPoint: .bottom)
                .frame(height: 150)
                .allowsHitTesting(false)
        }
        .overlay(alignment: .bottom) { WelcomeWorthPill().padding(.bottom, 10) }
        .task {
            await withTaskGroup(of: (String, UIImage?).self) { group in
                for item in Self.columns.joined() where images[item.slug] == nil {
                    guard let u = Self.url(item) else { continue }
                    group.addTask { (item.slug, await ImageCache.shared.load(u)) }
                }
                for await (slug, img) in group {
                    guard let img else { continue }
                    // Plain update, no animation: the columns' drift is the only motion here.
                    var t = Transaction()
                    t.disablesAnimations = true
                    withTransaction(t) { images[slug] = img }
                }
            }
        }
        .accessibilityElement(children: .ignore)
        .accessibilityLabel("Columns of cards from a collection, worth \(Format.money(WelcomeWorthPill.worth)) today")
    }

    /// The three columns at one moment of the drift (`seconds` since the page appeared).
    private func columns(at seconds: Double, tileW: CGFloat, tileH: CGFloat) -> some View {
        HStack(alignment: .top, spacing: Self.gap) {
            ForEach(0 ..< 3, id: \.self) { i in
                let items = Self.columns[i]
                let listH = CGFloat(items.count) * (tileH + Self.gap)
                // How far through its loop this column is, 0 to 1 (its own start and speed).
                let progress = CGFloat((Self.phases[i] + seconds / Self.durations[i]).truncatingRemainder(dividingBy: 1))
                // Up: the list slides up by one list's height and starts over (the copies match).
                // Down: it starts one list higher and slides down to 0.
                let y = Self.down[i] ? -listH + listH * progress : -listH * progress
                WelcomeColumn(items: items, images: images, tileW: tileW, tileH: tileH)
                    .offset(y: y)
            }
        }
    }

    /// Solid right to the top edge of the screen; fading to the page over the bottom 40%.
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

/// One column: its cards three times over. Its inputs only change when a picture arrives, so
/// the clock's frames move it (the offset outside) without laying it out again.
private struct WelcomeColumn: View {
    var items: [DemoData.Item]
    var images: [String: UIImage]
    var tileW: CGFloat
    var tileH: CGFloat

    var body: some View {
        VStack(spacing: 8) {
            ForEach(0 ..< 3, id: \.self) { _ in
                ForEach(items, id: \.slug) { item in
                    // From the grid's pictures, or straight from the cache once it's there.
                    WelcomeTile(image: images[item.slug] ?? WelcomeGrid.url(item).flatMap { ImageCache.shared.cached($0) })
                        .frame(width: tileW, height: tileH)
                }
            }
        }
        .frame(width: tileW, alignment: .top)
    }
}

/// One card of the grid: a dark card-shaped well with the card's picture on it once it's here.
private struct WelcomeTile: View {
    var image: UIImage?

    /// The demo product, with the same picture the scan page and the rest of the app load.
    static func product(_ item: DemoData.Item) -> Product {
        DemoData.product(item)
    }

    var body: some View {
        ZStack {
            RoundedRectangle(cornerRadius: 6, style: .continuous).fill(Theme.well)
            if let image {
                Image(uiImage: image).resizable().aspectRatio(contentMode: .fill)
            }
        }
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
        .liquidGlass(in: RoundedRectangle(cornerRadius: 18, style: .continuous))
    }
}

// MARK: - Page 2: cards being scanned, one after another

/// Where one card's scan is in its 4.2s turn, from the clock (no state). Local time `u` runs
/// from -0.5 (sliding in from the right, during the previous card's exit) to 4.2: the card lies
/// at an angle on the table, the brackets snap on as it squares up (0.45–0.95), the line sweeps
/// (0.95–1.75), the pill pops and the price counts up (1.9–2.6), the tick lands and a lime flash
/// runs round the edge (2.05–2.65), the card turns to the light (2.5–3.3), its gain tag springs
/// in (2.6), a hold, then it slides out to the left (3.65–4.2).
private struct ScanPhase {
    static let cycle: Double = 4.2
    /// The still frame under Reduce Motion: everything landed.
    static let still = ScanPhase(u: 3.4)
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
        if u > 3.65 { return -Self.ease((u - 3.65) / 0.55) }
        return 0
    }
    /// 0 wide and off the card (and the card still lying at its angle), 1 tight on it.
    var snap: Double { Self.ease((u - 0.45) / 0.5) }
    var brackets: Double { min(Self.ease((u - 0.45) / 0.12), leaving) }
    /// How far down the card the scan line is, while it sweeps.
    var sweep: Double? {
        guard u >= 0.95, u <= 1.75 else { return nil }
        return (u - 0.95) / 0.8
    }
    /// The faint lime wash while the line sweeps.
    var glow: Double { min(Self.ease((u - 1.0) / 0.5), 1 - Self.ease((u - 1.9) / 0.4)) }
    var pill: Double { min(Self.ease((u - 1.9) / 0.3), leaving) }
    /// The price counting up from nothing.
    var count: Double { Self.ease((u - 1.9) / 0.7) }
    var tick: Double { min(Self.ease((u - 2.05) / 0.3), leaving) }
    /// The lime flash running once round the card's edge as it locks (nil when not running).
    var flash: Double? {
        guard u >= 2.05, u <= 2.65 else { return nil }
        return (u - 2.05) / 0.6
    }
    /// The card turning to the light and back, and the sheen crossing it (nil when still).
    var turn: Double? {
        guard u >= 2.5, u <= 3.3 else { return nil }
        return (u - 2.5) / 0.8
    }
    var tag: Double { min(Self.back((u - 2.6) / 0.35), leaving) }
    /// The read's overlays fade as the card leaves.
    var leaving: Double { 1 - Self.ease((u - 3.65) / 0.3) }
    /// The card itself is drawn while it's anywhere on the page.
    var onPage: Bool { u > -0.5 && u < Self.cycle }
}

/// What the scanner reads off one demo card, and the angle it lies at on the table.
private struct ScanCard {
    var item: DemoData.Item
    var name: String
    /// Leaning back (degrees about the card's width) and turned (degrees in the table's plane).
    var lean: Double
    var turn: Double

    var number: String {
        let n = item.number ?? ""
        let short = n.split(separator: "/").first.map(String.init) ?? n
        return "#" + short
    }

    /// What it has gained since it was bought, as a ratio.
    var gain: Double { item.start > 0 ? item.now / item.start - 1 : 0 }

    /// The cards that take turns (all up, so their tags are lime), with the short names the
    /// pill shows, each lying differently, like cards picked up off a binder page.
    static let all: [ScanCard] = {
        let picks: [(String, String, Double, Double)] = [
            ("pikachu-ex-ss", "Pikachu ex", 24, -9), ("umbreon-vmax-alt", "Umbreon VMAX", 18, 8),
            ("rayquaza-vmax-alt", "Rayquaza VMAX", 26, -5), ("giratina-v-alt", "Giratina V", 20, 11),
            ("lugia-v-alt", "Lugia V", 22, -12),
        ]
        var out: [ScanCard] = []
        for pick in picks {
            if let item = DemoData.items.first(where: { $0.slug == pick.0 }) {
                out.append(ScanCard(item: item, name: pick.1, lean: pick.2, turn: pick.3))
            }
        }
        return out
    }()

    /// The card whose turn `t` is.
    static func at(_ t: Int) -> ScanCard? {
        guard !all.isEmpty else { return nil }
        return all[((t % all.count) + all.count) % all.count]
    }
}

/// The scanner as the camera sees it: a dark table in a viewfinder, demo cards slid under the
/// phone one after another and read on loop (brackets snap on as the card squares up, the
/// line sweeps, the price counts up, a flash runs round the edge, the card turns to the light),
/// and under it the last three cards scanned. One timeline moves a handful of views by
/// offsets, turns and opacities; the table, its blur and the glow sit still outside it.
private struct WelcomeScanLoop: View {
    @Environment(\.accessibilityReduceMotion) private var reduceMotion

    var body: some View {
        VStack(spacing: 14) {
            GeometryReader { geo in
                let finder = CGRect(x: 20, y: 0, width: geo.size.width - 40, height: geo.size.height)
                let card = Self.cardRect(in: finder)
                ZStack(alignment: .topLeading) {
                    // The glow is never clipped: it runs out under the viewfinder into the page.
                    Ellipse()
                        .fill(Theme.lime.opacity(0.3))
                        .frame(width: card.width * 1.6, height: 120)
                        .blur(radius: 40)
                        .position(x: finder.midX, y: finder.maxY)
                    ScanTable(finder: finder)
                    Group {
                        if reduceMotion {
                            ScanStage(now: ScanPhase.still.u, card: card, size: geo.size)
                        } else {
                            TimelineView(.animation) { context in
                                ScanStage(now: context.date.timeIntervalSinceReferenceDate, card: card, size: geo.size)
                            }
                        }
                    }
                    .frame(width: geo.size.width, height: geo.size.height)
                    // The cards only show inside the camera's view.
                    .mask(
                        RoundedRectangle(cornerRadius: 26, style: .continuous)
                            .frame(width: finder.width, height: finder.height)
                            .position(x: finder.midX, y: finder.midY)
                    )
                }
                .frame(width: geo.size.width, height: geo.size.height)
            }
            RecentScans()
                .padding(.horizontal, 20)
        }
        .padding(.top, 8)
        .accessibilityElement(children: .ignore)
        .accessibilityLabel("Cards being scanned one after another, each with its name and price")
    }

    /// The card, about 60% of the page's width (less on a short screen), centred in the
    /// viewfinder with room for the pill above it.
    private static func cardRect(in finder: CGRect) -> CGRect {
        var h = finder.width * 0.66 * 88 / 63
        h = min(h, finder.height - 120)
        let w = h * 63 / 88
        let x = finder.midX - w / 2
        let y = finder.minY + (finder.height - h) / 2 + 12
        return CGRect(x: x, y: y, width: w, height: h)
    }
}

/// The table under the camera, still: a dark warm surface lit from the top left, an out-of-
/// focus card lying further off, a vignette, faint thirds lines and the camera's labels.
private struct ScanTable: View {
    var finder: CGRect

    var body: some View {
        let shape = RoundedRectangle(cornerRadius: 26, style: .continuous)
        ZStack {
            LinearGradient(colors: [Color(hex: 0x2B2723), Color(hex: 0x151311)], startPoint: .top, endPoint: .bottom)
            RadialGradient(colors: [Color.white.opacity(0.10), .clear], center: UnitPoint(x: 0.15, y: 0.05), startRadius: 0, endRadius: finder.width * 0.9)
            // Another card on the table, out of focus.
            RoundedRectangle(cornerRadius: 8, style: .continuous)
                .fill(LinearGradient(colors: [Theme.planBlue.opacity(0.55), Theme.planPink.opacity(0.35)], startPoint: .top, endPoint: .bottom))
                .frame(width: 90, height: 126)
                .rotationEffect(.degrees(24))
                .blur(radius: 14)
                .offset(x: finder.width * 0.42, y: -finder.height * 0.36)
            RoundedRectangle(cornerRadius: 8, style: .continuous)
                .fill(Color.white.opacity(0.10))
                .frame(width: 80, height: 112)
                .rotationEffect(.degrees(-18))
                .blur(radius: 12)
                .offset(x: -finder.width * 0.46, y: finder.height * 0.38)
            RadialGradient(colors: [.clear, .black.opacity(0.55)], center: .center, startRadius: finder.width * 0.35, endRadius: finder.width * 0.95)
            ThirdsLines().stroke(Color.white.opacity(0.06), lineWidth: 1)
            VStack {
                HStack {
                    MonoLabel(text: "Scanning", color: Theme.lime)
                    Spacer()
                    MonoLabel(text: "1×")
                }
                Spacer()
            }
            .padding(14)
        }
        .frame(width: finder.width, height: finder.height)
        .clipShape(shape)
        .overlay(shape.strokeBorder(Color.white.opacity(0.10), lineWidth: 1))
        .position(x: finder.midX, y: finder.midY)
        .allowsHitTesting(false)
    }
}

/// The camera's rule-of-thirds guide.
private struct ThirdsLines: Shape {
    func path(in r: CGRect) -> Path {
        var p = Path()
        for i in 1 ... 2 {
            let x = r.minX + r.width * CGFloat(i) / 3
            let y = r.minY + r.height * CGFloat(i) / 3
            p.move(to: CGPoint(x: x, y: r.minY)); p.addLine(to: CGPoint(x: x, y: r.maxY))
            p.move(to: CGPoint(x: r.minX, y: y)); p.addLine(to: CGPoint(x: r.maxX, y: y))
        }
        return p
    }
}

/// The scanner at one moment: the card whose turn it is, and the next one on its way in.
private struct ScanStage: View {
    /// Seconds (any clock); under Reduce Motion, the still frame's local time.
    var now: Double
    var card: CGRect
    var size: CGSize

    var body: some View {
        let cycle = ScanPhase.cycle
        let turn = Int(floor(now / cycle))
        // The turn whose card is on the page, and the next one sliding in. Each is keyed by its
        // turn number, so the next card's view carries straight on as the current one instead
        // of being rebuilt (which blinked).
        let turns = ScanCard.all.count > 1 ? [turn, turn + 1] : [turn]
        ZStack(alignment: .topLeading) {
            ForEach(turns, id: \.self) { t in
                if let read = ScanCard.at(t) {
                    ScanTurn(read: read, phase: ScanPhase(u: now - Double(t) * cycle), card: card, size: size)
                }
            }
        }
        .frame(width: size.width, height: size.height)
    }
}

/// One card's turn in the scanner: its shadow on the table, the card (lying at its angle until
/// the brackets lock, then turning to the light), then its read, all moved together as it
/// slides in and out.
private struct ScanTurn: View {
    var read: ScanCard
    var phase: ScanPhase
    var card: CGRect
    var size: CGSize

    var body: some View {
        if phase.onPage {
            let loose = 1 - phase.snap
            let wobble = phase.turn.map { sin(Double.pi * $0) * 16 } ?? 0
            ZStack(alignment: .topLeading) {
                // Its shadow on the table (a gradient, not a blur).
                Ellipse()
                    .fill(RadialGradient(colors: [.black.opacity(0.6), .clear], center: .center, startRadius: 0, endRadius: card.width * 0.6))
                    .frame(width: card.width * 1.2, height: card.height * 0.3)
                    .offset(x: card.minX - card.width * 0.1, y: card.maxY - card.height * 0.12)
                ZStack {
                    HoldingArt(product: DemoData.product(read.item), identity: nil, cornerRadius: 10, caption: false)
                    if let t = phase.turn { ScanSheen(progress: t, card: card.size) }
                }
                .frame(width: card.width, height: card.height)
                .clipShape(RoundedRectangle(cornerRadius: 10, style: .continuous))
                .scaleEffect(0.9 + 0.1 * phase.snap)
                .rotationEffect(.degrees(read.turn * loose))
                .rotation3DEffect(.degrees(read.lean * loose), axis: (x: 1, y: 0, z: 0), perspective: 0.5)
                .rotation3DEffect(.degrees(wobble), axis: (x: 0, y: 1, z: 0), perspective: 0.5)
                .offset(x: card.minX, y: card.minY)
                ScanOverlays(read: read, phase: phase, card: card, size: size)
            }
            .frame(width: size.width, height: size.height)
            .offset(x: CGFloat(phase.slide) * size.width)
        }
    }
}

/// The light crossing the card as it turns: a soft white band, diagonal, left to right.
private struct ScanSheen: View {
    var progress: Double
    var card: CGSize

    var body: some View {
        LinearGradient(colors: [.clear, .white.opacity(0.45), .clear], startPoint: .leading, endPoint: .trailing)
            .frame(width: card.width * 0.45, height: card.height * 1.6)
            .rotationEffect(.degrees(20))
            .offset(x: CGFloat(-0.9 + 1.8 * progress) * card.width)
            .allowsHitTesting(false)
    }
}

/// The scanner's read over the card at one moment: brackets, scan line, wash, edge flash,
/// pill, tick and gain tag.
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
        let edge = RoundedRectangle(cornerRadius: 10, style: .continuous)
        ZStack(alignment: .topLeading) {
            ScanLineClip(card: card, sweep: phase.sweep)
            edge.fill(Theme.lime)
                .frame(width: card.width, height: card.height)
                .offset(x: card.minX, y: card.minY)
                .opacity(0.1 * phase.glow)
            if let f = phase.flash {
                // A bright head running once round the edge, over a quick whole-edge flash.
                let head = f * 1.3
                let flare = sin(Double.pi * f)
                ZStack {
                    edge.stroke(Theme.lime, lineWidth: 2).opacity(0.9 * flare)
                    edge.trim(from: max(0, head - 0.3), to: min(1, head))
                        .stroke(Theme.lime.opacity(0.35), style: StrokeStyle(lineWidth: 12, lineCap: .round))
                    edge.trim(from: max(0, head - 0.3), to: min(1, head))
                        .stroke(Theme.lime, style: StrokeStyle(lineWidth: 3.5, lineCap: .round))
                }
                .frame(width: card.width, height: card.height)
                .offset(x: card.minX, y: card.minY)
            }
            CornerBracketsShape(rect: box, arm: 26)
                .stroke(Theme.lime, style: StrokeStyle(lineWidth: 4, lineCap: .round, lineJoin: .round))
                .opacity(phase.brackets)
            ScanPill(read: read, count: phase.count)
                .scaleEffect(0.85 + 0.15 * phase.pill)
                .opacity(phase.pill)
                .position(x: card.midX, y: card.minY - 28)
            ScanTick()
                .scaleEffect(1.6 - 0.6 * phase.tick)
                .opacity(phase.tick)
                .position(x: card.maxX - 10, y: card.minY + 10)
            SkewTag(text: "\(Format.signedPercent(read.gain)) all time", icon: "arrow.up.right")
                .scaleEffect(CGFloat(0.6 + 0.4 * phase.tag), anchor: .leading)
                .opacity(min(max(phase.tag, 0), 1))
                .frame(width: card.width + 24, alignment: .leading)
                .position(x: card.midX - 12, y: card.maxY - 20)
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

/// The live read: name, number and the price counting up in lime, in a dark pill. The final
/// price sets the width, so the pill doesn't jiggle while the digits run.
private struct ScanPill: View {
    var read: ScanCard
    /// 0 to 1: how far the price has counted up.
    var count: Double

    var body: some View {
        HStack(spacing: 6) {
            Text(read.name).font(.geist(13, .semibold)).foregroundStyle(.white)
            Text(read.number).font(.mono(11)).foregroundStyle(Theme.muted)
            Text(Format.money(read.item.now)).font(.geist(13, .bold)).monospacedDigit()
                .hidden()
                .overlay(alignment: .trailing) {
                    Text(Format.money(read.item.now * count)).font(.geist(13, .bold)).monospacedDigit()
                        .foregroundStyle(Theme.lime)
                }
        }
        .lineLimit(1)
        .fixedSize()
        .padding(.horizontal, 12)
        .frame(height: 30)
        .background(Capsule().fill(Color.black.opacity(0.72)))
        .overlay(Capsule().strokeBorder(Color.white.opacity(0.14), lineWidth: 1))
    }
}

/// The last three cards scanned, newest first, under the viewfinder: each joins from the
/// left once its tick has landed. Checked a few times a second, not every frame.
private struct RecentScans: View {
    @Environment(\.accessibilityReduceMotion) private var reduceMotion

    var body: some View {
        if reduceMotion {
            row(latest: 2)
        } else {
            TimelineView(.periodic(from: .now, by: 0.25)) { context in
                let now = context.date.timeIntervalSinceReferenceDate
                let turn = Int(floor(now / ScanPhase.cycle))
                let u = now - Double(turn) * ScanPhase.cycle
                row(latest: u >= 2.3 ? turn : turn - 1)
            }
        }
    }

    private func row(latest: Int) -> some View {
        HStack(spacing: 8) {
            ForEach([latest, latest - 1, latest - 2], id: \.self) { t in
                if let read = ScanCard.at(t) {
                    RecentScanChip(read: read)
                        .transition(.asymmetric(insertion: .move(edge: .leading).combined(with: .opacity), removal: .opacity))
                }
            }
        }
        .frame(maxWidth: .infinity, alignment: .leading)
        .animation(reduceMotion ? nil : .snappy(duration: 0.4), value: latest)
    }
}

/// One card in the recently-scanned row: a small picture, its name and price.
private struct RecentScanChip: View {
    var read: ScanCard

    var body: some View {
        HStack(spacing: 8) {
            HoldingArt(product: DemoData.product(read.item), identity: nil, cornerRadius: 3, caption: false)
                .frame(width: 26, height: 36)
            VStack(alignment: .leading, spacing: 1) {
                Text(read.name).font(.geist(11, .semibold)).foregroundStyle(.white).lineLimit(1)
                Text(Format.money(read.item.now)).font(.geist(11, .bold)).monospacedDigit().foregroundStyle(Theme.lime).lineLimit(1)
            }
        }
        .padding(6)
        .padding(.trailing, 4)
        .frame(maxWidth: .infinity, alignment: .leading)
        .background(RoundedRectangle(cornerRadius: 12, style: .continuous).fill(Color.white.opacity(0.06)))
        .overlay(RoundedRectangle(cornerRadius: 12, style: .continuous).strokeBorder(Color.white.opacity(0.08), lineWidth: 1))
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
