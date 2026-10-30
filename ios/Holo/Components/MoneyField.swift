import SwiftUI

/// A dollar amount field: shows a hint when empty, keeps the text you type.
struct MoneyField: View {
    var title: String
    @Binding var text: String
    var hint: String = "$0.00"

    var body: some View {
        HStack {
            Text(title)
            Spacer()
            TextField(hint, text: $text)
                .keyboardType(.decimalPad)
                .multilineTextAlignment(.trailing)
                .monospacedDigit()
                .frame(maxWidth: 140)
        }
    }

    /// The typed amount, or nil when blank or not a number.
    static func value(_ text: String) -> Double? {
        let cleaned = text.replacingOccurrences(of: "$", with: "").replacingOccurrences(of: ",", with: "").trimmingCharacters(in: .whitespaces)
        return cleaned.isEmpty ? nil : Double(cleaned)
    }
}
