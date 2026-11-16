import SwiftUI

/// What a price is and where it comes from, for a tap on any headline figure (a card's price,
/// your copy's worth, your collection's total). No text on the page itself: the answer is here.
struct PriceInfo: Identifiable {
    var id = UUID()
    /// What the figure is: "Near Mint · ungraded", "Your PSA 10", "Your collection".
    var title: String
    var value: Double?
    /// Label and value rows: Source, Updated, Printing…
    var rows: [(String, String)] = []
    /// Cross-checked against eBay's recent sold prices (cards only): this product, printing and grade.
    var ebay: (productId: String, printing: String?, grade: String?)? = nil
    /// A line under the rows, when there's something to explain (how an estimate was made).
    var note: String? = nil
    /// A price more than 3 days old.
    var stale = false
    /// One copy's price, for the eBay comparison when `value` is several copies (defaults to `value`).
    var each: Double? = nil
}

struct PriceInfoSheet: View {
    var info: PriceInfo
    @Environment(\.dismiss) private var dismiss
    @State private var sales: EbaySales?
    @State private var loaded = false

    var body: some View {
        ScrollView {
            VStack(alignment: .leading, spacing: 18) {
                HStack {
                    MonoLabel(text: "Where this price comes from")
                    Spacer()
                    Button("Done") { dismiss() }.font(.geist(15, .semibold)).foregroundStyle(Theme.lime)
                }
                VStack(alignment: .leading, spacing: 4) {
                    Text(info.title).font(.geist(14)).foregroundStyle(Theme.muted)
                    Text(Format.money(info.value)).font(.display(40)).tracking(-1.4).monospacedDigit().displayTrim(40)
                        .opacity(info.stale ? 0.6 : 1)
                }
                VStack(spacing: 0) {
                    ForEach(Array(rows.enumerated()), id: \.offset) { i, row in
                        if i > 0 { Rectangle().fill(Color.white.opacity(0.08)).frame(height: 1) }
                        HStack(alignment: .firstTextBaseline) {
                            Text(row.0).font(.geist(14)).foregroundStyle(Theme.muted)
                            Spacer(minLength: 12)
                            Text(row.1).font(.geist(14, .medium)).monospacedDigit().multilineTextAlignment(.trailing)
                        }
                        .padding(.vertical, 11)
                    }
                }
                .padding(.horizontal, 14)
                .sheetPanel(radius: 16)
                if let note = info.note {
                    Text(note.noWidow).font(.geist(13)).foregroundStyle(Theme.muted)
                }
            }
            .foregroundStyle(.white)
            .padding(20)
        }
        .glassSheet()
        .presentationDetents([.medium, .large])
        .presentationDragIndicator(.visible)
        .task {
            guard let e = info.ebay, EbaySalesCache.supports(e.productId) else { loaded = true; return }
            sales = try? await EbaySalesCache.sales(e.productId, printing: e.printing, market: info.each ?? info.value)
            loaded = true
        }
    }

    /// The given rows, then what eBay's recent sales say (when this is a card with sales).
    private var rows: [(String, String)] {
        var out = info.rows
        guard let e = info.ebay, EbaySalesCache.supports(e.productId) else { return out }
        guard loaded else { out.append(("eBay sold, 30 days", "Checking…")); return out }
        let stats = e.grade.flatMap { sales?.graded[$0] } ?? (e.grade == nil ? sales?.ungraded : nil)
        guard let stats, let median = stats.median, stats.count > 0 else {
            out.append(("eBay sold, 30 days", "No sales"))
            return out
        }
        out.append(("eBay sold, 30 days", "\(Format.money(median)) median · \(stats.count) sale\(stats.count == 1 ? "" : "s")"))
        // The spread of those sales, as a likely range.
        let prices = (sales?.sales ?? []).filter { $0.grade == e.grade }.map(\.price)
        if prices.count >= 3, let lo = prices.min(), let hi = prices.max() {
            out.append(("Recent sales range", "\(Format.money(lo)) – \(Format.money(hi))"))
        }
        if let value = info.each ?? info.value, median > 0, stats.count >= 3 {
            let off = value / median - 1
            out.append(("Against eBay", abs(off) <= 0.15 ? "Agrees" : "\(Format.signedPercent(off)) vs median"))
        }
        return out
    }
}

extension PriceInfo {
    /// "3h ago", "2d ago" for a timestamp; nil when unknown.
    static func age(_ iso: String?) -> String? {
        guard let iso, let date = ISOTime.plain.date(from: iso) ?? Format.isoDay.date(from: String(iso.prefix(10))) else { return nil }
        let hours = Int(Date().timeIntervalSince(date) / 3600)
        if hours < 1 { return "just now" }
        if hours < 24 { return "\(hours)h ago" }
        return "\(hours / 24)d ago"
    }

    /// More than 3 days old.
    static func isStale(_ iso: String?) -> Bool {
        guard let iso, let date = ISOTime.plain.date(from: iso) ?? Format.isoDay.date(from: String(iso.prefix(10))) else { return false }
        return Date().timeIntervalSince(date) > 3 * 86_400
    }
}
