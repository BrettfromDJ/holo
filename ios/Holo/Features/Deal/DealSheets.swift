import SwiftUI

/// Pick what's coming in or going out: from your inventory, anything in the catalog (going out,
/// that's something you have that isn't in Holo yet), or a custom line with just a name and price.
struct DealPickerSheet: View {
    var side: DealSide
    /// Scan into this side instead (the page closes this sheet and opens the scanner).
    var onScan: (() -> Void)? = nil
    @Environment(\.dismiss) private var dismiss
    @Environment(CollectionStore.self) private var store
    @Environment(DealStore.self) private var deals
    @State private var query = ""
    @State private var results: [SearchHit] = []
    @State private var searching = false
    @State private var added: Set<String> = []
    @State private var customOpen = false
    @State private var searchedFor = ""
    @FocusState private var focused: Bool

    private var owned: [HoldingView] {
        let q = query.trimmingCharacters(in: .whitespaces).lowercased()
        let all = store.allHoldings.filter { $0.product != nil }
        guard !q.isEmpty else { return Array(all.prefix(40)) }
        return all.filter { h in
            let p = h.product!
            return p.name.lowercased().contains(q) || (p.setName ?? "").lowercased().contains(q) || (p.number ?? "").lowercased().contains(q)
        }
    }

    var body: some View { sheetBody.presentationDetents([.fraction(0.93)]).glassSheet() }

    @ViewBuilder private var sheetBody: some View {
        // Filtered once per keystroke, not once per use (going out only).
        let owned = side == .outgoing ? self.owned : []
        NavigationStack {
            // Plain rows straight on the sheet (no panel behind the results; the owner's call).
            List { Group {
                // Coming in is the customer's cards, so only going out lists your inventory.
                if side == .outgoing {
                Section("Your collection") {
                    if owned.isEmpty { Text("Nothing matches.").foregroundStyle(Theme.muted) }
                    ForEach(owned) { h in
                        Button { addHolding(h) } label: {
                            HStack {
                                MiniRow(holding: h, trailing: Format.money(h.price), tint: .primary)
                                if side == .outgoing { Text("×\(Int(h.quantity))").font(.caption).foregroundStyle(Theme.muted) }
                                if added.contains(h.id) { Image(systemName: "checkmark").foregroundStyle(Theme.lime) }
                            }
                        }
                        .buttonStyle(.plain)
                    }
                }
                }
                if query.count >= 2 {
                    Section {
                        if searching && results.isEmpty { ProgressView() }
                        if !searching && results.isEmpty && searchedFor == query.trimmingCharacters(in: .whitespaces) {
                            // Not in the stored catalog: look live only when asked (a paid TCG API call).
                            Button {
                                Task {
                                    let q = query.trimmingCharacters(in: .whitespaces)
                                    searching = true
                                    results = (try? await Backend.shared.api.liveSearch(q)) ?? []
                                    searching = false
                                }
                            } label: { Label("Not found. Search the live catalog", systemImage: "bolt.fill") }
                        }
                        ForEach(results) { hit in
                            Button { addHit(hit) } label: {
                                HStack(spacing: 12) {
                                    SearchRow(hit: hit)
                                    // A plus to add, a lime check once it's on the deal.
                                    Image(systemName: added.contains(hit.id) ? "checkmark.circle.fill" : "plus.circle")
                                        .font(.system(size: 22))
                                        .foregroundStyle(added.contains(hit.id) ? Theme.lime : Color.white.opacity(0.35))
                                }
                            }
                            .buttonStyle(.plain)
                        }
                    } header: {
                        Text(side == .incoming ? "Catalog" : "Not in Corodex")
                    } footer: {
                        if side == .outgoing {
                            Text("Something you have that isn't in your collection yet. Add what you paid on the deal and it's recorded properly; otherwise it's counted in the deal but not\u{00A0}tracked.")
                                .font(.geist(13)).foregroundStyle(Theme.muted)
                        }
                    }
                }
                // Not in the catalog (a lot, a binder, an odd one): a name and a price.
                if side == .outgoing || query.count >= 2 {
                    Section {
                        customRow
                    }
                }
            }
            .listRowBackground(Color.clear)
            .listRowSeparatorTint(Color.white.opacity(0.08))
            }
            .foregroundStyle(.white)
            .overlay {
                // Coming in, before you type: what to do, and the custom way in.
                if side == .incoming && query.count < 2 {
                    VStack(spacing: 10) {
                        Image(systemName: "magnifyingglass").font(.system(size: 20, weight: .semibold)).foregroundStyle(.white)
                            .frame(width: 56, height: 56).liquidGlass(in: Circle())
                        Text("Find their cards").font(.display(22)).tracking(-0.5)
                        Text("Search by name, set or number, or scan with the camera.").font(.geist(14)).foregroundStyle(Theme.muted)
                            .multilineTextAlignment(.center)
                        Button { customOpen = true } label: {
                            Label("Add a custom item or lot", systemImage: "square.and.pencil")
                                .font(.geist(14, .medium)).foregroundStyle(.white)
                                .padding(.horizontal, 16).frame(height: 40)
                                .liquidGlass(in: Capsule())
                        }
                        .buttonStyle(.plain)
                        .padding(.top, 8)
                    }
                    .padding(.horizontal, 32)
                    .padding(.bottom, 120)
                }
            }
            .scrollContentBackground(.hidden)
            // The first list sits just under the search bar.
            .contentMargins(.top, 0, for: .scrollContent)
            // Thumbnails, decoded off the main thread (a sheet doesn't get the Deal page's setting).
            .imageMaxPixel(360)
            .safeAreaInset(edge: .top, spacing: 0) {
                // The title and Done in the sheet (no bar), then the search across the full width.
                VStack(spacing: 14) {
                    SheetHeader(title: side == .incoming ? "Add cards" : "Add from your collection") { dismiss() }
                    HoloSearchField(text: $query, prompt: side == .incoming ? "Search any card or product" : "Search your collection or any card",
                                    focus: $focused, loading: searching, scan: onScan.map { SearchScan(action: $0) })
                }
                .padding(.horizontal, 16)
                .padding(.top, 22)
                .padding(.bottom, 8)
                // Results scroll on up behind the title and search, blurred (frosted, darkened with
                // the sheet's colour), fading out at the bottom edge so there's no hard cut.
                .background {
                    ZStack {
                        Rectangle().fill(.ultraThinMaterial)
                        Theme.sheet.opacity(0.55)
                    }
                    .environment(\.colorScheme, .dark)
                    .mask(LinearGradient(stops: [.init(color: .black, location: 0), .init(color: .black, location: 0.78),
                                                 .init(color: .clear, location: 1)], startPoint: .top, endPoint: .bottom))
                    .padding(.bottom, -14)
                    .ignoresSafeArea(edges: .top)
                    .allowsHitTesting(false)
                }
            }
            .scrollDismissesKeyboard(.immediately)
            .toolbar(.hidden, for: .navigationBar)
            .task(id: query) { await search() }
            .task {
                // Ready to type the moment it opens.
                try? await Task.sleep(nanoseconds: 80_000_000)
                focused = true
            }
            .sheet(isPresented: $customOpen) {
                CustomItemSheet { name, price, qty in
                    let id = UUID().uuidString.lowercased()
                    let product = Product(id: "custom:\(id)", source: "custom", name: name, productType: "Custom", kind: "sealed")
                    deals.add(DealItem(key: "c:\(id)", product: product, printing: nil, market: nil, qty: qty, price: price, custom: true), to: side)
                    Haptics.tap()
                    dismiss()
                }
            }
        }
    }

