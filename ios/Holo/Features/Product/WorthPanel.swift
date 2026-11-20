import SwiftUI

/// TCGplayer's market price for the card (what Near Mint copies actually sold for) and a link
/// to its TCGplayer page. Per-condition prices were dropped on purpose: our source only has
/// asking prices for played copies, too often wrong or out of order. Same as the website's
/// `WhatsItWorth`.
struct WorthPanel: View {
    var productId: String
    var printing: String?
    var nm: Double
    var owned: [HoldingView]
    @Environment(CollectionStore.self) private var store

    /// The card's TCGplayer page: its stored link, else one built from its TCGplayer number.
    private var tcgplayerURL: URL? {
        let p = store.products[productId]
        if let u = p?.tcgplayerUrl.flatMap(URL.init(string:)) { return u }
        if let id = p?.tcgplayerId { return URL(string: "https://www.tcgplayer.com/product/\(id)") }
        return nil
    }

    var body: some View {
        VStack(alignment: .leading, spacing: 16) {
            // Laid out like the eBay panel: the title on the left, the source's logo on the right.
            HStack(alignment: .top, spacing: 12) {
                VStack(alignment: .leading, spacing: 2) {
                    Text("TCGplayer market price").font(.geist(15, .semibold))
                    Text("Near Mint, from recent sales").font(.geist(12)).foregroundStyle(Theme.muted)
                }
                Spacer(minLength: 0)
                TCGplayerMark()
            }
            Text(Format.money(nm)).font(.display(52)).tracking(-2.1).monospacedDigit()
                .lineLimit(1).minimumScaleFactor(0.6)
            if let url = tcgplayerURL {
                Link(destination: url) {
                    HStack(spacing: 8) {
                        Text("View on TCGplayer")
                        Image(systemName: "arrow.up.right").font(.system(size: 13, weight: .semibold))
                    }
                    .frame(maxWidth: .infinity)
                }
                .buttonStyle(Button3D(kind: .blue, height: 46))
            }
        }
        // The tint adds 16 of its own: 4 more makes the 20 the other panels have.
        .padding(4)
        .tinted(Theme.planBlue)
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
