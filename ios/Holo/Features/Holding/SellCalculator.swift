import SwiftUI

/// "What if I sell?", like the website: what you'd keep after marketplace fees and shipping,
/// the profit against what you paid (oldest copies first), the break-even price on each
/// marketplace, and a button to record the sale with those exact numbers.
struct SellCalculatorSheet: View {
    var holding: HoldingView
    @Environment(\.dismiss) private var dismiss
    @Environment(CollectionStore.self) private var store
    @State private var platform = Sell.Platform.ebay
    @State private var quantity = 1
    @State private var price = ""
    @State private var percent = ""
    @State private var fixed = ""
    @State private var shipCharged = ""
    @State private var shipCost = ""
    @State private var editFees = false
    @State private var saving = false
    @State private var error: String?

    private var unitPrice: Double? { MoneyField.value(price) }
    private var fees: Sell.Fees { Sell.Fees(percent: Double(percent) ?? 0, fixed: MoneyField.value(fixed) ?? 0) }
    private var charged: Double { platform == .local ? 0 : MoneyField.value(shipCharged) ?? 0 }
    private var cost: Double { platform == .local ? 0 : MoneyField.value(shipCost) ?? 0 }
    private var estimate: Sell.Estimate {
        Sell.estimate(lots: holding.lots, quantity: Double(quantity), unitPrice: unitPrice ?? 0, fees: fees, shippingCharged: charged, shippingCost: cost)
    }

    var body: some View {
        let e = estimate
        NavigationStack {
            ScrollView {
                VStack(alignment: .leading, spacing: 22) {
                    Text("\(holding.product?.name ?? "Item") · \(Int(holding.quantity)) owned · market \(Format.money(holding.price))")
                        .font(.geist(14)).foregroundStyle(Theme.muted)
                    breakEvens
                    ChipPicker(options: Sell.Platform.allCases.map { ($0, $0.label) }, selection: Binding(get: { platform }, set: { apply($0) }))
                    inputs
                    result(e)
                    if let error { Text(error).font(.geist(13)).foregroundStyle(Theme.down) }
                }
                .padding(.horizontal, 20)
                .padding(.top, 8)
                .padding(.bottom, 24)
            }
            .scrollDismissesKeyboard(.immediately)
            .background(Theme.background)
            .navigationTitle("What if I sell?")
            .navigationBarTitleDisplayMode(.inline)
            .toolbar {
                ToolbarItem(placement: .cancellationAction) { Button("Close") { dismiss() } }
            }
            .safeAreaInset(edge: .bottom) {
                Button(saving ? "Recording…" : "Record this sale") { Task { await record(e) } }
                    .buttonStyle(Button3D(kind: .light))
                    .disabled(unitPrice == nil || saving)
                    .padding(.horizontal, 20)
                    .padding(.vertical, 12)
                    .background(Theme.background)
            }
        }
        .onAppear {
            if price.isEmpty, let p = holding.price { price = String(format: "%.2f", p) }
            apply(.ebay)
        }
    }

    private func apply(_ p: Sell.Platform) {
        platform = p
        percent = p.fees.percent.formatted(.number.precision(.fractionLength(0...2)))
        fixed = String(format: "%.2f", p.fees.fixed)
        editFees = p == .custom
    }

    // MARK: Break-even on each marketplace

