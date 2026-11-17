import SwiftUI

// The Deal tab, simple: what are you doing (Buying, Selling, Trading, Price check), then a few
// big steps, one thing on screen at a time, in plain words for whichever side of the table
// you're on. The same deal underneath as the detailed page (`DealView`), one tap away.

/// The Deal tab: the simple flow, or the detailed page when picked.
struct DealTab: View {
    @AppStorage("deal-detailed") private var detailed = false

    /// Screenshots: -HoloDealDetailed (and the customer view and history) show the detailed page.
    private var forcedDetailed: Bool {
        let a = ProcessInfo.processInfo.arguments
        return Demo.isOn && (a.contains("-HoloDealDetailed") || a.contains("-HoloDealCustomer") || a.contains("-HoloDealHistory"))
    }

    var body: some View {
        if detailed || forcedDetailed { DealView() } else { DealFlowView() }
    }
}

/// What you're doing at the table.
enum DealFlowMode: String {
    case buying, selling, trading, check
}

struct DealFlowView: View {
    @Environment(CollectionStore.self) private var store
    @Environment(DealStore.self) private var deals
    @AppStorage("deal-flow-mode") private var modeRaw = ""
    @AppStorage("deal-detailed") private var detailed = false
    @State private var step = 0
    @State private var path = NavigationPath()
    @State private var scanning: DealSide?
    @State private var searching: DealSide?
    @State private var closing = false
    @State private var clearing = false
    @State private var parkedList = false
    /// Price check: the cards looked up, newest first.
    @State private var checks: [ScanCandidate] = []
    @State private var checkScanning = false

    private var mode: DealFlowMode? { DealFlowMode(rawValue: modeRaw) }

    var body: some View {
        NavigationStack(path: $path) {
            Group {
                switch mode {
                case nil: start
                case .check: priceCheck
                case let m?: flow(m)
                }
            }
            .background(Theme.background)
            .navigationBarTitleDisplayMode(.inline)
            .toolbarBackground(.hidden, for: .navigationBar)
            .clearTopEdge()
            .navigationDestination(for: DealRoute.self) { _ in DealHistoryView() }
            .navigationDestination(for: DealRecord.self) { DealRecordDetail(recordId: $0.id) }
            .navigationDestination(for: String.self) { ProductDetailView(productId: $0) }
            .tabTopReset("deal", path: $path)
        }
        .sheet(isPresented: $closing) { DealCloseSheet() }
        .sheet(isPresented: $parkedList) { ParkedDealsSheet() }
        .sheet(item: $searching) { side in DealPickerSheet(side: side) }
        .fullScreenCover(item: $scanning) { side in
            ScanView(dealSide: side, onPick: { c, read in deals.addScanned(c, read: read, to: side, store: store) },
                     trayTitle: side == .incoming ? "Their cards" : "Your cards")
        }
        .fullScreenCover(isPresented: $checkScanning) {
            ScanView(dealSide: .incoming, onPick: { c, _ in
                checks.insert(c, at: 0)
                return (true, "Price checked")
            }, trayTitle: "Price check")
        }
        .alert("Clear this deal?", isPresented: $clearing) {
            Button("Cancel", role: .cancel) {}
            Button("Clear", role: .destructive) { withAnimation(.snappy) { deals.update { $0 = DealState() } }; modeRaw = ""; step = 0 }
        } message: {
            Text("The cards and prices in it go. Nothing has been recorded\u{00A0}yet.")
        }
        // The simple flow has no deal bar in the tab bar's place.
        .onAppear {
            Router.shared.dealDocked = false
            // A deal already under way (from the detailed page, or parked): pick the matching flow.
            if mode == nil, deals.deal.kind != .empty { modeRaw = inferred.rawValue }
        }
        // Closed (or cleared elsewhere): back to the start.
        .onChange(of: deals.deal.kind == .empty) { was, empty in
            if empty, !was, mode != .check { modeRaw = ""; step = 0 }
        }
    }

    private var inferred: DealFlowMode {
        let d = deals.deal
        if !d.incoming.isEmpty && !d.outgoing.isEmpty { return .trading }
        return d.outgoing.isEmpty ? .buying : .selling
    }

    // MARK: Start

