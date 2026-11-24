import SwiftUI

// The Deal tab, rebuilt after the owner's recording (Nov 2026): a start page that asks what
// you're doing (buy, sell or trade, always from your side), then one simple page per deal:
// a rate for all cards as chips, Scan card / Add cards, the cards (tap one to change its rate,
// price or quantity), and the total pinned at the bottom with Review deal.

// MARK: - Start

/// "What's the deal?": Buy, Sell or Trade, then your parked and recent deals.
struct DealStartPage: View {
    var onPick: (DealKind) -> Void
    var onParkedAll: () -> Void
    var onHistory: () -> Void
    var onRecord: (DealRecord) -> Void
    @Environment(DealStore.self) private var deals
    /// The parked deal whose ⋯ was tapped (Resume, Delete).
    @State private var acting: ParkedDeal?

    var body: some View {
        ScrollView {
            VStack(alignment: .leading, spacing: 30) {
                VStack(alignment: .leading, spacing: 6) {
                    MonoLabel(text: "New deal")
                    DisplayText(text: "What's the deal?", size: 32)
                    Text("Choose what you're doing today.").font(.geist(15)).foregroundStyle(Theme.muted)
                }
                VStack(spacing: 10) {
                    choice(.buy, icon: "arrow.down.to.line", title: "Buy cards", line: "Pay for cards at your rate.")
                    choice(.sell, icon: "arrow.up.to.line", title: "Sell cards", line: "Price out cards for a buyer.")
                    choice(.trade, icon: "arrow.left.arrow.right", title: "Trade cards", line: "Swap cards and balance the difference.")
                }
                if !deals.parked.isEmpty {
                    list("Parked deals", count: deals.parked.count, onAll: onParkedAll) {
                        ForEach(Array(deals.parked.prefix(3).enumerated()), id: \.element.id) { i, entry in
                            let t = DealTotals(entry.state, rates: deals.rates(for: entry.state), cost: { _ in nil })
                            HStack(spacing: 0) {
                                Button {
                                    Haptics.tap()
                                    withAnimation(.snappy) { deals.resume(entry) }
                                } label: {
                                    DealListRow(kind: entry.state.kind, title: entry.name,
                                                line: "\(DealView.pathTitle(entry.state.kind)) · \(cards(entry.state.incoming.count + entry.state.outgoing.count))",
                                                amount: abs(t.balance), note: "Parked", divider: false)
                                }
                                .buttonStyle(.plain)
                                // Its actions (Resume, Delete), so deleting never hides.
                                RowMoreButton(label: entry.name) { acting = entry }
                                    .padding(.trailing, -10)
                            }
                            .overlay(alignment: .top) { if i > 0 { Rectangle().fill(Theme.border).frame(height: 1) } }
                        }
                    }
                }
                if !deals.log.isEmpty {
                    list("Recent deals", count: deals.log.count, onAll: onHistory) {
                        ForEach(Array(deals.log.prefix(3).enumerated()), id: \.element.id) { i, r in
                            Button { onRecord(r) } label: {
                                DealListRow(kind: r.kind, title: title(r),
                                            line: "\(DealView.pathTitle(r.kind)) · \(cards(r.items)) · \(when(r))",
                                            amount: abs(r.balance),
                                            // How it ended: ahead or behind, coloured (the cash is the amount above).
                                            note: r.aheadTotal.map { abs($0) < 0.005 ? "Even" : "\(Format.signedMoney($0)) \($0 > 0 ? "profit" : "loss")" } ?? "Completed",
                                            noteTint: r.aheadTotal.map { abs($0) < 0.005 ? Theme.muted : Theme.tone($0) },
                                            divider: i > 0)
                            }
                            .buttonStyle(.plain)
                        }
                    }
                }
            }
            .padding(.horizontal, 16).padding(.top, 8).padding(.bottom, 40)
        }
        .actionsSheet(item: $acting, title: { $0.name }) { entry in
            [[SheetAction(title: "Resume deal", icon: "play") { withAnimation(.snappy) { deals.resume(entry) } }],
             [SheetAction(title: "Delete deal", icon: "trash", destructive: true) { withAnimation(.snappy) { deals.deleteParked(entry) } }]]
        }
    }

    private func choice(_ k: DealKind, icon: String, title: String, line: String) -> some View {
        Button { onPick(k) } label: {
            HStack(spacing: 14) {
                Image(systemName: icon).font(.system(size: 17, weight: .semibold)).foregroundStyle(.white)
                    .frame(width: 44, height: 44)
                    .background(RoundedRectangle(cornerRadius: 12, style: .continuous).fill(Color.white.opacity(0.08)))
                VStack(alignment: .leading, spacing: 2) {
                    Text(title).font(.geist(17, .semibold)).foregroundStyle(.white)
                    Text(line).font(.geist(13)).foregroundStyle(Theme.muted)
                }
                Spacer(minLength: 8)
                Image(systemName: "chevron.right").font(.system(size: 13, weight: .semibold)).foregroundStyle(Theme.subtle)
            }
            .padding(14)
            .liquidGlass(in: RoundedRectangle(cornerRadius: 20, style: .continuous))
            .contentShape(RoundedRectangle(cornerRadius: 20, style: .continuous))
        }
        .buttonStyle(.plain)
    }

