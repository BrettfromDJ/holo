import SwiftUI

/// Your slabs, cards at the grader, and what's worth sending in, like the website's Grading page.
struct GradingView: View {
    @Environment(CollectionStore.self) private var store
    @Environment(GradingStore.self) private var grading
    @State private var summaries: [String: [EbaySummary]] = [:]
    @State private var loadedSummaries = false
    @State private var showAll = false
    @State private var editingCosts = false
    @State private var sending: HoldingView?
    @State private var returning: GradingStore.Submission?

    private static let shown = 8
    private var today: String { Format.day() }

    private var slabs: [HoldingView] {
        store.holdings.filter(\.identity.isGraded).sorted { ($0.value ?? 0) > ($1.value ?? 0) }
    }

    /// Raw singles worth more than $15 with upside as a PSA 10 after costs, best first.
    private var candidates: [(HoldingView, Grading.Outlook)] {
        store.holdings.compactMap { h -> (HoldingView, Grading.Outlook)? in
            guard !h.identity.isGraded, h.product?.isSealed == false, let price = h.price, price >= Grading.minRaw else { return nil }
            let summary = loadedSummaries ? summaryFor(summaries[h.identity.productId], printing: h.identity.printing) ?? EbaySummary(printing: nil, ungraded: EbayStats(count: 0), graded: [:], asOf: "") : nil
            let o = Grading.outlook(productId: h.identity.productId, raw: price, costs: grading.costs, summary: summary)
            return o.upside10 > 0 ? (h, o) : nil
        }
        .sorted { $0.1.score > $1.1.score }
    }

    var body: some View {
        let slabs = self.slabs
        let candidates = self.candidates
        ScrollView {
            VStack(alignment: .leading, spacing: 20) {
                PageHeader(title: "Grading", subtitle: "Your slabs, cards at the grader, and what's worth sending in")
                metrics(slabs)
                atGrader
                worthGrading(candidates)
                yourSlabs(slabs)
            }
            .padding(.horizontal, 16)
            .padding(.bottom, 120)
        }
        .background(Theme.background)
        .navigationBarTitleDisplayMode(.inline)
        .pageTitle("Grading")
        .task {
            await grading.load(userId: store.demo == nil ? store.userId : nil)
            let ids = Array(Set(store.holdings.filter { $0.product?.isSealed == false && $0.identity.productId.hasPrefix("tcgapi:") }.map(\.identity.productId))).sorted()
            if !ids.isEmpty, !loadedSummaries, let found = try? await Backend.shared.api.ebaySummaries(ids) {
                summaries = found
                loadedSummaries = true
            }
        }
        .sheet(isPresented: $editingCosts) { CostsSheet() }
        .sheet(item: $sending) { SendSheet(holding: $0) }
        .sheet(item: $returning) { ReturnSheet(submission: $0) }
    }

    // MARK: Numbers

