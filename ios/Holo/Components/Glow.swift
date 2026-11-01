import SwiftUI

// The small graphic pieces Master Sets uses: the set deck's glow, dot-matrix digits, the
// ownership dial (`GlowPie`), a thin ring and a tick bar. (Left from the brief "Lucent glow"
// look; the rest of it was removed.)

/// A set card's light: the dark surface with a lime, blue or pink glow from one corner and a
/// second, softer one from the other, chosen by the set's id so a set always looks the same.
/// Static gradients, cheap to draw.
struct SetGlow: View {
    var id: String

    var body: some View {
        let accents = [Theme.lime, Theme.planBlue, Theme.planPink]
        var h: UInt64 = 1469598103934665603
        for b in id.utf8 { h = (h ^ UInt64(b)) &* 1099511628211 }
        let first = accents[Int(h % 3)]
        let second = accents[Int((h / 3) % 3)]
        return ZStack {
            Theme.surface
            RadialGradient(colors: [first.opacity(0.26), .clear], center: .topLeading, startRadius: 0, endRadius: 260)
            RadialGradient(colors: [second.opacity(0.16), .clear], center: .bottomTrailing, startRadius: 0, endRadius: 240)
            LinearGradient(colors: [.white.opacity(0.04), .clear], startPoint: .top, endPoint: .center)
        }
        .allowsHitTesting(false)
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
            ctx.fill(tri, with: .color(Theme.lime))
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
                .fill(Theme.lime)
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
