import SwiftUI
import UserNotifications

/// The walkthrough's quiet text: white, partly see-through (not grey), so it sits well on every
/// backdrop colour behind it.
private let welcomeSoft = Color.white.opacity(0.62)

/// Whether this welcome page is the one on screen. The page slider keeps its neighbours alive,
/// so each page's moving picture pauses unless it's showing.
private struct WelcomeActiveKey: EnvironmentKey { static let defaultValue = true }

private extension EnvironmentValues {
    var welcomeActive: Bool {
        get { self[WelcomeActiveKey.self] }
        set { self[WelcomeActiveKey.self] = newValue }
    }
}

/// The welcome, before sign-in: six swipeable pages (what the app does, in big moving
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

    private let last = 25
    /// The price alerts page: it offers to turn notifications on.
    private let alertsPage = 24
    /// iPhone hasn't asked about notifications yet (so the alerts page offers to).
    @State private var canAskNotifications = false
    /// Notifications were just turned on: the button says so for a moment before moving on.
    @State private var alertsOn = false

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
        .task {
            let settings = await UNUserNotificationCenter.current().notificationSettings()
            canAskNotifications = preview || settings.authorizationStatus == .notDetermined
        }
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
            .environment(\.welcomeActive, page == 0)
            WelcomePage(
                title: "Scan a card, know its price",
                line: "Point the camera at a card. Its name\nand price appear\u{00A0}on\u{00A0}it.",
                graphicHeight: graphicHeight
            ) {
                WelcomeScanLoop()
            }
            .tag(1)
            .environment(\.welcomeActive, page == 1)
            WelcomePage(
                title: "Graded cards, in their slabs",
                line: "Add a PSA, CGC or BGS grade. It's shown\nin its slab and priced\u{00A0}as\u{00A0}graded.",
                graphicHeight: graphicHeight
            ) {
                WelcomeGrading()
            }
            .tag(2)
            .environment(\.welcomeActive, page == 2)
            // Twenty-one Master Sets designs side by side for now, to compare (pages 3 to 23).
            ForEach(1 ... 21, id: \.self) { option in
                WelcomePage(
                    title: "Finish every set",
                    line: "See how much of each set you own, and the cards\u{00A0}still\u{00A0}missing.",
                    graphicHeight: graphicHeight
                ) {
                    if option == 21 {
                        WelcomeMasterOption(option: option).ignoresSafeArea(edges: .top)
                    } else {
                        WelcomeMasterOption(option: option)
                    }
                }
                .tag(2 + option)
                .environment(\.welcomeActive, page == 2 + option)
            }
            WelcomePage(
                title: "Know when prices move",
                line: "Set a target on any card. You'll get a notification\u{00A0}when\u{00A0}it's\u{00A0}hit.",
                graphicHeight: graphicHeight
            ) {
                WelcomeAlerts()
            }
            .tag(alertsPage)
            .environment(\.welcomeActive, page == alertsPage)
            WelcomePage(
                title: "Deals, made easier",
                line: "Add what's coming in and going out. The cash and your profit are\u{00A0}worked\u{00A0}out.",
                graphicHeight: graphicHeight
            ) {
                WelcomeDeal()
            }
            .tag(last)
            .environment(\.welcomeActive, page == last)
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
        .padding(.vertical, 8)
        .padding(.horizontal, 12)
        .contentShape(Rectangle())
        // Hold the dots to jump straight to a page.
        .contextMenu {
            ForEach(0 ... last, id: \.self) { i in
                Button(Self.pageNames[i]) { go(to: i) }
            }
        }
        .padding(.bottom, 10)
        .accessibilityHidden(true)
    }

    private static let pageNames = ["What it's worth", "Scan a card", "Grading"] + MasterOption.names.enumerated().map { "Master sets \($0.offset + 1): \($0.element)" } + ["Price alerts", "Deals"]

    /// Continue on the first pages; the ways in on the last.
    @ViewBuilder private var footer: some View {
        if page == alertsPage, canAskNotifications {
            // The moment to ask: iPhone's own prompt follows "Turn on alerts".
            VStack(spacing: 14) {
                Button { Task { await turnOnAlerts() } } label: {
                    Label(alertsOn ? "Alerts on" : "Turn on alerts", systemImage: alertsOn ? "checkmark" : "bell.fill")
                        .contentTransition(.symbolEffect(.replace))
                }
                    .buttonStyle(Button3D(kind: .lime))
                    .disabled(alertsOn)
                    .accessibilityIdentifier("welcome-alerts-on")
                Button("Not now") { go(to: page + 1) }
                    .font(.geist(15, .medium)).foregroundStyle(welcomeSoft)
                    .frame(maxWidth: .infinity)
                    .frame(height: 22)
                    .accessibilityIdentifier("welcome-alerts-later")
            }
        } else if page < last {
            // Sits at the bottom of the screen, like the last page's buttons.
            VStack(spacing: 14) {
                Button("Continue") { go(to: page + 1) }
                    .buttonStyle(Button3D(kind: .lime))
                    .accessibilityIdentifier("welcome-continue")
                // Plain text under Continue, centred, like "Try the demo" on the last page.
                Button("Skip") { go(to: last) }
                    .font(.geist(15, .medium)).foregroundStyle(welcomeSoft)
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
                .font(.geist(15, .medium)).foregroundStyle(welcomeSoft)
                .frame(height: 22)
                .accessibilityIdentifier("welcome-demo")
                if let error {
                    Text(error).font(.geist(13)).foregroundStyle(Theme.down).multilineTextAlignment(.center)
                }
            }
        }
    }

    /// Apple's notification prompt (the page itself is the explanation, so no extra note), then
    /// on to the next page whatever the answer. The device is registered once signed in.
    private func turnOnAlerts() async {
        var granted = preview
        if !preview {
            Onboarding.notificationsExplained = true
            granted = (try? await UNUserNotificationCenter.current().requestAuthorization(options: [.alert, .sound, .badge])) ?? false
        }
        if granted {
            // A moment of "Alerts on" before moving on, so the tap is answered.
            withAnimation(.snappy(duration: 0.25)) { alertsOn = true }
            try? await Task.sleep(for: .milliseconds(900))
        }
        go(to: page + 1)
        if !preview { canAskNotifications = false }
        alertsOn = false
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
                Text(line).font(.geist(16)).foregroundStyle(welcomeSoft).multilineTextAlignment(.center)
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
    @Environment(\.welcomeActive) private var active

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
                    TimelineView(.animation(minimumInterval: nil, paused: !active)) { context in
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
    private static let start = Date()
    @Environment(\.welcomeActive) private var active
    @Environment(\.accessibilityReduceMotion) private var reduceMotion

    var body: some View {
        if reduceMotion {
            pill(Self.worth)
        } else {
            // A small rise every few seconds, so the figure feels live.
            TimelineView(.animation(minimumInterval: 3.2, paused: !active)) { context in
                let ticks = Int(context.date.timeIntervalSince(Self.start) / 3.2)
                let steps: [Double] = [0, 1.35, 2.1, 3.85, 4.4, 6.05]
                let rise: Double = steps[ticks % steps.count] + Double(ticks / steps.count) * 6.05
                pill(Self.worth + rise)
            }
        }
    }

    private func pill(_ value: Double) -> some View {
        HStack(spacing: 12) {
            VStack(alignment: .leading, spacing: 2) {
                MonoLabel(text: "Worth today", color: welcomeSoft)
                CountingText(value: value, format: { Format.money($0) }, duration: 1.4, delay: 0.3)
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
    /// How far the card is turned to the light, in degrees.
    var wobble: Double {
        guard let t = turn else { return 0 }
        return sin(Double.pi * t) * 16
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
            ("lugia-v-alt", "Lugia V", 22, -12), ("gengar-vmax-alt", "Gengar VMAX", 19, 9),
            ("espeon-vmax-alt", "Espeon VMAX", 25, -7),
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
    @Environment(\.welcomeActive) private var active

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
                            TimelineView(.animation(minimumInterval: nil, paused: !active)) { context in
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
                    MonoLabel(text: "1×", color: welcomeSoft)
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
        // A light tap as each card's read locks on (the tick).
        let locked: Bool = now - Double(turn) * cycle >= 2.05
        ZStack(alignment: .topLeading) {
            ForEach(turns, id: \.self) { t in
                if let read = ScanCard.at(t) {
                    ScanTurn(read: read, phase: ScanPhase(u: now - Double(t) * cycle), card: card, size: size)
                }
            }
        }
        .frame(width: size.width, height: size.height)
        .sensoryFeedback(.impact(weight: .light), trigger: locked) { _, new in new }
    }
}

/// One card's turn in the scanner: its shadow on the table, the card (lying at its angle until
/// the brackets lock), then its read, all moved together as it
/// slides in and out.
private struct ScanTurn: View {
    var read: ScanCard
    var phase: ScanPhase
    var card: CGRect
    var size: CGSize

    var body: some View {
        if phase.onPage {
            let loose = 1 - phase.snap
            let cardScale = CGFloat(0.9 + 0.1 * phase.snap)
            let turnAngle: Double = read.turn * loose
            let leanAngle: Double = read.lean * loose
            let slideX = CGFloat(phase.slide) * size.width
            ZStack(alignment: .topLeading) {
                // Its shadow on the table (a gradient, not a blur).
                Ellipse()
                    .fill(RadialGradient(colors: [.black.opacity(0.6), .clear], center: .center, startRadius: 0, endRadius: card.width * 0.6))
                    .frame(width: card.width * 1.2, height: card.height * 0.3)
                    .offset(x: card.minX - card.width * 0.1, y: card.maxY - card.height * 0.12)
                ZStack {
                    HoldingArt(product: DemoData.product(read.item), identity: nil, cornerRadius: 10, caption: false)
                }
                .frame(width: card.width, height: card.height)
                .clipShape(RoundedRectangle(cornerRadius: 10, style: .continuous))
                .scaleEffect(cardScale)
                .rotationEffect(.degrees(turnAngle))
                .rotation3DEffect(.degrees(leanAngle), axis: (x: 1, y: 0, z: 0), perspective: 0.5)
                .offset(x: card.minX, y: card.minY)
                ScanOverlays(read: read, phase: phase, card: card, size: size)
            }
            .frame(width: size.width, height: size.height)
            .offset(x: slideX)
        }
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
                let head: Double = f * 1.3
                let flare: Double = sin(Double.pi * f)
                let from = CGFloat(max(0, head - 0.3))
                let to = CGFloat(min(1, head))
                ZStack {
                    edge.stroke(Theme.lime, lineWidth: 2).opacity(0.9 * flare)
                    edge.trim(from: from, to: to)
                        .stroke(Theme.lime.opacity(0.35), style: StrokeStyle(lineWidth: 12, lineCap: .round))
                    edge.trim(from: from, to: to)
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
                .scaleEffect(CGFloat(0.6 + 0.4 * phase.tag))
                .opacity(min(max(phase.tag, 0), 1))
                // Centred under the card.
                .position(x: card.midX, y: card.maxY + 20)
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
            Text(read.number).font(.mono(11)).foregroundStyle(welcomeSoft)
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
    @Environment(\.welcomeActive) private var active

    var body: some View {
        if reduceMotion {
            row(latest: 2)
        } else {
            TimelineView(.animation(minimumInterval: 0.25, paused: !active)) { context in
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
        .liquidGlass(in: RoundedRectangle(cornerRadius: 12, style: .continuous))
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

/// Easing for the clock-driven pages (no state: each frame works out where everything is).
private enum Ease {
    static func clamp(_ x: Double) -> Double { min(max(x, 0), 1) }
    /// Ease out (cubic), from `start` over `length` seconds of local time `t`.
    static func out(_ t: Double, _ start: Double, _ length: Double) -> Double {
        let c = clamp((t - start) / length)
        return 1 - pow(1 - c, 3)
    }
    /// Ease out with a touch of overshoot, like a spring settling.
    static func back(_ t: Double, _ start: Double, _ length: Double) -> Double {
        let c = clamp((t - start) / length) - 1
        return 1 + 2.4 * c * c * c + 1.4 * c * c
    }
}

/// One side of a deal: a card (thumbnail, name, price) or cash.
private struct WelcomeDealSide {
    var slug: String?
    var name: String
    var value: Double

    static func card(_ slug: String, _ name: String, _ value: Double) -> WelcomeDealSide { WelcomeDealSide(slug: slug, name: name, value: value) }
    static func cash(_ value: Double) -> WelcomeDealSide { WelcomeDealSide(slug: nil, name: "Cash", value: value) }

    var item: DemoData.Item? { slug.flatMap { s in DemoData.items.first { $0.slug == s } } }
}

/// One deal the page shows: a trade, a buy or a sale, taking turns.
private struct DealSpec {
    var tag: String
    var icon: String
    var coming: WelcomeDealSide
    var going: WelcomeDealSide
    var cashLabel: String
    var cash: Double
    var ahead: Double

    static let all: [DealSpec] = [
        DealSpec(tag: "Trade", icon: "arrow.left.arrow.right",
                 coming: .card("umbreon-vmax-alt", "Umbreon VMAX", 1537), going: .card("charizard-ex-151", "Charizard ex", 371),
                 cashLabel: "Customer pays you", cash: 1166, ahead: 212),
        DealSpec(tag: "Buy", icon: "arrow.down.left",
                 coming: .card("rayquaza-vmax-alt", "Rayquaza VMAX", 548), going: .cash(430),
                 cashLabel: "You pay", cash: 430, ahead: 118),
        DealSpec(tag: "Sale", icon: "arrow.up.right",
                 coming: .cash(372), going: .card("pikachu-ex-ss", "Pikachu ex", 371.5),
                 cashLabel: "Customer pays you", cash: 372, ahead: 87),
    ]

    /// The cards fanned above the deal: both sides of a trade, or the one card bought or sold.
    var fan: [WelcomeDealSide] { [going, coming].filter { $0.slug != nil } }
}

/// The deal page on loop, all off one clock: the deal's cards fan out above a lime deal card;
/// what's coming in and going out arrive from the right; the In/Out bar tips; the cash counts
/// up; the dark "You come out ahead" panel punches in as the card's edge flashes. Then the next deal (trade, buy, sale).
private struct WelcomeDeal: View {
    static let cycle: Double = 7
    /// The composition's natural height; a shorter page shrinks it to fit.
    private static let height: CGFloat = 500
    private static let start = Date()
    @Environment(\.accessibilityReduceMotion) private var reduceMotion
    @Environment(\.welcomeActive) private var active

    var body: some View {
        GeometryReader { geo in
            let scale = min(1, geo.size.height / Self.height)
            ZStack {
                Ellipse()
                    .fill(Theme.lime.opacity(0.26))
                    .frame(width: 320, height: 160)
                    .blur(radius: 50)
                    .offset(y: 90)
                Group {
                    if reduceMotion {
                        DealScene(spec: DealSpec.all[0], t: 6, clock: 0)
                    } else {
                        TimelineView(.animation(minimumInterval: nil, paused: !active)) { context in
                            let s = context.date.timeIntervalSince(Self.start)
                            let n = Int(s / Self.cycle)
                            DealScene(spec: DealSpec.all[n % DealSpec.all.count], t: s - Double(n) * Self.cycle, clock: s)
                        }
                    }
                }
                .frame(width: geo.size.width, height: Self.height)
                .scaleEffect(scale)
            }
            .frame(width: geo.size.width, height: geo.size.height)
        }
        .accessibilityElement(children: .ignore)
        .accessibilityLabel("Deals worked out: a trade, Umbreon VMAX coming in and Charizard ex going out, the customer pays you \(Format.money(1166)) and you come out ahead by \(Format.moneyWhole(212)); then a buy and a sale")
    }
}

/// One deal at local time `t` (0 to the cycle); `clock` keeps the fan's float running across deals.
private struct DealScene: View {
    var spec: DealSpec
    var t: Double
    var clock: Double

    var body: some View {
        let appear = Ease.out(t, 0, 0.4)
        let leave = 1 - Ease.out(t, WelcomeDeal.cycle - 0.55, 0.45)
        // Each deal slides in from the right and out to the left, so the change reads.
        let sceneX = CGFloat((1 - appear) * 140 - (1 - leave) * 140)
        VStack(spacing: -46) {
            DealFan(spec: spec, t: t, clock: clock)
                .frame(height: 170)
            DealPanel(spec: spec, t: t)
        }
        .padding(.horizontal, 24)
        .opacity(min(appear, leave))
        .offset(x: sceneX)
    }
}

/// The deal's cards, big and tilted above the deal card (tucked behind its top edge): a trade
/// shows both with a lime swap mark between them; a buy or sale shows its one card.
private struct DealFan: View {
    var spec: DealSpec
    var t: Double
    var clock: Double

    private var swapTurn: Double { 180 * Ease.out(t, 0.3, 0.6) }
    private var swapScale: CGFloat { CGFloat(Ease.back(t, 0.3, 0.4)) }

    var body: some View {
        let cards: [WelcomeDealSide] = spec.fan
        ZStack {
            ForEach(0 ..< cards.count, id: \.self) { i in
                DealFanCard(side: cards[i], index: i, count: cards.count, t: t, clock: clock)
            }
            if cards.count > 1 {
                Image(systemName: "arrow.left.arrow.right")
                    .font(.system(size: 15, weight: .bold))
                    .foregroundStyle(Theme.ink)
                    .frame(width: 40, height: 40)
                    .background(Circle().fill(Theme.lime))
                    .rotationEffect(.degrees(swapTurn))
                    .scaleEffect(swapScale)
                    .offset(y: -8)
            }
        }
        .frame(maxWidth: .infinity)
    }
}

/// One card of the fan, dropping in and floating gently.
private struct DealFanCard: View {
    var side: WelcomeDealSide
    var index: Int
    var count: Int
    var t: Double
    var clock: Double

    var body: some View {
        let i = Double(index)
        let pos: Double = count == 1 ? 0 : (index == 0 ? -1 : 1)
        let enter: Double = Ease.back(t, 0.05 + 0.12 * i, 0.5)
        let float: Double = sin(clock * 1.3 + i * 2) * 4
        let angle: Double = pos == 0 ? -6 : pos * 12
        let x = CGFloat(pos * 64)
        let y = CGFloat(float + (1 - enter) * 50)
        let scale = CGFloat(0.8 + 0.2 * enter)
        let fade: Double = Ease.clamp(enter * 2)
        if let item = side.item {
            HoldingArt(product: DemoData.product(item), identity: nil, cornerRadius: 8, caption: false)
                .frame(width: 104, height: 145)
                .rotationEffect(.degrees(angle))
                .offset(x: x, y: y)
                .scaleEffect(scale)
                .opacity(fade)
        }
    }
}

/// The lime deal card. Ink text on lime (never pink on lime); the profit panel is ink with a
/// lime figure.
private struct DealPanel: View {
    var spec: DealSpec
    var t: Double

    var body: some View {
        let shape = RoundedRectangle(cornerRadius: 28, style: .continuous)
        let flash: Double = (t >= 3.5 && t <= 4.1) ? sin(Double.pi * (t - 3.5) / 0.6) : 0
        let counted: Double = Ease.out(t, 2.2, 1.2)
        VStack(alignment: .leading, spacing: 12) {
            SkewTag(text: spec.tag, color: Theme.ink, textColor: Theme.lime, icon: spec.icon)
                .opacity(Ease.out(t, 0.2, 0.3))
            DealRowView(label: "Coming in", side: spec.coming, enter: Ease.back(t, 0.5, 0.5))
            DealRowView(label: "Going out", side: spec.going, enter: Ease.out(t, 0.9, 0.4))
            VStack(alignment: .leading, spacing: 2) {
                MonoLabel(text: spec.cashLabel, color: Theme.ink.opacity(0.6))
                Text(Format.money(spec.cash * counted))
                    .font(.display(40)).tracking(-1.5).monospacedDigit()
                    .lineLimit(1).minimumScaleFactor(0.7)
            }
            .opacity(Ease.out(t, 2.2, 0.3))
            DealProfit(ahead: spec.ahead, pop: Ease.back(t, 3.5, 0.4))
                .sensoryFeedback(.impact(weight: .light), trigger: t >= 3.5) { _, new in new }
        }
        .padding(.horizontal, 22)
        .padding(.vertical, 20)
        .frame(maxWidth: .infinity, alignment: .leading)
        .background(shape.fill(Theme.lime))
        .overlay(shape.strokeBorder(Color.white.opacity(0.35), lineWidth: 1))
        .overlay(shape.strokeBorder(Color.white, lineWidth: 3).opacity(0.9 * flash))
        .foregroundStyle(Theme.ink)
    }
}

/// One side of the deal: its label, then the card (or cash) arriving from the right.
private struct DealRowView: View {
    var label: String
    var side: WelcomeDealSide
    /// 0 to 1 (with overshoot): the row arriving.
    var enter: Double

    var body: some View {
        let early: Double = 1 - min(enter, 1)
        let thumbAngle: Double = (1 - enter) * 25
        let thumbScale = CGFloat(1 + early * 0.8)
        let rowX = CGFloat((1 - enter) * 300)
        let rowFade: Double = Ease.clamp(enter * 2)
        VStack(alignment: .leading, spacing: 6) {
            MonoLabel(text: label, color: Theme.ink.opacity(0.6))
            HStack(spacing: 10) {
                ZStack {
                    if let item = side.item {
                        HoldingArt(product: DemoData.product(item), identity: nil, cornerRadius: 3, caption: false)
                            .rotationEffect(.degrees(thumbAngle))
                            .scaleEffect(thumbScale)
                    } else {
                        RoundedRectangle(cornerRadius: 4, style: .continuous).fill(Theme.ink)
                        Image(systemName: "banknote").font(.system(size: 12, weight: .bold)).foregroundStyle(Theme.lime)
                    }
                }
                .frame(width: 26, height: 36)
                Text(side.name).font(.geist(16, .semibold))
                Spacer()
                Text(Format.moneyWhole(side.value)).font(.geist(16, .semibold)).monospacedDigit()
            }
            .offset(x: rowX)
            .opacity(rowFade)
        }
    }
}

/// The dark panel that punches in: "You come out ahead" and the big lime figure.
private struct DealProfit: View {
    var ahead: Double
    /// 0 to 1 (with overshoot).
    var pop: Double

    var body: some View {
        HStack {
            HStack(spacing: 6) {
                Image(systemName: "arrow.up.right").font(.system(size: 11, weight: .bold)).foregroundStyle(Theme.lime)
                Text("You come out ahead").font(.geist(13, .semibold)).foregroundStyle(.white)
            }
            Spacer()
            Text("+" + Format.moneyWhole(ahead))
                .font(.display(26)).tracking(-0.8).monospacedDigit()
                .foregroundStyle(Theme.lime)
        }
        .lineLimit(1)
        .padding(.horizontal, 16)
        .frame(height: 50)
        .background(RoundedRectangle(cornerRadius: 16, style: .continuous).fill(Theme.ink))
        .scaleEffect(CGFloat(0.6 + 0.4 * pop))
        .opacity(Ease.clamp(pop * 2))
    }
}

// MARK: - Shared: a fixed-size picture, shrunk to fit a shorter page

/// Lays the picture out at its natural height and shrinks it (never grows it) to the page.
private struct WelcomeFit<Content: View>: View {
    var height: CGFloat
    /// How much it may grow on a taller page (1: never).
    var grow: CGFloat = 1
    /// Where it sits in its space when there's room to spare (bottom: close to the heading).
    var alignment: Alignment = .center
    @ViewBuilder var content: Content

    var body: some View {
        GeometryReader { geo in
            let scale = min(grow, geo.size.height / height)
            // Laid out at the width it will fill once scaled, so its margins stay on screen.
            content
                .frame(width: geo.size.width / scale, height: height, alignment: alignment)
                .scaleEffect(scale, anchor: alignment == .bottom ? .bottom : .center)
                .frame(width: geo.size.width, height: geo.size.height, alignment: alignment)
        }
    }
}

// MARK: - Page 3: a card graded, into its slab

/// One card the grading page shows: raw, then graded, and both values.
private struct GradeShow {
    var slug: String
    var company: String
    var grade: String
    var raw: Double
    var graded: Double
    /// The bumpers tried on in turn (indexes into `GradeShow.bumpers`); the last one stays.
    var picks: [Int]

    var gain: Double { raw > 0 ? graded / raw - 1 : 0 }

    /// The bumpers offered in the picker.
    static let bumpers: [Bumper] = ["rainbow", "galaxy", "yellow", "blue", "black"].compactMap { Bumper.byId($0) }

    static let all: [GradeShow] = [
        GradeShow(slug: "pikachu-ex-ss", company: "PSA", grade: "10", raw: 371.5, graded: 1250, picks: [3, 1, 2]),
        GradeShow(slug: "umbreon-vmax-alt", company: "CGC", grade: "10", raw: 1392, graded: 2850, picks: [2, 0, 1]),
        GradeShow(slug: "charizard-base", company: "BGS", grade: "9.5", raw: 455, graded: 1480, picks: [4, 3, 0]),
    ]
}

/// The grading page on loop, off one clock: a raw card sits under a lime glow, a slab drops
/// over it, its edge flashes, the value climbs from raw to graded and a gain tag springs in;
/// then the bumper picker comes up and bumpers are tried on until one stays. Then the next
/// card. The slab is redrawn only when its card or bumper changes (otherwise it only moves).
private struct WelcomeGrading: View {
    static let cycle: Double = 8.5
    private static let start = Date()
    @Environment(\.accessibilityReduceMotion) private var reduceMotion
    @Environment(\.welcomeActive) private var active

    var body: some View {
        WelcomeFit(height: 500, grow: 1.05, alignment: .bottom) {
            ZStack {
                Ellipse()
                    .fill(Theme.lime.opacity(0.26))
                    .frame(width: 320, height: 160)
                    .blur(radius: 50)
                    .offset(y: 40)
                if reduceMotion {
                    GradingScene(show: GradeShow.all[0], t: 6.5, clock: 0)
                } else {
                    TimelineView(.animation(minimumInterval: nil, paused: !active)) { context in
                        let s = context.date.timeIntervalSince(Self.start)
                        let n = Int(s / Self.cycle)
                        GradingScene(show: GradeShow.all[n % GradeShow.all.count], t: s - Double(n) * Self.cycle, clock: s)
                    }
                }
            }
        }
        .accessibilityElement(children: .ignore)
        .accessibilityLabel("Cards graded by PSA, CGC and BGS. A Pikachu ex graded PSA 10, in its slab: \(Format.money(371.5)) raw, \(Format.money(1250)) graded, then a bumper chosen for it")
    }
}

/// The grading page at local time `t`: the values on top (raw, then graded counting up), the
/// card and its slab over slowly turning lime rays, the gain tag on the slab's edge, and the
/// bumper picker underneath.
private struct GradingScene: View {
    var show: GradeShow
    var t: Double
    /// Seconds, for the rays' slow turn.
    var clock: Double

    private static let slabW: CGFloat = 214
    private static let slabH: CGFloat = 342

    var body: some View {
        let appear: Double = Ease.out(t, 0, 0.4)
        let leave: Double = 1 - Ease.out(t, WelcomeGrading.cycle - 0.5, 0.45)
        let drop: Double = Ease.back(t, 0.8, 0.6)
        let slabY = CGFloat((1 - drop) * -560)
        let slabFade: Double = Ease.clamp((t - 0.8) / 0.12)
        let rawFade: Double = 1 - Ease.out(t, 1.3, 0.2)
        let rawAngle: Double = -5 * (1 - Ease.out(t, 0.8, 0.6))
        let flash: Double = (t >= 1.4 && t <= 2.0) ? sin(Double.pi * (t - 1.4) / 0.6) : 0
        let bump = CGFloat(1 + 0.04 * flash)
        // The case closing over the card: a quick squash as it lands, and a tap.
        let landing: Double = (t >= 1.35 && t <= 1.6) ? sin(Double.pi * (t - 1.35) / 0.25) : 0
        let squash = CGFloat(1 - 0.035 * landing)
        let landed: Bool = t >= 1.38
        let gradedShown: Double = Ease.out(t, 1.5, 0.3)
        let value: Double = show.raw + (show.graded - show.raw) * Ease.out(t, 1.6, 1.0)
        let tag: Double = Ease.back(t, 2.6, 0.35)
        let rays: Double = 0.55 * Ease.out(t, 1.4, 0.8)
        let rayTurn: Double = clock * 8
        let picker: Double = Ease.out(t, 3.0, 0.35)
        let bumping = BumperTiming(show: show, t: t)
        let bumper: Bumper? = bumping.bumper
        let pop = CGFloat(bumping.pop)
        let item = DemoData.items.first { $0.slug == show.slug }
        VStack(spacing: 18) {
            ZStack {
                GradingRays()
                    .frame(width: 440, height: 440)
                    .rotationEffect(.degrees(rayTurn))
                    .opacity(rays)
                if let item, rawFade > 0 {
                    HoldingArt(product: DemoData.product(item), identity: nil, cornerRadius: 12, caption: false)
                        .frame(width: Self.slabW, height: Self.slabW * 88 / 63)
                        .rotationEffect(.degrees(rawAngle))
                        .opacity(rawFade)
                }
                WelcomeSlab(slug: show.slug, company: show.company, grade: show.grade, bumper: bumper?.id)
                    .equatable()
                    .frame(width: Self.slabW, height: Self.slabH)
                    .overlay(
                        RoundedRectangle(cornerRadius: 16, style: .continuous)
                            .strokeBorder(Theme.lime, lineWidth: 3)
                            .opacity(0.9 * flash)
                    )
                    .scaleEffect(x: bump * pop, y: bump * pop * squash, anchor: .bottom)
                    .offset(y: slabY)
                    .opacity(slabFade)
            }
            .frame(height: Self.slabH)
            // Raw to graded and the gain, in one pill under the slab.
            GradingValues(show: show, value: value, gradedShown: gradedShown, tag: tag)
            BumperPickerDemo(ringAt: bumping.ringAt, ringShown: bumping.ringShown, name: bumper?.name)
                .offset(y: CGFloat((1 - picker) * 24))
                .opacity(picker)
        }
        .opacity(min(appear, leave))
        .sensoryFeedback(.impact(weight: .medium), trigger: landed) { _, new in new }
    }
}

/// The values under the slab, in one glass pill: the raw price, an arrow, the grade and the
/// graded price counting up in lime, then the gain tag. The final figure sets the width, so
/// nothing shifts while the digits run.
private struct GradingValues: View {
    var show: GradeShow
    var value: Double
    var gradedShown: Double
    /// 0 to 1 (with overshoot): the gain tag springing in.
    var tag: Double

    var body: some View {
        HStack(spacing: 10) {
            Text(Format.moneyWhole(show.raw)).font(.geist(15, .semibold)).monospacedDigit()
                .foregroundStyle(gradedShown > 0.5 ? welcomeSoft : .white)
            Image(systemName: "arrow.right")
                .font(.system(size: 11, weight: .bold))
                .foregroundStyle(welcomeSoft)
                .opacity(gradedShown)
            HStack(spacing: 6) {
                MonoLabel(text: show.company + " " + show.grade, color: Theme.lime)
                Text(Format.moneyWhole(show.graded)).font(.geist(15, .semibold)).monospacedDigit()
                    .hidden()
                    .overlay(alignment: .leading) {
                        Text(Format.moneyWhole(value)).font(.geist(15, .semibold)).monospacedDigit()
                            .foregroundStyle(Theme.lime)
                            .fixedSize()
                    }
            }
            .opacity(gradedShown)
            SkewTag(text: Format.signedPercent(show.gain), icon: "arrow.up.right")
                .scaleEffect(CGFloat(0.6 + 0.4 * tag))
                .opacity(Ease.clamp(tag * 2))
        }
        .lineLimit(1)
        .fixedSize()
        .foregroundStyle(.white)
        .padding(.horizontal, 16)
        .frame(height: 44)
        .liquidGlass(in: Capsule())
    }
}

/// Soft lime light rays fanning out from the middle, fading toward the edge (one still picture;
/// the page turns it slowly).
private struct GradingRays: View {
    var body: some View {
        let stops: [Gradient.Stop] = (0 ..< 24).map { i in
            Gradient.Stop(color: i % 2 == 0 ? Theme.lime.opacity(0.35) : .clear, location: Double(i) / 24)
        } + [Gradient.Stop(color: Theme.lime.opacity(0.35), location: 1)]
        Circle()
            .fill(AngularGradient(stops: stops, center: .center))
            .mask(RadialGradient(colors: [.white, .white.opacity(0.4), .clear], center: .center, startRadius: 40, endRadius: 220))
            .allowsHitTesting(false)
    }
}

/// Where the grading page's bumper part is at local time `t`: which bumper is on (if any), the
/// little bounce as one goes on, and where the picker's ring is (gliding between swatches).
private struct BumperTiming {
    static let times: [Double] = [4.1, 4.9, 5.7]
    var bumper: Bumper?
    var pop: Double = 1
    var ringAt: Double = 0
    var ringShown: Double = 0

    init(show: GradeShow, t: Double) {
        let times = Self.times
        let tried = times.filter { t >= $0 }.count
        let picks = show.picks
        guard !picks.isEmpty else { return }
        if tried > 0 {
            let pick = picks[min(tried, picks.count) - 1]
            bumper = GradeShow.bumpers[pick]
            let since = t - times[tried - 1]
            pop = 1 + 0.04 * max(0, 1 - since / 0.3)
        }
        // The ring arrives on the first swatch just before it goes on, then glides to each next.
        ringShown = Ease.out(t, times[0] - 0.3, 0.2)
        ringAt = Double(picks[0])
        for k in 1 ..< min(picks.count, times.count) {
            let from = Double(picks[k - 1])
            let to = Double(picks[k])
            let glide = Ease.out(t, times[k] - 0.3, 0.3)
            if glide > 0 { ringAt = from + (to - from) * glide }
        }
    }
}

/// The slab, redrawn only when the card or grade changes (not on every frame of its fall).
private struct WelcomeSlab: View, Equatable {
    var slug: String
    var company: String
    var grade: String
    var bumper: String?

    var body: some View {
        let item = DemoData.items.first { $0.slug == slug }
        Slab(product: item.map { DemoData.product($0) }, company: company, grade: grade, bumper: Bumper.byId(bumper))
    }
}

/// The bumper picker as the page shows it: "Bumper" and the chosen one's name, a row of
/// swatches, and a white ring gliding to the one being tried on.
private struct BumperPickerDemo: View {
    /// Which swatch the ring is on (fractional while it glides).
    var ringAt: Double
    var ringShown: Double
    var name: String?

    private static let size: CGFloat = 36
    private static let gap: CGFloat = 12

    var body: some View {
        let bumpers = GradeShow.bumpers
        let rowWidth = CGFloat(bumpers.count) * Self.size + CGFloat(bumpers.count - 1) * Self.gap
        let ringX = CGFloat(ringAt) * (Self.size + Self.gap)
        VStack(spacing: 10) {
            HStack(spacing: 8) {
                MonoLabel(text: "Bumper", color: welcomeSoft)
                Text(name ?? "Choose one").font(.geist(13, .semibold)).foregroundStyle(.white)
            }
            ZStack(alignment: .leading) {
                HStack(spacing: Self.gap) {
                    ForEach(bumpers) { b in
                        RoundedRectangle(cornerRadius: 10, style: .continuous)
                            .fill(b.fill)
                            .frame(width: Self.size, height: Self.size)
                            .overlay(RoundedRectangle(cornerRadius: 10, style: .continuous).strokeBorder(.white.opacity(0.15)))
                    }
                }
                RoundedRectangle(cornerRadius: 13, style: .continuous)
                    .strokeBorder(Color.white, lineWidth: 2)
                    .frame(width: Self.size + 6, height: Self.size + 6)
                    .offset(x: ringX - 3)
                    .opacity(ringShown)
            }
            .frame(width: rowWidth, alignment: .leading)
        }
    }
}

// MARK: - Page 4: a master set filling in

/// A pocket of the binder page: a card by its number, owned, missing (an empty sleeve), bought
/// during the loop, or the set's chase card (in the middle, lighting up as the set fills).
private struct SetStripCard {
    var number: Int
    var missing: Bool = false
    var bought: Bool = false
    var chase: Bool = false
    /// The chase cards use the large picture (already on the phone from the demo).
    var big: Bool = false
}

/// One set the page shows. The page takes the sets in turn, turning the binder page between them.
private struct SetShow {
    var code: String
    var name: String
    /// The series and year, over the name.
    var era: String
    var total: Int
    var startCount: Int
    var endCount: Int
    /// Nine pockets, three by three; the middle one is the chase card.
    var pockets: [SetStripCard]

    func url(_ card: SetStripCard) -> URL? {
        URL(string: "https://images.pokemontcg.io/\(code)/\(card.number)\(card.big ? "_hires" : "").png")
    }

    static let all: [SetShow] = [
        // Each set's best art: alternate arts and illustration rares around its chase card.
        SetShow(code: "swsh7", name: "Evolving Skies", era: "Sword & Shield · 2021", total: 203, startCount: 160, endCount: 173, pockets: [
            SetStripCard(number: 167), SetStripCard(number: 175), SetStripCard(number: 184),
            SetStripCard(number: 189, missing: true, bought: true), SetStripCard(number: 215, chase: true, big: true), SetStripCard(number: 212, missing: true),
            SetStripCard(number: 205), SetStripCard(number: 209), SetStripCard(number: 218, big: true),
        ]),
        SetShow(code: "sv3pt5", name: "Scarlet & Violet—151", era: "Scarlet & Violet · 2023", total: 207, startCount: 150, endCount: 163, pockets: [
            SetStripCard(number: 166), SetStripCard(number: 168), SetStripCard(number: 170),
            SetStripCard(number: 173, missing: true, bought: true), SetStripCard(number: 199, chase: true, big: true), SetStripCard(number: 205, missing: true, big: true),
            SetStripCard(number: 198), SetStripCard(number: 200), SetStripCard(number: 201),
        ]),
        SetShow(code: "sv8", name: "Surging Sparks", era: "Scarlet & Violet · 2024", total: 252, startCount: 180, endCount: 193, pockets: [
            SetStripCard(number: 192), SetStripCard(number: 193), SetStripCard(number: 194),
            SetStripCard(number: 195, missing: true, bought: true), SetStripCard(number: 238, chase: true, big: true), SetStripCard(number: 196, missing: true),
            SetStripCard(number: 197), SetStripCard(number: 198), SetStripCard(number: 199),
        ]),
    ]
}


/// The master set page on loop, off one clock: a binder page under the set's name, plastic
/// sleeves catching the light. The chase card in the middle starts dark and lights up from the
/// bottom as the share climbs; a missing card slides into its empty sleeve with a glint; the chase
/// card comes fully alight with a lime edge; then the page turns to the next set.
private struct WelcomeMasterSet: View {
    static let cycle: Double = 7.5
    private static let start = Date()
    @Environment(\.accessibilityReduceMotion) private var reduceMotion
    @Environment(\.welcomeActive) private var active

    var body: some View {
        WelcomeFit(height: 610, alignment: .bottom) {
            ZStack {
                Ellipse()
                    .fill(Theme.lime.opacity(0.18))
                    .frame(width: 340, height: 220)
                    .blur(radius: 60)
                    .offset(y: 60)
                if reduceMotion {
                    MasterSetScene(set: SetShow.all[0], t: 5.5)
                } else {
                    TimelineView(.animation(minimumInterval: nil, paused: !active)) { context in
                        let s = context.date.timeIntervalSince(Self.start)
                        let n = Int(s / Self.cycle)
                        MasterSetScene(set: SetShow.all[n % SetShow.all.count], t: s - Double(n) * Self.cycle)
                    }
                }
            }
            .padding(.horizontal, 24)
        }
        .accessibilityElement(children: .ignore)
        .accessibilityLabel("A binder page of a master set: the chase card lighting up as the set fills, a missing card going into its sleeve")
    }
}

/// The set's page at local time `t`.
private struct MasterSetScene: View {
    var set: SetShow
    var t: Double

    static let boughtAt: Double = 2.6
    static let chaseAt: Double = 3.9

    var body: some View {
        let turnIn: Double = Ease.out(t, 0, 0.6)
        let turnOut: Double = Ease.out(t, WelcomeMasterSet.cycle - 0.6, 0.55)
        let pageAngle: Double = 75 * (1 - turnIn) - 75 * turnOut
        let fade: Double = min(turnIn, 1 - turnOut)
        let climb: Double = Ease.out(t, 0.4, 2.2)
        let bought: Double = Ease.out(t, Self.boughtAt, 0.5)
        let span: Double = Double(set.endCount - 1 - set.startCount)
        let climbed: Int = Int((span * climb).rounded())
        let extra: Int = bought >= 0.5 ? 1 : 0
        let count: Int = set.startCount + climbed + extra
        let pct: Int = Int((Double(count) / Double(set.total) * 100).rounded())
        let reveal: Double = min(1, 0.2 + 0.6 * climb + 0.2 * Ease.out(t, Self.chaseAt, 0.5))
        let lit: Double = Ease.out(t, Self.chaseAt + 0.3, 0.3) * (1 - Ease.out(t, Self.chaseAt + 1.6, 0.6))
        let glint: Double = Ease.clamp((t - Self.boughtAt - 0.45) / 0.5)
        let chaseGlow: Double = Ease.out(t, Self.chaseAt + 0.3, 0.6)
        VStack(spacing: 14) {
            // The heading stays still; only the binder page turns.
            VStack(spacing: 6) {
                MonoLabel(text: set.era, color: welcomeSoft)
                Text(set.name).font(.display(26)).tracking(-0.8)
                HStack(alignment: .firstTextBaseline, spacing: 8) {
                    Text("\(pct)%").font(.display(34)).tracking(-1.2).monospacedDigit().foregroundStyle(Theme.lime)
                    Text("\(count) of \(set.total) cards").font(.geist(14)).monospacedDigit().foregroundStyle(welcomeSoft)
                }
            }
            // Sized (with the page's height) so the heading always sits clear of the status bar.
            // The binder's other pages lie underneath, peeking out below; only the top page turns.
            BinderPage(set: set, bought: bought, reveal: reveal, lit: lit, glow: chaseGlow, glint: glint)
                .hidden()
                .overlay { BinderLayers() }
                .overlay {
                    BinderPage(set: set, bought: bought, reveal: reveal, lit: lit, glow: chaseGlow, glint: glint)
                        .rotation3DEffect(.degrees(pageAngle), axis: (x: 0, y: 1, z: 0), anchor: .leading, perspective: 0.5)
                        .opacity(fade)
                }
                .frame(maxWidth: 320)
                .padding(.bottom, 30)
        }
        .foregroundStyle(.white)
    }
}

/// The binder's pages under the top one: two dark pages, each a little smaller and lower, so their
/// edges peek out below like a stack. Still.
private struct BinderLayers: View {
    var body: some View {
        let shape = RoundedRectangle(cornerRadius: 22, style: .continuous)
        ZStack {
            ForEach([2, 1], id: \.self) { depth in
                let d = CGFloat(depth)
                shape
                    .fill(LinearGradient(colors: [Color(hex: 0x1A1A1D), Color(hex: 0x0F0F11)], startPoint: .top, endPoint: .bottom))
                    .overlay(shape.strokeBorder(Color.white.opacity(0.08), lineWidth: 1))
                    .overlay(shape.strokeBorder(LinearGradient(colors: [.white.opacity(0.22), .clear], startPoint: .bottom, endPoint: .top), lineWidth: 1))
                    .scaleEffect(1 - 0.045 * d, anchor: .bottom)
                    .offset(x: 5 * d, y: 15 * d)
                    .opacity(1 - 0.25 * Double(depth))
            }
        }
    }
}

/// The binder page: three rows of three plastic sleeves on a dark page.
private struct BinderPage: View {
    var set: SetShow
    var bought: Double
    var reveal: Double
    var lit: Double
    /// The chase card's glow once it's alight (stays on).
    var glow: Double
    var glint: Double

    var body: some View {
        let shape = RoundedRectangle(cornerRadius: 22, style: .continuous)
        VStack(spacing: 10) {
            ForEach(0 ..< 3, id: \.self) { row in
                HStack(spacing: 10) {
                    ForEach(0 ..< 3, id: \.self) { col in
                        let card = set.pockets[row * 3 + col]
                        BinderSleeve(card: card, url: set.url(card),
                                     bought: card.bought ? bought : 0,
                                     reveal: card.chase ? reveal : 1,
                                     lit: card.chase ? lit : 0,
                                     glow: card.chase ? glow : 0,
                                     glint: card.bought ? glint : 0)
                            .zIndex(card.chase ? 1 : 0)
                    }
                }
            }
        }
        .padding(14)
        .background(
            ZStack {
                shape.fill(LinearGradient(colors: [Color(hex: 0x1A1A1D), Color(hex: 0x0F0F11)], startPoint: .top, endPoint: .bottom))
                shape.strokeBorder(Color.white.opacity(0.08), lineWidth: 1)
            }
        )
    }
}

/// One sleeve: the clear pocket (an empty one shows the page through it), the card in it, a
/// sheen across the plastic. The chase card shows dark with its lit part rising from the bottom;
/// a bought card slides up into its sleeve and a glint runs across it.
private struct BinderSleeve: View {
    var card: SetStripCard
    var url: URL?
    var bought: Double
    var reveal: Double
    var lit: Double
    var glow: Double = 0
    var glint: Double

    var body: some View {
        let shape = RoundedRectangle(cornerRadius: 6, style: .continuous)
        let present: Bool = !card.missing || bought > 0
        let slide = CGFloat(card.bought ? (1 - bought) * 60 : 0)
        ZStack {
            shape.fill(Color.white.opacity(0.03))
            if !present {
                // An empty sleeve: a ghost of the card that goes here, and its number.
                SetCardArt(url: url).equatable()
                    .saturation(0)
                    .opacity(0.14)
                    .clipShape(shape)
                Text("#\(card.number)").font(.mono(11)).foregroundStyle(Color.white.opacity(0.55))
            }
            if present {
                ZStack {
                    if card.chase {
                        SetCardArt(url: url).equatable()
                            .saturation(0).brightness(-0.25).opacity(0.45)
                        SetCardArt(url: url).equatable()
                            .mask { Rectangle().scaleEffect(x: 1, y: CGFloat(max(reveal, 0.001)), anchor: .bottom) }
                    } else {
                        SetCardArt(url: url).equatable()
                    }
                }
                .clipShape(shape)
                .offset(y: slide)
                .opacity(card.bought ? bought : 1)
            }
            // The plastic: a soft sheen and an edge.
            shape.fill(LinearGradient(colors: [.white.opacity(0.12), .clear, .white.opacity(0.04)], startPoint: .topLeading, endPoint: .bottomTrailing))
            shape.strokeBorder(Color.white.opacity(present ? 0.14 : 0.1), lineWidth: 1)
            if glint > 0, glint < 1 {
                GeometryReader { g in
                    LinearGradient(colors: [.clear, .white.opacity(0.55), .clear], startPoint: .leading, endPoint: .trailing)
                        .frame(width: g.size.width * 0.5, height: g.size.height * 1.6)
                        .rotationEffect(.degrees(20))
                        .offset(x: CGFloat(-0.8 + 1.8 * glint) * g.size.width, y: -g.size.height * 0.3)
                }
                .clipShape(shape)
            }
            if card.chase {
                shape.strokeBorder(Theme.lime, lineWidth: 2.5).opacity(max(lit, 0.6 * glow))
            }
        }
        .aspectRatio(63.0 / 88.0, contentMode: .fit)
        .clipShape(shape)
        // The chase card: a touch bigger than the rest, glowing lime once it's alight (a still
        // gradient behind it, not a blur).
        .background {
            if card.chase {
                RadialGradient(colors: [Theme.lime.opacity(0.55), .clear], center: .center, startRadius: 10, endRadius: 110)
                    .padding(-40)
                    .opacity(glow)
            }
        }
        .scaleEffect(card.chase ? 1.08 : 1)
    }
}

/// A card of the set, drawn once.
private struct SetCardArt: View, Equatable {
    var url: URL?

    var body: some View {
        CachedImage(url: url) { image in
            image.resizable().aspectRatio(contentMode: .fill)
        } placeholder: {
            Theme.well
        }
    }
}

// MARK: - Master Sets: ten options to compare (temporary)

/// The twenty Master Sets designs being compared, each its own page for now. Option 1 is the binder.
private enum MasterOption {
    static let names = ["Binder", "Dial", "Chase hero", "Fan", "Mosaic", "Your sets", "Pile", "Checklist", "Puzzle", "Orbit",
                        "Rings", "Wallet", "Big type", "Cover Flow", "Memories", "Widgets", "Live Activity", "To go", "Watch", "Apple Card", "Tilted grid"]
}

/// Where a set's loop is: the share climbing, the bought card landing, the chase card lighting.
private struct SetProgress {
    var climb: Double
    var bought: Double
    var count: Int
    var pct: Int
    /// Smooth share (for rings and bars), 0 to 1.
    var share: Double
    var reveal: Double
    var lit: Double

    static let boughtAt: Double = 2.6
    static let chaseAt: Double = 3.9

    init(set: SetShow, t: Double) {
        climb = Ease.out(t, 0.4, 2.2)
        bought = Ease.out(t, Self.boughtAt, 0.5)
        let span: Double = Double(set.endCount - 1 - set.startCount)
        let climbed: Int = Int((span * climb).rounded())
        let extra: Int = bought >= 0.5 ? 1 : 0
        count = set.startCount + climbed + extra
        pct = Int((Double(count) / Double(set.total) * 100).rounded())
        let smooth: Double = Double(set.startCount) + span * climb + bought
        share = smooth / Double(set.total)
        reveal = min(1, 0.2 + 0.6 * climb + 0.2 * Ease.out(t, Self.chaseAt, 0.5))
        lit = Ease.out(t, Self.chaseAt + 0.3, 0.6)
    }
}

/// One option's page: its label at the top, then the design, off one clock (paused off screen).
private struct WelcomeMasterOption: View {
    var option: Int
    static let cycle: Double = 7.5
    private static let start = Date()
    @Environment(\.accessibilityReduceMotion) private var reduceMotion
    @Environment(\.welcomeActive) private var active

    var body: some View {
        Group {
            if option == 1 {
                WelcomeMasterSet()
            } else if option == 21 {
                // Full bleed like the first page, one set, the grid drifting on its own.
                if reduceMotion {
                    MSVTiltGrid(set: SetShow.all[0], p: SetProgress(set: SetShow.all[0], t: 6), clock: 0)
                } else {
                    TimelineView(.animation(minimumInterval: nil, paused: !active)) { context in
                        MSVTiltGrid(set: SetShow.all[0], p: SetProgress(set: SetShow.all[0], t: 6),
                                    clock: context.date.timeIntervalSince(Self.start))
                    }
                }
            } else {
                WelcomeFit(height: 540, alignment: .bottom) {
                    Group {
                        if reduceMotion {
                            scene(set: SetShow.all[0], t: 5.5, clock: 0)
                        } else {
                            TimelineView(.animation(minimumInterval: nil, paused: !active)) { context in
                                let s = context.date.timeIntervalSince(Self.start)
                                let n = Int(s / Self.cycle)
                                scene(set: SetShow.all[n % SetShow.all.count], t: s - Double(n) * Self.cycle, clock: s)
                            }
                        }
                    }
                    .padding(.horizontal, 24)
                }
            }
        }
        .overlay(alignment: .top) {
            Text("Option \(option) · \(MasterOption.names[option - 1])")
                .font(.mono(11)).tracking(1.2).textCase(.uppercase)
                .foregroundStyle(Theme.ink)
                .padding(.horizontal, 10).padding(.vertical, 4)
                .background(Capsule().fill(Theme.lime))
                .padding(.top, 6)
        }
    }

    @ViewBuilder private func scene(set: SetShow, t: Double, clock: Double) -> some View {
        let p = SetProgress(set: set, t: t)
        let fade: Double = min(Ease.out(t, 0, 0.45), 1 - Ease.out(t, Self.cycle - 0.5, 0.45))
        Group {
            switch option {
            case 2: MSVDial(set: set, p: p, clock: clock)
            case 3: MSVChase(set: set, p: p)
            case 4: MSVFan(set: set, p: p, clock: clock)
            case 5: MSVMosaic(set: set, p: p, t: t)
            case 6: MSVSets(t: t)
            case 7: MSVPile(set: set, p: p, t: t)
            case 8: MSVChecklist(set: set, p: p, t: t)
            case 9: MSVPuzzle(set: set, p: p)
            case 10: MSVOrbit(set: set, p: p, clock: clock)
            case 11: MSVRings(t: t)
            case 12: MSVWallet(set: set, p: p, t: t)
            case 13: MSVBigType(set: set, p: p, clock: clock)
            case 14: MSVCoverFlow(set: set, p: p, clock: clock)
            case 15: MSVMemories(set: set, p: p, clock: clock)
            case 16: MSVWidgets(set: set, p: p)
            case 17: MSVLiveActivity(set: set, p: p)
            case 18: MSVToGo(set: set, p: p)
            case 19: MSVWatch(set: set, p: p)
            case 20: MSVCardShine(set: set, p: p, clock: clock)
            default: MSVTiltGrid(set: set, p: p, clock: clock)
            }
        }
        .foregroundStyle(.white)
        .opacity(fade)
    }
}

/// The set's era, name, and share with its count, centred.
private struct MSVHeading: View {
    var set: SetShow
    var p: SetProgress
    var big: Bool = false

    var body: some View {
        VStack(spacing: 6) {
            MonoLabel(text: set.era, color: welcomeSoft)
            Text(set.name).font(.display(26)).tracking(-0.8)
            HStack(alignment: .firstTextBaseline, spacing: 8) {
                Text("\(p.pct)%").font(.display(big ? 48 : 34)).tracking(-1.4).monospacedDigit().foregroundStyle(Theme.lime)
                Text("\(p.count) of \(set.total) cards").font(.geist(14)).monospacedDigit().foregroundStyle(welcomeSoft)
            }
        }
    }
}

/// A card of the set as a tile: owned in full colour, missing dim and grey (the bought one fills).
private struct MSVCard: View {
    var set: SetShow
    var card: SetStripCard
    var p: SetProgress
    var radius: CGFloat = 6

    var body: some View {
        let shape = RoundedRectangle(cornerRadius: radius, style: .continuous)
        let on: Double = card.missing ? (card.bought ? p.bought : 0) : 1
        SetCardArt(url: set.url(card)).equatable()
            .saturation(on)
            .opacity(0.25 + 0.75 * on)
            .clipShape(shape)
            .overlay(shape.strokeBorder(Color.white.opacity(0.12), lineWidth: 1))
            .aspectRatio(63.0 / 88.0, contentMode: .fit)
    }
}

/// The chase card, dark, lighting up from the bottom as the set fills; a lime edge once alight.
private struct MSVChaseArt: View {
    var set: SetShow
    var p: SetProgress
    var radius: CGFloat = 12

    var body: some View {
        let shape = RoundedRectangle(cornerRadius: radius, style: .continuous)
        let chase = set.pockets.first { $0.chase } ?? set.pockets[4]
        ZStack {
            SetCardArt(url: set.url(chase)).equatable()
                .saturation(0).brightness(-0.25).opacity(0.45)
            SetCardArt(url: set.url(chase)).equatable()
                .mask { Rectangle().scaleEffect(x: 1, y: CGFloat(max(p.reveal, 0.001)), anchor: .bottom) }
            shape.strokeBorder(Theme.lime, lineWidth: 3).opacity(p.lit)
        }
        .clipShape(shape)
        .aspectRatio(63.0 / 88.0, contentMode: .fit)
    }
}

/// 2. Dial: the big lime ring with the share inside, a row of the set's cards drifting under it.
private struct MSVDial: View {
    var set: SetShow
    var p: SetProgress
    var clock: Double

    var body: some View {
        let cards = set.pockets
        let w: CGFloat = 70
        let listW = CGFloat(cards.count) * (w + 10)
        let x = -CGFloat((clock * 16).truncatingRemainder(dividingBy: Double(listW)))
        VStack(spacing: 22) {
            VStack(spacing: 4) {
                MonoLabel(text: set.era, color: welcomeSoft)
                Text(set.name).font(.display(26)).tracking(-0.8)
            }
            ZStack {
                Circle().stroke(Theme.lime.opacity(0.15), lineWidth: 18)
                Circle().trim(from: 0, to: CGFloat(max(p.share, 0.001)))
                    .stroke(Theme.lime, style: StrokeStyle(lineWidth: 18, lineCap: .round))
                    .rotationEffect(.degrees(-90))
                VStack(spacing: 2) {
                    Text("\(p.pct)%").font(.display(52)).tracking(-2).monospacedDigit().foregroundStyle(Theme.lime)
                    Text("\(p.count) of \(set.total)").font(.geist(13)).monospacedDigit().foregroundStyle(welcomeSoft)
                }
            }
            .frame(width: 200, height: 200)
            HStack(spacing: 10) {
                ForEach(0 ..< cards.count * 2, id: \.self) { i in
                    MSVCard(set: set, card: cards[i % cards.count], p: p).frame(width: w)
                }
            }
            .offset(x: x)
            .frame(maxWidth: .infinity, alignment: .leading)
            .clipped()
            .mask(LinearGradient(stops: [.init(color: .clear, location: 0), .init(color: .black, location: 0.12), .init(color: .black, location: 0.88), .init(color: .clear, location: 1)], startPoint: .leading, endPoint: .trailing))
        }
    }
}

/// 3. Chase hero: the set's chase card huge in the middle, lighting up as the set fills, the
/// rest of the set in a small overlapping row beneath.
private struct MSVChase: View {
    var set: SetShow
    var p: SetProgress

    var body: some View {
        let others = set.pockets.filter { !$0.chase }
        VStack(spacing: 18) {
            MSVHeading(set: set, p: p)
            ZStack {
                RadialGradient(colors: [Theme.lime.opacity(0.45), .clear], center: .center, startRadius: 20, endRadius: 170)
                    .opacity(p.lit)
                MSVChaseArt(set: set, p: p, radius: 14).frame(width: 190)
            }
            .frame(height: 270)
            HStack(spacing: -12) {
                ForEach(0 ..< others.count, id: \.self) { i in
                    MSVCard(set: set, card: others[i], p: p, radius: 4)
                        .frame(width: 46)
                        .rotationEffect(.degrees(Double(i - others.count / 2) * 4))
                }
            }
        }
    }
}

/// 4. Fan: the set's cards spread in an arc that sways gently, the share below.
private struct MSVFan: View {
    var set: SetShow
    var p: SetProgress
    var clock: Double

    var body: some View {
        let cards = set.pockets
        let sway: Double = sin(clock * 0.7) * 2
        VStack(spacing: 10) {
            ZStack {
                ForEach(0 ..< cards.count, id: \.self) { i in
                    let angle: Double = (Double(i) - Double(cards.count - 1) / 2) * 11 + sway
                    MSVCard(set: set, card: cards[i], p: p, radius: 7)
                        .frame(width: 104)
                        .shadow(color: .black.opacity(0.4), radius: 8, y: 4)
                        .rotationEffect(.degrees(angle), anchor: UnitPoint(x: 0.5, y: 2.4))
                        .zIndex(cards[i].chase ? 10 : Double(i))
                        .scaleEffect(cards[i].chase ? 1.08 : 1, anchor: .bottom)
                }
            }
            .frame(height: 330)
            .offset(y: 30)
            MSVHeading(set: set, p: p, big: true)
        }
    }
}

/// 5. Mosaic: the whole set at a glance, thirty small cards filling in left to right, the share
/// on a glass pill over them.
private struct MSVMosaic: View {
    var set: SetShow
    var p: SetProgress
    var t: Double

    var body: some View {
        let missingAt: Set<Int> = [4, 11, 17, 23, 26]
        VStack(spacing: 6) {
            ForEach(0 ..< 5, id: \.self) { row in
                HStack(spacing: 6) {
                    ForEach(0 ..< 6, id: \.self) { col in
                        let k = row * 6 + col
                        let card = SetStripCard(number: 1 + k * 6, missing: missingAt.contains(k))
                        let shown: Double = Ease.out(t, 0.3 + Double(k) * 0.06, 0.3)
                        MSVCard(set: set, card: card, p: p, radius: 4)
                            .opacity(shown)
                            .scaleEffect(CGFloat(0.9 + 0.1 * shown))
                    }
                }
            }
        }
        .overlay {
            VStack(spacing: 4) {
                Text(set.name).font(.display(22)).tracking(-0.6)
                Text("\(p.pct)%").font(.display(44)).tracking(-1.6).monospacedDigit().foregroundStyle(Theme.lime)
                Text("\(p.count) of \(set.total) cards").font(.geist(13)).monospacedDigit().foregroundStyle(welcomeSoft)
            }
            .padding(.horizontal, 24).padding(.vertical, 16)
            .liquidGlass(in: RoundedRectangle(cornerRadius: 24, style: .continuous))
        }
    }
}

/// 6. Your sets: three sets as rows, like the Master Sets list, their bars filling in turn.
private struct MSVSets: View {
    var t: Double

    var body: some View {
        VStack(alignment: .leading, spacing: 12) {
            VStack(alignment: .leading, spacing: 4) {
                MonoLabel(text: "Your master sets", color: welcomeSoft)
                Text("3 sets started").font(.display(28)).tracking(-0.8)
            }
            .padding(.bottom, 6)
            ForEach(0 ..< SetShow.all.count, id: \.self) { i in
                let set = SetShow.all[i]
                let start: Double = 0.4 + Double(i) * 0.5
                let fill: Double = Ease.out(t, start, 1.6)
                let share: Double = Double(set.endCount) / Double(set.total) * fill
                let chase = set.pockets.first { $0.chase } ?? set.pockets[4]
                HStack(spacing: 14) {
                    SetCardArt(url: set.url(chase)).equatable()
                        .clipShape(RoundedRectangle(cornerRadius: 5, style: .continuous))
                        .frame(width: 52, height: 73)
                    VStack(alignment: .leading, spacing: 8) {
                        HStack(alignment: .firstTextBaseline) {
                            VStack(alignment: .leading, spacing: 2) {
                                Text(set.name).font(.geist(16, .semibold)).lineLimit(1)
                                MonoLabel(text: set.era, color: welcomeSoft)
                            }
                            Spacer()
                            Text("\(Int((share * 100).rounded()))%").font(.display(24)).tracking(-0.8).monospacedDigit().foregroundStyle(Theme.lime)
                        }
                        ZStack(alignment: .leading) {
                            Capsule().fill(Color.white.opacity(0.1))
                            Capsule().fill(Theme.lime).scaleEffect(x: CGFloat(max(share, 0.001)), anchor: .leading)
                        }
                        .frame(height: 5)
                    }
                }
                .padding(14)
                .liquidGlass(in: RoundedRectangle(cornerRadius: 22, style: .continuous))
                .opacity(Ease.out(t, start - 0.2, 0.4))
                .offset(y: CGFloat(1 - Ease.out(t, start - 0.2, 0.4)) * 20)
            }
        }
    }
}

/// 7. Pile: the set's cards dropping one by one onto a loose pile as the count climbs; the chase
/// card still missing hangs above as a faint outline.
private struct MSVPile: View {
    var set: SetShow
    var p: SetProgress
    var t: Double

    var body: some View {
        let owned = set.pockets.filter { !$0.missing && !$0.chase }
        let chase = set.pockets.first { $0.chase } ?? set.pockets[4]
        let tilts: [Double] = [-8, 6, -3, 10, -11, 4, -5, 8]
        VStack(spacing: 22) {
            MSVHeading(set: set, p: p, big: true)
            ZStack {
                ForEach(0 ..< owned.count, id: \.self) { i in
                    let land: Double = Ease.back(t, 0.4 + Double(i) * 0.32, 0.45)
                    MSVCard(set: set, card: owned[i], p: p, radius: 8)
                        .frame(width: 150)
                        .shadow(color: .black.opacity(0.5), radius: 10, y: 6)
                        .rotationEffect(.degrees(tilts[i % tilts.count]))
                        .offset(x: CGFloat(tilts[(i + 3) % tilts.count]) * 2, y: CGFloat(1 - min(land, 1)) * -320)
                        .opacity(Ease.clamp(land * 3))
                }
                MSVChaseArt(set: set, p: p, radius: 10)
                    .frame(width: 150)
                    .rotationEffect(.degrees(-2))
                    .opacity(Ease.out(t, SetProgress.chaseAt - 0.4, 0.4))
                    .scaleEffect(CGFloat(1.1 - 0.1 * Ease.out(t, SetProgress.chaseAt - 0.4, 0.4)))
            }
            .frame(height: 270)
        }
    }
}

/// 8. Checklist: the set as a list, rows ticking off one by one; the missing ones wait unticked
/// and one ticks as it's bought.
private struct MSVChecklist: View {
    var set: SetShow
    var p: SetProgress
    var t: Double

    var body: some View {
        let rows = Array(set.pockets.prefix(7))
        VStack(spacing: 16) {
            MSVHeading(set: set, p: p)
            VStack(spacing: 0) {
                ForEach(0 ..< rows.count, id: \.self) { i in
                    let card = rows[i]
                    let tickAt: Double = card.bought ? SetProgress.boughtAt : (card.missing ? 99 : 0.4 + Double(i) * 0.28)
                    let ticked: Double = Ease.back(t, tickAt, 0.35)
                    HStack(spacing: 12) {
                        SetCardArt(url: set.url(card)).equatable()
                            .saturation(ticked > 0 ? 1 : 0)
                            .opacity(ticked > 0 ? 1 : 0.4)
                            .clipShape(RoundedRectangle(cornerRadius: 3, style: .continuous))
                            .frame(width: 28, height: 39)
                        Text("#\(card.number)").font(.mono(13)).foregroundStyle(.white)
                        Text(card.chase ? "Chase card" : (card.missing && ticked <= 0 ? "Missing" : "Owned"))
                            .font(.geist(14)).foregroundStyle(welcomeSoft)
                        Spacer()
                        ZStack {
                            Circle().strokeBorder(Color.white.opacity(0.25), lineWidth: 1.5)
                            Circle().fill(Theme.lime).scaleEffect(CGFloat(min(max(ticked, 0), 1.2)))
                            Image(systemName: "checkmark").font(.system(size: 11, weight: .bold)).foregroundStyle(Theme.ink)
                                .opacity(Ease.clamp(ticked))
                        }
                        .frame(width: 24, height: 24)
                    }
                    .padding(.vertical, 8)
                    if i < rows.count - 1 { Rectangle().fill(Color.white.opacity(0.07)).frame(height: 1) }
                }
            }
            .padding(.horizontal, 16).padding(.vertical, 6)
            .liquidGlass(in: RoundedRectangle(cornerRadius: 22, style: .continuous))
        }
    }
}

/// 9. Puzzle: the chase card's art in twelve tiles, each lighting as the set fills; complete,
/// it gets a lime edge.
private struct MSVPuzzle: View {
    var set: SetShow
    var p: SetProgress

    var body: some View {
        let chase = set.pockets.first { $0.chase } ?? set.pockets[4]
        let order: [Int] = [5, 0, 9, 3, 7, 1, 10, 4, 11, 2, 8, 6]
        let litCount: Int = p.lit > 0.5 ? 12 : Int((Double(9) * p.climb + 2 * p.bought).rounded())
        let lit: Set<Int> = Set(order.prefix(litCount))
        let shape = RoundedRectangle(cornerRadius: 14, style: .continuous)
        VStack(spacing: 18) {
            MSVHeading(set: set, p: p)
            ZStack {
                SetCardArt(url: set.url(chase)).equatable()
                    .saturation(0).brightness(-0.3).opacity(0.35)
                SetCardArt(url: set.url(chase)).equatable()
                    .mask { PuzzleTiles(lit: lit) }
                PuzzleGrid().stroke(Color.black.opacity(0.55), lineWidth: 2)
                shape.strokeBorder(Theme.lime, lineWidth: 3).opacity(p.lit)
            }
            .clipShape(shape)
            .aspectRatio(63.0 / 88.0, contentMode: .fit)
            .frame(width: 236)
        }
    }
}

/// The lit tiles of the puzzle (3 across, 4 down), as one shape.
private struct PuzzleTiles: Shape {
    var lit: Set<Int>

    func path(in r: CGRect) -> Path {
        var p = Path()
        let w = r.width / 3, h = r.height / 4
        for k in lit {
            p.addRect(CGRect(x: r.minX + CGFloat(k % 3) * w, y: r.minY + CGFloat(k / 3) * h, width: w, height: h))
        }
        return p
    }
}

/// The puzzle's seams.
private struct PuzzleGrid: Shape {
    func path(in r: CGRect) -> Path {
        var p = Path()
        for i in 1 ..< 3 { let x = r.minX + r.width * CGFloat(i) / 3; p.move(to: CGPoint(x: x, y: r.minY)); p.addLine(to: CGPoint(x: x, y: r.maxY)) }
        for j in 1 ..< 4 { let y = r.minY + r.height * CGFloat(j) / 4; p.move(to: CGPoint(x: r.minX, y: y)); p.addLine(to: CGPoint(x: r.maxX, y: y)) }
        return p
    }
}

/// 10. Orbit: the set's cards circling slowly around the share.
private struct MSVOrbit: View {
    var set: SetShow
    var p: SetProgress
    var clock: Double

    var body: some View {
        let cards = set.pockets
        let radius: CGFloat = 138
        VStack(spacing: 18) {
            VStack(spacing: 4) {
                MonoLabel(text: set.era, color: welcomeSoft)
                Text(set.name).font(.display(26)).tracking(-0.8)
            }
            ZStack {
                Circle().stroke(Color.white.opacity(0.08), lineWidth: 1).frame(width: radius * 2, height: radius * 2)
                ForEach(0 ..< cards.count, id: \.self) { i in
                    let a: Double = (Double(i) / Double(cards.count)) * 2 * .pi + clock * 0.18
                    MSVCard(set: set, card: cards[i], p: p, radius: 5)
                        .frame(width: cards[i].chase ? 66 : 54)
                        .overlay {
                            if cards[i].chase {
                                RoundedRectangle(cornerRadius: 5, style: .continuous).strokeBorder(Theme.lime, lineWidth: 2)
                            }
                        }
                        .offset(x: CGFloat(cos(a)) * radius, y: CGFloat(sin(a)) * radius)
                }
                VStack(spacing: 2) {
                    Text("\(p.pct)%").font(.display(56)).tracking(-2).monospacedDigit().foregroundStyle(Theme.lime)
                    Text("\(p.count) of \(set.total) cards").font(.geist(13)).monospacedDigit().foregroundStyle(welcomeSoft)
                }
            }
            .frame(width: radius * 2 + 70, height: radius * 2 + 90)
        }
    }
}

// MARK: Options 11-20

/// 11. Rings: one ring per set, closing in turn, like Activity; the legend beside each colour.
private struct MSVRings: View {
    var t: Double

    var body: some View {
        let colors: [Color] = [Theme.lime, Theme.planBlue, Theme.planPink]
        VStack(spacing: 26) {
            ZStack {
                ForEach(0 ..< 3, id: \.self) { i in
                    let set = SetShow.all[i]
                    let size = CGFloat(250 - i * 64)
                    let fill: Double = Ease.out(t, 0.4 + Double(i) * 0.35, 1.8)
                    let share: Double = Double(set.endCount) / Double(set.total) * fill
                    Circle().stroke(colors[i].opacity(0.18), lineWidth: 24).frame(width: size, height: size)
                    Circle().trim(from: 0, to: CGFloat(max(share, 0.001)))
                        .stroke(colors[i], style: StrokeStyle(lineWidth: 24, lineCap: .round))
                        .rotationEffect(.degrees(-90))
                        .frame(width: size, height: size)
                }
            }
            .frame(height: 280)
            VStack(spacing: 10) {
                ForEach(0 ..< 3, id: \.self) { i in
                    let set = SetShow.all[i]
                    let fill: Double = Ease.out(t, 0.4 + Double(i) * 0.35, 1.8)
                    let pct = Int((Double(set.endCount) / Double(set.total) * fill * 100).rounded())
                    HStack {
                        Capsule().fill(colors[i]).frame(width: 14, height: 4)
                        Text(set.name).font(.geist(15, .medium))
                        Spacer()
                        Text("\(pct)%").font(.display(20)).tracking(-0.6).monospacedDigit().foregroundStyle(colors[i])
                    }
                }
            }
            .padding(.horizontal, 12)
        }
    }
}

/// 12. Wallet: the sets as passes in a stack; the front one is open with its progress.
private struct MSVWallet: View {
    var set: SetShow
    var p: SetProgress
    var t: Double

    var body: some View {
        let others = SetShow.all.filter { $0.code != set.code }
        let open: Double = Ease.back(t, 0.3, 0.6)
        VStack(spacing: -150) {
            ForEach(0 ..< others.count, id: \.self) { i in
                WalletPass(set: others[i], share: Double(others[i].endCount) / Double(others[i].total), open: false)
                    .scaleEffect(CGFloat(0.92 + 0.04 * Double(i)))
            }
            WalletPass(set: set, share: p.share, open: true, count: p.count)
                .offset(y: CGFloat(1 - min(open, 1)) * 60)
        }
    }
}

/// One pass: the chase card's art across the top under a dark fade, the set's name and share.
private struct WalletPass: View {
    var set: SetShow
    var share: Double
    var open: Bool
    var count: Int = 0

    var body: some View {
        let shape = RoundedRectangle(cornerRadius: 22, style: .continuous)
        let chase = set.pockets.first { $0.chase } ?? set.pockets[4]
        VStack(alignment: .leading, spacing: 10) {
            HStack(alignment: .firstTextBaseline) {
                VStack(alignment: .leading, spacing: 2) {
                    MonoLabel(text: set.era, color: .white.opacity(0.7))
                    Text(set.name).font(.display(22)).tracking(-0.6)
                }
                Spacer()
                Text("\(Int((share * 100).rounded()))%").font(.display(28)).tracking(-1).monospacedDigit().foregroundStyle(Theme.lime)
            }
            Spacer(minLength: 0)
            if open {
                ZStack(alignment: .leading) {
                    Capsule().fill(Color.white.opacity(0.15))
                    Capsule().fill(Theme.lime).scaleEffect(x: CGFloat(max(share, 0.001)), anchor: .leading)
                }
                .frame(height: 6)
                Text("\(count) of \(set.total) cards").font(.geist(13)).monospacedDigit().foregroundStyle(.white.opacity(0.75))
            }
        }
        .padding(18)
        .frame(height: open ? 230 : 190)
        .background {
            ZStack {
                SetCardArt(url: set.url(chase)).equatable().scaleEffect(1.4).offset(y: 40)
                LinearGradient(colors: [.black.opacity(0.75), .black.opacity(0.35), .black.opacity(0.8)], startPoint: .top, endPoint: .bottom)
            }
            .clipShape(shape)
        }
        .overlay(shape.strokeBorder(Color.white.opacity(0.14), lineWidth: 1))
        .shadow(color: .black.opacity(0.5), radius: 16, y: 8)
    }
}

/// 13. Big type: the share as giant numerals filled with the chase card's art.
private struct MSVBigType: View {
    var set: SetShow
    var p: SetProgress
    var clock: Double

    var body: some View {
        let chase = set.pockets.first { $0.chase } ?? set.pockets[4]
        let drift = CGFloat(sin(clock * 0.4)) * 30
        VStack(spacing: 6) {
            MonoLabel(text: set.era, color: welcomeSoft)
            Text(set.name).font(.display(26)).tracking(-0.8)
            ZStack {
                // A faint lime base, then the art showing through the numerals.
                MSVBigNumber(text: "\(p.pct)%").foregroundStyle(Theme.lime.opacity(0.15))
                SetCardArt(url: set.url(chase)).equatable()
                    .frame(width: 420, height: 420)
                    .offset(y: drift)
                    .frame(width: 340, height: 220)
                    .mask { MSVBigNumber(text: "\(p.pct)%") }
            }
            .frame(width: 340, height: 220)
            Text("\(p.count) of \(set.total) cards").font(.geist(17)).monospacedDigit().foregroundStyle(welcomeSoft)
        }
    }
}

/// The giant numerals of the big-type option.
private struct MSVBigNumber: View {
    var text: String

    var body: some View {
        Text(text).font(.display(170)).tracking(-9).monospacedDigit()
            .minimumScaleFactor(0.5).lineLimit(1)
            .frame(width: 340, height: 220)
    }
}

/// 21. Tilted grid: the set as drifting columns of cards, like the first page but leaning the
/// other way and smaller, so more of the set shows. Cards you own are in colour; the ones you
/// don't are black tiles with their number in grey. The set's name and share sit on a glass pill.
private struct MSVTiltGrid: View {
    var set: SetShow
    var p: SetProgress
    var clock: Double

    private static let cols = 5
    private static let perCol = 7
    private static let gap: CGFloat = 8
    private static let durations: [Double] = [30, 24, 34, 27, 31]
    private static let phases: [Double] = [0.1, 0.6, 0.35, 0.8, 0.25]

    var body: some View {
        GeometryReader { geo in
            // Wider than the screen and tilted, so the edges stay covered (like the first page).
            let span = geo.size.width * 1.45
            let w = (span - Self.gap * CGFloat(Self.cols - 1)) / CGFloat(Self.cols)
            let h = w * 88 / 63
            let listH = CGFloat(Self.perCol) * (h + Self.gap)
            ZStack(alignment: .bottom) {
                HStack(alignment: .top, spacing: Self.gap) {
                    ForEach(0 ..< Self.cols, id: \.self) { c in
                        let progress = CGFloat((Self.phases[c] + clock / Self.durations[c]).truncatingRemainder(dividingBy: 1))
                        let y: CGFloat = c % 2 == 1 ? -listH + listH * progress : -listH * progress
                        VStack(spacing: Self.gap) {
                            ForEach(0 ..< Self.perCol * 3, id: \.self) { k in
                                let n = 1 + c * Self.perCol + (k % Self.perCol)
                                TiltGridTile(set: set, number: n * 3 - 2, owned: (n * 7) % 9 >= 2)
                                    .frame(width: w, height: h)
                            }
                        }
                        .offset(y: y)
                    }
                }
                .frame(width: span, height: geo.size.height * 1.5, alignment: .top)
                .rotationEffect(.degrees(10))
                .frame(width: geo.size.width, height: geo.size.height)
                .clipped()
                // Solid to the top of the screen, fading into the page at the bottom.
                .mask(LinearGradient(stops: [.init(color: .black, location: 0), .init(color: .black, location: 0.6), .init(color: .clear, location: 1)],
                                     startPoint: .top, endPoint: .bottom))
                VStack(spacing: 4) {
                    MonoLabel(text: set.era, color: welcomeSoft)
                    Text(set.name).font(.display(22)).tracking(-0.6)
                    HStack(alignment: .firstTextBaseline, spacing: 8) {
                        Text("\(p.pct)%").font(.display(34)).tracking(-1.2).monospacedDigit().foregroundStyle(Theme.lime)
                        Text("\(p.count) of \(set.total)").font(.geist(14)).monospacedDigit().foregroundStyle(welcomeSoft)
                    }
                }
                .foregroundStyle(.white)
                .padding(.horizontal, 24).padding(.vertical, 14)
                .liquidGlass(in: RoundedRectangle(cornerRadius: 24, style: .continuous))
                .padding(.bottom, 10)
            }
        }
    }
}

/// One tile of the tilted grid: the card in colour, or a black tile with its number in grey.
private struct TiltGridTile: View, Equatable {
    var set: SetShow
    var number: Int
    var owned: Bool

    static func == (a: Self, b: Self) -> Bool { a.set.code == b.set.code && a.number == b.number && a.owned == b.owned }

    var body: some View {
        let shape = RoundedRectangle(cornerRadius: 6, style: .continuous)
        if owned {
            SetCardArt(url: set.url(SetStripCard(number: number))).equatable()
                .clipShape(shape)
        } else {
            ZStack {
                shape.fill(Color(hex: 0x0B0B0C))
                shape.strokeBorder(Color.white.opacity(0.08), lineWidth: 1)
                Text("#\(number)").font(.mono(12)).foregroundStyle(welcomeSoft)
            }
        }
    }
}

/// 14. Cover Flow: the set's cards in a carousel, the middle one facing you, the rest turned away.
private struct MSVCoverFlow: View {
    var set: SetShow
    var p: SetProgress
    var clock: Double

    var body: some View {
        let cards = set.pockets
        let n = Double(cards.count)
        let pos: Double = (clock * 0.45).truncatingRemainder(dividingBy: n)
        VStack(spacing: 30) {
            ZStack {
                ForEach(0 ..< cards.count, id: \.self) { i in
                    let raw: Double = Double(i) - pos
                    let d: Double = raw > n / 2 ? raw - n : (raw < -n / 2 ? raw + n : raw)
                    let side: Double = max(-1, min(1, d))
                    let x = CGFloat(d * 62 + side * 40)
                    MSVCard(set: set, card: cards[i], p: p, radius: 8)
                        .frame(width: 170)
                        .rotation3DEffect(.degrees(-side * 58), axis: (x: 0, y: 1, z: 0), perspective: 0.5)
                        .scaleEffect(CGFloat(1 - 0.12 * abs(side)))
                        .offset(x: x)
                        .zIndex(-abs(d))
                        .opacity(abs(d) < 3.2 ? 1 : 0)
                }
            }
            .frame(height: 260)
            MSVHeading(set: set, p: p)
        }
    }
}

/// 15. Memories: the chase card's art filling a tall rounded frame, panning slowly, with the
/// set's name and share over a dark fade at the bottom, like a Photos memory.
private struct MSVMemories: View {
    var set: SetShow
    var p: SetProgress
    var clock: Double

    var body: some View {
        let chase = set.pockets.first { $0.chase } ?? set.pockets[4]
        let shape = RoundedRectangle(cornerRadius: 30, style: .continuous)
        let pan = CGFloat(sin(clock * 0.25)) * 60
        ZStack(alignment: .bottomLeading) {
            SetCardArt(url: set.url(chase)).equatable()
                .frame(width: 520, height: 720)
                .offset(x: pan, y: -pan * 0.6)
                .frame(width: 320, height: 460)
                .clipped()
            LinearGradient(colors: [.clear, .black.opacity(0.85)], startPoint: .center, endPoint: .bottom)
            VStack(alignment: .leading, spacing: 6) {
                MonoLabel(text: set.era, color: .white.opacity(0.75))
                Text(set.name).font(.display(30)).tracking(-1)
                HStack(alignment: .firstTextBaseline, spacing: 8) {
                    Text("\(p.pct)%").font(.display(30)).tracking(-1).monospacedDigit().foregroundStyle(Theme.lime)
                    Text("complete").font(.geist(15)).foregroundStyle(.white.opacity(0.75))
                }
            }
            .padding(22)
        }
        .frame(width: 320, height: 460)
        .clipShape(shape)
        .overlay(shape.strokeBorder(Color.white.opacity(0.12), lineWidth: 1))
    }
}

/// 16. Widgets: the set's progress as home screen widgets: a ring, the chase card, and a wide one.
private struct MSVWidgets: View {
    var set: SetShow
    var p: SetProgress

    var body: some View {
        let chase = set.pockets.first { $0.chase } ?? set.pockets[4]
        let shape = RoundedRectangle(cornerRadius: 24, style: .continuous)
        VStack(spacing: 14) {
            HStack(spacing: 14) {
                ZStack {
                    Circle().stroke(Theme.lime.opacity(0.18), lineWidth: 12)
                    Circle().trim(from: 0, to: CGFloat(max(p.share, 0.001)))
                        .stroke(Theme.lime, style: StrokeStyle(lineWidth: 12, lineCap: .round))
                        .rotationEffect(.degrees(-90))
                    Text("\(p.pct)%").font(.display(28)).tracking(-1).monospacedDigit().foregroundStyle(Theme.lime)
                }
                .padding(22)
                .frame(width: 150, height: 150)
                .background(shape.fill(Color(hex: 0x1C1C1E)))
                ZStack(alignment: .bottomLeading) {
                    SetCardArt(url: set.url(chase)).equatable().scaleEffect(1.3)
                    LinearGradient(colors: [.clear, .black.opacity(0.8)], startPoint: .center, endPoint: .bottom)
                    Text("Chase").font(.geist(13, .semibold)).padding(12)
                }
                .frame(width: 150, height: 150)
                .clipShape(shape)
            }
            VStack(alignment: .leading, spacing: 10) {
                HStack {
                    MonoLabel(text: "Master set", color: welcomeSoft)
                    Spacer()
                    Text("\(p.count)/\(set.total)").font(.geist(13)).monospacedDigit().foregroundStyle(welcomeSoft)
                }
                Text(set.name).font(.display(22)).tracking(-0.6)
                ZStack(alignment: .leading) {
                    Capsule().fill(Color.white.opacity(0.12))
                    Capsule().fill(Theme.lime).scaleEffect(x: CGFloat(max(p.share, 0.001)), anchor: .leading)
                }
                .frame(height: 8)
            }
            .padding(18)
            .frame(width: 314, height: 150, alignment: .topLeading)
            .background(shape.fill(Color(hex: 0x1C1C1E)))
        }
    }
}

/// 17. Live Activity: a lock screen, the time big, and the set's progress as a live card.
private struct MSVLiveActivity: View {
    var set: SetShow
    var p: SetProgress

    var body: some View {
        let chase = set.pockets.first { $0.chase } ?? set.pockets[4]
        let next = set.pockets.first { $0.missing && !$0.bought } ?? chase
        VStack(spacing: 30) {
            VStack(spacing: 0) {
                Text("Thursday, November 6").font(.geist(18, .semibold)).foregroundStyle(.white.opacity(0.8))
                Text("9:41").font(.display(96)).tracking(-3).monospacedDigit()
            }
            HStack(spacing: 14) {
                SetCardArt(url: set.url(chase)).equatable()
                    .clipShape(RoundedRectangle(cornerRadius: 6, style: .continuous))
                    .frame(width: 52, height: 73)
                VStack(alignment: .leading, spacing: 8) {
                    HStack {
                        Text(set.name).font(.geist(16, .semibold)).lineLimit(1)
                        Spacer()
                        Text("\(p.pct)%").font(.display(20)).monospacedDigit().foregroundStyle(Theme.lime)
                    }
                    ZStack(alignment: .leading) {
                        Capsule().fill(Color.white.opacity(0.15))
                        Capsule().fill(Theme.lime).scaleEffect(x: CGFloat(max(p.share, 0.001)), anchor: .leading)
                    }
                    .frame(height: 6)
                    Text("\(p.count) of \(set.total) · next: #\(next.number)").font(.geist(13)).monospacedDigit().foregroundStyle(.white.opacity(0.7))
                }
            }
            .padding(16)
            .liquidGlass(in: RoundedRectangle(cornerRadius: 26, style: .continuous))
        }
    }
}

/// 18. To go: how many cards are left, huge, with the set's ring and its missing cards beneath.
private struct MSVToGo: View {
    var set: SetShow
    var p: SetProgress

    var body: some View {
        let left = set.total - p.count
        let missing = set.pockets.filter { $0.missing }
        VStack(spacing: 14) {
            Text(set.name).font(.display(24)).tracking(-0.7)
            Text("\(left)").font(.display(150)).tracking(-7).monospacedDigit().foregroundStyle(Theme.lime)
                .displayTrim(150)
            Text("cards to go").font(.display(26)).tracking(-0.8).foregroundStyle(.white.opacity(0.8))
            HStack(spacing: 10) {
                ForEach(0 ..< missing.count, id: \.self) { i in
                    MSVCard(set: set, card: missing[i], p: p, radius: 5).frame(width: 64)
                }
            }
            .padding(.top, 10)
        }
    }
}

/// 19. Watch: sixty ticks round a dial lighting up to the share, the chase card in the middle.
private struct MSVWatch: View {
    var set: SetShow
    var p: SetProgress

    var body: some View {
        let lit = Int((p.share * 60).rounded())
        VStack(spacing: 18) {
            ZStack {
                ForEach(0 ..< 60, id: \.self) { i in
                    Capsule()
                        .fill(i < lit ? Theme.lime : Color.white.opacity(0.14))
                        .frame(width: 4, height: i % 5 == 0 ? 22 : 14)
                        .offset(y: -128)
                        .rotationEffect(.degrees(Double(i) * 6))
                }
                VStack(spacing: 8) {
                    MSVChaseArt(set: set, p: p, radius: 8).frame(width: 96)
                    Text("\(p.pct)%").font(.display(30)).tracking(-1).monospacedDigit().foregroundStyle(Theme.lime)
                }
            }
            .frame(width: 290, height: 290)
            VStack(spacing: 4) {
                Text(set.name).font(.display(24)).tracking(-0.7)
                Text("\(p.count) of \(set.total) cards").font(.geist(14)).monospacedDigit().foregroundStyle(welcomeSoft)
            }
        }
    }
}

/// 20. Apple Card: the chase card big, tilting slowly with a light sliding across it, its
/// share in small type underneath.
private struct MSVCardShine: View {
    var set: SetShow
    var p: SetProgress
    var clock: Double

    var body: some View {
        let chase = set.pockets.first { $0.chase } ?? set.pockets[4]
        let tiltX: Double = sin(clock * 0.6) * 9
        let tiltY: Double = cos(clock * 0.45) * 12
        let sweep = CGFloat(sin(clock * 0.6)) * 160
        let shape = RoundedRectangle(cornerRadius: 16, style: .continuous)
        VStack(spacing: 26) {
            ZStack {
                SetCardArt(url: set.url(chase)).equatable()
                LinearGradient(colors: [.clear, .white.opacity(0.35), .clear], startPoint: .leading, endPoint: .trailing)
                    .frame(width: 120)
                    .rotationEffect(.degrees(25))
                    .offset(x: sweep)
                    .blendMode(.plusLighter)
            }
            .frame(width: 230, height: 321)
            .clipShape(shape)
            .overlay(shape.strokeBorder(Color.white.opacity(0.18), lineWidth: 1))
            .rotation3DEffect(.degrees(tiltX), axis: (x: 1, y: 0, z: 0), perspective: 0.5)
            .rotation3DEffect(.degrees(tiltY), axis: (x: 0, y: 1, z: 0), perspective: 0.5)
            .shadow(color: Theme.lime.opacity(0.25), radius: 30, y: 10)
            VStack(spacing: 6) {
                Text(set.name).font(.display(24)).tracking(-0.7)
                HStack(spacing: 10) {
                    ZStack(alignment: .leading) {
                        Capsule().fill(Color.white.opacity(0.12))
                        Capsule().fill(Theme.lime).scaleEffect(x: CGFloat(max(p.share, 0.001)), anchor: .leading)
                    }
                    .frame(width: 160, height: 4)
                    Text("\(p.pct)%").font(.geist(15, .semibold)).monospacedDigit().foregroundStyle(Theme.lime)
                }
            }
        }
    }
}

// MARK: - Page 5: price alerts

/// A notification in the stack: what it says and when it arrives (local time).
private struct AlertNote {
    var icon: String
    var message: String
    var at: Double
}

/// One alert the page shows: a watched card, its price line crossing the target, and the
/// notifications that stack up over the loop (the last is the one this card's crossing sends).
private struct AlertShow {
    var slug: String
    var name: String
    var message: String
    var targetLabel: String
    /// The price at the top, middle and bottom of the chart.
    var axis: [String]
    /// The line's points, as a share of the chart's height from the top (higher = cheaper).
    var points: [Double]
    var target: Double
    /// Where along the line it crosses the target (0 to 1).
    var cross: Double
    /// Notifications that came in earlier in the loop.
    var earlier: [AlertNote]

    static let drawFrom: Double = 0.3
    static let drawFor: Double = 2.4
    /// When the line crosses (the main notification follows).
    var hitAt: Double { Self.drawFrom + Self.drawFor * cross }

    /// Every notification, oldest first.
    var notes: [AlertNote] { earlier + [AlertNote(icon: "bell.badge.fill", message: message, at: hitAt + 0.1)] }

    static let all: [AlertShow] = [
        AlertShow(slug: "charizard-ex-of", name: "Charizard ex",
                  message: "Charizard ex dropped to \(Format.money(58.3)), under your $60 target.",
                  targetLabel: "$60 target", axis: ["$80", "$66", "$52"],
                  points: [0.18, 0.26, 0.22, 0.34, 0.42, 0.37, 0.5, 0.58, 0.54, 0.68, 0.79, 0.86],
                  target: 0.72, cross: 0.86,
                  earlier: [AlertNote(icon: "calendar", message: "Prismatic Evolutions is out today.", at: 0.5),
                            AlertNote(icon: "arrow.up.right", message: "Gengar VMAX is up 9% this week.", at: 1.3)]),
        AlertShow(slug: "umbreon-vmax-alt", name: "Umbreon VMAX",
                  message: "Umbreon VMAX passed your $1,350 alert. Now \(Format.money(1392)).",
                  targetLabel: "$1,350 alert", axis: ["$1,420", "$1,305", "$1,190"],
                  points: [0.82, 0.74, 0.77, 0.64, 0.6, 0.62, 0.5, 0.44, 0.47, 0.34, 0.25, 0.16],
                  target: 0.3, cross: 0.88,
                  earlier: [AlertNote(icon: "arrow.down.right", message: "Mew ex dropped under $30.", at: 0.5),
                            AlertNote(icon: "calendar", message: "Journey Together is out in 3 days.", at: 1.3)]),
    ]
}

/// The alerts page on loop, off one clock: notifications stack up at the top like a lock
/// screen, while below, a watched card's price line draws full width toward its lime target;
/// where it crosses, the dot pings and that card's notification lands on top of the stack.
private struct WelcomeAlerts: View {
    static let cycle: Double = 6.5
    private static let start = Date()
    @Environment(\.accessibilityReduceMotion) private var reduceMotion
    @Environment(\.welcomeActive) private var active

    var body: some View {
        WelcomeFit(height: 540, alignment: .bottom) {
            ZStack {
                Ellipse()
                    .fill(Theme.lime.opacity(0.2))
                    .frame(width: 320, height: 160)
                    .blur(radius: 55)
                    .offset(y: 140)
                Group {
                    if reduceMotion {
                        AlertScene(show: AlertShow.all[0], t: 5)
                    } else {
                        TimelineView(.animation(minimumInterval: nil, paused: !active)) { context in
                            let s = context.date.timeIntervalSince(Self.start)
                            let n = Int(s / Self.cycle)
                            AlertScene(show: AlertShow.all[n % AlertShow.all.count], t: s - Double(n) * Self.cycle)
                        }
                    }
                }
                .padding(.horizontal, 24)
            }
        }
        .accessibilityElement(children: .ignore)
        .accessibilityLabel("Price alerts arriving: \(AlertShow.all[0].message)")
    }
}

/// The alerts page at local time `t`.
private struct AlertScene: View {
    var show: AlertShow
    var t: Double

    private static let noteH: CGFloat = 66
    private static let noteGap: CGFloat = 8

    var body: some View {
        let appear: Double = Ease.out(t, 0, 0.4)
        let leave: Double = 1 - Ease.out(t, WelcomeAlerts.cycle - 0.45, 0.4)
        let drawn: Double = Ease.clamp((t - AlertShow.drawFrom) / AlertShow.drawFor)
        let hit: Double = Ease.out(t, show.hitAt, 0.3)
        let item = DemoData.items.first { $0.slug == show.slug }
        VStack(spacing: 22) {
            AlertStack(notes: show.notes, t: t)
                .frame(height: Self.noteH + 22, alignment: .top)
            VStack(alignment: .leading, spacing: 14) {
                HStack(spacing: 12) {
                    if let item {
                        HoldingArt(product: DemoData.product(item), identity: nil, cornerRadius: 4, caption: false)
                            .frame(width: 40, height: 56)
                    }
                    VStack(alignment: .leading, spacing: 3) {
                        Text(show.name).font(.display(20)).tracking(-0.5)
                        MonoLabel(text: "Watching", color: welcomeSoft)
                    }
                    Spacer()
                    Image(systemName: "bell.fill")
                        .font(.system(size: 16, weight: .semibold))
                        .foregroundStyle(hit > 0.5 ? Theme.lime : welcomeSoft)
                }
                AlertChart(show: show, drawn: drawn, hit: hit)
                    .frame(height: 250)
            }
        }
        .foregroundStyle(.white)
        .opacity(min(appear, leave))
    }
}

/// The notifications so far, stacked like iPhone's: the newest on top at full size, each older one
/// tucked behind it, peeking out a little lower, smaller and dimmer. A new one drops in from above
/// and the others sink back a step.
private struct AlertStack: View {
    var notes: [AlertNote]
    var t: Double

    var body: some View {
        let step: CGFloat = 10
        ZStack(alignment: .top) {
            ForEach(0 ..< notes.count, id: \.self) { i in
                let note = notes[i]
                let come: Double = Ease.back(t, note.at, 0.45)
                // How many newer ones have arrived above it (fractional while they arrive).
                let above: Double = (i + 1 ..< notes.count).reduce(0.0) { $0 + Ease.out(t, notes[$1].at, 0.35) }
                let drop: Double = 1 - min(come, 1)
                let y = CGFloat(above) * step - CGFloat(drop) * 40
                let scale = CGFloat(1 - 0.06 * above)
                let fade: Double = Ease.clamp(come * 2) * (1 - 0.3 * above)
                if t >= note.at {
                    // Behind the top one only the edge shows, so its words fade out (the glass is see-through).
                    AlertBanner(icon: note.icon, message: note.message, content: 1 - min(above, 1))
                        .frame(height: 66)
                        .scaleEffect(scale, anchor: .bottom)
                        .offset(y: y)
                        .opacity(fade)
                }
            }
        }
    }
}

/// A notification, as iPhone shows it: the app's mark, "Lucent", "now" and the message.
private struct AlertBanner: View {
    var icon: String = "bell.badge.fill"
    var message: String
    /// How much of the icon and words show (0 when it's tucked behind another).
    var content: Double = 1

    var body: some View {
        HStack(alignment: .center, spacing: 12) {
            Image(systemName: icon)
                .font(.system(size: 16, weight: .semibold))
                .foregroundStyle(Theme.ink)
                .frame(width: 38, height: 38)
                .background(RoundedRectangle(cornerRadius: 9, style: .continuous).fill(Theme.lime))
            VStack(alignment: .leading, spacing: 2) {
                HStack {
                    Text("Lucent").font(.geist(14, .semibold))
                    Spacer()
                    Text("now").font(.geist(12)).foregroundStyle(welcomeSoft)
                }
                Text(message).font(.geist(13)).foregroundStyle(.white.opacity(0.9))
                    .lineLimit(2)
            }
        }
        .opacity(content)
        .padding(.horizontal, 14)
        .frame(maxWidth: .infinity, maxHeight: .infinity)
        .liquidGlass(in: RoundedRectangle(cornerRadius: 22, style: .continuous))
    }
}

/// The price line drawing toward the dashed lime target, with a dot at its tip that pings when
/// it crosses.
private struct AlertChart: View {
    var show: AlertShow
    var drawn: Double
    var hit: Double

    var body: some View {
        GeometryReader { geo in
            let w = geo.size.width
            let h = geo.size.height
            let tip = AlertLine.point(show.points, at: drawn, in: geo.size)
            let targetY = CGFloat(show.target) * h
            let ring = CGFloat(8 + 16 * hit)
            ZStack(alignment: .topLeading) {
                // A faint grid with the price at its lines, on the right.
                ForEach(0 ..< 3, id: \.self) { k in
                    let y = h * CGFloat(k) / 2
                    Path { p in
                        p.move(to: CGPoint(x: 0, y: y))
                        p.addLine(to: CGPoint(x: w, y: y))
                    }
                    .stroke(Color.white.opacity(0.07), lineWidth: 1)
                    Text(show.axis[k]).font(.mono(10)).foregroundStyle(welcomeSoft)
                        .fixedSize()
                        .frame(width: w, alignment: .trailing)
                        .offset(y: y - (k == 0 ? -4 : 16))
                }
                Path { p in
                    p.move(to: CGPoint(x: 0, y: targetY))
                    p.addLine(to: CGPoint(x: w, y: targetY))
                }
                .stroke(Theme.lime.opacity(0.8), style: StrokeStyle(lineWidth: 1.5, dash: [5, 4]))
                MonoLabel(text: show.targetLabel, color: Theme.lime)
                    .fixedSize()
                    .offset(x: 0, y: targetY - 18)
                AlertLine(points: show.points, upTo: drawn)
                    .stroke(Color.white, style: StrokeStyle(lineWidth: 2.5, lineCap: .round, lineJoin: .round))
                Circle()
                    .stroke(Theme.lime, lineWidth: 2)
                    .frame(width: ring, height: ring)
                    .opacity(hit > 0 ? 1 - hit : 0)
                    .position(tip)
                Circle()
                    .fill(hit > 0 ? Theme.lime : Color.white)
                    .frame(width: 9, height: 9)
                    .position(tip)
                    .opacity(drawn > 0 ? 1 : 0)
            }
        }
    }
}

/// The price line through evenly spaced points, drawn as far as `upTo` (0 to 1).
private struct AlertLine: Shape {
    var points: [Double]
    var upTo: Double

    func path(in r: CGRect) -> Path {
        var p = Path()
        guard points.count > 1, upTo > 0 else { return p }
        let step = r.width / CGFloat(points.count - 1)
        let pos = Ease.clamp(upTo) * Double(points.count - 1)
        p.move(to: CGPoint(x: r.minX, y: r.minY + CGFloat(points[0]) * r.height))
        for i in 1 ..< points.count where Double(i) <= pos {
            p.addLine(to: CGPoint(x: r.minX + step * CGFloat(i), y: r.minY + CGFloat(points[i]) * r.height))
        }
        let tip = Self.point(points, at: upTo, in: r.size)
        p.addLine(to: CGPoint(x: r.minX + tip.x, y: r.minY + tip.y))
        return p
    }

    /// Where the line is `share` of the way along (by step, close enough for a still tip).
    static func point(_ points: [Double], at share: Double, in size: CGSize) -> CGPoint {
        guard points.count > 1 else { return .zero }
        let pos = Ease.clamp(share) * Double(points.count - 1)
        let i = min(Int(pos), points.count - 2)
        let f = pos - Double(i)
        let v = points[i] + (points[i + 1] - points[i]) * f
        let step = size.width / CGFloat(points.count - 1)
        return CGPoint(x: CGFloat(pos) * step, y: CGFloat(v) * size.height)
    }
}
