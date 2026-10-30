import SwiftUI

/// What the card is actually selling for: the last 30 days of eBay sales, each linking to its listing.
struct EbaySalesPanel: View {
    var productId: String
    var printing: String?
    /// Opens on this grade when you own a slab.
    var grade: String?

    @State private var ebay: EbaySales?
    @State private var state = LoadState.loading
    @State private var filter = "All"
    @State private var showAll = false

    enum LoadState { case loading, ready, failed }

    private var grades: [String] { ebay.map { $0.graded.keys.sorted { gradeOrder($0) > gradeOrder($1) } } ?? [] }
    private var shown: [EbaySale] {
        let sales = ebay?.sales ?? []
        switch filter {
        case "All": return sales
        case "Raw": return sales.filter { $0.grade == nil }
        default: return sales.filter { $0.grade == filter }
        }
    }

    var body: some View {
        Panel {
            VStack(alignment: .leading, spacing: 12) {
                HStack {
                    CardLabel(text: "Recent eBay sales")
                    Spacer()
                    Text("eBay").font(.system(size: 15, weight: .heavy)).foregroundStyle(.white.opacity(0.85))
                }
                switch state {
                case .loading:
                    ProgressView().frame(maxWidth: .infinity)
                case .failed:
                    Text("Couldn't load eBay sales right now.").font(.callout).foregroundStyle(Theme.muted)
                case .ready:
                    if let e = ebay, !e.sales.isEmpty {
                        summary(e)
                        ScrollView(.horizontal, showsIndicators: false) {
                            HStack(spacing: 6) {
                                ForEach(["All", "Raw"] + grades, id: \.self) { f in
                                    Button(f) { filter = f }
                                        .font(.caption.weight(.semibold))
                                        .padding(.horizontal, 10).padding(.vertical, 6)
                                        .background(filter == f ? Color.white : Theme.surface2, in: Capsule())
                                        .foregroundStyle(filter == f ? Theme.ink : .primary)
                                }
                            }
                        }
                        ForEach(Array(shown.prefix(showAll ? 50 : 6))) { s in SaleRow(sale: s) }
                        if shown.count > 6 {
                            Button(showAll ? "Show fewer" : "Show all \(shown.count)") { withAnimation { showAll.toggle() } }
                                .font(.footnote.weight(.medium)).foregroundStyle(Theme.muted)
                        }
                    } else {
                        Text("No eBay sales in the last 30 days.").font(.callout).foregroundStyle(Theme.muted)
                    }
                }
            }
        }
        .task(id: "\(productId)|\(printing ?? "")") { await load() }
    }

    private func summary(_ e: EbaySales) -> some View {
        let stats = filter == "All" || filter == "Raw" ? e.ungraded : (e.graded[filter] ?? e.ungraded)
        return HStack(spacing: 20) {
            VStack(alignment: .leading, spacing: 2) {
                Text("Median").font(.caption2).foregroundStyle(Theme.muted).textCase(.uppercase)
                Text(Format.money(stats.median)).font(.title3.weight(.bold)).monospacedDigit()
            }
            VStack(alignment: .leading, spacing: 2) {
                Text("Sold").font(.caption2).foregroundStyle(Theme.muted).textCase(.uppercase)
                Text("\(stats.count)").font(.title3.weight(.bold)).monospacedDigit()
            }
            VStack(alignment: .leading, spacing: 2) {
                Text("Last sale").font(.caption2).foregroundStyle(Theme.muted).textCase(.uppercase)
                Text(Format.money(stats.lastPrice)).font(.title3.weight(.bold)).monospacedDigit()
            }
        }
    }

    private func gradeOrder(_ label: String) -> Double {
        Double(label.split(separator: " ").last ?? "") ?? 0
    }

    private func load() async {
        guard productId.hasPrefix("tcgapi:") else { return state = .ready }
        do {
            ebay = try await Backend.shared.api.ebaySales(productId, printing: printing)
            if let grade, ebay?.graded[grade] != nil { filter = grade }
            state = .ready
        } catch {
            state = .failed
        }
    }
}

private struct SaleRow: View {
    var sale: EbaySale

    var body: some View {
        Link(destination: URL(string: sale.url) ?? URL(string: "https://www.ebay.com")!) {
            HStack(alignment: .top, spacing: 10) {
                VStack(alignment: .leading, spacing: 4) {
                    Text(sale.title).font(.caption).lineLimit(2).multilineTextAlignment(.leading).foregroundStyle(Color.white)
                    HStack(spacing: 6) {
                        if let g = sale.grade {
                            Tag(text: g, tint: .white)
                        } else if let c = CardCondition.from(label: sale.condition) {
                            Tag(text: c.short, tint: c.tint)
                        }
                        Text(dateLabel).font(.caption2).foregroundStyle(Theme.muted)
                        if sale.bestOffer { Text("Best offer").font(.caption2).foregroundStyle(Theme.muted) }
                    }
                }
                Spacer()
                Text(Format.money(sale.price)).font(.subheadline.weight(.semibold)).monospacedDigit().foregroundStyle(Theme.lime)
            }
        }
    }

    private var dateLabel: String {
        let d = Format.isoDay.date(from: String(sale.soldDate.prefix(10)))
        return d?.formatted(.dateTime.month(.abbreviated).day()) ?? sale.soldDate
    }
}
