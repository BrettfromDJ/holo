import SwiftUI

/// Home: what the collection is worth, and everything in it.
struct CollectionView: View {
    var onScan: () -> Void
    @Environment(CollectionStore.self) private var store
    @Environment(SessionModel.self) private var session
    @State private var adding = false

    private let columns = [GridItem(.flexible(), spacing: 14), GridItem(.flexible(), spacing: 14)]

    var body: some View {
        NavigationStack {
            ScrollView {
                switch store.status {
                case .idle, .loading:
                    ProgressView().padding(.top, 120)
                case let .failed(message):
                    VStack(spacing: 12) {
                        Text("Couldn't load your collection").font(.headline)
                        Text(message).font(.callout).foregroundStyle(Theme.muted).multilineTextAlignment(.center)
                        Button("Try again") { reload() }
                    }
                    .padding(32)
                case .ready:
                    if store.holdings.isEmpty {
                        empty
                    } else {
                        VStack(alignment: .leading, spacing: 20) {
                            header
                            LazyVGrid(columns: columns, spacing: 22) {
                                ForEach(store.holdings) { h in
                                    NavigationLink(value: h.identity.productId) { HoldingTile(holding: h) }
                                        .buttonStyle(.plain)
                                }
                            }
                        }
                        .padding(.horizontal, 16)
                        .padding(.bottom, 100)
                    }
                }
            }
            .background(Theme.background)
            .refreshable { await reloadNow() }
            .navigationTitle("Collection")
            .toolbar {
                ToolbarItem(placement: .topBarTrailing) {
                    Button { adding = true } label: { Image(systemName: "plus") }
                        .accessibilityLabel("Add to collection")
                }
            }
            .navigationDestination(for: String.self) { ProductDetailView(productId: $0) }
            .sheet(isPresented: $adding) { SearchView(asSheet: true) }
        }
    }

    private var header: some View {
        let s = store.summary
        return VStack(alignment: .leading, spacing: 6) {
            Text("\(Int(s.items)) items").font(.caption.weight(.medium)).foregroundStyle(Theme.muted).textCase(.uppercase)
            Text(Format.money(s.value))
                .font(.system(size: 44, weight: .heavy, design: .rounded))
                .monospacedDigit()
                .foregroundStyle(Theme.lime)
                .minimumScaleFactor(0.6)
                .lineLimit(1)
            HStack(spacing: 14) {
                stat("Today", Format.signedMoney(s.dayChange), Theme.tone(s.dayChange))
                stat("All time", Format.signedMoney(s.gain), Theme.tone(s.gain))
                stat("Invested", Format.money(s.totalCost), .primary)
            }
            if s.unpriced > 0 {
                Text("\(s.unpriced) without a price aren't counted.").font(.caption).foregroundStyle(Theme.muted)
            }
        }
        .padding(.top, 8)
    }

    private func stat(_ label: String, _ value: String, _ tint: Color) -> some View {
        VStack(alignment: .leading, spacing: 2) {
            Text(label).font(.caption2).foregroundStyle(Theme.muted).textCase(.uppercase)
            Text(value).font(.subheadline.weight(.semibold)).monospacedDigit().foregroundStyle(tint)
        }
    }

    private var empty: some View {
        VStack(spacing: 14) {
            Image(systemName: "rectangle.stack.badge.plus").font(.system(size: 44)).foregroundStyle(Theme.lime)
            Text("Start your collection").font(.title3.bold())
            Text("Scan your cards, or search for anything you own.").foregroundStyle(Theme.muted).multilineTextAlignment(.center)
            Button { onScan() } label: { Label("Scan cards", systemImage: "viewfinder") }
                .buttonStyle(LimeButtonStyle())
            Button("Search instead") { adding = true }.foregroundStyle(Theme.muted)
        }
        .padding(32)
        .padding(.top, 60)
    }

    private func reload() { Task { await reloadNow() } }

    private func reloadNow() async {
        if case let .signedIn(userId, _) = session.state { await store.load(userId: userId) }
    }
}

/// A card-forward tile: picture, name, value and gain.
struct HoldingTile: View {
    var holding: HoldingView

    var body: some View {
        VStack(alignment: .leading, spacing: 6) {
            ZStack(alignment: .topLeading) {
                ProductImage(product: holding.product)
                    .frame(maxWidth: .infinity)
                    .aspectRatio(5.0 / 7.0, contentMode: .fit)
                HStack {
                    if holding.quantity > 1 { Tag(text: "×\(Int(holding.quantity))", tint: .white) }
                    Spacer()
                    if let label = holding.label { Tag(text: label, tint: .white) }
                }
                .padding(6)
            }
            Text(holding.product?.name ?? "Unknown").font(.subheadline.weight(.medium)).lineLimit(1)
            Text(holding.product?.setName ?? "").font(.caption).foregroundStyle(Theme.muted).lineLimit(1)
            HStack(alignment: .firstTextBaseline) {
                Text((holding.isConditionEstimate ? "≈ " : "") + Format.money(holding.value))
                    .font(.system(size: 18, weight: .bold, design: .rounded))
                    .monospacedDigit()
                Spacer()
                Text(Format.signedPercent(holding.gainRatio))
                    .font(.caption.weight(.semibold))
                    .monospacedDigit()
                    .foregroundStyle(Theme.tone(holding.gainRatio))
            }
        }
    }
}
