import SwiftUI

/// Your copy of a card, opened from Collection: what it's worth and what you made, its price
/// line, what it would be worth graded (raw) or its cert and bumper (slabs), sell or try a sale,
/// its history, and a button to the full card page.
struct HoldingSheet: View {
    /// The copy as it was when the sheet opened.
    private var opened: HoldingIdentity
    /// Opens the full card page (from Collection); nil when already on it.
    var onOpenCard: (() -> Void)?

    init(identity: HoldingIdentity, onOpenCard: (() -> Void)? = nil) {
        opened = identity
        self.onOpenCard = onOpenCard
    }

    @Environment(\.dismiss) private var dismiss
    @Environment(CollectionStore.self) private var store
    @Environment(GradingStore.self) private var grading
    @Environment(GroupsStore.self) private var groups
    @State private var namingShelf = false
    @State private var newShelf = ""
    @State private var selling = false
    @State private var removing = false
    @State private var editingDetails = false
    @State private var confirmDelete = false
    @State private var whatIf = false
    @State private var valuing = false
    @State private var sending = false
    @State private var certing = false
    @State private var bumpering = false
    @State private var editing: Txn?
    @State private var deleting: Txn?
    @State private var error: String?
    @State private var graded: GradedValues?
    /// The graded lookup has answered (or there's nothing to ask), so the If graded tiles show
    /// their final figures instead of jumping from an estimate.
    @State private var gradedReady = false

    var body: some View {
        // The copy now (it follows a demo card that switched to its real catalog card, or a copy
        // whose details changed, while open), looked up once per redraw and handed down. Tapping
        // a button here only flips a flag; the price chart and the history are their own views
        // with plain values, so they aren't redrawn for it.
        let identity = store.current(opened)
        let holding = store.holding(identity)
        return sheetBody(identity, holding).undoToast(bottom: 90).glassSheet()
    }

    @ViewBuilder private func sheetBody(_ identity: HoldingIdentity, _ holding: HoldingView?) -> some View {
        let product = store.products[identity.productId]
        ScrollView {
            VStack(alignment: .leading, spacing: 20) {
                // Title and Done sit in the content (no navigation bar), so nothing above the
                // content changes size while the sheet comes up and nothing shifts.
                titleRow
                header(identity, holding, product)
                if let h = holding {
                    HoldingWorth(holding: h, points: worthPoints(h))
                    tiles(h)
                    // How easily this exact copy sells (its grade, else ungraded), from the shared
                    // eBay cache; only cards with eBay data show it.
                    if EbaySalesCache.supports(identity.productId), !Demo.perfNoSellMeter {
                        // A CGC 10 sells on Pristine sales when it's marked Pristine, else on Gem Mint ones.
                        SellSpeedLine(productId: identity.productId, printing: identity.printing, grade: identity.gradeLabel,
                                      market: store.marketPrice(identity.productId, printing: identity.printing)?.market,
                                      pristine: Pristine.isCGCTen(company: identity.gradeCompany, grade: identity.grade) ? grading.pristine.contains(identity.key) : nil)
                    }
                    if identity.isGraded { slabRows(identity) } else if product?.isSealed == false { ifGraded(identity, h) }
                    actions(h)
                } else {
                    Text("You don't hold any of these right now.").font(.geist(14)).foregroundStyle(Theme.muted)
                }
                HoldingHistory(entries: store.entries(for: identity), editing: $editing, deleting: $deleting)
                if let error { Text(error).font(.geist(13)).foregroundStyle(Theme.down) }
            }
            .frame(maxWidth: .infinity, alignment: .leading)
            .padding(.horizontal, 20)
            .padding(.top, 18)
            .padding(.bottom, onOpenCard == nil ? 24 : 12)
        }
        // The sheet is glass, so the page behind shows through and it reads as a sheet.
        .scrollContentBackground(.hidden)
        .safeAreaInset(edge: .bottom) {
            if let onOpenCard {
                Button {
                    dismiss()
                    onOpenCard()
                } label: { Label("View card details", systemImage: "arrow.right").labelStyle(TrailingIconLabel()) }
                    .buttonStyle(Button3D(kind: .lime))
                    .padding(.horizontal, 20)
                    .padding(.vertical, 10)
            }
        }
        .sheet(isPresented: $selling) { if let h = holding { SellSheet(holding: h) } }
        .sheet(isPresented: $removing) { if let h = holding { RemoveSheet(holding: h) } }
        .sheet(isPresented: $editingDetails) { if let h = holding { EditDetailsSheet(holding: h) } }
        .alert("New list", isPresented: $namingShelf) {
            TextField("Grails, For sale at the show…", text: $newShelf)
            Button("Cancel", role: .cancel) { newShelf = "" }
            Button("Create") {
                let value = String(newShelf.trimmingCharacters(in: .whitespaces).prefix(40))
                newShelf = ""
                guard !value.isEmpty else { return }
                Task { await groupRun { _ = try await groups.createShelf(value, productIds: [identity.productId]) } }
            }
        }
        .alert("Delete this from your collection?", isPresented: $confirmDelete) {
            Button("Cancel", role: .cancel) {}
            Button("Delete from collection", role: .destructive) {
                Task {
                    do {
                        try await store.deleteCopy(identity)
                        dismiss()
                    } catch { self.error = error.localizedDescription }
                }
            }
        } message: {
            Text("It's removed as if you never added it: it leaves your value, cost and gains. To count it as a loss instead, use Remove.")
        }
        .sheet(isPresented: $whatIf) { if let h = holding { SellCalculatorSheet(holding: h) } }
        .sheet(isPresented: $sending) { if let h = holding { SendSheet(holding: h) } }
        .sheet(isPresented: $certing) { if let h = holding { CertSheet(holding: h) } }
        .sheet(isPresented: $bumpering) { if let h = holding { BumperSheet(holding: h) } }
        .sheet(isPresented: $valuing) { ManualValueSheet(identity: identity, current: store.manualValue(identity)?.value) }
        .sheet(item: $editing) { t in EntryEditSheet(entry: t) }
        .alert("Delete this entry?", isPresented: Binding(get: { deleting != nil }, set: { if !$0 { deleting = nil } })) {
            Button("Cancel", role: .cancel) {}
            Button("Delete", role: .destructive) {
                guard let t = deleting else { return }
                Task {
                    do { try await store.delete(t) } catch { self.error = error.localizedDescription }
                }
            }
        } message: {
            Text("Your totals update as if it never happened. The original stays in the record.")
        }
        .task(id: identity.productId) {
            defer { withAnimation(.easeOut(duration: 0.25)) { gradedReady = true } }
            guard identity.productId.hasPrefix("tcgapi:"), !identity.isGraded else { return }
            graded = (try? await Backend.shared.api.gradedValues([identity.productId]))?[identity.productId]
        }
        // Just short of full height: iOS 26 keeps a sheet glass only while it isn't full screen.
        .presentationDetents([.fraction(0.93)])
        .presentationDragIndicator(.visible)
    }

