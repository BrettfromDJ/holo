import SwiftUI
import UIKit

// MARK: - Glow cards (Lucent)

/// The colors of a glowing card: a base and a few soft blobs of light. Static radial gradients
/// (no live blur), so they cost nothing to draw or scroll.
struct GlowPalette: Hashable {
    struct Blob: Hashable {
        var color: Color
        var x: CGFloat
        var y: CGFloat
        /// Radius as a share of the card's longer side.
        var size: CGFloat
        var strength: Double = 1
    }

    var base: Color
    var blobs: [Blob]
    /// Text color on the card (white, or near-black on the light mint card).
    var ink: Color = .white

    /// Up overall: teal and green with a pale core, blue and violet at the shoulders.
    static let up = GlowPalette(base: Color(hex: 0x0B2A24), blobs: [
        Blob(color: Color(hex: 0x2A7BFF), x: 0.15, y: 0.25, size: 0.55),
        Blob(color: Color(hex: 0x7B5CFF), x: 0.9, y: 0.2, size: 0.5),
        Blob(color: Color(hex: 0xDFFFF2), x: 0.5, y: 0.5, size: 0.42, strength: 0.75),
        Blob(color: Color(hex: 0x19D38A), x: 0.5, y: 0.85, size: 0.6),
    ])
    /// Down: pink into orange.
    static let down = GlowPalette(base: Color(hex: 0x3A0A22), blobs: [
        Blob(color: Color(hex: 0xFF2E9A), x: 0.2, y: 0.25, size: 0.75),
        Blob(color: Color(hex: 0xFF5A1F), x: 0.75, y: 0.8, size: 0.7),
    ])
    static let violet = GlowPalette(base: Color(hex: 0x0D0F33), blobs: [
        Blob(color: Color(hex: 0x2F5BFF), x: 0.15, y: 0.15, size: 0.7),
        Blob(color: Color(hex: 0x9B7BFF), x: 0.6, y: 0.75, size: 0.75),
    ])
    static let gold = GlowPalette(base: Color(hex: 0x06231A), blobs: [
        Blob(color: Color(hex: 0x7CF5FF), x: 0.6, y: 0.05, size: 0.5),
        Blob(color: Color(hex: 0x18C98A), x: 0.25, y: 0.65, size: 0.75),
        Blob(color: Color(hex: 0xFFD36A), x: 0.85, y: 0.6, size: 0.6),
    ])
    static let sunset = GlowPalette(base: Color(hex: 0xFF6BB5), blobs: [
        Blob(color: Color(hex: 0xFF7A3D), x: 0.5, y: 0.5, size: 0.8),
        Blob(color: Color(hex: 0x13110F), x: 0.5, y: 0.6, size: 0.4, strength: 0.85),
    ])
    static let ember = GlowPalette(base: Color(hex: 0x3A0A1E), blobs: [
        Blob(color: Color(hex: 0xFF9D2E), x: 0.2, y: 0.3, size: 0.7),
        Blob(color: Color(hex: 0xFF3D7F), x: 0.75, y: 0.75, size: 0.7),
    ])
    static let indigo = GlowPalette(base: Color(hex: 0x140A33), blobs: [
        Blob(color: Color(hex: 0xD06BFF), x: 0.3, y: 0.2, size: 0.6),
        Blob(color: Color(hex: 0x3D6BFF), x: 0.6, y: 0.7, size: 0.7),
    ])
    static let mint = GlowPalette(base: Color(hex: 0x9EFFD8), blobs: [
        Blob(color: Color(hex: 0x2FE0A0), x: 0.5, y: 0.5, size: 0.85),
        Blob(color: Color(hex: 0x0A1A14), x: 0.5, y: 0.55, size: 0.38, strength: 0.55),
    ], ink: Color(hex: 0x03130D))
    static let ocean = GlowPalette(base: Color(hex: 0x0A0F2E), blobs: [
        Blob(color: Color(hex: 0x7CF5FF), x: 0.2, y: 0.2, size: 0.55),
        Blob(color: Color(hex: 0x2F5BFF), x: 0.6, y: 0.6, size: 0.7),
    ])
    static let forest = GlowPalette(base: Color(hex: 0x06180F), blobs: [
        Blob(color: Color(hex: 0x5FE3E8), x: 0.8, y: 0.2, size: 0.55),
        Blob(color: Color(hex: 0x1D6B4F), x: 0.4, y: 0.6, size: 0.7),
    ])
    static let orchid = GlowPalette(base: Color(hex: 0x2A0A3A), blobs: [
        Blob(color: Color(hex: 0xFF3D9A), x: 0.15, y: 0.2, size: 0.55),
        Blob(color: Color(hex: 0xFF8A3D), x: 0.9, y: 0.2, size: 0.5),
        Blob(color: Color(hex: 0xFFFFFF), x: 0.5, y: 0.45, size: 0.4, strength: 0.7),
        Blob(color: Color(hex: 0xB13CFF), x: 0.5, y: 0.82, size: 0.6),
    ])

