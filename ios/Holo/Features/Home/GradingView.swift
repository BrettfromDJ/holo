import SwiftUI

/// Your slabs, cards at the grader, and what's worth sending in, like the website's Grading page.
struct GradingView: View {
    @Environment(CollectionStore.self) private var store
    @Environment(GradingStore.self) private var grading
    @State private var summaries: [String: [EbaySummary]] = [:]
    @State private var loadedSummaries = false
    @State private var showAll = false
    @State private var editingCosts = false
    @State private var sending: HoldingView?
    /// The worth-grading row whose ⋯ is open.
    @State private var acting: HoldingView?
    @State private var returning: GradingStore.Submission?
    /// The slab being unboxed over the page (after "It's back", or a returned slab's first look).
    @State private var unboxing: Unboxing?

    struct Unboxing: Identifiable, Equatable {
        var id: String
        var productId: String
        var company: String
        var grade: String
        /// Wait before playing, e.g. while the return sheet slides down.
        var delay: Double
    }

    /// Returned slabs already unboxed this session (so a returned slab plays once per launch).
    private static var unboxed: Set<String> = []

    private static let shown = 8
    private var today: String { Format.day() }

    private var slabs: [HoldingView] {
        store.holdings.filter(\.identity.isGraded).sorted { ($0.value ?? 0) > ($1.value ?? 0) }
    }

    /// Raw singles worth more than $15 with upside as a PSA 10 after costs, best first.
    private var candidates: [(HoldingView, Grading.Outlook)] {
        store.holdings.compactMap { h -> (HoldingView, Grading.Outlook)? in
            guard !h.identity.isGraded, h.product?.isSealed == false, let price = h.price, price >= Grading.minRaw else { return nil }
            let summary = loadedSummaries ? summaryFor(summaries[h.identity.productId], printing: h.identity.printing) ?? EbaySummary(printing: nil, ungraded: EbayStats(count: 0), graded: [:], asOf: "") : nil
            let o = Grading.outlook(productId: h.identity.productId, raw: price, costs: grading.costs, summary: summary)
            return o.upside10 > 0 ? (h, o) : nil
        }
        // Biggest PSA 10 upside first, so the list reads in order of the figure it shows.
        .sorted { $0.1.upside10 > $1.1.upside10 }
    }

    var body: some View {
        let slabs = self.slabs
        let candidates = self.candidates
        ScrollView {
            VStack(alignment: .leading, spacing: 36) {
                // Only what has something in it: no $0.00 hero, empty slabs or empty grader panel.
                if !slabs.isEmpty { heroTop(slabs) }
                if !grading.sent.isEmpty || !grading.returned.isEmpty { atGrader.reveal() }
                worthGrading(candidates).reveal()
                if !slabs.isEmpty { yourSlabs(slabs).reveal() }
            }
            .padding(.top, slabs.isEmpty ? 8 : 0)
            .padding(.horizontal, 16)
            .padding(.bottom, 120)
        }
        .background(Theme.background)
        .replaysAnimations()
        .navigationBarTitleDisplayMode(.inline)
        .pageTitle("Grading")
        // The grading and shipping costs, behind a quiet icon at the top right.
        .toolbar {
            ToolbarItem(placement: .topBarTrailing) {
                Button { editingCosts = true } label: { Image(systemName: "slider.horizontal.3") }
                    .accessibilityLabel("Grading costs")
            }
        }
        .actionsSheet(item: $acting, title: { $0.product?.name }, product: { $0.product }) { h in
            let sent = (grading.atGrader[h.identity.key] ?? 0) >= h.quantity
            return [[
                SheetAction(title: sent ? "Sent for grading" : "Send for grading", icon: "paperplane", disabled: sent, run: { sending = h }),
            ], [
                SheetAction(title: "Grading costs", icon: "slider.horizontal.3", run: { editingCosts = true }),
            ]]
        }
        .task {
            await grading.load(userId: store.demo == nil ? store.userId : nil)
            let ids = Array(Set(store.holdings.filter { $0.product?.isSealed == false && $0.identity.productId.hasPrefix("tcgapi:") }.map(\.identity.productId))).sorted()
            if !ids.isEmpty, !loadedSummaries, let found = try? await Backend.shared.api.ebaySummaries(ids) {
                summaries = found
                loadedSummaries = true
            }
        }
        // The first look this session at a slab that came back: unbox the newest one.
        .onChange(of: grading.returned.map(\.id), initial: true) { _, _ in unboxNewestReturned() }
        .sheet(isPresented: $editingCosts) { CostsSheet() }
        .sheet(item: $sending) { SendSheet(holding: $0) }
        .sheet(item: $returning) { s in
            ReturnSheet(submission: s, onReturned: { grade in
                Self.unboxed.insert(s.id)
                unboxing = Unboxing(id: s.id, productId: s.productId, company: s.company, grade: grade, delay: 0.45)
            })
        }
        .overlay {
            if let u = unboxing {
                SlabUnboxing(product: store.products[u.productId], company: u.company, grade: u.grade, delay: u.delay) {
                    withAnimation(.easeOut(duration: 0.2)) { unboxing = nil }
                }
                .id(u.id)
                .transition(.opacity)
            }
        }
    }

