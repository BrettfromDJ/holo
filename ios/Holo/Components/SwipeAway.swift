import SwiftUI

/// Swipe a row left or right to remove it: a pink panel with a trash icon shows behind the
/// side it slides from, and past half-way the row slides out and `onRemove` runs; let go
/// sooner and it snaps back. Only the row's offset moves while you drag, and an up-and-down
/// drag is left to the list's scrolling. Respects Reduce Motion (no slide, just the removal).
struct SwipeAway: ViewModifier {
    var name: String
    var onRemove: () -> Void
    @State private var dragX: CGFloat = 0
    @State private var leaving = false
    @Environment(\.accessibilityReduceMotion) private var reduceMotion
    private let threshold: CGFloat = 120

    func body(content: Content) -> some View {
        content
            .offset(x: dragX)
            .background(alignment: dragX < 0 ? .trailing : .leading) {
                VStack(spacing: 5) {
                    Image(systemName: "trash.fill").font(.system(size: 16, weight: .semibold))
                    Text("Remove").font(.geist(12, .semibold))
                }
                .foregroundStyle(.white)
                .frame(width: max(0, min(abs(dragX), 120)))
                .frame(maxHeight: .infinity)
                .background(RoundedRectangle(cornerRadius: 20, style: .continuous).fill(Theme.planPink))
                .opacity(min(1, abs(dragX) / 50))
                .accessibilityHidden(true)
            }
            .simultaneousGesture(
                DragGesture(minimumDistance: 18)
                    .onChanged { g in
                        guard !leaving, abs(g.translation.width) > abs(g.translation.height) * 1.3 else { return }
                        dragX = g.translation.width
                    }
                    .onEnded { g in
                        guard !leaving, dragX != 0 else { return }
                        let end = g.predictedEndTranslation.width
                        if abs(end) > threshold || abs(dragX) > threshold {
                            leaving = true
                            if reduceMotion {
                                onRemove()
                            } else {
                                withAnimation(.easeIn(duration: 0.18)) { dragX = end < 0 ? -600 : 600 }
                                DispatchQueue.main.asyncAfter(deadline: .now() + 0.18) { onRemove() }
                            }
                        } else {
                            withAnimation(reduceMotion ? nil : .snappy(duration: 0.25)) { dragX = 0 }
                        }
                    }
            )
            .accessibilityAction(named: "Remove \(name)") { onRemove() }
    }
}

extension View {
    /// Swipe left or right to remove (see `SwipeAway`).
    func swipeAway(_ name: String, onRemove: @escaping () -> Void) -> some View {
        modifier(SwipeAway(name: name, onRemove: onRemove))
    }
}
