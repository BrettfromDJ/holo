import SwiftUI

/// "Your week in Holo": story-style slides about the last seven days, like the website's recap.
/// Tap the right two thirds to go on, the left third to go back; hold to pause. Each slide
/// moves on by itself after a few seconds.
struct WeeklyRecap: View {
    var store: CollectionStore
    @Environment(\.dismiss) private var dismiss
    @State private var index = 0
    @State private var paused = false
    @State private var progress: CGFloat = 0

    private static let slideSeconds: Double = 5.5

    private var slides: [Slide] { Slide.build(store) }

    var body: some View {
        let all = slides
        let slide = all[min(index, all.count - 1)]
        ZStack(alignment: .top) {
            slide.background.ignoresSafeArea()
            VStack(alignment: .leading, spacing: 0) {
                // Progress bars, one per slide.
                HStack(spacing: 6) {
                    ForEach(all.indices, id: \.self) { n in
                        GeometryReader { geo in
                            Capsule().fill(.white.opacity(0.25))
                                .overlay(alignment: .leading) {
                                    Capsule().fill(.white)
                                        .frame(width: geo.size.width * (n < index ? 1 : n > index ? 0 : progress))
                                }
                        }
                        .frame(height: 3)
                    }
                }
                HStack {
                    Spacer()
                    Button { dismiss() } label: {
                        Image(systemName: "xmark").font(.system(size: 17, weight: .semibold)).foregroundStyle(.white.opacity(0.8))
                            .frame(width: 40, height: 40)
                    }
                    .accessibilityLabel("Close recap")
                }
                slide.content
                    .id(slide.key)
                    .transition(.asymmetric(insertion: .move(edge: .bottom).combined(with: .opacity), removal: .opacity))
                    .frame(maxHeight: .infinity)
                Text("HOLO").font(.geist(11, .semibold)).tracking(2.2).foregroundStyle(.white.opacity(0.35))
            }
            .padding(.horizontal, 28)
            .padding(.top, 12)
            .padding(.bottom, 20)
        }
        .contentShape(Rectangle())
        .gesture(
            DragGesture(minimumDistance: 0)
                .onChanged { _ in paused = true }
                .onEnded { value in
                    paused = false
                    // A tap (not a hold-and-drag) moves between slides.
                    guard abs(value.translation.width) < 12, abs(value.translation.height) < 12 else {
                        if value.translation.height > 120 { dismiss() }
                        return
                    }
                    let width = UIScreen.main.bounds.width
                    if value.location.x < width * 0.33 { go(index - 1, of: all.count) } else { go(index + 1, of: all.count) }
                }
        )
        .task(id: index) {
            // Fill this slide's bar, then move on (the last slide waits).
            progress = 0
            let steps = 110
            for _ in 0 ..< steps {
                try? await Task.sleep(for: .seconds(Self.slideSeconds / Double(steps)))
                if Task.isCancelled { return }
                if !paused { progress += 1 / CGFloat(steps) }
                if progress >= 1 { break }
            }
            if index < slides.count - 1 { go(index + 1, of: slides.count) }
        }
        .statusBarHidden()
    }

    private func go(_ n: Int, of count: Int) {
        guard n >= 0, n < count else { return }
        withAnimation(.spring(response: 0.45, dampingFraction: 0.85)) { index = n }
    }
}

private struct Slide {
    var key: String
    var background: RadialGradient
    var content: AnyView

    private static func glow(_ hex: UInt32, _ mid: UInt32, at: UnitPoint) -> RadialGradient {
        RadialGradient(colors: [Color(hex: hex), Color(hex: mid), Color(hex: 0x0B0B0C)], center: at, startRadius: 0, endRadius: 620)
    }

