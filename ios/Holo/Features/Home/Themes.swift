import SwiftUI

// Home's themed collections, like a streaming app's rows: "Skyridge holos", "Charizard through
// the years", "Every price of Gengar"… Rules over our own catalog, filled on the server
// (`src/lib/explore/themes.ts`, `/api/themes`). Each time the app opens, Home shows a few, in a
// new mix that leans toward what you collect, with something unexpected in it. Each has its own
// look (billboard, fan, timeline, mosaic, ladder, spotlight), so no two rows look the same, and
// each opens its own page with every card in it.

struct MarketTheme: Codable, Identifiable, Hashable {
    var id: String
    var title: String
    var blurb: String
    /// billboard, fan, timeline, mosaic, ladder or spotlight.
    var look: String
    var pokemon: [String]? = nil
    var era: String? = nil
    /// One of this week's new ideas (tagged New).
    var fresh: Bool? = nil
    var hits: [SearchHit]
}

@Observable
final class ThemesModel {
    var all: [MarketTheme] = ThemesModel.saved
    /// The few on Home this time, in order.
    var shown: [MarketTheme] = []

    /// A new mix each time the app opens (the same while it stays open).
    private static let launchSeed = UInt64.random(in: 1...UInt64.max)

    @MainActor
    func load(index: ExploreIndex?) async {
        if Demo.isOn {
            all = Self.stand(in: index)
            return
        }
        if let fresh = try? await Backend.shared.api.themes(), !fresh.isEmpty {
            all = fresh
            Self.saved = fresh
        } else if all.isEmpty {
            // Nothing from the server yet: themes made from the market lists stand in.
            all = Self.stand(in: index)
        }
    }

    /// Pick this visit's few: favourites first in the draw (your Pokémon count three times,
    /// your era once more, new ones once more), never two of the same look while others remain.
    @MainActor
    func pick(store: CollectionStore, index: ExploreIndex?, count: Int = 4) {
        let holdings = store.allHoldings
        let favourite = CollectorTaste.favourite(holdings)?.name.lowercased()
        var released: [String: String] = [:]
        for s in index?.sets ?? [] { if let d = s.releaseDate { released[s.name] = d } }
        let era = CollectorTaste.era(holdings, released: released)
        var rng = SeededRandom(seed: Self.launchSeed)
        var pool = all.filter { $0.hits.count >= 3 }
        var out: [MarketTheme] = []
        var looks = Set<String>()
        while out.count < count, !pool.isEmpty {
            let fresh = pool.filter { !looks.contains($0.look) }
            let candidates = fresh.isEmpty ? pool : fresh
            let weights = candidates.map { t -> Double in
                var w = 1.0
                if let favourite, t.pokemon?.contains(where: { $0.lowercased() == favourite }) == true { w += 3 }
                if let era, t.era == era { w += 1 }
                if t.fresh == true { w += 1 }
                return w
            }
            var roll = Double.random(in: 0..<weights.reduce(0, +), using: &rng)
            var chosen = candidates[candidates.count - 1]
            for (t, w) in zip(candidates, weights) {
                if roll < w { chosen = t; break }
                roll -= w
            }
            out.append(chosen)
            looks.insert(chosen.look)
            pool.removeAll { $0.id == chosen.id }
        }
        shown = out
    }

    // MARK: Saved on the phone

    private static var file: URL { FileManager.default.urls(for: .cachesDirectory, in: .userDomainMask)[0].appendingPathComponent("market-themes.json") }

    static var saved: [MarketTheme] {
        get { (try? Data(contentsOf: file)).flatMap { try? JSONDecoder().decode([MarketTheme].self, from: $0) } ?? [] }
        set { try? JSONEncoder().encode(newValue).write(to: file, options: .atomic) }
    }

