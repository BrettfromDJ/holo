import SwiftUI

// Dexora Pro (test mode): what Free includes and what Pro unlocks, the Pro page, and the locks
// shown where a Free account reaches a Pro feature. Nothing is charged yet: "Start free trial"
// turns Pro on for this phone only, so the plan and the prompts can be tried. Real purchases
// (Apple in the app, Stripe on the website, one Pro for both) come later and will replace
// `isPro` with the account's own entitlement.

/// The plan on this phone and Free's limits.
@Observable
final class Pro {
    static let shared = Pro()

    // Free's limits (Pro has none).
    static let freeScansPerMonth = 20
    static let freeHistoryDays = 30
    static let freeShelves = 2
    static let freeMasterSets = 2
    static let freeAlerts = 3

    // The prices shown (test mode: nothing is charged).
    static let monthly = 4.99
    static let yearly = 39.99
    static let trialDays = 7

    /// Pro is on (test mode, this phone only). Demos and screenshots count as Pro, so every
    /// screen shows in full.
    var isPro: Bool {
        didSet { UserDefaults.standard.set(isPro, forKey: "pro-test") }
    }

    /// Scans this calendar month, kept on the phone ("pro-scans:2026-11").
    private(set) var scansThisMonth: Int

    private init() {
        isPro = UserDefaults.standard.bool(forKey: "pro-test")
        scansThisMonth = UserDefaults.standard.integer(forKey: Self.scanKey())
    }

    private static func scanKey(_ date: Date = Date()) -> String {
        let c = Calendar.current.dateComponents([.year, .month], from: date)
        return String(format: "pro-scans:%04d-%02d", c.year ?? 0, c.month ?? 0)
    }

    /// Pro, or a demo (everything shows in a demo).
    var unlocked: Bool { isPro || Demo.isOn || DemoKind.selected != nil }

    var scansLeft: Int { max(0, Self.freeScansPerMonth - scansThisMonth) }
    var canScan: Bool { unlocked || scansLeft > 0 }

    func countScan() {
        guard !unlocked else { return }
        let key = Self.scanKey()
        scansThisMonth = UserDefaults.standard.integer(forKey: key) + 1
        UserDefaults.standard.set(scansThisMonth, forKey: key)
    }
}

/// Why the Pro page opened: its headline speaks to what you just tried.
enum ProReason: String, Identifiable {
    case general, scans, history, ebay, portfolios, shelves, grading, analytics, masterSets, alerts
    var id: String { rawValue }

    var headline: String {
        switch self {
        case .general: return "Everything, unlocked"
        case .scans: return "You've used this month's \(Pro.freeScansPerMonth) free scans"
        case .history: return "See the whole price history"
        case .ebay: return "See what it really sells for"
        case .portfolios: return "Split your collection into portfolios"
        case .shelves: return "Make as many lists as you like"
        case .grading: return "Know what to grade"
        case .analytics: return "See every gain and loss"
        case .masterSets: return "Chase every set"
        case .alerts: return "Watch as many cards as you like"
        }
    }
}

/// What Pro adds, in the order the Pro page lists it.
private let proFeatures: [(icon: String, title: String, line: String)] = [
    ("viewfinder", "Unlimited scans", "Scan a whole show haul at once, with no monthly limit."),
    ("chart.xyaxis.line", "Full price history", "Years of prices on every card, not just the last 30 days."),
    ("tag", "eBay sold comps", "Recent sales, the median and the range, raw and by grade."),
    ("checkmark.seal", "Grading tools", "Grade-or-not maths, submissions, costs and return."),
    ("chart.pie", "Full analytics", "Gains with cost basis, realised and unrealised, tax export."),
    ("square.stack.3d.up", "Unlimited portfolios and lists", "Resale, PC, graded: split it any way you like."),
    ("bell.badge", "Unlimited, instant price alerts", "Know the moment a card hits your price."),
    ("square.grid.3x3.fill", "Every master set", "Track them all, with the cost to finish each."),
]