    /// The custom way in, as a quiet row at the end of the list.
    private var customRow: some View {
        Button { customOpen = true } label: {
            HStack(spacing: 12) {
                Image(systemName: "square.and.pencil").font(.system(size: 15, weight: .semibold)).foregroundStyle(.white)
                    .frame(width: 36, height: 36).background(Circle().fill(Color.white.opacity(0.08)))
                VStack(alignment: .leading, spacing: 2) {
                    Text("Add a custom item or lot").font(.geist(15, .medium)).foregroundStyle(.white)
                    Text("Not in the catalog? A name and a price is enough.").font(.geist(12)).foregroundStyle(Theme.muted)
                }
                Spacer()
            }
            .contentShape(Rectangle())
        }
        .buttonStyle(.plain)
        .accessibilityHint("A name and a price, for things not in the catalog")
    }

    private func addHolding(_ h: HoldingView) {
        guard let p = h.product else { return }
        let item = DealItem(
            key: "h:\(h.identity.key)", product: p, printing: h.identity.printing, market: h.price,
            holdingKey: h.identity.key, maxQty: side == .outgoing ? Int(h.quantity) : nil
        )
        deals.add(item, to: side)
        added.insert(h.id)
        Haptics.tap()
    }

    private func addHit(_ hit: SearchHit) {
        deals.add(DealItem(key: "p:\(hit.product.id):\(hit.printing ?? ""):", product: hit.product, printing: hit.printing, market: hit.market), to: side)
        added.insert(hit.id)
        Haptics.tap()
    }

    private func search() async {
        let q = query.trimmingCharacters(in: .whitespaces)
        guard q.count >= 2 else {
            results = []
            return
        }
        try? await Task.sleep(nanoseconds: 350_000_000)
        guard !Task.isCancelled else { return }
        searching = true
        defer { searching = false }
        if let hits = try? await Backend.shared.api.search(q), !Task.isCancelled {
            results = hits
            searchedFor = q
        }
    }
}

/// A line that isn't in the catalog: a name, a price each and how many.
private struct CustomItemSheet: View {
    var onAdd: (String, Double, Int) -> Void
    @Environment(\.dismiss) private var dismiss
    @State private var name = ""
    @State private var price = ""
    @State private var qty = 1

    var body: some View { sheetBody.glassSheet() }

    @ViewBuilder private var sheetBody: some View {
        NavigationStack {
            GlassForm {
                Section {
                    TextField("What is it? (Bulk lot, binder of commons…)", text: $name)
                    MoneyField(title: "Price each", text: $price, hint: "0.00")
                    Stepper("Quantity: \(qty)", value: $qty, in: 1...999)
                } footer: {
                    Text("For things that aren't in the catalog. Counted in the deal, not tracked in your\u{00A0}collection.").font(.geist(13)).foregroundStyle(Theme.muted)
                }
            }
            .scrollContentBackground(.hidden)
            .navigationTitle("Custom item")
            .navigationBarTitleDisplayMode(.inline)
            .toolbar {
                ToolbarItem(placement: .cancellationAction) { Button("Cancel") { dismiss() } }
                ToolbarItem(placement: .confirmationAction) {
                    Button("Add") {
                        guard let value = MoneyField.value(price) else { return }
                        onAdd(name.trimmingCharacters(in: .whitespaces), value, qty)
                        dismiss()
                    }
                    .disabled(name.trimmingCharacters(in: .whitespaces).isEmpty || MoneyField.value(price) == nil)
                }
            }
        }
        .presentationDetents([.medium])
    }
}