    /// Themes made from Home's own market lists, for the demo and until the server's arrive.
    static func stand(in index: ExploreIndex?) -> [MarketTheme] {
        guard let index else { return [] }
        let trending = index.trending ?? [], eras = index.eras ?? MarketEras()
        var everything: [SearchHit] = trending
        everything += index.today ?? []
        everything += eras.modern
        everything += eras.midEra
        everything += eras.vintage
        var seen = Set<String>()
        let unique = everything.filter { $0.market != nil && seen.insert($0.product.id).inserted }
        var bySet: [String: SearchHit] = [:]
        for h in unique.sorted(by: { ($0.market ?? 0) > ($1.market ?? 0) }) where h.releaseDate != nil {
            let key = h.product.setName ?? h.product.id
            if bySet[key] == nil { bySet[key] = h }
        }
        let timeline = bySet.values.sorted { ($0.releaseDate ?? "") < ($1.releaseDate ?? "") }
        let ladder = unique.sorted { ($0.market ?? 0) < ($1.market ?? 0) }
        let ladderSteps = ladder.count <= 7 ? ladder : (0..<7).map { ladder[Int((Double($0) * Double(ladder.count - 1) / 6).rounded())] }
        return [
            MarketTheme(id: "stand-grails", title: "Modern grails", blurb: "The priciest modern cards rising this week.", look: "billboard", era: "modern",
                        hits: eras.modern.sorted { ($0.market ?? 0) > ($1.market ?? 0) }),
            MarketTheme(id: "stand-vintage", title: "Vintage on the move", blurb: "Wizards-era cards climbing this week.", look: "fan", era: "vintage", hits: eras.vintage),
            MarketTheme(id: "stand-years", title: "Through the years", blurb: "One standout from each set, oldest first.", look: "timeline", hits: timeline),
            MarketTheme(id: "stand-wall", title: "This week's wall", blurb: "Everything rising, side by side.", look: "mosaic", hits: trending),
            MarketTheme(id: "stand-ladder", title: "At every price", blurb: "From pocket money to grail.", look: "ladder", hits: ladderSteps),
            MarketTheme(id: "stand-mid", title: "Mid-era spotlight", blurb: "Diamond & Pearl to XY's biggest riser.", look: "spotlight", era: "midEra", hits: eras.midEra),
        ].filter { $0.hits.count >= 3 }
    }
}

/// The same shuffle while the app stays open.
private struct SeededRandom: RandomNumberGenerator {
    var state: UInt64
    init(seed: UInt64) { state = seed }
    mutating func next() -> UInt64 {
        state &+= 0x9E3779B97F4A7C15
        var z = state
        z = (z ^ (z >> 30)) &* 0xBF58476D1CE4E5B9
        z = (z ^ (z >> 27)) &* 0x94D049BB133111EB
        return z ^ (z >> 31)
    }
}

// MARK: A theme on Home

struct ThemeSection: View {
    var theme: MarketTheme

    var body: some View {
        VStack(alignment: .leading, spacing: 14) {
            ThemeHeader(theme: theme).padding(.horizontal, 16)
            Group {
                switch theme.look {
                case "billboard": BillboardLook(hits: theme.hits)
                case "timeline": TimelineLook(hits: theme.hits)
                case "mosaic": MosaicLook(hits: theme.hits)
                case "ladder": LadderLook(hits: theme.hits)
                case "spotlight": SpotlightLook(hits: theme.hits)
                default: FanLook(hits: theme.hits)
                }
            }
            .cardSequence(theme.hits.map(\.product.id))
        }
        .reveal()
    }
}

/// The theme's title and line; tapping it opens the whole collection.
private struct ThemeHeader: View {
    var theme: MarketTheme

    var body: some View {
        NavigationLink(value: theme) {
            HStack(alignment: .lastTextBaseline, spacing: 8) {
                VStack(alignment: .leading, spacing: 6) {
                    HStack(spacing: 8) {
                        Text(theme.title).font(.display(22)).tracking(22 * -0.03).foregroundStyle(.white).lineLimit(1).minimumScaleFactor(0.8).displayTrim(22)
                        if theme.fresh == true { SkewTag(text: "New") }
                    }
                    Text(theme.blurb.noWidow).font(.geist(15)).foregroundStyle(Theme.muted).multilineTextAlignment(.leading)
                }
                Spacer(minLength: 8)
                HStack(spacing: 4) { Text("See all"); Image(systemName: "arrow.right").font(.system(size: 12, weight: .semibold)) }
                    .font(.geist(13, .medium)).foregroundStyle(Theme.muted).fixedSize()
            }
            .contentShape(Rectangle())
        }
        .buttonStyle(.plain)
    }
}