    // MARK: Parts

    private var titleRow: some View {
        ZStack {
            // The card page's lime tag: in your collection, and how many copies you have.
            let owns = store.holdings(for: identity.productId).reduce(0) { $0 + $1.quantity }
            SkewTag(text: "Owned" + (owns > 1 ? " ×\(Int(owns))" : ""), icon: "checkmark")
            HStack {
                Spacer()
                Button("Done") { dismiss() }
                    .font(.geist(16, .semibold)).foregroundStyle(Theme.lime)
                    .padding(.horizontal, 14).frame(height: 36)
                    .background(Capsule().fill(Color.white.opacity(0.09)))
            }
        }
        .frame(maxWidth: .infinity)
    }

    private func header(_ identity: HoldingIdentity, _ holding: HoldingView?, _ product: Product?) -> some View {
        HStack(spacing: 14) {
            HoldingArt(product: product, identity: identity, cornerRadius: 6, caption: false).frame(width: 62, height: 86)
            VStack(alignment: .leading, spacing: 5) {
                Text(product?.name ?? "Unknown").font(.geist(17, .semibold)).lineLimit(2)
                HStack(spacing: 6) {
                    Tag(text: holding?.label ?? (product?.isSealed == true ? "Sealed" : identity.condition), tint: identity.isGraded ? Theme.lime : .white)
                    if store.isPulled(identity) { PulledBadge() }
                    if let set = product?.setName { Text(set).font(.geist(12)).foregroundStyle(Theme.muted).lineLimit(1) }
                }
            }
            Spacer(minLength: 0)
            // Everything else you can do with this copy, up by its name where it's easy to find.
            if holding != nil { moreMenu }
        }
    }

    private var moreMenu: some View {
        Menu {
            // Short titles with a small line under each (iOS sets the menu's width, so long titles
            // would wrap onto three lines).
            Button { editingDetails = true } label: {
                Label { Text("Edit details"); Text("Condition, grade or printing") } icon: { Image(systemName: "pencil") }
            }
            shelfMenu
            if !groups.portfolios.isEmpty { portfolioMenu }
            Button { selling = true } label: {
                Label { Text("Mark as sold"); Text("Record the price you sold it for") } icon: { Image(systemName: "tag") }
            }
            Button { removing = true } label: {
                Label { Text("Remove"); Text("Opened, lost or gave away") } icon: { Image(systemName: "minus.circle") }
            }
            Button(role: .destructive) { confirmDelete = true } label: {
                Label { Text("Delete"); Text("As if you never added it") } icon: { Image(systemName: "trash") }
            }
        } label: {
            Image(systemName: "ellipsis").font(.system(size: 17, weight: .semibold)).foregroundStyle(.white)
                .frame(width: 40, height: 40)
                .background(Circle().fill(Color.white.opacity(0.12)))
                .overlay(Circle().strokeBorder(Color.white.opacity(0.14)))
                .contentShape(Circle())
        }
        .menuStyle(.button)
        .buttonStyle(.plain)
        .accessibilityLabel("More actions")
    }

    /// Put the card on shelves or take it off (a check on each it's on).
    private var shelfMenu: some View {
        let productId = store.current(opened).productId
        let on = groups.shelves.filter { $0.product_ids.contains(productId) }.map(\.name)
        return Menu {
            ForEach(groups.shelves) { shelf in
                Button {
                    Task { await groupRun { try await groups.toggle(shelf.id, productId: productId) } }
                } label: {
                    if shelf.product_ids.contains(productId) { Label(shelf.name, systemImage: "checkmark") } else { Text(shelf.name) }
                }
            }
            Button { newShelf = ""; namingShelf = true } label: { Label("New list…", systemImage: "plus") }
        } label: {
            Label { Text("Lists"); Text(on.isEmpty ? "On no list" : on.joined(separator: ", ")) } icon: { Image(systemName: "square.stack") }
        }
    }