    private var start: some View {
        ScrollView {
            VStack(alignment: .leading, spacing: 14) {
                VStack(alignment: .leading, spacing: 6) {
                    Text("Deal").font(.display(40)).tracking(-1.2)
                    Text("What are you doing?").font(.geist(17)).foregroundStyle(Theme.muted)
                }
                .padding(.bottom, 8)
                bigChoice(.buying, icon: "bag.fill", title: "Buying", line: "Their cards, your cash")
                bigChoice(.selling, icon: "banknote.fill", title: "Selling", line: "Your cards, their cash")
                bigChoice(.trading, icon: "arrow.left.arrow.right", title: "Trading", line: "Cards for cards, plus any cash")
                bigChoice(.check, icon: "viewfinder", title: "Price check", line: "Scan a card, see what it's worth")
                HStack(spacing: 18) {
                    Button { path.append(DealRoute.history) } label: { Label("Closed deals", systemImage: "clock.arrow.circlepath") }
                    if !deals.parked.isEmpty {
                        Button { parkedList = true } label: { Label("Parked (\(deals.parked.count))", systemImage: "parkingsign") }
                    }
                    Spacer()
                    Button("Detailed view") { detailed = true }
                }
                .font(.geist(14, .medium))
                .foregroundStyle(Theme.muted)
                .buttonStyle(.plain)
                .padding(.top, 10)
            }
            .padding(.horizontal, 16)
            .padding(.top, 12)
            .padding(.bottom, HoloTabBar<Int>.clearance + 20)
        }
    }

    private func bigChoice(_ m: DealFlowMode, icon: String, title: String, line: String) -> some View {
        Button {
            Haptics.tap()
            step = 0
            modeRaw = m.rawValue
        } label: {
            HStack(spacing: 16) {
                Image(systemName: icon).font(.system(size: 22, weight: .semibold)).foregroundStyle(Theme.ink)
                    .frame(width: 56, height: 56).background(Circle().fill(Theme.lime))
                VStack(alignment: .leading, spacing: 3) {
                    Text(title).font(.display(26)).tracking(-0.6).foregroundStyle(.white)
                    Text(line).font(.geist(15)).foregroundStyle(Theme.muted)
                }
                Spacer(minLength: 8)
                Image(systemName: "chevron.right").font(.system(size: 16, weight: .semibold)).foregroundStyle(Theme.muted)
            }
            .padding(18)
            .frame(maxWidth: .infinity, minHeight: 96, alignment: .leading)
            .background(RoundedRectangle(cornerRadius: 24, style: .continuous).fill(Theme.surface))
            .overlay(RoundedRectangle(cornerRadius: 24, style: .continuous).strokeBorder(Theme.border))
            .contentShape(RoundedRectangle(cornerRadius: 24))
        }
        .buttonStyle(.plain)
    }

    // MARK: A deal, step by step

    /// The steps for each kind of deal: whose cards to scan, then settle.
    private func steps(_ m: DealFlowMode) -> [(title: String, side: DealSide?)] {
        switch m {
        case .buying: return [("Their cards", .incoming), ("Settle", nil)]
        case .selling: return [("Your cards", .outgoing), ("Settle", nil)]
        case .trading: return [("Your cards", .outgoing), ("Their cards", .incoming), ("Settle", nil)]
        case .check: return []
        }
    }

    private func flow(_ m: DealFlowMode) -> some View {
        let all = steps(m)
        let current = min(step, all.count - 1)
        return VStack(spacing: 0) {
            flowHeader(m, steps: all, current: current)
            if let side = all[current].side {
                cardsStep(side, mode: m, last: current == all.count - 2)
            } else {
                DealSettle(mode: m, onClose: { closing = true }, onBack: { withAnimation(.snappy) { step = max(0, current - 1) } })
            }
        }
    }

