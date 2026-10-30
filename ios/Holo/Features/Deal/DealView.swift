import SwiftUI

/// Deal maker for card shows, laid out like the website: today's deals, the balance (who pays
/// whom, profit and equity), then what comes in and what goes out, each at a share of market
/// you can drag, with a pinned bar to close. Closing records it all.
struct DealView: View {
    @Environment(CollectionStore.self) private var store
    @Environment(DealStore.self) private var deals
    @State private var picking: DealSide?
    @State private var scanning: DealSide?
    @State private var settings = false
    @State private var history = false
    @State private var customer = false
    @State private var confirming = false
    @State private var closing = false
    @State private var ebayItem: DealItem?
    @State private var message: String?

    private var rates: (in: Double, out: Double) { deals.rates }
    private var defaultRates: (in: Double, out: Double) {
        var d = deals.deal
        d.rateIn = nil
        d.rateOut = nil
        return d.rates(deals.defaults)
    }

    private var totals: DealTotals { DealTotals(deals.deal, rates: rates, cost: { deals.cost(of: $0, in: store) }) }
    private var unpriced: Bool {
        deals.deal.incoming.contains { $0.unitPrice(side: rates.in) == nil } || deals.deal.outgoing.contains { $0.unitPrice(side: rates.out) == nil }
    }

    private var todays: [DealRecord] {
        deals.log.filter { Calendar.current.isDateInToday($0.date) }
    }

    var body: some View {
        NavigationStack {
            ScrollView {
                VStack(alignment: .leading, spacing: 32) {
                    VStack(alignment: .leading, spacing: 14) {
                        if !todays.isEmpty { TodayStrip(deals: todays) { history = true } }
                        BalanceCard(totals: totals)
                        if let message {
                            Text(message).font(.geist(13)).foregroundStyle(Theme.muted)
                        }
                    }
                    side(.incoming).reveal()
                    side(.outgoing).reveal()
                }
                .padding(.horizontal, 16)
                .padding(.top, 8)
                .padding(.bottom, 24)
                .background(alignment: .top) { DealBackdrop() }
            }
            .scrollDismissesKeyboard(.interactively)
            .background(Theme.background)
            .replaysAnimations()
            .navigationBarTitleDisplayMode(.inline)
            .pageTitle("Deal")
            .toolbar {
                ToolbarItem(placement: .topBarLeading) {
                    Button { history = true } label: { Image(systemName: "clock.arrow.circlepath") }.accessibilityLabel("Closed deals")
                }
                ToolbarItemGroup(placement: .topBarTrailing) {
                    Button { customer = true } label: { Image(systemName: "eye") }
                        .accessibilityLabel("Customer view")
                        .disabled(deals.deal.kind == .empty)
                    Button { settings = true } label: { Image(systemName: "slider.horizontal.3") }.accessibilityLabel("Default rates")
                }
            }
            .safeAreaInset(edge: .bottom) {
                if deals.deal.kind != .empty { closeBar }
            }
            .tabBarClearance()
            .confirmationDialog(confirmTitle, isPresented: $confirming, titleVisibility: .visible) {
                Button("Close \(deals.deal.kind.noun.lowercased())") { Task { await close() } }
            } message: {
                Text("Sales and purchases are added to your collection.")
            }
            .sheet(item: $picking) { side in DealPickerSheet(side: side) }
            .sheet(isPresented: $settings) { DealRatesSheet() }
            .sheet(isPresented: $history) { DealHistorySheet() }
            .sheet(isPresented: $customer) { CustomerViewSheet(deal: deals.deal, rates: rates, totals: totals) }
            .sheet(item: $ebayItem) { item in
                NavigationStack {
                    ScrollView {
                        EbaySalesPanel(productId: item.product.id, printing: item.printing, grade: item.grade.map { "\($0.company) \($0.grade)" })
                            .padding(16)
                    }
                    .background(Theme.background)
                    .navigationTitle(item.product.name)
                    .navigationBarTitleDisplayMode(.inline)
                }
                .presentationDetents([.medium, .large])
            }
            .fullScreenCover(item: $scanning) { side in
                ScanView(dealSide: side, onPick: { candidate, read in addScan(candidate, read: read, to: side) })
            }
        }
    }

    // MARK: Close bar