    private func list<C: View>(_ title: String, count: Int?, onAll: @escaping () -> Void, @ViewBuilder _ rows: () -> C) -> some View {
        VStack(alignment: .leading, spacing: 8) {
            HStack(alignment: .firstTextBaseline) {
                Text(title).font(.display(20)).tracking(-0.5)
                if let count { Text("\(count)").font(.geist(14)).foregroundStyle(Theme.subtle) }
                Spacer()
                Button("View all", action: onAll).font(.geist(14, .medium)).foregroundStyle(Theme.muted).buttonStyle(.plain)
            }
            VStack(spacing: 0) { rows() }
        }
    }

    private func cards(_ n: Int) -> String { "\(n) card\(n == 1 ? "" : "s")" }

    /// A closed deal's name: its first card, and how many more.
    private func title(_ r: DealRecord) -> String {
        guard let first = r.lines?.first else { return DealView.pathTitle(r.kind) }
        let more = (r.lines?.count ?? 1) - 1
        return first.product.name + (more > 0 ? " +\(more)" : "")
    }

    private func when(_ r: DealRecord) -> String {
        guard let d = ISO8601DateFormatter.withFraction.date(from: r.at) ?? ISO8601DateFormatter().date(from: r.at) else { return "" }
        if Calendar.current.isDateInToday(d) { return "Today" }
        if Calendar.current.isDateInYesterday(d) { return "Yesterday" }
        return d.formatted(.dateTime.month(.abbreviated).day())
    }
}

/// A parked or closed deal: its kind's icon, name, one line, the amount and a quiet note.
private struct DealListRow: View {
    var kind: DealKind
    var title: String
    var line: String
    var amount: Double
    var note: String
    var noteTint: Color? = nil
    var divider: Bool

    var body: some View {
        HStack(spacing: 12) {
            Image(systemName: kind == .buy ? "arrow.down.to.line" : kind == .sell ? "arrow.up.to.line" : "arrow.left.arrow.right")
                .font(.system(size: 14, weight: .semibold)).foregroundStyle(.white)
                .frame(width: 38, height: 38)
                .background(RoundedRectangle(cornerRadius: 10, style: .continuous).fill(Color.white.opacity(0.07)))
            VStack(alignment: .leading, spacing: 2) {
                Text(title).font(.geist(15, .medium)).foregroundStyle(.white).lineLimit(1)
                Text(line).font(.geist(12)).foregroundStyle(Theme.muted).lineLimit(1)
            }
            Spacer(minLength: 8)
            VStack(alignment: .trailing, spacing: 2) {
                Text(Format.money(amount)).font(.geist(15, .semibold)).monospacedDigit().foregroundStyle(.white)
                Text(note).font(.geist(12, noteTint == nil ? .regular : .semibold)).monospacedDigit().foregroundStyle(noteTint ?? Theme.subtle)
            }
        }
        .padding(.vertical, 12)
        .overlay(alignment: .top) { if divider { Rectangle().fill(Theme.border).frame(height: 1) } }
        .contentShape(Rectangle())
    }
}

// MARK: - The deal

/// One deal: title and name, (on a trade) I receive / I give, the side's rate as chips, Scan card
/// and Add cards, the cards, and the total pinned at the bottom with park and Review deal.
struct DealEditorPage: View {
    var path: DealKind
    var name: String
    var onScan: (DealSide) -> Void
    var onAdd: (DealSide) -> Void
    var onEditCard: (DealItem) -> Void
    var onCustomRate: (DealSide) -> Void
    var onRename: () -> Void
    /// The deal's ⋯: Name, Park, Delete.
    var onMore: () -> Void
    var onReview: () -> Void
    var onPark: () -> Void
    @Environment(DealStore.self) private var deals
    @Environment(CollectionStore.self) private var store
    @State private var tradeSide = DealSide.incoming
    /// The breakdown above the total (open by default on a trade, where it matters most).
    @State private var breakdownOpen: Bool?

    private var side: DealSide { path == .buy ? .incoming : path == .sell ? .outgoing : tradeSide }