/// The rates new deals start at.
struct DealRatesSheet: View {
    @Environment(\.dismiss) private var dismiss
    @Environment(DealStore.self) private var deals
    @State private var rates = DealRates()
    @State private var role = DealRole.vendor
    @State private var collector = CollectorRates()

    var body: some View {
        ScrollView {
            VStack(alignment: .leading, spacing: 26) {
                SheetHeader(title: "Deal settings") { dismiss() }
                group("You're dealing as") {
                    ChipPicker(options: DealRole.allCases.map { ($0, $0.title) }, selection: $role, fills: true)
                    note(role == .vendor
                        ? "Your own buy and sell rates, with your profit on every deal."
                        : "At a vendor's table: what they offer and charge, against market.")
                }
                group("Your collection") {
                    SheetPanel {
                        toggleRow("Add what comes in", "You can still switch any single card on the deal.",
                                  Binding(get: { rates.addsIncoming }, set: { rates.addIncoming = $0 }))
                        SheetDivider()
                        toggleRow("Ask what I paid", "For cards going out that aren't in your collection.",
                                  Binding(get: { rates.asksCost }, set: { rates.askCost = $0 }))
                    }
                }
                group("Round the cash up to") {
                    ChipPicker(options: DealRates.roundSteps.map { ($0, "$\(Int($0))") },
                               selection: Binding(get: { rates.step }, set: { rates.roundStep = $0 }), scrolls: true)
                }
                group(role == .vendor ? "Your rates" : "What to expect") {
                    SheetPanel {
                        if role == .vendor {
                            rate("Buying", "What you pay for cards", \.buy)
                            SheetDivider()
                            rate("Trade-in", "What you credit on trade", \.trade)
                            SheetDivider()
                            rate("Selling", "What you charge for yours", \.sell)
                        } else {
                            collectorRate("Cash offer", "What a vendor pays for yours", \.offer)
                            SheetDivider()
                            collectorRate("Trade-in credit", "What you get in trade credit", \.tradeOffer)
                            SheetDivider()
                            collectorRate("Their prices", "What a vendor charges", \.charge)
                        }
                    }
                    note("A share of market price. Each deal starts here, and you can change it on the deal.")
                }
            }
            .padding(.horizontal, 20).padding(.top, 24).padding(.bottom, 16)
        }
        .scrollIndicators(.hidden)
        // Save stays in reach at the bottom.
        .safeAreaInset(edge: .bottom, spacing: 0) {
            SheetLimeButton(title: "Save") {
                deals.setDefaults(rates)
                deals.role = role
                deals.collector = collector
                dismiss()
            }
            .padding(.horizontal, 20).padding(.top, 10).padding(.bottom, 8)
            .background(Theme.sheet)
        }
        .onAppear {
            rates = deals.defaults
            role = deals.role
            collector = deals.collector
        }
        .presentationDetents([.fraction(0.93)])
        .glassSheet()
    }

    /// A group's quiet mono label, then its content.
    private func group<C: View>(_ title: String, @ViewBuilder _ content: () -> C) -> some View {
        VStack(alignment: .leading, spacing: 10) {
            MonoLabel(text: title)
            content()
        }
    }

    private func note(_ text: String) -> some View {
        Text(text.noWidow).font(.geist(12)).foregroundStyle(Theme.muted).fixedSize(horizontal: false, vertical: true)
    }

    private func toggleRow(_ title: String, _ line: String, _ isOn: Binding<Bool>) -> some View {
        Toggle(isOn: isOn) {
            VStack(alignment: .leading, spacing: 2) {
                Text(title).font(.geist(15, .medium)).foregroundStyle(.white)
                Text(line.noWidow).font(.geist(12)).foregroundStyle(Theme.muted)
            }
        }
        .tint(Theme.lime)
        .padding(.vertical, 12)
    }

    /// A row's title and its one quiet line under it.
    private func rowLabel(_ title: String, _ note: String) -> some View {
        VStack(alignment: .leading, spacing: 3) {
            Text(title).font(.geist(16, .semibold)).foregroundStyle(.white)
            Text(note.noWidow).font(.geist(13)).foregroundStyle(Theme.muted)
        }
    }

    /// A rate: its name and line on the left, the percent big in lime, the slider under.
    private func rateRow(_ title: String, _ hint: String, value: Binding<Double>) -> some View {
        VStack(alignment: .leading, spacing: 12) {
            HStack(alignment: .firstTextBaseline, spacing: 12) {
                VStack(alignment: .leading, spacing: 2) {
                    Text(title).font(.geist(15, .medium)).foregroundStyle(.white)
                    Text(hint).font(.geist(12)).foregroundStyle(Theme.muted)
                }
                Spacer(minLength: 8)
                Text("\(Int((value.wrappedValue * 100).rounded()))%").font(.display(20)).tracking(-0.5).monospacedDigit().foregroundStyle(.white)
            }
            Slider(value: Binding(get: { value.wrappedValue }, set: { value.wrappedValue = ($0 * 100).rounded() / 100 }), in: 0.3...1.5, step: 0.01)
                .tint(Theme.lime)
        }
        .padding(.vertical, 12)
    }

