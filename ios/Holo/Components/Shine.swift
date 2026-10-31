import CoreMotion
import SwiftUI

// MARK: - Tilt shine

/// The phone's roll and pitch, smoothed, for the shine band on the star card. Runs only while a
/// shine is on screen, at 30 updates a second.
@Observable
final class ShineMotion {
    static let shared = ShineMotion()

    /// -1...1 left/right and up/down from where the phone was held when it started.
    private(set) var roll: Double = 0
    private(set) var pitch: Double = 0

    private let manager = CMMotionManager()
    @ObservationIgnored private var listeners = 0
    @ObservationIgnored private var origin: CMAttitude?

    func start() {
        listeners += 1
        guard listeners == 1, manager.isDeviceMotionAvailable else { return }
        manager.deviceMotionUpdateInterval = 1 / 30
        manager.startDeviceMotionUpdates(to: .main) { [weak self] motion, _ in
            guard let self, let motion else { return }
            if self.origin == nil { self.origin = motion.attitude.copy() as? CMAttitude }
            let att = motion.attitude
            if let origin = self.origin { att.multiply(byInverseOf: origin) }
            let r = max(-1, min(1, att.roll / 0.6))
            let p = max(-1, min(1, att.pitch / 0.6))
            // Ease toward the reading so the band glides instead of jittering.
            let nextRoll = self.roll + (r - self.roll) * 0.2
            let nextPitch = self.pitch + (p - self.pitch) * 0.2
            // Skip tiny changes so a phone lying still doesn't redraw.
            if abs(nextRoll - self.roll) > 0.002 { self.roll = nextRoll }
            if abs(nextPitch - self.pitch) > 0.002 { self.pitch = nextPitch }
        }
    }

    func stop() {
        listeners = max(0, listeners - 1)
        guard listeners == 0 else { return }
        manager.stopDeviceMotionUpdates()
        origin = nil
        roll = 0
        pitch = 0
    }
}

/// A soft white and lime band of light across the art that slides as you tilt the phone.
/// Only the band's offset changes; it is off under Reduce Motion.
private struct TiltShine: ViewModifier {
    var cornerRadius: CGFloat
    @Environment(\.accessibilityReduceMotion) private var reduceMotion

    func body(content: Content) -> some View {
        content.overlay {
            if !reduceMotion {
                ShineBand()
                    .blendMode(.plusLighter)
                    .clipShape(RoundedRectangle(cornerRadius: cornerRadius, style: .continuous))
                    .allowsHitTesting(false)
                    .accessibilityHidden(true)
                    .onAppear { ShineMotion.shared.start() }
                    .onDisappear { ShineMotion.shared.stop() }
            }
        }
    }
}

/// Its own view, so a motion update redraws only the band.
private struct ShineBand: View {
    private var motion: ShineMotion { ShineMotion.shared }

    private static let gradient = LinearGradient(
        stops: [
            .init(color: .clear, location: 0),
            .init(color: .white.opacity(0.10), location: 0.3),
            .init(color: .white.opacity(0.28), location: 0.48),
            .init(color: Theme.lime.opacity(0.22), location: 0.56),
            .init(color: .clear, location: 1),
        ],
        startPoint: .leading, endPoint: .trailing
    )

    var body: some View {
        GeometryReader { geo in
            let w = geo.size.width
            let h = geo.size.height
            Self.gradient
                .frame(width: w * 0.9, height: h * 1.8)
                .rotationEffect(.degrees(22))
                // At rest the band sits toward the top left; tilting slides it across.
                .offset(x: CGFloat(motion.roll - 0.35) * w * 0.85, y: CGFloat(motion.pitch) * h * 0.25)
                .frame(width: w, height: h)
        }
    }
}

extension View {
    /// A band of light across the art that follows the phone's tilt.
    func tiltShine(cornerRadius: CGFloat = 12) -> some View { modifier(TiltShine(cornerRadius: cornerRadius)) }
}

// MARK: - Grail shimmer

/// A slow lime light running around a piece's edge: one rotating gradient, masked to a thin
/// rounded outline. Off under Reduce Motion, and stopped while the tile is off screen.
struct GrailShimmer: View {
    var cornerRadius: CGFloat
    @Environment(\.accessibilityReduceMotion) private var reduceMotion
    @State private var spin = false

    private static let sweep = AngularGradient(
        stops: [
            .init(color: .clear, location: 0),
            .init(color: .clear, location: 0.62),
            .init(color: Theme.lime.opacity(0.95), location: 0.8),
            .init(color: .clear, location: 0.96),
        ],
        center: .center, startAngle: .zero, endAngle: .degrees(360)
    )

    var body: some View {
        let shape = RoundedRectangle(cornerRadius: cornerRadius, style: .continuous)
        if !reduceMotion {
            GeometryReader { geo in
                // A square as big as the diagonal, so it covers every corner as it turns.
                let d = (geo.size.width * geo.size.width + geo.size.height * geo.size.height).squareRoot()
                Self.sweep
                    .frame(width: d, height: d)
                    .rotationEffect(.degrees(spin ? 360 : 0))
                    .frame(width: geo.size.width, height: geo.size.height)
            }
            .mask { shape.strokeBorder(lineWidth: 1.5) }
            .overlay(shape.strokeBorder(Theme.lime.opacity(0.14), lineWidth: 1))
            .allowsHitTesting(false)
            .accessibilityHidden(true)
            .onVisibilityChange { visible in
                if visible {
                    guard !spin else { return }
                    withAnimation(.linear(duration: 4).repeatForever(autoreverses: false)) { spin = true }
                } else {
                    stopLoop { spin = false }
                }
            }
        }
    }
}