    var body: some View {
        let rates = deals.rates
        let totals = DealTotals(deals.deal.settled(rates: rates), rates: rates, cost: { deals.cost(of: $0, in: store) })
        let items = side == .incoming ? deals.deal.incoming : deals.deal.outgoing
        let rate = side == .incoming ? rates.in : rates.out
        let count = deals.deal.incoming.count + deals.deal.outgoing.count
        ScrollView {
            VStack(alignment: .leading, spacing: 18) {
                // Title, and the deal's name; the ⋯ names, parks or deletes it.
                HStack(alignment: .top) {
                    VStack(alignment: .leading, spacing: 4) {
                        DisplayText(text: path == .buy ? "New purchase" : path == .sell ? "New sale" : "New trade", size: 30)
                        Text("\(name.isEmpty ? "Untitled deal" : name) · \(count) card\(count == 1 ? "" : "s")")
                            .font(.geist(14)).foregroundStyle(Theme.muted)
                    }
                    Spacer()
                    Button { Haptics.tap(); onMore() } label: {
                        Image(systemName: "ellipsis").font(.system(size: 17, weight: .semibold)).foregroundStyle(.white)
                            .frame(width: 40, height: 40).liquidGlass(in: Circle())
                    }
                    .buttonStyle(.plain)
                    .accessibilityLabel("Deal actions")
                }
                if path == .trade {
                    ChipPicker(options: [(DealSide.incoming, "Buy · \(Format.money(totals.inValue))"),
                                         (.outgoing, "Sell · \(Format.money(totals.outValue))")],
                               selection: $tradeSide, fills: true)
                }
                rateCard(rate: rate)
                HStack(spacing: 10) {
                    Button { onScan(side) } label: {
                        Label("Scan card", systemImage: "viewfinder").font(.geist(15, .semibold)).foregroundStyle(.white)
                            .frame(maxWidth: .infinity).frame(height: 48)
                            .liquidGlass(in: Capsule())
                            .contentShape(Capsule())
                    }
                    .buttonStyle(.plain)
                    Button { onAdd(side) } label: {
                        Label("Add cards", systemImage: "plus").font(.geist(15, .semibold)).foregroundStyle(Theme.ink)
                            .frame(maxWidth: .infinity).frame(height: 48)
                            .background(Capsule().fill(Theme.lime))
                            .contentShape(Capsule())
                    }
                    .buttonStyle(.plain)
                }
                cardsList(items, rate: rate)
            }
            .padding(.horizontal, 16).padding(.top, 4).padding(.bottom, 24)
        }
        .safeAreaInset(edge: .bottom, spacing: 0) { summary(totals) }
        .navigationBarTitleDisplayMode(.inline)
        .pageTitle(path == .buy ? "Buying cards" : path == .sell ? "Selling cards" : "Trading cards")
    }

    // MARK: Rate

    private func rateCard(rate: Double) -> some View {
        let pct = Int((rate * 100).rounded())
        let title = path == .buy ? "Buying rate" : path == .sell ? "Selling rate" : (side == .incoming ? "Buying rate" : "Selling rate")
        return VStack(alignment: .leading, spacing: 12) {
            HStack(alignment: .center) {
                VStack(alignment: .leading, spacing: 2) {
                    Text(title).font(.geist(15, .semibold)).foregroundStyle(.white)
                    Text("Default for all cards").font(.geist(12)).foregroundStyle(Theme.muted)
                }
                Spacer()
                Text("\(pct)%").font(.display(28)).tracking(-0.8).monospacedDigit().foregroundStyle(.white)
                    .contentTransition(.numericText())
                    .animation(.snappy, value: pct)
            }
            HStack(spacing: 6) {
                ForEach([75, 80, 85, 90, 100], id: \.self) { v in
                    Button {
                        Haptics.tap()
                        setRate(Double(v) / 100)
                    } label: {
                        // The app's chip look: a glass tile with a faint light edge, the picked one white.
                        Text("\(v)%").font(.geist(13, .semibold)).monospacedDigit()
                            .foregroundStyle(v == pct ? Theme.ink : .white)
                            .frame(maxWidth: .infinity).frame(height: 36)
                            .background { rateChip(on: v == pct) }
                    }
                    .buttonStyle(.plain)
                }
                Button { onCustomRate(side) } label: {
                    Image(systemName: "ellipsis").font(.system(size: 13, weight: .semibold)).foregroundStyle(.white)
                        .frame(maxWidth: .infinity).frame(height: 36)
                        .background { rateChip(on: false) }
                }
                .buttonStyle(.plain)
                .accessibilityLabel("Another rate")
            }
        }
        .padding(16)
        // A glass panel like the app's other cards (it was a flat dark box).
        .liquidGlass(in: RoundedRectangle(cornerRadius: 22, style: .continuous))
    }

    @ViewBuilder private func rateChip(on: Bool) -> some View {
        let shape = RoundedRectangle(cornerRadius: 13, style: .continuous)
        if on {
            shape.fill(Color.white)
        } else {
            shape.fill(Color.white.opacity(0.06))
                .overlay(shape.strokeBorder(LinearGradient(colors: [.white.opacity(0.18), .white.opacity(0.05)], startPoint: .top, endPoint: .bottom), lineWidth: 1))
        }
    }

    private func setRate(_ r: Double) {
        deals.update { d in if side == .incoming { d.rateIn = r } else { d.rateOut = r } }
    }

    // MARK: Cards

