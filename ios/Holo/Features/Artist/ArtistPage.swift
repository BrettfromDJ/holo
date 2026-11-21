import SwiftUI

/// One artist's page: every card they drew, priciest first, under their top card's art blurred
/// (like a collection's page). Opened from "Illustrated by …" on a card page. Same as the web's
/// /artist/<name>.
struct ArtistPage: View {
    var name: String
    @State private var cards: [SearchHit]?

    var body: some View {
        ScrollView {
            VStack(alignment: .leading, spacing: 20) {
                VStack(alignment: .leading, spacing: 8) {
                    MonoLabel(text: "Illustrator")
                    DisplayText(text: name, size: 34)
                    if let cards { Text(cards.count == 1 ? "1 card" : "\(cards.count) cards").font(.mono(11)).foregroundStyle(Theme.subtle).padding(.top, 2) }
                }
                if let cards {
                    if cards.isEmpty {
                        Text("No cards found for this artist yet.").font(.geist(15)).foregroundStyle(Theme.muted)
                    } else {
                        LazyVGrid(columns: Array(repeating: GridItem(.flexible(), spacing: 12), count: 3), alignment: .leading, spacing: 18) {
                            ForEach(cards) { hit in
                                MarketLink(hit: hit) {
                                    VStack(alignment: .leading, spacing: 5) {
                                        ProductImage(product: hit.pictured, cornerRadius: 5).aspectRatio(63 / 88, contentMode: .fit)
                                        Text(hit.product.name).font(.geist(12, .medium)).foregroundStyle(.white).lineLimit(1)
                                        Text(hit.product.setName ?? "").font(.geist(11)).foregroundStyle(Theme.muted).lineLimit(1)
                                        Text(Format.money(hit.market)).font(.geist(13, .semibold)).monospacedDigit().foregroundStyle(.white)
                                    }
                                    .contentShape(Rectangle())
                                }
                            }
                        }
                        .cardSequence(cards.map(\.product.id))
                    }
                } else {
                    // Dim, still placeholders while the cards load (no spinner).
                    LazyVGrid(columns: Array(repeating: GridItem(.flexible(), spacing: 12), count: 3), spacing: 18) {
                        ForEach(0..<9, id: \.self) { _ in
                            RoundedRectangle(cornerRadius: 5, style: .continuous).fill(Color.white.opacity(0.05)).aspectRatio(63 / 88, contentMode: .fit)
                        }
                    }
                }
            }
            .padding(.horizontal, 16)
            .padding(.top, 8)
            .padding(.bottom, 40)
            .background(alignment: .top) {
                if let url = cards?.first?.pictured.imageURL { ArtBackdrop(url: url, blur: 40) }
            }
        }
        .background(Theme.background)
        .tabBarClearance()
        .navigationBarTitleDisplayMode(.inline)
        .task(id: name) {
            cards = (try? await Backend.shared.api.artistCards(name)) ?? []
        }
    }
}