    private func collectorRate(_ title: String, _ hint: String, _ key: WritableKeyPath<CollectorRates, Double>) -> some View {
        rateRow(title, hint, value: Binding(get: { collector[keyPath: key] }, set: { collector[keyPath: key] = $0 }))
    }

    private func rate(_ title: String, _ hint: String, _ key: WritableKeyPath<DealRates, Double>) -> some View {
        rateRow(title, hint, value: Binding(get: { rates[keyPath: key] }, set: { rates[keyPath: key] = $0 }))
    }
}

/// Before a deal closes: who pays whom in big numbers, what changes hands on each side, the
/// profit, and one lime button. Recording happens here, so a problem shows right on the sheet,
/// and it ends on a confirmation with what was recorded.
struct DealCloseSheet: View {
    @Environment(\.dismiss) private var dismiss
    @Environment(CollectionStore.self) private var store
    @Environment(DealStore.self) private var deals
    /// The deal as it was when the sheet opened (closing clears the live one).
    @State private var deal: DealState
    @State private var rates: (in: Double, out: Double)
    @State private var phase = Phase.review
    @State private var error: String?
    /// The totals as recorded (after closing, costs have moved on).
    @State private var recorded: DealTotals?
    /// The final amount: the cash at the cards' own prices, and what's typed or picked over it.
    @State private var original: Double = 0
    @State private var finalText = ""
    @FocusState private var editingFinal: Bool

    enum Phase { case review, recording, done }

    init() {
        _deal = State(initialValue: DealState())
        _rates = State(initialValue: (0, 0))
    }

    private var totals: DealTotals { DealTotals(deal, rates: rates, cost: { deals.cost(of: $0, in: store) }) }

    /// The deal at the cards' own prices (no agreed cash).
    private var plainTotals: DealTotals {
        var d = deals.deal
        d.agreedCash = nil
        return DealTotals(d, rates: deals.rates, cost: { deals.cost(of: $0, in: store) })
    }

    private var market: Double { (deals.deal.incoming + deals.deal.outgoing).reduce(0.0) { $0 + ($1.market ?? 0) * Double($1.qty) } }
    private var finalAmount: Double { MoneyField.value(finalText) ?? original }
    /// Round amounts around the total: the $5 below it, the $5 above, and the $5 after that.
    private var roundOptions: [Double] {
        let down = (original / 5).rounded(.down) * 5
        var up = (original / 5).rounded(.up) * 5
        if up == down { up += 5 }
        return [down, up, up + 5].filter { $0 > 0 }
    }

    /// Set (or clear) the agreed cash and redo the deal's prices to match.
    private func applyFinal(_ amount: Double?) {
        if let amount, abs(amount - original) > 0.004 {
            deals.setAgreedCash(signedAgreedCash(amount, totals: plainTotals))
        } else {
            deals.update { $0.agreedCash = nil }
        }
        withAnimation(.snappy) { deal = deals.deal.settled(rates: deals.rates) }
    }

    var body: some View { sheetBody.glassSheet() }

    @ViewBuilder private var sheetBody: some View {
        Group {
            if phase == .done {
                RecordedScreen(totals: recorded ?? totals, deal: deal, rates: rates, demo: store.demo != nil) { dismiss() }
            } else {
                reviewBody
            }
        }
        .presentationDetents([.large])
        .presentationDragIndicator(.hidden)
        .interactiveDismissDisabled(phase == .recording)
        .onAppear {
            // At the agreed cash, when there is one: the same prices the record will keep.
            deal = deals.deal.settled(rates: deals.rates)
            rates = deals.rates
            original = abs(plainTotals.balance)
            if deals.deal.agreedCash != nil { finalText = String(format: "%.2f", abs(totals.balance)) }
        }
    }

