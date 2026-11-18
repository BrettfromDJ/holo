import SwiftUI

// Small, cheap bits of motion shared around the app, in the family of the week recap's embers
// and snow: one Canvas each, 20 frames a second at most (slow drift needs no more), paused while off screen or under a
// sheet (onVisibilityChange), and still under Reduce Motion.

/// Looping particles in one color: sparks rising, motes drifting, or dust falling and twinkling.
/// Drawn by iOS's own particle system (Core Animation), so they move at the screen's full rate
/// (up to 120 a second) with no work on the app's side each frame: smooth, never steppy.
struct MoteParticles: View {
    enum Style { case sparks, motes, dust }
    var style: Style
    var color: Color
    var count = 22

    var body: some View {
        ParticleEmitter(kind: {
            switch style {
            case .sparks: return .rise(UIColor(color), count: count)
            case .motes: return .drift(UIColor(color), count: count)
            case .dust: return .fall(UIColor(color), count: count)
            }
        }())
    }
}

/// iOS's particle system in a SwiftUI view: a few presets in the app's style (a soft dot with a
/// glow), filling the view from the start, pausing off screen and under sheets, still under
/// Reduce Motion.
struct ParticleEmitter: UIViewRepresentable {
    enum Kind: Equatable {
        /// Sparks rising from the bottom, swaying.
        case rise(UIColor, count: Int)
        /// Motes floating slowly up and sideways.
        case drift(UIColor, count: Int)
        /// Dust falling slowly, twinkling.
        case fall(UIColor, count: Int)
        /// Fire embers (orange to yellow) rising.
        case embers
        /// Snow falling.
        case snow
    }

    var kind: Kind
    @Environment(\.accessibilityReduceMotion) private var reduceMotion
    @Environment(\.pageHidden) private var pageHidden

    func makeUIView(context: Context) -> EmitterHost {
        let v = EmitterHost()
        v.configure(kind)
        return v
    }

    func updateUIView(_ v: EmitterHost, context: Context) {
        if v.kind != kind { v.configure(kind) }
        v.still = reduceMotion
        v.hiddenPage = pageHidden
    }

    final class EmitterHost: UIView {
        private let emitter = CAEmitterLayer()
        fileprivate var kind: Kind?
        var still = false { didSet { refresh() } }
        var hiddenPage = false { didSet { refresh() } }