    @ViewBuilder private func cardsList(_ items: [DealItem], rate: Double) -> some View {
        let market = items.reduce(0.0) { $0 + ($1.market ?? 0) * Double($1.qty) }
        VStack(alignment: .leading, spacing: 4) {
            HStack(alignment: .firstTextBaseline) {
                Text(path == .trade ? (side == .incoming ? "Buying" : "Selling") : "Cards").font(.display(20)).tracking(-0.5)
                Text("\(items.reduce(0) { $0 + $1.qty })").font(.geist(14)).foregroundStyle(Theme.subtle)
                Spacer()
                Text("\(Format.money(market)) market").font(.geist(13)).monospacedDigit().foregroundStyle(Theme.muted)
            }
            .padding(.top, 8)
            if items.isEmpty {
                VStack(spacing: 8) {
                    Image(systemName: "rectangle.portrait.on.rectangle.portrait").font(.system(size: 22)).foregroundStyle(Theme.subtle)
                    Text("No cards added yet.").font(.geist(14, .medium)).foregroundStyle(Theme.muted)
                    Text("Scan or search to start your deal.").font(.geist(13)).foregroundStyle(Theme.subtle)
                }
                .frame(maxWidth: .infinity).padding(.vertical, 36)
            } else {
                ForEach(Array(items.enumerated()), id: \.element.id) { i, item in
                    Button { onEditCard(item) } label: { cardRow(item, rate: rate) }
                        .buttonStyle(.plain)
                        .overlay(alignment: .top) { if i > 0 { Rectangle().fill(Theme.border).frame(height: 1) } }
                }
            }
        }
    }

    private func cardRow(_ item: DealItem, rate: Double) -> some View {
        let unit = item.unitPrice(side: rate)
        let total = unit.map { $0 * Double(item.qty) }
        // Selling: what you paid for it (from your collection, or typed in) and the profit.
        let selling = side == .outgoing
        let cost = selling ? deals.cost(of: item, in: store) : nil
        let profit: Double? = { guard let cost, let total else { return nil }; return total - cost }()
        // The card's true share of market: "99.6%" when a rounded total moved it off a whole number.
        let share: Double? = { guard let unit, let m = item.market, m > 0 else { return nil }; return unit / m * 100 }()
        let offWhole = share.map { abs($0 - $0.rounded()) >= 0.05 } ?? false
        let pct: String? = share.map { offWhole ? String(format: "%.1f", $0) : "\(Int($0.rounded()))" }
        return HStack(alignment: .center, spacing: 12) {
            HoldingArt(product: item.product, cornerRadius: 3, caption: false).frame(width: 40, height: 56)
            VStack(alignment: .leading, spacing: 2) {
                Text(ActionsSheet.shortName(item.product)).font(.geist(15, .medium)).foregroundStyle(.white).lineLimit(1)
                Text([item.product.setName, item.product.number].compactMap { $0 }.joined(separator: " · "))
                    .font(.geist(12)).foregroundStyle(Theme.muted).lineLimit(1)
                Text((item.qty > 1 ? "×\(item.qty) · " : "") + (item.market.map { "\(Format.money($0)) market" } ?? "No market price")
                     // Changed by hand: the catalog's price beside it, so both sides can see.
                     + (item.catalogMarket.map { " (was \(Format.money($0)))" } ?? ""))
                    .font(.geist(12)).monospacedDigit().foregroundStyle(Theme.subtle).lineLimit(1)
                if selling && !item.isCustom {
                    if let cost {
                        Text("Paid \(Format.money(cost))").font(.geist(12)).monospacedDigit().foregroundStyle(Theme.muted)
                    } else {
                        Text("Add what you paid").font(.geist(12, .medium)).foregroundStyle(Theme.lime)
                    }
                }
            }
            Spacer(minLength: 8)
            VStack(alignment: .trailing, spacing: 4) {
                Text(total.map { Format.money($0) } ?? "Set price").font(.geist(15, .semibold)).monospacedDigit()
                    .foregroundStyle(total == nil ? Theme.lime : .white)
                if let pct {
                    HStack(spacing: 2) {
                        Text("\(pct)%")
                        if item.price != nil || item.rate != nil || offWhole { Image(systemName: "pencil").font(.system(size: 8, weight: .bold)) }
                    }
                    .font(.geist(11, .semibold)).monospacedDigit().foregroundStyle(.white.opacity(0.8))
                    .padding(.horizontal, 7).frame(height: 20)
                    .background(Capsule().fill(Color.white.opacity(0.08)))
                }
                if let profit {
                    Text(Format.signedMoney(profit)).font(.geist(12, .semibold)).monospacedDigit().foregroundStyle(Theme.tone(profit))
                }
            }
        }
        .padding(.vertical, 10)
        .contentShape(Rectangle())
    }

    // MARK: Summary

