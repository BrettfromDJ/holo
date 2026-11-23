import CoreTransferable
import SwiftUI
import UniformTypeIdentifiers

/// Sales & taxes: what you sold in a year, what those copies cost, and the profit, split by how
/// long you held them, with a spreadsheet to hand to an accountant. Covers every portfolio.
struct SalesView: View {
    @Environment(CollectionStore.self) private var store
    /// The year shown; nil is the latest, 0 is every year.
    @State private var year: Int?
    /// A sale's ⋯: edit or delete it.
    @State private var acting: SaleRef?
    @State private var editing: Txn?
    @State private var deleting: Txn?
    @State private var info = false

    var body: some View {
        // Every sale, once per log change (few lines, cheap).
        let all = SalesReport.lines(store.transactions)
        let years = SalesReport.years(all)
        let shown = year ?? years.first ?? Calendar.current.component(.year, from: Date())
        let lines = shown == 0 ? all : all.filter { $0.year == shown }
        let t = SalesReport.totals(lines)
        let fees = Self.fees(lines, store.effectiveTransactions)
        ScrollView {
            if all.isEmpty {
                EmptyPage(title: "No sales yet", line: "When you sell something, mark it sold on its page. Your profit for the year shows up here, ready for tax time.",
                          icon: "doc.text")
                    .padding(.top, 40)
            } else {
                VStack(alignment: .leading, spacing: 32) {
                    // Every year you sold in, and All.
                    ChipPicker(options: [(0, "All")] + years.map { ($0, String($0)) }, selection: Binding(get: { shown }, set: { year = $0 }), scrolls: true)
                        .fixedSize(horizontal: false, vertical: true)
                    hero(t, lines: lines, fees: fees, year: shown)
                    heldSplit(t)
                    list(lines)
                }
                .padding(.horizontal, 16)
                .padding(.top, 8)
                .padding(.bottom, 120)
            }
        }
        .background(Theme.background)
        .navigationBarTitleDisplayMode(.inline)
        .pageTitle("Sales & taxes")
        // The spreadsheet for your accountant: a share icon at the top right.
        .toolbar {
            if !all.isEmpty {
                ToolbarItem(placement: .topBarTrailing) {
                    let file = SalesFile(csv: SalesReport.csv(lines, products: store.products), name: shown == 0 ? "Corodex sales" : "Corodex sales \(shown)")
                    ShareLink(item: file, preview: SharePreview(file.name)) { Image(systemName: "square.and.arrow.up") }
                        .accessibilityLabel("Export for your accountant")
                }
            }
        }
        .actionsSheet(item: $acting, title: { store.products[$0.productId]?.name }, product: { store.products[$0.productId] }) { ref in
            guard let t = store.effectiveTransactions.first(where: { $0.id == ref.id }) else { return [] }
            return [
                [SheetAction(title: "Edit sale", icon: "pencil") { editing = t }],
                [SheetAction(title: "Delete sale", icon: "trash", destructive: true) { deleting = t }],
            ]
        }
        .sheet(item: $editing) { t in EntryEditSheet(entry: t) }
        .alert("Delete this sale?", isPresented: Binding(get: { deleting != nil }, set: { if !$0 { deleting = nil } })) {
            Button("Cancel", role: .cancel) {}
            Button("Delete", role: .destructive) {
                guard let t = deleting else { return }
                Task { try? await store.delete(t) }
            }
        } message: {
            Text("The copies go back into your collection. The original stays in the\u{00A0}record.")
        }
        .alert("About these numbers", isPresented: $info) {
            Button("OK", role: .cancel) {}
        } message: {
            Text("Profit is what each sale brought in after its fees, shipping and tax, minus what those copies cost you, oldest copies first. Cards you pulled count as costing nothing.\n\nIn the US, collectibles held over a year are taxed at up to 28%. A year or less is taxed like income. Your accountant will know what applies to you.\n\nA guide for your records, not tax advice.")
        }
    }

    /// Fees, shipping and tax paid on the sales shown.
    private static func fees(_ lines: [SalesReport.Line], _ txns: [Txn]) -> Double {
        let ids = Set(lines.map(\.saleId))
        return txns.filter { ids.contains($0.id) }.reduce(0) { $0 + $1.fees + $1.shipping + $1.tax }
    }