    /// Yellow-green into lime light, like a spring meadow.
    static let citrus = GlowPalette(base: Color(hex: 0x1C2A06), blobs: [
        Blob(color: Color(hex: 0xE8FF5A), x: 0.75, y: 0.25, size: 0.6),
        Blob(color: Color(hex: 0x3BD16F), x: 0.25, y: 0.75, size: 0.7),
    ])
    static let aqua = GlowPalette(base: Color(hex: 0x05232A), blobs: [
        Blob(color: Color(hex: 0x5FF0FF), x: 0.3, y: 0.3, size: 0.65),
        Blob(color: Color(hex: 0x1F8BFF), x: 0.8, y: 0.8, size: 0.6),
    ])
    static let rose = GlowPalette(base: Color(hex: 0x33061E), blobs: [
        Blob(color: Color(hex: 0xFF8FC7), x: 0.3, y: 0.25, size: 0.6),
        Blob(color: Color(hex: 0xFF2E9A), x: 0.7, y: 0.8, size: 0.65),
    ])
    static let lilac = GlowPalette(base: Color(hex: 0x1E1238), blobs: [
        Blob(color: Color(hex: 0xC8B6FF), x: 0.7, y: 0.3, size: 0.6),
        Blob(color: Color(hex: 0x7B5CFF), x: 0.25, y: 0.8, size: 0.65),
    ])
    static let flame = GlowPalette(base: Color(hex: 0x2E0C04), blobs: [
        Blob(color: Color(hex: 0xFFB13D), x: 0.25, y: 0.3, size: 0.6),
        Blob(color: Color(hex: 0xFF4B2B), x: 0.75, y: 0.75, size: 0.65),
    ])
    static let sky = GlowPalette(base: Color(hex: 0x081A3A), blobs: [
        Blob(color: Color(hex: 0xA7C4FF), x: 0.5, y: 0.2, size: 0.6),
        Blob(color: Color(hex: 0x2F5BFF), x: 0.4, y: 0.85, size: 0.65),
    ])
    static let moss = GlowPalette(base: Color(hex: 0x0A1A0E), blobs: [
        Blob(color: Color(hex: 0x86F2CF), x: 0.7, y: 0.25, size: 0.55),
        Blob(color: Color(hex: 0x2E7D4F), x: 0.3, y: 0.75, size: 0.7),
    ])

    /// Rim glow: light around the edges and a dark center (like a lit bezel).
    static func rim(_ a: Color, _ b: Color, base: Color = Color(hex: 0x0B0B10)) -> GlowPalette {
        GlowPalette(base: base, blobs: [
            Blob(color: a, x: 0, y: 0, size: 0.75, strength: 0.95),
            Blob(color: b, x: 1, y: 1, size: 0.75, strength: 0.95),
            Blob(color: b, x: 1, y: 0, size: 0.5, strength: 0.7),
            Blob(color: a, x: 0, y: 1, size: 0.5, strength: 0.7),
            Blob(color: base, x: 0.5, y: 0.5, size: 0.5, strength: 0.95),
        ])
    }
    static let rimViolet = rim(Color(hex: 0x8B6CFF), Color(hex: 0x4E7BFF))
    static let rimTeal = rim(Color(hex: 0x2FE0C0), Color(hex: 0x2A7BFF))
    static let rimRose = rim(Color(hex: 0xFF5FA8), Color(hex: 0xFF8A3D))
    static let rimAmber = rim(Color(hex: 0xFFB13D), Color(hex: 0xE8FF5A))
    static let rimSky = rim(Color(hex: 0xA7C4FF), Color(hex: 0x7CF5FF))
    static let rimMoss = rim(Color(hex: 0x86F2CF), Color(hex: 0x2E9D5F))
    static let rimLilac = rim(Color(hex: 0xC8B6FF), Color(hex: 0xFF8FC7))