/// The Pro page: what you get, the two plans, and the free trial. Test mode: starting the trial
/// turns Pro on for this phone.
struct ProSheet: View {
    var reason: ProReason = .general
    @Environment(\.dismiss) private var dismiss
    @State private var yearly = true
    @State private var pro = Pro.shared

    var body: some View {
        ZStack(alignment: .top) {
            // The lit grid and glows behind the hero: across the whole sheet, fading out on every
            // side (it sat inside the scroll before and was cut off at the top and sides).
            ZStack {
                GridPattern(step: 28, opacity: 0.06)
                RadialGradient(colors: [Theme.lime.opacity(0.32), .clear], center: UnitPoint(x: 0.5, y: 0.42), startRadius: 0, endRadius: 240)
                RadialGradient(colors: [Theme.planBlue.opacity(0.22), .clear], center: UnitPoint(x: 0.08, y: 0.12), startRadius: 0, endRadius: 220)
            }
            .frame(height: 560)
            .mask(LinearGradient(stops: [.init(color: .clear, location: 0), .init(color: .black, location: 0.12),
                                         .init(color: .black, location: 0.55), .init(color: .clear, location: 1)],
                                 startPoint: .top, endPoint: .bottom))
            .allowsHitTesting(false)
            // Full screen: the glow runs up under the status bar.
            .ignoresSafeArea(edges: .top)
            // Lime sparks rising behind the top.
            MoteParticles(style: .sparks, color: Theme.lime, count: 26)
                .frame(height: 320)
                .mask(LinearGradient(colors: [.black, .clear], startPoint: .top, endPoint: .bottom))
                .ignoresSafeArea(edges: .top)
            ScrollView {
                VStack(alignment: .leading, spacing: 22) {
                    HStack {
                        SkewTag(text: "Dexora Pro", icon: "sparkles")
                        Spacer()
                        Button { dismiss() } label: {
                            Image(systemName: "xmark").font(.system(size: 14, weight: .bold)).foregroundStyle(.white)
                                .frame(width: 36, height: 36).background(Circle().fill(Color.white.opacity(0.1)))
                        }
                        .buttonStyle(.plain)
                        .accessibilityLabel("Close")
                    }
                    ProHero(reason: reason)
                    VStack(alignment: .leading, spacing: 16) {
                        ForEach(proFeatures, id: \.title) { f in
                            HStack(alignment: .top, spacing: 12) {
                                Image(systemName: f.icon).font(.system(size: 15, weight: .semibold)).foregroundStyle(Theme.ink)
                                    .frame(width: 34, height: 34).background(Circle().fill(Theme.lime))
                                VStack(alignment: .leading, spacing: 2) {
                                    Text(f.title).font(.geist(15, .semibold)).foregroundStyle(.white)
                                    Text(f.line).font(.geist(13)).foregroundStyle(Theme.muted)
                                        .fixedSize(horizontal: false, vertical: true)
                                }
                            }
                        }
                    }
                    VStack(spacing: 10) {
                        plan(yearly: true, title: "Yearly", price: Format.money(Pro.yearly) + " a year",
                             note: "\(Format.money(Pro.yearly / 12)) a month", tag: "Save 33%")
                        plan(yearly: false, title: "Monthly", price: Format.money(Pro.monthly) + " a month", note: "Cancel any time", tag: nil)
                    }
                    Text("Free stays free: your whole collection, prices, Home and Explore, \(Pro.freeScansPerMonth) scans a month, \(Pro.freeHistoryDays) days of price history, \(Pro.freeShelves) lists, \(Pro.freeAlerts) price alerts and \(Pro.freeMasterSets) master sets.".noWidow)
                        .font(.geist(12)).foregroundStyle(Theme.subtle)
                        .fixedSize(horizontal: false, vertical: true)
                }
                .padding(20)
                .padding(.bottom, 140)
            }
        }
        .safeAreaInset(edge: .bottom) {
            VStack(spacing: 8) {
                Button {
                    // Test mode: no charge; Pro turns on for this phone.
                    Haptics.tap()
                    pro.isPro = true
                    dismiss()
                } label: {
                    Label("Start \(Pro.trialDays)-day free trial", systemImage: "sparkles")
                }
                .buttonStyle(LimeButtonStyle())
                .proShine(RoundedRectangle(cornerRadius: 14, style: .continuous))
                Text("Then \(yearly ? Format.money(Pro.yearly) + " a year" : Format.money(Pro.monthly) + " a month"). Test mode: nothing is charged.")
                    .font(.geist(12)).foregroundStyle(Theme.subtle)
            }
            .padding(.horizontal, 20).padding(.top, 12).padding(.bottom, 8)
            .background(Color.black)
        }
        .background(Color.black)
        .presentationBackground(Color.black)
    }