    private var closeBar: some View {
        HStack(spacing: 8) {
            Button("Clear") {
                withAnimation(.snappy) { deals.update { $0 = DealState() } }
            }
            .buttonStyle(Button3D(kind: .dark, fullWidth: false, height: 48))
            Button { confirming = true } label: {
                Text(closing ? "Recording…" : (unpriced ? "Price every item to close" : "Close \(deals.deal.kind.noun.lowercased())"))
                    .frame(maxWidth: .infinity)
            }
            .buttonStyle(Button3D(kind: .lime, fullWidth: true, height: 48))
            .disabled(unpriced || closing)
            .opacity(unpriced ? 0.55 : 1)
        }
        .padding(8)
        .liquidGlass(in: RoundedRectangle(cornerRadius: 22, style: .continuous))
        .padding(.horizontal, 16)
        .padding(.bottom, 8)
    }

    private var confirmTitle: String {
        let b = totals.balance
        if abs(b) < 0.005 { return "Even trade" }
        return b > 0 ? "Customer pays you \(Format.money(b))" : "You pay the customer \(Format.money(-b))"
    }

    // MARK: A side of the deal

    @ViewBuilder private func side(_ side: DealSide) -> some View {
        let incoming = side == .incoming
        let items = incoming ? deals.deal.incoming : deals.deal.outgoing
        let rate = incoming ? rates.in : rates.out
        let fallback = incoming ? defaultRates.in : defaultRates.out
        VStack(alignment: .leading, spacing: 12) {
            HStack(alignment: .lastTextBaseline) {
                VStack(alignment: .leading, spacing: 6) {
                    HStack(spacing: 8) {
                        Image(systemName: incoming ? "arrow.down.left" : "arrow.up.right")
                            .font(.system(size: 16, weight: .bold))
                            .foregroundStyle(incoming ? Theme.lime : Theme.planPink)
                        Text(incoming ? "COMING IN" : "GOING OUT").font(.display(24)).displayTrim(24)
                    }
                    Text(incoming ? "What the customer hands you" : "What you hand over").font(.geist(12)).foregroundStyle(Theme.muted)
                }
                Spacer(minLength: 8)
                Text(Format.money(incoming ? totals.inValue : totals.outValue))
                    .font(.display(26)).monospacedDigit().displayTrim(26)
                    .contentTransition(.numericText())
                    .animation(.snappy, value: incoming ? totals.inValue : totals.outValue)
            }

            RateCard(rate: rate, fallback: fallback) { r in
                deals.update { d in if incoming { d.rateIn = r } else { d.rateOut = r } }
            }

            ForEach(items) { item in
                DealItemCard(item: item, rate: rate, cost: incoming ? nil : deals.cost(of: item, in: store),
                             onEbay: { ebayItem = item },
                             onRemove: {
                                 withAnimation(.snappy) {
                                     deals.update { d in
                                         if incoming { d.incoming.removeAll { $0.key == item.key } } else { d.outgoing.removeAll { $0.key == item.key } }
                                     }
                                 }
                             }) { changed in
                    deals.update { d in
                        if incoming {
                            if let i = d.incoming.firstIndex(where: { $0.key == item.key }) { d.incoming[i] = changed }
                        } else {
                            if let i = d.outgoing.firstIndex(where: { $0.key == item.key }) { d.outgoing[i] = changed }
                        }
                    }
                }
                .transition(.opacity.combined(with: .move(edge: .top)))
            }

            HStack(spacing: 8) {
                Button { picking = side } label: {
                    Label(incoming ? "Add what's coming in" : "Add from inventory", systemImage: "plus")
                        .frame(maxWidth: .infinity)
                }
                .buttonStyle(Button3D(kind: .dark, fullWidth: true, height: 46))
                Button { scanning = side } label: { Label("Scan", systemImage: "viewfinder") }
                    .buttonStyle(Button3D(kind: .dark, fullWidth: false, height: 46))
                    .accessibilityLabel(incoming ? "Scan what's coming in" : "Scan what's going out")
            }
        }
    }