    /// Every palette in a pleasing order, washes and rims alternating, to mix colors across a
    /// row or grid of tiles.
    static let mix: [GlowPalette] = [.violet, .rimTeal, .citrus, .rimRose, .aqua, .rimViolet, .flame, .rimSky,
                                     .lilac, .rimAmber, .gold, .rimMoss, .rose, .rimLilac, .sky, .ember]

    /// The `i`th palette of the mix (wraps around), so neighbouring tiles differ.
    static func mixed(_ i: Int) -> GlowPalette { mix[((i % mix.count) + mix.count) % mix.count] }

    /// A steady rim palette (dark center) for an id.
    static func rimForProduct(_ id: String) -> GlowPalette {
        let options: [GlowPalette] = [.rimViolet, .rimTeal, .rimRose, .rimAmber, .rimSky, .rimMoss, .rimLilac]
        var h: UInt64 = 1469598103934665603
        for b in id.utf8 { h = (h ^ UInt64(b)) &* 1099511628211 }
        return options[Int(h % UInt64(options.count))]
    }

    /// Up or down.
    static func tone(_ value: Double?) -> GlowPalette { (value ?? 0) < 0 ? .down : .up }

    /// A steady palette for a product (the same card always gets the same glow), warmer for
    /// rarer cards.
    static func forProduct(_ id: String) -> GlowPalette {
        let options: [GlowPalette] = [.orchid, .indigo, .ocean, .ember, .gold, .violet, .citrus, .aqua, .rose, .lilac, .flame, .sky]
        var h: UInt64 = 1469598103934665603
        for b in id.utf8 { h = (h ^ UInt64(b)) &* 1099511628211 }
        return options[Int(h % UInt64(options.count))]
    }
}

/// A rounded card filled with soft colored light and a fine grain, holding its content.
struct GlowCard<Content: View>: View {
    var palette: GlowPalette
    var radius: CGFloat = 28
    var padding: CGFloat = 18
    @ViewBuilder var content: Content

    var body: some View {
        content
            .padding(padding)
            .frame(maxWidth: .infinity, alignment: .leading)
            .foregroundStyle(palette.ink)
            .background { GlowFill(palette: palette) }
            .clipShape(RoundedRectangle(cornerRadius: radius, style: .continuous))
            .overlay(RoundedRectangle(cornerRadius: radius, style: .continuous).strokeBorder(.white.opacity(0.08)))
    }
}

/// Just the light: the base color, the blobs and the grain.
struct GlowFill: View {
    var palette: GlowPalette

    var body: some View {
        // Drawn once into a small cached picture per palette and size, then just shown: soft
        // light looks the same scaled up, and nothing is redrawn while numbers count or the page
        // scrolls. (Live gradients on every card made the app lag.)
        GeometryReader { geo in
            Image(uiImage: GlowImageCache.shared.image(palette, size: geo.size))
                .resizable()
                .interpolation(.medium)
        }
        .allowsHitTesting(false)
    }
}

/// Rendered glow pictures, by palette and (rounded) size.
final class GlowImageCache {
    static let shared = GlowImageCache()
    private let cache = NSCache<NSString, UIImage>()
    private var keys: [GlowPalette: Int] = [:]

    init() { cache.countLimit = 120 }

