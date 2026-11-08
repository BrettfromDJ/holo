import SwiftUI
import UIKit

/// The holo card: press and drag on it to tilt it any way you like, and the light, glare and
/// foil move across it as it leans; let go and it springs back flat. It doesn't move with the
/// phone and doesn't drift on its own. Printed cards get paper grain, a fine print pattern and
/// a bevelled edge; foil cards get rainbow foil in etched grooves with glitter.
struct HoloCard<Content: View>: View {
    var foil: Bool
    /// Paper grain and bevel (bare cards only; not slabs or sealed).
    var textured: Bool
    var cornerRadius: CGFloat
    /// The moving white glare. Off for sealed products, which have no shine.
    var showsGlare = true
    @ViewBuilder var content: Content
    /// A quick tap (not a tilt): set with `.onCardTap { }`.
    var tapAction: (() -> Void)? = nil
    /// Tilts slowly on its own with a band of light sweeping across (the card page): set with
    /// `.drifting()`. Holds while you touch it; Reduce Motion keeps it still.
    var drifts = false

    @Environment(\.accessibilityReduceMotion) private var reduceMotion
    @State private var touch: CGPoint?
    /// When the current touch began, to tell a tap from a press-and-tilt.
    @State private var downAt: Date?
    @State private var size: CGSize = .zero
    /// On screen and not under a sheet: the drift only runs then (otherwise the page never rests
    /// and every tap on it waits).
    @State private var onScreen = true

    var body: some View {
        Group {
            if drifts && !reduceMotion {
                // One clock: the slow tilt and the light's sweep. Paused while you hold it (the
                // same view throughout, so a drag is never interrupted).
                // 30 a second is plenty for a slow drift (it was every frame, up to 120).
                TimelineView(.animation(minimumInterval: 1.0 / 30, paused: touch != nil || !onScreen)) { context in
                    let c = context.date.timeIntervalSinceReferenceDate
                    let idle = CGPoint(x: cos(c * 0.45) * 0.545, y: -sin(c * 0.6) * 0.5)
                    card(lean: touch ?? idle, sweep: touch == nil ? sin(c * 0.6) : nil)
                }
            } else {
                // Still unless you're touching it: nothing redraws on its own.
                card(lean: reduceMotion ? .zero : (touch ?? .zero), sweep: nil)
            }
        }
        .sensoryFeedback(.impact(weight: .light), trigger: touch != nil) { _, touching in touching }
        .onVisibilityChange { visible in if visible != onScreen { onScreen = visible } }
    }

    /// Makes the card drift (tilt slowly, light sweeping across) until it's touched.
    func drifting() -> HoloCard {
        var copy = self
        copy.drifts = true
        return copy
    }

    private func card(lean: CGPoint, sweep: Double?) -> some View {
        let shape = RoundedRectangle(cornerRadius: cornerRadius, style: .continuous)
        let light = UnitPoint(x: 0.5 + lean.x * 0.45, y: 0.5 + lean.y * 0.45)
        let touching = touch != nil
        return content
            .overlay { if textured { texture(light: light) } }
            // The foil (rainbow and glitter) shows only while you tilt it, so at rest the art is clean.
            .overlay { if foil && touching { foilLayer(light: light, strength: 0.6) } }
            // While drifting, the sweeping band is the light (no glare washing over the art).
            .overlay { if showsGlare && (sweep == nil || touching) { glare(light: light).opacity(touching ? 1 : 0.5) } }
            .overlay { if let sweep { sweepBand(sweep) } }
            .clipShape(shape)
            .overlay {
                if textured {
                    shape.strokeBorder(LinearGradient(colors: [.white.opacity(0.28), .white.opacity(0.1), .black.opacity(0.25)], startPoint: .top, endPoint: .bottom), lineWidth: 1)
                }
            }
            .background(GeometryReader { geo in Color.clear.onAppear { size = geo.size }.onChange(of: geo.size) { _, s in size = s } })
            .rotation3DEffect(.degrees(Double(lean.x) * 22), axis: (x: 0, y: 1, z: 0), perspective: 0.45)
            .rotation3DEffect(.degrees(Double(-lean.y) * 18), axis: (x: 1, y: 0, z: 0), perspective: 0.45)
            .scaleEffect(touching ? 1.035 : 1)
            .animation(.spring(response: 0.3, dampingFraction: 0.7), value: touching)
            // A soft lime glow behind a drifting card (a still gradient, not a shadow).
            .background {
                if drifts {
                    // Fades to nothing within its own frame (just past the card), so nothing clips it.
                    RadialGradient(colors: [Theme.lime.opacity(0.22), Theme.lime.opacity(0.08), .clear], center: .center,
                                   startRadius: max(size.width, 1) * 0.25, endRadius: max(size.width, 1) * 0.5 + 28)
                        .padding(-30)
                        .allowsHitTesting(false)
                }
            }
            // The shadow falls away from the light.
            .background {
                // A soft contact shadow under the card's bottom edge: a radial gradient, not a
                // blur, since it moves every frame and a blur would be redrawn each time.
                GeometryReader { geo in
                    let w = geo.size.width
                    Ellipse()
                        .fill(RadialGradient(colors: [.black.opacity(0.55), .black.opacity(0.2), .clear],
                                             center: .center, startRadius: 0, endRadius: w * 0.5))
                        .frame(width: w * 0.95, height: w * 0.95)
                        .scaleEffect(x: 1, y: 0.18)
                        .position(x: w / 2, y: geo.size.height * 0.98)
                }
                .offset(x: -lean.x * 30, y: 18 - lean.y * 20)
            }
            .simultaneousGesture(
                DragGesture(minimumDistance: 0)
                    .onChanged { g in
                        if downAt == nil || g.translation == .zero { downAt = g.time }
                        guard size.width > 0 else { return }
                        // Follows the drag from wherever you start: drag right and it swings right.
                        touch = CGPoint(x: max(-1, min(1, g.translation.width / (size.width * 0.6))),
                                        y: max(-1, min(1, g.translation.height / (size.height * 0.6))))
                    }
                    .onEnded { g in
                        // A short touch that barely moved is a tap.
                        let quick = downAt.map { g.time.timeIntervalSince($0) < 0.35 } ?? false
                        downAt = nil
                        // Springs back flat, with the light sliding back to the middle.
                        withAnimation(reduceMotion ? nil : .spring(response: 0.45, dampingFraction: 0.6)) { touch = nil }
                        if quick, abs(g.translation.width) < 8, abs(g.translation.height) < 8, let tapAction { tapAction() }
                    }
            )
    }

