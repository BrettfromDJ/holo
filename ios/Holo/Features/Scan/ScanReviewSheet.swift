import SwiftUI

/// After scanning: a checklist of what was scanned, what each is worth and what you paid. Tap a
/// row to open it close up (condition, printing, price, the right card, remove); swipe to
/// remove; then add them all.
struct ScanReviewSheet: View {
    @Bindable var model: ScanModel
    var focus: UUID?
    var onAdded: () -> Void
    @Environment(\.dismiss) private var dismiss
    @Environment(CollectionStore.self) private var store
    @Environment(GroupsStore.self) private var groups
    @State private var pulled = false
    /// The details for the whole batch: portfolio, date, where, and shipping, tax and fees.
    @State private var details = ScanBatchDetails()
    @State private var editingDetails = false
    @State private var saving = false
    @State private var error: String?
    /// The scan open close up.
    @State private var editing: EditingScan?

    var body: some View { sheetBody.presentationDetents([.fraction(0.93)]).glassSheet() }

    @ViewBuilder private var sheetBody: some View {
        ScrollViewReader { proxy in
            GlassList {
                // The heading sits in the content (no navigation bar on a display sheet):
                // how many were scanned and what they're worth, and a glass pill back to the camera.
                Section {
                    HStack(alignment: .firstTextBaseline, spacing: 12) {
                        VStack(alignment: .leading, spacing: 2) {
                            Text("\(model.entries.count) scanned").font(.display(26)).tracking(-0.7).foregroundStyle(.white)
                            Text("\(model.picks.count) matched · \(Format.money(model.total))").font(.geist(13)).foregroundStyle(.white).monospacedDigit()
                        }
                        Spacer()
                        Button { dismiss() } label: {
                            HStack(spacing: 7) {
                                Image(systemName: "camera.fill").font(.system(size: 14, weight: .semibold))
                                Text("Camera").font(.geist(14, .semibold))
                            }
                            .foregroundStyle(.white)
                            .padding(.horizontal, 14).frame(height: 38)
                            .contentShape(Capsule())
                        }
                        .buttonStyle(.plain)
                        .background { Color.clear.liquidGlass(in: Capsule()).allowsHitTesting(false) }
                        .accessibilityLabel("Back to camera")
                    }
                    .listRowBackground(Color.clear)
                    .listRowInsets(EdgeInsets(top: 6, leading: 20, bottom: 4, trailing: 20))
                    .listRowSeparator(.hidden)
                }
                ForEach(model.entries) { entry in
                    // Rows are compared by value: a change to one scan redraws that row alone.
                    ReviewRow(entry: entry, owned: owned(entry))
                        .equatable()
                        .contentShape(Rectangle())
                        .onTapGesture {
                            if entry.state == .failed { model.retry(entry.id) }
                            if let p = entry.picked { store.setOpenPrinting(entry.printing ?? p.printing, for: p.product.id) }
                            editing = EditingScan(id: entry.id)
                        }
                        .id(entry.id)
                        .listRowBackground(Color.white.opacity(0.07))
                        // Swipe: pink with a trash icon, like a deal card's.
                        .swipeActions {
                            Button(role: .destructive) { withAnimation(.snappy) { model.remove(entry.id) } } label: {
                                Label("Remove", systemImage: "trash.fill")
                            }
                            .tint(Theme.planPink)
                        }
                }
                if let error {
                    Text(error).foregroundStyle(Theme.down)
                }
            }
            .scrollContentBackground(.hidden)
            .onAppear { if let focus { proxy.scrollTo(focus, anchor: .center) } }
        }
        .safeAreaInset(edge: .bottom) {
            if model.onPick == nil {
                footer
            } else {
                Button("Done") { dismiss() }.buttonStyle(LimeButtonStyle()).padding(16)
            }
        }
        .sheet(isPresented: $editingDetails) { ScanBatchDetailsSheet(details: $details, pulled: pulled) }
        .sheet(item: $editing) { e in
            ScanCardSheet(model: model, id: e.id, onRemove: { withAnimation(.snappy) { model.remove(e.id) } })
        }
    }

    /// How many of this card you already have.
    private func owned(_ e: ScanModel.Entry) -> Int {
        guard let id = e.picked?.product.id else { return 0 }
        return Int(store.allHoldings.filter { $0.identity.productId == id }.reduce(0) { $0 + $1.quantity })
    }