    func image(_ palette: GlowPalette, size: CGSize) -> UIImage {
        // Quarter resolution, rounded to 8pt steps so near sizes share one picture.
        let w = max(8, (size.width / 8).rounded() * 8)
        let h = max(8, (size.height / 8).rounded() * 8)
        let id: Int
        if let known = keys[palette] { id = known } else { id = keys.count; keys[palette] = id }
        let key = "\(id)-\(Int(w))x\(Int(h))" as NSString
        if let hit = cache.object(forKey: key) { return hit }
        let px = CGSize(width: w / 4, height: h / 4)
        let format = UIGraphicsImageRendererFormat()
        format.scale = 1
        format.opaque = true
        let image = UIGraphicsImageRenderer(size: px, format: format).image { ctx in
            let cg = ctx.cgContext
            cg.setFillColor(UIColor(palette.base).cgColor)
            cg.fill(CGRect(origin: .zero, size: px))
            let side = max(px.width, px.height)
            let space = CGColorSpaceCreateDeviceRGB()
            for b in palette.blobs {
                let c = UIColor(b.color)
                let colors = [c.withAlphaComponent(b.strength).cgColor,
                              c.withAlphaComponent(b.strength * 0.55).cgColor,
                              c.withAlphaComponent(0).cgColor] as CFArray
                guard let g = CGGradient(colorsSpace: space, colors: colors, locations: [0, 0.35, 1]) else { continue }
                let center = CGPoint(x: px.width * b.x, y: px.height * b.y)
                cg.drawRadialGradient(g, startCenter: center, startRadius: 0, endCenter: center, endRadius: side * b.size, options: [])
            }
        }
        cache.setObject(image, forKey: key)
        return image
    }
}

/// The small mono label on glow cards.
struct GlowLabel: View {
    var text: String
    var secondary: String?

    var body: some View {
        VStack(alignment: .leading, spacing: 3) {
            Text(text.uppercased()).font(.mono(11)).tracking(1.4)
            if let secondary { Text(secondary).font(.mono(11)).tracking(0.6).opacity(0.6) }
        }
        .opacity(0.85)
    }
}

/// A big thin figure: Geist, tight, with the cents faded.
struct GlowFigure: View {
    var value: Double
    var size: CGFloat = 60
    var signed = false
    var cents = true

    var body: some View {
        CountingText(value: value, format: { v in Self.text(v, signed: signed, cents: cents) })
            .font(.geist(size, .regular))
            .tracking(-size * 0.04)
            .monospacedDigit()
            .lineLimit(1)
            .minimumScaleFactor(0.5)
    }

    static func text(_ v: Double, signed: Bool, cents: Bool) -> String {
        let s = signed ? Format.signedMoney(v) : Format.money(v)
        return cents ? s : (s.split(separator: ".").first.map(String.init) ?? s)
    }
}

/// The pill on glow cards: a dark translucent capsule ("▲ 67.3%").
struct GlowPill: View {
    var text: String

    var body: some View {
        Text(text).font(.geist(13, .semibold)).monospacedDigit()
            .padding(.horizontal, 10).padding(.vertical, 5)
            .background(.black.opacity(0.28), in: Capsule())
    }
}

/// The yellow marker used on dials, tick bars and charts.
struct GlowMarker: View {
    var size: CGFloat = 12

    var body: some View {
        Triangle().fill(Color(hex: 0xFFF36A)).frame(width: size, height: size * 0.85)
    }
}

private struct Triangle: Shape {
    func path(in r: CGRect) -> Path {
        Path { p in
            p.move(to: CGPoint(x: r.minX, y: r.minY))
            p.addLine(to: CGPoint(x: r.maxX, y: r.minY))
            p.addLine(to: CGPoint(x: r.midX, y: r.maxY))
            p.closeSubpath()
        }
    }
}

/// A half-circle dial with ticks: where `fraction` (0…1) sits between two labels.
struct GlowDial: View {
    var fraction: Double
    var low: String
    var high: String
    var caption: String