    private func summary(_ t: DealTotals) -> some View {
        let b = t.balance
        let market = (deals.deal.incoming + deals.deal.outgoing).reduce(0.0) { $0 + ($1.market ?? 0) * Double($1.qty) }
        let label: String = {
            switch path {
            case .buy: return "You pay"
            case .sell: return "You receive"
            default: return abs(b) < 0.005 ? "Even trade" : (b > 0 ? "You receive" : "You pay")
            }
        }()
        let empty = deals.deal.kind == .empty
        // What the cards going out cost you, when every one has a cost, and the profit on them.
        let out = deals.deal.settled(rates: deals.rates).outgoing
        let costs = out.map { deals.cost(of: $0, in: store) }
        let basis: Double? = out.isEmpty || costs.contains(where: { $0 == nil }) ? nil : costs.reduce(0) { $0 + ($1 ?? 0) }
        let getMarket = deals.deal.incoming.reduce(0.0) { $0 + ($1.market ?? 0) * Double($1.qty) }
        let open = breakdownOpen ?? false
        let ahead = DealBreakdown.ahead(t, basis: basis, selling: !out.isEmpty)
        return VStack(alignment: .leading, spacing: 6) {
            // The answer in plain words; tap it for what it's made of.
            if !empty {
                Button {
                    Haptics.tap()
                    withAnimation(.snappy(duration: 0.25)) { breakdownOpen = !open }
                } label: {
                    HStack(spacing: 6) {
                        Text(DealBreakdown.verdict(ahead)).font(.geist(14, .semibold))
                            .foregroundStyle(ahead.map { abs($0) < 0.005 ? Color.white : Theme.tone($0) } ?? Theme.muted)
                        Image(systemName: "chevron.down").font(.system(size: 10, weight: .bold)).foregroundStyle(Theme.muted)
                            .rotationEffect(.degrees(open ? 180 : 0))
                        Spacer()
                    }
                    .contentShape(Rectangle())
                }
                .buttonStyle(.plain)
                if open {
                    DealBreakdown(kind: path, totals: t, getMarket: getMarket, basis: basis, selling: !out.isEmpty)
                        .padding(.vertical, 4)
                        .transition(.opacity)
                }
            }
            // A total rounded on the review screen: by how much, and a way back to the cards' prices.
            if deals.deal.agreedCash != nil {
                let plain = DealTotals(deals.unrounded, rates: deals.rates(for: deals.unrounded), cost: { _ in nil })
                let diff = abs(b) - abs(plain.balance)
                if abs(diff) > 0.004 {
                    HStack(spacing: 6) {
                        Text("Rounded \(Format.signedMoney(diff))").font(.geist(13)).monospacedDigit().foregroundStyle(Theme.muted)
                        Text("·").font(.geist(13)).foregroundStyle(Theme.subtle)
                        Button {
                            Haptics.tap()
                            withAnimation(.snappy) { deals.clearAgreedTotal() }
                        } label: { Text("Reset").font(.geist(13, .medium)).foregroundStyle(Theme.lime) }
                        .buttonStyle(.plain)
                    }
                    .padding(.top, 2)
                }
            }
            // One big white line: "You pay $186.70" (the owner's call), the % of market beside it.
            HStack(alignment: .center, spacing: 10) {
                HStack(spacing: 8) {
                    Text(label)
                    if !(path == .trade && abs(b) < 0.005) {
                        Text(Format.money(abs(b))).monospacedDigit()
                            .contentTransition(.numericText())
                            .animation(.snappy, value: b)
                    }
                }
                .font(.display(28)).tracking(-0.8).foregroundStyle(.white)
                .lineLimit(1).minimumScaleFactor(0.6)
                .padding(.top, 2)
                if path != .trade, market > 0 {
                    Text("\(Int((abs(b) / market * 100).rounded()))% of market").font(.geist(12, .medium)).foregroundStyle(.white.opacity(0.8))
                        .padding(.horizontal, 8).frame(height: 22)
                        .background(Capsule().fill(Color.white.opacity(0.08)))
                }
                Spacer(minLength: 0)
            }
            HStack(spacing: 10) {
                Button(action: onPark) {
                    Image(systemName: "pause").font(.system(size: 16, weight: .semibold)).foregroundStyle(.white)
                        .frame(width: 52, height: 52)
                        .liquidGlass(in: RoundedRectangle(cornerRadius: 16, style: .continuous))
                }
                .buttonStyle(.plain)
                .disabled(empty)
                .opacity(empty ? 0.5 : 1)
                .accessibilityLabel("Park this deal")
                Button(action: onReview) {
                    Text("Review deal").font(.geist(16, .semibold)).foregroundStyle(Theme.ink)
                        .frame(maxWidth: .infinity).frame(height: 52)
                        .background(RoundedRectangle(cornerRadius: 16, style: .continuous).fill(Theme.lime))
                        .contentShape(Rectangle())
                }
                .buttonStyle(.plain)
                .disabled(empty)
                .opacity(empty ? 0.45 : 1)
            }
            .padding(.top, 6)
        }
        // Close above the tab bar: the page's room for the tab bar is generous, so the bar eats into it.
        .padding(.horizontal, 16).padding(.top, 14).padding(.bottom, -16)
        .background(alignment: .top) {
            Theme.background.ignoresSafeArea(edges: .bottom)
                .overlay(alignment: .top) { Rectangle().fill(Theme.border).frame(height: 1) }
        }
    }

    private func line(_ label: String, _ value: String) -> some View {
        HStack {
            Text(label).foregroundStyle(Theme.muted)
            Spacer()
            Text(value).monospacedDigit().foregroundStyle(.white.opacity(0.85))
        }
        .font(.geist(13))
    }
}

// MARK: - A card's price

