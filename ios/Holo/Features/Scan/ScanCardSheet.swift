import SwiftUI

/// One scan, close up: the card, what it's worth in the condition and printing you choose, what
/// you paid, and the ways out (the right card from search, the full card page, remove). Opens
/// from a tile in the scanner and from a row in the review; the same sheet everywhere. Light on
/// purpose: nothing loads here that the scan didn't already fetch.
struct ScanCardSheet: View {
    let model: ScanModel
    let id: UUID
    /// Takes the scan out (the sheet closes itself first).
    var onRemove: () -> Void
    @Environment(\.dismiss) private var dismiss
    @Environment(CollectionStore.self) private var store
    @State private var searching = false
    @State private var fullPage = false

    private var entry: ScanModel.Entry? { model.entries.first { $0.id == id } }
    private var inDeal: Bool { model.onPick != nil }

    var body: some View {
        Group {
            if let entry {
                content(entry)
            } else {
                Color.clear.onAppear { dismiss() }
            }
        }
        .presentationDetents([.fraction(0.72), .large])
        .presentationDragIndicator(.visible)
        .glassSheet()
        // The right card, picked from search, takes this scan over.
        .sheet(isPresented: $searching) {
            SearchScreen(mode: .add, onPick: { hit in model.replace(id, with: hit) })
        }
        // Everything about the card, for when you want the history too.
        .sheet(isPresented: $fullPage) {
            if let p = entry?.picked?.product {
                NavigationStack {
                    ProductDetailView(productId: p.id)
                        .navigationDestination(for: String.self) { ProductDetailView(productId: $0) }
                        .toolbar { ToolbarItem(placement: .cancellationAction) { Button("Done") { fullPage = false } } }
                }
                .presentationDetents([.fraction(0.93)])
                .glassSheet()
            }
        }
    }

    @ViewBuilder private func content(_ entry: ScanModel.Entry) -> some View {
        ScrollView(showsIndicators: false) {
            VStack(alignment: .leading, spacing: 18) {
                header(entry)
                if let c = entry.picked {
                    price(entry)
                    if !inDeal {
                        if let printings = c.product.printings, printings.count > 1 {
                            labelled("Printing") {
                                ChipPicker(options: printings.map { ($0, $0) },
                                           selection: Binding(get: { entry.printing ?? c.printing ?? printings[0] }, set: { model.setPrinting(id, $0) }),
                                           scrolls: true)
                            }
                        }
                        if !c.product.isSealed, !entry.isSlab {
                            labelled("Condition") {
                                ChipPicker(options: CardCondition.allCases.map { ($0.rawValue, $0.short) },
                                           selection: Binding(get: { entry.condition }, set: { model.setCondition(id, $0) }))
                            }
                        }
                        paid(entry)
                    }
                } else {
                    candidates(entry)
                }
                actions(entry)
            }
            .padding(.horizontal, 20).padding(.top, 18).padding(.bottom, 24)
        }
        .foregroundStyle(.white)
    }

    // MARK: Pieces

    private func header(_ entry: ScanModel.Entry) -> some View {
        HStack(alignment: .top, spacing: 14) {
            Group {
                if let p = entry.picked?.product {
                    ProductImage(product: p, cornerRadius: 8)
                } else if let img = entry.thumbnail {
                    Image(uiImage: img).resizable().scaledToFill()
                } else {
                    Color.white.opacity(0.08)
                }
            }
            .frame(width: 92, height: 128)
            .clipShape(RoundedRectangle(cornerRadius: 8, style: .continuous))
            VStack(alignment: .leading, spacing: 6) {
                Text(title(entry)).font(.display(22)).tracking(-0.6).lineLimit(3)
                if let p = entry.picked?.product {
                    Text(p.subtitle).font(.geist(14)).lineLimit(2)
                }
                HStack(spacing: 6) {
                    if let g = entry.result?.read?.grade { Tag(text: "\(g.company) \(g.grade)", tint: Theme.lime) }
                    if let p = entry.picked?.product {
                        let owned = store.allHoldings.filter { $0.identity.productId == p.id }.reduce(0) { $0 + $1.quantity }
                        if owned > 0 { Tag(text: "Owned ×\(Int(owned))", tint: Theme.lime) }
                    }
                    if entry.picked != nil, entry.unsure { Tag(text: "Check it's right", tint: Theme.warn) }
                }
            }
            Spacer(minLength: 0)
        }
    }