    private func metrics(_ slabs: [HoldingView]) -> some View {
        let value = slabs.reduce(0) { $0 + ($1.value ?? 0) }
        let rawEquivalent = slabs.reduce(0.0) { sum, h in
            guard let raw = store.marketPrice(h.identity.productId, printing: h.identity.printing)?.market, h.value != nil else { return sum }
            return sum + raw * h.quantity
        }
        let stale = slabs.filter { h in
            guard h.isManual, let m = store.manualValue(h.identity) else { return false }
            return Timeline.daysBetween(m.date, today) > 60
        }.count
        let sentCount = grading.sent.reduce(0) { $0 + $1.quantity }
        let premium = value - rawEquivalent
        let items: [(String, String, Color, String, Color)] = [
            ("Slabs", "\(Int(slabs.reduce(0) { $0 + $1.quantity }))", .white, slabs.isEmpty ? "None yet" : Format.money(value), Theme.lime),
            ("Grading premium", rawEquivalent > 0 ? Format.signedMoney(premium) : "—", rawEquivalent > 0 ? Theme.tone(premium) : .white, rawEquivalent > 0 ? "vs \(Format.money(rawEquivalent)) raw" : "Slab value over raw", Theme.planBlue),
            ("At the grader", "\(Int(sentCount))", .white, grading.sent.isEmpty ? "Nothing out" : "\(grading.sent.count) submission\(grading.sent.count == 1 ? "" : "s")", Theme.planPink),
            ("Values to refresh", "\(stale)", .white, "Over 60 days old", Theme.planBlue),
        ]
        return LazyVGrid(columns: [GridItem(.flexible(), spacing: 12), GridItem(.flexible(), spacing: 12)], spacing: 12) {
            ForEach(items, id: \.0) { label, value, tint, sub, glow in
                VStack(alignment: .leading, spacing: 0) {
                    Text(label.uppercased()).font(.display(14)).tracking(0.3).foregroundStyle(.white.opacity(0.85)).lineLimit(1).minimumScaleFactor(0.8).displayTrim(14)
                    Text(value).font(.display(28)).monospacedDigit().foregroundStyle(tint).lineLimit(1).minimumScaleFactor(0.6).displayTrim(28).padding(.top, 14)
                    Text(sub).font(.geist(12)).foregroundStyle(Theme.muted).lineLimit(1).padding(.top, 8)
                }
                .frame(maxWidth: .infinity, alignment: .leading)
                .tinted(glow, radius: 20, border: false)
            }
        }
    }

    // MARK: At the grader

    private var atGrader: some View {
        VStack(alignment: .leading, spacing: 12) {
            heading("At the grader", "Cards stay raw until they come back")
            if grading.sent.isEmpty {
                Label("Nothing out for grading", systemImage: "paperplane")
                    .font(.geist(13)).foregroundStyle(Theme.muted)
                    .padding(.horizontal, 14).padding(.vertical, 12)
                    .frame(maxWidth: .infinity, alignment: .leading)
                    .background(Theme.surface2.opacity(0.6), in: RoundedRectangle(cornerRadius: 14, style: .continuous))
            }
            ForEach(grading.sent) { s in
                HStack(spacing: 12) {
                    NavigationLink(value: s.productId) {
                        HStack(spacing: 12) {
                            HoldingArt(product: store.products[s.productId], cornerRadius: 6, caption: false).frame(width: 33, height: 46)
                            VStack(alignment: .leading, spacing: 2) {
                                (Text(s.quantity > 1 ? "\(Int(s.quantity)) × " : "").foregroundColor(Theme.muted) + Text(store.products[s.productId]?.name ?? "Card"))
                                    .font(.geist(14, .medium)).lineLimit(1)
                                Text(sentLine(s)).font(.geist(12)).foregroundStyle(Theme.muted).lineLimit(1)
                            }
                            Spacer(minLength: 4)
                        }
                    }
                    .buttonStyle(.plain)
                    Button("It's back") { returning = s }
                        .buttonStyle(Button3D(kind: .dark, fullWidth: false, height: 34))
                    Menu {
                        Button("Remove submission", role: .destructive) { grading.cancel(s.id) }
                    } label: {
                        Image(systemName: "ellipsis").foregroundStyle(Theme.muted).frame(width: 28, height: 28)
                    }
                }
                .padding(.vertical, 4)
            }
            if !grading.returned.isEmpty {
                Rectangle().fill(Theme.border).frame(height: 1).padding(.top, 4)
                MonoLabel(text: "Recently returned", color: Theme.subtle)
                ForEach(grading.returned) { s in
                    HStack(spacing: 8) {
                        Tag(text: "\(s.company) \(s.grade ?? "?")", tint: Theme.lime)
                        Text(store.products[s.productId]?.name ?? "Card").font(.geist(13)).lineLimit(1)
                        Spacer(minLength: 4)
                        Text(s.returnedOn.flatMap { Format.isoDay.date(from: $0)?.formatted(date: .abbreviated, time: .omitted) } ?? "").font(.geist(12)).foregroundStyle(Theme.subtle)
                    }
                }
            }
        }
        .surface(radius: 22, padding: 18)
    }

