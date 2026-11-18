import SwiftUI

// "For you" on Home: your own progress, worked out on the phone from your records (no Claude,
// nothing paid).
// - Finish your sets: the cheapest cards missing from sets you're at least halfway through.
// - Your week's budget: what's left of your monthly budget, split over the weeks left, and a mix
//   that fits: a card toward a set, one of the Pokémon you collect, one near what you usually pay.
// The discovery rows (themed collections) are in Themes.swift; CollectorTaste here steers them.

/// What you collect most, from your singles: the Pokémon's name without its card type and
/// number ("Pikachu ex - 238/191" → Pikachu, "Dark Gengar" → Gengar, "Umbreon VMAX" → Umbreon).
enum CollectorTaste {
    private static let suffixes: Set<String> = ["ex", "gx", "v", "vmax", "vstar", "v-union", "lv.x", "break", "prime", "legend", "star", "δ", "★", "&"]

    static func pokemon(in name: String) -> String? {
        var n = name
        if let dash = n.range(of: " - ") { n = String(n[..<dash.lowerBound]) }
        n = n.replacingOccurrences(of: #"\([^)]*\)"#, with: " ", options: .regularExpression)
        let words = n.split(separator: " ").map(String.init).filter { !suffixes.contains($0.lowercased()) && !$0.allSatisfy(\.isNumber) }
        guard let last = words.last, last.count >= 3, last.first?.isLetter == true else { return nil }
        return last
    }

    /// The Pokémon you own the most cards of (two or more), with how many.
    static func favourite(_ holdings: [HoldingView]) -> (name: String, count: Int)? {
        var counts: [String: Int] = [:]
        for h in holdings where h.product?.isSealed == false {
            guard let name = h.product.flatMap({ pokemon(in: $0.name) }) else { continue }
            counts[name, default: 0] += Int(h.quantity)
        }
        guard let best = counts.max(by: { $0.value != $1.value ? $0.value < $1.value : $0.key > $1.key }), best.value >= 2 else { return nil }
        return (best.key, best.value)
    }

    /// What you usually pay for a single: the middle of what each of your singles cost a copy
    /// (needs three with a price paid).
    static func usualPrice(_ holdings: [HoldingView]) -> Double? {
        let paid = holdings.compactMap { h -> Double? in
            guard h.product?.isSealed == false, h.quantity > 0, h.costBasis > 0 else { return nil }
            return h.costBasis / h.quantity
        }.sorted()
        guard paid.count >= 3 else { return nil }
        return paid[paid.count / 2]
    }

    /// The prices to suggest around what you usually pay: half of it to double it.
    static func range(around usual: Double) -> ClosedRange<Double> { max(1, usual * 0.5)...max(2, usual * 2) }

    /// The era most of your singles come from ("vintage", "midEra" or "modern"), when at least
    /// three of them and six in ten share it.
    static func era(_ holdings: [HoldingView], released: [String: String]) -> String? {
        var counts: [String: Int] = [:]
        for h in holdings where h.product?.isSealed == false {
            guard let set = h.product?.setName, let e = MarketEras.era(of: released[set]) else { continue }
            counts[e, default: 0] += 1
        }
        let total = counts.values.reduce(0, +)
        guard let best = counts.max(by: { $0.value < $1.value }), best.value >= 3, Double(best.value) >= Double(total) * 0.6 else { return nil }
        return best.key
    }

    static func eraName(_ era: String) -> String { era == "midEra" ? "mid-era" : era }
}

/// One set you could finish: how far along you are and the cheapest cards still missing.
struct SetToFinish: Identifiable {
    var id: String
    var name: String
    var owned: Int
    var total: Int
    /// The cheapest priced cards you don't have, cheapest first.
    var cheapest: [SearchHit]