    private func price(_ entry: ScanModel.Entry) -> some View {
        VStack(alignment: .leading, spacing: 2) {
            Text(Format.money(entry.value)).font(.display(32)).tracking(-1).monospacedDigit()
                .contentTransition(.numericText())
                .animation(.snappy(duration: 0.25), value: entry.value)
            Text(entry.priceNote ?? "No price yet").font(.geist(12)).lineLimit(2)
        }
    }

    private func labelled<Content: View>(_ label: String, @ViewBuilder content: () -> Content) -> some View {
        VStack(alignment: .leading, spacing: 8) {
            Text(label).font(.geist(13, .semibold))
            content()
        }
    }

    private func paid(_ entry: ScanModel.Entry) -> some View {
        HStack(spacing: 12) {
            VStack(alignment: .leading, spacing: 2) {
                Text("Paid").font(.geist(13, .semibold))
                Text("Blank: the price above, or $0 if pulled").font(.geist(11)).lineLimit(1)
            }
            Spacer()
            TextField(Format.money(entry.value ?? 0), text: Binding(get: { entry.paid }, set: { model.setPaid(id, $0) }))
                .keyboardType(.decimalPad)
                .multilineTextAlignment(.trailing)
                .font(.geist(16, .semibold)).monospacedDigit()
                .frame(width: 110)
                .padding(.horizontal, 12).frame(height: 40)
                .background(Color.white.opacity(0.1), in: RoundedRectangle(cornerRadius: 12, style: .continuous))
        }
    }

    /// No clear match: the close ones to pick from.
    @ViewBuilder private func candidates(_ entry: ScanModel.Entry) -> some View {
        let list = entry.result?.candidates ?? []
        if !list.isEmpty {
            labelled("Which one is it?") {
                ScrollView(.horizontal, showsIndicators: false) {
                    HStack(spacing: 8) {
                        ForEach(Array(list.prefix(6).enumerated()), id: \.offset) { _, c in
                            Button { model.pick(c, for: id) } label: {
                                VStack(alignment: .leading, spacing: 4) {
                                    ProductImage(product: c.product, cornerRadius: 6).frame(width: 84, height: 116)
                                    Text(c.product.name).font(.geist(12, .semibold)).lineLimit(1)
                                    Text(c.product.subtitle).font(.geist(11)).lineLimit(1)
                                    Text(Format.money(c.market)).font(.geist(12, .bold)).monospacedDigit()
                                }
                                .frame(width: 96, alignment: .leading)
                                .padding(8)
                                .background(Color.white.opacity(0.1), in: RoundedRectangle(cornerRadius: 12, style: .continuous))
                            }
                            .buttonStyle(.plain)
                        }
                    }
                }
            }
        } else if let message = entry.error ?? entry.result?.message {
            Text(message).font(.geist(14)).lineLimit(3)
        }
    }

    private func actions(_ entry: ScanModel.Entry) -> some View {
        VStack(spacing: 10) {
            HStack(spacing: 10) {
                pill("Wrong card?", icon: "magnifyingglass") { searching = true }
                if entry.picked?.product != nil {
                    pill("Full card page", icon: "arrow.up.right") { fullPage = true }
                }
                if entry.state == .failed {
                    pill("Try again", icon: "arrow.clockwise") { model.retry(id); dismiss() }
                }
            }
            Button {
                dismiss()
                onRemove()
            } label: {
                Label("Remove from this scan", systemImage: "trash.fill")
            }
            .buttonStyle(Button3D(kind: .pink, height: 48))
        }
        .padding(.top, 6)
    }

    private func pill(_ title: String, icon: String, action: @escaping () -> Void) -> some View {
        Button(action: action) {
            HStack(spacing: 7) {
                Image(systemName: icon).font(.system(size: 13, weight: .semibold))
                Text(title).font(.geist(14, .semibold))
            }
            .foregroundStyle(.white)
            .padding(.horizontal, 14).frame(height: 40)
            .background(Color.white.opacity(0.12), in: Capsule())
            .contentShape(Capsule())
        }
        .buttonStyle(.plain)
    }

    private func title(_ entry: ScanModel.Entry) -> String {
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