    private func flowHeader(_ m: DealFlowMode, steps all: [(title: String, side: DealSide?)], current: Int) -> some View {
        VStack(alignment: .leading, spacing: 14) {
            HStack {
                Button {
                    Haptics.tap()
                    if current > 0 { withAnimation(.snappy) { step = current - 1 } } else { modeRaw = "" }
                } label: {
                    Image(systemName: "chevron.left").font(.system(size: 17, weight: .semibold)).foregroundStyle(.white)
                        .frame(width: 44, height: 44).liquidGlass(in: Circle())
                }
                .buttonStyle(.plain)
                .accessibilityLabel(current > 0 ? "Back" : "Start over")
                Spacer()
                Text(m == .buying ? "Buying" : m == .selling ? "Selling" : "Trading").font(.geist(17, .semibold))
                Spacer()
                Menu {
                    Button("Detailed view") { detailed = true }
                    Button("Park this deal") { deals.park(name: ""); modeRaw = ""; step = 0 }
                        .disabled(deals.deal.kind == .empty)
                    Button("Clear deal", role: .destructive) { clearing = true }
                        .disabled(deals.deal.kind == .empty)
                } label: {
                    Image(systemName: "ellipsis").font(.system(size: 17, weight: .semibold)).foregroundStyle(.white)
                        .frame(width: 44, height: 44).liquidGlass(in: Circle())
                }
                .accessibilityLabel("More")
            }
            // Where you are: one segment per step, the current and done ones lit.
            HStack(spacing: 6) {
                ForEach(Array(all.enumerated()), id: \.offset) { i, s in
                    VStack(alignment: .leading, spacing: 6) {
                        Capsule().fill(i <= current ? Theme.lime : Color.white.opacity(0.12)).frame(height: 4)
                        Text("\(i + 1) \(s.title)").font(.geist(12, i == current ? .semibold : .medium))
                            .foregroundStyle(i == current ? .white : Theme.muted).lineLimit(1)
                    }
                    .frame(maxWidth: .infinity, alignment: .leading)
                }
            }
        }
        .padding(.horizontal, 16)
        .padding(.top, 8)
        .padding(.bottom, 12)
    }

    /// One side's cards: a big Scan button, the cards as big rows, the running total pinned
    /// at the bottom with Next.
    private func cardsStep(_ side: DealSide, mode m: DealFlowMode, last: Bool) -> some View {
        let items = side == .incoming ? deals.deal.incoming : deals.deal.outgoing
        let market = items.reduce(0) { $0 + ($1.market ?? 0) * Double($1.qty) }
        let count = items.reduce(0) { $0 + $1.qty }
        let theirs = side == .incoming
        return ScrollView {
            VStack(alignment: .leading, spacing: 14) {
                Text(theirs ? (m == .trading ? "Scan their cards" : "Scan what you're buying") : (m == .trading ? "Scan your cards" : "Scan what you're selling"))
                    .font(.display(28)).tracking(-0.7)
                HStack(spacing: 10) {
                    Button { Haptics.tap(); scanning = side } label: {
                        Label("Scan", systemImage: "viewfinder").font(.geist(20, .semibold))
                    }
                    .buttonStyle(Button3D(kind: .lime, height: 64))
                    Button { searching = side } label: {
                        Image(systemName: "magnifyingglass").font(.system(size: 20, weight: .semibold))
                    }
                    .buttonStyle(Button3D(kind: .dark, fullWidth: false, height: 64))
                    .accessibilityLabel("Search instead")
                }
                if items.isEmpty {
                    Text(theirs ? "Their cards show here, with what each is worth." : "Your cards show here, with what each is worth.")
                        .font(.geist(15)).foregroundStyle(Theme.muted)
                        .frame(maxWidth: .infinity, minHeight: 140)
                } else {
                    VStack(spacing: 0) {
                        ForEach(items) { item in
                            DealBigRow(item: item, onOpen: { path.append(item.product.id) }) {
                                Haptics.remove()
                                withAnimation(.snappy) {
                                    deals.update { d in
                                        if theirs { d.incoming.removeAll { $0.key == item.key } } else { d.outgoing.removeAll { $0.key == item.key } }
                                    }
                                }
                            }
                        }
                    }
                }
            }
            .padding(.horizontal, 16)
            .padding(.bottom, 24)
        }
        .safeAreaInset(edge: .bottom, spacing: 0) {
            HStack(alignment: .center, spacing: 14) {
                VStack(alignment: .leading, spacing: 2) {
                    Text(Format.money(market)).font(.display(36)).tracking(-1).monospacedDigit()
                        .contentTransition(.numericText()).lineLimit(1).minimumScaleFactor(0.6)
                    Text("Market value · \(count) card\(count == 1 ? "" : "s")").font(.geist(13)).foregroundStyle(Theme.muted)
                }
                Spacer(minLength: 8)
                Button {
                    Haptics.tap()
                    withAnimation(.snappy) { step += 1 }
                } label: {
                    HStack(spacing: 6) {
                        Text(m == .trading && !last ? "Next" : "Settle")
                        Image(systemName: "arrow.right").font(.system(size: 15, weight: .semibold))
                    }
                    .font(.geist(18, .semibold))
                }
                .buttonStyle(Button3D(kind: .lime, fullWidth: false, height: 60))
                .fixedSize()
                .disabled(items.isEmpty && m != .trading)
                .opacity(items.isEmpty && m != .trading ? 0.4 : 1)
            }
            .padding(.horizontal, 16).padding(.top, 14)
            .padding(.bottom, HoloTabBar<Int>.clearance)
            .background(Color.black.opacity(0.92).ignoresSafeArea())
            .overlay(alignment: .top) { Rectangle().fill(Color.white.opacity(0.08)).frame(height: 1) }
        }
    }