    var share: Double { total > 0 ? Double(owned) / Double(total) : 0 }
    /// The share once the cheapest few are added.
    var shareAfter: Double { total > 0 ? Double(owned + cheapest.count) / Double(total) : 0 }
    var cost: Double { cheapest.reduce(0) { $0 + ($1.market ?? 0) } }
}

/// For you's picks, worked out from your collection (held by Home, which shows the section only
/// when there's something in it).
@Observable
final class ForYouModel {
    var taste: (name: String, count: Int)?
    var picks: [SearchHit] = []
    var sets: [SetToFinish] = []
    /// What you usually pay a single, and the era you collect most (nil when none stands out).
    var usual: Double?
    var era: String?
    /// This week's risers in your price range (and era).
    var inRange: [SearchHit] = []
    /// What's yours to spend this week, and a mix of picks that fits in it.
    var week: (amount: Double, basket: [SearchHit])?
    /// The share of a set you need before Finish your sets suggests it.
    static let setThreshold = 0.5
    /// Shown: Finish your sets and Your week's budget (picks and in-range cards only fill the budget's mix).
    var hasContent: Bool { !sets.isEmpty || week != nil }

    @MainActor
    func load(store: CollectionStore, index: ExploreIndex?) async {
        guard store.status == .ready || store.demo != nil else { return }
        let holdings = store.allHoldings
        let owned = Set(holdings.map(\.identity.productId))
        usual = CollectorTaste.usualPrice(holdings)
        let range = usual.map(CollectorTaste.range(around:))

        // In your range: the week's risers you don't own, near what you usually pay, from your era.
        if let index {
            var released: [String: String] = [:]
            for s in index.sets { if let d = s.releaseDate { released[s.name] = d } }
            era = CollectorTaste.era(holdings, released: released)
            let eras = index.eras ?? MarketEras()
            var pool: [SearchHit] = []
            switch era {
            case "vintage": pool = eras.vintage
            case "midEra": pool = eras.midEra
            case "modern": pool = eras.modern
            default: break
            }
            pool += index.today ?? []
            pool += index.trending ?? []
            pool += eras.modern
            pool += eras.midEra
            pool += eras.vintage
            var seen = Set<String>()
            inRange = Array(pool.filter { hit in
                guard !hit.product.isSealed, !owned.contains(hit.product.id), let m = hit.market, m > 0, seen.insert(hit.product.id).inserted else { return false }
                if let range, !range.contains(m) { return false }
                if let era, let e = MarketEras.era(of: hit.releaseDate ?? hit.product.setName.flatMap { released[$0] }), e != era { return false }
                return true
            }.prefix(10))
            // Without a usual price there's nothing personal about it.
            if range == nil { inRange = [] }

        }

        // Because you collect…: cards of your favourite Pokémon you don't own, priced, best first.
        if let t = CollectorTaste.favourite(holdings) {
            taste = t
            if let hits = try? await Backend.shared.api.search(t.name) {
                let fresh = hits.filter { !$0.product.isSealed && !owned.contains($0.product.id) && ($0.market ?? 0) > 0
                    && CollectorTaste.pokemon(in: $0.product.name) == t.name }
                // Closest to what you usually pay first; without that, the best first.
                func distance(_ hit: SearchHit, _ u: Double) -> Double { abs(log((hit.market ?? 1) / u)) }
                let sorted: [SearchHit]
                if let u = usual {
                    sorted = fresh.sorted { distance($0, u) < distance($1, u) }
                } else {
                    sorted = fresh.sorted { ($0.market ?? 0) > ($1.market ?? 0) }
                }
                picks = Array(sorted.prefix(10))
            }
        } else {
            taste = nil
            picks = []
        }

        // Finish your sets: your four biggest sets' card lists (shared with Master Sets), then the
        // two with the most done that aren't finished.
        let mine = Array(MasterSetDetailView.ownedSets(holdings).prefix(4))
        await MasterSetDetailView.load(mine, store: store)
        let cache = MasterSetsCache.shared
        defer { planWeek(store: store) }
        sets = Array(mine.compactMap { s -> SetToFinish? in
            guard let list = cache.checklists[s.id], !list.isEmpty else { return nil }
            let have = list.filter { owned.contains($0.product.id) }.count
            // Most people don't chase whole sets: only once you have half of one does it show.
            guard have < list.count, Double(have) >= Double(list.count) * ForYouModel.setThreshold else { return nil }
            let missing = list.filter { !owned.contains($0.product.id) && ($0.market ?? 0) > 0 }
                .sorted { ($0.market ?? 0) < ($1.market ?? 0) }
            guard !missing.isEmpty else { return nil }
            return SetToFinish(id: s.id, name: s.name, owned: have, total: list.count, cheapest: Array(missing.prefix(5)))
        }
        .sorted { $0.share > $1.share }
        .prefix(2))
    }