    /// Unbox the newest returned slab not yet seen this session, and count the rest as seen.
    private func unboxNewestReturned() {
        let fresh = grading.returned.filter { !Self.unboxed.contains($0.id) }
        guard !fresh.isEmpty else { return }
        for s in fresh { Self.unboxed.insert(s.id) }
        guard unboxing == nil, returning == nil, let s = fresh.first, let g = s.grade else { return }
        unboxing = Unboxing(id: s.id, productId: s.productId, company: s.company, grade: g, delay: 0.5)
    }

    // MARK: Numbers

    private func heroTop(_ slabs: [HoldingView]) -> some View {
        let value = slabs.reduce(0) { $0 + ($1.value ?? 0) }
        let rawEquivalent = slabs.reduce(0.0) { sum, h in
            guard let raw = store.marketPrice(h.identity.productId, printing: h.identity.printing)?.market, h.value != nil else { return sum }
            return sum + raw * h.quantity
        }
        let stale = slabs.filter { h in
            guard h.isManual, let m = store.manualValue(h.identity) else { return false }
            return Timeline.daysBetween(m.date, today) > 60
        }.count
        let sentCount = grading.sent.reduce(0) { $0 + $1.quantity }
        let premium = value - rawEquivalent
        let count = Int(slabs.reduce(0) { $0 + $1.quantity })
        return SlabFanHero(slabs: slabs, value: value) {
            HStack(spacing: 8) {
                Text("\(count) slab\(count == 1 ? "" : "s")").font(.geist(13, .semibold)).monospacedDigit()
                    .foregroundStyle(Theme.ink)
                    .padding(.horizontal, 8).padding(.vertical, 3)
                    .background(Theme.lime, in: RoundedRectangle(cornerRadius: 6))
                if rawEquivalent > 0 {
                    Text(String(format: "%.1f× what they're worth raw", value / rawEquivalent)).font(.geist(13)).foregroundStyle(Theme.muted)
                }
            }
        } below: {
            // Only numbers that say something: no "0 at grader" or "0 to refresh".
            HStack(spacing: 8) {
                GlassStat(label: "Premium", value: rawEquivalent > 0 ? Format.signedMoney(premium) : "—", tint: rawEquivalent > 0 ? Theme.tone(premium) : .white)
                GlassStat(label: "Raw, they'd be", value: rawEquivalent > 0 ? Format.money(rawEquivalent) : "—")
                if sentCount > 0 {
                    GlassStat(label: "At grader", value: "\(Int(sentCount))")
                } else if stale > 0 {
                    GlassStat(label: "To refresh", value: "\(stale)")
                }
            }
        }
    }

    // MARK: At the grader

