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

    /// "3d old" for a price last updated more than a day and a half ago (nil when it's current),
    /// so an older price is never mistaken for today's.
    static func priceAge(_ iso: String?) -> String? {
        guard let iso else { return nil }
        let f = ISO8601DateFormatter()
        f.formatOptions = [.withInternetDateTime, .withFractionalSeconds]
        guard let date = f.date(from: iso) ?? ISO8601DateFormatter().date(from: iso) else { return nil }
        let hours = Date().timeIntervalSince(date) / 3600
        guard hours > 36 else { return nil }
        let days = Int((hours / 24).rounded())
        return days < 60 ? "\(days)d old" : "\(days / 30)mo old"
    }
}