    static func build(_ store: CollectionStore) -> [Slide] {
        let today = Date()
        let from = Format.day(Calendar.current.date(byAdding: .day, value: -7, to: today) ?? today)
        let week = store.timeline.filter { $0.date >= from }
        // Market moves alone: the change in value less what new buys added at cost.
        let gain: Double = {
            guard let a = week.first, let b = week.last else { return 0 }
            return (b.value - a.value) - (b.cost - a.cost)
        }()
        let ratio: Double? = week.first.map { $0.value > 0 ? gain / $0.value : nil } ?? nil
        let moved = store.holdings.filter { $0.change7dPct != nil && $0.product != nil }
        let gainer = moved.max { ($0.change7dPct ?? 0) < ($1.change7dPct ?? 0) }
        let loser = moved.min { ($0.change7dPct ?? 0) < ($1.change7dPct ?? 0) }
        let buys = Ledger.effective(store.transactions).filter { $0.kind == .purchase && $0.date > from && $0.date <= Format.day(today) }
        let spent = buys.reduce(0) { $0 + $1.acquisitionCost }
        let units = buys.reduce(0) { $0 + $1.quantity }
        let best = store.holdings.filter { $0.gainRatio != nil && $0.product != nil }.max { ($0.gainRatio ?? 0) < ($1.gainRatio ?? 0) }
        let s = store.summary

        var slides: [Slide] = []
        let range = "\(shortDate(Calendar.current.date(byAdding: .day, value: -6, to: today) ?? today)) – \(shortDate(today))"
        slides.append(Slide(key: "intro", background: glow(0x5B3DF5, 0x1B1240, at: UnitPoint(x: 0.2, y: 0)), content: AnyView(
            VStack(alignment: .leading, spacing: 0) {
                Kicker(text: "Your week in Holo")
                Text(range).font(.geist(14)).foregroundStyle(.white.opacity(0.7)).padding(.top, 8)
                Spacer()
                Text("Your collection \(gain >= 0 ? "grew" : "slipped")").font(.geist(18, .medium)).foregroundStyle(.white.opacity(0.8))
                Big(text: Format.signedMoney(gain), color: gain >= 0 ? Color(hex: 0xE4FF7A) : Color(hex: 0xFF8AB3))
                Text("\(Format.signedPercent(ratio)) from market moves alone · now \(Format.money(s.value))")
                    .font(.geist(15)).monospacedDigit().foregroundStyle(.white.opacity(0.7)).padding(.top, 8)
            }
        )))
        if let gainer, (gainer.change7dPct ?? 0) > 0 {
            slides.append(Slide(key: "gainer", background: glow(0x8FAE00, 0x2A3600, at: UnitPoint(x: 0.8, y: 0)), content: AnyView(
                HeroSlide(kicker: "Hottest this week", holding: gainer) {
                    Big(text: Format.signedPercent((gainer.change7dPct ?? 0) / 100), color: Color(hex: 0xE4FF7A))
                    Text("Now \(Format.money(gainer.price)) each").font(.geist(14)).monospacedDigit().foregroundStyle(.white.opacity(0.7)).padding(.top, 4)
                }
            )))
        }
        if let loser, (loser.change7dPct ?? 0) < 0 {
            slides.append(Slide(key: "loser", background: glow(0xE0306F, 0x3D0A1F, at: UnitPoint(x: 0.2, y: 0)), content: AnyView(
                HeroSlide(kicker: "Cooled off", holding: loser) {
                    Big(text: Format.signedPercent((loser.change7dPct ?? 0) / 100), color: Color(hex: 0xFF8AB3))
                    Text("Now \(Format.money(loser.price)) each. Buying opportunity?").font(.geist(14)).monospacedDigit().foregroundStyle(.white.opacity(0.7)).padding(.top, 4)
                }
            )))
        }
        slides.append(Slide(key: "spent", background: glow(0xF59E0B, 0x3D2606, at: UnitPoint(x: 0.5, y: 0)), content: AnyView(
            VStack(alignment: .leading, spacing: 0) {
                Kicker(text: "Shopping")
                Spacer()
                if spent > 0 {
                    Text("You picked up").font(.geist(18, .medium)).foregroundStyle(.white.opacity(0.8))
                    Big(text: "\(Int(units)) item\(units == 1 ? "" : "s")", color: .white)
                    Text("\(Format.money(spent)) spent, fees included").font(.geist(15)).monospacedDigit().foregroundStyle(.white.opacity(0.7)).padding(.top, 8)
                    HStack(spacing: -12) {
                        ForEach(Array(buys.prefix(5)), id: \.id) { t in
                            ProductImage(product: store.products[t.identity.productId], cornerRadius: 14)
                                .frame(width: 56, height: 56)
                                .background(RoundedRectangle(cornerRadius: 14).fill(Color(hex: 0x18181A)))
                                .overlay(RoundedRectangle(cornerRadius: 14).strokeBorder(Color(hex: 0x3D2606), lineWidth: 2))
                        }
                    }
                    .padding(.top, 24)
                } else {
                    Big(text: "$0 spent", color: .white)
                    Text("No new buys this week.").font(.geist(18)).foregroundStyle(.white.opacity(0.8)).padding(.top, 12)
                }
            }
        )))
        if let best, (best.gainRatio ?? 0) > 0 {
            slides.append(Slide(key: "best", background: glow(0xEC4899, 0x3D0D26, at: UnitPoint(x: 0.5, y: 0)), content: AnyView(
                HeroSlide(kicker: "Best buy you've ever made", holding: best) {
                    Big(text: Format.signedPercent(best.gainRatio), color: Color(hex: 0xFFB3D9))
                    Text("Paid \(Format.money(best.costBasis)) · worth \(Format.money(best.value))").font(.geist(14)).monospacedDigit().foregroundStyle(.white.opacity(0.7)).padding(.top, 4)
                }
            )))
        }
        slides.append(Slide(key: "outro", background: glow(0x3B82F6, 0x0C1D3D, at: UnitPoint(x: 0.5, y: 1)), content: AnyView(
            VStack(alignment: .leading, spacing: 0) {
                Kicker(text: "That's a wrap")
                Spacer()
                Text("Your collection is worth").font(.geist(18, .medium)).foregroundStyle(.white.opacity(0.8))
                Big(text: Format.money(s.value), color: .white)
                Text("\(Int(s.items)) items · \(Format.signedMoney(s.gain)) (\(Format.signedPercent(s.gainRatio))) all time")
                    .font(.geist(15)).monospacedDigit().foregroundStyle(.white.opacity(0.7)).padding(.top, 8)
                Spacer()
                Text("See you next week.").font(.geist(13)).foregroundStyle(.white.opacity(0.5))
            }
        )))
        return slides
    }

