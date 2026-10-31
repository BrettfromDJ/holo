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
    /// One path for everything the Deal tab pushes (closed deals, a deal, a card), so pages
    /// stack properly instead of reopening each other.
    @State private var path = NavigationPath()
    @State private var customer = false
    @State private var confirming = false
    @State private var ebayItem: DealItem?

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

    /// Equity taken in has gone negative: every lime accent on the page turns pink as a warning.
    private var warning: Bool {
        let t = totals
        return t.kind != .sell && t.kind != .empty && t.inValue > 0 && t.equity < -0.005
    }

    private var accent: Color { warning ? Theme.planPink : Theme.lime }

    private var todays: [DealRecord] {
        deals.log.filter { Calendar.current.isDateInToday($0.date) }
    }

    var body: some View {
        NavigationStack(path: $path) {
            ScrollView {
                VStack(alignment: .leading, spacing: 32) {
                    VStack(alignment: .leading, spacing: 14) {
                        if !todays.isEmpty { TodayStrip(deals: todays) { path.append(DealRoute.history) } }
                        BalanceCard(totals: totals, roundTo: roundTarget, onRound: roundCash)
                    }
                    side(.incoming).reveal()
                    side(.outgoing).reveal()
                    photosSection.reveal()
                }
                .padding(.horizontal, 16)
                .padding(.top, 8)
                .padding(.bottom, 24)
                .background(alignment: .top) { DealBackdrop(accent: accent) }
            }
            .scrollDismissesKeyboard(.interactively)
            .background(Theme.background)
            .imageMaxPixel(360)
            .replaysAnimations()
            .animation(.easeInOut(duration: 0.3), value: warning)
            .tint(accent)
            .navigationBarTitleDisplayMode(.inline)
            .pageTitle("Deal")
            .toolbar {
                ToolbarItem(placement: .topBarLeading) {
                    Button { path.append(DealRoute.history) } label: { Image(systemName: "clock.arrow.circlepath") }.accessibilityLabel("Closed deals")
                }
                ToolbarItemGroup(placement: .topBarTrailing) {
                    Button { customer = true } label: { Image(systemName: "eye") }
                        .accessibilityLabel("Customer view")
                        .disabled(deals.deal.kind == .empty)
                    Button { settings = true } label: { Image(systemName: "slider.horizontal.3") }.accessibilityLabel("Deal settings")
                }
            }
            .safeAreaInset(edge: .bottom) {
                if deals.deal.kind != .empty { closeBar }
            }
            .tabBarClearance()
            .sheet(isPresented: $confirming) { DealCloseSheet() }
            .sheet(item: $picking) { side in DealPickerSheet(side: side) }
            .sheet(isPresented: $settings) { DealRatesSheet() }
            .navigationDestination(for: DealRoute.self) { _ in DealHistoryView() }
            .navigationDestination(for: DealRecord.self) { DealRecordDetail(recordId: $0.id) }
            .navigationDestination(for: String.self) { ProductDetailView(productId: $0) }
            .sheet(isPresented: $customer) { CustomerViewSheet(deal: deals.deal, rates: rates, totals: totals) }
            .sheet(item: $ebayItem) { item in
                NavigationStack {
                    ScrollView {
                        EbaySalesPanel(productId: item.product.id, printing: item.printing, grade: item.grade.map { "\($0.company) \($0.grade)" })
                            .padding(16)
                    }
                    .navigationTitle(item.product.name)
                    .navigationBarTitleDisplayMode(.inline)
                }
                .presentationDetents([.medium, .large])
                .glassSheet()
            }
            .fullScreenCover(item: $scanning) { side in
                ScanView(dealSide: side, onPick: { candidate, read in addScan(candidate, read: read, to: side) })
            }
        }
    }

    // MARK: Close bar

    private var closeBar: some View {
        VStack(spacing: 8) {
        // The answer, always on screen: who pays and whether you come out ahead.
        HStack(spacing: 6) {
            Text(totals.cashLine).foregroundStyle(.white)
            if let net = totals.net {
                Text("·").foregroundStyle(Theme.muted)
                Text(net >= 0 ? "You're \(Format.signedMoney(net))" : "You're \(Format.signedMoney(net))").foregroundStyle(Theme.tone(net))
            }
        }
        .font(.geist(13, .semibold)).monospacedDigit().lineLimit(1).minimumScaleFactor(0.75)
        .contentTransition(.numericText())
        .animation(.snappy, value: totals.balance)
        .padding(.top, 4)
        HStack(spacing: 8) {
            Button("Clear") {
                let photos = deals.deal.photos
                withAnimation(.snappy) { deals.update { $0 = DealState() } }
                // The deal's photos go with it.
                Task { for p in photos { await DealPhotos.delete(p) } }
            }
            .buttonStyle(Button3D(kind: .dark, fullWidth: false, height: 48))
            Button { confirming = true } label: {
                Text(unpriced ? "Price every item to close" : "Close \(deals.deal.kind.noun.lowercased())")
                    .frame(maxWidth: .infinity)
            }
            .buttonStyle(Button3D(kind: warning ? .pink : .lime, fullWidth: true, height: 48))
            .disabled(unpriced)
            .opacity(unpriced ? 0.55 : 1)
        }
        }
        .padding(8)
        .liquidGlass(in: RoundedRectangle(cornerRadius: 22, style: .continuous))
        .padding(.horizontal, 16)
        .padding(.bottom, 8)
    }

    // MARK: Rounding the cash

    /// The cash rounded to the nearest $5, when it isn't already.
    private var roundTarget: Double? {
        let b = totals.balance
        let r = (abs(b) / 5).rounded() * 5
        guard deals.deal.kind != .empty, r >= 5, abs(abs(b) - r) > 0.004 else { return nil }
        return b < 0 ? -r : r
    }

    /// Round the cash by nudging the price of the biggest item: one going out if there is one,
    /// else one coming in. It becomes a typed price on that item, so you can see and undo it.
    private func roundCash() {
        guard let target = roundTarget else { return }
        let delta = target - totals.balance
        let r = rates
        withAnimation(.snappy) {
            deals.update { d in
                if let i = d.outgoing.indices.max(by: { d.outgoing[$0].total(side: r.out) < d.outgoing[$1].total(side: r.out) }) {
                    let item = d.outgoing[i]
                    let newTotal = item.total(side: r.out) + delta
                    guard newTotal > 0 else { return }
                    d.outgoing[i].price = round2(newTotal / Double(item.qty))
                    d.outgoing[i].rate = nil
                } else if let i = d.incoming.indices.max(by: { d.incoming[$0].total(side: r.in) < d.incoming[$1].total(side: r.in) }) {
                    let item = d.incoming[i]
                    let newTotal = item.total(side: r.in) - delta
                    guard newTotal > 0 else { return }
                    d.incoming[i].price = round2(newTotal / Double(item.qty))
                    d.incoming[i].rate = nil
                }
            }
        }
        UIImpactFeedbackGenerator(style: .light).impactOccurred()
    }

    // MARK: Photos

    /// Photos documenting the deal (the cards on the table, a receipt); they're kept with it when it closes.
    private var photosSection: some View {
        VStack(alignment: .leading, spacing: 12) {
            VStack(alignment: .leading, spacing: 6) {
                HStack(spacing: 8) {
                    Image(systemName: "camera.fill").font(.system(size: 14, weight: .bold)).foregroundStyle(accent)
                    Text("PHOTOS").font(.display(24)).displayTrim(24)
                    if !deals.deal.photos.isEmpty { MonoLabel(text: "\(deals.deal.photos.count)") }
                }
                Text("Document the deal: the cards on the table, a receipt, the customer's binder").font(.geist(12)).foregroundStyle(Theme.muted)
            }
            DealPhotosStrip(photos: deals.deal.photos, accountId: store.demo == nil ? deals.accountId : nil, accent: accent) { photos in
                deals.update { $0.photos = photos }
            }
        }
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
                            .foregroundStyle(incoming ? accent : Theme.planPink)
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

            RateCard(rate: rate, fallback: fallback, accent: accent, result: deals.deal.kind == .empty ? nil : totals.summary) { r in
                deals.update { d in if incoming { d.rateIn = r } else { d.rateOut = r } }
            }

            ForEach(items) { item in
                DealItemCard(item: item, incoming: incoming, rate: rate, cost: incoming ? nil : deals.cost(of: item, in: store), accent: accent,
                             tracked: deals.tracked(item, side: side), asksCost: deals.defaults.asksCost,
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
            if let h = store.allHoldings.first(where: { $0.identity.productId == c.product.id && $0.identity.printing == c.printing && sameGrade($0.identity) }), let p = h.product {
                deals.add(DealItem(key: "h:\(h.identity.key)", product: p, printing: h.identity.printing, market: h.price ?? c.market, holdingKey: h.identity.key), to: .incoming)
            } else {
                let gradeLabel = grade.map { "\($0.company) \($0.grade)" } ?? ""
                deals.add(DealItem(key: "p:\(c.product.id):\(c.printing ?? ""):\(gradeLabel)", product: c.product, printing: c.printing, market: c.value(for: read), grade: grade), to: .incoming)
            }
            return (true, "Added to coming in")
        }
        let owned = store.allHoldings.filter { $0.identity.productId == c.product.id }
        guard let h = owned.first(where: { $0.identity.printing == c.printing && sameGrade($0.identity) }) ?? owned.first, let p = h.product else {
            // Not in Holo: it still goes in the deal, marked so, with an optional "you paid".
            let gradeLabel = grade.map { "\($0.company) \($0.grade)" } ?? ""
            deals.add(DealItem(key: "p:\(c.product.id):\(c.printing ?? ""):\(gradeLabel)", product: c.product, printing: c.printing, market: c.value(for: read), grade: grade), to: .outgoing)
            return (true, "Added · not in Holo")
        }
        deals.add(DealItem(key: "h:\(h.identity.key)", product: p, printing: h.identity.printing, market: h.price, holdingKey: h.identity.key, maxQty: Int(h.quantity)), to: .outgoing)
        return (true, "Added to going out")
    }
}