    @ViewBuilder private var reviewBody: some View {
        let t = totals
        let b = t.balance
        VStack(alignment: .leading, spacing: 0) {
            // The sheet's own pull handle is the only one (a drawn one doubled it).
            Color.clear.frame(height: 8)
            ScrollView {
                VStack(alignment: .leading, spacing: 22) {
                    Group {
                        VStack(alignment: .leading, spacing: 8) {
                            SkewTag(text: t.kind.label)
                            DisplayText(text: "Close this \(t.kind.noun.lowercased())?", size: 30)
                                .frame(maxWidth: .infinity, alignment: .leading)
                        }
                        // The final amount: type it, or tap a round one. It's what gets recorded.
                        VStack(alignment: .leading, spacing: 12) {
                            HStack {
                                MonoLabel(text: abs(b) < 0.005 && original < 0.005 ? "Even trade" : (plainTotals.balance > 0 ? "Final amount I receive" : "Final amount I pay"))
                                Spacer()
                                Text("Market \(Format.money(market))").font(.geist(12)).monospacedDigit().foregroundStyle(Theme.muted)
                            }
                            HStack(spacing: 4) {
                                Text("$").foregroundStyle(Theme.muted)
                                TextField(String(format: "%.2f", original), text: $finalText)
                                    .keyboardType(.decimalPad).focused($editingFinal)
                                    .onSubmit { applyFinal(MoneyField.value(finalText)) }
                                // Changed: Reset sits beside the amount (in the pencil's place).
                                if abs(finalAmount - original) > 0.004 {
                                    Button {
                                        finalText = ""
                                        applyFinal(nil)
                                    } label: {
                                        Text("Reset to original total").font(.geist(13, .medium)).foregroundStyle(Theme.lime)
                                            .lineLimit(1).fixedSize()
                                    }
                                    .buttonStyle(.plain)
                                } else {
                                    Image(systemName: "pencil").font(.system(size: 16, weight: .medium)).foregroundStyle(Theme.muted)
                                }
                            }
                            .font(.display(40)).tracking(-1.2).monospacedDigit()
                            .onChange(of: editingFinal) { _, on in if !on { applyFinal(MoneyField.value(finalText)) } }
                            HStack(spacing: 8) {
                                ForEach(roundOptions, id: \.self) { o in
                                    let on = abs(finalAmount - o) < 0.005
                                    Button {
                                        Haptics.tap()
                                        editingFinal = false
                                        finalText = String(format: "%.0f", o)
                                        applyFinal(o)
                                    } label: {
                                        Text(Format.moneyWhole(o)).font(.geist(15, .semibold)).monospacedDigit()
                                            .foregroundStyle(on ? Theme.ink : .white)
                                            .frame(maxWidth: .infinity).frame(height: 40)
                                            .background(RoundedRectangle(cornerRadius: 13, style: .continuous).fill(on ? Color.white : Color.white.opacity(0.08)))
                                    }
                                    .buttonStyle(.plain)
                                }
                            }
                            VStack(spacing: 6) {
                                finalLine("At the cards' prices", Format.money(original))
                                finalLine("Price adjustment", Format.signedMoney(finalAmount - original))
                                if deal.kind != .trade, market > 0 {
                                    finalLine("Effective market rate", String(format: "%.2f%%", finalAmount / market * 100))
                                }
                            }
                            .padding(.top, 2)
                        }
                        .padding(18)
                        .frame(maxWidth: .infinity, alignment: .leading)
                        .liquidGlass(in: RoundedRectangle(cornerRadius: 22, style: .continuous))
                        // Where you land, then what it's made of: the same breakdown as the deal page.
                        let costs = deal.outgoing.map { deals.cost(of: $0, in: store) }
                        let basis: Double? = deal.outgoing.isEmpty || costs.contains(where: { $0 == nil }) ? nil : costs.reduce(0) { $0 + ($1 ?? 0) }
                        let ahead = DealBreakdown.ahead(t, basis: basis, selling: !deal.outgoing.isEmpty)
                        VStack(alignment: .leading, spacing: 10) {
                            Text(DealBreakdown.verdict(ahead)).font(.geist(16, .bold))
                                .foregroundStyle(ahead.map { abs($0) < 0.005 ? Color.white : Theme.tone($0) } ?? Theme.muted)
                            DealBreakdown(kind: deal.kind, totals: t,
                                          getMarket: deal.incoming.reduce(0.0) { $0 + ($1.market ?? 0) * Double($1.qty) },
                                          basis: basis, selling: !deal.outgoing.isEmpty)
                        }
                        .padding(16)
                        .frame(maxWidth: .infinity, alignment: .leading)
                        .background(RoundedRectangle(cornerRadius: 18, style: .continuous).fill(Theme.surface))
                        .overlay(RoundedRectangle(cornerRadius: 18, style: .continuous).strokeBorder(Theme.border))
                        if !deal.incoming.isEmpty { sideRow(.incoming, deal.incoming, t.inValue) }
                        if !deal.outgoing.isEmpty { sideRow(.outgoing, deal.outgoing, t.outValue) }
                        let fx = deals.effects(deal)
                        Label {
                            Text([fx.adds > 0 ? "Adds \(fx.adds) to your collection" : nil,
                                  fx.sells > 0 ? "sells \(fx.sells) from it" : nil,
                                  fx.untracked > 0 ? "\(fx.untracked) not tracked" : nil].compactMap { $0 }.joined(separator: " · ").capitalizedFirst)
                        } icon: { Image(systemName: "square.stack.3d.up") }
                        .font(.geist(14, .semibold)).foregroundStyle(.white)
                        Text(store.demo != nil
                             ? "This is a demo collection: closing updates it on this phone only, and nothing is saved to your account."
                             : "Sales and purchases are added to your collection, and the deal goes in your history.")
                            .font(.geist(13)).foregroundStyle(Theme.muted)
                        if let error {
                            Label(error, systemImage: "exclamationmark.triangle.fill")
                                .font(.geist(13, .medium)).foregroundStyle(Theme.warn)
                        }
                    }
                }
                .padding(.horizontal, 20)
                .padding(.top, 14)
                .padding(.bottom, 16)
            }
            VStack(spacing: 8) {
                Group {
                    Button {
                        // A typed amount counts even if the keyboard is still up.
                        if editingFinal { editingFinal = false; applyFinal(MoneyField.value(finalText)) }
                        Task { await close() }
                    } label: {
                        HStack(spacing: 8) {
                            if phase == .recording { ProgressView().tint(Theme.ink) }
                            Text(phase == .recording ? "Recording…" : "Complete deal · \(Format.money(abs(b)))")
                        }
                    }
                    .buttonStyle(Button3D(kind: .lime))
                    .disabled(phase == .recording)
                    Button("Keep editing") { dismiss() }
                        .buttonStyle(Button3D(kind: .dark))
                        .disabled(phase == .recording)
                }
            }
            .padding(.horizontal, 20)
            .padding(.bottom, 12)
        }
    }

    private func finalLine(_ label: String, _ value: String) -> some View {
        HStack {
            Text(label).foregroundStyle(Theme.muted)
            Spacer()
            Text(value).monospacedDigit().foregroundStyle(.white)
        }
        .font(.geist(14))
    }

