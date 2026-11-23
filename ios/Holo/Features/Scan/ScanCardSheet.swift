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
    @State private var changing = false
    /// The full add sheet for this card (portfolio, grading, bought or pulled, shipping…).
    @State private var detailing = false

    private var entry: ScanModel.Entry? { model.entries.first { $0.id == id } }

    var body: some View {
        Group {
            if let entry, let product = entry.picked?.product {
                NavigationStack {
                    ProductDetailView(productId: product.id, extra: AnyView(ScanPanel(model: model, id: id, onWrong: { changing = true }, onDetails: { detailing = true }, onRemove: {
                        dismiss()
                        onRemove()
                    })))
                    .navigationDestination(for: String.self) { ProductDetailView(productId: $0) }
                    .toolbar { ToolbarItem(placement: .confirmationAction) { Button("Done") { dismiss() } } }
                    .environment(\.cardPageInSheet, true)
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
        // Wrong card?: the next best matches, or search (Change card).
        .sheet(isPresented: $changing) { ChangeCardSheet(model: model, id: id) }
        // Every detail, as when adding from search: kept with this card and added with the rest
        // of the scan (reopened just as it was left).
        .sheet(isPresented: $detailing) { ScanPurchaseSheet(model: model, id: id) }
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
    var onDetails: () -> Void
    var onRemove: () -> Void
    @Environment(CollectionStore.self) private var store

    private var entry: ScanModel.Entry? { model.entries.first { $0.id == id } }
    private var inDeal: Bool { model.onPick != nil }
    @FocusState private var paidFocused: Bool

    var body: some View {
        if let entry, let c = entry.picked {
            VStack(alignment: .leading, spacing: 18) {
                HStack(alignment: .center) {
                    MonoLabel(text: "This scan")
                    Spacer()
                    HStack(spacing: 6) {
                        if let g = entry.result?.read?.grade { Tag(text: "\(g.company) \(g.grade)", tint: Theme.lime) }
                        let owned = store.allHoldings.filter { $0.identity.productId == c.product.id }.reduce(0) { $0 + $1.quantity }
                        if owned > 0 { SkewTag(text: "Owned ×\(Int(owned))", icon: "checkmark") }
                    }
                }
                // Worth and what you paid, side by side in matching tiles.
                HStack(alignment: .top, spacing: 10) {
                    tile("Worth") {
                        Text(Format.money(entry.value)).font(.display(26)).tracking(-0.8).monospacedDigit().foregroundStyle(.white)
                            .lineLimit(1).minimumScaleFactor(0.7)
                            .contentTransition(.numericText())
                            .animation(.snappy(duration: 0.25), value: entry.value)
                        Text(entry.priceNote ?? "No price yet").font(.geist(11)).foregroundStyle(Theme.muted).lineLimit(2)
                            .fixedSize(horizontal: false, vertical: true)
                    }
                    if !inDeal {
                        tile("You paid") {
                            // The price shows in white when nothing is typed (it's what a blank means).
                            TextField("", text: Binding(get: { entry.paid }, set: { model.setPaid(id, $0) }),
                                      prompt: Text(Format.money(entry.value ?? 0)).foregroundColor(.white))
                                .keyboardType(.decimalPad)
                                .font(.display(26)).tracking(-0.8).monospacedDigit().foregroundStyle(.white)
                                .focused($paidFocused)
                            Text("Tap to change").font(.geist(11)).foregroundStyle(Theme.muted)
                        }
                        .contentShape(Rectangle())
                        .onTapGesture { paidFocused = true }
                    }
                }
                if !inDeal {
                    if let printings = c.product.printings.map(Editions.ordered), printings.count > 1 {
                        labelled("Printing") {
                            ChipPicker(options: printings.map { ($0, $0) },
                                       selection: Binding(get: { entry.printing ?? c.printing ?? printings[0] }, set: { model.setPrinting(id, $0) }),
                                       scrolls: true)
                        }
                    }
                    if !c.product.isSealed, !entry.isSlab {
                        labelled("Condition") {
                            ChipPicker(options: CardCondition.allCases.map { ($0.rawValue, $0.short) },
                                       selection: Binding(get: { entry.condition }, set: { model.setCondition(id, $0) }),
                                       fills: true)
                        }
                    }
                }
                if !inDeal {
                    // The same sheet as adding from search: portfolio, graded, condition, bought
                    // or pulled, price, shipping, tax, date and where, for this card alone.
                    if let d = entry.draft {
                        HStack(spacing: 8) {
                            Image(systemName: "checkmark.circle.fill").foregroundStyle(Theme.lime)
                            Text(ScanDraftSummary.text(d)).font(.geist(13, .medium)).foregroundStyle(.white).lineLimit(2)
                            Spacer(minLength: 4)
                            Button("Clear") { model.setDraft(id, nil) }.font(.geist(13, .semibold)).foregroundStyle(Theme.muted)
                        }
                    }
                    action("Edit purchase details", icon: "slider.horizontal.3", iconColor: Theme.lime, fill: Theme.lime.opacity(0.12), run: onDetails)
                }
                // Two equal ways out: search for the right card, or drop this scan.
                HStack(spacing: 10) {
                    action("Wrong card?", icon: "magnifyingglass", iconColor: .white, fill: Color.white.opacity(0.1), run: onWrong)
                    action("Remove", icon: "trash", iconColor: Theme.planPink, fill: Theme.planPink.opacity(0.14), run: onRemove)
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

    private func tile<Content: View>(_ label: String, @ViewBuilder content: () -> Content) -> some View {
        VStack(alignment: .leading, spacing: 6) {
            MonoLabel(text: label)
            content()
        }
        .padding(12)
        .frame(maxWidth: .infinity, minHeight: 104, alignment: .topLeading)
        .background(Color.white.opacity(0.06), in: RoundedRectangle(cornerRadius: 14, style: .continuous))
    }

    private func action(_ title: String, icon: String, iconColor: Color, fill: Color, run: @escaping () -> Void) -> some View {
        Button {
            Haptics.tap()
            run()
        } label: {
            HStack(spacing: 7) {
                Image(systemName: icon).font(.system(size: 13, weight: .semibold)).foregroundStyle(iconColor)
                Text(title).font(.geist(14, .semibold)).foregroundStyle(.white)
            }
            .frame(maxWidth: .infinity).frame(height: 44)
            .background(fill, in: Capsule())
            .contentShape(Capsule())
        }
        .buttonStyle(.plain)
    }
}

/// A scan with no card yet. Two layouts: close matches to pick from (a heading and a tip, then
/// the matches two a row), or nothing found (why, tips for the next photo, and Try again).
/// Your photo isn't shown: the matches are what to look at. Either way the ways out sit in a bar pinned to the bottom: Search and Remove.
private struct Unmatched: View {
    let model: ScanModel
    let entry: ScanModel.Entry
    var onWrong: () -> Void
    var onRemove: () -> Void
    @Environment(\.dismiss) private var dismiss

    private var candidates: [ScanCandidate] { Array((entry.result?.candidates ?? []).prefix(6)) }
    private var canRetry: Bool { entry.state == .failed || entry.result?.status == "retake" }
    private var message: String? { entry.error ?? entry.result?.message }

    var body: some View {
        let list = candidates
        ScrollView(showsIndicators: false) {
            VStack(spacing: 0) {
                closeRow
                if list.isEmpty { nothingFound } else { matches(list) }
            }
            .padding(.horizontal, 20)
            .padding(.bottom, 24)
        }
        .foregroundStyle(.white)
        .safeAreaInset(edge: .bottom, spacing: 0) { bottomBar }
    }

    /// Room under the grabber, and a close button you can see.
    private var closeRow: some View {
        HStack {
            Spacer()
            Button { Haptics.tap(); dismiss() } label: {
                Image(systemName: "xmark").font(.system(size: 14, weight: .semibold)).foregroundStyle(.white)
                    .frame(width: 34, height: 34)
                    .background(Circle().fill(Color.white.opacity(0.1)))
            }
            .buttonStyle(.plain)
            .accessibilityLabel("Close")
        }
        .padding(.top, 22)
    }

    // MARK: Close matches

    private func matches(_ list: [ScanCandidate]) -> some View {
        VStack(alignment: .leading, spacing: 22) {
            VStack(alignment: .leading, spacing: 6) {
                MonoLabel(text: "\(list.count) close match\(list.count == 1 ? "" : "es")")
                DisplayText(text: title, size: 30)
            }
            .frame(maxWidth: .infinity, alignment: .leading)
            Text("Match the set symbol and the number in the bottom corner. Hold a card to see it\u{00A0}bigger.")
                .font(.geist(14)).foregroundStyle(Theme.muted).fixedSize(horizontal: false, vertical: true)
                .padding(.top, -12)
            LazyVGrid(columns: [GridItem(.flexible(), spacing: 12), GridItem(.flexible(), spacing: 12)], spacing: 12) {
                ForEach(Array(list.enumerated()), id: \.offset) { _, c in
                    CandidateCard(candidate: c, best: false) { model.pick(c, for: entry.id) }
                }
            }
        }
        .padding(.top, 4)
    }

    // MARK: Nothing found

    private var nothingFound: some View {
        VStack(spacing: 0) {
            Image(systemName: "camera").font(.system(size: 30, weight: .semibold)).foregroundStyle(Theme.lime)
                .frame(width: 72, height: 72)
                .background(Circle().fill(Theme.lime.opacity(0.12)))
                .padding(.top, 24)
            DisplayText(text: title, size: 28, alignment: .center)
                .frame(maxWidth: .infinity)
                .padding(.top, 20)
            if let message {
                BalancedText(text: message, font: .geist(15), color: Theme.muted)
                    .frame(maxWidth: 300)
                    .padding(.top, 10)
            }
            // Tips for the next photo, when the scanner couldn't make it out.
            if canRetry {
                VStack(alignment: .leading, spacing: 10) {
                    tip("viewfinder", "Fill the frame with the card")
                    tip("sun.max", "Tilt away from glare and bright lights")
                    tip("hand.raised", "Hold still for a moment")
                }
                .frame(maxWidth: .infinity, alignment: .leading)
                .padding(16)
                .background(RoundedRectangle(cornerRadius: 18, style: .continuous).fill(Color.white.opacity(0.06)))
                .padding(.top, 24)
            }
        }
        .frame(maxWidth: .infinity)
    }

    private func tip(_ icon: String, _ text: String) -> some View {
        HStack(spacing: 12) {
            Image(systemName: icon).font(.system(size: 14, weight: .semibold)).foregroundStyle(Theme.lime).frame(width: 22)
            Text(text).font(.geist(14)).foregroundStyle(.white)
        }
    }

    // MARK: Pinned bar

    private var bottomBar: some View {
        VStack(spacing: 10) {
            if canRetry && candidates.isEmpty {
                Button { Haptics.tap(); model.retry(entry.id); dismiss() } label: {
                    Label("Try again", systemImage: "arrow.clockwise")
                }
                .buttonStyle(Button3D(kind: .lime, height: 52))
            }
            HStack(spacing: 10) {
                Button { Haptics.tap(); onWrong() } label: {
                    HStack(spacing: 8) {
                        Image(systemName: "magnifyingglass").font(.system(size: 15, weight: .semibold))
                        Text(candidates.isEmpty ? "Search for it" : "Not here? Search").font(.geist(15, .semibold))
                    }
                    .foregroundStyle(.white)
                    .frame(maxWidth: .infinity).frame(height: 52)
                    // Its own glass: whatever's behind the button blurs; nothing spans the bar.
                    .liquidGlass(in: Capsule())
                    .contentShape(Capsule())
                }
                .buttonStyle(.plain)
                Button { Haptics.remove(); onRemove() } label: {
                    HStack(spacing: 8) {
                        Image(systemName: "trash").font(.system(size: 15, weight: .semibold))
                        Text("Remove").font(.geist(15, .semibold))
                    }
                    .frame(maxWidth: .infinity).frame(height: 52)
                    .dangerStyle(Capsule())
                    .contentShape(Capsule())
                }
                .buttonStyle(.plain)
                .accessibilityLabel("Remove from this scan")
            }
        }
        .padding(.horizontal, 20)
        .padding(.top, 14)
        .padding(.bottom, 8)
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
            default: return candidates.isEmpty ? "No match found" : "Which one is it?"
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
                    .environment(\.quietPlaceholder, true)
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

/// "Change card": the card this scan matched, the scanner's next best matches to swap in with one
/// tap (picture, name, number and set, price), Search all cards, or keep it as it is. Opens from
/// the tray's Change card and the card page's Wrong card?.
struct ChangeCardSheet: View {
    let model: ScanModel
    let id: UUID
    @Environment(\.dismiss) private var dismiss
    @State private var searching = false

    private var entry: ScanModel.Entry? { model.entries.first { $0.id == id } }

    /// The other close matches, best first (the one picked now left out).
    private var others: [ScanCandidate] {
        guard let entry else { return [] }
        let picked = entry.picked?.product.id
        return Array((entry.result?.candidates ?? []).filter { $0.product.id != picked }.prefix(6))
    }

    var body: some View {
        VStack(spacing: 0) {
            Text("Change card").font(.display(26)).tracking(-0.7).foregroundStyle(.white)
                .padding(.top, 28).padding(.bottom, 18)
            Rectangle().fill(Color.white.opacity(0.08)).frame(height: 1)
            ScrollView(showsIndicators: false) {
                VStack(alignment: .leading, spacing: 0) {
                    if let p = entry?.picked?.product {
                        Text("Replacing: \(p.name)" + (p.number.map { " · #\($0)" } ?? ""))
                            .font(.geist(16, .semibold)).foregroundStyle(.white).lineLimit(2)
                            .padding(.top, 20)
                    }
                    if !others.isEmpty {
                        let condition = entry.flatMap { CardCondition(rawValue: $0.condition)?.short }
                        MonoLabel(text: "Next best matches" + (condition.map { " · \($0)" } ?? ""))
                            .padding(.top, 18).padding(.bottom, 6)
                        ForEach(Array(others.enumerated()), id: \.offset) { i, c in
                            if i > 0 { Rectangle().fill(Color.white.opacity(0.08)).frame(height: 1) }
                            row(c)
                        }
                    } else {
                        Text("No other close matches for this scan. Search for the right card.".noWidow)
                            .font(.geist(14)).foregroundStyle(Theme.muted).padding(.top, 14)
                    }
                }
                .padding(.horizontal, 20)
                .padding(.bottom, 16)
            }
            VStack(spacing: 12) {
                Button { Haptics.tap(); searching = true } label: {
                    Label("Search all cards", systemImage: "magnifyingglass")
                }
                .buttonStyle(Button3D(kind: .dark, height: 52))
                if let name = entry?.picked?.product.name {
                    Button { dismiss() } label: {
                        Text("Keep \(name)").font(.geist(15, .medium)).foregroundStyle(Theme.muted).underline().lineLimit(1)
                    }
                    .buttonStyle(.plain)
                }
            }
            .padding(.horizontal, 20).padding(.top, 8).padding(.bottom, 16)
        }
        .foregroundStyle(.white)
        .presentationDetents([.fraction(0.75), .fraction(0.93)])
        .presentationDragIndicator(.visible)
        .glassSheet()
        .sheet(isPresented: $searching) {
            SearchScreen(mode: .add, onPick: { hit in
                model.replace(id, with: hit)
                dismiss()
            })
        }
    }

    private func row(_ c: ScanCandidate) -> some View {
        Button {
            Haptics.tap()
            // In a deal a scan is handed over once, so swapping goes through replace there.
            if model.onPick != nil {
                model.replace(id, with: SearchHit(product: c.product, printing: c.printing, market: c.market))
            } else {
                model.pick(c, for: id)
            }
            dismiss()
        } label: {
            HStack(spacing: 14) {
                ProductImage(product: c.product, cornerRadius: 5).frame(width: 44, height: 62)
                VStack(alignment: .leading, spacing: 3) {
                    Text(c.product.name).font(.geist(16, .semibold)).foregroundStyle(.white).lineLimit(2)
                    Text([c.product.number.map { "#\($0)" }, c.product.setName].compactMap { $0 }.joined(separator: " · "))
                        .font(.geist(13)).foregroundStyle(Theme.muted).lineLimit(1)
                }
                Spacer(minLength: 8)
                Text(Format.money(c.market)).font(.geist(17, .semibold)).monospacedDigit().foregroundStyle(.white)
            }
            .padding(.vertical, 12)
            .contentShape(Rectangle())
        }
        .buttonStyle(.plain)
    }
}

/// A scanned card's own details in a line: graded or condition, paid or pulled, where and when.
enum ScanDraftSummary {
    static func text(_ d: ScanDraft) -> String {
        let p = d.purchase
        var parts: [String] = []
        if let co = p.gradeCompany, let g = p.grade { parts.append("\(co) \(d.pristine ? "Pristine 10" : g)") } else if p.condition != "Sealed" { parts.append(p.condition) }
        parts.append(d.pulled ? "Pulled" : "Paid \(Format.money(p.unitPrice))")
        let extra = p.shipping + p.tax + p.fees
        if extra > 0 { parts.append("+\(Format.money(extra))") }
        if let s = p.source, !s.isEmpty, s != "ios", s != Txn.pulledSource { parts.append(s) }
        if let day = Format.isoDay.date(from: p.date), !Calendar.current.isDateInToday(day) { parts.append(day.formatted(.dateTime.month(.abbreviated).day())) }
        return parts.joined(separator: " · ")
    }
}

/// A scanned card's purchase details (what you paid, bought or pulled, graded, shipping, where,
/// when, portfolio): the add-from-search sheet, started from the scan and the scan's defaults,
/// and kept with the card until the scan is added.
struct ScanPurchaseSheet: View {
    let model: ScanModel
    let id: UUID

    var body: some View {
        if let entry = model.entries.first(where: { $0.id == id }), let c = entry.picked {
            AddPurchaseSheet(
                hit: SearchHit(product: c.product, printing: entry.printing ?? c.printing, market: entry.value ?? c.market),
                prefill: entry.draft?.prefill ?? AddPrefill(printing: entry.printing ?? c.printing, condition: entry.condition,
                                                            gradeCompany: entry.isSlab ? entry.result?.read?.grade?.company : nil,
                                                            grade: entry.isSlab ? entry.result?.read?.grade?.grade : nil,
                                                            price: entry.paid, pulled: model.defaultPulled),
                onCollect: { model.setDraft(id, $0) }
            )
        }
    }
}
