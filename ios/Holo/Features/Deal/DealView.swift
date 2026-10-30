import SwiftUI

/// Deal maker for card shows: what comes in and what goes out, each at a share of market,
/// with your profit on what you hand over and the cash to settle. Closing records it all.
struct DealView: View {
    @Environment(CollectionStore.self) private var store
    @Environment(DealStore.self) private var deals
    @State private var picking: DealSide?
    @State private var scanning: DealSide?
    @State private var settings = false
    @State private var history = false
    @State private var confirming = false
    @State private var closing = false
    @State private var message: String?

    private var rates: (in: Double, out: Double) { deals.rates }
    private var totals: DealTotals { DealTotals(deals.deal, rates: rates, cost: { deals.cost(of: $0, in: store) }) }
    private var unpriced: Bool {
        deals.deal.incoming.contains { $0.unitPrice(side: rates.in) == nil } || deals.deal.outgoing.contains { $0.unitPrice(side: rates.out) == nil }
    }

    var body: some View {
        NavigationStack {
            List {
                Section { PageHeader(title: "Deal", subtitle: "Buys, sells and trades at the table") }
                    .listRowBackground(Color.clear)
                    .listRowInsets(EdgeInsets(top: 8, leading: 0, bottom: 4, trailing: 0))
                Section { BalanceCard(totals: totals) }
                    .listRowBackground(Color.clear)
                    .listRowInsets(EdgeInsets(top: 0, leading: 0, bottom: 0, trailing: 0))

                side(.incoming)
                side(.outgoing)

                if let message {
                    Text(message).font(.callout).foregroundStyle(Theme.muted).listRowBackground(Color.clear)
                }
            }
            .scrollContentBackground(.hidden)
            .background(Theme.background)
            .navigationBarTitleDisplayMode(.inline)
            .toolbar {
                ToolbarItem(placement: .topBarLeading) {
                    Button { history = true } label: { Image(systemName: "clock.arrow.circlepath") }.accessibilityLabel("Closed deals")
                }
                ToolbarItem(placement: .topBarTrailing) {
                    Menu {
                        Button { settings = true } label: { Label("Default rates", systemImage: "slider.horizontal.3") }
                        Button(role: .destructive) { deals.update { $0 = DealState() } } label: { Label("Clear deal", systemImage: "trash") }
                            .disabled(deals.deal.kind == .empty)
                    } label: { Image(systemName: "ellipsis.circle") }
                }
            }
            .safeAreaInset(edge: .bottom) {
                if deals.deal.kind != .empty {
                    Button { confirming = true } label: {
                        Text(closing ? "Recording…" : (unpriced ? "Price every item to close" : "Close \(deals.deal.kind.noun.lowercased())"))
                    }
                    .buttonStyle(LimeButtonStyle())
                    .disabled(unpriced || closing)
                    .padding(.horizontal, 16)
                    .padding(.bottom, 8)
                }
            }
            .confirmationDialog(confirmTitle, isPresented: $confirming, titleVisibility: .visible) {
                Button("Close \(deals.deal.kind.noun.lowercased())") { Task { await close() } }
            } message: {
                Text("Sales and purchases are added to your collection.")
            }
            .sheet(item: $picking) { side in DealPickerSheet(side: side) }
            .sheet(isPresented: $settings) { DealRatesSheet() }
            .sheet(isPresented: $history) { DealHistorySheet() }
            .fullScreenCover(item: $scanning) { side in
                ScanView(dealSide: side, onPick: { candidate, read in addScan(candidate, read: read, to: side) })
            }
        }
    }

    private var confirmTitle: String {
        let b = totals.balance
        if abs(b) < 0.005 { return "Even trade" }
        return b > 0 ? "Customer pays you \(Format.money(b))" : "You pay the customer \(Format.money(-b))"
    }

