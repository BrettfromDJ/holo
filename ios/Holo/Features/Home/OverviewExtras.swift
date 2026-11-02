import SwiftUI

// MARK: - Pinned worth bar

/// The hero's worth, compact, pinned to the top of Overview once the hero's figures scroll away:
/// your collection's worth on the left, today's change on the right, in one Liquid Glass strip.
struct PinnedWorth: View {
    var value: Double
    var dayChange: Double
    var dayRatio: Double?

    var body: some View {
        let tint = Theme.tone(dayChange)
        HStack(alignment: .center, spacing: 12) {
            VStack(alignment: .leading, spacing: 2) {
                MonoLabel(text: "Your collection")
                Text(Format.money(value))
                    .font(.display(22)).tracking(-0.6)
                    .monospacedDigit()
                    .foregroundStyle(.white)
                    .displayTrim(22)
            }
            Spacer(minLength: 8)
            VStack(alignment: .trailing, spacing: 2) {
                MonoLabel(text: "Today")
                HStack(alignment: .firstTextBaseline, spacing: 4) {
                    Text(Format.signedMoney(dayChange)).font(.geist(15, .semibold))
                    if let dayRatio {
                        Text(Format.signedPercent(dayRatio)).font(.geist(11, .medium)).opacity(0.8)
                    }
                }
                .foregroundStyle(tint)
                .monospacedDigit()
            }
        }
        .lineLimit(1).minimumScaleFactor(0.7)
        .padding(.horizontal, 16).padding(.vertical, 10)
        .liquidGlass(in: RoundedRectangle(cornerRadius: 20, style: .continuous))
        .shadow(color: .black.opacity(0.35), radius: 14, y: 8)
        .contentShape(RoundedRectangle(cornerRadius: 20, style: .continuous))
        .accessibilityElement(children: .combine)
    }
}

// MARK: - Alerts strip

/// Something on Overview that needs you: a watched card at or below your target, or cards out
/// at the grader. Read from what the stores already hold (no network).
struct HomeAlert: Identifiable, Hashable {
    enum Target: Hashable {
        case product(String)
        case grading
    }

    var id: String
    var text: String
    /// Good news (a target hit) gets a lime dot; plain information doesn't.
    var good: Bool
    var target: Target

    /// At most three, targets hit first.
    static func collect(store: CollectionStore, grading: GradingStore) -> [HomeAlert] {
        var out: [HomeAlert] = []
        for w in store.watchlist {
            guard let target = w.target_price, target > 0,
                  let market = store.marketPrice(w.product_id, printing: w.printing)?.market,
                  market <= target,
                  let product = store.products[w.product_id] else { continue }
            let name = product.name.count > 26 ? String(product.name.prefix(25)) + "…" : product.name
            out.append(HomeAlert(id: "watch:\(w.id)", text: "\(name) hit your \(Format.money(target)) target", good: true, target: .product(w.product_id)))
            if out.count >= 3 { return out }
        }
        // Grading is your account's (a demo has none of its own).
        if store.demo == nil {
            let away = Int(grading.sent.reduce(0) { $0 + $1.quantity }.rounded())
            if away > 0 {
                out.append(HomeAlert(id: "grading", text: away == 1 ? "1 card at the grader" : "\(away) cards at the grader", good: false, target: .grading))
            }
        }
        return Array(out.prefix(3))
    }
}

/// A slim row of glass chips under the search field. Stays inside the margins; the chips scroll
/// inside it when they don't fit.
struct HomeAlertsStrip: View {
    var alerts: [HomeAlert]
    var open: (HomeAlert.Target) -> Void

    var body: some View {
        ScrollView(.horizontal) {
            HStack(spacing: 8) {
                ForEach(alerts) { alert in
                    Button { open(alert.target) } label: { chip(alert) }
                        .buttonStyle(.plain)
                }
            }
            .padding(.vertical, 2)
        }
        .scrollIndicators(.hidden)
        .padding(.horizontal, 16)
    }

    private func chip(_ alert: HomeAlert) -> some View {
        HStack(spacing: 7) {
            if alert.good {
                Circle().fill(Theme.lime).frame(width: 6, height: 6)
            }
            Text(alert.text).font(.geist(13, .medium)).foregroundStyle(.white).lineLimit(1)
            Image(systemName: "chevron.right").font(.system(size: 9, weight: .semibold)).foregroundStyle(Theme.subtle)
        }
        .padding(.horizontal, 12)
        .frame(height: 32)
        .liquidGlass(in: Capsule())
        .contentShape(Capsule())
    }
}

// MARK: - Today sheet

