import SwiftUI

/// One scan, open: the full card page (price history, eBay comps, graded values, your position),
/// with this scan's own panel under the title: what it's worth in the condition and printing you
/// choose, what you paid, "Wrong card?" (search) and Remove. A scan with no match yet shows its
/// close matches to pick from instead. Opens from a tile in the scanner and from a row in the
/// review; the same sheet everywhere.
struct ScanCardSheet: View {
    let model: ScanModel
    let id: UUID
    /// Takes the scan out (the sheet closes itself first).
    var onRemove: () -> Void
    @Environment(\.dismiss) private var dismiss
    @State private var searching = false

    private var entry: ScanModel.Entry? { model.entries.first { $0.id == id } }

    var body: some View {
        Group {
            if let entry, let product = entry.picked?.product {
                NavigationStack {
                    ProductDetailView(productId: product.id, extra: AnyView(ScanPanel(model: model, id: id, onWrong: { searching = true }, onRemove: {
                        dismiss()
                        onRemove()
                    })))
                    .navigationDestination(for: String.self) { ProductDetailView(productId: $0) }
                    .toolbar { ToolbarItem(placement: .cancellationAction) { Button("Done") { dismiss() } } }
                }
            } else if let entry {
                Unmatched(model: model, entry: entry, onWrong: { searching = true }, onRemove: {
                    dismiss()
                    onRemove()
                })
            } else {
                Color.clear.onAppear { dismiss() }
            }
        }
        .presentationDetents([.fraction(0.93)])
        .presentationDragIndicator(.visible)
        .glassSheet()
        // The right card, picked from search, takes this scan over.
        .sheet(isPresented: $searching) {
            SearchScreen(mode: .add, onPick: { hit in model.replace(id, with: hit) })
        }
    }
}

/// This scan's panel on the card page: the price for the chosen condition and printing (the
/// Owned sheet's maths), the chips to change them, what you paid, and the ways out.
private struct ScanPanel: View {
    let model: ScanModel
    let id: UUID
    var onWrong: () -> Void
    var onRemove: () -> Void
    @Environment(CollectionStore.self) private var store

    private var entry: ScanModel.Entry? { model.entries.first { $0.id == id } }
    private var inDeal: Bool { model.onPick != nil }

    var body: some View {
        if let entry, let c = entry.picked {
            VStack(alignment: .leading, spacing: 14) {
                HStack(alignment: .firstTextBaseline) {
                    Text("This scan").font(.geist(13, .semibold)).foregroundStyle(.white)
                    Spacer()
                    HStack(spacing: 6) {
                        if let g = entry.result?.read?.grade { Tag(text: "\(g.company) \(g.grade)", tint: Theme.lime) }
                        let owned = store.allHoldings.filter { $0.identity.productId == c.product.id }.reduce(0) { $0 + $1.quantity }
                        if owned > 0 { Tag(text: "Owned ×\(Int(owned))", tint: Theme.lime) }
                    }
                }
                VStack(alignment: .leading, spacing: 2) {
                    Text(Format.money(entry.value)).font(.display(30)).tracking(-0.9).monospacedDigit().foregroundStyle(.white)
                        .contentTransition(.numericText())
                        .animation(.snappy(duration: 0.25), value: entry.value)
                    Text(entry.priceNote ?? "No price yet").font(.geist(12)).foregroundStyle(.white).lineLimit(2)
                }
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
                    HStack(spacing: 12) {
                        Text("Paid").font(.geist(13, .semibold)).foregroundStyle(.white)
                        Spacer()
                        // The price shows in white when nothing is typed (it's what a blank means).
                        TextField("", text: Binding(get: { entry.paid }, set: { model.setPaid(id, $0) }),
                                  prompt: Text(Format.money(entry.value ?? 0)).foregroundColor(.white))
                            .keyboardType(.decimalPad)
                            .multilineTextAlignment(.trailing)
                            .font(.geist(16, .semibold)).monospacedDigit().foregroundStyle(.white)
                            .frame(width: 110)
                            .padding(.horizontal, 12).frame(height: 40)
                            .background(Color.white.opacity(0.1), in: RoundedRectangle(cornerRadius: 12, style: .continuous))
                    }
                }
                HStack(spacing: 10) {
                    pill("Wrong card?", icon: "magnifyingglass", action: onWrong)
                    Spacer()
                    Button(action: onRemove) {
                        HStack(spacing: 7) {
                            Image(systemName: "trash.fill").font(.system(size: 13, weight: .semibold))
                            Text("Remove").font(.geist(14, .semibold))
                        }
                        .foregroundStyle(.white)
                        .padding(.horizontal, 14).frame(height: 40)
                        .background(Theme.planPink, in: Capsule())
                        .contentShape(Capsule())
                    }
                    .buttonStyle(.plain)
                }
            }
            .padding(16)
            .background(Theme.surface2, in: RoundedRectangle(cornerRadius: 20, style: .continuous))
            .overlay(RoundedRectangle(cornerRadius: 20, style: .continuous).strokeBorder(Theme.borderStrong, lineWidth: 1))
        }
    }

    private func labelled<Content: View>(_ label: String, @ViewBuilder content: () -> Content) -> some View {
        VStack(alignment: .leading, spacing: 8) {
            Text(label).font(.geist(13, .semibold)).foregroundStyle(.white)
            content()
        }
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
}

