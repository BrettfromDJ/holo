import SwiftUI

/// What the lime + opens: two glass pills, Scan and Search, that spring out from behind the
/// button and fan up to either side of it, over a dimmed screen. Tap one to go, or anywhere
/// else (or the ×) to fold them back in.
struct AddMenu: View {
    @Binding var open: Bool
    var onScan: () -> Void
    var onSearch: () -> Void
    @Environment(\.accessibilityReduceMotion) private var reduceMotion

    var body: some View {
        ZStack(alignment: .bottom) {
            // The dim: tap anywhere to close.
            Color.black.opacity(open ? 0.55 : 0)
                .ignoresSafeArea()
                .allowsHitTesting(open)
                .onTapGesture { close() }
                .accessibilityHidden(true)

            HStack(spacing: 14) {
                pill("Scan", icon: "viewfinder", side: -1, delay: 0, action: onScan)
                pill("Search", icon: "magnifyingglass", side: 1, delay: 0.04, action: onSearch)
            }
            // Just above the +, which sits 18pt above the 64pt bar.
            .padding(.bottom, 112)
        }
        .sensoryFeedback(.impact(weight: .light), trigger: open)
    }

    /// A pill that starts tucked behind the + (small, centered under it) and springs out to its
    /// place on the left or right.
    private func pill(_ title: String, icon: String, side: CGFloat, delay: Double, action: @escaping () -> Void) -> some View {
        Button {
            close()
            // Let the pills fold away before the next screen slides up.
            DispatchQueue.main.asyncAfter(deadline: .now() + 0.18, execute: action)
        } label: {
            HStack(spacing: 10) {
                Image(systemName: icon)
                    .font(.system(size: 16, weight: .bold))
                    .foregroundStyle(Theme.ink)
                    .frame(width: 34, height: 34)
                    .background(Circle().fill(Theme.lime))
                Text(title).font(.geist(16, .semibold)).foregroundStyle(.white)
            }
            .padding(.leading, 7)
            .padding(.trailing, 18)
            .frame(height: 48)
            .liquidGlass(in: Capsule())
            .shadow(color: .black.opacity(0.45), radius: 14, y: 8)
            .contentShape(Capsule())
        }
        .buttonStyle(PressScale())
        .accessibilityLabel(title == "Scan" ? "Scan cards" : "Search and add")
        // Closed: tucked behind the + (it sits below and between the two pills).
        .scaleEffect(open ? 1 : 0.3, anchor: side < 0 ? .trailing : .leading)
        .offset(x: open || reduceMotion ? 0 : -side * 70, y: open || reduceMotion ? 0 : 66)
        .rotationEffect(.degrees(open || reduceMotion ? 0 : Double(side) * 25))
        .opacity(open ? 1 : 0)
        .allowsHitTesting(open)
        .animation(reduceMotion ? .easeOut(duration: 0.15) : .spring(response: 0.42, dampingFraction: 0.68).delay(open ? delay : 0), value: open)
    }

    private func close() {
        withAnimation(.spring(response: 0.36, dampingFraction: 0.8)) { open = false }
    }
}

/// Shrinks a little while held, so the pills feel pressable.
private struct PressScale: ButtonStyle {
    func makeBody(configuration: Configuration) -> some View {
        configuration.label
            .scaleEffect(configuration.isPressed ? 0.94 : 1)
            .animation(.spring(response: 0.25, dampingFraction: 0.7), value: configuration.isPressed)
    }
}
