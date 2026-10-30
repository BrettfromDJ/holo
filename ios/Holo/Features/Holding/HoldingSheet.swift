import SwiftUI

/// One position you hold: sell some, set a slab's value, and fix or delete past entries.
struct HoldingSheet: View {
    var identity: HoldingIdentity
    @Environment(\.dismiss) private var dismiss
    @Environment(CollectionStore.self) private var store
    @State private var selling = false
    @State private var valuing = false
    @State private var editing: Txn?
    @State private var deleting: Txn?
    @State private var error: String?

    private var holding: HoldingView? { store.holding(identity) }
    private var product: Product? { store.products[identity.productId] }
    private var entries: [Txn] { store.entries(for: identity) }

    var body: some View {
        NavigationStack {
            List {
                Section {
                    HStack(spacing: 12) {
                        ProductImage(product: product, cornerRadius: 5).frame(width: 48, height: 66)
                        VStack(alignment: .leading, spacing: 3) {
                            Text(product?.name ?? "Unknown").font(.headline)
                            Text(holding?.label ?? (product?.isSealed == true ? "Sealed" : "Near Mint")).font(.subheadline).foregroundStyle(Theme.muted)
                        }
                    }
                    if let h = holding {
                        LabeledContent("Quantity", value: "\(h.quantity.formatted())")
                        LabeledContent("Cost") { Text(Format.money(h.costBasis)).monospacedDigit() }
                        LabeledContent("Value") { Text((h.isConditionEstimate ? "≈ " : "") + Format.money(h.value)).monospacedDigit() }
                        LabeledContent("Gain") { Text(Format.signedMoney(h.gain)).monospacedDigit().foregroundStyle(Theme.tone(h.gain)) }
                    } else {
                        Text("You don't hold any of these right now.").foregroundStyle(Theme.muted)
                    }
                }

                Section {
                    if holding != nil {
                        Button { selling = true } label: { Label("Sell", systemImage: "dollarsign.circle") }
                    }
                    if identity.isGraded {
                        Button { valuing = true } label: {
                            Label(store.manualValue(identity) == nil ? "Set its value" : "Change its value", systemImage: "pencil")
                        }
                    }
                } footer: {
                    if identity.isGraded {
                        Text("Graded slabs are valued at the price you set.")
                    }
                }

                Section("History") {
                    ForEach(entries, id: \.id) { t in
                        EntryRow(entry: t)
                            .swipeActions {
                                Button("Delete", role: .destructive) { deleting = t }
                                Button("Edit") { editing = t }.tint(Theme.surface3)
                            }
                            .contextMenu {
                                Button { editing = t } label: { Label("Edit", systemImage: "pencil") }
                                Button(role: .destructive) { deleting = t } label: { Label("Delete", systemImage: "trash") }
                            }
                    }
                    if entries.isEmpty { Text("No entries.").foregroundStyle(Theme.muted) }
                }

                if let error {
                    Section { Text(error).foregroundStyle(Theme.down) }
                }
            }
            .scrollContentBackground(.hidden)
            .background(Theme.background)
            .navigationTitle("Your copy")
            .navigationBarTitleDisplayMode(.inline)
            .toolbar { ToolbarItem(placement: .confirmationAction) { Button("Done") { dismiss() } } }
            .sheet(isPresented: $selling) { if let h = holding { SellSheet(holding: h) } }
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
        }
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

    var body: some View {
        NavigationStack {
            Form {
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
            .background(Theme.background)
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

    var body: some View {
        NavigationStack {
            Form {
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
            .background(Theme.background)
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

    var body: some View {
        NavigationStack {
            Form {
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
            .background(Theme.background)
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