    private func plan(yearly isYearly: Bool, title: String, price: String, note: String, tag: String?) -> some View {
        let on = yearly == isYearly
        return Button {
            Haptics.tap()
            withAnimation(.snappy(duration: 0.2)) { yearly = isYearly }
        } label: {
            HStack(spacing: 12) {
                Image(systemName: on ? "checkmark.circle.fill" : "circle").font(.system(size: 20))
                    .foregroundStyle(on ? Theme.lime : Color.white.opacity(0.25))
                VStack(alignment: .leading, spacing: 2) {
                    HStack(spacing: 8) {
                        Text(title).font(.geist(16, .semibold)).foregroundStyle(.white)
                        if let tag { SkewTag(text: tag) }
                    }
                    Text(note).font(.geist(13)).foregroundStyle(Theme.muted)
                }
                Spacer()
                Text(price).font(.geist(15, .semibold)).foregroundStyle(.white).monospacedDigit()
            }
            .padding(16)
            // Glass: blurs what's behind (the sparks and glow), with a lime wash when chosen.
            .background(RoundedRectangle(cornerRadius: 18, style: .continuous).fill(on ? Theme.lime.opacity(0.08) : Color.clear))
            .liquidGlass(in: RoundedRectangle(cornerRadius: 18, style: .continuous))
            .overlay(RoundedRectangle(cornerRadius: 18, style: .continuous).strokeBorder(on ? Theme.lime : Color.white.opacity(0.08), lineWidth: on ? 1.5 : 1))
            .contentShape(RoundedRectangle(cornerRadius: 18))
        }
        .buttonStyle(.plain)
    }
}

extension View {
    /// Shows the Pro page whenever `reason` is set.
    func proPaywall(_ reason: Binding<ProReason?>) -> some View {
        // A full-screen takeover, closed with the X at the top right.
        fullScreenCover(item: reason) { ProSheet(reason: $0) }
    }
}

/// A whole page that's Pro (Grading, Analytics) on a Free account: what it does, and the way in.
struct ProLockedPage: View {
    var reason: ProReason
    var title: String
    var line: String
    var icon: String
    @State private var paywall: ProReason?
    @State private var pro = Pro.shared

    var body: some View {
        Group {
            if pro.unlocked {
                EmptyView()
            } else {
                VStack(spacing: 16) {
                    Spacer()
                    Image(systemName: icon).font(.system(size: 28, weight: .semibold)).foregroundStyle(Theme.ink)
                        .frame(width: 64, height: 64).background(Circle().fill(Theme.lime))
                        .background { MoteParticles(style: .sparks, color: Theme.lime, count: 14).frame(width: 200, height: 200) }
                    Text(title).font(.display(28)).tracking(-0.7)
                    BalancedText(text: line, font: .geist(15), color: Theme.muted, alignment: .center)
                        .padding(.horizontal, 32)
                    Button { paywall = reason } label: { Label("See Dexora Pro", systemImage: "sparkles") }
                        .buttonStyle(Button3D(kind: .lime, fullWidth: false))
                        .proShine(RoundedRectangle(cornerRadius: 14, style: .continuous))
                        .padding(.top, 6)
                    Spacer()
                }
                .frame(maxWidth: .infinity)
                .background(Theme.background)
            }
        }
        .proPaywall($paywall)
    }
}