    /// This week's share of what's left of your monthly budget (a demo pretends $400 a month), and
    /// a mix that fits: a card toward a set first, then one of your Pokémon, then one in your range,
    /// round and round while there's room.
    @MainActor
    private func planWeek(store: CollectionStore) {
        guard let budget = store.monthlyBudget ?? (store.demo != nil ? 400 : nil), budget > 0 else { week = nil; return }
        let cal = Calendar.current
        let now = Date()
        let daysInMonth = cal.range(of: .day, in: .month, for: now)?.count ?? 30
        let daysLeft = daysInMonth - cal.component(.day, from: now) + 1
        let weeksLeft = max(1, Int((Double(daysLeft) / 7).rounded(.up)))
        let left = budget - (store.demo != nil ? budget * 0.35 : store.spentThisMonth)
        guard left > 1 else { week = (0, []); return }
        let amount = left / Double(weeksLeft)
        let lanes: [[SearchHit]] = [sets.flatMap(\.cheapest), picks, inRange]
        var basket: [SearchHit] = [], spent = 0.0, used = Set<String>()
        var progressed = true
        var cursors = [0, 0, 0]
        while progressed && basket.count < 5 {
            progressed = false
            for lane in 0..<lanes.count {
                while cursors[lane] < lanes[lane].count {
                    let hit = lanes[lane][cursors[lane]]
                    cursors[lane] += 1
                    guard let m = hit.market, m > 0, !used.contains(hit.product.id), spent + m <= amount else { continue }
                    basket.append(hit); spent += m; used.insert(hit.product.id); progressed = true
                    break
                }
                if basket.count >= 5 { break }
            }
        }
        week = (amount, basket)
    }
}

struct ForYouSection: View {
    var model: ForYouModel

    var body: some View {
        VStack(alignment: .leading, spacing: 18) {
            HStack(spacing: 8) {
                Image(systemName: "sparkles").font(.system(size: 13, weight: .semibold)).foregroundStyle(Theme.subtle)
                Text("For you").font(.display(24)).tracking(-0.6)
            }
            .padding(.horizontal, 16)
            if !model.sets.isEmpty {
                finishYourSets(model.sets)
            }
            if let week = model.week {
                WeekBudgetCard(amount: week.amount, basket: week.basket).padding(.horizontal, 16)
            }
        }
    }

    // MARK: Finish your sets

    private func finishYourSets(_ sets: [SetToFinish]) -> some View {
        VStack(alignment: .leading, spacing: 10) {
            VStack(alignment: .leading, spacing: 3) {
                Text("Finish your sets").font(.geist(17, .semibold))
                Text("You're over halfway there. The cheapest cards still\u{00A0}missing.").font(.geist(13)).foregroundStyle(Theme.muted)
            }
            .padding(.horizontal, 16)
            VStack(spacing: 10) {
                ForEach(sets) { s in SetToFinishCard(set: s) }
            }
            .padding(.horizontal, 16)
        }
    }

}

/// A set to finish: its name, the progress now and with the cheapest few, and those cards.
private struct SetToFinishCard: View {
    var set: SetToFinish

