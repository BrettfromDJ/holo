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
                    Text(Format.money(entry.value)).font(.display(30)).tracking(-0.9).padding(.trailing, 0.9).monospacedDigit().foregroundStyle(.white)
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
                let list = Array((entry.result?.candidates ?? []).prefix(6))
                // Your photo beside the question, big enough to compare against.
                HStack(alignment: .top, spacing: 14) {
                    Group {
                        if let img = entry.thumbnail { Image(uiImage: img).resizable().scaledToFill() } else { Color.white.opacity(0.08) }
                    }
                    .frame(width: 104, height: 145)
                    .clipShape(RoundedRectangle(cornerRadius: 10, style: .continuous))
                    .overlay(RoundedRectangle(cornerRadius: 10, style: .continuous).strokeBorder(Color.white.opacity(0.18)))
                    VStack(alignment: .leading, spacing: 8) {
                        MonoLabel(text: "Your scan")
                        Text(title).font(.display(24)).tracking(-0.6).lineLimit(3)
                        if !list.isEmpty {
                            Text("Tap the card that matches. Check the set symbol and the number in the bottom corner. Hold a card to see it bigger.")
                                .font(.geist(13)).foregroundStyle(Theme.muted).fixedSize(horizontal: false, vertical: true)
                        } else if let message = entry.error ?? entry.result?.message {
                            Text(message).font(.geist(14)).lineLimit(4)
                        }
                    }
                    Spacer(minLength: 0)
                }
                if !list.isEmpty {
                    // Two big cards a row, the best match first and marked, each with everything
                    // that tells look-alikes apart: set, number, rarity, printings and price.
                    LazyVGrid(columns: [GridItem(.flexible(), spacing: 12), GridItem(.flexible(), spacing: 12)], spacing: 12) {
                        ForEach(Array(list.enumerated()), id: \.offset) { i, c in
                            CandidateCard(candidate: c, best: i == 0 && list.count > 1) { model.pick(c, for: entry.id) }
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

/// One possible match, big: the card's picture, its name, set, number and rarity, the printings
/// it comes in, and its price. Tap to pick it; hold to see the picture large.
private struct CandidateCard: View {
    var candidate: ScanCandidate
    var best: Bool
    var onPick: () -> Void

    var body: some View {
        let p = candidate.product
        let shape = RoundedRectangle(cornerRadius: 18, style: .continuous)
        Button(action: onPick) {
            VStack(alignment: .leading, spacing: 6) {
                ProductImage(product: p, cornerRadius: 8, large: true)
                    // Shrunk to the size it shows at (the full picture is for the hold preview).
                    .imageMaxPixel(520)
                    .aspectRatio(0.716, contentMode: .fit)
                    .frame(maxWidth: .infinity)
                    .overlay(alignment: .topLeading) {
                        if best { SkewTag(text: "Best match", icon: "sparkles").padding(6) }
                    }
                    .padding(.bottom, 4)
                Text(p.name).font(.geist(14, .semibold)).lineLimit(2).fixedSize(horizontal: false, vertical: true)
                if let set = p.setName {
                    Text(set).font(.geist(12)).foregroundStyle(Theme.muted).lineLimit(2).fixedSize(horizontal: false, vertical: true)
                }
                // The details that tell look-alikes apart.
                let details = [p.number.map { "#\($0)" }, p.rarity].compactMap { $0 }
                if !details.isEmpty {
                    Text(details.joined(separator: " · ")).font(.geist(12, .medium)).monospacedDigit().lineLimit(2)
                }
                if candidate.printings.count > 1 {
                    Text(candidate.printings.joined(separator: " · ")).font(.geist(11)).foregroundStyle(Theme.muted).lineLimit(2)
                }
                Spacer(minLength: 0)
                Text(Format.money(candidate.market)).font(.display(20)).tracking(-0.5).monospacedDigit()
                    .padding(.top, 2)
            }
            .padding(10)
            .frame(maxWidth: .infinity, maxHeight: .infinity, alignment: .topLeading)
            .background(Color.white.opacity(best ? 0.1 : 0.07), in: shape)
            .overlay(shape.strokeBorder(best ? Theme.lime.opacity(0.7) : Color.white.opacity(0.1), lineWidth: best ? 1.5 : 1))
            .contentShape(shape)
        }
        .buttonStyle(.plain)
        .contextMenu {
            Button(action: onPick) { Label("This is the one", systemImage: "checkmark") }
        } preview: {
            ProductImage(product: p, cornerRadius: 14, large: true).frame(width: 300, height: 419)
        }
        .accessibilityLabel("\(p.name), \(p.subtitle), \(Format.money(candidate.market))")
    }
}