/// Wraps a Pro page: the page itself with Pro, else its locked page.
struct ProOnly<Content: View>: View {
    var reason: ProReason
    var title: String
    var line: String
    var icon: String
    @ViewBuilder var content: Content
    @State private var pro = Pro.shared

    var body: some View {
        if pro.unlocked { content } else { ProLockedPage(reason: reason, title: title, line: line, icon: icon) }
    }
}

/// The eBay sales panel on a Free account: made-up rows blurred behind a lock, and the way in.
struct EbayLockedPanel: View {
    @State private var paywall: ProReason?

    var body: some View {
        VStack(alignment: .leading, spacing: 12) {
            HStack {
                MonoLabel(text: "Recent eBay sales")
                Spacer()
                Image(systemName: "lock.fill").font(.system(size: 12, weight: .semibold)).foregroundStyle(Theme.lime)
            }
            ZStack {
                VStack(spacing: 10) {
                    ForEach(0 ..< 4, id: \.self) { i in
                        HStack {
                            RoundedRectangle(cornerRadius: 3).fill(Color.white.opacity(0.2)).frame(width: 70, height: 10)
                            Spacer()
                            Text(["$142.50", "$138.00", "$151.25", "$129.99"][i]).font(.geist(14, .semibold)).monospacedDigit()
                        }
                    }
                }
                .blur(radius: 6)
                .accessibilityHidden(true)
                Button { paywall = .ebay } label: {
                    HStack(spacing: 6) {
                        Image(systemName: "sparkles").font(.system(size: 12, weight: .bold))
                        Text("See with Pro").font(.geist(14, .semibold))
                    }
                    .foregroundStyle(Theme.ink)
                    .padding(.horizontal, 16).frame(height: 38)
                    .background(Capsule().fill(Theme.lime))
                    .proShine(Capsule())
                }
                .buttonStyle(.plain)
            }
        }
        .padding(16)
        .background(Theme.surface, in: RoundedRectangle(cornerRadius: 20, style: .continuous))
        .overlay(RoundedRectangle(cornerRadius: 20, style: .continuous).strokeBorder(Theme.border))
        .proPaywall($paywall)
    }
}

/// Account's Pro card: Go Pro on Free; on Pro, that it's on (test mode) and a way to turn it off.
struct ProAccountCard: View {
    @State private var pro = Pro.shared
    @State private var paywall: ProReason?

    var body: some View {
        VStack(alignment: .leading, spacing: 10) {
            HStack(spacing: 8) {
                SkewTag(text: pro.isPro ? "Pro" : "Free", icon: pro.isPro ? "sparkles" : nil)
                Spacer()
                if !pro.isPro {
                    Text("\(pro.scansLeft) of \(Pro.freeScansPerMonth) scans left").font(.geist(12)).foregroundStyle(Theme.muted).monospacedDigit()
                }
            }
            Text(pro.isPro ? "Dexora Pro is on" : "Go Pro").font(.display(24)).tracking(-0.6)
            Text(pro.isPro ? "Test mode: on this phone only, nothing charged." : "Unlimited scans, full price history, eBay comps, grading and analytics.")
                .font(.geist(14)).foregroundStyle(Theme.muted)
                .fixedSize(horizontal: false, vertical: true)
            if pro.isPro {
                Button("Turn Pro off (test)") { pro.isPro = false }
                    .font(.geist(14, .semibold)).foregroundStyle(Theme.lime)
            } else {
                Button { paywall = .general } label: { Label("See Dexora Pro", systemImage: "sparkles") }
                    .buttonStyle(Button3D(kind: .lime))
                    .proShine(RoundedRectangle(cornerRadius: 14, style: .continuous))
            }
        }
        .proPaywall($paywall)
    }
}