    /// Which portfolios this copy shows in: tap one to add it there or take it out (it always
    /// stays in at least one).
    private var portfolioMenu: some View {
        let key = store.current(opened).key
        let current = groups.portfoliosOf(key)
        return Menu {
            ForEach([GroupsStore.main] + groups.portfolios.map(\.id), id: \.self) { id in
                Button {
                    var next = current
                    if next.contains(id) { next.removeAll { $0 == id } } else { next.append(id) }
                    if next.isEmpty { return }
                    Task { await groupRun { try await groups.place(key, in: next, store: store) } }
                } label: {
                    if current.contains(id) { Label(groups.name(of: id), systemImage: "checkmark") } else { Text(groups.name(of: id)) }
                }
            }
        } label: {
            Label { Text("Portfolios"); Text(current.map { groups.name(of: $0) }.joined(separator: ", ")) } icon: { Image(systemName: "folder") }
        }
    }

    private func groupRun(_ work: () async throws -> Void) async {
        do { error = nil; try await work() } catch { self.error = error.localizedDescription }
    }

    /// Since you first bought it (cached in the store, so this is a lookup).
    private func worthPoints(_ h: HoldingView) -> [TimelinePoint] {
        let held = h.firstAcquired.map { Timeline.daysBetween($0, Format.day()) } ?? 90
        return store.series(h.identity, days: min(max(held, 7), 3650))
    }

    private func tiles(_ h: HoldingView) -> some View {
        // One copy: what you paid and what it's worth (quantity and average would repeat them).
        // Several: all four.
        LazyVGrid(columns: [GridItem(.flexible(), spacing: 8), GridItem(.flexible(), spacing: 8)], spacing: 8) {
            if h.quantity > 1 {
                SheetStat(label: "Quantity", value: "\(Int(h.quantity))")
                SheetStat(label: "You paid", value: Format.money(h.costBasis))
                SheetStat(label: "Average cost", value: Format.money(h.avgCost))
                SheetStat(label: "Each now", value: Format.money(h.price))
            } else {
                SheetStat(label: "You paid", value: Format.money(h.costBasis))
                SheetStat(label: "Worth now", value: Format.money(h.price))
            }
        }
    }

    /// A raw single: what it could be worth graded, and a way to send it in.
    private func ifGraded(_ identity: HoldingIdentity, _ h: HoldingView) -> some View {
        let nm = store.marketPrice(identity.productId, printing: identity.printing)?.market ?? h.price ?? 0
        func worth(_ grade: String) -> (Double, Bool) {
            // PriceCharting's 9 is for any company; scaled to PSA it's an estimate (≈).
            if let v = graded?.value(company: "PSA", grade: grade) { return grade == "10" ? (v, false) : (WorthCalc.companyAdjusted(v, company: "PSA"), true) }
            return ((nm * WorthCalc.multiple(productId: identity.productId, company: "PSA", grade: grade) * 100).rounded() / 100, true)
        }
        let ten = worth("10"), nine = worth("9")
        return VStack(alignment: .leading, spacing: 12) {
            MonoLabel(text: "If graded")
            HStack(spacing: 8) {
                SheetStat(label: "PSA 10", value: (ten.1 ? "≈ " : "") + Format.money(ten.0), tint: Theme.lime)
                SheetStat(label: "PSA 9", value: (nine.1 ? "≈ " : "") + Format.money(nine.0))
            }
            .redacted(reason: gradedReady ? [] : .placeholder)
            Text(!gradedReady ? "Looking up graded prices…" : ten.1 ? "Estimates from the usual grade curve. The card page has every grade." : "From PriceCharting (≈ adjusted for PSA). The card page has every grade.")
                .font(.geist(12)).foregroundStyle(Theme.subtle)
            Button { sending = true } label: { Label("Send for grading", systemImage: "paperplane") }
                .buttonStyle(GlassButton())
        }
    }

