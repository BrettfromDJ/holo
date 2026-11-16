import SwiftUI

// Small, cheap bits of motion shared around the app, in the family of the week recap's embers
// and snow: one Canvas each, 30 frames a second at most, paused while off screen or under a
// sheet (onVisibilityChange), and still under Reduce Motion.

/// Looping particles in one color: sparks rising, motes drifting, or dust falling and twinkling.
struct MoteParticles: View {
    enum Style { case sparks, motes, dust }
    var style: Style
    var color: Color
    var count = 22
    @Environment(\.accessibilityReduceMotion) private var reduceMotion
    @State private var onScreen = true

    var body: some View {
        TimelineView(.animation(minimumInterval: 1.0 / 30, paused: reduceMotion || !onScreen)) { context in
            let time = reduceMotion ? 3 : context.date.timeIntervalSinceReferenceDate
            Canvas { ctx, size in draw(ctx, size, time) }
        }
        .allowsHitTesting(false)
        .accessibilityHidden(true)
        .onVisibilityChange { visible in if visible != onScreen { onScreen = visible } }
    }

    private func draw(_ ctx: GraphicsContext, _ size: CGSize, _ time: Double) {
        func r(_ i: Int, _ k: Double) -> Double {
            let v = sin(Double(i) * 12.9898 + k * 78.233) * 43758.5453
            return v - floor(v)
        }
        func frac(_ v: Double) -> Double { v - floor(v) }
        for i in 0 ..< count {
            let x0 = size.width * CGFloat(r(i, 1))
            var x = x0, y: CGFloat, rad: CGFloat, a: Double
            switch style {
            case .sparks:
                // Rising, quick, swaying a little; brightest mid-way.
                let p = frac(time * (0.12 + 0.16 * r(i, 2)) + r(i, 3))
                x += CGFloat(sin(time * 2 + Double(i)) * 8 * p)
                y = size.height * CGFloat(1 - p)
                rad = CGFloat(1 + 1.8 * r(i, 4)) * CGFloat(1 - p * 0.5)
                a = sin(Double.pi * p)
            case .motes:
                // Floating slowly sideways and up, like dust in light.
                let p = frac(time * (0.03 + 0.05 * r(i, 2)) + r(i, 3))
                x = size.width * CGFloat(frac(r(i, 1) + p * 0.35)) + CGFloat(sin(time * 0.7 + Double(i)) * 6)
                y = size.height * CGFloat(frac(r(i, 5) - p * 0.4))
                rad = CGFloat(1.2 + 2.2 * r(i, 4))
                a = 0.75 * sin(Double.pi * p)
            case .dust:
                // Drifting down, each twinkling on its own beat.
                let p = frac(time * (0.04 + 0.05 * r(i, 2)) + r(i, 3))
                x += CGFloat(sin(time * 0.9 + Double(i)) * 10)
                y = size.height * CGFloat(p)
                rad = CGFloat(0.8 + 1.6 * r(i, 4))
                a = (0.35 + 0.65 * pow(max(0, sin(time * (1.5 + r(i, 6)) + Double(i))), 3)) * sin(Double.pi * p)
            }
            ctx.fill(Path(ellipseIn: CGRect(x: x - rad * 3, y: y - rad * 3, width: rad * 6, height: rad * 6)), with: .color(color.opacity(0.16 * a)))
            ctx.fill(Path(ellipseIn: CGRect(x: x - rad, y: y - rad, width: rad * 2, height: rad * 2)), with: .color(color.opacity(a)))
        }
    }
}

/// A one-off burst of sparks from the middle, each time `trigger` changes (about 0.8s, then
/// nothing runs). For a tap or a pull: the tab you're already on, pull to refresh.
struct SparkBurst: View {
    var trigger: Int
    var color: Color = Theme.lime
    var count = 14
    /// How far the sparks fly, in points.
    var spread: CGFloat = 40
    @Environment(\.accessibilityReduceMotion) private var reduceMotion
    @State private var start: Date?
    private static let life = 0.8

