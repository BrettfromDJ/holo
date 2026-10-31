import SwiftUI

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

    /// Up or down.
    static func tone(_ value: Double?) -> GlowPalette { (value ?? 0) < 0 ? .down : .up }

    /// A steady palette for a product (the same card always gets the same glow), warmer for
    /// rarer cards.
    static func forProduct(_ id: String) -> GlowPalette {
        let options: [GlowPalette] = [.orchid, .indigo, .ocean, .ember, .gold, .violet]
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
        GeometryReader { geo in
            let side = max(geo.size.width, geo.size.height)
            ZStack {
                palette.base
                ForEach(Array(palette.blobs.enumerated()), id: \.offset) { _, b in
                    RadialGradient(
                        stops: [
                            .init(color: b.color.opacity(b.strength), location: 0),
                            .init(color: b.color.opacity(b.strength * 0.55), location: 0.35),
                            .init(color: b.color.opacity(0), location: 1),
                        ],
                        center: UnitPoint(x: b.x, y: b.y), startRadius: 0, endRadius: side * b.size
                    )
                }
                Textures.image("grain").resizable(resizingMode: .tile)
                    .opacity(0.16).blendMode(.overlay)
            }
            .drawingGroup()
        }
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