    private var atGrader: some View {
        VStack(alignment: .leading, spacing: 12) {
            MoreHeading(title: "At the grader", subtitle: "Cards stay raw until they come back")
            ForEach(grading.sent) { s in
                HStack(spacing: 12) {
                    CardLink(productId: s.productId) {
                        HStack(spacing: 12) {
                            HoldingArt(product: store.products[s.productId], cornerRadius: 6, caption: false).frame(width: 33, height: 46)
                            VStack(alignment: .leading, spacing: 2) {
                                (Text(s.quantity > 1 ? "\(Int(s.quantity)) × " : "").foregroundColor(Theme.muted) + Text(store.products[s.productId]?.name ?? "Card"))
                                    .font(.geist(14, .medium)).lineLimit(1)
                                Text(sentLine(s)).font(.geist(12)).foregroundStyle(Theme.muted).lineLimit(1)
                            }
                            Spacer(minLength: 4)
                        }
                    }
                    .buttonStyle(.plain)
                    Button("It's back") { returning = s }
                        .buttonStyle(Button3D(kind: .dark, fullWidth: false, height: 34))
                    Menu {
                        Button("Remove submission", role: .destructive) { grading.cancel(s.id) }
                    } label: {
                        Image(systemName: "ellipsis").foregroundStyle(Theme.muted).frame(width: 44, height: 44).contentShape(Rectangle())
                    }
                }
                .padding(.vertical, 4)
            }
            if !grading.returned.isEmpty {
                Rectangle().fill(Theme.border).frame(height: 1).padding(.top, 4)
                MonoLabel(text: "Recently returned", color: Theme.subtle)
                ForEach(grading.returned) { s in
                    // Tap one to unbox it again.
                    Button {
                        if let g = s.grade { unboxing = Unboxing(id: s.id, productId: s.productId, company: s.company, grade: g, delay: 0) }
                    } label: {
                        HStack(spacing: 8) {
                            Tag(text: "\(s.company) \(s.grade ?? "?")", tint: Theme.lime)
                            Text(store.products[s.productId]?.name ?? "Card").font(.geist(13)).lineLimit(1)
                            Spacer(minLength: 4)
                            Text(s.returnedOn.flatMap { Format.isoDay.date(from: $0)?.formatted(date: .abbreviated, time: .omitted) } ?? "").font(.geist(12)).foregroundStyle(Theme.subtle)
                        }
                        .contentShape(Rectangle())
                    }
                    .buttonStyle(.plain)
                }
            }
        }
        .surface(radius: 16, padding: 16)
    }

    private func sentLine(_ s: GradingStore.Submission) -> String {
        let days = Timeline.daysBetween(s.sentOn, today)
        let date = Format.isoDay.date(from: s.sentOn)?.formatted(date: .abbreviated, time: .omitted) ?? s.sentOn
        return "\(s.company) \(s.service) · sent \(date)\(days > 0 && days < .max ? " · \(days) day\(days == 1 ? "" : "s") ago" : "")"
    }

    // MARK: Worth grading

