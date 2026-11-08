import SwiftUI
import UIKit

// MARK: - Other versions of this card

/// The same card in other sets, printings, promos and languages: a row of art, short set name
/// and price. Found with the free stored-catalog search (never the paid live one), once per
/// product per session.
struct OtherVersionsRow: View {
    var product: Product
    @Environment(CollectionStore.self) private var store
    @State private var versions: [SearchHit] = []

    var body: some View {
        // A container that's always there (an empty one would never start its task); nothing
        // shows, and no space is taken, until versions are found.
        VStack(alignment: .leading, spacing: 0) {
            if versions.isEmpty {
                Color.clear.frame(height: 0)
            } else {
                VStack(alignment: .leading, spacing: 0) {
                    Text("Similar cards").font(.display(22)).tracking(22 * -0.03).displayTrim(22)
                    Text("Cards with the same name, from other sets and printings").font(.geist(13)).foregroundStyle(Theme.muted)
                        .padding(.top, 6)
                    ScrollView(.horizontal, showsIndicators: false) {
                        LazyHStack(alignment: .top, spacing: 12) {
                            ForEach(versions) { hit in
                                CardLink(productId: hit.product.id) { tile(hit) }
                                    .buttonStyle(.plain)
                                    .simultaneousGesture(TapGesture().onEnded { store.seed(hit) })
                            }
                        }
                    }
                    .contentMargins(.horizontal, 16, for: .scrollContent)
                    .padding(.horizontal, -16)
                    .padding(.top, 14)
                    // Thumbnails, decoded off the main thread (the card page asks for full size).
                    .imageMaxPixel(300)
                }
                .padding(.top, 24)
            }
        }
        .frame(maxWidth: .infinity, alignment: .leading)
        .task(id: product.id) { await load() }
    }

    private func tile(_ hit: SearchHit) -> some View {
        VStack(alignment: .leading, spacing: 3) {
            ProductImage(product: hit.product, cornerRadius: 5)
                .frame(width: 84, height: 117)
                .padding(.bottom, 5)
            Text(Self.shortSet(hit.product.setName) ?? " ")
                .font(.geist(12)).foregroundStyle(Theme.muted).lineLimit(1)
            Text(Format.money(hit.market))
                .font(.geist(13, .semibold)).monospacedDigit().foregroundStyle(.white).lineLimit(1)
        }
        .frame(width: 84, alignment: .leading)
        .contentShape(Rectangle())
        .accessibilityElement(children: .combine)
    }

    private func load() async {
        let id = product.id
        if let cached = OtherVersionsCache.hits[id] {
            versions = cached
            return
        }
        versions = []
        guard !product.isSealed else { return }
        let base = Self.baseName(product.name)
        guard base.count >= 2 else { return }
        guard let hits = try? await Backend.shared.api.search(base), !Task.isCancelled else { return }
        let wanted = base.lowercased()
        // One entry per product (search can list a product once per printing): its best price.
        var best: [String: SearchHit] = [:]
        for hit in hits {
            let p = hit.product
            guard p.id != id, !p.isSealed, p.kind == "single", Self.baseName(p.name).lowercased() == wanted else { continue }
            if let have = best[p.id], (have.market ?? -1) >= (hit.market ?? -1) { continue }
            best[p.id] = hit
        }
        let list = Array(best.values.sorted { ($0.market ?? -1) > ($1.market ?? -1) }.prefix(12))
        OtherVersionsCache.hits[id] = list
        versions = list
    }

