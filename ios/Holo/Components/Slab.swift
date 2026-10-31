import SwiftUI

/// A grading slab drawn to scale with its own width, ported from the website: a thick clear
/// case with a lit edge and glare, the grader's printed label (PSA's red-framed label with its
/// logo tab, or the others' cream stock with an accent bar), and the card in a recessed window.
/// It keeps the 5:8 shape of a real slab and fits itself inside whatever space it's given.
struct Slab: View {
    var product: Product?
    var company: String
    var grade: String
    /// The bumper guard around it, if one is chosen (the slab then sits inside it).
    var bumper: Bumper? = nil

    var body: some View {
        Color.clear
            .aspectRatio(5.0 / 8.0, contentMode: .fit)
            .overlay {
                GeometryReader { geo in
                    let u = geo.size.width / 100
                    ZStack {
                        if let bumper { BumperFrame(bumper: bumper, u: u) }
                        SlabDrawing(product: product, company: company, grade: grade, u: bumper == nil ? u : u * 0.9)
                            .padding(bumper == nil ? 0 : 5 * u)
                    }
                    .frame(width: geo.size.width, height: geo.size.height)
                }
            }
            .accessibilityElement(children: .ignore)
            .accessibilityLabel("\(product?.name ?? "Card"), \(company) \(grade)")
    }
}

/// The slab at one size; `u` is 1% of its width (the website's cqw).
private struct SlabDrawing: View {
    var product: Product?
    var company: String
    var grade: String
    var u: CGFloat

    private var tiny: Bool { u < 0.9 }
    private var isPSA: Bool { company.uppercased() == "PSA" }

    var body: some View {
        let caseShape = RoundedRectangle(cornerRadius: 7 * u, style: .continuous)
        ZStack {
            // The case: clear acrylic with a lit top edge and a darker base.
            caseShape
                .fill(LinearGradient(stops: [
                    .init(color: .white.opacity(0.26), location: 0),
                    .init(color: .white.opacity(0.08), location: 0.22),
                    .init(color: .white.opacity(0.04), location: 0.55),
                    .init(color: .white.opacity(0.14), location: 1),
                ], startPoint: UnitPoint(x: 0.2, y: 0), endPoint: UnitPoint(x: 0.8, y: 1)))
                .overlay(caseShape.strokeBorder(.white.opacity(0.22), lineWidth: 1))
                .overlay(alignment: .top) {
                    caseShape.stroke(.white.opacity(0.45), lineWidth: 1.5).mask(LinearGradient(colors: [.black, .clear], startPoint: .top, endPoint: UnitPoint(x: 0.5, y: 0.04)))
                }
                .background(caseShape.fill(Color(hex: 0x141416)))
                .shadow(color: .black.opacity(0.7), radius: 6 * u, y: 3 * u)
            // The inner step where the insert sits.
            RoundedRectangle(cornerRadius: 5 * u, style: .continuous)
                .strokeBorder(.white.opacity(0.1), lineWidth: 1)
                .padding(2.2 * u)

            VStack(spacing: (tiny ? 5 : 3.5) * u) {
                if isPSA { psaLabel } else { stockLabel }
                // Card window.
                ZStack {
                    RoundedRectangle(cornerRadius: 3 * u, style: .continuous)
                        .fill(LinearGradient(colors: [.black.opacity(0.45), .black.opacity(0.3)], startPoint: .top, endPoint: .bottom))
                        .overlay(RoundedRectangle(cornerRadius: 3 * u, style: .continuous).strokeBorder(.white.opacity(0.06), lineWidth: 1))
                    ProductImage(product: product, cornerRadius: 2 * u)
                        .padding(3.5 * u)
                }
            }
            .padding((tiny ? 6 : 4.5) * u)

            // Glare across the acrylic.
            LinearGradient(stops: [
                .init(color: .clear, location: 0.40),
                .init(color: .white.opacity(0.13), location: 0.47),
                .init(color: .white.opacity(0.04), location: 0.52),
                .init(color: .clear, location: 0.58),
            ], startPoint: UnitPoint(x: 0, y: 0.15), endPoint: UnitPoint(x: 1, y: 0.85))
            .clipShape(caseShape)
            .allowsHitTesting(false)
        }
    }

