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
            // Lime sparks rising behind the top.
            MoteParticles(style: .sparks, color: Theme.lime, count: 26)
                .frame(height: 320)
                .mask(LinearGradient(colors: [.black, .clear], startPoint: .top, endPoint: .bottom))
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
                    VStack(alignment: .leading, spacing: 8) {
                        DisplayText(text: reason.headline, size: 32, lineGap: -0.04)
                        Text("Pro unlocks every tool in Dexora, in the app and on the website.")
                            .font(.geist(15)).foregroundStyle(Theme.muted)
                            .fixedSize(horizontal: false, vertical: true)
                    }
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
                    Text("Free stays free: your whole collection, prices, Home and Explore, \(Pro.freeScansPerMonth) scans a month, \(Pro.freeHistoryDays) days of price history, \(Pro.freeShelves) lists, \(Pro.freeAlerts) price alerts and \(Pro.freeMasterSets) master sets.")
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
                    Text("Start \(Pro.trialDays)-day free trial")
                }
                .buttonStyle(LimeButtonStyle())
                Text("Then \(yearly ? Format.money(Pro.yearly) + " a year" : Format.money(Pro.monthly) + " a month"). Test mode: nothing is charged.")
                    .font(.geist(12)).foregroundStyle(Theme.subtle)
            }
            .padding(.horizontal, 20).padding(.top, 12).padding(.bottom, 8)
            .background(Color.black)
        }
        .background(Color.black)
        .presentationDetents([.fraction(0.93)])
        .presentationBackground(Color.black)
        .presentationDragIndicator(.visible)
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
            .background(RoundedRectangle(cornerRadius: 18, style: .continuous).fill(on ? Theme.lime.opacity(0.08) : Color.white.opacity(0.06)))
            .overlay(RoundedRectangle(cornerRadius: 18, style: .continuous).strokeBorder(on ? Theme.lime : Color.white.opacity(0.08), lineWidth: on ? 1.5 : 1))
            .contentShape(RoundedRectangle(cornerRadius: 18))
        }
        .buttonStyle(.plain)
    }
}

extension View {
    /// Shows the Pro page whenever `reason` is set.
    func proPaywall(_ reason: Binding<ProReason?>) -> some View {
        sheet(item: reason) { ProSheet(reason: $0) }
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
                    Button("See Dexora Pro") { paywall = reason }
                        .buttonStyle(Button3D(kind: .lime, fullWidth: false))
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
                Button("See Dexora Pro") { paywall = .general }
                    .buttonStyle(Button3D(kind: .lime))
            }
        }
        .proPaywall($paywall)
    }
}