    /// The card's name without its number and variant notes: "Charizard ex - 199/165" and
    /// "Umbreon VMAX (Alternate Art Secret)" become "Charizard ex" and "Umbreon VMAX".
    static func baseName(_ name: String) -> String {
        var s = name.replacingOccurrences(of: #"\([^)]*\)|\[[^\]]*\]"#, with: " ", options: .regularExpression)
        s = s.replacingOccurrences(of: #"\s+-\s+.*$"#, with: "", options: .regularExpression)
        s = s.replacingOccurrences(of: #"\s+#?[A-Za-z]{0,5}\d+(/[A-Za-z]{0,5}\d+)?\s*$"#, with: "", options: .regularExpression)
        s = s.replacingOccurrences(of: #"\s+"#, with: " ", options: .regularExpression)
        return s.trimmingCharacters(in: .whitespacesAndNewlines)
    }

    /// "SV: Scarlet & Violet 151" → "Scarlet & Violet 151".
    static func shortSet(_ name: String?) -> String? {
        guard let name else { return nil }
        if let r = name.range(of: ": ") { return String(name[r.upperBound...]) }
        return name
    }
}

/// Other versions already found this session, by product (going back and forth costs nothing).
@MainActor
enum OtherVersionsCache {
    static var hits: [String: [SearchHit]] = [:]
}

// MARK: - Your copy strip

/// Under the price when you own it: how many, and how it's doing against what you paid.
/// Tapping opens Owned for your most valuable copy (`onOpen`; the card page shows it in its own
/// sheet, which also works when the page is itself in a sheet, where the app-wide one can't open).
struct YourCopyStrip: View {
    var owned: [HoldingView]
    var onOpen: (HoldingView) -> Void

    var body: some View {
        if owned.count > 1 { copies } else { single }
    }

    /// Different copies (a raw one and a slab, two grades…): the total, then a row for each, so
    /// you open the one you mean.
    private var copies: some View {
        let sorted = owned.sorted { ($0.value ?? 0) > ($1.value ?? 0) }
        return VStack(spacing: 0) {
            HStack(spacing: 8) {
                line.font(.geist(14, .medium)).monospacedDigit().lineLimit(1).minimumScaleFactor(0.75)
                if let r = gainRatio { DeltaPill(ratio: r, size: 12) }
                Spacer(minLength: 0)
            }
            .padding(.horizontal, 16)
            .frame(height: 46)
            ForEach(sorted) { h in
                Rectangle().fill(Color.white.opacity(0.08)).frame(height: 1).padding(.horizontal, 16)
                Button {
                    Haptics.tap()
                    onOpen(h)
                } label: {
                    HStack(spacing: 10) {
                        Text(h.identity.isGraded ? (h.identity.gradeLabel ?? "Graded") : h.identity.condition)
                            .font(.geist(12, .semibold))
                            .foregroundStyle(h.identity.isGraded ? Theme.ink : .white)
                            .padding(.horizontal, 8).padding(.vertical, 3)
                            .background(Capsule().fill(h.identity.isGraded ? Theme.lime : Color.white.opacity(0.12)))
                        if h.quantity > 1 {
                            Text(verbatim: "\u{00D7}\(Int(h.quantity))").font(.geist(13, .medium)).foregroundStyle(Theme.muted)
                        }
                        Spacer(minLength: 4)
                        Text(Format.money(h.value)).font(.geist(14, .semibold)).monospacedDigit().foregroundStyle(.white)
                        if let g = h.gain {
                            Text(Format.signedMoney(g)).font(.geist(12)).monospacedDigit().foregroundStyle(Theme.tone(g))
                        }
                        Image(systemName: "chevron.right").font(.system(size: 12, weight: .semibold)).foregroundStyle(Theme.muted)
                    }
                    .padding(.horizontal, 16)
                    .frame(height: 46)
                    .contentShape(Rectangle())
                }
                .buttonStyle(.plain)
                .accessibilityHint("Opens this copy")
            }
        }
        .liquidGlass(in: RoundedRectangle(cornerRadius: 16, style: .continuous))
    }

    private var single: some View {
        Button {
            if let h = owned.first { onOpen(h) }
        } label: {
            HStack(spacing: 8) {
                line
                    .font(.geist(14, .medium)).monospacedDigit()
                    .lineLimit(1).minimumScaleFactor(0.75)
                if let r = gainRatio { DeltaPill(ratio: r, size: 12) }
                Spacer(minLength: 4)
                Image(systemName: "chevron.right").font(.system(size: 12, weight: .semibold)).foregroundStyle(Theme.muted)
            }
            .padding(.horizontal, 16)
            .frame(height: 46)
            .contentShape(RoundedRectangle(cornerRadius: 16, style: .continuous))
            .liquidGlass(in: RoundedRectangle(cornerRadius: 16, style: .continuous))
        }
        .buttonStyle(.plain)
        .accessibilityHint("Opens your copy")
    }

    /// "You own 2 · +$848.00 on what you paid · +155%", only the numbers coloured.
    private var line: Text {
        let qty = owned.reduce(0) { $0 + $1.quantity }
        let priced = owned.filter { $0.value != nil }
        let value = priced.reduce(0) { $0 + ($1.value ?? 0) }
        let cost = priced.reduce(0) { $0 + $1.costBasis }
        var text = Text(verbatim: "You own \(qty.formatted())").foregroundStyle(.white)
        guard !priced.isEmpty else { return text }
        let gain = value - cost
        text = text
            + Text(verbatim: " · ").foregroundStyle(Theme.muted)
            + Text(verbatim: Format.signedMoney(gain)).foregroundStyle(Theme.tone(gain))
            + Text(verbatim: " on what you paid").foregroundStyle(Theme.muted)
        return text
    }

    /// What you've made on what you paid, as a share (shown in its pill after the line).
    private var gainRatio: Double? {
        let priced = owned.filter { $0.value != nil }
        let cost = priced.reduce(0) { $0 + $1.costBasis }
        guard !priced.isEmpty, cost > 0 else { return nil }
        return (priced.reduce(0) { $0 + ($1.value ?? 0) } - cost) / cost
    }
}

// MARK: - Add to deal

/// In the action row while a deal is open: add this card to what's coming in or going out.
/// Going out uses your own copy when you have one (as the deal's picker does for inventory).
struct DealAddButton: View {
    var product: Product?
    var printing: String?
    var market: Double?
    var owned: [HoldingView]
    @Environment(DealStore.self) private var deals
    @State private var added = false

    var body: some View {
        if deals.deal.kind != .empty, product != nil {
            Menu {
                Button { add(.incoming) } label: { Label("Coming in", systemImage: "arrow.down.left") }
                Button { add(.outgoing) } label: { Label("Going out", systemImage: "arrow.up.right") }
            } label: {
                Image(systemName: added ? "checkmark" : "arrow.left.arrow.right")
            }
            .menuStyle(.button)
            .buttonStyle(IconButton3D(size: 36, active: added))
            .accessibilityLabel("Add to deal")
            .task(id: added) {
                guard added else { return }
                try? await Task.sleep(nanoseconds: 1_600_000_000)
                added = false
            }
        }
    }

    private func add(_ side: DealSide) {
        guard let product else { return }
        Self.add(side, product: product, printing: printing, market: market, owned: owned, deals: deals)
        added = true
    }

    /// Your copy to send out: the one in the printing on show, else your most valuable.
    static func outgoingCopy(_ owned: [HoldingView], printing: String?) -> HoldingView? {
        let held = owned.filter { $0.product != nil && $0.quantity > 0 }
        return held.first(where: { $0.identity.printing == printing && !$0.identity.isGraded })
            ?? held.max(by: { ($0.value ?? 0) < ($1.value ?? 0) })
    }

    /// Puts the card on one side of the open deal (going out, your own copy), with an undo toast.
    /// Also used by the card page's ⋯ menu.
    @MainActor
    static func add(_ side: DealSide, product: Product, printing: String?, market: Double?, owned: [HoldingView], deals: DealStore) {
        let item: DealItem
        if side == .outgoing, let h = outgoingCopy(owned, printing: printing), let p = h.product {
            item = DealItem(
                key: "h:\(h.identity.key)", product: p, printing: h.identity.printing, market: h.price,
                holdingKey: h.identity.key, maxQty: Int(h.quantity)
            )
        } else {
            item = DealItem(key: "p:\(product.id):\(printing ?? ""):", product: product, printing: printing, market: market)
        }
        let key = item.key
        let list = side == .incoming ? deals.deal.incoming : deals.deal.outgoing
        let before = list.first(where: { $0.key == key })?.qty
        deals.add(item, to: side)
        // The undo toast (with its success haptic): "Added to coming in · Undo".
        let store = deals
        Router.shared.undo = UndoItem(message: side == .incoming ? "Added to coming in" : "Added to going out") {
            store.update { d in
                func revert(_ items: inout [DealItem]) {
                    guard let i = items.firstIndex(where: { $0.key == key }) else { return }
                    if let before { items[i].qty = before } else { items.remove(at: i) }
                }
                if side == .incoming { revert(&d.incoming) } else { revert(&d.outgoing) }
            }
        }
    }
}

// MARK: - Full-screen art

/// The card art full screen on black: pinch to zoom (1× to 5×), drag to pan when zoomed,
/// double-tap to zoom in or out, and swipe down (at 1×) or the close button to leave.
struct ArtViewer: View {
    var product: Product?
    /// A slab to show in its frame instead of the bare card.
    var slab: HoldingIdentity?
    @Environment(\.dismiss) private var dismiss
    @Environment(\.accessibilityReduceMotion) private var reduceMotion
    @State private var scale: CGFloat = 1
    @State private var baseScale: CGFloat = 1
    @State private var offset: CGSize = .zero
    @State private var baseOffset: CGSize = .zero
    /// How far it's been pulled down to close (at 1×).
    @State private var drop: CGFloat = 0

    private var spring: Animation? { reduceMotion ? nil : .spring(response: 0.35, dampingFraction: 0.86) }

    var body: some View {
        GeometryReader { geo in
            ZStack {
                Color.black.ignoresSafeArea()
                art
                    .padding(.horizontal, 20)
                    .padding(.vertical, 64)
                    .frame(width: geo.size.width, height: geo.size.height)
                    .scaleEffect(scale)
                    .offset(x: offset.width, y: offset.height + drop)
                    .opacity(1 - min(0.5, Double(abs(drop)) / 600))
                    .contentShape(Rectangle())
                    .onTapGesture(count: 2) { location in
                        toggleZoom(at: location, in: geo.size)
                    }
                    .gesture(magnify(geo.size).simultaneously(with: pan(geo.size)))
            }
            .overlay(alignment: .topLeading) {
                Button { dismiss() } label: {
                    Image(systemName: "xmark")
                        .font(.system(size: 16, weight: .semibold))
                        .foregroundStyle(.white)
                        .frame(width: 44, height: 44)
                        .liquidGlass(in: Circle(), interactive: true)
                }
                .buttonStyle(.plain)
                .accessibilityLabel("Close")
                .padding(.leading, 16)
                .padding(.top, 8)
            }
        }
        .background(Color.black.ignoresSafeArea())
        // Full resolution: whatever the page behind asked for.
        .environment(\.imageMaxPixel, nil)
        .statusBarHidden()
    }

    @ViewBuilder private var art: some View {
        if let slab, slab.isGraded {
            HoldingArt(product: product, identity: slab)
                .aspectRatio(5.0 / 8.0, contentMode: .fit)
        } else {
            ProductImage(product: product, cornerRadius: product?.isSealed == true ? 8 : 16, large: true)
        }
    }

    private func clamp(_ s: CGFloat) -> CGFloat { min(5, max(1, s)) }

    /// Keeps a zoomed picture from being dragged off the screen.
    private func bounded(_ o: CGSize, scale s: CGFloat, in size: CGSize) -> CGSize {
        let maxX = max(0, (s - 1) * size.width / 2)
        let maxY = max(0, (s - 1) * size.height / 2)
        return CGSize(width: min(maxX, max(-maxX, o.width)), height: min(maxY, max(-maxY, o.height)))
    }

    private func magnify(_ size: CGSize) -> some Gesture {
        MagnifyGesture()
            .onChanged { v in
                scale = clamp(baseScale * v.magnification)
                drop = 0
            }
            .onEnded { _ in
                withAnimation(spring) {
                    if scale <= 1.02 {
                        scale = 1
                        offset = .zero
                    } else {
                        offset = bounded(offset, scale: scale, in: size)
                    }
                }
                baseScale = scale
                baseOffset = offset
            }
    }

    private func pan(_ size: CGSize) -> some Gesture {
        DragGesture(minimumDistance: 8)
            .onChanged { g in
                if baseScale > 1 {
                    offset = CGSize(width: baseOffset.width + g.translation.width, height: baseOffset.height + g.translation.height)
                } else if scale <= 1 {
                    // At 1×: pull down to close.
                    drop = max(0, g.translation.height)
                }
            }
            .onEnded { g in
                if baseScale > 1 {
                    withAnimation(spring) { offset = bounded(offset, scale: scale, in: size) }
                    baseOffset = offset
                } else if scale <= 1 {
                    if g.translation.height > 120 || g.predictedEndTranslation.height > 320 {
                        dismiss()
                    } else {
                        withAnimation(spring) { drop = 0 }
                    }
                }
            }
    }

    /// 1× ↔ 2.5×, zooming in on the spot tapped.
    private func toggleZoom(at location: CGPoint, in size: CGSize) {
        withAnimation(spring) {
            if scale > 1 {
                scale = 1
                offset = .zero
            } else {
                let s: CGFloat = 2.5
                scale = s
                let toward = CGSize(width: (size.width / 2 - location.x) * (s - 1), height: (size.height / 2 - location.y) * (s - 1))
                offset = bounded(toward, scale: s, in: size)
            }
            drop = 0
        }
        baseScale = scale
        baseOffset = offset
    }
}
