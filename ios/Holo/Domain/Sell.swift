import Foundation

/// "What if I sell?" estimates, ported from the website's `src/lib/finance/sell.ts`. Platform
/// fees are editable presets, not a live feed, so they're labelled estimates.
enum Sell {
    enum Platform: String, CaseIterable, Identifiable {
        case ebay, tcgplayer, local, custom
        var id: String { rawValue }

        var label: String {
            switch self {
            case .ebay: return "eBay"
            case .tcgplayer: return "TCGplayer"
            case .local: return "In person"
            case .custom: return "Custom"
            }
        }

        var fees: Fees {
            switch self {
            case .ebay: return Fees(percent: 13.25, fixed: 0.4)
            case .tcgplayer: return Fees(percent: 13.25, fixed: 0.3)
            case .local, .custom: return Fees(percent: 0, fixed: 0)
            }
        }

        var note: String {
            switch self {
            case .ebay: return "Trading cards final value fee + per-order fee (estimate)"
            case .tcgplayer: return "Marketplace commission + payment processing (estimate)"
            case .local: return "No platform fees"
            case .custom: return "Enter your own fees"
            }
        }
    }

    struct Fees: Equatable {
        /// Percentage of the order total (item price + shipping charged to the buyer).
        var percent: Double
        /// Fixed fee per order.
        var fixed: Double
    }

    struct Estimate {
        var gross = 0.0
        var platformFees = 0.0
        /// What you keep after fees and shipping.
        var net = 0.0
        /// Cost of the units sold, oldest first.
        var costBasis = 0.0
        var profit = 0.0
        var profitPct: Double?
        /// Price per unit at which profit is exactly zero.
        var breakEven: Double?
        /// Units actually sold (clamped to what you hold).
        var quantity = 0.0
    }

    static func estimate(lots: [Lot], quantity: Double, unitPrice: Double, fees: Fees, shippingCharged: Double, shippingCost: Double) -> Estimate {
        let held = lots.reduce(0) { $0 + $1.quantity }
        let q = max(0, min(quantity, held))
        let rate = max(0, fees.percent) / 100
        var e = Estimate()
        e.quantity = q
        e.gross = q * unitPrice
        e.platformFees = q > 0 ? (e.gross + shippingCharged) * rate + fees.fixed : 0
        e.net = e.gross + shippingCharged - e.platformFees - shippingCost
        var left = q
        for lot in lots where left > 0 {
            let take = min(lot.quantity, left)
            e.costBasis += take * lot.unitCost
            left -= take
        }
        e.profit = e.net - e.costBasis
        e.profitPct = e.costBasis > 0 ? e.profit / e.costBasis : nil
        // Solve q·p·(1−r) + S·(1−r) − fixed − shippingCost = basis for p.
        if q > 0, rate < 1 {
            e.breakEven = max(0, (e.costBasis + fees.fixed + shippingCost - shippingCharged * (1 - rate)) / (q * (1 - rate)))
        }
        return e
    }
}
