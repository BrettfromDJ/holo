import SwiftUI

/// What the card sells for graded, from PriceCharting's daily price guide (stored nightly on
/// the server, so free to show): each grade's value and how many times ungraded it is, with the
/// grade you own highlighted. Hidden when PriceCharting has no graded prices for the card.
/// Same as the website's Graded prices card.
struct GradedPricesPanel: View {
    var productId: String
    /// Grades you own, as (company, grade).
    var owned: [(company: String, grade: String)]

    @State private var values: GradedValues?
    @State private var loaded = false

    private struct Row: Identifiable {
        var key: String
        var company: String?
        var grade: String
        var id: String { key }
    }

    /// The 10s by grader, then any grader below.
    private static let rows: [Row] = [
        Row(key: "PSA 10", company: "PSA", grade: "10"),
        Row(key: "BGS 10", company: "BGS", grade: "10"),
        Row(key: "CGC 10", company: "CGC", grade: "10"),
        Row(key: "SGC 10", company: "SGC", grade: "10"),
        Row(key: "9.5", company: nil, grade: "9.5"),
        Row(key: "9", company: nil, grade: "9"),
        Row(key: "8", company: nil, grade: "8"),
        Row(key: "7", company: nil, grade: "7"),
    ]

    var body: some View {
        Group {
            if !loaded {
                card { ProgressView().controlSize(.small).tint(Theme.muted).frame(maxWidth: .infinity).padding(.vertical, 20) }
            } else if let values, !values.grades.isEmpty {
                card { table(values) }
            }
        }
        .task(id: productId) {
            values = (try? await Backend.shared.api.gradedValues([productId]))?[productId]
            loaded = true
        }
    }

    private func card<Content: View>(@ViewBuilder _ content: () -> Content) -> some View {
        VStack(alignment: .leading, spacing: 0) {
            VStack(alignment: .leading, spacing: 2) {
                Text("Graded prices").font(.geist(15, .semibold))
                Text(values.map { "What it sells for graded · PriceCharting" + (relative($0.updatedAt).map { " · updated \($0)" } ?? "") } ?? "What it sells for graded")
                    .font(.geist(12)).foregroundStyle(Theme.muted)
            }
            content().padding(.top, 14)
        }
        .surface(padding: 20)
    }

    @ViewBuilder private func table(_ v: GradedValues) -> some View {
        VStack(alignment: .leading, spacing: 0) {
            if let ungraded = v.ungraded {
                HStack {
                    Text("Ungraded").font(.geist(13)).foregroundStyle(Theme.muted)
                    Spacer()
                    Text(Format.money(ungraded)).font(.geist(17, .semibold)).monospacedDigit()
                }
                .padding(.horizontal, 14).padding(.vertical, 11)
                .background(RoundedRectangle(cornerRadius: 12, style: .continuous).fill(Theme.surface2))
                .padding(.bottom, 6)
            }
            let shown = Self.rows.filter { v.grades[$0.key] != nil }
            ForEach(Array(shown.enumerated()), id: \.element.id) { i, row in
                let value = v.grades[row.key] ?? 0
                let mine = isOwned(row)
                HStack(spacing: 10) {
                    HStack(spacing: 4) {
                        Text(row.company ?? "Any").foregroundStyle(Theme.muted)
                        Text(row.grade).foregroundStyle(.white)
                    }
                    .font(.mono(12))
                    .padding(.horizontal, 8).frame(height: 24)
                    .frame(minWidth: 72, alignment: .leading)
                    .background(RoundedRectangle(cornerRadius: 6, style: .continuous).fill(Theme.surface2))
                    .overlay(RoundedRectangle(cornerRadius: 6, style: .continuous).strokeBorder(Theme.border))
                    if mine { Text("Yours").font(.geist(11, .semibold)).foregroundStyle(Theme.lime) }
                    Spacer(minLength: 8)
                    if let base = v.ungraded, base > 0 {
                        let m = value / base
                        Text("\(m >= 10 ? String(format: "%.0f", m) : String(format: "%.1f", m))× ungraded")
                            .font(.geist(12)).foregroundStyle(Theme.subtle).monospacedDigit()
                    }
                    Text(Format.money(value)).font(.geist(16, .semibold)).monospacedDigit()
                        .frame(minWidth: 86, alignment: .trailing)
                }
                .padding(.vertical, 11)
                .padding(.horizontal, mine ? 10 : 0)
                .background { if mine { RoundedRectangle(cornerRadius: 12, style: .continuous).fill(Theme.lime.opacity(0.1)) } }
                if i < shown.count - 1 { Divider().overlay(Theme.border) }
            }
            Text("10s are per grading company; lower grades are for any company.")
                .font(.geist(12)).foregroundStyle(Theme.subtle).padding(.top, 10)
        }
    }

    private func isOwned(_ row: Row) -> Bool {
        owned.contains { o in
            let g = Double(o.grade) ?? -1
            if let company = row.company { return o.company.uppercased() == company && g == 10 }
            return g == Double(row.grade) && g != 10
        }
    }

    private func relative(_ iso: String) -> String? {
        let f = ISO8601DateFormatter()
        f.formatOptions = [.withInternetDateTime, .withFractionalSeconds]
        guard let date = f.date(from: iso) ?? ISO8601DateFormatter().date(from: iso) else { return nil }
        let hours = Int(Date().timeIntervalSince(date) / 3600)
        if hours < 1 { return "just now" }
        if hours < 24 { return "\(hours)h ago" }
        return "\(hours / 24)d ago"
    }
}
