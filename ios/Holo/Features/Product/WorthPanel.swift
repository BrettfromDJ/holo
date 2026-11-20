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

    /// The card's TCGplayer page: its stored link, else one built from its TCGplayer number.
    private var tcgplayerURL: URL? {
        let p = store.products[productId]
        if let u = p?.tcgplayerUrl.flatMap(URL.init(string:)) { return u }
        if let id = p?.tcgplayerId { return URL(string: "https://www.tcgplayer.com/product/\(id)") }
        return nil
    }

    var body: some View {
        // Just the button: "View on" and TCGplayer's logo, opening the card's TCGplayer page.
        // No figures (our source can't say which condition TCGplayer's are for).
        if let url = tcgplayerURL {
            Link(destination: url) {
                HStack(spacing: 8) {
                    Text("View on")
                    Image("TCGplayerLogo").resizable().scaledToFit().frame(height: 18)
                        .accessibilityLabel("TCGplayer")
                    Image(systemName: "arrow.up.right").font(.system(size: 13, weight: .semibold))
                }
                .frame(maxWidth: .infinity)
            }
            .buttonStyle(Button3D(kind: .blue, height: 50, sheen: false))
            .overlay {
                TCGGlint()
                    .clipShape(RoundedRectangle(cornerRadius: 14, style: .continuous))
                    .offset(y: -1)
                    .allowsHitTesting(false)
            }
        }
    }
}

/// The TCGplayer button's shine: one wide, soft glow (a gradient with long fades, so it reads as
/// blurred without any per-frame blur), added light so the blue brightens instead of greying. It
/// drifts across slowly, easing in and out, then rests off the button. One looping offset
/// animation set once, only while on screen; still with Reduce Motion.
private struct TCGGlint: View {
    @Environment(\.accessibilityReduceMotion) private var reduceMotion
    @State private var across = false

    var body: some View {
        if !reduceMotion {
            LinearGradient(stops: [
                .init(color: .clear, location: 0),
                .init(color: .white.opacity(0.06), location: 0.25),
                .init(color: .white.opacity(0.22), location: 0.5),
                .init(color: .white.opacity(0.06), location: 0.75),
                .init(color: .clear, location: 1),
            ], startPoint: .leading, endPoint: .trailing)
            .frame(width: 140)
            .scaleEffect(x: 1, y: 3)
            .rotationEffect(.degrees(18))
            .frame(maxWidth: .infinity, maxHeight: .infinity)
            .offset(x: across ? 700 : -700)
            .blendMode(.plusLighter)
            .onVisibilityChange { on in
                if on {
                    withAnimation(.timingCurve(0.45, 0, 0.55, 1, duration: 8).repeatForever(autoreverses: false)) { across = true }
                } else {
                    stopLoop { across = false }
                }
            }
        }
    }
}