    var body: some View {
        VStack(alignment: .leading, spacing: 12) {
            NavigationLink(value: MasterSetRoute(id: set.id, name: set.name)) {
                VStack(alignment: .leading, spacing: 8) {
                    HStack {
                        Text(set.name).font(.geist(16, .semibold)).foregroundStyle(.white).lineLimit(1)
                        Spacer(minLength: 8)
                        Image(systemName: "chevron.right").font(.system(size: 12, weight: .semibold)).foregroundStyle(Theme.muted)
                    }
                    // Now, and with the cheapest few added (the lighter part of the bar).
                    GeometryReader { geo in
                        ZStack(alignment: .leading) {
                            Capsule().fill(Color.white.opacity(0.08))
                            Capsule().fill(Theme.lime.opacity(0.35)).frame(width: max(6, geo.size.width * set.shareAfter))
                            Capsule().fill(Theme.lime).frame(width: max(6, geo.size.width * set.share))
                        }
                    }
                    .frame(height: 6)
                    (Text("\(set.cheapest.count) card\(set.cheapest.count == 1 ? "" : "s") for ").foregroundColor(Theme.muted)
                     + Text(Format.money(set.cost)).foregroundColor(.white).fontWeight(.semibold)
                     + Text(" take you from \(Int((set.share * 100).rounded()))% to ").foregroundColor(Theme.muted)
                     + Text("\(Int((set.shareAfter * 100).rounded()))%").foregroundColor(Theme.lime).fontWeight(.semibold))
                        .font(.geist(13)).monospacedDigit()
                }
                .contentShape(Rectangle())
            }
            .buttonStyle(.plain)
            HStack(spacing: 8) {
                ForEach(set.cheapest) { hit in
                    MarketLink(hit: hit) {
                        VStack(spacing: 4) {
                            ProductImage(product: hit.pictured, cornerRadius: 4).frame(width: 54, height: 75)
                            Text(Format.money(hit.market)).font(.geist(11, .semibold)).monospacedDigit().foregroundStyle(.white)
                        }
                    }
                }
                Spacer(minLength: 0)
            }
            .cardSequence(set.cheapest.map(\.product.id))
        }
        .padding(14)
        .background(RoundedRectangle(cornerRadius: 18, style: .continuous).fill(Theme.surface))
        .overlay(RoundedRectangle(cornerRadius: 18, style: .continuous).strokeBorder(Theme.border))
    }
}

/// Your week's budget: how much is yours to spend, a bar of how a mix of picks would use it, and
/// those picks. Nothing is bought or saved; it's an idea.
private struct WeekBudgetCard: View {
    var amount: Double
    var basket: [SearchHit]

    private var total: Double { basket.reduce(0) { $0 + ($1.market ?? 0) } }

    var body: some View {
        VStack(alignment: .leading, spacing: 12) {
            VStack(alignment: .leading, spacing: 3) {
                Text("Your week's budget").font(.geist(17, .semibold))
                if amount <= 0 {
                    Text("This month's budget is spent. Next month starts\u{00A0}fresh.").font(.geist(13)).foregroundStyle(Theme.muted)
                } else {
                    (Text(Format.money(amount)).foregroundColor(.white).fontWeight(.semibold)
                     + Text(" left for this week. One way to use it:").foregroundColor(Theme.muted))
                        .font(.geist(13)).monospacedDigit()
                }
            }
            if amount > 0, !basket.isEmpty {
                // How the mix splits the week: one lime piece per card, the rest left over.
                GeometryReader { geo in
                    HStack(spacing: 2) {
                        ForEach(Array(basket.enumerated()), id: \.element.id) { i, hit in
                            Capsule().fill(Theme.lime.opacity(1 - Double(i) * 0.15))
                                .frame(width: max(4, (geo.size.width - CGFloat(basket.count) * 2) * (hit.market ?? 0) / amount))
                        }
                        Capsule().fill(Color.white.opacity(0.08))
                    }
                }
                .frame(height: 6)
                VStack(spacing: 8) {
                    ForEach(basket) { hit in
                        MarketLink(hit: hit) {
                            HStack(spacing: 10) {
                                ProductImage(product: hit.pictured, cornerRadius: 3).frame(width: 30, height: 42)
                                VStack(alignment: .leading, spacing: 1) {
                                    Text(hit.product.name).font(.geist(13, .medium)).foregroundStyle(.white).lineLimit(1)
                                    Text(hit.product.setName ?? "").font(.geist(11)).foregroundStyle(Theme.muted).lineLimit(1)
                                }
                                Spacer(minLength: 8)
                                Text(Format.money(hit.market)).font(.geist(13, .semibold)).monospacedDigit().foregroundStyle(.white)
                            }
                            .contentShape(Rectangle())
                        }
                    }
                }
                .cardSequence(basket.map(\.product.id))
                (Text(Format.money(total)).foregroundColor(.white).fontWeight(.semibold)
                 + Text(" of \(Format.money(amount)), \(Format.money(max(0, amount - total))) to spare").foregroundColor(Theme.muted))
                    .font(.geist(12)).monospacedDigit()
            }
        }
        .padding(14)
        .background(RoundedRectangle(cornerRadius: 18, style: .continuous).fill(Theme.surface))
        .overlay(RoundedRectangle(cornerRadius: 18, style: .continuous).strokeBorder(Theme.border))
    }
}