    // MARK: Price check

    private var priceCheck: some View {
        ScrollView {
            VStack(alignment: .leading, spacing: 14) {
                HStack {
                    Button { modeRaw = ""; checks = [] } label: {
                        Image(systemName: "chevron.left").font(.system(size: 17, weight: .semibold)).foregroundStyle(.white)
                            .frame(width: 44, height: 44).liquidGlass(in: Circle())
                    }
                    .buttonStyle(.plain)
                    .accessibilityLabel("Back")
                    Spacer()
                }
                Text("Price check").font(.display(32)).tracking(-0.8)
                Button { Haptics.tap(); checkScanning = true } label: {
                    Label("Scan a card", systemImage: "viewfinder").font(.geist(20, .semibold))
                }
                .buttonStyle(Button3D(kind: .lime, height: 64))
                if checks.isEmpty {
                    Text("Each card you scan shows here with its price, big. Nothing is added to a deal or your collection.")
                        .font(.geist(15)).foregroundStyle(Theme.muted)
                        .fixedSize(horizontal: false, vertical: true)
                        .padding(.top, 6)
                } else {
                    ForEach(Array(checks.enumerated()), id: \.offset) { i, c in
                        Button { path.append(c.product.id) } label: {
                            HStack(spacing: 14) {
                                ProductImage(product: c.product, cornerRadius: 6).frame(width: i == 0 ? 96 : 56, height: i == 0 ? 134 : 78)
                                VStack(alignment: .leading, spacing: 4) {
                                    Text(c.product.name).font(.geist(i == 0 ? 18 : 15, .semibold)).foregroundStyle(.white).lineLimit(2)
                                    Text(c.product.subtitle).font(.geist(13)).foregroundStyle(Theme.muted).lineLimit(1)
                                    Text(Format.money(c.slabMarket ?? c.market)).font(.display(i == 0 ? 44 : 24)).tracking(-1).monospacedDigit()
                                        .foregroundStyle(.white).lineLimit(1).minimumScaleFactor(0.6)
                                }
                                Spacer(minLength: 0)
                            }
                            .padding(.vertical, 10)
                            .contentShape(Rectangle())
                        }
                        .buttonStyle(.plain)
                        Rectangle().fill(Color.white.opacity(0.08)).frame(height: 1)
                    }
                }
            }
            .padding(.horizontal, 16)
            .padding(.top, 8)
            .padding(.bottom, HoloTabBar<Int>.clearance + 20)
        }
    }
}

/// One card in a deal step: big picture, name, set and market; × to take it out.
private struct DealBigRow: View {
    var item: DealItem
    var onOpen: () -> Void
    var onRemove: () -> Void