    private func sideRow(_ side: DealSide, _ items: [DealItem], _ value: Double) -> some View {
        let incoming = side == .incoming
        let count = items.reduce(0) { $0 + $1.qty }
        return HStack(spacing: 12) {
            Image(systemName: incoming ? "arrow.down.left" : "arrow.up.right")
                .font(.system(size: 14, weight: .semibold))
                .foregroundStyle(incoming ? Theme.lime : Theme.planPink)
                .frame(width: 30, height: 30)
                .background(Circle().fill(Color.white.opacity(0.06)))
            VStack(alignment: .leading, spacing: 6) {
                HStack {
                    Text(incoming ? "Buying" : "Selling").font(.geist(15, .semibold))
                    Text("\(count) item\(count == 1 ? "" : "s")").font(.geist(13)).foregroundStyle(Theme.muted)
                    Spacer()
                    Text(Format.money(value)).font(.geist(15, .semibold)).monospacedDigit()
                }
                // The items themselves, overlapping like a hand of cards.
                HStack(spacing: -10) {
                    ForEach(items.prefix(8)) { i in
                        HoldingArt(product: i.product, identity: nil, cornerRadius: 3, caption: false)
                            .frame(width: 34, height: 48)
                            .shadow(color: .black.opacity(0.5), radius: 4, x: 2)
                    }
                    if items.count > 8 {
                        Text("+\(items.count - 8)").font(.geist(12, .semibold)).foregroundStyle(Theme.muted).padding(.leading, 16)
                    }
                }
            }
        }
        .padding(14)
        .background(RoundedRectangle(cornerRadius: 18, style: .continuous).fill(Theme.surface))
        .overlay(RoundedRectangle(cornerRadius: 18, style: .continuous).strokeBorder(Theme.border))
    }

    private func pill(_ label: String, _ value: String, _ tint: Color) -> some View {
        HStack(spacing: 8) {
            MonoLabel(text: label)
            Text(value).font(.geist(15, .semibold)).monospacedDigit().foregroundStyle(tint)
        }
        .lineLimit(1)
        .padding(.horizontal, 14)
        .frame(height: 38)
        .liquidGlass(in: Capsule())
    }

    private func close() async {
        error = nil
        phase = .recording
        do {
            recorded = try await deals.close(using: store)
            UINotificationFeedbackGenerator().notificationOccurred(.success)
            withAnimation(.spring(duration: 0.45)) { phase = .done }
        } catch {
            UINotificationFeedbackGenerator().notificationOccurred(.error)
            self.error = "Couldn't record it: \(error.localizedDescription)"
            phase = .review
        }
    }
}

/// The deal, recorded: the whole screen goes electric lime (pink if it left you behind, so
/// there's never pink on lime). A check stamps in, the items fan in like a hand of cards and then slide together
/// into a neat recorded pile (each card a few degrees off), the headline number
/// counts up (how far ahead you came out, with profit and value gained under it), and an ink receipt lists what
/// changed hands and who paid. A broad soft glare passes over once.
private struct RecordedScreen: View {
    var totals: DealTotals
    var deal: DealState
    var rates: (in: Double, out: Double)
    var demo: Bool
    var onDone: () -> Void
    @Environment(\.accessibilityReduceMotion) private var reduceMotion
    @State private var shown = false
    /// The fanned cards have slid together into the recorded pile.
    @State private var piled = false

    private struct Row: Identifiable {
        var id: String
        var incoming: Bool
        var name: String
        var qty: Int
        var total: Double
    }

