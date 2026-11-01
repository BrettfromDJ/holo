import SwiftUI

// MARK: - Tilt shine

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
                    .onAppear { Tilt.shared.start() }
                    .onDisappear { Tilt.shared.stop() }
            }
        }
    }
}

/// Its own view, so a motion update redraws only the band.
private struct ShineBand: View {
    private var motion: Tilt { Tilt.shared }

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
                .offset(x: CGFloat(motion.x - 0.35) * w * 0.85, y: CGFloat(motion.y) * h * 0.25)
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