    private var breakEvens: some View {
        VStack(alignment: .leading, spacing: 8) {
            MonoLabel(text: quantity > 1 ? "Sell for at least this to break even · each, for \(quantity)" : "Sell for at least this to break even")
            HStack(spacing: 8) {
                ForEach([Sell.Platform.ebay, .tcgplayer, .local]) { p in
                    let f = p == platform ? fees : p.fees
                    let local = p == .local
                    let be = Sell.estimate(lots: holding.lots, quantity: Double(quantity), unitPrice: 0, fees: f,
                                           shippingCharged: local ? 0 : charged, shippingCost: local ? 0 : cost).breakEven
                    let gap = be.flatMap { b in holding.price.map { $0 - b } }
                    Button { apply(p) } label: {
                        VStack(alignment: .leading, spacing: 4) {
                            Text(p.label).font(.geist(12, .medium)).foregroundStyle(Theme.muted)
                            Text(be.map { Format.money($0) } ?? "—").font(.geist(20, .semibold)).monospacedDigit()
                                .lineLimit(1).minimumScaleFactor(0.6)
                            if let gap {
                                (Text(Format.signedMoney(gap)).foregroundColor(Theme.tone(gap)) + Text(" mkt").foregroundColor(Theme.muted))
                                    .font(.geist(11)).monospacedDigit().lineLimit(1).minimumScaleFactor(0.8)
                            }
                        }
                        .padding(.horizontal, 10).padding(.vertical, 12)
                        .frame(maxWidth: .infinity, alignment: .leading)
                        .background(p == platform ? Theme.surface3 : Theme.surface2, in: RoundedRectangle(cornerRadius: 14, style: .continuous))
                        .overlay(RoundedRectangle(cornerRadius: 14, style: .continuous).strokeBorder(p == platform ? Theme.lime : .clear, lineWidth: 2))
                    }
                    .buttonStyle(.plain)
                }
            }
            Text("Each, after fees and shipping. The small number is how far the market price is above it.")
                .font(.geist(11)).foregroundStyle(Theme.subtle)
        }
    }

    // MARK: Inputs

    private var inputs: some View {
        VStack(alignment: .leading, spacing: 14) {
            HStack(alignment: .top, spacing: 12) {
                field("Quantity", hint: "of \(Int(holding.quantity))") {
                    HStack {
                        Button { quantity = max(1, quantity - 1) } label: { Image(systemName: "minus") }
                            .disabled(quantity <= 1)
                        Spacer()
                        Text("\(quantity)").font(.geist(16, .medium)).monospacedDigit()
                        Spacer()
                        Button { quantity = min(Int(holding.quantity), quantity + 1) } label: { Image(systemName: "plus") }
                            .disabled(quantity >= Int(holding.quantity))
                    }
                    .foregroundStyle(.white)
                    .padding(.horizontal, 14)
                    .frame(height: 46)
                    .background(box)
                }
                field("Sale price each", hint: nil) { money($price) }
            }
            if platform != .local {
                HStack(alignment: .top, spacing: 12) {
                    field("Buyer pays", hint: "shipping") { money($shipCharged) }
                    field("You pay", hint: "shipping") { money($shipCost) }
                }
                if editFees {
                    HStack(alignment: .top, spacing: 12) {
                        field("Fee %", hint: nil) {
                            HStack {
                                TextField("0", text: $percent).keyboardType(.decimalPad).font(.geist(16)).monospacedDigit()
                                Text("%").foregroundStyle(Theme.subtle)
                            }
                            .padding(.horizontal, 14).frame(height: 46).background(box)
                        }
                        field("Per-order fee", hint: nil) { money($fixed) }
                    }
                } else {
                    (Text("Fees: \(percent)% + \(Format.money(fees.fixed)) per order · \(platform.note). ") + Text("Edit").foregroundColor(.white).fontWeight(.medium))
                        .font(.geist(12)).foregroundStyle(Theme.subtle)
                        .onTapGesture { editFees = true }
                }
            }
        }
    }

    private var box: some View {
        RoundedRectangle(cornerRadius: 12, style: .continuous).fill(Theme.surface2)
            .overlay(RoundedRectangle(cornerRadius: 12, style: .continuous).strokeBorder(Theme.border))
    }

    private func money(_ text: Binding<String>) -> some View {
        HStack(spacing: 4) {
            Text("$").foregroundStyle(Theme.subtle)
            TextField("0.00", text: text).keyboardType(.decimalPad).font(.geist(16)).monospacedDigit()
        }
        .padding(.horizontal, 14).frame(height: 46).background(box)
    }