    // MARK: PSA

    private var psaLines: [String] {
        [product?.setName, product?.name, product?.rarity ?? (product?.isSealed == false ? "Holo" : nil)].compactMap { $0 }
    }

    private var psaLabel: some View {
        RoundedRectangle(cornerRadius: 1.8 * u, style: .continuous)
            .fill(LinearGradient(colors: [Color(hex: 0xE3262F), Color(hex: 0xC8141F)], startPoint: .top, endPoint: .bottom))
            .overlay {
                ZStack(alignment: .bottom) {
                    RoundedRectangle(cornerRadius: 0.7 * u)
                        .fill(LinearGradient(colors: [Color(hex: 0xFBFCFD), Color(hex: 0xEEF3F6)], startPoint: .top, endPoint: .bottom))
                    if !tiny {
                        HStack(alignment: .top, spacing: 2 * u) {
                            VStack(alignment: .leading, spacing: 0) {
                                ForEach(Array(psaLines.enumerated()), id: \.offset) { _, line in
                                    Text(line.uppercased()).lineLimit(1)
                                }
                                Spacer(minLength: 0)
                                Barcode(u: u).frame(width: 30 * u, height: 3.2 * u)
                            }
                            .frame(maxWidth: .infinity, alignment: .leading)
                            VStack(alignment: .trailing, spacing: 0) {
                                if let number = product?.number { Text("#" + (number.split(separator: "/").first.map(String.init) ?? number)) }
                                Text(Slab.descriptor(company: company, grade: grade))
                                Text(grade)
                                Spacer(minLength: 0)
                            }
                        }
                        .font(.geist(4.2 * u, .medium))
                        .foregroundStyle(Color(hex: 0x161616))
                        .padding(.horizontal, 2.4 * u)
                        .padding(.top, 1.4 * u)
                        .padding(.bottom, 1.2 * u)
                        .frame(maxHeight: .infinity, alignment: .top)
                        // The PSA logo, joined to the red trim below.
                        Text("PSA")
                            .font(.system(size: 3.8 * u, weight: .black).italic())
                            .tracking(-0.15 * u)
                            .foregroundStyle(Color(hex: 0x1D3F8F))
                            .frame(width: 11 * u, height: 5.8 * u)
                            .background(UnevenRoundedRectangle(topLeadingRadius: 0.6 * u, topTrailingRadius: 0.6 * u)
                                .fill(LinearGradient(colors: [Color(hex: 0xC9CED6), Color(hex: 0x9AA3AE)], startPoint: .top, endPoint: .bottom)))
                    }
                }
                .clipShape(RoundedRectangle(cornerRadius: 0.7 * u))
                .padding((tiny ? 1.6 : 1.5) * u)
            }
            .frame(height: (tiny ? 16 : 29) * u)
            .shadow(color: .black.opacity(0.35), radius: 0.75 * u, y: 0.5 * u)
    }

    // MARK: CGC, BGS, SGC and the rest

    private var accent: Color {
        switch company.uppercased() {
        case "BGS" where (Double(grade) ?? 0) >= 10: return Color(hex: 0xD9B45A)
        case "BGS": return Color(hex: 0x8A8F98)
        case "CGC": return Color(hex: 0x1D4F91)
        case "SGC", "TAG": return Color(hex: 0x111111)
        default: return Color(hex: 0x636366)
        }
    }

    private var blackLabel: Bool { company.uppercased() == "BGS" && (Double(grade) ?? 0) >= 10 }

