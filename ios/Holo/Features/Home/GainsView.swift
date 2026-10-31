import SwiftUI

/// Where your gains come from, like the website's Gains page: unrealized, realized or all-time,
/// by product, set or type, as a waterfall that adds up to the total.
struct GainsView: View {
    @Environment(CollectionStore.self) private var store
    @State private var mode = Gains.Mode.unrealized
    @State private var group = Gains.Group.product
    @State private var expanded = false

    private static let collapsedRows = 12

    private var label: String {
        switch mode {
        case .unrealized: return "Unrealized gain"
        case .realized: return "Realized gain"
        case .all: return "Total gain"
        }
    }

    private var hint: String {
        switch mode {
        case .unrealized: return "Market value minus cost basis of what you hold today."
        case .realized: return "Profit or loss locked in by sales and write-offs."
        case .all: return "Unrealized plus realized: everything your collection has earned."
        }
    }

    private var noun: (one: String, many: String) {
        switch group {
        case .product: return ("product", "products")
        case .set: return ("set", "sets")
        case .category: return ("type", "types")
        }
    }

    var body: some View {
        let a = Gains.attribute(holdings: store.holdings, transactions: store.portfolioTransactions, products: store.products,
                                mode: mode, group: group, maxRows: expanded ? nil : Self.collapsedRows)
        ScrollView {
            VStack(alignment: .leading, spacing: 28) {
                TugOfWarHero(label: label, total: a.total, gains: a.gains, losses: a.losses,
                             leaders: a.steps.filter { $0.gain > 0 && $0.members == nil })
                    .id("\(mode.rawValue)\(group.rawValue)")
                Text(hint).font(.geist(13)).foregroundStyle(Theme.muted)
                ChipPicker(options: [(.unrealized, "Unrealized"), (.realized, "Realized"), (.all, "All-time")], selection: $mode)
                VStack(alignment: .leading, spacing: 16) {
                    HStack(alignment: .center) {
                        MoreHeading(title: "Where it comes from", subtitle: nil)
                        // Group by product, set or type: a menu, so there's one row of tabs on the page.
                        Menu {
                            Picker("Group by", selection: Binding(get: { group }, set: { group = $0; expanded = false })) {
                                Text("Products").tag(Gains.Group.product)
                                Text("Sets").tag(Gains.Group.set)
                                Text("Type").tag(Gains.Group.category)
                            }
                        } label: {
                            HStack(spacing: 5) {
                                Text(noun.many.capitalized).font(.geist(14, .semibold))
                                Image(systemName: "chevron.down").font(.system(size: 10, weight: .bold))
                            }
                            .foregroundStyle(.white)
                            .padding(.horizontal, 14).frame(height: 36)
                            .liquidGlass(in: Capsule())
                        }
                    }
                    Text("Each bar starts where the last one ended, gains first, then losses").font(.geist(14)).foregroundStyle(Theme.muted)
                    if a.steps.isEmpty {
                        Text(mode == .realized ? "No sales or write-offs yet." : "No gains or losses yet.")
                            .font(.geist(14)).foregroundStyle(Theme.muted)
                            .frame(maxWidth: .infinity).padding(.vertical, 48)
                            .surface(radius: 16, padding: 16)
                    } else {
                        VStack(alignment: .leading, spacing: 0) {
                            Waterfall(steps: a.steps, total: a.total, totalLabel: label, gains: a.gains, group: group)
                                .id("\(mode.rawValue)\(group.rawValue)\(expanded)")
                            if a.count > Self.collapsedRows {
                                Button(expanded ? "Show top contributors only" : "Show all \(a.count) \(noun.many)") { expanded.toggle() }
                                    .buttonStyle(Button3D(kind: .dark, height: 42))
                                    .padding(.top, 16)
                            }
                        }
                        .surface(radius: 16, padding: 16)
                    }
                }
                .reveal()

                if a.unpriced > 0, mode != .realized {
                    Label("\(a.unpriced) holding\(a.unpriced == 1 ? " has" : "s have") no market price and \(a.unpriced == 1 ? "isn't" : "aren't") included.", systemImage: "exclamationmark.circle")
                        .font(.geist(13)).foregroundStyle(Theme.muted)
                }
            }
            .padding(.horizontal, 16)
            .padding(.bottom, 120)
        }
        .background(Theme.background)
        .replaysAnimations()
        .sensoryFeedback(.selection, trigger: "\(mode.rawValue)\(group.rawValue)")
        .navigationBarTitleDisplayMode(.inline)
        .pageTitle("Gains")
    }
}

/// The waterfall: each row's bar runs from where the last one ended, on one shared scale.
private struct Waterfall: View {
    var steps: [Gains.Row]
    var total: Double
    var totalLabel: String
    var gains: Double
    var group: Gains.Group