    /// A scanned card: anything can come in; going out, it has to be something you hold.
    @MainActor
    private func addScan(_ c: ScanCandidate, read: ScanRead?, to side: DealSide) -> (ok: Bool, note: String) {
        let grade = read?.kind == "slab" ? read?.grade : nil
        let sameGrade: (HoldingIdentity) -> Bool = { $0.gradeCompany == grade?.company && $0.grade == grade?.grade }
        if side == .incoming {
            if let h = store.holdings.first(where: { $0.identity.productId == c.product.id && $0.identity.printing == c.printing && sameGrade($0.identity) }), let p = h.product {
                deals.add(DealItem(key: "h:\(h.identity.key)", product: p, printing: h.identity.printing, market: h.price ?? c.market, holdingKey: h.identity.key), to: .incoming)
            } else {
                let gradeLabel = grade.map { "\($0.company) \($0.grade)" } ?? ""
                deals.add(DealItem(key: "p:\(c.product.id):\(c.printing ?? ""):\(gradeLabel)", product: c.product, printing: c.printing, market: c.value(for: read), grade: grade), to: .incoming)
            }
            return (true, "Added to coming in")
        }
        let owned = store.holdings.filter { $0.identity.productId == c.product.id }
        guard let h = owned.first(where: { $0.identity.printing == c.printing && sameGrade($0.identity) }) ?? owned.first, let p = h.product else {
            return (false, "Not in your inventory")
        }
        deals.add(DealItem(key: "h:\(h.identity.key)", product: p, printing: h.identity.printing, market: h.price, holdingKey: h.identity.key, maxQty: Int(h.quantity)), to: .outgoing)
        return (true, "Added to going out")
    }

    private func close() async {
        closing = true
        defer { closing = false }
        do {
            let kind = deals.deal.kind
            let t = try await deals.close(using: store)
            UINotificationFeedbackGenerator().notificationOccurred(.success)
            message = "\(kind.noun) recorded" + (t.profit.map { " · profit \(Format.signedMoney($0))" } ?? "")
        } catch {
            message = "Couldn't record the deal: \(error.localizedDescription)"
        }
    }
}

extension DealSide: Identifiable {
    var id: String { rawValue }
}

/// The lit grid and soft glows behind the top of the page, like the other tabs.
private struct DealBackdrop: View {
    var body: some View {
        ZStack {
            GridPattern(step: 36, opacity: 0.05)
            RadialGradient(colors: [Theme.lime.opacity(0.18), .clear], center: UnitPoint(x: 0.2, y: 0.3), startRadius: 0, endRadius: 260)
            RadialGradient(colors: [Theme.planBlue.opacity(0.18), .clear], center: UnitPoint(x: 0.9, y: 0.5), startRadius: 0, endRadius: 240)
        }
        .frame(height: 520)
        .mask(LinearGradient(stops: [.init(color: .black, location: 0), .init(color: .black, location: 0.6), .init(color: .clear, location: 1)],
                             startPoint: .top, endPoint: .bottom))
        .padding(.top, -160)
        .allowsHitTesting(false)
    }
}

/// "TODAY  3 deals  Cash +$120  Profit +$48  See all": today's closed deals at a glance.
private struct TodayStrip: View {
    var deals: [DealRecord]
    var onOpen: () -> Void

    var body: some View {
        let cash = deals.reduce(0) { $0 + $1.balance }
        let profit = deals.reduce(0) { $0 + ($1.profit ?? 0) }
        Button(action: onOpen) {
            HStack(spacing: 12) {
                MonoLabel(text: "Today")
                Text("\(deals.count) deal\(deals.count == 1 ? "" : "s")").foregroundStyle(.white)
                HStack(spacing: 4) {
                    Text("Cash").foregroundStyle(Theme.muted)
                    Text(Format.signedMoney(cash)).foregroundStyle(Theme.tone(cash))
                }
                HStack(spacing: 4) {
                    Text("Profit").foregroundStyle(Theme.muted)
                    Text(Format.signedMoney(profit)).foregroundStyle(Theme.tone(profit))
                }
                Spacer(minLength: 0)
                Image(systemName: "chevron.right").font(.system(size: 11, weight: .bold)).foregroundStyle(Theme.subtle)
            }
            .font(.geist(13, .semibold)).monospacedDigit().lineLimit(1).minimumScaleFactor(0.8)
            .padding(.horizontal, 14)
            .frame(height: 40)
            .liquidGlass(in: Capsule())
        }
        .buttonStyle(.plain)
    }
}

