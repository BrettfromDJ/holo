import CoreMotion
import SwiftUI

// MARK: - Counting numbers

/// A number that counts to its value: up from 85% when it first appears, and from the old
/// value to the new one whenever it changes (a refresh), easing out like the website's.
struct CountingText: View {
    var value: Double
    var format: (Double) -> String
    var duration: Double = 1.3
    @Environment(\.accessibilityReduceMotion) private var reduceMotion
    @State private var shown: Double?

    var body: some View {
        CountingLabel(value: shown ?? value * 0.85, format: format)
            .onAppear {
                guard shown == nil else { return }
                if reduceMotion { shown = value; return }
                shown = value * 0.85
                withAnimation(.timingCurve(0.16, 1, 0.3, 1, duration: duration)) { shown = value }
            }
            .onChange(of: value) { _, new in
                if reduceMotion { shown = new; return }
                withAnimation(.timingCurve(0.16, 1, 0.3, 1, duration: 0.9)) { shown = new }
            }
    }
}

/// Text whose number is animatable, so SwiftUI redraws it at every step of the count.
private struct CountingLabel: View, Animatable {
    var value: Double
    var format: (Double) -> String
    var animatableData: Double {
        get { value }
        set { value = newValue }
    }

    var body: some View { Text(format(value)) }
}

/// Flashes a colored number once when it appears: a quick glow in its own color.
struct FlashOnAppear: ViewModifier {
    var color: Color
    var delay: Double = 0.9
    @Environment(\.accessibilityReduceMotion) private var reduceMotion
    @State private var lit = false

    func body(content: Content) -> some View {
        content
            .shadow(color: color.opacity(lit ? 0.9 : 0), radius: lit ? 14 : 0)
            .brightness(lit ? 0.12 : 0)
            .onAppear {
                guard !reduceMotion else { return }
                withAnimation(.easeOut(duration: 0.25).delay(delay)) { lit = true }
                withAnimation(.easeIn(duration: 0.6).delay(delay + 0.3)) { lit = false }
            }
    }
}

extension View {
    func flashOnAppear(_ color: Color, delay: Double = 0.9) -> some View { modifier(FlashOnAppear(color: color, delay: delay)) }
}

// MARK: - Reveal on scroll

extension View {
    /// Runs once when the view first scrolls into sight (iOS 18), or when it appears on iOS 17.
    @ViewBuilder func onFirstVisible(_ action: @escaping () -> Void) -> some View {
        if #available(iOS 18, *) {
            onScrollVisibilityChange(threshold: 0.01) { visible in if visible { action() } }
        } else {
            onAppear(perform: action)
        }
    }

    /// Lifts and fades a section in the first time it scrolls into view, like the website.
    func reveal() -> some View { modifier(Reveal()) }
}

private struct Reveal: ViewModifier {
    @Environment(\.accessibilityReduceMotion) private var reduceMotion
    @State private var shown = false

    func body(content: Content) -> some View {
        content
            .opacity(shown || reduceMotion ? 1 : 0)
            .offset(y: shown || reduceMotion ? 0 : 28)
            .scaleEffect(shown || reduceMotion ? 1 : 0.98, anchor: .top)
            .onFirstVisible {
                guard !shown else { return }
                withAnimation(.spring(response: 0.6, dampingFraction: 0.85)) { shown = true }
            }
    }
}

// MARK: - Charts drawing in

extension View {
    /// Draws a chart in left to right the first time it scrolls into view (and again whenever
    /// `replay` changes, e.g. a new range), like the Performance chart.
    func drawIn<T: Equatable>(replay: T, duration: Double = 1.2) -> some View { modifier(DrawIn(replay: replay, duration: duration)) }
    func drawIn(duration: Double = 1.2) -> some View { modifier(DrawIn(replay: 0, duration: duration)) }
}

private struct DrawIn<T: Equatable>: ViewModifier {
    var replay: T
    var duration: Double
    @Environment(\.accessibilityReduceMotion) private var reduceMotion
    @State private var drawn: CGFloat = 0