    var body: some View {
        let t = totals
        // The headline figure decides the color: down turns the whole screen pink.
        let down = (t.kind != .sell && t.inValue > 0 && t.equity < -0.005) || (t.ahead ?? 0) < -0.005
        let fill = down ? Theme.planPink : Theme.lime
        let ink = down ? Color.white : Theme.ink
        let items = Array((deal.outgoing + deal.incoming).prefix(7))
        let headline = Self.headline(t)
        VStack(spacing: 0) {
            Spacer(minLength: 12)
            VStack(spacing: 16) {
                Image(systemName: "checkmark")
                    .font(.system(size: 30, weight: .medium))
                    .foregroundStyle(fill)
                    .frame(width: 74, height: 74)
                    .background(Circle().fill(ink))
                    .scaleEffect(shown ? 1 : 0.3)
                    .rotationEffect(.degrees(shown ? 0 : -30))
                    .opacity(shown ? 1 : 0)
                VStack(spacing: 10) {
                    Text(demo ? "DEMO · NOTHING SAVED" : "IN YOUR COLLECTION").font(.mono(11)).tracking(1.6).foregroundStyle(ink.opacity(0.6))
                    // Two tight lines in sentence case ("Trade / recorded"), leading about 0.9.
                    VStack(spacing: -10) {
                        Text(t.kind.noun.capitalized).font(.display(58)).tracking(-2.3).displayTrim(58)
                        Text("recorded").font(.display(58)).tracking(-2.3).displayTrim(58)
                    }
                    .foregroundStyle(ink)
                    .lineLimit(1).minimumScaleFactor(0.6)
                }
                if !items.isEmpty {
                    ZStack {
                        ForEach(Array(items.enumerated()), id: \.element.id) { i, item in
                            let off = Double(i) - Double(items.count - 1) / 2
                            let pose = pilePose(i)
                            HoldingArt(product: item.product, identity: nil, cornerRadius: 5, caption: false)
                                .frame(width: 72, height: 100)
                                .shadow(color: .black.opacity(0.3), radius: 10, y: 8)
                                .rotationEffect(.degrees(piled ? pose.angle : (shown ? off * 9 : 0)), anchor: .bottom)
                                .offset(x: piled ? pose.x : (shown ? off * 36 : 0),
                                        y: piled ? pose.y : (shown ? abs(off) * 5 : 60))
                                .opacity(shown ? 1 : 0)
                                .animation(reduceMotion ? nil : cardAnimation(i, count: items.count), value: cardStage)
                        }
                    }
                    .frame(height: 118)
                    .overlay(alignment: .topTrailing) {
                        let count = deal.outgoing.count + deal.incoming.count
                        SkewTag(text: "\(count) item\(count == 1 ? "" : "s") filed", color: ink, textColor: fill)
                            .scaleEffect(piled ? 1 : 0.6)
                            .opacity(piled ? 1 : 0)
                            .rotationEffect(.degrees(-4))
                            .offset(x: 44, y: -8)
                            .animation(reduceMotion ? nil : .spring(response: 0.4, dampingFraction: 0.6).delay(0.1 + Double(items.count) * 0.07), value: piled)
                    }
                }
                if let headline {
                    VStack(spacing: 6) {
                        if t.ahead != nil {
                            Text(headline.label).font(.display(22)).tracking(-0.6).foregroundStyle(ink)
                        } else {
                            Text(headline.label.uppercased()).font(.mono(11)).tracking(1.6).foregroundStyle(ink.opacity(0.6))
                        }
                        CountingText(value: headline.value, format: { Format.signedMoney($0) })
                            .font(.display(64)).tracking(-2.6).monospacedDigit().foregroundStyle(ink).displayTrim(64)
                            .lineLimit(1).minimumScaleFactor(0.5)
                        breakdown(t, ink: ink)
                    }
                }
                receipt(t, ink: ink, fill: fill)
            }
            .padding(.horizontal, 20)
            Spacer(minLength: 12)
            Button(action: onDone) {
                Text("Done").font(.geist(17, .semibold)).foregroundStyle(fill)
                    .frame(maxWidth: .infinity).frame(height: 56)
                    .background(Capsule().fill(ink))
                    .contentShape(Capsule())
            }
            .buttonStyle(ShutterStyle())
            .padding(.horizontal, 20)
            .padding(.bottom, 12)
        }
        .frame(maxWidth: .infinity, maxHeight: .infinity)
        .background {
            ZStack {
                fill
                Canvas { ctx, size in
                    var path = Path()
                    stride(from: 0, through: size.width, by: 32).forEach { x in path.move(to: CGPoint(x: x, y: 0)); path.addLine(to: CGPoint(x: x, y: size.height)) }
                    stride(from: 0, through: size.height, by: 32).forEach { y in path.move(to: CGPoint(x: 0, y: y)); path.addLine(to: CGPoint(x: size.width, y: y)) }
                    ctx.stroke(path, with: .color(.black.opacity(0.06)), lineWidth: 1)
                }
                RadialGradient(colors: [.white.opacity(0.35), .clear], center: .top, startRadius: 0, endRadius: 440)
                SoftGlare()
            }
            .ignoresSafeArea()
        }
        .presentationBackground(fill)
        .onAppear {
            if reduceMotion { shown = true; piled = true } else { withAnimation(.spring(response: 0.5, dampingFraction: 0.6)) { shown = true } }
        }
        .task {
            // Once the hand has fanned in, the cards slide together into a neat pile.
            guard !reduceMotion, !piled else { return }
            try? await Task.sleep(for: .milliseconds(1100))
            piled = true
        }
    }

    /// 0 hidden, 1 fanned out, 2 piled: the cards animate whenever it moves on.
    private var cardStage: Int { piled ? 2 : (shown ? 1 : 0) }

    /// Fanning in, left to right; piling up, the outer cards first so the pile builds inward.
    private func cardAnimation(_ i: Int, count: Int) -> Animation {
        if piled {
            let fromEdge = abs(Double(i) - Double(count - 1) / 2)
            let maxEdge = Double(count - 1) / 2
            return .spring(response: 0.5, dampingFraction: 0.72).delay((maxEdge - fromEdge) * 0.07)
        }
        return .spring(response: 0.55, dampingFraction: 0.7).delay(0.15 + Double(i) * 0.06)
    }

    /// Where each card lands in the pile: nearly square, each a few degrees off, stacking up.
    private func pilePose(_ i: Int) -> (angle: Double, x: Double, y: Double) {
        let angles: [Double] = [-5, 4, -2, 6, -4, 2, -6]
        let nudges: [Double] = [-3, 2, -1, 3, -2, 1, 0]
        return (angles[i % angles.count], nudges[i % nudges.count], Double(-i) * 2)
    }

    /// How far ahead you came out; without every cost, profit (or for a buy, the equity you took in).
    private static func headline(_ t: DealTotals) -> (label: String, value: Double)? {
        if let ahead = t.ahead { return (dealAheadTitle(ahead, past: true), ahead) }
        if let profit = t.profit { return ("Sale profit", profit) }
        if t.inValue > 0 { return (t.kind == .buy ? "Potential profit" : "Trade-in value", t.equity) }
        return nil
    }