    var body: some View {
        Canvas { ctx, size in
            let r = min(size.width / 2, size.height) - 6
            let c = CGPoint(x: size.width / 2, y: size.height - 4)
            var arc = Path()
            arc.addArc(center: c, radius: r, startAngle: .degrees(180), endAngle: .degrees(360), clockwise: false)
            ctx.stroke(arc, with: .color(.white.opacity(0.55)), lineWidth: 1.2)
            for i in 0 ... 40 {
                let a = Double.pi * (1 - Double(i) / 40)
                let inner = r - (i % 5 == 0 ? 12 : 7)
                var t = Path()
                t.move(to: CGPoint(x: c.x + r * cos(a), y: c.y - r * sin(a)))
                t.addLine(to: CGPoint(x: c.x + inner * cos(a), y: c.y - inner * sin(a)))
                ctx.stroke(t, with: .color(.white.opacity(0.5)), lineWidth: 1)
            }
            let f = min(max(fraction, 0), 1)
            let a = Double.pi * (1 - f)
            let tip = CGPoint(x: c.x + (r + 2) * cos(a), y: c.y - (r + 2) * sin(a))
            var dash = Path()
            dash.move(to: tip)
            dash.addLine(to: CGPoint(x: tip.x, y: c.y))
            ctx.stroke(dash, with: .color(.white.opacity(0.6)), style: StrokeStyle(lineWidth: 1, dash: [1.5, 4]))
            var tri = Path()
            tri.move(to: CGPoint(x: tip.x - 7, y: tip.y - 14))
            tri.addLine(to: CGPoint(x: tip.x + 7, y: tip.y - 14))
            tri.addLine(to: CGPoint(x: tip.x, y: tip.y))
            tri.closeSubpath()
            ctx.fill(tri, with: .color(Color(hex: 0xFFF36A)))
        }
        .overlay(alignment: .bottom) {
            VStack(spacing: 10) {
                Text(caption.uppercased()).font(.mono(10)).tracking(1.6).opacity(0.8)
                HStack {
                    Text(low).font(.mono(10)).opacity(0.6)
                    Spacer()
                    Text(high).font(.mono(10)).opacity(0.6)
                }
            }
        }
    }
}

/// A thin ring with a share drawn on it and the share in the middle.
struct GlowRing: View {
    var fraction: Double
    var label: String

    var body: some View {
        ZStack {
            Circle().stroke(.white.opacity(0.35), lineWidth: 1)
            Circle().trim(from: 0, to: min(max(fraction, 0), 1))
                .stroke(.white, style: StrokeStyle(lineWidth: 1.6, lineCap: .round))
                .rotationEffect(.degrees(-90))
            Text(label).font(.geist(17)).monospacedDigit()
        }
    }
}

/// A row of ticks with a marker at `fraction`: ticks before it bright, after it faint.
struct GlowTicks: View {
    var fraction: Double

    var body: some View {
        Canvas { ctx, size in
            let n = 34
            let step = size.width / CGFloat(n)
            let cut = Int((Double(n) * min(max(fraction, 0), 1)).rounded())
            for i in 0 ..< n {
                let x = step * CGFloat(i) + step / 2
                var p = Path()
                p.move(to: CGPoint(x: x, y: i % 5 == 0 ? 8 : 13))
                p.addLine(to: CGPoint(x: x, y: size.height))
                ctx.stroke(p, with: .color(.white.opacity(i < cut ? 0.9 : 0.35)), lineWidth: 1)
            }
            let mx = step * CGFloat(cut)
            var tri = Path()
            tri.move(to: CGPoint(x: mx - 5, y: 0))
            tri.addLine(to: CGPoint(x: mx + 5, y: 0))
            tri.addLine(to: CGPoint(x: mx, y: 7))
            tri.closeSubpath()
            ctx.fill(tri, with: .color(Color(hex: 0xFFF36A)))
        }
    }
}

/// Digits drawn as a dot matrix, like an LED display (0-9, %, +, -, .).
struct DotMatrixText: View {
    var text: String
    var dot: CGFloat = 3.6
    var color: Color = .white

    private static let font: [Character: [String]] = [
        "0": ["01110", "10001", "10011", "10101", "11001", "10001", "01110"],
        "1": ["00100", "01100", "00100", "00100", "00100", "00100", "01110"],
        "2": ["01110", "10001", "00001", "00010", "00100", "01000", "11111"],
        "3": ["11110", "00001", "00001", "01110", "00001", "00001", "11110"],
        "4": ["10010", "10010", "10010", "11111", "00010", "00010", "00010"],
        "5": ["11111", "10000", "11110", "00001", "00001", "10001", "01110"],
        "6": ["00110", "01000", "10000", "11110", "10001", "10001", "01110"],
        "7": ["11111", "00001", "00010", "00100", "00100", "00100", "00100"],
        "8": ["01110", "10001", "10001", "01110", "10001", "10001", "01110"],
        "9": ["01110", "10001", "10001", "01111", "00001", "00010", "01100"],
        "%": ["11000", "11001", "00010", "00100", "01000", "10011", "00011"],
        "+": ["00000", "00100", "00100", "11111", "00100", "00100", "00000"],
        "-": ["00000", "00000", "00000", "11111", "00000", "00000", "00000"],
        ".": ["00000", "00000", "00000", "00000", "00000", "01100", "01100"],
    ]

