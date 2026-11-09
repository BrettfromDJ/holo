import SwiftUI

/// Every purchase, sale and adjustment, newest first and grouped by month, like the website's
/// Activity page. Follows the portfolio picker. Deleted entries and the records that edited or
/// deleted them stay hidden unless you ask to see them; edit or delete any live entry.
struct ActivityView: View {
    @Environment(CollectionStore.self) private var store
    @State private var filter = Filter.all
    @State private var showHidden = false
    @State private var editing: Txn?
    @State private var deleting: Txn?
    @State private var error: String?
    /// Find every entry for a card.
    @State private var query = ""
    /// The three totals: this year or all time.
    @State private var thisYear = false

    enum Filter: String, CaseIterable { case all = "All", purchase = "Bought", sale = "Sold", pulls = "Pulls", adjustment = "Other" }

    /// The ledger work (corrections applied, FIFO realized gains, totals), done once per change to
    /// the log, not on every redraw (opening a row's menu, a sheet or the delete prompt redraws
    /// the page).
    private struct Base {
        var all: [Txn] = []
        /// Each live entry as it stands after edits, by its original id.
        var effective: [String: Txn] = [:]
        var byId: [String: Txn] = [:]
        var realized: [String: RealizedEntry] = [:]
        var hiddenCount = 0
        var bought = 0.0
        var sold = 0.0
        var realizedTotal = 0.0
        /// The same three, this calendar year only.
        var yearBought = 0.0
        var yearSold = 0.0
        var yearRealized = 0.0

        init() {}

        init(_ all: [Txn]) {
            self.all = all
            let live = Ledger.effective(all)
            let byLive = Dictionary(live.map { ($0.id, $0) }, uniquingKeysWith: { a, _ in a })
            effective = byLive
            byId = Dictionary(all.map { ($0.id, $0) }, uniquingKeysWith: { a, _ in a })
            hiddenCount = all.filter { $0.kind == .correction || byLive[$0.id] == nil }.count
            var gains: [String: RealizedEntry] = [:]
            for pos in Ledger(all).positions.values { for r in pos.realized { gains[r.transactionId] = r } }
            realized = gains
            realizedTotal = gains.values.reduce(0) { $0 + $1.gain }
            let year = String(Calendar.current.component(.year, from: Date()))
            yearRealized = gains.values.filter { $0.date.hasPrefix(year) }.reduce(0) { $0 + $1.gain }
            for t in live {
                let inYear = t.date.hasPrefix(year)
                if t.kind == .purchase || (t.kind == .adjustment && t.quantity > 0) {
                    bought += t.acquisitionCost
                    if inYear { yearBought += t.acquisitionCost }
                }
                if t.kind == .sale {
                    sold += t.saleProceeds
                    if inYear { yearSold += t.saleProceeds }
                }
            }
        }
    }

    /// What the page shows: the ledger work plus the list for the chosen filter, by month.
    private struct Model {
        var base = Base()
        var months: [(key: String, rows: [Txn])] = []
        var effective: [String: Txn] { base.effective }
        var byId: [String: Txn] { base.byId }
        var realized: [String: RealizedEntry] { base.realized }
        var hiddenCount: Int { base.hiddenCount }
        var bought: Double { base.bought }
        var sold: Double { base.sold }
        var realizedTotal: Double { base.realizedTotal }
    }

    /// Remembers the last model: the ledger replays only when the log changes, and the list is
    /// regrouped only when the log, the filter or "show deleted" changes. A plain (unobserved)
    /// object, so filling it while drawing never asks for another redraw.
    private final class Memo {
        var log: [Txn]?
        var base = Base()
        var listKey: (Filter, Bool, String)?
        var months: [(key: String, rows: [Txn])] = []

