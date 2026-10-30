import SwiftUI

/// Pick what's coming in or going out: from your inventory, anything in the catalog (going out,
/// that's something you have that isn't in Holo yet), or a custom line with just a name and price.
struct DealPickerSheet: View {
    var side: DealSide
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
        let all = store.holdings.filter { $0.product != nil }
        guard !q.isEmpty else { return Array(all.prefix(40)) }
        return all.filter { h in
            let p = h.product!
            return p.name.lowercased().contains(q) || (p.setName ?? "").lowercased().contains(q) || (p.number ?? "").lowercased().contains(q)
        }
    }

    var body: some View {
        NavigationStack {
            List {
                Section {
                    Button { customOpen = true } label: {
                        Label("Custom item: a name and a price", systemImage: "square.and.pencil").foregroundStyle(.white)
                    }
                } footer: {
                    Text("For things that aren't in the catalog, like a bulk lot or a binder of commons. Counted in the deal, not tracked in your collection.")
                }
                Section(side == .outgoing ? "Your inventory" : "In your inventory") {
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
                                HStack {
                                    SearchRow(hit: hit)
                                    if added.contains(hit.id) { Image(systemName: "checkmark").foregroundStyle(Theme.lime) }
                                }
                            }
                            .buttonStyle(.plain)
                        }
                    } header: {
                        Text(side == .incoming ? "Catalog" : "Not in Holo")
                    } footer: {
                        if side == .outgoing {
                            Text("Something you have that isn't in Holo yet. Add what you paid on the deal and it's recorded properly; otherwise it's counted in the deal but not tracked.")
                        }
                    }
                }
            }
            .scrollContentBackground(.hidden)
            .background(Theme.background)
            .safeAreaInset(edge: .top, spacing: 0) {
                HoloSearchField(text: $query, prompt: side == .incoming ? "Search any card or product" : "Search your inventory or any card",
                                focus: $focused, loading: searching)
                    .padding(.horizontal, 16)
                    .padding(.vertical, 8)
                    .background(Theme.background)
            }
            .scrollDismissesKeyboard(.immediately)
            .navigationTitle(side == .incoming ? "Coming in" : "Going out")
            .navigationBarTitleDisplayMode(.inline)
            .toolbar { ToolbarItem(placement: .confirmationAction) { Button("Done") { dismiss() } } }
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
                    UIImpactFeedbackGenerator(style: .light).impactOccurred()
                    dismiss()
                }
            }
        }
    }

    private func addHolding(_ h: HoldingView) {
        guard let p = h.product else { return }
        let item = DealItem(
            key: "h:\(h.identity.key)", product: p, printing: h.identity.printing, market: h.price,
            holdingKey: h.identity.key, maxQty: side == .outgoing ? Int(h.quantity) : nil
        )
        deals.add(item, to: side)
        added.insert(h.id)
        UIImpactFeedbackGenerator(style: .light).impactOccurred()
    }

    private func addHit(_ hit: SearchHit) {
        deals.add(DealItem(key: "p:\(hit.product.id):\(hit.printing ?? ""):", product: hit.product, printing: hit.printing, market: hit.market), to: side)
        added.insert(hit.id)
        UIImpactFeedbackGenerator(style: .light).impactOccurred()
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

    var body: some View {
        NavigationStack {
            Form {
                TextField("What is it? (Bulk lot, binder of commons…)", text: $name)
                MoneyField(title: "Price each", text: $price, hint: "0.00")
                Stepper("Quantity: \(qty)", value: $qty, in: 1...999)
            }
            .scrollContentBackground(.hidden)
            .background(Theme.background)
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

    var body: some View {
        NavigationStack {
            Form {
                Section {
                    Toggle("Add what comes in to my collection", isOn: Binding(get: { rates.addsIncoming }, set: { rates.addIncoming = $0 }))
                    Toggle("Ask what I paid for things not in Holo", isOn: Binding(get: { rates.asksCost }, set: { rates.askCost = $0 }))
                } footer: {
                    Text("You can still switch any single item in or out on the deal. Items going out that aren't in Holo are tracked when you add what you paid.")
                }
                .tint(Theme.lime)
                rate("Buying", "What you pay for cards you buy", \.buy)
                rate("Trade-in", "What you credit for cards taken in on trade", \.trade)
                rate("Selling", "What you charge for cards going out", \.sell)
            }
            .scrollContentBackground(.hidden)
            .background(Theme.background)
            .navigationTitle("Deal settings")
            .navigationBarTitleDisplayMode(.inline)
            .toolbar {
                ToolbarItem(placement: .cancellationAction) { Button("Cancel") { dismiss() } }
                ToolbarItem(placement: .confirmationAction) {
                    Button("Save") {
                        deals.setDefaults(rates)
                        dismiss()
                    }
                }
            }
            .onAppear { rates = deals.defaults }
        }
        .presentationDetents([.medium, .large])
    }

    private func rate(_ title: String, _ hint: String, _ key: WritableKeyPath<DealRates, Double>) -> some View {
        Section {
            HStack {
                Text(title)
                Spacer()
                Text("\(Int((rates[keyPath: key] * 100).rounded()))%").monospacedDigit().bold()
            }
            Slider(value: Binding(get: { rates[keyPath: key] }, set: { rates[keyPath: key] = ($0 * 100).rounded() / 100 }), in: 0.3...1.5, step: 0.01)
        } footer: {
            Text("\(hint), as a share of market.")
        }
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

    enum Phase { case review, recording, done }

    init() {
        _deal = State(initialValue: DealState())
        _rates = State(initialValue: (0, 0))
    }

    private var totals: DealTotals { DealTotals(deal, rates: rates, cost: { deals.cost(of: $0, in: store) }) }

    var body: some View {
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
            deal = deals.deal
            rates = deals.rates
        }
    }

    @ViewBuilder private var reviewBody: some View {
        let t = totals
        let b = t.balance
        VStack(alignment: .leading, spacing: 0) {
            Capsule().fill(Color.white.opacity(0.2)).frame(width: 40, height: 5).frame(maxWidth: .infinity).padding(.top, 8)
            ScrollView {
                VStack(alignment: .leading, spacing: 22) {
                    Group {
                        VStack(alignment: .leading, spacing: 8) {
                            SkewTag(text: t.kind.label)
                            DisplayText(text: "CLOSE THIS \(t.kind.noun.uppercased())?", size: 30)
                                .frame(maxWidth: .infinity, alignment: .leading)
                        }
                        // Who pays whom, big enough to turn the phone around.
                        VStack(alignment: .leading, spacing: 8) {
                            MonoLabel(text: abs(b) < 0.005 ? "Even trade" : (b > 0 ? "Customer pays you" : "You pay the customer"))
                            Text(Format.money(abs(b))).font(.display(56)).monospacedDigit().displayTrim(56)
                                .lineLimit(1).minimumScaleFactor(0.5)
                        }
                        .padding(18)
                        .frame(maxWidth: .infinity, alignment: .leading)
                        .liquidGlass(in: RoundedRectangle(cornerRadius: 22, style: .continuous))
                        if let verdict = t.verdict {
                            Label(verdict, systemImage: (t.net ?? 0) >= 0 ? "arrow.up.right" : "arrow.down.right")
                                .font(.geist(16, .bold)).foregroundStyle(Theme.tone(t.net))
                        }
                        if !deal.incoming.isEmpty { sideRow(.incoming, deal.incoming, t.inValue) }
                        if !deal.outgoing.isEmpty { sideRow(.outgoing, deal.outgoing, t.outValue) }
                        HStack(spacing: 8) {
                            if let profit = t.profit { pill("Profit", Format.signedMoney(profit), Theme.tone(profit)) }
                            if deal.kind != .sell, t.inValue > 0 { pill("Value gained", Format.signedMoney(t.equity), Theme.tone(t.equity)) }
                        }
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
                    Button { Task { await close() } } label: {
                        HStack(spacing: 8) {
                            if phase == .recording { ProgressView().tint(Theme.ink) }
                            Text(phase == .recording ? "Recording…" : "Close \(t.kind.noun.lowercased())")
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
        .background(Theme.background)
    }

    private func sideRow(_ side: DealSide, _ items: [DealItem], _ value: Double) -> some View {
        let incoming = side == .incoming
        let count = items.reduce(0) { $0 + $1.qty }
        return HStack(spacing: 12) {
            Image(systemName: incoming ? "arrow.down.left" : "arrow.up.right")
                .font(.system(size: 14, weight: .bold))
                .foregroundStyle(incoming ? Theme.lime : Theme.planPink)
                .frame(width: 30, height: 30)
                .background(Circle().fill(Color.white.opacity(0.06)))
            VStack(alignment: .leading, spacing: 6) {
                HStack {
                    Text(incoming ? "Coming in" : "Going out").font(.geist(15, .semibold))
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

/// The deal, recorded: the whole screen goes electric lime (pink if the equity taken in was
/// negative). A check stamps in, the items fan in like a hand of cards, the headline number
/// counts up (profit, or for a buy the equity you took in), and an ink receipt lists what
/// changed hands and who paid. A broad soft glare passes over once.
private struct RecordedScreen: View {
    var totals: DealTotals
    var deal: DealState
    var rates: (in: Double, out: Double)
    var demo: Bool
    var onDone: () -> Void
    @Environment(\.accessibilityReduceMotion) private var reduceMotion
    @State private var shown = false

    private struct Row: Identifiable {
        var id: String
        var incoming: Bool
        var name: String
        var qty: Int
        var total: Double
    }

    var body: some View {
        let t = totals
        let down = t.kind != .sell && t.inValue > 0 && t.equity < -0.005
        let fill = down ? Theme.planPink : Theme.lime
        let ink = down ? Color.white : Theme.ink
        let items = Array((deal.outgoing + deal.incoming).prefix(7))
        // Profit when something went out; for a buy, the equity you took in.
        let headline: (label: String, value: Double)? = t.profit.map { ("Profit", $0) } ?? (t.inValue > 0 ? ("Value gained", t.equity) : nil)
        VStack(spacing: 0) {
            Spacer(minLength: 12)
            VStack(spacing: 20) {
                Image(systemName: "checkmark")
                    .font(.system(size: 30, weight: .black))
                    .foregroundStyle(fill)
                    .frame(width: 74, height: 74)
                    .background(Circle().fill(ink))
                    .scaleEffect(shown ? 1 : 0.3)
                    .rotationEffect(.degrees(shown ? 0 : -30))
                    .opacity(shown ? 1 : 0)
                VStack(spacing: 10) {
                    Text(demo ? "DEMO · NOTHING SAVED" : "IN YOUR COLLECTION").font(.mono(11)).tracking(1.6).foregroundStyle(ink.opacity(0.6))
                    // Anton has tall built-in line spacing; trim each line so they sit tight.
                    VStack(spacing: 6) {
                        Text(t.kind.noun.uppercased()).font(.display(58)).displayTrim(58)
                        Text("RECORDED").font(.display(58)).displayTrim(58)
                    }
                    .foregroundStyle(ink)
                    .lineLimit(1).minimumScaleFactor(0.6)
                }
                if !items.isEmpty {
                    ZStack {
                        ForEach(Array(items.enumerated()), id: \.element.id) { i, item in
                            let off = Double(i) - Double(items.count - 1) / 2
                            HoldingArt(product: item.product, identity: nil, cornerRadius: 5, caption: false)
                                .frame(width: 72, height: 100)
                                .shadow(color: .black.opacity(0.3), radius: 10, y: 8)
                                .rotationEffect(.degrees(shown ? off * 9 : 0), anchor: .bottom)
                                .offset(x: shown ? off * 36 : 0, y: shown ? abs(off) * 5 : 60)
                                .opacity(shown ? 1 : 0)
                                .animation(reduceMotion ? nil : .spring(response: 0.55, dampingFraction: 0.7).delay(0.15 + Double(i) * 0.06), value: shown)
                        }
                    }
                    .frame(height: 118)
                }
                if let headline {
                    VStack(spacing: 6) {
                        Text(headline.label.uppercased()).font(.mono(11)).tracking(1.6).foregroundStyle(ink.opacity(0.6))
                        CountingText(value: headline.value, format: { Format.signedMoney($0) })
                            .font(.display(72)).monospacedDigit().foregroundStyle(ink).displayTrim(72)
                            .lineLimit(1).minimumScaleFactor(0.5)
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
            if reduceMotion { shown = true } else { withAnimation(.spring(response: 0.5, dampingFraction: 0.6)) { shown = true } }
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
                        .font(.system(size: 11, weight: .bold))
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
                Text(Format.money(abs(t.balance))).font(.display(26)).monospacedDigit().foregroundStyle(fill).displayTrim(26)
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
