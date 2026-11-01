import SwiftUI

/// The "Sells fast" meter: three small segments (lime for fast and steady, one pink for slow),
/// the tier, then "82% · 14 sold this month" with only the percentage colored. Same as the
/// website's `SellSpeedMeter`. `compact` shows just the segments and the tier (the Deal tab).
struct SellSpeedMeter: View {
    var score: Liquidity.Score
    var compact = false
    @State private var explain = false

    private var percentColor: Color {
        score.score >= 70 ? Theme.lime : score.score >= 40 ? .white : Theme.planPink
    }

    var body: some View {
        if compact {
            HStack(spacing: 6) {
                SellSpeedBar(tier: score.tier, small: true)
                Text(score.tier.rawValue).font(.geist(11)).foregroundStyle(Theme.muted).lineLimit(1)
            }
            .accessibilityElement(children: .ignore)
            .accessibilityLabel(score.tier.rawValue)
        } else {
            VStack(alignment: .leading, spacing: 6) {
                Button { explain.toggle() } label: {
                    HStack(spacing: 8) {
                        SellSpeedBar(tier: score.tier, small: false)
                        Text(score.tier.rawValue).font(.geist(14, .semibold)).foregroundStyle(.white).lineLimit(1)
                        (Text("\(score.score)%").foregroundColor(percentColor) + Text(" · \(score.sold) sold this month").foregroundColor(Theme.muted))
                            .font(.geist(13)).monospacedDigit().lineLimit(1).minimumScaleFactor(0.8)
                        Spacer(minLength: 0)
                        Image(systemName: "info.circle").font(.system(size: 13)).foregroundStyle(Theme.subtle)
                    }
                    .contentShape(Rectangle())
                }
                .buttonStyle(.plain)
                .accessibilityLabel("\(score.tier.rawValue), \(score.score) percent, \(score.sold) sold this month")
                .accessibilityHint("Explains the score")
                if explain {
                    Text(Liquidity.note).font(.geist(12)).foregroundStyle(Theme.muted).fixedSize(horizontal: false, vertical: true)
                }
            }
        }
    }
}

/// Three segments: 3 filled for Sells fast, 2 for Sells steady, 1 (pink) for Slow to sell.
struct SellSpeedBar: View {
    var tier: Liquidity.Tier
    var small = false

    var body: some View {
        let fill = tier == .slow ? Theme.planPink : Theme.lime
        HStack(spacing: 2) {
            ForEach(0..<3, id: \.self) { i in
                Capsule()
                    .fill(i < tier.segments ? fill : Color.white.opacity(0.14))
                    .frame(width: small ? 7 : 10, height: small ? 4 : 6)
            }
        }
        .accessibilityHidden(true)
    }
}

/// The meter for one copy (a grade label for slabs, else ungraded), from the shared eBay cache.
/// Its own small view with plain values, so the Owned sheet doesn't redraw for it. Hidden for
/// products without eBay data.
struct SellSpeedLine: View {
    var productId: String
    var printing: String?
    var grade: String?
    var market: Double?
    /// For a CGC 10: score on Pristine sales (true) or Gem Mint ones (false); nil scores every sale of the grade.
    var pristine: Bool? = nil

    @State private var score: Liquidity.Score?
    @State private var state = LoadState.loading

    private enum LoadState { case loading, ready, hidden }

    var body: some View {
        Group {
            switch state {
            case .loading:
                ProgressView().controlSize(.small).tint(Theme.lime)
                    .frame(maxWidth: .infinity, minHeight: 20, alignment: .leading)
                    .sellSpeedPanel()
            case .ready:
                Group {
                    if let score {
                        SellSpeedMeter(score: score)
                    } else {
                        HStack(spacing: 8) {
                            SellSpeedBar(tier: .slow).opacity(0.35)
                            Text("Not enough sales yet").font(.geist(13)).foregroundStyle(Theme.muted)
                        }
                        .frame(maxWidth: .infinity, alignment: .leading)
                    }
                }
                .sellSpeedPanel()
            case .hidden:
                EmptyView()
            }
        }
        .task(id: taskKey) { await load() }
    }

    private var taskKey: String {
        let kind: String
        switch pristine {
        case .some(true): kind = "pristine"
        case .some(false): kind = "gem"
        case .none: kind = ""
        }
        return "\(productId)|\(printing ?? "")|\(grade ?? "")|\(kind)"
    }

    private func load() async {
        guard EbaySalesCache.supports(productId) else { return state = .hidden }
        let ebay: EbaySales? = (try? await EbaySalesCache.sales(productId, printing: printing, market: market)) ?? nil
        guard let ebay else { return state = .hidden }
        score = Liquidity.score(ebay, grade: grade, today: Format.day(), pristine: pristine)
        state = .ready
    }
}

private extension View {
    /// A faint white panel that reads on the glass sheet, like the worth tiles.
    func sellSpeedPanel() -> some View {
        padding(.horizontal, 12).padding(.vertical, 11).sheetPanel(radius: 14)
    }
}
