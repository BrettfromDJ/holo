import SwiftUI

/// Log a purchase: which printing, condition or grade, how many, and what you paid.
struct AddPurchaseSheet: View {
    var hit: SearchHit
    var onDone: (() -> Void)?
    @Environment(\.dismiss) private var dismiss
    @Environment(CollectionStore.self) private var store
    @Environment(GradingStore.self) private var grading
    @Environment(GroupsStore.self) private var groups
    /// The portfolio picked for this purchase; nil until you pick one (see `portfolioId`).
    @State private var pickedPortfolio: String?
    @State private var namingPortfolio = false
    @State private var newPortfolio = ""

    @State private var printing: String?
    @State private var condition = CardCondition.nearMint.rawValue
    @State private var graded = false
    @State private var company = "PSA"
    @State private var grade = "10"
    /// The bumper guard on the slab, if any (saved with the slab once it's added).
    @State private var bumper: String?
    @State private var quantity = 1
    @State private var price = ""
    @State private var date = Date()
    @State private var source = ""
    /// Pulled from a pack rather than bought: no price or where; it's marked as a pull.
    @State private var pulled = false
    // Your usual details, remembered on this phone: where you buy, and the condition or grade
    // you last picked; the date too while you're logging buys within a few hours of each other.
    @AppStorage("holo.add.source") private var lastSource = ""
    @AppStorage("holo.add.condition") private var lastCondition = ""
    @AppStorage("holo.add.graded") private var lastGraded = false
    @AppStorage("holo.add.company") private var lastCompany = "PSA"
    @AppStorage("holo.add.grade") private var lastGrade = "10"
    @AppStorage("holo.add.date") private var lastDate = 0.0
    @AppStorage("holo.add.savedAt") private var lastSavedAt = 0.0
    @State private var saving = false
    /// Shipping, tax and fees for the whole purchase: separate lines, folded away until wanted.
    @State private var extras = false
    @State private var shipping = ""
    @State private var tax = ""
    @State private var fees = ""
    @State private var error: String?

    private var product: Product { hit.product }
    /// Highest first. CGC 10s come in two kinds: Pristine 10 (the gold label) and Gem Mint 10.
    private var grades: [String] {
        let whole = (1...10).map(String.init)
        let list = (company == "BGS" || company == "CGC" ? whole + ["9.5", "8.5", "7.5"] : whole)
            .sorted { (Double($0) ?? 0) > (Double($1) ?? 0) }
        return company == "CGC" ? [Self.pristine] + list : list
    }

    static let pristine = "Pristine 10"

    /// The copy this purchase adds to (a slab is Near Mint underneath; Pristine is still a 10).
    private var identity: HoldingIdentity {
        let isGraded = graded && !product.isSealed
        return HoldingIdentity(
            productId: product.id, printing: printing,
            condition: product.isSealed ? "Sealed" : (isGraded ? CardCondition.nearMint.rawValue : condition),
            gradeCompany: isGraded ? company : nil,
            grade: isGraded ? (grade == Self.pristine ? "10" : grade) : nil
        )
    }

    /// Until you pick one: the portfolio Collection is showing; when it shows all of them, more
    /// of a copy you own stays where it is and anything new goes to Main.
    private var portfolioId: String {
        if let pickedPortfolio { return pickedPortfolio }
        if groups.portfolios.contains(where: { $0.id == groups.selected }) || groups.selected == GroupsStore.main { return groups.selected }
        return store.holding(key: identity.key) != nil ? groups.portfolioOf(identity.key) : GroupsStore.main
    }

    private func gradeTitle(_ g: String) -> String {
        company == "CGC" && g == "10" ? "Gem Mint 10" : g
    }

    var body: some View { sheetBody.glassSheet() }