    var body: some View {
        let chars = Array(text).filter { Self.font[$0] != nil }
        let pitch = dot * 1.25
        let width = CGFloat(chars.count) * pitch * 6 - pitch
        Canvas { ctx, _ in
            for (n, ch) in chars.enumerated() {
                guard let rows = Self.font[ch] else { continue }
                for (y, row) in rows.enumerated() {
                    for (x, bit) in row.enumerated() where bit == "1" {
                        let origin = CGPoint(x: CGFloat(n * 6 + x) * pitch, y: CGFloat(y) * pitch)
                        ctx.fill(Path(ellipseIn: CGRect(origin: origin, size: CGSize(width: dot, height: dot))), with: .color(color))
                    }
                }
            }
        }
        .frame(width: max(width, 0), height: pitch * 7)
        .accessibilityLabel(text)
    }
}


// MARK: - Tiles and grids (same-size squares; tall and wide spans)

enum GlowTileShape { case square, wide, tall }

/// A glow tile: a small label and note at the top, a fun graphic in the middle, the figure at
/// the bottom. Squares in a group are all one size; a tall tile spans two squares, a wide one
/// the full row (see `GlowSquares`, `GlowTallRow`).
struct GlowTile<Graphic: View>: View {
    var label: String
    var note: String? = nil
    var value: String? = nil
    var unit: String? = nil
    var palette: GlowPalette
    var shape: GlowTileShape = .square
    var badge: String? = nil
    @ViewBuilder var graphic: Graphic

    var body: some View {
        let shapeR = RoundedRectangle(cornerRadius: 28, style: .continuous)
        VStack(alignment: .leading, spacing: 0) {
            HStack(alignment: .top, spacing: 6) {
                VStack(alignment: .leading, spacing: 2) {
                    Text(label).font(.geist(13, .medium)).lineLimit(1).minimumScaleFactor(0.8)
                    if let note { Text(note).font(.geist(11)).opacity(0.6).lineLimit(1) }
                }
                Spacer(minLength: 0)
                if let badge {
                    Text(badge).font(.geist(11, .semibold)).monospacedDigit()
                        .padding(.horizontal, 8).padding(.vertical, 4)
                        .background(.black.opacity(0.3), in: Capsule())
                }
            }
            Spacer(minLength: 6)
            graphic.frame(maxWidth: .infinity)
            Spacer(minLength: 6)
            if let value {
                HStack(alignment: .firstTextBaseline, spacing: 4) {
                    Text(value).font(.geist(shape == .square ? 28 : 34)).tracking(-1).monospacedDigit()
                        .lineLimit(1).minimumScaleFactor(0.5)
                    if let unit { Text(unit).font(.geist(13)).opacity(0.7) }
                }
            }
        }
        .padding(16)
        .frame(maxWidth: .infinity, maxHeight: .infinity, alignment: .topLeading)
        .foregroundStyle(palette.ink)
        .background { GlowFill(palette: palette) }
        .clipShape(shapeR)
        .overlay(shapeR.strokeBorder(.white.opacity(0.08)))
        .modifier(TileAspect(shape: shape))
    }
}

/// Squares are 1:1 and wide tiles two squares wide; tall tiles take the height they're given.
private struct TileAspect: ViewModifier {
    var shape: GlowTileShape

    func body(content: Content) -> some View {
        switch shape {
        case .square: content.aspectRatio(1, contentMode: .fit)
        case .wide: content.aspectRatio(GlowGrid.wideRatio, contentMode: .fit)
        case .tall: content
        }
    }
}

enum GlowGrid {
    static let spacing: CGFloat = 10
    /// A wide tile is two squares and the gap: about 2.06 : 1 at phone widths.
    static let wideRatio: CGFloat = 2.06
}

/// Two square tiles side by side, the same size.
struct GlowSquares<A: View, B: View>: View {
    @ViewBuilder var a: A
    @ViewBuilder var b: B

    var body: some View {
        HStack(spacing: GlowGrid.spacing) { a; b }
    }
}

