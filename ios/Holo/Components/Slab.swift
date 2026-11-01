import SwiftUI

/// A grading slab drawn to scale with its own width, ported from the website: a thick clear
/// case with a lit edge and glare, the grader's printed label (PSA's red-framed label with its
/// logo tab, CGC's black frame with its silver panel (or a Pristine 10's cream panel and gold
/// badge), or the others' cream stock with an accent bar), and the card in a recessed window.
/// It keeps the 5:8 shape of a real slab and fits itself inside whatever space it's given.
struct Slab: View {
    var product: Product?
    var company: String
    var grade: String
    /// The bumper guard around it, if one is chosen (the slab then sits inside it).
    var bumper: Bumper? = nil
    /// The cert number printed on a CGC label, if one is saved ("slab-certs").
    var cert: String? = nil
    /// Marked Pristine ("slab-pristine"); only a CGC 10 shows it.
    var pristine: Bool = false

    private var isPristine: Bool { pristine && Slab.isCGCTen(company: company, grade: grade) }
    private var gradeLabel: String { isPristine ? "CGC Pristine 10" : company + " " + grade }

    var body: some View {
        Color.clear
            .aspectRatio(5.0 / 8.0, contentMode: .fit)
            .overlay {
                GeometryReader { geo in
                    let u = geo.size.width / 100
                    ZStack {
                        if let bumper { BumperFrame(bumper: bumper, u: u) }
                        SlabDrawing(product: product, company: company, grade: grade, cert: cert, pristine: isPristine, u: bumper == nil ? u : u * 0.9)
                            .padding(bumper == nil ? 0 : 5 * u)
                    }
                    .frame(width: geo.size.width, height: geo.size.height)
                }
            }
            .accessibilityElement(children: .ignore)
            .accessibilityLabel("\(product?.name ?? "Card"), \(gradeLabel)")
    }
}

/// The slab at one size; `u` is 1% of its width (the website's cqw).
private struct SlabDrawing: View {
    var product: Product?
    var company: String
    var grade: String
    var cert: String?
    /// Already checked to be a CGC 10.
    var pristine: Bool
    var u: CGFloat

    private var tiny: Bool { u < 0.9 }
    private var isPSA: Bool { company.uppercased() == "PSA" }
    private var isCGC: Bool { company.uppercased() == "CGC" }

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
                if isPSA { psaLabel } else if isCGC { cgcLabel } else { stockLabel }
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

    // MARK: CGC

    /// Like the website's CgcLabel (all sizes in u, the label is 91u wide): a black frame with
    /// the scales, CGC and CERTIFIED GUARANTY COMPANY across the top, and a silver panel with
    /// the card's lines, barcode and cert, then a fine rule and the grade. A Pristine 10 has a
    /// cream panel and a black badge with a gold 10 standing over its right edge.
    private var cgcLabel: some View {
        let frameShape = RoundedRectangle(cornerRadius: (tiny ? 1.4 : 1.6) * u, style: .continuous)
        let panelShape = RoundedRectangle(cornerRadius: (tiny ? 0.8 : 1) * u, style: .continuous)
        let panelFill = pristine
            ? LinearGradient(colors: [Color(hex: 0xF4EFDF), Color(hex: 0xE9E1C8)], startPoint: .top, endPoint: .bottom)
            : LinearGradient(colors: [Color(hex: 0xEDEEF0), Color(hex: 0xD6D8DB)], startPoint: .top, endPoint: .bottom)
        return ZStack(alignment: .top) {
            frameShape.fill(Color(hex: 0x101012))
            frameShape.strokeBorder(.white.opacity(0.06), lineWidth: 0.15 * u)
            if !tiny {
                cgcBand
                    .frame(height: 8 * u)
                    .frame(maxHeight: .infinity, alignment: .top)
            }
            panelShape
                .fill(panelFill)
                .overlay { if !tiny { cgcPanel } }
                .padding(.top, (tiny ? 4.5 : 8) * u)
                .padding(.leading, (tiny ? 1.6 : 2) * u)
                .padding(.trailing, (tiny ? 1.6 : (pristine ? 23.5 : 2.6)) * u)
                .padding(.bottom, (tiny ? 1.6 : 2.6) * u)
            if pristine && !tiny {
                pristineBadge
                    .frame(width: 24 * u, height: 25 * u)
                    .padding(.top, 8.6 * u)
                    .padding(.trailing, 4.5 * u)
                    .frame(maxWidth: .infinity, maxHeight: .infinity, alignment: .topTrailing)
            }
        }
        .clipShape(frameShape)
        .frame(height: (tiny ? 16 : 36) * u)
        .shadow(color: .black.opacity(0.35), radius: 0.75 * u, y: 0.5 * u)
    }