    private func sentLine(_ s: GradingStore.Submission) -> String {
        let days = Timeline.daysBetween(s.sentOn, today)
        let date = Format.isoDay.date(from: s.sentOn)?.formatted(date: .abbreviated, time: .omitted) ?? s.sentOn
        return "\(s.company) \(s.service) · sent \(date)\(days > 0 && days < .max ? " · \(days) day\(days == 1 ? "" : "s") ago" : "")"
    }

    // MARK: Worth grading

    private func worthGrading(_ candidates: [(HoldingView, Grading.Outlook)]) -> some View {
        let away = grading.atGrader
        return VStack(alignment: .leading, spacing: 12) {
            HStack(alignment: .top) {
                heading("Worth grading", "Most upside as a PSA 10, after \(Format.money(grading.costs.fee + grading.costs.shipping)) in costs")
                Spacer(minLength: 8)
                Button("Costs") { editingCosts = true }.font(.geist(14, .medium)).foregroundStyle(Theme.muted)
            }
            if candidates.isEmpty {
                Text("No raw singles worth more than \(Format.money(Grading.minRaw)) with upside after grading costs.")
                    .font(.geist(13)).foregroundStyle(Theme.muted).padding(.vertical, 12)
            }
            ForEach(showAll ? candidates : Array(candidates.prefix(Self.shown)), id: \.0.id) { h, o in
                let est = o.source == .estimate ? "≈" : ""
                HStack(spacing: 12) {
                    NavigationLink(value: h.identity.productId) {
                        HStack(spacing: 12) {
                            HoldingArt(product: h.product, identity: h.identity, cornerRadius: 6, caption: false).frame(width: 33, height: 46)
                            VStack(alignment: .leading, spacing: 2) {
                                Text(h.product?.name ?? "Card").font(.geist(14, .medium)).lineLimit(1)
                                Text("Raw \(Format.money(o.raw)) · PSA 10 \(est)\(Format.money(o.psa10)) · PSA 9 \(est)\(Format.money(o.psa9))")
                                    .font(.geist(12)).monospacedDigit().foregroundStyle(Theme.muted).lineLimit(1).minimumScaleFactor(0.85)
                                Text("PSA 10s: \(Grading.liquidity(o.psa10Sales).lowercased())\(o.source == .sales ? " · eBay" : " · estimated, few recent sales")")
                                    .font(.geist(11)).foregroundStyle(o.psa10Sales < 12 ? Theme.subtle : Theme.muted).lineLimit(1)
                            }
                            Spacer(minLength: 4)
                            VStack(alignment: .trailing, spacing: 2) {
                                Text(Format.signedMoney(o.upside10)).font(.geist(14, .semibold)).monospacedDigit().foregroundStyle(Theme.up)
                                (Text("at a 9: ").foregroundColor(Theme.muted) + Text(Format.signedMoney(o.upside9)).foregroundColor(Theme.tone(o.upside9)))
                                    .font(.geist(11)).monospacedDigit()
                            }
                        }
                    }
                    .buttonStyle(.plain)
                    if (away[h.identity.key] ?? 0) >= h.quantity {
                        Text("Sent").font(.geist(11)).foregroundStyle(Theme.subtle).frame(width: 32)
                    } else {
                        Button { sending = h } label: {
                            Image(systemName: "paperplane").font(.system(size: 14, weight: .semibold)).foregroundStyle(Theme.muted).frame(width: 32, height: 32)
                        }
                        .accessibilityLabel("Send for grading")
                    }
                }
                .padding(.vertical, 4)
            }
            if candidates.count > Self.shown {
                Button(showAll ? "Show fewer" : "Show all \(candidates.count)") { showAll.toggle() }
                    .font(.geist(13, .medium)).foregroundStyle(Theme.muted)
            }
        }
        .surface(radius: 22, padding: 18)
    }

    // MARK: Slabs