    /// What a blank price means (bought at market, or pulled for $0) as a chip pair in the
    /// app's own style, then the Add button. Sits on the sheet's glass under a hairline.
    private var footer: some View {
        VStack(spacing: 12) {
            HStack(spacing: 12) {
                Text("Blank price means").font(.geist(13, .medium)).foregroundStyle(.white)
                Spacer()
                ChipPicker(options: [(false, "Paid market"), (true, "Pulled, $0")], selection: $pulled)
            }
            // Portfolio, date, where, shipping, tax and fees for all of them at once (a card's
            // own details, graded and the rest, are on its page: tap it, then Add with all details).
            Button { editingDetails = true } label: {
                HStack(spacing: 8) {
                    Image(systemName: "slider.horizontal.3").font(.system(size: 13, weight: .semibold)).foregroundStyle(Theme.lime)
                    Text(details.summary(groups: groups, pulled: pulled)).font(.geist(13, .medium)).foregroundStyle(.white).lineLimit(1)
                    Spacer(minLength: 6)
                    Text("Edit").font(.geist(13, .semibold)).foregroundStyle(Theme.lime)
                }
                .padding(.horizontal, 14).frame(height: 40)
                .background(Color.white.opacity(0.07), in: Capsule())
                .contentShape(Capsule())
            }
            .buttonStyle(.plain)
            Button {
                Task { await add() }
            } label: {
                Text(saving ? "Adding…" : "Add \(model.picks.count) to collection · \(Format.money(model.total))")
            }
            .buttonStyle(LimeButtonStyle())
            .disabled(saving || model.picks.isEmpty)
        }
        .padding(.horizontal, 16).padding(.top, 12).padding(.bottom, 8)
        .background(alignment: .top) { Rectangle().fill(Color.white.opacity(0.08)).frame(height: 1) }
        .background(Color.black.opacity(0.18))
    }

    private func add() async {
        saving = true
        error = nil
        defer { saving = false }
        do {
            let before = store.allHoldings.reduce(0) { $0 + ($1.value ?? 0) }
            let purchases = details.apply(to: model.purchases(pulled: pulled, date: Format.day(details.date)), pulled: pulled)
            let ownedBefore = Set(store.allHoldings.map(\.identity.key))
            try await store.add(purchases)
            // Into the picked portfolio: more of a copy you own is also shown there (a Copy); a new one goes only there.
            if !groups.portfolios.isEmpty, let target = details.portfolio {
                for p in purchases {
                    let key = HoldingIdentity(productId: p.product.id, printing: p.printing, condition: p.condition, gradeCompany: p.gradeCompany, grade: p.grade).key
                    if ownedBefore.contains(key) {
                        try? await groups.copyMany([key], to: target, store: store)
                    } else if groups.portfoliosOf(key) != [target] {
                        try? await groups.moveMany([key], to: target, store: store)
                    }
                }
            }
            UINotificationFeedbackGenerator().notificationOccurred(.success)
            dismiss()
            onAdded()
            // Reveal the most valuable one of the batch.
            if let top = purchases.max(by: { $0.unitPrice < $1.unitPrice }) {
                Router.shared.pull = PullEvent(product: top.product, quantity: purchases.count > 1 ? Double(purchases.count) : top.quantity, before: before, pulled: pulled)
            }
        } catch {
            self.error = error.localizedDescription
        }
    }
}

/// One line of the checklist: picture, name, set and number, condition and price, what you paid.
private struct ReviewRow: View, Equatable {
    var entry: ScanModel.Entry
    var owned = 0

    var body: some View {
        HStack(spacing: 12) {
            Group {
                if let p = entry.picked?.product {
                    ProductImage(product: p, cornerRadius: 5)
                } else if let img = entry.thumbnail {
                    Image(uiImage: img).resizable().scaledToFill()
                } else {
                    Color.white.opacity(0.08)
                }
            }
            .frame(width: 48, height: 66)
            .clipShape(RoundedRectangle(cornerRadius: 5, style: .continuous))

            VStack(alignment: .leading, spacing: 3) {
                Text(title).font(.geist(15, .semibold)).foregroundStyle(.white).lineLimit(1)
                if let p = entry.picked?.product {
                    Text(p.subtitle).font(.geist(12)).foregroundStyle(.white).lineLimit(1)
                } else if let message = entry.error ?? entry.result?.message {
                    Text(message).font(.geist(12)).foregroundStyle(.white).lineLimit(2)
                }
                HStack(spacing: 5) {
                    if let line = detail { Text(line).font(.geist(13)).foregroundStyle(.white).monospacedDigit().lineLimit(1) }
                    if owned > 0 { Tag(text: "Owned ×\(owned)", tint: Theme.lime) }
                }
                if let note = entry.note {
                    Text(note).font(.geist(12, .medium)).foregroundStyle(entry.rejected ? Theme.down : .white)
                }
            }
            Spacer(minLength: 8)
            VStack(alignment: .trailing, spacing: 3) {
                if entry.picked != nil {
                    Text(Format.money(entry.value)).font(.geist(15, .semibold)).foregroundStyle(.white).monospacedDigit()
                    if !entry.paid.isEmpty { Text("Paid \(entry.paid)").font(.geist(12)).foregroundStyle(.white).monospacedDigit() }
                } else if entry.state == .queued || entry.state == .reading {
                    ProgressView().tint(.white)
                }
                Image(systemName: "chevron.right").font(.system(size: 12, weight: .semibold)).foregroundStyle(.white.opacity(0.5))
            }
        }
        .padding(.vertical, 6)
    }