private func price(_ hit: SearchHit) -> String { Format.money(hit.market) }

/// Billboard: one big card on its own art, the title beside it, a few more under it.
private struct BillboardLook: View {
    var hits: [SearchHit]

    var body: some View {
        let star = hits[0]
        VStack(alignment: .leading, spacing: 14) {
            MarketLink(hit: star) {
                HStack(alignment: .bottom, spacing: 16) {
                    VStack(alignment: .leading, spacing: 6) {
                        MonoLabel(text: "No. 1 in this collection")
                        Text(star.product.name.noWidow).font(.display(26)).tracking(-0.8).foregroundStyle(.white).lineLimit(3)
                        Text(star.product.setName ?? "").font(.geist(13)).foregroundStyle(Theme.muted).lineLimit(1)
                        Text(price(star)).font(.display(30)).tracking(-0.9).monospacedDigit().foregroundStyle(Theme.lime).padding(.top, 6)
                    }
                    Spacer(minLength: 0)
                    ProductImage(product: star.pictured, cornerRadius: 8)
                        .frame(width: 140, height: 196)
                        .rotationEffect(.degrees(4))
                        .shadow(color: .black.opacity(0.5), radius: 16, y: 10)
                }
                .padding(18)
                .frame(maxWidth: .infinity)
                .background {
                    // The card's own art, blown up and dimmed, behind it (drawn once, still).
                    ProductImage(product: star.pictured, cornerRadius: 0)
                        .scaleEffect(2.4)
                        .blur(radius: 30)
                        .opacity(0.45)
                        .overlay(LinearGradient(colors: [.black.opacity(0.75), .black.opacity(0.2)], startPoint: .leading, endPoint: .trailing))
                        .allowsHitTesting(false)
                }
                .clipShape(RoundedRectangle(cornerRadius: 22, style: .continuous))
                .overlay(RoundedRectangle(cornerRadius: 22, style: .continuous).strokeBorder(Theme.border))
            }
            HStack(spacing: 10) {
                ForEach(hits.dropFirst().prefix(4)) { hit in
                    MarketLink(hit: hit) {
                        VStack(alignment: .leading, spacing: 4) {
                            ProductImage(product: hit.pictured, cornerRadius: 5).aspectRatio(63 / 88, contentMode: .fit)
                            Text(price(hit)).font(.geist(12, .semibold)).monospacedDigit().foregroundStyle(.white)
                        }
                    }
                    .frame(maxWidth: .infinity)
                }
            }
        }
        .padding(.horizontal, 16)
    }
}

/// Fan: five cards held like a hand, the middle one up front, names under it.
private struct FanLook: View {
    var hits: [SearchHit]

    var body: some View {
        let hand = Array(hits.prefix(5))
        let mid = Double(hand.count - 1) / 2
        VStack(spacing: 14) {
            ZStack {
                ForEach(Array(hand.enumerated()), id: \.element.id) { i, hit in
                    let d = Double(i) - mid
                    MarketLink(hit: hit) {
                        ProductImage(product: hit.pictured, cornerRadius: 7)
                            .frame(width: 118, height: 165)
                            .shadow(color: .black.opacity(0.45), radius: 10, y: 6)
                    }
                    .rotationEffect(.degrees(d * 9), anchor: .bottom)
                    .offset(x: d * 58, y: abs(d) * 10)
                    // The middle card on top, the outer ones behind.
                    .zIndex(-abs(d))
                }
            }
            .frame(height: 200)
            .frame(maxWidth: .infinity)
            // What's in the hand, as one line of names and prices.
            ScrollView(.horizontal, showsIndicators: false) {
                HStack(spacing: 8) {
                    ForEach(hits.prefix(10)) { hit in
                        MarketLink(hit: hit) {
                            HStack(spacing: 6) {
                                Text(hit.product.name).font(.geist(12, .medium)).foregroundStyle(.white).lineLimit(1)
                                Text(price(hit)).font(.geist(12, .semibold)).monospacedDigit().foregroundStyle(Theme.lime)
                            }
                            .padding(.horizontal, 12).padding(.vertical, 8)
                            .background(Capsule().fill(Color.white.opacity(0.06)))
                        }
                    }
                }
                .padding(.horizontal, 16)
            }
        }
    }
}

