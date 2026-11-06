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
    /// A pull: the pack's little shake just before it tears.
    @State private var shaking = false
    /// A pull: the card's value counting up from nothing.
    @State private var pullValue: Double = 0
    /// A card's spin, in degrees: it starts on its back, turns a few times and lands on its
    /// face at 0.
    @State private var spin: Double = 900
    /// The card back has appeared (it scales in before spinning).
    @State private var shown = false
    /// The lime flash behind the card as it lands.
    @State private var landed = false

    private var after: Double { store.allHoldings.reduce(0) { $0 + ($1.value ?? 0) } }
    private var isCard: Bool { !event.product.isSealed && event.product.imageURL != nil }
    /// A raw card spins in from its back (a slab or sealed product flips in as before).
    private var spins: Bool { isCard && event.identity?.isGraded != true && !reduceMotion }
    /// Screenshots: hold the spin partway, on the card's back.
    private static let holdBack = ProcessInfo.processInfo.arguments.contains("-HoloPullBack")

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
                Spacer(minLength: 12)
                ZStack {
                    if spins {
                        // A lime flash behind the card as it lands on its face.
                        Circle().fill(Theme.lime).frame(width: 260, height: 260).blur(radius: 60)
                            .scaleEffect(landed ? 1.25 : 0.4)
                            .opacity(landed ? 0 : (flipped ? 0.55 : 0))
                            .allowsHitTesting(false)
                        SpinningCard(angle: spin, front: art, back: CardBack().frame(width: 260, height: 363).shadow(color: .black.opacity(0.6), radius: 30, y: 16))
                            .scaleEffect(shown ? 1 : 0.55)
                            .opacity(shown ? 1 : 0)
                            .offset(y: shown ? 0 : 50)
                    } else {
                        art
                            .rotation3DEffect(.degrees(flipped || reduceMotion ? 0 : 100), axis: (x: 0, y: 1, z: 0), perspective: 0.6)
                            .scaleEffect(flipped || reduceMotion ? 1 : 0.7)
                            .opacity(flipped || reduceMotion ? 1 : 0)
                            .offset(y: event.pulled && !flipped && !reduceMotion ? 60 : 0)
                        if event.pulled && !reduceMotion { PackWrapper(product: event.product, shaking: shaking, torn: torn) }
                    }
                }

                if event.pulled {
                    pullFigures
                } else {
                VStack(spacing: 8) {
                    MonoLabel(text: "Added to your collection")
                    (Text(event.quantity > 1 ? "\(Int(event.quantity)) × " : "").foregroundColor(Theme.muted) + Text(event.product.name))
                        .font(.geist(22, .semibold)).multilineTextAlignment(.center).lineLimit(3)
                }
                .padding(.top, 20)
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
                .padding(.top, 14)
                .opacity(risen ? 1 : 0).offset(y: risen ? 0 : 12)
                }

                Spacer(minLength: 20)
                // At the bottom of the screen: the main action full width; Share (for a pull) and
                // Done side by side under it, so every label fits on one line.
                VStack(spacing: 12) {
                    Button(action: onOpen) { Label("View product", systemImage: "arrow.right").labelStyle(.titleAndIcon).lineLimit(1) }
                        .buttonStyle(Button3D(kind: .lime, height: 50))
                    HStack(spacing: 10) {
                        if event.pulled {
                            ShareLink(item: shareImage, preview: SharePreview("My pull", image: shareImage)) {
                                Label("Share", systemImage: "square.and.arrow.up").lineLimit(1)
                            }
                            .buttonStyle(Button3D(kind: .dark, height: 48))
                        }
                        Button("Done", action: onDone).buttonStyle(Button3D(kind: .dark, height: 48))
                    }
                }
                .opacity(risen ? 1 : 0)
            }
            .padding(.horizontal, 24)
            .padding(.bottom, 12)
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
        let shape = RoundedRectangle(cornerRadius: slab ? 18 : (isCard ? 13 : 24), style: .continuous)
        return Group {
            if slab, let id = event.identity {
                // A graded add shows in its slab (with its Pristine mark and bumper, if any), at the
                // card page's size and drifting like it.
                HoloCard(foil: false, textured: false, cornerRadius: 18) {
                    HoldingArt(product: event.product, identity: id, caption: false).frame(width: 250, height: 400)
                }
                .drifting()
            } else if isCard {
                // The card at the card page's size, its biggest picture, drifting like the card page.
                HoloCard(foil: false, textured: false, cornerRadius: 12) {
                    ProductImage(product: event.product, cornerRadius: 13, large: true).frame(width: 260, height: 363)
                }
                .drifting()
                .environment(\.imageMaxPixel, nil)
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
        .padding(.top, 18)
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
        if spins {
            playSpin()
            return
        }
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
    /// A raw card: its back scales in (a pull holds there a moment longer), then it spins
    /// a few turns, slowing, and lands on its face with a lime flash and a thump; the foil band
    /// sweeps and the figures rise.
    fileprivate func playSpin() {
        let value = max(after - event.before, 0)
        shownValue = event.pulled ? after : event.before
        if Self.holdBack {
            spin = 160; shown = true
            return
        }
        // A pull gets a longer build: more turns after a moment longer on its back.
        let wait = event.pulled ? 0.9 : 0.35
        let turn = event.pulled ? 1.9 : 1.5
        spin = event.pulled ? 1260 : 900
        withAnimation(.spring(response: 0.45, dampingFraction: 0.75)) { shown = true }
        withAnimation(.timingCurve(0.3, 0.6, 0.15, 1, duration: turn).delay(wait)) { spin = 0 }
        // The card faces you about 70% of the way through the turn (the rest is it settling).
        let land = wait + turn * 0.72
        Task { @MainActor in
            try? await Task.sleep(for: .seconds(land))
            // The flash and the thump (the haptic follows `flipped`).
            withAnimation(.easeOut(duration: 0.12)) { flipped = true }
            try? await Task.sleep(for: .seconds(0.12))
            withAnimation(.easeOut(duration: 0.8)) { landed = true }
            withAnimation(.easeInOut(duration: 1.1).delay(0.05)) { sweep = true }
            withAnimation(.easeOut(duration: 0.5).delay(0.1)) { risen = true }
            if event.pulled {
                withAnimation(.timingCurve(0.16, 1, 0.3, 1, duration: 1.8).delay(0.2)) { pullValue = value }
            } else {
                withAnimation(.timingCurve(0.16, 1, 0.3, 1, duration: 1.6).delay(0.2)) { shownValue = after }
            }
        }
    }

    /// The pull: the wrapper tears open, the card rises out and flips in with its foil sweep,
    /// then its value counts up from $0.
    fileprivate func playPull() {
        let value = max(after - event.before, 0)
        shownValue = after
        guard !reduceMotion else {
            torn = true; flipped = true; risen = true; pullValue = value
            return
        }
        // The pack sits a moment, shakes, tears; then the card rises out.
        withAnimation(.easeInOut(duration: 0.07).repeatCount(6, autoreverses: true).delay(0.55)) { shaking = true }
        withAnimation(.easeIn(duration: 0.45).delay(1.0)) { torn = true }
        withAnimation(.spring(response: 0.7, dampingFraction: 0.7).delay(1.3)) { flipped = true }
        withAnimation(.easeInOut(duration: 1.1).delay(1.7)) { sweep = true }
        withAnimation(.easeOut(duration: 0.5).delay(1.75)) { risen = true }
        withAnimation(.timingCurve(0.16, 1, 0.3, 1, duration: 1.8).delay(1.85)) { pullValue = value }
    }
}

/// A card turning about its upright axis: its face when the face is toward you, its back
/// (mirrored back the right way round) when it's turned away. Only the angle animates; both sides
/// stay built, so the picture isn't reloaded at each turn.
private struct SpinningCard<Front: View, Back: View>: View, Animatable {
    var angle: Double
    var front: Front
    var back: Back
    var animatableData: Double {
        get { angle }
        set { angle = newValue }
    }

    var body: some View {
        let a = abs(angle.truncatingRemainder(dividingBy: 360))
        let showsBack = a > 90 && a < 270
        ZStack {
            front.opacity(showsBack ? 0 : 1)
            back.scaleEffect(x: -1, y: 1).opacity(showsBack ? 1 : 0)
        }
        .rotation3DEffect(.degrees(angle), axis: (x: 0, y: 1, z: 0), perspective: 0.45)
    }
}

/// The back of a card, in Lucent's own look: a deep blue swirl in a dark border, a lime orb in
/// the middle and the name above and (upside down) below it. Drawn once into a single layer.
struct CardBack: View {
    var body: some View {
        let shape = RoundedRectangle(cornerRadius: 13, style: .continuous)
        let inner = RoundedRectangle(cornerRadius: 8, style: .continuous)
        let deep = Color(red: 0.05, green: 0.08, blue: 0.24)
        let mid = Color(red: 0.12, green: 0.24, blue: 0.62)
        ZStack {
            shape.fill(Color(red: 0.04, green: 0.06, blue: 0.16))
            ZStack {
                AngularGradient(colors: [deep, mid, deep, Color(red: 0.2, green: 0.36, blue: 0.85), deep, mid, deep], center: .center)
                // The swirl: soft white bands turning about the middle.
                ForEach(0..<5, id: \.self) { i in
                    Ellipse()
                        .stroke(Color.white.opacity(0.13 - Double(i) * 0.015), lineWidth: 16 - CGFloat(i) * 2)
                        .frame(width: 300 - CGFloat(i) * 40, height: 130 - CGFloat(i) * 14)
                        .rotationEffect(.degrees(Double(i) * 34 - 25))
                }
                .blur(radius: 5)
                // The orb: lime above, dark below, a ring round its middle.
                ZStack {
                    Circle().fill(RadialGradient(colors: [Color(red: 0.93, green: 1, blue: 0.6), Theme.lime, Color(red: 0.45, green: 0.6, blue: 0.05)],
                                                 center: UnitPoint(x: 0.38, y: 0.3), startRadius: 4, endRadius: 70))
                    Rectangle().fill(Color(red: 0.07, green: 0.08, blue: 0.1)).frame(height: 12)
                    Circle().fill(Color(red: 0.07, green: 0.08, blue: 0.1)).frame(width: 40, height: 40)
                    Circle().fill(Color.white.opacity(0.9)).frame(width: 22, height: 22)
                }
                .frame(width: 104, height: 104)
                .clipShape(Circle())
                .shadow(color: Theme.lime.opacity(0.5), radius: 18)
                VStack {
                    Text("Lucent").font(.display(44)).tracking(-1.4).foregroundStyle(Theme.lime)
                    Spacer()
                    Text("Lucent").font(.display(44)).tracking(-1.4).foregroundStyle(Theme.lime).rotationEffect(.degrees(180))
                }
                .shadow(color: .black.opacity(0.5), radius: 0, x: 0, y: 3)
                .padding(.vertical, 26)
            }
            .clipShape(inner)
            .padding(12)
        }
        .clipShape(shape)
        .overlay(shape.strokeBorder(Color.white.opacity(0.14)))
        .drawingGroup()
        .accessibilityHidden(true)
    }
}

/// A booster pack over the card, as real as we can draw it: a crimped seal top and bottom, a
/// metallic foil body with a light stripe across it, the pulled card's own art (softly blurred)
/// as the pack's artwork, and its printing. It shakes, the top seal tears off and flies away, and
/// the body drops so the card can rise out.
private struct PackWrapper: View {
    var product: Product
    var shaking: Bool
    var torn: Bool

    private static let width: CGFloat = 214
    private static let foil = LinearGradient(
        stops: [
            .init(color: Color(hex: 0x2B2F45), location: 0),
            .init(color: Color(hex: 0x8C93B8), location: 0.18),
            .init(color: Color(hex: 0x3A3F5C), location: 0.4),
            .init(color: Color(hex: 0xB9BEDB), location: 0.62),
            .init(color: Color(hex: 0x2E3350), location: 1),
        ],
        startPoint: .topLeading, endPoint: .bottomTrailing
    )

    var body: some View {
        VStack(spacing: 0) {
            // The top seal: torn off along the dotted line.
            CrimpBand(teeth: 16, edge: .top)
                .fill(Self.foil)
                .overlay(CrimpLines().stroke(Color.black.opacity(0.25), lineWidth: 0.6).padding(.horizontal, 6).padding(.vertical, 6))
                .frame(width: Self.width, height: 26)
                .rotationEffect(.degrees(torn ? -16 : 0), anchor: .trailing)
                .offset(x: torn ? 50 : 0, y: torn ? -170 : 0)
                .opacity(torn ? 0 : 1)
            // The body: art window, printing and foil.
            ZStack {
                Rectangle().fill(Self.foil)
                // The card's own art, soft, as the pack's artwork.
                ProductImage(product: product, cornerRadius: 0)
                    .scaledToFill()
                    .frame(width: Self.width - 22, height: 196)
                    .blur(radius: 5)
                    .saturation(1.3)
                    .opacity(0.8)
                    .clipShape(RoundedRectangle(cornerRadius: 10, style: .continuous))
                    .overlay(RoundedRectangle(cornerRadius: 10, style: .continuous).strokeBorder(Color.white.opacity(0.35), lineWidth: 1))
                    .offset(y: -18)
                VStack(spacing: 2) {
                    Spacer()
                    Text("BOOSTER PACK").font(.geist(13, .bold)).tracking(2.4)
                    Text("10 ADDITIONAL CARDS").font(.mono(8)).tracking(1.2).opacity(0.8)
                }
                .foregroundStyle(.white)
                .shadow(color: .black.opacity(0.5), radius: 2, y: 1)
                .padding(.bottom, 14)
                // A light stripe across the foil.
                LinearGradient(colors: [.clear, .white.opacity(0.45), .clear], startPoint: .leading, endPoint: .trailing)
                    .frame(width: 46)
                    .rotationEffect(.degrees(18))
                    .offset(x: shaking ? 70 : -70)
                    .blendMode(.plusLighter)
            }
            .frame(width: Self.width, height: 270)
            .clipped()
            // The bottom seal.
            CrimpBand(teeth: 16, edge: .bottom)
                .fill(Self.foil)
                .overlay(CrimpLines().stroke(Color.black.opacity(0.25), lineWidth: 0.6).padding(.horizontal, 6).padding(.vertical, 6))
                .frame(width: Self.width, height: 22)
        }
        .compositingGroup()
        .shadow(color: .black.opacity(0.55), radius: 24, y: 14)
        .rotationEffect(.degrees(shaking && !torn ? 2.5 : 0))
        .offset(y: torn ? 240 : 0)
        .opacity(torn ? 0 : 1)
        .allowsHitTesting(false)
        .accessibilityHidden(true)
    }
}

/// A seal strip with a zigzag (crimped) outer edge.
private struct CrimpBand: Shape {
    var teeth: Int
    var edge: VerticalEdge

    func path(in r: CGRect) -> Path {
        var p = Path()
        let step = r.width / CGFloat(teeth)
        let depth: CGFloat = 5
        if edge == .top {
            p.move(to: CGPoint(x: r.minX, y: r.maxY))
            p.addLine(to: CGPoint(x: r.minX, y: r.minY + depth))
            for i in 0 ..< teeth {
                let x = r.minX + CGFloat(i) * step
                p.addLine(to: CGPoint(x: x + step / 2, y: r.minY))
                p.addLine(to: CGPoint(x: x + step, y: r.minY + depth))
            }
            p.addLine(to: CGPoint(x: r.maxX, y: r.maxY))
        } else {
            p.move(to: CGPoint(x: r.minX, y: r.minY))
            p.addLine(to: CGPoint(x: r.maxX, y: r.minY))
            p.addLine(to: CGPoint(x: r.maxX, y: r.maxY - depth))
            for i in 0 ..< teeth {
                let x = r.maxX - CGFloat(i) * step
                p.addLine(to: CGPoint(x: x - step / 2, y: r.maxY))
                p.addLine(to: CGPoint(x: x - step, y: r.maxY - depth))
            }
            p.addLine(to: CGPoint(x: r.minX, y: r.minY))
        }
        p.closeSubpath()
        return p
    }
}

/// The fine pressed lines of a crimped seal.
private struct CrimpLines: Shape {
    func path(in r: CGRect) -> Path {
        var p = Path()
        var x = r.minX
        while x <= r.maxX {
            p.move(to: CGPoint(x: x, y: r.minY))
            p.addLine(to: CGPoint(x: x, y: r.maxY))
            x += 4
        }
        return p
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