/// Who pays whom, and what you make. The card goes pink when the deal loses money.
private struct BalanceCard: View {
    var totals: DealTotals

    var body: some View {
        let b = totals.balance
        let empty = totals.kind == .empty
        let losing = (totals.profit ?? 0) < -0.005
        let tint = losing ? Theme.planPink : Theme.lime
        VStack(alignment: .leading, spacing: 0) {
            HStack {
                SkewTag(text: empty ? "New deal" : totals.kind.label, color: .white, textColor: Theme.ink)
                Spacer()
                if totals.belowCost > 0 {
                    Label("\(totals.belowCost) below cost", systemImage: "exclamationmark.triangle.fill")
                        .font(.geist(12, .semibold)).foregroundStyle(Theme.planPink)
                }
            }
            MonoLabel(text: empty ? "Add items to start" : (abs(b) < 0.005 ? "Settled" : (b > 0 ? "Customer pays you" : "You pay the customer")))
                .padding(.top, 18)
            CountingText(value: abs(b), format: { Format.money($0) })
                .font(.display(60)).monospacedDigit().lineLimit(1).minimumScaleFactor(0.5)
                .displayTrim(60)
                .padding(.top, 10)
            LazyVGrid(columns: [GridItem(.flexible(), spacing: 12), GridItem(.flexible(), spacing: 12)], alignment: .leading, spacing: 14) {
                stat("Coming in", Format.money(totals.inValue), .white)
                stat("Going out", Format.money(totals.outValue), .white)
                stat("Profit on sale", totals.profit.map { Format.signedMoney($0) } ?? "—", totals.profit == nil ? Theme.muted : Theme.tone(totals.profit))
                stat("Equity taken in", totals.kind == .sell || empty ? "—" : Format.signedMoney(totals.equity),
                     totals.kind == .sell || empty ? Theme.muted : Theme.tone(totals.equity))
            }
            .padding(.top, 20)
        }
        .padding(4)
        .tinted(tint, radius: 24)
        .animation(.easeInOut(duration: 0.3), value: losing)
    }

    private func stat(_ label: String, _ value: String, _ tint: Color) -> some View {
        VStack(alignment: .leading, spacing: 5) {
            MonoLabel(text: label)
            Text(value).font(.geist(17, .semibold)).monospacedDigit().foregroundStyle(tint).lineLimit(1).minimumScaleFactor(0.7)
        }
        .frame(maxWidth: .infinity, alignment: .leading)
    }
}

/// The side's share of market, adjustable for this deal (the counter-offer slider).
private struct RateCard: View {
    var rate: Double
    var fallback: Double
    var onChange: (Double?) -> Void

    var body: some View {
        VStack(alignment: .leading, spacing: 10) {
            HStack(alignment: .firstTextBaseline) {
                Text("At ").foregroundColor(Theme.muted) + Text("\(Int((rate * 100).rounded()))%").foregroundColor(.white) + Text(" of market").foregroundColor(Theme.muted)
                Spacer()
                if abs(rate - fallback) > 0.0001 {
                    Button("Reset to \(Int((fallback * 100).rounded()))%") { onChange(nil) }
                        .font(.geist(12, .medium)).foregroundStyle(Theme.muted)
                        .buttonStyle(.plain)
                }
            }
            .font(.geist(14, .medium)).monospacedDigit()
            Slider(value: Binding(get: { rate }, set: { onChange(($0 * 100).rounded() / 100) }), in: 0.4...1.2, step: 0.01)
                .tint(Theme.lime)
                .sensoryFeedback(.selection, trigger: Int((rate * 20).rounded()))
        }
        .padding(14)
        .background(RoundedRectangle(cornerRadius: 18, style: .continuous).fill(Theme.surface))
        .overlay(RoundedRectangle(cornerRadius: 18, style: .continuous).strokeBorder(Theme.border))
    }
}

/// One item: its picture, name, market and eBay link, then quantity, its own % of market or a
/// typed price, and for items going out what you have in it and the profit.
private struct DealItemCard: View {
    var item: DealItem
    var rate: Double
    var cost: Double?
    var onEbay: () -> Void
    var onRemove: () -> Void
    var onChange: (DealItem) -> Void
    @State private var priceText = ""
    @State private var rateText = ""

