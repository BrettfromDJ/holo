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

    enum Filter: String, CaseIterable { case all = "All", purchase = "Purchases", sale = "Sales", adjustment = "Adjustments" }

    /// Everything the page shows, worked out once per change.
    private struct Model {
        var months: [(key: String, rows: [Txn])] = []
        /// Each live entry as it stands after edits, by its original id.
        var effective: [String: Txn] = [:]
        var byId: [String: Txn] = [:]
        var realized: [String: RealizedEntry] = [:]
        var hiddenCount = 0
        var bought = 0.0
        var sold = 0.0
        var realizedTotal = 0.0
    }

    private var model: Model {
        let all = store.portfolioTransactions
        var m = Model()
        let effective = Ledger.effective(all)
        m.effective = Dictionary(effective.map { ($0.id, $0) }, uniquingKeysWith: { a, _ in a })
        m.byId = Dictionary(all.map { ($0.id, $0) }, uniquingKeysWith: { a, _ in a })
        let hidden = all.filter { $0.kind == .correction || m.effective[$0.id] == nil }
        m.hiddenCount = hidden.count
        for pos in Ledger(all).positions.values { for r in pos.realized { m.realized[r.transactionId] = r } }
        m.realizedTotal = m.realized.values.reduce(0) { $0 + $1.gain }
        for t in effective {
            if t.kind == .purchase || (t.kind == .adjustment && t.quantity > 0) { m.bought += t.acquisitionCost }
            if t.kind == .sale { m.sold += t.saleProceeds }
        }
        let list = (showHidden ? all : all.filter { $0.kind != .correction && m.effective[$0.id] != nil })
            .filter { t in
                switch filter {
                case .all: return true
                case .purchase: return t.kind == .purchase || (showHidden && t.kind == .correction)
                case .sale: return t.kind == .sale || (showHidden && t.kind == .correction)
                case .adjustment: return t.kind == .adjustment || (showHidden && t.kind == .correction)
                }
            }
            .sorted { $0.date != $1.date ? $0.date > $1.date : $0.createdAt > $1.createdAt }
        var order: [String] = []
        var groups: [String: [Txn]] = [:]
        for t in list {
            let key = String(t.date.prefix(7))
            if groups[key] == nil { order.append(key) }
            groups[key, default: []].append(t)
        }
        m.months = order.map { ($0, groups[$0] ?? []) }
        return m
    }

    var body: some View {
        let m = model
        ScrollView {
            VStack(alignment: .leading, spacing: 26) {
                header(m)
                controls(m)
                if m.months.isEmpty {
                    Text(store.portfolioTransactions.isEmpty ? "No activity yet. Add a purchase and it shows up here." : "Nothing matches.")
                        .font(.geist(15)).foregroundStyle(Theme.muted)
                        .frame(maxWidth: .infinity).padding(.vertical, 40)
                }
                if let error { Text(error).font(.geist(13)).foregroundStyle(Theme.down) }
                LazyVStack(alignment: .leading, spacing: 26) {
                    ForEach(m.months, id: \.key) { month in
                        VStack(alignment: .leading, spacing: 10) {
                            Text(monthTitle(month.key).uppercased()).font(.display(20)).displayTrim(20)
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
        .confirmationDialog("Delete this entry?", isPresented: Binding(get: { deleting != nil }, set: { if !$0 { deleting = nil } }), titleVisibility: .visible) {
            Button("Delete", role: .destructive) {
                guard let t = deleting else { return }
                Task {
                    do { try await store.delete(t) } catch { self.error = error.localizedDescription }
                }
            }
        } message: {
            Text("Your totals update as if it never happened. The original stays in the record.")
        }
    }

    // MARK: Top

    private func header(_ m: Model) -> some View {
        let count = m.effective.count
        return VStack(alignment: .leading, spacing: 18) {
            VStack(alignment: .leading, spacing: 8) {
                MonoLabel(text: "Activity")
                HStack(alignment: .lastTextBaseline, spacing: 10) {
                    CountingText(value: Double(count), format: { "\(Int($0.rounded()))" })
                        .font(.display(56)).monospacedDigit().lineLimit(1).displayTrim(56)
                    Text(count == 1 ? "ENTRY" : "ENTRIES").font(.display(24)).foregroundStyle(Theme.muted).displayTrim(24)
                }
                Text("Every purchase, sale and adjustment").font(.geist(13)).foregroundStyle(Theme.muted)
            }
            .padding(.top, 8)
            HStack(spacing: 8) {
                GlassStat(label: "Bought", value: Format.money(m.bought))
                GlassStat(label: "Sold", value: Format.money(m.sold))
                GlassStat(label: "Realized", value: Format.signedMoney(m.realizedTotal), tint: Theme.tone(m.realizedTotal))
            }
        }
        .background(alignment: .top) {
            DotBackdrop().padding(.horizontal, -16).padding(.top, -160).padding(.bottom, -40)
        }
    }

    private func controls(_ m: Model) -> some View {
        VStack(alignment: .leading, spacing: 10) {
            ScrollView(.horizontal, showsIndicators: false) {
                ChipPicker(options: Filter.allCases.map { ($0, $0.rawValue) }, selection: $filter)
            }
            .scrollClipDisabled()
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
        let (icon, label) = kindLabel(t)
        let amount: Double? = t.kind == .sale ? shown.saleProceeds : (t.kind == .purchase || (t.kind == .adjustment && t.quantity > 0)) ? shown.acquisitionCost : nil
        let gain = m.realized[t.id]?.gain
        let original = t.correctsId.flatMap { m.byId[$0] }
        let detail: String = t.kind == .correction
            ? "\(t.quantity == 0 ? "deleted" : "edited") \(original.map { "\($0.kind.rawValue) from \(day($0.date))" } ?? "entry")"
            : "\(Int(abs(shown.quantity))) × \(Format.money(shown.unitPrice))"
        let meta = [label, detail, day(shown.date), t.source, t.identity.gradeLabel].compactMap { $0 }.joined(separator: " · ")

        return HStack(spacing: 12) {
            NavigationLink(value: t.identity.productId) {
                HStack(spacing: 12) {
                    ZStack(alignment: .bottomTrailing) {
                        HoldingArt(product: product, identity: t.identity, cornerRadius: 4, caption: false)
                            .frame(width: 38, height: 52)
                        Image(systemName: icon).font(.system(size: 9, weight: .bold))
                            .foregroundStyle(t.kind == .sale ? Theme.up : Theme.muted)
                            .frame(width: 18, height: 18)
                            .background(Theme.surface3, in: Circle())
                            .overlay(Circle().strokeBorder(Theme.surface, lineWidth: 2))
                            .offset(x: 5, y: 5)
                    }
                    VStack(alignment: .leading, spacing: 3) {
                        Text(product?.name ?? t.identity.productId).font(.geist(14, .medium)).lineLimit(1)
                        Text(meta).font(.geist(12)).foregroundStyle(Theme.muted).lineLimit(2)
                        HStack(spacing: 6) {
                            if voided { Tag(text: "Deleted", tint: Theme.muted) }
                            if edited { Tag(text: "Edited", tint: Theme.muted) }
                            if let notes = t.notes, !notes.isEmpty, !["Deleted", "Edited", "Voided", "Corrected"].contains(notes) {
                                Text(notes).font(.geist(12)).foregroundStyle(Theme.subtle).lineLimit(1)
                            }
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
                            Text(Format.signedMoney(gain)).font(.geist(12)).monospacedDigit().foregroundStyle(Theme.tone(gain))
                        }
                        if t.kind == .adjustment, t.quantity < 0, gain != nil {
                            Text("written off").font(.geist(11)).foregroundStyle(Theme.subtle)
                        }
                    }
                }
                .contentShape(Rectangle())
            }
            .buttonStyle(.plain)
            if t.kind != .correction, !voided {
                Menu {
                    Button { editing = shown } label: { Label("Edit", systemImage: "pencil") }
                    Button(role: .destructive) { deleting = t } label: { Label("Delete", systemImage: "trash") }
                } label: {
                    Image(systemName: "ellipsis").font(.system(size: 13)).foregroundStyle(Theme.muted).frame(width: 28, height: 32)
                }
            } else {
                Color.clear.frame(width: 28)
            }
        }
        .padding(.horizontal, 14)
        .padding(.vertical, 12)
    }

    private func kindLabel(_ t: Txn) -> (String, String) {
        switch t.kind {
        case .purchase: return ("arrow.down.left", "Purchase")
        case .sale: return ("arrow.up.right", "Sale")
        case .adjustment: return t.quantity > 0 ? ("plus", "Added") : ("minus", "Removed")
        case .correction: return ("pencil", "Edit record")
        }
    }

    private func day(_ iso: String) -> String {
        Format.isoDay.date(from: iso)?.formatted(.dateTime.month(.abbreviated).day().year()) ?? iso
    }

    private func monthTitle(_ key: String) -> String {
        Format.isoDay.date(from: key + "-01")?.formatted(.dateTime.month(.wide).year()) ?? key
    }
}