    /// Condition (or grade), the printing when the card has several.
    private var detail: String? {
        guard let p = entry.picked else { return nil }
        let condition = entry.isSlab ? entry.result?.read?.grade.map { "\($0.company) \($0.grade)" } : (p.product.isSealed ? nil : CardCondition(rawValue: entry.condition)?.short)
        let printing = (p.product.printings?.count ?? 0) > 1 ? (entry.printing ?? p.printing) : nil
        let line = [condition, printing].compactMap { $0 }.joined(separator: " · ")
        return line.isEmpty ? nil : line
    }

    private var title: String {
        switch entry.state {
        case .queued, .reading: return "Reading…"
        case .failed: return "Couldn't read · tap to try again"
        case .done:
            if let p = entry.picked { return p.product.name }
            switch entry.result?.status {
            case "ambiguous": return "Which one is it?"
            case "retake": return "Couldn't read it clearly"
            case "unsupported": return "That game or language isn't supported"
            default: return "No match found"
            }
        }
    }
}

/// What a whole scan shares: the portfolio, the day, where from, and the shipping, tax and fees
/// (totals for the lot, shared across the cards by price).
struct ScanBatchDetails {
    /// Nil: where each would go anyway (Main, or the copy's own portfolio).
    var portfolio: String?
    var date = Date()
    var source = ""
    var shipping = ""
    var tax = ""
    var fees = ""

    func summary(groups: GroupsStore, pulled: Bool) -> String {
        var parts: [String] = []
        if let portfolio { parts.append(groups.portfolios.first { $0.id == portfolio }?.name ?? "Main") }
        parts.append(Calendar.current.isDateInToday(date) ? "Today" : date.formatted(.dateTime.month(.abbreviated).day()))
        let place = source.trimmingCharacters(in: .whitespaces)
        if !pulled, !place.isEmpty { parts.append(place) }
        let extra = (MoneyField.value(shipping) ?? 0) + (MoneyField.value(tax) ?? 0) + (MoneyField.value(fees) ?? 0)
        if !pulled, extra > 0 { parts.append("+\(Format.money(extra))") }
        return parts.count == 1 && portfolio == nil ? "Portfolio, date, where, shipping" : parts.joined(separator: " · ")
    }

    /// The batch's details on each purchase: where, and its share of the extras (by price).
    func apply(to purchases: [CollectionStore.Purchase], pulled: Bool) -> [CollectionStore.Purchase] {
        guard !pulled else { return purchases }
        let place = source.trimmingCharacters(in: .whitespaces)
        let total = purchases.reduce(0) { $0 + $1.unitPrice * $1.quantity }
        let ship = MoneyField.value(shipping) ?? 0, tx = MoneyField.value(tax) ?? 0, fee = MoneyField.value(fees) ?? 0
        return purchases.map { p in
            var p = p
            if !place.isEmpty { p.source = place }
            let share = total > 0 ? p.unitPrice * p.quantity / total : 1 / Double(max(purchases.count, 1))
            p.shipping = (ship * share * 100).rounded() / 100
            p.tax = (tx * share * 100).rounded() / 100
            p.fees = (fee * share * 100).rounded() / 100
            return p
        }
    }
}

/// The batch details, as a small form on glass.
private struct ScanBatchDetailsSheet: View {
    @Binding var details: ScanBatchDetails
    var pulled: Bool
    @Environment(\.dismiss) private var dismiss
    @Environment(GroupsStore.self) private var groups

    var body: some View {
        NavigationStack {
            GlassForm {
                if !groups.portfolios.isEmpty {
                    Section {
                        Picker("Add to", selection: $details.portfolio) {
                            Text("Where they'd go anyway").tag(String?.none)
                            Text("Main").tag(Optional(GroupsStore.main))
                            ForEach(groups.portfolios) { Text($0.name).tag(Optional($0.id)) }
                        }
                    } header: {
                        SectionTitle("Portfolio")
                    }
                }
                Section {
                    DatePicker(pulled ? "Pulled on" : "Date", selection: $details.date, in: ...Date(), displayedComponents: .date)
                    if !pulled {
                        HStack {
                            Text("Where")
                            Spacer()
                            TextField("Card show, eBay, store…", text: $details.source)
                                .multilineTextAlignment(.trailing)
                                .textInputAutocapitalization(.words)
                        }
                        MoneyField(title: "Shipping", text: $details.shipping)
                        MoneyField(title: "Tax", text: $details.tax)
                        MoneyField(title: "Fees", text: $details.fees)
                    }
                } header: {
                    SectionTitle(pulled ? "Pull" : "Purchase")
                } footer: {
                    SectionNote(pulled
                        ? "For every card in this scan."
                        : "For every card in this scan. Shipping, tax and fees are totals for the lot, shared across the cards by price. To grade a card or set its own details, tap it and pick Add with all details.")
                }
            }
            .scrollContentBackground(.hidden)
            .navigationTitle("Details for all")
            .navigationBarTitleDisplayMode(.inline)
            .toolbar { ToolbarItem(placement: .confirmationAction) { Button("Done") { dismiss() } } }
        }
        .presentationDetents([.large])
        .glassSheet()
    }
}