    var body: some View {
        HStack(spacing: 14) {
            Button(action: onOpen) {
                ProductImage(product: item.product, cornerRadius: 6).frame(width: 60, height: 84)
            }
            .buttonStyle(.plain)
            VStack(alignment: .leading, spacing: 3) {
                Text(item.product.name).font(.geist(17, .semibold)).foregroundStyle(.white).lineLimit(2)
                Text([item.product.setName, item.grade.map { "\($0.company) \($0.grade)" }, item.qty > 1 ? "×\(item.qty)" : nil].compactMap { $0 }.joined(separator: " · "))
                    .font(.geist(13)).foregroundStyle(Theme.muted).lineLimit(1)
                Text(Format.money((item.market ?? 0) * Double(item.qty))).font(.display(22)).tracking(-0.5).monospacedDigit().foregroundStyle(.white)
            }
            Spacer(minLength: 6)
            Button(action: onRemove) {
                Image(systemName: "xmark").font(.system(size: 14, weight: .bold)).foregroundStyle(.white)
                    .frame(width: 44, height: 44).background(Circle().fill(Color.white.opacity(0.1)))
            }
            .buttonStyle(.plain)
            .accessibilityLabel("Take \(item.product.name) out")
        }
        .padding(.vertical, 12)
        .overlay(alignment: .bottom) { Rectangle().fill(Color.white.opacity(0.08)).frame(height: 1) }
    }
}

/// The last step: the price, and one big verdict on whether it's good for you.
private struct DealSettle: View {
    var mode: DealFlowMode
    var onClose: () -> Void
    var onBack: () -> Void
    @Environment(CollectionStore.self) private var store
    @Environment(DealStore.self) private var deals
    @State private var amount = ""
    /// Trading: who pays the cash.
    @State private var theyPay = true
    @FocusState private var typing: Bool

    private var inMarket: Double { deals.deal.incoming.reduce(0) { $0 + ($1.market ?? 0) * Double($1.qty) } }
    private var outMarket: Double { deals.deal.outgoing.reduce(0) { $0 + ($1.market ?? 0) * Double($1.qty) } }
    private var typed: Double? { MoneyField.value(amount) }
    /// What you paid for the cards going out, where known.
    private var outCost: Double? {
        let costs = deals.deal.outgoing.compactMap { deals.cost(of: $0, in: store).map { c in c * Double($0.qty) } }
        return costs.count == deals.deal.outgoing.count && !costs.isEmpty ? costs.reduce(0, +) : nil
    }

    var body: some View {
        ScrollView {
            VStack(alignment: .leading, spacing: 18) {
                Text(question).font(.display(28)).tracking(-0.7)
                if mode == .trading {
                    ChipPicker(options: [(true, "They pay you"), (false, "You pay them")], selection: $theyPay, fills: true)
                }
                // The price, typed big.
                HStack(spacing: 4) {
                    Text("$").font(.display(48)).foregroundStyle(Theme.muted)
                    TextField("0", text: $amount)
                        .font(.display(56)).tracking(-1.5).monospacedDigit()
                        .keyboardType(.decimalPad)
                        .focused($typing)
                }
                .padding(.horizontal, 18).padding(.vertical, 10)
                .background(RoundedRectangle(cornerRadius: 22, style: .continuous).fill(Theme.surface))
                .overlay(RoundedRectangle(cornerRadius: 22, style: .continuous).strokeBorder(typing ? Theme.lime : Theme.border, lineWidth: typing ? 1.5 : 1))
                if mode != .trading {
                    // Nudge the price without typing.
                    HStack(spacing: 8) {
                        ForEach([-10.0, -5, 5, 10], id: \.self) { d in
                            Button { nudge(d) } label: {
                                Text(d > 0 ? "+$\(Int(d))" : "−$\(Int(-d))").font(.geist(17, .semibold)).monospacedDigit()
                            }
                            .buttonStyle(Button3D(kind: .dark, height: 52))
                        }
                    }
                }
                verdict
                Text(marketLine).font(.geist(14)).foregroundStyle(Theme.muted).monospacedDigit()
            }
            .padding(.horizontal, 16)
            .padding(.bottom, 24)
        }
        .scrollDismissesKeyboard(.interactively)
        .safeAreaInset(edge: .bottom, spacing: 0) {
            Button {
                Haptics.tap()
                typing = false
                apply()
                onClose()
            } label: {
                Text("Close deal").font(.geist(20, .semibold))
            }
            .buttonStyle(Button3D(kind: .lime, height: 64))
            .disabled(deals.deal.kind == .empty)
            .padding(.horizontal, 16).padding(.top, 14)
            .padding(.bottom, HoloTabBar<Int>.clearance)
            .background(Color.black.opacity(0.92).ignoresSafeArea())
            .overlay(alignment: .top) { Rectangle().fill(Color.white.opacity(0.08)).frame(height: 1) }
        }
        .onAppear(perform: load)
        .onChange(of: amount) { _, _ in apply() }
        .onChange(of: theyPay) { _, _ in apply() }
    }