    /// A slab: its cert number and bumper (and Pristine, for a CGC 10), and your own value.
    private func slabRows(_ identity: HoldingIdentity) -> some View {
        let cert = grading.certs[identity.key]
        let bumper = Bumper.byId(grading.bumpers[identity.key])
        return VStack(spacing: 0) {
            row(icon: "number", title: "Cert number", value: cert ?? "Add") { certing = true }
            Rectangle().fill(Theme.border).frame(height: 1).padding(.leading, 44)
            row(icon: "square.dashed", title: "Bumper", value: bumper?.name ?? "Add") { bumpering = true }
            Rectangle().fill(Theme.border).frame(height: 1).padding(.leading, 44)
            if let company = identity.gradeCompany, let grade = identity.grade, Slab.isCGCTen(company: company, grade: grade) {
                // CGC's Pristine 10: the slab's label turns black and gold at once.
                HStack(spacing: 12) {
                    Image(systemName: "rosette").font(.system(size: 14, weight: .semibold)).foregroundStyle(Theme.lime).frame(width: 30)
                    Toggle("Pristine", isOn: Binding(
                        get: { grading.pristine.contains(identity.key) },
                        set: {
                            grading.setPristine(identity.key, $0)
                            // A Pristine 10 is priced apart from a Gem Mint 10: re-price the slabs.
                            Task { await store.loadSlabPrices() }
                        }
                    ))
                    .font(.geist(15))
                    .tint(Theme.lime)
                }
                .padding(.vertical, 6)
                Rectangle().fill(Theme.border).frame(height: 1).padding(.leading, 44)
            }
            row(icon: "pencil", title: "Your value", value: store.manualValue(identity).map { Format.money($0.value) } ?? "Set") { valuing = true }
            if let cert, let company = identity.gradeCompany, let url = URL(string: Grading.certLookupURL(company: company, cert: cert)) {
                Link(destination: url) { Label("Look up cert \(cert)", systemImage: "arrow.up.right.square") }
                    .font(.geist(14, .medium)).padding(.top, 12)
            }
        }
        .padding(14)
        .sheetPanel(radius: 16)
    }

    private func row(icon: String, title: String, value: String, action: @escaping () -> Void) -> some View {
        Button(action: action) {
            HStack(spacing: 12) {
                Image(systemName: icon).font(.system(size: 14, weight: .semibold)).foregroundStyle(Theme.lime).frame(width: 30)
                Text(title).font(.geist(15))
                Spacer()
                Text(value).font(.geist(14, .medium)).monospacedDigit().foregroundStyle(Theme.muted)
                Image(systemName: "chevron.right").font(.system(size: 11, weight: .semibold)).foregroundStyle(Theme.subtle)
            }
            .padding(.vertical, 10)
            .contentShape(Rectangle())
        }
        .buttonStyle(.plain)
    }

    private func actions(_ h: HoldingView) -> some View {
        HStack(spacing: 8) {
            Button { selling = true } label: { Label("Record sale", systemImage: "tag") }
                .buttonStyle(GlassButton())
            Button { whatIf = true } label: { Label("What if I sell?", systemImage: "plus.forwardslash.minus") }
                .buttonStyle(GlassButton())
        }
    }
}

/// What your copy is worth, its gain and its price line since you bought it. Its own view with
/// a plain value, so opening a child sheet or menu doesn't redraw the chart.
private struct HoldingWorth: View {
    var holding: HoldingView
    /// The price line since you first bought it, colored by whether you're up overall.
    var points: [TimelinePoint]

    var body: some View {
        let h = holding
        let points = Self.thin(self.points)
        VStack(alignment: .leading, spacing: 8) {
            HStack {
                MonoLabel(text: h.quantity > 1 ? "Your \(Int(h.quantity)) are worth" : "Yours is worth")
                Spacer()
                h.category.tag()
            }
            // Everything sits in place; only the figures count and the chart draws.
            CountingText(value: h.value ?? 0, format: { (h.isConditionEstimate ? "≈ " : "") + Format.money($0) }, duration: 0.9, delay: 0.15)
                .font(.display(44)).tracking(-1.8).monospacedDigit().displayTrim(44)
            HStack(spacing: 8) {
                DeltaPill(ratio: h.gainRatio, size: 13)
                CountingText(value: h.gain ?? 0, format: { Format.signedMoney($0) }, duration: 0.9, delay: 0.15)
                    .font(.geist(14, .semibold)).monospacedDigit().foregroundStyle(Theme.tone(h.gain))
                Text("on what you paid").font(.geist(13)).foregroundStyle(Theme.muted)
            }
            // How long you've had it, so the gain has context.
            if let held = HoldingWorth.heldFor(h.firstAcquired) {
                Text(held).font(.geist(13)).foregroundStyle(Theme.muted)
            }
            if points.count > 1 {
                let up = (h.gain ?? 0) >= 0
                // Draws in left to right, quickly, as the sheet arrives.
                Sparkline(points: points, color: up ? Theme.lime : Theme.planPink, delay: 0.15).frame(height: 56).padding(.top, 6)
                HStack {
                    MonoLabel(text: h.firstAcquired.flatMap { Format.isoDay.date(from: $0) }.map { "Since you bought it · \($0.formatted(.dateTime.month(.abbreviated).year()))" } ?? "Since you bought it")
                    Spacer()
                    Text(Format.signedMoney(h.gain)).font(.geist(12, .semibold)).monospacedDigit().foregroundStyle(Theme.tone(h.gain))
                }
            }
        }
        .tinted(h.category.color)
    }

    /// A copy held for years has a point for every day (up to 3,650), and Swift Charts lays out
    /// an area and a line mark for each as the sheet rises. A 56-point-high line can't show more
    /// than ~200, so keep that many evenly spaced (always the first and the last).
    private static func thin(_ points: [TimelinePoint], to limit: Int = 200) -> [TimelinePoint] {
        guard points.count > limit else { return points }
        let step = Double(points.count - 1) / Double(limit - 1)
        return (0..<limit).map { points[min(points.count - 1, Int((Double($0) * step).rounded()))] }
    }
}