        func model(log: [Txn], filter: Filter, showHidden: Bool, query: String, names: [String: Product]) -> Model {
            var fresh = false
            if self.log != log {
                self.log = log
                base = Base(log)
                fresh = true
            }
            let q = query.trimmingCharacters(in: .whitespaces).lowercased()
            if fresh || listKey?.0 != filter || listKey?.1 != showHidden || listKey?.2 != q {
                listKey = (filter, showHidden, q)
                months = Self.group(base, filter: filter, showHidden: showHidden, query: q, names: names)
            }
            return Model(base: base, months: months)
        }

        /// The filtered, sorted list, grouped by month.
        private static func group(_ base: Base, filter: Filter, showHidden: Bool, query: String, names: [String: Product]) -> [(key: String, rows: [Txn])] {
            let list = (showHidden ? base.all : base.all.filter { $0.kind != .correction && base.effective[$0.id] != nil })
                .filter { t in
                    switch filter {
                    case .all: return true
                    case .purchase: return (t.kind == .purchase && !t.isPull) || (showHidden && t.kind == .correction)
                    case .pulls: return t.isPull
                    case .sale: return t.kind == .sale || (showHidden && t.kind == .correction)
                    case .adjustment: return t.kind == .adjustment || (showHidden && t.kind == .correction)
                    }
                }
                .filter { t in
                    guard !query.isEmpty else { return true }
                    let p = names[t.identity.productId]
                    return (p?.name ?? t.identity.productId).lowercased().contains(query) || (p?.setName ?? "").lowercased().contains(query)
                }
                .sorted { $0.date != $1.date ? $0.date > $1.date : $0.createdAt > $1.createdAt }
            var order: [String] = []
            var groups: [String: [Txn]] = [:]
            for t in list {
                let key = String(t.date.prefix(7))
                if groups[key] == nil { order.append(key) }
                groups[key, default: []].append(t)
            }
            return order.map { ($0, groups[$0] ?? []) }
        }
    }

    @State private var memo = Memo()

    var body: some View {
        let log = store.portfolioTransactions
        let m = memo.model(log: log, filter: filter, showHidden: showHidden, query: query, names: store.products)
        ScrollView {
            VStack(alignment: .leading, spacing: 26) {
                header(m)
                controls(m)
                if m.months.isEmpty {
                    Text(log.isEmpty ? "No activity yet. Add a purchase and it shows up here." : "Nothing matches.")
                        .font(.geist(15)).foregroundStyle(Theme.muted)
                        .frame(maxWidth: .infinity).padding(.vertical, 40)
                }
                if let error { Text(error).font(.geist(13)).foregroundStyle(Theme.down) }
                LazyVStack(alignment: .leading, spacing: 26) {
                    ForEach(m.months, id: \.key) { month in
                        VStack(alignment: .leading, spacing: 10) {
                            HStack(alignment: .lastTextBaseline) {
                                Text(monthTitle(month.key)).font(.display(20)).tracking(-0.5).displayTrim(20)
                                Spacer(minLength: 8)
                                Text(monthTotals(month.rows, m)).font(.geist(12)).monospacedDigit().foregroundStyle(Theme.muted).lineLimit(1)
                            }
                            VStack(spacing: 0) {
                                ForEach(month.rows) { t in
                                    row(t, m)
                                    if t.id != month.rows.last?.id { Rectangle().fill(Theme.border).frame(height: 1).padding(.leading, 66) }
                                }
                            }
                            .surface(radius: 16, padding: 0)
                        }
                    }
                }
            }
            .padding(.horizontal, 16)
            .padding(.bottom, 120)
        }
        .background(Theme.background)
        .navigationBarTitleDisplayMode(.inline)
        .pageTitle("Activity")
        .sheet(item: $editing) { EntryEditSheet(entry: $0) }
        .alert("Delete this entry?", isPresented: Binding(get: { deleting != nil }, set: { if !$0 { deleting = nil } })) {
            Button("Cancel", role: .cancel) {}
            Button("Delete", role: .destructive) {
                guard let t = deleting else { return }
                Task {
                    do { try await store.delete(t) } catch { self.error = error.localizedDescription }
                }
            }
        } message: {
            Text("Your totals update as if it never happened. The original stays in the\u{00A0}record.")
        }
    }

