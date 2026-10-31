import SwiftUI

/// The palette, matching the website's dark theme: lime accent and gains, pink losses.
enum Theme {
    static let background = Color(hex: 0x0B0B0C)
    static let surface = Color(hex: 0x131315)
    static let surface2 = Color(hex: 0x1A1A1D)
    static let surface3 = Color(hex: 0x232327)
    static let lime = Color(hex: 0xD4FF3A)
    static let ink = Color(hex: 0x0B0B0C)
    static let muted = Color(hex: 0x8E8E93)
    static let up = Color(hex: 0xD4FF3A)
    static let down = Color(hex: 0xFF3D7F)
    static let warn = Color(hex: 0xF5B84A)

    /// The iridescent sheen's colors, in order across a foil.
    static let holoColors: [Color] = [
        Color(hex: 0xC8B6FF), Color(hex: 0xA7C4FF), Color(hex: 0x9EF5E0), Color(hex: 0xFFC3E6), Color(hex: 0xFFEFB3),
    ]
    /// Accent fills (buttons, the +, selected chips, badges, headline numbers): solid lime.
    /// (Named `holo` from the brief iridescent look; a gradient type so it fills shapes and text.)
    static let holo = LinearGradient(colors: [Color(hex: 0xD4FF3A), Color(hex: 0xD4FF3A)], startPoint: .top, endPoint: .bottom)
    /// The shadow edge under 3D lime buttons, and their glow.
    static let holoEdge = Color(hex: 0x7A9200)
    static let holoGlow = Color(hex: 0xD4FF3A)
    static let violet = Color(hex: 0xD4FF3A)
    static let cyan = Color(hex: 0x2F5BFF)

    /// Gains in lime, losses in pink, nothing in gray. Only numbers get colored.
    static func tone(_ value: Double?) -> Color {
        guard let v = value, abs(v) > 0.000_1 else { return muted }
        return v > 0 ? up : down
    }
}

extension Color {
    init(hex: UInt32) {
        self.init(
            .sRGB,
            red: Double((hex >> 16) & 0xFF) / 255,
            green: Double((hex >> 8) & 0xFF) / 255,
            blue: Double(hex & 0xFF) / 255,
            opacity: 1
        )
    }
}

/// A card panel, styled like the website's (see Surface).
struct Panel<Content: View>: View {
    var padding: CGFloat = 20
    @ViewBuilder var content: Content

    var body: some View {
        content.surface(padding: padding)
    }
}

/// The lime call-to-action button (3D, like the website's).
struct LimeButtonStyle: ButtonStyle {
    func makeBody(configuration: Configuration) -> some View {
        Button3D(kind: .lime).makeBody(configuration: configuration)
    }
}