/// A tall tile beside two stacked squares: the tall one is exactly their combined height.
struct GlowTallRow<T: View, A: View, B: View>: View {
    var tallOnRight = false
    @ViewBuilder var tall: T
    @ViewBuilder var a: A
    @ViewBuilder var b: B

    var body: some View {
        HStack(spacing: GlowGrid.spacing) {
            if tallOnRight {
                VStack(spacing: GlowGrid.spacing) { a; b }
                tall.frame(maxHeight: .infinity)
            } else {
                tall.frame(maxHeight: .infinity)
                VStack(spacing: GlowGrid.spacing) { a; b }
            }
        }
        .fixedSize(horizontal: false, vertical: true)
    }
}

// MARK: - Little graphics

/// A mini bar chart; the highlighted bar (default the last) is solid with a marker over it.
struct GlowBars: View {
    var values: [Double]
    var highlight: Int? = nil

    var body: some View {
        Canvas { ctx, size in
            guard !values.isEmpty else { return }
            let top = max(values.map { abs($0) }.max() ?? 1, 0.0001)
            let n = CGFloat(values.count)
            let gap: CGFloat = 3
            let w = max(1.5, (size.width - gap * (n - 1)) / n)
            let hi = highlight ?? values.count - 1
            for (i, v) in values.enumerated() {
                let h = max(3, (size.height - 10) * CGFloat(abs(v) / top))
                let r = CGRect(x: CGFloat(i) * (w + gap), y: size.height - h, width: w, height: h)
                ctx.fill(Path(roundedRect: r, cornerRadius: min(w / 2, 2)), with: .color(.white.opacity(i == hi ? 1 : 0.35)))
                if i == hi {
                    var t = Path()
                    t.move(to: CGPoint(x: r.midX - 4, y: r.minY - 9))
                    t.addLine(to: CGPoint(x: r.midX + 4, y: r.minY - 9))
                    t.addLine(to: CGPoint(x: r.midX, y: r.minY - 3))
                    t.closeSubpath()
                    ctx.fill(t, with: .color(Color(hex: 0xFFF36A)))
                }
            }
        }
    }
}

/// A row of dots whose size and brightness follow the values (a variability strip).
struct GlowDotRow: View {
    var values: [Double]

    var body: some View {
        Canvas { ctx, size in
            guard !values.isEmpty else { return }
            let top = max(values.map { abs($0) }.max() ?? 1, 0.0001)
            let step = size.width / CGFloat(values.count)
            for (i, v) in values.enumerated() {
                let f = CGFloat(abs(v) / top)
                let d = 2 + 5 * f
                let r = CGRect(x: step * (CGFloat(i) + 0.5) - d / 2, y: size.height / 2 - d / 2, width: d, height: d)
                ctx.fill(Path(ellipseIn: r), with: .color(.white.opacity(0.35 + 0.65 * Double(f))))
            }
        }
    }
}

/// Concentric rings, the inner `filled` ones bright (an aura).
struct GlowRings: View {
    var count = 4
    var filled = 2

    var body: some View {
        ZStack {
            ForEach(0 ..< count, id: \.self) { i in
                Circle()
                    .stroke(.white.opacity(i < filled ? 0.9 : 0.25), lineWidth: 1)
                    .scaleEffect(CGFloat(i + 1) / CGFloat(count))
            }
        }
        .aspectRatio(1, contentMode: .fit)
    }
}

/// A sun rising over a horizon: higher as `fraction` grows.
struct GlowSun: View {
    var fraction: Double

    var body: some View {
        GeometryReader { geo in
            let d = min(geo.size.width * 0.62, geo.size.height * 1.4)
            let horizon = geo.size.height * 0.72
            let rise = CGFloat(min(max(fraction, 0), 1)) * d * 0.55
            ZStack(alignment: .topLeading) {
                Circle()
                    .fill(LinearGradient(colors: [.white, Color(hex: 0xA7C4FF)], startPoint: .top, endPoint: .bottom))
                    .frame(width: d, height: d)
                    .position(x: geo.size.width / 2, y: horizon + d / 2 - rise)
                Rectangle().fill(.black.opacity(0.45))
                    .frame(width: geo.size.width, height: geo.size.height - horizon)
                    .offset(y: horizon)
                Rectangle().fill(.white.opacity(0.5)).frame(width: geo.size.width, height: 1).offset(y: horizon)
            }
            .clipped()
        }
    }
}