    // MARK: Top

    private func header(_ m: Model) -> some View {
        let count = m.effective.count
        return VStack(alignment: .leading, spacing: 18) {
            HStack(alignment: .lastTextBaseline, spacing: 10) {
                CountingText(value: Double(count), format: { "\(Int($0.rounded()))" })
                    .font(.display(56)).tracking(-2.2).monospacedDigit().lineLimit(1).displayTrim(56)
                Text(count == 1 ? "purchase or sale" : "purchases and sales").font(.display(24)).tracking(-0.6).foregroundStyle(Theme.muted).displayTrim(24)
                    .lineLimit(1).minimumScaleFactor(0.7)
            }
            .padding(.top, 8)
            VStack(alignment: .leading, spacing: 10) {
                ChipPicker(options: [(false, "All time"), (true, "This year")], selection: $thisYear)
                    .fixedSize()
                HStack(spacing: 8) {
                    GlassStat(label: "Bought", value: Format.money(thisYear ? m.base.yearBought : m.bought))
                    GlassStat(label: "Sold", value: Format.money(thisYear ? m.base.yearSold : m.sold))
                    // The profit from selling: opens Sales & taxes.
                    let realized = thisYear ? m.base.yearRealized : m.realizedTotal
                    NavigationLink(value: MorePage.sales) {
                        GlassStat(label: "Realized ›", value: Format.signedMoney(realized), tint: Theme.tone(realized))
                    }
                    .buttonStyle(.plain)
                }
            }
        }
        .background(alignment: .top) {
            DotBackdrop().padding(.horizontal, -16).padding(.top, -160).padding(.bottom, -40)
        }
    }

    private func controls(_ m: Model) -> some View {
        VStack(alignment: .leading, spacing: 10) {
            HStack(spacing: 8) {
                Image(systemName: "magnifyingglass").font(.system(size: 14, weight: .medium)).foregroundStyle(Theme.muted)
                TextField("", text: $query, prompt: Text("Find a card").foregroundColor(Theme.subtle))
                    .font(.geist(15)).foregroundStyle(.white)
                    .submitLabel(.search)
                if !query.isEmpty {
                    Button { query = "" } label: { Image(systemName: "xmark.circle.fill").foregroundStyle(Theme.subtle) }
                        .buttonStyle(.plain)
                }
            }
            .padding(.horizontal, 14).frame(height: 44)
            .liquidGlass(in: Capsule())
            ChipPicker(options: Filter.allCases.map { ($0, $0.rawValue) }, selection: $filter, scrolls: true)
            if m.hiddenCount > 0 {
                Button("\(showHidden ? "Hide" : "Show") deleted & edit records (\(m.hiddenCount))") { showHidden.toggle() }
                    .font(.geist(12, .medium)).foregroundStyle(Theme.subtle)
            }
        }
    }

    // MARK: Rows