    @ViewBuilder private func side(_ side: DealSide) -> some View {
        let incoming = side == .incoming
        let items = incoming ? deals.deal.incoming : deals.deal.outgoing
        let rate = incoming ? rates.in : rates.out
        Section {
            RateRow(rate: rate, isDefault: (incoming ? deals.deal.rateIn : deals.deal.rateOut) == nil) { r in
                deals.update { d in if incoming { d.rateIn = r } else { d.rateOut = r } }
            }
            ForEach(items) { item in
                DealItemRow(item: item, rate: rate, cost: incoming ? nil : deals.cost(of: item, in: store)) { changed in
                    deals.update { d in
                        if incoming {
                            if let i = d.incoming.firstIndex(where: { $0.key == item.key }) { d.incoming[i] = changed }
                        } else {
                            if let i = d.outgoing.firstIndex(where: { $0.key == item.key }) { d.outgoing[i] = changed }
                        }
                    }
                }
                .swipeActions {
                    Button("Remove", role: .destructive) {
                        deals.update { d in
                            if incoming { d.incoming.removeAll { $0.key == item.key } } else { d.outgoing.removeAll { $0.key == item.key } }
                        }
                    }
                }
            }
            HStack(spacing: 10) {
                Button { picking = side } label: { Label(incoming ? "Add" : "From inventory", systemImage: "plus").frame(maxWidth: .infinity, minHeight: 40) }
                    .buttonStyle(.bordered)
                Button { scanning = side } label: { Label("Scan", systemImage: "viewfinder").frame(maxWidth: .infinity, minHeight: 40) }
                    .buttonStyle(.bordered)
            }
            .tint(.white)
            .listRowBackground(Color.clear)
        } header: {
            HStack(alignment: .lastTextBaseline) {
                Image(systemName: incoming ? "arrow.down.left" : "arrow.up.right").font(.system(size: 15, weight: .bold)).foregroundStyle(Theme.lime)
                Text(incoming ? "COMING IN" : "GOING OUT").font(.display(26)).foregroundStyle(.white)
                Spacer()
                Text(Format.money(incoming ? totals.inValue : totals.outValue)).font(.display(26)).monospacedDigit().foregroundStyle(.white)
            }
            .textCase(nil)
            .padding(.top, 10)
        } footer: {
            Text(incoming ? "What the customer hands you." : "What you hand over, from your inventory.")
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

/// Who pays whom, and what you make.
private struct BalanceCard: View {
    var totals: DealTotals

    var body: some View {
        let b = totals.balance
        VStack(alignment: .leading, spacing: 10) {
            SkewTag(text: totals.kind == .empty ? "New deal" : totals.kind.label, color: .white, textColor: Theme.ink)
            MonoLabel(text: totals.kind == .empty ? "Add items to start" : (abs(b) < 0.005 ? "Even" : (b > 0 ? "Customer pays you" : "You pay the customer")))
                .padding(.top, 8)
            Text(Format.money(abs(b)))
                .font(.display(60)).monospacedDigit()
            HStack(spacing: 18) {
                metric("Coming in", Format.money(totals.inValue), .primary)
                metric("Going out", Format.money(totals.outValue), .primary)
            }
            HStack(spacing: 18) {
                metric("Profit on sale", totals.profit.map { Format.signedMoney($0) } ?? "—", Theme.tone(totals.profit))
                metric("Equity taken in", totals.kind == .empty || totals.inValue == 0 ? "—" : Format.signedMoney(totals.equity), Theme.tone(totals.equity))
            }
            if totals.belowCost > 0 {
                Label("\(totals.belowCost) going out below what you paid", systemImage: "exclamationmark.triangle.fill")
                    .font(.caption).foregroundStyle(Theme.warn)
            }
        }
        .padding(4)
        .tinted(Theme.lime, radius: 24)
    }

    private func metric(_ label: String, _ value: String, _ tint: Color) -> some View {
        VStack(alignment: .leading, spacing: 4) {
            MonoLabel(text: label)
            Text(value).font(.geist(19, .semibold)).monospacedDigit().foregroundStyle(tint)
        }
        .frame(maxWidth: .infinity, alignment: .leading)
    }
}

/// The side's share of market, adjustable for this deal.
private struct RateRow: View {
    var rate: Double
    var isDefault: Bool
    var onChange: (Double?) -> Void

    var body: some View {
        VStack(alignment: .leading, spacing: 4) {
            HStack {
                Text("At \(Int((rate * 100).rounded()))% of market").font(.subheadline.weight(.medium)).monospacedDigit()
                Spacer()
                if !isDefault {
                    Button("Reset") { onChange(nil) }.font(.footnote).buttonStyle(.borderless)
                }
            }
            Slider(value: Binding(get: { rate }, set: { onChange(($0 * 100).rounded() / 100) }), in: 0.3...1.5, step: 0.01)
        }
    }
}

/// One item: quantity, the price it goes at (typed, or market × rate), and your cost when going out.
private struct DealItemRow: View {
    var item: DealItem
    var rate: Double
    var cost: Double?
    var onChange: (DealItem) -> Void
    @State private var priceText = ""
    @FocusState private var focused: Bool

    var body: some View {
        let unit = item.unitPrice(side: rate)
        VStack(alignment: .leading, spacing: 8) {
            HStack(spacing: 10) {
                ProductImage(product: item.product, cornerRadius: 4).frame(width: 34, height: 48)
                VStack(alignment: .leading, spacing: 2) {
                    Text(item.product.name).font(.subheadline.weight(.medium)).lineLimit(1)
                    Text(subtitle).font(.caption).foregroundStyle(Theme.muted).lineLimit(1)
                }
                Spacer()
                Text(Format.money(item.total(side: rate))).font(.subheadline.weight(.semibold)).monospacedDigit()
            }
            HStack(spacing: 10) {
                Stepper(value: Binding(get: { item.qty }, set: { var c = item; c.qty = $0; onChange(c) }), in: 1...(item.maxQty ?? 999)) {
                    Text("×\(item.qty)").font(.footnote.weight(.medium)).monospacedDigit()
                }
                .fixedSize()
                Spacer()
                TextField(unit.map { Format.money($0) } ?? "Price", text: $priceText)
                    .keyboardType(.decimalPad)
                    .multilineTextAlignment(.trailing)
                    .monospacedDigit()
                    .focused($focused)
                    .frame(width: 96)
                    .padding(.horizontal, 8)
                    .frame(height: 32)
                    .background(Theme.surface2, in: RoundedRectangle(cornerRadius: 8))
                    .onChange(of: priceText) { _, text in
                        var c = item
                        c.price = MoneyField.value(text)
                        onChange(c)
                    }
                Text("each").font(.caption).foregroundStyle(Theme.muted)
            }
            if let cost {
                let profit = item.total(side: rate) - cost
                HStack(spacing: 4) {
                    Text("Cost \(Format.money(cost)) ·").foregroundStyle(Theme.muted)
                    Text(Format.signedMoney(profit)).foregroundStyle(Theme.tone(profit))
                }
                .font(.caption).monospacedDigit()
            }
        }
        .padding(.vertical, 4)
        .onAppear { if let p = item.price { priceText = String(format: "%.2f", p) } }
    }

    private var subtitle: String {
        [item.grade.map { "\($0.company) \($0.grade)" }, item.product.setName, item.market.map { "Market \(Format.money($0))" }]
            .compactMap { $0 }.joined(separator: " · ")
    }
}