    private func worthGrading(_ candidates: [(HoldingView, Grading.Outlook)]) -> some View {
        let away = grading.atGrader
        return VStack(alignment: .leading, spacing: 8) {
            MoreHeading(title: "Worth grading", subtitle: "What each could make as a PSA 10, after \(Format.moneyWhole(grading.costs.fee + grading.costs.shipping)) to grade and ship.")
            if candidates.isEmpty {
                Text("No raw singles worth more than \(Format.moneyWhole(Grading.minRaw)) with upside after grading\u{00A0}costs.")
                    .font(.geist(13)).foregroundStyle(Theme.muted).padding(.vertical, 12)
            }
            // Plain rows on the page (no panel), divided by a hairline.
            let rows = showAll ? candidates : Array(candidates.prefix(Self.shown))
            let firstId = rows.first?.0.id
            VStack(spacing: 0) {
                ForEach(rows, id: \.0.id) { h, o in
                    let est = o.source == .estimate ? "≈" : ""
                    let sent = (away[h.identity.key] ?? 0) >= h.quantity
                    // Picture | name, raw → PSA 10, one quiet line | the upside, then ⋯.
                    HStack(alignment: .center, spacing: 12) {
                        CardLink(productId: h.identity.productId, identity: h.identity) {
                            HStack(alignment: .center, spacing: 12) {
                                HoldingArt(product: h.product, identity: h.identity, cornerRadius: 5, caption: false).frame(width: 40, height: 56)
                                VStack(alignment: .leading, spacing: 3) {
                                    Text(h.product?.name ?? "Card").font(.geist(15, .medium)).foregroundStyle(.white).lineLimit(1)
                                    Text("\(Format.moneyWhole(o.raw)) raw → \(est)\(Format.moneyWhole(o.psa10)) PSA 10")
                                        .font(.geist(12)).monospacedDigit().foregroundStyle(Theme.muted).lineLimit(1).minimumScaleFactor(0.8)
                                    Text(detail(o, sent: sent))
                                        .font(.geist(12)).monospacedDigit().foregroundStyle(Theme.subtle).lineLimit(1)
                                }
                                Spacer(minLength: 8)
                                Text(Self.signedWhole(o.upside10))
                                    .font(.geist(16, .semibold)).monospacedDigit().foregroundStyle(Theme.up)
                                    .lineLimit(1).fixedSize()
                            }
                            .contentShape(Rectangle())
                        }
                        .buttonStyle(.plain)
                        RowMoreButton(label: h.product?.name) { acting = h }
                            .padding(.trailing, -10)
                    }
                    .padding(.vertical, 12)
                    .overlay(alignment: .top) {
                        if h.id != firstId { Rectangle().fill(Color.white.opacity(0.08)).frame(height: 1) }
                    }
                }
            }
            if candidates.count > Self.shown {
                Button(showAll ? "Show fewer" : "Show all \(candidates.count)") { showAll.toggle() }
                    .font(.geist(14, .medium)).foregroundStyle(Theme.muted)
                    .padding(.top, 4)
            }
        }
    }

    /// The row's quiet line: sent, or what a 9 makes and how 10s sell ("+$1,024 at a 9 · hard to sell").
    private func detail(_ o: Grading.Outlook, sent: Bool) -> String {
        if sent { return "At the grader" }
        let nine = "\(Self.signedWhole(o.upside9)) at a 9"
        guard o.source == .sales else { return "\(nine) · estimate" }
        let speed = o.psa10Sales >= 52 ? "10s sell fast" : o.psa10Sales >= 12 ? "10s sell steadily" : "10s sell slowly"
        return "\(nine) · \(speed)"
    }

    /// "+$25,099" / "−$40": whole dollars with a sign.
    static func signedWhole(_ v: Double) -> String { (v < 0 ? "−" : "+") + Format.moneyWhole(abs(v)) }

    // MARK: Slabs

    private func yourSlabs(_ slabs: [HoldingView]) -> some View {
        VStack(alignment: .leading, spacing: 14) {
            MoreHeading(title: "Your slabs", subtitle: slabs.isEmpty ? "No graded cards yet. Add one with Graded switched on, or mark a submission as returned." : "Graded cards, by value")
            LazyVGrid(columns: [GridItem(.flexible(), spacing: 14), GridItem(.flexible(), spacing: 14)], spacing: 24) {
                ForEach(Array(slabs.enumerated()), id: \.element.id) { i, h in
                    CardLink(productId: h.identity.productId, identity: h.identity) { slabTile(h) }.buttonStyle(.plain)
                        .popIn(delay: Double(min(i, 6)) * 0.07)
                }
            }
        }
    }