    @ViewBuilder private var sheetBody: some View {
        NavigationStack {
            GlassForm {
                Section {
                    HStack(spacing: 12) {
                        ProductImage(product: product, cornerRadius: 3).frame(width: 48, height: 66)
                        VStack(alignment: .leading, spacing: 2) {
                            Text(product.name).font(.headline)
                            Text(product.subtitle).font(.caption).foregroundStyle(Theme.muted)
                            Text("Market \(Format.money(hit.market))").font(.caption.weight(.medium)).monospacedDigit()
                        }
                    }
                }

                // Which portfolio it goes in, right at the top so it's never missed.
                Section {
                    Picker("Add to", selection: Binding(get: { portfolioId }, set: { pickedPortfolio = $0 })) {
                        Text("Main").tag(GroupsStore.main)
                        ForEach(groups.portfolios) { Text($0.name).tag($0.id) }
                    }
                    Button { namingPortfolio = true } label: { Label("New portfolio…", systemImage: "plus") }
                        .foregroundStyle(Theme.lime)
                } header: {
                    SectionTitle("Portfolio")
                } footer: {
                    SectionNote("The portfolio this goes into. Main is everything not in another portfolio.")
                }

                if let printings = product.printings, printings.count > 1 {
                    Picker("Printing", selection: $printing) {
                        ForEach(printings, id: \.self) { Text($0).tag(Optional($0)) }
                    }
                }

                if !product.isSealed {
                    Section {
                        Toggle("Graded", isOn: $graded)
                        if graded {
                            Picker("Company", selection: $company) {
                                ForEach(gradingCompanies, id: \.self) { Text($0) }
                            }
                            Picker("Grade", selection: $grade) {
                                ForEach(grades, id: \.self) { Text(gradeTitle($0)) }
                            }
                            .onChange(of: company) { _, _ in if !grades.contains(grade) { grade = "10" } }
                            // The bumper guard it sits in, picked here rather than later from Owned.
                            VStack(alignment: .leading, spacing: 6) {
                                HStack {
                                    Text("Bumper")
                                    Spacer()
                                    Text(Bumper.byId(bumper)?.name ?? "None").foregroundStyle(Theme.muted)
                                }
                                BumperStrip(pick: $bumper)
                            }
                        } else {
                            Picker("Condition", selection: $condition) {
                                ForEach(CardCondition.allCases) { Text($0.rawValue).tag($0.rawValue) }
                            }
                        }
                    } header: {
                        SectionTitle("Condition")
                    }
                }

                // How you got it: bought, or pulled from a pack (a pull has no price to fill in).
                if !product.isSealed {
                    Section {
                        HStack(spacing: 10) {
                            HowYouGotIt(icon: "bag", title: "Bought", detail: "You paid for it", selected: !pulled) { pulled = false }
                            HowYouGotIt(icon: "sparkles", title: "Pulled", detail: "From a pack you opened", selected: pulled) { pulled = true }
                        }
                        // A little in from the row's edges: the form clips each row to its own,
                        // rounder corners, which shaved the selected card's outline.
                        .padding(3)
                        .listRowBackground(Color.clear)
                        .listRowInsets(EdgeInsets())
                    } header: {
                        SectionTitle("How you got it")
                    } footer: {
                        if pulled { SectionNote("Marked as a pull, with a Pulled badge. Nothing to fill in for price.") }
                    }
                }

                Section {
                    Stepper("Quantity: \(quantity)", value: $quantity, in: 1...999)
                    if !pulled {
                    HStack {
                        Text("Price paid (each)")
                        Spacer()
                        TextField(Format.money(hit.market ?? 0), text: $price)
                            .keyboardType(.decimalPad)
                            .multilineTextAlignment(.trailing)
                            .monospacedDigit()
                    }
                    }
                    if pulled {
                        // Nothing about money for a pull.
                    } else if extras {
                        MoneyField(title: "Shipping", text: $shipping)
                        MoneyField(title: "Tax", text: $tax)
                        MoneyField(title: "Fees", text: $fees)
                    } else {
                        Button { withAnimation(.snappy) { extras = true } } label: {
                            Label("Add shipping, tax or fees", systemImage: "plus")
                        }
                        .foregroundStyle(Theme.lime)
                    }
                    DatePicker(pulled ? "Pulled on" : "Date", selection: $date, in: ...Date(), displayedComponents: .date)
                    if !pulled {
                        HStack {
                            Text("Where")
                            Spacer()
                            TextField("Card show, eBay, store…", text: $source)
                                .multilineTextAlignment(.trailing)
                                .textInputAutocapitalization(.words)
                        }
                    }
                } header: {
                    SectionTitle(pulled ? "Pull" : "Purchase")
                }

                if let error {
                    Section { Text(error).foregroundStyle(Theme.down) }
                }
            }
            .scrollContentBackground(.hidden)
            .alert("New portfolio", isPresented: $namingPortfolio) {
                TextField("Resale, PC, Graded…", text: $newPortfolio)
                Button("Cancel", role: .cancel) { newPortfolio = "" }
                Button("Create") {
                    let name = String(newPortfolio.trimmingCharacters(in: .whitespaces).prefix(40))
                    newPortfolio = ""
                    guard !name.isEmpty else { return }
                    Task {
                        do {
                            try await groups.createPortfolio(name, store: store)
                            pickedPortfolio = groups.portfolios.last?.id
                        } catch { self.error = error.localizedDescription }
                    }
                }
            } message: {
                Text("This card goes into it.")
            }
            .navigationTitle("Add to collection")
            .navigationBarTitleDisplayMode(.inline)
            .toolbar {
                ToolbarItem(placement: .cancellationAction) { Button("Cancel") { dismiss() } }
                ToolbarItem(placement: .confirmationAction) {
                    Button(saving ? "Saving…" : "Add") { Task { await save() } }.disabled(saving)
                }
            }
            .onAppear {
                if printing == nil { printing = hit.printing ?? product.printings?.first }
                source = lastSource
                if Demo.isOn, ProcessInfo.processInfo.arguments.contains("-HoloAddPulled") { pulled = true }
                if !product.isSealed {
                    if CardCondition(rawValue: lastCondition) != nil { condition = lastCondition }
                    graded = lastGraded
                    if gradingCompanies.contains(lastCompany) { company = lastCompany }
                    grade = grades.contains(lastGrade) ? lastGrade : "10"
                }
                // Logging several buys (a card show): keep the date you picked for a few hours.
                if lastDate > 0, Date().timeIntervalSince1970 - lastSavedAt < 6 * 3600 {
                    date = min(Date(timeIntervalSince1970: lastDate), Date())
                }
            }
        }
        .presentationDetents([.large])
    }

