import SwiftUI

/// A link to the card on TCGplayer, with its logo. No prices: our source can't say which
/// condition TCGplayer's figures are for, so TCGplayer shows them itself. Same as the
/// website's `WhatsItWorth`.
struct WorthPanel: View {
    var productId: String
    var printing: String?
    var nm: Double
    var owned: [HoldingView]
    @Environment(CollectionStore.self) private var store

    /// The card's TCGplayer page: its stored link, else one built from its TCGplayer number,
    /// opened on the printing shown here and Near Mint (TCGplayer otherwise opens on whatever
    /// it likes, often the cheaper printing in Lightly Played).
    private var tcgplayerURL: URL? {
        let p = store.products[productId]
        let base = p?.tcgplayerUrl.flatMap(URL.init(string:)) ?? p?.tcgplayerId.flatMap { URL(string: "https://www.tcgplayer.com/product/\($0)") }
        guard let base else { return nil }
        return Self.withPrinting(base, printing: printing ?? p?.printings?.first, sealed: p?.isSealed == true)
    }

    /// Adds TCGplayer's own filters for printing and condition to a product page link.
    static func withPrinting(_ url: URL, printing: String?, sealed: Bool) -> URL {
        guard url.path.contains("/product/"), var c = URLComponents(url: url, resolvingAgainstBaseURL: false) else { return url }
        var items = (c.queryItems ?? []).filter { !["Printing", "Condition", "Language"].contains($0.name) }
        items.append(URLQueryItem(name: "Language", value: "English"))
        if let printing, !printing.isEmpty { items.append(URLQueryItem(name: "Printing", value: printing)) }
        if !sealed { items.append(URLQueryItem(name: "Condition", value: "Near Mint")) }
        c.queryItems = items
        return c.url ?? url
    }

    var body: some View {
        // A quiet Liquid Glass button, text only, under Add to Collection.
        if let url = tcgplayerURL {
            Link(destination: url) {
                HStack(spacing: 6) {
                    Text("View on TCGplayer")
                    Image(systemName: "arrow.up.right").font(.system(size: 12, weight: .semibold))
                }
                .font(.geist(15, .semibold))
                .foregroundStyle(.white)
                .frame(maxWidth: .infinity, minHeight: 46)
                .contentShape(Rectangle())
                .liquidGlass(in: RoundedRectangle(cornerRadius: 14, style: .continuous), interactive: true)
            }
            .buttonStyle(.plain)
        }
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


