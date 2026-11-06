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
    /// A pull: the pack's foil wrapper tearing open (0 to 1) before the card rises out.
    @State private var torn = false
    /// A pull: the card's value counting up from nothing.
    @State private var pullValue: Double = 0

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
                ZStack {
                    art
                        .rotation3DEffect(.degrees(flipped || reduceMotion ? 0 : 100), axis: (x: 0, y: 1, z: 0), perspective: 0.6)
                        .scaleEffect(flipped || reduceMotion ? 1 : 0.7)
                        .opacity(flipped || reduceMotion ? 1 : 0)
                        .offset(y: event.pulled && !flipped && !reduceMotion ? 60 : 0)
                    if event.pulled && !reduceMotion { PackWrapper(torn: torn) }
                }

                if event.pulled {
                    pullFigures
                } else {
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
                        .font(.display(52)).tracking(-2.1).monospacedDigit().foregroundStyle(Theme.lime).displayTrim(52)
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
                }

                HStack(spacing: 10) {
                    if event.pulled {
                        ShareLink(item: shareImage, preview: SharePreview("My pull", image: shareImage)) {
                            Label("Share", systemImage: "square.and.arrow.up")
                        }
                        .buttonStyle(Button3D(kind: .dark, height: 48))
                    }
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
        .sensoryFeedback(event.pulled ? .impact(weight: .heavy, intensity: 1) : .success, trigger: flipped)
        .onAppear(perform: play)
        .accessibilityElement(children: .contain)
        .accessibilityAddTraits(.isModal)
    }

    /// The item with a foil band sweeping across it once.
    private var art: some View {
        let slab = event.identity?.isGraded == true
        let shape = RoundedRectangle(cornerRadius: slab ? 14 : (isCard ? 10 : 24), style: .continuous)
        return Group {
            if slab, let id = event.identity {
                // A graded add shows in its slab (with its Pristine mark and bumper, if any).
                HoldingArt(product: event.product, identity: id, caption: false).frame(width: 210, height: 336)
            } else if isCard {
                ProductImage(product: event.product, cornerRadius: 10).frame(width: 190, height: 266)
            } else {
                SealedWell(product: event.product, cornerRadius: 24, caption: false).frame(width: 230, height: 230)
            }
        }
        // The shadow goes on before the foil sweep, so it's drawn once rather than every frame
        // the band moves (the sweep stays inside the picture, so it looks the same).
        .shadow(color: .black.opacity(0.6), radius: 30, y: 16)
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
    }

    /// A pull's moment: "You pulled", the card's value counting up from $0 in big lime figures,
    /// whether it's your best pull ever, and the collection's new total underneath.
    private var pullFigures: some View {
        let value = max(after - event.before, 0)
        let best = isBestPull(value)
        return VStack(spacing: 6) {
            MonoLabel(text: "You pulled", color: Theme.lime)
            Text(event.product.name).font(.geist(20, .semibold)).multilineTextAlignment(.center).lineLimit(2)
            CountUp(value: pullValue)
                .font(.display(60)).tracking(-2.4).monospacedDigit().foregroundStyle(Theme.lime).displayTrim(60)
                .padding(.top, 6)
            if best {
                SkewTag(text: "Your best pull ever", icon: "crown.fill").padding(.top, 4)
            }
            (Text("Collection now ").foregroundColor(Theme.muted) + Text(Format.money(after)).foregroundColor(.white))
                .font(.geist(13)).monospacedDigit().padding(.top, 6)
        }
        .padding(.top, 28)
        .opacity(risen ? 1 : 0).offset(y: risen ? 0 : 12)
    }

    /// Whether this pull is worth more than every other card you've pulled.
    private func isBestPull(_ value: Double) -> Bool {
        guard value > 0 else { return false }
        let others = store.pulledHoldings.filter { $0.identity.key != event.identity?.key }
        let unit = value / max(event.quantity, 1)
        return others.allSatisfy { ($0.price ?? 0) < unit }
    }

    /// The pull as a picture to share: the card, "Pulled", its name and value.
    private var shareImage: Image {
        let card = PullShareCard(product: event.product, identity: event.identity, value: max(after - event.before, 0))
        let renderer = ImageRenderer(content: card)
        renderer.scale = 3
        return renderer.uiImage.map { Image(uiImage: $0) } ?? Image(systemName: "sparkles")
    }

    private func play() {
        if event.pulled {
            playPull()
            return
        }
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

extension PullReveal {
    /// The pull: the wrapper tears open, the card rises out and flips in with its foil sweep,
    /// then its value counts up from $0.
    fileprivate func playPull() {
        let value = max(after - event.before, 0)
        shownValue = after
        guard !reduceMotion else {
            torn = true; flipped = true; risen = true; pullValue = value
            return
        }
        withAnimation(.easeIn(duration: 0.45).delay(0.15)) { torn = true }
        withAnimation(.spring(response: 0.7, dampingFraction: 0.7).delay(0.45)) { flipped = true }
        withAnimation(.easeInOut(duration: 1.1).delay(0.85)) { sweep = true }
        withAnimation(.easeOut(duration: 0.5).delay(0.9)) { risen = true }
        withAnimation(.timingCurve(0.16, 1, 0.3, 1, duration: 1.8).delay(1.0)) { pullValue = value }
    }
}

/// A foil pack wrapper over the card that tears open: the top strip flies up and away, the body
/// drops and fades, so the card can rise out.
private struct PackWrapper: View {
    var torn: Bool

    private static let foil = LinearGradient(colors: [Color(hex: 0x6B5CFF), Color(hex: 0xFF5FAE), Color(hex: 0xFFC94D), Color(hex: 0x4FD1FF)],
                                             startPoint: .topLeading, endPoint: .bottomTrailing)

    var body: some View {
        let shape = RoundedRectangle(cornerRadius: 14, style: .continuous)
        VStack(spacing: 0) {
            // The torn-off top strip.
            shape.fill(Self.foil)
                .overlay(shape.fill(Color.black.opacity(0.15)))
                .frame(width: 210, height: 46)
                .rotationEffect(.degrees(torn ? -18 : 0))
                .offset(x: torn ? 40 : 0, y: torn ? -160 : 0)
                .opacity(torn ? 0 : 1)
            // The pack's body.
            shape.fill(Self.foil)
                .overlay {
                    VStack(spacing: 6) {
                        Image(systemName: "sparkles").font(.system(size: 28, weight: .bold))
                        Text("LUCENT").font(.geist(13, .bold)).tracking(3)
                    }
                    .foregroundStyle(.white.opacity(0.9))
                }
                .frame(width: 210, height: 250)
                .offset(y: torn ? 220 : 0)
                .opacity(torn ? 0 : 1)
        }
        .allowsHitTesting(false)
        .accessibilityHidden(true)
    }
}

/// The picture shared for a pull: the card on a dark card with a lime glow, "Pulled", its name
/// and value, and the app's name small at the bottom.
struct PullShareCard: View {
    var product: Product
    var identity: HoldingIdentity?
    var value: Double

    var body: some View {
        VStack(spacing: 14) {
            HStack {
                PulledBadge()
                Spacer()
            }
            HoldingArt(product: product, identity: identity, cornerRadius: 12, caption: false)
                .frame(width: 220, height: identity?.isGraded == true ? 352 : 307)
            Text(product.name).font(.geist(18, .semibold)).foregroundStyle(.white).multilineTextAlignment(.center).lineLimit(2)
            Text(Format.money(value)).font(.display(40)).tracking(-1.4).monospacedDigit().foregroundStyle(Theme.lime)
            Text("Lucent").font(.geist(12, .semibold)).tracking(1).foregroundStyle(.white.opacity(0.5))
        }
        .padding(24)
        .frame(width: 320)
        .background {
            ZStack {
                Color(hex: 0x0B0B0C)
                RadialGradient(colors: [Theme.lime.opacity(0.25), .clear], center: .center, startRadius: 0, endRadius: 220)
            }
        }
        .environment(\.imageMaxPixel, nil)
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
