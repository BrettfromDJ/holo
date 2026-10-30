import SwiftUI

/// Holo's palette, matching the web app's dark theme.
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
