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
    @State private var pulled = false
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
            let purchases = model.purchases(pulled: pulled, date: Format.day())
            try await store.add(purchases)
            UINotificationFeedbackGenerator().notificationOccurred(.success)
            dismiss()
            onAdded()
            // Reveal the most valuable one of the batch.
            if let top = purchases.max(by: { $0.unitPrice < $1.unitPrice }) {
                Router.shared.pull = PullEvent(product: top.product, quantity: purchases.count > 1 ? Double(purchases.count) : top.quantity, before: before)
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
                    if entry.picked != nil, entry.unsure { Tag(text: "Check", tint: Theme.warn) }
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
