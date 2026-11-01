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