    private var question: String {
        switch mode {
        case .buying: return "What are they asking?"
        case .selling: return "What are they offering?"
        default: return "Any cash on top?"
        }
    }

    private var marketLine: String {
        switch mode {
        case .buying: return "Their cards: \(Format.money(inMarket)) market"
        case .selling: return "Your cards: \(Format.money(outMarket)) market" + (outCost.map { " · you paid \(Format.money($0))" } ?? "")
        default: return "Your cards \(Format.money(outMarket)) · their cards \(Format.money(inMarket)) market"
        }
    }

    /// One big line, lime when it's good for you, pink when it isn't.
    @ViewBuilder private var verdict: some View {
        let v = verdictText
        if let v {
            VStack(alignment: .leading, spacing: 6) {
                Text(v.big).font(.display(34)).tracking(-0.9).foregroundStyle(v.good ? Theme.lime : Theme.planPink)
                    .fixedSize(horizontal: false, vertical: true)
                if let small = v.small { Text(small).font(.geist(15)).foregroundStyle(.white) }
            }
            .padding(18)
            .frame(maxWidth: .infinity, alignment: .leading)
            .background(RoundedRectangle(cornerRadius: 22, style: .continuous).fill((v.good ? Theme.lime : Theme.planPink).opacity(0.1)))
            .overlay(RoundedRectangle(cornerRadius: 22, style: .continuous).strokeBorder((v.good ? Theme.lime : Theme.planPink).opacity(0.4)))
            .animation(.snappy, value: v.big)
        }
    }

    private var verdictText: (big: String, small: String?, good: Bool)? {
        switch mode {
        case .buying:
            guard let ask = typed, inMarket > 0 else { return nil }
            let diff = inMarket - ask
            let pct = Int((ask / inMarket * 100).rounded())
            if abs(diff) < 0.5 { return ("Right at market", "\(pct)% of market", true) }
            return (diff > 0 ? "You're paying \(Format.money(diff)) under market" : "You're paying \(Format.money(-diff)) over market", "\(pct)% of market", diff > 0)
        case .selling:
            guard let offer = typed, outMarket > 0 else { return nil }
            let pct = Int((offer / outMarket * 100).rounded())
            let made = outCost.map { offer - $0 }
            let small = made.map { $0 >= 0 ? "You'd make \(Format.money($0)) on what you paid" : "You'd lose \(Format.money(-$0)) on what you paid" }
            return ("They're offering \(pct)% of market", small, made.map { $0 >= 0 } ?? (pct >= 70))
        default:
            let cash = (typed ?? 0) * (theyPay ? 1 : -1)
            let net = inMarket - outMarket + cash
            guard inMarket > 0 || outMarket > 0 else { return nil }
            if abs(net) < 0.5 { return ("Even trade", nil, true) }
            let even = typed == nil || typed == 0 ? (net < 0 ? "Ask for \(Format.money(-net)) cash to even it" : "You could add \(Format.money(net)) cash to even it") : nil
            return (net > 0 ? "You're up \(Format.money(net))" : "You're down \(Format.money(-net))", even, net > 0)
        }
    }

    private func nudge(_ d: Double) {
        Haptics.tap()
        let base = typed ?? (mode == .buying ? inMarket : outMarket)
        let next = max(0, (base + d).rounded())
        amount = next == next.rounded() ? String(Int(next)) : String(format: "%.2f", next)
    }

    /// The typed price becomes the deal's agreed cash (signed: positive, they pay you).
    private func apply() {
        guard let v = typed else { return }
        switch mode {
        case .buying: deals.setAgreedCash(-v)
        case .selling: deals.setAgreedCash(v)
        default: deals.setAgreedCash(theyPay ? v : -v)
        }
    }

    private func load() {
        guard let cash = deals.deal.agreedCash else { return }
        let v = abs(cash)
        amount = v == v.rounded() ? String(Int(v)) : String(format: "%.2f", v)
        if mode == .trading { theyPay = cash >= 0 }
    }
}