    private var stockLabel: some View {
        let ink = blackLabel ? Color(hex: 0xF2E6C4) : Color(hex: 0x1A1A1A)
        let details = [product?.setName, product?.number.map { "#\($0)" }].compactMap { $0 }.joined(separator: " · ")
        return RoundedRectangle(cornerRadius: 2.4 * u, style: .continuous)
            .fill(blackLabel
                ? LinearGradient(colors: [Color(hex: 0x1C1C1E), Color(hex: 0x0C0C0D)], startPoint: .top, endPoint: .bottom)
                : LinearGradient(colors: [Color(hex: 0xFBFAF6), Color(hex: 0xEBE8DF)], startPoint: .top, endPoint: .bottom))
            .overlay(alignment: .top) { Rectangle().fill(accent).frame(height: (tiny ? 2.5 : 1.1) * u) }
            .overlay {
                if !tiny {
                    HStack(alignment: .center, spacing: 3 * u) {
                        VStack(alignment: .leading, spacing: 0) {
                            Text(company.uppercased()).font(.system(size: 6.4 * u, weight: .black)).foregroundStyle(accent)
                            Text((product?.name ?? "Card").uppercased()).font(.geist(3.3 * u, .bold)).lineLimit(1).padding(.top, 1.6 * u)
                            if !details.isEmpty { Text(details.uppercased()).font(.geist(2.8 * u, .medium)).lineLimit(1).opacity(0.6) }
                            Spacer(minLength: 0)
                            Barcode(u: u).frame(width: 40 * u, height: 3 * u).opacity(0.7)
                        }
                        .frame(maxWidth: .infinity, alignment: .leading)
                        VStack(alignment: .trailing, spacing: 1 * u) {
                            Text(Slab.descriptor(company: company, grade: grade)).font(.geist(2.9 * u, .bold)).opacity(0.75)
                            Text(grade).font(.system(size: 12 * u, weight: .black)).tracking(-0.4 * u)
                        }
                    }
                    .foregroundStyle(ink)
                    .padding(.horizontal, 4 * u)
                    .padding(.top, 3.4 * u)
                    .padding(.bottom, 2.6 * u)
                }
            }
            .clipShape(RoundedRectangle(cornerRadius: 2.4 * u, style: .continuous))
            .frame(height: (tiny ? 16 : 27) * u)
            .shadow(color: .black.opacity(0.35), radius: 0.75 * u, y: 0.5 * u)
    }
}

/// A printed barcode: thin and thick bars on a repeating pattern.
private struct Barcode: View {
    var u: CGFloat

    var body: some View {
        Canvas { ctx, size in
            // Bar widths and gaps in units of u, like the website's repeating pattern.
            let pattern: [(CGFloat, Bool)] = [(0.3, true), (0.3, false), (0.6, true), (0.3, false), (0.2, true), (0.6, false)]
            var x: CGFloat = 0
            var i = 0
            while x < size.width {
                let (w, bar) = pattern[i % pattern.count]
                if bar { ctx.fill(Path(CGRect(x: x, y: 0, width: w * u, height: size.height)), with: .color(Color(hex: 0x161616))) }
                x += w * u
                i += 1
            }
        }
    }
}

extension Slab {
    /// The words printed with the grade, e.g. "GEM MT" for a PSA 10.
    static func descriptor(company: String, grade: String) -> String {
        guard let n = Double(grade) else { return "" }
        if company.uppercased() == "PSA" {
            switch n {
            case 10...: return "GEM MT"
            case 9...: return "MINT"
            case 8...: return "NM-MT"
            case 7...: return "NM"
            case 6...: return "EX-MT"
            case 5...: return "EX"
            case 4...: return "VG-EX"
            case 3...: return "VG"
            case 2...: return "GOOD"
            default: return "POOR"
            }
        }
        switch n {
        case 10...: return "PRISTINE"
        case 9.5...: return "GEM MINT"
        case 9...: return "MINT"
        case 8.5...: return "NM-MT+"
        case 8...: return "NM-MT"
        default: return "NEAR MINT"
        }
    }
}
