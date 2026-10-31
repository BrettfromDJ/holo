import SwiftUI

/// Lucent's palette: the dark theme with iridescent accents (lavender, periwinkle, pearl mint,
/// pink, butter), like a holo foil catching light.
enum Theme {
    static let background = Color(hex: 0x0B0B0C)
    static let surface = Color(hex: 0x131315)
    static let surface2 = Color(hex: 0x1A1A1D)
    static let surface3 = Color(hex: 0x232327)
    /// The accent's solid form: pearl mint, the iridescent sheen's brightest note. (Named `lime`
    /// from before the Lucent rebrand.) Big fills use `holo`, the full iridescent gradient.
    static let lime = Color(hex: 0x9EF5E0)
    static let ink = Color(hex: 0x0B0B0C)
    static let muted = Color(hex: 0x8E8E93)
    /// Gains: mint.
    static let up = Color(hex: 0x86F2CF)
    static let down = Color(hex: 0xFF3D7F)
    static let warn = Color(hex: 0xF5B84A)

    /// The iridescent sheen's colors, in order across a foil.
    static let holoColors: [Color] = [
        Color(hex: 0xC8B6FF), Color(hex: 0xA7C4FF), Color(hex: 0x9EF5E0), Color(hex: 0xFFC3E6), Color(hex: 0xFFEFB3),
    ]
    /// Accent fills (buttons, the +, selected chips, badges, headline numbers): a soft pearl
    /// white, like the glow cards' white controls. (Was the iridescent gradient; the name stayed.)
    static let holo = LinearGradient(colors: [Color(hex: 0xFFFFFF), Color(hex: 0xE4E4EA)], startPoint: .top, endPoint: .bottom)
    /// The shadow edge under 3D accent buttons, and their glow.
    static let holoEdge = Color(hex: 0x8A8A92)
    static let holoGlow = Color.white.opacity(0.35)
    static let violet = Color(hex: 0x8B6CFF)
    static let cyan = Color(hex: 0x5FE3E8)

    /// Gains in mint, losses in pink, nothing in gray. Only numbers get colored.
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
