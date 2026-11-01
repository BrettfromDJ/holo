import SwiftUI

/// Log a purchase: which printing, condition or grade, how many, and what you paid.
struct AddPurchaseSheet: View {
    var hit: SearchHit
    var onDone: (() -> Void)?
    @Environment(\.dismiss) private var dismiss
    @Environment(CollectionStore.self) private var store

    @State private var printing: String?
    @State private var condition = CardCondition.nearMint.rawValue
    @State private var graded = false
    @State private var company = "PSA"
    @State private var grade = "10"
    @State private var quantity = 1
    @State private var price = ""
    @State private var date = Date()
    @State private var source = ""
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
    @State private var error: String?

    private var product: Product { hit.product }
    private var grades: [String] {
        let whole = (1...10).map(String.init)
        return company == "BGS" || company == "CGC" ? whole + ["9.5", "8.5", "7.5"] : whole
    }

    var body: some View { sheetBody.glassSheet() }

    @ViewBuilder private var sheetBody: some View {
        NavigationStack {
            GlassForm {
                Section {
                    HStack(spacing: 12) {
                        ProductImage(product: product, cornerRadius: 5).frame(width: 48, height: 66)
                        VStack(alignment: .leading, spacing: 2) {
                            Text(product.name).font(.headline)
                            Text(product.subtitle).font(.caption).foregroundStyle(Theme.muted)
                            Text("Market \(Format.money(hit.market))").font(.caption.weight(.medium)).monospacedDigit()
                        }
                    }
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
                                ForEach(grades.sorted { (Double($0) ?? 0) > (Double($1) ?? 0) }, id: \.self) { Text($0) }
                            }
                        } else {
                            Picker("Condition", selection: $condition) {
                                ForEach(CardCondition.allCases) { Text($0.rawValue).tag($0.rawValue) }
                            }
                        }
                    }
                }

                Section("Purchase") {
                    Stepper("Quantity: \(quantity)", value: $quantity, in: 1...999)
                    HStack {
                        Text("Price paid (each)")
                        Spacer()
                        TextField(Format.money(hit.market ?? 0), text: $price)
                            .keyboardType(.decimalPad)
                            .multilineTextAlignment(.trailing)
                            .monospacedDigit()
                    }
                    DatePicker("Date", selection: $date, in: ...Date(), displayedComponents: .date)
                    HStack {
                        Text("Where")
                        Spacer()
                        TextField("Card show, eBay, store…", text: $source)
                            .multilineTextAlignment(.trailing)
                            .textInputAutocapitalization(.words)
                    }
                }

                if let error {
                    Section { Text(error).foregroundStyle(Theme.down) }
                }
            }
            .scrollContentBackground(.hidden)
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
                if !product.isSealed {
                    if CardCondition(rawValue: lastCondition) != nil { condition = lastCondition }
                    graded = lastGraded
                    if gradingCompanies.contains(lastCompany) { company = lastCompany }
                    grade = lastGrade
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
        let unit = typed ?? hit.market ?? 0
        let purchase = CollectionStore.Purchase(
            product: product,
            printing: printing,
            condition: product.isSealed ? "Sealed" : (graded ? CardCondition.nearMint.rawValue : condition),
            gradeCompany: graded && !product.isSealed ? company : nil,
            grade: graded && !product.isSealed ? grade : nil,
            quantity: Double(quantity),
            unitPrice: unit,
            date: Format.day(date),
            source: source.trimmingCharacters(in: .whitespaces).isEmpty ? "ios" : source.trimmingCharacters(in: .whitespaces)
        )
        do {
            let before = store.allHoldings.reduce(0) { $0 + ($1.value ?? 0) }
            try await store.add([purchase])
            lastSource = source.trimmingCharacters(in: .whitespaces)
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
            Router.shared.pull = PullEvent(product: product, quantity: Double(quantity), before: before)
        } catch {
            self.error = error.localizedDescription
        }
    }
}