    private func yourSlabs(_ slabs: [HoldingView]) -> some View {
        VStack(alignment: .leading, spacing: 14) {
            heading("Your slabs", slabs.isEmpty ? "No graded cards yet. Add one with Graded switched on, or mark a submission as returned." : "Graded cards, by value")
            LazyVGrid(columns: [GridItem(.flexible(), spacing: 14), GridItem(.flexible(), spacing: 14)], spacing: 24) {
                ForEach(slabs) { h in
                    NavigationLink(value: h.identity.productId) { slabTile(h) }.buttonStyle(.plain)
                }
            }
        }
    }

    private func slabTile(_ h: HoldingView) -> some View {
        let raw = store.marketPrice(h.identity.productId, printing: h.identity.printing)?.market
        let manualDate = h.isManual ? store.manualValue(h.identity)?.date : nil
        let staleDays = manualDate.map { Timeline.daysBetween($0, today) } ?? 0
        return VStack(alignment: .leading, spacing: 3) {
            HoldingArt(product: h.product, identity: h.identity, caption: false)
                .aspectRatio(4 / 5, contentMode: .fit)
                .frame(maxWidth: .infinity)
                .padding(.bottom, 9)
            Text(h.product?.name ?? "Card").font(.geist(13, .medium)).lineLimit(2)
            HStack(alignment: .firstTextBaseline, spacing: 6) {
                if h.price == nil {
                    Text("No value").font(.geist(14, .semibold)).foregroundStyle(Theme.subtle)
                } else {
                    Text(Format.money(h.value)).font(.geist(14, .semibold)).monospacedDigit()
                }
                if let raw, raw > 0, let p = h.price {
                    Text(String(format: "%.1f× raw", p / raw)).font(.mono(11)).foregroundStyle(Theme.muted)
                }
            }
            Text(h.isManual ? (staleDays > 60 ? "Your value · \(staleDays) days old" : "Your value") : h.price == nil ? "No recent eBay sales · set your value" : "eBay sold median")
                .font(.geist(11)).foregroundStyle(staleDays > 60 ? .white.opacity(0.8) : Theme.subtle).lineLimit(1)
        }
    }

    private func heading(_ title: String, _ sub: String) -> some View {
        VStack(alignment: .leading, spacing: 4) {
            Text(title).font(.geist(17, .semibold))
            Text(sub).font(.geist(13)).foregroundStyle(Theme.muted)
        }
    }
}

/// The fee and shipping assumed when weighing whether to grade.
private struct CostsSheet: View {
    @Environment(GradingStore.self) private var grading
    @Environment(\.dismiss) private var dismiss
    @State private var fee = ""
    @State private var shipping = ""

    var body: some View {
        NavigationStack {
            Form {
                Section {
                    MoneyField(title: "Fee per card", text: $fee)
                    MoneyField(title: "Shipping per card", text: $shipping)
                } footer: {
                    Text("Used to weigh which cards are worth grading, and as the default when you send one in. Shipping both ways, with insurance.")
                }
            }
            .scrollContentBackground(.hidden)
            .background(Theme.background)
            .navigationTitle("Grading costs")
            .navigationBarTitleDisplayMode(.inline)
            .toolbar {
                ToolbarItem(placement: .cancellationAction) { Button("Cancel") { dismiss() } }
                ToolbarItem(placement: .confirmationAction) {
                    Button("Save") {
                        if let f = MoneyField.value(fee), let s = MoneyField.value(shipping) { grading.setCosts(.init(fee: f, shipping: s)) }
                        dismiss()
                    }
                    .disabled(MoneyField.value(fee) == nil || MoneyField.value(shipping) == nil)
                }
            }
            .onAppear {
                fee = String(format: "%.2f", grading.costs.fee)
                shipping = String(format: "%.2f", grading.costs.shipping)
            }
        }
        .presentationDetents([.medium])
    }
}

