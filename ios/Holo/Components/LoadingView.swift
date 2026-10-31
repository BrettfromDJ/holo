import SwiftUI

/// The loading screen: three cards fanned on the lit grid, shuffling in a loop (the front card
/// tucks to the back and the next springs forward with a lime glow and a foil sweep), over a
/// rotating collector's caption. Cheap: a few offsets and rotations per step, no per-frame
/// drawing. With Reduce Motion the cards rest and only the caption changes.
struct LoadingView: View {
    var fullScreen = false
    @Environment(\.accessibilityReduceMotion) private var reduceMotion

    private static let captions = [
        "Shuffling your binder…",
        "Checking today's prices…",
        "Polishing the slabs…",
        "Counting your grails…",
        "Sleeving the hits…",
        "Opening the vault…",
    ]

    var body: some View {
        VStack(spacing: 34) {
            deck.frame(width: 200, height: 170)
            TimelineView(.periodic(from: .now, by: 1.6)) { context in
                let i = Int(context.date.timeIntervalSinceReferenceDate / 1.6) % Self.captions.count
                Text(Self.captions[i])
                    .font(.geist(15, .medium))
                    .foregroundStyle(Theme.muted)
                    .contentTransition(.opacity)
                    .animation(.easeInOut(duration: 0.35), value: i)
                    .id(i)
                    .transition(.opacity)
            }
            .frame(height: 20)
        }
        .frame(maxWidth: .infinity, maxHeight: fullScreen ? .infinity : nil)
        .padding(.vertical, fullScreen ? 0 : 120)
        .background {
            ZStack {
                GridPattern(step: 28, opacity: 0.06)
                RadialGradient(colors: [Theme.lime.opacity(0.18), .clear], center: .center, startRadius: 0, endRadius: 220)
                RadialGradient(colors: [Theme.planPink.opacity(0.1), .clear], center: UnitPoint(x: 0.8, y: 0.3), startRadius: 0, endRadius: 180)
                RadialGradient(colors: [Theme.planBlue.opacity(0.12), .clear], center: UnitPoint(x: 0.2, y: 0.75), startRadius: 0, endRadius: 180)
            }
            .mask(RadialGradient(colors: [.black, .clear], center: .center, startRadius: 40, endRadius: 320))
            .allowsHitTesting(false)
        }
        .background(fullScreen ? Theme.background : Color.clear)
        .accessibilityElement(children: .ignore)
        .accessibilityLabel("Loading")
    }

    @ViewBuilder private var deck: some View {
        if reduceMotion {
            cards(step: 0)
        } else {
            PhaseAnimator([0, 1, 2]) { step in
                cards(step: step)
            } animation: { _ in
                .spring(response: 0.55, dampingFraction: 0.72)
            }
        }
    }

    /// The three cards, each in the slot it holds at this step (back, middle, front).
    private func cards(step: Int) -> some View {
        ZStack {
            ForEach(0 ..< 3, id: \.self) { i in
                let slot = (i + step) % 3
                LoaderCard(front: slot == 2, tint: [Theme.planBlue, Theme.planPink, Theme.lime][i])
                    .rotationEffect(.degrees([-12, -2, 9][slot]))
                    .offset(x: [-38, -6, 30][slot], y: [8, 0, -8][slot])
                    .scaleEffect([0.9, 0.95, 1.04][slot])
                    .zIndex(Double(slot))
            }
        }
    }
}

/// One card in the loader: a dark card with a colored glow, the front one lit with a lime
/// edge and a foil sweep.
private struct LoaderCard: View {
    var front: Bool
    var tint: Color
    @State private var sweep = false
    @Environment(\.accessibilityReduceMotion) private var reduceMotion

    var body: some View {
        let shape = RoundedRectangle(cornerRadius: 12, style: .continuous)
        ZStack {
            shape.fill(Theme.surface2)
            RadialGradient(colors: [tint.opacity(0.35), .clear], center: .top, startRadius: 0, endRadius: 110)
                .clipShape(shape)
            // A simple card face: art window and two lines.
            VStack(spacing: 6) {
                RoundedRectangle(cornerRadius: 6, style: .continuous).fill(.white.opacity(0.07))
                    .frame(height: 70)
                Capsule().fill(.white.opacity(0.12)).frame(height: 5)
                Capsule().fill(.white.opacity(0.08)).frame(width: 40, height: 5)
                    .frame(maxWidth: .infinity, alignment: .leading)
            }
            .padding(10)
            if front {
                LinearGradient(stops: [
                    .init(color: .clear, location: 0.3),
                    .init(color: .white.opacity(0.35), location: 0.5),
                    .init(color: .clear, location: 0.7),
                ], startPoint: .leading, endPoint: .trailing)
                .frame(width: 220)
                .offset(x: sweep ? 140 : -140)
                .clipShape(shape)
                .blendMode(.plusLighter)
                .allowsHitTesting(false)
            }
        }
        .frame(width: 92, height: 128)
        .overlay(shape.strokeBorder(front ? Theme.lime : Theme.border, lineWidth: front ? 1.5 : 1))
        .shadow(color: front ? Theme.lime.opacity(0.45) : .black.opacity(0.4), radius: 14, y: 6)
        .onAppear {
            guard !reduceMotion else { return }
            withAnimation(.easeInOut(duration: 1.4).repeatForever(autoreverses: false)) { sweep = true }
        }
    }
}
