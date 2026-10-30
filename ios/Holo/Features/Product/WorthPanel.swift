import SwiftUI

/// One question, one number: what is this card worth in a given condition or grade?
/// Real prices first (TCGplayer per condition, eBay sales per grade); estimates are always marked.
struct WorthPanel: View {
    var productId: String
    var printing: String?
    var nm: Double
    var owned: [HoldingView]

    @State private var graded = false
    @State private var condition = CardCondition.nearMint
    @State private var company = "PSA"
    @State private var grade = "10"
    @State private var ebay: EbaySales?
    @State private var conditions: [ConditionPrice] = []
    @State private var loaded = false

    private var worth: Worth {
        graded ? WorthCalc.graded(productId: productId, nm: nm, company: company, grade: grade, ebay: ebay)
            : WorthCalc.raw(nm: nm, condition: condition, ebay: ebay, conditions: conditions, printing: printing)
    }

    var body: some View {
        Panel {
            VStack(alignment: .leading, spacing: 14) {
                HStack {
                    Text("What's it worth?").font(.headline)
                    Spacer()
                    if !loaded { ProgressView().controlSize(.small) }
                }
                Picker("", selection: $graded) {
                    Text("Raw").tag(false)
                    Text("Graded").tag(true)
                }
                .pickerStyle(.segmented)

                let w = worth
                HStack(alignment: .lastTextBaseline) {
                    Text((w.isEstimate ? "≈ " : "") + Format.money(w.price))
                        .font(.display(52)).monospacedDigit()
                        .foregroundStyle(Color.primary.opacity(w.isEstimate ? 0.85 : 1))
                        .contentTransition(.numericText())
                    Spacer()
                    Text(graded ? "\(company) \(grade)" : condition.rawValue).font(.subheadline.weight(.semibold))
                }
                HStack(spacing: 8) {
                    SourceTag(source: w.source)
                    Text(w.detail).font(.caption).foregroundStyle(Theme.muted)
                }
                if !(graded == false && condition == .nearMint) {
                    let diff = w.price - nm
                    (Text(Format.signedMoney(diff)).foregroundStyle(Theme.tone(diff)) + Text(" vs raw Near Mint (\(Format.money(nm)))").foregroundStyle(Theme.muted))
                        .font(.caption).monospacedDigit()
                }

                if graded {
                    Picker("Company", selection: $company) {
                        ForEach(gradingCompanies, id: \.self) { Text($0) }
                    }
                    .pickerStyle(.segmented)
                    ScrollView(.horizontal, showsIndicators: false) {
                        HStack(spacing: 6) {
                            ForEach(WorthCalc.grades(for: company).reversed(), id: \.self) { g in
                                Button(g) { grade = g }
                                    .font(.footnote.weight(.semibold)).monospacedDigit()
                                    .frame(minWidth: 38, minHeight: 34)
                                    .background(grade == g ? Theme.lime : Theme.surface2, in: RoundedRectangle(cornerRadius: 9))
                                    .foregroundStyle(grade == g ? Theme.ink : .primary)
                            }
                        }
                    }
                } else {
                    HStack(spacing: 6) {
                        ForEach(CardCondition.allCases) { c in
                            Button(c.short) { condition = c }
                                .font(.footnote.weight(.semibold))
                                .frame(maxWidth: .infinity, minHeight: 38)
                                .background(condition == c ? c.tint.opacity(0.22) : Theme.surface2, in: RoundedRectangle(cornerRadius: 10))
                                .overlay(RoundedRectangle(cornerRadius: 10).stroke(condition == c ? c.tint : .clear, lineWidth: 1.5))
                                .foregroundStyle(condition == c ? c.tint : Theme.muted)
                        }
                    }
                    // Is grading it worth it? PSA 10 against raw Near Mint.
                    let gem = WorthCalc.graded(productId: productId, nm: nm, company: "PSA", grade: "10", ebay: ebay)
                    Button {
                        graded = true
                        company = "PSA"
                        grade = "10"
                    } label: {
                        HStack {
                            Text("As a PSA 10: ").foregroundStyle(Theme.muted) + Text((gem.isEstimate ? "≈ " : "") + Format.money(gem.price)).bold()
                            Spacer()
                            Text(Format.signedMoney(gem.price - nm)).foregroundStyle(Theme.tone(gem.price - nm)).monospacedDigit()
                        }
                        .font(.footnote)
                        .padding(12)
                        .background(Theme.surface2, in: RoundedRectangle(cornerRadius: 12))
                    }
                    .buttonStyle(.plain)
                }
            }
        }
        .task(id: "\(productId)|\(printing ?? "")") { await load() }
        .onAppear {
            // Open on the copy you own.
            if let slab = owned.first(where: { $0.identity.isGraded })?.identity, !owned.contains(where: { !$0.identity.isGraded }) {
                graded = true
                company = slab.gradeCompany ?? "PSA"
                grade = slab.grade ?? "10"
            } else if let raw = owned.first(where: { !$0.identity.isGraded }), let c = CardCondition(rawValue: raw.identity.condition) {
                condition = c
            }
        }
    }

    private func load() async {
        guard productId.hasPrefix("tcgapi:") else { return loaded = true }
        async let sales = try? Backend.shared.api.ebaySales(productId, printing: printing)
        async let conds = try? Backend.shared.api.conditionPrices(productId, printing: printing)
        let (s, c) = await (sales, conds)
        ebay = s ?? nil
        conditions = c ?? []
        loaded = true
    }
}

struct SourceTag: View {
    var source: Worth.Source

    var body: some View {
        let label = ["market": "Market price", "sales": "eBay sales", "guide": "Price guide", "estimate": "Estimate"][source.rawValue] ?? ""
        Text(label)
            .font(.system(size: 11, weight: .semibold))
            .padding(.horizontal, 8).padding(.vertical, 3)
            .foregroundStyle(source == .sales ? Theme.up : Color.primary.opacity(0.8))
            .background(source == .estimate ? Color.clear : (source == .sales ? Theme.lime.opacity(0.16) : Theme.surface2), in: Capsule())
            .overlay(Capsule().strokeBorder(source == .estimate ? Theme.muted : .clear, style: StrokeStyle(lineWidth: 1, dash: [3, 2])))
    }
}

extension CardCondition {
    /// The color each condition is tagged with, as on the web.
    var tint: Color {
        switch self {
        case .nearMint: return Theme.lime
        case .lightlyPlayed: return Color(hex: 0x5AC8FA)
        case .moderatelyPlayed: return Theme.warn
        case .heavilyPlayed: return Color(hex: 0xFF9F0A)
        case .damaged: return Theme.down
        }
    }

    /// A condition named in an eBay title ("Lightly Played"), if it's one of ours.
    static func from(label: String?) -> CardCondition? { label.flatMap(CardCondition.init(rawValue:)) }
}