/// Tap a card: its rate as a percentage or a fixed price, the market price, quantity, reset to
/// the deal's rate, Save changes and Remove card. Fits its content.
struct DealCardSheet: View {
    var item: DealItem
    var rate: Double
    var onSave: (DealItem) -> Void
    var onRemove: () -> Void
    /// Selling: what you paid for these copies (from your collection), or nil to ask for it.
    var selling = false
    var collectionCost: Double? = nil
    /// Opens the card's full page (nil for a custom item, which has none).
    var onOpen: (() -> Void)? = nil
    @Environment(\.dismiss) private var dismiss
    @State private var paid = ""
    enum Mode: Hashable { case percent, fixed }
    @State private var mode = Mode.percent
    @State private var value = ""
    @State private var market = ""
    @State private var qty = 1
    @State private var height: CGFloat = 520

    private var marketValue: Double? { MoneyField.value(market) ?? item.market }

    /// The typed market onto the card, remembering the catalog's the first time it changes (and
    /// forgetting it once it's back to the catalog's).
    private func applyMarket(_ c: inout DealItem) {
        guard let m = MoneyField.value(market) else { return }
        let catalog = item.catalogMarket ?? item.market
        if let catalog, abs(m - catalog) < 0.005 { c.catalogMarket = nil } else if c.catalogMarket == nil { c.catalogMarket = item.market }
        c.market = m
    }
    private var unit: Double? {
        guard let v = MoneyField.value(value) else { return nil }
        if mode == .fixed { return v }
        return marketValue.map { $0 * v / 100 }
    }

    var body: some View {
        VStack(alignment: .leading, spacing: 16) {
            HStack(alignment: .center, spacing: 12) {
                // The card, its name and set; tap them for its full page (prices, history, sales).
                Button {
                    guard let onOpen else { return }
                    dismiss()
                    onOpen()
                } label: {
                    HStack(spacing: 12) {
                        HoldingArt(product: item.product, cornerRadius: 3, caption: false).frame(width: 40, height: 56)
                        VStack(alignment: .leading, spacing: 2) {
                            Text(ActionsSheet.shortName(item.product)).font(.geist(18, .semibold)).foregroundStyle(.white).lineLimit(1)
                            Text([item.product.setName, item.product.number].compactMap { $0 }.joined(separator: " · ")).font(.geist(13)).foregroundStyle(Theme.muted).lineLimit(1)
                            if onOpen != nil {
                                HStack(spacing: 3) {
                                    Text("View card")
                                    Image(systemName: "chevron.right").font(.system(size: 9, weight: .bold))
                                }
                                .font(.geist(13, .medium)).foregroundStyle(Theme.lime)
                                .padding(.top, 2)
                            }
                        }
                    }
                    .contentShape(Rectangle())
                }
                .buttonStyle(.plain)
                .disabled(onOpen == nil)
                Spacer()
                SheetHeader(title: "") { dismiss() }.fixedSize()
            }
            ChipPicker(options: [(Mode.percent, "Percentage"), (.fixed, "Fixed price")],
                       selection: Binding(get: { mode }, set: { switchMode($0) }), fills: true)
            VStack(spacing: 6) {
                Text(mode == .percent ? "Agreed rate" : "Agreed price per card").font(.geist(13)).foregroundStyle(Theme.muted)
                if mode == .percent {
                    StepField(text: $value, step: 1, range: 1...200, suffix: "%", decimals: 0)
                } else {
                    StepField(text: $value, step: 1, range: 0...1_000_000, prefix: "$", decimals: 2)
                }
            }
            // What the field works out to, never the same figure twice: the price on a %, the
            // share of market on a fixed price.
            HStack {
                Text(mode == .percent ? "Agreed price per card" : "Share of market").font(.geist(14)).foregroundStyle(Theme.muted)
                Spacer()
                Text(mode == .percent ? (unit.map { Format.money($0) } ?? "—")
                     : (unit.flatMap { u in marketValue.flatMap { $0 > 0 ? "\(Int((u / $0 * 100).rounded()))%" : nil } } ?? "—"))
                    .font(.geist(15, .semibold)).monospacedDigit().foregroundStyle(.white)
            }
            SheetPanel {
                SheetMoneyRow(title: "Market price", text: $market)
                // Changed by hand (agreed with the other side): one tap puts the catalog's back.
                if let catalog = item.catalogMarket ?? item.market, let typed = MoneyField.value(market),
                   abs(typed - catalog) > 0.004, !item.isCustom {
                    Button {
                        Haptics.tap()
                        market = String(format: "%.2f", catalog)
                    } label: {
                        Text("Reset to catalog price (\(Format.money(catalog)))").font(.geist(13, .medium)).foregroundStyle(Theme.lime)
                            .frame(maxWidth: .infinity, alignment: .leading)
                    }
                    .buttonStyle(.plain)
                    .padding(.bottom, 12)
                }
                SheetDivider()
                HStack {
                    Text("Quantity").font(.geist(16)).foregroundStyle(.white)
                    Spacer()
                    Text("\(qty)").font(.geist(16)).monospacedDigit().foregroundStyle(Theme.muted)
                    Stepper("", value: $qty, in: 1...max(1, item.maxQty ?? 999)).labelsHidden().fixedSize()
                }
                .frame(minHeight: 50)
                if selling && !item.isCustom {
                    SheetDivider()
                    if let collectionCost {
                        // From your collection's records: shown, not typed.
                        HStack {
                            Text("You paid").font(.geist(16)).foregroundStyle(.white)
                            Spacer()
                            Text(Format.money(collectionCost)).font(.geist(16)).monospacedDigit().foregroundStyle(Theme.muted)
                        }
                        .frame(minHeight: 50)
                    } else {
                        SheetMoneyRow(title: "You paid each", text: $paid)
                    }
                }
            }
            if selling, let u = unit, let cost = collectionCost ?? MoneyField.value(paid).map({ $0 * Double(qty) }) {
                let profit = u * Double(qty) - cost
                HStack {
                    Text("Profit").font(.geist(14)).foregroundStyle(Theme.muted)
                    Spacer()
                    Text(Format.signedMoney(profit)).font(.geist(15, .semibold)).monospacedDigit().foregroundStyle(Theme.tone(profit))
                }
            }
            if item.price != nil || item.rate != nil {
                Button {
                    var c = item
                    c.price = nil
                    c.rate = nil
                    c.qty = qty
                    applyMarket(&c)
                    onSave(c)
                    dismiss()
                } label: {
                    Text("Reset to deal rate (\(Int((rate * 100).rounded()))%)").font(.geist(14, .medium)).foregroundStyle(Theme.muted)
                }
                .buttonStyle(.plain)
            }
            SheetLimeButton(title: "Save changes") {
                var c = item
                c.qty = qty
                if selling, collectionCost == nil, !item.isCustom { c.cost = MoneyField.value(paid) }
                applyMarket(&c)
                if let v = MoneyField.value(value) {
                    if mode == .fixed { c.price = v; c.rate = nil } else {
                        let r = v / 100
                        if abs(r - rate) < 0.0001 && item.rate == nil && item.price == nil { c.rate = nil } else { c.rate = r }
                        c.price = nil
                    }
                }
                onSave(c)
                dismiss()
            }
            Button {
                onRemove()
                dismiss()
            } label: {
                Text("Remove card").font(.geist(14, .medium)).foregroundStyle(Theme.planPink).frame(maxWidth: .infinity)
            }
            .buttonStyle(.plain)
        }
        .padding(.horizontal, 20).padding(.top, 24).padding(.bottom, 8)
        .onGeometryChange(for: CGFloat.self) { $0.size.height } action: { height = $0 }
        .onAppear {
            qty = item.qty
            if let c = item.cost { paid = String(format: "%.2f", c) }
            if let m = item.market { market = String(format: "%.2f", m) }
            if let p = item.price { mode = .fixed; value = String(format: "%.2f", p) }
            else { value = "\(Int((item.rate(side: rate) * 100).rounded()))" }
        }
        .presentationDetents([.height(height)])
        .glassSheet()
    }

