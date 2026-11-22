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
    @Environment(GradingStore.self) private var grading
    /// The scan's default, bought at market or pulled (kept on the model, so a card's purchase sheet starts from it).
    private var pulled: Bool { model.defaultPulled }
    /// The card whose purchase details are open (from its row's Edit link).
    @State private var purchaseFor: EditingScan?
    /// The details for the whole batch: portfolio, date, where, and shipping, tax and fees.
    @State private var details = ScanBatchDetails()
    @State private var editingDetails = false
    @State private var saving = false
    @State private var error: String?
    /// The scan open close up.
    @State private var editing: EditingScan?
    /// The list picker for "Add to a list" (our own action sheet).
    @State private var pickingList = false

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
                    Group {
                        if entry.state == .done, entry.picked != nil, !entry.rejected {
                            // The scan page's opened-out row: printing and condition in place, and
                            // "Bought $X" with a pencil for its purchase details.
                            ScanListRow(entry: entry, owned: owned(entry), inDeal: model.onPick != nil,
                                        onOpen: { open(entry) },
                                        setPrinting: { model.setPrinting(entry.id, $0) },
                                        setCondition: { model.setCondition(entry.id, $0) },
                                        pulled: pulled,
                                        onPurchase: { purchaseFor = EditingScan(id: entry.id) })
                        } else {
                            // Rows are compared by value: a change to one scan redraws that row alone.
                            ReviewRow(entry: entry, owned: owned(entry), pulled: pulled).equatable()
                        }
                    }
                        .contentShape(Rectangle())
                        // Anywhere else on the row: the card's page.
                        .onTapGesture { open(entry) }
                        .id(entry.id)
                        .listRowBackground(Color.clear)
                        .listRowSeparator(.hidden)
                        .listRowInsets(EdgeInsets(top: 0, leading: 16, bottom: 0, trailing: 16))
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
        .sheet(isPresented: $editingDetails) { ScanBatchDetailsSheet(details: $details, pulled: $model.defaultPulled) }
        .sheet(item: $purchaseFor) { e in ScanPurchaseSheet(model: model, id: e.id) }
        .sheet(item: $editing) { e in
            ScanCardSheet(model: model, id: e.id, onRemove: { withAnimation(.snappy) { model.remove(e.id) } })
        }
    }

    /// A scan's card page (a failed read is tried again first).
    private func open(_ entry: ScanModel.Entry) {
        if entry.state == .failed { model.retry(entry.id) }
        if let p = entry.picked { store.setOpenPrinting(entry.printing ?? p.printing, for: p.product.id) }
        editing = EditingScan(id: entry.id)
    }

    /// How many of this card you already have.
    private func owned(_ e: ScanModel.Entry) -> Int {
        guard let id = e.picked?.product.id else { return 0 }
        return Int(store.allHoldings.filter { $0.identity.productId == id }.reduce(0) { $0 + $1.quantity })
    }

    /// The scan's defaults in one line (tap to change), then the Add button. Sits on the sheet's
    /// glass under a hairline.
    private var footer: some View {
        VStack(spacing: 12) {
            // The defaults every card starts from: bought at market or pulled, portfolio, date,
            // where, shipping. A card's own purchase details (its row's Edit) override them.
            Button { editingDetails = true } label: {
                HStack(spacing: 8) {
                    Image(systemName: "slider.horizontal.3").font(.system(size: 13, weight: .semibold)).foregroundStyle(Theme.lime)
                    (Text("Defaults: ").foregroundStyle(Theme.muted) + Text(details.summary(groups: groups, pulled: pulled)).foregroundStyle(.white))
                        .font(.geist(13, .medium)).lineLimit(1)
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
            // Or put them on a list instead (a want list, cards for a show), without adding them
            // to your collection.
            Button { Haptics.tap(); pickingList = true } label: {
                HStack(spacing: 8) {
                    Image(systemName: "square.stack").font(.system(size: 14, weight: .semibold))
                    Text("Add \(model.picks.count) to a list")
                }
                .font(.geist(15, .semibold)).foregroundStyle(.white)
                .frame(maxWidth: .infinity).frame(height: 46)
                .liquidGlass(in: Capsule(), interactive: true)
                .contentShape(Capsule())
            }
            .buttonStyle(.plain)
            .disabled(saving || model.picks.isEmpty)
            .opacity(model.picks.isEmpty ? 0.45 : 1)
            .actionsSheet(isPresented: $pickingList, title: "Add to a list") { listActions }
        }
        .padding(.horizontal, 16).padding(.top, 12).padding(.bottom, 8)
        .background(alignment: .top) { Rectangle().fill(Color.white.opacity(0.08)).frame(height: 1) }
        .background(Color.black.opacity(0.18))
    }

    /// Your lists (tap one to put every matched card on it) and New list… to name one right here.
    private var listActions: [[SheetAction]] {
        let ids = Array(Set(model.picks.compactMap { $0.picked?.product.id }))
        var rows: [SheetAction] = groups.shelves.map { list in
            SheetAction(title: list.name, icon: "rectangle.stack") { putOnList { try await groups.addMany(list.id, productIds: ids) } }
        }
        if Pro.shared.unlocked || groups.shelves.count < Pro.freeShelves {
            rows.append(SheetAction(title: "New list…", icon: "plus", outlined: true, onCreate: { name in
                putOnList { _ = try await groups.createShelf(name, productIds: ids) }
            }))
        }
        return [rows]
    }

    /// Saves to the list, then closes the review and the camera (the scans are done with).
    private func putOnList(_ work: @escaping () async throws -> Void) {
        // So the list shows each card's picture and price right away.
        for pick in model.picks { if let p = pick.picked { groups.remember(p.product, market: p.market) } }
        Task {
            do {
                try await work()
                UINotificationFeedbackGenerator().notificationOccurred(.success)
                dismiss()
                onAdded()
            } catch {
                self.error = error.localizedDescription
            }
        }
    }

    private func add() async {
        saving = true
        error = nil
        defer { saving = false }
        do {
            let before = store.allHoldings.reduce(0) { $0 + ($1.value ?? 0) }
            // Cards with their own details use them; the rest share the batch's.
            let picks = model.picks
            let drafted = picks.compactMap(\.draft)
            let shared = details.apply(to: picks.filter { $0.draft == nil }.compactMap { model.purchase(for: $0, pulled: pulled, date: Format.day(details.date)) }, pulled: pulled)
            let purchases = drafted.map(\.purchase) + shared
            // Where each goes: a card's own pick, else the batch's (nil: where it would go anyway).
            let targets: [String?] = drafted.map { Optional($0.portfolio) } + shared.map { _ in details.portfolio }
            let ownedBefore = Set(store.allHoldings.map(\.identity.key))
            try await store.add(purchases)
            for d in drafted {
                let p = d.purchase
                let key = HoldingIdentity(productId: p.product.id, printing: p.printing, condition: p.condition, gradeCompany: p.gradeCompany, grade: p.grade).key
                if let bumper = d.bumper { grading.setBumper(key, bumper) }
                if d.pristine { grading.setPristine(key, true) }
            }
            if drafted.contains(where: \.pristine) { Task { await store.loadSlabPrices() } }
            // Into the picked portfolio: more of a copy you own is also shown there (a Copy); a new one goes only there.
            if !groups.portfolios.isEmpty {
                for (p, target) in zip(purchases, targets) {
                    guard let target else { continue }
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
    /// The scan's default (bought at market or pulled), for what the line under the card says.
    var pulled = false
    /// Its purchase details (the Edit link on the row).
    var onPurchase: () -> Void = {}

    static func == (a: Self, b: Self) -> Bool { a.entry == b.entry && a.owned == b.owned && a.pulled == b.pulled }

    /// What this card will be saved as: its own details, a typed price, or the scan's default.
    private var purchaseLine: (text: String, own: Bool) {
        if let d = entry.draft { return (ScanDraftSummary.text(d), true) }
        if !entry.paid.isEmpty { return ("Paid \(entry.paid)", true) }
        if pulled { return ("Pulled", false) }
        return ("Market \(Format.money(entry.value))", false)
    }

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
                if entry.picked != nil {
                    // A quick way to the purchase details, without opening the card's page.
                    Button(action: onPurchase) {
                        HStack(spacing: 6) {
                            Text(purchaseLine.text).foregroundStyle(purchaseLine.own ? .white : Theme.muted).lineLimit(1)
                            Text("Edit").foregroundStyle(Theme.lime)
                        }
                        .font(.geist(12, .medium))
                        .padding(.horizontal, 10).frame(height: 26)
                        .background(Color.white.opacity(0.08), in: Capsule())
                        .contentShape(Capsule())
                    }
                    .buttonStyle(.borderless)
                    .padding(.top, 3)
                    .accessibilityLabel("Purchase details: \(purchaseLine.text). Edit")
                }
                if let note = entry.note {
                    Text(note).font(.geist(12, .medium)).foregroundStyle(entry.rejected ? Theme.down : .white)
                }
            }
            Spacer(minLength: 8)
            VStack(alignment: .trailing, spacing: 3) {
                if entry.picked != nil {
                    Text(Format.money(entry.value)).font(.geist(15, .semibold)).foregroundStyle(.white).monospacedDigit()
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
        var parts: [String] = [pulled ? "Pulled" : "Bought at market"]
        if let portfolio { parts.append(groups.portfolios.first { $0.id == portfolio }?.name ?? "Main") }
        parts.append(Calendar.current.isDateInToday(date) ? "Today" : date.formatted(.dateTime.month(.abbreviated).day()))
        let place = source.trimmingCharacters(in: .whitespaces)
        if !pulled, !place.isEmpty { parts.append(place) }
        let extra = (MoneyField.value(shipping) ?? 0) + (MoneyField.value(tax) ?? 0) + (MoneyField.value(fees) ?? 0)
        if !pulled, extra > 0 { parts.append("+\(Format.money(extra))") }
        return parts.joined(separator: " · ")
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
    @Binding var pulled: Bool
    @Environment(\.dismiss) private var dismiss
    @Environment(GroupsStore.self) private var groups

    var body: some View {
        NavigationStack {
            GlassForm {
                Section {
                    ChipPicker(options: [(false, "Bought"), (true, "Pulled")], selection: $pulled, fills: true)
                        .listRowBackground(Color.clear)
                        .listRowInsets(EdgeInsets())
                } header: {
                    SectionTitle("How you got them")
                } footer: {
                    SectionNote(pulled ? "Pulled from packs: $0 each, marked as pulls." : "Bought: at market price unless you set a card's own price.")
                }
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
                        ? "For every card in this scan, unless you set its own purchase details."
                        : "For every card in this scan, unless you set its own purchase details. Shipping, tax and fees are totals for the lot, shared across the cards by price.")
                }
            }
            .scrollContentBackground(.hidden)
            .navigationTitle("Defaults for this scan")
            .navigationBarTitleDisplayMode(.inline)
            .toolbar { ToolbarItem(placement: .confirmationAction) { Button("Done") { dismiss() } } }
        }
        .presentationDetents([.large])
        .glassSheet()
    }
}
