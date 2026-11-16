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
    /// The slab being unboxed over the page (after "It's back", or a returned slab's first look).
    @State private var unboxing: Unboxing?

    struct Unboxing: Identifiable, Equatable {
        var id: String
        var productId: String
        var company: String
        var grade: String
        /// Wait before playing, e.g. while the return sheet slides down.
        var delay: Double
    }

    /// Returned slabs already unboxed this session (so a returned slab plays once per launch).
    private static var unboxed: Set<String> = []

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
            VStack(alignment: .leading, spacing: 36) {
                heroTop(slabs)
                // What's out at the grader first when there is any; what to send next; then your slabs.
                if !grading.sent.isEmpty { atGrader.reveal() }
                worthGrading(candidates).reveal()
                yourSlabs(slabs).reveal()
                if grading.sent.isEmpty { atGrader.reveal() }
            }
            .padding(.horizontal, 16)
            .padding(.bottom, 120)
        }
        .background(Theme.background)
        .replaysAnimations()
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
        // The first look this session at a slab that came back: unbox the newest one.
        .onChange(of: grading.returned.map(\.id), initial: true) { _, _ in unboxNewestReturned() }
        .sheet(isPresented: $editingCosts) { CostsSheet() }
        .sheet(item: $sending) { SendSheet(holding: $0) }
        .sheet(item: $returning) { s in
            ReturnSheet(submission: s, onReturned: { grade in
                Self.unboxed.insert(s.id)
                unboxing = Unboxing(id: s.id, productId: s.productId, company: s.company, grade: grade, delay: 0.45)
            })
        }
        .overlay {
            if let u = unboxing {
                SlabUnboxing(product: store.products[u.productId], company: u.company, grade: u.grade, delay: u.delay) {
                    withAnimation(.easeOut(duration: 0.2)) { unboxing = nil }
                }
                .id(u.id)
                .transition(.opacity)
            }
        }
    }

    /// Unbox the newest returned slab not yet seen this session, and count the rest as seen.
    private func unboxNewestReturned() {
        let fresh = grading.returned.filter { !Self.unboxed.contains($0.id) }
        guard !fresh.isEmpty else { return }
        for s in fresh { Self.unboxed.insert(s.id) }
        guard unboxing == nil, returning == nil, let s = fresh.first, let g = s.grade else { return }
        unboxing = Unboxing(id: s.id, productId: s.productId, company: s.company, grade: g, delay: 0.5)
    }

    // MARK: Numbers

    private func heroTop(_ slabs: [HoldingView]) -> some View {
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
        let count = Int(slabs.reduce(0) { $0 + $1.quantity })
        return SlabFanHero(slabs: slabs, value: value) {
            HStack(spacing: 8) {
                Text("\(count) slab\(count == 1 ? "" : "s")").font(.geist(13, .semibold)).monospacedDigit()
                    .foregroundStyle(Theme.ink)
                    .padding(.horizontal, 8).padding(.vertical, 3)
                    .background(Theme.lime, in: RoundedRectangle(cornerRadius: 6))
                if rawEquivalent > 0 {
                    Text(String(format: "%.1f× what they're worth raw", value / rawEquivalent)).font(.geist(13)).foregroundStyle(Theme.muted)
                }
            }
        } below: {
            // Only numbers that say something: no "0 at grader" or "0 to refresh".
            HStack(spacing: 8) {
                GlassStat(label: "Premium", value: rawEquivalent > 0 ? Format.signedMoney(premium) : "—", tint: rawEquivalent > 0 ? Theme.tone(premium) : .white)
                GlassStat(label: "Raw, they'd be", value: rawEquivalent > 0 ? Format.money(rawEquivalent) : "—")
                if sentCount > 0 {
                    GlassStat(label: "At grader", value: "\(Int(sentCount))")
                } else if stale > 0 {
                    GlassStat(label: "To refresh", value: "\(stale)")
                }
            }
        }
    }

    // MARK: At the grader

    private var atGrader: some View {
        VStack(alignment: .leading, spacing: 12) {
            MoreHeading(title: "At the grader", subtitle: "Cards stay raw until they come back")
            if grading.sent.isEmpty {
                Label("Nothing out for grading", systemImage: "paperplane")
                    .font(.geist(13)).foregroundStyle(Theme.muted)
                    .padding(.horizontal, 14).padding(.vertical, 12)
                    .frame(maxWidth: .infinity, alignment: .leading)
                    .background(Theme.surface2.opacity(0.6), in: RoundedRectangle(cornerRadius: 14, style: .continuous))
            }
            ForEach(grading.sent) { s in
                HStack(spacing: 12) {
                    CardLink(productId: s.productId) {
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
                        Image(systemName: "ellipsis").foregroundStyle(Theme.muted).frame(width: 44, height: 44).contentShape(Rectangle())
                    }
                }
                .padding(.vertical, 4)
            }
            if !grading.returned.isEmpty {
                Rectangle().fill(Theme.border).frame(height: 1).padding(.top, 4)
                MonoLabel(text: "Recently returned", color: Theme.subtle)
                ForEach(grading.returned) { s in
                    // Tap one to unbox it again.
                    Button {
                        if let g = s.grade { unboxing = Unboxing(id: s.id, productId: s.productId, company: s.company, grade: g, delay: 0) }
                    } label: {
                        HStack(spacing: 8) {
                            Tag(text: "\(s.company) \(s.grade ?? "?")", tint: Theme.lime)
                            Text(store.products[s.productId]?.name ?? "Card").font(.geist(13)).lineLimit(1)
                            Spacer(minLength: 4)
                            Text(s.returnedOn.flatMap { Format.isoDay.date(from: $0)?.formatted(date: .abbreviated, time: .omitted) } ?? "").font(.geist(12)).foregroundStyle(Theme.subtle)
                        }
                        .contentShape(Rectangle())
                    }
                    .buttonStyle(.plain)
                }
            }
        }
        .surface(radius: 16, padding: 16)
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
                MoreHeading(title: "Worth grading", subtitle: "Your raw cards that would make the most if graded a PSA 10, after \(Format.money(grading.costs.fee + grading.costs.shipping)) for grading and shipping. The smaller figure is what you'd make at a 9.")
                Spacer(minLength: 8)
                Button("Costs") { editingCosts = true }.buttonStyle(Button3D(kind: .dark, fullWidth: false, height: 34))
            }
            if candidates.isEmpty {
                Text("No raw singles worth more than \(Format.money(Grading.minRaw)) with upside after grading\u{00A0}costs.")
                    .font(.geist(13)).foregroundStyle(Theme.muted).padding(.vertical, 12)
            }
            // Rows touch, divided by a hairline, so the spacing above and below each line matches.
            let rows = showAll ? candidates : Array(candidates.prefix(Self.shown))
            let firstId = rows.first?.0.id
            VStack(spacing: 0) {
            ForEach(rows, id: \.0.id) { h, o in
                let est = o.source == .estimate ? "≈" : ""
                let sent = (away[h.identity.key] ?? 0) >= h.quantity
                // One balanced row: picture | name, prices, tag | upside and Send, top-aligned.
                HStack(alignment: .top, spacing: 12) {
                    CardLink(productId: h.identity.productId, identity: h.identity) {
                        HStack(alignment: .top, spacing: 12) {
                            HoldingArt(product: h.product, identity: h.identity, cornerRadius: 6, caption: false).frame(width: 44, height: 62)
                            VStack(alignment: .leading, spacing: 5) {
                                Text(h.product?.name ?? "Card").font(.geist(14, .medium)).foregroundStyle(.white)
                                    .lineLimit(2).fixedSize(horizontal: false, vertical: true)
                                Text("Raw \(Format.money(o.raw)) → PSA 10 \(est)\(Format.money(o.psa10))")
                                    .font(.geist(12)).monospacedDigit().foregroundStyle(Theme.muted).lineLimit(1).minimumScaleFactor(0.8)
                                Tag(text: o.source == .sales ? "10s \(Grading.liquidity(o.psa10Sales).lowercased())" : "Estimate",
                                    tint: o.psa10Sales < 12 ? Theme.muted : Theme.lime)
                            }
                            Spacer(minLength: 0)
                        }
                        .contentShape(Rectangle())
                    }
                    .buttonStyle(.plain)
                    VStack(alignment: .trailing, spacing: 6) {
                        Text(Format.signedMoney(o.upside10)).font(.geist(15, .semibold)).monospacedDigit().foregroundStyle(Theme.up)
                        (Text("at a 9 ").foregroundColor(Theme.muted) + Text(Format.signedMoney(o.upside9)).foregroundColor(Theme.tone(o.upside9)))
                            .font(.geist(11)).monospacedDigit()
                        if sent {
                            Text("Sent").font(.geist(12, .medium)).foregroundStyle(Theme.subtle).frame(height: 30)
                        } else {
                            Button { Haptics.tap(); sending = h } label: {
                                Text("Send").font(.geist(13, .semibold)).foregroundStyle(.white)
                                    .padding(.horizontal, 14).frame(height: 30)
                                    .background(Capsule().fill(Color.white.opacity(0.1)))
                                    .contentShape(Capsule())
                            }
                            .buttonStyle(.plain)
                            .accessibilityLabel("Send for grading")
                        }
                    }
                    .fixedSize()
                }
                .padding(.vertical, 14)
                .overlay(alignment: .top) {
                    // A divider between rows (not above the first).
                    if h.id != firstId {
                        Rectangle().fill(Color.white.opacity(0.08)).frame(height: 1)
                    }
                }
            }
            }
            if candidates.count > Self.shown {
                Button(showAll ? "Show fewer" : "Show all \(candidates.count)") { showAll.toggle() }
                    .font(.geist(13, .medium)).foregroundStyle(Theme.muted)
            }
        }
        .surface(radius: 16, padding: 16)
    }

    // MARK: Slabs

    private func yourSlabs(_ slabs: [HoldingView]) -> some View {
        VStack(alignment: .leading, spacing: 14) {
            MoreHeading(title: "Your slabs", subtitle: slabs.isEmpty ? "No graded cards yet. Add one with Graded switched on, or mark a submission as returned." : "Graded cards, by value")
            LazyVGrid(columns: [GridItem(.flexible(), spacing: 14), GridItem(.flexible(), spacing: 14)], spacing: 24) {
                ForEach(Array(slabs.enumerated()), id: \.element.id) { i, h in
                    CardLink(productId: h.identity.productId, identity: h.identity) { slabTile(h) }.buttonStyle(.plain)
                        .popIn(delay: Double(min(i, 6)) * 0.07)
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
struct CostsSheet: View {
    @Environment(GradingStore.self) private var grading
    @Environment(\.dismiss) private var dismiss
    @State private var fee = ""
    @State private var shipping = ""

    var body: some View { sheetBody.glassSheet() }

    @ViewBuilder private var sheetBody: some View {
        NavigationStack {
            GlassForm {
                Section {
                    MoneyField(title: "Fee per card", text: $fee)
                    MoneyField(title: "Shipping per card", text: $shipping)
                } footer: {
                    Text("Used to weigh which cards are worth grading, and as the default when you send one in. Shipping both ways, with\u{00A0}insurance.")
                }
            }
            .scrollContentBackground(.hidden)
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
struct SendSheet: View {
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

    var body: some View { sheetBody.presentationDetents([.fraction(0.93)]).glassSheet() }

    @ViewBuilder private var sheetBody: some View {
        NavigationStack {
            GlassForm {
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
                    Text("It stays in your collection raw until it comes\u{00A0}back.")
                }
            }
            .scrollContentBackground(.hidden)
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
    /// Called with the grade once it's saved (the page then unboxes the slab).
    var onReturned: (String) -> Void = { _ in }
    @Environment(GradingStore.self) private var grading
    @Environment(CollectionStore.self) private var store
    @Environment(GroupsStore.self) private var groups
    @Environment(\.dismiss) private var dismiss
    @State private var grade = "10"
    @State private var date = Date()
    @State private var saving = false
    @State private var error: String?

    var body: some View { sheetBody.presentationDetents([.fraction(0.93)]).glassSheet() }

    @ViewBuilder private var sheetBody: some View {
        NavigationStack {
            GlassForm {
                Section {
                    Picker("\(submission.company) grade", selection: $grade) {
                        ForEach(WorthCalc.grades(for: submission.company).reversed(), id: \.self) { Text($0) }
                    }
                    DatePicker("Returned", selection: $date, in: ...Date(), displayedComponents: .date)
                } header: {
                    Text(store.products[submission.productId]?.name ?? "Card")
                } footer: {
                    Text("The raw copies move into a \(submission.company) slab at what they cost you, plus the grading fee and\u{00A0}shipping.")
                }
                if let error { Section { Text(error).foregroundStyle(Theme.down) } }
            }
            .scrollContentBackground(.hidden)
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
            let from = groups.portfoliosOf(submission.rawIdentity.key)
            try await grading.complete(submission, grade: grade, date: Format.day(date), store: store)
            // Keep the slab in the same portfolios as the raw card it came from.
            let slab = HoldingIdentity(productId: submission.productId, printing: submission.printing, condition: "Near Mint", gradeCompany: submission.company, grade: grade)
            if groups.portfoliosOf(slab.key) != from { try await groups.place(slab.key, in: from, store: store) }
            UINotificationFeedbackGenerator().notificationOccurred(.success)
            onReturned(grade)
            dismiss()
        } catch {
            self.error = error.localizedDescription
        }
    }
}
