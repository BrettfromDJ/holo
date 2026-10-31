import SwiftUI

/// A number whose digits roll like an odometer: each digit is its own little column of 0–9 that
/// slides (one offset animation, with a spring) to the new digit when the value changes.
/// Everything else in the text ($, commas, the point) stays still. It keeps the font, tracking
/// and color it's given. Under Reduce Motion the number just changes.
struct OdometerText: View {
    var value: Double
    var format: (Double) -> String

    @Environment(\.accessibilityReduceMotion) private var reduceMotion

    /// One character of the text, keyed by its place from the right, so the ones stay the ones
    /// when the number gains a digit.
    private struct Slot: Identifiable {
        var id: Int
        var char: Character
    }

    var body: some View {
        let text = format(value)
        let chars = Array(text)
        let slots = chars.enumerated().map { i, c in Slot(id: chars.count - 1 - i, char: c) }
        HStack(spacing: 0) {
            ForEach(slots) { slot in
                if let d = Self.digit(slot.char) {
                    OdometerDigit(digit: d, animation: reduceMotion ? nil : Animation.spring(response: 0.55, dampingFraction: 0.82).delay(Double(min(slot.id, 8)) * 0.035))
                } else {
                    Text(String(slot.char))
                }
            }
        }
        .animation(reduceMotion ? nil : Animation.snappy, value: chars.count)
        .accessibilityElement(children: .ignore)
        .accessibilityLabel(text)
    }

    private static func digit(_ c: Character) -> Int? {
        guard c.isASCII, let n = c.wholeNumberValue, (0...9).contains(n) else { return nil }
        return n
    }
}

/// One rolling digit: an invisible "0" sets the size (and the baseline), and a column of 0–9
/// behind a mask slides so the right digit shows.
private struct OdometerDigit: View {
    var digit: Int
    var animation: Animation?

    var body: some View {
        Text("0").opacity(0)
            .overlay(alignment: .topLeading) {
                GeometryReader { geo in
                    VStack(spacing: 0) {
                        ForEach(0..<10, id: \.self) { n in
                            Text(String(n)).frame(width: geo.size.width, height: geo.size.height)
                        }
                    }
                    .offset(y: -CGFloat(digit) * geo.size.height)
                    .animation(animation, value: digit)
                }
            }
            // Clip above and below only, so a slightly wider glyph never loses its sides.
            .mask { Rectangle().padding(.horizontal, -12) }
    }
}
