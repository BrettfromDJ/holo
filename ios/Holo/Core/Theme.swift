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
    /// The iridescent gradient for accent fills: buttons, the +, selected chips, badges.
    static let holo = LinearGradient(colors: holoColors, startPoint: .topLeading, endPoint: .bottomTrailing)
    /// The shadow edge under 3D iridescent buttons, and their glow.
    static let holoEdge = Color(hex: 0x6A62B0)
    static let holoGlow = Color(hex: 0xB7A6FF)
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
