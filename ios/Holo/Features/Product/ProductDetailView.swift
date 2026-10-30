import Charts
import SwiftUI

/// One card or product: its market price, price history and the copies you own.
struct ProductDetailView: View {
    var productId: String
    @Environment(CollectionStore.self) private var store
    @State private var adding = false

    private var product: Product? { store.products[productId] }
    private var owned: [HoldingView] { store.holdings(for: productId) }
    private var printing: String? { owned.first?.identity.printing ?? product?.printings?.first }
    private var price: Price? { store.marketPrice(productId, printing: printing) }
    private var points: [PricePoint] { store.history[priceKey(productId, printing)] ?? [] }

    var body: some View {
        ScrollView {
            VStack(alignment: .leading, spacing: 20) {
                ProductImage(product: product, cornerRadius: 14)
                    .frame(maxWidth: 280)
                    .frame(maxWidth: .infinity)
                    .shadow(color: .black.opacity(0.5), radius: 24, y: 12)

                VStack(alignment: .leading, spacing: 4) {
                    Text(product?.name ?? "Unknown").font(.title.bold())
                    Text([product?.subtitle, printing].compactMap { $0 }.filter { !$0.isEmpty }.joined(separator: " · "))
                        .foregroundStyle(Theme.muted)
                }

                VStack(alignment: .leading, spacing: 8) {
                    Text(Format.money(price?.market))
                        .font(.system(size: 44, weight: .heavy, design: .rounded))
                        .monospacedDigit()
                    // The headline is the Near Mint (ungraded) price; your copies that differ are listed below.
                    Text(product?.isSealed == true ? "Market price" : "Near Mint market price").font(.caption).foregroundStyle(Theme.muted)
                    HStack(spacing: 8) {
                        change("24h", price?.change24hPct)
                        change("7d", price?.change7dPct)
                        change("30d", price?.change30dPct)
                    }
                }

                if points.count > 1 {
                    Panel {
                        VStack(alignment: .leading, spacing: 10) {
                            Text("Price history").font(.headline)
                            Chart(points) { p in
                                LineMark(x: .value("Date", p.day), y: .value("Price", p.price))
                                    .foregroundStyle(Theme.lime)
                                    .interpolationMethod(.monotone)
                            }
                            .chartYAxis { AxisMarks(position: .trailing) }
                            .frame(height: 180)
                        }
                    }
                }

                if !owned.isEmpty {
                    Panel {
                        VStack(alignment: .leading, spacing: 12) {
                            Text("Your copies").font(.headline)
                            ForEach(owned) { h in
                                HStack {
                                    VStack(alignment: .leading, spacing: 2) {
                                        HStack(spacing: 6) {
                                            Text(h.label ?? (product?.isSealed == true ? "Sealed" : "Near Mint")).font(.subheadline.weight(.medium))
                                            Text("×\(Int(h.quantity))").font(.subheadline).foregroundStyle(Theme.muted)
                                        }
                                        Text("Paid \(Format.money(h.costBasis))").font(.caption).foregroundStyle(Theme.muted)
                                    }
                                    Spacer()
                                    VStack(alignment: .trailing, spacing: 2) {
                                        Text((h.isConditionEstimate ? "≈ " : "") + Format.money(h.value)).font(.subheadline.weight(.semibold)).monospacedDigit()
                                        Text(Format.signedMoney(h.gain)).font(.caption.weight(.medium)).monospacedDigit().foregroundStyle(Theme.tone(h.gain))
                                    }
                                }
                            }
                            if owned.contains(where: \.isConditionEstimate) {
                                Text("≈ Played copies are estimated from the Near Mint price.").font(.caption).foregroundStyle(Theme.muted)
                            }
                            if owned.contains(where: { $0.identity.isGraded && $0.price == nil }) {
                                Text("Graded copies show a value once you set one on the website.").font(.caption).foregroundStyle(Theme.muted)
                            }
                        }
                    }
                }

                if let product {
                    Button { adding = true } label: { Label(owned.isEmpty ? "Add to collection" : "Add more", systemImage: "plus") }
                        .buttonStyle(LimeButtonStyle())
                        .sheet(isPresented: $adding) {
                            AddPurchaseSheet(hit: SearchHit(product: product, printing: printing, market: price?.market))
                        }
                }
                if let url = product?.tcgplayerUrl.flatMap(URL.init(string:)) {
                    Link(destination: url) { Label("View on TCGplayer", systemImage: "arrow.up.right.square") }
                        .font(.callout)
                        .foregroundStyle(Theme.muted)
                }
            }
            .padding(16)
            .padding(.bottom, 80)
        }
        .background(Theme.background)
        .navigationBarTitleDisplayMode(.inline)
    }

    private func change(_ label: String, _ pct: Double?) -> some View {
        HStack(spacing: 4) {
            Text(label).foregroundStyle(Theme.muted)
            Text(Format.signedPercent(pct.map { $0 / 100 })).monospacedDigit().foregroundStyle(Theme.tone(pct))
        }
        .font(.caption.weight(.medium))
        .padding(.horizontal, 10)
        .padding(.vertical, 5)
        .background(Theme.surface, in: Capsule())
    }
}