/// The copy's entries, newest first, each with Edit and Delete. Its own view with plain values,
/// so it isn't rebuilt when a sheet flag flips.
private struct HoldingHistory: View {
    var entries: [Txn]
    @Binding var editing: Txn?
    @Binding var deleting: Txn?

    var body: some View {
        let lastId = entries.last?.id
        VStack(alignment: .leading, spacing: 8) {
            MonoLabel(text: "History")
            VStack(spacing: 0) {
                ForEach(entries, id: \.id) { t in
                    HStack {
                        EntryRow(entry: t)
                        Menu {
                            Button { editing = t } label: { Label("Edit", systemImage: "pencil") }
                            Button(role: .destructive) { deleting = t } label: { Label("Delete", systemImage: "trash") }
                        } label: {
                            Image(systemName: "ellipsis").font(.system(size: 13)).foregroundStyle(Theme.muted).frame(width: 44, height: 44).contentShape(Rectangle())
                        }
                    }
                    .padding(.vertical, 10)
                    if t.id != lastId { Rectangle().fill(Theme.border).frame(height: 1) }
                }
                if entries.isEmpty { Text("No entries.").font(.geist(14)).foregroundStyle(Theme.muted).padding(.vertical, 10) }
            }
            .padding(14)
            .sheetPanel(radius: 16)
        }
    }
}

/// "View card details →": the icon after the title.
private struct TrailingIconLabel: LabelStyle {
    func makeBody(configuration: Configuration) -> some View {
        HStack(spacing: 8) { configuration.title; configuration.icon }
    }
}

extension Txn: Identifiable {}

private struct EntryRow: View {
    var entry: Txn

    var body: some View {
        HStack {
            VStack(alignment: .leading, spacing: 2) {
                Text(title).font(.subheadline.weight(.medium))
                Text(subtitle).font(.caption).foregroundStyle(Theme.muted)
            }
            Spacer()
            Text(amount).font(.subheadline.weight(.semibold)).monospacedDigit()
        }
    }

    private var title: String {
        let q = abs(entry.quantity).formatted()
        switch entry.kind {
        case .purchase: return "Bought \(q)"
        case .sale: return "Sold \(q)"
        case .adjustment: return entry.quantity > 0 ? "Added \(q)" : "Removed \(q)"
        case .correction: return "Correction"
        }
    }

    private var subtitle: String {
        let date = Format.isoDay.date(from: entry.date).map { $0.formatted(date: .abbreviated, time: .omitted) } ?? entry.date
        return [date, entry.unitPrice > 0 ? "\(Format.money(entry.unitPrice)) each" : nil, entry.source].compactMap { $0 }.joined(separator: " · ")
    }

    private var amount: String {
        entry.kind == .sale ? Format.money(entry.saleProceeds) : Format.money(entry.acquisitionCost)
    }
}

/// Record a sale, with what you'll actually make after fees and shipping.
struct SellSheet: View {
    var holding: HoldingView
    @Environment(\.dismiss) private var dismiss
    @Environment(CollectionStore.self) private var store
    @State private var quantity = 1
    @State private var price = ""
    @State private var feePercent = ""
    @State private var shipping = ""
    @State private var date = Date()
    @State private var saving = false
    @State private var error: String?

    private var unit: Double { MoneyField.value(price) ?? holding.price ?? 0 }
    private var gross: Double { unit * Double(quantity) }
    private var fees: Double { ((MoneyField.value(feePercent) ?? 0) / 100 * gross * 100).rounded() / 100 }
    private var ship: Double { MoneyField.value(shipping) ?? 0 }
    private var net: Double { gross - fees - ship }
    private var cost: Double { holding.fifoCost(Double(quantity)) }

    var body: some View { sheetBody.presentationDetents([.fraction(0.93)]).glassSheet() }

    @ViewBuilder private var sheetBody: some View {
        NavigationStack {
            GlassForm {
                Section {
                    Stepper("Quantity: \(quantity) of \(Int(holding.quantity))", value: $quantity, in: 1...max(1, Int(holding.quantity)))
                    MoneyField(title: "Price each", text: $price, hint: Format.money(holding.price ?? 0))
                    HStack {
                        Text("Selling fees")
                        Spacer()
                        TextField("0", text: $feePercent).keyboardType(.decimalPad).multilineTextAlignment(.trailing).frame(maxWidth: 70)
                        Text("%").foregroundStyle(Theme.muted)
                    }
                    MoneyField(title: "Shipping you pay", text: $shipping)
                    DatePicker("Date", selection: $date, in: ...Date(), displayedComponents: .date)
                }
                Section {
                    LabeledContent("You receive") { Text(Format.money(net)).monospacedDigit().bold() }
                    LabeledContent("Cost of these") { Text(Format.money(cost)).monospacedDigit() }
                    LabeledContent("Profit") { Text(Format.signedMoney(net - cost)).monospacedDigit().foregroundStyle(Theme.tone(net - cost)) }
                } footer: {
                    Text("Cost comes from your oldest copies first.")
                }
                if let error { Section { Text(error).foregroundStyle(Theme.down) } }
            }
            .scrollContentBackground(.hidden)
            .navigationTitle("Sell")
            .navigationBarTitleDisplayMode(.inline)
            .toolbar {
                ToolbarItem(placement: .cancellationAction) { Button("Cancel") { dismiss() } }
                ToolbarItem(placement: .confirmationAction) {
                    Button(saving ? "Saving…" : "Record sale") { Task { await save() } }.disabled(saving || unit <= 0)
                }
            }
        }
    }

