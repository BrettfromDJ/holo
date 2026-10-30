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

    var body: some View {
        NavigationStack {
            ScrollViewReader { proxy in
                List {
                    ForEach($model.entries) { $entry in
                        ReviewRow(entry: $entry, onPick: { model.pick($0, for: entry.id) }, onRetry: { model.retry(entry.id) })
                            .id(entry.id)
                            .listRowBackground(Theme.surface)
                            .swipeActions { Button("Remove", role: .destructive) { model.remove(entry.id) } }
                    }
                    if let error {
                        Text(error).foregroundStyle(Theme.down)
                    }
                }
                .scrollContentBackground(.hidden)
                .background(Theme.background)
                .onAppear { if let focus { proxy.scrollTo(focus, anchor: .center) } }
            }
            .navigationTitle("\(model.entries.count) scanned")
            .navigationBarTitleDisplayMode(.inline)
            .toolbar {
                ToolbarItem(placement: .cancellationAction) { Button("Back to camera") { dismiss() } }
            }
            .safeAreaInset(edge: .bottom) { footer }
        }
        .presentationDragIndicator(.visible)
    }

    private var footer: some View {
        VStack(spacing: 12) {
            HStack {
                Text("If you leave a price blank, you paid").font(.footnote).foregroundStyle(Theme.muted)
                Spacer()
                Picker("", selection: $pulled) {
                    Text("Market").tag(false)
                    Text("$0 (pulled)").tag(true)
                }
                .pickerStyle(.segmented)
                .frame(width: 170)
            }
            Button {
                Task { await add() }
            } label: {
                Text(saving ? "Adding…" : "Add \(model.picks.count) to collection · \(Format.money(model.total))")
            }
            .buttonStyle(LimeButtonStyle())
            .disabled(saving || model.picks.isEmpty)
        }
        .padding(16)
        .background(.bar)
    }

    private func add() async {
        saving = true
        error = nil
        defer { saving = false }
        do {
            try await store.add(model.purchases(pulled: pulled, date: Format.day()))
            UINotificationFeedbackGenerator().notificationOccurred(.success)
            dismiss()
            onAdded()
        } catch {
            self.error = error.localizedDescription
        }
    }
}

private struct ReviewRow: View {
    @Binding var entry: ScanModel.Entry
    var onPick: (ScanCandidate) -> Void
    var onRetry: () -> Void

    var body: some View {
        VStack(alignment: .leading, spacing: 10) {
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
                Spacer()
                if entry.picked != nil {
                    Text(Format.money(entry.value)).font(.subheadline.weight(.semibold)).monospacedDigit()
                } else if entry.state == .failed {
                    Button("Retry", action: onRetry).font(.footnote)
                } else if entry.state == .queued || entry.state == .reading {
                    ProgressView()
                }
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

            if let picked = entry.picked {
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