    func body(content: Content) -> some View {
        content
            .mask(alignment: .leading) {
                GeometryReader { geo in Rectangle().frame(width: geo.size.width * (reduceMotion ? 1 : drawn)) }
            }
            .onFirstVisible {
                guard drawn == 0 else { return }
                withAnimation(.easeInOut(duration: duration)) { drawn = 1 }
            }
            .onChange(of: replay) { _, _ in
                drawn = 0
                withAnimation(.easeInOut(duration: duration * 0.7)) { drawn = 1 }
            }
    }
}

// MARK: - Tilt

/// The phone's tilt, smoothed, for cards that lean as you move it. Runs only while something
/// on screen is listening, at 30 updates a second.
@Observable
final class Tilt {
    static let shared = Tilt()

    /// -1...1 left/right and up/down from where the phone was held when it started.
    private(set) var x: Double = 0
    private(set) var y: Double = 0

    private let manager = CMMotionManager()
    private var listeners = 0
    private var origin: CMAttitude?

    func start() {
        listeners += 1
        guard listeners == 1, manager.isDeviceMotionAvailable else { return }
        manager.deviceMotionUpdateInterval = 1 / 30
        manager.startDeviceMotionUpdates(to: .main) { [weak self] motion, _ in
            guard let self, let motion else { return }
            if self.origin == nil { self.origin = motion.attitude.copy() as? CMAttitude }
            let att = motion.attitude
            if let origin = self.origin { att.multiply(byInverseOf: origin) }
            let nx = max(-1, min(1, att.roll / 0.5))
            let ny = max(-1, min(1, att.pitch / 0.5))
            // Ease toward the reading so the cards glide rather than jitter.
            self.x += (nx - self.x) * 0.2
            self.y += (ny - self.y) * 0.2
        }
    }

    func stop() {
        listeners = max(0, listeners - 1)
        guard listeners == 0 else { return }
        manager.stopDeviceMotionUpdates()
        origin = nil
        x = 0
        y = 0
    }
}

/// Leans a card with the phone's tilt; with `foil`, a rainbow sheen slides across it as it
/// moves, like light on a holo card.
struct TiltCard: ViewModifier {
    var amount: Double = 10
    var foil = false
    var cornerRadius: CGFloat = 8
    @Environment(\.accessibilityReduceMotion) private var reduceMotion
    private var tilt: Tilt { Tilt.shared }

    func body(content: Content) -> some View {
        if reduceMotion {
            content
        } else {
            content
                .overlay {
                    if foil {
                        LinearGradient(
                            colors: [.clear, Color(hex: 0xFF6AD5).opacity(0.35), Color(hex: 0x8AF5FF).opacity(0.35),
                                     Color(hex: 0xD4FF3A).opacity(0.35), .clear],
                            startPoint: UnitPoint(x: 0.0 + tilt.x * 0.6, y: 0.0 + tilt.y * 0.6),
                            endPoint: UnitPoint(x: 1.0 + tilt.x * 0.6, y: 1.0 + tilt.y * 0.6)
                        )
                        .blendMode(.overlay)
                        .clipShape(RoundedRectangle(cornerRadius: cornerRadius, style: .continuous))
                        .allowsHitTesting(false)
                    }
                }
                .rotation3DEffect(.degrees(tilt.x * amount), axis: (x: 0, y: 1, z: 0), perspective: 0.6)
                .rotation3DEffect(.degrees(-tilt.y * amount * 0.7), axis: (x: 1, y: 0, z: 0), perspective: 0.6)
                .onAppear { Tilt.shared.start() }
                .onDisappear { Tilt.shared.stop() }
        }
    }
}

extension View {
    func tiltCard(_ amount: Double = 10, foil: Bool = false, cornerRadius: CGFloat = 8) -> some View {
        modifier(TiltCard(amount: amount, foil: foil, cornerRadius: cornerRadius))
    }
}