/// Timeline: oldest first along a line, each card with its year.
private struct TimelineLook: View {
    var hits: [SearchHit]

    var body: some View {
        ScrollView(.horizontal, showsIndicators: false) {
            HStack(alignment: .top, spacing: 0) {
                ForEach(Array(hits.enumerated()), id: \.element.id) { i, hit in
                    VStack(alignment: .leading, spacing: 10) {
                        // The year on the line, with a dot.
                        HStack(spacing: 6) {
                            Circle().fill(Theme.lime).frame(width: 7, height: 7)
                            Text(String((hit.releaseDate ?? "").prefix(4))).font(.mono(11)).foregroundStyle(.white)
                            Rectangle().fill(Color.white.opacity(i == hits.count - 1 ? 0 : 0.15)).frame(height: 1)
                        }
                        MarketLink(hit: hit) {
                            VStack(alignment: .leading, spacing: 4) {
                                ProductImage(product: hit.pictured, cornerRadius: 5).frame(width: 96, height: 134)
                                Text(hit.product.setName ?? "").font(.geist(11)).foregroundStyle(Theme.muted).lineLimit(1)
                                Text(price(hit)).font(.geist(13, .semibold)).monospacedDigit().foregroundStyle(.white)
                            }
                            .frame(width: 96, alignment: .leading)
                        }
                    }
                    .frame(width: 112, alignment: .leading)
                }
            }
            .padding(.horizontal, 16)
        }
    }
}

/// Mosaic: a wall of art, two rows of three, the first one twice the size.
private struct MosaicLook: View {
    var hits: [SearchHit]

    var body: some View {
        let wall = Array(hits.prefix(5))
        HStack(alignment: .top, spacing: 8) {
            if let first = wall.first { tile(first, big: true) }
            VStack(spacing: 8) {
                HStack(spacing: 8) { ForEach(wall.dropFirst().prefix(2)) { tile($0, big: false) } }
                HStack(spacing: 8) { ForEach(wall.dropFirst(3).prefix(2)) { tile($0, big: false) } }
            }
        }
        .padding(.horizontal, 16)
    }

    private func tile(_ hit: SearchHit, big: Bool) -> some View {
        MarketLink(hit: hit) {
            ProductImage(product: hit.pictured, cornerRadius: big ? 10 : 6)
                .aspectRatio(63 / 88, contentMode: .fit)
                .overlay(alignment: .bottomLeading) {
                    Text(price(hit)).font(.geist(big ? 13 : 10, .semibold)).monospacedDigit().foregroundStyle(.white)
                        .padding(.horizontal, 6).padding(.vertical, 3)
                        .background(Capsule().fill(.black.opacity(0.65)))
                        .padding(6)
                }
        }
        .frame(maxWidth: .infinity)
    }
}

/// Ladder: one Pokémon from cheapest to priciest, each step a little taller.
private struct LadderLook: View {
    var hits: [SearchHit]

    var body: some View {
        ScrollView(.horizontal, showsIndicators: false) {
            HStack(alignment: .bottom, spacing: 10) {
                ForEach(Array(hits.enumerated()), id: \.element.id) { i, hit in
                    let scale = 0.62 + 0.38 * Double(i) / Double(max(1, hits.count - 1))
                    MarketLink(hit: hit) {
                        VStack(alignment: .leading, spacing: 6) {
                            ProductImage(product: hit.pictured, cornerRadius: 6).frame(width: 120 * scale, height: 168 * scale)
                            Text(price(hit)).font(.display(15 + 5 * scale)).tracking(-0.4).monospacedDigit().foregroundStyle(i == hits.count - 1 ? Theme.lime : .white)
                            Text(hit.product.setName ?? "").font(.geist(11)).foregroundStyle(Theme.muted).lineLimit(1).frame(width: 120 * scale, alignment: .leading)
                        }
                    }
                }
            }
            .padding(.horizontal, 16)
        }
    }
}

