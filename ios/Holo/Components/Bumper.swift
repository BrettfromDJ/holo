import SwiftUI

/// Bumper guards: the colored frames collectors snap around slabs, the same set as the website
/// (`src/lib/bumpers.ts`). Chosen per slab and saved in user_state "slab-bumpers".
struct Bumper: Identifiable, Hashable {
    enum Kind { case glitter, solid }
    var id: String
    var name: String
    var kind: Kind
    var colors: [Color]

    static func solid(_ id: String, _ name: String, _ hex: UInt32) -> Bumper {
        let c = Color(hex: hex)
        // A soft top-lit gradient so it reads as molded plastic, not a flat color.
        return Bumper(id: id, name: name, kind: .solid, colors: [c.mix(.white, 0.18), c, c.mix(.black, 0.2)])
    }

    static func glitter(_ id: String, _ name: String, _ hexes: [UInt32]) -> Bumper {
        Bumper(id: id, name: name, kind: .glitter, colors: hexes.map { Color(hex: $0) })
    }

    static let all: [Bumper] = [
        .glitter("rainbow", "Rainbow glitter", [0xB56CF0, 0xF06CC4, 0xFF5F6D, 0xFF8A3D]),
        .glitter("aurora", "Aurora glitter", [0x7B5CFF, 0x3FA9FF, 0x2ED3A1, 0xB6F05A]),
        .glitter("sunset", "Sunset glitter", [0xFF6A88, 0xFF8A3D, 0xFFD23F]),
        .glitter("ocean", "Ocean glitter", [0x2C5CFF, 0x23B5FF, 0x5EF0E0]),
        .glitter("cotton-candy", "Cotton candy glitter", [0xFF9AD5, 0xC9A6FF, 0x8FD3FF]),
        .glitter("galaxy", "Galaxy glitter", [0x1B1446, 0x4B2A8F, 0xC04FD1]),
        .solid("red", "Red", 0xE5302F),
        .solid("orange", "Orange", 0xFF7A1A),
        .solid("yellow", "Yellow", 0xFFD21F),
        .solid("green", "Green", 0x2CC84D),
        .solid("mint", "Mint", 0x4FE0B0),
        .solid("blue", "Blue", 0x36A6F0),
        .solid("navy", "Navy", 0x1F2F9E),
        .solid("purple", "Purple", 0x9A4BE0),
        .solid("pink", "Pink", 0xF05BBD),
        .solid("black", "Black", 0x1C1C1E),
        .solid("white", "White", 0xF4F4F6),
    ]

    static func byId(_ id: String?) -> Bumper? { id.flatMap { id in all.first { $0.id == id } } }

    var fill: LinearGradient {
        kind == .solid
            ? LinearGradient(colors: colors, startPoint: UnitPoint(x: 0.3, y: 0), endPoint: UnitPoint(x: 0.7, y: 1))
            : LinearGradient(colors: colors, startPoint: .top, endPoint: .bottom)
    }
}

private extension Color {
    /// This color blended toward another by `amount` (0…1).
    func mix(_ other: Color, _ amount: Double) -> Color {
        let a = UIColor(self).cgColor.components ?? [0, 0, 0, 1]
        let b = UIColor(other).cgColor.components ?? [0, 0, 0, 1]
        func ch(_ i: Int) -> Double {
            let x = Double(a.count > 2 ? a[i] : a[0])
            let y = Double(b.count > 2 ? b[i] : b[0])
            return x + (y - x) * amount
        }
        return Color(red: ch(0), green: ch(1), blue: ch(2))
    }
}

/// The bumper drawn around a slab: molded plastic with a lit top and a lip the slab sits in;
/// glitter bumpers get fine bright specks. `u` is 1% of the width.
struct BumperFrame: View {
    var bumper: Bumper
    var u: CGFloat

    var body: some View {
        let outer = RoundedRectangle(cornerRadius: 10 * u, style: .continuous)
        ZStack {
            outer.fill(bumper.fill)
                .opacity(bumper.kind == .glitter ? 0.94 : 1)
            if bumper.kind == .glitter {
                GlitterSpecks().clipShape(outer).blendMode(.screen)
            }
            // Lit top edge and a shaded base, like light on plastic.
            outer.strokeBorder(LinearGradient(colors: [.white.opacity(0.45), .clear, .black.opacity(0.3)], startPoint: .top, endPoint: .bottom), lineWidth: 1.4 * u)
            // The lip the slab sits in.
            RoundedRectangle(cornerRadius: 7.5 * u, style: .continuous)
                .strokeBorder(.black.opacity(0.28), lineWidth: 0.6 * u)
                .padding(4.2 * u)
        }
        .shadow(color: .black.opacity(0.55), radius: 5 * u, y: 3 * u)
    }
}

/// Fixed, sparse white specks (drawn once, not animated).
private struct GlitterSpecks: View {
    var body: some View {
        Canvas { ctx, size in
            var seed: UInt64 = 0x9E3779B97F4A7C15
            func next() -> Double {
                seed = seed &* 6364136223846793005 &+ 1442695040888963407
                return Double(seed >> 33) / Double(UInt64(1) << 31)
            }
            let count = Int(size.width * size.height / 90)
            for _ in 0..<count {
                let x = next() * size.width, y = next() * size.height, r = 0.4 + next() * 0.9
                ctx.fill(Path(ellipseIn: CGRect(x: x, y: y, width: r, height: r)), with: .color(.white.opacity(0.35 + next() * 0.55)))
            }
        }
        .allowsHitTesting(false)
    }
}