/// Record raw copies as sent off for grading.
private struct SendSheet: View {
    var holding: HoldingView
    @Environment(GradingStore.self) private var grading
    @Environment(\.dismiss) private var dismiss
    @State private var company = "PSA"
    @State private var service = "Value"
    @State private var quantity = 1
    @State private var fee = ""
    @State private var shipping = ""
    @State private var date = Date()

    private static let companies = ["PSA", "BGS", "CGC", "SGC", "TAG"]
    private static let services = ["Value", "Regular", "Express", "Super Express"]

    var body: some View {
        NavigationStack {
            Form {
                Section {
                    Picker("Grader", selection: $company) { ForEach(Self.companies, id: \.self) { Text($0) } }
                    Picker("Service", selection: $service) { ForEach(Self.services, id: \.self) { Text($0) } }
                    Stepper("Quantity: \(quantity) of \(Int(holding.quantity))", value: $quantity, in: 1...max(1, Int(holding.quantity)))
                    MoneyField(title: "Fee per card", text: $fee)
                    MoneyField(title: "Shipping per card", text: $shipping)
                    DatePicker("Sent", selection: $date, in: ...Date(), displayedComponents: .date)
                } header: {
                    Text(holding.product?.name ?? "Card")
                } footer: {
                    Text("It stays in your collection raw until it comes back.")
                }
            }
            .scrollContentBackground(.hidden)
            .background(Theme.background)
            .navigationTitle("Send for grading")
            .navigationBarTitleDisplayMode(.inline)
            .toolbar {
                ToolbarItem(placement: .cancellationAction) { Button("Cancel") { dismiss() } }
                ToolbarItem(placement: .confirmationAction) {
                    Button("Mark as sent") {
                        grading.send(holding, company: company, service: service, quantity: Double(quantity),
                                     fee: MoneyField.value(fee) ?? grading.costs.fee, shipping: MoneyField.value(shipping) ?? grading.costs.shipping, date: Format.day(date))
                        UINotificationFeedbackGenerator().notificationOccurred(.success)
                        dismiss()
                    }
                }
            }
            .onAppear {
                fee = String(format: "%.2f", grading.costs.fee)
                shipping = String(format: "%.2f", grading.costs.shipping)
            }
        }
    }
}

/// A submission came back: pick the grade and it moves into a slab.
private struct ReturnSheet: View {
    var submission: GradingStore.Submission
    @Environment(GradingStore.self) private var grading
    @Environment(CollectionStore.self) private var store
    @Environment(\.dismiss) private var dismiss
    @State private var grade = "10"
    @State private var date = Date()
    @State private var saving = false
    @State private var error: String?

    var body: some View {
        NavigationStack {
            Form {
                Section {
                    Picker("\(submission.company) grade", selection: $grade) {
                        ForEach(WorthCalc.grades(for: submission.company).reversed(), id: \.self) { Text($0) }
                    }
                    DatePicker("Returned", selection: $date, in: ...Date(), displayedComponents: .date)
                } header: {
                    Text(store.products[submission.productId]?.name ?? "Card")
                } footer: {
                    Text("The raw copies move into a \(submission.company) slab at what they cost you, plus the grading fee and shipping.")
                }
                if let error { Section { Text(error).foregroundStyle(Theme.down) } }
            }
            .scrollContentBackground(.hidden)
            .background(Theme.background)
            .navigationTitle("It's back")
            .navigationBarTitleDisplayMode(.inline)
            .toolbar {
                ToolbarItem(placement: .cancellationAction) { Button("Cancel") { dismiss() } }
                ToolbarItem(placement: .confirmationAction) {
                    Button(saving ? "Saving…" : "Save") { Task { await save() } }.disabled(saving)
                }
            }
        }
    }

    private func save() async {
        saving = true
        defer { saving = false }
        do {
            try await grading.complete(submission, grade: grade, date: Format.day(date), store: store)
            UINotificationFeedbackGenerator().notificationOccurred(.success)
            dismiss()
        } catch {
            self.error = error.localizedDescription
        }
    }
}