/// Pages the Deal tab pushes besides deals and cards.
enum DealRoute: Hashable { case history }

extension DealSide: Identifiable {
    var id: String { rawValue }
}

/// The lit grid and soft glows behind the top of the page, like the other tabs.
private struct DealBackdrop: View {
    var accent: Color

    var body: some View {
        ZStack {
            GridPattern(step: 36, opacity: 0.05)
            RadialGradient(colors: [accent.opacity(0.18), .clear], center: UnitPoint(x: 0.2, y: 0.3), startRadius: 0, endRadius: 260)
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

extension DealTotals {
    /// Equity only means something when something comes in.
    var showsEquity: Bool { !(kind == .sell || kind == .empty || inValue == 0) }

    /// How much better off you are, at market: your profit on what goes out plus the value
    /// you gain on what comes in. Nil when neither is known.
    var net: Double? {
        if profit == nil && !showsEquity { return nil }
        return (profit ?? 0) + (showsEquity ? equity : 0)
    }

    var cashLine: String {
        abs(balance) < 0.005 ? "Even swap" : (balance > 0 ? "Customer pays you \(Format.money(balance))" : "You pay \(Format.money(-balance))")
    }

    var verdict: String? {
        net.map { n in abs(n) < 0.005 ? "You break even" : (n > 0 ? "You come out \(Format.money(n)) ahead" : "You come out \(Format.money(-n)) behind") }
    }

    /// "Customer pays you $40 · you're +$58", for under the slider.
    var summary: String {
        cashLine + (net.map { " · you're \(Format.signedMoney($0))" } ?? "")
    }
}

/// What each number means, one sentence each (tap a label to read it).
enum DealTerm: String {
    case verdict, cash, comingIn, goingOut, profit, value, rate

    var title: String {
        switch self {
        case .verdict: return "Ahead or behind"
        case .cash: return "Cash"
        case .comingIn: return "Coming in"
        case .goingOut: return "Going out"
        case .profit: return "Your profit"
        case .value: return "Value gained"
        case .rate: return "Share of market"
        }
    }

    var explanation: String {
        switch self {
        case .verdict: return "Your profit on what you hand over plus the value you gain on what comes in: how much better off you are after this deal, at market prices."
        case .cash: return "The difference between the two sides, paid in cash so the deal comes out even."
        case .comingIn: return "What the customer's cards count for in this deal, at the prices you set."
        case .goingOut: return "What your cards count for in this deal, at the prices you set."
        case .profit: return "What your cards go for in this deal, minus what you paid for them."
        case .value: return "Market value of what comes in, minus what you're giving for it: how far below market you're getting it."
        case .rate: return "Each item counts for this share of its market price. Drag to counter-offer, or set one item's own % or price."
        }
    }
}

/// A small caps label you can tap to read what it means.
private struct TermLabel: View {
    var text: String
    var term: DealTerm
    var color: Color
    @State private var open = false

    var body: some View {
        Button { open = true } label: {
            HStack(spacing: 4) {
                Text(text.uppercased()).font(.mono(10)).tracking(1.1)
                Image(systemName: "info.circle").font(.system(size: 9, weight: .semibold)).opacity(0.7)
            }
            .foregroundStyle(color)
            .contentShape(Rectangle())
        }
        .buttonStyle(.plain)
        .popover(isPresented: $open) {
            TermTip(term: term)
        }
    }
}

/// The deal at a glance on a solid electric-lime card: whether you come out ahead, who pays
/// whom (with a one-tap round to $5), a bar showing what each side puts in, and the four numbers
/// in plain words (tap any for what it means). When the value gained is negative the whole card
/// goes pink, so there's never pink on lime.
private struct BalanceCard: View {
    var totals: DealTotals
    var roundTo: Double?
    var onRound: () -> Void

    var body: some View {
        let t = totals
        let b = t.balance
        let empty = t.kind == .empty
        let down = t.showsEquity && t.equity < -0.005
        let fill = down ? Theme.planPink : Theme.lime
        let ink = down ? Color.white : Theme.ink
        let shape = RoundedRectangle(cornerRadius: 24, style: .continuous)
        VStack(alignment: .leading, spacing: 0) {
            HStack {
                SkewTag(text: empty ? "New deal" : t.kind.label, color: down ? .white : Theme.ink, textColor: down ? Theme.ink : Theme.lime)
                Spacer()
                if t.belowCost > 0 {
                    Label("\(t.belowCost) below cost", systemImage: "exclamationmark.triangle.fill")
                        .font(.geist(12, .semibold)).foregroundStyle(ink)
                }
            }

            // The verdict, in plain English.
            if let verdict = t.verdict {
                HStack(spacing: 8) {
                    Image(systemName: (t.net ?? 0) >= 0 ? "arrow.up.right" : "arrow.down.right").font(.system(size: 13, weight: .black))
                    Text(verdict).font(.geist(15, .bold)).lineLimit(1).minimumScaleFactor(0.7)
                    TermInfo(term: .verdict, color: fill)
                }
                .foregroundStyle(fill)
                .padding(.horizontal, 14).frame(height: 36)
                .background(Capsule().fill(ink))
                .padding(.top, 16)
                .contentTransition(.numericText())
                .animation(.snappy, value: t.net)
            }
            if t.uncosted > 0 {
                Text("Profit unknown for \(t.uncosted) item\(t.uncosted == 1 ? "" : "s") not in Holo: add what you paid")
                    .font(.geist(12, .medium)).foregroundStyle(ink.opacity(0.7))
                    .padding(.top, 8)
            }

            HStack(alignment: .lastTextBaseline) {
                TermLabel(text: empty ? "Add items to start" : (abs(b) < 0.005 ? "Settled · no cash" : (b > 0 ? "Customer pays you" : "You pay the customer")), term: .cash, color: ink.opacity(0.7))
                Spacer()
            }
            .padding(.top, 16)
            HStack(alignment: .center, spacing: 10) {
                CountingText(value: abs(b), format: { Format.money($0) })
                    .font(.display(60)).monospacedDigit().foregroundStyle(ink).lineLimit(1).minimumScaleFactor(0.5)
                    .displayTrim(60)
                Spacer(minLength: 0)
                if let roundTo {
                    Button(action: onRound) {
                        VStack(spacing: 1) {
                            Text("Round to").font(.geist(10, .semibold)).opacity(0.7)
                            Text(Format.money(abs(roundTo))).font(.geist(14, .bold)).monospacedDigit()
                        }
                        .foregroundStyle(fill)
                        .padding(.horizontal, 12).frame(height: 44)
                        .background(Capsule().fill(ink))
                    }
                    .buttonStyle(ShutterStyle())
                    .transition(.scale.combined(with: .opacity))
                }
            }
            .padding(.top, 8)

            LazyVGrid(columns: [GridItem(.flexible(), spacing: 12), GridItem(.flexible(), spacing: 12)], alignment: .leading, spacing: 14) {
                stat("Coming in", .comingIn, Format.money(t.inValue), ink)
                stat("Going out", .goingOut, Format.money(t.outValue), ink)
                stat("Your profit", .profit, t.profit.map { Format.signedMoney($0) } ?? "—", ink)
                stat("Value gained", .value, t.showsEquity ? Format.signedMoney(t.equity) : "—", ink)
            }
            .padding(.top, 18)
        }
        .padding(20)
        .frame(maxWidth: .infinity, alignment: .leading)
        .background {
            ZStack {
                shape.fill(fill)
                // A faint ink grid, like the other tabs' backdrops, printed on the card.
                Canvas { ctx, size in
                    var path = Path()
                    stride(from: 0, through: size.width, by: 28).forEach { x in path.move(to: CGPoint(x: x, y: 0)); path.addLine(to: CGPoint(x: x, y: size.height)) }
                    stride(from: 0, through: size.height, by: 28).forEach { y in path.move(to: CGPoint(x: 0, y: y)); path.addLine(to: CGPoint(x: size.width, y: y)) }
                    ctx.stroke(path, with: .color(.black.opacity(0.06)), lineWidth: 1)
                }
            }
            .clipShape(shape)
            .shadow(color: fill.opacity(0.4), radius: 22)
        }
        .animation(.easeInOut(duration: 0.3), value: down)
        .animation(.snappy, value: roundTo)
        // A warning buzz the moment value gained goes negative (and a light tap when it recovers).
        .sensoryFeedback(trigger: down) { was, now in
            now && !was ? .warning : (was && !now ? .impact(weight: .light) : nil)
        }
    }

    private func stat(_ label: String, _ term: DealTerm, _ value: String, _ ink: Color) -> some View {
        VStack(alignment: .leading, spacing: 5) {
            TermLabel(text: label, term: term, color: ink.opacity(0.65))
            Text(value).font(.geist(17, .semibold)).monospacedDigit().foregroundStyle(ink).lineLimit(1).minimumScaleFactor(0.7)
        }
        .frame(maxWidth: .infinity, alignment: .leading)
    }
}

/// A term's explanation: a solid dark tip with small corners and bright, readable text.
private struct TermTip: View {
    var term: DealTerm

    var body: some View {
        VStack(alignment: .leading, spacing: 6) {
            Text(term.title).font(.geist(15, .semibold)).foregroundStyle(.white)
            Text(term.explanation).font(.geist(14)).foregroundStyle(.white.opacity(0.85))
                .fixedSize(horizontal: false, vertical: true)
        }
        .padding(16)
        .frame(width: 280, alignment: .leading)
        .presentationCompactAdaptation(.popover)
        .presentationBackground(Theme.surface2)
        .presentationCornerRadius(12)
    }
}

/// Just the info mark, for inside the verdict pill.
private struct TermInfo: View {
    var term: DealTerm
    var color: Color
    @State private var open = false

    var body: some View {
        Button { open = true } label: {
            Image(systemName: "info.circle").font(.system(size: 12, weight: .semibold)).foregroundStyle(color.opacity(0.75))
        }
        .buttonStyle(.plain)
        .popover(isPresented: $open) {
            TermTip(term: term)
        }
    }
}

/// The side's share of market, adjustable for this deal (the counter-offer slider), with what it
/// does to the deal shown live underneath as you drag.
private struct RateCard: View {
    var rate: Double
    var fallback: Double
    var accent: Color
    var result: String?
    var onChange: (Double?) -> Void

    var body: some View {
        VStack(alignment: .leading, spacing: 10) {
            HStack(alignment: .firstTextBaseline) {
                Text("At ").foregroundColor(Theme.muted) + Text("\(Int((rate * 100).rounded()))%").foregroundColor(.white) + Text(" of market").foregroundColor(Theme.muted)
                TermInfo(term: .rate, color: .white)
                Spacer()
                if abs(rate - fallback) > 0.0001 {
                    Button("Reset to \(Int((fallback * 100).rounded()))%") { onChange(nil) }
                        .font(.geist(12, .medium)).foregroundStyle(Theme.muted)
                        .buttonStyle(.plain)
                }
            }
            .font(.geist(14, .medium)).monospacedDigit()
            Slider(value: Binding(get: { rate }, set: { onChange(($0 * 100).rounded() / 100) }), in: 0.4...1.2, step: 0.01)
                .tint(accent)
                .sensoryFeedback(.selection, trigger: Int((rate * 20).rounded()))
            if let result {
                HStack(spacing: 6) {
                    Image(systemName: "arrow.turn.down.right").font(.system(size: 10, weight: .bold)).foregroundStyle(Theme.subtle)
                    Text(result).font(.geist(12, .medium)).foregroundStyle(Theme.muted).monospacedDigit()
                        .lineLimit(1).minimumScaleFactor(0.8)
                        .contentTransition(.numericText())
                        .animation(.snappy, value: result)
                }
            }
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
    var incoming: Bool
    var rate: Double
    var cost: Double?
    var accent: Color
    /// Whether closing records this line in your collection.
    var tracked: Bool
    var asksCost: Bool
    var onEbay: () -> Void
    var onRemove: () -> Void
    var onChange: (DealItem) -> Void
    @State private var priceText = ""
    @State private var rateText = ""
    @State private var costText = ""
    @State private var showCost = false

    var body: some View {
        let unit = item.unitPrice(side: rate)
        let total = item.total(side: rate)
        HStack(alignment: .top, spacing: 12) {
            HoldingArt(product: item.product, identity: nil, cornerRadius: 4, caption: false)
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
                HStack(spacing: 5) {
                    if let market = item.market, let unit, abs(unit - market) > 0.004 {
                        Text(Format.money(market)).strikethrough().foregroundStyle(Theme.subtle)
                        Image(systemName: "arrow.right").font(.system(size: 9, weight: .bold)).foregroundStyle(Theme.subtle)
                        Text(Format.money(unit)).foregroundStyle(.white).fontWeight(.semibold)
                        Text("\(Int((unit / market * 100).rounded()))%")
                            .font(.geist(10, .bold)).foregroundStyle(Theme.ink)
                            .padding(.horizontal, 5).frame(height: 16)
                            .background(Capsule().fill(accent))
                    } else {
                        Text(subtitle).foregroundStyle(Theme.muted)
                    }
                    if let g = item.grade { Text("· \(g.company) \(g.grade)").foregroundStyle(Theme.muted) }
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

                statusRow
                    .padding(.top, 10)

                HStack(spacing: 6) {
                    if let cost {
                        let profit = total - cost
                        if item.holdingKey != nil { Text("You paid \(Format.money(cost)) ·").foregroundStyle(Theme.muted) } else { Text("Profit").foregroundStyle(Theme.muted) }
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
            if let c = item.cost { costText = String(format: "%.2f", c) }
        }
        .onChange(of: item.price) { _, p in
            if let p, MoneyField.value(priceText) != p { priceText = String(format: "%.2f", p) }
        }
    }

    /// What happens to this line in your collection, and the switch or field that changes it.
    @ViewBuilder private var statusRow: some View {
        if item.isCustom {
            tag("Custom · not tracked", icon: "square.and.pencil")
        } else if incoming {
            Toggle(isOn: Binding(get: { tracked }, set: { on in change { $0.track = on } })) {
                Text("Add to collection").font(.geist(12, .medium)).foregroundStyle(tracked ? .white : Theme.muted)
            }
            .toggleStyle(.switch)
            .controlSize(.mini)
            .tint(accent)
        } else if item.holdingKey == nil {
            HStack(spacing: 8) {
                tag(tracked ? "Not in Holo · will be added" : "Not in Holo · not tracked", icon: "exclamationmark.circle")
                Spacer(minLength: 0)
                if asksCost || showCost || item.cost != nil {
                    HStack(spacing: 2) {
                        Text("Paid $").foregroundStyle(Theme.subtle)
                        TextField("each", text: $costText)
                            .keyboardType(.decimalPad)
                            .frame(width: 52)
                            .onChange(of: costText) { _, text in
                                let value = MoneyField.value(text)
                                guard value != item.cost else { return }
                                change { $0.cost = value }
                            }
                    }
                    .font(.geist(12)).monospacedDigit()
                    .padding(.horizontal, 9).frame(height: 28)
                    .background(Capsule().fill(item.cost != nil ? Theme.surface3 : Theme.surface2))
                    .overlay(Capsule().strokeBorder(item.cost != nil ? accent.opacity(0.6) : .clear))
                } else {
                    Button("Add what you paid") { showCost = true }
                        .font(.geist(12, .medium)).foregroundStyle(.white).buttonStyle(.plain)
                }
            }
        }
    }

    private func tag(_ text: String, icon: String) -> some View {
        Label(text, systemImage: icon)
            .font(.geist(11, .semibold)).foregroundStyle(Theme.muted)
            .padding(.horizontal, 8).frame(height: 22)
            .background(Capsule().fill(Color.white.opacity(0.06)))
            .lineLimit(1).fixedSize()
    }

    private var subtitle: String {
        item.market.map { "Market \(Format.money($0))" } ?? "No market price"
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
        .overlay(Capsule().strokeBorder(on ? accent.opacity(0.6) : .clear))
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
        .overlay(Capsule().strokeBorder(on ? accent.opacity(0.6) : .clear))
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
                    HoldingArt(product: i.product, identity: nil, cornerRadius: 3, caption: false).frame(width: 40, height: 56)
                    (Text(i.product.name) + Text(i.qty > 1 ? " × \(i.qty)" : "").foregroundColor(Theme.muted))
                        .font(.geist(15, .medium))
                    Spacer(minLength: 8)
                    Text(Format.money(i.total(side: rate))).font(.geist(16, .semibold)).monospacedDigit()
                }
            }
        }
    }
}