    private var cgcBand: some View {
        HStack(spacing: 3 * u) {
            HStack(spacing: 0.6 * u) {
                ScalesGlyph()
                    .stroke(Color.white, style: StrokeStyle(lineWidth: 0.25 * u, lineCap: .round, lineJoin: .round))
                    .frame(width: 4.9 * u, height: 3.3 * u)
                Text("CGC").font(.geist(6 * u, .medium)).tracking(-0.42 * u)
            }
            .fixedSize()
            Spacer(minLength: 0)
            Text("CERTIFIED GUARANTY COMPANY")
                .font(.geist(2.75 * u, .bold))
                .tracking(0.1 * u)
                .lineLimit(1)
                .minimumScaleFactor(0.5)
        }
        .foregroundStyle(Color.white)
        .padding(.horizontal, 2.6 * u)
    }

    private var certNumber: String {
        let saved = cert?.trimmingCharacters(in: .whitespaces) ?? ""
        return saved.isEmpty ? Slab.fallbackCert(product) : saved
    }

    private var cgcPanel: some View {
        let ink = Color(hex: 0x151515)
        return HStack(spacing: 0) {
            VStack(alignment: .leading, spacing: 0) {
                Spacer(minLength: 0)
                // Geist's line is 1.3 em; the negative spacing brings it to the website's 1.13.
                VStack(alignment: .leading, spacing: -0.63 * u) {
                    ForEach(Array(Slab.cgcLines(product).enumerated()), id: \.offset) { _, line in
                        Text(line).lineLimit(1).truncationMode(.tail)
                    }
                }
                .font(.geist(3.7 * u, .semibold))
                .tracking(-0.037 * u)
                Spacer(minLength: 0)
                HStack(alignment: .bottom, spacing: 2 * u) {
                    Barcode(u: u, pattern: Barcode.cgc).frame(width: 26 * u, height: 2.8 * u)
                    Spacer(minLength: 0)
                    Text(certNumber).font(.geist(2.6 * u, .semibold)).monospacedDigit().lineLimit(1)
                }
            }
            .padding(.leading, 2.4 * u)
            .padding(.trailing, (pristine ? 6 : 2) * u)
            .padding(.top, 1.4 * u)
            .padding(.bottom, 1.6 * u)
            .frame(maxWidth: .infinity, maxHeight: .infinity, alignment: .leading)
            if !pristine {
                Rectangle().fill(ink).frame(width: 0.3 * u, height: 15 * u)
                VStack(spacing: -3.3 * u) {
                    Text(Slab.descriptor(company: company, grade: grade))
                        .font(.geist(3.1 * u, .bold))
                        .tracking(0.03 * u)
                        .lineLimit(1)
                        .minimumScaleFactor(0.6)
                    Text(grade)
                        .font(.geist(15 * u, .bold))
                        .tracking(-0.75 * u)
                        .lineLimit(1)
                        .minimumScaleFactor(0.5)
                        .scaleEffect(x: 0.88, y: 1)
                }
                .frame(width: 22 * u)
            }
        }
        .foregroundStyle(ink)
    }

    private var pristineBadge: some View {
        let shape = RoundedRectangle(cornerRadius: 2.8 * u, style: .continuous)
        let goldTone = Color(hex: 0xC9A44C)
        let gold = LinearGradient(stops: [
            .init(color: Color(hex: 0xF6E6A8), location: 0.08),
            .init(color: goldTone, location: 0.55),
            .init(color: Color(hex: 0x8E6B23), location: 0.96),
        ], startPoint: .top, endPoint: .bottom)
        return shape
            .fill(LinearGradient(colors: [Color(hex: 0x19191B), Color(hex: 0x0A0A0B)], startPoint: .top, endPoint: .bottom))
            .overlay(shape.strokeBorder(goldTone.opacity(0.9), lineWidth: 0.25 * u))
            .overlay(
                RoundedRectangle(cornerRadius: 2.2 * u, style: .continuous)
                    .strokeBorder(goldTone.opacity(0.22), lineWidth: 0.15 * u)
                    .padding(0.6 * u)
            )
            .overlay(alignment: .top) {
                VStack(spacing: -4.6 * u) {
                    Text("PRISTINE")
                        .font(.geist(2.9 * u, .bold))
                        .tracking(0.29 * u)
                        .lineLimit(1)
                        .fixedSize()
                        .foregroundStyle(gold)
                    Text("10")
                        .font(.geist(20 * u, .bold))
                        .tracking(-1.2 * u)
                        .lineLimit(1)
                        .fixedSize()
                        .foregroundStyle(gold)
                        .shadow(color: .black.opacity(0.6), radius: 0.3 * u, y: 0.25 * u)
                        .scaleEffect(x: 0.84, y: 1)
                }
                .padding(.top, 1.37 * u)
            }
            .shadow(color: .black.opacity(0.45), radius: 1 * u, y: 0.4 * u)
    }

