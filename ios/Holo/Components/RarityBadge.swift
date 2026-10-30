import SwiftUI

/// A card's rarity as a pill styled by how special it is: plain for commons, silver for rares,
/// gold for ultra and double rares, teal for illustration rares, holographic for special
/// illustration rares, solid gold for hyper and secret rares, violet for shiny, magenta for
/// ACE SPEC, lime for promos. The rarest ones catch the light now and then.
struct RarityBadge: View {
    var rarity: String

    enum Tier {
        case common, rare, ultra, illustration, specialIllustration, gold, shiny, aceSpec, promo, amazing
    }

    static func tier(_ rarity: String) -> Tier {
        let r = rarity.lowercased()
        if r.contains("special illustration") || r.contains("special art") { return .specialIllustration }
        if r.contains("illustration") { return .illustration }
        if r.contains("hyper") || r.contains("secret") || r.contains("gold") || r.contains("rainbow") { return .gold }
        if r.contains("shiny") { return .shiny }
        if r.contains("ace spec") { return .aceSpec }
        if r.contains("amazing") || r.contains("radiant") { return .amazing }
        if r.contains("ultra") || r.contains("double") || r.contains("full art") || r.contains("vmax") || r.contains("vstar") { return .ultra }
        if r.contains("promo") { return .promo }
        if r.contains("rare") || r.contains("holo") { return .rare }
        return .common
    }

    private var tier: Tier { Self.tier(rarity) }

    var body: some View {
        let shape = Capsule()
        Text(rarity)
            .font(.geist(12, tier == .common ? .medium : .semibold))
            .lineLimit(1)
            .foregroundStyle(textColor)
            .padding(.horizontal, 10)
            .frame(height: 24)
            .background(shape.fill(fill))
            .overlay(shape.strokeBorder(border, lineWidth: tier == .common || tier == .rare ? 1 : 1.2))
            .overlay {
                if shines { Sheen(strength: 0.55).clipShape(shape) }
            }
            .shadow(color: glow.opacity(0.45), radius: glowRadius)
    }

    private var shines: Bool { [.specialIllustration, .gold, .shiny, .amazing, .ultra].contains(tier) }

    private static let gold = [Color(hex: 0xFFE7A3), Color(hex: 0xE8B64C), Color(hex: 0xB8862B), Color(hex: 0xF7D77E)]
    private static let holo = [Color(hex: 0xFF8AD8), Color(hex: 0xFFD36E), Color(hex: 0x9CFF8A), Color(hex: 0x7AD8FF), Color(hex: 0xB79CFF), Color(hex: 0xFF8AD8)]

    private var fill: AnyShapeStyle {
        switch tier {
        case .common: return AnyShapeStyle(Color.clear)
        case .rare: return AnyShapeStyle(Color.white.opacity(0.06))
        case .ultra: return AnyShapeStyle(LinearGradient(colors: [Color(hex: 0xE8B64C).opacity(0.22), Color(hex: 0xE8B64C).opacity(0.08)], startPoint: .top, endPoint: .bottom))
        case .illustration: return AnyShapeStyle(LinearGradient(colors: [Color(hex: 0x3EE8C5).opacity(0.24), Color(hex: 0x4A72FF).opacity(0.2)], startPoint: .leading, endPoint: .trailing))
        case .specialIllustration: return AnyShapeStyle(LinearGradient(colors: Self.holo, startPoint: .leading, endPoint: .trailing))
        case .gold: return AnyShapeStyle(LinearGradient(colors: Self.gold, startPoint: .topLeading, endPoint: .bottomTrailing))
        case .shiny: return AnyShapeStyle(LinearGradient(colors: [Color(hex: 0x8B5CFF), Color(hex: 0xFF5CC8)], startPoint: .leading, endPoint: .trailing))
        case .aceSpec: return AnyShapeStyle(LinearGradient(colors: [Color(hex: 0xFF2E9A), Color(hex: 0x9B2EFF)], startPoint: .leading, endPoint: .trailing))
        case .promo: return AnyShapeStyle(Theme.lime.opacity(0.12))
        case .amazing: return AnyShapeStyle(Color.black.opacity(0.4))
        }
    }

    private var border: AnyShapeStyle {
        switch tier {
        case .common: return AnyShapeStyle(Theme.borderStrong)
        case .rare: return AnyShapeStyle(LinearGradient(colors: [.white.opacity(0.55), .white.opacity(0.18)], startPoint: .top, endPoint: .bottom))
        case .ultra: return AnyShapeStyle(LinearGradient(colors: Self.gold, startPoint: .leading, endPoint: .trailing))
        case .illustration: return AnyShapeStyle(LinearGradient(colors: [Color(hex: 0x3EE8C5), Color(hex: 0x4A72FF)], startPoint: .leading, endPoint: .trailing))
        case .specialIllustration, .gold, .shiny, .aceSpec: return AnyShapeStyle(Color.white.opacity(0.45))
        case .promo: return AnyShapeStyle(Theme.lime.opacity(0.6))
        case .amazing: return AnyShapeStyle(LinearGradient(colors: Self.holo, startPoint: .leading, endPoint: .trailing))
        }
    }

    private var textColor: Color {
        switch tier {
        case .common: return Theme.muted
        case .rare: return .white
        case .ultra: return Color(hex: 0xF7D77E)
        case .illustration: return Color(hex: 0x9DF5E2)
        case .specialIllustration, .gold: return Theme.ink
        case .shiny, .aceSpec, .amazing: return .white
        case .promo: return Theme.lime
        }
    }

    private var glow: Color {
        switch tier {
        case .specialIllustration: return Color(hex: 0xFF8AD8)
        case .gold, .ultra: return Color(hex: 0xE8B64C)
        case .shiny: return Color(hex: 0x8B5CFF)
        case .aceSpec: return Color(hex: 0xFF2E9A)
        case .illustration: return Color(hex: 0x3EE8C5)
        default: return .clear
        }
    }

    private var glowRadius: CGFloat {
        switch tier {
        case .specialIllustration, .gold, .shiny, .aceSpec: return 8
        case .ultra, .illustration: return 5
        default: return 0
        }
    }
}