/// Spotlight: one card, big, with its story in numbers, and the rest as a small stack.
private struct SpotlightLook: View {
    var hits: [SearchHit]

    var body: some View {
        let star = hits[0]
        HStack(alignment: .center, spacing: 18) {
            MarketLink(hit: star) {
                ProductImage(product: star.pictured, cornerRadius: 9)
                    .frame(width: 150, height: 210)
                    .background(
                        RadialGradient(colors: [Theme.lime.opacity(0.35), .clear], center: .center, startRadius: 0, endRadius: 150)
                            .frame(width: 300, height: 300)
                            .allowsHitTesting(false)
                    )
            }
            VStack(alignment: .leading, spacing: 8) {
                Text(star.product.name.noWidow).font(.display(22)).tracking(-0.6).foregroundStyle(.white).lineLimit(3)
                Text(star.product.setName ?? "").font(.geist(13)).foregroundStyle(Theme.muted).lineLimit(2)
                Text(price(star)).font(.display(28)).tracking(-0.8).monospacedDigit().foregroundStyle(Theme.lime)
                if let c = star.change7dPct {
                    Text("\(c >= 0 ? "+" : "")\(Int(c.rounded()))% this week").font(.geist(12, .semibold)).monospacedDigit()
                        .foregroundStyle(c >= 0 ? Theme.lime : Theme.planPink)
                }
                // The others, overlapping like a small stack.
                HStack(spacing: -18) {
                    ForEach(hits.dropFirst().prefix(4)) { hit in
                        MarketLink(hit: hit) {
                            ProductImage(product: hit.pictured, cornerRadius: 4).frame(width: 40, height: 56)
                                .overlay(RoundedRectangle(cornerRadius: 4).strokeBorder(Theme.background, lineWidth: 2))
                        }
                    }
                }
                .padding(.top, 4)
            }
            Spacer(minLength: 0)
        }
        .padding(.horizontal, 16)
    }
}

// MARK: A theme's own page

struct ThemePage: View {
    var theme: MarketTheme

    var body: some View {
        ScrollView {
            VStack(alignment: .leading, spacing: 20) {
                VStack(alignment: .leading, spacing: 8) {
                    if theme.fresh == true { SkewTag(text: "New this week") }
                    Text(theme.title.noWidow).font(.display(34)).tracking(-1.1).foregroundStyle(.white)
                    Text(theme.blurb.noWidow).font(.geist(15)).foregroundStyle(Theme.muted)
                    Text("\(theme.hits.count) cards").font(.mono(11)).foregroundStyle(Theme.subtle).padding(.top, 2)
                }
                LazyVGrid(columns: Array(repeating: GridItem(.flexible(), spacing: 12), count: 3), alignment: .leading, spacing: 18) {
                    ForEach(theme.hits) { hit in
                        MarketLink(hit: hit) {
                            VStack(alignment: .leading, spacing: 5) {
                                ProductImage(product: hit.pictured, cornerRadius: 5).aspectRatio(63 / 88, contentMode: .fit)
                                Text(hit.product.name).font(.geist(12, .medium)).foregroundStyle(.white).lineLimit(1)
                                Text(hit.product.setName ?? "").font(.geist(11)).foregroundStyle(Theme.muted).lineLimit(1)
                                Text(price(hit)).font(.geist(13, .semibold)).monospacedDigit().foregroundStyle(.white)
                            }
                            .contentShape(Rectangle())
                        }
                    }
                }
                .cardSequence(theme.hits.map(\.product.id))
            }
            .padding(.horizontal, 16)
            .padding(.top, 8)
            .padding(.bottom, 40)
        }
        .background(Theme.background)
        .tabBarClearance()
        .navigationBarTitleDisplayMode(.inline)
    }
}