    private func slabTile(_ h: HoldingView) -> some View {
        let raw = store.marketPrice(h.identity.productId, printing: h.identity.printing)?.market
        let manualDate = h.isManual ? store.manualValue(h.identity)?.date : nil
        let staleDays = manualDate.map { Timeline.daysBetween($0, today) } ?? 0
        return VStack(alignment: .leading, spacing: 3) {
            HoldingArt(product: h.product, identity: h.identity, caption: false)
                .aspectRatio(4 / 5, contentMode: .fit)
                .frame(maxWidth: .infinity)
                .padding(.bottom, 9)
            Text(h.product?.name ?? "Card").font(.geist(13, .medium)).lineLimit(2)
            HStack(alignment: .firstTextBaseline, spacing: 6) {
                if h.price == nil {
                    Text("No value").font(.geist(14, .semibold)).foregroundStyle(Theme.subtle)
                } else {
                    Text(Format.money(h.value)).font(.geist(14, .semibold)).monospacedDigit()
                }
                if let raw, raw > 0, let p = h.price {
                    Text(String(format: "%.1f× raw", p / raw)).font(.mono(11)).foregroundStyle(Theme.muted)
                }
            }
            Text(h.isManual ? (staleDays > 60 ? "Your value · \(staleDays) days old" : "Your value") : h.price == nil ? "No recent eBay sales · set your value" : "eBay sold median")
                .font(.geist(11)).foregroundStyle(staleDays > 60 ? .white.opacity(0.8) : Theme.subtle).lineLimit(1)
        }
    }

    private func heading(_ title: String, _ sub: String) -> some View {
        VStack(alignment: .leading, spacing: 4) {
            Text(title).font(.geist(17, .semibold))
            Text(sub).font(.geist(13)).foregroundStyle(Theme.muted)
        }
    }
}

/// The fee and shipping assumed when weighing whether to grade. Fits its content: a title with a
/// round close, the two amounts in one panel, a note, and a lime Save.
struct CostsSheet: View {
    @Environment(GradingStore.self) private var grading
    @Environment(\.dismiss) private var dismiss
    @State private var fee = ""
    @State private var shipping = ""
    @State private var height: CGFloat = 330

    private var valid: Bool { MoneyField.value(fee) != nil && MoneyField.value(shipping) != nil }

    var body: some View {
        VStack(alignment: .leading, spacing: 18) {
            SheetHeader(title: "Grading costs") { dismiss() }
            SheetPanel {
                SheetMoneyRow(title: "Fee per card", text: $fee)
                SheetDivider()
                SheetMoneyRow(title: "Shipping per card", text: $shipping)
            }
            Text("Used to weigh which cards are worth grading, and as the default when you send one in. Shipping both ways, with\u{00A0}insurance.")
                .font(.geist(13)).foregroundStyle(Theme.muted).fixedSize(horizontal: false, vertical: true)
            SheetLimeButton(title: "Save", enabled: valid) {
                if let f = MoneyField.value(fee), let s = MoneyField.value(shipping) { grading.setCosts(.init(fee: f, shipping: s)) }
                dismiss()
            }
        }
        .padding(.horizontal, 20).padding(.top, 24).padding(.bottom, 8)
        .onGeometryChange(for: CGFloat.self) { $0.size.height } action: { height = $0 }
        .onAppear {
            fee = String(format: "%.2f", grading.costs.fee)
            shipping = String(format: "%.2f", grading.costs.shipping)
        }
        .presentationDetents([.height(height)])
        .glassSheet()
    }
}

/// Record raw copies as sent off for grading. Fits its content: title and close, the card, the
/// grader and service as chips, one panel of details, and a lime Mark as sent.
struct SendSheet: View {
    var holding: HoldingView
    @Environment(GradingStore.self) private var grading
    @Environment(\.dismiss) private var dismiss
    @State private var company = "PSA"
    @State private var service = "Value"
    @State private var quantity = 1
    @State private var fee = ""
    @State private var shipping = ""
    @State private var date = Date()
    @State private var height: CGFloat = 560

    private static let companies = ["PSA", "BGS", "CGC", "SGC", "TAG"]
    private static let services = ["Value", "Regular", "Express", "Super Express"]
    private var owned: Int { max(1, Int(holding.quantity)) }

