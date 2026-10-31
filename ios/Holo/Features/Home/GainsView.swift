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
            VStack(alignment: .leading, spacing: 16) {
                PageHeader(title: "Gains", subtitle: "See exactly which products your gains come from.")
                ScrollView(.horizontal, showsIndicators: false) {
                    HStack(spacing: 8) {
                        ChipPicker(options: [(.unrealized, "Unrealized"), (.realized, "Realized"), (.all, "All-time")], selection: $mode)
                        ChipPicker(options: [(.product, "Products"), (.set, "Sets"), (.category, "Type")], selection: Binding(
                            get: { group },
                            set: { group = $0; expanded = false }
                        ))
                    }
                }
                .scrollClipDisabled()

                VStack(alignment: .leading, spacing: 0) {
                    Text(label).font(.geist(13, .medium)).foregroundStyle(Theme.muted)
                    Text(Format.signedMoney(a.total)).font(.display(52)).monospacedDigit().foregroundStyle(Theme.tone(a.total))
                        .lineLimit(1).minimumScaleFactor(0.5).displayTrim(52).padding(.top, 10)
                    Text(hint).font(.geist(13)).foregroundStyle(Theme.subtle).padding(.top, 10)
                    HStack(spacing: 24) {
                        tally("Gains · \(a.winners) \(a.winners == 1 ? noun.one : noun.many)", a.gains > 0 ? Format.signedMoney(a.gains) : Format.money(0), a.gains > 0 ? Theme.up : Theme.muted)
                        tally("Losses · \(a.losers) \(a.losers == 1 ? noun.one : noun.many)", a.losses < 0 ? Format.signedMoney(a.losses) : Format.money(0), a.losses < 0 ? Theme.down : Theme.muted)
                    }
                    .padding(.top, 16)

                    if let share = a.topThreeShare, a.winners > 3 {
                        (Text("Your top 3 \(noun.many) account for ") + Text("\(Int((share * 100).rounded()))%").fontWeight(.semibold).foregroundColor(.white) + Text(" of your gains."))
                            .font(.geist(14)).foregroundStyle(Theme.muted)
                            .padding(.horizontal, 14).padding(.vertical, 12)
                            .frame(maxWidth: .infinity, alignment: .leading)
                            .background(Theme.surface2, in: RoundedRectangle(cornerRadius: 12, style: .continuous))
                            .padding(.top, 18)
                    }

                    if a.steps.isEmpty {
                        Text(mode == .realized ? "No sales or write-offs yet." : "No gains or losses yet.")
                            .font(.geist(14)).foregroundStyle(Theme.muted)
                            .frame(maxWidth: .infinity).padding(.vertical, 48)
                    } else {
                        Waterfall(steps: a.steps, total: a.total, totalLabel: label, gains: a.gains, group: group)
                            .padding(.top, 22)
                        if a.count > Self.collapsedRows {
                            Button(expanded ? "Show top contributors only" : "Show all \(a.count) \(noun.many)") { expanded.toggle() }
                                .font(.geist(13, .medium)).foregroundStyle(Theme.muted)
                                .padding(.top, 16)
                        }
                    }
                }
                .surface(radius: 22, padding: 18)

                if a.unpriced > 0, mode != .realized {
                    Label("\(a.unpriced) holding\(a.unpriced == 1 ? " has" : "s have") no market price and \(a.unpriced == 1 ? "isn't" : "aren't") included.", systemImage: "exclamationmark.circle")
                        .font(.geist(13)).foregroundStyle(Theme.muted)
                }
            }
            .padding(.horizontal, 16)
            .padding(.bottom, 120)
        }
        .background(Theme.background)
        .navigationBarTitleDisplayMode(.inline)
        .pageTitle("Gains")
    }

    private func tally(_ title: String, _ value: String, _ tint: Color) -> some View {
        VStack(alignment: .leading, spacing: 2) {
            Text(title).font(.geist(13)).foregroundStyle(Theme.muted).lineLimit(1)
            Text(value).font(.geist(15, .semibold)).monospacedDigit().foregroundStyle(tint)
        }
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
            ForEach(steps) { s in
                if group == .product, s.key != "__other" {
                    NavigationLink(value: s.key) { row(s, pos: pos) }.buttonStyle(.plain)
                } else {
                    row(s, pos: pos)
                }
            }
            Divider().overlay(Theme.border).padding(.vertical, 4)
            VStack(spacing: 8) {
                HStack {
                    Text(totalLabel).font(.geist(14, .semibold))
                    Spacer()
                    Text(Format.signedMoney(total)).font(.geist(15, .semibold)).monospacedDigit().foregroundStyle(Theme.tone(total))
                }
                Bar(start: 0, end: total, pos: pos, isTotal: true)
            }
        }
    }

    private func row(_ s: Gains.Row, pos: @escaping (Double) -> Double) -> some View {
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
            Bar(start: s.start, end: s.end, pos: pos, isTotal: false)
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
            HoldingArt(product: s.product, identity: s.identity, cornerRadius: 6, caption: false).frame(width: 30, height: 40)
        }
    }
}

/// One waterfall segment from `start` to `end` on the shared scale, with a hairline at zero.
private struct Bar: View {
    var start: Double
    var end: Double
    var pos: (Double) -> Double
    var isTotal: Bool

    var body: some View {
        GeometryReader { geo in
            let w = geo.size.width
            let left = pos(min(start, end)) * w
            let width = max(abs(pos(end) - pos(start)) * w, 3)
            let up = end >= start
            let tint = isTotal ? Color.white : up ? Theme.up : Theme.down
            ZStack(alignment: .leading) {
                Rectangle().fill(Theme.border).frame(width: 1).offset(x: pos(0) * w)
                Capsule()
                    .fill(LinearGradient(colors: [tint.opacity(0.35), tint], startPoint: up ? .leading : .trailing, endPoint: up ? .trailing : .leading))
                    .frame(width: width, height: 10)
                    .offset(x: left)
            }
            .frame(height: geo.size.height)
        }
        .frame(height: 14)
    }
}
