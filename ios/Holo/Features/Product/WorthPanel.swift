import SwiftUI

/// One question, one number: what is this card worth raw, in the condition you pick? Real
/// TCGplayer's prices only (per condition, else a marked estimate from its Near Mint price).
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
    @Environment(CollectionStore.self) private var store

    private var worth: Worth {
        // TCGplayer prices only (eBay's are in their own panel above).
        WorthCalc.raw(nm: nm, condition: condition, ebay: ebay, conditions: conditions, printing: printing, tcgplayerOnly: true)
    }

    var body: some View {
        // Themed around TCGplayer, where these prices come from: its name on top, a blue tint,
        // and the card's TCGplayer page at the bottom.
        VStack(alignment: .leading, spacing: 14) {
            VStack(alignment: .leading, spacing: 14) {
                // Laid out like the eBay panel: the title on the left, the source's wordmark on the right.
                HStack(alignment: .top, spacing: 12) {
                    VStack(alignment: .leading, spacing: 2) {
                        Text("What's it worth raw?").font(.geist(15, .semibold))
                        Text("TCGplayer prices by condition").font(.geist(12)).foregroundStyle(Theme.muted)
                    }
                    Spacer(minLength: 0)
                    TCGplayerMark()
                }
                let w = worth
                HStack(alignment: .lastTextBaseline) {
                    // Rolls digit by digit to the new worth when you pick a condition.
                    OdometerText(value: w.price, format: { Format.money($0) })
                        .font(.display(52)).tracking(-2.1).monospacedDigit()
                        .foregroundStyle(Color.primary.opacity(w.isEstimate ? 0.85 : 1))
                    Spacer()
                    Text(condition.rawValue).font(.subheadline.weight(.semibold))
                }
                // Side by side when the note fits on one line; else the note sits under the tag at
                // full width (not squeezed into a narrow column beside it).
                ViewThatFits(in: .horizontal) {
                    HStack(spacing: 8) {
                        SourceTag(source: w.source)
                        Text(w.detail).font(.caption).foregroundStyle(Theme.muted).lineLimit(1).fixedSize()
                    }
                    VStack(alignment: .leading, spacing: 6) {
                        SourceTag(source: w.source)
                        Text(w.detail.noWidow).font(.caption).foregroundStyle(Theme.muted)
                    }
                }
                if condition != .nearMint {
                    let diff = w.price - nm
                    (Text(Format.signedMoney(diff)).foregroundStyle(Theme.tone(diff)) + Text(" vs Near Mint (\(Format.money(nm)))").foregroundStyle(Theme.muted))
                        .font(.caption).monospacedDigit()
                }
                HStack(spacing: 6) {
                    ForEach(CardCondition.allCases) { c in
                        Button(c.short) { condition = c }
                            .font(.footnote.weight(.semibold))
                            .frame(maxWidth: .infinity, minHeight: 38)
                            // Unpicked ones a faint white, so they stand off the blue panel.
                            .background(condition == c ? c.tint.opacity(0.22) : Color.white.opacity(0.1), in: RoundedRectangle(cornerRadius: 10))
                            .overlay(RoundedRectangle(cornerRadius: 10).stroke(condition == c ? c.tint : .clear, lineWidth: 1.5))
                            .foregroundStyle(condition == c ? c.tint : Color.white.opacity(0.8))
                    }
                }
                .sensoryFeedback(.selection, trigger: condition)
                if let url = store.products[productId]?.tcgplayerUrl.flatMap(URL.init(string:)) {
                    Link(destination: url) {
                        HStack(spacing: 8) {
                            Text("View on TCGplayer")
                            Image(systemName: "arrow.up.right").font(.system(size: 13, weight: .semibold))
                        }
                        .frame(maxWidth: .infinity)
                    }
                    .buttonStyle(Button3D(kind: .blue, height: 46))
                    .padding(.top, 4)
                }
            }
        }
        // The tint adds 16 of its own: 4 more makes the 20 the other panels have.
        .padding(4)
        .tinted(Theme.planBlue)
        .task(id: "\(productId)|\(printing ?? "")") { await load() }
        .onAppear {
            // Open on the condition you own.
            if let raw = owned.first(where: { !$0.identity.isGraded }), let c = CardCondition(rawValue: raw.identity.condition) {
                condition = c
            }
        }
    }

    private func load() async {
        guard productId.hasPrefix("tcgapi:") else { return loaded = true }
        async let sales = try? EbaySalesCache.sales(productId, printing: printing)
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
        if source == .estimate {
            EstimatePill()
        } else {
            let label = ["market": "Market price", "sales": "eBay sales", "guide": "Price guide"][source.rawValue] ?? ""
            let icon = ["market": "chart.line.uptrend.xyaxis", "sales": "checkmark.seal.fill", "guide": "book.closed.fill"][source.rawValue] ?? "circle"
            HStack(spacing: 4) {
                Image(systemName: icon).font(.system(size: 9, weight: .bold))
                Text(label).font(.geist(11, .semibold))
            }
            .padding(.horizontal, 8).padding(.vertical, 3)
            .foregroundStyle(source == .sales ? Theme.up : Color.white.opacity(0.85))
            .background(source == .sales ? Theme.lime.opacity(0.16) : Color.white.opacity(0.08), in: Capsule())
        }
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


/// TCGplayer's logo (the owner's file, in the asset catalog as a vector), marking where these
/// prices come from, sized like the eBay panel's wordmark.
private struct TCGplayerMark: View {
    var body: some View {
        Image("TCGplayerLogo")
            .resizable()
            .scaledToFit()
            .frame(height: 26)
            .accessibilityLabel("TCGplayer")
    }
}
