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
    /// The balance card has scrolled up under the top: a compact copy pins there instead and
    /// the top icons step aside.
    @State private var pinned = false
    @Environment(\.accessibilityReduceMotion) private var reduceMotion
    @State private var confirming = false
    @State private var ebayItem: DealItem?
    @AppStorage("holo.dealHintSeen") private var hintSeen = false
    /// A card in the deal, opened to see its full details in a sheet.
    @State private var detailItem: DealItem?
    /// Parking the deal: asks for an optional name first.
    @State private var parking = false
    @State private var parkName = ""
    @State private var parkedList = false

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

    /// The deal leaves you behind (the "ahead" total is negative, or, when it can't be worked
    /// out, the value taken in is): every lime accent on the page turns pink as a warning, the
    /// same rule the Recorded screen uses.
    private static func warning(_ t: DealTotals) -> Bool {
        guard t.kind != .empty else { return false }
        // Pink when what you take in is worth less than you're giving for it, or when the deal
        // as a whole leaves you behind.
        let equityDown = t.kind != .sell && t.inValue > 0 && t.equity < -0.005
        return equityDown || (t.ahead ?? 0) < -0.005
    }

    private var todays: [DealRecord] {
        deals.log.filter { Calendar.current.isDateInToday($0.date) }
    }

    var body: some View {
        // The deal's totals, worked out once per change and handed to everything that shows
        // them (they were recomputed for every number, accent and item card on the page).
        let totals = self.totals
        let warning = Self.warning(totals)
        let accent = warning ? Theme.planPink : Theme.lime
        NavigationStack(path: $path) {
            ScrollView {
                VStack(alignment: .leading, spacing: 32) {
                    VStack(alignment: .leading, spacing: 14) {
                        // First time here, with nothing in the deal yet: one line on how it works.
                        if !hintSeen && deals.deal.kind == .empty {
                            DealHint { withAnimation(.snappy) { hintSeen = true } }
                                .transition(.opacity.combined(with: .move(edge: .top)))
                        }
                        if !todays.isEmpty { TodayStrip(deals: todays) { path.append(DealRoute.history) } }
                        if !deals.parked.isEmpty { ParkedChip(count: deals.parked.count) { parkedList = true } }
                        BalanceCard(totals: totals, roundTo: roundTarget(totals), onRound: roundCash)
                            // Reports only when it crosses the top, not on every scroll frame.
                            .onGeometryChange(for: Bool.self) { $0.frame(in: .global).maxY < 150 } action: { gone in
                                withAnimation(reduceMotion ? nil : .snappy(duration: 0.25)) { pinned = gone && deals.deal.kind != .empty }
                            }
                    }
                    side(.incoming, totals: totals, accent: accent).reveal()
                    side(.outgoing, totals: totals, accent: accent).reveal()
                    photosSection(accent: accent).reveal()
                    notesSection(accent: accent).reveal()
                }
                .padding(.horizontal, 16)
                .padding(.top, 8)
                .padding(.bottom, 24)
                .background(alignment: .top) { DealBackdrop(accent: accent) }
            }
            // A tap on this tab (from anywhere) closes pushed pages and scrolls back to the top.
            .tabTopReset("deal", path: $path)
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
            .toolbar(pinned ? .hidden : .visible, for: .navigationBar)
            .overlay(alignment: .top) {
                if pinned {
                    // Tap to go back up to the full card (the same as tapping the Deal tab).
                    Button {
                        Router.shared.tabTap = TabTap(name: "deal", count: Router.shared.tabTap.count + 1)
                    } label: { PinnedBalance(totals: totals) }
                        .buttonStyle(.plain)
                        .accessibilityHint("Scrolls back to the top")
                        .padding(.horizontal, 16)
                        .padding(.top, 4)
                        .transition(.move(edge: .top).combined(with: .opacity))
                }
            }
            .safeAreaInset(edge: .bottom) {
                if deals.deal.kind != .empty { closeBar(totals, warning: warning) }
            }
            .tabBarClearance()
            .sheet(isPresented: $confirming) { DealCloseSheet() }
            .sheet(item: $picking) { side in DealPickerSheet(side: side) }
            .sheet(isPresented: $settings) { DealRatesSheet() }
            .navigationDestination(for: DealRoute.self) { _ in DealHistoryView() }
            .navigationDestination(for: DealRecord.self) { DealRecordDetail(recordId: $0.id) }
            .navigationDestination(for: String.self) { ProductDetailView(productId: $0) }
            .fullScreenCover(isPresented: $customer) { CustomerViewSheet(deal: deals.deal, rates: rates, totals: totals) }
            .sheet(isPresented: $parkedList) { ParkedDealsSheet() }
            .alert("Park this deal", isPresented: $parking) {
                TextField(ParkedDeal.defaultName(), text: $parkName)
                Button("Cancel", role: .cancel) { parkName = "" }
                Button("Park") {
                    let name = parkName
                    parkName = ""
                    withAnimation(.snappy) { deals.park(name: name) }
                    UIImpactFeedbackGenerator(style: .light).impactOccurred()
                }
            } message: {
                Text("Set it aside with its photos and notes, and start a fresh one. Pick it back up from Parked.")
            }
            .sheet(item: $detailItem) { item in
                // The card's full page (prices, history, eBay sales, graded values) in a sheet,
                // so the deal stays right where it was underneath.
                NavigationStack {
                    ProductDetailView(productId: item.product.id)
                        .navigationDestination(for: String.self) { ProductDetailView(productId: $0) }
                        .toolbar {
                            ToolbarItem(placement: .cancellationAction) { Button("Done") { detailItem = nil } }
                        }
                }
                .presentationDetents([.large])
                .presentationDragIndicator(.visible)
            }
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

    private func closeBar(_ totals: DealTotals, warning: Bool) -> some View {
        VStack(spacing: 8) {
        // The answer, always on screen: who pays and whether you come out ahead.
        HStack(spacing: 6) {
            Text(totals.cashLine).foregroundStyle(.white)
            if let ahead = totals.ahead {
                Text("·").foregroundStyle(Theme.muted)
                Text(ahead < 0 ? "Behind" : "Ahead").foregroundStyle(Theme.muted)
                Text(Format.signedMoney(ahead)).foregroundStyle(Theme.tone(ahead))
            } else if let net = totals.net {
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
            Button { parking = true } label: { Image(systemName: "bookmark") }
                .buttonStyle(Button3D(kind: .dark, fullWidth: false, height: 48))
                .accessibilityLabel("Park this deal to finish later")
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
    private func roundTarget(_ totals: DealTotals) -> Double? {
        let b = totals.balance
        let r = (abs(b) / 5).rounded() * 5
        guard deals.deal.kind != .empty, r >= 5, abs(abs(b) - r) > 0.004 else { return nil }
        return b < 0 ? -r : r
    }

    /// Round the cash by nudging the price of the biggest item: one going out if there is one,
    /// else one coming in. It becomes a typed price on that item, so you can see and undo it.
    private func roundCash() {
        let totals = self.totals
        guard let target = roundTarget(totals) else { return }
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
    private func photosSection(accent: Color) -> some View {
        VStack(alignment: .leading, spacing: 12) {
            VStack(alignment: .leading, spacing: 6) {
                HStack(spacing: 8) {
                    Image(systemName: "camera.fill").font(.system(size: 14, weight: .semibold)).foregroundStyle(accent)
                    Text("Photos").font(.display(24)).tracking(-0.6).displayTrim(24)
                    if !deals.deal.photos.isEmpty { MonoLabel(text: "\(deals.deal.photos.count)") }
                }
                Text("Document the deal: the cards on the table, a receipt, the customer's binder").font(.geist(12)).foregroundStyle(Theme.muted)
            }
            DealPhotosStrip(photos: deals.deal.photos, accountId: store.demo == nil ? deals.accountId : nil, accent: accent) { photos in
                deals.update { $0.photos = photos }
            }
        }
    }

    // MARK: Notes

    /// Your own notes on the deal (who it was with, how they paid); kept with it when it closes.
    private func notesSection(accent: Color) -> some View {
        VStack(alignment: .leading, spacing: 12) {
            HStack(spacing: 8) {
                Image(systemName: "note.text").font(.system(size: 14, weight: .semibold)).foregroundStyle(accent)
                Text("Notes").font(.display(24)).tracking(-0.6).displayTrim(24)
            }
            DealNotesField(notes: deals.deal.notes, prompt: "Who it was with, how they paid, anything to remember", accent: accent) { text in
                deals.update { $0.notes = text.isEmpty ? nil : text }
            }
        }
    }

    // MARK: A side of the deal

    @ViewBuilder private func side(_ side: DealSide, totals: DealTotals, accent: Color) -> some View {
        let incoming = side == .incoming
        let items = incoming ? deals.deal.incoming : deals.deal.outgoing
        let rate = incoming ? rates.in : rates.out
        let fallback = incoming ? defaultRates.in : defaultRates.out
        VStack(alignment: .leading, spacing: 12) {
            HStack(alignment: .lastTextBaseline) {
                VStack(alignment: .leading, spacing: 6) {
                    HStack(spacing: 8) {
                        Image(systemName: incoming ? "arrow.down.left" : "arrow.up.right")
                            .font(.system(size: 16, weight: .semibold))
                            .foregroundStyle(incoming ? accent : Theme.planPink)
                        Text(incoming ? "Coming in" : "Going out").font(.display(24)).tracking(-0.6).displayTrim(24)
                    }
                    Text(incoming ? "What the customer hands you" : "What you hand over").font(.geist(12)).foregroundStyle(Theme.muted)
                }
                Spacer(minLength: 8)
                Text(Format.money(incoming ? totals.inValue : totals.outValue))
                    .font(.display(26)).tracking(-0.7).monospacedDigit().displayTrim(26)
                    .contentTransition(.numericText())
                    .animation(.snappy, value: incoming ? totals.inValue : totals.outValue)
            }

            RateCard(rate: rate, fallback: fallback, accent: accent, result: deals.deal.kind == .empty ? nil : totals.summary) { r in
                deals.update { d in if incoming { d.rateIn = r } else { d.rateOut = r } }
            }

            ForEach(items) { item in
                DealItemCard(item: item, incoming: incoming, rate: rate, cost: incoming ? nil : deals.cost(of: item, in: store), accent: accent,
                             tracked: deals.tracked(item, side: side), asksCost: deals.defaults.asksCost,
                             onOpen: item.product.id.hasPrefix("custom:") ? nil : { detailItem = item },
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
                .swipeToRemove(item.product.name) {
                    withAnimation(.snappy) {
                        deals.update { d in
                            if incoming { d.incoming.removeAll { $0.key == item.key } } else { d.outgoing.removeAll { $0.key == item.key } }
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
        deals.addScanned(c, read: read, to: side, store: store)
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

/// "TODAY  3 deals  Ahead +$140  Cash +$120": today's closed deals at a glance.
private struct TodayStrip: View {
    var deals: [DealRecord]
    var onOpen: () -> Void

    var body: some View {
        let cash = deals.reduce(0) { $0 + $1.balance }
        let known = deals.compactMap(\.aheadTotal)
        let ahead = known.reduce(0, +)
        let profit = deals.reduce(0) { $0 + ($1.profit ?? 0) }
        Button(action: onOpen) {
            HStack(spacing: 12) {
                MonoLabel(text: "Today")
                Text("\(deals.count) deal\(deals.count == 1 ? "" : "s")").foregroundStyle(.white)
                // How far ahead today's deals left you; profit when none of them know it.
                if !known.isEmpty {
                    HStack(spacing: 4) {
                        Text("Ahead").foregroundStyle(Theme.muted)
                        Text(Format.signedMoney(ahead)).foregroundStyle(Theme.tone(ahead))
                    }
                } else {
                    HStack(spacing: 4) {
                        Text("Profit").foregroundStyle(Theme.muted)
                        Text(Format.signedMoney(profit)).foregroundStyle(Theme.tone(profit))
                    }
                }
                HStack(spacing: 4) {
                    Text("Cash").foregroundStyle(Theme.muted)
                    Text(Format.signedMoney(cash)).foregroundStyle(Theme.tone(cash))
                }
                Spacer(minLength: 0)
                Image(systemName: "chevron.right").font(.system(size: 11, weight: .semibold)).foregroundStyle(Theme.subtle)
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

    /// "Customer pays you $40 · ahead +$58", for under the slider.
    var summary: String {
        if let ahead { return cashLine + " · \(ahead < 0 ? "behind" : "ahead") \(Format.signedMoney(ahead))" }
        return cashLine + (net.map { " · you're \(Format.signedMoney($0))" } ?? "")
    }

    /// "You come out ahead +$1,701" when every cost is known, else the older verdict.
    var headline: String? {
        if let ahead { return "\(dealAheadTitle(ahead)) \(Format.signedMoney(ahead))" }
        return verdict
    }

    /// The value gained that's only on paper (market value, not cash), when there is some.
    var onPaper: Double? {
        ahead != nil && showsEquity && equity > 0.005 ? equity : nil
    }
}

/// What each number means, one sentence each (tap a label to read it).
enum DealTerm: String {
    case verdict, ahead, cash, comingIn, goingOut, profit, value, rate

    var title: String {
        switch self {
        case .verdict: return "Ahead or behind"
        case .ahead: return "Ahead or behind"
        case .cash: return "Cash"
        case .comingIn: return "Coming in"
        case .goingOut: return "Going out"
        case .profit: return "Sale profit"
        case .value: return "Trade-in value"
        case .rate: return "Share of market"
        }
    }

    var explanation: String {
        switch self {
        case .verdict: return "Your profit on what you hand over plus the value you gain on what comes in: how much better off you are after this deal, at market prices."
        case .ahead: return "Market value of what comes in, minus what you paid for what goes out, minus any cash you pay (plus any you get): your profit plus the value you gain."
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
        let down = (t.showsEquity && t.equity < -0.005) || (t.ahead ?? 0) < -0.005
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

            // How far ahead you come out, in plain English (pink when behind: it sits on the ink pill,
            // never on lime).
            if let verdict = t.headline {
                let score = t.ahead ?? t.net ?? 0
                HStack(spacing: 8) {
                    Image(systemName: score >= 0 ? "arrow.up.right" : "arrow.down.right").font(.system(size: 13, weight: .medium))
                    Text(verdict).font(.geist(15, .bold)).lineLimit(1).minimumScaleFactor(0.7)
                    TermInfo(term: t.ahead != nil ? .ahead : .verdict, color: score < -0.005 ? Theme.planPink : fill)
                }
                .foregroundStyle(score < -0.005 ? Theme.planPink : fill)
                .padding(.horizontal, 14).frame(height: 36)
                .background(Capsule().fill(ink))
                .padding(.top, 16)
                .contentTransition(.numericText())
                .animation(.snappy, value: t.ahead ?? t.net)
            }
            if let paper = t.onPaper {
                Text("Includes \(Format.money(paper)) on paper")
                    .font(.geist(12, .medium)).foregroundStyle(ink.opacity(0.7))
                    .padding(.top, 8)
            }
            if t.uncosted > 0 {
                Text("Add what you paid for every item to see your total")
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
                    .font(.display(60)).tracking(-2.4).monospacedDigit().foregroundStyle(ink).lineLimit(1).minimumScaleFactor(0.5)
                    .displayTrim(60)
                Spacer(minLength: 0)
                if let roundTo {
                    // A quiet outlined chip on the card: one line, the round figure.
                    Button(action: onRound) {
                        HStack(spacing: 5) {
                            Image(systemName: "arrow.up.arrow.down").font(.system(size: 11, weight: .semibold))
                            Text("Round to \(Format.money(abs(roundTo)))").font(.geist(13, .semibold)).monospacedDigit()
                        }
                        .foregroundStyle(ink)
                        .padding(.horizontal, 12).frame(height: 34)
                        .background(RoundedRectangle(cornerRadius: 10, style: .continuous).fill(ink.opacity(0.08)))
                        .overlay(RoundedRectangle(cornerRadius: 10, style: .continuous).strokeBorder(ink.opacity(0.35), lineWidth: 1))
                        .lineLimit(1).fixedSize()
                    }
                    .buttonStyle(ShutterStyle())
                    .transition(.scale.combined(with: .opacity))
                }
            }
            .padding(.top, 8)

            LazyVGrid(columns: [GridItem(.flexible(), spacing: 12), GridItem(.flexible(), spacing: 12)], alignment: .leading, spacing: 14) {
                stat("Coming in", .comingIn, Format.money(t.inValue), ink)
                stat("Going out", .goingOut, Format.money(t.outValue), ink)
                stat("Sale profit", .profit, t.profit.map { Format.signedMoney($0) } ?? "—", ink)
                stat("Trade-in value", .value, t.showsEquity ? Format.signedMoney(t.equity) : "—", ink)
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
                    Image(systemName: "arrow.turn.down.right").font(.system(size: 10, weight: .semibold)).foregroundStyle(Theme.subtle)
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
    /// Opens the card's full page in a sheet (nil for custom lines, which have none).
    var onOpen: (() -> Void)? = nil
    var onEbay: () -> Void
    var onRemove: () -> Void
    var onChange: (DealItem) -> Void
    @State private var priceText = ""
    @State private var rateText = ""
    @State private var costText = ""
    @State private var showCost = false
    @Environment(CollectionStore.self) private var store

    /// What this line is, graded or not: a slab coming in carries its grade; a copy going out
    /// from your collection is that holding. Graded ones show as a slab with a grade tag.
    private var identity: HoldingIdentity? {
        if let key = item.holdingKey, let held = store.allHoldings.first(where: { $0.identity.key == key }) { return held.identity }
        if let g = item.grade {
            return HoldingIdentity(productId: item.product.id, printing: item.printing, condition: "Near Mint", gradeCompany: g.company, grade: g.grade)
        }
        return nil
    }

    /// "Sells fast" from eBay sales already cached (a card page or Owned sheet loaded them).
    private func sellSpeed(_ identity: HoldingIdentity?) -> Liquidity.Score? {
        guard !item.isCustom, EbaySalesCache.supports(item.product.id),
              let ebay = EbaySalesCache.cached(item.product.id, printing: item.printing, market: item.market) else { return nil }
        return Liquidity.score(ebay, grade: identity?.gradeLabel, today: Format.day())
    }

    var body: some View {
        let unit = item.unitPrice(side: rate)
        let identity = self.identity
        let total = item.total(side: rate)
        HStack(alignment: .top, spacing: 12) {
            // Tap the picture or the name to see the card's details (eBay sales and all).
            Button { onOpen?() } label: {
                HoldingArt(product: item.product, identity: identity, cornerRadius: 4, caption: false)
                    .frame(width: 52, height: 72)
            }
            .buttonStyle(.plain)
            .disabled(onOpen == nil)
            .accessibilityLabel("Details for \(item.product.name)")
            VStack(alignment: .leading, spacing: 0) {
                HStack(alignment: .top, spacing: 8) {
                    Button { onOpen?() } label: {
                        Text(item.product.name).font(.geist(14, .medium)).foregroundStyle(.white).lineLimit(2)
                            .multilineTextAlignment(.leading)
                    }
                    .buttonStyle(.plain)
                    .disabled(onOpen == nil)
                    Spacer(minLength: 0)
                    Button(action: onRemove) {
                        Image(systemName: "trash").font(.system(size: 13, weight: .medium)).foregroundStyle(Theme.subtle)
                            .frame(width: 28, height: 28)
                    }
                    .buttonStyle(.plain)
                    .accessibilityLabel("Remove \(item.product.name)")
                }
                if let label = identity?.gradeLabel {
                    Tag(text: label, tint: Theme.lime).padding(.top, 2).padding(.bottom, 4)
                }
                HStack(spacing: 5) {
                    if let market = item.market, let unit, abs(unit - market) > 0.004 {
                        Text(Format.money(market)).strikethrough().foregroundStyle(Theme.subtle)
                        Image(systemName: "arrow.right").font(.system(size: 9, weight: .semibold)).foregroundStyle(Theme.subtle)
                        Text(Format.money(unit)).foregroundStyle(.white).fontWeight(.semibold)
                        Text("\(Int((unit / market * 100).rounded()))%")
                            .font(.geist(10, .bold)).foregroundStyle(Theme.ink)
                            .padding(.horizontal, 5).frame(height: 16)
                            .background(Capsule().fill(accent))
                    } else {
                        Text(subtitle).foregroundStyle(Theme.muted)
                    }
                    if item.product.source == "tcgapi" || item.product.source == "sample" {
                        Text("·").foregroundStyle(Theme.muted)
                        Button("eBay sold", action: onEbay).foregroundStyle(.white.opacity(0.85)).buttonStyle(.plain)
                    }
                }
                .font(.geist(12)).monospacedDigit().lineLimit(1)
                .padding(.top, 2)

                // How easily it sells, only when its eBay sales are already here (never fetched per line).
                if let speed = sellSpeed(identity) {
                    SellSpeedMeter(score: speed, compact: true).padding(.top, 4)
                }

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
                tag(tracked ? "Not in Lucent · will be added" : "Not in Lucent · not tracked", icon: "exclamationmark.circle")
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
            Image(systemName: icon).font(.system(size: 10, weight: .semibold)).frame(width: 28, height: 30)
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

/// What the customer sees, full screen and calm: their cards (what they hand you, what they
/// get), each at the price you're paying or charging, and the cash, big. Never market prices,
/// rates, your costs, profit or value gained. Tap a card for a closer look; Flip turns the
/// page upside down so it reads the right way for someone across the table, while the buttons
/// stay the right way up for you at your end.
private struct CustomerViewSheet: View {
    var deal: DealState
    var rates: (in: Double, out: Double)
    var totals: DealTotals
    @Environment(\.dismiss) private var dismiss
    @Environment(\.accessibilityReduceMotion) private var reduceMotion
    @State private var flipped = false
    @State private var looking: Look?

    struct Look: Identifiable {
        var item: DealItem
        var incoming: Bool
        var rate: Double
        var id: String { (incoming ? "i" : "o") + item.key }
    }

    var body: some View {
        let b = totals.balance
        let even = abs(b) < 0.005
        ZStack(alignment: flipped ? .bottomTrailing : .topTrailing) {
            Theme.background.ignoresSafeArea()
            ScrollView {
                VStack(alignment: .leading, spacing: 36) {
                    if !deal.incoming.isEmpty { list("You hand us", deal.incoming, rates.in, incoming: true, total: totals.inValue) }
                    if !deal.outgoing.isEmpty { list("You get", deal.outgoing, rates.out, incoming: false, total: totals.outValue) }
                    VStack(spacing: 10) {
                        Text(even ? "Even swap" : (b > 0 ? "You pay" : "We pay you"))
                            .font(.display(30)).tracking(-0.8).foregroundStyle(.white)
                        if even {
                            Text("No cash changes hands").font(.geist(18)).foregroundStyle(Theme.muted)
                        } else {
                            Text(Format.money(abs(b))).font(.display(76)).tracking(-3).monospacedDigit().foregroundStyle(.white)
                                .lineLimit(1).minimumScaleFactor(0.5).displayTrim(76)
                        }
                    }
                    .frame(maxWidth: .infinity)
                    .padding(.vertical, 32)
                    .padding(.horizontal, 20)
                    .background(RoundedRectangle(cornerRadius: 26, style: .continuous).fill(Color.white.opacity(0.06)))
                }
                .padding(.horizontal, 20)
                .padding(.top, 64)
                .padding(.bottom, 40)
            }
            .rotationEffect(.degrees(flipped ? 180 : 0))
            // The controls stay the right way up for you, at whichever end is yours.
            HStack(spacing: 10) {
                Button {
                    withAnimation(reduceMotion ? nil : .spring(response: 0.5, dampingFraction: 0.88)) { flipped.toggle() }
                } label: {
                    Label(flipped ? "Flip back" : "Flip", systemImage: "arrow.up.arrow.down")
                        .font(.geist(16, .semibold)).foregroundStyle(.white)
                        .padding(.horizontal, 18).frame(height: 40)
                        .liquidGlass(in: Capsule())
                }
                .accessibilityHint("Turns the page around for the person across from you")
                Button("Done") { dismiss() }
                    .font(.geist(16, .semibold)).foregroundStyle(.white)
                    .padding(.horizontal, 18).frame(height: 40)
                    .liquidGlass(in: Capsule())
            }
            .padding(.horizontal, 16).padding(.vertical, 8)
        }
        .sensoryFeedback(.selection, trigger: flipped)
        .sheet(item: $looking) { look in
            CustomerCardSheet(item: look.item, incoming: look.incoming, rate: look.rate, flipped: flipped)
        }
        .preferredColorScheme(.dark)
    }

    private func list(_ title: String, _ items: [DealItem], _ rate: Double, incoming: Bool, total: Double) -> some View {
        VStack(alignment: .leading, spacing: 4) {
            HStack(alignment: .firstTextBaseline) {
                Text(title).font(.display(28)).tracking(-0.7).foregroundStyle(.white)
                Spacer(minLength: 8)
                Text(Format.money(total)).font(.geist(18, .medium)).monospacedDigit().foregroundStyle(Theme.muted)
            }
            .padding(.bottom, 8)
            ForEach(items) { i in
                Button { looking = Look(item: i, incoming: incoming, rate: rate) } label: {
                    HStack(spacing: 16) {
                        HoldingArt(product: i.product, identity: nil, cornerRadius: 4, caption: false).frame(width: 56, height: 78)
                        VStack(alignment: .leading, spacing: 4) {
                            Text(i.product.name).font(.geist(19, .medium)).foregroundStyle(.white)
                                .lineLimit(3).fixedSize(horizontal: false, vertical: true)
                                .multilineTextAlignment(.leading)
                            if i.qty > 1 {
                                Text("\(i.qty) × \(Format.money(i.unitPrice(side: rate)))").font(.geist(15)).monospacedDigit().foregroundStyle(Theme.muted)
                            }
                        }
                        Spacer(minLength: 8)
                        Text(Format.money(i.total(side: rate))).font(.geist(22, .semibold)).monospacedDigit().foregroundStyle(.white)
                            .lineLimit(1).fixedSize()
                    }
                    .padding(.vertical, 10)
                    .contentShape(Rectangle())
                }
                .buttonStyle(.plain)
                .disabled(i.isCustom)
                if i.id != items.last?.id { Divider().overlay(Color.white.opacity(0.1)) }
            }
        }
    }
}

/// One card from the customer view, up close: the art (lean it with a finger), what it is, and
/// the deal price. Like the customer view, never market prices, rates, costs or profit.
/// Follows the customer view's flip so it reads the right way for the customer too.
private struct CustomerCardSheet: View {
    var item: DealItem
    var incoming: Bool
    var rate: Double
    var flipped: Bool
    @Environment(\.dismiss) private var dismiss

    var body: some View {
        let p = item.product
        VStack(spacing: 0) {
            HStack {
                Spacer()
                Button("Done") { dismiss() }
                    .font(.geist(16, .semibold)).foregroundStyle(.white)
                    .padding(.horizontal, 18).frame(height: 40)
                    .liquidGlass(in: Capsule())
            }
            .padding(.horizontal, 16).padding(.top, 14)
            ScrollView {
                VStack(spacing: 22) {
                    art(p).padding(.top, 8)
                    VStack(spacing: 6) {
                        Text(p.name).font(.display(28)).tracking(-0.8).foregroundStyle(.white)
                            .multilineTextAlignment(.center)
                        let line = [p.setName, p.number.map { "#\($0)" }, item.printing].compactMap { $0 }.filter { !$0.isEmpty }
                        if !line.isEmpty {
                            Text(line.joined(separator: " · ")).font(.geist(15)).foregroundStyle(Theme.muted)
                                .multilineTextAlignment(.center)
                        }
                        if let g = item.grade {
                            Text("\(g.company) \(g.grade)").font(.mono(12)).tracking(1.2).foregroundStyle(.white)
                                .padding(.horizontal, 10).padding(.vertical, 5)
                                .background(Capsule().fill(Color.white.opacity(0.1)))
                                .padding(.top, 4)
                        }
                    }
                    .padding(.horizontal, 20)
                    VStack(spacing: 6) {
                        Text(incoming ? "We pay" : "Price").font(.mono(11)).tracking(1.4).textCase(.uppercase).foregroundStyle(Theme.muted)
                        Text(Format.money(item.total(side: rate))).font(.display(52)).tracking(-2).monospacedDigit().foregroundStyle(.white)
                            .lineLimit(1).minimumScaleFactor(0.5)
                        if item.qty > 1 {
                            Text("\(item.qty) × \(Format.money(item.unitPrice(side: rate)))").font(.geist(15)).monospacedDigit().foregroundStyle(Theme.muted)
                        }
                    }
                    .frame(maxWidth: .infinity)
                    .padding(.vertical, 22)
                    .sheetPanel(radius: 22)
                    .padding(.horizontal, 20)
                }
                .padding(.bottom, 32)
            }
        }
        .rotationEffect(.degrees(flipped ? 180 : 0))
        .presentationDetents([.fraction(0.93)])
        .presentationDragIndicator(.hidden)
        .glassSheet()
    }

    @ViewBuilder private func art(_ p: Product) -> some View {
        if p.isSealed {
            SealedWell(product: p, cornerRadius: 28, caption: true).frame(width: 260, height: 260)
        } else {
            HoloCard(foil: p.isFoil, textured: false, cornerRadius: 12) {
                ProductImage(product: p, cornerRadius: 13, large: true).frame(width: 240, height: 335)
            }
            .environment(\.imageMaxPixel, nil)
        }
    }
}

/// A deal's notes: one line until you tap in, then room to write. Saves a moment after you stop
/// typing and when you leave the field.
struct DealNotesField: View {
    var notes: String?
    var prompt: String
    var accent: Color = Theme.lime
    var onCommit: (String) -> Void
    @State private var text = ""
    @State private var committed: String?
    @State private var pending: Task<Void, Never>?
    @FocusState private var focused: Bool

    var body: some View {
        TextField("", text: $text, prompt: Text(prompt).foregroundColor(Theme.subtle), axis: .vertical)
            .font(.geist(15))
            .foregroundStyle(.white)
            .lineLimit(focused ? 3 ... 8 : 1 ... 1)
            .focused($focused)
            .padding(.horizontal, 14).padding(.vertical, 12)
            .background(RoundedRectangle(cornerRadius: 16, style: .continuous).fill(Theme.surface))
            .overlay(RoundedRectangle(cornerRadius: 16, style: .continuous).strokeBorder(focused ? accent.opacity(0.6) : Theme.border))
            .contentShape(Rectangle())
            .onTapGesture { focused = true }
            .onAppear { text = notes ?? "" }
            .onChange(of: text) { _, value in
                pending?.cancel()
                pending = Task {
                    try? await Task.sleep(nanoseconds: 600_000_000)
                    guard !Task.isCancelled else { return }
                    commit(value)
                }
            }
            .onChange(of: focused) { _, on in
                if !on {
                    pending?.cancel()
                    commit(text)
                }
            }
            // Changed elsewhere (cleared, parked, resumed, or on the website): show that instead.
            .onChange(of: notes) { _, value in
                let incoming = value ?? ""
                guard incoming != (committed ?? ""), incoming != text.trimmingCharacters(in: .whitespacesAndNewlines) else { return }
                pending?.cancel()
                committed = incoming
                text = incoming
            }
            .onDisappear {
                pending?.cancel()
                commit(text)
            }
    }

    private func commit(_ value: String) {
        let trimmed = value.trimmingCharacters(in: .whitespacesAndNewlines)
        guard trimmed != (notes ?? "").trimmingCharacters(in: .whitespacesAndNewlines) else { return }
        committed = trimmed
        onCommit(trimmed)
    }
}

/// "Parked (2)": deals set aside, one tap from the list.
private struct ParkedChip: View {
    var count: Int
    var onOpen: () -> Void

    var body: some View {
        Button(action: onOpen) {
            HStack(spacing: 8) {
                Image(systemName: "bookmark.fill").font(.system(size: 12, weight: .semibold)).foregroundStyle(Theme.lime)
                Text("Parked").foregroundStyle(.white)
                Text("(\(count))").foregroundStyle(Theme.muted)
                Image(systemName: "chevron.right").font(.system(size: 11, weight: .semibold)).foregroundStyle(Theme.subtle)
            }
            .font(.geist(13, .semibold)).monospacedDigit()
            .padding(.horizontal, 14)
            .frame(height: 36)
            .liquidGlass(in: Capsule())
        }
        .buttonStyle(.plain)
        .accessibilityLabel("Parked deals, \(count)")
    }
}

/// Deals set aside: resume one (an open deal is parked first, after asking) or delete it.
private struct ParkedDealsSheet: View {
    @Environment(\.dismiss) private var dismiss

    var body: some View {
        NavigationStack {
            ScrollView {
                VStack(alignment: .leading, spacing: 0) {
                    HStack(alignment: .firstTextBaseline) {
                        Text("Parked deals").font(.display(28)).tracking(-0.7)
                        Spacer()
                        Button("Done") { dismiss() }.font(.geist(16, .semibold)).foregroundStyle(.white)
                    }
                    Text("Deals you set aside to finish later, here or on the website.").font(.geist(14)).foregroundStyle(Theme.muted)
                        .padding(.top, 4)
                        .padding(.bottom, 18)
                    ParkedDealsList { dismiss() }
                }
                .padding(.horizontal, 16)
                .padding(.top, 28)
                .padding(.bottom, 16)
            }
            .toolbar(.hidden, for: .navigationBar)
        }
        .presentationDetents([.medium, .fraction(0.93)])
        .glassSheet()
    }
}

/// The parked deals as rows (a little fan of the cards, name, what and when, delete and Resume),
/// with the two questions they can ask. Used by the Parked sheet and the Parked section in
/// Closed deals; `onResumed` runs after a deal is back on the Deal page.
struct ParkedDealsList: View {
    var onResumed: () -> Void
    @Environment(DealStore.self) private var deals
    @State private var asking: ParkedDeal?
    @State private var deleting: ParkedDeal?

    var body: some View {
        VStack(spacing: 10) {
            if deals.parked.isEmpty {
                Text("Nothing parked.").font(.geist(14)).foregroundStyle(Theme.muted).padding(.vertical, 24)
                    .frame(maxWidth: .infinity)
            }
            ForEach(deals.parked) { entry in row(entry) }
        }
        .confirmationDialog("You have a deal open", isPresented: Binding(get: { asking != nil }, set: { if !$0 { asking = nil } }), titleVisibility: .visible, presenting: asking) { entry in
            Button("Park it and resume \(entry.name)") { resume(entry) }
            Button("Cancel", role: .cancel) {}
        } message: { _ in
            Text("It's parked first, so nothing is lost.")
        }
        .confirmationDialog("Delete this parked deal?", isPresented: Binding(get: { deleting != nil }, set: { if !$0 { deleting = nil } }), titleVisibility: .visible, presenting: deleting) { entry in
            Button("Delete \(entry.name)", role: .destructive) { withAnimation(.snappy) { deals.deleteParked(entry) } }
            Button("Cancel", role: .cancel) {}
        } message: { _ in
            Text("Its photos are deleted too.")
        }
    }

    private func row(_ entry: ParkedDeal) -> some View {
        let state = entry.state
        let items = state.incoming + state.outgoing
        let count = items.reduce(0) { $0 + $1.qty }
        let when = entry.date.formatted(.dateTime.month(.abbreviated).day().hour().minute())
        return HStack(spacing: 12) {
            ZStack {
                if items.isEmpty {
                    RoundedRectangle(cornerRadius: 6, style: .continuous).fill(Theme.well).frame(width: 40, height: 56)
                }
                ForEach(Array(items.prefix(3).enumerated()), id: \.offset) { i, item in
                    let off = Double(i) - Double(min(items.count, 3) - 1) / 2
                    HoldingArt(product: item.product, identity: nil, cornerRadius: 3, caption: false)
                        .frame(width: 40, height: 56)
                        .rotationEffect(.degrees(off * 9), anchor: .bottom)
                        .offset(x: off * 10)
                }
            }
            .frame(width: 64, height: 62)
            VStack(alignment: .leading, spacing: 3) {
                Text(entry.name).font(.geist(15, .semibold)).foregroundStyle(.white).lineLimit(1)
                Text("\(state.kind.noun) · \(count) item\(count == 1 ? "" : "s")")
                    .font(.geist(12)).foregroundStyle(Theme.muted).lineLimit(1)
                Text(when).font(.geist(12)).foregroundStyle(Theme.subtle).lineLimit(1)
            }
            Spacer(minLength: 6)
            Button { deleting = entry } label: {
                Image(systemName: "trash").font(.system(size: 14, weight: .medium)).foregroundStyle(Theme.subtle).frame(width: 34, height: 34)
            }
            .buttonStyle(.plain)
            .accessibilityLabel("Delete \(entry.name)")
            Button("Resume") {
                if deals.deal.hasContent { asking = entry } else { resume(entry) }
            }
            .buttonStyle(Button3D(kind: .lime, fullWidth: false, height: 38))
        }
        .padding(12)
        .sheetPanel(radius: 18)
    }

    private func resume(_ entry: ParkedDeal) {
        withAnimation(.snappy) { deals.resume(entry) }
        UIImpactFeedbackGenerator(style: .light).impactOccurred()
        onResumed()
    }
}

/// Swipe a deal card left to show a pink Remove button behind it; swipe back, or tap the card,
/// to close it. Only the card's offset moves while you drag. The trash icon on the card still works.
private struct SwipeToRemove: ViewModifier {
    var name: String
    var onRemove: () -> Void
    @State private var dragX: CGFloat = 0
    @State private var open = false
    @Environment(\.accessibilityReduceMotion) private var reduceMotion
    private let reveal: CGFloat = 92

    func body(content: Content) -> some View {
        let x = min(0, max(-reveal * 1.35, (open ? -reveal : 0) + dragX))
        content
            .overlay {
                // While open, a tap anywhere on the card closes it instead of acting on it.
                if open {
                    Color.clear.contentShape(Rectangle()).onTapGesture { snap(false) }
                }
            }
            .offset(x: x)
            .background(alignment: .trailing) {
                Button {
                    snap(false)
                    onRemove()
                } label: {
                    VStack(spacing: 5) {
                        Image(systemName: "trash.fill").font(.system(size: 16, weight: .semibold))
                        Text("Remove").font(.geist(12, .semibold))
                    }
                    .foregroundStyle(.white)
                    .frame(width: reveal - 8)
                    .frame(maxHeight: .infinity)
                    .background(RoundedRectangle(cornerRadius: 18, style: .continuous).fill(Theme.planPink))
                }
                .buttonStyle(.plain)
                .opacity(x < -1 ? 1 : 0)
                .accessibilityHidden(true)
            }
            .simultaneousGesture(
                DragGesture(minimumDistance: 18)
                    .onChanged { g in
                        // Only a sideways drag moves the card; an up-and-down one is the page scrolling.
                        guard abs(g.translation.width) > abs(g.translation.height) * 1.3 else { return }
                        dragX = g.translation.width
                    }
                    .onEnded { g in
                        guard dragX != 0 else { return }
                        let end = (open ? -reveal : 0) + g.predictedEndTranslation.width
                        snap(end < -reveal / 2)
                    }
            )
            .accessibilityAction(named: "Remove \(name)") { onRemove() }
    }

    private func snap(_ isOpen: Bool) {
        withAnimation(reduceMotion ? nil : .snappy(duration: 0.25)) {
            open = isOpen
            dragX = 0
        }
    }
}

extension View {
    /// Swipe left to reveal a Remove button (see SwipeToRemove).
    fileprivate func swipeToRemove(_ name: String, onRemove: @escaping () -> Void) -> some View {
        modifier(SwipeToRemove(name: name, onRemove: onRemove))
    }
}

/// The one-time hint on an empty Deal tab.
private struct DealHint: View {
    var onDismiss: () -> Void

    var body: some View {
        HStack(alignment: .top, spacing: 12) {
            Image(systemName: "arrow.left.arrow.right").font(.system(size: 15, weight: .semibold)).foregroundStyle(Theme.lime)
                .frame(width: 34, height: 34)
                .background(Theme.lime.opacity(0.12), in: Circle())
            VStack(alignment: .leading, spacing: 3) {
                Text("How a deal works").font(.geist(14, .semibold))
                Text("Add what's coming in and what's going out (search or scan). We'll work out the cash, your profit and whether it's fair.")
                    .font(.geist(13)).foregroundStyle(Theme.muted).fixedSize(horizontal: false, vertical: true)
            }
            Spacer(minLength: 4)
            Button(action: onDismiss) {
                Image(systemName: "xmark").font(.system(size: 11, weight: .semibold)).foregroundStyle(Theme.muted)
                    .frame(width: 28, height: 28)
            }
            .buttonStyle(.plain)
            .accessibilityLabel("Got it")
        }
        .surface(radius: 18, padding: 14)
    }
}

/// The balance card, compact, pinned to the top once the full card scrolls away: the deal kind,
/// the cash figure and how far ahead it leaves you, on the card's lime (pink when behind).
private struct PinnedBalance: View {
    var totals: DealTotals

    var body: some View {
        let b = totals.balance
        let down = (totals.showsEquity && totals.equity < -0.005) || (totals.ahead ?? 0) < -0.005
        let fill = down ? Theme.planPink : Theme.lime
        let ink = down ? Color.white : Theme.ink
        HStack(alignment: .center, spacing: 12) {
            VStack(alignment: .leading, spacing: 2) {
                Text((abs(b) < 0.005 ? "Settled · no cash" : (b > 0 ? "Customer pays you" : "You pay the customer")).uppercased())
                    .font(.mono(10)).tracking(1).opacity(0.7)
                Text(Format.money(abs(b))).font(.display(26)).tracking(-0.8).monospacedDigit().displayTrim(26)
            }
            Spacer(minLength: 8)
            if let ahead = totals.ahead {
                VStack(alignment: .trailing, spacing: 2) {
                    Text(ahead >= 0 ? "AHEAD" : "BEHIND").font(.mono(10)).tracking(1).opacity(0.7)
                    Text(Format.signedMoney(ahead)).font(.geist(17, .semibold)).monospacedDigit()
                }
            }
        }
        .foregroundStyle(ink)
        .lineLimit(1).minimumScaleFactor(0.7)
        .padding(.horizontal, 16).padding(.vertical, 12)
        .background(RoundedRectangle(cornerRadius: 20, style: .continuous).fill(fill))
        .shadow(color: .black.opacity(0.35), radius: 14, y: 8)
        .accessibilityElement(children: .combine)
    }
}