/// What moved today: every holding whose price changed since yesterday, biggest move first,
/// under the day's total. Tapping one opens Owned.
struct TodaySheet: View {
    @Environment(CollectionStore.self) private var store
    @Environment(\.dismiss) private var dismiss
    /// A row was tapped: the caller closes this sheet and opens Owned for it.
    var onOpen: (HoldingIdentity) -> Void

    struct Move {
        var holding: HoldingView
        var change: Double
        /// A ratio (0.012 for 1.2%).
        var ratio: Double
    }

    /// Holdings with a day change worth showing (a cent or more), biggest move first.
    static func moved(_ holdings: [HoldingView]) -> [Move] {
        holdings.compactMap { h -> Move? in
            guard let change = h.dayChange, abs(change) >= 0.005, let pct = h.change24hPct else { return nil }
            return Move(holding: h, change: change, ratio: pct / 100)
        }
        .sorted { abs($0.change) > abs($1.change) }
    }

    var body: some View {
        sheetBody.presentationDetents([.medium, .fraction(0.93)]).glassSheet()
    }

    private var sheetBody: some View {
        let s = store.summary
        let moves = Self.moved(store.holdings)
        return ScrollView {
            VStack(alignment: .leading, spacing: 20) {
                // Title and Done sit in the content (no navigation bar), so nothing shifts while
                // the sheet comes up.
                titleRow
                total(s, count: moves.count)
                if moves.isEmpty {
                    Text("Nothing has moved today.")
                        .font(.geist(15)).foregroundStyle(Theme.muted)
                        .frame(maxWidth: .infinity, alignment: .center)
                        .padding(.vertical, 24)
                } else {
                    LazyVStack(alignment: .leading, spacing: 14) {
                        ForEach(moves, id: \.holding.id) { m in
                            Button { onOpen(m.holding.identity) } label: { row(m) }
                                .buttonStyle(.plain)
                        }
                    }
                }
            }
            .frame(maxWidth: .infinity, alignment: .leading)
            .padding(.horizontal, 20)
            .padding(.top, 18)
            .padding(.bottom, 24)
        }
        .scrollContentBackground(.hidden)
    }

    private var titleRow: some View {
        ZStack {
            Text("Today").font(.geist(17, .semibold))
            HStack {
                Spacer()
                Button("Done") { dismiss() }
                    .font(.geist(16, .semibold)).foregroundStyle(Theme.lime)
                    .padding(.horizontal, 14).frame(height: 36)
                    .background(Capsule().fill(Color.white.opacity(0.09)))
            }
        }
        .frame(maxWidth: .infinity)
    }

    private func total(_ s: PortfolioSummary, count: Int) -> some View {
        let tint = Theme.tone(s.dayChange)
        return VStack(alignment: .leading, spacing: 6) {
            MonoLabel(text: count == 1 ? "1 piece moved" : "\(count) pieces moved")
            HStack(alignment: .firstTextBaseline, spacing: 6) {
                Text(Format.signedMoney(s.dayChange))
                    .font(.display(34)).tracking(-1)
                    .foregroundStyle(tint)
                Text("today").font(.geist(15)).foregroundStyle(Theme.muted)
                if let r = s.dayRatio {
                    Text("·").font(.geist(15)).foregroundStyle(Theme.muted)
                    Text(Format.signedPercent(r)).font(.geist(15, .semibold)).foregroundStyle(tint)
                }
            }
            .monospacedDigit()
            .lineLimit(1).minimumScaleFactor(0.7)
        }
        .accessibilityElement(children: .combine)
    }

    private func row(_ m: Move) -> some View {
        let h = m.holding
        let tint = Theme.tone(m.change)
        return HStack(spacing: 12) {
            HoldingArt(product: h.product, identity: h.identity, cornerRadius: 6, caption: false)
                .frame(width: 36, height: 48)
            VStack(alignment: .leading, spacing: 2) {
                Text(h.product?.name ?? "").font(.geist(15, .medium)).lineLimit(1).foregroundStyle(.white)
                Text([Format.money(h.price), h.quantity > 1 ? "×\(Int(h.quantity))" : nil, h.label].compactMap { $0 }.joined(separator: " · "))
                    .font(.geist(13)).foregroundStyle(Theme.muted).monospacedDigit().lineLimit(1)
            }
            Spacer(minLength: 8)
            VStack(alignment: .trailing, spacing: 2) {
                Text(Format.signedMoney(m.change)).font(.geist(15, .semibold)).foregroundStyle(tint)
                Text(Format.signedPercent(m.ratio)).font(.geist(13)).foregroundStyle(tint.opacity(0.8))
            }
            .monospacedDigit()
        }
        .contentShape(Rectangle())
    }
}
