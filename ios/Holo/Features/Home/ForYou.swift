import SwiftUI

// "For you" on Home: picks from what you own, refreshed each visit, so there's something worth
// a look even on a quiet market day.
// - Because you collect…: the Pokémon you own most of, and cards of it you don't have yet
//   (Dexora's own catalog, free).
// - Finish your sets: the cheapest cards missing from the sets you're closest to finishing.
// - In your range: this week's risers near what you usually pay for a single, from the era you
//   collect most (when one stands out).
// All of it is worked out on the phone from your own records: no Claude, nothing paid.
// The lines under each are plain facts worked out here; Claude's written reasons can replace
// them once the daily insights are switched on.

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
    var hasContent: Bool { !picks.isEmpty || !sets.isEmpty || !inRange.isEmpty }

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
            let byEra = era == "vintage" ? eras.vintage : era == "midEra" ? eras.midEra : era == "modern" ? eras.modern : []
            let pool = byEra + (index.today ?? []) + (index.trending ?? []) + eras.modern + eras.midEra + eras.vintage
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
                let sorted = usual.map { u in fresh.sorted { abs(log(($0.market ?? 1) / u)) < abs(log(($1.market ?? 1) / u)) } }
                    ?? fresh.sorted { ($0.market ?? 0) > ($1.market ?? 0) }
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
        sets = Array(mine.compactMap { s -> SetToFinish? in
            guard let list = cache.checklists[s.id], !list.isEmpty else { return nil }
            let have = list.filter { owned.contains($0.product.id) }.count
            guard have < list.count else { return nil }
            let missing = list.filter { !owned.contains($0.product.id) && ($0.market ?? 0) > 0 }
                .sorted { ($0.market ?? 0) < ($1.market ?? 0) }
            guard !missing.isEmpty else { return nil }
            return SetToFinish(id: s.id, name: s.name, owned: have, total: list.count, cheapest: Array(missing.prefix(5)))
        }
        .sorted { $0.share > $1.share }
        .prefix(2))
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
            if let taste = model.taste, !model.picks.isEmpty {
                becauseYouCollect(taste, picks: model.picks)
            }
            if !model.inRange.isEmpty, let usual = model.usual {
                inYourRange(model.inRange, usual: usual, era: model.era)
            }
            if !model.sets.isEmpty {
                finishYourSets(model.sets)
            }
        }
    }

    // MARK: Because you collect…

    private func becauseYouCollect(_ t: (name: String, count: Int), picks: [SearchHit]) -> some View {
        VStack(alignment: .leading, spacing: 10) {
            VStack(alignment: .leading, spacing: 3) {
                Text("Because you collect \(t.name)").font(.geist(17, .semibold))
                Text("You own \(t.count) \(t.name) cards. Here are some you don't have\u{00A0}yet.").font(.geist(13)).foregroundStyle(Theme.muted)
            }
            .padding(.horizontal, 16)
            ScrollView(.horizontal, showsIndicators: false) {
                HStack(alignment: .top, spacing: 12) {
                    ForEach(picks) { hit in
                        MarketLink(hit: hit) { PickTile(hit: hit) }
                    }
                }
                .padding(.horizontal, 16)
                .padding(.vertical, 4)
            }
            .cardSequence(picks.map(\.product.id))
        }
    }

    // MARK: In your range

    private func inYourRange(_ hits: [SearchHit], usual: Double, era: String?) -> some View {
        VStack(alignment: .leading, spacing: 10) {
            VStack(alignment: .leading, spacing: 3) {
                Text(era.map { "Rising \(CollectorTaste.eraName($0)), in your range" } ?? "Rising in your range").font(.geist(17, .semibold))
                Text("You usually pay about \(Format.money(usual)) a card. These are up this\u{00A0}week.").font(.geist(13)).foregroundStyle(Theme.muted)
            }
            .padding(.horizontal, 16)
            ScrollView(.horizontal, showsIndicators: false) {
                HStack(alignment: .top, spacing: 12) {
                    ForEach(hits) { hit in
                        MarketLink(hit: hit) { PickTile(hit: hit, showsChange: true) }
                    }
                }
                .padding(.horizontal, 16)
                .padding(.vertical, 4)
            }
            .cardSequence(hits.map(\.product.id))
        }
    }

    // MARK: Finish your sets

    private func finishYourSets(_ sets: [SetToFinish]) -> some View {
        VStack(alignment: .leading, spacing: 10) {
            VStack(alignment: .leading, spacing: 3) {
                Text("Finish your sets").font(.geist(17, .semibold))
                Text("The cheapest cards missing from the sets you're closest to\u{00A0}finishing.").font(.geist(13)).foregroundStyle(Theme.muted)
            }
            .padding(.horizontal, 16)
            VStack(spacing: 10) {
                ForEach(sets) { s in SetToFinishCard(set: s) }
            }
            .padding(.horizontal, 16)
        }
    }

}

/// A picked card: its picture, name and price.
private struct PickTile: View {
    var hit: SearchHit
    var showsChange = false

    var body: some View {
        VStack(alignment: .leading, spacing: 8) {
            ProductImage(product: hit.pictured, cornerRadius: 5).frame(width: 96, height: 134)
            VStack(alignment: .leading, spacing: 2) {
                Text(hit.product.name).font(.geist(13, .medium)).foregroundStyle(.white).lineLimit(1)
                Text(hit.product.setName ?? "").font(.geist(11)).foregroundStyle(Theme.muted).lineLimit(1)
                HStack(alignment: .firstTextBaseline, spacing: 6) {
                    Text(Format.money(hit.market)).font(.display(16)).tracking(-0.4).monospacedDigit().foregroundStyle(.white)
                    if showsChange, let c = hit.change7dPct ?? hit.change24hPct {
                        Text("\(c >= 0 ? "+" : "")\(Int(c.rounded()))%").font(.geist(11, .semibold)).monospacedDigit()
                            .foregroundStyle(c >= 0 ? Theme.lime : Theme.planPink)
                    }
                }
            }
        }
        .frame(width: 96, alignment: .leading)
        .contentShape(Rectangle())
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