    private func save() async {
        saving = true
        error = nil
        defer { saving = false }
        do {
            try await store.sell(holding.identity, quantity: Double(quantity), unitPrice: unit, fees: fees, shipping: ship, date: Format.day(date))
            UINotificationFeedbackGenerator().notificationOccurred(.success)
            dismiss()
        } catch {
            self.error = error.localizedDescription
        }
    }
}

/// Fix a past purchase or sale.
struct EntryEditSheet: View {
    var entry: Txn
    @Environment(\.dismiss) private var dismiss
    @Environment(CollectionStore.self) private var store
    @State private var quantity: Int
    @State private var price: String
    @State private var fees: String
    @State private var shipping: String
    @State private var date: Date
    @State private var saving = false
    @State private var error: String?

    init(entry: Txn) {
        self.entry = entry
        _quantity = State(initialValue: max(1, Int(abs(entry.quantity))))
        _price = State(initialValue: String(format: "%.2f", entry.unitPrice))
        _fees = State(initialValue: entry.fees > 0 ? String(format: "%.2f", entry.fees) : "")
        _shipping = State(initialValue: entry.shipping > 0 ? String(format: "%.2f", entry.shipping) : "")
        _date = State(initialValue: Format.isoDay.date(from: entry.date) ?? Date())
    }

    var body: some View { sheetBody.presentationDetents([.fraction(0.93)]).glassSheet() }

    @ViewBuilder private var sheetBody: some View {
        NavigationStack {
            GlassForm {
                Section {
                    Stepper("Quantity: \(quantity)", value: $quantity, in: 1...9999)
                    MoneyField(title: "Price each", text: $price)
                    MoneyField(title: "Fees", text: $fees)
                    MoneyField(title: "Shipping", text: $shipping)
                    DatePicker("Date", selection: $date, in: ...Date(), displayedComponents: .date)
                } footer: {
                    Text("Saved as a correction, so the original stays in the record.")
                }
                if let error { Section { Text(error).foregroundStyle(Theme.down) } }
            }
            .scrollContentBackground(.hidden)
            .navigationTitle(entry.kind == .sale ? "Edit sale" : "Edit purchase")
            .navigationBarTitleDisplayMode(.inline)
            .toolbar {
                ToolbarItem(placement: .cancellationAction) { Button("Cancel") { dismiss() } }
                ToolbarItem(placement: .confirmationAction) { Button(saving ? "Saving…" : "Save") { Task { await save() } }.disabled(saving) }
            }
        }
    }

    private func save() async {
        saving = true
        error = nil
        defer { saving = false }
        do {
            try await store.correct(
                entry, date: Format.day(date), quantity: Double(quantity), unitPrice: MoneyField.value(price) ?? 0,
                fees: MoneyField.value(fees) ?? 0, shipping: MoneyField.value(shipping) ?? 0
            )
            dismiss()
        } catch {
            self.error = error.localizedDescription
        }
    }
}

/// What a graded slab is worth to you.
struct ManualValueSheet: View {
    var identity: HoldingIdentity
    var current: Double?
    @Environment(\.dismiss) private var dismiss
    @Environment(CollectionStore.self) private var store
    @State private var value = ""
    @State private var saving = false
    @State private var error: String?

    var body: some View { sheetBody.glassSheet() }

    @ViewBuilder private var sheetBody: some View {
        NavigationStack {
            GlassForm {
                Section {
                    MoneyField(title: identity.gradeLabel ?? "Value", text: $value, hint: current.map { Format.money($0) } ?? "$0.00")
                } footer: {
                    Text("Used for this slab's value from today on.")
                }
                if current != nil {
                    Section { Button("Clear value", role: .destructive) { Task { await save(nil) } } }
                }
                if let error { Section { Text(error).foregroundStyle(Theme.down) } }
            }
            .scrollContentBackground(.hidden)
            .navigationTitle("Slab value")
            .navigationBarTitleDisplayMode(.inline)
            .toolbar {
                ToolbarItem(placement: .cancellationAction) { Button("Cancel") { dismiss() } }
                ToolbarItem(placement: .confirmationAction) {
                    Button("Save") { Task { await save(MoneyField.value(value)) } }.disabled(saving || MoneyField.value(value) == nil)
                }
            }
        }
        .presentationDetents([.medium])
    }

    private func save(_ v: Double?) async {
        saving = true
        defer { saving = false }
        do {
            try await store.setManualValue(identity, v)
            dismiss()
        } catch {
            self.error = error.localizedDescription
        }
    }
}

/// A figure tile for a glass sheet: a faint white fill and hairline edge, which reads cleanly on
/// glass (glass on glass turns blotchy).
struct SheetStat: View {
    var label: String
    var value: String
    var tint: Color = .white

    var body: some View {
        VStack(alignment: .leading, spacing: 4) {
            MonoLabel(text: label).lineLimit(1).minimumScaleFactor(0.6)
            Text(value).font(.geist(15, .semibold)).monospacedDigit().foregroundStyle(tint).lineLimit(1).minimumScaleFactor(0.7)
        }
        .padding(.horizontal, 12)
        .padding(.vertical, 10)
        .frame(maxWidth: .infinity, minHeight: 58, maxHeight: 58, alignment: .leading)
        .sheetPanel(radius: 14)
    }
}