    private func save() async {
        saving = true
        error = nil
        defer { saving = false }
        // A blank price means you paid market (the field shows it as the hint).
        let typed = Double(price.replacingOccurrences(of: "$", with: "").replacingOccurrences(of: ",", with: ""))
        let unit = pulled ? 0 : (typed ?? hit.market ?? 0)
        let where_: String = pulled ? Txn.pulledSource : (source.trimmingCharacters(in: .whitespaces).isEmpty ? "ios" : source.trimmingCharacters(in: .whitespaces))
        let purchase = CollectionStore.Purchase(
            product: product,
            printing: printing,
            condition: product.isSealed ? "Sealed" : (graded ? CardCondition.nearMint.rawValue : condition),
            gradeCompany: graded && !product.isSealed ? company : nil,
            // Pristine is still a 10; the gold label is remembered per slab (slab-pristine).
            grade: graded && !product.isSealed ? (grade == Self.pristine ? "10" : grade) : nil,
            quantity: Double(quantity),
            unitPrice: unit,
            date: Format.day(date),
            source: where_,
            shipping: pulled ? 0 : (MoneyField.value(shipping) ?? 0),
            tax: pulled ? 0 : (MoneyField.value(tax) ?? 0),
            fees: pulled ? 0 : (MoneyField.value(fees) ?? 0)
        )
        do {
            let before = store.allHoldings.reduce(0) { $0 + ($1.value ?? 0) }
            let key = identity.key
            let owned = store.holding(key: key) != nil
            let target = portfolioId
            try await store.add([purchase])
            // More of a copy you own also shows in the picked portfolio (a Copy: it stays where
            // it is); a new one goes only there. A demo keeps this on the phone.
            if !groups.portfolios.isEmpty {
                if owned {
                    try? await groups.copyMany([key], to: target, store: store)
                } else if groups.portfoliosOf(key) != [target] {
                    try? await groups.moveMany([key], to: target, store: store)
                }
            }
            if graded, !product.isSealed, let bumper { grading.setBumper(key, bumper) }
            if graded, !product.isSealed, company == "CGC", grade == Self.pristine {
                let id = HoldingIdentity(productId: product.id, printing: printing, condition: CardCondition.nearMint.rawValue, gradeCompany: "CGC", grade: "10")
                grading.setPristine(id.key, true)
                // Price it as a Pristine 10 straight away, not at the next load.
                Task { await store.loadSlabPrices() }
            }
            if !pulled { lastSource = source.trimmingCharacters(in: .whitespaces) }
            lastDate = date.timeIntervalSince1970
            lastSavedAt = Date().timeIntervalSince1970
            if !product.isSealed {
                lastGraded = graded
                if graded { lastCompany = company; lastGrade = grade } else { lastCondition = condition }
            }
            UINotificationFeedbackGenerator().notificationOccurred(.success)
            dismiss()
            onDone?()
            // The "pack pull" moment, like the website, once the sheet is away.
            let slab: HoldingIdentity? = graded && !product.isSealed
                ? HoldingIdentity(productId: product.id, printing: printing, condition: CardCondition.nearMint.rawValue, gradeCompany: company, grade: grade == Self.pristine ? "10" : grade)
                : nil
            let added = HoldingIdentity(productId: product.id, printing: printing, condition: graded ? CardCondition.nearMint.rawValue : condition,
                                        gradeCompany: graded ? company : nil, grade: graded ? (grade == Self.pristine ? "10" : grade) : nil)
            Router.shared.pull = PullEvent(product: product, quantity: Double(quantity), before: before, identity: pulled ? added : slab, pulled: pulled)
        } catch {
            self.error = error.localizedDescription
        }
    }
}