        override init(frame: CGRect) {
            super.init(frame: frame)
            isUserInteractionEnabled = false
            backgroundColor = .clear
            // Particles stay inside their box (the card or tile they're behind).
            clipsToBounds = true
            layer.addSublayer(emitter)
            NotificationCenter.default.addObserver(self, selector: #selector(refresh), name: .sheetCoverChanged, object: nil)
        }
        required init?(coder: NSCoder) { fatalError() }

        override func layoutSubviews() {
            super.layoutSubviews()
            emitter.frame = bounds
            place()
        }

        override func didMoveToWindow() {
            super.didMoveToWindow()
            refresh()
        }

        /// Running only when on screen, not under a sheet and not on a page kept out of sight.
        @objc func refresh() {
            let run = window != nil && !hiddenPage && !SheetCover.shared.isOpen
            // Reduce Motion: the particles hold still where they are.
            emitter.speed = run && !still ? 1 : 0
            emitter.birthRate = run || still ? 1 : 0
        }

        fileprivate func configure(_ k: Kind) {
            kind = k
            let cell = CAEmitterCell()
            cell.contents = Self.dot.cgImage
            cell.scale = 0.32
            cell.scaleRange = 0.18
            switch k {
            case let .rise(c, count):
                cell.color = c.cgColor
                cell.lifetime = 6
                cell.birthRate = Float(count) / 6
                cell.emissionLongitude = -.pi / 2; cell.emissionRange = .pi / 24
                cell.alphaRange = 0.3; cell.alphaSpeed = -0.14
                cell.scaleSpeed = -0.03
            case let .drift(c, count):
                cell.color = c.withAlphaComponent(0.8).cgColor
                cell.lifetime = 9
                cell.birthRate = Float(count) / 9
                cell.velocity = 5; cell.velocityRange = 3
                cell.emissionLongitude = -.pi / 3; cell.emissionRange = .pi / 2
                cell.alphaRange = 0.4; cell.alphaSpeed = -0.08
            case let .fall(c, count):
                cell.color = c.cgColor
                cell.lifetime = 10
                cell.birthRate = Float(count) / 10
                cell.emissionLongitude = .pi / 2; cell.emissionRange = .pi / 24
                cell.alphaRange = 0.5; cell.alphaSpeed = -0.07
                cell.scale = 0.24
                // A slow spin of a glow-shaped dot reads as a gentle twinkle.
                cell.spinRange = 2
            case .embers:
                cell.color = UIColor(red: 1, green: 0.55, blue: 0.15, alpha: 1).cgColor
                cell.greenRange = 0.25; cell.blueRange = 0.1
                cell.lifetime = 5
                cell.birthRate = 5
                cell.emissionLongitude = -.pi / 2; cell.emissionRange = .pi / 24
                cell.alphaSpeed = -0.18
                cell.scaleSpeed = -0.04
            case .snow:
                cell.color = UIColor.white.withAlphaComponent(0.9).cgColor
                cell.lifetime = 9
                cell.birthRate = 3
                cell.emissionLongitude = .pi / 2; cell.emissionRange = .pi / 24
                cell.alphaRange = 0.4; cell.alphaSpeed = -0.05
                cell.scale = 0.26
            }
            cell.name = "dot"
            emitter.emitterCells = [cell]
            emitter.renderMode = .additive
            // Begun a lifetime ago, so the view starts full instead of filling up.
            emitter.beginTime = CACurrentMediaTime() - Double(cell.lifetime)
            place()
            refresh()
        }

        /// Where the particles start: a line along the bottom (rising) or the top (falling), the
        /// whole area for drifting motes.
        private func place() {
            guard let kind else { return }
            let b = bounds
            // Rising and falling ones cross the box once over their life: a gentle drift,
            // whatever the box's height.
            if let cell = emitter.emitterCells?.first, b.height > 0 {
                switch kind {
                case .rise, .embers, .fall, .snow:
                    let v = b.height / CGFloat(max(cell.lifetime, 1))
                    emitter.setValue(v, forKeyPath: "emitterCells.\(cell.name ?? "dot").velocity")
                    emitter.setValue(v * 0.3, forKeyPath: "emitterCells.\(cell.name ?? "dot").velocityRange")
                case .drift: break
                }
            }
            switch kind {
            case .rise, .embers:
                emitter.emitterShape = .line
                emitter.emitterPosition = CGPoint(x: b.midX, y: b.maxY + 4)
                emitter.emitterSize = CGSize(width: b.width * 0.85, height: 1)
            case .fall, .snow:
                emitter.emitterShape = .line
                emitter.emitterPosition = CGPoint(x: b.midX, y: b.minY - 4)
                emitter.emitterSize = CGSize(width: b.width, height: 1)
            case .drift:
                emitter.emitterShape = .rectangle
                emitter.emitterPosition = CGPoint(x: b.midX, y: b.midY)
                emitter.emitterSize = b.size
            }
        }

        /// One soft dot: a bright core and a glow around it, drawn once and shared.
        static let dot: UIImage = {
            let size = CGSize(width: 16, height: 16)
            return UIGraphicsImageRenderer(size: size).image { ctx in
                let c = ctx.cgContext
                let colors = [UIColor.white.cgColor, UIColor.white.withAlphaComponent(0.35).cgColor, UIColor.white.withAlphaComponent(0).cgColor] as CFArray
                if let g = CGGradient(colorsSpace: CGColorSpaceCreateDeviceRGB(), colors: colors, locations: [0, 0.25, 1]) {
                    c.drawRadialGradient(g, startCenter: CGPoint(x: 8, y: 8), startRadius: 0, endCenter: CGPoint(x: 8, y: 8), endRadius: 8, options: [])
                }
            }
        }()
    }
}

extension Notification.Name {
    /// A glass sheet went up or down (see SheetCover): particles pause under one.
    static let sheetCoverChanged = Notification.Name("sheetCoverChanged")
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
