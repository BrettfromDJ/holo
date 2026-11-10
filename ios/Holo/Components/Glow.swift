import SwiftUI

// The small graphic pieces Master Sets uses: the set deck's glow, the
// ownership dial (`GlowPie`), a thin ring and a tick bar. (Left from the brief "Dexora glow"
// look; the rest of it was removed.)

/// A set card's light: the dark surface with a lime, blue or pink glow from one corner and a
/// second, softer one from the other, chosen by the set's id so a set always looks the same.
/// Static gradients, cheap to draw.
struct SetGlow: View {
    var id: String

    /// The set's main light (lime, blue or pink), the same one its card glows with.
    static func accent(for id: String) -> Color {
        let accents = [Theme.lime, Theme.planBlue, Theme.planPink]
        var h: UInt64 = 1469598103934665603
        for b in id.utf8 { h = (h ^ UInt64(b)) &* 1099511628211 }
        return accents[Int(h % 3)]
    }

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

/// A share as a thick ring: a dark lime track, and a lime arc with round ends that starts at the
/// top, with an arrow riding at its start. The arc sweeps in when it appears and glides to a new
/// share (instantly under Reduce Motion). The track is frosted, so the dots behind are blurred.
struct GlowPie: View {
    var fraction: Double
    @State private var shown: Double = 0
    @Environment(\.accessibilityReduceMotion) private var reduceMotion

    var body: some View {
        let f = min(max(fraction, 0), 1)
        GeometryReader { geo in
            let side = min(geo.size.width, geo.size.height)
            let line = side * 0.2
            ZStack {
                // The track: a ring of Liquid Glass with a faint lime tint, so it reads clearly
                // over the dotted backdrop.
                Color.clear.liquidGlass(in: RingShape(thickness: line), tint: Theme.lime.opacity(0.18))
                // A fine light edge on both sides of the ring, so its shape is always clear.
                RingShape(thickness: line).stroke(Color.white.opacity(0.28), lineWidth: 1)
                // The arc. Even at 0% the round start shows, so the arrow always has a home.
                Circle()
                    .inset(by: line / 2)
                    .trim(from: 0, to: max(shown, 0.0001))
                    .stroke(Theme.lime, style: StrokeStyle(lineWidth: line, lineCap: .round))
                    .rotationEffect(.degrees(-90))
                    .shadow(color: Theme.lime.opacity(0.35), radius: 10)
                // The arrow at the top, where the arc begins.
                Image(systemName: "arrow.right")
                    .font(.system(size: line * 0.5, weight: .bold))
                    .foregroundStyle(Theme.ink)
                    .offset(y: -(side / 2 - line / 2))
            }
            .frame(width: side, height: side)
            .frame(maxWidth: .infinity, maxHeight: .infinity)
        }
        .aspectRatio(1, contentMode: .fit)
        .onAppear {
            if reduceMotion { shown = f; return }
            shown = 0
            withAnimation(.timingCurve(0.3, 0, 0.2, 1, duration: 0.9).delay(0.15)) { shown = f }
        }
        .onChange(of: f) { _, new in
            withAnimation(reduceMotion ? nil : .timingCurve(0.3, 0, 0.2, 1, duration: 0.9)) { shown = new }
        }
        .accessibilityElement()
        .accessibilityLabel("\(Int((f * 100).rounded())) percent complete")
    }
}

/// A ring: the outer circle with the middle cut out (drawn as two circles of opposite direction,
/// so glass and fills leave the center clear).
struct RingShape: InsettableShape {
    var thickness: CGFloat
    var inset: CGFloat = 0

    func path(in rect: CGRect) -> Path {
        let c = CGPoint(x: rect.midX, y: rect.midY)
        let outer = min(rect.width, rect.height) / 2 - inset
        let inner = max(outer - thickness + inset * 2, 0)
        var p = Path()
        p.addArc(center: c, radius: outer, startAngle: .zero, endAngle: .degrees(360), clockwise: false)
        p.closeSubpath()
        p.addArc(center: c, radius: inner, startAngle: .zero, endAngle: .degrees(360), clockwise: true)
        p.closeSubpath()
        return p
    }

    func inset(by amount: CGFloat) -> RingShape {
        var r = self
        r.inset += amount
        return r
    }
}