/// One of the two "How you got it" choices: a tile with an icon, a name and a line under it.
/// The chosen one is outlined in lime with a lime icon; the other stays quiet.
private struct HowYouGotIt: View {
    var icon: String
    var title: String
    var detail: String
    var selected: Bool
    var action: () -> Void

    var body: some View {
        Button {
            Haptics.tap()
            withAnimation(.snappy(duration: 0.2)) { action() }
        } label: {
            VStack(alignment: .leading, spacing: 12) {
                HStack {
                    Image(systemName: icon)
                        .font(.system(size: 16, weight: .semibold))
                        .foregroundStyle(selected ? Theme.ink : .white)
                        .frame(width: 36, height: 36)
                        .background(Circle().fill(selected ? Theme.lime : Color.white.opacity(0.08)))
                    Spacer()
                    Image(systemName: selected ? "checkmark.circle.fill" : "circle")
                        .font(.system(size: 20))
                        .foregroundStyle(selected ? Theme.lime : Color.white.opacity(0.25))
                }
                VStack(alignment: .leading, spacing: 3) {
                    Text(title).font(.geist(17, .semibold)).foregroundStyle(.white)
                    Text(detail).font(.geist(13)).foregroundStyle(Theme.muted)
                        .lineLimit(2).fixedSize(horizontal: false, vertical: true)
                }
            }
            .padding(14)
            .frame(maxWidth: .infinity, alignment: .leading)
            .background(RoundedRectangle(cornerRadius: 20).fill(selected ? Theme.lime.opacity(0.08) : Color.white.opacity(0.06)))
            .overlay(RoundedRectangle(cornerRadius: 20).strokeBorder(selected ? Theme.lime : Color.white.opacity(0.08), lineWidth: selected ? 1.5 : 1))
            .contentShape(RoundedRectangle(cornerRadius: 20))
        }
        .buttonStyle(.plain)
        .accessibilityAddTraits(selected ? .isSelected : [])
    }
}