// MARK: The Pro buttons' shine

extension View {
    /// Pro's buttons: a crisp bright edge and a sharp double glint sweeping across every few
    /// seconds (only while on screen; still with Reduce Motion). Lime only, no rainbow foil.
    func proShine<S: Shape>(_ shape: S) -> some View {
        modifier(ProShine(shape: shape))
    }
}

private struct ProShine<S: Shape>: ViewModifier {
    var shape: S

    func body(content: Content) -> some View {
        content
            .overlay { ProGlint().clipShape(shape).allowsHitTesting(false) }
            // A sharp, bright rim: white at the top left fading to the lime's deep edge.
            .overlay {
                shape.stroke(LinearGradient(colors: [.white.opacity(0.95), .white.opacity(0.15), Theme.limeEdge.opacity(0.7)],
                                            startPoint: .topLeading, endPoint: .bottomTrailing), lineWidth: 1.5)
                    .allowsHitTesting(false)
            }
    }
}

/// Two bands of light, a soft wide one with a sharp thin one riding it, sliding across at an
/// angle. One looping offset animation, set once: nothing is laid out per frame, and it rests
/// off the button for most of each loop.
private struct ProGlint: View {
    @Environment(\.accessibilityReduceMotion) private var reduceMotion
    @State private var across = false

    var body: some View {
        if !reduceMotion {
            HStack(spacing: 6) {
                LinearGradient(colors: [.clear, .white.opacity(0.55), .clear], startPoint: .leading, endPoint: .trailing).frame(width: 34)
                LinearGradient(colors: [.clear, .white.opacity(0.95), .clear], startPoint: .leading, endPoint: .trailing).frame(width: 8)
            }
            .scaleEffect(x: 1, y: 3)
            .rotationEffect(.degrees(22))
            .frame(maxWidth: .infinity, maxHeight: .infinity)
            .offset(x: across ? 420 : -420)
            .blendMode(.plusLighter)
            .onVisibilityChange { on in
                if on {
                    withAnimation(.easeInOut(duration: 2.8).repeatForever(autoreverses: false)) { across = true }
                } else {
                    stopLoop { across = false }
                }
            }
        }
    }
}


// MARK: The Pro page's hero

/// The top of the Pro page: your three most valuable cards fanned on a lime glow over the grid
/// (the market's top risers if you have none), a glint sweeping the front one, then "Dexora Pro"
/// big, the reason's headline and three quick highlights.
private struct ProHero: View {
    var reason: ProReason
    @Environment(CollectionStore.self) private var store

    /// Pictures for the fan: your priciest singles, else the week's top risers.
    private var cards: [Product] {
        let mine = store.allHoldings
            .filter { $0.product?.isSealed == false }
            .sorted { ($0.value ?? 0) > ($1.value ?? 0) }
            .compactMap(\.product)
        if mine.count >= 3 { return Array(mine.prefix(3)) }
        let market = (SavedExplore.preloaded ?? DemoData.exploreIndex).trending ?? []
        return Array((mine + market.map(\.pictured)).prefix(3))
    }

    var body: some View {
        VStack(alignment: .leading, spacing: 18) {
            fan
                .frame(maxWidth: .infinity)
                .frame(height: 210)
            VStack(alignment: .leading, spacing: 10) {
                HStack(alignment: .firstTextBaseline, spacing: 10) {
                    Text("Dexora").font(.display(44)).tracking(-1.6).foregroundStyle(.white)
                    SkewTag(text: "Pro", icon: "sparkles")
                }
                DisplayText(text: reason.headline, size: 24, lineGap: -0.04)
                Text("Every tool in Dexora, in the app and on the\u{00A0}website.")
                    .font(.geist(15)).foregroundStyle(Theme.muted)
                    .fixedSize(horizontal: false, vertical: true)
            }
            // Three quick wins, as glass pills.
            ViewThatFits(in: .horizontal) {
                HStack(spacing: 8) { highlights }
                VStack(alignment: .leading, spacing: 8) { highlights }
            }
        }
    }

