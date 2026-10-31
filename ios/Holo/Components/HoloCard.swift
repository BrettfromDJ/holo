import SwiftUI
import UIKit

/// The website's holo card: the card leans as the phone tilts (or under your finger), a soft
/// light and glare follow the lean, printed cards get paper grain, a fine print pattern and a
/// bevelled edge, and foil cards get rainbow foil in etched grooves with glitter, brightest
/// where the light is. With no tilt it drifts slowly on its own, like the website on a phone.
struct HoloCard<Content: View>: View {
    var foil: Bool
    /// Paper grain and bevel (bare cards only; not slabs or sealed).
    var textured: Bool
    var cornerRadius: CGFloat
    @ViewBuilder var content: Content

    @Environment(\.accessibilityReduceMotion) private var reduceMotion
    @State private var touch: CGPoint?
    @State private var size: CGSize = .zero
    @State private var onScreen = true

    var body: some View {
        TimelineView(.animation(minimumInterval: 1 / 30, paused: reduceMotion || !onScreen)) { context in
            let lean = lean(at: context.date)
            card(lean: lean)
        }
        .onVisibilityChange { onScreen = $0 }
        .onAppear { if !reduceMotion { Tilt.shared.start() } }
        .onDisappear { if !reduceMotion { Tilt.shared.stop() } }
        .sensoryFeedback(.impact(weight: .light), trigger: touch != nil) { _, touching in touching }
    }

    /// -1...1 each way: your finger, else the phone's tilt plus a slow drift.
    private func lean(at date: Date) -> CGPoint {
        if reduceMotion { return .zero }
        if let touch { return touch }
        let t = date.timeIntervalSinceReferenceDate / 9 * 2 * .pi
        let drift = CGPoint(x: sin(t) * 0.45, y: cos(t * 0.8) * 0.35)
        let tilt = Tilt.shared
        return CGPoint(x: max(-1, min(1, drift.x + tilt.x * 1.4)), y: max(-1, min(1, drift.y + tilt.y * 1.4)))
    }

    private func card(lean: CGPoint) -> some View {
        let shape = RoundedRectangle(cornerRadius: cornerRadius, style: .continuous)
        let light = UnitPoint(x: 0.5 + lean.x * 0.45, y: 0.5 + lean.y * 0.45)
        let touching = touch != nil
        return content
            .overlay { if textured { texture(light: light) } }
            .overlay { if foil { foilLayer(light: light, strength: touching ? 0.6 : 0.32) } }
            .overlay { glare(light: light).opacity(touching ? 1 : 0.5) }
            .clipShape(shape)
            .overlay {
                if textured {
                    shape.strokeBorder(LinearGradient(colors: [.white.opacity(0.28), .white.opacity(0.1), .black.opacity(0.25)], startPoint: .top, endPoint: .bottom), lineWidth: 1)
                }
            }
            .background(GeometryReader { geo in Color.clear.onAppear { size = geo.size }.onChange(of: geo.size) { _, s in size = s } })
            .rotation3DEffect(.degrees(Double(lean.x) * 11), axis: (x: 0, y: 1, z: 0), perspective: 0.55)
            .rotation3DEffect(.degrees(Double(-lean.y) * 9), axis: (x: 1, y: 0, z: 0), perspective: 0.55)
            .scaleEffect(touching ? 1.035 : 1)
            .animation(.spring(response: 0.3, dampingFraction: 0.7), value: touching)
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
                .offset(x: -lean.x * 22, y: 14 - lean.y * 16)
            }
            .simultaneousGesture(
                DragGesture(minimumDistance: 0)
                    .onChanged { g in
                        guard size.width > 0 else { return }
                        touch = CGPoint(x: max(-1, min(1, (g.location.x / size.width - 0.5) * 2)),
                                        y: max(-1, min(1, (g.location.y / size.height - 0.5) * 2)))
                    }
                    .onEnded { _ in touch = nil }
            )
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
        return text.range(of: #"holo|foil|secret|illustration|full art|alternate|alt art|rainbow|gold|hyper|ultra|special|v(max|star)\b|\bex\b|\bgx\b|shiny|prism"#,
                          options: [.regularExpression, .caseInsensitive]) != nil
    }
}