/// Take copies out of your collection without a sale: opened, lost, gave away or damaged. Their
/// cost is written off (counts as a loss), like the website's Remove.
struct RemoveSheet: View {
    var holding: HoldingView
    @Environment(CollectionStore.self) private var store
    @Environment(\.dismiss) private var dismiss
    @State private var quantity = 1
    @State private var reason = "Opened"
    @State private var date = Date()
    @State private var saving = false
    @State private var error: String?

    private static let reasons = ["Opened", "Lost", "Gave away", "Damaged", "Traded away"]

    var body: some View { sheetBody.glassSheet() }

    @ViewBuilder private var sheetBody: some View {
        NavigationStack {
            GlassForm {
                Section {
                    Text(holding.product?.name ?? "This copy").font(.geist(15, .semibold))
                }
                Section {
                    Picker("Why", selection: $reason) {
                        ForEach(Self.reasons, id: \.self) { Text($0) }
                    }
                    if holding.quantity > 1 {
                        Stepper("Quantity: \(quantity)", value: $quantity, in: 1...max(1, Int(holding.quantity)))
                    }
                    DatePicker("Date", selection: $date, in: ...Date(), displayedComponents: .date)
                } footer: {
                    Text("What you paid for \(quantity == 1 ? "it" : "them") is written off, so it shows as a loss in your gains. To erase it as if you never had it, use Delete from collection instead.")
                }
                if let error { Section { Text(error).foregroundStyle(Theme.down) } }
            }
            .navigationTitle("Remove")
            .navigationBarTitleDisplayMode(.inline)
            .toolbar {
                ToolbarItem(placement: .cancellationAction) { Button("Cancel") { dismiss() } }
                ToolbarItem(placement: .confirmationAction) {
                    Button(saving ? "Removing…" : "Remove") {
                        Task {
                            saving = true
                            defer { saving = false }
                            do {
                                try await store.remove(holding.identity, quantity: Double(quantity), reason: reason, date: Format.day(date))
                                dismiss()
                            } catch { self.error = error.localizedDescription }
                        }
                    }
                    .disabled(saving)
                }
            }
        }
        .presentationDetents([.medium, .fraction(0.93)])
    }
}


/// Fix a copy's details: its condition (or grade, for a slab) and printing. Its purchases,
/// sales and edits all stay; only what it is changes.
struct EditDetailsSheet: View {
    var holding: HoldingView
    @Environment(GradingStore.self) private var grading
    @Environment(CollectionStore.self) private var store
    @Environment(GroupsStore.self) private var groups
    @Environment(\.dismiss) private var dismiss
    @State private var printing: String?
    /// The shelves and portfolios it's in, saved with the rest.
    @State private var shelfIds: Set<String> = []
    @State private var portfolioIds: Set<String> = []
    @State private var startShelves: Set<String> = []
    @State private var startPortfolios: Set<String> = []
    @State private var namingShelf = false
    @State private var newShelf = ""
    @State private var condition = CardCondition.nearMint.rawValue
    @State private var graded = false
    @State private var company = "PSA"
    @State private var grade = "10"
    @State private var saving = false
    @State private var error: String?

    private var product: Product? { holding.product }
    private var grades: [String] {
        let whole = (1...10).map(String.init)
        let all = company == "BGS" || company == "CGC" ? whole + ["9.5", "8.5", "7.5"] : whole
        return all.sorted { (Double($0) ?? 0) > (Double($1) ?? 0) }
    }

    private var edited: HoldingIdentity {
        var i = holding.identity
        i.printing = printing
        if product?.isSealed == true {
            i.condition = "Sealed"
        } else if graded {
            i.condition = CardCondition.nearMint.rawValue
            i.gradeCompany = company
            i.grade = grade
        } else {
            i.condition = condition
            i.gradeCompany = nil
            i.grade = nil
        }
        return i
    }

    var body: some View { sheetBody.glassSheet() }

