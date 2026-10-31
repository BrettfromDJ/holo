import SwiftUI

/// The website's stock-ticker strip: today's moves across everything you own or watch, biggest
/// first, scrolling by on a loop. Tap a tick to open the card. Still with Reduce Motion on.
struct MarketPulse: View {
    var store: CollectionStore
    @Environment(\.accessibilityReduceMotion) private var reduceMotion
    @State private var onScreen = true
    @State private var rowWidth: CGFloat = 0

    struct Tick: Identifiable {
        var id: String
        var product: Product
        var price: Double
        var change: Double
        var watching: Bool
    }

    private var ticks: [Tick] {
        var out: [String: Tick] = [:]
        for h in store.holdings {
            guard let p = h.product, let price = h.price, let pct = h.change24hPct, !h.identity.isGraded else { continue }
            let key = priceKey(h.identity.productId, h.identity.printing)
            if out[key] == nil { out[key] = Tick(id: key, product: p, price: price, change: pct / 100, watching: false) }
        }
        for w in store.watchlist {
            let key = priceKey(w.product_id, w.printing)
            guard out[key] == nil, let p = store.products[w.product_id], let price = store.prices[key]?.market,
                  let pct = store.prices[key]?.change24hPct else { continue }
            out[key] = Tick(id: key, product: p, price: price, change: pct / 100, watching: true)
        }
        return Array(out.values.filter { abs($0.change) >= 0.0005 }.sorted { abs($0.change) > abs($1.change) }.prefix(24))
    }

    var body: some View {
        let ticks = self.ticks
        if ticks.count >= 3 {
            HStack(spacing: 0) {
                label
                track(ticks)
            }
            .frame(maxWidth: .infinity)
            .frame(height: 42)
            .background(Theme.surface.opacity(0.4))
            .overlay(alignment: .top) { Rectangle().fill(Theme.border).frame(height: 1) }
            .overlay(alignment: .bottom) { Rectangle().fill(Theme.border).frame(height: 1) }
        }
    }

    private var label: some View {
        HStack(spacing: 8) {
            LiveDot()
            HStack(spacing: 4) {
                Image(systemName: "waveform.path.ecg").font(.system(size: 11, weight: .semibold))
                Text("PULSE").font(.mono(11, .medium)).tracking(0.7)
            }
            .foregroundStyle(Theme.muted)
        }
        .padding(.horizontal, 16)
        .fixedSize(horizontal: true, vertical: false)
        .frame(maxHeight: .infinity)
        .background(Theme.background)
        .overlay(alignment: .trailing) { Rectangle().fill(Theme.border).frame(width: 1) }
        .zIndex(1)
    }

    /// Two copies of the row side by side, slid left by one row's width per loop. The offset is
    /// computed from the clock every frame, so thumbnails that load late move with their row.
    private func track(_ ticks: [Tick]) -> some View {
        let seconds = max(30, Double(ticks.count) * 5)
        // The moving row sits in an overlay so its width (two copies of every tick) can never
        // widen the page; the strip itself just takes whatever room is left beside the label.
        return Color.clear
            .frame(maxWidth: .infinity, maxHeight: .infinity)
            .overlay(alignment: .leading) { moving(ticks, seconds: seconds) }
            .clipped()
            .mask(LinearGradient(stops: [.init(color: .clear, location: 0), .init(color: .black, location: 0.04),
                                         .init(color: .black, location: 0.96), .init(color: .clear, location: 1)],
                                 startPoint: .leading, endPoint: .trailing))
    }

    private func moving(_ ticks: [Tick], seconds: Double) -> some View {
        // 30 frames a second is smooth for a slow crawl, and half the work of the screen's full rate.
        TimelineView(.animation(minimumInterval: 1 / 30, paused: reduceMotion || rowWidth == 0 || !onScreen)) { context in
            let t = context.date.timeIntervalSinceReferenceDate
            let shift = reduceMotion || rowWidth == 0 ? 0 : CGFloat(t.truncatingRemainder(dividingBy: seconds) / seconds) * rowWidth
            HStack(spacing: 0) {
                row(ticks)
                    .background(GeometryReader { geo in Color.clear.preference(key: RowWidth.self, value: geo.size.width) })
                row(ticks)
            }
            .fixedSize()
            .offset(x: -shift)
        }
        .onPreferenceChange(RowWidth.self) { rowWidth = $0 }
        // The ticker stops while it's scrolled away or another tab is showing.
        .onVisibilityChange { onScreen = $0 }
    }

    private func row(_ ticks: [Tick]) -> some View {
        HStack(spacing: 0) {
            ForEach(ticks) { tick in
                NavigationLink(value: tick.product.id) {
                    HStack(spacing: 10) {
                        ProductImage(product: tick.product, cornerRadius: 5)
                            .frame(width: 24, height: 24)
                            .background(RoundedRectangle(cornerRadius: 5).fill(Theme.well))
                        Text(shortName(tick.product.name)).font(.geist(13, .medium)).lineLimit(1).foregroundStyle(.white)
                            .frame(maxWidth: 180, alignment: .leading)
                            .fixedSize(horizontal: true, vertical: false)
                        if tick.watching {
                            Text("WATCH").font(.mono(9, .medium)).tracking(0.5).foregroundStyle(Theme.subtle)
                                .padding(.horizontal, 4).background(RoundedRectangle(cornerRadius: 3).fill(Theme.surface2))
                        }
                        Text(Format.money(tick.price)).font(.geist(13)).monospacedDigit().foregroundStyle(Theme.muted)
                        Text("\(tick.change > 0 ? "▲" : "▼") \(String(format: "%.1f%%", abs(tick.change) * 100))")
                            .font(.geist(13, .semibold)).monospacedDigit()
                            .foregroundStyle(tick.change > 0 ? Theme.up : Theme.down)
                    }
                    .padding(.horizontal, 20)
                    .frame(maxHeight: .infinity)
                }
                .buttonStyle(.plain)
            }
        }
        .fixedSize()
    }

    private func shortName(_ name: String) -> String {
        name.replacingOccurrences(of: #"\s*\(.*?\)\s*"#, with: " ", options: .regularExpression)
            .replacingOccurrences(of: #"\s+-\s+\d+/\d+$"#, with: "", options: .regularExpression)
            .trimmingCharacters(in: .whitespaces)
    }
}

private struct RowWidth: PreferenceKey {
    static var defaultValue: CGFloat = 0
    static func reduce(value: inout CGFloat, nextValue: () -> CGFloat) { value = max(value, nextValue()) }
}

/// The green "live" dot with a ring that pings out of it.
private struct LiveDot: View {
    @Environment(\.accessibilityReduceMotion) private var reduceMotion
    @State private var ping = false

    var body: some View {
        ZStack {
            Circle().fill(Theme.up.opacity(0.6))
                .scaleEffect(ping ? 2.2 : 1)
                .opacity(ping ? 0 : 0.6)
            Circle().fill(Theme.up)
        }
        .frame(width: 8, height: 8)
        .onAppear {
            guard !reduceMotion else { return }
            withAnimation(.easeOut(duration: 1).repeatForever(autoreverses: false)) { ping = true }
        }
    }
}
