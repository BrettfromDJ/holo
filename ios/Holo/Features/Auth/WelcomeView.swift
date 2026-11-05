import SwiftUI

/// The welcome, before sign-in: three swipeable pages (what the app does, in pictures made from
/// the demo collection), then the ways in: Sign in with Apple, email, or the demo without an
/// account. Seen once; a signed-out app later opens on the sign-in form.
struct WelcomeView: View {
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
            VStack(spacing: 0) {
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

                TabView(selection: $page) {
                    WelcomePage(title: "See what your collection is worth", line: "Every card and box you own, priced daily, with how it has moved.") {
                        WelcomeFan()
                    }
                    .tag(0)
                    WelcomePage(title: "Scan a card, know its price", line: "Point the camera at a card and its name and market price appear on it.") {
                        WelcomeScanStill()
                    }
                    .tag(1)
                    WelcomePage(title: "Make deals that add up", line: "Add what's coming in and going out; the cash, your profit and whether it's fair are worked out for you.") {
                        WelcomeDealCard()
                    }
                    .tag(2)
                }
                .tabViewStyle(.page(indexDisplayMode: .never))

                HStack(spacing: 6) {
                    ForEach(0 ... last, id: \.self) { i in
                        Capsule().fill(i == page ? Theme.lime : Color.white.opacity(0.18))
                            .frame(width: i == page ? 18 : 6, height: 6)
                    }
                }
                .animation(reduceMotion ? nil : .snappy(duration: 0.25), value: page)
                .padding(.bottom, 18)
                .accessibilityHidden(true)

                footer
                    .padding(.horizontal, 24)
                    .padding(.bottom, 12)
            }
        }
        .foregroundStyle(.white)
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
                AppleSignInButton(onSuccess: { Onboarding.shared.welcomeSeen = true }) { message in error = message }
                Button("Continue with email") {
                    Onboarding.shared.welcomeSeen = true
                    onEmail()
                }
                .buttonStyle(Button3D(kind: .dark))
                .accessibilityIdentifier("welcome-email")
                Button("Try the demo") {
                    Onboarding.shared.welcomeSeen = true
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

/// One welcome page: the picture up top, then the heading and one line.
private struct WelcomePage<Picture: View>: View {
    var title: String
    var line: String
    @ViewBuilder var picture: Picture

    var body: some View {
        VStack(spacing: 0) {
            picture
                .frame(maxWidth: .infinity)
                .frame(height: 340)
            VStack(spacing: 10) {
                // Centered, so a plain balanced-ish Text rather than the left-flowing DisplayText.
                Text(title).font(.display(34)).tracking(-1).multilineTextAlignment(.center)
                    .fixedSize(horizontal: false, vertical: true)
                Text(line).font(.geist(15)).foregroundStyle(Theme.muted).multilineTextAlignment(.center)
                    .fixedSize(horizontal: false, vertical: true)
            }
            .padding(.horizontal, 32)
            .padding(.top, 8)
            Spacer(minLength: 0)
        }
    }
}

// MARK: - Page 1: the demo fan and its worth

/// A still hand of five demo pieces over the hero's lit grid, and their worth counting up once.
private struct WelcomeFan: View {
    private static let slugs = ["umbreon-vmax-alt", "es-bb", "pikachu-ex-ss", "cel-upc", "rayquaza-vmax-alt"]
    private static let steps: [CGFloat] = [0, -1, 1, -2, 2]
    private static let tilts: [Double] = [0, -9, 9, -17, 17]
    private static let drops: [CGFloat] = [0, 15, 15, 38, 38]
    private static let scales: [CGFloat] = [1, 0.86, 0.86, 0.74, 0.74]
    private static let width: CGFloat = 96
    private static let height: CGFloat = 134

    private var items: [DemoData.Item] {
        Self.slugs.compactMap { slug in DemoData.items.first { $0.slug == slug } }
    }

    var body: some View {
        let items = self.items
        let worth = items.reduce(0.0) { $0 + $1.now }
        VStack(spacing: 14) {
            ZStack {
                // Back pieces first, so the front one sits on top.
                ForEach(Array(items.enumerated().reversed()), id: \.offset) { i, item in
                    HoldingArt(product: DemoData.product(item), identity: nil, cornerRadius: 6, caption: false)
                        .frame(width: Self.width, height: Self.height)
                        .shadow(color: .black.opacity(0.55), radius: 13, y: 18)
                        .scaleEffect(Self.scales[i], anchor: UnitPoint(x: 0.5, y: 0.9))
                        .rotationEffect(.degrees(Self.tilts[i]), anchor: UnitPoint(x: 0.5, y: 0.9))
                        .offset(x: Self.steps[i] * Self.width * 0.26, y: Self.drops[i])
                }
            }
            .frame(height: 190)
            VStack(spacing: 2) {
                MonoLabel(text: "Worth today")
                CountingText(value: worth, format: { Format.money($0) })
                    .font(.display(58)).tracking(-2.2).monospacedDigit()
                    .foregroundStyle(Theme.lime)
                    .lineLimit(1).minimumScaleFactor(0.6)
                    .displayTrim(58)
                    .shadow(color: Theme.lime.opacity(0.45), radius: 24)
            }
        }
        .frame(maxWidth: .infinity)
        .background(WelcomeBackdrop())
    }
}

/// The hero's backdrop: a faint grid with a lime and a pink glow, fading out top and bottom.
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

// MARK: - Page 2: the scanner, still

/// A card as the scanner sees it: the lime tracking border around it, a little askew, and the
/// name and price pill above. No camera; nothing moves.
private struct WelcomeScanStill: View {
    private var item: DemoData.Item? { DemoData.items.first { $0.slug == "pikachu-ex-ss" } }

    var body: some View {
        let w: CGFloat = 150
        let h: CGFloat = 210
        ZStack {
            // A dark "viewfinder" with the corner marks of the scanner's guide.
            RoundedRectangle(cornerRadius: 28, style: .continuous)
                .fill(Color.black)
                .overlay(RoundedRectangle(cornerRadius: 28, style: .continuous).strokeBorder(Color.white.opacity(0.08), lineWidth: 1))
                .frame(width: 250, height: 320)
            if let item {
                HoldingArt(product: DemoData.product(item), identity: nil, cornerRadius: 6, caption: false)
                    .frame(width: w, height: h)
                    .rotationEffect(.degrees(-6))
                    .shadow(color: .black.opacity(0.5), radius: 12, y: 10)
            }
            // The tracking border: a quad through the card's corners, drawn the way the scanner does.
            let points = Self.corners(width: w, height: h, tilt: -6, center: CGPoint(x: 125, y: 160))
            CardQuadShape(points: points)
                .stroke(Theme.lime.opacity(0.22), style: StrokeStyle(lineWidth: 11, lineCap: .round, lineJoin: .round))
                .frame(width: 250, height: 320)
            CardQuadShape(points: points)
                .stroke(Theme.lime, style: StrokeStyle(lineWidth: 3, lineCap: .round, lineJoin: .round))
                .frame(width: 250, height: 320)
            // The live read, above the card.
            HStack(spacing: 6) {
                Text("Pikachu ex").font(.geist(13, .semibold)).foregroundStyle(.white)
                Text("#238").font(.mono(11)).foregroundStyle(Theme.muted)
                Text(Format.money(item?.now ?? 0)).font(.geist(13, .bold)).monospacedDigit().foregroundStyle(.white)
            }
            .padding(.horizontal, 12)
            .frame(height: 30)
            .background(Capsule().fill(Color.black.opacity(0.72)))
            .overlay(Capsule().strokeBorder(Color.white.opacity(0.14), lineWidth: 1))
            .offset(y: -138)
        }
        .frame(maxWidth: .infinity)
        .accessibilityElement(children: .ignore)
        .accessibilityLabel("A scanned card with its name and price")
    }

    /// The four corners of a card of this size, tilted, around a centre (in the viewfinder's space).
    private static func corners(width w: CGFloat, height h: CGFloat, tilt: Double, center: CGPoint) -> [CGPoint] {
        let a = tilt * Double.pi / 180
        let c = CGFloat(cos(a)), s = CGFloat(sin(a))
        let pad: CGFloat = 6
        let hw = w / 2 + pad, hh = h / 2 + pad
        return [CGPoint(x: -hw, y: -hh), CGPoint(x: hw, y: -hh), CGPoint(x: hw, y: hh), CGPoint(x: -hw, y: hh)].map { p in
            CGPoint(x: center.x + p.x * c - p.y * s, y: center.y + p.x * s + p.y * c)
        }
    }
}

// MARK: - Page 3: a deal card

/// A small lime deal card, like Deal's balance card: the kind tag, the cash and how far ahead
/// it leaves you.
private struct WelcomeDealCard: View {
    var body: some View {
        VStack(alignment: .leading, spacing: 14) {
            HStack {
                SkewTag(text: "Trade")
                Spacer()
                Text("2 in · 1 out").font(.mono(11)).tracking(0.8).foregroundStyle(Theme.ink.opacity(0.65))
            }
            VStack(alignment: .leading, spacing: 2) {
                Text("Customer pays you".uppercased()).font(.mono(10)).tracking(1).foregroundStyle(Theme.ink.opacity(0.7))
                Text(Format.money(42.5)).font(.display(54)).tracking(-2).monospacedDigit().foregroundStyle(Theme.ink).displayTrim(54)
            }
            HStack(spacing: 18) {
                dealStat("Coming in", Format.money(318.4))
                dealStat("Going out", Format.money(262))
                dealStat("Ahead", Format.signedMoney(18.2))
            }
        }
        .padding(20)
        .frame(width: 300)
        .background(RoundedRectangle(cornerRadius: 24, style: .continuous).fill(Theme.lime))
        .shadow(color: Theme.lime.opacity(0.3), radius: 30, y: 12)
        .frame(maxWidth: .infinity)
        .background(WelcomeBackdrop())
        .accessibilityElement(children: .ignore)
        .accessibilityLabel("A deal card: the customer pays you \(Format.money(42.5)), leaving you \(Format.signedMoney(18.2)) ahead")
    }

    private func dealStat(_ label: String, _ value: String) -> some View {
        VStack(alignment: .leading, spacing: 2) {
            Text(label.uppercased()).font(.mono(9)).tracking(0.8).foregroundStyle(Theme.ink.opacity(0.6))
            Text(value).font(.geist(15, .semibold)).monospacedDigit().foregroundStyle(Theme.ink)
        }
    }
}