    /// Runs `action` on a quick tap; pressing and dragging still tilts the card.
    func onCardTap(_ action: @escaping () -> Void) -> HoloCard {
        var copy = self
        copy.tapAction = action
        return copy
    }

    /// Paper grain, a fine print pattern and a soft sheen where the light is.
    private func texture(light: UnitPoint) -> some View {
        ZStack {
            RadialGradient(colors: [.white.opacity(0.16), .clear], center: light, startRadius: 0, endRadius: max(size.width, 1) * 0.9)
            Textures.image("grain").resizable(resizingMode: .tile).opacity(0.9)
            if foil {
                Textures.image("etch").resizable().opacity(0.28)
            }
        }
        .blendMode(.overlay)
        .opacity(0.4)
        .allowsHitTesting(false)
    }

    /// Rainbow foil showing only in the etched grooves, strongest around the light, with glitter.
    private func foilLayer(light: UnitPoint, strength: Double) -> some View {
        let hues: [Color] = [
            Color(hue: 0, saturation: 0.9, brightness: 1), Color(hue: 0.125, saturation: 0.95, brightness: 1),
            Color(hue: 0.33, saturation: 0.8, brightness: 0.95), Color(hue: 0.53, saturation: 0.9, brightness: 1),
            Color(hue: 0.72, saturation: 0.85, brightness: 1), Color(hue: 0.89, saturation: 0.9, brightness: 1),
            Color(hue: 0, saturation: 0.9, brightness: 1),
        ]
        let shift = CGFloat(light.x + light.y) - 1
        return ZStack {
            LinearGradient(colors: hues + hues, startPoint: UnitPoint(x: -0.5 + shift, y: -0.5 + shift), endPoint: UnitPoint(x: 1.5 + shift, y: 1.5 + shift))
                .mask(Textures.image("etch").resizable())
            Textures.image("glitter").resizable(resizingMode: .tile)
                .offset(x: (light.x - 0.5) * 30, y: (light.y - 0.5) * 30)
                .opacity(0.5)
        }
        .mask(RadialGradient(colors: [.black, .clear], center: light, startRadius: 0, endRadius: max(size.width, 1) * 0.75))
        .blendMode(.colorDodge)
        .opacity(strength)
        .allowsHitTesting(false)
    }

    /// The band of light sliding across a drifting card (`sweep` from -1 to 1).
    private func sweepBand(_ sweep: Double) -> some View {
        GeometryReader { geo in
            LinearGradient(colors: [.clear, .white.opacity(0.35), .clear], startPoint: .leading, endPoint: .trailing)
                .frame(width: geo.size.width * 0.52, height: geo.size.height * 1.4)
                .rotationEffect(.degrees(25))
                .position(x: geo.size.width / 2 + CGFloat(sweep) * geo.size.width * 0.7, y: geo.size.height / 2)
        }
        .blendMode(.plusLighter)
        .allowsHitTesting(false)
    }

    /// A spot of light plus a soft band, following the lean.
    private func glare(light: UnitPoint) -> some View {
        ZStack {
            RadialGradient(colors: [.white.opacity(0.38), .clear], center: light, startRadius: 0, endRadius: max(size.width, 1) * 0.6)
            LinearGradient(stops: [
                .init(color: .clear, location: 0.38),
                .init(color: .white.opacity(0.22), location: 0.47),
                .init(color: .white.opacity(0.08), location: 0.52),
                .init(color: .clear, location: 0.6),
            ], startPoint: UnitPoint(x: light.x - 0.9, y: 0), endPoint: UnitPoint(x: light.x + 0.9, y: 1))
        }
        .blendMode(.overlay)
        .allowsHitTesting(false)
    }
}

/// The bundled finish textures (Resources/Textures), loaded once.
enum Textures {
    private static var cache: [String: UIImage] = [:]

    static func image(_ name: String) -> Image {
        if let cached = cache[name] { return Image(uiImage: cached) }
        let image = UIImage(named: name) ?? Bundle.main.path(forResource: name, ofType: "png").flatMap(UIImage.init(contentsOfFile:)) ?? UIImage()
        cache[name] = image
        return Image(uiImage: image)
    }
}

extension Product {
    /// Foil and special-art cards get the etched foil, like the website's isFoilCard.
    var isFoil: Bool {
        guard !isSealed else { return false }
        let text = "\(rarity ?? "") \(name)"
        return Self.foilPattern?.firstMatch(in: text, range: NSRange(text.startIndex..., in: text)) != nil
    }

    /// Compiled once: tiles ask `isFoil` on every redraw.
    private static let foilPattern = try? NSRegularExpression(
        pattern: #"holo|foil|secret|illustration|full art|alternate|alt art|rainbow|gold|hyper|ultra|special|v(max|star)\b|\bex\b|\bgx\b|shiny|prism"#,
        options: [.caseInsensitive]
    )
}

