import SwiftUI

/// Recent eBay sold listings, laid out like the website: the 30-day median, how many sold and
/// the last sale for ungraded copies or any grade that has sold, then the sales themselves,
/// each linking to its listing. Opens on `grade` when you own a slab that has sold.
struct EbaySalesPanel: View {
    var productId: String
    var printing: String?
    /// Opens on this grade when you own a slab.
    var grade: String?

    @State private var ebay: EbaySales?
    @State private var state = LoadState.loading
    @State private var tab = ungradedTab
    @State private var showAll = false

    enum LoadState { case loading, ready, failed }

    private static let ungradedTab = "Ungraded"

    /// Grades that have sold, most sales first.
    private var labels: [String] {
        guard let ebay else { return [] }
        return ebay.graded.sorted { $0.value.count > $1.value.count }.map(\.key)
    }

    private var sales: [EbaySale] {
        let all = ebay?.sales ?? []
        return tab == Self.ungradedTab ? all.filter { $0.grade == nil } : all.filter { $0.grade == tab }
    }

    var body: some View {
        VStack(alignment: .leading, spacing: 0) {
            HStack(alignment: .top, spacing: 12) {
                VStack(alignment: .leading, spacing: 2) {
                    Text("Recent eBay sales").font(.geist(15, .semibold))
                    if let ebay {
                        Text("Last 30 days · as of \(shortDate(ebay.asOf))").font(.geist(12)).foregroundStyle(Theme.muted)
                    }
                }
                Spacer(minLength: 0)
                EbayLogo()
            }

            switch state {
            case .loading:
                HStack(spacing: 8) {
                    ProgressView().controlSize(.small)
                    Text("Loading sold listings…").font(.geist(13)).foregroundStyle(Theme.muted)
                }
                .padding(.vertical, 24)
            case .failed:
                Text("Couldn't load eBay sales right now.").font(.geist(13)).foregroundStyle(Theme.muted).padding(.vertical, 16)
            case .ready:
                if let ebay { content(ebay) } else {
                    Text("No eBay sales tracked for this card yet.").font(.geist(13)).foregroundStyle(Theme.muted).padding(.vertical, 16)
                }
            }
        }
        .surface(padding: 20)
        .task(id: "\(productId)|\(printing ?? "")") { await load() }
    }

    @ViewBuilder private func content(_ e: EbaySales) -> some View {
        if !labels.isEmpty {
            ScrollView(.horizontal, showsIndicators: false) {
                HStack(spacing: 6) {
                    ForEach([Self.ungradedTab] + labels, id: \.self) { l in
                        let on = tab == l
                        Button {
                            tab = l
                            showAll = false
                        } label: {
                            HStack(spacing: 6) {
                                Text(l).font(.geist(13, on ? .semibold : .regular))
                                Text("\(l == Self.ungradedTab ? e.ungraded.count : (e.graded[l]?.count ?? 0))")
                                    .font(.geist(13)).monospacedDigit().opacity(0.6)
                            }
                            .padding(.horizontal, 12)
                            .frame(height: 32)
                            .foregroundStyle(on ? Theme.background : Theme.muted)
                            .background(Capsule().fill(on ? Color.white : Theme.surface2))
                        }
                        .buttonStyle(.plain)
                    }
                }
                .padding(.vertical, 4)
            }
            .padding(.top, 12)
        }

        let stats = tab == Self.ungradedTab ? e.ungraded : (e.graded[tab] ?? e.ungraded)
        HStack(alignment: .top, spacing: 12) {
            stat("Median sold", stats.median.map { Format.money($0) } ?? "—").frame(maxWidth: .infinity, alignment: .leading).layoutPriority(1.2)
            stat("Sold", "\(stats.count)").frame(maxWidth: .infinity, alignment: .leading).layoutPriority(0.6)
            VStack(alignment: .leading, spacing: 4) {
                stat("Last sale", stats.lastPrice.map { Format.money($0) } ?? "—")
                if let last = stats.lastSold { Text(relative(last)).font(.geist(11)).foregroundStyle(Theme.muted) }
            }
            .frame(maxWidth: .infinity, alignment: .leading).layoutPriority(1.2)
        }
        .padding(.top, 16)

        if sales.isEmpty {
            Text("No \(tab == Self.ungradedTab ? "ungraded" : tab) sales in the last 30 days.")
                .font(.geist(13)).foregroundStyle(Theme.muted).padding(.top, 16)
        } else {
            VStack(spacing: 0) {
                ForEach(Array(sales.prefix(showAll ? sales.count : 6).enumerated()), id: \.offset) { i, s in
                    if i > 0 { Rectangle().fill(Theme.border).frame(height: 1) }
                    SaleRow(sale: s)
                }
            }
            .padding(.top, 20)
            if sales.count > 6 {
                Button(showAll ? "Show fewer" : "Show all \(sales.count)") { withAnimation { showAll.toggle() } }
                    .font(.geist(12, .medium)).foregroundStyle(Theme.muted)
                    .buttonStyle(.plain)
                    .padding(.top, 8)
            }
        }
    }