    @ViewBuilder private var highlights: some View {
        pill("infinity", "Unlimited scans")
        pill("dollarsign.circle", "eBay sold prices")
        pill("chart.xyaxis.line", "Full history")
    }

    private func pill(_ icon: String, _ text: String) -> some View {
        HStack(spacing: 6) {
            Image(systemName: icon).font(.system(size: 11, weight: .bold)).foregroundStyle(Theme.lime)
            Text(text).font(.geist(12, .semibold)).foregroundStyle(.white).lineLimit(1)
        }
        .padding(.horizontal, 10).padding(.vertical, 7)
        .liquidGlass(in: Capsule())
        .fixedSize()
    }

    /// Three cards fanned from the bottom, each with a bright rim and a sweeping glint.
    private var fan: some View {
        let shown = cards
        return ZStack {
            ForEach(Array(shown.enumerated()), id: \.offset) { i, product in
                let d = Double(i) - 1
                ProductImage(product: product, cornerRadius: 8)
                    .frame(width: 118, height: 165)
                    // Foil light: a soft gloss, a bright rim and a wide band of light sweeping across,
                    // each card a beat after the one before.
                    .modifier(CardShine(delay: Double(i) * 0.35))
                    .shadow(color: .black.opacity(0.5), radius: 14, y: 10)
                    .rotationEffect(.degrees(d * 12), anchor: .bottom)
                    .offset(x: d * 70, y: abs(d) * 14)
                    .zIndex(i == 1 ? 1 : 0)
            }
        }
    }
}


/// Light over a card on the Pro page: a still gloss from the top-left, a bright rim, and a wide
/// soft band with a sharp core sliding across every few seconds (one offset animation, only while
/// on screen; still with Reduce Motion).
private struct CardShine: ViewModifier {
    var delay: Double
    @Environment(\.accessibilityReduceMotion) private var reduceMotion
    @State private var across = false

    func body(content: Content) -> some View {
        let shape = RoundedRectangle(cornerRadius: 8, style: .continuous)
        content
            .overlay {
                // The gloss: brighter at the top-left corner, a touch at the bottom-right.
                LinearGradient(stops: [.init(color: .white.opacity(0.22), location: 0), .init(color: .clear, location: 0.35),
                                       .init(color: .clear, location: 0.8), .init(color: .white.opacity(0.08), location: 1)],
                               startPoint: .topLeading, endPoint: .bottomTrailing)
                    .blendMode(.plusLighter)
                    .clipShape(shape)
                    .allowsHitTesting(false)
            }
            .overlay {
                if !reduceMotion {
                    ZStack {
                        LinearGradient(colors: [.clear, .white.opacity(0.35), .clear], startPoint: .leading, endPoint: .trailing).frame(width: 90)
                        LinearGradient(colors: [.clear, .white.opacity(0.85), .clear], startPoint: .leading, endPoint: .trailing).frame(width: 10)
                    }
                    .scaleEffect(x: 1, y: 2.4)
                    .rotationEffect(.degrees(24))
                    .offset(x: across ? 220 : -220)
                    .blendMode(.plusLighter)
                    .clipShape(shape)
                    .allowsHitTesting(false)
                    .onVisibilityChange { on in
                        if on {
                            withAnimation(.easeInOut(duration: 2.2).delay(delay).repeatForever(autoreverses: false)) { across = true }
                        } else {
                            stopLoop { across = false }
                        }
                    }
                }
            }
            .overlay(shape.stroke(LinearGradient(colors: [.white.opacity(0.8), .white.opacity(0.1), Theme.lime.opacity(0.5)],
                                                 startPoint: .topLeading, endPoint: .bottomTrailing), lineWidth: 1).allowsHitTesting(false))
    }
}
