import SwiftUI

/// One question, one number: what is this card worth raw, in the condition you pick? Real
/// prices first (TCGplayer per condition, then eBay sales); estimates are always marked.
/// Grades are in the Graded prices panel above.
struct WorthPanel: View {
    var productId: String
    var printing: String?
    var nm: Double
    var owned: [HoldingView]

    @State private var condition = CardCondition.nearMint
    @State private var ebay: EbaySales?
    @State private var conditions: [ConditionPrice] = []
    @State private var loaded = false

    private var worth: Worth {
        WorthCalc.raw(nm: nm, condition: condition, ebay: ebay, conditions: conditions, printing: printing)
    }

    var body: some View {
        Panel {
            VStack(alignment: .leading, spacing: 14) {
                HStack {
                    CardLabel(text: "What's it worth raw?")
                    Spacer()
                    if !loaded { ProgressView().controlSize(.small) }
                }
                let w = worth
                // The raw value on its own glow (a different color from the price card above).
                GlowCard(palette: palette, radius: 24, padding: 18) {
                    VStack(alignment: .leading, spacing: 0) {
                        HStack(alignment: .top) {
                            GlowLabel(text: condition.rawValue, secondary: w.detail)
                            Spacer(minLength: 8)
                            GlowPill(text: Self.sourceLabel(w.source))
                        }
                        Text((w.isEstimate ? "≈ " : "") + Format.money(w.price))
                            .font(.geist(52)).tracking(-2).monospacedDigit()
                            .lineLimit(1).minimumScaleFactor(0.5)
                            .contentTransition(.numericText())
                            .animation(.snappy, value: w.price)
                            .padding(.top, 16)
                        if condition != .nearMint {
                            let diff = w.price - nm
                            Text("\(Format.signedMoney(diff)) vs Near Mint (\(Format.money(nm)))")
                                .font(.geist(13, .medium)).monospacedDigit().opacity(0.8)
                        }
                    }
                }
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
                .sensoryFeedback(.selection, trigger: condition)
            }
        }
        .task(id: "\(productId)|\(printing ?? "")") { await load() }
        .onAppear {
            // Open on the condition you own.
            if let raw = owned.first(where: { !$0.identity.isGraded }), let c = CardCondition(rawValue: raw.identity.condition) {
                condition = c
            }
        }
    }

    /// Its own glow, never the same as the product's price card.
    private var palette: GlowPalette {
        GlowPalette.forProduct(productId) == .aqua ? .flame : .aqua
    }

    static func sourceLabel(_ source: Worth.Source) -> String {
        ["market": "Market price", "sales": "eBay sales", "guide": "Price guide", "estimate": "Estimate"][source.rawValue] ?? ""
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
