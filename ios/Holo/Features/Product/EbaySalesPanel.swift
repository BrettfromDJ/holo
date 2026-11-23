import SwiftUI

/// Recent eBay sold listings, laid out like the website: the 30-day median, how many sold and
/// the last sale for ungraded copies or any grade that has sold, then the sales themselves,
/// each linking to its listing. Opens on `grade` when you own a slab that has sold.
struct EbaySalesPanel: View {
    var productId: String
    var printing: String?
    @Environment(CollectionStore.self) private var store
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

    private static func salesCount(_ n: Int) -> String { n == 1 ? "1 sale" : "\(n) sales" }

    /// Sold grades grouped by company ("PSA", "CGC", …), companies by total sales, grades
    /// highest first within each.
    private static func companies(_ labels: [String]) -> [(company: String, grades: [String])] {
        var order: [String] = []
        var groups: [String: [String]] = [:]
        for l in labels {
            let company = String(l.split(separator: " ").first ?? Substring(l))
            if groups[company] == nil { order.append(company) }
            groups[company, default: []].append(l)
        }
        func number(_ l: String) -> Double { Double(l.split(separator: " ").last ?? "") ?? 0 }
        return order.map { c in (c, groups[c]!.sorted { number($0) > number($1) }) }
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
                        Text("Last 30 days · as of \(shortDate(ebay.asOf))" + (productId.hasPrefix("sample:") ? " · sample data" : ""))
                            .font(.geist(12)).foregroundStyle(Theme.muted)
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
                Text("Couldn't load eBay sales right\u{00A0}now.").font(.geist(13)).foregroundStyle(Theme.muted).padding(.vertical, 16)
            case .ready:
                if let ebay { content(ebay) } else {
                    Text("No eBay sales tracked for this card\u{00A0}yet.").font(.geist(13)).foregroundStyle(Theme.muted).padding(.vertical, 16)
                }
            }
        }
        .surface(padding: 20)
        .task(id: "\(productId)|\(printing ?? "")") { await load() }
    }

    @ViewBuilder private func content(_ e: EbaySales) -> some View {
        // Sorted and filtered once per redraw, not once per use.
        let labels = self.labels
        let sales = self.sales
        if !labels.isEmpty {
            // One pill showing the open grade and its sale count; tap for every grade that has
            // sold, grouped by company (the chip row scrolled sideways and hid most of them).
            Menu {
                Picker("Grade", selection: Binding(get: { tab }, set: { tab = $0; showAll = false })) {
                    Text("Ungraded · \(Self.salesCount(e.ungraded.count))").tag(Self.ungradedTab)
                }
                ForEach(Self.companies(labels), id: \.company) { group in
                    Section(group.company) {
                        Picker(group.company, selection: Binding(get: { tab }, set: { tab = $0; showAll = false })) {
                            ForEach(group.grades, id: \.self) { l in
                                Text("\(l) · \(Self.salesCount(e.graded[l]?.count ?? 0))").tag(l)
                            }
                        }
                    }
                }
            } label: {
                HStack(spacing: 8) {
                    Text(tab).font(.geist(14, .semibold))
                    Text(Self.salesCount(tab == Self.ungradedTab ? e.ungraded.count : (e.graded[tab]?.count ?? 0)))
                        .font(.geist(14)).monospacedDigit().foregroundStyle(Theme.muted)
                    Image(systemName: "chevron.down").font(.system(size: 11, weight: .semibold)).foregroundStyle(Theme.muted)
                }
                .foregroundStyle(.white)
                .padding(.horizontal, 14)
                .frame(height: 36)
                .liquidGlass(in: Capsule())
                .contentShape(Capsule())
            }
            .buttonStyle(.plain)
            .padding(.top, 14)
        }

        let stats = tab == Self.ungradedTab ? e.ungraded : (e.graded[tab] ?? e.ungraded)
        HStack(alignment: .top, spacing: 12) {
            stat("Median sold", stats.median.map { Format.money($0) } ?? "—").frame(maxWidth: .infinity, alignment: .leading)
            VStack(alignment: .leading, spacing: 4) {
                stat("Last sale", stats.lastPrice.map { Format.money($0) } ?? "—")
                if let last = stats.lastSold { Text(relative(last)).font(.geist(11)).foregroundStyle(Theme.muted) }
            }
            .frame(maxWidth: .infinity, alignment: .leading)
        }
        .padding(.top, 16)

        // (The sell-speed meter was here: removed, the owner's call.)

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
        // eBay's own listings for this card (and the open grade), side by side: every recent
        // sale (lime) and what's for sale now (quiet). Short words: the panel already says eBay.
        if let product = store.products[productId] {
            let grade = tab == Self.ungradedTab ? nil : tab
            let prefix = grade.map { "\($0) " } ?? ""
            HStack(spacing: 8) {
                if let sold = Self.soldURL(product, grade: grade) {
                    Link(destination: sold) { ebayPill("\(prefix)sold", lime: true) }.buttonStyle(.plain)
                }
                if let listings = Self.searchURL(product, grade: grade, sold: false) {
                    Link(destination: listings) { ebayPill("\(prefix)for sale", lime: false) }.buttonStyle(.plain)
                }
            }
            .padding(.top, 16)
        }
    }

    /// One of the two eBay buttons: "See … ↗" in a capsule, lime for sold, quiet for for-sale.
    private func ebayPill(_ what: String, lime: Bool) -> some View {
        HStack(spacing: 6) {
            Text("See \(what)").lineLimit(1).minimumScaleFactor(0.8)
            Image(systemName: "arrow.up.right").font(.system(size: 11, weight: .semibold))
        }
        .font(.geist(14, .semibold))
        .foregroundStyle(lime ? Theme.lime : .white)
        .frame(maxWidth: .infinity).frame(height: 42)
        .background(Capsule().fill(lime ? Theme.lime.opacity(0.12) : Color.white.opacity(0.08)))
        .overlay(Capsule().strokeBorder(lime ? Theme.lime.opacity(0.25) : Theme.borderStrong, lineWidth: 1))
        .contentShape(Capsule())
    }

    /// The words sellers use for a set in titles: the set's name without its code prefix
    /// ("SV05:", "ME:") or filler, first two words, or a numbered set's number alone ("151").
    /// Same as the website's `ebaySetWords`.
    /// The set as sellers write it in titles: its name without the code prefix ("SV05:") or the
    /// series before a dash ("Scarlet & Violet—"), keeping "Base Set" whole; a numbered set's number
    /// alone ("151"). Up to two words, plus "1st Edition" for a 1st Edition half. Same as the website.
    static func setWords(_ setName: String?) -> String {
        guard let setName else { return "" }
        let filler: Set<String> = ["pokemon", "pokémon", "tcg", "the", "and", "&", "of", "-"]
        let first = setName.lowercased().contains("1st edition")
        var rest = setName.replacingOccurrences(of: #"^[A-Za-z]{1,6}\d*(\.\d+)?\s*:\s*"#, with: "", options: .regularExpression)
        if let dash = rest.range(of: "—", options: .backwards) { rest = String(rest[dash.upperBound...]) }
        rest = rest.replacingOccurrences(of: #"\([^)]*\)"#, with: " ", options: .regularExpression)
            .replacingOccurrences(of: #"[:,]"#, with: " ", options: .regularExpression)
        let words = rest.split(whereSeparator: { $0.isWhitespace }).map(String.init).filter { !filler.contains($0.lowercased()) }
        if let numbered = words.first(where: { $0.range(of: #"^\d{2,3}$"#, options: .regularExpression) != nil }) { return numbered }
        let set = words.prefix(2).joined(separator: " ")
        return first ? "\(set) 1st Edition" : set
    }

    /// eBay sold-listings search: the name without bracketed notes, the set's words (so other
    /// printings don't fill it), the card number as sellers write it (the part before "/"), and
    /// the grade; ungraded singles leave out slabs. Same as the website.
    static func soldURL(_ p: Product, grade: String?) -> URL? { searchURL(p, grade: grade, sold: true) }

    /// The same eBay search: sold listings, or (`sold: false`) what's for sale now, cheapest
    /// first (price plus shipping). Same as the website's `ebaySoldUrl` / `ebayListingsUrl`.
    static func searchURL(_ p: Product, grade: String?, sold: Bool) -> URL? {
        var q = p.name.replacingOccurrences(of: #"\([^)]*\)"#, with: " ", options: .regularExpression)
            .replacingOccurrences(of: #"\s+-\s+\S*\d+/\d+\S*"#, with: " ", options: .regularExpression)
            .replacingOccurrences(of: #"\s+-\s+"#, with: " ", options: .regularExpression)
            .replacingOccurrences(of: #"\s+"#, with: " ", options: .regularExpression)
            .trimmingCharacters(in: .whitespaces)
        if !p.isSealed {
            let set = setWords(p.setName)
            if !set.isEmpty, !q.lowercased().contains(set.lowercased()) { q += " \(set)" }
            if let head = p.number?.trimmingCharacters(in: .whitespaces).split(separator: "/").first.map({ String($0).replacingOccurrences(of: "#", with: "") }), !head.isEmpty {
                q += " \(head)"
            }
        }
        // Ungraded singles: sold searches leave slabs out; what's for sale asks for "NM" (near mint).
        if let grade { q += " \(grade)" } else if !p.isSealed { q += sold ? " -psa -bgs -cgc -sgc" : " NM" }
        var c = URLComponents(string: "https://www.ebay.com/sch/i.html")
        c?.queryItems = sold ? [
            URLQueryItem(name: "_nkw", value: q),
            URLQueryItem(name: "LH_Sold", value: "1"),
            URLQueryItem(name: "LH_Complete", value: "1"),
            URLQueryItem(name: "_sacat", value: "0"),
        ] : [
            URLQueryItem(name: "_nkw", value: q),
            URLQueryItem(name: "_sop", value: "15"),
            // Buy It Now only: a price you can pay today, not an auction that may climb.
            URLQueryItem(name: "LH_BIN", value: "1"),
            URLQueryItem(name: "_sacat", value: "0"),
        ]
        return c?.url
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
        let date = ISOTime.plain.date(from: iso) ?? Format.isoDay.date(from: String(iso.prefix(10)))
        guard let date else { return "" }
        let minutes = Int((Date().timeIntervalSince(date) / 60).rounded())
        if minutes < 1 { return "just now" }
        if minutes < 60 { return "\(minutes)m ago" }
        let hours = Int((Double(minutes) / 60).rounded())
        if hours < 24 { return "\(hours)h ago" }
        return "\(Int((Double(hours) / 24).rounded()))d ago"
    }

    private func load() async {
        guard EbaySalesCache.supports(productId) else { return state = .ready }
        do {
            ebay = try await EbaySalesCache.sales(productId, printing: printing, market: store.marketPrice(productId, printing: printing)?.market)
            if let grade, ebay?.graded[grade] != nil { tab = grade }
            state = .ready
        } catch {
            state = .failed
        }
    }
}

/// One eBay request per card and printing, shared by the panels on its page (the sales, graded
/// prices and worth panels each fetched their own copy), the Owned sheet's "Sells fast" meter and
/// the Deal tab, and kept for a few minutes. Demo products (`sample:`) get sample sales made on
/// the phone instead (no request).
@MainActor
enum EbaySalesCache {
    private static var entries: [String: (at: Date, task: Task<EbaySales?, Error>)] = [:]
    /// Answers that have arrived, so a view can show them without asking (the Deal tab).
    private static var resolved: [String: (at: Date, value: EbaySales?)] = [:]
    private static let ttl: TimeInterval = 300

    private static func cacheKey(_ productId: String, _ printing: String?) -> String { "\(productId)|\(printing ?? "")" }

    /// Whether a product has eBay sales to show: catalog cards, and demo ones (sample sales).
    nonisolated static func supports(_ productId: String) -> Bool {
        productId.hasPrefix("tcgapi:") || productId.hasPrefix("sample:")
    }

    /// `market` is only used for demo products, whose sample sales are made around it.
    static func sales(_ productId: String, printing: String?, market: Double? = nil) async throws -> EbaySales? {
        if productId.hasPrefix("sample:") { return sample(productId, printing: printing, market: market) }
        let key = cacheKey(productId, printing)
        if let hit = entries[key], Date().timeIntervalSince(hit.at) < ttl { return try await hit.task.value }
        let task = Task { try await Backend.shared.api.ebaySales(productId, printing: printing) }
        entries[key] = (Date(), task)
        do {
            let value = try await task.value
            resolved[key] = (Date(), value)
            return value
        } catch {
            // A failed request isn't kept, so the next look tries again.
            if entries[key]?.task == task { entries[key] = nil }
            throw error
        }
    }

    /// The sales if they're already here (never fetches); demo products are made on the spot.
    static func cached(_ productId: String, printing: String?, market: Double? = nil) -> EbaySales? {
        if productId.hasPrefix("sample:") { return sample(productId, printing: printing, market: market) }
        guard let hit = resolved[cacheKey(productId, printing)], Date().timeIntervalSince(hit.at) < 3600 else { return nil }
        return hit.value
    }

    private static func sample(_ productId: String, printing: String?, market: Double?) -> EbaySales? {
        let key = cacheKey(productId, printing)
        if let hit = resolved[key], let value = hit.value, value.asOf == Format.day() { return value }
        let name = DemoData.items.first { "sample:\($0.slug)" == productId }?.name ?? "Card"
        let value = DemoEbay.sales(productId: productId, name: name, printing: printing, market: market)
        if value != nil { resolved[key] = (Date(), value) }
        return value
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
                        // One line: the condition tag, then "Best offer · listed $X" as plain quiet
                        // text (no second pill), never wrapping.
                        HStack(spacing: 6) {
                            if let c = sale.condition { ConditionTag(condition: c).fixedSize() }
                            if sale.bestOffer {
                                Text(["Best offer", sale.listPrice.map { "listed \(Format.money($0))" }].compactMap { $0 }.joined(separator: " · "))
                                    .monospacedDigit()
                                    .lineLimit(1)
                                    .truncationMode(.tail)
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