    private static func shortDate(_ d: Date) -> String { d.formatted(.dateTime.month(.abbreviated).day()) }
}

private struct Kicker: View {
    var text: String
    var body: some View {
        Text(text.uppercased()).font(.mono(12, .medium)).tracking(0.7).foregroundStyle(.white.opacity(0.6))
    }
}

private struct Big: View {
    var text: String
    var color: Color
    var body: some View {
        Text(text).font(.geist(46, .semibold)).tracking(-1.8).monospacedDigit().foregroundStyle(color)
            .lineLimit(1).minimumScaleFactor(0.5).padding(.top, 12)
    }
}

/// A slide about one product: kicker, the piece, then its name and numbers.
private struct HeroSlide<Numbers: View>: View {
    var kicker: String
    var holding: HoldingView
    @ViewBuilder var numbers: Numbers

    var body: some View {
        VStack(alignment: .leading, spacing: 0) {
            Kicker(text: kicker)
            HoldingArt(product: holding.product, identity: holding.identity, cornerRadius: 16)
                .frame(maxWidth: 240, maxHeight: 300)
                .shadow(color: .black.opacity(0.5), radius: 24, y: 14)
                .frame(maxWidth: .infinity, maxHeight: .infinity)
                .padding(.vertical, 24)
            Text(shortName(holding.product?.name ?? "")).font(.geist(20, .semibold)).foregroundStyle(.white).lineLimit(2)
            numbers
        }
    }

    private func shortName(_ name: String) -> String {
        name.replacingOccurrences(of: #"\s*\(.*?\)\s*"#, with: " ", options: .regularExpression)
            .replacingOccurrences(of: #"\s+-\s+\d+/\d+$"#, with: "", options: .regularExpression)
            .trimmingCharacters(in: .whitespaces)
    }
}