    private func hero(_ t: SalesReport.Totals, lines: [SalesReport.Line], fees: Double, year: Int) -> some View {
        let gains = lines.reduce(0) { $0 + max(0, $1.gain) }
        let losses = lines.reduce(0) { $0 + min(0, $1.gain) }
        return VStack(alignment: .leading, spacing: 16) {
            VStack(alignment: .leading, spacing: 6) {
                HStack(spacing: 6) {
                    MonoLabel(text: year == 0 ? "Profit, every year" : "Profit in \(String(year))")
                    // The fine print, folded away.
                    Button { info = true } label: {
                        Image(systemName: "info.circle").font(.system(size: 13, weight: .medium)).foregroundStyle(Theme.subtle)
                    }
                    .buttonStyle(.plain)
                    .accessibilityLabel("About these numbers")
                }
                Text(Format.signedMoney(t.gain))
                    .font(.display(48)).tracking(-1.4).monospacedDigit()
                    .foregroundStyle(Theme.tone(t.gain))
                    .lineLimit(1).minimumScaleFactor(0.6)
                Text("From \(t.sales) \(t.sales == 1 ? "sale" : "sales") · \(count(t.quantity)) \(t.quantity == 1 ? "copy" : "copies")")
                    .font(.geist(14)).foregroundStyle(Theme.muted)
            }
            // Gains and losses apart (losses lower the tax), then what came in and went out.
            HStack(spacing: 8) {
                GlassStat(label: "Gains", value: Format.signedMoney(gains), tint: gains > 0 ? Theme.up : Theme.subtle)
                GlassStat(label: "Losses", value: losses < 0 ? Format.signedMoney(losses) : "—", tint: losses < 0 ? Theme.down : Theme.subtle)
            }
            HStack(spacing: 8) {
                GlassStat(label: "Sold for", value: Format.money(t.proceeds))
                GlassStat(label: "They cost", value: Format.money(t.cost))
                GlassStat(label: "Fees", value: fees > 0 ? Format.money(fees) : "—", tint: fees > 0 ? .white : Theme.subtle)
            }
        }
    }

    private func heldSplit(_ t: SalesReport.Totals) -> some View {
        VStack(alignment: .leading, spacing: 12) {
            MoreHeading(title: "How long you held them", subtitle: nil)
            HStack(spacing: 8) {
                heldTile("Over a year", t.longTermGain)
                heldTile("A year or less", t.shortTermGain)
            }
        }
    }

    /// The same glass tile as the figures above; nothing held that long reads as a quiet dash.
    private func heldTile(_ label: String, _ gain: Double) -> some View {
        GlassStat(label: label, value: abs(gain) < 0.005 ? "—" : Format.signedMoney(gain), tint: abs(gain) < 0.005 ? Theme.subtle : Theme.tone(gain))
    }

    private func list(_ lines: [SalesReport.Line]) -> some View {
        VStack(alignment: .leading, spacing: 12) {
            MoreHeading(title: "Every sale", subtitle: "Split by when you got the copies, the way a tax form lists them")
            VStack(spacing: 0) {
                ForEach(Array(lines.enumerated()), id: \.element.id) { i, l in
                    if i > 0 { Divider().overlay(Color.white.opacity(0.06)) }
                    row(l)
                }
            }
            .surface(radius: 16, padding: 14)
        }
    }

    private func row(_ l: SalesReport.Line) -> some View {
        let product = store.products[l.identity.productId]
        return HStack(spacing: 2) {
        CardLink(productId: l.identity.productId, identity: l.identity) {
            HStack(spacing: 12) {
                ProductImage(product: product, cornerRadius: 4)
                    .frame(width: 40, height: 56)
                VStack(alignment: .leading, spacing: 3) {
                    Text(product.map(ActionsSheet.shortName) ?? "Unknown item").font(.geist(14, .semibold)).foregroundStyle(.white).lineLimit(1)
                    Text(detail(l)).font(.geist(12)).foregroundStyle(Theme.muted).lineLimit(1)
                }
                Spacer(minLength: 8)
                VStack(alignment: .trailing, spacing: 3) {
                    Text(Format.signedMoney(l.gain)).font(.geist(14, .semibold)).monospacedDigit().foregroundStyle(Theme.tone(l.gain))
                    Text("sold for \(Format.money(l.proceeds))").font(.geist(12)).monospacedDigit().foregroundStyle(Theme.muted)
                }
            }
            .padding(.vertical, 10)
            .contentShape(Rectangle())
        }
        .buttonStyle(.plain)
        // Edit or delete the sale (the same ⋯ as other lists of cards).
        RowMoreButton(label: product?.name) { acting = SaleRef(id: l.saleId, productId: l.identity.productId) }
        }
    }

    private func detail(_ l: SalesReport.Line) -> String {
        var parts = ["Sold \(Self.short(l.sold))"]
        if let a = l.acquired, let d = SalesReport.daysHeld(from: a, to: l.sold) { parts.append("held \(Self.held(d))") }
        if l.quantity != 1 { parts.append("×\(count(l.quantity))") }
        return parts.joined(separator: " · ")
    }

    private func count(_ q: Double) -> String { q == q.rounded() ? String(Int(q)) : String(q) }

    private static func short(_ day: String) -> String {
        guard let d = Format.isoDay.date(from: day) else { return day }
        return d.formatted(.dateTime.month(.abbreviated).day())
    }

    private static func held(_ days: Int) -> String {
        if days < 60 { return "\(days) \(days == 1 ? "day" : "days")" }
        let months = Int((Double(days) / 30.44).rounded())
        if months < 24 { return "\(months) months" }
        let years = Double(days) / 365.25
        return String(format: "%.1f years", years)
    }
}

/// The sales spreadsheet, written when you share it.
struct SalesFile: Transferable {
    var csv: String
    var name: String

    static var transferRepresentation: some TransferRepresentation {
        FileRepresentation(exportedContentType: .commaSeparatedText) { file in
            let url = FileManager.default.temporaryDirectory.appendingPathComponent("\(file.name).csv")
            try Data(file.csv.utf8).write(to: url, options: .atomic)
            return SentTransferredFile(url)
        }
    }
}

/// A sale, for its ⋯ sheet.
private struct SaleRef: Identifiable { var id: String; var productId: String }
