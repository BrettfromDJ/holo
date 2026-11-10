import CoreTransferable
import SwiftUI
import UniformTypeIdentifiers

/// Sales & taxes: what you sold in a year, what those copies cost, and the profit, split by how
/// long you held them, with a spreadsheet to hand to an accountant. Covers every portfolio.
struct SalesView: View {
    @Environment(CollectionStore.self) private var store
    @State private var year: Int?

    var body: some View {
        // Every sale, once per log change (few lines, cheap).
        let all = SalesReport.lines(store.transactions)
        let years = SalesReport.years(all)
        let shown = year ?? years.first ?? Calendar.current.component(.year, from: Date())
        let lines = all.filter { $0.year == shown }
        let t = SalesReport.totals(lines)
        ScrollView {
            if all.isEmpty {
                EmptyPage(title: "No sales yet", line: "When you sell something, mark it sold on its page. Your profit for the year shows up here, ready for tax time.",
                          icon: "doc.text")
                    .padding(.top, 40)
            } else {
                VStack(alignment: .leading, spacing: 32) {
                    if years.count > 1 {
                        ChipPicker(options: years.map { ($0, String($0)) }, selection: Binding(get: { shown }, set: { year = $0 }), scrolls: true)
                            .fixedSize(horizontal: false, vertical: true)
                    }
                    hero(t, year: shown)
                    heldSplit(t)
                    export(lines, year: shown)
                    list(lines)
                    Text("Profit is what each sale brought in after its fees, shipping and tax, minus what those copies cost you, oldest copies first. Cards you pulled count as costing nothing. A guide for your records, not tax\u{00A0}advice.")
                        .font(.geist(12)).foregroundStyle(Theme.subtle)
                }
                .padding(.horizontal, 16)
                .padding(.top, 8)
                .padding(.bottom, 120)
            }
        }
        .background(Theme.background)
        .navigationBarTitleDisplayMode(.inline)
        .pageTitle("Sales & taxes")
    }

    private func hero(_ t: SalesReport.Totals, year: Int) -> some View {
        VStack(alignment: .leading, spacing: 16) {
            VStack(alignment: .leading, spacing: 6) {
                MonoLabel(text: "Profit in \(String(year))")
                Text(Format.signedMoney(t.gain))
                    .font(.display(48)).tracking(-1.4).monospacedDigit()
                    .foregroundStyle(Theme.tone(t.gain))
                    .lineLimit(1).minimumScaleFactor(0.6)
                Text("From \(t.sales) \(t.sales == 1 ? "sale" : "sales") · \(count(t.quantity)) \(t.quantity == 1 ? "copy" : "copies")")
                    .font(.geist(14)).foregroundStyle(Theme.muted)
            }
            HStack(spacing: 8) {
                GlassStat(label: "Sold for", value: Format.money(t.proceeds))
                GlassStat(label: "They cost", value: Format.money(t.cost))
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
            Text("In the US, collectibles held over a year are taxed at up to 28%. A year or less is taxed like income. Your accountant will know what applies to\u{00A0}you.")
                .font(.geist(12)).foregroundStyle(Theme.subtle)
        }
    }

    private func heldTile(_ label: String, _ gain: Double) -> some View {
        VStack(alignment: .leading, spacing: 6) {
            MonoLabel(text: label)
            Text(Format.signedMoney(gain)).font(.display(24)).tracking(-0.6).monospacedDigit()
                .foregroundStyle(gain == 0 ? .white : Theme.tone(gain))
                .lineLimit(1).minimumScaleFactor(0.6)
        }
        .frame(maxWidth: .infinity, alignment: .leading)
        .surface(radius: 16, padding: 14)
    }

    private func export(_ lines: [SalesReport.Line], year: Int) -> some View {
        let file = SalesFile(csv: SalesReport.csv(lines, products: store.products), name: "Dexora sales \(year)")
        return ShareLink(item: file, preview: SharePreview(file.name)) {
            HStack(spacing: 8) {
                Image(systemName: "square.and.arrow.up").font(.system(size: 16, weight: .semibold))
                Text("Export for your accountant").font(.geist(16, .semibold))
            }
            .foregroundStyle(Theme.ink)
            .frame(maxWidth: .infinity)
            .frame(height: 52)
            .background(Capsule().fill(Theme.lime))
        }
        .buttonStyle(.plain)
        .simultaneousGesture(TapGesture().onEnded { Haptics.tap() })
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
        return CardLink(productId: l.identity.productId, identity: l.identity) {
            HStack(spacing: 12) {
                ProductImage(product: product, cornerRadius: 4)
                    .frame(width: 40, height: 56)
                VStack(alignment: .leading, spacing: 3) {
                    Text(product?.name ?? "Unknown item").font(.geist(14, .semibold)).foregroundStyle(.white).lineLimit(1)
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