    var body: some View {
        let unit = item.unitPrice(side: rate)
        let total = item.total(side: rate)
        HStack(alignment: .top, spacing: 12) {
            HoldingArt(product: item.product, identity: nil, cornerRadius: 10, caption: false)
                .frame(width: 52, height: 72)
            VStack(alignment: .leading, spacing: 0) {
                HStack(alignment: .top, spacing: 8) {
                    Text(item.product.name).font(.geist(14, .medium)).foregroundStyle(.white).lineLimit(2)
                    Spacer(minLength: 0)
                    Button(action: onRemove) {
                        Image(systemName: "trash").font(.system(size: 13, weight: .medium)).foregroundStyle(Theme.subtle)
                            .frame(width: 28, height: 28)
                    }
                    .buttonStyle(.plain)
                    .accessibilityLabel("Remove \(item.product.name)")
                }
                HStack(spacing: 4) {
                    Text(subtitle).foregroundStyle(Theme.muted)
                    if item.product.source == "tcgapi" || item.product.source == "sample" {
                        Text("·").foregroundStyle(Theme.muted)
                        Button("eBay sold", action: onEbay).foregroundStyle(.white.opacity(0.85)).buttonStyle(.plain)
                    }
                }
                .font(.geist(12)).monospacedDigit().lineLimit(1)
                .padding(.top, 2)

                HStack(spacing: 6) {
                    stepper
                    percentField
                    priceField(placeholder: unit.map { String(format: "%.2f", $0) } ?? "Price")
                    if item.price != nil || item.rate != nil {
                        Button("Use \(Int((rate * 100).rounded()))%") {
                            priceText = ""
                            rateText = ""
                            var c = item
                            c.price = nil
                            c.rate = nil
                            onChange(c)
                        }
                        .font(.geist(11, .medium)).foregroundStyle(Theme.muted).buttonStyle(.plain).fixedSize()
                    }
                    Spacer(minLength: 0)
                }
                .padding(.top, 10)

                HStack(spacing: 6) {
                    if let cost {
                        let profit = total - cost
                        Text("In it \(Format.money(cost)) ·").foregroundStyle(Theme.muted)
                        Text(Format.signedMoney(profit)).foregroundStyle(Theme.tone(profit))
                        if profit < -0.005 { SkewTag(text: "Below cost", color: Theme.planPink, textColor: .white) }
                    }
                    Spacer(minLength: 0)
                    Text(Format.money(total)).font(.geist(15, .semibold)).foregroundStyle(.white)
                }
                .font(.geist(12)).monospacedDigit()
                .padding(.top, 10)
            }
        }
        .padding(12)
        .background(RoundedRectangle(cornerRadius: 18, style: .continuous).fill(Theme.surface))
        .overlay(RoundedRectangle(cornerRadius: 18, style: .continuous).strokeBorder(Theme.border))
        .onAppear {
            if let p = item.price { priceText = String(format: "%.2f", p) }
            if let r = item.rate { rateText = "\(Int((r * 100).rounded()))" }
        }
    }

    private var subtitle: String {
        [item.market.map { "Market \(Format.money($0))" } ?? "No market price", item.grade.map { "\($0.company) \($0.grade)" }]
            .compactMap { $0 }.joined(separator: " · ")
    }

    private var stepper: some View {
        HStack(spacing: 0) {
            qtyButton("minus", enabled: item.qty > 1) { change { $0.qty -= 1 } }
            Text("\(item.qty)").font(.geist(13, .semibold)).monospacedDigit().frame(minWidth: 18)
            qtyButton("plus", enabled: item.qty < (item.maxQty ?? 999)) { change { $0.qty += 1 } }
        }
        .frame(height: 30)
        .background(Capsule().fill(Theme.surface2))
    }

    private func qtyButton(_ icon: String, enabled: Bool, action: @escaping () -> Void) -> some View {
        Button(action: action) {
            Image(systemName: icon).font(.system(size: 10, weight: .bold)).frame(width: 28, height: 30)
        }
        .buttonStyle(.plain)
        .foregroundStyle(enabled ? Color.white : Theme.subtle)
        .disabled(!enabled)
    }