    // MARK: BGS, SGC and the rest

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

/// The balance scales in front of the CGC wordmark (the website's ScalesGlyph, a 24 × 16 drawing).
private struct ScalesGlyph: Shape {
    func path(in rect: CGRect) -> Path {
        let sx = rect.width / 24
        let sy = rect.height / 16
        func p(_ x: CGFloat, _ y: CGFloat) -> CGPoint { CGPoint(x: rect.minX + x * sx, y: rect.minY + y * sy) }
        var path = Path()
        path.move(to: p(12, 2.2)); path.addLine(to: p(12, 14.6))
        path.move(to: p(8.2, 14.6)); path.addLine(to: p(15.8, 14.6))
        path.move(to: p(3.5, 3.6)); path.addLine(to: p(20.5, 3.6))
        for cx: CGFloat in [3.5, 20.5] {
            path.move(to: p(cx, 3.6)); path.addLine(to: p(cx - 2.5, 9.6))
            path.move(to: p(cx, 3.6)); path.addLine(to: p(cx + 2.5, 9.6))
            // The pan.
            path.move(to: p(cx - 2.7, 9.6))
            path.addLine(to: p(cx + 2.7, 9.6))
            path.addQuadCurve(to: p(cx, 12.4), control: p(cx + 2.1, 12.4))
            path.addQuadCurve(to: p(cx - 2.7, 9.6), control: p(cx - 2.1, 12.4))
            path.closeSubpath()
        }
        path.addEllipse(in: CGRect(x: rect.minX + 11.4 * sx, y: rect.minY + 1.0 * sy, width: 1.2 * sx, height: 1.2 * sy))
        return path
    }
}

/// A printed barcode: thin and thick bars on a repeating pattern.
private struct Barcode: View {
    var u: CGFloat
    /// Bar widths and gaps in units of u, like the website's repeating patterns.
    var pattern: [(CGFloat, Bool)] = Barcode.standard

    static let standard: [(CGFloat, Bool)] = [(0.3, true), (0.3, false), (0.6, true), (0.3, false), (0.2, true), (0.6, false)]
    /// CGC's, a little busier.
    static let cgc: [(CGFloat, Bool)] = [(0.25, true), (0.25, false), (0.6, true), (0.25, false), (0.2, true), (0.5, false), (0.55, true), (0.2, false), (0.2, true), (0.6, false)]

    var body: some View {
        Canvas { ctx, size in
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
        // A CGC 10 is "GEM MINT"; its Pristine 10 is marked per slab and has its own badge.
        case 10...: return company.uppercased() == "CGC" ? "GEM MINT" : "PRISTINE"
        case 9.5...: return "GEM MINT"
        case 9...: return "MINT"
        case 8.5...: return "NM-MT+"
        case 8...: return "NM-MT"
        default: return "NEAR MINT"
        }
    }

    /// Only a CGC 10 can be marked Pristine.
    static func isCGCTen(company: String, grade: String) -> Bool {
        company.uppercased() == "CGC" && (Double(grade) ?? 0) >= 10
    }

    /// The lines printed on a CGC label: the card, the game, "Set - number", then the rarity
    /// (the website's cgcLabelLines).
    static func cgcLines(_ p: Product?) -> [String] {
        let set = p?.setName.flatMap { $0.isEmpty ? nil : $0 }
        let num = p?.number.flatMap { $0.isEmpty ? nil : $0 }
        let third: String?
        if let set, let num {
            third = "\(set) - \(num)"
        } else if let set {
            third = set
        } else if let num {
            third = "#\(num)"
        } else {
            third = nil
        }
        return [p?.name ?? "Card", "Pokémon", third, p?.rarity].compactMap { $0 }.filter { !$0.isEmpty }
    }

    /// A stand-in cert number for a slab with none saved: 10 digits that stay the same for the
    /// card (FNV-1a of name|set|number, ending in 001 like CGC's). Matches the website's fallbackCert.
    static func fallbackCert(_ p: Product?) -> String {
        let text = [p?.name ?? "Card", p?.setName ?? "", p?.number ?? ""].joined(separator: "|")
        var h: UInt32 = 2_166_136_261
        for c in text.utf16 { h = (h ^ UInt32(c)) &* 16_777_619 }
        return "\(h % 9_000_000 + 1_000_000)001"
    }
}
