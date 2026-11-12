import SwiftUI

/// Under a card's headline (its Near Mint, ungraded price): one graded price, PSA 10 to begin
/// with (or the grade of a slab you own), and a menu to pick any company and grade. Priced the
/// same way as the Graded prices panel. Same as the website's GradedPriceLine.
struct GradedPriceLine: View {
    var productId: String
    var printing: String?
    var nm: Double?
    /// A slab you own, to open on: (company, grade, pristine).
    var initial: (company: String, grade: String, pristine: Bool)?

    @State private var values: GradedValues?
    @State private var ebay: EbaySales?
    @State private var loaded = false
    @State private var company = "PSA"
    @State private var grade = "10"

    var body: some View {
        let r = lookup
        VStack(alignment: .leading, spacing: 6) {
            HStack(spacing: 12) {
                Menu {
                    ForEach(gradingCompanies, id: \.self) { c in
                        Section(c) {
                            ForEach(GradedPricesPanel.lookupGrades(c), id: \.self) { g in
                                Button {
                                    company = c
                                    grade = g
                                } label: {
                                    if c == company && g == grade { Label(title(c, g), systemImage: "checkmark") } else { Text(title(c, g)) }
                                }
                            }
                        }
                    }
                } label: {
                    HStack(spacing: 6) {
                        Text(title(company, grade)).font(.geist(15, .semibold)).monospacedDigit()
                        Image(systemName: "chevron.up.chevron.down").font(.system(size: 10, weight: .semibold)).foregroundStyle(Theme.muted)
                    }
                    .foregroundStyle(.white)
                    .padding(.horizontal, 14).frame(height: 36)
                    .liquidGlass(in: Capsule())
                    .contentShape(Capsule())
                }
                .menuStyle(.button)
                .buttonStyle(.plain)
                Spacer(minLength: 8)
                Group {
                    if !loaded {
                        Text(" ")
                    } else if let price = r.price {
                        HStack(spacing: 8) {
                            if r.estimate { EstimatePill() }
                            Text(Format.money(price))
                        }
                    } else {
                        Text("—")
                    }
                }
                .font(.display(22)).tracking(-0.5).monospacedDigit().foregroundStyle(.white)
            }
            .padding(.leading, 6).padding(.trailing, 16).padding(.vertical, 6)
            .surface(padding: 0)
            if loaded {
                Text(r.detail).font(.geist(12)).foregroundStyle(Theme.subtle).lineLimit(2)
            }
        }
        .sensoryFeedback(.selection, trigger: "\(company)\(grade)")
        .task(id: "\(productId)|\(printing ?? "")") {
            // Only catalog cards have PriceCharting and eBay data; others use the grade curve.
            guard productId.hasPrefix("tcgapi:") else { return loaded = true }
            async let pc = try? await Backend.shared.api.gradedValues([productId])
            async let sales = try? await EbaySalesCache.sales(productId, printing: printing)
            let (p, e) = await (pc, sales)
            values = p?[productId]
            ebay = e ?? nil
            loaded = true
        }
        .onAppear {
            if let o = initial {
                company = o.company.uppercased()
                grade = o.pristine && Pristine.isCGCTen(company: o.company, grade: o.grade) ? GradedPricesPanel.pristine10 : o.grade
            }
        }
    }

    private func title(_ c: String, _ g: String) -> String {
        "\(c) \(g == GradedPricesPanel.pristine10 ? g : GradedPricesPanel.gradeTitle(company: c, grade: g))"
    }

    private var lookup: (price: Double?, estimate: Bool, detail: String) {
        let isPristine = grade == GradedPricesPanel.pristine10
        let slabGrade = isPristine ? "10" : grade
        let label = Pristine.label(company: company, grade: slabGrade, pristine: isPristine)
        guard let p = GradedPricesPanel.price(company: company, grade: slabGrade, values: values, ebay: ebay, nm: nm, productId: productId, pristine: isPristine) else {
            return (nil, false, "No sales or price guide for this grade yet")
        }
        switch p.source {
        case let .ebay(n): return (p.value, false, n >= WorthCalc.minSales ? "Median of \(n) \(label) eBay sales this month" : "Last \(label) eBay sale")
        case .guide: return (p.value, false, "PriceCharting · \(label)")
        case .adjusted: return (p.value, true, "Estimate · PriceCharting's grade \(slabGrade) price for any company, adjusted for \(company)")
        case .curve: return (p.value, true, "Estimate from the usual grade curve")
        case .premium: return (p.value, true, "Estimate · \(Pristine.gemMintLabel) price × \(String(Pristine.pristinePremium)), the usual Pristine premium")
        }
    }
}