    var body: some View {
        ZStack {
            if let start {
                TimelineView(.animation(minimumInterval: 1.0 / 60)) { context in
                    let t = context.date.timeIntervalSince(start) / Self.life
                    Canvas { ctx, size in draw(ctx, size, min(max(t, 0), 1)) }
                }
            }
        }
        .allowsHitTesting(false)
        .accessibilityHidden(true)
        .onChange(of: trigger) { _, _ in
            guard !reduceMotion else { return }
            let now = Date()
            start = now
            Task {
                try? await Task.sleep(for: .seconds(Self.life + 0.05))
                if start == now { start = nil }
            }
        }
    }

    private func draw(_ ctx: GraphicsContext, _ size: CGSize, _ t: Double) {
        func r(_ i: Int, _ k: Double) -> Double {
            let v = sin(Double(i) * 12.9898 + k * 78.233) * 43758.5453
            return v - floor(v)
        }
        let c = CGPoint(x: size.width / 2, y: size.height / 2)
        // Fast out, then slowing; a touch of fall at the end.
        let ease = 1 - pow(1 - t, 3)
        for i in 0 ..< count {
            let angle = Double(i) / Double(count) * 2 * .pi + r(i, 1) * 0.5
            let dist = spread * CGFloat(0.55 + 0.45 * r(i, 2)) * CGFloat(ease)
            let x = c.x + CGFloat(cos(angle)) * dist
            let y = c.y + CGFloat(sin(angle)) * dist + CGFloat(t * t * 10)
            let rad = CGFloat(1.2 + 1.6 * r(i, 3)) * CGFloat(1 - t * 0.6)
            let a = 1 - t
            ctx.fill(Path(ellipseIn: CGRect(x: x - rad * 3, y: y - rad * 3, width: rad * 6, height: rad * 6)), with: .color(color.opacity(0.2 * a)))
            ctx.fill(Path(ellipseIn: CGRect(x: x - rad, y: y - rad, width: rad * 2, height: rad * 2)), with: .color(color.opacity(a)))
        }
    }
}

/// A slow band of light across a slab's case, like turning it under a lamp: one sweep every
/// few seconds (a single offset animation; nothing runs between sweeps). Brighter on a 10.
struct SlabSweep: View {
    var bright: Bool
    var cornerRadius: CGFloat
    @Environment(\.accessibilityReduceMotion) private var reduceMotion
    @State private var onScreen = false
    @State private var phase: CGFloat = 0

    var body: some View {
        GeometryReader { geo in
            let w = geo.size.width, h = geo.size.height
            LinearGradient(colors: [.clear, .white.opacity(bright ? 0.3 : 0.18), .clear], startPoint: .leading, endPoint: .trailing)
                .frame(width: w * 0.5, height: h * 1.8)
                .rotationEffect(.degrees(22))
                .offset(x: -w * 0.8 + phase * w * 2.1, y: -h * 0.4)
        }
        .blendMode(.plusLighter)
        .clipShape(RoundedRectangle(cornerRadius: cornerRadius, style: .continuous))
        .allowsHitTesting(false)
        .accessibilityHidden(true)
        .onVisibilityChange { visible in if visible != onScreen { onScreen = visible } }
        .task(id: onScreen) {
            guard onScreen, !reduceMotion else { return }
            try? await Task.sleep(for: .seconds(1.2))
            while !Task.isCancelled {
                phase = 0
                withAnimation(.easeInOut(duration: 1.6)) { phase = 1 }
                try? await Task.sleep(for: .seconds(6))
            }
        }
    }
}

extension View {
    /// Pull to refresh with a burst of lime sparks at the top as it lets go.
    func sparkRefresh(_ action: @escaping @MainActor () async -> Void) -> some View {
        modifier(SparkRefresh(action: action))
    }
}

private struct SparkRefresh: ViewModifier {
    var action: @MainActor () async -> Void
    @State private var bursts = 0

    func body(content: Content) -> some View {
        content
            .refreshable {
                await MainActor.run { bursts += 1 }
                await action()
            }
            .overlay(alignment: .top) {
                SparkBurst(trigger: bursts, count: 18, spread: 70)
                    .frame(width: 180, height: 140)
                    .padding(.top, 40)
            }
    }
}
