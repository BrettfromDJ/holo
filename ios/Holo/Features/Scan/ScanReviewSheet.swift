import SwiftUI

/// After scanning: pick between close matches, set condition and what you paid, then add them all.
struct ScanReviewSheet: View {
    @Bindable var model: ScanModel
    var focus: UUID?
    var onAdded: () -> Void
    @Environment(\.dismiss) private var dismiss
    @Environment(CollectionStore.self) private var store
    @State private var pulled = false
    @State private var saving = false
    @State private var error: String?

    var body: some View { sheetBody.presentationDetents([.fraction(0.93)]).glassSheet() }

    @ViewBuilder private var sheetBody: some View {
        NavigationStack {
            ScrollViewReader { proxy in
                GlassList {
                    // The heading sits in the content (no navigation bar on a display sheet):
                    // how many were scanned, and a glass pill back to the camera.
                    Section {
                        HStack(spacing: 12) {
                            Text("\(model.entries.count) scanned").font(.display(26)).tracking(-0.7).foregroundStyle(.white)
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
                    ForEach($model.entries) { $entry in
                        ReviewRow(entry: $entry, inDeal: model.onPick != nil, onPick: { model.pick($0, for: entry.id) }, onRetry: { model.retry(entry.id) },
                                  onRemove: { withAnimation(.snappy) { model.remove(entry.id) } })
                            .id(entry.id)
                            .listRowBackground(Color.white.opacity(0.07))
                            // Swipe left: pink with a trash icon, like a deal card's.
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
            // A matched card's picture and name lead to its page.
            .navigationDestination(for: String.self) { ProductDetailView(productId: $0) }
            .toolbar(.hidden, for: .navigationBar)
            .safeAreaInset(edge: .bottom) {
                if model.onPick == nil {
                    footer
                } else {
                    Button("Done") { dismiss() }.buttonStyle(LimeButtonStyle()).padding(16).background(.bar)
                }
            }
        }
        .presentationDragIndicator(.visible)
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

private struct ReviewRow: View {
    @Binding var entry: ScanModel.Entry
    var inDeal = false
    var onPick: (ScanCandidate) -> Void
    var onRetry: () -> Void
    var onRemove: () -> Void

    var body: some View {
        VStack(alignment: .leading, spacing: 10) {
            HStack(spacing: 12) {
                // The picture and name: a link to the card's page once it has matched.
                Group {
                    if let p = entry.picked?.product {
                        NavigationLink(value: p.id) { heading }.buttonStyle(.plain)
                    } else {
                        heading
                    }
                }
                Spacer()
                if entry.picked != nil {
                    Text(Format.money(entry.value)).font(.subheadline.weight(.semibold)).monospacedDigit()
                } else if entry.state == .failed {
                    Button("Retry", action: onRetry).font(.footnote)
                } else if entry.state == .queued || entry.state == .reading {
                    ProgressView()
                }
                // Plain to see, as on a deal card; swiping left works too.
                Button(action: onRemove) {
                    Image(systemName: "trash").font(.system(size: 13, weight: .medium)).foregroundStyle(.white)
                        .frame(width: 30, height: 30)
                        .background(Circle().fill(Color.white.opacity(0.12)))
                        .contentShape(Circle())
                }
                .buttonStyle(.plain)
                .accessibilityLabel("Remove \(title)")
            }

            // Close matches: tap the right one.
            if entry.state == .done, let candidates = entry.result?.candidates, candidates.count > 1 || entry.picked == nil, !candidates.isEmpty {
                ScrollView(.horizontal, showsIndicators: false) {
                    HStack(spacing: 8) {
                        ForEach(Array(candidates.prefix(5).enumerated()), id: \.offset) { _, c in
                            Button { onPick(c) } label: {
                                VStack(alignment: .leading, spacing: 4) {
                                    ProductImage(product: c.product, cornerRadius: 5).frame(width: 70, height: 96)
                                    Text(c.product.name).font(.caption2.weight(.medium)).lineLimit(1)
                                    Text(c.product.number.map { "#\($0)" } ?? "").font(.caption2).foregroundStyle(Theme.muted)
                                }
                                .frame(width: 80)
                                .padding(6)
                                .background(entry.picked == c ? Theme.lime.opacity(0.18) : Theme.surface2, in: RoundedRectangle(cornerRadius: 10))
                            }
                            .buttonStyle(.plain)
                        }
                    }
                }
            }

            if let note = entry.note {
                Text(note).font(.caption.weight(.medium)).foregroundStyle(entry.rejected ? Theme.down : Theme.muted)
            }
            if let picked = entry.picked, !inDeal {
                HStack(spacing: 10) {
                    if !picked.product.isSealed && entry.result?.read?.kind != "slab" {
                        Picker("Condition", selection: $entry.condition) {
                            ForEach(CardCondition.allCases) { Text($0.short).tag($0.rawValue) }
                        }
                        .pickerStyle(.menu)
                        .fixedSize()
                    }
                    Spacer()
                    Text("Paid").font(.footnote).foregroundStyle(Theme.muted)
                    TextField(Format.money(entry.value ?? 0), text: $entry.paid)
                        .keyboardType(.decimalPad)
                        .multilineTextAlignment(.trailing)
                        .monospacedDigit()
                        .frame(width: 90)
                        .padding(.horizontal, 10)
                        .frame(height: 36)
                        .background(Theme.surface2, in: RoundedRectangle(cornerRadius: 10))
                }
            }
        }
        .padding(.vertical, 6)
    }

    private var heading: some View {
        HStack(spacing: 12) {
            Group {
                if let p = entry.picked?.product {
                    ProductImage(product: p, cornerRadius: 5)
                } else if let img = entry.thumbnail {
                    Image(uiImage: img).resizable().scaledToFill()
                } else {
                    Theme.surface2
                }
            }
            .frame(width: 44, height: 60)
            .clipShape(RoundedRectangle(cornerRadius: 5))

            VStack(alignment: .leading, spacing: 2) {
                Text(title).font(.subheadline.weight(.semibold))
                if let c = entry.picked {
                    Text([c.product.subtitle, c.printing, entry.result?.read?.grade.map { "\($0.company) \($0.grade)" }]
                        .compactMap { $0 }.filter { !$0.isEmpty }.joined(separator: " · "))
                        .font(.caption).foregroundStyle(Theme.muted).lineLimit(2)
                } else if let message = entry.error ?? entry.result?.message {
                    Text(message).font(.caption).foregroundStyle(Theme.muted)
                }
            }
        }
    }

    private var title: String {
        switch entry.state {
        case .queued, .reading: return "Reading…"
        case .failed: return "Couldn't read"
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