    private func row(_ t: Txn, _ m: Model) -> some View {
        let product = store.products[t.identity.productId]
        let eff = m.effective[t.id]
        let voided = t.kind != .correction && eff == nil
        let shown = eff ?? t
        let edited = eff.map { $0.unitPrice != t.unitPrice || $0.quantity != t.quantity || $0.date != t.date || $0.fees != t.fees } ?? false
        let (tag, tint) = kindTag(t)
        let amount: Double? = t.kind == .sale ? shown.saleProceeds : (t.kind == .purchase || (t.kind == .adjustment && t.quantity > 0)) ? shown.acquisitionCost : nil
        let gain = m.realized[t.id]?.gain
        let original = t.correctsId.flatMap { m.byId[$0] }
        // Short: what, where and the day (the year is in the month heading).
        let what: String = t.kind == .correction
            ? "\(t.quantity == 0 ? "deleted" : "edited") \(original.map { "\($0.kind.rawValue) from \(shortDay($0.date))" } ?? "entry")"
            : "\(Int(abs(shown.quantity))) × \(Format.money(shown.unitPrice))"
        let source = t.isPull ? nil : t.source
        let meta = [what, source, t.identity.gradeLabel, t.kind == .correction ? nil : shortDay(shown.date)].compactMap { $0 }.joined(separator: " · ")
        let editable = t.kind != .correction && !voided

        return CardLink(productId: t.identity.productId, identity: t.identity) {
            HStack(spacing: 12) {
                HoldingArt(product: product, identity: t.identity, cornerRadius: 4, caption: false)
                    .frame(width: 38, height: 52)
                VStack(alignment: .leading, spacing: 4) {
                    Text(product?.name ?? t.identity.productId).font(.geist(14, .medium)).foregroundStyle(.white)
                        .lineLimit(2).fixedSize(horizontal: false, vertical: true)
                    HStack(spacing: 6) {
                        Tag(text: tag, tint: tint)
                        if voided { Tag(text: "Deleted", tint: Theme.muted) }
                        if edited { Tag(text: "Edited", tint: Theme.muted) }
                    }
                    Text(meta).font(.geist(12)).monospacedDigit().foregroundStyle(Theme.muted).lineLimit(1)
                    if let notes = t.notes, !notes.isEmpty, !["Deleted", "Edited", "Voided", "Corrected"].contains(notes) {
                        Text(notes).font(.geist(12)).foregroundStyle(Theme.subtle).lineLimit(1)
                    }
                }
                Spacer(minLength: 6)
                VStack(alignment: .trailing, spacing: 3) {
                    if let amount {
                        Text((t.kind == .sale ? "+" : "−") + Format.money(amount))
                            .font(.geist(14, .semibold)).monospacedDigit()
                            .foregroundStyle(voided ? Theme.subtle : .white)
                            .strikethrough(voided)
                    }
                    if let gain {
                        // Labelled, so it doesn't read as a second price.
                        (Text(t.kind == .adjustment ? "written off " : "profit ").foregroundColor(Theme.subtle)
                            + Text(Format.signedMoney(gain)).foregroundColor(Theme.tone(gain)))
                            .font(.geist(12)).monospacedDigit()
                    }
                }
            }
            .padding(.horizontal, 14)
            .padding(.vertical, 12)
            .contentShape(Rectangle())
        }
        .buttonStyle(.plain)
        // Edit and delete on a long press (the row's tap opens the card).
        .contextMenu {
            if editable {
                Button { editing = shown } label: { Label("Edit", systemImage: "pencil") }
                Button(role: .destructive) { deleting = t } label: { Label("Delete", systemImage: "trash") }
            }
        }
    }

    /// Each month's money, on its heading: "spent $124 · sold $879".
    private func monthTotals(_ rows: [Txn], _ m: Model) -> String {
        var spent = 0.0, sold = 0.0
        for t in rows {
            guard let e = m.effective[t.id] else { continue }
            if e.kind == .purchase || (e.kind == .adjustment && e.quantity > 0) { spent += e.acquisitionCost }
            if e.kind == .sale { sold += e.saleProceeds }
        }
        return [spent > 0 ? "spent \(Format.money(spent))" : nil, sold > 0 ? "sold \(Format.money(sold))" : nil].compactMap { $0 }.joined(separator: " · ")
    }

    private func kindTag(_ t: Txn) -> (String, Color) {
        switch t.kind {
        case .purchase: return t.isPull ? ("Pulled", Theme.planBlue) : ("Bought", Theme.muted)
        case .sale: return ("Sold", Theme.lime)
        case .adjustment: return t.quantity > 0 ? ("Added", Theme.muted) : ("Removed", Theme.muted)
        case .correction: return ("Edit record", Theme.muted)
        }
    }

    private func shortDay(_ iso: String) -> String {
        Format.isoDay.date(from: iso)?.formatted(.dateTime.month(.abbreviated).day()) ?? iso
    }

    private func monthTitle(_ key: String) -> String {
        Format.isoDay.date(from: key + "-01")?.formatted(.dateTime.month(.wide).year()) ?? key
    }
}
