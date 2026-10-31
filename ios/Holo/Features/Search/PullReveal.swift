import SwiftUI

/// The "pack pull" moment after a purchase is saved, like the website: the item flips in with a
/// foil sweep, then your collection's value counts up to its new total. Tap anywhere to close.
struct PullReveal: View {
    var event: PullEvent
    var onDone: () -> Void
    var onOpen: () -> Void
    @Environment(CollectionStore.self) private var store
    @Environment(\.accessibilityReduceMotion) private var reduceMotion
    @State private var flipped = false
    @State private var sweep = false
    @State private var shownValue: Double = 0
    @State private var risen = false

    private var after: Double { store.allHoldings.reduce(0) { $0 + ($1.value ?? 0) } }
    private var isCard: Bool { !event.product.isSealed && event.product.imageURL != nil }

    var body: some View {
        let added = after - event.before
        let overBudget = store.monthlyBudget.map { store.spentThisMonth - $0 }
        ZStack {
            Rectangle().fill(.ultraThinMaterial).ignoresSafeArea()
            Theme.background.opacity(0.55).ignoresSafeArea()
            RadialGradient(colors: [Color(red: 0.63, green: 0.47, blue: 1).opacity(0.28), Color(red: 0.31, green: 0.78, blue: 1).opacity(0.12), .clear],
                           center: .center, startRadius: 0, endRadius: 280)
                .ignoresSafeArea()
                .allowsHitTesting(false)

            VStack(spacing: 0) {
                art
                    .rotation3DEffect(.degrees(flipped || reduceMotion ? 0 : 100), axis: (x: 0, y: 1, z: 0), perspective: 0.6)
                    .scaleEffect(flipped || reduceMotion ? 1 : 0.7)
                    .opacity(flipped || reduceMotion ? 1 : 0)

                VStack(spacing: 8) {
                    MonoLabel(text: "Added to your collection")
                    (Text(event.quantity > 1 ? "\(Int(event.quantity)) × " : "").foregroundColor(Theme.muted) + Text(event.product.name))
                        .font(.geist(22, .semibold)).multilineTextAlignment(.center).lineLimit(3)
                }
                .padding(.top, 32)
                .opacity(risen ? 1 : 0).offset(y: risen ? 0 : 12)

                VStack(spacing: 6) {
                    Text("Collection value").font(.geist(12)).foregroundStyle(Theme.muted)
                    CountUp(value: shownValue)
                        .font(.display(52)).monospacedDigit().foregroundStyle(Theme.lime).displayTrim(52)
                    if abs(added) >= 0.01 {
                        (Text(Format.signedMoney(added)).foregroundColor(Theme.up) + Text(" at today's price").foregroundColor(Theme.muted))
                            .font(.geist(13)).monospacedDigit()
                    }
                    if let over = overBudget, over > 0 {
                        (Text("That puts you ").foregroundColor(Theme.muted) + Text(Format.money(over)).foregroundColor(Theme.down).fontWeight(.medium) + Text(" over your monthly budget").foregroundColor(Theme.muted))
                            .font(.geist(12)).monospacedDigit()
                            .padding(.horizontal, 12).padding(.vertical, 6)
                            .background(Theme.surface2, in: Capsule())
                            .padding(.top, 6)
                    }
                }
                .padding(.top, 24)
                .opacity(risen ? 1 : 0).offset(y: risen ? 0 : 12)

                HStack(spacing: 10) {
                    Button("Done", action: onDone).buttonStyle(Button3D(kind: .dark, height: 48))
                    Button(action: onOpen) { Label("View product", systemImage: "arrow.right").labelStyle(.titleAndIcon) }
                        .buttonStyle(Button3D(kind: .lime, height: 48))
                }
                .padding(.top, 32)
                .opacity(risen ? 1 : 0)
            }
            .padding(.horizontal, 28)
        }
        .contentShape(Rectangle())
        .onTapGesture(perform: onDone)
        .sensoryFeedback(.success, trigger: flipped)
        .onAppear(perform: play)
        .accessibilityElement(children: .contain)
        .accessibilityAddTraits(.isModal)
    }

    /// The item with a foil band sweeping across it once.
    private var art: some View {
        let shape = RoundedRectangle(cornerRadius: isCard ? 10 : 24, style: .continuous)
        return Group {
            if isCard {
                ProductImage(product: event.product, cornerRadius: 10).frame(width: 190, height: 266)
            } else {
                SealedWell(product: event.product, cornerRadius: 24, caption: false).frame(width: 230, height: 230)
            }
        }
        .overlay {
            GeometryReader { geo in
                LinearGradient(stops: [
                    .init(color: .clear, location: 0.2),
                    .init(color: Color(red: 1, green: 0.47, blue: 0.78).opacity(0.6), location: 0.35),
                    .init(color: Color(red: 0.47, green: 0.86, blue: 1).opacity(0.6), location: 0.5),
                    .init(color: Color(red: 1, green: 0.9, blue: 0.47).opacity(0.6), location: 0.65),
                    .init(color: .clear, location: 0.8),
                ], startPoint: .leading, endPoint: .trailing)
                .frame(width: geo.size.width * 2.5)
                .offset(x: sweep ? geo.size.width : -geo.size.width * 2.5)
                .blendMode(.colorDodge)
            }
            .clipShape(shape)
            .allowsHitTesting(false)
        }
        .shadow(color: .black.opacity(0.6), radius: 30, y: 16)
    }

    private func play() {
        shownValue = event.before
        guard !reduceMotion else {
            flipped = true; risen = true; shownValue = after
            return
        }
        withAnimation(.spring(response: 0.7, dampingFraction: 0.7)) { flipped = true }
        withAnimation(.easeInOut(duration: 1.1).delay(0.35)) { sweep = true }
        withAnimation(.easeOut(duration: 0.5).delay(0.5)) { risen = true }
        withAnimation(.timingCurve(0.16, 1, 0.3, 1, duration: 1.6).delay(0.75)) { shownValue = after }
    }
}

/// Money that animates between values (the number itself is animatable).
private struct CountUp: View, Animatable {
    var value: Double
    var animatableData: Double {
        get { value }
        set { value = newValue }
    }

    var body: some View { Text(Format.money(value)) }
}