    /// Switching keeps the same price: the % becomes its dollar figure, and back.
    private func switchMode(_ m: Mode) {
        guard m != mode else { return }
        let u = unit
        mode = m
        if m == .fixed { value = u.map { String(format: "%.2f", $0) } ?? "" }
        else if let u, let mk = marketValue, mk > 0 { value = "\(Int((u / mk * 100).rounded()))" }
    }
}

// MARK: - Another rate

/// The ⋯ beside the rate chips: type any rate. Only cards without their own price follow it.
struct DealRateSheet: View {
    var title: String
    var rate: Double
    var onApply: (Double) -> Void
    @Environment(\.dismiss) private var dismiss
    @State private var value = ""
    @State private var height: CGFloat = 300

    var body: some View {
        VStack(alignment: .leading, spacing: 16) {
            // The line sits right under the title (the round close makes the header tall).
            VStack(alignment: .leading, spacing: 0) {
                SheetHeader(title: title) { dismiss() }
                Text("Only cards without their own price will update.").font(.geist(13)).foregroundStyle(Theme.muted)
            }
            StepField(text: $value, step: 1, range: 30...150, suffix: "%", decimals: 0)
            SheetLimeButton(title: "Apply rate", enabled: Double(value).map { (30...150).contains($0) } ?? false) {
                if let v = Double(value) { onApply(v / 100) }
                dismiss()
            }
        }
        .padding(.horizontal, 20).padding(.top, 24).padding(.bottom, 8)
        .onGeometryChange(for: CGFloat.self) { $0.size.height } action: { height = $0 }
        .onAppear { value = "\(Int((rate * 100).rounded()))" }
        .presentationDetents([.height(height)])
        .glassSheet()
    }
}

// MARK: - A number with − and +

/// A big number you can type, with a round − on the left and + on the right to nudge it.
struct StepField: View {
    @Binding var text: String
    var step: Double
    var range: ClosedRange<Double>
    var prefix: String? = nil
    var suffix: String? = nil
    var decimals = 0