    /// This item's own rate: overrides the slider for just this row. Typing one clears the price.
    private var percentField: some View {
        let on = item.rate != nil
        return HStack(spacing: 1) {
            TextField(item.price != nil || item.market == nil ? "—" : "\(Int((item.rate(side: rate) * 100).rounded()))", text: $rateText)
                .keyboardType(.numberPad)
                .multilineTextAlignment(.trailing)
                .frame(width: 30)
                .onChange(of: rateText) { _, text in
                    let digits = String(text.filter(\.isNumber).prefix(3))
                    if digits != text { rateText = digits; return }
                    guard digits.isEmpty ? item.rate != nil : Double(digits).map({ $0 / 100 }) != item.rate else { return }
                    priceText = ""
                    change { c in
                        c.rate = digits.isEmpty ? nil : Double(digits).map { $0 / 100 }
                        c.price = nil
                    }
                }
            Text("%").foregroundStyle(Theme.subtle)
        }
        .font(.geist(13)).monospacedDigit()
        .padding(.horizontal, 9)
        .frame(height: 30)
        .background(Capsule().fill(on ? Theme.surface3 : Theme.surface2))
        .overlay(Capsule().strokeBorder(on ? Theme.lime.opacity(0.6) : .clear))
        .disabled(item.market == nil)
        .opacity(item.market == nil ? 0.4 : 1)
    }

    private func priceField(placeholder: String) -> some View {
        let on = item.price != nil
        return HStack(spacing: 2) {
            Text("$").foregroundStyle(Theme.subtle)
            TextField(placeholder, text: $priceText)
                .keyboardType(.decimalPad)
                .frame(width: 58)
                .onChange(of: priceText) { _, text in
                    let value = MoneyField.value(text)
                    guard value != item.price else { return }
                    rateText = ""
                    change { c in
                        c.price = value
                        c.rate = nil
                    }
                }
            Text("each").font(.geist(11)).foregroundStyle(Theme.subtle)
        }
        .font(.geist(13)).monospacedDigit()
        .padding(.horizontal, 9)
        .frame(height: 30)
        .background(Capsule().fill(on ? Theme.surface3 : Theme.surface2))
        .overlay(Capsule().strokeBorder(on ? Theme.lime.opacity(0.6) : .clear))
    }

    private func change(_ edit: (inout DealItem) -> Void) {
        var c = item
        edit(&c)
        onChange(c)
    }
}

/// What the customer sees: items and prices, no market, costs or margins.
private struct CustomerViewSheet: View {
    var deal: DealState
    var rates: (in: Double, out: Double)
    var totals: DealTotals
    @Environment(\.dismiss) private var dismiss

    var body: some View {
        NavigationStack {
            ScrollView {
                VStack(alignment: .leading, spacing: 22) {
                    if !deal.incoming.isEmpty { list("You're bringing", deal.incoming, rates.in) }
                    if !deal.outgoing.isEmpty { list("You're taking home", deal.outgoing, rates.out) }
                    let even = abs(totals.balance) < 0.005
                    VStack(spacing: 8) {
                        MonoLabel(text: even ? "Straight swap" : (totals.balance > 0 ? "You pay" : "We pay you"))
                        Text(Format.money(abs(totals.balance))).font(.display(56)).monospacedDigit().displayTrim(56)
                    }
                    .frame(maxWidth: .infinity)
                    .padding(.vertical, 24)
                    .background(RoundedRectangle(cornerRadius: 22, style: .continuous).fill(Theme.surface))
                }
                .padding(16)
            }
            .background(Theme.background)
            .navigationTitle("Your deal")
            .navigationBarTitleDisplayMode(.inline)
            .toolbar { ToolbarItem(placement: .confirmationAction) { Button("Done") { dismiss() } } }
        }
    }

    private func list(_ title: String, _ items: [DealItem], _ rate: Double) -> some View {
        VStack(alignment: .leading, spacing: 10) {
            MonoLabel(text: title)
            ForEach(items) { i in
                HStack(spacing: 12) {
                    HoldingArt(product: i.product, identity: nil, cornerRadius: 8, caption: false).frame(width: 40, height: 56)
                    (Text(i.product.name) + Text(i.qty > 1 ? " × \(i.qty)" : "").foregroundColor(Theme.muted))
                        .font(.geist(15, .medium))
                    Spacer(minLength: 8)
                    Text(Format.money(i.total(side: rate))).font(.geist(16, .semibold)).monospacedDigit()
                }
            }
        }
    }
}
