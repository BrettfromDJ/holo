import SwiftUI

/// What the card sells for graded, from PriceCharting's daily price guide (stored nightly on
/// the server, so free to show): each grade's value and how many times ungraded it is, with the
/// grade you own highlighted. Hidden when PriceCharting has no graded prices for the card.
/// Same as the website's Graded prices card.
struct GradedPricesPanel: View {
    var productId: String
    var printing: String? = nil
    /// Raw Near Mint, for the grade curve when nothing better is known.
    var nm: Double? = nil
    /// Grades you own, as (company, grade).
    var owned: [(company: String, grade: String)]

    @State private var values: GradedValues?
    @State private var ebay: EbaySales?
    @State private var loaded = false
    @State private var company = "PSA"
    @State private var grade = "9"

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
            } else if values?.grades.isEmpty == false || nm != nil || ebay?.graded.isEmpty == false {
                card {
                    VStack(alignment: .leading, spacing: 20) {
                        if let values, !values.grades.isEmpty { table(values, estimate: false) }
                        else if let est = estimated { table(est, estimate: true) }
                        Rectangle().fill(Theme.border).frame(height: 1)
                        lookup
                    }
                }
            }
        }
        .task(id: "\(productId)|\(printing ?? "")") {
            // Only catalog cards have PriceCharting and eBay data; others use the grade curve.
            guard productId.hasPrefix("tcgapi:") else { return loaded = true }
            async let pc = try? await Backend.shared.api.gradedValues([productId])
            async let sales = try? await Backend.shared.api.ebaySales(productId, printing: printing)
            let (p, e) = await (pc, sales)
            values = p?[productId]
            ebay = e ?? nil
            loaded = true
        }
        .onAppear {
            // Open on the grade you own, if you own a slab of it.
            if let o = owned.first { company = o.company.uppercased(); grade = o.grade }
        }
    }

    private func card<Content: View>(@ViewBuilder _ content: () -> Content) -> some View {
        VStack(alignment: .leading, spacing: 0) {
            VStack(alignment: .leading, spacing: 2) {
                Text("Graded prices").font(.geist(15, .semibold))
                Text(values.flatMap { $0.grades.isEmpty ? nil : "What it sells for graded · PriceCharting" + (relative($0.updatedAt).map { " · updated \($0)" } ?? "") } ?? "Estimated from the usual grade curve")
                    .font(.geist(12)).foregroundStyle(Theme.muted)
            }
            content().padding(.top, 14)
        }
        .surface(padding: 20)
    }

    // MARK: Look up any grade

    /// Any company and grade: recent eBay sales of that exact slab first, then PriceCharting's
    /// guide (10s per company, lower grades for any company), then the usual grade curve.
    private var lookup: some View {
        let r = lookupValue
        // One calm row: pick the company and grade from two small menus, the price sits beside
        // them, and where it comes from reads underneath.
        return VStack(alignment: .leading, spacing: 10) {
            MonoLabel(text: "Look up any grade")
            HStack(spacing: 8) {
                lookupMenu(company, options: gradingCompanies) { c in
                    company = c
                    if !Self.lookupGrades(c).contains(grade) { grade = "10" }
                }
                lookupMenu(grade, options: Self.lookupGrades(company)) { grade = $0 }
                Spacer(minLength: 8)
                // The price rolls to each grade like an odometer.
                Group {
                    if let price = r.price {
                        OdometerText(value: price, format: { Format.money($0) })
                    } else {
                        Text("—")
                    }
                }
                .font(.display(24)).tracking(-0.6).monospacedDigit()
            }
            Text(r.detail).font(.geist(12)).foregroundStyle(Theme.subtle).lineLimit(2)
        }
        .sensoryFeedback(.selection, trigger: "\(company)\(grade)")
    }

    /// A small pill showing the current choice; tap it for the list.
    private func lookupMenu(_ current: String, options: [String], pick: @escaping (String) -> Void) -> some View {
        Menu {
            Picker(selection: Binding(get: { current }, set: pick)) {
                ForEach(options, id: \.self) { Text($0).tag($0) }
            } label: { EmptyView() }
        } label: {
            HStack(spacing: 6) {
                Text(current).font(.geist(15, .semibold)).monospacedDigit()
                Image(systemName: "chevron.up.chevron.down").font(.system(size: 10, weight: .semibold)).foregroundStyle(Theme.muted)
            }
            .foregroundStyle(.white)
            .padding(.horizontal, 14).frame(height: 36)
            .liquidGlass(in: Capsule())
            .contentShape(Capsule())
        }
        .menuStyle(.button)
        .buttonStyle(.plain)
    }

    static func lookupGrades(_ company: String) -> [String] {
        WorthCalc.grades(for: company).filter { (Double($0) ?? 0) >= 5 }.reversed()
    }

    private var lookupValue: (price: Double?, detail: String) {
        let label = "\(company) \(grade)"
        if let sold = ebay?.graded[label], sold.count >= WorthCalc.minSales, let median = sold.median {
            return (median, "Median of \(sold.count) \(label) eBay sales this month")
        }
        if let v = values?.value(company: company, grade: grade) {
            let any = (Double(grade) ?? 0) < 10
            return (v, any ? "PriceCharting · grade \(grade), any grading company" : "PriceCharting · \(label)")
        }
        if let sold = ebay?.graded[label], let last = sold.lastPrice ?? sold.median {
            return (last, "Last \(label) eBay sale")
        }
        if let nm {
            return ((nm * WorthCalc.multiple(productId: productId, company: company, grade: grade) * 100).rounded() / 100,
                    "Estimate from the usual grade curve")
        }
        return (nil, "No sales or price guide for this grade yet")
    }

    /// The same table from the usual grade curve, when PriceCharting has nothing for the card.
    private var estimated: GradedValues? {
        guard let nm, nm > 0 else { return nil }
        var grades: [String: Double] = [:]
        for row in Self.rows {
            grades[row.key] = (nm * WorthCalc.multiple(productId: productId, company: row.company ?? "PSA", grade: row.grade) * 100).rounded() / 100
        }
        return GradedValues(ungraded: nm, grades: grades, updatedAt: "")
    }

    @ViewBuilder private func table(_ v: GradedValues, estimate: Bool) -> some View {
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
                .background { if mine { RoundedRectangle(cornerRadius: 12, style: .continuous).fill(Theme.lime.opacity(0.1)).padding(.horizontal, -10) } }
                if i < shown.count - 1 { Divider().overlay(Theme.border) }
            }
            Text(estimate ? "No graded sales for this card yet, so these follow the usual grade curve." : "10s are per grading company; lower grades are for any company.")
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
