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
                            Button {
                                Haptics.tap()
                                withAnimation(.snappy) { deals.resume(entry) }
                            } label: {
                                DealListRow(kind: entry.state.kind, title: entry.name,
                                            line: "\(DealView.pathTitle(entry.state.kind)) · \(cards(entry.state.incoming.count + entry.state.outgoing.count))",
                                            amount: abs(t.balance), note: "Parked", divider: i > 0)
                            }
                            .buttonStyle(.plain)
                        }
                    }
                }
                if !deals.log.isEmpty {
                    list("Recent deals", count: nil, onAll: onHistory) {
                        ForEach(Array(deals.log.prefix(3).enumerated()), id: \.element.id) { i, r in
                            Button { onRecord(r) } label: {
                                DealListRow(kind: r.kind, title: title(r),
                                            line: "\(DealView.pathTitle(r.kind)) · \(cards(r.items)) · \(when(r))",
                                            amount: abs(r.balance), note: r.kind == .trade ? "Cash difference" : "Completed", divider: i > 0)
                            }
                            .buttonStyle(.plain)
                        }
                    }
                }
            }
            .padding(.horizontal, 16).padding(.top, 8).padding(.bottom, 40)
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
                Text(note).font(.geist(11)).foregroundStyle(Theme.subtle)
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
    var onReview: () -> Void
    var onPark: () -> Void
    @Environment(DealStore.self) private var deals
    @Environment(CollectionStore.self) private var store
    @State private var tradeSide = DealSide.incoming

    private var side: DealSide { path == .buy ? .incoming : path == .sell ? .outgoing : tradeSide }

    var body: some View {
        let rates = deals.rates
        let totals = DealTotals(deals.deal.settled(rates: rates), rates: rates, cost: { deals.cost(of: $0, in: store) })
        let items = side == .incoming ? deals.deal.incoming : deals.deal.outgoing
        let rate = side == .incoming ? rates.in : rates.out
        let count = deals.deal.incoming.count + deals.deal.outgoing.count
        ScrollView {
            VStack(alignment: .leading, spacing: 18) {
                // Title, and the deal's name (tap the pencil to name it).
                HStack(alignment: .top) {
                    VStack(alignment: .leading, spacing: 4) {
                        DisplayText(text: path == .buy ? "New purchase" : path == .sell ? "New sale" : "New trade", size: 30)
                        Text("\(name.isEmpty ? "Untitled deal" : name) · \(count) card\(count == 1 ? "" : "s")")
                            .font(.geist(14)).foregroundStyle(Theme.muted)
                    }
                    Spacer()
                    Button(action: onRename) {
                        Image(systemName: "pencil").font(.system(size: 16, weight: .medium)).foregroundStyle(.white)
                            .frame(width: 40, height: 40).contentShape(Rectangle())
                    }
                    .buttonStyle(.plain)
                    .accessibilityLabel("Name this deal")
                }
                if path == .trade {
                    ChipPicker(options: [(DealSide.incoming, "I receive · \(Format.money(totals.inValue))"),
                                         (.outgoing, "I give · \(Format.money(totals.outValue))")],
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
        let title = path == .buy ? "Buying rate" : path == .sell ? "Selling rate" : (side == .incoming ? "Receiving rate" : "Giving rate")
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
                        Text("\(v)%").font(.geist(13, .semibold)).monospacedDigit()
                            .foregroundStyle(v == pct ? Theme.ink : .white)
                            .frame(maxWidth: .infinity).frame(height: 36)
                            .background(RoundedRectangle(cornerRadius: 10, style: .continuous).fill(v == pct ? Color.white : Color.white.opacity(0.07)))
                    }
                    .buttonStyle(.plain)
                }
                Button { onCustomRate(side) } label: {
                    Image(systemName: "ellipsis").font(.system(size: 13, weight: .semibold)).foregroundStyle(.white)
                        .frame(maxWidth: .infinity).frame(height: 36)
                        .background(RoundedRectangle(cornerRadius: 10, style: .continuous).fill(Color.white.opacity(0.07)))
                }
                .buttonStyle(.plain)
                .accessibilityLabel("Another rate")
            }
        }
        .padding(14)
        .background(RoundedRectangle(cornerRadius: 18, style: .continuous).fill(Theme.surface))
        .overlay(RoundedRectangle(cornerRadius: 18, style: .continuous).strokeBorder(Theme.border))
    }

    private func setRate(_ r: Double) {
        deals.update { d in if side == .incoming { d.rateIn = r } else { d.rateOut = r } }
    }

    // MARK: Cards

    @ViewBuilder private func cardsList(_ items: [DealItem], rate: Double) -> some View {
        let market = items.reduce(0.0) { $0 + ($1.market ?? 0) * Double($1.qty) }
        VStack(alignment: .leading, spacing: 4) {
            HStack(alignment: .firstTextBaseline) {
                Text(path == .trade ? (side == .incoming ? "I receive" : "I give") : "Cards").font(.display(20)).tracking(-0.5)
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
        let pct: Int? = { guard let unit, let m = item.market, m > 0 else { return nil }; return Int((unit / m * 100).rounded()) }()
        return HStack(alignment: .center, spacing: 12) {
            HoldingArt(product: item.product, cornerRadius: 3, caption: false).frame(width: 40, height: 56)
            VStack(alignment: .leading, spacing: 2) {
                Text(ActionsSheet.shortName(item.product)).font(.geist(15, .medium)).foregroundStyle(.white).lineLimit(1)
                Text([item.product.setName, item.product.number].compactMap { $0 }.joined(separator: " · "))
                    .font(.geist(12)).foregroundStyle(Theme.muted).lineLimit(1)
                Text((item.qty > 1 ? "×\(item.qty) · " : "") + (item.market.map { "\(Format.money($0)) market" } ?? "No market price"))
                    .font(.geist(12)).monospacedDigit().foregroundStyle(Theme.subtle).lineLimit(1)
            }
            Spacer(minLength: 8)
            VStack(alignment: .trailing, spacing: 4) {
                Text(total.map { Format.money($0) } ?? "Set price").font(.geist(15, .semibold)).monospacedDigit()
                    .foregroundStyle(total == nil ? Theme.lime : .white)
                if let pct {
                    HStack(spacing: 2) {
                        Text("\(pct)%")
                        if item.price != nil || item.rate != nil { Image(systemName: "pencil").font(.system(size: 8, weight: .bold)) }
                    }
                    .font(.geist(11, .semibold)).monospacedDigit().foregroundStyle(.white.opacity(0.8))
                    .padding(.horizontal, 7).frame(height: 20)
                    .background(Capsule().fill(Color.white.opacity(0.08)))
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
            case .buy: return "Total I pay"
            case .sell: return "Total I receive"
            default: return abs(b) < 0.005 ? "Even trade" : (b > 0 ? "I receive cash" : "I pay the difference")
            }
        }()
        let empty = deals.deal.kind == .empty
        return VStack(alignment: .leading, spacing: 6) {
            if path == .trade {
                line("I receive", Format.money(t.inValue))
                line("I give", Format.money(t.outValue))
            } else {
                line("Market value", Format.money(market))
            }
            Text(label).font(.geist(13)).foregroundStyle(Theme.muted).padding(.top, 4)
            HStack(alignment: .center, spacing: 10) {
                Text(Format.money(abs(b))).font(.display(32)).tracking(-1).monospacedDigit().foregroundStyle(.white)
                    .contentTransition(.numericText())
                    .animation(.snappy, value: b)
                    .lineLimit(1).minimumScaleFactor(0.6)
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
        .padding(.horizontal, 16).padding(.top, 14).padding(.bottom, 10)
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
    @Environment(\.dismiss) private var dismiss
    enum Mode: Hashable { case percent, fixed }
    @State private var mode = Mode.percent
    @State private var value = ""
    @State private var market = ""
    @State private var qty = 1
    @State private var height: CGFloat = 520

    private var marketValue: Double? { MoneyField.value(market) ?? item.market }
    private var unit: Double? {
        guard let v = MoneyField.value(value) else { return nil }
        if mode == .fixed { return v }
        return marketValue.map { $0 * v / 100 }
    }

    var body: some View {
        VStack(alignment: .leading, spacing: 16) {
            HStack(alignment: .top) {
                VStack(alignment: .leading, spacing: 2) {
                    Text(ActionsSheet.shortName(item.product)).font(.geist(18, .semibold)).foregroundStyle(.white).lineLimit(1)
                    Text([item.product.setName, item.product.number].compactMap { $0 }.joined(separator: " · ")).font(.geist(13)).foregroundStyle(Theme.muted)
                }
                Spacer()
                SheetHeader(title: "") { dismiss() }.fixedSize()
            }
            ChipPicker(options: [(Mode.percent, "Percentage"), (.fixed, "Fixed price")],
                       selection: Binding(get: { mode }, set: { switchMode($0) }), fills: true)
            VStack(spacing: 6) {
                Text(mode == .percent ? "Agreed rate" : "Agreed price per card").font(.geist(13)).foregroundStyle(Theme.muted)
                HStack(spacing: 4) {
                    if mode == .fixed { Text("$").foregroundStyle(Theme.muted) }
                    TextField("0", text: $value).keyboardType(.decimalPad).multilineTextAlignment(.center).fixedSize()
                    if mode == .percent { Text("%").foregroundStyle(Theme.muted) }
                }
                .font(.display(34)).monospacedDigit()
                .frame(maxWidth: .infinity).frame(height: 70)
                .sheetPanel(radius: 16)
            }
            HStack {
                Text("Agreed price per card").font(.geist(14)).foregroundStyle(Theme.muted)
                Spacer()
                Text(unit.map { Format.money($0) } ?? "—").font(.geist(15, .semibold)).monospacedDigit().foregroundStyle(.white)
            }
            SheetPanel {
                SheetMoneyRow(title: "Market price", text: $market)
                SheetDivider()
                HStack {
                    Text("Quantity").font(.geist(16)).foregroundStyle(.white)
                    Spacer()
                    Text("\(qty)").font(.geist(16)).monospacedDigit().foregroundStyle(Theme.muted)
                    Stepper("", value: $qty, in: 1...max(1, item.maxQty ?? 999)).labelsHidden().fixedSize()
                }
                .frame(minHeight: 50)
            }
            if item.price != nil || item.rate != nil {
                Button {
                    var c = item
                    c.price = nil
                    c.rate = nil
                    c.qty = qty
                    if let m = MoneyField.value(market) { c.market = m }
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
                if let m = MoneyField.value(market) { c.market = m }
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
            SheetHeader(title: title) { dismiss() }
            Text("Only cards without their own price will update.").font(.geist(13)).foregroundStyle(Theme.muted)
            HStack(spacing: 4) {
                TextField("0", text: $value).keyboardType(.numberPad).multilineTextAlignment(.center).fixedSize()
                Text("%").foregroundStyle(Theme.muted)
            }
            .font(.display(34)).monospacedDigit()
            .frame(maxWidth: .infinity).frame(height: 70)
            .sheetPanel(radius: 16)
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