    var body: some View {
        HStack(spacing: 8) {
            nudge("minus", -step)
            Spacer(minLength: 0)
            HStack(spacing: 4) {
                if let prefix { Text(prefix).foregroundStyle(Theme.muted) }
                TextField("0", text: $text).keyboardType(decimals == 0 ? .numberPad : .decimalPad)
                    .multilineTextAlignment(.center).fixedSize()
                if let suffix { Text(suffix).foregroundStyle(Theme.muted) }
            }
            .font(.display(34)).monospacedDigit()
            Spacer(minLength: 0)
            nudge("plus", step)
        }
        .padding(.horizontal, 12)
        .frame(maxWidth: .infinity).frame(height: 70)
        .sheetPanel(radius: 16)
    }

    private func nudge(_ icon: String, _ by: Double) -> some View {
        let current = MoneyField.value(text) ?? 0
        let next = min(range.upperBound, max(range.lowerBound, (by > 0 ? floor(current / step) * step + step : ceil(current / step) * step - step)))
        return Button {
            Haptics.tap()
            text = decimals == 0 ? "\(Int(next.rounded()))" : String(format: "%.\(decimals)f", next)
        } label: {
            Image(systemName: icon).font(.system(size: 16, weight: .semibold)).foregroundStyle(.white)
                .frame(width: 44, height: 44)
                .background(Circle().fill(Color.white.opacity(0.08)))
                .contentShape(Circle())
        }
        .buttonStyle(.plain)
        .disabled(next == current)
        .opacity(next == current ? 0.4 : 1)
        .accessibilityLabel(by > 0 ? "Up \(Int(step))" : "Down \(Int(step))")
    }
}


// MARK: - What the deal is made of

/// The deal's numbers, only the ones that apply: what you get at market, what you pay or receive,
/// the trade-in value (what you get is worth at market minus what you give for it), what you
/// paid for what you sell and the sale profit, and how far ahead it leaves you. Each has an ⓘ.
struct DealBreakdown: View {
    var kind: DealKind
    var totals: DealTotals
    /// What the cards you get are worth at market.
    var getMarket: Double
    /// What you paid for the cards you sell (nil when one has no cost yet).
    var basis: Double?
    var selling: Bool

    /// How far ahead the deal leaves you: trade-in value plus sale profit (nil while a card you
    /// sell has no cost).
    static func ahead(_ t: DealTotals, basis: Double?, selling: Bool) -> Double? {
        let gained = t.inValue > 0 ? t.equity : 0
        if !selling { return gained }
        guard let basis else { return nil }
        return gained + (t.outValue - basis)
    }

    static func verdict(_ ahead: Double?) -> String {
        guard let ahead else { return "Add what you paid to see where you land" }
        if abs(ahead) < 0.005 { return "You break even" }
        return ahead > 0 ? "You make \(Format.money(ahead)) profit" : "You take a \(Format.money(-ahead)) loss"
    }

    /// Two figures side by side, like the old balance card's details: what explains the answer.
    /// Buying: what it's worth and the trade-in value. Selling: what you paid and the sale profit.
    /// Trading: the trade-in value and the sale profit (they add up to the answer).
    var body: some View {
        let t = totals
        let profit = basis.map { t.outValue - $0 }
        let gained = t.inValue > 0 ? t.equity : nil
        HStack(spacing: 8) {
            switch kind {
            case .buy:
                GlassStat(label: "Market value", value: Format.money(getMarket))
                // How far under market you're buying: what you'd make reselling at market.
                GlassStat(label: "Potential profit", value: gained.map { Format.signedMoney($0) } ?? "—", tint: gained.map { Theme.tone($0) } ?? .white)
            case .sell:
                GlassStat(label: "You paid", value: basis.map { Format.money($0) } ?? "—")
                GlassStat(label: "Sale profit", value: profit.map { Format.signedMoney($0) } ?? "—", tint: profit.map { Theme.tone($0) } ?? .white)
            default:
                GlassStat(label: "Trade-in value", value: gained.map { Format.signedMoney($0) } ?? "—", tint: gained.map { Theme.tone($0) } ?? .white)
                GlassStat(label: "Sale profit", value: selling ? (profit.map { Format.signedMoney($0) } ?? "Add cost") : "—", tint: profit.map { Theme.tone($0) } ?? .white)
            }
        }
    }
}

/// A small ⓘ that shows one line of explanation in a popover.
struct InfoDot: View {
    var text: String
    @State private var open = false

    var body: some View {
        Button { open = true } label: {
            Image(systemName: "info.circle").font(.system(size: 11, weight: .medium)).foregroundStyle(Theme.subtle)
                .frame(width: 22, height: 22).contentShape(Rectangle())
        }
        .buttonStyle(.plain)
        .popover(isPresented: $open) {
            Text(text).font(.geist(14)).foregroundStyle(.white)
                .fixedSize(horizontal: false, vertical: true)
                .padding(14).frame(width: 260, alignment: .leading)
                .presentationCompactAdaptation(.popover)
                .presentationBackground(Theme.surface2)
        }
    }
}