    @ViewBuilder private var sheetBody: some View {
        NavigationStack {
            GlassForm {
                Section {
                    Text(product?.name ?? "This copy").font(.geist(15, .semibold))
                }
                if let printings = product?.printings, printings.count > 1 {
                    Picker("Printing", selection: $printing) {
                        ForEach(printings, id: \.self) { Text($0).tag(Optional($0)) }
                    }
                }
                if product?.isSealed == false {
                    Section {
                        Toggle("Graded", isOn: $graded)
                        if graded {
                            Picker("Company", selection: $company) {
                                ForEach(gradingCompanies, id: \.self) { Text($0) }
                            }
                            Picker("Grade", selection: $grade) {
                                ForEach(grades, id: \.self) { Text($0) }
                            }
                        } else {
                            Picker("Condition", selection: $condition) {
                                ForEach(CardCondition.allCases) { Text($0.rawValue).tag($0.rawValue) }
                            }
                        }
                    } header: {
                        SectionTitle("Condition")
                    } footer: {
                        SectionNote("Your purchases, sales and edits stay as they are; only what this copy is changes. If you already have a copy with these details, the two become one.")
                    }
                }
                Section {
                    ForEach(groups.shelves) { shelf in
                        checkRow(shelf.name, on: shelfIds.contains(shelf.id)) {
                            if shelfIds.contains(shelf.id) { shelfIds.remove(shelf.id) } else { shelfIds.insert(shelf.id) }
                        }
                    }
                    Button { newShelf = ""; namingShelf = true } label: { Label("New list", systemImage: "plus") }
                        .foregroundStyle(Theme.lime)
                } header: {
                    SectionTitle("Lists")
                } footer: {
                    SectionNote("Lists hold the card, whatever copy it is.")
                }
                if !groups.portfolios.isEmpty {
                    Section {
                        ForEach([GroupsStore.main] + groups.portfolios.map(\.id), id: \.self) { id in
                            checkRow(groups.name(of: id), on: portfolioIds.contains(id)) {
                                if portfolioIds.contains(id) {
                                    if portfolioIds.count > 1 { portfolioIds.remove(id) }
                                } else { portfolioIds.insert(id) }
                            }
                        }
                    } header: {
                        SectionTitle("Portfolios")
                    } footer: {
                        SectionNote("It can be in several; it always stays in at least one.")
                    }
                }
                if let error { Section { Text(error).foregroundStyle(Theme.down) } }
            }
            .navigationTitle("Edit details")
            .navigationBarTitleDisplayMode(.inline)
            .toolbar {
                ToolbarItem(placement: .cancellationAction) { Button("Cancel") { dismiss() } }
                ToolbarItem(placement: .confirmationAction) {
                    Button(saving ? "Saving…" : "Save") {
                        Task {
                            saving = true
                            defer { saving = false }
                            do {
                                let target = edited
                                if target.key != holding.identity.key {
                                    try await store.changeDetails(holding.identity, to: target)
                                    grading.moveSlab(from: holding.identity, to: target)
                                }
                                let productId = holding.identity.productId
                                for id in shelfIds.symmetricDifference(startShelves) {
                                    try await groups.toggle(id, productId: productId)
                                }
                                if portfolioIds != startPortfolios || target.key != holding.identity.key {
                                    try await groups.place(target.key, in: Array(portfolioIds), store: store)
                                }
                                dismiss()
                            } catch { self.error = error.localizedDescription }
                        }
                    }
                    .disabled(saving || (edited.key == holding.identity.key && shelfIds == startShelves && portfolioIds == startPortfolios))
                }
            }
            .onAppear {
                let i = holding.identity
                printing = i.printing ?? product?.printings?.first
                graded = i.isGraded
                if let c = i.gradeCompany { company = c }
                if let g = i.grade { grade = g }
                if CardCondition(rawValue: i.condition) != nil { condition = i.condition }
                startShelves = Set(groups.shelves.filter { $0.product_ids.contains(i.productId) }.map(\.id))
                shelfIds = startShelves
                startPortfolios = Set(groups.portfoliosOf(i.key))
                if startPortfolios.isEmpty { startPortfolios = [GroupsStore.main] }
                portfolioIds = startPortfolios
            }
            .alert("New list", isPresented: $namingShelf) {
                TextField("Grails, For sale at the show…", text: $newShelf)
                Button("Cancel", role: .cancel) { newShelf = "" }
                Button("Create") {
                    let value = String(newShelf.trimmingCharacters(in: .whitespaces).prefix(40))
                    newShelf = ""
                    guard !value.isEmpty else { return }
                    Task {
                        do {
                            // Created now (empty) and ticked; the card goes on it when you save.
                            let shelf = try await groups.createShelf(value)
                            shelfIds.insert(shelf.id)
                        } catch { self.error = error.localizedDescription }
                    }
                }
            }
        }
        .presentationDetents([.medium, .fraction(0.93)])
    }

    /// A row with a lime check when it's on; tap to switch.
    private func checkRow(_ title: String, on: Bool, toggle: @escaping () -> Void) -> some View {
        Button(action: toggle) {
            HStack {
                Text(title).foregroundStyle(.white)
                Spacer()
                if on { Image(systemName: "checkmark").font(.system(size: 15, weight: .semibold)).foregroundStyle(Theme.lime) }
            }
            .contentShape(Rectangle())
        }
        .buttonStyle(.plain)
        .accessibilityAddTraits(on ? .isSelected : [])
    }
}

private extension HoldingWorth {
    /// "Held 7 months", "Held 2 years 3 months", "Held 12 days" from the first purchase date.
    static func heldFor(_ firstAcquired: String?) -> String? {
        guard let first = firstAcquired.flatMap({ Format.isoDay.date(from: $0) }) else { return nil }
        let parts = Calendar.current.dateComponents([.year, .month, .day], from: first, to: Date())
        let y = parts.year ?? 0, m = parts.month ?? 0, d = parts.day ?? 0
        func plural(_ n: Int, _ word: String) -> String { "\(n) \(word)\(n == 1 ? "" : "s")" }
        if y > 0 { return "Held " + plural(y, "year") + (m > 0 ? " " + plural(m, "month") : "") }
        if m > 0 { return "Held " + plural(m, "month") }
        return d < 1 ? "Added today" : "Held " + plural(d, "day")
    }
}
