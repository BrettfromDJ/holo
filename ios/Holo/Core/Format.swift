import Foundation

enum Format {
    private static let usd: NumberFormatter = {
        let f = NumberFormatter()
        f.numberStyle = .currency
        f.currencyCode = "USD"
        f.locale = Locale(identifier: "en_US")
        return f
    }()

    private static let usdWhole: NumberFormatter = {
        let f = NumberFormatter()
        f.numberStyle = .currency
        f.currencyCode = "USD"
        f.locale = Locale(identifier: "en_US")
        f.maximumFractionDigits = 0
        return f
    }()

    /// "$1,234.56", or an em dash for unknown (never "$0.00" for a missing price).
    static func money(_ value: Double?) -> String {
        guard let v = value, v.isFinite else { return "—" }
        return usd.string(from: NSNumber(value: v)) ?? "—"
    }

    static func moneyWhole(_ value: Double?) -> String {
        guard let v = value, v.isFinite else { return "—" }
        return usdWhole.string(from: NSNumber(value: v)) ?? "—"
    }

    static func signedMoney(_ value: Double?) -> String {
        guard let v = value, v.isFinite else { return "—" }
        let s = money(abs(v))
        return v < 0 ? "−\(s)" : "+\(s)"
    }

    /// A ratio (0.123) as "+12.3%".
    static func signedPercent(_ ratio: Double?) -> String {
        guard let r = ratio, r.isFinite else { return "—" }
        let pct = String(format: "%.1f%%", abs(r) * 100)
        return r < 0 ? "−\(pct)" : "+\(pct)"
    }

    /// Dates are stored as yyyy-MM-dd strings, like the web app.
    static let isoDay: DateFormatter = {
        let f = DateFormatter()
        f.calendar = Calendar(identifier: .gregorian)
        f.locale = Locale(identifier: "en_US_POSIX")
        f.timeZone = TimeZone.current
        f.dateFormat = "yyyy-MM-dd"
        return f
    }()

    static func day(_ date: Date = Date()) -> String { isoDay.string(from: date) }
}
