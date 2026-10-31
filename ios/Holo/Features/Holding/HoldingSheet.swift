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

    /// The copy now: follows a demo card that switched to its real catalog card while open.
    private var identity: HoldingIdentity { store.current(opened) }
    @Environment(\.dismiss) private var dismiss
    @Environment(CollectionStore.self) private var store
    @Environment(GradingStore.self) private var grading
    @State private var selling = false
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

    private var holding: HoldingView? { store.holding(identity) }
    private var product: Product? { store.products[identity.productId] }
    private var entries: [Txn] { store.entries(for: identity) }

    var body: some View { sheetBody.glassSheet() }

    @ViewBuilder private var sheetBody: some View {
        ScrollView {
            VStack(alignment: .leading, spacing: 20) {
                // Title and Done sit in the content (no navigation bar), so nothing above the
                // content changes size while the sheet comes up and nothing shifts.
                titleRow
                header
                if let h = holding {
                    value(h)
                    tiles(h)
                    if identity.isGraded { slabRows } else if product?.isSealed == false { ifGraded(h) }
                    actions(h)
                } else {
                    Text("You don't hold any of these right now.").font(.geist(14)).foregroundStyle(Theme.muted)
                }
                history
                if let error { Text(error).font(.geist(13)).foregroundStyle(Theme.down) }
            }
            .frame(maxWidth: .infinity, alignment: .leading)
            .padding(.horizontal, 20)
            .padding(.top, 18)
            .padding(.bottom, onOpenCard == nil ? 24 : 96)
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
        .sheet(isPresented: $whatIf) { if let h = holding { SellCalculatorSheet(holding: h) } }
        .sheet(isPresented: $sending) { if let h = holding { SendSheet(holding: h) } }
        .sheet(isPresented: $certing) { if let h = holding { CertSheet(holding: h) } }
        .sheet(isPresented: $bumpering) { if let h = holding { BumperSheet(holding: h) } }
        .sheet(isPresented: $valuing) { ManualValueSheet(identity: identity, current: store.manualValue(identity)?.value) }
        .sheet(item: $editing) { t in EntryEditSheet(entry: t) }
        .confirmationDialog("Delete this entry?", isPresented: Binding(get: { deleting != nil }, set: { if !$0 { deleting = nil } }), titleVisibility: .visible) {
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
            Text("Your copy").font(.geist(17, .semibold))
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

    private var header: some View {
        HStack(spacing: 14) {
            HoldingArt(product: product, identity: identity, cornerRadius: 6, caption: false).frame(width: 62, height: 86)
            VStack(alignment: .leading, spacing: 5) {
                Text(product?.name ?? "Unknown").font(.geist(17, .semibold)).lineLimit(2)
                HStack(spacing: 6) {
                    Tag(text: holding?.label ?? (product?.isSealed == true ? "Sealed" : identity.condition), tint: identity.isGraded ? Theme.lime : .white)
                    if let set = product?.setName { Text(set).font(.geist(12)).foregroundStyle(Theme.muted).lineLimit(1) }
                }
            }
        }
    }

    private func value(_ h: HoldingView) -> some View {
        // Since you first bought it, colored by whether you're up overall.
        let held = h.firstAcquired.map { Timeline.daysBetween($0, Format.day()) } ?? 90
        let points = store.series(identity, days: min(max(held, 7), 3650))
        return VStack(alignment: .leading, spacing: 8) {
            MonoLabel(text: h.quantity > 1 ? "Your \(Int(h.quantity)) are worth" : "Yours is worth")
            // Everything sits in place; only the figures count and the chart draws.
            CountingText(value: h.value ?? 0, format: { (h.isConditionEstimate ? "≈ " : "") + Format.money($0) }, duration: 0.9, delay: 0.15)
                .font(.display(44)).monospacedDigit().displayTrim(44)
            HStack(spacing: 8) {
                DeltaPill(ratio: h.gainRatio, size: 13)
                CountingText(value: h.gain ?? 0, format: { Format.signedMoney($0) }, duration: 0.9, delay: 0.15)
                    .font(.geist(14, .semibold)).monospacedDigit().foregroundStyle(Theme.tone(h.gain))
                Text("on what you paid").font(.geist(13)).foregroundStyle(Theme.muted)
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
    }

    private func tiles(_ h: HoldingView) -> some View {
        LazyVGrid(columns: [GridItem(.flexible(), spacing: 8), GridItem(.flexible(), spacing: 8)], spacing: 8) {
            SheetStat(label: "Quantity", value: "\(Int(h.quantity))")
            SheetStat(label: "You paid", value: Format.money(h.costBasis))
            SheetStat(label: "Average cost", value: Format.money(h.avgCost))
            SheetStat(label: "Each now", value: Format.money(h.price))
        }
    }

    /// A raw single: what it could be worth graded, and a way to send it in.
    private func ifGraded(_ h: HoldingView) -> some View {
        let nm = store.marketPrice(identity.productId, printing: identity.printing)?.market ?? h.price ?? 0
        func worth(_ grade: String) -> (Double, Bool) {
            if let v = graded?.value(company: "PSA", grade: grade) { return (v, false) }
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
            Text(!gradedReady ? "Looking up graded prices…" : ten.1 ? "Estimates from the usual grade curve. The card page has every grade." : "From PriceCharting. The card page has every grade.")
                .font(.geist(12)).foregroundStyle(Theme.subtle)
            Button { sending = true } label: { Label("Send for grading", systemImage: "paperplane") }
                .buttonStyle(GlassButton())
        }
    }

    /// A slab: its cert number and bumper, and your own value.
    private var slabRows: some View {
        let cert = grading.certs[identity.key]
        let bumper = Bumper.byId(grading.bumpers[identity.key])
        return VStack(spacing: 0) {
            row(icon: "number", title: "Cert number", value: cert ?? "Add") { certing = true }
            Rectangle().fill(Theme.border).frame(height: 1).padding(.leading, 44)
            row(icon: "square.dashed", title: "Bumper", value: bumper?.name ?? "Add") { bumpering = true }
            Rectangle().fill(Theme.border).frame(height: 1).padding(.leading, 44)
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
            Button { selling = true } label: { Label("Sell", systemImage: "tag") }
                .buttonStyle(GlassButton())
            Button { whatIf = true } label: { Label("What if I sell?", systemImage: "plus.forwardslash.minus") }
                .buttonStyle(GlassButton())
        }
    }

    private var history: some View {
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
                            Image(systemName: "ellipsis").font(.system(size: 13)).foregroundStyle(Theme.muted).frame(width: 28, height: 28)
                        }
                    }
                    .padding(.vertical, 10)
                    if t.id != entries.last?.id { Rectangle().fill(Theme.border).frame(height: 1) }
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

    var body: some View { sheetBody.glassSheet() }

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

    var body: some View { sheetBody.glassSheet() }

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

