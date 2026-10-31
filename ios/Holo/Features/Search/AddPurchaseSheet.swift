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
    @State private var saving = false
    @State private var error: String?

    private var product: Product { hit.product }
    private var grades: [String] {
        let whole = (1...10).map(String.init)
        return company == "BGS" || company == "CGC" ? whole + ["9.5", "8.5", "7.5"] : whole
    }

    var body: some View {
        NavigationStack {
            Form {
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
                }

                if let error {
                    Section { Text(error).foregroundStyle(Theme.down) }
                }
            }
            .scrollContentBackground(.hidden)
            .background(Theme.background)
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
            date: Format.day(date)
        )
        do {
            let before = store.allHoldings.reduce(0) { $0 + ($1.value ?? 0) }
            try await store.add([purchase])
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