    private func field<Content: View>(_ label: String, hint: String?, @ViewBuilder content: () -> Content) -> some View {
        VStack(alignment: .leading, spacing: 6) {
            HStack {
                Text(label).font(.geist(13, .medium)).foregroundStyle(Theme.muted).lineLimit(1)
                Spacer(minLength: 4)
                if let hint { Text(hint).font(.geist(12)).foregroundStyle(Theme.subtle).lineLimit(1) }
            }
            content()
        }
        .frame(maxWidth: .infinity)
    }

    // MARK: Result

    private func result(_ e: Sell.Estimate) -> some View {
        let ready = unitPrice != nil
        return VStack(alignment: .leading, spacing: 0) {
            Text("You'd make").font(.geist(12, .medium)).foregroundStyle(Theme.muted)
            HStack(alignment: .firstTextBaseline, spacing: 8) {
                Text(ready ? Format.signedMoney(e.profit) : "—").font(.display(40)).monospacedDigit()
                    .foregroundStyle(ready ? Theme.tone(e.profit) : Theme.subtle).displayTrim(40)
                if ready, let pct = e.profitPct {
                    Text(Format.signedPercent(pct)).font(.geist(15, .semibold)).monospacedDigit().foregroundStyle(Theme.tone(e.profit))
                }
            }
            .padding(.top, 10)
            VStack(spacing: 7) {
                line("Sale (\(Int(e.quantity)) × \(Format.money(unitPrice ?? 0)))", Format.money(e.gross))
                if charged > 0 { line("Shipping buyer pays", "+" + Format.money(charged)) }
                if e.platformFees > 0 { line(platform == .custom ? "Fees" : "\(platform.label) fees", "−" + Format.money(e.platformFees)) }
                if cost > 0 { line("Your shipping cost", "−" + Format.money(cost)) }
                line("You receive", Format.money(e.net), strong: true)
                line("Cost basis (oldest copies first)", "−" + Format.money(e.costBasis))
                Rectangle().fill(Theme.border).frame(height: 1)
                HStack {
                    Text("Profit").font(.geist(14, .semibold))
                    Spacer()
                    Text(ready ? Format.signedMoney(e.profit) : "—").font(.geist(14, .semibold)).monospacedDigit().foregroundStyle(Theme.tone(e.profit))
                }
            }
            .padding(.top, 16)
        }
        .padding(16)
        .frame(maxWidth: .infinity, alignment: .leading)
        .background(Theme.surface2, in: RoundedRectangle(cornerRadius: 16, style: .continuous))
    }

    private func line(_ label: String, _ value: String, strong: Bool = false) -> some View {
        HStack {
            Text(label).lineLimit(1)
            Spacer(minLength: 8)
            Text(value).monospacedDigit()
        }
        .font(.geist(13, strong ? .medium : .regular))
        .foregroundStyle(strong ? .white : Theme.muted)
    }

    // MARK: Record

    private func record(_ e: Sell.Estimate) async {
        guard let unitPrice, e.quantity > 0 else { return }
        saving = true
        error = nil
        defer { saving = false }
        // Stored so the recorded proceeds equal the estimate: shipping charged is income,
        // shipping paid is a cost.
        let shipNet = charged - cost
        do {
            try await store.sell(
                holding.identity, quantity: e.quantity,
                unitPrice: shipNet > 0 ? unitPrice + shipNet / e.quantity : unitPrice,
                fees: (e.platformFees * 100).rounded() / 100,
                shipping: shipNet < 0 ? (-shipNet * 100).rounded() / 100 : 0,
                date: Format.day(), source: platform.label, notes: "Sold via \(platform.label)"
            )
            UINotificationFeedbackGenerator().notificationOccurred(.success)
            dismiss()
        } catch {
            self.error = error.localizedDescription
        }
    }
}
