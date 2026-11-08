import Foundation

/// What you sold, matched to what those copies cost, for a year-end summary or an accountant.
/// Copies leave oldest first (FIFO), exactly like `Ledger`, so the profit here adds up to the
/// realized gain shown everywhere else. A sale that takes copies bought on different days is split
/// into one line per purchase date, the way a tax form lists it. Mirrors src/lib/finance/sales-report.ts.
enum SalesReport {
    struct Line: Identifiable, Hashable {
        /// The sale, plus which of its purchase dates this line covers.
        var id: String
        var saleId: String
        var identity: HoldingIdentity
        /// yyyy-MM-dd the copies were bought or pulled (nil if they were never recorded).
        var acquired: String?
        /// yyyy-MM-dd they were sold.
        var sold: String
        var quantity: Double
        /// What they sold for after the sale's fees, shipping and tax.
        var proceeds: Double
        /// What they cost, extras included.
        var cost: Double
        var gain: Double { proceeds - cost }
        /// Held more than a year (the US long-term rule).
        var longTerm: Bool
        var year: Int { Int(sold.prefix(4)) ?? 0 }
    }

    struct Totals: Hashable {
        var proceeds = 0.0
        var cost = 0.0
        var gain = 0.0
        var shortTermGain = 0.0
        var longTermGain = 0.0
        /// Copies sold.
        var quantity = 0.0
        /// Separate sales (one sale split over several purchase dates counts once).
        var sales = 0
    }

    private struct OpenLot { var date: String; var quantity: Double; var unitCost: Double }
    private static let eps = 1e-9

    /// Every sale in the log, newest first, split by purchase date.
    static func lines(_ transactions: [Txn]) -> [Line] {
        var lots: [String: [OpenLot]] = [:]
        var out: [Line] = []

        func consume(_ key: String, _ qty: Double) -> [(OpenLot, Double)] {
            var remaining = qty
            var taken: [(OpenLot, Double)] = []
            var open = lots[key] ?? []
            for i in open.indices {
                if remaining <= eps { break }
                let take = min(open[i].quantity, remaining)
                if take > eps { taken.append((open[i], take)) }
                open[i].quantity -= take
                remaining -= take
            }
            lots[key] = open.filter { $0.quantity > eps }
            return taken
        }

        for t in Ledger.effective(transactions) {
            let key = t.identity.key
            switch t.kind {
            case .purchase where t.quantity > 0:
                lots[key, default: []].append(OpenLot(date: t.date, quantity: t.quantity, unitCost: t.acquisitionCost / t.quantity))
            case .adjustment where t.quantity > 0:
                lots[key, default: []].append(OpenLot(date: t.date, quantity: t.quantity, unitCost: t.acquisitionCost / t.quantity))
            case .adjustment where t.quantity < 0:
                // Lost or given away: those copies are gone, but nothing was sold.
                _ = consume(key, -t.quantity)
            case .sale where t.quantity > 0:
                let taken = consume(key, t.quantity)
                let perUnit = t.saleProceeds / t.quantity
                for (n, (lot, qty)) in taken.enumerated() {
                    out.append(Line(id: "\(t.id)#\(n)", saleId: t.id, identity: t.identity, acquired: lot.date, sold: t.date,
                                    quantity: qty, proceeds: perUnit * qty, cost: lot.unitCost * qty,
                                    longTerm: heldOverAYear(from: lot.date, to: t.date)))
                }
            default:
                break
            }
        }
        return out.sorted { $0.sold != $1.sold ? $0.sold > $1.sold : $0.id < $1.id }
    }

    /// The years with at least one sale, newest first.
    static func years(_ lines: [Line]) -> [Int] {
        Array(Set(lines.map(\.year))).sorted(by: >)
    }

    static func totals(_ lines: [Line]) -> Totals {
        var t = Totals()
        for l in lines {
            t.proceeds += l.proceeds
            t.cost += l.cost
            t.gain += l.gain
            if l.longTerm { t.longTermGain += l.gain } else { t.shortTermGain += l.gain }
            t.quantity += l.quantity
        }
        t.sales = Set(lines.map(\.saleId)).count
        return t
    }

    /// More than one year: sold after the first anniversary of the purchase.
    static func heldOverAYear(from acquired: String, to sold: String) -> Bool {
        guard let y = Int(acquired.prefix(4)) else { return false }
        let anniversary = String(y + 1) + acquired.dropFirst(4)
        return sold > anniversary
    }

    /// Whole days between two yyyy-MM-dd dates.
    static func daysHeld(from acquired: String, to sold: String) -> Int? {
        guard let a = Format.isoDay.date(from: acquired), let b = Format.isoDay.date(from: sold) else { return nil }
        return Calendar(identifier: .gregorian).dateComponents([.day], from: a, to: b).day
    }

    /// A spreadsheet of the lines, laid out like a capital gains form: what, when bought, when
    /// sold, what it sold for, what it cost, and the gain.
    static func csv(_ lines: [Line], products: [String: Product]) -> String {
        func cell(_ s: String) -> String {
            s.contains(where: { $0 == "," || $0 == "\"" || $0 == "\n" }) ? "\"" + s.replacingOccurrences(of: "\"", with: "\"\"") + "\"" : s
        }
        func money(_ v: Double) -> String { String(format: "%.2f", v) }
        var rows = ["Description,Set,Condition or grade,Quantity,Date acquired,Date sold,Proceeds,Cost basis,Gain or loss,Term"]
        for l in lines.sorted(by: { $0.sold != $1.sold ? $0.sold < $1.sold : $0.id < $1.id }) {
            let p = products[l.identity.productId]
            let grade = l.identity.gradeCompany.map { "\($0) \(l.identity.grade ?? "")" } ?? l.identity.condition
            let qty = l.quantity == l.quantity.rounded() ? String(Int(l.quantity)) : String(l.quantity)
            rows.append([
                cell(p?.name ?? "Unknown item"), cell(p?.setName ?? ""), cell(grade), qty,
                l.acquired ?? "", l.sold, money(l.proceeds), money(l.cost), money(l.gain), l.longTerm ? "Long" : "Short",
            ].joined(separator: ","))
        }
        return rows.joined(separator: "\n") + "\n"
    }
}
