import CoreImage
import UIKit

/// The small marks that tell old cards' prints apart, read from the flattened card photo:
/// the 1st Edition stamp (a black circle at the left edge, just under the picture box) and the
/// Celebrations Classic Collection reprints' 25th anniversary Pikachu (big and yellow, out of the
/// picture box's bottom-right corner). Measured on reference scans and real photos (Nov 2026):
/// the stamp patch is 6–14% dark with it and ≤1% without; the Pikachu patch is 48–64% Pikachu
/// yellow on reprints and ≤27% on originals, with the card framed up to 3% off. In between it
/// says nothing (nil) and the scan stays on the everyday print.
enum PrintMarks {
    struct Found: Equatable {
        /// True: the 1st Edition stamp is there. False: clearly not. Nil: can't tell (glare, sleeve).
        var firstEdition: Bool?
        /// True: the Celebrations 25th anniversary Pikachu is there (a Classic Collection reprint).
        var celebrations: Bool?
    }

    /// Where the marks sit, as fractions of the card (from its top-left).
    static let stampBox = CGRect(x: 0.035, y: 0.525, width: 0.085, height: 0.065)
    static let pikachuBox = CGRect(x: 0.79, y: 0.45, width: 0.16, height: 0.09)

    /// Reads both marks from a photo of the card alone (the scanner's flattened crop). A few
    /// milliseconds: the card is shrunk to 120 × 168 first.
    static func read(_ jpeg: Data) -> Found? {
        guard let image = CIImage(data: jpeg, options: [.applyOrientationProperty: true]),
              image.extent.width > 0, image.extent.height > 0,
              let cg = CIContext(options: [.useSoftwareRenderer: false]).createCGImage(image, from: image.extent) else { return nil }
        return read(cg)
    }

    static func read(_ cg: CGImage) -> Found? {
        let w = 120, h = 168
        var px = [UInt8](repeating: 0, count: w * h * 4)
        let drawn: Bool = px.withUnsafeMutableBytes { buf in
            guard let ctx = CGContext(data: buf.baseAddress, width: w, height: h, bitsPerComponent: 8, bytesPerRow: w * 4,
                                      space: CGColorSpaceCreateDeviceRGB(), bitmapInfo: CGImageAlphaInfo.premultipliedLast.rawValue) else { return false }
            ctx.interpolationQuality = .medium
            ctx.draw(cg, in: CGRect(x: 0, y: 0, width: w, height: h))
            return true
        }
        guard drawn else { return nil }
        // The bitmap's first row is the card's top.
        func pixels(_ box: CGRect) -> [(r: Double, g: Double, b: Double)] {
            let x0 = Int(box.minX * Double(w)), x1 = Int(box.maxX * Double(w))
            let y0 = Int(box.minY * Double(h)), y1 = Int(box.maxY * Double(h))
            var out: [(Double, Double, Double)] = []
            for y in max(0, y0)..<min(h, y1) {
                for x in max(0, x0)..<min(w, x1) {
                    let i = (y * w + x) * 4
                    out.append((Double(px[i]) / 255, Double(px[i + 1]) / 255, Double(px[i + 2]) / 255))
                }
            }
            return out
        }
        return Found(firstEdition: stamp(pixels(stampBox)), celebrations: pikachu(pixels(pikachuBox)))
    }

    /// The stamp: a share of pixels far darker than the patch around them.
    static func stamp(_ px: [(r: Double, g: Double, b: Double)]) -> Bool? {
        guard !px.isEmpty else { return nil }
        let lum = px.map { 0.3 * $0.r + 0.59 * $0.g + 0.11 * $0.b }.sorted()
        let median = lum[lum.count / 2]
        // A dark patch (shadow, a dark card) can't show a black stamp.
        guard median > 0.25 else { return nil }
        let dark = Double(lum.filter { $0 < median * 0.45 }.count) / Double(lum.count)
        return dark >= 0.04 ? true : dark <= 0.015 ? false : nil
    }

    /// The Pikachu: a share of strong, saturated yellow.
    static func pikachu(_ px: [(r: Double, g: Double, b: Double)]) -> Bool? {
        guard !px.isEmpty else { return nil }
        let yellow = px.filter { p in
            let mx = max(p.r, p.g, p.b), mn = min(p.r, p.g, p.b)
            guard mx > 0.6, mx - mn > 0.6 * mx else { return false }
            // Hue 40°–61°: yellow, not the gold frame's orange or a green card's green.
            var hue: Double
            if mx == p.r { hue = (p.g - p.b) / (mx - mn) } else if mx == p.g { hue = 2 + (p.b - p.r) / (mx - mn) } else { hue = 4 + (p.r - p.g) / (mx - mn) }
            hue *= 60
            if hue < 0 { hue += 360 }
            return hue > 40 && hue < 61
        }.count
        let share = Double(yellow) / Double(px.count)
        return share >= 0.38 ? true : share <= 0.25 ? false : nil
    }
}
