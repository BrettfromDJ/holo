import SwiftUI

// Shared pieces for the More pages (Analytics, Gains, Grading, Binder), so they share Home's
// energy: a glowing hero number on a grid, tinted stat tiles that count up, bars that grow in
// and Anton section headings.

/// The top of a More page: a mono label, a big Anton number that counts up and glows, a line
/// under it, on Home's grid with lime and pink glows.
struct MoreHero<Below: View>: View {
    var label: String
    var value: Double
    var format: (Double) -> String
    var tint: Color
    @ViewBuilder var below: Below

    var body: some View {
        VStack(alignment: .leading, spacing: 12) {
            MonoLabel(text: label)
            CountingText(value: value, format: format)
                .font(.display(64)).monospacedDigit()
                .foregroundStyle(tint)
                .lineLimit(1).minimumScaleFactor(0.5)
                .displayTrim(64)
                .shadow(color: tint.opacity(0.45), radius: 22)
                .flashOnAppear(tint)
            below
        }
        .frame(maxWidth: .infinity, alignment: .leading)
        .padding(.vertical, 18)
        .background {
            ZStack {
                GridPattern()
                RadialGradient(colors: [tint.opacity(0.22), .clear], center: UnitPoint(x: 0.25, y: 0.5), startRadius: 0, endRadius: 240)
                RadialGradient(colors: [Theme.planBlue.opacity(0.16), .clear], center: UnitPoint(x: 0.9, y: 0.2), startRadius: 0, endRadius: 200)
            }
            .padding(.horizontal, -16)
            .mask(LinearGradient(colors: [.clear, .black, .black, .clear], startPoint: .top, endPoint: .bottom))
            .allowsHitTesting(false)
        }
    }
}

/// An Anton heading with a muted line under it, like Home's section titles.
struct MoreHeading: View {
    var title: String
    var subtitle: String?

    var body: some View {
        VStack(alignment: .leading, spacing: 6) {
            DisplayText(text: title.uppercased(), size: 26)
            if let subtitle { Text(subtitle).font(.geist(14)).foregroundStyle(Theme.muted) }
        }
        .frame(maxWidth: .infinity, alignment: .leading)
    }
}

/// A tinted tile with an Anton figure that counts up, like Home's metric cards.
struct CountTile: View {
    var label: String
    var value: Double?
    var format: (Double) -> String
    var valueTint: Color = .white
    var sub: String
    var glow: Color
    var tag: String? = nil

    var body: some View {
        VStack(alignment: .leading, spacing: 0) {
            HStack(spacing: 6) {
                Text(label.uppercased()).font(.display(14)).tracking(0.3).foregroundStyle(.white.opacity(0.85))
                    .lineLimit(1).minimumScaleFactor(0.75).displayTrim(14)
                Spacer(minLength: 0)
                if let tag { SkewTag(text: tag, color: glow, textColor: glow == Theme.lime ? Theme.ink : .white) }
            }
            Group {
                if let value {
                    CountingText(value: value, format: format)
                } else {
                    Text("—")
                }
            }
            .font(.display(26)).monospacedDigit().foregroundStyle(valueTint)
            .lineLimit(1).minimumScaleFactor(0.55).displayTrim(26)
            .flashOnAppear(valueTint == .white ? .clear : valueTint)
            .padding(.top, 14)
            Text(sub).font(.geist(12)).foregroundStyle(Theme.muted).lineLimit(2).minimumScaleFactor(0.85)
                .fixedSize(horizontal: false, vertical: true)
                .padding(.top, 8)
        }
        .frame(maxWidth: .infinity, minHeight: 92, alignment: .topLeading)
        .tinted(glow, radius: 20, border: false)
    }
}

/// A capsule that grows to `fraction` of the width the first time it scrolls into view (and
/// again when the page comes back), with its glow.
struct GrowBar: View {
    var fraction: Double
    var color: Color
    var height: CGFloat = 8
    var delay: Double = 0
    var gradient = true
    @Environment(\.accessibilityReduceMotion) private var reduceMotion
    @State private var grown = false

    var body: some View {
        GeometryReader { geo in
            ZStack(alignment: .leading) {
                Capsule().fill(Theme.surface2)
                Capsule()
                    .fill(gradient ? AnyShapeStyle(LinearGradient(colors: [color.opacity(0.5), color], startPoint: .leading, endPoint: .trailing)) : AnyShapeStyle(color))
                    .frame(width: max(height, geo.size.width * max(0, min(1, fraction))) * (grown || reduceMotion ? 1 : 0.001))
                    .shadow(color: color.opacity(0.45), radius: 6)
            }
        }
        .frame(height: height)
        .onFirstVisible { grow() }
        .onReplay {
            grown = false
            grow()
        }
    }

    private func grow() {
        guard !reduceMotion else { return }
        withAnimation(.spring(response: 0.9, dampingFraction: 0.82).delay(0.15 + delay)) { grown = true }
    }
}

/// A view that pops in (scale and fade) after `delay` the first time it's visible, for staggered
/// grids of tiles and heatmap cells.
struct PopIn: ViewModifier {
    var delay: Double
    @Environment(\.accessibilityReduceMotion) private var reduceMotion
    @State private var shown = false

    func body(content: Content) -> some View {
        content
            .scaleEffect(shown || reduceMotion ? 1 : 0.6)
            .opacity(shown || reduceMotion ? 1 : 0)
            .onFirstVisible {
                guard !shown else { return }
                withAnimation(.spring(response: 0.5, dampingFraction: 0.7).delay(delay)) { shown = true }
            }
            .onReplay {
                guard !reduceMotion else { return }
                shown = false
                withAnimation(.spring(response: 0.5, dampingFraction: 0.7).delay(delay)) { shown = true }
            }
    }
}

extension View {
    func popIn(delay: Double = 0) -> some View { modifier(PopIn(delay: delay)) }
}
