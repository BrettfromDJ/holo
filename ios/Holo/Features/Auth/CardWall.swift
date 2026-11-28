import SwiftUI

/// Whether the card wall drifts (it stops while you type, so nothing moves under the keyboard).
private struct WelcomeActiveKey: EnvironmentKey { static let defaultValue = true }

extension EnvironmentValues {
    var welcomeActive: Bool {
        get { self[WelcomeActiveKey.self] }
        set { self[WelcomeActiveKey.self] = newValue }
    }
}

/// The app's lit grid (like Explore's) behind the sign-in screen: lime, blue and pink glows over the
/// faint grid, full bleed and unfaded (a fade behind the heading read as a dark band).
struct WelcomeBackdrop: View {
    var body: some View {
        ZStack {
            GridPattern(step: 36, opacity: 0.05)
            RadialGradient(colors: [Theme.lime.opacity(0.22), .clear], center: UnitPoint(x: 0.2, y: 0.45), startRadius: 0, endRadius: 250)
            RadialGradient(colors: [Theme.planBlue.opacity(0.2), .clear], center: UnitPoint(x: 0.9, y: 0.6), startRadius: 0, endRadius: 230)
            RadialGradient(colors: [Theme.purple.opacity(0.16), .clear], center: UnitPoint(x: 0.65, y: 0.1), startRadius: 0, endRadius: 200)
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
/// into the page.
struct WelcomeGrid: View {
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
    /// Still: no drift, drawn once into one flat picture (the sign-in screen, so the keyboard
    /// never waits on the wall).
    var still = false
    /// The card pictures, held by the grid itself and handed to the tiles.
    @State private var images: [String: UIImage] = Self.cachedImages()
    @Environment(\.accessibilityReduceMotion) private var reduceMotion
    @Environment(\.welcomeActive) private var active

    static func url(_ item: DemoData.Item) -> URL? { WelcomeTile.product(item).imageURL }
    /// The tiles are about 120 points wide, so small pictures do: full-size scans, nine copies
    /// of each column drawn every frame, kept the graphics chip busy enough to stall the keyboard.
    static let maxPixel: CGFloat = 400

    private static func cachedImages() -> [String: UIImage] {
        var out: [String: UIImage] = [:]
        for item in columns.joined() { if let u = url(item), let img = ImageCache.shared.cached(u, maxPixel: maxPixel) { out[item.slug] = img } }
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
                if still {
                    columns(at: 0, tileW: tileW, tileH: tileH)
                } else if reduceMotion {
                    columns(at: 0, tileW: tileW, tileH: tileH)
                } else {
                    // A slow drift: 30 frames a second looks the same and costs half.
                    TimelineView(.animation(minimumInterval: 1.0 / 30, paused: !active)) { context in
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
        // Still: flattened into one picture, so nothing behind the form is redrawn while the
        // keyboard slides up.
        .modifier(FlattenWhen(on: still))
        // A soft dark shade at the top, so the clock reads over the cards.
        .overlay(alignment: .top) {
            LinearGradient(colors: [.black.opacity(0.7), .black.opacity(0.35), .clear], startPoint: .top, endPoint: .bottom)
                .frame(height: 150)
                .allowsHitTesting(false)
        }
        .task {
            await withTaskGroup(of: (String, UIImage?).self) { group in
                for item in Self.columns.joined() where images[item.slug] == nil {
                    guard let u = Self.url(item) else { continue }
                    group.addTask { (item.slug, await ImageCache.shared.load(u, maxPixel: Self.maxPixel)) }
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
        .accessibilityHidden(true)
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

/// Draws the view into one flat picture when `on` (for content that doesn't move).
private struct FlattenWhen: ViewModifier {
    var on: Bool
    func body(content: Content) -> some View {
        if on { content.drawingGroup() } else { content }
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
                    WelcomeTile(image: images[item.slug] ?? WelcomeGrid.url(item).flatMap { ImageCache.shared.cached($0, maxPixel: WelcomeGrid.maxPixel) })
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