    var body: some View {
        let lo = steps.reduce(0.0) { min($0, $1.start, $1.end) }
        let hi = steps.reduce(0.0) { max($0, $1.start, $1.end) }
        let span = hi - lo == 0 ? 1 : hi - lo
        let pos = { (v: Double) in (v - lo) / span }
        VStack(spacing: 6) {
            ForEach(Array(steps.enumerated()), id: \.element.id) { i, s in
                Group {
                    if group == .product, s.key != "__other" {
                        NavigationLink(value: s.key) { row(s, pos: pos, delay: Double(min(i, 14)) * 0.07) }.buttonStyle(.plain)
                    } else {
                        row(s, pos: pos, delay: Double(min(i, 14)) * 0.07)
                    }
                }
            }
            Divider().overlay(Theme.border).padding(.vertical, 4)
            VStack(spacing: 8) {
                HStack {
                    Text(totalLabel).font(.geist(14, .semibold))
                    Spacer()
                    Text(Format.signedMoney(total)).font(.geist(15, .semibold)).monospacedDigit().foregroundStyle(Theme.tone(total))
                }
                Bar(start: 0, end: total, pos: pos, isTotal: true, delay: Double(min(steps.count, 14)) * 0.07)
            }
        }
    }

    private func row(_ s: Gains.Row, pos: @escaping (Double) -> Double, delay: Double) -> some View {
        let share = s.gain > 0 && gains > 0 ? s.gain / gains : nil
        let detail = [
            s.quantity > 0 && s.value > 0 ? "\(Format.money(s.value)) value · \(Format.money(s.costBasis)) cost" : nil,
            s.realized != 0 && s.unrealized != 0 ? "\(Format.signedMoney(s.realized)) realized" : s.realized != 0 && s.quantity == 0 ? "Sold" : nil,
            s.members != nil ? "Smaller contributors combined" : nil,
        ].compactMap { $0 }.joined(separator: " · ")
        return VStack(spacing: 8) {
            HStack(spacing: 12) {
                thumb(s)
                VStack(alignment: .leading, spacing: 2) {
                    Text(s.label).font(.geist(14, .medium)).lineLimit(1)
                    if !detail.isEmpty {
                        Text(detail).font(.geist(12)).monospacedDigit().foregroundStyle(Theme.muted).lineLimit(1)
                    }
                }
                Spacer(minLength: 8)
                VStack(alignment: .trailing, spacing: 2) {
                    Text(Format.signedMoney(s.gain)).font(.geist(14, .medium)).monospacedDigit().foregroundStyle(Theme.tone(s.gain))
                    if let share {
                        Text("\(Int((share * 100).rounded()))% of gains").font(.geist(11)).monospacedDigit().foregroundStyle(Theme.subtle)
                    }
                }
            }
            Bar(start: s.start, end: s.end, pos: pos, isTotal: false, delay: delay)
        }
        .padding(.vertical, 6)
        .contentShape(Rectangle())
    }

    @ViewBuilder private func thumb(_ s: Gains.Row) -> some View {
        if group == .category, let c = s.category {
            Circle().fill(c.color).frame(width: 10, height: 10).frame(width: 30)
        } else if let members = s.members {
            Text("+\(members)").font(.geist(12)).foregroundStyle(Theme.muted)
                .frame(width: 30, height: 40)
                .background(Theme.surface2, in: RoundedRectangle(cornerRadius: 8, style: .continuous))
        } else {
            HoldingArt(product: s.product, identity: s.identity, cornerRadius: 3, caption: false).frame(width: 30, height: 40)
        }
    }
}

/// One waterfall segment from `start` to `end` on the shared scale, with a hairline at zero.
private struct Bar: View {
    var start: Double
    var end: Double
    var pos: (Double) -> Double
    var isTotal: Bool
    var delay: Double = 0
    @Environment(\.accessibilityReduceMotion) private var reduceMotion
    @State private var grown = false

    var body: some View {
        GeometryReader { geo in
            let w = geo.size.width
            let left = pos(min(start, end)) * w
            let full = max(abs(pos(end) - pos(start)) * w, 3)
            let g = grown || reduceMotion ? 1.0 : 0.0
            let width = max(full * g, 0.5)
            let up = end >= start
            let tint = isTotal ? (end >= 0 ? Theme.lime : Theme.planPink) : up ? Theme.up : Theme.down
            ZStack(alignment: .leading) {
                // Gains grow rightward from where the last step ended; losses grow leftward.
                Capsule()
                    .fill(LinearGradient(colors: [tint.opacity(0.35), tint], startPoint: up ? .leading : .trailing, endPoint: up ? .trailing : .leading))
                    .frame(width: width, height: 10)
                    .offset(x: up ? left : left + full - width)
            }
            .frame(height: geo.size.height)
        }
        .frame(height: 14)
        .onFirstVisible { grow() }
        .onReplay {
            grown = false
            grow()
        }
    }

    private func grow() {
        guard !reduceMotion else { return }
        withAnimation(.spring(response: 0.7, dampingFraction: 0.85).delay(0.1 + delay)) { grown = true }
    }
}