/// A square grid of dots, filled to `fraction` (left to right, top to bottom).
struct GlowDotGrid: View {
    var fraction: Double
    var side = 5

    var body: some View {
        Canvas { ctx, size in
            let n = side * side
            let lit = Int((Double(n) * min(max(fraction, 0), 1)).rounded())
            let pitch = min(size.width, size.height) / CGFloat(side)
            let d = pitch * 0.55
            let ox = (size.width - pitch * CGFloat(side)) / 2
            let oy = (size.height - pitch * CGFloat(side)) / 2
            for i in 0 ..< n {
                let x = ox + CGFloat(i % side) * pitch + (pitch - d) / 2
                let y = oy + CGFloat(i / side) * pitch + (pitch - d) / 2
                ctx.fill(Path(ellipseIn: CGRect(x: x, y: y, width: d, height: d)), with: .color(.white.opacity(i < lit ? 0.95 : 0.2)))
            }
        }
        .aspectRatio(1, contentMode: .fit)
    }
}

/// A thin line with the yellow marker on its last point.
struct GlowLine: View {
    var values: [Double]

    var body: some View {
        Canvas { ctx, size in
            guard values.count > 1, let lo = values.min(), let hi = values.max() else { return }
            let span = max(hi - lo, 0.0001)
            let pts = values.enumerated().map { i, v in
                CGPoint(x: size.width * CGFloat(i) / CGFloat(values.count - 1),
                        y: 8 + (size.height - 12) * CGFloat(1 - (v - lo) / span))
            }
            var p = Path()
            p.addLines(pts)
            ctx.stroke(p, with: .color(.white), style: StrokeStyle(lineWidth: 1.4, lineCap: .round, lineJoin: .round))
            if let last = pts.last {
                var t = Path()
                t.move(to: CGPoint(x: last.x - 5, y: last.y - 11))
                t.addLine(to: CGPoint(x: last.x + 5, y: last.y - 11))
                t.addLine(to: CGPoint(x: last.x, y: last.y - 3))
                t.closeSubpath()
                ctx.fill(t, with: .color(Color(hex: 0xFFF36A)))
            }
        }
    }
}

/// A disc showing a share as a lit wedge (like a compass dial), with a dotted ring and four
/// quarter labels around it.
struct GlowPie: View {
    var fraction: Double
    var labels: [String] = ["0", "25", "50", "75"]

    var body: some View {
        let f = min(max(fraction, 0), 1)
        ZStack {
            Circle().fill(LinearGradient(colors: [Color.white.opacity(0.18), Color.white.opacity(0.05)], startPoint: .top, endPoint: .bottom))
            PieWedge(fraction: f)
                .fill(LinearGradient(colors: [.white, Color(hex: 0xA7C4FF)], startPoint: .topLeading, endPoint: .bottomTrailing))
            Circle().strokeBorder(.white.opacity(0.35), style: StrokeStyle(lineWidth: 1, dash: [1, 4]))
                .padding(-8)
        }
        .overlay(alignment: .top) { Text(labels[0]).font(.mono(10)).opacity(0.7).offset(y: -26) }
        .overlay(alignment: .trailing) { Text(labels[1]).font(.mono(10)).opacity(0.7).offset(x: 26) }
        .overlay(alignment: .bottom) { Text(labels[2]).font(.mono(10)).opacity(0.7).offset(y: 26) }
        .overlay(alignment: .leading) { Text(labels[3]).font(.mono(10)).opacity(0.7).offset(x: -26) }
        .aspectRatio(1, contentMode: .fit)
    }
}

private struct PieWedge: Shape {
    var fraction: Double
    var animatableData: Double {
        get { fraction }
        set { fraction = newValue }
    }

    func path(in r: CGRect) -> Path {
        Path { p in
            let c = CGPoint(x: r.midX, y: r.midY)
            p.move(to: c)
            p.addArc(center: c, radius: min(r.width, r.height) / 2, startAngle: .degrees(-90), endAngle: .degrees(-90 + 360 * fraction), clockwise: false)
            p.closeSubpath()
        }
    }
}
