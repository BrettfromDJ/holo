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
    /// Asking before clearing the whole deal.
    @State private var clearing = false
    @State private var parkName = ""
    @State private var parkedList = false
    /// Typing the cash the two of you agreed on (tap the big figure on the balance card).
    @State private var editingCash = false
    @State private var cashText = ""
    /// The agreed market value box (tap Market value on the deal card).
    @State private var editingMarket = false
    @State private var marketText = ""
    /// The tab bar brought back over a docked deal bar ("Show tabs"); off again once the deal empties
    /// or the Deal tab is tapped.
    @State private var showTabs = false
    /// The deal's ⋯ at the top right (park, clear, round up, the agreed cash).
    @State private var dealMenu = false
    /// A row's ⋯ (its rarer actions), and the price sheet a row's price opens.
    @State private var actingItem: DealItem?
    @State private var pricingItem: DealItem?
    /// Photos and notes, folded into one row until opened (open when the deal has either).
    @State private var extrasOpen = false
    /// The path picked when the deal started: buying, selling or trading ("" = not picked yet:
    /// the page asks first). Kept on the phone so the page comes back the same.
    @AppStorage("deal-path") private var pathRaw = ""
    @State private var pathMenu = false
    /// The new flow: leaving a deal (park / discard), naming it, and typing another rate.
    @State private var leaving = false
    @State private var dealOptions = false
    /// Switching to this kind would drop the other side's cards: the alert asking first.
    @State private var confirmKind: DealKind?
    /// A switch to Buy or Sell that would drop the other side's cards: asked first.

    @State private var renaming = false
    @State private var nameText = ""
    @AppStorage("deal-name") private var dealName = ""
    @State private var rateSide: DealSide?
    /// Finalize deal: the final amount (rounded or typed) before recording.
    @State private var finalizing = false

    /// The path in use: the one picked, else what the deal's items say it is.
    private var dealPath: DealKind? {
        if let k = DealKind(rawValue: pathRaw), k != .empty { return k }
        return deals.deal.kind == .empty ? nil : deals.deal.kind
    }

    private var rates: (in: Double, out: Double) { deals.rates }
    private var defaultRates: (in: Double, out: Double) {
        var d = deals.deal
        d.rateIn = nil
        d.rateOut = nil
        return deals.rates(for: d)
    }

    /// The deal at its agreed cash, when one is set (the stored prices never change).
    private var agreed: AgreedDeal { deals.deal.agreed(rates: rates) }
    private var totals: DealTotals { DealTotals(agreed.deal, rates: rates, cost: { deals.cost(of: $0, in: store) }) }

    /// The deal bar takes the tab bar's place while a deal has items (until "Show tabs"), on the
    /// Deal page itself, not a page pushed on it.
    private var docked: Bool { false }
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
        let agreed = self.agreed
        let totals = DealTotals(agreed.deal, rates: rates, cost: { deals.cost(of: $0, in: store) })
        let role = deals.role
        // A collector's read on the deal: the vendor's offer and prices against market.
        let read: CollectorRead? = role == .collector && deals.deal.kind != .empty ? CollectorRead(agreed.deal, totals: totals, rates: rates) : nil
        // Pink warnings are a vendor's (selling to a vendor always comes in under market).
        let warning = role == .vendor && Self.warning(totals)
        let accent = warning ? Theme.planPink : Theme.lime
        NavigationStack(path: $path) {
            // The owner's flow (Nov 2026): pick what you're doing, then one simple page per deal.
            Group {
                if let p = dealPath {
                    DealEditorPage(path: p, name: dealName,
                                   onScan: { scanning = $0 },
                                   onAdd: { picking = $0 },
                                   onEditCard: { pricingItem = $0 },
                                   onCustomRate: { rateSide = $0 },
                                   onRename: { nameText = dealName; renaming = true },
                                   onMore: { dealOptions = true },
                                   onMakeTrade: { side in
                                       withAnimation(.snappy) { pathRaw = DealKind.trade.rawValue }
                                       // The add sheet for the new side, once the page has turned into a trade.
                                       Task {
                                           try? await Task.sleep(nanoseconds: 300_000_000)
                                           picking = side
                                       }
                                   },
                                   onReview: { Haptics.tap(); confirming = true },
                                   onPark: { parkNow() },
                                   card: { rate in
                                       AnyView(BalanceCard(totals: totals, role: role, read: read, roundTo: nil, onRound: {},
                                                           agreed: agreed.side != nil, share: agreed.share,
                                                           onEditCash: { startEditingCash(totals) }, onClearAgreed: clearAgreed,
                                                           extra: rate,
                                                           onEditMarket: { startEditingMarket(totals) },
                                                           marketAgreed: marketSide.map { deals.marketAgreed(on: $0) } ?? false,
                                                           tagKind: dealPath))
                                   })
                        .alert(confirmKind.map { dropTitle($0) } ?? "", isPresented: Binding(get: { confirmKind != nil }, set: { if !$0 { confirmKind = nil } })) {
                            Button("Cancel", role: .cancel) { confirmKind = nil }
                            Button("Remove and switch", role: .destructive) {
                                if let k = confirmKind { switchDropping(to: k) }
                                confirmKind = nil
                            }
                        } message: {
                            Text("This deal becomes \(confirmKind.map { Self.pathTitle($0).lowercased() } ?? "") only.")
                        }
                        .toolbar {
                            ToolbarItem(placement: .topBarLeading) {
                                Button {
                                    Haptics.tap()
                                    if deals.deal.hasContent { leaving = true } else { withAnimation(.snappy) { pathRaw = "" } }
                                } label: { Image(systemName: "chevron.left") }
                                .accessibilityLabel("Leave this deal")
                            }
                            ToolbarItem(placement: .topBarTrailing) {
                                Button { settings = true } label: { Image(systemName: "slider.horizontal.3") }.accessibilityLabel("Deal settings")
                            }
                        }
                } else {
                    DealStartPage(onPick: { k in
                        Haptics.tap()
                        withAnimation(.snappy) { pathRaw = k.rawValue }
                    }, onParkedAll: { parkedList = true },
                       onHistory: { path.append(DealRoute.history) },
                       onRecord: { path.append($0) })
                        .pageTitle("Deal")
                        .toolbar {
                            ToolbarItem(placement: .topBarLeading) {
                                Button { path.append(DealRoute.history) } label: { Image(systemName: "clock.arrow.circlepath") }.accessibilityLabel("Closed deals")
                            }
                            ToolbarItem(placement: .topBarTrailing) {
                                Button { settings = true } label: { Image(systemName: "slider.horizontal.3") }.accessibilityLabel("Deal settings")
                            }
                        }
                }
            }
            .background(alignment: .top) { DealBackdrop(accent: accent) }
            .background(Theme.background)
            // A tap on this tab (from anywhere) closes pushed pages and scrolls back to the top.
            .tabTopReset("deal", path: $path)
            .scrollDismissesKeyboard(.interactively)
            .toolbar {
                ToolbarItemGroup(placement: .keyboard) {
                    Spacer()
                    Button("Done") {
                        UIApplication.shared.sendAction(#selector(UIResponder.resignFirstResponder), to: nil, from: nil, for: nil)
                    }
                    .font(.geist(16, .semibold))
                }
            }
            .imageMaxPixel(360)
            .tint(Theme.lime)
            .navigationBarTitleDisplayMode(.inline)
            .actionsSheet(isPresented: $leaving, title: "Leave this deal?") {
                [[SheetAction(title: "Save for later", icon: "bookmark") { parkNow() }],
                 [SheetAction(title: "Discard deal", icon: "trash", destructive: true) { discardDeal() }]]
            }
            .actionsSheet(isPresented: $dealOptions, title: "This deal") {
                [[SheetAction(title: dealName.isEmpty ? "Name deal" : "Rename deal", icon: "pencil") { nameText = dealName; renaming = true },
                  SheetAction(title: "Change deal type", icon: "arrow.left.arrow.right",
                              children: [[DealKind.buy, .sell, .trade].map { k in kindRow(k) }])]
                 + (deals.deal.hasContent ? [SheetAction(title: "Save for later", icon: "bookmark") { parkNow() }] : []),
                 [SheetAction(title: "Delete deal", icon: "trash", destructive: true) { discardDeal() }]]
            }
            .alert("Name this deal", isPresented: $renaming) {
                TextField("Untitled deal", text: $nameText)
                Button("Cancel", role: .cancel) {}
                Button("Save") { dealName = nameText.trimmingCharacters(in: .whitespaces) }
            }
            .sheet(item: $rateSide) { side in
                let r = side == .incoming ? rates.in : rates.out
                DealRateSheet(title: "Set default rate", rate: r) { v in
                    deals.update { d in if side == .incoming { d.rateIn = v } else { d.rateOut = v } }
                }
            }
            .toolbar(pinned ? .hidden : .visible, for: .navigationBar)
            .overlay(alignment: .top) {
                if pinned {
                    // Tap to go back up to the full card (the same as tapping the Deal tab).
                    Button {
                        Router.shared.tabTap = TabTap(name: "deal", count: Router.shared.tabTap.count + 1)
                    } label: { PinnedBalance(totals: totals, role: role, read: read) }
                        .buttonStyle(.plain)
                        .accessibilityHint("Scrolls back to the top")
                        .padding(.horizontal, 16)
                        .padding(.top, 4)
                        .transition(.move(edge: .top).combined(with: .opacity))
                }
            }
            .safeAreaInset(edge: .bottom, spacing: 0) { Color.clear.frame(height: docked ? 0 : HoloTabBar<Int>.clearance) }
            .actionsSheet(isPresented: $dealMenu, title: "This deal") { dealActions(totals) }
            .actionsSheet(isPresented: $pathMenu, title: "What kind of deal?") {
                [[DealKind.buy, .sell, .trade].map { k in
                    SheetAction(title: Self.pathTitle(k), subtitle: Self.pathLine(k), checked: dealPath == k) {
                        withAnimation(.snappy) { pathRaw = k.rawValue }
                    }
                }]
            }
            .actionsSheet(item: $actingItem, title: { $0.product.name }, product: { $0.product }) { itemActions($0) }
            .sheet(item: $pricingItem) { item in
                let incoming = deals.deal.incoming.contains { $0.key == item.key }
                DealCardSheet(item: item, rate: incoming ? rates.in : rates.out,
                              onSave: { replace($0) }, onRemove: { remove(item) },
                              selling: !incoming,
                              collectionCost: item.holdingKey != nil ? deals.cost(of: item, in: store) : nil,
                              onOpen: item.product.id.hasPrefix("custom:") ? nil : {
                                  // Once this sheet is down, the card's page in its own sheet.
                                  Task {
                                      try? await Task.sleep(nanoseconds: 350_000_000)
                                      detailItem = item
                                  }
                              })
            }
            .onAppear { if !deals.deal.photos.isEmpty || deals.deal.notes != nil { extrasOpen = true } }
            .sheet(isPresented: $confirming) { DealCloseSheet() }
            .sheet(item: $picking) { side in
                DealPickerSheet(side: side, onScan: {
                    picking = nil
                    // Once the sheet is down, the scanner for that side.
                    Task {
                        try? await Task.sleep(nanoseconds: 350_000_000)
                        scanning = side
                    }
                })
            }
            .sheet(isPresented: $settings) { DealRatesSheet() }
            .navigationDestination(for: DealRoute.self) { _ in DealHistoryView() }
            .navigationDestination(for: DealRecord.self) { DealRecordDetail(recordId: $0.id) }
            .navigationDestination(for: String.self) { ProductDetailView(productId: $0) }
            .fullScreenCover(isPresented: $customer) { CustomerViewSheet(deal: agreed.deal, rates: rates, totals: totals) }
            .alert("Agreed market value", isPresented: $editingMarket) {
                TextField("0.00", text: $marketText).keyboardType(.decimalPad)
                Button("Cancel", role: .cancel) { marketText = "" }
                if let side = marketSide, deals.marketAgreed(on: side) {
                    Button("Back to catalog prices") {
                        marketText = ""
                        withAnimation(.snappy) { deals.resetMarket(on: side) }
                    }
                }
                Button("Set") {
                    let v = MoneyField.value(marketText)
                    marketText = ""
                    if let v, let side = marketSide { withAnimation(.snappy) { deals.setAgreedMarket(v, on: side) } }
                }
            } message: {
                Text("What the cards are worth, as you both agreed. Cards priced at a % of market follow it.")
            }
            .alert("Agreed cash", isPresented: $editingCash) {
                TextField("0.00", text: $cashText).keyboardType(.decimalPad)
                Button("Cancel", role: .cancel) { cashText = "" }
                Button("Set") { setAgreedCash(totals) }
            } message: {
                Text(agreedPrompt(totals))
            }
            .task {
                // Screenshots: open the customer view (-HoloDealCustomer) or Closed deals (-HoloDealHistory).
                let args = ProcessInfo.processInfo.arguments
                guard args.contains("-HoloDealCustomer") || args.contains("-HoloDealHistory") else { return }
                try? await Task.sleep(nanoseconds: 1_500_000_000)
                if args.contains("-HoloDealCustomer") { customer = true } else { path.append(DealRoute.history) }
            }
            .sheet(isPresented: $parkedList) { ParkedDealsSheet() }
            .alert("Save for later", isPresented: $parking) {
                TextField(ParkedDeal.defaultName(), text: $parkName)
                Button("Cancel", role: .cancel) { parkName = "" }
                Button("Save") {
                    let name = parkName
                    parkName = ""
                    withAnimation(.snappy) { deals.park(name: name) }
                    Haptics.tap()
                }
            } message: {
                Text("Set it aside with its photos and notes, and start a fresh one. Pick it back up from Saved for\u{00A0}later.")
            }
            .sheet(item: $detailItem) { item in
                // The card's full page (prices, history, eBay sales, graded values) in a sheet,
                // so the deal stays right where it was underneath.
                NavigationStack {
                    ProductDetailView(productId: item.product.id)
                        .navigationDestination(for: String.self) { ProductDetailView(productId: $0) }
                        .toolbar {
                            ToolbarItem(placement: .confirmationAction) { Button("Done") { detailItem = nil } }
                        }
                        .environment(\.cardPageInSheet, true)
                }
                .presentationDetents([.fraction(0.93)])
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
                .presentationDetents([.medium, .fraction(0.93)])
                .glassSheet()
            }
            .fullScreenCover(item: $scanning) { side in
                ScanView(dealSide: side, onPick: { candidate, read in addScan(candidate, read: read, to: side) })
            }
        }
        // The tab bar hides only while this page shows a docked deal bar. MainTabView only reads
        // this while the Deal tab is the one showing, so every other tab always keeps its tab bar.
        .onAppear { Router.shared.dealDocked = docked }
        .onChange(of: docked) { _, on in Router.shared.dealDocked = on }
        .onChange(of: deals.deal.kind == .empty) { was, empty in
            if empty { showTabs = false }
            // A deal that had cards and is now empty (closed, parked or cleared): next time, ask again.
            if empty && !was { pathRaw = ""; dealName = "" }
        }
        // Tapping the Deal tab goes back into the deal: the deal bar docks again.
        .onChange(of: Router.shared.tabTap) { _, tap in if tap.name == "deal" { showTabs = false } }
    }

    // MARK: The path

    static func pathTitle(_ k: DealKind) -> String {
        switch k {
        case .buy: return "Buying"
        case .sell: return "Selling"
        case .trade: return "Trading"
        case .empty: return "Deal"
        }
    }
    static func pathLine(_ k: DealKind) -> String {
        switch k {
        case .buy: return "Cards come in, you pay"
        case .sell: return "Cards go out, they pay"
        case .trade: return "Cards both ways, cash evens it out"
        case .empty: return ""
        }
    }

    /// "Buying ▾" at the top: switch the kind of deal without losing the cards.
    private func pathChip(_ path: DealKind) -> some View {
        Button { Haptics.tap(); pathMenu = true } label: {
            HStack(spacing: 6) {
                Text(Self.pathTitle(path)).font(.geist(15, .semibold)).foregroundStyle(.white)
                Image(systemName: "chevron.down").font(.system(size: 11, weight: .bold)).foregroundStyle(Theme.muted)
            }
            .padding(.horizontal, 14).frame(height: 36)
            .liquidGlass(in: Capsule())
            .contentShape(Capsule())
        }
        .buttonStyle(.plain)
        .accessibilityLabel("Kind of deal: \(Self.pathTitle(path))")
        .accessibilityHint("Change it")
    }

    // MARK: The receipt bar

    /// Pinned above the tab bar: the sum (in − out), who pays and how much (tap it to type the
    /// cash you agreed on), the one verdict, and Close. Park, clear and round up are in the ⋯.
    private func receiptBar(_ totals: DealTotals, warning: Bool) -> some View {
        let b = totals.balance
        let cashLabel = abs(b) < 0.005 ? "Even swap" : (b > 0 ? "They pay" : "You pay")
        let second: (text: String, value: Double)? = {
            if deals.role == .collector {
                let net = CollectorRead(agreed.deal, totals: totals, rates: rates).net
                return (abs(net) < 0.005 ? "At market" : "\(Format.money(abs(net))) \(net < 0 ? "under" : "over") market", net)
            }
            if let ahead = totals.ahead { return ("\(Format.money(abs(ahead))) \(ahead < 0 ? "behind" : "ahead")", ahead) }
            if let net = totals.net { return ("\(Format.signedMoney(net)) on the deal", net) }
            return nil
        }()
        let sum = [totals.inValue > 0 ? "In \(Format.money(totals.inValue))" : nil,
                   totals.outValue > 0 ? "Out \(Format.money(totals.outValue))" : nil].compactMap { $0 }.joined(separator: " − ")
        return HStack(alignment: .center, spacing: 12) {
            Button { startEditingCash(totals) } label: {
                if deals.deal.kind == .empty {
                    VStack(alignment: .leading, spacing: 2) {
                        Text("Add both sides").font(.geist(11)).foregroundStyle(Theme.subtle)
                        HStack(alignment: .firstTextBaseline, spacing: 6) {
                            Text("Cash").font(.geist(13, .medium)).foregroundStyle(Theme.muted)
                            Text("$0").font(.display(24)).tracking(-0.7).foregroundStyle(.white.opacity(0.5))
                        }
                    }
                } else {
                VStack(alignment: .leading, spacing: 2) {
                    Text(sum).font(.geist(11)).monospacedDigit().foregroundStyle(Theme.subtle).lineLimit(1)
                    HStack(alignment: .firstTextBaseline, spacing: 6) {
                        Text(cashLabel).font(.geist(13, .medium)).foregroundStyle(Theme.muted)
                        Text(abs(b) < 0.005 ? "$0" : Format.money(abs(b)))
                            .font(.display(24)).tracking(-0.7).monospacedDigit().foregroundStyle(.white)
                            .contentTransition(.numericText())
                    }
                    if let second {
                        Text(second.text + (totals.belowCost > 0 ? " · \(totals.belowCost) below cost" : ""))
                            .font(.geist(12, .medium)).monospacedDigit()
                            .foregroundStyle(abs(second.value) < 0.005 ? Theme.muted : Theme.tone(second.value))
                    } else if totals.belowCost > 0 {
                        Text("\(totals.belowCost) below cost").font(.geist(12, .medium)).foregroundStyle(Theme.planPink)
                    }
                }
                .lineLimit(1).minimumScaleFactor(0.75)
                .contentShape(Rectangle())
                }
            }
            .buttonStyle(.plain)
            .disabled(deals.deal.kind == .empty)
            .accessibilityHint("Type the cash you agreed on")
            .animation(.snappy, value: totals.balance)
            Spacer(minLength: 0)
            Button { Haptics.tap(); confirming = true } label: {
                Text(unpriced ? "Price all" : "Close \(deals.deal.kind.noun.lowercased())")
                    .font(.geist(16, .semibold)).foregroundStyle(warning ? .white : Theme.ink)
                    .lineLimit(1).minimumScaleFactor(0.8)
                    .padding(.horizontal, 22).frame(height: 50)
                    .background(Capsule().fill(warning ? Theme.planPink : Theme.lime))
                    .contentShape(Capsule())
            }
            .buttonStyle(.plain)
            .disabled(unpriced || deals.deal.kind == .empty)
            .opacity(unpriced || deals.deal.kind == .empty ? 0.45 : 1)
        }
        .padding(.leading, 18).padding(.trailing, 10).padding(.vertical, 10)
        .liquidGlass(in: RoundedRectangle(cornerRadius: 30, style: .continuous))
        .overlay(RoundedRectangle(cornerRadius: 30, style: .continuous).strokeBorder(Color.white.opacity(0.08), lineWidth: 1))
    }

    /// The deal's ⋯: round up or type the cash, park it, clear it.
    private func dealActions(_ totals: DealTotals) -> [[SheetAction]] {
        var cash: [SheetAction] = []
        if let target = roundTarget(totals) {
            cash.append(SheetAction(title: "Round up to \(Format.money(abs(target)))", icon: "arrow.up") { roundCash() })
        }
        cash.append(SheetAction(title: "Type the agreed cash", icon: "pencil") { startEditingCash(totals) })
        if deals.deal.agreedCash != nil {
            cash.append(SheetAction(title: "Clear the agreed cash", icon: "xmark") { clearAgreed() })
        }
        return [cash, [
            SheetAction(title: "Save for later", icon: "bookmark") { parking = true },
        ], [
            SheetAction(title: "Clear this deal", icon: "trash", destructive: true) {
                let photos = deals.deal.photos
                withAnimation(.snappy) { deals.update { $0 = DealState() } }
                Task { for p in photos { await DealPhotos.delete(p) } }
            },
        ]]
    }

    /// A row's ⋯: price, quantity, collection, card details, remove.
    private func itemActions(_ item: DealItem) -> [[SheetAction]] {
        let incoming = deals.deal.incoming.contains { $0.key == item.key }
        let tracked = deals.tracked(item, side: incoming ? .incoming : .outgoing)
        var main: [SheetAction] = [SheetAction(title: "Set its price", icon: "dollarsign") { pricingItem = item }]
        if item.price != nil || item.rate != nil {
            let r = incoming ? rates.in : rates.out
            main.append(SheetAction(title: "Use \(Int((r * 100).rounded()))% of market", icon: "arrow.uturn.backward") {
                var c = item
                c.price = nil
                c.rate = nil
                replace(c)
            })
        }
        if item.qty < (item.maxQty ?? 999) {
            main.append(SheetAction(title: "One more", subtitle: "\(item.qty) now", icon: "plus") { var c = item; c.qty += 1; replace(c) })
        }
        if item.qty > 1 {
            main.append(SheetAction(title: "One fewer", subtitle: "\(item.qty) now", icon: "minus") { var c = item; c.qty -= 1; replace(c) })
        }
        if incoming && !item.isCustom {
            main.append(SheetAction(title: tracked ? "Don't add to collection" : "Add to collection", icon: tracked ? "minus.circle" : "plus.circle") {
                var c = item
                c.track = !tracked
                replace(c)
            })
        }
        var more: [SheetAction] = []
        if !item.product.id.hasPrefix("custom:") {
            more.append(SheetAction(title: "Card details", icon: "rectangle.portrait") { detailItem = item })
        }
        return [main, more, [
            SheetAction(title: "Remove from deal", icon: "trash", destructive: true) { remove(item) },
        ]].filter { !$0.isEmpty }
    }

    /// Park the deal under its name (or today's) and go back to the start.
    /// A deal type in the ⋯ sheet. Going to Buy or Sell when the other side has cards asks first,
    /// on a page of the same sheet (a second sheet raised as this one closed looped); nothing
    /// switches by itself as cards come and go.
    private func kindRow(_ k: DealKind) -> SheetAction {
        let dropping = k == .buy ? deals.deal.outgoing : k == .sell ? deals.deal.incoming : []
        if dealPath == k || dropping.isEmpty {
            return SheetAction(title: Self.pathTitle(k), checked: dealPath == k) {
                guard dealPath != k else { return }
                withAnimation(.snappy) { pathRaw = k.rawValue }
            }
        }
        // Asked in a plain alert in the middle of the screen (the owner's call), once the ⋯ sheet
        // has fully gone (an alert raised while it was still closing didn't show).
        return SheetAction(title: Self.pathTitle(k)) {
            Task {
                try? await Task.sleep(nanoseconds: 400_000_000)
                confirmKind = k
            }
        }
    }

    /// The alert's words for switching to a kind that drops a side.
    private func dropTitle(_ k: DealKind) -> String {
        let dropping = k == .buy ? deals.deal.outgoing : deals.deal.incoming
        let n = dropping.reduce(0) { $0 + $1.qty }
        return "Remove the \(n) card\(n == 1 ? "" : "s") you're \(k == .buy ? "selling" : "buying")?"
    }

    private func switchDropping(to k: DealKind) {
        withAnimation(.snappy) {
            // Switch first, so emptying that side doesn't send you back to the start.
            pathRaw = k.rawValue
            deals.update { d in if k == .buy { d.outgoing = [] } else { d.incoming = [] } }
        }
    }

    /// Throws the open deal away (its photos too) and goes back to the start.
    private func discardDeal() {
        let photos = deals.deal.photos
        withAnimation(.snappy) { deals.update { $0 = DealState() }; pathRaw = ""; dealName = "" }
        Task { for p in photos { await DealPhotos.delete(p) } }
    }

    private func parkNow() {
        guard deals.deal.hasContent else { return }
        withAnimation(.snappy) {
            deals.park(name: dealName)
            pathRaw = ""
            dealName = ""
        }
        Haptics.tap()
    }

    /// Puts a changed line back where it was, on whichever side it's on.
    private func replace(_ changed: DealItem) {
        deals.update { d in
            if let i = d.incoming.firstIndex(where: { $0.key == changed.key }) { d.incoming[i] = changed }
            else if let i = d.outgoing.firstIndex(where: { $0.key == changed.key }) { d.outgoing[i] = changed }
        }
    }

    private func remove(_ item: DealItem) {
        withAnimation(.snappy) {
            deals.update { d in
                d.incoming.removeAll { $0.key == item.key }
                d.outgoing.removeAll { $0.key == item.key }
            }
        }
    }

    private func roundBarButton(_ icon: String, label: String, action: @escaping () -> Void) -> some View {
        Button { Haptics.tap(); action() } label: {
            Image(systemName: icon).font(.system(size: 17, weight: .semibold)).foregroundStyle(.white)
                .frame(width: 50, height: 50)
                .liquidGlass(in: Circle(), tint: Color.white.opacity(0.04), interactive: true)
                .contentShape(Circle())
        }
        .buttonStyle(.plain)
        .accessibilityLabel(label)
    }

    // MARK: Rounding the cash

    /// The cash rounded up to the next step (deal settings, $5 unless changed), when it isn't on one.
    private func roundTarget(_ totals: DealTotals) -> Double? {
        guard deals.deal.kind != .empty else { return nil }
        return roundedCash(totals.balance, step: deals.defaults.step)
    }

    /// Round the cash up: it becomes the agreed cash, and the slider of the side that moves (going
    /// out, or coming in) goes to the % that gets there. Moving a slider or a price lets go of it.
    private func roundCash() {
        guard let target = roundTarget(totals) else { return }
        withAnimation(.snappy) { deals.setAgreedCash(target) }
        Haptics.tap()
    }

    /// The deal at the cards' own prices (no agreed cash, whole %s): what the round pills round.
    private var plainTotals: DealTotals {
        DealTotals(deals.unrounded, rates: deals.rates(for: deals.unrounded), cost: { deals.cost(of: $0, in: store) })
    }

    /// The same three round amounts as the review screen: the cards' total rounded down and up to
    /// $5, and the $5 after.
    private func cardRoundOptions() -> [Double] {
        guard deals.deal.kind != .empty else { return [] }
        let original = abs(plainTotals.balance)
        let down = (original / 5).rounded(.down) * 5
        var up = (original / 5).rounded(.up) * 5
        if up == down { up += 5 }
        return [down, up, up + 5].filter { $0 > 0 }
    }

    /// Settle on a round amount (as the review screen does): the cash becomes it, paid the way it goes now.
    private func pickRound(_ amount: Double) {
        let plain = plainTotals
        if abs(amount - abs(plain.balance)) < 0.004 {
            withAnimation(.snappy) { deals.clearAgreedTotal() }
        } else {
            withAnimation(.snappy) { deals.setAgreedCash(signedAgreedCash(amount, totals: plain)) }
        }
    }

    /// Which side's market value the card shows: what you buy on a buy, what you sell on a sale.
    private var marketSide: DealSide? {
        switch deals.deal.kind {
        case .buy: return .incoming
        case .sell: return .outgoing
        default: return nil
        }
    }

    /// Open the agreed-market box, filled in with the market value as it stands.
    private func startEditingMarket(_ totals: DealTotals) {
        guard let side = marketSide else { return }
        marketText = String(format: "%.2f", (side == .incoming ? totals.inMarket : totals.outMarket) ?? 0)
        editingMarket = true
    }

    /// Open the agreed-cash box, filled in with the cash as it stands.
    private func startEditingCash(_ totals: DealTotals) {
        guard deals.deal.kind != .empty else { return }
        cashText = String(format: "%.2f", abs(totals.balance))
        editingCash = true
    }

    /// Under the agreed-cash box: which way the cash goes, and which prices move to match.
    private func agreedPrompt(_ totals: DealTotals) -> String {
        let customerPays = signedAgreedCash(1, totals: totals) > 0
        let moving = deals.deal.outgoing.isEmpty ? "coming in" : "going out"
        let other = deals.role.other
        return (customerPays ? "What the \(other) pays you." : "What you pay the \(other).") + " The prices \(moving) move to match."
    }

    /// The typed amount, paid the way the cash goes now (see signedAgreedCash).
    private func setAgreedCash(_ totals: DealTotals) {
        let text = cashText
        cashText = ""
        guard let amount = MoneyField.value(text) else { return }
        withAnimation(.snappy) { deals.setAgreedCash(signedAgreedCash(amount, totals: totals)) }
        Haptics.tap()
    }

    /// Lets go of the agreed cash; the slider stays where it moved to.
    private func clearAgreed() {
        withAnimation(.snappy) { deals.clearAgreedTotal() }
    }

    // MARK: Photos and notes

    /// One quiet row until wanted, then the photos strip and the notes field.
    @ViewBuilder private func extras(accent: Color) -> some View {
        if extrasOpen {
            VStack(alignment: .leading, spacing: 28) {
                photosSection(accent: accent)
                notesSection(accent: accent)
            }
            .transition(.opacity)
        } else {
            Button {
                Haptics.tap()
                withAnimation(.snappy) { extrasOpen = true }
            } label: {
                HStack(spacing: 10) {
                    Image(systemName: "camera").font(.system(size: 15, weight: .semibold))
                    Text("Add a photo or note").font(.geist(15, .medium))
                    Spacer()
                }
                .foregroundStyle(Theme.muted)
                .padding(.horizontal, 16).frame(height: 50)
                .background(RoundedRectangle(cornerRadius: 16, style: .continuous).fill(Theme.surface))
                .overlay(RoundedRectangle(cornerRadius: 16, style: .continuous).strokeBorder(Theme.border))
            }
            .buttonStyle(.plain)
        }
    }

    /// Photos documenting the deal (the cards on the table, a receipt); they're kept with it when it closes.
    private func photosSection(accent: Color) -> some View {
        VStack(alignment: .leading, spacing: 12) {
            VStack(alignment: .leading, spacing: 6) {
                HStack(spacing: 8) {
                    Image(systemName: "camera.fill").font(.system(size: 14, weight: .semibold)).foregroundStyle(accent)
                    Text("Photos").font(.display(20)).tracking(-0.5).displayTrim(20)
                    if !deals.deal.photos.isEmpty { MonoLabel(text: "\(deals.deal.photos.count)") }
                }
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
                Text("Notes").font(.display(20)).tracking(-0.5).displayTrim(20)
            }
            DealNotesField(notes: deals.deal.notes, prompt: "Who it was with, how they paid, anything to remember", accent: accent) { text in
                deals.update { $0.notes = text.isEmpty ? nil : text }
            }
        }
    }

    // MARK: A side of the deal

    @ViewBuilder private func side(_ side: DealSide, totals: DealTotals, settled: DealState, accent: Color) -> some View {
        let incoming = side == .incoming
        let items = incoming ? deals.deal.incoming : deals.deal.outgoing
        // Each line's price at the agreed cash, when one is set (nil: its own price as it stands).
        let agreedUnits: [String: Double] = deals.deal.agreedCash == nil ? [:]
            : Dictionary((incoming ? settled.incoming : settled.outgoing).compactMap { i in i.unitPrice(side: incoming ? rates.in : rates.out).map { (i.key, $0) } }, uniquingKeysWith: { a, _ in a })
        let rate = incoming ? rates.in : rates.out
        let fallback = incoming ? defaultRates.in : defaultRates.out
        VStack(alignment: .leading, spacing: 12) {
            // "Coming in · 2" with the side's total on the right.
            if !(items.isEmpty && dealPath != .trade) {
            HStack(alignment: .firstTextBaseline) {
                Image(systemName: incoming ? "arrow.down.left" : "arrow.up.right")
                    .font(.system(size: 15, weight: .semibold))
                    .foregroundStyle(incoming ? accent : Theme.planPink)
                Text(incoming ? (dealPath == .buy ? "What you're buying" : dealPath == .trade ? "Their cards" : "Coming in")
                              : (dealPath == .sell ? "What you're selling" : dealPath == .trade ? "Your cards" : "Going out"))
                    .font(.display(24)).tracking(-0.6).displayTrim(24).lineLimit(1).minimumScaleFactor(0.8)
                // What the side is, behind an ⓘ (no line of small text under the title).
                TermInfo(term: incoming ? .comingIn : .goingOut, color: .white)
                if !items.isEmpty {
                    Text("· \(items.reduce(0) { $0 + $1.qty })").font(.geist(17, .medium)).monospacedDigit().foregroundStyle(Theme.subtle)
                }
                Spacer(minLength: 8)
                if !items.isEmpty {
                    Text(Format.money(incoming ? totals.inValue : totals.outValue))
                        .font(.display(22)).tracking(-0.6).monospacedDigit().displayTrim(22)
                        .contentTransition(.numericText())
                        .animation(.snappy, value: incoming ? totals.inValue : totals.outValue)
                }
            }
            }

            if !items.isEmpty {
                // One rate for the side, as chips; a card with its own price ignores it.
                RateChips(rate: rate, fallback: fallback,
                          lead: deals.role == .vendor ? (incoming ? "You pay" : "You charge") : (incoming ? "They charge" : "They offer")) { r in
                    deals.update { d in if incoming { d.rateIn = r } else { d.rateOut = r } }
                }
                VStack(spacing: 0) {
                    ForEach(Array(items.enumerated()), id: \.element.id) { n, item in
                        DealRow(item: item, incoming: incoming, rate: rate, agreedUnit: agreedUnits[item.key],
                                cost: incoming ? nil : deals.cost(of: item, in: store),
                                tracked: deals.tracked(item, side: side),
                                onOpen: item.product.id.hasPrefix("custom:") ? nil : { detailItem = item },
                                onPrice: { pricingItem = item },
                                onMore: { actingItem = item })
                            .overlay(alignment: .top) {
                                if n > 0 { Rectangle().fill(Theme.border).frame(height: 1) }
                            }
                            .transition(.opacity)
                    }
                }
            }

            if items.isEmpty {
                if dealPath == .trade {
                    // The table: faint card slots waiting to be filled; tap one to scan.
                    TradeSlots(incoming: incoming, onScan: { scanning = side }, onSearch: { picking = side })
                } else {
                    // Buying or selling with nothing yet (the camera was closed): a proper empty state.
                    DealEmptySide(incoming: incoming, onScan: { scanning = side }, onSearch: { picking = side })
                }
            } else {
                HStack(spacing: 8) {
                    Button { picking = side } label: {
                        Label(incoming ? "Add" : "Add from collection", systemImage: "plus")
                            .frame(maxWidth: .infinity)
                    }
                    .buttonStyle(Button3D(kind: .dark, fullWidth: true, height: 46))
                    Button { scanning = side } label: { Label("Scan", systemImage: "camera") }
                        .buttonStyle(Button3D(kind: .dark, fullWidth: false, height: 46))
                        .accessibilityLabel(incoming ? "Scan what's coming in" : "Scan what's going out")
                }
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
        abs(balance) < 0.005 ? "Even swap" : (balance > 0 ? "\(DealRole.stored.theyPay) \(Format.money(balance))" : "You pay \(Format.money(-balance))")
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
    case verdict, ahead, cash, comingIn, goingOut, profit, value, rate, offer, charge, market, paid, gain

    var title: String {
        switch self {
        case .verdict: return "Ahead or behind"
        case .ahead: return "Ahead or behind"
        case .cash: return "Cash"
        case .comingIn: return "Buying"
        case .goingOut: return "Selling"
        case .profit: return "Sale profit"
        case .value: return "Trade-in value"
        case .rate: return "Share of market"
        case .offer: return "Their offer"
        case .charge: return "Their price"
        case .market: return "Market value"
        case .paid: return "You paid"
        case .gain: return "Profit"
        }
    }

    var explanation: String {
        switch self {
        case .verdict: return "Your profit on what you hand over plus the value you gain on what comes in: how much better off you are after this deal, at market prices."
        case .ahead: return "Market value of what comes in, minus what you paid for what goes out, minus any cash you pay (plus any you get): your profit plus the value you gain."
        case .cash: return "The difference between the two sides, paid in cash so the deal comes out even."
        case .comingIn: return "What the \(DealRole.stored.other)'s cards count for in this deal, at the prices you set."
        case .goingOut: return "What your cards count for in this deal, at the prices you set."
        case .profit: return "What your cards go for in this deal, minus what you paid for them."
        case .value: return "Market value of what comes in, minus what you're giving for it: how far below market you're getting it."
        case .rate: return "Each item counts for this share of its market price. Drag to counter-offer, or set one item's own % or price."
        case .offer: return "What the vendor is paying for your cards, as a share of their market price. Cash offers are usually lower than trade-in credit."
        case .charge: return "What the vendor is charging for their cards, as a share of market. Over 100% means you pay above market."
        case .market: return "What the cards are worth at today's market prices."
        case .paid: return "What you paid for the cards you're selling, from your collection's records (or what you typed in)."
        case .gain: return "On a buy: what the cards are worth at market, minus what you pay; what you'd make reselling them at market. On a sale: what you sell for, minus what you paid."
        }
    }
}

/// A small caps label you can tap to read what it means.
struct TermLabel: View {
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
        .sheet(isPresented: $open) { TermSheet(term: term) }
    }
}

/// What a deal figure means, in a small sheet from the bottom (the owner found the speech-bubble
/// tip ugly: it covered the card): the name and one plain line, with a round close.
struct TermSheet: View {
    var term: DealTerm
    @Environment(\.dismiss) private var dismiss
    @State private var height: CGFloat = 200

    var body: some View {
        VStack(alignment: .leading, spacing: 10) {
            SheetHeader(title: term.title) { dismiss() }
            Text(term.explanation).font(.geist(15)).foregroundStyle(Theme.muted)
                .fixedSize(horizontal: false, vertical: true)
        }
        .padding(.horizontal, 20).padding(.top, 22).padding(.bottom, 24)
        .frame(maxWidth: .infinity, alignment: .leading)
        .onGeometryChange(for: CGFloat.self) { $0.size.height } action: { height = $0 + 12 }
        .presentationDetents([.height(height)])
        .glassSheet()
    }
}

/// The deal at a glance on a solid electric-lime card: whether you come out ahead, who pays
/// whom (with a one-tap round up), a bar showing what each side puts in, and the four numbers
/// in plain words (tap any for what it means). When the value gained is negative the whole card
/// goes pink, so there's never pink on lime.
/// The deal card as a read-only summary (the review screen). Built here because the card's own
/// initializer is file-private (it has private state).
@MainActor func dealSummaryCard(totals: DealTotals, role: DealRole, agreed: Bool, past: Bool = false, tagKind: DealKind? = nil) -> some View {
    BalanceCard(totals: totals, role: role, read: nil, roundTo: nil, onRound: {}, agreed: agreed, readOnly: true, past: past, tagKind: tagKind)
}

private struct BalanceCard: View {
    var totals: DealTotals
    var role: DealRole = .vendor
    /// A collector's read (the vendor's offer against market); nil for a vendor.
    var read: CollectorRead?
    var roundTo: Double?
    var onRound: () -> Void
    /// The cash is one the two of you agreed on (the prices are spread to reach it).
    var agreed = false
    /// What the moved side works out to, as a share of market, at the agreed cash.
    var share: Double?
    /// Tap the big figure to type the agreed cash.
    var onEditCash: () -> Void = {}
    var onClearAgreed: () -> Void = {}
    /// Round amounts to settle on, as on the review screen ($780 · $785 · $790); tapping the one
    /// picked again goes back to the cards' own total. Empty: no pills (the old Round up chip).
    var roundOptions: [Double] = []
    var onPickRound: (Double) -> Void = { _ in }
    /// A summary, nothing to change (the review screen): no pencil, chips or pills, figures shown.
    var readOnly = false
    /// Shown under the amount (the deal page puts the rate here); with it, no round pills or chips.
    var extra: AnyView? = nil
    /// Tap Market value to type the market value you agreed on (the deal page only).
    var onEditMarket: (() -> Void)? = nil
    var marketAgreed = false
    /// A closed deal: the verdict in the past tense ("You made a profit").
    var past = false
    /// The deal type picked (Trade stays Trade even while one side is still empty).
    var tagKind: DealKind? = nil
    /// The breakdown under the big figure (what comes in and goes out, the shares of market,
    /// notes on the total), folded away until wanted: the figure and one verdict are enough.
    @State private var details = false

    var body: some View {
        let t = totals
        let b = t.balance
        let empty = t.kind == .empty
        let down = read == nil && ((t.showsEquity && t.equity < -0.005) || (t.ahead ?? 0) < -0.005)
        let fill = down ? Theme.planPink : Theme.lime
        // A soft glow of the color around a dark middle, so the text is white on both.
        let ink = Color.white
        let shape = RoundedRectangle(cornerRadius: 24, style: .continuous)
        VStack(alignment: .leading, spacing: 0) {
            HStack {
                SkewTag(text: empty ? "New deal" : (tagKind == .trade ? DealKind.trade.label : t.kind.label), color: fill, textColor: down ? .white : Theme.ink)
                Spacer()
                if t.belowCost > 0 {
                    Label("\(t.belowCost) below cost", systemImage: "exclamationmark.triangle.fill")
                        .font(.geist(12, .semibold)).foregroundStyle(ink)
                }
            }

            // How far ahead you come out, in plain English (pink when behind: it sits on the ink pill,
            // never on lime).
            if let read {
                // A collector's headline: more or less market value after the deal, cash included.
                HStack(spacing: 8) {
                    Image(systemName: read.net >= 0 ? "arrow.up.right" : "arrow.down.right").font(.system(size: 13, weight: .medium))
                    Text(read.headline).font(.geist(15, .bold)).lineLimit(1).minimumScaleFactor(0.7)
                }
                .foregroundStyle(fill)
                .padding(.horizontal, 14).frame(height: 36)
                .background(Capsule().fill(Theme.ink.opacity(0.85)))
                .padding(.top, 16)
                .contentTransition(.numericText())
                .animation(.snappy, value: read.net)
                if details, read.offerShare != nil {
                    Text("Vendors often pay 60 to 80% of market for cards they\u{00A0}buy.")
                        .font(.geist(12, .medium)).foregroundStyle(ink.opacity(0.7))
                        .padding(.top, 8)
                }
            } else if let verdict = past ? (t.ahead.map { "\(dealAheadTitle($0, past: true)) \(Format.signedMoney($0))" } ?? t.headline) : t.headline {
                let score = t.ahead ?? t.net ?? 0
                HStack(spacing: 8) {
                    Image(systemName: score >= 0 ? "arrow.up.right" : "arrow.down.right").font(.system(size: 13, weight: .medium))
                    Text(verdict).font(.geist(15, .bold)).lineLimit(1).minimumScaleFactor(0.7)
                    TermInfo(term: t.ahead != nil ? .ahead : .verdict, color: score < -0.005 ? Theme.planPink : fill)
                }
                .foregroundStyle(score < -0.005 ? Theme.planPink : fill)
                .padding(.horizontal, 14).frame(height: 36)
                .background(Capsule().fill(Theme.ink.opacity(0.85)))
                .padding(.top, 16)
                .contentTransition(.numericText())
                .animation(.snappy, value: t.ahead ?? t.net)
            }
            if details, read == nil, t.uncosted > 0 {
                Text("Add what you paid for every item to see your\u{00A0}total")
                    .font(.geist(12, .medium)).foregroundStyle(ink.opacity(0.7))
                    .padding(.top, 8)
            }

            HStack(alignment: .center, spacing: 8) {
                TermLabel(text: cashLabel(b, empty: empty), term: .cash, color: ink.opacity(0.7))
                Spacer()
            }
            .padding(.top, 16)
            HStack(alignment: .center, spacing: 10) {
                // Tap the figure to type the cash you agreed on.
                Button(action: onEditCash) {
                    // The pencil says the figure can be tapped to type an amount; one tap target.
                    HStack(alignment: .center, spacing: 6) {
                        CountingText(value: abs(b), format: { Format.money($0) })
                            .font(.display(60)).tracking(-2.4).padding(.trailing, 2.4).monospacedDigit().foregroundStyle(ink).lineLimit(1).minimumScaleFactor(0.5)
                            .displayTrim(60)
                        if !empty && !readOnly {
                            Image(systemName: "pencil")
                                .font(.system(size: 17, weight: .medium))
                                .foregroundStyle(ink.opacity(0.7))
                                .accessibilityHidden(true)
                        }
                    }
                    .contentShape(Rectangle())
                }
                .buttonStyle(.plain)
                .disabled(empty)
                // Read-only: the tap goes nowhere, but the figure isn't dimmed (a disabled button
                // fades its label, which made the review screen's amount look faded).
                .allowsHitTesting(!readOnly)
                .accessibilityHint(readOnly ? "" : "Type the cash you agreed on")
                Spacer(minLength: 0)
                if readOnly || extra != nil {
                    EmptyView()
                } else if roundOptions.isEmpty, let roundTo {
                    // A quiet outlined chip on the card: one line, no figure (it's in the label read aloud).
                    chip("Round up", icon: "arrow.up", ink: ink, action: onRound)
                        .accessibilityLabel("Round up to \(Format.money(abs(roundTo)))")
                        .transition(.scale.combined(with: .opacity))
                } else if agreed && !roundOptions.contains(where: { abs(abs(b) - $0) < 0.005 }) {
                    // A typed amount (not one of the pills): Clear goes back to the cards' total.
                    chip("Clear", icon: "xmark", ink: ink, action: onClearAgreed)
                        .accessibilityLabel("Clear the agreed cash")
                }
            }
            .padding(.top, 8)
            if !empty && !roundOptions.isEmpty && !readOnly && extra == nil { roundPills(abs(b), ink: ink) }
            if let extra { extra }

            if details || readOnly {
            Group {
                if let read {
                    LazyVGrid(columns: [GridItem(.flexible(), spacing: 12), GridItem(.flexible(), spacing: 12)], alignment: .leading, spacing: 14) {
                        stat("Coming in", .comingIn, Format.money(t.inValue), ink)
                        stat("Going out", .goingOut, Format.money(t.outValue), ink)
                        stat("Their offer", .offer, read.offerShare.map { "\(Int(($0 * 100).rounded()))% of market" } ?? "—", ink)
                        stat("Their price", .charge, read.chargeShare.map { "\(Int(($0 * 100).rounded()))% of market" } ?? "—", ink)
                    }
                } else {
                    DealFigures(totals: t, ink: ink, onEditMarket: readOnly ? nil : onEditMarket, marketAgreed: marketAgreed, past: past)
                }
            }
            .padding(.top, 18)
            .transition(.opacity)
            }
            if !empty && !readOnly {
                Button {
                    Haptics.tap()
                    withAnimation(.snappy(duration: 0.25)) { details.toggle() }
                } label: {
                    HStack(spacing: 4) {
                        Text(details ? "Hide details" : "Details")
                        Image(systemName: "chevron.down").font(.system(size: 10, weight: .bold))
                            .rotationEffect(.degrees(details ? 180 : 0))
                    }
                    .font(.geist(13, .semibold)).foregroundStyle(ink.opacity(0.75))
                    .padding(.vertical, 6)
                    .contentShape(Rectangle())
                }
                .buttonStyle(.plain)
                .padding(.top, 12)
            }
        }
        .padding(20)
        .frame(maxWidth: .infinity, alignment: .leading)
        .background {
            ZStack {
                // Dark olive (or wine when down) in the middle, the color glowing in from the edges. Still.
                shape.fill(down ? Color(hex: 0x3A0B22) : Color(hex: 0x2F3A0A))
                RadialGradient(colors: [fill.opacity(0.75), fill.opacity(0)], center: UnitPoint(x: 0.1, y: -0.05), startRadius: 0, endRadius: 300)
                RadialGradient(colors: [fill.opacity(0.55), fill.opacity(0)], center: UnitPoint(x: 1.05, y: 0.2), startRadius: 0, endRadius: 230)
                RadialGradient(colors: [fill.opacity(0.7), fill.opacity(0)], center: UnitPoint(x: 0.55, y: 1.15), startRadius: 0, endRadius: 280)
                RadialGradient(colors: [Color.black.opacity(0.45), Color.black.opacity(0)], center: UnitPoint(x: 0.45, y: 0.5), startRadius: 0, endRadius: 190)
            }
            .clipShape(shape)
            .overlay(shape.strokeBorder(fill.opacity(0.25), lineWidth: 1))
            .shadow(color: fill.opacity(0.25), radius: 22)
        }
        .animation(.easeInOut(duration: 0.3), value: down)
        .animation(.snappy, value: roundTo)
        .animation(.snappy, value: agreed)
        // A warning buzz the moment value gained goes negative (and a light tap when it recovers).
        .sensoryFeedback(trigger: down) { was, now in
            now && !was ? .warning : (was && !now ? .impact(weight: .light) : nil)
        }
    }

    /// A quiet outlined chip beside the big figure (Round up, or Clear once a cash is agreed).
    private func chip(_ title: String, icon: String, ink: Color, action: @escaping () -> Void) -> some View {
        Button(action: action) {
            HStack(spacing: 5) {
                Image(systemName: icon).font(.system(size: 11, weight: .semibold))
                Text(title).font(.geist(13, .semibold))
            }
            .foregroundStyle(ink)
            .padding(.horizontal, 12).frame(height: 34)
            .background(RoundedRectangle(cornerRadius: 10, style: .continuous).fill(ink.opacity(0.08)))
            .overlay(RoundedRectangle(cornerRadius: 10, style: .continuous).strokeBorder(ink.opacity(0.35), lineWidth: 1))
            .lineLimit(1).fixedSize()
        }
        .buttonStyle(ShutterStyle())
    }

    /// Who pays whom; in the past tense on a closed deal ("You paid the customer").
    private func cashLabel(_ b: Double, empty: Bool) -> String {
        if empty { return "Add items to start" }
        if abs(b) < 0.005 { return "Settled · no cash" }
        if b > 0 { return past ? role.theyPaid : role.theyPay }
        return past ? role.youPaid : role.youPay
    }

    /// The review screen's round amounts, right under the total (the owner's call: no disconnect
    /// between the two). The picked one is white; tap it again to go back to the cards' total.
    private func roundPills(_ cash: Double, ink: Color) -> some View {
        HStack(spacing: 8) {
            ForEach(roundOptions, id: \.self) { o in
                let on = agreed && abs(cash - o) < 0.005
                Button {
                    Haptics.tap()
                    if on { onClearAgreed() } else { onPickRound(o) }
                } label: {
                    Text(Format.moneyWhole(o)).font(.geist(15, .semibold)).monospacedDigit()
                        .foregroundStyle(on ? Theme.ink : ink)
                        .frame(maxWidth: .infinity).frame(height: 40)
                        .background(RoundedRectangle(cornerRadius: 13, style: .continuous).fill(on ? Color.white : Theme.ink.opacity(0.35)))
                }
                .buttonStyle(.plain)
                .accessibilityLabel(on ? "\(Format.moneyWhole(o)), picked. Tap to go back to the cards' total" : "Settle on \(Format.moneyWhole(o))")
            }
        }
        .padding(.top, 12)
    }

    private func stat(_ label: String, _ term: DealTerm, _ value: String, _ ink: Color) -> some View {
        VStack(alignment: .leading, spacing: 5) {
            TermLabel(text: label, term: term, color: ink.opacity(0.65))
            Text(value).font(.geist(17, .semibold)).monospacedDigit().foregroundStyle(ink).lineLimit(1).minimumScaleFactor(0.7)
        }
        .frame(maxWidth: .infinity, alignment: .leading)
    }
}

/// The deal card's figures, only those that apply (the owner's call): a buy shows what's coming
/// in; a sale what's going out and its profit; a trade all four, Trade-in value included. Shared
/// by the deal card and the review screen so both say the same things in the same words.
struct DealFigures: View {
    var totals: DealTotals
    var ink: Color = .white
    /// Market value is tappable to type the agreed market value (with a pencil); nil on summaries.
    var onEditMarket: (() -> Void)? = nil
    /// The market value was agreed by hand: the label says so.
    var marketAgreed = false
    /// A closed deal: Came in / Went out (past tense).
    var past = false

    var body: some View {
        let t = totals
        let columns = Array(repeating: GridItem(.flexible(), spacing: 12), count: t.kind == .trade ? 2 : 3)
        LazyVGrid(columns: columns, alignment: .leading, spacing: 14) {
            switch t.kind {
            case .buy:
                market(t.inMarket)
                stat("Of market", .rate, t.inMarket.flatMap { $0 > 0 ? "\(Int((t.inValue / $0 * 100).rounded()))%" : nil } ?? "—")
                gain(t.ahead)
            case .sell:
                stat("You paid", .paid, t.profit.map { Format.money(t.outValue - $0) } ?? "—")
                market(t.outMarket)
                gain(t.profit)
            default:
                stat(past ? "Came in" : "Coming in", .comingIn, Format.money(t.inValue))
                stat(past ? "Went out" : "Going out", .goingOut, Format.money(t.outValue))
                stat("Sale profit", .profit, t.profit.map { Format.signedMoney($0) } ?? "—")
                stat("Trade-in value", .value, t.showsEquity ? Format.signedMoney(t.equity) : "—")
            }
        }
    }

    /// Market value; on the deal page a pencil beside it opens the agreed-market box.
    @ViewBuilder private func market(_ v: Double?) -> some View {
        let value = v.map { Format.money($0) } ?? "—"
        if let onEditMarket {
            VStack(alignment: .leading, spacing: 5) {
                TermLabel(text: marketAgreed ? "Agreed market" : "Market value", term: .market, color: ink.opacity(0.65))
                Button { Haptics.tap(); onEditMarket() } label: {
                    HStack(spacing: 4) {
                        Text(value).font(.geist(17, .semibold)).monospacedDigit().foregroundStyle(ink).lineLimit(1).minimumScaleFactor(0.7)
                        Image(systemName: "pencil").font(.system(size: 11, weight: .semibold)).foregroundStyle(ink.opacity(0.7))
                    }
                    .contentShape(Rectangle())
                }
                .buttonStyle(.plain)
                .accessibilityHint("Type the market value you agreed on")
            }
            .frame(maxWidth: .infinity, alignment: .leading)
        } else {
            stat(marketAgreed ? "Agreed market" : "Market value", .market, value)
        }
    }

    /// "Profit" or "Loss", by itself (the owner's call), the number signed.
    private func gain(_ v: Double?) -> some View {
        stat((v ?? 0) < -0.005 ? "Loss" : "Profit", .gain, v.map { Format.signedMoney($0) } ?? "—")
    }

    private func stat(_ label: String, _ term: DealTerm, _ value: String) -> some View {
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
        .sheet(isPresented: $open) { TermSheet(term: term) }
    }
}

/// The side's share of market, adjustable for this deal (the counter-offer slider), with what it
/// does to the deal shown live underneath as you drag.
private struct RateCard: View {
    var rate: Double
    var fallback: Double
    var accent: Color
    var result: String?
    /// Before the percentage: "At " (a vendor's own rate), "They offer " / "They charge " (a collector's).
    var lead = "At "
    var onChange: (Double?) -> Void

    var body: some View {
        VStack(alignment: .leading, spacing: 10) {
            HStack(alignment: .firstTextBaseline) {
                Text(lead).foregroundColor(Theme.muted) + Text("\(Int((rate * 100).rounded()))%").foregroundColor(.white) + Text(" of market").foregroundColor(Theme.muted)
                TermInfo(term: .rate, color: .white)
                Spacer()
                if abs(rate - fallback) > 0.0001 {
                    Button("Reset to \(Int((fallback * 100).rounded()))%") { onChange(nil) }
                        .font(.geist(12, .medium)).foregroundStyle(Theme.muted)
                        .buttonStyle(.plain)
                }
            }
            .font(.geist(14, .medium)).monospacedDigit()
            Slider(value: Binding(get: { rate }, set: { onChange(($0 * 100).rounded() / 100) }), in: DealState.rateRange, step: 0.01)
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
    /// Its price per unit at the deal's agreed cash, when one is set (the typed fields keep its own).
    var agreedUnit: Double? = nil
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
        let own = item.unitPrice(side: rate)
        let unit = agreedUnit ?? own
        let identity = self.identity
        let total = (unit ?? 0) * Double(item.qty)
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
                    // Plain to see: white on a faint circle (it was a faint grey icon before).
                    Button(action: onRemove) {
                        Image(systemName: "trash").font(.system(size: 13, weight: .medium)).foregroundStyle(.white)
                            .frame(width: 30, height: 30)
                            .background(Circle().fill(Color.white.opacity(0.12)))
                            .contentShape(Circle())
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
                    // Just the price: where it came from, eBay sales and how fast it sells are on
                    // the card's page (tap the card).
                }
                .font(.geist(12)).monospacedDigit().lineLimit(1)
                .padding(.top, 2)


                HStack(spacing: 6) {
                    stepper
                    percentField
                    priceField(placeholder: own.map { String(format: "%.2f", $0) } ?? "Price")
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

                // Coming in, the collection switch is a small chip on the total's line.
                if !(incoming && !item.isCustom) {
                    statusRow
                        .padding(.top, 10)
                }

                HStack(spacing: 6) {
                    if incoming && !item.isCustom { collectionChip }
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

    /// Coming in: whether it goes into your collection, as a chip you tap. Filled with a check when
    /// it will be added; a faint outline when it won't.
    private var collectionChip: some View {
        Button {
            change { $0.track = !tracked }
            Haptics.tap()
        } label: {
            HStack(spacing: 5) {
                Image(systemName: tracked ? "checkmark" : "plus").font(.system(size: 10, weight: .semibold))
                Text(tracked ? "Adding to collection" : "Add to collection")
            }
            .font(.geist(12, .medium))
            .foregroundStyle(tracked ? accent : Theme.muted)
            .padding(.horizontal, 10).frame(height: 26)
            .background(Capsule().fill(tracked ? accent.opacity(0.16) : .clear))
            .overlay(Capsule().strokeBorder(tracked ? accent.opacity(0.5) : Color.white.opacity(0.12)))
            .contentShape(Capsule())
        }
        .buttonStyle(.plain)
        .accessibilityLabel("Add to collection")
        .accessibilityValue(tracked ? "On" : "Off")
        .accessibilityAddTraits(.isToggle)
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
                tag(tracked ? "Not in Corodex · will be added" : "Not in Corodex · not tracked", icon: "exclamationmark.circle")
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

/// The empty Deal tab: what kind of deal is this? Three big choices, each leading to a page
/// with only what it needs, and a scan button that starts a buy straight away.
private struct DealPathChooser: View {
    var onPick: (DealKind) -> Void
    var onScan: () -> Void

    var body: some View {
        VStack(alignment: .leading, spacing: 14) {
            DisplayText(text: "What's the deal?", size: 30)
                .padding(.bottom, 4)
            option(.buy, icon: "arrow.down.left")
            option(.sell, icon: "arrow.up.right")
            option(.trade, icon: "arrow.left.arrow.right")
            Button(action: onScan) {
                HStack(spacing: 8) {
                    Image(systemName: "camera").font(.system(size: 14, weight: .semibold))
                    Text("Or scan a card to start buying").font(.geist(14, .medium))
                }
                .foregroundStyle(Theme.muted)
                .frame(maxWidth: .infinity).frame(height: 44)
                .contentShape(Rectangle())
            }
            .buttonStyle(.plain)
        }
    }

    private func option(_ k: DealKind, icon: String) -> some View {
        Button { onPick(k) } label: {
            HStack(spacing: 14) {
                Image(systemName: icon).font(.system(size: 18, weight: .semibold))
                    .foregroundStyle(k == .sell ? Theme.planPink : Theme.lime)
                    .frame(width: 44, height: 44)
                    .background(Circle().fill(Color.white.opacity(0.06)))
                VStack(alignment: .leading, spacing: 3) {
                    Text(DealView.pathTitle(k)).font(.geist(18, .semibold)).foregroundStyle(.white)
                    Text(DealView.pathLine(k)).font(.geist(13)).foregroundStyle(Theme.muted)
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
}

/// Faint card outlines in a row, the first with a + (tap to scan), and a quiet way to search:
/// what a side of a trade looks like before anything's on it.
private struct TradeSlots: View {
    var incoming: Bool
    var onScan: () -> Void
    var onSearch: () -> Void

    var body: some View {
        VStack(alignment: .leading, spacing: 12) {
            HStack(spacing: 10) {
                ForEach(0 ..< 4, id: \.self) { i in
                    let shape = RoundedRectangle(cornerRadius: 8, style: .continuous)
                    Button(action: onScan) {
                        ZStack {
                            shape.fill(Color.white.opacity(i == 0 ? 0.05 : 0.02))
                            shape.strokeBorder(Color.white.opacity(i == 0 ? 0.28 : 0.1), style: StrokeStyle(lineWidth: 1.5, dash: [5, 5]))
                            if i == 0 {
                                Image(systemName: "plus").font(.system(size: 20, weight: .semibold)).foregroundStyle(incoming ? Theme.lime : Theme.planPink)
                            }
                        }
                        .aspectRatio(63.0 / 88.0, contentMode: .fit)
                        .frame(maxWidth: .infinity)
                    }
                    .buttonStyle(.plain)
                    .accessibilityHidden(i > 0)
                    .accessibilityLabel(incoming ? "Scan their cards" : "Scan your cards")
                }
            }
            Button(action: onSearch) {
                Text(incoming ? "Tap to scan, or search for a card" : "Tap to scan, or pick from your collection")
                    .font(.geist(13, .medium)).foregroundStyle(Theme.muted)
            }
            .buttonStyle(.plain)
        }
    }
}

/// Buying or selling with nothing added: a fan of faint card outlines, a big question, one line,
/// a lime Scan and a quiet second way.
private struct DealEmptySide: View {
    var incoming: Bool
    var onScan: () -> Void
    var onSearch: () -> Void

    var body: some View {
        VStack(spacing: 14) {
            ZStack {
                ForEach(0 ..< 3, id: \.self) { i in
                    let shape = RoundedRectangle(cornerRadius: 10, style: .continuous)
                    shape.fill(Color.white.opacity(i == 1 ? 0.05 : 0.025))
                        .overlay(shape.strokeBorder(Color.white.opacity(i == 1 ? 0.22 : 0.1), style: StrokeStyle(lineWidth: 1.5, dash: [5, 5])))
                        .frame(width: 78, height: 109)
                        .rotationEffect(.degrees(Double(i - 1) * 10), anchor: .bottom)
                        .offset(x: CGFloat(i - 1) * 44, y: i == 1 ? -6 : 4)
                        .zIndex(i == 1 ? 1 : 0)
                }
            }
            .frame(height: 130)
            .padding(.bottom, 6)
            Text(incoming ? "What are they selling you?" : "What are you selling?")
                .font(.display(24)).tracking(-0.6).multilineTextAlignment(.center)
            Text(incoming ? "Scan each card and its price adds up as you go." : "Scan your cards, and they're priced from the market.")
                .font(.geist(14)).foregroundStyle(Theme.muted).multilineTextAlignment(.center)
            Button(action: onScan) {
                Label("Scan cards", systemImage: "camera").font(.geist(16, .semibold)).foregroundStyle(Theme.ink)
                    .padding(.horizontal, 28).frame(height: 48)
                    .background(Capsule().fill(Theme.lime))
                    .contentShape(Capsule())
            }
            .buttonStyle(.plain)
            .padding(.top, 6)
            Button(action: onSearch) {
                Text(incoming ? "or search for a card" : "or pick from your collection").font(.geist(14, .medium)).foregroundStyle(Theme.muted)
            }
            .buttonStyle(.plain)
        }
        .frame(maxWidth: .infinity)
        .padding(.top, 30)
    }
}

/// A side's share of market as chips (one rate for the side). Picking the usual one goes back
/// to following the deal settings.
private struct RateChips: View {
    var rate: Double
    var fallback: Double
    var lead: String
    var onChange: (Double?) -> Void

    var body: some View {
        let pct = Int((rate * 100).rounded())
        let usual = Int((fallback * 100).rounded())
        // Five steps fit across the screen (100% was scrolled out of sight), plus this deal's % and the usual one.
        let options = Array(Set([60, 70, 80, 90, 100, pct, usual])).filter { (40...120).contains($0) }.sorted()
        VStack(alignment: .leading, spacing: 8) {
            Text(lead).foregroundColor(Theme.muted) + Text(" \(pct)%").foregroundColor(.white) + Text(" of market").foregroundColor(Theme.muted)
            ChipPicker(options: options.map { ($0, "\($0)%") },
                       selection: Binding(get: { pct }, set: { v in onChange(v == usual ? nil : Double(v) / 100) }), scrolls: true)
        }
        .font(.geist(13, .medium)).monospacedDigit()
        .sensoryFeedback(.selection, trigger: pct)
    }
}

/// One line of the deal, calm: picture, name, one quiet line (market and its share, or its own
/// price), a pink line only when it's below what you paid, the price on the right (tap to change
/// it) and a ⋯ for the rest.
private struct DealRow: View {
    var item: DealItem
    var incoming: Bool
    var rate: Double
    var agreedUnit: Double?
    var cost: Double?
    var tracked: Bool
    var onOpen: (() -> Void)?
    var onPrice: () -> Void
    var onMore: () -> Void
    @Environment(CollectionStore.self) private var store

    private var identity: HoldingIdentity? {
        if let key = item.holdingKey, let held = store.allHoldings.first(where: { $0.identity.key == key }) { return held.identity }
        if let g = item.grade {
            return HoldingIdentity(productId: item.product.id, printing: item.printing, condition: "Near Mint", gradeCompany: g.company, grade: g.grade)
        }
        return nil
    }

    var body: some View {
        let unit = agreedUnit ?? item.unitPrice(side: rate)
        let total = unit.map { $0 * Double(item.qty) }
        let identity = self.identity
        let loss: Double? = { guard let cost, let total else { return nil }; let p = total - cost; return p < -0.005 ? -p : nil }()
        HStack(alignment: .center, spacing: 12) {
            Button { onOpen?() } label: {
                HoldingArt(product: item.product, identity: identity, cornerRadius: 3, caption: false)
                    .frame(width: 40, height: 56)
            }
            .buttonStyle(.plain)
            .disabled(onOpen == nil)
            .accessibilityLabel("Details for \(item.product.name)")
            VStack(alignment: .leading, spacing: 3) {
                Text(ActionsSheet.shortName(item.product)).font(.geist(15, .medium)).foregroundStyle(.white).lineLimit(1)
                Text(detail(unit: unit, identity: identity)).font(.geist(12)).monospacedDigit().foregroundStyle(Theme.muted).lineLimit(1)
                if let loss {
                    Text("Below what you paid by \(Format.money(loss))").font(.geist(12, .medium)).monospacedDigit().foregroundStyle(Theme.planPink).lineLimit(1)
                }
            }
            Spacer(minLength: 8)
            Button(action: onPrice) {
                VStack(alignment: .trailing, spacing: 2) {
                    Text(total.map { Format.money($0) } ?? "Set price").font(.geist(15, .semibold)).monospacedDigit()
                        .foregroundStyle(total == nil ? Theme.lime : .white)
                    if item.qty > 1, let unit {
                        Text("\(item.qty) × \(Format.money(unit))").font(.geist(11)).monospacedDigit().foregroundStyle(Theme.subtle)
                    }
                }
                .contentShape(Rectangle())
            }
            .buttonStyle(.plain)
            .accessibilityHint("Change its price")
            RowMoreButton(label: item.product.name, action: onMore)
                .padding(.trailing, -10)
        }
        .padding(.vertical, 10)
    }

    /// "Market $103.52 · 100%", "Own price · market $54.84", plus what happens in your collection
    /// when that isn't the usual.
    private func detail(unit: Double?, identity: HoldingIdentity?) -> String {
        var parts: [String] = []
        if let g = identity?.gradeLabel { parts.append(g) }
        if item.isCustom {
            parts.append("Custom")
        } else if let market = item.market {
            if item.price != nil { parts.append("Own price · market \(Format.money(market))") }
            else if let unit, market > 0 { parts.append("Market \(Format.money(market)) · \(Int((unit / market * 100).rounded()))%") }
            else { parts.append("Market \(Format.money(market))") }
        } else {
            parts.append("No market price")
        }
        if incoming, !item.isCustom, !tracked { parts.append("not adding to collection") }
        if !incoming, item.holdingKey == nil, !item.isCustom { parts.append("not in your collection") }
        if let cost, (unit.map { $0 * Double(item.qty) } ?? 0) - cost >= -0.005 { parts.append("paid \(Format.money(cost))") }
        return parts.joined(separator: " · ")
    }
}

/// A line's price (and quantity, and what you paid when it isn't in your collection), in a sheet
/// that fits its content, like the Grading sheets.
private struct DealPriceSheet: View {
    var item: DealItem
    var incoming: Bool
    var rate: Double
    var asksPaid: Bool
    var onSave: (DealItem) -> Void
    @Environment(\.dismiss) private var dismiss
    @State private var price = ""
    @State private var paid = ""
    @State private var qty = 1
    @State private var height: CGFloat = 380

    var body: some View {
        let maxQty = item.maxQty ?? 999
        VStack(alignment: .leading, spacing: 18) {
            SheetHeader(title: "Its price") { dismiss() }
            HStack(spacing: 12) {
                HoldingArt(product: item.product, cornerRadius: 3, caption: false).frame(width: 40, height: 56)
                VStack(alignment: .leading, spacing: 3) {
                    Text(ActionsSheet.shortName(item.product)).font(.geist(15, .semibold)).foregroundStyle(.white).lineLimit(1)
                    Text(item.market.map { "Market \(Format.money($0))" } ?? "No market price").font(.geist(13)).monospacedDigit().foregroundStyle(Theme.muted)
                }
            }
            SheetPanel {
                SheetMoneyRow(title: "Price each", text: $price)
                if maxQty > 1 || item.qty > 1 {
                    SheetDivider()
                    HStack {
                        Text("Quantity").font(.geist(16)).foregroundStyle(.white)
                        Spacer()
                        Text("\(qty)").font(.geist(16)).monospacedDigit().foregroundStyle(Theme.muted)
                        Stepper("", value: $qty, in: 1...max(1, maxQty)).labelsHidden().fixedSize()
                    }
                    .frame(minHeight: 50)
                }
                if asksPaid {
                    SheetDivider()
                    SheetMoneyRow(title: "You paid each", text: $paid)
                }
            }
            if item.market != nil {
                Button {
                    price = ""
                    var c = item
                    c.price = nil
                    c.rate = nil
                    c.qty = qty
                    if asksPaid { c.cost = MoneyField.value(paid) }
                    onSave(c)
                    dismiss()
                } label: {
                    Text("Use \(Int((rate * 100).rounded()))% of market instead").font(.geist(14, .medium)).foregroundStyle(Theme.muted)
                }
                .buttonStyle(.plain)
            }
            SheetLimeButton(title: "Save", enabled: MoneyField.value(price) != nil || item.market != nil) {
                var c = item
                if let v = MoneyField.value(price), abs(v - (item.unitPrice(side: rate) ?? -1)) > 0.004 || item.price != nil {
                    c.price = v
                    c.rate = nil
                }
                c.qty = qty
                if asksPaid { c.cost = MoneyField.value(paid) }
                onSave(c)
                dismiss()
            }
        }
        .padding(.horizontal, 20).padding(.top, 24).padding(.bottom, 8)
        .onGeometryChange(for: CGFloat.self) { $0.size.height } action: { height = $0 }
        .onAppear {
            qty = item.qty
            if let u = item.unitPrice(side: rate) { price = String(format: "%.2f", u) }
            if let c = item.cost { paid = String(format: "%.2f", c) }
        }
        .presentationDetents([.height(height)])
        .glassSheet()
    }
}

/// What the customer sees, full screen and calm: their cards (what they hand you, what they
/// get), each at the price you're paying or charging, and the cash, big. A card they hand you
/// that you're paying under market for shows the market price struck through and the share
/// off; otherwise never market prices, rates, your costs, profit or value gained. Tap a card for a closer look; Flip turns the
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
    /// Measured: the page's height outside the tiles (header, headings, gaps) and the cash panel's.
    @State private var chrome: CGFloat = 300
    @State private var cashHeight: CGFloat = 170

    struct Look: Identifiable {
        var item: DealItem
        var incoming: Bool
        var rate: Double
        var id: String { (incoming ? "i" : "o") + item.key }
    }

    private var title: String {
        switch deal.kind {
        case .buy: return "We're buying"
        case .sell: return "You're buying"
        default: return "Your trade"
        }
    }

    var body: some View {
        let b = totals.balance
        ZStack(alignment: flipped ? .bottomTrailing : .topTrailing) {
            backdrop
            GeometryReader { geo in
                // Tiles as big as fit: more columns (smaller tiles) as cards are added, so the cash always shows.
                let fit = layout(width: geo.size.width, room: geo.size.height - cashHeight - chrome)
                ScrollView {
                    VStack(alignment: .leading, spacing: 30) {
                        header
                        if !deal.incoming.isEmpty { section("You hand us", deal.incoming, rates.in, incoming: true, total: totals.inValue, fit: fit) }
                        if !deal.outgoing.isEmpty { section("You get", deal.outgoing, rates.out, incoming: false, total: totals.outValue, fit: fit) }
                    }
                    .padding(.horizontal, 20)
                    .padding(.top, 72)
                    .padding(.bottom, 20)
                    .frame(maxWidth: .infinity, alignment: .leading)
                    // What isn't tiles: the content's height less the tiles' (known from the layout).
                    .onGeometryChange(for: CGFloat.self) { $0.size.height } action: { h in
                        let c = max(0, h - tilesHeight(fit))
                        if abs(c - chrome) > 1 { chrome = c }
                    }
                }
                .scrollBounceBehavior(.basedOnSize)
                // Pinned at the bottom: never scrolled out of sight.
                .safeAreaInset(edge: .bottom, spacing: 0) {
                    cashPanel(b)
                        .padding(.horizontal, 20)
                        .padding(.top, 8)
                        .padding(.bottom, 12)
                        .background(LinearGradient(colors: [Theme.background.opacity(0), Theme.background], startPoint: .top, endPoint: .init(x: 0.5, y: 0.25)))
                        .onGeometryChange(for: CGFloat.self) { $0.size.height } action: { h in
                            if abs(h - cashHeight) > 1 { cashHeight = h }
                        }
                }
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
        .imageMaxPixel(600)
        .sensoryFeedback(.selection, trigger: flipped)
        .sheet(item: $looking) { look in
            CustomerCardSheet(item: look.item, incoming: look.incoming, rate: look.rate, flipped: flipped)
        }
        .preferredColorScheme(.dark)
    }

    /// The lit grid behind the top of the page, like Overview and Closed deals. Still.
    private var backdrop: some View {
        ZStack(alignment: .top) {
            Theme.background
            ZStack {
                GridPattern(step: 36, opacity: 0.05)
                RadialGradient(colors: [Theme.lime.opacity(0.18), .clear], center: UnitPoint(x: 0.15, y: 0.3), startRadius: 0, endRadius: 300)
                RadialGradient(colors: [Theme.planBlue.opacity(0.2), .clear], center: UnitPoint(x: 0.95, y: 0.5), startRadius: 0, endRadius: 280)
            }
            .frame(height: 460)
            .mask(LinearGradient(stops: [.init(color: .black, location: 0), .init(color: .black, location: 0.5), .init(color: .clear, location: 1)],
                                 startPoint: .top, endPoint: .bottom))
        }
        .rotationEffect(.degrees(flipped ? 180 : 0))
        .ignoresSafeArea()
    }

    /// Corodex and the date, then what this deal is, like the top of a receipt.
    private var header: some View {
        VStack(alignment: .leading, spacing: 14) {
            HStack(alignment: .firstTextBaseline) {
                Text("Corodex").font(.display(20)).tracking(-0.5).foregroundStyle(Theme.lime)
                Spacer()
                MonoLabel(text: Date.now.formatted(.dateTime.month(.abbreviated).day().year()))
            }
            Text(title).font(.display(44)).tracking(-1.6).foregroundStyle(.white)
                .lineLimit(1).minimumScaleFactor(0.6)
        }
    }

    /// How the tiles are laid out: columns, each tile's width, and the text height under the art.
    struct Fit: Equatable { var cols: Int; var width: CGFloat; var text: CGFloat }

    /// The text under a tile; a line taller when a card shows its struck-through market price.
    private func textHeight(_ cols: Int) -> CGFloat {
        let base: CGFloat = cols >= 4 ? 28 : (cols == 3 ? 56 : 80)
        return base + (showsMarket && cols < 4 ? 20 : 0)
    }

    /// Some card they hand us is priced under market (so its tile shows the market struck through).
    private var showsMarket: Bool { deal.incoming.contains { $0.underMarket(side: rates.in) != nil } }

    private var sectionCounts: [Int] { [deal.incoming.count, deal.outgoing.count].filter { $0 > 0 } }

    /// The biggest tiles that fit `room`: for 2 to 6 columns, as wide as the column or as the
    /// height allows, whichever is smaller; the widest wins (fewer columns on a tie).
    private func layout(width: CGFloat, room: CGFloat) -> Fit {
        let counts = sectionCounts
        var best = Fit(cols: 6, width: max(30, (width - 40 - 60) / 6), text: textHeight(6))
        var bestWidth: CGFloat = 0
        for c in 2...6 {
            let colW = (width - 40 - CGFloat(c - 1) * 12) / CGFloat(c)
            let rows = counts.reduce(0) { $0 + Int((Double($1) / Double(c)).rounded(.up)) }
            guard rows > 0 else { return Fit(cols: 2, width: colW, text: textHeight(2)) }
            let perRow = (room - CGFloat(max(0, rows - counts.count)) * 14) / CGFloat(rows) - textHeight(c)
            let w = min(colW, perRow * 63 / 88)
            if w > bestWidth + 0.5 { bestWidth = w; best = Fit(cols: c, width: w, text: textHeight(c)) }
        }
        // Too many to fit even at six across: six across, full column width, and it scrolls.
        if bestWidth < 40 { best = Fit(cols: 6, width: (width - 40 - 60) / 6, text: textHeight(6)) }
        return best
    }

    /// The tiles' total height in a layout (every tile is card-shaped, 63:88, over its text).
    private func tilesHeight(_ fit: Fit) -> CGFloat {
        let counts = sectionCounts
        let rows = counts.reduce(0) { $0 + Int((Double($1) / Double(fit.cols)).rounded(.up)) }
        return CGFloat(rows) * (fit.width * 88 / 63 + fit.text) + CGFloat(max(0, rows - counts.count)) * 14
    }

    private func section(_ title: String, _ items: [DealItem], _ rate: Double, incoming: Bool, total: Double, fit: Fit) -> some View {
        let count = items.reduce(0) { $0 + $1.qty }
        return VStack(alignment: .leading, spacing: 14) {
            HStack(alignment: .firstTextBaseline, spacing: 10) {
                Text(title).font(.display(26)).tracking(-0.7).foregroundStyle(.white)
                MonoLabel(text: "\(count) item\(count == 1 ? "" : "s")")
                Spacer(minLength: 8)
                Text(Format.money(total)).font(.geist(18, .semibold)).monospacedDigit().foregroundStyle(.white)
            }
            LazyVGrid(columns: Array(repeating: GridItem(.fixed(fit.width), spacing: 12), count: fit.cols), alignment: .leading, spacing: 14) {
                ForEach(items) { i in tile(i, rate, incoming: incoming, cols: fit.cols).frame(width: fit.width) }
            }
            .frame(maxWidth: .infinity, alignment: .leading)
        }
    }

    /// A card as a tile: the art large, its name, and the deal price under it.
    private func tile(_ i: DealItem, _ rate: Double, incoming: Bool, cols: Int) -> some View {
        // Smaller tiles drop the name (tap for it) and set the price smaller.
        let priceSize: CGFloat = cols >= 4 ? 14 : (cols == 3 ? 18 : 24)
        return Button { looking = Look(item: i, incoming: incoming, rate: rate) } label: {
            // Every tile is card-shaped (sealed sits in a card-shaped well), with the text block a
            // fixed height, so the layout's size sums are exact.
            let gap: CGFloat = cols >= 4 ? 6 : 10
            VStack(alignment: .leading, spacing: gap) {
                Color.clear
                    .aspectRatio(63.0 / 88.0, contentMode: .fit)
                    .overlay { HoldingArt(product: i.product, identity: nil, cornerRadius: i.product.isSealed ? 14 : 8, caption: false) }
                    .overlay(alignment: .topTrailing) {
                        if i.qty > 1 {
                            Text("×\(i.qty)").font(.geist(cols >= 4 ? 11 : 14, .semibold)).monospacedDigit().foregroundStyle(.white)
                                .padding(.horizontal, cols >= 4 ? 6 : 10).frame(height: cols >= 4 ? 20 : 28)
                                .background(Capsule().fill(Theme.background.opacity(0.85)))
                                .padding(cols >= 4 ? 4 : 8)
                        }
                    }
                VStack(alignment: .leading, spacing: 3) {
                    if cols < 4 {
                        Text(i.product.name).font(.geist(cols == 3 ? 12 : 14, .medium)).foregroundStyle(Theme.muted)
                            .lineLimit(cols == 3 ? 1 : 2, reservesSpace: true).multilineTextAlignment(.leading)
                    }
                    Text(Format.money(i.total(side: rate))).font(.display(priceSize)).tracking(-priceSize * 0.025).monospacedDigit().foregroundStyle(.white)
                        .lineLimit(1).minimumScaleFactor(0.6)
                    // What we pay under market: the market price struck through and the share off.
                    if incoming, cols < 4, let under = i.underMarket(side: rate) {
                        MarketStrike(market: under.market, off: under.off, size: cols == 3 ? 11 : 13)
                    }
                }
                .frame(height: textHeight(cols) - gap, alignment: .top)
            }
            .contentShape(Rectangle())
        }
        .buttonStyle(.plain)
        .disabled(i.isCustom)
    }

    /// The cash, big. Lime when we pay them (the good news for them); a calm glass panel when
    /// they pay or it's an even swap.
    private func cashPanel(_ b: Double) -> some View {
        let even = abs(b) < 0.005
        let wePay = !even && b < 0
        let ink = wePay ? Theme.ink : Color.white
        let shape = RoundedRectangle(cornerRadius: 28, style: .continuous)
        return VStack(spacing: 8) {
            Text(even ? "Even swap" : (wePay ? "We pay you" : "You pay"))
                .font(.display(26)).tracking(-0.7).foregroundStyle(ink.opacity(wePay ? 0.75 : 0.8))
            if even {
                Text("No cash changes hands").font(.geist(17)).foregroundStyle(Theme.muted)
            } else {
                Text(Format.money(abs(b))).font(.display(68)).tracking(-2.6).padding(.trailing, 2.6).monospacedDigit().foregroundStyle(ink)
                    .lineLimit(1).minimumScaleFactor(0.5).displayTrim(68)
            }
        }
        .frame(maxWidth: .infinity)
        .padding(.vertical, 26)
        .padding(.horizontal, 20)
        .background {
            if wePay {
                ZStack {
                    shape.fill(Theme.lime)
                    GridPattern(step: 28, opacity: 0.08).clipShape(shape)
                }
                .shadow(color: Theme.lime.opacity(0.3), radius: 24)
            } else {
                shape.fill(Color.white.opacity(0.06))
            }
        }
        .overlay(shape.strokeBorder(Color.white.opacity(wePay ? 0 : 0.1)))
    }
}

/// The market price struck through, then how much under it the deal price is ("30% off").
private struct MarketStrike: View {
    var market: Double
    var off: Double
    var size: CGFloat

    var body: some View {
        HStack(spacing: 6) {
            Text(Format.money(market))
                .strikethrough(true, color: Theme.muted)
                .foregroundStyle(Theme.muted)
            Text("\(Int((off * 100).rounded()))% off")
                .fontWeight(.semibold)
                .foregroundStyle(.white)
        }
        .font(.geist(size))
        .monospacedDigit()
        .lineLimit(1)
        .minimumScaleFactor(0.7)
        .accessibilityElement(children: .ignore)
        .accessibilityLabel("Market price \(Format.money(market)), \(Int((off * 100).rounded())) percent off")
    }
}

extension DealItem {
    /// Market for the whole line and the share the deal price is under it, when it's under by
    /// at least 1% (catalog lines with a market price only).
    func underMarket(side: Double) -> (market: Double, off: Double)? {
        guard !isCustom, let m = market, m > 0 else { return nil }
        let marketTotal = m * Double(qty)
        let off = 1 - total(side: side) / marketTotal
        return off >= 0.01 ? (marketTotal, off) : nil
    }
}

/// One card from the customer view, up close: the art (lean it with a finger), what it is, and
/// the deal price (with the market struck through when we pay under it). Otherwise, like the
/// customer view, never market prices, rates, costs or profit.
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
                        Text(Format.money(item.total(side: rate))).font(.display(52)).tracking(-2).padding(.trailing, 2).monospacedDigit().foregroundStyle(.white)
                            .lineLimit(1).minimumScaleFactor(0.5)
                        if incoming, let under = item.underMarket(side: rate) {
                            MarketStrike(market: under.market, off: under.off, size: 16)
                        }
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
        .presentationDetents([.large])
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
                Text("Saved for later").foregroundStyle(.white)
                Text("(\(count))").foregroundStyle(Theme.muted)
                Image(systemName: "chevron.right").font(.system(size: 11, weight: .semibold)).foregroundStyle(Theme.subtle)
            }
            .font(.geist(13, .semibold)).monospacedDigit()
            .padding(.horizontal, 14)
            .frame(height: 36)
            .liquidGlass(in: Capsule())
        }
        .buttonStyle(.plain)
        .accessibilityLabel("Saved for later, \(count)")
    }
}

/// Deals set aside: resume one (an open deal is parked first, after asking) or delete it.
struct ParkedDealsSheet: View {
    @Environment(\.dismiss) private var dismiss

    var body: some View {
        NavigationStack {
            ScrollView {
                VStack(alignment: .leading, spacing: 0) {
                    HStack(alignment: .firstTextBaseline) {
                        Text("Saved for later").font(.display(28)).tracking(-0.7)
                        Spacer()
                        Button("Done") { dismiss() }.font(.geist(16, .semibold)).foregroundStyle(.white)
                    }
                    Text("Deals you set aside to finish later, here or on the\u{00A0}website.").font(.geist(14)).foregroundStyle(Theme.muted)
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
        .presentationDetents([.medium, .large])
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
                Text("Nothing saved for later.").font(.geist(14)).foregroundStyle(Theme.muted).padding(.vertical, 24)
                    .frame(maxWidth: .infinity)
            }
            ForEach(deals.parked) { entry in row(entry) }
        }
        .confirmationDialog("You have a deal open", isPresented: Binding(get: { asking != nil }, set: { if !$0 { asking = nil } }), titleVisibility: .visible, presenting: asking) { entry in
            Button("Save it and resume \(entry.name)") { resume(entry) }
            Button("Cancel", role: .cancel) {}
        } message: { _ in
            Text("It's saved for later first, so nothing is\u{00A0}lost.")
        }
        .confirmationDialog("Delete this saved deal?", isPresented: Binding(get: { deleting != nil }, set: { if !$0 { deleting = nil } }), titleVisibility: .visible, presenting: deleting) { entry in
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
        Haptics.tap()
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
                Text("Start a deal").font(.geist(14, .semibold))
                Text("Add what's coming in and what's going out (scan or search). The cash, your profit and whether it's fair are worked out for\u{00A0}you.")
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
    var role: DealRole = .vendor
    var read: CollectorRead?

    var body: some View {
        let b = totals.balance
        let down = read == nil && ((totals.showsEquity && totals.equity < -0.005) || (totals.ahead ?? 0) < -0.005)
        let fill = down ? Theme.planPink : Theme.lime
        let ink = down ? Color.white : Theme.ink
        HStack(alignment: .center, spacing: 12) {
            VStack(alignment: .leading, spacing: 2) {
                Text((abs(b) < 0.005 ? "Settled · no cash" : (b > 0 ? role.theyPay : role.youPay)).uppercased())
                    .font(.mono(10)).tracking(1).opacity(0.7)
                Text(Format.money(abs(b))).font(.display(26)).tracking(-0.8).monospacedDigit().displayTrim(26)
            }
            Spacer(minLength: 8)
            if let read {
                VStack(alignment: .trailing, spacing: 2) {
                    Text("AT MARKET").font(.mono(10)).tracking(1).opacity(0.7)
                    Text(Format.signedMoney(read.net)).font(.geist(17, .semibold)).monospacedDigit()
                }
            } else if let ahead = totals.ahead {
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