    /// "Profit +$971 · Value gained +$730", then "includes $730 on paper", all in ink (no pink on
    /// lime). Without every cost, a short note that the total isn't known.
    @ViewBuilder private func breakdown(_ t: DealTotals, ink: Color) -> some View {
        if t.ahead != nil {
            let parts = [t.profit.map { "Sale profit \(Format.signedMoney($0))" },
                         t.showsEquity ? "\(t.kind == .buy ? "Potential profit" : "Trade-in value") \(Format.signedMoney(t.equity))" : nil].compactMap { $0 }
            if !parts.isEmpty {
                Text(parts.joined(separator: " · ")).font(.geist(14, .semibold)).monospacedDigit().foregroundStyle(ink)
                    .lineLimit(1).minimumScaleFactor(0.75)
            }
            if let paper = t.onPaper {
                Text("includes \(Format.money(paper)) on paper").font(.geist(12, .medium)).foregroundStyle(ink.opacity(0.65))
            }
        } else if t.uncosted > 0 {
            Text("Total unknown: not every item had a\u{00A0}cost").font(.geist(12, .medium)).foregroundStyle(ink.opacity(0.65))
        }
    }

    /// An ink receipt: each item with its side, quantity and price, then who paid.
    private func receipt(_ t: DealTotals, ink: Color, fill: Color) -> some View {
        let rows: [Row] =
            deal.outgoing.map { Row(id: "o" + $0.key, incoming: false, name: $0.product.name, qty: $0.qty, total: $0.total(side: rates.out)) } +
            deal.incoming.map { Row(id: "i" + $0.key, incoming: true, name: $0.product.name, qty: $0.qty, total: $0.total(side: rates.in)) }
        let shown = Array(rows.prefix(4))
        return VStack(spacing: 0) {
            ForEach(shown) { r in
                HStack(spacing: 10) {
                    Image(systemName: r.incoming ? "arrow.down.left" : "arrow.up.right")
                        .font(.system(size: 11, weight: .semibold))
                        .foregroundStyle(r.incoming ? Theme.lime : Theme.planPink)
                    Text(r.name).font(.geist(14, .medium)).foregroundStyle(.white).lineLimit(1)
                    if r.qty > 1 { Text("×\(r.qty)").font(.geist(13)).foregroundStyle(Theme.muted) }
                    Spacer(minLength: 8)
                    Text(Format.money(r.total)).font(.geist(14, .semibold)).monospacedDigit().foregroundStyle(.white)
                }
                .padding(.vertical, 9)
            }
            if rows.count > shown.count {
                Text("+ \(rows.count - shown.count) more").font(.geist(12)).foregroundStyle(Theme.muted)
                    .frame(maxWidth: .infinity, alignment: .leading).padding(.vertical, 6)
            }
            // A perforated line, like a ticket.
            PerforatedLine().stroke(Theme.muted.opacity(0.5), style: StrokeStyle(lineWidth: 1, dash: [4, 4])).frame(height: 1).padding(.vertical, 8)
            HStack {
                Text(abs(t.balance) < 0.005 ? "Even swap" : (t.balance > 0 ? "They paid" : "You paid")).font(.geist(14, .semibold)).foregroundStyle(.white)
                if !deal.photos.isEmpty {
                    Label("\(deal.photos.count)", systemImage: "camera.fill").font(.geist(12, .semibold)).foregroundStyle(Theme.muted)
                }
                Spacer()
                Text(Format.money(abs(t.balance))).font(.display(26)).tracking(-0.7).monospacedDigit().foregroundStyle(fill).displayTrim(26)
            }
        }
        .padding(.horizontal, 16)
        .padding(.vertical, 10)
        .background(RoundedRectangle(cornerRadius: 22, style: .continuous).fill(Theme.ink))
        .opacity(self.shown ? 1 : 0)
        .offset(y: self.shown ? 0 : 30)
        .animation(reduceMotion ? nil : .spring(response: 0.6, dampingFraction: 0.8).delay(0.35), value: self.shown)
    }
}

private struct PerforatedLine: Shape {
    func path(in r: CGRect) -> Path {
        var p = Path()
        p.move(to: CGPoint(x: r.minX, y: r.midY))
        p.addLine(to: CGPoint(x: r.maxX, y: r.midY))
        return p
    }
}

/// A broad, soft band of light that sweeps across once (then rests), like light off a card.
/// One offset animation on a wide gradient: no blur.
private struct SoftGlare: View {
    @Environment(\.accessibilityReduceMotion) private var reduceMotion
    @State private var across = false

    var body: some View {
        GeometryReader { geo in
            let w = geo.size.width
            LinearGradient(stops: [
                .init(color: .white.opacity(0), location: 0),
                .init(color: .white.opacity(0.12), location: 0.35),
                .init(color: .white.opacity(0.28), location: 0.5),
                .init(color: .white.opacity(0.12), location: 0.65),
                .init(color: .white.opacity(0), location: 1),
            ], startPoint: .leading, endPoint: .trailing)
            .frame(width: w * 1.1, height: geo.size.height * 1.8)
            .rotationEffect(.degrees(18))
            .offset(x: across ? w * 1.2 : -w * 1.3, y: -geo.size.height * 0.4)
            .onAppear {
                guard !reduceMotion else { return }
                withAnimation(.easeInOut(duration: 2.2).delay(0.3)) { across = true }
            }
        }
        .allowsHitTesting(false)
    }
}

private extension String {
    var capitalizedFirst: String { prefix(1).uppercased() + dropFirst() }
}