    var body: some View {
        VStack(alignment: .leading, spacing: 18) {
            SheetHeader(title: "Send for grading") { dismiss() }
            HStack(spacing: 12) {
                HoldingArt(product: holding.product, identity: holding.identity, cornerRadius: 4, caption: false).frame(width: 40, height: 56)
                VStack(alignment: .leading, spacing: 3) {
                    Text(holding.product.map(ActionsSheet.shortName) ?? "Card").font(.geist(15, .semibold)).foregroundStyle(.white).lineLimit(1)
                    Text("Raw \(Format.moneyWhole(holding.price))").font(.geist(13)).monospacedDigit().foregroundStyle(Theme.muted)
                }
            }
            VStack(alignment: .leading, spacing: 8) {
                MonoLabel(text: "Grader")
                ChipPicker(options: Self.companies.map { ($0, $0) }, selection: $company, scrolls: true)
            }
            VStack(alignment: .leading, spacing: 8) {
                MonoLabel(text: "Service")
                ChipPicker(options: Self.services.map { ($0, $0) }, selection: $service, scrolls: true)
            }
            SheetPanel {
                if owned > 1 {
                    HStack {
                        Text("Copies").font(.geist(16)).foregroundStyle(.white)
                        Spacer()
                        Text("\(quantity) of \(owned)").font(.geist(16)).monospacedDigit().foregroundStyle(Theme.muted)
                        Stepper("", value: $quantity, in: 1...owned).labelsHidden().fixedSize()
                    }
                    .frame(minHeight: 50)
                    SheetDivider()
                }
                SheetMoneyRow(title: "Fee per card", text: $fee)
                SheetDivider()
                SheetMoneyRow(title: "Shipping per card", text: $shipping)
                SheetDivider()
                HStack {
                    Text("Sent").font(.geist(16)).foregroundStyle(.white)
                    Spacer()
                    DatePicker("", selection: $date, in: ...Date(), displayedComponents: .date).labelsHidden()
                }
                .frame(minHeight: 50)
            }
            Text("It stays in your collection raw until it comes\u{00A0}back.").font(.geist(13)).foregroundStyle(Theme.muted)
            SheetLimeButton(title: "Mark as sent") {
                grading.send(holding, company: company, service: service, quantity: Double(quantity),
                             fee: MoneyField.value(fee) ?? grading.costs.fee, shipping: MoneyField.value(shipping) ?? grading.costs.shipping, date: Format.day(date))
                UINotificationFeedbackGenerator().notificationOccurred(.success)
                dismiss()
            }
        }
        .padding(.horizontal, 20).padding(.top, 24).padding(.bottom, 8)
        .onGeometryChange(for: CGFloat.self) { $0.size.height } action: { height = $0 }
        .onAppear {
            fee = String(format: "%.2f", grading.costs.fee)
            shipping = String(format: "%.2f", grading.costs.shipping)
        }
        .presentationDetents([.height(height)])
        .glassSheet()
    }
}

// MARK: Small sheet pieces (one look for sheets that fit their content)

/// A sheet's title on the left and a round close on the right.
struct SheetHeader: View {
    var title: String
    var close: () -> Void
    var body: some View {
        HStack {
            Text(title).font(.geist(17, .semibold)).foregroundStyle(.white)
            Spacer()
            Button { Haptics.tap(); close() } label: {
                Image(systemName: "xmark").font(.system(size: 14, weight: .semibold)).foregroundStyle(.white)
                    .frame(width: 34, height: 34).background(Circle().fill(Color.white.opacity(0.1)))
            }
            .buttonStyle(.plain)
            .accessibilityLabel("Close")
        }
    }
}

/// Rows grouped in one faint panel on a sheet.
struct SheetPanel<Content: View>: View {
    @ViewBuilder var content: Content
    var body: some View {
        VStack(spacing: 0) { content }
            .padding(.horizontal, 16)
            .sheetPanel(radius: 18)
    }
}

struct SheetDivider: View {
    var body: some View { Rectangle().fill(Color.white.opacity(0.08)).frame(height: 1) }
}