    private func stat(_ label: String, _ value: String) -> some View {
        VStack(alignment: .leading, spacing: 4) {
            Text(label.uppercased()).font(.mono(10)).tracking(0.6).foregroundStyle(Theme.subtle).lineLimit(1)
            Text(value).font(.geist(22, .semibold)).tracking(-0.4).monospacedDigit().lineLimit(1).minimumScaleFactor(0.6)
        }
    }

    private func shortDate(_ iso: String) -> String {
        guard let d = Format.isoDay.date(from: String(iso.prefix(10))) else { return iso }
        return d.formatted(.dateTime.month(.abbreviated).day())
    }

    /// "just now", "5m ago", "3h ago", "2d ago", like the website.
    private func relative(_ iso: String) -> String {
        let date = ISO8601DateFormatter().date(from: iso) ?? Format.isoDay.date(from: String(iso.prefix(10)))
        guard let date else { return "" }
        let minutes = Int((Date().timeIntervalSince(date) / 60).rounded())
        if minutes < 1 { return "just now" }
        if minutes < 60 { return "\(minutes)m ago" }
        let hours = Int((Double(minutes) / 60).rounded())
        if hours < 24 { return "\(hours)h ago" }
        return "\(Int((Double(hours) / 24).rounded()))d ago"
    }

    private func load() async {
        guard productId.hasPrefix("tcgapi:") else { return state = .ready }
        do {
            ebay = try await Backend.shared.api.ebaySales(productId, printing: printing)
            if let grade, ebay?.graded[grade] != nil { tab = grade }
            state = .ready
        } catch {
            state = .failed
        }
    }
}

/// One sold listing: date, title, condition and best-offer tags, price and a link-out icon.
private struct SaleRow: View {
    var sale: EbaySale

    var body: some View {
        Link(destination: URL(string: sale.url) ?? URL(string: "https://www.ebay.com")!) {
            HStack(spacing: 12) {
                Text(dateLabel).font(.geist(12)).foregroundStyle(Theme.muted).frame(width: 52, alignment: .leading)
                VStack(alignment: .leading, spacing: 3) {
                    Text(sale.title).font(.geist(13)).foregroundStyle(Color.white.opacity(0.85)).lineLimit(1)
                    if sale.condition != nil || sale.bestOffer {
                        HStack(spacing: 6) {
                            if let c = sale.condition { ConditionTag(condition: c) }
                            if sale.bestOffer {
                                Text("Best offer").padding(.horizontal, 6).background(Capsule().fill(Theme.surface2))
                                if let listed = sale.listPrice { Text("listed \(Format.money(listed))").monospacedDigit() }
                            }
                        }
                        .font(.geist(11)).foregroundStyle(Theme.muted)
                    }
                }
                .frame(maxWidth: .infinity, alignment: .leading)
                Text(Format.money(sale.price)).font(.geist(15, .semibold)).monospacedDigit().foregroundStyle(Color.white)
                Image(systemName: "arrow.up.right.square").font(.system(size: 13)).foregroundStyle(Theme.subtle)
            }
            .padding(.vertical, 10)
            .contentShape(Rectangle())
        }
        .buttonStyle(.plain)
    }

    private var dateLabel: String {
        let d = Format.isoDay.date(from: String(sale.soldDate.prefix(10)))
        return d?.formatted(.dateTime.month(.abbreviated).day()) ?? sale.soldDate
    }
}

/// A condition in its own hue, best to worst, like the website's.
struct ConditionTag: View {
    var condition: String

    private var hue: Color? {
        let c = condition.trimmingCharacters(in: .whitespaces).lowercased()
        if c == "mint" || c == "gem mint" || c == "m" { return Color(hex: 0x3EE8C5) }
        if c.contains("near mint") || c.hasPrefix("nm") { return Color(hex: 0x8BE04E) }
        if c.contains("lightly played") || c == "lp" || c.contains("excellent") { return Color(hex: 0x5AA9FF) }
        if c.contains("moderately played") || c == "mp" || c.contains("very good") { return Color(hex: 0xFFC53D) }
        if c.contains("heavily played") || c == "hp" || c == "good" || c.contains("poor") { return Color(hex: 0xFF8A3D) }
        if c.contains("damaged") || c == "dmg" { return Color(hex: 0xFF4D6D) }
        return nil
    }

    var body: some View {
        Text(condition)
            .font(.geist(11, .medium))
            .lineLimit(1)
            .padding(.horizontal, 6)
            .foregroundStyle(hue.map { $0.opacity(0.9) } ?? Theme.muted)
            .background(Capsule().fill(hue.map { $0.opacity(0.16) } ?? Theme.surface2))
    }
}

/// eBay's four-color wordmark, marking where these sales come from.
private struct EbayLogo: View {
    var body: some View {
        HStack(spacing: -1.5) {
            Text("e").foregroundStyle(Color(hex: 0xE53238))
            Text("b").foregroundStyle(Color(hex: 0x0064D2))
            Text("a").foregroundStyle(Color(hex: 0xF5AF02))
            Text("y").foregroundStyle(Color(hex: 0x86B817))
        }
        .font(.geist(26, .bold))
        .accessibilityElement(children: .ignore)
        .accessibilityLabel("eBay")
    }
}