/// A scan with no card yet: the photo, the close matches to pick from (or why there are none),
/// search for the right one, try again, or remove.
private struct Unmatched: View {
    let model: ScanModel
    let entry: ScanModel.Entry
    var onWrong: () -> Void
    var onRemove: () -> Void
    @Environment(\.dismiss) private var dismiss

    var body: some View {
        ScrollView(showsIndicators: false) {
            VStack(alignment: .leading, spacing: 18) {
                HStack(alignment: .top, spacing: 14) {
                    Group {
                        if let img = entry.thumbnail { Image(uiImage: img).resizable().scaledToFill() } else { Color.white.opacity(0.08) }
                    }
                    .frame(width: 92, height: 128)
                    .clipShape(RoundedRectangle(cornerRadius: 8, style: .continuous))
                    VStack(alignment: .leading, spacing: 6) {
                        Text(title).font(.display(22)).tracking(-0.6).lineLimit(3)
                        if let message = entry.error ?? entry.result?.message, entry.result?.candidates.isEmpty ?? true {
                            Text(message).font(.geist(14)).lineLimit(4)
                        }
                    }
                    Spacer(minLength: 0)
                }
                let list = entry.result?.candidates ?? []
                if !list.isEmpty {
                    VStack(alignment: .leading, spacing: 8) {
                        Text("Which one is it?").font(.geist(13, .semibold))
                        ScrollView(.horizontal, showsIndicators: false) {
                            HStack(spacing: 8) {
                                ForEach(Array(list.prefix(6).enumerated()), id: \.offset) { _, c in
                                    Button { model.pick(c, for: entry.id) } label: {
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
                }
                HStack(spacing: 10) {
                    pill("Search for it", icon: "magnifyingglass", action: onWrong)
                    if entry.state == .failed || entry.result?.status == "retake" {
                        pill("Try again", icon: "arrow.clockwise") { model.retry(entry.id); dismiss() }
                    }
                }
                Button(action: onRemove) {
                    Label("Remove from this scan", systemImage: "trash.fill")
                }
                .buttonStyle(Button3D(kind: .pink, height: 48))
            }
            .padding(.horizontal, 20).padding(.top, 18).padding(.bottom, 24)
        }
        .foregroundStyle(.white)
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

    private var title: String {
        switch entry.state {
        case .queued, .reading: return "Reading…"
        case .failed: return "Couldn't read"
        case .done:
            switch entry.result?.status {
            case "ambiguous": return "Which one is it?"
            case "retake": return "Couldn't read it clearly"
            case "unsupported": return "That game or language isn't supported"
            default: return "No match found"
            }
        }
    }
}