/// A label on the left and a dollar amount typed on the right, one row tall.
struct SheetMoneyRow: View {
    var title: String
    @Binding var text: String
    var body: some View {
        HStack {
            Text(title).font(.geist(16)).foregroundStyle(.white)
            Spacer()
            Text("$").font(.geist(16)).foregroundStyle(Theme.muted)
            TextField("0.00", text: $text)
                .keyboardType(.decimalPad).multilineTextAlignment(.trailing).monospacedDigit()
                .font(.geist(16)).foregroundStyle(.white)
                .fixedSize()
        }
        .frame(minHeight: 50)
        .contentShape(Rectangle())
    }
}

/// The full-width lime button that ends a sheet.
struct SheetLimeButton: View {
    var title: String
    var enabled = true
    var action: () -> Void
    var body: some View {
        Button(action: action) {
            Text(title).font(.geist(16, .semibold)).foregroundStyle(Theme.ink)
                .frame(maxWidth: .infinity).frame(height: 52)
                .background(Capsule().fill(Theme.lime))
                .opacity(enabled ? 1 : 0.4)
        }
        .buttonStyle(.plain)
        .disabled(!enabled)
    }
}

/// A submission came back: pick the grade and it moves into a slab.
private struct ReturnSheet: View {
    var submission: GradingStore.Submission
    /// Called with the grade once it's saved (the page then unboxes the slab).
    var onReturned: (String) -> Void = { _ in }
    @Environment(GradingStore.self) private var grading
    @Environment(CollectionStore.self) private var store
    @Environment(GroupsStore.self) private var groups
    @Environment(\.dismiss) private var dismiss
    @State private var grade = "10"
    @State private var date = Date()
    @State private var saving = false
    @State private var error: String?

    @State private var height: CGFloat = 420

    var body: some View {
        VStack(alignment: .leading, spacing: 18) {
            SheetHeader(title: "It's back") { dismiss() }
            Text(store.products[submission.productId].map(ActionsSheet.shortName) ?? "Card")
                .font(.geist(15, .semibold)).foregroundStyle(.white).lineLimit(1)
            VStack(alignment: .leading, spacing: 8) {
                MonoLabel(text: "\(submission.company) grade")
                ChipPicker(options: WorthCalc.grades(for: submission.company).reversed().map { ($0, $0) }, selection: $grade, scrolls: true)
            }
            SheetPanel {
                HStack {
                    Text("Returned").font(.geist(16)).foregroundStyle(.white)
                    Spacer()
                    DatePicker("", selection: $date, in: ...Date(), displayedComponents: .date).labelsHidden()
                }
                .frame(minHeight: 50)
            }
            Text("The raw copies move into a \(submission.company) slab at what they cost you, plus the grading fee and\u{00A0}shipping.")
                .font(.geist(13)).foregroundStyle(Theme.muted).fixedSize(horizontal: false, vertical: true)
            if let error { Text(error).font(.geist(13)).foregroundStyle(.white) }
            SheetLimeButton(title: saving ? "Saving…" : "Save", enabled: !saving) { Task { await save() } }
        }
        .padding(.horizontal, 20).padding(.top, 24).padding(.bottom, 8)
        .onGeometryChange(for: CGFloat.self) { $0.size.height } action: { height = $0 }
        .presentationDetents([.height(height)])
        .glassSheet()
    }

    private func save() async {
        saving = true
        defer { saving = false }
        do {
            let from = groups.portfoliosOf(submission.rawIdentity.key)
            try await grading.complete(submission, grade: grade, date: Format.day(date), store: store)
            // Keep the slab in the same portfolios as the raw card it came from.
            let slab = HoldingIdentity(productId: submission.productId, printing: submission.printing, condition: "Near Mint", gradeCompany: submission.company, grade: grade)
            if groups.portfoliosOf(slab.key) != from { try await groups.place(slab.key, in: from, store: store) }
            UINotificationFeedbackGenerator().notificationOccurred(.success)
            onReturned(grade)
            dismiss()
        } catch {
            self.error = error.localizedDescription
        }
    }
}
